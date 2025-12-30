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
local attackingPlayer = {} -- Track mobs attacking the player (by GUID if SuperWoW, else by name)
local superwow_active = SpellInfo ~= nil -- SuperWoW detection
local twthreat_active = UnitThreat ~= nil -- TurtleWoW TWThreat detection

-- Role setting: "TANK" or "DPS" (DPS includes healers)
local playerRole = "DPS"

-- Nameplate overlap setting: true = overlapping, false = stacking (default)
local nameplateOverlap = false

-- Plater-style threat colors
local THREAT_COLORS = {
    -- DPS/Healer colors
    DPS = {
        AGGRO = {0.85, 0.2, 0.2, 1},       -- Red: mob attacking you (BAD)
        HIGH_THREAT = {1.0, 0.6, 0.0, 1},  -- Orange: high threat, about to pull (WARNING)
        NO_AGGRO = {0.41, 0.35, 0.76, 1},  -- Blue: tank has aggro (GOOD)
    },
    -- Tank colors
    TANK = {
        AGGRO = {0.41, 0.35, 0.76, 1},     -- Blue: you have aggro (GOOD)
        LOSING_AGGRO = {1.0, 1.0, 0.0, 1}, -- Yellow: losing aggro (WARNING)
        NO_AGGRO = {0.85, 0.2, 0.2, 1},    -- Red: no aggro, need to taunt (BAD)
        OTHER_TANK = {0.6, 0.8, 1.0, 1},   -- Light Blue: another tank has it
    },
}

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
    
    local nameplate = CreateFrame("Button", platename, frame)
    nameplate.platename = platename
    nameplate:EnableMouse(false)
    nameplate.parent = frame
    nameplate.original = {}
    
    -- Click handler for overlap mode - forward clicks to parent
    nameplate:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    nameplate:SetScript("OnClick", function()
        if arg1 == "LeftButton" then
            this.parent:Click()
        elseif arg1 == "RightButton" then
            this.parent:Click()
        end
    end)
    
    -- Get healthbar - ShaguTweaks sets frame.healthbar directly
    if frame.healthbar then
        nameplate.original.healthbar = frame.healthbar
    else
        nameplate.original.healthbar = frame:GetChildren()
    end
    
    -- Find name and level from regions before hiding
    -- Get regions by index (vanilla nameplate order: border, glow, name, level, levelicon, raidicon)
    local regions = {frame:GetRegions()}
    for i, region in ipairs(regions) do
        if region and region.GetObjectType then
            local rtype = region:GetObjectType()
            if i == 6 then
                -- 6th region is raid icon
                nameplate.original.raidicon = region
            elseif rtype == "FontString" then
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
    nameplate.health:SetPoint("CENTER", nameplate, "CENTER", 0, 0)
    
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
    
    -- Reparent original raid icon to our health bar
    if nameplate.original.raidicon then
        nameplate.original.raidicon:SetParent(nameplate.health)
        nameplate.original.raidicon:ClearAllPoints()
        nameplate.original.raidicon:SetPoint("RIGHT", nameplate.health, "LEFT", -5, 0)
        nameplate.original.raidicon:SetWidth(24)
        nameplate.original.raidicon:SetHeight(24)
        nameplate.original.raidicon:SetDrawLayer("OVERLAY")
    end
    
    -- Target highlight borders (left and right)
    nameplate.health.targetLeft = nameplate.health:CreateTexture(nil, "OVERLAY")
    nameplate.health.targetLeft:SetTexture(1, 1, 1, 1)
    nameplate.health.targetLeft:SetWidth(3)
    nameplate.health.targetLeft:SetPoint("TOPRIGHT", nameplate.health, "TOPLEFT", -1, 2)
    nameplate.health.targetLeft:SetPoint("BOTTOMRIGHT", nameplate.health, "BOTTOMLEFT", -1, -2)
    nameplate.health.targetLeft:Hide()
    
    nameplate.health.targetRight = nameplate.health:CreateTexture(nil, "OVERLAY")
    nameplate.health.targetRight:SetTexture(1, 1, 1, 1)
    nameplate.health.targetRight:SetWidth(3)
    nameplate.health.targetRight:SetPoint("TOPLEFT", nameplate.health, "TOPRIGHT", 1, 2)
    nameplate.health.targetRight:SetPoint("BOTTOMLEFT", nameplate.health, "BOTTOMRIGHT", 1, -2)
    nameplate.health.targetRight:Hide()
    
    -- Name below the health bar (like in Plater)
    nameplate.name = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.name:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")
    nameplate.name:SetPoint("TOP", nameplate.health, "BOTTOM", 0, -2)
    nameplate.name:SetTextColor(1, 1, 1, 1)
    nameplate.name:SetJustifyH("CENTER")
    
    -- Level above the health bar on the right
    nameplate.level = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.level:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")
    nameplate.level:SetPoint("BOTTOMRIGHT", nameplate.health, "TOPRIGHT", 0, 2)
    nameplate.level:SetTextColor(1, 1, 0.6, 1)
    nameplate.level:SetJustifyH("RIGHT")
    
    -- Health text centered on bar
    nameplate.healthtext = nameplate.health:CreateFontString(nil, "OVERLAY")
    nameplate.healthtext:SetFont("Fonts\\ARIALN.TTF", 8, "OUTLINE")
    nameplate.healthtext:SetPoint("CENTER", nameplate.health, "CENTER", 0, 0)
    nameplate.healthtext:SetTextColor(1, 1, 1, 1)
    
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
    
    -- Hide regions on main frame (but NOT the raid icon - it's reparented to us)
    for i, region in ipairs({frame:GetRegions()}) do
        if region and region.GetObjectType then
            local otype = region:GetObjectType()
            if otype == "Texture" then
                -- Skip raid icon (6th region) - we reparented it
                if region ~= nameplate.original.raidicon then
                    region:SetTexture("")
                    region:SetTexCoord(0, 0, 0, 0)
                    region:SetAlpha(0)
                end
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
    
    -- Calculate percentage and format health text like Plater "1.3K (30.6%)"
    local perc = math.floor((hp / hpmax) * 100)
    local hpText = ""
    if hpmax > 1000 then
        hpText = string.format("%.1fK (%.1f%%)", hp / 1000, (hp / hpmax) * 100)
    else
        hpText = string.format("%d (%.1f%%)", hp, (hp / hpmax) * 100)
    end
    nameplate.healthtext:SetText(hpText)
    
    -- Update level from original
    if original.level and original.level.GetText then
        local levelText = original.level:GetText()
        if levelText then
            nameplate.level:SetText(levelText)
        end
    end
    
    -- Plater-style colors with threat support
    local r, g, b = original.healthbar:GetStatusBarColor()
    
    local isHostile = r > 0.9 and g < 0.2 and b < 0.2
    local isNeutral = r > 0.9 and g > 0.9 and b < 0.2
    local isFriendly = r < 0.2 and g > 0.9 and b < 0.2
    
    -- Get unit string for threat check
    local unitstr = nil
    local plateName = nil
    if original.name and original.name.GetText then
        plateName = original.name:GetText()
    end
    
    -- SuperWoW: get GUID for unit from the parent nameplate frame
    if superwow_active and frame and frame.GetName then
        unitstr = frame:GetName(1)
    end
    
    -- Check if this mob is attacking the player (mob→player targeting)
    local isAttackingPlayer = false
    local hasValidGUID = unitstr and unitstr ~= ""
    
    -- SuperWoW method: use GUID to check mob's target directly (real-time, per-plate)
    if hasValidGUID then
        local mobTarget = unitstr .. "target"
        -- This check works regardless of what player is targeting
        if UnitIsUnit(mobTarget, "player") then
            isAttackingPlayer = true
            -- Store on nameplate object for this specific plate
            nameplate.isAttackingPlayer = true
            nameplate.lastAttackTime = GetTime()
        else
            -- Check if this specific plate was recently attacking
            if nameplate.isAttackingPlayer and nameplate.lastAttackTime and (GetTime() - nameplate.lastAttackTime < 2) then
                isAttackingPlayer = true
            else
                nameplate.isAttackingPlayer = false
            end
        end
    else
        -- Fallback: use name-based tracking (has same-name mob limitation)
        if plateName then
            -- Check if we recently confirmed this mob was attacking us
            if attackingPlayer[plateName] and GetTime() - attackingPlayer[plateName] < 5 then
                isAttackingPlayer = true
            end
            
            -- If we're targeting this mob, verify and update tracking
            if UnitExists("target") and UnitName("target") == plateName then
                if UnitExists("targettarget") and UnitIsUnit("targettarget", "player") then
                    attackingPlayer[plateName] = GetTime()
                    isAttackingPlayer = true
                elseif UnitExists("targettarget") and not UnitIsUnit("targettarget", "player") then
                    -- Mob is targeting someone else, clear tracking
                    attackingPlayer[plateName] = nil
                    isAttackingPlayer = false
                end
            end
            
            -- Expire old entries after 5 seconds without refresh
            if attackingPlayer[plateName] and GetTime() - attackingPlayer[plateName] > 5 then
                attackingPlayer[plateName] = nil
                isAttackingPlayer = false
            end
        end
    end
    
    -- TWThreat: get threat information
    local threatPct = 0
    local isTanking = false
    local threatStatus = 0
    
    if twthreat_active and unitstr and isHostile then
        -- UnitThreat returns: isTanking, status, threatpct, rawthreatpct, threatvalue
        local tanking, status, pct = UnitThreat("player", unitstr)
        if tanking ~= nil then
            isTanking = tanking
            threatStatus = status or 0
            threatPct = pct or 0
        end
    end
    
    -- Determine color based on role and threat
    if isFriendly then
        nameplate.health:SetStatusBarColor(0.27, 0.63, 0.27, 1)
    elseif isNeutral and not isAttackingPlayer then
        -- Neutral and not attacking - yellow
        nameplate.health:SetStatusBarColor(0.9, 0.7, 0.0, 1)
    elseif isHostile or (isNeutral and isAttackingPlayer) then
        -- Hostile OR neutral that is attacking player
        -- Check if mob is in combat (has a target)
        local mobInCombat = false
        
        if hasValidGUID then
            local mobTarget = unitstr .. "target"
            mobInCombat = UnitExists(mobTarget)
        else
            -- Fallback: assume in combat if attacking player or we have threat data
            mobInCombat = isAttackingPlayer or (twthreat_active and threatPct > 0)
        end
        
        if not mobInCombat then
            -- Not in combat - default hostile red
            nameplate.health:SetStatusBarColor(0.85, 0.2, 0.2, 1)
        elseif hasValidGUID and twthreat_active then
            -- Full threat-based coloring (mob is in combat, has GUID and threat data)
            if playerRole == "TANK" then
                if isTanking or isAttackingPlayer then
                    -- Tank has aggro (GOOD)
                    nameplate.health:SetStatusBarColor(unpack(THREAT_COLORS.TANK.AGGRO))
                elseif threatPct > 80 then
                    -- Losing aggro (WARNING)
                    nameplate.health:SetStatusBarColor(unpack(THREAT_COLORS.TANK.LOSING_AGGRO))
                else
                    -- No aggro, need to taunt (BAD)
                    nameplate.health:SetStatusBarColor(unpack(THREAT_COLORS.TANK.NO_AGGRO))
                end
            else -- DPS/Healer
                if isAttackingPlayer or isTanking then
                    -- Mob attacking you (BAD)
                    nameplate.health:SetStatusBarColor(unpack(THREAT_COLORS.DPS.AGGRO))
                elseif threatPct > 80 then
                    -- High threat, about to pull (WARNING)
                    nameplate.health:SetStatusBarColor(unpack(THREAT_COLORS.DPS.HIGH_THREAT))
                else
                    -- Tank has aggro (GOOD)
                    nameplate.health:SetStatusBarColor(unpack(THREAT_COLORS.DPS.NO_AGGRO))
                end
            end
        elseif hasValidGUID then
            -- Has GUID but no TWThreat - use targeting-based colors
            if playerRole == "TANK" then
                if isAttackingPlayer then
                    nameplate.health:SetStatusBarColor(unpack(THREAT_COLORS.TANK.AGGRO))
                else
                    nameplate.health:SetStatusBarColor(unpack(THREAT_COLORS.TANK.NO_AGGRO))
                end
            else
                if isAttackingPlayer then
                    nameplate.health:SetStatusBarColor(unpack(THREAT_COLORS.DPS.AGGRO))
                else
                    nameplate.health:SetStatusBarColor(unpack(THREAT_COLORS.DPS.NO_AGGRO))
                end
            end
        else
            -- No GUID (no SuperWoW) - fallback with name-based detection (has same-name limitation)
            if playerRole == "TANK" then
                if isAttackingPlayer then
                    nameplate.health:SetStatusBarColor(unpack(THREAT_COLORS.TANK.AGGRO))
                else
                    nameplate.health:SetStatusBarColor(unpack(THREAT_COLORS.TANK.NO_AGGRO))
                end
            else
                if isAttackingPlayer then
                    nameplate.health:SetStatusBarColor(unpack(THREAT_COLORS.DPS.AGGRO))
                else
                    nameplate.health:SetStatusBarColor(unpack(THREAT_COLORS.DPS.NO_AGGRO))
                end
            end
        end
    else
        nameplate.health:SetStatusBarColor(r, g, b, 1)
    end
    
    -- Update name from original
    if original.name and original.name.GetText then
        local name = original.name:GetText()
        if name then nameplate.name:SetText(name) end
    end
    
    -- Target highlight - show borders on current target
    local isTarget = false
    if UnitExists("target") and plateName then
        local targetName = UnitName("target")
        if targetName and targetName == plateName then
            -- Additional check: verify via alpha (target nameplate has alpha 1)
            if frame:GetAlpha() == 1 then
                isTarget = true
            end
        end
    end
    
    if isTarget then
        nameplate.health.targetLeft:Show()
        nameplate.health.targetRight:Show()
        -- Target always has highest z-index
        nameplate:SetFrameStrata("TOOLTIP")
    else
        nameplate.health.targetLeft:Hide()
        nameplate.health.targetRight:Hide()
        -- Non-target z-index based on attacking state (only in overlap mode)
        if nameplateOverlap then
            if nameplate.isAttackingPlayer then
                nameplate:SetFrameStrata("HIGH")
            else
                nameplate:SetFrameStrata("MEDIUM")
            end
        end
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
        end
    end
    
    -- If using ShaguTweaks, still apply overlap settings
    if usingShaguTweaks then
        for plate, nameplate in pairs(registry) do
            if plate:IsShown() then
                -- Apply overlap/stacking setting
                if nameplateOverlap then
                    plate:EnableMouse(false)
                    if plate:GetWidth() > 1 then
                        plate:SetWidth(1)
                        plate:SetHeight(1)
                    end
                    -- Z-index is handled in UpdateNamePlate (target > attacking > others)
                    nameplate:EnableMouse(true)
                else
                    plate:EnableMouse(true)
                    nameplate:EnableMouse(false)
                end
            end
        end
        return
    end
    
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
            
            -- Apply overlap/stacking setting
            if nameplateOverlap then
                -- Overlapping: disable parent mouse and shrink to 1px
                -- This prevents game's collision avoidance from moving nameplates
                plate:EnableMouse(false)
                
                if plate:GetWidth() > 1 then
                    plate:SetWidth(1)
                    plate:SetHeight(1)
                end
                
                -- Z-index is handled in UpdateNamePlate (target > attacking > others)
                -- Enable clicking on nameplate itself
                nameplate:EnableMouse(true)
            else
                -- Stacking: restore parent frame size so game stacks them
                plate:EnableMouse(true)
                
                local npWidth = nameplate:GetWidth() * UIParent:GetScale()
                local npHeight = nameplate:GetHeight() * UIParent:GetScale()
                if math.floor(plate:GetWidth()) ~= math.floor(npWidth) then
                    plate:SetWidth(npWidth)
                    plate:SetHeight(npHeight)
                end
                nameplate:EnableMouse(false)
            end
        end
    end
end)

GudaPlates:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        Print("Initialized. Scanning...")
        if twthreat_active then
            Print("TWThreat detected - full threat colors enabled")
        end
        if superwow_active then
            Print("SuperWoW detected - GUID targeting enabled")
        end
    end
end)

-- Slash command to toggle role
SLASH_GUDAPLATES1 = "/gudaplates"
SLASH_GUDAPLATES2 = "/gp"
SlashCmdList["GUDAPLATES"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "tank" then
        playerRole = "TANK"
        Print("Role set to TANK - Blue=you have aggro, Red=need to taunt")
    elseif msg == "dps" or msg == "healer" then
        playerRole = "DPS"
        Print("Role set to DPS/HEALER - Red=mob attacking you, Blue=tank has aggro")
    elseif msg == "toggle" then
        if playerRole == "TANK" then
            playerRole = "DPS"
            Print("Role set to DPS/HEALER")
        else
            playerRole = "TANK"
            Print("Role set to TANK")
        end
    elseif msg == "config" or msg == "options" then
        if GudaPlatesOptionsFrame:IsShown() then
            GudaPlatesOptionsFrame:Hide()
        else
            GudaPlatesOptionsFrame:Show()
        end
    else
        Print("Commands: /gp tank | /gp dps | /gp toggle | /gp config")
        Print("Current role: " .. playerRole)
    end
end

-- Saved Variables (will be loaded from SavedVariables)
GudaPlatesDB = GudaPlatesDB or {}

local function SaveSettings()
    GudaPlatesDB.playerRole = playerRole
    GudaPlatesDB.THREAT_COLORS = THREAT_COLORS
    GudaPlatesDB.nameplateOverlap = nameplateOverlap
end

local function LoadSettings()
    if GudaPlatesDB.playerRole then
        playerRole = GudaPlatesDB.playerRole
    end
    if GudaPlatesDB.nameplateOverlap ~= nil then
        nameplateOverlap = GudaPlatesDB.nameplateOverlap
    end
    if GudaPlatesDB.THREAT_COLORS then
        for role, colors in pairs(GudaPlatesDB.THREAT_COLORS) do
            if THREAT_COLORS[role] then
                for colorType, colorVal in pairs(colors) do
                    if THREAT_COLORS[role][colorType] then
                        THREAT_COLORS[role][colorType] = colorVal
                    end
                end
            end
        end
    end
end

-- Minimap Button
local minimapButton = CreateFrame("Button", "GudaPlatesMinimapButton", Minimap)
minimapButton:SetWidth(32)
minimapButton:SetHeight(32)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local minimapIcon = minimapButton:CreateTexture(nil, "BACKGROUND")
minimapIcon:SetTexture("Interface\\Icons\\Spell_Nature_WispSplode")
minimapIcon:SetWidth(20)
minimapIcon:SetHeight(20)
minimapIcon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)

local minimapBorder = minimapButton:CreateTexture(nil, "OVERLAY")
minimapBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
minimapBorder:SetWidth(56)
minimapBorder:SetHeight(56)
minimapBorder:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", -5, 5)

-- Minimap button dragging
local minimapAngle = 220
local function UpdateMinimapButtonPosition()
    local rad = math.rad(minimapAngle)
    local x = math.cos(rad) * 80
    local y = math.sin(rad) * 80
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
UpdateMinimapButtonPosition()

minimapButton:RegisterForDrag("LeftButton")
minimapButton:SetScript("OnDragStart", function()
    this.dragging = true
end)

minimapButton:SetScript("OnDragStop", function()
    this.dragging = false
end)

minimapButton:SetScript("OnUpdate", function()
    if this.dragging then
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
        UpdateMinimapButtonPosition()
    end
end)

minimapButton:SetScript("OnClick", function()
    if GudaPlatesOptionsFrame:IsShown() then
        GudaPlatesOptionsFrame:Hide()
    else
        GudaPlatesOptionsFrame:Show()
    end
end)

minimapButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("GudaPlates")
    GameTooltip:AddLine("Click to open settings", 1, 1, 1)
    GameTooltip:AddLine("Drag to move button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)

minimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Options Frame
local optionsFrame = CreateFrame("Frame", "GudaPlatesOptionsFrame", UIParent)
optionsFrame:SetWidth(350)
optionsFrame:SetHeight(430)
optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
optionsFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
optionsFrame:SetMovable(true)
optionsFrame:EnableMouse(true)
optionsFrame:RegisterForDrag("LeftButton")
optionsFrame:SetScript("OnDragStart", function() this:StartMoving() end)
optionsFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
optionsFrame:Hide()

-- Title
local title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", optionsFrame, "TOP", 0, -20)
title:SetText("GudaPlates Settings")

-- Close Button
local closeButton = CreateFrame("Button", nil, optionsFrame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -5, -5)

-- Role Selection
local roleLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
roleLabel:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -50)
roleLabel:SetText("Role:")

local tankButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
tankButton:SetWidth(80)
tankButton:SetHeight(25)
tankButton:SetPoint("LEFT", roleLabel, "RIGHT", 20, 0)
tankButton:SetText("Tank")
tankButton:SetScript("OnClick", function()
    playerRole = "TANK"
    SaveSettings()
    Print("Role set to TANK")
end)

local dpsButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
dpsButton:SetWidth(80)
dpsButton:SetHeight(25)
dpsButton:SetPoint("LEFT", tankButton, "RIGHT", 10, 0)
dpsButton:SetText("DPS/Healer")
dpsButton:SetScript("OnClick", function()
    playerRole = "DPS"
    SaveSettings()
    Print("Role set to DPS/HEALER")
end)

-- Nameplate Mode Selection
local modeLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
modeLabel:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -80)
modeLabel:SetText("Nameplates:")

local stackButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
stackButton:SetWidth(80)
stackButton:SetHeight(25)
stackButton:SetPoint("LEFT", modeLabel, "RIGHT", 20, 0)
stackButton:SetText("Stacking")
stackButton:SetScript("OnClick", function()
    nameplateOverlap = false
    SaveSettings()
    Print("Nameplates set to STACKING")
end)

local overlapButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
overlapButton:SetWidth(80)
overlapButton:SetHeight(25)
overlapButton:SetPoint("LEFT", stackButton, "RIGHT", 10, 0)
overlapButton:SetText("Overlapping")
overlapButton:SetScript("OnClick", function()
    nameplateOverlap = true
    SaveSettings()
    Print("Nameplates set to OVERLAPPING")
end)

-- Color picker helper
local function ShowColorPicker(r, g, b, callback)
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame.previousValues = {r, g, b}
    ColorPickerFrame.func = callback
    ColorPickerFrame.cancelFunc = function()
        callback(unpack(ColorPickerFrame.previousValues))
    end
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
end

-- Create color swatch
local function CreateColorSwatch(parent, x, y, label, colorTable, colorKey)
    local swatchLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    swatchLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    swatchLabel:SetText(label)
    
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetWidth(20)
    swatch:SetHeight(20)
    swatch:SetPoint("LEFT", swatchLabel, "RIGHT", 10, 0)
    
    -- Black border
    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetTexture(0, 0, 0, 1)
    border:SetAllPoints()
    
    -- Color fill (slightly inset for border effect)
    local swatchBg = swatch:CreateTexture(nil, "ARTWORK")
    swatchBg:SetTexture(1, 1, 1, 1)
    swatchBg:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
    swatchBg:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)
    
    local function UpdateSwatchColor()
        local c = colorTable[colorKey]
        swatchBg:SetVertexColor(c[1], c[2], c[3], 1)
    end
    UpdateSwatchColor()
    
    swatch:SetScript("OnClick", function()
        local c = colorTable[colorKey]
        ShowColorPicker(c[1], c[2], c[3], function(r, g, b)
            if r then
                colorTable[colorKey] = {r, g, b, 1}
                UpdateSwatchColor()
                SaveSettings()
            end
        end)
    end)
    
    swatch:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Click to change color")
        GameTooltip:Show()
    end)
    
    swatch:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    return swatch
end

-- DPS Colors Section
local dpsHeader = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dpsHeader:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -120)
dpsHeader:SetText("|cff00ff00DPS/Healer Colors:|r")

CreateColorSwatch(optionsFrame, 20, -145, "Aggro (Bad)", THREAT_COLORS.DPS, "AGGRO")
CreateColorSwatch(optionsFrame, 20, -170, "High Threat (Warning)", THREAT_COLORS.DPS, "HIGH_THREAT")
CreateColorSwatch(optionsFrame, 20, -195, "No Aggro (Good)", THREAT_COLORS.DPS, "NO_AGGRO")

-- Tank Colors Section
local tankHeader = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tankHeader:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -230)
tankHeader:SetText("|cff00ff00Tank Colors:|r")

CreateColorSwatch(optionsFrame, 20, -255, "Has Aggro (Good)", THREAT_COLORS.TANK, "AGGRO")
CreateColorSwatch(optionsFrame, 20, -280, "Losing Aggro (Warning)", THREAT_COLORS.TANK, "LOSING_AGGRO")
CreateColorSwatch(optionsFrame, 20, -305, "No Aggro (Bad)", THREAT_COLORS.TANK, "NO_AGGRO")

-- Status info
local statusLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusLabel:SetPoint("BOTTOMLEFT", optionsFrame, "BOTTOMLEFT", 20, 40)

local function UpdateStatusLabel()
    local status = "Status: "
    if superwow_active then
        status = status .. "|cff00ff00SuperWoW|r "
    end
    if twthreat_active then
        status = status .. "|cff00ff00TWThreat|r "
    end
    if not superwow_active and not twthreat_active then
        status = status .. "|cffff0000Basic Mode|r"
    end
    statusLabel:SetText(status)
end

optionsFrame:SetScript("OnShow", function()
    UpdateStatusLabel()
end)

-- Reset to defaults button
local resetButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
resetButton:SetWidth(120)
resetButton:SetHeight(25)
resetButton:SetPoint("BOTTOM", optionsFrame, "BOTTOM", 0, 20)
resetButton:SetText("Reset Defaults")
resetButton:SetScript("OnClick", function()
    THREAT_COLORS.DPS.AGGRO = {0.85, 0.2, 0.2, 1}
    THREAT_COLORS.DPS.HIGH_THREAT = {1.0, 0.6, 0.0, 1}
    THREAT_COLORS.DPS.NO_AGGRO = {0.41, 0.35, 0.76, 1}
    THREAT_COLORS.TANK.AGGRO = {0.41, 0.35, 0.76, 1}
    THREAT_COLORS.TANK.LOSING_AGGRO = {1.0, 1.0, 0.0, 1}
    THREAT_COLORS.TANK.NO_AGGRO = {0.85, 0.2, 0.2, 1}
    SaveSettings()
    Print("Colors reset to defaults. Reopen settings to see changes.")
    optionsFrame:Hide()
end)

-- Load settings on addon load
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("VARIABLES_LOADED")
loadFrame:SetScript("OnEvent", function()
    LoadSettings()
    Print("Settings loaded.")
end)

Print("Loaded. Use /gp tank or /gp dps to set role.")