// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "fhevm/gateway/GatewayCaller.sol";
import { LibAdapterStorage } from "../libraries/LibAdapterStorage.sol";
import { TFHE } from "fhevm/lib/TFHE.sol";
import { ConfidentialERC20Wrapped } from "../../../zama/ConfidentialERC20Wrapped.sol";
import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library LibRepayRequest {
    bytes4 constant RepayRequestFacet__callbackRepayRequest = bytes4(keccak256("callbackRepayRequest(uint256,uint64)"));

    function repayRequest(address asset, euint64 amount, DataTypes.InterestRateMode interestRateMode) internal {
        LibAdapterStorage.Storage storage s = LibAdapterStorage.getStorage();

        euint64 userDebt = s.userDebts[msg.sender][asset];
        euint64 safeAmount = TFHE.select(TFHE.le(amount, userDebt), amount, TFHE.asEuint64(0));

        address cToken = s.tokenAddressToCTokenAddress[asset];
        if (cToken == address(0)) {
            revert LibAdapterStorage.InvalidCTokenAddress(asset);
        }

        TFHE.allow(safeAmount, cToken);

        require(
            ConfidentialERC20Wrapped(cToken).transferFrom(msg.sender, address(this), safeAmount),
            "LibRepayRequest: Transfer failed"
        );
        TFHE.allowThis(safeAmount);

        s.repayRequests.push(
            LibAdapterStorage.RepayRequestData({
                sender: msg.sender,
                asset: asset,
                amount: safeAmount,
                interestRateMode: interestRateMode
            })
        );
        emit LibAdapterStorage.RepayRequested(asset, msg.sender, msg.sender, safeAmount, false);

        if (s.repayRequests.length < s.REQUEST_THRESHOLD) {
            return;
        }

        LibAdapterStorage.RepayRequestData[] memory requests = new LibAdapterStorage.RepayRequestData[](
            s.REQUEST_THRESHOLD
        );
        uint256[] memory matchedIndexes = new uint256[](s.REQUEST_THRESHOLD);
        uint256 count = 0;

        for (uint256 i = 0; i < s.repayRequests.length; i++) {
            LibAdapterStorage.RepayRequestData storage rrd = s.repayRequests[i];
            if (rrd.asset == asset && rrd.interestRateMode == interestRateMode) {
                requests[count] = rrd;
                matchedIndexes[count] = i;

                unchecked {
                    count++;
                }
            }
            if (count == s.REQUEST_THRESHOLD) break;
        }

        if (requests.length >= s.REQUEST_THRESHOLD) {
            _processRepayRequests(s, requests, matchedIndexes);
        }
    }

    function _processRepayRequests(
        LibAdapterStorage.Storage storage s,
        LibAdapterStorage.RepayRequestData[] memory rrd,
        uint256[] memory matchedIndexes
    ) internal {
        uint256[] memory cts = new uint256[](1);
        euint256 totalAmount = TFHE.asEuint256(0);

        for (uint256 i = 0; i < rrd.length; i++) {
            totalAmount = TFHE.add(totalAmount, rrd[i].amount);
        }

        cts[0] = Gateway.toUint256(totalAmount);
        uint256 requestId = Gateway.requestDecryption(
            cts,
            RepayRequestFacet__callbackRepayRequest,
            0,
            block.timestamp + 100,
            false
        );

        for (uint256 i = 0; i < rrd.length; i++) {
            s.requestIdToRepayRequests[requestId].push(rrd[i]);
        }

        s.requestIdToRequestData[requestId] = LibAdapterStorage.RequestData({
            requestType: LibAdapterStorage.RequestType.REPAY,
            data: abi.encode(rrd)
        });

        for (uint256 i = matchedIndexes.length; i > 0; i--) {
            uint256 idx = matchedIndexes[i - 1];
            s.repayRequests[idx] = s.repayRequests[s.repayRequests.length - 1];
            s.repayRequests.pop();
        }
    }

    function callbackRepayRequest(uint256 requestId, uint64 amount) internal {
        LibAdapterStorage.Storage storage s = LibAdapterStorage.getStorage();

        LibAdapterStorage.RepayRequestData[] memory requests = s.requestIdToRepayRequests[requestId];
        if (requests.length == 0) {
            revert LibAdapterStorage.NotEnoughRepayRequest();
        }
        if (amount == 0) {
            revert LibAdapterStorage.AmountIsZero();
        }

        address asset = requests[0].asset;
        address cToken = s.tokenAddressToCTokenAddress[asset];
        if (cToken == address(0)) {
            revert LibAdapterStorage.InvalidCTokenAddress(asset);
        }

        ConfidentialERC20Wrapped(cToken).unwrap(uint64(amount));

        IERC20(asset).approve(address(s.aavePool), amount);

        emit LibAdapterStorage.RepayCallback(asset, uint64(amount), requestId);
    }

    function finalizeRepayRequests(uint256 repayRequestId) internal {
        LibAdapterStorage.Storage storage s = LibAdapterStorage.getStorage();

        LibAdapterStorage.RequestData memory requestData = s.requestIdToRequestData[repayRequestId];

        if (requestData.requestType != LibAdapterStorage.RequestType.REPAY) {
            revert LibAdapterStorage.InvalidRequestType();
        }

        LibAdapterStorage.RepayRequestData[] memory requests = abi.decode(
            requestData.data,
            (LibAdapterStorage.RepayRequestData[])
        );

        uint256 unwrapRequestId = s.requestIdToUnwrapRequestId[repayRequestId];
        if (unwrapRequestId == 0) {
            revert LibAdapterStorage.NoUnwrapRequestIdFound();
        }
        uint256 amount = s.requestIdToAmount[unwrapRequestId];
        if (amount == 0) {
            revert LibAdapterStorage.AmountIsZero();
        }
        address asset = requests[0].asset;

        IERC20(asset).approve(address(s.aavePool), amount);
        s.aavePool.repay(asset, amount, uint256(requests[0].interestRateMode), address(this));

        for (uint256 i = 0; i < requests.length; i++) {
            address user = requests[i].sender;

            //decrease user's enrypteddebt
            s.userDebts[user][asset] = TFHE.sub(s.userDebts[user][asset], requests[i].amount);
            TFHE.allow(s.userDebts[user][asset], user);
            TFHE.allowThis(s.userDebts[user][asset]);

            //update user's max borrowable
            s.userMaxBorrowable[user] = TFHE.add(s.userMaxBorrowable[user], requests[i].amount);
            TFHE.allow(s.userMaxBorrowable[user], user);
            TFHE.allowThis(s.userMaxBorrowable[user]);
        }

        emit LibAdapterStorage.FinalizeRepayRequest(asset, repayRequestId);

        delete s.requestIdToRepayRequests[repayRequestId];
        delete s.requestIdToRequestData[repayRequestId];
        delete s.requestIdToAmount[unwrapRequestId];
        delete s.requestIdToUnwrapRequestId[repayRequestId];
    }
}
