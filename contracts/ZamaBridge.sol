// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "fhevm/lib/TFHE.sol";
import "fhevm/config/ZamaFHEVMConfig.sol";
import { IConfidentialERC20 } from "fhevm-contracts/contracts/token/ERC20/IConfidentialERC20.sol";

contract ZamaBridge is SepoliaZamaFHEVMConfig, Ownable2Step {
    struct Intent {
        address tokenAddress;
        address from;
        address to;
        euint64 encryptedAmount;
    }

    uint64 public nextIntentId = 0;

    mapping(uint64 => Intent) public intents;

    event Packet(address tokenAddress, eaddress to, euint64 amount, address relayer);
    event IntentProcessed(uint64 indexed intentId);

    constructor() Ownable(msg.sender) {}

    function bridgeCERC20(
        address tokenAddress,
        einput _encryptedTo,
        einput _encryptedAmount,
        bytes calldata _inputProof,
        address _relayerAddress
    ) public {
        eaddress to = TFHE.asEaddress(_encryptedTo, _inputProof);
        euint64 amount = TFHE.asEuint64(_encryptedAmount, _inputProof);

        TFHE.allow(amount, tokenAddress);

        IConfidentialERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);

        TFHE.allow(to, _relayerAddress);
        TFHE.allow(amount, _relayerAddress);

        emit Packet(tokenAddress, to, amount, _relayerAddress);
    }

    function onRecvIntent(
        address tokenAddress,
        address _to,
        einput _encryptedAmount,
        bytes calldata inputProof
    ) external {
        euint64 amount = TFHE.asEuint64(_encryptedAmount, inputProof);
        TFHE.allow(amount, tokenAddress);
        IConfidentialERC20(tokenAddress).transferFrom(msg.sender, _to, amount);

        nextIntentId++;
        Intent memory intent = Intent({
            tokenAddress: tokenAddress,
            from: msg.sender,
            to: _to,
            encryptedAmount: amount
        });
        intents[nextIntentId] = intent;

        emit IntentProcessed(nextIntentId);
    }

    function withdraw(address tokenAddress, einput _encryptedAmount, bytes calldata _inputProof) public onlyOwner {
        IConfidentialERC20(tokenAddress).transfer(msg.sender, _encryptedAmount, _inputProof);
    }
}
