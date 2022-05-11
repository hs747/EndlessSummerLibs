-- Save
-- Quantum Maniac
-- Mar 25 2022

--[[
	This module is in charge of saving and loading player save data to and from the datastore
]]

--Module
local Save = {}
Save.__index = Save

--Constants
local SAVE_RETRY_INTERVAL = 1
local SAVE_RETRY_ATTEMPTS = 3

--Types
export type Save = {
	Destroyed: boolean,
	UserId: number,
	OrderedDataStore: OrderedDataStore,
	DataStore: DataStore,
	LastSave: string?
}

--\\ Private //--
local dataStoreService = game:GetService("DataStoreService")
local httpService = game:GetService("HttpService")
local runService = game:GetService("RunService")

local saveCache = {}

--[[
	Pcalls the passed function up to SAVE_RETRY_INTERVAL times, or until
	the function does not error
]]
local function retry(foo: ()->any?): any?
	local attempts = 0
	local success, message, data

	repeat
		attempts += 1
		success, message = pcall(function()
			data = foo()
		end)
		if not success then
			task.wait(SAVE_RETRY_INTERVAL)
		end
	until success or attempts >= SAVE_RETRY_ATTEMPTS

	if not success then
		warn("Failed to reach datastore: " .. message .. "\n" .. debug.traceback())
	end

	return success, data
end

--\\ Public //--

--[[
	Save constructor. Returns the save object associated with the passed user ID
	If a save object already exists for that user ID, it is returned from the cache and no
	new object is created
]]
function Save.new(userId: number): Save
	if saveCache[userId] then
		return saveCache[userId]
	end

	local self = {}
	setmetatable(self, Save)

	self.Destroyed = false
	self.UserId = userId
	self.OrderedDataStore = dataStoreService:GetOrderedDataStore(tostring(userId), "PlayerSaveHistory_1")
	self.DataStore = dataStoreService:GetDataStore(tostring(userId), "PlayerSaves_1")

	saveCache[userId] = self

	return self
end

--[[
	Completely erases all data for the passed user ID. For safety, this function can only be called
	from Studio. This is only meant to be used in the case of a data erasure request from Roblox
]]
function Save.DeleteUserData(userId: number): nil
	if not runService:IsStudio() then
		error("This function can only be called from Roblox Studio", 2)
	end

	local orderedDataStore = dataStoreService:GetOrderedDataStore(tostring(userId), "PlayerSaveHistory_1")
	local pages = orderedDataStore:GetSortedAsync(false, 100)
	repeat
		for _, pair in ipairs(pages:GetCurrentPage()) do
			local key = pair.key
			orderedDataStore:RemoveAsync(key)
		end
	until pages:IsFinished()

	local dataStore = dataStoreService:GetDataStore(tostring(userId), "PlayerSaves_1")
	pages = dataStore:ListKeysAsync()
	repeat
		for _, dataStoreKey in ipairs(pages:GetCurrentPage()) do
			local key = dataStoreKey.KeyName
			dataStore:RemoveAsync(key)
		end
	until pages:IsFinished()
end

--[[
	Destroys and uncaches the save
]]
function Save:Destroy(): nil
	self.Destroyed = true
	saveCache[self.UserId] = nil
end

--[[
	Saves the passed data to the datastore
	Returns a boolean that indicates whether the data was saved successfully
	Note: If the data being saved is identical to the currently saved data,
	this function simply returns true and does not make a save API request
]]
function Save:SaveData(data: table): (boolean, ...any)
	if self.Destroyed then
		error("Error saving data, this save instance is destroyed.", 2)
	end

	local encodedData = httpService:JSONEncode(data)
	if encodedData == self.LastSave then
		return true
	end

	local success, message = pcall(function()
		local timestamp = os.time()
		self.DataStore:SetAsync(timestamp, encodedData)
		self.OrderedDataStore:SetAsync(timestamp, timestamp)
		self.LastSave = encodedData
	end)

	if not success then
		warn("Failed to save player data: " .. message)
	end

	return success
end

--[[
	Same as Save() but will retry up to SAVE_RETRY_ATTEMPTS times
	If this function fails, it will print a warning and the data is considered lost
	Returns a boolean that indicates whether the data was saved successfully
]]
function Save:SafeSaveData(data: table): boolean
	if self.Destroyed then
		error("Error saving data, this save instance is destroyed.", 2)
	end

	local encodedData = httpService:JSONEncode(data)
	if encodedData == self.LastSave then
		return true
	end

	local timestamp = os.time()
	local success = retry(function()
		self.DataStore:SetAsync(timestamp, encodedData)
		self.OrderedDataStore:SetAsync(timestamp, timestamp)
		self.LastSave = encodedData
	end)

	if not success then
		warn("FAILED TO SAVE DATA FOR USER " .. self.UserId .. " AFTER " .. SAVE_RETRY_ATTEMPTS .. " ATTEMPTS.")
	end

	return success
end

--[[
	Gets the latest timestamp that the player has a save in
	Returns a tuple containing a boolean that indicates if the
	timestamp was successfully retrieved, and the timestamp itself
	if it exists
]]
function Save:GetLatestSaveTimestamp(): (boolean, number?)
	if self.Destroyed then
		error("Error getting data, this save instance is destroyed.", 2)
	end

	return retry(function()
		local pages = self.OrderedDataStore:GetSortedAsync(false, 1)
		local latestSave = select(2, next(pages:GetCurrentPage()))
		if latestSave then
			return latestSave.value
		end
	end)
end

--[[
	Gets the oldest timestamp that the player has a save in
	Returns a tuple containing a boolean that indicates if the
	timestamp was successfully retrieved, and the timestamp itself
	if it exists
]]
function Save:GetOldestSaveTimestamp(): (boolean, number?)
	if self.Destroyed then
		error("Error getting data, this save instance is destroyed.", 2)
	end

	return retry(function()
		local pages = self.OrderedDataStore:GetSortedAsync(true, 1)
		local oldestSave = select(2, next(pages:GetCurrentPage()))
		if oldestSave then
			return oldestSave.value
		end
	end)
end

--[[
	Returns the save at the given timestamp. If a timestamp is not
	provided, it defaults to the value of GetLatestSaveTimestamp()
	Returns a tuple containing a boolean that indicates if the
	data was successfully retrieved, and the data itself if it exists
]]
function Save:GetData(timestamp: number?): (boolean, table?)
	if self.Destroyed then
		error("Error getting data, this save instance is destroyed.", 2)
	end

	if not timestamp then
		local success
		success, timestamp = self:GetLatestSaveTimestamp()
		if not success then
			return false
		elseif not timestamp then
			return true
		end
	end

	return retry(function()
		local encodedData = self.DataStore:GetAsync(timestamp)
		local data = httpService:JSONDecode(encodedData)
		return data
	end)
end

--[[
	Returns an array of length <= n containing the timestamps of the
	user's saves. The timestaps are sorted in descending order, so the
	most recent save is at index 1
	Maximum value of n is 100
]]
function Save:GetTimestampHistory(n: number): {number}
	if self.Destroyed then
		error("Error getting data, this save instance is destroyed.", 2)
	end

	return retry(function()
		local pages = self.OrderedDataStore:GetSortedAsync(false, n)
		local timestamps = {}
		for _, timestamp in ipairs(pages:GetCurrentPage()) do
			table.insert(timestamps, timestamp.value)
		end
		return timestamps
	end)
end

return Save