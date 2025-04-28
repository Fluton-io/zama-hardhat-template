import { task, types } from "hardhat/config";

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

    const supplyRequestFacet = await ethers.getContractAt("SupplyRequestFacet", diamondaddress, signer);

    const tx = await supplyRequestFacet.finalizeSupplyRequests(requestid, {
      gasLimit: 9000000,
    });

    console.info("finalizeSupplyRequests tx hash:", tx.hash);
    await tx.wait();
    console.info("finalizeSupplyRequests transaction confirmed ✅", tx.hash);
  });
