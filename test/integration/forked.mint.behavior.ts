import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Contract } from "@ethersproject/contracts";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import Wei, { wei } from "@synthetixio/wei";
import { BigNumber } from "ethers";

// Fork Optimism Network for following tests
const forkOptimismNetwork = async () => {
	await network.provider.request({
		method: 'hardhat_reset',
		params: [
			{
				forking: {
					jsonRpcUrl: process.env.ARCHIVE_NODE_URL,
					blockNumber: 3225902,
				},
			},
		],
	});
};

describe("Mint", () => {
    const NAME = "Kwenta";
    const SYMBOL = "KWENTA";
    const INITIAL_SUPPLY = wei(313373);
    const INITIAL_WEEKLY_EMISSION = INITIAL_SUPPLY.mul(2.4).div(52);
    const RATE_OF_DECAY = 0.0205;
    const TREASURY_DAO_ADDRESS = "0x0000000000000000000000000000000000000001";
    const INFLATION_DIVERSION_BPS = 2000;

    let safeDecimalMath,
        supplySchedule: Contract,
        kwenta: Contract,
        mockStakingRewards: Contract;
    let owner: SignerWithAddress;

    beforeEach(async () => {
        // fork optimism mainnet
		forkOptimismNetwork();
        
        [owner] = await ethers.getSigners();

        const MockStakingRewards = await ethers.getContractFactory(
            "MockStakingRewards"
        );
        mockStakingRewards = await MockStakingRewards.deploy();
        await mockStakingRewards.deployed();

        const SafeDecimalMath = await ethers.getContractFactory(
            "SafeDecimalMathV5"
        );
        safeDecimalMath = await SafeDecimalMath.deploy();
        await safeDecimalMath.deployed();

        const SupplySchedule = await ethers.getContractFactory(
            "SupplySchedule",
            {
                libraries: {
                    SafeDecimalMathV5: safeDecimalMath.address,
                },
            }
        );
        supplySchedule = await SupplySchedule.deploy(owner.address);
        await supplySchedule.deployed();

        const Kwenta = await ethers.getContractFactory("Kwenta");
        kwenta = await Kwenta.deploy(
            NAME,
            SYMBOL,
            INITIAL_SUPPLY.toBN(),
            owner.address,
            TREASURY_DAO_ADDRESS,
            supplySchedule.address,
            INFLATION_DIVERSION_BPS
        );
        await kwenta.deployed();
        await kwenta.setStakingRewards(mockStakingRewards.address);

        await supplySchedule.setKwenta(kwenta.address);

        return kwenta;
    });

    it("No inflationary supply to mint", async () => {
        await expect(kwenta.mint()).to.be.revertedWith("No supply is mintable");
        expect(await kwenta.balanceOf(mockStakingRewards.address)).to.equal(0);
    });

    it("Mint inflationary supply 1 week later", async () => {
        const MINTER_REWARD = ethers.utils.parseUnits("1");
        const FIRST_WEEK_MINT = INITIAL_WEEKLY_EMISSION.sub(MINTER_REWARD);

        // We subtract treasury inflationary diversion amount so that stakers get remainder (after truncation)
        const FIRST_WEEK_STAKING_REWARDS = FIRST_WEEK_MINT.sub(
            FIRST_WEEK_MINT.mul(INFLATION_DIVERSION_BPS).div(10000)
        );

        expect(await kwenta.balanceOf(owner.address)).to.equal(0);
        await network.provider.send("evm_increaseTime", [604800]);
        await kwenta.mint();

        // Make sure this is equivalent to first week distribution
        expect(await kwenta.balanceOf(mockStakingRewards.address)).to.equal(
            FIRST_WEEK_STAKING_REWARDS.toBN()
        );
    });

    describe("Verify future supply", () => {
        const powRoundDown = (
            x: BigNumber,
            n: number,
            unit = wei(1).toBN()
        ) => {
            let xBN = x;
            let temp = unit;
            while (n > 0) {
                if (n % 2 !== 0) {
                    temp = temp.mul(xBN).div(unit);
                }
                xBN = xBN.mul(xBN).div(unit);
                n = parseInt(String(n / 2)); // For some reason my terminal will freeze until reboot if I don't do this?
            }
            return temp;
        };

        function getSupplyAtWeek(weekNumber: number) {
            let supply = INITIAL_SUPPLY;
            for (let week = 0; week < weekNumber; week++) {
                const expectedMint = INITIAL_WEEKLY_EMISSION.mul(
                    powRoundDown(wei(1 - RATE_OF_DECAY).toBN(), week)
                );
                supply = supply.add(expectedMint);
            }
            return supply;
        }

        it("Mint rewards 1 week later", async () => {
            const expected = getSupplyAtWeek(1);
            await network.provider.send("evm_increaseTime", [604800]);
            await kwenta.mint();
            expect(await kwenta.totalSupply()).to.equal(expected.toBN());
        });

        it("Mint rewards the second week after the first", async () => {
            const expected = getSupplyAtWeek(2);
            await network.provider.send("evm_increaseTime", [604800]);
            await kwenta.mint();
            await network.provider.send("evm_increaseTime", [604800 * 2]);
            await kwenta.mint();
            expect(await kwenta.totalSupply()).to.equal(expected.toBN());
        });

        it("Mint rewards the second week skipping first", async () => {
            const expected = getSupplyAtWeek(2);
            await network.provider.send("evm_increaseTime", [604800 * 2]);
            await kwenta.mint();
            expect(await kwenta.totalSupply()).to.equal(expected.toBN());
        });

        it("Mint rewards 4 years later", async () => {
            const expected = getSupplyAtWeek(208);
            await network.provider.send("evm_increaseTime", [604800 * 208]);
            await kwenta.mint();
            expect(await kwenta.totalSupply()).to.equal(expected.toBN());
        });

        it("Mint rewards 4 years and one week later", async () => {
            const expectedSupplyAtEndOfDecay = getSupplyAtWeek(208);
            const expected = expectedSupplyAtEndOfDecay.add(
                expectedSupplyAtEndOfDecay.mul(wei(0.01).div(52))
            );
            await network.provider.send("evm_increaseTime", [604800 * 208]);
            await kwenta.mint();
            await network.provider.send("evm_increaseTime", [604800 * 2]);
            await kwenta.mint();
            expect(await kwenta.totalSupply()).to.equal(expected.toBN());
        });
    });
});
