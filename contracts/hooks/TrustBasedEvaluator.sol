// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title TrustBasedEvaluator
 * @notice Example evaluator that uses an external trust oracle to verify
 *         job deliverables. Demonstrates how to build an ERC-8183 evaluator
 *         that goes beyond simple approve/reject.
 *
 * @dev This is a REFERENCE IMPLEMENTATION — adapt for your use case.
 *
 * Pattern:
 *   1. Provider submits deliverable
 *   2. AgenticCommerce calls evaluator.evaluate(jobId) (or off-chain keeper)
 *   3. Evaluator checks provider trust score from oracle
 *   4. Returns complete() or reject() to AgenticCommerce
 *   5. [v1.1] Calls registry.recordOutcome() to update on-chain performance stats
 *
 * Trust oracle interface:
 *   getUserData(address) → { reputationScore, initialized, ... }
 *
 * v1.1 additions:
 *   - Feedback loop: after each evaluation, recordOutcome() is called on the
 *     EvaluatorRegistry so this evaluator's stats are tracked on-chain.
 *     This allows the registry to rank evaluators by real-world performance,
 *     making the discovery mechanism self-optimizing over time.
 */

/// @notice Minimal trust oracle interface
interface ITrustOracle {
    struct UserReputation {
        uint256 reputationScore;
        uint256 totalReviews;
        bool initialized;
        uint256 lastUpdated;
    }
    function getUserData(address user) external view returns (UserReputation memory);
}

/// @notice Minimal AgenticCommerce interface for evaluation
interface IAgenticCommerce {
    enum JobStatus { Open, Funded, Submitted, Completed, Rejected, Expired }

    struct Job {
        uint256 id;
        address client;
        address provider;
        address evaluator;
        string description;
        uint256 budget;
        uint256 expiredAt;
        JobStatus status;
        address hook;
    }

    function getJob(uint256 jobId) external view returns (Job memory);
    function complete(uint256 jobId, bytes32 reason, bytes calldata optParams) external;
    function reject(uint256 jobId, bytes32 reason, bytes calldata optParams) external;
}

/// @notice EvaluatorRegistry interface — only the methods we need for the feedback loop
interface IEvaluatorRegistry {
    function recordOutcome(address evaluator, bool approved) external;
}

contract TrustBasedEvaluator is OwnableUpgradeable {
    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    ITrustOracle public oracle;
    IAgenticCommerce public agenticCommerce;

    /// @notice Optional EvaluatorRegistry for on-chain performance feedback loop.
    ///         Can be address(0) if the registry is not deployed or not opted in.
    IEvaluatorRegistry public registry;

    /// @notice Minimum trust score (0-100) to auto-approve
    uint256 public minTrustScore;

    /// @notice Tracks evaluated jobs to prevent double-evaluation
    mapping(uint256 => bool) public evaluated;

    /// @notice Stats (local to this evaluator — mirrors what registry tracks globally)
    uint256 public totalEvaluated;
    uint256 public totalApproved;
    uint256 public totalRejected;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event JobEvaluated(
        uint256 indexed jobId,
        address indexed provider,
        bool approved,
        uint256 trustScore,
        bytes32 reason
    );
    event RegistryUpdated(address indexed registry);
    event OutcomeReportFailed(address indexed registry, bytes reason);

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error TrustBasedEvaluator__AlreadyEvaluated(uint256 jobId);
    error TrustBasedEvaluator__NotSubmitted(uint256 jobId);
    error TrustBasedEvaluator__NotAssignedEvaluator(uint256 jobId);

    /*//////////////////////////////////////////////////////////////
                            INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function initialize(
        address oracle_,
        address agenticCommerce_,
        uint256 minTrustScore_,
        address owner_
    ) external initializer {
        __Ownable_init(owner_);
        oracle = ITrustOracle(oracle_);
        agenticCommerce = IAgenticCommerce(agenticCommerce_);
        minTrustScore = minTrustScore_;
        // registry defaults to address(0) — set later via setRegistry()
    }

    /*//////////////////////////////////////////////////////////////
                        CORE: EVALUATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Evaluate a submitted job. Called by anyone (typically off-chain keeper).
     * @param jobId The job to evaluate
     *
     * Flow:
     *   1. Verify job is in Submitted status
     *   2. Verify this contract is the assigned evaluator
     *   3. Check provider trust score
     *   4. Auto-approve if score >= minTrustScore, reject otherwise
     *   5. Call complete() or reject() on AgenticCommerce
     *   6. [v1.1] Report outcome to EvaluatorRegistry (feedback loop)
     *             — uses a try/catch so registry failures never block evaluation
     */
    function evaluate(uint256 jobId) external {
        if (evaluated[jobId]) revert TrustBasedEvaluator__AlreadyEvaluated(jobId);

        IAgenticCommerce.Job memory job = agenticCommerce.getJob(jobId);

        if (job.status != IAgenticCommerce.JobStatus.Submitted) {
            revert TrustBasedEvaluator__NotSubmitted(jobId);
        }
        if (job.evaluator != address(this)) {
            revert TrustBasedEvaluator__NotAssignedEvaluator(jobId);
        }

        evaluated[jobId] = true;
        totalEvaluated++;

        // Check provider trust
        ITrustOracle.UserReputation memory rep = oracle.getUserData(job.provider);
        uint256 score = rep.initialized ? rep.reputationScore : 0;

        bool approved = score >= minTrustScore;
        bytes32 reason = approved
            ? bytes32("trust_approved")
            : bytes32("trust_too_low");

        if (approved) {
            totalApproved++;
            agenticCommerce.complete(jobId, reason, "");
        } else {
            totalRejected++;
            agenticCommerce.reject(jobId, reason, "");
        }

        emit JobEvaluated(jobId, job.provider, approved, score, reason);

        // [v1.1] Feedback loop — report outcome to the registry.
        // This updates our on-chain performance stats so the registry can rank
        // evaluators by real-world success rates.
        // We use try/catch so that a registry failure (e.g., not authorized yet,
        // registry upgraded, etc.) never causes the evaluation itself to revert.
        _reportOutcomeToRegistry(approved);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the EvaluatorRegistry address for the feedback loop.
     * @dev Set to address(0) to disable registry reporting.
     *      This contract must also be authorized in the registry via
     *      registry.setAuthorized(address(this), true) for recordOutcome to succeed.
     * @param registry_ Address of the EvaluatorRegistry (or address(0) to disable)
     */
    function setRegistry(address registry_) external onlyOwner {
        registry = IEvaluatorRegistry(registry_);
        emit RegistryUpdated(registry_);
    }

    /**
     * @notice Update minimum trust score threshold.
     * @param score New minimum score (0-100)
     */
    function setMinTrustScore(uint256 score) external onlyOwner {
        minTrustScore = score;
    }

    /**
     * @notice Update trust oracle address.
     * @param oracle_ New oracle address
     */
    function setOracle(address oracle_) external onlyOwner {
        oracle = ITrustOracle(oracle_);
    }

    /**
     * @notice Update AgenticCommerce address.
     * @param agenticCommerce_ New AgenticCommerce address
     */
    function setAgenticCommerce(address agenticCommerce_) external onlyOwner {
        agenticCommerce = IAgenticCommerce(agenticCommerce_);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Attempts to call registry.recordOutcome(). Silently catches all failures.
     *      Emits OutcomeReportFailed with the low-level error bytes if it fails,
     *      so operators can diagnose authorization or registry issues off-chain.
     */
    function _reportOutcomeToRegistry(bool approved) internal {
        IEvaluatorRegistry reg = registry;
        if (address(reg) == address(0)) return;

        try reg.recordOutcome(address(this), approved) {
            // success — stats updated in registry
        } catch (bytes memory reason) {
            // never revert the parent transaction; just surface the failure as an event
            emit OutcomeReportFailed(address(reg), reason);
        }
    }
}
