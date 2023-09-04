// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {RewardEscrowV2} from "../../../../contracts/RewardEscrowV2.sol";

contract MockRewardEscrowV3 is RewardEscrowV2 {
    uint256 public newNum;

    constructor(address _kwenta, address _rewardsNotifier)
        RewardEscrowV2(_kwenta, _rewardsNotifier)
    {}

    function setNewNum(uint256 _newNum) external {
        newNum = _newNum;
    }

    function newFunctionality() external pure returns (uint256) {
        return 42;
    }
}
