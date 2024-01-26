// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITokenDistributor} from "./interfaces/ITokenDistributor.sol";
import {IStakingRewardsV2} from "./interfaces/IStakingRewardsV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

contract TokenDistributor is ITokenDistributor {
    using BitMaps for BitMaps.BitMap;

    /// @dev BitMap for storing claimed epochs
    mapping(address to => BitMaps.BitMap claimedEpochs) internal _claimedEpochsBitMap;  

    /// @inheritdoc ITokenDistributor
    mapping(uint => uint) public tokensPerEpoch;

    /// @notice token to distribute
    IERC20 public immutable rewardsToken;

    /// @notice rewards staking contract
    IStakingRewardsV2 public immutable stakingRewardsV2;

    /// @notice last recorded balance of rewards tokens in contract
    uint public lastTokenBalance;

    /// @notice last checkpoint time
    uint public lastCheckpoint;

    /// @notice starting week of deployment
    uint public immutable startTime;

    /// @notice the week offset in seconds
    uint public immutable offset;

    /// @notice max amount of days the epoch can be offset by
    uint public constant MAX_OFFSET_DAYS = 6;

    /// @notice weeks in a year
    uint public constant WEEKS_IN_YEAR = 52;

    /// @notice constructs the TokenDistributor contract
    /// and sets startTime
    /// @param _rewardsToken: address of the rewards token contract
    /// @param _stakingRewardsV2: address of the stakingRewardsV2 contract
    /// @param _daysToOffsetBy: the number of days to offset the epoch by
    constructor(
        address _rewardsToken,
        address _stakingRewardsV2,
        uint _daysToOffsetBy
    ) {
        if (
            _rewardsToken == address(0) ||
            _stakingRewardsV2 == address(0)
        ) {
            revert ZeroAddress();
        }
        rewardsToken = IERC20(_rewardsToken);
        stakingRewardsV2 = IStakingRewardsV2(_stakingRewardsV2);

        /// @notice custom start day (startTime + daysToOffsetBy)
        if (_daysToOffsetBy > MAX_OFFSET_DAYS) {
            revert OffsetTooBig();
        }
        offset = _daysToOffsetBy * 1 days;
        uint startOfThisWeek = _startOfWeek(block.timestamp);
        startTime = startOfThisWeek;
        lastCheckpoint = startOfThisWeek;
    }

    /// @inheritdoc ITokenDistributor
    function checkpointToken() public override {
        uint tokenBalance = rewardsToken.balanceOf(address(this));
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
        uint256 proportionalFees = _claimEpoch(to, epochNumber);

        lastTokenBalance -= proportionalFees;

        rewardsToken.transfer(to, proportionalFees);
    }

    /// @notice internal claimEpoch function
    function _claimEpoch(address to, uint epochNumber) internal returns (uint256 proportionalFees) {
        _isEpochReady(epochNumber);
        if (claimedEpoch(to, epochNumber)) {
            revert CannotClaimTwice();
        }
        _claimedEpochsBitMap[to].set(epochNumber);

        proportionalFees = calculateEpochFees(to, epochNumber);

        if (proportionalFees == 0) {
            revert CannotClaim0Fees();
        }

        emit EpochClaim(to, epochNumber, proportionalFees);
    }

    /// @inheritdoc ITokenDistributor
    function claimMany(address to, uint[] calldata epochs) public {
        _checkpointWhenReady();
        uint256 length = epochs.length;
        uint256 totalProportionalFees;
        for (uint i; i < length; ) {
            uint epochNumber = epochs[i];
            totalProportionalFees += _claimEpoch(to, epochNumber);
            unchecked {
                ++i;
            }
        }

        lastTokenBalance -= totalProportionalFees;

        rewardsToken.transfer(to, totalProportionalFees);
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

    /// @inheritdoc ITokenDistributor
    function claimedEpoch(address to, uint epochNumber) public view override returns (bool) {
        return _claimedEpochsBitMap[to].get(epochNumber);
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
