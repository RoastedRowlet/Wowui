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

local lookup = {'Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Priest-Holy','Priest-Shadow','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Druid-Feral','Warlock-Destruction','Warlock-Demonology','Paladin-Protection','Monk-Brewmaster','Warlock-Affliction','Druid-Restoration','DemonHunter-Havoc','Paladin-Holy','Mage-Fire','DeathKnight-Blood','Priest-Discipline','Warrior-Protection','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Balance','Hunter-Marksmanship','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Achkmed:BAAANQAECgcICwAAAA==.',
Ad='Adelaid:BAAANQAECgEIAQABNQAFFAgIFwABAPcPAA==.',
Ak='Akalon:BAABNQAECn9iAAICAAoKMxB2RgC7AQACAAoKMxB2RgC7AQAAAA==.',
Al='Aleckzander:BAAANQAECgMIBAABNQAECgkJMAADADMlAA==.Alexandrìte:BAAANQADCgcIEQAAAA==.Allfrost:BAAANQAECgUIDAAAAA==.Altscale:BAAANQAECggIDgAAAA==.Aluda:BAABNQAECn8rAAMEAAkKSBTXUgDvAQAEAAgK3xPXUgDvAQAFAAYKTw8bQAAuAQAAAA==.',
Am='Amberina:BAAANQADCggICAAAAA==.',
An='Anùbis:BAAANQADCgIIAgAAAA==.',
Ao='Aoeina:BAABNQAECn9BAAMGAAoKJxyXfwB/AgAGAAoK0xmXfwB/AgAHAAIKiBsQKgCTAAAAAA==.',
Ap='Apollo:BAABNQAECn83AAIIAAoKISZQBABtAwAIAAoKISZQBABtAwAAAA==.',
Ar='Arcanelotus:BAAANQADCgIIAwAAAA==.Arctus:BAAANQADCgcIBwAAAA==.Ariaves:BAABNQAECn8YAAIFAAkKRhGvIwAVAgAFAAkKRhGvIwAVAgAAAA==.Arlind:BAABNQAECn8dAAIIAAgK5wUpxgAlAQAIAAgK5wUpxgAlAQAAAA==.Artemix:BAAANQAECgQIBAAAAA==.Arthara:BAAANQABCgQIBwAAAA==.',
As='Askeral:BAAANQAECgEIAQAAAA==.Astelana:BAABNQAECn8qAAIBAAkKegjKzgA6AQABAAkKegjKzgA6AQAAAA==.',
At='Atanatari:BAAANQAECgUIDgABNQAECgcIEgAJAAAAAA==.Athennah:BAAANQADCgUIBAAAAA==.',
Ba='Bannar:BAAANQAECgcICQAAAA==.Bassotan:BAABNQAECn8YAAIBAAkKawqb1AByAQABAAkKawqb1AByAQAAAA==.Baticus:BAAANQADCgcIBwAAAA==.',
Be='Beleva:BAAANQAECgIIBQAAAA==.Belias:BAAANQAECggICwAAAA==.Bezzaj:BAAANQAFFAIIAgABNQAFFAgIHQAGAMYPAA==.',
Bj='Bjornagain:BAAANQAECgUICgAAAA==.Björne:BAAANQADCggIFAAAAA==.',
Bl='Blackendmoon:BAABNQAECn88AAMKAAkKCQiwVABDAQAKAAkKpAewVABDAQALAAIKdQioygBXAAAAAA==.Blacklotus:BAAANQAECggIEAAAAA==.Bloodedge:BAAANQAECgYIDwAAAA==.Bloodklaat:BAAANQAECgUICAAAAA==.Bloodnight:BAABNQAECn8cAAIBAAkKKhHnsQC7AQABAAkKKhHnsQC7AQAAAA==.Bluebubbles:BAAANQADCggIIQAAAA==.Bluéyes:BAAANQAECgYIDQAAAA==.Blvckscvl:BAACNQAFFH8GAAIIAAMKLg0pFgDgAAAIAAMKLg0pFgDgAAA1AAQKfzAAAggACgqFHWApAPMCAAgACgqFHWApAPMCAAAA.Blynna:BAAANQADCgYICQAAAA==.',
Br='Brannik:BAABNQAECn8WAAMMAAcKoQyrSwCTAQAMAAcKoQyrSwCTAQANAAEKmQOB4gApAAAAAA==.Breña:BAAANQADCggIGAAAAA==.Broadleaf:BAAANQAECgQICgAAAA==.',
Ca='Camiliana:BAAANQADCgUIBQAAAA==.',
Ce='Cellulight:BAABNQAECn8xAAMOAAoKQxm4DQCKAgAOAAoKQxm4DQCKAgAPAAEKsAm3UAAnAAAAAA==.',
Ch='Charizard:BAAANQAECgcIGAAAAQ==.Chelais:BAAANQAECggICQABNQABCgIIAgAJAAAAAA==.Cherrycola:BAAANQAECgQICQAAAA==.Chobits:BAAANQAECgQIBAAAAA==.',
Co='Coppertopp:BAAANQADCgQJBQAAAA==.Corvany:BAAANQAECgUICwAAAA==.',
Cr='Crawley:BAABNQAECn+BAAIMAAoK7h8fBQDNAgAMAAoK7h8fBQDNAgAAAA==.Crazalulla:BAAANQADCggIFgAAAA==.Creeder:BAABNQAECn8fAAIBAAkK1gwNqwDJAQABAAkK1gwNqwDJAQAAAA==.Crixus:BAABNQAECn8fAAMQAAoKbA0QBwBnAQAQAAkK2AwQBwBnAQARAAUKCwWv/QDQAAAAAA==.',
Da='Dagoland:BAAANQADCggIBQAAAA==.Daij:BAAANQADCgUIBQAAAA==.Dainty:BAAANQAECgIIAQABNQAFFAcIEgAIAG0WAA==.',
De='Deaanor:BAAANQAECgMIBAAAAA==.Deathcòw:BAAANQAECgYICwAAAA==.Deween:BAABNQAECn8WAAMBAAgKHhOJ9gAwAQABAAgKHhOJ9gAwAQASAAEKAAB2fAAAAAAAAA==.',
Di='Diamond:BAAANQAECgIIAQAAAA==.Dionysuz:BAAANQAECggIDwAAAA==.Disdekay:BAAANQAECgMIAgABNQAECggIDAAJAAAAAA==.',
Do='Dojoro:BAABNQAECn8vAAITAAoKyhLrCADCAQATAAoKyhLrCADCAQAAAA==.Dorc:BAAANQADCgMIAwAAAA==.Dotsarelocks:BAABNQAECn8fAAQUAAoKcRQaDQCKAQAUAAgK+xIaDQCKAQARAAMKoxL2BAFNAAAQAAIKxxiRLQBMAAAAAA==.',
Dr='Dradyos:BAABNQAECn8YAAIVAAcKOQ7YNABNAQAVAAcKOQ7YNABNAQAAAA==.Draegare:BAAANQAFFAEIAQAAAA==.Drdeer:BAAANQADCgUIBgAAAA==.Drewarel:BAAANQAECgQIBAABNQAECgcIFgAHAFYCAA==.Drittsz:BAAANQADCgYIBgAAAA==.',
Ee='Eelecurb:BAAANQADCggIDwAAAA==.',
Ei='Eisysae:BAAANQADCggICAAAAA==.',
El='Eliard:BAAANQABCggICQAAAA==.Ellå:BAAANQAECgUICAABNQAECgoKQgAEAJ0iAA==.',
Er='Erisynn:BAEANQADCgUIBQABNQAFFAUIDQAWAMYEAA==.',
Et='Eternalx:BAAANQAECgEIAQAAAA==.',
Ev='Evang:BAABNQAECn8oAAIIAAkKWgvpjwCWAQAIAAkKWgvpjwCWAQAAAA==.Everd:BAABNQAECn85AAIBAAoK/AozkwCmAQABAAoK/AozkwCmAQAAAA==.',
Fi='Fiametta:BAABNQAECn84AAIQAAoKuhhhAwARAgAQAAoKuhhhAwARAgAAAA==.Firerain:BAAANQADCggIEQAAAA==.',
Fl='Flameward:BAAANQAECgUIDgAAAA==.Flippi:BAAANQABCggIDgAAAA==.',
Fo='Forkingidiot:BAAANQAECgQIBAAAAA==.Forodin:BAAANQADCgYIBgABNQADCggIFAAJAAAAAA==.Foxymizzy:BAAANQAECgQIBAABNQAECgoKJQAXAP0dAA==.',
Fr='Freadrick:BAAANQADCgEIAQABNQADCggIFAAJAAAAAA==.Frostknight:BAAANQAECgYICAAAAA==.',
Fu='Funsize:BAABNQAECn9CAAIEAAoKnSIsEwA/AwAEAAoKnSIsEwA/AwAAAA==.',
Ga='Gazzlok:BAAANQAECgQIBwAAAA==.',
Ge='Gesen:BAAANQADCggIFQAAAA==.Geva:BAAANQAECgIIAgAAAA==.',
Gl='Global:BAAANQABCgcICgABNQAECgkJLgAYAKgcAA==.Gloriance:BAABNQAECn8oAAIRAAkK8xahVQDTAQARAAkK8xahVQDTAQAAAA==.',
Go='Gondra:BAAANQABCgIIBAABNQAECgUICwAJAAAAAA==.Gortalon:BAAANQABCgIIAgAAAA==.',
Ha='Haplo:BAAANQAECgUICwAAAA==.',
He='Hellmet:BAAANQAECgIIAgABNQAECgMIAwAJAAAAAQ==.Hey:BAACNQAFFH8IAAMCAAMKvgLPHgC/AAACAAMKvgLPHgC/AAADAAIKGRkMKgBRAAA1AAQKfygAAwMACgr4IMsfAOsCAAMACQpLIMsfAOsCAAIACApXCeWWANoAAAAA.',
Hi='Hinamori:BAAANQAECgcIDAAAAA==.',
Ho='Holythot:BAAANQAECgIIAwABNQAFFAcIIgAZAFsbAA==.',
Hu='Huogmi:BAAANQAECgQIBQAAAA==.',
Il='Ilharra:BAABNQAECn8cAAMFAAcK1gvJLQAZAQAFAAcK1gvJLQAZAQAaAAEKUgceHQAoAAAAAA==.Ilililili:BAAANQAECgUIDAAAAA==.Illee:BAABNQAECn87AAIGAAoKoBXURAA+AgAGAAoKoBXURAA+AgAAAA==.',
Im='Impgangpimp:BAEBNQAECn88AAIRAAoKGR9eHwCWAgARAAoKGR9eHwCWAgAAAA==.Imturtle:BAABNQAECn9TAAIZAAoKNiO9BgAbAwAZAAoKNiO9BgAbAwABNQAFFAQICQARAJITAA==.',
Ir='Irmis:BAABNQAECn88AAMbAAoKnSD4BADPAgAbAAoKxR/4BADPAgAcAAoKThxbBQCEAgAAAA==.',
Is='Ishaya:BAAANQAECgMIAwAAAA==.',
It='Ithrynluin:BAAANQAECgcIEgAAAA==.',
Iu='Iupiter:BAAANQAECggICgAAAA==.',
Iy='Iyahlieairia:BAAANQAECgMIBAAAAA==.',
Iz='Izabeth:BAABNQAECn8yAAQHAAkKsQ+wDwCVAQAHAAkKsQ+wDwCVAQAGAAEKQgLW1QErAAAYAAEKygMfDwAfAAAAAA==.',
Ja='Jamella:BAABNQAECn8yAAMBAAoKHhOHmQDwAQABAAcKQxiHmQDwAQAXAAoKqg2+YQCUAQAAAA==.',
Je='Jesüschrist:BAAANQAECgEIAQAAAA==.',
Ji='Jiglestd:BAAANQAECgQIAwAAAA==.',
Ju='Judeath:BAAANQABCggICQABNQADCggIGAAJAAAAAA==.',
Ka='Kabocha:BAAANQAECgcIDgAAAA==.Katsa:BAAANQADCgQIBgAAAA==.Kawi:BAAANQABCgIIAwAAAA==.Kayeh:BAAANQADCgIIAgAAAA==.',
Ki='Kiraneem:BAABNQAECn84AAIIAAkKFxytXQANAgAIAAkKFxytXQANAgAAAA==.Kittie:BAABNQAECn8+AAIDAAoKzRWqRgBHAgADAAoKzRWqRgBHAgAAAA==.Kittynip:BAAANQADCgQIBAABNQAECgYICQAJAAAAAA==.',
Kr='Krinj:BAABNQAECn8fAAMKAAkKXh2FHwCPAgAKAAkKXh2FHwCPAgALAAEKOQsF4AA0AAAAAA==.Kristov:BAAANQAECgcIDgAAAA==.',
Kt='Ktariani:BAAANQADCgYICgAAAA==.',
Ky='Kyden:BAAANQADCgEIAQAAAA==.',
['Kï']='Kïa:BAABNQAECn8aAAIEAAYKuwozqgAXAQAEAAYKuwozqgAXAQAAAA==.',
La='Lazulie:BAAANQADCgcIBwAAAA==.',
Le='Leahim:BAABNQAECn+cAAIZAAoKHSVsAwBPAwAZAAoKHSVsAwBPAwAAAA==.Ledani:BAABNQAECn9CAAMFAAoKbhUtEwAqAgAFAAoKbhUtEwAqAgAEAAYKGRxpbQDWAQAAAA==.Leonato:BAAANQADCgEIAQAAAA==.',
Li='Light:BAAANQADCggICAAAAA==.Lilbulky:BAAANQAECgcIDwABNQAECggIIwAdAM8dAA==.Liriels:BAAANQAECgQIBQABNQAECgUICwAJAAAAAA==.',
Lo='Lohith:BAABNQAECn8gAAIDAAkKSgVtjwBiAQADAAkKSgVtjwBiAQAAAA==.Lonedawg:BAAANQAECgUIEAAAAA==.Lourival:BAAANQAECgQJBAAAAA==.Lovécoil:BAABNQAECn8lAAILAAoKax4fEACAAgALAAoKax4fEACAAgAAAA==.',
Lu='Lunâ:BAAANQAECgYIEgAAAA==.',
['Lë']='Lëw:BAAANQAECgYICAAAAA==.',
Ma='Mageofthe:BAAANQADCgUICAAAAA==.Maggnolya:BAAANQAECggIEgAAAA==.Marsyx:BAABNQAECn8fAAIEAAkKvRvSKgC+AgAEAAkKvRvSKgC+AgAAAA==.Matidan:BAABNQAECn8YAAIeAAgK0BQCKAAEAgAeAAgK0BQCKAAEAgAAAA==.Mayael:BAABNQAECn8lAAMLAAkKrRomLQB/AgALAAkKrRomLQB/AgAKAAcKuA8dUABzAQAAAA==.',
Me='Medreaux:BAABNQAECn+eAAMEAAoKESRmBgCTAwAEAAoKESRmBgCTAwAFAAEKdgADmQACAAAAAA==.Merrei:BAABNQAECn8sAAMWAAgKvx5PJQDgAQAWAAgKvx5PJQDgAQAfAAYKHwlvGAAqAQAAAA==.Meta:BAAANQADCggICAABNQAECgkJHwAZABcVAA==.Metalknyte:BAABNQAECn86AAMZAAkKaRLaMQCEAQAZAAkKaRLaMQCEAQALAAEKAAAmqgAAAAAAAA==.',
Mi='Miniknyte:BAABNQAECn9IAAMVAAoKOR0pCwAaAwAVAAoKOR0pCwAaAwAgAAIKxAm/jAAxAAAAAA==.',
Mo='Mohu:BAAANQADCgcIBwAAAA==.Monkey:BAAANQADCgcICgAAAA==.Moonsz:BAAANQADCggINwAAAA==.Mooseonloose:BAABNQAECn8dAAQLAAoKIhSfNQBRAgALAAkK9xSfNQBRAgAKAAYKkg7+bQDmAAAZAAEKAACQxwA5AAAAAA==.Morandus:BAAANQAECgEIAQAAAA==.Moraria:BAAANQADCgMIAwAAAA==.Morgrathh:BAAANQADCgYIBgAAAA==.',
My='Mychelle:BAABNQAECn81AAIhAAoKVwxFGgCxAQAhAAoKVwxFGgCxAQAAAA==.',
['Më']='Më:BAAANQAFFAIIAgABNQAECgkJGgAFAIwVAA==.',
Na='Nakryn:BAABNQAECn8mAAMHAAoKqgNGJADLAAAGAAoKqgPlwwAfAQAHAAYKLwJGJADLAAAAAA==.Natorn:BAABNQAECn8fAAIdAAkKeCHeJAAlAwAdAAkKeCHeJAAlAwAAAA==.Nay:BAAANQAECgcJCQAAAA==.',
Ne='Nemrod:BAAANQAECgEIAQAAAA==.Nezum:BAAANQAECgEIAQAAAA==.',
Ni='Nickoli:BAAANQAECgEIAQAAAA==.Niterend:BAABNQAECn8jAAMdAAgKzx25fgAeAgAdAAgKzx25fgAeAgAbAAEKjiGBNwBhAAAAAA==.',
No='Nojomoto:BAAANQADCgcIBwAAAA==.Norabel:BAAANQADCgQICAAAAA==.',
Nu='Nugehuts:BAABNQAFFH8TAAIZAAUKQyOHDQAvAQAZAAUKQyOHDQAvAQABNQAFFAkJRgARAOomAA==.',
['Nø']='Nøxxi:BAABNQAECn9AAAMQAAoKhhhqCgBQAgAQAAgKtBtqCgBQAgARAAoK8A7jUADhAQAAAA==.',
Ob='Obbimcanood:BAAANQADCgIIAgAAAA==.',
Ok='Okbloomer:BAAANQAECggIEAABNQAFFAgIEgAEAGAZAA==.',
Ol='Oldben:BAABNQAECn9LAAMBAAoK9RaJUAA6AgABAAoK9RaJUAA6AgASAAMK5gDHawA7AAAAAA==.',
Or='Oriel:BAABNQAECn85AAIaAAkKQg9ABQDEAQAaAAkKQg9ABQDEAQAAAA==.',
Ov='Ovy:BAAANQAECgEIAQAAAA==.',
Pa='Paleblueeye:BAAANQAECgQIAgAAAA==.Panda:BAAANQAECgMIAwAAAA==.',
Pi='Pixystix:BAAANQADCgYIDAABNQAECgoKNQAhAFcMAA==.',
Pl='Plop:BAAANQAECgQIBAABNQAECgkJLgAYAKgcAA==.Plumpcheeks:BAAANQADCggIDQAAAA==.',
Po='Poc:BAABNQAECn8oAAMPAAkKEwyyHgARAQAPAAkKzgmyHgARAQAOAAMKAg/XSACbAAAAAA==.Poundya:BAAANQADCgYICgAAAA==.',
Pr='Priblet:BAAANQAECgcIDAAAAA==.Prinsana:BAABNQAECn81AAISAAkKZxI6JQC2AQASAAkKZxI6JQC2AQAAAA==.',
Pu='Purquis:BAABNQAECn8eAAIgAAkKKgsBPAA+AQAgAAkKKgsBPAA+AQAAAA==.',
Ra='Raeve:BAAANQADCgYIBgABNQADCgMIAwAJAAAAAA==.Raidkicker:BAAANQADCgEIAQABNQAECgoKHwAUAHEUAA==.',
Re='Reaperlord:BAABNQAECn85AAMXAAoKOBuGIwCoAgAXAAoKOBuGIwCoAgABAAYKCAc4EAHRAAAAAA==.',
Ri='Rizzardofoz:BAAANQADCgMIAwAAAA==.',
Rl='Rllybuffnerd:BAAANQAECggICwAAAA==.',
Ro='Rodikus:BAABNQAECn9OAAMEAAoKtiHtFQAoAwAEAAoKtiHtFQAoAwAFAAQKFBZrRwCNAAAAAA==.',
Sa='Saeryan:BAAANQADCggICAAAAA==.Saiaa:BAABNQAECn8qAAIMAAkKPwdZIgAaAQAMAAkKPwdZIgAaAQAAAA==.Sakeena:BAAANQAECgUIEAAAAA==.Samará:BAAANQADCgQICAAAAA==.Sarleigh:BAAANQADCgIIAgAAAA==.Sattia:BAAANQAECgYIDQAAAA==.',
Sh='Shabloink:BAAANQABCgQIBAAAAA==.Shadereaver:BAAANQAECggICQAAAA==.Shenanygins:BAAANQADCgMIAwAAAA==.Shendalla:BAAANQABCgQIBAAAAA==.Shinokishi:BAABNQAECn8lAAIZAAkKvw7tPwA/AQAZAAkKvw7tPwA/AQAAAA==.',
Si='Silentninjaa:BAABNQAECn9FAAIcAAoKzRQXCQATAgAcAAoKzRQXCQATAgAAAA==.Simphunter:BAEBNQAECn8jAAIeAAoKOxbDIABGAgAeAAoKOxbDIABGAgABNQAECgoKPAARABkfAA==.Sinfel:BAABNQAECn82AAMWAAoKIAgCQAA5AQAWAAoKAwgCQAA5AQAfAAYKbQS+JgBbAAAAAA==.Sit:BAAANQADCggICAAAAA==.',
Sk='Skoriavis:BAAANQAECgMIAgABNQAECgcIHQANADUZAA==.Skoriko:BAABNQAECn8dAAMNAAcKNRn6FgAoAgANAAcKNRn6FgAoAgAMAAMK2gwbhgCaAAAAAA==.',
Sl='Slürmp:BAAANQAECgEIAQABNQAECggIEAAJAAAAAA==.',
Sn='Snowcones:BAAANQADCgUIBQAAAA==.',
So='Sonett:BAAANQAECgUICQAAAA==.Sonto:BAABNQAECn8WAAQRAAoKQBSkaACdAQARAAoKQBSkaACdAQAQAAEK5gdyfQAvAAAUAAIKAAD9NAAAAAAAAA==.',
Sp='Sparks:BAAANQAECggICAAAAA==.Splunk:BAABNQAECn8fAAIZAAkKFxWyOAAkAgAZAAkKFxWyOAAkAgAAAA==.',
St='Staggerdaddy:BAAANQAECgQIBgAAAA==.Stariya:BAAANQAECgUIEAAAAA==.Stompinghoof:BAAANQAECgYICAAAAA==.Strapattack:BAAANQAECgcICAAAAA==.Strawyà:BAABNQAECn8yAAMiAAoK/A4QGwDSAQAiAAoK/A4QGwDSAQAjAAEKWAUXUQAnAAAAAA==.',
Sw='Swïft:BAAANQAECgIIAgABNQAECgoKFgARAEAUAA==.',
Sy='Syananta:BAAANQAECgYICQAAAA==.Syannara:BAAANQAECgUIBAABNQAECgYICQAJAAAAAA==.Syklar:BAAANQADCgEIAQAAAA==.Syssa:BAABNQAECn8vAAIEAAoK3xmPIgDOAgAEAAoK3xmPIgDOAgABNQAECgcIIQAEADETAA==.',
['Sì']='Sìrocco:BAAANQAECgYICgAAAA==.',
Ta='Taleranor:BAAANQAECggIDwAAAA==.Tamerizer:BAABNQAECn8oAAIhAAoKnhEAMADNAQAhAAoKnhEAMADNAQAAAA==.',
Te='Tealera:BAAANQAECgQIAwAAAA==.Tearali:BAAANQADCggICAAAAA==.Teejrath:BAABNQAECn8bAAQLAAkKVA/EWwChAQALAAgKFhDEWwChAQAKAAEKzgqktAArAAAZAAEKAAB24AAeAAAAAA==.Teekeez:BAAANQADCggICQAAAA==.',
Th='Thekal:BAAANQADCgEIAgAAAA==.Theodorel:BAAANQAECgEIAQAAAA==.Thiadra:BAAANQABCgQIBwAAAA==.Thicchick:BAAANQAECgYICwAAAA==.Thirge:BAABNQAECn8qAAMcAAoKBw28FQAfAQAcAAkKDA68FQAfAQAdAAMKGAc97QCYAAAAAA==.Thorek:BAAANQADCggIDwAAAA==.Thrushbeard:BAAANQADCgcIBwAAAA==.Thundertaco:BAABNQAECn8oAAICAAoK9wy0TQCgAQACAAoK9wy0TQCgAQAAAA==.',
Ti='Tighten:BAAANQABCgEIAQAAAA==.',
To='Toesniffer:BAAANQADCggICAAAAA==.Tofaaway:BAAANQAECgUIEAAAAA==.Tolak:BAAANQAECgYIDwAAAA==.Tormikinos:BAABNQAECn8nAAIgAAkK2gjJQQAgAQAgAAkK2gjJQQAgAQAAAA==.Torturousôwl:BAABNQAECn8YAAMEAAcK7xJnigA5AQAEAAcK7xJnigA5AQAaAAEK3AXeLwAlAAAAAA==.',
Tr='Trapology:BAAANQAECgEIAQAAAA==.Trillianh:BAAANQADCgEIAQAAAA==.Trisky:BAABNQAECn8nAAMXAAkKYBodNQCPAgAXAAkKYBodNQCPAgASAAEKMw+CdQAnAAAAAA==.',
Tu='Tumblebumble:BAAANQADCgMIAwAAAA==.Turtle:BAACNQAFFH8JAAIRAAQKkhNhGQDgAAARAAQKkhNhGQDgAAA1AAQKf1cAAxEACgoAIqgQAOoCABEACgo6IagQAOoCABAAAwoFF4sXAKIAAAAA.',
Va='Vadrakquin:BAAANQAECggIEAAAAA==.Valshamommy:BAABNQAECn8kAAIkAAoKPhKVEwAvAgAkAAoKPhKVEwAvAgAAAA==.Vanloth:BAAANQADCgEIAgAAAA==.Vantadim:BAAANQAECgQIBAAAAA==.',
Ve='Vegito:BAAANQAECgIIBQAAAA==.Velfurry:BAAANQAECgEIAQABNQAFFAkJJwAlAPALAA==.Verlassan:BAAANQADCgcIBwAAAA==.',
Vi='Viverrid:BAAANQAECgEIAQAAAA==.',
Vo='Voinwar:BAACNQAFFH8KAAIbAAUK9xkDAgAiAQAbAAUK9xkDAgAiAQA1AAQKf1AAAhsACgqiJaABALIDABsACgqiJaABALIDAAAA.Vorpine:BAABNQAECn89AAMFAAoKThHFFgD3AQAFAAoKThHFFgD3AQAEAAkKwxafbACXAQAAAA==.',
We='Wetkittie:BAAANQADCgYIBwAAAA==.',
Wh='Whybebabo:BAAANQAECgMIAwAAAA==.',
Wi='Wiccawitch:BAAANQADCgYIEwAAAA==.Wirhl:BAABNQAECn84AAIIAAoK2g20YgABAgAIAAoK2g20YgABAgAAAA==.',
Wo='Worthatry:BAACNQAFFH8KAAIBAAUKORlDEwDrAAABAAUKORlDEwDrAAA1AAQKfzQAAgEACgo0IhgsABcDAAEACgo0IhgsABcDAAAA.',
Xa='Xalbit:BAABNQAECn8vAAIDAAkK/QYpfQA7AQADAAkK/QYpfQA7AQAAAA==.Xanae:BAAANQAECgcIDAAAAA==.Xantia:BAABNQAECn9IAAIVAAoKgxIKIgDoAQAVAAoKgxIKIgDoAQAAAA==.',
Xe='Xenlo:BAAANQAECgYICgAAAA==.',
Yo='Yogurt:BAAANQAECgMIAwAAAA==.',
Za='Zaizel:BAAANQAECgEIAQABNQAFFAcIFwAmAHgSAA==.Zalulu:BAAANQAECgMIAwABNQAECgQIBwAJAAAAAA==.Zathennyx:BAAANQAECgMIAwABNQAECgQIAwAJAAAAAA==.',
Ze='Zenpai:BAAANQAECgcIDgAAAA==.',
Zv='Zvorunalotus:BAAANQADCgYIDQAAAA==.',
['Ðr']='Ðread:BAAANQAECgcIDgAAAA==.',
['ßß']='ßßqñüt:BAABNQAECn8yAAIFAAoKnwxHGgDKAQAFAAoKnwxHGgDKAQAAAA==.',
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
