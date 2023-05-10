// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StakingRewardsV2} from "./StakingRewardsV2.sol";
import {IKwenta} from "./interfaces/IKwenta.sol";

contract TokenDistributor {
    struct Distribution {
        uint epochStartBlockNumber;
        uint totalFees;
        uint totalStakedAmount;
    }

    mapping(uint => Distribution) public distributionEpochs;

    IKwenta public kwenta;

    /// @notice Counter for new epochs
    /// @notice initialized to 0
    uint256 public epoch;

    StakingRewardsV2 public stakingRewardsV2;

    constructor(address _kwenta, address _stakingRewardsV2) {
        kwenta = IKwenta(_kwenta);
        epoch = 0;
        stakingRewardsV2 = StakingRewardsV2(_stakingRewardsV2);
    }

    /// @notice  creates a new Distribution entry at the current block
    /// @notice  can only be called once per week
    function newDistribution() public {
        ///@dev [epoch - 1] to get the start of last weeks epoch
        require(
            block.timestamp >=
                (distributionEpochs[epoch - 1].epochStartBlockNumber + 1 weeks),
            "TokenDistributor: Last week's epoch has not ended yet"
        );

        //0's are placeholders
        //calculate the total fees for THIS epoch (ignore unclaimed fees from previous epochs)
        //then insert to .totalFees
        Distribution memory distribution = Distribution(
            block.timestamp,
            0,
            stakingRewardsV2.totalSupply()
        );

        distributionEpochs[epoch] = distribution;

        epoch++;
    }

    /// @notice this function will fetch StakingRewardsV2 to see what their staked balance was at the start of the epoch
    /// @notice then calculate proportional fees and transfer to user
    function claimDistribution(address to, uint epochNumber) public {
        //require the epoch they're claiming is ready to claim

        uint256 totalStaked = distributionEpochs[epochNumber].totalStakedAmount;
        uint256 userStaked = stakingRewardsV2.balanceAtBlock(
            msg.sender,
            distributionEpochs[epochNumber].epochStartBlockNumber
        );
        uint256 fees = distributionEpochs[epochNumber].totalFees;
        uint256 proportionalFees = (userStaked / totalStaked) * fees;

        kwenta.transferFrom(address(this), to, proportionalFees);

        /// @dev if this is the first claim of a new epoch, call newDistribution to start a new epoch
        if (
            block.timestamp >=
            (distributionEpochs[epoch].epochStartBlockNumber + 1 weeks)
        ) {
            newDistribution();
        }
    }
}
