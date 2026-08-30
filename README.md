# LibreWolf Auto Update

A small Bash script that checks the latest LibreWolf release on the LibreWolf Forgejo instance (librewolf.dev), compares it with the installed version, and installs the update when a newer version is available. Before installing, it shows the release notes published by LibreWolf and asks for confirmation (`Y/n`; press Enter to accept).

Downloads are verified against LibreWolf's published SHA-256 checksum before installation.

## Supported systems

- macOS (defaults to `/Applications/LibreWolf.app`; override with `LIBREWOLF_APP`)
- Debian-based Linux using `dpkg` and `apt-get`
- RPM-based Linux using `dnf` or `rpm`
- ARM64 and x86-64 processors

## Requirements

The script requires `curl`, Bash, either `jq` or Python 3, and either `sha256sum` or `shasum`. LibreWolf must already be installed and detectable.

## Setup

After cloning, run:

```bash
bash setup.sh
```

The setup script checks that the updater's required command-line dependencies are available, creates `~/.local/bin` if needed, and links:

```text
~/.local/bin/update-librewolf -> <repo>/update-librewolf.sh
```

If `~/.local/bin` is not on your `PATH`, the setup script prints the shell configuration line to add it.

## Usage

Check whether an update is available without installing it:

```bash
update-librewolf --check
```

View the latest release notes without updating:

```bash
update-librewolf --release-notes
```

Review the release notes and install an available update after confirming with `Y` (or just Enter):

```bash
update-librewolf
```

You can also run `./update-librewolf.sh` directly from the repository.

The installation may ask for your password through `sudo`.

Run `update-librewolf --help` to see the documented options and environment variables.
