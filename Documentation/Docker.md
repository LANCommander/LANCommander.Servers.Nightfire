---
sidebar_label: Docker
---

# James Bond 007: Nightfire Docker Container

This Docker container runs a James Bond 007: Nightfire dedicated server. It is built on the WINE image and runs the 5.9x community patch's engine in dedicated mode, `Bond2.exe -dedicated`, on a virtual display. The container doesn't download the game, so you provide the files.

## Quick Start

```yaml
services:
  nightfire:
    image: lancommander/nightfire:latest
    container_name: nightfire

    ports:
      - 26015:26015/udp
      - 6550:6550/udp

    volumes:
      - "/data/Servers/James Bond 007 - Nightfire/CTF:/config"

    environment:
      NF_SERVER_NAME: "My Nightfire Server"
      NF_MAP: "ctf_romania"
      NF_RCON_PASSWORD: "changeme"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

Before the first start, copy a Nightfire install with the 5.9x community patch, the folder that contains `Bond2.exe`, into `Server/`. You can instead set `NF_ARCHIVE_URL` to a zip of that folder.

## How It Starts

1. `PostInitialization/10-InitializeWinePrefix.ps1` (from the WINE image) creates the Wine prefix in `/config/wineprefix`.
2. `PostInitialization/20-InstallNightfire.ps1` checks for `Server/Bond2.exe`. If it's missing and `NF_ARCHIVE_URL` is set, the hook downloads and extracts the archive (without `bond/movies/`) and remounts the overlay.
3. `PostInitialization/25-PatchEngine.ps1` writes a patched `engine.dll` into `Overlay/` (see below).
4. `PostInitialization/30-ConfigureNightfire.ps1` writes the non-empty `NF_*` settings into `bond/<NF_CONFIG>` and the map rotation into `bond/<name>_mapcycle.txt`.
5. `START_EXE` (`/usr/local/bin/nf-server`) runs this from the game folder, under Wine and Xvfb:

   ```
   Bond2.exe -dedicated -port 26015 -queryport 6550 -maxplayers 16 -condebug [START_ARGS] +servercfgfile lancommander.cfg +map ctf_romania
   ```

`Bond.exe` in the game folder is the patch's .NET launcher and updater. `Bond2.exe` is the engine. The server console is a window, so `-condebug` logs it to `bond/qconsole.log` and the launcher streams that file to `docker logs`. A successful start ends with:

```
Server IP address 172.17.0.2:26015
Could not get IPX socket name, IPX disabled
Reason:  WSAENOTSOCK
Executing AMX Mod X Configuration File
```

The IPX lines are harmless.

To check that the server is up, send a GameSpy status query to the query port:

```bash
python3 -c 'import socket; s=socket.socket(2,2); s.settimeout(3); s.sendto(b"\\status\\",("<server>",6550)); print(s.recvfrom(4096)[0])'
# b'\\gamename\\jbnightfire\\gamever\\5.99 insecure\\dedicated\\1\\...\\gametype\\CTF\\hostport\\26015\\mapname\\ctf_romania\\...\\hostname\\My Nightfire Server\\...'
```

or the engine's info query to the game port (`\xff\xff\xff\xffbond_infostring\n`, answered with `infostringresponse` and the name, map, player count and `lan` flag).

## Configuration Options

### Ports

- **26015/udp**: Game, RCON and `bond_infostring` queries (`NF_PORT`)
- **6550/udp**: GameSpy status queries (`NF_QUERY_PORT`)

### Environment Variables

See the [README](../README.md#environment-variables) for the full table.

### Server Config

`bond/<NF_CONFIG>` (default `lancommander.cfg`) is regenerated on every start and passed as `servercfgfile`, so the engine runs it on every map load, as it would `server.cfg`. If `bond/server.cfg` exists, the generated file execs it first. Put your own settings in `Overlay/bond/server.cfg`. A setting that also has a non-empty `NF_*` variable is overridden by that variable.

Some cvar names differ from Half-Life's:

| Setting | Cvar |
|---------|------|
| Server name | `host_name` (`hostname` does nothing) |
| CTF capture limit | `ctf_capture` |
| Time / frag limit | `mp_timelimit` / `mp_fraglimit` |
| Bots | `bots_mode`, `bot_list` |

`ProfileTemplate/config.cfg` in the game folder lists the game's defaults.

### Maps and Game Types

The map prefix picks the game type: `ctf_` maps are Capture the Flag, `dm_` maps are Deathmatch (shown as the map's mode name, e.g. "Vega", in the server info). The maps are packed into `bond/assets.007`, so you won't find them in `bond/maps/`. `dm_backstreets`, `dm_backstreets_winter` and `ctf_backstreets` are mentioned in the game files, but aren't in the 5.9x assets.

### Metamod and AMX Mod X

The 5.9x patch loads its game DLL through Metamod (`bond/liblist.gam`) with AMX Mod X and several patch modules. Their configs are in `bond/addons/`. Put edited copies in `Overlay/bond/addons/`.

### engine.dll Patch

The 5.9x patch adds code to `engine.dll` that precaches the player death sounds with hard-coded pointers to strings inside `bond/cl_dlls/client.dll`. Only a game client loads `client.dll`, so on a dedicated server every map load crashes with

```
wine: Unhandled page fault on read access to 4107DDFE at address 4306CEDC
```

in `PF_precache_sound_I`. The female death sound code does the same during play. The hook copies the four strings (`player/pl_die2.wav`, `pl_die3.wav`, `pl_die4.wav`, `fe_die1.wav`) into unused space in the patch's section of `engine.dll` and points the code at the copies. It writes the patched file to `Overlay/`, and `Server/` keeps the original. Only the known engine (5.9.9.0, sha256 `fb9a9896...7f4797`) is patched. Any other build is left alone with a warning. Set `NF_PATCH_ENGINE=false` to skip it.

### RCON

Set `NF_RCON_PASSWORD` and use any GoldSrc-style RCON client against the game port (challenge, then `rcon <challenge> "<password>" <command>`). Command output goes to the server console (`docker logs`).

### Hooks

| Hook | When |
|------|------|
| `PreInstallNightfire` / `PostInstallNightfire` | Around the game file check/download |
| `PreInitializeWinePrefix` / `PostInitializeWinePrefix` | Around Wine prefix creation (WINE image) |

Put `.ps1` scripts in `config/Scripts/Hooks/<HookName>/`.

## Troubleshooting

- **Crash on map load, `page fault on read access to 4107DDFE`**: `engine.dll` isn't patched. Check the hook's log line. An unknown engine build isn't patched.
- **No ports bound, nothing in the log**: the server needs a display. With no X display it starts but never binds its ports. Keep `WINE_XVFB=true`.
- **Status queries get no reply**: the starting map doesn't exist (see [Maps and Game Types](#maps-and-game-types)). The server keeps running but never answers queries. Check `NF_MAP` and the console log.
- **The first start takes a while**: creating the Wine prefix takes about a minute, and the first map load after that takes up to 30 seconds more.
- **Server name stays `NIGHTFIRE`**: set it with `host_name`, not `hostname`.
- **`Bad Rcon` lines in the log**: Half-Life style connectionless queries (`info`, `details`, `TSource Engine Query`) aren't supported and are logged as bad RCON. Use `bond_infostring` or the GameSpy port.
- **Not in the in-game server list**: LAN discovery is untested with this image. Discovery by broadcast needs the container on the LAN itself (macvlan/ipvlan, or `network_mode: host`). Clients can always join by IP.
