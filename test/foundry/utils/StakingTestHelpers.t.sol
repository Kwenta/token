// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {TestHelpers} from "../utils/TestHelpers.t.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {MultipleMerkleDistributor} from "../../../contracts/MultipleMerkleDistributor.sol";
import {IERC20} from "../../../contracts/interfaces/IERC20.sol";
import "../utils/Constants.t.sol";

contract StakingTestHelpers is TestHelpers {
    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event RewardsDurationUpdated(uint256 newDuration);
    event UnstakingCooldownPeriodUpdated(uint256 unstakingCooldownPeriod);
    event VestingEntryTransfer(address from, address to, uint256 entryID);

    /*//////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    address public treasury;
    address public user1;
    address public user2;
    address public user3;
    address public user4;
    address public user5;
    IERC20 public mockToken;
    Kwenta public kwenta;
    RewardEscrow public rewardEscrowV1;
    RewardEscrowV2 public rewardEscrowV2;
    SupplySchedule public supplySchedule;
    StakingRewards public stakingRewardsV1;
    StakingRewardsV2 public stakingRewardsV2;
    MultipleMerkleDistributor public tradingRewards;

    /*//////////////////////////////////////////////////////////////
                                Setup
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        // Setup StakingV1
        treasury = createUser();
        user1 = createUser();
        user2 = createUser();
        user3 = createUser();
        user4 = createUser();
        user5 = createUser();
        mockToken = new Kwenta(
            "Mock",
            "MOCK",
            INITIAL_SUPPLY,
            address(this),
            treasury
        );
        kwenta = new Kwenta(
            "Kwenta",
            "KWENTA",
            INITIAL_SUPPLY,
            address(this),
            treasury
        );
        rewardEscrowV1 = new RewardEscrow(address(this), address(kwenta));
        supplySchedule = new SupplySchedule(address(this), treasury);
        supplySchedule.setKwenta(kwenta);
        kwenta.setSupplySchedule(address(supplySchedule));
        stakingRewardsV1 = new StakingRewards(
            address(kwenta),
            address(rewardEscrowV1),
            address(supplySchedule)
        );
        tradingRewards = new MultipleMerkleDistributor(address(this), address(kwenta));
        supplySchedule.setStakingRewards(address(stakingRewardsV1));
        supplySchedule.setTradingRewards(address(tradingRewards));
        rewardEscrowV1.setStakingRewards(address(stakingRewardsV1));

        // Deploy StakingV2
        rewardEscrowV2 = new RewardEscrowV2(address(this), address(kwenta));
        stakingRewardsV2 = new StakingRewardsV2(
            address(kwenta),
            address(rewardEscrowV2),
            address(supplySchedule),
            address(stakingRewardsV1)
        );
        rewardEscrowV2.setTreasuryDAO(treasury);
    }

    /*//////////////////////////////////////////////////////////////
                            Migration Helpers
    //////////////////////////////////////////////////////////////*/

    function pauseAndSwitchToStakingRewardsV2() public {
        // Pause StakingV1
        stakingRewardsV1.pauseStakingRewards();

        // Update SupplySchedule to point to StakingV2
        supplySchedule.setStakingRewards(address(stakingRewardsV2));
        // TODO: move out of here and into setup => adjust all pauseAndSwitchToStakingRewardsV2 equivalently
        rewardEscrowV2.setStakingRewardsV2(address(stakingRewardsV2));

        // Unpause StakingV1
        stakingRewardsV1.unpauseStakingRewards();
    }

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
        uint256 rewardsPerTokenPaid = stakingRewardsV1.userRewardPerTokenPaid(user);
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
        uint256 rewardPerToken = previousRewardPerToken + (newRewards * 1e18 / totalSupply);
        uint256 rewardsPerTokenForUser = rewardPerToken - rewardsPerTokenPaid;
        uint256 expectedRewards = balance * rewardsPerTokenForUser / 1e18;

        return expectedRewards;
    }

    // Note - this must be run before triggering notifyRewardAmount and getReward
    function getExpectedRewardV2(uint256 reward, uint256 waitTime, address user) public view returns (uint256) {
        // This defaults to 7 days
        uint256 rewardsDuration = stakingRewardsV2.rewardsDuration();
        uint256 previousRewardPerToken = stakingRewardsV2.rewardPerToken();
        uint256 rewardsPerTokenPaid = stakingRewardsV2.userRewardPerTokenPaid(user);
        uint256 totalSupply = stakingRewardsV2.totalSupply() + stakingRewardsV1.totalSupply();
        uint256 balance = stakingRewardsV2.balanceOf(user) + stakingRewardsV1.balanceOf(user);

        // general formula for rewards should be:
        // rewardRate = reward / rewardsDuration
        // newRewards = rewardRate * min(timePassed, rewardsDuration)
        // rewardPerToken = previousRewards + (newRewards * 1e18 / totalSupply)
        // rewardsPerTokenForUser = rewardPerToken - rewardPerTokenPaid
        // rewards = (balance * rewardsPerTokenForUser) / 1e18
        uint256 rewardRate = reward / rewardsDuration;
        uint256 newRewards = rewardRate * min(waitTime, rewardsDuration);
        uint256 rewardPerToken = previousRewardPerToken + (newRewards * 1e18 / totalSupply);
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

    function unstakeAllUnstakedEscrowV1(address account, uint256 amount) public {
        vm.prank(account);
        rewardEscrowV1.unstakeEscrow(amount);
    }

    function getNonStakedEscrowAmountV1(address account) public view returns (uint256) {
        return rewardEscrowV1.balanceOf(account) - stakingRewardsV1.escrowedBalanceOf(account);
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

    function fundAccountAndStakeV2(address account, uint256 amount) public {
        fundAndApproveAccountV2(account, amount);
        vm.prank(account);
        stakingRewardsV2.stake(amount);
    }

    function stakeFundsV2(address account, uint256 amount) public {
        vm.prank(account);
        kwenta.approve(address(stakingRewardsV2), amount);
        vm.prank(account);
        stakingRewardsV2.stake(amount);
    }

    function unstakeFundsV2(address account, uint256 amount) public {
        vm.prank(account);
        stakingRewardsV2.unstake(amount);
    }

    function stakeEscrowedFundsV2(address account, uint256 amount) public {
        vm.prank(address(rewardEscrowV2));
        stakingRewardsV2.stakeEscrow(account, amount);
    }

    function unstakeEscrowedFundsV2(address account, uint256 amount) public {
        vm.prank(address(rewardEscrowV2));
        stakingRewardsV2.unstakeEscrow(account, amount);
    }

    function createRewardEscrowEntryV2(address account, uint256 amount, uint256 duration) public {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), amount);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(account, amount, duration, 90);
    }

    function createRewardEscrowEntryV2(address account, uint256 amount, uint256 duration, uint8 earlyVestingFee) public {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), amount);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(account, amount, duration, earlyVestingFee);
    }

    function appendRewardEscrowEntryV2(address account, uint256 amount, uint256 duration) public {
        vm.prank(treasury);
        kwenta.transfer(address(rewardEscrowV2), amount);
        vm.prank(address(stakingRewardsV2));
        rewardEscrowV2.appendVestingEntry(account, amount, duration);
    }

    // INTEGRATION HELPERS
    function getStakingRewardsV2(address account) public {
        vm.prank(account);
        stakingRewardsV2.getReward();
    }

    function stakeAllUnstakedEscrowV2(address account) public {
        uint256 amount = getNonStakedEscrowAmountV2(account);
        vm.prank(account);
        rewardEscrowV2.stakeEscrow(amount);
    }

    function unstakeAllUnstakedEscrowV2(address account, uint256 amount) public {
        vm.prank(account);
        rewardEscrowV2.unstakeEscrow(amount);
    }

    function getNonStakedEscrowAmountV2(address account) public view returns (uint256) {
        return rewardEscrowV2.balanceOf(account) - stakingRewardsV2.escrowedBalanceOf(account);
    }
}
