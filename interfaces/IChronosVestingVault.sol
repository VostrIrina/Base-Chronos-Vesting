// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;
interface IChronosVestingVault {
    function claimVestedTokens(uint256 scheduleId) external;
    function revokeVestingSchedule(uint256 scheduleId) external;
    function computeVestedAmount(uint256 scheduleId) external view returns (uint256);
}
