// SPDX-License-Identifier: unlicensed
pragma solidity >=0.8.19;

import "./ReachDistributionV2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract ReachDistributionFactory is Ownable {
    event ReachAffiliateDistributionCreated(
        address indexed distribution,
        uint256 timestamp
    );

    event PricesSet(
        uint256 credits,
        uint256 minEthAllocation,
        uint256 timestamp
    );

    event TopUp(
        address indexed user,
        uint256 balance,
        uint256 oldBalance,
        uint256 timestamp
    );

    event EthAllocationReserved(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    struct Prices {
        uint256 credits;
        uint256 minEthAllocation;
    }

    address public reachToken;
    mapping(address => uint256) public credits;
    mapping(address => uint256) public ethAllocations;
    ReachDistribution[] public deployedDistributions;
    Prices public prices;

    constructor(address _reachToken) Ownable() {
        reachToken = _reachToken;
    }

    modifier onlySigned(bytes calldata _signature, uint256 _data) {
        // Recreate the signed message from the provided credits and user's address
        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, _data));
        bytes32 ethSignedMessageHash = ECDSA.toEthSignedMessageHash(
            messageHash
        );

        // Recover the signer from the provided signature
        address signer = ECDSA.recover(ethSignedMessageHash, _signature);
        require(signer == owner(), "Invalid signature");
        _;
    }

    function topUp(
        uint256 _amount,
        bytes calldata _signature,
        uint256 _previousBalance
    ) external onlySigned(_signature, _previousBalance) {
        uint256 price = _amount * prices.credits;
        require(
            IERC20(reachToken).transferFrom(msg.sender, address(this), price),
            "Transfer failed"
        );

        credits[msg.sender] = _amount + _previousBalance;
        emit TopUp(msg.sender, _amount, _previousBalance, block.timestamp);
    }

    function reserveEthAllocation(
        bytes calldata _signature,
        uint256 _previousBalance
    ) external payable onlySigned(_signature, _previousBalance) {
        require(msg.value >= prices.minEthAllocation, "Must send ETH");
        ethAllocations[msg.sender] = msg.value + _previousBalance;

        emit EthAllocationReserved(msg.sender, msg.value, block.timestamp);
    }

    function setPrices(
        uint256 _credits,
        uint256 _minEthAllocation
    ) external onlyOwner {
        prices = Prices(_credits, _minEthAllocation);
        emit PricesSet(_credits, _minEthAllocation, block.timestamp);
    }

    function deployAffiliateDistribution() external onlyOwner {
        ReachDistribution newDistribution = new ReachDistribution();
        deployedDistributions.push(newDistribution);

        emit ReachAffiliateDistributionCreated(
            address(newDistribution),
            block.timestamp
        );
    }

    function getDeployedDistributions()
        public
        view
        returns (ReachDistribution[] memory)
    {
        return deployedDistributions;
    }
}
