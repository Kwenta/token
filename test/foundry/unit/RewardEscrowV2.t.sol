// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../utils/DefaultStakingV2Setup.t.sol";
import {IRewardEscrowV2} from "../../../contracts/interfaces/IRewardEscrowV2.sol";
import "../utils/Constants.t.sol";

contract RewardEscrowV2Tests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                        Deploys Correctly
    //////////////////////////////////////////////////////////////*/

    function test_Should_Have_A_Kwenta_Token() public {
        assertEq(address(rewardEscrowV2.getKwentaAddress()), address(kwenta));
    }

    function test_Should_Set_Owner() public {
        assertEq(address(rewardEscrowV2.owner()), address(this));
    }

    function test_Should_Set_StakingRewards() public {
        assertEq(address(rewardEscrowV2.stakingRewardsV2()), address(stakingRewardsV2));
    }

    function test_Should_Set_Treasury() public {
        assertEq(address(rewardEscrowV2.treasuryDAO()), address(treasury));
    }

    function test_Should_Not_Allow_Treasury_To_Be_Set_To_Zero_Address() public {
        vm.expectRevert(IRewardEscrowV2.ZeroAddress.selector);
        rewardEscrowV2.setTreasuryDAO(address(0));
    }

    function test_Should_Not_Allow_StakingRewards_To_Be_Set_Twice() public {
        vm.expectRevert(IRewardEscrowV2.StakingRewardsAlreadySet.selector);
        rewardEscrowV2.setStakingRewardsV2(address(stakingRewardsV1));
    }

    function test_Should_Set_nextEntryId_To_1() public {
        assertEq(rewardEscrowV2.nextEntryId(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                        When No Escrow Entries
    //////////////////////////////////////////////////////////////*/

    function test_totalSupply_Should_Be_0() public {
        assertEq(rewardEscrowV2.totalSupply(), 0);
    }

    function test_balanceOf_Should_Be_0() public {
        assertEq(rewardEscrowV2.balanceOf(address(this)), 0);
    }

    function test_totalEscrowedAccountBalance_Should_Be_0() public {
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 0);
    }

    function test_totalVestedAccountBalance_Should_Be_0() public {
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);
    }

    function test_vest_Should_Do_Nothing_And_Not_Revert() public {
        entryIDs.push(0);
        rewardEscrowV2.vest(entryIDs);
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                Appending Vesting Schedules Error
    //////////////////////////////////////////////////////////////*/

    function test_appendVestingEntry_Should_Not_Append_Entries_With_0_Amount() public {
        vm.expectRevert(IRewardEscrowV2.ZeroAmount.selector);
        vm.prank(address(stakingRewardsV2));
        rewardEscrowV2.appendVestingEntry(address(this), 0, 52 weeks);
    }

    function test_appendVestingEntry_Should_Not_Create_A_Vesting_Entry_Insufficient_Kwenta() public {
        vm.expectRevert(IRewardEscrowV2.InsufficientBalance.selector);
        vm.prank(address(stakingRewardsV2));
        rewardEscrowV2.appendVestingEntry(address(this), 1 ether, 52 weeks);
    }

    function test_appendVestingEntry_Should_Revert_If_Not_StakingRewards() public {
        vm.expectRevert(IRewardEscrowV2.OnlyStakingRewards.selector);
        rewardEscrowV2.appendVestingEntry(address(this), 1 ether, 52 weeks);
    }

    function test_appendVestingEntry_Should_Revert_If_Duration_Is_0() public {
        vm.prank(treasury);
        kwenta.transfer(address(rewardEscrowV2), 1 ether);
        vm.prank(address(stakingRewardsV2));
        vm.expectRevert(IRewardEscrowV2.InvalidDuration.selector);
        rewardEscrowV2.appendVestingEntry(address(this), 1 ether, 0);
    }

    function test_appendVestingEntry_Should_Revert_If_Duration_Is_Greater_Than_Max() public {
        uint256 maxDuration = rewardEscrowV2.MAX_DURATION();
        vm.prank(treasury);
        kwenta.transfer(address(rewardEscrowV2), 1 ether);
        vm.prank(address(stakingRewardsV2));
        vm.expectRevert(IRewardEscrowV2.InvalidDuration.selector);
        rewardEscrowV2.appendVestingEntry(address(this), 1 ether, maxDuration + 1);
    }

    function test_appendVestingEntry_Should_Revert_If_Beneficiary_Address_Is_Zero() public {
        vm.prank(treasury);
        kwenta.transfer(address(rewardEscrowV2), 1 ether);
        vm.prank(address(stakingRewardsV2));
        vm.expectRevert("ERC721: mint to the zero address");
        rewardEscrowV2.appendVestingEntry(address(0), 1 ether, 52 weeks);
    }

    /*//////////////////////////////////////////////////////////////
                        Appending Vesting Schedules
    //////////////////////////////////////////////////////////////*/

    function test_Should_Return_Vesting_Entry() public {
        appendRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);

        (uint64 endTime, uint256 escrowAmount, uint256 duration, uint8 earlyVestingFee) =
            rewardEscrowV2.getVestingEntry(1);

        assertEq(endTime, block.timestamp + 52 weeks);
        assertEq(escrowAmount, TEST_VALUE);
        assertEq(duration, 52 weeks);
        assertEq(earlyVestingFee, 90);
    }

    function test_Should_Increment_nextEntryId() public {
        appendRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);
        assertEq(rewardEscrowV2.nextEntryId(), 2);
    }

    function test_totalEscrowBalanceOf_Should_Be_Incremented() public {
        appendRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), TEST_VALUE);
    }

    function test_totalVestedAccountBalance_Should_Be_Zero() public {
        appendRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);
    }

    function test_balanceOf_Should_Be_Incremented() public {
        appendRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);
        assertEq(rewardEscrowV2.balanceOf(address(this)), 1);
    }

    function test_Correct_Amount_Claimable_After_6_Months() public {
        appendRewardEscrowEntryV2(address(this), 10 ether, 52 weeks);

        vm.warp(block.timestamp + 26 weeks);

        (uint256 claimable,) = rewardEscrowV2.getVestingEntryClaimable(1);
        assertEq(claimable, 11 ether / 2);
    }

    function test_Correct_Amount_Claimable_After_6_Months_Fuzz(uint32 _amount) public {
        uint256 amount = _amount;
        vm.assume(amount > 0);

        appendRewardEscrowEntryV2(address(this), amount, 52 weeks);

        vm.warp(block.timestamp + 26 weeks);

        (uint256 claimable, uint256 fee) = rewardEscrowV2.getVestingEntryClaimable(1);

        uint256 maxFee = amount * 90 / 100;
        uint256 earlyVestFee = maxFee * 26 weeks / 52 weeks;
        uint256 expectedClaimable = amount - earlyVestFee;

        assertEq(claimable, expectedClaimable);
        assertEq(fee, earlyVestFee);
    }

    function test_Correct_Amount_Claimable_After_1_Year() public {
        appendRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);

        vm.warp(block.timestamp + 52 weeks);

        (uint256 claimable,) = rewardEscrowV2.getVestingEntryClaimable(1);
        assertEq(claimable, TEST_VALUE);
    }

    // TODO: create full fuzz test for different claim, amounts, waitTime and duration
    function test_Correct_Amount_Claimable_After_1_Year_Fuzz(uint32 _amount) public {
        uint256 amount = _amount;
        vm.assume(amount > 0);

        appendRewardEscrowEntryV2(address(this), amount, 52 weeks);

        vm.warp(block.timestamp + 52 weeks);

        (uint256 claimable,) = rewardEscrowV2.getVestingEntryClaimable(1);
        assertEq(claimable, amount);
    }

    /*//////////////////////////////////////////////////////////////
                    Creating Vesting Schedules Errors
    //////////////////////////////////////////////////////////////*/

    function test_createEscrowEntry_Should_Not_Append_Entries_With_0_Amount() public {
        vm.expectRevert(IRewardEscrowV2.ZeroAmount.selector);
        rewardEscrowV2.createEscrowEntry(address(this), 0, 52 weeks, 90);
    }

    function test_createEscrowEntry_Should_Not_Create_A_Vesting_Entry_Without_Allowance() public {
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        rewardEscrowV2.createEscrowEntry(address(this), TEST_VALUE, 52 weeks, 90);
    }

    function test_createEscrowEntry_Should_Revert_If_Duration_Is_0() public {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), TEST_VALUE);
        vm.expectRevert(IRewardEscrowV2.InvalidDuration.selector);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(address(this), TEST_VALUE, 0, 90);
    }

    function test_createEscrowEntry_Should_Revert_If_Duration_Is_Greater_Than_Max() public {
        uint256 maxDuration = rewardEscrowV2.MAX_DURATION();
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), TEST_VALUE);
        vm.expectRevert(IRewardEscrowV2.InvalidDuration.selector);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(address(this), TEST_VALUE, maxDuration + 1, 90);
    }

    function test_createEscrowEntry_Should_Revert_If_Beneficiary_Address_Is_Zero() public {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), TEST_VALUE);
        vm.expectRevert(IRewardEscrowV2.ZeroAddress.selector);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(address(0), TEST_VALUE, 52 weeks, 90);
    }

    function test_createEscrowEntry_Should_Revert_If_Early_Vesting_Fee_Is_0() public {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), TEST_VALUE);
        vm.expectRevert(IRewardEscrowV2.ZeroEarlyVestingFee.selector);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(address(this), TEST_VALUE, 52 weeks, 0);
    }

    function test_createEscrowEntry_Should_Revert_If_Early_Vesting_Fee_Is_Over_100() public {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), 1 ether);
        vm.expectRevert(IRewardEscrowV2.EarlyVestingFeeTooHigh.selector);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(address(this), 1 ether, 52 weeks, 101);
    }

    /*//////////////////////////////////////////////////////////////
                        Creating Vesting Schedules
    //////////////////////////////////////////////////////////////*/

    function test_Creates_New_Vesting_Entry() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks, 90);

        (uint64 endTime, uint256 escrowAmount, uint256 duration, uint8 earlyVestingFee) =
            rewardEscrowV2.getVestingEntry(1);

        assertEq(endTime, block.timestamp + 52 weeks);
        assertEq(escrowAmount, TEST_VALUE);
        assertEq(duration, 52 weeks);
        assertEq(earlyVestingFee, 90);
    }

    function test_Increments_The_Next_Entry_ID() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks, 90);
        assertEq(rewardEscrowV2.nextEntryId(), 2);
    }

    function test_Increments_totalEscrowedBalance() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks, 90);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), TEST_VALUE);
    }
}
