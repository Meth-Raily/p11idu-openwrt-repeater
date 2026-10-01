# 09 — Is This an L3 Switch?

> 👤 **Author:** Nipun Methmal · Part 9 of 9 · [← Index](../README.md)

Short answer: **no.** It is a **NAT router / wireless repeater with an L2 switch on its LAN side.**

That is a good thing to be — it just isn't an L3 switch, and it isn't stackable either.

## What it actually is

```
        ┌─────────────────────────────────────────────┐
 upstream│            Tozed P11IDU                    │
   ┌─────┤                                             │
   │     │  wwan 192.168.1.102 ── NAT / masquerade ────┼──► the ONLY L3 boundary
   │     │                                             │
   │     │  lan 192.168.8.1                           │
   │     │   ├ eth0.1  (VLAN 1: ports 0,1,3)  ────────┤  hardware L2 switch
   │     │   └ phy0-ap0 (<AP_SSID>)            ────────┤  same L2 domain
   │     │   VLAN 2 (ports 2,4) ── disabled            │
   │     └─────────────────────────────────────────────┘
   │
  clients on 192.168.8.0/24
```

| Claim | Verdict | Why |
|---|---|---|
| **It switches** | ✅ Yes (L2) | The MT7628AN's built-in `rt305x-esw` bridges ports 0/1/3 and the AP in hardware, VLAN 1 |
| **It routes** | ✅ Yes (one boundary) | `lan` ↔ `wwan`, kernel-forwarded |
| **It NATs** | ✅ Yes | `masq '1'` in the `wan` zone |
| **It's an L3 switch** | ❌ No | Only one IP boundary, and it is masqueraded |
| **It's stackable** | ❌ No | Single standalone box; no stacking/MLAG/virtual-chassis exists in OpenWrt for this device |
| **Line-rate switching** | ⚠️ LAN ports only | 10/100 Fast Ethernet; routing is CPU-forwarded |

### Why the masquerade disqualifies it

An L3 switch terminates **multiple** subnets on SVIs (VLAN interfaces) and forwards between them
*transparently* — hosts stay directly reachable from every other subnet.

Here, everything in `192.168.8.0/24` disappears behind `192.168.1.102` when it leaves. A device on
the upstream network cannot initiate a connection to your phone. That is textbook **router**
behaviour, and it is exactly what you want for a home extender.

### The hardware, plainly

```
system type   : MediaTek MT7628AN ver:1 eco:2
cpu model     : MIPS 24KEc V5.2        (~580 MHz, single core)
BogoMIPS      : 385.50
switch        : switch0 (rt305x-esw), ports: 7 (cpu @ 6)
Ethernet      : 10/100 only on user ports
RAM           : 57.40 MiB
```

A real L3 switch forwards in ASIC at line rate with hundreds of megabytes of tables. This forwards
in the Linux kernel on a single MIPS core with 64 MB of RAM. Different class of machine entirely.

## If you want it to become a genuine small L3 switch

It is entirely doable on this hardware. The `wan` interface being disabled leaves `VLAN 2`
(ports 2,4) free as spare capacity.

**1 — Create more VLANs, each tagged to the CPU**

```uci
config switch_vlan
        option device 'switch0'
        option vlan   '10'
        option ports  '6t 0'        # CPU + LAN 1  → 10.0.10.0/24
```

**2 — Add an SVI per subnet**

```uci
config device
        option name 'eth0.10'
        option type 'vlan'
        option ifname 'eth0'
        option vid '10'

config interface 'vlan10'
        option device 'eth0.10'
        option proto  'static'
        option ipaddr '10.0.10.1'
        option netmask '255.255.255.0'
```

**3 — Route without NAT**

Put the VLANs in a zone with inter-zone forwarding allowed and **masquerade off**:

```uci
config zone
        option name    'vlanzone'
        list network   'vlan10'
        list network   'vlan20'
        option input   'ACCEPT'
        option forward 'ACCEPT'
        option masq    '0'      # ← the whole point
```

**4 — Accept the trade-offs**

| | |
|---|---|
| Inter-VLAN routing | CPU-forwarded, roughly **50–90 Mbps** on this SoC, not line rate |
| Ports | 10/100 — a gigabit L3 switch would immediately expose this |
| RAM | 64 MB total; large routing tables aren't happening |
| Reachable from upstream | ✅ yes, once NAT is off — which also means you must firewall properly |

If you only need "my phone can reach my NAS on a different VLAN", this works well. If you need
wire-speed inter-VLAN switching for a busy network, buy a switch that does it in hardware.

## Summary

The P11IDU, as configured in this project, is:

- a **wireless repeater** (STA + AP on one radio, same channel),
- sitting behind a **NAT boundary** to the upstream network,
- with a **hardware L2 switch** serving its LAN ports and Wi‑Fi clients,
- **not** stackable, **not** an L3 switch — but convertible into a small one if you want.

---

> 🔙 [Back to the README](../README.md)

---
> ✍️ © 2026 **Nipun Methmal** · MIT License · *p11idu-openwrt-repeater*
