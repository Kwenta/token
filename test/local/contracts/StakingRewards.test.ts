import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "@ethersproject/contracts";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { wei } from "@synthetixio/wei";
import { loadFixture } from "ethereum-waffle";
import { deployKwenta } from "../../utils/kwenta";
import { impersonate, fastForward, currentTime } from "../../utils/helpers";
import { add } from "lodash";

// constants
const NAME = "Kwenta";
const SYMBOL = "KWENTA";
const INITIAL_SUPPLY = ethers.utils.parseUnits("313373");
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

// mock token
let mockToken: Contract;

// deploy contracts and transfer 1/4 supply of kwenta to staking rewards
const setupStakingRewards = async () => {
    // get signers
    [owner, addr1, addr2, TREASURY_DAO] = await ethers.getSigners();

    // deploy contracts
    let deployments = await deployKwenta(
        NAME,
        SYMBOL,
        INITIAL_SUPPLY,
        owner,
        TREASURY_DAO
    );
    kwenta = deployments.kwenta;
    supplySchedule = deployments.supplySchedule;
    rewardEscrow = deployments.rewardEscrow;
    stakingRewards = deployments.stakingRewards;

    // fund StakingRewards
    await kwenta
        .connect(TREASURY_DAO)
        .transfer(stakingRewards.address, INITIAL_SUPPLY.div(4));
};

// Using Kwenta.sol contract as a mock token for testing
// Please notice: mockToken != kwenta
const deployMockToken = async () => {
    const MockToken = await ethers.getContractFactory("Kwenta");
    mockToken = await MockToken.deploy(
        "Mock",
        "MOCK",
        INITIAL_SUPPLY,
        owner.address,
        TREASURY_DAO.address
    );
};

/**
 * @notice stakingRewards is funded with reward tokens (KWENTA) when
 * setupStakingRewards() is called
 * @notice mockToken is based on kwenta.sol, but IS NOT kwenta
 * (mockToken used for testing ONLY)
 * @notice sometimes SECONDS_IN_WEEK is used for fastForwarding time and amounts.
 * This might be confusing, but SECONDS_IN_WEEK is only a number and
 * makes testing easier. Example: notifyRewardAmount(604800), stake(604800), rewardsDuration(604800)
 * makes math pretty easy to follow. Hope that helps (:
 */

describe("StakingRewards", () => {
    describe("Constructor & Settings", () => {
        beforeEach("Setup", async () => {
            await loadFixture(setupStakingRewards);
        });

        it("should set rewards token on constructor", async () => {
            expect(await stakingRewards.rewardsToken()).to.equal(
                kwenta.address
            );
        });

        it("should set staking token on constructor", async () => {
            expect(await stakingRewards.stakingToken()).to.equal(
                kwenta.address
            );
        });

        it("should set owner on constructor", async () => {
            const ownerAddress = await stakingRewards.owner();
            expect(ownerAddress).to.equal(owner.address);
        });
    });

    describe("Function Permissions", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
        });

        it("only SupplySchedule can call notifyRewardAmount", async () => {
            let tx = stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(TEST_VALUE);
            await expect(tx).to.not.be.reverted;

            tx = stakingRewards.notifyRewardAmount(TEST_VALUE);
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Only Supply Schedule"
            );
        });

        it("only owner address can call setRewardsDuration", async () => {
            // ff
            await fastForward(SECONDS_IN_WEEK);

            let tx = stakingRewards
                .connect(owner)
                .setRewardsDuration(SECONDS_IN_WEEK);
            await expect(tx).to.not.be.reverted;

            tx = stakingRewards
                .connect(addr1)
                .setRewardsDuration(SECONDS_IN_WEEK);
            await expect(tx).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
        });

        it("only owner address can call recoverERC20", async () => {
            let tx = stakingRewards
                .connect(addr1)
                .recoverERC20(kwenta.address, 0);
            await expect(tx).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );

            // notice following tx passes owner check despite ultimately failing
            tx = stakingRewards.connect(owner).recoverERC20(kwenta.address, 0);
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Cannot unstake the staking token"
            );
        });

        it("only RewardEscrow address can call stakeEscrow", async () => {
            let tx = stakingRewards
                .connect(addr1)
                .stakeEscrow(addr1.address, TEST_VALUE);
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Only Reward Escrow"
            );

            // notice following tx passes rewardEscrow check despite ultimately failing
            tx = stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, TEST_VALUE);
            await expect(tx).to.not.be.reverted;
        });

        it("only RewardEscrow address can call unstakeEscrow", async () => {
            let tx = stakingRewards
                .connect(addr2)
                .unstakeEscrow(addr2.address, TEST_VALUE);
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Only Reward Escrow"
            );

            // notice following tx passes rewardEscrow check despite ultimately failing
            tx = stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .unstakeEscrow(addr2.address, TEST_VALUE);
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Invalid Amount"
            );
        });

        it("only owner address can pause/unpause contract", async () => {
            // attempt to pause
            let tx = stakingRewards.connect(addr2).pauseStakingRewards();
            await expect(tx).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );

            // pause
            tx = stakingRewards.connect(owner).pauseStakingRewards();
            await expect(tx).to.not.be.reverted;

            // attempt to unpause
            tx = stakingRewards.connect(addr2).unpauseStakingRewards();
            await expect(tx).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );

            // unpause
            tx = stakingRewards.connect(owner).unpauseStakingRewards();
            await expect(tx).to.not.be.reverted;
        });
    });

    describe("Pausable", async () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
        });

        it("should revert calling stake() when paused", async () => {
            // pause
            await stakingRewards.connect(owner).pauseStakingRewards();
            expect(await stakingRewards.paused()).to.equal(true);

            await kwenta
                .connect(TREASURY_DAO)
                .transfer(addr1.address, TEST_VALUE);
            await kwenta
                .connect(addr1)
                .approve(stakingRewards.address, TEST_VALUE);

            let tx = stakingRewards.connect(addr1).stake(TEST_VALUE);
            await expect(tx).to.be.revertedWith("Pausable: paused");
        });

        it("should not revert calling stake() when unpaused", async () => {
            // pause
            await stakingRewards.connect(owner).pauseStakingRewards();
            expect(await stakingRewards.paused()).to.equal(true);

            // unpause
            await stakingRewards.connect(owner).unpauseStakingRewards();

            await kwenta
                .connect(TREASURY_DAO)
                .transfer(addr2.address, TEST_VALUE);
            await kwenta
                .connect(addr2)
                .approve(stakingRewards.address, TEST_VALUE);

            let tx = stakingRewards.connect(addr2).stake(TEST_VALUE);
            await expect(tx).to.not.be.reverted;
        });
    });

    describe("External Rewards Recovery", () => {
        beforeEach(async () => {
            await setupStakingRewards();
            await deployMockToken();

            // Send non-staking ERC20 to StakingRewards Contract
            await mockToken
                .connect(TREASURY_DAO)
                .transfer(stakingRewards.address, TEST_VALUE);
            expect(await mockToken.balanceOf(stakingRewards.address)).is.equal(
                TEST_VALUE
            );
        });

        it("should revert if recovering staking token", async () => {
            let tx = stakingRewards
                .connect(owner)
                .recoverERC20(kwenta.address, TEST_VALUE);
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Cannot unstake the staking toke"
            );
        });

        it("should retrieve external token from StakingRewards and reduce contracts balance", async () => {
            await stakingRewards
                .connect(owner)
                .recoverERC20(mockToken.address, TEST_VALUE);
            expect(await mockToken.balanceOf(stakingRewards.address)).is.equal(
                0
            );
        });

        it("should retrieve external token from StakingRewards and increase owners balance", async () => {
            const prevBalance = await mockToken.balanceOf(owner.address);
            await stakingRewards
                .connect(owner)
                .recoverERC20(mockToken.address, TEST_VALUE);
            const postBalance = await mockToken.balanceOf(owner.address);
            expect(postBalance).to.equal(prevBalance.add(TEST_VALUE));
        });
    });

    describe("lastTimeRewardApplicable()", () => {
        it("should return 0", async () => {
            await setupStakingRewards();

            const lastTimeRewardApplicable =
                await stakingRewards.lastTimeRewardApplicable();
            expect(lastTimeRewardApplicable).to.equal(0);
        });

        describe("when updated", () => {
            it("should equal current timestamp", async () => {
                await stakingRewards
                    .connect(await impersonate(supplySchedule.address))
                    .notifyRewardAmount(TEST_VALUE);

                const cur = await currentTime();
                const lastTimeReward =
                    await stakingRewards.lastTimeRewardApplicable();

                expect(cur).to.equal(lastTimeReward);
            });
        });
    });

    describe("rewardPerToken()", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
        });

        it("should return 0", async () => {
            expect(await stakingRewards.rewardPerToken()).to.equal(0);
        });

        it("should be > 0", async () => {
            await kwenta
                .connect(TREASURY_DAO)
                .transfer(addr1.address, SECONDS_IN_WEEK);
            await kwenta
                .connect(addr1)
                .approve(stakingRewards.address, SECONDS_IN_WEEK);

            // stake
            await stakingRewards.connect(addr1).stake(SECONDS_IN_WEEK);

            const totalSupply = await stakingRewards.totalSupply();
            expect(totalSupply).to.be.above(0);

            // set rewards
            await stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(SECONDS_IN_WEEK);

            // ff
            await fastForward(SECONDS_IN_WEEK * 2);

            const rewardPerToken = await stakingRewards.rewardPerToken();
            expect(rewardPerToken).to.be.above(0);
        });
    });

    describe("stake()", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
        });

        it("staking increases staking balance", async () => {
            await kwenta
                .connect(TREASURY_DAO)
                .transfer(addr1.address, SECONDS_IN_WEEK);
            await kwenta
                .connect(addr1)
                .approve(stakingRewards.address, SECONDS_IN_WEEK);

            const initialStakeBal = await stakingRewards.balanceOf(
                addr1.address
            );

            // stake
            await stakingRewards.connect(addr1).stake(SECONDS_IN_WEEK);

            const postStakeBal = await stakingRewards.balanceOf(addr1.address);

            expect(postStakeBal).is.above(initialStakeBal);
        });

        it("cannot stake 0", async () => {
            let tx = stakingRewards.stake(0);
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Cannot stake 0"
            );
        });
    });

    describe('earned()', () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
        });

    	it('should be 0 when not staking', async () => {
    		expect(await stakingRewards.earned(addr1.address)).to.be.equal(0);
    	});

    	it('should be > 0 when staking', async () => {
    		await kwenta
                .connect(TREASURY_DAO)
                .transfer(addr1.address, SECONDS_IN_WEEK);
            await kwenta
                .connect(addr1)
                .approve(stakingRewards.address, SECONDS_IN_WEEK);

            // stake
            await stakingRewards.connect(addr1).stake(SECONDS_IN_WEEK);

    		// set rewards
            await stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(SECONDS_IN_WEEK);

    		await fastForward(SECONDS_IN_WEEK * 2);

    		const earned = await stakingRewards.earned(addr1.address);

    		expect(earned).to.be.above(0);
    	});

    	it("rewardRate should increase if new rewards come before DURATION ends", async () => {
            const totalToDistribute = wei(5000).toBN();

            await kwenta
                .connect(TREASURY_DAO)
                .transfer(addr1.address, SECONDS_IN_WEEK);
            await kwenta
                .connect(addr1)
                .approve(stakingRewards.address, SECONDS_IN_WEEK);

            // stake
            await stakingRewards.connect(addr1).stake(SECONDS_IN_WEEK);

            await kwenta
                .connect(TREASURY_DAO)
                .transfer(stakingRewards.address, totalToDistribute);
            await stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(totalToDistribute);

            const rewardRateInitial = await stakingRewards.rewardRate();

            await kwenta
                .connect(TREASURY_DAO)
                .transfer(stakingRewards.address, totalToDistribute);
            await stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(totalToDistribute);

            const rewardRateLater = await stakingRewards.rewardRate();

            expect(rewardRateInitial).to.be.above(0);
            expect(rewardRateLater).to.be.above(rewardRateInitial);
        });

    	it('rewards token balance should rollover after DURATION', async () => {
    		await kwenta
                .connect(TREASURY_DAO)
                .transfer(addr1.address, SECONDS_IN_WEEK);
            await kwenta
                .connect(addr1)
                .approve(stakingRewards.address, SECONDS_IN_WEEK);

    		// stake
            await stakingRewards.connect(addr1).stake(SECONDS_IN_WEEK);

    		await stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(SECONDS_IN_WEEK);

    		await fastForward(SECONDS_IN_WEEK);
    		const earnedFirst = await stakingRewards.earned(addr1.address);

    		await stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(SECONDS_IN_WEEK);

            await fastForward(SECONDS_IN_WEEK);
    		const earnedSecond = await stakingRewards.earned(addr1.address);

    		expect(earnedSecond).to.equal(earnedFirst.add(earnedFirst));
    	});
    });

    // describe('getReward()', () => {
    // 	it('should increase rewards token balance', async () => {
    // 		const totalToStake = toUnit('100');
    // 		const totalToDistribute = toUnit('5000');

    // 		await stakingToken.transfer(stakingAccount1, totalToStake, { from: owner });
    // 		await stakingToken.approve(stakingRewards.address, totalToStake, { from: stakingAccount1 });
    // 		await stakingRewards.stake(totalToStake, { from: stakingAccount1 });

    // 		await rewardsToken.transfer(stakingRewards.address, totalToDistribute, { from: owner });
    // 		await stakingRewards.notifyRewardAmount(totalToDistribute, {
    // 			from: mockRewardsDistributionAddress,
    // 		});

    // 		await fastForward(DAY);

    // 		const initialRewardBal = await rewardsToken.balanceOf(stakingAccount1);
    // 		const initialEarnedBal = await stakingRewards.earned(stakingAccount1);
    // 		await stakingRewards.getReward({ from: stakingAccount1 });
    // 		const postRewardBal = await rewardsToken.balanceOf(stakingAccount1);
    // 		const postEarnedBal = await stakingRewards.earned(stakingAccount1);

    // 		assert.bnLt(postEarnedBal, initialEarnedBal);
    // 		assert.bnGt(postRewardBal, initialRewardBal);
    // 	});
    // });

    // describe('setRewardsDuration()', () => {
    // 	const sevenDays = DAY * 7;
    // 	const seventyDays = DAY * 70;
    // 	it('should increase rewards duration before starting distribution', async () => {
    // 		const defaultDuration = await stakingRewards.rewardsDuration();
    // 		assert.bnEqual(defaultDuration, sevenDays);

    // 		await stakingRewards.setRewardsDuration(seventyDays, { from: owner });
    // 		const newDuration = await stakingRewards.rewardsDuration();
    // 		assert.bnEqual(newDuration, seventyDays);
    // 	});
    // 	it('should revert when setting setRewardsDuration before the period has finished', async () => {
    // 		const totalToStake = toUnit('100');
    // 		const totalToDistribute = toUnit('5000');

    // 		await stakingToken.transfer(stakingAccount1, totalToStake, { from: owner });
    // 		await stakingToken.approve(stakingRewards.address, totalToStake, { from: stakingAccount1 });
    // 		await stakingRewards.stake(totalToStake, { from: stakingAccount1 });

    // 		await rewardsToken.transfer(stakingRewards.address, totalToDistribute, { from: owner });
    // 		await stakingRewards.notifyRewardAmount(totalToDistribute, {
    // 			from: mockRewardsDistributionAddress,
    // 		});

    // 		await fastForward(DAY);

    // 		await assert.revert(
    // 			stakingRewards.setRewardsDuration(seventyDays, { from: owner }),
    // 			'Previous rewards period must be complete before changing the duration for the new period'
    // 		);
    // 	});
    // 	it('should update when setting setRewardsDuration after the period has finished', async () => {
    // 		const totalToStake = toUnit('100');
    // 		const totalToDistribute = toUnit('5000');

    // 		await stakingToken.transfer(stakingAccount1, totalToStake, { from: owner });
    // 		await stakingToken.approve(stakingRewards.address, totalToStake, { from: stakingAccount1 });
    // 		await stakingRewards.stake(totalToStake, { from: stakingAccount1 });

    // 		await rewardsToken.transfer(stakingRewards.address, totalToDistribute, { from: owner });
    // 		await stakingRewards.notifyRewardAmount(totalToDistribute, {
    // 			from: mockRewardsDistributionAddress,
    // 		});

    // 		await fastForward(DAY * 8);

    // 		const transaction = await stakingRewards.setRewardsDuration(seventyDays, { from: owner });
    // 		assert.eventEqual(transaction, 'RewardsDurationUpdated', {
    // 			newDuration: seventyDays,
    // 		});

    // 		const newDuration = await stakingRewards.rewardsDuration();
    // 		assert.bnEqual(newDuration, seventyDays);

    // 		await stakingRewards.notifyRewardAmount(totalToDistribute, {
    // 			from: mockRewardsDistributionAddress,
    // 		});
    // 	});

    // 	it('should update when setting setRewardsDuration after the period has finished', async () => {
    // 		const totalToStake = toUnit('100');
    // 		const totalToDistribute = toUnit('5000');

    // 		await stakingToken.transfer(stakingAccount1, totalToStake, { from: owner });
    // 		await stakingToken.approve(stakingRewards.address, totalToStake, { from: stakingAccount1 });
    // 		await stakingRewards.stake(totalToStake, { from: stakingAccount1 });

    // 		await rewardsToken.transfer(stakingRewards.address, totalToDistribute, { from: owner });
    // 		await stakingRewards.notifyRewardAmount(totalToDistribute, {
    // 			from: mockRewardsDistributionAddress,
    // 		});

    // 		await fastForward(DAY * 4);
    // 		await stakingRewards.getReward({ from: stakingAccount1 });
    // 		await fastForward(DAY * 4);

    // 		// New Rewards period much lower
    // 		await rewardsToken.transfer(stakingRewards.address, totalToDistribute, { from: owner });
    // 		const transaction = await stakingRewards.setRewardsDuration(seventyDays, { from: owner });
    // 		assert.eventEqual(transaction, 'RewardsDurationUpdated', {
    // 			newDuration: seventyDays,
    // 		});

    // 		const newDuration = await stakingRewards.rewardsDuration();
    // 		assert.bnEqual(newDuration, seventyDays);

    // 		await stakingRewards.notifyRewardAmount(totalToDistribute, {
    // 			from: mockRewardsDistributionAddress,
    // 		});

    // 		await fastForward(DAY * 71);
    // 		await stakingRewards.getReward({ from: stakingAccount1 });
    // 	});
    // });

    // describe('getRewardForDuration()', () => {
    // 	it('should increase rewards token balance', async () => {
    // 		const totalToDistribute = toUnit('5000');
    // 		await rewardsToken.transfer(stakingRewards.address, totalToDistribute, { from: owner });
    // 		await stakingRewards.notifyRewardAmount(totalToDistribute, {
    // 			from: mockRewardsDistributionAddress,
    // 		});

    // 		const rewardForDuration = await stakingRewards.getRewardForDuration();

    // 		const duration = await stakingRewards.rewardsDuration();
    // 		const rewardRate = await stakingRewards.rewardRate();

    // 		assert.bnGt(rewardForDuration, ZERO_BN);
    // 		assert.bnEqual(rewardForDuration, duration.mul(rewardRate));
    // 	});
    // });

    // describe('withdraw()', () => {
    // 	it('cannot withdraw if nothing staked', async () => {
    // 		await assert.revert(stakingRewards.withdraw(toUnit('100')), 'SafeMath: subtraction overflow');
    // 	});

    // 	it('should increases lp token balance and decreases staking balance', async () => {
    // 		const totalToStake = toUnit('100');
    // 		await stakingToken.transfer(stakingAccount1, totalToStake, { from: owner });
    // 		await stakingToken.approve(stakingRewards.address, totalToStake, { from: stakingAccount1 });
    // 		await stakingRewards.stake(totalToStake, { from: stakingAccount1 });

    // 		const initialStakingTokenBal = await stakingToken.balanceOf(stakingAccount1);
    // 		const initialStakeBal = await stakingRewards.balanceOf(stakingAccount1);

    // 		await stakingRewards.withdraw(totalToStake, { from: stakingAccount1 });

    // 		const postStakingTokenBal = await stakingToken.balanceOf(stakingAccount1);
    // 		const postStakeBal = await stakingRewards.balanceOf(stakingAccount1);

    // 		assert.bnEqual(postStakeBal.add(toBN(totalToStake)), initialStakeBal);
    // 		assert.bnEqual(initialStakingTokenBal.add(toBN(totalToStake)), postStakingTokenBal);
    // 	});

    // 	it('cannot withdraw 0', async () => {
    // 		await assert.revert(stakingRewards.withdraw('0'), 'Cannot withdraw 0');
    // 	});
    // });

    // describe('exit()', () => {
    // 	it('should retrieve all earned and increase rewards bal', async () => {
    // 		const totalToStake = toUnit('100');
    // 		const totalToDistribute = toUnit('5000');

    // 		await stakingToken.transfer(stakingAccount1, totalToStake, { from: owner });
    // 		await stakingToken.approve(stakingRewards.address, totalToStake, { from: stakingAccount1 });
    // 		await stakingRewards.stake(totalToStake, { from: stakingAccount1 });

    // 		await rewardsToken.transfer(stakingRewards.address, totalToDistribute, { from: owner });
    // 		await stakingRewards.notifyRewardAmount(toUnit(5000.0), {
    // 			from: mockRewardsDistributionAddress,
    // 		});

    // 		await fastForward(DAY);

    // 		const initialRewardBal = await rewardsToken.balanceOf(stakingAccount1);
    // 		const initialEarnedBal = await stakingRewards.earned(stakingAccount1);
    // 		await stakingRewards.exit({ from: stakingAccount1 });
    // 		const postRewardBal = await rewardsToken.balanceOf(stakingAccount1);
    // 		const postEarnedBal = await stakingRewards.earned(stakingAccount1);

    // 		assert.bnLt(postEarnedBal, initialEarnedBal);
    // 		assert.bnGt(postRewardBal, initialRewardBal);
    // 		assert.bnEqual(postEarnedBal, ZERO_BN);
    // 	});
    // });

    // describe('notifyRewardAmount()', () => {
    // 	let localStakingRewards;

    // 	before(async () => {
    // 		localStakingRewards = await setupContract({
    // 			accounts,
    // 			contract: 'StakingRewards',
    // 			args: [owner, rewardsDistribution.address, rewardsToken.address, stakingToken.address],
    // 		});

    // 		await localStakingRewards.setRewardsDistribution(mockRewardsDistributionAddress, {
    // 			from: owner,
    // 		});
    // 	});

    // 	it('Reverts if the provided reward is greater than the balance.', async () => {
    // 		const rewardValue = toUnit(1000);
    // 		await rewardsToken.transfer(localStakingRewards.address, rewardValue, { from: owner });
    // 		await assert.revert(
    // 			localStakingRewards.notifyRewardAmount(rewardValue.add(toUnit(0.1)), {
    // 				from: mockRewardsDistributionAddress,
    // 			}),
    // 			'Provided reward too high'
    // 		);
    // 	});

    // 	it('Reverts if the provided reward is greater than the balance, plus rolled-over balance.', async () => {
    // 		const rewardValue = toUnit(1000);
    // 		await rewardsToken.transfer(localStakingRewards.address, rewardValue, { from: owner });
    // 		localStakingRewards.notifyRewardAmount(rewardValue, {
    // 			from: mockRewardsDistributionAddress,
    // 		});
    // 		await rewardsToken.transfer(localStakingRewards.address, rewardValue, { from: owner });
    // 		// Now take into account any leftover quantity.
    // 		await assert.revert(
    // 			localStakingRewards.notifyRewardAmount(rewardValue.add(toUnit(0.1)), {
    // 				from: mockRewardsDistributionAddress,
    // 			}),
    // 			'Provided reward too high'
    // 		);
    // 	});
    // });

    //////
    //////
    //////
    //////
    //////
});
