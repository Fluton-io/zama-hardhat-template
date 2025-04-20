import { Typed } from "ethers";
// @ts-expect-error zama has no types - import types when it exists
import { createInstance as createFhevmInstance } from "fhevmjs";
import { task, types } from "hardhat/config";

import addresses from "../../../config/addresses";
import { GATEWAY_URL } from "../../../config/constants";
import { AaveConfidentialityAdapter } from "../../../types";

task("borrowRequest", "Borrow tokens from Aave")
  .addOptionalParam("signeraddress", "signer address", undefined, types.string)
  .addOptionalParam("contractaddress", "Aave Confidentiality Adapter address", undefined, types.string)
  .addOptionalParam("asset", "The borrowed token address", undefined, types.string)
  .addOptionalParam("amount", "The borrowed amount", "1000000", types.string)
  .addOptionalParam("interestRateMode", "The interest rate mode (0 for stable, 1 for variable)", "2", types.string)
  .setAction(async ({ signeraddress, contractaddress, asset, amount, interestRateMode }, hre) => {
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
    if (!contractaddress) {
      contractaddress = (await deployments.get("AaveConfidentialityAdapter")).address;
    }
    const instance = await createFhevmInstance({
      kmsContractAddress: addresses[+chainId].KMSVERIFIER,
      aclContractAddress: addresses[+chainId].ACL,
      networkUrl: hre.network.config.url,
      gatewayUrl: GATEWAY_URL,
    });

    const input = instance.createEncryptedInput(contractaddress, signer.address);
    const encryptedAmount = await input.add64(+amount).encrypt();
    const contract = (await ethers.getContractAt(
      "AaveConfidentialityAdapter",
      contractaddress,
      signer,
    )) as AaveConfidentialityAdapter;

    const txHash = await contract.borrowRequest(
      Typed.address(asset),
      Typed.bytes32(encryptedAmount.handles[0]),
      Typed.uint8(interestRateMode),
      Typed.uint16(0),
      Typed.bytes(encryptedAmount.inputProof),
    );
    console.info("Borrow tx receipt: ", txHash);
  });

task("finalizeBorrow", "Finalize borrow transaction")
  .addOptionalParam("signeraddress", "signer address", undefined, types.string)
  .addOptionalParam("contractaddress", "Aave Confidentiality Adapter address", undefined, types.string)
  .addOptionalParam("amount", "The borrowed amount", "1000000", types.string)
  .addOptionalParam("requestid", "The borrow request ID", undefined, types.string)
  .setAction(async ({ signeraddress, contractaddress, amount, requestid }, hre) => {
    const { getChainId, ethers, deployments, getNamedAccounts } = hre;

    const chainId = await getChainId();
    const { user } = await getNamedAccounts();
    const signer = await ethers.getSigner(signeraddress || user);
    if (!addresses[+chainId]) {
      throw new Error("Chain ID not supported");
    }
    if (!contractaddress) {
      contractaddress = (await deployments.get("AaveConfidentialityAdapter")).address;
    }
    const contract = (await ethers.getContractAt(
      "AaveConfidentialityAdapter",
      contractaddress,
      signer,
    )) as AaveConfidentialityAdapter;

    const txHash = await contract.finalizeBorrow(Typed.uint256(requestid), Typed.uint256(amount));
    console.info("Finalize borrow tx receipt: ", txHash);
  });
