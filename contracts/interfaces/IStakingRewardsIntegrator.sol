// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IStakingRewardsIntegrator {
    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/
    function beneficiary() external view returns (address);
}
