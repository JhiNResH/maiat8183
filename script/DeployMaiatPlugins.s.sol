// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TokenSafetyHook} from "../contracts/hooks/TokenSafetyHook.sol";
import {MaiatRouterHook} from "../contracts/hooks/MaiatRouterHook.sol";
import {TrustGateACPHook} from "../contracts/hooks/TrustGateACPHook.sol";
import {AttestationHook} from "../contracts/hooks/AttestationHook.sol";

/**
 * @title DeployMaiatPlugins
 * @notice Deploys TokenSafetyHook and MaiatRouterHook, then configures the Router
 *         with TrustGate (priority 1), TokenSafety (priority 2), Attestation (priority 3).
 *
 * Usage:
 *   forge script script/DeployMaiatPlugins.s.sol \
 *     --rpc-url $BASE_RPC_URL \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 *
 * Required env vars:
 *   DEPLOYER_PK          - Deployer private key
 *   ACP_CONTRACT         - AgenticCommerceHooked contract address
 *   TRUST_ORACLE         - ITrustOracle address (Maiat Oracle)
 *   TOKEN_SAFETY_ORACLE  - ITokenSafetyOracle address
 *   EAS_CONTRACT         - EAS contract (Base: 0x4200000000000000000000000000000000000021)
 *   EAS_SCHEMA_UID       - Pre-registered EAS schema UID
 *   OWNER                - Contract owner (multisig recommended)
 *
 * Optional (if hooking existing TrustGate + Attestation into Router):
 *   TRUST_GATE_HOOK      - Existing TrustGateACPHook address (skip deploy if set)
 *   ATTESTATION_HOOK     - Existing AttestationHook address (skip deploy if set)
 */
contract DeployMaiatPlugins is Script {
    // ── Existing contracts ──────────────────────────────────
    address acpContract;
    address trustOracle;
    address tokenSafetyOracle;
    address easContract;
    bytes32 easSchemaUID;
    address owner;

    // ── Optional: existing hooks (skip redeploy if set) ─────
    address existingTrustGate;
    address existingAttestation;

    // ── Deployed addresses ──────────────────────────────────
    address tokenSafetyHook;
    address maiatRouterHook;

    function run() external {
        // Load env
        acpContract       = vm.envAddress("ACP_CONTRACT");
        trustOracle       = vm.envAddress("TRUST_ORACLE");
        tokenSafetyOracle = vm.envAddress("TOKEN_SAFETY_ORACLE");
        easContract       = vm.envAddress("EAS_CONTRACT");
        easSchemaUID      = vm.envBytes32("EAS_SCHEMA_UID");
        owner             = vm.envAddress("OWNER");

        // Optional existing hooks
        existingTrustGate  = vm.envOr("TRUST_GATE_HOOK",  address(0));
        existingAttestation = vm.envOr("ATTESTATION_HOOK", address(0));

        uint256 deployerPK = vm.envUint("DEPLOYER_PK");

        console2.log("Deploying Maiat Plugin Hooks...");
        console2.log("  ACP Contract:     ", acpContract);
        console2.log("  Trust Oracle:     ", trustOracle);
        console2.log("  Token Safety Oracle:", tokenSafetyOracle);
        console2.log("  EAS Contract:     ", easContract);
        console2.log("  Owner:            ", owner);

        vm.startBroadcast(deployerPK);

        // 1. Deploy TokenSafetyHook (upgradeable)
        {
            TokenSafetyHook impl = new TokenSafetyHook();
            // DEFAULT_BLOCKED_VERDICTS = Honeypot(1) | HighTax(2) | Blocked(4) = bitmask 22
            uint8 defaultBlocked = TokenSafetyHook(address(impl)).DEFAULT_BLOCKED_VERDICTS();
            bytes memory initData = abi.encodeCall(
                TokenSafetyHook.initialize,
                (tokenSafetyOracle, acpContract, defaultBlocked, owner)
            );
            tokenSafetyHook = address(new ERC1967Proxy(address(impl), initData));
            console2.log("TokenSafetyHook deployed:", tokenSafetyHook);
        }

        // 2. Deploy MaiatRouterHook (upgradeable)
        {
            MaiatRouterHook impl = new MaiatRouterHook();
            bytes memory initData = abi.encodeCall(
                MaiatRouterHook.initialize,
                (acpContract, owner)
            );
            maiatRouterHook = address(new ERC1967Proxy(address(impl), initData));
            console2.log("MaiatRouterHook deployed:", maiatRouterHook);
        }

        // 3. Configure Router: add plugins in priority order
        MaiatRouterHook router = MaiatRouterHook(maiatRouterHook);

        // Plugin 1: TrustGateACPHook (priority 10) — trust check first
        if (existingTrustGate != address(0)) {
            router.addPlugin(existingTrustGate, 10);
            console2.log("Added existing TrustGateACPHook:", existingTrustGate);
        }

        // Plugin 2: TokenSafetyHook (priority 20) — token safety second
        router.addPlugin(tokenSafetyHook, 20);
        console2.log("Added TokenSafetyHook:", tokenSafetyHook);

        // Plugin 3: AttestationHook (priority 30) — afterAction only, runs last
        if (existingAttestation != address(0)) {
            router.addPlugin(existingAttestation, 30);
            console2.log("Added existing AttestationHook:", existingAttestation);
        }

        vm.stopBroadcast();

        // ── Summary ─────────────────────────────────────────
        console2.log("\n=== Deployment Summary ===");
        console2.log("TokenSafetyHook:  ", tokenSafetyHook);
        console2.log("MaiatRouterHook:  ", maiatRouterHook);
        console2.log("\nRouter plugin execution order (beforeAction):");
        if (existingTrustGate != address(0)) {
            console2.log("  1. TrustGateACPHook (priority 10):", existingTrustGate);
        }
        console2.log("  2. TokenSafetyHook (priority 20): ", tokenSafetyHook);
        if (existingAttestation != address(0)) {
            console2.log("  3. AttestationHook (priority 30) [afterAction only]:", existingAttestation);
        }
        console2.log("\nNext steps:");
        console2.log("  1. Set MaiatRouterHook as the hook for new ACP jobs");
        console2.log("  2. Register TokenSafetyHook with EAS schema if needed");
        console2.log("  3. Transfer ownership to multisig: ", owner);
    }
}
