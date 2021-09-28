const { toBN, toWei, fromWei} = require('web3-utils');
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
const TokenContract = artifacts.require("ERC20");
const RewardsEscrow = artifacts.require("RewardEscrow");

const NAME = "Kwenta";
const SYMBOL = "KWENTA";

const toUnit = amount => toBN(toWei(amount.toString(), 'ether'));

const assertBNClose = (actualBN, expectedBN, varianceParam = '10') => {
		const actual = BN.isBN(actualBN) ? actualBN : new BN(actualBN);
		const expected = BN.isBN(expectedBN) ? expectedBN : new BN(expectedBN);
		const variance = BN.isBN(varianceParam) ? varianceParam : new BN(varianceParam);
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

contract('StakingRewards_KWENTA', ([owner, rewardsDistribution, staker1, staker2]) => {
	console.log("Start tests");
	let stakingRewards;
	let stakingToken;
	let rewardsToken;
	const DAY = 86400;
	const ZERO_BN = toBN(0);

	before(async() => {
		stakingToken = await TokenContract.new(NAME, SYMBOL);
		rewardsToken = await TokenContract.new(NAME, SYMBOL);

		stakingRewards = await StakingRewards.new(owner,
			rewardsDistribution,
			rewardsToken.address,
			stakingToken.address
			);

		stakingToken._mint(staker1, 100);
		stakingToken._mint(staker2, 100);

		rewardsToken._mint(stakingRewards.address, toUnit(100));

	});

	describe("StakingRewards_KWENTA deployment", async() => {
		it("deploys with correct addresses", async() => {
			assert.equal(await stakingRewards.owner(), owner);
			assert.equal(await stakingRewards.rewardsDistribution(), rewardsDistribution);
			assert.equal(await stakingRewards.rewardsToken(), rewardsToken.address);
			assert.equal(await stakingRewards.stakingToken(), stakingToken.address);

		})
	});

	describe("stake()", async() => {
		it("fails with zero amounts", async() => {
			await stakingRewards.stake(0, {from: staker1}).should.be.rejected;
		})
		it("stakes the correct amount", async() => {

			await stakingToken.approve(stakingRewards.address, 100, {from: staker1});
			await stakingToken.approve(stakingRewards.address, 100, {from: staker2});

			await stakingRewards.stake(15, {from: staker1});

			let bal = await stakingRewards.balanceOf(staker1);
			assert.equal(bal, 15, "Incorrect amount");

			await stakingRewards.stake(50, {from: staker2});
			bal = await stakingRewards.balanceOf(staker2);
			assert.equal(bal, 50, "Incorrect amount");
			
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

			await stakingRewards.withdraw(50, {from: staker2});
			bal = await stakingRewards.balanceOf(staker2);
			assert.equal(bal, 0, "Incorrect amount");
		})
	});

	describe("traderScore()", async() => {
		it("initializes updatesTraderScore correctly", async() => {
			let ts1 = await stakingRewards.feesOf(staker1);
			let ts2 = await stakingRewards.feesOf(staker2);
			assert.equal(ts1, 0);
			assert.equal(ts2, 0);
		})

		it("updates updatesTraderScore correctly", async() => {
			await stakingRewards.stake(5, {from: staker1});
			await stakingRewards.stake(5, {from: staker2});

			await stakingRewards.updateTraderScore(staker1, 5);
			await stakingRewards.updateTraderScore(staker2, 4);

			let ts1 = await stakingRewards.feesOf(staker1);
			let expected = 5;
			
			assert.equal(ts1, expected);

			let ts2 = await stakingRewards.feesOf(staker2);
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
			const totalToStake = 10;
			;
			await stakingRewards.stake(totalToStake, { from: staker1 });

			const totalRewardScore = await stakingRewards.totalRewardScore();
			assertBNGreaterThan(totalRewardScore, 0);

			const rewardValue = toUnit(50.0);
			
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
			const totalToStake = 1;

			await stakingRewards.stake(totalToStake, { from: staker1 });

			const rewardValue = toUnit(5.0);
			
			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(DAY);

			const earned = await stakingRewards.earned(staker1);

			assertBNGreaterThan(earned, ZERO_BN);
		});

		it('should be > 0 when trading', async () => {

			await stakingRewards.updateTraderScore(staker1, 30);

			const rewardValue = toUnit(5.0);
			
			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(DAY);

			const earned = await stakingRewards.earned(staker1);

			assertBNGreaterThan(earned, ZERO_BN);
		});

		it('rewardRate should increase if new rewards come before DURATION ends', async () => {
			const totalToDistribute = toUnit('5');

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

	describe("Implementation test", () => {
		it("calculates rewards correctly", async() => {

			stakingToken = await TokenContract.new(NAME, SYMBOL);
			rewardsToken = await TokenContract.new(NAME, SYMBOL);

			stakingRewards = await StakingRewards.new(owner,
				rewardsDistribution,
				rewardsToken.address,
				stakingToken.address
				);

			rewardsEscrow = await RewardsEscrow.new(
				owner,
				stakingToken.address,
				stakingRewards.address
			);

			stakingRewards.setRewardEscrow(rewardsEscrow.address, {from: owner});

			stakingToken._mint(rewardsEscrow.address, toUnit(1000));

			stakingToken._mint(staker1, toUnit(100));
			stakingToken._mint(staker2, toUnit(100));

			rewardsToken._mint(stakingRewards.address, toUnit(500));

			await stakingToken.approve(stakingRewards.address, toUnit(100), {from: staker1});
			await stakingToken.approve(stakingRewards.address, toUnit(100), {from: staker2});

			let bal1 = await stakingRewards.balanceOf(staker1);	
			let bal2 = await stakingRewards.balanceOf(staker2);	
			
			assert.equal(bal1, 0);
			assert.equal(bal2, 0);

			let fees1 = await stakingRewards.feesOf(staker1);	
			let fees2 = await stakingRewards.feesOf(staker2);	
			
			assert.equal(fees1, 0);
			assert.equal(fees2, 0);

			let totalRewardScore = await stakingRewards.totalRewardScore();	
			
			assert.equal(totalRewardScore, 0);

			// Testing first leg of implementation

			await stakingRewards.stake(toUnit(10), {from: staker1});
			await stakingRewards.stake(toUnit(10), {from: staker2});

			await stakingRewards.updateTraderScore(staker1, toUnit(25));
			await stakingRewards.updateTraderScore(staker2, toUnit(50));

			let rewardValue = toUnit(60);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(61);

			let rewStaker1 = await stakingRewards.earned(staker1);
			assert.equal(rewStaker1.toString(), toUnit(20));

			let rewStaker2 = await stakingRewards.earned(staker2);
			assert.equal(rewStaker2.toString(), toUnit(40));

			// Testing second leg of implementation

			await stakingRewards.stake(toUnit(40), {from: staker1});
			rewardValue = toUnit(60);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(61);

			rewStaker1 = await stakingRewards.earned(staker1);
			assertBNClose(rewStaker1, toUnit(62.857), toUnit(0.01));

			rewStaker2 = await stakingRewards.earned(staker2);
			assertBNClose(rewStaker2, toUnit(57.143), toUnit(0.01));

			// Testing third leg of implementation

			await stakingRewards.setRewardsDuration(30, {from: owner});

			tst = await stakingRewards.updateTraderScore(staker2, toUnit(20));

			rewardValue = toUnit(30);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(31);

			rewStaker1 = await stakingRewards.earned(staker1);
			assertBNClose(rewStaker1, toUnit(82.088), toUnit(0.01));

			rewStaker2 = await stakingRewards.earned(staker2);
			assertBNClose(rewStaker2, toUnit(67.912), toUnit(0.01));

			// Testing fourth leg of implementation

			await stakingRewards.setRewardsDuration(70, {from: owner});

			await stakingRewards.stake(toUnit(20), {from: staker2});

			rewardValue = toUnit(70);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(71);

			rewStaker1 = await stakingRewards.earned(staker1);
			assertBNClose(rewStaker1, toUnit(108.207), toUnit(0.01));

			rewStaker2 = await stakingRewards.earned(staker2);
			assertBNClose(rewStaker2, toUnit(111.793), toUnit(0.01));

			// Testing fifth leg of implementation

			await stakingRewards.setRewardsDuration(30, {from: owner});

			await stakingRewards.withdraw(toUnit(10), {from: staker1});

			rewardValue = toUnit(30);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(31);

			rewStaker1 = await stakingRewards.earned(staker1);
			assertBNClose(rewStaker1, toUnit(117.885), toUnit(0.1));

			rewStaker2 = await stakingRewards.earned(staker2);
			assertBNClose(rewStaker2, toUnit(132.115), toUnit(0.1));

			// Testing sixth leg of implementation

			await stakingRewards.setRewardsDuration(50, {from: owner});

			await stakingRewards.updateTraderScore(staker1, toUnit(100));

			rewardValue = toUnit(50);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(51);

			rewStaker1 = await stakingRewards.earned(staker1);
			assertBNClose(rewStaker1, toUnit(153.096), toUnit(0.1));

			rewStaker2 = await stakingRewards.earned(staker2);
			assertBNClose(rewStaker2, toUnit(146.904), toUnit(0.1));

			await stakingRewards.exit({from: staker1});
			await stakingRewards.exit({from: staker2});

			bal1 = await rewardsEscrow.totalEscrowedAccountBalance(staker1);	
			bal2 = await rewardsEscrow.totalEscrowedAccountBalance(staker2);	
			
			assert.equal(bal1.toString(), rewStaker1.toString());
			assert.equal(bal2.toString(), rewStaker2.toString());
		});
	});

	
	
})