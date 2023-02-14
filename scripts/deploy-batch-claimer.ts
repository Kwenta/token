import { ethers } from "hardhat";
import { saveDeployments, verify } from "./utils";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    await deployBatchClaimer();
}

async function deployBatchClaimer() {
    const BatchClaimer = await ethers.getContractFactory(
        "BatchClaimer"
    );
    const batchClaimer = await BatchClaimer.deploy();
    await batchClaimer.deployed();
    await saveDeployments(
        "BatchClaimer",
        batchClaimer
    );
    console.log(
        "BatchClaimer deployed to:        ",
        batchClaimer.address
    );

    await verify(
        batchClaimer.address,
        [],
        "contracts/misc/BatchClaimer.sol:BatchClaimer" // to prevent bytecode clashes with contracts-exposed versions
    );

    return batchClaimer;
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
