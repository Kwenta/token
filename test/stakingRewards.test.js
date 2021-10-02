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

const FixidityLib = artifacts.require("FixidityLib");
const ExponentLib = artifacts.require("ExponentLib");
const LogarithmLib = artifacts.require("LogarithmLib");

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

contract('StakingRewards KWENTA', ([owner, rewardsDistribution, staker1, staker2]) => {
	console.log("Start tests");
	let stakingRewards;
	let stakingToken;
	let rewardsToken;
	let rewardsEscrow;
	const DAY = 86400;
	const ZERO_BN = toBN(0);

	before(async() => {
		stakingToken = await TokenContract.new(NAME, SYMBOL);
		rewardsToken = await TokenContract.new(NAME, SYMBOL);

		fixidityLib = await FixidityLib.new();
		await LogarithmLib.link(fixidityLib);
		logarithmLib = await LogarithmLib.new();
		await ExponentLib.link(fixidityLib);
		await ExponentLib.link(logarithmLib);
		exponentLib = await ExponentLib.new();

		await StakingRewards.link(fixidityLib);
		await StakingRewards.link(exponentLib);
		rewardsEscrow = await RewardsEscrow.new(
				owner,
				stakingToken.address
			);

		stakingRewards = await StakingRewards.new(owner,
			rewardsDistribution,
			rewardsToken.address,
			stakingToken.address,
			rewardsEscrow.address
			);


		rewardsEscrow.setStakingRewards(stakingRewards.address, {from: owner});
		rewardsToken._mint(stakingRewards.address, toUnit(100));

		stakingToken._mint(staker1, toUnit(100));
		stakingToken._mint(staker2, toUnit(100));


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

			await stakingToken.approve(stakingRewards.address, toUnit(100), {from: staker1});
			await stakingToken.approve(stakingRewards.address, toUnit(100), {from: staker2});

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
			let ts1 = await stakingRewards.feesPaidBy(staker1);
			let ts2 = await stakingRewards.feesPaidBy(staker2);
			assert.equal(ts1, 0);
			assert.equal(ts2, 0);
		})

		it("updates updatesTraderScore correctly", async() => {
			await stakingRewards.stake(toUnit(5), {from: staker1});
			await stakingRewards.stake(toUnit(5), {from: staker2});

			await stakingRewards.updateTraderScore(staker1, toUnit(5));
			await stakingRewards.updateTraderScore(staker2, toUnit(4));

			let ts1 = await stakingRewards.feesPaidBy(staker1);
			let expected = toUnit(5);
			
			assertBNEqual(ts1, expected);

			let ts2 = await stakingRewards.feesPaidBy(staker2);
			expected = toUnit(4);

			assertBNEqual(ts2, expected);
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
			const totalToStake = toUnit(10);
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

		it('should be 0 when staking but not trading', async () => {
			stakingRewards = await StakingRewards.new(owner,
				rewardsDistribution,
				rewardsToken.address,
				stakingToken.address,
				rewardsEscrow.address
				);


			rewardsEscrow.setStakingRewards(stakingRewards.address, {from: owner});
			rewardsToken._mint(stakingRewards.address, toUnit(100));
			await stakingToken.approve(stakingRewards.address, toUnit(100), {from: staker1});
			await stakingToken.approve(stakingRewards.address, toUnit(100), {from: staker2});

			const totalToStake = toUnit(1);

			await stakingRewards.stake(totalToStake, { from: staker1 });

			const rewardValue = toUnit(5.0);
			
			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(DAY);

			const earned = await stakingRewards.earned(staker1);

			assertBNEqual(earned, ZERO_BN);
		});

		it('should be 0 when trading and not staking', async () => {
			stakingRewards = await StakingRewards.new(owner,
				rewardsDistribution,
				rewardsToken.address,
				stakingToken.address,
				rewardsEscrow.address
				);


			rewardsEscrow.setStakingRewards(stakingRewards.address, {from: owner});
			rewardsToken._mint(stakingRewards.address, toUnit(100));
			await stakingToken.approve(stakingRewards.address, toUnit(100), {from: staker1});
			await stakingToken.approve(stakingRewards.address, toUnit(100), {from: staker2});

			await stakingRewards.updateTraderScore(staker1, 30);

			const rewardValue = toUnit(5.0);
			
			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(DAY);

			const earned = await stakingRewards.earned(staker1);

			assertBNEqual(earned, ZERO_BN);
		});

		it('should be 0 when not trading and not staking', async () => {
			stakingRewards = await StakingRewards.new(owner,
				rewardsDistribution,
				rewardsToken.address,
				stakingToken.address,
				rewardsEscrow.address
				);


			rewardsEscrow.setStakingRewards(stakingRewards.address, {from: owner});
			rewardsToken._mint(stakingRewards.address, toUnit(100));
			await stakingToken.approve(stakingRewards.address, toUnit(100), {from: staker1});
			await stakingToken.approve(stakingRewards.address, toUnit(100), {from: staker2});

			const rewardValue = toUnit(5.0);
			
			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(DAY);

			const earned = await stakingRewards.earned(staker1);

			assertBNEqual(earned, ZERO_BN);
		});

		it('should be > 0 when trading and staking', async () => {
			stakingRewards = await StakingRewards.new(owner,
				rewardsDistribution,
				rewardsToken.address,
				stakingToken.address,
				rewardsEscrow.address
				);


			rewardsEscrow.setStakingRewards(stakingRewards.address, {from: owner});
			rewardsToken._mint(stakingRewards.address, toUnit(100));
			await stakingToken.approve(stakingRewards.address, toUnit(100), {from: staker1});
			await stakingToken.approve(stakingRewards.address, toUnit(100), {from: staker2});

			const totalToStake = toUnit(1);

			await stakingRewards.stake(totalToStake, { from: staker1 });

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

			rewardsEscrow = await RewardsEscrow.new(
				owner,
				stakingToken.address
			);

			stakingRewards = await StakingRewards.new(owner,
				rewardsDistribution,
				rewardsToken.address,
				stakingToken.address,
				rewardsEscrow.address
				);


			rewardsEscrow.setStakingRewards(stakingRewards.address, {from: owner});

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

			let fees1 = await stakingRewards.feesPaidBy(staker1);	
			let fees2 = await stakingRewards.feesPaidBy(staker2);	
			
			assert.equal(fees1, 0);
			assert.equal(fees2, 0);

			let totalRewardScore = await stakingRewards.totalRewardScore();	
			
			assert.equal(totalRewardScore, 0);

			// Testing first leg of implementation

			await stakingRewards.setRewardsDuration(60, {from: owner});

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
			assertBNClose(rewStaker1, toUnit(26.892), toUnit(0.01));

			let rewStaker2 = await stakingRewards.earned(staker2);
			assertBNClose(rewStaker2, toUnit(33.108), toUnit(0.01));

			// Testing second leg of implementation

			await stakingRewards.stake(toUnit(40), {from: staker1});
			rewardValue = toUnit(60);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(61);

			rewStaker1 = await stakingRewards.earned(staker1);
			assertBNClose(rewStaker1, toUnit(69.778), toUnit(0.01));

			rewStaker2 = await stakingRewards.earned(staker2);
			assertBNClose(rewStaker2, toUnit(50.222), toUnit(0.01));

			// Testing third leg of implementation

			await stakingRewards.setRewardsDuration(30, {from: owner});

			tst = await stakingRewards.updateTraderScore(staker2, toUnit(20));

			rewardValue = toUnit(30);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(31);

			rewStaker1 = await stakingRewards.earned(staker1);
			assertBNClose(rewStaker1, toUnit(90.591), toUnit(0.01));

			rewStaker2 = await stakingRewards.earned(staker2);
			assertBNClose(rewStaker2, toUnit(59.409), toUnit(0.01));

			// Testing fourth leg of implementation

			await stakingRewards.setRewardsDuration(70, {from: owner});

			await stakingRewards.stake(toUnit(20), {from: staker2});

			rewardValue = toUnit(70);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(71);

			rewStaker1 = await stakingRewards.earned(staker1);
			assertBNClose(rewStaker1, toUnit(126.443), toUnit(0.01));

			rewStaker2 = await stakingRewards.earned(staker2);
			assertBNClose(rewStaker2, toUnit(93.557), toUnit(0.01));

			// Testing fifth leg of implementation

			await stakingRewards.setRewardsDuration(30, {from: owner});

			await stakingRewards.withdraw(toUnit(10), {from: staker1});

			rewardValue = toUnit(30);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(31);

			rewStaker1 = await stakingRewards.earned(staker1);
			assertBNClose(rewStaker1, toUnit(140.637), toUnit(0.01));

			rewStaker2 = await stakingRewards.earned(staker2);
			assertBNClose(rewStaker2, toUnit(109.363), toUnit(0.01));

			// Testing sixth leg of implementation

			await stakingRewards.setRewardsDuration(50, {from: owner});

			await stakingRewards.updateTraderScore(staker1, toUnit(100));

			rewardValue = toUnit(50);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(51);

			rewStaker1 = await stakingRewards.earned(staker1);
			assertBNClose(rewStaker1, toUnit(170.274), toUnit(0.01));

			rewStaker2 = await stakingRewards.earned(staker2);
			assertBNClose(rewStaker2, toUnit(129.726), toUnit(0.01));

			await stakingRewards.exit({from: staker1});
			await stakingRewards.exit({from: staker2});

			bal1 = await rewardsEscrow.totalEscrowedAccountBalance(staker1);	
			bal2 = await rewardsEscrow.totalEscrowedAccountBalance(staker2);	
			
			assert.equal(bal1.toString(), rewStaker1.toString());
			assert.equal(bal2.toString(), rewStaker2.toString());

			fastForward(60*60*24*366);

			bal1 = await stakingToken.balanceOf(staker1);	
			bal2 = await stakingToken.balanceOf(staker2);

			assert.equal(bal1.toString(), toUnit(100));
			assert.equal(bal2.toString(), toUnit(100));

			await rewardsEscrow.vest({from: staker1});
			await rewardsEscrow.vest({from: staker2});

			bal1 = await stakingToken.balanceOf(staker1);	
			bal2 = await stakingToken.balanceOf(staker2);

			assertBNClose(bal1, toUnit(270.274), toUnit(0.01));
			assertBNClose(bal2, toUnit(229.726), toUnit(0.01));

			bal1 = await rewardsEscrow.totalEscrowedAccountBalance(staker1);	
			bal2 = await rewardsEscrow.totalEscrowedAccountBalance(staker2);

			assert.equal(bal1.toString(), 0);
			assert.equal(bal2.toString(), 0);

			bal1 = await stakingRewards.totalBalanceOf(staker1);	
			bal2 = await stakingRewards.totalBalanceOf(staker2);

			assert.equal(bal1.toString(), 0);
			assert.equal(bal2.toString(), 0);

			bal1 = await stakingRewards.escrowedBalanceOf(staker1);	
			bal2 = await stakingRewards.escrowedBalanceOf(staker2);

			assert.equal(bal1.toString(), 0);
			assert.equal(bal2.toString(), 0);

		});
	});

	
	
})