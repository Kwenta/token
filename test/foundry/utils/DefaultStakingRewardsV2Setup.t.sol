// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {StakingRewardsTestHelpers} from "../utils/StakingRewardsTestHelpers.t.sol";
import "../utils/Constants.t.sol";

contract DefaultStakingRewardsV2Setup is StakingRewardsTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                Setup
    //////////////////////////////////////////////////////////////*/

    function setUp() public override virtual {
        super.setUp();

        pauseAndSwitchToStakingRewardsV2();
    }
}
