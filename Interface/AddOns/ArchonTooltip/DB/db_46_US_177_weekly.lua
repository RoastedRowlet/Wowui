local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Shaman-Restoration','DeathKnight-Unholy','Mage-Frost','Warrior-Fury','Druid-Balance','Evoker-Augmentation','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','Unknown-Unknown','Druid-Feral','Paladin-Protection','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Warrior-Arms','Priest-Holy','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Blood','Warlock-Destruction','Warlock-Demonology','DeathKnight-Frost','Shaman-Elemental','Monk-Mistweaver','Monk-Brewmaster','Hunter-Survival','Rogue-Assassination','Rogue-Outlaw','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Druid-Guardian','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Discipline',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abelas:BAAALgADCgYJFwAAAA==.Abracadaxis:BAAALgADCggJCAAAAA==.',
Ad='Adallyn:BAAALgADCgYJCgAAAA==.Adzen:BAAALgAECgEJAQAAAA==.Adêrna:BAABLgAECn8lAAIBAAgJghw+GwAcAgABAAgJghw+GwAcAgAAAA==.',
Af='Affliction:BAAALgADCgUJBQAAAA==.',
Ag='Agba:BAABLgAFFH8FAAICAAMJ/wSGeACAAAACAAMJ/wSGeACAAAAAAA==.',
Ah='Ahktari:BAAALgADCgcJBwAAAA==.',
Al='Alaidan:BAAALgAECgcJCwAAAA==.Alanus:BAABLgAECn8nAAIDAAgJihHYVACeAQADAAgJihHYVACeAQAAAA==.Alarion:BAAALgAECgMJBgAAAA==.Alavia:BAABLgAECn8wAAIEAAgJQxjaGgDJAQAEAAgJQxjaGgDJAQAAAA==.Alinäs:BAABLgAECn8fAAIDAAgJ+w/rXgCEAQADAAgJ+w/rXgCEAQAAAA==.Aliën:BAAALgADCgEJAQAAAA==.Alliumoo:BAABLgAECn8XAAIFAAYJwQkBRwASAQAFAAYJwQkBRwASAQAAAA==.Altana:BAAALgAECggJEwABLgAECggJHwAGAL0eAA==.Alydrus:BAAALgAECgYJEgAAAA==.Alíen:BAAALgADCgQJBAAAAA==.',
An='Anberlinean:BAABLgAECn8WAAIHAAYJ5gdvqQDdAAAHAAYJ5gdvqQDdAAAAAA==.Angryelf:BAAALgAECgEJAQAAAA==.Ankles:BAAALgADCgcJBwABLgAFFAQJDgAIAB8RAA==.Annahe:BAABLgAECn8UAAIJAAgJUxu5EQDnAQAJAAgJUxu5EQDnAQAAAA==.Annale:BAAALgAECgQJBQABLgAECggJFAAJAFMbAA==.Annatara:BAAALgAECgIJAgAAAA==.Anub:BAAALgADCgYJBgAAAA==.Anzala:BAAALgADCgIJAgAAAA==.',
Ao='Aoba:BAAALgAECgYJCwAAAA==.',
Ar='Arataeus:BAAALgAECgQJCgAAAA==.Areliss:BAAALgAECgUJBQAAAA==.Armsmaster:BAABLgAECn8lAAICAAgJLx/9XADbAQACAAgJLx/9XADbAQAAAA==.Artemistha:BAAALgADCgYJDAAAAA==.',
As='Asalynn:BAAALgADCgEJAQAAAA==.',
Av='Avalina:BAAALgAECgEJAQAAAA==.Avengharambe:BAAALgADCgcJBwAAAA==.Averan:BAAALgAECgYJEQAAAA==.Averybug:BAAALgAECgEJAQAAAA==.',
Ba='Backbeamz:BAAALgAECgYJCQAAAA==.Backspace:BAAALgADCgYJBgAAAA==.Badgër:BAAALgADCgEJAQAAAA==.Baey:BAAALgADCgMJAwABLgAECggJJQADABwfAA==.Balduun:BAAALgAECgEJAQAAAA==.Barelycastin:BAAALgAECgEJAQAAAA==.Bashdadargon:BAAALgAECgEJAQABLgAECgQJBQAKAAAAAA==.Bashoomba:BAAALgAECgQJBQAAAA==.',
Be='Bear:BAAALgAECggJDgAAAA==.Bearnaked:BAAALgADCgIJAgAAAA==.Belgarathh:BAAALgAFFAIJAgAAAA==.Bellíon:BAAALgAECgMJBgAAAA==.',
Bi='Bird:BAAALgADCgEJAQAAAA==.Bixee:BAAALgAECgUJCQAAAA==.',
Bl='Blacat:BAABLgAECn8nAAMLAAgJXB3bBABVAgALAAgJXB3bBABVAgAFAAIJUAM/eABEAAAAAA==.Bleen:BAAALgAECgUJDAAAAA==.Blitzcomets:BAAALgADCgcJCwAAAA==.Bloodbenders:BAAALgADCgEJAQAAAA==.Blueday:BAAALgAECgEJAQAAAA==.',
Bo='Bogeyman:BAABLgAECn8sAAIMAAgJRyD9BABeAgAMAAgJRyD9BABeAgAAAA==.Boondoks:BAABLgAECn8ZAAIIAAcJTR2YFQAUAgAIAAcJTR2YFQAUAgABLgAECggJNgABAOcfAA==.Borda:BAAALgAECgIJAgAAAA==.Bowrider:BAAALgAECgYJBwAAAA==.',
Br='Breer:BAAALgADCgkJCQAAAA==.Brondeadeye:BAAALgAECgUJBwAAAA==.Brunore:BAAALgAECgYJDAAAAA==.',
Bu='Bubbajüdd:BAAALgADCgEJAQAAAA==.',
Ca='Caidi:BAAALgADCgIJAgAAAA==.Caledur:BAAALgAECgYJDAAAAA==.Caratdeullie:BAAALgADCgEJAQAAAA==.Careblair:BAAALgADCgEJAQAAAA==.',
Ch='Chakrah:BAABLgAECn8YAAINAAcJ/gnZNQA9AQANAAcJ/gnZNQA9AQAAAA==.Challan:BAABLgAFFH8GAAIOAAMJtAKiTQCqAAAOAAMJtAKiTQCqAAAAAA==.Chloe:BAABLgAECn8XAAIPAAkJ9AF9sAAsAAAPAAkJ9AF9sAAsAAAAAA==.Chrno:BAAALgAECgcJEwAAAA==.Chunkymonkey:BAAALgADCgYJBgABLgAFFAMJBwADANIJAA==.',
Cl='Clutcha:BAABLgAECn8cAAIQAAYJKh3XGwBcAQAQAAYJKh3XGwBcAQAAAA==.Clutchcross:BAAALgAECgQJBgABLgAECgYJHAAQACodAA==.Clutchplate:BAABLgAECn8bAAMRAAcJFBPOGAAnAQARAAcJFBPOGAAnAQASAAEJWgb9VwAlAAAAAA==.Clûtch:BAACLgAFFH8KAAICAAQJSxcsNQD2AAACAAQJSxcsNQD2AAAuAAQKfx8AAgIACAlxIO42AFsCAAIACAlxIO42AFsCAAAA.',
Co='Codenameblue:BAAALgADCgEJAQAAAA==.Coldphoenix:BAAALgADCgkJCQAAAA==.Coog:BAAALgADCgEJAQAAAA==.Corynthe:BAABLgAECn8oAAITAAgJSx0wDwAsAgATAAgJSx0wDwAsAgAAAA==.',
Cr='Crickie:BAAALgAECgQJCQAAAA==.Crovaxis:BAABLgAECn8nAAMUAAgJXSKgBQCyAQAUAAcJ8SKgBQCyAQAVAAEJ4B5HwwBPAAAAAA==.',
Cu='Cursecackler:BAAALgADCgYJBgAAAA==.',
Cy='Cynda:BAAALgADCgMJAwAAAA==.Cyndestine:BAAALgADCgYJBgAAAA==.Cyzarius:BAAALgAECgEJAQAAAA==.',
Da='Daddychill:BAAALgAECggJDgAAAA==.Daedrìc:BAAALgAECgMJAwAAAA==.Damekka:BAAALgAECgQJBQAAAA==.Danazer:BAAALgAECgYJBgAAAA==.Danoe:BAAALgADCggJCAAAAA==.Darktalyn:BAABLgAECn8sAAMTAAgJFhaMEQANAgATAAgJFhaMEQANAgANAAYJxQ4zMwBOAQAAAA==.',
De='Deadpaws:BAAALgADCgMJAwAAAA==.Deathbinger:BAAALgADCgEJAQAAAA==.Deathgriped:BAABLgAECn8mAAIWAAcJ+xR/FgBAAQAWAAcJ+xR/FgBAAQAAAA==.Deathhawkzz:BAACLgAFFH8FAAMXAAMJLgOQCAC3AAAXAAMJLgOQCAC3AAAYAAEJZQEMmAA5AAAuAAQKfxkAAxcABwn6FeYLAAQCABcABwn6FeYLAAQCABgAAwnFExGgAMAAAAAA.Deathphoenix:BAAALgADCgcJBwAAAA==.Deathslock:BAAALgADCgQJBAAAAA==.Deekura:BAABLgAECn8XAAMCAAYJkgdUnQDmAAACAAYJkgdUnQDmAAAZAAIJlQFeIQA2AAAAAA==.Deladorana:BAAALgADCgUJBQAAAA==.Dellma:BAAALgADCgYJDAAAAA==.Delusion:BAAALgAECgQJBwAAAA==.Demonpapi:BAAALgAECgYJBwAAAA==.Demoryx:BAEALgAECgQJBAABLgAECggJIQAaAF0dAA==.Denjack:BAAALgAECgQJCQAAAA==.Dewayne:BAAALgAECgUJBQAAAA==.',
Dh='Dhadzen:BAAALgAECgQJCwAAAA==.',
Di='Dionan:BAABLgAECn8nAAIHAAgJaROHVACFAQAHAAgJaROHVACFAQAAAA==.Dirtysouth:BAAALgAECgEJAQABLgAFFAQJDAAVAHIbAA==.',
Do='Docs:BAABLgAECn8jAAIIAAgJSBZEGAD6AQAIAAgJSBZEGAD6AQAAAA==.Doks:BAABLgAECn82AAIBAAgJ5x+KDACpAgABAAgJ5x+KDACpAgAAAA==.Dontpanic:BAABLgAECn8YAAIbAAcJqhvZEgAcAgAbAAcJqhvZEgAcAgABLgAFFAQJDgAIAB8RAA==.Doomsnake:BAAALgADCgMJAwABLgADCgEJAQAKAAAAAA==.Dove:BAAALgADCgYJBgAAAA==.',
Dr='Dragomalfoy:BAAALgADCgQJBAAAAA==.Dragondznuts:BAAALgAFFAQJBAAAAA==.Dragõn:BAAALgAECgQJBwAAAA==.Drexeos:BAAALgADCgcJBwAAAA==.Drinker:BAAALgADCgUJBQAAAA==.',
Du='Dunir:BAAALgAECgEJAQAAAA==.',
Ea='Ealara:BAABLgAECn8cAAIVAAcJ4AknYgAnAQAVAAcJ4AknYgAnAQAAAA==.',
Ed='Edran:BAAALgADCgcJFQAAAA==.',
Ei='Eifel:BAAALgAECgQJBAABLgAECgkJGwAHABceAA==.Eimin:BAAALgADCgYJCgAAAA==.',
El='Eldarion:BAAALgAECgMJAgAAAA==.Elfmonk:BAAALgAECgEJAQAAAA==.Ellipses:BAAALgADCgYJBgABLgAECggJEwAKAAAAAA==.',
Em='Emeraldz:BAABLgAECn8fAAIJAAcJXxonGQCZAQAJAAcJXxonGQCZAQAAAA==.',
En='Eneru:BAAALgADCgYJCAABLgAECggJHwAIAJ0XAA==.',
Er='Erebrethil:BAAALgAECgYJDwAAAA==.',
Es='Espe:BAABLgAECn8bAAIcAAgJPhVfGQCfAQAcAAgJPhVfGQCfAQAAAA==.',
Eu='Eucalyptia:BAAALgADCgQJBAAAAA==.',
Ev='Evenin:BAAALgADCgIJAgAAAA==.',
Ex='Exoncantotem:BAAALgADCgQJBAAAAA==.',
Fa='Faenor:BAAALgAECgQJCgAAAA==.Faynor:BAABLgAECn8pAAIcAAgJqhr7EAD2AQAcAAgJqhr7EAD2AQAAAA==.',
Fe='Feloni:BAAALgAECgMJAwAAAA==.',
Fi='Finalone:BAAALgADCgYJBwAAAA==.Firêfly:BAAALgAECgIJAwAAAA==.',
Fk='Fknsteve:BAAALgADCgYJBgAAAA==.',
Fl='Flaptix:BAAALgAECgMJAwAAAA==.Flipingflerp:BAAALgAECgcJEQAAAA==.Flloran:BAAALgAECgQJBwAAAA==.Floragoth:BAAALgAECgEJAQAAAA==.Flowers:BAAALgADCgkJCQAAAA==.Fluffboi:BAABLgAECn8dAAIJAAcJ+gh5MgDtAAAJAAcJ+gh5MgDtAAAAAA==.',
Fo='Foxyblue:BAAALgAECgYJDgAAAA==.',
Fr='Fraggle:BAACLgAFFH8OAAMIAAQJHxFQGQAOAQAIAAQJHxFQGQAOAQAHAAMJUwnaRgDXAAAuAAQKfyIAAwgACAl+IBsLAMcCAAgACAl+IBsLAMcCAAcAAQkwIQIAAVwAAAAA.Freefromfate:BAAALgAECgEJAQAAAA==.Frogchi:BAAALgAECgQJCQAAAA==.Frostbité:BAABLgAECn8lAAIMAAkJvRqzBABnAgAMAAkJvRqzBABnAgAAAA==.Fruit:BAAALgAECgQJCQAAAA==.',
Fu='Fuknak:BAAALgAECgIJAwAAAA==.Fumikiko:BAAALgADCgIJAgABLgAECggJHwAGAL0eAA==.Furrykarg:BAAALgAECgEJAQABLgAECgQJBgAKAAAAAA==.',
['Fà']='Fàynor:BAAALgAECgQJBQABLgAECggJKQAcAKoaAA==.',
['Fú']='Fúzzy:BAAALgADCgEJAgAAAA==.',
Ga='Gakkle:BAAALgAECggJEAAAAA==.Galadralvia:BAAALgAECgcJEQAAAA==.Gali:BAAALgAECgUJDAAAAA==.',
Ge='Gearsofbob:BAAALgAFFAIJBAAAAA==.Gekkle:BAAALgADCgUJBQAAAA==.',
Gh='Ghorn:BAAALgAECgEJAQAAAA==.Ghoulei:BAABLgAECn8lAAICAAgJdR8lKQAWAgACAAgJdR8lKQAWAgAAAA==.',
Gl='Glaistiguain:BAAALgAECgYJCwABLgAECggJJQACAC8fAA==.Glenheals:BAAALgADCgkJEgAAAA==.Glifin:BAAALgAECgQJCQAAAA==.Gloomstalkin:BAABLgAECn8uAAIdAAgJYBbiEgDOAQAdAAgJYBbiEgDOAQAAAA==.',
Gn='Gnøsis:BAAALgADCggJEQAAAA==.',
Go='Goldìelocks:BAAALgAECgQJBAAAAA==.Gom:BAAALgAECgIJAgAAAA==.Gomdrog:BAAALgAECgEJAQAAAA==.',
Gr='Gr:BAABLgAECn8lAAIeAAcJVA0sCgBQAQAeAAcJVA0sCgBQAQAAAA==.Grannecs:BAAALgADCgEJAQAAAA==.Grizzledpaw:BAAALgAECgQJCgAAAA==.Gryffs:BAABLgAECn81AAMRAAkJuSC6AgDiAgARAAkJuSC6AgDiAgASAAEJ1Ao7UgAuAAAAAA==.',
Gu='Gum:BAAALgADCgcJBwABLgAECggJLAAMAEcgAA==.Gutts:BAABLgAECn8kAAQRAAgJrSIDBQCLAgARAAgJrSIDBQCLAgASAAcJ3BIvGwAoAQAEAAQJ0Q7wfQDFAAAAAA==.',
Ha='Hadron:BAAALgAECgEJAQAAAA==.Halomea:BAAALgADCgQJBAAAAA==.Hanukira:BAAALgADCgUJBQAAAA==.Happi:BAAALgAECgYJCQABLgAFFAYJEwAOAEsXAA==.Harald:BAAALgAECgcJEAAAAA==.Harkle:BAAALgADCgcJDQAAAA==.Haruun:BAAALgAECgEJAQAAAA==.',
He='Hesmydaddy:BAABLgAECn8pAAITAAgJWQm0KAA5AQATAAgJWQm0KAA5AQAAAA==.',
Ho='Honestie:BAAALgAECgEJAQAAAA==.Hongling:BAAALgADCgYJBgABLgAECggJHwAGAL0eAA==.Honêy:BAEALgAECgEJAQABLgAECggJIQAaAF0dAA==.Hotdogstand:BAACLgAFFH8TAAIQAAUJECVGBQCqAQAQAAUJECVGBQCqAQAuAAQKfzEABBAACQlwJSYBAEIDABAACQlwJSYBAEIDAB4ABAmEIYELAHMBAB8AAQkrIocUAFwAAAAA.',
Hu='Huzzaah:BAAALgAECgcJEwABLgAFFAQJDgAIAB8RAA==.',
Hy='Hyperius:BAAALgADCgIJAgAAAA==.',
['Hö']='Höneÿdew:BAABLgAECn8ZAAIVAAgJ8Bg2LAADAgAVAAgJ8Bg2LAADAgAAAA==.',
Ic='Icemann:BAAALgAECgEJAgAAAA==.',
Il='Ilidrayssel:BAABLgAECn8aAAIUAAcJbQMDGACYAAAUAAcJbQMDGACYAAAAAA==.Illida:BAAALgAECgMJCAAAAA==.Illidad:BAAALgAECgQJBAAAAA==.Ilyssara:BAAALgADCgYJBgABLgAECggJEwAKAAAAAA==.',
Im='Imhappy:BAAALgAECgIJAwABLgAFFAYJEwAOAEsXAA==.Imherdaddy:BAAALgADCgYJCAABLgAECggJLgAdAGAWAA==.',
In='Indracus:BAAALgAECgEJAQAAAA==.Innervape:BAAALgADCgMJAwAAAA==.',
Ja='Jacorict:BAAALgAECgYJDwAAAA==.Jagga:BAAALgADCgMJAwAAAA==.Jarrack:BAABLgAECn8iAAIDAAgJgRhFOgDwAQADAAgJgRhFOgDwAQAAAA==.',
Je='Jellyhawk:BAAALgAECgEJAQAAAA==.Jessicae:BAAALgAECgcJDgAAAA==.',
Jo='Josephd:BAAALgADCgEJAQABLgAECggJLQAFAAIWAA==.Josephedd:BAABLgAECn8tAAIFAAgJAhbZGACuAQAFAAgJAhbZGACuAQAAAA==.',
Ju='Jukk:BAABLgAECn8XAAIDAAYJzQcfqQDyAAADAAYJzQcfqQDyAAABLgAECggJEAAKAAAAAA==.Junazeena:BAABLgAECn8ZAAIaAAcJHwRjSQC4AAAaAAcJHwRjSQC4AAAAAA==.',
Ka='Kaji:BAABLgAECn8bAAIbAAYJ5RCXLQA6AQAbAAYJ5RCXLQA6AQAAAA==.Kalistus:BAAALgAECgEJAQAAAA==.Kargfu:BAAALgAECgQJBgAAAA==.Karolat:BAAALgAECgUJBgAAAA==.Kayfabe:BAABLgAECn8ZAAIDAAgJ4gNz+gAGAQADAAgJ4gNz+gAGAQAAAA==.Kazz:BAAALgAECgQJBAAAAA==.',
Ke='Keishilda:BAAALgAECgUJEAAAAA==.Keladria:BAAALgAECgMJBgAAAA==.Kelirra:BAAALgADCgQJCAAAAA==.Kelvyren:BAAALgADCgEJAQAAAA==.Kenel:BAABLgAECn8mAAMPAAgJGxcpHwAHAgAPAAgJGxcpHwAHAgAFAAUJcRGyOQDUAAAAAA==.Kerea:BAABLgAECn8pAAIPAAgJ2wdYVAD6AAAPAAgJ2wdYVAD6AAAAAA==.',
Ki='Kicken:BAABLgAECn8dAAMYAAYJwBu2UABsAQAYAAUJ1Bm2UABsAQAXAAMJihkmPwC4AAAAAA==.Kitschy:BAAALgADCgEJAQAAAA==.Kittyperry:BAAALgAECgMJAwAAAA==.',
Kn='Knome:BAABLgAECn8lAAIDAAgJHB94JwA8AgADAAgJHB94JwA8AgAAAA==.',
Ko='Koana:BAAALgAECgQJBwAAAA==.Kororin:BAAALgAECgMJAwAAAA==.Korthelan:BAABLgAECn8lAAIOAAgJZRDrTwBIAQAOAAgJZRDrTwBIAQAAAA==.Kothara:BAABLgAECn8dAAIVAAYJkBM1QgCnAQAVAAYJkBM1QgCnAQAAAA==.Kotongar:BAAALgADCgMJAwAAAA==.',
Kr='Kreeoo:BAAALgAECgIJAgAAAA==.Krimzin:BAACLgAFFH8MAAIVAAQJchsHGwBFAQAVAAQJchsHGwBFAQAuAAQKfx4AAxUACAnfIZQhADwCABUACAnfIZQhADwCAB0AAgkaELxFAEEAAAAA.Krystine:BAAALgAECgQJCQAAAA==.',
Ks='Kserasera:BAAALgAECggJEQAAAA==.',
Ku='Kuball:BAAALgAECgYJCQABLgAECggJJAARAK0iAA==.Kukuruku:BAAALgAECgIJAwAAAA==.',
['Kî']='Kîllara:BAABLgAECn8nAAIBAAkJUhU+HQAMAgABAAkJUhU+HQAMAgAAAA==.',
La='Labialicious:BAAALgAECgEJAgAAAA==.Lanfeår:BAABLgAECn8VAAICAAYJCwhboADhAAACAAYJCwhboADhAAAAAA==.Lanskies:BAAALgAECggJDQAAAA==.',
Le='Leafymeds:BAAALgAECgYJEAABLgAECgkJLwABANwTAA==.Lebronjames:BAAALgAECgQJBAAAAA==.Leiluna:BAAALgADCgkJEQAAAA==.Letheos:BAAALgAECgYJBgAAAA==.',
Li='Libertinne:BAABLgAECn8cAAIEAAgJMxdFIwCNAQAEAAgJMxdFIwCNAQAAAA==.Librarte:BAABLgAECn8fAAIHAAgJKwyXdwA1AQAHAAgJKwyXdwA1AQAAAA==.Ligmanuts:BAAALgAECgIJBAAAAA==.Lillytrae:BAAALgAECgEJAQAAAA==.Lilmeds:BAAALgAECggJCAABLgAECgkJLwABANwTAA==.Listie:BAAALgADCgQJBAABLgAECgQJBAAKAAAAAA==.Litty:BAABLgAECn8gAAIDAAcJzCTeHgBqAgADAAcJzCTeHgBqAgAAAA==.Lizrdkng:BAAALgADCgMJBgAAAA==.',
Lo='Locktärd:BAACLgAFFH8MAAQgAAQJiBu3AQBKAQAgAAQJiBu3AQBKAQAYAAIJShYXMwCtAAAXAAIJogaEDgCXAAAuAAQKfyoABCAACAmIH6oCAJACACAACAk+H6oCAJACABgACAktGRZCAAYCABcAAgkLHIJGAJwAAAAA.Lohken:BAAALgAECgMJCQAAAA==.Lox:BAABLgAECn8lAAIXAAgJBxSWBwCKAQAXAAgJBxSWBwCKAQAAAA==.',
Lu='Lucieb:BAAALgAECgEJAQAAAA==.',
Ly='Lydirn:BAABLgAECn8dAAQHAAgJnRzvPADKAQAHAAcJmh3vPADKAQAIAAQJzRXwQADsAAAMAAEJrRZdNwA9AAAAAA==.Lyofel:BAAALgAECgYJDwAAAA==.Lyonel:BAAALgADCggJCAAAAA==.',
['Lí']='Lítterbox:BAAALgAECgEJAQAAAA==.',
Ma='Magedzen:BAAALgAECgEJAQAAAA==.Magicguy:BAABLgAECn8VAAIDAAgJngwQYgB8AQADAAgJngwQYgB8AQAAAA==.Mahariel:BAAALgAECggJDQAAAA==.Mahdy:BAABLgAECn8zAAIHAAgJ9Rt1KgAQAgAHAAgJ9Rt1KgAQAgAAAA==.Maivel:BAAALgAECgEJAQAAAA==.Mandret:BAAALgAECgMJBAAAAA==.Manicppanic:BAABLgAECn8YAAIQAAgJXhNkFwCJAQAQAAgJXhNkFwCJAQABLgAFFAQJDgAIAB8RAA==.Manrypurp:BAAALgAECgUJDQAAAA==.Marcie:BAABLgAECn8lAAIFAAgJzgxJJQBHAQAFAAgJzgxJJQBHAQAAAA==.',
Mc='Mchammer:BAAALgADCgUJBgAAAA==.',
Me='Meatyloaf:BAAALgAECgYJDQAAAA==.Melkedrik:BAAALgAECgYJDQAAAA==.Melleren:BAAALgAECgEJAgAAAA==.Messande:BAAALgAECgUJBgAAAA==.',
Mi='Minõs:BAAALgADCgkJEAAAAA==.Mirai:BAAALgADCgUJBQAAAA==.Mirei:BAABLgAECn8dAAITAAYJgghJNADrAAATAAYJgghJNADrAAAAAA==.Mistdancer:BAAALgADCgYJBgABLgAECgkJHgAZABMOAA==.Mitsurugi:BAAALgADCgQJAwABLgAECgkJHgAZABMOAA==.Miyagí:BAAALgAECgcJDgABLgAECggJGAAWAKUdAA==.',
Mo='Mojam:BAAALgAECgQJBwAAAA==.Monk:BAAALgAECgEJAQAAAA==.Moonless:BAAALgAECgEJAgAAAA==.Moovidlin:BAAALgAECggJEAAAAA==.Mordian:BAAALgAECgYJBgAAAA==.Morinnas:BAAALgADCgkJDAAAAA==.Moschpit:BAAALgADCgEJAQAAAA==.',
Mu='Munkeez:BAAALgADCgMJAwAAAA==.Murdermoo:BAAALgADCgMJAwAAAA==.Murkessa:BAAALgAECgQJBwAAAA==.Mushhead:BAAALgAECgUJCAAAAA==.',
My='Myishaa:BAAALgADCgIJAgAAAA==.Mykeal:BAAALgADCgMJBQAAAA==.Mystryl:BAAALgADCgcJBwAAAA==.',
['Mì']='Mìstra:BAAALgADCgUJBwAAAA==.',
Na='Nargo:BAAALgADCgYJCgAAAA==.Nataliia:BAAALgAECgQJBAAAAA==.',
Ne='Necrostalker:BAAALgADCgkJCQABLgADCgEJAQAKAAAAAA==.Negative:BAAALgAECgQJBgAAAA==.Nerwende:BAAALgAECgEJAQAAAA==.Nethershade:BAABLgAECn8dAAIeAAYJChh5CQBiAQAeAAYJChh5CQBiAQAAAA==.Netherstörm:BAAALgADCgkJJgAAAA==.',
Ni='Niclea:BAAALgAECgQJBAAAAA==.Nightelm:BAABLgAECn8fAAQGAAgJvR73GwDpAQAGAAgJth73GwDpAQAhAAUJcAwWNADNAAAiAAQJ9xvWKgDHAAAAAA==.Niënor:BAAALgAECgYJBgABLgAECgYJDwAKAAAAAA==.',
Nj='Njorvir:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.',
No='Noslien:BAAALgAECgUJBwAAAA==.Nostradamuz:BAAALgAECgEJAQAAAA==.Novasong:BAAALgAECgEJAwAAAA==.',
Ny='Nyxstonia:BAACLgAFFH8JAAIRAAMJlxm3EADdAAARAAMJlxm3EADdAAAuAAQKfzAAAhEACQm4GioJAB0CABEACQm4GioJAB0CAAAA.',
Ob='Oballi:BAAALgAECgUJBwAAAA==.',
Od='Oddsaint:BAAALgAECgEJAwAAAA==.',
Ol='Olierra:BAAALgAECgYJDAAAAA==.',
On='Onlyvoids:BAAALgAECgMJAwAAAA==.',
Or='Ornac:BAAALgADCgYJBgAAAA==.',
Ot='Otkspring:BAACLgAFFH8FAAIEAAMJCAd6JQDEAAAEAAMJCAd6JQDEAAAuAAQKfxkAAgQABwmAF6sdALQBAAQABwmAF6sdALQBAAAA.Otto:BAABLgAECn8jAAIHAAgJyBJ8UACPAQAHAAgJyBJ8UACPAQAAAA==.',
Ox='Oxadin:BAAALgAECgEJAQAAAA==.Oxideous:BAAALgADCgMJAwAAAA==.',
Pa='Paleale:BAABLgAECn8VAAIaAAYJ7wzDQQDVAAAaAAYJ7wzDQQDVAAAAAA==.Pallyshore:BAAALgADCgMJAwAAAA==.Pampoovy:BAEALgADCgMJAwABLgAECgUJCQAKAAAAAA==.Pantoponrose:BAAALgAECgMJAwAAAA==.Pastorbash:BAAALgADCggJCQAAAA==.',
Pb='Pb:BAAALgAECgMJAwAAAA==.',
Pe='Persephoneia:BAABLgAECn8hAAINAAgJ7BAHHwB6AQANAAgJ7BAHHwB6AQAAAA==.',
Ph='Phukimded:BAAALgAECggJEAABLgAECggJEwAKAAAAAA==.',
Pk='Pkashmuk:BAAALgADCgcJBwAAAA==.',
Pr='Prophettool:BAABLgAECn8oAAMHAAkJlAuvVgB/AQAHAAkJlAuvVgB/AQAIAAQJigQEfQCGAAAAAA==.Pruned:BAAALgADCgcJBwABLgAFFAQJDAAgAIgbAA==.',
Pu='Punjistake:BAAALgAECgYJBgAAAA==.',
Qu='Quanchii:BAAALgADCgMJAwAAAA==.',
Ra='Raemie:BAAALgAECgQJBwAAAA==.Ragequit:BAAALgAECggJEwAAAA==.Raikoho:BAAALgAECgEJAQAAAA==.Rakulm:BAAALgADCgUJCgAAAA==.Ravenrest:BAEBLgAECn8vAAINAAgJqx43CwBTAgANAAgJqx43CwBTAgAAAA==.',
Re='Reaverhiem:BAAALgAECgQJEQAAAA==.Reiko:BAAALgADCgkJIQABLgAECgYJHQATAIIIAA==.Remuz:BAAALgAECgMJBgAAAA==.Rennwick:BAAALgAECgQJBgAAAA==.',
Rh='Rhe:BAAALgAECgEJAQABLgAECgYJBQAKAAAAAA==.',
Ri='Rilz:BAABLgAECn8nAAICAAgJch5gJgAkAgACAAgJch5gJgAkAgAAAA==.',
Ro='Rochambeu:BAAALgADCgEJAQAAAA==.Rockasham:BAAALgAECgEJAQAAAA==.Rodgerwabbet:BAAALgAECgQJBAAAAA==.Roiddemon:BAAALgADCgQJBAABLgAECggJKwAYABcUAA==.Roiddrood:BAAALgAECgIJAgABLgAECggJKwAYABcUAA==.Roidlock:BAABLgAECn8rAAIYAAgJFxTBPACrAQAYAAgJFxTBPACrAQAAAA==.Roidtank:BAAALgAECgUJDAABLgAECggJKwAYABcUAA==.Rosaline:BAAALgAECgYJDgAAAA==.Rottn:BAAALgAECgYJDAABLgAECggJEwAKAAAAAA==.',
Ru='Runerion:BAAALgAECgEJAgAAAA==.',
Ry='Ry:BAAALgAECgYJBQAAAA==.',
['Rà']='Ràìn:BAABLgAECn8WAAIDAAgJAglRewBGAQADAAgJAglRewBGAQAAAA==.',
Sa='Safmen:BAABLgAECn8bAAQRAAYJwQcOJwCyAAARAAYJjAcOJwCyAAASAAMJMgXpQgBUAAAEAAEJCAr0ogA9AAAAAA==.Sanikoa:BAAALgAECgQJCAAAAA==.Saraid:BAABLgAECn8qAAQPAAgJNxs8FABkAgAPAAgJNxs8FABkAgAFAAMJZxAUYQCdAAAjAAEJOAbFTQAVAAAAAA==.Saravase:BAAALgAECgQJDgAAAA==.Sardel:BAAALgADCgcJBwAAAA==.Sargeros:BAAALgAECgQJBQAAAA==.Sazem:BAAALgADCgIJAgAAAA==.',
Se='Sedaldra:BAAALgADCgYJCwAAAA==.',
Sh='Shadowi:BAAALgAECgEJAQAAAA==.Shadownights:BAABLgAECn8nAAINAAcJTxFlIwBZAQANAAcJTxFlIwBZAQAAAA==.Shadowpope:BAAALgAECgkJAgAAAA==.Shamoneyy:BAAALgADCgUJBQAAAA==.Shazi:BAABLgAECn8hAAMaAAgJXR09EAAiAgAaAAgJXR09EAAiAgAkAAEJ8Ao1LAA1AAAAAA==.Shiki:BAAALgADCgkJEgABLgAECgYJHQATAIIIAA==.Shimnar:BAAALgAECgcJEAABLgAECggJHAAEADMXAA==.Shinifur:BAAALgADCgUJBgAAAA==.Shinoto:BAAALgAECgQJBgAAAA==.Shockazam:BAAALgAECgcJEgAAAA==.Shrewby:BAAALgAECgEJAQAAAA==.Shyandra:BAAALgADCgYJBgAAAA==.',
Si='Sieghart:BAAALgAECgEJAQAAAA==.Six:BAAALgAECgUJCwAAAA==.',
Sk='Skylines:BAAALgAECgQJBAAAAA==.',
Sl='Sloptop:BAAALgAECgEJAgAAAA==.',
Sn='Snickersbar:BAAALgADCgUJCAAAAA==.Snowynn:BAAALgAECgQJBgAAAA==.Snöw:BAABLgAECn8iAAIDAAgJ0hWrPgDgAQADAAgJ0hWrPgDgAQAAAA==.Snöwy:BAAALgAECgQJBAAAAA==.',
So='Southpaw:BAAALgAECgMJAwAAAA==.',
Sp='Spooki:BAAALgAECgEJAQAAAA==.Spyro:BAABLgAECn8jAAQGAAkJ6Ax9GgD2AQAGAAkJ6Ax9GgD2AQAhAAgJZRD2FwAIAQAiAAIJpgnVNgBgAAAAAA==.',
Sr='Sron:BAABLgAECn8nAAIVAAgJKB90IgAMAgAVAAgJKB90IgAMAgAAAA==.',
St='Stariah:BAABLgAECn8aAAIDAAgJVQontQB1AQADAAgJVQontQB1AQAAAA==.Stawn:BAAALgADCgEJAQAAAA==.',
Su='Sumwhiteguy:BAAALgAECgEJAQAAAA==.',
Sw='Swooze:BAABLgAECn84AAIDAAkJ3R2ZDwDLAgADAAkJ3R2ZDwDLAgAAAA==.',
Sy='Sylrythriana:BAAALgAECgUJBwAAAA==.Syndicate:BAAALgAECgcJDQAAAA==.Syrenis:BAAALgADCgkJDwABLgAECggJHwAGAL0eAA==.',
['Sù']='Sùnnydk:BAAALgADCgcJBwAAAA==.',
Ta='Talwaz:BAAALgADCgkJDgAAAA==.Tankinbur:BAAALgAECgMJBgAAAA==.Tanzri:BAAALgAECgEJAQAAAA==.Tarlyn:BAABLgAECn8yAAQIAAgJrxfmGQDrAQAIAAgJrxfmGQDrAQAHAAYJXBomXgBtAQAMAAEJAADSPwA+AAAAAA==.Tatslight:BAABLgAECn8dAAIMAAYJah2ODwB0AQAMAAYJah2ODwB0AQABLgAECgYJHQAMAGodAA==.Tatsrage:BAAALgADCgYJBgABLgAECgYJHQAMAGodAA==.Tazaral:BAAALgADCgEJAQABLgAECgQJBwAKAAAAAA==.',
Te='Teysá:BAAALgADCgEJAQAAAA==.',
Th='Thor:BAAALgAECgYJCAAAAA==.Thyandris:BAAALgADCgYJCwAAAA==.Thánátós:BAAALgAECgQJBwAAAA==.',
Ti='Timmthemage:BAAALgAECgUJBwABLgAECgEJAQAKAAAAAQ==.Timthepally:BAAALgAECgcJCQABLgAECgEJAQAKAAAAAQ==.Tinytex:BAABLgAECn8ZAAIcAAgJ1QojJgBAAQAcAAgJ1QojJgBAAQAAAA==.Tisiphoneia:BAAALgAECgQJBgAAAA==.',
To='Toberson:BAAALgAECgEJAQAAAA==.Toxicbanana:BAAALgAECgYJEAAAAA==.',
Tr='Tradarynn:BAABLgAECn8WAAIHAAgJ8xV5PQDIAQAHAAgJ8xV5PQDIAQAAAA==.Trayvein:BAAALgADCgUJBQAAAA==.Trekk:BAAALgAECgcJBQAAAA==.Tress:BAAALgAECgQJDAAAAA==.',
Ts='Tsindre:BAAALgAECgEJAgAAAA==.',
Tu='Tulkar:BAAALgAECgEJAQAAAA==.Turambar:BAAALgADCgEJAQAAAA==.',
Um='Umbrax:BAAALgAECgQJBAAAAA==.',
Un='Unholymochi:BAABLgAECn8gAAICAAgJHh6SXQDaAQACAAgJHh6SXQDaAQAAAA==.',
Va='Valaynia:BAAALgAECgEJAQAAAA==.Valhalia:BAAALgAECgcJEgAAAA==.Vanyllapea:BAAALgAECgMJAwAAAA==.Varaelitha:BAAALgAECgMJAwAAAA==.Vashan:BAAALgAECgQJBQAAAA==.Vashni:BAAALgAECgkJDAAAAA==.',
Ve='Velinariae:BAAALgADCgYJEAAAAA==.Vengful:BAABLgAECn8ZAAMlAAYJhR1gHQDVAQAlAAYJhR1gHQDVAQAmAAIJoBf3GQB/AAAAAA==.',
Vi='Vira:BAAALgAECgIJAgAAAA==.Vivy:BAABLgAECn8fAAQYAAkJNhThLwBNAgAYAAkJzRPhLwBNAgAXAAQJaxSaMwDpAAAgAAIJBhXMJgBWAAAAAA==.',
Vo='Vorumbrae:BAAALgAECgQJBgAAAA==.',
Vu='Vultus:BAAALgAECgIJAgAAAA==.',
['Vä']='Väntage:BAAALgADCgEJAQAAAA==.',
Wa='Wagyubeef:BAABLgAECn8hAAIEAAgJ8xdoGwDFAQAEAAgJ8xdoGwDFAQAAAA==.Wali:BAABLgAECn8gAAMYAAgJMBPpQwCSAQAYAAgJMBPpQwCSAQAXAAEJAAB9dgAuAAAAAA==.Warlodzen:BAAALgADCgcJBwAAAA==.',
We='Wenson:BAAALgAECgEJAQAAAA==.',
Wh='Whatupbruh:BAACLgAFFH8OAAMdAAQJBBEMDQA5AQAdAAQJeg8MDQA5AQAVAAMJRxBBOQDjAAAuAAQKfyQABB0ABwkcIh4HAIgCAB0ABwm5IR4HAIgCABUAAQkJGzrIAEgAABQAAQndBnKSACgAAAAA.',
Wi='Wildfire:BAAALgAECgcJBwAAAA==.',
Wy='Wyleriya:BAABLgAECn8mAAIYAAgJBgk9YgA+AQAYAAgJBgk9YgA+AQAAAA==.',
Xa='Xanthas:BAAALgADCgQJBAAAAA==.',
Xc='Xcella:BAAALgAECgQJBwAAAA==.',
Xe='Xephon:BAAALgADCgcJBwAAAA==.',
Xi='Xina:BAAALgAECgEJAQAAAA==.',
Ya='Yamonu:BAAALgADCgEJAQAAAA==.',
Ye='Yelizaveta:BAAALgAECgMJAwAAAA==.',
Yl='Ylfcwen:BAAALgAECgEJAQAAAA==.',
Yo='Yodey:BAABLgAECn8fAAICAAkJpx86DgC/AgACAAkJpx86DgC/AgAAAA==.Yoovee:BAAALgADCgEJAQAAAA==.',
Yu='Yuaetrende:BAACLgAFFH8IAAIlAAMJih8JCwDKAAAlAAMJih8JCwDKAAAuAAQKfygAAiUACQm1IgQCABEDACUACQm1IgQCABEDAAAA.Yumii:BAABLgAECn8fAAMTAAgJfyXPAgA6AwATAAgJTSXPAgA6AwAnAAYJ/yH2DgBNAgAAAA==.',
Za='Zack:BAAALgAECgYJDgAAAA==.Zaerie:BAAALgADCgcJBwAAAA==.Zagul:BAAALgAECgUJCAAAAA==.Zalarah:BAAALgAECgQJCwAAAA==.Zalarilia:BAAALgAECgEJAQAAAA==.Zanoo:BAAALgADCgYJBwAAAA==.Zaphod:BAAALgAECgMJAwAAAA==.Zardan:BAABLgAECn8dAAIYAAgJtAu/UwBkAQAYAAgJtAu/UwBkAQAAAA==.',
Zi='Ziegler:BAAALgADCgYJBgAAAA==.',
Zo='Zorrita:BAAALgAECgEJAQAAAA==.',
Zu='Zuggasaurus:BAAALgAECgEJAQABLgAECggJKAAIADAhAA==.Zugglite:BAABLgAECn8oAAQIAAgJMCEyFwBYAgAIAAgJMCEyFwBYAgAMAAQJ2xqEFQAmAQAHAAEJdgkERAEuAAAAAA==.Zulthar:BAABLgAECn8aAAIDAAgJ8QrfhAAzAQADAAgJ8QrfhAAzAQAAAA==.',
['Äs']='Äshborn:BAABLgAECn8gAAICAAgJpg5NWgBxAQACAAgJpg5NWgBxAQAAAA==.Ästra:BAAALgADCggJCAAAAA==.',
['Æl']='Ælxx:BAEALgAECgYJBwABLgAFFAEJAQAKAAAAAA==.',
['Ðe']='Ðeathless:BAAALgADCgUJBQAAAA==.',
['Øm']='Ømnium:BAABLgAECn8rAAIHAAcJWAk/iwARAQAHAAcJWAk/iwARAQAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
