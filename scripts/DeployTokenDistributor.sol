// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "../lib/forge-std/src/Script.sol";
import {TokenDistributor} from "../contracts/TokenDistributor.sol";

/**
 *
 * MAINNET/TESTNET DEPLOYMENT: Optimism/Optimism Goerli
 *
 */

contract DeployTokenDistributor is Script {
    // contract(s) being deployed
    TokenDistributor distributor;

    // constructor arguments
    address constant MAINNET_KWENTA =
        0x920Cf626a271321C151D027030D5d08aF699456b;
    address constant MAINNET_STAKING_REWARDS_V2_PROXY = address(0); //todo: update before deployment
    address constant MAINNET_REWARD_ESCROW_V2_PROXY = address(0); //todo: update before deployment

    address constant TESTNET_KWENTA =
        0xDA0C33402Fc1e10d18c532F0Ed9c1A6c5C9e386C;
    address constant TESTNET_STAKING_REWARDS_V2_PROXY =
        0x3e5371D909Bf1996c95e9D179b0Bc91C26fb1279;
    address constant TESTNET_REWARD_ESCROW_V2_PROXY =
        0xf211F298C6985fF4cF6f9488e065292B818163F8;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy contract(s)

        /// @dev if rpc url == Optimism mainnet then deploy there
        if (block.chainid == 10) {
            distributor = new TokenDistributor({
                _stakingRewardsV2: MAINNET_STAKING_REWARDS_V2_PROXY,
                _rewardEscrowV2: MAINNET_REWARD_ESCROW_V2_PROXY,
                _kwenta: MAINNET_KWENTA,
                daysToOffsetBy: 0 //todo: update before deployment
            });
        }
        /// @dev else if rpc url == Optimism Goerli testnet then deploy there
        else if (block.chainid == 420) {
            distributor = new TokenDistributor({
                _stakingRewardsV2: TESTNET_STAKING_REWARDS_V2_PROXY,
                _rewardEscrowV2: TESTNET_REWARD_ESCROW_V2_PROXY,
                _kwenta: TESTNET_KWENTA,
                daysToOffsetBy: 0 //todo: update before deployment
            });
        }

        vm.stopBroadcast();
    }
}

/**
 * TO DEPLOY:
 *
 * To load the variables in the .env file
 * > source .env
 *
 * To deploy and verify our contract
 * > forge script script/DeployTokenDistributor.s.sol:DeployTokenDistributor --rpc-url $OPTIMISM_RPC_URL/$OPTIMISM_GOERLI_RPC_URL --broadcast -vvvv
 */
