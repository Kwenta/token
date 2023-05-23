// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.19;

// import "forge-std/Test.sol";
// import {StakingTestHelpers} from "../utils/StakingTestHelpers.t.sol";
// import "../utils/Constants.t.sol";

// contract StakingV2RewardMigrationCalculationTests is StakingTestHelpers {
//     /*//////////////////////////////////////////////////////////////
//                                 Setup
//     //////////////////////////////////////////////////////////////*/

//     function setUp() public virtual override {
//         // Deploy v1 and v2
//         super.setUp();

//         // fund and stake in v1
//         fundAccountAndStakeV1(user1, 1 ether);
//         fundAccountAndStakeV1(user2, 1 ether);
//         fundAccountAndStakeV1(user3, 1 ether);
//         fundAccountAndStakeV1(user4, 1 ether);
//         fundAccountAndStakeV1(user5, 1 ether);

//         // switch to staking v2
//         switchToStakingV2();
//     }

//     /*//////////////////////////////////////////////////////////////
//                     Rewards Migration Calculation Tests
//     //////////////////////////////////////////////////////////////*/
//     function test_Staking_Rewards_One_Staker() public {
//         // this is 7 days by default
//         uint256 lengthOfPeriod = stakingRewardsV2.rewardsDuration();
//         uint256 initialStake = 1 ether;

//         // fund so totalSupply is initialStake or 1 ether
//         // user1 earns 100% of rewards
//         fundAccountAndStakeV2(user1, initialStake);

//         // get initial rewards
//         uint256 rewards = rewardEscrowV2.balanceOf(user1);
//         // assert initial rewards are 0
//         assertEq(rewards, 0);

//         // send in 604800 (1 week) of rewards - (using 1 week for round numbers)
//         addNewRewardsToStakingRewardsV2(1 weeks);

//         // fast forward 1 week - one complete period
//         vm.warp(block.timestamp + lengthOfPeriod);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // general formula for rewards should be:
//         // newRewards = reward * min(timePassed, 1 weeks) / 1 weeks
//         // rewardPerToken = previousRewards + (newRewards * 1e18 / totalSupply)
//         // rewardsPerTokenForUser = rewardPerToken - rewardPerTokenPaid
//         // rewards = (balance * rewardsPerTokenForUser) / 1e18

//         // applying this calculation to the test case:
//         // newRewards = 1 weeks * min(1 weeks, 1 weeks) / 1 weeks = 1 weeks
//         // totalSupply = stakingV1 totalSuplly + stakingV2 totalSupply = 5 ether + 1 ether = 6 ether
//         // rewardPerToken = 0 + (1 weeks * 1e18 / 6 ether) = 1/6 weeks
//         // rewardsPerTokenForUser = 1/6 weeks - 0 = 1/6 weeks
//         // balance = stakingV1 balance + stakingV2 balance = 1 ether + 1 ether  = 2 ether
//         // rewards = (2 ether * 1/6 weeks) / 1e18 = 1/3 weeks
//         uint256 expectedRewards = 1 weeks / 3;

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         assertEq(rewards, expectedRewards);

//         // send in another 604800 (1 week) of rewards
//         addNewRewardsToStakingRewardsV2(1 weeks);

//         // fast forward 1 week - one complete period
//         vm.warp(block.timestamp + lengthOfPeriod);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         // we exect the same amount of rewards again as this week was exactly the same as the previous one
//         uint256 numberOfPeriods = 2;
//         assertEq(rewards, expectedRewards * numberOfPeriods);
//     }

//     function test_Staking_Rewards_One_Staker_In_Single_Reward_Period_Fuzz(uint64 _initialStake, uint64 _reward, uint24 _waitTime)
//         public
//     {
//         uint256 initialStake = uint256(_initialStake);
//         uint256 reward = uint256(_reward);
//         uint256 waitTime = uint256(_waitTime);
//         vm.assume(initialStake > 0);

//         // this is 7 days by default
//         uint256 rewardsDuration = stakingRewardsV2.rewardsDuration();

//         // fund so totalSupply is initialStake or 1 ether
//         // user1 earns 100% of rewards
//         fundAccountAndStakeV2(user1, initialStake);

//         // get initial rewards
//         uint256 rewards = rewardEscrowV2.balanceOf(user1);
//         // assert initial rewards are 0
//         assertEq(rewards, 0);

//         // calculate expected reward
//         uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);

//         // send in reward to the contract
//         addNewRewardsToStakingRewardsV2(reward);

//         // fast forward some period of time to accrue rewards
//         vm.warp(block.timestamp + waitTime);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         assertEq(rewards, expectedRewards);

//         // move forward to the end of the rewards period
//         jumpToEndOfRewardsPeriod(waitTime);

//         // calculate new rewards now
//         uint256 newReward = 0;
//         expectedRewards += getExpectedRewardV2(newReward, rewardsDuration, user1);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         assertEq(rewards, expectedRewards);
//     }

//     function test_Staking_Rewards_Multiple_Stakers_In_Single_Reward_Period_Fuzz(
//         uint64 _initialStake,
//         uint64 _reward,
//         uint24 _waitTime
//     ) public {
//         uint256 initialStake = uint256(_initialStake);
//         uint256 reward = uint256(_reward);
//         uint256 waitTime = uint256(_waitTime);
//         vm.assume(initialStake > 0);

//         // this is 7 days by default
//         uint256 rewardsDuration = stakingRewardsV2.rewardsDuration();

//         // stake with other users
//         fundAccountAndStakeV2(user2, getPseudoRandomNumber(10 ether, 1, initialStake));
//         fundAccountAndStakeV2(user3, getPseudoRandomNumber(10 ether, 1, initialStake));
//         fundAccountAndStakeV2(user4, getPseudoRandomNumber(10 ether, 1, initialStake));
//         fundAccountAndStakeV2(user5, getPseudoRandomNumber(10 ether, 1, initialStake));

//         // fund so totalSupply is initialStake or 1 ether
//         // user1 earns 100% of rewards
//         fundAccountAndStakeV2(user1, initialStake);

//         // get initial rewards
//         uint256 rewards = rewardEscrowV2.balanceOf(user1);
//         // assert initial rewards are 0
//         assertEq(rewards, 0);

//         // calculate expected reward
//         uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);

//         // send in reward to the contract
//         addNewRewardsToStakingRewardsV2(reward);

//         // fast forward some period of time to accrue rewards
//         vm.warp(block.timestamp + waitTime);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         assertEq(rewards, expectedRewards);

//         // move forward to the end of the rewards period
//         jumpToEndOfRewardsPeriod(waitTime);

//         // calculate new rewards now
//         uint256 newReward = 0;
//         expectedRewards += getExpectedRewardV2(newReward, rewardsDuration, user1);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         assertEq(rewards, expectedRewards);
//     }

//     function test_Staking_Rewards_One_Staker_Two_Reward_Periods_Fuzz(uint64 _initialStake, uint64 _reward, uint24 _waitTime)
//         public
//     {
//         uint256 initialStake = uint256(_initialStake);
//         uint256 reward = uint256(_reward);
//         uint256 waitTime = uint256(_waitTime);
//         vm.assume(initialStake > 0);

//         // fund so totalSupply is initialStake or 1 ether
//         // user1 earns 100% of rewards
//         fundAccountAndStakeV2(user1, initialStake);

//         // get initial rewards
//         uint256 rewards = rewardEscrowV2.balanceOf(user1);
//         // assert initial rewards are 0
//         assertEq(rewards, 0);

//         // calculate expected reward
//         uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);

//         // send in reward to the contract
//         addNewRewardsToStakingRewardsV2(reward);

//         // fast forward some period of time to accrue rewards
//         vm.warp(block.timestamp + waitTime);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         assertEq(rewards, expectedRewards);

//         // move forward to the end of the rewards period
//         jumpToEndOfRewardsPeriod(waitTime);

//         // get new pseudorandom reward and wait time
//         uint256 newWaitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
//         uint256 newReward = getPseudoRandomNumber(10 ether, 1, reward);

//         // calculate new rewards now
//         expectedRewards += getExpectedRewardV2(newReward, newWaitTime, user1);

//         addNewRewardsToStakingRewardsV2(newReward);
//         vm.warp(block.timestamp + newWaitTime);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         assertEq(rewards, expectedRewards);
//     }

//     function test_Staking_Rewards_Three_Rounds_Fuzz(uint64 _initialStake, uint64 _reward, uint24 _waitTime) public {
//         uint256 initialStake = uint256(_initialStake);
//         uint256 reward = uint256(_reward);
//         uint256 waitTime = uint256(_waitTime);
//         vm.assume(initialStake > 0);

//         // fund so totalSupply is initialStake or 1 ether
//         // user1 earns 100% of rewards
//         fundAccountAndStakeV2(user1, initialStake);

//         // get initial rewards
//         uint256 rewards = rewardEscrowV2.balanceOf(user1);
//         // assert initial rewards are 0
//         assertEq(rewards, 0);

//         // calculate expected reward
//         uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);

//         // send in reward to the contract
//         addNewRewardsToStakingRewardsV2(reward);

//         // fast forward some period of time to accrue rewards
//         vm.warp(block.timestamp + waitTime);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         assertEq(rewards, expectedRewards);

//         // move forward to the end of the rewards period
//         jumpToEndOfRewardsPeriod(waitTime);

//         // get new pseudorandom reward and wait time
//         waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
//         reward = getPseudoRandomNumber(10 ether, 1, reward);

//         // calculate new rewards now
//         expectedRewards += getExpectedRewardV2(reward, waitTime, user1);

//         addNewRewardsToStakingRewardsV2(reward);
//         vm.warp(block.timestamp + waitTime);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         assertEq(rewards, expectedRewards);

//         // move forward to the end of the rewards period
//         jumpToEndOfRewardsPeriod(waitTime);

//         // get new pseudorandom reward and wait time
//         waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
//         reward = getPseudoRandomNumber(10 ether, 1, reward);

//         // calculate new rewards now
//         expectedRewards += getExpectedRewardV2(reward, waitTime, user1);

//         addNewRewardsToStakingRewardsV2(reward);
//         vm.warp(block.timestamp + waitTime);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         assertEq(rewards, expectedRewards);
//     }

//     function test_Staking_Rewards_Multiple_Rounds_Fuzz(
//         uint64 _initialStake,
//         uint64 _reward,
//         uint24 _waitTime,
//         uint8 numberOfRounds
//     ) public {
//         uint256 initialStake = uint256(_initialStake);
//         uint256 reward = uint256(_reward);
//         uint256 waitTime = uint256(_waitTime);
//         vm.assume(initialStake > 0);
//         vm.assume(numberOfRounds < 100);

//         // fund so totalSupply is initialStake or 1 ether
//         // user1 earns 100% of rewards
//         fundAccountAndStakeV2(user1, initialStake);

//         // get initial rewards
//         uint256 rewards = rewardEscrowV2.balanceOf(user1);
//         // assert initial rewards are 0
//         assertEq(rewards, 0);

//         // calculate expected reward
//         uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);

//         // send in reward to the contract
//         addNewRewardsToStakingRewardsV2(reward);

//         // fast forward some period of time to accrue rewards
//         vm.warp(block.timestamp + waitTime);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         assertEq(rewards, expectedRewards);

//         for (uint256 i = 0; i < numberOfRounds; i++) {
//             // move forward to the end of the rewards period
//             jumpToEndOfRewardsPeriod(waitTime);

//             // get new pseudorandom reward and wait time
//             waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
//             reward = getPseudoRandomNumber(10 ether, 1, reward);

//             // calculate new rewards now
//             expectedRewards += getExpectedRewardV2(reward, waitTime, user1);

//             addNewRewardsToStakingRewardsV2(reward);
//             vm.warp(block.timestamp + waitTime);

//             // get the rewards
//             getStakingRewardsV2(user1);

//             // check rewards
//             rewards = rewardEscrowV2.balanceOf(user1);
//             assertEq(rewards, expectedRewards);
//         }
//     }

//     function test_Staking_Rewards_Multiple_Rounds_And_Stakers_Fuzz(
//         uint64 _initialStake,
//         uint64 _reward,
//         uint24 _waitTime,
//         uint8 numberOfRounds,
//         uint8 initialNumberOfStakers
//     ) public {
//         uint256 initialStake = uint256(_initialStake);
//         uint256 reward = uint256(_reward);
//         uint256 waitTime = uint256(_waitTime);
//         vm.assume(initialStake > 0);
//         vm.assume(numberOfRounds < 50);
//         vm.assume(initialNumberOfStakers < 50);

//         // other user
//         for (uint256 i = 0; i < initialNumberOfStakers; i++) {
//             address otherUser = createUser();
//             fundAccountAndStakeV2(otherUser, getPseudoRandomNumber(10 ether, 1, initialStake));
//         }

//         // fund so totalSupply is initialStake or 1 ether
//         // user1 earns 100% of rewards
//         fundAccountAndStakeV2(user1, initialStake);

//         // get initial rewards
//         uint256 rewards = rewardEscrowV2.balanceOf(user1);
//         // assert initial rewards are 0
//         assertEq(rewards, 0);

//         // calculate expected reward
//         uint256 expectedRewards = getExpectedRewardV2(reward, waitTime, user1);

//         // send in reward to the contract
//         addNewRewardsToStakingRewardsV2(reward);

//         // fast forward some period of time to accrue rewards
//         vm.warp(block.timestamp + waitTime);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         assertEq(rewards, expectedRewards);

//         for (uint256 i = 0; i < numberOfRounds; i++) {
//             // add another staker
//             address otherUser = createUser();
//             if (flipCoin()) {
//                 fundAccountAndStakeV1(otherUser, getPseudoRandomNumber(10 ether, 1, initialStake));
//             } else {
//                 fundAccountAndStakeV2(otherUser, getPseudoRandomNumber(10 ether, 1, initialStake));
//             }

//             // move forward to the end of the rewards period
//             jumpToEndOfRewardsPeriod(waitTime);

//             // get new pseudorandom reward and wait time
//             waitTime = getPseudoRandomNumber(10 weeks, 0, waitTime);
//             reward = getPseudoRandomNumber(10 ether, 1, reward);

//             // calculate new rewards now
//             expectedRewards += getExpectedRewardV2(reward, waitTime, user1);

//             addNewRewardsToStakingRewardsV2(reward);
//             vm.warp(block.timestamp + waitTime);

//             // get the rewards
//             getStakingRewardsV2(user1);

//             // check rewards
//             rewards = rewardEscrowV2.balanceOf(user1);
//             assertEq(rewards, expectedRewards);
//         }
//     }

//     function test_Staking_Rewards_One_Staker_Small_Intervals() public {
//         // this is 7 days by default
//         uint256 lengthOfPeriod = stakingRewardsV2.rewardsDuration();
//         uint256 initialStake = 1 ether;

//         // fund so totalSupply is initialStake or 1 ether
//         // user1 earns 100% of rewards
//         fundAccountAndStakeV2(user1, initialStake);

//         // get initial rewards
//         uint256 rewards = rewardEscrowV2.balanceOf(user1);
//         // assert initial rewards are 0
//         assertEq(rewards, 0);

//         // send in 604800 (1 week) of rewards - (using 1 week for round numbers)
//         addNewRewardsToStakingRewardsV2(1 weeks);

//         // fast forward 0.5 weeks - half of one complete period
//         vm.warp(block.timestamp + lengthOfPeriod / 2);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // general formula for rewards should be:
//         // newRewards = reward * min(timePassed, 1 weeks) / 1 weeks
//         // rewardPerToken = previousRewards + (newRewards * 1e18 / totalSupply)
//         // rewardsPerTokenForUser = rewardPerToken - rewardPerTokenPaid
//         // rewards = (balance * rewardsPerTokenForUser) / 1e18

//         // applying this calculation to the test case:
//         // newRewards = 1 weeks * min(0.5 weeks, 1 weeks) / 1 weeks = 0.5 weeks
//         // rewardPerToken = 0 + (0.5 weeks * 1e18 / 6 ether) = 1/12 weeks
//         // rewardsPerTokenForUser = 1/12 weeks - 0 = 1/12 weeks
//         // rewards = (2 ether * 1/12 weeks) / 1e18 = 1/6 weeks
//         uint256 expectedRewards = 1 weeks / 6;

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         assertEq(rewards, expectedRewards);

//         // fast forward 0.5 weeks - to the end of this period
//         vm.warp(block.timestamp + lengthOfPeriod / 2);

//         // get the rewards
//         getStakingRewardsV2(user1);

//         // check rewards
//         rewards = rewardEscrowV2.balanceOf(user1);
//         // we exect to claim the other half of this weeks rewards
//         assertEq(rewards, expectedRewards * 2);
//     }
// }
