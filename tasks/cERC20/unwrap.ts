import { task } from "hardhat/config";

import { CUSDC } from "../../types";

task("unwrap", "Unwrap your erc20 into cERC20")
  .addParam("signeraddress", "signer address")
  .addParam("tokenaddress", "cERC20 contract address")
  .addOptionalParam("amount", "unwrap amount", "1000000") // 1 cERC20
  .setAction(async ({ signeraddress, tokenaddress, amount }, hre) => {
    const { ethers } = hre;
    const signer = await ethers.getSigner(signeraddress);

    const cerc20 = (await ethers.getContractAt("cUSDC", tokenaddress, signer)) as unknown as CUSDC;

    console.log("Unwrapping...");
    const txHash = await cerc20.unwrap(amount);

    console.info("Unwrap tx receipt: ", txHash);
  });
