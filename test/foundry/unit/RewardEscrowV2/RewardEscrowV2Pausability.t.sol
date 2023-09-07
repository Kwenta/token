// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {IRewardEscrowV2} from "../../../../contracts/interfaces/IRewardEscrowV2.sol";
import "../../utils/Constants.t.sol";

contract RewardEscrowV2PausabilityTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                            Pausability
    //////////////////////////////////////////////////////////////*/

    function test_Only_Owner_Can_Pause_Contract() public {
        // attempt to pause
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        rewardEscrowV2.pauseRewardEscrow();

        // pause
        rewardEscrowV2.pauseRewardEscrow();

        // attempt to unpause
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        rewardEscrowV2.unpauseRewardEscrow();

        // unpause
        rewardEscrowV2.unpauseRewardEscrow();
    }

    function test_Cannot_Vest_When_Paused() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);
        vm.warp(block.timestamp + 52 weeks);

        // pause
        rewardEscrowV2.pauseRewardEscrow();

        entryIDs.push(1);
        vm.expectRevert("Pausable: paused");
        rewardEscrowV2.vest(entryIDs);

        // unpause
        rewardEscrowV2.unpauseRewardEscrow();

        // now shouldn't revert
        rewardEscrowV2.vest(entryIDs);
    }

    function test_Cannot_Create_Escrow_Entry_When_Paused() public {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), TEST_VALUE);

        // pause
        rewardEscrowV2.pauseRewardEscrow();

        vm.prank(treasury);
        vm.expectRevert("Pausable: paused");
        rewardEscrowV2.createEscrowEntry(address(this), TEST_VALUE, 52 weeks, 90);

        // unpause
        rewardEscrowV2.unpauseRewardEscrow();

        // now shouldn't revert
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(address(this), TEST_VALUE, 52 weeks, 90);
    }

    function test_Cannot_Append_Escrow_Entry_When_Paused() public {
        vm.prank(treasury);
        kwenta.transfer(address(rewardEscrowV2), TEST_VALUE);

        // pause
        rewardEscrowV2.pauseRewardEscrow();

        vm.prank(address(stakingRewardsV2));
        vm.expectRevert("Pausable: paused");
        rewardEscrowV2.appendVestingEntry(address(this), TEST_VALUE);

        // unpause
        rewardEscrowV2.unpauseRewardEscrow();

        // now shouldn't revert
        vm.prank(address(stakingRewardsV2));
        rewardEscrowV2.appendVestingEntry(address(this), TEST_VALUE);
    }

    function test_Cannot_Import_Entry_When_Paused() public {
        vm.prank(treasury);
        kwenta.transfer(address(rewardEscrowV2), TEST_VALUE);

        // pause
        rewardEscrowV2.pauseRewardEscrow();

        vm.prank(address(escrowMigrator));
        vm.expectRevert("Pausable: paused");
        rewardEscrowV2.importEscrowEntry(
            address(this),
            IRewardEscrowV2.VestingEntry({
                endTime: uint64(block.timestamp + 52 weeks),
                escrowAmount: uint144(TEST_VALUE),
                duration: 52 weeks,
                earlyVestingFee: 90
            })
        );

        // unpause
        rewardEscrowV2.unpauseRewardEscrow();

        // now shouldn't revert
        vm.prank(address(escrowMigrator));
        rewardEscrowV2.importEscrowEntry(
            address(this),
            IRewardEscrowV2.VestingEntry({
                endTime: uint64(block.timestamp + 52 weeks),
                escrowAmount: uint144(TEST_VALUE),
                duration: 52 weeks,
                earlyVestingFee: 90
            })
        );
    }
}
