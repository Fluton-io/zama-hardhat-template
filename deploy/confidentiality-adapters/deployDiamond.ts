import { Contract } from "ethers";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import addresses from "../../config/addresses";
import { getSelectors } from "./getSelectors";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const chainId = await hre.getChainId();
  const { deploy } = hre.deployments;

  console.log("Deploying with:", deployer, "on chainId:", chainId);

  // 2. Deploy Diamond
  const diamondDeployment = await deploy("Diamond", {
    from: deployer,
    args: [deployer],
    log: true,
  });
  console.log("Diamond deployed at:", diamondDeployment.address);

  const supplyFacetDeployment = await deploy("SupplyFacet", {
    from: deployer,
    log: true,
  });
  console.log("SupplyFacet deployed at:", supplyFacetDeployment.address);

  const withdrawFacetDeployment = await deploy("WithdrawFacet", {
    from: deployer,
    log: true,
  });
  console.log("WithdrawFacet deployed at:", withdrawFacetDeployment.address);

  const borrowFacetDeployment = await deploy("BorrowFacet", {
    from: deployer,
    log: true,
  });
  console.log("BorrowFacet deployed at:", borrowFacetDeployment.address);

  const repayFacetDeployment = await deploy("RepayFacet", {
    from: deployer,
    log: true,
  });
  console.log("RepayFacet deployed at:", repayFacetDeployment.address);

  const supplyCut = {
    facetAddress: supplyFacetDeployment.address,
    action: 0,
    functionSelectors: getSelectors(
      (await hre.ethers.getContractAt("SupplyFacet", supplyFacetDeployment.address)) as unknown as Contract,
    ),
  };

  const withdrawCut = {
    facetAddress: withdrawFacetDeployment.address,
    action: 0,
    functionSelectors: getSelectors(
      (await hre.ethers.getContractAt("WithdrawFacet", withdrawFacetDeployment.address)) as unknown as Contract,
    ),
  };

  const borrowCut = {
    facetAddress: borrowFacetDeployment.address,
    action: 0,
    functionSelectors: getSelectors(
      (await hre.ethers.getContractAt("BorrowFacet", borrowFacetDeployment.address)) as unknown as Contract,
    ),
  };

  const repayCut = {
    facetAddress: repayFacetDeployment.address,
    action: 0,
    functionSelectors: getSelectors(
      (await hre.ethers.getContractAt("RepayFacet", repayFacetDeployment.address)) as unknown as Contract,
    ),
  };

  const diamond = await hre.ethers.getContractAt("Diamond", diamondDeployment.address);

  console.log("Performing SupplyFacet diamondCut...");
  const tx = await diamond.diamondCut([supplyCut]);
  await tx.wait();
  console.log("SupplyFacet cut completed.");

  console.log("Performing WithdrawFacet diamondCut...");
  const tx2 = await diamond.diamondCut([withdrawCut]);
  await tx2.wait();
  console.log("WithdrawFacet diamond cut completed.");

  console.log("Performing BorrowFacet diamondCut...");
  const tx3 = await diamond.diamondCut([borrowCut]);
  await tx3.wait();
  console.log("BorrowFacet diamond cut completed.");

  console.log("Performing RepayFacet diamondCut...");
  const tx4 = await diamond.diamondCut([repayCut]);
  await tx4.wait();
  console.log("RepayFacet diamond cut completed.");

  const adminFacetDeployment = await deploy("AdminFacet", {
    from: deployer,
    log: true,
  });
  console.log("AdminFacet deployed at:", adminFacetDeployment.address);

  // Now prepare another cut
  const adminCut = {
    facetAddress: adminFacetDeployment.address,
    action: 0,
    functionSelectors: getSelectors(
      (await hre.ethers.getContractAt("AdminFacet", adminFacetDeployment.address)) as unknown as Contract,
    ),
  };

  // Cut AdminFacet into diamond
  console.log("Performing AdminFacet diamondCut...");

  const tx5 = await diamond.diamondCut([adminCut]);
  await tx5.wait();
  console.log("AdminFacet diamond cut completed.");

  const adminFacet = await hre.ethers.getContractAt("AdminFacet", diamondDeployment.address);

  const loupeFacetDeployment = await deploy("DiamondLoupeFacet", {
    from: deployer,
    log: true,
  });
  console.log("DiamondLoupeFacet deployed at:", loupeFacetDeployment.address);

  // Now prepare cut for LoupeFacet
  const loupeCut = {
    facetAddress: loupeFacetDeployment.address,
    action: 0,
    functionSelectors: getSelectors(
      (await hre.ethers.getContractAt("DiamondLoupeFacet", loupeFacetDeployment.address)) as unknown as Contract,
    ),
  };

  // Cut LoupeFacet into diamond
  console.log("Performing LoupeFacet diamondCut...");
  const txLoupe = await diamond.diamondCut([loupeCut]);
  await txLoupe.wait();
  console.log("LoupeFacet diamond cut completed.");

  console.log("Setting cToken mapping...");
  await adminFacet.setCTokenAddress(addresses[+chainId].AAVE_USDC, "0xF155Bbd3359639B2Cf00F1181099B17e87A89a91");
  console.log("CToken mapping set successfully.");

  console.log("Setting Aave Pool address...");
  await adminFacet.setAavePoolAddress(addresses[+chainId].AAVE_POOL);
  console.log("Aave Pool set successfully.");

  // 7. (Optional) Set Threshold
  console.log("Setting request threshold...");
  await adminFacet.setRequestThreshold(1);
  console.log("Request threshold set successfully.");

  /*   // Optional: Verify contracts
  console.info("\nSubmitting verification requests on Etherscan...");
  await sleep(40000);

  await hre.run("verify:verify", {
    address: diamondCutFacetDeployment.address,
    contract: "contracts/confidentiality-adapters/diamond/DiamondCutFacet.sol:DiamondCutFacet",
    constructorArguments: [],
  });

  await hre.run("verify:verify", {
    address: diamondDeployment.address,
    contract: "contracts/confidentiality-adapters/diamond/Diamond.sol:Diamond",
    constructorArguments: [deployer, diamondCutFacetDeployment.address],
  });

  await hre.run("verify:verify", {
    address: supplyRequestFacetDeployment.address,
    contract: "contracts/confidentiality-adapters/aave/SupplyRequestFacet.sol:SupplyRequestFacet",
    constructorArguments: [],
  });

  console.log("All contracts verified."); */
};

export default func;
func.id = "deploy_diamond"; // unique deploy ID
func.tags = ["Diamond"];
