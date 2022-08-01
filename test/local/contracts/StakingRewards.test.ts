import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "@ethersproject/contracts";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { wei } from "@synthetixio/wei";
import { loadFixture } from "ethereum-waffle";
import { deployKwenta } from "../../utils/kwenta";
import { impersonate, fastForward } from "../../utils/helpers";
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

describe("StakingRewards", () => {
    // We define a fixture to reuse the same setup in every test. We use
    // loadFixture to run this setup once, snapshot that state, and reset Hardhat
    // Network to that snapshopt in every test.
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
            .transfer(stakingRewards.address, TEST_VALUE);
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
            await loadFixture(setupStakingRewards);
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
            await loadFixture(setupStakingRewards);
        });

        it("should revert calling stake() when paused", async () => {
            // pause
            await stakingRewards.connect(owner).pauseStakingRewards();

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
            let isPaused = await stakingRewards.paused();
            expect(isPaused).to.equal(true);

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
            await loadFixture(setupStakingRewards);

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
});
