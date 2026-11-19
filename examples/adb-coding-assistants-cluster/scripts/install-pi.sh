#!/bin/bash
#
# Databricks cluster init script - Pi coding agent on Unity Gateway
#
# Installs Node.js, the Pi coding agent, the Unity Gateway CLI (ug) and
# Databricks agent skills. ug configures Pi to call Databricks-hosted models
# through Unity Gateway
# (https://docs.databricks.com/aws/en/ai-gateway/coding-agent-quickstart).
#
# Nothing in this script handles a credential. At run time ug reads the
# session's DATABRICKS_TOKEN from the environment for each request, so no token
# is written to disk.
#

set -uo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a CI=true

L="/tmp/init-script-pi.log"
log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$L"; }
cmd_exists() { command -v "$1" >/dev/null 2>&1; }

# Init scripts run as root. sudo is only used when the script is run by hand.
as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Pinned inputs. Override through cluster environment variables (spark_env_vars).
# Node.js release (Pi needs 22.19 or newer). The tarball is checked against the
# SHASUMS256.txt published with the release.
NODE_VERSION="${NODE_VERSION:-24.22.3}"
# Pi release on npm. The package ships npm-shrinkwrap.json, so its dependencies
# are pinned too.
PI_VERSION="${PI_VERSION:-1.5.2}"
# Unity Gateway CLI: commit of github.com/databricks/unity-gateway (main, 2026-11-18;
# 224 commits after release v0.2.1, which does not write Pi model metadata).
UG_REF="${UG_REF:-e5d113253a12ca58d327d35a87bafdf816204a71}"
# uv, used to install ug. The release archive is checked against its .sha256.
UV_VERSION="${UV_VERSION:-0.13.8}"
# Databricks CLI, installed only when the cluster has none at 1.0 or newer.
DATABRICKS_CLI_VERSION="${DATABRICKS_CLI_VERSION:-1.26.0}"
# Commit of github.com/databricks/databricks-agent-skills to install skills from
# (release v0.2.50). A commit SHA cannot be moved, unlike a branch or tag.
DATABRICKS_SKILLS_REF="${DATABRICKS_SKILLS_REF:-7a4e1a9cb745f8bede84dd22199b8d72c51e863d}"

# Everything is installed under one prefix and reached through the
# pi-databricks wrappers, so nothing the Databricks Runtime ships in
# /usr/local/bin (node, uv, the databricks CLI launcher) is replaced.
PREFIX="/opt/pi-databricks"
BIN_DIR="$PREFIX/bin"
NODE_DIR="$PREFIX/node"
UV_TOOLS_DIR="$PREFIX/uv-tools"
export PATH="$BIN_DIR:$NODE_DIR/bin:$PATH"

node_is_new_enough() {
    cmd_exists node && node -e '
        const [maj, min] = process.versions.node.split(".").map(Number);
        process.exit(maj > 22 || (maj === 22 && min >= 19) ? 0 : 1);
    ' 2>/dev/null
}

# Install Node.js from the official release tarball
install_nodejs() {
    if [ -x "$NODE_DIR/bin/node" ] && [ "$("$NODE_DIR/bin/node" --version)" = "v${NODE_VERSION}" ]; then
        log "[OK] Node.js ${NODE_VERSION} already installed"
        return 0
    fi

    local arch
    case "$(uname -m)" in
        x86_64) arch="x64" ;;
        aarch64 | arm64) arch="arm64" ;;
        *)
            log "[WARN] Unsupported architecture for Node.js: $(uname -m)"
            return 1
            ;;
    esac

    local file="node-v${NODE_VERSION}-linux-${arch}.tar.gz"
    local base_url="https://nodejs.org/dist/v${NODE_VERSION}"
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    log "Installing Node.js ${NODE_VERSION} (${arch})..."
    if curl -fsSL --max-time 300 --retry 3 -o "$tmp_dir/$file" "$base_url/$file" 2>>"$L" \
        && curl -fsSL --max-time 60 --retry 3 -o "$tmp_dir/SHASUMS256.txt" "$base_url/SHASUMS256.txt" 2>>"$L" \
        && (cd "$tmp_dir" && grep " ${file}\$" SHASUMS256.txt | sha256sum -c - &>>"$L") \
        && as_root rm -rf "$NODE_DIR" && as_root mkdir -p "$NODE_DIR" \
        && as_root tar -xzf "$tmp_dir/$file" -C "$NODE_DIR" --strip-components=1 2>>"$L"; then
        rm -rf "$tmp_dir"
        if node_is_new_enough; then
            log "[OK] Node.js installed ($(node --version))"
            return 0
        fi
        log "[WARN] Node.js installed but not usable"
        return 1
    fi

    rm -rf "$tmp_dir"
    log "[WARN] Node.js installation failed (Pi will not work)"
    return 1
}

# Install the Pi coding agent
install_pi() {
    if [ -x "$NODE_DIR/bin/pi" ] && [ "$(pi --version 2>/dev/null)" = "$PI_VERSION" ]; then
        log "[OK] Pi ${PI_VERSION} already installed"
        return 0
    fi

    log "Installing Pi ${PI_VERSION}..."
    # --ignore-scripts: Pi needs no dependency lifecycle scripts, so none run.
    # The global prefix is this Node.js install, so pi lands in $NODE_DIR/bin.
    if as_root env PATH="$PATH" npm install -g --ignore-scripts --no-fund --no-audit \
        "@earendil-works/pi-coding-agent@${PI_VERSION}" &>>"$L" && [ -x "$NODE_DIR/bin/pi" ]; then
        log "[OK] Pi installed ($(pi --version 2>/dev/null))"
        return 0
    fi

    log "[WARN] Pi installation failed"
    return 1
}

# Install Databricks skills
# Skills come from the official databricks/databricks-agent-skills repository,
# fetched as one archive at a pinned commit. Pi discovers ~/.agents/skills.
install_databricks_skills() {
    local skills_dir="$HOME/.agents/skills"
    local archive_url="https://github.com/databricks/databricks-agent-skills/archive/${DATABRICKS_SKILLS_REF}.tar.gz"

    # Core skills to install (curated list for most common use cases)
    local core_skills=(
        "databricks-core"
        "databricks-python-sdk"
        "databricks-unity-catalog"
        "databricks-jobs"
        "databricks-dabs"
        "databricks-apps-python"
        "databricks-model-serving"
        "databricks-mlflow-evaluation"
        "databricks-aibi-dashboards"
        "databricks-pipelines"
    )

    log "Installing Databricks skills (ref ${DATABRICKS_SKILLS_REF})..."

    mkdir -p "$skills_dir"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    # Written as a positive test. In testing on Databricks Runtime 17.3, a
    # workspace-file init script containing the negated form of this condition
    # (`if ! curl ... \` followed by `|| ! tar ...`) failed before running.
    if curl -fsSL --max-time 300 --retry 3 -o "$tmp_dir/skills.tar.gz" "$archive_url" 2>>"$L" \
        && tar -xzf "$tmp_dir/skills.tar.gz" -C "$tmp_dir" --strip-components=1 2>>"$L"; then
        :
    else
        log "[WARN] Could not download Databricks skills archive"
        rm -rf "$tmp_dir"
        return 1
    fi

    local installed=0
    local failed=0

    for skill in "${core_skills[@]}"; do
        local skill_dir="$skills_dir/$skill"

        if [ -d "$skill_dir" ] && [ -f "$skill_dir/SKILL.md" ]; then
            installed=$((installed + 1))
            continue
        fi

        if [ -f "$tmp_dir/skills/$skill/SKILL.md" ] && cp -R "$tmp_dir/skills/$skill" "$skill_dir" 2>>"$L"; then
            installed=$((installed + 1))
        else
            log "  [WARN] Skill not found in archive: $skill"
            rm -rf "$skill_dir"
            failed=$((failed + 1))
        fi
    done

    rm -rf "$tmp_dir"

    if [ $installed -gt 0 ]; then
        log "[OK] Databricks skills installed: $installed skills"
        [ $failed -gt 0 ] && log "[WARN] Failed to install: $failed skills"
        return 0
    fi

    log "[WARN] No Databricks skills installed"
    return 1
}


# Install uv from its release archive
install_uv() {
    if cmd_exists uv; then
        log "[OK] uv already installed ($(uv --version 2>/dev/null))"
        return 0
    fi

    local target
    case "$(uname -m)" in
        x86_64) target="x86_64-unknown-linux-gnu" ;;
        aarch64 | arm64) target="aarch64-unknown-linux-gnu" ;;
        *)
            log "[WARN] Unsupported architecture for uv: $(uname -m)"
            return 1
            ;;
    esac

    local file="uv-${target}.tar.gz"
    local base_url="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}"
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    log "Installing uv ${UV_VERSION}..."
    if curl -fsSL --max-time 300 --retry 3 -o "$tmp_dir/$file" "$base_url/$file" 2>>"$L" \
        && curl -fsSL --max-time 60 --retry 3 -o "$tmp_dir/$file.sha256" "$base_url/$file.sha256" 2>>"$L" \
        && (cd "$tmp_dir" && sha256sum -c "$file.sha256" &>>"$L") \
        && tar -xzf "$tmp_dir/$file" -C "$tmp_dir" --strip-components=1 2>>"$L" \
        && as_root install -D -m 755 "$tmp_dir/uv" "$BIN_DIR/uv"; then
        rm -rf "$tmp_dir"
        log "[OK] uv installed ($(uv --version 2>/dev/null))"
        return 0
    fi

    rm -rf "$tmp_dir"
    log "[WARN] uv installation failed"
    return 1
}

# Install the Databricks CLI that ug calls
# The Databricks Runtime's own `databricks` command only runs inside the web
# terminal, so ug gets a regular CLI under the prefix instead.
install_databricks_cli() {
    if [ -x "$BIN_DIR/databricks" ]; then
        log "[OK] Databricks CLI already installed ($("$BIN_DIR/databricks" --version 2>/dev/null))"
        return 0
    fi

    local arch
    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64 | arm64) arch="arm64" ;;
        *)
            log "[WARN] Unsupported architecture for the Databricks CLI: $(uname -m)"
            return 1
            ;;
    esac

    local file="databricks_cli_${DATABRICKS_CLI_VERSION}_linux_${arch}.tar.gz"
    local base_url="https://github.com/databricks/cli/releases/download/v${DATABRICKS_CLI_VERSION}"
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    log "Installing Databricks CLI ${DATABRICKS_CLI_VERSION}..."
    if curl -fsSL --max-time 300 --retry 3 -o "$tmp_dir/$file" "$base_url/$file" 2>>"$L" \
        && curl -fsSL --max-time 60 --retry 3 -o "$tmp_dir/SHA256SUMS" \
            "$base_url/databricks_cli_${DATABRICKS_CLI_VERSION}_SHA256SUMS" 2>>"$L" \
        && (cd "$tmp_dir" && grep " ${file}\$" SHA256SUMS | sha256sum -c - &>>"$L") \
        && tar -xzf "$tmp_dir/$file" -C "$tmp_dir" 2>>"$L" \
        && as_root install -D -m 755 "$tmp_dir/databricks" "$BIN_DIR/databricks"; then
        rm -rf "$tmp_dir"
        log "[OK] Databricks CLI installed ($(databricks --version 2>/dev/null))"
        return 0
    fi

    rm -rf "$tmp_dir"
    log "[WARN] Databricks CLI installation failed"
    return 1
}

# Install the Unity Gateway CLI for every user of the cluster
install_ug() {
    if [ -x "$BIN_DIR/ug" ]; then
        log "[OK] ug already installed ($(ug --version 2>/dev/null))"
        return 0
    fi

    log "Installing Unity Gateway CLI (ref ${UG_REF})..."
    if as_root env PATH="$PATH" UV_TOOL_DIR="$UV_TOOLS_DIR" UV_TOOL_BIN_DIR="$BIN_DIR" \
        uv tool install --python ">=3.12" \
        "git+https://github.com/databricks/unity-gateway@${UG_REF}" &>>"$L"; then
        as_root chmod -R a+rX "$PREFIX" 2>/dev/null || true
        log "[OK] ug installed ($(ug --version 2>/dev/null))"
        return 0
    fi

    log "[WARN] ug installation failed"
    return 1
}

# Install the helper commands
install_helpers() {
    as_root mkdir -p "$BIN_DIR"
    # pi-databricks: launch Pi through Unity Gateway with the session's credentials.
    as_root tee /usr/local/bin/pi-databricks >/dev/null <<'LAUNCH'
#!/bin/bash
# Launch the Pi coding agent through Databricks Unity Gateway.
#
# ug writes Pi's provider and model configuration and resolves a token for every
# request. On a cluster the token is the session's DATABRICKS_TOKEN, which ug
# reads through DATABRICKS_BEARER_COMMAND, so no login runs and nothing that
# expires is stored on disk.
set -euo pipefail
export PATH="/opt/pi-databricks/bin:/opt/pi-databricks/node/bin:$PATH"

if [ -z "${DATABRICKS_HOST:-}" ]; then
    echo "DATABRICKS_HOST is not set. Open a cluster terminal or set it to your workspace URL." >&2
    exit 1
fi
HOST="${DATABRICKS_HOST%/}"
case "$HOST" in
    http://* | https://*) ;;
    *) HOST="https://$HOST" ;;
esac
export UG_WORKSPACE="$HOST"

# Without a session token, ug falls back to its own login (`databricks auth login`).
if [ -n "${DATABRICKS_TOKEN:-}" ] && [ -z "${DATABRICKS_BEARER:-}" ] && [ -z "${DATABRICKS_BEARER_COMMAND:-}" ]; then
    export DATABRICKS_BEARER_COMMAND="printenv DATABRICKS_TOKEN"
fi

STAMP="$HOME/.ucode/.pi-databricks-workspace"
if [ "${1:-}" = "--reconfigure" ]; then
    shift
    rm -f "$STAMP"
fi
if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$HOST" ]; then
    echo "Configuring Pi for Unity Gateway at $HOST..." >&2
    ug configure --agents pi --workspace "$HOST" </dev/null >&2
    mkdir -p "$(dirname "$STAMP")"
    printf '%s' "$HOST" >"$STAMP"
fi

exec ug pi "$@"
LAUNCH
    as_root chmod 755 /usr/local/bin/pi-databricks

    # pi-databricks-check: show what is installed and configured. Prints no secrets.
    as_root tee /usr/local/bin/pi-databricks-check >/dev/null <<'CHECK'
#!/bin/bash
# Report the state of the Pi + Unity Gateway setup. Never prints the token.
ok() { echo "  [OK] $1"; }
bad() { echo "  [ERROR] $1"; }
have() { command -v "$1" >/dev/null 2>&1; }
export PATH="/opt/pi-databricks/bin:/opt/pi-databricks/node/bin:$PATH"

echo "=== Pi on Unity Gateway ==="
if have node; then ok "Node.js $(node --version)"; else bad "Node.js not found"; fi
if have pi; then ok "Pi $(pi --version 2>/dev/null)"; else bad "pi not found"; fi
if have ug; then ok "ug $(ug --version 2>/dev/null)"; else bad "ug not found"; fi
if have databricks; then ok "Databricks CLI $(databricks --version 2>/dev/null)"; else bad "Databricks CLI not found"; fi

if [ -n "${DATABRICKS_HOST:-}" ]; then ok "DATABRICKS_HOST: $DATABRICKS_HOST"; else bad "DATABRICKS_HOST: not set"; fi
if [ -n "${DATABRICKS_TOKEN:-}" ]; then
    ok "DATABRICKS_TOKEN: set"
else
    echo "  [INFO] DATABRICKS_TOKEN: not set (ug will ask you to log in)"
fi

STAMP="$HOME/.ucode/.pi-databricks-workspace"
if [ -f "$STAMP" ]; then
    ok "Pi configured for $(cat "$STAMP")"
else
    echo "  [INFO] Pi is configured on first run of pi-databricks"
fi

SKILLS_DIR="$HOME/.agents/skills"
if [ -d "$SKILLS_DIR" ]; then
    ok "Skills: $(find "$SKILLS_DIR" -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ') in $SKILLS_DIR"
fi

echo ""
echo "Start Pi with:      pi-databricks"
echo "Test the gateway:   pi-databricks -p \"Reply with the word ready\""
echo "Models and spend:   ug status"
CHECK
    as_root chmod 755 /usr/local/bin/pi-databricks-check
    log "[OK] Helper commands installed (pi-databricks, pi-databricks-check)"
}

main() {
    log "Starting installation..."

    log "Installing system dependencies..."
    if as_root apt-get update -qq -y &>>"$L" && as_root apt-get install -y -qq curl git jq ca-certificates &>>"$L"; then
        log "[OK] System dependencies installed (curl, git, jq)"
    else
        log "[WARN] Some system dependencies failed to install"
    fi

    # Continue even if a step fails, so the cluster still starts.
    install_nodejs && install_pi || log "[WARN] Pi is not installed"
    install_databricks_cli || log "[WARN] Databricks CLI is not installed"
    install_uv && install_ug || log "[WARN] ug is not installed"
    install_databricks_skills || log "[WARN] Databricks skills installation incomplete"
    install_helpers || log "[WARN] Helper installation failed"

    log ""
    log "Installation complete. Full log: $L"
    log "Next steps (in a cluster terminal):"
    log "  1. Verify: pi-databricks-check"
    log "  2. Use: pi-databricks"
    return 0
}

main
exit 0
