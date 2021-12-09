import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Contract } from "@ethersproject/contracts";

describe("Mint", () => {
    const NAME = "Kwenta";
    const SYMBOL = "KWENTA";
    const INITIAL_SUPPLY = ethers.utils.parseUnits("313373");
    const TREASURY_DAO_ADDRESS = "0x0000000000000000000000000000000000000001";

    let safeDecimalMath,
        supplySchedule: Contract,
        kwenta: Contract,
        mockRewardsDistribution: Contract;
    before(async () => {
        const [owner] = await ethers.getSigners();

        const MockRewardsDistribution = await ethers.getContractFactory(
            "MockRewardsDistribution"
        );
        mockRewardsDistribution = await MockRewardsDistribution.deploy();
        await mockRewardsDistribution.deployed();

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
            mockRewardsDistribution.address,
            supplySchedule.address
        );
        await kwenta.deployed();

        await supplySchedule.setSynthetixProxy(kwenta.address);

        return kwenta;
    });

    it("No inflationary supply to mint", async () => {
        await expect(kwenta.mint()).to.be.revertedWith("No supply is mintable");
        expect(
            await kwenta.balanceOf(mockRewardsDistribution.address)
        ).to.equal(0);
    });

    it("Mint inflationary supply 1 week later", async () => {
        const [owner] = await ethers.getSigners();
        const MINTER_REWARD = ethers.utils.parseUnits("200");

        expect(await kwenta.balanceOf(owner.address)).to.equal(0);
        await network.provider.send("evm_increaseTime", [604800]);
        await kwenta.mint();

        // Make sure this is equivalent to first week distribution
        expect(
            await kwenta.balanceOf(mockRewardsDistribution.address)
        ).to.equal(INITIAL_SUPPLY.mul(60).div(100).div(52).sub(MINTER_REWARD));
    });
});
