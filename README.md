# asdf-secretspec

An [asdf](https://asdf-vm.com/) plugin for installing prebuilt
[SecretSpec](https://github.com/cachix/secretspec) command-line binaries.

## Support

- macOS: Intel and Apple Silicon.
- Linux: x86_64 and ARM64.
- Stable X.Y.Z release versions only.
- SHA-256 verification before archive extraction.
- Prebuilt archives only. The plugin does not compile SecretSpec.

Linux installations use GNU archives for versions before 0.20.0 and static
musl archives from 0.20.0 onward. SecretSpec release 0.19.0 has no CLI
archives, so installation of that version fails with a clear archive error.
A Git tag does not prove that an archive exists for the current platform.

The plugin requires Bash, Git, curl, tar with xz support, standard Unix
utilities, and either sha256sum or shasum. Native Windows installation is
outside this plugin's scope.

## Install

    asdf plugin add secretspec https://github.com/kokjinsam/asdf-secretspec.git
    asdf list all secretspec
    asdf install secretspec 0.21.1
    asdf set -u secretspec 0.21.1
    secretspec --version

For the latest stable release:

    asdf install secretspec latest
    asdf set -u secretspec latest

SecretSpec updates remain under asdf control. The plugin does not install
SecretSpec package-manager integrations or run the upstream self-updater.

## Development

Use asdf 0.16.5. The required versions of Just, ShellCheck, and shfmt are in
.tool-versions. Their asdf plugins must already be registered.

    just setup
    just check

Only just setup installs the development tools. The tests use local release
fixtures and do not contact GitHub. They cover version ordering, prefix
selection, platform mapping, unsupported inputs, missing archives, checksum
failures, paths with spaces, archive validation, and preservation of an
existing installation after a failed install.

The build workflow also runs the real 0.21.1 installation test on the
supported macOS and Linux runner architectures. Hosted CI results are not
included in this checkout's verification.

## License

MIT. See LICENSE.
