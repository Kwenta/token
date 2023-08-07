// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { wei } from "@synthetixio/wei";
import { Contract } from "ethers";
import hre, { ethers, upgrades, tenderly } from "hardhat";
import { saveDeployments, verify } from "./utils";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { Interface } from "@ethersproject/abi";

const OPTIMISM_KWENTA_TOKEN = "0x920Cf626a271321C151D027030D5d08aF699456b";
const OPTIMISM_PDAO = "0xe826d43961a87fBE71C91d9B73F7ef9b16721C07";
const OPTIMISM_STAKING_REWARDS_V1 =
    "0x6e56A5D49F775BA08041e28030bc7826b13489e0";
const OPTIMISM_REWARD_ESCROW_V1 = "0x1066A8eB3d90Af0Ad3F89839b974658577e75BE2";
const OPTIMISM_SUPPLY_SCHEDULE = "0x3e8b82326Ff5f2f10da8CEa117bD44343ccb9c26";
const OPTIMISM_TREASURY_DAO = "0x82d2242257115351899894eF384f779b5ba8c695";

export function getInitializerData(
    contractInterface: Interface,
    args: unknown[],
    initializer?: string | false
): string {
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
}

const provider = new ethers.providers.JsonRpcProvider(
    process.env.TENDERLY_FORK_URL
);

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deployer: ", deployer.address);

    // ========== DEPLOYMENT ========== */

    console.log("\n💥 Beginning deployments...");

    const RewardEscrowV2 = await ethers.getContractFactory("RewardEscrowV2");

    const rewardEscrowV2Impl = await RewardEscrowV2.deploy(
        OPTIMISM_KWENTA_TOKEN
    );

    const rewardEscrowInitializerData = getInitializerData(
        RewardEscrowV2.interface,
        [OPTIMISM_PDAO],
        undefined
    );

    await rewardEscrowV2Impl.deployed();

    await tenderly.verify({
        name: "RewardEscrowV2",
        address: rewardEscrowV2Impl.address,
    });

    const ERC1967ProxyExposed = await ethers.getContractFactory(
        "ERC1967ProxyExposed"
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
}

const deployRewardEscrowV2 = async () => {
    const RewardEscrowV2Factory = await ethers.getContractFactory(
        "RewardEscrowV2"
    );
    const rewardEscrowV2 = await upgrades.deployProxy(
        RewardEscrowV2Factory,
        [OPTIMISM_PDAO],
        {
            kind: "uups",
            constructorArgs: [OPTIMISM_KWENTA_TOKEN],
        }
    );
    await rewardEscrowV2.deployed();
    return rewardEscrowV2;
};

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
