// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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

    function setUp() public {
        user = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("user")))))
        );
        kwenta = new Kwenta("Kwenta", "Kwe", 11, address(this), address(this));
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

    /// @notice newDistribution test first epoch and second
    function testNewDistributionSequentialEpochs() public {
        vm.startPrank(user);
        tokenDistributor.newDistribution();
        vm.warp(block.timestamp + 604801);
        vm.expectEmit(true, true, true, true);
        emit NewEpochCreated(604802, 1);
        tokenDistributor.newDistribution();
    }

    /// @notice claimDistribution happy case and make a new epoch
    function testClaimDistributionNewEpoch() public {
        //make sure tokenDistributor has kwenta first
        kwenta.transfer(address(tokenDistributor), 10);
        //then have user stake in stakingRewardsV2
        kwenta.transfer(address(user), 1);
        vm.prank(address(kwenta));
        stakingRewardsV2.stakeEscrow(address(user), 1);
        //then make new epoch
        vm.prank(user);
        tokenDistributor.newDistribution();
        //wait a week
        vm.warp(block.timestamp + 604801);
        //claim distribution
        vm.prank(user);
        tokenDistributor.claimDistribution(address(user), 0);
        //assert that its actually a new epoch

        //assert that user got all the fees
        assertEq(kwenta.balanceOf(user), 11);
    }

    /// @notice claimDistribution happy case and don't make a new epoch
    function testClaimDistribution() public {}

    /// @notice claimDistribution fail - epoch is not ready to claim
    function testClaimDistributionEpochNotReady() public {
        //do a revert with message
    }

    /// @notice claimDistribution fail - already claimed
    function testClaimDistributionAlreadyClaimed() public {
        //expect revert with message
    }

    //maybe try fuzzing claimDistribution

    /// @notice claimDistribution with previous claims in earlier epochs

    /// @notice claimDistribution claim an epoch that had no staking
}
