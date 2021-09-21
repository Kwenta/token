const { toBN, toWei } = require('web3-utils');
const hardhat = require('hardhat');

const send = payload => {
		if (!payload.jsonrpc) payload.jsonrpc = '2.0';
		if (!payload.id) payload.id = new Date().getTime();

		return new Promise((resolve, reject) => {
			web3.currentProvider.send(payload, (error, result) => {
				if (error) return reject(error);

				return resolve(result);
			});
		});
	};
const mineBlock = () => send({ method: 'evm_mine' });

const StakingRewards = artifacts.require("StakingRewards");

const toUnit = amount => toBN(toWei(amount.toString(), 'ether'));
const currentTime = async () => {
		const { timestamp } = await web3.eth.getBlock('latest');
		return timestamp;
	};
const fastForward = async seconds => {
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
const assertBNGreaterThan = (aBN, bBN) => {
	assert.ok(aBN.gt(bBN), `${aBN.toString()} is not greater than ${bBN.toString()}`);
};
const assertBNEqual = (actualBN, expectedBN, context) => {
		assert.strictEqual(actualBN.toString(), expectedBN.toString(), context);
	};
const BN = require('bn.js');

require("chai")
	.use(require("chai-as-promised"))
	.use(require("chai-bn-equal"))
	.should();

contract('StakingRewards_KWENTA', ([owner, rewardsDistribution, rewardsToken, stakingToken, staker1, staker2]) => {
	console.log("Start tests");
	let stakingRewards;
	const DAY = 86400;
	const ZERO_BN = toBN(0);

	before(async() => {
		stakingRewards = await StakingRewards.new(owner,
			rewardsDistribution,
			rewardsToken,
			stakingToken
			);
	});

	describe("StakingRewards_KWENTA deployment", async() => {
		it("deploys with correct addresses", async() => {
			assert.equal(await stakingRewards.owner(), owner);
			assert.equal(await stakingRewards.rewardsDistribution(), rewardsDistribution);
			assert.equal(await stakingRewards.rewardsToken(), rewardsToken);
			assert.equal(await stakingRewards.stakingToken(), stakingToken);

		})
	});

	describe("stake()", async() => {
		it("fails with zero amounts", async() => {
			await stakingRewards.stake(0, {from: staker1}).should.be.rejected;
		})
		it("stakes the correct amount", async() => {
			await stakingRewards.stake(15, {from: staker1});
			let bal = await stakingRewards.balanceOf(staker1);
			assert.equal(bal, 15, "Incorrect amount");
			let ts = await stakingRewards.totalSupply();
			assert.equal(ts, 15, "Incorrect _totalSupply");

			await stakingRewards.stake(50, {from: staker2});
			bal = await stakingRewards.balanceOf(staker2);
			assert.equal(bal, 50, "Incorrect amount");
			ts = await stakingRewards.totalSupply();
			assert.equal(ts, 65, "Incorrect _totalSupply");
		})
	});

	describe("withdraw()", async() => {
		it("fails with zero amounts", async() => {
			await stakingRewards.withdraw(0, {from: staker1}).should.be.rejected;
		})
		it("withdraws the correct amount", async() => {
			await stakingRewards.withdraw(15, {from: staker1});
			let bal = await stakingRewards.balanceOf(staker1);
			assert.equal(bal, 0, "Incorrect amount");
			let ts = await stakingRewards.totalSupply();
			assert.equal(ts, 50, "Incorrect _totalSupply");

			await stakingRewards.withdraw(50, {from: staker2});
			bal = await stakingRewards.balanceOf(staker2);
			assert.equal(bal, 0, "Incorrect amount");
			ts = await stakingRewards.totalSupply();
			assert.equal(ts, 0, "Incorrect _totalSupply");
		})
	});

	describe("traderScore()", async() => {
		it("initializes updatesTraderScore correctly", async() => {
			let ts1 = await stakingRewards._feesPaid(staker1);
			let ts2 = await stakingRewards._feesPaid(staker2);
			assert.equal(ts1, 0);
			assert.equal(ts2, 0);
		})

		it("updates updatesTraderScore correctly", async() => {
			await stakingRewards.updateTraderScore(staker1, 5);
			await stakingRewards.updateTraderScore(staker2, 4);

			let ts1 = await stakingRewards._feesPaid(staker1);
			let expected = 5;
			
			assert.equal(ts1, expected);

			let ts2 = await stakingRewards._feesPaid(staker2);
			expected = 4;

			assert.equal(ts2, expected);
		})
	});

	describe('lastTimeRewardApplicable()', () => {
		it('should return 0', async () => {
			assert.equal(await stakingRewards.lastTimeRewardApplicable(), 0);
		});

		describe('when updated', () => {
			it('should equal current timestamp', async () => {
				await stakingRewards.notifyRewardAmount(toUnit(1.0), {
					from: rewardsDistribution,
				});

				const cur = await currentTime();
				const lastTimeReward = await stakingRewards.lastTimeRewardApplicable();

				assert.equal(cur.toString(), lastTimeReward.toString());
			});
		});
	});

	describe('rewardPerToken()', () => {
		it('should return 0', async () => {
			assert.equal(await stakingRewards.rewardPerRewardScore(), 0);
		});

		it('should be > 0', async () => {
			const totalToStake = toUnit('100');
			//await stakingToken.transfer(staker1, totalToStake, { from: owner });
			//await stakingToken.approve(stakingRewards.address, totalToStake, { from: staker1 });
			await stakingRewards.stake(totalToStake, { from: staker1 });

			const totalSupply = await stakingRewards.totalSupply();
			assertBNGreaterThan(totalSupply, 0);

			const rewardValue = toUnit(50.0);
			//await rewardsToken.transfer(stakingRewards.address, rewardValue, { from: owner });
			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(DAY);

			const rewardPerRewardScore = await stakingRewards.rewardPerRewardScore();
			assertBNGreaterThan(rewardPerRewardScore, 0);
		});
	});

	describe('earned()', () => {

		it('should be > 0 when staking', async () => {
			const totalToStake = toUnit('1');
			//await stakingToken.transfer(staker1, totalToStake, { from: owner });
			//await stakingToken.approve(stakingRewards.address, totalToStake, { from: staker1 });

			await stakingRewards.stake(totalToStake, { from: staker1 });

			const rewardValue = toUnit(5000.0);
			//await rewardsToken.transfer(stakingRewards.address, rewardValue, { from: owner });
			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(DAY);

			const earned = await stakingRewards.earned(staker1);

			assertBNGreaterThan(earned, ZERO_BN);
		});

		it('rewardRate should increase if new rewards come before DURATION ends', async () => {
			const totalToDistribute = toUnit('5000');

			//await rewardsToken.transfer(stakingRewards.address, totalToDistribute, { from: owner });
			await stakingRewards.notifyRewardAmount(totalToDistribute, {
				from: rewardsDistribution,
			});

			const rewardRateInitial = await stakingRewards.rewardRate();

			//await rewardsToken.transfer(stakingRewards.address, totalToDistribute, { from: owner });
			await stakingRewards.notifyRewardAmount(totalToDistribute, {
				from: rewardsDistribution,
			});

			const rewardRateLater = await stakingRewards.rewardRate();

			assertBNGreaterThan(rewardRateInitial, ZERO_BN);
			assertBNGreaterThan(rewardRateLater, rewardRateInitial);
		});
		
		describe('notifyRewardAmount()', () => {
		

		it('Reverts if the provided reward is greater than the balance.', async () => {
			const rewardValue = toUnit(100000000);
			//await rewardsToken.transfer(localStakingRewards.address, rewardValue, { from: owner });
			await (
				stakingRewards.notifyRewardAmount(rewardValue.add(toUnit(0.1)), {
					from: rewardsDistribution,
				})).should.be.rejected;;
		});

		
	});
	});
	
})