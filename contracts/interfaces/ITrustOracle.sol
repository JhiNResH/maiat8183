// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ITrustOracle
/// @notice Trust oracle interface for ERC-8183 trust-based hooks and evaluators.
/// @dev Matches MaiatOracle (TrustScoreOracle) deployed on Base mainnet at 0xc6cf...c6da.
///      Struct field order MUST match the on-chain contract for correct ABI decoding.
interface ITrustOracle {
    struct UserReputation {
        uint256 reputationScore;  // combined score (reviews + activity)
        uint256 totalReviews;     // reviews written
        uint256 scarabPoints;     // token points balance
        uint256 feeBps;           // fee in basis points (50 = 0.5%)
        bool initialized;         // true once updateUserReputation is called
        uint256 lastUpdated;      // block.timestamp of last update
    }

    /// @notice Get full user reputation data
    /// @param user The address to query
    /// @return UserReputation struct with all trust data
    function getUserData(address user) external view returns (UserReputation memory);
}
