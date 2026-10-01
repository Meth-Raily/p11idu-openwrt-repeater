<#
    verify-repeater.ps1 — Full health check for the P11IDU NAT repeater.

    Author : Nipun Methmal (c) 2026 — MIT License
    Part of: p11idu-openwrt-repeater
    See     : docs/08-verification.md

    Checks, over telnet, in one shot:
      * uplink association (SSID / freq / signal)
      * wwan state and address
      * route table + ip route get 1.1.1.1   (must be a single default via the STA)
      * resolver file                        (must list ONLY the working upstream DNS)
      * AP info                              (SSID, channel, HT mode)
      * attached Wi-Fi stations
      * DHCP leases
      * nft masquerade rule

    Set $env:P11_PASS before running (see tnexec.ps1).

    Usage:
        $env:P11_PASS = '...'
        & verify-repeater.ps1
        & verify-repeater.ps1 -OutFile .\repeater-state.txt
#>
param(
    [string]$Router  = '192.168.8.1',
    [string]$OutFile = ''
)
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$tnexec = Join-Path $here 'tnexec.ps1'

$cmd = @'
echo ===UPLINK==
iw dev phy0-sta0 link | head -6
echo ===WWAN==
ifstatus wwan | grep -E '"up"|uptime|192.168.1|nexthop'
echo ===ROUTES==
ip route
echo ===ROUTE_GET==
ip route get 1.1.1.1
echo ===DNS==
cat /tmp/resolv.conf.d/resolv.conf.auto
echo ===AP==
iwinfo phy0-ap0 info | head -5
echo ===STATIONS==
iw dev phy0-ap0 station dump | grep Station
echo ===LEASES==
cat /tmp/dhcp.leases
echo ===NAT_RULE==
nft list ruleset | grep -E 'masquerade' | head -5
echo ===WAN_DISABLED==
uci -q get network.wan.disabled
'@

$out = & $tnexec -Router $Router -Command $cmd -CmdTimeout 60000

$text = ($out | Out-String)
Write-Output $text
if ($OutFile) {
    $text | Set-Content -Path $OutFile -Encoding UTF8
    "SAVED: $OutFile"
}

# --- verdict ---------------------------------------------------------------
$fail = @()
if ($text -notmatch 'default via .* dev phy0-sta0') { $fail += 'no default route via the STA link' }
if (($text -split '===DNS===')[1] -notmatch 'nameserver') { $fail += 'no nameserver in resolv.conf.auto' }
if (($text -split '===DNS===')[1] -match '172\.19\.2\.')   { $fail += 'dead wired WAN DNS still present' }
if ($text -notmatch '"up": true')                          { $fail += 'wwan is not up' }
if ($text -notmatch 'masquerade')                          { $fail += 'no masquerade rule found' }

""
if ($fail.Count -eq 0) {
    "RESULT: PASS  — repeater is healthy"
} else {
    "RESULT: FAIL"
    $fail | ForEach-Object { "  - $_" }
}
