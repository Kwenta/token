import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

const NAME = 'Kwenta';
const SYMBOL = 'KWENTA';
const INITIAL_SUPPLY = ethers.utils.parseUnits('313373');
const INFLATION_DIVERSION_BPS = 2000;

// test accounts
let owner: SignerWithAddress;
let addr1: SignerWithAddress; 
let addr2: SignerWithAddress;
let TREASURY_DAO: SignerWithAddress;

// core contracts
let kwenta: Contract;
let stakingRewards: Contract;
let supplySchedule: Contract;
let rewardEscrow: Contract;

// library contracts
let fixidityLib: Contract;
let logarithmLib: Contract;
let exponentLib: Contract;

// util contracts
let safeDecimalMath: Contract;

const loadSetup = () => {
	before('Deploy contracts', async () => {
		[owner, addr1, addr2, TREASURY_DAO] = await ethers.getSigners();

        // Deploy FixidityLib
        const FixidityLib = await ethers.getContractFactory('FixidityLib');
		fixidityLib = await FixidityLib.deploy();
		await fixidityLib.deployed();

        // Deploy LogarithmLib
        const LogarithmLib = await ethers.getContractFactory('LogarithmLib', {
			libraries: {
				FixidityLib: fixidityLib.address,
			},
		});
		logarithmLib = await LogarithmLib.deploy();
		await logarithmLib.deployed();

        // Deploy ExponentLib
		const ExponentLib = await ethers.getContractFactory('ExponentLib', {
			libraries: {
				FixidityLib: fixidityLib.address,
				LogarithmLib: logarithmLib.address,
			},
		});
		exponentLib = await ExponentLib.deploy();
		await exponentLib.deployed();

        // Deploy StakingRewards
		const StakingRewards = await ethers.getContractFactory('StakingRewards', {
			libraries: {
				ExponentLib: exponentLib.address,
				FixidityLib: fixidityLib.address,
			},
		});
		stakingRewards = await StakingRewards.deploy();
		await stakingRewards.deployed();

        // Deploy SafeDecimalMath
		const SafeDecimalMath = await ethers.getContractFactory(
			'SafeDecimalMathV5'
		);
		safeDecimalMath = await SafeDecimalMath.deploy();
		await safeDecimalMath.deployed();

        // Deploy SupplySchedule
		const SupplySchedule = await ethers.getContractFactory('SupplySchedule', {
			libraries: {
				SafeDecimalMathV5: safeDecimalMath.address,
			},
		});
		supplySchedule = await SupplySchedule.deploy(owner.address);
		await supplySchedule.deployed();

        // Deploy Kwenta
		const Kwenta = await ethers.getContractFactory('Kwenta');
		kwenta = await Kwenta.deploy(
			NAME,
			SYMBOL,
			INITIAL_SUPPLY,
			owner.address,
			TREASURY_DAO.address,
			stakingRewards.address,
			supplySchedule.address,
			INFLATION_DIVERSION_BPS
		);
		await kwenta.deployed();
		await supplySchedule.setSynthetixProxy(kwenta.address);

        // Deploy RewardEscrow
		const RewardEscrow = await ethers.getContractFactory('RewardEscrow');
		rewardEscrow = await RewardEscrow.deploy(owner.address, kwenta.address);
		await rewardEscrow.deployed();

        // Initialize StakingRewards
        await stakingRewards.initialize(
            owner.address,
            kwenta.address,
            kwenta.address,
            rewardEscrow.address,
            1 // @TODO what is a good value to use here?
        );
	});
};

describe('Stake', () => {
	describe('Regular staking', async () => {
		loadSetup();
		it('Stake and withdraw all', async () => {
            // TODO: expect same tokens back
		});

		it('Stake and claim: ', async () => {
			// TODO: expect 0 rewards
		});
		it('Wait then claim', async () => {
			// TODO: expect > 0 rewards appended in escrow
		});
		it('Exit with half', async () => {
			// TODO: expect half tokens back no rewards
		});
		it('Wait, exit with remaining half', async () => {
			// TODO: expect same tokens back, > 0 rewards appended in escrow
		});
	});
	describe('Escrow staking', async () => {
		loadSetup();
		before('Create new escrow entry', async () => {
			// TODO: stake some equivalent kwenta for staker 1 and staker 2
		});
		it('Stake escrowed kwenta', async () => {
			// TODO: expect balance of staked escrow to be > 0
		});
		it('Wait, claim rewards', async () => {
			// TODO: expect balance of staked escrow to be > 0
		});
		it('Unstake escrowed kwenta', async () => {
			// TODO: expect balance of staked escrow 0
		});
	});
	describe('Staking w/ trading rewards', async () => {
		loadSetup();
		before('Stake kwenta', async () => {
			// TODO: stake some equivalent kwenta for staker 1 and staker 2
		});
		it('Execute trade on synthetix through proxy', async () => {
			// TODO: expect traderScore to have been updated for staker 1
		});
		it('Wait, and then claim kwenta for both stakers', async () => {
			// TODO: expect staker 1 to have greater rewards
		});
	});
});
