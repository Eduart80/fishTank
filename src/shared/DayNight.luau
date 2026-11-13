-- Time of day from the shared server clock (workspace:GetServerTimeNow()), so every player on every
-- server sees the same sky. Day: ClockTime 6 -> 18 over Config.DAY_NIGHT.daySeconds,
-- night: 18 -> 6 over nightSeconds.

local Config = require(script.Parent.Config)

local DayNight = {}

function DayNight.clockAt(t: number): number
	local day, night = Config.DAY_NIGHT.daySeconds, Config.DAY_NIGHT.nightSeconds
	local x = t % (day + night)
	if x < day then
		return 6 + 12 * x / day
	end
	return (18 + 12 * (x - day) / night) % 24
end

-- 0 = full day, 1 = deep night. Starts only AFTER sunset (18:00 -> 19:15) and ends at sunrise
-- (4:45 -> 6:00): before, the blue night tint came on while the sun was still up.
function DayNight.darkness(clock: number): number
	if clock >= 6 and clock <= 18 then
		return 0
	elseif clock > 18 and clock < 19.25 then
		return (clock - 18) / 1.25
	elseif clock > 4.75 and clock < 6 then
		return (6 - clock) / 1.25
	end
	return 1
end

-- 0..1 golden-hour warmth: rises towards sunset (16:30 -> 18:00), fades at dusk (-> 19:00);
-- same around sunrise (5:00 -> 6:00 -> 7:30).
function DayNight.warmth(clock: number): number
	if clock >= 16.5 and clock <= 18 then
		return (clock - 16.5) / 1.5
	elseif clock > 18 and clock < 19 then
		return 1 - (clock - 18)
	elseif clock >= 6 and clock < 7.5 then
		return 1 - (clock - 6) / 1.5
	elseif clock > 5 and clock < 6 then
		return clock - 5
	end
	return 0
end

-- Moon phase of the night that belongs to time t (the night at the end of each day/night cycle).
-- Returns the Config.MOON_PHASES entry. Same on every server.
function DayNight.moonPhase(t: number)
	local cycle = Config.DAY_NIGHT.daySeconds + Config.DAY_NIGHT.nightSeconds
	local phases = Config.MOON_PHASES
	return phases[(t // cycle) % #phases + 1]
end

-- Weather Radio: start of the next full-moon night (now if it is one right now).
function DayNight.nextFullMoon(now: number): number
	local day, night = Config.DAY_NIGHT.daySeconds, Config.DAY_NIGHT.nightSeconds
	local cycle = day + night
	for k = now // cycle, now // cycle + #Config.MOON_PHASES do
		local nightStart = k * cycle + day
		if Config.MOON_PHASES[k % #Config.MOON_PHASES + 1].key == "full" and nightStart + night > now then
			return math.max(now, nightStart)
		end
	end
	return now
end

function DayNight.phaseByKey(key: string)
	for _, phase in Config.MOON_PHASES do
		if phase.key == key then
			return phase
		end
	end
	return nil
end

return DayNight
