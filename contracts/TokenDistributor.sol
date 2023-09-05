// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IKwenta} from "./interfaces/IKwenta.sol";
import {ITokenDistributor} from "./interfaces/ITokenDistributor.sol";
import {IRewardEscrowV2} from "./interfaces/IRewardEscrowV2.sol";
import {IStakingRewardsV2} from "./interfaces/IStakingRewardsV2.sol";

contract TokenDistributor is ITokenDistributor {
    /// @inheritdoc ITokenDistributor
    mapping(uint => uint) public tokensPerEpoch;

    /// @notice represents the status of if a person already
    /// claimed their epoch
    mapping(address => mapping(uint => bool)) internal claimedEpochs;

    /// @notice kwenta interface
    IKwenta internal immutable kwenta;

    /// @notice rewards staking contract
    IStakingRewardsV2 internal immutable stakingRewardsV2;

    /// @notice escrow contract which holds (and may stake) reward tokens
    IRewardEscrowV2 internal immutable rewardEscrowV2;

    /// @notice last recorded balance of KWENTA in contract
    uint internal lastTokenBalance;

    /// @notice last checkpoint time
    uint internal lastCheckpoint;

    /// @notice starting week of deployment
    uint internal immutable startTime;

    /// @notice the week offset in seconds
    uint internal immutable offset;

    /// @notice max amount of days the epoch can be offset by
    uint internal constant MAX_OFFSET_DAYS = 6;

    /// @notice weeks in a year
    uint internal constant WEEKS_IN_YEAR = 52;

    /// @notice constructs the TokenDistributor contract
    /// and sets startTime
    /// @param _kwenta: address of the kwenta contract
    /// @param _stakingRewardsV2: address of the stakingRewardsV2 contract
    /// @param _rewardEscrowV2: address of the rewardEscrowV2 contract
    constructor(
        address _kwenta,
        address _stakingRewardsV2,
        address _rewardEscrowV2,
        uint daysToOffsetBy
    ) {
        if (
            _kwenta == address(0) ||
            _stakingRewardsV2 == address(0) ||
            _rewardEscrowV2 == address(0)
        ) {
            revert ZeroAddress();
        }
        kwenta = IKwenta(_kwenta);
        stakingRewardsV2 = IStakingRewardsV2(_stakingRewardsV2);
        rewardEscrowV2 = IRewardEscrowV2(_rewardEscrowV2);

        /// @notice custom start day (startTime + daysToOffsetBy)
        if (daysToOffsetBy > MAX_OFFSET_DAYS) {
            revert OffsetTooBig();
        }
        offset = daysToOffsetBy * 1 days;
        uint startOfThisWeek = _startOfWeek(block.timestamp);
        startTime = startOfThisWeek;
        lastCheckpoint = startOfThisWeek;
    }

    /// @inheritdoc ITokenDistributor
    function checkpointToken() public override {
        uint tokenBalance = kwenta.balanceOf(address(this));
        uint toDistribute = tokenBalance - lastTokenBalance;
        lastTokenBalance = tokenBalance;

        uint previousCheckpoint = lastCheckpoint;
        uint sinceLast = block.timestamp - previousCheckpoint;
        lastCheckpoint = block.timestamp;
        /// @dev this/nextWeek is for iterating through time
        uint thisWeek = _startOfWeek(previousCheckpoint);
        uint nextWeek = 0;

        /// @dev Loop for potential missed weeks
        /// iterates until caught up, unlikely to go to 52 weeks
        for (uint i = 0; i < WEEKS_IN_YEAR; ) {
            nextWeek = thisWeek + 1 weeks;
            uint thisEpoch = _epochFromTimestamp(thisWeek);
            if (block.timestamp < nextWeek) {
                /// @dev if in the current week
                if (sinceLast == 0) {
                    /// @dev If no time change since last checkpoint just add new tokens
                    /// that may have been deposited (same block)
                    tokensPerEpoch[thisEpoch] += toDistribute;
                } else {
                    /// @dev In the event that toDistribute contains tokens
                    /// for multiple weeks we take the remaining portion
                    tokensPerEpoch[thisEpoch] +=
                        (toDistribute *
                            (block.timestamp - previousCheckpoint)) /
                        sinceLast;
                }
                break;
            } else {
                /// @dev If passed weeks missed
                /// @dev Store proportion of tokens for this week in the past
                tokensPerEpoch[thisEpoch] +=
                    (toDistribute * (nextWeek - previousCheckpoint)) /
                    sinceLast;
            }
            previousCheckpoint = nextWeek;
            thisWeek = nextWeek;
            unchecked {
                ++i;
            }
        }
        emit CheckpointToken(block.timestamp, toDistribute);
    }

    /// @inheritdoc ITokenDistributor
    function claimEpoch(address to, uint epochNumber) public override {
        _checkpointWhenReady();
        _claimEpoch(to, epochNumber);
    }

    /// @notice internal claimEpoch function
    function _claimEpoch(address to, uint epochNumber) internal {
        _isEpochReady(epochNumber);
        mapping(uint256 => bool) storage claimedEpochsTo = claimedEpochs[to];
        if (claimedEpochsTo[epochNumber]) {
            revert CannotClaimTwice();
        }
        claimedEpochsTo[epochNumber] = true;

        uint256 proportionalFees = calculateEpochFees(to, epochNumber);

        if (proportionalFees == 0) {
            revert CannotClaim0Fees();
        }

        lastTokenBalance -= proportionalFees;

        kwenta.approve(address(rewardEscrowV2), proportionalFees);
        rewardEscrowV2.createEscrowEntry(to, uint128(proportionalFees),
        rewardEscrowV2.DEFAULT_DURATION(),
        rewardEscrowV2.DEFAULT_EARLY_VESTING_FEE());

        emit EpochClaim(to, epochNumber, proportionalFees);
    }

    /// @inheritdoc ITokenDistributor
    function claimMany(address to, uint[] calldata epochs) public {
        _checkpointWhenReady();
        uint256 length = epochs.length;
        for (uint i = 0; i < length; ) {
            uint epochNumber = epochs[i];
            _claimEpoch(to, epochNumber);
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc ITokenDistributor
    function calculateEpochFees(
        address to,
        uint epochNumber
    ) public view override returns (uint256) {
        uint epochStart = _startOfEpoch(epochNumber);
        uint256 userStaked = stakingRewardsV2.balanceAtTime(to, epochStart);
        uint256 totalStaked = stakingRewardsV2.totalSupplyAtTime(epochStart);
        if (totalStaked == 0) {
            return 0;
        }
        uint256 proportionalFees = (tokensPerEpoch[epochNumber] * userStaked) /
            totalStaked;

        return proportionalFees;
    }

    /// @notice function for calculating the start of a week with an offset
    function _startOfWeek(uint timestamp) internal view returns (uint) {
        /// @dev remove offset then truncate and then put offset back because
        /// you cannot truncate to an "offset" time - always truncates to the start
        /// of unix time -
        /// @dev this also prevents false truncation: without removing then adding
        /// offset, the end of a normal week but before the end of an offset week
        /// will get truncated to the next normal week even though the true week (offset)
        /// has not ended yet
        return (((timestamp - offset) / 1 weeks) * 1 weeks) + offset;
    }

    /// @notice function for calculating the start of an epoch
    function _startOfEpoch(uint epochNumber) internal view returns (uint) {
        return (epochNumber * 1 weeks) + startTime;
    }

    /// @notice function for determining if a checkpoint is necessary
    function _checkpointWhenReady() internal {
        /// @dev if more than 24 hours from last checkpoint
        /// @dev OR if it is the first claim of the week then checkpoint.
        /// this condition is so that the end of a week always
        /// gets updated before its claimed (even if < 24 hrs)
        if (
            block.timestamp - lastCheckpoint > 1 days ||
            block.timestamp - _startOfWeek(lastCheckpoint) > 1 weeks
        ) {
            checkpointToken();
        }
    }

    /// @notice function for determining if the epoch being claimed
    /// is the current epoch or has not happened yet
    function _isEpochReady(uint epochNumber) internal view {
        /// @dev if the end of the epoch is > current time, revert
        if (_startOfEpoch(epochNumber) + 1 weeks > block.timestamp) {
            revert CannotClaimYet();
        }
    }

    /// @notice function for getting the epoch number
    /// from the timestamp start of a week
    function _epochFromTimestamp(uint timestamp) internal view returns (uint) {
        return (_startOfWeek(timestamp) - startTime) / 1 weeks;
    }
}
