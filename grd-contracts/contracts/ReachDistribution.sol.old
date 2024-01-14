// SPDX-License-Identifier: GPL-3.0

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

    event DistributionCreated(uint256 indexed version, uint256 amount);
    event Received(address indexed sender, uint256 amount);
    event MissionCreated(string missionId, uint256 amount);

    enum PaymentType {
        ETH,
        ERC20
    }

    mapping(address => uint256) public totalClaimed;
    bytes32 public merkleRoot;
    uint256 public currentVersion;
    mapping(address => uint256) public lastClaimedVersion;
    address public erc20token;
    bool public paused;
    uint256 public lockdownPeriod = 1 days;
    uint256 public lockdownStart;
    uint256 public distributionLockStart;
    // Admins enumerable set
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private admins;

    constructor() Ownable(msg.sender) {
        admins.add(msg.sender);
    }

    modifier onlyAdmin() {
        require(isAdmin(msg.sender), "Caller is not an admin");
        _;
    }

    /*
     * @notice Pauses the contract
     */
    function toggleClaiming() external onlyOwner {
        paused = !paused;
    }

    /*
     * @notice Checks if an address is an admin
     * @param _account The address to check
     * @return bool indicating whether the address is an admin
     */
    function isAdmin(address _account) public view returns (bool) {
        return admins.contains(_account);
    }

    /*
     * @notice Adds new admins
     * @param _account The addresses to be added as admins
     */
    function addAdmin(address[] memory _account) external onlyOwner {
        //max admins is 5
        require(admins.length() + _account.length <= 5, "Too many admins");
        require(
            block.timestamp > lockdownStart + lockdownPeriod,
            "Lockdown period is not over."
        );
        require(_account.length <= 10, "Too many admins");
        for (uint i = 0; i < _account.length; i++) {
            admins.add(_account[i]);
        }
        lockdownStart = block.timestamp;
    }

    /*
     * @notice Removes admins
     * @param _account The addresses to be removed from admins
     */
    function removeAdmin(address[] memory _account) external onlyOwner {
        require(
            block.timestamp > lockdownStart + lockdownPeriod,
            "Lockdown period is not over."
        );
        require(_account.length <= 10, "Too many admins");
        for (uint i = 0; i < _account.length; i++) {
            admins.remove(_account[i]);
        }
        lockdownStart = block.timestamp;
    }

    /*
     * @notice Allows users to claim rewards
     * @param _amount The amount to be claimed
     * @param _merkleProof The merkle proof required for claiming
     */
    function claimRewards(
        uint256 _amount,
        bytes32[] calldata _merkleProof,
        PaymentType _paymentType
    ) external nonReentrant {
        require(!paused, "Claiming is paused.");
        // Ensure the user is claiming for the current version
        require(
            lastClaimedVersion[msg.sender] < currentVersion,
            "Already claimed for this version."
        );

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _amount));
        require(
            MerkleProof.verify(_merkleProof, merkleRoot, leaf),
            "Invalid Merkle Proof."
        );

        totalClaimed[msg.sender] += _amount;
        lastClaimedVersion[msg.sender] = currentVersion;

        if (_paymentType == PaymentType.ERC20) {
            require(erc20token != address(0), "ERC20 token not set.");
            IERC20(erc20token).safeTransfer(msg.sender, _amount);
        } else {
            // Transfer the amount to the user
            (bool success, ) = payable(msg.sender).call{value: _amount}("");
            require(success, "Transfer failed.");
        }

        emit Claimed(msg.sender, _amount, currentVersion);
    }

    /*
     * @notice Creates a new distribution
     * @param _merkleRoot The merkle root for the new distribution
     * @param _amount The total amount for the new distribution
     */
    function createDistribution(
        bytes32 _merkleRoot,
        uint256 _amount,
        PaymentType _paymentType
    ) external onlyAdmin {
        require(_merkleRoot != bytes32(0), "Invalid merkle root.");
        if (_paymentType == PaymentType.ERC20) {
            require(erc20token != address(0), "ERC20 token not set.");
            uint256 balance = IERC20(erc20token).balanceOf(address(this));
            require(balance >= _amount, "Insufficient balance.");
        } else {
            require(address(this).balance >= _amount, "Insufficient balance.");
        }

        if (msg.sender != owner()) {
            require(
                block.timestamp > distributionLockStart + lockdownPeriod,
                "Lockdown period is not over."
            );
        }
        distributionLockStart = block.timestamp;

        merkleRoot = _merkleRoot;
        currentVersion++;

        emit DistributionCreated(currentVersion, _amount);
    }

    /*
     * @notice Sets the address of the ERC20 token for distributions
     * @param _token The address of the ERC20 token
     */
    function setTokenAddress(address _token) external onlyOwner {
        //ensure that the address supports ERC20 interface
        require(
            IERC20(_token).totalSupply() > 0,
            "Invalid ERC20 token address."
        );
        erc20token = _token;
    }

    /*
     * @notice Creates a new mission
     * @param _missionId The ID of the new mission
     * @param _amount The amount allocated to the new mission
     */
    function createMission(
        string memory _missionId,
        uint256 _amount,
        PaymentType _paymentType
    ) external payable {
        require(_amount > 0, "Amount must be greater than 0.");
        if (_paymentType == PaymentType.ERC20) {
            require(erc20token != address(0), "ERC20 token not set.");
            IERC20(erc20token).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        } else {
            require(_amount == msg.value, "Incorrect amount sent.");
        }

        emit MissionCreated(_missionId, _amount);
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
