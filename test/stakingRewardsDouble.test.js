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

	describe("Implementation test", () => {
		it("calculates rewards correctly", async() => {

			let bal1 = await stakingRewards.balanceOf(staker1);	
			let bal2 = await stakingRewards.balanceOf(staker2);	
			
			assert.equal(bal1, 0);
			assert.equal(bal2, 0);

			let fees1 = await stakingRewards._feesPaid(staker1);	
			let fees2 = await stakingRewards._feesPaid(staker2);	
			
			assert.equal(fees1, 0);
			assert.equal(fees2, 0);

			let totalSupply = await stakingRewards.totalSupply();	
			let totaltrading = await stakingRewards.totalFeesPaid();	
			
			assert.equal(totalSupply, 0);
			assert.equal(totaltrading, 0);

			await stakingRewards.updateTraderScore(staker1, toUnit(25));
			await stakingRewards.updateTraderScore(staker2, toUnit(50));

			console.log("------------------- Testing first leg -------------------");

			let rewardValue = toUnit(60);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(61);

			rr = await stakingRewards.earned(staker1, 1);
			console.log("Staker1 has earned: ", rr.toString());

			rr = await stakingRewards.earned(staker2, 1);
			console.log("Staker2 has earned: ", rr.toString());

			console.log("------------------- Testing second leg -------------------");

			await stakingRewards.stake(toUnit(40), {from: staker1});
			rewardValue = toUnit(60);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(61);

			rr = await stakingRewards.rewards(staker1);
			console.log("RewardRate: ", rr.toString());

			rr = await stakingRewards.earned(staker1, 1);
			console.log("Staker1 has earned: ", rr.toString());

			rr = await stakingRewards.earned(staker2, 1);
			console.log("Staker2 has earned: ", rr.toString());

			console.log("------------------- Testing third leg -------------------");

			await stakingRewards.setRewardsDuration(30, {from: owner});

			await stakingRewards.updateTraderScore(staker2, toUnit(70));

			rewardValue = toUnit(30);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(31);

			rr = await stakingRewards.earned(staker1, 1);
			console.log("Staker1 has earned: ", rr.toString());

			rr = await stakingRewards.earned(staker2, 1);
			console.log("Staker2 has earned: ", rr.toString());

			console.log("------------------- Testing fourth leg -------------------");

			await stakingRewards.setRewardsDuration(70, {from: owner});

			await stakingRewards.stake(toUnit(20), {from: staker2});

			rewardValue = toUnit(70);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(71);

			rr = await stakingRewards.earned(staker1, 1);
			console.log("Staker1 has earned: ", rr.toString());

			rr = await stakingRewards.earned(staker2, 1);
			console.log("Staker2 has earned: ", rr.toString());

			console.log("------------------- Testing fifth leg -------------------");

			await stakingRewards.setRewardsDuration(30, {from: owner});

			await stakingRewards.withdraw(toUnit(10), {from: staker1});

			rewardValue = toUnit(30);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(31);

			rr = await stakingRewards.earned(staker1, 1);
			console.log("Staker1 has earned: ", rr.toString());

			rr = await stakingRewards.earned(staker2, 1);
			console.log("Staker2 has earned: ", rr.toString());

			console.log("------------------- Testing sixth leg -------------------");

			await stakingRewards.setRewardsDuration(50, {from: owner});

			await stakingRewards.updateTraderScore(staker1, toUnit(125));

			rewardValue = toUnit(50);

			await stakingRewards.notifyRewardAmount(rewardValue, {
				from: rewardsDistribution,
			});

			await fastForward(51);

			rr = await stakingRewards.earned(staker1, 1);
			console.log("Staker1 has earned: ", rr.toString());

			rr = await stakingRewards.earned(staker2, 1);
			console.log("Staker2 has earned: ", rr.toString());
			
		});	
	});
});