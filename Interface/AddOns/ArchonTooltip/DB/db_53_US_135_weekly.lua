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

local lookup = {'Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Priest-Holy','Priest-Shadow','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Druid-Feral','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Paladin-Protection','Monk-Brewmaster','Warlock-Affliction','DemonHunter-Havoc','Paladin-Holy','Mage-Fire','DeathKnight-Blood','Warrior-Protection','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Hunter-Marksmanship','Priest-Discipline','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Achkmed:BAAANQADCggIEgAAAA==.',
Ad='Adelaid:BAAANQAECgEIAQABNQAFFAcIFQABAJoPAA==.',
Ae='Aethelle:BAAANQAECgEIAQAAAA==.',
Ak='Akalon:BAABNQAECn9aAAICAAoKMxAyNwC/AQACAAoKMxAyNwC/AQAAAA==.',
Al='Aleckzander:BAAANQAECgMIBAABNQAECgkJLwADADMlAA==.Alexandrìte:BAAANQADCgcIEQAAAA==.Allfrost:BAAANQAECgUIDAAAAA==.Altscale:BAAANQAECgcIDQAAAA==.Aluda:BAABNQAECn8oAAMEAAgKrhWLTQDJAQAEAAcKaBWLTQDJAQAFAAYKTw8bQAAuAQAAAA==.',
Am='Amberina:BAAANQADCggICQAAAA==.',
An='Anùbis:BAAANQADCgIIAgAAAA==.',
Ao='Aoeina:BAABNQAECn84AAMGAAoKFBuXfwB/AgAGAAoKvxiXfwB/AgAHAAIKiBv2IQCZAAAAAA==.',
Ap='Apollo:BAABNQAECn8zAAIIAAoK8CVFDgAEAwAIAAoK8CVFDgAEAwAAAA==.',
Ar='Arcanelotus:BAAANQADCgIIAwAAAA==.Arctus:BAAANQADCgcIBwAAAA==.Ariaves:BAABNQAECn8XAAIFAAkKbBCvIwAVAgAFAAkKbBCvIwAVAgAAAA==.Arlind:BAAANQAECggIEwAAAA==.Artemix:BAAANQAECgQIBAAAAA==.Arthara:BAAANQADCgEIAQAAAA==.',
As='Askeral:BAAANQAECgEIAQAAAA==.Astelana:BAABNQAECn8nAAIBAAgK5wf6ywAAAQABAAgK5wf6ywAAAQAAAA==.',
At='Atanatari:BAAANQAECgUIBQABNQAECgkJHwAFACgFAA==.Athennah:BAAANQADCgUIBQAAAA==.',
Ba='Bannar:BAAANQAECgcIBwAAAA==.Bassotan:BAABNQAECn8YAAIBAAkKawqb1AByAQABAAkKawqb1AByAQAAAA==.Baticus:BAAANQADCgcIBwAAAA==.',
Be='Beleva:BAAANQAECgIIBQAAAA==.Belias:BAAANQAECggIDQAAAA==.Bezzaj:BAAANQAFFAIIAgABNQAFFAcIGwAGABgSAA==.',
Bj='Bjornagain:BAAANQAECgUICgAAAA==.Björne:BAAANQADCggIFQAAAA==.',
Bl='Blackendmoon:BAABNQAECn8rAAMJAAkKmwYhUwAMAQAJAAkKBwYhUwAMAQAKAAIKdQioygBXAAAAAA==.Blacklotus:BAAANQAECggIEQAAAA==.Bloodedge:BAAANQAECgYIDwAAAA==.Bloodklaat:BAAANQAECgYICgAAAA==.Bloodnight:BAABNQAECn8cAAIBAAkKKhHnsQC7AQABAAkKKhHnsQC7AQAAAA==.Bluebubbles:BAAANQADCggIJAAAAA==.Bluéyes:BAAANQAECgYIDQAAAA==.Blvckscvl:BAABNQAECn8rAAIIAAoKqBxgKQDzAgAIAAoKqBxgKQDzAgAAAA==.Blynna:BAAANQADCgYICgAAAA==.',
Br='Brannik:BAABNQAECn8WAAMLAAcKoQw2LgDFAAALAAcKoQw2LgDFAAAMAAEKmQOQwwApAAAAAA==.Breña:BAAANQADCggIGQAAAA==.Broadleaf:BAAANQAECgQICAAAAA==.',
Ca='Camiliana:BAAANQADCgUIBQAAAA==.',
Ce='Cellulight:BAABNQAECn8uAAMNAAoKbhi4DQCKAgANAAoKbhi4DQCKAgAOAAEKsAmdQQAnAAAAAA==.',
Ch='Charizard:BAAANQAECgcIGAAAAQ==.Chelais:BAAANQAECggICQABNQABCgIIAgAPAAAAAA==.Cherrycola:BAAANQAECgQICQAAAA==.Chobits:BAAANQAECgQIBAAAAA==.',
Co='Coppertopp:BAAANQADCgQJBQAAAA==.Corvany:BAAANQAECgUICwAAAA==.',
Cr='Crawley:BAABNQAECn95AAILAAoKzR7bBAC1AgALAAoKzR7bBAC1AgAAAA==.Crazalulla:BAAANQADCggIGAAAAA==.Creeder:BAABNQAECn8fAAIBAAkK1gwNqwDJAQABAAkK1gwNqwDJAQAAAA==.Crixus:BAABNQAECn8fAAMQAAoKbA0zBQBxAQAQAAkK2AwzBQBxAQARAAUKCwWv/QDQAAAAAA==.',
Da='Dagoland:BAAANQADCggIBQAAAA==.Daij:BAAANQADCgUIBQAAAA==.Dainty:BAAANQAECgIIAQABNQAFFAcIEgAIAG0WAA==.',
De='Deaanor:BAAANQAECgMIBAAAAA==.Deathcòw:BAAANQAECgYICwAAAA==.Deween:BAABNQAECn8WAAMBAAgKHhOJ9gAwAQABAAgKHhOJ9gAwAQASAAEKAADBbAAAAAAAAA==.Dewexa:BAAANQADCgEIAQAAAA==.',
Di='Diamond:BAAANQAECgIIAgAAAA==.Dionysuz:BAAANQAECggIEAAAAA==.Disdekay:BAAANQAECgMIAgABNQAECggIDQAPAAAAAA==.',
Do='Dojoro:BAABNQAECn8nAAITAAkKLRHGCQB3AQATAAkKLRHGCQB3AQAAAA==.Dorc:BAAANQADCgMIAwAAAA==.Dotsarelocks:BAABNQAECn8eAAQUAAkK0hOcCQBqAQAUAAgK+xKcCQBqAQAQAAEKAADTZwBSAAARAAMKoxK87QBNAAAAAA==.',
Dr='Dradyos:BAAANQAECgYIDwAAAA==.Draegare:BAAANQAFFAEIAQAAAA==.Drdeer:BAAANQADCgUIBgAAAA==.Drewarel:BAAANQAECgQIBAABNQAECggIEgAPAAAAAA==.Drittsz:BAAANQADCgYICAAAAA==.',
Ee='Eelecurb:BAAANQADCggIDwAAAA==.',
Ei='Eisysae:BAAANQADCgEIAQAAAA==.',
El='Eliard:BAAANQADCgEIAQAAAA==.Ellå:BAAANQAECgUICAABNQAECgoKQgAEAJ0iAA==.',
Er='Erisynn:BAEANQADCgUIBQABNQAFFAUIDQAVAMYEAA==.',
Et='Eternalx:BAAANQAECgEIAQAAAA==.',
Ev='Evang:BAABNQAECn8lAAIIAAgKZwuWigBZAQAIAAgKZwuWigBZAQAAAA==.Everd:BAABNQAECn8qAAIBAAcKhgqO4QBYAQABAAcKhgqO4QBYAQAAAA==.',
Fi='Fiametta:BAABNQAECn80AAIQAAoK2BeEAwDFAQAQAAoK2BeEAwDFAQAAAA==.Firerain:BAAANQADCggIFAAAAA==.',
Fl='Flameward:BAAANQAECgUIBQAAAA==.Flippi:BAAANQABCgYICgAAAA==.',
Fo='Forkingidiot:BAAANQAECgQIBAAAAA==.Forodin:BAAANQADCgYIBgABNQADCggIFQAPAAAAAA==.Foxymizzy:BAAANQAECgQIBAABNQAECgoKJQAWAP0dAA==.',
Fr='Fraybeilan:BAAANQADCgEIAQAAAA==.Freadrick:BAAANQADCgEIAQABNQADCggIFQAPAAAAAA==.Frostknight:BAAANQAECgYICAAAAA==.',
Fu='Funsize:BAABNQAECn9CAAIEAAoKnSLBDABWAwAEAAoKnSLBDABWAwAAAA==.',
Ga='Gardek:BAAANQAECggIAQAAAA==.Gazzlok:BAAANQAECgQIBQAAAA==.',
Ge='Gesen:BAAANQADCggIFQAAAA==.',
Gl='Global:BAAANQABCgcICgABNQAECgkJIQAXAOgYAA==.Gloriance:BAABNQAECn8lAAIRAAgKJhfFWQCNAQARAAgKJhfFWQCNAQAAAA==.',
Go='Gondra:BAAANQADCgEIAQABNQAECgUICwAPAAAAAA==.Gortalon:BAAANQADCgEIAQAAAA==.',
Ha='Haplo:BAAANQAECgUICwAAAA==.',
He='Hellmet:BAAANQAECgIIAgABNQAECgQIBQAPAAAAAQ==.Hey:BAACNQAFFH8IAAMCAAMKvgLPHgC/AAACAAMKvgLPHgC/AAADAAIKGRl1IwBRAAA1AAQKfygAAwMACgr4IMsfAOsCAAMACQpLIMsfAOsCAAIACApXCTt+ANsAAAAA.',
Hi='Hinamori:BAAANQAECggIDAAAAA==.',
Ho='Holythot:BAAANQAECgIIAwABNQAFFAYIIQAYACwfAA==.',
Hu='Huogmi:BAAANQAECgQIBQAAAA==.',
Il='Ilharra:BAAANQAECgUIEQAAAA==.Ilililili:BAAANQAECgUIDAAAAA==.Illee:BAABNQAECn8pAAIGAAoK5xAATgD+AQAGAAoK5xAATgD+AQAAAA==.',
Im='Impgangpimp:BAEBNQAECn81AAIRAAoKLR6vHQB6AgARAAoKLR6vHQB6AgAAAA==.Imturtle:BAABNQAECn9FAAIYAAoKiCJoBwACAwAYAAoKiCJoBwACAwABNQAFFAQICQARAJITAA==.',
Ir='Irmis:BAABNQAECn8rAAMZAAoKyx60BACpAgAZAAoK+x20BACpAgAaAAoKeRgXBgAuAgAAAA==.',
It='Ithrynluin:BAAANQAECgUIBwABNQAECgkJHwAFACgFAA==.',
Iu='Iupiter:BAAANQAECggICwAAAA==.',
Iy='Iyahlieairia:BAAANQAECgMIBAAAAA==.',
Iz='Izabeth:BAABNQAECn8iAAMHAAgKFA0QEgCFAQAHAAgKFA0QEgCFAQAGAAEKQgLW1QErAAAAAA==.',
Ja='Jamella:BAABNQAECn8xAAMBAAkKVhOHmQDwAQABAAcKQxiHmQDwAQAWAAkKmw1UXQBwAQAAAA==.',
Je='Jesüschrist:BAAANQAECgIIAwAAAA==.',
Ji='Jiglestd:BAAANQAECgQIBgAAAA==.',
Ju='Judeath:BAAANQADCgEIAQABNQADCggIGQAPAAAAAA==.',
Ka='Kabocha:BAAANQAECgcIDgAAAA==.Kars:BAAANQADCgEIAQAAAA==.Katsa:BAAANQAECgEIAQAAAA==.Kawi:BAAANQADCgEIAQAAAA==.Kayeh:BAAANQADCgIIAgAAAA==.',
Ki='Kiraneem:BAABNQAECn8pAAIIAAgK5hziYQBSAgAIAAgK5hziYQBSAgAAAA==.Kittie:BAABNQAECn8+AAIDAAoKzRWqRgBHAgADAAoKzRWqRgBHAgAAAA==.Kittynip:BAAANQADCgQIBQABNQAECgUIBQAPAAAAAA==.',
Ko='Koroar:BAAANQADCgEIAQAAAA==.',
Kr='Krinj:BAABNQAECn8fAAMJAAkKXh2FHwCPAgAJAAkKXh2FHwCPAgAKAAEKOQsF4AA0AAAAAA==.Kristov:BAAANQAECgcIBwAAAA==.',
Kt='Ktariani:BAAANQADCgYICgAAAA==.',
Ky='Kyden:BAAANQADCgEIAQAAAA==.',
['Kï']='Kïa:BAABNQAECn8YAAIEAAYKuwozqgAXAQAEAAYKuwozqgAXAQAAAA==.',
La='Lazulie:BAAANQADCgcICAAAAA==.',
Le='Leahim:BAABNQAECn+EAAIYAAoKFyT2BAAqAwAYAAoKFyT2BAAqAwAAAA==.Ledani:BAABNQAECn87AAMFAAoKgBEtEgAAAgAFAAoKgBEtEgAAAgAEAAYKGRxpbQDWAQAAAA==.Leonato:BAAANQADCgEIAQAAAA==.',
Li='Light:BAAANQADCggICAAAAA==.Lilbulky:BAAANQAECgcICQABNQAECggIIgAbAM8dAA==.Liriels:BAAANQAECgQIBQABNQAECgUICwAPAAAAAA==.',
Lo='Lohith:BAABNQAECn8fAAIDAAkKDQVtjwBiAQADAAkKDQVtjwBiAQAAAA==.Lonedawg:BAAANQAECgUIEAAAAA==.Lourival:BAAANQAECgQJBAAAAA==.Lovécoil:BAABNQAECn8eAAIKAAoKqRwjDwBjAgAKAAoKqRwjDwBjAgAAAA==.',
Lu='Lunâ:BAAANQAECgYIEgAAAA==.',
['Lë']='Lëw:BAAANQAECgYICAAAAA==.',
Ma='Mageofthe:BAAANQADCgUICAAAAA==.Maggnolya:BAAANQAECggIEAAAAA==.Marsyx:BAABNQAECn8fAAIEAAkKvRvSKgC+AgAEAAkKvRvSKgC+AgAAAA==.Mastian:BAAANQADCgEIAQAAAA==.Matidan:BAABNQAECn8YAAIcAAgK0BQCKAAEAgAcAAgK0BQCKAAEAgAAAA==.Mayael:BAABNQAECn8lAAMKAAkKrRomLQB/AgAKAAkKrRomLQB/AgAJAAcKuA8dUABzAQAAAA==.',
Me='Medreaux:BAABNQAECn+GAAMEAAoK0iJmBgCTAwAEAAoK0iJmBgCTAwAFAAEKdgADmQACAAAAAA==.Merrei:BAABNQAECn8qAAMVAAgKih5gHgDfAQAVAAgKih5gHgDfAQAdAAYKHwlvGAAqAQAAAA==.Meta:BAAANQADCggICAABNQAECgkJHwAYABcVAA==.Metalknyte:BAABNQAECn8qAAMYAAgK7xCxOgAuAQAYAAgK7xCxOgAuAQAKAAEKAACDmAAAAAAAAA==.',
Mi='Miniknyte:BAABNQAECn82AAMeAAoKcxz9CAAKAwAeAAoKcxz9CAAKAwAfAAEKAABVyQAZAAAAAA==.',
Mo='Mohu:BAAANQADCgcIBwAAAA==.Monkey:BAAANQADCgcICgAAAA==.Moonsz:BAAANQADCggIOgAAAA==.Mooseonloose:BAABNQAECn8YAAQKAAoKmRKfNQBRAgAKAAkK9xSfNQBRAgAJAAYKYQrVaQC6AAAYAAEKAACQxwA5AAAAAA==.Morandus:BAAANQAECgEIAQAAAA==.Moraria:BAAANQADCgMIAwAAAA==.Morgrathh:BAAANQADCgYIBwAAAA==.',
My='Mychelle:BAABNQAECn8uAAIgAAoKAwzoFQCtAQAgAAoKAwzoFQCtAQAAAA==.',
['Më']='Më:BAAANQAFFAIIAgABNQAECgkJGgAFAIwVAA==.',
Na='Nakryn:BAABNQAECn8eAAMHAAkKTANGJADLAAAGAAkKNQOa0ADdAAAHAAYKLwJGJADLAAAAAA==.Naryeth:BAAANQAECggIAQAAAA==.Natorn:BAABNQAECn8fAAIbAAkKeCHeJAAlAwAbAAkKeCHeJAAlAwAAAA==.Nay:BAAANQAECgcJCQAAAA==.',
Ne='Nemrod:BAAANQAECgEIAQAAAA==.Nezum:BAAANQAECgEIAQAAAA==.',
Ni='Nickoli:BAAANQAECgEIAQAAAA==.Niterend:BAABNQAECn8iAAMbAAgKzx25fgAeAgAbAAgKzx25fgAeAgAZAAEKjiG5LgBiAAAAAA==.',
No='Nojomoto:BAAANQADCgcIBwAAAA==.Norabel:BAAANQADCgQICAAAAA==.',
Nu='Nugehuts:BAABNQAFFH8QAAIYAAUK3yBdCgAbAQAYAAUK3yBdCgAbAQABNQAFFAkJNgARAOgmAA==.',
['Nø']='Nøxxi:BAABNQAECn8vAAMQAAoKphdqCgBQAgAQAAgKtBtqCgBQAgARAAoKtQqsUQCmAQAAAA==.',
Ob='Obbimcanood:BAAANQADCgIIAgAAAA==.',
Ok='Okbloomer:BAAANQAECggIEAABNQAFFAcIEQAEALMXAA==.',
Ol='Oldben:BAABNQAECn83AAMBAAoKqA8YcACwAQABAAoKqA8YcACwAQASAAMK5gDHawA7AAAAAA==.',
On='Onahwe:BAAANQADCgEIAQAAAA==.',
Or='Oriel:BAABNQAECn8pAAIhAAgKbgiYBgBAAQAhAAgKbgiYBgBAAQAAAA==.',
Ov='Ovy:BAAANQAECgEIAQAAAA==.',
Pa='Paleblueeye:BAAANQADCgIIAgAAAA==.Panda:BAAANQAECgMIAwAAAA==.Panqueke:BAAANQADCgEIAQAAAA==.',
Pi='Pixystix:BAAANQADCgYIDAABNQAECgoKLgAgAAMMAA==.',
Pl='Plop:BAAANQAECgQIBAABNQAECgkJIQAXAOgYAA==.Plumpcheeks:BAAANQAECgEIAQAAAA==.',
Po='Poc:BAABNQAECn8hAAMOAAgKBAvlGQD1AAAOAAgK8QnlGQD1AAANAAEKfQ11XgA2AAAAAA==.Poundya:BAAANQADCgYICgAAAA==.',
Pr='Priblet:BAAANQAECgcIDAAAAA==.Prinsana:BAABNQAECn8pAAISAAgK0xE6JQC2AQASAAgK0xE6JQC2AQAAAA==.',
Pu='Purquis:BAABNQAECn8eAAIfAAkKKgsHMgBBAQAfAAkKKgsHMgBBAQAAAA==.',
Ra='Raeve:BAAANQADCgYIBwABNQADCgMIBAAPAAAAAA==.Ragnus:BAAANQADCgEIAgAAAA==.Raidkicker:BAAANQADCgEIAQABNQAECgkJHgAUANITAA==.',
Re='Reaperlord:BAABNQAECn8rAAMWAAgKsx6tKQBTAgAWAAgKsx6tKQBTAgABAAMKmgdhMwFsAAAAAA==.',
Ri='Rincewind:BAAANQADCgEIAQAAAA==.Rizzardofoz:BAAANQADCgMIAwAAAA==.',
Rl='Rllybuffnerd:BAAANQAECggICwAAAA==.',
Ro='Rodikus:BAABNQAECn89AAMEAAoKziDwGADiAgAEAAoKziDwGADiAgAFAAMKFw8eQQB4AAAAAA==.',
Sa='Saeryan:BAAANQADCggICAAAAA==.Saiaa:BAABNQAECn8hAAILAAgKXwVTWwBKAQALAAgKXwVTWwBKAQAAAA==.Sakeena:BAAANQAECgUIEAAAAA==.Samará:BAAANQADCgQICgAAAA==.Sarleigh:BAAANQADCgIIAgAAAA==.Sattia:BAAANQAECgYIDQAAAA==.',
Sc='Scytheana:BAAANQADCgEIAQAAAA==.',
Sh='Shabloink:BAAANQAECgEIAQAAAA==.Shadereaver:BAAANQAECggICwAAAA==.Shenanygins:BAAANQADCgMIAwAAAA==.Shendalla:BAAANQABCgQIBAAAAA==.Shinokishi:BAABNQAECn8iAAIYAAgK7Q7ZPgAbAQAYAAgK7Q7ZPgAbAQAAAA==.',
Si='Silentninjaa:BAABNQAECn84AAIaAAoKkRCzCgCjAQAaAAoKkRCzCgCjAQAAAA==.Simphunter:BAEBNQAECn8eAAIcAAoK+hTDIABGAgAcAAoK+hTDIABGAgABNQAECgoKNQARAC0eAA==.Sinfel:BAABNQAECn8uAAMVAAoKvgf0NQAzAQAVAAoKoQf0NQAzAQAdAAYKbQQJIQBcAAAAAA==.Sit:BAAANQADCggICAAAAA==.',
Sk='Skoriavis:BAAANQAECgEIAQABNQAECgcIHQAMADUZAA==.Skoriko:BAABNQAECn8dAAMMAAcKNRn6FgAoAgAMAAcKNRn6FgAoAgALAAMK2gwbhgCaAAAAAA==.',
Sl='Slürmp:BAAANQAECgEIAQABNQAECggIEQAPAAAAAA==.',
Sn='Snowcones:BAAANQADCgUIBQAAAA==.',
So='Sonett:BAAANQAECgUICQAAAA==.Sonto:BAAANQAECgQICwAAAA==.',
Sp='Sparks:BAAANQAECggICAAAAA==.Splunk:BAABNQAECn8fAAIYAAkKFxWyOAAkAgAYAAkKFxWyOAAkAgAAAA==.',
St='Staggerdaddy:BAAANQAECgQIBgAAAA==.Stariya:BAAANQAECgUIEAAAAA==.Stompinghoof:BAAANQAECgYICAAAAA==.Strapattack:BAAANQAECgYICAAAAA==.Strawyà:BAABNQAECn8oAAMiAAoKTA0gGAC5AQAiAAoKTA0gGAC5AQAjAAEKWAUXUQAnAAAAAA==.',
Sw='Swïft:BAAANQAECgMIAwABNQAECgQICwAPAAAAAA==.',
Sy='Syananta:BAAANQAECgUIBQABNQAECgUIBQAPAAAAAA==.Syannara:BAAANQAECgUIBQAAAA==.Syklar:BAAANQADCgEIAQAAAA==.Syssa:BAABNQAECn8hAAIEAAgKehz9MgA/AgAEAAgKehz9MgA/AgABNQAECgYIHgAEANwTAA==.',
['Sì']='Sìrocco:BAAANQAECgYIDAAAAA==.',
Ta='Taleranor:BAAANQAECgcIDgAAAA==.Tamerizer:BAABNQAECn8kAAIgAAkK3w8AMADNAQAgAAkK3w8AMADNAQAAAA==.',
Te='Tealera:BAAANQAECgQIBAAAAA==.Tearali:BAAANQADCggICAAAAA==.Teejrath:BAABNQAECn8bAAQKAAkKVA/EWwChAQAKAAgKFhDEWwChAQAJAAEKzgqktAArAAAYAAEKAAB24AAeAAAAAA==.Teekeez:BAAANQADCggICgAAAA==.',
Th='Thekal:BAAANQADCgEIAwAAAA==.Theodorel:BAAANQAECgEIAQAAAA==.Thicchick:BAAANQAECgYIDAAAAA==.Thirge:BAABNQAECn8iAAMaAAgKVguSFQBDAQAaAAcKbAySFQBDAQAbAAMKGAch0wCaAAAAAA==.Thorek:BAAANQADCggIEAAAAA==.Thrushbeard:BAAANQADCgcICAAAAA==.Thundertaco:BAABNQAECn8hAAICAAgKUwpZYwAhAQACAAgKUwpZYwAhAQAAAA==.',
Ti='Tighten:BAAANQADCgEIAQAAAA==.',
To='Toesniffer:BAAANQADCggICAAAAA==.Tofaaway:BAAANQAECgUIEAAAAA==.Tolak:BAAANQAECgYIEAAAAA==.Tormikinos:BAABNQAECn8lAAIfAAgKTAliPQADAQAfAAgKTAliPQADAQAAAA==.Torturousôwl:BAABNQAECn8YAAMEAAcK7xK0cwBDAQAEAAcK7xK0cwBDAQAhAAEK3AXeLwAlAAAAAA==.Totemknyte:BAAANQADCgEIAQABNQAECggIKgAYAO8QAA==.',
Tr='Trapology:BAAANQAECgIIAwAAAA==.Trillianh:BAAANQADCgEIAQAAAA==.Trisky:BAABNQAECn8nAAMWAAkKYBodNQCPAgAWAAkKYBodNQCPAgASAAEKMw+CdQAnAAAAAA==.',
Tu='Tumblebumble:BAAANQADCgMIAwAAAA==.Turtle:BAACNQAFFH8JAAIRAAQKkhPIEQDrAAARAAQKkhPIEQDrAAA1AAQKf1MAAxEACgrpIB0RAMsCABEACgqMHx0RAMsCABAAAwoFF+cTAKAAAAAA.',
Un='Unholyghost:BAAANQADCgEIAQAAAA==.',
Va='Vadrakquin:BAAANQAECggIDwAAAA==.Valshamommy:BAABNQAECn8kAAIkAAoKPhKVEwAvAgAkAAoKPhKVEwAvAgAAAA==.Vanisha:BAAANQADCgEIAQAAAA==.Vanloth:BAAANQADCgEIAwAAAA==.Vantadim:BAAANQAECgQIBAAAAA==.',
Ve='Vegito:BAAANQAECgIIBQAAAA==.Velayna:BAAANQADCgEIAQAAAA==.Velfurry:BAAANQAECgEIAQABNQAFFAgIJQAlAGMMAA==.Verlassan:BAAANQADCgcIBwAAAA==.',
Vi='Viverrid:BAAANQAECgEIAQAAAA==.',
Vo='Voinwar:BAACNQAFFH8JAAIZAAQKEhidAgDPAAAZAAQKEhidAgDPAAA1AAQKf0oAAhkACgpzJaABALIDABkACgpzJaABALIDAAAA.Vorpine:BAABNQAECn8tAAMEAAoKchUShACLAQAEAAgKfxQShACLAQAFAAoKvhAPHAB1AQAAAA==.',
We='Wetkittie:BAAANQADCgYIBwAAAA==.',
Wh='Whybebabo:BAAANQAECgMIAwAAAA==.',
Wi='Wiccawitch:BAAANQADCgYIEwAAAA==.Wildnymphy:BAAANQADCgEIAQAAAA==.Wirhl:BAABNQAECn8sAAIIAAkK/A39YQC7AQAIAAkK/A39YQC7AQAAAA==.',
Wo='Worthatry:BAACNQAFFH8FAAIBAAQKaAw5FADDAAABAAQKaAw5FADDAAA1AAQKfzAAAgEACgoMIhgsABcDAAEACgoMIhgsABcDAAAA.',
Xa='Xalbit:BAABNQAECn8mAAIDAAcKwgT4iADpAAADAAcKwgT4iADpAAAAAA==.Xanae:BAAANQAECgUIBQAAAA==.Xantharcis:BAAANQADCgEIAQAAAA==.Xantia:BAABNQAECn9BAAIeAAoK/RHdGgDkAQAeAAoK/RHdGgDkAQAAAA==.',
Xe='Xenlo:BAAANQAECgYICgAAAA==.',
Yo='Yogurt:BAAANQAECgQIBQAAAA==.',
Za='Zaizel:BAAANQAECgEIAQABNQAFFAcIFwAmAHgSAA==.Zalulu:BAAANQAECgMIAwABNQAECgQIBwAPAAAAAA==.Zathennyx:BAAANQAECgMIAwABNQAECgQIBAAPAAAAAA==.',
Ze='Zenpai:BAAANQAECgcIDwAAAA==.',
Zv='Zvorunalotus:BAAANQADCgYIDQAAAA==.',
['Ðr']='Ðread:BAAANQAECgcIDgAAAA==.',
['ßß']='ßßqñüt:BAABNQAECn8fAAIFAAcKhgl0QwAZAQAFAAcKhgl0QwAZAQAAAA==.',
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
