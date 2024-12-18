// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

interface IPriceOracle {
    error PriceOracle_BaseUnsupported();
    error PriceOracle_QuoteUnsupported();
    error PriceOracle_Overflow();
    error PriceOracle_NoPath();

    /// @notice Returns the name of the price oracle
    function name() external view returns (string memory);

    /**
     * @notice Returns the quote for a given amount of base asset in quote asset
     * @param amount Amount of base asset
     * @param base The address of the base asset
     * @param quote The address of the quote asset
     * @return out The quote amount in quote asset
     */
    function getQuote(uint256 amount, address base, address quote) external view returns (uint256 out);

    /**
     * @notice Returns the bid and ask quotes for a given amount of base asset in quote asset
     * @param amount Amount of base assetI
     * @param base The address of the base asset
     * @param quote The address of the quote asset
     * @return bidOut The bid quote amount in quote asset
     * @return askOut The ask quote amount in quote asset
     */
    function getQuotes(uint256 amount, address base, address quote)
        external
        view
        returns (uint256 bidOut, uint256 askOut);
}
