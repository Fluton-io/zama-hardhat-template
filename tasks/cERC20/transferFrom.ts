import { Typed } from "ethers";
import { createInstance as createFhevmInstance } from "fhevmjs";
import { task } from "hardhat/config";

import addresses from "../../config/addresses";
import { GATEWAY_URL } from "../../config/constants";
import { CUSDC } from "../../types";

task("transferFrom", "Transfer cERC20 tokens from one address to another")
  .addParam("signeraddress", "signer address")
  .addParam("tokenaddress", "cERC20 contract address")
  .addParam("to", "receiver address")
  .addOptionalParam("from", "sender address")
  .addOptionalParam("amount", "transfer amount", "1000000") // 1 cERC20
  .setAction(async ({ signeraddress, tokenaddress, from, to, amount }, hre) => {
    const { ethers, getChainId } = hre;
    const chainId = await getChainId();
    const signer = await ethers.getSigner(signeraddress);

    if (!addresses[+chainId]) {
      throw new Error("Chain ID not supported");
    }

    if (!from) {
      from = signer.address;
    }

    const instance = await createFhevmInstance({
      kmsContractAddress: addresses[+chainId].KMSVERIFIER,
      aclContractAddress: addresses[+chainId].ACL,
      networkUrl: hre.network.config.url,
      gatewayUrl: GATEWAY_URL,
    });

    const input = instance.createEncryptedInput(tokenaddress, signer.address);
    const encryptedAmount = await input.add64(+amount).encrypt();

    const cerc20 = (await ethers.getContractAt("cUSDC", tokenaddress, signer)) as unknown as CUSDC;

    console.log("Transferring...");
    const txHash = await cerc20.transferFrom(
      Typed.address(from),
      Typed.address(to),
      Typed.bytes32(encryptedAmount.handles[0]),
      Typed.bytes(encryptedAmount.inputProof),
    );

    console.info("Transfer from receipt: ", txHash);
  });
