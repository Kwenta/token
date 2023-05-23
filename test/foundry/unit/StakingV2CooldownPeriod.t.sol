// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.19;

// import {DefaultStakingV2Setup} from "../utils/DefaultStakingV2Setup.t.sol";
// import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
// import "../utils/Constants.t.sol";

// contract StakingV2CooldownPeriodTests is DefaultStakingV2Setup {
//     /*//////////////////////////////////////////////////////////////
//                         Unstaking During Cooldown
//     //////////////////////////////////////////////////////////////*/

//     function test_Cannot_unstake_During_Cooldown() public {
//         // stake
//         fundAccountAndStakeV2(address(this), TEST_VALUE);

//         uint256 cooldownPeriod = stakingRewardsV2.unstakingCooldownPeriod();
//         uint256 canUnstakeAt = block.timestamp + cooldownPeriod;
//         uint256 stakedAt = block.timestamp;

//         // unstake immediately
//         vm.expectRevert(abi.encodeWithSelector(StakingRewardsV2.CannotUnstakeDuringCooldown.selector, canUnstakeAt));
//         stakingRewardsV2.unstake(TEST_VALUE);

//         // unstake midway through
//         vm.warp(stakedAt + cooldownPeriod / 2);
//         vm.expectRevert(abi.encodeWithSelector(StakingRewardsV2.CannotUnstakeDuringCooldown.selector, canUnstakeAt));
//         stakingRewardsV2.unstake(TEST_VALUE);

//         // unstake 1 sec before period ends
//         vm.warp(stakedAt + cooldownPeriod - 1);
//         vm.expectRevert(abi.encodeWithSelector(StakingRewardsV2.CannotUnstakeDuringCooldown.selector, canUnstakeAt));
//         stakingRewardsV2.unstake(TEST_VALUE);
//     }

//     function test_Cannot_unstake_During_Cooldown_Fuzz(uint32 stakeAmount, uint32 waitTime) public {
//         vm.assume(stakeAmount > 0);

//         // stake
//         fundAccountAndStakeV2(address(this), stakeAmount);

//         uint256 cooldownPeriod = stakingRewardsV2.unstakingCooldownPeriod();
//         uint256 canUnstakeAt = block.timestamp + cooldownPeriod;
//         uint256 stakedAt = block.timestamp;

//         // unstake
//         vm.warp(stakedAt + waitTime);
//         if (waitTime < cooldownPeriod) {
//             vm.expectRevert(abi.encodeWithSelector(StakingRewardsV2.CannotUnstakeDuringCooldown.selector, canUnstakeAt));
//         }
//         stakingRewardsV2.unstake(stakeAmount);
//     }

//     function test_Cannot_unstakeEscrow_During_Cooldown() public {
//         // stake
//         stakeEscrowedFundsV2(address(this), TEST_VALUE);

//         uint256 cooldownPeriod = stakingRewardsV2.unstakingCooldownPeriod();
//         uint256 canUnstakeAt = block.timestamp + cooldownPeriod;
//         uint256 stakedAt = block.timestamp;

//         // unstake immediately
//         vm.expectRevert(abi.encodeWithSelector(StakingRewardsV2.CannotUnstakeDuringCooldown.selector, canUnstakeAt));
//         unstakeEscrowedFundsV2(address(this), TEST_VALUE);

//         // unstake midway through
//         vm.warp(stakedAt + cooldownPeriod / 2);
//         vm.expectRevert(abi.encodeWithSelector(StakingRewardsV2.CannotUnstakeDuringCooldown.selector, canUnstakeAt));
//         unstakeEscrowedFundsV2(address(this), TEST_VALUE);

//         // unstake 1 sec before period ends
//         vm.warp(stakedAt + cooldownPeriod - 1);
//         vm.expectRevert(abi.encodeWithSelector(StakingRewardsV2.CannotUnstakeDuringCooldown.selector, canUnstakeAt));
//         unstakeEscrowedFundsV2(address(this), TEST_VALUE);
//     }

//     function test_Cannot_unstakeEscrow_During_Cooldown_Fuzz(uint32 stakeAmount, uint32 waitTime) public {
//         vm.assume(stakeAmount > 0);

//         // stake
//         stakeEscrowedFundsV2(address(this), stakeAmount);

//         uint256 cooldownPeriod = stakingRewardsV2.unstakingCooldownPeriod();
//         uint256 canUnstakeAt = block.timestamp + cooldownPeriod;
//         uint256 stakedAt = block.timestamp;

//         // unstake
//         vm.warp(stakedAt + waitTime);
//         if (waitTime < cooldownPeriod) {
//             vm.expectRevert(abi.encodeWithSelector(StakingRewardsV2.CannotUnstakeDuringCooldown.selector, canUnstakeAt));
//         }
//         unstakeEscrowedFundsV2(address(this), stakeAmount);
//     }

//     /*//////////////////////////////////////////////////////////////
//                         Staking During Cooldown
//     //////////////////////////////////////////////////////////////*/

//     function test_Can_stake_More_During_Cooldown() public {
//         // stake once
//         fundAndApproveAccountV2(address(this), TEST_VALUE * 3);
//         stakingRewardsV2.stake(TEST_VALUE);

//         // stake immediately again
//         stakingRewardsV2.stake(TEST_VALUE);

//         // stake half the cooldown period later again
//         vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod() / 2);
//         stakingRewardsV2.stake(TEST_VALUE);
//     }

//     function test_Can_stakeEscrow_More_During_Cooldown() public {
//         // stake once
//         stakeEscrowedFundsV2(address(this), TEST_VALUE);

//         // stake immediately again
//         stakeEscrowedFundsV2(address(this), TEST_VALUE);

//         // stake half the cooldown period later again
//         vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod() / 2);
//         stakeEscrowedFundsV2(address(this), TEST_VALUE);
//     }

//     function test_Staking_During_Cooldown_Extends_Wait() public {
//         // stake
//         fundAndApproveAccountV2(address(this), TEST_VALUE * 3);
//         stakingRewardsV2.stake(TEST_VALUE);

//         // stake half the cooldown period later again
//         vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod() / 2);
//         stakingRewardsV2.stake(TEST_VALUE);

//         // expected can unstakeAt time is now the cooldown period from now
//         uint256 canUnstakeAt = block.timestamp + stakingRewardsV2.unstakingCooldownPeriod();

//         // cannot unstake another half period later
//         vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod() / 2);
//         vm.expectRevert(abi.encodeWithSelector(StakingRewardsV2.CannotUnstakeDuringCooldown.selector, canUnstakeAt));
//         stakingRewardsV2.unstake(TEST_VALUE);
//     }

//     function test_Staking_Escrow_During_Cooldown_Extends_Wait() public {
//         // stake
//         stakeEscrowedFundsV2(address(this), TEST_VALUE);

//         // stake half the cooldown period later again
//         vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod() / 2);
//         stakeEscrowedFundsV2(address(this), TEST_VALUE);

//         // expected can unstakeAt time is now the cooldown period from now
//         uint256 canUnstakeAt = block.timestamp + stakingRewardsV2.unstakingCooldownPeriod();

//         // cannot unstake another half period later
//         vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod() / 2);
//         vm.expectRevert(abi.encodeWithSelector(StakingRewardsV2.CannotUnstakeDuringCooldown.selector, canUnstakeAt));
//         unstakeEscrowedFundsV2(address(this), TEST_VALUE);
//     }

//     /*//////////////////////////////////////////////////////////////
//                         Changing Cooldown Period
//     //////////////////////////////////////////////////////////////*/

//     function test_setUnstakingCooldownPeriod_Is_Only_Owner() public {
//         vm.expectRevert("Ownable: caller is not the owner");
//         vm.prank(user1);
//         stakingRewardsV2.setUnstakingCooldownPeriod(1 weeks);
//     }

//     function test_setUnstakingCooldownPeriod() public {
//         uint256 newCooldownPeriod = 1 weeks;

//         // Expect correct event emitted
//         vm.expectEmit(true, false, false, true);
//         emit UnstakingCooldownPeriodUpdated(newCooldownPeriod);

//         // Set new cooldown period
//         stakingRewardsV2.setUnstakingCooldownPeriod(newCooldownPeriod);

//         // Check cooldown period is updated
//         assertEq(stakingRewardsV2.unstakingCooldownPeriod(), newCooldownPeriod);

//         // stake
//         fundAccountAndStakeV2(address(this), TEST_VALUE);

//         // stake escrow
//         stakeEscrowedFundsV2(address(this), TEST_VALUE);

//         // move forward new cooldown period
//         vm.warp(block.timestamp + newCooldownPeriod);

//         // unstake
//         stakingRewardsV2.unstake(TEST_VALUE);

//         // unstake escrow
//         unstakeEscrowedFundsV2(address(this), TEST_VALUE);
//     }

//     function test_setUnstakingCooldownPeriod_Fuzz(uint128 newCooldownPeriod, uint128 timeJump) public {
//         vm.assume(newCooldownPeriod > stakingRewardsV2.MIN_COOLDOWN_PERIOD());
//         vm.assume(newCooldownPeriod < stakingRewardsV2.MAX_COOLDOWN_PERIOD());

//         // Expect correct event emitted
//         vm.expectEmit(true, false, false, true);
//         emit UnstakingCooldownPeriodUpdated(newCooldownPeriod);

//         // Set new cooldown period
//         stakingRewardsV2.setUnstakingCooldownPeriod(newCooldownPeriod);

//         // Check cooldown period is updated
//         assertEq(stakingRewardsV2.unstakingCooldownPeriod(), newCooldownPeriod);

//         // stake
//         fundAccountAndStakeV2(address(this), TEST_VALUE);

//         // stake escrow
//         stakeEscrowedFundsV2(address(this), TEST_VALUE);

//         uint256 canUnstakeAt = block.timestamp + newCooldownPeriod;

//         // move forward new cooldown period
//         vm.warp(block.timestamp + timeJump);

//         if (timeJump < newCooldownPeriod) {
//             // Expect revert if unstaking before cooldown period
//             vm.expectRevert(abi.encodeWithSelector(StakingRewardsV2.CannotUnstakeDuringCooldown.selector, canUnstakeAt));
//         }
//         // unstake
//         stakingRewardsV2.unstake(TEST_VALUE);

//         if (timeJump < newCooldownPeriod) {
//             // Expect revert if unstaking before cooldown period
//             vm.expectRevert(abi.encodeWithSelector(StakingRewardsV2.CannotUnstakeDuringCooldown.selector, canUnstakeAt));
//         }
//         // unstake escrow
//         unstakeEscrowedFundsV2(address(this), TEST_VALUE);
//     }

//     function test_setUnstakingCooldownPeriod_Range() public {
//         // Expect revert if cooldown period is too low
//         vm.expectRevert(abi.encodeWithSelector(StakingRewardsV2.CooldownPeriodTooLow.selector, 1 weeks));
//         stakingRewardsV2.setUnstakingCooldownPeriod(1 weeks - 1);

//         // Expect revert if cooldown period is too high
//         vm.expectRevert(abi.encodeWithSelector(StakingRewardsV2.CooldownPeriodTooHigh.selector, 52 weeks));
//         stakingRewardsV2.setUnstakingCooldownPeriod(52 weeks + 1);
//     }

//     function test_setUnstakingCooldownPeriod_Range_Fuzz(uint256 newCooldownPeriod) public {
//         // Expect revert if cooldown period is too low
//         if (newCooldownPeriod < 1 weeks) {
//             vm.expectRevert(
//                 abi.encodeWithSelector(
//                     StakingRewardsV2.CooldownPeriodTooLow.selector, stakingRewardsV2.MIN_COOLDOWN_PERIOD()
//                 )
//             );
//         }

//         // Expect revert if cooldown period is too high
//         if (newCooldownPeriod > 52 weeks) {
//             vm.expectRevert(
//                 abi.encodeWithSelector(
//                     StakingRewardsV2.CooldownPeriodTooHigh.selector, stakingRewardsV2.MAX_COOLDOWN_PERIOD()
//                 )
//             );
//         }

//         // Set new cooldown period
//         stakingRewardsV2.setUnstakingCooldownPeriod(newCooldownPeriod);
//     }
// }
