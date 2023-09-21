// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
import {
    OPTIMISM_TREASURY_DAO,
    OPTIMISM_PDAO,
    OPTIMISM_SUPPLY_SCHEDULE,
    provider,
} from "./helpers/constants";
import { getLatestBlockTimestamp } from "./helpers/helpers";
import {
    deployRewardsNotifier,
    deployRewardEscrowV2,
    deployStakingRewardsV2,
    deployEscrowMigrator,
    setStakingRewardsOnSupplySchedule,
    setTreasuryDAOOnRewardEscrowV1,
    transferOwnership,
    advanceToNextRewardsEmission,
} from "./helpers/staking-v2";

/************************************************
 * @main
 ************************************************/

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deployer: ", deployer.address);

    // ========== DEPLOYMENT ========== */

    console.log("\n💥 Beginning deployments...");
    const rewardsNotifier = await deployRewardsNotifier(deployer.address);
    const [rewardEscrowV2, rewardEscrowV2Impl] = await deployRewardEscrowV2(
        deployer.address,
        rewardsNotifier.address
    );
    const [stakingRewardsV2, stakingRewardsV2Impl] =
        await deployStakingRewardsV2(
            deployer.address,
            rewardEscrowV2.address,
            rewardsNotifier.address
        );
    const [escrowMigrator, escrowMigratorImpl] = await deployEscrowMigrator(
        deployer.address,
        rewardEscrowV2.address,
        stakingRewardsV2.address
    );
    console.log("StakingRewardsNotifier :", rewardsNotifier.address);
    console.log("RewardEscrowV2 Proxy   :", rewardEscrowV2.address);
    console.log("RewardEscrowV2 Impl    :", rewardEscrowV2Impl.address);
    console.log("StakingRewardsV2 Proxy :", stakingRewardsV2.address);
    console.log("StakingRewardsV2 Impl  :", stakingRewardsV2Impl.address);
    console.log("EscrowMigrator Proxy   :", escrowMigrator.address);
    console.log("EscrowMigrator Impl    :", escrowMigratorImpl.address);

    console.log("✅ Deployments complete!");

    // ========== SETTERS ========== */

    console.log("\n🔩 Configuring setters...");
    // set treasuryDAO for reward escrow v2
    await rewardEscrowV2.setTreasuryDAO(OPTIMISM_TREASURY_DAO);
    console.log(
        "RewardEscrowV2: treasuryDAO address set to:              ",
        await rewardEscrowV2.treasuryDAO()
    );

    // set staking rewards for reward escrow v2
    await rewardEscrowV2.setStakingRewards(stakingRewardsV2.address);
    console.log(
        "RewardEscrowV2: stakingRewards address set to:           ",
        await rewardEscrowV2.stakingRewards()
    );

    // set escrow migrator for reward escrow v2
    await rewardEscrowV2.setEscrowMigrator(escrowMigrator.address);
    console.log(
        "RewardEscrowV2: escrowMigrator address set to:           ",
        await rewardEscrowV2.escrowMigrator()
    );

    // set staking rewards for rewards notifier
    await rewardsNotifier.setStakingRewardsV2(stakingRewardsV2.address);
    console.log(
        "StakingRewardsNotifier: stakingRewardsV2 address set to: ",
        await rewardsNotifier.stakingRewardsV2()
    );

    // Give up rewards notifier ownership now that StakingRewardsV2 is set
    await rewardsNotifier.renounceOwnership();
    console.log("Renounced StakingRewardsNotifier ownership");

    console.log("✅ Setters set!");

    // ========== MIGRATION ========== */

    console.log("\n🔩 Migration setters...");

    await setStakingRewardsOnSupplySchedule(rewardsNotifier.address);
    await setTreasuryDAOOnRewardEscrowV1(escrowMigrator.address);
    await escrowMigrator.unpauseEscrowMigrator();

    console.log("✅ Migration setters set!");

    // ========== OWNERSHIP ========== */

    console.log("\n🔐 Ownership transfers...");

    await transferOwnership(rewardEscrowV2, "RewardEscrowV2", OPTIMISM_PDAO);
    await transferOwnership(
        stakingRewardsV2,
        "StakingRewardsV2",
        OPTIMISM_PDAO
    );
    await transferOwnership(escrowMigrator, "EscrowMigrator", OPTIMISM_PDAO);

    console.log("✅ Ownership transferred!");

    // ========== ADVANCE TIME ========== */

    await advanceToNextRewardsEmission();

    // ========== MIGRATE ========== */

    // await simulateMigration({
    //     escrowMigrator,
    //     rewardEscrowV2,
    // });
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
