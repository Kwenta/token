// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IKwenta is IERC20 {

    function mint() external returns (bool);

    function burn(uint amount) external;

    function setTreasuryDiversion(uint _treasuryDiversion) external;
    
    function setStakingRewards(address _stakingRewards) external;

}