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

const toUnit = amount => toBN(toWei(amount.toString(), 'ether')).toString();

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

let owner;
let rewardsDistribution;
let staker1;
let staker2;
let stProxy;

before(async() => {
		[owner, rewardsDistribution, staker1, staker2] = await hre.ethers.getSigners();
		KwentaToken = await hre.ethers.getContractFactory("ERC20");
		kwentaToken = await KwentaToken.deploy(NAME, SYMBOL);
		RewardsEscrow = await await hre.ethers.getContractFactory("RewardEscrow");
		rewardsEscrow = await RewardsEscrow.deploy(owner.address, kwentaToken.address);
	});

describe("Proxy deployment", async() => {
	it("should deploy the proxy", async() => {
			// const [owner, rewardsDistribution, staker1, staker2] = await hre.ethers.getSigners();
			FixidityLib = await hre.ethers.getContractFactory("FixidityLib");
			fixidityLib = await FixidityLib.deploy();
			
			LogarithmLib = await hre.ethers.getContractFactory("LogarithmLib", {
				libraries: {FixidityLib: fixidityLib.address}
			});
			logarithmLib = await LogarithmLib.deploy();

			ExponentLib = await hre.ethers.getContractFactory("ExponentLib", {
				libraries: {FixidityLib: fixidityLib.address,
							LogarithmLib: logarithmLib.address,
				}
			});
			exponentLib = await ExponentLib.deploy();


			StakingRewards = await hre.ethers.getContractFactory("StakingRewards", {
				libraries: {FixidityLib: fixidityLib.address,
							ExponentLib: exponentLib.address,
				}
			});
			stProxy = await hre.upgrades.deployProxy(StakingRewards,
				[owner.address, rewardsDistribution.address, kwentaToken.address, 
				kwentaToken.address, rewardsEscrow.address],
				{kind: "uups",
				unsafeAllow: ["external-library-linking"]
				});

			admin_address = await hre.upgrades.erc1967.getAdminAddress(stProxy.address);
			implementation = await hre.upgrades.erc1967.getImplementationAddress(stProxy.address);

			owner_address = await stProxy.owner();

			assert.notEqual(implementation, stProxy.address);
		});
});

describe("Reward implementation", async() => {
	it("should calculate staking rewards correctly", async() => {
		rewardsEscrow.connect(owner).setStakingRewards(stProxy.address);

		kwentaToken._mint(rewardsEscrow.address, toUnit(1000));

		await kwentaToken._mint(staker1.address, toUnit(100));
		kwentaToken._mint(staker2.address, toUnit(100));

		kwentaToken._mint(stProxy.address, toUnit(500));

		await kwentaToken.connect(staker1).approve(stProxy.address, toUnit(100));
		await kwentaToken.connect(staker2).approve(stProxy.address, toUnit(100));

		await stProxy.connect(owner).setRewardsDuration(60);

		await stProxy.connect(staker1).stake(toUnit(10));
		await stProxy.connect(staker2).stake(toUnit(10));

		await stProxy.updateTraderScore(staker1.address, toUnit(25));
		await stProxy.updateTraderScore(staker2.address, toUnit(50));

		let rewardValue = toUnit(60);

		await stProxy.connect(rewardsDistribution).notifyRewardAmount(rewardValue);

		await fastForward(61);

		let rewStaker1 = await stProxy.earned(staker1.address);
		console.log("rewStaker1 is: ", rewStaker1.toString());

		let rewStaker2 = await stProxy.earned(staker2.address);
		console.log("rewStaker2 is: ", rewStaker2.toString());

		// Testing second leg of implementation

		await stProxy.connect(staker1).stake(toUnit(40));
		rewardValue = toUnit(60);

		await stProxy.connect(rewardsDistribution).notifyRewardAmount(rewardValue);

		await fastForward(61);

		rewStaker1 = await stProxy.earned(staker1.address);
		console.log("rewStaker1 is: ", rewStaker1.toString());

		rewStaker2 = await stProxy.earned(staker2.address);
		console.log("rewStaker2 is: ", rewStaker2.toString());

		// Testing third leg of implementation

		await stProxy.connect(owner).setRewardsDuration(30);

		tst = await stProxy.updateTraderScore(staker2.address, toUnit(20));

		rewardValue = toUnit(30);

		await stProxy.connect(rewardsDistribution).notifyRewardAmount(rewardValue);

		await fastForward(31);

		rewStaker1 = await stProxy.earned(staker1.address);
		console.log("rewStaker1 is: ", rewStaker1.toString());

		rewStaker2 = await stProxy.earned(staker2.address);
		console.log("rewStaker2 is: ", rewStaker2.toString());

		// Testing fourth leg of implementation

		await stProxy.connect(owner).setRewardsDuration(70);

		await stProxy.connect(staker2).stake(toUnit(20));

		rewardValue = toUnit(70);

		await stProxy.connect(rewardsDistribution).notifyRewardAmount(rewardValue);

		await fastForward(71);

		rewStaker1 = await stProxy.earned(staker1.address);
		console.log("rewStaker1 is: ", rewStaker1.toString());

		rewStaker2 = await stProxy.earned(staker2.address);
		console.log("rewStaker2 is: ", rewStaker2.toString());

		// Testing fifth leg of implementation

		await stProxy.connect(owner).setRewardsDuration(30);

		await stProxy.connect(staker1).withdraw(toUnit(10));

		rewardValue = toUnit(30);

		await stProxy.connect(rewardsDistribution).notifyRewardAmount(rewardValue);

		await fastForward(31);

		rewStaker1 = await stProxy.earned(staker1.address);
		console.log("rewStaker1 is: ", rewStaker1.toString());

		rewStaker2 = await stProxy.earned(staker2.address);
		console.log("rewStaker2 is: ", rewStaker2.toString());

		// Testing sixth leg of implementation

		await stProxy.connect(owner).setRewardsDuration(50);

		await stProxy.updateTraderScore(staker1.address, toUnit(100));

		rewardValue = toUnit(50);

		await stProxy.connect(rewardsDistribution).notifyRewardAmount(rewardValue);

		await fastForward(51);

		rewStaker1 = await stProxy.earned(staker1.address);
		console.log("rewStaker1 is: ", rewStaker1.toString());

		rewStaker2 = await stProxy.earned(staker2.address);
		console.log("rewStaker2 is: ", rewStaker2.toString());

		/*let res = await stProxy.lastTimeRewardApplicable();
		console.log(res.toString());
		res = await stProxy.lastUpdateTime();
		console.log(res.toString());
		res = await stProxy.rewardRateStaking();
		console.log(res.toString());
		res = await stProxy._totalSupply();
		console.log(res.toString());
*/
	});
});