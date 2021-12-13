// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IStakingRewards {
    // Views

    function escrowedBalanceOf(address account) external view returns (uint256);

    function totalRewardScore() external view returns (uint256);
    
    function stakedBalanceOf(address account) external view returns (uint256);
    
    function totalBalanceOf(address account) external view returns (uint256);

    function rewardScoreOf(address account) external view returns (uint256);

    function rewardPerRewardScoreOfEpoch(uint256 _epoch) external view returns (uint256);

    function feesPaidBy(address account) external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function rewardsToken() external view returns (IERC20);

    // Mutative

    function setWeightsRewardScore(int256 _weightStaking, int256 _weightFees) external;

    function setPercentageRewards(uint256 _percentageStaking, uint256 _percentageTrading) external;

    function updateTraderScore(address _trader, uint256 _newFeesPaid) external;

    function exit() external;

    function getReward() external;

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function setRewardNEpochs(uint256 reward, uint256 nEpochs) external;

}