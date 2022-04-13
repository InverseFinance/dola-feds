pragma solidity ^0.8.13;

import "IMetapool.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    function burn(uint amount) external;
}
interface IyVault is IERC20{
    //Getter functions for public vars
    function token() external view returns (IERC20);
    function depositLimit() external view returns (uint);  // Limit for totalAssets the Vault can hold
    function debtRatio() external view returns (uint);  // Debt ratio for the Vault across all strategies (in BPS, <= 10k)
    function totalDebt() external view returns (uint);  // Amount of tokens that all strategies have borrowed
    function lastReport() external view returns (uint);  // block.timestamp of last report
    function activation() external view returns (uint);  // block.timestamp of contract deployment
    function lockedProfit() external view returns (uint); // how much profit is locked and cant be withdrawn
    function lockedProfitDegradation() external view returns (uint); // rate per block of degradation. DEGRADATION_COEFFICIENT is 100% per block

    //Function interfaces
    function deposit(uint _amount,  address recipient) external returns (uint);
    function withdraw(uint maxShares, address recipient, uint maxLoss) external returns (uint);
    function maxAvailableShares() external returns (uint);
    function pricePerShare() external returns (uint);
}

contract YearnFed is CurvePoolAdapter{

    IyVault public vault;
    IERC20 public underlying;
    address public chair; // Fed Chair
    address public gov;
    uint public supply;

    event Expansion(uint amount);
    event Contraction(uint amount);

    constructor(IyVault vault_, address gov_) {
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
        //Alternatively to the below, can do
        /*
        if( amount > _maxDeposit()){
            amount = type(uint256).max;
        }
        As max uint always supplies the greatest amount possible in yearn vaults 
        */
        require(amount <= _maxDeposit(), "AMOUNT TOO BIG"); // can't deploy more than max
        uint shares = vault.deposit(amount, address(this));
        require(shares == 0, 'Supplying failed'); //Probably an unnecessary require
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
        return vault.depositLimit() - vault.totalDebt();
    }
    
}
