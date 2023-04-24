// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {StakingRewardsTestHelpers} from "../utils/StakingRewardsTestHelpers.t.sol";
import "../utils/Constants.t.sol";

contract StakingV1RewardCalculationTests is StakingRewardsTestHelpers {
    /*//////////////////////////////////////////////////////////////
                    Staking Rewards Calculation Tests
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

    function testStakingRewardsOneStakerInSingleRewardPeriodFuzz(uint64 _initialStake, uint64 _reward, uint24 _waitTime)
        public
    {
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

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV1(reward, waitTime, initialStake);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV1(reward);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // calculate new rewards now
        uint256 newReward = 0;
        expectedRewards += getExpectedRewardV1(newReward, rewardsDuration, initialStake);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        assertEq(rewards, expectedRewards);
    }

    function testStakingRewardsMultipleStakersInSingleRewardPeriodFuzz(
        uint64 _initialStake,
        uint64 _reward,
        uint24 _waitTime
    ) public {
        uint256 initialStake = uint256(_initialStake);
        uint256 reward = uint256(_reward);
        uint256 waitTime = uint256(_waitTime);
        vm.assume(initialStake > 0);

        // this is 7 days by default
        uint256 rewardsDuration = stakingRewardsV1.rewardsDuration();

        // stake with other users
        fundAccountAndStakeV1(user2, getPseudoRandomNumber(10 ether, 1, initialStake));
        fundAccountAndStakeV1(user3, getPseudoRandomNumber(10 ether, 1, initialStake));
        fundAccountAndStakeV1(user4, getPseudoRandomNumber(10 ether, 1, initialStake));
        fundAccountAndStakeV1(user5, getPseudoRandomNumber(10 ether, 1, initialStake));

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV1(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV1.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV1(reward, waitTime, initialStake);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV1(reward);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // calculate new rewards now
        uint256 newReward = 0;
        expectedRewards += getExpectedRewardV1(newReward, rewardsDuration, initialStake);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        assertEq(rewards, expectedRewards);
    }

    function testStakingRewardsOneStakerTwoRewardPeriodsFuzz(uint64 _initialStake, uint64 _reward, uint24 _waitTime)
        public
    {
        uint256 initialStake = uint256(_initialStake);
        uint256 reward = uint256(_reward);
        uint256 waitTime = uint256(_waitTime);
        vm.assume(initialStake > 0);

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV1(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV1.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV1(reward, waitTime, initialStake);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV1(reward);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // get new pseudorandom reward and wait time
        uint256 newWaitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
        uint256 newReward = getPseudoRandomNumber(10 ether, 1, reward);

        // calculate new rewards now
        expectedRewards += getExpectedRewardV1(newReward, newWaitTime, initialStake);

        addNewRewardsToStakingRewardsV1(newReward);
        vm.warp(block.timestamp + newWaitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        assertEq(rewards, expectedRewards);
    }

    function testStakingRewardsThreeRoundsFuzz(uint64 _initialStake, uint64 _reward, uint24 _waitTime) public {
        uint256 initialStake = uint256(_initialStake);
        uint256 reward = uint256(_reward);
        uint256 waitTime = uint256(_waitTime);
        vm.assume(initialStake > 0);

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV1(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV1.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV1(reward, waitTime, initialStake);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV1(reward);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // get new pseudorandom reward and wait time
        waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
        reward = getPseudoRandomNumber(10 ether, 1, reward);

        // calculate new rewards now
        expectedRewards += getExpectedRewardV1(reward, waitTime, initialStake);

        addNewRewardsToStakingRewardsV1(reward);
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // get new pseudorandom reward and wait time
        waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
        reward = getPseudoRandomNumber(10 ether, 1, reward);

        // calculate new rewards now
        expectedRewards += getExpectedRewardV1(reward, waitTime, initialStake);

        addNewRewardsToStakingRewardsV1(reward);
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        assertEq(rewards, expectedRewards);
    }

    function testStakingRewardsMultipleRoundsFuzz(
        uint64 _initialStake,
        uint64 _reward,
        uint24 _waitTime,
        uint8 numberOfRounds
    ) public {
        uint256 initialStake = uint256(_initialStake);
        uint256 reward = uint256(_reward);
        uint256 waitTime = uint256(_waitTime);
        vm.assume(initialStake > 0);
        vm.assume(numberOfRounds < 100);

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV1(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV1.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV1(reward, waitTime, initialStake);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV1(reward);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        for (uint256 i = 0; i < numberOfRounds; i++) {
            // move forward to the end of the rewards period
            jumpToEndOfRewardsPeriod(waitTime);

            // get new pseudorandom reward and wait time
            waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
            reward = getPseudoRandomNumber(10 ether, 1, reward);

            // calculate new rewards now
            expectedRewards += getExpectedRewardV1(reward, waitTime, initialStake);

            addNewRewardsToStakingRewardsV1(reward);
            vm.warp(block.timestamp + waitTime);

            // get the rewards
            vm.prank(user1);
            stakingRewardsV1.getReward();

            // check rewards
            rewards = rewardEscrowV1.balanceOf(user1);
            assertEq(rewards, expectedRewards);
        }
    }

    function testStakingRewardsMultipleRoundsAndStakersFuzz(
        uint64 _initialStake,
        uint64 _reward,
        uint24 _waitTime,
        uint8 numberOfRounds,
        uint8 initialNumberOfStakers
    ) public {
        uint256 initialStake = uint256(_initialStake);
        uint256 reward = uint256(_reward);
        uint256 waitTime = uint256(_waitTime);
        vm.assume(initialStake > 0);
        vm.assume(numberOfRounds < 50);
        vm.assume(initialNumberOfStakers < 50);

        // other user
        for (uint256 i = 0; i < initialNumberOfStakers; i++) {
            address otherUser = createUser();
            fundAccountAndStakeV1(otherUser, getPseudoRandomNumber(10 ether, 1, initialStake));
        }

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV1(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV1.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV1(reward, waitTime, initialStake);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV1(reward);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV1.getReward();

        // check rewards
        rewards = rewardEscrowV1.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        for (uint256 i = 0; i < numberOfRounds; i++) {
            // add another staker
            address otherUser = createUser();
            fundAccountAndStakeV1(otherUser, getPseudoRandomNumber(10 ether, 1, initialStake));

            // move forward to the end of the rewards period
            jumpToEndOfRewardsPeriod(waitTime);

            // get new pseudorandom reward and wait time
            waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
            reward = getPseudoRandomNumber(10 ether, 1, reward);

            // calculate new rewards now
            expectedRewards += getExpectedRewardV1(reward, waitTime, initialStake);

            addNewRewardsToStakingRewardsV1(reward);
            vm.warp(block.timestamp + waitTime);

            // get the rewards
            vm.prank(user1);
            stakingRewardsV1.getReward();

            // check rewards
            rewards = rewardEscrowV1.balanceOf(user1);
            assertEq(rewards, expectedRewards);
        }
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
