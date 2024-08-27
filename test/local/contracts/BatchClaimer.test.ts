import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Contract, BigNumber } from "ethers";
import { smock } from "@defi-wonderland/smock";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import BalanceTree from "../../../scripts/merkle/balance-tree";
import { deployKwenta } from "../../utils/kwenta";

require("chai")
    .use(require("chai-as-promised"))
    .use(require("chai-bn-equal"))
    .use(smock.matchers)
    .should();

// constants
const NAME = "Kwenta";
const SYMBOL = "KWENTA";
const INITIAL_SUPPLY = ethers.utils.parseUnits("313373");
const EPOCH_ZERO = 0;
const EPOCH_ONE = 1;
const USDC_ADDRESS = "0x0b2c639c533813f4aa9d7837caf62653d097ff85";

// test accounts
let owner: SignerWithAddress;
let addr0: SignerWithAddress;
let addr1: SignerWithAddress;
let addr2: SignerWithAddress;
let TREASURY_DAO: SignerWithAddress;

// core contracts
let kwenta: Contract;
let rewardEscrow: Contract;

const loadSetup = () => {
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

        const RewardEscrowV2 = await ethers.getContractFactory(
            "RewardEscrowV2"
        );
        rewardEscrow = await upgrades.deployProxy(
            RewardEscrowV2,
            [owner.address],
            {
                constructorArgs: [kwenta.address, TREASURY_DAO.address],
            }
        );
        await rewardEscrow.deployed();

        const StakingRewardsV2 = await ethers.getContractFactory(
            "StakingRewardsV2"
        );
        const stakingRewards = await upgrades.deployProxy(
            StakingRewardsV2,
            [owner.address],
            {
                constructorArgs: [
                    kwenta.address,
                    USDC_ADDRESS,
                    rewardEscrow.address,
                    TREASURY_DAO.address,
                ],
            }
        );
        await stakingRewards.deployed();

        await rewardEscrow.setStakingRewards(stakingRewards.address);
    });
};

describe("BatchClaimer", () => {
    loadSetup();

    describe("claim across two contracts", () => {
        let distributor1: Contract;
        let distributor2: Contract;
        let batchClaimer: Contract;
        let tree: BalanceTree;
        let tree2: BalanceTree;
        beforeEach("deploy", async () => {
            // Build tree with:
            // (1) addresses who can claim KWENTA
            // (2) amount given address can claim
            tree = new BalanceTree([
                { account: addr0.address, amount: BigNumber.from(100) },
                { account: addr1.address, amount: BigNumber.from(101) },
                { account: addr2.address, amount: BigNumber.from(202) },
            ]);

            tree2 = new BalanceTree([
                { account: addr0.address, amount: BigNumber.from(1100) },
                { account: addr1.address, amount: BigNumber.from(1101) },
            ]);

            const EscrowedMultipleMerkleDistributor =
                await ethers.getContractFactory(
                    "EscrowedMultipleMerkleDistributor"
                );
            const BatchClaimer = await ethers.getContractFactory(
                "BatchClaimer"
            );

            distributor1 = await EscrowedMultipleMerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address
            );
            await distributor1.deployed();
            distributor2 = await EscrowedMultipleMerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address
            );
            await distributor2.deployed();
            batchClaimer = await BatchClaimer.deploy();
            await batchClaimer.deployed();

            await distributor1.setMerkleRootForEpoch(
                tree.getHexRoot(),
                EPOCH_ZERO
            );
            await distributor1.setMerkleRootForEpoch(
                tree2.getHexRoot(),
                EPOCH_ONE
            );
            await distributor2.setMerkleRootForEpoch(
                tree2.getHexRoot(),
                EPOCH_ZERO
            );

            await expect(() =>
                kwenta
                    .connect(TREASURY_DAO)
                    .transfer(distributor1.address, 2000)
            ).to.changeTokenBalance(kwenta, distributor1, 2000);
            await expect(() =>
                kwenta
                    .connect(TREASURY_DAO)
                    .transfer(distributor2.address, 2000)
            ).to.changeTokenBalance(kwenta, distributor2, 2000);
        });

        it("revert if claims length mismatch", async () => {
            let claims: any = [];
            const distributors = [distributor1.address, distributor2.address];

            await expect(
                batchClaimer.claimMultiple(distributors, claims)
            ).to.be.revertedWith("BatchClaimer: invalid input");
        });

        it("revert if distributor length mismatch", async () => {
            let claims = [];
            claims.push([
                [
                    0,
                    addr0.address,
                    100,
                    tree.getProof(0, addr0.address, BigNumber.from(100)),
                    EPOCH_ZERO,
                ],
            ]);

            claims.push([
                [
                    0,
                    addr0.address,
                    1100,
                    tree2.getProof(0, addr0.address, BigNumber.from(1100)),
                    EPOCH_ZERO,
                ],
            ]);

            const distributors: any = [];

            await expect(
                batchClaimer.claimMultiple(distributors, claims)
            ).to.be.revertedWith("BatchClaimer: invalid input");
        });

        it("can claim across distribution contracts", async () => {
            let claims = [];

            claims.push([
                [
                    0,
                    addr0.address,
                    100,
                    tree.getProof(0, addr0.address, BigNumber.from(100)),
                    EPOCH_ZERO,
                ],
            ]);

            claims.push([
                [
                    0,
                    addr0.address,
                    1100,
                    tree2.getProof(0, addr0.address, BigNumber.from(1100)),
                    EPOCH_ZERO,
                ],
            ]);

            const distributors = [distributor1.address, distributor2.address];

            await expect(batchClaimer.claimMultiple(distributors, claims))
                .to.emit(distributor1, "Claimed")
                .withArgs(0, addr0.address, 100, EPOCH_ZERO)
                .to.emit(distributor2, "Claimed")
                .withArgs(0, addr0.address, 1100, EPOCH_ZERO);

            expect(
                await rewardEscrow.escrowedBalanceOf(addr0.address)
            ).to.equal(1200);
        });

        it("can claim multiple epochs across distribution contracts", async () => {
            let claims = [];

            claims.push([
                [
                    0,
                    addr0.address,
                    100,
                    tree.getProof(0, addr0.address, BigNumber.from(100)),
                    EPOCH_ZERO,
                ],
                [
                    0,
                    addr0.address,
                    1100,
                    tree2.getProof(0, addr0.address, BigNumber.from(1100)),
                    EPOCH_ONE,
                ],
            ]);

            claims.push([
                [
                    0,
                    addr0.address,
                    1100,
                    tree2.getProof(0, addr0.address, BigNumber.from(1100)),
                    EPOCH_ZERO,
                ],
            ]);

            const distributors = [distributor1.address, distributor2.address];

            await expect(batchClaimer.claimMultiple(distributors, claims))
                .to.emit(distributor1, "Claimed")
                .withArgs(0, addr0.address, 100, EPOCH_ZERO)
                .to.emit(distributor1, "Claimed")
                .withArgs(0, addr0.address, 1100, EPOCH_ONE)
                .to.emit(distributor2, "Claimed")
                .withArgs(0, addr0.address, 1100, EPOCH_ZERO);
            expect(
                await rewardEscrow.escrowedBalanceOf(addr0.address)
            ).to.equal(2300);
        });
    });
});
