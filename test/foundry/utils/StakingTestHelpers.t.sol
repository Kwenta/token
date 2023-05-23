// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {Migrate} from "../../../scripts/Migrate.s.sol";
import {StakingSetup} from "../utils/StakingSetup.t.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {MultipleMerkleDistributor} from
    "../../../contracts/MultipleMerkleDistributor.sol";
import {IERC20} from "../../../contracts/interfaces/IERC20.sol";
import "../utils/Constants.t.sol";

contract StakingTestHelpers is StakingSetup {
    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event RewardsDurationUpdated(uint256 newDuration);
    event UnstakingCooldownPeriodUpdated(uint256 unstakingCooldownPeriod);
    event VestingEntryTransfer(address from, address to, uint256 entryID);
    event OperatorApproved(address owner, address operator, bool approved);
    event RewardPaid(address indexed account, uint256 reward);
    event EscrowStaked(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                        Reward Calculation Helpers
    //////////////////////////////////////////////////////////////*/

    // Note - this must be run before triggering notifyRewardAmount and getReward
    function getExpectedRewardV1(uint256 reward, uint256 waitTime, address user)
        public
        view
        returns (uint256)
    {
        // This defaults to 7 days
        uint256 rewardsDuration = stakingRewardsV1.rewardsDuration();
        uint256 previousRewardPerToken = stakingRewardsV1.rewardPerToken();
        uint256 rewardsPerTokenPaid =
            stakingRewardsV1.userRewardPerTokenPaid(user);
        uint256 totalSupply = stakingRewardsV1.totalSupply();
        uint256 balance = stakingRewardsV1.balanceOf(user);

        // general formula for rewards should be:
        // rewardRate = reward / rewardsDuration
        // newRewards = rewardRate * min(timePassed, rewardsDuration)
        // rewardPerToken = previousRewards + (newRewards * 1e18 / totalSupply)
        // rewardsPerTokenForUser = rewardPerToken - rewardPerTokenPaid
        // rewards = (balance * rewardsPerTokenForUser) / 1e18
        uint256 rewardRate = reward / rewardsDuration;
        uint256 newRewards = rewardRate * min(waitTime, rewardsDuration);
        uint256 rewardPerToken =
            previousRewardPerToken + (newRewards * 1e18 / totalSupply);
        uint256 rewardsPerTokenForUser = rewardPerToken - rewardsPerTokenPaid;
        uint256 expectedRewards = balance * rewardsPerTokenForUser / 1e18;

        return expectedRewards;
    }

    // Note - this must be run before triggering notifyRewardAmount and getReward
    function getExpectedRewardV2(uint256 reward, uint256 waitTime, uint256 accountId)
        public
        view
        returns (uint256)
    {
        // This defaults to 7 days
        uint256 rewardsDuration = stakingRewardsV2.rewardsDuration();
        uint256 previousRewardPerToken = stakingRewardsV2.rewardPerToken();
        uint256 rewardsPerTokenPaid =
            stakingRewardsV2.userRewardPerTokenPaid(accountId);
        uint256 totalSupply =
            stakingRewardsV2.totalSupply() + stakingRewardsV1.totalSupply();
        uint256 balance =
            stakingRewardsV2.balanceOf(accountId) + stakingRewardsV1.balanceOf(stakingAccount.ownerOf(accountId));

        // general formula for rewards should be:
        // rewardRate = reward / rewardsDuration
        // newRewards = rewardRate * min(timePassed, rewardsDuration)
        // rewardPerToken = previousRewards + (newRewards * 1e18 / totalSupply)
        // rewardsPerTokenForUser = rewardPerToken - rewardPerTokenPaid
        // rewards = (balance * rewardsPerTokenForUser) / 1e18
        uint256 rewardRate = reward / rewardsDuration;
        uint256 newRewards = rewardRate * min(waitTime, rewardsDuration);
        uint256 rewardPerToken =
            previousRewardPerToken + (newRewards * 1e18 / totalSupply);
        uint256 rewardsPerTokenForUser = rewardPerToken - rewardsPerTokenPaid;
        uint256 expectedRewards = balance * rewardsPerTokenForUser / 1e18;

        return expectedRewards;
    }

    function jumpToEndOfRewardsPeriod(uint256 waitTime) public {
        uint256 rewardsDuration = stakingRewardsV1.rewardsDuration();

        bool waitTimeLessThanRewardsDuration = waitTime < rewardsDuration;
        if (waitTimeLessThanRewardsDuration) {
            vm.warp(block.timestamp + rewardsDuration - waitTime);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            V1 Helper Functions
    //////////////////////////////////////////////////////////////*/

    // UNIT HELPERS
    function addNewRewardsToStakingRewardsV1(uint256 reward) public {
        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV1), reward);
        vm.prank(address(supplySchedule));
        stakingRewardsV1.notifyRewardAmount(reward);
    }

    function fundAndApproveAccountV1(address account, uint256 amount) public {
        vm.prank(treasury);
        kwenta.transfer(account, amount);
        vm.prank(account);
        kwenta.approve(address(stakingRewardsV1), amount);
    }

    function fundAccountAndStakeV1(address account, uint256 amount) public {
        fundAndApproveAccountV1(account, amount);
        vm.prank(account);
        stakingRewardsV1.stake(amount);
    }

    function stakeFundsV1(address account, uint256 amount) public {
        vm.prank(account);
        kwenta.approve(address(stakingRewardsV1), amount);
        vm.prank(account);
        stakingRewardsV1.stake(amount);
    }

    function unstakeFundsV1(address account, uint256 amount) public {
        vm.prank(account);
        stakingRewardsV1.unstake(amount);
    }

    function exitStakingV1(address account) public {
        vm.prank(account);
        stakingRewardsV1.exit();
    }

    function getStakingRewardsV1(address account) public {
        vm.prank(account);
        stakingRewardsV1.getReward();
    }

    // INTEGRATION HELPERS
    function stakeAllUnstakedEscrowV1(address account) public {
        uint256 amount = getNonStakedEscrowAmountV1(account);
        vm.prank(account);
        rewardEscrowV1.stakeEscrow(amount);
    }

    function unstakeAllUnstakedEscrowV1(address account, uint256 amount)
        public
    {
        vm.prank(account);
        rewardEscrowV1.unstakeEscrow(amount);
    }

    function getNonStakedEscrowAmountV1(address account)
        public
        view
        returns (uint256)
    {
        return rewardEscrowV1.balanceOf(account)
            - stakingRewardsV1.escrowedBalanceOf(account);
    }

    function warpAndMint(uint256 time) public {
        vm.warp(block.timestamp + time);
        supplySchedule.mint();
    }

    /*//////////////////////////////////////////////////////////////
                            V2 Helper Functions
    //////////////////////////////////////////////////////////////*/

    // UNIT HELPERS
    function addNewRewardsToStakingRewardsV2(uint256 reward) public {
        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV2), reward);
        vm.prank(address(supplySchedule));
        stakingRewardsV2.notifyRewardAmount(reward);
    }

    function fundAndApproveAccountV2(address account, uint256 amount) public {
        vm.prank(treasury);
        kwenta.transfer(account, amount);
        vm.prank(account);
        kwenta.approve(address(stakingRewardsV2), amount);
    }

    function fundAccountAndStakeV2(uint256 accountId, uint256 amount) public {
        fundAndApproveAccountV2(accountOwner(accountId), amount);
        vm.prank(address(stakingAccount));
        stakingRewardsV2.stake(accountId, amount);
    }

    function stakeFundsV2(uint256 accountId, uint256 amount) public {
        vm.prank(accountOwner(accountId));
        kwenta.approve(address(stakingRewardsV2), amount);
        vm.prank(address(stakingAccount));
        stakingRewardsV2.stake(accountId, amount);
    }

    function accountOwner(uint256 accountId) public view returns (address) {
        return stakingAccount.ownerOf(accountId);
    }

    function unstakeFundsV2(uint256 accountId, uint256 amount) public {
        vm.prank(address(stakingAccount));
        stakingRewardsV2.unstake(accountId, amount);
    }

    function stakeEscrowedFundsV2(uint256 accountId, uint256 amount) public {
        if (amount != 0) createRewardEscrowEntryV2(accountId, amount, 52 weeks);
        vm.prank(address(stakingAccount));
        rewardEscrowV2.stakeEscrow(accountId, amount);
    }

    function unstakeEscrowedFundsV2(uint256 accountId, uint256 amount) public {
        vm.prank(address(rewardEscrowV2));
        stakingRewardsV2.unstakeEscrow(accountId, amount);
    }

    function createRewardEscrowEntryV2(
        uint256 accountId,
        uint256 amount,
        uint256 duration
    ) public {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), amount);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(accountId, amount, duration, 90);
    }

    function createRewardEscrowEntryV2(
        uint256 accountId,
        uint256 amount,
        uint256 duration,
        uint8 earlyVestingFee
    ) public {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), amount);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(
            accountId, amount, duration, earlyVestingFee
        );
    }

    function appendRewardEscrowEntryV2(
        uint256 accountId,
        uint256 amount,
        uint256 duration
    ) public {
        vm.prank(treasury);
        kwenta.transfer(address(rewardEscrowV2), amount);
        vm.prank(address(stakingRewardsV2));
        rewardEscrowV2.appendVestingEntry(accountId, amount, duration);
    }

    function getStakingRewardsV2(uint256 accountId) public {
        vm.prank(address(stakingRewardsV2));
        stakingRewardsV2.getReward(accountId);
    }

    // INTEGRATION HELPERS
    function stakeAllUnstakedEscrowV2(uint256 accountId) public {
        uint256 amount = getNonStakedEscrowAmountV2(accountId);
        vm.prank(address(stakingAccount));
        rewardEscrowV2.stakeEscrow(accountId, amount);
    }

    function unstakeAllUnstakedEscrowV2(uint256 accountId, uint256 amount)
        public
    {
        vm.prank(address(stakingAccount));
        rewardEscrowV2.unstakeEscrow(accountId, amount);
    }

    function getNonStakedEscrowAmountV2(uint256 accountId)
        public
        view
        returns (uint256)
    {
        return rewardEscrowV2.balanceOf(accountId)
            - stakingRewardsV2.escrowedBalanceOf(accountId);
    }
}
