// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IEarlyVestFeeDistributor} from "../../../../contracts/interfaces/IEarlyVestFeeDistributor.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {RewardEscrowV2} from "../../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {EarlyVestFeeDistributorInternals} from "../../utils/EarlyVestFeeDistributorInternals.sol";
import {EarlyVestFeeDistributor} from "../../../../contracts/EarlyVestFeeDistributor.sol";

contract EarlyVestFeeDistributorTest is DefaultStakingV2Setup {
    event CheckpointToken(uint time, uint tokens);
    event EpochClaim(address user, uint epoch, uint tokens);

    function setUp() public override {
        /// @dev starts after a week so the startTime is != 0
        goForward(1 weeks + 1);
        super.setUp();
        vm.prank(treasury);
        kwenta.transfer(address(this), 100_000 ether);
    }

    /// @notice constructor fail when input address == 0
    function testInputAddress0() public {
        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.InputAddress0.selector)
        );
        earlyVestFeeDistributor = new EarlyVestFeeDistributor(
            address(0),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            0
        );
        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.InputAddress0.selector)
        );
        earlyVestFeeDistributor = new EarlyVestFeeDistributor(
            address(kwenta),
            address(0),
            address(rewardEscrowV2),
            0
        );
        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.InputAddress0.selector)
        );
        earlyVestFeeDistributor = new EarlyVestFeeDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            address(0),
            0
        );
    }

    /// @notice checkpointToken happy case after 1 week
    function testCheckpointToken() public {
        kwenta.transfer(address(earlyVestFeeDistributor), 10);
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        goForward(1 weeks);

        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(2 weeks + 2, 10);
        earlyVestFeeDistributor.checkpointToken();
    }

    /// @notice checkpointToken for missed weeks
    function testCheckpointTokenManyMissed() public {
        kwenta.transfer(address(earlyVestFeeDistributor), 10);
        goForward(5 weeks);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(6 weeks + 2, 10);
        earlyVestFeeDistributor.checkpointToken();
    }

    /// @notice checkpointToken for sinceLast == 0
    function testManyCheckpointTokenAtOnce() public {
        kwenta.transfer(address(earlyVestFeeDistributor), 10);
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        goForward(1 weeks);

        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(2 weeks + 2, 10);
        earlyVestFeeDistributor.checkpointToken();
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(2 weeks + 2, 0);
        earlyVestFeeDistributor.checkpointToken();
    }

    /// @notice checkpoint at the start and < 1 week
    /// make sure theres no error dividing by 0
    /// because thisEpoch should be 0
    function testCheckpointTokenFirstWeek() public {
        earlyVestFeeDistributor.checkpointToken();
        goForward(1 days);
        earlyVestFeeDistributor.checkpointToken();
    }

    /// @notice claimEpoch happy case
    function testClaimEpoch() public {
        //setup
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        goForward(1 weeks);

        kwenta.transfer(address(earlyVestFeeDistributor), 10);
        goForward(1 weeks);

        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(3 weeks + 2, 10);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), 4, 52 weeks, 1, 90);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 1, 4);
        earlyVestFeeDistributor.claimEpoch(address(user1), 1);
    }

    /// @notice claimEpoch happy case for > 1 person
    function testClaimEpoch3People() public {
        //setup
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();

        kwenta.transfer(address(user2), 1);
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();

        kwenta.transfer(address(user3), 3);
        vm.startPrank(address(user3));
        kwenta.approve(address(stakingRewardsV2), 3);
        stakingRewardsV2.stake(3);
        vm.stopPrank();

        goForward(1 weeks);

        EarlyVestFeeDistributor earlyVestFeeDistributorOffset = new EarlyVestFeeDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        earlyVestFeeDistributorOffset.checkpointToken();
        kwenta.transfer(address(earlyVestFeeDistributorOffset), 10);
        /// @dev forward to the exact end of epoch 0 and start of 1
        goForward(2 days - 2);

        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), 2, 52 weeks, 1, 90);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 0, 2);
        earlyVestFeeDistributorOffset.claimEpoch(address(user1), 0);

        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user2), 2, 52 weeks, 2, 90);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user2), 0, 2);
        earlyVestFeeDistributorOffset.claimEpoch(address(user2), 0);

        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user3), 6, 52 weeks, 3, 90);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user3), 0, 6);
        earlyVestFeeDistributorOffset.claimEpoch(address(user3), 0);
    }

    /// @notice claimEpoch happy case for epoch 0
    function testClaimEpoch0() public {
        //setup
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        goForward(1 weeks);

        EarlyVestFeeDistributor earlyVestFeeDistributorOffset = new EarlyVestFeeDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        earlyVestFeeDistributorOffset.checkpointToken();
        kwenta.transfer(address(earlyVestFeeDistributorOffset), 10);
        /// @dev forward to the exact end of epoch 0 and start of 1
        goForward(2 days - 2);

        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), 10, 52 weeks, 1, 90);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 0, 10);
        earlyVestFeeDistributorOffset.claimEpoch(address(user1), 0);
    }

    /// @notice make sure a checkpoint is created even if < 24 if it
    /// is a new week
    function testClaimEpochCheckpoint() public {
        //setup
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        kwenta.transfer(address(user2), 2);
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), 2);
        stakingRewardsV2.stake(2);
        vm.stopPrank();
        goForward(1 weeks + 1);

        /// @dev checkpoint just before the week ends
        kwenta.transfer(address(earlyVestFeeDistributor), 10);
        goForward(1 weeks - 4800);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1809603, 10);
        earlyVestFeeDistributor.checkpointToken();
        kwenta.transfer(address(earlyVestFeeDistributor), 5);
        goForward(4801);

        /// @dev make sure a claim at the turn of the week
        /// will checkpoint even if its < 24 hours
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1814404, 5);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), 2, 52 weeks, 1, 90);
        earlyVestFeeDistributor.claimEpoch(address(user1), 1);

        /// @dev a claim < 24 hours and not the first one
        /// of the week will not checkpoint which is correct
        goForward(1000);
        earlyVestFeeDistributor.claimEpoch(address(user2), 1);
    }

    /// @notice claimEpoch fail - epoch is not ready to claim
    function testClaimEpochNotReady() public {
        vm.startPrank(user1);

        goForward(.5 weeks);
        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.CannotClaimYet.selector)
        );
        earlyVestFeeDistributor.claimEpoch(address(user1), 0);
    }

    /// @notice claimEpoch fail - epoch is not ready to claim, not an epoch yet
    function testClaimEpochAhead() public {
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.CannotClaimYet.selector)
        );
        earlyVestFeeDistributor.claimEpoch(address(user1), 7);
    }

    /// @notice claimEpoch fail - no epoch to claim yet
    function testClaimNoEpochYet() public {
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.CannotClaimYet.selector)
        );
        earlyVestFeeDistributor.claimEpoch(address(user1), 0);
    }

    /// @notice claimEpoch fail - already claimed
    function testClaimAlreadyClaimed() public {
        //setup
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        goForward(1 weeks);
        kwenta.transfer(address(earlyVestFeeDistributor), 10);
        goForward(1 weeks);
        earlyVestFeeDistributor.claimEpoch(address(user1), 1);

        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.CannotClaimTwice.selector)
        );
        earlyVestFeeDistributor.claimEpoch(address(user1), 1);
    }

    /// @notice claimEpoch fail - claim an epoch that had no staking
    function testClaimNoStaking() public {
        kwenta.transfer(address(earlyVestFeeDistributor), 10);
        kwenta.transfer(address(user1), 1);
        vm.startPrank(user1);
        goForward(1 weeks);
        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.CannotClaim0Fees.selector)
        );
        earlyVestFeeDistributor.claimEpoch(address(user1), 0);
    }

    /// @notice claimEpoch fail - nonstaker tries to claim
    /// (cannot claim 0 fees)
    function testClaimNotStaker() public {
        //setup
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        goForward(1 weeks);
        kwenta.transfer(address(earlyVestFeeDistributor), 10);
        goForward(1 weeks);

        earlyVestFeeDistributor.claimEpoch(address(user1), 1);
        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.CannotClaim0Fees.selector)
        );
        earlyVestFeeDistributor.claimEpoch(address(user2), 1);
    }

    /// @notice claimEpoch happy case with a person who
    /// was previously staked but is now unstaked and trying to
    /// claim their fees
    function testClaimPreviouslyStaked() public {
        //setup
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        goForward(1 weeks);
        kwenta.transfer(address(earlyVestFeeDistributor), 10);
        goForward(1 weeks);

        vm.prank(address(user1));
        stakingRewardsV2.unstake(1);
        goForward(2 weeks);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), 2, 52 weeks, 1, 90);
        earlyVestFeeDistributor.claimEpoch(address(user1), 1);
    }

    /// @notice testCalculateEpochFees happy case
    function testCalculateEpochFees() public {
        kwenta.transfer(address(user1), 1);
        kwenta.transfer(address(user2), 2);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), 2);
        stakingRewardsV2.stake(2);
        vm.stopPrank();

        goForward(1 weeks);
        /// @dev forward half a week so it puts fees in epoch 1
        goForward(304801);
        kwenta.transfer(address(earlyVestFeeDistributor), 1000);
        earlyVestFeeDistributor.checkpointToken();
        goForward(1 weeks);

        uint256 sum = earlyVestFeeDistributor.calculateEpochFees(user1, 1);
        assertEq(sum, 111);
    }

    /// @notice fuzz calculateEpochFees, especially when checkpoints are across weeks
    function testFuzzCalculateEpochFees(uint256 amount) public {
        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 100_000 ether);
        vm.assume(amount > 10);

        kwenta.transfer(address(user1), 1);
        kwenta.transfer(address(user2), 2);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), 2);
        stakingRewardsV2.stake(2);
        vm.stopPrank();
        goForward(1 weeks - 2);

        /// @dev send fees to EarlyVestFeeDistributor midway through epoch 1
        /// this will be split between all of epoch 0 and half of 1
        goForward(.5 weeks);
        kwenta.transfer(address(earlyVestFeeDistributor), amount);
        uint256 timeSinceLastCheckpoint = block.timestamp - 1 weeks;
        earlyVestFeeDistributor.checkpointToken();

        uint256 result = earlyVestFeeDistributor.calculateEpochFees(address(user2), 1);
        /// @dev calculate the proportion for this week (same as checkpoint math)
        /// then get the proportion staked (2/3)
        assertEq(
            result,
            (((amount * .5 weeks) / timeSinceLastCheckpoint) * 2) / 3
        );
    }

    /// @notice fuzz calculateEpochFees, especially for when multiple weeks are missed
    function testFuzzCalculateMultipleWeeksMissed(uint256 amount) public {
        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 100_000 ether);
        vm.assume(amount > 10);

        kwenta.transfer(address(user1), 1);
        kwenta.transfer(address(user2), 2);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), 2);
        stakingRewardsV2.stake(2);
        vm.stopPrank();
        goForward(1 weeks - 2);

        /// @dev send fees to EarlyVestFeeDistributor midway through epoch 3
        /// this will be split between epochs 0 - 3.5
        goForward(2.5 weeks);
        kwenta.transfer(address(earlyVestFeeDistributor), amount);
        earlyVestFeeDistributor.checkpointToken();

        uint256 result = earlyVestFeeDistributor.calculateEpochFees(address(user2), 1);
        /// @dev calculate the proportion for this week (same as checkpoint math)
        /// then get the proportion staked (2/3)
        assertEq(result, (((amount * 1 weeks) / 3.5 weeks) * 2) / 3);
    }

    /// @notice fuzz calculateEpochFees, when staking amounts are random
    function testFuzzStakingCalculateEpochFees(
        uint256 amount,
        uint256 staking1,
        uint256 staking2
    ) public {
        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 10_000 ether);
        vm.assume(amount > 10);

        vm.assume(staking1 < 45_000 ether);
        vm.assume(staking1 > 0);

        vm.assume(staking2 < 45_000 ether);
        vm.assume(staking2 > 0);

        kwenta.transfer(address(user1), staking1);
        kwenta.transfer(address(user2), staking2);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), staking1);
        stakingRewardsV2.stake(staking1);
        vm.stopPrank();
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), staking2);
        stakingRewardsV2.stake(staking2);
        vm.stopPrank();
        goForward(1 weeks - 2);

        /// @dev send fees to EarlyVestFeeDistributor midway through epoch 1
        /// this will be split between all of epoch 0 and half of 1
        goForward(.5 weeks);
        kwenta.transfer(address(earlyVestFeeDistributor), amount);
        uint256 timeSinceLastCheckpoint = block.timestamp - 1 weeks;
        earlyVestFeeDistributor.checkpointToken();

        uint256 result = earlyVestFeeDistributor.calculateEpochFees(address(user2), 1);
        /// @dev calculate the proportion for this week (same as checkpoint math)
        /// then get the proportion staked
        assertEq(
            result,
            (((amount * .5 weeks) / timeSinceLastCheckpoint) * staking2) /
                (staking1 + staking2)
        );
    }

    /// @notice fuzz calculateEpochFees, fuzz the time until they checkpoint
    function testFuzzCalculateMultipleWeeksMissed(
        uint256 amount,
        uint256 time
    ) public {
        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 100_000 ether);
        vm.assume(amount > 10);

        vm.assume(time < 1 weeks * 52);

        kwenta.transfer(address(user1), 1);
        kwenta.transfer(address(user2), 2);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), 2);
        stakingRewardsV2.stake(2);
        vm.stopPrank();
        goForward(1 weeks - 2);

        /// @dev send fees to EarlyVestFeeDistributor
        goForward(1 weeks);
        goForward(time);
        kwenta.transfer(address(earlyVestFeeDistributor), amount);
        earlyVestFeeDistributor.checkpointToken();

        uint256 result = earlyVestFeeDistributor.calculateEpochFees(address(user2), 1);
        /// @dev calculate the proportion for this week (same as checkpoint math)
        /// then get the proportion staked (2/3)
        assertEq(result, (((amount * 1 weeks) / (time + 2 weeks)) * 2) / 3);
    }

    /// @notice test calculate epoch fees for returning 0
    /// when total staked == 0
    function testCalculateEpochFees0() public {
        uint256 result = earlyVestFeeDistributor.calculateEpochFees(address(user1), 1);
        assertEq(result, 0);
    }

    /// @notice claimEpoch happy case with partial claims
    /// in earlier epochs 2 complete epochs with differing fees
    /// @dev also an integration test with RewardEscrowV2
    function testClaimMultipleClaims() public {
        /// @dev user1 has 1/3 total staking and user2 has 2/3
        kwenta.transfer(address(user1), 1);
        kwenta.transfer(address(user2), 2);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), 2);
        stakingRewardsV2.stake(2);
        vm.stopPrank();
        goForward(1 weeks + 1);

        /// @notice start of epoch 1
        /// midway through epoch #1 EarlyVestFeeDistributor
        /// receives 1000 in fees and checkpoints
        /// (this is split up between epoch 0 and 1)
        goForward(304801);
        kwenta.transfer(address(earlyVestFeeDistributor), 1000);
        earlyVestFeeDistributor.checkpointToken();
        goForward(1 weeks + 1);

        /// @dev during epoch #2, user1 claims their fees from #1
        /// and EarlyVestFeeDistributor receives 5000 in fees
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), 111, 52 weeks, 1, 90);
        earlyVestFeeDistributor.claimEpoch(address(user1), 1);
        kwenta.transfer(address(earlyVestFeeDistributor), 5000);

        /// @dev At the start of epoch #3 user1 claims for epoch #2
        /// user2 also claims for #2 and #1
        /// and EarlyVestFeeDistributor receives 300 in fees
        goForward(304801);
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), 1640, 52 weeks, 2, 90);
        earlyVestFeeDistributor.claimEpoch(address(user1), 2);
        goForward(1000);
        kwenta.transfer(address(earlyVestFeeDistributor), 300);
        vm.prank(user2);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user2), 3280, 52 weeks, 3, 90);
        earlyVestFeeDistributor.claimEpoch(address(user2), 2);
        vm.prank(user2);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user2), 223, 52 weeks, 4, 90);
        earlyVestFeeDistributor.claimEpoch(address(user2), 1);
    }

    /// @notice test claimMany
    function testClaimMany() public {
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();

        goForward(1.5 weeks);
        kwenta.transfer(address(earlyVestFeeDistributor), 1000);
        earlyVestFeeDistributor.checkpointToken();
        goForward(1 weeks);

        kwenta.transfer(address(earlyVestFeeDistributor), 5000);
        goForward(1 weeks);

        uint[] memory epochs = new uint[](2);
        epochs[0] = 1;
        epochs[1] = 2;
        earlyVestFeeDistributor.claimMany(address(user1), epochs);
    }

    /// @notice test claimMany fail (one epoch cant be claimed)
    function testFailClaimMany() public {
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();

        goForward(1.5 weeks);
        kwenta.transfer(address(earlyVestFeeDistributor), 1000);
        earlyVestFeeDistributor.checkpointToken();
        goForward(1 weeks);

        kwenta.transfer(address(earlyVestFeeDistributor), 5000);
        goForward(1 weeks);

        uint[] memory epochs = new uint[](2);
        epochs[0] = 1;
        epochs[1] = 2;
        epochs[2] = 3;
        earlyVestFeeDistributor.claimMany(address(user1), epochs);
    }

    /// @notice fuzz claimEpochFees
    function testFuzzClaim(uint256 amount) public {
        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 99_999 ether);
        vm.assume(amount > 10);

        kwenta.transfer(address(user1), 1);
        kwenta.transfer(address(user2), 2);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), 2);
        stakingRewardsV2.stake(2);
        vm.stopPrank();
        /// @dev checkpoint at the end of epoch 0
        /// to remove cross epoch distribution
        /// -2 because setup takes 2 seconds
        goForward(1 weeks - 2);
        earlyVestFeeDistributor.checkpointToken();

        /// @dev send fees to EarlyVestFeeDistributor 1 second before
        /// epoch 1 ends
        goForward(1 weeks - 1);
        kwenta.transfer(address(earlyVestFeeDistributor), amount);
        earlyVestFeeDistributor.checkpointToken();
        goForward(1);

        /// @dev claim for epoch 1 at the first second of epoch 2
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), amount / 3, 52 weeks, 1, 90);
        earlyVestFeeDistributor.claimEpoch(address(user1), 1);
    }

    /// @notice fuzz claimEpochFees, fuzz staking
    function testFuzzStakingClaim(
        uint256 amount,
        uint256 staking1,
        uint256 staking2
    ) public {
        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 10_000 ether);
        vm.assume(amount > 10);

        vm.assume(staking1 < 45_000 ether);
        vm.assume(staking1 > 0);

        vm.assume(staking2 < 45_000 ether);
        vm.assume(staking2 > 0);

        /// @dev this is so we dont get "Cannot claim 0 fees"
        vm.assume((amount * staking1) / (staking1 + staking2) > 0);

        kwenta.transfer(address(user1), staking1);
        kwenta.transfer(address(user2), staking2);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), staking1);
        stakingRewardsV2.stake(staking1);
        vm.stopPrank();
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), staking2);
        stakingRewardsV2.stake(staking2);
        vm.stopPrank();
        /// @dev checkpoint at the end of epoch 0
        /// to remove cross epoch distribution
        /// -2 because setup takes 2 seconds
        goForward(1 weeks - 2);
        earlyVestFeeDistributor.checkpointToken();

        /// @dev send fees to EarlyVestFeeDistributor 1 second before
        /// epoch 1 ends
        goForward(1 weeks - 1);
        kwenta.transfer(address(earlyVestFeeDistributor), amount);
        earlyVestFeeDistributor.checkpointToken();
        goForward(1);

        /// @dev claim for epoch 1 at the first second of epoch 2
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(
            address(user1),
            (amount * staking1) / (staking1 + staking2),
            52 weeks,
            1,
            90
        );
        earlyVestFeeDistributor.claimEpoch(address(user1), 1);
    }

    /// @notice fuzz claimEpochFees, fuzz time
    function testFuzzTimeClaim(
        uint256 amount,
        uint256 staking1,
        uint256 staking2,
        uint256 time
    ) public {
        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 10_000 ether);
        vm.assume(amount > 10);

        vm.assume(staking1 < 45_000 ether);
        vm.assume(staking1 > 0);

        vm.assume(staking2 < 45_000 ether);
        vm.assume(staking2 > 0);

        /// @dev this is so we dont get "Cannot claim 0 fees"
        vm.assume(time < 52 weeks);
        uint proportionalFees = (((amount * 1 weeks) / (time + 1 weeks)) *
            staking1) / (staking1 + staking2);
        vm.assume(proportionalFees > 0);

        kwenta.transfer(address(user1), staking1);
        kwenta.transfer(address(user2), staking2);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), staking1);
        stakingRewardsV2.stake(staking1);
        vm.stopPrank();
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), staking2);
        stakingRewardsV2.stake(staking2);
        vm.stopPrank();
        /// @dev checkpoint at the end of epoch 0
        /// to remove cross epoch distribution
        /// -2 because setup takes 2 seconds
        goForward(1 weeks - 2);
        earlyVestFeeDistributor.checkpointToken();

        /// @dev send fees to EarlyVestFeeDistributor 1 second before
        /// epoch 1 ends
        goForward(1 weeks - 1);
        kwenta.transfer(address(earlyVestFeeDistributor), amount);
        goForward(1);
        goForward(time);

        /// @dev claim for epoch 1 at the first second of epoch 2
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(
            address(user1),
            proportionalFees,
            52 weeks,
            1,
            90
        );
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 1, proportionalFees);
        earlyVestFeeDistributor.claimEpoch(address(user1), 1);
    }

    /// @notice test everything with a custom offset
    function testOffset() public {
        EarlyVestFeeDistributor earlyVestFeeDistributorOffset = new EarlyVestFeeDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();

        /// @dev fees received at the start of the epoch (should be + 2 days)
        goForward(2 days + 1);
        kwenta.transfer(address(earlyVestFeeDistributorOffset), 100);

        /// @dev checkpoint token < 24 hours before epoch end
        goForward(1 weeks - 4800);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1377603, 100);
        earlyVestFeeDistributorOffset.checkpointToken();
        kwenta.transfer(address(earlyVestFeeDistributorOffset), 5);
        goForward(4801);

        /// @dev claim at the start of the new epoch (should also checkpoint)
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1382404, 5);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), 53, 52 weeks, 1, 90);
        earlyVestFeeDistributorOffset.claimEpoch(address(user1), 1);

        /// @dev user2 cant claim because they didnt stake
        vm.expectRevert();
        earlyVestFeeDistributorOffset.claimEpoch(address(user2), 1);
    }

    /// @notice test fuzz fees with a custom offset
    function testFuzzFeesOffset(uint amount) public {
        EarlyVestFeeDistributor earlyVestFeeDistributorOffset = new EarlyVestFeeDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 100_000 ether);
        vm.assume(amount > 10);

        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();

        /// @dev fees received at the start of the epoch (should be + 2 days)
        goForward(2 days - 2);
        earlyVestFeeDistributorOffset.checkpointToken();
        kwenta.transfer(address(earlyVestFeeDistributorOffset), amount);

        /// @dev claim at the start of the new epoch (should also checkpoint)
        goForward(1 weeks);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1382400, amount);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 1, amount);
        earlyVestFeeDistributorOffset.claimEpoch(address(user1), 1);
    }

    /// @notice test fuzz staking with a custom offset
    function testFuzzStakingOffset(
        uint amount,
        uint staking1,
        uint staking2,
        uint staking3
    ) public {
        EarlyVestFeeDistributor earlyVestFeeDistributorOffset = new EarlyVestFeeDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 25_000 ether);
        vm.assume(amount > 10);

        vm.assume(staking1 < 25_000 ether);
        vm.assume(staking1 > 0);

        vm.assume(staking2 < 25_000 ether);
        vm.assume(staking2 > 0);

        vm.assume(staking3 < 25_000 ether);
        vm.assume(staking3 > 0);

        uint proportionalFees1 = (amount * staking1) /
            (staking1 + staking2 + staking3);
        uint proportionalFees2 = (amount * staking2) /
            (staking1 + staking2 + staking3);
        uint proportionalFees3 = (amount * staking3) /
            (staking1 + staking2 + staking3);
        vm.assume(proportionalFees1 > 0);
        vm.assume(proportionalFees2 > 0);
        vm.assume(proportionalFees3 > 0);

        kwenta.transfer(address(user1), staking1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), staking1);
        stakingRewardsV2.stake(staking1);
        vm.stopPrank();

        kwenta.transfer(address(user2), staking2);
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), staking2);
        stakingRewardsV2.stake(staking2);
        vm.stopPrank();

        kwenta.transfer(address(user3), staking3);
        vm.startPrank(address(user3));
        kwenta.approve(address(stakingRewardsV2), staking3);
        stakingRewardsV2.stake(staking3);
        vm.stopPrank();

        /// @dev fees received at the start of the epoch (should be + 2 days)
        goForward(2 days - 2);
        earlyVestFeeDistributorOffset.checkpointToken();
        kwenta.transfer(address(earlyVestFeeDistributorOffset), amount);

        /// @dev claim at the start of the new epoch (should also checkpoint)
        goForward(1 weeks);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1382400, amount);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 1, proportionalFees1);
        earlyVestFeeDistributorOffset.claimEpoch(address(user1), 1);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user2), 1, proportionalFees2);
        earlyVestFeeDistributorOffset.claimEpoch(address(user2), 1);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user3), 1, proportionalFees3);
        earlyVestFeeDistributorOffset.claimEpoch(address(user3), 1);
    }

    /// @notice test fuzz time with a custom offset
    function testFuzzTimeOffset(
        uint amount,
        uint staking1,
        uint staking2,
        uint staking3,
        uint time
    ) public {
        EarlyVestFeeDistributor earlyVestFeeDistributorOffset = new EarlyVestFeeDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 25_000 ether);
        vm.assume(amount > 10);

        vm.assume(staking1 < 25_000 ether);
        vm.assume(staking1 > 0);

        vm.assume(staking2 < 25_000 ether);
        vm.assume(staking2 > 0);

        vm.assume(staking3 < 25_000 ether);
        vm.assume(staking3 > 0);

        /// @dev this is so we dont get "Cannot claim 0 fees"
        vm.assume(time < 52 weeks);
        uint proportionalFees1 = ((((amount * 1 weeks) / (time + 1 weeks)) *
            staking1) / (staking1 + staking2 + staking3));
        uint proportionalFees2 = ((((amount * 1 weeks) / (time + 1 weeks)) *
            staking2) / (staking1 + staking2 + staking3));
        uint proportionalFees3 = ((((amount * 1 weeks) / (time + 1 weeks)) *
            staking3) / (staking1 + staking2 + staking3));
        vm.assume(proportionalFees1 > 0);
        vm.assume(proportionalFees2 > 0);
        vm.assume(proportionalFees3 > 0);

        kwenta.transfer(address(user1), staking1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), staking1);
        stakingRewardsV2.stake(staking1);
        vm.stopPrank();

        kwenta.transfer(address(user2), staking2);
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), staking2);
        stakingRewardsV2.stake(staking2);
        vm.stopPrank();

        kwenta.transfer(address(user3), staking3);
        vm.startPrank(address(user3));
        kwenta.approve(address(stakingRewardsV2), staking3);
        stakingRewardsV2.stake(staking3);
        vm.stopPrank();

        /// @dev fees received at the start of the epoch (should be + 2 days)
        goForward(2 days - 2);
        earlyVestFeeDistributorOffset.checkpointToken();
        kwenta.transfer(address(earlyVestFeeDistributorOffset), amount);

        /// @dev claim at the start of the new epoch (should also checkpoint)
        goForward(1 weeks);
        goForward(time);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1382400 + time, amount);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 1, proportionalFees1);
        earlyVestFeeDistributorOffset.claimEpoch(address(user1), 1);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user2), 1, proportionalFees2);
        earlyVestFeeDistributorOffset.claimEpoch(address(user2), 1);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user3), 1, proportionalFees3);
        earlyVestFeeDistributorOffset.claimEpoch(address(user3), 1);
    }

    /// @notice test startOfWeek
    function testStartOfWeek() public {
        /// @dev starts after another week so the startTime is != 0
        goForward(1 weeks);

        EarlyVestFeeDistributorInternals earlyVestFeeDistributorOffset = new EarlyVestFeeDistributorInternals(
                address(kwenta),
                address(stakingRewardsV2),
                address(rewardEscrowV2),
                2
            );

        /// @dev normally the start of the week would be 608400 but offset of 2
        /// makes it it 777600 (608400 + 86400 * 2)
        /// @note the current timestamp is 608402 but the start of the OFFSET week
        /// is not for another 2 days
        uint result = earlyVestFeeDistributorOffset.startOfWeek(block.timestamp);
        assertEq(result, 1 weeks + 2 days);

        goForward(2 days);
        uint result2 = earlyVestFeeDistributorOffset.startOfWeek(block.timestamp);
        assertEq(result2, 2 weeks + 2 days);

        /// @dev this should be passed a normal week but just before the offset
        /// week so nothing should change
        goForward(604000);
        uint result3 = earlyVestFeeDistributorOffset.startOfWeek(block.timestamp);
        assertEq(result3, 2 weeks + 2 days);

        /// @dev this is a few hundred seconds into a new offset week so should
        /// be a different start time
        goForward(1000);
        uint result4 = earlyVestFeeDistributorOffset.startOfWeek(block.timestamp);
        assertEq(result4, 3 weeks + 2 days);
    }

    /// @notice test startOfWeek exactly at the turn of the week
    function testExactlyStartOfWeek() public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            0
        );
        uint result1 = eVFDI.startOfWeek(block.timestamp);
        assertEq(result1, 1 weeks);

        /// @dev this is 1 second before the turn of the week
        goForward(1 weeks - 3);
        uint result2 = eVFDI.startOfWeek(block.timestamp);
        assertEq(result2, 1 weeks);

        /// @dev this is the first second of week 2
        goForward(1);
        uint result3 = eVFDI.startOfWeek(block.timestamp);
        assertEq(result3, 2 weeks);
    }

    /// @notice test claiming an unready epoch with an offset
    function testCannotClaimYetOffset() public {
        EarlyVestFeeDistributorInternals earlyVestFeeDistributorOffset = new EarlyVestFeeDistributorInternals(
                address(kwenta),
                address(stakingRewardsV2),
                address(rewardEscrowV2),
                2
            );

        vm.startPrank(user1);

        /// @dev this goForward gets it right before the offset week changes
        /// but a regular week has already changed. claim should revert because
        /// it is offset and still not ready to claim
        goForward(2 days - 3);
        uint result = earlyVestFeeDistributorOffset.startOfWeek(block.timestamp);
        assertEq(result, 2 days);
        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.CannotClaimYet.selector)
        );
        earlyVestFeeDistributorOffset.claimEpoch(address(user1), 0);
    }

    /// @notice test _startOfEpoch so that it follows an offset like _startOfWeek
    function testStartOfEpoch() public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        assertEq(eVFDI.startOfWeek(block.timestamp), eVFDI.startOfEpoch(0));

        goForward(2 days);

        assertEq(eVFDI.startOfWeek(block.timestamp), eVFDI.startOfEpoch(1));
    }

    // Test _checkpointWhenReady

    /// @notice test _checkpointWhenReady for when its < 24 hrs and not a new week
    function testFailCheckpointWhenNotReady() public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        eVFDI.checkpointToken();
        vm.expectEmit(false, false, false, true);
        emit CheckpointToken(1 weeks + 2, 0);
        /// @dev this does not checkpoint and fails
        eVFDI.checkpointWhenReady();
    }

    /// @notice test _checkpointWhenReady for when its > 24 hrs and not new week
    function testCheckpointWhenReady24Hrs() public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        goForward(1 days + 1);
        uint result = eVFDI.startOfWeek(block.timestamp);
        assertEq(result, 2 days);
        vm.expectEmit(false, false, false, true);
        emit CheckpointToken(1 weeks + 1 days + 3, 0);
        eVFDI.checkpointWhenReady();
    }

    /// @notice test _checkpointWhenReady for when its > 24 hrs and is new week
    function testCheckpointWhen24hrsAndNewWeek() public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        uint result = eVFDI.startOfWeek(block.timestamp);
        assertEq(result, 2 days);

        goForward(3 days);
        uint result2 = eVFDI.startOfWeek(block.timestamp);
        assertEq(result2, 1 weeks + 2 days);
        vm.expectEmit(false, false, false, true);
        emit CheckpointToken(1 weeks + 3 days + 2, 0);
        eVFDI.checkpointWhenReady();
    }

    /// @notice test _checkpointWhenReady for when its < 24 hrs and is new week
    function testCheckpointWhenReadyNewWeek() public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        goForward(1.5 days);
        uint result = eVFDI.startOfWeek(block.timestamp);
        assertEq(result, 2 days);
        eVFDI.checkpointToken();

        goForward(1 days);
        uint result2 = eVFDI.startOfWeek(block.timestamp);
        assertEq(result2, 1 weeks + 2 days);
        vm.expectEmit(false, false, false, true);
        emit CheckpointToken(1 weeks + 2.5 days + 2, 0);
        eVFDI.checkpointWhenReady();
    }

    /// @notice test fail _checkpointWhenReady for when its been exactly 24 hours
    function testFailCheckpointWhenExactly24Hrs() public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        eVFDI.checkpointToken();
        goForward(1 days);
        uint result = eVFDI.startOfWeek(block.timestamp);
        assertEq(result, 2 days);
        vm.expectEmit(false, false, false, true);
        emit CheckpointToken(1 weeks + 1 days + 2, 0);
        eVFDI.checkpointWhenReady();
    }

    /// @notice complete test for when deployed after V2
    function testFuzzDeployedAfterV2(
        uint amount,
        uint staking1,
        uint staking2,
        uint staking3,
        uint time
    ) public {
        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 25_000 ether);
        vm.assume(amount > 10);

        vm.assume(staking1 < 25_000 ether);
        vm.assume(staking1 > 0);

        vm.assume(staking2 < 25_000 ether);
        vm.assume(staking2 > 0);

        vm.assume(staking3 < 25_000 ether);
        vm.assume(staking3 > 0);

        /// @dev this is so we dont get "Cannot claim 0 fees"
        vm.assume(time < 52 weeks);
        uint proportionalFees1 = ((((amount * 1 weeks) / (time + 1 weeks)) *
            staking1) / (staking1 + staking2 + staking3));
        uint proportionalFees2 = ((((amount * 1 weeks) / (time + 1 weeks)) *
            staking2) / (staking1 + staking2 + staking3));
        uint proportionalFees3 = ((((amount * 1 weeks) / (time + 1 weeks)) *
            staking3) / (staking1 + staking2 + staking3));
        vm.assume(proportionalFees1 > 0);
        vm.assume(proportionalFees2 > 0);
        vm.assume(proportionalFees3 > 0);

        kwenta.transfer(address(user1), staking1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), staking1);
        stakingRewardsV2.stake(staking1);
        vm.stopPrank();

        kwenta.transfer(address(user2), staking2);
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), staking2);
        stakingRewardsV2.stake(staking2);
        vm.stopPrank();

        kwenta.transfer(address(user3), staking3);
        vm.startPrank(address(user3));
        kwenta.approve(address(stakingRewardsV2), staking3);
        stakingRewardsV2.stake(staking3);
        vm.stopPrank();

        goForward(3 weeks);

        EarlyVestFeeDistributor earlyVestFeeDistributorOffset = new EarlyVestFeeDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        /// @dev fees received at the start of the epoch (should be + 2 days)
        goForward(2 days - 2);
        earlyVestFeeDistributorOffset.checkpointToken();
        kwenta.transfer(address(earlyVestFeeDistributorOffset), amount);

        /// @dev claim at the start of the new epoch + fuzzed time (should also checkpoint)
        goForward(1 weeks);
        goForward(time);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(5 weeks + 2 days + time, amount);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 1, proportionalFees1);
        earlyVestFeeDistributorOffset.claimEpoch(address(user1), 1);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user2), 1, proportionalFees2);
        earlyVestFeeDistributorOffset.claimEpoch(address(user2), 1);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user3), 1, proportionalFees3);
        earlyVestFeeDistributorOffset.claimEpoch(address(user3), 1);
    }

    /// @notice fuzz offset
    function testFuzzOffset(
        uint amount,
        uint128 staking1,
        uint128 staking2,
        uint8 offset
    ) public {
        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 25_000 ether);
        vm.assume(amount > 10);

        vm.assume(staking1 < 25_000 ether);
        vm.assume(staking1 > 0);

        vm.assume(staking2 < 25_000 ether);
        vm.assume(staking2 > 0);

        /// @dev this is so we dont get "Cannot claim 0 fees"
        vm.assume(amount > staking1 + staking2);
        uint proportionalFees1 = ((((amount * 1 weeks) / (1 weeks)) *
            staking1) / (staking1 + staking2));
        uint proportionalFees2 = ((((amount * 1 weeks) / (1 weeks)) *
            staking2) / (staking1 + staking2));
        vm.assume(proportionalFees1 > 0);
        vm.assume(proportionalFees2 > 0);

        vm.assume(offset < 7);
        vm.assume(offset > 0);

        kwenta.transfer(address(user1), staking1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), staking1);
        stakingRewardsV2.stake(staking1);
        vm.stopPrank();

        kwenta.transfer(address(user2), staking2);
        vm.startPrank(address(user2));
        kwenta.approve(address(stakingRewardsV2), staking2);
        stakingRewardsV2.stake(staking2);
        vm.stopPrank();

        goForward(3 weeks);

        EarlyVestFeeDistributor earlyVestFeeDistributorOffset = new EarlyVestFeeDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            offset
        );

        /// @dev fees received at the start of the epoch
        goForward((offset * 1 days) - 2);
        earlyVestFeeDistributorOffset.checkpointToken();
        kwenta.transfer(address(earlyVestFeeDistributorOffset), amount);

        /// @dev claim at the start of the new epoch (should also checkpoint)
        goForward(1 weeks);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(5 weeks + (offset * 1 days), amount);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 1, proportionalFees1);
        earlyVestFeeDistributorOffset.claimEpoch(address(user1), 1);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user2), 1, proportionalFees2);
        earlyVestFeeDistributorOffset.claimEpoch(address(user2), 1);
    }

    // Test _isEpochActive

    /// @notice current epoch is not ready to claim yet
    function testCurrentEpochNotDoneYet() public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            0
        );
        goForward(.5 weeks);
        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.CannotClaimYet.selector)
        );
        eVFDI.isEpochReady(0);
    }

    /// @notice epoch is not here yet (future)
    function testNotEpochYet() public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            0
        );
        goForward(.5 weeks);
        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.CannotClaimYet.selector)
        );
        eVFDI.isEpochReady(7);
    }

    /// @notice no epochs yet (claim right at deployment)
    function testNoEpochsYet() public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            0
        );
        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.CannotClaimYet.selector)
        );
        eVFDI.isEpochReady(0);
    }

    /// @notice epoch is not ready to claim yet (with offset)
    function testCurrentEpochNotDoneYetWithOffset() public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );
        goForward(2 days - 3);
        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.CannotClaimYet.selector)
        );
        eVFDI.isEpochReady(0);

        goForward(3);
        eVFDI.isEpochReady(0);
    }

    /// @notice fuzz that future epochs are not ready
    function testFuzzEpochsArentReady(uint epochNumber) public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            0
        );
        vm.assume(epochNumber < 1000);
        /// @dev this will forward to the exact week of the epoch
        /// which isn't claimable yet (ongoing)
        goForward(epochNumber * 1 weeks);
        vm.expectRevert(
            abi.encodeWithSelector(IEarlyVestFeeDistributor.CannotClaimYet.selector)
        );
        eVFDI.isEpochReady(epochNumber);
    }

    /// @notice fuzz that future epochs are ready
    function testFuzzIsEpochReady(uint8 epochNumber) public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            0
        );
        /// @dev 75 epochs will already be claimable
        vm.assume(epochNumber < 76);
        goForward(76 weeks);
        eVFDI.isEpochReady(epochNumber);
    }

    /// @notice epochFromTimestamp
    function testEpochFromTimestamp() public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            0
        );

        uint result1 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result1, 0);

        goForward(.5 weeks);
        uint result2 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result2, 0);

        goForward(.5 weeks);
        uint result3 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result3, 1);

        goForward(10 weeks);
        uint result4 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result4, 11);
    }

    /// @notice epochFromTimestamp with offset
    function testEpochFromTimestampOffset() public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        uint result1 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result1, 0);

        /// @dev right at the start of epoch 1
        goForward(2 days - 2);
        uint result2 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result2, 1);

        /// @dev end of a normal week but offset week hasnt ended yet
        goForward(6 days);
        uint result3 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result3, 1);

        goForward(10 weeks);
        uint result4 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result4, 11);
    }

    /// @notice make sure _startOfWeek and _startOfEpoch are always aligned
    function testFuzzStartOfTimeEpoch(uint time) public {
        EarlyVestFeeDistributorInternals eVFDI = new EarlyVestFeeDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );
        vm.assume(time < 1000 weeks);
        goForward(time);
        assertEq(eVFDI.startOfWeek(block.timestamp), eVFDI.startOfEpoch(eVFDI.epochFromTimestamp(block.timestamp)));
    }
}