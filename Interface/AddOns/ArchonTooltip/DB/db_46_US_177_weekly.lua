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

local lookup = {'Shaman-Restoration','DeathKnight-Unholy','Mage-Frost','Warrior-Fury','Druid-Balance','DeathKnight-Blood','DeathKnight-Frost','Evoker-Augmentation','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','Unknown-Unknown','Hunter-BeastMastery','Druid-Feral','Paladin-Protection','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Warrior-Arms','Priest-Holy','Hunter-Marksmanship','Monk-Brewmaster','Warlock-Destruction','Warlock-Demonology','Shaman-Elemental','Monk-Mistweaver','Hunter-Survival','Rogue-Assassination','Rogue-Outlaw','Priest-Discipline','Warlock-Affliction','DemonHunter-Havoc','Evoker-Devastation','Evoker-Preservation','Druid-Guardian','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abelas:BAAALgAECgYJCAAAAA==.Abracadaxis:BAAALgADCggJCAAAAA==.',
Ad='Adallyn:BAAALgADCgYJCgAAAA==.Adzen:BAAALgAECgMJAwAAAA==.Adêrna:BAABLgAECn8yAAIBAAkJ+B4nCgAHAwABAAkJ+B4nCgAHAwAAAA==.',
Af='Affliction:BAAALgADCgUJBQAAAA==.',
Ag='Agba:BAABLgAFFH8PAAICAAQJRwaYegD/AAACAAQJRwaYegD/AAAAAA==.',
Ah='Ahktari:BAAALgADCgcJBwAAAA==.',
Al='Alaidan:BAAALgAECgkJDQAAAA==.Alanus:BAABLgAECn8pAAIDAAkJMhBuVgDTAQADAAkJMhBuVgDTAQAAAA==.Alarion:BAAALgAECgQJBwAAAA==.Alavia:BAABLgAECn8/AAIEAAkJfxi9GAAhAgAEAAkJfxi9GAAhAgAAAA==.Alinäs:BAABLgAECn8hAAIDAAkJHQ/zXADCAQADAAkJHQ/zXADCAQAAAA==.Aliën:BAAALgADCgcJCQAAAA==.Alliumoo:BAABLgAECn8XAAIFAAYJwQkBRwASAQAFAAYJwQkBRwASAQAAAA==.Altana:BAABLgAECn8YAAMGAAkJDxLcGgB6AQAGAAkJNRDcGgB6AQAHAAMJ9xHWIQCsAAABLgAFFAMJBQAIAO4UAA==.Alydrus:BAABLgAECn82AAIDAAkJXRIaTgDrAQADAAkJXRIaTgDrAQAAAA==.Alíen:BAAALgAECgQJBAAAAA==.',
Am='Amnesian:BAAALgAECgkJAgAAAA==.',
An='Anberlinean:BAABLgAECn8WAAIJAAYJ5geytAAbAQAJAAYJ5geytAAbAQAAAA==.Angryelf:BAAALgAECgEJAQAAAA==.Angzhixing:BAAALgADCgIJAgAAAA==.Ankles:BAAALgADCgcJBwABLgAFFAQJDgAKAB8RAA==.Annahe:BAABLgAECn8WAAILAAkJ/xoTEgAlAgALAAkJ/xoTEgAlAgAAAA==.Annale:BAAALgAECgQJBQABLgAECgkJFgALAP8aAA==.Annatara:BAAALgAECgMJBAAAAA==.Anran:BAAALgADCgEJAQAAAA==.Anub:BAAALgADCgYJBgAAAA==.Anzala:BAAALgAECgYJDAAAAA==.',
Ao='Aoba:BAAALgAECgYJCwAAAA==.',
Ar='Arataeus:BAAALgAECgQJCgAAAA==.Areliss:BAAALgAECgUJBQAAAA==.Armsmaster:BAABLgAECn80AAICAAgJmiACMQAzAgACAAgJmiACMQAzAgAAAA==.Artemistha:BAAALgADCgkJHQAAAA==.',
As='Asalynn:BAAALgADCgEJAQAAAA==.',
Av='Avalina:BAAALgAECgEJAQAAAA==.Avengharambe:BAAALgADCgcJBwAAAA==.Averan:BAAALgAECgYJEQAAAA==.Averybug:BAAALgAECgEJAQAAAA==.',
Az='Azarke:BAAALgAECgEJAQAAAA==.',
Ba='Backbeamz:BAAALgAECgYJCQAAAA==.Backspace:BAAALgADCgYJBgAAAA==.Badgër:BAAALgADCgEJAQAAAA==.Baey:BAAALgADCgMJAwABLgAECgkJMwADAMIeAA==.Balduun:BAAALgAECgEJAgAAAA==.Barelycastin:BAAALgAECgUJBgAAAA==.Bashdadargon:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Bashoomba:BAAALgAECgQJBQAAAA==.',
Be='Bear:BAABLgAECn8gAAINAAgJVSDyFgCSAgANAAgJVSDyFgCSAgAAAA==.Bearnaked:BAAALgADCgIJAgAAAA==.Bebebluz:BAAALgADCgkJEAAAAA==.Belgarathh:BAAALgAFFAIJAgAAAA==.Bellíon:BAAALgAECgYJEQAAAA==.',
Bi='Bird:BAAALgADCgEJAQAAAA==.Bison:BAAALgAECgMJAwABLgADCgEJAQAMAAAAAA==.Bixee:BAAALgAECgUJCQAAAA==.',
Bl='Blacat:BAABLgAECn84AAMOAAkJCSKwAQAaAwAOAAkJCSKwAQAaAwAFAAIJUAM/eABEAAAAAA==.Bleen:BAAALgAECgUJDAAAAA==.Blitzcomets:BAAALgAECgEJAgAAAA==.Bloodbenders:BAAALgADCgEJAQAAAA==.Blueday:BAAALgAECgUJBQAAAA==.',
Bo='Bogeyman:BAABLgAECn81AAIPAAkJrSAdAwDhAgAPAAkJrSAdAwDhAgAAAA==.Boondoks:BAABLgAECn8gAAIKAAcJTh1hHgAFAgAKAAcJTh1hHgAFAgABLgAECgkJQQABAEYfAA==.Borda:BAAALgAECggJCAAAAA==.Bowrider:BAAALgAECgYJBwAAAA==.',
Br='Breer:BAAALgADCgkJCQAAAA==.Brondeadeye:BAAALgAECgUJBwAAAA==.Brunore:BAAALgAECgYJDAAAAA==.Brìan:BAAALgAECgUJBQAAAA==.',
Bu='Bubbajüdd:BAAALgADCgEJAQAAAA==.',
Ca='Caidi:BAAALgADCgMJAwAAAA==.Caledur:BAAALgAECgYJDAAAAA==.Caratdeullie:BAAALgADCgEJAQAAAA==.Careblair:BAAALgADCgkJCQAAAA==.',
Ch='Chakrah:BAABLgAECn8YAAIQAAcJ/gnZNQA9AQAQAAcJ/gnZNQA9AQAAAA==.Challan:BAABLgAFFH8GAAIRAAMJtAKIbQCWAAARAAMJtAKIbQCWAAAAAA==.Chloe:BAABLgAECn8XAAISAAkJ9AHN0AAtAAASAAkJ9AHN0AAtAAAAAA==.Chrno:BAABLgAECn8YAAISAAgJ5xEmMwDIAQASAAgJ5xEmMwDIAQAAAA==.Chunkymonkey:BAAALgADCgYJBgABLgAFFAQJDAADAKAHAA==.',
Ci='Cirilá:BAAALgAECgMJAQAAAA==.',
Cl='Clutcha:BAABLgAECn8cAAITAAYJKh19KABDAQATAAYJKh19KABDAQAAAA==.Clutchcross:BAAALgAECgQJBgABLgAECgYJHAATACodAA==.Clutchplate:BAABLgAECn8jAAMUAAgJKxRhFQCSAQAUAAgJKxRhFQCSAQAVAAEJWgbtfAAjAAAAAA==.Clûtch:BAACLgAFFH8WAAICAAUJjyA7SQBPAQACAAUJjyA7SQBPAQAuAAQKfyIAAgIACQliH+42AFsCAAIACQliH+42AFsCAAAA.',
Co='Codenameblue:BAAALgADCgEJAQAAAA==.Coldphoenix:BAAALgADCgkJCgAAAA==.Coog:BAAALgADCgEJAQAAAA==.Corynthe:BAABLgAECn86AAIWAAkJLyHOAwBFAwAWAAkJLyHOAwBFAwAAAA==.',
Cr='Crickie:BAAALgAECgYJDwAAAA==.Crovaxis:BAABLgAECn8oAAMXAAkJNB+dBwD/AQAXAAcJ8SKdBwD/AQANAAIJ/BNX1ACNAAAAAA==.',
Cu='Cursecackler:BAAALgADCgYJBgAAAA==.',
Cy='Cynda:BAAALgADCgMJAwAAAA==.Cyndestine:BAAALgADCgYJBgAAAA==.Cyzarius:BAAALgAECgEJAQAAAA==.',
Da='Daddychill:BAABLgAECn8fAAIYAAkJGxTYFQD1AQAYAAkJGxTYFQD1AQAAAA==.Dahunt:BAAALgAECgcJAQAAAA==.Damekka:BAAALgAECgQJBQAAAA==.Danazer:BAAALgAECgYJBgAAAA==.Danoe:BAAALgAECgIJAgAAAA==.Darktalyn:BAABLgAECn8vAAMWAAkJAhRiGQDyAQAWAAgJFhZiGQDyAQAQAAgJZwy+OgAfAQAAAA==.',
De='Deadpaws:BAAALgADCgMJAwAAAA==.Deathbinger:BAAALgADCgEJAQAAAA==.Deathgriped:BAABLgAECn84AAIGAAgJmBj+EQDiAQAGAAgJmBj+EQDiAQAAAA==.Deathhawkzz:BAACLgAFFH8PAAMZAAQJRgrPDwCqAAAaAAQJRgpyWAAJAQAZAAMJLgPPDwCqAAAuAAQKfxoAAxkACAmcFOYLAAQCABkABwn6FeYLAAQCABoABAntEWWiAPYAAAAA.Deathphoenix:BAAALgADCgcJBwAAAA==.Deathslock:BAAALgADCgQJBAAAAA==.Deekura:BAABLgAECn8xAAMCAAgJbwtudgBuAQACAAgJbwtudgBuAQAHAAIJlQFHNQA0AAAAAA==.Deladorana:BAAALgADCgUJBQAAAA==.Delimira:BAAALgAECgQJBwAAAA==.Dellma:BAAALgADCgYJDAAAAA==.Delusion:BAAALgAECgYJDQAAAA==.Demonpapi:BAABLgAFFH8GAAIaAAMJ6AJohgClAAAaAAMJ6AJohgClAAAAAA==.Demoryx:BAEALgAECgQJBAABLgAECgkJJAAbAPwbAA==.Denjack:BAAALgAECgYJDwAAAA==.Dewayne:BAAALgAECgUJBQAAAA==.',
Dh='Dhadzen:BAAALgAECgQJCwAAAA==.',
Di='Dionan:BAABLgAECn8qAAIJAAkJZRJbWgCzAQAJAAkJZRJbWgCzAQAAAA==.Dirtysouth:BAAALgAECgcJDAABLgAFFAUJGgANADAhAA==.',
Do='Docs:BAABLgAECn8vAAIKAAgJbhlPFgBNAgAKAAgJbhlPFgBNAgAAAA==.Doks:BAABLgAECn9BAAIBAAkJRh9hDADsAgABAAkJRh9hDADsAgAAAA==.Dontpanic:BAABLgAECn8iAAIcAAcJTRzxGgAsAgAcAAcJTRzxGgAsAgABLgAFFAQJDgAKAB8RAA==.Doomsnake:BAAALgADCgMJAwABLgADCgEJAQAMAAAAAA==.Dove:BAAALgADCgYJBgAAAA==.',
Dr='Dragana:BAAALgADCgcJBgAAAA==.Dragomalfoy:BAAALgADCgQJBAAAAA==.Dragondznuts:BAAALgAFFAQJBAAAAA==.Dragõn:BAAALgAECgYJDQAAAA==.Drexeos:BAAALgADCgcJBwAAAA==.Drinker:BAAALgADCgUJBQAAAA==.Drunkenhealz:BAAALgAECgcJBQAAAA==.',
Du='Dunir:BAAALgAECgQJCAAAAA==.',
Ea='Ealara:BAABLgAECn8eAAINAAgJ7gnmbQBZAQANAAgJ7gnmbQBZAQAAAA==.',
Ed='Edran:BAAALgADCgcJFQAAAA==.',
Ei='Eifel:BAAALgAECgQJBAABLgAECgkJGwAJABceAA==.Eimin:BAAALgADCgYJCgAAAA==.',
El='Eldarion:BAAALgAECgMJAgAAAA==.Elfmonk:BAAALgAECgEJAQAAAA==.Ellipses:BAAALgAECgMJAwABLgAFFAEJAQAMAAAAAA==.',
Em='Emberaegis:BAAALgAECgYJDgABLgAFFAEJAQAMAAAAAA==.Emeraldz:BAABLgAECn8mAAILAAgJcRzpEgAcAgALAAgJcRzpEgAcAgAAAA==.',
En='Eneru:BAAALgADCgYJCAABLgAECggJHwAKAJ0XAA==.',
Er='Erebrethil:BAAALgAECgYJDwABLgAECggJFQAcAEwTAA==.',
Es='Espe:BAABLgAECn8cAAIYAAkJyhMrGgDMAQAYAAkJyhMrGgDMAQAAAA==.',
Eu='Eucalyptia:BAAALgADCgQJBAAAAA==.',
Ev='Evenin:BAAALgADCgIJAgAAAA==.',
Ex='Exoncantotem:BAAALgADCgQJBAAAAA==.',
Fa='Faenor:BAAALgAECgUJDAAAAA==.Faynor:BAABLgAECn87AAMYAAkJdxhTEQAlAgAYAAkJdxhTEQAlAgALAAYJcRMcMgAwAQAAAA==.Faynór:BAAALgAECgMJAwABLgAECgkJOwAYAHcYAA==.',
Fe='Feloni:BAAALgAECgMJAwAAAA==.',
Fi='Finalone:BAAALgAECgEJAQAAAA==.Firêfly:BAAALgAECgcJEQAAAA==.',
Fk='Fknsteve:BAAALgADCgYJBgAAAA==.',
Fl='Flaptix:BAAALgAECgMJAwAAAA==.Flipingflerp:BAAALgAECgcJEQAAAA==.Flloran:BAAALgAECgYJCgAAAA==.Floragoth:BAAALgAECgEJAQAAAA==.Flowers:BAAALgADCgkJCQAAAA==.Fluffboi:BAABLgAECn8yAAILAAgJ7AoENAAnAQALAAgJ7AoENAAnAQAAAA==.',
Fo='Fourloko:BAAALgAECgEJAQAAAA==.Foxyblue:BAABLgAECn8UAAIWAAYJTBV3NABtAQAWAAYJTBV3NABtAQAAAA==.',
Fr='Fraggle:BAACLgAFFH8OAAMKAAQJHxEjJgDmAAAKAAQJHxEjJgDmAAAJAAMJUwnVbQDDAAAuAAQKfycAAwoACAl+IBsLAMcCAAoACAl+IBsLAMcCAAkABAmtEITLAOwAAAAA.Freefromfate:BAAALgAECgEJAQAAAA==.Frogchi:BAAALgAECgYJDQAAAA==.Frostbité:BAABLgAECn81AAIPAAkJph4OBAC6AgAPAAkJph4OBAC6AgAAAA==.Fruit:BAAALgAECgYJEgAAAA==.',
Fu='Fuknak:BAAALgAECgIJAwAAAA==.Fumikiko:BAAALgADCgIJAgABLgAFFAMJBQAIAO4UAA==.Furrykarg:BAAALgAECgEJAQABLgAECgQJBgAMAAAAAA==.',
['Fà']='Fàynor:BAAALgAECggJEgABLgAECgkJOwAYAHcYAA==.',
['Fú']='Fúzzy:BAAALgADCgEJAgABLgAECgEJAQAMAAAAAA==.',
Ga='Gakkle:BAABLgAECn8cAAIEAAgJ+hZEIADnAQAEAAgJ+hZEIADnAQAAAA==.Galadralvia:BAABLgAECn8VAAIUAAkJ8wxTGwBQAQAUAAkJ8wxTGwBQAQAAAA==.Gali:BAAALgAECgUJDAAAAA==.Ganaan:BAAALgAECgEJAQAAAA==.',
Ge='Gearsofbob:BAAALgAFFAIJBAAAAA==.Gekkle:BAAALgADCgUJBQAAAA==.',
Gh='Ghorn:BAAALgAECgEJAQAAAA==.Ghoulei:BAABLgAECn82AAICAAkJzx+sGACrAgACAAkJzx+sGACrAgAAAA==.',
Gi='Girlscout:BAAALgAECgYJBgABLgAFFAQJDgAKAB8RAA==.',
Gl='Glaistiguain:BAAALgAECgYJCwABLgAECggJNAACAJogAA==.Glenheals:BAAALgADCgkJEgAAAA==.Glifin:BAAALgAECgYJDQAAAA==.Gloomstalkin:BAABLgAECn8/AAIdAAkJNhfLDQBIAgAdAAkJNhfLDQBIAgAAAA==.',
Gn='Gnøsis:BAAALgADCggJEQAAAA==.',
Go='Goldìelocks:BAAALgAECgUJCAAAAA==.Gom:BAAALgAECgIJAgAAAA==.Gomdrog:BAAALgAECgEJAQAAAA==.',
Gr='Gr:BAABLgAECn8mAAIeAAcJVA0KDgA5AQAeAAcJVA0KDgA5AQAAAA==.Grannecs:BAAALgADCgEJAQAAAA==.Grimmli:BAAALgADCgEJAQAAAA==.Grizelda:BAAALgADCgQJBAAAAA==.Grizzledpaw:BAAALgAECgUJCwAAAA==.Gromcresh:BAAALgAECgUJBQAAAA==.Gryffs:BAABLgAECn86AAMUAAkJ3CD8BADDAgAUAAkJ3CD8BADDAgAVAAEJ1AqIdAAsAAAAAA==.',
Gu='Gum:BAAALgAECgcJBwABLgAECgkJNQAPAK0gAA==.Gutts:BAABLgAECn8nAAQUAAkJDSIzBQC8AgAUAAkJDSIzBQC8AgAVAAcJ3BIPKgAZAQAEAAQJ0Q7wfQDFAAAAAA==.',
Ha='Hadron:BAAALgAECgQJCQAAAA==.Halomea:BAAALgADCgQJBAAAAA==.Hanukira:BAAALgADCgUJBQAAAA==.Happi:BAAALgAECgYJCQABLgAFFAcJHgARADAkAA==.Happyhour:BAAALgADCgMJAwABLgAFFAcJHgARADAkAA==.Harald:BAABLgAECn8cAAMCAAgJDw4LnwAkAQACAAcJkAoLnwAkAQAGAAEJDCOPRwBjAAAAAA==.Harkle:BAAALgADCgcJDQAAAA==.Haruun:BAAALgAECgIJAgAAAA==.',
He='Healyoself:BAAALgAECgIJAgAAAA==.Heliõs:BAAALgAECgEJAQAAAA==.Hesmydaddy:BAABLgAECn86AAIWAAkJhguhJwB7AQAWAAkJhguhJwB7AQAAAA==.',
Ho='Honestie:BAAALgAECgQJCgAAAA==.Hongling:BAAALgADCgYJBgABLgAFFAMJBQAIAO4UAA==.Honêy:BAEALgAFFAIJAQABLgAECgkJJAAbAPwbAA==.Hotdogstand:BAACLgAFFH8WAAITAAcJ3yKtBQAzAgATAAcJ3yKtBQAzAgAuAAQKfzEABBMACQlwJZ0CACUDABMACQlwJZ0CACUDAB4ABAmEIYELAHMBAB8AAQkrIr8cAFgAAAAA.',
Hu='Huzzaah:BAAALgAECgcJEwABLgAFFAQJDgAKAB8RAA==.',
Hy='Hyperius:BAAALgADCgIJAgAAAA==.',
['Hö']='Höneÿdew:BAABLgAECn8ZAAINAAgJ9Bg2LAADAgANAAgJ9Bg2LAADAgAAAA==.',
Ic='Icemann:BAAALgAECgEJAgAAAA==.',
Il='Ilidrayssel:BAABLgAECn8aAAIXAAcJbQNtHgCwAAAXAAcJbQNtHgCwAAAAAA==.Illida:BAAALgAECgMJCQAAAA==.Illidad:BAAALgAECgQJBAAAAA==.',
Im='Imhappy:BAAALgAECgUJCgABLgAFFAcJHgARADAkAA==.Imherdaddy:BAAALgADCgYJCAABLgAECgkJPwAdADYXAA==.',
In='Indracus:BAAALgAECgQJCQAAAA==.Innervape:BAAALgADCgMJAwAAAA==.',
Ja='Jacorict:BAABLgAECn8UAAIJAAYJJwsmyADwAAAJAAYJJwsmyADwAAAAAA==.Jagga:BAAALgADCgMJAwAAAA==.Jarrack:BAABLgAECn8zAAIDAAkJ1RwzHQCmAgADAAkJ1RwzHQCmAgAAAA==.',
Je='Jellyhawk:BAAALgAECgEJAQAAAA==.Jessicae:BAAALgAECggJEAAAAA==.Jeuno:BAAALgAECgYJBwABLgAFFAMJBQAIAO4UAA==.',
Jo='Josephd:BAAALgADCgEJAQABLgAECggJPgAFABwcAA==.Josephedd:BAABLgAECn8+AAIFAAgJHBz0EQA9AgAFAAgJHBz0EQA9AgAAAA==.',
Ju='Judgment:BAAALgAECgEJAQAAAA==.Jukk:BAABLgAECn8iAAIDAAkJMAenfAB4AQADAAkJMAenfAB4AQAAAA==.Junazeena:BAABLgAECn8pAAMbAAkJuAjHOQBAAQAbAAkJuAjHOQBAAQABAAIJCgIZxgA4AAAAAA==.',
Jy='Jygglypuff:BAAALgAECgUJBQAAAA==.',
Ka='Kaji:BAABLgAECn8iAAIcAAYJSRMGQABTAQAcAAYJSRMGQABTAQAAAA==.Kalistus:BAAALgAECgEJAgAAAA==.Kargfu:BAAALgAECgQJBgAAAA==.Karolat:BAAALgAECgUJBgAAAA==.Kayfabe:BAABLgAECn8bAAIDAAkJ3QNz+gAGAQADAAkJ3QNz+gAGAQAAAA==.Kayfay:BAAALgAECgMJAwAAAA==.Kazz:BAAALgAECgQJBAAAAA==.',
Ke='Keishilda:BAABLgAECn8WAAMgAAUJXQkHTgC4AAAgAAQJOwsHTgC4AAAQAAUJGwPdZAB1AAAAAA==.Keladria:BAAALgAECgQJBwAAAA==.Kelirra:BAAALgADCgQJCAAAAA==.Kelvyren:BAAALgADCgEJAQAAAA==.Kenel:BAABLgAECn83AAMSAAkJhBcAGQB0AgASAAkJhBcAGQB0AgAFAAUJcRH4TADKAAAAAA==.Kerea:BAABLgAECn86AAMSAAkJLggzUwA4AQASAAkJLggzUwA4AQAFAAMJAQulYQCDAAAAAA==.Kerob:BAAALgAECgEJAQAAAA==.',
Ki='Kicken:BAABLgAECn83AAQaAAgJNxwUMAATAgAaAAcJ2BoUMAATAgAZAAMJihkmPwC4AAAhAAEJBhFeNgA9AAAAAA==.Kitschy:BAAALgADCgEJAQAAAA==.Kittyperry:BAAALgAECgQJBAAAAA==.',
Kn='Knome:BAABLgAECn8zAAIDAAkJwh6jGgC0AgADAAkJwh6jGgC0AgAAAA==.',
Ko='Koana:BAAALgAECgkJCwAAAA==.Kororin:BAAALgAECgMJAwAAAA==.Korthelan:BAABLgAECn82AAIRAAkJDBJ9OQDVAQARAAkJDBJ9OQDVAQAAAA==.Kothara:BAABLgAECn8xAAINAAkJ8RU7JQBBAgANAAkJ8RU7JQBBAgAAAA==.Kotongar:BAAALgADCgMJAwAAAA==.',
Kr='Kreeoo:BAAALgAECgIJAgAAAA==.Krimzin:BAACLgAFFH8aAAINAAUJMCHHGwB+AQANAAUJMCHHGwB+AQAuAAQKfx8AAw0ACAnfIZQhADwCAA0ACAnfIZQhADwCAB0AAgkaELBYAEEAAAAA.Krystine:BAABLgAECn8VAAISAAYJ/BMCRgBuAQASAAYJ/BMCRgBuAQAAAA==.',
Ks='Kserasera:BAAALgAFFAIJAwAAAA==.',
Ku='Kuball:BAAALgAECgYJCQABLgAECgkJJwAUAA0iAA==.Kukuruku:BAABLgAECn8UAAIbAAcJDwrBSgD6AAAbAAcJDwrBSgD6AAAAAA==.',
['Kì']='Kìssofdeath:BAAALgAECgUJBQAAAA==.',
['Kî']='Kîllara:BAABLgAECn8oAAIBAAkJrhUwJwAWAgABAAkJrhUwJwAWAgAAAA==.',
La='Labialicious:BAAALgAECgEJAgAAAA==.Lanfeår:BAABLgAECn8VAAICAAYJCwjN1ADYAAACAAYJCwjN1ADYAAAAAA==.Lanskies:BAABLgAECn8ZAAICAAkJPRVNLwA5AgACAAkJPRVNLwA5AgAAAA==.',
Le='Leafymeds:BAAALgAECgYJEAABLgAECgkJQgABANEXAA==.Lebronjames:BAABLgAFFH8FAAICAAMJdhrScQAQAQACAAMJdhrScQAQAQAAAA==.Leiluna:BAAALgADCgkJEQAAAA==.Letheos:BAAALgAECgYJBgAAAA==.',
Li='Libertinne:BAABLgAECn8cAAIEAAgJMxclMACGAQAEAAgJMxclMACGAQAAAA==.Librarte:BAABLgAECn85AAIJAAkJNw1AZQCaAQAJAAkJNw1AZQCaAQAAAA==.Ligmanuts:BAAALgAECgIJBAAAAA==.Lija:BAAALgAECgYJBgABLgAECgkJIgADADAHAA==.Lillytrae:BAAALgAECgMJBQAAAA==.Lilmeds:BAABLgAECn8WAAMgAAkJ+QdSKgB0AQAgAAkJxwdSKgB0AQAWAAgJBQRdPQDuAAABLgAECgkJQgABANEXAA==.Listie:BAAALgADCgQJBAABLgAECgQJBAAMAAAAAA==.Litty:BAABLgAECn8oAAIDAAcJASVNKQBuAgADAAcJASVNKQBuAgAAAA==.Lizrdkng:BAAALgADCgMJBgAAAA==.',
Lo='Locktärd:BAACLgAFFH8MAAQhAAQJiBvYBAAxAQAhAAQJiBvYBAAxAQAaAAIJShYXMwCtAAAZAAIJogaEDgCXAAAuAAQKfyoABCEACAmIH6oCAJACACEACAk+H6oCAJACABoACAktGRZCAAYCABkAAgkLHIJGAJwAAAAA.Lohken:BAAALgAECgMJCQAAAA==.Lox:BAABLgAECn89AAMZAAkJSBe+BAAiAgAZAAkJSBe+BAAiAgAaAAIJFQRrFgFGAAAAAA==.',
Lu='Lucieb:BAAALgAECgEJAQAAAA==.',
Ly='Lydirn:BAABLgAECn8gAAQJAAkJ+RzVOwAJAgAJAAgJ3x3VOwAJAgAKAAQJzRWQUgDiAAAPAAIJoBz/LgCgAAAAAA==.Lyofel:BAAALgAECgYJDwAAAA==.Lyonel:BAAALgADCggJCAAAAA==.Lysaviel:BAAALgAECgEJAgAAAA==.',
['Lí']='Lítterbox:BAAALgAFFAMJAwAAAA==.',
Ma='Magedzen:BAAALgAECgMJAwAAAA==.Magicguy:BAABLgAECn8ZAAIDAAgJdQ2udgCFAQADAAgJdQ2udgCFAQAAAA==.Mahariel:BAABLgAECn8kAAINAAkJuQ5AQADWAQANAAkJuQ5AQADWAQAAAA==.Mahdy:BAABLgAECn9FAAIJAAkJGR2XIQB2AgAJAAkJGR2XIQB2AgAAAA==.Mahoe:BAAALgAECgQJBAAAAA==.Maivel:BAAALgAECgcJCAAAAA==.Manandaar:BAAALgAECgIJBAAAAA==.Mandret:BAAALgAECgMJBAAAAA==.Manicppanic:BAABLgAECn8gAAITAAgJxxWMGwCsAQATAAgJxxWMGwCsAQABLgAFFAQJDgAKAB8RAA==.Manrypurp:BAAALgAECgUJDQAAAA==.Marcie:BAABLgAECn83AAIFAAkJixGxHADWAQAFAAkJixGxHADWAQAAAA==.Martinriggz:BAAALgAECgMJBgAAAA==.',
Mc='Mchammer:BAAALgAECgEJAQAAAA==.',
Me='Meatyloaf:BAABLgAECn8ZAAIHAAgJFQQxHADaAAAHAAgJFQQxHADaAAAAAA==.Melkedrik:BAABLgAECn8XAAIiAAgJpA6xIQBYAQAiAAgJpA6xIQBYAQAAAA==.Melleren:BAAALgAECgYJCQAAAA==.Messande:BAAALgAECgUJBgAAAA==.',
Mi='Minõs:BAAALgADCgkJEAAAAA==.Mirai:BAAALgADCgUJBQAAAA==.Mirei:BAABLgAECn83AAIWAAgJcg68KgBlAQAWAAgJcg68KgBlAQAAAA==.Mistdancer:BAAALgADCgYJBgABLgAFFAIJCAAHAI0GAA==.Mitsurugi:BAAALgAECgEJAgABLgAFFAIJCAAHAI0GAA==.Miyagí:BAAALgAECgcJDgABLgAECggJGAAGAKYdAA==.',
Mo='Mochisama:BAAALgAECgYJCAAAAA==.Mojam:BAAALgAECgQJCwAAAA==.Monk:BAAALgAECgEJAQAAAA==.Monkadzen:BAAALgAECgEJAgAAAA==.Moonless:BAAALgAECgEJAgAAAA==.Moovidlin:BAABLgAECn8XAAIEAAkJBQtWMQCAAQAEAAkJBQtWMQCAAQABLgAECgkJIgADADAHAA==.Mordian:BAAALgAECgYJBgAAAA==.Morinnas:BAAALgAECgEJAQAAAA==.Moschpit:BAAALgADCgEJAQAAAA==.',
Mu='Munkeez:BAAALgADCgMJAwAAAA==.Murdermoo:BAAALgADCgMJAwAAAA==.Murkessa:BAAALgAECgQJBwAAAA==.Mushhead:BAAALgAECgUJCAAAAA==.',
My='Myishaa:BAAALgADCgIJAgAAAA==.Mykeal:BAAALgADCgMJBQAAAA==.Mystryl:BAAALgADCgkJEAAAAA==.Mythantherox:BAABLgAFFH8FAAIVAAMJGxr1GgD8AAAVAAMJGxr1GgD8AAABLgAFFAYJEgAjAGgWAA==.',
['Mì']='Mìstra:BAAALgADCgUJBwAAAA==.',
Na='Nargo:BAAALgADCgYJCgAAAA==.Nataliia:BAAALgAECgQJBAAAAA==.',
Ne='Necrostalker:BAAALgADCgkJCQABLgADCgEJAQAMAAAAAA==.Negative:BAAALgAECgQJCAAAAA==.Neltherius:BAAALgAECgEJAQAAAA==.Nerwende:BAAALgAECgEJAQAAAA==.Nethershade:BAABLgAECn8zAAIeAAgJDxfNBgDvAQAeAAgJDxfNBgDvAQAAAA==.Netherstörm:BAAALgAECgQJBAAAAA==.',
Ni='Niclea:BAAALgAECgQJBAAAAA==.Nightelm:BAACLgAFFH8FAAIIAAMJ7hSuOwDHAAAIAAMJ7hSuOwDHAAAuAAQKfysABAgACQltH4kKAKkCAAgACQlnH4kKAKkCACQABgleDBY0AM0AACMABAn3G0cYAIkAAAAA.Niënor:BAABLgAECn8VAAIcAAgJTBOmKQDHAQAcAAgJTBOmKQDHAQAAAA==.',
Nj='Njorvir:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.',
No='Noslien:BAAALgAECgUJBwAAAA==.Nostradamuz:BAAALgAECgEJAQAAAA==.Novasong:BAAALgAECgEJAwAAAA==.',
Ny='Nyxstonia:BAACLgAFFH8TAAIUAAQJvxipEAAXAQAUAAQJvxipEAAXAQAuAAQKfzUAAhQACQkrG98LACECABQACQkrG98LACECAAAA.',
Ob='Oballi:BAAALgAECgUJBwAAAA==.',
Od='Oddsaint:BAAALgAECgEJAwAAAA==.',
Ol='Olierra:BAAALgAECgYJDAAAAA==.',
On='Onlyvoids:BAAALgAECgMJAwAAAA==.',
Or='Orhan:BAAALgAECgQJBAABLgAECgkJOwAYAHcYAA==.Ornac:BAAALgADCgcJDQAAAA==.',
Ot='Otkspring:BAACLgAFFH8HAAMEAAMJHwp9NwC5AAAEAAMJZgh9NwC5AAAVAAEJPweUOwBBAAAuAAQKfxkAAgQABwmAF5QqAKUBAAQABwmAF5QqAKUBAAAA.Otto:BAABLgAECn8pAAIJAAkJ2hFgWQC2AQAJAAkJ2hFgWQC2AQAAAA==.Ottomagus:BAAALgAECgcJDAAAAA==.',
Ox='Oxadin:BAAALgAECgEJAQAAAA==.Oxideous:BAAALgADCgMJAwAAAA==.',
Pa='Paleale:BAABLgAECn8VAAIbAAYJ7wxPWADLAAAbAAYJ7wxPWADLAAAAAA==.Pallyshore:BAAALgADCgMJAwAAAA==.Pampoovy:BAEALgADCgMJAwABLgAECgYJDQAMAAAAAA==.Pandapunk:BAAALgAECggJDgAAAA==.Pantoponrose:BAAALgAECgYJDAAAAA==.Pastorbash:BAAALgADCggJCQAAAA==.',
Pb='Pb:BAAALgAECgMJAwAAAA==.',
Pe='Persephoneia:BAABLgAECn8kAAIQAAkJYxHlHgDGAQAQAAkJYxHlHgDGAQAAAA==.',
Ph='Phukimded:BAABLgAECn8fAAMGAAgJTQ+vHwBLAQAGAAgJTQ+vHwBLAQACAAEJrgNihAEhAAABLgAFFAEJAQAMAAAAAA==.',
Pi='Pitnick:BAAALgAECgIJAgAAAA==.',
Pk='Pkashmuk:BAAALgADCgcJBwAAAA==.',
Pr='Prophettool:BAABLgAECn8oAAMJAAkJlAuFegBuAQAJAAkJlAuFegBuAQAKAAQJigQEfQCGAAAAAA==.Pruned:BAAALgADCgcJBwABLgAFFAQJDAAhAIgbAA==.',
Pu='Punjistake:BAAALgAECgYJBgAAAA==.',
['Pï']='Pïzzasteve:BAAALgADCgEJAQAAAA==.',
Qu='Quanchii:BAAALgADCgMJAwAAAA==.',
Ra='Raemie:BAAALgAECgQJBwAAAA==.Ragequit:BAABLgAECn8WAAIUAAgJwheEEwCrAQAUAAgJwheEEwCrAQABLgAFFAEJAQAMAAAAAA==.Raikoho:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.Rakulm:BAAALgADCgUJCgAAAA==.Ravenrest:BAEBLgAECn8vAAIQAAgJqx64EQBBAgAQAAgJqx64EQBBAgAAAA==.',
Re='Reaverhiem:BAABLgAECn8YAAQUAAYJAx+tFACaAQAUAAYJYx6tFACaAQAEAAQJfxcqZQAeAQAVAAIJBR3iRQClAAAAAA==.Reiko:BAAALgADCgkJIQABLgAECggJNwAWAHIOAA==.Remuz:BAAALgAECgUJCwAAAA==.Rennwick:BAAALgAECgQJBgAAAA==.Renriss:BAAALgAECgUJBQABLgAECggJOAAGAJgYAA==.Rey:BAAALgAECgEJAQABLgAECgYJBQAMAAAAAA==.',
Rh='Rhe:BAAALgAECgEJAQABLgAECgYJBQAMAAAAAA==.',
Ri='Rilz:BAABLgAECn8qAAICAAkJ3SBxGwCaAgACAAkJ3SBxGwCaAgAAAA==.',
Ro='Rochambeu:BAAALgADCgEJAQAAAA==.Rockasham:BAAALgAECgQJCgAAAA==.Rockyrogue:BAAALgAECgEJAQAAAA==.Rodgerwabbet:BAAALgAECgQJBAAAAA==.Roiddemon:BAAALgADCgQJBAABLgAECggJKwAaABcUAA==.Roiddrood:BAAALgAECgIJAgABLgAECggJKwAaABcUAA==.Roidlock:BAABLgAECn8rAAIaAAgJFxSKUgCfAQAaAAgJFxSKUgCfAQAAAA==.Roidtank:BAAALgAECgUJDAABLgAECggJKwAaABcUAA==.Rongyi:BAAALgADCgIJAgAAAA==.Rosaline:BAAALgAECgYJDgAAAA==.Rottn:BAAALgAFFAEJAQAAAA==.',
Ru='Runerion:BAAALgAECgEJBQAAAA==.',
Ry='Ry:BAAALgAECgYJBQAAAA==.',
['Rà']='Ràìn:BAABLgAECn8WAAIDAAgJAglkmgBAAQADAAgJAglkmgBAAQAAAA==.',
Sa='Safmen:BAABLgAECn8bAAQUAAYJwQdtMwCgAAAUAAYJjAdtMwCgAAAVAAMJMgWcYABSAAAEAAEJCAr0ogA9AAAAAA==.Sanikoa:BAAALgAECgQJCAAAAA==.Saraid:BAABLgAECn8tAAQSAAkJ9Rj6FQCOAgASAAkJ9Rj6FQCOAgAFAAMJZxAUYQCdAAAlAAIJvQX8awAtAAAAAA==.Saravase:BAAALgAECgYJEwAAAA==.Sardel:BAAALgADCgcJBwAAAA==.Sargeros:BAAALgAECgQJBQAAAA==.Sazem:BAAALgADCgIJAgAAAA==.',
Se='Sedaldra:BAAALgADCgYJCwAAAA==.',
Sh='Shadowi:BAAALgAECgQJBQAAAA==.Shadownights:BAABLgAECn84AAIQAAkJNRfBEQBAAgAQAAkJNRfBEQBAAgAAAA==.Shadowpope:BAAALgAECgkJBgAAAA==.Shamoneyy:BAAALgADCgUJBQAAAA==.Shazi:BAEBLgAECn8kAAMbAAkJ/BsiEQBdAgAbAAkJ/BsiEQBdAgAmAAEJ8Ao1LAA1AAABLgAECgkJJAAbAPwbAA==.Shiki:BAAALgADCgkJEwABLgAECggJNwAWAHIOAA==.Shimnar:BAAALgAECggJEwABLgAECggJHAAEADMXAA==.Shinifur:BAAALgADCgUJBgAAAA==.Shinoto:BAAALgAECgYJEwAAAA==.Shiritá:BAAALgAECgMJAgAAAA==.Shockazam:BAAALgAECgcJEgAAAA==.Shrewby:BAAALgAECgEJAQAAAA==.Shyandra:BAAALgADCgYJBgAAAA==.',
Si='Sieghart:BAAALgAECgEJAgAAAA==.Six:BAAALgAECgUJCwAAAA==.',
Sk='Skylines:BAAALgAECgQJBAAAAA==.',
Sl='Sloptop:BAAALgAECgEJAgAAAA==.',
Sn='Snickersbar:BAAALgADCgUJCAAAAA==.Snowynn:BAAALgAECgYJDAAAAA==.Snöw:BAABLgAECn8nAAIDAAkJGhWQPAAiAgADAAkJGhWQPAAiAgAAAA==.Snöwy:BAAALgAECgQJBAAAAA==.',
So='Sojudevourer:BAAALgAECgEJAQAAAA==.Southpaw:BAAALgAECgMJAwAAAA==.',
Sp='Spooki:BAAALgAECgEJAQAAAA==.Spyro:BAABLgAECn8uAAQIAAkJ1A59GgD2AQAIAAkJ1A59GgD2AQAkAAgJABOTEAC5AQAjAAIJYw6BIQA/AAAAAA==.',
Sr='Sron:BAABLgAECn8oAAINAAgJKB+pOADxAQANAAgJKB+pOADxAQAAAA==.',
St='Stariah:BAABLgAECn8fAAIDAAgJdgontQB1AQADAAgJdgontQB1AQAAAA==.Stawn:BAAALgADCgEJAQAAAA==.',
Su='Sumwhiteguy:BAAALgAECgEJAQAAAA==.',
Sw='Swooze:BAACLgAFFH8JAAIDAAQJDgkxZgASAQADAAQJDgkxZgASAQAuAAQKfzsAAgMACQndHdcZALgCAAMACQndHdcZALgCAAAA.',
Sy='Sylrythriana:BAABLgAECn8YAAMTAAcJfwTOMgD/AAATAAcJfwTOMgD/AAAeAAIJCwLDJgAxAAAAAA==.Syndicate:BAAALgAECgcJDQAAAA==.Syrenis:BAAALgADCgkJDwABLgAFFAMJBQAIAO4UAA==.',
['Sù']='Sùnnydk:BAAALgADCgcJBwAAAA==.',
Ta='Tahoe:BAAALgADCgYJBgABLgAFFAUJHQARACEbAA==.Talwaz:BAAALgADCgkJDgAAAA==.Tankinbur:BAAALgAECgYJDAAAAA==.Tanzri:BAAALgAECgMJAwAAAA==.Tarlyn:BAACLgAFFH8MAAIKAAMJCg3mLwCpAAAKAAMJCg3mLwCpAAAuAAQKfzQABAoACQkRFw8WAFACAAoACQkRFw8WAFACAAkABglcGu2GAFcBAA8AAQkAANI/AD4AAAAA.Tatslight:BAABLgAECn8sAAIPAAgJBRyrCgASAgAPAAgJBRyrCgASAgABLgAECggJLAAPAAUcAA==.Tatsrage:BAAALgAECgEJAQABLgAECggJLAAPAAUcAA==.Tazaral:BAAALgADCgEJAQABLgAECgkJCwAMAAAAAA==.',
Te='Ted:BAAALgAFFAIJAgABLgAFFAQJDgAKAB8RAA==.Temuadêrna:BAAALgAECgQJBAAAAA==.Teysá:BAAALgADCgEJAQAAAA==.',
Th='Thalasso:BAAALgADCgEJAQAAAA==.Thor:BAAALgAECgYJCAAAAA==.Thyandris:BAAALgADCgYJCwAAAA==.Thánátós:BAAALgAECgQJBwAAAA==.',
Ti='Timmthemage:BAAALgAECgUJBwABLgAECgEJAQAMAAAAAQ==.Timthepally:BAAALgAECggJDAABLgAECgEJAQAMAAAAAQ==.Tinytex:BAABLgAECn8mAAIYAAkJyw44IgCPAQAYAAkJyw44IgCPAQAAAA==.Tisiphoneia:BAAALgAECgQJBgAAAA==.',
To='Toberson:BAAALgAECgEJAQAAAA==.Toxicbanana:BAAALgAECgYJEAAAAA==.',
Tr='Tradarynn:BAABLgAECn8fAAIJAAkJ7hvDHQCJAgAJAAkJ7hvDHQCJAgAAAA==.Trayvein:BAAALgADCgUJBQAAAA==.Trekk:BAAALgAECgcJBQAAAA==.Tress:BAAALgAECgYJEwAAAA==.',
Ts='Tsindre:BAAALgAECgEJAgAAAA==.',
Tu='Tulkar:BAAALgAECgIJAgAAAA==.Turambar:BAAALgADCgEJAQAAAA==.',
Ty='Tyriir:BAAALgADCgMJAwAAAA==.Tyviae:BAAALgAECgEJAQAAAA==.',
Um='Umbrax:BAAALgAECgQJBQAAAA==.',
Un='Unholymochi:BAABLgAECn8jAAICAAkJHiAGVwC4AQACAAkJHiAGVwC4AQAAAA==.',
Va='Valaynia:BAAALgAECgcJDQAAAA==.Valhalia:BAABLgAECn8UAAMaAAgJ6RfaawBfAQAaAAYJKBjaawBfAQAZAAMJbg6pQgCqAAAAAA==.Vanyllapea:BAAALgAECgMJAwAAAA==.Varaelitha:BAAALgAECgMJAwAAAA==.Vashan:BAAALgAECgQJBQAAAA==.Vashni:BAAALgAECgkJDAAAAA==.',
Ve='Velinariae:BAAALgADCgYJEAAAAA==.Vengful:BAABLgAECn8uAAMiAAkJZhwJCAChAgAiAAkJZhwJCAChAgAnAAIJoBdBIgB7AAAAAA==.',
Vi='Vira:BAAALgAECgIJAgAAAA==.Vivy:BAABLgAECn8fAAQaAAkJNhThLwBNAgAaAAkJzRPhLwBNAgAZAAQJaxSaMwDpAAAhAAIJBhXMJgBWAAAAAA==.',
Vo='Vorumbrae:BAAALgAECgYJCAAAAA==.',
Vu='Vultus:BAAALgAECgIJAgAAAA==.',
Vy='Vylthyra:BAAALgADCgEJAQABLgAFFAEJAQAMAAAAAA==.Vyrkin:BAAALgAECgEJAQAAAA==.',
['Vä']='Väntage:BAAALgADCgEJAQAAAA==.',
Wa='Wagyubeef:BAABLgAECn8kAAIEAAkJghfNHQD5AQAEAAkJghfNHQD5AQAAAA==.Wali:BAABLgAECn8gAAMaAAgJMRMPWQCNAQAaAAgJMRMPWQCNAQAZAAEJAAB9dgAuAAAAAA==.Warlodzen:BAAALgADCgcJBwAAAA==.',
We='Wenson:BAAALgAECggJEQAAAA==.',
Wh='Whatupbruh:BAACLgAFFH8OAAMdAAQJBBGIFQAUAQAdAAQJeg+IFQAUAQANAAMJRxDbXgDRAAAuAAQKfyQABB0ABwkcIh4HAIgCAB0ABwm5IR4HAIgCAA0AAQkJGzgKAUAAABcAAQndBnKSACgAAAAA.',
Wi='Wildfire:BAAALgAECgcJBwAAAA==.',
Wo='Wooties:BAAALgADCgEJAQABLgAECgkJQQABAEYfAA==.',
Wy='Wyleriya:BAABLgAECn83AAIaAAkJggloZgBsAQAaAAkJggloZgBsAQAAAA==.',
Xa='Xanthas:BAAALgADCgQJBAAAAA==.',
Xc='Xcella:BAAALgAECgUJCAAAAA==.',
Xe='Xephon:BAAALgADCgcJBwAAAA==.',
Xi='Xina:BAAALgAECgEJAQAAAA==.',
Xw='Xweakling:BAAALgADCgYJCAABLgAFFAQJCwAEAEobAA==.',
Xy='Xyn:BAAALgADCggJCAABLgAECgYJBQAMAAAAAA==.',
Ya='Yamonu:BAAALgADCgEJAQAAAA==.',
Ye='Yelizaveta:BAAALgAECgYJEgAAAA==.',
Yl='Ylfcwen:BAAALgAECgEJAQAAAA==.',
Yo='Yodey:BAACLgAFFH8MAAICAAQJOB+iOAB1AQACAAQJOB+iOAB1AQAuAAQKfzEAAgIACQlwI4YGAD8DAAIACQlwI4YGAD8DAAAA.Yoovee:BAAALgAECggJCAAAAA==.',
Yu='Yuaetrende:BAACLgAFFH8OAAIiAAQJex7zCQBOAQAiAAQJex7zCQBOAQAuAAQKfy0AAiIACQnwIqwDAAsDACIACQnwIqwDAAsDAAAA.Yumii:BAABLgAECn8hAAMWAAkJPSXTAQCNAwAWAAkJECXTAQCNAwAgAAYJ/yH2DgBNAgAAAA==.',
Za='Zack:BAAALgAECgYJEwAAAA==.Zaerie:BAAALgADCgcJBwAAAA==.Zagul:BAAALgAECgUJCAAAAA==.Zalarah:BAAALgAECgUJDQAAAA==.Zalarilia:BAAALgAECgEJAQAAAA==.Zanoo:BAAALgADCgYJBwAAAA==.Zaphod:BAAALgAECgMJAwAAAA==.Zardan:BAABLgAECn8dAAIaAAgJtAsIbQBcAQAaAAgJtAsIbQBcAQAAAA==.',
Zi='Ziegler:BAAALgADCgYJBgAAAA==.',
Zu='Zuggasaurus:BAABLgAECn8XAAQOAAkJMRiOBwBNAgAOAAkJMRiOBwBNAgAlAAUJoRWLIAA2AQASAAIJVg1apABhAAAAAA==.Zugglite:BAABLgAECn8oAAQKAAgJMCEyFwBYAgAKAAgJMCEyFwBYAgAPAAQJ2xqXHQAbAQAJAAEJdgk7lQErAAABLgAECgkJFwAOADEYAA==.Zulthar:BAABLgAECn8aAAIDAAgJ8QqSowAwAQADAAgJ8QqSowAwAQAAAA==.',
['Äs']='Äshborn:BAABLgAECn8oAAICAAkJIQ5pWAC0AQACAAkJIQ5pWAC0AQAAAA==.Ästra:BAAALgADCggJCAAAAA==.',
['Æi']='Æix:BAEALgAECgEJAQABLgAFFAYJFAADACIPAA==.',
['Æl']='Ælxx:BAEALgAECgYJBwABLgAFFAYJFAADACIPAA==.',
['Ðe']='Ðeathless:BAAALgADCgUJBQAAAA==.',
['Øm']='Ømnium:BAABLgAECn8zAAIJAAcJaArosAASAQAJAAcJaArosAASAQAAAA==.',
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
