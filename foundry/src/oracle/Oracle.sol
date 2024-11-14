// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OApp, MessagingFee, Origin} from "LayerZero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/OApp.sol";
import {MessagingReceipt} from "LayerZero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/OAppSender.sol";

contract Oracle is OApp {
    uint256[] public pythPrices;
    uint256[] public flarePrices;
    uint256[] public chroniclePrices;

    uint256 public immutable TOLERANCE = 5;

    constructor(address _endpoint, address _delegate) OApp(_endpoint, _delegate) Ownable(_delegate) {}

    function getPrice(uint256 index) external view returns (uint256) {
        require(
            index < pythPrices.length && index < flarePrices.length && index < chroniclePrices.length,
            "Index out of bounds"
        );

        uint256[] memory prices = new uint256[](3);
        prices[0] = pythPrices[index];
        prices[1] = flarePrices[index];
        prices[2] = chroniclePrices[index];

        for (uint256 i = 0; i < prices.length - 1; i++) {
            for (uint256 j = i; j < prices.length; j++) {
                if (prices[i] > prices[j]) {
                    uint256 temp = prices[i];
                    prices[i] = prices[j];
                    prices[j] = temp;
                }
            }
        }

        return prices[1];
    }

    function setPythPrice(uint256[] memory prices) public {
        pythPrices = prices;
    }

    function setFlarePrice(uint256[] memory prices) public {
        flarePrices = prices;
    }

    function setChroniclePrice(uint256[] memory prices) public {
        chroniclePrices = prices;
    }

    function _lzReceive(
        Origin calldata, /*_origin*/
        bytes32, /*_guid*/
        bytes calldata payload,
        address, /*_executor*/
        bytes calldata /*_extraData*/
    ) internal override {
        (uint256 oracleId, uint256[] memory prices) = abi.decode(payload, (uint256, uint256[]));

        if (oracleId == 0) {
            setPythPrice(prices);
        } else if (oracleId == 1) {
            setFlarePrice(prices);
        } else if (oracleId == 2) {
            setChroniclePrice(prices);
        }
    }
}
