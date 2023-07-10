# Tokenized Strategy Periphery Contracts

This repo contains the option contracts that can be used for any Yearn V3 tokenized strategy to make strategy development even easier.

## How to start

### Requirements
First you will need to install [Foundry](https://book.getfoundry.sh/getting-started/installation).
NOTE: If you are on a windows machine it is recommended to use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)

### Fork this repository

    git clone --recursive https://github.com/user/tokenized-strategy-periphery

    cd tokenized-strategy-periphery

    yarn


### Set your environment Variables

Sign up for [Infura](https://infura.io/) and generate an API key and copy your RPC url. Store it in the `ETH_RPC_URL` environment variable.
NOTE: you can use other services.

Use .env file
  1. Make a copy of `.env.example`
  2. Add the values for `ETH_RPC_URL`, `ETHERSCAN_API_KEY` and other example vars
     NOTE: If you set up a global environment variable, that will take precedence.


### Build the project.

```sh
make build
```

Run tests
```sh
make test
```

## Swapper helper contracts

For strategies that need to swap reward tokens back into 'asset' a series of 'swapper' contracts have been pre-developed to make your preferred method as easy as possible to use.

For example if you want to use Uniswap V3 for swapping you can simply inherit the UniswapV3Swapper.sol, set the needed global variables for your specific strategy, then use the default syntax to swap any 'fromToken' to any 'toToken'.

EX:

    contract Strategy is UniswapV3Swapper, BaseTokenizedStrategy {
    
        ...
        
        ...
        
        function _harvestAndReport() exeternal override returns (uint256) {
            ... Claim rewards
            
            uint256 rewardBalance = rewardToken.balanceOf(address(this));
            _swapFrom(rewardToken, asset, rewardBalance, minAmountOut);
            
            ... reinvest and return the '_totalAssets'
        }
    }
    
NOTE: Its very important to read through all the comments in the swapper contract you use to assure all needed variables are set and any external setter functions that are needed are implemented.

## HealthCheck
Health Checks can be used by a strategy to assure automated reports are not unexpectedly reporting a loss or a extreme profit that a strategist doesn't expect.

It's important to note that the healthcheck does not stop losses from being reported, rather will require manual intervention from 'management' for out of range losses or gains.

A strategist simply has to inherit the `HealthCheck` contract in their strategy, set the profit and loss limit ratios with the needed setters, and then call `_executeHealthCheck(uint256)` with the expected return value as the parameter during `_harvestAndReport`.

EX:

    contract Strategy is HealthCheck, BaseTokenizedStrategy {
         ...
         
        function setProfitLimitRatio(
            uint256 _profitLimitRatio
        ) external onlyManagement {
            _setProfitLimitRatio(_profitLimitRatio);
        }

        function setLossLimitRatio(
            uint256 _lossLimitRatio
        ) external onlyManagement {
            _setLossLimitRatio(_lossLimitRatio);
        }

        function setDoHealthCheck(bool _doHealthCheck) external onlyManagement {
            doHealthCheck = _doHealthCheck;
        }
        
        ...
        
        function _harvestAndReport() internal override returns (uint256) {
            ...
            
            if (doHealthCheck) {
                require(_executeHealthCheck(_totalAssets), "!healthcheck");
            }
        }
    }
## Apr Oracle
For easy integration with on chain debt allocator's as well as off chain interfaces, strategist's can implement their own custom 'AprOracle'.

The goal of the APR oracle to is to return the expected current APY the strategy is expecting to be earning given some `debtChange`.


## Report Triggers
The default use of the Tokenized Strategies and V3 Vaults is for report cycles to be based off of the individual `maxProfitUnlockTime`. The triggers are an easy way for keepers to monitor the status of each strategy and know when `report` should be called on each.

However, if a strategist wants to implement a custom trigger for their strategy or vault you can use the simple `CustomTriggerBase` contracts to inherit the proper interface. Then return the expected APY repersented as 1e18 (1e17 == 10%).
