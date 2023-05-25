// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StakingRewardsV2} from "./StakingRewardsV2.sol";
import {RewardEscrowV2} from "./RewardEscrowV2.sol";
import {IKwenta} from "./interfaces/IKwenta.sol";
import {ITokenDistributor} from "./interfaces/ITokenDistributor.sol";

contract TokenDistributor is ITokenDistributor {
    /// @notice event for a new checkpoint
    event CheckpointToken(uint time, uint tokens);

    /// @notice event for a epoch that gets claimed
    event EpochClaim(address user, uint epoch, uint tokens);

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
    //todo: look at that^

    /// @notice the week offset in seconds
    uint public offset;

    constructor(
        address _kwenta,
        address _stakingRewardsV2,
        address _rewardEscrowV2,
        uint _offset
    ) {
        kwenta = IKwenta(_kwenta);
        stakingRewardsV2 = StakingRewardsV2(_stakingRewardsV2);
        rewardEscrowV2 = RewardEscrowV2(_rewardEscrowV2);

        /// @notice custom start day (startTime + param)
        if (_offset > 6) {
            revert OffsetTooBig();
        }
        offset = _offset * 86400;
        uint _t = _startOfWeek(block.timestamp);
        startTime = _t;
        lastCheckpoint = _t;
    }

    function checkpointToken() public override {
        uint tokenBalance = kwenta.balanceOf(address(this));
        uint toDistribute = tokenBalance - lastTokenBalance;
        lastTokenBalance = tokenBalance;

        uint t = lastCheckpoint;
        uint sinceLast = block.timestamp - t;
        lastCheckpoint = block.timestamp;
        uint thisWeek = _startOfWeek(t);
        uint nextWeek = 0;

        /// @dev Loop for potential missed weeks
        /// iterates until caught up, unlikely to go to 52
        for (uint i = 0; i < 52; i++) {
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
    function claimEpoch(address to, uint epochNumber) public override {
        /// @dev if more than 24 hours from last checkpoint OR if it is the first
        /// claim of the week. second condition is so that the end of a week always
        /// gets updated before its claimed.
        if (
            (block.timestamp - lastCheckpoint > 1 days) ||
            ((block.timestamp - _startOfWeek(lastCheckpoint)) > 1 weeks) //todo: break up if statement
        ) {
            checkpointToken();
        }
        /// @dev if the end of the epoch is > current time, revert
        if (_startOfEpoch(epochNumber) + 1 weeks > block.timestamp) {
            revert CannotClaimYet();
        }
        if (claimedEpochs[to][epochNumber] == true) {
            revert CannotClaimTwice();
        }
        uint256 totalStaked = stakingRewardsV2.totalSupplyAtTime(
            _startOfEpoch(epochNumber)
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

        emit EpochClaim(to, epochNumber, proportionalFees);
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
    ) public view override returns (uint256) {
        uint epochStart = _startOfEpoch(epochNumber);
        uint256 userStaked = stakingRewardsV2.balanceAtTime(to, epochStart);
        uint256 totalStaked = stakingRewardsV2.totalSupplyAtTime(epochStart);
        if (totalStaked == 0) {
            return totalStaked;
        }
        uint256 proportionalFees = ((tokensPerEpoch[epochStart] * userStaked) /
            totalStaked);

        return proportionalFees;
    }

    /// @notice function for calculating the start of a week with an offset
    function _startOfWeek(uint timestamp) internal view returns (uint) {
        return (((timestamp - offset) / 1 weeks) * 1 weeks) + offset;
    }

    /// @notice function for calculating the start of an epoch
    function _startOfEpoch(uint epochNumber) internal view returns (uint) {
        return (epochNumber * 1 weeks) + startTime;
    }

}
