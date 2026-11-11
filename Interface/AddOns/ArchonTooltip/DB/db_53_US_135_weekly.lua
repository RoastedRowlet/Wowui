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

local lookup = {'Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Priest-Holy','Priest-Shadow','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Druid-Feral','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Paladin-Protection','Monk-Brewmaster','Warlock-Affliction','Druid-Restoration','DemonHunter-Havoc','Paladin-Holy','Mage-Fire','DeathKnight-Blood','Warrior-Protection','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Balance','Hunter-Marksmanship','Priest-Discipline','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Achkmed:BAAANQAECgQIBAAAAA==.',
Ad='Adelaid:BAAANQAECgEIAQABNQAFFAcIFQABAJoPAA==.',
Ak='Akalon:BAABNQAECn9iAAICAAoKMxAwQAC9AQACAAoKMxAwQAC9AQAAAA==.',
Al='Aleckzander:BAAANQAECgMIBAABNQAECgkJMAADADMlAA==.Alexandrìte:BAAANQADCgcIEQAAAA==.Allfrost:BAAANQAECgUIDAAAAA==.Altscale:BAAANQAECggIDgAAAA==.Aluda:BAABNQAECn8qAAMEAAgKrhU6SgD6AQAEAAcKaBU6SgD6AQAFAAYKTw8bQAAuAQAAAA==.',
Am='Amberina:BAAANQADCggICgAAAA==.',
An='Anùbis:BAAANQADCgIIAgAAAA==.',
Ao='Aoeina:BAABNQAECn84AAMGAAoKFBuXfwB/AgAGAAoKvxiXfwB/AgAHAAIKiBuaJgCXAAAAAA==.',
Ap='Apollo:BAABNQAECn80AAIIAAoKByZiEQABAwAIAAoKByZiEQABAwAAAA==.',
Ar='Arcanelotus:BAAANQADCgIIAwAAAA==.Arctus:BAAANQADCgcIBwAAAA==.Ariaves:BAABNQAECn8YAAIFAAkKRhGvIwAVAgAFAAkKRhGvIwAVAgAAAA==.Arlind:BAAANQAECgYIEwAAAA==.Artemix:BAAANQAECgQIBAAAAA==.Arthara:BAAANQABCgQIBwAAAA==.',
As='Askeral:BAAANQAECgEIAQAAAA==.Astelana:BAABNQAECn8pAAIBAAgK+QfIvwA9AQABAAgK+QfIvwA9AQAAAA==.',
At='Atanatari:BAAANQAECgUICQABNQAECgkJHwAFACgFAA==.Athennah:BAAANQADCgUIBAAAAA==.',
Ba='Bannar:BAAANQAECgcICQAAAA==.Bassotan:BAABNQAECn8YAAIBAAkKawqb1AByAQABAAkKawqb1AByAQAAAA==.Baticus:BAAANQADCgcIBwAAAA==.',
Be='Beleva:BAAANQAECgIIBQAAAA==.Belias:BAAANQAECggICwAAAA==.Bezzaj:BAAANQAFFAIIAgABNQAFFAcIGwAGABgSAA==.',
Bj='Bjornagain:BAAANQAECgUICgAAAA==.Björne:BAAANQADCggIFAAAAA==.',
Bl='Blackendmoon:BAABNQAECn8wAAMJAAkKngbSVgAiAQAJAAkKHgbSVgAiAQAKAAIKdQioygBXAAAAAA==.Blacklotus:BAAANQAECggIEAAAAA==.Bloodedge:BAAANQAECgYIDwAAAA==.Bloodklaat:BAAANQAECgUICAAAAA==.Bloodnight:BAABNQAECn8cAAIBAAkKKhHnsQC7AQABAAkKKhHnsQC7AQAAAA==.Bluebubbles:BAAANQADCggIIQAAAA==.Bluéyes:BAAANQAECgYIDQAAAA==.Blvckscvl:BAABNQAECn8sAAIIAAoK/RxgKQDzAgAIAAoK/RxgKQDzAgAAAA==.Blynna:BAAANQADCgYICQAAAA==.',
Br='Brannik:BAABNQAECn8WAAMLAAcKoQzwMADCAAALAAcKoQzwMADCAAAMAAEKmQP21gApAAAAAA==.Breña:BAAANQADCggIGAAAAA==.Broadleaf:BAAANQAECgQICgAAAA==.',
Ca='Camiliana:BAAANQADCgUIBQAAAA==.',
Ce='Cellulight:BAABNQAECn8uAAMNAAoKbhi4DQCKAgANAAoKbhi4DQCKAgAOAAEKsAmwSgAnAAAAAA==.',
Ch='Charizard:BAAANQAECgcIGAAAAQ==.Chelais:BAAANQAECggICQABNQABCgIIAgAPAAAAAA==.Cherrycola:BAAANQAECgQICQAAAA==.Chobits:BAAANQAECgQIBAAAAA==.',
Co='Coppertopp:BAAANQADCgQJBQAAAA==.Corvany:BAAANQAECgUICwAAAA==.',
Cr='Crawley:BAABNQAECn+BAAILAAoK7h+tBADUAgALAAoK7h+tBADUAgAAAA==.Crazalulla:BAAANQADCggIGAAAAA==.Creeder:BAABNQAECn8fAAIBAAkK1gwNqwDJAQABAAkK1gwNqwDJAQAAAA==.Crixus:BAABNQAECn8fAAMQAAoKbA0xBgBqAQAQAAkK2AwxBgBqAQARAAUKCwWv/QDQAAAAAA==.',
Da='Dagoland:BAAANQADCggIBQAAAA==.Daij:BAAANQADCgUIBgAAAA==.Dainty:BAAANQAECgIIAQABNQAFFAcIEgAIAG0WAA==.',
De='Deaanor:BAAANQAECgMIBAAAAA==.Deathcòw:BAAANQAECgYICwAAAA==.Deween:BAABNQAECn8WAAMBAAgKHhOJ9gAwAQABAAgKHhOJ9gAwAQASAAEKAAAjdgAAAAAAAA==.',
Di='Diamond:BAAANQAECgIIAQAAAA==.Dionysuz:BAAANQAECggIDwAAAA==.Disdekay:BAAANQAECgMIAgABNQAECggIDAAPAAAAAA==.',
Do='Dojoro:BAABNQAECn8rAAITAAkKFRKQCgCBAQATAAkKFRKQCgCBAQAAAA==.Dorc:BAAANQADCgMIAwAAAA==.Dotsarelocks:BAABNQAECn8fAAQUAAoKcRQaDQCKAQAUAAgK+xIaDQCKAQARAAMKoxLO+wBNAAAQAAIKxxgRKwBMAAAAAA==.',
Dr='Dradyos:BAABNQAECn8WAAIVAAcKVA0dMgBFAQAVAAcKVA0dMgBFAQAAAA==.Draegare:BAAANQAFFAEIAQAAAA==.Drdeer:BAAANQADCgUIBgAAAA==.Drewarel:BAAANQAECgQIBAABNQAECggIGwARAJYCAA==.Drittsz:BAAANQADCgYIBgAAAA==.',
Ee='Eelecurb:BAAANQADCggIDwAAAA==.',
Ei='Eisysae:BAAANQABCgIJAwAAAA==.',
El='Eliard:BAAANQABCggICQAAAA==.Ellå:BAAANQAECgUICAABNQAECgoKQgAEAJ0iAA==.',
Er='Erisynn:BAEANQADCgUIBQABNQAFFAUIDQAWAMYEAA==.',
Et='Eternalx:BAAANQAECgEIAQAAAA==.',
Ev='Evang:BAABNQAECn8nAAIIAAgKtQvyggCYAQAIAAgKtQvyggCYAQAAAA==.Everd:BAABNQAECn8zAAIBAAkKNQvxogByAQABAAkKNQvxogByAQAAAA==.',
Fi='Fiametta:BAABNQAECn81AAIQAAoKnBjwAwDRAQAQAAoKnBjwAwDRAQAAAA==.Firerain:BAAANQADCggIEQAAAA==.',
Fl='Flameward:BAAANQAECgUICgAAAA==.Flippi:BAAANQADCgEIAQAAAA==.Flokii:BAAANQADCgEIAQAAAA==.',
Fo='Forkingidiot:BAAANQAECgQIBAAAAA==.Forodin:BAAANQADCgYIBgABNQADCggIFAAPAAAAAA==.Foxymizzy:BAAANQAECgQIBAABNQAECgoKJQAXAP0dAA==.',
Fr='Freadrick:BAAANQADCgEIAQABNQADCggIFAAPAAAAAA==.Frostknight:BAAANQAECgYICAAAAA==.',
Fu='Funsize:BAABNQAECn9CAAIEAAoKnSJEEABJAwAEAAoKnSJEEABJAwAAAA==.',
Ga='Gazzlok:BAAANQAECgQIBQAAAA==.',
Ge='Gesen:BAAANQADCggIFQAAAA==.',
Gl='Global:BAAANQADCgEIAQABNQAECgkJKgAYAJEbAA==.Gloriance:BAABNQAECn8nAAIRAAgKJhfPTgDVAQARAAgKJhfPTgDVAQAAAA==.',
Go='Gondra:BAAANQABCgIIBAABNQAECgUICwAPAAAAAA==.Gortalon:BAAANQABCgIIAgAAAA==.',
Ha='Haplo:BAAANQAECgUICwAAAA==.',
He='Hellmet:BAAANQAECgIIAgABNQAECgMIAwAPAAAAAQ==.Hey:BAACNQAFFH8IAAMCAAMKvgLPHgC/AAACAAMKvgLPHgC/AAADAAIKGRkmJwBRAAA1AAQKfygAAwMACgr4IMsfAOsCAAMACQpLIMsfAOsCAAIACApXCQaNANsAAAAA.',
Hi='Hinamori:BAAANQAECgcIDAAAAA==.',
Ho='Holythot:BAAANQAECgIIAwABNQAFFAcIIgAZAFsbAA==.',
Hu='Huogmi:BAAANQAECgQIBQAAAA==.',
Il='Ilharra:BAAANQAECgUIDwAAAA==.Ilililili:BAAANQAECgUIDAAAAA==.Illee:BAABNQAECn8zAAIGAAoKdhPzSwAcAgAGAAoKdhPzSwAcAgAAAA==.',
Im='Impgangpimp:BAEBNQAECn87AAIRAAoKGR9iGwCfAgARAAoKGR9iGwCfAgAAAA==.Imturtle:BAABNQAECn9PAAIZAAoKNiMHBgAhAwAZAAoKNiMHBgAhAwABNQAFFAQICQARAJITAA==.',
Ir='Irmis:BAABNQAECn8yAAMaAAoKmB+dBADNAgAaAAoKmB+dBADNAgAbAAoKeRhuBwAmAgAAAA==.',
Is='Ishaya:BAAANQAECgMIAwAAAA==.',
It='Ithrynluin:BAAANQAECgUICwABNQAECgkJHwAFACgFAA==.',
Iu='Iupiter:BAAANQAECggICgAAAA==.',
Iy='Iyahlieairia:BAAANQAECgMIBAAAAA==.',
Iz='Izabeth:BAABNQAECn8pAAQHAAkKZw0QEgCFAQAHAAkKZw0QEgCFAQAGAAEKQgLW1QErAAAYAAEKygOYDQAfAAAAAA==.',
Ja='Jamella:BAABNQAECn8yAAMBAAoKHhOHmQDwAQABAAcKQxiHmQDwAQAXAAoKqg3BWQCdAQAAAA==.',
Je='Jesüschrist:BAAANQAECgIIAQAAAA==.',
Ji='Jiglestd:BAAANQAECgQIAwAAAA==.',
Ju='Judeath:BAAANQABCggICQABNQADCggIGAAPAAAAAA==.',
Ka='Kabocha:BAAANQAECgcIDgAAAA==.Katsa:BAAANQADCgQIBgAAAA==.Kawi:BAAANQABCgIIAwAAAA==.Kayeh:BAAANQADCgIIAgAAAA==.',
Ki='Kiraneem:BAABNQAECn8wAAIIAAkKoBueVgAHAgAIAAkKoBueVgAHAgAAAA==.Kittie:BAABNQAECn8+AAIDAAoKzRWqRgBHAgADAAoKzRWqRgBHAgAAAA==.Kittynip:BAAANQADCgQIBAABNQAECgUIBgAPAAAAAA==.',
Kr='Krinj:BAABNQAECn8fAAMJAAkKXh2FHwCPAgAJAAkKXh2FHwCPAgAKAAEKOQsF4AA0AAAAAA==.Kristov:BAAANQAECggIDgAAAA==.',
Kt='Ktariani:BAAANQADCgYICgAAAA==.',
Ky='Kyden:BAAANQADCgEIAQAAAA==.',
['Kï']='Kïa:BAABNQAECn8YAAIEAAYKuwozqgAXAQAEAAYKuwozqgAXAQAAAA==.',
La='Lazulie:BAAANQADCgcIBwAAAA==.',
Le='Leahim:BAABNQAECn+UAAIZAAoKtyQmBABAAwAZAAoKtyQmBABAAwAAAA==.Ledani:BAABNQAECn8/AAMFAAoK5BJOEwAQAgAFAAoK5BJOEwAQAgAEAAYKGRxpbQDWAQAAAA==.Leonato:BAAANQADCgEIAQAAAA==.',
Li='Light:BAAANQADCggICAAAAA==.Lilbulky:BAAANQAECgcIDAABNQAECggIIgAcAM8dAA==.Liriels:BAAANQAECgQIBQABNQAECgUICwAPAAAAAA==.',
Lo='Lohith:BAABNQAECn8gAAIDAAkKSgVtjwBiAQADAAkKSgVtjwBiAQAAAA==.Lonedawg:BAAANQAECgUIEAAAAA==.Lourival:BAAANQAECgQJBAAAAA==.Lovécoil:BAABNQAECn8iAAIKAAoKXB7rDgCCAgAKAAoKXB7rDgCCAgAAAA==.',
Lu='Lunâ:BAAANQAECgYIEgAAAA==.',
['Lë']='Lëw:BAAANQAECgYICAAAAA==.',
Ma='Mageofthe:BAAANQADCgUICgAAAA==.Maggnolya:BAAANQAECggIDwAAAA==.Marsyx:BAABNQAECn8fAAIEAAkKvRvSKgC+AgAEAAkKvRvSKgC+AgAAAA==.Matidan:BAABNQAECn8YAAIdAAgK0BQCKAAEAgAdAAgK0BQCKAAEAgAAAA==.Mayael:BAABNQAECn8lAAMKAAkKrRomLQB/AgAKAAkKrRomLQB/AgAJAAcKuA8dUABzAQAAAA==.',
Me='Medreaux:BAABNQAECn+WAAMEAAoKvyNmBgCTAwAEAAoKvyNmBgCTAwAFAAEKdgADmQACAAAAAA==.Merrei:BAABNQAECn8rAAMWAAgKih5JIgDjAQAWAAgKih5JIgDjAQAeAAYKHwlvGAAqAQAAAA==.Meta:BAAANQADCggICAABNQAECgkJHwAZABcVAA==.Metalknyte:BAABNQAECn8xAAMZAAkKVhFhMwBtAQAZAAkKVhFhMwBtAQAKAAEKAAAsowAAAAAAAA==.',
Mi='Miniknyte:BAABNQAECn8/AAMVAAoKcxwACwAHAwAVAAoKcxwACwAHAwAfAAIKxAmPhgAxAAAAAA==.',
Mo='Mohu:BAAANQADCgcIBwAAAA==.Monkey:BAAANQADCgcICgAAAA==.Moonsz:BAAANQADCggIOQAAAA==.Mooseonloose:BAABNQAECn8aAAQKAAoKIhSfNQBRAgAKAAkK9xSfNQBRAgAJAAYKcw2NaQDeAAAZAAEKAACQxwA5AAAAAA==.Morandus:BAAANQAECgEIAQAAAA==.Moraria:BAAANQADCgMIAwAAAA==.Morgrathh:BAAANQADCgYIBgAAAA==.',
My='Mychelle:BAABNQAECn8yAAIgAAoKHAy2GACwAQAgAAoKHAy2GACwAQAAAA==.',
['Më']='Më:BAAANQAFFAIIAgABNQAECgkJGgAFAIwVAA==.',
Na='Nakryn:BAABNQAECn8lAAMHAAkK2ANGJADLAAAGAAkK2AOBzQD8AAAHAAYKLwJGJADLAAAAAA==.Natorn:BAABNQAECn8fAAIcAAkKeCHeJAAlAwAcAAkKeCHeJAAlAwAAAA==.Nay:BAAANQAECgcJCQAAAA==.',
Ne='Nemrod:BAAANQAECgEIAQAAAA==.Nezum:BAAANQAECgEIAQAAAA==.',
Ni='Nickoli:BAAANQAECgEIAQAAAA==.Niterend:BAABNQAECn8iAAMcAAgKzx25fgAeAgAcAAgKzx25fgAeAgAaAAEKjiHQMwBhAAAAAA==.',
No='Nojomoto:BAAANQADCgcIBwAAAA==.Norabel:BAAANQADCgQICQAAAA==.',
Nu='Nugehuts:BAABNQAFFH8TAAIZAAUKQyPaDAAZAQAZAAUKQyPaDAAZAQABNQAFFAkJPwARAOgmAA==.',
['Nø']='Nøxxi:BAABNQAECn83AAMQAAoKrBdqCgBQAgAQAAgKtBtqCgBQAgARAAoK1AvMVADCAQAAAA==.',
Ob='Obbimcanood:BAAANQADCgIIAgAAAA==.',
Ok='Okbloomer:BAAANQAECggIEAABNQAFFAgIEgAEAGAZAA==.',
Ol='Oldben:BAABNQAECn9CAAMBAAoKehVOVAAfAgABAAoKehVOVAAfAgASAAMK5gDHawA7AAAAAA==.',
Or='Oriel:BAABNQAECn8wAAIhAAkKUgkzBgB5AQAhAAkKUgkzBgB5AQAAAA==.',
Ov='Ovy:BAAANQAECgEIAQAAAA==.',
Pa='Panda:BAAANQAECgMIAwAAAA==.',
Pi='Pixystix:BAAANQADCgYIDAABNQAECgoKMgAgABwMAA==.',
Pl='Plop:BAAANQAECgQIBAABNQAECgkJKgAYAJEbAA==.Plumpcheeks:BAAANQADCggIEAAAAA==.',
Po='Poc:BAABNQAECn8jAAMOAAgKlwzkGwANAQAOAAgK8QnkGwANAQANAAMKAg+FQwCeAAAAAA==.Poundya:BAAANQADCgYICwAAAA==.',
Pr='Priblet:BAAANQAECgcIDAAAAA==.Prinsana:BAABNQAECn8wAAISAAkKwBA6JQC2AQASAAkKwBA6JQC2AQAAAA==.',
Pu='Purquis:BAABNQAECn8eAAIfAAkKKgvuNwA/AQAfAAkKKgvuNwA/AQAAAA==.',
Ra='Raeve:BAAANQADCgYIBgABNQADCgMIAwAPAAAAAA==.Raidkicker:BAAANQADCgEIAQABNQAECgoKHwAUAHEUAA==.',
Re='Reaperlord:BAABNQAECn8xAAMXAAgKsx41JwB/AgAXAAgKsx41JwB/AgABAAQKsgiFJAGgAAAAAA==.',
Ri='Rizzardofoz:BAAANQADCgMIAwAAAA==.',
Rl='Rllybuffnerd:BAAANQAECggICwAAAA==.',
Ro='Rodikus:BAABNQAECn9FAAMEAAoKEiGoFwAIAwAEAAoKEiGoFwAIAwAFAAMKVhRURACGAAAAAA==.',
Sa='Saeryan:BAAANQADCggICgAAAA==.Saiaa:BAABNQAECn8hAAILAAgKXwVTWwBKAQALAAgKXwVTWwBKAQAAAA==.Sakeena:BAAANQAECgUIEAAAAA==.Samará:BAAANQADCgQICAAAAA==.Sarleigh:BAAANQADCgIIAgAAAA==.Sattia:BAAANQAECgYIDQAAAA==.',
Sh='Shabloink:BAAANQABCgQIBAAAAA==.Shadereaver:BAAANQAECggICQAAAA==.Shenanygins:BAAANQADCgMIAwAAAA==.Shendalla:BAAANQABCgQIBAAAAA==.Shinokishi:BAABNQAECn8kAAIZAAgK7Q5iOwBFAQAZAAgK7Q5iOwBFAQAAAA==.',
Si='Silentninjaa:BAABNQAECn9BAAIbAAoKWhQVCAAVAgAbAAoKWhQVCAAVAgAAAA==.Simphunter:BAEBNQAECn8hAAIdAAoKuhXDIABGAgAdAAoKuhXDIABGAgABNQAECgoKOwARABkfAA==.Sinfel:BAABNQAECn8yAAMWAAoKvgefOwA4AQAWAAoKoQefOwA4AQAeAAYKbQQ4JABbAAAAAA==.Sit:BAAANQADCggICAAAAA==.',
Sk='Skoriavis:BAAANQAECgMIAgABNQAECgcIHQAMADUZAA==.Skoriko:BAABNQAECn8dAAMMAAcKNRn6FgAoAgAMAAcKNRn6FgAoAgALAAMK2gwbhgCaAAAAAA==.',
Sl='Slürmp:BAAANQAECgEIAQABNQAECggIEAAPAAAAAA==.',
Sn='Snowcones:BAAANQADCgUIBQAAAA==.',
So='Sonett:BAAANQAECgUICQAAAA==.Sonto:BAAANQAECgUICwAAAA==.',
Sp='Sparks:BAAANQAECggICAAAAA==.Splunk:BAABNQAECn8fAAIZAAkKFxWyOAAkAgAZAAkKFxWyOAAkAgAAAA==.',
St='Staggerdaddy:BAAANQAECgQIBgAAAA==.Stariya:BAAANQAECgUIEAAAAA==.Stompinghoof:BAAANQAECgYICAAAAA==.Strapattack:BAAANQAECgcICAAAAA==.Strawyà:BAABNQAECn8yAAMiAAoK/A4BGQDSAQAiAAoK/A4BGQDSAQAjAAEKWAUXUQAnAAAAAA==.',
Sw='Swïft:BAAANQAECgIIAgABNQAECgUICwAPAAAAAA==.',
Sy='Syananta:BAAANQAECgUIBgAAAA==.Syannara:BAAANQAECgUIBAABNQAECgUIBgAPAAAAAA==.Syklar:BAAANQADCgEIAQAAAA==.Syssa:BAABNQAECn8pAAIEAAoKchnLMgBgAgAEAAoKchnLMgBgAgABNQAECgcIIAAEAMkSAA==.',
['Sì']='Sìrocco:BAAANQAECgYICgAAAA==.',
Ta='Taleranor:BAAANQAECgcIDgAAAA==.Tamerizer:BAABNQAECn8oAAIgAAoKnhEAMADNAQAgAAoKnhEAMADNAQAAAA==.',
Te='Tealera:BAAANQAECgQIAwAAAA==.Tearali:BAAANQADCggICAAAAA==.Teejrath:BAABNQAECn8bAAQKAAkKVA/EWwChAQAKAAgKFhDEWwChAQAJAAEKzgqktAArAAAZAAEKAAB24AAeAAAAAA==.Teekeez:BAAANQADCggICQAAAA==.',
Th='Thekal:BAAANQADCgEIAgAAAA==.Theodorel:BAAANQAECgEIAQAAAA==.Thiadra:BAAANQABCgQIBwAAAA==.Thicchick:BAAANQAECgYICwAAAA==.Thirge:BAABNQAECn8mAAMbAAkKxAySFQBDAQAbAAgK6Q2SFQBDAQAcAAMKGAfe4gCZAAAAAA==.Thorek:BAAANQADCggIEAAAAA==.Thrushbeard:BAAANQADCgcIBwAAAA==.Thundertaco:BAABNQAECn8lAAICAAkK8wunVwBpAQACAAkK8wunVwBpAQAAAA==.',
Ti='Tighten:BAAANQABCgEIAQAAAA==.',
To='Toesniffer:BAAANQADCggICAAAAA==.Tofaaway:BAAANQAECgUIEAAAAA==.Tolak:BAAANQAECgYIDwAAAA==.Tormikinos:BAABNQAECn8mAAIfAAgKWgmePQAhAQAfAAgKWgmePQAhAQAAAA==.Torturousôwl:BAABNQAECn8YAAMEAAcK7xJjggA5AQAEAAcK7xJjggA5AQAhAAEK3AXeLwAlAAAAAA==.',
Tr='Trapology:BAAANQAECgIIAQAAAA==.Trillianh:BAAANQADCgEIAQAAAA==.Trisky:BAABNQAECn8nAAMXAAkKYBodNQCPAgAXAAkKYBodNQCPAgASAAEKMw+CdQAnAAAAAA==.',
Tu='Tumblebumble:BAAANQADCgMIAwAAAA==.Turtle:BAACNQAFFH8JAAIRAAQKkhP+FQDlAAARAAQKkhP+FQDlAAA1AAQKf1cAAxEACgoAIg8OAPICABEACgo6IQ8OAPICABAAAwoFFyoWAKEAAAAA.',
Va='Vadrakquin:BAAANQAECggIEAAAAA==.Valshamommy:BAABNQAECn8kAAIkAAoKPhKVEwAvAgAkAAoKPhKVEwAvAgAAAA==.Vanloth:BAAANQADCgEIAgAAAA==.Vantadim:BAAANQAECgQIBAAAAA==.Vanyssa:BAAANQADCgEIAQAAAA==.',
Ve='Vegito:BAAANQAECgIIBQAAAA==.Velfurry:BAAANQAECgEIAQABNQAFFAgIJQAlAGMMAA==.Verlassan:BAAANQADCgcICAAAAA==.',
Vi='Viverrid:BAAANQAECgEIAQAAAA==.',
Vo='Voinwar:BAACNQAFFH8KAAIaAAUK9xmgAQAqAQAaAAUK9xmgAQAqAQA1AAQKf0sAAhoACgqiJaABALIDABoACgqiJaABALIDAAAA.Vorpine:BAABNQAECn83AAMFAAoKThEkFQD3AQAFAAoKThEkFQD3AQAEAAgKfxQShACLAQAAAA==.',
We='Wetkittie:BAAANQADCgYIBwAAAA==.',
Wh='Whybebabo:BAAANQAECgMIAwAAAA==.',
Wi='Wiccawitch:BAAANQADCgYIEwAAAA==.Wirhl:BAABNQAECn8yAAIIAAkKLg5pbgDJAQAIAAkKLg5pbgDJAQAAAA==.',
Wo='Worthatry:BAACNQAFFH8KAAIBAAUKORmKEADvAAABAAUKORmKEADvAAA1AAQKfzQAAgEACgo0IhgsABcDAAEACgo0IhgsABcDAAAA.',
Xa='Xalbit:BAABNQAECn8mAAIDAAcKwgR+mgDYAAADAAcKwgR+mgDYAAAAAA==.Xanae:BAAANQAECgUIBQAAAA==.Xantia:BAABNQAECn9FAAIVAAoKgxLqHgDqAQAVAAoKgxLqHgDqAQAAAA==.',
Xe='Xenlo:BAAANQAECgYICgAAAA==.',
Yo='Yogurt:BAAANQAECgMIAwAAAA==.',
Za='Zaizel:BAAANQAECgEIAQABNQAFFAcIFwAmAHgSAA==.Zalulu:BAAANQAECgMIAwABNQAECgQIBwAPAAAAAA==.Zathennyx:BAAANQAECgMIAwABNQAECgQIAwAPAAAAAA==.',
Ze='Zenpai:BAAANQAECgcIDgAAAA==.',
Zv='Zvorunalotus:BAAANQADCgYIDQAAAA==.',
['Ðr']='Ðread:BAAANQAECgcIDgAAAA==.',
['ßß']='ßßqñüt:BAABNQAECn8rAAIFAAoK4QtRGQC+AQAFAAoK4QtRGQC+AQAAAA==.',
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
