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

local lookup = {'Priest-Holy','Hunter-BeastMastery','Warrior-Protection','Warrior-Arms','Priest-Shadow','Paladin-Holy','Unknown-Unknown','Hunter-Survival','Mage-Arcane','Hunter-Marksmanship','Mage-Frost','Druid-Restoration','DeathKnight-Unholy','Druid-Guardian','Druid-Balance','Shaman-Elemental','Warlock-Destruction','Shaman-Restoration','DemonHunter-Vengeance','Rogue-Assassination','DemonHunter-Havoc','Warrior-Fury','Priest-Discipline','DeathKnight-Frost','Paladin-Protection','Paladin-Retribution','Shaman-Enhancement','Warlock-Affliction','Warlock-Demonology','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Farstriders',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Aberren:BAAANQAECgIIAQAAAA==.Absolon:BAAANQAECgUICgAAAA==.',
Ad='Adinirin:BAAANQADCgMIAwAAAA==.',
Ae='Aellynn:BAABNQAECn8dAAIBAAkKFQyFewCnAQABAAkKFQyFewCnAQAAAA==.Aerir:BAAANQAECgIIAgABNQAFFAMIBQACACAKAA==.',
Ag='Aggar:BAAANQAFFAQIBAAAAA==.',
Ak='Akinom:BAAANQADCgUIDQAAAA==.',
Al='Alltheheals:BAABNQAECn8ZAAIBAAgKbxysNgCNAgABAAgKbxysNgCNAgAAAA==.',
Am='Amarawyn:BAAANQAECgQIDAAAAA==.Amoonfalar:BAAANQADCggIFwAAAA==.Amoradrac:BAAANQADCgYIBgAAAA==.Amoragan:BAABNQAECn8aAAMDAAgKuhadDwAwAgADAAgKuhadDwAwAgAEAAEKAAALTgE4AAAAAA==.',
An='Andriela:BAAANQADCgYIBgAAAA==.',
Ap='Apexy:BAAANQAECgQIBAAAAA==.',
Ar='Arashikaze:BAAANQAECgUICwAAAA==.',
As='Asclepius:BAAANQAECgQIBAAAAA==.Asurion:BAAANQADCgIIBAAAAA==.',
At='Atlantis:BAAANQAFFAIIAgABNQAFFAcIGwABAP8hAA==.',
Au='Augidget:BAABNQAECn8eAAIFAAkK3RPaIQAmAgAFAAkK3RPaIQAmAgAAAA==.',
Av='Avilen:BAAANQAECgQICQAAAA==.',
Ba='Balinteen:BAAANQAECgUICgAAAA==.Bastael:BAABNQAECn8YAAIGAAgKcxTeXAACAgAGAAgKcxTeXAACAgAAAA==.',
Bi='Biopainr:BAAANQADCggJHwAAAA==.Bitxi:BAAANQAECgQIBAAAAA==.',
Bl='Bloodtusk:BAAANQADCgQIBAAAAA==.',
Bo='Bob:BAAANQADCgYIBgAAAA==.Boldbane:BAAANQAECgQIBAAAAA==.',
Br='Brandalin:BAAANQADCgcIDQABNQAECgQICAAHAAAAAA==.Brax:BAAANQAECgUIEwAAAA==.',
Bu='Burda:BAABNQAECn8pAAIIAAoKwxZIBAClAgAIAAoKwxZIBAClAgAAAA==.Buttspanker:BAAANQADCggIJgAAAA==.',
Ca='Caenae:BAAANQAECgUICgAAAA==.Cakes:BAAANQADCgMIAwAAAA==.Cattlerage:BAAANQAECggIDQAAAA==.',
Ci='Ciannie:BAAANQADCgIIAgAAAA==.',
Co='Condar:BAAANQADCgIIBAAAAA==.Corri:BAAANQAECgMIBQAAAA==.',
Cr='Credon:BAAANQAECgQIBgAAAA==.',
Da='Davin:BAAANQADCgUIAQAAAA==.',
De='Dethdeej:BAAANQAECggIAQAAAA==.',
Dh='Dhrimr:BAAANQAECgMIBgAAAA==.',
Di='Dieceptionz:BAAANQADCggICgAAAA==.Dierlyn:BAAANQAECgQIDAAAAA==.Dimir:BAABNQAECn8ZAAIDAAcKPR14DABtAgADAAcKPR14DABtAgAAAA==.Dirtytaters:BAAANQAECgUIBAAAAA==.Divastating:BAABNQAECn8WAAICAAYK2gOlewC2AAACAAYK2gOlewC2AAAAAA==.',
Do='Doró:BAAANQAECgIIAQABNQAECgkJGgAJAN8VAA==.',
Dr='Dragonberry:BAAANQAECgQICQAAAA==.',
Dt='Dtothed:BAAANQAECgUICQABNQAECgoKPAAKAPMdAA==.',
Dw='Dwaleen:BAAANQAECgMIAgAAAA==.Dwarfred:BAAANQAECgQIDAAAAA==.',
['Dò']='Dòro:BAABNQAECn8aAAMJAAkK3xXJnABHAgAJAAkK3xXJnABHAgALAAEK4wf9UAAlAAAAAA==.',
El='Elasong:BAAANQAECgIIAgAAAA==.Elletal:BAABNQAECn8XAAIMAAgK5BNFLQCyAQAMAAgK5BNFLQCyAQAAAA==.Elloria:BAAANQADCgUIBQAAAA==.Elybria:BAAANQADCgEIAQAAAA==.',
Er='Erkil:BAAANQAECgQIBAAAAA==.',
Fa='Fayona:BAAANQADCgIJAgAAAA==.',
Fi='Figbe:BAAANQAECgUJBQABNQAFFAcIFwAEAHAgAA==.Fizzlyn:BAACNQAFFH8HAAINAAMK0wvwBQCJAAANAAMK0wvwBQCJAAA1AAQKfx0AAg0ACgp1G1IOAGwBAA0ACgp1G1IOAGwBAAAA.',
Fl='Flaren:BAAANQAECgYIBwAAAA==.',
Fu='Furybutt:BAAANQABCgQIBAABNQAECgcIEgAHAAAAAA==.',
Ga='Galedriel:BAAANQADCgEIAQAAAA==.',
Ge='Gereleron:BAAANQADCgQJBAAAAA==.',
Gr='Grewsöm:BAAANQAECgcICgABNQAECggIDQAHAAAAAA==.Grizzlegom:BAAANQADCgYIDgABNQAECgoKPAAKAPMdAA==.Grotusque:BAABNQAECn8kAAMOAAgKuxFSDwAWAQAOAAcKihNSDwAWAQAPAAEKrwhyVQAuAAAAAA==.',
Ha='Haerin:BAAANQADCgQIBAAAAA==.Hardim:BAAANQADCgcJBwAAAA==.Harknesse:BAAANQAECgQIBAAAAA==.Haxxis:BAAANQAECgUIDQAAAA==.',
He='Healingways:BAAANQADCgUIBwAAAA==.Heezee:BAAANQAECggIEgAAAA==.Heftypaw:BAAANQADCggIFQAAAA==.Helliglys:BAAANQADCgEIAQAAAA==.Hextor:BAAANQAECgQICAAAAA==.',
Ho='Hog:BAABNQAECn8WAAIQAAoKvR3dKgDUAgAQAAoKvR3dKgDUAgABNQAECgoKQgADAFkmAA==.Holyboy:BAAANQAECgQIDAAAAA==.',
Hr='Hranu:BAABNQAECn8YAAIMAAoKChV2GQBwAgAMAAoKChV2GQBwAgAAAA==.',
Hy='Hydraulicman:BAAANQADCgQIBwAAAA==.',
In='Invinciboi:BAAANQADCggICAABNQAECgoKJgAGAKUPAA==.',
Ja='Jasmirana:BAAANQAECggIEQAAAA==.',
Je='Jemano:BAAANQADCgIIAgAAAA==.Jenal:BAAANQABCgIIAgAAAA==.',
Ji='Jibbadin:BAAANQADCgIIAgABNQAECgkJHQAFAE8WAA==.Jibbzin:BAAANQADCgYIBgABNQAECgkJHQAFAE8WAA==.',
Jo='Jolage:BAAANQAECgcICwABNQAECgoKPAAKAPMdAA==.Jolreal:BAABNQAECn88AAIKAAoK8x3TCgAqAwAKAAoK8x3TCgAqAwAAAA==.Jophiel:BAAANQAECgUIBgAAAA==.',
Ju='Juansbane:BAAANQADCggIBgAAAA==.Julez:BAAANQAECgQIBgAAAA==.Julezara:BAAANQAECgUICQAAAA==.Jumbledmess:BAAANQABCgMIAwAAAA==.Junkai:BAAANQAFFAIIBAAAAA==.',
Ka='Kandyman:BAAANQAECgEIAQAAAA==.Kanzashi:BAAANQADCggICAAAAA==.',
Ke='Keco:BAAANQAECgMIBAABNQAECgYIFgACANoDAA==.Kellendril:BAAANQAECgUIBQAAAA==.Kennie:BAABNQAECn8VAAIRAAYK3QUjMAAIAQARAAYK3QUjMAAIAQAAAA==.',
Kl='Kladibo:BAAANQAECgcIDgAAAA==.Kladivo:BAAANQADCgYIBgABNQAECgcIDgAHAAAAAA==.Klick:BAAANQADCgYICgABNQAFFAIIBAAHAAAAAA==.',
Kr='Kröwten:BAABNQAECn8cAAICAAgKrBrpNABTAQACAAgKrBrpNABTAQAAAA==.',
['Kì']='Kìlana:BAABNQAECn8YAAMSAAcKZgx5lgBPAQASAAcKZgx5lgBPAQAQAAcKMwXZtAAoAQAAAA==.',
La='Lahlania:BAAANQAECgEIAQAAAA==.Lanaki:BAACNQAFFH8FAAICAAMKIAoQEQCEAAACAAMKIAoQEQCEAAA1AAQKfycAAgIACgp5FjFQAH8CAAIACgp5FjFQAH8CAAAA.',
Li='Lionheart:BAAANQAECgQIBAABNQAECgoKJgAGAKUPAA==.',
Lo='Logarithmic:BAABNQAECn8UAAQIAAkKlQzNBgAgAgAIAAkKlQzNBgAgAgACAAIKYwlANQF+AAAKAAEKAADkngAfAAAAAA==.',
Lu='Lunareon:BAABNQAECn8XAAIEAAcKgRB6HgCKAQAEAAcKgRB6HgCKAQAAAA==.',
Ma='Maccbeth:BAAANQAECgQICwAAAA==.Machette:BAAANQAECgQIDAABNQAECgoKPAAKAPMdAA==.Mailaria:BAABNQAECn8YAAITAAgK5BCPDwC7AQATAAgK5BCPDwC7AQAAAA==.Maithe:BAAANQADCgMIAwAAAA==.Malvolio:BAAANQADCgEIAQAAAA==.Mambo:BAAANQADCgMIAwAAAA==.Maralucia:BAAANQADCgIIAgAAAA==.Marellaa:BAAANQAECgUICgAAAA==.Marottie:BAAANQADCgIJAgAAAA==.',
Mc='Mcsplatapus:BAAANQAECgQIDAAAAA==.',
Me='Meingsolin:BAAANQAECgQIBgABNQAECgUICgAHAAAAAA==.Methodical:BAABNQAECn8aAAIUAAoKqA6JNQADAgAUAAoKqA6JNQADAgAAAA==.',
Mi='Miggylosoh:BAAANQADCgYIBgAAAA==.',
Mo='Monkeydluffy:BAAANQADCgEIAQAAAA==.Mopa:BAAANQADCggICAAAAA==.Morfas:BAAANQABCgQIBwAAAA==.',
My='Myuk:BAABNQAECn8XAAMIAAgK6Bf+BwDiAQAIAAcKwBX+BwDiAQACAAYKHhTxrQCpAQAAAA==.',
Na='Naminay:BAAANQADCgYIDwABNQAECgUIEAAHAAAAAA==.',
Ne='Nechahira:BAAANQAECgIIAgABNQAFFAUIDwAMAOQNAA==.Neroz:BAABNQAECn8zAAIVAAcKGSGaDACLAQAVAAcKGSGaDACLAQAAAA==.Netherlight:BAAANQAECgMIAwAAAA==.',
Ni='Nina:BAAANQADCgYIBgAAAA==.',
Nk='Nkript:BAAANQAECgUICgAAAA==.',
Od='Odysemus:BAABNQAECn8jAAMEAAgKxBOkgQAXAgAEAAgKxBOkgQAXAgAWAAEKDgodOAAnAAAAAA==.',
On='Onari:BAABNQAECn8aAAMXAAgK4RW5DgBBAQABAAgK4RV1VAAmAgAXAAYKxQ+5DgBBAQAAAA==.Onlyfannz:BAAANQADCggIFAAAAA==.',
Pa='Palara:BAAANQABCgUIBQABNQAECggIGgAXAOEVAA==.Pandamoníum:BAAANQAECgMIBgAAAA==.',
Pe='Perce:BAABNQAECn8cAAIGAAYKTRYSJwBGAQAGAAYKTRYSJwBGAQAAAA==.',
Pf='Pfemme:BAABNQAECn8iAAICAAgK3xeHYABWAgACAAgK3xeHYABWAgAAAA==.',
Ph='Phalaris:BAAANQADCgIIAgAAAA==.',
Pi='Pikupchew:BAABNQAECn8jAAMSAAkKcwooggCGAQASAAkKcwooggCGAQAQAAQKGQqiUgCcAAABNQAECgoKJgAGAKUPAA==.Pinball:BAAANQADCgEIAQAAAA==.Pinstripe:BAAANQADCgQIBAAAAA==.Pixie:BAAANQAECgYICAAAAA==.',
Po='Popcorns:BAAANQADCgIIAgAAAA==.Popcornss:BAAANQAECgIIBAAAAA==.',
Pu='Purian:BAAANQADCgIJAgAAAA==.',
Qu='Qualanthar:BAAANQADCgQIBQAAAA==.Quantimo:BAAANQABCgEIAQABNQAECgYIBAAHAAAAAA==.Quantismo:BAAANQAECgYIBAAAAA==.',
Ri='Rivenaer:BAABNQAECn8pAAIVAAgK7gshQQC2AQAVAAgK7gshQQC2AQAAAA==.',
Ru='Runearne:BAAANQADCgUIBgAAAA==.Rus:BAAANQAECgQIBgAAAA==.Rustymark:BAAANQAECgcIEQAAAA==.',
Sa='Satanos:BAAANQADCgQIBAAAAA==.',
Sc='Schmezzy:BAABNQAECn8UAAMYAAgK5QorSwCNAQAYAAgK5QorSwCNAQANAAUKtwL2rQCYAAAAAA==.Screechowl:BAAANQAECgMIAwAAAA==.Scrungagunga:BAAANQAECgQIBAAAAA==.',
Se='Sealalicious:BAABNQAECn8eAAMZAAgKmhbZHwDmAQAZAAcKfBrZHwDmAQAaAAEKLAP3DQEeAAAAAA==.Seenaa:BAAANQAECgUIDQAAAA==.',
Sh='Shailenya:BAAANQADCgIIAgAAAA==.Shallot:BAAANQADCgIIAgAAAA==.Shammywow:BAABNQAECn8bAAMQAAoK+hhJfQCsAQAQAAYK7hdJfQCsAQASAAoK2Qy/KgA3AQAAAA==.Sharkzilla:BAABNQAECn8dAAICAAkKpxrqJwD4AgACAAkKpxrqJwD4AgAAAA==.Shiggs:BAAANQADCgcIBwABNQAECggIFwAMAOQTAA==.Shine:BAABNQAECn8VAAICAAUKURxZuACTAQACAAUKURxZuACTAQAAAA==.Shinso:BAAANQADCggIEQABNQAECgUIEAAHAAAAAA==.Shiro:BAAANQADCgcICwAAAA==.',
Si='Silksmilk:BAAANQADCggIGgAAAA==.Silt:BAAANQABCgQIBAAAAA==.Siobhân:BAAANQABCgIIAgAAAA==.Sixt:BAAANQADCgYIBgAAAA==.',
Sl='Sloppy:BAAANQADCgYIEQAAAA==.',
Sm='Smoo:BAAANQAECgEIAgAAAA==.',
Sn='Snøsham:BAABNQAECn8ZAAIbAAcKagrNHACXAQAbAAcKagrNHACXAQAAAA==.',
So='Soggyaugi:BAAANQAECgcICwAAAA==.',
St='Stopdontstop:BAAANQABCgQIBQAAAA==.',
Su='Sukki:BAAANQAECgEIAgABNQAECgcIEgAHAAAAAA==.Sunwälker:BAAANQABCgYICAAAAA==.',
Sy='Synora:BAAANQADCgcICwAAAA==.',
['Sè']='Sèphiroth:BAAANQADCgUIBwAAAA==.',
Ta='Tallchief:BAAANQAECgUICgAAAA==.Talliah:BAAANQAECgQICQAAAA==.Tankufrdying:BAAANQADCgIIAgAAAA==.',
Ti='Tikisha:BAAANQADCgEIAQAAAA==.Tinx:BAAANQADCgMJAwAAAA==.',
To='Tonjuren:BAAANQAECgUICgAAAA==.',
Tr='Tremendous:BAAANQABCgIIAgAAAA==.Trickery:BAAANQAECgEIAQAAAA==.Tropi:BAAANQAECgIIBQAAAA==.Trublood:BAAANQAECgMIAwAAAA==.',
Tu='Tul:BAAANQAECgcIBwABNQAECggIEAAHAAAAAA==.',
Ty='Tybbalt:BAAANQADCgcICAAAAA==.Tyrra:BAAANQAECgEIAQAAAA==.',
Uk='Ukeenonme:BAAANQADCgEIAQAAAA==.',
Us='Usorloups:BAABNQAECn8dAAIQAAkKhBzFLwC8AgAQAAkKhBzFLwC8AgAAAA==.',
Va='Valithra:BAAANQAECgUIEAAAAA==.Vargrulfr:BAAANQAECgQICgAAAA==.',
Ve='Velonys:BAABNQAECn8sAAQRAAoKrxv9BwCBAgARAAgK+Rr9BwCBAgAcAAoKnhcJBQB8AgAdAAIKEQ+lLAFkAAAAAA==.Vendy:BAAANQAECgcIEgAAAA==.',
Vi='Victory:BAAANQAECgIIAgAAAA==.Vindictus:BAAANQADCgMIAwAAAA==.Vite:BAAANQADCgYIBgAAAA==.',
Vy='Vyu:BAAANQADCgEIAQAAAA==.',
Wa='Wanayu:BAABNQAECn8YAAMRAAgKWg5fJQBIAQAdAAcK+woprQB3AQARAAYKDQxfJQBIAQAAAA==.Wanweasley:BAAANQAECgYIDwAAAA==.',
We='Weh:BAABNQAECn8nAAMJAAkKDiXtGABxAwAJAAkKDiXtGABxAwALAAUKnx3WFwA8AQAAAA==.',
Wi='Wizagon:BAABNQAECn8YAAIeAAgKQhulDACYAgAeAAgKQhulDACYAgAAAA==.',
Wo='Woodlet:BAAANQADCgMIAwAAAA==.Woodsy:BAABNQAECn8cAAIfAAgKSBcZGwAVAgAfAAgKSBcZGwAVAgAAAA==.Woody:BAAANQADCgQIDgAAAA==.Wounded:BAAANQADCgQIBAAAAA==.Woundliquor:BAABNQAECn8WAAMBAAcKURa2bADYAQABAAcKURa2bADYAQAFAAMKQxfWXACRAAAAAA==.',
Wu='Wuinn:BAABNQAECn8XAAQMAAgKfhe3GwBZAgAMAAgKfhe3GwBZAgAPAAYKXw8cZgA0AQAOAAEK1ReCMgBKAAAAAA==.Wunna:BAAANQAECgQIDAAAAA==.',
Xc='Xcalabar:BAAANQADCgUICAAAAA==.',
Xe='Xeran:BAABNQAECn8ZAAIYAAgKFBLSOwDfAQAYAAgKFBLSOwDfAQAAAA==.',
Ya='Yawnight:BAAANQAECgMIAwAAAA==.',
Ze='Zenio:BAAANQAECgIIAQABNQAECgoKMgAaAAseAA==.',
Zi='Zitpally:BAABNQAECn8eAAIaAAkKrBILjAANAgAaAAkKrBILjAANAgABNQAFFAIIBQAYAOoOAA==.',
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
