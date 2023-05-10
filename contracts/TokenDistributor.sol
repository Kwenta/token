// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//import {StakingRewardsV2} from "./StakingRewardsV2";

contract TokenDistributor {
    struct Distribution {
        uint epochStartBlockNumber;
        uint amount;
        uint totalStakedAmount;
    }

    mapping(uint => Distribution) public distributionEpochs;

    constructor() {}

    /**
     *   creates a new Distribution entry at the current block
     *   can only be called once per week
     *   consider calling this the first time someone tries to claim in a new epoch
     */
    function newDistribution() public {

        //require there hasnt been a distribution this week yet "TokenDistributor: Distribution already happened this week"

        //create new distribution

        //map this to uint (block or sequential distribution epochs?)

    }

    /**
     *   this function will fetch StakingRewardsV2 to see what their
     *   staked balance was at the start of the epoch
     */
    function claimDistribution(address to, uint epochNumber) public {

        //fetch staked balance from StakingRewardsV2

    }
}
