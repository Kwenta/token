// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StakingRewardsV2} from "./StakingRewardsV2.sol";
import {RewardEscrowV2} from "./RewardEscrowV2.sol";
import {IKwenta} from "./interfaces/IKwenta.sol";
import {ITokenDistributor} from "./interfaces/ITokenDistributor.sol";

contract TokenDistributor is ITokenDistributor {
    /// @notice represents the status of if a person already
    /// claimed their epoch
    mapping(address => mapping(uint => bool)) internal claimedEpochs;

    /// @notice kwenta interface
    IKwenta private kwenta;

    /// @notice rewards staking contract
    StakingRewardsV2 private stakingRewardsV2;

    /// @notice escrow contract which holds (and may stake) reward tokens
    RewardEscrowV2 private rewardEscrowV2;

    /// @notice last recorded balance of KWENTA in contract
    uint internal lastTokenBalance;

    /// @notice last checkpoint time
    uint internal lastCheckpoint;

    /// @notice starting week of deployment
    uint internal startTime;

    /// @notice array for tokens allocated to each epoch
    uint[1000000000000000] internal tokensPerEpoch;

    /// @notice the week offset in seconds
    uint internal offset;

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
        offset = _offset * 1 days;
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
        uint thisWeek = _startOfWeek(previousCheckpoint);
        uint nextWeek = 0;

        /// @dev Loop for potential missed weeks
        /// iterates until caught up, unlikely to go to 52
        for (uint i = 0; i < 52; i++) {
            nextWeek = thisWeek + 1 weeks;

            if (block.timestamp < nextWeek) {
                /// @dev if in the current week
                if (sinceLast == 0 && block.timestamp == previousCheckpoint) {
                    /// @dev If no time change since last checkpoint just add new tokens
                    /// that may have been deposited (same block)
                    tokensPerEpoch[thisWeek] += toDistribute;
                } else {
                    /// @dev In the event that toDistribute contains tokens
                    /// for multiple weeks we take the remaining portion
                    tokensPerEpoch[thisWeek] +=
                        (toDistribute *
                            (block.timestamp - previousCheckpoint)) /
                        sinceLast;
                }
                break;
            } else {
                /// @dev If passed weeks missed
                if (sinceLast == 0 && nextWeek == previousCheckpoint) {
                    tokensPerEpoch[thisWeek] += toDistribute;
                } else {
                    /// @dev Store proportion of tokens for this week in the past
                    tokensPerEpoch[thisWeek] +=
                        (toDistribute * (nextWeek - previousCheckpoint)) /
                        sinceLast;
                }
            }
            previousCheckpoint = nextWeek;
            thisWeek = nextWeek;
        }
        emit CheckpointToken(block.timestamp, toDistribute);
    }

    /// @inheritdoc ITokenDistributor
    function claimEpoch(address to, uint epochNumber) public override {
        _checkpointWhenReady();
        _isEpochReady(epochNumber);
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

    /// @inheritdoc ITokenDistributor
    function claimMany(address to, uint[] memory epochs) public {
        for (uint i = 0; i < epochs.length; i++) {
            uint epochNumber = epochs[i];
            claimEpoch(to, epochNumber);
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
        uint256 proportionalFees = tokensPerEpoch[epochStart] * userStaked /
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
        if ((block.timestamp - lastCheckpoint > 1 days)) {
            checkpointToken();
        }
        /// @dev if it is the first claim of the week then checkpoint.
        /// this condition is so that the end of a week always
        /// gets updated before its claimed (even if < 24 hrs)
        if ((block.timestamp - _startOfWeek(lastCheckpoint)) > 1 weeks) {
            checkpointToken();
        }
    }

    /// @notice function for determining if the epoch being claimed
    /// is the current epoch or has not happened yet
    function _isEpochReady(uint epochNumber) internal {
        /// @dev if the end of the epoch is > current time, revert
        if (_startOfEpoch(epochNumber) + 1 weeks > block.timestamp) {
            revert CannotClaimYet();
        }
    }
}
