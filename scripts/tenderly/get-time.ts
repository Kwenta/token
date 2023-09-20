// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
import { getLatestBlockTimestamp, timeLog } from "./helpers/helpers";
import { OPTIMISM_SUPPLY_SCHEDULE } from "./helpers/constants";

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
