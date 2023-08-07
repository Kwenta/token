// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IStakingRewardsIntegrator} from
    "../../../../contracts/interfaces/IStakingRewardsIntegrator.sol";

contract MockStakingV2Integrator is IStakingRewardsIntegrator {
    address public override beneficiary;

    constructor(address _beneficiary) {
        beneficiary = _beneficiary;
    }
}
