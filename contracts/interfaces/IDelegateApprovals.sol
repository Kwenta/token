pragma solidity >=0.4.24;

// https://docs.synthetix.io/contracts/source/interfaces/idelegateapprovals
interface IDelegateApprovals {
    // Views
    function canExchangeFor(address authoriser, address delegate) external view returns (bool);
    // Mutative
    function approveExchangeOnBehalf(address delegate) external;
    function removeExchangeOnBehalf(address delegate) external;
}