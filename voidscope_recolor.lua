--[[
	Voidscope Recolor
	- Small menu with 8 colours + reset (RightShift hides/shows it)
	- Recolors the Voidscope tool you hold AND the shots it fires
	- CLIENT-SIDE ONLY: nobody else will see the change, just you

	Optional preselect before running:
		getgenv().VoidscopeColor = "Purple"
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local GUN_NAME = "voidscope" -- matched case-insensitively, partial match is fine
local SHOT_WINDOW = 1.0      -- seconds after you fire that new effects count as "your shot"
local SHOT_RADIUS = 40       -- studs from your character that a new shot part must spawn within

local COLORS = {
	{ name = "Red",    color = Color3.fromRGB(255, 0, 0) },
	{ name = "Green",  color = Color3.fromRGB(0, 255, 0) },
	{ name = "Black",  color = Color3.fromRGB(0, 0, 0) },
	{ name = "White",  color = Color3.fromRGB(255, 255, 255) },
	{ name = "Orange", color = Color3.fromRGB(255, 128, 0) },
	{ name = "Yellow", color = Color3.fromRGB(255, 255, 0) },
	{ name = "Blue",   color = Color3.fromRGB(0, 100, 255) },
	{ name = "Purple", color = Color3.fromRGB(160, 32, 240) },
}

------------------------------------------------------------------------
-- Re-run protection: clean up a previous run first
------------------------------------------------------------------------
local env = (getgenv and getgenv()) or _G
if env.VoidscopeRecolorCleanup then
	pcall(env.VoidscopeRecolorCleanup)
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local selected = nil -- current entry from COLORS, or nil for default
local shotUntil = 0
local conns = {}
local originals = setmetatable({}, { __mode = "k" }) -- inst -> { prop = originalValue }
local hooked = setmetatable({}, { __mode = "k" })    -- tools we've hooked
local gui

local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(conns, c)
	return c
end

------------------------------------------------------------------------
-- Painting
------------------------------------------------------------------------
local function set(inst, prop, value)
	local saved = originals[inst]
	if not saved then
		saved = {}
		originals[inst] = saved
	end
	if saved[prop] == nil then
		local ok, v = pcall(function() return inst[prop] end)
		if ok then saved[prop] = v end
	end
	pcall(function() inst[prop] = value end)
end

local function restoreAll()
	for inst, saved in pairs(originals) do
		for prop, v in pairs(saved) do
			pcall(function() inst[prop] = v end)
		end
	end
	for k in pairs(originals) do
		originals[k] = nil
	end
end

local function paint(inst, color, isShot)
	local seq = ColorSequence.new(color)

	if inst:IsA("BasePart") then
		set(inst, "Color", color)
		if inst:IsA("MeshPart") then
			set(inst, "TextureID", "") -- textures would otherwise override the colour
		end
		if isShot and color ~= Color3.new(0, 0, 0) then
			set(inst, "Material", Enum.Material.Neon)
		end
	elseif inst:IsA("SpecialMesh") then
		set(inst, "TextureId", "")
		set(inst, "VertexColor", Vector3.new(color.R, color.G, color.B))
	elseif inst:IsA("SurfaceAppearance") then
		set(inst, "ColorMap", "")
		set(inst, "Color", color)
	elseif inst:IsA("Decal") or inst:IsA("Texture") then
		set(inst, "Color3", color)
	elseif inst:IsA("Beam") or inst:IsA("Trail") or inst:IsA("ParticleEmitter") then
		set(inst, "Color", seq)
	elseif inst:IsA("Light") then -- PointLight / SpotLight / SurfaceLight
		set(inst, "Color", color)
	elseif inst:IsA("Fire") then
		set(inst, "Color", color)
		set(inst, "SecondaryColor", color)
	elseif inst:IsA("Sparkles") then
		set(inst, "SparkleColor", color)
	elseif inst:IsA("Highlight") then
		set(inst, "FillColor", color)
		set(inst, "OutlineColor", color)
	end
end

local function paintGun(tool)
	if not selected then return end
	for _, d in ipairs(tool:GetDescendants()) do
		paint(d, selected.color, false)
	end
end

------------------------------------------------------------------------
-- Finding / hooking the gun
------------------------------------------------------------------------
local function isGun(inst)
	return inst:IsA("Tool") and string.find(string.lower(inst.Name), GUN_NAME, 1, true) ~= nil
end

local function hookGun(tool)
	if hooked[tool] then return end
	hooked[tool] = true

	paintGun(tool)

	-- the game may build/clone gun visuals when it's equipped, so paint new bits too
	connect(tool.DescendantAdded, function(d)
		if selected then
			task.defer(paint, d, selected.color, false)
		end
	end)

	connect(tool.Activated, function()
		shotUntil = os.clock() + SHOT_WINDOW
	end)
end

local function scan(container)
	if not container then return end
	for _, child in ipairs(container:GetChildren()) do
		if isGun(child) then hookGun(child) end
	end
	connect(container.ChildAdded, function(child)
		if isGun(child) then hookGun(child) end
	end)
end

scan(LocalPlayer.Character)
scan(LocalPlayer:FindFirstChildOfClass("Backpack"))
connect(LocalPlayer.CharacterAdded, scan)
connect(LocalPlayer.ChildAdded, function(c)
	if c:IsA("Backpack") then scan(c) end
end)

-- fallback in case the game doesn't trigger Tool.Activated
connect(UserInputService.InputBegan, function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		local char = LocalPlayer.Character
		if char then
			for _, child in ipairs(char:GetChildren()) do
				if isGun(child) then
					shotUntil = os.clock() + SHOT_WINDOW
					break
				end
			end
		end
	end
end)

------------------------------------------------------------------------
-- Shot recolouring
------------------------------------------------------------------------
local function inCharacter(inst)
	local m = inst:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") then return true end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return false
end

local function partOf(inst)
	if inst:IsA("BasePart") then return inst end
	local p = inst.Parent
	if p and p:IsA("Attachment") then p = p.Parent end
	if p and p:IsA("BasePart") then return p end
	return nil
end

connect(Workspace.DescendantAdded, function(d)
	if not selected then return end
	if os.clock() > shotUntil then return end
	if inCharacter(d) then return end -- the gun's own parts are handled by hookGun

	local part = partOf(d)
	local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if part and root and (part.Position - root.Position).Magnitude > SHOT_RADIUS then
		return -- too far from you, probably someone else's effect / a coin etc.
	end

	-- wait a frame so the game can finish setting up the object, then override it
	task.defer(function()
		if d.Parent and selected then
			paint(d, selected.color, true)
		end
	end)
end)

------------------------------------------------------------------------
-- Menu
------------------------------------------------------------------------
local statusLabel
local buttons = {}

local function updateStatus()
	if statusLabel then
		statusLabel.Text = selected and ("Selected: " .. selected.name) or "Selected: Default"
	end
	for name, btn in pairs(buttons) do
		local stroke = btn:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = (selected ~= nil and selected.name == name)
		end
	end
end

local function applyColor(entry)
	selected = entry
	for tool in pairs(hooked) do
		if tool.Parent then paintGun(tool) end
	end
	updateStatus()
end

local function resetColor()
	selected = nil
	restoreAll()
	updateStatus()
end

local function brightness(c)
	return c.R * 0.299 + c.G * 0.587 + c.B * 0.114
end

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "VoidscopeRecolor"
	gui.ResetOnSpawn = false

	local ok = pcall(function()
		gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
	end)
	if not ok or not gui.Parent then
		gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end

	local frame = Instance.new("Frame")
	frame.Name = "Main"
	frame.Size = UDim2.new(0, 180, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Position = UDim2.new(0, 20, 0.35, 0)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	frame.BorderSizePixel = 0
	frame.Active = true
	pcall(function() frame.Draggable = true end)
	frame.Parent = gui

	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

	local pad = Instance.new("UIPadding", frame)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)

	local list = Instance.new("UIListLayout", frame)
	list.Padding = UDim.new(0, 5)
	list.SortOrder = Enum.SortOrder.LayoutOrder

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	local title = Instance.new("TextLabel")
	title.LayoutOrder = nextOrder()
	title.Size = UDim2.new(1, 0, 0, 22)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "Voidscope Recolor"
	title.Parent = frame

	for _, entry in ipairs(COLORS) do
		local btn = Instance.new("TextButton")
		btn.LayoutOrder = nextOrder()
		btn.Size = UDim2.new(1, 0, 0, 26)
		btn.BackgroundColor3 = entry.color
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = true
		btn.Font = Enum.Font.GothamMedium
		btn.TextSize = 14
		btn.Text = entry.name
		btn.TextColor3 = brightness(entry.color) > 0.5 and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
		btn.Parent = frame

		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(0, 170, 255)
		stroke.Thickness = 2
		stroke.Enabled = false
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = btn

		btn.MouseButton1Click:Connect(function()
			applyColor(entry)
		end)
		buttons[entry.name] = btn
	end

	local reset = Instance.new("TextButton")
	reset.LayoutOrder = nextOrder()
	reset.Size = UDim2.new(1, 0, 0, 26)
	reset.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
	reset.BorderSizePixel = 0
	reset.Font = Enum.Font.GothamMedium
	reset.TextSize = 14
	reset.TextColor3 = Color3.new(1, 1, 1)
	reset.Text = "Reset to default"
	reset.Parent = frame
	Instance.new("UICorner", reset).CornerRadius = UDim.new(0, 6)
	reset.MouseButton1Click:Connect(resetColor)

	statusLabel = Instance.new("TextLabel")
	statusLabel.LayoutOrder = nextOrder()
	statusLabel.Size = UDim2.new(1, 0, 0, 16)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 12
	statusLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
	statusLabel.Text = "Selected: Default"
	statusLabel.Parent = frame

	local hint = Instance.new("TextLabel")
	hint.LayoutOrder = nextOrder()
	hint.Size = UDim2.new(1, 0, 0, 14)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 11
	hint.TextColor3 = Color3.fromRGB(120, 120, 130)
	hint.Text = "RightShift = hide / show"
	hint.Parent = frame

	connect(UserInputService.InputBegan, function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.RightShift then
			frame.Visible = not frame.Visible
		end
	end)
end

buildGui()

-- optional preselect via getgenv().VoidscopeColor
local pre = env.VoidscopeColor
if type(pre) == "string" then
	for _, entry in ipairs(COLORS) do
		if string.lower(entry.name) == string.lower(pre) then
			applyColor(entry)
			break
		end
	end
end

env.VoidscopeRecolorCleanup = function()
	for _, c in ipairs(conns) do
		pcall(function() c:Disconnect() end)
	end
	restoreAll()
	if gui then gui:Destroy() end
	env.VoidscopeRecolorCleanup = nil
end
