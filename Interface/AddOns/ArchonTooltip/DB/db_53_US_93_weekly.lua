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

local lookup = {'Priest-Holy','Hunter-BeastMastery','Warrior-Fury','Warrior-Protection','Warrior-Arms','Priest-Shadow','Unknown-Unknown','Paladin-Holy','Hunter-Survival','Mage-Arcane','Hunter-Marksmanship','Shaman-Elemental','Mage-Frost','Druid-Restoration','Druid-Balance','DeathKnight-Unholy','Mage-Fire','Druid-Guardian','Paladin-Retribution','Warlock-Destruction','Shaman-Restoration','DemonHunter-Vengeance','Rogue-Assassination','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Blood','DeathKnight-Frost','Paladin-Protection','Shaman-Enhancement','Warlock-Affliction','Warlock-Demonology','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Farstriders',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Aberren:BAAANQAECgMIAgAAAA==.Absolon:BAAANQAECgUICgAAAA==.',
Ad='Adinirin:BAAANQADCgMIAwAAAA==.',
Ae='Aellynn:BAABNQAECn8hAAIBAAoKnA2FewCnAQABAAoKnA2FewCnAQAAAA==.Aerir:BAAANQAECgIIAgABNQAFFAUICAACAMoJAA==.',
Ag='Aggar:BAABNQAFFH8NAAICAAUKhyTABwBCAQACAAUKhyTABwBCAQAAAA==.',
Ak='Akinom:BAAANQADCgUIEAAAAA==.',
Al='Alltheheals:BAABNQAECn8dAAIBAAoK4ResNgCNAgABAAoK4ResNgCNAgAAAA==.Alysana:BAAANQADCgQIBAAAAA==.',
Am='Amarawyn:BAABNQAECn8cAAMDAAYKZgmwGAC2AAADAAYKZgmwGAC2AAAEAAIKwAQkQAA/AAAAAA==.Amoonfalar:BAAANQAECgEIAQAAAA==.Amoradrac:BAAANQADCgYIBwAAAA==.Amoragan:BAABNQAECn8cAAMEAAkKSRedDwAwAgAEAAgKuhadDwAwAgAFAAIKphoQ/ABPAAAAAA==.Amoratan:BAAANQAECgYIBgAAAA==.',
An='Anaren:BAAANQAECgEIAQAAAA==.Andriela:BAAANQADCgYIBgAAAA==.',
Ap='Apexy:BAAANQAECgUIBAAAAA==.',
Ar='Arashikaze:BAAANQAECgUICwAAAA==.Areadhel:BAAANQADCgQIBAAAAA==.Arianffwr:BAAANQADCgQIBAAAAA==.',
As='Asclepius:BAAANQAECgUIBAAAAA==.Asurion:BAAANQADCgIIBQAAAA==.',
At='Atlantis:BAAANQAFFAIIAgABNQAFFAgIHQABAGYhAA==.',
Au='Augidget:BAABNQAECn8vAAIGAAoK3BX0EAASAgAGAAoK3BX0EAASAgAAAA==.',
Av='Avilen:BAAANQAECgQICQAAAA==.',
Ba='Bachar:BAAANQADCgEIAQABNQAECgYIBgAHAAAAAA==.Balinteen:BAAANQAECgUICgAAAA==.Bastael:BAABNQAECn8kAAIIAAoK+B/YCwBIAwAIAAoK+B/YCwBIAwAAAA==.Bayus:BAAANQADCgMIAgAAAA==.',
Be='Berone:BAAANQADCgQIBAAAAA==.Beryrn:BAAANQADCgIIAgAAAA==.',
Bi='Biopainr:BAAANQADCggJIAAAAA==.Bitxi:BAAANQAECgUIBAAAAA==.',
Bl='Bloodtusk:BAAANQAECgQIBgAAAA==.',
Bo='Bob:BAAANQADCgYIBgAAAA==.Boldbane:BAAANQAECgYICQAAAA==.Boraimhe:BAAANQADCgEIAQAAAA==.',
Br='Brandalin:BAAANQADCggIDgABNQAECgQICAAHAAAAAA==.Brax:BAABNQAECn8dAAMEAAcKWRxkGACpAQAEAAUKaiJkGACpAQADAAYKLg+6EQAbAQAAAA==.',
Bu='Bunyan:BAAANQADCgEIAQAAAA==.Burda:BAABNQAECn8qAAIJAAoKwxZIBAClAgAJAAoKwxZIBAClAgAAAA==.Buttspanker:BAAANQADCggIKAAAAA==.Buzzle:BAAANQADCgEIAgAAAA==.',
Ca='Caenae:BAABNQAECn8WAAICAAYK9AYFywDXAAACAAYK9AYFywDXAAAAAA==.Cakes:BAAANQADCgMIAwAAAA==.Candilwyn:BAAANQADCgEIAQAAAA==.Cattlerage:BAAANQAECggIDQAAAA==.',
Ch='Chrissy:BAAANQADCgEIAgAAAA==.',
Ci='Ciannie:BAAANQADCgQIBAAAAA==.',
Co='Condar:BAAANQADCgIIBAAAAA==.Corri:BAAANQAECgYIDAAAAA==.',
Cr='Credon:BAAANQAECgQIBgAAAA==.',
Cy='Cybedru:BAAANQADCgQIBAAAAA==.',
Da='Davin:BAAANQADCgUIAQAAAA==.',
De='Dethdeej:BAAANQAFFAEIAQAAAA==.Dethrage:BAAANQAECggIAQAAAA==.Dezire:BAAANQADCgEIAQAAAA==.',
Dh='Dhrimr:BAAANQAECgMICQAAAA==.',
Di='Dieceptionz:BAAANQADCggICgAAAA==.Dierlyn:BAABNQAECn8cAAIBAAYKWxVYbABbAQABAAYKWxVYbABbAQAAAA==.Dimir:BAABNQAECn8nAAIEAAkKoBwFCAAqAgAEAAkKoBwFCAAqAgAAAA==.Dirtytaters:BAAANQAECgUIBAAAAA==.Divastating:BAABNQAECn8fAAICAAYK7AQe0gDJAAACAAYK7AQe0gDJAAAAAA==.',
Do='Doró:BAAANQAECgIIBAABNQAECgoKHgAKAH4VAA==.',
Dr='Dragonberry:BAAANQAECgcIEAAAAA==.',
Dt='Dtothed:BAAANQAECgYICQABNQAECgoKTgALAEAgAA==.',
Du='Duckyme:BAAANQADCgMIAwAAAA==.',
Dw='Dwaleen:BAAANQAECgQIBAAAAA==.Dwarfred:BAABNQAECn8aAAIMAAYKMRLxqwA8AQAMAAYKMRLxqwA8AQAAAA==.',
['Dò']='Dòro:BAABNQAECn8eAAMKAAoKfhXJnABHAgAKAAoKfhXJnABHAgANAAEK4wf9UAAlAAAAAA==.',
El='Elasong:BAAANQAECgUIBQAAAA==.Elletal:BAACNQAFFH8HAAIOAAQKXxF3CAAZAQAOAAQKXxF3CAAZAQA1AAQKfxsAAw4ACArkE0UtALIBAA4ACArkE0UtALIBAA8AAwohCBpeAIAAAAAA.Elloria:BAAANQADCgUIBQAAAA==.Elybria:BAAANQADCgEIAQAAAA==.',
Eo='Eosphoros:BAAANQADCgEIAQAAAA==.',
Er='Erkil:BAAANQAECgYIBAAAAA==.Erythnull:BAAANQADCgEIAQAAAA==.',
Ey='Eychen:BAAANQADCgEIAQABNQAECgcICgAHAAAAAA==.',
Fa='Fayona:BAAANQADCgIJAgAAAA==.',
Fi='Figbe:BAAANQAECgUJBQABNQAFFAcIFwAFAHAgAA==.Fizzlyn:BAACNQAFFH8KAAIQAAUKYxJZBgDjAAAQAAUKYxJZBgDjAAA1AAQKfyIAAhAACgr4Hb0pAJECABAACgr4Hb0pAJECAAAA.',
Fl='Flaren:BAAANQAECgYIBwAAAA==.',
Fu='Furybutt:BAAANQAECgIIAQABNQAECgoKIQARAI0lAA==.',
Ga='Galedriel:BAAANQADCgEIAQAAAA==.',
Ge='Gereleron:BAAANQADCgQJBAAAAA==.',
Gr='Grewsöm:BAAANQAECgcICgABNQAECggIDQAHAAAAAA==.Grizzlegom:BAAANQADCgcIEgABNQAECgoKTgALAEAgAA==.Grotusque:BAABNQAECn81AAMSAAkKeRR2HwCiAQASAAcKMBd2HwCiAQAPAAIKrw2oZABsAAAAAA==.',
Ha='Haerin:BAAANQADCgQIBAAAAA==.Halieyy:BAAANQABCgcIBwAAAA==.Hardim:BAAANQADCgcJBwAAAA==.Hardwood:BAAANQADCgYIBgAAAA==.Harknesse:BAAANQAECgUIBAAAAA==.Hawthorn:BAAANQADCgQIBAABNQAECgcIEAAHAAAAAA==.Haxxis:BAAANQAECgUIDQAAAA==.',
He='Healingways:BAAANQADCgUICQAAAA==.Heezee:BAABNQAECn8WAAICAAkKYQ5DcgCSAQACAAkKYQ5DcgCSAQAAAA==.Heftypaw:BAAANQADCggIFwAAAA==.Helliglys:BAAANQADCgMIAwAAAA==.Hextor:BAAANQAECgQICAAAAA==.',
Hi='Hickorie:BAAANQADCgMIAwAAAA==.Hielo:BAAANQADCgQIBAAAAA==.',
Ho='Hog:BAABNQAECn8WAAIMAAoKvR3dKgDUAgAMAAoKvR3dKgDUAgABNQAECgoKTAAEAK0mAA==.Holyboy:BAABNQAECn8aAAITAAYKNQ6E6ADTAAATAAYKNQ6E6ADTAAAAAA==.Honeybunz:BAAANQAECgEIAQAAAA==.Horizontal:BAAANQADCgEIAQABNQAECgkJFAAJAJUMAA==.',
Hr='Hranu:BAABNQAECn8mAAIOAAoKxhqrCgDnAgAOAAoKxhqrCgDnAgAAAA==.',
Hu='Husker:BAAANQADCgcIBwAAAA==.',
Hy='Hydraulicman:BAAANQADCgQIBwAAAA==.',
In='Inenwe:BAAANQADCgQIBAAAAA==.Invinciboi:BAAANQADCggICAABNQAECgoKMAAIAJUUAA==.',
Ir='Ironwind:BAAANQADCgMIAwAAAA==.',
Ja='Jasmirana:BAAANQAECgcIEwAAAA==.',
Je='Jemano:BAAANQADCgMIBQAAAA==.Jenal:BAAANQAECgUIBQAAAA==.Jenina:BAAANQADCgQIBAAAAA==.',
Ji='Jibbadin:BAAANQADCgIIAgABNQAECgkJHwAGAI8WAA==.Jibbzin:BAAANQADCgYIBgABNQAECgkJHwAGAI8WAA==.',
Jo='Jolage:BAAANQAECgcIDQABNQAECgoKTgALAEAgAA==.Jolreal:BAABNQAECn9OAAILAAoKQCDTCgAqAwALAAoKQCDTCgAqAwAAAA==.Jophiel:BAAANQAECgYIBgAAAA==.',
Ju='Juansbane:BAAANQADCggICQAAAA==.Julez:BAAANQAECgQIBgAAAA==.Julezara:BAAANQAECgUIEgAAAA==.Jumbledmess:BAAANQABCgMIAwAAAA==.Junkai:BAACNQAFFH8HAAITAAQK8hnHDQDwAAATAAQK8hnHDQDwAAA1AAQKfxwAAhMABgpMI2dTAPwBABMABgpMI2dTAPwBAAAA.',
Ka='Kandyman:BAAANQAECgEIAQAAAA==.Kanzashi:BAAANQADCggICAAAAA==.',
Ke='Keco:BAAANQAECgMICQABNQAECgYIHwACAOwEAA==.Kennie:BAABNQAECn8lAAIUAAoKnQuKBQBjAQAUAAoKnQuKBQBjAQAAAA==.',
Kl='Kladibo:BAABNQAECn8bAAIPAAoKZRzIFABGAgAPAAoKZRzIFABGAgAAAA==.Kladivo:BAAANQADCgYIBgABNQAECgoKGwAPAGUcAA==.Klick:BAAANQADCgYICgABNQAFFAQIBwATAPIZAA==.',
Kr='Kröwten:BAABNQAECn8jAAICAAkK4Bm9TQD0AQACAAkK4Bm9TQD0AQAAAA==.',
['Kì']='Kìlana:BAABNQAECn8mAAMVAAkKgBDSaQBEAQAVAAgK4w3SaQBEAQAMAAgK2ARDggDSAAAAAA==.',
La='Lahlania:BAAANQAECgUIAQAAAA==.Lammchop:BAAANQADCgQIBAAAAA==.Lanaki:BAACNQAFFH8IAAICAAUKyglDFADKAAACAAUKyglDFADKAAA1AAQKfysAAgIACgo1FzFQAH8CAAIACgo1FzFQAH8CAAAA.',
Li='Lionheart:BAAANQAECgQIBAABNQAECgoKMAAIAJUUAA==.Lissaelyia:BAAANQADCgEIAQAAAA==.',
Lo='Logarithmic:BAABNQAECn8UAAQJAAkKlQzNBgAgAgAJAAkKlQzNBgAgAgACAAIKYwlANQF+AAALAAEKAADkngAfAAAAAA==.',
Lu='Lunareon:BAABNQAECn8lAAIFAAgKIRC8XQCtAQAFAAgKIRC8XQCtAQAAAA==.',
Ma='Maccbeth:BAAANQAECgUICwAAAA==.Machette:BAAANQAECgUIDQABNQAECgoKTgALAEAgAA==.Mailaria:BAABNQAECn8lAAIWAAoKrxEaCQCgAQAWAAoKrxEaCQCgAQAAAA==.Maithe:BAAANQADCgMIAwAAAA==.Malamonk:BAAANQAECgEIAQAAAA==.Malvolio:BAAANQADCgEIAQAAAA==.Mambo:BAAANQADCgMIAwAAAA==.Maralucia:BAAANQADCgIIAgAAAA==.Marellaa:BAABNQAECn8VAAIBAAYKWQqLkwDmAAABAAYKWQqLkwDmAAAAAA==.Marottie:BAAANQADCgIJAgAAAA==.',
Mc='Mcsplatapus:BAAANQAECgUIDwAAAA==.',
Me='Meingsolin:BAAANQAECgUIBgABNQAECgUICgAHAAAAAA==.Methodical:BAABNQAECn8iAAIXAAoKXRNwEACfAQAXAAoKXRNwEACfAQAAAA==.',
Mi='Miggylosoh:BAAANQADCgYIBgAAAA==.',
Mo='Monkeydluffy:BAAANQADCgEIAQAAAA==.Mopa:BAAANQADCggICAAAAA==.Morfas:BAAANQADCgEIAgAAAA==.',
My='Myuk:BAABNQAECn8jAAMCAAoKRRsiJQCAAgACAAoKYhoiJQCAAgAJAAcKwBX+BwDiAQAAAA==.',
Mz='Mzskywalker:BAAANQADCgMIAwAAAA==.',
Na='Naminay:BAAANQADCgYIEQABNQAECgUIEAAHAAAAAA==.',
Ne='Nechahira:BAAANQAECgIIAgABNQAFFAYIEAAOACMNAA==.Neroz:BAABNQAECn9HAAIYAAkKlR3RGAAWAgAYAAkKlR3RGAAWAgAAAA==.Netherlight:BAAANQAECgMIAwABNQAECgUIDQAHAAAAAA==.',
Ni='Nina:BAAANQADCgYIBgAAAA==.',
Nk='Nkript:BAAANQAECgcICwAAAA==.',
Od='Odysemus:BAABNQAECn8jAAMFAAgKxBOkgQAXAgAFAAgKxBOkgQAXAgADAAEKDgodOAAnAAAAAA==.',
On='Onari:BAABNQAECn8jAAMZAAoK/Ra5DgBBAQABAAoK/RZ1VAAmAgAZAAYKxQ+5DgBBAQAAAA==.Onlyfannz:BAAANQADCggIFAAAAA==.',
Or='Orcicide:BAAANQADCgMIAwAAAA==.',
Os='Oskkar:BAAANQADCgQIBAAAAA==.',
Pa='Palara:BAAANQAECgQIBAABNQAECgoKIwAZAP0WAA==.Pandamoníum:BAAANQAECgMICwAAAA==.',
Pe='Perce:BAABNQAECn8hAAMIAAcKQRgziwB7AQAIAAYKTRYziwB7AQATAAUKpAgY6gDQAAAAAA==.',
Pf='Pfemme:BAABNQAECn8sAAICAAkKQheHYABWAgACAAkKQheHYABWAgAAAA==.',
Ph='Phalaris:BAAANQADCgIIAgAAAA==.',
Pi='Pikupchew:BAABNQAECn8rAAMVAAkK9hEeXgBsAQAVAAkK9hEeXgBsAQAMAAQKqQydogCPAAABNQAECgoKMAAIAJUUAA==.Pinball:BAAANQADCgEIAQAAAA==.Pinstripe:BAAANQADCgQIBAAAAA==.Pixie:BAAANQAECgUICAAAAA==.',
Po='Polli:BAAANQADCgEIAQAAAA==.Popcorns:BAAANQADCgIIAgAAAA==.Popcornss:BAAANQAECgIIBAAAAA==.',
Pu='Purian:BAAANQADCgIJAgAAAA==.',
Qu='Qualanthar:BAAANQADCgQIBQAAAA==.Quantismo:BAAANQAECgcICgAAAA==.',
Re='Reynerd:BAAANQADCgIIAgAAAA==.',
Ri='Ricky:BAAANQAECgEIAQAAAA==.Rivenaer:BAABNQAECn8yAAIYAAoK7QrfMgBGAQAYAAoK7QrfMgBGAQAAAA==.',
Ru='Runearne:BAAANQADCgUIBgAAAA==.Rus:BAAANQAECgUIDwAAAA==.Rustymark:BAAANQAECgcIEQAAAA==.',
Sa='Saberic:BAAANQADCgEIAQAAAA==.Satanos:BAAANQADCgQIBAAAAA==.',
Sc='Schmezzy:BAABNQAECn8hAAQaAAoK9gwkKwCCAQAbAAgKGwsrSwCNAQAaAAkKjgskKwCCAQAQAAUKtwL2rQCYAAAAAA==.Screechowl:BAAANQAECgMIAwAAAA==.Scrungagunga:BAAANQAECgQIBAAAAA==.',
Se='Sealalicious:BAABNQAECn8yAAMcAAkK4BmhFQCbAQAcAAkK4BmhFQCbAQATAAIKjAZEWwFAAAAAAA==.Seenaa:BAABNQAECn8WAAIKAAYKkgEcCwF8AAAKAAYKkgEcCwF8AAAAAA==.',
Sh='Shadowmaid:BAAANQADCgEIAQAAAA==.Shailenya:BAAANQADCgIIAgAAAA==.Shallot:BAAANQADCgQIBAAAAA==.Shammywow:BAABNQAECn8qAAMVAAoKWg/kRwDBAQAVAAoKWg/kRwDBAQAMAAYKZxhJfQCsAQAAAA==.Sharkzilla:BAABNQAECn8fAAICAAkKpxrqJwD4AgACAAkKpxrqJwD4AgAAAA==.Shiggs:BAAANQADCgcICAABNQAFFAQIBwAOAF8RAA==.Shine:BAABNQAECn8eAAICAAcKwRp7YgC6AQACAAcKwRp7YgC6AQAAAA==.Shinso:BAAANQADCggIEwABNQAECgUIEAAHAAAAAA==.Shiro:BAAANQADCgcIDQAAAA==.',
Si='Silksmilk:BAAANQADCggIHAAAAA==.Silt:BAAANQADCgEIAQAAAA==.Siobhân:BAAANQABCgIIAgAAAA==.Sixt:BAAANQADCgYIBgAAAA==.',
Sl='Sloppy:BAAANQADCgUIHQAAAA==.',
Sm='Smoo:BAAANQAECgEIAwAAAA==.',
Sn='Snøsham:BAABNQAECn8aAAMdAAgKyAvNHACXAQAdAAcKagrNHACXAQAVAAEKCwEN+gAYAAAAAA==.',
So='Soggyaugi:BAAANQAECggIDAAAAA==.',
Sp='Spatch:BAAANQADCgMIAwAAAA==.',
St='Stopdontstop:BAAANQABCgQIBQAAAA==.',
Su='Sueba:BAAANQADCgQIBAAAAA==.Sukki:BAAANQAECgEIAwABNQAECgoKIQARAI0lAA==.',
Sy='Sylvarah:BAAANQADCgEIAQAAAA==.Synora:BAAANQADCgcICwAAAA==.',
['Sè']='Sèphiroth:BAAANQADCgUICAAAAA==.',
Ta='Tallchief:BAABNQAECn8WAAICAAYKGAxbvQDzAAACAAYKGAxbvQDzAAAAAA==.Talliah:BAAANQAECgUIEgAAAA==.Talor:BAAANQADCgEIAQAAAA==.Tandyrose:BAAANQADCgEIAQAAAA==.Tankufrdying:BAAANQADCgIIAgAAAA==.',
Te='Terrier:BAAANQAECgMIAgAAAA==.',
Th='Theotank:BAABNQAECn8WAAMFAAkKDAecgwBIAQAFAAkKkwacgwBIAQAEAAEKQAlCRwAnAAAAAA==.Thrak:BAAANQAECgIIAgAAAA==.',
Ti='Tinx:BAAANQADCgMIAwAAAA==.',
To='Tokiwa:BAAANQAECggICQAAAA==.Tonjuren:BAAANQAECgUICgAAAA==.',
Tr='Tremendous:BAAANQADCgEIAQAAAA==.Trickery:BAAANQAECgEIAQAAAA==.Trublood:BAAANQAECgUIAwAAAA==.',
Tu='Tul:BAAANQAECggIBwAAAA==.',
Tw='Tweedyhunts:BAAANQAECggICAAAAA==.',
Ty='Tybbalt:BAAANQADCgcICQAAAA==.Tyrra:BAAANQAECgIIAQAAAA==.',
Uk='Ukeenonme:BAAANQADCgEIAQAAAA==.',
Us='Usorloups:BAABNQAECn8dAAIMAAkKhBzFLwC8AgAMAAkKhBzFLwC8AgAAAA==.',
Va='Valerius:BAAANQAECgYIBwAAAA==.Valithra:BAAANQAECgUIEAAAAA==.Vargrulfr:BAAANQAECgQICgAAAA==.',
Ve='Velonys:BAABNQAECn8wAAQUAAoK2xv9BwCBAgAUAAgK+Rr9BwCBAgAeAAoK+hgJBQB8AgAfAAIKEQ+lLAFkAAAAAA==.Vendra:BAAANQADCgIIAgAAAA==.Vendy:BAABNQAECn8hAAQRAAoKjSV+AAD0AgARAAoKjSV+AAD0AgAKAAEKphZFKgFOAAANAAIKSRmnMABKAAAAAA==.',
Vi='Victory:BAAANQAECgIIAgAAAA==.Vindictus:BAAANQADCgMIAwAAAA==.Vite:BAAANQADCgYIBgAAAA==.',
Vo='Vodius:BAAANQAECgMIAQABNQAECgcICgAHAAAAAA==.',
Wa='Wanayu:BAABNQAECn8lAAMfAAoK9g8fSADGAQAfAAoKhw4fSADGAQAUAAYKDQxfJQBIAQAAAA==.Wanweasley:BAABNQAECn8ZAAMVAAgKpBmJNwALAgAVAAgKpBmJNwALAgAMAAEKUgbW7gAnAAAAAA==.',
We='Weh:BAABNQAECn85AAQKAAoKjCTtGABxAwAKAAoKjCTtGABxAwARAAgKJR3wAAB+AgANAAUKnx3WFwA8AQAAAA==.',
Wi='Wizagon:BAABNQAECn8kAAIgAAoKSxzJBABYAgAgAAoKSxzJBABYAgAAAA==.',
Wo='Woode:BAAANQADCgYIBgAAAA==.Woodlet:BAAANQADCgMIAwAAAA==.Woodsy:BAABNQAECn8pAAIhAAoKchjEDQD6AQAhAAoKchjEDQD6AQAAAA==.Wounded:BAAANQADCgQIBAAAAA==.Woundliquor:BAABNQAECn8mAAMBAAgKPR0vIgCdAgABAAgKPR0vIgCdAgAGAAMKQxfWXACRAAAAAA==.',
Wu='Wuinn:BAABNQAECn8YAAQOAAgKfBm3GwBZAgAOAAgKfBm3GwBZAgAPAAYKXw8cZgA0AQASAAEK1Rd8WQBCAAABNQAFFAcIDwAhAHYIAA==.Wunna:BAAANQAECgQIDAAAAA==.',
Xc='Xcalabar:BAAANQADCgUICAAAAA==.',
Xe='Xeran:BAABNQAECn8ZAAIbAAgKFBLSOwDfAQAbAAgKFBLSOwDfAQAAAA==.',
Ya='Yawnight:BAAANQAECgMIAwAAAA==.',
Ze='Zenio:BAAANQAECggICwABNQAECgoKRgACADIlAA==.',
Zi='Zitpally:BAABNQAECn8nAAITAAoKqhQLjAANAgATAAoKqhQLjAANAgABNQAFFAIIBgAbAPoVAA==.',
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
