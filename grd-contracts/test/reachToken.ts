import { expect } from "chai";
import { ethers } from "hardhat";
import { IUniswapV2Router02Interface } from "../typechain-types/contracts/Uniswap.sol/IUniswapV2Router02";
import { Reach, Reach__factory } from "../typechain-types";

const addrs: string[] = [];

describe("$Reach tests", function () {
  console.log("Starting tests");
  let TokenFactory: Reach__factory;
  let UniswapFactory: IUniswapV2Router02Interface;
  let uniswap: any;
  let token: Reach;
  let owner: any;
  let addr1: any;
  let addr2: any;
  let addrs: any;

  const abiCoder = new ethers.AbiCoder();
  beforeEach(async function () {
    addrs = await ethers.getSigners();
    TokenFactory = await ethers.getContractFactory("Reach");
    uniswap = await ethers.getContractAt(
      "IUniswapV2Router02",
      "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"
    );
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    token = await TokenFactory.deploy();
    await token.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await token.owner()).to.equal(owner.address);
    });

    it("Should have zero balance initially", async function () {
      expect(await ethers.provider.getBalance(token.getAddress())).to.equal(0);
    });
  });
});
