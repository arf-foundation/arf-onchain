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

    /**
     * @dev Registers or reactivates a policy under `policyHash`.
     *
     * `bytes32(0)` is refused, permanently. `ExecutionGuard.execute()` used
     * to treat a zero `policyHash` as an ambient "no policy required"
     * default, conflating "nobody configured a policy" with "a policy was
     * deliberately not required" -- the same bit pattern meant two different
     * things. That default is gone; every attestation must now reference a
     * registered, active hash, including an explicit "unpoliced" sentinel
     * (see `arf_enterprise.onchain.policy_spec.UNPOLICED_SPEC`).
     *
     * If this function let an owner register zero anyway, the ambiguity
     * would simply move here: one `setPolicy(0, ...)` call -- deliberate,
     * or a registration script with an uncomputed-hash bug that defaults to
     * zero -- would silently make every unconfigured attestation valid
     * again. Refusing it here means zero can never become active through
     * any path, not merely by convention.
     */
    function setPolicy(bytes32 policyHash, string calldata description) external onlyOwner {
        require(policyHash != bytes32(0), "PolicyRegistry: zero hash is reserved");
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
