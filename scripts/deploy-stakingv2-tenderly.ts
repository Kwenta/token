// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers, tenderly } from "hardhat";
import { Interface } from "@ethersproject/abi";

const OPTIMISM_KWENTA_TOKEN = "0x920Cf626a271321C151D027030D5d08aF699456b";
const OPTIMISM_PDAO = "0xe826d43961a87fBE71C91d9B73F7ef9b16721C07";
const OPTIMISM_STAKING_REWARDS_V1 =
    "0x6e56A5D49F775BA08041e28030bc7826b13489e0";
const OPTIMISM_REWARD_ESCROW_V1 = "0x1066A8eB3d90Af0Ad3F89839b974658577e75BE2";
const OPTIMISM_SUPPLY_SCHEDULE = "0x3e8b82326Ff5f2f10da8CEa117bD44343ccb9c26";
const OPTIMISM_TREASURY_DAO = "0x82d2242257115351899894eF384f779b5ba8c695";

const provider = new ethers.providers.JsonRpcProvider(
    process.env.TENDERLY_FORK_URL
);

/************************************************
 * @main
 ************************************************/

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deployer: ", deployer.address);

    // ========== DEPLOYMENT ========== */

    console.log("\n💥 Beginning deployments...");
    const [rewardEscrowV2, rewardEscrowV2Impl] = await deployRewardEscrowV2(
        deployer.address
    );
    const [stakingRewardsV2, stakingRewardsV2Impl] =
        await deployStakingRewardsV2(deployer.address, rewardEscrowV2.address);
    const [escrowMigrator, escrowMigratorImpl] = await deployEscrowMigrator(
        deployer.address,
        rewardEscrowV2.address,
        stakingRewardsV2.address
    );
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
    // TODO: rewardEscrowV2.setTreasuryDAO is not a function - return implementation contract wrapped around proxy contract address
    // instead of actual proxy contract
    await rewardEscrowV2.setTreasuryDAO(OPTIMISM_TREASURY_DAO);
    console.log(
        "RewardEscrowV2: treasuryDAO address set to:          ",
        await rewardEscrowV2.treasuryDAO()
    );

    // set staking rewards for reward escrow v2
    await rewardEscrowV2.setStakingRewards(stakingRewardsV2.address);
    console.log(
        "RewardEscrowV2: stakingRewards address set to:          ",
        await rewardEscrowV2.stakingRewards()
    );

    // set escrow migrator for reward escrow v2
    await rewardEscrowV2.setEscrowMigrator(escrowMigrator.address);
    console.log(
        "RewardEscrowV2: escrowMigrator address set to:          ",
        await rewardEscrowV2.escrowMigrator()
    );
    console.log("✅ Setters set!");

    // ========== MIGRATION ========== */

    console.log("\n🔩 Migration setters...");


    provider.send("tenderly_simulateTransaction", [
        {
            from: OPTIMISM_PDAO,
            to: OPTIMISM_SUPPLY_SCHEDULE,
            gas: "0x7a1200",
            gasPrice: "0x0",
            value: "0x0",
            data: `0x6fb83a57000000000000000000000000${remove0xFromAddress(
                rewardEscrowV2.address
            )}`,
        },
    ]);

    console.log("✅ Migration setters set!");
}

/************************************************
 * @deployers
 ************************************************/

const deployRewardEscrowV2 = async (owner: string) =>
    await deployUUPSProxy({
        contractName: "RewardEscrowV2",
        constructorArgs: [OPTIMISM_KWENTA_TOKEN],
        initializerArgs: [owner],
    });

const deployStakingRewardsV2 = async (owner: string, rewardEscrowV2: string) =>
    await deployUUPSProxy({
        contractName: "StakingRewardsV2",
        constructorArgs: [
            OPTIMISM_KWENTA_TOKEN,
            rewardEscrowV2,
            OPTIMISM_SUPPLY_SCHEDULE,
        ],
        initializerArgs: [owner],
    });

const deployEscrowMigrator = async (
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
            OPTIMISM_STAKING_REWARDS_V1,
            stakingRewardsV2,
        ],
        initializerArgs: [owner],
    });

/************************************************
 * @helpers
 ************************************************/

const deployUUPSProxy = async ({
    contractName,
    constructorArgs,
    initializerArgs,
}: {
    contractName: string;
    constructorArgs: unknown[];
    initializerArgs: unknown[];
}) => {
    const Factory = await ethers.getContractFactory(contractName);
    const implementation = await Factory.deploy(...constructorArgs);
    await implementation.deployed();
    await tenderly.verify({
        name: contractName,
        address: implementation.address,
    });

    // Deploy proxy
    const ERC1967ProxyExposed = await ethers.getContractFactory(
        "ERC1967ProxyExposed"
    );
    const initializerData = getInitializerData(
        Factory.interface,
        initializerArgs,
        undefined
    );
    const proxy = await ERC1967ProxyExposed.deploy(
        implementation.address,
        initializerData
    );
    await proxy.deployed();
    await tenderly.verify({
        name: "ERC1967ProxyExposed",
        address: proxy.address,
    });
    return [proxy, implementation];
};

export const getInitializerData = (
    contractInterface: Interface,
    args: unknown[],
    initializer?: string | false
): string => {
    if (initializer === false) {
        return "0x";
    }

    const allowNoInitialization =
        initializer === undefined && args.length === 0;
    initializer = initializer ?? "initialize";

    try {
        const fragment = contractInterface.getFunction(initializer);
        return contractInterface.encodeFunctionData(fragment, args);
    } catch (e: unknown) {
        if (e instanceof Error) {
            if (
                allowNoInitialization &&
                e.message.includes("no matching function")
            ) {
                return "0x";
            }
        }
        throw e;
    }
};

const remove0xFromAddress = (address: string): string => address.slice(-40);

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
