pragma solidity 0.8.10;

library ArrayUtils {
  function indexOf(address[] memory self, address e) internal pure returns (int) {
    for (uint i = 0; i < self.length; i++)
      if (self[i] == e) return int(i);
    return int(-1);
  }

  function includes(address[] memory a, address e) internal pure returns (bool) {
    return indexOf(a, e) != int(-1);
  }
}
