// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./StakingRewardsV2.sol";

contract StakingRewardsV3 is StakingRewardsV2 {
    uint256 private _totalRewardScoreAdded;

    function setTotalRewardScoreAdded() public onlyOwner {
        _totalRewardScoreAdded = totalRewardScore() + 2;
    }

    function getTotalRewardScoreAdded() public view returns (uint256) {
        return _totalRewardScoreAdded;
    }
}
