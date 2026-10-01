# 07 — Building the Repeater

> 👤 **Author:** Nipun Methmal · Part 7 of 9 · [← Index](../README.md) · [Next →](08-verification.md)

The goal: pull internet from an existing Wi‑Fi network and re-broadcast it as **`<AP_SSID>`**, so
phones and PCs can join it and get online. Classic range-extender behaviour, on hardware we now
fully control.

## The design decision

The P11IDU has **one 2.4 GHz radio**. It must be both client and access point.

| Approach | Extra packages | Subnet | Complexity |
|---|---|---|---|
| **A. NAT repeater** *(chosen)* | **none** | Clients get their own `192.168.8.0/24` | Low |
| B. L2 relay (`relayd`) | `relayd` | Same subnet as upstream | Medium — and flaky on one radio |

**Chosen: A.** STA and AP on the same radio, same channel, uplink on `wwan` with DHCP, masquerade
`lan → wwan`. It needs no packages that aren't already in the image, and double NAT is irrelevant
to a phone that just wants to load a webpage.

The one unavoidable cost of a single radio: **both interfaces share a channel**, so the AP cannot be
on a different channel than the uplink. This turns out to be an advantage — see
[Automatic channel following](#automatic-channel-following).

## Topology

```
radio0 (single 2.4 GHz radio, one channel)
   ├── phy0-sta0  mode=sta  → network 'wwan'  → DHCP from upstream → 192.168.1.102
   └── phy0-ap0   mode=ap   → network 'lan'   → <AP_SSID>          → 192.168.8.1

br-lan = eth0.1 + phy0-ap0         (192.168.8.0/24, DHCP .100–.249)
firewall: zone 'lan' → zone 'wan'  (masquerade on)
```

## Step 0 — Back up

```sh
cp /etc/config/wireless  /root/wireless.bak
cp /etc/config/network   /root/network.bak
cp /etc/config/firewall  /root/firewall.bak
```

## Step 1 — Add the client interface

A second `wifi-iface` on the existing `radio0`:

```uci
config wifi-iface 'sta0'
        option device 'radio0'
        option network 'wwan'
        option mode 'sta'
        option ssid     '<UPSTREAM_SSID>'
        option encryption 'psk2'
        option key     '<UPSTREAM_PSK>'
```

Check it associated:

```sh
iw dev phy0-sta0 link
# Connected to <bssid> (on phy0-sta0)  SSID: …  freq: 2462.0  signal: -34 dBm
```

Signal strength matters here — if the uplink is weak, everything downstream inherits that weakness.
Ours sat at **−34 dBm**, which is excellent.

## Step 2 — The uplink interface

```uci
config interface 'wwan'
        option device 'phy0-sta0'
        option proto 'dhcp'
```

`netifd` names the device `phy0-sta0` (the wifi device name, not `wlan0`) on modern OpenWrt — using
`wlan0` here is the single most common mistake in this setup.

```sh
ifstatus wwan
# "up": true, "address": "192.168.1.102", "nexthop": "192.168.1.1"
```

## Step 3 — Firewall: masquerade out of `wwan`

Add `wwan` to the existing `wan` zone (which already has `masq '1'`):

```sh
uci add_list firewall.@zone[1].network='wwan'
```

Which yields:

```uci
config zone
        option name 'wan'
        list network 'wan'
        list network 'wan6'
        list network 'wwan'
        option input   'REJECT'
        option output  'ACCEPT'
        option forward 'REJECT'
        option masq    '1'
        option mtu_fix '1'

config forwarding
        option src  'lan'
        option dest 'wan'
```

That single `masq '1'` is the entire NAT implementation — `fw4` compiles it into an `nft`
postrouting `srcnat` rule.

> ⚠️ The chain is called **`srcnat`**, not `postrouting`:
> ```sh
 > nft list chain inet fw4 srcnat
 > ```
> Read the ruleset before you assume a name.

## Step 4 — Radio settings

```uci
config wifi-device 'radio0'
        option type       'mac80211'
        option path       'platform/10300000.wmac'
        option band       '2g'
        option channel    '11'
        option htmode     'HT40'
        option txpower    '20'
        option cell_density '0'
        option disabled   '0'
```

`channel` is a *starting point*: once `phy0-sta0` associates, the driver locks the whole radio to the
uplink's channel. The AP follows automatically.

`HT40` in the config is similarly advisory — with the STA attached, the link negotiates **HT20** to
match the upstream, which is correct:

```sh
iwinfo phy0-ap0 info
# Mode: Master  Channel: 10 (2.457 GHz)  HT Mode: HT20
```

### Automatic channel following

The home router moved from **channel 11 → channel 10** mid-project. Without any intervention:

```
phy0-sta0: freq 2462.0 (ch 11)   →   freq 2457.0 (ch 10)
phy0-ap0:  Channel 11            →   Channel 10
```

Both interfaces are on the same `radio0`, so the kernel moves them together and clients reconnect
transparently. This is the main practical advantage of the single-radio design — the extender can
never end up on the wrong channel.

## Step 5 — The access point

```uci
config wifi-iface 'default_radio0'
        option device     'radio0'
        option network    'lan'
        option mode       'ap'
        option ssid       '<AP_SSID>'
        option encryption 'psk2'
        option key        '<AP_KEY>'
```

Use `psk2` (WPA2-CCMP). **Do not use `sae`/`psk2+sae`** unless every client you care about supports
WPA3 — a mixed mode is the safe compromise if you need it.

## Step 6 — DNS: make sure only the working resolver survives

If `wwan` uses DHCP, `dnsmasq` reads `/tmp/resolv.conf.d/resolv.conf.auto`. Two things go wrong here:

1. `peerdns` on a *dead* interface injects a nameserver that never answers.
2. A leftover static `option dns` does the same.

Both are removed:

```sh
uci set network.wan.peerdns='0'
uci -q delete network.wan.dns
uci commit network
```

The result — **one** nameserver, the one that works:

```
$ cat /tmp/resolv.conf.d/resolv.conf.auto
# Interface wwan
nameserver 192.168.1.1
```

Verify locally rather than trusting it:

```sh
nslookup openwrt.org     # answered by dnsmasq on the device
```

## Step 7 — The dead wired `wan`

The config inherited from stock has a static `wan` on `eth0.2` (`172.19.2.2` → gateway
`172.19.2.254`) for an outdoor unit that **is not attached**. Left enabled it installs a second
default route that blackholes traffic when it wins, and pollutes the resolver list.

```sh
uci set network.wan.disabled='1'
uci set network.wan6.disabled='1'
uci commit network
```

The route table afterwards is unambiguous:

```
default via 192.168.1.1 dev phy0-sta0  src 192.168.1.102
192.168.1.0/24 dev phy0-sta0 scope link  src 192.168.1.102
192.168.8.0/24 dev br-lan scope link  src 192.168.8.1
```

If you ever reconnect the outdoor unit:

```sh
uci -q delete network.wan.disabled
uci -q delete network.wan6.disabled
uci commit network && service network reload
```

## Step 8 — A small nicety: link LED

Make the WAN LED track the uplink instead of the (disabled) wired port:

```uci
config led
        option sysfs   'green:wan'
        option trigger 'netdev'
        option dev     'phy0-sta0'
        list mode      'link'
```

## Step 9 — Apply

**Always put the reload last** — it restarts the network stack and will drop an open telnet session:

```sh
uci commit
service network reload
```

Run the reload as the final command in a block, expect the session to die, and reconnect to verify.

## Everything at once

The complete exported configuration from the live device is in
[`configs/`](../configs/) — `wireless`, `network`, `firewall`, `dhcp` and `system`, sanitised of
credentials but otherwise byte-for-byte what is running. Apply them with:

```sh
# on the device, after editing the placeholders
uci import < configs/network.txt && uci commit network
```

---

> 📖 Next: [08 — Verification](08-verification.md)

---
> ✍️ © 2026 **Nipun Methmal** · MIT License · *p11idu-openwrt-repeater*
