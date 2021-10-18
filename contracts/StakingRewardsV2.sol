// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import necessary contracts for math operations and Token handling

import "./StakingRewards.sol";


contract StakingRewardsV2 is StakingRewards{
    
    function version() public pure returns(string memory) {
        return "V2";
    }
    
}