import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { Contract, BigNumber, constants } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { wei } from '@synthetixio/wei';
import { FakeContract, smock } from '@defi-wonderland/smock';
import { IExchanger } from '../../typechain/IExchanger';
import { ISynthetix } from '../../typechain/ISynthetix';
import { IAddressResolver } from '../../typechain/IAddressResolver';
import BalanceTree from '../../src/balance-tree';
import { parseBalanceMap } from '../../src/parse-balance-map';

// constants
const NAME = 'Kwenta';
const SYMBOL = 'KWENTA';
const INITIAL_SUPPLY = ethers.utils.parseUnits('313373');
const INFLATION_DIVERSION_BPS = 2000;
const WEEKLY_START_REWARDS = 3;
const SECONDS_IN_WEEK = 6048000;
const ZERO_BYTES32 =
	'0x0000000000000000000000000000000000000000000000000000000000000000';

// test accounts
let owner: SignerWithAddress;
let addr1: SignerWithAddress;
let addr2: SignerWithAddress;
let TREASURY_DAO: SignerWithAddress;

// core contracts
let kwenta: Contract;
let supplySchedule: Contract;
let rewardEscrow: Contract;
let stakingRewardsProxy: Contract;
let exchangerProxy: Contract;
let distributor: Contract;

// library contracts
let fixidityLib: Contract;
let logarithmLib: Contract;
let exponentLib: Contract;

// util contracts
let safeDecimalMath: Contract;

// fake contracts
let fakeAddressResolver: FakeContract;

// time/fast-forwarding Helper Methods
const fastForward = async (sec: number) => {
	const blockNumber = await ethers.provider.getBlockNumber();
	const block = await ethers.provider.getBlock(blockNumber);
	const currTime = block.timestamp;
	await ethers.provider.send('evm_mine', [currTime + sec]);
};

// Mock Synthetix AddressResolver
const mockAddressResolver = async () => {
	const FEE = wei(10).toBN();

	const fakeSynthetix = await smock.fake<ISynthetix>('ISynthetix');
	fakeSynthetix.exchangeWithTracking.returns(FEE);

	const fakeExchanger = await smock.fake<IExchanger>('IExchanger');
	fakeExchanger.feeRateForExchange.returns(FEE);

	const fakeAddressResolver = await smock.fake<IAddressResolver>(
		'IAddressResolver'
	);
	fakeAddressResolver.requireAndGetAddress.reverts();
	fakeAddressResolver.requireAndGetAddress
		.whenCalledWith(
			ethers.utils.formatBytes32String('Synthetix'),
			'Could not get Synthetix'
		)
		.returns(fakeSynthetix.address);
	fakeAddressResolver.requireAndGetAddress
		.whenCalledWith(
			ethers.utils.formatBytes32String('Exchanger'),
			'Could not get Exchanger'
		)
		.returns(fakeExchanger.address);

	return fakeAddressResolver;
};

// StakingRewards: fund with KWENTA and set the rewards
const fundAndSetStakingRewards = async () => {
	// fund StakingRewards with KWENTA
	const rewards = wei(100000).toBN();
	await expect(() =>
		kwenta
			.connect(TREASURY_DAO)
			.transfer(stakingRewardsProxy.address, rewards)
	).to.changeTokenBalance(kwenta, stakingRewardsProxy, rewards);

	// set the rewards for the next epoch (1)
	await stakingRewardsProxy.setRewardNEpochs(rewards, 1);
};

const loadSetup = () => {
	before('Deploy contracts', async () => {
		[owner, addr1, addr2, TREASURY_DAO] = await ethers.getSigners();

		// deploy FixidityLib
		const FixidityLib = await ethers.getContractFactory('FixidityLib');
		fixidityLib = await FixidityLib.deploy();
		await fixidityLib.deployed();

		// deploy LogarithmLib
		const LogarithmLib = await ethers.getContractFactory('LogarithmLib', {
			libraries: {
				FixidityLib: fixidityLib.address,
			},
		});
		logarithmLib = await LogarithmLib.deploy();
		await logarithmLib.deployed();

		// deploy ExponentLib
		const ExponentLib = await ethers.getContractFactory('ExponentLib', {
			libraries: {
				FixidityLib: fixidityLib.address,
				LogarithmLib: logarithmLib.address,
			},
		});
		exponentLib = await ExponentLib.deploy();
		await exponentLib.deployed();

		// deploy SafeDecimalMath
		const SafeDecimalMath = await ethers.getContractFactory(
			'SafeDecimalMathV5'
		);
		safeDecimalMath = await SafeDecimalMath.deploy();
		await safeDecimalMath.deployed();

		// deploy SupplySchedule
		const SupplySchedule = await ethers.getContractFactory('SupplySchedule', {
			libraries: {
				SafeDecimalMathV5: safeDecimalMath.address,
			},
		});
		supplySchedule = await SupplySchedule.deploy(owner.address);
		await supplySchedule.deployed();

		// deploy Kwenta
		const Kwenta = await ethers.getContractFactory('Kwenta');
		kwenta = await Kwenta.deploy(
			NAME,
			SYMBOL,
			INITIAL_SUPPLY,
			owner.address,
			TREASURY_DAO.address,
			supplySchedule.address,
			INFLATION_DIVERSION_BPS
		);
		await kwenta.deployed();
		await supplySchedule.setKwenta(kwenta.address);

		// deploy RewardEscrow
		const RewardEscrow = await ethers.getContractFactory('RewardEscrow');
		rewardEscrow = await RewardEscrow.deploy(owner.address, kwenta.address);
		await rewardEscrow.deployed();

		// deploy StakingRewards
		const StakingRewards = await ethers.getContractFactory('StakingRewards', {
			libraries: {
				ExponentLib: exponentLib.address,
				FixidityLib: fixidityLib.address,
			},
		});

		// deploy UUPS Proxy using hardhat upgrades from OpenZeppelin
		stakingRewardsProxy = await upgrades.deployProxy(
			StakingRewards,
			[
				owner.address,
				kwenta.address,
				kwenta.address,
				rewardEscrow.address,
				WEEKLY_START_REWARDS,
			],
			{
				kind: 'uups',
				unsafeAllow: ['external-library-linking'],
			}
		);
		await stakingRewardsProxy.deployed();

		// get the address from the implementation (Staking Rewards Logic deployed)
		let stakingRewardsProxyLogicAddress =
			await upgrades.erc1967.getImplementationAddress(
				stakingRewardsProxy.address
			);

		// set StakingRewards address in Kwenta token
		await kwenta.setStakingRewards(stakingRewardsProxy.address);

		// set StakingRewards address in RewardEscrow
		await rewardEscrow.setStakingRewards(stakingRewardsProxy.address);

		// Mock AddressResolver
		fakeAddressResolver = await mockAddressResolver();

		// deploy ExchangerProxy
		const ExchangerProxy = await ethers.getContractFactory('ExchangerProxy');
		exchangerProxy = await ExchangerProxy.deploy(
			fakeAddressResolver.address,
			stakingRewardsProxy.address
		);
		await exchangerProxy.deployed();

		// set ExchangerProxy address in StakingRewards
		await stakingRewardsProxy.setExchangerProxy(exchangerProxy.address);
	});
};

describe('MerkleDistributor', () => {
	loadSetup();

	describe('kwenta', () => {
		it('returns the token address', async () => {
			const MerkleDistributor = await ethers.getContractFactory(
				'MerkleDistributor'
			);
			distributor = await MerkleDistributor.deploy(
				kwenta.address,
				ZERO_BYTES32
			);
			await distributor.deployed();
			expect(await distributor.token()).to.equal(kwenta.address);
		});
	});

	describe('merkleRoot', () => {
		it('returns the zero merkle root', async () => {
			const MerkleDistributor = await ethers.getContractFactory(
				'MerkleDistributor'
			);
			distributor = await MerkleDistributor.deploy(
				kwenta.address,
				ZERO_BYTES32
			);
			await distributor.deployed();
			expect(await distributor.merkleRoot()).to.equal(ZERO_BYTES32);
		});
	});

	describe('claim', () => {
		it('fails for empty proof', async () => {
			const MerkleDistributor = await ethers.getContractFactory(
				'MerkleDistributor'
			);
			distributor = await MerkleDistributor.deploy(
				kwenta.address,
				ZERO_BYTES32
			);
			await distributor.deployed();
			await expect(
				distributor.claim(0, addr1.address, 10, [])
			).to.be.revertedWith('MerkleDistributor: Invalid proof.');
		});

		it('fails for invalid index', async () => {
			const MerkleDistributor = await ethers.getContractFactory(
				'MerkleDistributor'
			);
			distributor = await MerkleDistributor.deploy(
				kwenta.address,
				ZERO_BYTES32
			);
			await distributor.deployed();
			await expect(
				distributor.claim(0, addr1.address, 10, [])
			).to.be.revertedWith('MerkleDistributor: Invalid proof.');
		});

		describe('two account tree', () => {
			let tree: BalanceTree;
			beforeEach('deploy', async () => {
				// Build tree with:
				// (1) addresses who can claim KWENTA
				// (2) amount given address can claim
				tree = new BalanceTree([
					{ account: addr1.address, amount: BigNumber.from(100) },
					{ account: addr2.address, amount: BigNumber.from(101) },
				]);

				const MerkleDistributor = await ethers.getContractFactory(
					'MerkleDistributor'
				);
				distributor = await MerkleDistributor.deploy(
					kwenta.address,
					tree.getHexRoot()
				);
				await distributor.deployed();
			});

			it('successful claim and transfer', async () => {
				// fund distributor
				await expect(() =>
					kwenta.connect(TREASURY_DAO).transfer(distributor.address, 201)
				).to.changeTokenBalance(kwenta, distributor, 201);

				// generate merkle proof for addr1.address
				const proof1 = tree.getProof(0, addr1.address, BigNumber.from(100));
				// addr1 claims KWENTA
				await expect(distributor.claim(0, addr1.address, 100, proof1))
					.to.emit(distributor, 'Claimed')
					.withArgs(0, addr1.address, 100);
				expect(await kwenta.balanceOf(addr1.address)).to.equal(100);

				// generate merkle proof for addr2.address
				const proof2 = tree.getProof(1, addr2.address, BigNumber.from(101));
				// addr2 claims KWENTA
				await expect(distributor.claim(1, addr2.address, 101, proof2))
					.to.emit(distributor, 'Claimed')
					.withArgs(1, addr2.address, 101);
				expect(await kwenta.balanceOf(addr2.address)).to.equal(101);

				expect(await kwenta.balanceOf(distributor.address)).to.equal(0);
			});

			it('must have enough to transfer', async () => {
				// fund distributor
				await expect(() =>
					kwenta.connect(TREASURY_DAO).transfer(distributor.address, 99)
				).to.changeTokenBalance(kwenta, distributor, 99);

				// generate merkle proof for addr1.address
				const proof1 = tree.getProof(0, addr1.address, BigNumber.from(100));
				// addr1 claims KWENTA
				await expect(
					distributor.claim(0, addr1.address, 100, proof1)
				).to.be.revertedWith('ERC20: transfer amount exceeds balance');
			});

			it('sets #isClaimed', async () => {
				// fund distributor
				await expect(() =>
					kwenta.connect(TREASURY_DAO).transfer(distributor.address, 100)
				).to.changeTokenBalance(kwenta, distributor, 100);

				// generate merkle proof for addr1.address
				const proof1 = tree.getProof(0, addr1.address, BigNumber.from(100));

				expect(await distributor.isClaimed(0)).to.equal(false);
				expect(await distributor.isClaimed(1)).to.equal(false);

				// addr1 claims KWENTA
				await distributor.claim(0, addr1.address, 100, proof1);

				expect(await distributor.isClaimed(0)).to.equal(true);
				expect(await distributor.isClaimed(1)).to.equal(false);
			});

			it('cannot allow two claims', async () => {
				// fund distributor
				await expect(() =>
					kwenta.connect(TREASURY_DAO).transfer(distributor.address, 100)
				).to.changeTokenBalance(kwenta, distributor, 100);

				// generate merkle proof for addr1.address
				const proof1 = tree.getProof(0, addr1.address, BigNumber.from(100));
				// addr1 claims KWENTA
				await distributor.claim(0, addr1.address, 100, proof1);
				// addr1 attempts to claim KWENTA (again)
				await expect(
					distributor.claim(0, addr1.address, 100, proof1)
				).to.be.revertedWith('MerkleDistributor: Drop already claimed.');
			});

			it('cannot claim more than once: (index) 0 and then 1', async () => {
				// fund distributor
				await expect(() =>
					kwenta.connect(TREASURY_DAO).transfer(distributor.address, 201)
				).to.changeTokenBalance(kwenta, distributor, 201);

				// addr1 claims KWENTA
				await distributor.claim(
					0,
					addr1.address,
					100,
					tree.getProof(0, addr1.address, BigNumber.from(100))
				);
				// addr2 claims KWENTA
				await distributor.claim(
					1,
					addr2.address,
					101,
					tree.getProof(1, addr2.address, BigNumber.from(101))
				);

				// addr1 attempts to claim KWENTA (again)
				await expect(
					distributor.claim(
						0,
						addr1.address,
						100,
						tree.getProof(0, addr1.address, BigNumber.from(100))
					)
				).to.be.revertedWith('MerkleDistributor: Drop already claimed.');
			});

			it('cannot claim more than once: (index) 1 and then 0', async () => {
				// fund distributor
				await expect(() =>
					kwenta.connect(TREASURY_DAO).transfer(distributor.address, 201)
				).to.changeTokenBalance(kwenta, distributor, 201);

				// addr2 claims KWENTA
				await distributor.claim(
					1,
					addr2.address,
					101,
					tree.getProof(1, addr2.address, BigNumber.from(101))
				);
				// addr1 claims KWENTA
				await distributor.claim(
					0,
					addr1.address,
					100,
					tree.getProof(0, addr1.address, BigNumber.from(100))
				);

				// addr2 attempts to claim KWENTA (again)
				await expect(
					distributor.claim(
						1,
						addr2.address,
						101,
						tree.getProof(1, addr2.address, BigNumber.from(101))
					)
				).to.be.revertedWith('MerkleDistributor: Drop already claimed.');
			});

			it('cannot claim for address other than proof', async () => {
				// fund distributor
				await expect(() =>
					kwenta.connect(TREASURY_DAO).transfer(distributor.address, 201)
				).to.changeTokenBalance(kwenta, distributor, 201);

				// generate merkle proof for addr1.address
				const proof1 = tree.getProof(0, addr1.address, BigNumber.from(100));

				// addr2 attempts to claim KWENTA with addr1's proof
				await expect(
					distributor.claim(1, addr2.address, 101, proof1)
				).to.be.revertedWith('MerkleDistributor: Invalid proof.');
			});

			it('cannot claim more than proof', async () => {
				// fund distributor
				await expect(() =>
					kwenta.connect(TREASURY_DAO).transfer(distributor.address, 201)
				).to.changeTokenBalance(kwenta, distributor, 201);

				// generate merkle proof for addr1.address
				const proof1 = tree.getProof(0, addr1.address, BigNumber.from(100));

				// addr1 attempts to claim MORE KWENTA than proof specifies
				await expect(
					distributor.claim(0, addr1.address, 101, proof1)
				).to.be.revertedWith('MerkleDistributor: Invalid proof.');
			});

			it('gas', async () => {
				// fund distributor
				await expect(() =>
					kwenta.connect(TREASURY_DAO).transfer(distributor.address, 100)
				).to.changeTokenBalance(kwenta, distributor, 100);

				// generate proof and claim for addr1
				const proof = tree.getProof(0, addr1.address, BigNumber.from(100));
				const tx = await distributor.claim(0, addr1.address, 100, proof);
				const receipt = await tx.wait();

				expect(receipt.gasUsed).to.equal(62960);
			});
		});

		describe('larger tree', () => {
			let tree: BalanceTree;
			let accounts: SignerWithAddress[];

			beforeEach('deploy', async () => {
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
					'MerkleDistributor'
				);
				distributor = await MerkleDistributor.deploy(
					kwenta.address,
					tree.getHexRoot()
				);
				await distributor.deployed();
			});

			it('claim index 4', async () => {
				// fund distributor
				await expect(() =>
					kwenta.connect(TREASURY_DAO).transfer(distributor.address, 100)
				).to.changeTokenBalance(kwenta, distributor, 100);

				// generate merkle proof
				const proof = tree.getProof(
					4,
					accounts[4].address,
					BigNumber.from(5)
				);

				// claim based on proof and index
				await expect(distributor.claim(4, accounts[4].address, 5, proof))
					.to.emit(distributor, 'Claimed')
					.withArgs(4, accounts[4].address, 5);
			});

			it('claim index 9', async () => {
				// fund distributor
				await expect(() =>
					kwenta.connect(TREASURY_DAO).transfer(distributor.address, 100)
				).to.changeTokenBalance(kwenta, distributor, 100);

				// generate merkle proof
				const proof = tree.getProof(
					9,
					accounts[9].address,
					BigNumber.from(10)
				);

				// claim based on proof and index
				await expect(distributor.claim(9, accounts[9].address, 10, proof))
					.to.emit(distributor, 'Claimed')
					.withArgs(9, accounts[9].address, 10);
			});

			it('gas', async () => {
				// fund distributor
				await expect(() =>
					kwenta.connect(TREASURY_DAO).transfer(distributor.address, 100)
				).to.changeTokenBalance(kwenta, distributor, 100);

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
				expect(receipt.gasUsed).to.eq(72796);
			});

			it('gas second down about 15k', async () => {
				// fund distributor
				await expect(() =>
					kwenta.connect(TREASURY_DAO).transfer(distributor.address, 100)
				).to.changeTokenBalance(kwenta, distributor, 100);

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
				expect(receipt.gasUsed).to.eq(55696);
			});
		});

		describe('realistic size tree', () => {
			let tree: BalanceTree;
			const NUM_LEAVES = 100_000;
			const NUM_SAMPLES = 25;
			const elements: { account: string; amount: BigNumber }[] = [];

			let addr1Address = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';

			for (let i = 0; i < NUM_LEAVES; i++) {
				const node = {
					account: addr1Address,
					amount: BigNumber.from(100),
				};
				elements.push(node);
			}

			tree = new BalanceTree(elements);

			it('proof verification works', () => {
				const root = Buffer.from(tree.getHexRoot().slice(2), 'hex');
				for (let i = 0; i < NUM_LEAVES; i += NUM_LEAVES / NUM_SAMPLES) {
					const proof = tree
						.getProof(i, addr1.address, BigNumber.from(100))
						.map((el) => Buffer.from(el.slice(2), 'hex'));
					const validProof = BalanceTree.verifyProof(
						i,
						addr1.address,
						BigNumber.from(100),
						proof,
						root
					);
					expect(validProof).to.be.true;
				}
			});

			beforeEach('deploy', async () => {
				const MerkleDistributor = await ethers.getContractFactory(
					'MerkleDistributor'
				);
				distributor = await MerkleDistributor.deploy(
					kwenta.address,
					tree.getHexRoot()
				);
				await distributor.deployed();

				// fund distributor
				await expect(() =>
					kwenta
						.connect(TREASURY_DAO)
						.transfer(distributor.address, 300_000)
				).to.changeTokenBalance(kwenta, distributor, 300_000);
			});

			it('gas', async () => {
				const proof = tree.getProof(
					50000,
					addr1.address,
					BigNumber.from(100)
				);
				const tx = await distributor.claim(
					50000,
					addr1.address,
					100,
					proof
				);
				const receipt = await tx.wait();
				expect(receipt.gasUsed).to.eq(87890);
			});

			it('gas deeper node', async () => {
				const proof = tree.getProof(
					90000,
					addr1.address,
					BigNumber.from(100)
				);
				const tx = await distributor.claim(
					90000,
					addr1.address,
					100,
					proof
				);
				const receipt = await tx.wait();
				expect(receipt.gasUsed).to.eq(87924);
			});

			it('gas average random distribution', async () => {
				let total: BigNumber = BigNumber.from(0);
				let count: number = 0;
				for (let i = 0; i < NUM_LEAVES; i += NUM_LEAVES / NUM_SAMPLES) {
					const proof = tree.getProof(
						i,
						addr1.address,
						BigNumber.from(100)
					);
					const tx = await distributor.claim(i, addr1.address, 100, proof);
					const receipt = await tx.wait();
					total = total.add(receipt.gasUsed);
					count++;
				}
				const average = total.div(count);
				expect(average).to.eq(87877);
			});

			// this is what we gas golfed by packing the bitmap
			it('gas average first 25', async () => {
				let total: BigNumber = BigNumber.from(0);
				let count: number = 0;
				for (let i = 0; i < 25; i++) {
					const proof = tree.getProof(
						i,
						addr1.address,
						BigNumber.from(100)
					);
					const tx = await distributor.claim(i, addr1.address, 100, proof);
					const receipt = await tx.wait();
					total = total.add(receipt.gasUsed);
					count++;
				}
				const average = total.div(count);
				expect(average).to.eq(71450);
			});

			it('no double claims in random distribution', async () => {
				for (
					let i = 0;
					i < 25;
					i += Math.floor(Math.random() * (NUM_LEAVES / NUM_SAMPLES))
				) {
					const proof = tree.getProof(
						i,
						addr1.address,
						BigNumber.from(100)
					);
					await distributor.claim(i, addr1.address, 100, proof);
					await expect(
						distributor.claim(i, addr1.address, 100, proof)
					).to.be.revertedWith('MerkleDistributor: Drop already claimed.');
				}
			});
		});
	});

	describe('parseBalanceMap', () => {
		let accounts: SignerWithAddress[];

		let claims: {
			[account: string]: {
				index: number;
				amount: string;
				proof: string[];
			};
		};

		beforeEach('deploy', async () => {
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

			expect(tokenTotal).to.equal('0x02ee'); // 750

			claims = innerClaims;

			const MerkleDistributor = await ethers.getContractFactory(
				'MerkleDistributor'
			);
			distributor = await MerkleDistributor.deploy(
				kwenta.address,
				merkleRoot
			);
			await distributor.deployed();

			// fund distributor
			await expect(() =>
				kwenta
					.connect(TREASURY_DAO)
					.transfer(distributor.address, tokenTotal)
			).to.changeTokenBalance(kwenta, distributor, tokenTotal);
		});

		it('all claims work exactly once', async () => {
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
					.to.emit(distributor, 'Claimed')
					.withArgs(claim.index, account, claim.amount);
				await expect(
					distributor.claim(
						claim.index,
						account,
						claim.amount,
						claim.proof
					)
				).to.be.revertedWith('MerkleDistributor: Drop already claimed.');
			}
			expect(await kwenta.balanceOf(distributor.address)).to.equal(0);
		});
	});
});
