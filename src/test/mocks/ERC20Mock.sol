// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import "solmate/tokens/ERC20.sol";

contract ERC20Mock is ERC20 {
  constructor() ERC20("MockToken", "MCK", 24) {
    _mint(msg.sender, 10e8);
  }

  function mint(uint256 value) external {
    _mint(msg.sender, value);
  }
}
