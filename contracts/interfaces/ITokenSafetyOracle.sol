// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ITokenSafetyOracle
/// @notice Minimal token safety oracle interface for ERC-8183 TokenSafetyHook.
/// @dev Shared interface — do not duplicate in individual contracts.
/// @custom:security-contact security@maiat.io
interface ITokenSafetyOracle {
    /// @notice Token safety verdict from oracle analysis
    /// @dev Safe(0), Honeypot(1), HighTax(2), Unverified(3), Blocked(4)
    enum TokenVerdict {
        Safe,
        Honeypot,
        HighTax,
        Unverified,
        Blocked
    }

    /// @notice Token safety data returned by oracle
    /// @param verdict The overall safety verdict
    /// @param buyTax Buy tax percentage (basis points, 10000 = 100%)
    /// @param sellTax Sell tax percentage (basis points, 10000 = 100%)
    /// @param verified Whether the token has been verified by oracle
    /// @param lastUpdated Timestamp of last oracle update for this token
    struct TokenSafetyData {
        TokenVerdict verdict;
        uint256 buyTax;
        uint256 sellTax;
        bool verified;
        uint256 lastUpdated;
    }

    /// @notice Get safety data for a token
    /// @param token The token address to check
    /// @return data The token safety data
    function getTokenSafety(address token) external view returns (TokenSafetyData memory data);
}
