-- extension/lua/prius_cvt.lua
-- Honda CR-Z Simulation
-- LOGIC: Original Prius Clutch (Unchanged)
-- FIX: Active RPM Governor to hold 6000 RPM exactly

-- STATE VARIABLES
local initialized = false
local carPh = nil
local smoothedRPM = 1000
local shiftTimer = 0
local lastGear = 0
local engageTimer = 0

-- ==========================================
--               CONFIGURATION
-- ==========================================
local idleRPM = 800

-- THE HOLD POINT: 6000 RPM
-- The script will fight to keep the engine here.
local peakRPM = 6000

-- RATIO LIMITS (CR-Z Spec)
local maxRatio = 13.32
local minRatio = 2.22

-- DRIVING FEEL
local throttleCurve = 1.0
local reactionSpeedUp = 4.0
local reactionSpeedDown = 0.5
local coastFactor = 25.0

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

    local currentGear = carPh.gear

    if currentGear ~= lastGear then
        if lastGear == 0 and currentGear ~= 0 then
            shiftTimer = 0.5
            engageTimer = 0.0
        end
        lastGear = currentGear
    end
    if shiftTimer > 0 then shiftTimer = shiftTimer - dt end
    if engageTimer < 1.0 then engageTimer = engageTimer + (dt * 1.5) end

    local gas = carPh.gas
    local speed = carPh.speedKmh
    local brake = carPh.brake
    local engineRPM = carPh.rpm -- Live RPM

    -- RPM TARGETS
    local driveRPM = idleRPM + (math.pow(gas, throttleCurve) * (peakRPM - idleRPM))

    -- HARD CAP: Never target higher than Peak
    if driveRPM > peakRPM then driveRPM = peakRPM end

    local coastRPM = math.max(idleRPM, speed * coastFactor)
    local targetRPM = math.max(driveRPM, coastRPM)

    local reaction = 0
    if targetRPM > smoothedRPM then
        reaction = reactionSpeedUp
    else
        local gap = smoothedRPM - targetRPM
        reaction = math.lerp(0.1, reactionSpeedDown, math.clamp(gap / 1500, 0, 1))
    end
    smoothedRPM = smoothedRPM + (targetRPM - smoothedRPM) * dt * reaction

    -- RATIO CALCULATION (CR-Z 16" Wheels)
    local trueWheelSpeed = (math.max(1.0, speed) / 3.6) / 0.310
    local engineSpeed = smoothedRPM * 0.10472
    local requiredTotalRatio = engineSpeed / trueWheelSpeed

    -- ==================================================
    --  ACTIVE CORRECTION (THE FIX)
    -- ==================================================
    -- This ignores the calculated ratio and takes control if RPM is too high.

    -- 1. Check Overshoot
    -- If we are even 50 RPM over the target (6050+), we intervene.
    if engineRPM > (targetRPM + 50) then

        -- 2. Calculate Correction Force
        -- The further over we are, the harder we push the ratio down (Shift Up).
        -- Example: 100 RPM over = 0.98 multiplier (2% taller gear per frame)
        -- Example: 500 RPM over = 0.90 multiplier (10% taller gear per frame)
        local error = engineRPM - targetRPM
        local correction = 1.0 - (error * 0.0002)

        -- 3. Apply Correction
        requiredTotalRatio = requiredTotalRatio * correction
    end

    -- Standard Clamp
    if requiredTotalRatio > maxRatio then requiredTotalRatio = maxRatio end
    if requiredTotalRatio < minRatio then requiredTotalRatio = minRatio end

    -- OUTPUT
    if speed > 1 then ac.setGearsFinalRatio(requiredTotalRatio) end

    if speed < 1.0 and currentGear ~= 0 and brake < 0.01 then ac.awakeCarPhysics() end

    ac.overrideSpecificValue(ac.CarPhysicsValueID.DrivetrainClutchOverride, 1)
end
