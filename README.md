# Chronos Vesting Vault

A decentralized, time-locked asset vesting protocol deployed on the Base L2 network. Chronos allows DAOs, protocols, and founders to securely lock tokens or native ETH for team members and investors, ensuring a trustless, math-backed release schedule.

## Core Mechanics
* **Cliff & Linear Unlocking:** Supports complex vesting schedules including initial lockup periods (cliffs) followed by block-by-block linear token release.
* **Revocable Schedules:** Protocol administrators can configure schedules to be revocable. If an employee leaves, the admin can instantly halt future vesting, while the employee retains the right to claim already vested assets.
* **Permissionless Claiming:** Beneficiaries do not need to wait for the entire schedule to finish. They can interact with the contract at any time to claim the exact amount of assets vested up to the current `block.timestamp`.

## Architecture
Built utilizing Solidity `0.8.37`. The vault architecture favors O(1) mathematical calculations over loop-based state updates, ensuring absolute minimal gas consumption during claiming operations regardless of how long the vesting period lasts.
