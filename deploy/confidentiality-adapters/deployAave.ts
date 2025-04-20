import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import addresses from "../../config/addresses";
import { sleep } from "../../utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const chainId = await hre.getChainId();
  const { deploy } = hre.deployments;

  console.log(deployer, chainId);

  const constructorArguments = [
    addresses[+chainId].AAVE_POOL,
    [addresses[+chainId].AAVE_USDC], // aave usdc,
    ["0x4A644e2dA7B7b3ff57Afc4a50aE4Bc9f4628B4a4"], // cusdc,
  ];

  const deployed = await deploy("AaveConfidentialityAdapter", {
    from: deployer,
    args: constructorArguments,
    log: true,
  });

  console.log(`AaveConfidentialityAdapter contract: `, deployed.address);
  /* 
  const verificationArgs = {
    address: deployed.address,
    contract: "contracts/confidentiality-adapters/aave/AaveConfidentialityAdapter.sol:AaveConfidentialityAdapter",
    constructorArguments,
  };

  console.info("\nSubmitting verification request on Etherscan...");
  await sleep(40000); // wait for etherscan to index the contract
  await hre.run("verify:verify", verificationArgs); */
};

export default func;
func.id = "deploy_aaveConfidentialityAdapter"; // id required to prevent reexecution
func.tags = ["AaveConfidentialityAdapter"];
