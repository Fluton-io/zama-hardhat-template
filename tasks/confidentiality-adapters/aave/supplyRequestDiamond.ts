import { Typed } from "ethers";
// @ts-expect-error zama has no types
import { createInstance as createFhevmInstance } from "fhevmjs";
import { task, types } from "hardhat/config";

import addresses from "../../../config/addresses";
import { GATEWAY_URL } from "../../../config/constants";

task("supplyRequest", "Supply tokens into Diamond SupplyRequestFacet")
  .addOptionalParam("signeraddress", "Signer address", undefined, types.string)
  .addOptionalParam("diamondaddress", "Diamond contract address", undefined, types.string)
  .addOptionalParam("asset", "The supplied token address", undefined, types.string)
  .addOptionalParam("amount", "The supplied amount", "1000000", types.string)
  .setAction(async ({ signeraddress, diamondaddress, asset, amount }, hre) => {
    const { getChainId, ethers, deployments, getNamedAccounts } = hre;
    const chainId = await getChainId();
    const { user } = await getNamedAccounts();
    const signer = await ethers.getSigner(signeraddress || user);

    if (!addresses[+chainId]) {
      throw new Error("Chain ID not supported");
    }

    if (!asset) {
      asset = addresses[+chainId].AAVE_USDC;
    }

    if (!diamondaddress) {
      diamondaddress = (await deployments.get("Diamond")).address;
    }

    const instance = await createFhevmInstance({
      kmsContractAddress: addresses[+chainId].KMSVERIFIER,
      aclContractAddress: addresses[+chainId].ACL,
      networkUrl: hre.network.config.url,
      gatewayUrl: GATEWAY_URL,
    });

    const input = instance.createEncryptedInput(diamondaddress, signer.address);

    const rawAmount = parseInt(amount);

    const encryptedAmount = await input.add64(rawAmount).encrypt();

    // Connect to Diamond as supplyFacet
    const supplyFacet = await ethers.getContractAt("SupplyFacet", diamondaddress, signer);

    const tx = await supplyFacet.supplyRequest(
      Typed.address(asset),
      Typed.bytes32(encryptedAmount.handles[0]),
      Typed.uint16(0), // referralCode
      Typed.bytes(encryptedAmount.inputProof),
      {
        gasLimit: 9000000,
      },
    );

    console.info("Supply tx receipt:", tx.hash);
    await tx.wait();
    console.info("Supply transaction confirmed.");
  });

task("finalizeSupplyRequests", "Finalize the supply requests via Diamond")
  .addOptionalParam("signeraddress", "Signer address", undefined, types.string)
  .addOptionalParam("diamondaddress", "Diamond contract address", undefined, types.string)
  .addParam("requestid", "The request ID of the supply request")
  .setAction(async ({ signeraddress, diamondaddress, requestid }, hre) => {
    const { ethers, deployments, getNamedAccounts } = hre;
    const { user } = await getNamedAccounts();
    const signer = await ethers.getSigner(signeraddress || user);

    if (!diamondaddress) {
      diamondaddress = (await deployments.get("Diamond")).address;
    }

    const supplyFacet = await ethers.getContractAt("SupplyFacet", diamondaddress, signer);

    const tx = await supplyFacet.finalizeSupplyRequests(requestid, {
      gasLimit: 9000000,
    });

    console.info("finalizeSupplyRequests tx hash:", tx.hash);
    await tx.wait();
    console.info("finalizeSupplyRequests transaction confirmed ✅", tx.hash);
  });
