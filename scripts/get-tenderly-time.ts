// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers, tenderly } from "hardhat";
import { Interface } from "@ethersproject/abi";
import { Contract } from "ethers";

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

    const timeNow = await getLatestBlockTimestamp();
    timeLog("timeNow", timeNow);

    const supplySchedule = await ethers.getContractAt(
        "SupplySchedule",
        OPTIMISM_SUPPLY_SCHEDULE
    );

    const timeOfLastMint = (await supplySchedule.lastMintEvent()).toNumber();
    timeLog("timeOfLastMint", timeOfLastMint);

    const mintPeriodDuration = (
        await supplySchedule.MINT_PERIOD_DURATION()
    ).toNumber();
    timeLog("mintPeriodDuration", mintPeriodDuration);

    const timeOfNextMint = timeOfLastMint + mintPeriodDuration;
    timeLog("timeOfNextMint", timeOfNextMint);

    const timeToNextMint = timeOfNextMint - timeNow;
    console.log("timeToNextMint: ", timeToNextMint);
    console.log("timeToNextMint in days: ", timeToNextMint / 60 / 60 / 24);
}

const advanceTime = async (seconds: number) => {
    const params = [
        ethers.utils.hexValue(seconds), // hex encoded number of seconds
    ];
    const res = await provider.send("evm_increaseTime", params);

    console.log("time advanced:", res);
};

const getLatestBlockTimestamp = async (): Promise<number> => {
    const currentBlock = await ethers.provider.getBlockNumber();
    const blockTimestamp = (await ethers.provider.getBlock(currentBlock))
        .timestamp;
    return blockTimestamp;
};

const timeLog = (label: string, timestamp: number) => {
    console.log(`${label}: `, timestamp, new Date(timestamp * 1000));
};

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
