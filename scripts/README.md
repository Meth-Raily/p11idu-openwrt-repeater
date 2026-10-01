# Scripts

> 👤 **Author:** Nipun Methmal · MIT License

PowerShell helpers actually used during this project. **No credentials are stored in any of these
files** — both passwords come from environment variables (or a prompt):

| Variable | Used by | What it is |
|---|---|---|
| `$env:P11_PASS` | `tnexec.ps1` | root password on the **OpenWrt** device (telnet/SSH) |
| `$env:P11_WEB_PASS` | `web-login.ps1` | `admin` account password on the **stock** web UI |

```powershell
$env:P11_PASS      = 'your-router-root-password'
$env:P11_WEB_PASS  = 'your-stock-web-admin-password'   # not the factory default
```

| Script | Purpose | Doc |
|---|---|---|
| [`tnexec.ps1`](tnexec.ps1) | **The workhorse.** Run a command block over telnet, strip IAC, wait on a marker, return output | [05](../docs/05-root-shell.md) |
| [`web-login.ps1`](web-login.ps1) | Log in to the stock API (`cmd=100`) and save the session token | [04](../docs/04-rce-cmd-145.md) |
| [`p145-inject.ps1`](p145-inject.ps1) | Proof of concept for the `pingUrl` injection — run a command, read the output back, or spawn a shell | [04](../docs/04-rce-cmd-145.md) |
| [`verify-repeater.ps1`](verify-repeater.ps1) | Full health check of the finished repeater, with a PASS/FAIL verdict | [08](../docs/08-verification.md) |
| [`md5crypt-cracker.cs`](md5crypt-cracker.cs) | Validated md5crypt (`$1$`) cracker — 3/3 known-answer vectors passing | [01](../docs/01-hardware-and-attack-surface.md) |

## Typical session

```powershell
# 1. shell on the stock device (docs 04 → 05)
.\web-login.ps1 -Password $env:P11_WEB_PASS -OutFile .\sid.txt
.\p145-inject.ps1 -SessionId (Get-Content .\sid.txt) -Command 'id'
.\p145-inject.ps1 -SessionId (Get-Content .\sid.txt) -SpawnTelnet

# 2. everything after that
.\tnexec.ps1 -Command 'ubus call system board'
.\tnexec.ps1 -Command 'ip route; cat /tmp/resolv.conf.d/resolv.conf.auto'

# 3. once OpenWrt is up and the repeater is configured
.\verify-repeater.ps1
```

## Notes and gotchas

- **Multi-line commands:** put them in a here-string inside a `.ps1` file. Passing a quoted
  command as a PowerShell `-Command` argument can lose inner double quotes, and the remote shell
  then sees unquoted `|` — which produces `-ash: not found`.
- **`service network reload`** restarts the stack and frequently drops the session. Make it the
  last command in a block and expect to reconnect.
- **`nft` chain names:** the postrouting/NAT chain in `fw4` is `srcnat`, not `postrouting`.
  Read the ruleset first: `nft list ruleset`.
- **Connectivity tests:** ICMP to the internet is filtered by the upstream carrier. Use TCP
  (`Test-NetConnection -Port 443`) or HTTP instead of ping.

## Scope

The scripts that touch the stock firmware exist because **the author owns this device** and was
re-purposing it. Do not run them against equipment you do not have permission to test.

---

> ✍️ © 2026 **Nipun Methmal** · MIT License · *p11idu-openwrt-repeater*
