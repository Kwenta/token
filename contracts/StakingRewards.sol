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
    // Tokens stoked for each address
    mapping(address => uint256) private _balances;
    // Save the latest total token to account for rewards (staked + escrowed rewards)
    mapping(address => uint256) public _totalBalances;

    // Mapping containing total fees paid
    mapping (address => uint256) private _feesPaid;
    
    uint256 private constant MAX_BPS = 10000;
    uint256 public _weightFees = 7_000;
    uint256 public _weightTradingScore = 3_000;
    uint256 public _weightStakingScore = 7_000;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _owner,
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken,
        RewardEscrow _rewardEscrow
    ) public Owned(_owner) {
    /*
    Setup the owner, rewards distribution and token addresses
    */
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        rewardsDistribution = _rewardsDistribution;
        rewardEscrow = _rewardEscrow;
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

    function feesOf(address account) external view returns (uint256) {
    /*
    Getter funtion for the state variable _balances
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

    function earned(address account, uint256 tokenFees) public view returns (uint256) {
    /*
    Function calculating the rewards earned by an account between the current call moment and the latest change in the
    account balance or fees paid. The function divides the current balance by the total supply and the fees paid by
    total fees, accounts for the changes between now and the last changes (deducting userRewardPerTokenPaid and 
    userRewardPerFeePaid) and adds the result to the existing rewards balance of the account
    returns: uint256 containing the total rewards due to account
    */
    uint256 staking = 0;
    uint256 trading = 0;
    if(tokenFees >= 1){
        staking = _totalBalances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(MAX_BPS);    
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
        Function called by the ExchangerProxy updating the fees paid by each account
        _trader: address, for which to update the score
        _feesPaid: uint256, total fees paid in this period
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
        _totalBalances[msg.sender] = _totalBalances[msg.sender].add(amount);
        stakingToken.transferFrom(msg.sender, address(this), amount);
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
        _totalBalances[msg.sender] = _totalBalances[msg.sender].sub(amount);
        stakingToken.transfer(msg.sender, amount);
        emit Sender(msg.sender);
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
            //rewardsToken.transfer(msg.sender, reward);
            rewardEscrow.appendVestingEntry(msg.sender, reward);
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

    // TODO: Modifier for onlyRewardEscrow
    function stakeEscrow(address _account, uint256 _amount) public nonReentrant {
        _totalBalances[_account] = _totalBalances[_account].add(_amount);
        _totalSupply = _totalSupply.add(_amount);
        emit EscrowStaked(_account, _amount);
    }

    // TODO: Modifier for onlyRewardEscrow
    function unstakeEscrow(address _account, uint256 _amount) public nonReentrant {
        require(_totalBalances[_account] >= _amount, "Amount required too large");
        _totalBalances[_account] = _totalBalances[_account].sub(_amount);
        _totalSupply = _totalSupply.sub(_amount);
        emit EscrowUnstaked(_account, _amount);
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

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account, uint256 tokenFees) {
    /*
    Modifier called each time an event changing the is called:
    - stake
    - withdraw
    - update trader score
    - notify reward amount
    The modifier saves the state of the reward rate per token and per fee until this point for the specific 
    address to be able to calculate the marginal contribution to rewards afterwards and adds the accumulated
    rewards since the last change to the account rewards
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
    event EscrowStaked(address account, uint256 amount);
    event EscrowUnstaked(address account, uint256 amount);
    event Sender(address snd);
}