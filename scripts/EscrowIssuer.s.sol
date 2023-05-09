// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {EscrowIssuer} from "../contracts/EscrowIssuer.sol";

contract DeployEscrowIssuer is Script {
    function deployEscrowIssuer(
        address _kwenta,
        address _rewardEscrow,
        address _treasury
    ) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        EscrowIssuer escrowIssuer = new EscrowIssuer(
            "EscIss",
            "EIS",
            address(_kwenta),
            address(_rewardEscrow),
            address(_treasury)
        );

        vm.stopBroadcast();
    }
}
