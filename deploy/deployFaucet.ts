import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { sleep } from "../utils";

const constructorArguments = [["0x5cFe32B9B71634f1c72EF633082c52d6f41f84f7"]];

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const chainId = await hre.getChainId();
  const { deploy } = hre.deployments;

  console.log(deployer, chainId);

  const deployed = await deploy("Faucet", {
    from: deployer,
    args: constructorArguments,
    log: true,
  });

  console.log(`Faucet contract: `, deployed.address);

  const verificationArgs = {
    address: deployed.address,
    contract: "contracts/Faucet.sol:Faucet",
    constructorArguments: constructorArguments,
  };

  console.info("\nSubmitting verification request on Etherscan...");
  await sleep(30000); // wait for etherscan to index the contract
  await hre.run("verify:verify", verificationArgs);
};

export default func;
func.id = "deploy_faucet"; // id required to prevent reexecution
func.tags = ["Faucet"];
