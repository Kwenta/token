import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, Contract } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { mockAddressResolver } from '../utils/mockAddressResolver';

// core contracts
let kwenta: Contract;
let supplySchedule: Contract;
let rewardEscrow: Contract;
let stakingRewardsProxy: Contract;
let exchangerProxy: Contract;


/**
 * Deploys core contracts
 * @dev Libraries that the core contracts depend on are also deployed, but not returned
 * @param NAME: token name (ex: kwenta)
 * @param SYMBOL: symbol of token (ex: KWENTA)
 * @param INITIAL_SUPPLY: number of tokens
 * @param INFLATION_DIVERSION_BPS: used to calculate weekly inflation to treasury percentage
 * @param WEEKLY_START_REWARDS: used for reward calculation 
 * @param owner: EOA used to deploy contracts
 * @param TREASURY_DAO: contract address of TREASURY
 * @returns kwenta, supplySchedule, rewardEscrow, stakingRewardsProxy, exchangerProxy
 */
export const deployKwenta = async (
	NAME: string,
	SYMBOL: string,
	INITIAL_SUPPLY: BigNumber,
	INFLATION_DIVERSION_BPS: number,
	WEEKLY_START_REWARDS: number,
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
	const StakingRewards = await ethers.getContractFactory('StakingRewards', {
		libraries: {
			ExponentLib: exponentLib.address,
			FixidityLib: fixidityLib.address,
		},
	});

	// deploy UUPS Proxy using hardhat upgrades from OpenZeppelin
	stakingRewardsProxy = await upgrades.deployProxy(
		StakingRewards,
		[
			owner.address,
			kwenta.address,
			rewardEscrow.address,
			supplySchedule.address, 
			WEEKLY_START_REWARDS,
		],
		{
			kind: 'uups',
			unsafeAllow: ['external-library-linking'],
		}
	);
	await stakingRewardsProxy.deployed();

	// set StakingRewards address in SupplySchedule
	await supplySchedule.setStakingRewards(stakingRewardsProxy.address);

	// set StakingRewards address in RewardEscrow
	await rewardEscrow.setStakingRewards(stakingRewardsProxy.address);

	// Mock AddressResolver
	const fakeAddressResolver = await mockAddressResolver();

	// deploy ExchangerProxy
	const ExchangerProxy = await ethers.getContractFactory('ExchangerProxy');
	exchangerProxy = await ExchangerProxy.deploy(
		fakeAddressResolver.address,
		stakingRewardsProxy.address
	);
	await exchangerProxy.deployed();

	// set ExchangerProxy address in StakingRewards
	await stakingRewardsProxy.setExchangerProxy(exchangerProxy.address);

	return {
		kwenta,
		supplySchedule,
		rewardEscrow,
		stakingRewardsProxy,
		exchangerProxy,
	};
};
