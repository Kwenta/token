// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {IStakingRewardsV2} from "../../../../contracts/interfaces/IStakingRewardsV2.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {IERC20} from "../../../../contracts/interfaces/IERC20.sol";
import "../../utils/Constants.t.sol";

contract Bug is DefaultStakingV2Setup {
    function setUp() public override {
        super.setUp();

        // addNewFundsToV2();
    }

    function test_Expected() public {
        fundAccountAndStakeV2(user1, 10 ether);

        vm.warp(block.timestamp + 2 weeks);

        vm.prank(user1);
        stakingRewardsV2.unstake(10 ether);
        
        uint reward = stakingRewardsV2.rewards(user1);
        assert(reward == 0);
    }

    function test_Actual_Bug() public {
        fundAccountAndStakeV1(user1, 10 ether);

        vm.warp(block.timestamp + 2 weeks);

        addNewFundsToV2();
        vm.warp(block.timestamp + 1 weeks);

        vm.prank(user1);
        stakingRewardsV1.unstake(10 ether);

        vm.prank(user1);
        kwenta.approve(address(stakingRewardsV2), 10 ether);
        vm.prank(user1);
        stakingRewardsV2.stake(10 ether);

        uint reward = stakingRewardsV2.earned(user1);
        assert(reward > 0);
    }

    function test_Actual_Solution_One() public {
        fundAccountAndStakeV1(user1, 10 ether);

        addNewFundsToV1();
        vm.warp(block.timestamp + 2 weeks);

        addNewFundsToV2();
        vm.warp(block.timestamp + 2 weeks);
        console.log("-----------here-----------", block.timestamp);

        uint256 earned = stakingRewardsV1.earned(user1);
        // console.log("earned", earned);

        uint256 escrowedBalanceBefore = rewardEscrowV2.escrowedBalanceOf(user1);
        // console.log("escrowedBalanceBefore", escrowedBalanceBefore);

        uint256 v1escrowedBalanceBefore = rewardEscrowV1.balanceOf(user1);
        // console.log("v1escrowedBalanceBefore", v1escrowedBalanceBefore);


        // vm.prank(user1);
        // stakingRewardsV2.getReward();

        // vm.prank(user1);
        // stakingRewardsV1.getReward();

        vm.prank(user1);
        stakingRewardsV1.unstake(10 ether);

        // vm.prank(user1);
        // kwenta.approve(address(stakingRewardsV1), 10 ether);
        // vm.prank(user1);
        // stakingRewardsV1.stake(10 ether);

        vm.prank(user1);
        kwenta.approve(address(stakingRewardsV2), 10 ether);
        vm.prank(user1);
        console.log("------------------------------ about to stake --------------------");
        stakingRewardsV2.stake(10 ether);



        uint256 v1Rewards = stakingRewardsV1.rewards(user1);

        uint256 v1escrowedBalanceAfter = rewardEscrowV1.balanceOf(user1);
        // console.log("v1escrowedBalanceAfter", v1escrowedBalanceAfter);

        uint256 escrowedBalanceAfter = rewardEscrowV2.escrowedBalanceOf(user1);
        // console.log("escrowedBalanceAfter", escrowedBalanceAfter);


        uint reward = stakingRewardsV2.earned(user1);
        console.log("reward", reward);
        console.log("block.timestamp", block.timestamp);
        assert(reward > 0);
    }

    function test_Actual_Solution_Two() public {
        fundAccountAndStakeV1(user1, 10 ether);
        fundAccountAndStakeV1(user2, 10 ether);
        fundAccountAndStakeV1(user3, 10 ether);
        fundAccountAndStakeV1(user4, 10 ether);

        addNewFundsToV1();
        vm.warp(block.timestamp + 2 weeks);

        addNewFundsToV2();
        vm.warp(block.timestamp + 2 weeks);

        uint256 earned = stakingRewardsV1.earned(user1);
        // console.log("earned", earned);

        uint256 escrowedBalanceBefore = rewardEscrowV2.escrowedBalanceOf(user1);
        // console.log("escrowedBalanceBefore", escrowedBalanceBefore);

        uint256 v1escrowedBalanceBefore = rewardEscrowV1.balanceOf(user1);
        // console.log("v1escrowedBalanceBefore", v1escrowedBalanceBefore);



        // vm.prank(user1);
        // stakingRewardsV2.getReward();

        // vm.prank(user1);
        // stakingRewardsV1.getReward();

        vm.prank(user1);
        stakingRewardsV1.unstake(10 ether);

        // vm.prank(user1);
        // kwenta.approve(address(stakingRewardsV1), 10 ether);
        // vm.prank(user1);
        // stakingRewardsV1.stake(10 ether);

        vm.prank(user1);
        kwenta.approve(address(stakingRewardsV2), 10 ether);
        vm.prank(user1);
        console.log("------------------------------ about to stake --------------------");
        stakingRewardsV2.stake(10 ether);



        uint256 v1Rewards = stakingRewardsV1.rewards(user1);

        uint256 v1escrowedBalanceAfter = rewardEscrowV1.balanceOf(user1);
        // console.log("v1escrowedBalanceAfter", v1escrowedBalanceAfter);

        uint256 escrowedBalanceAfter = rewardEscrowV2.escrowedBalanceOf(user1);
        // console.log("escrowedBalanceAfter", escrowedBalanceAfter);


        uint reward = stakingRewardsV2.earned(user1);
        console.log("reward", reward);
        console.log("block.timestamp", block.timestamp);
        assert(reward > 0);
    }

    function addNewFundsToV2() internal {
        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV2), INITIAL_SUPPLY / 4);

        address sc = address(stakingRewardsV2.supplySchedule());
        vm.prank(sc);
        stakingRewardsV2.notifyRewardAmount(TEST_VALUE);
    }

    function addNewFundsToV1() internal {
        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV1), INITIAL_SUPPLY / 4);

        address sc = address(stakingRewardsV2.supplySchedule());
        vm.prank(sc);
        stakingRewardsV1.notifyRewardAmount(TEST_VALUE);
    }
}

// things that are updated on unstaking v1
// rewardPerTokenStored
// lastUpdateTime
// rewards[account]
// userRewardPerTokenPaid[account]
// _totalSuppply
// balances[msg.sender]
// token.safeTransfer()

// things are updated on staking v1
// rewardPerTokenStored
// lastUpdateTime
// rewards[account]
// userRewardPerTokenPaid[account]
// _totalSuppply
// balances[msg.sender]
// token.safeTransfer()

// thing that are updated on staking v2
// rewardPerTokenStored
// lastUpdateTime
// rewards[account]
// userRewardPerTokenPaid[account]
// userLastStakeTime[msg.sender]
// _addTotalSupplyCheckpoint
// _addBalancesCheckpoint