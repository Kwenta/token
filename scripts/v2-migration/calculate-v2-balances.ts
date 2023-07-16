import { ethers } from "hardhat";
const data = require("./migration-transactions.json");

const totalSupply = 3519169475638094792106; // 3_519 KWENTA
const totalEscrowedBalance = 797126868540386926; // 0.7971 KWENTA
const totalKwentaInStakingRewardsV2 = 7808422413473944539139; // 7808 KWENTA
const totalStakedEscrow = 455395557014486600 // 0.4553 KWENTA
const mintedToStakingRewardsV2 = 4290530229572642102152 // 4290 KWENTA
const liquidStakedKwenta = 3518714080081080305506 // 3518 KWENTA

const kwentaThatCanBeClaimed = 4289708333392864233633;
const rewardsLost = mintedToStakingRewardsV2 - kwentaThatCanBeClaimed; // 821896179777868519 // 0.8218 KWENTA

async function main() {
    console.log("💻 Running calculations on local data...");
    const addressesWhoGotRewards: string[] = printInitialData();
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

    let totalStakedEscrow = 0;

    for (const claimer of addressesWhoGotRewards) {
        const escrowedBalanceOf = await (
            await stakingRewardsV2.escrowedBalanceOf(claimer)
        ).toString();
        totalStakedEscrow += Number(escrowedBalanceOf);
    }

    console.log("Total V2 Staked Escrow: ", totalStakedEscrow);

    console.log("📝 Manually collected/curated data:");
    console.log("Total KWENTA in StakingRewardsV2: 7_808 KWENTA");
    console.log("Total KWENTA liquid staked in  StakingRewardsV2: 3_518 KWENTA");
    console.log("Total KWENTA minted to StakingRewardsV2: 4_290 KWENTA");
    console.log("Total KWENTA in RewardEscrowV2: 0.7971 KWENTA");
    console.log("Total KWENTA escrow staked in RewardEscrowV2 0.4553 KWENTA");
}

function printInitialData(): string[] {
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

    return Object.keys(addressesWhoGotRewards);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
