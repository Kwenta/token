// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import {TokenDistributor} from "../../../contracts/TokenDistributor.sol";

contract TokenDistributorInternals is TokenDistributor {
    constructor(address _kwenta, address _stakingRewardsV2, uint256 _offset)
        TokenDistributor(_kwenta, _stakingRewardsV2, _offset)
    {}

    function startOfWeek(uint256 timestamp) public view returns (uint256) {
        return _startOfWeek(timestamp);
    }

    function startOfEpoch(uint256 epochNumber) public view returns (uint256) {
        return _startOfEpoch(epochNumber);
    }

    function checkpointWhenReady() public {
        _checkpointWhenReady();
    }

    function isEpochReady(uint256 epochNumber) external view {
        _isEpochReady(epochNumber);
    }

    function epochFromTimestamp(uint256 timestamp) external view returns (uint256) {
        return _epochFromTimestamp(timestamp);
    }
}
