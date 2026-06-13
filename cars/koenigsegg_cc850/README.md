# Koenigsegg CC850 — Engage Shift System (ESS)

CSP car physics script simulating the CC850's ESS: the physical gearbox is the
9-speed Light Speed Transmission (LST), but the driver interacts with a
6-speed manual whose slots map to different physical gears depending on the
drive mode — exactly how the real car works. A full automatic mode drives all
nine gears.

## Modes

| Mode | Slot → physical LST gear | Extras |
|---|---|---|
| **NORMAL** (default) | 1-6 → LST 2, 4, 6, 7, 8, 9 | softer throttle curve (`gas^1.35`), baseline dampers |
| **TRACK** | 1-6 → LST 3, 4, 5, 6, 7, 8 | linear throttle, stiffer dampers, more aggressive AUTO shift points |
| **AUTO (D)** | script shifts LST 1-9 by RPM | paddles inert while engaged |

## Controls

| Binding (AC controls → Custom Shaders Patch) | Action |
|---|---|
| `EXTRA A` | Toggle NORMAL / TRACK profile (manual mode only) |
| `EXTRA C` | Toggle AUTO (D) |
| Paddles / sequential | Walk the virtual 6-speed (R/N/1-6); capped at slot 6 |
| H-pattern shifter | Set `H_PATTERN = true` at the top of `script.lua`; gates 1-6 map per profile, **slot 7 engages AUTO (D)** |

## Installation

1. Copy `data/script.lua` into the car's `data/` folder.
   - If the car ships a packed `data.acd`, unpack it (Content Manager → car →
     Unpack data) and remove/rename `data.acd` while testing. Repack for release.
2. `data/car.ini` — enable CSP extended physics:
   ```ini
   [HEADER]
   VERSION=extended-2
   ```
3. `data/drivetrain.ini` — required setting:
   ```ini
   [GEARBOX]
   SUPPORTS_SHIFTER=1        ; required, even for controller use
   ```
4. Drive. Open the **Lua Debug** app in-game to see live `ESS …` values
   (mode, virtual slot, engaged physical gear, RPM, damper API). The display
   diagnostics — `display gear (pushed)`, `carPh.gear (physics raw)` and
   `car.gear (render)` — show whether the cosmetic dash override is landing:
   if `pushed` is correct but the dash shows a different number, this car's
   dash binding is ignoring the render override.

## How it works (short version)

- The actual physics is driven by forcing the engaged gear every physics
  frame via `ac.overrideSpecificValue(ac.CarPhysicsValueID.DrivetrainEngagedGear, …)`
  — the same technique CSP's shared `automatic-transmission` module uses —
  so it behaves identically with paddles, keyboard, or an H-shifter.
- AC's own sequential box is **bypassed, not driven**: every frame the script
  swallows the raw paddle inputs (`carPh.gearUp/gearDown = false`) and only
  reads their rising edges to walk the virtual slot. AC's box is never asked to
  shift, so its clutch/engagement logic never runs alongside the forced gear —
  that parallel box is exactly what caused the residual drivetrain slip, and
  leaving it parked is what keeps this version clean.
- The dash gear is a **display-only** override: `ac.overrideCarState('gear', …)`
  shows the virtual slot (or the AUTO gear) without touching physics. Toggle
  with `SHOW_VIRTUAL_GEAR`.
- Clutch is left entirely to AC's own handling — there is no clutch override.
- Gear-ratio blending across shifts (`ac.setGearsFinalRatio`) smooths RPM
  transitions: ~0.1 s in NORMAL auto, ~0.04 s in TRACK / manual (the LST
  engages near-instantly).

## Tuning

Everything lives at the top of `script.lua`:

- `PROFILES.NORMAL` / `PROFILES.TRACK`: gear maps, throttle exponent,
  AUTO shift RPMs, shift blend time, shift cooldown, damper multipliers.
- `H_PATTERN`, `REVERSE_MAX_KMH`, `MANUAL_SHIFT_TIME`, `SHOW_VIRTUAL_GEAR`
  (set `false` to show the physical LST gear on the dash instead of the slot).

## Known limitations

- Damper adjustment depends on a CSP accessor that isn't exposed in every
  build; the script probes for it and degrades gracefully (check
  `ESS damper API` in Lua Debug — `NOT AVAILABLE` means damping multipliers
  are inactive).
- Extended physics makes the car CSP-only and will fail checksum on strict
  online servers.
- Because AC's sequential box is bypassed, paddle shifts don't trigger AC's
  native shift animation/sound; the dash gear is driven by the display-only
  override instead. The engaged physical gear is always visible in the Lua
  Debug app.
