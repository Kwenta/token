// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TokenDistributor} from "../../../contracts/TokenDistributor.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {StakingSetup} from "../utils/StakingSetup.t.sol";
import "forge-std/Test.sol";

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
            address(rewardEscrowV2)
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
        //todo: figure out why the amount is 4 not 10
        emit VestingEntryCreated(address(user1), 4, 31449600, 1);
        tokenDistributor.claimEpoch(address(user1), 1);
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
        vm.expectRevert();
        tokenDistributor.claimEpoch(address(user1), 0);
    }

    //todo: comment out until figure out if doing things in same block matters
    /*
    /// @notice claimEpoch fail - cant claim in same block as new distribution
    function testClaimDistributionNewDistributionBlock() public {
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user1), 1);
        vm.startPrank(address(user1));
        kwenta.approve(address(stakingRewardsV2), 1);
        stakingRewardsV2.stake(1);
        goForward(604801);

        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributor.CannotClaimInNewEpochBlock.selector)
        );
        tokenDistributor.claimEpoch(address(user1), 1);
    }
    */
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

    //todo: test claiming when it doesnt make a new checkpoint

    //todo: test like multiple claims but when someone tries to claim new fees mid week
    // might not matter because 1 week wait
}
