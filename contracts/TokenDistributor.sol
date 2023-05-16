// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StakingRewardsV2} from "./StakingRewardsV2.sol";
import {RewardEscrowV2} from "./RewardEscrowV2.sol";
import {IKwenta} from "./interfaces/IKwenta.sol";

contract TokenDistributor {
    /// @notice event for tracking new epochs
    event NewEpochCreated(uint block, uint epoch);

    /// @notice error when user tries to create a new distribution too soon
    error LastEpochHasntEnded();

    /// @notice error when user tries to claim a distribution too soon
    error CannotClaimYet();

    /// @notice error when user tries to claim in new distribution block
    error CannotClaimInNewDistributionBlock();

    /// @notice error when user tries to claim for same epoch twice
    error CannotClaimTwice();

    /// @notice error when user tries to claim for epoch with 0 staking
    error NothingStakedThatEpoch();

    /// @notice error when user tries to claim 0 fees
    error CannotClaim0Fees();

    /// @notice tracks block, previously claimed fees,
    /// kwenta balance of this contract, and total
    /// staked amount in StakingRewardsV2
    struct Distribution {
        uint epochStartBlockNumber;
        uint epochStartTime;
        uint previouslyClaimedFees;
        uint kwentaStartOfEpoch;
    }

    /// @notice tracks the distribution for each epoch
    mapping(uint => Distribution) public distributionEpochs;

    /// @notice represents the status of if a person already
    /// claimed their epoch
    mapping(address => mapping(uint => bool)) public claimedEpochs;

    /// @notice kwenta interface
    IKwenta public kwenta;

    /// @notice Counter for new epochs (starts at 0)
    uint256 public epoch;

    /// @notice running total for claimed fees
    uint256 public claimedFees;

    /// @notice start time of the first epoch
    uint256 public startDate;

    /// @notice rewards staking contract
    StakingRewardsV2 public stakingRewardsV2;

    /// @notice escrow contract which holds (and may stake) reward tokens
    RewardEscrowV2 public rewardEscrowV2;

    uint public lastTokenBalance;
    uint public lastTokenTime;
    uint public startTime;
    uint[1000000000000000] public tokensPerEpoch;

    constructor(
        address _kwenta,
        address _stakingRewardsV2,
        address _rewardEscrowV2
    ) {
        kwenta = IKwenta(_kwenta);
        epoch = 0;
        stakingRewardsV2 = StakingRewardsV2(_stakingRewardsV2);
        rewardEscrowV2 = RewardEscrowV2(_rewardEscrowV2);

        uint _t = block.timestamp / 1 weeks * 1 weeks;
        startTime = _t;
        lastTokenTime = _t;
    }


    function _checkpoint_token() internal {
        uint tokenBalance = kwenta.balanceOf(address(this));
        uint to_distribute = tokenBalance - lastTokenBalance;
        lastTokenBalance = tokenBalance;

        uint t = lastTokenTime;
        uint since_last = block.timestamp - t;
        lastTokenTime = block.timestamp;
        uint thisWeek = t / 1 weeks * 1 weeks;
        uint nextWeek = 0;

        for (uint i = 0; i < 20; i++) {
            nextWeek = thisWeek + 1 weeks;
            if (block.timestamp < nextWeek) {
                if (since_last == 0 && block.timestamp == t) {
                    tokensPerEpoch[thisWeek] += to_distribute;
                } else {
                    tokensPerEpoch[thisWeek] += to_distribute * (block.timestamp - t) / since_last;
                }
                break;
            } else {
                if (since_last == 0 && nextWeek == t) {
                    tokensPerEpoch[thisWeek] += to_distribute;
                } else {
                    tokensPerEpoch[thisWeek] += to_distribute * (nextWeek - t) / since_last;
                }
            }
            t = nextWeek;
            thisWeek = nextWeek;
        }
        emit CheckpointToken(block.timestamp, to_distribute);
    }

    function checkpoint_token() external {
        assert(msg.sender == depositor);
        _checkpoint_token();
    }

    /// @notice  creates a new Distribution entry at the current block,
    /// can only be called once per week
    function newDistribution() public {
        ///@dev [epoch - 1] to get the start of last weeks epoch
    
        //todo: after redo: check if can call distribution twice for epoch 0

        //todo: should always happen on the same day
        if (
            epoch > 0 &&
            block.timestamp <
            (distributionEpochs[epoch - 1].epochStartTime + 1 weeks)
        ) {
            revert LastEpochHasntEnded();
        }

        Distribution memory distribution = Distribution(
            block.number,
            block.timestamp,
            claimedFees,
            kwenta.balanceOf(address(this))
        );
        //todo: for a given block it might not be the final value of the block
        distributionEpochs[epoch] = distribution;
        //todo: timestamp is put in for block but that is technically the time
        emit NewEpochCreated(block.timestamp, epoch);

        epoch++;
    }

    /// @notice this function will fetch StakingRewardsV2 to see what their staked balance
    /// was at the start of the epoch then calculate proportional fees and transfer to user
    function claimDistribution(address to, uint epochNumber) public {
        //todo: create a new checkpoint if its been more than 24 hours

        /// @dev if this is the first claim of a new epoch, call newDistribution to start a new epoch
        if (
            block.timestamp >=
            (distributionEpochs[epoch - 1].epochStartTime + 604800)
        ) {
            newDistribution();
        }
        if (epochNumber >= (epoch - 1)) {
            revert CannotClaimYet();
        }
        /// @notice cannot claim in the same block as a new distribution
        /// to prevent attacks in the same block (staking is calculated
        /// at the end of the block)
        //todo: fix require below
        if (
            block.number ==
            distributionEpochs[epochNumber].epochStartBlockNumber
        ) {
            revert CannotClaimInNewDistributionBlock();
        }
        if (claimedEpochs[to][epochNumber] == true) {
            revert CannotClaimTwice();
        }
        uint256 totalStaked = stakingRewardsV2.totalSupplyAtBlock(
            distributionEpochs[epochNumber].epochStartBlockNumber
        );
        if (totalStaked == 0) {
            revert NothingStakedThatEpoch();
        }
        //todo: hookup checkpoint token to here so tokens_per_week is used
        uint256 proportionalFees = calculateFee(to, epochNumber);

        if (proportionalFees == 0) {
            revert CannotClaim0Fees();
        }

        claimedFees += proportionalFees;
        claimedEpochs[to][epochNumber] = true;

        kwenta.approve(address(rewardEscrowV2), proportionalFees);
        rewardEscrowV2.createEscrowEntry(to, proportionalFees, 52 weeks, 90);
    }

    /// @notice view function for calculating fees for an epoch
    function calculateFee(
        address to,
        uint epochNumber
    ) public view returns (uint256) {
        uint256 userStaked = stakingRewardsV2.balanceAtBlock(
            to,
            distributionEpochs[epochNumber].epochStartBlockNumber
        );
        uint256 totalStaked = stakingRewardsV2.totalSupplyAtBlock(
            distributionEpochs[epochNumber].epochStartBlockNumber
        );
        /// @notice epochFees is the fees for that epoch only
        /// @dev calculated by: kwenta at the start of desired epoch + total claimed
        /// fees BEFORE this epoch - kwenta at the start of previous epoch
        uint256 epochFees;
        if (epochNumber == 0) {
            epochFees = distributionEpochs[1].kwentaStartOfEpoch;
        } else {
            epochFees =
                distributionEpochs[epochNumber + 1].kwentaStartOfEpoch +
                distributionEpochs[epochNumber + 1].previouslyClaimedFees -
                distributionEpochs[epochNumber].kwentaStartOfEpoch;
        }

        uint256 proportionalFees = ((epochFees * userStaked) / totalStaked);

        return proportionalFees;
    }
}
