// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import './interfaces/IvKwentaRedeemer.sol';
import './utils/ERC20.sol';

contract vKwentaRedeemer is IvKwentaRedeemer, ReentrancyGuard {
    // token to be burned
    address public immutable vToken;
    // token to be redeemed
    address public immutable token;


    event Redeemed(address redeemer, uint256 redeemedAmount);

    constructor(address _vToken, address _token) {
        vToken = _vToken;
        token = _token;
    }

    /*
     * Allows caller to redeem an equivalent amount of token for vToken
     * @notice caller must approve this contract to spend vToken
     * @notice vToken is burned prior to transfer of token
     */
    function redeem() override external nonReentrant {
        uint vTokenBalance = IERC20(vToken).balanceOf(msg.sender);

        // ensure valid balance
        require(vTokenBalance > 0, "vKwentaRedeemer: No balance to redeem");
        require(vTokenBalance <= IERC20(token).balanceOf(address(this)), 
            "vKwentaRedeemer: Insufficient contract balance"
        );

        // lock vToken in this contract
        require(
            IERC20(vToken).transferFrom(msg.sender, address(this), vTokenBalance),
            "vKwentaRedeemer: vToken transfer failed"
        );

        // transfer token
        require(
            IERC20(token).transfer(msg.sender, vTokenBalance),
            "vKwentaRedeemer: token transfer failed"
        );

        emit Redeemed(msg.sender, vTokenBalance);
    }

}