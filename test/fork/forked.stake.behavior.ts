import { expect } from 'chai';
import { artifacts, ethers, network, upgrades, waffle } from 'hardhat';
import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { wei } from '@synthetixio/wei';
import { Signer } from 'ethers';
import { fastForward } from '../utils/helpers';
import dotenv from 'dotenv';

dotenv.config();

// constants
const NAME = 'Kwenta';
const SYMBOL = 'KWENTA';
const INITIAL_SUPPLY = ethers.utils.parseUnits('313373');
const WEEKLY_START_REWARDS = 3;
const SECONDS_IN_WEEK = 6048000;
const ADDRESS_RESOLVER_OE = '0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C';
const sUSD_ADDRESS_OE = '0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9';
const sETH_ADDRESS_OE = '0xE405de8F52ba7559f9df3C368500B6E6ae6Cee49';

// test values for staking
const TEST_VALUE = wei(20000).toBN();

// test accounts
let owner: SignerWithAddress;
let addr1: SignerWithAddress;
let TREASURY_DAO: SignerWithAddress;
let TEST_SIGNER_WITH_sUSD: Signer;
let TEST_ADDRESS_WITH_sUSD = '0xB594a842A528cb8b80536a84D3DfEd73C2c0c658';

// core contracts
let kwenta: Contract;
let supplySchedule: Contract;
let rewardEscrow: Contract;
let stakingRewardsProxy: Contract;
let exchangerProxy: Contract;

// library contracts
let fixidityLib: Contract;
let logarithmLib: Contract;
let exponentLib: Contract;

// util contracts
let safeDecimalMath: Contract;

// StakingRewards: fund with KWENTA and set the rewards
const fundAndSetStakingRewards = async () => {
	// fund StakingRewards with KWENTA
	const rewards = wei(100000).toBN();
	await expect(() =>
		kwenta
			.connect(TREASURY_DAO)
			.transfer(stakingRewardsProxy.address, rewards)
	).to.changeTokenBalance(kwenta, stakingRewardsProxy, rewards);

	// set the rewards for the next epoch (1)
	await stakingRewardsProxy.setRewardNEpochs(rewards, 1);
};

// Fork Optimism Network for following tests
const forkOptimismNetwork = async () => {
	await network.provider.request({
		method: 'hardhat_reset',
		params: [
			{
				forking: {
					jsonRpcUrl: process.env.ARCHIVE_NODE_URL,
					blockNumber: 4225902,
				},
			},
		],
	});
};

const impersonateTestAccount = async () => {
	await network.provider.request({
		method: 'hardhat_impersonateAccount',
		params: [TEST_ADDRESS_WITH_sUSD],
	});

	TEST_SIGNER_WITH_sUSD = await ethers.provider.getSigner(
		TEST_ADDRESS_WITH_sUSD
	);

	await network.provider.request({
		method: 'hardhat_setBalance',
		params: [
			TEST_ADDRESS_WITH_sUSD,
			ethers.utils.parseEther('10').toHexString(),
		],
	});
};

const loadSetup = () => {
	before('Deploy contracts', async () => {
		// fork optimism mainnet
		forkOptimismNetwork();

		// impersonate account that has sUSD balance
		impersonateTestAccount();

		[owner, addr1, TREASURY_DAO] = await ethers.getSigners();

		// deploy FixidityLib
		const FixidityLib = await ethers.getContractFactory('FixidityLib');
		fixidityLib = await FixidityLib.deploy();
		await fixidityLib.deployed();

		// deploy LogarithmLib
		const LogarithmLib = await ethers.getContractFactory('LogarithmLib', {
			libraries: {
				FixidityLib: fixidityLib.address,
			},
		});
		logarithmLib = await LogarithmLib.deploy();
		await logarithmLib.deployed();

		// deploy ExponentLib
		const ExponentLib = await ethers.getContractFactory('ExponentLib', {
			libraries: {
				FixidityLib: fixidityLib.address,
				LogarithmLib: logarithmLib.address,
			},
		});
		exponentLib = await ExponentLib.deploy();
		await exponentLib.deployed();

		// deploy SafeDecimalMath
		const SafeDecimalMath = await ethers.getContractFactory(
			'SafeDecimalMath'
		);
		safeDecimalMath = await SafeDecimalMath.deploy();
		await safeDecimalMath.deployed();

		// deploy SupplySchedule
		const SupplySchedule = await ethers.getContractFactory('SupplySchedule', {
			libraries: {
				SafeDecimalMath: safeDecimalMath.address,
			},
		});
		supplySchedule = await SupplySchedule.deploy(
			owner.address,
			TREASURY_DAO.address,
			ethers.constants.AddressZero // StakingRewards address
		);
		await supplySchedule.deployed();

		// deploy Kwenta
		const Kwenta = await ethers.getContractFactory('Kwenta');
		kwenta = await Kwenta.deploy(
			NAME,
			SYMBOL,
			INITIAL_SUPPLY,
			owner.address,
			TREASURY_DAO.address,
			supplySchedule.address
		);
		await kwenta.deployed();
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
				kwenta.address,
				rewardEscrow.address,
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

		// deploy ExchangerProxy
		const ExchangerProxy = await ethers.getContractFactory('ExchangerProxy');
		exchangerProxy = await ExchangerProxy.deploy(
			ADDRESS_RESOLVER_OE,
			stakingRewardsProxy.address
		);
		await exchangerProxy.deployed();

		// set ExchangerProxy address in StakingRewards
		await stakingRewardsProxy.setExchangerProxy(exchangerProxy.address);
	});
};

describe('Stake (fork)', () => {
	describe('Staking w/ trading rewards', async () => {
		loadSetup();
		before('Stake kwenta', async () => {
			// fund StakingRewards with KWENTA and set the rewards for the next epoch
			await fundAndSetStakingRewards();

			// initial balance(s) should be 0
			expect(await kwenta.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.equal(0);
			expect(await kwenta.balanceOf(addr1.address)).to.equal(0);

			// transfer KWENTA to TEST_ADDRESS_WITH_sUSD & addr1
			await expect(() =>
				kwenta
					.connect(TREASURY_DAO)
					.transfer(TEST_ADDRESS_WITH_sUSD, TEST_VALUE)
			).to.changeTokenBalance(kwenta, TEST_SIGNER_WITH_sUSD, TEST_VALUE);
			await expect(() =>
				kwenta.connect(TREASURY_DAO).transfer(addr1.address, TEST_VALUE)
			).to.changeTokenBalance(kwenta, addr1, TEST_VALUE);

			// increase KWENTA allowance for stakingRewards and stake
			await kwenta
				.connect(TEST_SIGNER_WITH_sUSD)
				.approve(stakingRewardsProxy.address, TEST_VALUE);
			await kwenta
				.connect(addr1)
				.approve(stakingRewardsProxy.address, TEST_VALUE);
			await stakingRewardsProxy
				.connect(TEST_SIGNER_WITH_sUSD)
				.stake(TEST_VALUE);
			await stakingRewardsProxy.connect(addr1).stake(TEST_VALUE);

			// check KWENTA was staked
			expect(await kwenta.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.equal(0);
			expect(await kwenta.balanceOf(addr1.address)).to.equal(0);
			expect(
				await stakingRewardsProxy
					.connect(TEST_SIGNER_WITH_sUSD)
					.stakedBalanceOf(TEST_ADDRESS_WITH_sUSD)
			).to.equal(TEST_VALUE);
			expect(
				await stakingRewardsProxy
					.connect(addr1)
					.stakedBalanceOf(addr1.address)
			).to.equal(TEST_VALUE);
		});

		it('Confirm nil trade scores', async () => {
			// establish traderScore
			expect(
				await stakingRewardsProxy.rewardScoreOf(TEST_ADDRESS_WITH_sUSD)
			).to.equal(0);
			expect(
				await stakingRewardsProxy.rewardScoreOf(addr1.address)
			).to.equal(0);
		}).timeout(200000);

		it('Execute trade on synthetix through proxy', async () => {
			// confirm pre-balance of sUSD
			const IERC20ABI = (
				await artifacts.readArtifact(
					'contracts/interfaces/IERC20.sol:IERC20'
				)
			).abi;
			const sUSD = new ethers.Contract(
				sUSD_ADDRESS_OE,
				IERC20ABI,
				waffle.provider
			);
			expect(await sUSD.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.be.above(
				ethers.constants.One
			);

			// confirm no balance of sETH
			const sETH = new ethers.Contract(
				sETH_ADDRESS_OE,
				IERC20ABI,
				waffle.provider
			);
			const sETHBalancePreSwap = await sETH.balanceOf(
				TEST_ADDRESS_WITH_sUSD
			);
			expect(sETHBalancePreSwap).to.equal(0);

			// approve exchangerProxy to spend sUSD and
			await sUSD
				.connect(TEST_SIGNER_WITH_sUSD)
				.approve(exchangerProxy.address, ethers.constants.One);

			// confirm allowance
			const allowance = await sUSD.allowance(
				TEST_ADDRESS_WITH_sUSD,
				exchangerProxy.address
			);
			expect(allowance).to.equal(ethers.constants.One);

			// trade
			await exchangerProxy
				.connect(TEST_SIGNER_WITH_sUSD)
				.exchangeWithTraderScoreTracking(
					ethers.utils.formatBytes32String('sUSD'),
					ethers.constants.One,
					ethers.utils.formatBytes32String('sETH'),
					ethers.constants.AddressZero,
					ethers.utils.formatBytes32String('KWENTA')
				);

			// confirm sETH balance increased
			expect(await sETH.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.be.above(
				sETHBalancePreSwap
			);
			
		}).timeout(200000);

		it('Update reward scores properly', async () => {
			// calculate expected reward score
			const feesPaidByTestAddress = await stakingRewardsProxy.feesPaidBy(
				TEST_ADDRESS_WITH_sUSD
			);
			const kwentaStakedByTestAddress =
				await stakingRewardsProxy.stakedBalanceOf(TEST_ADDRESS_WITH_sUSD);

			// expected reward score
			const expectedRewardScoreTestAddress =
				Math.pow(feesPaidByTestAddress, 0.7) *
				Math.pow(kwentaStakedByTestAddress, 0.3);

			// actual reward score(s)
			const actualRewardScoreTestAddress =
				await stakingRewardsProxy.rewardScoreOf(TEST_ADDRESS_WITH_sUSD);
			const actualRewardScoreAddr1 = await stakingRewardsProxy.rewardScoreOf(
				addr1.address
			);

			// expect reward score to have increased post-trade
			expect(actualRewardScoreTestAddress).to.be.closeTo(
				wei(expectedRewardScoreTestAddress.toString(), 18, true)
					.toBN()
					.toString(),
				1e6
			);

			// expect reward score to not change
			expect(actualRewardScoreAddr1).to.equal(0);
		}).timeout(200000);

		it('Wait, and then claim kwenta for both stakers', async () => {
			// establish reward balance pre-claim
			expect(await rewardEscrow.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.equal(
				await rewardEscrow.balanceOf(addr1.address)
			);

			// wait
			fastForward(SECONDS_IN_WEEK);

			// claim reward(s)
			await stakingRewardsProxy.connect(TEST_SIGNER_WITH_sUSD).getReward();
			await stakingRewardsProxy.connect(addr1).getReward();

			// expect staker 1 to have greater rewards
			expect(
				await rewardEscrow.balanceOf(TEST_ADDRESS_WITH_sUSD)
			).to.be.above(await rewardEscrow.balanceOf(addr1.address));
		});
	});
});
