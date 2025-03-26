pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "fhevm/lib/TFHE.sol";
import "fhevm/config/ZamaFHEVMConfig.sol";
import "fhevm/gateway/GatewayCaller.sol";
import { IConfidentialERC20 } from "fhevm-contracts/contracts/token/ERC20/IConfidentialERC20.sol";
import { IAaveConfidentialityAdapter } from "./IAaveConfidentialityAdapter.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IScaledBalanceToken } from "@aave/core-v3/contracts/interfaces/IScaledBalanceToken.sol";

contract AaveConfidentialityAdapter is
    SepoliaZamaFHEVMConfig,
    Ownable2Step,
    GatewayCaller,
    ReentrancyGuardTransient,
    IAaveConfidentialityAdapter
{
    uint8 public REQUEST_THRESHOLD = 3;
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
        uint256 interestRateMode;
        uint16 referralCode;
    }

    struct RepayRequestData {
        address sender;
        address asset;
        euint64 amount;
        uint256 interestRateMode;
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
    mapping(uint256 requestId => RequestData[]) public requestIdToRequestData;
    mapping(address account => euint64 amount) public scaledBalances;

    modifier onlyCToken(address asset) {
        require(cTokenAddressToTokenAddress[asset] != address(0), "AaveConfidentialityAdapter: invalid asset");
        _;
    }

    constructor(address aavePoolContract, address[] tokens, address[] cTokens) Ownable(msg.sender) {
        setAavePoolContract(aavePoolContract);

        require(tokens.length == cTokens.length, "AaveConfidentialityAdapter: invalid input");

        for (uint256 i = 0; i < tokens.length; i++) {
            setCTokenAddress(tokens[i], cTokens[i]);
        }
    }

    function supplyRequest(address asset, euint64 amount, uint16 referralCode) public {
        address cToken = tokenAddressToCTokenAddress[asset];
        require(cToken != address(0), "AaveConfidentialityAdapter: invalid asset");
        require(
            IConfidentialERC20(cToken).transferFrom(msg.sender, address(this), amount),
            "AaveConfidentialityAdapter: transfer failed"
        );
        supplyRequests.push(SupplyRequestData(asset, amount, referralCode));
        emit SupplyRequested(asset, msg.sender, msg.sender, amount, referralCode);

        SupplyRequestData[] memory requests = new SupplyRequestData[](REQUEST_THRESHOLD);

        for (uint256 i = 0; i < REQUEST_THRESHOLD; i++) {
            SupplyRequestData memory srd = supplyRequests[i];
            if (srd.asset == asset) {
                requests[i] = srd;
            }
        }

        if (requests.length > REQUEST_THRESHOLD) {
            _processSupplyRequests(requests);
        }
    }

    function supplyRequest(address asset, einput amount, uint16 referralCode, bytes calldata inputProof) public {
        supplyRequest(asset, TFHE.asEuint64(amount, inputProof), referralCode);
    }

    function withdrawRequest(address asset, euint64 amount, address to) public {
        // check if the user has enough supplied balance
        euint64 suppliedBalance = getSuppliedBalance(msg.sender, asset);
        amount = TFHE.select(TFHE.le(amount, suppliedBalance), amount, TFHE.asEuint64(0));

        withdrawRequests.push(WithdrawRequestData(asset, amount, to));
        emit WithdrawRequested(asset, msg.sender, to, amount);

        WithdrawRequestData[] memory requests = new WithdrawRequestData[](REQUEST_THRESHOLD);

        for (uint256 i = 0; i < REQUEST_THRESHOLD; i++) {
            WithdrawRequestData memory wrd = withdrawRequests[i];
            if (wrd.asset == asset) {
                requests[i] = wrd;
            }
        }

        if (requests.length > REQUEST_THRESHOLD) {
            _processWithdrawRequests(requests);
        }
    }

    function withdrawRequest(address asset, einput amount, address to, bytes calldata inputProof) public {
        withdrawRequest(asset, TFHE.asEuint64(amount, inputProof), to);
    }

    function borrowRequest(address asset, euint64 amount, uint256 interestRateMode, uint16 referralCode) public {
        borrowRequests.push(BorrowRequestData(asset, amount, interestRateMode, referralCode));
        emit BorrowRequested(asset, msg.sender, msg.sender, amount, interestRateMode, 0, referralCode);

        BorrowRequestData[] memory requests = new BorrowRequestData[](REQUEST_THRESHOLD);

        for (uint256 i = 0; i < REQUEST_THRESHOLD; i++) {
            BorrowRequestData memory brd = borrowRequests[i];
            if (brd.asset == asset) {
                requests[i] = brd;
            }
        }

        if (requests.length > REQUEST_THRESHOLD) {
            _processBorrowRequests(requests);
        }
    }

    function borrowRequest(
        address asset,
        einput amount,
        uint256 interestRateMode,
        uint16 referralCode,
        bytes calldata inputProof
    ) public {
        borrowRequest(asset, TFHE.asEuint64(amount, inputProof), interestRateMode, referralCode);
    }

    function repayRequest(address asset, euint64 amount, uint256 interestRateMode) public {
        repayRequests.push(RepayRequestData(asset, amount, interestRateMode));
        emit RepayRequested(asset, msg.sender, msg.sender, amount, false);

        if (repayRequests.length > REQUEST_THRESHOLD) {
            _processRepayRequests();
        }
    }

    function repayRequest(address asset, einput amount, uint256 interestRateMode, bytes calldata inputProof) public {
        repayRequest(asset, TFHE.asEuint64(amount, inputProof), interestRateMode);
    }

    function setCTokenAddress(address token, address cToken) public onlyOwner {
        tokenAddressToCTokenAddress[token] = cToken;
        cTokenAddressToTokenAddress[cToken] = token;
    }

    function setAavePoolContract(address aavePoolContract) public onlyOwner {
        aavePool = IPool(aavePoolContract);
    }

    function callbackSupplyRequest(uint256 requestId, uint256 amount) public virtual nonReentrant onlyGateway {
        SupplyRequestData[] memory requests = requestIdToSupplyRequests[requestId];
        address asset = requests[0].asset;
        address cToken = tokenAddressToCTokenAddress[asset];
        IConfidentialERC20(cToken).unwrap(amount);
    }

    function callbackWithdrawRequest(uint256 requestId, uint256 amount) public virtual nonReentrant onlyGateway {
        WithdrawRequestData[] memory requests = requestIdToWithdrawRequests[requestId];
        address asset = requests[0].asset;
        address cToken = tokenAddressToCTokenAddress[asset];

        aavePool.withdraw(asset, amount, address(this));

        IERC20(asset).approve(cToken, amount);
        IConfidentialERC20(cToken).wrap(amount);

        for (uint256 i = 0; i < requests.length; i++) {
            address to = requests[i].to;
            IConfidentialERC20(cToken).transfer(to, requests[i].amount);
        }

        delete requestIdToWithdrawRequests[requestId];
        delete requestIdToRequestData[requestId];
    }

    function onUnwrapComplete(uint256 requestId, uint256 amount) public nonReentrant onlyCToken {
        RequestData[] memory requestData = requestIdToRequestData[requestId];

        if (requestData[0].requestType == RequestType.SUPPLY) {
            SupplyRequestData[] memory _supplyRequests = requestIdToSupplyRequests[requestId];
            address asset = _supplyRequests[0].asset; // every asset address is the same for given request

            IERC20(asset).approve(address(aavePool), amount);

            address aToken = aavePool.getReserveData(asset).aTokenAddress;
            uint256 beforeScaledBalance = IScaledBalanceToken(aToken).scaledBalanceOf(address(this));
            aavePool.supply(asset, amount, address(this));
            uint256 afterScaledBalance = IScaledBalanceToken(aToken).scaledBalanceOf(address(this));
            uint256 difference = afterScaledBalance - beforeScaledBalance;
            uint256 multiplier = difference / amount;

            for (uint256 i = 0; i < _supplyRequests.length; i++) {
                euint64 accountScaledBalance = TFHE.mul(_supplyRequests[i].amount, multiplier);
                scaledBalances[_supplyRequests[i].sender] = TFHE.add(
                    scaledBalances[_supplyRequests[i].sender],
                    accountScaledBalance
                );
            }
        }

        delete requestIdToSupplyRequests[requestId];
        delete requestIdToRequestData[requestId];
    }

    function _processSupplyRequests(SupplyRequestData[] memory srd) internal {
        uint256[] memory cts = new uint256[](1);
        euint64 totalAmount = TFHE.asEuint64(0);
        for (uint256 i = 0; i < srd.length; i++) {
            SupplyRequestData memory request = srd[i];
            totalAmount = TFHE.add(totalAmount, request.amount);
        }
        cts[0] = Gateway.toUint256(totalAmount);
        uint256 requestId = Gateway.requestDecryption(
            cts,
            this.callbackSupplyRequest.selector,
            0,
            block.timestamp + 100,
            false
        );
        requestIdToSupplyRequests[requestId] = srd;
        requestIdToRequestData[requestId] = RequestData(RequestType.SUPPLY, abi.encode(srd));
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

        requestIdToWithdrawRequests[requestId] = wrd;
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

        requestIdToBorrowRequests[requestId] = brd;
        requestIdToRequestData[requestId] = RequestData(RequestType.BORROW, abi.encode(brd));
    }

    function callbackBorrowRequest(uint256 requestId, uint256 amount) public virtual nonReentrant onlyGateway {
        BorrowRequestData[] memory requests = requestIdToBorrowRequests[requestId];
        address asset = requests[0].asset;
        uint256 interestRateMode = requests[0].interestRateMode;
        uint16 referralCode = requests[0].referralCode;

        aavePool.borrow(asset, amount, interestRateMode, referralCode, address(this));

        address cToken = tokenAddressToCTokenAddress[asset];
        IERC20(asset).approve(cToken, amount);
        IConfidentialERC20(cToken).wrap(amount);

        for (uint256 i = 0; i < requests.length; i++) {
            address to = requests[i].to;
            IConfidentialERC20(cToken).transfer(to, requests[i].amount);
        }

        delete requestIdToBorrowRequests[requestId];
        delete requestIdToRequestData[requestId];
    }

    function getSuppliedBalance(address user, address asset) public view returns (euint64) {
        euint64 scaledBalance = scaledBalances[user];
        uint256 reserveNormalizedIncome = aavePool.getReserveNormalizedIncome(asset);
        return TFHE.mul(scaledBalance, reserveNormalizedIncome);
    }
}
