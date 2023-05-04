const { toBN, toWei } = require("web3-utils");
const hardhat = require("hardhat");
const { ethers } = require("hardhat");
const { smock } = require("@defi-wonderland/smock");
const { wei } = require("@synthetixio/wei");
const BN = require("bn.js");
const { assert, expect } = require("chai");

require("chai")
    .use(require("chai-as-promised"))
    .use(require("chai-bn-equal"))
    .use(smock.matchers)
    .should();

const send = (payload) => {
    if (!payload.jsonrpc) payload.jsonrpc = "2.0";
    if (!payload.id) payload.id = new Date().getTime();

    return new Promise((resolve, reject) => {
        web3.currentProvider.send(payload, (error, result) => {
            if (error) return reject(error);

            return resolve(result);
        });
    });
};

const assertRevert = async (blockOrPromise, reason) => {
    let errorCaught = false;
    try {
        const result =
            typeof blockOrPromise === "function"
                ? blockOrPromise()
                : blockOrPromise;
        await result;
    } catch (error) {
        assert.include(error.message, "revert");
        if (reason) {
            assert.include(error.message, reason);
        }
        errorCaught = true;
    }

    assert.strictEqual(
        errorCaught,
        true,
        "Operation did not revert as expected"
    );
};

const assertEventEqual = (
    actualEventOrTransaction,
    expectedEvent,
    expectedArgs
) => {
    // If they pass in a whole transaction we need to extract the first log, otherwise we already have what we need
    const event = Array.isArray(actualEventOrTransaction.logs)
        ? actualEventOrTransaction.logs[0]
        : actualEventOrTransaction;

    if (!event) {
        assert.fail(new Error("No event was generated from this transaction"));
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
        typeof expected === "string" ||
        typeof actual === "string" ||
        typeof expected === "number" ||
        typeof actual === "number" ||
        typeof expected === "boolean" ||
        typeof actual === "boolean"
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

const mineBlock = () => send({ method: "evm_mine" });

const StakingRewards = artifacts.require("contracts/StakingRewards.sol:StakingRewards");
// const StakingRewardsV2 = artifacts.require("contracts/StakingRewards.sol:StakingRewardsV2");
const TokenContract = artifacts.require("Kwenta");
const RewardsEscrow = artifacts.require("RewardEscrow");
const RewardsEscrowV2 = artifacts.require("RewardEscrowV2");

const NAME = "Kwenta";
const SYMBOL = "KWENTA";
const INITIAL_SUPPLY = hre.ethers.utils.parseUnits("313373");



const toUnit = (amount) => toBN(toWei(amount.toString(), "ether"));

const currentTime = async () => {
    const { timestamp } = await web3.eth.getBlock("latest");
    return timestamp;
};
const fastForward = async (seconds) => {
    // It's handy to be able to be able to pass big numbers in as we can just
    // query them from the contract, then send them back. If not changed to
    // a number, this causes much larger fast forwards than expected without error.
    if (BN.isBN(seconds)) seconds = seconds.toNumber();

    // And same with strings.
    if (typeof seconds === "string") seconds = parseFloat(seconds);

    let params = {
        method: "evm_increaseTime",
        params: [seconds],
    };

    if (hardhat.ovm) {
        params = {
            method: "evm_setNextBlockTimestamp",
            params: [(await currentTime()) + seconds],
        };
    }

    await send(params);

    await mineBlock();
};
const assertBNEqual = (actualBN, expectedBN, context) => {
    assert.strictEqual(actualBN.toString(), expectedBN.toString(), context);
};

const assertBNClose = (actualBN, expectedBN, varianceParam = "10") => {
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

assert.revert = assertRevert;
assert.bnEqual = assertBNEqual;
assert.eventEqual = assertEventEqual;
assert.bnClose = assertBNClose;
assert.bnGreaterThan = assertBNGreaterThan;

contract(
    "RewardEscrowV2 KWENTA",
    ([owner, staker1, staker2, treasuryDAO]) => {
        console.log("Start tests");
        const WEEK = 604800;
        const YEAR = 31556926;
        let stakingRewards;
        let stakingToken;
        let rewardsEscrowV2;
        let kwentaSmock;
        let supplySchedule;

        before(async () => {
            kwentaSmock = await smock.fake("Kwenta");
            supplySchedule = await smock.fake("SupplySchedule");

            // TODO: Remove if unused
            stakingToken = await TokenContract.new(
                NAME,
                SYMBOL,
                INITIAL_SUPPLY,
                owner,
                treasuryDAO
            );

            rewardsEscrowV2 = await RewardsEscrowV2.new(owner, kwentaSmock.address);

            stakingRewards = await StakingRewards.new(
                kwentaSmock.address,
                rewardsEscrowV2.address,
                supplySchedule.address
            );

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [stakingRewards.address],
            });

            SRsigner = await ethers.getSigner(stakingRewards.address);

            await rewardsEscrowV2.setStakingRewards(stakingRewards.address, {
                from: owner,
            });

            await stakingToken.transfer(staker1, toUnit(10000), {
                from: treasuryDAO,
            });
            await stakingToken.transfer(staker2, toUnit(10000), {
                from: treasuryDAO,
            });
            await stakingToken.transfer(owner, toUnit(31000), {
                from: treasuryDAO,
            });

            await network.provider.send("hardhat_setBalance", [
                stakingRewards.address,
                "0x10000000000000000000000000000000",
            ]);
        });

        beforeEach(async () => {
            // Reset RewardsEscrow
            rewardsEscrowV2 = await RewardsEscrowV2.new(owner, kwentaSmock.address);
            await rewardsEscrowV2.setStakingRewards(stakingRewards.address, {
                from: owner,
            });
            await rewardsEscrowV2.setTreasuryDAO(treasuryDAO);
        });

        describe("Deploys correctly", async () => {
            it("Should have a KWENTA token", async () => {
                const kwentaAddress = await rewardsEscrowV2.getKwentaAddress();
                assert.equal(
                    kwentaAddress,
                    kwentaSmock.address,
                    "Wrong staking token address"
                );
            });

            it("Should set owner", async () => {
                const ownerAddress = await rewardsEscrowV2.owner();
                assert.equal(ownerAddress, owner, "Wrong owner address");
            });

            it("Should have set StakingRewards correctly", async () => {
                const stakingRewardsAddress =
                    await rewardsEscrowV2.stakingRewards();
                assert.equal(
                    stakingRewardsAddress,
                    stakingRewards.address,
                    "Wrong stakingRewards address"
                );
            });

            it("Should have set Treasury set correctly", async () => {
                const treasuryDAOAddress =
                    await rewardsEscrowV2.treasuryDAO();
                assert.equal(
                    treasuryDAOAddress,
                    treasuryDAO,
                    "Wrong treasury address"
                );
            });

            it("Should NOT allow owner to set StakingRewards again", async () => {
                await assert.revert(
                    rewardsEscrowV2.setStakingRewards(stakingRewards.address, {
                        from: owner,
                    }),
                    "Staking Rewards already set"
                );
            });

            it("should set nextEntryId to 1", async () => {
                const nextEntryId = await rewardsEscrowV2.nextEntryId();
                assert.equal(nextEntryId, 1);
            });
        });

        describe("Given there are no Escrow entries", async () => {
            it("then numVestingEntries should return 0", async () => {
                assert.equal(0, await rewardsEscrowV2.numVestingEntries(staker1));
            });
            it("then totalEscrowedAccountBalance should return 0", async () => {
                assert.equal(
                    0,
                    await rewardsEscrowV2.totalEscrowedAccountBalance(staker1)
                );
            });
            it("then totalVestedAccountBalance should return 0", async () => {
                assert.equal(
                    0,
                    await rewardsEscrowV2.totalVestedAccountBalance(staker1)
                );
            });
            it("then vest should do nothing and not revert", async () => {
                await rewardsEscrowV2.vest([0], { from: staker1 });
                assert.equal(
                    0,
                    await rewardsEscrowV2.totalVestedAccountBalance(staker1)
                );
            });
        });

        describe("Writing vesting schedules()", async () => {
            it("should not create a vesting entry with a zero amount", async () => {
                // Transfer of KWENTA to the escrow must occur before creating an entry
                await stakingToken.transfer(
                    rewardsEscrowV2.address,
                    toUnit("1"),
                    {
                        from: owner,
                    }
                );

                await rewardsEscrowV2.appendVestingEntry(staker1, toUnit("0"), {
                    from: stakingRewards.address,
                }).should.be.rejected;
            });

            it("should not create a vesting entry if there is not enough KWENTA in the contracts balance", async () => {
                // Transfer of KWENTA to the escrow must occur before creating an entry
                await stakingToken.transfer(
                    rewardsEscrowV2.address,
                    toUnit("1"),
                    {
                        from: owner,
                    }
                );
                await rewardsEscrowV2.appendVestingEntry(staker1, toUnit("10"), {
                    from: stakingRewards.address,
                }).should.be.rejected;
            });
        });

        describe("Creating vesting Schedule", async () => {
            describe("When appending vesting entry via feePool", async () => {
                let duration = YEAR;
                it("should revert appending a vesting entry from staker1", async () => {
                    // Transfer of KWENTA to the escrow must occur before creating an entry
                    kwentaSmock.balanceOf.returns(wei(10).toBN());

                    await assert.revert(
                        rewardsEscrowV2.appendVestingEntry(
                            staker1,
                            toUnit("1"),
                            duration,
                            {
                                from: staker1,
                            }
                        ),
                        "Only the StakingRewards can perform this action"
                    );
                });
                it("should revert appending a vesting entry with a zero amount", async () => {
                    // Transfer of KWENTA to the escrow must occur before creating an entry
                    kwentaSmock.balanceOf.returns(wei(1).toBN());

                    await assert.revert(
                        rewardsEscrowV2.appendVestingEntry(
                            staker1,
                            toUnit("0"),
                            duration,
                            {
                                from: stakingRewards.address,
                            }
                        ),
                        "Quantity cannot be zero"
                    );
                });
                it("should revert appending a vesting entry if there is not enough KWENTA in the contracts balance", async () => {
                    // Transfer of KWENTA to the escrow must occur before creating an entry
                    kwentaSmock.balanceOf.returns(wei(1).toBN());

                    await assert.revert(
                        rewardsEscrowV2.appendVestingEntry(
                            staker1,
                            toUnit("10"),
                            duration,
                            {
                                from: stakingRewards.address,
                            }
                        ),
                        "Must be enough balance in the contract to provide for the vesting entry"
                    );
                });
                it("should revert appending a vesting entry if the duration is 0", async () => {
                    duration = 0;

                    // Transfer of KWENTA to the escrow must occur before creating an entry
                    kwentaSmock.balanceOf.returns(wei(10).toBN());

                    await assert.revert(
                        rewardsEscrowV2.appendVestingEntry(
                            staker1,
                            toUnit("10"),
                            duration,
                            {
                                from: stakingRewards.address,
                            }
                        ),
                        "Cannot escrow with 0 duration OR above max_duration"
                    );
                });
                it("should revert appending a vesting entry if the duration is > max_duration", async () => {
                    duration = (await rewardsEscrowV2.MAX_DURATION()).add(
                        toUnit(1)
                    );

                    // Transfer of KWENTA to the escrow must occur before creating an entry
                    kwentaSmock.balanceOf.returns(wei(10).toBN());

                    await assert.revert(
                        rewardsEscrowV2.appendVestingEntry(
                            staker1,
                            toUnit("10"),
                            duration,
                            {
                                from: stakingRewards.address,
                            }
                        ),
                        "Cannot escrow with 0 duration OR above max_duration"
                    );
                });

                describe("When successfully appending new escrow entry for account 1 with 10 KWENTA", () => {
                    let entryID, nextEntryIdAfter, now, escrowAmount;
                    beforeEach(async () => {
                        duration = 1 * YEAR;

                        entryID = await rewardsEscrowV2.nextEntryId();

                        now = await currentTime();

                        escrowAmount = toUnit("10");

                        // Transfer of KWENTA to the escrow must occur before creating an entry
                        kwentaSmock.balanceOf.returns(wei(10).toBN());

                        // Append vesting entry
                        await rewardsEscrowV2.appendVestingEntry(
                            staker1,
                            escrowAmount,
                            duration,
                            {
                                from: stakingRewards.address,
                            }
                        );

                        nextEntryIdAfter = await rewardsEscrowV2.nextEntryId();
                    });
                    it("Should return the vesting entry for account 1 and entryID", async () => {
                        const vestingEntry =
                            await rewardsEscrowV2.getVestingEntry(
                                staker1,
                                entryID
                            );

                        // endTime is 1 year after
                        assert.isTrue(vestingEntry.endTime.gte(now + duration));

                        // escrowAmount is 10
                        assert.bnEqual(vestingEntry.escrowAmount, escrowAmount);
                    });
                    it("Should increment the nextEntryID", async () => {
                        assert.bnEqual(
                            nextEntryIdAfter,
                            entryID.add(new BN(1))
                        );
                    });
                    it("Account 1 should have balance of 10 KWENTA", async () => {
                        assert.bnEqual(
                            await rewardsEscrowV2.balanceOf(staker1),
                            escrowAmount
                        );
                    });
                    it("totalEscrowedBalance of the contract should be 10 KWENTA", async () => {
                        assert.bnEqual(
                            await rewardsEscrowV2.totalEscrowedBalance(),
                            escrowAmount
                        );
                    });
                    it("staker1 should have totalVested Account Balance of 0", async () => {
                        assert.bnEqual(
                            await rewardsEscrowV2.totalVestedAccountBalance(
                                staker1
                            ),
                            new BN(0)
                        );
                    });
                    it("staker1 numVestingEntries is 1", async () => {
                        assert.bnEqual(
                            await rewardsEscrowV2.numVestingEntries(staker1),
                            new BN(1)
                        );
                    });
                    describe("When 6 months has passed", () => {
                        let timeElapsed;
                        beforeEach(async () => {
                            timeElapsed = YEAR / 2;
                            await fastForward(timeElapsed);
                        });
                        // claimable = escrowedAmount - 90% escrowedAmount * vestingProgress
                        it("then the vesting entry has 5.5 kwenta claimable", async () => {
                            const claimable =
                                await rewardsEscrowV2.getVestingEntryClaimable(
                                    staker1,
                                    entryID
                                );
                            assert.bnEqual(claimable["0"], wei(5.5).toBN());
                        });
                    });
                    describe("When one year has passed after the vesting end time", () => {
                        let vestingEntry;
                        beforeEach(async () => {
                            await fastForward(YEAR + 1);
                            vestingEntry = await rewardsEscrowV2.getVestingEntry(
                                staker1,
                                entryID
                            );
                        });
                        it("then the vesting entry is fully claimable", async () => {
                            const claimable =
                                await rewardsEscrowV2.getVestingEntryClaimable(
                                    staker1,
                                    entryID
                                );
                            assert.bnEqual(
                                claimable["0"],
                                vestingEntry.escrowAmount
                            );
                        });
                    });
                });
            });
        });

        describe("Creating a new escrow entry by approval", async () => {
            let duration, entryID;
            beforeEach(async () => {
                // approve rewardEscrow to spend KWENTA
                kwentaSmock.allowance.returns(wei(10).toBN());

                // stub transferFrom
                kwentaSmock.transferFrom.returns(true);

                // stub balanceOf
                kwentaSmock.balanceOf.returns(wei(10).toBN());

                duration = 1 * YEAR;
            });
            it("should revert if escrow duration is greater than max_duration", async () => {
                const maxDuration = await rewardsEscrowV2.MAX_DURATION();
                await assert.revert(
                    rewardsEscrowV2.createEscrowEntry(
                        staker1,
                        new BN(1000),
                        maxDuration + 10,
                        {
                            from: owner,
                        }
                    ),
                    "Cannot escrow with 0 duration OR above max_duration"
                );
            });
            it("should revert if escrow duration is 0", async () => {
                await assert.revert(
                    rewardsEscrowV2.createEscrowEntry(staker1, new BN(1000), 0, {
                        from: owner,
                    }),
                    "Cannot escrow with 0 duration OR above max_duration"
                );
            });
            it("should revert when beneficiary is address zero", async () => {
                await assert.revert(
                    rewardsEscrowV2.createEscrowEntry(
                        ethers.constants.AddressZero,
                        toUnit("1"),
                        duration
                    ),
                    "Cannot create escrow with address(0)"
                );
            });
            it("should revert when msg.sender has no approval to spend", async () => {
                kwentaSmock.transferFrom.returns(false);
                await assert.revert(
                    rewardsEscrowV2.createEscrowEntry(
                        staker1,
                        toUnit("10"),
                        duration,
                        {
                            from: staker1,
                        }
                    ),
                    "Token transfer failed"
                );
            });
            describe("when successfully creating a new escrow entry for staker1", () => {
                let vestingEntry, escrowAmount, now, nextEntryIdAfter;
                beforeEach(async () => {
                    now = currentTime();
                    escrowAmount = toUnit("10");

                    const expectedEntryID = await rewardsEscrowV2.nextEntryId();

                    await rewardsEscrowV2.createEscrowEntry(
                        staker1,
                        escrowAmount,
                        duration,
                        {
                            from: owner,
                        }
                    );

                    // retrieve the vesting entryID from account 1's list of account vesting entrys
                    entryID = (await rewardsEscrowV2.getAccountVestingEntryIDs(
                        staker1,
                        0,
                        1
                    ))[0];

                    assert.bnEqual(entryID, expectedEntryID);

                    nextEntryIdAfter = await rewardsEscrowV2.nextEntryId();
                });
                it("Should have created a new vesting entry for account 1", async () => {
                    vestingEntry = await rewardsEscrowV2.getVestingEntry(
                        staker1,
                        entryID
                    );

                    // endTime is 1 year after
                    assert.isTrue(vestingEntry.endTime.gte(now + duration));

                    // escrowAmount is 10
                    assert.bnEqual(vestingEntry.escrowAmount, escrowAmount);
                });
                it("Should increment the nextEntryID", async () => {
                    assert.bnEqual(nextEntryIdAfter, entryID.add(new BN(1)));
                });
                it("totalEscrowedBalance of the contract should be 10 KWENTA", async () => {
                    assert.bnEqual(
                        await rewardsEscrowV2.totalEscrowedBalance(),
                        escrowAmount
                    );
                });
                it("Account1 should have balance of 10 KWENTA", async () => {
                    assert.bnEqual(
                        await rewardsEscrowV2.balanceOf(staker1),
                        escrowAmount
                    );
                });
                it("Account1 should have totalVested Account Balance of 0", async () => {
                    assert.bnEqual(
                        await rewardsEscrowV2.totalVestedAccountBalance(staker1),
                        new BN(0)
                    );
                });
                it("Account1 numVestingEntries is 1", async () => {
                    assert.bnEqual(
                        await rewardsEscrowV2.numVestingEntries(staker1),
                        new BN(1)
                    );
                });
            });
        });

        describe("Read Vesting Schedule", () => {
            const duration = 1 * YEAR;
            const escrowAmounts = [toUnit("200"), toUnit("300"), toUnit("500")];
            let entryID1, entryID2, entryID3;
            beforeEach(async () => {
                // Transfer of KWENTA to the escrow must occur before creating a vestinng entry
                kwentaSmock.balanceOf.returns(wei(1000).toBN());

                // Add a few vesting entries as the feepool address
                entryID1 = await rewardsEscrowV2.nextEntryId();
                await rewardsEscrowV2.appendVestingEntry(
                    staker1,
                    escrowAmounts[0],
                    duration,
                    {
                        from: stakingRewards.address,
                    }
                );
                await fastForward(WEEK);
                entryID2 = await rewardsEscrowV2.nextEntryId();
                await rewardsEscrowV2.appendVestingEntry(
                    staker1,
                    escrowAmounts[1],
                    duration,
                    {
                        from: stakingRewards.address,
                    }
                );
                await fastForward(WEEK);
                entryID3 = await rewardsEscrowV2.nextEntryId();
                await rewardsEscrowV2.appendVestingEntry(
                    staker1,
                    escrowAmounts[2],
                    duration,
                    {
                        from: stakingRewards.address,
                    }
                );

                // ensure Issuer.debtBalanceOf returns 0
                //mocks['Issuer'].smocked.debtBalanceOf.will.return.with('0');
            });
            it("should return the vesting schedules for staker1", async () => {
                const entries = await rewardsEscrowV2.getVestingSchedules(
                    staker1,
                    0,
                    3
                );
                // should be 3 entries
                assert.equal(entries.length, 3);

                // escrowAmounts should match for the entries in order
                entries.forEach((entry, i) => {
                    assert.bnEqual(entry.escrowAmount, escrowAmounts[i]);
                    assert.bnEqual(entry.entryID, i + 1);
                });
            });
            it("should return the list of vesting entryIDs for staker1", async () => {
                const vestingEntryIDs =
                    await rewardsEscrowV2.getAccountVestingEntryIDs(
                        staker1,
                        0,
                        3
                    );

                // should be 3 entries
                assert.equal(vestingEntryIDs.length, 3);

                assert.bnEqual(vestingEntryIDs[0], entryID1);
                assert.bnEqual(vestingEntryIDs[1], entryID2);
                assert.bnEqual(vestingEntryIDs[2], entryID3);
            });
        });

        describe("Vesting", () => {
            let mockedKwenta;

            beforeEach(async () => {
                mockedKwenta = await TokenContract.new(
                    NAME,
                    SYMBOL,
                    INITIAL_SUPPLY,
                    owner,
                    treasuryDAO
                );

                rewardsEscrowV2 = await RewardsEscrow.new(
                    owner,
                    mockedKwenta.address
                );
                await rewardsEscrowV2.setStakingRewards(stakingRewards.address, {
                    from: owner,
                });
                await rewardsEscrowV2.setTreasuryDAO(treasuryDAO);

                // Transfer from treasury to owner
                await mockedKwenta.transfer(owner, toUnit("1000"), {
                    from: treasuryDAO,
                });

                // Transfer of KWENTA to the escrow must occur before creating a vesting entry
                await mockedKwenta.transfer(
                    rewardsEscrowV2.address,
                    toUnit("1000"),
                    {
                        from: owner,
                    }
                );
            });
            describe("Vesting of vesting entry after 6 months (before escrow ends)", () => {
                const duration = 1 * YEAR;

                let escrowAmount, timeElapsed, entryID, claimableKWENTA;
                beforeEach(async () => {
                    escrowAmount = toUnit("1000");
                    timeElapsed = YEAR / 2;

                    entryID = await rewardsEscrowV2.nextEntryId();

                    // Add a few vesting entries as the feepool address
                    await rewardsEscrowV2.appendVestingEntry(
                        staker1,
                        escrowAmount,
                        duration,
                        {
                            from: stakingRewards.address,
                        }
                    );

                    // Need to go into the future to vest
                    await fastForward(timeElapsed);
                });

                it("should vest 0 amount if entryID does not exist for user", async () => {
                    const randomID = 200;
                    await rewardsEscrowV2.vest([randomID], { from: staker1 });

                    // Check user has no vested KWENTA
                    assert.bnEqual(
                        await mockedKwenta.balanceOf(staker1),
                        toUnit("0")
                    );

                    // Check rewardEscrow does not have any KWENTA
                    assert.bnEqual(
                        await mockedKwenta.balanceOf(rewardsEscrowV2.address),
                        escrowAmount
                    );

                    // Check total escrowedAccountBalance is unchanged
                    const escrowedAccountBalance =
                        await rewardsEscrowV2.totalEscrowedAccountBalance(
                            staker1
                        );
                    assert.bnEqual(escrowedAccountBalance, escrowAmount);

                    // Account should have 0 vested account balance
                    const totalVestedAccountBalance =
                        await rewardsEscrowV2.totalVestedAccountBalance(staker1);
                    assert.bnEqual(totalVestedAccountBalance, toUnit("0"));
                });

                it("should have 55% of the vesting entry claimable", async () => {
                    const expectedAmount = wei(escrowAmount)
                        .mul(0.55)
                        .toString(0);
                    assert.bnEqual(
                        (
                            await rewardsEscrowV2.getVestingEntryClaimable(
                                staker1,
                                entryID
                            )
                        )["0"],
                        expectedAmount
                    );
                });

                it("should vest and transfer 0 KWENTA from contract to the user", async () => {
                    claimableKWENTA =
                        await rewardsEscrowV2.getVestingEntryClaimable(
                            staker1,
                            entryID
                        );

                    assert.bnEqual(
                        claimableKWENTA["0"],
                        wei(escrowAmount).mul(0.55).toString(0)
                    );

                    const treasuryPreBalance = await mockedKwenta.balanceOf(
                        treasuryDAO
                    );

                    // Vest
                    await rewardsEscrowV2.vest([entryID], { from: staker1 });

                    const treasuryPostBalance = await mockedKwenta.balanceOf(
                        treasuryDAO
                    );

                    // Check user has more than 55% vested KWENTA
                    assert.bnClose(
                        await mockedKwenta.balanceOf(staker1),
                        wei(escrowAmount).mul(0.55).toString(0),
                        wei(1).toString()
                    );

                    // Check treasury has 40% vested KWENTA
                    assert.bnClose(
                        treasuryPostBalance.sub(treasuryPreBalance),
                        wei(escrowAmount).mul(0.45).toString(0),
                        wei(1).toString()
                    );

                    // Check rewardEscrow contract has same amount of KWENTA
                    assert.bnEqual(
                        await mockedKwenta.balanceOf(rewardsEscrowV2.address),
                        0
                    );

                    const vestingEntryAfter =
                        await rewardsEscrowV2.getVestingEntry(staker1, entryID);

                    assert.bnEqual(
                        await rewardsEscrowV2.totalEscrowedBalance(),
                        0
                    );

                    assert.bnEqual(
                        await rewardsEscrowV2.totalEscrowedAccountBalance(
                            staker1
                        ),
                        0
                    );

                    assert.bnEqual(
                        await rewardsEscrowV2.totalVestedAccountBalance(staker1),
                        await mockedKwenta.balanceOf(staker1)
                    );

                    assert.bnEqual(vestingEntryAfter.escrowAmount, 0);
                });
            });

            describe("When vesting after escrow ended", () => {
                let escrowAmount, duration, entryID;
                beforeEach(async () => {
                    duration = 1 * YEAR;
                    escrowAmount = toUnit("1000");

                    entryID = await rewardsEscrowV2.nextEntryId();

                    // Add a few vesting entries as the feepool address
                    await rewardsEscrowV2.appendVestingEntry(
                        staker1,
                        escrowAmount,
                        duration,
                        {
                            from: stakingRewards.address,
                        }
                    );

                    // fast forward to after escrow.endTime
                    fastForward(duration + 10);
                });
                it("should vest and transfer all the $KWENTA to the user", async () => {
                    await rewardsEscrowV2.vest([entryID], {
                        from: staker1,
                    });

                    // Check user has all their vested KWENTA
                    assert.bnEqual(
                        await mockedKwenta.balanceOf(staker1),
                        escrowAmount
                    );

                    // Check rewardEscrow does not have any KWENTA
                    assert.bnEqual(
                        await mockedKwenta.balanceOf(rewardsEscrowV2.address),
                        toUnit("0")
                    );
                });

                it("should vest and emit a Vest event", async () => {
                    const vestTransaction = await rewardsEscrowV2.vest(
                        [entryID],
                        {
                            from: staker1,
                        }
                    );

                    // Vested(msg.sender, now, total);
                    const vestedEvent = vestTransaction.logs.find(
                        (log) => log.event === "Vested"
                    );
                    assert.eventEqual(vestedEvent, "Vested", {
                        beneficiary: staker1,
                        value: escrowAmount,
                    });
                });

                it("should vest and update totalEscrowedAccountBalance", async () => {
                    // This account should have an escrowedAccountBalance
                    let escrowedAccountBalance =
                        await rewardsEscrowV2.totalEscrowedAccountBalance(
                            staker1
                        );
                    assert.bnEqual(escrowedAccountBalance, escrowAmount);

                    // Vest
                    await rewardsEscrowV2.vest([entryID], {
                        from: staker1,
                    });

                    // This account should not have any amount escrowed
                    escrowedAccountBalance =
                        await rewardsEscrowV2.totalEscrowedAccountBalance(
                            staker1
                        );
                    assert.bnEqual(escrowedAccountBalance, toUnit("0"));
                });

                it("should vest and update totalVestedAccountBalance", async () => {
                    // This account should have zero totalVestedAccountBalance
                    let totalVestedAccountBalance =
                        await rewardsEscrowV2.totalVestedAccountBalance(staker1);
                    assert.bnEqual(totalVestedAccountBalance, toUnit("0"));

                    // Vest
                    await rewardsEscrowV2.vest([entryID], {
                        from: staker1,
                    });

                    // This account should have vested its whole amount
                    totalVestedAccountBalance =
                        await rewardsEscrowV2.totalVestedAccountBalance(staker1);
                    assert.bnEqual(totalVestedAccountBalance, escrowAmount);
                });

                it("should vest and update totalEscrowedBalance", async () => {
                    await rewardsEscrowV2.vest([entryID], {
                        from: staker1,
                    });

                    // There should be no Escrowed balance left in the contract
                    assert.bnEqual(
                        await rewardsEscrowV2.totalEscrowedBalance(),
                        toUnit("0")
                    );
                });
                it("should vest and update entryID.escrowAmount to 0", async () => {
                    await rewardsEscrowV2.vest([entryID], {
                        from: staker1,
                    });

                    // There should be no escrowedAmount on entry
                    const entry = await rewardsEscrowV2.getVestingEntry(
                        staker1,
                        entryID
                    );
                    assert.bnEqual(entry.escrowAmount, toUnit("0"));
                });
            });

            describe("Vesting multiple vesting entries", () => {
                const duration = 1 * YEAR;
                let escrowAmount1,
                    escrowAmount2,
                    escrowAmount3,
                    entryID1,
                    entryID2,
                    entryID3;

                beforeEach(async () => {
                    escrowAmount1 = toUnit("200");
                    escrowAmount2 = toUnit("300");
                    escrowAmount3 = toUnit("500");

                    // Add a few vesting entries as the feepool address
                    entryID1 = await rewardsEscrowV2.nextEntryId();
                    await rewardsEscrowV2.appendVestingEntry(
                        staker1,
                        escrowAmount1,
                        duration,
                        {
                            from: stakingRewards.address,
                        }
                    );
                    await fastForward(WEEK);

                    entryID2 = await rewardsEscrowV2.nextEntryId();
                    await rewardsEscrowV2.appendVestingEntry(
                        staker1,
                        escrowAmount2,
                        duration,
                        {
                            from: stakingRewards.address,
                        }
                    );
                    await fastForward(WEEK);

                    entryID3 = await rewardsEscrowV2.nextEntryId();
                    await rewardsEscrowV2.appendVestingEntry(
                        staker1,
                        escrowAmount3,
                        duration,
                        {
                            from: stakingRewards.address,
                        }
                    );

                    // Need to go into the future to vest all entries
                    await fastForward(duration + WEEK * 3);
                });

                it("should have three vesting entries for the user", async () => {
                    const numOfEntries = await rewardsEscrowV2.numVestingEntries(
                        staker1
                    );
                    assert.bnEqual(numOfEntries, new BN(3));
                });

                describe("When another user (account 1) vests all their entries", () => {
                    it("should vest all entries and transfer $KWENTA to the user", async () => {
                        await rewardsEscrowV2.vest(
                            [entryID1, entryID2, entryID3],
                            {
                                from: staker2,
                            }
                        );

                        // Check staker1 has no KWENTA in their balance
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(staker1),
                            toUnit("0")
                        );

                        // Check staker2 has no KWENTA in their balance
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(staker2),
                            toUnit("0")
                        );

                        // Check rewardEscrow has all the KWENTA
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(rewardsEscrowV2.address),
                            toUnit("1000")
                        );
                    });
                });

                it("should vest all entries and transfer $KWENTA from contract to the user", async () => {
                    await rewardsEscrowV2.vest([entryID1, entryID2, entryID3], {
                        from: staker1,
                    });

                    // Check user has all their vested KWENTA
                    assert.bnEqual(
                        await mockedKwenta.balanceOf(staker1),
                        toUnit("1000")
                    );

                    // Check rewardEscrow does not have any KWENTA
                    assert.bnEqual(
                        await mockedKwenta.balanceOf(rewardsEscrowV2.address),
                        toUnit("0")
                    );
                });

                it("should vest and emit a Vest event", async () => {
                    const vestTx = await rewardsEscrowV2.vest(
                        [entryID1, entryID2, entryID3],
                        {
                            from: staker1,
                        }
                    );

                    // Vested(msg.sender, now, total);
                    const vestedEvent = vestTx.logs.find(
                        (log) => log.event === "Vested"
                    );
                    assert.eventEqual(vestedEvent, "Vested", {
                        beneficiary: staker1,
                        value: toUnit("1000"),
                    });
                });

                it("should vest and update totalEscrowedAccountBalance", async () => {
                    // This account should have an escrowedAccountBalance
                    let escrowedAccountBalance =
                        await rewardsEscrowV2.totalEscrowedAccountBalance(
                            staker1
                        );
                    assert.bnEqual(escrowedAccountBalance, toUnit("1000"));

                    // Vest
                    await rewardsEscrowV2.vest([entryID1, entryID2, entryID3], {
                        from: staker1,
                    });

                    // This account should not have any amount escrowed
                    escrowedAccountBalance =
                        await rewardsEscrowV2.totalEscrowedAccountBalance(
                            staker1
                        );
                    assert.bnEqual(escrowedAccountBalance, toUnit("0"));
                });

                it("should vest and update totalVestedAccountBalance", async () => {
                    // This account should have zero totalVestedAccountBalance
                    let totalVestedAccountBalance =
                        await rewardsEscrowV2.totalVestedAccountBalance(staker1);
                    assert.bnEqual(totalVestedAccountBalance, toUnit("0"));

                    // Vest
                    await rewardsEscrowV2.vest([entryID1, entryID2, entryID3], {
                        from: staker1,
                    });

                    // This account should have vested its whole amount
                    totalVestedAccountBalance =
                        await rewardsEscrowV2.totalVestedAccountBalance(staker1);
                    assert.bnEqual(totalVestedAccountBalance, toUnit("1000"));
                });

                it("should vest and update totalEscrowedBalance", async () => {
                    await rewardsEscrowV2.vest([entryID1, entryID2, entryID3], {
                        from: staker1,
                    });
                    // There should be no Escrowed balance left in the contract
                    assert.bnEqual(
                        await rewardsEscrowV2.totalEscrowedBalance(),
                        toUnit("0")
                    );
                });

                it("should vest all entries and ignore duplicate attempts to vest same entries again", async () => {
                    // Vest attempt 1
                    await rewardsEscrowV2.vest([entryID1, entryID2, entryID3], {
                        from: staker1,
                    });

                    // Check user has all their vested KWENTA
                    assert.bnEqual(
                        await mockedKwenta.balanceOf(staker1),
                        toUnit("1000")
                    );

                    // Check rewardEscrow does not have any KWENTA
                    assert.bnEqual(
                        await mockedKwenta.balanceOf(rewardsEscrowV2.address),
                        toUnit("0")
                    );

                    // Vest attempt 2
                    await rewardsEscrowV2.vest([entryID1, entryID2, entryID3], {
                        from: staker1,
                    });

                    // Check user has same amount of KWENTA
                    assert.bnEqual(
                        await mockedKwenta.balanceOf(staker1),
                        toUnit("1000")
                    );

                    // Check rewardEscrow does not have any KWENTA
                    assert.bnEqual(
                        await mockedKwenta.balanceOf(rewardsEscrowV2.address),
                        toUnit("0")
                    );
                });
            });

            describe("Vesting multiple vesting entries with different duration / end time", () => {
                const duration = 1 * YEAR;
                let escrowAmount1,
                    escrowAmount2,
                    escrowAmount3,
                    entryID1,
                    entryID2,
                    entryID3;

                beforeEach(async () => {
                    escrowAmount1 = toUnit("200");
                    escrowAmount2 = toUnit("300");
                    escrowAmount3 = toUnit("500");

                    // Add a few vesting entries as the feepool address
                    entryID1 = await rewardsEscrowV2.nextEntryId();
                    await rewardsEscrowV2.appendVestingEntry(
                        staker1,
                        escrowAmount1,
                        duration,
                        {
                            from: stakingRewards.address,
                        }
                    );
                    await fastForward(WEEK);

                    entryID2 = await rewardsEscrowV2.nextEntryId();
                    await rewardsEscrowV2.appendVestingEntry(
                        staker1,
                        escrowAmount2,
                        duration,
                        {
                            from: stakingRewards.address,
                        }
                    );
                    await fastForward(WEEK);

                    // EntryID3 has a longer duration than other entries
                    const twoYears = 2 * 52 * WEEK;
                    entryID3 = await rewardsEscrowV2.nextEntryId();
                    await rewardsEscrowV2.appendVestingEntry(
                        staker1,
                        escrowAmount3,
                        twoYears,
                        {
                            from: stakingRewards.address,
                        }
                    );
                });

                it("should have three vesting entries for the user", async () => {
                    const numOfEntries = await rewardsEscrowV2.numVestingEntries(
                        staker1
                    );
                    assert.bnEqual(numOfEntries, new BN(3));
                });

                describe("When another user (account 1) vests all their entries", () => {
                    it("should vest all entries and transfer $KWENTA to the user", async () => {
                        await rewardsEscrowV2.vest(
                            [entryID1, entryID2, entryID3],
                            {
                                from: staker2,
                            }
                        );

                        // Check staker1 has no KWENTA in their balance
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(staker1),
                            toUnit("0")
                        );

                        // Check staker2 has no KWENTA in their balance
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(staker2),
                            toUnit("0")
                        );

                        // Check rewardEscrow has all the KWENTA
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(rewardsEscrowV2.address),
                            toUnit("1000")
                        );
                    });
                });

                describe("vest only the first two entries", () => {
                    beforeEach(async () => {
                        // Need to go into the future to vest first two entries
                        await fastForward(duration);
                    });

                    it("should vest only first 2 entries and transfer $KWENTA from contract to the user", async () => {
                        await rewardsEscrowV2.vest([entryID1, entryID2], {
                            from: staker1,
                        });

                        // Check user has entry1 + entry2 amount
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(staker1),
                            escrowAmount1.add(escrowAmount2)
                        );

                        // Check rewardEscrow has remaining entry3 amount
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(rewardsEscrowV2.address),
                            escrowAmount3
                        );
                    });

                    it("should vest and emit a Vest event", async () => {
                        const vestTx = await rewardsEscrowV2.vest(
                            [entryID1, entryID2],
                            {
                                from: staker1,
                            }
                        );

                        // Vested(msg.sender, now, total);
                        const vestedEvent = vestTx.logs.find(
                            (log) => log.event === "Vested"
                        );
                        assert.eventEqual(vestedEvent, "Vested", {
                            beneficiary: staker1,
                            value: toUnit("500"),
                        });
                    });

                    it("should vest and update totalEscrowedAccountBalance", async () => {
                        // This account should have an escrowedAccountBalance
                        let escrowedAccountBalance =
                            await rewardsEscrowV2.totalEscrowedAccountBalance(
                                staker1
                            );
                        assert.bnEqual(escrowedAccountBalance, toUnit("1000"));

                        // Vest
                        await rewardsEscrowV2.vest([entryID1, entryID2], {
                            from: staker1,
                        });

                        // This account should have any 500 KWENTA escrowed
                        escrowedAccountBalance =
                            await rewardsEscrowV2.totalEscrowedAccountBalance(
                                staker1
                            );
                        assert.bnEqual(escrowedAccountBalance, escrowAmount3);
                    });

                    it("should vest and update totalVestedAccountBalance", async () => {
                        // This account should have zero totalVestedAccountBalance before
                        let totalVestedAccountBalance =
                            await rewardsEscrowV2.totalVestedAccountBalance(
                                staker1
                            );
                        assert.bnEqual(totalVestedAccountBalance, toUnit("0"));

                        // Vest
                        await rewardsEscrowV2.vest([entryID1, entryID2], {
                            from: staker1,
                        });

                        // This account should have vested entry 1 and entry 2 amounts
                        totalVestedAccountBalance =
                            await rewardsEscrowV2.totalVestedAccountBalance(
                                staker1
                            );
                        assert.bnEqual(
                            totalVestedAccountBalance,
                            escrowAmount1.add(escrowAmount2)
                        );
                    });

                    it("should vest and update totalEscrowedBalance", async () => {
                        await rewardsEscrowV2.vest([entryID1, entryID2], {
                            from: staker1,
                        });
                        // There should be escrowAmount3's Escrowed balance left in the contract
                        assert.bnEqual(
                            await rewardsEscrowV2.totalEscrowedBalance(),
                            escrowAmount3
                        );
                    });

                    it("should vest entryID1 and entryID2 and ignore duplicate attempts to vest same entries again", async () => {
                        // Vest attempt 1
                        await rewardsEscrowV2.vest([entryID1, entryID2], {
                            from: staker1,
                        });

                        // Check user have vested escrowAmount1 and escrowAmount2 KWENTA
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(staker1),
                            escrowAmount1.add(escrowAmount2)
                        );

                        // Check rewardEscrow does has escrowAmount3 KWENTA
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(rewardsEscrowV2.address),
                            escrowAmount3
                        );

                        // Vest attempt 2
                        await rewardsEscrowV2.vest([entryID1, entryID2], {
                            from: staker1,
                        });

                        // Check user has same amount of KWENTA
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(staker1),
                            escrowAmount1.add(escrowAmount2)
                        );

                        // Check rewardEscrow has same escrowAmount3 KWENTA
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(rewardsEscrowV2.address),
                            escrowAmount3
                        );
                    });
                });

                describe("when the first two entrys are vestable and third is partially vestable", () => {
                    beforeEach(async () => {
                        // Need to go into the future to vest first two entries
                        await fastForward(duration + WEEK * 2);
                    });

                    it("should fully vest entries 1 and 2 and partially vest entry 3 and transfer all to user", async () => {
                        await rewardsEscrowV2.vest(
                            [entryID1, entryID2, entryID3],
                            {
                                from: staker1,
                            }
                        );

                        // Check user has entry1 + entry2 amount
                        assert.bnGreaterThan(
                            await mockedKwenta.balanceOf(staker1),
                            escrowAmount1.add(escrowAmount2)
                        );

                        // Check rewardEscrow has remaining entry3 amount
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(rewardsEscrowV2.address),
                            0
                        );
                    });

                    it("should vest and emit a Vest event", async () => {
                        const vestTx = await rewardsEscrowV2.vest(
                            [entryID1, entryID2, entryID3],
                            {
                                from: staker1,
                            }
                        );

                        // Vested(msg.sender, now, total);
                        const vestedEvent = vestTx.logs.find(
                            (log) => log.event === "Vested"
                        );
                        assert.eventEqual(vestedEvent, "Vested", {
                            beneficiary: staker1,
                            value: wei(
                                "784421696142399267400",
                                18,
                                true
                            ).toBN(),
                        });
                    });

                    it("should vest and update totalEscrowedAccountBalance", async () => {
                        // This account should have an escrowedAccountBalance
                        let escrowedAccountBalance =
                            await rewardsEscrowV2.totalEscrowedAccountBalance(
                                staker1
                            );
                        assert.bnEqual(escrowedAccountBalance, toUnit("1000"));

                        // Vest
                        await rewardsEscrowV2.vest(
                            [entryID1, entryID2, entryID3],
                            {
                                from: staker1,
                            }
                        );

                        // This account should have any 0 KWENTA escrowed
                        escrowedAccountBalance =
                            await rewardsEscrowV2.totalEscrowedAccountBalance(
                                staker1
                            );
                        assert.bnEqual(escrowedAccountBalance, 0);
                    });

                    it("should vest and update totalVestedAccountBalance", async () => {
                        // This account should have zero totalVestedAccountBalance before
                        let totalVestedAccountBalance =
                            await rewardsEscrowV2.totalVestedAccountBalance(
                                staker1
                            );
                        assert.bnEqual(totalVestedAccountBalance, toUnit("0"));

                        // Vest
                        await rewardsEscrowV2.vest(
                            [entryID1, entryID2, entryID3],
                            {
                                from: staker1,
                            }
                        );

                        // This account should have vested more than entry 1 and entry 2 amounts
                        totalVestedAccountBalance =
                            await rewardsEscrowV2.totalVestedAccountBalance(
                                staker1
                            );
                        assert.bnGreaterThan(
                            totalVestedAccountBalance,
                            escrowAmount1.add(escrowAmount2)
                        );
                    });

                    it("should vest and update totalEscrowedBalance", async () => {
                        await rewardsEscrowV2.vest(
                            [entryID1, entryID2, entryID3],
                            {
                                from: staker1,
                            }
                        );

                        assert.bnEqual(
                            await rewardsEscrowV2.totalEscrowedBalance(),
                            0
                        );
                    });

                    it("should vest entryID1 and entryID2 and ignore duplicate attempts to vest same entries again", async () => {
                        // Vest attempt 1
                        await rewardsEscrowV2.vest(
                            [entryID1, entryID2, entryID3],
                            {
                                from: staker1,
                            }
                        );

                        const beforeBalance = await mockedKwenta.balanceOf(
                            staker1
                        );

                        // Check user have vested escrowAmount1 + escrowAmount2 + partial escrowAmount3 KWENTA
                        assert.bnGreaterThan(
                            beforeBalance,
                            escrowAmount1.add(escrowAmount2)
                        );

                        // Check rewardEscrow has 0 in escrow
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(rewardsEscrowV2.address),
                            0
                        );

                        // Vest attempt 2
                        await rewardsEscrowV2.vest(
                            [entryID1, entryID2, entryID3],
                            {
                                from: staker1,
                            }
                        );

                        // Check user has same amount of KWENTA
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(staker1),
                            beforeBalance
                        );

                        // Check rewardEscrow has same 0 KWENTA
                        assert.bnEqual(
                            await mockedKwenta.balanceOf(rewardsEscrowV2.address),
                            0
                        );
                    });
                });
            });
        });

        describe("Stress test - Read Vesting Schedule", () => {
            const duration = 1 * YEAR;
            const escrowAmount = toUnit(1);
            const numberOfEntries = 260; // 5 years of entries
            beforeEach(async () => {
                // Transfer of KWENTA to the escrow must occur before creating a vestinng entry
                kwentaSmock.balanceOf.returns(wei(1000).toBN());

                // add a 260 escrow entries
                for (var i = 0; i < numberOfEntries; i++) {
                    await rewardsEscrowV2.appendVestingEntry(
                        staker1,
                        escrowAmount,
                        duration,
                        {
                            from: stakingRewards.address,
                        }
                    );
                }

                // ensure Issuer.debtBalanceOf returns 0
                //mocks['Issuer'].smocked.debtBalanceOf.will.return.with('0');
            });
            it("should return the vesting schedules for staker1", async () => {
                const entries = await rewardsEscrowV2.getVestingSchedules(
                    staker1,
                    0,
                    numberOfEntries
                );
                // should be 260 entries
                assert.equal(entries.length, numberOfEntries);
            }).timeout(200000);
            it("should return the list of vesting entryIDs for staker1", async () => {
                const vestingEntryIDs =
                    await rewardsEscrowV2.getAccountVestingEntryIDs(
                        staker1,
                        0,
                        numberOfEntries
                    );

                // should be 260 entryID's in the list
                assert.equal(vestingEntryIDs.length, numberOfEntries);
            }).timeout(200000);
            it("should return a subset of vesting entryIDs for staker1", async () => {
                const vestingEntryIDs =
                    await rewardsEscrowV2.getAccountVestingEntryIDs(
                        staker1,
                        130,
                        numberOfEntries
                    );

                // should be 130 entryID's in the list
                assert.equal(vestingEntryIDs.length, 130);
            }).timeout(200000);
        });

        describe("Staking Escrow", () => {
            let stakingRewardsSmock;

            beforeEach(async () => {
                stakingRewardsSmock = await smock.fake("contracts/StakingRewards.sol:StakingRewards");

                rewardsEscrowV2 = await RewardsEscrow.new(
                    owner,
                    kwentaSmock.address
                );
                await rewardsEscrowV2.setStakingRewards(
                    stakingRewardsSmock.address,
                    {
                        from: owner,
                    }
                );
                await rewardsEscrowV2.setTreasuryDAO(treasuryDAO);
            });

            it("should revert because staker has no escrowed KWENTA", async () => {
                const escrowAmount = wei(10).toBN();
                await assert.revert(
                    rewardsEscrowV2.stakeEscrow(escrowAmount, {
                        from: staker1,
                    })
                );
            });

            it("should revert because staker does not have enough escrowed KWENTA", async () => {
                const escrowAmount = wei(10).toBN();
                // stub transferFrom
                kwentaSmock.transferFrom.returns(true);
                // stub balanceOf
                kwentaSmock.balanceOf.returns(escrowAmount);
                await rewardsEscrowV2.createEscrowEntry(
                    staker1,
                    escrowAmount,
                    1 * YEAR
                );
                // Stake half of escrow
                stakingRewardsSmock.escrowedBalanceOf.returns(
                    escrowAmount.div(2)
                );
                // Attempt to stake more
                await assert.revert(
                    rewardsEscrowV2.stakeEscrow(escrowAmount, {
                        from: staker1,
                    })
                );
            });

            it("should stake escrow", async () => {
                const escrowAmount = wei(10).toBN();
                // stub transferFrom
                kwentaSmock.transferFrom.returns(true);
                // stub balanceOf
                kwentaSmock.balanceOf.returns(escrowAmount);
                await rewardsEscrowV2.createEscrowEntry(
                    staker1,
                    escrowAmount,
                    1 * YEAR
                );
                await rewardsEscrowV2.stakeEscrow(escrowAmount, {
                    from: staker1,
                });
                expect(stakingRewardsSmock.stakeEscrow).to.have.been.calledWith(
                    staker1,
                    escrowAmount
                );
            });

            it("should unstake escrow", async () => {
                const escrowAmount = wei(10).toBN();
                await rewardsEscrowV2.unstakeEscrow(escrowAmount, {
                    from: staker1,
                });
                expect(
                    stakingRewardsSmock.unstakeEscrow
                ).to.have.been.calledWith(staker1, escrowAmount);
            });

            it("should vest without unstaking escrow", async () => {
                const escrowAmount = wei(10).toBN();
                // stub transferFrom
                kwentaSmock.transferFrom.returns(true);
                // stub balanceOf
                kwentaSmock.balanceOf.returns(escrowAmount.mul(2));
                await rewardsEscrowV2.createEscrowEntry(
                    staker1,
                    escrowAmount,
                    1 * YEAR
                );
                await rewardsEscrowV2.createEscrowEntry(
                    staker1,
                    escrowAmount,
                    1 * YEAR
                );
                //Stake half of escrow
                stakingRewardsSmock.escrowedBalanceOf.returns(escrowAmount);

                await fastForward(YEAR);
                await rewardsEscrowV2.vest([1], { from: staker1 });
                expect(stakingRewardsSmock.unstakeEscrow).to.have.callCount(0);
            });

            // This is what happens when you currently have staked escrow and it needs to be vested
            it("should unstake escrow to vest", async () => {
                const escrowAmount = wei(10).toBN();
                // stub transferFrom
                kwentaSmock.transferFrom.returns(true);
                // stub balanceOf
                kwentaSmock.balanceOf.returns(escrowAmount);
                await rewardsEscrowV2.createEscrowEntry(
                    staker1,
                    escrowAmount,
                    1 * YEAR
                );
                // Mock stake all of escrow
                stakingRewardsSmock.escrowedBalanceOf.returns(escrowAmount);

                await fastForward(YEAR);
                await rewardsEscrowV2.vest([1], { from: staker1 });
                expect(stakingRewardsSmock.unstakeEscrow).to.have.callCount(1);
                expect(
                    stakingRewardsSmock.unstakeEscrow
                ).to.have.been.calledWith(staker1, escrowAmount);
            });

            it("should unstake escrow to partially vest, partially impose fee and send to treaury", async () => {
                const escrowAmount = wei(10).toBN();
                // stub transferFrom
                kwentaSmock.transferFrom.returns(true);
                kwentaSmock.transfer.returns(true);
                // stub balanceOf
                kwentaSmock.balanceOf.returns(escrowAmount);
                await rewardsEscrowV2.createEscrowEntry(
                    staker1,
                    escrowAmount,
                    1 * YEAR
                );
                // Mock stake all of escrow
                stakingRewardsSmock.escrowedBalanceOf.returns(escrowAmount);

                await fastForward(YEAR / 2);
                await rewardsEscrowV2.vest([1], { from: staker1 });
                expect(
                    stakingRewardsSmock.unstakeEscrow
                ).to.have.been.calledWith(staker1, escrowAmount);
                assert.equal(await rewardsEscrowV2.balanceOf(staker1), 0);
            });
        });
    }
);
