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

local lookup = {'Shaman-Restoration','DeathKnight-Unholy','Mage-Frost','Warrior-Fury','Druid-Balance','DeathKnight-Blood','DeathKnight-Frost','Evoker-Augmentation','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','Shaman-Elemental','Shaman-Enhancement','Unknown-Unknown','Hunter-BeastMastery','Druid-Feral','Paladin-Protection','Hunter-Survival','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Warrior-Arms','Priest-Holy','Hunter-Marksmanship','Monk-Brewmaster','Warlock-Destruction','Warlock-Demonology','Rogue-Assassination','Monk-Mistweaver','Druid-Guardian','Rogue-Outlaw','DemonHunter-Vengeance','Priest-Discipline','Warlock-Affliction','DemonHunter-Havoc','Evoker-Devastation','Evoker-Preservation','Mage-Fire',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=46,date='2026-08-25',data={Ab='Abelas:BAAALgAECgYJCwAAAA==.Abracadavr:BAAALgAECgIJAgAAAA==.Abracadaxis:BAAALgADCggJCAAAAA==.',
Ad='Adallyn:BAAALgADCgYJCgAAAA==.Adzen:BAAALgAECgQJBQAAAA==.Adêrna:BAABLgAECn87AAIBAAkJzh8zAwCNAgABAAkJzh8zAwCNAgAAAA==.',
Af='Affliction:BAAALgADCgUJBQAAAA==.Aftermathz:BAAALgAECgMJAQAAAA==.',
Ag='Agba:BAABLgAFFH8PAAICAAQJRwaDiQD3AAACAAQJRwaDiQD3AAAAAA==.',
Ah='Ahktari:BAAALgADCgcJBwAAAA==.',
Al='Alaidan:BAAALgAECgkJDQAAAA==.Alanus:BAABLgAECn8rAAIDAAkJMBE5XADJAQADAAkJMBE5XADJAQAAAA==.Alarion:BAAALgAECgQJBwAAAA==.Alavia:BAABLgAECn8/AAIEAAkJfxg+GgAcAgAEAAkJfxg+GgAcAgAAAA==.Alderon:BAAALgAECgQJCAAAAA==.Alinäs:BAABLgAECn8hAAIDAAkJHQ/lYwC2AQADAAkJHQ/lYwC2AQAAAA==.Aliën:BAAALgADCgcJCQAAAA==.Alliumoo:BAABLgAECn8XAAIFAAYJwQkBRwASAQAFAAYJwQkBRwASAQAAAA==.Altana:BAABLgAECn8ZAAMGAAkJThN1HQBsAQAGAAkJNRB1HQBsAQAHAAMJSRXrIADGAAABLgAFFAMJBwAIAO4UAA==.Alydrus:BAACLgAFFH8FAAIDAAIJ1AY4qwB/AAADAAIJ1AY4qwB/AAAuAAQKfz0AAgMACQl/F9sNAIYBAAMACQl/F9sNAIYBAAAA.Alíen:BAAALgAECgQJBAAAAA==.',
Am='Amnesian:BAAALgAECgkJAgAAAA==.',
An='Anberlinean:BAABLgAECn8WAAIJAAYJ5geytAAbAQAJAAYJ5geytAAbAQAAAA==.Angryelf:BAAALgAECgEJAQAAAA==.Angzhixing:BAAALgADCgIJAgAAAA==.Anitasummon:BAAALgAECgEJAQAAAA==.Ankles:BAEALgADCgcJBwABLgAFFAQJDgAKAB8RAA==.Annahe:BAABLgAECn8YAAILAAkJjxs+EwAkAgALAAkJjxs+EwAkAgAAAA==.Annale:BAAALgAECgQJBQABLgAECgkJGAALAI8bAA==.Annatara:BAAALgAECgUJCwAAAA==.Anran:BAAALgADCgEJAQAAAA==.Anub:BAAALgADCgYJBgAAAA==.Anzala:BAAALgAECgkJEAAAAA==.',
Ao='Aoba:BAAALgAECgYJCwAAAA==.',
Ar='Arba:BAAALgAECgQJCAAAAA==.Areliss:BAAALgAECgUJBQAAAA==.Armsmaster:BAABLgAECn80AAICAAgJmiAqNQAqAgACAAgJmiAqNQAqAgAAAA==.Artemistha:BAAALgAECggJDwAAAA==.',
As='Asalynn:BAAALgADCgEJAQAAAA==.Asché:BAAALgAECgEJAgAAAA==.',
Av='Avalina:BAAALgAECgEJAQAAAA==.Avengharambe:BAAALgADCgcJBwAAAA==.Averan:BAAALgAECgYJEQAAAA==.Averybug:BAAALgAECgkJAQAAAA==.',
Az='Azarke:BAAALgAECgQJBQAAAA==.Azhkan:BAABLgAECn8kAAMMAAkJ/BuNEgBbAgAMAAkJ/BuNEgBbAgANAAEJ8Ao1LAA1AAAAAA==.',
Ba='Backbeamz:BAAALgAECgYJCQAAAA==.Backspace:BAAALgADCgYJBgAAAA==.Badgër:BAAALgAECgEJAQAAAA==.Baey:BAAALgADCgMJAwABLgAECgkJOwADAMIeAA==.Balduun:BAAALgAECgEJAwAAAA==.Barelycastin:BAABLgAECn8mAAIBAAcJLBiRCAC7AQABAAcJLBiRCAC7AQAAAA==.Bashdadargon:BAAALgAECgEJAQABLgAECgQJBQAOAAAAAA==.Bashoomba:BAAALgAECgQJBQAAAA==.',
Be='Bear:BAABLgAECn8gAAIPAAgJVSDBGQCLAgAPAAgJVSDBGQCLAgAAAA==.Bearnaked:BAAALgADCgIJAgAAAA==.Bebebluz:BAAALgAECgYJDgAAAA==.Beets:BAAALgAECgEJAQAAAA==.Belgarathh:BAAALgAFFAIJAgAAAA==.Bellíon:BAAALgAECgcJEgAAAA==.Belnoir:BAAALgADCgEJAQAAAA==.Beryline:BAAALgADCgEJAQAAAA==.',
Bi='Bird:BAAALgADCgEJAQAAAA==.Bison:BAAALgAECgMJAwABLgAECgEJAQAOAAAAAA==.Bixee:BAAALgAECgUJCQAAAA==.',
Bl='Blacat:BAABLgAECn84AAMQAAkJCSLrAQAWAwAQAAkJCSLrAQAWAwAFAAIJUAM/eABEAAAAAA==.Bleen:BAAALgAECgUJDAAAAA==.Blitzcomets:BAAALgAECgEJBAAAAA==.Blueday:BAAALgAECgUJBQAAAA==.',
Bo='Boagries:BAAALgADCgIJAgAAAA==.Bogeyman:BAABLgAECn81AAIRAAkJrSBsAwDeAgARAAkJrSBsAwDeAgAAAA==.Bonejovi:BAABLgAECn8xAAMGAAgJaxofBQB+AQAGAAgJaxofBQB+AQACAAEJrgPgnQEhAAABLgAECggJJQARAJgbAA==.Boondoks:BAABLgAECn8gAAIKAAcJTh0XIAADAgAKAAcJTh0XIAADAgABLgAECgkJQgABAEYfAA==.Borda:BAAALgAECggJCgAAAA==.Bosemaster:BAAALgADCgMJAwAAAA==.Bowrider:BAAALgAECgYJBwAAAA==.',
Br='Breer:BAAALgAECgcJCAAAAA==.Brondeadeye:BAAALgAECgUJBwAAAA==.Brunore:BAAALgAECgYJDAAAAA==.Brìan:BAABLgAECn8YAAMFAAgJ/BeTBgB3AQAFAAgJbhKTBgB3AQAQAAQJPxtuBAA8AQAAAA==.',
Bu='Bubbajüdd:BAAALgADCgEJAQAAAA==.Bubbleandout:BAAALgAECgEJAQABLgAECgkJPwASADYXAA==.',
Ca='Caledur:BAAALgAECgYJDAAAAA==.Caliandra:BAAALgAECgEJAQAAAA==.Caratdeullie:BAAALgAECggJCQAAAA==.Careblair:BAAALgADCgkJCQAAAA==.',
Ch='Chakrah:BAABLgAECn8YAAITAAcJ/gnZNQA9AQATAAcJ/gnZNQA9AQAAAA==.Challan:BAABLgAFFH8GAAIUAAMJtALNdwCSAAAUAAMJtALNdwCSAAAAAA==.Chimint:BAAALgAECgkJCQAAAA==.Chloe:BAABLgAECn8XAAIVAAkJ9AHJ1wAtAAAVAAkJ9AHJ1wAtAAAAAA==.Chrno:BAABLgAECn8YAAIVAAgJ5xEUNQDHAQAVAAgJ5xEUNQDHAQAAAA==.Chunkymonkey:BAAALgADCgYJBgABLgAFFAQJIQADABwRAA==.',
Ci='Cirilá:BAAALgAECgMJAQAAAA==.',
Cl='Cleric:BAAALgAECgYJCgAAAA==.Clutcha:BAABLgAECn8cAAIWAAYJKh3QKgBCAQAWAAYJKh3QKgBCAQAAAA==.Clutchcross:BAAALgAECgQJBgABLgAECgYJHAAWACodAA==.Clutchplate:BAABLgAECn8jAAMXAAgJKxTLFgCNAQAXAAgJKxTLFgCNAQAYAAEJWgZyhgAjAAAAAA==.Clûtch:BAACLgAFFH8gAAICAAUJISF1SABiAQACAAUJISF1SABiAQAuAAQKfyIAAgIACQliH+42AFsCAAIACQliH+42AFsCAAAA.',
Co='Codenameblue:BAAALgADCgEJAQAAAA==.Coldphoenix:BAAALgADCgkJCgAAAA==.Coog:BAAALgADCgEJAQAAAA==.Corynthe:BAABLgAECn9XAAIZAAkJLiRoAACLAwAZAAkJLiRoAACLAwAAAA==.',
Cr='Crickie:BAABLgAECn8UAAMBAAkJsReVSACMAQABAAgJ4ReVSACMAQAMAAIJ2RAcHQBhAAAAAA==.Crovaxis:BAABLgAECn8qAAMaAAkJlSEzCAD8AQAaAAgJ9yEzCAD8AQAPAAIJ/BPr4ACMAAAAAA==.',
Cu='Cursecackler:BAAALgADCgYJBgAAAA==.',
Cy='Cynda:BAAALgADCgMJAwAAAA==.Cyndestine:BAAALgADCgYJBgAAAA==.Cyzarius:BAAALgAECgEJAQAAAA==.',
Da='Daddychill:BAABLgAECn8mAAIbAAkJcBTqFgDyAQAbAAkJcBTqFgDyAQAAAA==.Dahunt:BAAALgAECgcJAQAAAA==.Damekka:BAAALgAECgQJBQAAAA==.Danazer:BAAALgAECgYJBgAAAA==.Danoe:BAAALgAECgIJAgAAAA==.Danzig:BAAALgAFFAEJAQAAAA==.Darktalyn:BAABLgAECn8xAAMZAAkJgBRdGwDuAQAZAAgJFhZdGwDuAQATAAgJ2Q9jQAAOAQAAAA==.Davidaire:BAAALgAECgEJAQAAAA==.',
De='Deadpaws:BAAALgADCgMJAwAAAA==.Deathbinger:BAAALgADCgEJAQAAAA==.Deathgriped:BAABLgAECn84AAIGAAgJmBheEwDbAQAGAAgJmBheEwDbAQAAAA==.Deathhawkzz:BAACLgAFFH8TAAMcAAQJRgqLEgCjAAAdAAQJRgoSYQAFAQAcAAMJLgOLEgCjAAAuAAQKfxoAAxwACAmcFOYLAAQCABwABwn6FeYLAAQCAB0ABAntEYSmAPQAAAAA.Deathphoenix:BAAALgADCgcJBwAAAA==.Deathslock:BAAALgADCgQJBAAAAA==.Deekura:BAABLgAECn9oAAMCAAkJRhqMBABsAgACAAkJRhqMBABsAgAHAAIJlQHbOgAyAAAAAA==.Deladorana:BAAALgADCgUJBQAAAA==.Dellma:BAAALgADCgYJDAAAAA==.Delusion:BAABLgAECn8UAAMeAAcJeQhMFADlAAAeAAYJxAdMFADlAAAWAAIJDAq8EgBdAAAAAA==.Demmin:BAAALgADCggJCAABLgAECgkJKgADABQLAA==.Demonpapi:BAABLgAFFH8GAAIdAAMJ6AJ1kACjAAAdAAMJ6AJ1kACjAAAAAA==.Demoryx:BAAALgAECgQJBAAAAA==.Denjack:BAAALgAECgcJEAAAAA==.Dewayne:BAAALgAECgUJBQAAAA==.',
Dh='Dhadzen:BAAALgAECgQJCwAAAA==.',
Di='Dinak:BAAALgAECgcJEAAAAA==.Diodotus:BAAALgADCgEJAQAAAA==.Dionan:BAABLgAECn8sAAIJAAkJZRKzXwCyAQAJAAkJZRKzXwCyAQAAAA==.Dirtysouth:BAABLgAFFH8FAAIWAAMJTwwhGQC3AAAWAAMJTwwhGQC3AAABLgAFFAUJGwAPADAhAA==.',
Do='Docs:BAABLgAECn8vAAIKAAgJbhmtFwBLAgAKAAgJbhmtFwBLAgAAAA==.Doks:BAABLgAECn9CAAIBAAkJRh9yDQDrAgABAAkJRh9yDQDrAgAAAA==.Dontpanic:BAEBLgAECn8oAAIfAAcJZh0wBwDDAQAfAAcJZh0wBwDDAQABLgAFFAQJDgAKAB8RAA==.Doomsnake:BAAALgADCgMJAwABLgAECgEJAQAOAAAAAA==.Dove:BAAALgADCgYJBgAAAA==.',
Dr='Drachim:BAAALgAECgEJAQAAAA==.Dragana:BAAALgAECgIJAgAAAA==.Dragomalfoy:BAAALgADCgQJBAAAAA==.Dragondznuts:BAAALgAFFAQJBAAAAA==.Dragõn:BAAALgAECgYJEwAAAA==.Drexeos:BAAALgADCgcJBwAAAA==.Drinker:BAAALgADCgUJBQAAAA==.Drunkenhealz:BAAALgAECgkJBQAAAA==.',
Du='Dunir:BAAALgAECgcJDQAAAA==.',
Ea='Ealara:BAABLgAECn8eAAIPAAgJ7gl6dQBUAQAPAAgJ7gl6dQBUAQAAAA==.',
Eb='Ebonwood:BAAALgAECgEJAQAAAA==.',
Ed='Edran:BAAALgADCgcJFQAAAA==.',
Ei='Eifel:BAAALgAECgQJBAABLgAECgkJGwAJABceAA==.Eimin:BAAALgADCgYJCgAAAA==.',
El='Eldarion:BAAALgAECgMJAgAAAA==.Elfmonk:BAAALgAECgEJAQAAAA==.Ellipses:BAAALgAECgMJAwABLgAECggJJQARAJgbAA==.',
Em='Emeraldz:BAABLgAECn8mAAILAAgJcRwbFAAaAgALAAgJcRwbFAAaAgAAAA==.',
En='Eneru:BAAALgADCgYJCAABLgAECggJHwAKAJ0XAA==.',
Er='Erebrethil:BAAALgAECgYJDwABLgAECggJOgAfANkaAA==.',
Es='Espe:BAABLgAECn8cAAIbAAkJyhM7GwDLAQAbAAkJyhM7GwDLAQAAAA==.',
Eu='Eucalyptia:BAAALgADCgQJBAAAAA==.Euli:BAABLgAFFH8MAAIgAAcJRhjiAgDSAQAgAAcJRhjiAgDSAQABLgAFFAkJJgAbAIQfAA==.',
Ev='Evenin:BAAALgADCgIJAgAAAA==.',
Ex='Exoncantotem:BAAALgADCgQJBAAAAA==.',
Fa='Faenor:BAAALgAECgUJDQAAAA==.Fallen:BAABLgAECn8VAAIFAAkJ7BWfAwD5AQAFAAkJ7BWfAwD5AQAAAA==.Fallenvoid:BAAALgAECgEJAQAAAA==.Faynor:BAABLgAECn9GAAMbAAkJBBxoAgDDAQAbAAkJBBxoAgDDAQALAAYJbROzNQAsAQAAAA==.Faynór:BAABLgAECn8VAAIGAAgJSQtTBwAhAQAGAAgJSQtTBwAhAQABLgAECgkJRgAbAAQcAA==.',
Fe='Feloni:BAAALgAECgMJAwAAAA==.',
Fi='Finalone:BAAALgAECgEJAQAAAA==.Firêfly:BAABLgAECn8WAAIJAAkJ8QhlqAAqAQAJAAkJ8QhlqAAqAQAAAA==.',
Fk='Fknsteve:BAAALgADCgYJBgAAAA==.',
Fl='Flaptix:BAAALgAECgMJAwAAAA==.Flipingflerp:BAAALgAECgcJEQAAAA==.Flloran:BAAALgAECgcJDgAAAA==.Floragoth:BAAALgAECgEJAQAAAA==.Flowers:BAAALgADCgkJCQAAAA==.Fluffboi:BAABLgAECn81AAILAAkJbwpMLwBMAQALAAkJbwpMLwBMAQAAAA==.',
Fo='Fourloko:BAAALgAECgEJAQAAAA==.Foxyblue:BAABLgAECn8UAAIZAAYJTBV3NABtAQAZAAYJTBV3NABtAQAAAA==.',
Fr='Fraggle:BAECLgAFFH8OAAMKAAQJHxH5KQDXAAAKAAQJHxH5KQDXAAAJAAMJUwk7eQDDAAAuAAQKfycAAwoACAl+IBsLAMcCAAoACAl+IBsLAMcCAAkABAmtEELWAOsAAAAA.Freefromfate:BAAALgAECgEJAQAAAA==.Frogchi:BAAALgAECgkJEQAAAA==.Frostbité:BAABLgAECn84AAMRAAkJ0B/QAwDPAgARAAkJ0B/QAwDPAgAKAAEJuwLBJQAdAAAAAA==.Fruit:BAABLgAECn8dAAIcAAcJZxJLFwDpAAAcAAcJZxJLFwDpAAAAAA==.',
Fu='Fuknak:BAAALgAECgIJAwAAAA==.Fumikiko:BAAALgADCgIJAgABLgAFFAMJBwAIAO4UAA==.Fumus:BAAALgAFFAEJAQAAAA==.Furrykarg:BAAALgAECgEJAQABLgAECgQJBgAOAAAAAA==.',
['Fà']='Fàynor:BAAALgAECggJEgABLgAECgkJRgAbAAQcAA==.',
['Fí']='Físh:BAAALgADCgYJBgABLgAFFAMJBwAIAO4UAA==.',
['Fú']='Fúzzy:BAAALgADCgEJAgABLgAFFAEJAQAOAAAAAA==.',
Ga='Gakkle:BAABLgAECn8nAAIEAAkJghuwBADDAQAEAAkJghuwBADDAQAAAA==.Galadralvia:BAABLgAECn8eAAIXAAkJRBWmEgDBAQAXAAkJRBWmEgDBAQAAAA==.Gali:BAABLgAECn8ZAAIaAAgJJQVDBgCsAAAaAAgJJQVDBgCsAAAAAA==.Ganaan:BAAALgAECgEJAwAAAA==.Garagas:BAAALgAECgIJAwAAAA==.',
Ge='Gearsofbob:BAAALgAFFAIJBAAAAA==.Gekkle:BAAALgADCgUJBQAAAA==.',
Gh='Ghorn:BAAALgAECgEJAQAAAA==.Ghoulei:BAABLgAECn82AAICAAkJzx+3GgCmAgACAAkJzx+3GgCmAgAAAA==.',
Gi='Girlscout:BAEALgAECgYJBgABLgAFFAQJDgAKAB8RAA==.',
Gl='Glaistiguain:BAAALgAECgYJCwABLgAECggJNAACAJogAA==.Glenheals:BAAALgADCgkJEgAAAA==.Glifin:BAAALgAECgcJDgAAAA==.Gloomstalkin:BAABLgAECn8/AAISAAkJNhd9DgBDAgASAAkJNhd9DgBDAgAAAA==.',
Gn='Gnøsis:BAAALgADCggJEQAAAA==.',
Go='Goldìelocks:BAAALgAECgUJCAAAAA==.Gom:BAAALgAECgIJAgAAAA==.Gomdrog:BAAALgAECgEJAQAAAA==.',
Gr='Gr:BAABLgAECn8oAAIeAAgJ7QzADgA4AQAeAAgJ7QzADgA4AQAAAA==.Grannecs:BAAALgADCgEJAQAAAA==.Greenygreen:BAAALgAECgEJAQAAAA==.Grimmli:BAAALgADCgEJAQAAAA==.Grizelda:BAAALgADCgQJBAAAAA==.Grizzledpaw:BAAALgAECgUJDAAAAA==.Gromcresh:BAAALgAECgUJBQAAAA==.Gryffs:BAABLgAECn86AAMXAAkJ3CCdBQC8AgAXAAkJ3CCdBQC8AgAYAAEJ1Aq1gAApAAAAAA==.Gràvity:BAAALgAECgEJAQABLgAFFAEJAQAOAAAAAA==.',
Gu='Guenhwyn:BAAALgADCgIJAQAAAA==.Gum:BAAALgAECgcJBwABLgAECgkJNQARAK0gAA==.Gutts:BAABLgAECn8nAAQXAAkJDSLdBQC0AgAXAAkJDSLdBQC0AgAYAAcJ3BKtLQATAQAEAAQJ0Q7wfQDFAAAAAA==.',
Ha='Hadron:BAAALgAECgQJCQAAAA==.Hahkoa:BAAALgADCgMJAwAAAA==.Haintala:BAAALgAECgEJAwAAAA==.Halomea:BAAALgADCgQJBAAAAA==.Hanukira:BAAALgADCgUJBQAAAA==.Happi:BAAALgAECgYJCQABLgAFFAkJRQAUAN8jAA==.Happyhour:BAAALgAFFAEJAQABLgAFFAkJRQAUAN8jAA==.Harald:BAABLgAECn8gAAMCAAkJ9g72qQAdAQACAAkJogz2qQAdAQAGAAIJ4hswPQCbAAAAAA==.Harkle:BAAALgADCgcJDQAAAA==.Haruun:BAAALgAECgIJAgAAAA==.Hazeleyez:BAAALgAECgEJAQAAAA==.',
He='Healyoself:BAAALgAECggJCQAAAA==.Heliõs:BAAALgAECgEJAQAAAA==.Hesmydaddy:BAABLgAECn9CAAIZAAkJLhL4BAC1AQAZAAkJLhL4BAC1AQAAAA==.',
Ho='Honcho:BAAALgAECgEJAQAAAA==.Honestie:BAAALgAECgQJCgAAAA==.Honêy:BAAALgAFFAIJAQAAAA==.Hotdogstand:BAACLgAFFH8bAAIWAAgJnCIoCAAlAgAWAAgJnCIoCAAlAgAuAAQKfzEABBYACQlwJQcDACADABYACQlwJQcDACADAB4ABAmEIYELAHMBACEAAQkrIq0eAFgAAAAA.',
Hu='Hukan:BAAALgAECgQJCAAAAA==.Huntarius:BAAALgAECgEJAQAAAA==.Huzzaah:BAEALgAFFAEJAQABLgAFFAQJDgAKAB8RAA==.',
Hy='Hyperius:BAAALgADCgIJAgAAAA==.',
['Hö']='Höneÿdew:BAABLgAECn8ZAAIPAAgJ9Bg2LAADAgAPAAgJ9Bg2LAADAgAAAA==.',
Ic='Icemann:BAAALgAECgEJAgAAAA==.',
Il='Ilidrayssel:BAABLgAECn8aAAIaAAcJbQNHIACuAAAaAAcJbQNHIACuAAAAAA==.Illida:BAAALgAECgMJCQAAAA==.Illidad:BAAALgAECgQJBAAAAA==.Ilyssara:BAABLgAECn8VAAIiAAkJUxKfAQDNAQAiAAkJUxKfAQDNAQABLgAECggJJQARAJgbAA==.',
Im='Imhappy:BAAALgAECgUJCgABLgAFFAkJRQAUAN8jAA==.Imherdaddy:BAAALgAECggJCAABLgAECgkJPwASADYXAA==.',
In='Indracus:BAAALgAECgQJCQAAAA==.Innervape:BAAALgADCgMJAwAAAA==.',
Ir='Ironfay:BAAALgAECggJCwABLgAECgkJRgAbAAQcAA==.',
It='Itakemeds:BAAALgAECgUJBQABLgAECgkJUgABAH8cAA==.',
Ja='Jacorict:BAABLgAECn8UAAIJAAYJJws90wDuAAAJAAYJJws90wDuAAAAAA==.Jagga:BAAALgADCgMJAwAAAA==.Jarrack:BAABLgAECn89AAIDAAkJrB6jBgArAgADAAkJrB6jBgArAgAAAA==.',
Je='Jellyhawk:BAAALgAECgEJAQAAAA==.Jessicae:BAAALgAECggJEgAAAA==.Jeuno:BAAALgAECgYJBwABLgAFFAMJBwAIAO4UAA==.',
Jo='Josephd:BAAALgADCgEJAQABLgAECggJPgAFABwcAA==.Josephedd:BAABLgAECn8+AAIFAAgJHBwYEwA8AgAFAAgJHBwYEwA8AgAAAA==.',
Ju='Judgemint:BAAALgADCgcJBgAAAA==.Judgment:BAAALgAECgEJAQAAAA==.Jukk:BAABLgAECn8qAAIDAAkJFAtTGQAQAQADAAkJFAtTGQAQAQAAAA==.Junazeena:BAABLgAECn88AAMMAAkJSgxSCQA8AQAMAAkJSgxSCQA8AQABAAIJCgKU0gA4AAAAAA==.',
Jy='Jygglypuff:BAAALgAECgUJBQAAAA==.',
Ka='Kaji:BAABLgAECn8jAAIfAAYJSROmRQBVAQAfAAYJSROmRQBVAQAAAA==.Kalistus:BAAALgAECgYJBwAAAA==.Kargfu:BAAALgAECgQJBgAAAA==.Karolat:BAAALgAECgUJBgAAAA==.Kayfabe:BAABLgAECn8bAAIDAAkJ3QNz+gAGAQADAAkJ3QNz+gAGAQAAAA==.Kayfay:BAAALgAECgMJAwAAAA==.Kazz:BAAALgAFFAEJAQAAAA==.',
Ke='Keishilda:BAABLgAECn8gAAMjAAgJ1wt+FAChAAAjAAcJtwl+FAChAAATAAcJzQclFQCTAAAAAA==.Keladria:BAAALgAECgQJBwAAAA==.Kelirra:BAAALgADCgQJCAAAAA==.Kelvyren:BAAALgADCgEJAQAAAA==.Kenel:BAABLgAECn83AAMVAAkJhBcpGgB0AgAVAAkJhBcpGgB0AgAFAAUJcRH5UADKAAAAAA==.Kerea:BAABLgAECn9PAAMVAAkJnguOBwBhAQAVAAkJnguOBwBhAQAFAAMJAQsJZwCCAAAAAA==.Kerob:BAAALgAECgYJDQAAAA==.Keyarga:BAAALgADCgIJAgABLgAECgcJFgASAM4TAA==.',
Kh='Khazargon:BAAALgAECgQJCgAAAA==.',
Ki='Kicken:BAABLgAECn9vAAQdAAkJLB+nAwBTAgAdAAgJcBynAwBTAgAcAAUJfxyiCAC1AAAkAAEJxB80DwBUAAAAAA==.Kitschy:BAAALgADCgEJAQAAAA==.Kittyperry:BAAALgAFFAEJAgAAAA==.Kizmo:BAAALgAECgEJAQAAAA==.',
Kn='Knome:BAABLgAECn87AAIDAAkJwh4PHQCuAgADAAkJwh4PHQCuAgAAAA==.',
Ko='Koana:BAAALgAECgkJCwAAAA==.Kororin:BAAALgAECgMJAwAAAA==.Korthelan:BAABLgAECn89AAIUAAkJMxJaPADWAQAUAAkJMxJaPADWAQAAAA==.Kothara:BAABLgAECn9IAAIPAAkJwxpzBQBeAgAPAAkJwxpzBQBeAgAAAA==.Kotongar:BAAALgADCgMJAwAAAA==.',
Kr='Kreeoo:BAAALgAECgIJAgAAAA==.Krimzin:BAACLgAFFH8bAAIPAAUJMCGaJABzAQAPAAUJMCGaJABzAQAuAAQKfx8AAw8ACAnfIZQhADwCAA8ACAnfIZQhADwCABIAAgkaEHldAD4AAAAA.Krystine:BAABLgAECn8fAAIVAAcJNhXgTwBPAQAVAAcJNhXgTwBPAQAAAA==.',
Ks='Kserasera:BAACLgAFFH8TAAIFAAYJIA/LDgAxAQAFAAYJIA/LDgAxAQAuAAQKfxUAAgUACQkGE/UJACIBAAUACQkGE/UJACIBAAAA.',
Ku='Kuball:BAAALgAECgYJCgABLgAECgkJJwAXAA0iAA==.Kukuruku:BAABLgAECn8ZAAIMAAkJmwzqPQA9AQAMAAkJmwzqPQA9AQAAAA==.Kurailatha:BAAALgADCgkJBgAAAA==.',
['Kì']='Kìssofdeath:BAAALgAECgUJBQAAAA==.',
['Kî']='Kîllara:BAABLgAECn8qAAIBAAkJrhW4KQAWAgABAAkJrhW4KQAWAgAAAA==.',
La='Labialicious:BAAALgAECgEJAgAAAA==.Lanfeår:BAABLgAECn8VAAICAAYJCwjL4ADTAAACAAYJCwjL4ADTAAAAAA==.Lanskies:BAABLgAECn8ZAAICAAkJPRXMMgAzAgACAAkJPRXMMgAzAgAAAA==.',
Le='Leafymeds:BAAALgAECgYJEAABLgAECgkJUgABAH8cAA==.Lebronjames:BAABLgAFFH8FAAICAAMJdhpzfwAIAQACAAMJdhpzfwAIAQAAAA==.Leiluna:BAAALgADCgkJEQAAAA==.Letheos:BAABLgAFFH8PAAIGAAYJkRTZCwBAAQAGAAYJkRTZCwBAAQAAAA==.Levanas:BAAALgAECgEJAQAAAA==.',
Li='Libertinne:BAABLgAECn8cAAIEAAgJMxewMwB8AQAEAAgJMxewMwB8AQAAAA==.Librarte:BAABLgAECn8/AAMJAAkJNw2BbACVAQAJAAkJNw2BbACVAQARAAUJGAKGFABLAAAAAA==.Ligmanuts:BAAALgAECgIJBAAAAA==.Lija:BAAALgAECgYJBgABLgAECgkJKgADABQLAA==.Lillytrae:BAAALgAECgMJBQAAAA==.Listie:BAAALgADCgQJBAABLgAECgkJFgAHAIgWAA==.Litty:BAABLgAECn8oAAIDAAcJASX8KwBpAgADAAcJASX8KwBpAgAAAA==.Lizrdkng:BAAALgADCgMJBgAAAA==.',
Lo='Locktärd:BAACLgAFFH8MAAQkAAQJiBsVBgAiAQAkAAQJiBsVBgAiAQAdAAIJShYXMwCtAAAcAAIJogaEDgCXAAAuAAQKfyoABCQACAmIH6oCAJACACQACAk+H6oCAJACAB0ACAktGRZCAAYCABwAAgkLHIJGAJwAAAAA.Lohken:BAAALgAFFAEJAQAAAA==.Loralila:BAAALgAECgUJCQABLgAECgkJHgAXAEQVAA==.Lox:BAABLgAECn9NAAMcAAkJSRohBABDAgAcAAkJSRohBABDAgAdAAIJFQSeJgFCAAAAAA==.',
Lu='Lucieb:BAAALgAECgEJAQAAAA==.',
Ly='Lydirn:BAABLgAECn8gAAQJAAkJ+RxtQAAFAgAJAAgJ3x1tQAAFAgAKAAQJzRVpVQDiAAARAAIJoBykMQCfAAAAAA==.Lyofel:BAAALgAECgYJDwAAAA==.Lyonel:BAAALgADCggJCAAAAA==.Lysaviel:BAAALgAECgEJAgAAAA==.',
['Lí']='Lítterbox:BAABLgAFFH8GAAIQAAMJzAkjCACqAAAQAAMJzAkjCACqAAAAAA==.',
Ma='Magedzen:BAAALgAECgMJBAAAAA==.Magicguy:BAACLgAFFH8MAAIDAAMJEw0aQQDEAAADAAMJEw0aQQDEAAAuAAQKfxsAAgMACQlnDzNVAN0BAAMACQlnDzNVAN0BAAAA.Mahariel:BAABLgAECn8xAAIPAAkJ/RD2PgDmAQAPAAkJ/RD2PgDmAQAAAA==.Mahdy:BAABLgAECn9LAAIJAAkJrR7GJAByAgAJAAkJrR7GJAByAgAAAA==.Mahoe:BAAALgAECgUJCQAAAA==.Maivel:BAAALgAECgcJCAAAAA==.Malva:BAAALgAECgEJAQABLgAECgEJAQAOAAAAAA==.Manandaar:BAAALgAECgIJBAAAAA==.Mandret:BAAALgAECgMJBAABLgAECggJHAAfANESAA==.Manicppanic:BAEBLgAECn8gAAIWAAgJxxVrHQCrAQAWAAgJxxVrHQCrAQABLgAFFAQJDgAKAB8RAA==.Manrypurp:BAAALgAECgUJDQAAAA==.Marcie:BAABLgAECn9SAAIFAAkJ+BO1BQCUAQAFAAkJ+BO1BQCUAQAAAA==.Martinriggz:BAAALgAECgQJCQAAAA==.',
Mc='Mchammer:BAAALgAECgEJAgAAAA==.',
Me='Meatyloaf:BAABLgAECn8iAAIHAAkJcQfiHgDVAAAHAAkJcQfiHgDVAAAAAA==.Medsedation:BAABLgAECn8XAAMjAAkJ+QcGLgBqAQAjAAkJxwcGLgBqAQAZAAgJBQRVQADtAAAAAA==.Melkedrik:BAABLgAECn8cAAIlAAkJ9g6TJABTAQAlAAkJ9g6TJABTAQAAAA==.Melleren:BAAALgAFFAEJAQAAAA==.Menorah:BAAALgAECgEJAQAAAA==.Messande:BAAALgAECgUJBgAAAA==.',
Mi='Minõs:BAAALgADCgkJEAAAAA==.Mirai:BAAALgADCgUJBQAAAA==.Mirei:BAABLgAECn9vAAIZAAkJ6RIZBADjAQAZAAkJ6RIZBADjAQAAAA==.Mistdancer:BAAALgADCgYJBgABLgAFFAIJCgAHAI0GAA==.Mitsurugi:BAAALgAECgEJAgABLgAFFAIJCgAHAI0GAA==.Miyagí:BAAALgAECgcJDgABLgAECggJGAAGAKYdAA==.',
Mo='Mochisama:BAAALgAECgYJCAAAAA==.Mojam:BAAALgAECgQJEQAAAA==.Monk:BAAALgAECgEJAQAAAA==.Monkadzen:BAAALgAECgEJBAAAAA==.Moonless:BAAALgAECgEJAgAAAA==.Moonovrmyham:BAAALgADCgMJAwAAAA==.Moovidlin:BAABLgAECn8XAAIEAAkJBQteNQBzAQAEAAkJBQteNQBzAQABLgAECgkJKgADABQLAA==.Mordian:BAAALgAECgYJBgAAAA==.Morinnas:BAAALgAECgQJBQAAAA==.Moschpit:BAAALgADCgEJAQAAAA==.',
Mu='Mugruss:BAAALgADCggJCAAAAA==.Munkeez:BAAALgADCgMJAwAAAA==.Murdermoo:BAAALgADCgMJAwAAAA==.Murkessa:BAAALgAECgQJBwAAAA==.Mushhead:BAAALgAECgUJCAAAAA==.Mustepin:BAAALgAECgQJBAABLgAFFAQJEAAEAEobAA==.',
My='Myishaa:BAAALgADCgIJAgAAAA==.Mykeal:BAAALgADCgMJBQAAAA==.Myndigo:BAAALgAECgEJAQAAAA==.Mystryl:BAAALgADCgkJEQAAAA==.Mythantherox:BAABLgAFFH8HAAIYAAMJrR1YHAAJAQAYAAMJrR1YHAAJAQABLgAFFAYJGgAmAFkZAA==.',
['Mì']='Mìstra:BAAALgADCgUJBwAAAA==.',
Na='Nakkal:BAAALgAECgUJBgAAAA==.Nanari:BAAALgADCgkJBgABLgAECgkJbwAZAOkSAA==.Nanlaria:BAAALgAECgIJBQAAAA==.Nargo:BAAALgADCgYJCgAAAA==.Nataliia:BAAALgAECgQJBAAAAA==.',
Ne='Necrostalker:BAAALgADCgkJCQABLgAECgEJAQAOAAAAAA==.Negative:BAAALgAECgQJCgAAAA==.Neltherius:BAAALgAECgEJAQAAAA==.Nerwende:BAAALgAECgEJAQAAAA==.Nethershade:BAABLgAECn9cAAIeAAkJqCI0AAAiAwAeAAkJqCI0AAAiAwAAAA==.Netherstörm:BAAALgAECgcJEAAAAA==.Nezot:BAAALgAECgEJAQABLgAECgkJHAACACERAA==.',
Ni='Niclea:BAAALgAECgQJBAAAAA==.Nightelm:BAACLgAFFH8HAAQIAAMJ7hQ/QgC+AAAIAAMJ7hQ/QgC+AAAmAAEJnBKoDQBIAAAnAAEJZgQCMAAmAAAuAAQKfysABAgACQltHw8LAKgCAAgACQlnHw8LAKgCACcABgleDBY0AM0AACYABAn3G3UZAIkAAAAA.Ninym:BAAALgAECgEJAQAAAA==.Niënor:BAABLgAECn86AAIfAAgJ2RrOBQDrAQAfAAgJ2RrOBQDrAQAAAA==.',
Nj='Njorvir:BAAALgAECgEJAQABLgAECgEJAQAOAAAAAA==.',
No='Noslien:BAAALgAECgUJBwAAAA==.Nostradamuz:BAAALgAECgEJAQAAAA==.Novasong:BAAALgAECgEJAwAAAA==.',
Ny='Nymneria:BAABLgAECn8YAAIcAAgJgQ2DFgDyAAAcAAgJgQ2DFgDyAAAAAA==.Nyxiera:BAAALgAFFAIJBAABLgAFFAUJKgAXALUaAA==.Nyxstonia:BAACLgAFFH8qAAIXAAUJtRozCwAEAQAXAAUJtRozCwAEAQAuAAQKf10AAxcACQnvINoAAOECABcACQnvINoAAOECAAQACAk8DfIJAC8BAAAA.',
Ob='Oballi:BAAALgAECgUJBwAAAA==.',
Od='Oddsaint:BAAALgAECgEJAwAAAA==.',
Ol='Olierra:BAAALgAECgYJDAAAAA==.',
On='Onlyvoids:BAAALgAECgMJAwAAAA==.',
Or='Oreshin:BAAALgAECgYJBgAAAA==.Orhan:BAAALgAECgQJBAABLgAECgkJRgAbAAQcAA==.Ornac:BAAALgADCgcJEAAAAA==.',
Ot='Otkspring:BAACLgAFFH8HAAMEAAMJHwonPQC5AAAEAAMJZggnPQC5AAAYAAEJPwecQwBAAAAuAAQKfxkAAgQABwmAF/ktAJkBAAQABwmAF/ktAJkBAAAA.Otto:BAABLgAECn8pAAIJAAkJ2hHLXwCxAQAJAAkJ2hHLXwCxAQAAAA==.Ottomagus:BAABLgAECn8fAAIDAAkJAxUOCgDIAQADAAkJAxUOCgDIAQAAAA==.',
Ox='Oxadin:BAAALgAECgEJAQAAAA==.Oxideous:BAAALgADCgMJAwAAAA==.',
Pa='Paleale:BAABLgAECn8VAAIMAAYJ7wztXQDLAAAMAAYJ7wztXQDLAAAAAA==.Pallyshore:BAAALgADCgMJAwAAAA==.Pallywack:BAAALgAECggJCQAAAA==.Pampoovy:BAEALgADCgMJAwABLgAECgkJFwASAA4ZAA==.Pandapunk:BAAALgAECggJDgAAAA==.Panic:BAAALgAECgEJAgAAAA==.Pantoponrose:BAAALgAECgYJEQAAAA==.Pastorbash:BAAALgADCggJCQAAAA==.',
Pb='Pb:BAAALgAECgMJAwAAAA==.',
Pe='Persephoneia:BAABLgAECn8mAAITAAkJYxF0IgC0AQATAAkJYxF0IgC0AQAAAA==.',
Pi='Pitnick:BAAALgAECgMJAwAAAA==.',
Pk='Pkashmuk:BAAALgADCgcJBwAAAA==.',
Pr='Prophettool:BAABLgAECn8oAAMJAAkJlAsIgwBpAQAJAAkJlAsIgwBpAQAKAAQJigQEfQCGAAAAAA==.Pruned:BAAALgADCgcJBwABLgAFFAQJDAAkAIgbAA==.',
Pu='Punjistake:BAAALgAECgYJBgAAAA==.',
['Pï']='Pïzzasteve:BAAALgAECgIJAgABLgAFFAEJAQAOAAAAAA==.',
Qu='Quanchii:BAAALgADCgMJAwAAAA==.Quna:BAAALgAECgUJBQAAAA==.',
Ra='Raemie:BAAALgAECgQJCgAAAA==.Ragequit:BAABLgAECn8WAAIXAAgJwhfEFACmAQAXAAgJwhfEFACmAQABLgAECggJJQARAJgbAA==.Raikoho:BAAALgAECgEJAQABLgAECgEJAQAOAAAAAA==.Rakulm:BAAALgADCgUJCgAAAA==.Ravenloare:BAAALgAECgQJBAAAAA==.Ravenrest:BAABLgAECn8vAAITAAgJqx7GEgA8AgATAAgJqx7GEgA8AgAAAA==.',
Re='Reaverheim:BAABLgAECn8ZAAQXAAYJAx8PFgCWAQAXAAYJYx4PFgCWAQAEAAQJfxcqZQAeAQAYAAIJBR0lSgCkAAAAAA==.Rehab:BAAALgAFFAIJAgABLgAECggJJQARAJgbAA==.Rehtië:BAAALgAECgcJBwABLgAECggJOgAfANkaAA==.Reiko:BAAALgADCgkJIQABLgAECgkJbwAZAOkSAA==.Remuz:BAAALgAECgUJCwAAAA==.Rennwick:BAAALgAECgQJBgAAAA==.Renriss:BAAALgAECgcJCQABLgAECggJOAAGAJgYAA==.Rey:BAABLgAECn8XAAIPAAkJzRU3BwAiAgAPAAkJzRU3BwAiAgAAAA==.',
Rh='Rhe:BAAALgAECgIJAgABLgAECgkJFwAPAM0VAA==.',
Ri='Rilz:BAABLgAECn8qAAICAAkJ3SDmHQCUAgACAAkJ3SDmHQCUAgAAAA==.',
Ro='Rochambeu:BAAALgADCgEJAQAAAA==.Rockasham:BAAALgAECgQJCgAAAA==.Rockyrogue:BAAALgAECgEJAQAAAA==.Rodgerwabbet:BAAALgAECgQJBAAAAA==.Roiddemon:BAAALgADCgQJBAABLgAECggJKwAdABcUAA==.Roiddrood:BAAALgAECgIJAgABLgAECggJKwAdABcUAA==.Roidlock:BAABLgAECn8rAAIdAAgJFxRoVgCZAQAdAAgJFxRoVgCZAQAAAA==.Roidtank:BAAALgAECgUJDAABLgAECggJKwAdABcUAA==.Rongyi:BAAALgADCgIJAgAAAA==.Rosaline:BAAALgAECgYJDgAAAA==.Rosewood:BAAALgAECgkJCAAAAA==.Rottn:BAABLgAECn8lAAIRAAgJmBviAQAgAgARAAgJmBviAQAgAgAAAA==.Rottnshot:BAAALgADCgYJBgABLgAECggJJQARAJgbAA==.',
Ru='Runerion:BAAALgAECgEJBQAAAA==.',
Ry='Ry:BAAALgAECgYJBQABLgAECgkJFwAPAM0VAA==.',
['Rà']='Ràìn:BAABLgAECn8WAAIDAAgJAgnuoQA4AQADAAgJAgnuoQA4AQAAAA==.',
['Rô']='Rôttñ:BAAALgADCgEJAQABLgAECggJJQARAJgbAA==.',
Sa='Sacrothoth:BAAALgAECgEJAgAAAA==.Safmen:BAABLgAECn8bAAQXAAYJwQdsNgCeAAAXAAYJjAdsNgCeAAAYAAMJMgXiaQBOAAAEAAEJCAr0ogA9AAAAAA==.Sanikoa:BAAALgAECgUJCwAAAA==.Sanlen:BAAALgAECgEJAQABLgAECgkJPQAUADMSAA==.Saraid:BAABLgAECn8vAAQVAAkJ9RgHFwCOAgAVAAkJ9RgHFwCOAgAFAAUJVRB5GABrAAAgAAIJvQUOeAAtAAAAAA==.Saravase:BAABLgAECn8ZAAIBAAcJJQi/IQCFAAABAAcJJQi/IQCFAAAAAA==.Sardel:BAAALgAECgEJAQAAAA==.Sargeros:BAAALgAECgQJBQAAAA==.Savidlin:BAAALgAECgEJAQABLgAECgkJKgADABQLAA==.Sazem:BAAALgADCgIJAgAAAA==.',
Se='Sedaldra:BAAALgADCgYJCwAAAA==.',
Sh='Shadowgo:BAAALgAECgEJAQAAAA==.Shadowi:BAAALgAECgQJBQAAAA==.Shadownights:BAABLgAECn9AAAITAAkJcxgUBADYAQATAAkJcxgUBADYAQAAAA==.Shadowpope:BAAALgAECgkJBgAAAA==.Shadowstorm:BAAALgADCgYJCQAAAA==.Shamadzen:BAAALgAECgEJAQAAAA==.Shamoneyy:BAAALgADCgUJBQAAAA==.Shanksinatra:BAAALgAECgEJAQAAAA==.Shiki:BAAALgADCgkJEwABLgAECgkJbwAZAOkSAA==.Shimnar:BAAALgAECggJEwABLgAECggJHAAEADMXAA==.Shinifur:BAAALgADCgUJBgAAAA==.Shinoto:BAABLgAECn8ZAAMDAAYJISAxWgDPAQADAAYJISAxWgDPAQAoAAEJDxXQEgA/AAAAAA==.Shiritá:BAAALgAECgMJAgAAAA==.Shockazam:BAAALgAECgcJEgAAAA==.Shrewby:BAAALgAECgEJAQAAAA==.Shyandra:BAAALgADCgYJBgAAAA==.',
Si='Sieghart:BAAALgAECgEJBAAAAA==.Silverstead:BAAALgAFFAEJAQAAAA==.Six:BAAALgAECgUJCwABLgAFFAEJAQAOAAAAAA==.',
Sk='Skinzey:BAAALgAECgYJBgAAAA==.Skylines:BAAALgAECgQJBAABLgAECgkJFgAHAIgWAA==.',
Sl='Sloptop:BAAALgAECgEJAgAAAA==.',
Sn='Snarkyshaman:BAAALgAECgQJBAABLgAECggJJQARAJgbAA==.Snickersbar:BAAALgADCgUJCAAAAA==.Snowynn:BAAALgAECgcJEwAAAA==.Snöw:BAABLgAECn8pAAIDAAkJGhVhQQAYAgADAAkJGhVhQQAYAgAAAA==.Snöwy:BAAALgAECgQJBAAAAA==.',
So='Sojudevourer:BAAALgAECgEJAQAAAA==.Southpaw:BAAALgAECgMJAwAAAA==.',
Sp='Spooki:BAAALgAECgEJAQAAAA==.Spyro:BAABLgAECn8wAAQIAAkJLA99GgD2AQAIAAkJLA99GgD2AQAnAAgJtBQsEQC4AQAmAAIJYw5CIwA/AAAAAA==.',
Sr='Sron:BAABLgAECn8qAAIPAAkJQx1qPQDrAQAPAAkJQx1qPQDrAQAAAA==.',
St='Stabalagmite:BAAALgAECgQJBAABLgAECggJJQARAJgbAA==.Stariah:BAABLgAECn8kAAIDAAgJPgttjQBcAQADAAgJPgttjQBcAQAAAA==.Stawn:BAAALgADCgEJAQAAAA==.Stupid:BAAALgADCgIJAgAAAA==.',
Su='Sumwhiteguy:BAAALgAECgEJAQAAAA==.',
Sw='Sweetbeef:BAAALgAECgIJAgAAAA==.Swooze:BAACLgAFFH8XAAIDAAYJARQaJQBIAQADAAYJARQaJQBIAQAuAAQKfzsAAgMACQndHVEcALICAAMACQndHVEcALICAAAA.',
Sy='Sylrythriana:BAABLgAECn8ZAAMWAAcJfwSwNQD/AAAWAAcJfwSwNQD/AAAeAAIJCwIIKQAxAAABLgAECgkJHgAXAEQVAA==.Syndar:BAAALgAECgQJBQABLgAECgkJLAADACoiAA==.Syndicate:BAAALgAECgcJDQAAAA==.Syrenis:BAAALgADCgkJDwABLgAFFAMJBwAIAO4UAA==.',
['Sù']='Sùnnydk:BAAALgADCgcJBwAAAA==.',
Ta='Tahoe:BAAALgADCgYJBgABLgAFFAcJJQAUABsWAA==.Talwaz:BAAALgADCgkJDgAAAA==.Tanzri:BAAALgAECgMJAwAAAA==.Tarlyn:BAACLgAFFH8MAAIKAAMJCg2yNACcAAAKAAMJCg2yNACcAAAuAAQKfzsABAoACQlcF24XAE4CAAoACQlcF24XAE4CAAkABglcGoyOAFUBABEAAQkAANI/AD4AAAAA.Tatslight:BAABLgAECn84AAIRAAgJMR21AgDYAQARAAgJMR21AgDYAQABLgAECggJOAARADEdAA==.Tatsrage:BAAALgAECgEJAQABLgAECggJOAARADEdAA==.Tazaral:BAAALgADCgEJAQABLgAECgkJCwAOAAAAAA==.',
Te='Ted:BAEBLgAFFH8RAAMVAAcJhBIzCwCHAQAVAAcJhBIzCwCHAQAFAAIJzwGCLAA9AAABLgAFFAQJDgAKAB8RAA==.Temuadêrna:BAAALgAECgQJBAAAAA==.Teysá:BAAALgADCgEJAQAAAA==.',
Th='Thalasso:BAAALgADCgEJAgAAAA==.Thor:BAAALgAECgYJCAAAAA==.Thyandris:BAAALgADCgYJCwAAAA==.Thánátós:BAAALgAECgQJBwAAAA==.',
Ti='Tichar:BAAALgADCgYJBgAAAA==.Timmthemage:BAAALgAECgUJBwABLgAECgEJAQAOAAAAAQ==.Timthehunter:BAAALgAECgEJAQAAAQ==.Timthepally:BAAALgAECggJDAABLgAECgEJAQAOAAAAAQ==.Tinytex:BAABLgAECn8oAAIbAAkJyw7VIwCMAQAbAAkJyw7VIwCMAQAAAA==.Tisiphoneia:BAAALgAECgQJBgAAAA==.',
To='Toberson:BAAALgAECgEJAQAAAA==.Tom:BAAALgAECgQJBAAAAA==.Toretto:BAAALgADCgkJBgAAAA==.Toxicbanana:BAABLgAECn8VAAIEAAYJeg8KEgC/AAAEAAYJeg8KEgC/AAAAAA==.',
Tr='Tradarynn:BAABLgAECn8hAAIJAAkJ7hujIACEAgAJAAkJ7hujIACEAgAAAA==.Trayvein:BAAALgADCgUJBQAAAA==.Trekk:BAAALgAECgcJBQAAAA==.Tress:BAABLgAECn8UAAINAAYJLx5YEgCQAQANAAYJLx5YEgCQAQAAAA==.',
Ts='Tsindre:BAAALgAECgEJAgAAAA==.Tsukong:BAAALgAECgEJAQAAAA==.',
Tu='Tulkar:BAABLgAECn8UAAIVAAgJchn8AgBCAgAVAAgJchn8AgBCAgAAAA==.Turambar:BAAALgAECgEJAQAAAA==.',
Tw='Twinkles:BAAALgAECgMJAwAAAA==.',
Ty='Tyriir:BAAALgADCgQJBgAAAA==.Tyviae:BAAALgAECgIJAgAAAA==.',
Um='Umbravine:BAABLgAECn8YAAIgAAgJyRY2AwDFAQAgAAgJyRY2AwDFAQABLgAECggJJQARAJgbAA==.Umbrax:BAAALgAECgQJBQAAAA==.',
Un='Unholymochi:BAABLgAECn8lAAICAAkJHiAgWwC1AQACAAkJHiAgWwC1AQAAAA==.',
Us='Usdaprime:BAABLgAFFH8LAAMFAAMJLwV6IQB0AAAFAAMJLwV6IQB0AAAQAAEJtQLVFgAeAAAAAA==.',
Uw='Uwuzi:BAAALgADCgQJBAAAAA==.',
Va='Valhalia:BAABLgAECn8UAAMdAAgJ6ReEcgBVAQAdAAYJKBiEcgBVAQAcAAMJbg6pQgCqAAAAAA==.Vanyllapea:BAAALgAECgMJAwAAAA==.Varaelitha:BAAALgAECgMJAwAAAA==.Vashan:BAAALgAECgQJBQAAAA==.Vashni:BAAALgAECgkJDAAAAA==.',
Ve='Velinariae:BAAALgADCgYJEAAAAA==.Vengful:BAABLgAECn86AAMlAAkJZB3tCACcAgAlAAkJZB3tCACcAgAiAAIJoBeAJAB7AAAAAA==.',
Vh='Vhalúryn:BAAALgAECgYJDQAAAA==.',
Vi='Vira:BAAALgAECgIJAgAAAA==.Vivy:BAABLgAECn8fAAQdAAkJNhThLwBNAgAdAAkJzRPhLwBNAgAcAAQJaxSaMwDpAAAkAAIJBhXMJgBWAAAAAA==.',
Vo='Vord:BAAALgAECgIJAgAAAA==.Vorumbrae:BAAALgAECgYJCAAAAA==.',
Vu='Vultus:BAAALgAECgIJAgAAAA==.',
Vy='Vylthyra:BAAALgADCgEJAQABLgAECggJJQARAJgbAA==.Vyrkin:BAAALgAECgEJAQAAAA==.Vyrul:BAAALgAECgQJBAABLgAECgkJFgAHAIgWAA==.',
['Vä']='Väntage:BAAALgADCgEJAQAAAA==.',
Wa='Wagyubeef:BAABLgAECn8kAAIEAAkJghdYIADtAQAEAAkJghdYIADtAQAAAA==.Wali:BAABLgAECn8gAAMdAAgJMRPKXQCFAQAdAAgJMRPKXQCFAQAcAAEJAAB9dgAuAAAAAA==.Warlodzen:BAAALgADCgcJBwAAAA==.Wayne:BAAALgAECgQJBAAAAA==.',
We='Weebey:BAAALgADCgEJAQAAAA==.Wenson:BAABLgAECn8cAAMCAAkJIRHfRwDqAQACAAkJIRHfRwDqAQAGAAkJ2wSHOQCtAAAAAA==.',
Wh='Whatupbruh:BAACLgAFFH8SAAMSAAQJ+RLrCwDbAAASAAQJbxHrCwDbAAAPAAMJRxDRawDMAAAuAAQKfyQABBIABwkcIh4HAIgCABIABwm5IR4HAIgCAA8AAQkJG1EcAUAAABoAAQndBnKSACgAAAAA.',
Wi='Wildfire:BAAALgAECgcJBwAAAA==.',
Wo='Wooties:BAAALgAECgcJCgABLgAECgkJQgABAEYfAA==.',
Wy='Wyleriya:BAABLgAECn85AAIdAAkJ+Ak9bQBhAQAdAAkJ+Ak9bQBhAQAAAA==.',
Xa='Xanthas:BAAALgADCgQJBAAAAA==.',
Xc='Xcella:BAAALgAECgUJCAAAAA==.',
Xe='Xephon:BAAALgADCgcJBwAAAA==.',
Xi='Xina:BAAALgAECgEJAQAAAA==.',
Xw='Xweakling:BAAALgADCgYJCAABLgAFFAQJEAAEAEobAA==.',
Xy='Xyn:BAAALgADCggJCAABLgAECgkJFwAPAM0VAA==.',
Ya='Yamonu:BAAALgADCgEJAQAAAA==.',
Ye='Yelizaveta:BAABLgAECn8dAAIPAAYJGwWdNQB3AAAPAAYJGwWdNQB3AAAAAA==.',
Yl='Ylfcwen:BAAALgAECgEJAQAAAA==.',
Yo='Yodey:BAACLgAFFH8MAAICAAQJOB/aRABrAQACAAQJOB/aRABrAQAuAAQKfzEAAgIACQlwI54HADkDAAIACQlwI54HADkDAAAA.Yoovee:BAAALgAECggJCAAAAA==.Yorsdon:BAAALgAECgIJAgAAAA==.',
Yu='Yuaetrende:BAACLgAFFH8OAAIlAAQJex4CDQBBAQAlAAQJex4CDQBBAQAuAAQKfzIAAiUACQlzI9wDABMDACUACQlzI9wDABMDAAAA.Yumii:BAABLgAECn8hAAMZAAkJPSUjAgCJAwAZAAkJECUjAgCJAwAjAAYJ/yH2DgBNAgAAAA==.',
Za='Zack:BAAALgAECgYJEwAAAA==.Zaerie:BAAALgADCgcJBwAAAA==.Zagul:BAAALgAECgUJCAAAAA==.Zalarah:BAAALgAECgUJDQAAAA==.Zalarilia:BAAALgAECgEJAQAAAA==.Zanoo:BAAALgADCgYJBwAAAA==.Zaphod:BAAALgAECgMJAwAAAA==.Zardan:BAABLgAECn81AAIdAAkJcBL2BQDeAQAdAAkJcBL2BQDeAQAAAA==.',
Zi='Ziegler:BAAALgADCgYJBgAAAA==.',
Zu='Zuggasaurus:BAABLgAECn8gAAUQAAkJHho+CABMAgAQAAkJ1Bk+CABMAgAgAAUJoRU1IwA2AQAFAAYJ+BIoCwALAQAVAAIJVg1sqQBhAAAAAA==.Zuggerker:BAAALgAECggJCwABLgAECgkJIAAQAB4aAA==.Zugglite:BAABLgAECn8oAAQKAAgJMCEyFwBYAgAKAAgJMCEyFwBYAgARAAQJ2xotHwAaAQAJAAEJdgmCtAEoAAABLgAECgkJIAAQAB4aAA==.Zulthar:BAABLgAECn8aAAIDAAgJ8Qo4rAAnAQADAAgJ8Qo4rAAnAQAAAA==.',
['Äs']='Äshborn:BAABLgAECn8qAAICAAkJRg58XwCqAQACAAkJRg58XwCqAQAAAA==.Ästra:BAAALgADCggJCAAAAA==.',
['Æi']='Æix:BAEALgAECgEJAQABLgAFFAgJHgADALERAA==.',
['Æl']='Ælxx:BAEALgAECgYJBwABLgAFFAgJHgADALERAA==.',
['Ðe']='Ðeathless:BAAALgADCgUJBQAAAA==.',
['Øm']='Ømnium:BAABLgAECn82AAIJAAcJbgseuwAPAQAJAAcJbgseuwAPAQAAAA==.',
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
