// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../utils/DefaultStakingV2Setup.t.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import "../utils/Constants.t.sol";

contract StakingRewardsOnBehalfActionsTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                            Access Control
    //////////////////////////////////////////////////////////////*/

    function test_Only_Approved_Can_Call_getRewardOnBehalf() public {
        fundAccountAndStakeV2(address(this), TEST_VALUE);
        addNewRewardsToStakingRewardsV2(1 weeks);
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // approve user1 as operator
        stakingRewardsV2.approveOperator(user1, true);

        // claim rewards on behalf as user2
        vm.prank(user2);
        vm.expectRevert(StakingRewardsV2.NotApprovedOperator.selector);
        stakingRewardsV2.getRewardOnBehalf(address(this));
    }

    function test_Only_Approved_Can_Call_getRewardOnBehalf_Fuzz(
        uint32 fundingAmount,
        uint32 newRewards,
        address owner,
        address operator,
        address caller
    ) public {
        vm.assume(fundingAmount > 0);
        vm.assume(newRewards > stakingRewardsV2.rewardsDuration());
        vm.assume(owner != address(0));
        vm.assume(operator != address(0));
        vm.assume(caller != address(0));
        vm.assume(owner != operator);
        vm.assume(owner != caller);
        vm.assume(operator != caller);

        fundAccountAndStakeV2(owner, fundingAmount);
        addNewRewardsToStakingRewardsV2(newRewards);
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // approve user1 as operator
        stakingRewardsV2.approveOperator(operator, true);

        // claim rewards on behalf as user2
        vm.prank(caller);
        vm.expectRevert(StakingRewardsV2.NotApprovedOperator.selector);
        stakingRewardsV2.getRewardOnBehalf(address(this));
    }

    function test_Cannot_Approve_Self() public {
        vm.expectRevert(StakingRewardsV2.CannotApproveSelf.selector);
        stakingRewardsV2.approveOperator(address(this), true);
    }

    function test_Cannot_Approve_Self_Fuzz(address owner) public {
        vm.expectRevert(StakingRewardsV2.CannotApproveSelf.selector);
        vm.prank(owner);
        stakingRewardsV2.approveOperator(owner, true);
    }

    /*//////////////////////////////////////////////////////////////
                        Get Reward On Behalf
    //////////////////////////////////////////////////////////////*/

    function test_getRewardOnBehalf() public {
        fundAccountAndStakeV2(address(this), TEST_VALUE);

        // assert initial rewards are 0
        assertEq(rewardEscrowV2.balanceOf(address(this)), 0);
        assertEq(rewardEscrowV2.balanceOf(user1), 0);

        // send in 604800 (1 week) of rewards - (using 1 week for round numbers)
        addNewRewardsToStakingRewardsV2(1 weeks);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // approve operator
        stakingRewardsV2.approveOperator(user1, true);

        // claim rewards on behalf
        vm.prank(user1);
        stakingRewardsV2.getRewardOnBehalf(address(this));

        // check rewards
        assertEq(rewardEscrowV2.balanceOf(address(this)), 1 weeks);
        assertEq(rewardEscrowV2.balanceOf(user1), 0);
    }

    function test_getRewardOnBehalf_Fuzz(
        uint32 fundingAmount,
        uint32 newRewards,
        address owner,
        address operator
    ) public {
        vm.assume(fundingAmount > 0);
        vm.assume(newRewards > stakingRewardsV2.rewardsDuration());
        vm.assume(owner != address(0));
        vm.assume(operator != address(0));
        vm.assume(operator != owner);

        fundAccountAndStakeV2(owner, fundingAmount);

        // assert initial rewards are 0
        assertEq(rewardEscrowV2.balanceOf(owner), 0);
        assertEq(rewardEscrowV2.balanceOf(operator), 0);

        // send in rewards
        addNewRewardsToStakingRewardsV2(newRewards);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // approve operator
        vm.prank(owner);
        stakingRewardsV2.approveOperator(operator, true);

        // claim rewards on behalf
        vm.prank(operator);
        stakingRewardsV2.getRewardOnBehalf(owner);

        // check rewards
        assertGt(rewardEscrowV2.balanceOf(owner), 0);
        assertEq(rewardEscrowV2.balanceOf(operator), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        Stake Escrow On Behalf
    //////////////////////////////////////////////////////////////*/

    function test_stakeEscrowOnBehalf() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);

        // assert initial escrowed balances
        assertEq(stakingRewardsV2.escrowedBalanceOf(address(this)), 0);
        assertEq(stakingRewardsV2.escrowedBalanceOf(user1), 0);

        // approve operator
        stakingRewardsV2.approveOperator(user1, true);

        // stake escrow on behalf
        vm.prank(user1);
        stakingRewardsV2.stakeEscrowOnBehalf(address(this), TEST_VALUE);

        // check final escrowed balances
        assertEq(stakingRewardsV2.escrowedBalanceOf(address(this)), TEST_VALUE);
        assertEq(stakingRewardsV2.escrowedBalanceOf(user1), 0);
    }

    function test_stakeEscrowOnBehalf_Fuzz(
        address owner,
        address operator,
        uint32 escrowAmount,
        uint24 duration
    ) public {
        vm.assume(escrowAmount > 0);
        vm.assume(duration > 0);
        vm.assume(owner != address(0));
        vm.assume(operator != address(0));
        vm.assume(owner != operator);

        createRewardEscrowEntryV2(owner, escrowAmount, duration);

        // assert initial escrowed balances
        assertEq(stakingRewardsV2.escrowedBalanceOf(owner), 0);
        assertEq(stakingRewardsV2.escrowedBalanceOf(operator), 0);

        // approve operator
        vm.prank(owner);
        stakingRewardsV2.approveOperator(operator, true);

        // stake escrow on behalf
        vm.prank(operator);
        stakingRewardsV2.stakeEscrowOnBehalf(owner, escrowAmount);

        // check final escrowed balances
        assertEq(stakingRewardsV2.escrowedBalanceOf(owner), escrowAmount);
        assertEq(stakingRewardsV2.escrowedBalanceOf(operator), 0);
    }

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    function test_approveOperator_Emits_Event() public {
        vm.expectEmit(true, true, true, true);
        emit OperatorApproved(address(this), user1, true);
        stakingRewardsV2.approveOperator(user1, true);
    }

    function test_approveOperator_Emits_Event_Fuzz(
        address owner,
        address operator,
        bool approved
    ) public {
        vm.assume(owner != address(0));
        vm.assume(operator != address(0));
        vm.assume(owner != operator);

        vm.expectEmit(true, true, true, true);
        emit OperatorApproved(owner, operator, approved);
        vm.prank(owner);
        stakingRewardsV2.approveOperator(operator, approved);
    }

    function test_getRewardOnBehalf_Emits_Event() public {
        fundAccountAndStakeV2(address(this), TEST_VALUE);
        addNewRewardsToStakingRewardsV2(1 weeks);
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // approve operator
        stakingRewardsV2.approveOperator(user1, true);

        // claim rewards on behalf
        vm.expectEmit(true, true, false, true);
        emit RewardPaid(address(this), 1 weeks);
        vm.prank(user1);
        stakingRewardsV2.getRewardOnBehalf(address(this));
    }

    // TODO: test staking on behalf emits an event
    // TODO: test getReward then staking Reward
    // TODO: test automated contract
}
