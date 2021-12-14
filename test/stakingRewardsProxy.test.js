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
const INITIAL_SUPPLY = hre.ethers.utils.parseUnits("313373");
const DAY = 86400;
const WEEK = DAY * 7;
const ZERO_BN = toBN(0);

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

const assertBNGreaterThan = (aBN, bBN) => {
	assert.ok(aBN.gt(bBN), `${aBN.toString()} is not greater than ${bBN.toString()}`);
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
const assertBNEqual = (actualBN, expectedBN, context) => {
		assert.strictEqual(actualBN.toString(), expectedBN.toString(), context);
	};
const BN = require('bn.js');

require("chai")
	.use(require("chai-as-promised"))
	.use(require("chai-bn-equal"))
	.should();

let owner;
let staker1;
let staker2;
let treasuryDAO;
let rewardsDistribution;
let supplySchedule;
let stProxy;
let exchangerProxy;
let rewardsEscrow;

let res;

const deployContract = async () => {
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
					ExponentLib: exponentLib.address
		}
	});
	return StakingRewards;
}
 
before(async() => {
		[owner, staker1, staker2, exchangerProxy, rewardsDistribution, treasuryDAO, supplySchedule] = await hre.ethers.getSigners();
		KwentaToken = await hre.ethers.getContractFactory("Kwenta");
		kwentaToken = await KwentaToken.deploy(NAME, 
			SYMBOL,
			INITIAL_SUPPLY,
			treasuryDAO.address,
			rewardsDistribution.address,
			supplySchedule.address
		);
		RewardsEscrow = await await hre.ethers.getContractFactory("RewardEscrow");
		rewardsEscrow = await RewardsEscrow.deploy(owner.address, kwentaToken.address);

		await kwentaToken.connect(treasuryDAO).transfer(staker1.address, toUnit(100));
		await kwentaToken.connect(treasuryDAO).transfer(staker2.address, toUnit(100));
	});

describe("Proxy deployment", async() => {
	it("should deploy the proxy", async() => {

		StakingRewards = await deployContract();
		stProxy = await hre.upgrades.deployProxy(StakingRewards,
			[owner.address, kwentaToken.address, 
			kwentaToken.address, rewardsEscrow.address, 3],
			{kind: "uups",
			unsafeAllow: ["external-library-linking"]
			});

			admin_address = await hre.upgrades.erc1967.getAdminAddress(stProxy.address);
			implementation = await hre.upgrades.erc1967.getImplementationAddress(stProxy.address);

			owner_address = await stProxy.owner();

			assert.notEqual(implementation, stProxy.address);

			await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);

			await kwentaToken.connect(treasuryDAO).transfer(stProxy.address, toUnit(500));

		});
	});

describe("StakingRewards deployment", async() => {
		it("deploys with correct addresses", async() => {
			assert.equal(await stProxy.owner(), owner.address);
			assert.equal(await stProxy.rewardsToken(), kwentaToken.address);
			assert.equal(await stProxy.stakingToken(), kwentaToken.address);
			assert.equal(await stProxy.getAdmin(), owner.address);
		})
	});

describe("stake()", async() => {
		it("fails with zero amounts", async() => {
			await stProxy.connect(staker1).stake(0).should.be.rejected;
		})
		it("stakes the correct amount", async() => {

			await kwentaToken.connect(staker1).approve(stProxy.address, toUnit(100));
			await kwentaToken.connect(staker2).approve(stProxy.address, toUnit(100));

			await stProxy.connect(staker1).stake(15);

			let bal = await stProxy.stakedBalanceOf(staker1.address);
			assert.equal(bal, 15, "Incorrect amount");

			await stProxy.connect(staker2).stake(50);
			bal = await stProxy.stakedBalanceOf(staker2.address);
			assert.equal(bal, 50, "Incorrect amount");
			
		})
	});

describe("withdraw()", async() => {
		it("fails with zero amounts", async() => {
			await stProxy.connect(staker1).withdraw(0).should.be.rejected;
		})
		it("fails with amounts too large", async() => {
			await stProxy.connect(staker1).withdraw(100).should.be.rejected;	
		})
		it("withdraws the correct amount", async() => {
			await stProxy.connect(staker1).withdraw(15);
			let bal = await stProxy.stakedBalanceOf(staker1.address);
			assert.equal(bal, 0, "Incorrect amount");

			await stProxy.connect(staker2).withdraw(50);
			bal = await stProxy.stakedBalanceOf(staker2.address);
			assert.equal(bal, 0, "Incorrect amount");
		})
	});

describe("feesPaid()", async() => {
		it("initializes updatesTraderScore correctly", async() => {
			let ts1 = await stProxy.feesPaidBy(staker1.address);
			let ts2 = await stProxy.feesPaidBy(staker2.address);
			assert.equal(ts1, 0);
			assert.equal(ts2, 0);
		})

		it("updates updatesTraderScore correctly", async() => {
			await stProxy.connect(staker1).stake(toUnit(5));
			await stProxy.connect(staker2).stake(toUnit(5));

			await stProxy.connect(exchangerProxy).updateTraderScore(staker1.address, toUnit(5));
			await stProxy.connect(exchangerProxy).updateTraderScore(staker2.address, toUnit(4));

			let ts1 = await stProxy.feesPaidBy(staker1.address);
			let expected = toUnit(5);
			
			assertBNEqual(ts1, expected);

			let ts2 = await stProxy.feesPaidBy(staker2.address);
			expected = toUnit(4);

			assertBNEqual(ts2, expected);
		})
	});

describe('lastTimeRewardApplicable()', () => {
		it('should return 0', async () => {
			assert.equal(await stProxy.lastTimeRewardApplicable(), 0);
		});

		describe('when updated', () => {
			it('should equal current timestamp', async () => {
				await stProxy.connect(owner).setRewardNEpochs(toUnit(10), 4);

				const cur = await currentTime();
				const lastTimeReward = await stProxy.lastTimeRewardApplicable();

				assert.equal(cur.toString(), lastTimeReward.toString());
			});
		});
	});

describe('rewardPerToken()', () => {
		it('should return 0', async () => {
			StakingRewards = await deployContract();
			stProxy = await hre.upgrades.deployProxy(StakingRewards,
				[owner.address, kwentaToken.address, 
				kwentaToken.address, rewardsEscrow.address, 3],
				{kind: "uups",
				unsafeAllow: ["external-library-linking"]
				});

			await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);

			assertBNEqual(await stProxy.rewardPerToken(), 0);
		});

		it('should be > 0', async () => {
			const totalToStake = toUnit(10);
			
			await kwentaToken.connect(treasuryDAO).transfer(stProxy.address, toUnit(10));
			await kwentaToken.connect(staker1).approve(stProxy.address, toUnit(10));
			await stProxy.connect(owner).setRewardNEpochs(toUnit(10), 4);

			await stProxy.connect(staker1).stake(totalToStake);
			await fastForward(1);

			const rewardPerToken = await stProxy.rewardPerToken();
			assertBNGreaterThan(rewardPerToken, 0);
		});
	});

describe('earned()', () => {

		it('should not be 0 when staking but not trading', async () => {
			StakingRewards = await deployContract();
			stProxy = await hre.upgrades.deployProxy(StakingRewards,
			[owner.address, kwentaToken.address, 
			kwentaToken.address, rewardsEscrow.address, 3],
			{kind: "uups",
			unsafeAllow: ["external-library-linking"]
			});

			rewardsEscrow.setStakingRewards(stProxy.address);
			await kwentaToken.connect(treasuryDAO).transfer(stProxy.address, toUnit(100));
			await kwentaToken.connect(staker1).approve(stProxy.address, toUnit(100));
			await kwentaToken.connect(staker2).approve(stProxy.address, toUnit(100));

			const totalToStake = toUnit(1);

			await stProxy.connect(staker1).stake(totalToStake);

			const rewardValue = toUnit(5.0);
			
			await stProxy.setRewardNEpochs(rewardValue, 1);

			await fastForward(DAY*7);

			const earned = await stProxy.earned(staker1.address);

			assertBNClose(earned.toString(), toUnit(4), toUnit(0.001));
			});

		it('should be 0 when trading and not staking', async () => {
			StakingRewards = await deployContract();
			stProxy = await hre.upgrades.deployProxy(StakingRewards,
			[owner.address, kwentaToken.address, 
			kwentaToken.address, rewardsEscrow.address, 3],
			{kind: "uups",
			unsafeAllow: ["external-library-linking"]
			});

			await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
			await rewardsEscrow.setStakingRewards(stProxy.address);
			await kwentaToken.connect(treasuryDAO).transfer(stProxy.address, toUnit(100));
			await kwentaToken.connect(staker1).approve(stProxy.address, toUnit(100));
			await kwentaToken.connect(staker2).approve(stProxy.address, toUnit(100));

			await stProxy.connect(exchangerProxy).updateTraderScore(staker1.address, 30);

			const rewardValue = toUnit(5.0);
			
			await stProxy.setRewardNEpochs(rewardValue, 1);

			await fastForward(DAY);

			const earned = await stProxy.earned(staker1.address);

			assertBNEqual(earned, ZERO_BN);
			});

		it('should be 0 when not trading and not staking', async () => {
			StakingRewards = await deployContract();
			stProxy = await hre.upgrades.deployProxy(StakingRewards,
			[owner.address, kwentaToken.address, 
			kwentaToken.address, rewardsEscrow.address, 3],
			{kind: "uups",
			unsafeAllow: ["external-library-linking"]
			});

			await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
			await rewardsEscrow.setStakingRewards(stProxy.address);
			await kwentaToken.connect(treasuryDAO).transfer(stProxy.address, toUnit(100));
			await kwentaToken.connect(staker1).approve(stProxy.address, toUnit(100));
			await kwentaToken.connect(staker2).approve(stProxy.address, toUnit(100));

			const rewardValue = toUnit(5.0);
			
			await stProxy.setRewardNEpochs(rewardValue, 1);

			await fastForward(DAY);

			const earned = await stProxy.earned(staker1.address);

			assertBNEqual(earned, ZERO_BN);
			});

		it('should be > 0 when trading and staking', async () => {
			StakingRewards = await deployContract();
			stProxy = await hre.upgrades.deployProxy(StakingRewards,
			[owner.address, kwentaToken.address, 
			kwentaToken.address, rewardsEscrow.address, 3],
			{kind: "uups",
			unsafeAllow: ["external-library-linking"]
			});

			await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
			await rewardsEscrow.setStakingRewards(stProxy.address);
			await kwentaToken.connect(treasuryDAO).transfer(stProxy.address, toUnit(100));
			await kwentaToken.connect(staker1).approve(stProxy.address, toUnit(100));
			await kwentaToken.connect(staker2).approve(stProxy.address, toUnit(100));

			const totalToStake = toUnit(1);

			await stProxy.connect(staker1).stake(totalToStake);

			await stProxy.connect(exchangerProxy).updateTraderScore(staker1.address, 30);

			const rewardValue = toUnit(5.0);
			
			await stProxy.setRewardNEpochs(rewardValue, 1);

			await fastForward(DAY);

			const earned = await stProxy.earned(staker1.address);

			assert(earned > ZERO_BN);
			});

		});

describe('setRewardNEpochs()', () => {
		it('Reverts if the provided reward is greater than the balance.', async () => {
			const rewardValue = toUnit(100000000);
			await (
				stProxy.setRewardNEpochs(rewardValue, 1)).should.be.rejected;
			});
	});

describe('rewardEpochs()', () => {
		it('Updates the reward Epoch mapping after the week is finished', async () => {
			StakingRewards = await deployContract();
			stProxy = await hre.upgrades.deployProxy(StakingRewards,
			[owner.address, kwentaToken.address, 
			kwentaToken.address, rewardsEscrow.address, 3],
			{kind: "uups",
			unsafeAllow: ["external-library-linking"]
			});
			await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
			await rewardsEscrow.setStakingRewards(stProxy.address);
			await kwentaToken.connect(treasuryDAO).transfer(stProxy.address, toUnit(100));
			await kwentaToken.connect(staker1).approve(stProxy.address, toUnit(100));
			await kwentaToken.connect(staker2).approve(stProxy.address, toUnit(100));

			const totalToStake = toUnit(1);
			const rewardValue = toUnit(5.0);
			var currEpoch = Math.floor(await currentTime() / WEEK) * WEEK;
			var today = Math.floor(await currentTime() / DAY) * DAY;
			if(today - currEpoch >= 4*DAY) {
				currEpoch = currEpoch + WEEK - 3*DAY;
			} else {
				currEpoch = currEpoch - 3*DAY;
			}
			await stProxy.setRewardNEpochs(rewardValue, 1);

			await stProxy.connect(staker1).stake(totalToStake);
			await stProxy.connect(exchangerProxy).updateTraderScore(staker1.address, 30);

			let reward = await stProxy.rewardPerRewardScoreOfEpoch(currEpoch);

			assert.equal(reward, 0);

			await fastForward(DAY*7);

			await stProxy.connect(staker1).stake(totalToStake);
			reward = await stProxy.rewardPerRewardScoreOfEpoch(currEpoch);
			assertBNGreaterThan(reward, 0);

			});
	});

describe('implementation test', () => {
	it('calculates rewards correctly', async() => {

		StakingRewards = await deployContract();
		stProxy = await hre.upgrades.deployProxy(StakingRewards,
			[owner.address, kwentaToken.address, 
			kwentaToken.address, rewardsEscrow.address, 3],
			{kind: "uups",
			unsafeAllow: ["external-library-linking"]
			});
		await stProxy.connect(owner).setExchangerProxy(exchangerProxy.address);
		await rewardsEscrow.setStakingRewards(stProxy.address);
		await kwentaToken.connect(treasuryDAO).transfer(stProxy.address, toUnit(1000));
		await kwentaToken.connect(staker1).approve(stProxy.address, toUnit(100));
		await kwentaToken.connect(staker2).approve(stProxy.address, toUnit(100));

		var currEpoch = Math.floor(await currentTime() / WEEK) * WEEK;
		var today = Math.floor(await currentTime() / DAY) * DAY;
		if(today - currEpoch >= 4*DAY) {
			currEpoch = currEpoch + WEEK - 3*DAY;
		} else {
			currEpoch = currEpoch - 3*DAY;
		}
		let daysTillMonday = currEpoch - today + WEEK;

		await fastForward(daysTillMonday + 1);

		await stProxy.connect(staker1).stake(toUnit(10));
		await stProxy.connect(staker2).stake(toUnit(10));

		await stProxy.setRewardNEpochs(toUnit(300), 3);

		await fastForward(1*DAY);
		
		await stProxy.connect(exchangerProxy).updateTraderScore(staker1.address, toUnit(25));
		await stProxy.connect(exchangerProxy).updateTraderScore(staker2.address, toUnit(50));

		await fastForward(3*DAY);

		await stProxy.connect(staker1).withdraw(toUnit(5));

		await fastForward(3*DAY);

		await stProxy.connect(staker2).withdraw(toUnit(10));

		await fastForward(1*DAY);

		await stProxy.connect(exchangerProxy).updateTraderScore(staker2.address, toUnit(70));

		await fastForward(6*DAY);

		await stProxy.connect(staker2).stake(toUnit(30));
		await stProxy.connect(exchangerProxy).updateTraderScore(staker2.address, toUnit(90));

		await fastForward(4*DAY);

		await stProxy.connect(exchangerProxy).updateTraderScore(staker1.address, toUnit(100));

		await fastForward(3*DAY);

		
		await stProxy.connect(staker1).exit();
		await stProxy.connect(staker2).exit();

		let escrowedSt1 = await stProxy.escrowedBalanceOf(staker1.address);
		let escrowedSt2 = await stProxy.escrowedBalanceOf(staker2.address);

		assertBNClose(escrowedSt1.toString(), toUnit(140.10276354425000), toUnit(0.001));
		assertBNClose(escrowedSt2.toString(), toUnit(139.89723645575000), toUnit(0.001));

		})
	})