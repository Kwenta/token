// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IStakingRewardsNotifier} from "./interfaces/IStakingRewardsNotifier.sol";
import {IKwenta} from "./interfaces/IKwenta.sol";
import {IRewardEscrowV2} from "./interfaces/IRewardEscrowV2.sol";
import {IStakingRewardsV2} from "./interfaces/IStakingRewardsV2.sol";
import {ISupplySchedule} from "./interfaces/ISupplySchedule.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract StakingRewardsNotifier is Ownable2Step, IStakingRewardsNotifier {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice kwenta interface
    IKwenta public immutable kwenta;

    /// @notice supply schedule contract
    ISupplySchedule public immutable supplySchedule;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice rewards staking contract
    IStakingRewardsV2 public stakingRewardsV2;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructor function for StakingRewardsNotifier contract
    /// @param _contractOwner: address of the contract owner
    /// @param _kwenta: address of the Kwenta contract
    /// @param _supplySchedule: address of the SupplySchedule contract
    constructor(address _contractOwner, address _kwenta, address _supplySchedule) {
        if (_contractOwner == address(0) || _kwenta == address(0) || _supplySchedule == address(0))
        {
            revert ZeroAddress();
        }
        kwenta = IKwenta(_kwenta);
        supplySchedule = ISupplySchedule(_supplySchedule);

        // transfer ownership
        _transferOwnership(_contractOwner);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice access control modifier for supplySchedule
    modifier onlySupplySchedule() {
        _onlySupplySchedule();
        _;
    }

    function _onlySupplySchedule() internal view {
        if (msg.sender != address(supplySchedule)) revert OnlySupplySchedule();
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStakingRewardsNotifier
    function setStakingRewardsV2(address _stakingRewardsV2) external onlyOwner {
        if (_stakingRewardsV2 == address(0)) revert ZeroAddress();
        stakingRewardsV2 = IStakingRewardsV2(_stakingRewardsV2);
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStakingRewardsNotifier
    function notifyRewardAmount(uint256 mintedAmount) external onlySupplySchedule {
        /// @dev delete mintedAmount because it is not used but cannot be removed from the function signature
        /// as it is called by SupplySchedule which is immutable and expects to pass this value
        /// instead currentBalance is used
        delete mintedAmount;
        uint256 currentBalance = kwenta.balanceOf(address(this));
        kwenta.transfer(address(stakingRewardsV2), currentBalance);
        stakingRewardsV2.notifyRewardAmount(currentBalance);
    }
}
