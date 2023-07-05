// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "../lib/forge-std/src/Script.sol";
import {TokenDistributor} from "../contracts/TokenDistributor.sol";

/**
 *
 * MAINNET DEPLOYMENT: Optimism
 *
 */

contract DeployTokenDistributor is Script {
    // contract(s) being deployed
    TokenDistributor distributor;

    // constructor arguments
    address constant KWENTA = 0x920Cf626a271321C151D027030D5d08aF699456b;
    address constant STAKING_REWARDS_V2_PROXY = address(0); //todo: update before deployment
    address constant REWARD_ESCROW_V2_PROXY = address(0);   //todo: update before deployment

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy contract(s)

        distributor = new TokenDistributor({
            _stakingRewardsV2: STAKING_REWARDS_V2_PROXY,
            _rewardEscrowV2: REWARD_ESCROW_V2_PROXY,
            _kwenta: KWENTA,
            daysToOffsetBy: 0   //todo: update before deployment
        });

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
 * > forge script script/DeployTokenDistributor.s.sol:DeployTokenDistributor --rpc-url $OPTIMISM_RPC_URL --broadcast -vvvv
 */
