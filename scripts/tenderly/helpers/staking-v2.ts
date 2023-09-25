/************************************************
 * @ownership
 ************************************************/

import { ethers } from "hardhat";
import { Contract, BigNumber } from "ethers";
import {
    OPTIMISM_SUPPLY_SCHEDULE,
    OPTIMISM_PDAO,
    OPTIMISM_REWARD_ESCROW_V1,
    OPTIMISM_KWENTA_TOKEN,
    OPTIMISM_TREASURY_DAO,
    STAKING_V1_USER,
    YEAR_IN_WEEKS,
    provider,
} from "./constants";
import {
    extendLog,
    sendTransaction,
    logTransaction,
    deployUUPSProxy,
    deployContract,
    printEntries,
    getLatestBlockTimestamp,
} from "./helpers";

/************************************************
 * @mutators
 ************************************************/

export const transferOwnership = async (
    contract: Contract,
    contractName: string,
    to: string
) => {
    await contract.transferOwnership(to);
    console.log(extendLog(`${contractName}: owner address set to:`), to);

    await sendTransaction({
        contractName: contractName,
        contractAddress: contract.address,
        functionName: "acceptOwnership",
        functionArgs: [],
        from: to,
    });
    console.log(extendLog(`${contractName}: ownership accepted by:`), to);
};

export const createV1EscrowEntries = async ({
    numToCreate,
    recipientAddress,
}: {
    numToCreate: number;
    recipientAddress: string;
}) => {
    await sendTransaction({
        contractName: "Kwenta",
        contractAddress: OPTIMISM_KWENTA_TOKEN,
        functionName: "approve",
        functionArgs: [OPTIMISM_REWARD_ESCROW_V1, ethers.constants.MaxUint256],
        from: OPTIMISM_TREASURY_DAO,
    });

    for (let i = 0; i < numToCreate; i++) {
        await sendTransaction({
            contractName: "RewardEscrow",
            contractAddress: OPTIMISM_REWARD_ESCROW_V1,
            functionName: "createEscrowEntry",
            functionArgs: [
                recipientAddress,
                ethers.utils.parseEther("1"),
                YEAR_IN_WEEKS,
            ],
            from: OPTIMISM_TREASURY_DAO,
        });
    }
};

/************************************************
 * @setters
 ************************************************/

export const setStakingRewardsOnSupplySchedule = async (
    rewardsNotifier: string
) => {
    const contractName = "SupplySchedule";
    const functionName = "setStakingRewards";
    const functionArgs = [rewardsNotifier];

    await sendTransaction({
        contractName,
        contractAddress: OPTIMISM_SUPPLY_SCHEDULE,
        functionName,
        functionArgs,
        from: OPTIMISM_PDAO,
    });

    logTransaction(contractName, functionName, functionArgs);
};

export const setTreasuryDAOOnRewardEscrowV1 = async (
    escrowMigrator: string
) => {
    const contractName = "RewardEscrow";
    const functionName = "setTreasuryDAO";
    const functionArgs = [escrowMigrator];

    await sendTransaction({
        contractName,
        contractAddress: OPTIMISM_REWARD_ESCROW_V1,
        functionName,
        functionArgs,
        from: OPTIMISM_PDAO,
    });

    logTransaction(contractName, functionName, functionArgs);
};

/************************************************
 * @deployers
 ************************************************/

export const deployRewardsNotifier = async (owner: string) =>
    await deployContract({
        contractName: "StakingRewardsNotifier",
        constructorArgs: [
            owner,
            OPTIMISM_KWENTA_TOKEN,
            OPTIMISM_SUPPLY_SCHEDULE,
        ],
    });

export const deployRewardEscrowV2 = async (
    owner: string,
    rewardsNotifier: string
) =>
    await deployUUPSProxy({
        contractName: "RewardEscrowV2",
        constructorArgs: [OPTIMISM_KWENTA_TOKEN, rewardsNotifier],
        initializerArgs: [owner],
    });

export const deployStakingRewardsV2 = async (
    owner: string,
    rewardEscrowV2: string,
    rewardsNotifier: string
) =>
    await deployUUPSProxy({
        contractName: "StakingRewardsV2",
        constructorArgs: [
            OPTIMISM_KWENTA_TOKEN,
            rewardEscrowV2,
            rewardsNotifier,
        ],
        initializerArgs: [owner],
    });

export const deployEscrowMigrator = async (
    owner: string,
    rewardEscrowV2: string,
    stakingRewardsV2: string
) =>
    await deployUUPSProxy({
        contractName: "EscrowMigrator",
        constructorArgs: [
            OPTIMISM_KWENTA_TOKEN,
            OPTIMISM_REWARD_ESCROW_V1,
            rewardEscrowV2,
            stakingRewardsV2,
        ],
        initializerArgs: [owner, OPTIMISM_TREASURY_DAO],
    });

/************************************************
 * @simulator
 ************************************************/

export const advanceToNextRewardsEmission = async () => {
    console.log("\n🕣 Update time...");

    const supplySchedule = await ethers.getContractAt(
        "SupplySchedule",
        OPTIMISM_SUPPLY_SCHEDULE
    );

    const timeNow = await getLatestBlockTimestamp();
    const timeOfLastMint = (await supplySchedule.lastMintEvent()).toNumber();
    const mintPeriodDuration = (
        await supplySchedule.MINT_PERIOD_DURATION()
    ).toNumber();
    const timeOfNextMint = timeOfLastMint + mintPeriodDuration;
    const timeToNextMint = timeOfNextMint - timeNow;

    if (timeToNextMint > 0) {
        const params = [
            ethers.utils.hexValue(timeToNextMint + 1), // hex encoded number of seconds
        ];
        await provider.send("evm_increaseTime", params);
        console.log(
            "Days fast forwarded:                                 ",
            timeToNextMint / 60 / 60 / 24
        );
        console.log(
            "Updated time to:                                     ",
            timeOfNextMint,
            new Date(timeOfNextMint * 1000)
        );

        const newTimeNow = await getLatestBlockTimestamp();
        console.log(
            "time confirmed:                                      ",
            newTimeNow,
            new Date(newTimeNow * 1000)
        );

        console.log("✅ Time updated!");
    } else {
        console.log("Time not updated");
    }
};

export const simulateMigration = async ({
    escrowMigrator,
    rewardEscrowV2,
}: {
    escrowMigrator: Contract;
    rewardEscrowV2: Contract;
}) => {
    console.log("\n🦅 Migrating entries...");

    const NUM_TO_REGISTER = 5; // estimated max = 556 (haven't tried 557)
    const NUM_TO_VEST = 5; // estimated max = 3419 (most I have tried is 1825)
    const NUM_TO_MIGRATE = 5; // last tested max = 182 (have tried 183)
    const NUM_TO_CREATE = Math.max(
        NUM_TO_REGISTER,
        NUM_TO_VEST,
        NUM_TO_MIGRATE
    );

    const rewardEscrowV1 = await ethers.getContractAt(
        "RewardEscrow",
        OPTIMISM_REWARD_ESCROW_V1
    );
    const kwenta = await ethers.getContractAt("Kwenta", OPTIMISM_KWENTA_TOKEN);

    const numberOfEntriesAlreadyCreated =
        await rewardEscrowV1.numVestingEntries(STAKING_V1_USER);

    if (NUM_TO_CREATE > numberOfEntriesAlreadyCreated) {
        await createV1EscrowEntries({
            numToCreate: NUM_TO_CREATE - numberOfEntriesAlreadyCreated,
            recipientAddress: STAKING_V1_USER,
        });
    }

    const allEntries = await rewardEscrowV1.getAccountVestingEntryIDs(
        STAKING_V1_USER,
        0,
        NUM_TO_CREATE
    );
    console.log("All entries: ");
    printEntries(allEntries);

    // register all entries
    const entriesToRegister: BigNumber[] =
        await rewardEscrowV1.getAccountVestingEntryIDs(
            STAKING_V1_USER,
            0,
            NUM_TO_REGISTER
        );
    await sendTransaction({
        contractName: "EscrowMigrator",
        contractAddress: escrowMigrator.address,
        functionName: "registerEntries",
        functionArgs: [entriesToRegister],
        from: STAKING_V1_USER,
    });

    // vest all entries
    const entriesToVest: BigNumber[] =
        await rewardEscrowV1.getAccountVestingEntryIDs(
            STAKING_V1_USER,
            0,
            NUM_TO_VEST
        );
    await sendTransaction({
        contractName: "RewardEscrow",
        contractAddress: rewardEscrowV1.address,
        functionName: "vest",
        functionArgs: [entriesToVest],
        from: STAKING_V1_USER,
    });

    // approve escrow migrator
    await sendTransaction({
        contractName: "Kwenta",
        contractAddress: kwenta.address,
        functionName: "approve",
        functionArgs: [escrowMigrator.address, ethers.constants.MaxUint256],
        from: STAKING_V1_USER,
    });

    // migrate all entries
    const entriesToMigrate: BigNumber[] =
        await rewardEscrowV1.getAccountVestingEntryIDs(
            STAKING_V1_USER,
            0,
            NUM_TO_MIGRATE
        );
    await sendTransaction({
        contractName: "EscrowMigrator",
        contractAddress: escrowMigrator.address,
        functionName: "migrateEntries",
        functionArgs: [STAKING_V1_USER, entriesToMigrate],
        from: STAKING_V1_USER,
    });

    // get num of entries in reward escrow v2
    const numEntriesInRewardEscrowV2: BigNumber =
        await rewardEscrowV2.balanceOf(STAKING_V1_USER);
    console.log("StakingV1 user: ", STAKING_V1_USER);
    console.log(
        "Num of entries migrated: ",
        numEntriesInRewardEscrowV2.toString()
    );

    console.log("✅ Entries migrated!");
};
