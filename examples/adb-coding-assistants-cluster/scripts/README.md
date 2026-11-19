# Init scripts for the Pi coding agent on Unity Gateway

| Script | Purpose | Runs on |
| --- | --- | --- |
| `install-pi.sh` | Cluster init script: installs Pi, the `ug` CLI and Databricks skills | Cluster, at start |
| `check-network-deps.sh` | Checks that the domains the init script needs are reachable | Any machine |
| `vscode-setup.sh` | VS Code/Cursor Remote SSH helper | Cluster terminal |

## What `install-pi.sh` installs

Everything goes under `/opt/pi-databricks`, so the Databricks Runtime's own `node`, `uv` and `databricks` commands are left alone.

| Component | Source | Integrity check |
| --- | --- | --- |
| Node.js | `nodejs.org` release archive | SHA-256 from the release's `SHASUMS256.txt` |
| Pi coding agent | npm, `@earendil-works/pi-coding-agent`, installed with `--ignore-scripts` | npm integrity hashes; dependencies pinned by the package's shrinkwrap file |
| Databricks CLI | GitHub release archive | SHA-256 from the release's `SHA256SUMS` |
| `uv` | Provided by the runtime, otherwise the GitHub release archive | SHA-256 from the release's `.sha256` file |
| `ug` CLI | `databricks/unity-gateway` at a pinned commit | Git commit SHA |
| Databricks skills | `databricks/databricks-agent-skills` at a pinned commit | Git commit SHA |

No remote script is piped into a shell.

The script logs to `/tmp/init-script-pi.log` and exits with status 0 even when a step fails, so a blocked download does not stop the cluster from starting.

## Commands added to the cluster

| Command | Purpose |
| --- | --- |
| `pi-databricks` | Configure Pi for the workspace on first run, then start it through `ug pi` |
| `pi-databricks --reconfigure` | Run `ug configure` again, for example to pick up new models |
| `pi-databricks-check` | Show installed versions and configuration. Prints no secrets |

## Environment variables

Set by a `databricks ssh` session:

- `DATABRICKS_HOST`: workspace URL
- `DATABRICKS_TOKEN`: session token. `ug` reads it on each request; it is not stored

Read by `install-pi.sh` (the Terraform example sets the first four):

- `PI_VERSION`
- `NODE_VERSION`
- `UG_REF`
- `DATABRICKS_SKILLS_REF`
- `UV_VERSION`
- `DATABRICKS_CLI_VERSION`

## Network dependencies

| Domain | Purpose |
| --- | --- |
| `archive.ubuntu.com`, `ports.ubuntu.com` | APT packages (`curl`, `git`, `jq`) |
| `nodejs.org` | Node.js release archive |
| `registry.npmjs.org` | Pi coding agent package |
| `github.com`, `codeload.github.com` | `ug` CLI source and Databricks skills archive |
| `release-assets.githubusercontent.com` | Databricks CLI and `uv` release downloads |
| `pypi.org`, `files.pythonhosted.org` | Python packages the `ug` CLI depends on |
| Your workspace URL | Unity Gateway |

Check them with:

```bash
./scripts/check-network-deps.sh
./scripts/check-network-deps.sh --verbose
```

## Security notes

- No credential is written to disk. Pi's provider configuration stores a command (`ug auth-token`) instead of a token, and `ug` resolves the session token from the environment.
- All model traffic goes to the workspace's Unity Gateway endpoints over HTTPS.
- Installed versions are pinned. Review and update the pins on your own schedule.

## A note on shell syntax in init scripts

In testing on Databricks Runtime 17.3, a workspace-file init script that contained this form failed before running any command, with "Script exit status is non-zero":

```bash
if ! curl ... 2>>"$L" \
    || ! tar ... 2>>"$L"; then
```

The same condition written as `if curl ... && tar ...; then :; else ...; fi` works. `install-pi.sh` uses the second form.
