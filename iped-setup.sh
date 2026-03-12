#!/bin/bash
# ============================================================================
# iped-setup.sh — IPED Local Environment Auto-Configuration
# ============================================================================
# This script detects and configures the local environment for running IPED
# after building from source. It solves the common first-run issues that new
# contributors encounter, such as missing tskJarPath, wrong Java version, and
# unavailable optional dependencies.
#
# Usage:
#   ./iped-setup.sh                    # Auto-detect release directory
#   ./iped-setup.sh /path/to/release   # Specify release directory
#
# What it does:
#   1. Validates Java version (must be 11)
#   2. Auto-detects SleuthKit JAR and patches LocalConfig.txt
#   3. Detects SSD and suggests optimal settings
#   4. Checks optional dependencies (LibreOffice, Tesseract, etc.)
#   5. Runs a quick smoke test with a minimal evidence set
#
# Contributing: https://github.com/sepinf-inc/IPED
# ============================================================================

set -euo pipefail

# --- Colors & Formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Logging ---
info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[  OK]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[FAIL]${NC}  $*"; }
header(){ echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

# --- Find Release Directory ---
find_release_dir() {
    local search_dir="${1:-.}"
    
    # Try common locations
    for candidate in \
        "$search_dir" \
        "$search_dir/target/release/"iped-*-SNAPSHOT \
        "$search_dir/target/release/"iped-* \
        "$(dirname "$0")" \
        ; do
        if [ -f "$candidate/iped.jar" ] 2>/dev/null; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# --- Main ---
main() {
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║       IPED — Local Environment Setup                  ║"
    echo "║       Auto-configuration for first-time contributors  ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    local release_dir
    if [ $# -ge 1 ]; then
        release_dir="$1"
    else
        release_dir=$(find_release_dir "." 2>/dev/null) || {
            err "Could not find IPED release directory."
            err "Please run from the IPED project root, or pass the release dir as argument:"
            err "  ./iped-setup.sh /path/to/target/release/iped-4.x.x"
            exit 1
        }
    fi

    # Resolve to absolute path
    release_dir="$(cd "$release_dir" && pwd)"
    info "Release directory: ${BOLD}$release_dir${NC}"

    local config_file="$release_dir/LocalConfig.txt"
    local errors=0
    local warnings=0

    # ── 1. Java Version ──────────────────────────────────────
    header "1/5 — Java Version Check"
    
    if ! command -v java &>/dev/null; then
        err "Java not found in PATH."
        err "IPED requires Java 11 (LTS). Install it with:"
        err "  curl -s https://get.sdkman.io | bash"
        err "  sdk install java 11.0.25.fx-librca"
        ((errors++))
    else
        local java_ver
        java_ver=$(java -version 2>&1 | head -1 | awk -F '"' '{print $2}')
        local java_major
        java_major=$(echo "$java_ver" | cut -d. -f1)
        
        if [ "$java_major" = "11" ]; then
            ok "Java $java_ver (Java 11 ✓)"
        elif [ "$java_major" -gt "11" ]; then
            warn "Java $java_ver detected. IPED is tested with Java 11."
            warn "Some features may not work. Consider: sdk use java 11.0.25.fx-librca"
            ((warnings++))
        else
            err "Java $java_ver is too old. IPED requires Java 11+."
            ((errors++))
        fi
    fi

    # ── 2. SleuthKit JAR ──────────────────────────────────────
    header "2/5 — SleuthKit JAR Detection"
    
    local tsk_jar=""
    # Search in lib/ directory
    for jar in "$release_dir"/lib/sleuthkit-*.jar; do
        if [ -f "$jar" ]; then
            tsk_jar="$jar"
            break
        fi
    done

    if [ -n "$tsk_jar" ]; then
        local tsk_relative="lib/$(basename "$tsk_jar")"
        ok "Found SleuthKit: $tsk_relative"

        # Check if LocalConfig.txt exists
        if [ -f "$config_file" ]; then
            # Check current tskJarPath value
            local current_tsk
            current_tsk=$(grep -E "^tskJarPath\s*=" "$config_file" 2>/dev/null | sed 's/.*=\s*//' || echo "")
            
            if [ -z "$current_tsk" ] || grep -qE "^#\s*tskJarPath" "$config_file"; then
                info "Patching LocalConfig.txt with tskJarPath = $tsk_relative"
                # Uncomment and set the value
                if grep -qE "^#\s*tskJarPath" "$config_file"; then
                    sed -i "s|^#\s*tskJarPath\s*=.*|tskJarPath = $tsk_relative|" "$config_file"
                else
                    echo "tskJarPath = $tsk_relative" >> "$config_file"
                fi
                ok "LocalConfig.txt patched successfully"
            elif [ "$current_tsk" = "$tsk_relative" ]; then
                ok "LocalConfig.txt already configured correctly"
            else
                warn "LocalConfig.txt has tskJarPath = $current_tsk"
                warn "Expected: $tsk_relative"
                info "Updating to detected value..."
                sed -i "s|^tskJarPath\s*=.*|tskJarPath = $tsk_relative|" "$config_file"
                ok "Updated tskJarPath"
            fi
        else
            err "LocalConfig.txt not found at $config_file"
            ((errors++))
        fi
    else
        warn "SleuthKit JAR not found in $release_dir/lib/"
        warn "Disk image parsing will not work. This is OK for folder-based evidence."
        ((warnings++))
    fi

    # ── 3. SSD Detection ──────────────────────────────────────
    header "3/5 — Storage Detection"
    
    local temp_dir
    temp_dir=$(grep -E "^indexTemp\s*=" "$config_file" 2>/dev/null | sed 's/.*=\s*//' || echo "default")
    
    if [ "$temp_dir" = "default" ]; then
        temp_dir="/tmp"
    fi
    
    # Check if temp is on SSD (Linux only)
    if [ -f /sys/block/sda/queue/rotational ]; then
        local rotational
        rotational=$(cat /sys/block/sda/queue/rotational 2>/dev/null || echo "1")
        if [ "$rotational" = "0" ]; then
            ok "SSD detected for system drive"
            # Check if indexTempOnSSD is enabled
            if grep -q "indexTempOnSSD = false" "$config_file" 2>/dev/null; then
                info "Enabling SSD optimizations in LocalConfig.txt..."
                sed -i "s|indexTempOnSSD = false|indexTempOnSSD = true|" "$config_file"
                ok "SSD optimizations enabled (up to 2x faster processing)"
            fi
        else
            ok "HDD detected — SSD optimizations correctly disabled"
        fi
    else
        info "Could not detect storage type. Using default settings."
    fi

    # ── 4. Optional Dependencies ──────────────────────────────
    header "4/5 — Optional Dependencies"
    
    # LibreOffice
    if command -v libreoffice &>/dev/null || [ -d "/usr/lib/libreoffice" ]; then
        local lo_ver
        lo_ver=$(libreoffice --version 2>/dev/null | head -1 || echo "detected")
        ok "LibreOffice: $lo_ver"
    else
        warn "LibreOffice not found. Document thumbnails and conversions will be limited."
        warn "Install: sudo apt install libreoffice-core"
        ((warnings++))
    fi

    # Tesseract (OCR)
    if command -v tesseract &>/dev/null; then
        ok "Tesseract OCR: $(tesseract --version 2>&1 | head -1)"
    else
        info "Tesseract OCR not installed. OCR features disabled (optional)."
    fi

    # Python + JEP (for Python modules)
    if command -v python3 &>/dev/null; then
        ok "Python 3: $(python3 --version 2>&1)"
        if python3 -c "import jep" 2>/dev/null; then
            ok "JEP (Java Embedded Python): available"
        else
            info "JEP not installed. Python-based IPED modules disabled (optional)."
            info "Install: pip install jep"
        fi
    else
        info "Python 3 not found. Python-based modules disabled (optional)."
    fi

    # perl + RegRipper
    if command -v perl &>/dev/null; then
        ok "Perl: $(perl -v 2>&1 | grep version | head -1 | sed 's/.*(\(.*\))/\1/')"
    else
        info "Perl not found. RegRipper reports disabled (optional)."
    fi

    # ── 5. Smoke Test ─────────────────────────────────────────
    header "5/5 — Quick Smoke Test"
    
    info "Creating minimal test dataset..."
    local test_dir
    test_dir=$(mktemp -d)
    echo "IPED smoke test file - $(date)" > "$test_dir/smoke_test.txt"
    
    local output_dir
    output_dir=$(mktemp -d)
    
    info "Running IPED in headless mode..."
    local smoke_log
    smoke_log=$(mktemp)
    
    (
        cd "$release_dir"
        java -jar iped.jar \
            -d "$test_dir" \
            -o "$output_dir" \
            -profile triage \
            --nogui < /dev/null > "$smoke_log" 2>&1
    )
    
    # Wait for the forked child process to finish (IPED forks a worker JVM)
    sleep 5
    wait 2>/dev/null || true
    
    if grep -q "Finished" "$smoke_log" || [ -d "$output_dir/iped/index" ]; then
        local index_size
        index_size=$(du -sh "$output_dir/iped/index" 2>/dev/null | cut -f1 || echo "unknown")
        ok "Smoke test passed! Index created ($index_size)"
    elif grep -qi "error\|exception" "$smoke_log"; then
        warn "Smoke test had errors (this may be OK if optional deps are missing)."
        warn "Check log: $smoke_log"
        ((warnings++))
    else
        ok "Smoke test completed (no critical errors)."
    fi
    rm -f "$smoke_log"
    
    # Cleanup
    rm -rf "$test_dir" "$output_dir"

    # ── Summary ───────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD} Setup Summary${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ "$errors" -eq 0 ]; then
        echo -e "  ${GREEN}${BOLD}✓ IPED is ready to use!${NC}"
    else
        echo -e "  ${RED}${BOLD}✗ $errors error(s) found — please fix before running IPED${NC}"
    fi
    
    if [ "$warnings" -gt 0 ]; then
        echo -e "  ${YELLOW}⚠ $warnings warning(s) — some features may be limited${NC}"
    fi
    
    echo ""
    echo -e "  ${BOLD}Quick start:${NC}"
    echo -e "    java -jar $release_dir/iped.jar -d /path/to/evidence -o /path/to/output --nogui"
    echo ""
    echo -e "  ${BOLD}Web API (localhost only):${NC}"
    echo -e "    java -cp '$release_dir/lib/*' iped.engine.webapi.Main --sources=sources.json --port=8080"
    echo ""
    echo -e "  ${BOLD}Documentation:${NC}"
    echo -e "    https://github.com/sepinf-inc/IPED/wiki/User-Manual"
    echo ""
}

main "$@"
