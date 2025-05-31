import Pool from "@aave/core-v3/artifacts/contracts/protocol/pool/Pool.sol/Pool.json";
import { createInstance as createFhevmInstance } from "fhevmjs";
import { task } from "hardhat/config";

import addresses from "../../../config/addresses";
import { GATEWAY_URL } from "../../../config/constants";

task("getSuppliedBalance", "Get user's supplied balance from adapter")
  .addParam("signeraddress", "Signer address")
  .addOptionalParam("diamondaddress", "Diamond contract address")
  .addParam("asset", "Underlying asset address")
  .addOptionalParam("address", "User Address")
  .setAction(async ({ signeraddress, diamondaddress, asset, address }, hre) => {
    const { ethers, getChainId, deployments } = hre;
    const chainId = await getChainId();
    const signer = await ethers.getSigner(signeraddress);

    if (!addresses[+chainId]) {
      throw new Error("Chain ID not supported");
    }

    if (!diamondaddress) {
      diamondaddress = (await deployments.get("Diamond")).address;
    }

    if (!address) {
      address = signer.address;
    }

    const instance = await createFhevmInstance({
      kmsContractAddress: addresses[+chainId].KMSVERIFIER,
      aclContractAddress: addresses[+chainId].ACL,
      networkUrl: hre.network.config.url,
      gatewayUrl: GATEWAY_URL,
    });

    const { publicKey, privateKey } = instance.generateKeypair();
    const eip712 = instance.createEIP712(publicKey, diamondaddress);
    const signature = await signer.signTypedData(eip712.domain, { Reencrypt: eip712.types.Reencrypt }, eip712.message);

    const adapter = await ethers.getContractAt("GetterFacet", diamondaddress, signer);

    const encryptedBalance = await adapter.getSuppliedBalance(address, asset);

    console.info("Encrypted supplied balance:", encryptedBalance);

    const userBalance = await instance.reencrypt(
      encryptedBalance,
      privateKey,
      publicKey,
      signature,
      diamondaddress,
      address,
    );

    console.log("Decrypted supplied balance:", userBalance);

    const aavePool = await ethers.getContractAt(Pool.abi, addresses[+chainId].AAVE_POOL, signer);
    const normalizedBalance: bigint = await aavePool.getReserveNormalizedIncome(asset);

    console.log("Reserve normalized income:", normalizedBalance);
    const suppliedBalance = (userBalance * normalizedBalance) / BigInt(1e27);

    console.log("Supplied balance (normalized):", suppliedBalance.toString());
  });

task("getMaxBorrowable", "Get user's max borrowable amount from adapter")
  .addParam("signeraddress", "Signer address")
  .addParam("asset", "Underlying asset address")
  .addOptionalParam("diamondaddress", "Diamond contract address")
  .addOptionalParam("address", "User Address")
  .setAction(async ({ signeraddress, asset, diamondaddress, address }, hre) => {
    const { ethers, getChainId, deployments } = hre;
    const chainId = await getChainId();
    const signer = await ethers.getSigner(signeraddress);

    if (!addresses[+chainId]) {
      throw new Error("Chain ID not supported");
    }

    if (!diamondaddress) {
      diamondaddress = (await deployments.get("Diamond")).address;
    }

    if (!address) {
      address = signer.address;
    }

    const instance = await createFhevmInstance({
      kmsContractAddress: addresses[+chainId].KMSVERIFIER,
      aclContractAddress: addresses[+chainId].ACL,
      networkUrl: hre.network.config.url,
      gatewayUrl: GATEWAY_URL,
    });

    const { publicKey, privateKey } = instance.generateKeypair();
    const eip712 = instance.createEIP712(publicKey, diamondaddress);
    const signature = await signer.signTypedData(eip712.domain, { Reencrypt: eip712.types.Reencrypt }, eip712.message);

    const adapter = await ethers.getContractAt("GetterFacet", diamondaddress, signer);

    const encryptedBalance = await adapter.getMaxBorrowable(address, asset);

    console.info("Encrypted max borrowable amount:", encryptedBalance);

    const userBalance = await instance.reencrypt(
      encryptedBalance,
      privateKey,
      publicKey,
      signature,
      diamondaddress,
      address,
    );

    console.log("Decrypted max borrowable amount:", userBalance);
  });

task("getWithdrawableAmount", "Get user's withdrawable amount from adapter")
  .addParam("signeraddress", "Signer address")
  .addOptionalParam("diamondaddress", "Diamond contract address")
  .addParam("asset", "Underlying asset address")
  .addOptionalParam("address", "User Address")
  .setAction(async ({ signeraddress, diamondaddress, asset, address }, hre) => {
    const { ethers, getChainId, deployments } = hre;
    const chainId = await getChainId();
    const signer = await ethers.getSigner(signeraddress);

    if (!addresses[+chainId]) {
      throw new Error("Chain ID not supported");
    }

    if (!diamondaddress) {
      diamondaddress = (await deployments.get("Diamond")).address;
    }

    if (!address) {
      address = signer.address;
    }

    const instance = await createFhevmInstance({
      kmsContractAddress: addresses[+chainId].KMSVERIFIER,
      aclContractAddress: addresses[+chainId].ACL,
      networkUrl: hre.network.config.url,
      gatewayUrl: GATEWAY_URL,
    });

    const { publicKey, privateKey } = instance.generateKeypair();
    const eip712 = instance.createEIP712(publicKey, diamondaddress);
    const signature = await signer.signTypedData(eip712.domain, { Reencrypt: eip712.types.Reencrypt }, eip712.message);

    const adapter = await ethers.getContractAt("GetterFacet", diamondaddress, signer);

    // Get both balances
    const encryptedSupplied = await adapter.getSuppliedBalance(address, asset);
    const encryptedDebt = await adapter.getScaledDebt(address, asset);

    // Decrypt both
    const suppliedBalance = await instance.reencrypt(
      encryptedSupplied,
      privateKey,
      publicKey,
      signature,
      diamondaddress,
      address,
    );

    const debtBalance = await instance.reencrypt(
      encryptedDebt,
      privateKey,
      publicKey,
      signature,
      diamondaddress,
      address,
    );

    // Calculate withdrawable off-chain
    let withdrawableBalance = suppliedBalance - debtBalance;
    if (withdrawableBalance < 0) withdrawableBalance = 0;

    console.log("Withdrawable scaled balance:", withdrawableBalance);
  });

task("getScaledDebt", "Get user's scaled debt from adapter")
  .addParam("signeraddress", "Signer address")
  .addOptionalParam("diamondaddress", "Diamond contract address")
  .addParam("asset", "Underlying asset address")
  .addOptionalParam("address", "User Address")
  .setAction(async ({ signeraddress, diamondaddress, asset, address }, hre) => {
    const { ethers, getChainId, deployments } = hre;
    const chainId = await getChainId();
    const signer = await ethers.getSigner(signeraddress);

    if (!addresses[+chainId]) {
      throw new Error("Chain ID not supported");
    }

    if (!diamondaddress) {
      diamondaddress = (await deployments.get("Diamond")).address;
    }

    if (!address) {
      address = signer.address;
    }

    const instance = await createFhevmInstance({
      kmsContractAddress: addresses[+chainId].KMSVERIFIER,
      aclContractAddress: addresses[+chainId].ACL,
      networkUrl: hre.network.config.url,
      gatewayUrl: GATEWAY_URL,
    });

    const { publicKey, privateKey } = instance.generateKeypair();
    const eip712 = instance.createEIP712(publicKey, diamondaddress);
    const signature = await signer.signTypedData(eip712.domain, { Reencrypt: eip712.types.Reencrypt }, eip712.message);

    const adapter = await ethers.getContractAt("GetterFacet", diamondaddress, signer);

    const encryptedDebt = await adapter.getScaledDebt(address, asset);

    console.info("Encrypted scaled debt:", encryptedDebt);

    const userBalance = await instance.reencrypt(
      encryptedDebt,
      privateKey,
      publicKey,
      signature,
      diamondaddress,
      address,
    );

    console.log("Decrypted scaled debt:", userBalance);

    const aavePool = await ethers.getContractAt(Pool.abi, addresses[+chainId].AAVE_POOL, signer);
    const normalizedBalance: bigint = await aavePool.getReserveNormalizedVariableDebt(asset);

    console.log("Reserve normalized variable debt:", normalizedBalance);
    const scaledDebt = (userBalance * normalizedBalance) / BigInt(1e27);
    console.log("Scaled debt (normalized):", scaledDebt.toString());
  });
