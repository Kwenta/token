// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IStakingRewardsV2Integrator {
    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/
    function beneficiary() external view returns (address);
}
