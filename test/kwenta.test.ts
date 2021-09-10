import { expect } from "chai";
import { ethers } from "hardhat";

describe("KWENTA Token", function () {
  it("Should deploy \"Kwenta\" token with \"KWENTA\" symbol.", async function () {
    const NAME = "Kwenta";
    const SYMBOL = "KWENTA";

    const ERC20 = await ethers.getContractFactory("ERC20");
    const kwenta = await ERC20.deploy(NAME, SYMBOL);
    await kwenta.deployed();

    expect(await kwenta.name()).to.equal(NAME);
    expect(await kwenta.symbol()).to.equal(SYMBOL);
  });
});
