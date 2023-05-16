// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../utils/DefaultStakingV2Setup.t.sol";
import {MockStakingRewardsV3} from "../utils/MockStakingRewardsV3.t.sol";
import "../utils/Constants.t.sol";

contract StakingV2UpgradeTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                            Upgrade Tests
    //////////////////////////////////////////////////////////////*/

    function test_Only_Owner_Can_Upgrade() public {
        address stakingV3Implementation = address(new MockStakingRewardsV3());

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        stakingRewardsV2.upgradeTo(stakingV3Implementation);
    }

    function test_Upgrade_StakingV2_To_V3() public {
        address stakingV3Implementation = address(new MockStakingRewardsV3());

        stakingRewardsV2.upgradeTo(stakingV3Implementation);

        MockStakingRewardsV3 stakingRewardsV3 =
            MockStakingRewardsV3(address(stakingRewardsV2));

        assertEq(stakingRewardsV3.newFunctionality(), 42);
    }
}
