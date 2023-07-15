// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";

contract MockStakingRewardsV3 is StakingRewardsV2 {
    uint256 public newNum;

    constructor(
        address _kwenta,
        address _rewardEscrow,
        address _supplySchedule,
        address _stakingRewardsV1
    ) StakingRewardsV2(_kwenta, _rewardEscrow, _supplySchedule, _stakingRewardsV1) {}

    function setNewNum(uint256 _newNum) external {
        newNum = _newNum;
    }

    function newFunctionality() external pure returns (uint256) {
        return 42;
    }
}
