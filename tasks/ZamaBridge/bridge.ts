import { createInstance as createFhevmInstance } from "fhevmjs";
import { task } from "hardhat/config";

import addresses from "../../config/addresses";
import { GATEWAY_URL } from "../../config/constants";
import { ZamaBridge } from "../../types";

task("bridge", "Bridge cERC20 tokens to FHEVM")
  .addParam("tokenaddress", "cERC20 contract address")
  .addOptionalParam("receiver", "receiver address")
  .addOptionalParam("amount", "amount to bridge", "1000000") // 1 cERC20
  .addOptionalParam("relayeraddress", "relayer address")
  .setAction(async ({ tokenaddress, receiver, amount, relayeraddress }, hre) => {
    const { deployments, ethers, getChainId } = hre;
    const chainId = await getChainId();
    const [_, user, relayer] = await ethers.getSigners();
    const zamaBridge = await deployments.get("ZamaBridge");

    if (!addresses[+chainId]) {
      throw new Error("Chain ID not supported");
    }

    if (!receiver) {
      receiver = user.address;
    }

    if (!relayeraddress) {
      relayeraddress = relayer.address;
    }

    const instance = await createFhevmInstance({
      kmsContractAddress: addresses[+chainId].KMSVERIFIER,
      aclContractAddress: addresses[+chainId].ACL,
      networkUrl: hre.network.config.url,
      gatewayUrl: GATEWAY_URL,
    });

    const encryptedInput = await instance
      .createEncryptedInput(zamaBridge.address, user.address)
      .addAddress(receiver)
      .add64(+amount)
      .encrypt();

    const bridge = (await ethers.getContractAt("ZamaBridge", zamaBridge.address, user)) as ZamaBridge;

    console.log("Bridging...");
    const txHash = await bridge.bridgeCERC20(
      tokenaddress,
      encryptedInput.handles[0],
      encryptedInput.handles[1],
      encryptedInput.inputProof,
      relayeraddress,
    );

    console.info("Bridge receipt: ", txHash);
  });
