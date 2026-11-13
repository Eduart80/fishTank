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

-- 0 = full day, 1 = deep night. Dusk 17.5 -> 19, dawn 5 -> 6.5.
function DayNight.darkness(clock: number): number
	if clock >= 6.5 and clock <= 17.5 then
		return 0
	elseif clock > 17.5 and clock < 19 then
		return (clock - 17.5) / 1.5
	elseif clock > 5 and clock < 6.5 then
		return (6.5 - clock) / 1.5
	end
	return 1
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
