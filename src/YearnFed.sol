pragma solidity ^0.8.13;

import "src/IYearnVault.sol";
import "src/IERC20.sol";

contract YearnFed{

    IYearnVault public vault;
    IERC20 public underlying;
    address public chair; // Fed Chair
    address public gov;
    uint public supply;
    uint public maxLossBpContraction;
    uint public maxLossBpTakeProfit;

    event Expansion(uint amount);
    event Contraction(uint amount);

    /**
    @param vault_ Address of the yearnV2 vault the Fed will deploy capital to
    @param gov_ Address of governance. This address will receive profits generated, and may perform privilegede actions
    @param maxLossBpContraction_ Maximum allowed loss in vault share value, when contracting supply of underlying.
     Denominated in basis points. 1 = 0.01%
    @param maxLossBpTakeProfit_ Maximum allowed loss in vault share value, when taking profit from the vault.
     Denominated in basis points. 1 = 0.01%
    */
    constructor(IYearnVault vault_, address gov_, uint maxLossBpContraction_, uint maxLossBpTakeProfit_) {
        vault = vault_;
        underlying = IERC20(vault_.token());
        underlying.approve(address(vault), type(uint256).max);
        chair = msg.sender;
        maxLossBpContraction = maxLossBpContraction_;
        maxLossBpTakeProfit = maxLossBpTakeProfit_;
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
    @notice Method for governance to set max loss in basis points, when withdraing from yearn vault
    @param newMaxLossBpContraction new maximally allowed loss in Bp 1 = 0.01%
    */
    function setMaxLossBpContraction(uint newMaxLossBpContraction) public {
        require(msg.sender == gov, "ONLY GOV");
        require(newMaxLossBpContraction <= 10000, "MAXLOSS OVER 100%");
        maxLossBpContraction = newMaxLossBpContraction;
    }

    /**
    @notice Method for governance to set max loss in basis points, when taking profit from yearn vault
    @param newMaxLossBpTakeProfit new maximally allowed loss in Bp 1 = 0.01%
    */
    function setMaxLossBpTakeProfit(uint newMaxLossBpTakeProfit) public {
        require(msg.sender == gov, "ONLY GOV");
        require(newMaxLossBpTakeProfit <= 10000, "MAXLOSS OVER 100%");
        maxLossBpTakeProfit = newMaxLossBpTakeProfit;
    }

    /**
    @notice Method for withdrawing any token from the contract to governance. Should only be used in emergencies.
    @param token Address of token contract to withdraw to gov
    @param amount Amount of tokens to withdraw
    */
    function emergencyWithdraw(address token, uint amount) public{
        require(msg.sender == gov, "ONLY GOV");
        require(token != address(vault), "FORBIDDEN TOKEN");
        IERC20(token).transfer(gov, amount);
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
        underlying.mint(address(this), amount);
        uint shares = vault.deposit(amount, address(this));
        require(shares > 0);
        supply = supply + amount;
        emit Expansion(amount);
    }

    /**
    @notice Withdraws an amount of underlying token to be burnt, contracting supply
    
    @dev Its recommended to always broadcast withdrawl transactions(contraction & takeProfits)
    through a frontrun protected RPC like Flashbots RPC.
    
    @param amountUnderlying The amount of underlying tokens to withdraw. Note that more tokens may
    be withdrawn than requested, as price is calculated by debts to strategies, but strategies
    may have outperformed price of underlying token.
    If underlyingWithdrawn exceeds supply, the remainder is returned as profits
    */
    function contraction(uint amountUnderlying) public {
        require(msg.sender == chair, "ONLY CHAIR");
        uint underlyingWithdrawn = _withdrawAmountUnderlying(amountUnderlying, maxLossBpContraction);
        _contraction(underlyingWithdrawn);
    }
    /**
    @notice Withdraws every vault share, leaving no dust.
    @dev If the vault shares are worth less than the underlying supplied,
    then it may result in some bad debt being left in the vault.
    This can happen due to transaction fees or slippage incurred by withdrawing from the vault
    */
    function contractAll() public {
        require(msg.sender == chair, "ONLY CHAIR");
        uint underlyingWithdrawn = vault.withdraw(vault.balanceOf(address(this)), address(this), maxLossBpContraction);
        _contraction(underlyingWithdrawn);
    }

    /**
    @notice Burns the amount of underlyingWithdrawn.
    If the amount exceeds supply, the surplus is sent to governance as profit
    @param underlyingWithdrawn Amount of underlying that has successfully been withdrawn
    */
    function _contraction(uint underlyingWithdrawn) internal {
        require(underlyingWithdrawn > 0, "NOTHING WITHDRAWN");
        if(underlyingWithdrawn > supply){
            underlying.burn(supply);
            underlying.transfer(gov, underlyingWithdrawn-supply);
            emit Contraction(supply);
            supply = 0;
        } else {
            underlying.burn(underlyingWithdrawn);
            supply = supply - underlyingWithdrawn;
            emit Contraction(underlyingWithdrawn);
        }   
    }

    /**
    @notice Withdraws the profit generated by yEarn vault

    @dev See dev note on Contraction method
    */
    function takeProfit() public {
        uint expectedBalance = vault.balanceOf(address(this))*vault.pricePerShare()/10**vault.decimals();
        if(expectedBalance > supply){
            uint expectedProfit = expectedBalance - supply;
            if(expectedProfit > 0) {
                uint actualProfit = _withdrawAmountUnderlying(expectedProfit, maxLossBpTakeProfit);
                require(actualProfit > 0, "NO PROFIT");
                underlying.transfer(gov, actualProfit);
            }
        }
    }

    /**
    @notice calculates the amount of shares needed for withdrawing amount of underlying, and withdraws that amount.

    @dev See dev note on Contraction method

    @param amount The amount of underlying tokens to withdraw.
    @param maxLossBp The maximally acceptable loss in basis points. 1 = 0.01%
    */
    function _withdrawAmountUnderlying(uint amount, uint maxLossBp) internal returns (uint){
        uint sharesNeeded = amount*10**vault.decimals()/vault.pricePerShare();
        return vault.withdraw(sharesNeeded, address(this), maxLossBp);
    }

    /**
    @notice calculates the maximum possible deposit for the yearn vault
    */
    function _maxDeposit() view internal returns (uint) {
        if(vault.totalAssets() > vault.depositLimit()){
            return 0;
        }
        return vault.depositLimit() - vault.totalAssets();
    }
}
