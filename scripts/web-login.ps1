<#
    web-login.ps1 — Log in to the stock Tozed web API and save the session token.

    Author : Nipun Methmal (c) 2026 — MIT License
    Part of: p11idu-openwrt-repeater
    See     : docs/04-rce-cmd-145.md

    Stock firmware login is cmd=100 to POST /cgi-bin/lua.cgi. The password is sent as an
    MD5 digest (not plaintext), and the client supplies its own sessionId which the device
    rewrites by appending a server timestamp.

    The account is the stock 'admin' user. The PASSWORD IS NOT the factory default and is
    never stored here — pass it in, or set $env:P11_WEB_PASS. Note that the "MD5 digest"
    travels over plain HTTP, so it protects nothing against anyone capturing LAN traffic.

    Usage:
        $env:P11_WEB_PASS = 'your-web-admin-password'
        & web-login.ps1 -Password $env:P11_WEB_PASS -OutFile .\sid.txt

    Authorised testing on equipment you own only.
#>
param(
    [Parameter(Mandatory = $false)][string]$Password = '',
    [string]$Username = 'admin',
    [string]$HostAddr = '192.168.8.1',
    [string]$OutFile  = ''
)
$ErrorActionPreference = 'Stop'

# Never stored in a file: parameter > $env:P11_WEB_PASS > interactive prompt
if (-not $Password) { $Password = $env:P11_WEB_PASS }
if (-not $Password) {
    $sec = Read-Host -AsSecureString "Password for ${Username}@$HostAddr"
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}

function Get-Md5([string]$s) {
    $md5  = [Security.Cryptography.MD5]::Create()
    $bytes = [Text.Encoding]::UTF8.GetBytes($s)
    ($md5.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
}

$md5pw     = Get-Md5 $Password
$sessionId = Get-Md5 ([guid]::NewGuid().ToString())

# Built via ConvertTo-Json so quoting can't mangle it on the way out
$payload = @{
    cmd       = 100
    method    = 'POST'
    sessionId = $sessionId
    username  = $Username
    passwd    = $md5pw
    language  = 'EN'
} | ConvertTo-Json -Compress

$bh  = [Text.Encoding]::UTF8.GetBytes($payload)
$hdr = "POST /cgi-bin/lua.cgi HTTP/1.1`r`n" +
       "Host: $HostAddr`r`n" +
       "User-Agent: Mozilla/5.0 Chrome/120`r`n" +
       "Accept: */*`r`n" +
       "X-Requested-With: XMLHttpRequest`r`n" +
       "Origin: http://$HostAddr`r`n" +
       "Referer: http://$HostAddr/login.html`r`n" +
       "Content-Type: application/json; charset=UTF-8`r`n" +
       "Content-Length: $($bh.Length)`r`n" +
       "Connection: close`r`n`r`n"

$c = New-Object Net.Sockets.TcpClient
$c.Connect($HostAddr, 80)
$st = $c.GetStream()
$req = [Text.Encoding]::ASCII.GetBytes($hdr) + $bh
$st.Write($req, 0, $req.Length); $st.Flush()

$ms = New-Object IO.MemoryStream
$buf = New-Object byte[] 8192
while ($st.DataAvailable) { $n = $st.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; $ms.Write($buf, 0, $n) }
$c.Close()

$flat  = [Text.Encoding]::UTF8.GetString($ms.ToArray()) -replace "`r`n", ' '
"RESPONSE: $flat"

if ($flat -match '"success"\s*:\s*true') {
    $d = $flat | ConvertFrom-Json
    "SESSION: $($d.sessionId)"
    if ($OutFile) {
        [IO.File]::WriteAllText($OutFile, $d.sessionId)
        "SAVED  : $OutFile"
    }
} else {
    Write-Warning 'Login did not return success:true — check credentials or host.'
    exit 1
}
