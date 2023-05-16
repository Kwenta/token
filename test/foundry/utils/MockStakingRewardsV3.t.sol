// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";

contract MockStakingRewardsV3 is StakingRewardsV2 {
    function newFunctionality() external pure returns (uint256) {
        return 42;
    }
}
