// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "fhevm/gateway/GatewayCaller.sol";
import { LibAdapterStorage } from "../libraries/LibAdapterStorage.sol";
import { TFHE } from "fhevm/lib/TFHE.sol";
import { ConfidentialERC20Wrapped } from "../../../zama/ConfidentialERC20Wrapped.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IScaledBalanceToken } from "@aave/core-v3/contracts/interfaces/IAToken.sol";

library LibSupplyRequest {
    bytes4 constant SupplyRequestFacet__callbackSupplyRequest =
        bytes4(keccak256("callbackSupplyRequest(uint256,uint64)"));

    function supplyRequest(address asset, euint64 amount, uint16 referralCode) internal {
        LibAdapterStorage.Storage storage s = LibAdapterStorage.getStorage();

        address cToken = s.tokenAddressToCTokenAddress[asset];
        require(cToken != address(0), "CToken not found");

        // Allow and pull cToken from user
        TFHE.allow(amount, cToken);
        require(ConfidentialERC20Wrapped(cToken).transferFrom(msg.sender, address(this), amount), "Transfer failed");

        s.supplyRequests.push(
            LibAdapterStorage.SupplyRequestData({
                sender: msg.sender,
                asset: asset,
                amount: amount,
                referralCode: referralCode
            })
        );

        if (!TFHE.isInitialized(s.scaledBalances[msg.sender])) {
            s.scaledBalances[msg.sender] = TFHE.asEuint64(0);
            TFHE.allowThis(s.scaledBalances[msg.sender]);
        }

        if (!TFHE.isInitialized(s.userMaxBorrowable[msg.sender])) {
            s.userMaxBorrowable[msg.sender] = TFHE.asEuint64(0);
            TFHE.allowThis(s.userMaxBorrowable[msg.sender]);
        }

        emit LibAdapterStorage.SupplyRequested(asset, msg.sender, msg.sender, amount, referralCode);

        if (s.supplyRequests.length < s.REQUEST_THRESHOLD) {
            return;
        }

        LibAdapterStorage.SupplyRequestData[] memory requests = new LibAdapterStorage.SupplyRequestData[](
            s.REQUEST_THRESHOLD
        );
        uint256[] memory matchedIndexes = new uint256[](s.REQUEST_THRESHOLD);

        uint256 count = 0;
        for (uint256 i = 0; i < s.supplyRequests.length; i++) {
            LibAdapterStorage.SupplyRequestData memory srd = s.supplyRequests[i];
            if (srd.asset == asset) {
                requests[count] = srd;
                matchedIndexes[count] = i;

                TFHE.allow(requests[count].amount, msg.sender);
                TFHE.allowThis(requests[count].amount);

                unchecked {
                    count++;
                }
                if (count == s.REQUEST_THRESHOLD) {
                    break;
                }
            }
        }

        TFHE.allowThis(ConfidentialERC20Wrapped(cToken).balanceOf(address(this)));
        TFHE.allow(ConfidentialERC20Wrapped(cToken).balanceOf(address(this)), msg.sender);

        if (requests.length >= s.REQUEST_THRESHOLD) {
            _processSupplyRequests(s, requests, matchedIndexes);
        }
    }

    function _processSupplyRequests(
        LibAdapterStorage.Storage storage s,
        LibAdapterStorage.SupplyRequestData[] memory srd,
        uint256[] memory matchedIndexes
    ) internal {
        uint256[] memory cts = new uint256[](1);
        euint256 totalAmount = TFHE.asEuint256(0);

        for (uint256 i = 0; i < srd.length; i++) {
            totalAmount = TFHE.add(totalAmount, srd[i].amount);
        }

        cts[0] = Gateway.toUint256(totalAmount);
        uint256 requestId = Gateway.requestDecryption(
            cts,
            SupplyRequestFacet__callbackSupplyRequest,
            0,
            block.timestamp + 100,
            false
        );

        for (uint256 i = 0; i < srd.length; i++) {
            s.requestIdToSupplyRequests[requestId].push(srd[i]);
        }

        s.requestIdToRequestData[requestId] = LibAdapterStorage.RequestData(
            LibAdapterStorage.RequestType.SUPPLY,
            abi.encode(srd)
        );

        for (uint256 i = matchedIndexes.length; i > 0; i--) {
            uint256 idx = matchedIndexes[i - 1];
            s.supplyRequests[idx] = s.supplyRequests[s.supplyRequests.length - 1];
            s.supplyRequests.pop();
        }
    }

    function callbackSupplyRequest(uint256 requestId, uint64 amount) internal {
        LibAdapterStorage.Storage storage s = LibAdapterStorage.getStorage();

        LibAdapterStorage.SupplyRequestData[] memory requests = s.requestIdToSupplyRequests[requestId];
        require(requests.length > 0, "LibSupplyRequest: No supply requests found");

        address asset = requests[0].asset;
        address cToken = s.tokenAddressToCTokenAddress[asset];
        require(cToken != address(0), "LibSupplyRequest: Invalid cToken");

        ConfidentialERC20Wrapped(cToken).unwrap(amount);

        IERC20(asset).approve(address(s.aavePool), amount);

        emit LibAdapterStorage.SupplyCallback(asset, amount, requestId);
    }

    function finalizeSupplyRequests(uint256 supplyRequestId) internal {
        LibAdapterStorage.Storage storage s = LibAdapterStorage.getStorage();

        LibAdapterStorage.SupplyRequestData[] memory requests = s.requestIdToSupplyRequests[supplyRequestId];
        require(requests.length >= s.REQUEST_THRESHOLD, "LibSupplyRequest: not enough supply requests");

        uint256 unwrapRequestId = s.requestIdToUnwrapRequestId[supplyRequestId];
        uint256 amount = s.requestIdToAmount[unwrapRequestId];
        require(amount > 0, "LibSupplyRequest: invalid amount");

        address asset = requests[0].asset;
        address aToken = s.aavePool.getReserveData(asset).aTokenAddress;

        uint256 beforeScaledBalance = IScaledBalanceToken(aToken).scaledBalanceOf(address(this));

        s.aavePool.supply(asset, amount, address(this), requests[0].referralCode);

        uint256 afterScaledBalance = IScaledBalanceToken(aToken).scaledBalanceOf(address(this));
        uint256 difference = afterScaledBalance - beforeScaledBalance;
        uint256 multiplier = difference / (amount / (10 ** 6)); // 6 decimals for USDC

        // update each user's scaled balances and max borrowable
        for (uint256 i = 0; i < requests.length; i++) {
            euint64 newBalance = TFHE.add(
                s.scaledBalances[requests[i].sender],
                TFHE.div(TFHE.mul(requests[i].amount, uint64(multiplier)), 1e6)
            );
            s.scaledBalances[requests[i].sender] = newBalance;
            TFHE.allowThis(newBalance);
            TFHE.allow(newBalance, requests[i].sender);

            // calculate and update max borrowable
            euint64 addedBorrowable = TFHE.div(TFHE.mul(requests[i].amount, uint64(8000)), uint64(10000)); // LTV 80%

            s.userMaxBorrowable[requests[i].sender] = TFHE.add(
                s.userMaxBorrowable[requests[i].sender],
                addedBorrowable
            );

            TFHE.allow(s.userMaxBorrowable[requests[i].sender], requests[i].sender);
            TFHE.allowThis(s.userMaxBorrowable[requests[i].sender]);
        }

        emit LibAdapterStorage.FinalizeSupplyRequest(asset, supplyRequestId);

        // clean up
        delete s.requestIdToSupplyRequests[supplyRequestId];
        delete s.requestIdToRequestData[supplyRequestId];
        delete s.requestIdToAmount[unwrapRequestId];
        delete s.requestIdToUnwrapRequestId[supplyRequestId];
    }
}
