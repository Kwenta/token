const { ethers } = require("hardhat");

/**
 * Deploy a contract by name without constructor arguments
 */
async function deploy(contractName) {
  let Contract = await ethers.getContractFactory(contractName);
  return await Contract.deploy();
}

/**
 * Deploy a contract by name with constructor arguments
 */
async function deployArgs(contractName, ...args) {
  let Contract = await ethers.getContractFactory(contractName);
  return await Contract.deploy(...args);
}

/**
 * Deploy a contract with abi
 */
async function deployWithAbi(contract, deployer, ...args) {
  let Factory = new ethers.ContractFactory(
    contract.abi,
    contract.bytecode,
    deployer
  );
  return await Factory.deploy(...args);
}

module.exports = {
  deploy,
  deployArgs,
  deployWithAbi,
};
