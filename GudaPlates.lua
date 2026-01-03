-- GudaPlates for WoW 1.12.1
-- Written for Lua 5.0 (Vanilla)

if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[GudaPlates]|r Loading...")
end

-- Debug flag for duration tracking
local DEBUG_DURATION = false

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
-- Track combat state per nameplate frame to avoid issues with same-named mobs
local superwow_active = (SpellInfo ~= nil) or (UnitGUID ~= nil) or (SUPERWOW_VERSION ~= nil) -- SuperWoW detection
local twthreat_active = UnitThreat ~= nil -- TWThreat detection

-- Debuff settings
local MAX_DEBUFFS = 16
local DEBUFF_SIZE = 16
local showDebuffTimers = true -- Toggle for debuff countdowns

-- Debuff tracking for non-SuperWoW
local debuffTracker = {}

-- Debuff timer tracking: stores {startTime, duration} by "targetName_texture" key
-- This prevents timer reset every frame
local debuffTimers = {}

-- Cast tracking database (keyed by GUID when SuperWoW, or by name otherwise)
local castDB = {}

-- Cast tracking for non-SuperWoW
local castTracker = {}

-- Role setting: "TANK" or "DPS" (DPS includes healers)
local playerRole = "DPS"
local minimapAngle = 220

-- Nameplate overlap setting: true = overlapping, false = stacking (default)
local nameplateOverlap = true

-- Healthbar dimensions
local healthbarHeight = 14
local healthbarWidth = 115

-- Font sizes
local healthFontSize = 10
local levelFontSize = 10
local nameFontSize = 10

-- New settings
local raidIconPosition = "LEFT" -- "LEFT" or "RIGHT"
local swapNameDebuff = true -- false: name below, debuffs above. true: debuffs below, name above.

-- Plater-style threat colors
local THREAT_COLORS = {
    -- DPS/Healer colors
    DPS = {
        AGGRO = {0.41, 0.35, 0.76, 1},       -- Blue: mob attacking you (BAD)
        HIGH_THREAT = {1.0, 0.6, 0.0, 1},  -- Orange: high threat, about to pull (WARNING)
        NO_AGGRO = {0.85, 0.2, 0.2, 1},  -- Red: tank has aggro (GOOD)
    },
    -- Tank colors
    TANK = {
        AGGRO = {0.41, 0.35, 0.76, 1},       -- Blue (matching DPS AGGRO)
        LOSING_AGGRO = {1.0, 0.6, 0.0, 1}, -- Orange (matching DPS HIGH_THREAT)
        NO_AGGRO = {0.85, 0.2, 0.2, 1},  -- Red (matching DPS NO_AGGRO)
        OTHER_TANK = {0.6, 0.8, 1.0, 1},   -- Light Blue: another tank has it
    },
}

-- Load spell database if available
local SpellDB = GudaPlates_SpellDB

-- Verify SpellDB loaded correctly
if not SpellDB then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[GudaPlates]|r ERROR: SpellDB failed to load!")
end

-- ============================================
-- SPELL CAST HOOKS (ShaguTweaks-style)
-- Detects when player casts spells to track debuff durations with correct rank
-- ============================================

-- Helper: Extract rank number from rank string like "Rank 2" (Lua 5.0 compatible)
local function GetRankNumber(rankStr)
	if not rankStr then return 0 end
	-- Lua 5.0 uses string.gfind instead of string.match
	for num in string.gfind(rankStr, "(%d+)") do
		return tonumber(num) or 0
	end
	return 0
end

-- Helper: Get spell name and rank from spellbook by ID
local function GetSpellInfoFromBook(spellId, bookType)
	local name, rank = GetSpellName(spellId, bookType)
	return name, GetRankNumber(rank)
end

-- Helper: Get spell name and rank from spell name string (e.g., "Rend(Rank 2)")
local function ParseSpellName(spellString)
	if not spellString then return nil, 0 end
	-- Try to match "SpellName(Rank X)" format (Lua 5.0 compatible)
	for name, rank in string.gfind(spellString, "^(.+)%(Rank (%d+)%)$") do
		return name, tonumber(rank) or 0
	end
	-- No rank specified, just spell name
	return spellString, 0
end

-- Strip rank suffix from spell name (for combat log parsing)
-- "Rend (Rank 2)" -> "Rend", rank 2
-- "Rend" -> "Rend", rank 0
local function StripSpellRank(spellString)
	if not spellString then return nil, 0 end
	-- Match "SpellName (Rank X)" with space before parenthesis
	for name, rank in string.gfind(spellString, "^(.+) %(Rank (%d+)%)$") do
		return name, tonumber(rank) or 0
	end
	-- Also try without space
	for name, rank in string.gfind(spellString, "^(.+)%(Rank (%d+)%)$") do
		return name, tonumber(rank) or 0
	end
	return spellString, 0
end

-- Hook original CastSpell (ShaguPlates-style)
local Original_CastSpell = CastSpell
CastSpell = function(spellId, bookType)
	if SpellDB and spellId and bookType then
		local spellName, rank = GetSpellName(spellId, bookType)
		if spellName and UnitExists("target") and UnitCanAttack("player", "target") then
			local targetName = UnitName("target")
			local targetLevel = UnitLevel("target") or 0
			local duration = SpellDB:GetDuration(spellName, rank)
			if duration and duration > 0 then
				SpellDB:AddPending(targetName, targetLevel, spellName, duration)
			end
		end
	end
	return Original_CastSpell(spellId, bookType)
end

-- Hook original CastSpellByName (ShaguPlates-style)
local Original_CastSpellByName = CastSpellByName
CastSpellByName = function(spellString, onSelf)
	if SpellDB and spellString then
		local spellName, rank = ParseSpellName(spellString)
		if spellName and UnitExists("target") and UnitCanAttack("player", "target") then
			local targetName = UnitName("target")
			local targetLevel = UnitLevel("target") or 0
			local duration = SpellDB:GetDuration(spellName, rank)
			if duration and duration > 0 then
				SpellDB:AddPending(targetName, targetLevel, spellName, duration)
			end
		end
	end
	return Original_CastSpellByName(spellString, onSelf)
end

-- Hook UseAction (for action bar clicks) (ShaguPlates-style)
local Original_UseAction = UseAction
UseAction = function(slot, checkCursor, onSelf)
	if SpellDB and slot then
		local actionTexture = GetActionTexture(slot)
		if GetActionText(slot) == nil and actionTexture ~= nil then
			local spellName, rank = SpellDB:ScanAction(slot)
			if spellName then
				-- Cache texture -> spell name for debuff display lookup
				if SpellDB.textureToSpell then
					SpellDB.textureToSpell[actionTexture] = spellName
				end
				if UnitExists("target") then
					local targetName = UnitName("target")
					local targetLevel = UnitLevel("target") or 0
					local duration = SpellDB:GetDuration(spellName, rank)
					if duration and duration > 0 then
						SpellDB:AddPending(targetName, targetLevel, spellName, duration)
					end
				end
			end
		end
	end
	return Original_UseAction(slot, checkCursor, onSelf)
end

-- Initialize tooltip scanner for action bar scanning
if SpellDB then
	SpellDB:InitScanner()
end

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
GudaPlates:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
GudaPlates:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
GudaPlates:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE")
GudaPlates:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
GudaPlates:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")
GudaPlates:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF")
GudaPlates:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
GudaPlates:RegisterEvent("CHAT_MSG_SPELL_TRADESKILLS")
GudaPlates:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
GudaPlates:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
GudaPlates:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_OTHER")
GudaPlates:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_PARTY_BUFF")
GudaPlates:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_BUFF")
-- SuperWoW cast event (provides exact GUID of caster)
GudaPlates:RegisterEvent("UNIT_CASTEVENT")
-- ShaguPlates-style events for debuff tracking
GudaPlates:RegisterEvent("SPELLCAST_STOP")
GudaPlates:RegisterEvent("CHAT_MSG_SPELL_FAILED_LOCALPLAYER")
GudaPlates:RegisterEvent("PLAYER_TARGET_CHANGED")
GudaPlates:RegisterEvent("UNIT_AURA")

-- Patterns for removing pending spells (ShaguPlates-style)
local REMOVE_PENDING_PATTERNS = {
	SPELLIMMUNESELFOTHER or "%s is immune to your %s.",
	IMMUNEDAMAGECLASSSELFOTHER or "%s is immune to your %s damage.",
	SPELLMISSSELFOTHER or "Your %s missed %s.",
	SPELLRESISTSELFOTHER or "Your %s was resisted by %s.",
	SPELLEVADEDSELFOTHER or "Your %s was evaded by %s.",
	SPELLDODGEDSELFOTHER or "Your %s was dodged by %s.",
	SPELLDEFLECTEDSELFOTHER or "Your %s was deflected by %s.",
	SPELLREFLECTSELFOTHER or "Your %s was reflected back by %s.",
	SPELLPARRIEDSELFOTHER or "Your %s was parried by %s.",
	SPELLLOGABSORBSELFOTHER or "Your %s is absorbed by %s.",
}

local function UpdateNamePlateDimensions(frame)
    local nameplate = frame.nameplate
    if not nameplate then return end

    nameplate.health:SetHeight(healthbarHeight)
    nameplate.health:SetWidth(healthbarWidth)
    nameplate.castbar:SetWidth(healthbarWidth)

    local healthFont, _, healthFlags = nameplate.healthtext:GetFont()
    nameplate.healthtext:SetFont(healthFont, healthFontSize, healthFlags)

    local levelFont, _, levelFlags = nameplate.level:GetFont()
    nameplate.level:SetFont(levelFont, levelFontSize, levelFlags)

    local nameFont, _, nameFlags = nameplate.name:GetFont()
    nameplate.name:SetFont(nameFont, nameFontSize, nameFlags)

    -- Update Raid Icon position
    if nameplate.original.raidicon then
        nameplate.original.raidicon:ClearAllPoints()
        if raidIconPosition == "LEFT" then
            nameplate.original.raidicon:SetPoint("RIGHT", nameplate.health, "LEFT", -5, 0)
        else
            nameplate.original.raidicon:SetPoint("LEFT", nameplate.health, "RIGHT", 5, 0)
        end
    end
    if frame.raidicon and frame.raidicon ~= nameplate.original.raidicon then
        frame.raidicon:ClearAllPoints()
        if raidIconPosition == "LEFT" then
            frame.raidicon:SetPoint("RIGHT", nameplate.health, "LEFT", -5, 0)
        else
            frame.raidicon:SetPoint("LEFT", nameplate.health, "RIGHT", 5, 0)
        end
    end

    -- Update Name and Debuff positions
    nameplate.name:ClearAllPoints()
    if swapNameDebuff then
        -- Name above castbar, Castbar above healthbar, Debuffs below
        nameplate.name:SetPoint("BOTTOM", nameplate.health, "TOP", 0, 6)
        -- Debuffs below (no gap)
        for i = 1, MAX_DEBUFFS do
            nameplate.debuffs[i]:ClearAllPoints()
            if i == 1 then
                nameplate.debuffs[i]:SetPoint("TOPLEFT", nameplate.health, "BOTTOMLEFT", 0, -1)
            else
                nameplate.debuffs[i]:SetPoint("LEFT", nameplate.debuffs[i-1], "RIGHT", 1, 0)
            end
        end
        -- Castbar above healthbar (no gap)
        nameplate.castbar:ClearAllPoints()
        nameplate.castbar:SetPoint("BOTTOM", nameplate.health, "TOP", 0, 0)
    else
        -- Default: Name below, Debuffs above
        nameplate.name:SetPoint("TOP", nameplate.health, "BOTTOM", 0, -6)
        for i = 1, MAX_DEBUFFS do
            nameplate.debuffs[i]:ClearAllPoints()
            if i == 1 then
                nameplate.debuffs[i]:SetPoint("BOTTOMLEFT", nameplate.health, "TOPLEFT", 0, 1)
            else
                nameplate.debuffs[i]:SetPoint("LEFT", nameplate.debuffs[i-1], "RIGHT", 1, 0)
            end
        end
        -- Adjust castbar to be below healthbar (default mode)
        nameplate.castbar:ClearAllPoints()
        nameplate.castbar:SetPoint("TOP", nameplate.health, "BOTTOM", 0, 0)
    end

    -- When stacking, we also need to update the parent frame size
    -- so the game's stacking logic uses the new dimensions
    if not nameplateOverlap then
        local npWidth = healthbarWidth * UIParent:GetScale()
        local npHeight = (healthbarHeight + 20) * UIParent:GetScale() -- Added space for name/level
        frame:SetWidth(npWidth)
        frame:SetHeight(npHeight)
        nameplate:SetAllPoints(frame)
    else
    -- In overlap mode, frame is 1x1 but nameplate should be clickable
        nameplate:ClearAllPoints()
        nameplate:SetPoint("CENTER", frame, "CENTER", 0, 0)
        nameplate:SetWidth(healthbarWidth)
        nameplate:SetHeight(healthbarHeight + 20)
    end
end


local function round(input, places)
    if not places then places = 0 end
    if type(input) == "number" and type(places) == "number" then
        local pow = 1
        for i = 1, places do pow = pow * 10 end
        return math.floor(input * pow + 0.5) / pow
    end
end

local function FormatTime(remaining)
    if not remaining or remaining < 0 then return "", 1, 1, 1, 1 end
    if remaining > 356400 then -- 99 hours
        return round(remaining / 86400) .. "d", 0.2, 0.2, 1, 1
    elseif remaining > 5940 then -- 99 minutes
        return round(remaining / 3600) .. "h", 0.2, 0.5, 1, 1
    elseif remaining > 99 then
        return round(remaining / 60) .. "m", 0.2, 1, 1, 1
    elseif remaining > 10 then
        -- White: more than 10 seconds
        return round(remaining) .. "", 1, 1, 1, 1
    elseif remaining > 5 then
        -- Yellow: 5-10 seconds
        return round(remaining) .. "", 1, 1, 0, 1
    elseif remaining > 0 then
        -- Red: less than 5 seconds
        return string.format("%.1f", remaining), 1, 0.2, 0.2, 1
    end
    return "", 1, 1, 1, 1
end

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
            if i == 2 then
            -- 2nd region is glow texture
                nameplate.original.glow = region
            elseif i == 6 then
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
    nameplate.health:SetHeight(healthbarHeight)
    nameplate.health:SetWidth(healthbarWidth)
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

    -- Also reparent ShaguTweaks raid icon if present (frame.raidicon)
    if frame.raidicon and frame.raidicon ~= nameplate.original.raidicon then
        frame.raidicon:SetParent(nameplate.health)
        frame.raidicon:ClearAllPoints()
        frame.raidicon:SetPoint("RIGHT", nameplate.health, "LEFT", -5, 0)
        frame.raidicon:SetWidth(24)
        frame.raidicon:SetHeight(24)
        frame.raidicon:SetDrawLayer("OVERLAY")
    end

    -- Target highlight borders (left and right)
    nameplate.health.targetLeft = nameplate.health:CreateTexture(nil, "OVERLAY")
    nameplate.health.targetLeft:SetTexture(1, 1, 1, 1)
    nameplate.health.targetLeft:SetWidth(2)
    nameplate.health.targetLeft:SetPoint("TOPRIGHT", nameplate.health, "TOPLEFT", -1, 0)
    nameplate.health.targetLeft:SetPoint("BOTTOMRIGHT", nameplate.health, "BOTTOMLEFT", -1, 0)
    nameplate.health.targetLeft:Hide()

    nameplate.health.targetRight = nameplate.health:CreateTexture(nil, "OVERLAY")
    nameplate.health.targetRight:SetTexture(1, 1, 1, 1)
    nameplate.health.targetRight:SetWidth(2)
    nameplate.health.targetRight:SetPoint("TOPLEFT", nameplate.health, "TOPRIGHT", 1, 0)
    nameplate.health.targetRight:SetPoint("BOTTOMLEFT", nameplate.health, "BOTTOMRIGHT", 1, 0)
    nameplate.health.targetRight:Hide()

    -- Name below the health bar (like in Plater)
    nameplate.name = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.name:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")
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

    -- Cast Bar below the name
    nameplate.castbar = CreateFrame("StatusBar", nil, nameplate)
    nameplate.castbar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    nameplate.castbar:SetHeight(12)
    nameplate.castbar:SetStatusBarColor(1, 0.8, 0, 1) -- Gold/Yellow color
    nameplate.castbar:Hide()

    nameplate.castbar.bg = nameplate.castbar:CreateTexture(nil, "BACKGROUND")
    nameplate.castbar.bg:SetTexture(0, 0, 0, 1.0)
    nameplate.castbar.bg:SetAllPoints()

    nameplate.castbar.border = nameplate.castbar:CreateTexture(nil, "OVERLAY")
    nameplate.castbar.border:SetTexture(0, 0, 0, 1)
    nameplate.castbar.border:SetPoint("TOPLEFT", nameplate.castbar, "TOPLEFT", -1, 1)
    nameplate.castbar.border:SetPoint("BOTTOMRIGHT", nameplate.castbar, "BOTTOMRIGHT", 1, -1)
    nameplate.castbar.border:SetDrawLayer("BACKGROUND", -1)

    nameplate.castbar.text = nameplate.castbar:CreateFontString(nil, "OVERLAY")
    nameplate.castbar.text:SetFont("Fonts\\ARIALN.TTF", 8, "OUTLINE")
    nameplate.castbar.text:SetPoint("LEFT", nameplate.castbar, "LEFT", 2, 0)
    nameplate.castbar.text:SetTextColor(1, 1, 1, 1)
    nameplate.castbar.text:SetJustifyH("LEFT")

    nameplate.castbar.timer = nameplate.castbar:CreateFontString(nil, "OVERLAY")
    nameplate.castbar.timer:SetFont("Fonts\\ARIALN.TTF", 8, "OUTLINE")
    nameplate.castbar.timer:SetPoint("RIGHT", nameplate.castbar, "RIGHT", -2, 0)
    nameplate.castbar.timer:SetTextColor(1, 1, 1, 1)
    nameplate.castbar.timer:SetJustifyH("RIGHT")

    nameplate.castbar.icon = nameplate.castbar:CreateTexture(nil, "OVERLAY")
    nameplate.castbar.icon:SetWidth(12)
    nameplate.castbar.icon:SetHeight(12)
    nameplate.castbar.icon:SetPoint("RIGHT", nameplate.castbar, "LEFT", -2, 0) -- Outside to the left
    nameplate.castbar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    nameplate.castbar.icon.border = nameplate.castbar:CreateTexture(nil, "BACKGROUND")
    nameplate.castbar.icon.border:SetTexture(0, 0, 0, 1)
    nameplate.castbar.icon.border:SetPoint("TOPLEFT", nameplate.castbar.icon, "TOPLEFT", -1, 1)
    nameplate.castbar.icon.border:SetPoint("BOTTOMRIGHT", nameplate.castbar.icon, "BOTTOMRIGHT", 1, -1)

    -- Debuff icons
    nameplate.debuffs = {}
    for i = 1, MAX_DEBUFFS do
        local debuff = CreateFrame("Frame", nil, nameplate)
        debuff:SetWidth(DEBUFF_SIZE)
        debuff:SetHeight(DEBUFF_SIZE)
        debuff:SetFrameLevel(nameplate.health:GetFrameLevel() + 5)

        debuff.icon = debuff:CreateTexture(nil, "ARTWORK")
        debuff.icon:SetAllPoints()
        debuff.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        debuff.icon:SetDrawLayer("ARTWORK")
        debuff.icon:SetAlpha(1)

        debuff.border = debuff:CreateTexture(nil, "BACKGROUND")
        debuff.border:SetTexture(0, 0, 0, 1)
        debuff.border:SetPoint("TOPLEFT", debuff, "TOPLEFT", -1, 1)
        debuff.border:SetPoint("BOTTOMRIGHT", debuff, "BOTTOMRIGHT", 1, -1)
        debuff.border:SetDrawLayer("BACKGROUND")

        -- Create a container frame for countdown text (ensure proper layering)
        debuff.cdframe = CreateFrame("Frame", nil, debuff)
        debuff.cdframe:SetAllPoints(debuff)
        debuff.cdframe:SetFrameLevel(debuff:GetFrameLevel() + 2)

        -- Text on top of the icon
        debuff.cd = debuff.cdframe:CreateFontString(nil, "OVERLAY")
        debuff.cd:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        debuff.cd:SetPoint("CENTER", debuff.cdframe, "CENTER", 0, 0)
        debuff.cd:SetTextColor(1, 1, 1, 1)
        debuff.cd:SetText("")
        debuff.cd:SetDrawLayer("OVERLAY", 7)

        debuff.count = debuff.cdframe:CreateFontString(nil, "OVERLAY")
        debuff.count:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        debuff.count:SetPoint("BOTTOMRIGHT", debuff, "BOTTOMRIGHT", 1, 0)
        debuff.count:SetTextColor(1, 1, 1, 1)
        debuff.count:SetText("")
        debuff.count:SetDrawLayer("OVERLAY", 7)

        debuff:SetScript("OnUpdate", function()
            local now = GetTime()
            if (this.tick or 0) > now then return else this.tick = now + 0.1 end

            if not this.expirationTime or this.expirationTime == 0 then
                if this.cd and this.cd:GetAlpha() > 0 then
                    this.cd:SetText("")
                    this.cd:SetAlpha(0)
                end
                return
            end

            local timeLeft = this.expirationTime - now

            if timeLeft > 0 then
                local text, r, g, b, a = FormatTime(timeLeft)
                if this.cd and text and text ~= "" then
                    this.cd:SetText(text)
                    if r then
                        this.cd:SetTextColor(r, g, b, a or 1)
                    end
                    if this.cd:GetAlpha() < 1 then
                        this.cd:SetAlpha(1)
                    end
                end
            else
                if this.cd then
                    this.cd:SetText("")
                    this.cd:SetAlpha(0)
                end
                this.expirationTime = 0
            end
        end)

        debuff:Hide()
        nameplate.debuffs[i] = debuff
    end

    UpdateNamePlateDimensions(frame)

    frame.nameplate = nameplate
    registry[frame] = nameplate

    --Print("Hooked: " .. platename)
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
            -- Skip raid icons - we reparented them
                if region ~= nameplate.original.raidicon and region ~= frame.raidicon then
                    region:SetAlpha(0)
                end
            elseif otype == "FontString" then
                region:SetAlpha(0)
            end
        end
    end

    -- Hide all other children frames (like Blizzard or other addon castbars)
    for i, child in ipairs({frame:GetChildren()}) do
        if child and child ~= nameplate and child ~= original.healthbar then
        -- Only hide if it's not a known useful child (like the original castbar if we want it)
        -- ShaguPlates disables the original castbar explicitly.
            if child.SetAlpha then child:SetAlpha(0) end
            if child.Hide then child:Hide() end
        end
    end

    -- Hide ShaguTweaks new frame elements if present (but not raidicon)
    if frame.new then
        frame.new:SetAlpha(0)
        for _, region in ipairs({frame.new:GetRegions()}) do
            if region and region ~= frame.raidicon then
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

    -- Update level from original or ShaguTweaks
    local levelText = nil
    if original.level and original.level.GetText then
        levelText = original.level:GetText()
    end
    -- ShaguTweaks stores level on frame.level
    if not levelText and frame.level and frame.level.GetText then
        levelText = frame.level:GetText()
    end
    if levelText then
        nameplate.level:SetText(levelText)
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

    -- Check original glow texture (shows when having aggro in Vanilla)
    local hasAggroGlow = false
    if original.glow and original.glow.IsShown and original.glow:IsShown() then
        hasAggroGlow = true
    end

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
        -- Use original glow texture as primary indicator if available
        -- Glow usually appears when unit is in combat and has threat
            if hasAggroGlow then
                isAttackingPlayer = true
                nameplate.isAttackingPlayer = true
                nameplate.lastAttackTime = GetTime()
            end

            -- Check if this specific plate was recently confirmed attacking
            if not isAttackingPlayer and nameplate.isAttackingPlayer and nameplate.lastAttackTime and (GetTime() - nameplate.lastAttackTime < 5) then
                isAttackingPlayer = true
            end

            -- If we're targeting this mob, verify and update tracking
            if UnitExists("target") and UnitName("target") == plateName then
            -- Check if target is actually this nameplate (alpha check is a common vanilla trick)
            -- Usually target nameplate has alpha 1.0, others might be 0.x
            -- Note: GetAlpha might be affected by UI modifications, but 1.0 is default for target
                if frame:GetAlpha() > 0.9 then
                    if UnitExists("targettarget") and UnitIsUnit("targettarget", "player") then
                        nameplate.isAttackingPlayer = true
                        nameplate.lastAttackTime = GetTime()
                        isAttackingPlayer = true
                    elseif UnitExists("targettarget") and not UnitIsUnit("targettarget", "player") then
                    -- Mob is targeting someone else, clear tracking
                        nameplate.isAttackingPlayer = false
                        nameplate.lastAttackTime = nil
                        isAttackingPlayer = false
                    end
                end
            end

            -- Expire old entries after 5 seconds without refresh
            if nameplate.isAttackingPlayer and nameplate.lastAttackTime and (GetTime() - nameplate.lastAttackTime > 5) then
                nameplate.isAttackingPlayer = false
                nameplate.lastAttackTime = nil
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
        -- Fallback: assume in combat if attacking player or we have threat data or has glow
            mobInCombat = isAttackingPlayer or (twthreat_active and threatPct > 0) or hasAggroGlow
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

    -- Update Cast Bar
    local casting = nil
    local now = GetTime()

    -- Method 1: Check castDB by GUID (SuperWoW UNIT_CASTEVENT - most accurate)
    if hasValidGUID and castDB[unitstr] then
        local cast = castDB[unitstr]
        -- Check if cast is still active
        if cast.startTime + (cast.duration / 1000) > now then
            casting = cast
        else
            -- Expired, clean up
            castDB[unitstr] = nil
        end
    end

    -- Method 2: Try UnitCastingInfo/UnitChannelInfo (SuperWoW 1.5+)
    if not casting and superwow_active and hasValidGUID then
        if UnitCastingInfo then
            local spell, nameSubtext, text, texture, startTime, endTime, isTradeSkill = UnitCastingInfo(unitstr)
            if spell then
                casting = {
                    spell = spell,
                    startTime = startTime / 1000,
                    duration = endTime - startTime,
                    icon = texture
                }
            end
        end

        if not casting and UnitChannelInfo then
            local spell, nameSubtext, text, texture, startTime, endTime, isTradeSkill = UnitChannelInfo(unitstr)
            if spell then
                casting = {
                    spell = spell,
                    startTime = startTime / 1000,
                    duration = endTime - startTime,
                    icon = texture
                }
            end
        end
    end

    -- Method 3: Fallback to castTracker (combat log based, name-based)
    -- Only used when SuperWoW GUID-based methods didn't find a cast
    if not casting and plateName and castTracker[plateName] and not hasValidGUID then
        -- Clean up expired casts first
        local i = 1
        while i <= table.getn(castTracker[plateName]) do
            local cast = castTracker[plateName][i]
            if now > cast.startTime + (cast.duration / 1000) then
                table.remove(castTracker[plateName], i)
            else
                -- Use first valid cast for this name
                if not casting then
                    casting = cast
                end
                i = i + 1
            end
        end
    end

    if casting and casting.spell then
        local now = GetTime()
        local start = casting.startTime
        local duration = casting.duration

        if now < start + (duration / 1000) then
            nameplate.castbar:SetMinMaxValues(0, duration)
            nameplate.castbar:SetValue((now - start) * 1000)
            nameplate.castbar.text:SetText(casting.spell)

            local timeLeft = (start + (duration / 1000)) - now
            nameplate.castbar.timer:SetText(string.format("%.1fs", timeLeft))

            if casting.icon then
                nameplate.castbar.icon:SetTexture(casting.icon)
                nameplate.castbar.icon:Show()
                if nameplate.castbar.icon.border then nameplate.castbar.icon.border:Show() end
            else
                nameplate.castbar.icon:Hide()
                if nameplate.castbar.icon.border then nameplate.castbar.icon.border:Hide() end
            end

            nameplate.castbar:Show()
        else
            nameplate.castbar:Hide()
        end
    else
        nameplate.castbar:Hide()
    end

    -- Update Debuffs
    for i = 1, MAX_DEBUFFS do
        nameplate.debuffs[i]:Hide()
        nameplate.debuffs[i].count:SetText("")
        nameplate.debuffs[i].expirationTime = 0
    end

    local debuffIndex = 1
    local now = GetTime()
    if superwow_active and hasValidGUID then
        for i = 1, 40 do
            if debuffIndex > MAX_DEBUFFS then break end

            -- Get debuff info from the game
            local texture, stacks = UnitDebuff(unitstr, i)
            if not texture then break end

            -- Try to get effect name and tracked data from SpellDB
            local effect, duration, timeleft = nil, nil, nil
            if SpellDB then
                -- Try tooltip scanning (may fail with GUID, will fallback to "target" if GUID matches)
                effect = SpellDB:ScanDebuff(unitstr, i)

                -- If GUID scanning failed, try "target" ONLY if this exact GUID is the target
                -- (not just same name - could be different mob with same name)
                if (not effect or effect == "") then
                    local targetGUID = UnitGUID and UnitGUID("target")
                    if targetGUID and targetGUID == unitstr then
                        effect = SpellDB:ScanDebuff("target", i)
                    end
                end

                -- Last resort: try texture-to-spell cache directly
                if (not effect or effect == "") and SpellDB.textureToSpell and SpellDB.textureToSpell[texture] then
                    effect = SpellDB.textureToSpell[texture]
                end

                -- Try to get tracked data from SpellDB.objects
                -- First try by GUID (unitstr), then by name (plateName)
                if effect and effect ~= "" then
                    local unitlevel = UnitLevel(unitstr) or 0
                    local data = nil

                    -- Try GUID lookup first (most accurate for multiple mobs with same name)
                    if SpellDB.objects[unitstr] then
                        if SpellDB.objects[unitstr][unitlevel] and SpellDB.objects[unitstr][unitlevel][effect] then
                            data = SpellDB.objects[unitstr][unitlevel][effect]
                        elseif SpellDB.objects[unitstr][0] and SpellDB.objects[unitstr][0][effect] then
                            data = SpellDB.objects[unitstr][0][effect]
                        else
                            for lvl, effects in pairs(SpellDB.objects[unitstr]) do
                                if effects[effect] then
                                    data = effects[effect]
                                    break
                                end
                            end
                        end
                    end

                    -- Fallback to name lookup
                    if not data and plateName and SpellDB.objects[plateName] then
                        if SpellDB.objects[plateName][unitlevel] and SpellDB.objects[plateName][unitlevel][effect] then
                            data = SpellDB.objects[plateName][unitlevel][effect]
                        elseif SpellDB.objects[plateName][0] and SpellDB.objects[plateName][0][effect] then
                            data = SpellDB.objects[plateName][0][effect]
                        else
                            for lvl, effects in pairs(SpellDB.objects[plateName]) do
                                if effects[effect] then
                                    data = effects[effect]
                                    break
                                end
                            end
                        end
                    end

                    if data and data.start and data.duration then
                        if data.start + data.duration > now then
                            duration = data.duration
                            timeleft = data.duration + data.start - now
                        end
                    end
                end

                -- Get duration from database if we don't have tracked data
                if effect and effect ~= "" and not duration then
                    duration = SpellDB:GetDuration(effect, 0)
                end
            end
            local debuff = nameplate.debuffs[debuffIndex]
            debuff.icon:SetTexture(texture)

            -- Set stacks
            if stacks and stacks > 1 then
                debuff.count:SetText(stacks)
                debuff.count:SetAlpha(1)
            else
                debuff.count:SetText("")
                debuff.count:SetAlpha(0)
            end

            -- Calculate time left for display
            local displayTimeLeft = nil
            -- Use GUID (unitstr) for unique cache key, not plateName (multiple mobs can have same name)
            local debuffKey = unitstr .. "_" .. (effect or texture)

            if timeleft and timeleft > 0 then
                -- Use accurate tracked data from SpellDB
                displayTimeLeft = timeleft
                -- Update cache with correct data so fallback stays in sync
                debuffTimers[debuffKey] = {
                    startTime = now - (duration - timeleft),
                    duration = duration,
                    lastSeen = now
                }
            else
                -- Fallback: use debuffTimers cache
                local fallbackDuration = duration or 1  -- Default 1s if unknown

                if not debuffTimers[debuffKey] then
                    debuffTimers[debuffKey] = {
                        startTime = now,
                        duration = fallbackDuration
                    }
                end
                local cached = debuffTimers[debuffKey]
                cached.lastSeen = now
                displayTimeLeft = cached.duration - (now - cached.startTime)
            end

            -- Display timer
            if showDebuffTimers and displayTimeLeft and displayTimeLeft > 0 then
                debuff.expirationTime = now + displayTimeLeft

                local text, r, g, b, a = FormatTime(displayTimeLeft)
                if debuff.cd and text and text ~= "" then
                    debuff.cd:SetText(text)
                    if r then debuff.cd:SetTextColor(r, g, b, a or 1) end
                    debuff.cd:SetAlpha(1)
                    debuff.cd:Show()
                end
                if debuff.cdframe then
                    debuff.cdframe:Show()
                end
            else
                debuff.expirationTime = 0
                if debuff.cd then
                    debuff.cd:SetText("")
                    debuff.cd:SetAlpha(0)
                end
            end

            debuff:Show()
            debuff.icon:SetAlpha(1)
            debuffIndex = debuffIndex + 1
        end
    elseif plateName then
    -- Fallback for non-SuperWoW: use UnitDebuff if it's the target
        if isTarget then
            for i = 1, 16 do
                if debuffIndex > MAX_DEBUFFS then break end

                -- Use ShaguPlates-style UnitDebuff wrapper
                local effect, rank, texture, stacks, dtype, duration, timeleft
                if SpellDB then
                    effect, rank, texture, stacks, dtype, duration, timeleft = SpellDB:UnitDebuff("target", i)
                else
                    texture, stacks = UnitDebuff("target", i)
                end

                if not texture then break end

                local debuff = nameplate.debuffs[debuffIndex]
                debuff.icon:SetTexture(texture)

                -- Set stacks
                if stacks and stacks > 1 then
                    debuff.count:SetText(stacks)
                    debuff.count:SetAlpha(1)
                else
                    debuff.count:SetText("")
                    debuff.count:SetAlpha(0)
                end

                -- Calculate time left for display
                local displayTimeLeft = nil

                -- If we have valid timeleft from SpellDB (from tracked data), use it directly
                if timeleft and timeleft > 0 then
                    displayTimeLeft = timeleft
                elseif effect and effect ~= "" and duration and duration > 0 then
                    -- Fallback: use debuffTimers cache to track when we first saw this debuff
                    local debuffKey = plateName .. "_" .. effect
                    if not debuffTimers[debuffKey] then
                        debuffTimers[debuffKey] = {
                            startTime = now,
                            duration = duration
                        }
                    end
                    local cached = debuffTimers[debuffKey]
                    cached.lastSeen = now
                    displayTimeLeft = cached.duration - (now - cached.startTime)
                end

                -- Display timer
                if showDebuffTimers and displayTimeLeft and displayTimeLeft > 0 then
                    debuff.expirationTime = now + displayTimeLeft

                    local text, r, g, b, a = FormatTime(displayTimeLeft)
                    if debuff.cd and text and text ~= "" then
                        debuff.cd:SetText(text)
                        if r then debuff.cd:SetTextColor(r, g, b, a or 1) end
                        debuff.cd:SetAlpha(1)
                        debuff.cd:Show()
                    end
                    if debuff.cdframe then
                        debuff.cdframe:Show()
                    end
                else
                    debuff.expirationTime = 0
                    if debuff.cd then
                        debuff.cd:SetText("")
                        debuff.cd:SetAlpha(0)
                    end
                end

                debuff:Show()
                debuff.icon:SetAlpha(1)
                debuffIndex = debuffIndex + 1
            end
        end
    end

    -- Centering logic
    local numDebuffs = debuffIndex - 1
    if numDebuffs > 0 then
        local totalWidth = (numDebuffs * DEBUFF_SIZE) + (numDebuffs - 1) * 1
        local startOffset = -totalWidth / 2

        for i = 1, numDebuffs do
            local debuff = nameplate.debuffs[i]
            debuff:ClearAllPoints()
            local x = startOffset + (i - 1) * (DEBUFF_SIZE + 1) + (DEBUFF_SIZE / 2)
            if swapNameDebuff then
                -- Debuffs below healthbar (no gap)
                debuff:SetPoint("TOP", nameplate.health, "BOTTOM", x, 0)

                -- Adjust name (above castbar which is above healthbar)
                nameplate.name:ClearAllPoints()
                nameplate.name:SetPoint("BOTTOM", nameplate.health, "TOP", 0, 14)
            else
                -- Debuffs above healthbar
                debuff:SetPoint("BOTTOM", nameplate.health, "TOP", x, 6)

                -- Adjust name
                nameplate.name:ClearAllPoints()
                nameplate.name:SetPoint("TOP", nameplate.health, "BOTTOM", 0, -6)
            end
        end
    else
    -- Reset positions if no debuffs
        UpdateNamePlateDimensions(frame)
    end

    -- Dynamic castbar positioning based on debuffs (only when castbar is visible)
    if nameplate.castbar:IsShown() then
        nameplate.castbar:ClearAllPoints()
        if swapNameDebuff then
            -- Swapped mode: castbar above healthbar (no gap)
            nameplate.castbar:SetPoint("BOTTOM", nameplate.health, "TOP", 0, 0)
        else
            -- Default mode: castbar below healthbar, move name down to avoid overlap
            nameplate.castbar:SetPoint("TOP", nameplate.health, "BOTTOM", 0, 0)
            nameplate.name:ClearAllPoints()
            nameplate.name:SetPoint("TOP", nameplate.health, "BOTTOM", 0, -14)
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
-- Throttle for debuff timer cleanup
local lastDebuffCleanup = 0

GudaPlates:SetScript("OnUpdate", function()
-- Reset tracking flags for non-SuperWoW timers once per frame
    if not superwow_active then
        for _, data in pairs(debuffTracker) do
            data.usedThisFrame = nil
        end
    end

    -- Cleanup stale debuff timers every 1 second
    -- Remove entries that haven't been seen in 2+ seconds (debuff removed or target despawned)
    local now = GetTime()
    if now - lastDebuffCleanup > 1 then
        lastDebuffCleanup = now
        for key, data in pairs(debuffTimers) do
            if data.lastSeen and (now - data.lastSeen > 2) then
                debuffTimers[key] = nil
            end
        end
    end

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

                -- Ensure dimensions are correct
                UpdateNamePlateDimensions(plate)
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
                nameplate:EnableMouse(false)
            end

            -- Ensure dimensions are correct
            UpdateNamePlateDimensions(plate)
        end
    end
end)

-- Helper function to match combat log patterns (ShaguPlates-style cmatch)
local function cmatch(str, pattern)
    if not str or not pattern then return nil end
    -- Convert WoW format strings to Lua patterns
    local pat = gsub(pattern, "%%%d?%$?s", "(.+)")
    pat = gsub(pat, "%%%d?%$?d", "(%d+)")
    for a, b, c, d in string.gfind(str, pat) do
        return a, b, c, d
    end
    return nil
end


-- Cast icons lookup table
local castIcons = {
    ["Fireball"] = "Interface\\Icons\\Spell_Fire_FlameBolt",
    ["Frostbolt"] = "Interface\\Icons\\Spell_Frost_FrostBolt02",
    ["Shadow Bolt"] = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
    ["Greater Heal"] = "Interface\\Icons\\Spell_Holy_GreaterHeal",
    ["Flash Heal"] = "Interface\\Icons\\Spell_Holy_FlashHeal",
    ["Lightning Bolt"] = "Interface\\Icons\\Spell_Nature_Lightning",
    ["Chain Lightning"] = "Interface\\Icons\\Spell_Nature_ChainLightning",
    ["Earthbind Totem"] = "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02",
    ["Healing Wave"] = "Interface\\Icons\\Spell_Nature_MagicImmunity",
    ["Fear"] = "Interface\\Icons\\Spell_Shadow_Possession",
    ["Polymorph"] = "Interface\\Icons\\Spell_Nature_Polymorph",
    ["Scorching Totem"] = "Interface\\Icons\\Spell_Fire_ScorchingTotem",
    ["Slowing Poison"] = "Interface\\Icons\\Ability_PoisonSting",
    ["Web"] = "Interface\\Icons\\Ability_Ensnare",
    ["Cursed Blood"] = "Interface\\Icons\\Spell_Shadow_RitualOfSacrifice",
    ["Shrink"] = "Interface\\Icons\\Spell_Shadow_AntiShadow",
    ["Shadow Weaving"] = "Interface\\Icons\\Spell_Shadow_BlackPlague",
    ["Smite"] = "Interface\\Icons\\Spell_Holy_HolySmite",
    ["Mind Blast"] = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
    ["Holy Light"] = "Interface\\Icons\\Spell_Holy_HolyLight",
    ["Starfire"] = "Interface\\Icons\\Spell_Arcane_StarFire",
    ["Wrath"] = "Interface\\Icons\\Spell_Nature_AbolishMagic",
    ["Entangling Roots"] = "Interface\\Icons\\Spell_Nature_StrangleVines",
    ["Moonfire"] = "Interface\\Icons\\Spell_Nature_StarFall",
    ["Regrowth"] = "Interface\\Icons\\Spell_Nature_ResistNature",
    ["Rejuvenation"] = "Interface\\Icons\\Spell_Nature_Rejuvenation",
}

-- Helper function to parse cast starts from combat log
local function ParseCastStart(msg)
    if not msg then return end

    local unit, spell = nil, nil

    -- Try "begins to cast"
    for u, s in string.gfind(msg, "(.+) begins to cast (.+)%.") do
        unit, spell = u, s
    end

    -- Try "begins to perform"
    if not unit then
        for u, s in string.gfind(msg, "(.+) begins to perform (.+)%.") do
            unit, spell = u, s
        end
    end

    if unit and spell then
        local duration = 2000 -- Default 2 seconds

        if not castTracker[unit] then castTracker[unit] = {} end

        local newCast = {
            spell = spell,
            startTime = GetTime(),
            duration = duration,
            icon = castIcons[spell],
        }

        table.insert(castTracker[unit], newCast)
    end

    -- Check for interrupts/failures
    local interruptedUnit = nil
    for u in string.gfind(msg, "(.+)'s .+ is interrupted%.") do interruptedUnit = u end
    if not interruptedUnit then
        for u in string.gfind(msg, "(.+)'s .+ fails%.") do interruptedUnit = u end
    end

    if interruptedUnit and castTracker[interruptedUnit] then
        table.remove(castTracker[interruptedUnit], 1)
    end
end

GudaPlates:SetScript("OnEvent", function()
    -- Parse cast starts for ALL combat log events first
    if arg1 and string.find(event, "CHAT_MSG_SPELL") then
        ParseCastStart(arg1)
    end

    if event == "PLAYER_ENTERING_WORLD" then
    -- Clear trackers on zone/load
        debuffTracker = {}
        castTracker = {}
        castDB = {}
        if SpellDB then SpellDB.objects = {} end
        Print("Initialized. Scanning...")
        if twthreat_active then
            Print("TWThreat detected - full threat colors enabled")
        end
        if superwow_active then
            Print("SuperWoW detected - GUID targeting enabled")
            if showDebuffTimers then
                Print("Debuff countdowns enabled")
            end
        end

    -- SuperWoW UNIT_CASTEVENT handler (ShaguPlates-style)
    -- This provides exact GUID of caster for accurate per-mob cast tracking
    elseif event == "UNIT_CASTEVENT" then
        local guid = arg1      -- GUID of the caster
        local target = arg2    -- target GUID (can be empty)
        local eventType = arg3 -- "START", "CAST", "CHANNEL", "FAIL"
        local spellId = arg4   -- spell ID
        local timer = arg5     -- duration in milliseconds

        if eventType == "START" or eventType == "CAST" or eventType == "CHANNEL" then
            -- Get spell info from SpellInfo if available
            local spell, icon
            if SpellInfo and spellId then
                spell, _, icon = SpellInfo(spellId)
            end

            -- Fallback values
            spell = spell or "Casting"
            icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"

            -- Skip buff procs during cast (same logic as ShaguPlates)
            if eventType == "CAST" then
                if castDB[guid] and castDB[guid].spell ~= spell then
                    return
                end
            end

            -- Store cast by GUID
            castDB[guid] = {
                spell = spell,
                startTime = GetTime(),
                duration = timer or 2000,
                icon = icon,
                channel = (eventType == "CHANNEL")
            }
        elseif eventType == "FAIL" then
            -- Remove cast entry for this GUID
            if castDB[guid] then
                castDB[guid] = nil
            end
        end

    -- ShaguPlates-style event handlers
    elseif event == "SPELLCAST_STOP" then
        -- For instant spells that refresh existing debuffs
        -- The "afflicted" message doesn't fire on refresh, only on initial apply
        if SpellDB and SpellDB.pending[3] then
            local effect = SpellDB.pending[3]
            local duration = SpellDB.pending[4]
            local unitName = SpellDB.pending[5]
            local unitlevel = SpellDB.pending[2]
            
            local hasObject = SpellDB.objects[unitName] and SpellDB.objects[unitName][unitlevel] and SpellDB.objects[unitName][unitlevel][effect]
            
            -- Check if this debuff already exists on target (refresh case)
            if unitName and hasObject then
                SpellDB:RefreshEffect(unitName, unitlevel, effect, duration)
                SpellDB:RemovePending()
            end
            -- If not existing, wait for combat log "afflicted" message
        end

    elseif event == "CHAT_MSG_SPELL_FAILED_LOCALPLAYER" and arg1 then
        -- Remove pending spell on failure
        if SpellDB then
            for _, pattern in pairs(REMOVE_PENDING_PATTERNS) do
                local effect = cmatch(arg1, pattern)
                if effect and SpellDB.pending[3] == effect then
                    SpellDB:RemovePending()
                    return
                end
            end
        end

    elseif event == "PLAYER_TARGET_CHANGED" or (event == "UNIT_AURA" and arg1 == "target") then
        -- Add missing debuffs by iteration (ShaguPlates-style)
        if SpellDB and UnitExists("target") then
            local unitname = UnitName("target")
            local unitlevel = UnitLevel("target") or 0
            for i = 1, 16 do
                local effect, rank, texture, stacks, dtype, duration, timeleft = SpellDB:UnitDebuff("target", i)
                if not texture then break end
                if effect and effect ~= "" then
                    -- Don't overwrite existing timers
                    if not SpellDB.objects[unitname] or not SpellDB.objects[unitname][unitlevel] or not SpellDB.objects[unitname][unitlevel][effect] then
                        SpellDB:AddEffect(unitname, unitlevel, effect)
                    end
                end
            end
        end

    elseif event == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE" or event == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" then
        -- Track debuff applications from combat log (ShaguPlates-style)
        if arg1 and SpellDB then
            -- Pattern: "Unit is afflicted by Spell."
            local unit, effect = cmatch(arg1, AURAADDEDOTHERHARMFUL or "%s is afflicted by %s.")
            if unit and effect then
                local unitlevel = UnitName("target") == unit and UnitLevel("target") or 0
                local recent = SpellDB.recentCasts and SpellDB.recentCasts[effect]
                local isRecentCast = recent and recent.time and (GetTime() - recent.time) < 3
                
                -- First try to persist pending spell (this has accurate rank/duration from cast hook)
                if SpellDB.pending[3] == effect then
                    SpellDB:PersistPending(effect)
                elseif isRecentCast then
                    -- Recent cast - refresh the timer (player reapplied the debuff)
                    SpellDB:RefreshEffect(unit, unitlevel, effect, recent.duration)
                else
                    -- Not our spell, only add if not already tracked
                    if not SpellDB.objects[unit] or not SpellDB.objects[unit][unitlevel] or not SpellDB.objects[unit][unitlevel][effect] then
                        local dbDuration = SpellDB:GetDuration(effect, 0)
                        SpellDB:AddEffect(unit, unitlevel, effect, dbDuration)
                    end
                end
            end
        end

    elseif arg1 then
        -- Pattern: "Spell fades from Unit."
        for rawSpell, unit in string.gfind(arg1, "(.+) fades from (.+)%.") do
            local spell = StripSpellRank(rawSpell)
            debuffTracker[unit .. spell] = nil
            -- Remove from SpellDB objects (all levels)
            if SpellDB and SpellDB.objects and SpellDB.objects[unit] then
                for level, effects in pairs(SpellDB.objects[unit]) do
                    if effects[spell] then effects[spell] = nil end
                end
            end
        end
        for rawSpell, unit in string.gfind(arg1, "(.+) is removed from (.+)%.") do
            local spell = StripSpellRank(rawSpell)
            debuffTracker[unit .. spell] = nil
            if SpellDB and SpellDB.objects and SpellDB.objects[unit] then
                for level, effects in pairs(SpellDB.objects[unit]) do
                    if effects[spell] then effects[spell] = nil end
                end
            end
        end
    elseif event == "CHAT_MSG_SPELL_AURA_GONE_OTHER" and arg1 then
        for rawSpell, unit in string.gfind(arg1, "(.+) fades from (.+)%.") do
            local spell = StripSpellRank(rawSpell)
            debuffTracker[unit .. spell] = nil
            if SpellDB and SpellDB.objects and SpellDB.objects[unit] then
                for level, effects in pairs(SpellDB.objects[unit]) do
                    if effects[spell] then effects[spell] = nil end
                end
            end
        end
        for rawSpell, unit in string.gfind(arg1, "(.+) is removed from (.+)%.") do
            local spell = StripSpellRank(rawSpell)
            debuffTracker[unit .. spell] = nil
            if SpellDB and SpellDB.objects and SpellDB.objects[unit] then
                for level, effects in pairs(SpellDB.objects[unit]) do
                    if effects[spell] then effects[spell] = nil end
                end
            end
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
    elseif msg == "debug" or msg == "debuffs" then
        -- Show all debuffs on current target using tooltip scanning
        if not UnitExists("target") then
            Print("No target selected. Target a unit with debuffs first.")
            return
        end
        local targetName = UnitName("target") or "target"
        Print("=== Debuffs on " .. targetName .. " ===")
        local found = false
        for i = 1, 40 do
            local texture, count = UnitDebuff("target", i)
            if not texture then break end
            found = true
            -- Use tooltip scanning to get spell name
            local spellName = SpellDB and SpellDB:ScanDebuff("target", i)
            local duration = spellName and SpellDB and SpellDB:GetDuration(spellName, 0)
            local durationStr = duration and (duration .. "s") or "NOT IN DB"
            Print(i .. ": " .. (spellName or "UNKNOWN") .. " (" .. durationStr .. ")")
            -- Check if we have tracked data
            if SpellDB and spellName then
                local tracked = SpellDB:GetTrackedDebuff(targetName, spellName)
                if tracked then
                    local remaining = tracked.duration - (GetTime() - tracked.start)
                    Print("   -> TRACKED: " .. string.format("%.1f", remaining) .. "s left (rank " .. (tracked.rank or 0) .. ")")
                end
            end
        end
        if not found then
            Print("No debuffs found on target.")
        end
        Print("=== End of debuffs ===")
    elseif msg == "tracked" then
        -- Show all tracked debuffs in SpellDB (ShaguPlates-style objects)
        Print("=== Tracked Debuffs ===")
        if SpellDB and SpellDB.objects then
            local count = 0
            for unitName, levels in pairs(SpellDB.objects) do
                for level, debuffs in pairs(levels) do
                    for spellName, data in pairs(debuffs) do
                        if data.start and data.duration then
                            local remaining = data.duration - (GetTime() - data.start)
                            if remaining > 0 then
                                Print(unitName .. " (L" .. level .. "): " .. spellName .. " - " .. string.format("%.1f", remaining) .. "s left")
                                count = count + 1
                            end
                        end
                    end
                end
            end
            if count == 0 then
                Print("No tracked debuffs.")
            end
        else
            Print("SpellDB not loaded or no tracked debuffs.")
        end
        Print("=== End of tracked ===")
    elseif msg == "pending" then
        -- Show pending spell cast (ShaguPlates-style array format)
        Print("=== Pending Spell ===")
        if SpellDB and SpellDB.pending and SpellDB.pending[3] then
            local p = SpellDB.pending
            Print("Unit: " .. (p[1] or "nil"))
            Print("Level: " .. (p[2] or 0))
            Print("Spell: " .. (p[3] or "nil"))
            Print("Duration: " .. (p[4] or "nil") .. "s")
        else
            Print("No pending spell.")
        end
    elseif msg == "spelldb" then
        -- Test SpellDB loading
        Print("=== SpellDB Status ===")
        if SpellDB then
            Print("SpellDB loaded: YES")
            Print("GetDuration: " .. tostring(SpellDB.GetDuration ~= nil))
            Print("ScanDebuff: " .. tostring(SpellDB.ScanDebuff ~= nil))
            -- Test Rend lookup
            local rendDur = SpellDB:GetDuration("Rend", 2)
            Print("Test - Rend Rank 2 -> " .. tostring(rendDur) .. "s")
            local rendMax = SpellDB:GetDuration("Rend", 0)
            Print("Test - Rend default -> " .. tostring(rendMax) .. "s")
        else
            Print("SpellDB loaded: NO")
            Print("GudaPlates_SpellDB: " .. tostring(GudaPlates_SpellDB ~= nil))
        end
    else
        Print("Commands: /gp tank | /gp dps | /gp toggle | /gp config")
        Print("         /gp debug - Show target debuffs with tooltip scanning")
        Print("         /gp tracked - Show all tracked debuffs")
        Print("         /gp pending - Show pending spell cast")
        Print("         /gp spelldb - Test SpellDB loading")
        Print("Current role: " .. playerRole)
    end
end

-- Saved Variables (will be loaded from SavedVariables)
GudaPlatesDB = GudaPlatesDB or {}

local function SaveSettings()
    GudaPlatesDB.playerRole = playerRole
    GudaPlatesDB.THREAT_COLORS = THREAT_COLORS
    GudaPlatesDB.nameplateOverlap = nameplateOverlap
    GudaPlatesDB.minimapAngle = minimapAngle
    GudaPlatesDB.healthbarHeight = healthbarHeight
    GudaPlatesDB.healthbarWidth = healthbarWidth
    GudaPlatesDB.healthFontSize = healthFontSize
    GudaPlatesDB.levelFontSize = levelFontSize
    GudaPlatesDB.nameFontSize = nameFontSize
    GudaPlatesDB.raidIconPosition = raidIconPosition
    GudaPlatesDB.swapNameDebuff = swapNameDebuff
    GudaPlatesDB.showDebuffTimers = showDebuffTimers
end

local function LoadSettings()
    if GudaPlatesDB.playerRole then
        playerRole = GudaPlatesDB.playerRole
    end
    if GudaPlatesDB.nameplateOverlap ~= nil then
        nameplateOverlap = GudaPlatesDB.nameplateOverlap
    end
    if GudaPlatesDB.minimapAngle then
        minimapAngle = GudaPlatesDB.minimapAngle
    end
    if GudaPlatesDB.healthbarHeight then
        healthbarHeight = GudaPlatesDB.healthbarHeight
    end
    if GudaPlatesDB.healthbarWidth then
        healthbarWidth = GudaPlatesDB.healthbarWidth
    end
    if GudaPlatesDB.healthFontSize then
        healthFontSize = GudaPlatesDB.healthFontSize
    end
    if GudaPlatesDB.levelFontSize then
        levelFontSize = GudaPlatesDB.levelFontSize
    end
    if GudaPlatesDB.nameFontSize then
        nameFontSize = GudaPlatesDB.nameFontSize
    end
    if GudaPlatesDB.raidIconPosition then
        raidIconPosition = GudaPlatesDB.raidIconPosition
    end
    if GudaPlatesDB.swapNameDebuff ~= nil then
        swapNameDebuff = GudaPlatesDB.swapNameDebuff
    end
    if GudaPlatesDB.showDebuffTimers ~= nil then
        showDebuffTimers = GudaPlatesDB.showDebuffTimers
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
minimapButton:SetFrameStrata("LOW")
minimapButton:SetToplevel(true)
minimapButton:SetMovable(true)
minimapButton:EnableMouse(true)
minimapButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local minimapIcon = minimapButton:CreateTexture(nil, "BACKGROUND")
minimapIcon:SetTexture("Interface\\Icons\\Spell_Nature_WispSplode")
minimapIcon:SetWidth(20)
minimapIcon:SetHeight(20)
minimapIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
minimapIcon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)

local minimapBorder = minimapButton:CreateTexture(nil, "OVERLAY")
minimapBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
minimapBorder:SetWidth(52)
minimapBorder:SetHeight(52)
minimapBorder:SetPoint("CENTER", minimapButton, "CENTER", 10, -10)

-- Minimap button dragging
local function UpdateMinimapButtonPosition()
    local rad = math.rad(minimapAngle)
    local x = math.cos(rad) * 80
    local y = math.sin(rad) * 80
    minimapButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52 - x, y - 52)
end
UpdateMinimapButtonPosition()

minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:RegisterForDrag("LeftButton", "RightButton")
minimapButton:SetScript("OnDragStart", function()
    this.dragging = true
    this:LockHighlight()
end)

minimapButton:SetScript("OnDragStop", function()
    this.dragging = false
    this:UnlockHighlight()
    SaveSettings()
end)

minimapButton:SetScript("OnUpdate", function()
    if this.dragging then
        local xpos, ypos = GetCursorPosition()
        local xmin, ymin = Minimap:GetLeft() or 400, Minimap:GetBottom() or 400
        local mscale = Minimap:GetEffectiveScale()

        -- TrinketMenu logic:
        -- xpos = xmin - xpos / mscale + 70
        -- ypos = ypos / mscale - ymin - 70
        -- angle = math.deg(math.atan2(ypos, xpos))

        local dx = xmin - xpos / mscale + 70
        local dy = ypos / mscale - ymin - 70
        minimapAngle = math.deg(math.atan2(dy, dx))
        UpdateMinimapButtonPosition()
    end
end)

minimapButton:SetScript("OnClick", function()
    if arg1 == "RightButton" or IsControlKeyDown() then
        if GudaPlatesOptionsFrame:IsShown() then
            GudaPlatesOptionsFrame:Hide()
        else
            GudaPlatesOptionsFrame:Show()
        end
    end
end)

minimapButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("GudaPlates")
    GameTooltip:AddLine("Left-Drag to move button", 1, 1, 1)
    GameTooltip:AddLine("Right-Click or Ctrl-Left-Click for settings", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)

minimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Options Frame
local optionsFrame = CreateFrame("Frame", "GudaPlatesOptionsFrame", UIParent)
optionsFrame:SetFrameStrata("DIALOG")
optionsFrame:SetFrameLevel(100)
optionsFrame:SetWidth(500)
optionsFrame:SetHeight(580)
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

-- Nameplate Mode Selection
local overlapCheckbox = CreateFrame("CheckButton", "GudaPlatesOverlapCheckbox", optionsFrame, "UICheckButtonTemplate")
overlapCheckbox:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -50)
local overlapLabel = getglobal(overlapCheckbox:GetName().."Text")
overlapLabel:SetText("Overlapping Nameplates")
overlapLabel:SetFont("Fonts\\FRIZQT__.TTF", 14)
overlapCheckbox:SetScript("OnClick", function()
    nameplateOverlap = this:GetChecked() == 1
    SaveSettings()
    if nameplateOverlap then
        Print("Nameplates set to OVERLAPPING")
    else
        Print("Nameplates set to STACKING")
    end
end)
overlapCheckbox:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Overlapping Nameplates")
    GameTooltip:AddLine("If unchecked, nameplates will use 'Stacking' mode (default).", 1, 1, 1, 1)
    GameTooltip:Show()
end)
overlapCheckbox:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Role Selection
local tankCheckbox = CreateFrame("CheckButton", "GudaPlatesTankCheckbox", optionsFrame, "UICheckButtonTemplate")
tankCheckbox:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 250, -50)
local tankLabel = getglobal(tankCheckbox:GetName().."Text")
tankLabel:SetText("Tank Mode")
tankLabel:SetFont("Fonts\\FRIZQT__.TTF", 14)
tankCheckbox:SetScript("OnClick", function()
    if this:GetChecked() == 1 then
        playerRole = "TANK"
    else
        playerRole = "DPS"
    end
    SaveSettings()
    Print("Role set to " .. playerRole)
end)
tankCheckbox:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Tank Mode")
    GameTooltip:AddLine("If unchecked, you are in DPS/Healer mode.", 1, 1, 1, 1)
    GameTooltip:Show()
end)
tankCheckbox:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Color picker helper
local function ShowColorPicker(r, g, b, callback)
    ColorPickerFrame.func = function()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        callback(r, g, b)
    end
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = {r, g, b}
    ColorPickerFrame.cancelFunc = function()
        local prev = ColorPickerFrame.previousValues
        callback(prev[1], prev[2], prev[3])
    end
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
end

-- Create color swatch
local swatches = {}
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

    -- Store for global updates
    table.insert(swatches, UpdateSwatchColor)

    swatch:SetScript("OnClick", function()
        local c = colorTable[colorKey]
        ShowColorPicker(c[1], c[2], c[3], function(r, g, b)
            if r then
                colorTable[colorKey] = {r, g, b, 1}
                UpdateSwatchColor()
                SaveSettings()
                -- Force refresh of all visible nameplates
                for plate, _ in pairs(registry) do
                    if plate:IsShown() then
                        UpdateNamePlate(plate)
                    end
                end
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
dpsHeader:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -100)
dpsHeader:SetText("|cff00ff00DPS/Healer Colors:|r")

CreateColorSwatch(optionsFrame, 20, -125, "Aggro (Bad)", THREAT_COLORS.DPS, "AGGRO")
CreateColorSwatch(optionsFrame, 20, -150, "High Threat (Warning)", THREAT_COLORS.DPS, "HIGH_THREAT")
CreateColorSwatch(optionsFrame, 20, -175, "No Aggro (Good)", THREAT_COLORS.DPS, "NO_AGGRO")

-- Tank Colors Section
local tankHeader = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tankHeader:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 250, -100)
tankHeader:SetText("|cff00ff00Tank Colors:|r")

CreateColorSwatch(optionsFrame, 250, -125, "Has Aggro (Good)", THREAT_COLORS.TANK, "AGGRO")
CreateColorSwatch(optionsFrame, 250, -150, "Losing Aggro (Warning)", THREAT_COLORS.TANK, "LOSING_AGGRO")
CreateColorSwatch(optionsFrame, 250, -175, "No Aggro (Bad)", THREAT_COLORS.TANK, "NO_AGGRO")

-- Dimensions Sliders
local heightSlider = CreateFrame("Slider", "GudaPlatesHeightSlider", optionsFrame, "OptionsSliderTemplate")
heightSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -220)
heightSlider:SetWidth(460)
heightSlider:SetMinMaxValues(10, 30)
heightSlider:SetValueStep(1)
local heightText = getglobal(heightSlider:GetName() .. "Text")
heightText:SetFont("Fonts\\FRIZQT__.TTF", 12)
getglobal(heightSlider:GetName() .. "Low"):SetText("10")
getglobal(heightSlider:GetName() .. "High"):SetText("30")
heightSlider:SetScript("OnValueChanged", function()
    healthbarHeight = this:GetValue()
    getglobal(this:GetName() .. "Text"):SetText("Healthbar Height: " .. healthbarHeight)
    SaveSettings()
    for plate, _ in pairs(registry) do
        UpdateNamePlateDimensions(plate)
    end
end)

local widthSlider = CreateFrame("Slider", "GudaPlatesWidthSlider", optionsFrame, "OptionsSliderTemplate")
widthSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -260)
widthSlider:SetWidth(460)
widthSlider:SetMinMaxValues(72, 150)
widthSlider:SetValueStep(1)
local widthText = getglobal(widthSlider:GetName() .. "Text")
widthText:SetFont("Fonts\\FRIZQT__.TTF", 12)
getglobal(widthSlider:GetName() .. "Low"):SetText("72")
getglobal(widthSlider:GetName() .. "High"):SetText("150")
widthSlider:SetScript("OnValueChanged", function()
    healthbarWidth = this:GetValue()
    getglobal(this:GetName() .. "Text"):SetText("Healthbar Width: " .. healthbarWidth)
    SaveSettings()
    for plate, _ in pairs(registry) do
        UpdateNamePlateDimensions(plate)
    end
end)

local healthFontSlider = CreateFrame("Slider", "GudaPlatesHealthFontSlider", optionsFrame, "OptionsSliderTemplate")
healthFontSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -300)
healthFontSlider:SetWidth(460)
healthFontSlider:SetMinMaxValues(8, 20)
healthFontSlider:SetValueStep(1)
local healthFontText = getglobal(healthFontSlider:GetName() .. "Text")
healthFontText:SetFont("Fonts\\FRIZQT__.TTF", 12)
getglobal(healthFontSlider:GetName() .. "Low"):SetText("8")
getglobal(healthFontSlider:GetName() .. "High"):SetText("20")
healthFontSlider:SetScript("OnValueChanged", function()
    healthFontSize = this:GetValue()
    getglobal(this:GetName() .. "Text"):SetText("Health Font Size: " .. healthFontSize)
    SaveSettings()
    for plate, _ in pairs(registry) do
        UpdateNamePlateDimensions(plate)
    end
end)

local levelFontSlider = CreateFrame("Slider", "GudaPlatesLevelFontSlider", optionsFrame, "OptionsSliderTemplate")
levelFontSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -340)
levelFontSlider:SetWidth(460)
levelFontSlider:SetMinMaxValues(8, 20)
levelFontSlider:SetValueStep(1)
local levelFontText = getglobal(levelFontSlider:GetName() .. "Text")
levelFontText:SetFont("Fonts\\FRIZQT__.TTF", 12)
getglobal(levelFontSlider:GetName() .. "Low"):SetText("8")
getglobal(levelFontSlider:GetName() .. "High"):SetText("20")
levelFontSlider:SetScript("OnValueChanged", function()
    levelFontSize = this:GetValue()
    getglobal(this:GetName() .. "Text"):SetText("Level Font Size: " .. levelFontSize)
    SaveSettings()
    for plate, _ in pairs(registry) do
        UpdateNamePlateDimensions(plate)
    end
end)

local nameFontSlider = CreateFrame("Slider", "GudaPlatesNameFontSlider", optionsFrame, "OptionsSliderTemplate")
nameFontSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -380)
nameFontSlider:SetWidth(460)
nameFontSlider:SetMinMaxValues(8, 20)
nameFontSlider:SetValueStep(1)
local nameFontText = getglobal(nameFontSlider:GetName() .. "Text")
nameFontText:SetFont("Fonts\\FRIZQT__.TTF", 12)
getglobal(nameFontSlider:GetName() .. "Low"):SetText("8")
getglobal(nameFontSlider:GetName() .. "High"):SetText("20")
nameFontSlider:SetScript("OnValueChanged", function()
    nameFontSize = this:GetValue()
    getglobal(this:GetName() .. "Text"):SetText("Name Font Size: " .. nameFontSize)
    SaveSettings()
    for plate, _ in pairs(registry) do
        UpdateNamePlateDimensions(plate)
    end
end)

-- Raid Mark Position Checkbox
local raidMarkCheckbox = CreateFrame("CheckButton", "GudaPlatesRaidMarkCheckbox", optionsFrame, "UICheckButtonTemplate")
raidMarkCheckbox:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -420)
local raidMarkLabel = getglobal(raidMarkCheckbox:GetName().."Text")
raidMarkLabel:SetText("Raid Mark on Right")
raidMarkLabel:SetFont("Fonts\\FRIZQT__.TTF", 12)
raidMarkCheckbox:SetScript("OnClick", function()
    if this:GetChecked() == 1 then
        raidIconPosition = "RIGHT"
    else
        raidIconPosition = "LEFT"
    end
    SaveSettings()
    for plate, _ in pairs(registry) do
        UpdateNamePlateDimensions(plate)
    end
end)

-- Swap Name and Debuffs Checkbox
local swapCheckbox = CreateFrame("CheckButton", "GudaPlatesSwapCheckbox", optionsFrame, "UICheckButtonTemplate")
swapCheckbox:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 250, -420)
local swapLabel = getglobal(swapCheckbox:GetName().."Text")
swapLabel:SetText("Swap Name and Debuffs")
swapLabel:SetFont("Fonts\\FRIZQT__.TTF", 12)
swapCheckbox:SetScript("OnClick", function()
    swapNameDebuff = this:GetChecked() == 1
    SaveSettings()
    for plate, _ in pairs(registry) do
        UpdateNamePlateDimensions(plate)
    end
end)

-- Show Debuff Timers Checkbox
local debuffTimerCheckbox = CreateFrame("CheckButton", "GudaPlatesDebuffTimerCheckbox", optionsFrame, "UICheckButtonTemplate")
debuffTimerCheckbox:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -460)
local debuffTimerLabel = getglobal(debuffTimerCheckbox:GetName().."Text")
debuffTimerLabel:SetText("Show Debuff Timers")
debuffTimerLabel:SetFont("Fonts\\FRIZQT__.TTF", 12)
debuffTimerCheckbox:SetScript("OnClick", function()
    showDebuffTimers = this:GetChecked() == 1
    SaveSettings()
    for plate, _ in pairs(registry) do
        UpdateNamePlate(plate)
    end
end)

optionsFrame:SetScript("OnShow", function()
    overlapCheckbox:SetChecked(nameplateOverlap)
    tankCheckbox:SetChecked(playerRole == "TANK")
    heightSlider:SetValue(healthbarHeight)
    getglobal(heightSlider:GetName() .. "Text"):SetText("Healthbar Height: " .. healthbarHeight)
    widthSlider:SetValue(healthbarWidth)
    getglobal(widthSlider:GetName() .. "Text"):SetText("Healthbar Width: " .. healthbarWidth)
    healthFontSlider:SetValue(healthFontSize)
    getglobal(healthFontSlider:GetName() .. "Text"):SetText("Health Font Size: " .. healthFontSize)
    levelFontSlider:SetValue(levelFontSize)
    getglobal(levelFontSlider:GetName() .. "Text"):SetText("Level Font Size: " .. levelFontSize)
    nameFontSlider:SetValue(nameFontSize)
    getglobal(nameFontSlider:GetName() .. "Text"):SetText("Name Font Size: " .. nameFontSize)
    raidMarkCheckbox:SetChecked(raidIconPosition == "RIGHT")
    swapCheckbox:SetChecked(swapNameDebuff)
    debuffTimerCheckbox:SetChecked(showDebuffTimers)
end)

-- Reset to defaults button
local resetButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
resetButton:SetWidth(120)
resetButton:SetHeight(25)
resetButton:SetPoint("BOTTOM", optionsFrame, "BOTTOM", 0, 20)
resetButton:SetText("Reset Defaults")
resetButton:SetScript("OnClick", function()
    playerRole = "DPS"
    THREAT_COLORS.DPS.AGGRO = {0.41, 0.35, 0.76, 1}
    THREAT_COLORS.DPS.HIGH_THREAT = {1.0, 0.6, 0.0, 1}
    THREAT_COLORS.DPS.NO_AGGRO = {0.85, 0.2, 0.2, 1}
    THREAT_COLORS.TANK.AGGRO = {0.41, 0.35, 0.76, 1}
    THREAT_COLORS.TANK.LOSING_AGGRO = {1.0, 0.6, 0.0, 1}
    THREAT_COLORS.TANK.NO_AGGRO = {0.85, 0.2, 0.2, 1}
    healthbarHeight = 14
    healthbarWidth = 115
    healthFontSize = 10
    levelFontSize = 10
    nameFontSize = 10
    raidIconPosition = "LEFT"
    swapNameDebuff = false
    showDebuffTimers = true
    SaveSettings()
    Print("Settings reset to defaults.")
    -- Update all swatches and sliders
    for _, updateFunc in ipairs(swatches) do
        updateFunc()
    end
    tankCheckbox:SetChecked(false)
    heightSlider:SetValue(healthbarHeight)
    getglobal(heightSlider:GetName() .. "Text"):SetText("Healthbar Height: " .. healthbarHeight)
    widthSlider:SetValue(healthbarWidth)
    getglobal(widthSlider:GetName() .. "Text"):SetText("Healthbar Width: " .. healthbarWidth)
    healthFontSlider:SetValue(healthFontSize)
    getglobal(healthFontSlider:GetName() .. "Text"):SetText("Health Font Size: " .. healthFontSize)
    levelFontSlider:SetValue(levelFontSize)
    getglobal(levelFontSlider:GetName() .. "Text"):SetText("Level Font Size: " .. levelFontSize)
    nameFontSlider:SetValue(nameFontSize)
    getglobal(nameFontSlider:GetName() .. "Text"):SetText("Name Font Size: " .. nameFontSize)
    raidMarkCheckbox:SetChecked(false)
    swapCheckbox:SetChecked(false)
    debuffTimerCheckbox:SetChecked(true)
    -- Force refresh of all visible nameplates
    for plate, _ in pairs(registry) do
        if plate:IsShown() then
            UpdateNamePlateDimensions(plate)
            UpdateNamePlate(plate)
        end
    end
end)

-- Load settings on addon load
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("VARIABLES_LOADED")
loadFrame:SetScript("OnEvent", function()
    LoadSettings()
    UpdateMinimapButtonPosition()
    Print("Settings loaded.")

    -- Test the spell database
    if SpellDB then
        Print("✓ Spell database loaded successfully")
        -- Quick test with Rend
        local duration = SpellDB:GetDuration("Rend", 2)
        Print("  Test - Rend Rank 2 -> " .. tostring(duration) .. "s (expected: 12)")
    else
        Print("✗ ERROR: Spell database not loaded!")
    end
end)

Print("Loaded. Use /gp tank or /gp dps to set role.")