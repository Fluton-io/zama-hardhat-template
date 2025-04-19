import { task, types } from "hardhat/config";

import { GATEWAY_URL } from "../../../config/constants";
import { AaveConfidentialityAdapter } from "../../../types";

task("finalizeSupplyRequests", "Finalize the supply requests and supply tokens into Aave")
  .addParam("requestid", "The request ID of the supply request")
  .addOptionalParam("signeraddress", "signer address", undefined, types.string)
  .addOptionalParam("contractaddress", "Aave Confidentiality Adapter address", undefined, types.string)
  .setAction(async ({ signeraddress, contractaddress, requestid }, hre) => {
    const { ethers, deployments, getNamedAccounts } = hre;
    const { user } = await getNamedAccounts();
    const signer = await ethers.getSigner(signeraddress || user);

    if (!contractaddress) {
      contractaddress = (await deployments.get("AaveConfidentialityAdapter")).address;
    }

    const contract = (await ethers.getContractAt(
      "AaveConfidentialityAdapter",
      contractaddress,
      signer,
    )) as AaveConfidentialityAdapter;

    const txHash = await contract.finalizeSupplyRequests(requestid);

    console.info("finalizeSupplyRequests tx receipt: ", txHash);
  });
