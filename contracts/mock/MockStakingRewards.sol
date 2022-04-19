pragma solidity ^0.8.0;

contract MockStakingRewards {

    function setRewards(uint256 reward) external {
        emit RewardAdded(reward);
    }

    event RewardAdded(uint256 reward);

}
