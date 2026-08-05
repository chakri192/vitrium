#!/usr/bin/env bash
#
# Runs the test suite.
#
# Not `swift test`: XCTest ships only with Xcode, and the Command Line Tools'
# swift-testing is missing its Foundation overlay. The suite is an ordinary
# executable instead, so it runs anywhere Swift does.

set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec swift run VitriumTests
