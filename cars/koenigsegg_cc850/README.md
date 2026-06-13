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
3. `data/drivetrain.ini` — required and recommended settings:
   ```ini
   [GEARBOX]
   SUPPORTS_SHIFTER=1        ; required, even for controller use

   [DOWNSHIFT_PROTECTION]
   ACTIVE=0                  ; AC's internal box is cosmetic here; it must
                             ; never refuse a shift

   [DAMAGE]
   RPM_WINDOW_K=0            ; prevent phantom gearbox damage on the
                             ; cosmetic internal box
   ```
4. Drive. Open the **Lua Debug** app in-game to see live `ESS …` values
   (mode, virtual slot, engaged physical gear, clutch state, damper API).

## How it works (short version)

- The actual physics is driven by forcing the engaged gear every physics
  frame via `ac.overrideSpecificValue(ac.CarPhysicsValueID.DrivetrainEngagedGear, …)`
  — the same technique CSP's shared `automatic-transmission` module uses —
  so it behaves identically with paddles, keyboard, or an H-shifter.
- AC's own gearbox keeps running as the *visible* box: legal paddle presses
  pass through to it for native shift animations, sounds and UI; presses
  beyond the virtual limits are swallowed.
- The drivetrain clutch coupling tracks the clutch input
  (`DrivetrainClutchOverride`). When the clutch is fully home (at/above
  `CLUTCH_HOME_THRESHOLD`) the coupling is snapped to a clean `1.0` hard lock
  rather than the live clutch value — AC's autoclutch parks that field a hair
  below 1.0 while cruising, and passing it straight through left the drivetrain
  a fraction of a percent open every frame, which was the residual slip felt in
  tall gears. Controller autoclutch and a real clutch pedal both feed the same
  field, so both "just work".
- Gear-ratio blending across shifts (`ac.setGearsFinalRatio`) smooths RPM
  transitions: ~0.1 s in NORMAL auto, ~0.04 s in TRACK / manual (the LST
  engages near-instantly).

## Tuning

Everything lives at the top of `script.lua`:

- `PROFILES.NORMAL` / `PROFILES.TRACK`: gear maps, throttle exponent,
  AUTO shift RPMs, shift blend time, shift cooldown, damper multipliers.
- `H_PATTERN`, `REVERSE_MAX_KMH`, `PULSE_INTERVAL`, `MAX_PULSES`,
  `CLUTCH_OPEN_THRESHOLD`, `CLUTCH_HOME_THRESHOLD` (at/above this the clutch is
  treated as fully home and the drivetrain is snapped to a clean hard lock —
  raise it toward 1.0 if you still feel residual slip, lower it if the clutch
  feels like it grabs too early off the line).

## Known limitations

- Damper adjustment depends on a CSP accessor that isn't exposed in every
  build; the script probes for it and degrades gracefully (check
  `ESS damper API` in Lua Debug — `NOT AVAILABLE` means damping multipliers
  are inactive).
- Extended physics makes the car CSP-only and will fail checksum on strict
  online servers.
- In AUTO (D), the dash shows whatever AC's cosmetic box last displayed; the
  engaged gear is visible in the Lua Debug app.
