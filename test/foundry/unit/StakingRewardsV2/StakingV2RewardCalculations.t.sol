// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import "../../utils/Constants.t.sol";

contract StakingV2RewardCalculationTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                Staking Rewards V2 Calculation Tests
    //////////////////////////////////////////////////////////////*/

    function test_Staking_Rewards_One_Staker() public {
        // this is 7 days by default
        uint256 lengthOfPeriod = stakingRewardsV2.rewardsDuration();
        uint256 initialStake = 1 ether;

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV2(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        uint256 rewardsUsdc = usdc.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);
        assertEq(rewardsUsdc, 0);

        // send in 604800 (1 week) of rewards - (using 1 week for round numbers)
        addNewRewardsToStakingRewardsV2(1 weeks, 1 weeks);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + lengthOfPeriod);

        // get the rewards
        getStakingRewardsV2(user1);

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
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        assertEq(rewards, expectedRewards);
        assertEq(rewardsUsdc, expectedRewards);

        // send in another 604800 (1 week) of rewards
        addNewRewardsToStakingRewardsV2(1 weeks, 1 weeks);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + lengthOfPeriod);

        // get the rewards
        getStakingRewardsV2(user1);

        // check rewards
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        // we exect the same amount of rewards again as this week was exactly the same as the previous one
        uint256 numberOfPeriods = 2;
        assertEq(rewards, expectedRewards * numberOfPeriods);
        assertEq(rewardsUsdc, expectedRewards * numberOfPeriods);
    }

    function test_Staking_Rewards_One_Staker_In_Single_Reward_Period_Fuzz(
        uint64 _initialStake,
        uint64 _reward,
        uint64 _rewardUsdc,
        uint24 _waitTime
    ) public {
        uint256 initialStake = uint256(_initialStake);
        uint256 reward = uint256(_reward);
        uint256 rewardUsdc = uint256(_rewardUsdc);
        uint256 waitTime = uint256(_waitTime);
        vm.assume(initialStake > 0);

        // this is 7 days by default
        uint256 rewardsDuration = stakingRewardsV2.rewardsDuration();

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV2(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        uint256 rewardsUsdc = usdc.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);
        assertEq(rewardsUsdc, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);
        uint256 expectedUsdcRewards = getExpectedUsdcRewardV2(rewardUsdc, waitTime, user1);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV2(reward, rewardUsdc);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        getStakingRewardsV2(user1);

        // check rewards
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        assertEq(rewards, expectedRewards);
        assertEq(rewardsUsdc, expectedUsdcRewards);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // calculate new rewards now
        uint256 newReward = 0;
        expectedRewards += getExpectedRewardV2(newReward, rewardsDuration, user1);
        expectedUsdcRewards += getExpectedUsdcRewardV2(newReward, rewardsDuration, user1);

        // get the rewards
        getStakingRewardsV2(user1);

        // check rewards
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        assertEq(rewards, expectedRewards);
        assertEq(rewardsUsdc, expectedUsdcRewards);
    }

    function test_Staking_Rewards_Multiple_Stakers_In_Single_Reward_Period_Fuzz(
        uint64 _initialStake,
        uint64 _reward,
        uint64 _rewardUsdc,
        uint24 _waitTime
    ) public {
        uint256 initialStake = uint256(_initialStake);
        uint256 reward = uint256(_reward);
        uint256 rewardUsdc = uint256(_rewardUsdc);
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
        uint256 rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        uint256 rewardsUsdc = usdc.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);
        assertEq(rewardsUsdc, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);
        uint256 expectedUsdcRewards = getExpectedUsdcRewardV2(rewardUsdc, waitTime, user1);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV2(reward, rewardUsdc);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        getStakingRewardsV2(user1);

        // check rewards
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        assertEq(rewards, expectedRewards);
        // assertEq(rewardsUsdc, expectedUsdcRewards);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // calculate new rewards now
        uint256 newReward = 0;
        expectedRewards += getExpectedRewardV2(newReward, rewardsDuration, user1);
        expectedUsdcRewards += getExpectedUsdcRewardV2(newReward, rewardsDuration, user1);

        // get the rewards
        getStakingRewardsV2(user1);
        getStakingRewardsV2(user2);
        getStakingRewardsV2(user3);
        getStakingRewardsV2(user4);
        getStakingRewardsV2(user5);

        // check rewards
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        assertEq(rewards, expectedRewards);
        assertApproxEqAbs(rewardsUsdc, expectedUsdcRewards, 10);
    }

    function test_Staking_Rewards_One_Staker_Two_Reward_Periods_Fuzz(
        uint64 _initialStake,
        uint64 _reward,
        uint64 _rewardUsdc,
        uint24 _waitTime
    ) public {
        uint256 initialStake = uint256(_initialStake);
        uint256 reward = uint256(_reward);
        uint256 rewardUsdc = uint256(_rewardUsdc);
        uint256 waitTime = uint256(_waitTime);
        vm.assume(initialStake > 0);

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV2(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        uint256 rewardsUsdc = usdc.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);
        assertEq(rewardsUsdc, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);
        uint256 expectedUsdcRewards = getExpectedUsdcRewardV2(rewardUsdc, waitTime, user1);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV2(reward, rewardUsdc);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        getStakingRewardsV2(user1);

        // check rewards
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        assertEq(rewards, expectedRewards);
        assertEq(rewardsUsdc, expectedUsdcRewards);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // get new pseudorandom reward and wait time
        uint256 newWaitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
        uint256 newReward = getPseudoRandomNumber(10 ether, 1, reward);
        uint256 newRewardUsdc = getPseudoRandomNumber(10 ether, 1, rewardUsdc);

        // calculate new rewards now
        expectedRewards += getExpectedRewardV2(newReward, newWaitTime, user1);
        expectedUsdcRewards += getExpectedUsdcRewardV2(newRewardUsdc, newWaitTime, user1);

        addNewRewardsToStakingRewardsV2(newReward, newRewardUsdc);
        vm.warp(block.timestamp + newWaitTime);

        // get the rewards
        getStakingRewardsV2(user1);

        // check rewards
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        assertEq(rewards, expectedRewards);
        assertApproxEqAbs(rewardsUsdc, expectedUsdcRewards, 10);
    }

    function test_Staking_Rewards_Three_Rounds_Fuzz(
        uint64 _initialStake,
        uint64 _reward,
        uint64 _rewardUsdc,
        uint24 _waitTime
    ) public {
        uint256 initialStake = uint256(_initialStake);
        uint256 reward = uint256(_reward);
        uint256 rewardUsdc = uint256(_rewardUsdc);
        uint256 waitTime = uint256(_waitTime);
        vm.assume(initialStake > 0);

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV2(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        uint256 rewardsUsdc = usdc.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);
        assertEq(rewardsUsdc, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);
        uint256 expectedUsdcRewards = getExpectedUsdcRewardV2(rewardUsdc, waitTime, user1);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV2(reward, rewardUsdc);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        getStakingRewardsV2(user1);

        // check rewards
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        assertEq(rewards, expectedRewards);
        assertEq(rewardsUsdc, expectedUsdcRewards);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // get new pseudorandom reward and wait time
        waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
        reward = getPseudoRandomNumber(10 ether, 1, reward);
        rewardUsdc = getPseudoRandomNumber(10 ether, 1, rewardUsdc);

        // calculate new rewards now
        expectedRewards += getExpectedRewardV2(reward, waitTime, user1);
        expectedUsdcRewards += getExpectedUsdcRewardV2(rewardUsdc, waitTime, user1);

        addNewRewardsToStakingRewardsV2(reward, rewardUsdc);
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        getStakingRewardsV2(user1);

        // check rewards
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        assertEq(rewards, expectedRewards);
        assertApproxEqAbs(rewardsUsdc, expectedUsdcRewards, 10);

        // move forward to the end of the rewards period
        jumpToEndOfRewardsPeriod(waitTime);

        // get new pseudorandom reward and wait time
        waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
        reward = getPseudoRandomNumber(10 ether, 1, reward);
        rewardUsdc = getPseudoRandomNumber(10 ether, 1, rewardUsdc);

        // calculate new rewards now
        expectedRewards += getExpectedRewardV2(reward, waitTime, user1);
        expectedUsdcRewards += getExpectedUsdcRewardV2(rewardUsdc, waitTime, user1);

        addNewRewardsToStakingRewardsV2(reward, rewardUsdc);
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        getStakingRewardsV2(user1);

        // check rewards
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        assertEq(rewards, expectedRewards);
        assertApproxEqAbs(rewardsUsdc, expectedUsdcRewards, 10);
    }

    function test_Staking_Rewards_Multiple_Rounds_Fuzz(
        uint64 _initialStake,
        uint64 _reward,
        uint64 _rewardUsdc,
        uint24 _waitTime,
        uint8 numberOfRounds
    ) public {
        uint256 initialStake = uint256(_initialStake);
        uint256 reward = uint256(_reward);
        uint256 rewardUsdc = uint256(_rewardUsdc);
        uint256 waitTime = uint256(_waitTime);
        vm.assume(initialStake > 0);
        vm.assume(numberOfRounds < 100);

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV2(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        uint256 rewardsUsdc = usdc.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);
        assertEq(rewardsUsdc, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);
        uint256 expectedUsdcRewards = getExpectedUsdcRewardV2(rewardUsdc, waitTime, user1);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV2(reward, rewardUsdc);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        getStakingRewardsV2(user1);

        // check rewards
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        assertEq(rewards, expectedRewards);
        assertEq(rewardsUsdc, expectedUsdcRewards);

        for (uint256 i = 0; i < numberOfRounds; i++) {
            // move forward to the end of the rewards period
            jumpToEndOfRewardsPeriod(waitTime);

            // get new pseudorandom reward and wait time
            waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
            reward = getPseudoRandomNumber(10 ether, 1, reward);
            rewardUsdc = getPseudoRandomNumber(10 ether, 1, rewardUsdc);

            // calculate new rewards now
            expectedRewards += getExpectedRewardV2(reward, waitTime, user1);
            expectedUsdcRewards += getExpectedUsdcRewardV2(rewardUsdc, waitTime, user1);

            addNewRewardsToStakingRewardsV2(reward, rewardUsdc);
            vm.warp(block.timestamp + waitTime);

            // get the rewards
            getStakingRewardsV2(user1);

            // check rewards
            rewards = rewardEscrowV2.escrowedBalanceOf(user1);
            rewardsUsdc = usdc.balanceOf(user1);
            assertEq(rewards, expectedRewards);
            assertApproxEqAbs(rewardsUsdc, expectedUsdcRewards, 10);
        }
    }

    function test_Staking_Rewards_Multiple_Rounds_And_Stakers_Fuzz(
        uint64 _initialStake,
        uint64 _reward,
        uint64 _rewardUsdc,
        uint24 _waitTime,
        uint8 numberOfRounds,
        uint8 initialNumberOfStakers
    ) public {
        uint256 initialStake = uint256(_initialStake);
        uint256 reward = uint256(_reward);
        uint256 rewardUsdc = uint256(_rewardUsdc);
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
        uint256 rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        uint256 rewardsUsdc = usdc.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);
        assertEq(rewardsUsdc, 0);

        // calculate expected reward
        uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);
        uint256 expectedUsdcRewards = getExpectedUsdcRewardV2(rewardUsdc, waitTime, user1);

        // send in reward to the contract
        addNewRewardsToStakingRewardsV2(reward, rewardUsdc);

        // fast forward some period of time to accrue rewards
        vm.warp(block.timestamp + waitTime);

        // get the rewards
        getStakingRewardsV2(user1);

        // check rewards
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        assertEq(rewards, expectedRewards);
        assertEq(rewardsUsdc, expectedUsdcRewards);

        for (uint256 i = 0; i < numberOfRounds; i++) {
            // add another staker
            address otherUser = createUser();
            fundAccountAndStakeV2(otherUser, getPseudoRandomNumber(10 ether, 1, initialStake));

            // move forward to the end of the rewards period
            jumpToEndOfRewardsPeriod(waitTime);

            // get new pseudorandom reward and wait time
            waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
            reward = getPseudoRandomNumber(10 ether, 1, reward);
            rewardUsdc = getPseudoRandomNumber(10 ether, 1, rewardUsdc);

            // calculate new rewards now
            expectedRewards += getExpectedRewardV2(reward, waitTime, user1);
            expectedUsdcRewards += getExpectedUsdcRewardV2(rewardUsdc, waitTime, user1);

            addNewRewardsToStakingRewardsV2(reward, rewardUsdc);
            vm.warp(block.timestamp + waitTime);

            // get the rewards
            getStakingRewardsV2(user1);

            // check rewards
            rewards = rewardEscrowV2.escrowedBalanceOf(user1);
            rewardsUsdc = usdc.balanceOf(user1);
            assertEq(rewards, expectedRewards);
            assertApproxEqAbs(rewardsUsdc, expectedUsdcRewards, 10);
        }
    }

    function test_Staking_Rewards_One_Staker_Small_Intervals() public {
        // this is 7 days by default
        uint256 lengthOfPeriod = stakingRewardsV2.rewardsDuration();
        uint256 initialStake = 1 ether;

        // fund so totalSupply is initialStake or 1 ether
        // user1 earns 100% of rewards
        fundAccountAndStakeV2(user1, initialStake);

        // get initial rewards
        uint256 rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        uint256 rewardsUsdc = usdc.balanceOf(user1);
        // assert initial rewards are 0
        assertEq(rewards, 0);
        assertEq(rewardsUsdc, 0);

        // send in 604800 (1 week) of rewards - (using 1 week for round numbers)
        addNewRewardsToStakingRewardsV2(1 weeks, 1 weeks);

        // fast forward 0.5 weeks - half of one complete period
        vm.warp(block.timestamp + lengthOfPeriod / 2);

        // get the rewards
        getStakingRewardsV2(user1);

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
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        assertEq(rewards, expectedRewards);
        assertEq(rewardsUsdc, expectedRewards);

        // fast forward 0.5 weeks - to the end of this period
        vm.warp(block.timestamp + lengthOfPeriod / 2);

        // get the rewards
        getStakingRewardsV2(user1);

        // check rewards
        rewards = rewardEscrowV2.escrowedBalanceOf(user1);
        rewardsUsdc = usdc.balanceOf(user1);
        // we exect to claim the other half of this weeks rewards
        assertEq(rewards, expectedRewards * 2);
        assertEq(rewardsUsdc, expectedRewards * 2);
    }
}
