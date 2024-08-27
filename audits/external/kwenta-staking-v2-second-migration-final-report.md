# Introduction

A time-boxed security review of **Kwenta**'s **Staking V2** second migration was conducted by **Guhu**, with a focus on the security aspects of the smart contract implementation.

Disclaimer: A smart contract security review does not guarantee a complete absence of vulnerabilities. This was a time-bound effort to provide the highest value possible within the available time. Subsequent security reviews, a bug bounty program, and on-chain monitoring are highly recommended.

# About **Guhu**

[**Guhu**](https://twitter.com/Guhu95) is an independent security researcher with extensive experience in smart contract audits and an established bug bounty track record on Immunefi's [leaderboard](https://immunefi.com/leaderboard/).

Specifically, this engagement was initiated following **Guhu**'s disclosure on Immunefi of a high-severity vulnerability in the contracts of the first version of the Staking V2 contracts—a separate vulnerability from the one that prevented the first migration.

# About **Kwenta**'s **Staking V2** migration

Previously, Kwenta's governance token was staked in `StakingRewards`, with rewards being escrowed in `RewardEscrow`—referred to as "staking V1" from this point forward. Although these contracts weren't upgradeable, new features outlined by [KIPs](https://gov.kwenta.eth.limo/all-kips/): 058, 062, 042, 077, 045, and 086 necessitated the development of upgradeable contracts: `StakingRewardsV2` and `RewardEscrowV2`. The initial V2 contracts aimed to integrate with the V1 contracts to avoid migrating tokens locked in V1 escrow. However, flaws in this design led to the creation of a revised set of contracts, which are the subject of this report.

In this revised version, the V2 contracts operate separately from the V1 contracts. The migration of V1 escrowed funds to V2 is facilitated through an `EscrowMigrator` contract. Users with funds in V1 escrow must follow these steps in sequence after the new contracts are deployed:

1. Claim V1 staking rewards.
2. Register all their vesting entry IDs in the migrator contract.
3. Vest only the registered entries in escrow V1. This action will deduct the early vesting fee and transfer it to the migrator contract. The remainder of the vested KWENTA will be transferred to the user.
4. Approve the migrator contract to access the user-held KWENTA received during vesting.
5. Migrate the now-vested entries using the migrator contract, which will pull KWENTA from the user, and use the early vesting fee transferred in the previous step to create new V2 entries mirroring the vested V1 entries.

Additional detailed and comprehensive documentation was provided in both the [implementation PR](https://github.com/Kwenta/token/pull/232) and in [additional notes](https://github.com/tommyrharper/shared-notes/blob/main/stakingv2/migration-v2/migration-v2.md).

## General Observations

The overall quality of the reviewed codebase is exceptional: the code is well-structured, thought-out, thoroughly documented, and adheres to industry best practices. The testing suite is similarly impressive, boasting high overall testing coverage and excellent use of fuzzing and fork tests. The deployment process is well-organized, scripted, automated, clearly documented, and fork-tested. The provided accompanying documentation is, as mentioned earlier, detailed and comprehensive, aiding significantly in the review process.

## Privileged Roles & Actors

All contracts in the scope are owned and are upgradeable (using the UUPS pattern) by the `owner`.

## Scope

The following smart contracts at commit [`9cceb6d`](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c) were in the scope of the audit:

- `StakingRewardsV2.sol`
- `RewardEscrowV2.sol`
- `EscrowMigrator.sol`
- `EarlyVestFeeDistributor.sol`

## Mitigation Review

The team's fixes were reviewed at commit [`df06446`](https://github.com/Kwenta/token/pull/232/commits/df06446d338313fa0b0be1b0a4364f6ade94ecaf).

---

# Findings Summary

|                     | Title                                                                                        | Severity | Status                   |
|---------------------|----------------------------------------------------------------------------------------------|----------|--------------------------|
| :red_circle:          | **[C-01] Checkpoint Views Denial of Service Due to Quadratic Memory Expansion Costs**        | Critical | :white_check_mark: Fixed |
| :orange_circle:     | **[H-01] Unbounded Migration Timeline Provides a Free Perpetual Call Option**                | High     | :white_check_mark: Fixed |
| :orange_circle:     | **[H-02] `EarlyVestFeeDistributor` Can Be Simplified to Reduce Risk and System Overhead**    | High     | :white_check_mark: Fixed |
| :yellow_circle:     | **[M-01] Incorrect Reporting of Claimable Amounts Due to Vested Entries**                    | Medium   | :white_check_mark: Fixed |
| :large_blue_circle: | **[L-01] Inefficient Storage Usage in `EscrowMigrator` Limiting Migration Methods**          | Low      | :white_check_mark: Fixed |
| :large_blue_circle: | **[L-02] Fee Rewards Distribution Fairness Concerns**                                        | Low      | :scroll: Noted    |
| :large_blue_circle: | **[L-03] Epoch 0 Rewards Unclaimability [Previously Known Issue]**                           | Low      | :scroll: Noted    |
| :black_circle:      | **[N-01] Code Duplication Across Checkpointing Functions**                                   | Note     | :white_check_mark: Fixed |
| :black_circle:      | **[N-02] Potential Token Dust Due to Rounding in `RewardEscrowV2` [Previously Known Issue]** | Note     | :white_check_mark: Fixed |
| :black_circle:      | **[N-03] Unused Code**                                                                       | Note     | :mag: Partially Fixed      |
| :black_circle:      | **[N-04] Documentation Improvements**                                                        | Note     | :white_check_mark: Fixed |
| :black_circle:      | **[N-05] Potential Cooldown Avoidance Through Community Liquid Staking Vaults**              | Note     | :scroll: Noted    |

# Severity Classification Framework

| Severity               | Impact: High | Impact: Medium | Impact: Low |
| ---------------------- | ------------ | -------------- | ----------- |
| **Likelihood: High**   | Critical     | High           | Medium      |
| **Likelihood: Medium** | High         | Medium         | Low         |
| **Likelihood: Low**    | Medium       | Low            | Low         |

----------

# :red_circle: [C-01] Checkpoint Views Denial of Service Due to Quadratic Memory Expansion Costs

### Severity

- Impact: High
- Likelihood: High

## Description

The `StakingRewardsV2` contract has an [internal method `_checkpointBinarySearch`](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/StakingRewardsV2.sol#L537) that casts a storage array to memory. This can make it unusable onchain due to the quadratic memory expansion costs. Although primarily a gas efficiency issue, the eventual unusability of the views onchain will cause a denial of service on contracts relying on these views when the gas costs surpass the available block gas limit. The first impacted method is likely to be the `totalSupplyAtTime` method, as the underlying checkpoint array is likely to grow very quickly. This is because checkpoints are added for most transactions ([`stake`](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/StakingRewardsV2.sol#L217), [`unstake`](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/StakingRewardsV2.sol#L240), and so on ..). For example, the memory cost expansion for an array 30K elements is 44M, and will surpass the block gas limit.

Specifically, to demonstrate the high likelihood of this impact, `EarlyVestFeeDistributor` [uses these views](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/EarlyVestFeeDistributor.sol#L173-L174) to allow users to claim rewards.  Furthermore, `EarlyVestFeeDistributor` also relies on using these methods in a loop during [`claimMany`](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/EarlyVestFeeDistributor.sol#L155-L165) which will cause this method to revert for even lower values. Notably, the [V1 `StakingRewards`](https://optimistic.etherscan.io/address/0x6e56a5d49f775ba08041e28030bc7826b13489e0) contract has above 70K EOA transaction at this time, not counting any transactions executed by contracts. This high volume of transactions on the V1 contract further demonstrates the high likelihood of this array reaching similar lengths in the V2 contract.

## Recommendations

Use `storage` instead of `memory` in the method signature to prevent copying the entire array into memory, ensuring gas costs remain logarithmic instead of quadratic. Note that this change will necessitate altering the method visibility from `pure` to `view`. This will reduce the gas costs of this method for the same 30K elements array to just 12000 gas.

## Status: :white_check_mark: Fixed

----------

# :orange_circle: [H-01] Unbounded Migration Timeline Provides a Free Perpetual Call Option

### Severity

- Impact: Medium
- Likelihood: High
## Description

If an open-ended migration timeline is allowed, locked KWENTA that is released during the V1 early vesting step will remain partially liquid for an undetermined period, while still allowing the migration to be completed at a later time. Although users delaying the second migration step forgo potential staking rewards, many may recognize a valuable trading opportunity. This is because the migration of an entry can be finalized in the future, including after its `endTime`. This creates two issues: 

1. Traders may sell the liquid portion, and leave the locked, unfinalized, portion as a free call option. For example, assume a trader can vest an entry at 50% early vest fee. They then have a perpetual free option to claim their remaining 50%,. This is because in the future, they may temporarily buy the needed 50%, complete the migration, vest the entry, and sell the entire 100%. They may not even need funds to complete it if a flashloan of KWENTA is available at the time.  Note that waiting until `endTime` is not necessary, since the option exists prior to that time, although due to the early vesting fee it unlocks a smaller amount of tokens (in addition to returning the liquid portion required for the final step).
2. The ability to temporarily trade the liquid tokens may create a self-fulfilling prophecy of a decline in price: traders that anticipate a drop in price will have additional temporary supply to sell.

Both of these scenarios can cause significant selling pressure after migration initiation, and cause losses to those holders of KWENTA who will complete the migration promptly.
## Recommendations

To reduce the potential destabilization it's possible to implement a late migration fee that will be distributed among stakers. This would serve as an added incentive for users to complete their migrations promptly. As a suggestion, the fee could grow linearly, starting one week after the initiation of migration for each user. Additionally, a global time window for the completion of the migration can be added, after which all  `EscrowMigrator` will be paused, and any remaining funds in it will be distributed to stakers.

## Status: :white_check_mark: Fixed

A two week deadline relative to the initiation of migration for each user was implemented.

----------

# :orange_circle: [H-02] `EarlyVestFeeDistributor` Can Be Simplified to Reduce Risk and System Overhead

### Severity

- Impact: Medium
- Likelihood: High

## Description

The contract introduces unnecessary complexity that presents several challenges:

- The complicated logic increases the surface for vulnerabilities. An example of this is the checkpoint views DoS vulnerability described previously.
- It operates based on implicit assumptions about the system that may be invalid in the future. For example, the assumption that the cooldown duration exceeds the epoch length.
- Users are inconvenienced by having to periodically claim rewards from this additional contract.
- An associated UI needs to be developed and maintained.
- It creates configuration complications related to the alignment of the fee epoch and minting epoch.

## Recommendations

In contrast, a more straightforward contract can be used as a step between the `SupplySchedule` and `StakingRewardsV2` [during minting](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/SupplySchedule.sol#L250-L251):

```solidity
/// SupplySchedule should call this contract instead of calling StakingRewardsV2 directly
contract NotifiableFeesAccumulator .. {
    ...	
    function notifyRewardAmount(uint mintedAmount) external onlySupplySchedule {
        delete mintedAmount; // not used
        uint currentBalance = kwenta.balanceOf(address(this));
        kwenta.transfer(address(stakingRewardsV2), currentBalance);
        stakingRewardsV2.notifyRewardAmount(currentBalance); 
        }
    ...
}
```

This simplified contract should then be [set as `stakingRewards` on `SupplySchedule`](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/SupplySchedule.sol#L293) and as [`supplySchedule` on `StakingRewardsV2`](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/StakingRewardsV2.sol#L147).

Adopting such a simplified contract offers multiple benefits over the existing `EarlyVestFeeDistributor`:

- The contract is short and simple.
- It eliminates the need for `StakingRewardsV2` to implement the checkpointing logic.
- For users and UI, the entire process becomes transparent and requires no additional effort.
- It improves the fee distribution fairness throughout the epoch by using the continuous mechanism instead of snapshots.
- It aligns naturally with the existing minting and reward update schedule.

## Status: :white_check_mark: Fixed

----------

# :yellow_circle: [M-01] Incorrect Reporting of Claimable Amounts Due to Vested Entries

### Severity

- Impact: Low
- Likelihood: High

## Description

The `RewardEscrowV2` contract's `vest` method does not update the `escrowAmount` for vested entries. Instead, it [only "burns" them](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/RewardEscrowV2.sol#L373-L374) - transferring their ownership to the zero address. However, the internal [method `_claimableAmount`](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/RewardEscrowV2.sol#L329-L343) does not factor this in. As a result, it reports amounts that have already been vested as claimable. This leads to the `getVestingEntryClaimable` and `getVestingQuantity` views reporting inaccurate values because entries that have been vested (and thus burned) are still included in the claimable sum. It's important to highlight that `address(0)` can only own burned entries, as both the minting to it and transferring to it are restricted by the token methods.

## Recommendations

Ensure that the `_claimableAmount` method returns a value of 0 for entries owned by `address(0)`.

## Status: :white_check_mark: Fixed

Vested entries are updated to have 0 `escrowAmount`.

----------

# :large_blue_circle: [L-1] Inefficient Storage Usage in `EscrowMigrator` Limiting Migration Methods

### Severity

- Impact: Low
- Likelihood: Medium
## Description

The `EscrowMigrator` contract's `IEscrowMigrator.VestingEntry` utilizes two storage slots for storing an amount of KWENTA and a `bool`.  The increased gas costs reduce the maximum number of iterations achievable within a single block for the migration methods.
## Recommendations

1. Pack the limited size `uint` and `bool` of `IEscrowMigrator.VestingEntry` into a single storage slot to conserve gas. While the total supply of KWENTA is not limited at the contract level, it is in practice unlikely to surpass the limits of even `88` bits, so using a `uint248` should be still extremely safe. This will facilitate more iterations within a single call to the `registerEntries` method, especially within a single Optimism Bedrock block. 
2. As an even more efficient approach, consider eliminating the `migrated` flag. Instead, set the `escrowAmount` to 0 as an indication of a migrated entry. By doing so, in addition to the savings in `registerEntries`, a gas refund will be issued when setting the storage slot to 0 during the `migrateEntries` method. This will allow more iterations to be executed in a single block when calling `migrateEntries`.

## Status: :white_check_mark: Fixed

The first recommended alternative was implemented.

----------

# :large_blue_circle: [L-2] Fee Rewards Distribution Fairness Concerns

### Severity

- Impact: Low
- Likelihood: Medium

## Description

There are several fairness concerns identified with the rewards distribution mechanism in the contract:

1. **Use of Balance Snapshots**: The contract determines eligibility for an epoch based on balances at the start of the epoch. Consequently, a user who unstakes right at the onset of an epoch will still be eligible to claim all rewards for that entire epoch, even though they've already withdrawn their tokens. On the other hand, choosing the epoch's end is no better, as a user staking just before that end would be able to claim all rewards for the past epoch. This is an inherent problem caused by using a single balance snapshot to account for an entire epoch.
2. **Inactive Contract Implications**: If the contract remains inactive over several weeks, the rewards will be distributed equally over those weeks. This method is likely to be inequitable for users, particularly if the rewards fluctuated significantly between weeks.
3. **Staking Cooldown Assumptions**: The contract implicitly assumes that the staking cooldown is longer than an epoch to maintain a fair distribution. In future updates, if this assumption becomes invalid and this contract is overlooked, it could lead to additional fairness issues.

## Recommendations

1. Avoid using balance snapshots. Instead, utilize a continuous mechanism similar to the one employed in `StakingRewards` to achieve a more equitable distribution.
2. If there are any future protocol upgrades, ensure the cooldown is not shortened to less than a week.
3. Ensure that balances are checkpointed weekly if the contract was inactive.

## Status: :scroll: Noted

> "Previously known and viewed as an acceptable solution, at least for now. Also currently mitigated by switch to `StakingRewardsNotifier`."

----------

# :large_blue_circle: [L-3] Epoch 0 Rewards Unclaimability [Previously Known Issue]

### Severity

- Impact: Medium
- Likelihood: Low

## Description

Rewards designated for epoch 0 and any KWENTA tokens sent to the contract during this epoch will remain fully or partially unclaimable. This is because, for epoch 0, staking balances will be queried as 0. As a consequence, only rewards sent after epoch 1's start will be accessible and claimable by stakeholders.

## Recommendations

1. To prevent this issue adjust the `startTime` to be `startOfThisWeek + 1 weeks`. By doing this, the epochs will be offset into the future, ensuring that all tokens can be claimed during the very first epoch.
2. Add a check in the `checkpointToken` function to revert for timestamps preceding `startTime`. 

## Status: :scroll: Noted

> "Some debate within the team about this issue, and your approach versus the wait 1 week approach. We have decided not to bother changing it at the moment as we have followed your recommendation to use `StakingRewardsNotifier` instead."

----------

# :black_circle: [N-01] Code Duplication Across Checkpointing Functions

## Description

In the `StakingRewardsV2` contract, significant code duplication is evident among the functions [`_addBalancesCheckpoint`](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/StakingRewardsV2.sol#L569-L584), [`_addEscrowedBalancesCheckpoint`](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/StakingRewardsV2.sol#L589-L604), and [`_addTotalSupplyCheckpoint`](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/StakingRewardsV2.sol#L608-L624). 
## Recommendations

To enhance clarity and maintainability, refactor the code by extracting the common logic from the mentioned functions into a separate method that accepts a storage pointer to the relevant checkpoints array.

## Status: :white_check_mark: Fixed

----------

# :black_circle: [N-02] Potential Token Dust Due to Rounding in `RewardEscrowV2` [Previously Known Issue]

## Recommendations

To circumvent the accumulation of residual KWENTA tokens in the contract [due to rounding](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/RewardEscrowV2.sol#L411), instead of transferring the `proportionalFee`, the full remainder of `totalFee - proportionalFee` should be used for the second transfer. 

## Status: :white_check_mark: Fixed

----------

# :black_circle: [N-03] Unused Code

- The [`Checkpoint.blk`](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/interfaces/IStakingRewardsV2.sol#L14) is not used onchain. It's recommended to remove and realize the gas savings. To derive the block offchain use the timestamp stored in the `ts` variable.
    
- If the `MustClaimStakingRewards()` function is removed, as suggested in [PR #234](https://github.com/Kwenta/token/pull/234/files), the `stakingRewardsV1` will become redundant. It's recommended to remove `stakingRewardsV1` from the contract.

- As [the `daysToOffsetBy`](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/EarlyVestFeeDistributor.sol#L53) will be [set to a value of 0](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/scripts/Migrate.s.sol#L320), it's advisable to remove this parameter from the contract to reduce complexity. If a future need to reintroduce the `daysToOffsetBy` arises, developers can always refer back to the git history to retrieve the previous implementation.

## Status: :mag: Partially Fixed

Second recommendation implemented. Regarding the first and third recommendations the team responded:

> "We decided to keep the `block.number` in the `Checkpoint` struct in case we need it in the future. We have however used packing to reduce the gas impact of this."

> "Since `TokenDistributor` is now being postponed for use in the future, the offset will likely be used then."

----------

# :black_circle: [N-04] Documentation Improvements

- The [comment in `RewardEscrowV2` is incorrect](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/RewardEscrowV2.sol#L64). This seems to be due to a copy-paste error from the previous line. 
    
- The [comment in `RewardEscrowV2` is misleading](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/RewardEscrowV2.sol#L373). Contrary to what's described, the entry isn't updated. Instead, its ownership is transferred to `address(0)`.
    
- The [comment in `IEscrowMigrator`](https://github.com/Kwenta/token/blob/9cceb6d5efd73b8e4794d253ce36daefe7123e0c/contracts/interfaces/IEscrowMigrator.sol#L149) should be more descriptive. Specifically, it should state that the expected approval is from the beneficiary's account and that they must pull the KWENTA from the integrator contract before calling `migrateIntegratorEntries`. 

## Status: :white_check_mark: Fixed

----------

# :black_circle: [N-05] Potential Cooldown Avoidance Through Community Liquid Staking Vaults

## Description

A third-party liquid staking vault could potentially be established, allowing users to circumvent the staking cooldown. The design of such a vault could employ a minimal proxy factory to initiate single-use staking accounts for each deposit or batch of deposits. In return, users would receive an ERC20 share token. Once the vault has accumulated deposits that have surpassed the cooldown period, new users could redeem their shares as needed without having to be subject to the cooldown delay. Additionally, since escrow entries are transferable, the staking reward entries can easily be transferred to individual users on redemption. The benefit for the users of such a setup is in the option of bypassing the cooldown, which could be preferred by many users. Additionally, such a mechanism could enable the sale of governance rights tied to staked positions, offering an extra yield stream for users with smaller holdings that don't typically participate in governance.

## Recommendations

Given the potential implications of such workarounds on governance integrity, it's advised to actively monitor contract usage. If such third-party staking vaults gain traction, appropriate measures should be taken to address or limit these loopholes utilizing the contracts' upgradeability.

## Status: :scroll: Noted

> "Don't have a viable solution to this problem at the moment."