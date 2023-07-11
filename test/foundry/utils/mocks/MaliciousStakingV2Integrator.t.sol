// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IStakingRewardsV2} from "../../../../contracts/interfaces/IStakingRewardsV2.sol";

contract MaliciousStakingV2Integrator {
    address public _beneficiary;
    IStakingRewardsV2 public _stakingRewards;

    constructor(address __beneficiary, address __stakingRewards) {
        _beneficiary = __beneficiary;
        _stakingRewards = IStakingRewardsV2(__stakingRewards);
    }

    function beneficiary() public returns (address) {
        _stakingRewards.getReward();
        return _beneficiary;
    }
}
