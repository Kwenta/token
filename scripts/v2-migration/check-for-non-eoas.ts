import { ethers } from "hardhat";
const data = require("./migration-transactions.json");

async function main() {
    console.log("🛜  Running calculations against remote data...");

    const [account] = await ethers.getSigners();
    console.log("Using the account:", account.address);
    console.log("Account balance:", (await account.getBalance()).toString());

    const StakingRewardsV2 = await ethers.getContractFactory(
        "StakingRewardsV2"
    );
    const stakingRewardsV2 = StakingRewardsV2.attach(
        "0xe5bB889B1f0B6B4B7384Bd19cbb37adBDDa941a6" // The deployed contract address
    );

    const code = await ethers.provider.getCode("0xe5bB889B1f0B6B4B7384Bd19cbb37adBDDa941a6");
    console.log("code of contract", code);

    console.log("-------------------");

    for (let i = 0; i < data.length; i++) {
        const element = data[i];
        const address = element.From;
        const code = await ethers.provider.getCode(address);
        console.log("code :", code);
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
