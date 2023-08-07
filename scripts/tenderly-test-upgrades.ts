// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers, upgrades, tenderly } from "hardhat";
import { getInitializerData } from "../test/utils/helpers.ts";

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

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deployer: ", deployer.address);

    // ========== DEPLOYMENT ========== */

    console.log("\n💥 Beginning deployments...");
    const { rewardEscrowV2Proxy, rewardEscrowV2Impl } =
        await deployRewardEscrowV2();
    console.log("RewardEscrowV2 Proxy: ", rewardEscrowV2Proxy.address);
    console.log("RewardEscrowV2 Impl: ", rewardEscrowV2Impl.address);
    // console.log("StakingRewardsV2: ", stakingRewardsV2.address);
    // console.log("EscrowMigrator: ", escrowMigrator.address);
    console.log("✅ Deployments complete!");
}

const deployRewardEscrowV2 = async () => {
    // Deploy implementation
    const RewardEscrowV2 = await ethers.getContractFactory("RewardEscrowV2");
    const rewardEscrowV2Impl = await RewardEscrowV2.deploy(
        OPTIMISM_KWENTA_TOKEN
    );
    await rewardEscrowV2Impl.deployed();
    await tenderly.verify({
        name: "RewardEscrowV2",
        address: rewardEscrowV2Impl.address,
    });

    // Deploy proxy
    const ERC1967ProxyExposed = await ethers.getContractFactory(
        "ERC1967ProxyExposed"
    );
    const rewardEscrowInitializerData = getInitializerData(
        RewardEscrowV2.interface,
        [OPTIMISM_PDAO],
        undefined
    );
    const rewardEscrowV2Proxy = await ERC1967ProxyExposed.deploy(
        rewardEscrowV2Impl.address,
        rewardEscrowInitializerData
    );
    await rewardEscrowV2Proxy.deployed();
    await tenderly.verify({
        name: "ERC1967ProxyExposed",
        address: rewardEscrowV2Proxy.address,
    });
    return { rewardEscrowV2Proxy, rewardEscrowV2Impl };
};

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
