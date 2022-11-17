import { ethers } from "hardhat";
import type { LPRewards } from "../typechain/LPRewards";

const ADMIN_DAO = "0xF510a2Ff7e9DD7e18629137adA4eb56B9c13E885";
const KWENTA = ethers.constants.AddressZero; // @TODO
const ARRAKIS_VAULT_TOKEN = ethers.constants.AddressZero; // @TODO

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    const LPRewards = await ethers.getContractFactory(
        "synthetix/contracts/StakingRewards.sol:StakingRewards"
    );
    const lpRewards = (await LPRewards.deploy(
        ADMIN_DAO, // Owner
        ADMIN_DAO, // RewardsDistribution (Owner)
        KWENTA, // RewardsToken (Kwenta)
        ARRAKIS_VAULT_TOKEN // StakingToken (Arrakis KWENTA/ETH LP Position)
    )) as LPRewards;

    await lpRewards.deployed();

    console.log("StakingRewards deployed to:", lpRewards.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
