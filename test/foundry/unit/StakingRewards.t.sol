// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {StakingRewardsTestHelpers} from "../utils/StakingRewardsTestHelpers.t.sol";
import "../utils/Constants.t.sol";

contract StakingRewardsTests is StakingRewardsTestHelpers {
    /*//////////////////////////////////////////////////////////////
                        Unstaking During Cooldown
    //////////////////////////////////////////////////////////////*/

    function testStakingRewardsOneStaker() public {
        // this is 7 days by default
        uint256 lengthOfPeriod = stakingRewardsV1.rewardsDuration();
        uint256 initialStake = 1 ether;

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV1(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV1.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // send in 604800 (1 week) of rewards - (using 1 week for round numbers)
        uint256 newRewards = 1 weeks;
        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV1), newRewards);
        vm.prank(address(supplySchedule));
        stakingRewardsV1.notifyRewardAmount(newRewards);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + lengthOfPeriod);

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
        uint256 expectedRewards = 1 weeks;

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        // send in another 604800 (1 week) of rewards
        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV1), newRewards);
        vm.prank(address(supplySchedule));
        stakingRewardsV1.notifyRewardAmount(newRewards);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + lengthOfPeriod);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        // we exect the same amount of rewards again as this week was exactly the same as the previous one
        uint256 numberOfPeriods = 2;
        assertEq(rewards, expectedRewards * numberOfPeriods);
    }

    function testStakingRewardsOneStakerFuzz(uint64 _initialStake, uint64 _reward, uint24 _waitTime) public {
        uint256 initialStake = uint256(_initialStake);
        uint256 reward = uint256(_reward);
        uint256 waitTime = uint256(_waitTime);
        vm.assume(initialStake > 0);

        // this is 7 days by default
        uint256 rewardsDuration = stakingRewardsV1.rewardsDuration();

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV1(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV1.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // send in 604800 (1 week) of rewards - (using 1 week for round numbers)
        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV1), reward);
        vm.prank(address(supplySchedule));
        stakingRewardsV1.notifyRewardAmount(reward);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // general formula for rewards should be:
        // rewardRate = reward / rewardsDuration
        // newRewards = rewardRate * min(timePassed, rewardsDuration)
        // rewardPerToken = previousRewards + (newRewards * 1e18 / totalSupply)
        // rewardsPerTokenForUser = rewardPerToken - rewardPerTokenPaid
        // rewards = (balance * rewardsPerTokenForUser) / 1e18

        // applying this calculation to the test case:
        // rewardRate = reward / 1 weeks
        // newRewards = rewardRate * min(1 weeks, 1 weeks)
        // rewardPerToken = 0 + (newRewards * 1e18 / initialStake)
        // rewardsPerTokenForUser = rewardPerToken - 0 = rewardPerToken
        // rewards = (initialStake * rewardsPerTokenForUser) / 1e18

        uint256 rewardRate = reward / rewardsDuration;
        uint256 newRewards = rewardRate * min(waitTime, rewardsDuration);
        uint256 previousRewardPerToken = 0;
        uint256 rewardPerToken = previousRewardPerToken + (newRewards * 1e18 / initialStake);
        uint256 rewardsPerTokenPaid = 0;
        uint256 rewardsPerTokenForUser = rewardPerToken - rewardsPerTokenPaid;
        uint256 expectedRewards = initialStake * rewardsPerTokenForUser / 1e18;

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        // ----------------------------------------------

        // // send in another 604800 (1 week) of rewards
        // vm.prank(treasury);
        // kwenta.transfer(address(stakingRewardsV1), newRewards);
        // vm.prank(address(supplySchedule));
        // stakingRewardsV1.notifyRewardAmount(newRewards);

        // // fast forward 1 week - one complete period
        // vm.warp(block.timestamp + lengthOfPeriod);

        // // get the rewards
        // vm.prank(user1);
        // stakingRewardsV1.getReward();

        // // check rewards
        // rewards = rewardEscrowV1.balanceOf(user1);
        // // we exect the same amount of rewards again as this week was exactly the same as the previous one
        // uint256 numberOfPeriods = 2;
        // assertEq(rewards, expectedRewards * numberOfPeriods);
    }

    function testStakingRewardsOneStakerSmallIntervals() public {
        // this is 7 days by default
        uint256 lengthOfPeriod = stakingRewardsV1.rewardsDuration();
        uint256 initialStake = 1 ether;

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV1(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV1.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // send in 604800 (1 week) of rewards - (using 1 week for round numbers)
        uint256 newRewards = 1 weeks;
        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV1), newRewards);
        vm.prank(address(supplySchedule));
        stakingRewardsV1.notifyRewardAmount(newRewards);

        // fast forward 0.5 weeks - half of one complete period
        vm.warp(block.timestamp + lengthOfPeriod / 2);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // general formula for rewards should be:
        // newRewards = reward * min(timePassed, 1 weeks) / 1 weeks
        // rewardPerToken = previousRewards + (newRewards * 1e18 / totalSupply)
        // rewardsPerTokenForUser = rewardPerToken - rewardPerTokenPaid
        // rewards = (balance * rewardsPerTokenForUser) / 1e18

        // applying this calculation to the test case:
        // newRewards = 1 weeks * min(0.5 weeks, 1 weeks) / 1 weeks = 0.5 weeks
        // rewardPerToken = 0 + (0.5 weeks * 1e18 / 1 ether) = 0.5 weeks
        // rewardsPerTokenForUser = 0.5 weeks - 0 = 0.5 weeks
        // rewards = (1 ether * 0.5 weeks) / 1e18 = 0.5 weeks
        uint256 expectedRewards = 1 weeks / 2;

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        // fast forward 0.5 weeks - to the end of this period
        vm.warp(block.timestamp + lengthOfPeriod / 2);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        // we exect to claim the other half of this weeks rewards
        assertEq(rewards, expectedRewards * 2);
    }
}
