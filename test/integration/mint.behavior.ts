import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Contract } from "@ethersproject/contracts";

describe("Mint", () => {
    const NAME = "Kwenta";
    const SYMBOL = "KWENTA";
    const INITIAL_SUPPLY = ethers.utils.parseUnits("313373");
    const TREASURY_DAO_ADDRESS = "0x0000000000000000000000000000000000000001";
    const INFLATION_DIVERSION_BPS = 2000;

    let safeDecimalMath,
        supplySchedule: Contract,
        kwenta: Contract,
        mockStakingRewards: Contract;
    before(async () => {
        const [owner] = await ethers.getSigners();

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
            INITIAL_SUPPLY,
            owner.address,
            TREASURY_DAO_ADDRESS,
            mockStakingRewards.address,
            supplySchedule.address,
            INFLATION_DIVERSION_BPS
        );
        await kwenta.deployed();

        await supplySchedule.setSynthetixProxy(kwenta.address);

        return kwenta;
    });

    it("No inflationary supply to mint", async () => {
        await expect(kwenta.mint()).to.be.revertedWith("No supply is mintable");
        expect(await kwenta.balanceOf(mockStakingRewards.address)).to.equal(0);
    });

    it("Mint inflationary supply 1 week later", async () => {
        const [owner] = await ethers.getSigners();
        const MINTER_REWARD = ethers.utils.parseUnits("200");
        const FIRST_WEEK_MINT = INITIAL_SUPPLY.mul(60)
            .div(100)
            .div(52)
            .sub(MINTER_REWARD);

        // We subtract treasury inflationary diversion amount so that stakers get remainder (after truncation)
        const FIRST_WEEK_STAKING_REWARDS = FIRST_WEEK_MINT.sub(
            FIRST_WEEK_MINT.mul(INFLATION_DIVERSION_BPS).div(10000)
        );

        expect(await kwenta.balanceOf(owner.address)).to.equal(0);
        await network.provider.send("evm_increaseTime", [604800]);
        await kwenta.mint();

        // Make sure this is equivalent to first week distribution
        expect(await kwenta.balanceOf(mockStakingRewards.address)).to.equal(
            FIRST_WEEK_STAKING_REWARDS
        );
    });
});
