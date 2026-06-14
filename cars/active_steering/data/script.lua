-- Active Steering — speed-variable steering ratio (BMW E60-style)
-- Coded by VR Driving AI Physics
-- CSP car physics script — must live at <car>/data/script.lua
--
-- Requires:
--   * A recent CSP with extended physics (writable carPh.steer; 0.1.77+)
--   * car.ini -> [HEADER] VERSION=extended-2   (extended physics enabled)
--
-- Simulates the variable-ratio Active Steering first seen on the BMW E60 5
-- Series. The real car puts a planetary actuator in the steering column that
-- adds or subtracts steering angle, so the OVERALL RATIO CHANGES WITH SPEED:
-- parking is very quick (~2 turns lock-to-lock, around 10:1) while the autobahn
-- is calm and stable (around 20:1). We can't fit a planetary gear, so we do the
-- electronic equivalent — read the driver's normalised steering every physics
-- frame and re-map it by a speed-scheduled gain before it reaches the tyres.
--
-- Why a gain on the normalised input == a ratio change:
--   carPh.steer is the driver's steering, -1..1, where +/-1 is the car's
--   MECHANICAL full lock (fixed by the suspension). Multiply it by a gain and:
--     gain > 1  -> +/-1 (full lock) is reached with LESS wheel rotation = a
--                  quicker ratio, fewer turns lock-to-lock (parking).
--     gain < 1  -> full input only asks for part lock = MORE rotation needed for
--                  a given angle = a slower, more stable ratio (high speed).
--   That is precisely what the real actuator does to the ratio, in software.
--
-- Controls (AC controls -> Custom Shaders Patch extra buttons):
--   EXTRA_C  toggle the system ON / OFF (OFF = the car's stock fixed ratio, for
--            an instant A/B back-to-back comparison)
--   EXTRA_A  toggle COMFORT / SPORT schedule

local ENABLED_AT_START = true   -- start with Active Steering engaged

-- Speed-scheduled gain. The gain is interpolated (smoothstep) from gainLow at or
-- below speedLow to gainHigh at or above speedHigh:
--   gainLow   low-speed / parking gain (quick).  ~1.6 turns a 16:1 rack into ~10:1
--   gainHigh  high-speed gain (stable).          ~0.8 turns a 16:1 rack into ~20:1
--   speedLow / speedHigh   km/h bounds of the transition
--   centerExp >1 softens on-centre response so a high parking gain isn't twitchy
--             near the straight-ahead; endpoints (0 and full lock) are untouched.
--             1.0 = pure linear variable ratio.
local PROFILES = {
  -- Calmer everyday map: easy to park, very settled at motorway speed.
  COMFORT = { gainLow = 1.60, gainHigh = 0.78, speedLow = 15, speedHigh = 140, centerExp = 1.10 },
  -- Stays direct deeper into the speed range and keeps a linear on-centre feel.
  SPORT   = { gainLow = 1.50, gainHigh = 1.00, speedLow = 25, speedHigh = 180, centerExp = 1.00 },
}

local carPh = ac.accessCarPhysics()

-- Read the car's stock steering numbers so the ini stays the single source of
-- truth and the Lua Debug app can show the EFFECTIVE ratio. These are the
-- AC-standard keys ([CONTROLS] STEER_LOCK / STEER_RATIO); defaults are only used
-- if a car omits them.
local cfg = ac.INIConfig.carData(car.index, 'car.ini')
local baseLock  = cfg:get('CONTROLS', 'STEER_LOCK', 400)   -- deg of wheel to full lock
local baseRatio = cfg:get('CONTROLS', 'STEER_RATIO', 16)   -- steering : road-wheel

local profile      = 'COMFORT'
local enabled      = ENABLED_AT_START
local steerWritable = nil   -- probed once; false on builds that lock the input
local extraAPrev, extraCPrev = false, false

local function message(title, desc)
  if ac.setSystemMessage ~= nil then ac.setSystemMessage(title, desc) end
end

-- Smoothstep gain schedule: gainLow below speedLow, easing to gainHigh above
-- speedHigh, with a smooth (no-kink) transition between.
local function steerGain(p, speedKmh)
  local span = math.max(1e-3, p.speedHigh - p.speedLow)
  local t = math.saturate((speedKmh - p.speedLow) / span)
  t = t * t * (3 - 2 * t)                 -- smoothstep
  return math.lerp(p.gainLow, p.gainHigh, t)
end

function script.reset()
  profile, enabled = 'COMFORT', ENABLED_AT_START
end

function script.update(dt)
  -- One-time probe: is the steering input writable on this build? If not we only
  -- display and never touch physics (graceful degrade, like the ESS damper probe).
  if steerWritable == nil then
    steerWritable = pcall(function() carPh.steer = carPh.steer end)
  end

  -- EXTRA_C: enable / disable Active Steering (OFF = stock fixed ratio).
  if car.extraC ~= extraCPrev then
    extraCPrev = car.extraC
    if car.extraC then
      enabled = not enabled
      message('Active Steering', enabled and 'ON' or 'OFF (stock ratio)')
    end
  end

  -- EXTRA_A: swap COMFORT / SPORT schedule.
  if car.extraA ~= extraAPrev then
    extraAPrev = car.extraA
    if car.extraA then
      profile = (profile == 'COMFORT') and 'SPORT' or 'COMFORT'
      message('Active Steering', profile .. ' schedule')
    end
  end

  local p     = PROFILES[profile]
  local speed = car.speedKmh
  local gain  = steerGain(p, speed)

  -- The driver's normalised steering, captured before we re-map it. +/-1 is the
  -- car's mechanical full lock.
  local s   = carPh.steer
  local out = s

  if enabled and steerWritable then
    -- Optional on-centre softening: shape the magnitude only, keep the sign and
    -- the endpoints (0->0, 1->1). centerExp == 1 makes this a no-op.
    local mag = math.abs(s)
    if p.centerExp ~= 1.0 then mag = mag ^ p.centerExp end
    -- Apply the speed-scheduled gain, restore the sign, and clamp to the rack's
    -- limits. With gain > 1, full lock is reached before full input travel — that
    -- early clamp IS the quicker ratio, not a bug.
    out = math.clamp((s < 0 and -mag or mag) * gain, -1, 1)
    carPh.steer = out
  end

  -- ====================================================================
  -- DEBUG (Lua Debug app) — show the effective ratio the driver feels now.
  -- ====================================================================
  -- A higher gain divides the stock ratio down (quicker); a lower gain
  -- multiplies it up (slower). Effective lock-to-lock turns scale the same way.
  local effRatio = baseRatio / math.max(1e-3, gain)
  local effTurns = (baseLock / 180) / math.max(1e-3, gain)   -- approx full turns L->R
  local feel = gain > 1.02 and 'quicker' or (gain < 0.98 and 'slower' or 'neutral')

  ac.debug('AS state', (enabled and ('ON  ' .. profile) or 'OFF (stock ratio)')
    .. (steerWritable and '' or '   [steer not writable on this CSP build]'))
  ac.debug('AS speed', string.format('%.0f km/h', speed))
  ac.debug('AS gain', string.format('%.2f x   (%s)', gain, feel))
  ac.debug('AS effective ratio', string.format('%.1f : 1   (stock %.1f : 1)', effRatio, baseRatio))
  ac.debug('AS lock-to-lock', string.format('%.1f turns   (stock %.1f)',
    effTurns, (baseLock / 180)))
  ac.debug('AS steer in/out', string.format('%+.2f -> %+.2f', s, out))
end
