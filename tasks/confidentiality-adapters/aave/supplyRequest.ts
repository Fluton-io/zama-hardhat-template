import { Typed } from "ethers";
// @ts-expect-error zama has no types - import types when it exists
import { createInstance as createFhevmInstance } from "fhevmjs";
import { task, types } from "hardhat/config";

import addresses from "../../../config/addresses";
import { GATEWAY_URL } from "../../../config/constants";
import { AaveConfidentialityAdapter } from "../../../types";

task("supplyRequest", "Supply tokens into Aave")
  .addOptionalParam("signeraddress", "signer address", undefined, types.string)
  .addOptionalParam("contractaddress", "Aave Confidentiality Adapter address", undefined, types.string)
  .addOptionalParam("asset", "The supplied token address", undefined, types.string)
  .addOptionalParam("amount", "The supplied amount", "1000000", types.string)
  .setAction(async ({ signeraddress, contractaddress, asset, amount }, hre) => {
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

    const txHash = await contract.supplyRequest(
      Typed.address(asset),
      Typed.bytes32(encryptedAmount.handles[0]),
      Typed.uint16(0),
      Typed.bytes(encryptedAmount.inputProof),
    );

    console.info("Supply tx receipt: ", txHash);
  });
