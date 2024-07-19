// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../utils/setup/DefaultStakingV2Setup.t.sol";
import {MockStakingRewardsV3} from "../utils/mocks/MockStakingRewardsV3.t.sol";
import {MockRewardEscrowV3} from "../utils/mocks/MockRewardEscrowV3.t.sol";
import {MockEscrowMigratorV2} from "../utils/mocks/MockEscrowMigratorV2.t.sol";
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
        address rewardEscrowV3Implementation =
            address(new MockRewardEscrowV3(address(kwenta), address(0x1)));

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        rewardEscrowV2.upgradeTo(rewardEscrowV3Implementation);
    }

    function test_Only_Owner_Can_Upgrade_And_Call_RewardEscrowV2() public {
        address rewardEscrowV3Implementation =
            address(new MockRewardEscrowV3(address(kwenta), address(0x1)));

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        rewardEscrowV2.upgradeToAndCall(
            rewardEscrowV3Implementation, abi.encodeWithSignature("setNewNum(uint256)", 5)
        );
    }

    function test_Only_Owner_Can_Upgrade_EscrowMigrator() public {
        address escrowMigratorV2Impl = deployEscrowMigratorImpl();

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        escrowMigrator.upgradeTo(escrowMigratorV2Impl);
    }

    function test_Only_Owner_Can_Upgrade_And_Call_EscrowMigrator() public {
        address escrowMigratorV2Impl = deployEscrowMigratorImpl();

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user1);
        escrowMigrator.upgradeToAndCall(
            escrowMigratorV2Impl, abi.encodeWithSignature("setNewNum(uint256)", 5)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        Initial Proxy Setup
    //////////////////////////////////////////////////////////////*/

    function test_RewardEscrowV2_Implementation_Cannot_Be_Initialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        rewardEscrowV2.initialize(address(0));
    }

    function test_StakingRewardsV2_Implementation_Cannot_Be_Initialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        stakingRewardsV2.initialize(address(0));
    }

    function test_EscrowMigrator_Implementation_Cannot_Be_Initialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        escrowMigrator.initialize(address(0x1), treasury);
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

        testStakingV2StillWorking();
    }

    function test_Upgrade_And_Call_StakingRewardsV2_To_V3() public {
        address stakingRewardsV3Implementation = deployStakingRewardsV3Implementation();

        stakingRewardsV2.upgradeToAndCall(
            stakingRewardsV3Implementation, abi.encodeWithSignature("setNewNum(uint256)", 5)
        );

        MockStakingRewardsV3 stakingRewardsV3 = MockStakingRewardsV3(address(stakingRewardsV2));

        assertEq(stakingRewardsV3.newFunctionality(), 42);
        assertEq(stakingRewardsV3.newNum(), 5);

        testStakingV2StillWorking();
    }

    /*//////////////////////////////////////////////////////////////
                        Upgrade RewardEscrowV2
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade_RewardEscrowV2_To_V3() public {
        address rewardEscrowV3Implementation =
            address(new MockRewardEscrowV3(address(kwenta), address(0x1)));

        rewardEscrowV2.upgradeTo(rewardEscrowV3Implementation);

        MockStakingRewardsV3 rewardEscrowV3 = MockStakingRewardsV3(address(rewardEscrowV2));

        assertEq(rewardEscrowV3.newFunctionality(), 42);
        assertEq(rewardEscrowV3.newNum(), 0);

        testStakingV2StillWorking();
    }

    function test_Upgrade_And_Call_RewardEscrowV2_To_V3() public {
        address rewardEscrowV3Implementation =
            address(new MockRewardEscrowV3(address(kwenta), address(0x1)));

        rewardEscrowV2.upgradeToAndCall(
            rewardEscrowV3Implementation, abi.encodeWithSignature("setNewNum(uint256)", 5)
        );

        MockStakingRewardsV3 rewardEscrowV3 = MockStakingRewardsV3(address(rewardEscrowV2));

        assertEq(rewardEscrowV3.newFunctionality(), 42);
        assertEq(rewardEscrowV3.newNum(), 5);

        testStakingV2StillWorking();
    }

    /*//////////////////////////////////////////////////////////////
                        UPGRADE ESCROW MIGRATOR
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade_EscrowMigrator_To_V2() public {
        address escrowMigratorV2Impl = deployEscrowMigratorImpl();

        escrowMigrator.upgradeTo(escrowMigratorV2Impl);

        MockEscrowMigratorV2 escrowMigratorV2 = MockEscrowMigratorV2(address(escrowMigrator));

        assertEq(escrowMigratorV2.newFunctionality(), 42);
        assertEq(escrowMigratorV2.newNum(), 0);

        testStakingV2StillWorking();
    }

    function test_Upgrade_And_Call_EscrowMigrator_To_V2() public {
        address escrowMigratorV2Impl = deployEscrowMigratorImpl();

        escrowMigrator.upgradeToAndCall(
            escrowMigratorV2Impl, abi.encodeWithSignature("setNewNum(uint256)", 5)
        );

        MockEscrowMigratorV2 escrowMigratorV2 = MockEscrowMigratorV2(address(escrowMigrator));

        assertEq(escrowMigratorV2.newFunctionality(), 42);
        assertEq(escrowMigratorV2.newNum(), 5);

        testEscrowMigratorStillWorking();
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
                address(usdc),
                address(rewardEscrowV2),
                address(rewardsNotifier)
            )
        );
    }

    function deployEscrowMigratorImpl() internal returns (address escrowMigratorImpl) {
        escrowMigratorImpl = address(
            new MockEscrowMigratorV2(
                address(kwenta),
                address(rewardEscrowV1),
                address(rewardEscrowV2),
                address(stakingRewardsV2)
            )
        );
    }

    function testStakingV2StillWorking() internal {
        // stake liquid kwenta
        assertEq(0, stakingRewardsV2.balanceOf(user1));
        fundAccountAndStakeV2(user1, 1 ether);
        assertEq(1 ether, stakingRewardsV2.balanceOf(user1));

        // escrow some kwenta
        assertEq(0, rewardEscrowV2.balanceOf(user1));
        assertEq(0, rewardEscrowV2.escrowedBalanceOf(user1));
        createRewardEscrowEntryV2(user1, 1 ether, 52 weeks);
        assertEq(1, rewardEscrowV2.balanceOf(user1));
        assertEq(1 ether, rewardEscrowV2.escrowedBalanceOf(user1));

        // add new rewards
        addNewRewardsToStakingRewardsV2(1 weeks, 0);
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // claim the rewards
        getStakingRewardsV2(user1);
        assertEq(1 ether, stakingRewardsV2.balanceOf(user1));
        assertEq(2, rewardEscrowV2.balanceOf(user1));
        assertEq(1 ether + 1 weeks, rewardEscrowV2.escrowedBalanceOf(user1));
        assertEq(1 ether + 1 weeks, rewardEscrowV2.unstakedEscrowedBalanceOf(user1));

        // stake the rewards
        stakeAllUnstakedEscrowV2(user1);
        assertEq(2 ether + 1 weeks, stakingRewardsV2.balanceOf(user1));
        assertEq(1 ether + 1 weeks, stakingRewardsV2.escrowedBalanceOf(user1));
        assertEq(0, rewardEscrowV2.unstakedEscrowedBalanceOf(user1));
    }

    function testEscrowMigratorStillWorking() internal {
        // create escrow entries
        createRewardEscrowEntryV1(user1, 1 ether);
        createRewardEscrowEntryV1(user1, 2 ether);
        createRewardEscrowEntryV1(user1, 3 ether);

        // migrate escrow entries
        claimAndFullyMigrate(user1);

        // check that the migration worked
        checkStateAfterStepThree(user1);
    }
}
