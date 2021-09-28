pragma solidity ^0.5.16;

// Import necessary contracts for math operations and Token handling
import "openzeppelin-solidity-2.3.0/contracts/math/Math.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";

// Inheritance
// import "./interfaces/IStakingRewards.sol";
import "./RewardsDistributionRecipient.sol";
import "./Pausable.sol";

import "./RewardEscrow.sol";


contract StakingRewards is RewardsDistributionRecipient, ReentrancyGuard, Pausable {
    /*
    StakingRewards contract for Kwenta responsible for:
    - Staking KWENTA tokens
    - Withdrawing KWENTA tokens
    - Updating staker and trader scores
    - Calculating and notifying rewards
    */
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    // Reward Escrow
    RewardEscrow public rewardEscrow;

    // Tokens to stake and reward
    IERC20 public rewardsToken;
    IERC20 public stakingToken;
    // Time handling:
    // Time where new reward epoch finishes 
    uint256 public periodFinish = 0;
    // Reward rate per second for next epoch
    uint256 public rewardRate = 0;
    // Reward rate per Token and per second for next epoch
    uint256 public rewardRateToken = 0;
    // Reward rate per Dollar Fee and second for next epoch
    uint256 public rewardRateFees = 0;
    // Epoch default duration
    uint256 public rewardsDuration = 1 minutes;
    // Last time an event altering the staked amount happened (staking, withdrawing, notifyreward)
    uint256 public lastUpdateTime;
    // Last time an event altering the fee amount happened (updating trader scores, notifyreward)
    uint256 public lastUpdateTimeFees;
    // Last rewardRate per Token
    uint256 public rewardPerTokenStored;
    // Last rewardRate per Fee
    uint256 public rewardPerFeePaid;

    // Save the latest reward per Token applicable for each address
    mapping(address => uint256) public userRewardPerTokenPaid;
    // Save the latest reward per Fee applicable for each address
    mapping(address => uint256) public userRewardPerFeePaid;
    // Rewards due to each account
    mapping(address => uint256) public rewards;

    // Total tokens staked
    uint256 private _totalSupply;
    
    // Number containing total Fees
    uint256 private _totalFeesPaid;
    // Tokens escrowed for each address
    mapping(address => uint256) private _escrowedBalances;
    // Save the latest total token to account for rewards (staked + escrowed rewards)
    mapping(address => uint256) private _totalBalances;

    // Mapping containing total fees paid
    mapping (address => uint256) private _feesPaid;
    
    uint256 private constant MIN_STAKE = 0;

    uint256 private constant MAX_BPS = 10000;
    uint256 public _weightFees = 7_000;
    uint256 public _weightTradingScore = 3_000;
    uint256 public _weightStakingScore = 7_000;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _owner,
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken
    ) public Owned(_owner) {
    /*
    Setup the owner, rewards distribution and token addresses
    */
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        rewardsDistribution = _rewardsDistribution;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
    /*
    Getter funtion for the state variable _totalSupply
    */
        return _totalSupply;
    }

    function totalFeesPaid() external view returns (uint256) {
    /*
    Getter funtion for the state variable _totalFeesPaid
    */
        return _totalFeesPaid;
    }

    function balanceOf(address account) public view returns (uint256) {
    /*
    Getter funtion for the staked balance of an account
    */
        return _totalBalances[account].sub(_escrowedBalances[account]);
    }

    function totalBalanceOf(address account) external view returns (uint256) {
    /*
    Getter funtion for the total balances of an account (staked`+ escrowed rewards)
    */
        return _totalBalances[account];
    }

    function feesOf(address account) external view returns (uint256) {
    /*
    Getter funtion for the state variable _feesPaid
    */
        return _feesPaid[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
    /*
    Calculate if we are still in the reward epoch or we reached periodFinish
    */
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
    /*
    Function calculating the state of reward to be delivered per Token staked to all acounts before the new change
    takes place. Saved in userRewardPerTokenPaid and used later in function earned() to calculate the extra rewards
    to add taking into account the reward conditions of the latest change and the current earned() context
    returns: uint256 containing the new reward per Token 
    */
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRateToken).mul(MAX_BPS).div(_totalSupply)
            );
    }

    function rewardPerFee() public view returns (uint256) {
    /*
    Function calculating the state of reward to be delivered per dollar of fees paid to all acounts before the new change
    takes place. Saved in userRewardPerFeePaid and used later in function earned() to calculate the extra rewards
    to add taking into account the reward conditions of the latest change and the current earned() context
    returns: uint256 containing the new reward per fee paid 
    */
        if (_totalFeesPaid == 0) {
            return rewardPerFeePaid;
        }
        return
            rewardPerFeePaid.add(
                lastTimeRewardApplicable().sub(lastUpdateTimeFees).mul(rewardRateFees).mul(MAX_BPS).div(_totalFeesPaid)
            );
    }

    function earnedFromTrading(address account) public view returns (uint256) {
    /*
    Function calculating the rewards earned by an account between the current call moment and the latest change in
    fees paid. The function divides the fees paid by total fees, accounts for the changes between now and the 
    last changes (deducting userRewardPerFeePaid) and adds the result to the existing rewards balance of the account
    returns: uint256 containing the total rewards due to account
    */
    
    uint256 trading = _feesPaid[account].mul(rewardPerFee().sub(userRewardPerFeePaid[account])).div(MAX_BPS);

    return trading;
    }

    function earnedFromStaking(address account) public view returns (uint256) {
    /*
    Function calculating the rewards earned by an account between the current call moment and the latest change in the
    account balance. The function divides the current balance by the total supply , accounts for the changes between 
    now and the last changes (deducting userRewardPerTokenPaid) and adds the result to the existing rewards balance
    of the account
    returns: uint256 containing the total rewards due to account
    */
    uint256 staking = _totalBalances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(MAX_BPS);    

    return staking;
    }

    function earnedTotal(address account) public view returns (uint256) {
    /*
    Function calculating the total rewards earned by an account adding staking and trading rewards
    returns: uint256 containing the total rewards due to account
    */
    uint256 totalEarned = earnedFromStaking(account).add(earnedFromTrading(account)).add(rewards[account]);

    return totalEarned;
    }

    function getRewardForDuration() external view returns (uint256) {
    /*
    Calculate the total rewards delivered in a specific duration, multiplying rewardRate x duration
    returns: uint256 containing the total rewards to be delivered
    */
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function updateTraderScore(address _trader, uint256 _newFeesPaid) external updateTradingRewards(_trader) {
        /*
        Function called by the ExchangerProxy updating the fees paid by each account
        _trader: address, for which to update the score
        _feesPaid: uint256, total fees paid in this period
        returns: NA, updates the state mapping _traderScore
        */
        if(balanceOf(_trader) > MIN_STAKE){
            _totalFeesPaid = _totalFeesPaid.add(_newFeesPaid);
            _feesPaid[_trader] = _feesPaid[_trader].add(_newFeesPaid);
        }
        
    }


    function stake(uint256 amount) external nonReentrant notPaused updateStakingRewards(msg.sender) {
    /*
    Function staking the requested tokens by the user.
    _amount: uint256, containing the number of tokens to stake
    returns: NA
    */
        require(amount > 0, "Cannot stake 0");
        // Update total supply of tokens
        _totalSupply = _totalSupply.add(amount);
        // Update caller balance
        _totalBalances[msg.sender] = _totalBalances[msg.sender].add(amount);
        stakingToken.transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateStakingRewards(msg.sender) {
    /*
    Function withdrawing the requested tokens by the user.
    _amount: uint256, containing the number of tokens to stake
    returns: NA
    */
        require(amount > 0, "Cannot withdraw 0");
        require(balanceOf(msg.sender) >= amount, "Amount required too high");
        // Update total supply of tokens
        _totalSupply = _totalSupply.sub(amount);
        // Update caller balance
        _totalBalances[msg.sender] = _totalBalances[msg.sender].sub(amount);
        stakingToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public definedEscrow updateStakingRewards(msg.sender) updateTradingRewards(msg.sender){
    /*
    Function transferring the accumulated rewards for the caller address and updating the state mapping 
    containing the current rewards
    */
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardEscrow.appendVestingEntry(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external definedEscrow {
    /*
    Function handling the exit of the protocol of the caller:
    - Withdraws all tokens
    - Transfers all rewards to caller's address
    */
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    // TODO: Modifier for onlyRewardEscrow
    function stakeEscrow(address _account, uint256 _amount) public nonReentrant definedEscrow updateStakingRewards(_account) {
        _totalBalances[_account] = _totalBalances[_account].add(_amount);
        _escrowedBalances[_account] = _escrowedBalances[_account].add(_amount);
        _totalSupply = _totalSupply.add(_amount);
        emit EscrowStaked(_account, _amount);
    }

    // TODO: Modifier for onlyRewardEscrow
    function unstakeEscrow(address _account, uint256 _amount) public nonReentrant definedEscrow updateStakingRewards(_account) {
        require(_escrowedBalances[_account] >= _amount, "Amount required too large");
        _totalBalances[_account] = _totalBalances[_account].sub(_amount);
        _escrowedBalances[_account] = _escrowedBalances[_account].sub(_amount);
        _totalSupply = _totalSupply.sub(_amount);
        emit EscrowUnstaked(_account, _amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward) external onlyRewardsDistribution updateStakingRewards(address(0)) updateTradingRewards(address(0)) {
    /*
    Function called to initialize a new reward distribution epoch, taking into account rewards still to be 
    delivered from a previous epoch and updating the lastUpdate and periodFinish state variables
    returns: NA
    */
    // If the previous epoch is finished, rewardRate calculation is straightforward
    // if not, add to the new amount to be delivered the remaining rewards still to be delivered by previous epoch
        if (block.timestamp >= periodFinish) {
            // Formula: rewardRate = total reward / time
            rewardRate = reward.div(rewardsDuration);
        } else {
            // Time to finish the previous reward epoch
            uint256 remaining = periodFinish.sub(block.timestamp);
            // Total rewardsa still to be delivered in previous epoch
            uint256 leftover = remaining.mul(rewardRate);
            // Formula: rewardRate = (sum of remaining rewards and new amount) / time
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        rewardRateToken = rewardRate.mul(_weightStakingScore).div(MAX_BPS);
        rewardRateFees = rewardRate.mul(_weightTradingScore).div(MAX_BPS);

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint balance = rewardsToken.balanceOf(address(this));
        
        require(rewardRate <= balance.div(rewardsDuration), "Provided reward too high");

        // Time updates
        lastUpdateTime = block.timestamp;
        lastUpdateTimeFees = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(stakingToken), "Cannot withdraw the staking token");
        IERC20(tokenAddress).transfer(owner, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
    /*
    Function available for the owner to change the rewards duration via the state variable _rewardsDuration
    */
        require(
            block.timestamp > periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    function setRewardEscrow(address _rewardEscrow) external onlyOwner {
    /*
    Function used to define the rewardEscrow to use
    */
        rewardEscrow = RewardEscrow(_rewardEscrow);
        emit RewardEscrowUpdated(address(_rewardEscrow));
    }

    /* ========== MODIFIERS ========== */

    modifier updateTradingRewards(address account) {
    /*
    Modifier called each time an event changing the trading score is updated:
    - update trader score
    - notify reward amount
    The modifier saves the state of the reward rate per fee until this point for the specific 
    address to be able to calculate the marginal contribution to rewards afterwards and adds the accumulated
    rewards since the last change to the account rewards
    */  
        
        // Calculate the reward per unit of reward score applicable to the last stint of account
        rewardPerFeePaid = rewardPerFee();
        // Calculate if the epoch is finished or not
        lastUpdateTimeFees = lastTimeRewardApplicable();
        if (account != address(0)) {
            // Add the rewards added during the last stint
            rewards[account] = earnedFromTrading(account).add(rewards[account]);
            userRewardPerFeePaid[account] = rewardPerFeePaid;
        }
        _;
    }

    modifier updateStakingRewards(address account) {
    /*
    Modifier called each time an event changing the staked balance is called:
    - stake
    - withdraw
    - notify reward amount
    The modifier saves the state of the reward rate per token until this point for the specific 
    address to be able to calculate the marginal contribution to rewards afterwards and adds the accumulated
    rewards since the last change to the account rewards
    */  
    // Calculate the reward per unit of reward score applicable to the last stint of account
        rewardPerTokenStored = rewardPerToken();
        // Calculate if the epoch is finished or not
        lastUpdateTime = lastTimeRewardApplicable();
            
        if (account != address(0)) {
            // Add the rewards added during the last stint
            rewards[account] = earnedFromStaking(account).add(rewards[account]);
            // Update the latest conditions of account for next stint calculations
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _; 
    }

    modifier definedEscrow() {
        require(address(rewardEscrow) != address(0), "Rewards Escrow needs to be defined");
        _;
    }


    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
    event EscrowStaked(address account, uint256 amount);
    event EscrowUnstaked(address account, uint256 amount);
    event RewardEscrowUpdated(address rewardEscrow);
}