// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TreasuryVault is Ownable, ReentrancyGuard {
    mapping(address => uint256) public balances;

    event Deposited(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);

    constructor() Ownable(msg.sender) {}

    function deposit() external payable {
        require(msg.value > 0, "TreasuryVault: zero amount");
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function withdraw(address to, uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "TreasuryVault: zero amount");
        require(balances[msg.sender] >= amount, "TreasuryVault: insufficient balance");
        balances[msg.sender] -= amount;
        payable(to).transfer(amount);
        emit Withdrawn(to, amount);
    }

    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }
}
