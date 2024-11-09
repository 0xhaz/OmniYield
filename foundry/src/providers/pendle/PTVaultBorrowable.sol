// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {IEVC} from "src/abstracts/VaultBase.sol";
import {OmniBaseVault} from "src/vaults/OmniBaseVault.sol";
import {IStandardizedYield} from "@pendle/core/contracts/interfaces/IStandardizedYield.sol";
import {IPYieldToken} from "@pendle/core/contracts/interfaces/IPYieldToken.sol";
import {IPPrincipalToken} from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";
import {IPMarketV3} from "@pendle/core/contracts/interfaces/IPMarketV3.sol";
import {PYIndexLib} from "@pendle/core/contracts/core/StandardizedYield/PYIndex.sol";
import {LpUsdOracle} from "src/providers/pendle/LpUsdOracle.sol";
import {PendleLpOracleLib} from "@pendle/core/contracts/oracles/PendleLpOracleLib.sol";
import {IOmniYieldCollateralVault} from "src/interfaces/IOmniYieldCollateralVault.sol";
import {IERC20, ERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MarketApproxPtOutLib, ApproxParams} from "@pendle/core/contracts/router/base/ActionBase.sol";

/**
 * @title PTVaultBorrowable
 * @notice Implements the vault containing the borrowable asset
 */
contract PTVaultBorrowable is OmniBaseVault {
    error PTVaultBorrowable__CollateralExpired();
    error PTVaultBorrowable__ZeroCollateral();
    error PTVaultBorrowable__InvalidTerm();
    error PTVaultBorrowable__WrongToken();
    error PTVaultBorrowable__MaxLoanExceeded();
    error PTVaultBorrowable__RepayFailed();
    error PTVaultBorrowable__LiquidationImpaired();
    error PTVaultBorrowable__SlippageTooHigh();
    error PTVaultBorrowable__LoanTermNotExpired();
    error PTVaultBorrowable__SnapshotNotTaken();
    error PTVaultBorrowable__InvalidCollateralFactor();
    error PTVaultBorrowable__NotEnoughCollateralPledged();
    error PTVaultBorrowable__ViolatorStatusCheckDeferred();
    error PTVaultBorrowable__ControllerDisabled();

    using Math for uint256;
    using MarketApproxPtOutLib for *;
    using PendleLpOracleLib for IPMarketV3;
    using PYIndexLib for IPYieldToken;

    mapping(address owner => uint256 owedAmount) private _owed;
    mapping(address => mapping(uint256 => UserInfo)) private userInfo;
    mapping(address => uint256) public loans;
    mapping(address => uint256) public pledgedCollateral;

    uint256 internal _totalBorrowed;
    uint256 internal _totalPledgedCollateral;
    uint256 private constant COLLATERAL_FACTOR_SCALE = 1_000_000;
    uint256 private constant RATE_PRECISION = 1_000_000; // 0.01 basis points
    uint256 public constant LTV = 990_000; // 99% LTV
    uint256 private constant MARKET_EPS = 10 ** 15; // 0.1%
    uint256 private constant FACTOR_SCALE = 1e18;
    uint256 private constant MIN_SHARES_AMOUNT = 1;

    LpUsdOracle public oracle;
    IPPrincipalToken public collateral;
    IOmniYieldCollateralVault public collateralVault;
    address public market;
    bytes internal constant EMPTY_BYTES = abi.encode();

    event Borrow(address indexed borrower, address indexed receiver, uint256 assets);
    event Repay(address indexed borrower, address indexed receiver, uint256 assets);

    struct UserInfo {
        uint256 collateralAmount;
        uint256 repurchasePrice;
        uint256 termExpires;
    }

    constructor(
        IEVC _evc,
        IERC20 _asset,
        address _collateralVault,
        address _collateralAsset,
        address _oracle,
        address _market
    ) OmniBaseVault(_evc, _asset, "Omni Borrowable Vault", "OBV") {
        collateralVault = IOmniYieldCollateralVault(_collateralVault);
        collateral = IPPrincipalToken(_collateralAsset);
        oracle = LpUsdOracle(_oracle);
        market = _market;
    }

    function borrowLoan(uint256 assets, uint256 term, address receiver)
        external
        callThroughEVC
        nonReentrant
        onlyEVCAccountOwner
    {
        address msgSender = _msgSenderForBorrow();

        createVaultSnapshot();
        if (collateral.isExpired()) revert PTVaultBorrowable__CollateralExpired();
        if (assets == 0) revert PTVaultBorrowable__ZeroCollateral();
        if (term < 1 days) revert PTVaultBorrowable__InvalidTerm();

        uint256 loanAmount = assets + getTermFeeForAmount(assets, term);
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        uint256 collateralValueRequired = loanAmount * RATE_PRECISION / LTV;
        uint256 collateralNominalRequired = collateralValueRequired * FACTOR_SCALE / (oracle.getLpPrice());
        _executeLoan(msgSender, collateralNominalRequired, loanAmount, term);

        emit Borrow(msgSender, receiver, loanAmount);
        _totalAssets -= assets;
        requireAccountAndVaultStatusCheck(msgSender);
    }

    function renewLoan(address _borrower, uint256 _loanIndex, uint256 _partialPayoff, uint256 _newTerm)
        external
        callThroughEVC
        nonReentrant
    {
        address msgSender = _msgSenderForBorrow();

        createVaultSnapshot();
        if (collateral.isExpired()) revert PTVaultBorrowable__CollateralExpired();
        if (_newTerm < 1 days) revert PTVaultBorrowable__InvalidTerm();

        UserInfo storage info = userInfo[_borrower][_loanIndex];
        SafeERC20.safeTransferFrom(IERC20(asset()), msgSender, address(this), _partialPayoff);
        _totalAssets += _partialPayoff; // cancel out utilization before renewing loan

        uint256 termFee = getTermFeeForAmount(info.repurchasePrice - _partialPayoff, _newTerm);
        uint256 newRepurchasePrice = (info.repurchasePrice - _partialPayoff) + termFee;

        // previous loan is repaid, new loan is taken
        loans[_borrower] -= 1;
        pledgedCollateral[_borrower] -= info.collateralAmount;

        _decreaseOwed(_borrower, info.repurchasePrice);

        // new loan is taken
        _executeLoan(_borrower, info.collateralAmount, newRepurchasePrice, _newTerm);

        requireAccountAndVaultStatusCheck(msgSender);
    }

    function tradeBaseForLP(uint256 _LPAmount, uint256 _term, uint256 _mintLpOut, address receiver)
        public
        callThroughEVC
        nonReentrant
        onlyEVCAccountOwner
    {
        address msgSender = _msgSenderForBorrow();

        // sanity check: the violator must be under control of the EVC
        if (!isControllerEnabled(receiver, address(this))) revert PTVaultBorrowable__ControllerDisabled();

        createVaultSnapshot();

        if (_term < 1 days) revert PTVaultBorrowable__InvalidTerm();
        if (collateral.isExpired()) revert PTVaultBorrowable__CollateralExpired();

        uint256 markPrice = oracle.getLpPrice();
        uint256 lpMarketValue = markPrice * _LPAmount / FACTOR_SCALE;

        uint256 netLpOut = swapExactTokenForLp(lpMarketValue, _LPAmount, _mintLpOut, asset());

        // the maximum loan value for the collateral purchased
        uint256 maxLoan = maxLoanValue(netLpOut * markPrice / FACTOR_SCALE);
        // the maximum borrowable agains the collateral for the term
        uint256 borrowAmount = getMaxBorrow(netLpOut * markPrice / FACTOR_SCALE, _term);

        // write a repurchase agreement for maxLoan at term agains netPtOut
        _executeLoan(msgSender, netLpOut, maxLoan, _term);
        // user myst pay the transactions total minus the total amount they were able to borrow against the collateral
        SafeERC20.safeTransferFrom(IERC20(asset()), msgSender, address(this), lpMarketValue - borrowAmount);

        // move collateral into vault on behalf of the user
        IERC20(collateral).approve(address(collateralVault), netLpOut);
        collateralVault.deposit(netLpOut, receiver);

        // asset in the pool reduced by borrowAmount
        _totalAssets -= borrowAmount;

        // do account checks
        requireAccountAndVaultStatusCheck(msgSender);
    }

    function repurchaseAndSellPt(address _borrower, address _receiver, uint256 _loanIndex)
        external
        callThroughEVC
        nonReentrant
        onlyEVCAccountOwner
    {
        address msgSender = _msgSenderForBorrow();

        createVaultSnapshot();

        UserInfo storage info = userInfo[_borrower][_loanIndex];

        liquidateCollateralShares(address(collateralVault), _borrower, address(this), info.collateralAmount);
        forgiveAccountStatusCheck(_borrower);

        collateralVault.withdraw(info.collateralAmount, address(this), address(this));
        uint256 saleAmount = _sellLpForToken(info.collateralAmount, address(asset()));

        if (saleAmount > info.repurchasePrice) {
            uint256 profit = saleAmount - info.repurchasePrice;
            if (profit > 0) {
                SafeERC20.safeTransfer(IERC20(asset()), _receiver, profit);
            }

            _decreaseOwed(_borrower, info.repurchasePrice);
            _totalAssets += info.repurchasePrice;

            pledgedCollateral[_borrower] -= info.collateralAmount;
            _totalPledgedCollateral -= info.collateralAmount;

            loans[_borrower] -= 1;

            delete userInfo[_borrower][_loanIndex];
        } else {
            revert PTVaultBorrowable__LiquidationImpaired();
        }

        requireAccountAndVaultStatusCheck(msgSender);
    }

    function liquidate(address _borrower, uint256 _loanIndex) external callThroughEVC nonReentrant {
        address msgSender = _msgSenderForBorrow();

        UserInfo storage info = userInfo[_borrower][_loanIndex];
        if (info.termExpires > block.timestamp) revert PTVaultBorrowable__LoanTermNotExpired();

        // due to later violator's account check forgiveness,
        // the violator's account must be fully settled when liquidating
        if (isAccountStatusCheckDeferred(_borrower)) revert PTVaultBorrowable__ViolatorStatusCheckDeferred();

        // sanity check: the violator must be under control of the EVC
        if (!isControllerEnabled(_borrower, address(this))) revert PTVaultBorrowable__ControllerDisabled();

        createVaultSnapshot();

        // liquidator pays off the loan
        SafeERC20.safeTransferFrom(ERC20(asset()), msgSender, address(this), info.repurchasePrice);

        // PT collateral shares transferred to the liquidator
        liquidateCollateralShares(address(collateralVault), _borrower, msgSender, info.collateralAmount);
        forgiveAccountStatusCheck(_borrower);

        _totalPledgedCollateral -= info.collateralAmount;
        _totalAssets += info.repurchasePrice;
        pledgedCollateral[_borrower] -= info.collateralAmount;
        _decreaseOwed(_borrower, info.repurchasePrice);
        loans[_borrower] -= 1;

        delete userInfo[_borrower][_loanIndex];

        requireAccountAndVaultStatusCheck(msgSender);
    }

    /// @notice Returns the current rate for borrowing
    function getRate(uint256 _amountBorrowed, uint256 totalAssets, uint256 totalBorrowed)
        public
        view
        returns (uint256)
    {
        if (totalAssets == 0) return 677; // 6.77 basis points (0.0677%)
        uint256 utilization1 = totalBorrowed * FACTOR_SCALE / totalAssets + totalBorrowed;
        uint256 utilization2 = (_amountBorrowed + totalBorrowed) * FACTOR_SCALE / (totalAssets - totalBorrowed);
        if (utilization2 < 0.8 ether) {
            return (((20 * utilization1 / 100 ether) + 677) + ((20 * utilization2 / 100 ether) + 677)) / 2;
        } else {
            uint256 amountBelow = ((0.8 ether * (totalAssets + totalBorrowed)) - totalBorrowed) / FACTOR_SCALE;
            uint256 amountAbove = _amountBorrowed - amountBelow;
            uint256 rateBelow = (20 * utilization1 / 100 ether) + 677;
            uint256 rateAbove = (20 * utilization2 / 100 ether) + 677;
            return (rateBelow * amountBelow + rateAbove * amountAbove) / _amountBorrowed;
        }
    }

    function getTermFeeForAmount(uint256 _amount, uint256 _term) public view returns (uint256) {
        return _amount * ((getRate(_amount, _totalAssets, _totalBorrowed) * _term)) / (RATE_PRECISION * 1 days);
    }

    function maxLoanValue(uint256 _collateralValue) public view returns (uint256) {
        return _collateralValue * LTV / RATE_PRECISION;
    }

    function getMaxBorrow(uint256 _collateralValue, uint256 _term) public view returns (uint256) {
        return maxLoanValue(_collateralValue)
            * ((1 days * RATE_PRECISION) - (getRate(maxLoanValue(_collateralValue), _totalAssets, _totalBorrowed) * _term))
            / (RATE_PRECISION * 1 days);
    }

    function getTermFee(uint256 _collateralValue, uint256 _term) public view returns (uint256) {
        return maxLoanValue(_collateralValue) - getMaxBorrow(_collateralValue, _term);
    }

    function swapExactTokenForLp(uint256 netTokenIn, uint256 _LpAmount, uint256 _mintLpOut, address tokenIn)
        internal
        returns (uint256 netLpOut)
    {
        (IStandardizedYield SY, IPPrincipalToken PT, IPYieldToken YT) = IPMarketV3(market).readTokens();

        IERC20(asset()).approve(address(SY), netTokenIn);
        uint256 netSyOut = SY.deposit(address(this), tokenIn, netTokenIn, MIN_SHARES_AMOUNT);
        SY.approve(address(market), netSyOut);
        (netLpOut,) = _SwapExactSyForPt(address(this), netSyOut, _LpAmount, _mintLpOut);
    }

    function repurchase(address receiver, uint256 _loanIndex) external callThroughEVC nonReentrant {
        address msgSender = _msgSenderForBorrow();

        if (!isControllerEnabled(receiver, address(this))) revert PTVaultBorrowable__ControllerDisabled();

        UserInfo storage info = userInfo[receiver][_loanIndex];

        createVaultSnapshot();
        SafeERC20.safeTransferFrom(IERC20(asset()), msgSender, address(this), info.repurchasePrice);

        _totalAssets += info.repurchasePrice;
        _totalPledgedCollateral -= info.collateralAmount;
        pledgedCollateral[msgSender] -= info.collateralAmount;

        _decreaseOwed(receiver, info.repurchasePrice);

        delete userInfo[receiver][_loanIndex];
        loans[receiver] -= 1;

        emit Repay(msgSender, receiver, info.repurchasePrice);
        requireAccountAndVaultStatusCheck(msgSender);
    }

    function _sellPtForToken(uint256 netPtIn, address tokenOut) internal returns (uint256 netTokenOut) {
        (IStandardizedYield SY, IPPrincipalToken PT, IPYieldToken YT) = IPMarketV3(market).readTokens();

        uint256 netSyOut;
        uint256 fee;
        if (PT.isExpired()) {
            PT.transfer(address(YT), netPtIn);
            netSyOut = YT.redeemPY(address(SY));
        } else {
            PT.transfer(address(market), netPtIn);
            (netSyOut, fee) = IPMarketV3(market).swapExactPtForSy(
                address(SY), // better gas optimization to transfer SY directly to itself and burn
                netPtIn,
                EMPTY_BYTES
            );
        }

        netTokenOut = SY.redeem(address(this), netSyOut, tokenOut, MIN_SHARES_AMOUNT, true);
    }

    function doCreateVaultSnapshot() internal virtual override returns (bytes memory) {
        return abi.encode(_totalAssets, _totalBorrowed, _totalPledgedCollateral);
    }

    function _executeLoan(address debtor, uint256 collateralPledged, uint256 loanAmount, uint256 term) internal {
        _increasedOwed(debtor, loanAmount);

        pledgedCollateral[debtor] += collateralPledged;
        loans[debtor] += 1;

        userInfo[debtor][loans[debtor]] = UserInfo(collateralPledged, loanAmount, block.timestamp + term);
        _totalPledgedCollateral += collateralPledged;
    }

    function doCheckVaultStatus(bytes memory oldSnapshot) internal virtual override {
        if (oldSnapshot.length == 0) revert PTVaultBorrowable__SnapshotNotTaken();

        (uint256 initialAssets, uint256 initialBorrowed, uint256 initialPledged) =
            abi.decode(oldSnapshot, (uint256, uint256, uint256));
        uint256 finalAssets = _totalAssets;
        uint256 finalBorrowed = _totalBorrowed;
        uint256 finalPledged = _totalPledgedCollateral;
        if (finalBorrowed > finalPledged) revert PTVaultBorrowable__NotEnoughCollateralPledged();
    }

    function setEps(uint256 _eps) external onlyOwner {
        MARKET_EPS = _eps;
    }

    function doCheckAccountStatus(address account, address[] calldata collaterals) internal view virtual override {
        uint256 _collateral = IERC20(collateral).balanceOf(account);
        uint256 maxLoan = maxLoanValue(collateral * oracle.getLpPrice() / FACTOR_SCALE);

        if (maxLoan < _owed[account]) revert PTVaultBorrowable__MaxLoanExceeded();
        if (_collateral < pledgedCollateral[account]) revert PTVaultBorrowable__LiquidationImpaired();
    }

    function _decreaseOwed(address account, uint256 assets) internal virtual {
        _owed[account] = _debtOf(account) - assets;
        _totalBorrowed -= assets;
    }

    function _increaseOwed(address account, uint256 assets) internal virtual {
        _owed[account] = _debtOf(account) + assets;
        _totalBorrowed += assets;
    }

    function _debtOf(address account) internal view virtual returns (uint256) {
        return _owed[account];
    }

    function getUserLoan(address user, uint256 loanIndex) external view returns (uint256 _collateral, uint256 term) {
        UserInfo memory info = userInfo[user][loanIndex];
        return (info.collateralAmount, info.repurchasePrice, info.termExpires);
    }

    // ===========================
    /// @notice Converts assets to shares.
    /// @dev That function is manipulable in its current form as it uses exact values. Considering that other vaults may
    /// rely on it, for a production vault, a manipulation resistant mechanism should be implemented.
    /// @dev Considering that this function may be relied on by controller vaults, it's read-only re-entrancy protected.
    /// @param assets The assets to convert.
    /// @return The converted shares.
    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        uint256 underlyingValue = totalAssets() + _totalBorrowed;
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), underlyingValue + 1, rounding);
    }
}
