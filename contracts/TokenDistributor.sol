// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StakingRewardsV2} from "./StakingRewardsV2.sol";

contract TokenDistributor {
    struct Distribution {
        uint epochStartBlockNumber;
        uint amount;
        uint totalStakedAmount;
    }

    mapping(uint => Distribution) public distributionEpochs;

    /// @notice Counter for new epochs
    /// @notice initialized to 0
    uint256 public epoch;

    StakingRewardsV2 public stakingRewardsV2;

    constructor(address _stakingRewardsV2) {
        epoch = 0;
        stakingRewardsV2 = StakingRewardsV2(_stakingRewardsV2);
    }

    /// @notice  creates a new Distribution entry at the current block
    /// @notice  can only be called once per week
    //  consider calling this the first time someone tries to claim in a new epoch
    function newDistribution() public {
        ///@dev [epoch - 1] to get the start of last weeks epoch
        require(
            block.timestamp >=
                (distributionEpochs[epoch - 1].epochStartBlockNumber + 1 weeks),
            "TokenDistributor: Distribution for last week has not ended yet"
        );

        //0's are placeholders
        Distribution memory distribution = Distribution(
            block.timestamp,
            0,
            stakingRewardsV2.totalSupply()
        );

        distributionEpochs[epoch] = distribution;

        epoch++;
    }

    /// @notice this function will fetch StakingRewardsV2 to see what their staked balance was at the start of the epoch
    function claimDistribution(address to, uint epochNumber) public {
        //fetch staked balance from StakingRewardsV2
        //probably use balanceOf
        stakingRewardsV2.balanceOf(msg.sender);

        //divy up all fees

        //transfer fees to msg.sender

        //if this is the first claim of a new epoch, call newDistribution to start a new epoch
        //if block.timestamp >= (distributionEpochs[epoch - 1].epochStartBlockNumber + 1 weeks), newDistribution();
    }
}
