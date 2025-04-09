pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "fhevm/lib/TFHE.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { SepoliaZamaGatewayConfig } from "fhevm/config/ZamaGatewayConfig.sol";
import "fhevm/gateway/GatewayCaller.sol";
import { ConfidentialERC20Wrapped } from "../../zama/ConfidentialERC20Wrapped.sol";
import { IAaveConfidentialityAdapter } from "./IAaveConfidentialityAdapter.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IScaledBalanceToken } from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

contract AaveConfidentialityAdapter is
    SepoliaZamaFHEVMConfig,
    SepoliaZamaGatewayConfig,
    GatewayCaller,
    Ownable2Step,
    IAaveConfidentialityAdapter,
    ReentrancyGuardTransient
{
    uint8 public REQUEST_THRESHOLD = 2;
    IPool public aavePool;

    enum RequestType {
        SUPPLY,
        WITHDRAW,
        BORROW,
        REPAY
    }

    struct RequestData {
        RequestType requestType;
        bytes data;
    }

    struct SupplyRequestData {
        address sender;
        address asset;
        euint64 amount;
        uint16 referralCode;
    }

    struct WithdrawRequestData {
        address sender;
        address asset;
        euint64 amount;
        address to;
    }

    struct BorrowRequestData {
        address sender;
        address asset;
        euint64 amount;
        DataTypes.InterestRateMode interestRateMode;
        uint16 referralCode;
    }

    struct RepayRequestData {
        address sender;
        address asset;
        euint64 amount;
        DataTypes.InterestRateMode interestRateMode;
    }

    SupplyRequestData[] public supplyRequests;
    WithdrawRequestData[] public withdrawRequests;
    BorrowRequestData[] public borrowRequests;
    RepayRequestData[] public repayRequests;

    mapping(address token => address cToken) public tokenAddressToCTokenAddress;
    mapping(address cToken => address token) public cTokenAddressToTokenAddress;
    mapping(uint256 requestId => SupplyRequestData[]) public requestIdToSupplyRequests;
    mapping(uint256 requestId => WithdrawRequestData[]) public requestIdToWithdrawRequests;
    mapping(uint256 requestId => BorrowRequestData[]) public requestIdToBorrowRequests;
    mapping(uint256 requestId => RepayRequestData[]) public requestIdToRepayRequests;
    mapping(uint256 requestId => RequestData) public requestIdToRequestData;
    mapping(address account => euint64 amount) public scaledBalances;

    modifier onlyCToken() {
        address[] memory aaveSupportedTokens = aavePool.getReservesList();
        bool isCToken = false;
        for (uint256 i = 0; i < aaveSupportedTokens.length; i++) {
            if (tokenAddressToCTokenAddress[aaveSupportedTokens[i]] == msg.sender) {
                isCToken = true;
                break;
            }
        }
        require(isCToken, "AaveConfidentialityAdapter: caller is not a cToken");
        _;
    }

    constructor(address aavePoolContract, address[] memory tokens, address[] memory cTokens) Ownable(msg.sender) {
        setAavePoolContract(aavePoolContract);

        require(tokens.length == cTokens.length, "AaveConfidentialityAdapter: invalid input");

        for (uint256 i = 0; i < tokens.length; i++) {
            setCTokenAddress(tokens[i], cTokens[i]);
        }
    }

    function supplyRequest(address asset, euint64 amount, uint16 referralCode) public {
        address cToken = tokenAddressToCTokenAddress[asset];
        require(cToken != address(0), "AaveConfidentialityAdapter: invalid asset");

        TFHE.allow(amount, cToken);
        require(
            ConfidentialERC20Wrapped(cToken).transferFrom(msg.sender, address(this), amount),
            "AaveConfidentialityAdapter: transfer failed"
        );
        supplyRequests.push(SupplyRequestData(msg.sender, asset, amount, referralCode));
        TFHE.allow(supplyRequests[supplyRequests.length - 1].amount, msg.sender);
        TFHE.allowThis(supplyRequests[supplyRequests.length - 1].amount);

        // initialize scaledBalance
        if (!TFHE.isInitialized(scaledBalances[msg.sender])) {
            scaledBalances[msg.sender] = TFHE.asEuint64(0);
            TFHE.allowThis(scaledBalances[msg.sender]);
        }

        emit SupplyRequested(asset, msg.sender, msg.sender, amount, referralCode);

        if (supplyRequests.length < REQUEST_THRESHOLD) {
            return;
        }

        SupplyRequestData[] memory requests = new SupplyRequestData[](REQUEST_THRESHOLD);

        for (uint256 i = 0; i < REQUEST_THRESHOLD; i++) {
            SupplyRequestData memory srd = supplyRequests[i];
            if (srd.asset == asset) {
                requests[i] = srd;
                TFHE.allow(requests[i].amount, msg.sender);
                TFHE.allowThis(requests[i].amount);
            }
        }

        TFHE.allowThis(ConfidentialERC20Wrapped(cToken).balanceOf(address(this)));
        TFHE.allow(ConfidentialERC20Wrapped(cToken).balanceOf(address(this)), msg.sender);

        if (requests.length >= REQUEST_THRESHOLD) {
            _processSupplyRequests(requests);
        }
    }

    function supplyRequest(address asset, einput amount, uint16 referralCode, bytes calldata inputProof) public {
        supplyRequest(asset, TFHE.asEuint64(amount, inputProof), referralCode);
    }

    function withdrawRequest(address asset, euint64 amount, address to) public {
        // @todo: check if the user has enough supplied balance
        euint64 suppliedBalance = TFHE.asEuint64(type(uint64).max);
        amount = TFHE.select(TFHE.le(amount, suppliedBalance), amount, TFHE.asEuint64(0));

        withdrawRequests.push(WithdrawRequestData(msg.sender, asset, amount, to));
        emit WithdrawRequested(asset, msg.sender, to, amount);

        if (withdrawRequests.length < REQUEST_THRESHOLD) {
            return;
        }

        WithdrawRequestData[] memory requests = new WithdrawRequestData[](REQUEST_THRESHOLD);

        for (uint256 i = 0; i < REQUEST_THRESHOLD; i++) {
            WithdrawRequestData memory wrd = withdrawRequests[i];
            if (wrd.asset == asset) {
                requests[i] = wrd;
            }
        }

        if (requests.length >= REQUEST_THRESHOLD) {
            _processWithdrawRequests(requests);
        }
    }

    function withdrawRequest(address asset, einput amount, address to, bytes calldata inputProof) public {
        withdrawRequest(asset, TFHE.asEuint64(amount, inputProof), to);
    }

    function borrowRequest(
        address asset,
        euint64 amount,
        DataTypes.InterestRateMode interestRateMode,
        uint16 referralCode
    ) public {
        borrowRequests.push(BorrowRequestData(msg.sender, asset, amount, interestRateMode, referralCode));
        emit BorrowRequested(asset, msg.sender, msg.sender, amount, interestRateMode, 0, referralCode);

        if (borrowRequests.length < REQUEST_THRESHOLD) {
            return;
        }

        BorrowRequestData[] memory requests = new BorrowRequestData[](REQUEST_THRESHOLD);

        for (uint256 i = 0; i < REQUEST_THRESHOLD; i++) {
            BorrowRequestData memory brd = borrowRequests[i];
            if (brd.asset == asset) {
                requests[i] = brd;
            }
        }

        if (requests.length >= REQUEST_THRESHOLD) {
            _processBorrowRequests(requests);
        }
    }

    function borrowRequest(
        address asset,
        einput amount,
        DataTypes.InterestRateMode interestRateMode,
        uint16 referralCode,
        bytes calldata inputProof
    ) public {
        borrowRequest(asset, TFHE.asEuint64(amount, inputProof), interestRateMode, referralCode);
    }

    function repayRequest(address asset, euint64 amount, DataTypes.InterestRateMode interestRateMode) public {
        repayRequests.push(RepayRequestData(msg.sender, asset, amount, interestRateMode));
        emit RepayRequested(asset, msg.sender, msg.sender, amount, false);

        if (repayRequests.length < REQUEST_THRESHOLD) {
            return;
        }

        RepayRequestData[] memory requests = new RepayRequestData[](REQUEST_THRESHOLD);

        for (uint256 i = 0; i < REQUEST_THRESHOLD; i++) {
            RepayRequestData memory rrd = repayRequests[i];
            if (rrd.asset == asset) {
                requests[i] = rrd;
            }
        }

        if (repayRequests.length >= REQUEST_THRESHOLD) {
            _processRepayRequests(requests);
        }
    }

    function repayRequest(
        address asset,
        einput amount,
        DataTypes.InterestRateMode interestRateMode,
        bytes calldata inputProof
    ) public {
        repayRequest(asset, TFHE.asEuint64(amount, inputProof), interestRateMode);
    }

    function setCTokenAddress(address token, address cToken) public onlyOwner {
        tokenAddressToCTokenAddress[token] = cToken;
        cTokenAddressToTokenAddress[cToken] = token;
    }

    function setAavePoolContract(address aavePoolContract) public onlyOwner {
        aavePool = IPool(aavePoolContract);
    }

    function callbackSupplyRequest(uint256 requestId, uint64 amount) public virtual nonReentrant onlyGateway {
        SupplyRequestData[] memory requests = requestIdToSupplyRequests[requestId];
        address asset = requests[0].asset;
        address cToken = tokenAddressToCTokenAddress[asset];
        ConfidentialERC20Wrapped(cToken).unwrap(amount);

        IERC20(asset).approve(address(aavePool), amount);

        emit SupplyCallback(asset, amount);
    }

    function callbackWithdrawRequest(uint256 requestId, uint256 amount) public virtual nonReentrant onlyGateway {
        WithdrawRequestData[] memory requests = requestIdToWithdrawRequests[requestId];
        address asset = requests[0].asset;
        address cToken = tokenAddressToCTokenAddress[asset];

        aavePool.withdraw(asset, amount, address(this));

        IERC20(asset).approve(cToken, amount);
        ConfidentialERC20Wrapped(cToken).wrap(amount);

        for (uint256 i = 0; i < requests.length; i++) {
            address to = requests[i].to;
            ConfidentialERC20Wrapped(cToken).transfer(to, requests[i].amount);
        }

        delete requestIdToWithdrawRequests[requestId];
        delete requestIdToRequestData[requestId];
    }

    function callbackBorrowRequest(uint256 requestId, uint256 amount) public virtual nonReentrant onlyGateway {
        BorrowRequestData[] memory requests = requestIdToBorrowRequests[requestId];
        address asset = requests[0].asset;
        DataTypes.InterestRateMode interestRateMode = requests[0].interestRateMode;
        uint16 referralCode = requests[0].referralCode;

        aavePool.borrow(asset, amount, uint256(interestRateMode), referralCode, address(this));

        address cToken = tokenAddressToCTokenAddress[asset];
        IERC20(asset).approve(cToken, amount);
        ConfidentialERC20Wrapped(cToken).wrap(amount);

        for (uint256 i = 0; i < requests.length; i++) {
            address to = requests[i].sender;
            ConfidentialERC20Wrapped(cToken).transfer(to, requests[i].amount);
        }

        delete requestIdToBorrowRequests[requestId];
        delete requestIdToRequestData[requestId];
    }

    function callbackRepayRequest(uint256 requestId, uint256 amount) public virtual nonReentrant onlyGateway {
        RepayRequestData[] memory requests = requestIdToRepayRequests[requestId];
        address asset = requests[0].asset;
        address cToken = tokenAddressToCTokenAddress[asset];

        // Unwrap the confidential tokens
        ConfidentialERC20Wrapped(cToken).unwrap(uint64(amount));

        // Approve and repay to Aave pool
        IERC20(asset).approve(address(aavePool), amount);
        aavePool.repay(asset, amount, uint256(requests[0].interestRateMode), address(this));

        delete requestIdToRepayRequests[requestId];
        delete requestIdToRequestData[requestId];
    }

    function onUnwrapComplete(uint256 requestId, uint256 amount) public nonReentrant onlyCToken {
        // @todo: requestId - 1 might not work every time. Find a better fix.
        RequestData memory requestData = requestIdToRequestData[requestId - 1];

        if (requestData.requestType == RequestType.SUPPLY) {
            SupplyRequestData[] storage _supplyRequests = requestIdToSupplyRequests[requestId - 1];
            address asset = _supplyRequests[0].asset; // every asset address is the same for given request
            address aToken = aavePool.getReserveData(asset).aTokenAddress;
            // address cToken = tokenAddressToCTokenAddress[asset];
            uint256 beforeScaledBalance = IScaledBalanceToken(aToken).scaledBalanceOf(address(this));

            aavePool.supply(asset, amount, address(this), _supplyRequests[0].referralCode);

            uint256 afterScaledBalance = IScaledBalanceToken(aToken).scaledBalanceOf(address(this));
            uint256 difference = afterScaledBalance - beforeScaledBalance;
            uint256 multiplier = difference / (amount / (10 ** 6));

            // update scaled balances
            for (uint256 i = 0; i < _supplyRequests.length; i++) {
                euint64 newBalance = TFHE.add(
                    scaledBalances[_supplyRequests[i].sender],
                    TFHE.mul(_supplyRequests[i].amount, uint64(multiplier))
                );
                scaledBalances[_supplyRequests[i].sender] = newBalance;
                TFHE.allowThis(newBalance);
                // uncomment the line below when the gas limit is increased on Zama's side.
                // TFHE.allow(newBalance, _supplyRequests[i].sender);
            }
        }

        delete requestIdToSupplyRequests[requestId - 1];
        delete requestIdToRequestData[requestId - 1];
    }

    function test() public {
        TFHE.allow(scaledBalances[msg.sender], msg.sender);
    }

    function _processSupplyRequests(SupplyRequestData[] memory srd) internal {
        uint256[] memory cts = new uint256[](1);
        euint64 totalAmount = TFHE.asEuint64(0);

        for (uint256 i = 0; i < srd.length; i++) {
            totalAmount = TFHE.add(totalAmount, srd[i].amount);
        }

        cts[0] = Gateway.toUint256(totalAmount);
        uint256 requestId = Gateway.requestDecryption(
            cts,
            this.callbackSupplyRequest.selector,
            0,
            block.timestamp + 100,
            false
        );

        for (uint256 i = 0; i < srd.length; i++) {
            requestIdToSupplyRequests[requestId].push(srd[i]);
        }

        requestIdToRequestData[requestId] = RequestData(RequestType.SUPPLY, abi.encode(srd));

        // clean supplyRequests array
        for (uint256 i = 0; i < srd.length; i++) {
            supplyRequests.pop();
        }
    }

    function _processWithdrawRequests(WithdrawRequestData[] memory wrd) internal {
        uint256[] memory cts = new uint256[](1);
        euint64 totalAmount = TFHE.asEuint64(0);

        for (uint256 i = 0; i < wrd.length; i++) {
            WithdrawRequestData memory request = wrd[i];
            totalAmount = TFHE.add(totalAmount, request.amount);
        }

        cts[0] = Gateway.toUint256(totalAmount);
        uint256 requestId = Gateway.requestDecryption(
            cts,
            this.callbackWithdrawRequest.selector,
            0,
            block.timestamp + 100,
            false
        );

        for (uint256 i = 0; i < wrd.length; i++) {
            requestIdToWithdrawRequests[requestId].push(wrd[i]);
        }

        requestIdToRequestData[requestId] = RequestData(RequestType.WITHDRAW, abi.encode(wrd));
    }

    function _processBorrowRequests(BorrowRequestData[] memory brd) internal {
        uint256[] memory cts = new uint256[](1);
        euint64 totalAmount = TFHE.asEuint64(0);

        // Calculate total amount to borrow
        for (uint256 i = 0; i < brd.length; i++) {
            BorrowRequestData memory request = brd[i];
            totalAmount = TFHE.add(totalAmount, request.amount);
        }

        cts[0] = Gateway.toUint256(totalAmount);
        uint256 requestId = Gateway.requestDecryption(
            cts,
            this.callbackBorrowRequest.selector,
            0,
            block.timestamp + 100,
            false
        );

        for (uint256 i = 0; i < brd.length; i++) {
            requestIdToBorrowRequests[requestId].push(brd[i]);
        }

        requestIdToRequestData[requestId] = RequestData(RequestType.BORROW, abi.encode(brd));
    }

    function _processRepayRequests(RepayRequestData[] memory rrd) internal {
        uint256[] memory cts = new uint256[](1);
        euint64 totalAmount = TFHE.asEuint64(0);

        // Calculate total amount to repay
        for (uint256 i = 0; i < rrd.length; i++) {
            RepayRequestData memory request = rrd[i];
            totalAmount = TFHE.add(totalAmount, request.amount);
        }

        cts[0] = Gateway.toUint256(totalAmount);
        uint256 requestId = Gateway.requestDecryption(
            cts,
            this.callbackRepayRequest.selector,
            0,
            block.timestamp + 100,
            false
        );

        for (uint256 i = 0; i < rrd.length; i++) {
            requestIdToRepayRequests[requestId].push(rrd[i]);
        }

        requestIdToRequestData[requestId] = RequestData(RequestType.REPAY, abi.encode(rrd));
    }

    //@todo: can't make this function view because it modifies the state?
    /*     function getSuppliedBalance(address user, address asset) public view returns (euint64) {
        euint64 scaledBalance = scaledBalances[user];
        uint256 reserveNormalizedIncome = aavePool.getReserveNormalizedIncome(asset);
        return TFHE.asEuint64(TFHE.div(TFHE.mul(TFHE.asEuint256(scaledBalance), reserveNormalizedIncome), 1e27)); // ray format
    } */

    receive() external payable {}
}
