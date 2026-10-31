# James Bond 007: Nightfire Server (Docker)

This repository provides a Dockerized **James Bond 007: Nightfire** dedicated server. The PC game (Gearbox, 2002) has no stand-alone server. Its engine runs one with `Bond2.exe -dedicated`. The image runs the 5.9x community patch build (engine 5.9.9.0, with Metamod and AMX Mod X) under Wine.
The image builds on [`lancommander/wine`](https://github.com/LANCommander/LANCommander.Servers.WINE). It supports file overlaying using OverlayFS.

---

## Features

- Runs `Bond2.exe -dedicated` from a normal 5.9x game install, with no separate server package
- Patches `engine.dll` on start so the dedicated server doesn't crash on every map load (see [Documentation/Docker.md](Documentation/Docker.md#enginedll-patch))
- Server name, map, rotation, limits and passwords are environment variables. They are written into a server config that runs on every map load
- Capture the Flag and Deathmatch, with default rotations of every stock map of the starting map's type
- The server console is streamed to `docker logs` (`-condebug`)
- Status queries on the GameSpy port and the game port for monitoring
- Supports file overlaying using OverlayFS (no file copying required)

## Docker Compose Example

```yaml
services:
  nightfire:
    image: lancommander/nightfire:latest
    container_name: nightfire

    ports:
      - "26015:26015/udp"
      - "6550:6550/udp"

    volumes:
      - ./config:/config

    environment:
      NF_SERVER_NAME: "My Nightfire Server"
      NF_MAP: "ctf_romania"
      NF_TIME_LIMIT: "15"
      NF_RCON_PASSWORD: "changeme"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

---

## Game Files

Nightfire is retail software with no public download. You must provide an install with the 5.9x community patch (`Bond2.exe`, `engine.dll`, `bond/assets.007`, `bond/dlls/game.dll` ...):

- copy the game folder (the one containing `Bond2.exe`) to `config/Server/`, **or**
- set `NF_ARCHIVE_URL` to a zip of that folder, e.g. a LANCommander archive. It is downloaded and extracted on first start, if `Server/Bond2.exe` doesn't exist yet. `bond/movies/` is skipped.

The server doesn't need `bond/movies/`.

## Directory Layout (Host)

```text
.
└── config/
    ├── Server/            # Nightfire install (Bond2.exe, engine.dll, bond/ ...)
    ├── Overlay/           # Your files, layered on top of Server/ (the patched engine.dll, the generated
    │                      # bond/lancommander.cfg and mapcycle, and bond/qconsole.log land here)
    ├── Merged/            # Overlayfs merged view (auto-created, the server runs here)
    ├── wineprefix/        # Wine prefix (auto-created)
    └── Scripts/
        └── Hooks/         # PowerShell scripts run at container lifecycle hooks
```

---

## Environment Variables

These are in addition to the [WINE image's variables](https://github.com/LANCommander/LANCommander.Servers.WINE#environment).
The `NF_*` server settings are written into `bond/<NF_CONFIG>` on every start. Settings left empty are not written, so you can set them in `bond/server.cfg` instead, which that file execs first.

| Variable | Description | Default |
|----------|-------------|---------|
| `NF_CONFIG` | Generated config, `bond/<name>`, passed as `servercfgfile` so it runs on every map load | `lancommander.cfg` |
| `NF_SERVER_NAME` | Server name (`host_name`) | `Nightfire` |
| `NF_PORT` | Game and RCON port (`-port`) | `26015` |
| `NF_QUERY_PORT` | GameSpy query port (`-queryport`) | `6550` |
| `NF_MAP` | Starting map. `ctf_` maps are Capture the Flag, `dm_` maps Deathmatch | `ctf_romania` |
| `NF_MAPCYCLE` | Comma-separated rotation (`bond/<name>_mapcycle.txt`). Empty = every stock map of `NF_MAP`'s type; `config` = leave `mapcyclefile` alone | |
| `NF_MAX_PLAYERS` | `-maxplayers` | `16` |
| `NF_TIME_LIMIT` | Minutes (`mp_timelimit`). The game's default is 50 | |
| `NF_FRAG_LIMIT` | `mp_fraglimit` | |
| `NF_CAPTURE_LIMIT` | Flag captures to win a CTF map (`ctf_capture`). The game's default is 5 | |
| `NF_FRIENDLY_FIRE` | `mp_friendlyfire` | |
| `NF_WEAPON_STAY` | `mp_weaponstay` | |
| `NF_PASSWORD` | Join password (`sv_password`). Empty = open server | |
| `NF_RCON_PASSWORD` | `rcon_password`. Empty = RCON off | |
| `NF_LAN` | `sv_lan` | `true` |
| `NF_PATCH_ENGINE` | Patch `engine.dll` for dedicated use (see above) | `true` |
| `NF_ARCHIVE_URL` | Zip of the game folder, used if `Server/Bond2.exe` is missing | |
| `WINE_XVFB` | Run on a virtual display. The server needs one | `true` |
| `START_EXE` | Launcher | `/usr/local/bin/nf-server` |
| `START_ARGS` | Added to the `Bond2.exe` command line, before `+map` | |

Default rotations (the maps in the 5.9x `assets.007`):

- Capture the Flag: `ctf_austria`, `ctf_island`, `ctf_japan`, `ctf_jungle`, `ctf_knox`, `ctf_office`, `ctf_romania`, `ctf_tower`
- Deathmatch: `dm_austria`, `dm_casino`, `dm_caviar`, `dm_island`, `dm_japan`, `dm_jungle`, `dm_knox`, `dm_maint`, `dm_office`, `dm_power`

See [Documentation/Docker.md](Documentation/Docker.md) for more detail.

---

## Building

The image is built `FROM lancommander/wine:latest` by default. To build against a local base image:

```bash
docker build --build-arg BASE_IMAGE=lancommander/wine:local -t lancommander/nightfire:local .
```

---

## License

James Bond 007: Nightfire, the community patch and Wine are distributed under their respective licenses.
This repository contains only Docker build logic and helper scripts licensed under MIT.
