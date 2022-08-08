import { expect } from 'chai';
import { ethers, network } from 'hardhat';
import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { wei } from '@synthetixio/wei';
import { BigNumber } from 'ethers';
import { deployKwenta } from '../../utils/kwenta';
import { fastForward } from '../../utils/helpers';

describe('Mint', () => {
	// constants
	const NAME = 'Kwenta';
	const SYMBOL = 'KWENTA';
	const INITIAL_SUPPLY = wei(313373);
	const INITIAL_WEEKLY_EMISSION = INITIAL_SUPPLY.mul(2.4).div(52);
	const RATE_OF_DECAY = 0.0205;
	const INFLATION_DIVERSION_BPS = 2000;
	const WEEKLY_START_REWARDS = 3;

	// test accounts
	let owner: SignerWithAddress;
	let addr1: SignerWithAddress;
	let addr2: SignerWithAddress;
	let TREASURY_DAO: SignerWithAddress;
	let tradingRewards: SignerWithAddress;

	// core contracts
	let kwenta: Contract;
	let supplySchedule: Contract;
	let rewardEscrow: Contract;
	let stakingRewards: Contract;

	beforeEach(async () => {
		[owner, addr1, addr2, TREASURY_DAO, tradingRewards] = await ethers.getSigners();
		let deployments = await deployKwenta(
			NAME,
			SYMBOL,
			INITIAL_SUPPLY.toBN(),
			owner,
			TREASURY_DAO
		);
		kwenta = deployments.kwenta;
		supplySchedule = deployments.supplySchedule;
		rewardEscrow = deployments.rewardEscrow;
		stakingRewards = deployments.stakingRewards;

		await supplySchedule.setStakingRewards(stakingRewards.address);
		await supplySchedule.setTradingRewards(tradingRewards.address);
	});

	it('No inflationary supply to mint', async () => {
		await expect(supplySchedule.mint()).to.be.revertedWith('No supply is mintable');
		expect(await kwenta.balanceOf(stakingRewards.address)).to.equal(0);
	});

	it('Mint inflationary supply 1 week later', async () => {
		const MINTER_REWARD = ethers.utils.parseUnits('1');
		const FIRST_WEEK_MINT = INITIAL_WEEKLY_EMISSION.sub(MINTER_REWARD);

		// We subtract treasury inflationary diversion amount so that stakers get remainder (after truncation)
		const FIRST_WEEK_STAKING_REWARDS = FIRST_WEEK_MINT
			.sub(FIRST_WEEK_MINT.mul(INFLATION_DIVERSION_BPS*2).div(10000));

		expect(await kwenta.balanceOf(owner.address)).to.equal(0);
		await fastForward(604800);
		await supplySchedule.mint();

		// Make sure this is equivalent to first week distribution
		expect(await kwenta.balanceOf(stakingRewards.address)).to.equal(
			FIRST_WEEK_STAKING_REWARDS.toBN()
		);
	});

	describe('Verify future supply', () => {
		const powRoundDown = (x: BigNumber, n: number, unit = wei(1).toBN()) => {
			let xBN = x;
			let temp = unit;
			while (n > 0) {
				if (n % 2 !== 0) {
					temp = temp.mul(xBN).div(unit);
				}
				xBN = xBN.mul(xBN).div(unit);
				n = parseInt(String(n / 2)); // For some reason my terminal will freeze until reboot if I don't do this?
			}
			return temp;
		};

		function getSupplyAtWeek(weekNumber: number) {
			let supply = INITIAL_SUPPLY;
			for (let week = 0; week < weekNumber; week++) {
				const expectedMint = INITIAL_WEEKLY_EMISSION.mul(
					powRoundDown(wei(1 - RATE_OF_DECAY).toBN(), week)
				);
				supply = supply.add(expectedMint);
			}
			return supply;
		}

		it('Mint rewards 1 week later', async () => {
			const expected = getSupplyAtWeek(1);
			await network.provider.send('evm_increaseTime', [604800]);
			await supplySchedule.mint();
			expect(await kwenta.totalSupply()).to.equal(expected.toBN());
		});

		it('Mint rewards the second week after the first', async () => {
			const expected = getSupplyAtWeek(2);
			await network.provider.send('evm_increaseTime', [604800]);
			await supplySchedule.mint();
			await network.provider.send('evm_increaseTime', [604800 * 2]);
			await supplySchedule.mint();
			expect(await kwenta.totalSupply()).to.equal(expected.toBN());
		});

		it('Mint rewards the second week skipping first', async () => {
			const expected = getSupplyAtWeek(2);
			await network.provider.send('evm_increaseTime', [604800 * 2]);
			await supplySchedule.mint();
			expect(await kwenta.totalSupply()).to.equal(expected.toBN());
		});

		it('Mint rewards 4 years later', async () => {
			const expected = getSupplyAtWeek(208);
			await network.provider.send('evm_increaseTime', [604800 * 208]);
			await supplySchedule.mint();
			expect(await kwenta.totalSupply()).to.equal(expected.toBN());
		});

		it('Mint rewards 4 years and one week later', async () => {
			const expectedSupplyAtEndOfDecay = getSupplyAtWeek(208);
			const expected = expectedSupplyAtEndOfDecay.add(
				expectedSupplyAtEndOfDecay.mul(wei(0.01).div(52))
			);
			await network.provider.send('evm_increaseTime', [604800 * 208]);
			await supplySchedule.mint();
			await network.provider.send('evm_increaseTime', [604800 * 2]);
			await supplySchedule.mint();
			expect(await kwenta.totalSupply()).to.equal(expected.toBN());
		});
	});
});
