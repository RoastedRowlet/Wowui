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

local lookup = {'Shaman-Restoration','DeathKnight-Unholy','Mage-Frost','Warrior-Fury','Druid-Balance','DeathKnight-Blood','DeathKnight-Frost','Evoker-Augmentation','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','Unknown-Unknown','Hunter-BeastMastery','Druid-Feral','Paladin-Protection','Hunter-Survival','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Warrior-Arms','Priest-Holy','Shaman-Elemental','Hunter-Marksmanship','Monk-Brewmaster','Warlock-Destruction','Warlock-Demonology','Monk-Mistweaver','Druid-Guardian','Rogue-Assassination','Rogue-Outlaw','Priest-Discipline','Warlock-Affliction','DemonHunter-Havoc','Evoker-Devastation','Evoker-Preservation','Shaman-Enhancement','Mage-Fire','DemonHunter-Vengeance',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=46,date='2026-07-28',data={Ab='Abelas:BAAALgAECgYJCwAAAA==.Abracadavr:BAAALgAECgIJAgAAAA==.Abracadaxis:BAAALgADCggJCAAAAA==.',
Ad='Adallyn:BAAALgADCgYJCgAAAA==.Adzen:BAAALgAECgQJBQAAAA==.Adêrna:BAABLgAECn87AAIBAAkJzh+2AgCOAgABAAkJzh+2AgCOAgAAAA==.',
Af='Affliction:BAAALgADCgUJBQAAAA==.Aftermathz:BAAALgAECgMJAQAAAA==.',
Ag='Agba:BAABLgAFFH8PAAICAAQJRwaDiQD3AAACAAQJRwaDiQD3AAAAAA==.',
Ah='Ahktari:BAAALgADCgcJBwAAAA==.',
Al='Alaidan:BAAALgAECgkJDQAAAA==.Alanus:BAABLgAECn8rAAIDAAkJMBE5XADJAQADAAkJMBE5XADJAQAAAA==.Alarion:BAAALgAECgQJBwAAAA==.Alavia:BAABLgAECn8/AAIEAAkJfxg+GgAcAgAEAAkJfxg+GgAcAgAAAA==.Alderon:BAAALgAECgQJBQAAAA==.Alinäs:BAABLgAECn8hAAIDAAkJHQ/lYwC2AQADAAkJHQ/lYwC2AQAAAA==.Aliën:BAAALgADCgcJCQAAAA==.Alliumoo:BAABLgAECn8XAAIFAAYJwQkBRwASAQAFAAYJwQkBRwASAQAAAA==.Altana:BAABLgAECn8ZAAMGAAkJThN1HQBsAQAGAAkJNRB1HQBsAQAHAAMJSRXrIADGAAABLgAFFAMJBwAIAO4UAA==.Alydrus:BAACLgAFFH8FAAIDAAIJ1AY4qwB/AAADAAIJ1AY4qwB/AAAuAAQKfz0AAgMACQl/F6cLAIwBAAMACQl/F6cLAIwBAAAA.Alíen:BAAALgAECgQJBAAAAA==.',
Am='Amnesian:BAAALgAECgkJAgAAAA==.',
An='Anberlinean:BAABLgAECn8WAAIJAAYJ5geytAAbAQAJAAYJ5geytAAbAQAAAA==.Angryelf:BAAALgAECgEJAQAAAA==.Angzhixing:BAAALgADCgIJAgAAAA==.Anitasummon:BAAALgAECgEJAQAAAA==.Ankles:BAEALgADCgcJBwABLgAFFAQJDgAKAB8RAA==.Annahe:BAABLgAECn8YAAILAAkJjxs+EwAkAgALAAkJjxs+EwAkAgAAAA==.Annale:BAAALgAECgQJBQABLgAECgkJGAALAI8bAA==.Annatara:BAAALgAECgQJCgAAAA==.Anran:BAAALgADCgEJAQAAAA==.Anub:BAAALgADCgYJBgAAAA==.Anzala:BAAALgAECgYJDAAAAA==.',
Ao='Aoba:BAAALgAECgYJCwAAAA==.',
Ar='Arba:BAAALgAECgQJCAAAAA==.Areliss:BAAALgAECgUJBQAAAA==.Armsmaster:BAABLgAECn80AAICAAgJmiAqNQAqAgACAAgJmiAqNQAqAgAAAA==.Artemistha:BAAALgAECggJDwAAAA==.',
As='Asalynn:BAAALgADCgEJAQAAAA==.Asché:BAAALgAECgEJAgAAAA==.',
Av='Avalina:BAAALgAECgEJAQAAAA==.Avengharambe:BAAALgADCgcJBwAAAA==.Averan:BAAALgAECgYJEQAAAA==.Averybug:BAAALgAECgkJAQAAAA==.',
Az='Azarke:BAAALgAECgEJAgAAAA==.',
Ba='Backbeamz:BAAALgAECgYJCQAAAA==.Backspace:BAAALgADCgYJBgAAAA==.Badgër:BAAALgAECgEJAQAAAA==.Baey:BAAALgADCgMJAwABLgAECgkJOwADAMIeAA==.Balduun:BAAALgAECgEJAwAAAA==.Barelycastin:BAABLgAECn8kAAIBAAcJKxhfBwC4AQABAAcJKxhfBwC4AQAAAA==.Bashdadargon:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Bashoomba:BAAALgAECgQJBQAAAA==.',
Be='Bear:BAABLgAECn8gAAINAAgJVSDBGQCLAgANAAgJVSDBGQCLAgAAAA==.Bearnaked:BAAALgADCgIJAgAAAA==.Bebebluz:BAAALgAECgYJDgAAAA==.Beets:BAAALgAECgEJAQAAAA==.Belgarathh:BAAALgAFFAIJAgAAAA==.Bellíon:BAAALgAECgcJEgAAAA==.Beryline:BAAALgADCgEJAQAAAA==.',
Bi='Bird:BAAALgADCgEJAQAAAA==.Bison:BAAALgAECgMJAwABLgAECgEJAQAMAAAAAA==.Bixee:BAAALgAECgUJCQAAAA==.',
Bj='Bjorii:BAAALgAECgEJAQABLgAECgQJBAAMAAAAAA==.',
Bl='Blacat:BAABLgAECn84AAMOAAkJCSLrAQAWAwAOAAkJCSLrAQAWAwAFAAIJUAM/eABEAAAAAA==.Bleen:BAAALgAECgUJDAAAAA==.Blitzcomets:BAAALgAECgEJAwAAAA==.Bloodbenders:BAAALgADCgEJAQAAAA==.Blueday:BAAALgAECgUJBQAAAA==.',
Bo='Boagries:BAAALgADCgIJAgAAAA==.Bogeyman:BAABLgAECn81AAIPAAkJrSBsAwDeAgAPAAkJrSBsAwDeAgAAAA==.Boondoks:BAABLgAECn8gAAIKAAcJTh0XIAADAgAKAAcJTh0XIAADAgABLgAECgkJQgABAEYfAA==.Borda:BAAALgAECggJCAAAAA==.Bowrider:BAAALgAECgYJBwAAAA==.',
Br='Breer:BAAALgAECgEJAQAAAA==.Brondeadeye:BAAALgAECgUJBwAAAA==.Brunore:BAAALgAECgYJDAAAAA==.Brìan:BAAALgAECgcJEwAAAA==.',
Bu='Bubbajüdd:BAAALgADCgEJAQAAAA==.Bubbleandout:BAAALgAECgEJAQABLgAECgkJPwAQADYXAA==.',
Ca='Caledur:BAAALgAECgYJDAAAAA==.Caliandra:BAAALgAECgEJAQAAAA==.Caratdeullie:BAAALgAECggJCQAAAA==.Careblair:BAAALgADCgkJCQAAAA==.',
Ch='Chakrah:BAABLgAECn8YAAIRAAcJ/gnZNQA9AQARAAcJ/gnZNQA9AQAAAA==.Challan:BAABLgAFFH8GAAISAAMJtALNdwCSAAASAAMJtALNdwCSAAAAAA==.Chimint:BAAALgAECgkJCQAAAA==.Chloe:BAABLgAECn8XAAITAAkJ9AHJ1wAtAAATAAkJ9AHJ1wAtAAAAAA==.Chrno:BAABLgAECn8YAAITAAgJ5xEUNQDHAQATAAgJ5xEUNQDHAQAAAA==.Chunkymonkey:BAAALgADCgYJBgABLgAFFAQJIQADABwRAA==.',
Ci='Cirilá:BAAALgAECgMJAQAAAA==.',
Cl='Cleric:BAAALgAECgYJCgAAAA==.Clutcha:BAABLgAECn8cAAIUAAYJKh3QKgBCAQAUAAYJKh3QKgBCAQAAAA==.Clutchcross:BAAALgAECgQJBgABLgAECgYJHAAUACodAA==.Clutchplate:BAABLgAECn8jAAMVAAgJKxTLFgCNAQAVAAgJKxTLFgCNAQAWAAEJWgZyhgAjAAAAAA==.Clûtch:BAACLgAFFH8gAAICAAUJISF1SABiAQACAAUJISF1SABiAQAuAAQKfyIAAgIACQliH+42AFsCAAIACQliH+42AFsCAAAA.',
Co='Codenameblue:BAAALgADCgEJAQAAAA==.Coldphoenix:BAAALgADCgkJCgAAAA==.Coog:BAAALgADCgEJAQAAAA==.Corynthe:BAABLgAECn9XAAIXAAkJLiRWAACSAwAXAAkJLiRWAACSAwAAAA==.',
Cr='Crickie:BAABLgAECn8UAAMBAAkJsReVSACMAQABAAgJ4ReVSACMAQAYAAIJ2RDQGABjAAAAAA==.Crovaxis:BAABLgAECn8qAAMZAAkJlSEzCAD8AQAZAAgJ9yEzCAD8AQANAAIJ/BPr4ACMAAAAAA==.',
Cu='Cursecackler:BAAALgADCgYJBgAAAA==.',
Cy='Cynda:BAAALgADCgMJAwAAAA==.Cyndestine:BAAALgADCgYJBgAAAA==.Cyzarius:BAAALgAECgEJAQAAAA==.',
Da='Daddychill:BAABLgAECn8mAAIaAAkJcBTqFgDyAQAaAAkJcBTqFgDyAQAAAA==.Dahunt:BAAALgAECgcJAQAAAA==.Damekka:BAAALgAECgQJBQAAAA==.Danazer:BAAALgAECgYJBgAAAA==.Danoe:BAAALgAECgIJAgAAAA==.Danzig:BAAALgAFFAEJAQAAAA==.Darktalyn:BAABLgAECn8xAAMXAAkJgBRdGwDuAQAXAAgJFhZdGwDuAQARAAgJ2Q9jQAAOAQAAAA==.Davidaire:BAAALgAECgEJAQAAAA==.',
De='Deadpaws:BAAALgADCgMJAwAAAA==.Deathbinger:BAAALgADCgEJAQAAAA==.Deathgriped:BAABLgAECn84AAIGAAgJmBheEwDbAQAGAAgJmBheEwDbAQAAAA==.Deathhawkzz:BAACLgAFFH8TAAMbAAQJRgqLEgCjAAAcAAQJRgoSYQAFAQAbAAMJLgOLEgCjAAAuAAQKfxoAAxsACAmcFOYLAAQCABsABwn6FeYLAAQCABwABAntEYSmAPQAAAAA.Deathphoenix:BAAALgADCgcJBwAAAA==.Deathslock:BAAALgADCgQJBAAAAA==.Deekura:BAABLgAECn9hAAMCAAkJYBknBABaAgACAAkJYBknBABaAgAHAAIJlQHbOgAyAAAAAA==.Deladorana:BAAALgADCgUJBQAAAA==.Dellma:BAAALgADCgYJDAAAAA==.Delusion:BAAALgAECgYJEwAAAA==.Demmin:BAAALgADCggJCAABLgAECgkJKgADABQLAA==.Demonpapi:BAABLgAFFH8GAAIcAAMJ6AJ1kACjAAAcAAMJ6AJ1kACjAAAAAA==.Demoryx:BAEALgAECgQJBAABLgAECgkJJAAYAPwbAA==.Denjack:BAAALgAECgcJEAAAAA==.Dewayne:BAAALgAECgUJBQAAAA==.',
Dh='Dhadzen:BAAALgAECgQJCwAAAA==.',
Di='Dinak:BAAALgAECgcJEAAAAA==.Diodotus:BAAALgADCgEJAQAAAA==.Dionan:BAABLgAECn8sAAIJAAkJZRKzXwCyAQAJAAkJZRKzXwCyAQAAAA==.Dirtysouth:BAABLgAFFH8FAAIUAAMJTwyjFwC4AAAUAAMJTwyjFwC4AAABLgAFFAUJGwANADAhAA==.',
Do='Docs:BAABLgAECn8vAAIKAAgJbhmtFwBLAgAKAAgJbhmtFwBLAgAAAA==.Doks:BAABLgAECn9CAAIBAAkJRh9yDQDrAgABAAkJRh9yDQDrAgAAAA==.Dontpanic:BAEBLgAECn8oAAIdAAcJZh1UBgDGAQAdAAcJZh1UBgDGAQABLgAFFAQJDgAKAB8RAA==.Doomsnake:BAAALgADCgMJAwABLgAECgEJAQAMAAAAAA==.Dove:BAAALgADCgYJBgAAAA==.',
Dr='Drachim:BAAALgAECgEJAQAAAA==.Dragana:BAAALgAECgIJAgAAAA==.Dragomalfoy:BAAALgADCgQJBAAAAA==.Dragondznuts:BAAALgAFFAQJBAAAAA==.Dragõn:BAAALgAECgYJEwAAAA==.Drexeos:BAAALgADCgcJBwAAAA==.Drinker:BAAALgADCgUJBQAAAA==.Drunkenhealz:BAAALgAECgkJBQAAAA==.',
Du='Dunir:BAAALgAECgcJDQAAAA==.',
Ea='Ealara:BAABLgAECn8eAAINAAgJ7gl6dQBUAQANAAgJ7gl6dQBUAQAAAA==.',
Ed='Edran:BAAALgADCgcJFQAAAA==.',
Ei='Eifel:BAAALgAECgQJBAABLgAECgkJGwAJABceAA==.Eimin:BAAALgADCgYJCgAAAA==.',
El='Eldarion:BAAALgAECgMJAgAAAA==.Elfmonk:BAAALgAECgEJAQAAAA==.Ellipses:BAAALgAECgMJAwABLgAECggJMQAGAGsaAA==.',
Em='Emeraldz:BAABLgAECn8mAAILAAgJcRwbFAAaAgALAAgJcRwbFAAaAgAAAA==.',
En='Eneru:BAAALgADCgYJCAABLgAECggJHwAKAJ0XAA==.',
Er='Erebrethil:BAAALgAECgYJDwABLgAECggJOgAdANkaAA==.',
Es='Espe:BAABLgAECn8cAAIaAAkJyhM7GwDLAQAaAAkJyhM7GwDLAQAAAA==.',
Eu='Eucalyptia:BAAALgADCgQJBAAAAA==.Euli:BAABLgAFFH8LAAIeAAYJ6BrGAwCNAQAeAAYJ6BrGAwCNAQABLgAFFAgJIwAaAJ8fAA==.',
Ev='Evenin:BAAALgADCgIJAgAAAA==.',
Ex='Exoncantotem:BAAALgADCgQJBAAAAA==.',
Fa='Faenor:BAAALgAECgUJDQAAAA==.Fallen:BAABLgAECn8VAAIFAAkJ7BXrAgACAgAFAAkJ7BXrAgACAgAAAA==.Fallenvoid:BAAALgAECgEJAQAAAA==.Faynor:BAABLgAECn9GAAMaAAkJBBwkAgDIAQAaAAkJBBwkAgDIAQALAAYJbROzNQAsAQAAAA==.Faynór:BAABLgAECn8VAAIGAAgJSQscBgAjAQAGAAgJSQscBgAjAQABLgAECgkJRgAaAAQcAA==.',
Fe='Feloni:BAAALgAECgMJAwAAAA==.',
Fi='Finalone:BAAALgAECgEJAQAAAA==.Firêfly:BAABLgAECn8WAAIJAAkJ8QhlqAAqAQAJAAkJ8QhlqAAqAQAAAA==.',
Fk='Fknsteve:BAAALgADCgYJBgAAAA==.',
Fl='Flaptix:BAAALgAECgMJAwAAAA==.Flipingflerp:BAAALgAECgcJEQAAAA==.Flloran:BAAALgAECgYJDQAAAA==.Floragoth:BAAALgAECgEJAQAAAA==.Flowers:BAAALgADCgkJCQAAAA==.Fluffboi:BAABLgAECn81AAILAAkJbwpMLwBMAQALAAkJbwpMLwBMAQAAAA==.',
Fo='Fourloko:BAAALgAECgEJAQAAAA==.Foxyblue:BAABLgAECn8UAAIXAAYJTBV3NABtAQAXAAYJTBV3NABtAQAAAA==.',
Fr='Fraggle:BAECLgAFFH8OAAMKAAQJHxH5KQDXAAAKAAQJHxH5KQDXAAAJAAMJUwk7eQDDAAAuAAQKfycAAwoACAl+IBsLAMcCAAoACAl+IBsLAMcCAAkABAmtEELWAOsAAAAA.Freefromfate:BAAALgAECgEJAQAAAA==.Frogchi:BAAALgAECgkJEQAAAA==.Frostbité:BAABLgAECn83AAIPAAkJ0B/QAwDPAgAPAAkJ0B/QAwDPAgAAAA==.Fruit:BAABLgAECn8dAAIbAAcJZxJLFwDpAAAbAAcJZxJLFwDpAAAAAA==.',
Fu='Fuknak:BAAALgAECgIJAwAAAA==.Fumikiko:BAAALgADCgIJAgABLgAFFAMJBwAIAO4UAA==.Fumus:BAAALgAFFAEJAQAAAA==.Furrykarg:BAAALgAECgEJAQABLgAECgQJBgAMAAAAAA==.',
['Fà']='Fàynor:BAAALgAECggJEgABLgAECgkJRgAaAAQcAA==.',
['Fí']='Físh:BAAALgADCgYJBgABLgAFFAMJBwAIAO4UAA==.',
['Fú']='Fúzzy:BAAALgADCgEJAgABLgAFFAEJAQAMAAAAAA==.',
Ga='Gakkle:BAABLgAECn8nAAIEAAkJghviAwDLAQAEAAkJghviAwDLAQAAAA==.Galadralvia:BAABLgAECn8eAAIVAAkJRBWmEgDBAQAVAAkJRBWmEgDBAQAAAA==.Gali:BAABLgAECn8ZAAIZAAgJJQUOBQCvAAAZAAgJJQUOBQCvAAAAAA==.Ganaan:BAAALgAECgEJAwAAAA==.Garagas:BAAALgAECgIJAwAAAA==.',
Ge='Gearsofbob:BAAALgAFFAIJBAAAAA==.Gekkle:BAAALgADCgUJBQAAAA==.',
Gh='Ghorn:BAAALgAECgEJAQAAAA==.Ghoulei:BAABLgAECn82AAICAAkJzx+3GgCmAgACAAkJzx+3GgCmAgAAAA==.',
Gi='Girlscout:BAEALgAECgYJBgABLgAFFAQJDgAKAB8RAA==.',
Gl='Glaistiguain:BAAALgAECgYJCwABLgAECggJNAACAJogAA==.Glenheals:BAAALgADCgkJEgAAAA==.Glifin:BAAALgAECgcJDgAAAA==.Gloomstalkin:BAABLgAECn8/AAIQAAkJNhd9DgBDAgAQAAkJNhd9DgBDAgAAAA==.',
Gn='Gnøsis:BAAALgADCggJEQAAAA==.',
Go='Goldìelocks:BAAALgAECgUJCAAAAA==.Gom:BAAALgAECgIJAgAAAA==.Gomdrog:BAAALgAECgEJAQAAAA==.',
Gr='Gr:BAABLgAECn8oAAIfAAgJ7QzADgA4AQAfAAgJ7QzADgA4AQAAAA==.Grannecs:BAAALgADCgEJAQAAAA==.Greenygreen:BAAALgAECgEJAQAAAA==.Grimmli:BAAALgADCgEJAQAAAA==.Grizelda:BAAALgADCgQJBAAAAA==.Grizzledpaw:BAAALgAECgUJDAAAAA==.Gromcresh:BAAALgAECgUJBQAAAA==.Gryffs:BAABLgAECn86AAMVAAkJ3CCdBQC8AgAVAAkJ3CCdBQC8AgAWAAEJ1Aq1gAApAAAAAA==.',
Gu='Guenhwyn:BAAALgADCgIJAQAAAA==.Gum:BAAALgAECgcJBwABLgAECgkJNQAPAK0gAA==.Gutts:BAABLgAECn8nAAQVAAkJDSLdBQC0AgAVAAkJDSLdBQC0AgAWAAcJ3BKtLQATAQAEAAQJ0Q7wfQDFAAAAAA==.',
Ha='Hadron:BAAALgAECgQJCQAAAA==.Hahkoa:BAAALgADCgMJAwAAAA==.Haintala:BAAALgAECgEJAgAAAA==.Halomea:BAAALgADCgQJBAAAAA==.Hanukira:BAAALgADCgUJBQAAAA==.Happi:BAAALgAECgYJCQABLgAFFAkJNgASAGMiAA==.Happyhour:BAAALgAFFAEJAQABLgAFFAkJNgASAGMiAA==.Harald:BAABLgAECn8gAAMCAAkJ9g72qQAdAQACAAkJogz2qQAdAQAGAAIJ4hswPQCbAAAAAA==.Harkle:BAAALgADCgcJDQAAAA==.Haruun:BAAALgAECgIJAgAAAA==.',
He='Healyoself:BAAALgAECggJCQAAAA==.Heliõs:BAAALgAECgEJAQAAAA==.Hesmydaddy:BAABLgAECn9CAAIXAAkJLhI8BAC4AQAXAAkJLhI8BAC4AQAAAA==.',
Ho='Honcho:BAAALgAECgEJAQAAAA==.Honestie:BAAALgAECgQJCgAAAA==.Honêy:BAEALgAFFAIJAQABLgAECgkJJAAYAPwbAA==.Hotdogstand:BAACLgAFFH8bAAIUAAgJnCIoCAAlAgAUAAgJnCIoCAAlAgAuAAQKfzEABBQACQlwJQcDACADABQACQlwJQcDACADAB8ABAmEIYELAHMBACAAAQkrIq0eAFgAAAAA.',
Hu='Hukan:BAAALgAECgQJCAAAAA==.Huntarius:BAAALgAECgEJAQAAAA==.Huzzaah:BAEALgAFFAEJAQABLgAFFAQJDgAKAB8RAA==.',
Hy='Hyperius:BAAALgADCgIJAgAAAA==.',
['Hö']='Höneÿdew:BAABLgAECn8ZAAINAAgJ9Bg2LAADAgANAAgJ9Bg2LAADAgAAAA==.',
Ic='Icemann:BAAALgAECgEJAgAAAA==.',
Il='Ilidrayssel:BAABLgAECn8aAAIZAAcJbQNHIACuAAAZAAcJbQNHIACuAAAAAA==.Illida:BAAALgAECgMJCQAAAA==.Illidad:BAAALgAECgQJBAAAAA==.Ilyssara:BAAALgAECggJEwABLgAECggJMQAGAGsaAA==.',
Im='Imhappy:BAAALgAECgUJCgABLgAFFAkJNgASAGMiAA==.Imherdaddy:BAAALgAECggJCAABLgAECgkJPwAQADYXAA==.',
In='Indracus:BAAALgAECgQJCQAAAA==.Innervape:BAAALgADCgMJAwAAAA==.',
Ir='Ironfay:BAAALgAECggJCwABLgAECgkJRgAaAAQcAA==.',
It='Itakemeds:BAAALgAECgUJBQABLgAECgkJUQABAH8cAA==.',
Ja='Jacorict:BAABLgAECn8UAAIJAAYJJws90wDuAAAJAAYJJws90wDuAAAAAA==.Jagga:BAAALgADCgMJAwAAAA==.Jarrack:BAABLgAECn89AAIDAAkJrB6XBQAwAgADAAkJrB6XBQAwAgAAAA==.',
Je='Jellyhawk:BAAALgAECgEJAQAAAA==.Jessicae:BAAALgAECggJEgAAAA==.Jeuno:BAAALgAECgYJBwABLgAFFAMJBwAIAO4UAA==.',
Jo='Josephd:BAAALgADCgEJAQABLgAECggJPgAFABwcAA==.Josephedd:BAABLgAECn8+AAIFAAgJHBwYEwA8AgAFAAgJHBwYEwA8AgAAAA==.',
Ju='Judgment:BAAALgAECgEJAQAAAA==.Jukk:BAABLgAECn8qAAIDAAkJFAtRFgARAQADAAkJFAtRFgARAQAAAA==.Junazeena:BAABLgAECn88AAMYAAkJSgycBwBCAQAYAAkJSgycBwBCAQABAAIJCgKU0gA4AAAAAA==.',
Jy='Jygglypuff:BAAALgAECgUJBQAAAA==.',
Ka='Kaji:BAABLgAECn8jAAIdAAYJSROmRQBVAQAdAAYJSROmRQBVAQAAAA==.Kalistus:BAAALgAECgYJBwAAAA==.Kargfu:BAAALgAECgQJBgAAAA==.Karolat:BAAALgAECgUJBgAAAA==.Kayfabe:BAABLgAECn8bAAIDAAkJ3QNz+gAGAQADAAkJ3QNz+gAGAQAAAA==.Kayfay:BAAALgAECgMJAwAAAA==.Kazz:BAAALgAFFAEJAQAAAA==.',
Ke='Keishilda:BAABLgAECn8dAAMhAAYJKAl1UwCzAAAhAAYJKAl1UwCzAAARAAYJfQV4GABgAAAAAA==.Keladria:BAAALgAECgQJBwAAAA==.Kelirra:BAAALgADCgQJCAAAAA==.Kelvyren:BAAALgADCgEJAQAAAA==.Kenel:BAABLgAECn83AAMTAAkJhBcpGgB0AgATAAkJhBcpGgB0AgAFAAUJcRH5UADKAAAAAA==.Kerea:BAABLgAECn9PAAMTAAkJnguIBgBnAQATAAkJnguIBgBnAQAFAAMJAQsJZwCCAAAAAA==.Kerob:BAAALgAECgUJCwAAAA==.Keyarga:BAAALgADCgIJAgABLgAECgcJFgAQAM4TAA==.',
Kh='Khazargon:BAAALgAECgQJCgAAAA==.',
Ki='Kicken:BAABLgAECn9oAAQcAAkJlh5eAwBJAgAcAAgJ2hteAwBJAgAbAAUJfxxDBwC3AAAiAAEJxB/xLwBfAAAAAA==.Kitschy:BAAALgADCgEJAQAAAA==.Kittyperry:BAAALgAFFAEJAQAAAA==.Kizmo:BAAALgAECgEJAQAAAA==.',
Kn='Knome:BAABLgAECn87AAIDAAkJwh4PHQCuAgADAAkJwh4PHQCuAgAAAA==.',
Ko='Koana:BAAALgAECgkJCwAAAA==.Kororin:BAAALgAECgMJAwAAAA==.Korthelan:BAABLgAECn89AAISAAkJMxJaPADWAQASAAkJMxJaPADWAQAAAA==.Kothara:BAABLgAECn9IAAINAAkJwxqYBABiAgANAAkJwxqYBABiAgAAAA==.Kotongar:BAAALgADCgMJAwAAAA==.',
Kr='Kreeoo:BAAALgAECgIJAgAAAA==.Krimzin:BAACLgAFFH8bAAINAAUJMCGaJABzAQANAAUJMCGaJABzAQAuAAQKfx8AAw0ACAnfIZQhADwCAA0ACAnfIZQhADwCABAAAgkaEHldAD4AAAAA.Krystine:BAABLgAECn8fAAITAAcJNhXgTwBPAQATAAcJNhXgTwBPAQAAAA==.',
Ks='Kserasera:BAABLgAFFH8SAAIFAAUJ4g8QEgDmAAAFAAUJ4g8QEgDmAAAAAA==.',
Ku='Kuball:BAAALgAECgYJCgABLgAECgkJJwAVAA0iAA==.Kukuruku:BAABLgAECn8ZAAIYAAkJmwzqPQA9AQAYAAkJmwzqPQA9AQAAAA==.',
['Kì']='Kìssofdeath:BAAALgAECgUJBQAAAA==.',
['Kî']='Kîllara:BAABLgAECn8qAAIBAAkJrhW4KQAWAgABAAkJrhW4KQAWAgAAAA==.',
La='Labialicious:BAAALgAECgEJAgAAAA==.Lanfeår:BAABLgAECn8VAAICAAYJCwjL4ADTAAACAAYJCwjL4ADTAAAAAA==.Lanskies:BAABLgAECn8ZAAICAAkJPRXMMgAzAgACAAkJPRXMMgAzAgAAAA==.',
Le='Leafymeds:BAAALgAECgYJEAABLgAECgkJUQABAH8cAA==.Lebronjames:BAABLgAFFH8FAAICAAMJdhpzfwAIAQACAAMJdhpzfwAIAQAAAA==.Leiluna:BAAALgADCgkJEQAAAA==.Letheos:BAABLgAFFH8OAAIGAAUJ5xhdDAAaAQAGAAUJ5xhdDAAaAQAAAA==.Levanas:BAAALgAECgEJAQAAAA==.',
Li='Libertinne:BAABLgAECn8cAAIEAAgJMxewMwB8AQAEAAgJMxewMwB8AQAAAA==.Librarte:BAABLgAECn8/AAMJAAkJNw2BbACVAQAJAAkJNw2BbACVAQAPAAUJGAKsEQBMAAAAAA==.Ligmanuts:BAAALgAECgIJBAAAAA==.Lija:BAAALgAECgYJBgABLgAECgkJKgADABQLAA==.Lillytrae:BAAALgAECgMJBQAAAA==.Lilmeds:BAABLgAECn8XAAMhAAkJ+QcGLgBqAQAhAAkJxwcGLgBqAQAXAAgJBQRVQADtAAABLgAECgkJUQABAH8cAA==.Listie:BAAALgADCgQJBAABLgAECgQJBAAMAAAAAA==.Litty:BAABLgAECn8oAAIDAAcJASX8KwBpAgADAAcJASX8KwBpAgAAAA==.Lizrdkng:BAAALgADCgMJBgAAAA==.',
Lo='Locktärd:BAACLgAFFH8MAAQiAAQJiBsVBgAiAQAiAAQJiBsVBgAiAQAcAAIJShYXMwCtAAAbAAIJogaEDgCXAAAuAAQKfyoABCIACAmIH6oCAJACACIACAk+H6oCAJACABwACAktGRZCAAYCABsAAgkLHIJGAJwAAAAA.Lohken:BAAALgAFFAEJAQAAAA==.Loralila:BAAALgAECgUJCQABLgAECgkJHgAVAEQVAA==.Lox:BAABLgAECn9NAAMbAAkJSRohBABDAgAbAAkJSRohBABDAgAcAAIJFQSeJgFCAAAAAA==.',
Lu='Lucieb:BAAALgAECgEJAQAAAA==.',
Ly='Lydirn:BAABLgAECn8gAAQJAAkJ+RxtQAAFAgAJAAgJ3x1tQAAFAgAKAAQJzRVpVQDiAAAPAAIJoBykMQCfAAAAAA==.Lyofel:BAAALgAECgYJDwAAAA==.Lyonel:BAAALgADCggJCAAAAA==.Lysaviel:BAAALgAECgEJAgAAAA==.',
['Lí']='Lítterbox:BAABLgAFFH8GAAIOAAMJzAmABwCsAAAOAAMJzAmABwCsAAAAAA==.',
Ma='Magedzen:BAAALgAECgMJBAAAAA==.Magicguy:BAACLgAFFH8KAAIDAAMJEw0EPADMAAADAAMJEw0EPADMAAAuAAQKfxsAAgMACQlnDzNVAN0BAAMACQlnDzNVAN0BAAAA.Mahariel:BAABLgAECn8wAAINAAkJ/RD2PgDmAQANAAkJ/RD2PgDmAQAAAA==.Mahdy:BAABLgAECn9IAAIJAAkJGR3GJAByAgAJAAkJGR3GJAByAgAAAA==.Mahoe:BAAALgAECgQJCAAAAA==.Maivel:BAAALgAECgcJCAAAAA==.Malva:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.Manandaar:BAAALgAECgIJBAAAAA==.Mandret:BAAALgAECgMJBAABLgAECggJHAAdANESAA==.Manicppanic:BAEBLgAECn8gAAIUAAgJxxVrHQCrAQAUAAgJxxVrHQCrAQABLgAFFAQJDgAKAB8RAA==.Manrypurp:BAAALgAECgUJDQAAAA==.Marcie:BAABLgAECn9SAAIFAAkJ+BOABACdAQAFAAkJ+BOABACdAQAAAA==.Martinriggz:BAAALgAECgQJCAAAAA==.',
Mc='Mchammer:BAAALgAECgEJAgAAAA==.',
Me='Meatyloaf:BAABLgAECn8iAAIHAAkJcQc6CgCHAAAHAAkJcQc6CgCHAAAAAA==.Melkedrik:BAABLgAECn8cAAIjAAkJ9g6TJABTAQAjAAkJ9g6TJABTAQAAAA==.Melleren:BAAALgAECgYJCQAAAA==.Menorah:BAAALgAECgEJAQAAAA==.Messande:BAAALgAECgUJBgAAAA==.',
Mi='Minõs:BAAALgADCgkJEAAAAA==.Mirai:BAAALgADCgUJBQAAAA==.Mirei:BAABLgAECn9oAAIXAAkJ5BJqAwDqAQAXAAkJ5BJqAwDqAQAAAA==.Mistdancer:BAAALgADCgYJBgABLgAFFAIJCgAHAI0GAA==.Mitsurugi:BAAALgAECgEJAgABLgAFFAIJCgAHAI0GAA==.Miyagí:BAAALgAECgcJDgABLgAECggJGAAGAKYdAA==.',
Mo='Mochisama:BAAALgAECgYJCAAAAA==.Mojam:BAAALgAECgQJEQAAAA==.Monk:BAAALgAECgEJAQAAAA==.Monkadzen:BAAALgAECgEJBAAAAA==.Moonless:BAAALgAECgEJAgAAAA==.Moovidlin:BAABLgAECn8XAAIEAAkJBQteNQBzAQAEAAkJBQteNQBzAQABLgAECgkJKgADABQLAA==.Mordian:BAAALgAECgYJBgAAAA==.Morinnas:BAAALgAECgQJBQAAAA==.Moschpit:BAAALgADCgEJAQAAAA==.',
Mu='Mugruss:BAAALgADCggJCAAAAA==.Munkeez:BAAALgADCgMJAwAAAA==.Murdermoo:BAAALgADCgMJAwAAAA==.Murkessa:BAAALgAECgQJBwAAAA==.Mushhead:BAAALgAECgUJCAAAAA==.Mustepin:BAAALgAECgQJBAABLgAFFAQJEAAEAEobAA==.',
My='Myishaa:BAAALgADCgIJAgAAAA==.Mykeal:BAAALgADCgMJBQAAAA==.Myndigo:BAAALgAECgEJAQAAAA==.Mystryl:BAAALgADCgkJEQAAAA==.Mythantherox:BAABLgAFFH8HAAIWAAMJrR1YHAAJAQAWAAMJrR1YHAAJAQABLgAFFAYJFQAkAH0XAA==.',
['Mì']='Mìstra:BAAALgADCgUJBwAAAA==.',
Na='Nakkal:BAAALgAECgIJAQAAAA==.Nanlaria:BAAALgAECgEJBAAAAA==.Nargo:BAAALgADCgYJCgAAAA==.Nataliia:BAAALgAECgQJBAAAAA==.',
Ne='Necrostalker:BAAALgADCgkJCQABLgAECgEJAQAMAAAAAA==.Negative:BAAALgAECgQJCgAAAA==.Neltherius:BAAALgAECgEJAQAAAA==.Nerwende:BAAALgAECgEJAQAAAA==.Nethershade:BAABLgAECn9bAAIfAAkJpiInAAAjAwAfAAkJpiInAAAjAwAAAA==.Netherstörm:BAAALgAECgcJCgAAAA==.Nezot:BAAALgAECgEJAQABLgAECgkJHAACACERAA==.',
Ni='Niclea:BAAALgAECgQJBAAAAA==.Nightelm:BAACLgAFFH8HAAQIAAMJ7hQ/QgC+AAAIAAMJ7hQ/QgC+AAAkAAEJnBKoDQBIAAAlAAEJZgQCMAAmAAAuAAQKfysABAgACQltHw8LAKgCAAgACQlnHw8LAKgCACUABgleDBY0AM0AACQABAn3G3UZAIkAAAAA.Ninym:BAAALgAECgEJAQAAAA==.Niënor:BAABLgAECn86AAIdAAgJ2RoQBQDtAQAdAAgJ2RoQBQDtAQAAAA==.',
Nj='Njorvir:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.',
No='Noslien:BAAALgAECgUJBwAAAA==.Nostradamuz:BAAALgAECgEJAQAAAA==.Novasong:BAAALgAECgEJAwAAAA==.',
Ny='Nymneria:BAABLgAECn8YAAIbAAgJgQ2DFgDyAAAbAAgJgQ2DFgDyAAAAAA==.Nyxiera:BAAALgAECggJCAABLgAFFAQJKQAVALUaAA==.Nyxstonia:BAACLgAFFH8pAAIVAAQJtRpbCgAJAQAVAAQJtRpbCgAJAQAuAAQKf10AAxUACQnvIKsAAOkCABUACQnvIKsAAOkCAAQACAk8DYgIADMBAAAA.',
Ob='Oballi:BAAALgAECgUJBwAAAA==.',
Od='Oddsaint:BAAALgAECgEJAwAAAA==.',
Ol='Olierra:BAAALgAECgYJDAAAAA==.',
On='Onlyvoids:BAAALgAECgMJAwAAAA==.',
Or='Oreshin:BAAALgAECgYJBgAAAA==.Orhan:BAAALgAECgQJBAABLgAECgkJRgAaAAQcAA==.Ornac:BAAALgADCgcJEAAAAA==.',
Ot='Otkspring:BAACLgAFFH8HAAMEAAMJHwonPQC5AAAEAAMJZggnPQC5AAAWAAEJPwecQwBAAAAuAAQKfxkAAgQABwmAF/ktAJkBAAQABwmAF/ktAJkBAAAA.Otto:BAABLgAECn8pAAIJAAkJ2hHLXwCxAQAJAAkJ2hHLXwCxAQAAAA==.Ottomagus:BAABLgAECn8fAAIDAAkJAxVmCADNAQADAAkJAxVmCADNAQAAAA==.',
Ox='Oxadin:BAAALgAECgEJAQAAAA==.Oxideous:BAAALgADCgMJAwAAAA==.',
Pa='Paleale:BAABLgAECn8VAAIYAAYJ7wztXQDLAAAYAAYJ7wztXQDLAAAAAA==.Pallyshore:BAAALgADCgMJAwAAAA==.Pallywack:BAAALgAECggJCQAAAA==.Pampoovy:BAEALgADCgMJAwABLgAECgkJFwAQAA4ZAA==.Pandapunk:BAAALgAECggJDgAAAA==.Panic:BAAALgAECgEJAgAAAA==.Pantoponrose:BAAALgAECgYJEQAAAA==.Pastorbash:BAAALgADCggJCQAAAA==.',
Pb='Pb:BAAALgAECgMJAwAAAA==.',
Pe='Persephoneia:BAABLgAECn8mAAIRAAkJYxF0IgC0AQARAAkJYxF0IgC0AQAAAA==.',
Pi='Pitnick:BAAALgAECgMJAwAAAA==.',
Pk='Pkashmuk:BAAALgADCgcJBwAAAA==.',
Pr='Prophettool:BAABLgAECn8oAAMJAAkJlAsIgwBpAQAJAAkJlAsIgwBpAQAKAAQJigQEfQCGAAAAAA==.Pruned:BAAALgADCgcJBwABLgAFFAQJDAAiAIgbAA==.',
Pu='Punjistake:BAAALgAECgYJBgAAAA==.',
['Pï']='Pïzzasteve:BAAALgAECgIJAgABLgAFFAEJAQAMAAAAAA==.',
Qu='Quanchii:BAAALgADCgMJAwAAAA==.Quna:BAAALgAECgUJBQAAAA==.',
Ra='Raemie:BAAALgAECgQJCgAAAA==.Ragequit:BAABLgAECn8WAAIVAAgJwhfEFACmAQAVAAgJwhfEFACmAQABLgAECggJMQAGAGsaAA==.Raikoho:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.Rakulm:BAAALgADCgUJCgAAAA==.Ravenloare:BAAALgAECgQJBAAAAA==.Ravenrest:BAEBLgAECn8vAAIRAAgJqx7GEgA8AgARAAgJqx7GEgA8AgAAAA==.',
Re='Reaverheim:BAABLgAECn8ZAAQVAAYJAx8PFgCWAQAVAAYJYx4PFgCWAQAEAAQJfxcqZQAeAQAWAAIJBR0lSgCkAAAAAA==.Rehab:BAAALgAFFAIJAgABLgAECggJMQAGAGsaAA==.Reiko:BAAALgADCgkJIQABLgAECgkJaAAXAOQSAA==.Remuz:BAAALgAECgUJCwAAAA==.Rennwick:BAAALgAECgQJBgAAAA==.Renriss:BAAALgAECgcJCQABLgAECggJOAAGAJgYAA==.Rey:BAAALgAECgkJEQAAAA==.',
Rh='Rhe:BAAALgAECgIJAgABLgAECgkJEQAMAAAAAA==.',
Ri='Rilz:BAABLgAECn8qAAICAAkJ3SDmHQCUAgACAAkJ3SDmHQCUAgAAAA==.',
Ro='Rochambeu:BAAALgADCgEJAQAAAA==.Rockasham:BAAALgAECgQJCgAAAA==.Rockyrogue:BAAALgAECgEJAQAAAA==.Rodgerwabbet:BAAALgAECgQJBAAAAA==.Roiddemon:BAAALgADCgQJBAABLgAECggJKwAcABcUAA==.Roiddrood:BAAALgAECgIJAgABLgAECggJKwAcABcUAA==.Roidlock:BAABLgAECn8rAAIcAAgJFxRoVgCZAQAcAAgJFxRoVgCZAQAAAA==.Roidtank:BAAALgAECgUJDAABLgAECggJKwAcABcUAA==.Rongyi:BAAALgADCgIJAgAAAA==.Rosaline:BAAALgAECgYJDgAAAA==.Rosewood:BAAALgAECgkJCAAAAA==.Rottn:BAABLgAECn8xAAMGAAgJaxouBACBAQAGAAgJaxouBACBAQACAAEJrgPgnQEhAAAAAA==.Rottnshot:BAAALgADCgYJBgABLgAECggJMQAGAGsaAA==.Rottyn:BAABLgAECn8jAAIPAAgJJBujAQAbAgAPAAgJJBujAQAbAgABLgAECggJMQAGAGsaAA==.',
Ru='Runerion:BAAALgAECgEJBQAAAA==.',
Ry='Ry:BAAALgAECgYJBQABLgAECgkJEQAMAAAAAA==.',
['Rà']='Ràìn:BAABLgAECn8WAAIDAAgJAgnuoQA4AQADAAgJAgnuoQA4AQAAAA==.',
Sa='Sacrothoth:BAAALgAECgEJAgAAAA==.Safmen:BAABLgAECn8bAAQVAAYJwQdsNgCeAAAVAAYJjAdsNgCeAAAWAAMJMgXiaQBOAAAEAAEJCAr0ogA9AAAAAA==.Sanikoa:BAAALgAECgUJCwAAAA==.Sanlen:BAAALgAECgEJAQABLgAECgkJPQASADMSAA==.Saraid:BAABLgAECn8vAAQTAAkJ9RgHFwCOAgATAAkJ9RgHFwCOAgAFAAUJVRAZFABsAAAeAAIJvQUOeAAtAAAAAA==.Saravase:BAABLgAECn8ZAAIBAAcJJQgDHQCGAAABAAcJJQgDHQCGAAAAAA==.Sardel:BAAALgADCgcJBwAAAA==.Sargeros:BAAALgAECgQJBQAAAA==.Savidlin:BAAALgAECgEJAQABLgAECgkJKgADABQLAA==.Sazem:BAAALgADCgIJAgAAAA==.',
Se='Sedaldra:BAAALgADCgYJCwAAAA==.',
Sh='Shadowgo:BAAALgAECgEJAQAAAA==.Shadowi:BAAALgAECgQJBQAAAA==.Shadownights:BAABLgAECn9AAAIRAAkJcxhXAwDeAQARAAkJcxhXAwDeAQAAAA==.Shadowpope:BAAALgAECgkJBgAAAA==.Shadowstorm:BAAALgADCgYJCQAAAA==.Shamadzen:BAAALgAECgEJAQAAAA==.Shamoneyy:BAAALgADCgUJBQAAAA==.Shanksinatra:BAAALgAECgEJAQAAAA==.Shazi:BAEBLgAECn8kAAMYAAkJ/BuNEgBbAgAYAAkJ/BuNEgBbAgAmAAEJ8Ao1LAA1AAABLgAECgkJJAAYAPwbAA==.Shiki:BAAALgADCgkJEwABLgAECgkJaAAXAOQSAA==.Shimnar:BAAALgAECggJEwABLgAECggJHAAEADMXAA==.Shinifur:BAAALgADCgUJBgAAAA==.Shinoto:BAABLgAECn8ZAAMDAAYJISAxWgDPAQADAAYJISAxWgDPAQAnAAEJDxXQEgA/AAAAAA==.Shiritá:BAAALgAECgMJAgAAAA==.Shockazam:BAAALgAECgcJEgAAAA==.Shrewby:BAAALgAECgEJAQAAAA==.Shyandra:BAAALgADCgYJBgAAAA==.',
Si='Sieghart:BAAALgAECgEJBAAAAA==.Silverstead:BAAALgAECgYJEgAAAA==.Six:BAAALgAECgUJCwABLgAFFAEJAQAMAAAAAA==.',
Sk='Skylines:BAAALgAECgQJBAAAAA==.',
Sl='Sloptop:BAAALgAECgEJAgAAAA==.',
Sn='Snarkyshaman:BAAALgAECgQJBAABLgAECggJMQAGAGsaAA==.Snickersbar:BAAALgADCgUJCAAAAA==.Snowynn:BAAALgAECgYJEgAAAA==.Snöw:BAABLgAECn8pAAIDAAkJGhVhQQAYAgADAAkJGhVhQQAYAgAAAA==.Snöwy:BAAALgAECgQJBAAAAA==.',
So='Sojudevourer:BAAALgAECgEJAQAAAA==.Southpaw:BAAALgAECgMJAwAAAA==.',
Sp='Spooki:BAAALgAECgEJAQAAAA==.Spyro:BAABLgAECn8wAAQIAAkJLA99GgD2AQAIAAkJLA99GgD2AQAlAAgJtBQsEQC4AQAkAAIJYw5CIwA/AAAAAA==.',
Sr='Sron:BAABLgAECn8qAAINAAkJQx1qPQDrAQANAAkJQx1qPQDrAQAAAA==.',
St='Stabalagmite:BAAALgAECgQJBAABLgAECggJMQAGAGsaAA==.Stariah:BAABLgAECn8kAAIDAAgJPgttjQBcAQADAAgJPgttjQBcAQAAAA==.Stawn:BAAALgADCgEJAQAAAA==.Stupid:BAAALgADCgIJAgAAAA==.',
Su='Sumwhiteguy:BAAALgAECgEJAQAAAA==.',
Sw='Sweetbeef:BAAALgAECgIJAgAAAA==.Swooze:BAACLgAFFH8WAAIDAAUJHhfaLQALAQADAAUJHhfaLQALAQAuAAQKfzsAAgMACQndHVEcALICAAMACQndHVEcALICAAAA.',
Sy='Sylrythriana:BAABLgAECn8ZAAMUAAcJfwSwNQD/AAAUAAcJfwSwNQD/AAAfAAIJCwIIKQAxAAABLgAECgkJHgAVAEQVAA==.Syndar:BAAALgAECgQJBQABLgAECgkJJAADAOkhAA==.Syndicate:BAAALgAECgcJDQAAAA==.Syrenis:BAAALgADCgkJDwABLgAFFAMJBwAIAO4UAA==.',
['Sù']='Sùnnydk:BAAALgADCgcJBwAAAA==.',
Ta='Tahoe:BAAALgADCgYJBgABLgAFFAcJIwASAKoUAA==.Talwaz:BAAALgADCgkJDgAAAA==.Tankinbur:BAAALgAECgYJDQAAAA==.Tanzri:BAAALgAECgMJAwAAAA==.Tarlyn:BAACLgAFFH8MAAIKAAMJCg2yNACcAAAKAAMJCg2yNACcAAAuAAQKfzgABAoACQlcF24XAE4CAAoACQlcF24XAE4CAAkABglcGoyOAFUBAA8AAQkAANI/AD4AAAAA.Tatslight:BAABLgAECn84AAIPAAgJMR08AgDdAQAPAAgJMR08AgDdAQABLgAECggJOAAPADEdAA==.Tatsrage:BAAALgAECgEJAQABLgAECggJOAAPADEdAA==.Tazaral:BAAALgADCgEJAQABLgAECgkJCwAMAAAAAA==.',
Te='Ted:BAEBLgAFFH8QAAMTAAYJLxMgDQBJAQATAAYJLxMgDQBJAQAFAAIJzwHwKAA9AAABLgAFFAQJDgAKAB8RAA==.Temuadêrna:BAAALgAECgQJBAAAAA==.Teysá:BAAALgADCgEJAQAAAA==.',
Th='Thalasso:BAAALgADCgEJAgAAAA==.Thor:BAAALgAECgYJCAAAAA==.Thyandris:BAAALgADCgYJCwAAAA==.Thánátós:BAAALgAECgQJBwAAAA==.',
Ti='Tichar:BAAALgADCgYJBgAAAA==.Timmthemage:BAAALgAECgUJBwABLgAECgEJAQAMAAAAAQ==.Timthehunter:BAAALgAECgEJAQAAAQ==.Timthepally:BAAALgAECggJDAABLgAECgEJAQAMAAAAAQ==.Tinytex:BAABLgAECn8oAAIaAAkJyw7VIwCMAQAaAAkJyw7VIwCMAQAAAA==.Tisiphoneia:BAAALgAECgQJBgAAAA==.',
To='Toberson:BAAALgAECgEJAQAAAA==.Tom:BAAALgAECgQJBAAAAA==.Toxicbanana:BAABLgAECn8VAAIEAAYJeg96DwDDAAAEAAYJeg96DwDDAAAAAA==.',
Tr='Tradarynn:BAABLgAECn8hAAIJAAkJ7hujIACEAgAJAAkJ7hujIACEAgAAAA==.Trayvein:BAAALgADCgUJBQAAAA==.Trekk:BAAALgAECgcJBQAAAA==.Tress:BAABLgAECn8UAAImAAYJLx5YEgCQAQAmAAYJLx5YEgCQAQAAAA==.',
Ts='Tsindre:BAAALgAECgEJAgAAAA==.Tsukong:BAAALgAECgEJAQAAAA==.',
Tu='Tulkar:BAABLgAECn8UAAITAAgJchmTAgBJAgATAAgJchmTAgBJAgAAAA==.Turambar:BAAALgAECgEJAQAAAA==.',
Ty='Tyriir:BAAALgADCgQJBgAAAA==.Tyviae:BAAALgAECgIJAgAAAA==.',
Um='Umbravine:BAAALgAECggJEgABLgAECggJMQAGAGsaAA==.Umbrax:BAAALgAECgQJBQAAAA==.',
Un='Unholymochi:BAABLgAECn8lAAICAAkJHiAgWwC1AQACAAkJHiAgWwC1AQAAAA==.',
Us='Usdaprime:BAABLgAFFH8JAAMFAAMJdwO8IABkAAAFAAMJdwO8IABkAAAOAAEJtQKLFQAeAAAAAA==.',
Uw='Uwuzi:BAAALgADCgQJBAAAAA==.',
Va='Valhalia:BAABLgAECn8UAAMcAAgJ6ReEcgBVAQAcAAYJKBiEcgBVAQAbAAMJbg6pQgCqAAAAAA==.Vanyllapea:BAAALgAECgMJAwAAAA==.Varaelitha:BAAALgAECgMJAwAAAA==.Vashan:BAAALgAECgQJBQAAAA==.Vashni:BAAALgAECgkJDAAAAA==.',
Ve='Velinariae:BAAALgADCgYJEAAAAA==.Vengful:BAABLgAECn86AAMjAAkJZB1+AgAVAgAjAAkJZB1+AgAVAgAoAAIJoBeAJAB7AAAAAA==.',
Vi='Vira:BAAALgAECgIJAgAAAA==.Vivy:BAABLgAECn8fAAQcAAkJNhThLwBNAgAcAAkJzRPhLwBNAgAbAAQJaxSaMwDpAAAiAAIJBhXMJgBWAAAAAA==.',
Vo='Vord:BAAALgAECgIJAgAAAA==.Vorumbrae:BAAALgAECgYJCAAAAA==.',
Vu='Vultus:BAAALgAECgIJAgAAAA==.',
Vy='Vylthyra:BAAALgADCgEJAQABLgAECggJMQAGAGsaAA==.Vyrkin:BAAALgAECgEJAQAAAA==.Vyrul:BAAALgAECgQJBAABLgAECgQJBAAMAAAAAA==.',
['Vä']='Väntage:BAAALgADCgEJAQAAAA==.',
Wa='Wagyubeef:BAABLgAECn8kAAIEAAkJghdYIADtAQAEAAkJghdYIADtAQAAAA==.Wali:BAABLgAECn8gAAMcAAgJMRPKXQCFAQAcAAgJMRPKXQCFAQAbAAEJAAB9dgAuAAAAAA==.Warlodzen:BAAALgADCgcJBwAAAA==.Wayne:BAAALgAECgQJBAAAAA==.',
We='Weebey:BAAALgADCgEJAQAAAA==.Wenson:BAABLgAECn8cAAMCAAkJIRHfRwDqAQACAAkJIRHfRwDqAQAGAAkJ2wSHOQCtAAAAAA==.',
Wh='Whatupbruh:BAACLgAFFH8SAAMQAAQJ+RIOCwDdAAAQAAQJbxEOCwDdAAANAAMJRxDRawDMAAAuAAQKfyQABBAABwkcIh4HAIgCABAABwm5IR4HAIgCAA0AAQkJG1EcAUAAABkAAQndBnKSACgAAAAA.',
Wi='Wildfire:BAAALgAECgcJBwAAAA==.',
Wo='Wooties:BAAALgAECgcJCgABLgAECgkJQgABAEYfAA==.',
Wy='Wyleriya:BAABLgAECn85AAIcAAkJ+Ak9bQBhAQAcAAkJ+Ak9bQBhAQAAAA==.',
Xa='Xanthas:BAAALgADCgQJBAAAAA==.',
Xc='Xcella:BAAALgAECgUJCAAAAA==.',
Xe='Xephon:BAAALgADCgcJBwAAAA==.',
Xi='Xina:BAAALgAECgEJAQAAAA==.',
Xw='Xweakling:BAAALgADCgYJCAABLgAFFAQJEAAEAEobAA==.',
Xy='Xyn:BAAALgADCggJCAABLgAECgkJEQAMAAAAAA==.',
Ya='Yamonu:BAAALgADCgEJAQAAAA==.',
Ye='Yelizaveta:BAABLgAECn8cAAINAAYJCAVcLwB2AAANAAYJCAVcLwB2AAAAAA==.',
Yl='Ylfcwen:BAAALgAECgEJAQAAAA==.',
Yo='Yodey:BAACLgAFFH8MAAICAAQJOB/aRABrAQACAAQJOB/aRABrAQAuAAQKfzEAAgIACQlwI54HADkDAAIACQlwI54HADkDAAAA.Yoovee:BAAALgAECggJCAAAAA==.Yorsdon:BAAALgAECgIJAgAAAA==.',
Yu='Yuaetrende:BAACLgAFFH8OAAIjAAQJex4CDQBBAQAjAAQJex4CDQBBAQAuAAQKfzIAAiMACQlzI9wDABMDACMACQlzI9wDABMDAAAA.Yumii:BAABLgAECn8hAAMXAAkJPSUjAgCJAwAXAAkJECUjAgCJAwAhAAYJ/yH2DgBNAgAAAA==.',
Za='Zack:BAAALgAECgYJEwAAAA==.Zaerie:BAAALgADCgcJBwAAAA==.Zagul:BAAALgAECgUJCAAAAA==.Zalarah:BAAALgAECgUJDQAAAA==.Zalarilia:BAAALgAECgEJAQAAAA==.Zanoo:BAAALgADCgYJBwAAAA==.Zaphod:BAAALgAECgMJAwAAAA==.Zardan:BAABLgAECn81AAIcAAkJcBIXBQDiAQAcAAkJcBIXBQDiAQAAAA==.',
Zi='Ziegler:BAAALgADCgYJBgAAAA==.',
Zu='Zuggasaurus:BAABLgAECn8gAAUOAAkJHho+CABMAgAOAAkJ1Bk+CABMAgAeAAUJoRU1IwA2AQAFAAYJ+BL+CAAQAQATAAIJVg1sqQBhAAAAAA==.Zuggerker:BAAALgAECggJCwABLgAECgkJIAAOAB4aAA==.Zugglite:BAABLgAECn8oAAQKAAgJMCEyFwBYAgAKAAgJMCEyFwBYAgAPAAQJ2xotHwAaAQAJAAEJdgmCtAEoAAABLgAECgkJIAAOAB4aAA==.Zulthar:BAABLgAECn8aAAIDAAgJ8Qo4rAAnAQADAAgJ8Qo4rAAnAQAAAA==.',
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
