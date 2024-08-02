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
const RewardEscrowV1 = artifacts.require("RewardEscrow");
const RewardEscrowV2 = artifacts.require("RewardEscrowV2");
const EscrowMigrator = artifacts.require("EscrowMigrator");
const StakingRewardsNotifier = artifacts.require("StakingRewardsNotifier");

const NAME = "Kwenta";
const SYMBOL = "KWENTA";
const INITIAL_SUPPLY = hre.ethers.utils.parseUnits("313373");
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const YEAR = 31556926;
const USDC_ADDRESS = "0x0b2c639c533813f4aa9d7837caf62653d097ff85";

const toUnit = (amount) => toBN(toWei(amount.toString(), "ether"));

assert.revert = assertRevert;

const deployRewardEscrowV2 = async (owner, kwenta, rewardsNotifier) => {
    const RewardEscrowV2Factory = await ethers.getContractFactory(
        "RewardEscrowV2"
    );
    const rewardEscrowV2 = await upgrades.deployProxy(
        RewardEscrowV2Factory,
        [owner],
        {
            kind: "uups",
            constructorArgs: [kwenta, rewardsNotifier],
        }
    );
    await rewardEscrowV2.deployed();
    // convert from hardhat to truffle contract
    return await RewardEscrowV2.at(rewardEscrowV2.address);
};

const deployStakingRewardsV2 = async (
    token,
    usdc,
    rewardEscrow,
    supplySchedule,
    owner
) => {
    const StakingRewardsV2Factory = await ethers.getContractFactory(
        "StakingRewardsV2"
    );
    const stakingRewardsV2 = await upgrades.deployProxy(
        StakingRewardsV2Factory,
        [owner],
        {
            kind: "uups",
            constructorArgs: [token, usdc, rewardEscrow, supplySchedule],
        }
    );
    await stakingRewardsV2.deployed();
    // convert from hardhat to truffle contract
    return await StakingRewardsV2.at(stakingRewardsV2.address);
};

const deployEscrowMigrator = async (
    token,
    rewardEscrowV1,
    rewardEscrowV2,
    stakingRewardsV2,
    owner,
    treasuryDAO
) => {
    const EscrowMigratorFactory = await ethers.getContractFactory(
        "EscrowMigrator"
    );

    const escrowMigrator = await upgrades.deployProxy(
        EscrowMigratorFactory,
        [owner, treasuryDAO],
        {
            kind: "uups",
            constructorArgs: [
                token,
                rewardEscrowV1,
                rewardEscrowV2,
                stakingRewardsV2,
            ],
        }
    );
    await escrowMigrator.deployed();
    // convert from hardhat to truffle contract
    return await EscrowMigrator.at(escrowMigrator.address);
};

const deployRewardsNotifier = async (owner, token, usdc, supplySchedule) => {
    const StakingRewardsNotifierFactory = await ethers.getContractFactory(
        "StakingRewardsNotifier"
    );

    const rewardsNotifier = await StakingRewardsNotifierFactory.deploy(
        owner,
        token,
        usdc,
        supplySchedule
    );
    await rewardsNotifier.deployed();
    // convert from hardhat to truffle contract
    return await StakingRewardsNotifier.at(rewardsNotifier.address);
};

contract("RewardEscrowV2 KWENTA", ([owner, staker1, staker2, treasuryDAO]) => {
    console.log("Start tests");
    let stakingRewards;
    let stakingRewardsV2;
    let stakingToken;
    let rewardEscrowV1;
    let rewardEscrowV2;
    let escrowMigrator;
    let supplySchedule;
    let rewardsNotifier;

    before(async () => {
        supplySchedule = await smock.fake("SupplySchedule");

        stakingToken = await TokenContract.new(
            NAME,
            SYMBOL,
            INITIAL_SUPPLY,
            owner,
            treasuryDAO
        );

        rewardEscrowV1 = await RewardEscrowV1.new(owner, stakingToken.address);

        rewardsNotifier = await deployRewardsNotifier(
            owner,
            stakingToken.address,
            USDC_ADDRESS,
            supplySchedule.address
        );

        rewardEscrowV2 = await deployRewardEscrowV2(
            owner,
            stakingToken.address,
            rewardsNotifier.address
        );

        stakingRewards = await StakingRewards.new(
            stakingToken.address,
            rewardEscrowV2.address,
            supplySchedule.address
        );

        await rewardEscrowV1.setStakingRewards(stakingRewards.address, {
            from: owner,
        });
        await rewardEscrowV1.setTreasuryDAO(treasuryDAO, {
            from: owner,
        });

        stakingRewardsV2 = await deployStakingRewardsV2(
            stakingToken.address,
            USDC_ADDRESS,
            rewardEscrowV2.address,
            rewardsNotifier.address,
            owner
        );

        escrowMigrator = await deployEscrowMigrator(
            stakingToken.address,
            rewardEscrowV1.address,
            rewardEscrowV2.address,
            stakingRewardsV2.address,
            owner,
            treasuryDAO
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

        await rewardEscrowV2.setEscrowMigrator(escrowMigrator.address, {
            from: owner,
        });

        await rewardsNotifier.setStakingRewardsV2(stakingRewardsV2.address, {
            from: owner,
        });

        await rewardsNotifier.renounceOwnership({
            from: owner,
        });

        await rewardEscrowV1.setTreasuryDAO(escrowMigrator.address, {
            from: owner,
        });

        await rewardEscrowV2.setTreasuryDAO(treasuryDAO, {
            from: owner,
        });

        await escrowMigrator.unpauseEscrowMigrator({
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

    describe("Deploys correctly", async () => {
        it("Should have a KWENTA token", async () => {
            const kwentaAddress = await rewardEscrowV2.getKwentaAddress();
            assert.equal(
                kwentaAddress,
                stakingToken.address,
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

    describe("Can Migrate Escrow", async () => {
        it("Can migrate entries from v1 to v2", async () => {
            let escrowAmount = toUnit("1");
            let duration = YEAR;

            await stakingToken.approve(
                rewardEscrowV1.address,
                toUnit("100000"),
                {
                    from: treasuryDAO,
                }
            );

            let numEntries = 1_30;

            for (let i = 0; i < numEntries; i++) {
                await rewardEscrowV1.createEscrowEntry(
                    staker1,
                    escrowAmount,
                    duration,
                    {
                        from: treasuryDAO,
                    }
                );
            }

            let entries = await rewardEscrowV1.getAccountVestingEntryIDs(
                staker1,
                0,
                numEntries
            );

            await escrowMigrator.registerEntries(entries, {
                from: staker1,
            });

            await rewardEscrowV1.vest(entries, {
                from: staker1,
            });

            await stakingToken.approve(
                escrowMigrator.address,
                toUnit("100000"),
                {
                    from: staker1,
                }
            );

            await escrowMigrator.migrateEntries(staker1, entries, {
                from: staker1,
            });

            const registered = await escrowMigrator.totalEscrowRegistered(
                staker1
            );
            const migrated = await escrowMigrator.totalEscrowMigrated(staker1);
            const v2Entries = await rewardEscrowV2.balanceOf(staker1);

            assert.equal(numEntries, v2Entries.toNumber());
            assert.equal(
                escrowAmount.mul(new BN(numEntries)).toString(),
                registered.toString()
            );
            assert.equal(
                escrowAmount.mul(new BN(numEntries)).toString(),
                migrated.toString()
            );
        });
    });
});
