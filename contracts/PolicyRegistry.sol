// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PolicyRegistry is Ownable {
    struct Policy {
        bytes32 policyHash;
        string description;
        bool active;
    }

    mapping(bytes32 => Policy) public policies;

    event PolicySet(bytes32 indexed policyHash, string description);
    event PolicyDeactivated(bytes32 indexed policyHash);

    constructor() Ownable(msg.sender) {}

    function setPolicy(bytes32 policyHash, string calldata description) external onlyOwner {
        policies[policyHash] = Policy(policyHash, description, true);
        emit PolicySet(policyHash, description);
    }

    function deactivatePolicy(bytes32 policyHash) external onlyOwner {
        require(policies[policyHash].active, "PolicyRegistry: policy not active");
        policies[policyHash].active = false;
        emit PolicyDeactivated(policyHash);
    }

    function isPolicyActive(bytes32 policyHash) external view returns (bool) {
        return policies[policyHash].active;
    }
}
