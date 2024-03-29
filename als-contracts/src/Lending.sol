// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Powered by NeoBase: https://github.com/neobase-one

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {UD60x18, ud, convert} from "@prb/math/src/UD60x18.sol";
import {IPriceIndex} from "./IPriceIndex.sol";

contract Lending is ReentrancyGuard, IERC721Receiver, Ownable {
    using SafeERC20 for IERC20;
    using ERC165Checker for address;

    uint256 private constant SECONDS_IN_DAY = 3600 * 24;
    uint256 public constant SECONDS_IN_YEAR = 360 * SECONDS_IN_DAY;
    uint256 public constant PRECISION = 10000;
    uint256 public constant MIN_GRACE_PERIOD = 2 * SECONDS_IN_DAY;
    uint256 public constant MAX_GRACE_PERIOD = 15 * SECONDS_IN_DAY;
    uint256 public constant MAX_PROTOCOL_FEE = 4 * PRECISION;
    uint256 public constant MAX_REPAY_GRACE_FEE = 4 * PRECISION;
    uint256 public constant MAX_BASE_ORIGINATION_FEE = 3 * PRECISION;
    uint256 public constant MAX_LIQUIDATION_FEE = 15 * PRECISION;
    uint256 public constant MAX_INTEREST_RATE = 20 * PRECISION;

    /**
     * @notice PriceIndex contract for NFT price valuations
     */
    IPriceIndex public priceIndex;

    /**
     * @notice Address of the GovernanceTreasury contract
     */
    address public governanceTreasury;

    /**
     * @notice Loan struct to store loans details
     */
    struct Loan {
        address borrower;
        address token;
        uint256 amount;
        address nftCollection;
        uint256 nftId;
        uint256 duration;
        uint256 interestRate;
        uint256 collateralValue;
        address lender;
        uint256 startTime;
        uint256 deadline;
        bool paid;
        bool cancelled;
    }

    /**
     * @notice Protocol fee rate (in basis points)
     */
    uint256 public protocolFee;

    /**
     * @notice Repayment grace period in seconds
     */
    uint256 public repayGracePeriod;

    /**
     * @notice Fee paid if loan repayment occurs during the grace period
     */
    uint256 public repayGraceFee;

    /**
     * @notice Origination fee ranges array
     */
    uint256[] public originationFeeRanges;

    /**
     * @notice Factor for calculating origination fee for next range
     */
    uint256 public feeReductionFactor;

    /**
     * @notice Fee paid during the liquidation process
     */
    uint256 public liquidationFee;

    /**
     * @notice Base origination fee based on loan amount
     */
    uint256 public baseOriginationFee;

    /**
     * @notice ID for the last created loan
     */
    uint256 public lastLoanId;

    /**
     * @notice Mapping from loan IDs to Loan structures
     */
    mapping(uint256 => Loan) private loans;

    /**
     * @notice Mapping for allowed tokens to be borrowed
     */
    mapping(address => bool) public allowedTokens;

    /**
     * @notice Mapping from loan duration to APR in %
     */
    mapping(uint256 => uint256) public aprFromDuration; // apr in %

    /**
     * @notice Emitted when a loan is created
     * @param loanId The unique identifier of the created loan
     * @param borrower The address of the borrower
     * @param token The address of the token in which the loan is denominated
     * @param amount The amount of tokens borrowed
     * @param nftCollection The address of the NFT collection used as collateral
     * @param nftId The unique identifier of the NFT within the collection
     * @param duration The duration of the loan in seconds
     * @param interestRate The annual interest rate in basis points
     * @param collateralValue The value of the NFT collateral in the token’s smallest units
     * @param deadline The deadline for accepting the loan
     */
    event LoanCreated(
        uint256 indexed loanId,
        address indexed borrower,
        address token,
        uint256 amount,
        address indexed nftCollection,
        uint256 nftId,
        uint256 duration,
        uint256 interestRate,
        uint256 collateralValue,
        uint256 deadline
    );

    /**
     * @notice Emitted when a loan is accepted by a lender
     * @param loanId The unique identifier of the accepted loan
     * @param lender The address of the lender
     * @param startTime The timestamp in seconds at which the loan becomes active
     */
    event LoanAccepted(uint256 indexed loanId, address indexed lender, uint256 startTime);

    /**
     * @notice Emitted when a loan is cancelled by the borrower
     * @param loanId The unique identifier of the cancelled loan
     */
    event LoanCancelled(uint256 indexed loanId);

    /**
     * @notice Emitted when a loan repayment is done by the borrower
     * @param loanId The unique identifier of the repaid loan
     * @param totalPaid The total amount paid by the borrower including fees
     * @param fees The fee amount charged on repayment in the token’s smallest units
     */
    event LoanRepayment(uint256 indexed loanId, uint256 totalPaid, uint256 fees);

    /**
     * @notice Emitted when a loan is liquidated
     * @param loanId The unique identifier of the liquidated loan
     * @param liquidator The address of the entity that triggered the liquidation
     * @param totalPaid The total amount that was due at the time of liquidation
     * @param fees The fee amount charged on liquidation in the token’s smallest units
     */
    event LoanLiquidated(uint256 indexed loanId, address indexed liquidator, uint256 totalPaid, uint256 fees);

    /**
     * @notice Emitted when NFT is claimed by lender from an overdue loan
     * @param loanId The unique identifier of the overdue loan
     */
    event NFTClaimed(uint256 indexed loanId);

    /**
     * @notice Emitted when the price index oracle is updated
     * @param newPriceIndex The address of the new price index oracle
     */
    event PriceIndexSet(address indexed newPriceIndex);

    /**
     * @notice Emitted when the governance treasury is updated
     * @param newGovernanceTreasury The address of the new governance treasury contract
     */
    event GovernanceTreasurySet(address indexed newGovernanceTreasury);

    /**
     * @notice Emitted when the repayment grace period is updated
     * @param newRepayGracePeriod The new grace period for repayment, in seconds
     */
    event RepayGracePeriodSet(uint256 newRepayGracePeriod);

    /**
     * @notice Emitted when the repayment grace fee is updated
     * @param newRepayGraceFee The new grace fee for repayment
     */
    event RepayGraceFeeSet(uint256 newRepayGraceFee);

    /**
     * @notice Emitted when the protocol fee is updated
     * @param newProtocolFee The new protocol fee, in basis points
     */
    event ProtocolFeeSet(uint256 newProtocolFee);

    /**
     * @notice Emitted when the liquidation fee is updated
     * @param newLiquidationFee The new liquidation fee
     */
    event LiquidationFeeSet(uint256 newLiquidationFee);

    /**
     * @notice Emitted when the base origination fee is updated
     * @param newBaseOriginationFee The new base origination fee
     */
    event BaseOriginationFeeSet(uint256 newBaseOriginationFee);

    /**
     * @notice Emitted when new tokens are add to allowedTokens
     * @param tokens New allowed tokens
     */
    event TokensSet(address[] tokens);

    /**
     * @notice Emitted when tokens are removed from allowedTokens
     * @param tokens Tokens to be removed from allowedTokens
     */
    event TokensUnset(address[] tokens);

    /**
     * @notice Emitted when new duration-interestRates tuples are added
     * @param durations Array of loan durations
     * @param interestRates Array of loan interest rates for duration
     */
    event LoanTypesSet(uint256[] durations, uint256[] interestRates);

    /**
     * @notice Emitted when duration-interestRates tuples are removed
     * @param durations Array of loan durations
     */
    event LoanTypesUnset(uint256[] durations);

    /**
     * @notice Contract constructor
     * @param _priceIndex Price index contract address
     * @param _governanceTreasury Governance treasury contract address
     * @param _protocolFee Protocol fee in basis point
     * @param _gracePeriod Grace period in seconds
     * @param _repayGraceFee Repay grace fee in %
     * @param _originationFeeRanges Origination fee ranges
     * @param _feeReductionFactor Origination fee reduction factor in %
     * @param _liquidationFee Liquidation fee in %
     * @param _durations Array of allowed loan durations
     * @param _interestRates Array of interest rates corresponding to each duration
     */
    constructor(
        address _priceIndex,
        address _governanceTreasury,
        uint256 _protocolFee,
        uint256 _gracePeriod,
        uint256 _repayGraceFee,
        uint256[] memory _originationFeeRanges,
        uint256 _feeReductionFactor,
        uint256 _liquidationFee,
        uint256[] memory _durations,
        uint256[] memory _interestRates,
        uint256 _baseOriginationFee
    ) {
        originationFeeRanges = _originationFeeRanges;

        feeReductionFactor = _feeReductionFactor;

        _setProtocolFee(_protocolFee);
        _setRepayGracePeriod(_gracePeriod);
        _setRepayGraceFee(_repayGraceFee);
        _setGovernanceTreasury(_governanceTreasury);
        _setPriceIndex(_priceIndex);
        _setLiquidationFee(_liquidationFee);
        _setLoanTypes(_durations, _interestRates);
        _setBaseOriginationFee(_baseOriginationFee);
    }

    /**
     * @notice ERC721 Token Received Hook
     * @dev Needed as a callback to receive ERC721 token through `safeTransferFrom` function
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @notice Allows a user to borrow a specified amount using an NFT as collateral
     * @dev Ensures that the token is allowed and the duration is valid before creating the loan
     * @dev Only NFTs that have a valuation from the PriceIndex contract can be used as collateral
     * @param _token The address of the token being borrowed
     * @param _amount The amount of tokens to be borrowed
     * @param _nftCollection The address of the NFT collection used as collateral
     * @param _nftId The ID of the NFT being used as collateral
     * @param _duration The duration of the loan
     * @param _deadline The deadline to accept the loan request
     */
    function requestLoan(
        address _token,
        uint256 _amount,
        address _nftCollection,
        uint256 _nftId,
        uint256 _duration,
        uint256 _deadline
    ) external nonReentrant {
        require(allowedTokens[_token], "Lending: borrow token not allowed");
        require(aprFromDuration[_duration] != 0, "Lending: invalid duration");
        require(_amount > 0, "Lending: borrow amount must be greater than zero");
        require(_deadline > block.timestamp, "Lending: deadline must be after current timestamp");

        IPriceIndex.Valuation memory valuation = priceIndex.getValuation(_nftCollection, _nftId);

        require(_amount <= (valuation.price * valuation.ltv) / 100, "Lending: amount greater than max borrow");

        Loan storage loan = loans[++lastLoanId];
        loan.borrower = msg.sender;
        loan.token = _token;
        loan.amount = _amount;
        loan.nftCollection = _nftCollection;
        loan.nftId = _nftId;
        loan.duration = _duration;
        loan.collateralValue = valuation.price;
        loan.interestRate = aprFromDuration[_duration];
        loan.paid = false;
        loan.deadline = _deadline;
        loan.cancelled = false;

        emit LoanCreated(
            lastLoanId,
            loan.borrower,
            loan.token,
            loan.amount,
            loan.nftCollection,
            loan.nftId,
            loan.duration,
            loan.interestRate,
            loan.collateralValue,
            loan.deadline
        );
    }

    /**
     * @notice Allows a borrower to cancel a loan
     * @dev Borrower can cancel a requested load if not yet accepted by any lender
     * @param _loanId The ID of the loan to cancel
     */
    function cancelLoan(uint256 _loanId) external nonReentrant {
        Loan storage loan = loans[_loanId];

        require(loan.borrower == msg.sender, "Lending: invalid loan id");
        require(loan.lender == address(0), "Lending: loan already accepted");
        require(!loan.cancelled, "Lending: loan already cancelled");

        loan.cancelled = true;

        emit LoanCancelled(_loanId);
    }

    /**
     * @notice Allows a lender to accept an existing loan
     * @dev Transfers the borrowed tokens from the lender to the borrower and sets the loan start time
     * @param _loanId The ID of the loan to accept
     */
    function acceptLoan(uint256 _loanId) external nonReentrant {
        Loan storage loan = loans[_loanId];

        require(loan.borrower != address(0) && loan.lender == address(0), "Lending: invalid loan id");
        require(!loan.cancelled, "Lending: loan cancelled");
        require(loan.deadline > block.timestamp, "Lending: loan acceptance deadline passed");

        loan.lender = msg.sender;
        loan.startTime = block.timestamp;

        IERC20(loan.token).safeTransferFrom(msg.sender, loan.borrower, loan.amount);
        IERC721(loan.nftCollection).safeTransferFrom(loan.borrower, address(this), loan.nftId);

        emit LoanAccepted(_loanId, loan.lender, loan.startTime);
    }

    /**
     * @notice Allows a borrower to repay a loan
     * @dev Transfers the repayment amount and additional fees to the lender and contract respectively
     * @param _loanId The ID of the loan being repaid
     */
    function repayLoan(uint256 _loanId) external nonReentrant {
        Loan storage loan = loans[_loanId];

        require(loan.borrower != address(0) && loan.lender != address(0), "Lending: invalid loan id");
        require(!loan.paid, "Lending: loan already paid");
        require(block.timestamp < loan.startTime + loan.duration + repayGracePeriod, "Lending: too late");

        uint256 totalPayable = loan.amount
            + getDebtWithPenalty(
                loan.amount, loan.interestRate + protocolFee, loan.duration, block.timestamp - loan.startTime
            ) + getOriginationFee(loan.amount);
        uint256 lenderPayable = loan.amount
            + getDebtWithPenalty(loan.amount, loan.interestRate, loan.duration, block.timestamp - loan.startTime);
        uint256 platformFee = totalPayable - lenderPayable;

        loan.paid = true;

        IERC20(loan.token).safeTransferFrom(msg.sender, loan.lender, lenderPayable);

        if (block.timestamp > loan.startTime + loan.duration) {
            platformFee += (totalPayable * repayGraceFee) / PRECISION;
        }

        IERC20(loan.token).safeTransferFrom(msg.sender, governanceTreasury, platformFee);

        IERC721(loan.nftCollection).safeTransferFrom(address(this), loan.borrower, loan.nftId);

        emit LoanRepayment(_loanId, lenderPayable + platformFee, platformFee);
    }

    /**
     * @notice Allows a lender to claim NFT from an overdue loan
     * @dev Transfers the collateralized NFT to the lender
     * @param _loanId The ID of the loan being liquidated
     */
    function claimNFT(uint256 _loanId) external nonReentrant {
        Loan storage loan = loans[_loanId];

        require(loan.borrower != address(0) && loan.lender != address(0), "Lending: invalid loan id");
        require(block.timestamp >= loan.startTime + loan.duration + repayGracePeriod, "Lending: too early");
        require(!loan.paid, "Lending: loan already paid");
        require(msg.sender == loan.lender, "Lending: only the lender can claim the nft");

        loan.paid = true;

        IERC721(loan.nftCollection).safeTransferFrom(address(this), msg.sender, loan.nftId);

        emit NFTClaimed(_loanId);
    }

    /**
     * @notice Allows an address to liquidate an overdue loan
     * @dev Transfers the repayment amount and additional fees to the lender and contract respectively
     * @param _loanId The ID of the loan being liquidated
     */
    function liquidateLoan(uint256 _loanId) external nonReentrant {
        Loan storage loan = loans[_loanId];

        require(loan.borrower != address(0) && loan.lender != address(0), "Lending: invalid loan id");
        require(block.timestamp >= loan.startTime + loan.duration + repayGracePeriod, "Lending: too early");
        require(!loan.paid, "Lending: loan already paid");

        uint256 totalPayable = loan.amount
            + getDebtWithPenalty(
                loan.amount, loan.interestRate + protocolFee, loan.duration, block.timestamp - loan.startTime
            ) + getOriginationFee(loan.amount) + getLiquidationFee(loan.amount);
        uint256 lenderPayable = loan.amount
            + getDebtWithPenalty(loan.amount, loan.interestRate, loan.duration, block.timestamp - loan.startTime);

        loan.paid = true;
        IERC20(loan.token).safeTransferFrom(msg.sender, loan.lender, lenderPayable);
        IERC20(loan.token).safeTransferFrom(msg.sender, governanceTreasury, totalPayable - lenderPayable);

        IERC721(loan.nftCollection).safeTransferFrom(address(this), msg.sender, loan.nftId);

        emit LoanLiquidated(_loanId, msg.sender, totalPayable, totalPayable - lenderPayable);
    }

    /**
     * @notice Updates the address of the price index contract used for valuations
     * @dev Only the contract owner can call this function
     * @param _priceIndex The address of the new price index contract
     */
    function setPriceIndex(address _priceIndex) external onlyOwner {
        _setPriceIndex(_priceIndex);

        emit PriceIndexSet(_priceIndex);
    }

    /**
     * @notice Updates the address of the governance treasury contract
     * @dev Only the contract owner can call this function
     * @param _governanceTreasury The address of the new governance treasury contract
     */
    function setGovernanceTreasury(address _governanceTreasury) external onlyOwner {
        _setGovernanceTreasury(_governanceTreasury);

        emit GovernanceTreasurySet(_governanceTreasury);
    }

    /**
     * @notice Sets the grace period for loan repayment
     * @dev Only the contract owner can call this function
     * @param _gracePeriod The new grace period for repayment
     */
    function setRepayGracePeriod(uint256 _gracePeriod) external onlyOwner {
        _setRepayGracePeriod(_gracePeriod);

        emit RepayGracePeriodSet(_gracePeriod);
    }

    /**
     * @notice Sets the grace fee for loan repayment
     * @dev Only the contract owner can call this function
     * @param _repayGraceFee The new grace fee for repayment
     */
    function setRepayGraceFee(uint256 _repayGraceFee) external onlyOwner {
        _setRepayGraceFee(_repayGraceFee);

        emit RepayGraceFeeSet(_repayGraceFee);
    }

    /**
     * @notice Sets the protocol fee
     * @dev Only the contract owner can call this function
     * @param _fee The new protocol fee
     */
    function setProtocolFee(uint256 _fee) external onlyOwner {
        _setProtocolFee(_fee);

        emit ProtocolFeeSet(_fee);
    }

    /**
     * @notice Sets the liquidation fee
     * @dev Only the contract owner can call this function
     * @param _fee The new liquidation fee
     */
    function setLiquidationFee(uint256 _fee) external onlyOwner {
        _setLiquidationFee(_fee);

        emit LiquidationFeeSet(_fee);
    }

    /**
     * @notice Sets the base origination fee
     * @dev Only the contract owner can call this function
     * @param _fee The new base origination fee
     */
    function setBaseOriginationFee(uint256 _fee) external onlyOwner {
        _setBaseOriginationFee(_fee);

        emit BaseOriginationFeeSet(_fee);
    }

    /**
     * @notice Allows the contract owner to whitelist tokens that can be borrowed
     * @dev Only the contract owner can call this function
     * @param _tokens Array of token addresses to be whitelisted
     */
    function setTokens(address[] calldata _tokens) external onlyOwner {
        for (uint256 i = 0; i < _tokens.length; i++) {
            allowedTokens[_tokens[i]] = true;
        }

        emit TokensSet(_tokens);
    }

    /**
     * @notice Allows the contract owner to remove tokens from the whitelist
     * @dev Only the contract owner can call this function
     * @param _tokens Array of token addresses to be removed from the whitelist
     */
    function unsetTokens(address[] calldata _tokens) external onlyOwner {
        for (uint256 i = 0; i < _tokens.length; i++) {
            allowedTokens[_tokens[i]] = false;
        }

        emit TokensUnset(_tokens);
    }

    /**
     * @notice Sets the available loan types by specifying the duration and interest rate
     * @dev Only the contract owner can call this function. The lengths of _durations and _interestRates arrays must be equal
     * @param _durations Array of loan durations
     * @param _interestRates Array of interest rates corresponding to each duration
     */
    function setLoanTypes(uint256[] calldata _durations, uint256[] calldata _interestRates) external onlyOwner {
        _setLoanTypes(_durations, _interestRates);

        emit LoanTypesSet(_durations, _interestRates);
    }

    /**
     * @notice Removes the specified loan types by duration
     * @dev Only the contract owner can call this function
     * @param _durations Array of loan durations to be removed
     */
    function unsetLoanTypes(uint256[] calldata _durations) external onlyOwner {
        for (uint256 i = 0; i < _durations.length; i++) {
            delete aprFromDuration[_durations[i]];
        }

        emit LoanTypesUnset(_durations);
    }

    /**
     * @notice Sets the fee reduction factor
     * @dev Only the contract owner can call this function
     * @param _factor The new fee reduction factor
     */
    function setFeeReductionFactor(uint256 _factor) external onlyOwner {
        feeReductionFactor = _factor;
    }

    /**
     * @notice Sets the originationFeeRanges array
     * @dev Only the contract owner can call this function
     * @param _originationFeeRanges The new originationFeeRanges array
     */
    function setRanges(uint256[] memory _originationFeeRanges) public onlyOwner {
        originationFeeRanges = _originationFeeRanges;
    }

    /**
     * @notice Retrieves the loan details for a specific loan ID
     * @dev Anyone can call this function
     * @param loanId The ID of the loan
     * @return loan The loan structure containing the details of the loan
     */
    function getLoan(uint256 loanId) external view returns (Loan memory loan) {
        return loans[loanId];
    }

    /**
     * @notice Calculates the debt amount with added penalty based on time and amount borrowed
     * @dev This is a utility function for internal use
     * @param _borrowedAmount The original amount borrowed
     * @param _apr The annual percentage rate
     * @param _loanDuration The duration of the loan
     * @param _repaymentDuration The time taken for repayment
     * @return uint256 The debt amount including penalties
     */
    function getDebtWithPenalty(
        uint256 _borrowedAmount,
        uint256 _apr,
        uint256 _loanDuration,
        uint256 _repaymentDuration
    ) public pure returns (uint256) {
        if (_repaymentDuration > _loanDuration) {
            _repaymentDuration = _loanDuration;
        }
        UD60x18 accruedDebt = convert((_borrowedAmount * _apr * _repaymentDuration) / SECONDS_IN_YEAR / 100 / PRECISION);
        UD60x18 penaltyFactor = convert(_loanDuration - _repaymentDuration).div(convert(_loanDuration));

        return convert(accruedDebt.add(accruedDebt.mul(penaltyFactor)));
    }

    /**
     * @notice Calculates the origination fee based on the loan amount
     * @dev This is a utility function for internal use
     * @param _amount The loan amount
     * @return uint256 The origination fee
     */
    function getOriginationFee(uint256 _amount) public view returns (uint256) {
        uint256 originationFee = baseOriginationFee;

        for (uint256 i = 0; i < originationFeeRanges.length; i++) {
            if (_amount < originationFeeRanges[i]) {
                break;
            } else {
                originationFee = (originationFee * PRECISION) / feeReductionFactor;
            }
        }
        return (_amount * originationFee) / 100 / PRECISION;
    }

    /**
     * @notice Calculates the liquidation fee based on the loan amount
     * @dev This is a utility function for internal use
     * @param _borrowedAmount The loan amount
     * @return uint256 The liquidation fee
     */
    function getLiquidationFee(uint256 _borrowedAmount) public view returns (uint256) {
        return (_borrowedAmount * liquidationFee) / PRECISION;
    }

    /**
     * @notice Sets the price index oracle for the contract
     * @dev It checks that the new price index address is not zero and supports the IPriceIndex interface
     * @param _priceIndex The new price index oracle address
     */
    function _setPriceIndex(address _priceIndex) internal {
        require(_priceIndex != address(0), "Lending: cannot be null address");
        require(
            _priceIndex.supportsInterface(type(IPriceIndex).interfaceId),
            "Lending: does not support IPriceIndex interface"
        );

        priceIndex = IPriceIndex(_priceIndex);
    }

    /**
     * @notice Sets the governance treasury address for the contract
     * @dev It checks that the new governance treasury address is not zero
     * @param _governanceTreasury The new governance treasury address
     */
    function _setGovernanceTreasury(address _governanceTreasury) internal {
        require(_governanceTreasury != address(0), "Lending: cannot be null address");

        governanceTreasury = _governanceTreasury;
    }

    /**
     * @notice Internal function to set the protocol fee
     * @param _fee The new protocol fee
     */
    function _setProtocolFee(uint256 _fee) internal {
        require(_fee <= MAX_PROTOCOL_FEE, "Lending: cannot be more than max");

        protocolFee = _fee;
    }

    /**
     * @notice Internal function to set the liquidation fee
     * @param _fee The new liquidation fee
     */
    function _setLiquidationFee(uint256 _fee) internal {
        require(_fee <= MAX_LIQUIDATION_FEE, "Lending: cannot be more than max");

        liquidationFee = _fee;
    }

    /**
     * @notice Internal function to set the repay grace period
     * @param _gracePeriod The new repay grace period
     */
    function _setRepayGracePeriod(uint256 _gracePeriod) internal {
        require(_gracePeriod >= MIN_GRACE_PERIOD, "Lending: cannot be less than min grace period");
        require(_gracePeriod < MAX_GRACE_PERIOD, "Lending: cannot be more than max grace period");

        repayGracePeriod = _gracePeriod;
    }

    /**
     * @notice Internal function to set the grace fee to be repaid
     * @param _repayGraceFee The new repay grace fee
     */
    function _setRepayGraceFee(uint256 _repayGraceFee) internal {
        require(_repayGraceFee <= MAX_REPAY_GRACE_FEE, "Lending: cannot be more than max");

        repayGraceFee = _repayGraceFee;
    }

    /**
     * @notice Internal function to set the available loan types by specifying the duration and interest rate
     * @param _durations Array of loan durations
     * @param _interestRates Array of interest rates corresponding to each duration
     */
    function _setLoanTypes(uint256[] memory _durations, uint256[] memory _interestRates) internal {
        require(_durations.length == _interestRates.length, "Lending: invalid input");
        for (uint256 i = 0; i < _durations.length; i++) {
            require(_interestRates[i] <= MAX_INTEREST_RATE, "Lending: cannot be more than max");
            aprFromDuration[_durations[i]] = _interestRates[i];
        }
    }

    /**
     * @notice Internal function to set the new base origination fee
     * @param _fee The new base origination fee
     */
    function _setBaseOriginationFee(uint256 _fee) internal {
        require(_fee <= MAX_BASE_ORIGINATION_FEE, "Lending: cannot be more than max");

        baseOriginationFee = _fee;
    }
}
