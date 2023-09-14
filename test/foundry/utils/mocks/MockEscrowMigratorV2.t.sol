// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {EscrowMigrator} from "../../../../contracts/EscrowMigrator.sol";

contract MockEscrowMigratorV2 is EscrowMigrator {
    uint256 public newNum;

    constructor(
        address _kwenta,
        address _rewardEscrowV1,
        address _rewardEscrowV2,
        address _stakingRewardsV2
    ) EscrowMigrator(_kwenta, _rewardEscrowV1, _rewardEscrowV2, _stakingRewardsV2) {}

    function setNewNum(uint256 _newNum) external {
        newNum = _newNum;
    }

    function newFunctionality() external pure returns (uint256) {
        return 42;
    }
}
