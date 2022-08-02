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
const SECONDS_IN_WEEK = 604_800;
const SECONDS_IN_THIRTY_DAYS = 2_592_000;

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

    describe("earned()", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
        });

        it("should be 0 when not staking", async () => {
            expect(await stakingRewards.earned(addr1.address)).to.be.equal(0);
        });

        it("should be > 0 when staking", async () => {
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

        it("rewards token balance should rollover after DURATION", async () => {
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

    describe("getReward()", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
        });

        /**
         * @dev notice difference in this functionality compared to Synthetix's version
         */
        it("should increase kwenta balance in escrow", async () => {
            const preEscrowBalance = await kwenta.balanceOf(
                rewardEscrow.address
            );

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

            await fastForward(SECONDS_IN_WEEK * 2);

            await stakingRewards.connect(addr1).getReward();

            const postEscrowBalance = await kwenta.balanceOf(
                rewardEscrow.address
            );

            expect(postEscrowBalance).to.be.above(preEscrowBalance);
        });
    });

    describe("setRewardsDuration()", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
        });

        it("should increase rewards duration before starting distribution", async () => {
            const defaultDuration = await stakingRewards.rewardsDuration();
            expect(defaultDuration).to.equal(SECONDS_IN_WEEK);

            await stakingRewards
                .connect(owner)
                .setRewardsDuration(SECONDS_IN_THIRTY_DAYS);
            const newDuration = await stakingRewards.rewardsDuration();
            expect(newDuration).to.equal(SECONDS_IN_THIRTY_DAYS);
        });

        it("should revert when setting setRewardsDuration before the period has finished", async () => {
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

            await fastForward(SECONDS_IN_WEEK / 7);

            let tx = stakingRewards
                .connect(owner)
                .setRewardsDuration(SECONDS_IN_THIRTY_DAYS);
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Previous rewards period must be complete before changing the duration for the new period"
            );
        });

        it("should update when setting setRewardsDuration after the period has finished", async () => {
            await kwenta
                .connect(TREASURY_DAO)
                .transfer(addr1.address, TEST_VALUE);
            await kwenta
                .connect(addr1)
                .approve(stakingRewards.address, TEST_VALUE);

            // stake
            await stakingRewards.connect(addr1).stake(TEST_VALUE);

            await stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(SECONDS_IN_WEEK);

            await fastForward(SECONDS_IN_WEEK * 2);

            const tx = await stakingRewards
                .connect(owner)
                .setRewardsDuration(SECONDS_IN_THIRTY_DAYS);
            expect(tx).to.emit(stakingRewards, "RewardsDurationUpdated");

            const newDuration = await stakingRewards.rewardsDuration();
            expect(newDuration).to.equal(SECONDS_IN_THIRTY_DAYS);

            await stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(TEST_VALUE);
        });

        it("should update when setting setRewardsDuration after the period has finished", async () => {
            await kwenta
                .connect(TREASURY_DAO)
                .transfer(addr1.address, TEST_VALUE);
            await kwenta
                .connect(addr1)
                .approve(stakingRewards.address, TEST_VALUE);

            // stake
            await stakingRewards.connect(addr1).stake(TEST_VALUE);

            await stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(SECONDS_IN_THIRTY_DAYS);

            await fastForward(SECONDS_IN_WEEK);
            await stakingRewards.connect(addr1).getReward();
            await fastForward(SECONDS_IN_WEEK);

            // New Rewards period much lower
            const tx = await stakingRewards
                .connect(owner)
                .setRewardsDuration(SECONDS_IN_THIRTY_DAYS);
            expect(tx).to.emit(stakingRewards, "RewardsDurationUpdated");

            const newDuration = await stakingRewards.rewardsDuration();
            expect(newDuration).to.equal(SECONDS_IN_THIRTY_DAYS);

            await stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(SECONDS_IN_THIRTY_DAYS);

            await fastForward(SECONDS_IN_THIRTY_DAYS);
            await stakingRewards.connect(addr1).getReward();
        });
    });

    describe("getRewardForDuration()", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
        });

        it("should increase rewards token balance", async () => {
            await kwenta
                .connect(TREASURY_DAO)
                .transfer(stakingRewards.address, TEST_VALUE);
            await stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(TEST_VALUE);

            const rewardForDuration =
                await stakingRewards.getRewardForDuration();

            const duration = await stakingRewards.rewardsDuration();
            const rewardRate = await stakingRewards.rewardRate();

            expect(rewardForDuration).to.be.above(0);
            expect(rewardForDuration).to.equal(duration.mul(rewardRate));
        });
    });

    /**
     * @dev notice difference in function name compared to Synthetix's version
     */
    describe("unstake()", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
        });

        it("cannot unstake if nothing staked", async () => {
            let tx = stakingRewards.connect(addr1).unstake(TEST_VALUE);
            await expect(tx).to.be.reverted;
        });

        it("should increases lp token balance and decreases staking balance", async () => {
            await kwenta
                .connect(TREASURY_DAO)
                .transfer(addr1.address, TEST_VALUE);
            await kwenta
                .connect(addr1)
                .approve(stakingRewards.address, TEST_VALUE);

            // stake
            await stakingRewards.connect(addr1).stake(TEST_VALUE);

            const initialStakingTokenBal = await kwenta.balanceOf(
                addr1.address
            );
            const initialStakeBal = await stakingRewards.balanceOf(
                addr1.address
            );

            await stakingRewards.connect(addr1).unstake(TEST_VALUE);

            const postStakingTokenBal = await kwenta.balanceOf(addr1.address);
            const postStakeBal = await stakingRewards.balanceOf(addr1.address);

            expect(postStakeBal.add(TEST_VALUE)).to.equal(initialStakeBal);
            expect(initialStakingTokenBal.add(TEST_VALUE)).to.equal(
                postStakingTokenBal
            );
        });

        it("cannot unstake 0", async () => {
            let tx = stakingRewards.connect(addr1).unstake(0);
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Cannot Unstake 0"
            );
        });
    });

    describe("exit()", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
        });

        it("should retrieve all earned and increase rewards bal", async () => {
            await kwenta
                .connect(TREASURY_DAO)
                .transfer(addr1.address, TEST_VALUE);
            await kwenta
                .connect(addr1)
                .approve(stakingRewards.address, TEST_VALUE);

            // stake
            await stakingRewards.connect(addr1).stake(TEST_VALUE);

            await stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(TEST_VALUE);

            await fastForward(SECONDS_IN_WEEK * 2);

            const initialRewardBal = await kwenta.balanceOf(addr1.address);
            const initialEarnedBal = await stakingRewards.earned(addr1.address);
            await stakingRewards.connect(addr1).exit();
            const postRewardBal = await kwenta.balanceOf(addr1.address);
            const postEarnedBal = await stakingRewards.earned(addr1.address);

            expect(postEarnedBal).to.be.below(initialEarnedBal);
            expect(postRewardBal).to.be.above(initialRewardBal);
            expect(postEarnedBal).to.be.equal(0);
        });
    });

    describe("notifyRewardAmount()", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
        });

        it("Reverts if the provided reward is greater than the balance.", async () => {
            const stakingRewardsKwentaBalance = await kwenta.balanceOf(
                stakingRewards.address
            );

            let tx = stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(
                    stakingRewardsKwentaBalance.add(TEST_VALUE)
                );
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Provided reward too high"
            );
        });

        it("Reverts if the provided reward is greater than the balance, plus rolled-over balance.", async () => {
            const stakingRewardsKwentaBalance = await kwenta.balanceOf(
                stakingRewards.address
            );
            await stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(stakingRewardsKwentaBalance);

            await kwenta
                .connect(TREASURY_DAO)
                .transfer(stakingRewards.address, stakingRewardsKwentaBalance);

            // Now take into account any leftover quantity.
            let tx = stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(
                    stakingRewardsKwentaBalance.add(TEST_VALUE)
                );
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Provided reward too high"
            );
        });
    });

    describe("problems...", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
        });

        /**
         * @dev investigate this
         */
        it("Doesn't revert if the provided reward is greater than the balance by a very small amount.", async () => {
            // max amount, theoretically, that new reward could be set to 
            // (i.e. no rate would be high enough to meet any amount higher than this)
            // balance: 100
            // reward: 101
            // rate (for a duration of 100 secs): 1.01/sec
            const stakingRewardsKwentaBalance = await kwenta.balanceOf(
                stakingRewards.address
            );

            let tx = stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(stakingRewardsKwentaBalance.add(100_000));
            await expect(tx).to.not.be.reverted;
        });
    });
});
