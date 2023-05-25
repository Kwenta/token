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

    // TODO: ensure tested for createVestingEntry
    function test_Should_Not_Append_Entries_With_0_Amount() public {
        vm.expectRevert(IRewardEscrowV2.ZeroAmount.selector);
        vm.prank(address(stakingRewardsV2));
        rewardEscrowV2.appendVestingEntry(address(this), 0, 52 weeks);
    }

    // TODO: ensure tested for createVestingEntry
    function test_Should_Not_Create_A_Vesting_Entry_Insufficient_Kwenta() public {
        vm.expectRevert(IRewardEscrowV2.InsufficientBalance.selector);
        vm.prank(address(stakingRewardsV2));
        rewardEscrowV2.appendVestingEntry(address(this), 1 ether, 52 weeks);
    }

    function test_Should_Revert_If_Not_StakingRewards() public {
        vm.expectRevert(IRewardEscrowV2.OnlyStakingRewards.selector);
        rewardEscrowV2.appendVestingEntry(address(this), 1 ether, 52 weeks);
    }

    // TODO: ensure tested for createVestingEntry
    function test_Should_Revert_If_Duration_Is_0() public {
        vm.prank(treasury);
        kwenta.transfer(address(rewardEscrowV2), 1 ether);
        vm.prank(address(stakingRewardsV2));
        vm.expectRevert(IRewardEscrowV2.InvalidDuration.selector);
        rewardEscrowV2.appendVestingEntry(address(this), 1 ether, 0);
    }

    // TODO: ensure tested for createVestingEntry
    function test_Should_Revert_If_Duration_Is_Greater_Than_Max() public {
        uint256 maxDuration = rewardEscrowV2.MAX_DURATION();
        vm.prank(treasury);
        kwenta.transfer(address(rewardEscrowV2), 1 ether);
        vm.prank(address(stakingRewardsV2));
        vm.expectRevert(IRewardEscrowV2.InvalidDuration.selector);
        rewardEscrowV2.appendVestingEntry(address(this), 1 ether, maxDuration + 1);
    }

    /*//////////////////////////////////////////////////////////////
                    Appending Vesting Schedules
    //////////////////////////////////////////////////////////////*/

    function test_Should_Return_Vesting_Entry() public {
        appendRewardEscrowEntryV2(address(this), 10 ether, 52 weeks);

        (uint64 endTime, uint256 escrowAmount, uint256 duration, uint8 earlyVestingFee) =
            rewardEscrowV2.getVestingEntry(1);

        assertEq(endTime, block.timestamp + 52 weeks);
        assertEq(escrowAmount, 10 ether);
        assertEq(duration, 52 weeks);
        assertEq(earlyVestingFee, 90);
    }

    function test_Should_Increment_nextEntryId() public {
        appendRewardEscrowEntryV2(address(this), 10 ether, 52 weeks);
        assertEq(rewardEscrowV2.nextEntryId(), 2);
    }

    function test_totalEscrowBalanceOf_Should_Be_Incremented() public {
        appendRewardEscrowEntryV2(address(this), 10 ether, 52 weeks);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 10 ether);
    }

    function test_totalVestedAccountBalance_Should_Be_Zero() public {
        appendRewardEscrowEntryV2(address(this), 10 ether, 52 weeks);
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);
    }

    function test_balanceOf_Should_Be_Incremented() public {
        appendRewardEscrowEntryV2(address(this), 10 ether, 52 weeks);
        assertEq(rewardEscrowV2.balanceOf(address(this)), 1);
    }
}
