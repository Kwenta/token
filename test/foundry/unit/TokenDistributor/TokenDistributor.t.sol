// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITokenDistributor} from "../../../../contracts/interfaces/ITokenDistributor.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {RewardEscrowV2} from "../../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";
import {TokenDistributorSetup} from "../../utils/setup/TokenDistributorSetup.t.sol";
import {TokenDistributorInternals} from "../../utils/TokenDistributorInternals.sol";
import {TokenDistributor} from "../../../../contracts/TokenDistributor.sol";

contract TokenDistributorTest is TokenDistributorSetup {
    event CheckpointToken(uint256 time, uint256 tokens);
    event EpochClaim(address user, uint256 epoch, uint256 tokens);

    uint256 startTime;

    function setUp() public override {
        /// @dev starts after a week so the startTime is != 0
        goForward(1 weeks);
        /// @dev set startTime to truncated week for easy testing
        startTime = block.timestamp / 1 weeks * 1 weeks;
        vm.warp(startTime);
        super.setUp();
        vm.prank(treasury);
        kwenta.transfer(address(this), 100_000 ether);
    }

    /// @notice constructor fail when input address == 0
    function testZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.ZeroAddress.selector));
        tokenDistributor = new TokenDistributor(
            address(0),
            address(stakingRewardsV2),
            0
        );
        vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.ZeroAddress.selector));
        tokenDistributor = new TokenDistributor(
            address(kwenta),
            address(0),
            0
        );
    }

    /// @notice checkpointToken happy case after 1 week
    function testCheckpointToken() public {
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        goForward(1 weeks);

        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(startTime + 1 weeks, 10);
        tokenDistributor.checkpointToken();
    }

    /// @notice checkpointToken for missed weeks
    function testCheckpointTokenManyMissed() public {
        kwenta.transfer(address(tokenDistributor), 10);
        goForward(5 weeks);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(startTime + 5 weeks, 10);
        tokenDistributor.checkpointToken();
    }

    /// @notice checkpointToken for sinceLast == 0
    function testManyCheckpointTokenAtOnce() public {
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        goForward(1 weeks);

        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(startTime + 1 weeks, 10);
        tokenDistributor.checkpointToken();
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(startTime + 1 weeks, 0);
        tokenDistributor.checkpointToken();
    }

    /// @notice checkpoint at the start and < 1 week
    /// make sure theres no error dividing by 0
    /// because thisEpoch should be 0
    function testCheckpointTokenFirstWeek() public {
        tokenDistributor.checkpointToken();
        goForward(1 days);
        tokenDistributor.checkpointToken();
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

        kwenta.transfer(address(tokenDistributor), 10);
        goForward(1 weeks);

        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(startTime + 2 weeks, 10);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 1, 5);
        tokenDistributor.claimEpoch(address(user1), 1);
        assertEq(kwenta.balanceOf(address(user1)), 5);
    }

    /// @notice make sure the proper vesting entry is created
    /// @dev must be the same as rewardEscrowV2 default constants
    function testClaimEpochVestingEntry() public {
        //setup
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        goForward(1 weeks);

        kwenta.transfer(address(tokenDistributor), 10);
        goForward(1 weeks);

        tokenDistributor.claimEpoch(address(user1), 1);
        assertEq(kwenta.balanceOf(address(user1)), 5);
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

        TokenDistributor tokenDistributorOffset = new TokenDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            2
        );

        tokenDistributorOffset.checkpointToken();
        kwenta.transfer(address(tokenDistributorOffset), 10);
        /// @dev forward to the exact end of epoch 0 and start of 1
        goForward(2 days);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 0, 2);
        tokenDistributorOffset.claimEpoch(address(user1), 0);
        assertEq(kwenta.balanceOf(address(user1)), 2);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user2), 0, 2);
        tokenDistributorOffset.claimEpoch(address(user2), 0);
        assertEq(kwenta.balanceOf(address(user2)), 2);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user3), 0, 6);
        tokenDistributorOffset.claimEpoch(address(user3), 0);
        assertEq(kwenta.balanceOf(address(user3)), 6);
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

        TokenDistributor tokenDistributorOffset = new TokenDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            2
        );

        tokenDistributorOffset.checkpointToken();
        kwenta.transfer(address(tokenDistributorOffset), 10);
        /// @dev forward to the exact end of epoch 0 and start of 1
        goForward(2 days);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 0, 10);
        tokenDistributorOffset.claimEpoch(address(user1), 0);
        assertEq(kwenta.balanceOf(address(user1)), 10);
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
        goForward(1 weeks);

        /// @dev checkpoint just before the week ends
        kwenta.transfer(address(tokenDistributor), 10);
        goForward(1 weeks - 4800);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(startTime + 2 weeks - 4800, 10);
        tokenDistributor.checkpointToken();
        kwenta.transfer(address(tokenDistributor), 5);
        goForward(4801);

        /// @dev make sure a claim at the turn of the week
        /// will checkpoint even if its < 24 hours
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(startTime + 2 weeks + 1, 5);
        tokenDistributor.claimEpoch(address(user1), 1);
        assertEq(kwenta.balanceOf(address(user1)), 2);

        uint256 lastCheckpoint = tokenDistributor.lastCheckpoint();

        /// @dev a claim < 24 hours and not the first one
        /// of the week will not checkpoint which is correct
        goForward(1000);
        tokenDistributor.claimEpoch(address(user2), 1);
        assertEq(tokenDistributor.lastCheckpoint(), lastCheckpoint);
    }

    /// @notice claimEpoch fail - epoch is not ready to claim
    function testClaimEpochNotReady() public {
        vm.startPrank(user1);

        goForward(0.5 weeks);
        vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.CannotClaimYet.selector));
        tokenDistributor.claimEpoch(address(user1), 0);
    }

    /// @notice claimEpoch fail - epoch is not ready to claim, not an epoch yet
    function testClaimEpochAhead() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.CannotClaimYet.selector));
        tokenDistributor.claimEpoch(address(user1), 7);
    }

    /// @notice claimEpoch fail - no epoch to claim yet
    function testClaimNoEpochYet() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.CannotClaimYet.selector));
        tokenDistributor.claimEpoch(address(user1), 0);
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
        kwenta.transfer(address(tokenDistributor), 10);
        goForward(1 weeks);
        tokenDistributor.claimEpoch(address(user1), 1);

        vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.CannotClaimTwice.selector));
        tokenDistributor.claimEpoch(address(user1), 1);
    }

    /// @notice claimEpoch fail - claim an epoch that had no staking
    function testClaimNoStaking() public {
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user1), 1);
        vm.startPrank(user1);
        goForward(1 weeks);
        vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.CannotClaim0Fees.selector));
        tokenDistributor.claimEpoch(address(user1), 0);
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
        kwenta.transfer(address(tokenDistributor), 10);
        goForward(1 weeks);

        tokenDistributor.claimEpoch(address(user1), 1);
        vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.CannotClaim0Fees.selector));
        tokenDistributor.claimEpoch(address(user2), 1);
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
        kwenta.transfer(address(tokenDistributor), 10);
        goForward(1 weeks);

        vm.prank(address(user1));
        stakingRewardsV2.unstake(1);
        goForward(2 weeks);
        tokenDistributor.claimEpoch(address(user1), 1);
        assertEq(kwenta.balanceOf(address(user1)), 3);
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
        goForward(304_801);
        kwenta.transfer(address(tokenDistributor), 1000);
        tokenDistributor.checkpointToken();
        goForward(1 weeks);

        uint256 sum = tokenDistributor.calculateEpochFees(user1, 1);
        assertEq(sum, 111);
    }

    /// @notice fuzz calculateEpochFees, especially when checkpoints are across weeks
    function testFuzzCalculateEpochFees(uint256 amount) public {
        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 100_000 ether - 3);
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
        goForward(1 weeks);

        /// @dev send fees to TokenDistributor midway through epoch 1
        /// this will be split between all of epoch 0 and half of 1
        goForward(0.5 weeks);
        kwenta.transfer(address(tokenDistributor), amount);
        uint256 timeSinceLastCheckpoint = block.timestamp - startTime;
        tokenDistributor.checkpointToken();

        uint256 result = tokenDistributor.calculateEpochFees(address(user2), 1);
        /// @dev calculate the proportion for this week (same as checkpoint math)
        /// then get the proportion staked (2/3)
        assertEq(result, (((amount * 0.5 weeks) / timeSinceLastCheckpoint) * 2) / 3);
    }

    /// @notice fuzz calculateEpochFees, especially for when multiple weeks are missed
    function testFuzzCalculateMultipleWeeksMissed(uint256 amount) public {
        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 100_000 ether - 3);
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
        goForward(1 weeks);

        /// @dev send fees to TokenDistributor midway through epoch 3
        /// this will be split between epochs 0 - 3.5
        goForward(2.5 weeks);
        kwenta.transfer(address(tokenDistributor), amount);
        tokenDistributor.checkpointToken();

        uint256 result = tokenDistributor.calculateEpochFees(address(user2), 1);
        /// @dev calculate the proportion for this week (same as checkpoint math)
        /// then get the proportion staked (2/3)
        assertEq(result, (((amount * 1 weeks) / 3.5 weeks) * 2) / 3);
    }

    /// @notice fuzz calculateEpochFees, when staking amounts are random
    function testFuzzStakingCalculateEpochFees(uint256 amount, uint256 staking1, uint256 staking2)
        public
    {
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
        goForward(1 weeks);

        /// @dev send fees to TokenDistributor midway through epoch 1
        /// this will be split between all of epoch 0 and half of 1
        goForward(0.5 weeks);
        kwenta.transfer(address(tokenDistributor), amount);
        uint256 timeSinceLastCheckpoint = block.timestamp - startTime;
        tokenDistributor.checkpointToken();

        uint256 result = tokenDistributor.calculateEpochFees(address(user2), 1);
        /// @dev calculate the proportion for this week (same as checkpoint math)
        /// then get the proportion staked
        assertEq(
            result,
            (((amount * 0.5 weeks) / timeSinceLastCheckpoint) * staking2) / (staking1 + staking2)
        );
    }

    /// @notice fuzz calculateEpochFees, fuzz the time until they checkpoint
    function testFuzzCalculateMultipleWeeksMissed(uint256 amount, uint256 time) public {
        /// @dev make sure its less than this contract
        /// holds and greater than 10 so the result isn't
        /// 0 after dividing
        vm.assume(amount < 100_000 ether - 3);
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
        goForward(1 weeks);

        /// @dev send fees to TokenDistributor
        goForward(1 weeks);
        goForward(time);
        kwenta.transfer(address(tokenDistributor), amount);
        tokenDistributor.checkpointToken();

        uint256 result = tokenDistributor.calculateEpochFees(address(user2), 1);
        /// @dev calculate the proportion for this week (same as checkpoint math)
        /// then get the proportion staked (2/3)
        assertEq(result, (((amount * 1 weeks) / (time + 2 weeks)) * 2) / 3);
    }

    /// @notice test calculate epoch fees for returning 0
    /// when total staked == 0
    function testCalculateEpochFees0() public {
        uint256 result = tokenDistributor.calculateEpochFees(address(user1), 1);
        assertEq(result, 0);
    }

    /// @notice test claimedEpoch with epoch not claimed
    function testClaimedEpochNotClaimYet() public {
        assertEq(tokenDistributor.claimedEpoch(address(user1), 0), false);
    }

    /// @notice test claimedEpoch happy case
    function testClaimedEpoch() public {
        //setup
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        goForward(1 weeks);
        kwenta.transfer(address(tokenDistributor), 10);
        goForward(1 weeks);

        tokenDistributor.claimEpoch(address(user1), 1);

        assertEq(tokenDistributor.claimedEpoch(address(user1), 1), true);
    }

    /// @notice claimEpoch happy case with partial claims
    /// in earlier epochs 2 complete epochs with differing fees
    /// @dev also an integration test with RewardEscrowV2
    function testClaimFourIndividualClaims() public {
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
        /// midway through epoch #1 TokenDistributor
        /// receives 1000 in fees and checkpoints
        /// (this is split up between epoch 0 and 1)
        goForward(304_801);
        kwenta.transfer(address(tokenDistributor), 1000);
        tokenDistributor.checkpointToken();
        goForward(1 weeks + 1);

        /// @dev during epoch #2, user1 claims their fees from #1
        /// and TokenDistributor receives 5000 in fees
        vm.prank(user1);
        tokenDistributor.claimEpoch(address(user1), 1);
        assertEq(kwenta.balanceOf(address(user1)), 111);
        kwenta.transfer(address(tokenDistributor), 5000);

        /// @dev At the start of epoch #3 user1 claims for epoch #2
        /// user2 also claims for #2 and #1
        /// and TokenDistributor receives 300 in fees
        goForward(304_801);
        vm.prank(user1);
        tokenDistributor.claimEpoch(address(user1), 2);
        assertEq(kwenta.balanceOf(address(user1)), 1751);
        goForward(1000);
        kwenta.transfer(address(tokenDistributor), 300);
        vm.prank(user2);
        tokenDistributor.claimEpoch(address(user2), 2);
        assertEq(kwenta.balanceOf(address(user2)), 3280);
        vm.prank(user2);
        tokenDistributor.claimEpoch(address(user2), 1);
        assertEq(kwenta.balanceOf(address(user2)), 3503);
    }

    /// @notice test claimMany
    function testClaimManyOnce() public {
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();

        goForward(1.5 weeks);
        kwenta.transfer(address(tokenDistributor), 1000);
        tokenDistributor.checkpointToken();
        goForward(1 weeks);

        kwenta.transfer(address(tokenDistributor), 5000);
        goForward(1 weeks);

        uint256[] memory epochs = new uint[](2);
        epochs[0] = 1;
        epochs[1] = 2;
        assertEq(kwenta.balanceOf(address(user1)), 0);
        assertEq(kwenta.balanceOf(address(tokenDistributor)), 6000);
        tokenDistributor.claimMany(address(user1), epochs);
        assertEq(kwenta.balanceOf(address(user1)), 4083);
        assertEq(kwenta.balanceOf(address(tokenDistributor)), 1917);
    }

    /// @notice test claimMany fail (one epoch cant be claimed)
    function testFailClaimMany() public {
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();

        goForward(1.5 weeks);
        kwenta.transfer(address(tokenDistributor), 1000);
        tokenDistributor.checkpointToken();
        goForward(1 weeks);

        kwenta.transfer(address(tokenDistributor), 5000);
        goForward(1 weeks);

        uint256[] memory epochs = new uint[](2);
        epochs[0] = 1;
        epochs[1] = 2;
        epochs[2] = 3;
        tokenDistributor.claimMany(address(user1), epochs);
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
        goForward(1 weeks);
        tokenDistributor.checkpointToken();

        /// @dev send fees to TokenDistributor 1 second before
        /// epoch 1 ends
        goForward(1 weeks - 1);
        kwenta.transfer(address(tokenDistributor), amount);
        tokenDistributor.checkpointToken();
        goForward(1);

        /// @dev claim for epoch 1 at the first second of epoch 2
        vm.prank(user1);
        tokenDistributor.claimEpoch(address(user1), 1);
        assertEq(kwenta.balanceOf(address(user1)), amount / 3);
    }

    /// @notice fuzz claimEpochFees, fuzz staking
    function testFuzzStakingClaim(uint256 amount, uint256 staking1, uint256 staking2) public {
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
        goForward(1 weeks);
        tokenDistributor.checkpointToken();

        /// @dev send fees to TokenDistributor 1 second before
        /// epoch 1 ends
        goForward(1 weeks - 1);
        kwenta.transfer(address(tokenDistributor), amount);
        tokenDistributor.checkpointToken();
        goForward(1);

        /// @dev claim for epoch 1 at the first second of epoch 2
        vm.prank(user1);
        tokenDistributor.claimEpoch(address(user1), 1);
        assertEq(kwenta.balanceOf(address(user1)), (amount * staking1) / (staking1 + staking2));
    }

    /// @notice fuzz claimEpochFees, fuzz time
    function testFuzzTimeClaim(uint256 amount, uint256 staking1, uint256 staking2, uint256 time)
        public
    {
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
        uint256 proportionalFees =
            (((amount * 1 weeks) / (time + 1 weeks)) * staking1) / (staking1 + staking2);
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
        goForward(1 weeks);
        tokenDistributor.checkpointToken();

        /// @dev send fees to TokenDistributor 1 second before
        /// epoch 1 ends
        goForward(1 weeks - 1);
        kwenta.transfer(address(tokenDistributor), amount);
        goForward(1);
        goForward(time);

        /// @dev claim for epoch 1 at the first second of epoch 2
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit EpochClaim(address(user1), 1, proportionalFees);
        tokenDistributor.claimEpoch(address(user1), 1);
        assertEq(kwenta.balanceOf(address(user1)), proportionalFees);
    }

    /// @notice fuzz claimEpochFees, fuzz time with a random start
    /// (when the distributor does not start right at a truncated week)
    function testFuzzTimeClaimWithRandomStart(
        uint256 amount,
        uint128 staking1,
        uint128 staking2,
        uint128 time,
        uint128 randomStart
    ) public {
        vm.assume(time > 0);
        vm.assume(randomStart > 0);
        vm.assume(randomStart < 1 weeks);
        goForward(randomStart);
        TokenDistributor tokenDistributorRandom = new TokenDistributor(
                address(kwenta),
                address(stakingRewardsV2),
                0
        );

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
        uint256 proportionalFees =
            (((amount * 1 weeks) / (time + randomStart)) * staking1) / (staking1 + staking2);
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

        /// @dev forward a random amount of time
        goForward(time);
        kwenta.transfer(address(tokenDistributorRandom), amount);

        /// @dev this is so we dont get "Cannot claim yet"
        /// cannot claim epoch 1 until 2 weeks has passed
        if (randomStart + time < 2 weeks) {
            vm.prank(user1);
            vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.CannotClaimYet.selector));
            tokenDistributorRandom.claimEpoch(address(user1), 1);
        } else {
            vm.prank(user1);
            vm.expectEmit(true, true, true, true);
            emit EpochClaim(address(user1), 1, proportionalFees);
            tokenDistributorRandom.claimEpoch(address(user1), 1);
            assertEq(kwenta.balanceOf(address(user1)), proportionalFees);
        }
    }

    /// @notice test everything with a custom offset
    function testOffset() public {
        TokenDistributor tokenDistributorOffset = new TokenDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            2
        );

        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();

        /// @dev fees received at the start of the epoch (should be + 2 days)
        goForward(2 days);
        kwenta.transfer(address(tokenDistributorOffset), 100);

        /// @dev checkpoint token < 24 hours before epoch end
        goForward(1 weeks - 4800);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(startTime + 1 weeks + 2 days - 4800, 100);
        tokenDistributorOffset.checkpointToken();
        kwenta.transfer(address(tokenDistributorOffset), 5);
        goForward(4801);

        /// @dev claim at the start of the new epoch (should also checkpoint)
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(startTime + 1 weeks + 2 days + 1, 5);
        tokenDistributorOffset.claimEpoch(address(user1), 1);
        assertEq(kwenta.balanceOf(address(user1)), 53);

        /// @dev user2 cant claim because they didnt stake
        vm.expectRevert();
        tokenDistributorOffset.claimEpoch(address(user2), 1);
    }

    /// @notice test fuzz fees with a custom offset
    function testFuzzFeesOffset(uint256 amount) public {
        TokenDistributor tokenDistributorOffset = new TokenDistributor(
            address(kwenta),
            address(stakingRewardsV2),
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
        goForward(2 days);
        tokenDistributorOffset.checkpointToken();
        kwenta.transfer(address(tokenDistributorOffset), amount);

        /// @dev claim at the start of the new epoch (should also checkpoint)
        goForward(1 weeks);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(startTime + 1 weeks + 2 days, amount);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 1, amount);
        tokenDistributorOffset.claimEpoch(address(user1), 1);
    }

    /// @notice test fuzz staking with a custom offset
    function testFuzzStakingOffset(
        uint256 amount,
        uint256 staking1,
        uint256 staking2,
        uint256 staking3
    ) public {
        TokenDistributor tokenDistributorOffset = new TokenDistributor(
            address(kwenta),
            address(stakingRewardsV2),
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

        uint256 proportionalFees1 = (amount * staking1) / (staking1 + staking2 + staking3);
        uint256 proportionalFees2 = (amount * staking2) / (staking1 + staking2 + staking3);
        uint256 proportionalFees3 = (amount * staking3) / (staking1 + staking2 + staking3);
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
        goForward(2 days);
        tokenDistributorOffset.checkpointToken();
        kwenta.transfer(address(tokenDistributorOffset), amount);

        /// @dev claim at the start of the new epoch (should also checkpoint)
        goForward(1 weeks);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(startTime + 1 weeks + 2 days, amount);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 1, proportionalFees1);
        tokenDistributorOffset.claimEpoch(address(user1), 1);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user2), 1, proportionalFees2);
        tokenDistributorOffset.claimEpoch(address(user2), 1);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user3), 1, proportionalFees3);
        tokenDistributorOffset.claimEpoch(address(user3), 1);
    }

    /// @notice test fuzz time with a custom offset
    function testFuzzTimeOffset(
        uint256 amount,
        uint256 staking1,
        uint256 staking2,
        uint256 staking3,
        uint256 time
    ) public {
        TokenDistributor tokenDistributorOffset = new TokenDistributor(
            address(kwenta),
            address(stakingRewardsV2),
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
        uint256 proportionalFees1 = (
            (((amount * 1 weeks) / (time + 1 weeks)) * staking1) / (staking1 + staking2 + staking3)
        );
        uint256 proportionalFees2 = (
            (((amount * 1 weeks) / (time + 1 weeks)) * staking2) / (staking1 + staking2 + staking3)
        );
        uint256 proportionalFees3 = (
            (((amount * 1 weeks) / (time + 1 weeks)) * staking3) / (staking1 + staking2 + staking3)
        );
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
        goForward(2 days);
        tokenDistributorOffset.checkpointToken();
        kwenta.transfer(address(tokenDistributorOffset), amount);

        /// @dev claim at the start of the new epoch (should also checkpoint)
        goForward(1 weeks);
        goForward(time);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(startTime + 1 weeks + 2 days + time, amount);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 1, proportionalFees1);
        tokenDistributorOffset.claimEpoch(address(user1), 1);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user2), 1, proportionalFees2);
        tokenDistributorOffset.claimEpoch(address(user2), 1);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user3), 1, proportionalFees3);
        tokenDistributorOffset.claimEpoch(address(user3), 1);
    }

    /// @notice test startOfWeek
    function testStartOfWeek() public {
        TokenDistributorInternals tokenDistributorOffset = new TokenDistributorInternals(
                address(kwenta),
                address(stakingRewardsV2),
                2
            );

        /// @dev normally the start of the week would be StartTime but offset of 2
        /// makes it it StartTime - 5 days (Last week + 2 days)
        /// @note the current timestamp is StartTime but the start of the OFFSET week
        /// was 5 days ago (2 days past the last week)
        uint256 result = tokenDistributorOffset.startOfWeek(block.timestamp);
        assertEq(result, startTime - 5 days);

        goForward(2 days);
        uint256 result2 = tokenDistributorOffset.startOfWeek(block.timestamp);
        assertEq(result2, startTime + 2 days);

        /// @dev this should be passed a normal week but just before the offset
        /// week so nothing should change
        goForward(0.9 weeks);
        uint256 result3 = tokenDistributorOffset.startOfWeek(block.timestamp);
        assertEq(result3, startTime + 2 days);

        /// @dev this is a few hundred seconds into a new offset week so should
        /// be a different start time
        goForward(0.1 weeks);
        uint256 result4 = tokenDistributorOffset.startOfWeek(block.timestamp);
        assertEq(result4, startTime + 1 weeks + 2 days);
    }

    /// @notice test startOfWeek exactly at the turn of the week
    function testExactlyStartOfWeek() public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            0
        );
        uint256 result1 = eVFDI.startOfWeek(block.timestamp);
        assertEq(result1, startTime);

        /// @dev this is 1 second before the turn of the week
        goForward(1 weeks - 1);
        uint256 result2 = eVFDI.startOfWeek(block.timestamp);
        assertEq(result2, startTime);

        /// @dev this is the first second of week 2
        goForward(1);
        uint256 result3 = eVFDI.startOfWeek(block.timestamp);
        assertEq(result3, startTime + 1 weeks);
    }

    /// @notice test claiming an unready epoch with an offset
    function testCannotClaimYetOffset() public {
        TokenDistributorInternals tokenDistributorOffset = new TokenDistributorInternals(
                address(kwenta),
                address(stakingRewardsV2),
                2
            );

        vm.startPrank(user1);

        /// @dev this goForward gets it right before the offset week changes
        /// but a regular week has already changed. claim should revert because
        /// it is offset and still not ready to claim
        goForward(2 days - 1);
        uint256 result = tokenDistributorOffset.startOfWeek(block.timestamp);
        assertEq(result, startTime - 5 days);
        vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.CannotClaimYet.selector));
        tokenDistributorOffset.claimEpoch(address(user1), 0);
    }

    /// @notice test _startOfEpoch so that it follows an offset like _startOfWeek
    function testStartOfEpoch() public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            2
        );

        assertEq(eVFDI.startOfWeek(block.timestamp), eVFDI.startOfEpoch(0));

        goForward(2 days);

        assertEq(eVFDI.startOfWeek(block.timestamp), eVFDI.startOfEpoch(1));
    }

    // Test _checkpointWhenReady

    /// @notice test _checkpointWhenReady for when its < 24 hrs and not a new week
    function testFailCheckpointWhenNotReady() public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
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
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            2
        );

        goForward(1 days + 1);
        uint256 result = eVFDI.startOfWeek(block.timestamp);
        assertEq(result, startTime - 5 days);
        vm.expectEmit(false, false, false, true);
        emit CheckpointToken(startTime + 1 days + 1, 0);
        eVFDI.checkpointWhenReady();
    }

    /// @notice test _checkpointWhenReady for when its > 24 hrs and is new week
    function testCheckpointWhen24hrsAndNewWeek() public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            2
        );

        uint256 result = eVFDI.startOfWeek(block.timestamp);
        assertEq(result, startTime - 5 days);

        goForward(5 days);
        uint256 result2 = eVFDI.startOfWeek(block.timestamp);
        assertEq(result2, startTime + 2 days);
        vm.expectEmit(false, false, false, true);
        emit CheckpointToken(startTime + 5 days, 0);
        eVFDI.checkpointWhenReady();
    }

    /// @notice test _checkpointWhenReady for when its < 24 hrs and is new week
    function testCheckpointWhenReadyNewWeek() public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            2
        );

        goForward(1.5 days);
        uint256 result = eVFDI.startOfWeek(block.timestamp);
        assertEq(result, startTime - 5 days);
        eVFDI.checkpointToken();

        goForward(0.9 days);
        uint256 result2 = eVFDI.startOfWeek(block.timestamp);
        assertEq(result2, startTime + 2 days);
        vm.expectEmit(false, false, false, true);
        emit CheckpointToken(startTime + 2.4 days, 0);
        eVFDI.checkpointWhenReady();
    }

    /// @notice test fail _checkpointWhenReady for when its been exactly 24 hours
    function testFailCheckpointWhenExactly24Hrs() public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            2
        );

        eVFDI.checkpointToken();
        goForward(1 days);
        uint256 result = eVFDI.startOfWeek(block.timestamp);
        assertEq(result, startTime - 5 days);
        vm.expectEmit(false, false, false, true);
        emit CheckpointToken(startTime + 1 days, 0);
        eVFDI.checkpointWhenReady();
    }

    /// @notice complete test for when deployed after V2
    function testFuzzDeployedAfterV2(
        uint256 amount,
        uint256 staking1,
        uint256 staking2,
        uint256 staking3,
        uint256 time
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
        uint256 proportionalFees1 = (
            (((amount * 1 weeks) / (time + 1 weeks)) * staking1) / (staking1 + staking2 + staking3)
        );
        uint256 proportionalFees2 = (
            (((amount * 1 weeks) / (time + 1 weeks)) * staking2) / (staking1 + staking2 + staking3)
        );
        uint256 proportionalFees3 = (
            (((amount * 1 weeks) / (time + 1 weeks)) * staking3) / (staking1 + staking2 + staking3)
        );
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

        TokenDistributor tokenDistributorOffset = new TokenDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            2
        );

        /// @dev fees received at the start of the epoch (should be + 2 days)
        goForward(2 days);
        tokenDistributorOffset.checkpointToken();
        kwenta.transfer(address(tokenDistributorOffset), amount);

        /// @dev claim at the start of the new epoch + fuzzed time (should also checkpoint)
        goForward(1 weeks);
        goForward(time);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(startTime + 4 weeks + 2 days + time, amount);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 1, proportionalFees1);
        tokenDistributorOffset.claimEpoch(address(user1), 1);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user2), 1, proportionalFees2);
        tokenDistributorOffset.claimEpoch(address(user2), 1);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user3), 1, proportionalFees3);
        tokenDistributorOffset.claimEpoch(address(user3), 1);
    }

    /// @notice fuzz offset
    function testFuzzOffset(uint256 amount, uint128 staking1, uint128 staking2, uint8 offset)
        public
    {
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
        uint256 proportionalFees1 =
            ((((amount * 1 weeks) / (1 weeks)) * staking1) / (staking1 + staking2));
        uint256 proportionalFees2 =
            ((((amount * 1 weeks) / (1 weeks)) * staking2) / (staking1 + staking2));
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

        TokenDistributor tokenDistributorOffset = new TokenDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            offset
        );

        /// @dev fees received at the start of the epoch
        goForward((offset * 1 days));
        tokenDistributorOffset.checkpointToken();
        kwenta.transfer(address(tokenDistributorOffset), amount);

        /// @dev claim at the start of the new epoch (should also checkpoint)
        goForward(1 weeks);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(startTime + 1 weeks + (offset * 1 days), amount);
        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user1), 1, proportionalFees1);
        tokenDistributorOffset.claimEpoch(address(user1), 1);

        vm.expectEmit(true, true, true, true);
        emit EpochClaim(address(user2), 1, proportionalFees2);
        tokenDistributorOffset.claimEpoch(address(user2), 1);
    }

    // Test _isEpochActive

    /// @notice current epoch is not ready to claim yet
    function testCurrentEpochNotDoneYet() public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            0
        );
        goForward(0.5 weeks);
        vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.CannotClaimYet.selector));
        eVFDI.isEpochReady(0);
    }

    /// @notice epoch is not here yet (future)
    function testNotEpochYet() public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            0
        );
        goForward(0.5 weeks);
        vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.CannotClaimYet.selector));
        eVFDI.isEpochReady(7);
    }

    /// @notice no epochs yet (claim right at deployment)
    function testNoEpochsYet() public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            0
        );
        vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.CannotClaimYet.selector));
        eVFDI.isEpochReady(0);
    }

    /// @notice epoch is not ready to claim yet (with offset)
    function testCurrentEpochNotDoneYetWithOffset() public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            2
        );
        goForward(2 days - 3);
        vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.CannotClaimYet.selector));
        eVFDI.isEpochReady(0);

        goForward(3);
        eVFDI.isEpochReady(0);
    }

    /// @notice fuzz that future epochs are not ready
    function testFuzzEpochsArentReady(uint256 epochNumber) public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            0
        );
        vm.assume(epochNumber < 1000);
        /// @dev this will forward to the exact week of the epoch
        /// which isn't claimable yet (ongoing)
        goForward(epochNumber * 1 weeks);
        vm.expectRevert(abi.encodeWithSelector(ITokenDistributor.CannotClaimYet.selector));
        eVFDI.isEpochReady(epochNumber);
    }

    /// @notice fuzz that future epochs are ready
    function testFuzzIsEpochReady(uint8 epochNumber) public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            0
        );
        /// @dev 75 epochs will already be claimable
        vm.assume(epochNumber < 76);
        goForward(76 weeks);
        eVFDI.isEpochReady(epochNumber);
    }

    /// @notice epochFromTimestamp
    function testEpochFromTimestamp() public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            0
        );

        uint256 result1 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result1, 0);

        goForward(0.5 weeks);
        uint256 result2 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result2, 0);

        goForward(0.5 weeks);
        uint256 result3 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result3, 1);

        goForward(10 weeks);
        uint256 result4 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result4, 11);
    }

    /// @notice epochFromTimestamp with offset
    function testEpochFromTimestampOffset() public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            2
        );

        uint256 result1 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result1, 0);

        /// @dev right at the start of epoch 1
        goForward(2 days);
        uint256 result2 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result2, 1);

        /// @dev end of a normal week but offset week hasnt ended yet
        goForward(6 days);
        uint256 result3 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result3, 1);

        /// @dev turn over into a new offset week
        goForward(2 days);
        uint256 result4 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result4, 2);

        goForward(10 weeks);
        uint256 result5 = eVFDI.epochFromTimestamp(block.timestamp);
        assertEq(result5, 12);
    }

    /// @notice make sure _startOfWeek and _startOfEpoch are always aligned
    function testFuzzStartOfTimeEpoch(uint256 time) public {
        TokenDistributorInternals eVFDI = new TokenDistributorInternals(
            address(kwenta),
            address(stakingRewardsV2),
            2
        );
        vm.assume(time < 1000 weeks);
        goForward(time);
        assertEq(
            eVFDI.startOfWeek(block.timestamp),
            eVFDI.startOfEpoch(eVFDI.epochFromTimestamp(block.timestamp))
        );
    }
}
