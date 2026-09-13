# codex-limit-saver

Run a minimal Codex CLI prompt (`hello`) on a persistent, anchored five-hour
cycle. It is useful when you want a new Codex usage window to begin regularly.

This project does not bypass limits, create API keys, or store credentials. It
uses the existing Codex CLI authentication in `~/.codex`.

## Why not fixed daily timer hours?

Five hours does not divide evenly into a 24-hour day. A daily timer such as
`07:00,12:00,17:00,22:00` breaks the interval at midnight. This project anchors
the schedule at 07:00 and calculates every later execution as exactly 18,000
seconds after that anchor:

```text
07:00 → 12:00 → 17:00 → 22:00 → 03:00 → 08:00 → 13:00 → 18:00 → ...
```

The systemd timer wakes the lightweight dispatcher once a minute. The
dispatcher invokes Codex only for an eligible five-hour slot. This is necessary
to preserve the non-daily cadence and let a `Persistent=true` timer catch up
after a shutdown. If one or more slots elapsed while the computer was off, the
most recent missed slot runs once shortly after startup.

## Requirements

- Linux with a working per-user `systemd` manager (Ubuntu, Debian, Fedora,
  Arch, openSUSE, and similar distributions)
- Bash, GNU `date`, and `systemctl`
- Codex CLI installed, in `PATH`, and already authenticated

There is no reliable single scheduler API for every Linux init system. This
repository deliberately targets systemd because it provides per-user timers,
boot persistence, and reliable logging. Non-systemd systems are not supported.

## Install

```bash
git clone https://github.com/ozcanpng/codex-limit-saver.git
cd codex-limit-saver
./install.sh
```

By default, installation anchors today at 07:00 in the machine's configured
timezone. If that time has already passed, the next future point in the same
five-hour sequence is used; historical prompts are not sent retroactively.

Optional settings:

```bash
./install.sh --start 07:00 --timezone Europe/Istanbul
```

The installer automatically finds and verifies an executable `codex` launcher,
then writes only its path and schedule metadata to
`~/.config/codex-limit-saver/config.env` with mode `600`. This handles npm's
JavaScript launcher without treating its non-executable module file as a binary.

## Verify and operate

```bash
systemctl --user status codex-limit-saver.timer
systemctl --user list-timers codex-limit-saver.timer --all
journalctl --user-unit=codex-limit-saver.service -f
tail -f ~/.local/state/codex-limit-saver/codex-limit-saver.log
./scripts/verify-schedule.sh Europe/Istanbul
```

The log records each scheduled timestamp, complete stdout/stderr, and exit
status. `loginctl enable-linger "$USER"` is attempted during installation so the
per-user manager can remain available after logout and across reboots.

## Uninstall

```bash
./uninstall.sh
```

This removes the installed unit files, runtime script, configuration, state,
and logs. It does not remove Codex or its authentication.

## Safety notes

- The exact prompt is `hello`.
- Invocations use `codex exec --ephemeral --sandbox read-only`.
- Existing Codex configuration may start optional MCP servers; their diagnostic
  output is retained in the log.

## License

[MIT](LICENSE)
