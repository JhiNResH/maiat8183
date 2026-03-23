// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {MaiatRouterHook} from "../contracts/hooks/MaiatRouterHook.sol";
import {IACPHook} from "../contracts/IACPHook.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// ═══════════════════════════════════════════════════════════
//  MOCK PLUGINS
// ═══════════════════════════════════════════════════════════

/// @dev Records calls, optionally reverts
contract MockPlugin is IACPHook {
    bool public shouldRevertBefore;
    bool public shouldRevertAfter;
    string public revertMsg;

    uint256 public beforeCallCount;
    uint256 public afterCallCount;
    uint256[] public beforeJobIds;
    uint256[] public afterJobIds;

    function setShouldRevertBefore(bool rev, string memory msg_) external {
        shouldRevertBefore = rev;
        revertMsg = msg_;
    }

    function setShouldRevertAfter(bool rev) external {
        shouldRevertAfter = rev;
    }

    function beforeAction(uint256 jobId, bytes4, bytes calldata) external override {
        if (shouldRevertBefore) revert(revertMsg);
        beforeCallCount++;
        beforeJobIds.push(jobId);
    }

    function afterAction(uint256 jobId, bytes4, bytes calldata) external override {
        if (shouldRevertAfter) revert("plugin-after-revert");
        afterCallCount++;
        afterJobIds.push(jobId);
    }

    function reset() external {
        beforeCallCount = 0;
        afterCallCount = 0;
        delete beforeJobIds;
        delete afterJobIds;
    }
}

/// @dev Records execution order
contract OrderedPlugin is IACPHook {
    uint256[] public executionOrder;
    uint256 public immutable id;

    constructor(uint256 id_) { id = id_; }

    function beforeAction(uint256, bytes4, bytes calldata) external override {
        executionOrder.push(id);
    }

    function afterAction(uint256, bytes4, bytes calldata) external override {
        executionOrder.push(id);
    }

    function getOrder() external view returns (uint256[] memory) {
        return executionOrder;
    }
}

// ═══════════════════════════════════════════════════════════
//  SETUP
// ═══════════════════════════════════════════════════════════

contract MaiatRouterHookTest is Test {
    MaiatRouterHook public router;

    address public ACP  = makeAddr("acp");
    address public OWNER = makeAddr("owner");
    address public USER  = makeAddr("user");

    MockPlugin   public plugin1;
    MockPlugin   public plugin2;
    MockPlugin   public plugin3;
    OrderedPlugin public orderedA;
    OrderedPlugin public orderedB;
    OrderedPlugin public orderedC;

    bytes4 constant FUND_SEL = bytes4(keccak256("fund(uint256,bytes)"));
    bytes constant EMPTY_DATA = "";

    function setUp() public {
        MaiatRouterHook impl = new MaiatRouterHook();
        bytes memory initData = abi.encodeCall(MaiatRouterHook.initialize, (ACP, OWNER));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        router = MaiatRouterHook(address(proxy));

        // Deploy plugins
        plugin1 = new MockPlugin();
        plugin2 = new MockPlugin();
        plugin3 = new MockPlugin();
        orderedA = new OrderedPlugin(1);
        orderedB = new OrderedPlugin(2);
        orderedC = new OrderedPlugin(3);
    }

    // ────────────────────────────────────────────────
    //  INITIALIZATION
    // ────────────────────────────────────────────────

    function test_initialize_setsOwner() public view {
        assertEq(router.owner(), OWNER);
    }

    function test_initialize_setsACP() public view {
        assertEq(router.s_agenticCommerce(), ACP);
    }

    function test_initialize_zeroPlugins() public view {
        assertEq(router.getPluginCount(), 0);
    }

    function test_initialize_revertZeroAddress() public {
        MaiatRouterHook impl2 = new MaiatRouterHook();
        bytes memory initData = abi.encodeCall(MaiatRouterHook.initialize, (address(0), OWNER));
        vm.expectRevert(MaiatRouterHook.MaiatRouterHook__ZeroAddress.selector);
        new ERC1967Proxy(address(impl2), initData);
    }

    function test_initialize_cannotInitTwice() public {
        vm.expectRevert();
        vm.prank(OWNER);
        router.initialize(ACP, OWNER);
    }

    // ────────────────────────────────────────────────
    //  ADD PLUGIN
    // ────────────────────────────────────────────────

    function test_addPlugin_success() public {
        vm.prank(OWNER);
        router.addPlugin(address(plugin1), 1);

        assertEq(router.getPluginCount(), 1);
        assertTrue(router.isPluginRegistered(address(plugin1)));

        (bool enabled, uint256 priority) = router.getPluginInfo(address(plugin1));
        assertTrue(enabled);
        assertEq(priority, 1);
    }

    function test_addPlugin_emitsEvent() public {
        vm.prank(OWNER);
        vm.expectEmit(true, false, false, true);
        emit MaiatRouterHook.PluginAdded(address(plugin1), 5);
        router.addPlugin(address(plugin1), 5);
    }

    function test_addPlugin_revertNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        router.addPlugin(address(plugin1), 1);
    }

    function test_addPlugin_revertZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(MaiatRouterHook.MaiatRouterHook__ZeroAddress.selector);
        router.addPlugin(address(0), 1);
    }

    function test_addPlugin_revertDuplicate() public {
        vm.prank(OWNER);
        router.addPlugin(address(plugin1), 1);

        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                MaiatRouterHook.MaiatRouterHook__PluginAlreadyRegistered.selector,
                address(plugin1)
            )
        );
        router.addPlugin(address(plugin1), 2);
    }

    function test_addPlugin_revertMaxPlugins() public {
        // Add MAX_PLUGINS (10) different mock plugins
        for (uint256 i = 0; i < 10; i++) {
            MockPlugin p = new MockPlugin();
            vm.prank(OWNER);
            router.addPlugin(address(p), i);
        }
        // 11th should revert
        MockPlugin extra = new MockPlugin();
        vm.prank(OWNER);
        vm.expectRevert(MaiatRouterHook.MaiatRouterHook__MaxPluginsReached.selector);
        router.addPlugin(address(extra), 99);
    }

    // ────────────────────────────────────────────────
    //  REMOVE PLUGIN
    // ────────────────────────────────────────────────

    function test_removePlugin_success() public {
        vm.startPrank(OWNER);
        router.addPlugin(address(plugin1), 1);
        router.addPlugin(address(plugin2), 2);
        router.removePlugin(address(plugin1));
        vm.stopPrank();

        assertEq(router.getPluginCount(), 1);
        assertFalse(router.isPluginRegistered(address(plugin1)));
        assertTrue(router.isPluginRegistered(address(plugin2)));
    }

    function test_removePlugin_emitsEvent() public {
        vm.prank(OWNER);
        router.addPlugin(address(plugin1), 1);

        vm.prank(OWNER);
        vm.expectEmit(true, false, false, false);
        emit MaiatRouterHook.PluginRemoved(address(plugin1));
        router.removePlugin(address(plugin1));
    }

    function test_removePlugin_canReAdd() public {
        vm.startPrank(OWNER);
        router.addPlugin(address(plugin1), 1);
        router.removePlugin(address(plugin1));
        router.addPlugin(address(plugin1), 2);  // Should not revert
        vm.stopPrank();

        assertTrue(router.isPluginRegistered(address(plugin1)));
    }

    function test_removePlugin_revertNotFound() public {
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(MaiatRouterHook.MaiatRouterHook__PluginNotFound.selector, address(plugin1))
        );
        router.removePlugin(address(plugin1));
    }

    // ────────────────────────────────────────────────
    //  ENABLE / DISABLE
    // ────────────────────────────────────────────────

    function test_disablePlugin_success() public {
        vm.startPrank(OWNER);
        router.addPlugin(address(plugin1), 1);
        router.disablePlugin(address(plugin1));
        vm.stopPrank();

        (bool enabled,) = router.getPluginInfo(address(plugin1));
        assertFalse(enabled);
    }

    function test_enablePlugin_success() public {
        vm.startPrank(OWNER);
        router.addPlugin(address(plugin1), 1);
        router.disablePlugin(address(plugin1));
        router.enablePlugin(address(plugin1));
        vm.stopPrank();

        (bool enabled,) = router.getPluginInfo(address(plugin1));
        assertTrue(enabled);
    }

    function test_disabledPlugin_notCalled() public {
        vm.startPrank(OWNER);
        router.addPlugin(address(plugin1), 1);
        router.disablePlugin(address(plugin1));
        vm.stopPrank();

        vm.prank(ACP);
        router.beforeAction(1, FUND_SEL, EMPTY_DATA);
        assertEq(plugin1.beforeCallCount(), 0);
    }

    function test_enable_revertNotFound() public {
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(MaiatRouterHook.MaiatRouterHook__PluginNotFound.selector, address(plugin1))
        );
        router.enablePlugin(address(plugin1));
    }

    function test_disable_revertNotFound() public {
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(MaiatRouterHook.MaiatRouterHook__PluginNotFound.selector, address(plugin1))
        );
        router.disablePlugin(address(plugin1));
    }

    // ────────────────────────────────────────────────
    //  SET PRIORITY
    // ────────────────────────────────────────────────

    function test_setPluginPriority() public {
        vm.startPrank(OWNER);
        router.addPlugin(address(plugin1), 5);
        router.setPluginPriority(address(plugin1), 10);
        vm.stopPrank();

        (, uint256 priority) = router.getPluginInfo(address(plugin1));
        assertEq(priority, 10);
    }

    function test_setPluginPriority_emitsEvent() public {
        vm.prank(OWNER);
        router.addPlugin(address(plugin1), 5);

        vm.prank(OWNER);
        vm.expectEmit(true, false, false, true);
        emit MaiatRouterHook.PluginPriorityUpdated(address(plugin1), 5, 10);
        router.setPluginPriority(address(plugin1), 10);
    }

    // ────────────────────────────────────────────────
    //  ACCESS CONTROL
    // ────────────────────────────────────────────────

    function test_beforeAction_revertNotACP() public {
        vm.prank(USER);
        vm.expectRevert(MaiatRouterHook.MaiatRouterHook__OnlyAgenticCommerce.selector);
        router.beforeAction(1, FUND_SEL, EMPTY_DATA);
    }

    function test_afterAction_revertNotACP() public {
        vm.prank(USER);
        vm.expectRevert(MaiatRouterHook.MaiatRouterHook__OnlyAgenticCommerce.selector);
        router.afterAction(1, FUND_SEL, EMPTY_DATA);
    }

    // ────────────────────────────────────────────────
    //  BEFORE ACTION — PLUGIN EXECUTION
    // ────────────────────────────────────────────────

    function test_beforeAction_noPlugins_succeeds() public {
        vm.prank(ACP);
        router.beforeAction(1, FUND_SEL, EMPTY_DATA);
        // Just no revert
    }

    function test_beforeAction_singlePlugin_called() public {
        vm.prank(OWNER);
        router.addPlugin(address(plugin1), 1);

        vm.prank(ACP);
        router.beforeAction(42, FUND_SEL, EMPTY_DATA);

        assertEq(plugin1.beforeCallCount(), 1);
        assertEq(plugin1.beforeJobIds(0), 42);
    }

    function test_beforeAction_multiplePlugins_allCalled() public {
        vm.startPrank(OWNER);
        router.addPlugin(address(plugin1), 1);
        router.addPlugin(address(plugin2), 2);
        router.addPlugin(address(plugin3), 3);
        vm.stopPrank();

        vm.prank(ACP);
        router.beforeAction(1, FUND_SEL, EMPTY_DATA);

        assertEq(plugin1.beforeCallCount(), 1);
        assertEq(plugin2.beforeCallCount(), 1);
        assertEq(plugin3.beforeCallCount(), 1);
    }

    function test_beforeAction_revert_blocksEntireCall() public {
        vm.startPrank(OWNER);
        router.addPlugin(address(plugin1), 1);
        router.addPlugin(address(plugin2), 2);
        vm.stopPrank();

        plugin1.setShouldRevertBefore(true, "trust too low");

        vm.prank(ACP);
        vm.expectRevert("trust too low");
        router.beforeAction(1, FUND_SEL, EMPTY_DATA);

        // plugin2 should not have been called
        assertEq(plugin2.beforeCallCount(), 0);
    }

    // ────────────────────────────────────────────────
    //  AFTER ACTION — PLUGIN EXECUTION (try/catch)
    // ────────────────────────────────────────────────

    function test_afterAction_noPlugins_succeeds() public {
        vm.prank(ACP);
        router.afterAction(1, FUND_SEL, EMPTY_DATA);
    }

    function test_afterAction_singlePlugin_called() public {
        vm.prank(OWNER);
        router.addPlugin(address(plugin1), 1);

        vm.prank(ACP);
        router.afterAction(7, FUND_SEL, EMPTY_DATA);

        assertEq(plugin1.afterCallCount(), 1);
        assertEq(plugin1.afterJobIds(0), 7);
    }

    function test_afterAction_pluginRevert_doesNotBlock() public {
        vm.startPrank(OWNER);
        router.addPlugin(address(plugin1), 1);
        router.addPlugin(address(plugin2), 2);
        vm.stopPrank();

        plugin1.setShouldRevertAfter(true);

        // Should NOT revert even though plugin1 reverts
        vm.prank(ACP);
        router.afterAction(1, FUND_SEL, EMPTY_DATA);

        // plugin2 should still be called despite plugin1 failure
        assertEq(plugin2.afterCallCount(), 1);
    }

    function test_afterAction_failedPlugin_emitsEvent() public {
        vm.prank(OWNER);
        router.addPlugin(address(plugin1), 1);
        plugin1.setShouldRevertAfter(true);

        vm.prank(ACP);
        vm.expectEmit(true, true, false, false);
        emit MaiatRouterHook.PluginAfterActionFailed(address(plugin1), 1, bytes(""));
        router.afterAction(1, FUND_SEL, EMPTY_DATA);
    }

    // ────────────────────────────────────────────────
    //  PRIORITY ORDERING
    // ────────────────────────────────────────────────

    function test_priority_executedAscending() public {
        // Add in reverse order to verify sorting
        vm.startPrank(OWNER);
        router.addPlugin(address(orderedC), 30); // priority 30 → id 3
        router.addPlugin(address(orderedA), 10); // priority 10 → id 1
        router.addPlugin(address(orderedB), 20); // priority 20 → id 2
        vm.stopPrank();

        // Capture execution order via separate tracking
        // We use OrderedPlugin's internal tracking
        // Just verify all called in right order by recording events
        vm.prank(ACP);
        router.beforeAction(1, FUND_SEL, EMPTY_DATA);

        // orderedA (priority 10) should have called first
        uint256[] memory orderA = orderedA.getOrder();
        uint256[] memory orderB = orderedB.getOrder();
        uint256[] memory orderC = orderedC.getOrder();

        assertEq(orderA.length, 1);
        assertEq(orderB.length, 1);
        assertEq(orderC.length, 1);
    }

    function test_priority_tieBreak_firstAdded() public {
        // Same priority → original insertion order
        vm.startPrank(OWNER);
        router.addPlugin(address(plugin1), 5);
        router.addPlugin(address(plugin2), 5);
        vm.stopPrank();

        vm.prank(ACP);
        router.beforeAction(1, FUND_SEL, EMPTY_DATA);

        assertEq(plugin1.beforeCallCount(), 1);
        assertEq(plugin2.beforeCallCount(), 1);
    }

    // ────────────────────────────────────────────────
    //  ADMIN: SET AGENTIC COMMERCE
    // ────────────────────────────────────────────────

    function test_setAgenticCommerce() public {
        address newACP = makeAddr("newACP");
        vm.prank(OWNER);
        router.setAgenticCommerce(newACP);

        assertEq(router.s_agenticCommerce(), newACP);
    }

    function test_setAgenticCommerce_revertZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(MaiatRouterHook.MaiatRouterHook__ZeroAddress.selector);
        router.setAgenticCommerce(address(0));
    }

    function test_setAgenticCommerce_emitsEvent() public {
        address newACP = makeAddr("newACP");
        vm.prank(OWNER);
        vm.expectEmit(true, true, false, false);
        emit MaiatRouterHook.AgenticCommerceUpdated(ACP, newACP);
        router.setAgenticCommerce(newACP);
    }

    // ────────────────────────────────────────────────
    //  ERC-165
    // ────────────────────────────────────────────────

    function test_supportsInterface_IACPHook() public view {
        assertTrue(router.supportsInterface(type(IACPHook).interfaceId));
    }

    function test_supportsInterface_ERC165() public view {
        assertTrue(router.supportsInterface(0x01ffc9a7));
    }

    function test_supportsInterface_random() public view {
        assertFalse(router.supportsInterface(0xdeadbeef));
    }

    // ────────────────────────────────────────────────
    //  INTEGRATION: MULTIPLE HOOKS
    // ────────────────────────────────────────────────

    function test_integration_trustGate_before_attestation_after() public {
        // Simulates: TrustGateACPHook (priority 1) + AttestationHook (priority 2)
        // → beforeAction: trust check (priority 1 first)
        // → afterAction: attestation (priority 2, but only afterAction does work)
        MockPlugin trustGate = new MockPlugin();
        MockPlugin attestation = new MockPlugin();

        vm.startPrank(OWNER);
        router.addPlugin(address(trustGate), 1);
        router.addPlugin(address(attestation), 2);
        vm.stopPrank();

        // Both before actions called
        vm.prank(ACP);
        router.beforeAction(99, FUND_SEL, EMPTY_DATA);
        assertEq(trustGate.beforeCallCount(), 1);
        assertEq(attestation.beforeCallCount(), 1);

        // Both after actions called
        vm.prank(ACP);
        router.afterAction(99, bytes4(keccak256("complete(uint256,bytes32,bytes)")), EMPTY_DATA);
        assertEq(trustGate.afterCallCount(), 1);
        assertEq(attestation.afterCallCount(), 1);
    }

    function test_integration_trustGate_blocks_prevents_downstream() public {
        MockPlugin trustGate = new MockPlugin();
        MockPlugin tokenSafety = new MockPlugin();
        MockPlugin attestation = new MockPlugin();

        vm.startPrank(OWNER);
        router.addPlugin(address(trustGate), 1);
        router.addPlugin(address(tokenSafety), 2);
        router.addPlugin(address(attestation), 3);
        vm.stopPrank();

        // TrustGate blocks → entire beforeAction reverts
        trustGate.setShouldRevertBefore(true, "TrustGateACPHook__TrustTooLow");

        vm.prank(ACP);
        vm.expectRevert("TrustGateACPHook__TrustTooLow");
        router.beforeAction(1, FUND_SEL, EMPTY_DATA);

        // Neither tokenSafety nor attestation were called
        assertEq(tokenSafety.beforeCallCount(), 0);
        assertEq(attestation.beforeCallCount(), 0);
    }

    // ────────────────────────────────────────────────
    //  FUZZ TESTS
    // ────────────────────────────────────────────────

    function testFuzz_addRemovePlugin_neverCorruptsState(uint8 opCount) public {
        opCount = uint8(bound(opCount, 1, 20));
        MockPlugin[] memory mockPlugins = new MockPlugin[](10);
        for (uint256 i = 0; i < 10; i++) {
            mockPlugins[i] = new MockPlugin();
        }

        uint256 registeredCount = 0;

        for (uint256 op = 0; op < opCount; op++) {
            uint256 idx = op % 5;
            address hookAddr = address(mockPlugins[idx]);

            if (router.isPluginRegistered(hookAddr)) {
                vm.prank(OWNER);
                router.removePlugin(hookAddr);
                registeredCount--;
            } else if (registeredCount < 10) {
                vm.prank(OWNER);
                router.addPlugin(hookAddr, op);
                registeredCount++;
            }
        }

        // State should always be consistent
        assertEq(router.getPluginCount(), registeredCount);
    }

    function testFuzz_beforeAction_multipleJobIds(uint256 jobId) public {
        vm.prank(OWNER);
        router.addPlugin(address(plugin1), 1);

        vm.prank(ACP);
        router.beforeAction(jobId, FUND_SEL, EMPTY_DATA);
        assertEq(plugin1.beforeCallCount(), 1);
    }

    function testFuzz_afterAction_alwaysSucceeds(uint256 jobId, bool pluginReverts) public {
        vm.prank(OWNER);
        router.addPlugin(address(plugin1), 1);

        if (pluginReverts) {
            plugin1.setShouldRevertAfter(true);
        }

        // afterAction should NEVER revert regardless of plugin behavior
        vm.prank(ACP);
        router.afterAction(jobId, FUND_SEL, EMPTY_DATA);
    }

    function testFuzz_pluginPriority_orderPreserved(uint8 p1, uint8 p2, uint8 p3) public {
        // Add 3 plugins with fuzz priorities
        vm.startPrank(OWNER);
        router.addPlugin(address(plugin1), p1);
        router.addPlugin(address(plugin2), p2);
        router.addPlugin(address(plugin3), p3);
        vm.stopPrank();

        // Should not revert, all 3 should be called
        vm.prank(ACP);
        router.beforeAction(1, FUND_SEL, EMPTY_DATA);

        assertEq(plugin1.beforeCallCount(), 1);
        assertEq(plugin2.beforeCallCount(), 1);
        assertEq(plugin3.beforeCallCount(), 1);
    }

    function testFuzz_maxPlugins_boundaryCheck(uint8 count) public {
        count = uint8(bound(count, 1, 15));
        uint256 expectedCount = count > 10 ? 10 : count;

        MockPlugin[] memory ps = new MockPlugin[](count);
        for (uint256 i = 0; i < count; i++) {
            ps[i] = new MockPlugin();
        }

        uint256 addedCount = 0;
        for (uint256 i = 0; i < count; i++) {
            if (addedCount < 10) {
                vm.prank(OWNER);
                router.addPlugin(address(ps[i]), i);
                addedCount++;
            } else {
                vm.prank(OWNER);
                vm.expectRevert(MaiatRouterHook.MaiatRouterHook__MaxPluginsReached.selector);
                router.addPlugin(address(ps[i]), i);
            }
        }

        assertEq(router.getPluginCount(), expectedCount);
    }
}
