-- Where the fishing boat is at any moment. Shared so the server (dock spot) and every client
-- (smooth animation) agree. Time = workspace:GetServerTimeNow(), the same on all machines.
-- Boat front = local -Z.

local BoatPath = {}

local Y = -1 -- hull centre: water surface is -1.5, pier deck top is 0.9
BoatPath.DOCK = Vector3.new(19.5, Y, 174) -- right side of the pier platform (platform spans x -13..13)
BoatPath.START = Vector3.new(19.5, Y, 560) -- far out at sea, straight behind the pier
BoatPath.FINISH = Vector3.new(320, Y, 520)

BoatPath.ARRIVE_SECONDS = 25
BoatPath.LEAVE_SECONDS = 25

local arriveRot = CFrame.lookAt(Vector3.zero, BoatPath.DOCK - BoatPath.START)
local leaveRot = CFrame.lookAt(Vector3.zero, BoatPath.FINISH - BoatPath.DOCK)

-- Returns the boat CFrame, or nil when the boat is away (not visible).
function BoatPath.cframeAt(state: string, phaseStart: number, now: number): CFrame?
	local pos, rot
	if state == "arriving" then
		local a = math.clamp((now - phaseStart) / BoatPath.ARRIVE_SECONDS, 0, 1)
		local e = 1 - (1 - a) ^ 2 -- slow down into the dock
		pos = BoatPath.START:Lerp(BoatPath.DOCK, e)
		rot = arriveRot
	elseif state == "docked" then
		pos = BoatPath.DOCK
		rot = arriveRot
	elseif state == "leaving" then
		local a = math.clamp((now - phaseStart) / BoatPath.LEAVE_SECONDS, 0, 1)
		pos = BoatPath.DOCK:Lerp(BoatPath.FINISH, a * a) -- speed up away from the dock
		rot = arriveRot:Lerp(leaveRot, math.min(1, a * 6)) -- turn first, then sail off
	else
		return nil
	end
	local bob = Vector3.new(0, math.sin(now * 1.3) * 0.25, 0)
	return CFrame.new(pos + bob) * rot * CFrame.Angles(0, 0, math.sin(now * 0.9) * 0.03)
end

return BoatPath
