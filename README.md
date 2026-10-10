# Logitech Harmony IR archive

## AI Disclaimer

I heavily used AI in creating this archive.

## TL;DR - Just give me the data

Don't care about my attempt, with Claudes help, to pull out the relevant data? Don't blame you :)

Check the files attached to the [Verbatim capture, 2026-09-02](https://github.com/pickysysadmin/logitech-harmony-ir-archive/releases/tag/raw-2026-09-02) release.

They are the unfiltered raw data I captured to do with as you see fit.

## Overview

The infrared control database from Logitech's Harmony universal remotes: about
276,000 devices from 7,900 manufacturers, 13.3 million commands, and all 684 of
Logitech's own IR protocol definitions. `manifest.json` has the current counts.

Harmony is mostly discontinued, and this data lived only on Logitech's servers. It is
all plain JSON, and using it needs no Logitech service, no account, and no tooling
beyond what is in this repository.

Every command has its original Harmony **keycode** and, where it is infrared, a
ready-to-send **Pronto Hex** string. Every protocol has Logitech's original
definition, so you can render any command yourself instead of trusting ours. Devices
also record how to *drive* them: timing, whether power is discrete or a toggle, their
inputs, and how channel numbers are dialled.

One convention applies throughout: **an optional field that has no value is absent.
It is never `null`, `{}` or a placeholder.** Test whether the key exists, not whether
its value is falsy.

## Contents

```
manifest.json                        counts, schema version, build date
index.json                           every manufacturer
devices/<Manufacturer>/index.json    every model that manufacturer has
devices/<Manufacturer>/<Model>.json  one device: identity, how to drive it, and its code set
codesets/<xx>/<hash>.json            one command set, shared by every device that has it
protocols/index.json                 every protocol
protocols/<Protocol_Name>.json       one protocol definition
index.html                           a lookup page
rehydrate.py, rehydrate.ps1          write device files with their commands inlined
```

Code sets are stored separately because 79% of devices share a byte-identical set
with another device. Storing each set once shrinks the tree from ~5.8 GB to ~0.8 GB.

## Looking something up

**The page.** `index.html` is a single file with no build step and no dependencies.
Double-click it and use **Open archive folder…** to pick the folder holding
`manifest.json`. It reads the files in place, and nothing is uploaded. This needs
the File System Access API, which Chromium browsers have and Firefox and Safari do
not. In any browser, you can instead serve the folder and open it over `http://`:

```sh
python3 -m http.server 8000     # or any static file server, run from the archive root
```

**By hand.**

```sh
jq -r '.[] | select(.n=="Sony") | .s' index.json           # -> Sony
jq -r '.[] | select(.m=="CDP222ES") | .f' devices/Sony/index.json
jq . devices/Sony/CDP222ES.json
jq -r '.commands[] | "\(.name)\t\(.pronto)"' \
   "$(jq -r .codeset devices/Sony/CDP222ES.json)"
```

**Rehydrated.** `rehydrate.py` writes self-contained device files with the commands
inlined:

```sh
python3 rehydrate.py --manufacturer Sony --out /tmp/sony
python3 rehydrate.py --model-file my-devices.txt --out /tmp/mine
python3 rehydrate.py --all --out /tmp/everything      # ~5.8 GB
```

`rehydrate.ps1` does the same in PowerShell. Windows PowerShell 5.1 is slow at
parsing JSON, so use Python or PowerShell 7 for anything bigger than one manufacturer.

## Schema

### `manifest.json`

| field | meaning |
|---|---|
| `schemaVersion` | bumped on any breaking field change. Pin it if you parse this |
| `generated` | build date, `YYYY-MM-DD` |
| `source` | where the data came from |
| `counts` | `manufacturers`, `devices`, `devicesWithCodes`, `devicesWithTiming`, `devicesWithControl`, `commands`, `commandsWithPronto`, `codesets`, `protocols` |
| `layout` | the path patterns, so a consumer never hard-codes them |
| `notes` | rendering caveats that apply to the whole archive |

### `devices/<Manufacturer>/<Model>.json`

A real one, `devices/Magnavox/RJ5540.json`, with its timing block removed:

```json
{"manufacturer": "Magnavox",
 "model": "RJ5540",
 "globalDeviceId": 636,
 "deviceType": 1,
 "codeset": "codesets/3b/3b3e7eddcbfe948a.json",
 "power": {"type": "toggle", "toggle": ["PowerToggle"]},
 "inputs": {"type": 1,
            "list": [{"name": "VCR/AUX", "commands": ["InputNext", {"delayMs": 500}, "InputAux"]},
                     {"name": "TV", "commands": ["InputNext", {"delayMs": 500}, "InputTuner"]}]}}
```

This device has no discrete power command, and to reach either input you press
`InputNext`, wait half a second, then press the one you want. Its command list alone
would not tell you that.

| field | meaning |
|---|---|
| `manufacturer`, `model` | verbatim, spelled as Logitech spells them. Read these rather than the filename (see *Filenames*) |
| `globalDeviceId` | Logitech's permanent catalogue id, and this file's stable identity |
| `deviceType` | Logitech's device-type code (1 TV, 2 VCR, 3 CD, 4 DVD, …) |
| `codeset` | path to the device's command set, relative to the archive root, or `null` for a device with no commands |
| `timing` | delays and repeat counts. See *Timing* |
| `power`, `inputs`, `channelTuning`, `states` | how to control it. See *Control* |

### Control

A code set tells you a device *has* a `PowerOn` command. It does not tell you whether
sending it is safe, which input is HDMI 1, or that channel 7 must be dialled `07`.
These four blocks carry that information, and about 91% of devices have at least one.

#### Action lists

Every actionable field (`power.on`, `inputs.next`, an input's `commands`,
`channelTuning.finish`, a state value's `select`, …) is a list of steps, performed in
array order:

| step | meaning |
|---|---|
| `"PowerOn"` | send the command with this `name` from the device's code set |
| `{"command": "X", "durationMs": 500}` | send `X` repeatedly for 500 ms (press and hold) |
| `{"hold": "X"}` | hold `X`, with no duration given |
| `{"delayMs": 500}` | send nothing, and wait 500 ms before the next step |
| `{"set": "Input", "to": "Antenna"}` | not a transmission. It records that the device is now in state `Input` = `Antenna` |

A delay between two steps is a real wait between them, not a cooldown at the end.
Logitech stores each step's position in an `Order` field and sometimes stores the
steps out of order (about 1 in 12 input lists). Every list here was sorted on
`Order` before publishing, so the array position is the execution order. A press with
a 0 ms duration is published as a bare string.

A consumer can ignore everything except the bare strings and `command` steps. It
will still work, but it will be less careful about timing and state.

#### `power`: read `type` first

| field | meaning |
|---|---|
| `type` | `discrete`, `toggle`, `none` or `unknown` |
| `on`, `off` | action lists for discrete power control |
| `toggle` | the action list that flips power state |
| `onReset` | actions to run after powering on, to put the device in a known state |
| `onResetInput` | the input `onReset` selects, when named |

Most devices are `toggle`. They have one power command, and it flips the current
state, so sending it to "turn the TV on" turns it off if the TV is already on. Only
`discrete` devices have separate `on` and `off` commands that are safe to send blind.
A code set can contain a command *named* `PowerOn` on a device that is really a
toggle, so **go by `type`, not by command names.** Most devices with no power control
have no `power` block at all.

#### `inputs`

| field | meaning |
|---|---|
| `list` | the inputs in order, each with a `name`, the `commands` that select it, and the `ports` it is wired to |
| `next`, `previous` | cycle through the inputs, for devices with no direct selection |
| `start`, `finish` | actions that bracket an input change |
| `canSkip` | `true` when inputs may be skipped |
| `type` | an undecoded Logitech enum, 0–6. Treat it as an opaque tag |

Port names are Logitech's labels (`HDMI`, `Composite`, `Antenna`, `Optical`, …), and
the list of possible names is not fixed. Inputs with no `commands` belong to devices
that can only cycle through inputs with `next`.

#### `channelTuning`

| field | meaning |
|---|---|
| `fixedDigits` | every channel number must be sent with exactly this many digits, e.g. `07` |
| `start`, `finish` | actions bracketing the digits. `finish` is usually `Enter` |
| `greaterTen` | prefix for a channel above 9 |
| `greaterHundred` | prefix for a channel above 99 (the old `-/--` key), pressed before the digits |

#### `states`: what `{"set": …, "to": …}` refers to

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
| `values` | every value this state can hold, in Logitech's order. A `{"to": …}` matches `name` |
| `values[].select` | ways to reach that value, each an action list. Absent when Logitech gives no direct way |
| `next`, `previous` | cycle through the values |
| `start`, `finish` | actions bracketing a change to this state |
| `valueDelay` | ms to wait after changing this state (rare) |

When `select` has more than one route, they are genuinely different routes,
distinguished by `setType`, an undecoded enum (1 or 2 in practice). Duplicate routes
have been removed. If you only want one route, take the first.

Some devices `set` a state they never declare. Treat those as opaque labels: two
actions that name the same state and value still refer to the same thing.

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
| `protocol` | Logitech's canonical protocol name, which always matches a file in `protocols/`. The keycode's own spelling of it can differ in case or spacing |
| `keycode` | the original Harmony keycode. Always present |
| `pronto` | Pronto Hex (format `0000`). Absent when the command can't be rendered (see *Caveats*) |
| `prontoRepeat` | the repeat burst alone, as its own Pronto string. Present only when there is a lead-in or trailer around it |

`pronto` is a two-section Pronto string: a player sends the first section once, then
loops the second while the key is held. If there is no separate repeat burst, the
second section is empty. `prontoRepeat` is for tools that only accept a single
sequence.

`hash` is the first 16 hex characters of a SHA-1 over each command's `name`, a NUL
byte, its `keycode` and a newline, with the commands sorted by `(name, keycode)`. It
depends only on Logitech's data, not on our rendering. `<xx>` is the first two
characters of the hash.

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
| `name` | Logitech's canonical name, which is what a command's `protocol` field holds |
| `logitechProtocolId` | Logitech's internal protocol id |
| `carrierHz` | carrier frequency. There are 192 distinct values, from 30 kHz to 455 kHz |
| `standardProtocol` | IrpTransmogrifier's name for it (`NEC1`, `RC5`, …), or `null` when it does not decode. For information only |
| `irp` | the definition as an [IRP](http://hifi-remote.com/wiki/index.php/IRP_Notation) string, or `null` for a non-IR protocol |
| `keycodeFields` | for each `CodeN` field in the IRP, the keycode group, token and segment it comes from, its width, and any toggle bit |
| `pressMinimumRepeats` | not the repeat count. See *Repeats* |
| `definition` | **Logitech's original JSON, verbatim.** It is the primary source, and other tools can render it without ours |

## Timing

There are three timing layers, and they are not interchangeable:

| layer | unit | where | controls |
|---|---|---|---|
| waveform | µs | protocol files and Pronto strings | the shape of one burst |
| burst spacing | ms | the device's `timing` block | gaps between whole transmissions |
| macro steps | ms | `{"delayMs": N}` in an action list | pauses within a sequence |

If the waveform is wrong, the device does not decode the signal at all. If the other
two are wrong, the device decodes each signal but misses or doubles presses.

### The `timing` block

Every device has one.

| field | unit | meaning |
|---|---|---|
| `interKeyDelay` | ms | between two presses to this device (500 or 100 on most) |
| `interDeviceDelay` | ms | between a command to this device and one to a different device |
| `holdInterDeviceDelay` | ms | the same, while a key is held. Almost always 0 |
| `pressMinRepeats` | count | **the repeat count for a single press**, usually 3 or 1. See *Repeats* |
| `minRepeats` | count | a second catalogue value that no known IR sender reads. See *Repeats* |
| `isInterKeyDelayOptimized` | flag | Logitech has tuned `interKeyDelay` for this device |
| `powerOnDelay` | ms | time to become responsive after power on. Commonly 1500, and can be tens of seconds |
| `connectedAppPowerOnDelay` | ms | the same for a network-connected app. Almost always 0 |
| `inputDelay` | ms | settling time after an input change |

The first six fields come from Logitech's catalogue, and the last three come from a
per-device profile, which wins when the two disagree. A device lacking a field, most
often `minRepeats` or `powerOnDelay`, simply has no value for it.

### Repeats

Harmony sends a minimum number of repeats even for a short press, and that number is
set per device in `timing.pressMinRepeats`. The Harmony Hub's IR engine
(`irmanager.lua`) reads it, defaulting to 3:

```lua
local minRepeats = 3
if device.pressMinRepeats ~= json.null and device.pressMinRepeats >= 0 then
  minRepeats = device.pressMinRepeats
end
```

A single press plays as:

    start group once  →  repeat group × pressMinRepeats  →  finish group

All of these copies are sent even if the key is released immediately. While the key
is held, the hub keeps replaying the repeat group, and it plays the finish group on
release. With `pressMinRepeats` 0, a quick press sends no repeat at all, unless the
keycode has no start or finish group, in which case one repeat is sent.

This was traced through the hub firmware but has not yet been checked against a
capture from a real hub. Older remotes (650, 700, One, …) were programmed by
Logitech's desktop compiler, which we have not seen.

These three values look like repeat counts but are not:

- the number after the keycode's last colon, which is `3` on 99.95% of keycodes
  regardless of the device
- a protocol's `pressMinimumRepeats`, which the hub reads but never uses when sending
- the device's `minRepeats`, which the hub does not read. The desktop compiler might
  use either of the last two

## Caveats

**The toggle bit is always 0.** Protocols with a toggle bit (RC5 and its relatives,
which have `toggleBit` in `keycodeFields`) expect the bit to alternate between
presses. A device may ignore the same Pronto sent twice. Flip the bit yourself for
the second press.

**2,247 commands have no `pronto`, and never can:**

| protocol | commands | why |
|---|---|---|
| `ATI 21 Bit` | 2,067 | 433 MHz radio, not infrared |
| `HID 16 Bit` | 109 | USB HID keyboard control |
| `Sonos IP` | 52 | network control |
| `Roku IP` | 19 | network control |

**61 more commands have keycodes that are corrupted in Logitech's database**, for
example a doubled prefix (`0x0x020122_…`), a stray character (`0x00FF48B7v`), a
missing digit (`xB6BA20DF`), or a segment the protocol does not define. They are kept
exactly as Logitech serves them, with no `pronto`.

**About 18,500 devices have no commands.** They are empty entries in Logitech's
catalogue, and here they have `"codeset": null`.

## What is not here

This archive is a curated subset of the data. The raw capture, which has every
service response verbatim, is published as release assets (see the TL;DR). If a field
you need was dropped, it can be rebuilt from the raw capture. The following are in
the raw capture but not here:

- seven timing fields that carry no information: `holdInterKeyDelay` (100 on every
  device), `holdMinRepeats` (0 on every device), and the `default*` fields, each of
  which repeats the field it is named after
- `OutputFeature`, the output jacks of about 11,000 devices. No actions are
  attached to them
- the undecoded `Attributes` integers on input port types
- identifiers and timestamps from Logitech's account system, which describe our
  capture rather than the device

## Rendering a keycode yourself

Every other field in the archive is derived from the keycode plus the protocol
definition.

```
G:<protocol name>:(<start>)(<repeat>)(<finish>):<trailer>
G:Sony 12 Bit:()(0x8D1)():3
G:JVC 16 Bit:(Start)(0xC004)():3
```

- The three groups are IRP's intro, repeat and ending sequences. Each splits on `_`
  into **segment tokens**.
- A token is either `<segment id>x<hex value>` (the `x` is always at index 1, so
  `0x750` is segment `"0"` with the value `750`) or a bare segment id naming a fixed
  segment, such as `Start`.
- The trailer is not part of the waveform and is not the repeat count.

Then, from the protocol `definition`:

- **Segments.** Each entry in `IRSegments` (encoded) and `CodeSegments` (fixed) is
  filed under an id taken from its `Name`. If the name equals the protocol name, the
  id is `"0"`. If it contains `KeyCode`, the id is the text after `KeyCode` (so
  `Toshiba 32 Bit KeyCodeRepeat` → `"Repeat"`). Otherwise it is the text after
  `"<protocol name> "`.
- **Bits.** For `EncodingType` 0 or 1, each hex digit contributes 4 bits, most
  significant first. For `EncodingType` 2 or 3 (the "N Bit Quad" protocols), each hex
  digit is one symbol. Left-pad with zeros to `NumberOfBits`, or drop *leading* bits
  if the value is too wide.
- **Toggle.** If there is a `ToggleBit`, that bit position is overwritten with a
  counter that alternates between presses.
- **Playout.** For each segment, play the `Header` atoms, then the
  `Encodings[BitType].Atoms` for each bit, then the `Trailer` atoms, then a space of
  `TotalLength - (header + data + trailer)` if that is positive. An atom with `Type`
  1 is a mark and one with `Type` 0 is a space. `Value` is in microseconds.
- **Assembly.** Play the start, repeat and finish groups in that order. Merge adjacent
  runs at the same level and drop any leading space. The carrier is
  `CarrierFrequency`.

> Don't treat "the first non-empty group" as the data. For ~4.8% of commands (38
> protocols, mostly `JVC 16 Bit`), that group is a lead-in with no payload.

## Filenames

Filenames are only addresses, so read `manufacturer` and `model` from inside the
file. They are normalised so that the archive checks out on Windows and macOS:

- Unicode is NFKC-normalised and combining marks are stripped (`Alizé` → `Alize`).
- Anything outside `A-Za-z0-9._-` becomes `_`. Runs of these collapse into one, and
  leading or trailing `_ . -` and spaces are trimmed.
- Windows reserved names get a trailing `_` (`AUX` is a real manufacturer).
- Collisions, compared case-insensitively, get `-<globalDeviceId>` added for a device,
  or `-2`, `-3`, … for a manufacturer.

Once a file has an address, it keeps it. If Logitech re-spells a model, only the
`model` field changes.

## Acknowledgements

A massive thank you to the following projects:

- Logitech for compiling all of these codes
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

If anyone from Logitech is reading this and could grant a license/permission to use the
data free and clear, please reach out.

See `LICENSE` for the full CC0 1.0 Universal text.
