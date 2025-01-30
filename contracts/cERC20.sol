// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import "fhevm/config/ZamaFHEVMConfig.sol";
import "./zama/ConfidentialERC20Wrapped.sol";

/// @notice This contract implements an encrypted ERC20-like token with confidential balances using Zama's FHE library.
/// @dev It supports typical ERC20 functionality such as transferring tokens, minting, and setting allowances,
/// @dev but uses encrypted data types.
contract cUSDC is SepoliaZamaFHEVMConfig, ConfidentialERC20Wrapped {
    /// @notice Constructor to initialize the token's name and symbol, and set up the owner
    /// @param erc20_ Address of the ERC20 token to wrap/unwrap.
    /// @param maxDecryptionDelay_ Maximum delay for the Gateway to decrypt. Use high values for production.
    constructor(address erc20_, uint256 maxDecryptionDelay_) ConfidentialERC20Wrapped(erc20_, maxDecryptionDelay_) {}
}
