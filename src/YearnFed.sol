pragma solidity ^0.8.13;

import "IYearnVault.sol";
import "IERC20.sol";

contract YearnFed{

    IYearnVault public vault;
    IERC20 public underlying;
    address public chair; // Fed Chair
    address public gov;
    uint public supply;

    event Expansion(uint amount);
    event Contraction(uint amount);

    constructor(IYearnVault vault_, address gov_) {
        vault = vault_;
        underlying = IERC20(vault_.token());
        underlying.approve(address(vault), type(uint256).max);
        chair = msg.sender;
        gov = gov_;
    }

    /**
    @notice Method for gov to change gov address
    */
    function changeGov(address newGov_) public {
        require(msg.sender == gov, "ONLY GOV");
        gov = newGov_;
    }

    /**
    @notice Method for gov to change the chair
    */
    function changeChair(address newChair_) public {
        require(msg.sender == gov, "ONLY GOV");
        chair = newChair_;
    }

    /**
    @notice Method for current chair of the Yearn FED to resign
    */
    function resign() public {
        require(msg.sender == chair, "ONLY CHAIR");
        chair = address(0);
    }

    /**
    @notice Deposits amount of underlying tokens into yEarn vault

    @param amount Amount of underlying token to deposit into yEarn vault
    */
    function expansion(uint amount) public {
        require(msg.sender == chair, "ONLY CHAIR");
        //Alternatively set amount to max uint if over deposit limit,
        //as that supplies greatest possible amount into vault
        /*
        if( amount > _maxDeposit()){
            amount = type(uint256).max;
        }
        */
        require(amount <= _maxDeposit(), "AMOUNT TOO BIG"); // can't deploy more than max
        uint shares = vault.deposit(amount, address(this));
        supply = supply + amount;
        emit Expansion(amount);
    }

    /**
    @notice Withdraws an amount of underlying token to be burnt, contracting DOLA supply
    
    @dev Be careful when setting maxLoss parameter. There will almost always be some loss,
    if the yEarn vault is forced to withdraw from underlying strategies. 
    For example, slippage + trading fees may be incurred when withdrawing from a Curve pool.
    
    On the other hand, setting the maxLoss too high, may cause you to be front run by MEV
    sandwhich bots, making sure your entire maxLoss is incurred.

    It's recommended to always broadcast withdrawl transactions(contraction & takeProfits)
    through a frontrun protected RPC like Flashbots RPC.
    
    @param amount The amount of underlying tokens to withdraw. Note that more tokens may
    be withdrawn than requested, as price is calculated by debts to strategies, but strategies
    may have outperformed price of underlying token.

    @param maxLoss the maximum allowed loss when withdrawing. 1 = 0.01%
    */
    function contraction(uint amount, uint maxLoss) public {
        require(msg.sender == chair, "ONLY CHAIR");
        uint underlyingWithdrawn = _withdrawAmountUnderlying(amount, maxLoss);
        require(underlyingWithdrawn <= supply, "AMOUNT TOO BIG"); // can't burn profits
        require(underlyingWithdrawn > 0, "NOTHING WITHDRAWN");
        underlying.burn(underlyingWithdrawn);
        supply = supply - amount;
        emit Contraction(underlyingWithdrawn);
    }

    /**
    @notice Withdraws the profit generated by yEarn vault

    @dev See dev note on Contraction method

    @param maxLoss the maximum allowed loss when withdrawing. 1 = 0.01%
    */
    function takeProfit(uint maxLoss) public {
        uint expectedBalance = vault.balanceOf(address(this))*vault.pricePerShare()/10**vault.decimals();
        if(expectedBalance > supply){
            uint expectedProfit = expectedBalance - supply;
            if(expectedProfit > 0) {
                uint actualProfit = _withdrawAmountUnderlying(expectedProfit, maxLoss);
                require(actualProfit > 0, "NO PROFIT");
                underlying.transfer(gov, actualProfit);
            }
        }
    }

    /**
    @notice calculates the amount of shares needed for withdrawing amount of underlying, and withdraws that amount.

    @dev See dev note on Contraction method

    @param amount The amount of underlying tokens to withdraw.

    @param maxLoss the maximum allowed loss when withdrawing. 1 = 0.01%
    */
    function _withdrawAmountUnderlying(uint amount, uint maxLoss) internal returns (uint){
        uint sharesNeeded = amount*10**vault.decimals()/vault.pricePerShare();
        return vault.withdraw(sharesNeeded, address(this), maxLoss);
    }

    /**
    @notice calculates the maximum possible deposit for the yearn vault
    */
    function _maxDeposit() view internal returns (uint) {
        // this can underflow as deposit limit can be set to 0 regardless of amount of assets in vault
        // return vault.depositLimit() - vault.totalDebt() - underlying.balanceOf(address(vault));
        uint depositLimit = vault.depositLimit();
        uint totalAssets = vault.totalAssets();
        if depositLimit > totalAssets {
            return depositLimit - totalAssets;
        }
        return 0;
    }
    
}
