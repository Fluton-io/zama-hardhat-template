// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "fhevm/lib/TFHE.sol";
import "fhevm/config/ZamaFHEVMConfig.sol";
import { IConfidentialERC20 } from "fhevm-contracts/contracts/token/ERC20/IConfidentialERC20.sol";

contract Faucet is SepoliaZamaFHEVMConfig, Ownable2Step {
    uint256 public waitTime = 24 hours;
    uint256 public nativeTransferAmount = 0.01 ether;

    address[] public tokenAddresses;

    mapping(address => uint256) public nextAccessTime;
    mapping(address => uint64) public maxReceivableTokenAmount;

    constructor(address[] memory _tokenAdresses) Ownable(msg.sender) {
        require(_tokenAdresses.length > 0, "Faucet: No tokens provided");
        tokenAddresses = _tokenAdresses;
    }

    function setWaitTime(uint256 _waitTime) public onlyOwner {
        require(_waitTime > 0);
        waitTime = _waitTime;
    }

    function setMaxReceivableTokenAmount(address _tokenAddress, uint64 _amount) public onlyOwner {
        require(_tokenAddress != address(0));
        maxReceivableTokenAmount[_tokenAddress] = _amount;
    }

    function setNativeTransferAmount(uint256 _amount) public onlyOwner {
        nativeTransferAmount = _amount;
    }

    function addToken(address _tokenAddress) public onlyOwner {
        require(_tokenAddress != address(0));
        tokenAddresses.push(_tokenAddress);
    }

    function removeToken(address _tokenAddress) public onlyOwner {
        require(_tokenAddress != address(0));
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            if (tokenAddresses[i] == _tokenAddress) {
                tokenAddresses[i] = tokenAddresses[tokenAddresses.length - 1];
                tokenAddresses.pop();
                break;
            }
        }
    }

    function requestTokens(bool withNative) public {
        require(allowedToWithdraw(msg.sender));
        nextAccessTime[msg.sender] = block.timestamp + waitTime;
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            address tokenAddress = tokenAddresses[i];
            IConfidentialERC20 token = IConfidentialERC20(tokenAddress);
            euint64 r64 = TFHE.randEuint64(maxReceivableTokenAmount[tokenAddress]);
            TFHE.allow(r64, tokenAddress);
            require(token.transfer(msg.sender, r64), "Faucet: Transfer failed");
        }
        if (withNative) {
            payable(msg.sender).transfer(nativeTransferAmount);
        }
    }

    function allowedToWithdraw(address _address) public view returns (bool) {
        if (nextAccessTime[_address] == 0) {
            return true;
        } else if (block.timestamp >= nextAccessTime[_address]) {
            return true;
        }
        return false;
    }
}
