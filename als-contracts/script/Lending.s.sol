// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Lending} from "../src/Lending.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

contract DeployLending is Script {
    uint256 immutable WEEK_1 = 7 * 60 * 60 * 24;
    uint256 immutable MONTHS_1 = 60 * 60 * 24 * 30;

    function run() external {
        address GOVERNANCE_TREASURY_ADDRESS = vm.envAddress("GovernanceTreasuryAddress");
        address PRICE_INDEX_ADDRESS = vm.envAddress("PriceIndexAddress");
        uint256 protocolFee = 15000; // 1.5%
        uint256 repayGracePeriod = 60 * 60 * 24 * 5; // 5 days
        uint256 repayGraceFee = 25000; // 2.5%
        uint256 feeReductionFactor = 14000; // 1.4%
        uint256[] memory originationFeeRanges = new uint256[](3);
        originationFeeRanges[0] = 50000e18; // 50k
        originationFeeRanges[1] = 100000e18; // 100k
        originationFeeRanges[2] = 500000e18; // 500k
        uint256 liquidationFee = 50000; // 5%
        uint256[] memory durations = new uint256[](5);
        durations[0] = WEEK_1;
        durations[1] = MONTHS_1;
        durations[2] = 3 * MONTHS_1;
        durations[3] = 6 * MONTHS_1;
        durations[4] = 12 * MONTHS_1;
        uint256[] memory interestRates = new uint256[](5);
        interestRates[0] = 66000;
        interestRates[1] = 73000;
        interestRates[2] = 80000;
        interestRates[3] = 88000;
        interestRates[4] = 97000;
        uint256 baseOriginationFee = 10000; // 1%

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("Deploying Lending contract...");
        vm.startBroadcast(deployerPrivateKey);
        Lending lending = new Lending(
            PRICE_INDEX_ADDRESS,
            GOVERNANCE_TREASURY_ADDRESS,
            protocolFee,
            repayGracePeriod,
            repayGraceFee,
            originationFeeRanges,
            feeReductionFactor,
            liquidationFee,
            durations,
            interestRates,
            baseOriginationFee
        );
        vm.stopBroadcast();
        console.log("Lending contract successfully deplyed at: ", address(lending));
    }
}
