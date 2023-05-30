// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {TokenDistributor} from "../../../contracts/TokenDistributor.sol";

contract TokenDistributorInternals is TokenDistributor {
    constructor(
        address _kwenta,
        address _stakingRewardsV2,
        address _rewardEscrowV2,
        uint _offset
    ) TokenDistributor(_kwenta, _stakingRewardsV2, _rewardEscrowV2, _offset) {}

    function startOfWeek(uint timestamp) public view returns (uint) {
        return _startOfWeek(timestamp);
    }

    function startOfEpoch(uint epochNumber) public view returns (uint) {
        return _startOfEpoch(epochNumber);
    }

    function checkpointWhenReady() public {
        _checkpointWhenReady();
    }

    function isEpochReady(uint epochNumber) public {
        _isEpochReady(epochNumber);
    }

}
