// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { wei } from "@synthetixio/wei";
import { ethers } from "hardhat";

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
      "0x82d2242257115351899894eF384f779b5ba8c695", //treasury
      wei(313373).mul(.05).toBN()
    );

  await vKwenta.deployed();

  console.log("vKWENTA token deployed to:", vKwenta.address);
  console.log("Total supply is: ", wei(await vKwenta.totalSupply(), 18, true).toString());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
