#!/bin/bash

# Load environment variables
source .env

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "   Sepolia Deployment Status"
echo "=========================================="
echo ""

echo -e "${BLUE}Core Contracts:${NC}"
echo "Market:  $MARKET_ADDRESS"
echo "Vault:   $VAULT_ADDRESS"
echo "Oracle:  $ORACLE_ADDRESS"
echo "IRM:     $IRM_ADDRESS"
echo ""

echo -e "${BLUE}Market Status:${NC}"
OWNER=$(cast call $MARKET_ADDRESS "owner()" --rpc-url https://rpc.sepolia.org)
echo "Owner: $OWNER"

TOTAL_BORROWS=$(cast call $MARKET_ADDRESS "totalBorrows()" --rpc-url https://rpc.sepolia.org)
echo "Total Borrows: $TOTAL_BORROWS"

echo ""
echo -e "${BLUE}Vault Status:${NC}"
TOTAL_ASSETS=$(cast call $VAULT_ADDRESS "totalAssets()" --rpc-url https://rpc.sepolia.org)
echo "Total Assets: $TOTAL_ASSETS"

TOTAL_SUPPLY=$(cast call $VAULT_ADDRESS "totalSupply()" --rpc-url https://rpc.sepolia.org)
echo "Total Supply (shares): $TOTAL_SUPPLY"

echo ""
echo -e "${BLUE}Interest Rate:${NC}"
BORROW_RATE=$(cast call $IRM_ADDRESS "getDynamicBorrowRate()" --rpc-url https://rpc.sepolia.org)
echo "Current Borrow Rate: $BORROW_RATE"

echo ""
echo -e "${BLUE}Market Parameters:${NC}"
PARAMS=$(cast call $MARKET_ADDRESS "marketParams()" --rpc-url https://rpc.sepolia.org)
echo "LLTV, Penalty, Fee: $PARAMS"

echo ""
echo -e "${GREEN}View on Etherscan:${NC}"
echo "https://sepolia.etherscan.io/address/$MARKET_ADDRESS"
echo ""
