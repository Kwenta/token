// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {TokenDistributor} from "../../../contracts/TokenDistributor.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";

contract TokenDistributorTest is Test {
    event NewEpochCreated(uint block, uint epoch);

    TokenDistributor public tokenDistributor;
    Kwenta public kwenta;
    StakingRewardsV2 public stakingRewardsV2;
    address public user;
    address public user2;

    function setUp() public {
        user = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("user")))))
        );
        user2 = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("user2")))))
        );
        kwenta = new Kwenta("Kwenta", "Kwe", 15, address(this), address(this));
        /// @dev kwenta is plugged in for all parameters to control variables
        /// @dev functions that are used by TokenDistributor shouldn't need the other dependencies
        stakingRewardsV2 = new StakingRewardsV2(
            address(kwenta),
            address(kwenta),
            address(kwenta),
            address(kwenta)
        );
        tokenDistributor = new TokenDistributor(
            address(kwenta),
            address(stakingRewardsV2)
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
        vm.expectRevert("TokenDistributor: Last week's epoch has not ended yet");
        tokenDistributor.newDistribution();
    }

    /// @notice claimDistribution happy case and make a new epoch
    function testClaimDistributionNewEpoch() public {
        //setup
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        vm.prank(address(kwenta));
        stakingRewardsV2.stakeEscrow(address(user), 1);
        vm.prank(user);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(604802, 1);
        tokenDistributor.claimDistribution(address(user), 0);

        //todo: change to rewardEscrow outcome
        //assert that user got all the fees
        assertEq(kwenta.balanceOf(user), 11);
    }

    /// @notice claimDistribution happy case and don't make a new epoch
    function testClaimDistributionSameEpoch() public {
        //setup
        kwenta.transfer(address(tokenDistributor), 10);
        kwenta.transfer(address(user), 1);
        kwenta.transfer(address(user2), 1);
        vm.startPrank(address(kwenta));
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
        
    }

    /// @notice claimDistribution with previous claims in earlier epochs

    /// @notice claimDistribution claim an epoch that had no staking
}
