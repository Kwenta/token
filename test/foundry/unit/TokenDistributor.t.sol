// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TokenDistributor} from "../../../contracts/TokenDistributor.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {StakingSetup} from "../utils/StakingSetup.t.sol";

contract TokenDistributorTest is StakingSetup {
    event CheckpointToken(uint time, uint tokens);
    event VestingEntryCreated(
        address indexed beneficiary,
        uint256 value,
        uint256 duration,
        uint256 entryID
    );

    TokenDistributor public tokenDistributor;

    function setUp() public override {
        /// @dev starts after a week so the startTime is != 0
        goForward(604801);
        super.setUp();
        switchToStakingV2();
        tokenDistributor = new TokenDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            0
        );
        vm.prank(treasury);
        kwenta.transfer(address(this), 100_000 ether);
    }

    /// @notice checkpointToken happy case after 1 week
    function testCheckpointToken() public {
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        goForward(604801);

        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1209603, 10);
        tokenDistributor.checkpointToken();
    }

    //todo: test checkpointing in more cases, look at velo or curve
    // take their tests and convert it to forge

    /// @notice claimEpoch happy case
    function testClaimEpoch() public {
        //setup
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        goForward(604801);

        kwenta.transfer(address(tokenDistributor), 10);
        goForward(604801);

        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1814404, 10);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), 4, 31449600, 1);
        tokenDistributor.claimEpoch(address(user1), 1);
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
        goForward(604801);

        /// @dev checkpoint just before the week ends
        kwenta.transfer(address(tokenDistributor), 10);
        goForward(600000);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1809603, 10);
        tokenDistributor.checkpointToken();
        kwenta.transfer(address(tokenDistributor), 5);
        goForward(4801);

        /// @dev make sure a claim at the turn of the week
        /// will checkpoint even if its < 24 hours
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1814404, 5);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), 2, 31449600, 1);
        tokenDistributor.claimEpoch(address(user1), 1);

        /// @dev a claim < 24 hours and not the first one
        /// of the week will not checkpoint which is correct
        goForward(1000);
        tokenDistributor.claimEpoch(address(user2), 1);
    }

    /// @notice claimEpoch fail - epoch is not ready to claim
    function testClaimEpochNotReady() public {
        vm.startPrank(user1);

        goForward(304801);
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributor.CannotClaimYet.selector)
        );
        tokenDistributor.claimEpoch(address(user1), 0);
    }

    /// @notice claimEpoch fail - epoch is not ready to claim, not an epoch yet
    function testClaimEpochAhead() public {
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributor.CannotClaimYet.selector)
        );
        tokenDistributor.claimEpoch(address(user1), 7);
    }

    /// @notice claimEpoch fail - no epoch to claim yet
    function testClaimNoEpochYet() public {
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributor.CannotClaimYet.selector)
        );
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
        goForward(604801);
        kwenta.transfer(address(tokenDistributor), 10);
        goForward(604801);
        tokenDistributor.claimEpoch(address(user1), 1);

        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributor.CannotClaimTwice.selector)
        );
        tokenDistributor.claimEpoch(address(user1), 1);
    }

    /// @notice claimEpoch fail - claim an epoch that had no staking
    function testClaimNoStaking() public {
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user1), 1);
        vm.startPrank(user1);
        goForward(604801);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenDistributor.NothingStakedThatEpoch.selector
            )
        );
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
        goForward(604801);
        kwenta.transfer(address(tokenDistributor), 10);
        goForward(604801);

        tokenDistributor.claimEpoch(address(user1), 1);
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributor.CannotClaim0Fees.selector)
        );
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
        goForward(604801);
        kwenta.transfer(address(tokenDistributor), 10);
        goForward(604801);

        vm.prank(address(user1));
        stakingRewardsV2.unstake(1);
        goForward(604801);
        goForward(604801);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), 2, 31449600, 1);
        tokenDistributor.claimEpoch(address(user1), 1);
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

        goForward(604801);
        /// @dev forward half a week so it puts fees in epoch 1
        goForward(304801);
        kwenta.transfer(address(tokenDistributor), 1000);
        tokenDistributor.checkpointToken();
        goForward(604801);

        uint256 sum = tokenDistributor.calculateEpochFees(user1, 1);
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
        goForward(604798);

        /// @dev send fees to TokenDistributor midway through epoch 1
        /// this will be split between all of epoch 0 and half of 1
        goForward(302400);
        kwenta.transfer(address(tokenDistributor), amount);
        uint256 timeSinceLastCheckpoint = block.timestamp - 604800;
        tokenDistributor.checkpointToken();

        uint256 result = tokenDistributor.calculateEpochFees(address(user2), 1);
        /// @dev calculate the proprtion for this week (same as checkpoint math)
        /// then get the proportion staked (2/3)
        assertEq(
            result,
            (((amount * 302400) / timeSinceLastCheckpoint) * 2) / 3
        );
    }

    //todo: next level fuzz: fuzz the amount that they stake, and fuzz the users, fuzz the time

    //todo: double check if multiple weeks are missed

    /// @notice test calculate epoch fees for returning 0
    /// when total staked == 0
    function testCalculateEpochFees0() public {
        uint256 result = tokenDistributor.calculateEpochFees(address(user1), 1);
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
        goForward(604801);

        /// @notice start of epoch 1
        /// midway through epoch #1 TokenDistributor
        /// receives 1000 in fees and checkpoints
        /// (this is split up between epoch 0 and 1)
        goForward(304801);
        kwenta.transfer(address(tokenDistributor), 1000);
        tokenDistributor.checkpointToken();
        goForward(604801);

        /// @dev during epoch #2, user1 claims their fees from #1
        /// and TokenDistributor receives 5000 in fees
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), 111, 31449600, 1);
        tokenDistributor.claimEpoch(address(user1), 1);
        kwenta.transfer(address(tokenDistributor), 5000);

        /// @dev At the start of epoch #3 user1 claims for epoch #2
        /// user2 also claims for #2 and #1
        /// and TokenDistributor receives 300 in fees
        goForward(304801);
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), 1640, 31449600, 2);
        tokenDistributor.claimEpoch(address(user1), 2);
        goForward(1000);
        kwenta.transfer(address(tokenDistributor), 300);
        vm.prank(user2);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user2), 3280, 31449600, 3);
        tokenDistributor.claimEpoch(address(user2), 2);
        vm.prank(user2);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user2), 223, 31449600, 4);
        tokenDistributor.claimEpoch(address(user2), 1);
    }

    /// @notice test claimMany
    function testClaimMany() public {
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        vm.stopPrank();
        goForward(604801);

        goForward(304801);
        kwenta.transfer(address(tokenDistributor), 1000);
        tokenDistributor.checkpointToken();
        goForward(604801);

        kwenta.transfer(address(tokenDistributor), 5000);
        goForward(604801);

        uint[] memory epochs = new uint[](2);
        epochs[0] = 1;
        epochs[1] = 2;
        tokenDistributor.claimMany(address(user1), epochs);
    }

    /// @notice fuzz claimEpochFees
    function testFuzzClaim(uint256 amount) public {
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
        /// @dev checkpoint at the end of epoch 0
        /// to remove cross epoch distribution
        goForward(604798);
        tokenDistributor.checkpointToken();

        /// @dev send fees to TokenDistributor 1 second before
        /// epoch 1 ends
        goForward(604799);
        kwenta.transfer(address(tokenDistributor), amount);
        tokenDistributor.checkpointToken();
        goForward(1);

        /// @dev claim for epoch 1 at the first second of epoch 2
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), amount / 3, 31449600, 1);
        tokenDistributor.claimEpoch(address(user1), 1);
    }

    //todo: go deeper with fuzzing

    /// @notice test everything with a custom offset
    function testOffset() public {
        TokenDistributor tokenDistributorOffset = new TokenDistributor(
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
        goForward(172801);
        kwenta.transfer(address(tokenDistributorOffset), 100);

        /// @dev checkpoint token < 24 hours before epoch end
        goForward(600000);
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1377603, 100);
        tokenDistributorOffset.checkpointToken();
        kwenta.transfer(address(tokenDistributorOffset), 5);
        goForward(4801);

        /// @dev claim at the start of the new epoch (should also checkpoint)
        vm.expectEmit(true, true, true, true);
        emit CheckpointToken(1382404, 5);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user1), 53, 31449600, 1);
        tokenDistributorOffset.claimEpoch(address(user1), 1);

        /// @dev user2 cant claim because they didnt stake
        vm.expectRevert();
        tokenDistributorOffset.claimEpoch(address(user2), 1);
    }

    /// @notice test startOfWeek
    function testStartOfWeek() public {
        /// @dev starts after another week so the startTime is != 0
        goForward(604801);

        TokenDistributor tokenDistributorOffset = new TokenDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            2
        );

        /// @dev normally the start of the week would be 608400 but offset of 2
        /// makes it it 777600 (608400 + 86400 * 2)
        /// @note the current timestamp is 608402 but the start of the OFFSET week
        /// is not for another 2 days
        uint result = tokenDistributorOffset.startOfWeek(block.timestamp);
        assertEq(result, 777600);

        goForward(172800);
        uint result2 = tokenDistributorOffset.startOfWeek(block.timestamp);
        assertEq(result2, 1382400);

        /// @dev this should be passed a normal week but just before the offset
        /// week so nothing should change
        goForward(604000);
        uint result3 = tokenDistributorOffset.startOfWeek(block.timestamp);
        assertEq(result3, 1382400);

        /// @dev this is a few hundred seconds into a new offset week so should
        /// be a different start time
        goForward(1000);
        uint result4 = tokenDistributorOffset.startOfWeek(block.timestamp);
        assertEq(result4, 1987200);
    }
    //todo: fuzz test offsetting

    //todo: test how many weeks we can go without - how much gas will it cost

    //todo: change seconds to 1 weeks or 1 days
}
