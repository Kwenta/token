// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IStakingRewardsV2Integrator} from
    "../../../../contracts/interfaces/IStakingRewardsV2Integrator.sol";

contract MockStakingV2Integrator is IStakingRewardsV2Integrator {
    address public override beneficiary;

    constructor(address _beneficiary) {
        beneficiary = _beneficiary;
    }
}
