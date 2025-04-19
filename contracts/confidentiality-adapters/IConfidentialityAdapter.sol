pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";

interface IConfidentialityAdapter {
    // function executeConfidential(einput encryptedData, bytes calldata inputProof) external;
    event OnUnwrap(uint256 indexed requestId, uint256 amount);
    function onUnwrap(uint256 requestId, uint256 amount) external;
}
