// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {StakingRewardsTestHelpers} from "../utils/StakingRewardsTestHelpers.t.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import "../utils/Constants.t.sol";

contract StakingV2CooldownPeriodTests is StakingRewardsTestHelpers {
    /*//////////////////////////////////////////////////////////////
                        Unstaking During Cooldown
    //////////////////////////////////////////////////////////////*/

    function testCannotUnstakeDuringCooldown() public {
        // stake
        stakeFunds(address(this), TEST_VALUE);

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
        stakeFunds(address(this), stakeAmount);

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
        stakeEscrowedFunds(address(this), TEST_VALUE);

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
        unstakeEscrowedFunds(address(this), TEST_VALUE);

        // unstake midway through
        vm.warp(stakedAt + cooldownPeriod / 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingRewardsV2.CannotUnstakeDuringCooldown.selector,
                canUnstakeAt
            )
        );
        unstakeEscrowedFunds(address(this), TEST_VALUE);

        // unstake 1 sec before period ends
        vm.warp(stakedAt + cooldownPeriod - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingRewardsV2.CannotUnstakeDuringCooldown.selector,
                canUnstakeAt
            )
        );
        unstakeEscrowedFunds(address(this), TEST_VALUE);
    }

    function testCannotUnstakeEscrowDuringCooldownFuzz(
        uint32 stakeAmount,
        uint32 waitTime
    ) public {
        vm.assume(stakeAmount > 0);

        // stake
        stakeEscrowedFunds(address(this), stakeAmount);

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
        unstakeEscrowedFunds(address(this), stakeAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        Staking During Cooldown
    //////////////////////////////////////////////////////////////*/

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
        stakeEscrowedFunds(address(this), TEST_VALUE);

        // stake immediately again
        stakeEscrowedFunds(address(this), TEST_VALUE);

        // stake half the cooldown period later again
        vm.warp(
            block.timestamp + stakingRewardsV2.unstakingCooldownPeriod() / 2
        );
        stakeEscrowedFunds(address(this), TEST_VALUE);
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
        stakeEscrowedFunds(address(this), TEST_VALUE);

        // stake half the cooldown period later again
        vm.warp(
            block.timestamp + stakingRewardsV2.unstakingCooldownPeriod() / 2
        );
        stakeEscrowedFunds(address(this), TEST_VALUE);

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
        unstakeEscrowedFunds(address(this), TEST_VALUE);
    }

    /*//////////////////////////////////////////////////////////////
                        Changing Cooldown Period
    //////////////////////////////////////////////////////////////*/

    function testSetCooldownPeriodIsOnlyOwner() public {
        vm.expectRevert("Only the contract owner may perform this action");
        vm.prank(user1);
        stakingRewardsV2.setUnstakingCooldownPeriod(1 weeks);
    }

    function testSetCooldownPeriod() public {
        uint256 newCooldownPeriod = 1 weeks;

        // Expect correct event emitted
        vm.expectEmit(true, true, false, false);
        emit UnstakingCooldownPeriodUpdated(newCooldownPeriod);

        // Set new cooldown period
        stakingRewardsV2.setUnstakingCooldownPeriod(newCooldownPeriod);

        // Check cooldown period is updated
        assertEq(stakingRewardsV2.unstakingCooldownPeriod(), newCooldownPeriod);

        // stake
        stakeFunds(address(this), TEST_VALUE);

        // stake escrow
        stakeEscrowedFunds(address(this), TEST_VALUE);

        // move forward new cooldown period
        vm.warp(block.timestamp + newCooldownPeriod);

        // unstake
        stakingRewardsV2.unstake(TEST_VALUE);

        // unstake escrow
        unstakeEscrowedFunds(address(this), TEST_VALUE);
    }

    function testSetCooldownPeriodFuzz(
        uint128 newCooldownPeriod,
        uint128 timeJump
    ) public {
        vm.assume(newCooldownPeriod > stakingRewardsV2.minCooldownPeriod());
        vm.assume(newCooldownPeriod < stakingRewardsV2.maxCooldownPeriod());

        // Expect correct event emitted
        vm.expectEmit(true, true, false, false);
        emit UnstakingCooldownPeriodUpdated(newCooldownPeriod);

        // Set new cooldown period
        stakingRewardsV2.setUnstakingCooldownPeriod(newCooldownPeriod);

        // Check cooldown period is updated
        assertEq(stakingRewardsV2.unstakingCooldownPeriod(), newCooldownPeriod);

        // stake
        stakeFunds(address(this), TEST_VALUE);

        // stake escrow
        stakeEscrowedFunds(address(this), TEST_VALUE);

        uint256 canUnstakeAt = block.timestamp + newCooldownPeriod;

        // move forward new cooldown period
        vm.warp(block.timestamp + timeJump);

        if (timeJump < newCooldownPeriod) {
            // Expect revert if unstaking before cooldown period
            vm.expectRevert(
                abi.encodeWithSelector(
                    StakingRewardsV2.CannotUnstakeDuringCooldown.selector,
                    canUnstakeAt
                )
            );
        }
        // unstake
        stakingRewardsV2.unstake(TEST_VALUE);

        if (timeJump < newCooldownPeriod) {
            // Expect revert if unstaking before cooldown period
            vm.expectRevert(
                abi.encodeWithSelector(
                    StakingRewardsV2.CannotUnstakeDuringCooldown.selector,
                    canUnstakeAt
                )
            );
        }
        // unstake escrow
        unstakeEscrowedFunds(address(this), TEST_VALUE);
    }

    function testSetCooldownPeriodRange() public {
        // Expect revert if cooldown period is too low
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingRewardsV2.CooldownPeriodTooLow.selector,
                1 weeks
            )
        );
        stakingRewardsV2.setUnstakingCooldownPeriod(1 weeks - 1);

        // Expect revert if cooldown period is too high
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingRewardsV2.CooldownPeriodTooHigh.selector,
                52 weeks
            )
        );
        stakingRewardsV2.setUnstakingCooldownPeriod(52 weeks + 1);
    }

    function testSetCooldownPeriodRangeFuzz(uint256 newCooldownPeriod) public {
        // Expect revert if cooldown period is too low
        if (newCooldownPeriod < 1 weeks) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    StakingRewardsV2.CooldownPeriodTooLow.selector,
                    stakingRewardsV2.minCooldownPeriod()
                )
            );
        }

        // Expect revert if cooldown period is too high
        if (newCooldownPeriod > 52 weeks) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    StakingRewardsV2.CooldownPeriodTooHigh.selector,
                    stakingRewardsV2.maxCooldownPeriod()
                )
            );
        }

        // Set new cooldown period
        stakingRewardsV2.setUnstakingCooldownPeriod(newCooldownPeriod);
    }
}