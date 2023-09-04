// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IKwenta} from "./interfaces/IKwenta.sol";
import {IStakingRewardsV2} from "./interfaces/IStakingRewardsV2.sol";
import {ISupplySchedule} from "./interfaces/ISupplySchedule.sol";
import {IRewardEscrowV2} from "./interfaces/IRewardEscrowV2.sol";

contract NotifiableRewardAccumulator {

    /// @notice kwenta interface
    IKwenta internal immutable kwenta;

    /// @notice rewards staking contract
    IStakingRewardsV2 internal stakingRewardsV2;

    /// @notice supply schedule contract
    ISupplySchedule internal immutable supplySchedule;

    /// @notice one time setter boolean
    bool public stakingRewardsV2IsSet;

    /// @notice Input address is 0
    error InputAddress0();

    /// @notice OnlySupplySchedule can access this
    error OnlySupplySchedule();

    /// @notice StakingRewardsV2 is already set
    error StakingRewardsV2IsSet();

    /// @notice AccumulatorRewardForwarded
    event AccumulatorRewardForwarded(uint currentBalance);

    /// @notice access control modifier for supplySchedule
    modifier onlySupplySchedule() {
        _onlySupplySchedule();
        _;
    }

    function _onlySupplySchedule() internal view {
        if (msg.sender != address(supplySchedule)) revert OnlySupplySchedule();
    }

    function setStakingRewardsV2(address _stakingRewardsV2) external {
        if (_stakingRewardsV2 == address(0)) revert InputAddress0();
        if (stakingRewardsV2IsSet) revert StakingRewardsV2IsSet();
        stakingRewardsV2IsSet = true;
        stakingRewardsV2 = IStakingRewardsV2(_stakingRewardsV2);
    }

    constructor(address _kwenta, address _supplySchedule) {
        if (_kwenta == address(0) || _supplySchedule == address(0)) {
            revert InputAddress0();
        }
        kwenta = IKwenta(_kwenta);
        supplySchedule = ISupplySchedule(_supplySchedule);
    }

    function notifyRewardAmount(uint mintedAmount) external onlySupplySchedule {
        /// @dev delete because it is not used
        /// instead currentBalance is used
        delete mintedAmount;
        uint currentBalance = kwenta.balanceOf(address(this));
        kwenta.transfer(address(stakingRewardsV2), currentBalance);
        stakingRewardsV2.notifyRewardAmount(currentBalance);
        }
    
}