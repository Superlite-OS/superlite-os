#!/bin/bash
# ============================================================================
# SuperLite OS — Build Validation
# Validates Alpine-native project structure
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo -e "  \033[0;32m✓\033[0m $*"; }
fail() { FAIL=$((FAIL + 1)); echo -e "  \033[0;31m✗\033[0m $*"; }

echo ""
echo "═══════════════════════════════════════════════"
echo "SuperLite OS — Build Validation"
echo "═══════════════════════════════════════════════"
echo ""

# ── Core build files ───────────────────────────────────────────────────────
echo "Core Build Files:"
if [ -f "${TOP_DIR}/build.sh" ]; then pass "build.sh"; else fail "build.sh missing"; fi
if [ -x "${TOP_DIR}/build.sh" ]; then pass "build.sh is executable"; else fail "build.sh not executable"; fi
if [ -f "${TOP_DIR}/Makefile" ]; then pass "Makefile"; else fail "Makefile missing"; fi
if [ -f "${TOP_DIR}/aports/scripts/mkimg.superlite.sh" ]; then pass "mkimg.superlite.sh (profile)"; else fail "mkimg.superlite.sh missing"; fi
if [ -f "${TOP_DIR}/aports/scripts/genapkovl-superlite.sh" ]; then pass "genapkovl-superlite.sh (overlay)"; else fail "genapkovl-superlite.sh missing"; fi

echo ""
echo "Package References:"
if [ -f "${TOP_DIR}/alpine/configs/packages.list" ]; then pass "packages.list"; else fail "packages.list missing"; fi
if [ -f "${TOP_DIR}/alpine/configs/repositories" ]; then pass "repositories"; else fail "repositories missing"; fi

echo ""
echo "Dotfiles:"
if [ -d "${TOP_DIR}/dotfiles/.config/labwc" ]; then pass "LabWC config"; else fail "LabWC config missing"; fi
if [ -d "${TOP_DIR}/dotfiles/.config/waybar" ]; then pass "Waybar config"; else fail "Waybar config missing"; fi
if [ -d "${TOP_DIR}/dotfiles/.config/foot" ]; then pass "Foot config"; else fail "Foot config missing"; fi
if [ -d "${TOP_DIR}/dotfiles/.config/mako" ]; then pass "Mako config"; else fail "Mako config missing"; fi
if [ -d "${TOP_DIR}/dotfiles/.config/tofi" ]; then pass "Tofi config"; else fail "Tofi config missing"; fi
if [ -d "${TOP_DIR}/dotfiles/.config/gtk-3.0" ]; then pass "GTK3 settings"; else fail "GTK3 settings missing"; fi
if [ -d "${TOP_DIR}/dotfiles/.config/gtk-4.0" ]; then pass "GTK4 settings"; else fail "GTK4 settings missing"; fi

echo ""
echo "Themes & Fonts:"
if [ -d "${TOP_DIR}/dotfiles/usr/share/themes/WhiteSur-Light" ]; then pass "WhiteSur-Light theme"; else fail "WhiteSur-Light missing"; fi
if [ -d "${TOP_DIR}/dotfiles/usr/share/icons/Phosphor" ]; then pass "Phosphor icons"; else fail "Phosphor icons missing"; fi
if [ -d "${TOP_DIR}/dotfiles/usr/share/fonts/ohsnap" ]; then pass "OhSnap font"; else fail "OhSnap font missing"; fi

echo ""
echo "QEMU Scripts:"
if [ -f "${TOP_DIR}/run-qemu.sh" ]; then pass "run-qemu.sh"; else fail "run-qemu.sh missing"; fi
if [ -x "${TOP_DIR}/run-qemu.sh" ]; then pass "run-qemu.sh is executable"; else fail "run-qemu.sh not executable"; fi
if [ -f "${TOP_DIR}/run-qemu-simple.sh" ]; then pass "run-qemu-simple.sh"; else fail "run-qemu-simple.sh missing"; fi
if [ -x "${TOP_DIR}/run-qemu-simple.sh" ]; then pass "run-qemu-simple.sh is executable"; else fail "run-qemu-simple.sh not executable"; fi
if [ -f "${TOP_DIR}/run-qemu-debug.sh" ]; then pass "run-qemu-debug.sh"; else fail "run-qemu-debug.sh missing"; fi
if [ -x "${TOP_DIR}/run-qemu-debug.sh" ]; then pass "run-qemu-debug.sh is executable"; else fail "run-qemu-debug.sh not executable"; fi

echo ""
echo "CI/CD:"
if [ -f "${TOP_DIR}/.github/workflows/build.yml" ]; then pass "GitHub Actions workflow"; else fail "build.yml missing"; fi

echo ""
echo "NOT Yocto (verify clean removal):"
if [ ! -d "${TOP_DIR}/meta-superlite" ]; then pass "meta-superlite removed"; else fail "meta-superlite still exists!"; fi

# ── Build artifacts ────────────────────────────────────────────────────────
echo ""
ISO_COUNT=$(find "${TOP_DIR}/output" -name "*.iso" 2>/dev/null | wc -l)
if [ "$ISO_COUNT" -gt 0 ]; then
    echo "Build Artifacts:"
    while IFS= read -r line; do
        pass "$line"
    done <<EOF
$(find "${TOP_DIR}/output" -name "*.iso" -exec ls -lh {} \;)
EOF
else
    echo "Build Artifacts: (none — run 'make docker' to build)"
fi

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
TOTAL=$((PASS + FAIL))
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
if [ "$FAIL" -eq 0 ]; then
    echo -e "\033[0;32mAll checks passed!\033[0m"
else
    echo -e "\033[0;31mSome checks failed.\033[0m"
fi
echo "═══════════════════════════════════════════════"

exit $FAIL
