# Tokenized Strategy Periphery Contract

This repo contains the option contracts that can be used for any Yearn V3 tokenized strategy to make strategy development even easier.

## Apr Oracle
add stuff

## Swapper helper contracts
say stuff

## HealthCheck
more stuff

## Report Triggers
Good stuff

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
