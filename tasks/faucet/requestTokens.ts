import { task } from "hardhat/config";

import { Faucet } from "../../types";

task("requestTokens", "Request Tokens from the Faucet")
  .addParam("signeraddress", "signer address")
  .addOptionalParam("withNative", "request with native token", "false")
  .setAction(async ({ signeraddress, withNative }, hre) => {
    const { ethers, deployments } = hre;
    const signer = await ethers.getSigner(signeraddress);
    const faucetDeployment = await deployments.get("Faucet");

    const faucet = (await ethers.getContractAt("Faucet", faucetDeployment.address, signer)) as unknown as Faucet;

    console.log("Requesting...");
    const txHash = await faucet.requestTokens(withNative);

    console.info("requestTokens tx receipt: ", txHash);
  });
