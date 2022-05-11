-- PlayerData
-- Quantum Maniac
-- Mar 25 2022

--[[
	This module is used to access the data of a player currently in-game.
]]

--\\ Constants //--

local LOAD_FAIL_KICK_MESSAGE = "Failed to load your data. You have been kicked to avoid corrupting your save. Please rejoin."
local AUTO_SAVE_INTERVAL = 5 * 60
local DEFAULT_PLAYER_DATA = {
	Version = 1,
	SaveIndex = 1,
}

--\\ Dependencies //--

local etable = require(game.ReplicatedStorage.Common.ExtendedTable)
local Save

--\\ Module //--

local PlayerData = {}

--\\ Private //--

local playerLoadedBindables = {}
local dataChangedEvents = {}
local accessorCache = {}
local rawDataCache = {}

-- Fires any events that are listening for changes in the passed key.
local function firePlayerDataChanged(player: Player, key: any, oldValue: any, newValue: any)
	local event = dataChangedEvents[key]
	if event then
		event:Fire(player, oldValue, newValue)
	end
end

-- Creates a new accessor table for the player data. This is done to utilize metamethods that
-- detect when the table is modified.
local function newPlayerData(player: Player, rawData: table): nil
	local accessor = {}

	setmetatable(accessor, {
		__index = rawData,						-- Reading from the table is direct

		__newindex = function(self, key, value)	-- Modifying the table will fire any listening events
			local oldValue = rawData[key]
			rawData[key] = value
			firePlayerDataChanged(player, key, oldValue, value)
		end,

		__metatable = false						-- Lock access to the metatable
	})

	-- Save the raw data to the cache so it can be accessed by private saving functions.
	-- This provides faster access to the data for shorter saving times.
	rawDataCache[player] = rawData

	return accessor
end

-- Fires the playerLoadedBindable event for the given player if it exists, passing the given value.
local function firePlayerLoadedBindable(player: Player, value: boolean): nil
	local playerLoadedBindable = playerLoadedBindables[player]
	if playerLoadedBindable then
		playerLoadedBindable:Fire(value)
	end
end

-- Loads the player's data and initializes them into the module.
local function loadPlayerData(player: Player): nil
	-- Get their saved data
	local save = Save.new(player.UserId)
	local success, rawData = save:GetData()

	-- If their data failed to load, kick them to prevent overwriting their save.
	if not success then
		player:Kick(LOAD_FAIL_KICK_MESSAGE)
		firePlayerLoadedBindable(player, false)
		return
	end

	-- Use the default data if they have no existing data.
	local newPlayer = rawData == nil
	if newPlayer then
		rawData = etable.Clone(DEFAULT_PLAYER_DATA, true)
	end

	-- Check for data loss and recover if so.
	if not rawData.SaveIndex or rawData.SaveIndex <= 1 then		-- If the save index is missing or 1 and there is a save history, then there was data loss.
		local lastSaveIndex = rawData.SaveIndex
		local success, timestamps = save:GetTimestampHistory(100)

		if not success then
			player:Kick(LOAD_FAIL_KICK_MESSAGE)
			firePlayerLoadedBindable(player, false)
			return
		end

		for _, timestamp in ipairs(timestamps) do
			local success, oldData = save:GetData(timestamp)

			if not success then
				player:Kick(LOAD_FAIL_KICK_MESSAGE)
				firePlayerLoadedBindable(player, false)
				return
			end

			-- SaveIndex should be ascending (we are traversing in reverse order, so it should appear to be descending).
			-- When we find an out-of-order SaveIndex, we found the point where the data loss occurred.
			if oldData.SaveIndex then
				if not lastSaveIndex or oldData.SaveIndex > lastSaveIndex then
					warn("Player " .. player.Name .. " experienced data loss. Reverting to " .. oldData.SaveIndex)
					rawData = oldData
					break
				end
				lastSaveIndex = oldData.SaveIndex
			end
		end
	end

	-- Fills in any fields that are present in DEFAULT_PLAYER_DATA, but missing in the given data.
	for i,v in pairs(DEFAULT_PLAYER_DATA) do
		if not rawData[i] then
			rawData[i] = v
		end
	end

	-- Create an accessor for the player and save it to the cache.
	local data = newPlayerData(player, rawData)
	accessorCache[player] = data

	-- Fire the event to release any threads waiting for them to load.
	firePlayerLoadedBindable(player, true)
end

-- Saves and unloads the player's data.
local function freePlayerData(player: Player): nil
	-- Fetch their data from the chache.
	local rawData = rawDataCache[player]
	if not rawData then
		return
	end

	-- Save it to the datastore.
	local save = Save.new(player.UserId)
	rawData.SaveIndex += 1
	save:SafeSaveData(rawData)

	-- Clear the caches for the player.
	accessorCache[player] = nil
	rawDataCache[player] = nil
end

-- Loops through all the players currently cached and saves their data.
local function saveAllPlayerData(): nil
	for player, data in pairs(rawDataCache) do
		local save = Save.new(player.UserId)
		data.SaveIndex += 1
		save:SaveData(data)
	end
end

-- Similar to saveAllPlayerData(), except uses SafeSave().
local function safeSaveAllPlayerData(): nil
	for player, data in pairs(rawDataCache) do
		local save = Save.new(player.UserId)
		data.SaveIndex += 1
		task.spawn(save.SafeSaveData, save, data)
	end
end

-- Infininite loop that saves every player's data every AUTO_SAVE_INTERVAL seconds.
local function autoSaveLoop(): nil
	while true do
		task.wait(AUTO_SAVE_INTERVAL)
		saveAllPlayerData()
	end
end

--\\ Public //--

function PlayerData.Init(): nil
	Save = require(script.Parent.Save)
end

function PlayerData.Start(): nil
	game.Players.PlayerAdded:Connect(loadPlayerData)
	game.Players.PlayerRemoving:Connect(freePlayerData)
	game:BindToClose(safeSaveAllPlayerData)
	task.spawn(autoSaveLoop)
end

-- Gets the player's data.
-- Returns a tuple containing a boolean that indicates if the data was successfully retrieved, and
-- an accessor table for the player's data.
-- If yielding is true, the function will yield until the data is available.
function PlayerData.GetPlayerData(player: Player, yielding: boolean?)
	local data = accessorCache[player]
	local success = data ~= nil

	-- If the data isn't ready yet and we need to yield (and the player still exists, to be safe).
	if player and player.Parent and not data and yielding then

		-- Get the player loaded bindable if it exists, otherwise create one.
		-- I don't think it's possible for bindable to already exist, but it doesn't hurt to be safe.
		local playerLoadedBindable = playerLoadedBindables[player] or Instance.new("BindableEvent")
		playerLoadedBindables[player] = playerLoadedBindable

		-- Wait for the bindable to fire. It returns true if the data loaded properly, or false
		-- if the data failed to load.
		success = playerLoadedBindable:Wait()

		-- Clean up.
		playerLoadedBindable:Destroy()
		playerLoadedBindables[player] = nil
	end

	return success, data
end

-- Returns a signal that fires when a player's data is modified at the given key.
function PlayerData.GetDataChangedSignal(key: any): RBXScriptSignal
	local event = dataChangedEvents[key]
	if not event then
		event = Instance.new("BindableEvent")
		dataChangedEvents[key] = event
	end

	return event.Event
end

--\\ Return //--

return PlayerData