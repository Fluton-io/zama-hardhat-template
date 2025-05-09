// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import { LibAdapterStorage } from "../libraries/LibAdapterStorage.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

contract AdminFacet {
    modifier onlyOwner() {
        require(msg.sender == LibDiamond.diamondStorage().contractOwner, "AdminFacet: Not owner");
        _;
    }

    function setCTokenAddress(address token, address cToken) external {
        LibAdapterStorage.Storage storage s = LibAdapterStorage.getStorage();
        s.tokenAddressToCTokenAddress[token] = cToken;
        s.cTokenAddressToTokenAddress[cToken] = token;
    }

    function setAavePoolAddress(address pool) external {
        LibAdapterStorage.Storage storage s = LibAdapterStorage.getStorage();
        s.aavePool = IPool(pool);
    }

    function setRequestThreshold(uint8 threshold) external {
        LibAdapterStorage.Storage storage s = LibAdapterStorage.getStorage();
        s.REQUEST_THRESHOLD = threshold;
    }
}
