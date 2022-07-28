import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { Contract, BigNumber } from "ethers";
import { FakeContract, smock } from "@defi-wonderland/smock";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import BalanceTree from "../../../scripts/balance-tree";
import { parseBalanceMap } from "../../../scripts/parse-balance-map";
import { deployKwenta } from "../../utils/kwenta";
import L2CrossDomainMessenger from "@eth-optimism/contracts/artifacts/contracts/L2/messaging/L2CrossDomainMessenger.sol/L2CrossDomainMessenger.json";

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

// mock contracts
let crossDomainMessenger: FakeContract;

// multisig testing
// CrossDomainMessenger address on L2
const CD_MESSENGER_ADDR = "0x4200000000000000000000000000000000000007";
// account on L2 which will effectively receive $KWENTA
let accountClaimedTo: SignerWithAddress;
// controlL2MerkleDistributor on L1
let xDomainMessageSender: SignerWithAddress;

const loadSetup = () => {
    before("Deploy contracts", async () => {
        [
            owner,
            addr0,
            addr1,
            addr2,
            TREASURY_DAO,
            accountClaimedTo,
            xDomainMessageSender,
        ] = await ethers.getSigners();

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

        // mock L2CrossDomainMessenger at proper address
        crossDomainMessenger = await smock.fake(L2CrossDomainMessenger, {
            address: CD_MESSENGER_ADDR,
        });

        // mock crossDomainMessenger.xDomainMessageSender()
        // @dev it is called to ensure msg.sender on L1 is valid
        crossDomainMessenger.xDomainMessageSender.returns(
            xDomainMessageSender.address
        );
    });
};

describe("MerkleDistributor", () => {
    loadSetup();

    describe("kwenta", () => {
        it("returns the token address", async () => {
            const MerkleDistributor = await ethers.getContractFactory(
                "MerkleDistributor"
            );
            distributor = await MerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address,
                ZERO_BYTES32
            );
            await distributor.deployed();
            expect(await distributor.token()).to.equal(kwenta.address);
            expect(await distributor.owner()).to.equal(owner.address);
        });
    });

    describe("merkleRoot", () => {
        it("returns the zero merkle root", async () => {
            const MerkleDistributor = await ethers.getContractFactory(
                "MerkleDistributor"
            );
            distributor = await MerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address,
                ZERO_BYTES32
            );
            await distributor.deployed();
            expect(await distributor.merkleRoot()).to.equal(ZERO_BYTES32);
        });
    });

    describe("claim", () => {
        it("fails for empty proof", async () => {
            const MerkleDistributor = await ethers.getContractFactory(
                "MerkleDistributor"
            );
            distributor = await MerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address,
                ZERO_BYTES32
            );
            await distributor.deployed();
            await expect(
                distributor.claim(0, addr0.address, 10, [])
            ).to.be.revertedWith("MerkleDistributor: Invalid proof.");
        });

        it("fails for invalid index", async () => {
            const MerkleDistributor = await ethers.getContractFactory(
                "MerkleDistributor"
            );
            distributor = await MerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address,
                ZERO_BYTES32
            );
            await distributor.deployed();
            await expect(
                distributor.claim(0, addr0.address, 10, [])
            ).to.be.revertedWith("MerkleDistributor: Invalid proof.");
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

                const MerkleDistributor = await ethers.getContractFactory(
                    "MerkleDistributor"
                );
                distributor = await MerkleDistributor.deploy(
                    owner.address,
                    kwenta.address,
                    rewardEscrow.address,
                    tree.getHexRoot()
                );
                await distributor.deployed();

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

                await expect(distributor.claim(0, addr0.address, 100, proof0))
                    .to.emit(distributor, "Claimed")
                    .withArgs(0, addr0.address, 100);

                expect(await rewardEscrow.balanceOf(addr0.address)).to.equal(
                    100
                );

                const proof1 = tree.getProof(
                    1,
                    addr1.address,
                    BigNumber.from(101)
                );

                await expect(distributor.claim(1, addr1.address, 101, proof1))
                    .to.emit(distributor, "Claimed")
                    .withArgs(1, addr1.address, 101);

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
                    distributor.claim(2, addr2.address, 202, proof2)
                ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
            });

            it("sets #isClaimed", async () => {
                const proof0 = tree.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(100)
                );

                expect(await distributor.isClaimed(0)).to.equal(false);
                expect(await distributor.isClaimed(1)).to.equal(false);

                await distributor.claim(0, addr0.address, 100, proof0);

                expect(await distributor.isClaimed(0)).to.equal(true);
                expect(await distributor.isClaimed(1)).to.equal(false);
            });

            it("cannot allow two claims", async () => {
                const proof0 = tree.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(100)
                );

                await distributor.claim(0, addr0.address, 100, proof0);

                await expect(
                    distributor.claim(0, addr0.address, 100, proof0)
                ).to.be.revertedWith(
                    "MerkleDistributor: Drop already claimed."
                );
            });

            it("cannot claim more than once: (index) 0 and then 1", async () => {
                await distributor.claim(
                    0,
                    addr0.address,
                    100,
                    tree.getProof(0, addr0.address, BigNumber.from(100))
                );

                await distributor.claim(
                    1,
                    addr1.address,
                    101,
                    tree.getProof(1, addr1.address, BigNumber.from(101))
                );

                await expect(
                    distributor.claim(
                        0,
                        addr0.address,
                        100,
                        tree.getProof(0, addr0.address, BigNumber.from(100))
                    )
                ).to.be.revertedWith(
                    "MerkleDistributor: Drop already claimed."
                );
            });

            it("cannot claim more than once: (index) 1 and then 0", async () => {
                await distributor.claim(
                    1,
                    addr1.address,
                    101,
                    tree.getProof(1, addr1.address, BigNumber.from(101))
                );

                await distributor.claim(
                    0,
                    addr0.address,
                    100,
                    tree.getProof(0, addr0.address, BigNumber.from(100))
                );

                await expect(
                    distributor.claim(
                        1,
                        addr1.address,
                        101,
                        tree.getProof(1, addr1.address, BigNumber.from(101))
                    )
                ).to.be.revertedWith(
                    "MerkleDistributor: Drop already claimed."
                );
            });

            it("cannot claim for address other than proof", async () => {
                const proof0 = tree.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(100)
                );

                await expect(
                    distributor.claim(1, addr1.address, 101, proof0)
                ).to.be.revertedWith("MerkleDistributor: Invalid proof.");
            });

            it("cannot claim more than proof", async () => {
                const proof0 = tree.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(100)
                );

                await expect(
                    distributor.claim(0, addr0.address, 101, proof0)
                ).to.be.revertedWith("MerkleDistributor: Invalid proof.");
            });

            it.skip("gas", async () => {
                const proof = tree.getProof(
                    0,
                    addr0.address,
                    BigNumber.from(100)
                );
                const tx = await distributor.claim(
                    0,
                    addr0.address,
                    100,
                    proof
                );
                const receipt = await tx.wait();
                expect(receipt.gasUsed).to.equal(196836);
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

                const MerkleDistributor = await ethers.getContractFactory(
                    "MerkleDistributor"
                );
                distributor = await MerkleDistributor.deploy(
                    owner.address,
                    kwenta.address,
                    rewardEscrow.address,
                    tree.getHexRoot()
                );
                await distributor.deployed();

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
                    distributor.claim(4, accounts[4].address, 5, proof)
                )
                    .to.emit(distributor, "Claimed")
                    .withArgs(4, accounts[4].address, 5);
            });

            it("claim index 9", async () => {
                const proof = tree.getProof(
                    9,
                    accounts[9].address,
                    BigNumber.from(10)
                );

                await expect(
                    distributor.claim(9, accounts[9].address, 10, proof)
                )
                    .to.emit(distributor, "Claimed")
                    .withArgs(9, accounts[9].address, 10);
            });

            it.skip("gas", async () => {
                const proof = tree.getProof(
                    9,
                    accounts[9].address,
                    BigNumber.from(10)
                );
                const tx = await distributor.claim(
                    9,
                    accounts[9].address,
                    10,
                    proof
                );
                const receipt = await tx.wait();
                expect(receipt.gasUsed).to.eq(200629);
            });

            it.skip("gas second down about 15k", async () => {
                await distributor.claim(
                    0,
                    accounts[0].address,
                    1,
                    tree.getProof(0, accounts[0].address, BigNumber.from(1))
                );

                const tx = await distributor.claim(
                    1,
                    accounts[1].address,
                    2,
                    tree.getProof(1, accounts[1].address, BigNumber.from(2))
                );
                const receipt = await tx.wait();
                expect(receipt.gasUsed).to.eq(183529);
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
                const MerkleDistributor = await ethers.getContractFactory(
                    "MerkleDistributor"
                );
                distributor = await MerkleDistributor.deploy(
                    owner.address,
                    kwenta.address,
                    rewardEscrow.address,
                    tree.getHexRoot()
                );
                await distributor.deployed();

                await expect(() =>
                    kwenta
                        .connect(TREASURY_DAO)
                        .transfer(distributor.address, 300_000)
                ).to.changeTokenBalance(kwenta, distributor, 300_000);
            });

            it.skip("gas", async () => {
                const proof = tree.getProof(
                    50000,
                    addr0.address,
                    BigNumber.from(100)
                );
                const tx = await distributor.claim(
                    50000,
                    addr0.address,
                    100,
                    proof
                );
                const receipt = await tx.wait();
                expect(receipt.gasUsed).to.eq(215723);
            });

            it.skip("gas deeper node", async () => {
                const proof = tree.getProof(
                    90000,
                    addr0.address,
                    BigNumber.from(100)
                );

                const tx = await distributor.claim(
                    90000,
                    addr0.address,
                    100,
                    proof
                );
                const receipt = await tx.wait();
                expect(receipt.gasUsed).to.eq(215757);
            });

            it.skip("gas average random distribution", async () => {
                let total: BigNumber = BigNumber.from(0);
                let count: number = 0;
                for (let i = 0; i < NUM_LEAVES; i += NUM_LEAVES / NUM_SAMPLES) {
                    const proof = tree.getProof(
                        i,
                        addr0.address,
                        BigNumber.from(100)
                    );
                    const tx = await distributor.claim(
                        i,
                        addr0.address,
                        100,
                        proof
                    );
                    const receipt = await tx.wait();
                    total = total.add(receipt.gasUsed);
                    count++;
                }
                const average = total.div(count);
                expect(average).to.eq(215710);
            });

            // this is what we gas golfed by packing the bitmap
            it.skip("gas average first 25", async () => {
                let total: BigNumber = BigNumber.from(0);
                let count: number = 0;
                for (let i = 0; i < 25; i++) {
                    const proof = tree.getProof(
                        i,
                        addr0.address,
                        BigNumber.from(100)
                    );
                    const tx = await distributor.claim(
                        i,
                        addr0.address,
                        100,
                        proof
                    );
                    const receipt = await tx.wait();
                    total = total.add(receipt.gasUsed);
                    count++;
                }
                const average = total.div(count);
                expect(average).to.eq(199283);
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
                    await distributor.claim(i, addr0.address, 100, proof);
                    await expect(
                        distributor.claim(i, addr0.address, 100, proof)
                    ).to.be.revertedWith(
                        "MerkleDistributor: Drop already claimed."
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

            const MerkleDistributor = await ethers.getContractFactory(
                "MerkleDistributor"
            );
            distributor = await MerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address,
                merkleRoot
            );
            await distributor.deployed();

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
                        claim.proof
                    )
                )
                    .to.emit(distributor, "Claimed")
                    .withArgs(claim.index, account, claim.amount);
                await expect(
                    distributor.claim(
                        claim.index,
                        account,
                        claim.amount,
                        claim.proof
                    )
                ).to.be.revertedWith(
                    "MerkleDistributor: Drop already claimed."
                );
            }
            expect(await kwenta.balanceOf(distributor.address)).to.equal(0);
        });
    });

    describe("claimToAddress", () => {
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
                [accounts[0].address]: 200, // L1 account which is used in merkle proof
            });

            expect(tokenTotal).to.equal("0xc8"); // 200

            claims = innerClaims;

            const MerkleDistributor = await ethers.getContractFactory(
                "MerkleDistributor"
            );
            distributor = await MerkleDistributor.deploy(
                owner.address,
                kwenta.address,
                rewardEscrow.address,
                merkleRoot
            );
            await distributor.deployed();

            await expect(() =>
                kwenta
                    .connect(TREASURY_DAO)
                    .transfer(distributor.address, tokenTotal)
            ).to.changeTokenBalance(kwenta, distributor, tokenTotal);
        });

        it("cannot claim when ControlL2MerkleDistributor has not been set", async () => {
            // get claim for L1 address
            const claim = claims[accounts[0].address];

            await hre.network.provider.send("hardhat_setBalance", [
                crossDomainMessenger.address,
                ethers.utils.parseEther("10").toHexString(),
            ]);
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [crossDomainMessenger.address],
            });
            const crossDomainMessengerSigner = await ethers.getSigner(
                crossDomainMessenger.address
            );

            //await distributor.connect(owner).setControlL2MerkleDistributor(xDomainMessageSender.address);

            // call MerkleDistributor.claimToAddress from crossDomainMessenger
            await expect(
                distributor
                    .connect(crossDomainMessengerSigner)
                    .claimToAddress(
                        claim.index,
                        accounts[0].address,
                        accountClaimedTo.address,
                        claim.amount,
                        claim.proof
                    )
            ).to.be.revertedWith(
                "MerkleDistributor: controlL2MerkleDistributor has not been set by owner"
            );
        });

        it("claim works when called by CrossDomainMessenger", async () => {
            // get claim for L1 address
            const claim = claims[accounts[0].address];

            await hre.network.provider.send("hardhat_setBalance", [
                crossDomainMessenger.address,
                ethers.utils.parseEther("10").toHexString(),
            ]);
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [crossDomainMessenger.address],
            });
            const crossDomainMessengerSigner = await ethers.getSigner(
                crossDomainMessenger.address
            );

            await distributor
                .connect(owner)
                .setControlL2MerkleDistributor(xDomainMessageSender.address);

            // call MerkleDistributor.claimToAddress from crossDomainMessenger
            expect(
                await distributor
                    .connect(crossDomainMessengerSigner)
                    .claimToAddress(
                        claim.index,
                        accounts[0].address,
                        accountClaimedTo.address,
                        claim.amount,
                        claim.proof
                    )
            )
                .to.emit(distributor, "Claimed")
                .withArgs(
                    claim.index,
                    xDomainMessageSender.address,
                    claim.amount
                );

            // expect new entry for accountClaimedTo in reward escrow for correct amount
            expect(
                await rewardEscrow.balanceOf(accountClaimedTo.address)
            ).to.equal(200);
        });
    });
});
