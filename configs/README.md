# Configurations

> 👤 **Author:** Nipun Methmal · MIT License

Byte-for-byte `uci export` output from the running P11IDU, **sanitised of credentials**. These are
the files described in [docs/07-building-the-repeater.md](../docs/07-building-the-repeater.md).

| File | What it is |
|---|---|
| [`wireless.txt`](wireless.txt) | `radio0` + the AP (`default_radio0`) + the uplink client (`sta0`) |
| [`network.txt`](network.txt) | `br-lan`, `wwan`, the disabled wired `wan`/`wan6`, switch VLANs |
| [`firewall.txt`](firewall.txt) | Zone `wan` with `wwan` attached → masquerade |
| [`dhcp.txt`](dhcp.txt) | dnsmasq + the LAN DHCP pool (`192.168.8.100`, 150 leases, 12 h) |
| [`system.txt`](system.txt) | Hostname, NTP, and the WAN-LED-follows-uplink rule |

## Placeholders

These four values were removed before publishing:

| Placeholder | Meaning |
|---|---|
| `<AP_SSID>` | Your extender's own network name |
| `<AP_KEY>` | Your extender's WPA2 key |
| `<UPSTREAM_SSID>` | The Wi‑Fi network you are repeating |
| `<UPSTREAM_PSK>` | Its WPA2 key |

Replace them in `wireless.txt` before applying. **Do not commit a filled-in copy.**

## Applying

```sh
# on the device
cd /tmp
# ...edit the placeholders first...
uci import < wireless.txt   && uci commit wireless
uci import < network.txt    && uci commit network
uci import < firewall.txt   && uci commit firewall
uci import < dhcp.txt       && uci commit dhcp
uci import < system.txt     && uci commit system

service network reload        # ← will likely drop your telnet session; reconnect after
service firewall reload
```

Prefer surgical edits to a full import if you are changing an already-working device:

```sh
uci set wireless.sta0.key='<UPSTREAM_PSK>'
uci commit wireless
wifi reload
```

> ⚠️ `uci import` **replaces** the whole file. Back up first:
> `cp /etc/config/network /root/network.bak`

## Notes on faithfulness

- The stock `macaddr` overrides on `eth0.1`/`eth0.2` were **omitted** — they are factory-specific
  and would be wrong on any other unit. If your device needs them, read them from
  `cat /sys/class/net/eth0.1/address` on stock firmware before you flash.
- `radio0` is configured as `channel 11` / `HT40`, but with a STA attached the driver locks the
  radio to the uplink's channel and negotiates HT20. See
  [docs/07 § automatic channel following](../docs/07-building-the-repeater.md#automatic-channel-following).
- `wan` / `wan6` are present but `disabled '1'`. They are kept in the config so the outdoor unit
  can be re-enabled later — see [docs/07 step 7](../docs/07-building-the-repeater.md#step-7--the-dead-wired-wan).

---

> ✍️ © 2026 **Nipun Methmal** · MIT License · *p11idu-openwrt-repeater*
