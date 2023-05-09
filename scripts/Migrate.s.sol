// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {Kwenta} from "../contracts/Kwenta.sol";
import {StakingRewards} from "../contracts/StakingRewards.sol";
import {SupplySchedule} from "../contracts/SupplySchedule.sol";
import {RewardEscrowV2} from "../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../contracts/StakingRewardsV2.sol";

/// @title Script for migration from StakingV1 to StakingV2
/// @author tommyrharper (zeroknowledgeltd@gmail.com)
contract Migrate {
    /// @dev Step 1 of the migration process: deploy the new contracts
    /// @dev This deploys the new stakingv2 contracts but stakingv1 will remain operational
    function deploySystem(
        address _owner,
        address _kwenta,
        address _supplySchedule,
        address _stakingRewardsV1
    )
        public
        returns (
            RewardEscrowV2 rewardEscrowV2,
            StakingRewardsV2 stakingRewardsV2
        )
    {
        console.log("********* 1. DEPLOYMENT STARTING... *********");
        rewardEscrowV2 = new RewardEscrowV2(_owner, _kwenta);
        console.log("Deployed RewardEscrowV2 at %s", address(rewardEscrowV2));

        stakingRewardsV2 = new StakingRewardsV2(
            _kwenta,
            address(rewardEscrowV2),
            _supplySchedule,
            address(_stakingRewardsV1)
        );
        console.log(
            "Deployed StakingRewardsV2 at %s", address(stakingRewardsV2)
        );
        console.log(unicode"--------- 🚀 DEPLOYMENT COMPLETE 🚀 ---------");
    }

    /// @dev Step 2 of the migration process: setup the new contracts
    /// @dev only the owner of RewardEscrowV2 can do this
    /// @dev this can be executed immediately after deploySystem is complete
    /// @dev this should be run before migrateSystem is executed
    function setupSystem(address _rewardEscrowV2, address _stakingRewardsV2)
        public
    {
        console.log("********* 2. SETUP STARTING... *********");
        RewardEscrowV2 rewardEscrowV2 = RewardEscrowV2(_rewardEscrowV2);

        rewardEscrowV2.setStakingRewardsV2(_stakingRewardsV2);
        console.log(
            "Switched RewardEscrowV2 to point to StakingRewardsV2 at %s",
            _stakingRewardsV2
        );
        console.log(unicode"--------- 🔧 SETUP COMPLETE 🔧 ---------");
    }

    /// @dev Step 3 of the migration process: migrate to the new contracts
    /// @dev only the owner of SupplySchedule can do this
    /// @dev this should be executed after setRewardEscrowStakingRewards is complete
    /// @dev only run if we are completely ready to migrate to stakingv2
    function migrateSystem(address _supplySchedule, address _stakingRewardsV2)
        public
    {
        console.log("********* 3. MIGRATION STARTING... *********");
        SupplySchedule supplySchedule = SupplySchedule(_supplySchedule);

        // Update SupplySchedule to point to StakingV2
        supplySchedule.setStakingRewards(_stakingRewardsV2);
        console.log(
            "Switched SupplySchedule to point to StakingRewardsV2 at %s",
            _stakingRewardsV2
        );
        console.log(unicode"--------- 🎉 MIGRATION COMPLETE 🎉 ---------");
    }

    /// @dev this is a convenience function to run the entire migration process
    /// @dev this should only be run if we are fully ready to deploy, setup and migrate to stakingv2
    /// @dev this can only be run using the key of the owner of the SupplySchedule contract
    function runCompleteMigrationProcess(
        address _owner,
        address _kwenta,
        address _supplySchedule,
        address _stakingRewardsV1
    )
        public
        returns (
            RewardEscrowV2 rewardEscrowV2,
            StakingRewardsV2 stakingRewardsV2
        )
    {
        // Step 1: Deploy StakingV2 contracts
        (rewardEscrowV2, stakingRewardsV2) =
            deploySystem(_owner, _kwenta, _supplySchedule, _stakingRewardsV1);

        // Step 2: Setup StakingV2 contracts
        setupSystem(address(rewardEscrowV2), address(stakingRewardsV2));

        // Step 3: Migrate SupplySchedule to point at StakingV2
        // After this, all new rewards will be distributed vai StakingV2
        migrateSystem(_supplySchedule, address(stakingRewardsV2));
    }
}
