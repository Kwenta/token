// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DefaultStakingV2Setup} from "../utils/DefaultStakingV2Setup.t.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import "../utils/Constants.t.sol";

contract StakingRewardsOnBehalfActionsTests is DefaultStakingV2Setup {
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

    // TODO: test offering approval emits an event
    // TODO: test claiming rewards on behalf emits an event
    // TODO: test cannot approve self
}
