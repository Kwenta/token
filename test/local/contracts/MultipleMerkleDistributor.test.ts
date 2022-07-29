import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { Contract, BigNumber } from "ethers";
import { FakeContract, smock } from "@defi-wonderland/smock";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import BalanceTree from "../../../scripts/balance-tree";
import { parseBalanceMap } from "../../../scripts/parse-balance-map";
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
const INFLATION_DIVERSION_BPS = 2000;
const WEEKLY_START_REWARDS = 3;
const ZERO_BYTES32 =
    "0x0000000000000000000000000000000000000000000000000000000000000000";
const EPOCH_ZERO = 0;
const EPOCH_ONE = 1;

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

const loadSetup = () => {
    before("Deploy contracts", async () => {
        [owner, addr0, addr1, addr2, TREASURY_DAO] = await ethers.getSigners();

        let deployments = await deployKwenta(
            NAME,
            SYMBOL,
            INITIAL_SUPPLY,
            INFLATION_DIVERSION_BPS,
            WEEKLY_START_REWARDS,
            owner,
            TREASURY_DAO
        );
        kwenta = deployments.kwenta;
        rewardEscrow = deployments.rewardEscrow;
    });
};

describe("MultipleMerkleDistributor", () => {
    loadSetup();

    describe("kwenta", () => {
        it("returns the token address", async () => {
            const MultipleMerkleDistributor = await ethers.getContractFactory(
                "MultipleMerkleDistributor"
            );
            distributor = await MultipleMerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address
            );
            await distributor.deployed();
            expect(await distributor.token()).to.equal(kwenta.address);
            expect(await distributor.owner()).to.equal(owner.address);
        });
    });

    describe("merkleRoot", () => {
        it("returns the zero merkle root", async () => {
            const MultipleMerkleDistributor = await ethers.getContractFactory(
                "MultipleMerkleDistributor"
            );
            distributor = await MultipleMerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address
            );
            await distributor.deployed();
            expect(await distributor.merkleRoots(0)).to.equal(ZERO_BYTES32);
        });

        it("multiple roots stored and keyed by epoch", async () => {
            const tree = new BalanceTree([
                { account: addr0.address, amount: BigNumber.from(100) },
                { account: addr1.address, amount: BigNumber.from(101) },
                { account: addr2.address, amount: BigNumber.from(202) },
            ]);

            const tree2 = new BalanceTree([
                { account: addr0.address, amount: BigNumber.from(1100) },
                { account: addr1.address, amount: BigNumber.from(1101) },
                { account: addr2.address, amount: BigNumber.from(1202) },
            ]);

            const MultipleMerkleDistributor = await ethers.getContractFactory(
                "MultipleMerkleDistributor"
            );
            distributor = await MultipleMerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address
            );
            await distributor.deployed();
            await expect(distributor.newMerkleRoot(tree.getHexRoot()))
                .to.emit(distributor, "MerkleRootAdded")
                .withArgs(EPOCH_ZERO);
            await expect(distributor.newMerkleRoot(tree2.getHexRoot()))
                .to.emit(distributor, "MerkleRootAdded")
                .withArgs(EPOCH_ONE);
            expect(await distributor.merkleRoots(0)).to.equal(
                tree.getHexRoot()
            );
            expect(await distributor.merkleRoots(1)).to.equal(
                tree2.getHexRoot()
            );
        });

        it("verify roots are distinct", async () => {
            const tree = new BalanceTree([
                { account: addr0.address, amount: BigNumber.from(100) },
                { account: addr1.address, amount: BigNumber.from(101) },
                { account: addr2.address, amount: BigNumber.from(202) },
            ]);

            const tree2 = new BalanceTree([
                { account: addr0.address, amount: BigNumber.from(1100) },
                { account: addr1.address, amount: BigNumber.from(1101) },
                { account: addr2.address, amount: BigNumber.from(1202) },
            ]);

            const MultipleMerkleDistributor = await ethers.getContractFactory(
                "MultipleMerkleDistributor"
            );
            distributor = await MultipleMerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address
            );
            await distributor.deployed();
            await distributor.newMerkleRoot(tree.getHexRoot());
            await distributor.newMerkleRoot(tree2.getHexRoot());
            expect(await distributor.merkleRoots(0)).to.not.equal(
                await distributor.merkleRoots(1)
            );
        });
    });

    describe("claim", () => {
        it("fails for empty proof", async () => {
            const MultipleMerkleDistributor = await ethers.getContractFactory(
                "MultipleMerkleDistributor"
            );
            distributor = await MultipleMerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address
            );
            await distributor.deployed();

            await expect(
                distributor.claim(0, addr0.address, 10, [], 0)
            ).to.be.revertedWith("MultipleMerkleDistributor: Invalid proof.");
        });

        it("fails for invalid index", async () => {
            const MultipleMerkleDistributor = await ethers.getContractFactory(
                "MultipleMerkleDistributor"
            );
            distributor = await MultipleMerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address
            );
            await distributor.deployed();
            await distributor.newMerkleRoot(ZERO_BYTES32);

            await expect(
                distributor.claim(0, addr0.address, 10, [], 0)
            ).to.be.revertedWith("MultipleMerkleDistributor: Invalid proof.");
        });

        describe("two account tree", () => {
            let tree: BalanceTree;
            beforeEach("deploy", async () => {
                // Build tree with:
                // (1) addresses who can claim KWENTA
                // (2) amount given address can claim
                tree = new BalanceTree([
                    { account: addr0.address, amount: BigNumber.from(100) },
                    { account: addr1.address, amount: BigNumber.from(101) },
                    { account: addr2.address, amount: BigNumber.from(202) },
                ]);

                const MultipleMerkleDistributor =
                    await ethers.getContractFactory(
                        "MultipleMerkleDistributor"
                    );
                distributor = await MultipleMerkleDistributor.deploy(
                    owner.address,
                    kwenta.address,
                    rewardEscrow.address
                );
                await distributor.deployed();
                await distributor.newMerkleRoot(tree.getHexRoot());

                await expect(() =>
                    kwenta
                        .connect(TREASURY_DAO)
                        .transfer(distributor.address, 201)
                ).to.changeTokenBalance(kwenta, distributor, 201);
            });

            it("successful claim and transfer", async () => {
                const proof0 = tree.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(100)
                );

                await expect(
                    distributor.claim(0, addr0.address, 100, proof0, EPOCH_ZERO)
                )
                    .to.emit(distributor, "Claimed")
                    .withArgs(0, addr0.address, 100, EPOCH_ZERO);

                expect(await rewardEscrow.balanceOf(addr0.address)).to.equal(
                    100
                );

                const proof1 = tree.getProof(
                    1,
                    addr1.address,
                    BigNumber.from(101)
                );

                await expect(
                    distributor.claim(1, addr1.address, 101, proof1, EPOCH_ZERO)
                )
                    .to.emit(distributor, "Claimed")
                    .withArgs(1, addr1.address, 101, EPOCH_ZERO);

                expect(await rewardEscrow.balanceOf(addr1.address)).to.equal(
                    101
                );

                expect(await kwenta.balanceOf(distributor.address)).to.equal(0);
            });

            it("must have enough to transfer", async () => {
                const proof2 = tree.getProof(
                    2,
                    addr2.address,
                    BigNumber.from(202)
                );

                await expect(
                    distributor.claim(2, addr2.address, 202, proof2, EPOCH_ZERO)
                ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
            });

            it("sets #isClaimed", async () => {
                const proof0 = tree.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(100)
                );

                expect(await distributor.isClaimed(0, EPOCH_ZERO)).to.equal(
                    false
                );
                expect(await distributor.isClaimed(1, EPOCH_ZERO)).to.equal(
                    false
                );

                await distributor.claim(
                    0,
                    addr0.address,
                    100,
                    proof0,
                    EPOCH_ZERO
                );

                expect(await distributor.isClaimed(0, EPOCH_ZERO)).to.equal(
                    true
                );
                expect(await distributor.isClaimed(1, EPOCH_ZERO)).to.equal(
                    false
                );
            });

            it("cannot allow two claims", async () => {
                const proof0 = tree.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(100)
                );

                await distributor.claim(
                    0,
                    addr0.address,
                    100,
                    proof0,
                    EPOCH_ZERO
                );

                await expect(
                    distributor.claim(0, addr0.address, 100, proof0, EPOCH_ZERO)
                ).to.be.revertedWith(
                    "MultipleMerkleDistributor: Drop already claimed."
                );
            });

            it("cannot claim more than once: (index) 0 and then 1", async () => {
                await distributor.claim(
                    0,
                    addr0.address,
                    100,
                    tree.getProof(0, addr0.address, BigNumber.from(100)),
                    EPOCH_ZERO
                );

                await distributor.claim(
                    1,
                    addr1.address,
                    101,
                    tree.getProof(1, addr1.address, BigNumber.from(101)),
                    EPOCH_ZERO
                );

                await expect(
                    distributor.claim(
                        0,
                        addr0.address,
                        100,
                        tree.getProof(0, addr0.address, BigNumber.from(100)),
                        EPOCH_ZERO
                    )
                ).to.be.revertedWith(
                    "MultipleMerkleDistributor: Drop already claimed."
                );
            });

            it("cannot claim more than once: (index) 1 and then 0", async () => {
                await distributor.claim(
                    1,
                    addr1.address,
                    101,
                    tree.getProof(1, addr1.address, BigNumber.from(101)),
                    EPOCH_ZERO
                );

                await distributor.claim(
                    0,
                    addr0.address,
                    100,
                    tree.getProof(0, addr0.address, BigNumber.from(100)),
                    EPOCH_ZERO
                );

                await expect(
                    distributor.claim(
                        1,
                        addr1.address,
                        101,
                        tree.getProof(1, addr1.address, BigNumber.from(101)),
                        EPOCH_ZERO
                    )
                ).to.be.revertedWith(
                    "MultipleMerkleDistributor: Drop already claimed."
                );
            });

            it("cannot claim for address other than proof", async () => {
                const proof0 = tree.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(100)
                );

                await expect(
                    distributor.claim(1, addr1.address, 101, proof0, EPOCH_ZERO)
                ).to.be.revertedWith(
                    "MultipleMerkleDistributor: Invalid proof."
                );
            });

            it("cannot claim more than proof", async () => {
                const proof0 = tree.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(100)
                );

                await expect(
                    distributor.claim(0, addr0.address, 101, proof0, EPOCH_ZERO)
                ).to.be.revertedWith(
                    "MultipleMerkleDistributor: Invalid proof."
                );
            });
        });

        describe("multiple tree", () => {
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

                const MultipleMerkleDistributor =
                    await ethers.getContractFactory(
                        "MultipleMerkleDistributor"
                    );
                distributor = await MultipleMerkleDistributor.deploy(
                    owner.address,
                    kwenta.address,
                    rewardEscrow.address
                );
                await distributor.deployed();
                await distributor.newMerkleRoot(tree.getHexRoot());
                await distributor.newMerkleRoot(tree2.getHexRoot());

                await expect(() =>
                    kwenta
                        .connect(TREASURY_DAO)
                        .transfer(distributor.address, 2000)
                ).to.changeTokenBalance(kwenta, distributor, 2000);
            });

            it("sets #isClaimed for first epoch only", async () => {
                const proof0 = tree.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(100)
                );

                expect(await distributor.isClaimed(0, EPOCH_ZERO)).to.equal(
                    false
                );
                expect(await distributor.isClaimed(0, EPOCH_ONE)).to.equal(
                    false
                );

                await distributor.claim(
                    0,
                    addr0.address,
                    100,
                    proof0,
                    EPOCH_ZERO
                );

                expect(await distributor.isClaimed(0, EPOCH_ZERO)).to.equal(
                    true
                );
                expect(await distributor.isClaimed(0, EPOCH_ONE)).to.equal(
                    false
                );
            });

            it("can claim epoch1 even if claimed epoch0", async () => {
                const proofEpoch0 = tree.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(100)
                );

                await expect(
                    distributor.claim(
                        0,
                        addr0.address,
                        100,
                        proofEpoch0,
                        EPOCH_ZERO
                    )
                )
                    .to.emit(distributor, "Claimed")
                    .withArgs(0, addr0.address, 100, EPOCH_ZERO);

                const proofEpoch1 = tree2.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(1100)
                );

                await expect(
                    distributor.claim(
                        0,
                        addr0.address,
                        1100,
                        proofEpoch1,
                        EPOCH_ONE
                    )
                )
                    .to.emit(distributor, "Claimed")
                    .withArgs(0, addr0.address, 1100, EPOCH_ONE);
            });

            it("can claim epoch0 even if claimed epoch1 (reverse)", async () => {
                const proofEpoch1 = tree2.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(1100)
                );

                await expect(
                    distributor.claim(
                        0,
                        addr0.address,
                        1100,
                        proofEpoch1,
                        EPOCH_ONE
                    )
                )
                    .to.emit(distributor, "Claimed")
                    .withArgs(0, addr0.address, 1100, EPOCH_ONE);

                const proofEpoch0 = tree.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(100)
                );

                await expect(
                    distributor.claim(
                        0,
                        addr0.address,
                        100,
                        proofEpoch0,
                        EPOCH_ZERO
                    )
                )
                    .to.emit(distributor, "Claimed")
                    .withArgs(0, addr0.address, 100, EPOCH_ZERO);
            });

            it("can claim epoch0, but not eligible for epoch1", async () => {
                const proofEpoch0 = tree.getProof(
                    2,
                    addr2.address,
                    BigNumber.from(202)
                );

                await expect(
                    distributor.claim(
                        2,
                        addr2.address,
                        202,
                        proofEpoch0,
                        EPOCH_ZERO
                    )
                )
                    .to.emit(distributor, "Claimed")
                    .withArgs(2, addr2.address, 202, EPOCH_ZERO);

                // attempt to claim epoch1 for another address with epoch0 proof
                await expect(
                    distributor.claim(
                        2,
                        addr2.address,
                        202,
                        proofEpoch0,
                        EPOCH_ONE
                    )
                ).to.be.revertedWith(
                    "MultipleMerkleDistributor: Invalid proof."
                );
            });
        });

        describe("larger tree", () => {
            let tree: BalanceTree;
            let accounts: SignerWithAddress[];

            beforeEach("deploy", async () => {
                accounts = await ethers.getSigners();

                // Build tree with:
                // (1) all signers provided by ethers.getSigners()
                tree = new BalanceTree(
                    accounts.map((account, ix) => {
                        return {
                            account: account.address,
                            amount: BigNumber.from(ix + 1),
                        };
                    })
                );

                const MultipleMerkleDistributor =
                    await ethers.getContractFactory(
                        "MultipleMerkleDistributor"
                    );
                distributor = await MultipleMerkleDistributor.deploy(
                    owner.address,
                    kwenta.address,
                    rewardEscrow.address
                );
                await distributor.deployed();
                await distributor.newMerkleRoot(tree.getHexRoot());

                await expect(() =>
                    kwenta
                        .connect(TREASURY_DAO)
                        .transfer(distributor.address, 100)
                ).to.changeTokenBalance(kwenta, distributor, 100);
            });

            it("claim index 4", async () => {
                const proof = tree.getProof(
                    4,
                    accounts[4].address,
                    BigNumber.from(5)
                );

                await expect(
                    distributor.claim(
                        4,
                        accounts[4].address,
                        5,
                        proof,
                        EPOCH_ZERO
                    )
                )
                    .to.emit(distributor, "Claimed")
                    .withArgs(4, accounts[4].address, 5, EPOCH_ZERO);
            });

            it("claim index 9", async () => {
                const proof = tree.getProof(
                    9,
                    accounts[9].address,
                    BigNumber.from(10)
                );

                await expect(
                    distributor.claim(
                        9,
                        accounts[9].address,
                        10,
                        proof,
                        EPOCH_ZERO
                    )
                )
                    .to.emit(distributor, "Claimed")
                    .withArgs(9, accounts[9].address, 10, EPOCH_ZERO);
            });
        });

        describe("realistic size tree", () => {
            let tree: BalanceTree;
            const NUM_LEAVES = 100_000;
            const NUM_SAMPLES = 25;
            const elements: { account: string; amount: BigNumber }[] = [];

            let addr1Address = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";

            for (let i = 0; i < NUM_LEAVES; i++) {
                const node = {
                    account: addr1Address,
                    amount: BigNumber.from(100),
                };
                elements.push(node);
            }

            tree = new BalanceTree(elements);

            it("proof verification works", () => {
                const root = Buffer.from(tree.getHexRoot().slice(2), "hex");
                for (let i = 0; i < NUM_LEAVES; i += NUM_LEAVES / NUM_SAMPLES) {
                    const proof = tree
                        .getProof(i, addr0.address, BigNumber.from(100))
                        .map((el) => Buffer.from(el.slice(2), "hex"));
                    const validProof = BalanceTree.verifyProof(
                        i,
                        addr0.address,
                        BigNumber.from(100),
                        proof,
                        root
                    );
                    expect(validProof).to.be.true;
                }
            });

            beforeEach("deploy", async () => {
                const MultipleMerkleDistributor =
                    await ethers.getContractFactory(
                        "MultipleMerkleDistributor"
                    );
                distributor = await MultipleMerkleDistributor.deploy(
                    owner.address,
                    kwenta.address,
                    rewardEscrow.address
                );
                await distributor.deployed();
                await distributor.newMerkleRoot(tree.getHexRoot());

                await expect(() =>
                    kwenta
                        .connect(TREASURY_DAO)
                        .transfer(distributor.address, 300_000)
                ).to.changeTokenBalance(kwenta, distributor, 300_000);
            });

            it("no double claims in random distribution", async () => {
                for (
                    let i = 0;
                    i < 25;
                    i += Math.floor(Math.random() * (NUM_LEAVES / NUM_SAMPLES))
                ) {
                    const proof = tree.getProof(
                        i,
                        addr0.address,
                        BigNumber.from(100)
                    );
                    await distributor.claim(
                        i,
                        addr0.address,
                        100,
                        proof,
                        EPOCH_ZERO
                    );
                    await expect(
                        distributor.claim(
                            i,
                            addr0.address,
                            100,
                            proof,
                            EPOCH_ZERO
                        )
                    ).to.be.revertedWith(
                        "MultipleMerkleDistributor: Drop already claimed."
                    );
                }
            });
        });
    });

    describe("parseBalanceMap", () => {
        let accounts: SignerWithAddress[];

        let claims: {
            [account: string]: {
                index: number;
                amount: string;
                proof: string[];
            };
        };

        beforeEach("deploy", async () => {
            accounts = await ethers.getSigners();

            const {
                claims: innerClaims,
                merkleRoot,
                tokenTotal,
            } = parseBalanceMap({
                [accounts[0].address]: 200,
                [accounts[1].address]: 300,
                [accounts[2].address]: 250,
            });

            expect(tokenTotal).to.equal("0x02ee"); // 750

            claims = innerClaims;

            const MultipleMerkleDistributor = await ethers.getContractFactory(
                "MultipleMerkleDistributor"
            );
            distributor = await MultipleMerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address
            );
            await distributor.deployed();
            await distributor.newMerkleRoot(merkleRoot);

            await expect(() =>
                kwenta
                    .connect(TREASURY_DAO)
                    .transfer(distributor.address, tokenTotal)
            ).to.changeTokenBalance(kwenta, distributor, tokenTotal);
        });

        it("all claims work exactly once", async () => {
            for (let account in claims) {
                const claim = claims[account];
                await expect(
                    distributor.claim(
                        claim.index,
                        account,
                        claim.amount,
                        claim.proof,
                        EPOCH_ZERO
                    )
                )
                    .to.emit(distributor, "Claimed")
                    .withArgs(claim.index, account, claim.amount, EPOCH_ZERO);
                await expect(
                    distributor.claim(
                        claim.index,
                        account,
                        claim.amount,
                        claim.proof,
                        EPOCH_ZERO
                    )
                ).to.be.revertedWith(
                    "MultipleMerkleDistributor: Drop already claimed."
                );
            }
            expect(await kwenta.balanceOf(distributor.address)).to.equal(0);
        });
    });
});
