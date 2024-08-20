// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingV2Setup} from "../../utils/setup/StakingV2Setup.t.sol";
import "../../utils/Constants.t.sol";

contract StakingTestHelpers is StakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                        Reward Calculation Helpers
    //////////////////////////////////////////////////////////////*/

    // Note - this must be run before triggering notifyRewardAmount and getReward
    function getExpectedRewardV1(uint256 _reward, uint256 _waitTime, address _user)
        internal
        view
        returns (uint256)
    {
        // This defaults to 7 days
        uint256 rewardsDuration = stakingRewardsV1.rewardsDuration();
        uint256 previousRewardPerToken = stakingRewardsV1.rewardPerToken();
        uint256 rewardsPerTokenPaid = stakingRewardsV1.userRewardPerTokenPaid(_user);
        uint256 totalSupply = stakingRewardsV1.totalSupply();
        uint256 balance = stakingRewardsV1.balanceOf(_user);

        // general formula for rewards should be:
        // rewardRate = reward / rewardsDuration
        // newRewards = rewardRate * min(timePassed, rewardsDuration)
        // rewardPerToken = previousRewards + (newRewards * 1e18 / totalSupply)
        // rewardsPerTokenForUser = rewardPerToken - rewardPerTokenPaid
        // rewards = (balance * rewardsPerTokenForUser) / 1e18
        uint256 rewardRate = _reward / rewardsDuration;
        uint256 newRewards = rewardRate * min(_waitTime, rewardsDuration);
        uint256 rewardPerToken = previousRewardPerToken + (newRewards * 1e18 / totalSupply);
        uint256 rewardsPerTokenForUser = rewardPerToken - rewardsPerTokenPaid;
        uint256 expectedRewards = balance * rewardsPerTokenForUser / 1e18;

        return expectedRewards;
    }

    // Note - this must be run before triggering notifyRewardAmount and getReward
    function getExpectedRewardV2(uint256 _reward, uint256 _waitTime, address _user)
        internal
        view
        returns (uint256)
    {
        // This defaults to 7 days
        uint256 rewardsDuration = stakingRewardsV2.rewardsDuration();
        uint256 previousRewardPerToken = stakingRewardsV2.rewardPerToken();
        uint256 rewardsPerTokenPaid = stakingRewardsV2.userRewardPerTokenPaid(_user);
        uint256 totalSupply = stakingRewardsV2.totalSupply() + stakingRewardsV1.totalSupply();
        uint256 balance = stakingRewardsV2.balanceOf(_user) + stakingRewardsV1.balanceOf(_user);

        // general formula for rewards should be:
        // rewardRate = reward / rewardsDuration
        // newRewards = rewardRate * min(timePassed, rewardsDuration)
        // rewardPerToken = previousRewards + (newRewards * 1e18 / totalSupply)
        // rewardsPerTokenForUser = rewardPerToken - rewardPerTokenPaid
        // rewards = (balance * rewardsPerTokenForUser) / 1e18
        uint256 rewardRate = _reward / rewardsDuration;
        uint256 newRewards = rewardRate * min(_waitTime, rewardsDuration);
        uint256 rewardPerToken = previousRewardPerToken + (newRewards * 1e18 / totalSupply);
        uint256 rewardsPerTokenForUser = rewardPerToken - rewardsPerTokenPaid;
        uint256 expectedRewards = balance * rewardsPerTokenForUser / 1e18;

        return expectedRewards;
    }

    // Note - this must be run before triggering notifyRewardAmount and getReward
    function getExpectedUsdcRewardV2(uint256 _rewardUsdc, uint256 _waitTime, address _user)
        internal
        view
        returns (uint256)
    {
        // This defaults to 7 days
        uint256 rewardsDuration = stakingRewardsV2.rewardsDuration();
        uint256 previousRewardPerToken = stakingRewardsV2.rewardPerTokenUSDC();
        uint256 rewardsPerTokenPaid = stakingRewardsV2.userRewardPerTokenPaidUSDC(_user);
        uint256 totalSupply = stakingRewardsV2.totalSupply() + stakingRewardsV1.totalSupply();
        uint256 balance = stakingRewardsV2.balanceOf(_user) + stakingRewardsV1.balanceOf(_user);

        // general formula for rewards should be:
        // rewardRate = reward / rewardsDuration
        // newRewards = rewardRate * min(timePassed, rewardsDuration)
        // rewardPerToken = previousRewards + (newRewards * 1e18 / totalSupply)
        // rewardsPerTokenForUser = rewardPerToken - rewardPerTokenPaid
        // rewards = (balance * rewardsPerTokenForUser) / 1e18
        uint256 rewardRate = _rewardUsdc * 1e12 / rewardsDuration;
        uint256 newRewards = rewardRate * min(_waitTime, rewardsDuration);
        uint256 rewardPerToken = previousRewardPerToken + (newRewards * 1e18 / totalSupply);
        uint256 rewardsPerTokenForUser = rewardPerToken - rewardsPerTokenPaid;
        uint256 expectedRewards = balance * rewardsPerTokenForUser / (1e18 * 1e12);

        return expectedRewards;
    }

    function jumpToEndOfRewardsPeriod(uint256 _waitTime) internal {
        uint256 rewardsDuration = stakingRewardsV1.rewardsDuration();

        bool waitTimeLessThanRewardsDuration = _waitTime < rewardsDuration;
        if (waitTimeLessThanRewardsDuration) {
            vm.warp(block.timestamp + rewardsDuration - _waitTime);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            V1 Helper Functions
    //////////////////////////////////////////////////////////////*/

    function createRewardEscrowEntryV1(address _account, uint256 _amount) internal {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV1), _amount);
        vm.prank(treasury);
        rewardEscrowV1.createEscrowEntry(_account, _amount, 52 weeks);
    }

    function createRewardEscrowEntryV1(address _account, uint256 _amount, uint256 _duration)
        internal
    {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV1), _amount);
        vm.prank(treasury);
        rewardEscrowV1.createEscrowEntry(_account, _amount, _duration);
    }

    function addNewRewardsToStakingRewardsV1(uint256 _reward) internal {
        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV1), _reward);
        vm.prank(address(supplySchedule));
        stakingRewardsV1.notifyRewardAmount(_reward);
    }

    function fundAndApproveAccountV1(address _account, uint256 _amount) internal {
        vm.prank(treasury);
        kwenta.transfer(_account, _amount);
        vm.prank(_account);
        kwenta.approve(address(stakingRewardsV1), _amount);
    }

    function fundAccountAndStakeV1(address _account, uint256 _amount) internal {
        fundAndApproveAccountV1(_account, _amount);
        vm.prank(_account);
        stakingRewardsV1.stake(_amount);
    }

    function stakeFundsV1(address _account, uint256 _amount) internal {
        vm.prank(_account);
        kwenta.approve(address(stakingRewardsV1), _amount);
        vm.prank(_account);
        stakingRewardsV1.stake(_amount);
    }

    function unstakeFundsV1(address _account, uint256 _amount) internal {
        vm.prank(_account);
        stakingRewardsV1.unstake(_amount);
    }

    function exitStakingV1(address _account) internal {
        vm.prank(_account);
        stakingRewardsV1.exit();
    }

    function getStakingRewardsV1(address _account) internal {
        vm.prank(_account);
        stakingRewardsV1.getReward();
    }

    function stakeAllUnstakedEscrowV1(address _account) internal {
        uint256 amount = getNonStakedEscrowAmountV1(_account);
        vm.prank(_account);
        rewardEscrowV1.stakeEscrow(amount);
    }

    function unstakeAllUnstakedEscrowV1(address _account) internal {
        uint256 amount = stakingRewardsV1.escrowedBalanceOf(_account);
        vm.prank(_account);
        rewardEscrowV1.unstakeEscrow(amount);
    }

    function getNonStakedEscrowAmountV1(address _account) internal view returns (uint256) {
        return rewardEscrowV1.balanceOf(_account) - stakingRewardsV1.escrowedBalanceOf(_account);
    }

    function warpAndMint(uint256 _time) internal {
        vm.warp(block.timestamp + _time);
        supplySchedule.mint();
    }

    /*//////////////////////////////////////////////////////////////
                            V2 Helper Functions
    //////////////////////////////////////////////////////////////*/

    function addNewRewardsToStakingRewardsV2(uint256 _reward, uint256 _rewardUsdc) internal {
        vm.startPrank(treasury);
        kwenta.transfer(address(stakingRewardsV2), _reward);
        usdc.transfer(address(stakingRewardsV2), _rewardUsdc);
        vm.stopPrank();
        vm.prank(address(rewardsNotifier));
        stakingRewardsV2.notifyRewardAmount(_reward, _rewardUsdc);
    }

    function fundAndApproveAccountV2(address _account, uint256 _amount) internal {
        vm.prank(treasury);
        kwenta.transfer(_account, _amount);
        vm.prank(_account);
        kwenta.approve(address(stakingRewardsV2), _amount);
    }

    function fundAccountAndStakeV2(address _account, uint256 _amount) internal {
        fundAndApproveAccountV2(_account, _amount);
        vm.prank(_account);
        stakingRewardsV2.stake(_amount);
    }

    function stakeFundsV2(address _account, uint256 _amount) internal {
        vm.prank(_account);
        kwenta.approve(address(stakingRewardsV2), _amount);
        vm.prank(_account);
        stakingRewardsV2.stake(_amount);
    }

    function unstakeFundsV2(address _account, uint256 _amount) internal {
        vm.prank(_account);
        stakingRewardsV2.unstake(_amount);
    }

    function stakeEscrowedFundsV2(address _account, uint256 _amount) internal {
        if (_amount != 0) createRewardEscrowEntryV2(_account, _amount, 52 weeks);
        vm.prank(_account);
        stakingRewardsV2.stakeEscrow(_amount);
    }

    function unstakeEscrowedFundsV2(address _account, uint256 _amount) internal {
        vm.prank(_account);
        stakingRewardsV2.unstakeEscrow(_amount);
    }

    function unstakeEscrowSkipCooldownFundsV2(address _account, uint256 _amount) internal {
        vm.prank(address(rewardEscrowV2));
        stakingRewardsV2.unstakeEscrowSkipCooldown(_account, _amount);
    }

    function bulkCreateV1EscrowEntries(address _account, uint256 _amount, uint256 num) internal {
        vm.startPrank(treasury);
        kwenta.approve(address(rewardEscrowV1), _amount * num);
        for (uint256 i; i < num; i++) {
            rewardEscrowV1.createEscrowEntry(_account, _amount, 52 weeks);
        }
        vm.stopPrank();
    }

    function createRewardEscrowEntryV2(address _account, uint256 _amount) internal {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), _amount);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(_account, _amount, 52 weeks, 90);
    }

    function createRewardEscrowEntryV2(address _account, uint256 _amount, uint256 _duration)
        internal
    {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), _amount);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(_account, _amount, _duration, 90);
    }

    function createRewardEscrowEntryV2(
        address _account,
        uint256 _amount,
        uint256 _duration,
        uint8 _earlyVestingFee
    ) internal {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), _amount);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(
            _account, _amount, _duration, _earlyVestingFee
        );
    }

    function appendRewardEscrowEntryV2(address _account, uint256 _amount) internal {
        vm.prank(treasury);
        kwenta.transfer(address(rewardEscrowV2), _amount);
        vm.prank(address(stakingRewardsV2));
        rewardEscrowV2.appendVestingEntry(_account, _amount);
    }

    function getStakingRewardsV2(address _account) internal {
        vm.prank(_account);
        stakingRewardsV2.getReward();
    }

    function stakeAllUnstakedEscrowV2(address _account) internal {
        uint256 amount = stakingRewardsV2.unstakedEscrowedBalanceOf(_account);
        vm.prank(_account);
        stakingRewardsV2.stakeEscrow(amount);
    }

    function transferEscrow(address _from, address _to, uint256 _entryID) internal {
        vm.prank(_from);
        rewardEscrowV2.transferFrom(_from, _to, _entryID);
    }

    function safeTransferEscrow(address _from, address _to, uint256 _entryID) internal {
        vm.prank(_from);
        rewardEscrowV2.safeTransferFrom(_from, _to, _entryID);
    }
}
