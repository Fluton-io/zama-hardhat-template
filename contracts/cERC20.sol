// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import "fhevm/config/ZamaFHEVMConfig.sol";
import "./zama/ConfidentialERC20Wrapped.sol";
import { IConfidentialityAdapter } from "./confidentiality-adapters/IConfidentialityAdapter.sol";

/// @notice This contract implements an encrypted ERC20-like token with confidential balances using Zama's FHE library.
/// @dev It supports typical ERC20 functionality such as transferring tokens, minting, and setting allowances,
/// @dev but uses encrypted data types.
contract cUSDC is SepoliaZamaFHEVMConfig, ConfidentialERC20Wrapped {
    /// @notice Constructor to initialize the token's name and symbol, and set up the owner
    /// @param erc20_ Address of the ERC20 token to wrap/unwrap.
    /// @param maxDecryptionDelay_ Maximum delay for the Gateway to decrypt. Use high values for production.
    constructor(address erc20_, uint256 maxDecryptionDelay_) ConfidentialERC20Wrapped(erc20_, maxDecryptionDelay_) {}

    /// @notice Custom unwrap callback to notify the confidentiality adapter
    function callbackUnwrap(uint256 requestId, bool canUnwrap) public override nonReentrant onlyGateway {
        UnwrapRequest memory unwrapRequest = unwrapRequests[requestId];

        if (canUnwrap) {
            uint256 amountUint256 = unwrapRequest.amount * (10 ** (ERC20_TOKEN.decimals() - decimals()));

            try ERC20_TOKEN.transfer(unwrapRequest.account, amountUint256) {
                _unsafeBurn(unwrapRequest.account, unwrapRequest.amount);
                _totalSupply -= unwrapRequest.amount;
                emit Unwrap(unwrapRequest.account, unwrapRequest.amount);

                // 🚨 Custom hook to adapter after successful unwrap
                try IConfidentialityAdapter(unwrapRequest.account).onUnwrapComplete(requestId, amountUint256) {
                    // ok
                } catch {
                    emit UnwrapFailTransferFail(unwrapRequest.account, unwrapRequest.amount);
                }
            } catch {
                emit UnwrapFailTransferFail(unwrapRequest.account, unwrapRequest.amount);
            }
        } else {
            emit UnwrapFailNotEnoughBalance(unwrapRequest.account, unwrapRequest.amount);
        }

        delete unwrapRequests[requestId];
        delete isAccountRestricted[unwrapRequest.account];
    }
}
