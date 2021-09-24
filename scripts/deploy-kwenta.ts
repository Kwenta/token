// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
const { setTargetAddress } = require("./snx-data/utils.js");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const networkObj = await ethers.provider.getNetwork();
  const network = networkObj.name;

  const ERC20 = await ethers.getContractFactory("ERC20");
  const kwenta = await ERC20.deploy("Kwenta", "KWENTA");

  await kwenta.deployed();
  // update deployments.json file for the distribution
  setTargetAddress("Kwenta", network, kwenta.address);

  console.log("KWENTA token deployed to:", kwenta.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
