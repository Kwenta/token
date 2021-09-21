import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Contract } from "@ethersproject/contracts";

describe("Mint", () => {
    const NAME = "Kwenta";
    const SYMBOL = "KWENTA";
    const INITIAL_SUPPLY = ethers.utils.parseUnits("313373");
    const TREASURY_DAO_ADDRESS = "0x0000000000000000000000000000000000000001";
    const REWARDS_DISTRIBUTION_ADDRESS =
        "0x0000000000000000000000000000000000000002";

    let safeDecimalMath, supplySchedule, kwenta: Contract;
    before(async () => {
        const [owner] = await ethers.getSigners();

        const SafeDecimalMath = await ethers.getContractFactory(
            "SafeDecimalMath"
        );
        safeDecimalMath = await SafeDecimalMath.deploy();
        await safeDecimalMath.deployed();

        const SupplySchedule = await ethers.getContractFactory(
            "SupplySchedule",
            {
                libraries: {
                    SafeDecimalMath: safeDecimalMath.address,
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
            TREASURY_DAO_ADDRESS,
            REWARDS_DISTRIBUTION_ADDRESS,
            supplySchedule.address
        );
        await kwenta.deployed();
        return kwenta;
    });

    it("No inflationary supply to mint", async () => {
        await expect(kwenta.mint()).to.be.revertedWith("No supply is mintable");
        expect(await kwenta.balanceOf(REWARDS_DISTRIBUTION_ADDRESS)).to.equal(
            0
        );
    });

    it.skip("Mint inflationary supply 1 week later", async () => {
        const [owner] = await ethers.getSigners();

        expect(await kwenta.balanceOf(owner.address)).to.equal(0);
        await network.provider.send("evm_increaseTime", [604800]);
        await kwenta.mint(); // TODO: look into 'SafeMath: subtraction overflow'
    });
});
