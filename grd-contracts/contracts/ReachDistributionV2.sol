// SPDX-License-Identifier: unlicensed

pragma solidity >=0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ReachDistribution is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event Claimed(
        address indexed account,
        uint256 amount,
        uint256 indexed version
    );
    event EthDistributionSet(bytes32 indexed merkleRoot, uint256 timestamp);
    event ReachDistributionSet(bytes32 indexed merkleRoot, uint256 timestamp);
    event Received(address indexed sender, uint256 amount);
    event RewardsClaimed(
        address indexed account,
        uint256 ethAmount,
        uint256 reachAmount,
        uint256 indexed version,
        uint256 timestamp
    );

    enum RewardType {
        ETH,
        REACH
    }

    struct MerkleTrees {
        bytes32 ethAllocationRoot;
        bytes32 reachAllocationRoot;
    }

    struct Claims {
        uint256 eth;
        uint256 reach;
    }

    mapping(address => Claims) public claims;
    uint256 public currentVersion;
    mapping(address => uint256) public lastClaimedVersion;
    address public reachToken;
    bool public paused;
    uint256 public lockdownPeriod = 1 days;
    uint256 public lockdownStart;
    uint256 public distributionLockStart;
    MerkleTrees public merkleTrees;

    /*
     * @notice Pauses the contract
     */
    function toggleClaiming() external onlyOwner {
        paused = !paused;
    }

    function setEthDistribution(
        bytes32 _merkleRoot,
        uint256 _amount
    ) public onlyOwner {
        require(_merkleRoot != bytes32(0), "Invalid merkle root.");
        require(address(this).balance >= _amount, "Insufficient balance.");
        merkleTrees.ethAllocationRoot = _merkleRoot;
        emit EthDistributionSet(_merkleRoot, block.timestamp);
    }

    function setReachDistribution(
        bytes32 _merkleRoot,
        uint256 _amount
    ) public onlyOwner {
        require(_merkleRoot != bytes32(0), "Invalid merkle root.");
        require(reachToken != address(0), "ERC20 token not set.");
        uint256 balance = IERC20(reachToken).balanceOf(address(this));
        require(balance >= _amount, "Insufficient balance.");
        merkleTrees.reachAllocationRoot = _merkleRoot;
        emit ReachDistributionSet(_merkleRoot, block.timestamp);
    }

    function verifyProof(
        bytes32[] calldata _merkleProof,
        uint256 _amount,
        bytes32 _merkleRoot
    ) internal view returns (bool) {
        bytes32 _leaf = keccak256(abi.encodePacked(msg.sender, _amount));

        return MerkleProof.verify(_merkleProof, _merkleRoot, _leaf);
    }

    /*
     * @notice Allows users to claim rewards
     * @param _amount The amount to be claimed
     * @param _merkleProof The merkle proof required for claiming
     */
    function claimRewards(
        bytes32[] calldata _ethMerkleProof,
        bytes32[] calldata _reachMerkleProof,
        uint256 _ethAmount,
        uint256 _reachAmount
    ) external nonReentrant {
        require(!paused, "Claiming is paused.");
        // Ensure the user is claiming for the current version
        require(
            lastClaimedVersion[msg.sender] < currentVersion,
            "Already claimed for this version."
        );

        bool ethValid = verifyProof(
            _ethMerkleProof,
            _ethAmount,
            merkleTrees.ethAllocationRoot
        );
        bool reachValid = verifyProof(
            _reachMerkleProof,
            _reachAmount,
            merkleTrees.reachAllocationRoot
        );

        require(ethValid || reachValid, "Invalid Merkle Proof.");
        lastClaimedVersion[msg.sender] = currentVersion;

        if (ethValid) {
            claims[msg.sender].eth += _ethAmount;
            (bool success, ) = payable(msg.sender).call{value: _ethAmount}("");
            require(success, "Transfer failed.");
        }

        if (reachValid) {
            claims[msg.sender].reach += _reachAmount;
            IERC20(reachToken).safeTransfer(msg.sender, _reachAmount);
        }

        emit RewardsClaimed(
            msg.sender,
            _ethAmount,
            _reachAmount,
            currentVersion,
            block.timestamp
        );
    }

    /*
     * @notice Creates a new distribution
     * @param _merkleRoot The merkle root for the new distribution
     * @param _amount The total amount for the new distribution
     */
    function createDistribution(
        bytes32 _ethMerkleRoot,
        uint256 _ethAmount,
        bytes32 _reachMerkleRoot,
        uint256 _reachAmount
    ) external onlyOwner {
        setEthDistribution(_ethMerkleRoot, _ethAmount);
        setReachDistribution(_reachMerkleRoot, _reachAmount);
        currentVersion++;
    }

    /*
     * @notice Sets the address of the ERC20 token for distributions
     * @param _token The address of the ERC20 token
     */
    function setReachAddress(address _token) external onlyOwner {
        //ensure that the address supports ERC20 interface
        require(
            IERC20(_token).totalSupply() > 0,
            "Invalid ERC20 token address."
        );
        reachToken = _token;
    }

    // Fallback function to receive Ether
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        require(
            block.timestamp > lockdownStart + lockdownPeriod,
            "Lockdown period is not over."
        );
        lockdownStart = block.timestamp;
        super.transferOwnership(newOwner);
    }

    function renounceOwnership() public override onlyOwner {}
}
