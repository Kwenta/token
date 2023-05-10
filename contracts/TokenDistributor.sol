// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StakingRewardsV2} from "./StakingRewardsV2.sol";
import {IKwenta} from "./interfaces/IKwenta.sol";

contract TokenDistributor {
    struct Distribution {
        uint epochStartBlockNumber;
        uint kwentaStartOfEpoch;
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

        Distribution memory distribution = Distribution(
            block.timestamp,
            kwenta.balanceOf(address(this)),
            stakingRewardsV2.totalSupply()
        );

        distributionEpochs[epoch] = distribution;

        epoch++;
    }

    /// @notice this function will fetch StakingRewardsV2 to see what their staked balance was at the start of the epoch
    /// @notice then calculate proportional fees and transfer to user
    function claimDistribution(address to, uint epochNumber) public {
        /// @dev if this is the first claim of a new epoch, call newDistribution to start a new epoch
        if (
            block.timestamp >=
            (distributionEpochs[epoch].epochStartBlockNumber + 1 weeks)
        ) {
            newDistribution();
        }

        require(
            epochNumber < epoch,
            "TokenDistributor: Epoch is not ready to claim"
        );

        uint256 totalStaked = distributionEpochs[epochNumber].totalStakedAmount;
        uint256 userStaked = stakingRewardsV2.balanceAtBlock(
            msg.sender,
            distributionEpochs[epochNumber].epochStartBlockNumber
        );
        /// @notice epochFees is for the fees for that epoch only
        /// @notice calculated by kwenta at the start of desired epoch - kwenta at the start of previous epoch
        uint256 epochFees = distributionEpochs[epochNumber].kwentaStartOfEpoch -
            distributionEpochs[epochNumber - 1].kwentaStartOfEpoch;
        uint256 proportionalFees = (userStaked / totalStaked) * epochFees;

        kwenta.transferFrom(address(this), to, proportionalFees);
    }
}
