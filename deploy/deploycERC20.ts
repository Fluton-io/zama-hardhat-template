import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import addresses from "../config/addresses";
import { sleep } from "../utils";

const decryptionDelay = 30;

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const chainId = await hre.getChainId();
  const { deploy } = hre.deployments;

  console.log(deployer, chainId);

  if (!addresses[+chainId]) {
    throw new Error(`No addresses found for chainId ${chainId}`);
  }

  const deployed = await deploy("cUSDC", {
    from: deployer,
    args: [addresses[+chainId].USDC, decryptionDelay],
    log: true,
  });

  console.log(`cUSDC contract: `, deployed.address);

  const verificationArgs = {
    address: deployed.address,
    contract: "contracts/cERC20.sol:cUSDC",
    constructorArguments: [addresses[+chainId].USDC, decryptionDelay],
  };

  console.info("\nSubmitting verification request on Etherscan...");
  await sleep(30000); // wait for etherscan to index the contract
  await hre.run("verify:verify", verificationArgs);
};

export default func;
func.id = "deploy_cERC20"; // id required to prevent reexecution
func.tags = ["cERC20"];
