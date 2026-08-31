# Logitech Harmony IR archive

## AI Disclaimer

I heavily used AI in creating this archive.

## Overview

The infrared control database from Logitech's Harmony universal remotes: **276,236
devices** from **7,889 manufacturers**, **13,293,293 commands**, and — the half that
usually goes missing — **all 684 of Logitech's own IR protocol definitions**.

Harmony is mostly discontinued and this data lived only on Logitech's servers.
Everything here is plain JSON. Nothing in it needs a Logitech service, an account,
or any tooling beyond what is in this repository.

Every command carries the original Harmony **keycode** and, for the 13,290,985 that
are infrared and well-formed, a ready-to-send **Pronto Hex** string. Every protocol carries
Logitech's original definition — carrier, header, per-bit waveform, framing, repeat
structure — so any command in the archive can be recompiled to a waveform from first
principles, by you, without trusting our rendering.

---

## Contents

```
manifest.json                    counts, schema version, build date
index.json                       every manufacturer
devices/<Manufacturer>/index.json    every model that manufacturer has
devices/<Manufacturer>/<Model>.json  one device: identity + a pointer to its code set
codesets/<xx>/<hash>.json        one command set, shared by every device that has it
protocols/index.json             every protocol
protocols/<Protocol_Name>.json   one protocol definition
index.html                       a lookup page (open it or serve it; see below)
rehydrate.py, rehydrate.ps1      write device files with their commands inlined
```

**Why code sets are separate.** 79% of devices have a byte-identical command set:
276,236 devices resolve to 54,118 distinct sets. Storing each set once takes the
tree from ~5.8 GB to ~0.8 GB. `rehydrate.py` or `rehydrate.ps1` undoes it if you
would rather have one fat file per device.

## Schema

### `manifest.json`

| field | meaning |
|---|---|
| `schemaVersion` | bumped on any breaking field change — pin it if you parse this |
| `generated` | build date, `YYYY-MM-DD` |
| `source` | where the data came from |
| `counts` | `manufacturers`, `devices`, `devicesWithCodes`, `commands`, `commandsWithPronto`, `codesets`, `protocols` |
| `layout` | the three path patterns, so a consumer never hard-codes them |
| `notes` | rendering caveats that apply to the whole archive |

### `devices/<Manufacturer>/<Model>.json`

```json
{"manufacturer": "Sony",
 "model": "CDP222ES",
 "globalDeviceId": 744,
 "deviceType": 3,
 "codeset": "codesets/41/41c7c832e76a05cd.json"}
```

| field | meaning |
|---|---|
| `manufacturer`, `model` | **verbatim as Logitech spells them.** The filename is only an address (see *Filenames*) — always read the name from inside the file |
| `globalDeviceId` | Logitech's permanent catalogue id, and this file's stable identity |
| `deviceType` | Logitech's device-type code (1 TV, 2 VCR, 3 CD, 4 DVD, …) |
| `codeset` | path to this device's command set, **relative to the archive root** — or `null` for a device Logitech lists with no commands |

`codeset` holds a path, not a bare hash, so nothing downstream needs to know the
sharding rule.

### `codesets/<xx>/<hash>.json`

```json
{"commands": [
  {"name": "NextTrack",
   "protocol": "Sony 12 Bit",
   "keycode": "G:Sony 12 Bit:()(0x8D1)():3",
   "pronto": "0000 0068 000D 0000 0060 0018 0030 …"}
]}
```

| field | meaning |
|---|---|
| `name` | the command's name, as Logitech ships it |
| `protocol` | Logitech's **canonical** protocol name — always resolves to a file in `protocols/`. The keycode's own spelling of it sometimes differs in case or spacing |
| `keycode` | the original Harmony keycode, always present |
| `pronto` | Pronto Hex (learned/CCF format `0000`). **Absent** — never null, never a placeholder — where the protocol is not infrared |
| `prontoRepeat` | present only when the transmission wraps a looping burst in a lead-in or trailer: the repeat burst alone, as its own Pronto string |

`pronto` is a complete two-section Pronto: `0000 <freq> <once pairs> <repeat pairs>`
followed by the once bursts and then the repeat bursts. A player sends section one,
then loops section two while the key is held. When there is no separate repeat burst
the repeat-pair count is `0000` and the string is a plain single-sequence Pronto.
`prontoRepeat` is a convenience for tools that accept only one sequence: the same
repeat bursts as a standalone `0000 <freq> 0000 <repeat pairs>` string.

`hash` is the first 16 hex characters of the SHA-1 of the command set. It is
computed over `name`, a NUL byte, `keycode` and a newline for each command, with
commands sorted by `(name, keycode)` — order-independent and stable, and it depends
only on Logitech's data, never on our rendering.

The `<xx>` directory is the first two characters of the hash; it exists only to keep
any one directory under a few hundred entries.

### `protocols/<Protocol_Name>.json`

```json
{"name": "Philips RC5 13 Bit Toggle",
 "logitechProtocolId": 674,
 "carrierHz": 36000,
 "standardProtocol": "RC5",
 "irp": "{36.0k,msb}<889u,-889u|-889u,889u>(889u,Code0A:1,T:1,Code0B:11,^113792u)*",
 "keycodeFields": {"Code0": {"sequence": "repeat", "token": 0, "segment": "0",
                             "bits": 13, "toggleBit": 1}},
 "pressMinimumRepeats": null,
 "definition": { }}
```

| field | meaning |
|---|---|
| `name` | Logitech's canonical name — what a command's `protocol` field holds |
| `logitechProtocolId` | Logitech's internal protocol id |
| `carrierHz` | carrier frequency in Hz. 192 distinct values appear, from 30 kHz to 455 kHz — this is not a 38 kHz-with-rounding database |
| `standardProtocol` | the name IrpTransmogrifier gives one generated waveform from this protocol (`NEC1`, `RC5`, `Kaseikyo`, …), or `null` where it does not decode. Informational; the definition is authoritative |
| `irp` | the definition rendered as an [IRP](http://hifi-remote.com/wiki/index.php/IRP_Notation) string, or `null` for a non-IR protocol |
| `keycodeFields` | which keycode group, token and segment feeds each `CodeN` field of the IRP, its width, and the toggle-bit position if it has one |
| `pressMinimumRepeats` | how many times Logitech's own remote repeats a single press |
| `definition` | **Logitech's original JSON, verbatim.** The primary source, and the reason this archive outlives our tooling |

## The keycode, and how a definition becomes a waveform

A keycode is the whole command. Everything else in the archive is derived from it
plus a protocol definition.

```
G:<protocol name>:(<start>)(<repeat>)(<finish>):<trailer>
G:Sony 12 Bit:()(0x8D1)():3
G:JVC 16 Bit:(Start)(0xC004)():3
```

- The three parenthesised groups are IRP's intro / repeat / ending sequences. Each
  splits on `_` into **segment tokens**; an empty group has none.
- A token is either `<segment id>x<hex value>` — the `x` sits at index 1, so plain
  `0x750` *is* segment `"0"` carrying the value `750` — or a bare segment id naming
  a fixed (literal) segment, such as `Start` or `Repeat`.
- The trailing number after the last colon is Logitech's repeat hint, not part of
  the waveform.

The protocol definition supplies the rest.

- **Segments.** Each entry in the definition's `IRSegments` (encoded) and
  `CodeSegments` (fixed literal) is filed under a short id taken from its `Name`:
  equal to the protocol name → `"0"`; containing `KeyCode` → the text after
  `KeyCode` (so `Toshiba 32 Bit KeyCodeRepeat` → `"Repeat"`); otherwise the text
  after `"<protocol name> "`.
- **Bits.** `EncodingType` 0 or 1: each hex character of the token's value
  contributes 4 bits, **most significant first**, in written order. `EncodingType`
  2 or 3: each hex character is **one symbol** — these are the quaternary "N Bit
  Quad" protocols. The bit list is then left-padded with zeros to `NumberOfBits`,
  or has *leading* bits dropped if the value is wider.
- **Toggle.** If the payload names a `ToggleBit`, that one bit position is
  overwritten with a counter that alternates between presses. Nothing else moves.
- **Playout.** For each segment: the `Header` atoms, then one
  `Encodings[BitType].Atoms` list per bit, then the `Trailer` atoms, then a space of
  `TotalLength - (header + data + trailer)` if that is positive. An atom's `Type` is
  `1` for a mark (carrier on) and `0` for a space, and `Value` is microseconds.
- **Assembly.** Play the start group's segments, then the repeat group's, then the
  finish group's. Merge adjacent same-level runs and drop any leading space: the
  result is the microsecond mark/space waveform, and the carrier is
  `CarrierFrequency`.

The `pronto` field here is that full start+repeat+finish transmission. `prontoRepeat`
is the repeat group alone, and it is only emitted when a start or finish group
exists — otherwise it would just repeat `pronto`.

> If you write your own renderer, do **not** take "the first non-empty group" as the
> data. For 4.81% of commands (~639,000, across 38 protocols) the first non-empty
> group is framing: `G:JVC 16 Bit:(Start)(0xC004)()` yields a lead-in carrying no
> payload, which no decoder can read. `JVC 16 Bit` alone is ~472,000 commands.

## Caveats

**The toggle bit is always 0.** Every waveform here is rendered with the toggle bit
at zero. Protocols that have one (RC5 and its many relatives — look for `toggleBit`
in the protocol's `keycodeFields`) expect that bit to *alternate* between consecutive
presses. Send the same Pronto twice to such a device and the second press may be
ignored as a repeat. Flip the bit yourself for a second press: its position is in the
protocol file.

**2,247 commands have no `pronto`, and never can.** They keep their `keycode` and
their `protocol`; the field is simply absent.

| protocol | commands | why |
|---|---|---|
| `ATI 21 Bit` | 2,067 | carrier is 433 MHz — a radio remote, not infrared |
| `HID 16 Bit` | 109 | USB HID keyboard control |
| `Sonos IP` | 52 | network control |
| `Roku IP` | 19 | network control |

Logitech's service types all four as `IrProtocol`, but the last three carry no
segments and a zero carrier, and the first is out of any IR transmitter's reach.
This is not a gap in the data.

**A further 61 commands have a keycode Logitech's own database has corrupted**, and
they lose `pronto` for the same reason: there is nothing to render. All 61 come from
46 distinct keycodes, in four shapes — a doubled prefix (`0x0x020122_1x0_2x2120030`),
a stray trailing character (`0x00FF48B7v`), a missing leading digit (`xB6BA20DF`),
and a group naming a segment the protocol does not define
(`G:MemorexO1 32 Bit:(0x7689906F)(Repeat)()`, where `MemorexO1 32 Bit` has no
`Repeat` segment). They are preserved exactly as Logitech serves them, so anyone who
works out what was meant can render them later.

**18,516 devices have no commands.** They are recorded as stubs with
`"codeset": null`. They are genuinely empty catalogue entries rather than missing
data, and they are here so that nothing has to keep re-checking them.

## Filenames

Filenames are addresses, not data. Read `manufacturer` and `model` from inside the
file — the archive is checked out on Windows and macOS too, so names are normalised:

- Unicode is NFKC-normalised and stripped of combining marks (`Alizé` → `Alize`,
  `２５Ｓ９９` → `25S99`).
- Anything outside `A-Za-z0-9._-` becomes `_`; runs collapse; leading and trailing
  `_ . -` and spaces are trimmed.
- Windows reserved names get a trailing `_` — `AUX` is a real manufacturer here.
- Remaining collisions, compared case-insensitively so a checkout on a
  case-insensitive filesystem is safe, are resolved by appending `-<globalDeviceId>`
  for a device and `-2`, `-3`, … for a manufacturer directory.

An address, once assigned, is never recomputed. If Logitech re-spells a model, the
file stays where it is and only the `model` field inside it changes.

## Looking something up

**The page.** `index.html` is a single vanilla-JS file with no build step, no CDN
and no dependencies. It reads the archive two ways.

*Double-click it.* Browsers block `fetch()` on `file://`, so the page instead offers
an **Open archive folder…** button: pick the folder holding `manifest.json` and it
reads the files where they sit. Nothing is uploaded and nothing is copied — looking
up one device opens about seven files out of the 338,935 in the tree. This needs a
browser with the File System Access API: Chrome, Edge, Opera, Brave and other
Chromium browsers have it; Firefox and Safari do not.

*Or serve the folder* and open it over `http://`, which works in every browser. Any
of these, run from the archive root, will do it — use whichever you already have:

```sh
npx --yes serve                 # Node
php -S localhost:8000           # PHP
ruby -run -e httpd . -p 8000    # Ruby
busybox httpd -f -p 8000        # busybox
python3 -m http.server 8000     # Python
```

Editors help too: VS Code's Live Server extension serves the open folder in a click.
And if the archive is published on a static host or your forge's pages service, the
page just works at that URL with nothing installed at all.

**By hand.**

```sh
jq -r '.[] | select(.n=="Sony") | .s' index.json           # -> Sony
jq -r '.[] | select(.m=="CDP222ES") | .f' devices/Sony/index.json
jq . devices/Sony/CDP222ES.json
jq -r '.commands[] | "\(.name)\t\(.pronto)"' \
   "$(jq -r .codeset devices/Sony/CDP222ES.json)"
```

**Rehydrated.** `rehydrate.py` writes device files with their commands inlined, so
each output file is self-contained:

```sh
python3 rehydrate.py --manufacturer Sony --out /tmp/sony
python3 rehydrate.py --model-file my-devices.txt --out /tmp/mine
python3 rehydrate.py --all --out /tmp/everything      # ~5.8 GB, 276,236 files
```

`rehydrate.ps1` is the same forty lines for PowerShell. Windows' built-in PowerShell
5.1 parses JSON slowly — fine for one manufacturer; use Python or PowerShell 7 for
anything larger.

## Acknowledgements

A massive thank you to the following projects:

- Flipper-IRDB – https://github.com/Lucaslhm/Flipper-IRDB
- IrScrutinizer – https://github.com/bengtmartensson/IrScrutinizer
- IrpTransmogrifier – https://github.com/bengtmartensson/IrpTransmogrifier
- MakeHex – https://github.com/probonopd/MakeHex
- irdb – https://github.com/probonopd/irdb
- Remote Central – https://www.remotecentral.com/cgi-bin/codes/
- harmony-hub-root – https://github.com/Ripthulhu/harmony-hub-root

Your work was invaluable in getting this archive created and the Pronto codes validated (hopefully).

## Licence

My contributions to this archive, the Pronto conversions, the schema, and the
organization of the data, are released under CC0 1.0 Universal.

The underlying IR codes and protocol definitions originate with Logitech. I make no
representation about their copyright status and I'm not in a position to license them.
CC0 waives my rights, not anyone else's. If you're building something commercial on
this, evaluate that yourself.

See `LICENSE` for the full CC0 1.0 Universal text.
