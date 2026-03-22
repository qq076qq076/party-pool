# Party Pool Prototype

This folder contains the first runnable MVP prototype implementation based on `規格書.md` and `遊戲機制.md`.

## What Is Implemented
- Room create/join with room code
- Permission-gated join (`DeviceMotion` must be granted in controller page flow)
- Ready phase with max 60-second timeout
  - All players press `OK` => start early
  - Otherwise auto-start at 60 seconds
  - Host cannot force immediate round start
- First mini-game: 20-second tap challenge
- Scoring: first place +1, ties for first all +1
- Browser-language default (`zh-*` -> `zh-TW`, else `en`) and manual switch
- Basic `rejoin_token` flow for reconnect
- Event-driven state sync via long-poll endpoint (`/api/wait-state`)
- `control_profile` included in room snapshots (mode/timers/countdown)

## Run
From repository root:

```bash
wsl python3 /home/walker/project/party-pool/prototype/server.py
```

Then open:
- Host screen: `http://localhost:8000/host.html`
- Controller screen: `http://localhost:8000/controller.html?room=ABCD`

Quick start helpers from repo root:

```bash
./run-prototype.sh
```

or in PowerShell:

```powershell
.\run-prototype.ps1
```

## Notes
- This is a web prototype to validate room/game flow quickly.
- Godot client integration is the next step (reuse API contract from this server).
