// SPDX-License-Identifier: MIT
pragma solidity >=0.4.24;

// https://docs.synthetix.io/contracts/source/interfaces/iexchangerates
interface IExchangeRates {
    // Views

    // Given a quantity of a source currency, returns a quantity 
    // of a destination currency that is of equivalent value at 
    // current exchange rates, if those rates are fresh
    function effectiveValue(
        bytes32 sourceCurrencyKey,
        uint sourceAmount,
        bytes32 destinationCurrencyKey
    ) external view returns (uint value);
}