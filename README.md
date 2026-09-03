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

Devices also carry what Logitech knew about *driving* them: how fast they accept
commands, whether power is discrete or a toggle, what their inputs are called and
which command selects each, and how a channel number must be dialled. See *Control*
and *Timing*.

---

## Contents

```
manifest.json                    counts, schema version, build date
index.json                       every manufacturer
devices/<Manufacturer>/index.json    every model that manufacturer has
devices/<Manufacturer>/<Model>.json  one device: identity, how to drive it, and a pointer to its code set
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
| `counts` | `manufacturers`, `devices`, `devicesWithCodes`, `devicesWithTiming`, `devicesWithControl`, `commands`, `commandsWithPronto`, `codesets`, `protocols` |
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
| `timing` | how fast this device can be driven: millisecond delays and repeat counts. See *Timing* |
| `power` | how the device is turned on and off, and — crucially — whether "on" is a distinct command or a toggle. See *Control* |
| `inputs` | its named inputs, the command that selects each one, and the physical ports each is wired to |
| `channelTuning` | how a channel number is dialled: fixed digit width, and any prefix or terminator |
| `states` | the device's internal states, their legal values, and what to send to reach each — what a `{"set": …, "to": …}` action refers to |

`codeset` holds a path, not a bare hash, so nothing downstream needs to know the
sharding rule.

The last five are **absent, never `null` and never `{}`**, on a device Logitech has
nothing to say about — the same convention `pronto` follows. Test with `in` /
`hasOwnProperty`, not for a falsy value. A fuller record:

```json
{"manufacturer": "Magnavox",
 "model": "RJ5540",
 "globalDeviceId": 9,
 "deviceType": 1,
 "codeset": "codesets/aa/aabbccddeeff0011.json",
 "timing": {"interKeyDelay": 100, "interDeviceDelay": 500, "minRepeats": 1},
 "power": {"type": "discrete", "on": ["PowerOn"], "off": ["PowerOff"]},
 "inputs": {"type": 1,
            "list": [{"name": "Tuner", "commands": ["InputTuner"], "ports": ["Antenna"]},
                     {"name": "TV", "commands": ["InputNext", "InputTuner", {"delayMs": 500}]}],
            "next": ["InputNext"]},
 "channelTuning": {"fixedDigits": 2, "finish": ["Enter"]}}
```

### Control

`codesets/` tells you a device *has* a command called `PowerOn`. It does not tell you
that sending it is unsafe, that `InputHdmi1` is the socket the console is plugged
into, or that channel 7 must be dialled as `07`. That is what these four blocks are
for. 251,449 devices (91%) carry at least one.

#### Action lists

Every actionable field — `power.on`, `inputs.next`, an input's `commands`,
`channelTuning.finish`, a state value's `select` — is a **list of steps, in the order
you must perform them**. A step is one of five things:

| step | meaning |
|---|---|
| `"PowerOn"` (a bare string) | send the command with this `name` from the device's code set |
| `{"command": "X", "durationMs": 500}` | send `X` and keep sending it for 500 ms — a press-and-hold |
| `{"hold": "X"}` | hold `X`, with no duration given |
| `{"delayMs": 500}` | send nothing; wait 500 ms before the next step |
| `{"set": "Input", "to": "Antenna"}` | **not a transmission.** The device is now in state `Input` = `Antenna`; record it if you track device state |

So `["InputNext", "InputTuner", {"delayMs": 500}]` means: send `InputNext`, send
`InputTuner`, then wait half a second before doing anything else. A consumer that
ignores everything except the bare strings and `command` fields will still work — it
will just be less careful about timing and state.

The names in `set` / `to` are Logitech's own state labels, and where the device
declares them you will find them in its `states` block, below.

#### `power` — read `type` before you send anything

| field | meaning |
|---|---|
| `type` | `discrete`, `toggle`, `none` or `unknown` |
| `on`, `off` | the action lists for discrete power control |
| `toggle` | the action list that flips power state |
| `onReset` | actions to run after powering on, to put the device in a known state |
| `onResetInput` | the input `onReset` selects, when named |

**`type` is the single most important field in this archive after the codes
themselves.** On a `toggle` device (176,596 of them — the majority) there is exactly
one power command and it flips whatever the current state is. Sending it to "turn the
TV on" turns it *off* half the time. Only `discrete` devices (63,924) have separate
`on` and `off` that are safe to send blind and idempotent.

A device can carry a command *named* `PowerOn` in its code set and still be
`toggle`-behaviour. Trust `type`, not the command name. `none` (35,412 devices) means
no power control at all, and the block is then omitted entirely.

#### `inputs`

| field | meaning |
|---|---|
| `list` | the device's inputs in order, each with a `name`, the `commands` that select it, and the `ports` it is wired to |
| `next`, `previous` | cycle through inputs, for devices with no discrete selection |
| `start`, `finish` | actions to bracket an input change |
| `canSkip` | present and `true` when inputs may be skipped |
| `type` | an **undecoded** Logitech enum, 0–6 |

209,010 devices (76%) name their inputs — 1,089,512 inputs, all named, 5.2 per
device. 680,091 of those inputs name a command that selects them directly; the rest
belong to devices that can only cycle with `next`.

`ports` values are Logitech's own labels (`HDMI`, `Composite`, `Streaming`,
`Antenna`, `Component`, `Optical`, `USB`, `Coaxial`, `S-Video`, `FM Antenna`, …) and
are not a closed set. **`type`, and the port `Attributes` that are not published, are
Logitech enums nobody here has decoded** — `type` is passed through as the integer it
is rather than guessed at a meaning for. Treat it as an opaque tag.

#### `channelTuning`

| field | meaning |
|---|---|
| `fixedDigits` | every channel number must be sent with exactly this many digits |
| `start`, `finish` | actions bracketing the digits — `finish` is usually `Enter` |
| `greaterTen` | prefix for a channel above 9 |
| `greaterHundred` | prefix for a channel above 99 — the old `-/--` key |

`fixedDigits` is on 57,940 devices (2 digits x41,339, 3 digits x16,594): on those,
channel 7 must be dialled `07` or `007`, or the tuner sits waiting for a digit that
never arrives. `finish` is on 28,996 devices — send the digits, then `Enter`.
`greaterHundred` is on 997 and is pressed *before* the digits, not after.

#### `states` — what `{"set": …, "to": …}` refers to

An `IRDevAction` step says the device is now in state `VideoInput` = `VideoSVideo`.
The `states` block is where those names are declared: which states the device has,
what values each can take, and what to send to reach one.

```json
"states": {
  "VideoInput": {
    "values": [
      {"name": "VideoAntenna"},
      {"name": "VideoSVideo",
       "select": [{"setType": 2, "commands": ["InputNext", {"set": "VideoInput", "to": "VideoSVideo"}]}]}
    ],
    "next": ["InputNext"]
  }
}
```

| field | meaning |
|---|---|
| `values` | every value this state can hold, in Logitech's order. `name` is what a `{"to": …}` will match |
| `values[].select` | how to reach that value — one or more routes, each an action list. Absent where the value is only declared and Logitech gives no way to select it directly |
| `next`, `previous` | cycle through this state's values |
| `start`, `finish` | actions bracketing a change to this state |
| `valueDelay` | ms to wait after changing this state. Rare — 36 devices |

15,689 devices (5.7%) declare states: 39,854 states, 947 distinct names — most
commonly `InputType`, `TVInput`, `Screen`, `VideoInput`, `TunerInput` and `Teletext`
— with 149,586 declared values, of which 82,622 carry a route.

**A value can have more than one route.** Where `select` holds two, they are
genuinely different ways to reach the same value, distinguished by `setType` — an
**undecoded** Logitech enum, in practice 1 or 2. They are kept separate rather than
merged because collapsing them would silently pick one of two real alternatives. If
you only want one, take the first. Routes that were byte-identical repeats in
Logitech's data are dropped, so two entries here always mean two different things.

Not every `{"set": …}` resolves: 14,693 devices reference a state they never declare.
Those actions are still worth recording as opaque labels — two actions naming the
same state and value refer to the same thing — you just cannot enumerate the state.

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

## Timing

There are **three separate timing layers** in this archive and they are not
interchangeable:

| layer | unit | where | what it controls |
|---|---|---|---|
| waveform | **microseconds** | `protocols/<name>.json`, and the Pronto strings | the shape of a single burst — mark and space lengths, framing, repeat structure |
| burst spacing | **milliseconds** | a device's `timing` block | how far apart whole transmissions are sent to this device |
| macro steps | **milliseconds** | `{"delayMs": N}` inside a control action list | how long to pause between two steps of a sequence |

Getting the first one wrong means the device does not decode the signal at all.
Getting the second or third wrong means it decodes each signal fine but misses or
doubles presses.

### The `timing` block

Every one of the 276,236 devices carries one.

| field | unit | meaning |
|---|---|---|
| `interKeyDelay` | ms | between two presses sent to this device (500 or 100 on most) |
| `interDeviceDelay` | ms | between a command to this device and one to a different device |
| `holdInterDeviceDelay` | ms | the same, while a key is held. 0 on all but 6 devices |
| `pressMinRepeats` | count | least number of times one press must be repeated (3 on 206,783; 1 on 67,803) |
| `minRepeats` | count | least repeats overall, where Logitech states one separately — present on 78,846 |
| `isInterKeyDelayOptimized` | flag | Logitech has tuned `interKeyDelay` for this device. True on 288 |
| `powerOnDelay` | ms | how long the device takes to become responsive after power on — present on 268,058, commonly 1500, and up to tens of seconds |
| `connectedAppPowerOnDelay` | ms | the same for a network-connected app rather than the device itself. 0 on 268,967 |
| `inputDelay` | ms | settling time after an input change before the device accepts more commands |

**Provenance, and why a device may be short a field.** These come from two different
Logitech endpoints. `interKeyDelay`, `interDeviceDelay`, `holdInterDeviceDelay`,
`pressMinRepeats`, `minRepeats` and `isInterKeyDelayOptimized` are catalogue values;
`powerOnDelay`, `connectedAppPowerOnDelay` and `inputDelay` come from the resolved
device profile, which had to be fetched per device. Where the two disagree the
resolved profile wins. A field a device does not have is simply absent — most
noticeably `minRepeats`, which only the catalogue publishes, and `powerOnDelay`,
which 8,178 devices have no profile value for.

**Nine fields, not sixteen.** Logitech serves seven more that are not published here,
because each carries no information: `holdInterKeyDelay` is 100 on every one of the
276,236 devices and `holdMinRepeats` is 0 on every one, while
`defaultInterKeyDelay`, `defaultInterDeviceDelay`, `defaultPressMinRepeats` and
`defaultInputDelay` are exact restatements of the field they are named after, and
`defaultPowerOnDelay` is exactly `powerOnDelay` with absent read as 0. All seven were
checked device by device across the whole catalogue, and all seven are in the raw
capture (see below) if you want to confirm that for yourself.

**There is no `preSilence` field, here or at Logitech.** Harmony hub firmware has a
runtime `preSilence` in its own engine, fed from the hub's compiled configuration. It
is not per-device data, Logitech's service never published it, and nothing in this
archive is a relabelling of it.

## What is not here

This archive is a curated projection. Alongside it, the **raw capture** is published
as release assets: the verbatim service responses every field above was derived
from, one JSON object per line, compressed. If a field you need was dropped, or a
schema decision here turns out to be the wrong one, nothing is lost — the raw has
every byte, and the fix is a rebuild rather than a re-crawl of a service that may not
answer forever.

Known to be in the raw and not projected here:

- the seven constant or duplicated timing fields listed above;
- `OutputFeature` — the physical output jacks of 11,185 devices. Named and typed, but
  **no device has any action attached to one**, so there is nothing to send and
  nothing an IR consumer can act on;
- the `Attributes` on each input's port types, which are undecoded integers;
- per-device identifiers and timestamps from Logitech's own account plumbing, which
  describe our capture rather than the device.

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

## Licence

This archive is dedicated to the public domain under CC0 1.0.

The underlying device and protocol data originates with Logitech's Harmony
service; this project makes no ownership claim over it and asserts no rights
beyond its own compilation and derived formats.

See `LICENSE` for the full CC0 1.0 Universal text.
