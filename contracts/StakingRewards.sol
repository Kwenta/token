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


contract StakingRewards is RewardsDistributionRecipient, ReentrancyGuard, Pausable {
    /*
    StakingRewards contract for Kwenta responsible for:
    - Staking KWENTA tokens
    - Withdrawing KWENTA tokens
    - Updating staker and trader scores
    - Calculating and notifying rewards
    */
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    // Tokens to stake and reward
    IERC20 public rewardsToken;
    IERC20 public stakingToken;
    // Time handling:
    // Time where new reward epoch finishes 
    uint256 public periodFinish = 0;
    // Reward rate per second for next epoch
    uint256 public rewardRate = 0;
    uint256 public rewardRateToken = 0;
    uint256 public rewardRateFees = 0;
    // Epoch default duration
    uint256 public rewardsDuration = 1 minutes;
    // Last time an event altering the reward distribution ocurred (staking, withdrawing, updating trader scores, notifyreward)
    uint256 public lastUpdateTime;
    uint256 public lastUpdateTimeFees;
    // Last rewardRate per unit of rewardScore
    uint256 public rewardPerTokenStored;
    // Last rewardRate per unit of rewardScore
    uint256 public rewardPerFeePaid;

    // Save the latest reward per unit of rewardScore applicable for each address
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public userRewardPerFeePaid;
    // Rewards due to each account
    mapping(address => uint256) public rewards;

    // Total tokens staked
    uint256 private _totalSupply;
    
    // Number containing total trading scores
    uint256 private _totalFeesPaid;
    // Tokens stoked for each address
    mapping(address => uint256) public _balances;

    // Mapping containing total fees paid
    mapping (address => uint256) public _feesPaid;
    
    uint256 private constant MAX_BPS = 10000;
    uint256 public _weightFees = 70;
    uint256 public _weightTradingScore = 30;
    uint256 private _weightStakingScore = 70;

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

        _weightFees = _weightFees.mul(MAX_BPS).div(100);
        _weightTradingScore = _weightTradingScore.mul(MAX_BPS).div(100);
        _weightStakingScore = _weightStakingScore.mul(MAX_BPS).div(100);
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

    function balanceOf(address account) external view returns (uint256) {
    /*
    Getter funtion for the state variable _balances
    */
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
    /*
    Calculate if we are still in the reward epoch or we reached periodFinish
    */
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
    /*
    Function calculating the state of reward to be delivered per unit of rewardScore to all acounts before the new change
    takes place. Saved in userRewardPerTokenPaid and used later in function earned() to calculate the extra rewards
    to add taking into account the reward conditions of the latest change and the current earned() context
    returns: uint256 containing the new reward per unit of reward score 
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
    Function calculating the state of reward to be delivered per unit of rewardScore to all acounts before the new change
    takes place. Saved in userRewardPerTokenPaid and used later in function earned() to calculate the extra rewards
    to add taking into account the reward conditions of the latest change and the current earned() context
    returns: uint256 containing the new reward per unit of reward score 
    */
        if (_totalFeesPaid == 0) {
            return rewardPerFeePaid;
        }
        return
            rewardPerFeePaid.add(
                lastTimeRewardApplicable().sub(lastUpdateTimeFees).mul(rewardRateFees).mul(MAX_BPS).div(_totalFeesPaid)
            );
    }

    function earned(address account, uint256 tokenFees) public view returns (uint256) {
    /*
    Function calculating the rewards earned by an account between the current call moment and the latest change in the
    account rewardScore. The function divides the current rewardScore by the accumulated total totalrewardScore (via the
    variable rewardPerTokenStored) between now and the last changes (deducting userRewardPerTokenPaid) and 
    adds the result to the existing rewards balance of the account
    returns: uint256 containing the total rewards due to account
    */
    uint256 staking = 0;
    uint256 trading = 0;
    if(tokenFees >= 1){
        staking = _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(MAX_BPS);    
    }
    if (tokenFees <= 1){
        trading = _feesPaid[account].mul(rewardPerFee().sub(userRewardPerFeePaid[account])).div(MAX_BPS);
    }
    
    return ((staking.add(trading)).add(rewards[account]));
    }

    function getRewardForDuration() external view returns (uint256) {
    /*
    Calculate the total rewards delivered in a specific duration, multiplying rewardRate x duration
    returns: uint256 containing the total rewards to be delivered
    */
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function updateTraderScore(address _trader, uint256 _newFeesPaid) external updateReward(_trader, 0) {
        /*
        Function called by the ExchangerProxy updating the trader score of a specific address using the
        formula: (fees*70%)
        _trader: address, for which to update the score
        _feesPaid: uint256, total fees paid in this period
        As the trader score changes the rewardScore, we also update both the rewardScore of the _trader account and
        the total accumulated sum of rewardScores
        returns: NA, updates the state mapping _traderScore
        */

        _totalFeesPaid = _totalFeesPaid.sub(_feesPaid[_trader]).add(_newFeesPaid);
        _feesPaid[_trader] = _newFeesPaid;

    }


    function stake(uint256 amount) external nonReentrant notPaused updateReward(msg.sender, 2) {
    /*
    Function staking the requested tokens by the user.
    _amount: uint256, containing the number of tokens to stake
    returns: NA
    */
        require(amount > 0, "Cannot stake 0");
        // Update total supply of tokens
        _totalSupply = _totalSupply.add(amount);
        // Update caller balance
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        //stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender, 2) {
    /*
    Function withdrawing the requested tokens by the user.
    _amount: uint256, containing the number of tokens to stake
    returns: NA
    */
        require(amount > 0, "Cannot withdraw 0");
        // Update total supply of tokens
        _totalSupply = _totalSupply.sub(amount);
        // Update caller balance
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        //stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender, 0) {
    /*
    Function transferring the accumulated rewards for the caller address and updating the state mapping 
    containing the current rewards
    */
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            //rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
    /*
    Function handling the exit of the protocol of the caller:
    - Withdraws all tokens
    - Transfers all rewards to caller's address
    */
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward) external onlyRewardsDistribution updateReward(address(0), 1) {
    /*
    Function called to initialize a new reward distribution epoch, taking into account rewards still to be 
    delivered from a previous epoch and updating the lastUpdate and periodFinish state variables
    returns: NA
    */
    // If the previous epoch is finished, rewardRate calculation is straightforward
    // if not, add to the new amount to be delivered the remaining rewards still to be delivered by previous epoch
        if (block.timestamp >= periodFinish) {
            // rewardRate = total reward / time
            rewardRate = reward.div(rewardsDuration);
        } else {
            // Time to finish the previous reward epoch
            uint256 remaining = periodFinish.sub(block.timestamp);
            // Total rewardsa still to be delivered in previous epoch
            uint256 leftover = remaining.mul(rewardRate);
            // rewardRate = (sum of remaining rewards and new amount) / time
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        rewardRateToken = rewardRate.mul(_weightStakingScore).div(MAX_BPS);
        rewardRateFees = rewardRate.mul(_weightTradingScore).div(MAX_BPS);

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        //uint balance = rewardsToken.balanceOf(address(this));
        uint balance = 100000000000000000000000;
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
        IERC20(tokenAddress).safeTransfer(owner, tokenAmount);
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

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account, uint256 tokenFees) {
    /*
    Modifier called each time an event changing the rewardScore is called:
    - stake
    - withdraw
    - update trader score
    - notify reward amount
    The modifier saves the state of the reward rate per unit of reward score until this point for the specific address
    to be able to calculate the marginal contribution to rewards afterwards and adds the accumulated rewards since the 
    last change to ther account rewards
    */  
        if(tokenFees >= 1) {
            // Calculate the reward per unit of reward score applicable to the last stint of account
            rewardPerTokenStored = rewardPerToken();
            // Calculate if the epoch is finished or not
            lastUpdateTime = lastTimeRewardApplicable();
        }
        if (tokenFees <= 1) {
            // Calculate the reward per unit of reward score applicable to the last stint of account
            rewardPerFeePaid = rewardPerFee();
            // Calculate if the epoch is finished or not
            lastUpdateTimeFees = lastTimeRewardApplicable();
        }
        
        if (account != address(0)) {
            // Add the rewards added during the last stint
            if(tokenFees >= 1) {
                rewards[account] = earned(account, tokenFees);
                // Update the latest conditions of account for next stint calculations
                userRewardPerTokenPaid[account] = rewardPerTokenStored;
            }
            if(tokenFees<=1) {
                rewards[account] = earned(account, tokenFees);
                userRewardPerFeePaid[account] = rewardPerFeePaid;   
            }
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
}