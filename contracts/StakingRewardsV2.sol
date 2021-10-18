// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import necessary contracts for math operations and Token handling

import "./StakingRewards.sol";


contract StakingRewardsV2 is StakingRewards{

    string private version;
    
    function setVersion(string memory _version) public onlyOwner {
        version = _version;
    }

    function getVersion() public view returns(string memory){
        return version;
    }
    
}