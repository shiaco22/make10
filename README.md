# MAKE10

An offline Flutter puzzle game for iOS and Android (single codebase). Four
digits (0-9, duplicates allowed) are dealt; you merge two cards at a time --
tap a card, tap an operator (`+` `-` `×` `÷`), tap a second card -- until one
card is left, aiming to land on exactly 10 after three merges. Every dealt
puzzle is guaranteed to have a solution.

Two modes, both asking for a difficulty (easy / normal / hard) first and
recording per-difficulty stats and best scores on-device:

- **Practice** -- untimed, with hints, "view answer", and skip.
- **Time Attack** -- a 120-second run scored by puzzles cleared; hints and
  "view answer" are disabled.

Not in this app (v1 scope; see
`docs/superpowers/specs/2026-08-30-make10-app-design.md` section 1.1 for the
authoritative list): sound/haptics, online leaderboards, accounts or any
network communication, daily challenges or stage progression, ads or
in-app purchases, and localization -- the UI is Japanese only.

## Requirements

Flutter SDK. On this machine it is installed at `C:\flutter` and is **not**
on `PATH` -- call it by full path:

```
C:\flutter\bin\flutter.bat ...
C:\flutter\bin\dart.bat ...
```

(`C:/flutter/bin/flutter.bat` also works from a POSIX-style shell.)

## Running the app

```
C:\flutter\bin\flutter.bat run
```

Pick an attached device/emulator, or run in a browser with `-d chrome` or
`-d web-server`. `.claude/launch.json` already has a `make10-web`
configuration for the latter.

## Running the tests

```
C:\flutter\bin\flutter.bat test
```

## Linting

```
C:\flutter\bin\flutter.bat analyze
```

**`flutter analyze` cannot run from a path containing non-ASCII characters**
(for example the Japanese folder name this repo lives under by default) --
the Dart analysis server mis-frames its LSP messages over stdio and crashes.
A directory junction does not help; it still resolves back to the original
path. Instead, copy the repository to an ASCII-only path (e.g.
`C:\Temp\make10`) and run `flutter pub get` then `flutter analyze` there.

## Regenerating `assets/puzzles.json`

The puzzle table is precomputed by running the app's own solver
(`lib/domain/solver.dart`) over all 715 possible 4-digit deals, so there is
only one implementation of the solving logic to keep correct. To
regenerate:

```
C:\flutter\bin\dart.bat run tool/generate_puzzles.dart
```

This overwrites `assets/puzzles.json`. `test/tool/generate_puzzles_test.dart`
asserts that regenerating reproduces the committed file byte for byte, so
run the tests afterward and commit the regenerated file alongside any
solver or rule change.
