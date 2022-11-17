import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Contract } from "ethers";
import { ethers } from "hardhat";

// core contracts
let kwenta: Contract;
let supplySchedule: Contract;
let rewardEscrow: Contract;
let stakingRewards: Contract;

/**
 * Deploys core contracts
 * @dev Libraries that the core contracts depend on are also deployed, but not returned
 * @param NAME: token name (ex: kwenta)
 * @param SYMBOL: symbol of token (ex: KWENTA)
 * @param INITIAL_SUPPLY: number of tokens
 * @param owner: EOA used to deploy contracts
 * @param TREASURY_DAO: contract address of TREASURY
 * @returns kwenta, supplySchedule, rewardEscrow, stakingRewardsProxy
 */
export const deployKwenta = async (
    NAME: string,
    SYMBOL: string,
    INITIAL_SUPPLY: BigNumber,
    owner: SignerWithAddress,
    TREASURY_DAO: SignerWithAddress
) => {
    // deploy SafeDecimalMath
    const SafeDecimalMath = await ethers.getContractFactory("SafeDecimalMath");
    const safeDecimalMath = await SafeDecimalMath.connect(owner).deploy();
    await safeDecimalMath.deployed();

    // deploy Kwenta
    const Kwenta = await ethers.getContractFactory("Kwenta");
    kwenta = await Kwenta.connect(owner).deploy(
        NAME,
        SYMBOL,
        INITIAL_SUPPLY,
        owner.address,
        TREASURY_DAO.address
    );
    await kwenta.deployed();

    // deploy SupplySchedule
    const SupplySchedule = await ethers.getContractFactory("SupplySchedule", {
        libraries: {
            SafeDecimalMath: safeDecimalMath.address,
        },
    });
    supplySchedule = await SupplySchedule.connect(owner).deploy(
        owner.address,
        TREASURY_DAO.address
    );
    await supplySchedule.deployed();

    await kwenta.setSupplySchedule(supplySchedule.address);
    await supplySchedule.setKwenta(kwenta.address);

    // deploy RewardEscrow
    const RewardEscrow = await ethers.getContractFactory("RewardEscrow");
    rewardEscrow = await RewardEscrow.connect(owner).deploy(
        owner.address,
        kwenta.address
    );
    await rewardEscrow.deployed();

    // deploy StakingRewards
    const StakingRewards = await ethers.getContractFactory("contracts/StakingRewards.sol:StakingRewards");
    stakingRewards = await StakingRewards.connect(owner).deploy(
        kwenta.address,
        rewardEscrow.address,
        supplySchedule.address
    );
    await stakingRewards.deployed();

    // set StakingRewards address in SupplySchedule
    await supplySchedule.setStakingRewards(stakingRewards.address);

    // set StakingRewards address in RewardEscrow
    await rewardEscrow.setStakingRewards(stakingRewards.address);

    return {
        kwenta,
        supplySchedule,
        rewardEscrow,
        stakingRewards
    };
};
