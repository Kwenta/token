import { ethers } from "hardhat";
const data = require("./migration-transactions.json");

async function main() {
    const [account] = await ethers.getSigners();
    console.log("Using the account:", account.address);
    console.log("Account balance:", (await account.getBalance()).toString());

    printInitialData();

    const StakingRewardsV2 = await ethers.getContractFactory(
        "StakingRewardsV2"
    );
    const stakingRewardsV2 = StakingRewardsV2.attach(
        "0xe5bB889B1f0B6B4B7384Bd19cbb37adBDDa941a6" // The deployed contract address
    );

    const totalSupply = await (await stakingRewardsV2.totalSupply()).toString();
    console.log("totalSupply: ", totalSupply);

    const escrowedBalanceOf = await (
        await stakingRewardsV2.escrowedBalanceOf(
            "0x976fdc5dfa145e3cbc690e9fef4a408642732952"
        )
    ).toString();
    console.log("escrowedBalanceOf :", escrowedBalanceOf);
}

function printInitialData() {
    const addressesWhoStaked: { [key: string]: Boolean } = {};
    const addressesWhoClaimed: { [key: string]: Boolean } = {};
    const addressesWhoCompounded: { [key: string]: Boolean } = {};
    const addressesWhoEscrowStaked: { [key: string]: Boolean } = {};
    const addressesWhoGotRewards: { [key: string]: Boolean } = {}; // Compounders and Get Rewarders

    for (let i = 0; i < data.length; i++) {
        const element = data[i];
        const method = element.Method;
        if (method == "Stake") {
            addressesWhoStaked[element.From] = true;
        }
        if (method == "Get Reward") {
            addressesWhoClaimed[element.From] = true;
        }
        if (method == "Compound") {
            addressesWhoCompounded[element.From] = true;
        }
        if (method == "Stake Escrow") {
            addressesWhoEscrowStaked[element.From] = true;
        }
        if (method == "Compound" || method == "Get Reward") {
            addressesWhoGotRewards[element.From] = true;
        }
    }

    let addressesWhoGotRewardsButDidNotStake = 0;

    for (const rewarded of Object.keys(addressesWhoGotRewards)) {
        if (!addressesWhoStaked[rewarded]) {
            addressesWhoGotRewardsButDidNotStake++;
        }
    }

    // let addressesWhoStakedButDidNotGetRewards = 0;

    // for (const staker of Object.keys(addressesWhoStaked)) {
    //     if (!addressesWhoGotRewards[staker]) {
    //         addressesWhoStakedButDidNotGetRewards++;
    //     }
    // }

    console.log("Total stakers: ", Object.keys(addressesWhoStaked).length);
    // console.log("Total claimers: ", Object.keys(addressesWhoClaimed).length);
    // console.log("Total compounders: ", Object.keys(addressesWhoCompounded).length);
    // console.log(
    //     "Total escrow stakers: ",
    //     Object.keys(addressesWhoEscrowStaked).length
    // );
    console.log(
        "Total who got rewards: ",
        Object.keys(addressesWhoGotRewards).length
    );
    console.log(
        "Total rewarded who did not stake: ",
        addressesWhoGotRewardsButDidNotStake
    );
    // console.log(
    //     "Total stakers who did not get rewards: ",
    //     addressesWhoStakedButDidNotGetRewards
    // );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
