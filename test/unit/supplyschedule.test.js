"use strict";

const { ethers } = require("hardhat");
const { parseUnits } = ethers.utils;
const { AddressZero } = ethers.constants;

const {
    onlyGivenAddressCanInvoke,
    fastForwardTo,
} = require("../utils/helpers");

const BN = require("bn.js");
const { expect } = require("chai");
const { wei } = require("@synthetixio/wei");

describe("SupplySchedule", async () => {
    const initialWeeklySupply = wei(313373).mul(0.6).div(52); // 75,000,000 / 52 weeks
    let inflationStartDate;

    //const [, owner, synthetix, account1, account2] = accounts;
    const accounts = await ethers.getSigners();
    const [owner, , account1, account2] = accounts;

    let supplySchedule, synthetixProxy, decayRate;

    /*
     * Exponentiation by squares of x^n, interpreting them as fixed point decimal numbers.
     */
    const powRoundDown = (x, n, unit = wei(1).toBN()) => {
        let xBN = x;
        let temp = unit;
        while (n > 0) {
            if (n % 2 !== 0) {
                temp = temp.mul(xBN).div(unit);
            }
            xBN = xBN.mul(xBN).div(unit);
            n = parseInt(n / 2);
        }
        return temp;
    };

    function getDecaySupplyForWeekNumber(initialAmount, weekNumber) {
        //const effectiveRate = wei(1).sub(decayRate).pow(weekNumber);
        const effectiveRate = powRoundDown(
            wei(1).sub(decayRate).toBN(),
            weekNumber
        );

        const supplyForWeek = initialAmount.mul(effectiveRate);
        return supplyForWeek;
    }

    const setupSupplySchedule = async () => {
        const MockRewardsDistribution = await ethers.getContractFactory(
            "MockRewardsDistribution"
        );
        const mockRewardsDistribution = await MockRewardsDistribution.deploy();
        await mockRewardsDistribution.deployed();

        const SafeDecimalMath = await ethers.getContractFactory(
            "SafeDecimalMath"
        );
        const safeDecimalMath = await SafeDecimalMath.deploy();
        await safeDecimalMath.deployed();

        const SupplySchedule = await ethers.getContractFactory(
            "SupplySchedule",
            {
                libraries: {
                    SafeDecimalMath: safeDecimalMath.address,
                },
            }
        );

        return SupplySchedule;
    };

    beforeEach(async () => {
        const NAME = "Kwenta";
        const SYMBOL = "KWENTA";
        const INITIAL_SUPPLY = parseUnits("313373");
        const TREASURY_DAO_ADDRESS =
            "0x0000000000000000000000000000000000000001";

        const SupplySchedule = await setupSupplySchedule();
        supplySchedule = await SupplySchedule.deploy(owner.address);
        await supplySchedule.deployed();

        const Kwenta = await ethers.getContractFactory("Kwenta");
        synthetixProxy = await Kwenta.deploy(
            NAME,
            SYMBOL,
            INITIAL_SUPPLY,
            TREASURY_DAO_ADDRESS, // Cannot mint to zero address
            ethers.constants.AddressZero,
            ethers.constants.AddressZero
        );

        await synthetixProxy.deployed();
        await supplySchedule.setSynthetixProxy(synthetixProxy.address);

        decayRate = await supplySchedule.DECAY_RATE();
        inflationStartDate = (
            await supplySchedule.INFLATION_START_DATE()
        ).toNumber();
    });

    it("should set constructor params on deployment", async () => {
        const SupplySchedule = await setupSupplySchedule();
        supplySchedule = await SupplySchedule.deploy(owner.address);
        await supplySchedule.deployed();

        const weeklyIssuance = wei(313373).div(52);
        expect(await instance.owner()).to.equal(owner);
        expect(await instance.lastMintEvent()).to.equal(wei(0).toBN());
        expect(await instance.weekCounter()).to.equal(wei(0).toBN());
        expect(await instance.INITIAL_WEEKLY_SUPPLY()).to.equal(weeklyIssuance);
    });

    describe("linking synthetix", async () => {
        it("should have set synthetix proxy", async () => {
            expect(await supplySchedule.synthetixProxy()).to.equal(
                synthetixProxy.address
            );
        });
        it("should revert when setting synthetix proxy to ZERO_ADDRESS", async () => {
            await expect(supplySchedule.setSynthetixProxy(AddressZero)).to.be
                .reverted;
        });

        it("should emit an event when setting synthetix proxy", async () => {
            await expect(
                supplySchedule.setSynthetixProxy(account2.address, {
                    from: owner.address,
                })
            )
                .to.emit(supplySchedule, "SynthetixProxyUpdated")
                .withArgs(account2.address);
        });

        it("should disallow a non-owner from setting the synthetix proxy", async () => {
            await onlyGivenAddressCanInvoke(
                supplySchedule.setSynthetixProxy,
                [account2.address],
                accounts,
                owner.address
            );
        });
    });

    describe("functions and modifiers", async () => {
        it("should allow owner to update the minter reward amount", async () => {
            const existingReward = await supplySchedule.minterReward();
            const newReward = existingReward.sub(ethers.utils.parseUnits("10"));

            //Capture event
            await expect(
                supplySchedule.setMinterReward(newReward, {
                    from: owner.address,
                })
            )
                .to.emit(supplySchedule, "MinterRewardUpdated")
                .withArgs(newReward);

            //Check updated value
            expect(await supplySchedule.minterReward()).to.equal(newReward);
        });

        it("should disallow a non-owner from setting the minter reward amount", async () => {
            await onlyGivenAddressCanInvoke(
                supplySchedule.setMinterReward,
                ["0"],
                accounts,
                owner.address
            );
        });

        describe("exponential decay supply with initial weekly supply of 1.44m", async () => {
            it("check calculating week 1 of inflation decay is valid", async () => {
                const decay = wei(decayRate).mul(initialWeeklySupply);

                const expectedIssuance = initialWeeklySupply.sub(decay);
                // check expectedIssuance of week 1 is same as getDecaySupplyForWeekNumber
                // bnClose as decimal multiplication has rounding
                expect(expectedIssuance.toBN()).to.be.closeTo(
                    getDecaySupplyForWeekNumber(initialWeeklySupply, 1).toBN(),
                    10
                );

                // bnClose as tokenDecaySupply is calculated using the decayRate (rounding down)
                // and not subtraction from initialWeeklySupply.
                expect(
                    await supplySchedule.tokenDecaySupplyForWeek(1)
                ).to.be.closeTo(expectedIssuance.toBN(), 10);
            });
            it("should calculate Week 2 Supply of inflation decay from initial weekly supply", async () => {
                const expectedIssuance = getDecaySupplyForWeekNumber(
                    initialWeeklySupply,
                    2
                );

                expect(
                    await supplySchedule.tokenDecaySupplyForWeek(2)
                ).to.equal(expectedIssuance.toBN());
            });
            it("should calculate Week 3 Supply of inflation decay from initial weekly supply", async () => {
                const expectedIssuance = getDecaySupplyForWeekNumber(
                    initialWeeklySupply,
                    3
                );

                expect(
                    await supplySchedule.tokenDecaySupplyForWeek(3)
                ).to.equal(expectedIssuance.toBN());
            });
            it("should calculate Week 10 Supply of inflation decay from initial weekly supply", async () => {
                const expectedIssuance = getDecaySupplyForWeekNumber(
                    initialWeeklySupply,
                    10
                );

                expect(
                    (
                        await supplySchedule.tokenDecaySupplyForWeek(10)
                    ).toString()
                ).to.equal(expectedIssuance.toBN().toString());
            });
            it("should calculate Week 11 Supply of inflation decay from initial weekly supply", async () => {
                const expectedIssuance = getDecaySupplyForWeekNumber(
                    initialWeeklySupply,
                    11
                );

                expect(
                    await supplySchedule.tokenDecaySupplyForWeek(11)
                ).to.equal(expectedIssuance.toBN());
            });
            it("should calculate last Week 195 Supply of inflation decay from initial weekly supply", async () => {
                const expectedIssuance = getDecaySupplyForWeekNumber(
                    initialWeeklySupply,
                    195
                );

                expect(
                    await supplySchedule.tokenDecaySupplyForWeek(195)
                ).to.equal(expectedIssuance.toBN());
            });
        });

        describe("terminal inflation supply with initial total supply of 1,000,000", async () => {
            let weeklySupplyRate;

            // Calculate the compound supply for numberOfPeriods (weeks) and initial principal
            // as supply at the beginning of the periods.
            function getCompoundSupply(principal, weeklyRate, numberOfPeriods) {
                // calcualte effective compound rate for number of weeks to 18 decimals precision
                const effectiveRate = powRoundDown(
                    wei(1).add(weeklyRate).toBN(),
                    numberOfPeriods
                );

                // supply = P * ( (1 + weeklyRate)^weeks) - 1)
                return wei(principal).mul(wei(effectiveRate).sub(wei(1)));
            }

            beforeEach(async () => {
                const terminalAnnualSupplyRate =
                    await supplySchedule.TERMINAL_SUPPLY_RATE_ANNUAL();
                weeklySupplyRate = wei(terminalAnnualSupplyRate).div(52);
            });

            // check initalAmount * weeklySupplyRate for 1 week is expected amount
            it("should calculate weekly supply for 1 week at 1.25pa% with 1m principal", async () => {
                const initialAmount = wei(1e6); // 1,000,000
                const expectedAmount = weeklySupplyRate.mul(initialAmount);

                expect(
                    await supplySchedule.terminalInflationSupply(
                        initialAmount.toBN(),
                        1
                    )
                ).to.equal(expectedAmount.toBN());
            });
            it("should calculate compounded weekly supply for 2 weeks at 1.25pa%", async () => {
                const intialAmount = wei(1e6); // 1,000,000
                const expectedAmount = getCompoundSupply(
                    intialAmount,
                    weeklySupplyRate,
                    2
                );
                const result = await supplySchedule.terminalInflationSupply(
                    intialAmount.toBN(),
                    2
                );

                expect(result).to.equal(expectedAmount.toBN());
            });
            it("should calculate compounded weekly supply for 4 weeks at 1.25pa%", async () => {
                const intialAmount = wei(1e6); // 1,000,000
                const expectedAmount = getCompoundSupply(
                    intialAmount,
                    weeklySupplyRate,
                    4
                );
                const result = await supplySchedule.terminalInflationSupply(
                    intialAmount.toBN(),
                    4
                );

                expect(result).to.equal(expectedAmount.toBN());
            });
            it("should calculate compounded weekly supply with principal 10m for 10 weeks at 1.25pa%", async () => {
                const intialAmount = wei(10e6); // 10,000,000
                const expectedAmount = getCompoundSupply(
                    intialAmount,
                    weeklySupplyRate,
                    10
                );
                const result = await supplySchedule.terminalInflationSupply(
                    intialAmount.toBN(),
                    10
                );

                expect(result).to.equal(expectedAmount.toBN());
            });
            it("should calculate compounded weekly supply with principal 260,387,945 for 1 week at 1.25pa%", async () => {
                const initialAmount = wei(260387945); // 260,387,945
                const expectedAmount = getCompoundSupply(
                    initialAmount,
                    weeklySupplyRate,
                    1
                );

                // check compound supply for 1 week is correct
                expect(expectedAmount.toBN()).to.equal(
                    initialAmount.mul(weeklySupplyRate).toBN()
                ); // ~125,187

                const result = await supplySchedule.terminalInflationSupply(
                    initialAmount.toBN(),
                    1
                );

                expect(result).to.equal(expectedAmount.toBN());
            });
            it("should calculate compounded weekly supply with principal 260,387,945 for 2 weeks at 1.25pa%", async () => {
                const initialAmount = wei(260387945); // 260,387,945
                const expectedAmount = getCompoundSupply(
                    initialAmount,
                    weeklySupplyRate,
                    2
                );

                const result = await supplySchedule.terminalInflationSupply(
                    initialAmount.toBN(),
                    2
                );

                expect(result).to.equal(expectedAmount.toBN());
            });
            it("should calculate compounded weekly supply with principal 260,387,945 for 10 weeks at 1.25pa%", async () => {
                const initialAmount = wei(260387945); // 260,387,945
                const expectedAmount = getCompoundSupply(
                    initialAmount,
                    weeklySupplyRate,
                    10
                );

                const result = await supplySchedule.terminalInflationSupply(
                    initialAmount.toBN(),
                    10
                );

                expect(result).to.equal(expectedAmount.toBN());
            });
            it("should calculate compounded weekly supply with principal 260,387,945 for 100 weeks at 1.25pa%", async () => {
                const initialAmount = wei(260387945); // 260,387,945
                const expectedAmount = getCompoundSupply(
                    initialAmount,
                    weeklySupplyRate,
                    100
                );

                const result = await supplySchedule.terminalInflationSupply(
                    initialAmount.toBN(),
                    100
                );

                expect(result).to.equal(expectedAmount.toBN());
            });
        });

        describe("mintable supply", async () => {
            const DAY = 60 * 60 * 24;
            const WEEK = 604800;
            let weekOne;

            beforeEach(async () => {
                weekOne = inflationStartDate + 3600 + 1 * DAY; // 1 day and 60 mins within first week of Inflation supply > Inflation supply as 1 day buffer is added to lastMintEvent
            });

            async function checkMintedValues(
                mintedSupply = wei(0),
                weeksIssued,
                instance = supplySchedule
            ) {
                const weekCounterBefore = await instance.weekCounter();

                // call updateMintValues to mimic synthetix issuing tokens
                await supplySchedule.setSynthetixProxy(owner.address);
                const transaction = await instance.recordMintEvent(
                    mintedSupply.toBN()
                );

                const weekCounterAfter = weekCounterBefore.add(
                    wei(weeksIssued, 18, true).toBN()
                );
                const lastMintEvent = await instance.lastMintEvent();

                expect(await instance.weekCounter()).to.equal(weekCounterAfter);

                // lastMintEvent is updated to number of weeks after inflation start date + 1 DAY buffer
                expect(
                    lastMintEvent.toNumber() ===
                        inflationStartDate + weekCounterAfter * WEEK + 1 * DAY
                ).to.be.ok;

                // check event emitted has correct amounts of supply
                /*expect(transaction)
                    .to.emit(transaction, "SupplyMinted")
                    .withArgs(
                        mintedSupply,
                        wei(weeksIssued, 18, true).toBN(),
                        lastMintEvent
                    );*/
            }

            it("should calculate the mintable supply as 0 within 1st week", async () => {
                const expectedIssuance = wei(0).toBN();
                // fast forward EVM to Week 1
                await fastForwardTo(new Date(weekOne * 1000));

                expect(await supplySchedule.mintableSupply()).to.equal(
                    expectedIssuance
                );
            });

            it.only("should calculate the mintable supply after 1 week", async () => {
                const expectedIssuance = initialWeeklySupply.toBN();
                const inWeekTwo = weekOne + WEEK;
                // fast forward EVM to Week 2
                await fastForwardTo(new Date(inWeekTwo * 1000));

                expect(await supplySchedule.mintableSupply()).to.equal(
                    expectedIssuance
                );
            });

            it("should calculate the mintable supply after 2 weeks", async () => {
                const expectedIssuance = initialWeeklySupply
                    .add(getDecaySupplyForWeekNumber(initialWeeklySupply, 1))
                    .toBN();

                const inWeekThree = weekOne + 2 * WEEK;
                // fast forward EVM to within Week 3
                await fastForwardTo(new Date(inWeekThree * 1000));

                expect(await supplySchedule.mintableSupply()).to.equal(
                    expectedIssuance
                );
            });

            it("should calculate the mintable supply after 3 weeks", async () => {
                const expectedIssuance = initialWeeklySupply
                    .add(getDecaySupplyForWeekNumber(initialWeeklySupply, 1))
                    .add(getDecaySupplyForWeekNumber(initialWeeklySupply, 2))
                    .toBN();
                const inWeekFour = weekOne + 3 * WEEK;
                // fast forward EVM to within Week 4 in Year 2 schedule starting at UNIX 1552435200+
                await fastForwardTo(new Date(inWeekFour * 1000));

                expect(await supplySchedule.mintableSupply()).to.equal(
                    expectedIssuance
                );
            });

            it("should calculate the mintable supply after 39 weeks", async () => {
                let expectedIssuance = wei(0);
                for (let i = 0; i <= 38; i++) {
                    expectedIssuance = expectedIssuance.add(
                        getDecaySupplyForWeekNumber(
                            initialWeeklySupply,
                            new BN(i)
                        )
                    );
                }

                const weekFourty = weekOne + 39 * WEEK;
                // fast forward EVM to within Week 40
                await fastForwardTo(new Date(weekFourty * 1000));

                expect(await supplySchedule.mintableSupply()).to.equal(
                    expectedIssuance.toBN()
                );
            });

            it("should calculate mintable supply of 1x week after minting", async () => {
                // fast forward EVM to Week 2
                const weekTwo = weekOne + 1 * WEEK;
                await fastForwardTo(new Date(weekTwo * 1000));

                const mintableSupply = await supplySchedule.mintableSupply();

                // fake updateMintValues
                await checkMintedValues(wei(mintableSupply, 18, true), 1);

                // Fast forward to week 2
                const weekThree = weekTwo + WEEK + 1 * DAY;
                // Expect only 1 extra week is mintable after first week minted

                await fastForwardTo(new Date(weekThree * 1000));

                expect(await supplySchedule.mintableSupply()).to.equal(
                    getDecaySupplyForWeekNumber(initialWeeklySupply, 1).toBN()
                );
            });

            it("should calculate mintable supply of 2 weeks if 2+ weeks passed, after minting", async () => {
                // fast forward EVM to Week 2 in Year 2 schedule starting at UNIX 1552435200+
                const weekTwo = weekOne + 1 * WEEK;
                await fastForwardTo(new Date(weekTwo * 1000));

                // Mint the first week of supply
                const mintableSupply = await supplySchedule.mintableSupply();

                // fake updateMintValues
                await checkMintedValues(wei(mintableSupply, 18, true), 1);

                // fast forward 2 weeks to within week 4
                const weekFour = weekTwo + 2 * WEEK + 1 * DAY; // Sometime within week four
                // // Expect 2 week is mintable after first week minted
                const expectedIssuance = initialWeeklySupply.mul(new BN(2));
                await fastForwardTo(new Date(weekFour * 1000));

                // fake minting 2 weeks again
                await checkMintedValues(expectedIssuance, 2);
            });

            describe("rounding down lastMintEvent to number of weeks issued since inflation start date", async () => {
                it("should have 0 mintable supply, only after 1 day, if minting was 5 days late", async () => {
                    // fast forward EVM to Week 2 in
                    const weekTwoAndFiveDays = weekOne + 1 * WEEK + 5 * DAY;
                    await fastForwardTo(new Date(weekTwoAndFiveDays * 1000));

                    // Mint the first week of supply
                    const mintableSupply =
                        await supplySchedule.mintableSupply();

                    // fake updateMintValues
                    await checkMintedValues(wei(mintableSupply, 18, true), 1);

                    // fast forward +1 day, should not be able to mint again
                    const weekTwoAndSixDays = weekTwoAndFiveDays + 1 * DAY; // Sometime within week two

                    // Expect no supply is mintable as still within weekTwo
                    await fastForwardTo(new Date(weekTwoAndSixDays * 1000));

                    expect(await supplySchedule.mintableSupply()).to.equal(
                        wei(0).toBN()
                    );
                });
                it("should be 1 week of mintable supply, after 2+ days, if minting was 5 days late", async () => {
                    // fast forward EVM to Week 2 in
                    const weekTwoAndFiveDays = weekOne + 1 * WEEK + 5 * DAY;
                    await fastForwardTo(new Date(weekTwoAndFiveDays * 1000));

                    // Mint the first week of supply
                    const mintableSupply =
                        await supplySchedule.mintableSupply();

                    // fake updateMintValues
                    await checkMintedValues(wei(mintableSupply, 18, true), 1);

                    // fast forward +2 days, should be able to mint again
                    const weekThree = weekTwoAndFiveDays + 2 * DAY; // Sometime within week three

                    // Expect 1 week is mintable after first week minted
                    const expectedIssuance = initialWeeklySupply.mul(new BN(1));
                    await fastForwardTo(new Date(weekThree * 1000));

                    // fake minting 1 week again
                    await checkMintedValues(expectedIssuance, 1);
                });
                it("should calculate 2 weeks of mintable supply after 1 week and 2+ days, if minting was 5 days late in week 2", async () => {
                    // fast forward EVM to Week 2 but not whole week 2
                    const weekTwoAndFiveDays = weekOne + 1 * WEEK + 5 * DAY;
                    await fastForwardTo(new Date(weekTwoAndFiveDays * 1000));

                    // Mint the first week of supply
                    const mintableSupply =
                        await supplySchedule.mintableSupply();

                    // fake updateMintValues
                    await checkMintedValues(wei(mintableSupply, 18, true), 1);

                    // fast forward 1 week and +2 days, should be able to mint again
                    const withinWeekFour =
                        weekTwoAndFiveDays + 1 * WEEK + 2 * DAY; // Sometime within week three

                    // Expect 1 week is mintable after first week minted
                    const expectedIssuance = initialWeeklySupply.mul(new BN(2));
                    await fastForwardTo(new Date(withinWeekFour * 1000));

                    // fake minting 1 week again
                    await checkMintedValues(expectedIssuance, 2);
                });
            });
        });
    });
});
