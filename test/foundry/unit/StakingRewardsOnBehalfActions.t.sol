// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DefaultStakingV2Setup} from "../utils/DefaultStakingV2Setup.t.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import "../utils/Constants.t.sol";

contract StakingRewardsOnBehalfActionsTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                        Get Reward On Behalf
    //////////////////////////////////////////////////////////////*/

    // TODO: fuzz test this
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

    // TODO: test using it without approval throws error
    // TODO: test offering approval emits an event
    // TODO: test claiming rewards on behalf emits an event
    // TODO: test cannot approve self
}
