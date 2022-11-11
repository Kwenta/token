// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { wei } from "@synthetixio/wei";
import { BigNumber, Contract } from "ethers";
import hre, { ethers } from "hardhat";
import { saveDeployments } from "../utils";

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

    const Kwenta = await ethers.getContractFactory("Kwenta");
    const kwenta = Kwenta.attach("0xDA0C33402Fc1e10d18c532F0Ed9c1A6c5C9e386C");

    // We get the contract to deploy
    const vKwentaFactory = await ethers.getContractFactory("vKwenta");
    const vKwenta = await vKwentaFactory.deploy(
        "vKwenta",
        "vKWENTA",
        "0xC2ecD777d06FFDF8B3179286BEabF52B67E9d991", //treasury
        wei(313373).mul(0.05).toBN()
    );

    await vKwenta.deployed();
    await saveDeployments("vKwenta", vKwenta);
    await verify(
        vKwenta.address,
        [
            "vKwenta",
            "vKWENTA",
            "0xC2ecD777d06FFDF8B3179286BEabF52B67E9d991", //treasury
            wei(313373).mul(0.05).toBN(),
        ],
        "contracts/vKwenta.sol:vKwenta"
    );

    await deployvKwentaRedeemer(vKwenta, kwenta);

    console.log("vKWENTA token deployed to:", vKwenta.address);
    console.log(
        "Total supply is: ",
        wei(await vKwenta.totalSupply(), 18, true).toString()
    );
}

async function deployvKwentaRedeemer(vKwenta: Contract, kwenta: Contract) {
    const VKwentaRedeemer = await ethers.getContractFactory("vKwentaRedeemer");
    const vKwentaRedeemer = await VKwentaRedeemer.deploy(
        vKwenta.address,
        kwenta.address
    );
    await vKwentaRedeemer.deployed();
    await saveDeployments("vKwentaRedeemer", vKwentaRedeemer);
    console.log("vKwentaRedeemer deployed to:       ", vKwentaRedeemer.address);

    await verify(
        vKwentaRedeemer.address,
        [vKwenta.address, kwenta.address],
        "contracts/vKwentaRedeemer.sol:vKwentaRedeemer" // to prevent bytecode clashes with contracts-exposed versions
    );

    return vKwentaRedeemer;
}

type ConstructorArgs = string | BigNumber;
async function verify(
    address: string,
    constructorArgs: Array<ConstructorArgs>,
    contract?: string
) {
    try {
        await hre.run("verify:verify", {
            address: address,
            constructorArguments: constructorArgs,
            contract: contract,
            noCompile: true,
        });
    } catch (e) {
        // Can error out even if already verified
        // We don't want this to halt execution
        console.log(e);
    }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
