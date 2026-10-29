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

local lookup = {'Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Priest-Holy','Priest-Shadow','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Unknown-Unknown','Paladin-Protection','Monk-Brewmaster','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','DemonHunter-Havoc','Paladin-Holy','Mage-Fire','DeathKnight-Blood','Warrior-Fury','Warrior-Protection','Warrior-Arms','Priest-Discipline','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Hunter-Marksmanship','Druid-Feral','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Achkmed:BAAANQADCggIEQAAAA==.',
Ad='Adelaid:BAAANQAECgEIAQABNQAFFAcIFQABAJoPAA==.',
Ae='Aethelle:BAAANQAECgEIAQAAAA==.',
Ak='Akalon:BAABNQAECn9IAAICAAoKsA/XJwDGAQACAAoKsA/XJwDGAQAAAA==.',
Al='Aleckzander:BAAANQAECgMIBAABNQAECgkJKwADABglAA==.Alexandrìte:BAAANQADCgcIEQAAAA==.Allfrost:BAAANQAECgQIBwAAAA==.Altscale:BAAANQAECgYIDAAAAA==.Aluda:BAABNQAECn8nAAMEAAcKKRdHRQCcAQAEAAYKFxdHRQCcAQAFAAYKTw8bQAAuAQAAAA==.',
Am='Amberina:BAAANQADCggICAAAAA==.',
An='Anùbis:BAAANQADCgIIAgAAAA==.',
Ao='Aoeina:BAABNQAECn84AAMGAAoKFBtOSwDPAQAGAAoKvxhOSwDPAQAHAAIKiBtgGgCeAAAAAA==.',
Ap='Apollo:BAABNQAECn8rAAIIAAkK5iV3GgCHAgAIAAkK5iV3GgCHAgAAAA==.',
Ar='Arcanelotus:BAAANQADCgIIAwAAAA==.Arctus:BAAANQADCgcIBwAAAA==.Ariaves:BAABNQAECn8XAAIFAAkKbBCvIwAVAgAFAAkKbBCvIwAVAgAAAA==.Arlind:BAAANQAECggIDAAAAA==.Artemix:BAAANQAECgQIBAAAAA==.Arthara:BAAANQABCgQIBwAAAA==.',
As='Askeral:BAAANQAECgEIAgAAAA==.Astelana:BAABNQAECn8mAAIBAAcKuwe1uwDkAAABAAcKuwe1uwDkAAAAAA==.',
At='Atanatari:BAAANQAECgUIBQABNQAECgkJHgAFACgFAA==.Athennah:BAAANQADCgQIBAAAAA==.',
Ba='Bannar:BAAANQAECgYIBgAAAA==.Bassotan:BAABNQAECn8YAAIBAAkKawqb1AByAQABAAkKawqb1AByAQAAAA==.Baticus:BAAANQAECgEIAwAAAA==.',
Be='Beleva:BAAANQAECgIIBwAAAA==.Belias:BAAANQAECgQICgAAAA==.Bezzaj:BAAANQAFFAIIAgABNQAFFAcIGgAGABgSAA==.',
Bj='Bjornagain:BAAANQAECgUIDgAAAA==.Björne:BAAANQADCggIFAAAAA==.',
Bl='Blackendmoon:BAABNQAECn8nAAMJAAgKLAfiSQDuAAAJAAgKfwbiSQDuAAAKAAIKdQioygBXAAAAAA==.Blackløtus:BAAANQAECggIEQAAAA==.Bloodedge:BAAANQAECgYIEAAAAA==.Bloodklaat:BAAANQAECgUIBQAAAA==.Bloodnight:BAABNQAECn8bAAIBAAkK1w/nsQC7AQABAAkK1w/nsQC7AQAAAA==.Bluebubbles:BAAANQAECgEIAQAAAA==.Bluéyes:BAAANQAECgYIDwAAAA==.Blvckscvl:BAABNQAECn8lAAIIAAoK+BtgKQDzAgAIAAoK+BtgKQDzAgAAAA==.Blynna:BAAANQADCgYICQAAAA==.',
Br='Brannik:BAABNQAECn8WAAMLAAcKoQzKJwDTAAALAAcKoQzKJwDTAAAMAAEKmQPDoAApAAAAAA==.Breña:BAAANQADCggIGAAAAA==.Broadleaf:BAAANQAECgUICwAAAA==.',
Ca='Camiliana:BAAANQADCgUIBQAAAA==.',
Ce='Cellulight:BAABNQAECn8mAAINAAoKbhi4DQCKAgANAAoKbhi4DQCKAgAAAA==.',
Ch='Charizard:BAAANQAECgcIGgAAAQ==.Chelais:BAAANQAECggICgABNQABCgIIAgAOAAAAAA==.Cherrycola:BAAANQAECgQICgAAAA==.Chobits:BAAANQAECgQIBQAAAA==.',
Co='Coppertopp:BAAANQADCgQJBQAAAA==.Corvany:BAAANQAECgUIDgAAAA==.',
Cr='Crawley:BAABNQAECn9nAAILAAoKVR3kBAB5AgALAAoKVR3kBAB5AgAAAA==.Crazalulla:BAAANQADCggIFgAAAA==.Creeder:BAABNQAECn8fAAIBAAkK1gwNqwDJAQABAAkK1gwNqwDJAQAAAA==.Crixus:BAAANQAECgUIDQAAAA==.',
Da='Dagoland:BAAANQADCggIBQAAAA==.Daij:BAAANQADCgUIBQAAAA==.Dainty:BAAANQAECgIIAwABNQAFFAcIEgAIAG0WAA==.Damartrius:BAAANQAECgEIAQAAAA==.',
De='Deaanor:BAAANQAECgMIBAAAAA==.Deathcòw:BAAANQAECgYIDgAAAA==.Deween:BAABNQAECn8WAAMBAAgKHhOJ9gAwAQABAAgKHhOJ9gAwAQAPAAEKAABnXAAAAAAAAA==.Deyedara:BAAANQAECgEIAQAAAA==.',
Di='Diamond:BAAANQAECgIIAgAAAA==.Dionysuz:BAAANQAECggIEQAAAA==.Disdekay:BAAANQAECgMIAgABNQAECggIDgAOAAAAAA==.',
Do='Dojoro:BAABNQAECn8fAAIQAAgKYRB3DAD+AAAQAAgKYRB3DAD+AAAAAA==.Dorc:BAAANQADCgMIAwAAAA==.Dotsarelocks:BAABNQAECn8cAAQRAAkKrxOvBQB9AQARAAgK0xKvBQB9AQASAAEKAADTZwBSAAATAAMKoxLr1ABPAAAAAA==.',
Dr='Dradyos:BAAANQAECgYIDwAAAA==.Draegare:BAAANQAFFAEIAQAAAA==.Drdeer:BAAANQADCgUIBgAAAA==.Drewarel:BAAANQAECgQIBAABNQAECgcIFgAHAFYCAA==.',
Ee='Eelecurb:BAAANQADCggIDwAAAA==.',
Ei='Eisysae:BAAANQABCgIJAwAAAA==.',
El='Eliard:BAAANQAECgEIAQAAAA==.Ellå:BAAANQAECgUICAABNQAECgoKQgAEAJ0iAA==.',
Er='Erisynn:BAEANQADCgUIBQABNQAFFAUICQAUAJkDAA==.',
Et='Eternalx:BAAANQAECgEIAQAAAA==.',
Ev='Evang:BAABNQAECn8kAAIIAAcKqwtWgQAwAQAIAAcKqwtWgQAwAQAAAA==.Everd:BAABNQAECn8kAAIBAAcKpgmO4QBYAQABAAcKpgmO4QBYAQAAAA==.',
Fi='Fiametta:BAABNQAECn8sAAISAAkKDxcTBABtAQASAAkKDxcTBABtAQAAAA==.Firerain:BAAANQADCggIEQAAAA==.',
Fl='Flameward:BAAANQADCgYIBgAAAA==.Flippi:BAAANQABCgYICAAAAA==.',
Fo='Forkingidiot:BAAANQAECgQIBQAAAA==.Forodin:BAAANQADCgYIBgABNQADCggIFAAOAAAAAA==.Foxymizzy:BAAANQAECgQIBQABNQAECgkJIQAVAGsdAA==.',
Fr='Freadrick:BAAANQADCgEIAQABNQADCggIFAAOAAAAAA==.Frostknight:BAAANQAECgYICAAAAA==.',
Fu='Funsize:BAABNQAECn9CAAIEAAoKnSJABwBsAwAEAAoKnSJABwBsAwAAAA==.',
Ga='Gardek:BAAANQAECggIAQAAAA==.Gazzlok:BAAANQAECgEIAQAAAA==.',
Ge='Gesen:BAAANQADCggIFQAAAA==.',
Gl='Global:BAAANQABCgcICgABNQAECgkJHgAWAAkYAA==.Gloriance:BAABNQAECn8kAAITAAcKHRjcWABYAQATAAcKHRjcWABYAQAAAA==.',
Go='Gondra:BAAANQABCgIIBAABNQAECgUIDgAOAAAAAA==.Gortalon:BAAANQABCgIIAgAAAA==.',
Ha='Haplo:BAAANQAECgIIBgABNQAECgQIBQAOAAAAAA==.',
He='Hellmet:BAAANQAECgIJAwAAAQ==.Hey:BAACNQAFFH8IAAMCAAMKvgLPHgC/AAACAAMKvgLPHgC/AAADAAIKGRnRHABWAAA1AAQKfygAAwMACgr4IMsfAOsCAAMACQpLIMsfAOsCAAIACApXCZdjAOIAAAAA.',
Hi='Hinamori:BAAANQAECgMIBQAAAA==.',
Ho='Holythot:BAAANQAECgIIAwABNQAFFAYIGwAXANEcAA==.',
Hu='Huogmi:BAAANQAECgQICAAAAA==.',
Il='Ilharra:BAAANQAECgQIDgAAAA==.Ilililili:BAAANQAECgMIBwAAAA==.Illee:BAABNQAECn8fAAIGAAkK7w1P0QDkAQAGAAkK7w1P0QDkAQAAAA==.',
Im='Impgangpimp:BAEBNQAECn8qAAITAAoKLR5wGABsAgATAAoKLR5wGABsAgAAAA==.Imturtle:BAABNQAECn88AAIXAAoKxiHCBwDXAgAXAAoKxiHCBwDXAgABNQAFFAMIBQATAKEQAA==.',
Ir='Irmis:BAABNQAECn8eAAMYAAoK1ho+BgDdAQAYAAkKUhY+BgDdAQAZAAgKZhpWDwBBAQAAAA==.',
It='Ithrynluin:BAAANQAECgQIBAABNQAECgkJHgAFACgFAA==.',
Iu='Iupiter:BAAANQAECggIDwAAAA==.',
Iy='Iyahlieairia:BAAANQAECgMIBgAAAA==.',
Iz='Izabeth:BAABNQAECn8iAAMHAAgKFA0QEgCFAQAHAAgKFA0QEgCFAQAGAAEKQgLW1QErAAAAAA==.',
Ja='Jamella:BAABNQAECn8uAAMBAAkKQhOHmQDwAQABAAcKQxiHmQDwAQAVAAkKXw28RwB3AQAAAA==.',
Je='Jesüschrist:BAAANQAECgIIAwAAAA==.',
Ji='Jiglestd:BAAANQAECgEIAQAAAA==.',
Jo='Jové:BAAANQAECgEIAgAAAA==.',
Ju='Judeath:BAAANQABCggICQABNQADCggIGAAOAAAAAA==.',
Ka='Kabocha:BAAANQAECgcIEAAAAA==.Katsa:BAAANQAECgIIAgAAAA==.Kawi:BAAANQABCgIIAwAAAA==.Kayeh:BAAANQADCgIIAgAAAA==.',
Ki='Kiraneem:BAABNQAECn8pAAIIAAgK5hziYQBSAgAIAAgK5hziYQBSAgAAAA==.Kittie:BAABNQAECn86AAIDAAoKzRWqRgBHAgADAAoKzRWqRgBHAgAAAA==.Kittynip:BAAANQADCgQIBAABNQAECgQIBgAOAAAAAA==.',
Kr='Krinj:BAABNQAECn8fAAMJAAkKXh2FHwCPAgAJAAkKXh2FHwCPAgAKAAEKOQsF4AA0AAAAAA==.Kristov:BAAANQAECgcICQAAAA==.',
Kt='Ktariani:BAAANQADCgYICgAAAA==.',
Ky='Kyarla:BAABNQAECn8XAAIEAAYKuwozqgAXAQAEAAYKuwozqgAXAQAAAA==.Kyden:BAAANQADCgEIAQAAAA==.',
La='Lazulie:BAAANQAECgEIAQAAAA==.',
Le='Leahim:BAABNQAECn9yAAIXAAoK6CNaBAAcAwAXAAoK6CNaBAAcAwAAAA==.Ledani:BAABNQAECn8zAAMEAAoKoxZpbQDWAQAEAAYKGRxpbQDWAQAFAAoKiQ2vEADCAQAAAA==.Leonato:BAAANQADCgEIAQAAAA==.',
Li='Light:BAAANQADCggICAAAAA==.Lilbulky:BAAANQAECgYIBwABNQAECggIHgAaAAIaAA==.Liriels:BAAANQAECgQIBQAAAA==.',
Lo='Lohith:BAABNQAECn8fAAIDAAkKDQVtjwBiAQADAAkKDQVtjwBiAQAAAA==.Lonedawg:BAAANQAECgQICwAAAA==.Lourival:BAAANQAECgQJBAAAAA==.Lovécoil:BAABNQAECn8YAAIKAAkK3BvJEAAUAgAKAAkK3BvJEAAUAgAAAA==.',
Lu='Lunâ:BAABNQAECn8WAAMbAAcKoxRkDQBdAQAEAAcKRhNrfQChAQAbAAcKvQxkDQBdAQAAAA==.',
['Lë']='Lëw:BAAANQAECgYIDQAAAA==.',
Ma='Mageofthe:BAAANQADCgUICAAAAA==.Maggnolya:BAAANQAECgYICgAAAA==.Marsyx:BAABNQAECn8fAAIEAAkKvRvSKgC+AgAEAAkKvRvSKgC+AgAAAA==.Matidan:BAABNQAECn8YAAIcAAgK0BQCKAAEAgAcAAgK0BQCKAAEAgAAAA==.Mayael:BAABNQAECn8lAAMKAAkKrRomLQB/AgAKAAkKrRomLQB/AgAJAAcKuA8dUABzAQAAAA==.',
Me='Medreaux:BAABNQAECn90AAMEAAoKiSJmBgCTAwAEAAoKiSJmBgCTAwAFAAEKdgADmQACAAAAAA==.Merrei:BAABNQAECn8iAAMUAAgKoBTiMwANAgAUAAgKoBTiMwANAgAdAAYKHwlvGAAqAQAAAA==.Meta:BAAANQADCggICAABNQAECgkJHwAXABcVAA==.Metalknyte:BAABNQAECn8qAAMXAAgK7xAnLgA3AQAXAAgK7xAnLgA3AQAKAAEKAAC+hQAAAAAAAA==.',
Mi='Miniknyte:BAABNQAECn80AAMeAAoKlBv9BQAPAwAeAAoKlBv9BQAPAwAfAAEKAABVyQAZAAAAAA==.',
Mo='Mohu:BAAANQADCgcIBwAAAA==.Monkey:BAAANQADCgcICgAAAA==.Moonsz:BAAANQADCggINwAAAA==.Mooseonloose:BAABNQAECn8XAAQKAAoKmRKfNQBRAgAKAAkK9xSfNQBRAgAJAAYKYQpyVgDAAAAXAAEKAACQxwA5AAAAAA==.Morandus:BAAANQAECgEIAQAAAA==.Moraria:BAAANQADCgMIAwAAAA==.Morgrathh:BAAANQAECgEIAQAAAA==.',
My='Mychelle:BAABNQAECn8mAAIgAAkK7gkRHAAgAQAgAAkK7gkRHAAgAQAAAA==.',
['Më']='Më:BAAANQAFFAIIAgABNQAECgkJGgAFAIwVAA==.',
Na='Nakryn:BAABNQAECn8XAAMHAAkKygJGJADLAAAGAAgKpgKLWgH7AAAHAAYKLwJGJADLAAAAAA==.Naryeth:BAAANQADCgEIAQAAAA==.Natorn:BAABNQAECn8fAAIaAAkKeCHeJAAlAwAaAAkKeCHeJAAlAwAAAA==.Nay:BAAANQAECgcJCQAAAA==.',
Ne='Nemrod:BAAANQAECgEIAQAAAA==.Neuwby:BAAANQAECgEIAQAAAA==.Nezum:BAAANQAECgEIAQAAAA==.',
Ni='Nickoli:BAAANQAECgEIAgAAAA==.Niterend:BAABNQAECn8eAAIaAAgKAhq5fgAeAgAaAAgKAhq5fgAeAgAAAA==.',
No='Nojomoto:BAAANQADCgcIBwAAAA==.Norabel:BAAANQADCgQICAAAAA==.',
Nu='Nugehuts:BAABNQAFFH8GAAIXAAQK2x1ODwCrAAAXAAQK2x1ODwCrAAABNQAFFAkJMQATANAmAA==.',
['Nø']='Nøxxi:BAABNQAECn8vAAMSAAoKphdqCgBQAgASAAgKtBtqCgBQAgATAAoKtQrLOgC+AQAAAA==.',
Ob='Obbimcanood:BAAANQADCgIIAgAAAA==.',
Ok='Okbloomer:BAAANQAECggIEQABNQAFFAcIEQAEALMXAA==.',
Ol='Oldben:BAABNQAECn8xAAMBAAoKig4bYgCVAQABAAoKig4bYgCVAQAPAAMK5gDHawA7AAAAAA==.',
Or='Oriel:BAABNQAECn8pAAIbAAgKbgjlBABFAQAbAAgKbgjlBABFAQAAAA==.',
Ov='Ovy:BAAANQAECgEIAgAAAA==.',
Ow='Owbunk:BAAANQAECgEIAQAAAA==.',
Pa='Paleblueeye:BAAANQAECgEIAwAAAA==.Panda:BAAANQAECgMIAwAAAA==.',
Pi='Pixystix:BAAANQADCgYIDAABNQAECgkJJgAgAO4JAA==.',
Pl='Plop:BAAANQAECgQIBAABNQAECgkJHgAWAAkYAA==.Plumpcheeks:BAAANQAECgEIAwAAAA==.',
Po='Poc:BAABNQAECn8gAAMhAAcKfgrwHAA5AQAhAAcKMwnwHAA5AQANAAEKfQ36TgA4AAAAAA==.Poundya:BAAANQADCgYICgAAAA==.',
Pr='Priblet:BAAANQAECgUICQAAAA==.Prinsana:BAABNQAECn8pAAIPAAgK0xE6JQC2AQAPAAgK0xE6JQC2AQAAAA==.',
Pu='Purquis:BAABNQAECn8YAAIfAAkKVQpDKgA4AQAfAAkKVQpDKgA4AQAAAA==.',
Ra='Raeve:BAAANQADCgYIBgAAAA==.Raidkicker:BAAANQADCgEIAQABNQAECgkJHAARAK8TAA==.',
Re='Reaperlord:BAABNQAECn8nAAIVAAcKCh/mKAAMAgAVAAcKCh/mKAAMAgAAAA==.',
Ri='Rizzardofoz:BAAANQADCgMIAwAAAA==.',
Rl='Rllybuffnerd:BAAANQAECggICgAAAA==.',
Ro='Rodikus:BAABNQAECn82AAMEAAoKziAmIADvAgAEAAoKziAmIADvAgAFAAMKFw/GNAB7AAAAAA==.',
Sa='Saeryan:BAAANQADCggICAAAAA==.Saiaa:BAABNQAECn8hAAILAAgKXwVTWwBKAQALAAgKXwVTWwBKAQAAAA==.Sakeena:BAAANQAECgQICwAAAA==.Samará:BAAANQADCgQICAAAAA==.Sarleigh:BAAANQADCgIIAgAAAA==.Sattia:BAAANQAECgYIDgAAAA==.',
Sh='Shabloink:BAAANQAECgEIAQAAAA==.Shadereaver:BAAANQAECggIDQAAAA==.Shenanygins:BAAANQADCgMIAwAAAA==.Shendalla:BAAANQAECgEIAQAAAA==.Shinokishi:BAABNQAECn8hAAIXAAcKMA/VPADvAAAXAAcKMA/VPADvAAAAAA==.',
Si='Silentninjaa:BAABNQAECn8vAAIYAAoKZRC7CACLAQAYAAoKZRC7CACLAQAAAA==.Simphunter:BAEBNQAECn8cAAIcAAoK+hTDIABGAgAcAAoK+hTDIABGAgABNQAECgoKKgATAC0eAA==.Sinfel:BAABNQAECn8iAAMUAAkKkgdSPwDNAAAUAAkKOwdSPwDNAAAdAAUKZQW0KgBeAAAAAA==.Sit:BAAANQAECgEIAQAAAA==.',
Sk='Skoriavis:BAAANQAECgEIAgABNQAECgcIHQAMADUZAA==.Skoriko:BAABNQAECn8dAAMMAAcKNRn6FgAoAgAMAAcKNRn6FgAoAgALAAMK2gwbhgCaAAAAAA==.',
Sl='Slürmp:BAAANQAECgEIAQABNQAECgcIEgAOAAAAAA==.',
Sn='Snowcones:BAAANQADCgUIBQAAAA==.',
So='Sonett:BAAANQAECgIIBAAAAA==.Sonto:BAAANQAECgUICwAAAA==.',
Sp='Sparks:BAAANQAECggICAAAAA==.Splunk:BAABNQAECn8fAAIXAAkKFxWyOAAkAgAXAAkKFxWyOAAkAgAAAA==.',
St='Staggerdaddy:BAAANQAECgQIBgAAAA==.Stariya:BAAANQAECgQICwAAAA==.Stompinghoof:BAAANQAECgYICQAAAA==.Strapattack:BAAANQADCggIDwAAAA==.Strawyà:BAABNQAECn8oAAMiAAoKTA1LEgDBAQAiAAoKTA1LEgDBAQAjAAEKWAUXUQAnAAAAAA==.',
Sy='Syananta:BAAANQADCggICAABNQAECgQIBgAOAAAAAA==.Syannara:BAAANQAECgQIBgAAAA==.Syklar:BAAANQADCgEIAQAAAA==.Syssa:BAABNQAECn8bAAIEAAYKuRwfRwCUAQAEAAYKuRwfRwCUAQABNQAECgYIGQAEAAcTAA==.',
['Sì']='Sìrocco:BAAANQAECgYIDgAAAA==.',
Ta='Taleranor:BAAANQAECgcIDgAAAA==.Tamerizer:BAABNQAECn8jAAIgAAkK3w8AMADNAQAgAAkK3w8AMADNAQAAAA==.',
Te='Tealera:BAAANQAECgQIBAAAAA==.Tearali:BAAANQADCggICAAAAA==.Teejrath:BAABNQAECn8bAAQKAAkKVA/EWwChAQAKAAgKFhDEWwChAQAJAAEKzgqktAArAAAXAAEKAAB24AAeAAAAAA==.Teekeez:BAAANQADCggICQAAAA==.',
Th='Thekal:BAAANQADCgEIAgAAAA==.Theodorel:BAAANQAECgEIAQAAAA==.Thicchick:BAAANQAECgYIDwAAAA==.Thirge:BAABNQAECn8bAAIYAAYK0Q6SFQBDAQAYAAYK0Q6SFQBDAQAAAA==.Thorek:BAAANQADCggIDwAAAA==.Thrushbeard:BAAANQADCgcIBwAAAA==.Thundertaco:BAABNQAECn8aAAICAAYKMQt4oQBTAQACAAYKMQt4oQBTAQAAAA==.',
Ti='Tighten:BAAANQABCgEIAQAAAA==.',
To='Toesniffer:BAAANQADCggICAAAAA==.Tofaaway:BAAANQAECgQICwAAAA==.Tolak:BAAANQAECgYIEwAAAA==.Tormikinos:BAABNQAECn8kAAIfAAcKvwlCOQDjAAAfAAcKvwlCOQDjAAAAAA==.Torturousôwl:BAABNQAECn8YAAMEAAcK7xKFWgBKAQAEAAcK7xKFWgBKAQAbAAEK3AXeLwAlAAAAAA==.Totemknyte:BAAANQABCgUIBQABNQAECggIKgAXAO8QAA==.',
Tr='Trapology:BAAANQAECgEIAgAAAA==.Trillianh:BAAANQADCgEIAQAAAA==.Trisky:BAABNQAECn8nAAMVAAkKYBodNQCPAgAVAAkKYBodNQCPAgAPAAEKMw+CdQAnAAAAAA==.',
Tu='Tumblebumble:BAAANQADCgMIAwAAAA==.Turtle:BAACNQAFFH8FAAITAAMKoRAZDgDkAAATAAMKoRAZDgDkAAA1AAQKf0cAAxMACgq0HkcjAC0CABMACQq9HUcjAC0CABIAAgp6E4pPAJEAAAAA.',
Va='Vadrakquin:BAAANQAECggIEAAAAA==.Valshamommy:BAABNQAECn8kAAIkAAoKPhKVEwAvAgAkAAoKPhKVEwAvAgAAAA==.Vanloth:BAAANQADCgEIAgAAAA==.Vantadim:BAAANQAECgQIBAAAAA==.',
Ve='Vegito:BAAANQAECgIIBwAAAA==.Velfurry:BAAANQAECgEIAQABNQAFFAgIJQAlAGMMAA==.Verlassan:BAAANQADCgcIBwAAAA==.',
Vi='Viverrid:BAAANQAECgEIBAAAAA==.',
Vo='Voinwar:BAACNQAFFH8JAAIZAAQKEhgFAgDSAAAZAAQKEhgFAgDSAAA1AAQKf0AAAhkACgqxJKABALIDABkACgqxJKABALIDAAAA.Vorpine:BAABNQAECn8tAAMEAAoKchUShACLAQAEAAgKfxQShACLAQAFAAoKvhBcFQB4AQAAAA==.',
We='Wetkittie:BAAANQADCgYIBwAAAA==.',
Wh='Whybebabo:BAAANQAECgMIAwAAAA==.',
Wi='Wiccawitch:BAAANQADCgYIEwAAAA==.Windbottom:BAAANQAECgEIAQAAAA==.Wirhl:BAABNQAECn8gAAIIAAkKnA1+RwDIAQAIAAkKnA1+RwDIAQAAAA==.',
Wo='Worthatry:BAABNQAECn8tAAIBAAoKCyIYLAAXAwABAAoKCyIYLAAXAwAAAA==.',
Xa='Xalbit:BAABNQAECn8mAAIDAAcKwgR2cADsAAADAAcKwgR2cADsAAAAAA==.Xantia:BAABNQAECn89AAIeAAoK/RHZEgD5AQAeAAoK/RHZEgD5AQAAAA==.',
Xe='Xenlo:BAAANQAECgYICgAAAA==.',
Yo='Yogurt:BAAANQAECgEIAQABNQAECgIJAwAOAAAAAA==.',
Za='Zaizel:BAAANQAECgEIAQABNQAFFAcIFwAmAHgSAA==.Zalulu:BAAANQAECgMIAwABNQAECgQICQAOAAAAAA==.Zathennyx:BAAANQAECgMIAwABNQAECgQIBAAOAAAAAA==.',
Ze='Zenpai:BAAANQAECgcIEQAAAA==.',
['Ðr']='Ðread:BAAANQAECgYIDgAAAA==.',
['ßß']='ßßqñüt:BAABNQAECn8aAAIFAAcKdwl0QwAZAQAFAAcKdwl0QwAZAQAAAA==.',
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
