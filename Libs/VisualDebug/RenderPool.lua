-- wafflechad, 1/30/2022

local FREE_CFRAME = CFrame.new(10e3, 10e3, 10e3)
local DEFAULT_POOL_COUNT = 0

-- THE CLASS --

local renderPool = {}
renderPool.__index = renderPool

function renderPool.new(creatorFunction, initialCount, freeCFrame)
	local self = setmetatable({}, renderPool)
	self.using = {}
	self.next = {}
	self.free = {}
	self.hasRendered = false
	self.freeCFrame = freeCFrame or FREE_CFRAME
	self.creatorFunc = creatorFunction
	return self
end

-- KINDA PRIVATE METHODS --

function renderPool:_create(use)
	local obj = self.creatorFunc()
	obj.CFrame = self.freeCFrame
	if use then
		if self.hasRendered then
			table.insert(self.next, obj)
		else
			table.insert(self.using, obj)
		end
	else
		table.insert(self.free, obj)
	end
	return obj
end

-- PUBLIC METHODS ---

function renderPool:cleanupFrame()
	debug.profilebegin("Render Pool Cleanup")
	-- remove items from using table
	for i = #self.using, 1, -1 do
		local v = table.remove(self.using, i)
		v.CFrame = self.freeCFrame
		table.insert(self.free, v)
	end
	-- switch next table to using table
	self.using = self.next
	self.next = {}
	-- set 'has rendered since last cleanup' flag to false
	self.hasRendered = false
	debug.profileend()
end

function renderPool:rendered()
	self.hasRendered = true
end

function renderPool:use()
	if #self.free > 0 then
		local obj = table.remove(self.free, #self.free)
		if self.hasRendered then
			table.insert(self.next, obj)
		else
			table.insert(self.using, obj)
		end
		return obj
	else
		return self:_create(true)
	end
end

return renderPool