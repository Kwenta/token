//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IAddressResolver.sol";
import "./interfaces/ISynthetix.sol";
import "./interfaces/IExchanger.sol";
import "./interfaces/IStakingRewards.sol";
import "./interfaces/IExchangeRates.sol";
import "./interfaces/IERC20.sol";

contract ExchangerProxy {
    IAddressResolver addressResolver;
    IStakingRewards stakingRewards;
    bytes32 private constant CONTRACT_SYNTHETIX = "Synthetix";
    bytes32 private constant CONTRACT_EXCHANGER = "Exchanger";
    bytes32 private constant CONTRACT_EXRATES = "ExchangeRates";
    bytes32 private constant sUSD_CURRENCY_KEY = "sUSD";
    
    constructor(address _addressResolver, address _stakingRewards) {
        addressResolver = IAddressResolver(_addressResolver);
        stakingRewards = IStakingRewards(_stakingRewards);
    }

    function synthetix() internal view returns (ISynthetix) {
        return ISynthetix(addressResolver.requireAndGetAddress(
            CONTRACT_SYNTHETIX, 
            "Could not get Synthetix"
        ));
    }

    function exchanger() internal view returns (IExchanger) {
        return IExchanger(addressResolver.requireAndGetAddress(
            CONTRACT_EXCHANGER, 
            "Could not get Exchanger"
        ));
    }

    function exchangeRates() internal view returns (IExchangeRates) {
        return IExchangeRates(addressResolver.requireAndGetAddress(
            CONTRACT_EXRATES,
            "Could not get ExchangeRates"
        ));
    }

    function exchangeOnBehalfWithTraderScoreTracking(
        bytes32 sourceCurrencyKey,
        uint sourceAmount,
        bytes32 destinationCurrencyKey,
        address rewardAddress,
        bytes32 trackingCode
    ) external returns (uint amountReceived) {
        // Get fee
        ( , uint fee, ) = exchanger().getAmountsForExchange(
            sourceAmount, 
            sourceCurrencyKey, 
            destinationCurrencyKey
        );

        // If fee is NOT denoted in sUSD, query Synthetix for exchange rate in sUSD
        if (destinationCurrencyKey != sUSD_CURRENCY_KEY) {
            fee = exchangeRates().effectiveValue(destinationCurrencyKey, fee, sUSD_CURRENCY_KEY);
        }

        // Execute exchange on behalf of user
        uint received = synthetix().exchangeOnBehalfWithTracking(
            msg.sender,
            sourceCurrencyKey,
            sourceAmount,
            destinationCurrencyKey,
            rewardAddress,
            trackingCode
        );

        // Update StakingRewards trader score
        stakingRewards.updateTraderScore(msg.sender, fee);
        return received;
    }
}