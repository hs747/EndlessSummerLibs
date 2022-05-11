-- wafflechad, rewritten version 1/30/22
local visualDebug = {}

local runService = game:GetService("RunService")
local debris = game:GetService("Debris")
local renderPool = require(script:WaitForChild("RenderPool"))

local DEFAULT_COLOR = Color3.fromRGB(255, 255, 255)

-- private
local function getColor(c)
	if typeof(c) == "Color3" then
		return c
	elseif typeof(c) == "string" then
		if visualDebug.color[c] then
			return visualDebug.color[c]
		else
			error("Invalid Color String.")
		end
	else
		return DEFAULT_COLOR
	end
end

local function createCylinder()
	local cylinder = Instance.new("CylinderHandleAdornment")
	cylinder.Height = 1
	cylinder.Radius = 0.1
	cylinder.Adornee = workspace
	cylinder.AlwaysOnTop = true
	cylinder.ZIndex = -1
	cylinder.Parent = workspace.Terrain
	return cylinder
end

local function createSphere()
	local sphere = Instance.new("SphereHandleAdornment")
	sphere.Radius = 1
	sphere.Adornee = workspace.Terrain
	sphere.Parent = workspace.Terrain
	sphere.AlwaysOnTop = true
	sphere.ZIndex = -1
	return sphere
end

local spherePool = renderPool.new(createSphere)
local cylinderPool = spherePool.new(createCylinder)

local function getSphere(t, cf, color, radius)
	local sphere
	if t then
		sphere = createSphere()
		debris:AddItem(sphere, t)
	else
		sphere = spherePool:use()
	end
	sphere.Color3 = getColor(color)
	sphere.Radius = radius
	sphere.CFrame = cf
	return sphere
end

local function getCylinder(t, cf, color, radius, height)
	local cylinder
	if t then
		cylinder = createCylinder()
		debris:AddItem(cylinder, t)
	else
		cylinder = cylinderPool:use()
	end
	cylinder.Color3 = getColor(color)
	cylinder.Radius = radius
	cylinder.Height = height
	cylinder.CFrame = cf
	return cylinder
end

-- mini color library
visualDebug.color = {
	red = Color3.fromRGB(255, 0, 0),
	green = Color3.fromRGB(0, 255, 0),
	blue = Color3.fromRGB(0, 0, 255),
	yellow = Color3.fromRGB(255, 217, 0),
	orange  = Color3.fromRGB(255, 126, 14),
	purple = Color3.fromRGB(135, 14, 255),
}

-- drawing interface
function visualDebug.drawRay(position, vector, color, timelength)
	local position = position + vector/2
	local ray = getCylinder(timelength, CFrame.new(position, position + vector), color, 0.1, vector.Magnitude)
end

function visualDebug.drawSphere(position, radius, color, timelength)
	local sphere = getSphere(timelength, CFrame.new(position), color, radius)
end

function visualDebug.drawCFrame(cframe, scale, timelength)
	scale = scale or 1
	visualDebug.drawRay(cframe.Position, cframe.LookVector * scale, visualDebug.color.blue, timelength)
	visualDebug.drawRay(cframe.Position, cframe.RightVector * scale, visualDebug.color.red, timelength)
	visualDebug.drawRay(cframe.Position, cframe.UpVector * scale, visualDebug.color.green, timelength)
end

function visualDebug.drawLine(p1, p2, color, timeLength)
	visualDebug.drawRay(p1, p2 - p1, color, timeLength)
end

-- startup stuff
runService.Heartbeat:Connect(function() 
	cylinderPool:cleanupFrame()
	spherePool:cleanupFrame()
end)

runService.RenderStepped:Connect(function() 
	cylinderPool:rendered()
	spherePool:rendered()
end)

return visualDebug