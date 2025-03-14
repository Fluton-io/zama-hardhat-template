import { createInstance as createFhevmInstance } from "fhevmjs";
import { task } from "hardhat/config";

import addresses from "../../config/addresses";
import { GATEWAY_URL } from "../../config/constants";
import { ZamaBridge } from "../../types";

task("fulfill", "Fulfills an intent on the bridge")
    .addParam("tokenaddress", "The input token address")
    .addOptionalParam("bridge", "The address of the ZamaBridge contract")
    .addOptionalParam("sender", "The address of the sender")
    .addOptionalParam("receiver", "The address of the receiver")
    .addOptionalParam("relayer", "The address of the relayer")
    .addOptionalParam("amount", "The amount of input tokens", "1000000")
    .setAction(async (args, hre) => {
        const { ethers, deployments, getChainId } = hre;
        const [deployer, user, relayer] = await ethers.getSigners();
        const chainId = await getChainId();
        const zamaBridge = await deployments.get("ZamaBridge");

        if (!args.bridge) {
            args.bridge = zamaBridge.address;
        }

        if (!args.sender) {
            args.sender = deployer.address;
        }

        if (!args.receiver) {
            args.receiver = user.address;
        }

        if (!args.relayeraddress) {
            args.relayer = relayer.address;
        }

        // hardcoded mocked values
        const destinationChainId = 3;
        const intentId = 1101;

        const instance = await createFhevmInstance({
            kmsContractAddress: addresses[+chainId].KMSVERIFIER,
            aclContractAddress: addresses[+chainId].ACL,
            networkUrl: hre.network.config.url,
            gatewayUrl: GATEWAY_URL,
        });

        const encryptedInput = await instance
            .createEncryptedInput(zamaBridge.address, relayer.address)
            .add64(+args.amount)
            .add64(+args.amount)
            .encrypt();

        function uint8ArrayToBigInt(uint8Array: Uint8Array): bigint {
            return BigInt("0x" + Buffer.from(uint8Array).toString("hex"));
        }
        // inputAmount ve outputAmount'u düzelt
        const inputAmountBigInt = uint8ArrayToBigInt(encryptedInput.handles[0]);
        const outputAmountBigInt = uint8ArrayToBigInt(encryptedInput.handles[1]);

        console.log("input amount: ", inputAmountBigInt);
        console.log("output amount: ", outputAmountBigInt);

        console.log("Connecting to ZamaBridge contract...");
        const bridge = (await ethers.getContractAt("ZamaBridge", args.bridge, relayer)) as ZamaBridge;

        console.log("ARGS: ", args);

        const intent = {
            sender: args.sender,
            receiver: args.receiver,
            relayer: args.relayer,
            inputToken: args.tokenaddress,
            outputToken: args.tokenaddress,
            inputAmount: "0xc932d712845b5e92e48bd79a90bf727188cb65f5b20c1f94aff58d7694000500",
            outputAmount: "0xf8f9c775ea3edb416a65ca3cdb061137f6c441c0f186cb8c902aebd3b1010500",
            id: intentId,
            originChainId: chainId,
            destinationChainId: destinationChainId,
            filledStatus: 0,
        };

        console.log("Fulfilling intent:", intent);

        // 📌 fulfill fonksiyonunu çağır
        const tx = await bridge.fulfill(intent);

        console.log(`Transaction sent!\n${tx.hash}`);
        await tx.wait();
        console.log("Intent fulfilled successfully!");
    });
