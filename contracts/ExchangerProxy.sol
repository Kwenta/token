//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./interfaces/ISynthetix.sol";
import "./interfaces/IExchanger.sol";

contract ExchangerProxy {

    ISynthetix synthetix;
    IExchanger exchanger;

    constructor(address _synthetixProxy, address _exchanger) {
        synthetix = ISynthetix(_synthetixProxy);
        exchanger = IExchanger(_exchanger);
    }
    
    function exchangeWithTraderScoreTracking(
        bytes32 sourceCurrencyKey,
        uint sourceAmount,
        bytes32 destinationCurrencyKey,
        address rewardAddress,
        bytes32 trackingCode
    ) external returns (uint amountReceived) {
        // Get fee
        uint fee = exchanger.feeRateForExchange(sourceCurrencyKey, destinationCurrencyKey);

        // Execute typical exchange
        uint received = synthetix.exchangeWithTracking(
            sourceCurrencyKey, 
            sourceAmount, 
            destinationCurrencyKey, 
            rewardAddress, 
            trackingCode
        );

        // Update StakingRewards trader score
        //updateTraderScore(msg.sender, fee);
        return received;
    }

}