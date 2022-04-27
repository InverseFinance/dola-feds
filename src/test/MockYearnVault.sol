pragma solidity 0.8.13;

import "src/IERC20.sol";

contract MockYearnVault {
    address public token = 0x865377367054516e17014CcdED1e7d814EDC9ce4; //Dola Addr
    uint public depositLimit = 10_000_000 * 1 ether;
    uint public totalAssets = 0;
    uint8 public decimals = 18;
    uint loss = 0; //Loss on withdrawals
    uint price = 1 ether;
    uint max_bp = 10000;
    mapping(address => uint) balances;
    
    function deposit(uint _amount, address recipient) public returns(uint){
        IERC20(token).transferFrom(msg.sender, address(this), _amount);
        totalAssets += _amount;
        balances[recipient] += _amount;
        return _amount;
    }

    function withdraw(uint maxShares, address recipient, uint maxLoss) public returns(uint){
        require(balances[msg.sender] >= maxShares, "NOT ENOUGH SHARES");
        totalAssets -= maxShares * price / 1 ether;
        balances[msg.sender] -= maxShares;
        require(maxLoss > loss);
        uint amountOut = (maxShares * price / 1 ether) * (max_bp - loss) / max_bp;
        IERC20(token).transfer(recipient, amountOut);
        return amountOut;
    }

    function pricePerShare() public view returns(uint){
        return price;
    }

    function balanceOf(address holder) public view returns(uint){
        return balances[holder];
    }


}
