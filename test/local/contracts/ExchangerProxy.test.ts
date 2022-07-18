import chai, { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract } from '@ethersproject/contracts';
import { FakeContract, smock } from '@defi-wonderland/smock';
import { IExchanger } from '../../../typechain/IExchanger';
import { ISynthetix } from '../../../typechain/ISynthetix';
import { IExchangeRates } from '../../../typechain/IExchangeRates';
import { IAddressResolver } from '../../../typechain/IAddressResolver';
import { IStakingRewards } from '../../../typechain/IStakingRewards';
import { IERC20 } from '../../../typechain/IERC20';

chai.use(smock.matchers);

describe('Exchanger Proxy', function () {
	let exchangerProxy: Contract;
	let fakeStakingRewards: FakeContract<IStakingRewards>;
	let fakeSynthetix: FakeContract<ISynthetix>;

	before(async () => {
        const fakeERC20 = await smock.fake<IERC20>('contracts/interfaces/IERC20.sol:IERC20');

		//// Synthetix AddressResolver mocking
		fakeSynthetix = await smock.fake<ISynthetix>('ISynthetix');

		const fakeExchanger = await smock.fake<IExchanger>('IExchanger');
		fakeExchanger.feeRateForExchange.returns(0);

		const fakeExchangeRates = await smock.fake<IExchangeRates>('IExchangeRates');
		fakeExchangeRates.effectiveValue.returns(0);

		const fakeAddressResolver = await smock.fake<IAddressResolver>(
			'IAddressResolver'
		);

		fakeAddressResolver.requireAndGetAddress.reverts();
		
		// Synthetix
		fakeAddressResolver.requireAndGetAddress
			.whenCalledWith(
				ethers.utils.formatBytes32String('Synthetix'),
				'Could not get Synthetix'
			)
			.returns(fakeSynthetix.address);
		
		// Exchanger
		fakeAddressResolver.requireAndGetAddress
			.whenCalledWith(
				ethers.utils.formatBytes32String('Exchanger'),
				'Could not get Exchanger'
			)
			.returns(fakeExchanger.address);
		
		// ExchangeRates
		fakeAddressResolver.requireAndGetAddress
			.whenCalledWith(
				ethers.utils.formatBytes32String('ExchangeRates'),
				'Could not get ExchangeRates'
			)
			.returns(fakeExchangeRates.address);

		fakeAddressResolver.getSynth
			.whenCalledWith(
				ethers.utils.formatBytes32String('sUSD')
			)
			.returns(fakeERC20.address);
		////

		fakeStakingRewards = await smock.fake<IStakingRewards>('StakingRewards');
		fakeStakingRewards.updateTraderScore.returns();

		const ExchangerProxy = await ethers.getContractFactory('ExchangerProxy');
		exchangerProxy = await ExchangerProxy.deploy(
			fakeAddressResolver.address,
			fakeStakingRewards.address
		);
		await exchangerProxy.deployed();

		return exchangerProxy;
	});

	it("updateTraderScore has NOT been called", async function () {
        fakeSynthetix.exchangeOnBehalfWithTracking.returns(0);

        await expect(
            exchangerProxy.exchangeOnBehalfWithTraderScoreTracking(
                ethers.utils.formatBytes32String("sUSD"),
                ethers.constants.One,
                ethers.utils.formatBytes32String("sETH"),
                ethers.constants.AddressZero
            )
        ).to.be.revertedWith("ExchangerProxy: Returned 0");
    });

    it("updateTraderScore has been called", async function () {
        fakeSynthetix.exchangeOnBehalfWithTracking.returns(1);

        await exchangerProxy.exchangeOnBehalfWithTraderScoreTracking(
            ethers.utils.formatBytes32String("sUSD"),
            ethers.constants.One,
            ethers.utils.formatBytes32String("sETH"),
            ethers.constants.AddressZero
        );

        expect(fakeStakingRewards.updateTraderScore).to.have.been.calledOnce;
    });
});
