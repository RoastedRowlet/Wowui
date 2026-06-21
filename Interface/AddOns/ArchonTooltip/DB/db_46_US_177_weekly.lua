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

local lookup = {'Shaman-Restoration','DeathKnight-Unholy','Mage-Frost','Warrior-Fury','Druid-Balance','DeathKnight-Blood','DeathKnight-Frost','Evoker-Augmentation','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','Unknown-Unknown','Hunter-BeastMastery','Druid-Feral','Paladin-Protection','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Warrior-Arms','Priest-Holy','Hunter-Marksmanship','Monk-Brewmaster','Warlock-Destruction','Warlock-Demonology','Shaman-Elemental','Monk-Mistweaver','Hunter-Survival','Rogue-Assassination','Rogue-Outlaw','Priest-Discipline','Warlock-Affliction','DemonHunter-Havoc','Evoker-Devastation','Evoker-Preservation','Druid-Guardian','Shaman-Enhancement','Mage-Fire','DemonHunter-Vengeance',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abelas:BAAALgAECgYJCAAAAA==.Abracadavr:BAAALgAECgIJAgAAAA==.Abracadaxis:BAAALgADCggJCAAAAA==.',
Ad='Adallyn:BAAALgADCgYJCgAAAA==.Adzen:BAAALgAECgQJBQAAAA==.Adêrna:BAABLgAECn8yAAIBAAkJ+B4vCwAFAwABAAkJ+B4vCwAFAwAAAA==.',
Af='Affliction:BAAALgADCgUJBQAAAA==.',
Ag='Agba:BAABLgAFFH8PAAICAAQJRwaKiQD3AAACAAQJRwaKiQD3AAAAAA==.',
Ah='Ahktari:BAAALgADCgcJBwAAAA==.',
Al='Alaidan:BAAALgAECgkJDQAAAA==.Alanus:BAABLgAECn8pAAIDAAkJMhA5XADJAQADAAkJMhA5XADJAQAAAA==.Alarion:BAAALgAECgQJBwAAAA==.Alavia:BAABLgAECn8/AAIEAAkJfxg+GgAcAgAEAAkJfxg+GgAcAgAAAA==.Alinäs:BAABLgAECn8hAAIDAAkJHQ/jYwC2AQADAAkJHQ/jYwC2AQAAAA==.Aliën:BAAALgADCgcJCQAAAA==.Alliumoo:BAABLgAECn8XAAIFAAYJwQkBRwASAQAFAAYJwQkBRwASAQAAAA==.Altana:BAABLgAECn8ZAAMGAAkJThNyHQBsAQAGAAkJNRByHQBsAQAHAAMJSRXqIADGAAABLgAFFAMJBwAIAO4UAA==.Alydrus:BAABLgAECn82AAIDAAkJXRL6UQDmAQADAAkJXRL6UQDmAQAAAA==.Alíen:BAAALgAECgQJBAAAAA==.',
Am='Amnesian:BAAALgAECgkJAgAAAA==.',
An='Anberlinean:BAABLgAECn8WAAIJAAYJ5geytAAbAQAJAAYJ5geytAAbAQAAAA==.Angryelf:BAAALgAECgEJAQAAAA==.Angzhixing:BAAALgADCgIJAgAAAA==.Ankles:BAEALgADCgcJBwABLgAFFAQJDgAKAB8RAA==.Annahe:BAABLgAECn8WAAILAAkJ/xo+EwAkAgALAAkJ/xo+EwAkAgAAAA==.Annale:BAAALgAECgQJBQABLgAECgkJFgALAP8aAA==.Annatara:BAAALgAECgQJCAAAAA==.Anran:BAAALgADCgEJAQAAAA==.Anub:BAAALgADCgYJBgAAAA==.Anzala:BAAALgAECgYJDAAAAA==.',
Ao='Aoba:BAAALgAECgYJCwAAAA==.',
Ar='Areliss:BAAALgAECgUJBQAAAA==.Armsmaster:BAABLgAECn80AAICAAgJmiAqNQAqAgACAAgJmiAqNQAqAgAAAA==.Artemistha:BAAALgAECgMJAwAAAA==.',
As='Asalynn:BAAALgADCgEJAQAAAA==.Asché:BAAALgAECgEJAQAAAA==.',
Av='Avalina:BAAALgAECgEJAQAAAA==.Avengharambe:BAAALgADCgcJBwAAAA==.Averan:BAAALgAECgYJEQAAAA==.Averybug:BAAALgAECgkJAQAAAA==.',
Az='Azarke:BAAALgAECgEJAgAAAA==.',
Ba='Backbeamz:BAAALgAECgYJCQAAAA==.Backspace:BAAALgADCgYJBgAAAA==.Badgër:BAAALgADCgEJAQAAAA==.Baey:BAAALgADCgMJAwABLgAECgkJMwADAMIeAA==.Balduun:BAAALgAECgEJAwAAAA==.Barelycastin:BAAALgAECgYJEQAAAA==.Bashdadargon:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Bashoomba:BAAALgAECgQJBQAAAA==.',
Be='Bear:BAABLgAECn8gAAINAAgJVSDBGQCLAgANAAgJVSDBGQCLAgAAAA==.Bearnaked:BAAALgADCgIJAgAAAA==.Bebebluz:BAAALgAECgEJAgAAAA==.Beets:BAAALgAECgEJAQAAAA==.Belgarathh:BAAALgAFFAIJAgAAAA==.Bellíon:BAAALgAECgYJEQAAAA==.',
Bi='Bird:BAAALgADCgEJAQAAAA==.Bison:BAAALgAECgMJAwABLgADCgEJAQAMAAAAAA==.Bixee:BAAALgAECgUJCQAAAA==.',
Bl='Blacat:BAABLgAECn84AAMOAAkJCSLrAQAWAwAOAAkJCSLrAQAWAwAFAAIJUAM/eABEAAAAAA==.Bleen:BAAALgAECgUJDAAAAA==.Blitzcomets:BAAALgAECgEJAwAAAA==.Bloodbenders:BAAALgADCgEJAQAAAA==.Blueday:BAAALgAECgUJBQAAAA==.',
Bo='Bogeyman:BAABLgAECn81AAIPAAkJrSBsAwDeAgAPAAkJrSBsAwDeAgAAAA==.Boondoks:BAABLgAECn8gAAIKAAcJTh0XIAADAgAKAAcJTh0XIAADAgABLgAECgkJQgABAEYfAA==.Borda:BAAALgAECggJCAAAAA==.Bowrider:BAAALgAECgYJBwAAAA==.',
Br='Breer:BAAALgAECgEJAQAAAA==.Brondeadeye:BAAALgAECgUJBwAAAA==.Brunore:BAAALgAECgYJDAAAAA==.Brìan:BAAALgAECgYJCwAAAA==.',
Bu='Bubbajüdd:BAAALgADCgEJAQAAAA==.',
Ca='Caidi:BAAALgADCgMJAwAAAA==.Caledur:BAAALgAECgYJDAAAAA==.Caliandra:BAAALgAECgEJAQAAAA==.Caratdeullie:BAAALgAECggJCQAAAA==.Careblair:BAAALgADCgkJCQAAAA==.',
Ch='Chakrah:BAABLgAECn8YAAIQAAcJ/gnZNQA9AQAQAAcJ/gnZNQA9AQAAAA==.Challan:BAABLgAFFH8GAAIRAAMJtALWdwCSAAARAAMJtALWdwCSAAAAAA==.Chloe:BAABLgAECn8XAAISAAkJ9AHL1wAtAAASAAkJ9AHL1wAtAAAAAA==.Chrno:BAABLgAECn8YAAISAAgJ5xEWNQDHAQASAAgJ5xEWNQDHAQAAAA==.Chunkymonkey:BAAALgADCgYJBgABLgAFFAQJEwADAKYKAA==.',
Ci='Cirilá:BAAALgAECgMJAQAAAA==.',
Cl='Cleric:BAAALgAECgYJBwAAAA==.Clutcha:BAABLgAECn8cAAITAAYJKh3OKgBCAQATAAYJKh3OKgBCAQAAAA==.Clutchcross:BAAALgAECgQJBgABLgAECgYJHAATACodAA==.Clutchplate:BAABLgAECn8jAAMUAAgJKxTNFgCNAQAUAAgJKxTNFgCNAQAVAAEJWgZzhgAjAAAAAA==.Clûtch:BAACLgAFFH8fAAICAAUJISGQBQAsAQACAAUJISGQBQAsAQAuAAQKfyIAAgIACQliH+42AFsCAAIACQliH+42AFsCAAAA.',
Co='Codenameblue:BAAALgADCgEJAQAAAA==.Coldphoenix:BAAALgADCgkJCgAAAA==.Coog:BAAALgADCgEJAQAAAA==.Corynthe:BAABLgAECn9KAAIWAAkJbCIRAABTAwAWAAkJbCIRAABTAwAAAA==.',
Cr='Crickie:BAAALgAECgcJEAAAAA==.Crovaxis:BAABLgAECn8oAAMXAAkJNB8zCAD8AQAXAAcJ8SIzCAD8AQANAAIJ/BPi4ACMAAAAAA==.',
Cu='Cursecackler:BAAALgADCgYJBgAAAA==.',
Cy='Cynda:BAAALgADCgMJAwAAAA==.Cyndestine:BAAALgADCgYJBgAAAA==.Cyzarius:BAAALgAECgEJAQAAAA==.',
Da='Daddychill:BAABLgAECn8fAAIYAAkJGxToFgDyAQAYAAkJGxToFgDyAQAAAA==.Dahunt:BAAALgAECgcJAQAAAA==.Damekka:BAAALgAECgQJBQAAAA==.Danazer:BAAALgAECgYJBgAAAA==.Danoe:BAAALgAECgIJAgAAAA==.Darktalyn:BAABLgAECn8vAAMWAAkJAhRbGwDuAQAWAAgJFhZbGwDuAQAQAAgJZwxdQAAOAQAAAA==.Davidaire:BAAALgAECgEJAQAAAA==.',
De='Deadpaws:BAAALgADCgMJAwAAAA==.Deathbinger:BAAALgADCgEJAQAAAA==.Deathgriped:BAABLgAECn84AAIGAAgJmBhdEwDbAQAGAAgJmBhdEwDbAQAAAA==.Deathhawkzz:BAACLgAFFH8TAAMZAAQJRgqTEgCjAAAaAAQJRgomYQAFAQAZAAMJLgOTEgCjAAAuAAQKfxoAAxkACAmcFOYLAAQCABkABwn6FeYLAAQCABoABAntEYOmAPQAAAAA.Deathphoenix:BAAALgADCgcJBwAAAA==.Deathslock:BAAALgADCgQJBAAAAA==.Deekura:BAABLgAECn8/AAMCAAgJ7hCzAgAbAQACAAgJ7hCzAgAbAQAHAAIJlQHaOgAyAAAAAA==.Deladorana:BAAALgADCgUJBQAAAA==.Delimira:BAAALgAECgQJBwAAAA==.Dellma:BAAALgADCgYJDAAAAA==.Delusion:BAAALgAECgYJEQAAAA==.Demonpapi:BAABLgAFFH8GAAIaAAMJ6AKGkACjAAAaAAMJ6AKGkACjAAAAAA==.Demoryx:BAEALgAECgQJBAABLgAECgkJJAAbAPwbAA==.Denjack:BAAALgAECgcJEAAAAA==.Dewayne:BAAALgAECgUJBQAAAA==.',
Dh='Dhadzen:BAAALgAECgQJCwAAAA==.',
Di='Dionan:BAABLgAECn8qAAIJAAkJZRK2XwCyAQAJAAkJZRK2XwCyAQAAAA==.Dirtysouth:BAAALgAFFAIJAgABLgAFFAUJGgANADAhAA==.',
Do='Docs:BAABLgAECn8vAAIKAAgJbhmvFwBLAgAKAAgJbhmvFwBLAgAAAA==.Doks:BAABLgAECn9CAAIBAAkJRh9yDQDrAgABAAkJRh9yDQDrAgAAAA==.Dontpanic:BAEBLgAECn8iAAIcAAcJTRxeHQAtAgAcAAcJTRxeHQAtAgABLgAFFAQJDgAKAB8RAA==.Doomsnake:BAAALgADCgMJAwABLgADCgEJAQAMAAAAAA==.Dove:BAAALgADCgYJBgAAAA==.',
Dr='Dragana:BAAALgAECgIJAgAAAA==.Dragomalfoy:BAAALgADCgQJBAAAAA==.Dragondznuts:BAAALgAFFAQJBAAAAA==.Dragõn:BAAALgAECgYJEQAAAA==.Drexeos:BAAALgADCgcJBwAAAA==.Drinker:BAAALgADCgUJBQAAAA==.Drunkenhealz:BAAALgAECgkJBQAAAA==.',
Du='Dunir:BAAALgAECgQJCAAAAA==.',
Ea='Ealara:BAABLgAECn8eAAINAAgJ7gmBdQBUAQANAAgJ7gmBdQBUAQAAAA==.',
Ed='Edran:BAAALgADCgcJFQAAAA==.',
Ei='Eifel:BAAALgAECgQJBAABLgAECgkJGwAJABceAA==.Eimin:BAAALgADCgYJCgAAAA==.',
El='Eldarion:BAAALgAECgMJAgAAAA==.Elfmonk:BAAALgAECgEJAQAAAA==.Ellipses:BAAALgAECgMJAwABLgAECggJKgAGACsZAA==.',
Em='Emeraldz:BAABLgAECn8mAAILAAgJcRwaFAAaAgALAAgJcRwaFAAaAgAAAA==.',
En='Eneru:BAAALgADCgYJCAAAAA==.',
Er='Erebrethil:BAAALgAECgYJDwABLgAECggJIgAcAL4aAA==.',
Es='Espe:BAABLgAECn8cAAIYAAkJyhM5GwDLAQAYAAkJyhM5GwDLAQAAAA==.',
Eu='Eucalyptia:BAAALgADCgQJBAAAAA==.Euli:BAAALgAFFAEJAQAAAA==.',
Ev='Evenin:BAAALgADCgIJAgAAAA==.',
Ex='Exoncantotem:BAAALgADCgQJBAAAAA==.',
Fa='Faenor:BAAALgAECgUJDQAAAA==.Fallen:BAAALgAECgkJCQAAAA==.Faynor:BAABLgAECn9DAAMYAAkJdxiIAAB6AQAYAAkJdxiIAAB6AQALAAYJbROyNQAsAQAAAA==.Faynór:BAAALgAECgcJCwABLgAECgkJQwAYAHcYAA==.',
Fe='Feloni:BAAALgAECgMJAwAAAA==.',
Fi='Finalone:BAAALgAECgEJAQAAAA==.Firêfly:BAAALgAECggJEwAAAA==.',
Fk='Fknsteve:BAAALgADCgYJBgAAAA==.',
Fl='Flaptix:BAAALgAECgMJAwAAAA==.Flipingflerp:BAAALgAECgcJEQAAAA==.Flloran:BAAALgAECgYJCwAAAA==.Floragoth:BAAALgAECgEJAQAAAA==.Flowers:BAAALgADCgkJCQAAAA==.Fluffboi:BAABLgAECn81AAILAAkJbwpKLwBMAQALAAkJbwpKLwBMAQAAAA==.',
Fo='Fourloko:BAAALgAECgEJAQAAAA==.Foxyblue:BAABLgAECn8UAAIWAAYJTBV3NABtAQAWAAYJTBV3NABtAQAAAA==.',
Fr='Fraggle:BAECLgAFFH8OAAMKAAQJHxH7KQDXAAAKAAQJHxH7KQDXAAAJAAMJUwlFeQDDAAAuAAQKfycAAwoACAl+IBsLAMcCAAoACAl+IBsLAMcCAAkABAmtEETWAOsAAAAA.Freefromfate:BAAALgAECgEJAQAAAA==.Frogchi:BAAALgAECgcJDgAAAA==.Frostbité:BAABLgAECn83AAIPAAkJ0B/QAwDPAgAPAAkJ0B/QAwDPAgAAAA==.Fruit:BAABLgAECn8ZAAIZAAYJIBRJFwDpAAAZAAYJIBRJFwDpAAAAAA==.',
Fu='Fuknak:BAAALgAECgIJAwAAAA==.Fumikiko:BAAALgADCgIJAgABLgAFFAMJBwAIAO4UAA==.Furrykarg:BAAALgAECgEJAQABLgAECgQJBgAMAAAAAA==.',
['Fà']='Fàynor:BAAALgAECggJEgABLgAECgkJQwAYAHcYAA==.',
['Fí']='Físh:BAAALgADCgYJBgABLgAFFAMJBwAIAO4UAA==.',
['Fú']='Fúzzy:BAAALgADCgEJAgABLgAECgIJAgAMAAAAAA==.',
Ga='Gakkle:BAABLgAECn8gAAIEAAkJAhrHAQADAQAEAAkJAhrHAQADAQAAAA==.Galadralvia:BAABLgAECn8cAAIUAAkJ2xGnEgDBAQAUAAkJ2xGnEgDBAQAAAA==.Gali:BAAALgAECgcJEgAAAA==.Ganaan:BAAALgAECgEJAwAAAA==.',
Ge='Gearsofbob:BAAALgAFFAIJBAAAAA==.Gekkle:BAAALgADCgUJBQAAAA==.',
Gh='Ghorn:BAAALgAECgEJAQAAAA==.Ghoulei:BAABLgAECn82AAICAAkJzx+3GgCmAgACAAkJzx+3GgCmAgAAAA==.',
Gi='Girlscout:BAEALgAECgYJBgABLgAFFAQJDgAKAB8RAA==.',
Gl='Glaistiguain:BAAALgAECgYJCwABLgAECggJNAACAJogAA==.Glenheals:BAAALgADCgkJEgAAAA==.Glifin:BAAALgAECgcJDgAAAA==.Gloomstalkin:BAABLgAECn8/AAIdAAkJNhd+DgBCAgAdAAkJNhd+DgBCAgAAAA==.Glorp:BAACLgAFFH8UAAILAAQJRR62DABdAQALAAQJRR62DABdAQAuAAQKfxwAAwsACQmWHxMIAMYCAAsACQmWHxMIAMYCABwAAQm5FK+zAD0AAAAA.',
Gn='Gnøsis:BAAALgADCggJEQAAAA==.',
Go='Goldìelocks:BAAALgAECgUJCAAAAA==.Gom:BAAALgAECgIJAgAAAA==.Gomdrog:BAAALgAECgEJAQAAAA==.',
Gr='Gr:BAABLgAECn8mAAIeAAcJVA2/DgA4AQAeAAcJVA2/DgA4AQAAAA==.Grannecs:BAAALgADCgEJAQAAAA==.Greenygreen:BAAALgAECgEJAQAAAA==.Grimmli:BAAALgADCgEJAQAAAA==.Grizelda:BAAALgADCgQJBAAAAA==.Grizzledpaw:BAAALgAECgUJDAAAAA==.Gromcresh:BAAALgAECgUJBQAAAA==.Gryffs:BAABLgAECn86AAMUAAkJ3CCfBQC8AgAUAAkJ3CCfBQC8AgAVAAEJ1Aq3gAApAAAAAA==.',
Gu='Gum:BAAALgAECgcJBwABLgAECgkJNQAPAK0gAA==.Gutts:BAABLgAECn8nAAQUAAkJDSLfBQC0AgAUAAkJDSLfBQC0AgAVAAcJ3BKsLQATAQAEAAQJ0Q7wfQDFAAAAAA==.',
Ha='Hadron:BAAALgAECgQJCQAAAA==.Hahkoa:BAAALgADCgMJAwAAAA==.Halomea:BAAALgADCgQJBAAAAA==.Hanukira:BAAALgADCgUJBQAAAA==.Happi:BAAALgAECgYJCQABLgAFFAcJIgARADAkAA==.Happyhour:BAAALgAECgYJBgABLgAFFAcJIgARADAkAA==.Harald:BAABLgAECn8gAAMCAAkJ+A5uBgCWAAAGAAIJ4hsuPQCbAAACAAkJpAxuBgCWAAAAAA==.Harkle:BAAALgADCgcJDQAAAA==.Haruun:BAAALgAECgIJAgAAAA==.',
He='Healyoself:BAAALgAECggJCQAAAA==.Heliõs:BAAALgAECgEJAQAAAA==.Hesmydaddy:BAABLgAECn86AAIWAAkJhguTKQB7AQAWAAkJhguTKQB7AQAAAA==.',
Ho='Honcho:BAAALgAECgEJAQAAAA==.Honestie:BAAALgAECgQJCgAAAA==.Honêy:BAEALgAFFAIJAQABLgAECgkJJAAbAPwbAA==.Hotdogstand:BAACLgAFFH8XAAITAAgJWyI4CAAlAgATAAgJWyI4CAAlAgAuAAQKfzEABBMACQlwJQcDACADABMACQlwJQcDACADAB4ABAmEIYELAHMBAB8AAQkrIq4eAFgAAAAA.',
Hu='Hukan:BAAALgAECgIJAgAAAA==.Huzzaah:BAEALgAECgcJEwABLgAFFAQJDgAKAB8RAA==.',
Hy='Hyperius:BAAALgADCgIJAgAAAA==.',
['Hö']='Höneÿdew:BAABLgAECn8ZAAINAAgJ9Bg2LAADAgANAAgJ9Bg2LAADAgAAAA==.',
Ic='Icemann:BAAALgAECgEJAgAAAA==.',
Il='Ilidrayssel:BAABLgAECn8aAAIXAAcJbQNGIACuAAAXAAcJbQNGIACuAAAAAA==.Illida:BAAALgAECgMJCQAAAA==.Illidad:BAAALgAECgQJBAAAAA==.',
Im='Imhappy:BAAALgAECgUJCgABLgAFFAcJIgARADAkAA==.Imherdaddy:BAAALgADCgYJCAABLgAECgkJPwAdADYXAA==.',
In='Indracus:BAAALgAECgQJCQAAAA==.Innervape:BAAALgADCgMJAwAAAA==.',
Ir='Ironfay:BAAALgAECgIJAgABLgAECgkJQwAYAHcYAA==.',
Ja='Jacorict:BAABLgAECn8UAAIJAAYJJws80wDuAAAJAAYJJws80wDuAAAAAA==.Jagga:BAAALgADCgMJAwAAAA==.Jarrack:BAABLgAECn8zAAIDAAkJ1RyyHwCgAgADAAkJ1RyyHwCgAgAAAA==.',
Je='Jellyhawk:BAAALgAECgEJAQAAAA==.Jessicae:BAAALgAECggJEAAAAA==.Jeuno:BAAALgAECgYJBwABLgAFFAMJBwAIAO4UAA==.',
Jo='Josephd:BAAALgADCgEJAQABLgAECggJPgAFABwcAA==.Josephedd:BAABLgAECn8+AAIFAAgJHBwXEwA8AgAFAAgJHBwXEwA8AgAAAA==.',
Ju='Judgment:BAAALgAECgEJAQAAAA==.Jukk:BAABLgAECn8iAAIDAAkJMAevhABuAQADAAkJMAevhABuAQAAAA==.Junazeena:BAABLgAECn8yAAMbAAkJLAlkOwBIAQAbAAkJLAlkOwBIAQABAAIJCgKV0gA4AAAAAA==.',
Jy='Jygglypuff:BAAALgAECgUJBQAAAA==.',
Ka='Kaji:BAABLgAECn8jAAIcAAYJSROoRQBVAQAcAAYJSROoRQBVAQAAAA==.Kalistus:BAAALgAECgEJAgAAAA==.Kargfu:BAAALgAECgQJBgAAAA==.Karolat:BAAALgAECgUJBgAAAA==.Kayfabe:BAABLgAECn8bAAIDAAkJ3QNz+gAGAQADAAkJ3QNz+gAGAQAAAA==.Kayfay:BAAALgAECgMJAwAAAA==.Kazz:BAAALgAECgQJBAAAAA==.',
Ke='Keishilda:BAABLgAECn8WAAMgAAUJXQl3UwCzAAAgAAQJOwt3UwCzAAAQAAUJGwMmbABuAAAAAA==.Keladria:BAAALgAECgQJBwAAAA==.Kelirra:BAAALgADCgQJCAAAAA==.Kelvyren:BAAALgADCgEJAQAAAA==.Kenel:BAABLgAECn83AAMSAAkJhBcqGgB0AgASAAkJhBcqGgB0AgAFAAUJcRHxUADKAAAAAA==.Kerea:BAABLgAECn9DAAMSAAkJkgkcAQBVAQASAAkJkgkcAQBVAQAFAAMJAQsFZwCCAAAAAA==.Kerob:BAAALgAECgMJBAAAAA==.',
Kh='Khazargon:BAAALgAECgQJCgAAAA==.',
Ki='Kicken:BAABLgAECn9GAAQaAAkJBR1kFgCeAgAaAAgJRBtkFgCeAgAZAAMJihkmPwC4AAAhAAEJxB/xLwBfAAAAAA==.Kitschy:BAAALgADCgEJAQAAAA==.Kittyperry:BAAALgAECgQJBAAAAA==.',
Kn='Knome:BAABLgAECn8zAAIDAAkJwh4RHQCuAgADAAkJwh4RHQCuAgAAAA==.',
Ko='Koana:BAAALgAECgkJCwAAAA==.Kororin:BAAALgAECgMJAwAAAA==.Korthelan:BAABLgAECn82AAIRAAkJDBJXPADWAQARAAkJDBJXPADWAQAAAA==.Kothara:BAABLgAECn84AAINAAkJThd7KAA9AgANAAkJThd7KAA9AgAAAA==.Kotongar:BAAALgADCgMJAwAAAA==.',
Kr='Kreeoo:BAAALgAECgIJAgAAAA==.Krimzin:BAACLgAFFH8aAAINAAUJMCGbJABzAQANAAUJMCGbJABzAQAuAAQKfx8AAw0ACAnfIZQhADwCAA0ACAnfIZQhADwCAB0AAgkaEHldAD4AAAAA.Krystine:BAABLgAECn8cAAISAAYJRhfiTwBPAQASAAYJRhfiTwBPAQAAAA==.',
Ks='Kserasera:BAABLgAFFH8IAAIFAAMJshIVBAC4AAAFAAMJshIVBAC4AAAAAA==.',
Ku='Kuball:BAAALgAECgYJCgABLgAECgkJJwAUAA0iAA==.Kukuruku:BAABLgAECn8WAAIbAAgJCAzoPQA9AQAbAAgJCAzoPQA9AQAAAA==.',
['Kì']='Kìssofdeath:BAAALgAECgUJBQAAAA==.',
['Kî']='Kîllara:BAABLgAECn8pAAIBAAkJrhW3KQAWAgABAAkJrhW3KQAWAgAAAA==.',
La='Labialicious:BAAALgAECgEJAgAAAA==.Lanfeår:BAABLgAECn8VAAICAAYJCwjD4ADTAAACAAYJCwjD4ADTAAAAAA==.Lanskies:BAABLgAECn8ZAAICAAkJPRXKMgAzAgACAAkJPRXKMgAzAgAAAA==.',
Le='Leafymeds:BAAALgAECgYJEAABLgAECgkJSQABAHcbAA==.Lebronjames:BAABLgAFFH8FAAICAAMJdhp9fwAIAQACAAMJdhp9fwAIAQAAAA==.Leiluna:BAAALgADCgkJEQAAAA==.Letheos:BAAALgAFFAMJAwAAAA==.',
Li='Libertinne:BAABLgAECn8cAAIEAAgJMxevMwB8AQAEAAgJMxevMwB8AQAAAA==.Librarte:BAABLgAECn85AAIJAAkJNw2FbACVAQAJAAkJNw2FbACVAQAAAA==.Ligmanuts:BAAALgAECgIJBAAAAA==.Lija:BAAALgAECgYJBgABLgAECgkJIgADADAHAA==.Lillytrae:BAAALgAECgMJBQAAAA==.Lilmeds:BAABLgAECn8XAAMgAAkJ+QcGLgBqAQAgAAkJxwcGLgBqAQAWAAgJBQRNQADtAAABLgAECgkJSQABAHcbAA==.Listie:BAAALgADCgQJBAABLgAECgQJBAAMAAAAAA==.Litty:BAABLgAECn8oAAIDAAcJASX/KwBpAgADAAcJASX/KwBpAgAAAA==.Lizrdkng:BAAALgADCgMJBgAAAA==.',
Lo='Locktärd:BAACLgAFFH8MAAQhAAQJiBsVBgAiAQAhAAQJiBsVBgAiAQAaAAIJShYXMwCtAAAZAAIJogaEDgCXAAAuAAQKfyoABCEACAmIH6oCAJACACEACAk+H6oCAJACABoACAktGRZCAAYCABkAAgkLHIJGAJwAAAAA.Lohken:BAAALgAECgMJCQAAAA==.Loralila:BAAALgAECgQJBAABLgAECgkJHAAUANsRAA==.Lox:BAABLgAECn9NAAMZAAkJQRodAAAkAgAZAAkJQRodAAAkAgAaAAIJFQSdJgFCAAAAAA==.',
Lu='Lucieb:BAAALgAECgEJAQAAAA==.',
Ly='Lydirn:BAABLgAECn8gAAQJAAkJ+RxuQAAFAgAJAAgJ3x1uQAAFAgAKAAQJzRVpVQDiAAAPAAIJoByjMQCfAAAAAA==.Lyofel:BAAALgAECgYJDwAAAA==.Lyonel:BAAALgADCggJCAAAAA==.Lysaviel:BAAALgAECgEJAgAAAA==.',
['Lí']='Lítterbox:BAABLgAFFH8GAAIOAAMJzAnqAADXAAAOAAMJzAnqAADXAAAAAA==.',
Ma='Magedzen:BAAALgAECgMJBAAAAA==.Magicguy:BAABLgAECn8bAAIDAAkJZw80VQDdAQADAAkJZw80VQDdAQAAAA==.Mahariel:BAABLgAECn8vAAINAAkJ/RD4PgDmAQANAAkJ/RD4PgDmAQAAAA==.Mahdy:BAABLgAECn9FAAIJAAkJGR3HJAByAgAJAAkJGR3HJAByAgAAAA==.Mahoe:BAAALgAECgQJBgAAAA==.Maivel:BAAALgAECgcJCAAAAA==.Manandaar:BAAALgAECgIJBAAAAA==.Mandret:BAAALgAECgMJBAABLgAECgkJKAAKALsQAA==.Manicppanic:BAEBLgAECn8gAAITAAgJxxVoHQCrAQATAAgJxxVoHQCrAQABLgAFFAQJDgAKAB8RAA==.Manrypurp:BAAALgAECgUJDQAAAA==.Marcie:BAABLgAECn9HAAIFAAkJ1ROHAADKAQAFAAkJ1ROHAADKAQAAAA==.Martinriggz:BAAALgAECgMJBgAAAA==.',
Mc='Mchammer:BAAALgAECgEJAQAAAA==.',
Me='Meatyloaf:BAABLgAECn8eAAIHAAkJcwTjHgDVAAAHAAkJcwTjHgDVAAAAAA==.Melkedrik:BAABLgAECn8aAAIiAAkJ4Q2QJABTAQAiAAkJ4Q2QJABTAQAAAA==.Melleren:BAAALgAECgYJCQAAAA==.Messande:BAAALgAECgUJBgAAAA==.',
Mi='Minõs:BAAALgADCgkJEAAAAA==.Mirai:BAAALgADCgUJBQAAAA==.Mirei:BAABLgAECn9GAAIWAAkJ5w3fAQDcAAAWAAkJ5w3fAQDcAAAAAA==.Mistdancer:BAAALgADCgYJBgABLgAFFAIJCAAHAI0GAA==.Mitsurugi:BAAALgAECgEJAgABLgAFFAIJCAAHAI0GAA==.Miyagí:BAAALgAECgcJDgABLgAECggJGAAGAKYdAA==.',
Mo='Mochisama:BAAALgAECgYJCAAAAA==.Mojam:BAAALgAECgQJDwAAAA==.Monk:BAAALgAECgEJAQAAAA==.Monkadzen:BAAALgAECgEJBAAAAA==.Moonless:BAAALgAECgEJAgAAAA==.Moovidlin:BAABLgAECn8XAAIEAAkJBQtcNQBzAQAEAAkJBQtcNQBzAQABLgAECgkJIgADADAHAA==.Mordian:BAAALgAECgYJBgAAAA==.Morinnas:BAAALgAECgMJBAAAAA==.Moschpit:BAAALgADCgEJAQAAAA==.',
Mu='Munkeez:BAAALgADCgMJAwAAAA==.Murdermoo:BAAALgADCgMJAwAAAA==.Murkessa:BAAALgAECgQJBwAAAA==.Mushhead:BAAALgAECgUJCAAAAA==.Mustepin:BAAALgAECgQJBAABLgAFFAQJDwAEAEobAA==.',
My='Myishaa:BAAALgADCgIJAgAAAA==.Mykeal:BAAALgADCgMJBQAAAA==.Mystryl:BAAALgADCgkJEQAAAA==.Mythantherox:BAABLgAFFH8HAAIVAAMJrR1eHAAJAQAVAAMJrR1eHAAJAQABLgAFFAYJFAAjAGgWAA==.',
['Mì']='Mìstra:BAAALgADCgUJBwAAAA==.',
Na='Nanlaria:BAAALgAECgEJAgAAAA==.Nargo:BAAALgADCgYJCgAAAA==.Nataliia:BAAALgAECgQJBAAAAA==.',
Ne='Necrostalker:BAAALgADCgkJCQABLgADCgEJAQAMAAAAAA==.Negative:BAAALgAECgQJCgAAAA==.Neltherius:BAAALgAECgEJAQAAAA==.Nerwende:BAAALgAECgEJAQAAAA==.Nethershade:BAABLgAECn88AAIeAAkJNx3UAgCdAgAeAAkJNx3UAgCdAgAAAA==.Netherstörm:BAAALgAECgcJCgAAAA==.Nezot:BAAALgAECgEJAQABLgAECgkJGQACACERAA==.',
Ni='Niclea:BAAALgAECgQJBAAAAA==.Nightelm:BAACLgAFFH8HAAQIAAMJ7hQ6QgC+AAAIAAMJ7hQ6QgC+AAAjAAEJnBKqDQBIAAAkAAEJZgQCMAAmAAAuAAQKfysABAgACQltHw0LAKgCAAgACQlnHw0LAKgCACQABgleDBY0AM0AACMABAn3G3UZAIkAAAAA.Niënor:BAABLgAECn8iAAIcAAgJvhq8FgBkAgAcAAgJvhq8FgBkAgAAAA==.',
Nj='Njorvir:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.',
No='Noslien:BAAALgAECgUJBwAAAA==.Nostradamuz:BAAALgAECgEJAQAAAA==.Novasong:BAAALgAECgEJAwAAAA==.',
Ny='Nymneria:BAABLgAECn8UAAIZAAgJmAmBFgDyAAAZAAgJmAmBFgDyAAAAAA==.Nyxstonia:BAACLgAFFH8aAAIUAAQJvxg6AgDLAAAUAAQJvxg6AgDLAAAuAAQKfz8AAhQACQnSHXwIAHICABQACQnSHXwIAHICAAAA.',
Ob='Oballi:BAAALgAECgUJBwAAAA==.',
Od='Oddsaint:BAAALgAECgEJAwAAAA==.',
Ol='Olierra:BAAALgAECgYJDAAAAA==.',
On='Onlyvoids:BAAALgAECgMJAwAAAA==.',
Or='Orhan:BAAALgAECgQJBAABLgAECgkJQwAYAHcYAA==.Ornac:BAAALgADCgcJDQAAAA==.',
Ot='Otkspring:BAACLgAFFH8HAAMEAAMJHwosPQC5AAAEAAMJZggsPQC5AAAVAAEJPwedQwBAAAAuAAQKfxkAAgQABwmAF/gtAJkBAAQABwmAF/gtAJkBAAAA.Otto:BAABLgAECn8pAAIJAAkJ2hHMXwCxAQAJAAkJ2hHMXwCxAQAAAA==.Ottomagus:BAABLgAECn8cAAIDAAkJ3RNPAQC/AQADAAkJ3RNPAQC/AQAAAA==.',
Ox='Oxadin:BAAALgAECgEJAQAAAA==.Oxideous:BAAALgADCgMJAwAAAA==.',
Pa='Paleale:BAABLgAECn8VAAIbAAYJ7wzpXQDLAAAbAAYJ7wzpXQDLAAAAAA==.Pallyshore:BAAALgADCgMJAwAAAA==.Pampoovy:BAEALgADCgMJAwABLgAECgkJEQAMAAAAAA==.Pandapunk:BAAALgAECggJDgAAAA==.Panic:BAAALgADCgEJAQAAAA==.Pantoponrose:BAAALgAECgYJEQAAAA==.Pastorbash:BAAALgADCggJCQAAAA==.',
Pb='Pb:BAAALgAECgMJAwAAAA==.',
Pe='Persephoneia:BAABLgAECn8kAAIQAAkJYxFzIgC0AQAQAAkJYxFzIgC0AQAAAA==.',
Pi='Pitnick:BAAALgAECgIJAgAAAA==.',
Pk='Pkashmuk:BAAALgADCgcJBwAAAA==.',
Pr='Prophettool:BAABLgAECn8oAAMJAAkJlAsKgwBpAQAJAAkJlAsKgwBpAQAKAAQJigQEfQCGAAAAAA==.Pruned:BAAALgADCgcJBwABLgAFFAQJDAAhAIgbAA==.',
Pu='Punjistake:BAAALgAECgYJBgAAAA==.',
['Pï']='Pïzzasteve:BAAALgADCgEJAQABLgAFFAEJAQAMAAAAAA==.',
Qu='Quanchii:BAAALgADCgMJAwAAAA==.Quna:BAAALgADCgQJBAAAAA==.',
Ra='Raemie:BAAALgAECgQJCQAAAA==.Ragequit:BAABLgAECn8WAAIUAAgJwhfGFACmAQAUAAgJwhfGFACmAQABLgAECggJKgAGACsZAA==.Raikoho:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.Rakulm:BAAALgADCgUJCgAAAA==.Ravenloare:BAAALgAECgMJAwAAAA==.Ravenrest:BAEBLgAECn8vAAIQAAgJqx7HEgA8AgAQAAgJqx7HEgA8AgAAAA==.',
Re='Reaverheim:BAABLgAECn8ZAAQUAAYJAx8RFgCWAQAUAAYJYx4RFgCWAQAEAAQJfxcqZQAeAQAVAAIJBR0iSgCkAAAAAA==.Rehab:BAAALgAFFAEJAQABLgAECggJKgAGACsZAA==.Reiko:BAAALgADCgkJIQABLgAECgkJRgAWAOcNAA==.Remuz:BAAALgAECgUJCwAAAA==.Rennwick:BAAALgAECgQJBgAAAA==.Renriss:BAAALgAECgcJCQABLgAECggJOAAGAJgYAA==.Rey:BAAALgAECgYJBgAAAA==.',
Rh='Rhe:BAAALgAECgIJAgABLgAECgYJBgAMAAAAAA==.',
Ri='Rilz:BAABLgAECn8qAAICAAkJ3SDlHQCUAgACAAkJ3SDlHQCUAgAAAA==.',
Ro='Rochambeu:BAAALgADCgEJAQAAAA==.Rockasham:BAAALgAECgQJCgAAAA==.Rockyrogue:BAAALgAECgEJAQAAAA==.Rodgerwabbet:BAAALgAECgQJBAAAAA==.Roiddemon:BAAALgADCgQJBAABLgAECggJKwAaABcUAA==.Roiddrood:BAAALgAECgIJAgABLgAECggJKwAaABcUAA==.Roidlock:BAABLgAECn8rAAIaAAgJFxRoVgCZAQAaAAgJFxRoVgCZAQAAAA==.Roidtank:BAAALgAECgUJDAABLgAECggJKwAaABcUAA==.Rongyi:BAAALgADCgIJAgAAAA==.Rosaline:BAAALgAECgYJDgAAAA==.Rosewood:BAAALgAECgkJBwAAAA==.Rottn:BAABLgAECn8qAAMGAAgJKxkcAQAiAQAGAAgJKxkcAQAiAQACAAEJrgPZnQEhAAAAAA==.Rottyn:BAABLgAECn8WAAIPAAgJDRZjAAC9AQAPAAgJDRZjAAC9AQABLgAECggJKgAGACsZAA==.',
Ru='Runerion:BAAALgAECgEJBQAAAA==.',
Ry='Ry:BAAALgAECgYJBQABLgAECgYJBgAMAAAAAA==.',
['Rà']='Ràìn:BAABLgAECn8WAAIDAAgJAgnpoQA4AQADAAgJAgnpoQA4AQAAAA==.',
Sa='Sacrothoth:BAAALgAECgEJAgAAAA==.Safmen:BAABLgAECn8bAAQUAAYJwQdqNgCeAAAUAAYJjAdqNgCeAAAVAAMJMgXlaQBOAAAEAAEJCAr0ogA9AAAAAA==.Sanikoa:BAAALgAECgQJCQAAAA==.Saraid:BAABLgAECn8tAAQSAAkJ9RgHFwCOAgASAAkJ9RgHFwCOAgAFAAMJZxAUYQCdAAAlAAIJvQUMeAAtAAAAAA==.Saravase:BAABLgAECn8WAAIBAAYJMgkngQDeAAABAAYJMgkngQDeAAAAAA==.Sardel:BAAALgADCgcJBwAAAA==.Sargeros:BAAALgAECgQJBQAAAA==.Sazem:BAAALgADCgIJAgAAAA==.',
Se='Sedaldra:BAAALgADCgYJCwAAAA==.',
Sh='Shadowi:BAAALgAECgQJBQAAAA==.Shadownights:BAABLgAECn84AAIQAAkJNRdiEwA2AgAQAAkJNRdiEwA2AgAAAA==.Shadowpope:BAAALgAECgkJBgAAAA==.Shamoneyy:BAAALgADCgUJBQAAAA==.Shazi:BAEBLgAECn8kAAMbAAkJ/BuPEgBbAgAbAAkJ/BuPEgBbAgAmAAEJ8Ao1LAA1AAABLgAECgkJJAAbAPwbAA==.Shiki:BAAALgADCgkJEwABLgAECgkJRgAWAOcNAA==.Shimnar:BAAALgAECggJEwABLgAECggJHAAEADMXAA==.Shinifur:BAAALgADCgUJBgAAAA==.Shinoto:BAABLgAECn8ZAAMDAAYJISAyWgDPAQADAAYJISAyWgDPAQAnAAEJDxXQEgA/AAAAAA==.Shiritá:BAAALgAECgMJAgAAAA==.Shockazam:BAAALgAECgcJEgAAAA==.Shrewby:BAAALgAECgEJAQAAAA==.Shyandra:BAAALgADCgYJBgAAAA==.',
Si='Sieghart:BAAALgAECgEJAwAAAA==.Six:BAAALgAECgUJCwABLgAFFAEJAQAMAAAAAA==.',
Sk='Skylines:BAAALgAECgQJBAAAAA==.',
Sl='Sloptop:BAAALgAECgEJAgAAAA==.',
Sn='Snarkyshaman:BAAALgAECgQJBAABLgAECggJKgAGACsZAA==.Snickersbar:BAAALgADCgUJCAAAAA==.Snowynn:BAAALgAECgYJEAAAAA==.Snöw:BAABLgAECn8pAAIDAAkJGhVhQQAYAgADAAkJGhVhQQAYAgAAAA==.Snöwy:BAAALgAECgQJBAAAAA==.',
So='Sojudevourer:BAAALgAECgEJAQAAAA==.Southpaw:BAAALgAECgMJAwAAAA==.',
Sp='Spooki:BAAALgAECgEJAQAAAA==.Spyro:BAABLgAECn8uAAQIAAkJ1A59GgD2AQAIAAkJ1A59GgD2AQAkAAgJABMsEQC4AQAjAAIJYw5CIwA/AAAAAA==.',
Sr='Sron:BAABLgAECn8oAAINAAgJKB9rPQDrAQANAAgJKB9rPQDrAQAAAA==.',
St='Stabalagmite:BAAALgAECgMJAwABLgAECggJKgAGACsZAA==.Stariah:BAABLgAECn8kAAIDAAgJPgtrjQBcAQADAAgJPgtrjQBcAQAAAA==.Stawn:BAAALgADCgEJAQAAAA==.',
Su='Sumwhiteguy:BAAALgAECgEJAQAAAA==.',
Sw='Sweetbeef:BAAALgAECgIJAgAAAA==.Swooze:BAACLgAFFH8NAAIDAAQJHheTUgA4AQADAAQJHheTUgA4AQAuAAQKfzsAAgMACQndHVMcALICAAMACQndHVMcALICAAAA.',
Sy='Sylrythriana:BAABLgAECn8ZAAMTAAcJfwStNQD/AAATAAcJfwStNQD/AAAeAAIJCwIHKQAxAAABLgAECgkJHAAUANsRAA==.Syndicate:BAAALgAECgcJDQAAAA==.Syrenis:BAAALgADCgkJDwABLgAFFAMJBwAIAO4UAA==.',
['Sù']='Sùnnydk:BAAALgADCgcJBwAAAA==.',
Ta='Tahoe:BAAALgADCgYJBgABLgAFFAUJIQARACEbAA==.Talwaz:BAAALgADCgkJDgAAAA==.Tankinbur:BAAALgAECgYJDQAAAA==.Tanzri:BAAALgAECgMJAwAAAA==.Tarlyn:BAACLgAFFH8MAAIKAAMJCg2yNACcAAAKAAMJCg2yNACcAAAuAAQKfzQABAoACQkRF28XAE4CAAoACQkRF28XAE4CAAkABglcGoyOAFUBAA8AAQkAANI/AD4AAAAA.Tatslight:BAABLgAECn8xAAIPAAgJBRx/CwAPAgAPAAgJBRx/CwAPAgABLgAECggJMQAPAAUcAA==.Tatsrage:BAAALgAECgEJAQABLgAECggJMQAPAAUcAA==.Tazaral:BAAALgADCgEJAQABLgAECgkJCwAMAAAAAA==.',
Te='Ted:BAEBLgAFFH8GAAISAAQJ7AsNNADdAAASAAQJ7AsNNADdAAABLgAFFAQJDgAKAB8RAA==.Temuadêrna:BAAALgAECgQJBAAAAA==.Teysá:BAAALgADCgEJAQAAAA==.',
Th='Thalasso:BAAALgADCgEJAgAAAA==.Thor:BAAALgAECgYJCAAAAA==.Thyandris:BAAALgADCgYJCwAAAA==.Thánátós:BAAALgAECgQJBwAAAA==.',
Ti='Timmthemage:BAAALgAECgUJBwABLgAECgEJAQAMAAAAAQ==.Timthepally:BAAALgAECggJDAABLgAECgEJAQAMAAAAAQ==.Tinytex:BAABLgAECn8oAAIYAAkJyw7SIwCMAQAYAAkJyw7SIwCMAQAAAA==.Tisiphoneia:BAAALgAECgQJBgAAAA==.',
To='Toberson:BAAALgAECgEJAQAAAA==.Tom:BAAALgAECgQJBAAAAA==.Toxicbanana:BAABLgAECn8VAAIEAAYJeg9RAgDRAAAEAAYJeg9RAgDRAAAAAA==.',
Tr='Tradarynn:BAABLgAECn8fAAIJAAkJ7huiIACEAgAJAAkJ7huiIACEAgAAAA==.Trayvein:BAAALgADCgUJBQAAAA==.Trekk:BAAALgAECgcJBQAAAA==.Tress:BAABLgAECn8UAAImAAYJLx5ZEgCQAQAmAAYJLx5ZEgCQAQAAAA==.',
Ts='Tsindre:BAAALgAECgEJAgAAAA==.Tsukong:BAAALgAECgEJAQAAAA==.',
Tu='Tulkar:BAAALgAECgIJAgAAAA==.Turambar:BAAALgAECgEJAQAAAA==.',
Ty='Tyriir:BAAALgADCgMJAwAAAA==.Tyviae:BAAALgAECgIJAgAAAA==.',
Um='Umbrax:BAAALgAECgQJBQAAAA==.',
Un='Unholymochi:BAABLgAECn8lAAICAAkJHiAdWwC1AQACAAkJHiAdWwC1AQAAAA==.',
Uw='Uwuzi:BAAALgADCgQJBAAAAA==.',
Va='Valhalia:BAABLgAECn8UAAMaAAgJ6ReDcgBVAQAaAAYJKBiDcgBVAQAZAAMJbg6pQgCqAAAAAA==.Vanyllapea:BAAALgAECgMJAwAAAA==.Varaelitha:BAAALgAECgMJAwAAAA==.Vashan:BAAALgAECgQJBQAAAA==.Vashni:BAAALgAECgkJDAAAAA==.',
Ve='Velinariae:BAAALgADCgYJEAAAAA==.Vengful:BAABLgAECn8vAAMiAAkJNh3tCACcAgAiAAkJNh3tCACcAgAoAAIJoBd+JAB7AAAAAA==.',
Vi='Vira:BAAALgAECgIJAgAAAA==.Vivy:BAABLgAECn8fAAQaAAkJNhThLwBNAgAaAAkJzRPhLwBNAgAZAAQJaxSaMwDpAAAhAAIJBhXMJgBWAAAAAA==.',
Vo='Vord:BAAALgAECgIJAgAAAA==.Vorumbrae:BAAALgAECgYJCAAAAA==.',
Vu='Vultus:BAAALgAECgIJAgAAAA==.',
Vy='Vylthyra:BAAALgADCgEJAQABLgAECggJKgAGACsZAA==.Vyrkin:BAAALgAECgEJAQAAAA==.Vyrul:BAAALgADCgQJBAABLgAECgQJBAAMAAAAAA==.',
['Vä']='Väntage:BAAALgADCgEJAQAAAA==.',
Wa='Wagyubeef:BAABLgAECn8kAAIEAAkJghdXIADtAQAEAAkJghdXIADtAQAAAA==.Wali:BAABLgAECn8gAAMaAAgJMRPLXQCFAQAaAAgJMRPLXQCFAQAZAAEJAAB9dgAuAAAAAA==.Warlodzen:BAAALgADCgcJBwAAAA==.',
We='Wenson:BAABLgAECn8ZAAMCAAkJIRHaRwDqAQACAAkJIRHaRwDqAQAGAAcJtwWFOQCtAAAAAA==.',
Wh='Whatupbruh:BAACLgAFFH8SAAMdAAQJ+RJ9AQACAQAdAAQJbxF9AQACAQANAAMJRxDUawDMAAAuAAQKfyQABB0ABwkcIh4HAIgCAB0ABwm5IR4HAIgCAA0AAQkJG04cAUAAABcAAQndBnKSACgAAAAA.',
Wi='Wildfire:BAAALgAECgcJBwAAAA==.',
Wo='Wooties:BAAALgAECgcJCgABLgAECgkJQgABAEYfAA==.',
Wy='Wyleriya:BAABLgAECn83AAIaAAkJggk9bQBhAQAaAAkJggk9bQBhAQAAAA==.',
Xa='Xanthas:BAAALgADCgQJBAAAAA==.',
Xc='Xcella:BAAALgAECgUJCAAAAA==.',
Xe='Xephon:BAAALgADCgcJBwAAAA==.',
Xi='Xina:BAAALgAECgEJAQAAAA==.',
Xw='Xweakling:BAAALgADCgYJCAABLgAFFAQJDwAEAEobAA==.',
Xy='Xyn:BAAALgADCggJCAABLgAECgYJBgAMAAAAAA==.',
Ya='Yamonu:BAAALgADCgEJAQAAAA==.',
Ye='Yelizaveta:BAABLgAECn8VAAINAAYJbwRUvADNAAANAAYJbwRUvADNAAAAAA==.',
Yl='Ylfcwen:BAAALgAECgEJAQAAAA==.',
Yo='Yodey:BAACLgAFFH8MAAICAAQJOB/hRABrAQACAAQJOB/hRABrAQAuAAQKfzEAAgIACQlwI54HADkDAAIACQlwI54HADkDAAAA.Yoovee:BAAALgAECggJCAAAAA==.',
Yu='Yuaetrende:BAACLgAFFH8OAAIiAAQJex4CDQBBAQAiAAQJex4CDQBBAQAuAAQKfzIAAiIACQlzI94DABMDACIACQlzI94DABMDAAAA.Yumii:BAABLgAECn8hAAMWAAkJPSUkAgCJAwAWAAkJECUkAgCJAwAgAAYJ/yH2DgBNAgAAAA==.',
Za='Zack:BAAALgAECgYJEwAAAA==.Zaerie:BAAALgADCgcJBwAAAA==.Zagul:BAAALgAECgUJCAAAAA==.Zalarah:BAAALgAECgUJDQAAAA==.Zalarilia:BAAALgAECgEJAQAAAA==.Zanoo:BAAALgADCgYJBwAAAA==.Zaphod:BAAALgAECgMJAwAAAA==.Zardan:BAABLgAECn8dAAIaAAgJtAvkcgBUAQAaAAgJtAvkcgBUAQAAAA==.',
Zi='Ziegler:BAAALgADCgYJBgAAAA==.',
Zu='Zuggasaurus:BAABLgAECn8eAAUOAAkJexg9CABMAgAOAAkJMRg9CABMAgAlAAUJoRU3IwA2AQAFAAYJGBM2AQAwAQASAAIJVg1sqQBhAAAAAA==.Zugglite:BAABLgAECn8oAAQKAAgJMCEyFwBYAgAKAAgJMCEyFwBYAgAPAAQJ2xotHwAaAQAJAAEJdgmAtAEoAAABLgAECgkJHgAOAHsYAA==.Zulthar:BAABLgAECn8aAAIDAAgJ8QoyrAAnAQADAAgJ8QoyrAAnAQAAAA==.',
['Äs']='Äshborn:BAABLgAECn8oAAICAAkJIQ57XwCqAQACAAkJIQ57XwCqAQAAAA==.Ästra:BAAALgADCggJCAAAAA==.',
['Æi']='Æix:BAEALgAECgEJAQABLgAFFAcJFgADANcPAA==.',
['Æl']='Ælxx:BAEALgAECgYJBwABLgAFFAcJFgADANcPAA==.',
['Ðe']='Ðeathless:BAAALgADCgUJBQAAAA==.',
['Øm']='Ømnium:BAABLgAECn80AAIJAAcJaAocuwAPAQAJAAcJaAocuwAPAQAAAA==.',
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
