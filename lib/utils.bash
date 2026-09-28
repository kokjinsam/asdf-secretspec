#!/usr/bin/env bash

set -euo pipefail

GH_REPO="https://github.com/cachix/secretspec"
TOOL_NAME="secretspec"

fail() {
	printf 'asdf-%s: %s\n' "$TOOL_NAME" "$*" >&2
	exit 1
}

sort_versions() {
	LC_ALL=C sort -t. -k1,1n -k2,2n -k3,3n -u
}

list_all_versions() {
	git ls-remote --tags --refs "$GH_REPO.git" |
		sed -nE 's#^[^[:space:]]+[[:space:]]+refs/tags/v((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))$#\1#p'
}

validate_version() {
	local install_type version
	install_type="${ASDF_INSTALL_TYPE:-}"
	version="${ASDF_INSTALL_VERSION:-}"

	[ "$install_type" = "version" ] || fail "Only release version installs are supported."
	[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
		fail "Use a stable version such as 0.21.1."
}

version_uses_musl() {
	local version="$1" major rest minor
	major="${version%%.*}"
	rest="${version#*.}"
	minor="${rest%%.*}"

	[ "$major" -gt 0 ] || {
		[ "$major" -eq 0 ] && [ "$minor" -ge 20 ]
	}
}

platform_target() {
	local version="$1" system architecture linux_libc
	system=$(uname -s)
	architecture=$(uname -m)

	case "$system/$architecture" in
	Darwin/arm64 | Darwin/aarch64) printf 'aarch64-apple-darwin\n' ;;
	Darwin/x86_64 | Darwin/amd64) printf 'x86_64-apple-darwin\n' ;;
	Linux/arm64 | Linux/aarch64) linux_libc=aarch64 ;;
	Linux/x86_64 | Linux/amd64) linux_libc=x86_64 ;;
	*) fail "Unsupported platform: $system/$architecture. Supported platforms are macOS and Linux on x86_64 or ARM64." ;;
	esac

	case "$system" in
	Linux)
		if version_uses_musl "$version"; then
			printf '%s-unknown-linux-musl\n' "$linux_libc"
		else
			printf '%s-unknown-linux-gnu\n' "$linux_libc"
		fi
		;;
	esac
}

sha256_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{ print $1 }'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{ print $1 }'
	else
		fail 'Install sha256sum or shasum to verify downloads.'
	fi
}

curl_download() {
	local url="$1" output="$2"
	local curl_args=(-qfsSL --retry 3)

	if [ -n "${GITHUB_API_TOKEN:-}" ]; then
		curl_args+=(-H "Authorization: token $GITHUB_API_TOKEN")
	fi

	curl "${curl_args[@]}" -o "$output" "$url"
}

checksum_for() {
	local checksum_file="$1" asset="$2" value
	value=$(awk -v asset="$asset" '
		$2 == "*" asset || $2 == asset {
			count++
			if (count == 1) print $1
		}
		END {
			if (count != 1) exit 1
		}
	' "$checksum_file") || fail "Missing or duplicate checksum for $asset."

	value=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
	[[ "$value" =~ ^[0-9a-f]{64}$ ]] || fail "Invalid SHA-256 checksum for $asset."
	printf '%s\n' "$value"
}

validate_archive() {
	local archive="$1" work_dir="$2" members member secret_member member_count root_dir secret_path
	members=$(tar -tJf "$archive") || fail "Could not read archive $archive."

	member_count=0
	secret_member=''
	while IFS= read -r member; do
		[ -n "$member" ] || continue
		case "$member" in
		/* | ../* | */../* | */.. | ..) fail "Archive contains an unsafe path: $member." ;;
		esac
		case "$member" in
		*/secretspec)
			member_count=$((member_count + 1))
			secret_member="$member"
			;;
		esac
	done <<EOF
$members
EOF

	[ "$member_count" -eq 1 ] || fail 'Archive must contain one secretspec executable.'
	case "$secret_member" in
	*/secretspec)
		root_dir="${secret_member%/secretspec}"
		;;
	*)
		fail "Archive has an unexpected secretspec path: $secret_member."
		;;
	esac
	case "$root_dir" in
	'' | */*) fail "Archive has an unexpected secretspec path: $secret_member." ;;
	esac

	tar -xJf "$archive" -C "$work_dir" "$secret_member" ||
		fail "Could not extract secretspec from $archive."
	secret_path="$work_dir/$secret_member"
	[ -f "$secret_path" ] && [ ! -L "$secret_path" ] && [ -x "$secret_path" ] ||
		fail 'Archive does not contain an executable secretspec file.'

	printf '%s\n' "$secret_path"
}

download_release() (
	validate_version
	local version="$ASDF_INSTALL_VERSION" download_path="${ASDF_DOWNLOAD_PATH:-}"
	local target asset checksum base_url temp_dir expected actual secret_path
	local secret_member root_dir

	[ -n "$download_path" ] || fail 'ASDF_DOWNLOAD_PATH is required.'
	target=$(platform_target "$version")
	asset="secretspec-$target.tar.xz"
	checksum="$asset.sha256"
	base_url="$GH_REPO/releases/download/v$version"
	temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/asdf-secretspec.XXXXXX") ||
		fail 'Could not create a temporary directory.'

	# shellcheck disable=SC2329
	cleanup() {
		rm -f "$temp_dir/$asset" "$temp_dir/$checksum"
		if [ -n "${secret_path:-}" ]; then
			rm -f "$secret_path"
		fi
		if [ -n "${root_dir:-}" ]; then
			rmdir "$temp_dir/$root_dir" 2>/dev/null || true
		fi
		rmdir "$temp_dir" 2>/dev/null || true
	}
	trap cleanup EXIT

	printf '* Downloading %s release %s (%s)...\n' "$TOOL_NAME" "$version" "$target" >&2
	curl_download "$base_url/$asset" "$temp_dir/$asset" ||
		fail "Could not download $asset. The release may not provide an archive for this platform."
	curl_download "$base_url/$checksum" "$temp_dir/$checksum" ||
		fail "Could not download $checksum."

	expected=$(checksum_for "$temp_dir/$checksum" "$asset")
	actual=$(sha256_file "$temp_dir/$asset")
	[ "$actual" = "$expected" ] || fail "SHA-256 mismatch for $asset."

	secret_path=$(validate_archive "$temp_dir/$asset" "$temp_dir")
	secret_member="${secret_path#"$temp_dir/"}"
	root_dir="${secret_member%/secretspec}"
	mkdir -p "$download_path"
	cp -p "$secret_path" "$download_path/secretspec"
)

install_version() {
	validate_version
	local download_path="${ASDF_DOWNLOAD_PATH:-}" install_path="${ASDF_INSTALL_PATH:-}"
	local staging_file

	[ -n "$download_path" ] || fail 'ASDF_DOWNLOAD_PATH is required.'
	[ -n "$install_path" ] || fail 'ASDF_INSTALL_PATH is required.'
	[ -f "$download_path/secretspec" ] &&
		[ ! -L "$download_path/secretspec" ] &&
		[ -x "$download_path/secretspec" ] ||
		fail 'Download is missing an executable secretspec file.'

	mkdir -p "$install_path/bin" || fail "Could not create $install_path/bin."
	staging_file=$(mktemp "$install_path/bin/.secretspec.XXXXXX") ||
		fail "Could not create a staging file in $install_path/bin."
	if ! cp -p "$download_path/secretspec" "$staging_file" ||
		! chmod 755 "$staging_file" ||
		! mv -f "$staging_file" "$install_path/bin/secretspec"; then
		rm -f "$staging_file"
		fail "Could not install secretspec into $install_path/bin."
	fi

	printf '%s %s installation was successful.\n' "$TOOL_NAME" "$ASDF_INSTALL_VERSION"
}
