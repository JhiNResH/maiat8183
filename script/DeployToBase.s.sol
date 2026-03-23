// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TokenSafetyHook} from "../contracts/hooks/TokenSafetyHook.sol";
import {MaiatRouterHook} from "../contracts/hooks/MaiatRouterHook.sol";
import {TrustGateACPHook} from "../contracts/hooks/TrustGateACPHook.sol";
import {AttestationHook} from "../contracts/hooks/AttestationHook.sol";
import {TrustBasedEvaluator} from "../contracts/hooks/TrustBasedEvaluator.sol";
import {EvaluatorRegistry} from "../contracts/EvaluatorRegistry.sol";

/**
 * @title DeployToBase
 * @notice Production deployment for Maiat trust hooks on Base.
 *         Points to the live MaiatOracle (TrustScoreOracle) at 0xc6cf...c6da.
 *
 * Usage:
 *   forge script script/DeployToBase.s.sol \
 *     --rpc-url $BASE_RPC \
 *     --broadcast --verify -vvvv
 *
 * Required env:
 *   DEPLOYER_PK   - Deployer private key
 *   OWNER         - Contract owner address
 *   ACP_CONTRACT  - AgenticCommerceHooked address (from erc-8183 deploy)
 *
 * Optional:
 *   EAS_SCHEMA_UID - Pre-registered EAS schema UID (default: skip AttestationHook)
 */
contract DeployToBase is Script {
    // -- Live Maiat contracts on Base mainnet --
    address constant MAIAT_ORACLE = 0xC6CFd160EE9E0c0e8e8ac5b005A1f1Ae0B76c6Da;

    // -- Base mainnet EAS --
    address constant EAS_CONTRACT = 0x4200000000000000000000000000000000000021;

    function run() external {
        uint256 deployerPK = vm.envUint("DEPLOYER_PK");
        address owner = vm.envAddress("OWNER");
        address acpContract = vm.envAddress("ACP_CONTRACT");
        bytes32 easSchemaUID = vm.envOr("EAS_SCHEMA_UID", bytes32(0));

        console2.log("=== Maiat Trust Hooks - Base Deploy ===");
        console2.log("Oracle:      ", MAIAT_ORACLE);
        console2.log("ACP Contract:", acpContract);
        console2.log("Owner:       ", owner);

        vm.startBroadcast(deployerPK);

        // 1. TrustGateACPHook (upgradeable proxy)
        address trustGate;
        {
            TrustGateACPHook impl = new TrustGateACPHook();
            bytes memory initData = abi.encodeCall(
                TrustGateACPHook.initialize,
                (MAIAT_ORACLE, acpContract, 60, 60, owner)
            );
            trustGate = address(new ERC1967Proxy(address(impl), initData));
            console2.log("TrustGateACPHook:", trustGate);
        }

        // 2. TokenSafetyHook (upgradeable proxy)
        address tokenSafety;
        {
            TokenSafetyHook impl = new TokenSafetyHook();
            bytes memory initData = abi.encodeCall(
                TokenSafetyHook.initialize,
                (MAIAT_ORACLE, acpContract, 7, owner)
            );
            tokenSafety = address(new ERC1967Proxy(address(impl), initData));
            console2.log("TokenSafetyHook: ", tokenSafety);
        }

        // 3. AttestationHook (constructor-based, only if schema UID is set)
        address attestation;
        if (easSchemaUID != bytes32(0)) {
            attestation = address(new AttestationHook(acpContract, EAS_CONTRACT, easSchemaUID));
            console2.log("AttestationHook: ", attestation);
        } else {
            console2.log("AttestationHook:  SKIPPED (set EAS_SCHEMA_UID to deploy)");
        }

        // 4. MaiatRouterHook (upgradeable proxy)
        address router;
        {
            MaiatRouterHook impl = new MaiatRouterHook();
            bytes memory initData = abi.encodeCall(
                MaiatRouterHook.initialize,
                (acpContract, owner)
            );
            router = address(new ERC1967Proxy(address(impl), initData));

            // Configure plugin execution order
            MaiatRouterHook(router).addPlugin(trustGate, 10);
            MaiatRouterHook(router).addPlugin(tokenSafety, 20);
            if (attestation != address(0)) {
                MaiatRouterHook(router).addPlugin(attestation, 30);
            }
            console2.log("MaiatRouterHook: ", router);
        }

        // 5. EvaluatorRegistry (upgradeable proxy)
        address registry;
        {
            EvaluatorRegistry impl = new EvaluatorRegistry();
            bytes memory initData = abi.encodeCall(EvaluatorRegistry.initialize, (owner));
            registry = address(new ERC1967Proxy(address(impl), initData));
            console2.log("EvaluatorRegistry:", registry);
        }

        // 6. TrustBasedEvaluator (upgradeable proxy)
        address evaluator;
        {
            TrustBasedEvaluator impl = new TrustBasedEvaluator();
            bytes memory initData = abi.encodeCall(
                TrustBasedEvaluator.initialize,
                (MAIAT_ORACLE, acpContract, 60, owner)
            );
            evaluator = address(new ERC1967Proxy(address(impl), initData));
            console2.log("TrustBasedEvaluator:", evaluator);
        }

        vm.stopBroadcast();

        // -- Summary --
        console2.log("");
        console2.log("=== Deploy Complete ===");
        console2.log("Router plugin chain:");
        console2.log("  1. TrustGateACPHook  (pri 10) - trust score >= 60");
        console2.log("  2. TokenSafetyHook   (pri 20) - blocks honeypot/rug");
        if (attestation != address(0)) {
            console2.log("  3. AttestationHook   (pri 30) - EAS receipts");
        }
        console2.log("");
        console2.log("Trust Oracle:", MAIAT_ORACLE);
        console2.log("|-- Live on Base with 18,600+ agent scores");
    }
}
