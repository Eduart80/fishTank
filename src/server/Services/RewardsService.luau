-- Free-growth rewards: daily login streak + invite-a-friend.
-- Pure rules on the data table (testable); Main.server decides when to call them and sends the toasts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local TankService = require(script.Parent.TankService)

local RewardsService = {}

-- Day number (UTC midnight on live servers; Studio uses short days, see Config.DAY_SECONDS)
function RewardsService.dayOf(now: number): number
	return now // Config.DAY_SECONDS
end

-- Gives one reward entry { coins = n } / { egg = id } / both. An egg that doesn't fit in the tank
-- becomes its egg price in coins. Returns the text part, e.g. "+50 coins and a Clownfish egg".
local function grant(data, reward, now: number): string
	local parts = {}
	local coins = reward.coins or 0
	if reward.egg then
		local species = Config.ById[reward.egg]
		if species and TankService.giveEgg(data, reward.egg, now) then
			table.insert(parts, ("a %s egg"):format(species.name))
		elseif species then
			coins += species.eggPrice -- tank full
		end
	end
	if coins > 0 then
		data.coins += coins
		table.insert(parts, 1, ("+%d coins"):format(coins))
	end
	return table.concat(parts, " and ")
end

local function describe(reward): string
	local species = reward.egg and Config.ById[reward.egg]
	if species and reward.coins then
		return ("%d coins + a %s egg"):format(reward.coins, species.name)
	elseif species then
		return ("a %s egg"):format(species.name)
	end
	return ("%d coins"):format(reward.coins or 0)
end

-- Once per day. Next day in a row = streak + 1, a missed day = back to 1. Rewards loop every
-- #DAILY_REWARDS days (the streak number keeps counting). Returns the toast text, or nil if
-- today's reward was already taken.
function RewardsService.claimDaily(data, now: number): string?
	local today = RewardsService.dayOf(now)
	local daily = data.daily
	if daily and daily.day == today then
		return nil
	end
	local streak = if daily and daily.day == today - 1 then daily.streak + 1 else 1
	data.daily = { day = today, streak = streak }
	local list = Config.DAILY_REWARDS
	local reward = list[(streak - 1) % #list + 1]
	if data.vip and reward.coins then
		reward = table.clone(reward)
		reward.coins *= 2 -- VIP pass: double daily coins
	end
	local got = grant(data, reward, now)
	local nextReward = list[streak % #list + 1]
	local head = if streak == 1 then "Daily reward!" else ("Day %d streak!"):format(streak)
	return ("%s %s. Come back tomorrow for %s!"):format(head, got, describe(nextReward))
end

-- Brand-new player who joined through a friend's invite / share link.
-- invitee gets a gift; the inviter (if online on this server) gets coins, capped per lifetime.
-- Returns (inviteeText?, inviterText?).
function RewardsService.applyInvite(newData, inviterData, inviterName: string, newName: string, now: number)
	if newData.invitedBy then
		return nil, nil
	end
	newData.invitedBy = true
	local inviteeText = ("%s invited you: %s!"):format(inviterName, grant(newData, Config.INVITE.newPlayerGift, now))
	local inviterText = nil
	if inviterData then
		local count = inviterData.inviteRewards or 0
		if count < Config.INVITE.maxRewards then
			inviterData.inviteRewards = count + 1
			inviterText = ("%s joined from your invite: %s!"):format(newName, grant(inviterData, { coins = Config.INVITE.inviterCoins }, now))
		end
	end
	return inviteeText, inviterText
end

-- Milestones: newly unlocked fish + the Harbor Master moment (Koi unlocked AND Sea Pen).
-- Returns { unlocked = { species... }, harborMaster = true if it JUST happened }.
-- First call on an old save only records what the player already has (no announcement spam).
function RewardsService.checkMilestones(data)
	local result = { unlocked = {}, harborMaster = false }
	local first = data.unlocked == nil
	data.unlocked = data.unlocked or {}
	for _, species in Config.Species do
		if (species.unlockEarned or 0) > 0 and data.stats.earned >= species.unlockEarned and not data.unlocked[species.id] then
			data.unlocked[species.id] = true
			if not first then
				table.insert(result.unlocked, species)
			end
		end
	end
	local top = Config.Species[#Config.Species]
	local seaPen = Config.TANK_STAGES[#Config.TANK_STAGES]
	if not data.harborMaster and data.unlocked[top.id] and data.slots >= seaPen.minSlots then
		data.harborMaster = true
		result.harborMaster = not first
	end
	return result
end

-- "New" = data created in the last few minutes (old saves have no `created` = never new).
function RewardsService.isNewPlayer(data, now: number): boolean
	return data.created ~= nil and now - data.created < 600
end

return RewardsService
