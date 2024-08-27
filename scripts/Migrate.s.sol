// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {Kwenta} from "../contracts/Kwenta.sol";
import {StakingRewards} from "../contracts/StakingRewards.sol";
import {SupplySchedule} from "../contracts/SupplySchedule.sol";
import {RewardEscrow} from "../contracts/RewardEscrow.sol";
import {RewardEscrowV2} from "../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../contracts/StakingRewardsV2.sol";
import {EscrowMigrator} from "../contracts/EscrowMigrator.sol";
import {StakingRewardsNotifier} from "../contracts/StakingRewardsNotifier.sol";
import "../test/foundry/utils/Constants.t.sol";

// Upgradeability imports
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/*//////////////////////////////////////////////////////////////
                        MIGRATION CONTRACT
//////////////////////////////////////////////////////////////*/

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
        address _usdc,
        address _supplySchedule,
        address _rewardEscrowV1,
        address _treasuryDAO,
        bool _printLogs
    )
        public
        returns (
            RewardEscrowV2 rewardEscrowV2,
            StakingRewardsV2 stakingRewardsV2,
            EscrowMigrator escrowMigrator,
            StakingRewardsNotifier rewardsNotifier,
            address rewardEscrowV2Implementation,
            address stakingRewardsV2Implementation,
            address escrowMigratorImplementation
        )
    {
        if (_printLogs) console.log("********* 1. DEPLOYMENT STARTING... *********");

        // Deploy StakingRewardsNotifier
        rewardsNotifier = new StakingRewardsNotifier(
            _owner,
            _kwenta,
            _usdc,
            _supplySchedule
        );

        if (_printLogs) {
            console.log("Deployed StakingRewardsNotifier at %s", address(rewardsNotifier));
        }

        // Deploy RewardEscrowV2
        rewardEscrowV2Implementation =
            address(new RewardEscrowV2(_kwenta, address(rewardsNotifier)));
        rewardEscrowV2 = RewardEscrowV2(
            address(
                new ERC1967Proxy(
                    rewardEscrowV2Implementation,
                    abi.encodeWithSignature(
                        "initialize(address)",
                        _owner
                    )
                )
            )
        );

        if (_printLogs) {
            console.log(
                "Deployed RewardEscrowV2 Implementation at %s", rewardEscrowV2Implementation
            );
        }
        if (_printLogs) console.log("Deployed RewardEscrowV2 Proxy at %s", address(rewardEscrowV2));

        // Deploy StakingRewardsV2
        stakingRewardsV2Implementation = address(
            new StakingRewardsV2(
                _kwenta,
                _usdc,
                address(rewardEscrowV2),
                address(rewardsNotifier)
            )
        );

        stakingRewardsV2 = StakingRewardsV2(
            address(
                new ERC1967Proxy(
                    stakingRewardsV2Implementation,
                    abi.encodeWithSignature("initialize(address)", _owner)
                )
            )
        );

        if (_printLogs) {
            console.log(
                "Deployed StakingRewardsV2 Implementation at %s", stakingRewardsV2Implementation
            );
        }
        if (_printLogs) {
            console.log("Deployed StakingRewardsV2 Proxy at %s", address(stakingRewardsV2));
        }

        // Deploy EscrowMigrator
        escrowMigratorImplementation = address(
            new EscrowMigrator(
                _kwenta,
                _rewardEscrowV1,
                address(rewardEscrowV2),
                address(stakingRewardsV2)
            )
        );

        escrowMigrator = EscrowMigrator(
            address(
                new ERC1967Proxy(
                    escrowMigratorImplementation,
                    abi.encodeWithSignature("initialize(address,address)", _owner, _treasuryDAO)
                )
            )
        );

        if (_printLogs) {
            console.log(
                "Deployed EscrowMigrator Implementation at %s", escrowMigratorImplementation
            );
        }
        if (_printLogs) {
            console.log("Deployed EscrowMigrator Proxy at %s", address(escrowMigrator));
        }

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
        address _escrowMigrator,
        address _rewardsNotifier,
        address _treasuryDAO,
        bool _printLogs
    ) public {
        if (_printLogs) console.log("********* 2. SETUP STARTING... *********");
        RewardEscrowV2 rewardEscrowV2 = RewardEscrowV2(_rewardEscrowV2);

        // Set RewardEscrowV2 TreasuryDAO
        rewardEscrowV2.setTreasuryDAO(_treasuryDAO);

        if (_printLogs) {
            console.log("Switched RewardEscrowV2 to point to TreasuryDAO at %s", _treasuryDAO);
        }

        // Set RewardEscrowV2 StakingRewardsV2
        rewardEscrowV2.setStakingRewards(_stakingRewardsV2);

        if (_printLogs) {
            console.log(
                "Switched RewardEscrowV2 to point to StakingRewardsV2 at %s", _stakingRewardsV2
            );
        }

        // Set RewardEscrowV2 EscrowMigrator
        rewardEscrowV2.setEscrowMigrator(_escrowMigrator);

        if (_printLogs) {
            console.log("Switched RewardEscrowV2 to point to EscrowMigrator at %s", _escrowMigrator);
        }

        StakingRewardsNotifier rewardsNotifier = StakingRewardsNotifier(_rewardsNotifier);

        // Set StakingRewardsV2 in rewardsNotifier
        rewardsNotifier.setStakingRewardsV2(_stakingRewardsV2);

        if (_printLogs) {
            console.log(
                "Switched StakingRewardsNotifier to point to StakingRewardsV2 at %s",
                _stakingRewardsV2
            );
        }

        // Give up rewards notifier ownership now that StakingRewardsV2 is set
        rewardsNotifier.renounceOwnership();

        if (_printLogs) {
            console.log("Renounced StakingRewardsNotifier ownership");
        }

        if (_printLogs) console.log(unicode"--------- 🔧 SETUP COMPLETE 🔧 ---------");
    }

    /**
     * @dev Step 3: migrate to the new contracts
     *   - Only the owner of SupplySchedule & RewardEscrow can successfully do this
     *   - This MUST be executed after setupSystem is complete
     *   - Only run if we are completely ready to migrate to stakingv2
     */
    function migrateSystem(
        address _supplySchedule,
        address _rewardEscrowV1,
        address _rewardsNotifier,
        address _escrowMigrator,
        bool _printLogs
    ) public {
        if (_printLogs) console.log("********* 3. MIGRATION STARTING... *********");
        SupplySchedule supplySchedule = SupplySchedule(_supplySchedule);

        // Update SupplySchedule to point to StakingV2
        /// @dev note that it is set to rewards notifier and not staking rewards v2
        /// this is because we amalgamate the early vest fees and the staking rewards
        /// together in the rewards notifier contract
        supplySchedule.setStakingRewards(_rewardsNotifier);

        if (_printLogs) {
            console.log(
                "Switched SupplySchedule to point to StakingRewardsNotifier at %s", _rewardsNotifier
            );
        }

        RewardEscrow rewardEscrowV1 = RewardEscrow(_rewardEscrowV1);

        // Update RewardEscrow to point to EscrowMigrator
        rewardEscrowV1.setTreasuryDAO(_escrowMigrator);

        if (_printLogs) {
            console.log("Switched RewardEscrow to point to EscrowMigrator at %s", _escrowMigrator);
        }

        // Unpause EscrowMigrator
        EscrowMigrator escrowMigrator = EscrowMigrator(_escrowMigrator);
        escrowMigrator.unpauseEscrowMigrator();

        if (_printLogs) {
            console.log("Unpaused EscrowMigrator at %s", _escrowMigrator);
        }

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
        address _usdc,
        address _supplySchedule,
        address _treasuryDAO,
        address _rewardEscrowV1,
        bool _printLogs
    )
        public
        returns (
            RewardEscrowV2 rewardEscrowV2,
            StakingRewardsV2 stakingRewardsV2,
            EscrowMigrator escrowMigrator,
            StakingRewardsNotifier rewardsNotifier
        )
    {
        // Step 1: Deploy StakingV2 contracts
        (rewardEscrowV2, stakingRewardsV2, escrowMigrator, rewardsNotifier,,,) = deploySystem({
            _owner: _owner,
            _kwenta: _kwenta,
            _usdc: _usdc,
            _supplySchedule: _supplySchedule,
            _rewardEscrowV1: _rewardEscrowV1,
            _treasuryDAO: _treasuryDAO,
            _printLogs: _printLogs
        });

        // Step 2: Setup StakingV2 contracts
        setupSystem({
            _rewardEscrowV2: address(rewardEscrowV2),
            _stakingRewardsV2: address(stakingRewardsV2),
            _escrowMigrator: address(escrowMigrator),
            _rewardsNotifier: address(rewardsNotifier),
            _treasuryDAO: _treasuryDAO,
            _printLogs: _printLogs
        });

        // Step 3: Migrate SupplySchedule to point at StakingV2 & RewardEscrow to point at EscrowMigrator
        // After this, all new rewards will be distributed via StakingV2, and all vest early penalties
        // will be sent to the EscrowMigrator contract
        migrateSystem({
            _supplySchedule: _supplySchedule,
            _rewardEscrowV1: _rewardEscrowV1,
            _rewardsNotifier: address(rewardsNotifier),
            _escrowMigrator: address(escrowMigrator),
            _printLogs: _printLogs
        });
    }
}

/*//////////////////////////////////////////////////////////////
                        OPTIMISM SCRIPT
//////////////////////////////////////////////////////////////*/

/// @dev steps to deploy, setup and verify on Optimism:
/// (1) ensure the .env file contains the following variables:
///     - DEPLOYER_PRIVATE_KEY - the private key of the deployer
///     - ETHERSCAN_API_KEY - the API key of the Optimism Etherscan account (a normal etherscan API key will not work)
///     - ARCHIVE_NODE_URL_L2 - the archive node URL of the Optimism network
/// (2) load the variables in the .env file via `source .env`
/// (3) run `forge script scripts/Migrate.s.sol:DeployAndSetupOptimism --rpc-url $ARCHIVE_NODE_URL_L2 --broadcast --verify -vvvv`
contract DeployAndSetupOptimism is Script, Migrate {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);

        (
            RewardEscrowV2 rewardEscrowV2,
            StakingRewardsV2 stakingRewardsV2,
            EscrowMigrator escrowMigrator,
            StakingRewardsNotifier rewardsNotifier,
            ,
            ,
        ) = Migrate.deploySystem({
            _owner: deployer,
            _kwenta: OPTIMISM_KWENTA_TOKEN,
            _usdc: OPTIMISM_USDC_TOKEN,
            _supplySchedule: OPTIMISM_SUPPLY_SCHEDULE,
            _rewardEscrowV1: OPTIMISM_REWARD_ESCROW_V1,
            _treasuryDAO: OPTIMISM_TREASURY_DAO,
            _printLogs: true
        });

        Migrate.setupSystem({
            _rewardEscrowV2: address(rewardEscrowV2),
            _stakingRewardsV2: address(stakingRewardsV2),
            _escrowMigrator: address(escrowMigrator),
            _rewardsNotifier: address(rewardsNotifier),
            _treasuryDAO: OPTIMISM_TREASURY_DAO,
            _printLogs: true
        });

        rewardEscrowV2.transferOwnership(OPTIMISM_PDAO);
        stakingRewardsV2.transferOwnership(OPTIMISM_PDAO);
        escrowMigrator.transferOwnership(OPTIMISM_PDAO);

        vm.stopBroadcast();
    }
}

/*//////////////////////////////////////////////////////////////
                    OPTIMISM GOERLI SCRIPTS
//////////////////////////////////////////////////////////////*/

/// @dev steps to deploy, setup and verify on Optimism Goerli:
/// (1) ensure the .env file contains the following variables:
///     - DEPLOYER_PRIVATE_KEY - the private key of the deployer
///     - ETHERSCAN_API_KEY - the API key of the Optimism Etherscan account (a normal etherscan API key will not work)
///     - ARCHIVE_NODE_URL_GOERLI_L2 - the archive node URL of the Optimism Goerli network
/// (2) load the variables in the .env file via `source .env`
/// (3) run `forge script scripts/Migrate.s.sol:DeployAndSetupOptimismGoerli --rpc-url $ARCHIVE_NODE_URL_GOERLI_L2 --broadcast --verify -vvvv`
contract DeployAndSetupOptimismGoerli is Script, Migrate {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);

        (
            RewardEscrowV2 rewardEscrowV2,
            StakingRewardsV2 stakingRewardsV2,
            EscrowMigrator escrowMigrator,
            StakingRewardsNotifier rewardsNotifier,
            ,
            ,
        ) = Migrate.deploySystem({
            _owner: deployer,
            _kwenta: OPTIMISM_GOERLI_KWENTA_TOKEN,
            _usdc: OPTIMISM_GOERLI_USDC_TOKEN,
            _supplySchedule: OPTIMISM_GOERLI_SUPPLY_SCHEDULE,
            _rewardEscrowV1: OPTIMISM_GOERLI_REWARD_ESCROW_V1,
            _treasuryDAO: OPTIMISM_GOERLI_TREASURY_DAO,
            _printLogs: true
        });

        Migrate.setupSystem({
            _rewardEscrowV2: address(rewardEscrowV2),
            _stakingRewardsV2: address(stakingRewardsV2),
            _escrowMigrator: address(escrowMigrator),
            _rewardsNotifier: address(rewardsNotifier),
            _treasuryDAO: OPTIMISM_GOERLI_TREASURY_DAO,
            _printLogs: true
        });

        rewardEscrowV2.transferOwnership(OPTIMISM_GOERLI_TREASURY_DAO);
        stakingRewardsV2.transferOwnership(OPTIMISM_GOERLI_TREASURY_DAO);
        escrowMigrator.transferOwnership(OPTIMISM_GOERLI_TREASURY_DAO);

        vm.stopBroadcast();
    }
}

/// @dev steps to deploy, setup and verify on Optimism Goerli:
/// (1) ensure the .env file contains the following variables:
///     - DEPLOYER_PRIVATE_KEY - the private key of the deployer
///     - ETHERSCAN_API_KEY - the API key of the Optimism Etherscan account (a normal etherscan API key will not work)
///     - ARCHIVE_NODE_URL_GOERLI_L2 - the archive node URL of the Optimism Goerli network
/// (2) load the variables in the .env file via `source .env`
/// (3) run `forge script scripts/Migrate.s.sol:DeploySetupAndMigrateOptimismGoerli --rpc-url $ARCHIVE_NODE_URL_GOERLI_L2 --broadcast --verify -vvvv`
contract DeploySetupAndMigrateOptimismGoerli is Script, Migrate {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);

        Migrate.runCompleteMigrationProcess({
            _owner: deployer,
            _kwenta: OPTIMISM_GOERLI_KWENTA_TOKEN,
            _usdc: OPTIMISM_GOERLI_USDC_TOKEN,
            _supplySchedule: OPTIMISM_GOERLI_SUPPLY_SCHEDULE,
            _treasuryDAO: OPTIMISM_GOERLI_TREASURY_DAO,
            _rewardEscrowV1: OPTIMISM_GOERLI_REWARD_ESCROW_V1,
            _printLogs: true
        });

        vm.stopBroadcast();
    }
}
