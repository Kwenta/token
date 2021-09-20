pragma solidity ^0.5.16;

// Import math & SafeMath for safe math operations
import "openzeppelin-solidity-2.3.0/contracts/math/Math.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";

contract StakingRewards_KWENTA {
	/*
	StakingRewards contract for Kwenta responsible for:
	- Staking KWENTA tokens
	- Withdrawing KWENTA tokens
	- updating staker and trader scores
	- calculating and notifying rewards
	*/

	using SafeMath for uint256;

	string public name = "KWENTA Staking rewards contract";

    // Mappings containing staker & trading scores
    mapping(address => uint256) public traderScores;
    mapping(address => uint256) public stakerScores;

    // Mapping containing the last rewardScore term for each address to update the sum of all 
    // rewardScores each time an address stakes or updates its traderscore
    mapping(address => uint256) public internalAddition;

    // Number containing the sum of reward scores for all addresses
    uint256 public sumRewardsScore = 0;

    // Total tokens staked
    uint256 public _totalSupply;
    // Tokens stoked for each address
    mapping(address => uint256) public _balances;

    constructor() public {
    }

    function stake(uint _amount) public returns(bool) {
    	/*
    	Function staking the requested tokens by the user. Also updates the staker score and total sum
    	of rewardScores as staker score has changed
    	_amount: uint256, containing the number of tokens to stake
    	returns: bool, true if all ok
    	*/

    	require(_amount > 0, "Cannot stake 0");
    	//TODO: Require balance of staking token be >= _amount
    	//  Update totalSupply adding new amount
        _totalSupply = _totalSupply.add(_amount);
        // Update balances mapping adding the new staked _amount
        _balances[msg.sender] = _balances[msg.sender].add(_amount);

        // Update the staker score of the caller
        updateStakerScore(msg.sender);
        // Update the total sum of rewardScores
        updateTotalSum(msg.sender);
        
    }

    function updateTotalSum(address _staker) private {
	    /*
		Function updating the total sum of rewardScores for all addresses by substracting the 
		previous amount (stored in internalAddition mapping) and adding the new term 
		(calculated by function totalRewardScore)
		_staker: address, for which to update the quantities
		returns: NA
		*/

    	// Deduct the previous contribution of this address
    	sumRewardsScore -= internalAddition[_staker];
    	// Calculate the new rewardScore for this address and add it back to the total sum
        uint256 tmp = totalRewardScore(_staker);
        sumRewardsScore += tmp;
        // Update the contribution of this address
        internalAddition[_staker] = tmp;
    }

    function totalRewardScore(address _staker) public view returns(uint256){
    	/*
		Function calculating the rewardScore of a specific address using the formula: 
		(stakerScore^1) * (traderScore^2)
		_staker: address, for which to update the score
		returns: uint256, the new rewardScore
		*/

		// TODO: update with 0.7 and 0.3
    	return (_balances[_staker] ** 1).mul(traderScores[_staker] ** 2);
    }

	function withdraw(uint _amount) public returns(bool) {
		/*
    	Function withdrawing the requested tokens by the user. Also updates the staker score and total sum
    	of rewardScores as staker score has changed
    	_amount: uint256, containing the number of tokens to withdraw
    	returns: bool, true if all ok
    	*/

    	require(_amount > 0, "Cannot stake 0");
    	//TODO: Require balance of staked tokens be >= _amount
    	//  Update totalSupply deducting amount
        _totalSupply = _totalSupply.sub(_amount);
        // Update balances mapping deducting the withdrawn _amount
        _balances[msg.sender] = _balances[msg.sender].sub(_amount);

        // Update staker score controlling for total supply == 0
        if(_totalSupply > 0) {
        	updateStakerScore(msg.sender);
    	} else {
    		stakerScores[msg.sender] = 0;
    	}
    	// Update the total sum of rewardScores
        updateTotalSum(msg.sender);
    }

    function updateTraderScore(uint256 _feesPaid, uint256 _avgOI, address _trader) public returns(bool) {
    	/*
		Function called by the ExchangerProxy updating the trader score of a specific address using the
		formula: (fees^2) * (avgOI^2)
		_feesPaid: uint256, total fees paid in this period
		_avgOI: average Open Interest during this period
		_trader: address, for which to update the score
		returns: bool, true if all ok
		*/

    	require(_feesPaid >= 0, "Fees cannot be negative");
    	require(_avgOI >= 0, "avgOI cannot be negative");
    	require(msg.sender != address(0));
    	require(_trader != address(0));

        // Update the trader score of the trader
    	// TODO: update formula with safemath power
    	traderScores[_trader] = (_feesPaid ** 2).mul(_avgOI ** 2);
    	// Update the total sum of rewardScores
    	updateTotalSum(_trader);

    	return true;
    }

    function updateStakerScore(address _staker) public returns(bool) {
    	/*
		Function called by the contract updating the staker score of a specific address using the
		formula: Nstaked / Ntotal
		_staker: address, for which to update the score
		returns: bool, true if all ok
		*/

		// Update the trader score of the trader
    	stakerScores[_staker] = _balances[_staker].div(_totalSupply);

    	return true;
    }

    function calculateRewardScore(address _staker) public view returns(uint256) {
    	/*
		Function called by the contract RewardsDistribution calcualting the % of reward to assign for 
		a specific address, distributing it by rewardsScore
		_staker: address, for which to update the score
		returns: uint256, % of the reward corresponding to address _staker
		*/
		
		// As the total sum of rewardsScores is already calculated (sumRewardsScore) the function
		// returns the ratio between the term corresponding to the address and the total sum
		// TODO: not multiply by 1000000 but return float?
    	uint256 result = (internalAddition[_staker].mul(1000000).div(sumRewardsScore));
    	return result;
    }



}