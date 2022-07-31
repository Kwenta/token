import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, Contract } from 'ethers';
import { ethers } from 'hardhat';

// core contracts
let kwenta: Contract;
let supplySchedule: Contract;
let rewardEscrow: Contract;
let stakingRewards: Contract;
let exchangerProxy: Contract;

/**
 * Deploys core contracts
 * @dev Libraries that the core contracts depend on are also deployed, but not returned
 * @param NAME: token name (ex: kwenta)
 * @param SYMBOL: symbol of token (ex: KWENTA)
 * @param INITIAL_SUPPLY: number of tokens
 * @param owner: EOA used to deploy contracts
 * @param TREASURY_DAO: contract address of TREASURY
 * @returns kwenta, supplySchedule, rewardEscrow, stakingRewardsProxy, exchangerProxy
 */
export const deployKwenta = async (
	NAME: string,
	SYMBOL: string,
	INITIAL_SUPPLY: BigNumber,
	owner: SignerWithAddress,
	TREASURY_DAO: SignerWithAddress
) => {
	// deploy FixidityLib
	const FixidityLib = await ethers.getContractFactory('FixidityLib');
	const fixidityLib = await FixidityLib.deploy();
	await fixidityLib.deployed();

	// deploy LogarithmLib
	const LogarithmLib = await ethers.getContractFactory('LogarithmLib', {
		libraries: {
			FixidityLib: fixidityLib.address,
		},
	});
	const logarithmLib = await LogarithmLib.deploy();
	await logarithmLib.deployed();

	// deploy ExponentLib
	const ExponentLib = await ethers.getContractFactory('ExponentLib', {
		libraries: {
			FixidityLib: fixidityLib.address,
			LogarithmLib: logarithmLib.address,
		},
	});
	const exponentLib = await ExponentLib.deploy();
	await exponentLib.deployed();

	// deploy SafeDecimalMath
	const SafeDecimalMath = await ethers.getContractFactory('SafeDecimalMath');
	const safeDecimalMath = await SafeDecimalMath.deploy();
	await safeDecimalMath.deployed();

	// deploy Kwenta
	const Kwenta = await ethers.getContractFactory('Kwenta');
	kwenta = await Kwenta.deploy(
		NAME,
		SYMBOL,
		INITIAL_SUPPLY,
		owner.address,
		TREASURY_DAO.address
	);
	await kwenta.deployed();

	// deploy SupplySchedule
	const SupplySchedule = await ethers.getContractFactory('SupplySchedule', {
		libraries: {
			SafeDecimalMath: safeDecimalMath.address,
		},
	});
	supplySchedule = await SupplySchedule.deploy(
		owner.address, 
		TREASURY_DAO.address
	);
	await supplySchedule.deployed();
	
	await kwenta.setSupplySchedule(supplySchedule.address);
	await supplySchedule.setKwenta(kwenta.address);

	// deploy RewardEscrow
	const RewardEscrow = await ethers.getContractFactory('RewardEscrow');
	rewardEscrow = await RewardEscrow.deploy(owner.address, kwenta.address);
	await rewardEscrow.deployed();

	// deploy StakingRewards
	const StakingRewards = await ethers.getContractFactory("StakingRewards");
    stakingRewards = await StakingRewards.deploy(
        kwenta.address,
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
		stakingRewards,
		exchangerProxy,
	};
};
