import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { Contract } from "@ethersproject/contracts";
import { FakeContract, smock } from "@defi-wonderland/smock";
import { SupplySchedule } from "../../../typechain/SupplySchedule";
import { StakingRewards } from "../../../typechain/StakingRewards";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { wei } from "@synthetixio/wei";

describe("KWENTA Token", function () {
    const NAME = "Kwenta";
    const SYMBOL = "KWENTA";
    const INITIAL_SUPPLY = ethers.utils.parseUnits("313373");
    const INFLATION_DIVERSION_BPS = 2000;

    let kwenta: Contract;
    let supplySchedule: FakeContract<SupplySchedule>;
    let stakingRewards: FakeContract<StakingRewards>;

    let owner: SignerWithAddress,
        treasuryDAO: SignerWithAddress,
        user1: SignerWithAddress;
    beforeEach(async () => {
        [owner, treasuryDAO, user1] = await ethers.getSigners();

        supplySchedule = await smock.fake("SupplySchedule");
        stakingRewards = await smock.fake("contracts/StakingRewards.sol:StakingRewards");

        const Kwenta = await ethers.getContractFactory("Kwenta");
        kwenta = await Kwenta.deploy(
            NAME,
            SYMBOL,
            INITIAL_SUPPLY,
            owner.address,
            treasuryDAO.address
        );
        await kwenta.deployed();

        await kwenta.setSupplySchedule(supplySchedule.address);

        return kwenta;
    });

    it('Should deploy "Kwenta" token with "KWENTA" symbol.', async function () {
        expect(await kwenta.name()).to.equal(NAME);
        expect(await kwenta.symbol()).to.equal(SYMBOL);
    });

    it("Total supply should be 313373", async function () {
        expect(await kwenta.totalSupply()).to.equal(INITIAL_SUPPLY);
    });

    it("Cannot mint from address other than supply schedule", async () => {
        await expect(kwenta.mint(owner.address, 100)).to.be.revertedWith(
            'Kwenta: Only SupplySchedule can perform this action'
        );
    });

    it("Can mint if supplySchedule", async () => {
        await hre.network.provider.send("hardhat_setBalance", [
            supplySchedule.address,
            "0x1000000000000000",
        ]);
        const impersonatedSupplySchedule = await ethers.getSigner(
            supplySchedule.address
        );
        await kwenta
            .connect(impersonatedSupplySchedule)
            .mint(owner.address, 100);
        expect(await kwenta.balanceOf(owner.address)).to.be.equal(100);
    });

    it("Test burn attempt from empty address", async function () {
        await expect(kwenta.connect(user1).burn(1)).to.be.revertedWith(
            "ERC20: burn amount exceeds balance"
        );
    });

    it("Test burn attempt", async function () {
        await kwenta.connect(treasuryDAO).burn(1);
        expect(await kwenta.totalSupply()).to.equal(INITIAL_SUPPLY.sub("1"));
    });
});
