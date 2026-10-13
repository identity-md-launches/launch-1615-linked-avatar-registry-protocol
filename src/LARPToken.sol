// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Linked Avatar Registry Protocol token
/// @notice Fixed supply of one billion LARP, with 18 decimals and ordinary ERC-20 transfers.
/// @dev The immediate deployer receives the entire supply. During the IMD launch this is the factory.
contract LARPToken is ERC20 {
    /// @notice The complete supply, denominated in the token's smallest unit.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Linked Avatar Registry Protocol", "LARP") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
