import { solidityPackedKeccak256 } from "ethers"; // Ethers utils
import keccak256 from "keccak256"; // Keccak256 hashing
import MerkleTree from "merkletreejs"; // MerkleTree.js

// Output file path
// const outputPath: string = path.join(__dirname, "../merkle.json");

// Airdrop recipient addresses and scaled token values
export type AirdropRecipient = {
  // Recipient address
  address: string;
  // Scaled-to-decimals token value
  value: bigint;
};

export default class Generator {
  // Airdrop recipients
  recipients: AirdropRecipient[] = [];

  /**
   * Setup generator
   * @param {number} decimals of token
   * @param {Record<string, number>} airdrop address to token claim mapping
   */
  constructor(airdrop: AirdropRecipient[]) {
    // For each airdrop entry
    // for (const [address, tokens] of Object.entries(airdrop)) {
    //   // Push:
    //   this.recipients.push({
    //     // Checksum address
    //     address: getAddress(address),
    //     // Scaled number of tokens claimable by recipient
    //     value: parseUnits(tokens.toString(), decimals).toString(),
    //   });
    // }
    this.recipients = airdrop;
  }

  /**
   * Generate Merkle Tree leaf from address and value
   * @param {string} address of airdrop claimee
   * @param {string} value of airdrop tokens to claimee
   * @returns {Buffer} Merkle Tree node
   */
  generateLeaf(address: string, value: string): Buffer {
    return Buffer.from(
      // Hash in appropriate Merkle format
      solidityPackedKeccak256(["address", "uint256"], [address, value]).slice(
        2
      ),
      "hex"
    );
  }

  process() {
    console;
    // Generate merkle tree
    const merkleTree = new MerkleTree(
      // Generate leafs
      this.recipients.map(({ address, value }) =>
        this.generateLeaf(address, value.toString())
      ),
      // Hashing function
      keccak256,
      { sortPairs: true }
    );

    const proofs = merkleTree.getLeaves().map((leaf) => {
      return merkleTree.getHexProof(leaf);
    });
    // Collect and log merkle root
    const merkleRoot: string = merkleTree.getHexRoot();

    return { root: merkleRoot, proofs, leaves: merkleTree.getLeaves() };
  }
}
