# kevin-Mini Data Server

A static website on the Windows mini PC that serves data files (CSV, Parquet, JSON, ...) to devices on your home network. Nothing is exposed to the internet.

It uses [Caddy](https://caddyserver.com) 2.11.7, installed by `setup-data-server.ps1` as a Windows service that starts at boot.

## Set it up

On kevin-Mini, in **PowerShell as Administrator**, from this repository's folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass        # allow this repo's scripts in this window only
Get-ChildItem -Recurse | Unblock-File            # only if you downloaded the repo as a ZIP
.\setup-data-server.ps1
```

Then copy files into `C:\DataServer\public\data` and open `http://kevin-Mini:8080/` from another device.

Re-running the script is safe: it updates the install in place and only restarts the server when something changed.

| Option | What it does |
|---|---|
| `-Port 8090` | Use another port (default 8080) |
| `-DataRoot D:\Datasets` | Serve a different folder; data goes in its `data` subfolder |
| `-BasicAuthUser kevin` | Require a login; you're prompted for the password (8+ characters) |
| `-RemoveBasicAuth` | Remove the login. A plain re-run keeps an existing login. |
| `-BindAddress 192.168.1.50` | Listen on one address only (reserve it in your router first) |
| `-SetNetworkPrivate` | Switch your home network from Public to Private if needed (see below). Other networks (VPNs, virtual adapters) are left alone. If the script can't tell which network is home, it switches nothing; add `-BindAddress <LAN IP>` to choose. |
| `-AllowSleep` | Don't change sleep settings |
| `-Uninstall` | Remove the service and firewall rule; files stay |

## What the script does

1. **Downloads Caddy 2.11.7** from its GitHub release and checks it against the published SHA-512. A mismatch stops the install. It picks the x64 or ARM64 build automatically.
2. **Creates folders** under `C:\DataServer`: `caddy\` (program), `Caddyfile` (config), `logs\` (`access.log` and Caddy's own `caddy.log`), `state\`, and `public\` (the website: `index.html` plus `data\`).
3. **Writes the config** from `data-server/Caddyfile.template` and has Caddy validate it.
4. **Installs the `DataServer` service**:
   - It starts automatically at boot (delayed start, so the network is up first) and restarts itself if it crashes.
   - It runs as the low-privilege **LocalService** account. That account gets read access to the program and data, and write access only to `logs\` and `state\`.
5. **Adds a firewall rule** that lets other devices connect only on networks Windows classifies as **Private**, only from your **local subnet**, and only to `caddy.exe`.
6. **Keeps the PC awake** on AC power (sleep and hibernate set to Never), since a sleeping server is unreachable. Skip this with `-AllowSleep`.
7. **Checks the server answers**, then prints the addresses to use.

## Reaching it from other devices

Try these, in order:

| Address | Usually works from |
|---|---|
| `http://kevin-Mini:8080/` | Other Windows PCs |
| `http://kevin-mini.local:8080/` | Macs, iPhones/iPads, Linux |
| `http://<IP shown by the script>:8080/` | Everything |

If the names don't resolve on your network, use the IP. To keep the IP from changing, set a **DHCP reservation** for kevin-Mini in your router's settings (often under LAN or DHCP, "address reservation"). Use the MAC address shown by `Get-NetAdapter` on kevin-Mini.

**Can't connect at all?** The most common cause is that Windows classifies your home network as **Public**, where the firewall rule doesn't apply. The script warns you about this. Fix it with `-SetNetworkPrivate`, or under **Settings → Network & internet → (your connection) → Network profile type → Private**.

## Using the data

The landing page at `/` shows copy-paste snippets with the right address filled in. `/data/` lists the files.

```python
import pandas as pd
df = pd.read_csv("http://kevin-Mini:8080/data/sales.csv")
df = pd.read_parquet("http://kevin-Mini:8080/data/sales.parquet")  # pip install pyarrow fsspec aiohttp

import polars as pl
lazy = pl.scan_parquet("http://kevin-Mini:8080/data/sales.parquet")  # reads only what the query needs
```

```sql
-- DuckDB
INSTALL httpfs; LOAD httpfs;
SELECT region, count(*) FROM read_parquet('http://kevin-Mini:8080/data/sales.parquet') GROUP BY 1;
```

How the server is set up for data work:
- **Range requests:** DuckDB, pyarrow and Polars read only the parts of a Parquet file they need.
- **Content types** are set explicitly: `text/csv`, `application/json`, `application/x-ndjson` and `application/vnd.apache.parquet` (IANA-registered 2024). Windows would otherwise guess from the registry, where Excel claims `.csv`.
- **Compression:** CSV, JSON and text are gzip/zstd-compressed (about 3× smaller for CSV). Parquet is left alone, since it's already compressed.
- **CORS** is open, so browser-based tools served over plain `http://` on your network can fetch files.
- **Hidden files:** dotfiles, `desktop.ini` and `Thumbs.db` are hidden and return 404.

**Browser tools on `https://` sites can't use this server.** Examples are shell.duckdb.org and Observable. Browsers block an `https://` page from fetching an `http://` address (mixed content), and Chrome also asks for local-network permission. Use DuckDB, pandas or Polars locally instead, or serve the tool's page from this server too.

## The optional login

`-BasicAuthUser` turns on HTTP basic authentication: browsers show a login prompt, and tools pass credentials in the URL or as options. The password is stored only as a bcrypt hash.

The first request after a login takes about a second while the password is checked; Caddy caches the result, so later requests (including the many small Range requests DuckDB and pyarrow make) are as fast as without a login. Browser tools can't fetch files cross-origin with a login on, because credentialed CORS requests need a specific origin rather than `*`.

**Over plain HTTP, this is a deterrent, not real security.** Anyone on your network who captures the traffic can read the password. Don't reuse an important password, and keep sensitive data off the server.

## Managing it

```powershell
Get-Service DataServer
Restart-Service DataServer
Get-Content C:\DataServer\logs\access.log -Tail 20       # who fetched what
Get-Content C:\DataServer\logs\caddy.log -Tail 20        # why it didn't start
notepad C:\DataServer\public\index.html                  # edit the landing page (re-runs don't overwrite it)
.\setup-data-server.ps1 -Uninstall
```

To change the Caddy config, edit `data-server/Caddyfile.template` in this repo and re-run the script. Edits made directly to `C:\DataServer\Caddyfile` are replaced on the next run.

## What was tested, and what wasn't

The script hasn't been run on Windows yet. What was tested, in a Linux sandbox:
- **Caddy's behavior:** the same 2.11.7 build and the same config template. This covered content types, Range requests (206), compression on CSV only, CORS preflight, hidden files, the login, and binding to one address.
- **Real clients:** pandas, pyarrow, Polars and DuckDB all read CSV and Parquet over HTTP.
- **The setup script:** run with PowerShell 7. Windows-only commands (services, firewall, `sc.exe`, `icacls`, `powercfg`) were replaced with recorders, but the real Caddy did the validation, password hashing and health checks. I ran a fresh install, a re-run with no changes, login on, kept, and removed, invalid input, and uninstall.
- **Downloads:** the pinned SHA-512 hashes were checked against GitHub for both x64 and ARM64, and a corrupted download was refused.
- **Static analysis:** PSScriptAnalyzer found no issues, including syntax compatibility with Windows PowerShell 5.1.

Not tested; please check on kevin-Mini:
- The service starting at boot as LocalService.
- The firewall rule and network-profile handling.
- Name resolution (`kevin-Mini`, `kevin-mini.local`) from your devices.
- Running under Windows PowerShell 5.1 itself, not just its syntax.
