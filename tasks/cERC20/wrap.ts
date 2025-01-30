import { task } from "hardhat/config";

import { CUSDC } from "../../types";

task("wrap", "Wrap your erc20 into cERC20")
  .addParam("tokenaddress", "cERC20 contract address")
  .addParam("amount", "wrap amount")
  .setAction(async ({ tokenaddress, amount }, hre) => {
    const { ethers } = hre;
    const [_, user] = await ethers.getSigners();

    const cerc20 = (await ethers.getContractAt("cUSDC", tokenaddress)) as unknown as CUSDC;

    console.log("Wrapping...");
    const txHash = await cerc20.connect(user).wrap(amount);

    console.info("Wrap tx receipt: ", txHash);
  });
