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

const assertEventEqual = (actualEventOrTransaction, expectedEvent, expectedArgs) => {
		// If they pass in a whole transaction we need to extract the first log, otherwise we already have what we need
		const event = Array.isArray(actualEventOrTransaction.logs)
			? actualEventOrTransaction.logs[0]
			: actualEventOrTransaction;

		if (!event) {
			assert.fail(new Error('No event was generated from this transaction'));
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
			typeof expected === 'string' ||
			typeof actual === 'string' ||
			typeof expected === 'number' ||
			typeof actual === 'number' ||
			typeof expected === 'boolean' ||
			typeof actual === 'boolean'
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

const mineBlock = () => send({ method: 'evm_mine' });

const FixidityLib = artifacts.require("FixidityLib");
const ExponentLib = artifacts.require("ExponentLib");
const LogarithmLib = artifacts.require("LogarithmLib");
const DecayRateLib = artifacts.require("DecayRateLib");

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

contract('RewardEscrow KWENTA', ([owner, rewardsDistribution, staker1, staker2]) => {
	console.log("Start tests");
	const SECOND = 1000;
	const DAY = 86400;
	const WEEK = 604800;
	const YEAR = 31556926;
	let stakingRewards;
	let stakingToken;
	let rewardsToken;
	let rewardsEscrow;
	let SRsigner;
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
		
		await DecayRateLib.link(exponentLib);
		decayRateLib = await DecayRateLib.new();

		await StakingRewards.link(fixidityLib);
		await StakingRewards.link(decayRateLib);
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

		await hre.network.provider.request({
		  method: "hardhat_impersonateAccount",
		  params: [stakingRewards.address],
		});

		SRsigner = await ethers.getSigner(stakingRewards.address);

		rewardsEscrow.setStakingRewards(stakingRewards.address, {from: owner});

		stakingToken._mint(staker1, toUnit(1000000));
		stakingToken._mint(staker2, toUnit(1000000));
		stakingToken._mint(owner, toUnit(1000000));

		rewardsToken._mint(stakingRewards.address, toUnit(1000000));

		await network.provider.send("hardhat_setBalance", [
		  stakingRewards.address,
		  "0x10000000000000000000000000000000",
		]);

	});

	describe("Deploys correctly", async() => {
		it('Should have a KWENTA token', async() => {
			const kwentaAddress = await rewardsEscrow.kwenta();
			assert.equal(kwentaAddress, stakingToken.address, "Wrong staking token address");
		});

		it('Should set owner', async() => {
			const ownerAddress = await rewardsEscrow.owner();
			assert.equal(ownerAddress, owner, "Wrong owner address");
		});

		it('Should allow owner to set StakingRewards', async() => {
			await rewardsEscrow.setStakingRewards(stakingRewards.address, {from: owner});
			const stakingRewardsAddress = await rewardsEscrow.stakingRewards();
			assert.equal(stakingRewardsAddress, stakingRewards.address, "Wrong stakingRewards address");
		});

	});

	describe("Given there are no Escrow entries", async() => {
		it('then numVestingEntries should return 0', async () => {
			assert.equal(0, await rewardsEscrow.numVestingEntries(staker1));
		});
		it('then getNextVestingEntry should return 0', async () => {
			const nextVestingEntry = await rewardsEscrow.getNextVestingEntry(staker1);
			assert.equal(nextVestingEntry[0], 0);
			assert.equal(nextVestingEntry[1], 0);
		});
		it('then vest should do nothing and not revert', async () => {
			await rewardsEscrow.vest({ from: staker1 });
			assert.equal(0, await rewardsEscrow.totalVestedAccountBalance(staker1));
		});
	});

	describe("Writing vesting schedules()", async() => {
		it('should not create a vesting entry with a zero amount', async () => {
				// Transfer of KWENTA to the escrow must occur before creating an entry
				await stakingToken.transfer(rewardsEscrow.address, toUnit('1'), {
					from: owner,
				});

				await rewardsEscrow.appendVestingEntry(staker1, toUnit('0'), { from: stakingRewards.address }).should.be.rejected;
				
			});

			it('should not create a vesting entry if there is not enough KWENTA in the contracts balance', async () => {
				// Transfer of KWENTA to the escrow must occur before creating an entry
				await stakingToken.transfer(rewardsEscrow.address, toUnit('1'), {
					from: owner,
				});
				await rewardsEscrow.appendVestingEntry(staker1, toUnit('10'), { from: stakingRewards.address }).should.be.rejected;
			});
	});

	describe('Vesting Schedule Reads ', async () => {
			before(async () => {
				// Transfer of KWENTA to the escrow must occur before creating a vestinng entry
				await stakingToken.transfer(rewardsEscrow.address, toUnit('6000'), {
					from: owner,
				});
				stakingRewards.setRewardEscrow(rewardsEscrow.address, {from: owner});
				// Add a few vesting entries as the feepool address
				await rewardsEscrow.appendVestingEntry(staker1, toUnit('1000'), { from: stakingRewards.address });
				await fastForward(WEEK);
				await rewardsEscrow.appendVestingEntry(staker1, toUnit('2000'), { from: stakingRewards.address });
				await fastForward(WEEK);
				await rewardsEscrow.appendVestingEntry(staker1, toUnit('3000'), { from: stakingRewards.address });
			});

			it('should append a vesting entry and increase the contracts balance', async () => {
				const balanceOfRewardEscrow = await stakingToken.balanceOf(rewardsEscrow.address);
				assert.equal(balanceOfRewardEscrow.toString(), toUnit('6002'));
			});

			it('should get an accounts total Vested Account Balance', async () => {
				const balanceOf = await rewardsEscrow.balanceOf(staker1);
				assertBNEqual(balanceOf, toUnit('6000'));
			});

			it('should get an accounts number of vesting entries', async () => {
				const numVestingEntries = await rewardsEscrow.numVestingEntries(staker1);
				assert.equal(numVestingEntries, 3);
			});

			it('should get an accounts vesting schedule entry by index', async () => {
				let vestingScheduleEntry;
				vestingScheduleEntry = await rewardsEscrow.getVestingScheduleEntry(staker1, 0);
				assertBNEqual(vestingScheduleEntry[1], toUnit('1000'));

				vestingScheduleEntry = await rewardsEscrow.getVestingScheduleEntry(staker1, 1);
				assertBNEqual(vestingScheduleEntry[1], toUnit('2000'));

				vestingScheduleEntry = await rewardsEscrow.getVestingScheduleEntry(staker1, 2);
				assertBNEqual(vestingScheduleEntry[1], toUnit('3000'));
			});

			it('should get an accounts vesting time for a vesting entry index', async () => {
				const oneYearAhead = (await currentTime()) + DAY * 365;
				assert.isAtLeast(oneYearAhead, parseInt(await rewardsEscrow.getVestingTime(staker1, 0)));
				assert.isAtLeast(oneYearAhead, parseInt(await rewardsEscrow.getVestingTime(staker1, 1)));
				assert.isAtLeast(oneYearAhead, parseInt(await rewardsEscrow.getVestingTime(staker1, 2)));
			});

			it('should get an accounts vesting quantity for a vesting entry index', async () => {
				assertBNEqual(await rewardsEscrow.getVestingQuantity(staker1, 0), toUnit('1000'));
				assertBNEqual(await rewardsEscrow.getVestingQuantity(staker1, 1), toUnit('2000'));
				assertBNEqual(await rewardsEscrow.getVestingQuantity(staker1, 2), toUnit('3000'));
			});

	});

	describe('Partial Vesting', async () => {
			beforeEach(async () => {

				rewardsEscrow = await RewardsEscrow.new(
				owner,
				stakingToken.address
					);

				rewardsEscrow.setStakingRewards(stakingRewards.address, {from: owner});
				stakingRewards.setRewardEscrow(rewardsEscrow.address, {from: owner});

				// Transfer of KWENTA to the escrow must occur before creating a vestinng entry
				await stakingToken.transfer(rewardsEscrow.address, toUnit('6000'), {
					from: owner,
				});

				// Add a few vesting entries as the feepool address
				await rewardsEscrow.appendVestingEntry(staker1, toUnit('1000'), { from: stakingRewards.address });
				await fastForward(WEEK);
				await rewardsEscrow.appendVestingEntry(staker1, toUnit('2000'), { from: stakingRewards.address });
				await fastForward(WEEK);
				await rewardsEscrow.appendVestingEntry(staker1, toUnit('3000'), { from: stakingRewards.address });

				// fastForward to vest only the first weeks entry
				await fastForward(YEAR - WEEK * 2);

				// Vest
				await rewardsEscrow.vest({ from: staker1 });
			});

			it('should get an accounts next vesting entry index', async () => {
				assertBNEqual(await rewardsEscrow.getNextVestingIndex(staker1), 1);
			});

			it('should get an accounts next vesting entry', async () => {
				const vestingScheduleEntry = await rewardsEscrow.getNextVestingEntry(staker1);
				assertBNEqual(vestingScheduleEntry[1], toUnit('2000'));
			});

			it('should get an accounts next vesting time', async () => {
				const fiveDaysAhead = (await currentTime()) + DAY * 5;
				assert.isAtLeast(parseInt(await rewardsEscrow.getNextVestingTime(staker1)), fiveDaysAhead);
			});

			it('should get an accounts next vesting quantity', async () => {
				const nextVestingQuantity = await rewardsEscrow.getNextVestingQuantity(staker1);
				assertBNEqual(nextVestingQuantity, toUnit('2000'));
			});
	});

	describe('Vesting', async () => {
			beforeEach(async () => {
				stakingToken = await TokenContract.new(NAME, SYMBOL);
				stakingToken._mint(owner, toUnit(1000000));

				rewardsEscrow = await RewardsEscrow.new(
				owner,
				stakingToken.address
					);

				rewardsEscrow.setStakingRewards(stakingRewards.address, {from: owner});
				stakingRewards.setRewardEscrow(rewardsEscrow.address, {from: owner});

				// Transfer of KWENTA to the escrow must occur before creating a vestinng entry
				await stakingToken.transfer(rewardsEscrow.address, toUnit('6000'), {
					from: owner,
				});

				// Add a few vesting entries as the feepool address
				await rewardsEscrow.appendVestingEntry(staker1, toUnit('1000'), { from: stakingRewards.address });
				await fastForward(WEEK);
				await rewardsEscrow.appendVestingEntry(staker1, toUnit('2000'), { from: stakingRewards.address });
				await fastForward(WEEK);
				await rewardsEscrow.appendVestingEntry(staker1, toUnit('3000'), { from: stakingRewards.address });

				// Need to go into the future to vest
				await fastForward(YEAR + WEEK * 3);
			});

			it('should vest and transfer KWENTA from contract to the user', async () => {
				await rewardsEscrow.vest({ from: staker1 });

				// Check user has all their vested KWENTA
				assertBNEqual(await stakingToken.balanceOf(staker1), toUnit('6000'));

				// Check rewardsEscrow does not have any KWENTA
				assertBNEqual(await stakingToken.balanceOf(rewardsEscrow.address), toUnit('0'));
			});

			it('should vest and emit a Vest event', async () => {
				const vestTransaction = await rewardsEscrow.vest({ from: staker1 });

				// Vested(msg.sender, now, total);
				const vestedEvent = vestTransaction.logs.find(log => log.event === 'Vested');
				assertEventEqual(vestedEvent, 'Vested', {
					beneficiary: staker1,
					value: toUnit('6000'),
				});
			});

			it('should vest and update totalEscrowedAccountBalance', async () => {
				// This account should have an escrowedAccountBalance
				let escrowedAccountBalance = await rewardsEscrow.totalEscrowedAccountBalance(staker1);
				assertBNEqual(escrowedAccountBalance, toUnit('6000'));

				// Vest
				await rewardsEscrow.vest({ from: staker1 });

				// This account should not have any amount escrowed
				escrowedAccountBalance = await rewardsEscrow.totalEscrowedAccountBalance(staker1);
				assertBNEqual(escrowedAccountBalance, toUnit('0'));
			});

			it('should vest and update totalVestedAccountBalance', async () => {
				// This account should have zero totalVestedAccountBalance
				let totalVestedAccountBalance = await rewardsEscrow.totalVestedAccountBalance(staker1);
				assertBNEqual(totalVestedAccountBalance, toUnit('0'));

				// Vest
				await rewardsEscrow.vest({ from: staker1 });

				// This account should have vested its whole amount
				totalVestedAccountBalance = await rewardsEscrow.totalVestedAccountBalance(staker1);
				assertBNEqual(totalVestedAccountBalance, toUnit('6000'));
			});

			it('should vest and update totalEscrowedBalance', async () => {
				await rewardsEscrow.vest({ from: staker1 });
				// There should be no Escrowed balance left in the contract
				assertBNEqual(await rewardsEscrow.totalEscrowedBalance(), toUnit('0'));
			});

	});

	describe('Stress Test', () => {

		beforeEach(async () => {
			stakingToken = await TokenContract.new(NAME, SYMBOL);
			stakingToken._mint(owner, toUnit(1000000));

			rewardsEscrow = await RewardsEscrow.new(
			owner,
			stakingToken.address
				);

			rewardsEscrow.setStakingRewards(stakingRewards.address, {from: owner});
			stakingRewards.setRewardEscrow(rewardsEscrow.address, {from: owner});

			// Transfer of KWENTA to the escrow must occur before creating a vestinng entry
			await stakingToken.transfer(rewardsEscrow.address, toUnit('6000'), {
				from: owner,
			});
		});

			it('should not create more than MAX_VESTING_ENTRIES vesting entries', async () => {

				const MAX_VESTING_ENTRIES = 260; // await rewardsEscrow.MAX_VESTING_ENTRIES();

				// Transfer of KWENTA to the escrow must occur before creating an entry
				await stakingToken.transfer(rewardsEscrow.address, toUnit('260'), {
					from: owner,
				});

				// append the MAX_VESTING_ENTRIES to the schedule
				for (let i = 0; i < MAX_VESTING_ENTRIES; i++) {
					await rewardsEscrow.appendVestingEntry(staker1, toUnit('1'), { from: stakingRewards.address });
					await fastForward(WEEK);
				}
				// assert adding 1 more above the MAX_VESTING_ENTRIES fails
				await rewardsEscrow.appendVestingEntry(staker1, toUnit('1'), { from: stakingRewards.address }).should.be.rejected;
			}).timeout(60e3);

			it('should be able to read an accounts schedule of 5 vesting entries', async () => {
				// Transfer of KWENTA to the escrow must occur before creating an entry
				await stakingToken.transfer(rewardsEscrow.address, toUnit('5'), {
					from: owner,
				});

				const VESTING_ENTRIES = 5;

				// Append the VESTING_ENTRIES to the schedule
				for (let i = 0; i < VESTING_ENTRIES; i++) {
					rewardsEscrow.appendVestingEntry(staker1, toUnit('1'), { from: stakingRewards.address });
					await fastForward(SECOND);
				}

				// Get the vesting Schedule
				const accountSchedule = await rewardsEscrow.checkAccountSchedule(staker1);

				// Check accountSchedule entries
				for (let i = 1; i < VESTING_ENTRIES; i += 2) {
					if (accountSchedule[i]) {
						assertBNEqual(accountSchedule[i], toUnit('1'));
					}
					break;
				}
			}).timeout(60e3);

			it('should be able to read the full account schedule 52 week * 5 years vesting entries', async () => {
				// Transfer of KWENTA to the escrow must occur before creating an entry
				await stakingToken.transfer(rewardsEscrow.address, toUnit('260'), {
					from: owner,
				});

				const MAX_VESTING_ENTRIES = 260; // await rewardsEscrow.MAX_VESTING_ENTRIES();

				// Append the MAX_VESTING_ENTRIES to the schedule
				for (let i = 0; i < MAX_VESTING_ENTRIES; i++) {
					rewardsEscrow.appendVestingEntry(staker1, toUnit('1'), { from: stakingRewards.address });
					await fastForward(SECOND);
				}

				// Get the vesting Schedule
				const accountSchedule = await rewardsEscrow.checkAccountSchedule(staker1);

				// Check accountSchedule entries
				for (let i = 1; i < MAX_VESTING_ENTRIES; i += 2) {
					assertBNEqual(accountSchedule[i], toUnit('1'));
				}
			}).timeout(60e3);
	});

});