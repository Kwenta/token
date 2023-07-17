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

    function test_Can_Vest_When_Paused() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);
        vm.warp(block.timestamp + 52 weeks);

        // pause
        rewardEscrowV2.pauseRewardEscrow();

        entryIDs.push(1);
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
}
