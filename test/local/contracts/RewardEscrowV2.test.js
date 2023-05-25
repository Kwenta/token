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

const send = (payload) => {
    if (!payload.jsonrpc) payload.jsonrpc = "2.0";
    if (!payload.id) payload.id = new Date().getTime();

    return new Promise((resolve, reject) => {
        web3.currentProvider.send(payload, (error, result) => {
            if (error) return reject(error);

            return resolve(result);
        });
    });
};

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

const assertEventEqual = (
    actualEventOrTransaction,
    expectedEvent,
    expectedArgs
) => {
    // If they pass in a whole transaction we need to extract the first log, otherwise we already have what we need
    const event = Array.isArray(actualEventOrTransaction.logs)
        ? actualEventOrTransaction.logs[0]
        : actualEventOrTransaction;

    if (!event) {
        assert.fail(new Error("No event was generated from this transaction"));
    }

    // Assert the names are the same.
    assert.strictEqual(event.event, expectedEvent);

    assertDeepEqual(event.args, expectedArgs);
    // Note: this means that if you don't assert args they'll pass regardless.
    // Ensure you pass in all the args you need to assert on.
};

const assertDeepEqual = (actual, expected, context) => {
    // Check if it's a value type we can assert on straight away.
    if (BN.isBN(actual) || BN.isBN(expected)) {
        assertBNEqual(actual, expected, context);
    } else if (
        typeof expected === "string" ||
        typeof actual === "string" ||
        typeof expected === "number" ||
        typeof actual === "number" ||
        typeof expected === "boolean" ||
        typeof actual === "boolean"
    ) {
        assert.strictEqual(actual, expected, context);
    }
    // Otherwise dig through the deeper object and recurse
    else if (Array.isArray(expected)) {
        for (let i = 0; i < expected.length; i++) {
            assertDeepEqual(actual[i], expected[i], `(array index: ${i}) `);
        }
    } else {
        for (const key of Object.keys(expected)) {
            assertDeepEqual(actual[key], expected[key], `(key: ${key}) `);
        }
    }
};

const mineBlock = () => send({ method: "evm_mine" });

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
const DEFAULT_EARLY_VESTING_FEE = new BN(90);
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const toUnit = (amount) => toBN(toWei(amount.toString(), "ether"));

const currentTime = async () => {
    const { timestamp } = await web3.eth.getBlock("latest");
    return timestamp;
};
const fastForward = async (seconds) => {
    // It's handy to be able to be able to pass big numbers in as we can just
    // query them from the contract, then send them back. If not changed to
    // a number, this causes much larger fast forwards than expected without error.
    if (BN.isBN(seconds)) seconds = seconds.toNumber();

    // And same with strings.
    if (typeof seconds === "string") seconds = parseFloat(seconds);

    let params = {
        method: "evm_increaseTime",
        params: [seconds],
    };

    if (hardhat.ovm) {
        params = {
            method: "evm_setNextBlockTimestamp",
            params: [(await currentTime()) + seconds],
        };
    }

    await send(params);

    await mineBlock();
};
const assertBNEqual = (actualBN, expectedBN, context) => {
    assert.strictEqual(actualBN.toString(), expectedBN.toString(), context);
};

const assertBNClose = (actualBN, expectedBN, varianceParam = "10") => {
    const actual = BN.isBN(actualBN) ? actualBN : new BN(actualBN);
    const expected = BN.isBN(expectedBN) ? expectedBN : new BN(expectedBN);
    const variance = BN.isBN(varianceParam)
        ? varianceParam
        : new BN(varianceParam);
    const actualDelta = expected.sub(actual).abs();

    assert.ok(
        actual.gte(expected.sub(variance)),
        `Number is too small to be close (Delta between actual and expected is ${actualDelta.toString()}, but variance was only ${variance.toString()}`
    );
    assert.ok(
        actual.lte(expected.add(variance)),
        `Number is too large to be close (Delta between actual and expected is ${actualDelta.toString()}, but variance was only ${variance.toString()})`
    );
};

const assertBNGreaterThan = (aBN, bBN) => {
    assert.ok(
        aBN.gt(bBN),
        `${aBN.toString()} is not greater than ${bBN.toString()}`
    );
};

assert.revert = assertRevert;
assert.bnEqual = assertBNEqual;
assert.eventEqual = assertEventEqual;
assert.bnClose = assertBNClose;
assert.bnGreaterThan = assertBNGreaterThan;

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
    const WEEK = 604800;
    const YEAR = 31556926;
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
            rewardEscrowV2.setStakingRewardsV2(ZERO_ADDRESS, {
                from: owner,
            }),
            "ZeroAddress"
        );

        await rewardEscrowV2.setStakingRewardsV2(stakingRewardsV2.address, {
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
        await rewardEscrowV2.setStakingRewardsV2(stakingRewardsV2.address, {
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
                await rewardEscrowV2.stakingRewardsV2();
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
                rewardEscrowV2.setStakingRewardsV2(stakingRewardsV2.address, {
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
