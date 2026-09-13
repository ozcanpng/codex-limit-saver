# codex-limit-saver

Submit a minimal Codex CLI prompt (`hello`) shortly after the account's actual
five-hour usage window resets.

This project does not bypass, extend, or reset limits. It does not create API
keys or store credentials. It uses the existing Codex CLI authentication in
`~/.codex`.

## How it works

Instead of guessing a five-hour schedule from a fixed clock time, the
dispatcher queries Codex CLI's machine-readable app-server JSON-RPC endpoint:

```text
initialize → account/rateLimits/read → rateLimits.primary.resetsAt
```

`resetsAt` is a Unix timestamp supplied by Codex. The tool records the observed
timestamp and runs `codex exec hello` when Codex reports that this reset has
passed. Its per-user systemd timer wakes the lightweight dispatcher once a
minute; Codex is only invoked after a newly observed reset.

This avoids parsing ANSI terminal output from `/status`, depending on a local
database, or using an undocumented HTTP endpoint. JSON is decoded by Python's
standard library and validated before a prompt can be submitted.

If the computer is off over a reset, systemd's `Persistent=true` timer starts
the dispatcher on the next opportunity. It detects the newer reset timestamp
and sends one catch-up `hello` for the missed transition.

## Requirements

- Linux with a working per-user `systemd` manager (Ubuntu, Debian, Fedora,
  Arch, openSUSE, and similar distributions)
- Bash, Python 3, GNU `date`, and `systemctl`
- Codex CLI installed, in `PATH`, and already authenticated

There is no reliable single scheduler API for every Linux init system. This
repository deliberately targets systemd for per-user timers and persistence;
non-systemd systems are not supported.

## Install

```bash
git clone https://github.com/ozcanpng/codex-limit-saver.git
cd codex-limit-saver
./install.sh
```

By default, `hello` is submitted at least 60 seconds after the detected reset.
Larger safety buffers are supported:

```bash
./install.sh --grace-seconds 90
```

The installer discovers and verifies the executable `codex` launcher, then
writes only that path and the grace period to
`~/.config/codex-limit-saver/config.env` with mode `600`.

## Verify and operate

```bash
systemctl --user status codex-limit-saver.timer
systemctl --user list-timers codex-limit-saver.timer --all
journalctl --user-unit=codex-limit-saver.service -f
tail -f ~/.local/state/codex-limit-saver/codex-limit-saver.log
~/.local/lib/codex-limit-saver/read-rate-limit.py "$(command -v codex)"
```

The final command prints the primary reset timestamp without submitting a
prompt. Convert it to local time with:

```bash
date -d "@$(~/.local/lib/codex-limit-saver/read-rate-limit.py "$(command -v codex)")"
```

`loginctl enable-linger "$USER"` is attempted during installation so the
per-user manager can continue after logout and across reboots.

## Uninstall

```bash
./uninstall.sh
```

This removes installed unit files, runtime scripts, configuration, state, and
logs. It does not remove Codex or its authentication.

## Safety notes

- The exact prompt is `hello`.
- Invocations use `codex exec --ignore-user-config --ephemeral --sandbox read-only`.
- `--ignore-user-config` keeps Codex authentication but avoids loading personal
  config such as optional MCP servers for this scheduler-only request.
- The log records every newly reported `reset_observed` time and its matching
  `hello_eligible_after` time.
- If the JSON-RPC response is unavailable or malformed, no prompt is sent.
- `codex app-server` is marked experimental by Codex CLI; the included reader
  checks its response rather than scraping UI text.

## License

[MIT](LICENSE)
