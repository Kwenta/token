//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IAddressResolver.sol";
import "./interfaces/ISynthetix.sol";
import "./interfaces/IExchanger.sol";
import "./interfaces/IStakingRewards.sol";
import "./interfaces/IExchangeRates.sol";
import "./interfaces/IERC20.sol";

contract ExchangerProxy {
    IAddressResolver internal immutable addressResolver;
    IStakingRewards internal immutable stakingRewards;
    bytes32 private constant CONTRACT_SYNTHETIX = "Synthetix";
    bytes32 private constant CONTRACT_EXCHANGER = "Exchanger";
    bytes32 private constant CONTRACT_EXRATES = "ExchangeRates";
    // solhint-disable-next-line
    bytes32 private constant sUSD_CURRENCY_KEY = "sUSD";
    bytes32 private constant TRACKING_CODE = "KWENTA";

    constructor(address _addressResolver, address _stakingRewards) {
        addressResolver = IAddressResolver(_addressResolver);
        stakingRewards = IStakingRewards(_stakingRewards);
    }

    function synthetix() internal view returns (ISynthetix) {
        return
            ISynthetix(
                addressResolver.requireAndGetAddress(
                    CONTRACT_SYNTHETIX,
                    "Could not get Synthetix"
                )
            );
    }

    function exchanger() internal view returns (IExchanger) {
        return
            IExchanger(
                addressResolver.requireAndGetAddress(
                    CONTRACT_EXCHANGER,
                    "Could not get Exchanger"
                )
            );
    }

    function exchangeRates() internal view returns (IExchangeRates) {
        return
            IExchangeRates(
                addressResolver.requireAndGetAddress(
                    CONTRACT_EXRATES,
                    "Could not get ExchangeRates"
                )
            );
    }

    function exchangeOnBehalfWithTraderScoreTracking(
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey,
        address rewardAddress
    ) external returns (uint256 amountReceived) {
        // Get fee
        (, uint256 fee, ) = exchanger().getAmountsForExchange(
            sourceAmount,
            sourceCurrencyKey,
            destinationCurrencyKey
        );

        // If fee is NOT denoted in sUSD, query Synthetix for exchange rate in sUSD
        if (destinationCurrencyKey != sUSD_CURRENCY_KEY) {
            fee = exchangeRates().effectiveValue(
                destinationCurrencyKey,
                fee,
                sUSD_CURRENCY_KEY
            );
        }

        /// @notice Execute exchange on behalf of user
        uint256 received = synthetix().exchangeOnBehalfWithTracking(
            msg.sender,
            sourceCurrencyKey,
            sourceAmount,
            destinationCurrencyKey,
            rewardAddress,
            TRACKING_CODE
        );

        /// @dev few scenarios where synthetix().exchangeOnBehalfWithTracking() will return 0.
        /// balance too low after settlement, exchange rate circuit breaker is broken,
        /// or if the exchange rates are too volatile
        require(received > 0, "ExchangerProxy: Returned 0");

        // Update StakingRewards trader score
        stakingRewards.updateTraderScore(msg.sender, fee);
        return received;
    }
}
