// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// TODO: remove
import "forge-std/Test.sol";

// Inheritance
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Internal references
import "./interfaces/IStakingRewardsV2.sol";
import "./interfaces/IRewardEscrowV2.sol";

// TODO: add interface

contract StakingAccount is
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{

    IStakingRewardsV2 public stakingRewards;
    IRewardEscrowV2 public rewardEscrow;

    /* ========== CONSTRUCTOR ========== */

    /// @dev disable default constructor for disable implementation contract
    /// Actual contract construction will take place in the initialize function via proxy
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address _stakingRewards, address _rewardEscrow) external initializer {
        // Initialize inherited contracts
        __Ownable_init();
        __UUPSUpgradeable_init();
        // TODO: what should these names be?
        __ERC721_init("Kwenta Staking Account", "KSA");

        // transfer ownership
        transferOwnership(_owner);

        // define variables
        stakingRewards = IStakingRewardsV2(_stakingRewards);
        rewardEscrow = IRewardEscrowV2(_rewardEscrow);
    }

    function createAccount() external returns (uint256 tokenId) {
        tokenId = totalSupply() + 1;
        _mint(msg.sender, tokenId);
    }

    // function stake(uint256 _accountId, uint256 amount) public {
    //     if (!_isApprovedOrOwner(msg.sender, _accountId)) revert;

    //     stakingRewards.stake(amount);
    // }

    



    /* ========== UPGRADEABILITY ========== */

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
}
