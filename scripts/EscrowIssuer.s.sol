// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {EscrowIssuer} from "../contracts/EscrowIssuer.sol";

contract DeployEscrowIssuer is Script {
    ///@notice mainnet optimism kwenta address
    address public kwenta = 0x920Cf626a271321C151D027030D5d08aF699456b;

    ///@notice mainnet optimism rewardEscrow address
    address public rewardEscrow = 0x1066A8eB3d90Af0Ad3F89839b974658577e75BE2;

    ///@notice treasury address
    address public treasury = 0x82d2242257115351899894eF384f779b5ba8c695;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        new EscrowIssuer(
            "EscIss",
            "EIS",
            address(kwenta),
            address(rewardEscrow),
            address(treasury)
        );

        vm.stopBroadcast();
    }
}
