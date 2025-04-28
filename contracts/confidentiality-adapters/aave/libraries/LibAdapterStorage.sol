// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

library LibAdapterStorage {
    bytes32 constant STORAGE_POSITION = keccak256("confidential.adapter.storage");

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

    struct Storage {
        uint8 REQUEST_THRESHOLD;
        IPool aavePool;
        SupplyRequestData[] supplyRequests;
        WithdrawRequestData[] withdrawRequests;
        BorrowRequestData[] borrowRequests;
        RepayRequestData[] repayRequests;
        mapping(address => address) tokenAddressToCTokenAddress;
        mapping(address => address) cTokenAddressToTokenAddress;
        mapping(uint256 => SupplyRequestData[]) requestIdToSupplyRequests;
        mapping(uint256 => RequestData) requestIdToRequestData;
        mapping(uint256 => uint256) requestIdToAmount;
        mapping(uint256 => uint256) requestIdToUnwrapRequestId;
        mapping(address => euint64) scaledBalances;
        mapping(address => euint64) userMaxBorrowable;
    }

    event OnUnwrap(uint256 indexed requestId, uint256 amount);

    event SupplyRequested(
        address indexed asset,
        address indexed sender,
        address indexed to,
        euint64 amount,
        uint16 referralCode
    );

    event SupplyCallback(address indexed asset, uint64 amount, uint256 requestId);

    function getStorage() internal pure returns (Storage storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
