const { toBN, toWei } = require("web3-utils");
const hardhat = require("hardhat");
const { ethers, upgrades } = require("hardhat");
const { smock } = require("@defi-wonderland/smock");
const { wei } = require("@synthetixio/wei");
const BN = require("bn.js");
const { assert, expect } = require("chai");

require("chai")
    .use(require("chai-as-promised"))
    .use(require("chai-bn-equal"))
    .use(smock.matchers)
    .should();

const assertRevert = async (blockOrPromise, reason) => {
    let errorCaught = false;
    try {
        const result =
            typeof blockOrPromise === "function"
                ? blockOrPromise()
                : blockOrPromise;
        await result;
    } catch (error) {
        assert.include(error.message, "revert");
        if (reason) {
            assert.include(error.message, reason);
        }
        errorCaught = true;
    }

    assert.strictEqual(
        errorCaught,
        true,
        "Operation did not revert as expected"
    );
};

const StakingRewards = artifacts.require(
    "contracts/StakingRewards.sol:StakingRewards"
);
const StakingRewardsV2 = artifacts.require(
    "contracts/StakingRewardsV2.sol:StakingRewardsV2"
);
const TokenContract = artifacts.require("Kwenta");
const RewardEscrowV2 = artifacts.require("RewardEscrowV2");

const NAME = "Kwenta";
const SYMBOL = "KWENTA";
const INITIAL_SUPPLY = hre.ethers.utils.parseUnits("313373");
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const toUnit = (amount) => toBN(toWei(amount.toString(), "ether"));

assert.revert = assertRevert;

const deployRewardEscrowV2 = async (owner, kwenta) => {
    const RewardEscrowV2Factory = await ethers.getContractFactory(
        "RewardEscrowV2"
    );
    const rewardEscrowV2 = await upgrades.deployProxy(
        RewardEscrowV2Factory,
        [owner, kwenta],
        { kind: "uups" }
    );
    await rewardEscrowV2.deployed();
    // convert from hardhat to truffle contract
    return await RewardEscrowV2.at(rewardEscrowV2.address);
};

const deployStakingRewardsV2 = async (
    token,
    rewardEscrow,
    supplySchedule,
    stakingRewardsV1,
    owner
) => {
    const StakingRewardsV2Factory = await ethers.getContractFactory(
        "StakingRewardsV2"
    );
    const stakingRewardsV2 = await upgrades.deployProxy(
        StakingRewardsV2Factory,
        [token, rewardEscrow, supplySchedule, stakingRewardsV1, owner],
        { kind: "uups" }
    );
    await stakingRewardsV2.deployed();
    // convert from hardhat to truffle contract
    return await StakingRewardsV2.at(stakingRewardsV2.address);
};

contract("RewardEscrowV2 KWENTA", ([owner, staker1, staker2, treasuryDAO]) => {
    console.log("Start tests");
    let stakingRewards;
    let stakingRewardsV2;
    let stakingToken;
    let rewardEscrowV2;
    let kwentaSmock;
    let supplySchedule;

    before(async () => {
        kwentaSmock = await smock.fake("Kwenta");
        supplySchedule = await smock.fake("SupplySchedule");

        stakingToken = await TokenContract.new(
            NAME,
            SYMBOL,
            INITIAL_SUPPLY,
            owner,
            treasuryDAO
        );

        rewardEscrowV2 = await deployRewardEscrowV2(owner, kwentaSmock.address);

        stakingRewards = await StakingRewards.new(
            kwentaSmock.address,
            rewardEscrowV2.address,
            supplySchedule.address
        );

        stakingRewardsV2 = await deployStakingRewardsV2(
            kwentaSmock.address,
            rewardEscrowV2.address,
            supplySchedule.address,
            stakingRewards.address,
            owner
        );

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [stakingRewardsV2.address],
        });

        SRsigner = await ethers.getSigner(stakingRewardsV2.address);

        await assert.revert(
            rewardEscrowV2.setStakingRewards(ZERO_ADDRESS, {
                from: owner,
            }),
            "ZeroAddress"
        );

        await rewardEscrowV2.setStakingRewards(stakingRewardsV2.address, {
            from: owner,
        });

        await stakingToken.transfer(staker1, toUnit(10000), {
            from: treasuryDAO,
        });
        await stakingToken.transfer(staker2, toUnit(10000), {
            from: treasuryDAO,
        });
        await stakingToken.transfer(owner, toUnit(31000), {
            from: treasuryDAO,
        });

        await network.provider.send("hardhat_setBalance", [
            stakingRewardsV2.address,
            "0x10000000000000000000000000000000",
        ]);
    });

    beforeEach(async () => {
        // Reset RewardsEscrow
        rewardEscrowV2 = await deployRewardEscrowV2(owner, kwentaSmock.address);
        await rewardEscrowV2.setStakingRewards(stakingRewardsV2.address, {
            from: owner,
        });
        await rewardEscrowV2.setTreasuryDAO(treasuryDAO);
    });

    describe("Deploys correctly", async () => {
        it("Should have a KWENTA token", async () => {
            const kwentaAddress = await rewardEscrowV2.getKwentaAddress();
            assert.equal(
                kwentaAddress,
                kwentaSmock.address,
                "Wrong staking token address"
            );
        });

        it("Should set owner", async () => {
            const ownerAddress = await rewardEscrowV2.owner();
            assert.equal(ownerAddress, owner, "Wrong owner address");
        });

        it("Should have set StakingRewards correctly", async () => {
            const stakingRewardsV2Address =
                await rewardEscrowV2.stakingRewards();
            assert.equal(
                stakingRewardsV2Address,
                stakingRewardsV2.address,
                "Wrong stakingRewards address"
            );
        });

        it("Should have set Treasury set correctly", async () => {
            const treasuryDAOAddress = await rewardEscrowV2.treasuryDAO();
            assert.equal(
                treasuryDAOAddress,
                treasuryDAO,
                "Wrong treasury address"
            );
        });

        it("Should not allow the Treasury to be set to the zero address", async () => {
            await assert.revert(
                rewardEscrowV2.setTreasuryDAO(ZERO_ADDRESS, {
                    from: owner,
                }),
                "ZeroAddress"
            );
        });

        it("Should NOT allow owner to set StakingRewards again", async () => {
            await assert.revert(
                rewardEscrowV2.setStakingRewards(stakingRewardsV2.address, {
                    from: owner,
                }),
                "StakingRewardsAlreadySet"
            );
        });

        it("should set nextEntryId to 1", async () => {
            const nextEntryId = await rewardEscrowV2.nextEntryId();
            assert.equal(nextEntryId, 1);
        });
    });
});
