// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    error Oracle_priceStale();
    uint256 private constant TIMEOUT = 3 hours;
    function stalePriceCheck(AggregatorV3Interface pricefeed) public view returns(uint80, int256, uint256, uint256, uint80) {
         (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound ) = pricefeed.latestRoundData();
        
        uint256 secondsSince = block.timestamp - updatedAt;

        if(secondsSince > TIMEOUT) {
             revert Oracle_priceStale();
        }

        return(roundId, answer, startedAt, updatedAt, answeredInRound);

    }
}