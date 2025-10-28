#!/bin/bash
# Genesis Generator for Lean Quickstart (Using PK's eth-beacon-genesis Tool)
# Uses PK's official docker image for leanchain genesis generation
# PR: https://github.com/ethpandaops/eth-beacon-genesis/pull/36

set -e

# ========================================
# Configuration
# ========================================
PK_DOCKER_IMAGE="ethpandaops/eth-beacon-genesis:pk910-leanchain"

# ========================================
# Usage and Help
# ========================================
show_usage() {
    cat << EOF
Usage: $0 <genesis-directory>

Generate genesis configuration files using PK's eth-beacon-genesis tool.
Generates: config.yaml, validators.yaml, nodes.yaml, genesis.json, genesis.ssz, and .key files

Arguments:
  genesis-directory    Path to the genesis directory containing:
                       - validator-config.yaml (with node configurations and individual counts)

Example:
  $0 local-devnet/genesis

Generated Files:
  - config.yaml        Auto-generated with GENESIS_TIME and VALIDATOR_COUNT
  - validators.yaml    Validator index assignments for each node
  - nodes.yaml         ENR (Ethereum Node Records) for peer discovery
  - genesis.json       Genesis state in JSON format
  - genesis.ssz        Genesis state in SSZ format
  - <node>.key         Private key files for each node

How It Works:
  1. Calculates GENESIS_TIME (current time + 30 seconds)
  2. Reads individual validator 'count' fields from validator-config.yaml
  3. Automatically sums them to calculate total VALIDATOR_COUNT
  4. Generates config.yaml from scratch with calculated values
  5. Runs PK's genesis generator with correct parameters

Note: config.yaml is a generated file - only edit validator-config.yaml

Requirements:
  - Docker (to run PK's eth-beacon-genesis tool)
  - yq: YAML processor (install: brew install yq)

Docker Image: ethpandaops/eth-beacon-genesis:pk910-leanchain
PR: https://github.com/ethpandaops/eth-beacon-genesis/pull/36

EOF
}

# Check for help flag
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    show_usage
    exit 0
fi

# ========================================
# Validate Arguments
# ========================================
if [ -z "$1" ]; then
    echo "❌ Error: Missing genesis directory argument"
    echo ""
    show_usage
    exit 1
fi

GENESIS_DIR="$1"
CONFIG_FILE="$GENESIS_DIR/config.yaml"
VALIDATOR_CONFIG_FILE="$GENESIS_DIR/validator-config.yaml"

# ========================================
# Check Dependencies
# ========================================
echo "🔍 Checking dependencies..."

# Check for yq
if ! command -v yq &> /dev/null; then
    echo "❌ Error: yq is required but not installed"
    echo "   Install on macOS: brew install yq"
    echo "   Install on Linux: https://github.com/mikefarah/yq#install"
    exit 1
fi
echo "  ✅ yq found: $(which yq)"

# Check for docker
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is required but not installed"
    echo "   Install from: https://docs.docker.com/get-docker/"
    exit 1
fi
echo "  ✅ docker found: $(which docker)"

# Check for hash-sig-cli tool
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HASHSIG_CLI_DIR="$SCRIPT_DIR/tools/hash-sig-cli"
HASH_SIG_CLI="$HASHSIG_CLI_DIR/target/release/hashsig"

# Check if hash-sig submodule exists
if [ ! -d "$HASHSIG_CLI_DIR" ]; then
    echo "❌ Error: hash-sig-cli submodule not found at $HASHSIG_CLI_DIR"
    echo "   Please initialize the submodule:"
    echo "   git submodule update --init --recursive"
    exit 1
fi

# Check if binary is built, build if needed
if [ ! -f "$HASH_SIG_CLI" ]; then
    echo "  ⚠️  hash-sig-cli binary not found"
    echo "  📦 Building hash-sig-cli from source..."
    
    (cd "$HASHSIG_CLI_DIR" && cargo build --release)
    
    if [ ! -f "$HASH_SIG_CLI" ]; then
        echo "  ❌ Error: Failed to build hash-sig-cli"
        echo "     Make sure Rust/Cargo is installed: https://rustup.rs/"
        exit 1
    fi
    
    echo "  ✅ Successfully built hash-sig-cli"
fi
echo "  ✅ hash-sig-cli found: $HASH_SIG_CLI"

echo ""

# ========================================
# Validate Input Files
# ========================================
echo "📂 Validating input files..."

if [ ! -d "$GENESIS_DIR" ]; then
    echo "❌ Error: Genesis directory not found: $GENESIS_DIR"
    exit 1
fi
echo "  ✅ Genesis directory: $GENESIS_DIR"

if [ ! -f "$VALIDATOR_CONFIG_FILE" ]; then
    echo "❌ Error: validator-config.yaml not found at $VALIDATOR_CONFIG_FILE"
    exit 1
fi
echo "  ✅ validator-config.yaml found"

echo ""

# ========================================
# Step 1: Generate Hash-Sig Validator Keys
# ========================================
echo "🔐 Step 1: Generating hash-sig validator keys..."

# Create hash-sig keys directory
HASH_SIG_KEYS_DIR="$GENESIS_DIR/hash-sig-keys"
mkdir -p "$HASH_SIG_KEYS_DIR"

# Count total validators from validator-config.yaml
VALIDATOR_COUNT=$(yq eval '.validators | length' "$VALIDATOR_CONFIG_FILE")

if [ -z "$VALIDATOR_COUNT" ] || [ "$VALIDATOR_COUNT" == "null" ] || [ "$VALIDATOR_COUNT" -eq 0 ]; then
    echo "❌ Error: Could not determine validator count from $VALIDATOR_CONFIG_FILE"
    exit 1
fi

echo "   Generating keys for $VALIDATOR_COUNT validators..."
echo "   Using scheme: SIGTopLevelTargetSumLifetime32Dim64Base8"
echo "   Key directory: $HASH_SIG_KEYS_DIR"
echo ""

# Generate hash-sig keys for all validators using genesis-specific command
# Scheme: SIGTopLevelTargetSumLifetime32Dim64Base8
# Active epochs: 2^18 (262,144)
# Total lifetime: 2^32 (4,294,967,296)
"$HASH_SIG_CLI" generate-for-genesis \
    --num-validators "$VALIDATOR_COUNT" \
    --log-num-active-epochs 18 \
    --output-dir "$HASH_SIG_KEYS_DIR"

if [ $? -ne 0 ]; then
    echo "   ❌ Failed to generate hash-sig keys"
    exit 1
fi

echo "   ✅ Generated keys for $VALIDATOR_COUNT validators"
echo "   ✅ Files created:"
for i in $(seq 0 $((VALIDATOR_COUNT - 1))); do
    echo "      - validator_${i}_pk.json and validator_${i}_sk.json"
done

echo ""
echo "   ✅ Hash-sig key generation complete!"
echo ""

# ========================================
# Step 2: Generate config.yaml
# ========================================
echo "🔧 Step 2: Generating config.yaml..."

# Calculate genesis time (30 seconds from now)
TIME_NOW="$(date +%s)"
GENESIS_TIME=$((TIME_NOW + 30))
echo "   Genesis time: $GENESIS_TIME"

# Sum all individual validator counts from validator-config.yaml
TOTAL_VALIDATORS=$(yq eval '.validators[].count' "$VALIDATOR_CONFIG_FILE" | awk '{sum+=$1} END {print sum}')

# Validate the sum
if [ -z "$TOTAL_VALIDATORS" ] || [ "$TOTAL_VALIDATORS" == "null" ]; then
    echo "❌ Error: Could not calculate total validator count from $VALIDATOR_CONFIG_FILE"
    echo "   Make sure each validator has a 'count' field defined"
    exit 1
fi

if [ "$TOTAL_VALIDATORS" -eq 0 ]; then
    echo "❌ Error: Total validator count is 0"
    echo "   Check that validator count values are greater than 0 in $VALIDATOR_CONFIG_FILE"
    exit 1
fi

# Display individual validator counts for transparency
echo "   Individual validator counts:"
while IFS= read -r line; do
    validator_name=$(echo "$line" | cut -d: -f1)
    validator_count=$(echo "$line" | cut -d: -f2 | xargs)
    echo "     - $validator_name: $validator_count"
done < <(yq eval '.validators[] | .name + ":" + (.count | tostring)' "$VALIDATOR_CONFIG_FILE")

echo "   Total validator count: $TOTAL_VALIDATORS"

# Generate config.yaml from scratch
cat > "$CONFIG_FILE" << EOF
# Genesis Settings
GENESIS_TIME: $GENESIS_TIME
# Validator Settings  
VALIDATOR_COUNT: $TOTAL_VALIDATORS
EOF

echo "   ✅ Generated config.yaml"
echo ""

# ========================================
# Step 3: Run PK's Genesis Generator
# ========================================
echo "🔧 Step 3: Running PK's eth-beacon-genesis tool..."
echo "   Docker image: $PK_DOCKER_IMAGE"
echo "   Command: leanchain"
echo ""

# Convert to absolute path for docker volume mount
GENESIS_DIR_ABS="$(cd "$GENESIS_DIR" && pwd)"
PARENT_DIR_ABS="$(cd "$GENESIS_DIR/.." && pwd)"

# Run PK's tool
# Note: PK's tool expects parent directory as mount point
echo "   Executing docker command..."

docker run --rm \
  -v "$PARENT_DIR_ABS:/data" \
  "$PK_DOCKER_IMAGE" \
  leanchain \
  --config "/data/genesis/config.yaml" \
  --mass-validators "/data/genesis/validator-config.yaml" \
  --state-output "/data/genesis/genesis.ssz" \
  --json-output "/data/genesis/genesis.json" \
  --nodes-output "/data/genesis/nodes.yaml" \
  --validators-output "/data/genesis/validators.yaml" \
  --config-output "/data/genesis/config.yaml"

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Error: PK's genesis generator failed!"
    exit 1
fi

echo ""
echo "   ✅ PK's tool completed successfully"
echo "   ✅ Generated: config.yaml (updated)"
echo "   ✅ Generated: validators.yaml"
echo "   ✅ Generated: nodes.yaml"
echo "   ✅ Generated: genesis.json"
echo "   ✅ Generated: genesis.ssz"
echo ""

# ========================================
# Step 4: Generate Private Key Files
# ========================================
echo "🔑 Step 4: Generating private key files..."

# Extract node names from validator-config.yaml
NODE_NAMES=($(yq eval '.validators[].name' "$VALIDATOR_CONFIG_FILE"))

if [ ${#NODE_NAMES[@]} -eq 0 ]; then
    echo "❌ Error: No validators found in $VALIDATOR_CONFIG_FILE"
    exit 1
fi

echo "  Nodes: ${NODE_NAMES[@]}"

for node in "${NODE_NAMES[@]}"; do
    privkey=$(yq eval ".validators[] | select(.name == \"$node\") | .privkey" "$VALIDATOR_CONFIG_FILE")
    
    if [ "$privkey" == "null" ] || [ -z "$privkey" ]; then
        echo "  ⚠️  Node $node: No privkey found, skipping"
        continue
    fi
    
    key_file="$GENESIS_DIR/$node.key"
    echo "$privkey" > "$key_file"
    echo "  ✅ Generated: $node.key"
done

echo ""

# ========================================
# Step 5: Validate Generated Files
# ========================================
echo "✓ Step 5: Validating generated files..."

required_files=("config.yaml" "validators.yaml" "nodes.yaml" "genesis.json" "genesis.ssz")
all_good=true

for file in "${required_files[@]}"; do
    if [ -f "$GENESIS_DIR/$file" ]; then
        echo "  ✅ $file exists"
    else
        echo "  ❌ $file is missing"
        all_good=false
    fi
done

if [ "$all_good" = false ]; then
    echo ""
    echo "❌ Some required files are missing!"
    exit 1
fi

echo ""

# ========================================
# Summary
# ========================================
echo "✅ Genesis generation complete!"
echo ""
echo "📄 Generated files:"
echo "   $GENESIS_DIR/config.yaml (updated)"
echo "   $GENESIS_DIR/validators.yaml"
echo "   $GENESIS_DIR/nodes.yaml"
echo "   $GENESIS_DIR/genesis.json"
echo "   $GENESIS_DIR/genesis.ssz"
for node in "${NODE_NAMES[@]}"; do
    if [ -f "$GENESIS_DIR/$node.key" ]; then
        echo "   $GENESIS_DIR/$node.key"
    fi
done
echo ""
echo "🔐 Hash-Sig Validator Keys:"
for i in $(seq 0 $((VALIDATOR_COUNT - 1))); do
    echo "   $GENESIS_DIR/hash-sig-keys/validator_${i}_pk.json"
    echo "   $GENESIS_DIR/hash-sig-keys/validator_${i}_sk.json"
done
echo ""
echo "🎯 Next steps:"
echo "   Run your nodes with: NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis"
echo ""
echo "ℹ️  Using PK's eth-beacon-genesis docker image:"
echo "   Image: $PK_DOCKER_IMAGE"
echo "   PR: https://github.com/ethpandaops/eth-beacon-genesis/pull/36"
echo ""
echo "ℹ️  Hash-sig keys generated with:"
echo "   Scheme: SIGTopLevelTargetSumLifetime32Dim64Base8"
echo "   Active Epochs: 2^18 (262,144)"
echo "   Total Lifetime: 2^32 (4,294,967,296)"
echo ""
