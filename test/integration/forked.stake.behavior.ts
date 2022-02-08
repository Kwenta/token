import { expect } from 'chai';
import { artifacts, ethers, network, upgrades, waffle } from 'hardhat';
import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { wei } from '@synthetixio/wei';
import { Signer } from 'ethers';
import dotenv from 'dotenv';

dotenv.config();

// constants
const NAME = 'Kwenta';
const SYMBOL = 'KWENTA';
const INITIAL_SUPPLY = ethers.utils.parseUnits('313373');
const INFLATION_DIVERSION_BPS = 2000;
const WEEKLY_START_REWARDS = 3;
const SECONDS_IN_WEEK = 6048000;
const ADDRESS_RESOLVER_OE = '0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C';
const sUSD_ADDRESS_OE = '0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9';

// test values for staking
const TEST_VALUE = wei(20000).toBN();

// test accounts
let owner: SignerWithAddress;
let addr1: SignerWithAddress;
let addr2: SignerWithAddress;
let TREASURY_DAO: SignerWithAddress;
let TEST_SIGNER_WITH_sUSD: Signer;
let TEST_ADDRESS_WITH_sUSD = '0xD8a8aA5E8D776a89EE1B7aE98D3490de8ACad53d'; // found via etherscan

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

// time/fast-forwarding Helper Methods
const fastForward = async (sec: number) => {
	const blockNumber = await ethers.provider.getBlockNumber();
	const block = await ethers.provider.getBlock(blockNumber);
	const currTime = block.timestamp;
	await ethers.provider.send('evm_mine', [currTime + sec]);
};

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
					blockNumber: 3225902,
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

		[owner, addr1, addr2, TREASURY_DAO] = await ethers.getSigners();

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
			'SafeDecimalMathV5'
		);
		safeDecimalMath = await SafeDecimalMath.deploy();
		await safeDecimalMath.deployed();

		// deploy SupplySchedule
		const SupplySchedule = await ethers.getContractFactory('SupplySchedule', {
			libraries: {
				SafeDecimalMathV5: safeDecimalMath.address,
			},
		});
		supplySchedule = await SupplySchedule.deploy(owner.address);
		await supplySchedule.deployed();

		// deploy Kwenta
		const Kwenta = await ethers.getContractFactory('Kwenta');
		kwenta = await Kwenta.deploy(
			NAME,
			SYMBOL,
			INITIAL_SUPPLY,
			owner.address,
			TREASURY_DAO.address,
			supplySchedule.address,
			INFLATION_DIVERSION_BPS
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

		// get the address from the implementation (Staking Rewards Logic deployed)
		let stakingRewardsProxyLogicAddress =
			await upgrades.erc1967.getImplementationAddress(
				stakingRewardsProxy.address
			);

		// set StakingRewards address in Kwenta token
		await kwenta.setStakingRewards(stakingRewardsProxy.address);

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

describe('Stake', () => {
	describe('Staking w/ trading rewards', async () => {
		loadSetup();
		before('Stake kwenta', async () => {
			// fund StakingRewards with KWENTA and set the rewards for the next epoch
			await fundAndSetStakingRewards();

			// initial balance(s) should be 0
			expect(await kwenta.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.equal(0);
			expect(await kwenta.balanceOf(addr2.address)).to.equal(0);

			// transfer KWENTA to addr1 & addr2
			await expect(() =>
				kwenta
					.connect(TREASURY_DAO)
					.transfer(TEST_ADDRESS_WITH_sUSD, TEST_VALUE)
			).to.changeTokenBalance(kwenta, TEST_SIGNER_WITH_sUSD, TEST_VALUE);
			await expect(() =>
				kwenta.connect(TREASURY_DAO).transfer(addr2.address, TEST_VALUE)
			).to.changeTokenBalance(kwenta, addr2, TEST_VALUE);

			// increase KWENTA allowance for stakingRewards and stake
			await kwenta
				.connect(TEST_SIGNER_WITH_sUSD)
				.approve(stakingRewardsProxy.address, TEST_VALUE);
			await kwenta
				.connect(addr2)
				.approve(stakingRewardsProxy.address, TEST_VALUE);
			await stakingRewardsProxy
				.connect(TEST_SIGNER_WITH_sUSD)
				.stake(TEST_VALUE);
			await stakingRewardsProxy.connect(addr2).stake(TEST_VALUE);

			// check KWENTA was staked
			expect(await kwenta.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.equal(0);
			expect(await kwenta.balanceOf(addr2.address)).to.equal(0);
			expect(
				await stakingRewardsProxy
					.connect(TEST_SIGNER_WITH_sUSD)
					.stakedBalanceOf(TEST_ADDRESS_WITH_sUSD)
			).to.equal(TEST_VALUE);
			expect(
				await stakingRewardsProxy
					.connect(addr2)
					.stakedBalanceOf(addr2.address)
			).to.equal(TEST_VALUE);
		});

		it('Execute trade on synthetix through proxy', async () => {
			// establish traderScore pre-trade
			expect(
				await stakingRewardsProxy.rewardScoreOf(TEST_ADDRESS_WITH_sUSD)
			).to.equal(0);
			expect(
				await stakingRewardsProxy.rewardScoreOf(addr2.address)
			).to.equal(0);

			// confirm valid pre-balance of sUSD
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
			const preBalance = await sUSD.balanceOf(TEST_ADDRESS_WITH_sUSD);
			expect(preBalance).to.be.above(ethers.constants.One);

			// approve exchangerProxy to spend sUSD and
			await sUSD
				.connect(TEST_SIGNER_WITH_sUSD)
				.approve(exchangerProxy.address, ethers.constants.One);

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

			// calculate expected reward score
			const feesPaidByAddr1 = await stakingRewardsProxy.feesPaidBy(
				TEST_ADDRESS_WITH_sUSD
			);
			const kwentaStakedByAddr1 = await stakingRewardsProxy.stakedBalanceOf(
				TEST_ADDRESS_WITH_sUSD
			);

			// expected reward score
			const expectedRewardScoreAddr1 =
				Math.pow(feesPaidByAddr1, 0.7) * Math.pow(kwentaStakedByAddr1, 0.3);

			// actual reward score(s)
			const actualRewardScoreAddr1 = await stakingRewardsProxy.rewardScoreOf(
				TEST_ADDRESS_WITH_sUSD
			);
			const actualRewardScoreAddr2 = await stakingRewardsProxy.rewardScoreOf(
				addr2.address
			);

			// expect reward score to be increase post-trade
			expect(actualRewardScoreAddr1.div(wei(1).toBN())).to.be.closeTo(
				wei(expectedRewardScoreAddr1.toString(), 18, true)
					.toBN()
					.toString(),
				1e6
			);
			expect(actualRewardScoreAddr2).to.equal(0);
		});

		it('Wait, and then claim kwenta for both stakers', async () => {
			// establish reward balance pre-claim
			expect(await rewardEscrow.balanceOf(addr1.address)).to.equal(
				await rewardEscrow.balanceOf(addr2.address)
			);

			// wait
			fastForward(SECONDS_IN_WEEK);

			// claim reward(s)
			await stakingRewardsProxy.connect(TEST_SIGNER_WITH_sUSD).getReward();
			await stakingRewardsProxy.connect(addr2).getReward();

			// expect staker 1 to have greater rewards
			expect(
				await rewardEscrow.balanceOf(TEST_ADDRESS_WITH_sUSD)
			).to.be.above(await rewardEscrow.balanceOf(addr2.address));
		});
	});
});
