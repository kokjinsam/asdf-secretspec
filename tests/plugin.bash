#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/asdf-secretspec-tests.XXXXXX")
mock_bin="$test_root/mock bin"
fixture_dir="$test_root/fixture"
mkdir -p "$mock_bin" "$fixture_dir"

cleanup() {
	rm -f "$mock_bin/git" "$mock_bin/curl" "$mock_bin/uname"
	rm -f "$fixture_dir/secretspec-x86_64-unknown-linux-gnu.tar.xz"
	rm -f "$fixture_dir/secretspec-x86_64-unknown-linux-musl.tar.xz"
	rm -f "$fixture_dir/secretspec-aarch64-unknown-linux-musl.tar.xz"
	rm -f "$fixture_dir/secretspec-aarch64-apple-darwin.tar.xz"
	rmdir "$mock_bin" "$fixture_dir" "$test_root" 2>/dev/null || true
}
trap cleanup EXIT

assert_eq() {
	local expected="$1" actual="$2" message="$3"
	if [ "$expected" != "$actual" ]; then
		printf 'FAIL: %s\nexpected: %s\nactual: %s\n' "$message" "$expected" "$actual" >&2
		exit 1
	fi
}

assert_file_content() {
	local expected="$1" file="$2" message="$3" actual
	actual=$(sed -n '1p' "$file")
	assert_eq "$expected" "$actual" "$message"
}

cat >"$mock_bin/git" <<'EOF'
#!/usr/bin/env bash
cat <<'TAGS'
111 refs/tags/v0.21.1
222 refs/tags/v0.20.0
333 refs/tags/v0.19.0
444 refs/tags/v0.2.0
555 refs/tags/v0.20.0-rc1
666 refs/tags/release-1.0.0
777 refs/tags/v01.2.3
TAGS
EOF

cat >"$mock_bin/uname" <<'EOF'
#!/usr/bin/env bash
case "$1" in
-s) printf '%s\n' "${MOCK_UNAME_S:-Linux}" ;;
-m) printf '%s\n' "${MOCK_UNAME_M:-x86_64}" ;;
*) exit 1 ;;
esac
EOF

cat >"$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=''
url=''
while [ "$#" -gt 0 ]; do
	case "$1" in
	-o) output="$2"; shift 2 ;;
	-H | --header | --retry) shift 2 ;;
	-*) shift ;;
	*) url="$1"; shift ;;
	esac
done
asset="${url##*/}"
if [ "${MOCK_CURL_MODE:-ok}" = missing ]; then
	exit 22
fi
if [ "$asset" = "secretspec-x86_64-unknown-linux-gnu.tar.xz" ] ||
	[ "$asset" = "secretspec-x86_64-unknown-linux-musl.tar.xz" ] ||
	[ "$asset" = "secretspec-aarch64-unknown-linux-musl.tar.xz" ] ||
	[ "$asset" = "secretspec-aarch64-apple-darwin.tar.xz" ]; then
	cp "$MOCK_FIXTURE_DIR/$asset" "$output"
elif [[ "$asset" == *.sha256 ]]; then
	archive="${asset%.sha256}"
	if [ "${MOCK_CURL_MODE:-ok}" = checksum ]; then
		printf '%064d *%s\n' 0 "$archive" >"$output"
	else
		if command -v sha256sum >/dev/null 2>&1; then
			digest=$(sha256sum "$MOCK_FIXTURE_DIR/$archive" | awk '{print $1}')
		else
			digest=$(shasum -a 256 "$MOCK_FIXTURE_DIR/$archive" | awk '{print $1}')
		fi
		printf '%s *%s\n' "$digest" "$archive" >"$output"
	fi
else
	exit 22
fi
EOF

chmod 755 "$mock_bin/git" "$mock_bin/curl" "$mock_bin/uname"

export PATH="$mock_bin:$PATH"
export MOCK_FIXTURE_DIR="$fixture_dir"

list_output=$("$repo_dir/bin/list-all")
assert_eq $'0.2.0\n0.19.0\n0.20.0\n0.21.1' "$list_output" 'stable versions are filtered and sorted'
assert_eq '0.20.0' "$("$repo_dir/bin/latest-stable" 0.20)" 'latest-stable supports a version prefix'
if "$repo_dir/bin/latest-stable" 1.0 >/dev/null 2>&1; then
	printf 'FAIL: latest-stable accepted an unknown prefix\n' >&2
	exit 1
fi

make_fixture() {
	local target="$1"
	local archive="$fixture_dir/secretspec-$target.tar.xz"
	local root="$fixture_dir/secretspec-$target"
	mkdir -p "$root"
	local script_line
	script_line="printf \"secretspec %s\\\\n\" \"\$MOCK_VERSION\""
	printf '%s\n' '#!/usr/bin/env bash' "$script_line" >"$root/secretspec"
	chmod 755 "$root/secretspec"
	tar -cJf "$archive" -C "$fixture_dir" "secretspec-$target/secretspec"
	rm -f "$root/secretspec"
	rmdir "$root"
}

export MOCK_VERSION=0.21.1
make_fixture x86_64-unknown-linux-musl
make_fixture x86_64-unknown-linux-gnu
make_fixture aarch64-unknown-linux-musl
make_fixture aarch64-apple-darwin

space_root="$test_root/path with spaces"
mkdir -p "$space_root/tmp"
export TMPDIR="$space_root/tmp"
download_path="$space_root/download"
ASDF_INSTALL_TYPE=version ASDF_INSTALL_VERSION=0.21.1 ASDF_DOWNLOAD_PATH="$download_path" \
	MOCK_UNAME_S=Linux MOCK_UNAME_M=x86_64 "$repo_dir/bin/download"
[ -x "$download_path/secretspec" ] || {
	printf 'FAIL: Linux musl archive was not downloaded\n' >&2
	exit 1
}
assert_eq 'secretspec 0.21.1' "$(MOCK_VERSION=0.21.1 "$download_path/secretspec")" 'downloaded executable works'

gnu_download="$space_root/gnu-download"
ASDF_INSTALL_TYPE=version ASDF_INSTALL_VERSION=0.19.1 ASDF_DOWNLOAD_PATH="$gnu_download" \
	MOCK_UNAME_S=Linux MOCK_UNAME_M=x86_64 "$repo_dir/bin/download" >/dev/null
[ -x "$gnu_download/secretspec" ] || {
	printf 'FAIL: pre-0.20 GNU archive was not downloaded\n' >&2
	exit 1
}

arm_download="$space_root/arm-download"
ASDF_INSTALL_TYPE=version ASDF_INSTALL_VERSION=0.21.1 ASDF_DOWNLOAD_PATH="$arm_download" \
	MOCK_UNAME_S=Linux MOCK_UNAME_M=aarch64 "$repo_dir/bin/download" >/dev/null
[ -x "$arm_download/secretspec" ] || {
	printf 'FAIL: Linux ARM64 archive was not downloaded\n' >&2
	exit 1
}

darwin_download="$space_root/darwin-download"
ASDF_INSTALL_TYPE=version ASDF_INSTALL_VERSION=0.21.1 ASDF_DOWNLOAD_PATH="$darwin_download" \
	MOCK_UNAME_S=Darwin MOCK_UNAME_M=arm64 "$repo_dir/bin/download" >/dev/null
[ -x "$darwin_download/secretspec" ] || {
	printf 'FAIL: macOS ARM64 archive was not downloaded\n' >&2
	exit 1
}

if ASDF_INSTALL_TYPE=path ASDF_INSTALL_VERSION=0.21.1 ASDF_DOWNLOAD_PATH="$space_root/invalid" \
	MOCK_UNAME_S=Linux MOCK_UNAME_M=x86_64 "$repo_dir/bin/download" >/dev/null 2>&1; then
	printf 'FAIL: non-version install type was accepted\n' >&2
	exit 1
fi
if ASDF_INSTALL_TYPE=version ASDF_INSTALL_VERSION=0.21 ASDF_DOWNLOAD_PATH="$space_root/invalid" \
	MOCK_UNAME_S=Linux MOCK_UNAME_M=x86_64 "$repo_dir/bin/download" >/dev/null 2>&1; then
	printf 'FAIL: non-release version was accepted\n' >&2
	exit 1
fi

existing_download="$space_root/existing-download"
mkdir -p "$existing_download"
printf 'old download\n' >"$existing_download/secretspec"
if ASDF_INSTALL_TYPE=version ASDF_INSTALL_VERSION=0.21.1 ASDF_DOWNLOAD_PATH="$existing_download" \
	MOCK_CURL_MODE=checksum MOCK_UNAME_S=Linux MOCK_UNAME_M=x86_64 "$repo_dir/bin/download" >/dev/null 2>&1; then
	printf 'FAIL: checksum failure was accepted\n' >&2
	exit 1
fi
assert_file_content 'old download' "$existing_download/secretspec" 'checksum failure preserves existing download'

missing_download="$space_root/missing-download"
if ASDF_INSTALL_TYPE=version ASDF_INSTALL_VERSION=0.19.0 ASDF_DOWNLOAD_PATH="$missing_download" \
	MOCK_CURL_MODE=missing MOCK_UNAME_S=Linux MOCK_UNAME_M=x86_64 "$repo_dir/bin/download" >/dev/null 2>&1; then
	printf 'FAIL: missing archive was accepted\n' >&2
	exit 1
fi
[ ! -e "$missing_download/secretspec" ] || {
	printf 'FAIL: missing archive created an installation file\n' >&2
	exit 1
}

if ASDF_INSTALL_TYPE=version ASDF_INSTALL_VERSION=0.21.1 ASDF_DOWNLOAD_PATH="$space_root/unsupported" \
	MOCK_UNAME_S=FreeBSD MOCK_UNAME_M=x86_64 "$repo_dir/bin/download" >/dev/null 2>&1; then
	printf 'FAIL: unsupported platform was accepted\n' >&2
	exit 1
fi

install_path="$space_root/install"
mkdir -p "$install_path/bin"
printf 'old install\n' >"$install_path/bin/secretspec"
invalid_download="$space_root/invalid-download"
mkdir -p "$invalid_download"
printf 'not executable\n' >"$invalid_download/secretspec"
if ASDF_INSTALL_TYPE=version ASDF_INSTALL_VERSION=0.21.1 ASDF_DOWNLOAD_PATH="$invalid_download" \
	ASDF_INSTALL_PATH="$install_path" "$repo_dir/bin/install" >/dev/null 2>&1; then
	printf 'FAIL: invalid download was installed\n' >&2
	exit 1
fi
assert_file_content 'old install' "$install_path/bin/secretspec" 'failed install preserves existing file'

ASDF_INSTALL_TYPE=version ASDF_INSTALL_VERSION=0.21.1 ASDF_DOWNLOAD_PATH="$download_path" \
	ASDF_INSTALL_PATH="$install_path" "$repo_dir/bin/install" >/dev/null
assert_eq 'secretspec 0.21.1' "$(MOCK_VERSION=0.21.1 "$install_path/bin/secretspec")" 'valid install replaces the executable'

printf 'Plugin tests passed. Temporary files: %s\n' "$test_root"
