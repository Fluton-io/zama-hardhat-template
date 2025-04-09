pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "fhevm/lib/TFHE.sol";
import "fhevm/config/ZamaFHEVMConfig.sol";
import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import { IConfidentialityAdapter } from "../IConfidentialityAdapter.sol";

interface IAaveConfidentialityAdapter is IConfidentialityAdapter {
    event SupplyRequested(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        euint64 amount,
        uint16 indexed referralCode
    );

    event WithdrawRequested(address indexed reserve, address indexed user, address indexed to, euint64 amount);

    event BorrowRequested(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        euint64 amount,
        DataTypes.InterestRateMode interestRateMode,
        uint256 borrowRate,
        uint16 indexed referralCode
    );

    event RepayRequested(
        address indexed reserve,
        address indexed user,
        address indexed repayer,
        euint64 amount,
        bool useATokens
    );

    event SupplyCallback(address indexed reserve, uint64 amount);

    function supplyRequest(address asset, euint64 amount, uint16 referralCode) external;
    function supplyRequest(address asset, einput amount, uint16 referralCode, bytes calldata inputProof) external;

    function withdrawRequest(address asset, euint64 amount, address to) external;
    function withdrawRequest(address asset, einput amount, address to, bytes calldata inputProof) external;

    function borrowRequest(
        address asset,
        euint64 amount,
        DataTypes.InterestRateMode interestRateMode,
        uint16 referralCode
    ) external;
    function borrowRequest(
        address asset,
        einput amount,
        DataTypes.InterestRateMode interestRateMode,
        uint16 referralCode,
        bytes calldata inputProof
    ) external;

    function repayRequest(address asset, euint64 amount, DataTypes.InterestRateMode interestRateMode) external;
    function repayRequest(
        address asset,
        einput amount,
        DataTypes.InterestRateMode interestRateMode,
        bytes calldata inputProof
    ) external;

    function callbackSupplyRequest(uint256 requestId, uint64 amount) external;
    function callbackWithdrawRequest(uint256 requestId, uint256 amount) external;
    function callbackBorrowRequest(uint256 requestId, uint256 amount) external;
    function callbackRepayRequest(uint256 requestId, uint256 amount) external;

    // function getSuppliedBalance(address user, address asset) external view returns (euint64);
}
