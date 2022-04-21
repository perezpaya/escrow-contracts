// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "solmate/tokens/ERC20.sol";
import "forge-std/console.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ArrayUtils} from "./utils/ArrayUtils.sol";

error TokenTransferFailed(uint256 amount, address token, address from, address to);

contract Escrow {
  using SafeTransferLib for address;
  using SafeTransferLib for ERC20;
  using ArrayUtils for address[];

  event Deposit(address depositor, uint256 amount);
  event Withdraw(uint256 amount);
  event DepositToken(address depositor, address token, uint256 amount);
  event WithdrawToken(address token, uint256 amount);
  event BeneficiaryAdded(address beneficiary);
  event BeneficiaryRemoved(address beneficiary);
  event BeneficiaryWithdrawal(address beneficiary);
  event Heartbeat(uint256 time);

  address public owner;
  uint256 public lastHeartbeat;
  uint256 public timeLock;

  mapping(address => uint) public tokenBalances;
  address[] public tokensInEscrow;

  mapping(address => bool) beneficiaries;
  uint256 public totalBeneficiaries;

  constructor(uint256 _timeLock) {
    owner = msg.sender;
    lastHeartbeat = block.timestamp;
    timeLock = _timeLock;
  }

  modifier onlyOwner() {
    require(isOwner(), "OWNER_RESTRICTED");
    _;
  }

  modifier onlyBeneficiaries() {
    require(isBeneficiary(msg.sender), "BENEFICIARY_RESTRICTED");
    _;
  }

  modifier onlyIfUnlocked() {
    require(isUnlocked(), "ESCROW_LOCKED");
    _;
  }

  modifier sendsHeartbeat() {
    if (isOwner()) {
      lastHeartbeat = block.timestamp;
      emit Heartbeat(block.timestamp);
    }
    _;
  }

  function isOwner() internal view returns (bool) {
    return msg.sender == owner;
  }

  function isUnlocked() public view returns (bool) {
    return block.timestamp >= (lastHeartbeat + timeLock);
  }

  function getBalance() public view returns (uint256) {
    return address(this).balance;
  }

  function getTokenBalance(address token) public view returns (uint256) {
    return tokenBalances[token];
  }

  function getTokensInEscrow() external view returns (address[] memory) {
    return tokensInEscrow;
  }

  function deposit() sendsHeartbeat external payable {}

  function depositToken(address token, uint256 amount) sendsHeartbeat external {
    ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    tokenBalances[token] += amount;
    if (!tokensInEscrow.includes(token)) tokensInEscrow.push(token);
    emit DepositToken(msg.sender, token, amount);
  }

  function withdraw(uint256 amount) sendsHeartbeat external onlyOwner {
    require(amount <= getBalance(), "INVALID_AMOUNT");
    owner.safeTransferETH(amount);
  }

  function withdrawToken(address token, uint256 amount) sendsHeartbeat external onlyOwner {
    require(tokenBalances[token] >= amount, "INVALID_TOKEN_AMOUNT");
    ERC20(token).safeTransfer(owner, amount);
  }

  function addBeneficiary(address beneficiary) onlyOwner sendsHeartbeat external {
    beneficiaries[beneficiary] = true;
    totalBeneficiaries++;
    emit BeneficiaryAdded(beneficiary);
  }

  function removeBeneficiary(address beneficiary) onlyOwner sendsHeartbeat external {
    _removeBeneficiary(beneficiary);

    emit BeneficiaryRemoved(beneficiary);
  }

  function _removeBeneficiary(address beneficiary) internal {
    delete beneficiaries[beneficiary];
    totalBeneficiaries--;
  }

  function isBeneficiary(address beneficiary) public view returns (bool) {
    return beneficiaries[beneficiary];
  }

  function settleBeneficiary() onlyIfUnlocked onlyBeneficiaries external {
    uint256 allowedEth =  getBalance() / totalBeneficiaries;
    msg.sender.safeTransferETH(allowedEth);
    for (uint256 i = 0; i < tokensInEscrow.length; i++) {
      settleBeneficiaryToken(tokensInEscrow[i]);
    }
    _removeBeneficiary(msg.sender);
    if (totalBeneficiaries == 0) delete tokensInEscrow;
  }

  function settleBeneficiaryToken(address token) internal {
    uint256 allowedTokenAmount = getTokenBalance(token) / totalBeneficiaries;
    ERC20(token).safeTransfer(msg.sender, allowedTokenAmount);

    if (tokenBalances[token] > allowedTokenAmount) tokenBalances[token] -= allowedTokenAmount;
    else delete tokenBalances[token];
  }

  function resign() onlyBeneficiaries external {
    _removeBeneficiary(msg.sender);
  }

  receive() external payable {}
  fallback() external payable {}
}
