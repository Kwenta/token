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
    const INFLATION_DIVERSION_BPS = 2000;

    let kwenta: Contract, supplySchedule: FakeContract<SupplySchedule>;
    beforeEach(async () => {
        const [owner, treasuryDAO] = await ethers.getSigners();
        supplySchedule = await smock.fake("SupplySchedule");

        const stakingRewards = await smock.fake<StakingRewards>(
            "StakingRewards"
        );

        const Kwenta = await ethers.getContractFactory("Kwenta");
        kwenta = await Kwenta.deploy(
            NAME,
            SYMBOL,
            INITIAL_SUPPLY,
            owner.address,
            treasuryDAO.address, // Cannot mint to zero address
            stakingRewards.address,
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
        expect(await kwenta.totalSupply()).to.equal(INITIAL_SUPPLY);
    });

    it("Test inflationary diversion", async function () {
        const [, treasuryDAO] = await ethers.getSigners();
        const inflationaryRewardsForMint = 200;
        const treasurySupplyWithDivertedRewards = INITIAL_SUPPLY.add(
            ethers.BigNumber.from(inflationaryRewardsForMint)
                .mul(INFLATION_DIVERSION_BPS)
                .div(10000)
        );

        supplySchedule.mintableSupply.returns(inflationaryRewardsForMint);
        await kwenta.mint();

        expect(await kwenta.balanceOf(treasuryDAO.address)).to.equal(
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

    it("Test burn attempt from empty address", async function () {
        const [, , user1] = await ethers.getSigners();
        await expect(kwenta.connect(user1).burn(1)).to.be.revertedWith(
            "ERC20: burn amount exceeds balance"
        );
    });

    it("Test burn attempt", async function () {
        const [, treasuryDAO] = await ethers.getSigners();
        await kwenta.connect(treasuryDAO).burn(1);
        expect(await kwenta.totalSupply()).to.equal(INITIAL_SUPPLY.sub("1"));
    });
});
