import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Contract } from "@ethersproject/contracts";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { wei } from "@synthetixio/wei";
import { fastForward, impersonate } from "../utils/helpers";
import dotenv from "dotenv";

dotenv.config();

// constants
const NAME = "Kwenta";
const SYMBOL = "KWENTA";
const INITIAL_SUPPLY = ethers.utils.parseUnits("313373");
const SECONDS_IN_WEEK = 6048000;

// test values
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

// library contracts
let fixidityLib: Contract;
let logarithmLib: Contract;
let exponentLib: Contract;

// util contracts
let safeDecimalMath: Contract;

// StakingRewards: fund with KWENTA and set the rewards
const fundAndSetStakingRewards = async (value: number) => {
    // send/fund StakingRewards
    kwenta.connect(TREASURY_DAO).transfer(stakingRewards.address, value);

    // set duration/epoch/period
    await stakingRewards.setRewardsDuration(value);

    // set rewards per duration/epoch/period
    // (i.e. 1 KWENTA per second since value is used for both duration and reward amount)
    await stakingRewards
        .connect(await impersonate(supplySchedule.address))
        .notifyRewardAmount(value);
};

// Fork Optimism Network for following tests
const forkOptimismNetwork = async () => {
    await network.provider.request({
        method: "hardhat_reset",
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

const loadSetup = () => {
    before("Deploy contracts", async () => {
        // fork optimism mainnet
        forkOptimismNetwork();

        [owner, addr1, addr2, TREASURY_DAO] = await ethers.getSigners();

        // deploy FixidityLib
        const FixidityLib = await ethers.getContractFactory("FixidityLib");
        fixidityLib = await FixidityLib.deploy();
        await fixidityLib.deployed();

        // deploy LogarithmLib
        const LogarithmLib = await ethers.getContractFactory("LogarithmLib", {
            libraries: {
                FixidityLib: fixidityLib.address,
            },
        });
        logarithmLib = await LogarithmLib.deploy();
        await logarithmLib.deployed();

        // deploy ExponentLib
        const ExponentLib = await ethers.getContractFactory("ExponentLib", {
            libraries: {
                FixidityLib: fixidityLib.address,
                LogarithmLib: logarithmLib.address,
            },
        });
        exponentLib = await ExponentLib.deploy();
        await exponentLib.deployed();

        // deploy SafeDecimalMath
        const SafeDecimalMath = await ethers.getContractFactory(
            "SafeDecimalMath"
        );
        safeDecimalMath = await SafeDecimalMath.deploy();
        await safeDecimalMath.deployed();

        // deploy SupplySchedule
        const SupplySchedule = await ethers.getContractFactory(
            "SupplySchedule",
            {
                libraries: {
                    SafeDecimalMath: safeDecimalMath.address,
                },
            }
        );
        supplySchedule = await SupplySchedule.deploy(
            owner.address,
            TREASURY_DAO.address
        );
        await supplySchedule.deployed();

        // deploy Kwenta
        const Kwenta = await ethers.getContractFactory("Kwenta");
        kwenta = await Kwenta.deploy(
            NAME,
            SYMBOL,
            INITIAL_SUPPLY,
            owner.address,
            TREASURY_DAO.address
        );
        await kwenta.deployed();
        await kwenta.setSupplySchedule(supplySchedule.address);
        await supplySchedule.setKwenta(kwenta.address);

        // deploy RewardEscrow
        const RewardEscrow = await ethers.getContractFactory("RewardEscrow");
        rewardEscrow = await RewardEscrow.deploy(owner.address, kwenta.address);
        await rewardEscrow.deployed();

        // deploy StakingRewards
        const StakingRewards = await ethers.getContractFactory(
            "StakingRewards"
        );
        stakingRewards = await StakingRewards.deploy(
            kwenta.address,
            kwenta.address,
            rewardEscrow.address,
            supplySchedule.address
        );
        await stakingRewards.deployed();

        // set StakingRewards address in SupplySchedule
        await supplySchedule.setStakingRewards(stakingRewards.address);

        // set StakingRewards address in RewardEscrow
        await rewardEscrow.setStakingRewards(stakingRewards.address);
    });
};

describe("Stake (fork)", () => {
    describe("Staking", async () => {
        loadSetup();
        it("Stake and claim rewards", async () => {
            // set the rewards for the next duration/epoch/period
            await fundAndSetStakingRewards(SECONDS_IN_WEEK);

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

        it("Wait then claim rewards", async () => {
            // wait
            await fastForward(SECONDS_IN_WEEK * 2);

            // addr1 does not have any escrow entries
            expect(
                await rewardEscrow.numVestingEntries(addr1.address)
            ).to.equal(0);

            // claim rewards (expect > 0 rewards appended in escrow)
            await stakingRewards.connect(addr1).getReward();
            expect(await rewardEscrow.balanceOf(addr1.address)).to.be.above(0);

            // @TODO: should be SECONDS_IN_WEEK (i.e. 604800 but turns out to be 604000... 800 stuck in StakingRewards... why?)
            // expect(await rewardEscrow.balanceOf(addr1.address)).to.equal(SECONDS_IN_WEEK);

            // check that addr1 does have an escrow entry
            expect(
                await rewardEscrow.numVestingEntries(addr1.address)
            ).to.equal(1);

            // not tested here
            await stakingRewards.connect(addr1).exit();
        });

        it("Stake, Wait, and then Exit", async () => {
            // initial balance should be 0
            expect(await kwenta.balanceOf(addr2.address)).to.equal(0);

            // transfer KWENTA to addr2
            await expect(() =>
                kwenta.connect(TREASURY_DAO).transfer(addr2.address, TEST_VALUE)
            ).to.changeTokenBalance(kwenta, addr2, TEST_VALUE);

            // set the rewards for the next duration/epoch/period
            await fundAndSetStakingRewards(SECONDS_IN_WEEK);

            // increase KWENTA allowance for stakingRewards and stake
            await kwenta
                .connect(addr2)
                .approve(stakingRewards.address, TEST_VALUE);
            await stakingRewards.connect(addr2).stake(TEST_VALUE);

            // wait
            await fastForward(SECONDS_IN_WEEK * 2);

            // expect tokens back and rewards
            await stakingRewards.connect(addr2).exit();
            expect(await rewardEscrow.balanceOf(addr2.address)).to.be.above(0);
            expect(await kwenta.balanceOf(addr2.address)).to.equal(TEST_VALUE);
        });
    });

    describe("Escrow staking", async () => {
        loadSetup();
        before("Create new escrow entry", async () => {
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
            await kwenta
                .connect(addr1)
                .approve(rewardEscrow.address, TEST_VALUE);
            await rewardEscrow
                .connect(addr1)
                .createEscrowEntry(addr1.address, TEST_VALUE, SECONDS_IN_WEEK);
            await kwenta
                .connect(addr2)
                .approve(rewardEscrow.address, TEST_VALUE);
            await rewardEscrow
                .connect(addr2)
                .createEscrowEntry(addr2.address, TEST_VALUE, SECONDS_IN_WEEK);

            // check escrow entries
            expect(
                await rewardEscrow.numVestingEntries(addr1.address)
            ).to.equal(1);
            expect(
                await rewardEscrow.numVestingEntries(addr2.address)
            ).to.equal(1);
        });

        it("Stake escrowed kwenta", async () => {
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

        it("Wait, claim rewards", async () => {
            // set the rewards for the next duration/epoch/period
            await fundAndSetStakingRewards(SECONDS_IN_WEEK);

            // establish current escrow balance(s)
            const prevAddr1EscrowBalance = await rewardEscrow.balanceOf(
                addr1.address
            );
            const prevAddr2EscrowBalance = await rewardEscrow.balanceOf(
                addr2.address
            );

            // wait
            fastForward(SECONDS_IN_WEEK * 2);

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

        it("Unstake escrowed kwenta", async () => {
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
});
