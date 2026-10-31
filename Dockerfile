# syntax=docker/dockerfile:1.7

# Override to build against a locally built base, e.g. lancommander/wine:local
ARG BASE_IMAGE=lancommander/wine:latest
FROM ${BASE_IMAGE}

# ----------------------------
# Server settings
#   - The game files are not downloadable; put a Nightfire install with the 5.9x community patch
#     (Bond2.exe, engine.dll, bond/assets.007 ...) in /config/Server, or set NF_ARCHIVE_URL to a
#     zip of one
#   - The dedicated server is `Bond2.exe -dedicated`. A hook patches engine.dll so it doesn't
#     crash on map load (NF_PATCH_ENGINE)
#   - The configure hook writes the NF_* settings below into bond/<NF_CONFIG> on every start
#     (empty settings are left alone); it execs bond/server.cfg first if there is one
#   - NF_MAP's prefix picks the game type (ctf_ or dm_). NF_MAPCYCLE is a comma-separated
#     rotation; empty uses every stock map of that type, "config" keeps mapcyclefile as it is
#   - The server needs a window (with no X display it never binds its ports), so it runs under Xvfb
# ----------------------------
ENV NF_ARCHIVE_URL="" \
    NF_PATCH_ENGINE="true" \
    NF_CONFIG="lancommander.cfg" \
    NF_SERVER_NAME="Nightfire" \
    NF_PORT="26015" \
    NF_QUERY_PORT="6550" \
    NF_MAP="ctf_romania" \
    NF_MAPCYCLE="" \
    NF_MAX_PLAYERS="16" \
    NF_TIME_LIMIT="" \
    NF_FRAG_LIMIT="" \
    NF_CAPTURE_LIMIT="" \
    NF_FRIENDLY_FIRE="" \
    NF_WEAPON_STAY="" \
    NF_PASSWORD="" \
    NF_RCON_PASSWORD="" \
    NF_LAN="true" \
    WINE_XVFB="true" \
    START_EXE="/usr/local/bin/nf-server" \
    START_ARGS=""

COPY Scripts/nf-server /usr/local/bin/nf-server
RUN chmod +x /usr/local/bin/nf-server

COPY Hooks/ "${BASE_HOOKS}/"

# 26015/udp: game, RCON and `bond_infostring` queries (NF_PORT)
# 6550/udp:  GameSpy status queries (NF_QUERY_PORT)
EXPOSE 26015/udp
EXPOSE 6550/udp

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]
