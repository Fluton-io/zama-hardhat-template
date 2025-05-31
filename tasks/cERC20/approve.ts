import { Typed } from "ethers";
import { createInstance as createFhevmInstance } from "fhevmjs";
import { task } from "hardhat/config";

import addresses from "../../config/addresses";
import { GATEWAY_URL } from "../../config/constants";
import { CERC20 } from "../../types";

task("approve", "Approve cERC20 contract to spend tokens")
  .addParam("signeraddress", "signer address")
  .addParam("tokenaddress", "cERC20 contract address")
  .addOptionalParam("spenderaddress", "spender address")
  .addParam("amount", "amount to approve")
  .setAction(async ({ signeraddress, tokenaddress, spenderaddress, amount }, hre) => {
    const { ethers, getChainId, deployments } = hre;
    const chainId = await getChainId();
    const signer = await ethers.getSigner(signeraddress);

    if (!addresses[+chainId]) {
      throw new Error("Chain ID not supported");
    }

    if (!spenderaddress) {
      spenderaddress = (await deployments.get("Diamond")).address;
    }
    const instance = await createFhevmInstance({
      kmsContractAddress: addresses[+chainId].KMSVERIFIER,
      aclContractAddress: addresses[+chainId].ACL,
      networkUrl: hre.network.config.url,
      gatewayUrl: GATEWAY_URL,
    });
    const input = instance.createEncryptedInput(tokenaddress, signer.address);

    const encryptedAmount = await input.add64(+amount).encrypt();

    const cerc20 = (await ethers.getContractAt("cERC20", tokenaddress, signer)) as unknown as CERC20;

    console.log("Approving spender to spend tokens...");
    const txHash = await cerc20.approve(
      Typed.address(spenderaddress),
      Typed.bytes32(encryptedAmount.handles[0]),
      Typed.bytes(encryptedAmount.inputProof),
    );

    console.info("Approve tx receipt: ", txHash);
  });
