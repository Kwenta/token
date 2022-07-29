// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 @TODO: Interface Update
 @TODO: Integrate with other contracts ):
 @TODO: notifyRewardAmount (implementation review and docs)
 @TODO: pull/ref tests from snx and token v1
 @TODO: trading vault integration
 @TODO: variable visibility refactor
 */

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ISupplySchedule.sol";
import "./interfaces/IRewardEscrow.sol";

/// @title KWENTA Staking Rewards
/// @author SYNTHETIX, JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @notice Updated version of Synthetix's StakingRewards with new features supporting
/// escrow staking, trading incentives disbursal, etc..
contract StakingRewards is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                                CONSTANTS
    ///////////////////////////////////////////////////////////////*/

    /// @notice minimum amount of time a user must stake
    /// @dev used to prevent flashloans from temporarily inflating voting power
    uint256 private constant MIN_STAKING_PERIOD = 1 days;

    /*///////////////////////////////////////////////////////////////
                                STATE
    ///////////////////////////////////////////////////////////////*/

    /// @notice token used for rewards
    IERC20 public rewardsToken;

    /// @notice token used to stake
    /// @dev staked token can/will be used for voting
    IERC20 public stakingToken;

    /// @notice escrow contract which holds (and may stake) reward tokens
    IRewardEscrow public rewardEscrow;

    /// @notice handles reward token minting logic
    ISupplySchedule public supplySchedule;

    /// @notice marks applicable reward period finish time
    uint256 public periodFinish = 0;

    /// @notice amount of tokens minted per second
    uint256 public rewardRate = 0;

    /// @notice period for rewards
    uint256 public rewardsDuration = 7 days;

    /// @notice track last time the rewards were updated
    uint256 public lastUpdateTime;

    /// @notice summation of rewardRate divided by total staked tokens
    uint256 public rewardPerTokenStored;

    /// @notice percent distributed for staking
    uint256 public percentageStaking;

    /// @notice percent distributed for trading
    uint256 public percentageTrading;

    /// @notice total number of tokens staked in this contract
    uint256 public _totalSupply;

    /// @notice track rewardPerTokenStored for a user and updates
    /// upon the user interacting with the contract (i.e. updateRewards())
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice save most recent date an address emitted Staked event
    mapping(address => uint256) public lastStakingEvent;

    /// @notice track rewards for a given user which changes when
    /// a user stakes, withdraws, or claims rewards
    mapping(address => uint256) public rewards;

    /// @notice number of tokens staked by address
    /// @dev this includes escrowed tokens stake
    mapping(address => uint256) public _balances;

    /// @notice number of tokens escrowed by address
    mapping(address => uint256) public _escrowedBalances;

    /*///////////////////////////////////////////////////////////////
                                EVENTS
    ///////////////////////////////////////////////////////////////*/

    /// @notice update reward rate
    /// @param reward: amount to be distributed over applicable rewards duration
    event RewardAdded(uint256 reward);

    /// @notice emitted when user stakes tokens
    /// @param user: staker address
    /// @param amount: amount staked
    event Staked(address indexed user, uint256 amount);

    /// @notice emitted when user withdraws tokens
    /// @param user: address of user withdrawing
    /// @param amount: amount withdrawn
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice emitted when escrow staked
    /// @param user: owner of escrowed tokens address
    /// @param amount: amount staked
    event EscrowStaked(address indexed user, uint256 amount);

    /// @notice emitted when staked escrow tokens are un-staked
    /// @param user: owner of escrowed tokens address
    /// @param amount: amount withdrawn
    event EscrowUnstaked(address user, uint256 amount);

    /// @notice emitted when user claims rewards
    /// @param user: address of user claiming rewards
    /// @param reward: amount of reward token claimed
    event RewardPaid(address indexed user, uint256 reward);

    /// @notice emitted when rewards duration changes
    /// @param newDuration: denoted in seconds
    event RewardsDurationUpdated(uint256 newDuration);

    /// @notice emitted when tokens are recovered from this contract
    /// @param token: address of token recovered
    /// @param amount: amount of token recovered
    event Recovered(address token, uint256 amount);

    /// @notice emitted when address for RewardEscrow is updated
    /// @dev can only be updated by owner
    /// @param addr: address of new RewardEscrow
    event RewardEscrowUpdated(address addr);

    /// @notice emitted when percentage of rewards are set
    /// @param percentageStaking: percent of inflation distributed to stakers
    /// @param percentageTrading: percent of inflation distributed to traders
    event PercentageRewardsSet(
        uint256 percentageStaking,
        uint256 percentageTrading
    );

    /*///////////////////////////////////////////////////////////////
                                AUTH
    ///////////////////////////////////////////////////////////////*/

    /// @notice access control modifier for rewardEscrow
    modifier onlyRewardEscrow() {
        require(
            msg.sender == address(rewardEscrow),
            "StakingRewards: Only Reward Escrow"
        );
        _;
    }

    /// @notice access control modifier for rewardEscrow
    modifier onlySupplySchedule() {
        require(
            msg.sender == address(supplySchedule),
            "StakingRewards: Only Supply Schedule"
        );
        _;
    }

    /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ///////////////////////////////////////////////////////////////*/

    /// @notice configure StakingRewards state
    /// @dev owner set to address that deployed StakingRewards
    /// @param _rewardsToken: token rewarded to staker
    /// @param _stakingToken: token staked
    /// @param _rewardEscrow: escrow contract which holds (and may stake) reward tokens
    /// @param _supplySchedule: handles reward token minting logic
    constructor(
        address _rewardsToken,
        address _stakingToken,
        address _rewardEscrow,
        address _supplySchedule
    ) {
        // define reward/staking token
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);

        // define contracts which will interact with StakingRewards
        rewardEscrow = IRewardEscrow(_rewardEscrow);
        supplySchedule = ISupplySchedule(_supplySchedule);
    }

    /*///////////////////////////////////////////////////////////////
                                VIEWS
    ///////////////////////////////////////////////////////////////*/

    /// @return total supply of staked tokens
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @param account: address of potential staker
    /// @return amount of tokens staked by account
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice Getter function for the escrowed balance of an account
    /// @param account address to check the escrowed balance of
    /// @return escrowed balance of specified account
    function escrowedBalanceOf(address account)
        external
        view
        returns (uint256)
    {
        return _escrowedBalances[account];
    }

    /// @return rewards for the duration specified by rewardsDuration
    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /*///////////////////////////////////////////////////////////////
                            STAKE/WITHDRAW
    ///////////////////////////////////////////////////////////////*/

    /// @notice stake token
    /// @param amount: amount to stake
    /// @dev updateReward() called prior to function logic
    function stake(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        updateReward(msg.sender)
    {
        require(amount > 0, "StakingRewards: Cannot stake 0");

        // update state
        _totalSupply = _totalSupply + amount;
        _balances[msg.sender] = _balances[msg.sender] + amount;

        // update addresses last staking event timestamp
        lastStakingEvent[msg.sender] = block.timestamp;

        // transfer token to this contract from the caller
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        // emit staking event and index msg.sender
        emit Staked(msg.sender, amount);
    }

    /// @notice withdraw token
    /// @param amount: amount to withdraw
    /// @dev updateReward() called prior to function logic
    function withdraw(uint256 amount)
        public
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, "StakingRewards: Cannot withdraw 0");
        require(
            block.timestamp - lastStakingEvent[msg.sender] >=
                MIN_STAKING_PERIOD,
            "StakingRewards: Minimum Staking Period Not Met"
        );

        // update state
        _totalSupply = _totalSupply - amount;
        _balances[msg.sender] = _balances[msg.sender] - amount;

        // transfer token from this contract to the caller
        stakingToken.safeTransfer(msg.sender, amount);

        // emit withdraw event and index msg.sender
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice stake escrowed token
    /// @param account: address which owns token
    /// @param amount: amount to stake
    /// @dev updateReward() called prior to function logic
    /// @dev msg.sender NOT used (account is used)
    function stakeEscrow(address account, uint256 amount)
        public
        whenNotPaused
        onlyRewardEscrow
        updateReward(account)
    {
        require(amount > 0, "StakingRewards: Cannot stake 0");

        // update state
        _balances[account] += amount;
        _escrowedBalances[account] += amount;
        _totalSupply += amount;
        
        // update addresses last staking event timestamp
        lastStakingEvent[account] = block.timestamp;

        // emit escrow staking event and index _account
        emit EscrowStaked(account, amount);
    }

    /// @notice un-stake escrowed token
    /// @param account: address which owns token
    /// @param amount: amount to un-stake
    /// @dev updateReward() called prior to function logic
    /// @dev msg.sender NOT used (account is used)
    function unstakeEscrow(address account, uint256 amount)
        public
        nonReentrant
        onlyRewardEscrow
        updateReward(account)
    {
        require(
            _escrowedBalances[account] >= amount,
            "StakingRewards: Invalid Amount"
        );
        require(
            block.timestamp - lastStakingEvent[msg.sender] >=
                MIN_STAKING_PERIOD,
            "StakingRewards: Minimum Staking Period Not Met"
        );

        // update state
        _balances[account] -= amount;
        _escrowedBalances[account] -= amount;
        _totalSupply -= amount;

        // emit escrow unstaked event and index account
        emit EscrowUnstaked(account, amount);
    }

    /// @notice withdraw all available staked tokens and
    /// claim any rewards
    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /*///////////////////////////////////////////////////////////////
                            CLAIM REWARDS
    ///////////////////////////////////////////////////////////////*/

    /// @notice caller claims any rewards generated from staking
    /// @dev updateReward() called prior to function logic
    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            // update state (first)
            rewards[msg.sender] = 0;

            // transfer token from this contract to the caller
            rewardsToken.safeTransfer(msg.sender, reward);

            // emit reward claimed event and index msg.sender
            emit RewardPaid(msg.sender, reward);
        }
    }

    /*///////////////////////////////////////////////////////////////
                        REWARD UPDATE CALCULATIONS
    ///////////////////////////////////////////////////////////////*/

    /// @notice update reward state for the account and contract
    /// @param account: address of account which rewards are being updated for
    /// @dev contract state not specific to an account will be updated also
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (account != address(0)) {
            // update amount of rewards a user can claim
            rewards[account] = earned(account);

            // update reward per token staked AT this given time
            // (i.e. when this user is interacting with StakingRewards)
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /// @notice calculate running sum of reward per total tokens staked
    /// at this specific time
    /// @return running sum of reward per total tokens staked
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            (((lastTimeRewardApplicable() - lastUpdateTime) *
                rewardRate *
                1e18) / (_totalSupply));
    }

    /// @return timestamp of the last time rewards are applicable
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice determine how much reward token an account has earned thus far
    /// @param account: address of account earned amount is being calculated for
    function earned(address account) public view returns (uint256) {
        return
            ((_balances[account] *
                (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) +
            rewards[account];
    }

    /*///////////////////////////////////////////////////////////////
                            RESTRICTED FUNCTIONS
    ///////////////////////////////////////////////////////////////*/

    // @TODO: Add docs
    function notifyRewardAmount(uint256 reward)
        external
        onlySupplySchedule
        updateReward(address(0))
    {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardsToken.balanceOf(address(this));
        require(
            rewardRate <= balance / rewardsDuration,
            "StakingRewards: Provided reward too high"
        );

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    /// @notice added to support recovering LP Rewards from other systems
    /// such as BAL to be distributed to holders
    /// @param tokenAddress: address of token to be recovered
    /// @param tokenAmount: amount of token to be recovered
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        require(
            tokenAddress != address(stakingToken),
            "StakingRewards: Cannot withdraw the staking token"
        );
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /// @notice set rewards duration
    /// @param _rewardsDuration: denoted in seconds
    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(
            block.timestamp > periodFinish,
            "StakingRewards: Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /// @notice Set the % distribution between staking and trading
    /// @dev Only the owner can use this function and parameters should be in base 10_000 (80% = 8_000)
    /// @param _percentageStaking the % of rewards to distribute to staking scores
    /// @param _percentageTrading the % of rewards to distribute to reward scores
    function setPercentageRewards(
        uint256 _percentageStaking,
        uint256 _percentageTrading
    ) external onlyOwner {
        require(
            _percentageTrading + _percentageStaking == 10_000,
            "StakingRewards: Invalid Percentage"
        );
        percentageStaking = _percentageStaking;
        percentageTrading = _percentageTrading;

        emit PercentageRewardsSet(_percentageStaking, _percentageTrading);
    }

    /// @notice function available for the owner to change the rewardEscrow contract to use
    /// @param _rewardEscrow: address of the rewardEsxrow contract to use
    function setRewardEscrow(address _rewardEscrow) external onlyOwner {
        // solhint-disable-next-line
        require(
            IRewardEscrow(_rewardEscrow).getKwentaAddress() ==
                address(stakingToken),
            "staking token address not equal to RewardEscrow KWENTA address"
        );
        rewardEscrow = IRewardEscrow(_rewardEscrow);
        emit RewardEscrowUpdated(address(_rewardEscrow));
    }
}
