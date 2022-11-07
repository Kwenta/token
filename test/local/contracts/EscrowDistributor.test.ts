import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, BigNumber } from "ethers";
import { smock } from "@defi-wonderland/smock";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployKwenta } from "../../utils/kwenta";
import { wei } from "@synthetixio/wei";

require("chai")
    .use(require("chai-as-promised"))
    .use(require("chai-bn-equal"))
    .use(smock.matchers)
    .should();

// constants
const NAME = "Kwenta";
const SYMBOL = "KWENTA";
const INITIAL_SUPPLY = ethers.utils.parseUnits("313373");
const DURATION_WEEKS = BigNumber.from(52);
const APPROVAL_AMOUNT = wei(1000000).toBN();

// test accounts
let owner: SignerWithAddress;
let addr0: SignerWithAddress;
let addr1: SignerWithAddress;
let addr2: SignerWithAddress;
let TREASURY_DAO: SignerWithAddress;

// core contracts
let kwenta: Contract;
let rewardEscrow: Contract;
let distributor: Contract;

describe("EscrowDistributor", () => {
    beforeEach("Deploy contracts", async () => {
        [owner, addr0, addr1, addr2, TREASURY_DAO] = await ethers.getSigners();

        let deployments = await deployKwenta(
            NAME,
            SYMBOL,
            INITIAL_SUPPLY,
            owner,
            TREASURY_DAO
        );

        kwenta = deployments.kwenta;
        rewardEscrow = deployments.rewardEscrow;
    });

    it("sets escrow address on constructor", async () => {
        const EscrowDistributor = await ethers.getContractFactory(
            "EscrowDistributor"
        );
        distributor = await EscrowDistributor.deploy(
            kwenta.address,
            rewardEscrow.address
        );

        await distributor.deployed();
        expect(await distributor.rewardEscrowAddr()).to.equal(
            rewardEscrow.address
        );
    });

    it("fails to batch escrow when number of accounts doesn't equal number of amounts", async () => {
        const EscrowDistributor = await ethers.getContractFactory(
            "EscrowDistributor"
        );
        distributor = await EscrowDistributor.deploy(
            kwenta.address,
            rewardEscrow.address
        );
        await distributor.deployed();
        await expect(
            distributor.distirbuteEscrowed(
                [addr0.address],
                [wei(100).toBN(), wei(1000).toBN()],
                DURATION_WEEKS
            )
        ).to.be.revertedWith(
            "Number of accounts does not match number of values"
        );
    });

    it("distributes escrowed amounts successfully", async () => {
        const EscrowDistributor = await ethers.getContractFactory(
            "EscrowDistributor"
        );
        distributor = await EscrowDistributor.deploy(
            kwenta.address,
            rewardEscrow.address
        );
        await distributor.deployed();

        await kwenta
            .connect(TREASURY_DAO)
            .transfer(owner.address, wei(10000).toBN());

        await kwenta
            .connect(owner)
            .approve(distributor.address, APPROVAL_AMOUNT);

        expect(
            await distributor
                .connect(owner)
                .distirbuteEscrowed(
                    [addr0.address, addr1.address, addr2.address],
                    [wei(1).toBN(), wei(50).toBN(), wei(200).toBN()],
                    DURATION_WEEKS
                )
        ).to.emit(distributor, "BatchEscrowed");

        expect(await rewardEscrow.balanceOf(addr0.address)).to.equal(
            wei(1).toBN()
        );
        expect(await rewardEscrow.balanceOf(addr1.address)).to.equal(
            wei(50).toBN()
        );
        expect(await rewardEscrow.balanceOf(addr2.address)).to.equal(
            wei(200).toBN()
        );
    });
});