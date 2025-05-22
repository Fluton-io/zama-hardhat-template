import { Contract } from "ethers";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { getSelectors } from "./getSelectors";

const facetName = process.env.FACET_NAME || "BorrowFacet";
const diamondAddress = process.env.DIAMOND_ADDRESS || "0xc516013704be88936D97Fe4eF72871148D9759Da";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const chainId = await hre.getChainId();
  const { deploy } = hre.deployments;

  console.log(`Deploying ${facetName} with ${deployer} on chainId: ${chainId}`);

  const facetDeployment = await deploy(facetName, {
    from: deployer,
    log: true,
  });
  console.log(`${facetName} deployed at: ${facetDeployment.address}`);

  const diamond = await hre.ethers.getContractAt("Diamond", diamondAddress);
  const facetContract = (await hre.ethers.getContractAt(facetName, facetDeployment.address)) as unknown as Contract;

  const loupe = await hre.ethers.getContractAt("DiamondLoupeFacet", diamondAddress);
  const existingFacets = await loupe.facets();

  const existingSelectors = existingFacets.flatMap((f) => f.functionSelectors);
  const facetSelectors = getSelectors(facetContract);

  const selectorsToAdd: string[] = [];
  const selectorsToReplace: string[] = [];

  for (const selector of facetSelectors) {
    if (existingSelectors.includes(selector)) {
      selectorsToReplace.push(selector);
    } else {
      selectorsToAdd.push(selector);
    }
  }

  if (selectorsToAdd.length) {
    console.log(`Adding selectors for ${facetName}:`, selectorsToAdd);
    const cutAdd = [
      {
        facetAddress: facetDeployment.address,
        action: 0, // Add
        functionSelectors: selectorsToAdd,
      },
    ];
    const txAdd = await diamond.diamondCut(cutAdd, { gasLimit: 800000 });
    await txAdd.wait();
    console.log(`Added selectors for ${facetName}.`);
  }

  if (selectorsToReplace.length) {
    console.log(`Replacing selectors for ${facetName}:`, selectorsToReplace);
    const cutReplace = [
      {
        facetAddress: facetDeployment.address,
        action: 1, // Replace
        functionSelectors: selectorsToReplace,
      },
    ];
    const txReplace = await diamond.diamondCut(cutReplace, { gasLimit: 800000 });
    await txReplace.wait();
    console.log(`Replaced selectors for ${facetName}.`);
  }

  if (!selectorsToAdd.length && !selectorsToReplace.length) {
    console.log(`Nothing to add or replace for ${facetName}. Everything is up to date.`);
  }
};

export default func;
func.id = "deploy_single_facet_dynamic";
func.tags = ["SingleFacet"];
