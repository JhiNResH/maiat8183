// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IACPHook} from "../IACPHook.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title MaiatRouterHook
 * @notice Composite IACPHook that chains multiple plugin hooks in priority order.
 *         Enables flexible composition of hook behaviors for ERC-8183 jobs.
 *
 * @dev This is a REFERENCE IMPLEMENTATION for the ERC-8183 hook system.
 *
 * Hook points:
 *   - beforeAction → Iterates enabled plugins in priority order (ascending).
 *                    If any plugin reverts, entire call reverts.
 *   - afterAction  → Iterates enabled plugins in priority order (ascending).
 *                    Wraps calls in try/catch so failures don't block job completion.
 *
 * Features:
 *   - Max 10 plugins for gas safety
 *   - No duplicate plugin addresses
 *   - Admin can add, remove, enable, disable plugins
 *   - Plugins sorted by priority (ascending — lower number = earlier execution)
 *   - Upgradeable via UUPS pattern (OwnableUpgradeable + storage gap)
 *
 * @custom:security-contact security@maiat.io
 */
contract MaiatRouterHook is IACPHook, OwnableUpgradeable {
    /*//////////////////////////////////////////////////////////////
                            TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Plugin configuration
    struct Plugin {
        IACPHook hook;
        bool enabled;
        uint256 priority;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum number of plugins (gas safety)
    uint256 public constant MAX_PLUGINS = 10;

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice AgenticCommerce contract — used for access control
    address public s_agenticCommerce;

    /// @notice Array of registered plugins
    Plugin[] private s_plugins;

    /// @notice Mapping to check if a hook address is already registered
    mapping(address => bool) public s_registered;

    /// @dev Reserved storage gap for future upgrades
    uint256[44] private __gap;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event PluginAdded(address indexed hook, uint256 priority);
    event PluginRemoved(address indexed hook);
    event PluginEnabled(address indexed hook);
    event PluginDisabled(address indexed hook);
    event PluginPriorityUpdated(address indexed hook, uint256 oldPriority, uint256 newPriority);
    event AgenticCommerceUpdated(address indexed oldAC, address indexed newAC);
    event PluginBeforeActionFailed(address indexed hook, uint256 indexed jobId, bytes reason);
    event PluginAfterActionFailed(address indexed hook, uint256 indexed jobId, bytes reason);

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error MaiatRouterHook__ZeroAddress();
    error MaiatRouterHook__OnlyAgenticCommerce();
    error MaiatRouterHook__MaxPluginsReached();
    error MaiatRouterHook__PluginAlreadyRegistered(address hook);
    error MaiatRouterHook__PluginNotFound(address hook);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the MaiatRouterHook
     * @param agenticCommerce_ AgenticCommerce contract address
     * @param owner_ Contract owner address
     */
    function initialize(
        address agenticCommerce_,
        address owner_
    ) external initializer {
        if (agenticCommerce_ == address(0)) revert MaiatRouterHook__ZeroAddress();

        __Ownable_init(owner_);
        s_agenticCommerce = agenticCommerce_;
    }

    /*//////////////////////////////////////////////////////////////
                    IACPHook: beforeAction
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Called before state transitions. Executes all enabled plugins in priority order.
     * @dev Only callable by AgenticCommerce. If any plugin reverts, entire call reverts.
     * @param jobId The job ID
     * @param selector The function selector being called
     * @param data Encoded function parameters
     */
    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external override {
        if (msg.sender != s_agenticCommerce) revert MaiatRouterHook__OnlyAgenticCommerce();

        uint256 len = s_plugins.length;
        if (len == 0) return;

        // Get sorted indices by priority
        uint256[] memory sortedIndices = _getSortedIndices();

        // Execute enabled plugins in priority order (ascending)
        for (uint256 i = 0; i < len; i++) {
            Plugin storage plugin = s_plugins[sortedIndices[i]];
            if (plugin.enabled) {
                // No try/catch — revert propagates to block the action
                plugin.hook.beforeAction(jobId, selector, data);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    IACPHook: afterAction
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Called after state transitions. Executes all enabled plugins in priority order.
     * @dev Only callable by AgenticCommerce. Uses try/catch so failures don't revert.
     * @param jobId The job ID
     * @param selector The function selector being called
     * @param data Encoded function parameters
     */
    function afterAction(uint256 jobId, bytes4 selector, bytes calldata data) external override {
        if (msg.sender != s_agenticCommerce) revert MaiatRouterHook__OnlyAgenticCommerce();

        uint256 len = s_plugins.length;
        if (len == 0) return;

        // Get sorted indices by priority
        uint256[] memory sortedIndices = _getSortedIndices();

        // Execute enabled plugins in priority order (ascending)
        for (uint256 i = 0; i < len; i++) {
            Plugin storage plugin = s_plugins[sortedIndices[i]];
            if (plugin.enabled) {
                // Wrap in try/catch — failures don't block job completion
                try plugin.hook.afterAction(jobId, selector, data) {
                    // Success — continue to next plugin
                } catch (bytes memory reason) {
                    emit PluginAfterActionFailed(address(plugin.hook), jobId, reason);
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    ERC-165
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice ERC-165 interface support
     * @param interfaceId The interface identifier
     * @return True if supported
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IACPHook).interfaceId
            || interfaceId == 0x01ffc9a7; // IERC165
    }

    /*//////////////////////////////////////////////////////////////
                    ADMIN: Plugin Management
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a new plugin hook
     * @param hook The hook contract address
     * @param priority Execution priority (lower = earlier)
     */
    function addPlugin(address hook, uint256 priority) external onlyOwner {
        if (hook == address(0)) revert MaiatRouterHook__ZeroAddress();
        if (s_registered[hook]) revert MaiatRouterHook__PluginAlreadyRegistered(hook);
        if (s_plugins.length >= MAX_PLUGINS) revert MaiatRouterHook__MaxPluginsReached();

        s_plugins.push(Plugin({
            hook: IACPHook(hook),
            enabled: true,
            priority: priority
        }));
        s_registered[hook] = true;

        emit PluginAdded(hook, priority);
    }

    /**
     * @notice Remove a plugin hook
     * @param hook The hook contract address to remove
     */
    function removePlugin(address hook) external onlyOwner {
        if (!s_registered[hook]) revert MaiatRouterHook__PluginNotFound(hook);

        uint256 len = s_plugins.length;
        for (uint256 i = 0; i < len; i++) {
            if (address(s_plugins[i].hook) == hook) {
                // Swap with last and pop
                if (i != len - 1) {
                    s_plugins[i] = s_plugins[len - 1];
                }
                s_plugins.pop();
                s_registered[hook] = false;

                emit PluginRemoved(hook);
                return;
            }
        }

        // Should not reach here due to s_registered check
        revert MaiatRouterHook__PluginNotFound(hook);
    }

    /**
     * @notice Enable a plugin
     * @param hook The hook contract address to enable
     */
    function enablePlugin(address hook) external onlyOwner {
        if (!s_registered[hook]) revert MaiatRouterHook__PluginNotFound(hook);

        uint256 len = s_plugins.length;
        for (uint256 i = 0; i < len; i++) {
            if (address(s_plugins[i].hook) == hook) {
                s_plugins[i].enabled = true;
                emit PluginEnabled(hook);
                return;
            }
        }
    }

    /**
     * @notice Disable a plugin
     * @param hook The hook contract address to disable
     */
    function disablePlugin(address hook) external onlyOwner {
        if (!s_registered[hook]) revert MaiatRouterHook__PluginNotFound(hook);

        uint256 len = s_plugins.length;
        for (uint256 i = 0; i < len; i++) {
            if (address(s_plugins[i].hook) == hook) {
                s_plugins[i].enabled = false;
                emit PluginDisabled(hook);
                return;
            }
        }
    }

    /**
     * @notice Update a plugin's priority
     * @param hook The hook contract address
     * @param newPriority The new priority value
     */
    function setPluginPriority(address hook, uint256 newPriority) external onlyOwner {
        if (!s_registered[hook]) revert MaiatRouterHook__PluginNotFound(hook);

        uint256 len = s_plugins.length;
        for (uint256 i = 0; i < len; i++) {
            if (address(s_plugins[i].hook) == hook) {
                uint256 oldPriority = s_plugins[i].priority;
                s_plugins[i].priority = newPriority;
                emit PluginPriorityUpdated(hook, oldPriority, newPriority);
                return;
            }
        }
    }

    /**
     * @notice Update the AgenticCommerce contract reference
     * @param agenticCommerce_ New AgenticCommerce address
     */
    function setAgenticCommerce(address agenticCommerce_) external onlyOwner {
        if (agenticCommerce_ == address(0)) revert MaiatRouterHook__ZeroAddress();
        address old = s_agenticCommerce;
        s_agenticCommerce = agenticCommerce_;
        emit AgenticCommerceUpdated(old, agenticCommerce_);
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get all registered plugins
     * @return Array of plugin configurations
     */
    function getPlugins() external view returns (Plugin[] memory) {
        return s_plugins;
    }

    /**
     * @notice Get the number of registered plugins
     * @return Plugin count
     */
    function getPluginCount() external view returns (uint256) {
        return s_plugins.length;
    }

    /**
     * @notice Check if a hook is registered
     * @param hook The hook address to check
     * @return True if registered
     */
    function isPluginRegistered(address hook) external view returns (bool) {
        return s_registered[hook];
    }

    /**
     * @notice Get plugin info by address
     * @param hook The hook address
     * @return enabled Whether the plugin is enabled
     * @return priority The plugin's priority
     */
    function getPluginInfo(address hook) external view returns (bool enabled, uint256 priority) {
        if (!s_registered[hook]) revert MaiatRouterHook__PluginNotFound(hook);

        uint256 len = s_plugins.length;
        for (uint256 i = 0; i < len; i++) {
            if (address(s_plugins[i].hook) == hook) {
                return (s_plugins[i].enabled, s_plugins[i].priority);
            }
        }

        // Should not reach here
        revert MaiatRouterHook__PluginNotFound(hook);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get indices sorted by priority (ascending)
     *      Uses simple insertion sort since MAX_PLUGINS = 10
     * @return sortedIndices Array of indices into s_plugins sorted by priority
     */
    function _getSortedIndices() internal view returns (uint256[] memory sortedIndices) {
        uint256 len = s_plugins.length;
        sortedIndices = new uint256[](len);

        // Initialize indices
        for (uint256 i = 0; i < len; i++) {
            sortedIndices[i] = i;
        }

        // Insertion sort by priority (ascending)
        for (uint256 i = 1; i < len; i++) {
            uint256 key = sortedIndices[i];
            uint256 keyPriority = s_plugins[key].priority;
            uint256 j = i;

            while (j > 0 && s_plugins[sortedIndices[j - 1]].priority > keyPriority) {
                sortedIndices[j] = sortedIndices[j - 1];
                j--;
            }
            sortedIndices[j] = key;
        }

        return sortedIndices;
    }
}
