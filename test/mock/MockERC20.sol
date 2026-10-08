// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract MockERC20 is ERC20Mock {
    // name and symbol are unused: ERC20Mock fixes them. Decimals stay at the default 18,
    // which is what DSCEngine's price math assumes.
    constructor(string memory, string memory, address initialAccount, uint256 initialBalance) ERC20Mock() {
        _mint(initialAccount, initialBalance);
    }
}
