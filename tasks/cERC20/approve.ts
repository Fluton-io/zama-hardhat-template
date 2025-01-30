import { Typed } from "ethers";
import { createInstance as createFhevmInstance } from "fhevmjs";
import { task } from "hardhat/config";

import addresses from "../../config/addresses";
import { GATEWAY_URL } from "../../config/constants";
import { CUSDC } from "../../types";

task("approve", "Approve cERC20 contract to spend USDC")
  .addParam("tokenaddress", "cERC20 contract address")
  .addParam("spender", "spender address")
  .addParam("amount", "amount to approve")
  .setAction(async ({ tokenaddress, spender, amount }, hre) => {
    const { ethers, getChainId } = hre;
    const chainId = await getChainId();
    const [_, user] = await ethers.getSigners();

    if (!addresses[+chainId]) {
      throw new Error("Chain ID not supported");
    }

    const instance = await createFhevmInstance({
      kmsContractAddress: addresses[+chainId].KMSVERIFIER,
      aclContractAddress: addresses[+chainId].ACL,
      networkUrl: hre.network.config.url,
      gatewayUrl: GATEWAY_URL,
    });

    const input = instance.createEncryptedInput(tokenaddress, user.address);
    const encryptedAmount = await input.add64(+amount).encrypt();

    const cerc20 = (await ethers.getContractAt("cUSDC", tokenaddress)) as unknown as CUSDC;

    console.log("Approving spender to spend USDC");
    const txHash = await cerc20
      .connect(user)
      .approve(
        Typed.address(spender),
        Typed.bytes32(encryptedAmount.handles[0]),
        Typed.bytes(encryptedAmount.inputProof),
      );

    console.info("Approve tx receipt: ", txHash);
  });
