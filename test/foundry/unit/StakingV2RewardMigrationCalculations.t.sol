// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {StakingRewardsTestHelpers} from "../utils/StakingRewardsTestHelpers.t.sol";
import "../utils/Constants.t.sol";

contract StakingV2RewardMigrationCalculationTests is StakingRewardsTestHelpers {
    /*//////////////////////////////////////////////////////////////
                    Rewards Migration Calculation Tests
    //////////////////////////////////////////////////////////////*/

    // TODO: check if this can be fuzzed
    function setUp() public virtual override {
        super.setUp();

        fundAccountAndStakeV2(user1, 1 ether);
        fundAccountAndStakeV2(user2, 1 ether);
        fundAccountAndStakeV2(user3, 1 ether);
        fundAccountAndStakeV2(user4, 1 ether);
        fundAccountAndStakeV2(user5, 1 ether);

        pauseAndSwitchToStakingRewardsV2();
    }

    function testStakingRewardsOneStaker() public {
        // this is 7 days by default
        uint256 lengthOfPeriod = stakingRewardsV2.rewardsDuration();
        uint256 initialStake = 1 ether;

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV2(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV2.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // send in 604800 (1 week) of rewards - (using 1 week for round numbers)
        uint256 newRewards = 1 weeks;
        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV2), newRewards);
        vm.prank(address(supplySchedule));
        stakingRewardsV2.notifyRewardAmount(newRewards);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + lengthOfPeriod);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV2.getReward();

        // general formula for rewards should be:
        // newRewards = reward * min(timePassed, 1 weeks) / 1 weeks
        // rewardPerToken = previousRewards + (newRewards * 1e18 / totalSupply)
        // rewardsPerTokenForUser = rewardPerToken - rewardPerTokenPaid
        // rewards = (balance * rewardsPerTokenForUser) / 1e18

        // applying this calculation to the test case:
        // newRewards = 1 weeks * min(1 weeks, 1 weeks) / 1 weeks = 1 weeks
        // totalSupply = stakingV1 totalSuplly + stakingV2 totalSupply = 5 ether + 1 ether = 6 ether
        // rewardPerToken = 0 + (1 weeks * 1e18 / 6 ether) = 1/6 weeks
        // rewardsPerTokenForUser = 1/6 weeks - 0 = 1/6 weeks
        // balance = stakingV1 balance + stakingV2 balance = 1 ether + 1 ether  = 2 ether
        // rewards = (2 ether * 1/6 weeks) / 1e18 = 1/3 weeks
        uint256 expectedRewards = 1 weeks / 3;

        // check rewards
        rewards = rewardEscrowV2.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        // send in another 604800 (1 week) of rewards
        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV2), newRewards);
        vm.prank(address(supplySchedule));
        stakingRewardsV2.notifyRewardAmount(newRewards);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + lengthOfPeriod);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV2.getReward();

        // check rewards
        rewards = rewardEscrowV2.balanceOf(user1);
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
        uint256 rewardsDuration = stakingRewardsV2.rewardsDuration();

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV2(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV2.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV2(reward);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV2.getReward();

        // check rewards
        rewards = rewardEscrowV2.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // calculate new rewards now
        uint256 newReward = 0;
        expectedRewards += getExpectedRewardV2(newReward, rewardsDuration, user1);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV2.getReward();

        // check rewards
        rewards = rewardEscrowV2.balanceOf(user1);
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
        uint256 rewardsDuration = stakingRewardsV2.rewardsDuration();

        // stake with other users
        fundAccountAndStakeV2(user2, getPseudoRandomNumber(10 ether, 1, initialStake));
        fundAccountAndStakeV2(user3, getPseudoRandomNumber(10 ether, 1, initialStake));
        fundAccountAndStakeV2(user4, getPseudoRandomNumber(10 ether, 1, initialStake));
        fundAccountAndStakeV2(user5, getPseudoRandomNumber(10 ether, 1, initialStake));

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV2(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV2.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV2(reward);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV2.getReward();

        // check rewards
        rewards = rewardEscrowV2.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // calculate new rewards now
        uint256 newReward = 0;
        expectedRewards += getExpectedRewardV2(newReward, rewardsDuration, user1);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV2.getReward();

        // check rewards
        rewards = rewardEscrowV2.balanceOf(user1);
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
        fundAccountAndStakeV2(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV2.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV2(reward);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV2.getReward();

        // check rewards
        rewards = rewardEscrowV2.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // get new pseudorandom reward and wait time
        uint256 newWaitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
        uint256 newReward = getPseudoRandomNumber(10 ether, 1, reward);

        // calculate new rewards now
        expectedRewards += getExpectedRewardV2(newReward, newWaitTime, user1);

        addNewRewardsToStakingRewardsV2(newReward);
        vm.warp(block.timestamp + newWaitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV2.getReward();

        // check rewards
        rewards = rewardEscrowV2.balanceOf(user1);
        assertEq(rewards, expectedRewards);
    }

    function testStakingRewardsThreeRoundsFuzz(uint64 _initialStake, uint64 _reward, uint24 _waitTime) public {
        uint256 initialStake = uint256(_initialStake);
        uint256 reward = uint256(_reward);
        uint256 waitTime = uint256(_waitTime);
        vm.assume(initialStake > 0);

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV2(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV2.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV2(reward);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV2.getReward();

        // check rewards
        rewards = rewardEscrowV2.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // get new pseudorandom reward and wait time
        waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
        reward = getPseudoRandomNumber(10 ether, 1, reward);

        // calculate new rewards now
        expectedRewards += getExpectedRewardV2(reward, waitTime, user1);

        addNewRewardsToStakingRewardsV2(reward);
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV2.getReward();

        // check rewards
        rewards = rewardEscrowV2.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // get new pseudorandom reward and wait time
        waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
        reward = getPseudoRandomNumber(10 ether, 1, reward);

        // calculate new rewards now
        expectedRewards += getExpectedRewardV2(reward, waitTime, user1);

        addNewRewardsToStakingRewardsV2(reward);
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV2.getReward();

        // check rewards
        rewards = rewardEscrowV2.balanceOf(user1);
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
        fundAccountAndStakeV2(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV2.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV2(reward);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV2.getReward();

        // check rewards
        rewards = rewardEscrowV2.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        for (uint256 i = 0; i < numberOfRounds; i++) {
            // move forward to the end of the rewards period
            jumpToEndOfRewardsPeriod(waitTime);

            // get new pseudorandom reward and wait time
            waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
            reward = getPseudoRandomNumber(10 ether, 1, reward);

            // calculate new rewards now
            expectedRewards += getExpectedRewardV2(reward, waitTime, user1);

            addNewRewardsToStakingRewardsV2(reward);
            vm.warp(block.timestamp + waitTime);

            // get the rewards
            vm.prank(user1);
            stakingRewardsV2.getReward();

            // check rewards
            rewards = rewardEscrowV2.balanceOf(user1);
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
            fundAccountAndStakeV2(otherUser, getPseudoRandomNumber(10 ether, 1, initialStake));
        }

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV2(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV2.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV2(reward);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        vm.prank(user1);
        stakingRewardsV2.getReward();

        // check rewards
        rewards = rewardEscrowV2.balanceOf(user1);
        assertEq(rewards, expectedRewards);

        for (uint256 i = 0; i < numberOfRounds; i++) {
            // add another staker
            address otherUser = createUser();
            fundAccountAndStakeV2(otherUser, getPseudoRandomNumber(10 ether, 1, initialStake));

            // move forward to the end of the rewards period
            jumpToEndOfRewardsPeriod(waitTime);

            // get new pseudorandom reward and wait time
            waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
            reward = getPseudoRandomNumber(10 ether, 1, reward);

            // calculate new rewards now
            expectedRewards += getExpectedRewardV2(reward, waitTime, user1);

            addNewRewardsToStakingRewardsV2(reward);
            vm.warp(block.timestamp + waitTime);

            // get the rewards
            vm.prank(user1);
            stakingRewardsV2.getReward();

            // check rewards
            rewards = rewardEscrowV2.balanceOf(user1);
            assertEq(rewards, expectedRewards);
        }
    }

    // function testStakingRewardsOneStakerSmallIntervals() public {
    //     // this is 7 days by default
    //     uint256 lengthOfPeriod = stakingRewardsV2.rewardsDuration();
    //     uint256 initialStake = 1 ether;

    //     // fund so totalSupply is initialStake or 1 ether
    //     // user1 earns 100% of rewards
    //     fundAccountAndStakeV2(user1, initialStake);

    //     // get initial rewards
    //     uint256 rewards = rewardEscrowV2.balanceOf(user1);
    //     // assert initial rewards are 0
    //     assertEq(rewards, 0);

    //     // send in 604800 (1 week) of rewards - (using 1 week for round numbers)
    //     uint256 newRewards = 1 weeks;
    //     vm.prank(treasury);
    //     kwenta.transfer(address(stakingRewardsV2), newRewards);
    //     vm.prank(address(supplySchedule));
    //     stakingRewardsV2.notifyRewardAmount(newRewards);

    //     // fast forward 0.5 weeks - half of one complete period
    //     vm.warp(block.timestamp + lengthOfPeriod / 2);

    //     // get the rewards
    //     vm.prank(user1);
    //     stakingRewardsV2.getReward();

    //     // general formula for rewards should be:
    //     // newRewards = reward * min(timePassed, 1 weeks) / 1 weeks
    //     // rewardPerToken = previousRewards + (newRewards * 1e18 / totalSupply)
    //     // rewardsPerTokenForUser = rewardPerToken - rewardPerTokenPaid
    //     // rewards = (balance * rewardsPerTokenForUser) / 1e18

    //     // applying this calculation to the test case:
    //     // newRewards = 1 weeks * min(0.5 weeks, 1 weeks) / 1 weeks = 0.5 weeks
    //     // rewardPerToken = 0 + (0.5 weeks * 1e18 / 1 ether) = 0.5 weeks
    //     // rewardsPerTokenForUser = 0.5 weeks - 0 = 0.5 weeks
    //     // rewards = (1 ether * 0.5 weeks) / 1e18 = 0.5 weeks
    //     uint256 expectedRewards = 1 weeks / 2;

    //     // check rewards
    //     rewards = rewardEscrowV2.balanceOf(user1);
    //     assertEq(rewards, expectedRewards);

    //     // fast forward 0.5 weeks - to the end of this period
    //     vm.warp(block.timestamp + lengthOfPeriod / 2);

    //     // get the rewards
    //     vm.prank(user1);
    //     stakingRewardsV2.getReward();

    //     // check rewards
    //     rewards = rewardEscrowV2.balanceOf(user1);
    //     // we exect to claim the other half of this weeks rewards
    //     assertEq(rewards, expectedRewards * 2);
    // }
}
