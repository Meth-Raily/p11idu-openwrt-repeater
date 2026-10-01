# 08 — Verification

> 👤 **Author:** Nipun Methmal · Part 8 of 9 · [← Index](../README.md) · [Next →](09-is-it-an-l3-switch.md)

A repeater that "seems to work" is not a repeater. Everything below was actually run against the
finished device.

## 1. Routing — exactly one default path

```sh
$ ip route
default via 192.168.1.1 dev phy0-sta0  src 192.168.1.102
192.168.1.0/24 dev phy0-sta0 scope link  src 192.168.1.102
192.168.8.0/24 dev br-lan scope link  src 192.168.8.1

$ ip route get 1.1.1.1
1.1.1.1 via 192.168.1.1 dev phy0-sta0  src 192.168.1.102
```

One default route, out the Wi‑Fi client, with the correct source address. The dead `172.19.2.254`
path is gone.

## 2. DNS — only the working resolver

```sh
$ cat /tmp/resolv.conf.d/resolv.conf.auto
# Interface wwan
nameserver 192.168.1.1
```

```sh
$ nslookup openwrt.org        # resolved by dnsmasq locally
```

## 3. The uplink

```sh
$ ifstatus wwan | grep -E '"up"|uptime|192.168.1|nexthop'
        "up": true,
        "uptime": 1452,
        "address": "192.168.1.102",
        "nexthop": "192.168.1.1",

$ iw dev phy0-sta0 link
Connected to <upstream-bssid> (on phy0-sta0)
        SSID: <UPSTREAM_SSID>
        freq: 2457.0
        RX: 34715301 bytes (27824 packets)
        TX: 2653074 bytes (12695 packets)
        signal: -39 dBm
```

## 4. NAT — watch the packet get rewritten

The decisive test: a client on `192.168.8.0/24` talking to the internet should be SNAT'd to
`192.168.1.102`.

```sh
$ nft list chain inet fw4 srcnat
# … oifname { "phy0-sta0" } masquerade

$ conntrack -L | grep 192.168.8
# 192.168.8.139:49xxx → 173.194.146.225:443  SNAT src=192.168.1.102
```

The client address on the WAN side is `192.168.1.102` — NAT confirmed.

## 5. End-to-end from the PC

```
$ tracert -d 1.1.1.1

Tracing route to 1.1.1.1 over a maximum of 3 hops

  1    <1 ms    <1 ms    <1 ms  192.168.8.1     ← the P11IDU
  2     2 ms     8 ms     2 ms  192.168.1.1     ← the home router
  3     *        *        *     Request timed out.   (ICMP filtered upstream)

Trace complete.
```

```
HTTP  :  http://example.com/      → 200 OK
DNS   :  Resolve-DnsName openwrt.org → 64.226.122.113
TCP   :  Test-NetConnection 1.1.1.1 -Port 443 → True
```

> 💡 ICMP to the internet is filtered by the upstream carrier, so hop 3 timing out is expected.
> Use **TCP or HTTP** to prove connectivity, not ping.

The PC's own path also matters — with both Ethernet and Wi‑Fi connected, Windows must prefer the
repeater:

```powershell
Find-NetRoute -RemoteIPAddress 1.1.1.1
# InterfaceIndex = Ethernet (192.168.8.158 → gw 192.168.8.1)
```

## 6. Clients and leases

```sh
$ iw dev phy0-ap0 station dump | grep Station
Station <client-mac> (on phy0-ap0)

$ cat /tmp/dhcp.leases
…  <client-mac>  192.168.8.139  iPhone      …
…  <pc-mac>      192.168.8.158  <PC_HOST>   …
```

An iPhone pulled **270 MB** through the STA link during ordinary use — it behaved like a normal
router as far as the phone was concerned.

## 7. Reboot persistence — the test that matters

Everything was `uci commit`'d, but committed is not the same as proven. The device was rebooted:

```
$ uptime
 19:35:28 up 3 min,  load average: 1.20, 1.06, 0.45
```

…and **every layer rebuilt itself unaided**:

| Layer | After reboot |
|---|---|
| Radio interfaces | `phy0-sta0` (managed) + `phy0-ap0` (AP) both up |
| STA association | `Connected to <bssid>` — SSID, freq, signal correct |
| `wwan` | `"up": true`, re-acquired `192.168.1.102`, uptime counting |
| Routes | One default via `phy0-sta0`; no `172.19.2.254` |
| DNS | Only `# Interface wwan` |
| AP | `Meth's WIFI`, ch 11, HT20, WPA2 |
| LAN | PC re-leased `192.168.8.158`; PC internet restored immediately |
| `wan`/`wan6` | Still `disabled='1'` — the commit held |

From the PC, *before even touching the console*:

```
HTTP OK status=200
Tracert: 192.168.8.1 → 192.168.1.1 → internet
```

**This is the test to run on any change you make.** If it survives `reboot`, the config is correct.

## 8. Channel change (the unplanned test)

The upstream router changed channel mid-project, from 11 to 10. Both interfaces followed:

```
phy0-sta0: freq 2462.0 (ch 11)  →  2457.0 (ch 10)
phy0-ap0 : Channel 11           →  Channel 10
```

No config change, no manual intervention. The single radio drags the AP along with it.

## 9. Throughput

Measured end-to-end through the repeater, on a weak LTE uplink:

```
DOWNLOAD   22.34 Mbps
UPLOAD      1.32 Mbps
PING          90 ms   (loaded: 290 / 643 ms)
```

Context: the upstream 4G link was reporting **RSRP −110 dBm, SINR 4 dB** — a genuinely marginal
signal. The repeater was not the bottleneck; the radio path to the cell tower was.

> To measure the repeater itself rather than the ISP, run a LAN-to-LAN test (e.g. `iperf3` between
> the PC and a device on the upstream subnet) and compare against a wired baseline.

## 10. Service lifecycle notes

- `service network reload` **drops the telnet session** roughly half the time. Put it last.
- Two full `reload` cycles were run; configuration state was re-verified after each.
- `fw4` logs live under `logread | grep -iE "firewall|fw4"`.

## The reproducible check

[`scripts/verify-repeater.ps1`](../scripts/verify-repeater.ps1) runs the whole battery — routes,
`ip route get`, resolver file, `ifstatus`, AP info, stations, leases — in one shot over telnet.

```powershell
& scripts/verify-repeater.ps1
```

---

> 📖 Next: [09 — Is it an L3 switch?](09-is-it-an-l3-switch.md)

---
> ✍️ © 2026 **Nipun Methmal** · MIT License · *p11idu-openwrt-repeater*
