import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "@ethersproject/contracts";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { wei } from "@synthetixio/wei";
import { loadFixture } from "ethereum-waffle";
import { deployKwenta } from "../../utils/kwenta";
import { impersonate, fastForward, currentTime } from "../../utils/helpers";
import { BigNumber } from "ethers";

// constants
const NAME = "Kwenta";
const SYMBOL = "KWENTA";
const INITIAL_SUPPLY = ethers.utils.parseUnits("313373");
const SECONDS_IN_WEEK = 604_800;
const SECONDS_IN_THIRTY_DAYS = 2_592_000;

// test values for staking
const TEST_VALUE = wei(2000).toBN();

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

/**
 * @notice deploy contracts and transfer 1/4 supply of kwenta to staking rewards
 */
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

/**
 * @notice using Kwenta.sol contract as a mock token for testing.
 * Please notice: mockToken != kwenta
 */
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
 * @noitce transfer kwenta to rewardEscrow contract and approve StakingRewards to spend amount
 * @param amount - amount to transfer and approve
 */
const fundAndApproveRewardEscrow = async (amount: number) => {
    // fund rewardEscrow
    await kwenta.connect(TREASURY_DAO).transfer(rewardEscrow.address, amount);

    // approve StakingRewards
    await kwenta
        .connect(await impersonate(rewardEscrow.address))
        .approve(stakingRewards.address, amount);
};

/**
 * @noitce transfer kwenta to account and approve StakingRewards to spend amount
 * @param account - account to transfer amount to
 * @param amount - amount to transfer and approve
 */
const fundAndApproveAccount = async (
    account: SignerWithAddress,
    amount: number | BigNumber
) => {
    await kwenta.connect(TREASURY_DAO).transfer(account.address, amount);
    await kwenta.connect(account).approve(stakingRewards.address, amount);
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

        it("should set staking/rewards token on constructor", async () => {
            expect(await stakingRewards.token()).to.equal(kwenta.address);
        });

        it("should set owner on constructor", async () => {
            const ownerAddress = await stakingRewards.owner();
            expect(ownerAddress).to.equal(owner.address);
        });

        it("should set RewardEscrow on constructor", async () => {
            expect(await stakingRewards.rewardEscrow()).to.equal(
                rewardEscrow.address
            );
        });

        it("should set supplySchedule on constructor", async () => {
            expect(await stakingRewards.supplySchedule()).to.equal(
                supplySchedule.address
            );
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
                "Only the contract owner may perform this action"
            );
        });

        it("only owner address can call recoverERC20", async () => {
            let tx = stakingRewards
                .connect(addr1)
                .recoverERC20(kwenta.address, 0);
            await expect(tx).to.be.revertedWith(
                "Only the contract owner may perform this action"
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
                "Only the contract owner may perform this action"
            );

            // pause
            tx = stakingRewards.connect(owner).pauseStakingRewards();
            await expect(tx).to.not.be.reverted;

            // attempt to unpause
            tx = stakingRewards.connect(addr2).unpauseStakingRewards();
            await expect(tx).to.be.revertedWith(
                "Only the contract owner may perform this action"
            );

            // unpause
            tx = stakingRewards.connect(owner).unpauseStakingRewards();
            await expect(tx).to.not.be.reverted;
        });

        it("only owner can nominate new owner", async () => {
            // attempt to nominate new owner as addr1
            let tx = stakingRewards.connect(addr1).nominateNewOwner(addr1.address);
            await expect(tx).to.be.revertedWith(
                "Only the contract owner may perform this action"
            );

            // attempt to nominate new owner as owner
            tx = stakingRewards.connect(owner).nominateNewOwner(addr1.address);
            await expect(tx).to.not.be.reverted;

            await stakingRewards.connect(addr1).acceptOwnership();

            expect(await stakingRewards.owner()).to.equal(addr1.address);
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

            await fundAndApproveAccount(addr1, TEST_VALUE);

            let tx = stakingRewards.connect(addr1).stake(TEST_VALUE);
            await expect(tx).to.be.revertedWith("Pausable: paused");
        });

        it("should not revert calling stake() when unpaused", async () => {
            // pause
            await stakingRewards.connect(owner).pauseStakingRewards();
            expect(await stakingRewards.paused()).to.equal(true);

            // unpause
            await stakingRewards.connect(owner).unpauseStakingRewards();

            await fundAndApproveAccount(addr2, TEST_VALUE);

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
            await fundAndApproveAccount(addr1, SECONDS_IN_WEEK);
        });

        it("should return 0", async () => {
            expect(await stakingRewards.rewardPerToken()).to.equal(0);
        });

        it("should be > 0", async () => {
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
            await fundAndApproveAccount(addr1, SECONDS_IN_WEEK);
        });

        it("staking increases token balance", async () => {
            const preBal = await kwenta.balanceOf(stakingRewards.address);

            // stake
            await stakingRewards.connect(addr1).stake(SECONDS_IN_WEEK);

            const postBal = await kwenta.balanceOf(stakingRewards.address);

            expect(postBal).to.be.above(preBal);
        });

        it("staking increases balances[] mapping", async () => {
            const preBal = await stakingRewards.balanceOf(addr1.address);

            // stake
            await stakingRewards.connect(addr1).stake(SECONDS_IN_WEEK);

            const postBal = await stakingRewards.balanceOf(addr1.address);

            expect(postBal).to.be.above(preBal);
        });

        it("staking does NOT increase escrowedBalances[] mapping", async () => {
            const preBal = await stakingRewards.escrowedBalanceOf(
                addr1.address
            );

            // stake
            await stakingRewards.connect(addr1).stake(SECONDS_IN_WEEK);

            const postBal = await stakingRewards.escrowedBalanceOf(
                addr1.address
            );

            expect(postBal).to.equal(preBal);
        });

        // increase total supply AND token balance
        it("staking increases totalSupply", async () => {
            const preBal = await stakingRewards.totalSupply();

            // stake
            await stakingRewards.connect(addr1).stake(SECONDS_IN_WEEK);

            const postBal = await stakingRewards.totalSupply();

            expect(postBal).to.be.above(preBal);
        });

        it("cannot stake 0", async () => {
            let tx = stakingRewards.stake(0);
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Cannot stake 0"
            );
        });
    });

    describe("stakeEscrow()", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
            await fundAndApproveRewardEscrow(SECONDS_IN_WEEK);
        });

        it("escrowStaking does NOT increase token balance", async () => {
            const preBal = await kwenta.balanceOf(stakingRewards.address);

            // stake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, SECONDS_IN_WEEK);

            const postBal = await kwenta.balanceOf(stakingRewards.address);

            expect(preBal).to.equal(postBal);
        });

        it("escrowStaking increases balances[] mapping", async () => {
            const preBal = await stakingRewards.balanceOf(addr1.address);

            // stake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, SECONDS_IN_WEEK);

            const postBal = await stakingRewards.balanceOf(addr1.address);

            expect(postBal).to.be.above(preBal);
        });

        it("escrowStaking increases escrowedBalances[] mapping", async () => {
            const preBal = await stakingRewards.escrowedBalanceOf(
                addr1.address
            );

            // stake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, SECONDS_IN_WEEK);

            const postBal = await stakingRewards.escrowedBalanceOf(
                addr1.address
            );

            expect(postBal).to.be.above(preBal);
        });

        // increase total supply but not token balance
        it("escrowStaking increases totalSupply", async () => {
            const preBal = await stakingRewards.totalSupply();

            // stake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, SECONDS_IN_WEEK);

            const postBal = await stakingRewards.totalSupply();

            expect(postBal).to.be.above(preBal);
        });

        it("cannot stake 0", async () => {
            let tx = stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, 0);
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Cannot stake 0"
            );
        });

        it("stake escrow then call unstake()", async () => {
            // stake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, SECONDS_IN_WEEK);

            // call unstake (not unstakeEscrow)
            let tx = stakingRewards.connect(addr1).unstake(SECONDS_IN_WEEK);
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Invalid Amount"
            );
        });

        it("stake escrow then call exit()", async () => {
            // stake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, SECONDS_IN_WEEK);

            // call unstake (not unstakeEscrow)
            let tx = stakingRewards.connect(addr1).exit();
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Cannot Unstake 0"
            );
        });

        it("stake escrow, and then call exit()", async () => {
            // stake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, SECONDS_IN_WEEK);

            // call unstake (not unstakeEscrow)
            let tx = stakingRewards.connect(addr1).exit();
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Cannot Unstake 0"
            );
        });

        it("stake, stake escrow, and then call exit()", async () => {
            let nonEscrowStakedBal = SECONDS_IN_WEEK / 2;

            // fund addr1
            await kwenta
                .connect(TREASURY_DAO)
                .transfer(addr1.address, nonEscrowStakedBal);

            // approve StakingRewards
            await kwenta
                .connect(addr1)
                .approve(stakingRewards.address, nonEscrowStakedBal);

            // stake
            await stakingRewards.connect(addr1).stake(nonEscrowStakedBal);

            // stake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, SECONDS_IN_WEEK);

            await stakingRewards.connect(addr1).exit();

            expect(await kwenta.balanceOf(addr1.address)).to.equal(
                nonEscrowStakedBal
            );
        });
    });

    describe("earned()", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
            await fundAndApproveAccount(addr1, SECONDS_IN_WEEK);
        });

        it("should be 0 when not staking", async () => {
            expect(await stakingRewards.earned(addr1.address)).to.be.equal(0);
        });

        it("should be > 0 when staking", async () => {
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
            await fundAndApproveAccount(addr1, SECONDS_IN_WEEK);
        });

        /**
         * @dev notice difference in this functionality compared to Synthetix's version
         */
        it("should increase kwenta balance in escrow", async () => {
            const preEscrowBalance = await kwenta.balanceOf(
                rewardEscrow.address
            );

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
            await fundAndApproveAccount(addr1, SECONDS_IN_WEEK);

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
            await fundAndApproveAccount(addr1, TEST_VALUE);

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
            await fundAndApproveAccount(addr1, TEST_VALUE);

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
            await fundAndApproveAccount(addr1, TEST_VALUE);

            // stake
            await stakingRewards.connect(addr1).stake(TEST_VALUE);

            const initialTokenBal = await kwenta.balanceOf(addr1.address);
            const initialStakeBal = await stakingRewards.balanceOf(
                addr1.address
            );

            await stakingRewards.connect(addr1).unstake(TEST_VALUE);

            const postTokenBal = await kwenta.balanceOf(addr1.address);
            const postStakeBal = await stakingRewards.balanceOf(addr1.address);

            expect(postStakeBal.add(TEST_VALUE)).to.equal(initialStakeBal);
            expect(initialTokenBal.add(TEST_VALUE)).to.equal(postTokenBal);
        });

        it("cannot unstake 0", async () => {
            let tx = stakingRewards.connect(addr1).unstake(0);
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Cannot Unstake 0"
            );
        });
    });

    describe("unstakEscrow()", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
            await fundAndApproveRewardEscrow(SECONDS_IN_WEEK);
        });

        it("cannot unstake if nothing staked", async () => {
            let tx = stakingRewards.connect(rewardEscrow.address).unstakeEscrow(TEST_VALUE);
            await expect(tx).to.be.reverted;
        });

        it("should not change token balance(s) for lp account nor contract", async () => {
            // stake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, SECONDS_IN_WEEK);

            const preAddr1Bal = await kwenta.balanceOf(addr1.address);
            const preSRBalance = await kwenta.balanceOf(stakingRewards.address);

            // unstake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .unstakeEscrow(addr1.address, SECONDS_IN_WEEK);

            const postAddr1Bal = await kwenta.balanceOf(addr1.address);
            const postSRBalance = await kwenta.balanceOf(
                stakingRewards.address
            );

            expect(preAddr1Bal).to.equal(postAddr1Bal);
            expect(preSRBalance).to.equal(postSRBalance);
        });

        it("should change totalSupply", async () => {
            // stake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, SECONDS_IN_WEEK);

            const preBal = await stakingRewards.totalSupply();

            // unstake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .unstakeEscrow(addr1.address, SECONDS_IN_WEEK);

            const postBal = await stakingRewards.totalSupply();

            expect(preBal).to.be.above(postBal);
        });

        it("should change balances[] mapping", async () => {
            // stake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, SECONDS_IN_WEEK);

            const preBal = await stakingRewards.balanceOf(addr1.address);

            // unstake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .unstakeEscrow(addr1.address, SECONDS_IN_WEEK);

            const postBal = await stakingRewards.balanceOf(addr1.address);

            expect(preBal).to.be.above(postBal);
        });

        it("should change escrowedBalances[] mapping", async () => {
            // stake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, SECONDS_IN_WEEK);

            const preBal = await stakingRewards.escrowedBalanceOf(
                addr1.address
            );

            // unstake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .unstakeEscrow(addr1.address, SECONDS_IN_WEEK);

            const postBal = await stakingRewards.escrowedBalanceOf(
                addr1.address
            );

            expect(preBal).to.be.above(postBal);
        });

        it("cannot unstake more than escrow staked", async () => {
            // stake escrow
            await stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .stakeEscrow(addr1.address, SECONDS_IN_WEEK);

            // unstake escrow
            let tx = stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .unstakeEscrow(addr1.address, SECONDS_IN_THIRTY_DAYS);

            await expect(tx).to.be.revertedWith(
                "StakingRewards: Invalid Amount"
            );
        });

        it("cannot unstake 0", async () => {
            let tx = stakingRewards
                .connect(await impersonate(rewardEscrow.address))
                .unstakeEscrow(addr1.address, 0);
            await expect(tx).to.be.revertedWith(
                "StakingRewards: Cannot Unstake 0"
            );
        });
    });

    describe("exit()", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
            await fundAndApproveAccount(addr1, TEST_VALUE);
        });

        it("should retrieve all earned and increase rewards bal", async () => {
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

    describe("Known Edge Case(s)", () => {
        beforeEach("Setup", async () => {
            await setupStakingRewards();
        });

        /**
         * Minor issue discovered by 0xMacro
         *
         * Fix: Deployer can stake
         * Fix: Accept edge case and ensure future cycles distribute "unused" tokens
         */
        it.skip("Inefficient Reward Distribution", async () => {
            await stakingRewards
                .connect(owner)
                .setRewardsDuration(SECONDS_IN_THIRTY_DAYS);
            stakingRewards
                .connect(await impersonate(supplySchedule.address))
                .notifyRewardAmount(SECONDS_IN_THIRTY_DAYS);

            // delay
            await fastForward(3600);

            await fundAndApproveAccount(addr1, TEST_VALUE);

            // stake
            await stakingRewards.connect(addr1).stake(TEST_VALUE);

            // reward distribution period is passed
            await fastForward(SECONDS_IN_THIRTY_DAYS * 2);

            // claim rewards (notice rewards go to escrow, not user!)
            expect(await kwenta.balanceOf(rewardEscrow.address)).to.equal(0);
            await stakingRewards.connect(addr1).getReward();
            expect(await kwenta.balanceOf(rewardEscrow.address)).to.equal(
                SECONDS_IN_THIRTY_DAYS
            );

            // above balance comes as 2590000
            // so, as per current implementation, only 2590000 tokens can be distributed from the intended 2592000.
            // this difference between what the project intended to do and the actual will increase in direct proportion to delay.
            // this is not an exploitable scenario, it's just project's loss.
            // as of now, project will have to start a new cycle to distribute those unused tokens.
            // hence, consider defining periodFinish in the first stake done after notifyRewardAmount
            // - 0xMacro
        });
    });
});
