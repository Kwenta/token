// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../utils/DefaultStakingV2Setup.t.sol";
import {IRewardEscrowV2} from "../../../contracts/interfaces/IRewardEscrowV2.sol";
import "../utils/Constants.t.sol";

contract RewardEscrowV2VestingChangesTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                        Variable Early Vesting Fee
    //////////////////////////////////////////////////////////////*/

    function test_Max_Duration() public {
        assertEq(rewardEscrowV2.MAX_DURATION(), 4 * 52 weeks);
    }

    function test_Default_Early_Vest_Fee_Is_90_Percent() public {
        appendRewardEscrowEntryV2(user1, 1 ether, 52 weeks);
        (,,, uint8 earlyVestingFee) = rewardEscrowV2.getVestingEntry(1);

        assertEq(rewardEscrowV2.DEFAULT_EARLY_VESTING_FEE(), 90);
        assertEq(earlyVestingFee, rewardEscrowV2.DEFAULT_EARLY_VESTING_FEE());
    }

    function test_Default_Early_Vest_Fee_Is_90_Percent_Fuzz(uint32 escrowAmount, uint24 duration)
        public
    {
        vm.assume(escrowAmount > 0);
        vm.assume(duration > 0);

        appendRewardEscrowEntryV2(user1, escrowAmount, duration);
        (,,, uint8 earlyVestingFee) = rewardEscrowV2.getVestingEntry(1);

        assertEq(rewardEscrowV2.DEFAULT_EARLY_VESTING_FEE(), 90);
        assertEq(earlyVestingFee, rewardEscrowV2.DEFAULT_EARLY_VESTING_FEE());
    }

    function test_Can_Set_Early_Vesting_Fee_On_Entry() public {
        uint8 earlyVestingFee = 50;

        createRewardEscrowEntryV2(user1, 1 ether, 52 weeks, earlyVestingFee);
        (,,, uint8 earlyVestingFeeAfter) = rewardEscrowV2.getVestingEntry(1);

        assertEq(earlyVestingFeeAfter, earlyVestingFee);
    }

    function test_Can_Set_Early_Vesting_Fee_On_Entry_Fuzz(
        uint32 escrowAmount,
        uint24 duration,
        uint8 earlyVestingFee
    ) public {
        vm.assume(escrowAmount > 0);
        vm.assume(duration > 0);
        vm.assume(earlyVestingFee <= 100);

        createRewardEscrowEntryV2(user1, escrowAmount, duration, earlyVestingFee);
        (,,, uint8 earlyVestingFeeAfter) = rewardEscrowV2.getVestingEntry(1);

        assertEq(earlyVestingFeeAfter, earlyVestingFee);
    }

    function test_Cannot_Set_Early_Vesting_Fee_Above_100() public {
        uint8 earlyVestingFee = 101;

        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), 1 ether);

        vm.prank(treasury);
        vm.expectRevert(IRewardEscrowV2.MaxEarlyVestingFeeIs100.selector);
        rewardEscrowV2.createEscrowEntry(user1, 1 ether, 52 weeks, earlyVestingFee);
    }

    function test_Cannot_Set_Early_Vesting_Fee_Above_100_Fuzz(
        uint8 earlyVestingFee,
        uint32 escrowAmount,
        uint24 duration
    ) public {
        vm.assume(earlyVestingFee > 100);
        vm.assume(escrowAmount > 0);
        vm.assume(duration > 0);

        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), escrowAmount);

        vm.prank(treasury);
        vm.expectRevert(IRewardEscrowV2.MaxEarlyVestingFeeIs100.selector);
        rewardEscrowV2.createEscrowEntry(user1, escrowAmount, duration, earlyVestingFee);
    }

    function test_Variable_Entry_Early_Vesting_Fee_Is_Applied() public {
        uint256 escrowAmount = 1 ether;
        uint256 duration = 52 weeks;
        uint8 earlyVestingFee = 20;

        // create entry
        createRewardEscrowEntryV2(user1, escrowAmount, duration, earlyVestingFee);
        uint256 balanceBefore = kwenta.balanceOf(user1);

        // vest entry
        entryIDs.push(1);
        vm.prank(user1);
        rewardEscrowV2.vest(entryIDs);

        // check vested balance
        uint256 balanceAfter = kwenta.balanceOf(user1);
        uint256 amountVestedAfterFee = escrowAmount - (escrowAmount * earlyVestingFee / 100);
        assertEq(balanceAfter, balanceBefore + amountVestedAfterFee);
    }

    function test_Variable_Entry_Early_Vesting_Fee_Is_Applied_Fuzz(
        uint32 _escrowAmount,
        uint24 _duration,
        uint8 _earlyVestingFee
    ) public {
        uint256 escrowAmount = _escrowAmount;
        uint256 duration = _duration;
        uint8 earlyVestingFee = _earlyVestingFee;

        vm.assume(escrowAmount > 0);
        vm.assume(duration > 0);
        vm.assume(earlyVestingFee <= 100);

        // create entry
        createRewardEscrowEntryV2(user1, escrowAmount, duration, earlyVestingFee);
        uint256 balanceBefore = kwenta.balanceOf(user1);

        // vest entry
        entryIDs.push(1);
        vm.prank(user1);
        rewardEscrowV2.vest(entryIDs);

        // check vested balance
        uint256 balanceAfter = kwenta.balanceOf(user1);
        uint256 amountVestedAfterFee = escrowAmount - (escrowAmount * earlyVestingFee / 100);
        assertEq(balanceAfter, balanceBefore + amountVestedAfterFee);
    }

    /*//////////////////////////////////////////////////////////////
                        Can Vest When Staked
    //////////////////////////////////////////////////////////////*/

    function test_Can_Vest_When_Escrow_Staked_Within_Cooldown() public {
        uint256 escrowAmount = 1 ether;
        uint256 duration = 52 weeks;
        uint8 earlyVestingFee = 20;

        // create entry
        createRewardEscrowEntryV2(user1, escrowAmount, duration, earlyVestingFee);
        uint256 balanceBefore = kwenta.balanceOf(user1);

        // stake escrow
        vm.prank(user1);
        rewardEscrowV2.stakeEscrow(escrowAmount);

        // vest entry
        entryIDs.push(1);
        vm.prank(user1);
        rewardEscrowV2.vest(entryIDs);

        // check vested balance
        uint256 balanceAfter = kwenta.balanceOf(user1);
        uint256 amountVestedAfterFee = escrowAmount - (escrowAmount * earlyVestingFee / 100);
        assertEq(balanceAfter, balanceBefore + amountVestedAfterFee);
    }

    function test_Can_Vest_When_Escrow_Staked_Within_Cooldown_Fuzz(
        uint32 _escrowAmount,
        uint32 _stakingAmount,
        uint24 _duration,
        uint8 _earlyVestingFee
    ) public {
        uint256 escrowAmount = _escrowAmount;
        uint256 stakingAmount = _stakingAmount;
        uint256 duration = _duration;
        uint8 earlyVestingFee = _earlyVestingFee;

        vm.assume(escrowAmount > 0);
        vm.assume(stakingAmount > 0);
        vm.assume(stakingAmount <= escrowAmount);
        vm.assume(duration > 0);
        vm.assume(earlyVestingFee <= 100);

        // create entry
        createRewardEscrowEntryV2(user1, escrowAmount, duration, earlyVestingFee);
        uint256 balanceBefore = kwenta.balanceOf(user1);

        // stake escrow
        vm.prank(user1);
        rewardEscrowV2.stakeEscrow(escrowAmount);

        // vest entry
        entryIDs.push(1);
        vm.prank(user1);
        rewardEscrowV2.vest(entryIDs);

        // check vested balance
        uint256 balanceAfter = kwenta.balanceOf(user1);
        uint256 amountVestedAfterFee = escrowAmount - (escrowAmount * earlyVestingFee / 100);
        assertEq(balanceAfter, balanceBefore + amountVestedAfterFee);
    }
}
