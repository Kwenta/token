// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../utils/DefaultStakingV2Setup.t.sol";
import {MockStakingRewardsV3} from "../utils/MockStakingRewardsV3.t.sol";
import {MockRewardEscrowV3} from "../utils/MockRewardEscrowV3.t.sol";
import "../utils/Constants.t.sol";

contract StakingV2UpgradeTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                            Access Control
    //////////////////////////////////////////////////////////////*/

    function test_Only_Owner_Can_Upgrade_StakingRewardsV2() public {
        address stakingRewardsV3Implementation =
            address(new MockStakingRewardsV3());

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        stakingRewardsV2.upgradeTo(stakingRewardsV3Implementation);
    }

    function test_Only_Owner_Can_Upgrade_And_Call_StakingRewardsV2() public {
        address stakingRewardsV3Implementation =
            address(new MockStakingRewardsV3());

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        stakingRewardsV2.upgradeToAndCall(
            stakingRewardsV3Implementation,
            abi.encodeWithSignature("setNewNum(uint256)", 5)
        );
    }

    function test_Only_Owner_Can_Upgrade_RewardEscrowV2() public {
        address rewardEscrowV3Implementation = address(new MockRewardEscrowV3());

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        rewardEscrowV2.upgradeTo(rewardEscrowV3Implementation);
    }

    function test_Only_Owner_Can_Upgrade_And_Call_RewardEscrowV2() public {
        address rewardEscrowV3Implementation = address(new MockRewardEscrowV3());

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        stakingRewardsV2.upgradeToAndCall(
            stakingRewardsV3Implementation,
            abi.encodeWithSignature("setNewNum(uint256)", 5)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            Upgrade Tests
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade_StakingRewardsV2_To_V3() public {
        address stakingRewardsV3Implementation =
            address(new MockStakingRewardsV3());

        stakingRewardsV2.upgradeTo(stakingRewardsV3Implementation);

        MockStakingRewardsV3 stakingRewardsV3 =
            MockStakingRewardsV3(address(stakingRewardsV2));

        assertEq(stakingRewardsV3.newFunctionality(), 42);
    }
}
