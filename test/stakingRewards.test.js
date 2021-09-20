const { toBN, toWei } = require('web3-utils');

const StakingRewards = artifacts.require("StakingRewards");

const toUnit = amount => toBN(toWei(amount.toString(), 'ether'));
const currentTime = async () => {
		const { timestamp } = await web3.eth.getBlock('latest');
		return timestamp;
	};

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
			let ts1 = await stakingRewards._tradingScores(staker1);
			let ts2 = await stakingRewards._tradingScores(staker2);
			assert.equal(ts1, 0);
			assert.equal(ts2, 0);
		})

		it("updates updatesTraderScore correctly", async() => {
			await stakingRewards.updateTraderScore(staker1, 5);
			await stakingRewards.updateTraderScore(staker2, 4);

			let ts1 = await stakingRewards._tradingScores(staker1);
			let expected = 3;
			
			assert.equal(ts1, expected);

			let ts2 = await stakingRewards._tradingScores(staker2);
			expected = 2;

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

		/*
	describe("rewards", async() => {
		it("updates calculates rewards correctly", async() => {
			// Nacho stakes 5
			await stakingRewards.stake(5, {from: staker1});
			await stakingRewards.updateTraderScore(20, 3, staker1);
			let tsN = await stakingRewards._tradingScores(staker1);
			assert.equal(tsN, 3600);
			await stakingRewards.updateStakerScore(staker1);
			let ssN = await stakingRewards.stakerScores(staker1);
			assert.equal(ssN, 1);
			var crN = await stakingRewards.calculateRewardScore(staker1);
			assert.equal(crN, 1*1000000);
			
			await stakingRewards.stake(10, {from: staker2});
			await stakingRewards.updateTraderScore(2, 3, staker1);
			tsN = await stakingRewards._tradingScores(staker1);
			assert.equal(tsN, 36);

			await stakingRewards.updateTraderScore(3, 5, staker2);
			let tsJ = await stakingRewards._tradingScores(staker2);
			assert.equal(tsJ, 225);

			crN = await stakingRewards.calculateRewardScore(staker1);
			assert.equal(crN, 12638);
			//console.log("Reward score is, ", crN);

			crJ = await stakingRewards.calculateRewardScore(staker2);
			assert.equal(crJ, 987361);
			//console.log("Reward score is, ", crJ);

			await stakingRewards.stake(20, {from: staker3});
			await stakingRewards.updateTraderScore(5, 1, staker1);
			await stakingRewards.updateTraderScore(4, 5, staker2);
			await stakingRewards.updateTraderScore(4, 10, staker3);

			crN = await stakingRewards.calculateRewardScore(staker1);
			assert.equal(crN, 59);
			crJ = await stakingRewards.calculateRewardScore(staker2);
			assert.equal(crJ, 30301);
			crA = await stakingRewards.calculateRewardScore(staker3);
			assert.equal(crA, 969639);

		})
	})
		*/
	
})