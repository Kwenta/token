// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {StakingRewardsTestHelpers} from "../utils/StakingRewardsTestHelpers.t.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import "../utils/Constants.t.sol";

contract StakingRewardsV2ChangesTest is StakingRewardsTestHelpers {
    /*//////////////////////////////////////////////////////////////
                        Staking Cooldown Period
    //////////////////////////////////////////////////////////////*/

    function testCannotUnstakeDuringCooldown() public {
        // stake
        fundAndApproveAccount(address(this), TEST_VALUE);
        stakingRewardsV2.stake(TEST_VALUE);

        uint256 cooldownPeriod = stakingRewardsV2.unstakingCooldownPeriod();
        uint256 canUnstakeAt = block.timestamp + cooldownPeriod;
        uint256 stakedAt = block.timestamp;

        // unstake immediately
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingRewardsV2.CannotUnstakeDuringCooldown.selector,
                canUnstakeAt
            )
        );
        stakingRewardsV2.unstake(TEST_VALUE);

        // unstake midway through
        vm.warp(stakedAt + cooldownPeriod / 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingRewardsV2.CannotUnstakeDuringCooldown.selector,
                canUnstakeAt
            )
        );
        stakingRewardsV2.unstake(TEST_VALUE);

        // unstake 1 sec before period ends
        vm.warp(stakedAt + cooldownPeriod - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingRewardsV2.CannotUnstakeDuringCooldown.selector,
                canUnstakeAt
            )
        );
        stakingRewardsV2.unstake(TEST_VALUE);
    }

    function testCannotUnstakeDuringCooldownFuzz(
        uint32 stakeAmount,
        uint32 waitTime
    ) public {
        vm.assume(stakeAmount > 0);

        // stake
        fundAndApproveAccount(address(this), stakeAmount);
        stakingRewardsV2.stake(stakeAmount);

        uint256 cooldownPeriod = stakingRewardsV2.unstakingCooldownPeriod();
        uint256 canUnstakeAt = block.timestamp + cooldownPeriod;
        uint256 stakedAt = block.timestamp;

        // unstake
        vm.warp(stakedAt + waitTime);
        if (waitTime < cooldownPeriod) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    StakingRewardsV2.CannotUnstakeDuringCooldown.selector,
                    canUnstakeAt
                )
            );
        }
        stakingRewardsV2.unstake(stakeAmount);
    }

    function testCannotUnstakeEscrowDuringCooldown() public {
        // stake
        vm.prank(address(rewardEscrow));
        stakingRewardsV2.stakeEscrow(address(this), TEST_VALUE);

        uint256 cooldownPeriod = stakingRewardsV2.unstakingCooldownPeriod();
        uint256 canUnstakeAt = block.timestamp + cooldownPeriod;
        uint256 stakedAt = block.timestamp;

        // unstake immediately
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingRewardsV2.CannotUnstakeDuringCooldown.selector,
                canUnstakeAt
            )
        );
        vm.prank(address(rewardEscrow));
        stakingRewardsV2.unstakeEscrow(address(this), TEST_VALUE);

        // unstake midway through
        vm.warp(stakedAt + cooldownPeriod / 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingRewardsV2.CannotUnstakeDuringCooldown.selector,
                canUnstakeAt
            )
        );
        vm.prank(address(rewardEscrow));
        stakingRewardsV2.unstakeEscrow(address(this), TEST_VALUE);

        // unstake 1 sec before period ends
        vm.warp(stakedAt + cooldownPeriod - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingRewardsV2.CannotUnstakeDuringCooldown.selector,
                canUnstakeAt
            )
        );
        vm.prank(address(rewardEscrow));
        stakingRewardsV2.unstakeEscrow(address(this), TEST_VALUE);
    }

    function testCannotUnstakeEscrowDuringCooldownFuzz(
        uint32 stakeAmount,
        uint32 waitTime
    ) public {
        vm.assume(stakeAmount > 0);

        // stake
        vm.prank(address(rewardEscrow));
        stakingRewardsV2.stakeEscrow(address(this), stakeAmount);

        uint256 cooldownPeriod = stakingRewardsV2.unstakingCooldownPeriod();
        uint256 canUnstakeAt = block.timestamp + cooldownPeriod;
        uint256 stakedAt = block.timestamp;

        // unstake
        vm.warp(stakedAt + waitTime);
        if (waitTime < cooldownPeriod) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    StakingRewardsV2.CannotUnstakeDuringCooldown.selector,
                    canUnstakeAt
                )
            );
        }
        vm.prank(address(rewardEscrow));
        stakingRewardsV2.unstakeEscrow(address(this), stakeAmount);
    }

    function testCanStakeMoreDuringCooldown() public {
        // stake once
        fundAndApproveAccount(address(this), TEST_VALUE * 3);
        stakingRewardsV2.stake(TEST_VALUE);

        // stake immediately again
        stakingRewardsV2.stake(TEST_VALUE);

        // stake half the cooldown period later again
        vm.warp(
            block.timestamp + stakingRewardsV2.unstakingCooldownPeriod() / 2
        );
        stakingRewardsV2.stake(TEST_VALUE);
    }

    function testCanStakeEscrowMoreDuringCooldown() public {
        // stake once
        vm.prank(address(rewardEscrow));
        stakingRewardsV2.stakeEscrow(address(this), TEST_VALUE);

        // stake immediately again
        vm.prank(address(rewardEscrow));
        stakingRewardsV2.stakeEscrow(address(this), TEST_VALUE);

        // stake half the cooldown period later again
        vm.warp(
            block.timestamp + stakingRewardsV2.unstakingCooldownPeriod() / 2
        );
        vm.prank(address(rewardEscrow));
        stakingRewardsV2.stakeEscrow(address(this), TEST_VALUE);
    }

    function testStakingDuringCooldownExtendsWait() public {
        // stake
        fundAndApproveAccount(address(this), TEST_VALUE * 3);
        stakingRewardsV2.stake(TEST_VALUE);

        // stake half the cooldown period later again
        vm.warp(
            block.timestamp + stakingRewardsV2.unstakingCooldownPeriod() / 2
        );
        stakingRewardsV2.stake(TEST_VALUE);

        // expected can unstakeAt time is now the cooldown period from now
        uint256 canUnstakeAt = block.timestamp +
            stakingRewardsV2.unstakingCooldownPeriod();

        // cannot unstake another half period later
        vm.warp(
            block.timestamp + stakingRewardsV2.unstakingCooldownPeriod() / 2
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingRewardsV2.CannotUnstakeDuringCooldown.selector,
                canUnstakeAt
            )
        );
        stakingRewardsV2.unstake(TEST_VALUE);
    }

    function testStakingEscrowDuringCooldownExtendsWait() public {
        // stake
        vm.prank(address(rewardEscrow));
        stakingRewardsV2.stakeEscrow(address(this), TEST_VALUE);

        // stake half the cooldown period later again
        vm.warp(
            block.timestamp + stakingRewardsV2.unstakingCooldownPeriod() / 2
        );
        vm.prank(address(rewardEscrow));
        stakingRewardsV2.stakeEscrow(address(this), TEST_VALUE);

        // expected can unstakeAt time is now the cooldown period from now
        uint256 canUnstakeAt = block.timestamp +
            stakingRewardsV2.unstakingCooldownPeriod();

        // cannot unstake another half period later
        vm.warp(
            block.timestamp + stakingRewardsV2.unstakingCooldownPeriod() / 2
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingRewardsV2.CannotUnstakeDuringCooldown.selector,
                canUnstakeAt
            )
        );
        vm.prank(address(rewardEscrow));
        stakingRewardsV2.unstakeEscrow(address(this), TEST_VALUE);
    }

    // TODO: test setCooldownPeriod
    // TODO: test setCooldownPeriod min is 1 week
    // TODO: test setCooldownPeriod max is 1 year
    // TODO: test can unstake after cooldown
    // TODO: test can escrow unstake after cooldown

    // TODO: check when a user stakes balances checkpoints are updated
    // TODO: check when a user escrow stakes balances checkpoints are updated
    // TODO: check when a user stakes escrowedBalances checkpoints are unchanged???
    // TODO: check when a user escrow stakes escrowedBalances checkpoints are updated
    // TODO: check when a user stakes total supply checkpoints are updated
    // TODO: check when a user escrow stakes total supply checkpoints are updated

    // TODO: test escrowStaked mapping copy migration
    // TODO: test manual staked balance migration

    // TODO: refactor cooldown check into cooldownLock modifier
    // TODO: refactor - extract new functionality into new test file

    // TODO: suggest that instead of automatically transferring escrowed balances over - a migrate function should be added
}
