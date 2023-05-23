// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StakingRewardsV2} from "./StakingRewardsV2.sol";
import {RewardEscrowV2} from "./RewardEscrowV2.sol";
import {IKwenta} from "./interfaces/IKwenta.sol";

contract TokenDistributor {
    /// @notice event for a new checkpoint
    event CheckpointToken(uint time, uint tokens);

    /// @notice error when user tries to create a new distribution too soon
    error LastEpochHasntEnded();

    /// @notice error when user tries to claim a distribution too soon
    error CannotClaimYet();

    /// @notice error when user tries to claim in new distribution block
    error CannotClaimInNewEpochBlock();

    /// @notice error when user tries to claim for same epoch twice
    error CannotClaimTwice();

    /// @notice error when user tries to claim for epoch with 0 staking
    error NothingStakedThatEpoch();

    /// @notice error when user tries to claim 0 fees
    error CannotClaim0Fees();

    /// @notice represents the status of if a person already
    /// claimed their epoch
    mapping(address => mapping(uint => bool)) public claimedEpochs;

    /// @notice kwenta interface
    IKwenta public kwenta;

    /// @notice rewards staking contract
    StakingRewardsV2 public stakingRewardsV2;

    /// @notice escrow contract which holds (and may stake) reward tokens
    RewardEscrowV2 public rewardEscrowV2;

    /// @notice last recorded balance of KWENTA in contract
    uint public lastTokenBalance;

    /// @notice last checkpoint time
    uint public lastCheckpoint;

    /// @notice starting week of deployment
    uint public startTime;

    /// @notice array for tokens allocated to each epoch
    uint[1000000000000000] public tokensPerEpoch;

    constructor(
        address _kwenta,
        address _stakingRewardsV2,
        address _rewardEscrowV2
    ) {
        kwenta = IKwenta(_kwenta);
        stakingRewardsV2 = StakingRewardsV2(_stakingRewardsV2);
        rewardEscrowV2 = RewardEscrowV2(_rewardEscrowV2);

        //todo: add param for custom start day (startTime + param)
        uint _t = (block.timestamp / 1 weeks) * 1 weeks;
        startTime = _t;
        lastCheckpoint = _t;
    }

    function checkpointToken() public {
        uint tokenBalance = kwenta.balanceOf(address(this));
        uint toDistribute = tokenBalance - lastTokenBalance;
        lastTokenBalance = tokenBalance;

        uint t = lastCheckpoint;
        uint sinceLast = block.timestamp - t;
        lastCheckpoint = block.timestamp;
        uint thisWeek = (t / 1 weeks) * 1 weeks;
        uint nextWeek = 0;

        /// @dev Loop for potential missed weeks
        /// iterates until caught up, unlikely to go to 20
        for (uint i = 0; i < 20; i++) {
            nextWeek = thisWeek + 1 weeks;

            if (block.timestamp < nextWeek) {
                /// @dev if in the current week
                if (sinceLast == 0 && block.timestamp == t) {
                    /// @dev If no time change since last checkpoint just add new tokens
                    /// that may have been deposited (same block)
                    tokensPerEpoch[thisWeek] += toDistribute;
                } else {
                    /// @dev In the event that toDistribute contains tokens
                    /// for multiple weeks we take the remaining portion
                    tokensPerEpoch[thisWeek] +=
                        (toDistribute * (block.timestamp - t)) /
                        sinceLast;
                }
                break;
            } else {
                /// @dev If passed weeks missed
                if (sinceLast == 0 && nextWeek == t) {
                    tokensPerEpoch[thisWeek] += toDistribute;
                } else {
                    /// @dev Store proportion of tokens for this week in the past
                    tokensPerEpoch[thisWeek] +=
                        (toDistribute * (nextWeek - t)) /
                        sinceLast;
                }
            }
            t = nextWeek;
            thisWeek = nextWeek;
        }
        emit CheckpointToken(block.timestamp, toDistribute);
    }

    /// @notice this function will fetch StakingRewardsV2 to see what their staked balance
    /// was at the start of the epoch then calculate proportional fees and transfer to user
    function claimEpoch(address to, uint epochNumber) public returns (uint256) {
        /// @dev if more than 24 hours from last checkpoint OR if it is the first
        /// claim of the week. second condition is so that the end of a week always
        /// gets updated before its claimed.
        if (
            (block.timestamp - lastCheckpoint > 86400) ||
            ((block.timestamp - (lastCheckpoint / 1 weeks * 1 weeks)) > 604800)
        ) {
            checkpointToken();
        }
        /// @dev if the end of the epoch is > current time, revert
        if ((epochNumber * 1 weeks) + 1 weeks + startTime > block.timestamp) {
            revert CannotClaimYet();
        }
        //todo: double check if i need to require its not the same second as new epoch
        if (claimedEpochs[to][epochNumber] == true) {
            revert CannotClaimTwice();
        }
        uint256 totalStaked = stakingRewardsV2.totalSupplyAtTime(
            (epochNumber * 1 weeks) + startTime
        );
        if (totalStaked == 0) {
            revert NothingStakedThatEpoch();
        }

        uint256 proportionalFees = calculateEpochFees(to, epochNumber);

        if (proportionalFees == 0) {
            revert CannotClaim0Fees();
        }

        lastTokenBalance -= proportionalFees;
        claimedEpochs[to][epochNumber] = true;

        kwenta.approve(address(rewardEscrowV2), proportionalFees);
        rewardEscrowV2.createEscrowEntry(to, proportionalFees, 52 weeks, 90);

        return proportionalFees;
    }

    /// @notice claim many epochs at once
    function claimMany(address to, uint[] memory epochs) public {
        for (uint i = 0; i < epochs.length; i++) {
            uint epochNumber = epochs[i];
            claimEpoch(to, epochNumber);
        }
    }

    /// @notice view function for calculating fees for an epoch
    function calculateEpochFees(
        address to,
        uint epochNumber
    ) public view returns (uint256) {
        uint thisWeek = (epochNumber * 1 weeks) + startTime;
        uint256 userStaked = stakingRewardsV2.balanceAtTime(to, thisWeek);
        uint256 totalStaked = stakingRewardsV2.totalSupplyAtTime(thisWeek);
        if (totalStaked == 0) {
            return totalStaked;
        }
        uint256 proportionalFees = ((tokensPerEpoch[thisWeek] * userStaked) /
            totalStaked);

        return proportionalFees;
    }
}
