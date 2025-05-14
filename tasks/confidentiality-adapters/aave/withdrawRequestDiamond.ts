import { Typed } from "ethers";
// @ts-expect-error zama has no types
import { createInstance as createFhevmInstance } from "fhevmjs";
import { task, types } from "hardhat/config";

import addresses from "../../../config/addresses";
import { GATEWAY_URL } from "../../../config/constants";

task("withdrawRequest", "Withdraw tokens from Aave via Diamond")
  .addOptionalParam("signeraddress", "Signer address", undefined, types.string)
  .addOptionalParam("diamondaddress", "Diamond contract address", undefined, types.string)
  .addOptionalParam("asset", "The supplied token address", undefined, types.string)
  .addOptionalParam("amount", "The amount to withdraw", "1000000", types.string)
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

    // Connect to Diamond as withdrawFacet
    const withdrawFacet = await ethers.getContractAt("WithdrawFacet", diamondaddress, signer);

    const txHash = await withdrawFacet.withdrawRequest(
      Typed.address(asset),
      Typed.bytes32(encryptedAmount.handles[0]),
      Typed.bytes(encryptedAmount.inputProof),
    );
    console.info("Withdraw tx receipt: ", txHash);
  });

task("finalizeWithdrawRequest", "Finalize the withdraw requests via Diamond")
  .addOptionalParam("signeraddress", "Signer address", undefined, types.string)
  .addOptionalParam("diamondaddress", "Diamond contract address", undefined, types.string)
  .addParam("requestid", "The request ID of the withdraw request")
  .setAction(async ({ signeraddress, diamondaddress, requestid }, hre) => {
    const { ethers, deployments, getNamedAccounts } = hre;

    const chainId = await hre.getChainId();
    const { user } = await getNamedAccounts();
    const signer = await ethers.getSigner(signeraddress || user);

    if (!addresses[+chainId]) {
      throw new Error("Chain ID not supported");
    }
    if (!diamondaddress) {
      diamondaddress = (await deployments.get("Diamond")).address;
    }

    // Connect to Diamond as withdrawFacet
    const withdrawFacet = await ethers.getContractAt("WithdrawFacet", diamondaddress, signer);

    const tx = await withdrawFacet.finalizeWithdrawRequests(requestid, {
      gasLimit: 9000000,
    });
    console.info("Finalize withdraw tx hash: ", tx.hash);

    await tx.wait();
    console.info("Withdraw request finalized ", tx.hash);
  });
