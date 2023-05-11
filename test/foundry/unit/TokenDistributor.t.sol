// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {TokenDistributor} from "../../../contracts/TokenDistributor.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";

contract TokenDistributorTest is Test {
    TokenDistributor public tokenDistributor;
    Kwenta public kwenta;
    StakingRewardsV2 public stakingRewardsV2;

    function setUp() public {
        kwenta = new Kwenta("Kwenta", "Kwe", 10, address(this), address(this));
        /// @dev kwenta is plugged in for all parameters to control variables
        /// @dev functions that are used by TokenDistributor shouldn't need the dependencies
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
    function testNewDistribution() public {}

    /// @notice newDistribution fail - epoch hasnt started yet
    function testFailNewDistributionEpochNotStarted() public {}

    /// @notice newDistribution test first epoch and second
    function testNewDistributionSequentialEpochs() public {}

    //maybe use tokenDistributor.epoch? to check if epoch changed

    /// @notice claimDistribution happy case and make a new epoch
    function testClaimDistributionNewEpoch() public {}

    /// @notice claimDistribution happy case and don't make a new epoch
    function testClaimDistribution() public {}

    /// @notice claimDistribution fail - epoch is not ready to claim
    function testClaimDistributionEpochNotReady() public {
        //do a revert with message
    }

    /// @notice claimDistribution fail - already claimed
    function testClaimDistributionAlreadyClained() public {
        //expect revert with message
    }

    //maybe try fuzzing claimDistribution

   
}
