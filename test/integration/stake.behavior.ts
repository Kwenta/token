import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { wei } from '@synthetixio/wei';
import { FakeContract, smock } from "@defi-wonderland/smock";
import { IExchanger } from "../../typechain/IExchanger";
import { ISynthetix } from "../../typechain/ISynthetix";
import { IAddressResolver } from "../../typechain/IAddressResolver";

// constants
const NAME = 'Kwenta';
const SYMBOL = 'KWENTA';
const INITIAL_SUPPLY = ethers.utils.parseUnits('313373');
const INFLATION_DIVERSION_BPS = 2000;
const WEEKLY_START_REWARDS = 3;
const SECONDS_IN_WEEK = 6048000;

// test values for staking
const TEST_VALUE = wei(2000).toBN();
const SMALLER_TEST_VALUE = wei(1000).toBN();

// test accounts
let owner: SignerWithAddress;
let addr1: SignerWithAddress;
let addr2: SignerWithAddress;
let TREASURY_DAO: SignerWithAddress;

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

// fake contracts
let fakeAddressResolver: FakeContract;

// time/fast-forwarding Helper Methods
const fastForward = async (sec: number) => {
	const blockNumber = await ethers.provider.getBlockNumber();
    const block = await ethers.provider.getBlock(blockNumber);
    const currTime = block.timestamp;
    await ethers.provider.send('evm_mine', [currTime + sec]);
};

// Mock Synthetix AddressResolver
const mockAddressResolver = async () => {
	const FEE = wei(10).toBN();

	const fakeSynthetix = await smock.fake<ISynthetix>('ISynthetix');
	fakeSynthetix.exchangeWithTracking.returns(FEE);

	const fakeExchanger = await smock.fake<IExchanger>('IExchanger');
	fakeExchanger.feeRateForExchange.returns(FEE);

	const fakeAddressResolver = await smock.fake<IAddressResolver>(
		'IAddressResolver'
	);
	fakeAddressResolver.requireAndGetAddress.reverts();
	fakeAddressResolver.requireAndGetAddress
		.whenCalledWith(
			ethers.utils.formatBytes32String('Synthetix'),
			'Could not get Synthetix'
		)
		.returns(fakeSynthetix.address);
	fakeAddressResolver.requireAndGetAddress
		.whenCalledWith(
			ethers.utils.formatBytes32String('Exchanger'),
			'Could not get Exchanger'
		)
		.returns(fakeExchanger.address);

	return fakeAddressResolver;
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
}

const loadSetup = () => {
	before('Deploy contracts', async () => {
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
		await supplySchedule.setSynthetixProxy(kwenta.address);

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

		// Mock AddressResolver
		fakeAddressResolver = await mockAddressResolver();

		// deploy ExchangerProxy
		const ExchangerProxy = await ethers.getContractFactory('ExchangerProxy');
		exchangerProxy = await ExchangerProxy.deploy(
			fakeAddressResolver.address,
			stakingRewardsProxy.address
		);
		await exchangerProxy.deployed();

		// set ExchangerProxy address in StakingRewards
		await stakingRewardsProxy.setExchangerProxy(exchangerProxy.address);
	});
};

describe('Stake', () => {
	describe('Regular staking', async () => {
		loadSetup();
		it('Stake and withdraw all', async () => {
			// initial balance should be 0
			expect(await kwenta.balanceOf(addr1.address)).to.equal(0);

			// transfer KWENTA to addr1
			await expect(() =>
				kwenta.connect(TREASURY_DAO).transfer(addr1.address, TEST_VALUE)
			).to.changeTokenBalance(kwenta, addr1, TEST_VALUE);

			// increase KWENTA allowance for stakingRewards and stake
			await kwenta.connect(addr1).approve(stakingRewardsProxy.address, TEST_VALUE);
			await stakingRewardsProxy.connect(addr1).stake(TEST_VALUE);

			// check KWENTA was staked
			expect(await kwenta.balanceOf(addr1.address)).to.equal(0);
			expect(
				await stakingRewardsProxy
					.connect(addr1)
					.stakedBalanceOf(addr1.address)
			).to.equal(TEST_VALUE);

			// withdraw ALL KWENTA staked
			await stakingRewardsProxy.connect(addr1).withdraw(TEST_VALUE);
			expect(await kwenta.balanceOf(addr1.address)).to.equal(TEST_VALUE);
			expect(
				await stakingRewardsProxy
					.connect(addr1)
					.stakedBalanceOf(addr1.address)
			).to.equal(0);
		});

		it('Stake and claim rewards', async () => {
			// increase KWENTA allowance for stakingRewards and stake
			await kwenta.connect(addr1).approve(stakingRewardsProxy.address, TEST_VALUE);
			await stakingRewardsProxy.connect(addr1).stake(TEST_VALUE);

			// check that addr1 does not have any escrow entries
			expect(await rewardEscrow.numVestingEntries(addr1.address)).to.equal(0);

			// claim rewards (expect 0 rewards)
			expect(await stakingRewardsProxy.totalBalanceOf(addr1.address)).to.equal(TEST_VALUE);
			await stakingRewardsProxy.connect(addr1).getReward();
			expect(await rewardEscrow.balanceOf(addr1.address)).to.equal(0);
		});

		it('Wait then claim rewards', async () => {
			// fund StakingRewards with KWENTA and set the rewards for the next epoch
			await fundAndSetStakingRewards();

			// wait
			await fastForward(SECONDS_IN_WEEK);

			// addr1 does not have any escrow entries
			expect(await rewardEscrow.numVestingEntries(addr1.address)).to.equal(0);

			// claim rewards (expect > 0 rewards appended in escrow)
			await stakingRewardsProxy.connect(addr1).getReward();
			expect(await rewardEscrow.balanceOf(addr1.address)).to.be.above(0);

			// check that addr1 does have an escrow entry
			expect(await rewardEscrow.numVestingEntries(addr1.address)).to.equal(1);
		});

		it('Stake, Wait, and then Exit', async () => {
			// initial balance should be 0
			expect(await kwenta.balanceOf(addr2.address)).to.equal(0);

			// transfer KWENTA to addr2
			await expect(() =>
				kwenta.connect(TREASURY_DAO).transfer(addr2.address, TEST_VALUE)
			).to.changeTokenBalance(kwenta, addr2, TEST_VALUE);

			// set the rewards for the next epoch (2)
			const reward = wei(1).toBN();
			await stakingRewardsProxy.setRewardNEpochs(reward, 1);

			// increase KWENTA allowance for stakingRewards and stake
			await kwenta.connect(addr2).approve(stakingRewardsProxy.address, TEST_VALUE);
			await stakingRewardsProxy.connect(addr2).stake(TEST_VALUE);

			// wait
			await fastForward(SECONDS_IN_WEEK);

			// expect tokens back and no rewards
			await stakingRewardsProxy.connect(addr2).exit();
			expect(await rewardEscrow.balanceOf(addr2.address)).to.be.above(0);
			expect(await kwenta.balanceOf(addr2.address)).to.equal(TEST_VALUE);
		});
	});
  
	describe('Escrow staking', async () => {
		loadSetup();
		before('Create new escrow entry', async () => {
			// initial balance(s) should be 0
			expect(await kwenta.balanceOf(addr1.address)).to.equal(0);
			expect(await kwenta.balanceOf(addr2.address)).to.equal(0);

			// transfer KWENTA to addr1 & addr2
			await expect(() =>
				kwenta.connect(TREASURY_DAO).transfer(addr1.address, TEST_VALUE)
			).to.changeTokenBalance(kwenta, addr1, TEST_VALUE);
			await expect(() =>
				kwenta.connect(TREASURY_DAO).transfer(addr2.address, TEST_VALUE)
			).to.changeTokenBalance(kwenta, addr2, TEST_VALUE);

			// increase KWENTA allowance for rewardEscrow and stake
			await kwenta.connect(addr1).approve(rewardEscrow.address, TEST_VALUE);
			await rewardEscrow.connect(addr1).createEscrowEntry(
				addr1.address,
        		TEST_VALUE,
        		SECONDS_IN_WEEK
			);
			await kwenta.connect(addr2).approve(rewardEscrow.address, TEST_VALUE);
			await rewardEscrow.connect(addr2).createEscrowEntry(
				addr2.address,
        		TEST_VALUE,
        		SECONDS_IN_WEEK
			);

			// check escrow entries
			expect(await rewardEscrow.numVestingEntries(addr1.address)).to.equal(1);
			expect(await rewardEscrow.numVestingEntries(addr2.address)).to.equal(1);
		});
		
		it('Stake escrowed kwenta', async () => {
			// check escrowed balance(s)
			expect(await rewardEscrow.balanceOf(addr1.address)).to.equal(TEST_VALUE);
			expect(await rewardEscrow.balanceOf(addr2.address)).to.equal(TEST_VALUE);

			// stake (different amounts) 
			await rewardEscrow.connect(addr1).stakeEscrow(TEST_VALUE);
			await rewardEscrow.connect(addr2).stakeEscrow(SMALLER_TEST_VALUE);

			// check escrow balance(s) and expect balance of staked escrow to be > 0
			expect(await stakingRewardsProxy.escrowedBalanceOf(addr1.address)).to.equal(TEST_VALUE);
			expect(await stakingRewardsProxy.escrowedBalanceOf(addr2.address)).to.equal(SMALLER_TEST_VALUE);
		});

		it('Wait, claim rewards', async () => {
			// fund StakingRewards with KWENTA and set the rewards for the next epoch
			await fundAndSetStakingRewards();

			// establish current escrow balance(s)
			const prevAddr1EscrowBalance = await rewardEscrow.balanceOf(
				addr1.address
			);
			const prevAddr2EscrowBalance = await rewardEscrow.balanceOf(
				addr2.address
			);

			// wait
			fastForward(SECONDS_IN_WEEK);

			// claim reward(s)
			await stakingRewardsProxy.connect(addr1).getReward();
			await stakingRewardsProxy.connect(addr2).getReward();

			// check escrow balance(s) have increased appropriately
			expect(await rewardEscrow.balanceOf(addr1.address)).to.be.above(prevAddr1EscrowBalance);
			expect(await rewardEscrow.balanceOf(addr2.address)).to.be.above(prevAddr2EscrowBalance);

			// addr1 staked more than addr2
			expect(await rewardEscrow.balanceOf(addr1.address)).to.be.above(
				await rewardEscrow.balanceOf(addr2.address)
			);
		});

		it('Unstake escrowed kwenta', async () => {
			// initial balance(s) should be 0
			expect(await kwenta.balanceOf(addr1.address)).to.equal(0);
			expect(await kwenta.balanceOf(addr2.address)).to.equal(0);

			// establish amount of staked KWENTA 
			const addr1EscrowStakedBalance = await stakingRewardsProxy.escrowedBalanceOf(addr1.address);
			const addr2EscrowStakedBalance = await stakingRewardsProxy.escrowedBalanceOf(addr2.address);

			// unstake KWENTA
			await rewardEscrow.connect(addr1).unstakeEscrow(addr1EscrowStakedBalance);
			await rewardEscrow.connect(addr2).unstakeEscrow(addr2EscrowStakedBalance);

			// check saked escrow balance(s) and expect balance of staked escrow to be 0
			expect(await stakingRewardsProxy.escrowedBalanceOf(addr1.address)).to.equal(0);
			expect(await stakingRewardsProxy.escrowedBalanceOf(addr2.address)).to.equal(0);
		});
	});

	describe('Staking w/ trading rewards', async () => {
		loadSetup();
		before('Stake kwenta', async () => {
			// fund StakingRewards with KWENTA and set the rewards for the next epoch
			await fundAndSetStakingRewards();

			// initial balance(s) should be 0
			expect(await kwenta.balanceOf(addr1.address)).to.equal(0);
			expect(await kwenta.balanceOf(addr2.address)).to.equal(0);

			// transfer KWENTA to addr1 & addr2
			await expect(() =>
				kwenta.connect(TREASURY_DAO).transfer(addr1.address, wei(20000).toBN())
			).to.changeTokenBalance(kwenta, addr1, wei(20000).toBN());
			await expect(() =>
				kwenta.connect(TREASURY_DAO).transfer(addr2.address, wei(20000).toBN())
			).to.changeTokenBalance(kwenta, addr2, wei(20000).toBN());

			// increase KWENTA allowance for stakingRewards and stake
			await kwenta.connect(addr1).approve(stakingRewardsProxy.address, wei(20000).toBN());
			await kwenta.connect(addr2).approve(stakingRewardsProxy.address, wei(20000).toBN());
			await stakingRewardsProxy.connect(addr1).stake(wei(20000).toBN());
			await stakingRewardsProxy.connect(addr2).stake(wei(20000).toBN());

			// check KWENTA was staked
			expect(await kwenta.balanceOf(addr1.address)).to.equal(0);
			expect(await kwenta.balanceOf(addr2.address)).to.equal(0);
			expect(
				await stakingRewardsProxy
					.connect(addr1)
					.stakedBalanceOf(addr1.address)
			).to.equal(wei(20000).toBN());
			expect(
				await stakingRewardsProxy
					.connect(addr2)
					.stakedBalanceOf(addr2.address)
			).to.equal(wei(20000).toBN());
		});

		it('Execute trade on synthetix through proxy', async () => {
			// establish traderScore pre-trade
			expect(
				await stakingRewardsProxy.rewardScoreOf(addr1.address)
			).to.equal(0);
			expect(
				await stakingRewardsProxy.rewardScoreOf(addr2.address)
			).to.equal(0);

			// trade
			await exchangerProxy.connect(addr1).exchangeWithTraderScoreTracking(
				ethers.utils.formatBytes32String('sUSD'),
				ethers.constants.One,
				ethers.utils.formatBytes32String('sETH'),
				ethers.constants.AddressZero,
				ethers.utils.formatBytes32String('KWENTA')
			);

			// calculate expected reward score
			const feesPaidByAddr1 = await stakingRewardsProxy.feesPaidBy(addr1.address);
			console.log("Fees: " + feesPaidByAddr1);
			const kwentaStakedByAddr1 = await stakingRewardsProxy.stakedBalanceOf(addr1.address);
			console.log("Staked: " + kwentaStakedByAddr1);

			const expectedRewardScoreAddr1 = Math.pow(feesPaidByAddr1, 0.7) * Math.pow(kwentaStakedByAddr1, (0.3));
			console.log("Expected: " + expectedRewardScoreAddr1);

			const actualRewardScoreAddr1 = await stakingRewardsProxy.rewardScoreOf(addr1.address);
			console.log("Actual: " + actualRewardScoreAddr1);
			const actualRewardScoreAddr2 = await stakingRewardsProxy.rewardScoreOf(addr2.address);

			// expect reward score to be increase post-trade
			expect(
				actualRewardScoreAddr1
			).to.be.above(expectedRewardScoreAddr1.toString());
			expect(
				actualRewardScoreAddr2
			).to.equal(0);
		});

		it('Wait, and then claim kwenta for both stakers', async () => {
			// establish reward balance pre-claim
			expect(await rewardEscrow.balanceOf(addr1.address)).to.equal(
				await rewardEscrow.balanceOf(addr2.address)
			);

			// wait
			fastForward(SECONDS_IN_WEEK);

			// claim reward(s)
			await stakingRewardsProxy.connect(addr1).getReward();
			await stakingRewardsProxy.connect(addr2).getReward();

			// expect staker 1 to have greater rewards
			expect(await rewardEscrow.balanceOf(addr1.address)).to.be.above(
				await rewardEscrow.balanceOf(addr2.address)
			);
		});
	});
});
