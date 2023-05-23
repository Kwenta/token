// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Kwenta} from "../contracts/Kwenta.sol";
import {StakingRewards} from "../contracts/StakingRewards.sol";
import {SupplySchedule} from "../contracts/SupplySchedule.sol";
import {RewardEscrowV2} from "../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../contracts/StakingRewardsV2.sol";
import {StakingAccount} from "../contracts/StakingAccount.sol";

// Upgradeability imports
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Script for migration from StakingV1 to StakingV2
/// @author tommyrharper (zeroknowledgeltd@gmail.com)
/// @dev This uses the UUPS upgrade pattern (see eip-1822)
contract Migrate {
    /**
     * @dev Step 1: deploy the new contracts
     *   - This deploys the new stakingv2 contracts but stakingv1 will remain operational
     */
    function deploySystem(
        address _owner,
        address _kwenta,
        address _supplySchedule,
        address _stakingRewardsV1,
        bool _printLogs
    )
        public
        returns (
            RewardEscrowV2 rewardEscrowV2,
            StakingRewardsV2 stakingRewardsV2,
            StakingAccount stakingAccount,
            address rewardEscrowV2Implementation,
            address stakingRewardsV2Implementation,
            address stakingAccountImplementation
        )
    {
        if (_printLogs) console.log("********* 1. DEPLOYMENT STARTING... *********");

        // Deploy RewardEscrowV2
        rewardEscrowV2Implementation = address(new RewardEscrowV2());
        rewardEscrowV2 = RewardEscrowV2(address(new ERC1967Proxy(
            rewardEscrowV2Implementation,
            abi.encodeWithSignature(
                "initialize(address,address)",
                _owner,
                _kwenta
            )
        )));

        if (_printLogs) console.log("Deployed RewardEscrowV2 Implementation at %s", rewardEscrowV2Implementation);
        if (_printLogs) console.log("Deployed RewardEscrowV2 Proxy at %s", address(rewardEscrowV2));

        // Deploy StakingRewardsV2
        stakingRewardsV2Implementation = address(new StakingRewardsV2());
        stakingRewardsV2 = StakingRewardsV2(address(new ERC1967Proxy(
            stakingRewardsV2Implementation,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address)",
                _kwenta,
                address(rewardEscrowV2),
                _supplySchedule,
                address(_stakingRewardsV1),
                _owner
            )
        )));

        if (_printLogs) console.log("Deployed StakingRewardsV2 Implementation at %s", stakingRewardsV2Implementation);
        if (_printLogs) console.log(
            "Deployed StakingRewardsV2 Proxy at %s", address(stakingRewardsV2)
        );

        // Deploy StakingAccount
        stakingAccountImplementation = address(new StakingAccount());
        stakingAccount = StakingAccount(address(new ERC1967Proxy(
            stakingAccountImplementation,
            abi.encodeWithSignature(
                "initialize(address,address,address)",
                _owner,
                address(stakingRewardsV2),
                address(rewardEscrowV2)
            )
        )));

        if (_printLogs) console.log("Deployed StakingAccount Implementation at %s", stakingAccountImplementation);
        if (_printLogs) console.log("Deployed StakingAccount Proxy at %s", address(stakingAccount));

        if (_printLogs) console.log(unicode"--------- 🚀 DEPLOYMENT COMPLETE 🚀 ---------");
    }

    /**
     * @dev Step 2: setup the new contracts
     *   - Only the owner of RewardEscrowV2 can successfully do this
     *   - This can safely be executed immediately after deploySystem is complete
     *   - This MUST be run before migrateSystem is executed
     */
    function setupSystem(
        address _rewardEscrowV2,
        address _stakingRewardsV2,
        address _stakingAccount,
        address _treasuryDAO,
        bool _printLogs
    ) public {
        if (_printLogs) console.log("********* 2. SETUP STARTING... *********");
        RewardEscrowV2 rewardEscrowV2 = RewardEscrowV2(_rewardEscrowV2);

        // Set RewardEscrowV2 TreasuryDAO
        rewardEscrowV2.setTreasuryDAO(_treasuryDAO);

        if (_printLogs) console.log(
            "Switched RewardEscrowV2 to point to TreasuryDAO at %s",
            _treasuryDAO
        );

        // Set RewardEscrowV2 StakingRewardsV2
        rewardEscrowV2.setStakingRewardsV2(_stakingRewardsV2);

        if (_printLogs) console.log(
            "Switched RewardEscrowV2 to point to StakingRewardsV2 at %s",
            _stakingRewardsV2
        );

        // Set RewardEscrowV2 StakingAccount
        rewardEscrowV2.setStakingAccount(_stakingAccount);

        if (_printLogs) console.log(
            "Switched RewardEscrowV2 to point to StakingAccount at %s",
            _stakingAccount
        );

        // Set StakingRewardsV2 StakingAccount
        StakingRewardsV2 stakingRewardsV2 = StakingRewardsV2(_stakingRewardsV2);
        stakingRewardsV2.setStakingAccount(_stakingAccount);


        if (_printLogs) console.log(
            "Switched StakingRewardsV2 to point to StakingAccount at %s",
            _stakingAccount
        );

        if (_printLogs) console.log(unicode"--------- 🔧 SETUP COMPLETE 🔧 ---------");
    }

    /**
     * @dev Step 3: migrate to the new contracts
     *   - Only the owner of SupplySchedule can successfully do this
     *   - This MUST be executed after setRewardEscrowStakingRewards is complete
     *   - Only run if we are completely ready to migrate to stakingv2
     */
    function migrateSystem(address _supplySchedule, address _stakingRewardsV2, bool _printLogs)
        public
    {
        if (_printLogs) console.log("********* 3. MIGRATION STARTING... *********");
        SupplySchedule supplySchedule = SupplySchedule(_supplySchedule);

        // Update SupplySchedule to point to StakingV2
        supplySchedule.setStakingRewards(_stakingRewardsV2);

        if (_printLogs) console.log(
            "Switched SupplySchedule to point to StakingRewardsV2 at %s",
            _stakingRewardsV2
        );
        if (_printLogs) console.log(unicode"--------- 🎉 MIGRATION COMPLETE 🎉 ---------");
    }

    /**
     * @dev This is a convenience function to run the entire migration process
     *   - This should only be run if we are fully ready to deploy, setup and migrate to stakingv2
     *   - This can only be run successfully using the key of the owner of the SupplySchedule contract
     */
    function runCompleteMigrationProcess(
        address _owner,
        address _kwenta,
        address _supplySchedule,
        address _stakingRewardsV1,
        address _treasuryDAO,
        bool _printLogs
    )
        public
        returns (
            RewardEscrowV2 rewardEscrowV2,
            StakingRewardsV2 stakingRewardsV2,
            StakingAccount stakingAccount,
            address rewardEscrowV2Implementation,
            address stakingRewardsV2Implementation,
            address stakingAccountImplementation
        )
    {
        // Step 1: Deploy StakingV2 contracts
        (rewardEscrowV2, stakingRewardsV2, stakingAccount, rewardEscrowV2Implementation, stakingRewardsV2Implementation, stakingAccountImplementation) =
            deploySystem(_owner, _kwenta, _supplySchedule, _stakingRewardsV1, _printLogs);

        // Step 2: Setup StakingV2 contracts
        setupSystem(
            address(rewardEscrowV2), address(stakingRewardsV2), address(stakingAccount), _treasuryDAO, _printLogs
        );

        // Step 3: Migrate SupplySchedule to point at StakingV2
        // After this, all new rewards will be distributed via StakingV2
        migrateSystem(_supplySchedule, address(stakingRewardsV2), _printLogs);
    }
}
