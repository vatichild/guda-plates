-- GudaPlates for WoW 1.12.1
-- Written for Lua 5.0 (Vanilla)

if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[GudaPlates]|r Loading...")
end

local function Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[GudaPlates]|r " .. tostring(msg))
    end
end

local initialized = 0
local parentcount = 0
local platecount = 0
local registry = {}
local REGION_ORDER = { "border", "glow", "name", "level", "levelicon", "raidicon" }

local function IsNamePlate(frame)
    if not frame then return nil end
    local objType = frame:GetObjectType()
    if objType ~= "Frame" and objType ~= "Button" then return nil end
    
    -- Check ALL regions for the nameplate border texture
    local regions = { frame:GetRegions() }
    for _, r in ipairs(regions) do
        if r and r.GetObjectType and r:GetObjectType() == "Texture" then
            if r.GetTexture then
                local tex = r:GetTexture()
                if tex == "Interface\\Tooltips\\Nameplate-Border" then
                    return true
                end
            end
        end
    end
    return nil
end

local function DisableObject(object)
    if not object then return end
    if object.SetAlpha then object:SetAlpha(0) end
end

local function HideVisual(object)
    if not object then return end
    if object.SetAlpha then object:SetAlpha(0) end
    if object.GetObjectType then
        local otype = object:GetObjectType()
        if otype == "Texture" then
            object:SetTexture("")
        elseif otype == "FontString" then
            object:SetTextColor(0, 0, 0, 0)
        end
    end
end

local GudaPlates = CreateFrame("Frame", "GudaPlatesFrame", UIParent)
GudaPlates:RegisterEvent("PLAYER_ENTERING_WORLD")

local function HandleNamePlate(frame)
    if not frame then return end
    if registry[frame] then return end
    
    platecount = platecount + 1
    local platename = "GudaPlate" .. platecount
    
    local nameplate = CreateFrame("Frame", platename, frame)
    nameplate.platename = platename
    nameplate:EnableMouse(0)
    nameplate.parent = frame
    nameplate.original = {}
    
    -- Get healthbar - ShaguTweaks sets frame.healthbar directly
    if frame.healthbar then
        nameplate.original.healthbar = frame.healthbar
    else
        nameplate.original.healthbar = frame:GetChildren()
    end
    
    -- Find name and level from regions before hiding
    for _, region in ipairs({frame:GetRegions()}) do
        if region and region.GetObjectType then
            local rtype = region:GetObjectType()
            if rtype == "FontString" then
                local text = region:GetText()
                if text then
                    if tonumber(text) then
                        nameplate.original.level = region
                    else
                        nameplate.original.name = region
                    end
                end
            end
        end
    end
    
    -- Also check frame.new (ShaguTweaks creates this)
    if frame.new then
        for _, region in ipairs({frame.new:GetRegions()}) do
            if region and region.GetObjectType then
                local rtype = region:GetObjectType()
                if rtype == "FontString" then
                    local text = region:GetText()
                    if text and not tonumber(text) and not nameplate.original.name then
                        nameplate.original.name = region
                    end
                end
            end
        end
    end
    
    nameplate:SetAllPoints(frame)
    nameplate:SetFrameLevel(frame:GetFrameLevel() + 10)
    
    -- Plater-style health bar with higher frame level
    nameplate.health = CreateFrame("StatusBar", nil, nameplate)
    nameplate.health:SetFrameLevel(frame:GetFrameLevel() + 11)
    nameplate.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    nameplate.health:SetHeight(10)
    nameplate.health:SetWidth(120)
    nameplate.health:SetPoint("CENTER", nameplate, "CENTER", 0, 12)
    
    -- Dark background
    nameplate.health.bg = nameplate.health:CreateTexture(nil, "BACKGROUND")
    nameplate.health.bg:SetTexture(0, 0, 0, 0.8)
    nameplate.health.bg:SetAllPoints()
    
    -- Border
    nameplate.health.border = nameplate.health:CreateTexture(nil, "OVERLAY")
    nameplate.health.border:SetTexture(0, 0, 0, 1)
    nameplate.health.border:SetPoint("TOPLEFT", nameplate.health, "TOPLEFT", -1, 1)
    nameplate.health.border:SetPoint("BOTTOMRIGHT", nameplate.health, "BOTTOMRIGHT", 1, -1)
    nameplate.health.border:SetDrawLayer("BACKGROUND", -1)
    
    -- Name on the left
    nameplate.name = nameplate.health:CreateFontString(nil, "OVERLAY")
    nameplate.name:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")
    nameplate.name:SetPoint("LEFT", nameplate.health, "LEFT", 2, 0)
    nameplate.name:SetTextColor(1, 1, 1, 1)
    nameplate.name:SetJustifyH("LEFT")
    
    -- Percentage on the right
    nameplate.perc = nameplate.health:CreateFontString(nil, "OVERLAY")
    nameplate.perc:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")
    nameplate.perc:SetPoint("RIGHT", nameplate.health, "RIGHT", -2, 0)
    nameplate.perc:SetTextColor(1, 1, 1, 1)
    nameplate.perc:SetJustifyH("RIGHT")
    
    frame.nameplate = nameplate
    registry[frame] = nameplate
    
    Print("Hooked: " .. platename)
end

local function UpdateNamePlate(frame)
    local nameplate = frame.nameplate
    if not nameplate then return end
    
    local original = nameplate.original
    if not original.healthbar then return end
    
    -- Hide ALL original elements every frame
    original.healthbar:SetStatusBarTexture("")
    original.healthbar:SetAlpha(0)
    
    -- Hide regions on main frame
    for _, region in ipairs({frame:GetRegions()}) do
        if region and region.GetObjectType then
            local otype = region:GetObjectType()
            if otype == "Texture" then
                region:SetTexture("")
                region:SetTexCoord(0, 0, 0, 0)
                region:SetAlpha(0)
            elseif otype == "FontString" then
                region:SetWidth(0.001)
                region:SetAlpha(0)
            end
        end
    end
    
    -- Hide ShaguTweaks new frame elements if present
    if frame.new then
        frame.new:SetAlpha(0)
        for _, region in ipairs({frame.new:GetRegions()}) do
            if region then
                if region.SetTexture then region:SetTexture("") end
                if region.SetAlpha then region:SetAlpha(0) end
                if region.SetWidth and region.GetObjectType and region:GetObjectType() == "FontString" then
                    region:SetWidth(0.001)
                end
            end
        end
    end
    
    local hp = original.healthbar:GetValue() or 0
    local hpmin, hpmax = original.healthbar:GetMinMaxValues()
    if not hpmax or hpmax == 0 then hpmax = 1 end
    
    nameplate.health:SetMinMaxValues(hpmin, hpmax)
    nameplate.health:SetValue(hp)
    
    -- Calculate percentage
    local perc = math.floor((hp / hpmax) * 100)
    nameplate.perc:SetText(perc .. "%")
    
    -- Plater-style colors
    local r, g, b = original.healthbar:GetStatusBarColor()
    
    local isHostile = r > 0.9 and g < 0.2 and b < 0.2
    local isNeutral = r > 0.9 and g > 0.9 and b < 0.2
    local isFriendly = r < 0.2 and g > 0.9 and b < 0.2
    
    -- Check if this mob is attacking the player (mob→player targeting)
    local isAttackingPlayer = false
    if original.name and original.name.GetText then
        local plateName = original.name:GetText()
        -- If we're targeting this mob, check if it's targeting us back
        if UnitExists("target") and UnitName("target") == plateName then
            if UnitExists("targettarget") and UnitIsUnit("targettarget", "player") then
                isAttackingPlayer = true
            end
        end
        -- Also check if our target's target is us and matches this plate
        -- This catches cases where mob is attacking us but we're not targeting it
        if not isAttackingPlayer and UnitExists("targettarget") then
            if UnitName("targettarget") == plateName and UnitIsUnit("target", "player") then
                isAttackingPlayer = true
            end
        end
    end
    
    if isFriendly then
        -- Friendly - green
        nameplate.health:SetStatusBarColor(0.27, 0.63, 0.27, 1)
    elseif isNeutral then
        -- Neutral - yellow/orange
        nameplate.health:SetStatusBarColor(0.9, 0.7, 0.0, 1)
    elseif isAttackingPlayer and isHostile then
        -- Mob attacking player - Plater-style bluish/purple
        nameplate.health:SetStatusBarColor(0.41, 0.35, 0.76, 1)
    elseif isHostile then
        -- Hostile - red
        nameplate.health:SetStatusBarColor(0.85, 0.2, 0.2, 1)
    else
        -- Unknown - use original
        nameplate.health:SetStatusBarColor(r, g, b, 1)
    end
    
    -- Update name from original
    if original.name and original.name.GetText then
        local name = original.name:GetText()
        if name then nameplate.name:SetText(name) end
    end
end

-- Check if ShaguTweaks libnameplate is available
local function TryShaguTweaksHook()
    if ShaguTweaks and ShaguTweaks.libnameplate then
        Print("Using ShaguTweaks libnameplate")
        
        -- Hook into ShaguTweaks OnInit
        ShaguTweaks.libnameplate.OnInit["GudaPlates"] = function(plate)
            if plate and not registry[plate] then
                HandleNamePlate(plate)
            end
        end
        
        -- Hook into ShaguTweaks OnUpdate for our updates
        -- Note: ShaguTweaks passes 'this' as the plate in Lua 5.0 style
        ShaguTweaks.libnameplate.OnUpdate["GudaPlates"] = function()
            local plate = this
            if plate and plate:IsShown() and registry[plate] then
                UpdateNamePlate(plate)
            end
        end
        
        return true
    end
    return false
end

-- Try ShaguTweaks hook first, otherwise use our own scanner
local usingShaguTweaks = false
local scanCount = 0
local lastChildCount = 0
GudaPlates:SetScript("OnUpdate", function()
    -- Try to hook ShaguTweaks once
    if not usingShaguTweaks and ShaguTweaks and ShaguTweaks.libnameplate then
        if TryShaguTweaksHook() then
            usingShaguTweaks = true
            return
        end
    end
    
    -- If using ShaguTweaks, just let their hooks handle it
    if usingShaguTweaks then return end
    
    -- Our own scanning logic
    parentcount = WorldFrame:GetNumChildren()
    
    local childs = { WorldFrame:GetChildren() }
    for i = 1, parentcount do
        local plate = childs[i]
        if plate then
            local isPlate = IsNamePlate(plate)
            if isPlate and not registry[plate] then
                HandleNamePlate(plate)
            end
        end
    end
    
    for plate, nameplate in pairs(registry) do
        if plate:IsShown() then
            UpdateNamePlate(plate)
        end
    end
end)

GudaPlates:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        Print("Initialized. Scanning...")
    end
end)

Print("Loaded.")