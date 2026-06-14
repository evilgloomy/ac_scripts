# Active Steering — Variable-Ratio Steering (BMW E60-style)

*Coded by VR Driving AI Physics.*

A drop-in CSP car physics script that simulates **speed-variable steering
ratio**, the headline feature of the Active Steering system BMW introduced on
the **E60 5 Series**. The real car has a planetary actuator in the steering
column that adds or subtracts steering angle, so the *overall ratio changes with
speed*: parking is very quick (~2 turns lock-to-lock, around **10:1**) and the
autobahn is calm and stable (around **20:1**).

We can't fit a planetary gear, so the script does the electronic equivalent —
every physics frame it reads the driver's normalised steering and re-maps it by a
speed-scheduled gain before it reaches the tyres. It's generic: drop it into
**any** car's `data/` folder and it adapts to that car's own steering numbers.

## Behaviour

| Speed | Gain | Ratio | Feel |
|---|---|---|---|
| Parking / low speed | `gainLow` (>1, ~1.6) | quick (e.g. ~10:1) | small inputs, few turns lock-to-lock — easy maneuvering |
| Transition | smoothstep between | — | ratio eases smoothly with speed, no step |
| Motorway / high speed | `gainHigh` (<1, ~0.8) | slow (e.g. ~20:1) | bigger inputs needed — settled and stable |

Because `±1` steering input always equals the car's **mechanical** full lock,
multiplying the input by a gain `> 1` reaches full lock with *less* wheel
rotation (a quicker ratio) and a gain `< 1` needs *more* rotation for a given
angle (a slower, more stable ratio) — exactly what the real actuator does.

## Controls

| Binding (AC controls → Custom Shaders Patch) | Action |
|---|---|
| `EXTRA C` | Toggle Active Steering **ON / OFF** (OFF = the car's stock fixed ratio — instant A/B) |
| `EXTRA A` | Toggle **COMFORT / SPORT** schedule |

| Schedule | Character |
|---|---|
| **COMFORT** (default) | Quickest parking ratio, calmest at speed, mild on-centre softening |
| **SPORT** | Stays direct deeper into the speed range, linear on-centre feel |

## Installation

1. Copy `data/script.lua` into the target car's `data/` folder.
   - If the car ships a packed `data.acd`, unpack it (Content Manager → car →
     Unpack data) and remove/rename `data.acd` while testing. Repack for release.
2. `data/car.ini` — enable CSP extended physics:
   ```ini
   [HEADER]
   VERSION=extended-2
   ```
3. Drive. Open the **Lua Debug** app in-game to see live `AS …` values (state,
   speed, current gain, effective ratio, lock-to-lock and steer in→out). The
   `AS state` line reports `[steer not writable on this CSP build]` if this CSP
   build doesn't expose a writable steering input (the script then only displays).

For the most faithful feel, turn off AC's gameplay steering aids (no
steering assist) so the only thing shaping the ratio is this script.

## How it works (short version)

- Every frame the script reads `carPh.steer` (the driver's steering, `-1..1`,
  where `±1` is the car's mechanical full lock), multiplies it by a
  **speed-scheduled gain**, clamps to `±1`, and writes it back — the same input
  hook CSP gamepad-assist scripts use to reshape steering before physics.
- The gain comes from a **smoothstep schedule**: `gainLow` at/below `speedLow`,
  easing to `gainHigh` at/above `speedHigh`. High gain at low speed = quick;
  low gain at high speed = slow and stable. Speed changes smoothly, so the ratio
  does too — no steps or kinks.
- **On-centre softening** (`centerExp`) optionally shapes only the magnitude of
  the input (sign and endpoints preserved), so a high parking gain doesn't feel
  nervous around the straight-ahead. `1.0` disables it (pure linear ratio).
- The car's stock `[CONTROLS] STEER_LOCK` / `STEER_RATIO` are read from
  `car.ini` so the **ini stays the single source of truth** and the debug app can
  show the *effective* ratio and lock-to-lock you're feeling right now.
- It **degrades gracefully**: the steering write is `pcall`-probed once, and on a
  build that locks the input the script just displays and never touches physics.
- Toggling Active Steering **OFF** (`EXTRA C`) stops writing entirely, handing
  steering straight back to the car's stock fixed ratio for a clean comparison.

## Tuning

Everything lives at the top of `script.lua`:

- `PROFILES.COMFORT` / `PROFILES.SPORT`: each has `gainLow`, `gainHigh`,
  `speedLow`, `speedHigh` (the speed-scheduled ratio) and `centerExp`
  (on-centre softening).
  - Want a more dramatic / arcade-quick park? Raise `gainLow` (e.g. `1.8–2.2`).
  - Want a calmer, more stable motorway? Lower `gainHigh` (e.g. `0.6–0.7`).
  - Want the transition to happen sooner/later? Move `speedLow` / `speedHigh`.
- `ENABLED_AT_START`: whether the system is engaged when the car loads.

## Known limitations

- **Force feedback** is computed from the physics, so with a quicker ratio the
  self-aligning torque arrives "sooner" in wheel rotation — the wheel feels
  lighter/quicker at parking gains, heavier as the ratio slows. The real system
  partly decouples FFB from the actuator; this script does not fake that.
- With a parking gain `> 1`, full lock is reached before full input travel, so
  the last slice of wheel rotation does nothing — that's the quicker ratio, not a
  bug, and it mirrors needing fewer turns lock-to-lock.
- Only the **variable-ratio** half of Active Steering is modelled. The real
  system's yaw-rate *stabilisation* (small automatic counter-steer corrections
  during a slide, tied to DSC) is **not** simulated — this is steering ratio, not
  a stability controller.
- Extended physics makes the car CSP-only and will fail checksum on strict
  online servers.

## Credits

Coded by **VR Driving AI Physics**.
