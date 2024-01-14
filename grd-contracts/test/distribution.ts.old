import { expect } from "chai";
import { keccak256, parseEther } from "ethers";
import { ethers } from "hardhat";
import { MerkleTree } from "merkletreejs";
import {
  ReachDistribution,
  ReachDistribution__factory,
} from "../typechain-types";
import Generator, { AirdropRecipient } from "../services/merkle-generator";

describe("ReachDistribution Contract", function () {
  let ReachDistribution: ReachDistribution__factory;
  let reachDistribution: ReachDistribution;
  let owner: any;
  let addr1: any;
  let addr2: any;
  let addrs: any;
  const abiCoder = new ethers.AbiCoder();
  beforeEach(async function () {
    ReachDistribution = await ethers.getContractFactory("ReachDistribution");
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    reachDistribution = await ReachDistribution.deploy();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await reachDistribution.owner()).to.equal(owner.address);
    });

    it("Should have zero balance initially", async function () {
      expect(
        await ethers.provider.getBalance(reachDistribution.getAddress())
      ).to.equal(0);
    });
  });

  describe("Admin Management", function () {
    it("Should allow owner to add and remove admins", async function () {
      await reachDistribution.addAdmin([addr1.address]);
      expect(await reachDistribution.isAdmin(addr1.address)).to.equal(true);

      await reachDistribution.removeAdmin([addr1.address]);
      expect(await reachDistribution.isAdmin(addr1.address)).to.equal(false);
    });

    it("Should not allow non-owner to add and remove admins", async function () {
      await expect(
        reachDistribution.connect(addr1).addAdmin([addr1.address])
      ).to.be.revertedWith("Ownable: caller is not the owner");

      await expect(
        reachDistribution.connect(addr1).removeAdmin([addr1.address])
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should allow admin to toggle claims", async function () {
      await reachDistribution.toggleClaiming();
      expect(await reachDistribution.paused()).to.equal(true);

      await reachDistribution.toggleClaiming();
      expect(await reachDistribution.paused()).to.equal(false);
    });

    it("Should not allow non-admin to toggle claims", async function () {
      await expect(
        reachDistribution.connect(addr1).toggleClaiming()
      ).to.be.revertedWith("Caller is not an admin");
    });

    it("Should be able to withdraw from the contract", async function () {
      const amount = parseEther("1"); // 1 ether
      await reachDistribution
        .connect(owner)
        .createMission("missionId1", amount, { value: amount });

      const balance = await ethers.provider.getBalance(
        reachDistribution.getAddress()
      );
      expect(balance).to.equal(amount);

      await reachDistribution.connect(owner).withdraw();
      expect(
        await ethers.provider.getBalance(reachDistribution.getAddress())
      ).to.equal(0);
    });
  });

  describe("Mission Management", function () {
    it("Should allow to create a mission", async function () {
      const missionId = "mission1";
      const amount = parseEther("1"); // 1 ether

      // Send transaction to create a mission
      await reachDistribution
        .connect(owner)
        .createMission(missionId, amount, { value: amount });

      // Check mission details
      const mission = await reachDistribution.missions(missionId);
      expect(mission.amount).to.equal(amount);
      expect(mission.creator).to.equal(owner.address);
    });
  });

  describe("Distribution Management", function () {
    it("Should allow to create a distribution", async function () {
      // Assume a simple Merkle Tree with one leaf for simplicity
      const leaf = keccak256(
        abiCoder.encode(["address", "uint256"], [addr1.address, 100])
      );
      const merkleRoot = keccak256(abiCoder.encode(["bytes32"], [leaf]));

      const amount = ethers.parseEther("100"); // 100 ether

      // Send transaction to create a distribution
      await reachDistribution
        .connect(owner)
        .createDistribution(merkleRoot, amount);

      // Check distribution details
      expect(await reachDistribution.merkleRoot()).to.equal(merkleRoot);
      expect(await reachDistribution.currentVersion()).to.equal(1);
    });
  });

  describe("Claims", function () {
    it("Should allow users to claim rewards", async function () {
      const amount = ethers.parseEther("1"); // 1 ether
      const airdropRecipients: AirdropRecipient[] = [
        {
          address: addr1.address,
          value: amount / BigInt(2),
        },
        {
          address: addr2.address,
          value: amount / BigInt(2),
        },
      ];

      const merkleGenerator = new Generator(airdropRecipients);
      const { root, proofs } = merkleGenerator.process();

      await reachDistribution.connect(owner).createMission("mission1", amount, {
        value: amount,
      });
      // Create a distribution
      await reachDistribution.connect(owner).createDistribution(root, amount);

      const proof = proofs[0];
      // Claim rewards
      await reachDistribution
        .connect(addr1)
        .claimRewards(amount / BigInt(2), proof);

      // Check the claim
      expect(await reachDistribution.totalClaimed(addr1.address)).to.equal(
        amount / BigInt(2)
      );
      expect(
        await reachDistribution.lastClaimedVersion(addr1.address)
      ).to.equal(1);
    });
  });

  describe("Token Address Management", function () {
    it("Should allow owner to set the token address", async function () {
      const tokenAddress = addr1.address;
      await reachDistribution.connect(owner).setTokenAddress(tokenAddress);
      expect(await reachDistribution.erc20token()).to.equal(tokenAddress);
    });

    it("Should not allow non-owner to set the token address", async function () {
      const tokenAddress = addr1.address; // Example token address
      await expect(
        reachDistribution.connect(addr1).setTokenAddress(tokenAddress)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });
});
