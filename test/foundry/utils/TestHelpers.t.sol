// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";

contract TestHelpers is Test {
    uint256 public userNonce;
    uint256 public nonce;

    function createUser() public returns (address) {
        userNonce++;
        return vm.addr(userNonce);
    }

    function getPseudoRandomNumber(
        uint256 max,
        uint256 min,
        uint256 salt
    ) internal returns (uint256) {
        require(min <= max, "min must be <= max");
        if (max == min) return max;

        uint256 result;
        while (result < min)
            result = uint256(keccak256(abi.encodePacked(++nonce, salt))) % max;
        return result;
    }
}
