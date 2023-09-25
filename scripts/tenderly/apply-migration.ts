// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
import {
    OPTIMISM_PDAO,
    OPTIMISM_STAKING_REWARDS_NOTIFIER,
    OPTIMISM_ESCROW_MIGRATOR,
    OPTIMISM_STAKING_REWARDS_V2,
    OPTIMISM_REWARD_ESCROW_V2,
} from "./helpers/constants";
import { sendTransaction } from "./helpers/helpers";
import {
    setStakingRewardsOnSupplySchedule,
    setTreasuryDAOOnRewardEscrowV1,
    advanceToNextRewardsEmission,
} from "./helpers/staking-v2";

/************************************************
 * @main
 ************************************************/

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deployer: ", deployer.address);

    // ========== MIGRATION ========== */

    console.log("\n🔩 Migration setters...");

    await setStakingRewardsOnSupplySchedule(OPTIMISM_STAKING_REWARDS_NOTIFIER);
    await setTreasuryDAOOnRewardEscrowV1(OPTIMISM_ESCROW_MIGRATOR);

    console.log("✅ Migration setters set!");

    console.log("\n🏇 Unpausing contracts...");

    await sendTransaction({
        contractName: "EscrowMigrator",
        contractAddress: OPTIMISM_ESCROW_MIGRATOR,
        functionName: "unpauseEscrowMigrator",
        functionArgs: [],
        from: OPTIMISM_PDAO,
    });

    console.log("Unpaused EscrowMigrator");

    await sendTransaction({
        contractName: "StakingRewardsV2",
        contractAddress: OPTIMISM_STAKING_REWARDS_V2,
        functionName: "unpauseStakingRewards",
        functionArgs: [],
        from: OPTIMISM_PDAO,
    });

    console.log("Unpaused StakingRewardsV2");

    await sendTransaction({
        contractName: "RewardEscrowV2",
        contractAddress: OPTIMISM_REWARD_ESCROW_V2,
        functionName: "unpauseRewardEscrow",
        functionArgs: [],
        from: OPTIMISM_PDAO,
    });

    console.log("Unpaused RewardEscrowV2");

    console.log("✅ Contracts unpaused!");

    // ========== ADVANCE TIME ========== */

    await advanceToNextRewardsEmission();
}

/************************************************
 * @execute
 ************************************************/

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
