#!/bin/bash
# Genesis Generator for Lean Quickstart
# Generates validators.yaml, nodes.yaml, and .key files from validator-config.yaml and config.yaml
# This tool eliminates the need for hardcoded genesis files

set -e

# ========================================
# Usage and Help
# ========================================
show_usage() {
    cat << EOF
Usage: $0 <genesis-directory>

Generate genesis configuration files (validators.yaml, nodes.yaml, and .key files)
from validator-config.yaml and config.yaml.

Arguments:
  genesis-directory    Path to the genesis directory containing:
                       - config.yaml (with GENESIS_TIME and VALIDATOR_COUNT)
                       - validator-config.yaml (with node configurations)

Example:
  $0 local-devnet/genesis

Generated Files:
  - validators.yaml    Validator index assignments for each node
  - nodes.yaml         ENR (Ethereum Node Records) for peer discovery
  - <node>.key         Private key files for each node

Requirements:
  - yq: YAML processor (install: brew install yq)
  - zeam-tools: For ENR generation (build: zig build tools -Doptimize=ReleaseFast)

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

# Check for zeam-tools
ZEAM_TOOLS=""

# Priority 1: Check for ZEAM_TOOLS_PATH environment variable
if [ -n "$ZEAM_TOOLS_PATH" ] && [ -f "$ZEAM_TOOLS_PATH" ]; then
    ZEAM_TOOLS="$ZEAM_TOOLS_PATH"
    echo "  ✅ zeam-tools found (via ZEAM_TOOLS_PATH): $ZEAM_TOOLS"
else
    # Priority 2: Try relative path from script location (for lean-quickstart inside zeam repo)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ZEAM_TOOLS_RELATIVE="$SCRIPT_DIR/../zig-out/bin/zeam-tools"
    
    if [ -f "$ZEAM_TOOLS_RELATIVE" ]; then
        ZEAM_TOOLS="$ZEAM_TOOLS_RELATIVE"
        echo "  ✅ zeam-tools found (relative): $ZEAM_TOOLS"
    # Priority 3: Check common zeam installation location
    elif [ -f "/Users/mercynaps/zeam/zig-out/bin/zeam-tools" ]; then
        ZEAM_TOOLS="/Users/mercynaps/zeam/zig-out/bin/zeam-tools"
        echo "  ✅ zeam-tools found (common location): $ZEAM_TOOLS"
    # Priority 4: Try to find in PATH
    elif command -v zeam-tools &> /dev/null; then
        ZEAM_TOOLS=$(which zeam-tools)
        echo "  ✅ zeam-tools found in PATH: $ZEAM_TOOLS"
    else
        echo "❌ Error: zeam-tools is required for ENR generation"
        echo "   Build it with: cd <zeam-repo> && zig build tools -Doptimize=ReleaseFast"
        echo "   Or set ZEAM_TOOLS_PATH environment variable"
        echo "   Or add zeam-tools to your PATH"
        exit 1
    fi
fi

# Check for openssl (optional, for key generation)
if ! command -v openssl &> /dev/null; then
    echo "  ⚠️  Warning: openssl not found (needed only for new key generation)"
fi

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

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Error: config.yaml not found at $CONFIG_FILE"
    exit 1
fi
echo "  ✅ config.yaml found"

if [ ! -f "$VALIDATOR_CONFIG_FILE" ]; then
    echo "❌ Error: validator-config.yaml not found at $VALIDATOR_CONFIG_FILE"
    exit 1
fi
echo "  ✅ validator-config.yaml found"

echo ""

# ========================================
# Read Configuration
# ========================================
echo "📊 Reading configuration..."

# Read validator count from config.yaml
VALIDATOR_COUNT=$(yq eval '.VALIDATOR_COUNT' "$CONFIG_FILE")
if [ "$VALIDATOR_COUNT" == "null" ] || [ -z "$VALIDATOR_COUNT" ]; then
    echo "❌ Error: VALIDATOR_COUNT not found in $CONFIG_FILE"
    exit 1
fi
echo "  Total validators: $VALIDATOR_COUNT"

# Read shuffle strategy (default: roundrobin)
SHUFFLE=$(yq eval '.shuffle' "$VALIDATOR_CONFIG_FILE")
if [ "$SHUFFLE" == "null" ] || [ -z "$SHUFFLE" ]; then
    SHUFFLE="roundrobin"
fi
echo "  Shuffle strategy: $SHUFFLE"

# Extract all node names from validator-config.yaml
NODE_NAMES=($(yq eval '.validators[].name' "$VALIDATOR_CONFIG_FILE"))
NODE_COUNT=${#NODE_NAMES[@]}

if [ $NODE_COUNT -eq 0 ]; then
    echo "❌ Error: No validators found in $VALIDATOR_CONFIG_FILE"
    exit 1
fi

echo "  Node count: $NODE_COUNT"
echo "  Nodes: ${NODE_NAMES[@]}"

# Validate that each node has required fields
for node in "${NODE_NAMES[@]}"; do
    # Check for privkey
    privkey=$(yq eval ".validators[] | select(.name == \"$node\") | .privkey" "$VALIDATOR_CONFIG_FILE")
    if [ "$privkey" == "null" ] || [ -z "$privkey" ]; then
        echo "  ⚠️  Node $node: missing privkey (will need to generate)"
    fi
    
    # Check for enrFields
    ip=$(yq eval ".validators[] | select(.name == \"$node\") | .enrFields.ip" "$VALIDATOR_CONFIG_FILE")
    quic=$(yq eval ".validators[] | select(.name == \"$node\") | .enrFields.quic" "$VALIDATOR_CONFIG_FILE")
    
    if [ "$ip" == "null" ] || [ -z "$ip" ]; then
        echo "❌ Error: Node $node: missing enrFields.ip in $VALIDATOR_CONFIG_FILE"
        exit 1
    fi
    
    if [ "$quic" == "null" ] || [ -z "$quic" ]; then
        echo "❌ Error: Node $node: missing enrFields.quic in $VALIDATOR_CONFIG_FILE"
        exit 1
    fi
done

echo ""

# ========================================
# Generate Private Key Files
# ========================================
echo "🔑 Generating private key files..."

for node in "${NODE_NAMES[@]}"; do
    privkey=$(yq eval ".validators[] | select(.name == \"$node\") | .privkey" "$VALIDATOR_CONFIG_FILE")
    
    if [ "$privkey" == "null" ] || [ -z "$privkey" ]; then
        echo "  ⚠️  Node $node: No privkey found, cannot generate key file"
        echo "     Please add privkey to validator-config.yaml for node: $node"
        exit 1
    fi
    
    key_file="$GENESIS_DIR/$node.key"
    echo "$privkey" > "$key_file"
    echo "  ✅ Generated: $node.key"
done

echo ""

# ========================================
# Generate ENRs and nodes.yaml
# ========================================
echo "🌐 Generating ENRs and nodes.yaml..."

NODES_YAML="$GENESIS_DIR/nodes.yaml"
> "$NODES_YAML"  # Clear/create file

for node in "${NODE_NAMES[@]}"; do
    privkey=$(yq eval ".validators[] | select(.name == \"$node\") | .privkey" "$VALIDATOR_CONFIG_FILE")
    ip=$(yq eval ".validators[] | select(.name == \"$node\") | .enrFields.ip" "$VALIDATOR_CONFIG_FILE")
    quic=$(yq eval ".validators[] | select(.name == \"$node\") | .enrFields.quic" "$VALIDATOR_CONFIG_FILE")
    
    # Generate ENR using zeam-tools
    enr=$("$ZEAM_TOOLS" enrgen --sk "$privkey" --ip "$ip" --quic "$quic" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$enr" ]; then
        echo "  ❌ Failed to generate ENR for $node"
        exit 1
    fi
    
    echo "- $enr" >> "$NODES_YAML"
    echo "  ✅ $node: ${enr:0:50}..."
done

echo ""

# ========================================
# Generate validators.yaml
# ========================================
echo "👥 Generating validators.yaml..."

VALIDATORS_YAML="$GENESIS_DIR/validators.yaml"
> "$VALIDATORS_YAML"  # Clear/create file

if [ "$SHUFFLE" == "roundrobin" ]; then
    # Round-robin distribution: distribute validators evenly across nodes
    for node_idx in "${!NODE_NAMES[@]}"; do
        node="${NODE_NAMES[$node_idx]}"
        
        # Get the count for this node (how many validator indices it should get)
        node_count=$(yq eval ".validators[] | select(.name == \"$node\") | .count" "$VALIDATOR_CONFIG_FILE")
        if [ "$node_count" == "null" ] || [ -z "$node_count" ]; then
            node_count=1  # Default to 1 if not specified
        fi
        
        echo "$node:" >> "$VALIDATORS_YAML"
        
        # Calculate validators for this node
        validators_assigned=0
        val_idx=$node_idx
        
        while [ $validators_assigned -lt $node_count ] && [ $val_idx -lt $VALIDATOR_COUNT ]; do
            echo "  - $val_idx" >> "$VALIDATORS_YAML"
            validators_assigned=$((validators_assigned + 1))
            val_idx=$((val_idx + NODE_COUNT))
        done
        
        # Build display array
        validators_for_node=()
        val_idx=$node_idx
        validators_assigned=0
        while [ $validators_assigned -lt $node_count ] && [ $val_idx -lt $VALIDATOR_COUNT ]; do
            validators_for_node+=($val_idx)
            validators_assigned=$((validators_assigned + 1))
            val_idx=$((val_idx + NODE_COUNT))
        done
        
        echo "  ✅ $node: [${validators_for_node[@]}]"
    done
else
    echo "  ❌ Error: Unknown shuffle strategy: $SHUFFLE"
    echo "     Currently only 'roundrobin' is supported"
    exit 1
fi

echo ""

# ========================================
# Summary
# ========================================
echo "✅ Genesis generation complete!"
echo ""
echo "📄 Generated files:"
echo "   $NODES_YAML"
echo "   $VALIDATORS_YAML"
for node in "${NODE_NAMES[@]}"; do
    echo "   $GENESIS_DIR/$node.key"
done
echo ""
echo "🎯 Next steps:"
echo "   Run your nodes with: NETWORK_DIR=local-devnet ./spin-node.sh --node all --freshStart"
echo ""

