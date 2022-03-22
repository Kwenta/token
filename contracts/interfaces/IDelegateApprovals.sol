pragma solidity >=0.4.24;

// https://docs.synthetix.io/contracts/source/interfaces/idelegateapprovals
interface IDelegateApprovals {
    // Mutative
    function approveExchangeOnBehalf(address delegate) external;
    function removeExchangeOnBehalf(address delegate) external;
}