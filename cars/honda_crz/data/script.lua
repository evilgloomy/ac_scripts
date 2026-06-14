-- Honda CR-Z — CVT simulation
-- CSP car physics script (must live at <car>/data/script.lua)
--
-- Models a continuously variable transmission by continuously trimming the
-- final-drive ratio so the engine sits at a throttle-chosen target RPM, with
-- the proven fluid-coupling clutch handling launch/creep.
--
-- Control overview:
--   1. Target RPM from throttle: a light "eco" band (<= ecoThrottle) keeps revs
--      low so the ratio drops (upshifts) early when cruising; above it the
--      target ramps up to the peak-power hold point.
--   2. Feed-forward ratio = the ratio that puts the engine at that target for
--      the current wheel speed (exact at steady state).
--   3. Closed-loop governor (symmetric PI on ACTUAL rpm error) trims the ratio
--      so the engine actually HOLDS the target instead of flaring past it.

-- STATE VARIABLES
local initialized = false
local carPh = nil
local smoothedRPM = 1000
local lastGear = 0
local engageTimer = 0
local govIntegral = 0       -- governor integral term (anti-windup clamped)
local currentRatio = nil    -- slew-limited final-drive ratio (lazy-init to maxRatio)

local RPM_TO_RAD = 0.10472  -- 2*pi/60: rpm -> rad/s

-- ==========================================
--               CONFIGURATION
-- ==========================================
-- Engine operating points (rpm)
local idleRPM     = 800
local cruiseRPM   = 1300    -- light-cruise target: lowest RPM the CVT settles to
                            -- while rolling (tall gear / low ratio)
local ecoThrottle = 0.30    -- throttle at/below this stays in the low "eco" band
                            -- => ratio reduces (upshifts) earlier on light pedal
local ecoTopRPM   = 2200    -- target RPM at the top of the eco band (gas == ecoThrottle)
local peakRPM     = 6000    -- PEAK-POWER HOLD POINT: WOT target the governor pins to

-- Engine braking: only fades in once you're (nearly) off the gas, so it can
-- never prop up light-throttle cruising (that was the old coastFactor=25 issue).
local closedThrottle = 0.06 -- below this throttle the engine-braking floor fades in
local coastFactor    = 14.0 -- km/h -> min RPM when fully off the gas

-- Ratio limits (CR-Z spec) and wheel
local maxRatio    = 13.32
local minRatio    = 2.22
local wheelRadius = 0.310   -- m, rolling radius (16" wheel)

-- Target-RPM smoothing (how fast the GOAL moves; reaction = 1/time-constant)
local reactionUp        = 5.0   -- rev up promptly when you get on the throttle
local reactionDownLight = 3.5   -- light throttle: let revs fall quickly (reduce ratio early)
local reactionDownHeavy = 1.2   -- near WOT: ease down gently

-- RPM governor (closed loop on ACTUAL rpm; this is what holds the peak)
local govP         = 1.8    -- proportional gain (fractional ratio trim per unit norm error)
local govI         = 1.2    -- integral gain (removes steady-state offset)
local govTrimLimit = 0.35   -- max fractional ratio trim the governor may apply
local govIntLimit  = 0.25   -- integral clamp (anti-windup)
local ratioRate    = 30.0   -- max ratio units/sec the output may slew (anti-snap)

-- FLUID COUPLING (Your Working Prius Settings)
local creepViscosity = 0.10
local driveViscosity = 0.50
local lockedViscosity = 100.0

-- ==========================================
--              CLUTCH LOGIC
-- ==========================================
-- (This is 100% identical to the code that worked for you)
local function customClutchLogic(engineVelocity, rootVelocity, engineInertia, rootInertia, clutchAmount, dt)
    local gasInput = 0
    local brakeInput = 0
    local gear = 0

    if not carPh then return 0, 0 end

    gasInput = carPh.gas
    brakeInput = carPh.brake
    gear = carPh.gear

    if gear == 0 then return 0, 0 end

    -- SPEEDS
    local slipRad = engineVelocity - rootVelocity
    local engineRPM = engineVelocity * 9.55

    -- FLUID COUPLING
    local lockupFactor = 0.0
    if math.abs(rootVelocity) > 20.0 and engineRPM > 1100 then
        lockupFactor = math.clamp((math.abs(rootVelocity) - 20.0) / 40.0, 0.0, 1.0)
    end

    local activeViscosity = math.lerp(creepViscosity, driveViscosity, gasInput)
    local finalViscosity = math.lerp(activeViscosity, lockedViscosity, lockupFactor)

    if engineRPM < 1000 and gasInput > 0.01 then finalViscosity = creepViscosity end

    local pressure = math.min(engageTimer, 1.0)
    if (brakeInput > 0.1) and math.abs(rootVelocity) < 10.0 then pressure = 0.0 end

    -- TORQUE
    local torque = slipRad * finalViscosity * pressure

    -- Keep this high to ensure the engine doesn't slip past the limiter
    torque = math.clamp(torque, -1000.0, 1000.0)

    -- OUTPUT
    local torqueToEngine = torque
    local torqueToWheels = torque

    if math.abs(rootVelocity) < 0.2 and gear ~= 0 and brakeInput < 0.01 then
        if torqueToWheels < 20.0 then torqueToWheels = 20.0 end
        torqueToEngine = 0
    end

    local combinedInertia = (1 / math.max(0.01, engineInertia)) + (1 / math.max(0.01, rootInertia))
    local maxPhysicalTorque = math.abs(slipRad) / (math.max(0.0001, dt) * combinedInertia)
    local safeLimit = maxPhysicalTorque * 0.90

    torqueToEngine = math.clamp(torqueToEngine, -safeLimit, safeLimit)
    torqueToWheels = math.clamp(torqueToWheels, -safeLimit, safeLimit)

    return -torqueToEngine, torqueToWheels
end

-- ==========================================
--              MAIN LOOP
-- ==========================================
function script.update(dt)
    if not initialized then
        carPh = ac.accessCarPhysics()
        if carPh then
            ac.replaceClutch(customClutchLogic)
            ac.awakeCarPhysics()
            initialized = true
        end
        return
    end

    currentRatio = currentRatio or maxRatio

    local currentGear = carPh.gear

    -- Launch engagement: restart the clutch pressure ramp when leaving neutral
    if currentGear ~= lastGear then
        if lastGear == 0 and currentGear ~= 0 then engageTimer = 0.0 end
        lastGear = currentGear
    end
    if engageTimer < 1.0 then engageTimer = engageTimer + (dt * 1.5) end

    local gas       = math.clamp(carPh.gas, 0.0, 1.0)
    local brake     = math.clamp(carPh.brake, 0.0, 1.0)
    local speed     = carPh.speedKmh
    local engineRPM = carPh.rpm

    -- ---------------------------------------------------------------
    -- 1. TARGET RPM
    --    Eco band (gas <= ecoThrottle): low revs so the ratio reduces
    --    (upshifts) early on a light pedal. Power band: ramp to peak.
    -- ---------------------------------------------------------------
    local demandRPM
    if gas <= ecoThrottle then
        demandRPM = math.lerp(cruiseRPM, ecoTopRPM, gas / ecoThrottle)
    else
        demandRPM = math.lerp(ecoTopRPM, peakRPM, (gas - ecoThrottle) / (1.0 - ecoThrottle))
    end

    -- Engine-braking floor, blended in only as the throttle closes
    local brakingBlend = 1.0 - math.clamp(gas / closedThrottle, 0.0, 1.0)
    local coastRPM = math.lerp(idleRPM, math.max(idleRPM, speed * coastFactor), brakingBlend)

    local targetRPM = math.max(idleRPM, demandRPM, coastRPM)
    if targetRPM > peakRPM then targetRPM = peakRPM end

    -- ---------------------------------------------------------------
    -- 2. SMOOTH THE TARGET (throttle-aware: up quick; down quick when
    --    light so the ratio reduces early, gentle when near WOT)
    -- ---------------------------------------------------------------
    local reaction
    if targetRPM > smoothedRPM then
        reaction = reactionUp
    else
        reaction = math.lerp(reactionDownLight, reactionDownHeavy, gas)
    end
    smoothedRPM = smoothedRPM + (targetRPM - smoothedRPM) * math.clamp(dt * reaction, 0.0, 1.0)

    -- ---------------------------------------------------------------
    -- 3. FEED-FORWARD RATIO (exact ratio for smoothedRPM at this speed)
    -- ---------------------------------------------------------------
    local wheelRad = math.max(0.5, (speed / 3.6) / wheelRadius)   -- rad/s, floored near standstill
    local ratioFF = (smoothedRPM * RPM_TO_RAD) / wheelRad

    -- ---------------------------------------------------------------
    -- 4. GOVERNOR — symmetric PI on ACTUAL rpm error.
    --    err > 0 (revving past target) -> trim ratio DOWN (taller gear);
    --    err < 0 (under target)        -> trim ratio UP. This is what
    --    actually holds the peak instead of letting it flare over.
    -- ---------------------------------------------------------------
    local err = (engineRPM - smoothedRPM) / peakRPM               -- normalized, signed
    govIntegral = math.clamp(govIntegral + err * dt, -govIntLimit, govIntLimit)
    local trim = math.clamp(-(govP * err + govI * govIntegral), -govTrimLimit, govTrimLimit)

    local rawCmd = ratioFF * (1.0 + trim)
    local ratioCmd = math.clamp(rawCmd, minRatio, maxRatio)

    -- Anti-windup: if we're saturated against a limit and the error still
    -- pushes further into it, undo this frame's integration.
    if (rawCmd > maxRatio and err < 0) or (rawCmd < minRatio and err > 0) then
        govIntegral = govIntegral - err * dt
    end

    -- ---------------------------------------------------------------
    -- 5. SLEW + OUTPUT
    -- ---------------------------------------------------------------
    local maxStep = ratioRate * dt
    currentRatio = currentRatio + math.clamp(ratioCmd - currentRatio, -maxStep, maxStep)

    if speed > 1.0 then
        ac.setGearsFinalRatio(currentRatio)
    else
        -- Standstill: hold the launch ratio and keep the integral clean so the
        -- next pull-away starts from the tall, high-multiplication gear.
        currentRatio = maxRatio
        govIntegral = 0.0
        if currentGear ~= 0 and brake < 0.01 then ac.awakeCarPhysics() end
    end

    ac.overrideSpecificValue(ac.CarPhysicsValueID.DrivetrainClutchOverride, 1)
end
