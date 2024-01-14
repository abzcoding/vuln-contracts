# Test Contract

Test is a smart contract developed on the Ethereum blockchain using Solidity programming language version 0.8.19 or later. This contract is intended to manage distributions and missions in a systematic and secure manner.

## Features:

1. **Ownership and Admin Control**: 
   - The contract utilizes OpenZeppelin's Ownable and ReentrancyGuard libraries to manage ownership and reentrancy attacks, respectively.
   - It also includes an admin system to allow for multiple administrators with different levels of control over the contract.

2. **ERC-20 Token and Ether Distribution**:
   - The contract supports distributions in both ERC-20 tokens and Ether.
   - It has a mechanism to toggle between token and Ether distributions.

3. **Claiming System**:
   - Users can claim rewards based on the amount allocated to them.
   - Each distribution can be uniquely identified using a version number.
   - The MerkleProof library is used to verify claims against a Merkle root, ensuring the authenticity of claims.

4. **Missions**:
   - The contract has a system to create missions, with each mission having a unique ID and a specified amount of funds allocated to it.

5. **Events**:
   - Events are emitted for significant actions within the contract, such as claims, creation of distributions, and missions, allowing for easier monitoring and auditing.

6. **Fallback Function**:
   - The contract includes a fallback function to receive Ether.

## Getting Started

1. **Prerequisites**:
   - Ensure you have a development environment set up for Ethereum smart contracts (e.g., Truffle or Hardhat).
   - Install the necessary OpenZeppelin contracts and libraries as imported at the beginning of the contract.

2. **Deployment**:
   - Deploy the `ReachDistribution` contract to the Ethereum network using a migration script or through a development environment like Truffle.

3. **Admin Management**:
   - Use `addAdmin` and `removeAdmin` functions to manage admin addresses.
   - Toggle claiming functionality using the `toggleClaiming` function.

4. **Creating Distributions**:
   - Create a new distribution using the `createDistribution` function, specifying a new Merkle root and the total amount for the distribution.
   - Set the address of the ERC-20 token for distributions using `setTokenAddress` if necessary.

5. **Claiming Rewards**:
   - Users can claim their rewards using the `claimRewards` function by providing the amount and Merkle proof.

6. **Creating Missions**:
   - Create a new mission using the `createMission` function, specifying a mission ID and the amount allocated to the mission.

7. **Withdrawal**:
   - The owner can withdraw remaining funds from the contract using the `withdraw` function.

## Security

- The contract uses ReentrancyGuard to prevent reentrancy attacks.
- Only the owner and admins have the authority to perform critical actions within the contract.
- The contract code should be audited by a professional smart contract auditor before mainnet deployment to ensure it's free from bugs and vulnerabilities.

## Events

- `Claimed`: Emitted when a user claims rewards.
- `DistributionCreated`: Emitted when a new distribution is created.
- `Received`: Emitted when the contract receives Ether.
- `MissionCreated`: Emitted when a new mission is created.

## Interfaces and Libraries

- The contract imports several libraries and contracts from OpenZeppelin for safe math operations, ownership management, reentrancy guard, and ERC-20 token standards.

## Functions

The contract has various functions to manage distributions, claims, missions, admins, and the owner's control over the contract.

## Future Improvements

- Any future improvements or updates to the contract can be managed by the owner or admins as necessary.
- Additional functionalities or optimizations may be added to enhance the contract's efficiency and usability.