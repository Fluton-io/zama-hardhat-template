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

  const supplyRequestFacetDeployment = await deploy("SupplyRequestFacet", {
    from: deployer,
    log: true,
  });
  console.log("SupplyRequestFacet deployed at:", supplyRequestFacetDeployment.address);

  const cut = {
    facetAddress: supplyRequestFacetDeployment.address,
    action: 0,
    functionSelectors: getSelectors(
      (await hre.ethers.getContractAt(
        "SupplyRequestFacet",
        supplyRequestFacetDeployment.address,
      )) as unknown as Contract,
    ),
  };

  console.log("Performing diamondCut...");
  const diamond = await hre.ethers.getContractAt("Diamond", diamondDeployment.address);
  const tx = await diamond.diamondCut(cut);
  await tx.wait();
  console.log("Diamond cut completed.");

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

  const tx2 = await diamond.diamondCut(adminCut);
  await tx2.wait();
  console.log("AdminFacet diamond cut completed.");

  const adminFacet = await hre.ethers.getContractAt("AdminFacet", diamondDeployment.address);

  console.log("Setting cToken mapping...");
  await adminFacet.setCTokenAddress(addresses[+chainId].AAVE_USDC, "0x4a644e2da7b7b3ff57afc4a50ae4bc9f4628b4a4");
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
func.tags = ["Diamond", "SupplyRequest"];
