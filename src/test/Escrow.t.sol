// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../Escrow.sol";
import "./mocks/ERC20Mock.sol";
import {ArrayUtils} from "../utils/ArrayUtils.sol";

contract LabeledAccountsTest is Test {
  function account(string memory _label) internal returns (address addr) {
    addr = vm.addr(uint256(keccak256(abi.encodePacked(_label))));
    vm.label(addr, _label);
    return addr;
  }
}

contract EscrowTest is LabeledAccountsTest {
  using ArrayUtils for address[];

  Escrow public escrow;
  ERC20Mock public mockToken;
  uint256 public _defaultTimeLock = 365 days;
  uint256 public _initialHeartbeat;

  address OWNER = account("owner");
  address SOMEONE = account("someone");
  address BENEFICIARY = account("beneficiary");

  function setUp() public {
    hoax(OWNER);
    escrow = new Escrow(_defaultTimeLock);
    mockToken = new ERC20Mock();
    _initialHeartbeat = block.timestamp;
  }

  function testConstruction() public {
    assertEq(escrow.owner(), OWNER);
  }

  function testDepositTokenBySomeone() public {
    hoax(SOMEONE);
    uint initialBalance = mockToken.balanceOf(SOMEONE);

    uint tokenSupply = 10;
    fundEscrowWithMockToken(tokenSupply);

    assertEq(mockToken.balanceOf(address(escrow)), tokenSupply);
    assertEq(mockToken.balanceOf(SOMEONE), initialBalance);
    assertEq(escrow.getTokenBalance(address(mockToken)), tokenSupply);
    assertTrue(escrow.getTokensInEscrow().includes(address(mockToken)));
    assertEq(escrow.lastHeartbeat(), _initialHeartbeat);
  }

  function testReceiveAndDepositEtherBySomeone() public {
    startHoax(SOMEONE, 10 ether);

    bool success = payable(escrow).send(1 ether);
    assertTrue(success);

    escrow.deposit{value: 1 ether}();

    vm.stopPrank();

    assertEq(escrow.getBalance(), 2 ether);
    assertEq(SOMEONE.balance, 8 ether);
    assertEq(escrow.lastHeartbeat(), _initialHeartbeat);
  }

  function testWithdrawEthByOwner() public {
    startHoax(OWNER, 1 ether);

    escrow.deposit{value: 1 ether}();
    uint256 balanceBeforeWithdraw = OWNER.balance;
    escrow.withdraw(1 ether);

    vm.stopPrank();

    assertEq(escrow.getBalance(), 0);
    assertEq(balanceBeforeWithdraw, 0);
    assertEq(OWNER.balance, 1 ether);
    assertEq(escrow.lastHeartbeat(), block.timestamp);
  }

  function testWithdrawTokenByOwner() public {
    uint tokenSupply = 10;
    fundEscrowWithMockToken(tokenSupply);

    hoax(OWNER);
    escrow.withdrawToken(address(mockToken), tokenSupply);

    assertEq(mockToken.balanceOf(address(escrow)), 0);
    assertEq(escrow.getTokenBalance(address(escrow)), 0);
    assertEq(mockToken.balanceOf(OWNER), tokenSupply);
    assertEq(escrow.lastHeartbeat(), block.timestamp);
  }

  function testIsUnlocked() public {
    assertTrue(!escrow.isUnlocked());

    uint256 skipTime = _defaultTimeLock + 1 days;
    skip(skipTime);

    assertTrue(escrow.isUnlocked());
    rewind(skipTime);
  }

  function testAddAndRemoveBeneficiaryByOwner() public {
    assertEq(escrow.totalBeneficiaries(), 0);

    hoax(OWNER);
    escrow.addBeneficiary(BENEFICIARY);

    assertTrue(escrow.isBeneficiary(BENEFICIARY));
    assertEq(escrow.totalBeneficiaries(), 1);

    hoax(OWNER);
    escrow.removeBeneficiary(BENEFICIARY);
    assertTrue(!escrow.isBeneficiary(BENEFICIARY));
    assertEq(escrow.totalBeneficiaries(), 0);
  }

  function testSettleOneOfOneBeneficiary() public {
    hoax(OWNER);
    escrow.addBeneficiary(BENEFICIARY);

    uint256 totalEth = 10 ether;
    uint256 totalTokenSupply = 10;
    escrow.deposit{value: totalEth}();

    fundEscrowWithMockToken(totalTokenSupply);

    unlockEscrow();

    hoax(BENEFICIARY, 0 ether);
    escrow.settleBeneficiary();

    assertEq(BENEFICIARY.balance, totalEth);
    assertEq(mockToken.balanceOf(BENEFICIARY), totalTokenSupply);
    assertEq(escrow.getTokenBalance(address(mockToken)), 0);
  }

  function testSettleOneOfMultipleBeneficiaries() public {
    startHoax(OWNER);
    escrow.addBeneficiary(BENEFICIARY);
    escrow.addBeneficiary(account('another_beneficiary'));
    escrow.addBeneficiary(account('yet_another_beneficiary'));
    escrow.addBeneficiary(account('last_beneficiary'));
    vm.stopPrank();

    uint256 totalEth = 10 ether;
    escrow.deposit{value: totalEth}();

    uint256 totalTokenSupply = 100;
    fundEscrowWithMockToken(totalTokenSupply);

    unlockEscrow();

    hoax(BENEFICIARY, 0 ether);
    escrow.settleBeneficiary();

    assertEq(BENEFICIARY.balance, 2.5 ether);
    assertEq(mockToken.balanceOf(BENEFICIARY), 25);
    assertEq(escrow.getBalance(), 7.5 ether);
    assertEq(escrow.getTokenBalance(address(mockToken)), 75);
  }

  function testSettleByNonBeneficiary() public {
    fundEscrowWithMockToken(10);
    escrow.deposit{value: 1 ether}();

    hoax(SOMEONE);
    vm.expectRevert("ESCROW_LOCKED");
    escrow.settleBeneficiary();

    assertEq(escrow.getBalance(), 1 ether);
    assertEq(escrow.getTokenBalance(address(mockToken)), 10);
  }

  function testAddAndRemoveBeneficiaryBySomeone() public {
    hoax(SOMEONE);
    vm.expectRevert("OWNER_RESTRICTED");
    escrow.addBeneficiary(BENEFICIARY);
    assertTrue(!escrow.isBeneficiary(BENEFICIARY));

    hoax(OWNER);
    escrow.addBeneficiary(BENEFICIARY);

    hoax(SOMEONE);
    vm.expectRevert("OWNER_RESTRICTED");
    escrow.removeBeneficiary(BENEFICIARY);
    assertTrue(escrow.isBeneficiary(BENEFICIARY));

    vm.stopPrank();
  }

  function testResign() public {
    hoax(OWNER);
    escrow.addBeneficiary(BENEFICIARY);

    hoax(SOMEONE);
    vm.expectRevert("BENEFICIARY_RESTRICTED");
    escrow.resign();
    assertTrue(escrow.isBeneficiary(BENEFICIARY));

    hoax(BENEFICIARY);
    escrow.resign();
    assertTrue(!escrow.isBeneficiary(BENEFICIARY));
  }

  function unlockEscrow() internal {
    if(!escrow.isUnlocked()) {
      uint256 skipTime = _defaultTimeLock + 1 days;
      skip(skipTime);
    }
  }

  function fundEscrowWithMockToken(uint256 amount) internal {
    mockToken.mint(amount);
    mockToken.approve(address(escrow), amount);
    escrow.depositToken(address(mockToken), amount);
  }
}
