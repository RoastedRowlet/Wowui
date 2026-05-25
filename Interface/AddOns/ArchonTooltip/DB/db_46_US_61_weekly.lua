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

local lookup = {'DeathKnight-Frost','Hunter-BeastMastery','Hunter-Survival','Warrior-Fury','Warrior-Arms','Warlock-Demonology','Druid-Balance','Shaman-Elemental','Paladin-Retribution','Unknown-Unknown','Priest-Discipline','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Warrior-Protection','Monk-Windwalker','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DemonHunter-Havoc','Rogue-Subtlety','Warlock-Affliction','Warlock-Destruction','DemonHunter-Devourer','Monk-Mistweaver','Priest-Holy','Druid-Guardian','Rogue-Assassination','Paladin-Holy','Druid-Restoration','Hunter-Marksmanship','Paladin-Protection','Priest-Shadow','Monk-Brewmaster','Druid-Feral',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abaddonmoon:BAABLgAECn8oAAIBAAgJvQZhEwD/AAABAAgJvQZhEwD/AAAAAA==.',
Ad='Addvar:BAAALgADCgEJAQAAAA==.Adelost:BAAALgAECgQJBQAAAA==.',
Ah='Ahalina:BAAALgAECgYJBwAAAA==.Ahnari:BAACLgAFFH8FAAICAAMJdgJ5DwDMAAACAAMJdgJ5DwDMAAAuAAQKfxUAAwIACAlAEVg9ALkBAAIACAlAEVg9ALkBAAMABAm8AoQmAIsAAAAA.',
Ai='Ailinaa:BAACLgAFFH8eAAMEAAYJTht6BQCbAQAEAAUJBRx6BQCbAQAFAAUJ8xdfCgBUAQAuAAQKfyAAAwQACQkkH8kVAJ8CAAQACAkpH8kVAJ8CAAUABAnjF4QkABcBAAAA.',
Ak='Akalifato:BAACLgAFFH8FAAIGAAMJ6RdDUQD6AAAGAAMJ6RdDUQD6AAAuAAQKfxQAAgYABwldFlFTAIsBAAYABwldFlFTAIsBAAEuAAUUBwkcAAcACxwA.Akroma:BAAALgAECgIJBAAAAA==.',
Al='Alariya:BAAALgAECgUJBQAAAA==.Alerat:BAAALgADCgMJAwABLgAECggJHAAIAMEJAA==.Alistin:BAAALgAECggJEgAAAA==.Alistïn:BAAALgAECgEJAgAAAA==.Alone:BAAALgADCgQJAwAAAA==.Alstir:BAAALgAECgEJAQAAAA==.',
Am='Amaryllis:BAAALgAECgEJAQAAAA==.Ambivalent:BAAALgAECgQJBgAAAA==.',
Ar='Aradin:BAAALgAECgEJAQAAAA==.Archanfel:BAABLgAECn8vAAIDAAgJSQ9RHACcAQADAAgJSQ9RHACcAQAAAA==.Argasha:BAAALgADCgUJBQAAAA==.',
As='Asriel:BAAALgAECgcJDAAAAA==.',
At='Atraxa:BAAALgAECgYJCwAAAA==.',
Aw='Awsomweorc:BAAALgADCgEJAQAAAA==.',
Ay='Ayonna:BAABLgAECn8WAAIJAAYJCgYPzADTAAAJAAYJCgYPzADTAAAAAA==.',
Az='Azar:BAAALgADCgUJBQABLgAECgEJAQAKAAAAAA==.',
Ba='Bandie:BAAALgAECgYJEQAAAA==.Barksalot:BAAALgAECgcJBwAAAA==.Barrakum:BAAALgAECgUJDgAAAA==.Bayn:BAAALgADCgQJCQAAAA==.',
Be='Beeftruck:BAACLgAFFH8KAAMEAAMJ8hTXJgDgAAAEAAMJAxTXJgDgAAAFAAIJtwi8JQBzAAAuAAQKfysAAwUACAn1IRMHAGMCAAUACAnmHxMHAGMCAAQABwn7HnomAKABAAAA.Belletrixx:BAAALgAECgYJEwAAAA==.Berried:BAABLgAECn9AAAILAAkJGSA5BAA1AwALAAkJGSA5BAA1AwAAAA==.',
Bi='Biigmâc:BAABLgAECn8WAAIIAAcJ6QUdSwAbAQAIAAcJ6QUdSwAbAQAAAA==.Biminem:BAABLgAECn8dAAIMAAgJbxW3CwDBAQAMAAgJbxW3CwDBAQAAAA==.',
Bl='Black:BAAALgAECgYJDAAAAA==.Blackwidow:BAAALgAECgMJAwAAAA==.Bloodshöt:BAABLgAECn8YAAMNAAgJlxmJOgDzAQANAAgJlxmJOgDzAQAOAAEJXgcTVwAYAAABLgAECgkJIQAEAHIVAA==.',
Bo='Bodak:BAABLgAECn8bAAIPAAYJ5hnRNwCjAQAPAAYJ5hnRNwCjAQAAAA==.Boricua:BAAALgAECgEJAgAAAA==.',
Br='Brakun:BAAALgADCgIJAgAAAA==.Brolly:BAAALgAECgkJAgAAAA==.Broris:BAAALgAECgMJAwABLgAECgYJCwAKAAAAAA==.Brucewii:BAAALgADCgEJAQAAAA==.Brunn:BAAALgAECgYJCwAAAA==.',
Ca='Calamari:BAAALgADCgQJBAAAAA==.Calistarius:BAACLgAFFH8GAAIQAAMJ+Q4LFwC4AAAQAAMJ+Q4LFwC4AAAuAAQKfxsAAhAACAlHEdEWAGUBABAACAlHEdEWAGUBAAAA.Caliste:BAAALgADCgIJAgABLgAFFAUJEwAMAOkeAA==.Calityy:BAAALgADCgYJBgABLgAFFAcJFQADAGUhAA==.Camine:BAABLgAECn8wAAINAAgJAR0GOQD5AQANAAgJAR0GOQD5AQAAAA==.Candrabeckya:BAAALgADCgUJBQAAAA==.Carise:BAAALgAECgQJBAAAAA==.Castalasaras:BAAALgAECgYJDgAAAA==.Castorsilver:BAAALgAECgEJAQAAAA==.',
Ce='Certified:BAAALgAECgUJBQAAAA==.',
Ch='Chickeny:BAAALgADCgEJAQAAAA==.Choppstik:BAABLgAECn8VAAIRAAYJpQUDSwCsAAARAAYJpQUDSwCsAAAAAA==.',
Co='Coldslayerck:BAAALgADCgkJCQAAAA==.Constäntine:BAAALgAECgQJBQAAAA==.Coriolis:BAABLgAECn8zAAMSAAgJfBijGgDgAQASAAgJfBijGgDgAQATAAMJggrxMACPAAAAAA==.',
Cr='Crowléy:BAAALgAECgYJEQAAAA==.',
Cu='Cuddlyowl:BAABLgAECn8XAAIUAAcJwQ4DqwCFAQAUAAcJwQ4DqwCFAQAAAA==.',
Da='Dagnamagus:BAAALgAECgYJCQAAAA==.Daire:BAAALgADCgYJBgAAAA==.Daliann:BAAALgAECgYJDAAAAA==.Damnation:BAAALgAECgYJCwAAAA==.Dangerduck:BAABLgAECn8YAAMTAAYJvxTaDgD+AAATAAQJpxTaDgD+AAASAAYJgg9XRADwAAAAAA==.Darktruth:BAAALgADCgMJAwAAAA==.Dartes:BAABLgAECn8UAAICAAcJBRODWgBnAQACAAcJBRODWgBnAQAAAA==.Dashe:BAAALgAECgcJAQAAAA==.',
De='Deathcokie:BAAALgAECgYJDgAAAA==.Deatho:BAABLgAECn8zAAMQAAgJ3CbcAQAiAwAQAAgJ3CbcAQAiAwAEAAEJCSNznQBKAAAAAA==.Deathstoned:BAAALgADCgQJBQAAAA==.Deimos:BAAALgAECgEJAQAAAA==.',
Di='Diamondshard:BAAALgAECgMJBQAAAA==.',
Dr='Draegov:BAAALgADCgYJBgAAAA==.Draeth:BAAALgADCgcJDQAAAA==.Dreadful:BAAALgAECgYJDgAAAA==.Dreylan:BAAALgADCgcJBwAAAA==.Dreyra:BAAALgADCgcJBwABLgAECgkJMAADAL8eAA==.Drosof:BAAALgADCgYJEAAAAA==.Drow:BAAALgADCgcJBwAAAA==.',
Du='Dukalioth:BAABLgAECn8iAAIVAAcJ0BCNHwBBAQAVAAcJ0BCNHwBBAQAAAA==.',
['Dê']='Dêcay:BAACLgAFFH8TAAMNAAUJaSJELABvAQANAAUJaSJELABvAQAOAAEJAABsPgAAAAAuAAQKfy8AAw0ACQlaIhMYAOsCAA0ACAn9IRMYAOsCAAEABwmJITIEAFACAAAA.',
['Dö']='Döctorfate:BAABLgAECn8VAAIWAAgJngjwIABhAQAWAAgJngjwIABhAQAAAA==.',
Ef='Effinsoldier:BAABLgAECn8YAAIJAAYJnhCSnAAcAQAJAAYJnhCSnAAcAQAAAA==.',
Eg='Egfuyun:BAAALgAECgQJBwAAAA==.',
Ek='Ekko:BAAALgADCgIJAgAAAA==.',
El='Ellyy:BAAALgADCgIJAgAAAA==.Elvira:BAAALgAECgQJBQAAAA==.',
En='Endlessagony:BAABLgAECn8lAAINAAkJqB4wIADBAgANAAkJqB4wIADBAgAAAA==.Endlessice:BAAALgAECgUJBQAAAA==.Ennyo:BAAALgAECgMJAwAAAA==.Enyo:BAABLgAECn8sAAQGAAcJvSA6JgAqAgAGAAcJvSA6JgAqAgAXAAEJAAA1JwBVAAAYAAIJeAZ9XgBTAAAAAA==.',
Er='Erathas:BAABLgAECn8ZAAIJAAkJsRHBYQC/AQAJAAkJsRHBYQC/AQAAAA==.',
Fa='Falandril:BAAALgAECgkJEAAAAA==.Fasriel:BAAALgAECgIJAgAAAA==.',
Fe='Feata:BAAALgAECgEJAQABLgAECgYJCwAKAAAAAA==.Felston:BAAALgADCgUJBQAAAA==.',
Fi='Fiyero:BAABLgAECn8rAAMEAAkJ8A4HIwC2AQAEAAkJ8A4HIwC2AQAFAAcJwgQqJQDEAAAAAA==.',
Fl='Flagcrazed:BAAALgADCgUJBQAAAA==.Fleabath:BAAALgAECgYJDgABLgAECggJIAACAKUKAA==.Fluffypyro:BAAALgADCgYJBgAAAA==.',
Fo='Forëplây:BAAALgAECgYJCgAAAA==.Foughum:BAAALgADCgUJBQABLgAECgYJCwAKAAAAAA==.',
Fr='Friedcheekin:BAAALgADCgUJBQAAAA==.',
Fu='Fury:BAAALgADCgEJAQAAAA==.',
Ga='Galdames:BAAALgADCgQJBAAAAA==.',
Ge='Gedien:BAAALgAECggJDwAAAA==.Gerftrazkal:BAAALgAECgUJBQAAAA==.',
Gi='Gilforty:BAABLgAECn8YAAIYAAcJ0RZDCQCGAQAYAAcJ0RZDCQCGAQAAAA==.',
Gl='Glep:BAAALgAECgIJAgABLgAECgkJJgAZAEUdAA==.Gloriosa:BAABLgAECn9AAAIaAAkJPBCoIwC7AQAaAAkJPBCoIwC7AQAAAA==.',
Go='Gorl:BAAALgAECgEJAQAAAA==.',
Gr='Grootforce:BAAALgADCgMJAwAAAA==.',
Gv='Gvendalyn:BAABLgAECn8nAAICAAgJYSZaCAD2AgACAAgJYSZaCAD2AgAAAA==.',
Gw='Gweyn:BAAALgADCgQJBQAAAA==.',
Gy='Gyatsò:BAABLgAECn8jAAIRAAkJAxhODwAtAgARAAkJAxhODwAtAgAAAA==.',
['Gø']='Gød:BAAALgADCgUJBQAAAA==.',
Ha='Harshdh:BAAALgAECgYJBgABLgAECgkJHgANABgUAA==.Harshdk:BAABLgAECn8eAAMNAAkJGBS3UACuAQANAAgJ6Ra3UACuAQAOAAQJoAFFRABPAAAAAA==.',
He='Helel:BAACLgAFFH8GAAINAAMJWBifZgD+AAANAAMJWBifZgD+AAAuAAQKfzwAAw0ACQl6IHwLAPMCAA0ACQl6IHwLAPMCAA4ABgnlEWsnAOoAAAAA.',
Ho='Hops:BAAALgAECgIJBQAAAA==.',
Il='Illibanger:BAAALgAECgcJBwABLgAFFAMJCgAEAPIUAA==.Illifiend:BAAALgAECgYJBgABLgAECgkJKwAEAPAOAA==.',
Im='Impetuous:BAAALgADCgYJDwABLgAECggJIAACAKUKAA==.',
Ip='Ipokeu:BAAALgADCgQJBAAAAA==.',
Ja='Jabmoney:BAAALgAFFAEJAgAAAA==.Jaffy:BAAALgADCgYJDgAAAA==.Jamninja:BAABLgAECn8pAAIUAAkJsxu2IwByAgAUAAkJsxu2IwByAgAAAA==.Jardalanin:BAAALgADCgEJAQAAAA==.Jaroshe:BAAALgADCgUJBQAAAA==.',
Je='Jellyfish:BAABLgAECn8eAAMLAAkJqxJwFwDsAQALAAkJYQ5wFwDsAQAbAAgJRgw7JgBwAQAAAA==.Jessamyn:BAAALgAECgYJCwAAAA==.',
Jh='Jhoira:BAAALgAECgYJDwAAAA==.',
Jo='Jokko:BAAALgADCgEJAgAAAA==.Jordyy:BAABLgAECn8oAAQXAAkJTiKeBQD6AQAGAAgJfSCeIQCQAgAXAAYJpiSeBQD6AQAYAAIJERNKVABxAAAAAA==.',
Ka='Kaifren:BAACLgAFFH8LAAIUAAQJbxCqSAA2AQAUAAQJbxCqSAA2AQAuAAQKfx0AAhQACQmvFM1DAPQBABQACQmvFM1DAPQBAAAA.Kalifa:BAACLgAFFH8cAAIHAAcJCxxVAwAsAgAHAAcJCxxVAwAsAgAuAAQKfzQAAwcACAn1I7cIAAoDAAcACAn1I7cIAAoDABwAAgmIFUhOAD0AAAAA.Kalinethe:BAAALgAECgEJAgAAAA==.Karatay:BAAALgADCgQJBQAAAA==.Karrod:BAAALgAECggJEQAAAA==.Katyce:BAAALgADCgcJDQAAAA==.',
Ke='Keilani:BAAALgAECgQJBQAAAA==.',
Ki='Killeerrkap:BAAALgAECgQJBgAAAA==.Killrmiller:BAAALgADCgMJAwAAAA==.Kirajdh:BAABLgAECn8mAAIZAAkJRR07EwCLAgAZAAkJRR07EwCLAgAAAA==.Kittenmitten:BAAALgADCgQJBAAAAA==.Kiwaj:BAAALgAECgUJBQABLgAECgkJJgAZAEUdAA==.',
Ko='Komayetu:BAAALgAECgQJBgAAAA==.',
Kr='Kraas:BAAALgAECgEJAQAAAA==.Krateis:BAABLgAECn8fAAIdAAcJ+QR/EQDpAAAdAAcJ+QR/EQDpAAAAAA==.Kraéthlas:BAAALgADCgYJCgAAAA==.',
Kw='Kwonhee:BAAALgADCgMJAwAAAA==.',
La='Lanadelrey:BAAALgAECgYJAQAAAA==.Laurenth:BAAALgADCgkJFQAAAA==.Lazyace:BAAALgAECgYJCQAAAA==.',
Le='Lebenspender:BAABLgAECn8qAAMPAAgJ1R8EHgAwAgAPAAYJWiIEHgAwAgAIAAgJ6A4LLQBjAQAAAA==.Lextalonis:BAAALgAECgYJCAABLgAECgcJDgAKAAAAAA==.',
Li='Linkstery:BAABLgAECn8sAAMGAAgJ9RpQUwDNAQAGAAcJJRlQUwDNAQAYAAMJfRWwNADkAAAAAA==.',
Lo='Losvanknight:BAAALgAECgcJDAAAAA==.',
Lt='Lt:BAAALgADCgEJAQAAAA==.',
Ly='Lyathon:BAAALgADCgMJAwAAAA==.',
Ma='Macfluffy:BAAALgAECgUJBgAAAA==.Mactacolover:BAAALgAECgMJAwAAAA==.Madbomber:BAAALgAECgcJDwAAAA==.Maeze:BAABLgAECn8gAAICAAgJpQocWQBrAQACAAgJpQocWQBrAQAAAA==.Magepawk:BAAALgAECgMJAwAAAA==.Magew:BAAALgADCgQJBAAAAA==.Malandru:BAACLgAFFH8HAAIeAAQJwhScGQAhAQAeAAQJwhScGQAhAQAuAAQKfysAAwkACQnlIicQAMwCAAkACAn0JCcQAMwCAB4ACQlUDGQ6AJABAAAA.Mawwowow:BAABLgAECn8qAAIZAAgJtxgNLgDvAQAZAAgJtxgNLgDvAQAAAA==.Maximillius:BAAALgAECgUJBgABLgAECggJJAANAHgbAA==.Mayjoraid:BAAALgAECgEJAgAAAA==.',
Me='Meekah:BAACLgAFFH8LAAILAAQJ6xDEGwArAQALAAQJ6xDEGwArAQAuAAQKf0gAAgsACQn2HuIEAB4DAAsACQn2HuIEAB4DAAAA.Melbrosha:BAAALgAECgUJDAAAAA==.Melodine:BAAALgADCgEJAQAAAA==.Melyndia:BAAALgAECgUJBQABLgAECggJIQAfAP4fAA==.Meriks:BAAALgAECgQJDAABLgAECgUJDQAKAAAAAA==.',
Mi='Mickmonkey:BAAALgAECgcJBwABLgAECgMJAwAKAAAAAA==.Mickspooky:BAACLgAFFH8XAAMNAAUJlhVJTAAxAQANAAQJlhVJTAAxAQAOAAEJAABbPgAAAAAuAAQKfywAAw0ACAmZH0opAJUCAA0ACAmZH0opAJUCAA4AAwkwFyMuALwAAAEuAAQKAwkDAAoAAAAA.Mickstormy:BAAALgAECgMJAwAAAA==.Mierin:BAAALgAECgQJBwAAAA==.Milfy:BAAALgADCgQJBAABLgAECgEJAQAKAAAAAA==.Mintie:BAABLgAECn8sAAIcAAgJxxWnEQCWAQAcAAgJxxWnEQCWAQAAAA==.',
Mo='Moozylla:BAAALgAECggJCQAAAA==.Morrïgan:BAAALgAECgQJCgAAAA==.Mossiah:BAAALgAECgEJAQAAAA==.',
Mu='Muriggy:BAAALgADCgIJAgAAAA==.',
My='Mylarna:BAABLgAECn8cAAIIAAgJwQljOwAXAQAIAAgJwQljOwAXAQAAAA==.Mynx:BAABLgAECn8WAAIgAAgJPx9RAwB4AgAgAAgJPx9RAwB4AgAAAA==.',
['Må']='Mårsh:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîstweaver:BAAALgAECgIJAgAAAA==.',
Na='Nadira:BAAALgADCgYJBgABLgADCgcJBwAKAAAAAA==.Nahkti:BAAALgADCgcJBwAAAA==.Nazarick:BAAALgAECgYJCAAAAA==.',
Ne='Neona:BAAALgAECgQJBAAAAA==.Neriv:BAABLgAECn8VAAIYAAcJ8A0EEAAWAQAYAAcJ8A0EEAAWAQAAAA==.Nexaladin:BAAALgAECgEJAQAAAA==.',
Ni='Nicor:BAAALgADCgQJBAAAAA==.Nimbus:BAAALgAECgMJBAABLgAFFAgJFgASAEwWAA==.Nixii:BAABLgAECn8sAAIHAAgJ/RBgJAB5AQAHAAgJ/RBgJAB5AQAAAA==.',
No='Nocticula:BAABLgAECn86AAIbAAkJXAnqJgBrAQAbAAkJXAnqJgBrAQAAAA==.',
Ny='Nyet:BAACLgAFFH8YAAMEAAUJ+hMhDgAkAQAEAAUJ+hMhDgAkAQAFAAEJYganLgA+AAAuAAQKfxwAAgQACQm/G1wcAGoCAAQACQm/G1wcAGoCAAAA.Nythraxia:BAAALgAECgMJAwAAAA==.Nyxiria:BAAALgADCgcJGgAAAA==.',
['Nò']='Nòir:BAAALgAECgcJCAAAAA==.',
Oh='Ohnarr:BAAALgAECgMJAwAAAA==.',
Ok='Oktoberfist:BAAALgAECgcJBwABLgAECggJAwAKAAAAAA==.',
Or='Orine:BAAALgAECggJEwAAAA==.Orioz:BAACLgAFFH8TAAIMAAUJ6R47BABPAQAMAAUJ6R47BABPAQAuAAQKfyQAAgwACAk0IvEDAOgCAAwACAk0IvEDAOgCAAAA.',
Os='Osiras:BAAALgAECgcJDgAAAA==.',
Ot='Othela:BAAALgADCgEJAQAAAA==.',
Ow='Owun:BAAALgADCgEJAQAAAA==.',
Oz='Oz:BAAALgADCgkJCgAAAA==.',
Pa='Pandapal:BAAALgAECgEJAgAAAA==.Pathbrin:BAAALgADCgEJAQAAAA==.Pauliee:BAAALgAECgMJAwAAAA==.Pawkah:BAAALgAECgEJAgAAAA==.Paytowintaxi:BAAALgADCgEJAQAAAA==.',
Pe='Peyton:BAAALgADCggJEQAAAA==.',
Pr='Protection:BAAALgADCgUJBgAAAA==.',
Ps='Psychoman:BAAALgADCgMJAwABLgAFFAUJDwAHANAbAA==.Psychomurda:BAABLgAECn8dAAMJAAYJpAtDsgD6AAAJAAYJpAtDsgD6AAAhAAMJ/gciNABkAAABLgAFFAQJCwALAOsQAA==.',
Pu='Puthealshere:BAAALgAFFAEJAQAAAA==.',
['Pü']='Pü:BAAALgADCgcJBwAAAA==.',
Ra='Raign:BAAALgAECgEJAgAAAA==.Randomfelfox:BAAALgADCgYJBgAAAA==.Ratpack:BAAALgAECggJAwAAAA==.',
Re='Renfri:BAAALgADCgYJDgAAAA==.',
Ro='Robel:BAAALgAECgUJBgAAAA==.Ronaldbruce:BAAALgAECgQJBQAAAA==.Roupert:BAAALgAECgEJAwAAAA==.Rovox:BAAALgAECgEJAQABLgAECgkJJgAZAEUdAA==.',
Sa='Sadness:BAAALgAECgYJBAAAAA==.Sao:BAAALgAECgIJAgAAAA==.Sardrian:BAABLgAECn8WAAICAAcJEAZyhwD+AAACAAcJEAZyhwD+AAAAAA==.',
Se='Seimie:BAABLgAECn8nAAIYAAkJeQv+CgBjAQAYAAkJeQv+CgBjAQAAAA==.Selithvia:BAABLgAECn8WAAIiAAcJnBKyJwBnAQAiAAcJnBKyJwBnAQAAAA==.Senethotsare:BAAALgAECgYJCQAAAA==.Sethen:BAAALgADCgEJAQAAAA==.',
Sh='Shaboudi:BAAALgADCgEJAQABLgAECgQJBQAKAAAAAA==.Shamalicious:BAAALgADCgEJAQAAAA==.Shammwow:BAAALgAECgMJBQAAAA==.Shaofikx:BAABLgAECn8wAAIjAAkJCAwqIgB5AQAjAAkJCAwqIgB5AQAAAA==.Shenknarok:BAABLgAECn8rAAIkAAYJ1xu7EAB1AQAkAAYJ1xu7EAB1AQAAAA==.Sherryl:BAABLgAECn8wAAIfAAgJ7Q4fPACBAQAfAAgJ7Q4fPACBAQAAAA==.Shmooples:BAAALgAECgEJAQAAAA==.Shunei:BAAALgADCgQJBAAAAA==.',
Si='Siema:BAAALgAECgMJAwAAAA==.Sigurd:BAAALgADCggJBwAAAA==.',
Sk='Skdragon:BAAALgADCgMJAQAAAA==.Skyari:BAABLgAECn8cAAIEAAcJPSSeEwAxAgAEAAcJPSSeEwAxAgAAAA==.Skyarii:BAAALgAECgUJCAABLgAECgcJHAAEAD0kAA==.',
So='Songweaver:BAAALgAECgEJAgAAAA==.Soulminion:BAABLgAECn8eAAINAAYJuAJw5wCWAAANAAYJuAJw5wCWAAAAAA==.',
Sp='Spiritshard:BAAALgADCgcJEgAAAA==.Splashmountn:BAEALgAECgYJEAAAAA==.',
St='Sthane:BAAALgADCgEJAQAAAA==.Sthise:BAAALgAECgMJAwAAAA==.',
Su='Subtlety:BAABLgAECn8aAAIWAAkJ+yI3AwD9AgAWAAkJ+yI3AwD9AgAAAA==.Sulfurya:BAAALgAECgYJCQAAAA==.',
Sy='Sykoman:BAACLgAFFH8PAAMHAAUJ0BtTFAA/AQAHAAUJ0BtTFAA/AQAfAAEJ5QAtYwAvAAAuAAQKfygAAgcACAlwI30LAN8CAAcACAlwI30LAN8CAAAA.',
['Sì']='Sìleñtclãw:BAAALgAECgcJDgAAAA==.',
Ta='Talarina:BAAALgADCgYJBgAAAA==.Taylen:BAAALgADCgcJBwAAAA==.',
Te='Terumi:BAAALgAECgQJBQAAAA==.Teverion:BAAALgADCgcJCwAAAA==.',
Th='Thesios:BAAALgADCgkJDQAAAA==.Thickthighs:BAAALgAECgEJAQAAAA==.Thiizz:BAAALgAECgYJCwAAAA==.Thizz:BAABLgAECn8fAAIEAAYJPiD/KQASAgAEAAYJPiD/KQASAgABLgAFFAEJAgAKAAAAAA==.',
Ti='Tic:BAAALgAFFAIJAgAAAA==.Tinksy:BAAALgADCgEJAQABLgAECgEJAQAKAAAAAA==.Tionder:BAAALgADCgEJAQAAAA==.',
To='Toeto:BAAALgADCgYJBgAAAA==.Toetoeto:BAAALgAECgMJAwAAAA==.Toetoetoete:BAAALgADCgYJBgAAAA==.Tooe:BAAALgAECgMJAwAAAA==.Torquei:BAAALgAECgYJBwAAAA==.Toxious:BAAALgAECgQJBAAAAA==.',
Tp='Tpaman:BAAALgAECgYJBgAAAA==.Tpdruid:BAAALgAECgMJAwAAAA==.',
Ts='Tsjuda:BAAALgADCgEJAQAAAA==.Tsjudii:BAAALgADCgYJBgAAAA==.Tsjudilla:BAAALgADCgEJAQAAAA==.',
Tu='Tujefe:BAAALgAECgcJCwAAAA==.',
Ug='Ugzlug:BAAALgADCgEJAQAAAA==.',
Un='Unholydk:BAAALgAFFAMJAgABLgAFFAQJBQAfAPUQAA==.',
Va='Vacuus:BAABLgAECn8mAAIXAAkJSwrTCAClAQAXAAkJSwrTCAClAQAAAA==.Vahldire:BAAALgAECgUJDAAAAA==.Valeri:BAAALgADCggJCwAAAA==.Varkon:BAAALgAECgYJBgAAAA==.Varn:BAAALgADCggJCAAAAA==.Varthion:BAAALgAECgYJBgAAAA==.',
Ve='Velastrasza:BAAALgADCgcJBwAAAA==.Velkethria:BAAALgAECgYJEwAAAA==.Velnyxia:BAAALgAECgQJBQAAAA==.Velovañ:BAAALgADCgEJAQAAAA==.Velthyria:BAAALgADCgkJCQAAAA==.Vestara:BAAALgAECggJCAAAAA==.Veylara:BAABLgAECn8oAAIGAAcJ7gbojwAGAQAGAAcJ7gbojwAGAQAAAA==.',
Vi='Viryda:BAAALgAECgQJBAABLgAECggJLgAcAKMJAA==.',
Wa='Wartimebeast:BAAALgAECgUJEAAAAA==.',
We='Welp:BAAALgAECgEJAgAAAA==.',
Wh='Wherebear:BAAALgAECgEJAQAAAA==.',
Wi='Windwalker:BAAALgAECgcJCAAAAA==.Wisteria:BAABLgAECn80AAMYAAgJiRZiCwALAgAYAAgJiRZiCwALAgAXAAEJwwEzOAAaAAABLgAECgEJAQAKAAAAAA==.',
Wo='Wompalot:BAAALgADCgQJBAAAAA==.Womplock:BAAALgAECgQJBgAAAA==.',
Wr='Wrâth:BAACLgAFFH8HAAIUAAMJOAWZcgDKAAAUAAMJOAWZcgDKAAAuAAQKfy8AAhQACQkVE+NCAPcBABQACQkVE+NCAPcBAAAA.',
Wy='Wydwen:BAAALgAECgEJAQAAAA==.',
Xe='Xenro:BAAALgADCgcJBgAAAA==.',
Xi='Xirus:BAAALgADCgQJAQAAAA==.',
Xu='Xulfred:BAAALgADCgIJAgAAAA==.',
Ya='Yavana:BAAALgADCgEJAQAAAA==.',
Zi='Zigzogg:BAAALgADCgEJAQAAAA==.Zilida:BAAALgADCgEJAQAAAA==.Ziwee:BAABLgAECn8aAAIjAAgJvBqBFQBeAgAjAAgJvBqBFQBeAgABLgAECggJGgAjALwaAA==.',
Zo='Zorana:BAAALgADCgEJAQAAAA==.',
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
