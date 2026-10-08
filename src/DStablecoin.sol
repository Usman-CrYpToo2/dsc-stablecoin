// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DStablecoin is ERC20Burnable, Ownable {
    error DStablecoin_MustBeMoreThanZero();
    error DStablecoin_InsuffienctBalance();

    constructor() ERC20("DStablecoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 amount) public override onlyOwner {
        if (amount <= 0) {
            revert DStablecoin_MustBeMoreThanZero();
        }
        uint256 balance = balanceOf(msg.sender);
        if (amount > balance) {
            revert DStablecoin_InsuffienctBalance();
        }

        super.burn(amount);
    }

    function mint(address addr, uint256 amount) public onlyOwner returns (bool) {
        if (amount <= 0) {
            revert DStablecoin_MustBeMoreThanZero();
        }
        // Minting creates new tokens, so the minter's own balance does not matter.
        // (A balance check copied from burn() here made every mint revert.)
        _mint(addr, amount);
        return true;
    }

    function burnFrom(address, uint256) public pure override {
        revert("burnFrom is disabled");
    }
}
