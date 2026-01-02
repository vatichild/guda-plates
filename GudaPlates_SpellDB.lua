-- GudaPlates Spell Database
-- Debuff duration tracking with rank support (ShaguPlates-style)

GudaPlates_SpellDB = {}

-- ============================================
-- DEBUFF DURATIONS BY SPELL NAME AND RANK
-- Format: ["Spell Name"] = { [rank] = duration, [0] = default/max }
-- ============================================
GudaPlates_SpellDB.DEBUFFS = {
	-- WARRIOR
	["Rend"] = {[1]=9, [2]=12, [3]=15, [4]=18, [5]=21, [6]=21, [7]=21, [0]=21},
	["Thunder Clap"] = {[1]=10, [2]=14, [3]=18, [4]=22, [5]=26, [6]=30, [0]=30},
	["Sunder Armor"] = {[0]=30},
	["Disarm"] = {[0]=10},
	["Hamstring"] = {[0]=15},
	["Demoralizing Shout"] = {[0]=30},
	["Intimidating Shout"] = {[0]=8},
	["Concussion Blow"] = {[0]=5},
	["Mocking Blow"] = {[0]=6},
	["Piercing Howl"] = {[0]=6},
	["Mortal Strike"] = {[0]=10},
	["Deep Wounds"] = {[0]=12},

	-- ROGUE
	["Cheap Shot"] = {[0]=4},
	["Kidney Shot"] = {[0]=1}, -- +1s per combo point, handled dynamically
	["Sap"] = {[1]=25, [2]=35, [3]=45, [0]=45},
	["Blind"] = {[0]=10},
	["Gouge"] = {[0]=4}, -- +0.5s per talent point
	["Rupture"] = {[0]=8}, -- +2s per combo point, handled dynamically
	["Garrote"] = {[1]=18, [2]=18, [3]=18, [4]=18, [5]=18, [0]=18},
	["Expose Armor"] = {[0]=30},
	["Crippling Poison"] = {[0]=12},
	["Deadly Poison"] = {[0]=12},
	["Deadly Poison II"] = {[0]=12},
	["Deadly Poison III"] = {[0]=12},
	["Deadly Poison IV"] = {[0]=12},
	["Deadly Poison V"] = {[0]=12},
	["Mind-numbing Poison"] = {[0]=14},
	["Mind-numbing Poison II"] = {[0]=14},
	["Mind-numbing Poison III"] = {[0]=14},
	["Wound Poison"] = {[0]=15},
	["Wound Poison II"] = {[0]=15},
	["Wound Poison III"] = {[0]=15},
	["Wound Poison IV"] = {[0]=15},
	["Instant Poison"] = {[0]=3},
	["Instant Poison II"] = {[0]=3},
	["Instant Poison III"] = {[0]=3},
	["Instant Poison IV"] = {[0]=3},
	["Instant Poison V"] = {[0]=3},
	["Instant Poison VI"] = {[0]=3},

	-- MAGE
	["Frost Nova"] = {[1]=8, [2]=8, [3]=8, [4]=8, [0]=8},
	["Polymorph"] = {[1]=20, [2]=30, [3]=40, [4]=50, [0]=50},
	["Polymorph: Pig"] = {[0]=50},
	["Polymorph: Turtle"] = {[0]=50},
	["Polymorph: Cow"] = {[0]=50},
	["Frostbolt"] = {[1]=5, [2]=6, [3]=7, [4]=8, [5]=9, [6]=9, [7]=9, [8]=9, [9]=9, [10]=9, [11]=9, [0]=9},
	["Cone of Cold"] = {[0]=8},
	["Frostbite"] = {[0]=5},
	["Counterspell - Silenced"] = {[0]=4},
	["Winter's Chill"] = {[0]=15},
	["Fireball"] = {[0]=8}, -- DoT component
	["Pyroblast"] = {[0]=12}, -- DoT component
	["Ignite"] = {[0]=4},
	["Fire Vulnerability"] = {[0]=30},

	-- WARLOCK
	["Corruption"] = {[1]=12, [2]=15, [3]=18, [4]=18, [5]=18, [6]=18, [7]=18, [0]=18},
	["Immolate"] = {[1]=15, [2]=15, [3]=15, [4]=15, [5]=15, [6]=15, [7]=15, [8]=15, [0]=15},
	["Fear"] = {[1]=10, [2]=15, [3]=20, [0]=20},
	["Howl of Terror"] = {[1]=10, [2]=15, [0]=15},
	["Death Coil"] = {[0]=3},
	["Curse of Agony"] = {[1]=24, [2]=24, [3]=24, [4]=24, [5]=24, [6]=24, [0]=24},
	["Curse of Weakness"] = {[0]=120},
	["Curse of Recklessness"] = {[0]=120},
	["Curse of Tongues"] = {[0]=30},
	["Curse of the Elements"] = {[0]=300},
	["Curse of Shadow"] = {[0]=300},
	["Curse of Exhaustion"] = {[0]=12},
	["Curse of Doom"] = {[0]=60},
	["Siphon Life"] = {[0]=30},
	["Drain Life"] = {[0]=5},
	["Drain Mana"] = {[0]=5},
	["Drain Soul"] = {[0]=15},
	["Banish"] = {[1]=20, [2]=30, [0]=30},
	["Enslave Demon"] = {[0]=300},
	["Seduction"] = {[0]=15},
	["Shadow Vulnerability"] = {[0]=30},

	-- PRIEST
	["Shadow Word: Pain"] = {[1]=18, [2]=18, [3]=18, [4]=18, [5]=18, [6]=18, [7]=18, [8]=18, [0]=18},
	["Psychic Scream"] = {[1]=8, [2]=8, [3]=8, [4]=8, [0]=8},
	["Mind Flay"] = {[0]=3},
	["Mind Control"] = {[0]=60},
	["Silence"] = {[0]=5},
	["Weakened Soul"] = {[0]=15},
	["Devouring Plague"] = {[0]=24},
	["Vampiric Embrace"] = {[0]=60},
	["Blackout"] = {[0]=3},
	["Mana Burn"] = {[0]=0}, -- instant

	-- HUNTER
	["Serpent Sting"] = {[1]=15, [2]=15, [3]=15, [4]=15, [5]=15, [6]=15, [7]=15, [8]=15, [9]=15, [0]=15},
	["Viper Sting"] = {[1]=8, [2]=8, [3]=8, [4]=8, [0]=8},
	["Scorpid Sting"] = {[0]=20},
	["Concussive Shot"] = {[0]=4},
	["Scatter Shot"] = {[0]=4},
	["Wing Clip"] = {[0]=10},
	["Improved Concussive Shot"] = {[0]=3},
	["Hunter's Mark"] = {[0]=120},
	["Counterattack"] = {[0]=5},
	["Wyvern Sting"] = {[0]=12}, -- sleep, then 12s DoT
	["Freezing Trap Effect"] = {[0]=20},
	["Immolation Trap Effect"] = {[0]=15},
	["Intimidation"] = {[0]=3},
	["Entrapment"] = {[0]=5},

	-- DRUID
	["Moonfire"] = {[1]=9, [2]=12, [3]=12, [4]=12, [5]=12, [6]=12, [7]=12, [8]=12, [9]=12, [10]=12, [0]=12},
	["Entangling Roots"] = {[1]=12, [2]=15, [3]=18, [4]=21, [5]=24, [6]=27, [0]=27},
	["Bash"] = {[1]=2, [2]=3, [3]=4, [0]=4},
	["Faerie Fire"] = {[0]=40},
	["Faerie Fire (Feral)"] = {[0]=40},
	["Rake"] = {[1]=9, [2]=9, [3]=9, [4]=9, [0]=9},
	["Rip"] = {[1]=12, [2]=12, [3]=12, [4]=12, [5]=12, [0]=12},
	["Pounce Bleed"] = {[0]=18},
	["Pounce"] = {[0]=3}, -- stun component
	["Insect Swarm"] = {[0]=12},
	["Hibernate"] = {[1]=20, [2]=30, [3]=40, [0]=40},
	["Feral Charge Effect"] = {[0]=4},

	-- PALADIN
	["Hammer of Justice"] = {[1]=3, [2]=4, [3]=5, [4]=6, [0]=6},
	["Turn Undead"] = {[0]=20},
	["Repentance"] = {[0]=6},
	["Judgement of the Crusader"] = {[0]=10},
	["Judgement of Light"] = {[0]=10},
	["Judgement of Wisdom"] = {[0]=10},
	["Judgement of Justice"] = {[0]=10},

	-- SHAMAN
	["Frost Shock"] = {[1]=8, [2]=8, [3]=8, [4]=8, [0]=8},
	["Earth Shock"] = {[0]=2}, -- interrupt
	["Flame Shock"] = {[1]=12, [2]=12, [3]=12, [4]=12, [5]=12, [6]=12, [0]=12},
	["Earthbind"] = {[0]=5}, -- per pulse
	["Stoneclaw Stun"] = {[0]=3},
	["Stormstrike"] = {[0]=12},
}

-- Dynamic debuffs that scale with combo points
GudaPlates_SpellDB.COMBO_POINT_DEBUFFS = {
	["Kidney Shot"] = true,
	["Rupture"] = true,
}

-- Dynamic debuffs that scale with talents
GudaPlates_SpellDB.DYN_DEBUFFS = {
	["Rupture"] = "Rupture",
	["Kidney Shot"] = "Kidney Shot",
	["Rend"] = "Rend",
	["Shadow Word: Pain"] = "Shadow Word: Pain",
	["Demoralizing Shout"] = "Demoralizing Shout",
	["Frostbolt"] = "Frostbolt",
	["Gouge"] = "Gouge",
}

-- ============================================
-- DEBUFF TRACKING STATE (ShaguPlates-style)
-- objects[unit][unitlevel][effect] = {effect, start, duration}
-- ============================================
GudaPlates_SpellDB.objects = {}
GudaPlates_SpellDB.pending = {}  -- Array: [1]=unit, [2]=unitlevel, [3]=effect, [4]=duration
local lastspell = nil

-- ============================================
-- DURATION LOOKUP FUNCTIONS
-- ============================================

-- Get max rank for a spell
function GudaPlates_SpellDB:GetMaxRank(effect)
	local spellData = self.DEBUFFS[effect]
	if not spellData then return 0 end

	local max = 0
	for id in pairs(spellData) do
		if id > max then max = id end
	end
	return max
end

-- Get duration by spell name and rank (ShaguPlates-style)
function GudaPlates_SpellDB:GetDuration(effect, rank)
	if not effect then return 0 end

	local spellData = self.DEBUFFS[effect]
	if not spellData then return 0 end

	-- Parse rank from string like "Rank 2" if needed
	local rankNum = 0
	if rank then
		if type(rank) == "number" then
			rankNum = rank
		elseif type(rank) == "string" then
			-- Extract number from "Rank X" format
			for num in string.gfind(rank, "(%d+)") do
				rankNum = tonumber(num) or 0
				break
			end
		end
	end

	-- If exact rank not found, use max rank
	if not spellData[rankNum] then
		rankNum = self:GetMaxRank(effect)
	end

	local duration = spellData[rankNum] or spellData[0] or 0

	-- Handle dynamic duration adjustments
	if effect == self.DYN_DEBUFFS["Rupture"] then
		-- Rupture: +2 sec per combo point
		duration = duration + (GetComboPoints("player", "target") or 0) * 2
	elseif effect == self.DYN_DEBUFFS["Kidney Shot"] then
		-- Kidney Shot: +1 sec per combo point
		duration = duration + (GetComboPoints("player", "target") or 0) * 1
	elseif effect == self.DYN_DEBUFFS["Demoralizing Shout"] then
		-- Booming Voice: 10% per talent
		local _,_,_,_,count = GetTalentInfo(2, 1)
		if count and count > 0 then
			duration = duration + (duration / 100 * (count * 10))
		end
	elseif effect == self.DYN_DEBUFFS["Shadow Word: Pain"] then
		-- Improved Shadow Word: Pain: +3s per talent
		local _,_,_,_,count = GetTalentInfo(3, 4)
		if count and count > 0 then
			duration = duration + count * 3
		end
	elseif effect == self.DYN_DEBUFFS["Frostbolt"] then
		-- Permafrost: +1s per talent
		local _,_,_,_,count = GetTalentInfo(3, 7)
		if count and count > 0 then
			duration = duration + count
		end
	elseif effect == self.DYN_DEBUFFS["Gouge"] then
		-- Improved Gouge: +.5s per talent
		local _,_,_,_,count = GetTalentInfo(2, 1)
		if count and count > 0 then
			duration = duration + (count * 0.5)
		end
	end

	return duration
end

-- ============================================
-- PENDING SPELL TRACKING (ShaguPlates-style)
-- ============================================

function GudaPlates_SpellDB:AddPending(unit, unitlevel, effect, duration)
	DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[SpellDB]|r AddPending called: unit=" .. tostring(unit) .. " effect=" .. tostring(effect) .. " duration=" .. tostring(duration))
	if not unit or not effect then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SpellDB]|r AddPending REJECTED: unit or effect is nil")
		return
	end
	if not self.DEBUFFS[effect] then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SpellDB]|r AddPending REJECTED: effect '" .. tostring(effect) .. "' not in DEBUFFS table")
		return
	end
	if duration <= 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SpellDB]|r AddPending REJECTED: duration <= 0")
		return
	end
	if self.pending[3] then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SpellDB]|r AddPending REJECTED: already have pending spell: " .. tostring(self.pending[3]))
		return
	end

	-- Try to get GUID for unique identification (SuperWoW)
	local unitKey = unit
	if UnitGUID and UnitExists("target") and UnitName("target") == unit then
		local guid = UnitGUID("target")
		if guid then
			unitKey = guid
			DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[SpellDB]|r Using GUID as key: " .. guid)
		end
	end

	self.pending[1] = unitKey
	self.pending[2] = unitlevel or 0
	self.pending[3] = effect
	self.pending[4] = duration
	self.pending[5] = unit  -- Store original name for fallback lookups
	DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[SpellDB]|r AddPending SUCCESS: " .. effect .. " on " .. unitKey .. " for " .. duration .. "s")
end

function GudaPlates_SpellDB:RemovePending()
	self.pending[1] = nil
	self.pending[2] = nil
	self.pending[3] = nil
	self.pending[4] = nil
	self.pending[5] = nil
end

function GudaPlates_SpellDB:PersistPending(effect)
	DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[SpellDB]|r PersistPending called: effect=" .. tostring(effect) .. " pending[3]=" .. tostring(self.pending[3]))
	if not self.pending[3] then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SpellDB]|r PersistPending: no pending spell")
		return
	end

	if self.pending[3] == effect or (effect == nil and self.pending[3]) then
		DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[SpellDB]|r PersistPending: calling AddEffect for " .. tostring(self.pending[3]))
		-- Store by GUID (pending[1]) for accurate per-mob tracking
		self:AddEffect(self.pending[1], self.pending[2], self.pending[3], self.pending[4])
		-- Also store by name (pending[5]) as fallback for non-SuperWoW lookups
		if self.pending[5] and self.pending[5] ~= self.pending[1] then
			self:AddEffect(self.pending[5], self.pending[2], self.pending[3], self.pending[4])
		end
	end

	self:RemovePending()
end

-- ============================================
-- EFFECT TRACKING (ShaguPlates-style)
-- ============================================

function GudaPlates_SpellDB:RevertLastAction()
	if lastspell and lastspell.start_old then
		lastspell.start = lastspell.start_old
		lastspell.start_old = nil
	end
end

function GudaPlates_SpellDB:AddEffect(unit, unitlevel, effect, duration)
	DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[SpellDB]|r AddEffect called: unit=" .. tostring(unit) .. " level=" .. tostring(unitlevel) .. " effect=" .. tostring(effect) .. " duration=" .. tostring(duration))
	if not unit or not effect then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SpellDB]|r AddEffect REJECTED: unit or effect is nil")
		return
	end
	unitlevel = unitlevel or 0

	-- Initialize tables
	if not self.objects[unit] then self.objects[unit] = {} end
	if not self.objects[unit][unitlevel] then self.objects[unit][unitlevel] = {} end
	if not self.objects[unit][unitlevel][effect] then self.objects[unit][unitlevel][effect] = {} end

	-- Save current effect as lastspell for potential revert
	lastspell = self.objects[unit][unitlevel][effect]

	self.objects[unit][unitlevel][effect].effect = effect
	self.objects[unit][unitlevel][effect].start_old = self.objects[unit][unitlevel][effect].start
	self.objects[unit][unitlevel][effect].start = GetTime()
	self.objects[unit][unitlevel][effect].duration = duration or self:GetDuration(effect)
	DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[SpellDB]|r AddEffect SUCCESS: objects[" .. unit .. "][" .. unitlevel .. "][" .. effect .. "] = start:" .. self.objects[unit][unitlevel][effect].start .. " duration:" .. self.objects[unit][unitlevel][effect].duration)
end

function GudaPlates_SpellDB:UpdateDuration(unit, unitlevel, effect, duration)
	if not unit or not effect or not duration then return end
	unitlevel = unitlevel or 0

	if self.objects[unit] and self.objects[unit][unitlevel] and self.objects[unit][unitlevel][effect] then
		self.objects[unit][unitlevel][effect].duration = duration
	end
end

-- ============================================
-- UNITDEBUFF WRAPPER (ShaguPlates-style)
-- Returns: effect, rank, texture, stacks, dtype, duration, timeleft
-- ============================================
function GudaPlates_SpellDB:UnitDebuff(unit, id)
	local unitname = UnitName(unit)
	local unitlevel = UnitLevel(unit) or 0
	local texture, stacks, dtype = UnitDebuff(unit, id)
	local duration, timeleft = nil, -1
	local rank = nil
	local effect = nil

	if texture then
		-- Get spell name via tooltip scanning
		-- Try the unit first, but if it's a GUID and that fails, try "target" if it matches
		effect = self:ScanDebuff(unit, id)

		-- If scanning failed and this unit is the target, try scanning "target" instead
		if (not effect or effect == "") and UnitName("target") == unitname then
			effect = self:ScanDebuff("target", id)
		end

		effect = effect or ""
	end

	-- Check tracked debuffs with level
	if effect and effect ~= "" and self.objects[unitname] then
		local data = nil

		-- Try exact level first
		if self.objects[unitname][unitlevel] and self.objects[unitname][unitlevel][effect] then
			data = self.objects[unitname][unitlevel][effect]
		-- Fallback: check level 0
		elseif self.objects[unitname][0] and self.objects[unitname][0][effect] then
			data = self.objects[unitname][0][effect]
		-- Fallback: check any level for this unit
		else
			for lvl, effects in pairs(self.objects[unitname]) do
				if effects[effect] then
					data = effects[effect]
					break
				end
			end
		end

		if data and data.start and data.duration then
			-- Clean up expired
			if data.duration + data.start < GetTime() then
				-- Don't remove here, let it be cleaned up elsewhere
				data = nil
			else
				duration = data.duration
				timeleft = duration + data.start - GetTime()
			end
		end
	end

	-- Fallback: if we have effect name but no tracked data, get duration from DB
	-- Don't set timeleft - let the caller handle untracked debuffs with their own timer cache
	if effect and effect ~= "" and (not duration or duration <= 0) then
		local dbDuration = self:GetDuration(effect, 0)
		if dbDuration and dbDuration > 0 then
			duration = dbDuration
			-- timeleft stays at -1, signaling caller to use their own timer cache
		end
	end

	return effect, rank, texture, stacks, dtype, duration, timeleft
end

-- ============================================
-- TOOLTIP SCANNER
-- ============================================
GudaPlates_SpellDB.scanner = nil
GudaPlates_SpellDB.textureToSpell = {}  -- Cache: texture path -> spell name

function GudaPlates_SpellDB:InitScanner()
	if self.scanner then return end

	-- Create hidden tooltip for scanning
	self.scanner = CreateFrame("GameTooltip", "GudaPlatesDebuffScanner", UIParent, "GameTooltipTemplate")
	self.scanner:SetOwner(UIParent, "ANCHOR_NONE")
end

-- Check if a string looks like a SuperWoW GUID
local function IsGUID(unit)
	if not unit or type(unit) ~= "string" then return false end
	return string.sub(unit, 1, 2) == "0x"
end

function GudaPlates_SpellDB:ScanDebuff(unit, index)
	if not self.scanner then self:InitScanner() end

	-- Get the debuff texture first for cache lookup
	local texture = UnitDebuff(unit, index)

	-- Try texture cache first (fastest, works with GUIDs)
	if texture and self.textureToSpell and self.textureToSpell[texture] then
		DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[ScanDebuff]|r Cache hit: " .. texture .. " -> " .. self.textureToSpell[texture])
		return self.textureToSpell[texture]
	end

	-- SetUnitDebuff doesn't work with GUID strings, only standard unit IDs
	-- Convert GUID to "target" if it matches the current target
	local scanUnit = unit
	if IsGUID(unit) then
		-- Try to match with target
		if UnitExists("target") then
			local targetGUID = UnitGUID and UnitGUID("target")
			if targetGUID and targetGUID == unit then
				scanUnit = "target"
			else
				-- Can't scan this GUID, no cache hit
				DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[ScanDebuff]|r GUID mismatch, no cache for: " .. tostring(texture))
				return nil
			end
		else
			DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[ScanDebuff]|r No target, no cache for: " .. tostring(texture))
			return nil
		end
	end

	self.scanner:ClearLines()
	self.scanner:SetUnitDebuff(scanUnit, index)

	local textLeft = getglobal("GudaPlatesDebuffScannerTextLeft1")
	if textLeft then
		local effect = textLeft:GetText()
		DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[ScanDebuff]|r Tooltip: " .. tostring(effect))
		-- Cache texture -> spell mapping for future lookups
		if effect and effect ~= "" and texture then
			self.textureToSpell[texture] = effect
		end
		return effect
	end

	return nil
end

-- Get spell name and rank from action bar slot by matching texture to spellbook
function GudaPlates_SpellDB:ScanAction(slot)
	local actionTexture = GetActionTexture(slot)
	if not actionTexture then return nil, nil end

	-- Search through spellbook to find matching texture
	local bookTypes = { "spell", "BOOKTYPE_SPELL" }

	-- Get number of spells
	local i = 1
	while true do
		local spellName, spellRank = GetSpellName(i, "spell")
		if not spellName then break end

		local spellTexture = GetSpellTexture(i, "spell")
		if spellTexture and spellTexture == actionTexture then
			DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[ScanAction]|r Found spell: " .. spellName .. " (" .. tostring(spellRank) .. ") texture match!")
			return spellName, spellRank
		end
		i = i + 1
	end

	-- If not found in spellbook, try tooltip as fallback
	if not self.scanner then self:InitScanner() end
	self.scanner:ClearLines()
	self.scanner:SetAction(slot)

	local textLeft = getglobal("GudaPlatesDebuffScannerTextLeft1")
	local textRight = getglobal("GudaPlatesDebuffScannerTextRight1")

	local effect = textLeft and textLeft:GetText() or nil
	local rank = textRight and textRight:GetText() or nil

	DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[ScanAction]|r Fallback tooltip: effect='" .. tostring(effect) .. "' rank='" .. tostring(rank) .. "'")
	return effect, rank
end

-- ============================================
-- INITIALIZATION
-- ============================================
_G["GudaPlates_SpellDB"] = GudaPlates_SpellDB

if DEFAULT_CHAT_FRAME then
	local count = 0
	for _ in pairs(GudaPlates_SpellDB.DEBUFFS) do count = count + 1 end
	DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[GudaPlates]|r SpellDB loaded with " .. count .. " spells")
end
