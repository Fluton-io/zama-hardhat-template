import { Typed } from "ethers";
// @ts-expect-error zama has no types
import { createInstance as createFhevmInstance } from "fhevmjs";
import { task, types } from "hardhat/config";

import addresses from "../../../config/addresses";
import { GATEWAY_URL } from "../../../config/constants";

task("borrowRequest", "Borrow tokens from Aave via Diamond")
  .addOptionalParam("signeraddress", "Signer address", undefined, types.string)
  .addOptionalParam("diamondaddress", "Diamond contract address", undefined, types.string)
  .addOptionalParam("asset", "The asset to borrow", undefined, types.string)
  .addOptionalParam("amount", "The borrowed amount", "1000000", types.string)
  .addOptionalParam("interestRateMode", "The interest rate mode (1 for stable, 2 for variable)", "2", types.string)
  .setAction(async ({ signeraddress, diamondaddress, asset, amount, interestRateMode }, hre) => {
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

    // Connect to Diamond as borrowFacet
    const borrowFacet = await ethers.getContractAt("BorrowFacet", diamondaddress, signer);

    const txHash = await borrowFacet.borrowRequest(
      Typed.address(asset),
      Typed.bytes32(encryptedAmount.handles[0]),
      Typed.uint8(interestRateMode),
      Typed.uint16(0), // referralCode
      Typed.bytes(encryptedAmount.inputProof),
    );
    console.info("Borrow tx receipt: ", txHash);
  });

task("finalizeBorrowRequest", "Finalize the borrow requests via Diamond")
  .addOptionalParam("signeraddress", "Signer address", undefined, types.string)
  .addOptionalParam("diamondaddress", "Diamond contract address", undefined, types.string)
  .addParam("requestid", "The request ID of the borrow request")
  .setAction(async ({ signeraddress, diamondaddress, requestid }, hre) => {
    const { ethers, deployments, getNamedAccounts } = hre;
    const { user } = await getNamedAccounts();
    const signer = await ethers.getSigner(signeraddress || user);

    if (!diamondaddress) {
      diamondaddress = (await deployments.get("Diamond")).address;
    }

    const borrowFacet = await ethers.getContractAt("BorrowFacet", diamondaddress, signer);

    const tx = await borrowFacet.finalizeBorrowRequests(requestid, {
      gasLimit: 9000000,
    });

    console.info("finalizeBorrowRequests tx hash:", tx.hash);
    await tx.wait();
    console.info("finalizeBorrowRequests transaction confirmed ✅", tx.hash);
  });
