// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {AttestationHook, IEAS, IAgenticCommerceReader} from "../contracts/hooks/AttestationHook.sol";
import {IACPHook} from "../contracts/IACPHook.sol";

/*//////////////////////////////////////////////////////////////
                        MOCK CONTRACTS
//////////////////////////////////////////////////////////////*/

contract MockEAS is IEAS {
    bytes32 public lastSchemaUID;
    address public lastRecipient;
    bytes public lastData;
    bool public lastRevocable;
    uint256 public attestCount;
    bool public shouldRevert;
    bytes32 public nextUID;

    function setNextUID(bytes32 uid) external {
        nextUID = uid;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function attest(AttestationRequest calldata request) external payable override returns (bytes32) {
        if (shouldRevert) revert("EAS_REVERTED");
        lastSchemaUID = request.schema;
        lastRecipient = request.data.recipient;
        lastData = request.data.data;
        lastRevocable = request.data.revocable;
        attestCount++;
        if (nextUID != bytes32(0)) return nextUID;
        return keccak256(abi.encode(attestCount));
    }
}

/// @dev A combined mock that acts as both ACP contract and job reader
contract ACPWithJobs {
    mapping(uint256 => IAgenticCommerceReader.Job) public jobs;
    IACPHook public hook;
    bool public getJobShouldRevert;

    function setHook(address hook_) external {
        hook = IACPHook(hook_);
    }

    function setJob(
        uint256 id,
        address client_,
        address provider_,
        address evaluator_,
        uint256 budget_
    ) external {
        jobs[id] = IAgenticCommerceReader.Job({
            id: id,
            client: client_,
            provider: provider_,
            evaluator: evaluator_,
            hook: address(hook),
            description: "",
            budget: budget_,
            expiredAt: block.timestamp + 1 days,
            status: 0
        });
    }

    function setGetJobShouldRevert(bool val) external {
        getJobShouldRevert = val;
    }

    function getJob(uint256 jobId) external view returns (IAgenticCommerceReader.Job memory) {
        if (getJobShouldRevert) revert("JOB_NOT_FOUND");
        return jobs[jobId];
    }

    function callComplete(uint256 jobId, bytes32 reason) external {
        bytes memory data = abi.encode(reason, bytes(""));
        hook.afterAction(jobId, bytes4(keccak256("complete(uint256,bytes32,bytes)")), data);
    }

    function callReject(uint256 jobId, bytes32 reason) external {
        bytes memory data = abi.encode(reason, bytes(""));
        hook.afterAction(jobId, bytes4(keccak256("reject(uint256,bytes32,bytes)")), data);
    }
}

/*//////////////////////////////////////////////////////////////
                        UNIT TESTS
//////////////////////////////////////////////////////////////*/

contract AttestationHookUnitTest is Test {
    AttestationHook public hook;
    MockEAS public mockEAS;
    ACPWithJobs public acp;

    address public owner = makeAddr("owner");
    address public client = makeAddr("client");
    address public provider = makeAddr("provider");
    address public evaluator = makeAddr("evaluator");

    bytes32 public constant SCHEMA_UID = keccak256("test-schema");

    function setUp() public {
        mockEAS = new MockEAS();
        acp = new ACPWithJobs();

        vm.prank(owner);
        hook = new AttestationHook(
            address(acp),
            address(mockEAS),
            SCHEMA_UID
        );
        acp.setHook(address(hook));
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function test_constructor() public view {
        assertEq(address(hook.eas()), address(mockEAS));
        assertEq(hook.schemaUID(), SCHEMA_UID);
        assertEq(hook.owner(), owner);
        assertEq(hook.totalAttestations(), 0);
    }

    function test_constructor_revertZeroEAS() public {
        vm.expectRevert(AttestationHook.AttestationHook__ZeroAddress.selector);
        new AttestationHook(address(acp), address(0), SCHEMA_UID);
    }

    function test_constructor_revertZeroSchema() public {
        vm.expectRevert(AttestationHook.AttestationHook__ZeroSchemaUID.selector);
        new AttestationHook(address(acp), address(mockEAS), bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN: setSchemaUID
    //////////////////////////////////////////////////////////////*/

    function test_setSchemaUID() public {
        bytes32 newSchema = keccak256("new-schema");
        vm.prank(owner);
        hook.setSchemaUID(newSchema);
        assertEq(hook.schemaUID(), newSchema);
    }

    function test_setSchemaUID_revertNotOwner() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert(AttestationHook.AttestationHook__OnlyOwner.selector);
        hook.setSchemaUID(keccak256("new"));
    }

    function test_setSchemaUID_revertZero() public {
        vm.prank(owner);
        vm.expectRevert(AttestationHook.AttestationHook__ZeroSchemaUID.selector);
        hook.setSchemaUID(bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN: setEAS
    //////////////////////////////////////////////////////////////*/

    function test_setEAS() public {
        address newEAS = makeAddr("newEAS");
        vm.prank(owner);
        hook.setEAS(newEAS);
        assertEq(address(hook.eas()), newEAS);
    }

    function test_setEAS_revertNotOwner() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert(AttestationHook.AttestationHook__OnlyOwner.selector);
        hook.setEAS(makeAddr("newEAS"));
    }

    function test_setEAS_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(AttestationHook.AttestationHook__ZeroAddress.selector);
        hook.setEAS(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    ADMIN: Two-Step Ownership
    //////////////////////////////////////////////////////////////*/

    function test_transferOwnership_twoStep() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        hook.transferOwnership(newOwner);
        assertEq(hook.owner(), owner); // Still old owner
        assertEq(hook.pendingOwner(), newOwner);

        vm.prank(newOwner);
        hook.acceptOwnership();
        assertEq(hook.owner(), newOwner);
        assertEq(hook.pendingOwner(), address(0));
    }

    function test_transferOwnership_revertNotOwner() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert(AttestationHook.AttestationHook__OnlyOwner.selector);
        hook.transferOwnership(makeAddr("newOwner"));
    }

    function test_transferOwnership_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(AttestationHook.AttestationHook__ZeroAddress.selector);
        hook.transferOwnership(address(0));
    }

    function test_acceptOwnership_revertNotPending() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        hook.transferOwnership(newOwner);

        vm.prank(makeAddr("random"));
        vm.expectRevert(AttestationHook.AttestationHook__OnlyPendingOwner.selector);
        hook.acceptOwnership();
    }

    /*//////////////////////////////////////////////////////////////
                    ERC-165
    //////////////////////////////////////////////////////////////*/

    function test_supportsInterface_IACPHook() public view {
        assertTrue(hook.supportsInterface(type(IACPHook).interfaceId));
    }

    function test_supportsInterface_ERC165() public view {
        assertTrue(hook.supportsInterface(0x01ffc9a7));
    }

    function test_supportsInterface_random() public view {
        assertFalse(hook.supportsInterface(0xdeadbeef));
    }

    function test_getAttestation_default() public view {
        assertEq(hook.getAttestation(999), bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_setSchemaUID(bytes32 newSchema) public {
        vm.assume(newSchema != bytes32(0));
        vm.prank(owner);
        hook.setSchemaUID(newSchema);
        assertEq(hook.schemaUID(), newSchema);
    }

    function testFuzz_setSchemaUID_revertNotOwner(address caller_, bytes32 newSchema) public {
        vm.assume(caller_ != owner);
        vm.assume(newSchema != bytes32(0));
        vm.prank(caller_);
        vm.expectRevert(AttestationHook.AttestationHook__OnlyOwner.selector);
        hook.setSchemaUID(newSchema);
    }

    function testFuzz_setEAS(address newEAS) public {
        vm.assume(newEAS != address(0));
        vm.prank(owner);
        hook.setEAS(newEAS);
        assertEq(address(hook.eas()), newEAS);
    }

    function testFuzz_setEAS_revertNotOwner(address caller_, address newEAS) public {
        vm.assume(caller_ != owner);
        vm.assume(newEAS != address(0));
        vm.prank(caller_);
        vm.expectRevert(AttestationHook.AttestationHook__OnlyOwner.selector);
        hook.setEAS(newEAS);
    }

    function testFuzz_transferOwnership_twoStep(address newOwner) public {
        vm.assume(newOwner != address(0));
        vm.prank(owner);
        hook.transferOwnership(newOwner);
        assertEq(hook.pendingOwner(), newOwner);
        assertEq(hook.owner(), owner); // Not changed yet

        vm.prank(newOwner);
        hook.acceptOwnership();
        assertEq(hook.owner(), newOwner);
    }

    function testFuzz_supportsInterface(bytes4 interfaceId) public view {
        bool expected = (interfaceId == type(IACPHook).interfaceId) || (interfaceId == 0x01ffc9a7);
        assertEq(hook.supportsInterface(interfaceId), expected);
    }

    function testFuzz_getAttestation_nonexistent(uint256 jobId) public view {
        assertEq(hook.getAttestation(jobId), bytes32(0));
    }
}

/*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
//////////////////////////////////////////////////////////////*/

contract AttestationHookIntegrationTest is Test {
    AttestationHook public hook;
    MockEAS public mockEAS;
    ACPWithJobs public acp;

    address public owner = makeAddr("owner");
    address public client = makeAddr("client");
    address public provider = makeAddr("provider");
    address public evaluator = makeAddr("evaluator");

    bytes32 public constant SCHEMA_UID = keccak256("test-schema");
    bytes32 public constant REASON = keccak256("quality-ok");

    function setUp() public {
        mockEAS = new MockEAS();
        acp = new ACPWithJobs();

        vm.prank(owner);
        hook = new AttestationHook(
            address(acp),
            address(mockEAS),
            SCHEMA_UID
        );

        acp.setHook(address(hook));
        acp.setJob(1, client, provider, evaluator, 500 ether);
        acp.setJob(2, client, provider, evaluator, 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    COMPLETE FLOW
    //////////////////////////////////////////////////////////////*/

    function test_complete_writesAttestation() public {
        bytes32 expectedUID = keccak256(abi.encode(uint256(1)));
        mockEAS.setNextUID(expectedUID);

        vm.expectEmit(true, true, true, true);
        emit AttestationHook.AttestationCreated(1, expectedUID, provider, true);

        acp.callComplete(1, REASON);

        assertEq(hook.getAttestation(1), expectedUID);
        assertEq(hook.totalAttestations(), 1);
        assertEq(mockEAS.attestCount(), 1);
        assertEq(mockEAS.lastRecipient(), provider);
        assertEq(mockEAS.lastSchemaUID(), SCHEMA_UID);
        assertFalse(mockEAS.lastRevocable());
    }

    function test_complete_encodesCorrectData() public {
        acp.callComplete(1, REASON);

        bytes memory expectedData = abi.encode(
            uint256(1), client, provider, evaluator, 500 ether, REASON, true
        );
        assertEq(mockEAS.lastData(), expectedData);
    }

    /*//////////////////////////////////////////////////////////////
                    REJECT FLOW
    //////////////////////////////////////////////////////////////*/

    function test_reject_writesAttestation() public {
        bytes32 expectedUID = keccak256(abi.encode(uint256(1)));
        mockEAS.setNextUID(expectedUID);

        vm.expectEmit(true, true, true, true);
        emit AttestationHook.AttestationCreated(1, expectedUID, provider, false);

        acp.callReject(1, REASON);

        assertEq(hook.getAttestation(1), expectedUID);
        assertEq(hook.totalAttestations(), 1);
    }

    function test_reject_encodesCorrectData() public {
        acp.callReject(1, REASON);

        bytes memory expectedData = abi.encode(
            uint256(1), client, provider, evaluator, 500 ether, REASON, false
        );
        assertEq(mockEAS.lastData(), expectedData);
    }

    /*//////////////////////////////////////////////////////////////
                    IDEMPOTENCY (ATH-02 FIX)
    //////////////////////////////////////////////////////////////*/

    function test_complete_idempotent_secondCallSkipped() public {
        bytes32 firstUID = keccak256("first");
        mockEAS.setNextUID(firstUID);

        acp.callComplete(1, REASON);
        assertEq(hook.getAttestation(1), firstUID);
        assertEq(hook.totalAttestations(), 1);

        // Second call should be silently skipped
        mockEAS.setNextUID(keccak256("second"));
        acp.callComplete(1, REASON);
        assertEq(hook.getAttestation(1), firstUID); // Still first UID
        assertEq(hook.totalAttestations(), 1); // Not incremented
        assertEq(mockEAS.attestCount(), 1); // EAS not called again
    }

    function test_reject_afterComplete_skipped() public {
        bytes32 firstUID = keccak256("first");
        mockEAS.setNextUID(firstUID);

        acp.callComplete(1, REASON);
        assertEq(hook.totalAttestations(), 1);

        // Reject after complete should be skipped
        acp.callReject(1, REASON);
        assertEq(hook.totalAttestations(), 1); // Not incremented
    }

    /*//////////////////////////////////////////////////////////////
                    EAS FAILURE HANDLING
    //////////////////////////////////////////////////////////////*/

    function test_complete_easReverts_emitsFailedEvent() public {
        mockEAS.setShouldRevert(true);

        vm.expectEmit(true, false, false, false);
        emit AttestationHook.AttestationFailed(1, bytes(""));

        acp.callComplete(1, REASON);

        // Should not revert, attestation should be empty (sentinel reset)
        assertEq(hook.getAttestation(1), bytes32(0));
        assertEq(hook.totalAttestations(), 0);
    }

    function test_complete_easReverts_canRetry() public {
        // First attempt: EAS fails
        mockEAS.setShouldRevert(true);
        acp.callComplete(1, REASON);
        assertEq(hook.getAttestation(1), bytes32(0));

        // Second attempt: EAS works (sentinel was reset, so not blocked by idempotency)
        mockEAS.setShouldRevert(false);
        bytes32 uid = keccak256("retry-success");
        mockEAS.setNextUID(uid);
        acp.callComplete(1, REASON);
        assertEq(hook.getAttestation(1), uid);
        assertEq(hook.totalAttestations(), 1);
    }

    function test_reject_easReverts_doesNotRevert() public {
        mockEAS.setShouldRevert(true);
        acp.callReject(1, REASON);
        assertEq(hook.totalAttestations(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    JOB READ FAILURE
    //////////////////////////////////////////////////////////////*/

    function test_complete_jobReadFails_emitsFailedEvent() public {
        acp.setGetJobShouldRevert(true);

        vm.expectEmit(true, false, false, false);
        emit AttestationHook.AttestationFailed(1, bytes(""));

        acp.callComplete(1, REASON);

        assertEq(hook.getAttestation(1), bytes32(0));
        assertEq(hook.totalAttestations(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE JOBS
    //////////////////////////////////////////////////////////////*/

    function test_multipleJobs_incrementCounter() public {
        acp.callComplete(1, REASON);
        acp.callComplete(2, REASON);
        assertEq(hook.totalAttestations(), 2);
    }

    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function test_afterAction_revertNotACP() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert();
        hook.afterAction(1, bytes4(keccak256("complete(uint256,bytes32,bytes)")), bytes(""));
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function testFuzz_complete_anyJob(
        uint256 jobId,
        address client_,
        address provider_,
        address evaluator_,
        uint256 budget,
        bytes32 reason
    ) public {
        vm.assume(provider_ != address(0));
        acp.setJob(jobId, client_, provider_, evaluator_, budget);

        acp.callComplete(jobId, reason);

        assertEq(hook.totalAttestations(), 1);
        assertEq(mockEAS.lastRecipient(), provider_);
        assertFalse(mockEAS.lastRevocable());

        bytes memory expectedData = abi.encode(
            jobId, client_, provider_, evaluator_, budget, reason, true
        );
        assertEq(mockEAS.lastData(), expectedData);
    }

    function testFuzz_reject_anyJob(
        uint256 jobId,
        address client_,
        address provider_,
        address evaluator_,
        uint256 budget,
        bytes32 reason
    ) public {
        vm.assume(provider_ != address(0));
        acp.setJob(jobId, client_, provider_, evaluator_, budget);

        acp.callReject(jobId, reason);

        assertEq(hook.totalAttestations(), 1);

        bytes memory expectedData = abi.encode(
            jobId, client_, provider_, evaluator_, budget, reason, false
        );
        assertEq(mockEAS.lastData(), expectedData);
    }

    function testFuzz_easFailure_neverReverts(
        uint256 jobId,
        bytes32 reason
    ) public {
        acp.setJob(jobId, client, provider, evaluator, 1 ether);
        mockEAS.setShouldRevert(true);

        // Should never revert regardless of inputs
        acp.callComplete(jobId, reason);
        acp.callReject(jobId, reason);

        assertEq(hook.totalAttestations(), 0);
    }

    function testFuzz_idempotent_secondCallNoop(
        uint256 jobId,
        bytes32 reason1,
        bytes32 reason2
    ) public {
        acp.setJob(jobId, client, provider, evaluator, 1 ether);

        acp.callComplete(jobId, reason1);
        uint256 countAfterFirst = hook.totalAttestations();

        acp.callComplete(jobId, reason2);
        assertEq(hook.totalAttestations(), countAfterFirst); // Not incremented
    }
}
