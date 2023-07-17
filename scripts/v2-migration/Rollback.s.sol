// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {Kwenta} from "../../contracts/Kwenta.sol";
import {StakingRewards} from "../../contracts/StakingRewards.sol";
import {SupplySchedule} from "../../contracts/SupplySchedule.sol";
import {RewardEscrowV2} from "../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../contracts/StakingRewardsV2.sol";
import "../../test/foundry/utils/Constants.t.sol";

/*//////////////////////////////////////////////////////////////
                        MIGRATION CONTRACT
//////////////////////////////////////////////////////////////*/

/// @title Script for rollingback from StakingV2 to StakingV1
/// @author tommyrharper (zeroknowledgeltd@gmail.com)
/// @dev The contracts use the UUPS upgrade pattern (see eip-1822)
contract Rollback {
    /**
     * @dev Step 1: deploy the new contracts
     *   - This deploys the new stakingv2 contracts
     */
    function deploySystem(
        address _kwenta,
        address _rewardEscrowV2,
        address _supplySchedule,
        address _stakingRewardsV1,
        bool _printLogs
    )
        public
        returns (
            address rewardEscrowV2Impl,
            address stakingRewardsV2Impl
        )
    {
        if (_printLogs) console.log("********* 1. DEPLOYMENT STARTING... *********");

        // Deploy RewardEscrowV2Impl
        rewardEscrowV2Impl = address(new RewardEscrowV2(_kwenta));

        if (_printLogs) {
            console.log(
                "Deployed RewardEscrowV2 Implementation at %s", rewardEscrowV2Impl
            );
        }

        // Deploy StakingRewardsV2
        stakingRewardsV2Impl = address(
            new StakingRewardsV2(
                _kwenta,
                address(_rewardEscrowV2),
                _supplySchedule,
                address(_stakingRewardsV1)
            )
        );

        if (_printLogs) {
            console.log(
                "Deployed StakingRewardsV2 Implementation at %s", stakingRewardsV2Impl
            );
        }

        if (_printLogs) console.log(unicode"--------- 🚀 DEPLOYMENT COMPLETE 🚀 ---------");
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
/// (3) run `forge script scripts/Migrate.s.sol:DeployRollbackOptimism --rpc-url $ARCHIVE_NODE_URL_L2 --broadcast --verify -vvvv`
contract DeployRollbackOptimism is Script, Rollback {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Rollback.deploySystem(
            OPTIMISM_KWENTA_TOKEN,
            OPTIMISM_REWARD_ESCROW_V2,
            OPTIMISM_SUPPLY_SCHEDULE,
            OPTIMISM_STAKING_REWARDS_V1,
            true
        );

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
/// (3) run `forge script scripts/Migrate.s.sol:DeployRollbackOptimismGoerli --rpc-url $ARCHIVE_NODE_URL_GOERLI_L2 --broadcast --verify -vvvv`
contract DeployRollbackOptimismGoerli is Script, Rollback {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Rollback.deploySystem(
            OPTIMISM_GOERLI_KWENTA_TOKEN,
            OPTIMISM_GOERLI_REWARD_ESCROW_V2,
            OPTIMISM_GOERLI_SUPPLY_SCHEDULE,
            OPTIMISM_GOERLI_STAKING_REWARDS_V1,
            true
        );

        vm.stopBroadcast();
    }
}
