// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract MockERC20 is ERC20Mock {
      constructor(string memory name , string memory symbol, address initailAccount, uint256 initailBalance)   ERC20Mock() {
          name = name;
          symbol = symbol;
          _mint(initailAccount, initailBalance);
      }


    function decimals() public pure override returns (uint8) {
        return 8;
    }


}