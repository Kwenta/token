// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StakingRewardsV2} from "./StakingRewardsV2.sol";
import {RewardEscrowV2} from "./RewardEscrowV2.sol";
import {IKwenta} from "./interfaces/IKwenta.sol";

contract TokenDistributor {
    /// @notice event for tracking new epochs
    event NewEpochCreated(uint block, uint epoch);

    /// @notice tracks block, previously claimed fees,
    /// kwenta balance of this contract, and total
    /// staked amount in StakingRewardsV2
    struct Distribution {
        uint epochStartBlockNumber;
        uint previouslyClaimedFees;
        uint kwentaStartOfEpoch;
        uint totalStakedAmount;
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

    /// @notice rewards staking contract
    StakingRewardsV2 public stakingRewardsV2;

    /// @notice escrow contract which holds (and may stake) reward tokens
    RewardEscrowV2 public rewardEscrowV2;

    constructor(
        address _kwenta,
        address _stakingRewardsV2,
        address _rewardEscrowV2
    ) {
        kwenta = IKwenta(_kwenta);
        epoch = 0;
        stakingRewardsV2 = StakingRewardsV2(_stakingRewardsV2);
        rewardEscrowV2 = RewardEscrowV2(_rewardEscrowV2);
    }

    /// @notice  creates a new Distribution entry at the current block,
    /// can only be called once per week
    function newDistribution() public {
        ///@dev [epoch - 1] to get the start of last weeks epoch
        if (epoch > 0) {
            require(
                block.timestamp >=
                    (distributionEpochs[epoch - 1].epochStartBlockNumber +
                        1 weeks),
                "TokenDistributor: Last week's epoch has not ended yet"
            );
        }

        Distribution memory distribution = Distribution(
            block.timestamp,
            claimedFees,
            kwenta.balanceOf(address(this)),
            stakingRewardsV2.totalSupply()
        );

        distributionEpochs[epoch] = distribution;

        emit NewEpochCreated(block.timestamp, epoch);

        epoch++;
    }

    /// @notice this function will fetch StakingRewardsV2 to see what their staked balance
    /// was at the start of the epoch then calculate proportional fees and transfer to user
    function claimDistribution(address to, uint epochNumber) public {
        /// @dev if this is the first claim of a new epoch, call newDistribution to start a new epoch
        if (
            block.timestamp >=
            (distributionEpochs[epoch - 1].epochStartBlockNumber + 604800)
        ) {
            newDistribution();
        }

        require(
            epochNumber < (epoch - 1),
            "TokenDistributor: Epoch is not ready to claim"
        );

        require(
            claimedEpochs[to][epochNumber] != true,
            "TokenDistributor: You already claimed this epoch's fees"
        );

        uint256 totalStaked = distributionEpochs[epochNumber].totalStakedAmount;
        require(
            totalStaked != 0,
            "TokenDistributor: Nothing was staked in StakingRewardsV2 that epoch"
        );
        uint256 userStaked = stakingRewardsV2.balanceAtBlock(
            to,
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

        claimedFees += proportionalFees;
        claimedEpochs[to][epochNumber] = true;

        kwenta.approve(address(rewardEscrowV2), proportionalFees);
        rewardEscrowV2.createEscrowEntry(to, proportionalFees, 52 weeks, 90);
    }
}