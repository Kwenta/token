import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "@ethersproject/contracts";
import { FakeContract, smock } from "@defi-wonderland/smock";
import { SupplySchedule } from "../../typechain/SupplySchedule";
import { StakingRewards } from "../../typechain/StakingRewards";

describe("KWENTA Token", function () {
    const NAME = "Kwenta";
    const SYMBOL = "KWENTA";
    const INITIAL_SUPPLY = ethers.utils.parseUnits("313373");
    const TREASURY_DAO_ADDRESS = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const INFLATION_DIVERSION_BPS = 2000; 

    let kwenta: Contract
    let supplySchedule: FakeContract<SupplySchedule>;
    let stakingRewards: FakeContract<StakingRewards>;

    before(async () => {
        const [owner] = await ethers.getSigners();

        supplySchedule = await smock.fake("SupplySchedule");
        stakingRewards = await smock.fake("StakingRewards");

        const Kwenta = await ethers.getContractFactory("Kwenta");
        kwenta = await Kwenta.deploy(
            NAME,
            SYMBOL,
            INITIAL_SUPPLY,
            owner.address,
            TREASURY_DAO_ADDRESS, // Cannot mint to zero address
            supplySchedule.address,
            INFLATION_DIVERSION_BPS
        );
        await kwenta.deployed();

        return kwenta;
    });

    it('Should deploy "Kwenta" token with "KWENTA" symbol.', async function () {
        expect(await kwenta.name()).to.equal(NAME);
        expect(await kwenta.symbol()).to.equal(SYMBOL);
    });

    it("Total supply should be 313373", async function () {
        expect(await kwenta.totalSupply()).to.equal(
            INITIAL_SUPPLY
        );
    });

    it("Test mint reverts because 'Staking rewards not set'", async function () {
        expect(await kwenta.stakingRewards()).to.equal("0x0000000000000000000000000000000000000000");
        await expect(kwenta.mint()).to.be.revertedWith(
            "Staking rewards not set"
        );
    });

    it("Test setting the staking rewards address actually sets the address", async function () {
        await kwenta.setStakingRewards(stakingRewards.address);
        expect(await kwenta.stakingRewards()).to.equal(stakingRewards.address);
    });

    it("Test inflationary diversion", async function () {
        await kwenta.setStakingRewards(stakingRewards.address);
        const inflationaryRewardsForMint = 200;
        const treasurySupplyWithDivertedRewards = INITIAL_SUPPLY.add(
            ethers.BigNumber.from(inflationaryRewardsForMint)
                .mul(INFLATION_DIVERSION_BPS)
                .div(10000)
        );

        supplySchedule.mintableSupply.returns(inflationaryRewardsForMint);
        await kwenta.mint();

        expect(await kwenta.balanceOf(TREASURY_DAO_ADDRESS)).to.equal(
            treasurySupplyWithDivertedRewards
        );
    });

    it("Test changing inflationary diversion percentage", async function () {
        await kwenta.setTreasuryDiversion(3000);
        expect(await kwenta.treasuryDiversion()).to.equal("3000");
    });

    it("Test revert for setting inflationary diversion basis points greater than 10000", async function () {
        await expect(kwenta.setTreasuryDiversion(20000)).to.be.revertedWith(
            "Represented in basis points"
        );
    });

});
