// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";

contract MockStakingRewardsV3 is StakingRewardsV2 {
    uint256 public newNum;

    constructor(
        address _kwenta,
        address _usdc,
        address _rewardEscrow,
        address _rewardNotifier
    ) StakingRewardsV2(_kwenta, _usdc, _rewardEscrow, _rewardNotifier) {}

    function setNewNum(uint256 _newNum) external {
        newNum = _newNum;
    }

    function newFunctionality() external pure returns (uint256) {
        return 42;
    }
}
