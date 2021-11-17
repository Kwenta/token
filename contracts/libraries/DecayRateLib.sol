// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./FixidityLib.sol";
import "./ExponentLib.sol";
import "./LogarithmLib.sol";

interface IContract {
    function getSlopeChangeAt(uint256 timeSlopeChange) external view returns (uint);
    function getUserSlopeChangeAt(address _account, uint256 timeSlopeChange) external view returns (uint);
    function setNewUserState(address account, uint256 slope, uint256 total, uint256 lastUpdate) external;
    function setNewAccumulatedUser(address account, uint256 accumulated) external;
    function feesPaidBy(address account) external view returns (uint256);
}

/*
* @title External library used to calculate the new and decayed reward scores from StakingRewards contract
*/
library DecayRateLib {
	using FixidityLib for FixidityLib.Fixidity;
    using ExponentLib for FixidityLib.Fixidity;
    using LogarithmLib for FixidityLib.Fixidity;

	uint256 constant public HOUR = 3_600;
	uint256 constant public DAY = 86_400;
	uint256 constant public WEEK = 604_800;
	uint256 constant public MONTH = 2_592_000;

	struct ParamsCalculateDecayedRewardScore {
		uint256 slope;
		uint256 total;
		uint256 roundedFinish;
		uint256 rewardStartedTime;
		uint256 accumulated;
		uint256 lastUpdate;
		uint256 timeToZero;
	}

	struct ParamsCalculateRewardScore {
		address _account;
    	uint256 _prevStakingAmount; 
    	uint256 _newFees;
    	uint256 _totalBalanceUser;
    	uint256 lastSlope;
    	uint256 lastRewardScore;
    	int256 WEIGHT_STAKING;
    	int256 WEIGHT_FEES;
    	int256 INVERSE_WEIGHT_FEES;
    	uint256 timeToZero;
	}

	/*
    * @notice Calculate the decayed value of the total sum of reward scores
    * @param params, struct containing the necessary values for decaying calculations
    * @return new slope of the total reward score
    * @return new total value of the total reward score
    * @return new total accumulated value of the total reward score
    */
	function calculateDecayedTotalRewardScore(
		ParamsCalculateDecayedRewardScore memory params
		) public returns(uint256, uint256, uint256) {
        
        uint256 currentTime = (block.timestamp / DAY) * DAY;

        uint256 lastInteraction = (params.lastUpdate / DAY ) * DAY;

        uint256 nEntries = (currentTime - lastInteraction) / DAY;
        
        // If initial call or calling the same day it has already been calculated, return same state
        if(nEntries == 0 || lastInteraction == 0) {
            return (params.slope, params.total, params.accumulated);
        }
        
        
        uint256 nextSlopeChange = 0;
        uint256 total = params.total;
        uint256 slope = params.slope;
        uint256 accumulated = params.accumulated;

        // Iterate over the last days until reaching the current time, incrementing both the accumulatedTotalRewardScore
        // and updating the totalRewardScore
        for(uint256 i = lastInteraction; i <= Math.min(currentTime, lastInteraction + params.timeToZero); i += DAY) {
            nextSlopeChange = IContract(address(this)).getSlopeChangeAt(i);
            if(nextSlopeChange != 0 || i == Math.min(currentTime, lastInteraction + params.timeToZero)) {
                total = (total - slope * (i - lastInteraction));

                if (lastInteraction < params.rewardStartedTime && i >= params.rewardStartedTime) {
                    accumulated = 0;
                    if(i > params.roundedFinish) {
                        accumulated = total + slope * (i - params.roundedFinish);
                        accumulated = accumulated + slope * (Math.min(i, params.roundedFinish) - params.rewardStartedTime) / 2;
                        accumulated *= (Math.min(i, params.roundedFinish) - params.rewardStartedTime);    
                    } else {
                        accumulated = total + slope * (Math.min(i, params.roundedFinish) - params.rewardStartedTime) / 2;
                        accumulated *= (Math.min(i, params.roundedFinish) - params.rewardStartedTime);
                    }
                } else if (params.roundedFinish > 0) {
                    if (i > params.roundedFinish) {
                            accumulated += (total + slope * (i - params.roundedFinish)) * (params.roundedFinish - lastInteraction) + slope * (params.roundedFinish - lastInteraction) * (params.roundedFinish - lastInteraction) / 2;
                        } else {
                            accumulated += total * (i - lastInteraction) + slope * (i - lastInteraction) * (i - lastInteraction) / 2;
                        }
                }

                lastInteraction = i;
                slope = slope - nextSlopeChange;
            }
        }


        if (slope == 0) {
            total = 0;
        }

		return (slope, total, accumulated);
	}

	/*
    * @notice Calculate the decayed value of a user's reward scores
    * @param account, user to update the information from
    * @param params, struct containing the necessary values for decaying calculations
    * @return new slope of the user's reward score
    * @return new value of the user's reward score
    * @return new accumulated value of the user's reward score
    */
    function calculateDecayedUserRewardScore(
    	address account,
    	ParamsCalculateDecayedRewardScore memory params
    	) public returns(uint256, uint256, uint256) {

        uint256 currentTime = (block.timestamp / DAY) * DAY;
        uint256 lastInteraction = params.lastUpdate;

        uint256 nEntries = (currentTime - lastInteraction) / DAY;

        // If initial call or calling the same day it has already been calculated, return same state
        if(nEntries == 0 || lastInteraction == 0) {
            return (params.slope, params.total, params.accumulated);
        // If more time than _timeToZero has passed, everything is decayed, return 0
        } else if(params.total == 0) {
            return (0, 0, params.accumulated);
        } 
        
        uint256 nextSlopeChange = 0;
        uint256 total = params.total;
        uint256 slope = params.slope;
        uint256 accumulated = params.accumulated;

        // Iterate over the last days until reaching the current time, incrementing both the accumulatedTotalRewardScore
        // and updating the totalRewardScore
        for(uint256 i = lastInteraction; i <= Math.min(currentTime, lastInteraction + params.timeToZero); i += DAY) {
            nextSlopeChange = IContract(address(this)).getUserSlopeChangeAt(account, i);
            if(nextSlopeChange != 0 || i == Math.min(currentTime, lastInteraction + params.timeToZero)) {
                total = (total - slope * (i - lastInteraction));

                if (lastInteraction <= params.rewardStartedTime && i >= params.rewardStartedTime) {
                    if(i > params.roundedFinish) {
                        accumulated = total + slope * (i - params.roundedFinish);
                        accumulated = accumulated + slope * (Math.min(i, params.roundedFinish) - params.rewardStartedTime) / 2;
                        accumulated *= (Math.min(i, params.roundedFinish) - params.rewardStartedTime);    
                    } else {
                        accumulated = total + slope * (Math.min(i, params.roundedFinish) - params.rewardStartedTime) / 2;
                        accumulated *= (Math.min(i, params.roundedFinish) - params.rewardStartedTime);
                    }
                } else if (params.roundedFinish > 0){
                    if (i > params.roundedFinish) {
                            accumulated += (total + slope * (i - params.roundedFinish)) * (params.roundedFinish - lastInteraction) + slope * (params.roundedFinish - lastInteraction) * (params.roundedFinish - lastInteraction) / 2;
                        } else {
                            accumulated += total * (i - lastInteraction) + slope * (i - lastInteraction) * (i - lastInteraction) / 2;
                        }
                }

                
                lastInteraction = i;
                slope = slope - nextSlopeChange;
            }

        }

        if (slope == 0) {
            total = 0;
        }

        return (slope, total, accumulated);
    }

    /*
    * @notice Re-scale the reward score of a user (necessary when changing total balance)
    * @param params, struct containing the necessary values for reward score calculations
    * @param fixidity, pointer to the library to access its functions
    * @return new value of the reward score
    * @return new slope of the reward score
    */
    function scalePreviousRewardScore(
    	ParamsCalculateRewardScore memory _params,
    	FixidityLib.Fixidity storage fixidity
    	) public returns(uint256, uint256){
    	uint256 scalingFactor = uint256(fixidity.power_any(int256(_params._totalBalanceUser * (1e18) / _params._prevStakingAmount), _params.WEIGHT_STAKING));
        uint256 newRewardScore = _params.lastRewardScore * scalingFactor / (1e18);
        uint256 lastSlope = _params.lastSlope;
        lastSlope = lastSlope * scalingFactor / (1e18);

        return (newRewardScore, lastSlope);
    }

    /*
    * @notice Re-calculate the reward score of a user by increasing the fees (necessary when updating trader score)
    * @param params, struct containing the necessary values for reward score calculations
    * @param fixidity, pointer to the library to access its functions
    * @return new value of the reward score
    * @return new slope of the reward score
    */
    function increaseFeesRewardScore(
    	ParamsCalculateRewardScore memory _params,
    	FixidityLib.Fixidity storage fixidity
    	) public returns(uint256, uint256){
    	// New amount of fees, we calculate what are the decayed fees today, add the new amount and 
        // re-calculate rewardScore by:
        // 1. Divide the rewardScore by N^0.3 to isolate the trading feed component
        uint256 stakingComponent = uint256(fixidity.power_any(int256(_params._totalBalanceUser), _params.WEIGHT_STAKING));
        uint256 newRewardScore = _params.lastRewardScore / stakingComponent;
        // 2. Elevate to 1/0.7 to get the equivalent trading fees after decay and add the new fees spent
        newRewardScore = uint256(fixidity.power_any(int256(newRewardScore), _params.INVERSE_WEIGHT_FEES)) + _params._newFees;
        // 3. Calculate the new rewardScore re-multiplying the staking component N^0.3
        newRewardScore = stakingComponent * (uint256(fixidity.power_any(int256(newRewardScore), _params.WEIGHT_FEES)));

        // New fees mean new slopes to add as they have to decay later + increase today's slope
        uint256 additionalSlope = (newRewardScore - _params.lastRewardScore) / _params.timeToZero;

        return (newRewardScore, additionalSlope);
    }

    /*
    * @notice Calculate the reward score of a user using the entire formula
    * @param params, struct containing the necessary values for reward score calculations
    * @param fixidity, pointer to the library to access its functions
    * @return new value of the reward score
    */
    function calculateRewardScore(
    	ParamsCalculateRewardScore memory _params,
    	FixidityLib.Fixidity storage fixidity
    	) public returns(uint256){
    	uint256 newRewardScore = uint256(fixidity.power_any(int256(_params._totalBalanceUser), _params.WEIGHT_STAKING)) * (uint256(fixidity.power_any(int256(IContract(address(this)).feesPaidBy(_params._account)), _params.WEIGHT_FEES)));
    	return (newRewardScore);
    }

}