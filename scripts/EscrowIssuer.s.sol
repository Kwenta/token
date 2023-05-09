// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {EscrowIssuer} from "../contracts/EscrowIssuer.sol";

contract MyScript is Script {
    address public kwenta;

    address public rewardEscrow;

    //public address
    address public treasury = 0x3C704e28C8EfCC7aCa262031818001895595081D;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        EscrowIssuer escrowIssuer = new EscrowIssuer(
            "EscIss",
            "EIS",
            address(kwenta),
            address(rewardEscrow),
            address(treasury)
        );

        vm.stopBroadcast();
    }
}
