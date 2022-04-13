// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Inheritance
import "./OwnedUpgradeable.sol";

// https://docs.synthetix.io/contracts/source/contracts/pausable
abstract contract Pausable is OwnedUpgradeable {
    uint public lastPauseTime;
    bool public paused;

    function __Pausable_init(address _owner) public initializer {
        __Owned_init(_owner);
        require(owner != address(0), "Owner must be set");
    }

    /**
     * @notice Change the paused state of the contract
     * @dev Only the contract owner may call this.
     */
    function setPaused(bool _paused) external onlyOwner {
        // Ensure we're actually changing the state before we do anything
        if (_paused == paused) {
            return;
        }

        // Set our paused state.
        paused = _paused;

        // If applicable, set the last pause time.
        if (paused) {
            lastPauseTime = block.timestamp;
        }

        // Let everyone know that our pause state has changed.
        emit PauseChanged(paused);
    }

    event PauseChanged(bool isPaused);

    modifier notPaused {
        _notPaused();
        _;
    }

    function _notPaused() internal view {
        require(!paused, "This action cannot be performed while the contract is paused");
    }
}
