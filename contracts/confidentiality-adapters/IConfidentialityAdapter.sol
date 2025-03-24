pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";

interface IConfidentialityAdapter {
    // function executeConfidential(einput encryptedData, bytes calldata inputProof) external;
    function onUnwrapComplete(uint256 requestId, uint256 amount) external;
}
