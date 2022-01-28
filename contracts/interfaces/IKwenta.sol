// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./IERC20.sol";

interface IKwenta is IERC20 {

    function mint() external returns (bool);

    function setTreasuryDiversion(uint _treasuryDiversion) external;

    function setStakingRewards(address _stakingRewards) external;

}