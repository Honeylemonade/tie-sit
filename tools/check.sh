#!/bin/bash
# Regression checks that also work with Command Line Tools (no XCTest/Xcode required).
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
SOURCES=()
for source in Sources/TIESit/*.swift; do
    [[ "$source" == */TIESitApp.swift ]] || SOURCES+=("$source")
done
swiftc -parse-as-library "${SOURCES[@]}" Tests/RegressionChecks.swift -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks" "$@"
if [[ "$#" -gt 0 ]]; then exit 0; fi

swiftc -parse-as-library "${SOURCES[@]}" Tests/HoldUICheck.swift -o "$CHECK_DIR/hold-ui"
"$CHECK_DIR/hold-ui"
