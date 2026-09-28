#!/usr/bin/env bash

set -euo pipefail

shellcheck --shell=bash --external-sources \
	bin/* lib/*.bash scripts/*.bash tests/*.bash

shfmt --language-dialect bash --diff bin lib scripts tests
