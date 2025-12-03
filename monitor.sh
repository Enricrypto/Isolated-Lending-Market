#!/bin/bash

# Load environment variables
source .env

# Use Alchemy RPC
RPC_URL="https://eth-sepolia.g.alchemy.com/v2/rBgXMI1K1DTe3cHIew_X3VV1EcpMlzsp"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "   Sepolia Deployment Status"
echo "=========================================="
echo ""

echo -e "${BLUE}📍 Core Contracts:${NC}"
echo "Market:  $MARKET_ADDRESS"
echo "Vault:   $VAULT_ADDRESS"
echo "Oracle:  $ORACLE_ADDRESS"
echo "IRM:     $IRM_ADDRESS"
echo ""

echo -e "${BLUE}💰 Market Status:${NC}"
OWNER=$(cast call $MARKET_ADDRESS "owner()" --rpc-url $RPC_URL 2>/dev/null)
echo "Owner: $OWNER"

TOTAL_BORROWS=$(cast call $MARKET_ADDRESS "totalBorrows()" --rpc-url $RPC_URL 2>/dev/null)
if [ "$TOTAL_BORROWS" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
    BORROWS_WEI=$(cast --to-dec $TOTAL_BORROWS)
    BORROWS_ETHER=$(cast --from-wei $BORROWS_WEI)
    echo "Total Borrows: $BORROWS_ETHER (${BORROWS_WEI} wei)"
else
    echo "Total Borrows: 0 (no active loans)"
fi

echo ""
echo -e "${BLUE}🏦 Vault Status:${NC}"
TOTAL_ASSETS=$(cast call $VAULT_ADDRESS "totalAssets()" --rpc-url $RPC_URL 2>/dev/null)
if [ "$TOTAL_ASSETS" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
    ASSETS_WEI=$(cast --to-dec $TOTAL_ASSETS)
    # USDC has 6 decimals, so divide by 1e6
    ASSETS_USDC=$(echo "scale=6; $ASSETS_WEI / 1000000" | bc)
    echo "Total Assets: $ASSETS_USDC USDC (${ASSETS_WEI} units)"
else
    echo "Total Assets: 0 USDC (vault is empty)"
fi

TOTAL_SUPPLY=$(cast call $VAULT_ADDRESS "totalSupply()" --rpc-url $RPC_URL 2>/dev/null)
SUPPLY_WEI=$(cast --to-dec $TOTAL_SUPPLY)
SUPPLY_SHARES=$(echo "scale=6; $SUPPLY_WEI / 1000000000000000000" | bc)
echo "Total Supply: $SUPPLY_SHARES shares (${SUPPLY_WEI} wei)"

echo ""
echo -e "${BLUE}�� Interest Rate:${NC}"
BORROW_RATE=$(cast call $IRM_ADDRESS "getDynamicBorrowRate()" --rpc-url $RPC_URL 2>/dev/null)
RATE_WEI=$(cast --to-dec $BORROW_RATE)
# Convert from 18 decimals to percentage (divide by 1e16 for %)
RATE_PCT=$(echo "scale=2; $RATE_WEI / 10000000000000000" | bc)
echo "Current Borrow Rate: ${RATE_PCT}% APR"

echo ""
echo -e "${BLUE}⚙️  Market Parameters:${NC}"
# LLTV (85%)
echo "LLTV: 85%"
echo "Liquidation Penalty: 5%"
echo "Protocol Fee: 10%"

echo ""
echo -e "${BLUE}🔐 Security Check:${NC}"
ORACLE_OWNER=$(cast call $ORACLE_ADDRESS "owner()" --rpc-url $RPC_URL 2>/dev/null)
# Remove leading zeros and 0x, compare addresses
ORACLE_OWNER_CLEAN=$(echo $ORACLE_OWNER | sed 's/0x0*/0x/')
MARKET_CLEAN=$(echo $MARKET_ADDRESS | tr '[:upper:]' '[:lower:]')
ORACLE_OWNER_LOWER=$(echo $ORACLE_OWNER_CLEAN | tr '[:upper:]' '[:lower:]')

if [ "$ORACLE_OWNER_LOWER" == "$MARKET_CLEAN" ]; then
    echo -e "${GREEN}✓ Oracle owned by Market${NC}"
else
    echo -e "${RED}✗ Oracle NOT owned by Market${NC}"
    echo "  Oracle owner: $ORACLE_OWNER_CLEAN"
    echo "  Expected:     $MARKET_ADDRESS"
fi

echo ""
echo -e "${GREEN}🔗 View on Etherscan:${NC}"
echo "Market:  https://sepolia.etherscan.io/address/$MARKET_ADDRESS"
echo "Vault:   https://sepolia.etherscan.io/address/$VAULT_ADDRESS"
echo "Oracle:  https://sepolia.etherscan.io/address/$ORACLE_ADDRESS"
echo "IRM:     https://sepolia.etherscan.io/address/$IRM_ADDRESS"
echo ""
echo -e "${YELLOW}💡 Next Steps:${NC}"
echo "1. Mint test tokens and deposit to vault"
echo "2. Test borrow/repay cycle"
echo "3. Monitor for 1-2 weeks"
echo ""
