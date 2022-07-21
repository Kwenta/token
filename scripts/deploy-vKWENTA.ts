// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { wei } from "@synthetixio/wei";
import { Contract } from "ethers";
import hre, { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const vKwentaFactory = await ethers.getContractFactory("vKwenta");
  const vKwenta = await vKwentaFactory.deploy(
      "vKwenta", 
      "vKWENTA", 
      "0x652c46a302060B324A02d2d3e4a56e3DA07FA91b", //treasury
      wei(313373).mul(.05).toBN()
    );

  await vKwenta.deployed();

  saveDeployments('vKwenta', vKwenta);
  console.log("vKWENTA token deployed to:", vKwenta.address);
  console.log("Total supply is: ", wei(await vKwenta.totalSupply(), 18, true).toString());
}

async function saveDeployments(name: string, contract: Contract) {
  // For hardhat-deploy plugin to save deployment artifacts
  const { deployments } = hre;
  const { save } = deployments;

  const artifact = await deployments.getExtendedArtifact(name);
  let deployment = {
      address: contract.address,
      ...artifact,
  };

  await save(name, deployment);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
