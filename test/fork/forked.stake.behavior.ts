import { expect } from 'chai';
import { artifacts, ethers, network, upgrades, waffle } from 'hardhat';
import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { wei } from '@synthetixio/wei';
import { Signer } from 'ethers';
import { fastForward, impersonate } from '../utils/helpers';
import dotenv from 'dotenv';

dotenv.config();

// constants
const NAME = 'Kwenta';
const SYMBOL = 'KWENTA';
const INITIAL_SUPPLY = ethers.utils.parseUnits('313373');
const WEEKLY_START_REWARDS = 3;
const SECONDS_IN_WEEK = 6048000;
const FEE_BPS = 25;

// deployed contract addresses on OE
const ADDRESS_RESOLVER_OE = '0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C';
const DELEGATE_APPROVALS_OE = '0x2a23bc0ea97a89abd91214e8e4d20f02fe14743f';
const EXCHANGE_RATES_OE = '0x1B9d6cD65dDC981410cb93Af91B097667E0Bc7eE';

// token addresses on OE
const sUSD_ADDRESS_OE = '0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9';
const sETH_ADDRESS_OE = '0xE405de8F52ba7559f9df3C368500B6E6ae6Cee49';
const sUNI_ADDRESS_OE = '0xf5a6115Aa582Fd1BEEa22BC93B7dC7a785F60d03';
const sLINK_ADDRESS_OE = '0x2302D7F7783e2712C48aA684451b9d706e74F299';

// test values
const TEST_STAKING_VALUE = wei(20000).toBN();
const TEST_SWAP_VALUE = wei(1000).toBN();

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
let delegateApprovals: Contract;
let exchangeRates: Contract;

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
	await stakingRewardsProxy.connect(await impersonate(supplySchedule.address)).setRewardNEpochs(rewards, 1);
};

// Fork Optimism Network for following tests
const forkOptimismNetwork = async () => {
	await network.provider.request({
		method: 'hardhat_reset',
		params: [
			{
				forking: {
					jsonRpcUrl: process.env.ARCHIVE_NODE_URL,
					blockNumber: 4683200,
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

		// deploy ExchangerProxy
		const ExchangerProxy = await ethers.getContractFactory('ExchangerProxy');
		exchangerProxy = await ExchangerProxy.deploy(
			ADDRESS_RESOLVER_OE,
			stakingRewardsProxy.address
		);
		await exchangerProxy.deployed();

		// set ExchangerProxy address in StakingRewards
		await stakingRewardsProxy.setExchangerProxy(exchangerProxy.address);

		// define DelegateApprovals contract for approvals
		const IDelegateApprovals = (
			await artifacts.readArtifact(
				'contracts/interfaces/IDelegateApprovals.sol:IDelegateApprovals'
			)
		).abi;
		delegateApprovals = new ethers.Contract(
			DELEGATE_APPROVALS_OE,
			IDelegateApprovals,
			waffle.provider
		);

		// define ExchangeRates contract to poll synth swap rates
		const IExchangeRates = (
			await artifacts.readArtifact(
				'contracts/interfaces/IExchangeRates.sol:IExchangeRates'
			)
		).abi;
		exchangeRates = new ethers.Contract(
			EXCHANGE_RATES_OE,
			IExchangeRates,
			waffle.provider
		);
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
					.transfer(TEST_ADDRESS_WITH_sUSD, TEST_STAKING_VALUE)
			).to.changeTokenBalance(
				kwenta,
				TEST_SIGNER_WITH_sUSD,
				TEST_STAKING_VALUE
			);
			await expect(() =>
				kwenta
					.connect(TREASURY_DAO)
					.transfer(addr1.address, TEST_STAKING_VALUE)
			).to.changeTokenBalance(kwenta, addr1, TEST_STAKING_VALUE);

			// increase KWENTA allowance for stakingRewards and stake
			await kwenta
				.connect(TEST_SIGNER_WITH_sUSD)
				.approve(stakingRewardsProxy.address, TEST_STAKING_VALUE);
			await kwenta
				.connect(addr1)
				.approve(stakingRewardsProxy.address, TEST_STAKING_VALUE);
			await stakingRewardsProxy
				.connect(TEST_SIGNER_WITH_sUSD)
				.stake(TEST_STAKING_VALUE);
			await stakingRewardsProxy.connect(addr1).stake(TEST_STAKING_VALUE);

			// check KWENTA was staked
			expect(await kwenta.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.equal(0);
			expect(await kwenta.balanceOf(addr1.address)).to.equal(0);
			expect(
				await stakingRewardsProxy
					.connect(TEST_SIGNER_WITH_sUSD)
					.stakedBalanceOf(TEST_ADDRESS_WITH_sUSD)
			).to.equal(TEST_STAKING_VALUE);
			expect(
				await stakingRewardsProxy
					.connect(addr1)
					.stakedBalanceOf(addr1.address)
			).to.equal(TEST_STAKING_VALUE);
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

		it('Can poll synth rate for sETH to sUSD', async () => {
			// Given a quantity of a source currency, returns a quantity
			// of a destination currency that is of equivalent value at
			// current exchange rates
			const rate = await exchangeRates
				.connect(TEST_SIGNER_WITH_sUSD)
				.effectiveValue(
					ethers.utils.formatBytes32String('sETH'),
					wei(1).toBN(),
					ethers.utils.formatBytes32String('sUSD')
				);

			expect(rate).to.equal('2903367300000000000000'); // $2,903.367
		});

		it('Caller can approve swap on behalf of exchange', async () => {
			// approve exchange to swap token on behalf of TEST_SIGNER_WITH_sUSD
			await delegateApprovals
				.connect(TEST_SIGNER_WITH_sUSD)
				.approveExchangeOnBehalf(exchangerProxy.address);

			const canExchange = await delegateApprovals
				.connect(TEST_SIGNER_WITH_sUSD)
				.canExchangeFor(TEST_ADDRESS_WITH_sUSD, exchangerProxy.address);

			expect(canExchange).to.be.true;
		});

		it('Execute trade (sUSD -> sETH) on synthetix through proxy', async () => {
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
			const sUSDBalancePreSwap = await sUSD.balanceOf(
				TEST_ADDRESS_WITH_sUSD
			);
			expect(sUSDBalancePreSwap).to.be.above(TEST_SWAP_VALUE);

			// confirm no balance of sETH
			const sETH = new ethers.Contract(
				sETH_ADDRESS_OE,
				IERC20ABI,
				waffle.provider
			);
			expect(await sETH.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.equal(0);

			// trade sUSD -> sETH
			// @notice delegateApprovals.approveExchangeOnBehalf called previously
			await exchangerProxy
				.connect(TEST_SIGNER_WITH_sUSD)
				.exchangeOnBehalfWithTraderScoreTracking(
					ethers.utils.formatBytes32String('sUSD'),
					TEST_SWAP_VALUE,
					ethers.utils.formatBytes32String('sETH'),
					ethers.constants.AddressZero,
					ethers.utils.formatBytes32String('KWENTA')
				);

			// poll exchange rate
			const rate = await exchangeRates
				.connect(TEST_SIGNER_WITH_sUSD)
				.effectiveValue(
					ethers.utils.formatBytes32String('sUSD'),
					TEST_SWAP_VALUE,
					ethers.utils.formatBytes32String('sETH')
				);
			
			// calculate fee taken from synth exchange
			const fee = wei(rate, 18, true).mul(FEE_BPS / 10000).toBN();

			// confirm sUSD balance decreased
			expect(await sUSD.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.equal(
				sUSDBalancePreSwap.sub(TEST_SWAP_VALUE)
			);

			// confirm sETH balance increased
			expect(await sETH.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.be.closeTo(
				rate.sub(fee),
				1,
				'numbers are *very* close'
				// actual sETH balance: 343566589043005340
				// rate - fee: 			343566589043005341
			);
		}).timeout(200000);

		it('Caller can remove swap approval on behalf of exchange', async () => {
			// remove approval to swap token on behalf of TEST_SIGNER_WITH_sUSD
			await delegateApprovals
				.connect(TEST_SIGNER_WITH_sUSD)
				.removeExchangeOnBehalf(exchangerProxy.address);

			const canExchange = await delegateApprovals
				.connect(TEST_SIGNER_WITH_sUSD)
				.canExchangeFor(TEST_ADDRESS_WITH_sUSD, exchangerProxy.address);

			expect(canExchange).to.be.false;
		});

		it('Expect trade (sUSD -> sLINK) to fail without approval', async () => {
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
			const sUSDBalancePreSwap = await sUSD.balanceOf(
				TEST_ADDRESS_WITH_sUSD
			);
			expect(sUSDBalancePreSwap).to.be.above(TEST_SWAP_VALUE);

			// confirm no balance of sLINK
			const sLINK = new ethers.Contract(
				sLINK_ADDRESS_OE,
				IERC20ABI,
				waffle.provider
			);
			expect(await sLINK.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.equal(0);

			// trade sUSD -> sLINK
			// @notice delegateApprovals.removeExchangeOnBehalf called previously
			await expect(
				exchangerProxy
					.connect(TEST_SIGNER_WITH_sUSD)
					.exchangeOnBehalfWithTraderScoreTracking(
						ethers.utils.formatBytes32String('sUSD'),
						TEST_SWAP_VALUE,
						ethers.utils.formatBytes32String('sLINK'),
						ethers.constants.AddressZero,
						ethers.utils.formatBytes32String('KWENTA')
					)
			).to.be.revertedWith('Not approved to act on behalf');

			// confirm sUSD balance did not decrease
			expect(await sUSD.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.equal(
				sUSDBalancePreSwap
			);
		}).timeout(200000);

		it('Caller can approve swap *again* on behalf of exchange', async () => {
			// approve exchange to swap token on behalf of TEST_SIGNER_WITH_sUSD
			await delegateApprovals
				.connect(TEST_SIGNER_WITH_sUSD)
				.approveExchangeOnBehalf(exchangerProxy.address);

			const canExchange = await delegateApprovals
				.connect(TEST_SIGNER_WITH_sUSD)
				.canExchangeFor(TEST_ADDRESS_WITH_sUSD, exchangerProxy.address);

			expect(canExchange).to.be.true;
		});

		it('Execute trade (sUSD -> sUNI) on synthetix through proxy', async () => {
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
			const sUSDBalancePreSwap = await sUSD.balanceOf(
				TEST_ADDRESS_WITH_sUSD
			);
			expect(sUSDBalancePreSwap).to.be.above(TEST_SWAP_VALUE);

			// confirm no balance of sUNI
			const sUNI = new ethers.Contract(
				sUNI_ADDRESS_OE,
				IERC20ABI,
				waffle.provider
			);
			expect(await sUNI.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.equal(0);

			// trade sUSD -> sUNI
			// @notice delegateApprovals.approveExchangeOnBehalf called previously
			await exchangerProxy
				.connect(TEST_SIGNER_WITH_sUSD)
				.exchangeOnBehalfWithTraderScoreTracking(
					ethers.utils.formatBytes32String('sUSD'),
					TEST_SWAP_VALUE,
					ethers.utils.formatBytes32String('sUNI'),
					ethers.constants.AddressZero,
					ethers.utils.formatBytes32String('KWENTA')
				);

			// poll exchange rate
			const rate = await exchangeRates
				.connect(TEST_SIGNER_WITH_sUSD)
				.effectiveValue(
					ethers.utils.formatBytes32String('sUSD'),
					TEST_SWAP_VALUE,
					ethers.utils.formatBytes32String('sUNI')
				);
			
			// calculate fee taken from synth exchange
			const fee = wei(rate, 18, true).mul(FEE_BPS / 10000).toBN();

			// confirm sUSD balance decreased
			expect(await sUSD.balanceOf(TEST_ADDRESS_WITH_sUSD)).to.equal(
				sUSDBalancePreSwap.sub(TEST_SWAP_VALUE)
			);

			// confirm sUNI balance increased
			expect(
				await sUNI.balanceOf(TEST_ADDRESS_WITH_sUSD)
			).to.be.closeTo(
				rate.sub(fee),
				1,
				'numbers are *very* close'
				// actual sUNI balance: 107215161274136549846
				// rate - fee: 			107215161274136549847
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
