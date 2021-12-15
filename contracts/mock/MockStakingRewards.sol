pragma solidity ^0.8.0;

contract MockStakingRewards {

    function setRewardNEpochs(uint256 reward, uint256 nEpochs) external {
        emit RewardAdded(reward, nEpochs);
    }

    event RewardAdded(uint256 reward, uint256 nEpochs);

}
