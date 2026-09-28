set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Install the pinned project tools. This is the only recipe that installs tools.
setup:
    test "$(asdf version)" = "0.16.5" || test "$(asdf version)" = "v0.16.5"
    asdf install

# Verify the pinned project tools.
doctor:
    test "$(asdf version)" = "0.16.5" || test "$(asdf version)" = "v0.16.5"
    test "$(just --version)" = "just 1.54.0"
    test "$(shellcheck --version | sed -n '2s/^version: //p')" = "0.11.0"
    test "$(shfmt --version)" = "v3.13.1"

# Format shell scripts.
format:
    scripts/format.bash

# Check shell script formatting without changing files.
format-check: doctor
    shfmt -d bin lib scripts tests

# Check shell scripts for defects.
lint: doctor
    shellcheck -x bin/* lib/*.bash scripts/*.bash tests/*.bash

# Run offline plugin behavior tests.
test: doctor
    bash tests/plugin.bash

# Run the complete local verification suite.
check: doctor format-check lint test
