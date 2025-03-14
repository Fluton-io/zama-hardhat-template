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
        const [deployer, user, relayer] = await ethers.getSigners();
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

        const destinationChainId = 3;

        const instance = await createFhevmInstance({
            kmsContractAddress: addresses[+chainId].KMSVERIFIER,
            aclContractAddress: addresses[+chainId].ACL,
            networkUrl: hre.network.config.url,
            gatewayUrl: GATEWAY_URL,
        });

        const encryptedInput = await instance
            .createEncryptedInput(zamaBridge.address, deployer.address)
            .add64(+amount)
            .add64(+amount)
            .encrypt();

        const bridge = (await ethers.getContractAt("ZamaBridge", zamaBridge.address, deployer)) as ZamaBridge;

        console.log("Bridging...");
        console.log("Tx sent by: ", deployer.address);
        const tx = await bridge.bridge(
            deployer.address,
            receiver,
            relayeraddress,
            tokenaddress,
            tokenaddress,
            encryptedInput.handles[0],
            encryptedInput.handles[1],
            destinationChainId,
            encryptedInput.inputProof,
        );

        console.info("Bridge receipt: ", tx);

        const receipt = await tx.wait();
        console.log("Transaction Mined in Block:", receipt?.blockNumber);

        // Eventleri log olarak al
        const iface = new ethers.Interface(["event BridgeCompleted(address sender, address receiver, uint256 amount)"]); // Örnek event

        console.log("Events Emitted: ", receipt?.logs);
        // // for (const log of receipt?.logs) {
        // //   try {
        // //     const parsedLog = iface.parseLog(log);
        // //     console.log(`Event: ${parsedLog.name}, Args: ${JSON.stringify(parsedLog.args)}`);
        // //   } catch (error) {
        // //     // Eğer log bu contract'ın eventlerine ait değilse, parseLog hata verebilir.
        // //   }
        // // }

        // // }
    });
