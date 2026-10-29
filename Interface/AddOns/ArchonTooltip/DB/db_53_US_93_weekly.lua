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

local lookup = {'Priest-Holy','Hunter-BeastMastery','Warrior-Fury','Warrior-Protection','Warrior-Arms','Priest-Shadow','Paladin-Holy','Unknown-Unknown','Hunter-Survival','Mage-Arcane','Hunter-Marksmanship','Shaman-Elemental','Mage-Frost','Druid-Restoration','Druid-Balance','DeathKnight-Unholy','Mage-Fire','Druid-Guardian','Paladin-Retribution','Shaman-Restoration','Warlock-Destruction','DemonHunter-Vengeance','Rogue-Assassination','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Frost','DeathKnight-Blood','Paladin-Protection','Shaman-Enhancement','Evoker-Preservation','Warlock-Affliction','Warlock-Demonology','Evoker-Devastation',}
local provider = {region='US',realm='Farstriders',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Aberren:BAAANQAECgMIBQAAAA==.Absolon:BAAANQAECgUIDAAAAA==.',
Ad='Adinirin:BAAANQADCgMIAwAAAA==.',
Ae='Aellynn:BAABNQAECn8fAAIBAAoKDQ2FewCnAQABAAoKDQ2FewCnAQAAAA==.Aerir:BAAANQAECgIIAgABNQAFFAUICAACAMoJAA==.',
Ag='Aggar:BAABNQAFFH8IAAICAAUK1hzGCAAOAQACAAUK1hzGCAAOAQAAAA==.',
Ak='Akinom:BAAANQADCgUIDQAAAA==.',
Al='Alltheheals:BAABNQAECn8aAAIBAAkK8xmsNgCNAgABAAkK8xmsNgCNAgAAAA==.Alysana:BAAANQADCgMIAwAAAA==.',
Am='Amarawyn:BAABNQAECn8WAAMDAAUKFwonHgDQAAADAAUKFwonHgDQAAAEAAIKwAQkQAA/AAAAAA==.Amoonfalar:BAAANQADCggIFwAAAA==.Amoradrac:BAAANQAECgEIAQAAAA==.Amoragan:BAABNQAECn8bAAMEAAgKuhadDwAwAgAEAAgKuhadDwAwAgAFAAEKAAALTgE4AAAAAA==.Amoratan:BAAANQADCgMIAwAAAA==.',
An='Anaren:BAAANQAECgEIAQAAAA==.Andriela:BAAANQADCgYIBgAAAA==.',
Ap='Apexy:BAAANQAECgQIBgAAAA==.',
Ar='Arashikaze:BAAANQAECgUIDwAAAA==.Areadhel:BAAANQADCgMIAwAAAA==.Arianffwr:BAAANQADCgMIAwAAAA==.',
As='Asclepius:BAAANQAECgQIBgAAAA==.Asurion:BAAANQAECgEIAQAAAA==.',
At='Atlantis:BAAANQAFFAIIAgABNQAFFAcIGwABAP8hAA==.',
Au='Augidget:BAABNQAECn8mAAIGAAoKzxLaIQAmAgAGAAoKzxLaIQAmAgAAAA==.',
Av='Avilen:BAAANQAECgQICQAAAA==.',
Ba='Balinteen:BAAANQAECgUIDwAAAA==.Bastael:BAABNQAECn8cAAIHAAoKHBXeXAACAgAHAAoKHBXeXAACAgAAAA==.Bayus:BAAANQADCgIIAgAAAA==.',
Be='Berone:BAAANQADCgMIAwAAAA==.Beryrn:BAAANQADCgIIAgAAAA==.',
Bi='Biopainr:BAAANQADCggJHwAAAA==.Bitxi:BAAANQAECgQIBgAAAA==.',
Bl='Bloodtusk:BAAANQAECgMIAwAAAA==.',
Bo='Bob:BAAANQADCgYIBgAAAA==.Boldbane:BAAANQAECgYICgAAAA==.',
Br='Brandalin:BAAANQADCgcIDQABNQAECgQICAAIAAAAAA==.Brax:BAABNQAECn8VAAMEAAYKyB5kGACpAQAEAAUKaiJkGACpAQADAAEKQBC9IAA/AAAAAA==.',
Bu='Burda:BAABNQAECn8pAAIJAAoKwxZIBAClAgAJAAoKwxZIBAClAgAAAA==.Buttspanker:BAAANQADCggIJgAAAA==.',
Ca='Caenae:BAAANQAECgUIEQAAAA==.Cakes:BAAANQADCgMIAwAAAA==.Cattlerage:BAAANQAECggIDQAAAA==.',
Ce='Celan:BAAANQAECgEIAQAAAA==.',
Ci='Ciannie:BAAANQADCgQIBAAAAA==.',
Co='Condar:BAAANQADCgIIBAAAAA==.Corri:BAAANQAECgQICwAAAA==.',
Cr='Credon:BAAANQAECgQICAAAAA==.',
Cy='Cybedru:BAAANQADCgMIAwAAAA==.',
Da='Davin:BAAANQADCgUIAQAAAA==.',
De='Dethdeej:BAAANQAFFAEIAQAAAA==.',
Dh='Dhrimr:BAAANQAECgQIDAAAAA==.',
Di='Dieceptionz:BAAANQADCggICgAAAA==.Dierlyn:BAABNQAECn8WAAIBAAUKVBYGZAAsAQABAAUKVBYGZAAsAQAAAA==.Dimir:BAABNQAECn8gAAIEAAgKlBx4DABtAgAEAAgKlBx4DABtAgAAAA==.Dirtytaters:BAAANQAECgUIBgAAAA==.Divastating:BAABNQAECn8YAAICAAYK2gPRxACoAAACAAYK2gPRxACoAAAAAA==.',
Do='Doró:BAAANQAECgMIBwABNQAECgoKGwAKADAUAA==.',
Dr='Dragonberry:BAAANQAECgQICgAAAA==.',
Dt='Dtothed:BAAANQAECgUICwABNQAECgoKRQALALAeAA==.',
Du='Duckyme:BAAANQADCgMIAwAAAA==.',
Dw='Dwaleen:BAAANQAECgQIBQAAAA==.Dwarfred:BAABNQAECn8UAAIMAAQKWBnxqwA8AQAMAAQKWBnxqwA8AQAAAA==.',
Dy='Dyàsis:BAAANQAECgEIAwAAAA==.',
['Dò']='Dòro:BAABNQAECn8bAAMKAAoKMBTJnABHAgAKAAoKMBTJnABHAgANAAEK4wf9UAAlAAAAAA==.',
El='Elasong:BAAANQAECgUIBQAAAA==.Elletal:BAABNQAECn8aAAMOAAgK5BNFLQCyAQAOAAgK5BNFLQCyAQAPAAMKIQhETwCJAAAAAA==.Elloria:BAAANQADCgUIBQAAAA==.Elybria:BAAANQADCgEIAQAAAA==.',
Er='Erkil:BAAANQAECgUIBgAAAA==.',
Fa='Fayona:BAAANQADCgIJAgAAAA==.',
Fi='Figbe:BAAANQAECgUJBgABNQAFFAcIFwAFAHAgAA==.Fizzlyn:BAACNQAFFH8KAAIQAAUKYxLfBADxAAAQAAUKYxLfBADxAAA1AAQKfyEAAhAACgrUHb0pAJECABAACgrUHb0pAJECAAAA.',
Fl='Flaren:BAAANQAECgYIBwAAAA==.',
Fu='Furybutt:BAAANQAECgIIAwABNQAECgoKFgARAPEkAA==.',
Ga='Galedriel:BAAANQADCgEIAQAAAA==.',
Ge='Gereleron:BAAANQAECgEIAQAAAA==.',
Gr='Grewsöm:BAAANQAECgcICwABNQAECggIDQAIAAAAAA==.Grizzlegom:BAAANQADCgcIEQABNQAECgoKRQALALAeAA==.Grotusque:BAABNQAECn8sAAMSAAgKxxRoGQBBAQASAAcKxxZoGQBBAQAPAAEKxwqKbgAzAAAAAA==.',
Ha='Haerin:BAAANQADCgQIBAAAAA==.Hardim:BAAANQADCgcJBwAAAA==.Harknesse:BAAANQAECgQIBgAAAA==.Hawthorn:BAAANQADCgMIAwABNQAECgQICgAIAAAAAA==.Haxxis:BAAANQAECgUIDQAAAA==.',
He='Healingways:BAAANQADCgUIBwAAAA==.Heezee:BAABNQAECn8WAAICAAkKYQ5vUQCoAQACAAkKYQ5vUQCoAQAAAA==.Heftypaw:BAAANQADCggIFQAAAA==.Helliglys:BAAANQADCgMIAwAAAA==.Hextor:BAAANQAECgQICAAAAA==.',
Hi='Hickorie:BAAANQADCgMIAwAAAA==.Hielo:BAAANQADCgMIAwAAAA==.',
Ho='Hog:BAABNQAECn8WAAIMAAoKvR3dKgDUAgAMAAoKvR3dKgDUAgABNQAECgoKSwAEAK0mAA==.Holyboy:BAABNQAECn8UAAITAAQKGRO1CQEPAQATAAQKGRO1CQEPAQAAAA==.',
Hr='Hranu:BAABNQAECn8gAAIOAAoKxhrZCAC/AgAOAAoKxhrZCAC/AgAAAA==.',
Hu='Husker:BAAANQADCgcIBwAAAA==.',
Hy='Hydraulicman:BAAANQADCgQIBwAAAA==.',
In='Inenwe:BAAANQADCgMIAwAAAA==.Invinciboi:BAAANQADCggICAABNQAECgkJJQAUAMEKAA==.',
Ir='Ironwind:BAAANQADCgMIAwAAAA==.',
Ja='Jasmirana:BAABNQAECn8XAAMBAAgKUA6TmgBFAQABAAgKUA6TmgBFAQAGAAQKuAEfRQA7AAAAAA==.',
Je='Jemano:BAAANQADCgMIBQAAAA==.Jenal:BAAANQABCgIIAgAAAA==.Jenina:BAAANQADCgMIAwAAAA==.Jeselle:BAAANQAECgEIAwAAAA==.',
Ji='Jibbadin:BAAANQADCgIIAgABNQAECgkJHQAGAE8WAA==.Jibbzin:BAAANQADCgYIBgABNQAECgkJHQAGAE8WAA==.',
Jo='Jolage:BAAANQAECgcIEQABNQAECgoKRQALALAeAA==.Jolreal:BAABNQAECn9FAAILAAoKsB7TCgAqAwALAAoKsB7TCgAqAwAAAA==.Jophiel:BAAANQAECgUICAAAAA==.',
Ju='Juansbane:BAAANQADCggICQAAAA==.Julez:BAAANQAECgQICAAAAA==.Julezara:BAAANQAECgQIDgAAAA==.Jumbledmess:BAAANQAECgEIAQAAAA==.Junkai:BAACNQAFFH8HAAITAAQK8hmYCQD7AAATAAQK8hmYCQD7AAA1AAQKfxcAAhMABQq8IR5pAIQBABMABQq8IR5pAIQBAAAA.',
Ka='Kandyman:BAAANQAECgEIAQAAAA==.Kanzashi:BAAANQADCggICAAAAA==.',
Ke='Keco:BAAANQAECgMICAABNQAECgYIGAACANoDAA==.Kennie:BAABNQAECn8cAAIVAAgKQAlbBwACAQAVAAgKQAlbBwACAQAAAA==.',
Ki='Kinlar:BAAANQAECgEIBAAAAA==.',
Kl='Kladibo:BAAANQAECggIEgAAAA==.Kladivo:BAAANQADCgYIBgABNQAECggIEgAIAAAAAA==.Klick:BAAANQADCgYICgABNQAFFAQIBwATAPIZAA==.',
Kn='Knorr:BAAANQAECgEIAQAAAA==.',
Kr='Kröwten:BAABNQAECn8gAAICAAgKgRxoRgDMAQACAAgKgRxoRgDMAQAAAA==.',
['Kì']='Kìlana:BAABNQAECn8fAAMUAAgKhw95lgBPAQAUAAcKZgx5lgBPAQAMAAgK2ATDaADUAAAAAA==.',
La='Lahlania:BAAANQAECgEIAgAAAA==.Lammchop:BAAANQADCgMIAwAAAA==.Lanaki:BAACNQAFFH8IAAICAAUKygnIDwDPAAACAAUKygnIDwDPAAA1AAQKfysAAgIACgo1FzFQAH8CAAIACgo1FzFQAH8CAAAA.',
Li='Linwe:BAAANQAECgEIAgAAAA==.Lionheart:BAAANQAECgQIBAABNQAECgkJJQAUAMEKAA==.',
Lo='Logarithmic:BAABNQAECn8UAAQJAAkKlQzNBgAgAgAJAAkKlQzNBgAgAgACAAIKYwlANQF+AAALAAEKAADkngAfAAAAAA==.',
Lu='Lunareon:BAABNQAECn8eAAIFAAcKgRAXWAB5AQAFAAcKgRAXWAB5AQAAAA==.',
Ma='Maccbeth:BAAANQAECgUIDAAAAA==.Machette:BAAANQAECgUIDwABNQAECgoKRQALALAeAA==.Mailaria:BAABNQAECn8cAAIWAAoKlw+PDwC7AQAWAAoKlw+PDwC7AQAAAA==.Maithe:BAAANQADCgMIAwAAAA==.Malamonk:BAAANQAECgEIAQAAAA==.Malphric:BAAANQAECgEIAgAAAA==.Malvolio:BAAANQADCgEIAQAAAA==.Mambo:BAAANQADCgMIAwAAAA==.Maralucia:BAAANQADCgIIAgAAAA==.Marellaa:BAAANQAECgYIEAAAAA==.Marottie:BAAANQADCgIJAgAAAA==.',
Mc='Mcsplatapus:BAAANQAECgQIEAAAAA==.',
Me='Meingsolin:BAAANQAECgUIDwAAAA==.Methodical:BAABNQAECn8hAAIXAAoKuRDYEQBxAQAXAAoKuRDYEQBxAQAAAA==.',
Mi='Miggylosoh:BAAANQADCgYIBgAAAA==.',
Mo='Monkeydluffy:BAAANQADCgEIAQAAAA==.Mopa:BAAANQADCggICAAAAA==.Morfas:BAAANQABCgQIBwAAAA==.',
My='Myuk:BAABNQAECn8aAAMJAAkKsBj+BwDiAQAJAAcKwBX+BwDiAQACAAcK9xXxrQCpAQAAAA==.',
Mz='Mzskywalker:BAAANQADCgMIAwAAAA==.',
Na='Naminay:BAAANQADCgYIDwABNQAECgYIFQABAIAiAA==.',
Ne='Nechahira:BAAANQAECgIIAgABNQAECggIEQAIAAAAAA==.Neroz:BAABNQAECn8/AAIYAAgKGB/RHAC0AQAYAAgKGB/RHAC0AQAAAA==.Netherlight:BAAANQAECgMIBAABNQAECgQICQAIAAAAAA==.',
Ni='Nina:BAAANQADCgYIBgAAAA==.',
Nk='Nkript:BAAANQAECgcIDQAAAA==.',
Od='Odysemus:BAABNQAECn8jAAMFAAgKxBOkgQAXAgAFAAgKxBOkgQAXAgADAAEKDgodOAAnAAAAAA==.',
On='Onari:BAABNQAECn8eAAMZAAoKSxS5DgBBAQABAAoKSxR1VAAmAgAZAAYKxQ+5DgBBAQAAAA==.Onlyfannz:BAAANQADCggIFAAAAA==.',
Or='Orcicide:BAAANQADCgMIAwAAAA==.',
Os='Oskkar:BAAANQADCgMIAwAAAA==.',
Pa='Palara:BAAANQAECgEIAwABNQAECgoKHgAZAEsUAA==.Pandamoníum:BAAANQAECgQIDAAAAA==.',
Pe='Perce:BAABNQAECn8hAAMHAAcKQRgiWgA0AQAHAAYKTRYiWgA0AQATAAUKpAgrxgDSAAAAAA==.',
Pf='Pfemme:BAABNQAECn8mAAICAAgK3xeHYABWAgACAAgK3xeHYABWAgAAAA==.',
Ph='Phalaris:BAAANQADCgIIAgAAAA==.',
Pi='Pikupchew:BAABNQAECn8lAAMUAAkKwQooggCGAQAUAAkKwQooggCGAQAMAAQKGQpTjACFAAAAAA==.Pinball:BAAANQADCgEIAQAAAA==.Pinstripe:BAAANQADCgQIBAAAAA==.Pixie:BAAANQAECgYICwAAAA==.',
Po='Popcorns:BAAANQADCgIIAgAAAA==.Popcornss:BAAANQAECgIIBAAAAA==.',
Pu='Purian:BAAANQADCgIJAgAAAA==.',
Qu='Qualanthar:BAAANQADCgQIBQAAAA==.Quantimo:BAAANQAECgIIAwABNQAECgcIDQAIAAAAAA==.Quantismo:BAAANQAECgcIDQAAAA==.',
Re='Reyaieleron:BAAANQAECgEIAQAAAA==.Reynerd:BAAANQADCgIIAgAAAA==.',
Ri='Ricky:BAAANQAECgEIAQAAAA==.Rivenaer:BAABNQAECn8pAAIYAAgK7gshQQC2AQAYAAgK7gshQQC2AQAAAA==.',
Ru='Runearne:BAAANQADCgUIBgAAAA==.Rus:BAAANQAECgUICwAAAA==.Rustymark:BAAANQAECgcIEwAAAA==.',
Sa='Satanos:BAAANQADCgQIBAAAAA==.',
Sc='Schmezzy:BAABNQAECn8YAAQaAAoKcworSwCNAQAaAAgKGwsrSwCNAQAQAAUKtwL2rQCYAAAbAAIKegh7bgBWAAAAAA==.Screechowl:BAAANQAECgMIAwAAAA==.Scrungagunga:BAAANQAECgQIBQAAAA==.',
Se='Sealalicious:BAABNQAECn8uAAMcAAkKKRfZHwDmAQAcAAgKXhnZHwDmAQATAAIKjAZqIgFTAAAAAA==.Seenaa:BAAANQAECgUIEQAAAA==.',
Sh='Shailenya:BAAANQADCgIIAgAAAA==.Shallot:BAAANQADCgQIBAAAAA==.Shammywow:BAABNQAECn8kAAMUAAoKEQ+INQDHAQAUAAoKEQ+INQDHAQAMAAYK7hdJfQCsAQAAAA==.Sharkzilla:BAABNQAECn8dAAICAAkKpxrqJwD4AgACAAkKpxrqJwD4AgAAAA==.Shiggs:BAAANQADCgcIBwABNQAECggIGgAOAOQTAA==.Shine:BAABNQAECn8cAAICAAcKwRp/SQDBAQACAAcKwRp/SQDBAQAAAA==.Shinso:BAAANQAECgEIAQABNQAECgYIFQABAIAiAA==.Shiro:BAAANQADCgcICwAAAA==.',
Si='Silksmilk:BAAANQAECgEIAgAAAA==.Silt:BAAANQABCgQIBAAAAA==.Siobhân:BAAANQAECgEIAQAAAA==.Sixt:BAAANQADCgYIBgAAAA==.',
Sl='Sloppy:BAAANQADCgUIFgAAAA==.',
Sm='Smoo:BAAANQAECgEIAwAAAA==.',
Sn='Snøsham:BAABNQAECn8aAAMdAAgKyAvNHACXAQAdAAcKagrNHACXAQAUAAEKCwFL3QAZAAAAAA==.',
So='Soggyaugi:BAAANQAECggIEQAAAA==.',
Sp='Spatch:BAAANQADCgMIAwAAAA==.',
St='Stopdontstop:BAAANQAECgEIAQAAAA==.',
Su='Sueba:BAAANQADCgMIAwAAAA==.Sukki:BAAANQAECgEIBwABNQAECgoKFgARAPEkAA==.Sunwälker:BAAANQAECgEIBQAAAA==.',
Sy='Synora:BAAANQAECgEIAQAAAA==.',
['Sè']='Sèphiroth:BAAANQADCgUIBwAAAA==.',
Ta='Tallchief:BAAANQAECgYIEQAAAA==.Talliah:BAAANQAECgQIDQAAAA==.Tankufrdying:BAAANQADCgIIAgAAAA==.Tatershotz:BAAANQAECgIIAgAAAA==.',
Th='Thrak:BAAANQAECgMIAwAAAA==.',
Ti='Tinx:BAAANQADCgMIAwAAAA==.',
To='Tokiwa:BAAANQAECgEIAQABNQAECgoKMgAeAEgHAA==.Tonjuren:BAAANQAECgUICwABNQAECgUIDwAIAAAAAA==.',
Tr='Tremendous:BAAANQABCgIIAgAAAA==.Trickery:BAAANQAECgEIAwAAAA==.Tropi:BAAANQAECggIDQAAAA==.Trublood:BAAANQAECgMIBQAAAA==.',
Tu='Tul:BAAANQAECggICAAAAA==.',
Ty='Tybbalt:BAAANQADCgcICAAAAA==.Tyrra:BAAANQAECgIIAgAAAA==.',
Uk='Ukeenonme:BAAANQADCgEIAQAAAA==.',
Us='Usorloups:BAABNQAECn8dAAIMAAkKhBzFLwC8AgAMAAkKhBzFLwC8AgAAAA==.',
Va='Valerius:BAAANQAECgcICwAAAA==.Valithra:BAABNQAECn8VAAIBAAYKgCJwSABNAgABAAYKgCJwSABNAgAAAA==.Vargrulfr:BAAANQAECgUICwAAAA==.',
Ve='Velonys:BAABNQAECn8vAAQVAAoK2xv9BwCBAgAVAAgK+Rr9BwCBAgAfAAoK+hgJBQB8AgAgAAIKEQ+lLAFkAAAAAA==.Vendra:BAAANQADCgIIAgAAAA==.Vendy:BAABNQAECn8WAAIRAAoK8SSdAABSAwARAAoK8SSdAABSAwAAAA==.',
Vi='Victory:BAAANQAECgIIBQAAAA==.Vindictus:BAAANQADCgMIAwAAAA==.Vite:BAAANQADCgYIBgAAAA==.',
Vo='Vodius:BAAANQAECgMIAwABNQAECgcIDQAIAAAAAA==.',
Vy='Vyu:BAAANQADCgEIAQAAAA==.',
Wa='Wanayu:BAABNQAECn8cAAMVAAoK3Q1fJQBIAQAgAAkKaQsprQB3AQAVAAYKDQxfJQBIAQAAAA==.Wanweasley:BAAANQAECggIEwAAAA==.',
We='Weh:BAABNQAECn8wAAMKAAoKjCTtGABxAwAKAAoKjCTtGABxAwANAAUKnx3WFwA8AQAAAA==.',
Wi='Wizagon:BAABNQAECn8cAAIhAAoKeRqlDACYAgAhAAoKeRqlDACYAgAAAA==.',
Wo='Woodlet:BAAANQAECgEIAgAAAA==.Woodsy:BAABNQAECn8kAAIeAAoKtRY7DgCRAQAeAAoKtRY7DgCRAQAAAA==.Wounded:BAAANQADCgQIBAAAAA==.Woundliquor:BAABNQAECn8eAAMBAAgKdxuyHwBkAgABAAgKdxuyHwBkAgAGAAMKQxfWXACRAAAAAA==.',
Wu='Wuinn:BAABNQAECn8YAAQOAAgKfBm3GwBZAgAOAAgKfBm3GwBZAgAPAAYKXw8cZgA0AQASAAEK1RctSgBFAAABNQAFFAcIDwAeAHYIAA==.Wunna:BAAANQAECgQIDAAAAA==.',
Xc='Xcalabar:BAAANQADCgUICAAAAA==.',
Xe='Xeran:BAABNQAECn8ZAAIaAAgKFBLSOwDfAQAaAAgKFBLSOwDfAQAAAA==.',
Ya='Yawnight:BAAANQAECgMIAwAAAA==.',
Ze='Zenio:BAAANQAECgcICgABNQAECgoKQAACADIlAA==.',
Zi='Zitpally:BAABNQAECn8iAAITAAkKqxQLjAANAgATAAkKqxQLjAANAgABNQAFFAIIBQAaAOoOAA==.',
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
