# Koenigsegg CC850 — Engage Shift System (ESS)

*Coded by VR Driving AI Physics.*

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
| `EXTRA A` | Toggle NORMAL / TRACK profile (works in manual and AUTO) |
| `EXTRA C` | Toggle AUTO (D) |
| Paddles / sequential | Walk the virtual 6-speed (R/N/1-6), capped at slot 6 |
| H-pattern shifter | Gates 1-6 map per profile, **gate 7 engages AUTO (D)** |

The controller type is **auto-detected** — paddles and an H-pattern shifter both
just work, with nothing to configure. The Lua Debug app shows the detected input
as `ESS detected input`.

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
   (mode, virtual slot, engaged physical gear, RPM, clutch, damper API). The
   `ESS drivetrain lock` line reports the clutch hard-lock state: `LOCKED`
   while driving, `tracking` in N/R or while declutching, or `ID NOT FOUND`
   if this CSP build doesn't expose the clutch-override values.

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
- **Controller type is auto-detected**, so there's no flag to set. An H-pattern
  shifter moves `carPh.requestedGearIndex` directly, so a change there is read as
  a gate selection and mapped straight to the virtual slot (gate 1 → slot 1, …).
  Paddles/sequential walk the slot by `gearUp`/`gearDown` edges, which the script
  swallows — so `requestedGearIndex` stays parked and the two inputs can't be
  confused. Either way it's the same virtual slot, so the normal slot → mapped
  LST gear logic takes over (gate 1 is LST 2nd in NORMAL, LST 3rd in TRACK).
- In H-pattern, after reading the gate the script drives AC's own gearbox to the
  *mapped* gear by writing `requestedGearIndex = engaged + 1`. AC's box gear is
  what sets the actual ratio, so the box has to sit in the mapped gear — e.g.
  gate 1 in TRACK puts AC's box in 3rd, giving 3rd's ratio. AC re-samples the
  physical gate before the next read, so this doesn't disturb gate reading.
- The dash gear is a **display-only** override: `ac.overrideCarState('gear', …)`
  shows the virtual slot (or the AUTO gear) without touching physics. Toggle
  with `SHOW_VIRTUAL_GEAR`.
- **AUTO (D)** uses a throttle-adaptive shift map: the up/downshift RPMs are
  lerped between a light-throttle and a full-throttle value by pedal position, so
  cruising upshifts early and keeps revs low while flooring it holds each gear to
  near redline and kicks down harder — like a real load-based shift schedule.
- In **AUTO (D)** there's no driver clutch, so the script slips the clutch itself
  below `AUTO_LAUNCH_KMH`: a gentle creep off the brake, more as you press the
  throttle, fully locked once rolling. This lets it pull away from a standstill
  without stalling instead of staying stuck with the clutch disengaged.
- The drivetrain clutch is **hard-locked** while driving (`CLUTCH_HARD_LOCK`).
  Forcing the engaged gear leaves the clutch coupling a few percent open on its
  own — felt most in tall gears — so the script overrides the coupling to a
  full lock whenever you're in a forward gear with the clutch fully home, and
  releases it (tracking the real clutch) in N/R or while you declutch. Set
  `CLUTCH_HARD_LOCK = false` for plain bypass behavior (the slip returns).
- Gear-ratio blending across shifts (`ac.setGearsFinalRatio`) smooths RPM
  transitions: ~0.1 s in NORMAL auto, ~0.04 s in TRACK / manual (the LST
  engages near-instantly).

## Tuning

Everything lives at the top of `script.lua`:

- `PROFILES.NORMAL` / `PROFILES.TRACK`: gear maps, throttle exponent,
  throttle-adaptive AUTO shift map (`upshiftLightRpm`/`upshiftFullRpm` and
  `downshiftLightRpm`/`downshiftFullRpm` — the up/down RPMs at light vs full
  throttle, lerped by pedal position), shift blend time, shift cooldown, damper
  multipliers.
- `REVERSE_MAX_KMH`, `MANUAL_SHIFT_TIME`, `SHOW_VIRTUAL_GEAR`
  (set `false` to show the physical LST gear on the dash instead of the slot).
  Controller type needs no setting — it's auto-detected.
- `CLUTCH_HARD_LOCK` (on by default; `false` = plain bypass, slip returns) and
  `CLUTCH_HOME` (clutch fraction at/above which the lock engages — raise toward
  1.0 if any slip remains, lower if the clutch grabs too early off the line).
- `AUTO_LAUNCH_KMH` (speed below which AUTO slips the clutch for a stall-free
  launch from a stop) and `AUTO_CREEP` (idle creep engagement off the brake in
  AUTO; `0` disables creep).

## Known limitations

- Damper adjustment depends on a CSP accessor that isn't exposed in every
  build; the script probes for it and degrades gracefully (check
  `ESS damper API` in Lua Debug — `NOT AVAILABLE` means damping multipliers
  are inactive).
- Extended physics makes the car CSP-only and will fail checksum on strict
  online servers.
- AC's box is bypassed, so shifts don't trigger AC's native shift
  animation/sound; the dash gear is driven by the display-only override instead.
  The engaged physical gear is always visible in the Lua Debug app.

## Credits

Coded by **VR Driving AI Physics**.
