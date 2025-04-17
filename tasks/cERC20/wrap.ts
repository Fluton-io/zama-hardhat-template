import { task } from "hardhat/config";

import { CUSDC } from "../../types";

task("wrap", "Wrap your erc20 into cERC20")
  .addParam("signeraddress", "signer address")
  .addParam("tokenaddress", "cERC20 contract address")
  .addOptionalParam("amount", "wrap amount", "1000000000000000000") // 1 ERC20
  .setAction(async ({ signeraddress, tokenaddress, amount }, hre) => {
    const { ethers } = hre;
    const signer = await ethers.getSigner(signeraddress);

    const cerc20 = (await ethers.getContractAt("cUSDC", tokenaddress, signer)) as unknown as CUSDC;

    console.log("Wrapping...");
    const txHash = await cerc20.wrap(amount);
    console.log("Transaction hash:", txHash.hash);

    const tx = await txHash.wait();
    console.log("Transaction mined in block:", tx?.blockNumber);
    console.log("Transaction receipt:", tx);
  });
