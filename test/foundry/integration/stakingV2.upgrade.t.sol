// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../utils/setup/DefaultStakingV2Setup.t.sol";
import {MockStakingRewardsV3} from "../utils/mocks/MockStakingRewardsV3.t.sol";
import {MockRewardEscrowV3} from "../utils/mocks/MockRewardEscrowV3.t.sol";
import "../utils/Constants.t.sol";

contract StakingV2UpgradeTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                            Access Control
    //////////////////////////////////////////////////////////////*/

    function test_Only_Owner_Can_Upgrade_StakingRewardsV2() public {
        address stakingRewardsV3Implementation = deployStakingRewardsV3Implementation();

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        stakingRewardsV2.upgradeTo(stakingRewardsV3Implementation);
    }

    function test_Only_Owner_Can_Upgrade_And_Call_StakingRewardsV2() public {
        address stakingRewardsV3Implementation = deployStakingRewardsV3Implementation();

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        stakingRewardsV2.upgradeToAndCall(
            stakingRewardsV3Implementation, abi.encodeWithSignature("setNewNum(uint256)", 5)
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
            rewardEscrowV3Implementation, abi.encodeWithSignature("setNewNum(uint256)", 5)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        Initial Proxy Setup
    //////////////////////////////////////////////////////////////*/

    function test_RewardEscrowV2_Implementation_Cannot_Be_Initialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        rewardEscrowV2.initialize(address(0), address(0));
    }

    function test_StakingRewardsV2_Implementation_Cannot_Be_Initialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        stakingRewardsV2.initialize(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        Upgrade StakingRewardsV2
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade_StakingRewardsV2_To_V3() public {
        address stakingRewardsV3Implementation = deployStakingRewardsV3Implementation();

        stakingRewardsV2.upgradeTo(stakingRewardsV3Implementation);

        MockStakingRewardsV3 stakingRewardsV3 = MockStakingRewardsV3(address(stakingRewardsV2));

        assertEq(stakingRewardsV3.newFunctionality(), 42);
        assertEq(stakingRewardsV3.newNum(), 0);
    }

    function test_Upgrade_And_Call_StakingRewardsV2_To_V3() public {
        address stakingRewardsV3Implementation = deployStakingRewardsV3Implementation();

        stakingRewardsV2.upgradeToAndCall(
            stakingRewardsV3Implementation, abi.encodeWithSignature("setNewNum(uint256)", 5)
        );

        MockStakingRewardsV3 stakingRewardsV3 = MockStakingRewardsV3(address(stakingRewardsV2));

        assertEq(stakingRewardsV3.newFunctionality(), 42);
        assertEq(stakingRewardsV3.newNum(), 5);
    }

    /*//////////////////////////////////////////////////////////////
                        Upgrade RewardEscrowV2
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade_RewardEscrowV2_To_V3() public {
        address rewardEscrowV3Implementation = address(new MockRewardEscrowV3());

        rewardEscrowV2.upgradeTo(rewardEscrowV3Implementation);

        MockStakingRewardsV3 rewardEscrowV3 = MockStakingRewardsV3(address(rewardEscrowV2));

        assertEq(rewardEscrowV3.newFunctionality(), 42);
        assertEq(rewardEscrowV3.newNum(), 0);
    }

    function test_Upgrade_And_Call_RewardEscrowV2_To_V3() public {
        address rewardEscrowV3Implementation = address(new MockRewardEscrowV3());

        rewardEscrowV2.upgradeToAndCall(
            rewardEscrowV3Implementation, abi.encodeWithSignature("setNewNum(uint256)", 5)
        );

        MockStakingRewardsV3 rewardEscrowV3 = MockStakingRewardsV3(address(rewardEscrowV2));

        assertEq(rewardEscrowV3.newFunctionality(), 42);
        assertEq(rewardEscrowV3.newNum(), 5);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function deployStakingRewardsV3Implementation()
        internal
        returns (address stakingRewardsV3Implementation)
    {
        stakingRewardsV3Implementation = address(
            new MockStakingRewardsV3(
                address(kwenta),
                address(rewardEscrowV2),
                address(supplySchedule),
                address(stakingRewardsV1)
            )
        );
    }
}
