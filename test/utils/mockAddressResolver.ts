import { smock } from "@defi-wonderland/smock";
import { wei } from "@synthetixio/wei";
import { ethers } from "hardhat";
import { IAddressResolver } from "../../typechain/IAddressResolver";
import { IERC20 } from "../../typechain/IERC20";
import { IExchanger } from "../../typechain/IExchanger";
import { ISynthetix } from "../../typechain/ISynthetix";
import { IExchangeRates } from '../../typechain/IExchangeRates';

/**
 * Deploys mock synthetix AddressResolver
 * @returns fakeAddressResolver
 */
export const mockAddressResolver = async () => {
	const fakeERC20 = await smock.fake<IERC20>('contracts/interfaces/IERC20.sol:IERC20');
	
	const FEE = wei(10).toBN();

	const fakeSynthetix = await smock.fake<ISynthetix>('ISynthetix');
	fakeSynthetix.exchangeWithTracking.returns(FEE);

	const fakeExchanger = await smock.fake<IExchanger>('IExchanger');
	fakeExchanger.feeRateForExchange.returns(FEE);

	const fakeExchangeRates = await smock.fake<IExchangeRates>('IExchangeRates');
	fakeExchangeRates.effectiveValue.returns(FEE);

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

	// sUSD
	fakeAddressResolver.getSynth
		.whenCalledWith(
			ethers.utils.formatBytes32String('sUSD')
		)
		.returns(fakeERC20.address);

	return fakeAddressResolver;
};