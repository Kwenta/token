// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {StakingRewardsTestHelpers} from "../utils/StakingRewardsTestHelpers.t.sol";
import "../utils/Constants.t.sol";

contract StakingRewardsTests is StakingRewardsTestHelpers {
    /*//////////////////////////////////////////////////////////////
                        Unstaking During Cooldown
    //////////////////////////////////////////////////////////////*/

    function testStakingRewards() public {
        // fund so totalSupply is 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV1(user1, 1 ether);

        // get initial rewards
        uint256 initialRewards = rewardEscrowV1.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(initialRewards, 0);


        // send in 604800 (1 week) of rewards
        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV1), 1 weeks);
        vm.prank(address(supplySchedule));
        stakingRewardsV1.notifyRewardAmount(1 weeks);

        // TODO: test with half a period
        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + 1 weeks);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // general formula for rewards should be:
        // newRewards = reward * min(timePassed, 1 weeks) / 1 weeks
        // rewardPerToken = previousRewards + (newRewards * 1e18 / totalSupply)
        // rewardsPerTokenForUser = rewardPerToken - rewardPerTokenPaid
        // rewards = (balance * rewardsPerTokenForUser) / 1e18

        // applying this calculation to the test case:
        // newRewards = 1 weeks * min(1 weeks, 1 weeks) / 1 weeks = 1 weeks
        // rewardPerToken = 0 + (1 weeks * 1e18 / 1 ether) = 1 weeks
        // rewardsPerTokenForUser = 1 weeks - 0 = 1 weeks
        // rewards = (1 ether * 1 weeks) / 1e18 = 1 weeks

        // check rewards
        uint256 finalRewards = rewardEscrowV1.balanceOf(user1);
        assertEq(finalRewards, initialRewards + 1 weeks);
    }
}
