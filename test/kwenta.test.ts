import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "@ethersproject/contracts";

describe("KWENTA Token", function () {
    const NAME = "Kwenta";
    const SYMBOL = "KWENTA";
    const INITIAL_SUPPLY = ethers.utils.parseUnits("313373");
    const TREASURY_DAO_ADDRESS = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

    let kwenta: Contract;
    before(async () => {
        const Kwenta = await ethers.getContractFactory("Kwenta");
        kwenta = await Kwenta.deploy(
            NAME,
            SYMBOL,
            INITIAL_SUPPLY,
            TREASURY_DAO_ADDRESS, // Cannot mint to zero address
            ethers.constants.AddressZero,
            ethers.constants.AddressZero
        );
        await kwenta.deployed();
        console.log(kwenta.address)
        return kwenta;
    });

    it('Should deploy "Kwenta" token with "KWENTA" symbol.', async function () {
        expect(await kwenta.name()).to.equal(NAME);
        expect(await kwenta.symbol()).to.equal(SYMBOL);
    });

    it('Total supply should be at 60%', async function () {
        // This is because we only mint into the treasury for now
        expect(await kwenta.totalSupply()).to.equal(INITIAL_SUPPLY.mul(60).div(100));
    });
});
