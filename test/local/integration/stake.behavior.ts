import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { wei } from '@synthetixio/wei';
import { fastForward, impersonate } from '../../utils/helpers';
import { deployKwenta } from '../../utils/kwenta';

// constants
const NAME = 'Kwenta';
const SYMBOL = 'KWENTA';
const INITIAL_SUPPLY = ethers.utils.parseUnits('313373');
const INFLATION_DIVERSION_BPS = 2000;
const WEEKLY_START_REWARDS = 3;
const SECONDS_IN_WEEK = 604800;

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
let stakingRewards: Contract;

// StakingRewards: fund with KWENTA and set the rewards
const fundAndSetStakingRewards = async () => {
	// fund StakingRewards with KWENTA
	const rewards = wei(100000).toBN();
	await expect(() =>
		kwenta
			.connect(TREASURY_DAO)
			.transfer(stakingRewards.address, rewards)
	).to.changeTokenBalance(kwenta, stakingRewards, rewards);

	// set the rewards for the next epoch (1)
	await stakingRewards.connect(await impersonate(supplySchedule.address)).notifyRewardAmount(rewards);
};

const loadSetup = () => {
	before('Deploy contracts', async () => {
		[owner, addr1, addr2, TREASURY_DAO] = await ethers.getSigners();
		let deployments = await deployKwenta(
			NAME,
			SYMBOL,
			INITIAL_SUPPLY,
			INFLATION_DIVERSION_BPS,
			WEEKLY_START_REWARDS,
			owner,
			TREASURY_DAO
		);
		kwenta = deployments.kwenta;
		supplySchedule = deployments.supplySchedule;
		rewardEscrow = deployments.rewardEscrow;
		stakingRewards = deployments.stakingRewards;
	});
};

describe('Stake', () => {
	describe('Regular staking', async () => {
		loadSetup();
		it("Stake and claim rewards", async () => {
            // initial balance should be 0
            expect(await kwenta.balanceOf(addr1.address)).to.equal(0);

            // transfer KWENTA to addr1
            await expect(() =>
                kwenta.connect(TREASURY_DAO).transfer(addr1.address, TEST_VALUE)
            ).to.changeTokenBalance(kwenta, addr1, TEST_VALUE);

            // increase KWENTA allowance for stakingRewards
            await kwenta
                .connect(addr1)
                .approve(stakingRewards.address, TEST_VALUE);

            // stake
            await stakingRewards.connect(addr1).stake(TEST_VALUE);

            // check that addr1 does not have any escrow entries
            expect(
                await rewardEscrow.numVestingEntries(addr1.address)
            ).to.equal(0);

            // check total staked balance is TEST_VALUE
            expect(await stakingRewards.balanceOf(addr1.address)).to.equal(
                TEST_VALUE
            );
            await stakingRewards.connect(addr1).getReward();
            expect(await rewardEscrow.balanceOf(addr1.address)).to.equal(0);
        });

		it('Wait then claim rewards', async () => {
			// fund StakingRewards with KWENTA and set the rewards for the next epoch
			await fundAndSetStakingRewards();

			// wait
			await fastForward(SECONDS_IN_WEEK + 1);

			// addr1 does not have any escrow entries
			expect(await rewardEscrow.numVestingEntries(addr1.address)).to.equal(
				0
			);

			// claim rewards (expect > 0 rewards appended in escrow)
			await stakingRewards.connect(addr1).getReward();
			expect(await rewardEscrow.balanceOf(addr1.address)).to.be.above(0);

			// check that addr1 does have an escrow entry
			expect(await rewardEscrow.numVestingEntries(addr1.address)).to.equal(
				1
			);
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
			await stakingRewards.connect(await impersonate(supplySchedule.address)).notifyRewardAmount(reward);

			// increase KWENTA allowance for stakingRewards and stake
			await kwenta
				.connect(addr2)
				.approve(stakingRewards.address, TEST_VALUE);
			await stakingRewards.connect(addr2).stake(TEST_VALUE);

			// wait
			await fastForward(SECONDS_IN_WEEK);

			// expect tokens back and rewards
			await stakingRewards.connect(addr2).exit();
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
			await rewardEscrow
				.connect(addr1)
				.createEscrowEntry(addr1.address, TEST_VALUE, SECONDS_IN_WEEK);
			await kwenta.connect(addr2).approve(rewardEscrow.address, TEST_VALUE);
			await rewardEscrow
				.connect(addr2)
				.createEscrowEntry(addr2.address, TEST_VALUE, SECONDS_IN_WEEK);

			// check escrow entries
			expect(await rewardEscrow.numVestingEntries(addr1.address)).to.equal(
				1
			);
			expect(await rewardEscrow.numVestingEntries(addr2.address)).to.equal(
				1
			);
		});

		it('Stake escrowed kwenta', async () => {
			// check escrowed balance(s)
			expect(await rewardEscrow.balanceOf(addr1.address)).to.equal(
				TEST_VALUE
			);
			expect(await rewardEscrow.balanceOf(addr2.address)).to.equal(
				TEST_VALUE
			);

			// stake (different amounts)
			await rewardEscrow.connect(addr1).stakeEscrow(TEST_VALUE);
			await rewardEscrow.connect(addr2).stakeEscrow(SMALLER_TEST_VALUE);

			// check escrow balance(s) and expect balance of 
			// staked escrow to be what was staked above
			expect(
				await stakingRewards.escrowedBalanceOf(addr1.address)
			).to.equal(TEST_VALUE);
			expect(
				await stakingRewards.escrowedBalanceOf(addr2.address)
			).to.equal(SMALLER_TEST_VALUE);
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
			await stakingRewards.connect(addr1).getReward();
			await stakingRewards.connect(addr2).getReward();

			// check escrow balance(s) have increased appropriately
			expect(await rewardEscrow.balanceOf(addr1.address)).to.be.above(
				prevAddr1EscrowBalance
			);
			expect(await rewardEscrow.balanceOf(addr2.address)).to.be.above(
				prevAddr2EscrowBalance
			);

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
			const addr1EscrowStakedBalance =
				await stakingRewards.escrowedBalanceOf(addr1.address);
			const addr2EscrowStakedBalance =
				await stakingRewards.escrowedBalanceOf(addr2.address);

			// unstake KWENTA
			await rewardEscrow
				.connect(addr1)
				.unstakeEscrow(addr1EscrowStakedBalance);
			await rewardEscrow
				.connect(addr2)
				.unstakeEscrow(addr2EscrowStakedBalance);

			// check saked escrow balance(s) and expect balance of staked escrow to be 0
			expect(
				await stakingRewards.escrowedBalanceOf(addr1.address)
			).to.equal(0);
			expect(
				await stakingRewards.escrowedBalanceOf(addr2.address)
			).to.equal(0);
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
				kwenta
					.connect(TREASURY_DAO)
					.transfer(addr1.address, wei(20000).toBN())
			).to.changeTokenBalance(kwenta, addr1, wei(20000).toBN());
			await expect(() =>
				kwenta
					.connect(TREASURY_DAO)
					.transfer(addr2.address, wei(20000).toBN())
			).to.changeTokenBalance(kwenta, addr2, wei(20000).toBN());

			// increase KWENTA allowance for stakingRewards and stake
			await kwenta
				.connect(addr1)
				.approve(stakingRewards.address, wei(20000).toBN());
			await kwenta
				.connect(addr2)
				.approve(stakingRewards.address, wei(20000).toBN());
			await stakingRewards.connect(addr1).stake(wei(20000).toBN());
			await stakingRewards.connect(addr2).stake(wei(20000).toBN());

			// check KWENTA was staked
			expect(
				await stakingRewards
					.connect(addr1)
					.balanceOf(addr1.address)
			).to.equal(wei(20000).toBN());
			expect(
				await stakingRewards
					.connect(addr2)
					.balanceOf(addr2.address)
			).to.equal(wei(20000).toBN());
		});

		it('Wait, and then claim kwenta for both stakers', async () => {
			// establish reward balance pre-claim
			expect(await rewardEscrow.balanceOf(addr1.address)).to.equal(
				await rewardEscrow.balanceOf(addr2.address)
			);

			// wait
			fastForward(SECONDS_IN_WEEK);

			// claim reward(s)
			await stakingRewards.connect(addr1).getReward();
			await stakingRewards.connect(addr2).getReward();

			// expect staker 1 to have greater rewards
			var escrowedBalanceAddr1 = await rewardEscrow.balanceOf(addr1.address)
			var escrowedBalanceAddr2 = await rewardEscrow.balanceOf(addr2.address)
			expect(escrowedBalanceAddr1).to.be.above(
				escrowedBalanceAddr2
			);
			
			// multiple calls to getReward() should not produce any extra rewards
			await stakingRewards.connect(addr1).getReward();
			await stakingRewards.connect(addr2).getReward();
			expect(await rewardEscrow.balanceOf(addr1.address)).to.equal(
					escrowedBalanceAddr1
				);
			expect(await rewardEscrow.balanceOf(addr2.address)).to.equal(
				escrowedBalanceAddr2
			);
		});
	});
});
