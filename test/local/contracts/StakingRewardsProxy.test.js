const {toBN, toWei} = require('web3-utils');
const hardhat = require('hardhat');

const send = (payload) => {
    if (!payload.jsonrpc) payload.jsonrpc = '2.0';
    if (!payload.id) payload.id = new Date().getTime();

    return new Promise((resolve, reject) => {
        web3.currentProvider.send(payload, (error, result) => {
            if (error) return reject(error);

            return resolve(result);
        });
    });
};
const mineBlock = () => send({method: 'evm_mine'});

const NAME = 'Kwenta';
const SYMBOL = 'KWENTA';
const INITIAL_SUPPLY = hre.ethers.utils.parseUnits('313373');
const DAY = 86400;
const WEEK = DAY * 7;
const ZERO_BN = toBN(0);

const toUnit = (amount) => toBN(toWei(amount.toString(), 'ether')).toString();

const assertBNClose = (actualBN, expectedBN, varianceParam = '10') => {
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

const currentTime = async () => {
    const {timestamp} = await web3.eth.getBlock('latest');
    return timestamp;
};
const fastForward = async (seconds) => {
    // It's handy to be able to be able to pass big numbers in as we can just
    // query them from the contract, then send them back. If not changed to
    // a number, this causes much larger fast forwards than expected without error.
    if (BN.isBN(seconds)) seconds = seconds.toNumber();

    // And same with strings.
    if (typeof seconds === 'string') seconds = parseFloat(seconds);

    let params = {
        method: 'evm_increaseTime',
        params: [seconds],
    };

    if (hardhat.ovm) {
        params = {
            method: 'evm_setNextBlockTimestamp',
            params: [(await currentTime()) + seconds],
        };
    }

    await send(params);

    await mineBlock();
};
const assertBNEqual = (actualBN, expectedBN, context) => {
    assert.strictEqual(actualBN.toString(), expectedBN.toString(), context);
};
const assertBNNotEqual = (actualBN, expectedBN, context) => {
    assert.notStrictEqual(actualBN.toString(), expectedBN.toString(), context);
};
const BN = require('bn.js');

require('chai')
    .use(require('chai-as-promised'))
    .use(require('chai-bn-equal'))
    .should();

let owner;
let owner2;
let staker1;
let staker2;
let treasuryDAO;
let supplySchedule;
let stProxy;
let exchangerProxy;
let rewardsEscrow;

const deployContract = async () => {
    FixidityLib = await hre.ethers.getContractFactory('FixidityLib');
    fixidityLib = await FixidityLib.deploy();

    LogarithmLib = await hre.ethers.getContractFactory('LogarithmLib', {
        libraries: {FixidityLib: fixidityLib.address},
    });
    logarithmLib = await LogarithmLib.deploy();
    ExponentLib = await hre.ethers.getContractFactory('ExponentLib', {
        libraries: {
            FixidityLib: fixidityLib.address,
            LogarithmLib: logarithmLib.address,
        },
    });
    exponentLib = await ExponentLib.deploy();

    StakingRewards = await hre.ethers.getContractFactory('StakingRewards', {
        libraries: {
            FixidityLib: fixidityLib.address,
            ExponentLib: exponentLib.address,
        },
    });
    return StakingRewards;
};

const deployProxy = async () => {
    return await hre.upgrades.deployProxy(
        StakingRewards,
        [
            owner.address,
            kwentaToken.address,
            rewardsEscrow.address,
            supplySchedule.address,
            3,
        ],
        {kind: 'uups', unsafeAllow: ['external-library-linking']}
    );
};

const deployNewRewardsEscrow = async (owner, kwentaToken) => {
    RewardsEscrow = await await hre.ethers.getContractFactory('RewardEscrow');
    rewardsEscrow = await RewardsEscrow.deploy(
        owner.address,
        kwentaToken.address
    );
};

const getCurrentEpoch = async () => {
    let currEpoch = Math.floor((await currentTime()) / WEEK) * WEEK;
    let today = Math.floor((await currentTime()) / DAY) * DAY;
    if (today - currEpoch >= 4 * DAY) {
        currEpoch = currEpoch + WEEK - 3 * DAY;
    } else {
        currEpoch = currEpoch - 3 * DAY;
    }
    return currEpoch;
}

before(async () => {
    [
        owner,
        staker1,
        staker2,
        exchangerProxy,
        rewardsDistribution,
        treasuryDAO,
        supplySchedule,
        owner2,
    ] = await hre.ethers.getSigners();
    KwentaToken = await hre.ethers.getContractFactory('Kwenta');
    kwentaToken = await KwentaToken.deploy(
        NAME,
        SYMBOL,
        INITIAL_SUPPLY,
        owner.address,
        treasuryDAO.address
    );

    await deployNewRewardsEscrow(owner, kwentaToken);

    await kwentaToken
        .connect(treasuryDAO)
        .transfer(staker1.address, toUnit(1000));
    await kwentaToken
        .connect(treasuryDAO)
        .transfer(staker2.address, toUnit(1000));
});

describe('Proxy deployment', async () => {
    it('should deploy the proxy', async () => {
        StakingRewards = await deployContract();
        stProxy = await deployProxy();

        admin_address = await hre.upgrades.erc1967.getAdminAddress(
            stProxy.address
        );
        implementation = await hre.upgrades.erc1967.getImplementationAddress(
            stProxy.address
        );

        owner_address = await stProxy.owner();

        assert.notEqual(implementation, stProxy.address);

        await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
        await stProxy.connect(owner).setRewardEscrow(rewardsEscrow.address);

        await kwentaToken
            .connect(treasuryDAO)
            .transfer(stProxy.address, toUnit(500));
    });
});

describe('StakingRewards deployment', async () => {
    it('deploys with correct addresses', async () => {
        assert.equal(await stProxy.owner(), owner.address);
        assert.equal(await stProxy.stakingToken(), kwentaToken.address);
        assert.equal(await stProxy.owner(), owner.address);
        assert.equal(await stProxy.rewardEscrow(), rewardsEscrow.address);
    });
});

describe('stake()', async () => {
    it('fails with zero amounts', async () => {
        await stProxy.connect(staker1).stake(0).should.be.rejected;
    });
    it('fails when staking below safety limit', async () => {
        const stakingMinimum = await stProxy.STAKING_SAFETY_MINIMUM();
        await kwentaToken
            .connect(staker1)
            .approve(stProxy.address, stakingMinimum.sub(1));
        await stProxy.connect(staker1).stake(stakingMinimum.sub(1)).should.be
            .rejected;
    });
    it('stakes the correct amount', async () => {
        await kwentaToken
            .connect(staker1)
            .approve(stProxy.address, toUnit(100));
        await kwentaToken
            .connect(staker2)
            .approve(stProxy.address, toUnit(100));

        await stProxy.connect(staker1).stake(toUnit(15));

        let bal = await stProxy.stakedBalanceOf(staker1.address);
        assert.equal(bal, toUnit(15), 'Incorrect amount');

        await stProxy.connect(staker2).stake(toUnit(50));
        bal = await stProxy.stakedBalanceOf(staker2.address);
        assert.equal(bal, toUnit(50), 'Incorrect amount');
    });
});

describe('unstake()', async () => {
    it('fails with zero amounts', async () => {
        await stProxy.connect(staker1).unstake(0).should.be.rejected;
    });
    it('fails with amounts too large', async () => {
        await stProxy.connect(staker1).unstake(toUnit(100)).should.be.rejected;
    });
    it('fails when unstaking results in a balance below safety limit', async () => {
        const stakingMinimum = await stProxy.STAKING_SAFETY_MINIMUM();
        const stakedAmount = await stProxy.totalBalanceOf(staker1.address);
        const invalidWithdrawalAmount = stakedAmount.sub(stakingMinimum).add(1);
        await stProxy.connect(staker1).unstake(invalidWithdrawalAmount).should
            .be.rejected;
    });
    it('unstakes the correct amount', async () => {
        await stProxy.connect(staker1).unstake(toUnit(15));
        let bal = await stProxy.stakedBalanceOf(staker1.address);
        assert.equal(bal, 0, 'Incorrect amount');

        await stProxy.connect(staker2).unstake(toUnit(50));
        bal = await stProxy.stakedBalanceOf(staker2.address);
        assert.equal(bal, 0, 'Incorrect amount');
    });
});

describe('feesPaid()', async () => {
    it('initializes updatesTraderScore correctly', async () => {
        let ts1 = await stProxy.feesPaidBy(staker1.address);
        let ts2 = await stProxy.feesPaidBy(staker2.address);
        assert.equal(ts1, 0);
        assert.equal(ts2, 0);
    });
    it('fails when fees update is below safety limit', async () => {
        const feesPaidMinimum = await stProxy.FEES_PAID_SAFETY_MINIMUM();
        await stProxy
            .connect(exchangerProxy)
            .updateTraderScore(staker1.address, feesPaidMinimum.sub(1)).should
            .be.rejected;
    });
    it('updates updatesTraderScore correctly', async () => {
        await stProxy.connect(staker1).stake(toUnit(5));
        await stProxy.connect(staker2).stake(toUnit(5));

        await stProxy
            .connect(exchangerProxy)
            .updateTraderScore(staker1.address, toUnit(5));
        await stProxy
            .connect(exchangerProxy)
            .updateTraderScore(staker2.address, toUnit(4));

        let ts1 = await stProxy.feesPaidBy(staker1.address);
        let expected = toUnit(5);

        assertBNEqual(ts1, expected);

        let ts2 = await stProxy.feesPaidBy(staker2.address);
        expected = toUnit(4);

        assertBNEqual(ts2, expected);
    });
});

describe('lastTimeRewardApplicable()', () => {
    it('should return 0', async () => {
        assert.equal(await stProxy.lastTimeRewardApplicable(), 0);
    });

    describe('when updated', () => {
        it('should equal current timestamp', async () => {
            await stProxy
                .connect(supplySchedule)
                .setRewards(toUnit(10));

            const cur = await currentTime();
            const lastTimeReward = await stProxy.lastTimeRewardApplicable();

            assert.equal(cur.toString(), lastTimeReward.toString());
        });
    });
});

describe('staking before setRewards() edge case', () => {
    it("staking a small amount before setting rewards throws off next value", async () => {
        StakingRewards = await deployContract();
        stProxy = await deployProxy();

        await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
        await stProxy.connect(owner).setRewardEscrow(rewardsEscrow.address);

        await kwentaToken
            .connect(staker1)
            .approve(stProxy.address, 10000);
        await kwentaToken
            .connect(staker2)
            .approve(stProxy.address, toUnit(100));

        await kwentaToken
            .connect(treasuryDAO)
            .transfer(stProxy.address, toUnit(100));

        // Stake staker1
        await stProxy.connect(staker1).stake(10000);
        console.log(`Staking ${ethers.utils.formatEther(10000)} from staker1`)

        // setRewards
        await stProxy.connect(supplySchedule).setRewards(toUnit(100));
        console.log(`setRewards(100e18)`)
        
        // Stake staker 2
        await stProxy.connect(staker2).stake(toUnit(100));
        console.log(`Staking ${100} from staker2`)
        console.log(`Fast forward a week`)
        
        // ff
        await fastForward(WEEK);

        // Check values
        const earned1 = await stProxy.earned(staker1.address)
        const earned2 = await stProxy.earned(staker2.address)

        console.log(`earned (staker 1): ${ethers.utils.formatEther(earned1)}`)
        console.log(`earned (staker 2): ${ethers.utils.formatEther(earned2)}`)
    });
});

describe('rewardPerToken()', () => {
    it('should return 0', async () => {
        StakingRewards = await deployContract();
        stProxy = await deployProxy();

        await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
        await stProxy.connect(owner).setRewardEscrow(rewardsEscrow.address);

        assertBNEqual(await stProxy.rewardPerToken(), 0);
    });

    it('should be > 0', async () => {
        const totalToStake = toUnit(10);

        await kwentaToken
            .connect(treasuryDAO)
            .transfer(stProxy.address, toUnit(10));
        await kwentaToken.connect(staker1).approve(stProxy.address, toUnit(10));
        await stProxy.connect(supplySchedule).setRewards(toUnit(10));

        await stProxy.connect(staker1).stake(totalToStake);
        await fastForward(1);

        const rewardPerToken = await stProxy.rewardPerToken();
        assertBNGreaterThan(rewardPerToken, 0);
    });
});

describe('earned()', () => {
    it('should not be 0 when staking but not trading', async () => {
        // RewardsEscrow only allows for StakingRewards to be set *once*,
        // thus requiring new deployment when StakingRewards needs to change
        // for testing purposes
        await deployNewRewardsEscrow(owner, kwentaToken);

        StakingRewards = await deployContract();
        stProxy = await deployProxy();

        rewardsEscrow.setStakingRewards(stProxy.address);
        await kwentaToken
            .connect(treasuryDAO)
            .transfer(stProxy.address, toUnit(100));
        await kwentaToken
            .connect(staker1)
            .approve(stProxy.address, toUnit(100));
        await kwentaToken
            .connect(staker2)
            .approve(stProxy.address, toUnit(100));

        const totalToStake = toUnit(1);

        await stProxy.connect(staker1).stake(totalToStake);

        const rewardValue = toUnit(5.0);

        await stProxy.connect(supplySchedule).setRewards(rewardValue);

        await fastForward(DAY * 7);

        const earned = await stProxy.earned(staker1.address);

        assertBNClose(earned.toString(), toUnit(4), toUnit(0.001));
    });

    it('should be 0 when trading and not staking', async () => {
        // RewardsEscrow only allows for StakingRewards to be set *once*,
        // thus requiring new deployment when StakingRewards needs to change
        // for testing purposes
        await deployNewRewardsEscrow(owner, kwentaToken);

        StakingRewards = await deployContract();
        stProxy = await deployProxy();

        await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
        await stProxy.connect(owner).setRewardEscrow(rewardsEscrow.address);

        await rewardsEscrow.setStakingRewards(stProxy.address);
        await kwentaToken
            .connect(treasuryDAO)
            .transfer(stProxy.address, toUnit(100));
        await kwentaToken
            .connect(staker1)
            .approve(stProxy.address, toUnit(100));
        await kwentaToken
            .connect(staker2)
            .approve(stProxy.address, toUnit(100));

        await stProxy
            .connect(exchangerProxy)
            .updateTraderScore(staker1.address, toUnit(1));

        const rewardValue = toUnit(5.0);

        await stProxy.connect(supplySchedule).setRewards(rewardValue);

        await fastForward(DAY);

        const earned = await stProxy.earned(staker1.address);

        assertBNEqual(earned, ZERO_BN);
    });

    it('should be 0 when not trading and not staking', async () => {
        // RewardsEscrow only allows for StakingRewards to be set *once*,
        // thus requiring new deployment when StakingRewards needs to change
        // for testing purposes
        await deployNewRewardsEscrow(owner, kwentaToken);

        StakingRewards = await deployContract();
        stProxy = await deployProxy();

        await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
        await stProxy.connect(owner).setRewardEscrow(rewardsEscrow.address);

        await rewardsEscrow.setStakingRewards(stProxy.address);
        await kwentaToken
            .connect(treasuryDAO)
            .transfer(stProxy.address, toUnit(100));
        await kwentaToken
            .connect(staker1)
            .approve(stProxy.address, toUnit(100));
        await kwentaToken
            .connect(staker2)
            .approve(stProxy.address, toUnit(100));

        const rewardValue = toUnit(5.0);

        await stProxy.connect(supplySchedule).setRewards(rewardValue);

        await fastForward(DAY);

        const earned = await stProxy.earned(staker1.address);

        assertBNEqual(earned, ZERO_BN);
    });

    it('should be > 0 when trading and staking', async () => {
        // RewardsEscrow only allows for StakingRewards to be set *once*,
        // thus requiring new deployment when StakingRewards needs to change
        // for testing purposes
        await deployNewRewardsEscrow(owner, kwentaToken);

        StakingRewards = await deployContract();
        stProxy = await deployProxy();

        await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
        await stProxy.connect(owner).setRewardEscrow(rewardsEscrow.address);

        await rewardsEscrow.setStakingRewards(stProxy.address);
        await kwentaToken
            .connect(treasuryDAO)
            .transfer(stProxy.address, toUnit(100));
        await kwentaToken
            .connect(staker1)
            .approve(stProxy.address, toUnit(100));
        await kwentaToken
            .connect(staker2)
            .approve(stProxy.address, toUnit(100));

        const totalToStake = toUnit(1);

        await stProxy.connect(staker1).stake(totalToStake);

        await stProxy
            .connect(exchangerProxy)
            .updateTraderScore(staker1.address, toUnit(1));

        const rewardValue = toUnit(5.0);

        await stProxy.connect(supplySchedule).setRewards(rewardValue);

        await fastForward(DAY);

        const earned = await stProxy.earned(staker1.address);

        assert(earned > ZERO_BN);
    });
});

describe('rewardEpochs()', () => {
    it('Updates the reward Epoch mapping after the week is finished', async () => {
        // RewardsEscrow only allows for StakingRewards to be set *once*,
        // thus requiring new deployment when StakingRewards needs to change
        // for testing purposes
        await deployNewRewardsEscrow(owner, kwentaToken);

        StakingRewards = await deployContract();
        stProxy = await deployProxy();

        await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
        await stProxy.connect(owner).setRewardEscrow(rewardsEscrow.address);

        await rewardsEscrow.setStakingRewards(stProxy.address);
        await kwentaToken
            .connect(treasuryDAO)
            .transfer(stProxy.address, toUnit(100));
        await kwentaToken
            .connect(staker1)
            .approve(stProxy.address, toUnit(100));
        await kwentaToken
            .connect(staker2)
            .approve(stProxy.address, toUnit(100));

        const totalToStake = toUnit(1);
        const rewardValue = toUnit(5.0);
        var currEpoch = Math.floor((await currentTime()) / WEEK) * WEEK;
        var today = Math.floor((await currentTime()) / DAY) * DAY;
        if (today - currEpoch >= 4 * DAY) {
            currEpoch = currEpoch + WEEK - 3 * DAY;
        } else {
            currEpoch = currEpoch - 3 * DAY;
        }
        await stProxy.connect(supplySchedule).setRewards(rewardValue);

        await stProxy.connect(staker1).stake(totalToStake);
        await stProxy
            .connect(exchangerProxy)
            .updateTraderScore(staker1.address, toUnit(1));

        let reward = await stProxy.rewardPerRewardScoreOfEpoch(currEpoch);

        assert.equal(reward, 0);

        await fastForward(DAY * 7);

        await stProxy.connect(staker1).stake(totalToStake);
        reward = await stProxy.rewardPerRewardScoreOfEpoch(currEpoch);
        assertBNGreaterThan(reward, 0);
    });
});

describe('implementation test', () => {
    // @TODO: this test needs to be rewritten -- way too brittle
    it.skip('calculates rewards correctly', async () => {
        // RewardsEscrow only allows for StakingRewards to be set *once*,
        // thus requiring new deployment when StakingRewards needs to change
        // for testing purposes
        await deployNewRewardsEscrow(owner, kwentaToken);

        StakingRewards = await deployContract();
        stProxy = await deployProxy();

        await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
        await stProxy.connect(owner).setRewardEscrow(rewardsEscrow.address);

        await rewardsEscrow.setStakingRewards(stProxy.address);
        await kwentaToken
            .connect(treasuryDAO)
            .transfer(stProxy.address, toUnit(1000));
        await kwentaToken
            .connect(staker1)
            .approve(stProxy.address, toUnit(100));
        await kwentaToken
            .connect(staker2)
            .approve(stProxy.address, toUnit(100));

        const today = Math.floor((await currentTime()) / DAY) * DAY;
        const currEpoch = await getCurrentEpoch();
        let daysTillMonday = currEpoch - today + WEEK;

        await fastForward(daysTillMonday + 1);

        await stProxy.connect(staker1).stake(toUnit(10));
        await stProxy.connect(staker2).stake(toUnit(10));

        await stProxy.connect(supplySchedule).setRewards(toUnit(300));

        await fastForward(1 * DAY);

        await stProxy
            .connect(exchangerProxy)
            .updateTraderScore(staker1.address, toUnit(25));
        await stProxy
            .connect(exchangerProxy)
            .updateTraderScore(staker2.address, toUnit(50));

        await fastForward(3 * DAY);

        await stProxy.connect(staker1).unstake(toUnit(5));

        await fastForward(3 * DAY);

        await stProxy.connect(staker2).unstake(toUnit(10));

        await fastForward(1 * DAY);

        await stProxy
            .connect(exchangerProxy)
            .updateTraderScore(staker2.address, toUnit(70));

        await fastForward(6 * DAY);

        await stProxy.connect(staker2).stake(toUnit(30));
        await stProxy
            .connect(exchangerProxy)
            .updateTraderScore(staker2.address, toUnit(90));

        await fastForward(4 * DAY);

        await stProxy
            .connect(exchangerProxy)
            .updateTraderScore(staker1.address, toUnit(100));

        await fastForward(3 * DAY);

        // Check rewards are accrued into the escrow contract after stakers exit()
        await stProxy.connect(staker1).exit();
        let escrowedSt1 = await kwentaToken.balanceOf(rewardsEscrow.address);
        assertBNClose(
            escrowedSt1.toString(),
            toUnit(122.85734126983),
            toUnit(0.001)
        );

        await stProxy.connect(staker2).exit();
        let escrowedSt2 = await kwentaToken.balanceOf(rewardsEscrow.address);
        assertBNClose(
            escrowedSt2.toString(),
            toUnit(122.85734126983 + 177.14265873015),
            toUnit(0.001)
        );
    });
});

describe('ownership test', () => {
    beforeEach(async () => {
        await deployNewRewardsEscrow(owner, kwentaToken);

        StakingRewards = await deployContract();
        stProxy = await deployProxy();

        await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
        await stProxy.connect(owner).setRewardEscrow(rewardsEscrow.address);

        await rewardsEscrow.setStakingRewards(stProxy.address);
    });

    it('pending address should be 0', async () => {
        assert.equal(
            await stProxy.nominatedOwner(),
            hre.ethers.constants.AddressZero
        );
    });

    it('transfer ownership, pending address should be 0', async () => {
        await stProxy.connect(owner).nominateNewOwner(owner2.address);
        assert.equal(await stProxy.nominatedOwner(), owner2.address);
        await stProxy.connect(owner2).acceptOwnership();
        assert.equal(
            await stProxy.nominatedOwner(),
            hre.ethers.constants.AddressZero
        );
    });
});

describe('recoverERC20()', () => {
    let stakingToken;
    beforeEach(async () => {
        ERC20 = await hre.ethers.getContractFactory('ERC20');
        stakingToken = await ERC20.deploy(NAME, SYMBOL);

        unrelatedToken = await ERC20.deploy(NAME, SYMBOL);

        await deployNewRewardsEscrow(owner, kwentaToken);

        StakingRewards = await deployContract();
        stProxy = await hre.upgrades.deployProxy(
            StakingRewards,
            [
                owner.address,
                stakingToken.address,
                rewardsEscrow.address,
                supplySchedule.address,
                3,
            ],
            {kind: 'uups', unsafeAllow: ['external-library-linking']}
        );

        await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
        await rewardsEscrow.setStakingRewards(stProxy.address);
    });

    it('sweeping the staking token', async () => {
        await stProxy.connect(owner).recoverERC20(stakingToken.address, 1)
            .should.be.rejected;
    });

    it('sweeping unrelated token', async () => {
        await stProxy
            .connect(owner)
            .recoverERC20(unrelatedToken.address, 1)
            .should.be.rejectedWith('ERC20: transfer amount exceeds balance');
    });
});

describe('setRewardEscrow()', () => {
    it("Reverts if the provided RewardEscrow's $kwenta does not match StakingRewards' $stakingToken", async () => {
        // deploy a new kwenta token
        NewKwentaToken = await hre.ethers.getContractFactory('Kwenta');
        newKwentaToken = await KwentaToken.deploy(
            NAME,
            SYMBOL,
            INITIAL_SUPPLY,
            owner.address,
            treasuryDAO.address
        );

        // deploy new RewardEscrow with newKwentaToken
        // @notice StakingRewards.stakingToken address does NOT equal the newRewardsEscrow.kwenta address
        const newRewardsEscrow = await RewardsEscrow.deploy(
            owner.address,
            newKwentaToken.address
        );

        await stProxy
            .connect(owner)
            .setRewardEscrow(newRewardsEscrow.address)
            .should.be.rejectedWith(
                'staking token address not equal to RewardEscrow KWENTA address'
            );
    });
});

describe('setRewards()', () => {
    beforeEach(async () => {
        await deployNewRewardsEscrow(owner, kwentaToken);

        StakingRewards = await deployContract();
        stProxy = await deployProxy();

        await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
        await stProxy.connect(owner).setRewardEscrow(rewardsEscrow.address);

        await rewardsEscrow.setStakingRewards(stProxy.address);
    });

    it("next week is new epoch", async () => {
        await stProxy.connect(supplySchedule).setRewards(toUnit(5));
        const oldEpoch = await stProxy.currentEpoch();
        await fastForward(WEEK);
        await stProxy.connect(supplySchedule).setRewards(toUnit(5));
        assertBNGreaterThan(
            await stProxy.currentEpoch(),
            oldEpoch
        );
    });

    it("first periodFinish should be in the next epoch", async () => {
        await stProxy.connect(supplySchedule).setRewards(toUnit(5));
        assertBNGreaterThan(
            await stProxy.periodFinish(),
            await stProxy.currentEpoch()
        );
    });

    it("rewardRate accounts remaining time in epoch", async () => {
        const reward = toUnit(5);

        await stProxy.connect(supplySchedule).setRewards(reward);

        assertBNNotEqual(
            await currentTime(),
            await stProxy.currentEpoch()
        );

        const currentEpoch = await getCurrentEpoch();
        const timeElapsedSincePeriodStart = hre.ethers.BigNumber.from(await currentTime()).sub(currentEpoch).toNumber();

        assertBNEqual(
            await stProxy.rewardRate(),
            hre.ethers.BigNumber.from(reward).div(WEEK - timeElapsedSincePeriodStart)
        )
    });
})
