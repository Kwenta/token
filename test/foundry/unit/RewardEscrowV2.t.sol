// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DefaultStakingRewardsV2Setup} from "../utils/DefaultStakingRewardsV2Setup.t.sol";
import "../utils/Constants.t.sol";

contract RewardEscrowV2Tests is DefaultStakingRewardsV2Setup {
    /*//////////////////////////////////////////////////////////////
                                Tests
    //////////////////////////////////////////////////////////////*/

    function test_transferVestingEntry() public {
        // stakeEscrowedFundsV2()
        assertTrue(true);
    }

}
