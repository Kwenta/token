// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {TokenDistributor} from "../../../contracts/TokenDistributor.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";

contract TokenDistributorTest is Test {
    event NewEpochCreated(uint block, uint epoch);
    event VestingEntryCreated(
        address indexed beneficiary,
        uint256 value,
        uint256 duration,
        uint256 entryID
    );

    TokenDistributor public tokenDistributor;
    Kwenta public kwenta;
    StakingRewardsV2 public stakingRewardsV2;
    RewardEscrowV2 public rewardEscrowV2;
    address public user;
    address public user2;

    function setUp() public {
        user = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("user")))))
        );
        user2 = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("user2")))))
        );
        kwenta = new Kwenta(
            "Kwenta",
            "Kwe",
            10000,
            address(this),
            address(this)
        );
        rewardEscrowV2 = new RewardEscrowV2(address(this), address(kwenta));
        /// @dev kwenta is plugged in for all parameters except rewardEscrowV2 to control variables
        /// functions that are used by TokenDistributor shouldn't need the other dependencies
        stakingRewardsV2 = new StakingRewardsV2(
            address(kwenta),
            address(rewardEscrowV2),
            address(kwenta),
            address(kwenta)
        );
        tokenDistributor = new TokenDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2)
        );
    }

    /// @notice newDistribution happy case
    function testNewDistribution() public {
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(1, 0);
        tokenDistributor.newDistribution();
    }

    /// @notice newDistribution fail - last epoch hasnt ended yet
    function testNewDistributionLastEpochNotEnded() public {
        vm.startPrank(user);
        tokenDistributor.newDistribution();
        vm.expectRevert(
            "TokenDistributor: Last week's epoch has not ended yet"
        );
        tokenDistributor.newDistribution();
    }

    /// @notice newDistribution fail - last epoch hasnt ended yet, epoch > 1
    function testNewDistributionLastEpochNotEnded2() public {
        vm.startPrank(user);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 304801);
        vm.expectRevert(
            "TokenDistributor: Last week's epoch has not ended yet"
        );
        tokenDistributor.newDistribution();
    }

    /// @notice newDistribution test first epoch and second
    function testNewDistributionSequentialEpochs() public {
        vm.startPrank(user);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(604802, 1);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(1209603, 2);
        tokenDistributor.newDistribution();
    }

    /// @notice newDistribution test fail after 2 created and third is too soon
    function testNewDistributionSequentialEpochsFail() public {
        vm.startPrank(user);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(604802, 1);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 304801);
        vm.expectRevert(
            "TokenDistributor: Last week's epoch has not ended yet"
        );
        tokenDistributor.newDistribution();
    }

    /// @notice claimDistribution happy case and make a new epoch
    function testClaimDistributionNewEpoch() public {
        //setup
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        vm.prank(address(rewardEscrowV2));
        stakingRewardsV2.stakeEscrow(address(user), 1);
        vm.prank(user);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(604802, 1);
        tokenDistributor.claimDistribution(address(user), 0);
    }

    /// @notice claimDistribution happy case and don't make a new epoch
    function testClaimDistributionSameEpoch() public {
        //setup
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        kwenta.transfer(address(user2), 1);
        vm.startPrank(address(rewardEscrowV2));
        stakingRewardsV2.stakeEscrow(address(user), 1);
        stakingRewardsV2.stakeEscrow(address(user2), 1);
        vm.stopPrank();
        vm.prank(user);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(604802, 1);
        tokenDistributor.claimDistribution(address(user), 0);

        vm.warp(block.timestamp + 1000);
        vm.prank(user2);
        tokenDistributor.claimDistribution(address(user2), 0);
    }

    /// @notice claimDistribution fail - epoch is not ready to claim
    function testClaimDistributionEpochNotReady() public {
        vm.startPrank(user);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 304801);
        vm.expectRevert("TokenDistributor: Epoch is not ready to claim");
        tokenDistributor.claimDistribution(address(user), 0);
    }

    /// @notice claimDistribution fail - epoch is not ready to claim, not an epoch yet
    function testClaimDistributionEpochAhead() public {
        vm.startPrank(user);
        tokenDistributor.newDistribution();
        vm.expectRevert("TokenDistributor: Epoch is not ready to claim");
        tokenDistributor.claimDistribution(address(user), 7);
    }

    /// @notice claimDistribution fail - no epoch to claim yet
    function testClaimDistributionNoEpochYet() public {
        vm.startPrank(user);
        vm.expectRevert();
        tokenDistributor.claimDistribution(address(user), 0);
    }

    /// @notice claimDistribution fail - already claimed
    function testClaimDistributionAlreadyClaimed() public {
        //setup
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        vm.prank(address(rewardEscrowV2));
        stakingRewardsV2.stakeEscrow(address(user), 1);
        vm.prank(user);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(604802, 1);
        tokenDistributor.claimDistribution(address(user), 0);

        vm.expectRevert(
            "TokenDistributor: You already claimed this epoch's fees"
        );
        tokenDistributor.claimDistribution(address(user), 0);
    }

    /// @notice claimDistribution fail - claim an epoch that had no staking
    function testClaimDistributionNoStaking() public {
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        vm.prank(user);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);
        vm.prank(user);
        vm.expectRevert(
            "TokenDistributor: Nothing was staked in StakingRewardsV2 that epoch"
        );
        tokenDistributor.claimDistribution(address(user), 0);
    }

    /// @notice claimDistribution fail - nonstaker tries to claim
    function testFailClaimDistributionNotStaker() public {
        //setup
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        vm.prank(address(rewardEscrowV2));
        stakingRewardsV2.stakeEscrow(address(user), 1);
        vm.prank(user);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(604802, 1);
        tokenDistributor.claimDistribution(address(user), 0);

        vm.prank(user2);
        tokenDistributor.claimDistribution(address(user2), 0);
    }

    /// @notice claimDistribution happy case with a person who
    /// was previously staked but is now unstaked and trying to
    /// claim their fees
    function testClaimDistributionPreviouslyStaked() public {
        //setup
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        vm.prank(address(rewardEscrowV2));
        stakingRewardsV2.stakeEscrow(address(user), 1);
        stakingRewardsV2.balanceAtBlock(user, 1);
        //vm.warp(block.timestamp + 1);
        vm.prank(user);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(604802, 1);
        tokenDistributor.newDistribution();

        vm.warp(block.timestamp + 1209601);
        stakingRewardsV2.balanceAtBlock(user, 1);
        vm.prank(address(rewardEscrowV2));
        stakingRewardsV2.unstakeEscrow(address(user), 1);
        stakingRewardsV2.balanceAtBlock(user, 1);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);
        tokenDistributor.newDistribution();

        vm.prank(user);
        tokenDistributor.claimDistribution(address(user), 0);


    }

    /// @notice claimDistribution happy case with partial claims
    /// in earlier epochs 2 complete epochs with differing fees
    /// @dev also an integration test with RewardEscrowV2
    function testClaimDistributionMultipleClaims() public {
        /// @dev user has 1/3 total staking and user2 has 2/3
        /// before epoch #0 (same as during) TokenDistributor
        /// receives 1000 in fees
        kwenta.transfer(address(tokenDistributor), 1000);
        kwenta.transfer(address(user), 1);
        kwenta.transfer(address(user2), 2);
        vm.startPrank(address(rewardEscrowV2));
        stakingRewardsV2.stakeEscrow(address(user), 1);
        stakingRewardsV2.stakeEscrow(address(user2), 2);
        vm.stopPrank();
        vm.prank(user);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);

        /// @dev during epoch #1, user claims their fees from #0
        /// and TokenDistributor receives 5000 in fees

        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(604802, 1);
        tokenDistributor.newDistribution();
        kwenta.transfer(address(tokenDistributor), 5000);
        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user), 333, 31449600, 1);
        tokenDistributor.claimDistribution(address(user), 0);

        /// @dev user claims for epoch #1 to start epoch #2
        /// user2 also claims for #1 and #0
        /// and TokenDistributor receives 300 in fees

        vm.warp(block.timestamp + 604801);
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(1209603, 2);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user), 1666, 31449600, 2);
        tokenDistributor.claimDistribution(address(user), 1);
        vm.warp(block.timestamp + 1000);
        kwenta.transfer(address(tokenDistributor), 300);
        vm.prank(user2);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user2), 3333, 31449600, 3);
        tokenDistributor.claimDistribution(address(user2), 1);
        vm.prank(user2);
        vm.expectEmit(true, true, false, true);
        emit VestingEntryCreated(address(user2), 666, 31449600, 4);
        tokenDistributor.claimDistribution(address(user2), 0);
    }
}
