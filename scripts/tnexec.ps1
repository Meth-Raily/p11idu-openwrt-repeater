<#
    tnexec.ps1 — Telnet command executor for the P11IDU / OpenWrt

    Author : Nipun Methmal (c) 2026 — MIT License
    Part of: p11idu-openwrt-repeater

    Runs a command block on the router over telnet and returns its output.

    - Strips telnet IAC negotiation byte sequences
    - Handles the login: / Password: handshake automatically
    - Waits on a unique marker + exit code so it knows when the shell is REALLY done
    - Accepts multi-line command blocks (pass them as a here-string from a .ps1 file)

    Credentials are NEVER stored in this file. Pass -Pass, or set $env:P11_PASS.

    Usage:
        $env:P11_PASS = 'your-router-password'
        & tnexec.ps1 -Command 'ip route'

        $cmd = @'
        ifstatus wwan
        ip route get 1.1.1.1
        '@
        & tnexec.ps1 -Command $cmd -CmdTimeout 45000

    Gotchas (learned the hard way — see docs/05-root-shell.md):
      * Run this from a .ps1 file when the command contains quotes or pipes. Passing a
        quoted string as a PowerShell -Command argument loses the inner double quotes.
      * 'service network reload' may drop the session — always put a reload LAST.
#>
param(
    [string]$Router    = '192.168.8.1',
    [int]   $Port      = 23,
    [string]$User      = 'root',
    [string]$Pass      = '',                       # falls back to $env:P11_PASS, then prompts
    [string]$Command   = 'uname -a; cat /etc/openwrt_release',
    [int]   $CmdTimeout = 30000,
    [switch]$KeepOpen
)
$ErrorActionPreference = 'Stop'

if (-not $Pass) { $Pass = $env:P11_PASS }
if (-not $Pass) {
    $sec = Read-Host -AsSecureString "Password for ${User}@${Router}"
    $Pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}

function Strip-Iac([byte[]]$tmp, [int]$n) {
    $out = New-Object byte[] $n
    $len = 0
    $i = 0
    while ($i -lt $n) {
        $b = $tmp[$i]
        if ($b -eq 255) {
            if ($i + 1 -ge $n) { break }
            $c = $tmp[$i + 1]
            if ($c -eq 255) { $out[$len] = 255; $len++; $i += 2; continue }
            if ($c -ge 251 -and $c -le 254) { $i += 3; continue }   # WILL/WONT/DO/DONT + option
            if ($c -eq 250) {                                        # SB ... SE
                $i += 2
                while ($i -lt $n -and $tmp[$i] -ne 240) { $i++ }
                if ($i -lt $n) { $i++ }
                continue
            }
            $i += 2
            continue
        }
        $out[$len] = $b; $len++; $i++
    }
    return ,@($out, $len)
}

function Read-Until($s, [string]$pattern, [int]$ms) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $buf = New-Object Text.StringBuilder
    $tmp = New-Object byte[] 4096
    $rx = [regex]$pattern
    while ($sw.ElapsedMilliseconds -lt $ms) {
        if ($s.DataAvailable) {
            $n = $s.Read($tmp, 0, $tmp.Length)
            if ($n -le 0) { break }
            $r = Strip-Iac $tmp $n
            if ($r[1] -gt 0) { [void]$buf.Append([Text.Encoding]::ASCII.GetString($r[0], 0, $r[1])) }
            if ($rx.IsMatch($buf.ToString())) { break }
        } else {
            Start-Sleep -Milliseconds 20
        }
    }
    return $buf.ToString()
}

function Send-Line($s, [string]$line) {
    $b = [Text.Encoding]::ASCII.GetBytes($line + "`r`n")
    $s.Write($b, 0, $b.Length)
    $s.Flush()
}

$tcp = New-Object Net.Sockets.TcpClient
$tcp.Connect($Router, $Port)
$s = $tcp.GetStream()
$banner = Read-Until $s '(?i)login:|assword:|[$#] $|[$#] $' 8000

$auth = $banner
if ($banner -match '(?i)login:') {
    Send-Line $s $User
    $auth += Read-Until $s '(?i)assword:' 8000
    if ($auth -match '(?i)assword:') {
        Send-Line $s $Pass
        $auth += Read-Until $s '(?m)[@$#].*[$#] $|Login incorrect' 10000
    }
} elseif ($banner -match '(?i)assword:') {
    Send-Line $s $Pass
    $auth += Read-Until $s '(?m)[@$#].*[$#] $|Login incorrect' 10000
} else {
    $auth += Read-Until $s '(?m)[@$#].*[$#] $' 5000
}

if ($auth -match 'Login incorrect') {
    Write-Output 'AUTH FAILED'
    Write-Output $auth
    $tcp.Close()
    exit 2
}

$marker = '__M' + (Get-Random -Maximum 99999) + '__'
Send-Line $s ("{0}; echo {1}$?" -f $Command, $marker)
$out = Read-Until $s ('(?m)' + [regex]::Escape($marker) + '\d+') $CmdTimeout

Write-Output '--- OUTPUT ---'
Write-Output $out

if ($KeepOpen) {
    Write-Output '--- (kept open: session id ' + $s.GetHashCode() + ') ---'
} else {
    try { Send-Line $s 'exit' } catch { }
    Start-Sleep -Milliseconds 200
    $tcp.Close()
}
