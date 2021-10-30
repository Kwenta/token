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

const Owned = artifacts.require("Owned");

let FixidityLib = artifacts.require("FixidityLib");
let ExponentLib = artifacts.require("ExponentLib");
let LogarithmLib = artifacts.require("LogarithmLib");

let StakingRewards = artifacts.require("StakingRewards");
let StakingRewardsV2 = artifacts.require("StakingRewardsV2");
let TokenContract = artifacts.require("ERC20");
let RewardsEscrow = artifacts.require("RewardEscrow");

let res;

require("chai")
	.use(require("chai-as-promised"))
	.use(require("chai-bn-equal"))
	.should();

contract('Staking Rewards with decay rate', ([owner, rewardsDistribution, staker1, staker2]) => {
	console.log("Start tests");
	let stakingRewards;
	let stakingToken;
	let rewardsToken;
	let rewardsEscrow;

	before(async() => {
		stakingToken = await TokenContract.new(NAME, SYMBOL);
		rewardsToken = await TokenContract.new(NAME, SYMBOL);
		rewardsEscrow = await RewardsEscrow.new(
				owner,
				stakingToken.address
			);
		// console.log("Before: ,", stakingToken);
	});

	describe("Deployment", async() => {
		it("should deploy the contracts", async() => {

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

			stakingRewards = await StakingRewards.new();

			stakingRewards.initialize(owner,
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

		});
	});

	describe("Decay rate", async() => {
		it("should update total correctly", async() => {

			await stakingToken._mint(rewardsEscrow.address, toUnit(1000));
			await stakingToken._mint(staker1, toUnit(100));
			await stakingToken._mint(staker2, toUnit(100));

			await rewardsToken._mint(stakingRewards.address, toUnit(500));
			
			await stakingToken.approve(stakingRewards.address, toUnit(100), {from: staker1});
			await stakingToken.approve(stakingRewards.address, toUnit(100), {from: staker2});

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

			res = await stakingRewards.rewardScoreOf(staker1);
			console.log("Total for staker1 is", res.toString());	
			res = await stakingRewards.totalRewardScore();
			console.log("Total for staker1 is", res.toString());	
			res = await stakingRewards.rewardRate();
			console.log("Total for staker1 is", res.toString());	
			res = await stakingRewards.lastUpdateTimeFeeDecay();
			console.log("Total for staker1 is", res.toString());
			res = await stakingRewards.lastTimeRewardApplicable();
			console.log("Total for staker1 is", res.toString());		

			let rewStaker1 = await stakingRewards.earned(staker1);
			console.log("Total for staker1 is", rewStaker1.toString());

			let rewStaker2 = await stakingRewards.earned(staker2);
			console.log("Total for staker2 is", rewStaker2.toString());

		})

		

	});
});