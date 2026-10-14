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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Shaman-Elemental','Druid-Balance','DeathKnight-Unholy','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','Evoker-Devastation','Evoker-Augmentation','Priest-Discipline','Priest-Shadow','Priest-Holy','Mage-Arcane','Hunter-BeastMastery','Rogue-Assassination','Druid-Restoration','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Preservation','Druid-Feral','Mage-Frost','DeathKnight-Blood','Druid-Guardian','Rogue-Subtlety','Warlock-Affliction','DemonHunter-Devourer','Paladin-Holy','Paladin-Protection','Warrior-Arms','Shaman-Enhancement','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abones:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.',
Ad='Adonìs:BAAANQAECgYIDAABNQAECgkJJQACAB4cAA==.',
Ae='Aeolos:BAAANQADCgcICwAAAA==.Aesthetic:BAAANQAECgcIDgABNQAFFAcIFwADAHUbAA==.',
Ag='Agrios:BAACNQAFFH8FAAIEAAIKPA9IHgCbAAAEAAIKPA9IHgCbAAA1AAQKfy0AAgQACQrzG04YAAMDAAQACQrzG04YAAMDAAAA.',
Ai='Aiellee:BAAANQAECgMIBQAAAA==.',
Ak='Akias:BAAANQAECgYIBgAAAA==.',
Al='Alexandra:BAAANQAECgQIBQABNQABCgQIBAABAAAAAA==.Alliekill:BAAANQADCgUIBgABNQAECgYIBwABAAAAAA==.Altaurus:BAAANQAECgUIDQAAAA==.Alynnei:BAAANQAECgIIAwABNQABCgQIBAABAAAAAA==.',
Am='Amare:BAAANQAECgQIBwAAAA==.Amiria:BAAANQADCggICAAAAA==.',
An='Andros:BAAANQAECgUIDQAAAA==.Antigone:BAAANQADCgYIBgAAAA==.',
Ar='Arroyo:BAABNQAECn8lAAIFAAgKLCP9EAAuAwAFAAgKLCP9EAAuAwAAAA==.',
As='Askadar:BAACNQAFFH8GAAIGAAMK6SXbAgBOAQAGAAMK6SXbAgBOAQA1AAQKfyYAAgYACQr5JiAAAAsEAAYACQr5JiAAAAsEAAAA.',
Az='Azora:BAABNQAECn8dAAMHAAkK3haUDAAtAgAHAAcK3xmUDAAtAgAIAAcK6hKWhQDTAQAAAA==.Azzura:BAAANQAECgEJAQAAAA==.',
Ba='Baheem:BAAANQADCggIIAAAAA==.Bams:BAABNQAECn8YAAIJAAcKWRPmewCUAQAJAAcKWRPmewCUAQAAAA==.Banthisname:BAAANQADCgIIAgAAAA==.Barnie:BAABNQAECn8gAAMKAAkKEhxRCQDcAgAKAAkKEhxRCQDcAgALAAEK3AElKAAeAAAAAA==.Basquiat:BAAANQADCgYIBQAAAA==.Bastile:BAAANQADCggICQAAAA==.Bauer:BAABNQAECn8jAAICAAkKNRT5cABJAgACAAkKNRT5cABJAgAAAA==.',
Be='Beasthunter:BAAANQADCgYIBgAAAA==.Beeftruck:BAAANQADCgYIGQAAAA==.',
Bi='Bifrons:BAAANQADCgYIGAAAAA==.',
Bj='Björk:BAAANQADCgEIAQAAAA==.',
Bl='Blackkheartt:BAAANQADCgUIBQAAAA==.Blahwithpets:BAAANQADCgMIBgAAAA==.Bluè:BAAANQAECgIIAgAAAA==.',
Bo='Bobble:BAAANQADCgUIBQAAAA==.Boneman:BAAANQAECgEIAQAAAA==.Bookwyrm:BAAANQADCgYIGAAAAA==.Boolil:BAAANQAECgQIDAABNQAECgkJKwAMAPUNAA==.Boolove:BAAANQABCgUIAwABNQAECgkJKwAMAPUNAA==.Booloved:BAABNQAECn8rAAQMAAkK9Q1iCgChAQAMAAgKPA9iCgChAQANAAkKHgT+OwBGAQAOAAYK8QH6yADAAAAAAA==.',
Bq='Bqcritraven:BAAANQADCgUJBQAAAA==.',
Br='Broxx:BAAANQADCgcICQAAAA==.',
Bu='Bulwei:BAAANQAECgYIBwAAAA==.',
By='Byssrak:BAAANQAECgIIAgAAAA==.',
Ca='Carmêl:BAAANQAECgQIBQABNQAECgkJJAAPALUgAA==.Cattiegreen:BAABNQAECn8lAAIQAAcKpRmAZwBDAgAQAAcKpRmAZwBDAgAAAA==.',
Ce='Celoraning:BAAANQADCgcIBwAAAA==.Cerealmilk:BAAANQADCgQIBAABNQADCggJEQABAAAAAA==.',
Ch='Chopshop:BAAANQADCgUIBQAAAA==.Christopher:BAABNQAECn8iAAIPAAkKghZkgQB7AgAPAAkKghZkgQB7AgAAAA==.',
Co='Costica:BAAANQADCgUIBQAAAA==.',
Cr='Creepychaos:BAAANQADCggICAABNQAECgUIBQABAAAAAA==.Creepydemise:BAAANQAECgUIBQAAAA==.Croixsmash:BAAANQAECgcIEgAAAA==.',
Cu='Cuculain:BAAANQAECgYIBgAAAA==.',
Cy='Cylvanna:BAAANQAECgQICQAAAA==.',
Da='Darkagedemon:BAAANQADCgQIBAAAAA==.Darkrest:BAAANQADCggIDgAAAA==.Dartboofer:BAAANQADCgYIBgABNQAECgcIEgABAAAAAA==.Daslouse:BAAANQADCggIFAAAAA==.Davennial:BAABNQAECn8kAAICAAkKXwweqADKAQACAAkKXwweqADKAQAAAA==.Dawnn:BAAANQAECgUICwAAAA==.',
De='Deanwnchestr:BAAANQAECgUICQAAAA==.Deatnshadow:BAAANQAECggICAAAAA==.Dendin:BAAANQADCgcIBwAAAA==.',
Dm='Dmncgdss:BAAANQAECgQIBQAAAA==.',
Do='Dogeatdog:BAAANQADCgEIAQAAAA==.',
Dr='Draakell:BAAANQAECgYICwAAAA==.Dragonstew:BAAANQADCgYIBgAAAA==.Drausella:BAAANQADCgMIAwAAAA==.Dreamsicle:BAAANQAECgUIBwAAAA==.Dregomalfoy:BAAANQADCggICQAAAA==.Drizzle:BAAANQABCgIIAgAAAA==.Dryrain:BAAANQADCggICAAAAA==.',
Du='Dudè:BAAANQAECgUIDAAAAA==.',
['Dâ']='Dâggèr:BAABNQAFFH8HAAIRAAMKDRvJDgD3AAARAAMKDRvJDgD3AAAAAA==.',
['Dí']='Dímoní:BAAANQADCgUIBgAAAA==.',
Ec='Echidna:BAAANQABCggIDAAAAA==.',
El='Elarae:BAABNQAECn8ZAAIQAAgKcxbhVwBpAgAQAAgKcxbhVwBpAgAAAA==.Elementblah:BAABNQAECn8UAAIDAAYKng+YmABjAQADAAYKng+YmABjAQAAAA==.Elfkinn:BAACNQAFFH8RAAIEAAUKDhneDACYAQAEAAUKDhneDACYAQA1AAQKfyEAAwQACQqRH0gdAN0CAAQACQqRH0gdAN0CABIAAQqHAcaDABUAAAAA.Elivaniel:BAAANQADCgYIBgAAAA==.Ellemere:BAAANQAECgUIBQABNQABCgQIBAABAAAAAA==.',
Em='Emeryl:BAAANQAECgQIBQABNQAFFAcIFwADAHUbAA==.Empathyforyo:BAABNQAECn8nAAMQAAkKdRhHSQCPAgAQAAgKXRtHSQCPAgATAAQKAAlaVgDIAAAAAA==.',
En='Enna:BAAANQADCgYIGAAAAA==.',
Eq='Equinox:BAABNQAECn8aAAIEAAkKZRLNOgAZAgAEAAkKZRLNOgAZAgAAAA==.',
Er='Ericcdraven:BAAANQADCgQIBAAAAA==.Erodoria:BAABNQAECn8ZAAMUAAgKsRajDAD3AQAUAAgK8hSjDAD3AQAVAAUKshjXTgBaAQAAAA==.',
Es='Eshtar:BAAANQAECgQIBAAAAA==.',
Ev='Eve:BAAANQADCgEIAQAAAA==.',
Ex='Exkwon:BAAANQAECggIEwAAAA==.Exzanthia:BAAANQADCggICwAAAA==.',
Ey='Eyln:BAABNQAECn8WAAITAAYKygwHPwBVAQATAAYKygwHPwBVAQAAAA==.',
Fa='Falkor:BAABNQAECn8mAAIWAAkKKxdmEgCEAgAWAAkKKxdmEgCEAgAAAA==.Fayway:BAABNQAECn8hAAMSAAgKMR43EgC7AgASAAgKMR43EgC7AgAEAAEKAAAsxwAZAAAAAA==.',
Fe='Fentlord:BAAANQADCgYIBgAAAA==.Ferral:BAABNQAECn8rAAIXAAkKBB7gBAA2AwAXAAkKBB7gBAA2AwAAAA==.',
Fi='Figgy:BAAANQAECggIEwAAAA==.Firepower:BAABNQAECn8sAAMPAAkK6RvtTgDjAgAPAAkK1RvtTgDjAgAYAAEKvhmaQgA9AAAAAA==.',
Fo='Forevershy:BAAANQADCggIHgAAAA==.',
Fr='Fries:BAEANQAECggIDQAAAA==.',
Ga='Galvianick:BAAANQADCggICQAAAA==.',
Gi='Giggles:BAAANQAECgUIDAAAAA==.',
Go='Goh:BAAANQAECgQIBAAAAA==.Gomugomu:BAAANQADCgEIAQAAAA==.Gonzo:BAAANQAECgcIDgABNQAECgkJJwAJAI4iAA==.Gothrim:BAAANQADCggICAAAAA==.',
Gr='Greenbean:BAAANQADCggJCAABNQAFFAUIEQAEAA4ZAA==.Groto:BAAANQAECgYIDwAAAA==.Grrum:BAAANQAECgQIBAAAAA==.Grèy:BAAANQAECgQIBwAAAA==.',
Gu='Gullible:BAAANQAECgYICQAAAA==.',
Ha='Hairy:BAAANQAECgMIAwAAAA==.Halbin:BAAANQADCgEIAQAAAA==.Hamburgrtime:BAAANQADCgYIEAAAAA==.Hanjo:BAABNQAECn8VAAIGAAYKDB1JFADfAQAGAAYKDB1JFADfAQAAAA==.Hatookorr:BAABNQAECn8aAAIZAAgKzx32IQCjAgAZAAgKzx32IQCjAgABNQAECgkJLAAPAOkbAA==.',
He='Heledrianis:BAAANQAECgQIBAAAAA==.Heledriann:BAAANQADCgUIBQAAAA==.Herunn:BAAANQADCggICAAAAA==.',
Ho='Hornet:BAAANQADCggIJAAAAA==.',
Hy='Hydé:BAACNQAFFH8SAAIaAAUKfB5fAQDEAQAaAAUKfB5fAQDEAQA1AAQKfxsAAhoACQqTGyYLALgCABoACQqTGyYLALgCAAAA.',
Ik='Ikwon:BAAANQADCgUIBwAAAA==.',
Im='Immatry:BAAANQADCgcIBwAAAA==.',
Is='Ishmael:BAAANQAECgQIBAAAAA==.Ismeldbad:BAAANQAECgIIAwABNQAECgkJGQAbAJgaAA==.',
Ja='Jaland:BAAANQABCgQIBAAAAA==.',
Je='Jellybreak:BAABNQAECn8YAAIEAAYKRQ9OXABcAQAEAAYKRQ9OXABcAQAAAA==.',
Jo='Joeewee:BAAANQAECgMIBQAAAA==.',
Ka='Kaanâ:BAABNQAECn8VAAIOAAYKQhYofgCaAQAOAAYKQhYofgCaAQAAAA==.Kateblue:BAABNQAECn8VAAIEAAYKgQyxXwBNAQAEAAYKgQyxXwBNAQAAAA==.',
Ke='Keeble:BAAANQAECgEIAQAAAA==.Kegstand:BAAANQADCgUIBQAAAA==.Kelser:BAABNQAECn8WAAMcAAcKChpkCAAHAgAcAAcKChpkCAAHAgAIAAMKWAURHwF9AAAAAA==.Kelsyyr:BAAANQAECgUIBwABNQAECgcIFgAcAAoaAA==.Kenpachi:BAAANQADCgEIAQAAAA==.',
Ki='Kidneysweeny:BAABNQAECn8ZAAMbAAkKmBpwIQC9AQAbAAYK6xdwIQC9AQARAAQKiBl8XwAwAQAAAA==.Kikyou:BAABNQAECn8dAAIFAAcKoBz6OAA+AgAFAAcKoBz6OAA+AgABNQAFFAYIGwAdALcgAA==.Kim:BAAANQAECgYIEQAAAA==.Kissofdeáth:BAAANQADCggIDwAAAA==.',
Kr='Kreepywife:BAAANQADCgUIBQAAAA==.Krelbelorll:BAABNQAECn8hAAIdAAkK4Q9HKAD+AQAdAAkK4Q9HKAD+AQAAAA==.Krowley:BAABNQAECn8ZAAIJAAgKtggVjwBfAQAJAAgKtggVjwBfAQAAAA==.',
Ku='Kurast:BAAANQAECgUIDgABNQAECgkJJgAWACsXAA==.Kuz:BAAANQADCgUIBgAAAA==.Kuzan:BAACNQAFFH8OAAIPAAUK/R9aFgC/AQAPAAUK/R9aFgC/AQA1AAQKfx4AAw8ACQoiIn5JAO8CAA8ACQoiIn5JAO8CABgAAQp9HQFJADEAAAAA.',
Kx='Kxwono:BAAANQAECgYIEAAAAA==.',
La='Ladýshinobu:BAABNQAECn8XAAIeAAYKZQd3rwAcAQAeAAYKZQd3rwAcAQAAAA==.',
Le='Leahu:BAAANQAECgUICQAAAA==.Lediaa:BAAANQADCgQIBAAAAA==.Lemonweed:BAAANQADCgIIAgAAAA==.Leonidus:BAAANQAECgMIAwAAAA==.',
Li='Lisavia:BAAANQAECgYIDwAAAA==.',
Lo='Locholovis:BAAANQAECgcICAAAAA==.Locklicous:BAABNQAECn8nAAIIAAkKeBuOIQD7AgAIAAkKeBuOIQD7AgABNQAECgcIEgABAAAAAA==.Lonewolf:BAAANQAECgEIAQAAAA==.Longhorse:BAACNQAFFH8OAAIZAAUKJRZIEABMAQAZAAUKJRZIEABMAQA1AAQKfywAAxkACQocHxEiAKICABkACQpCHhEiAKICAAUABAr/HNl7ACgBAAAA.',
Lu='Luminouss:BAACNQAFFH8KAAIJAAUK8BQZCwCXAQAJAAUK8BQZCwCXAQA1AAQKfzkAAwkACQp0HZokANECAAkACQp0HZokANECAAMAAQrTFfgiAUQAAAAA.Lumpia:BAAANQAECgcIBwAAAA==.Lustnnbustin:BAAANQADCgcIDwAAAA==.',
Ly='Lyrium:BAAANQADCgYIBgABNQAECggIHgAZALwZAA==.Lysandora:BAAANQADCgQIBAAAAA==.',
Ma='Magicgal:BAAANQAECgEIAQAAAA==.Magnuus:BAAANQAECgUIBgAAAA==.Majin:BAAANQAECgIIAgAAAA==.Malvorak:BAAANQAECgQIBAAAAA==.Mantis:BAABNQAECn8cAAIJAAcKWCOxLACtAgAJAAcKWCOxLACtAgABNQAECgkJJgAWACsXAA==.',
Me='Meekerz:BAAANQADCgMIAwAAAA==.Melissandra:BAABNQAECn8VAAINAAYKBw4yOgBSAQANAAYKBw4yOgBSAQAAAA==.Merab:BAAANQADCgIIAgAAAA==.Mercas:BAAANQAECgQIBQABNQAECggIIwAPACwYAA==.Mezi:BAABNQAECn8bAAIOAAYK6h21YwDxAQAOAAYK6h21YwDxAQAAAA==.',
Mg='Mg:BAAANQADCgUIDQAAAA==.',
Mh='Mhonster:BAAANQAECgYIBgABNQABCgQIBAABAAAAAA==.',
Mi='Miasma:BAAANQADCggICwAAAA==.Middleman:BAAANQADCgQIBAAAAA==.Mildchaos:BAAANQAECgUIEQAAAA==.',
Mu='Mulron:BAABNQAECn8YAAIfAAgKUxagGAAwAgAfAAgKUxagGAAwAgAAAA==.',
My='Myrica:BAAANQAECggIBwAAAA==.',
Ni='Nishand:BAAANQADCgEIAQAAAA==.',
Oa='Oakenshíeld:BAACNQAFFH8LAAIEAAQKRxTMEgA4AQAEAAQKRxTMEgA4AQA1AAQKfy4AAgQACQq4HMUYAP8CAAQACQq4HMUYAP8CAAAA.',
Od='Odyn:BAAANQAECgEIAQAAAA==.',
Ok='Okwonz:BAAANQADCggICAAAAA==.',
Ol='Olkwon:BAAANQAECggIDgAAAA==.',
Oo='Oozwoz:BAAANQADCggIBAAAAA==.',
Ou='Outfoxed:BAAANQAECggIEwABNQAFFAYIFAAOACUXAA==.',
Ox='Oxwon:BAAANQADCggIDgAAAA==.',
Pa='Palliera:BAAANQADCgMIAwAAAA==.',
Pe='Peetufo:BAABNQAECn8VAAIEAAYKXQi9aAAlAQAEAAYKXQi9aAAlAQAAAA==.Pewpewtazarz:BAAANQADCggICAAAAA==.',
Ph='Phrizzle:BAAANQADCgQIDAAAAA==.',
Pl='Plaguebeard:BAAANQAECgIJAwABNQAECggJGgAgAGkSAA==.Plagueblade:BAABNQAECn8VAAIZAAYKlRHuawBBAQAZAAYKlRHuawBBAQAAAA==.',
Po='Poppy:BAAANQABCgIIAgAAAA==.',
Pr='Progression:BAAANQAECggICwAAAA==.',
Ra='Ragingrain:BAAANQADCgUIBQAAAA==.Rainsshammy:BAABNQAECn8hAAIJAAgKPht+NgCDAgAJAAgKPht+NgCDAgAAAA==.Rawak:BAAANQABCggIDgAAAA==.Rawktuah:BAAANQADCgMIAwABNQAECgUICgABAAAAAA==.',
Re='Realhelz:BAAANQADCgcICQAAAA==.Redsamilf:BAAANQAECgQICQAAAA==.Rekka:BAAANQADCgYICgAAAA==.Requizik:BAAANQAECgUICAAAAA==.Resaana:BAAANQAECgIIAwABNQAECgQIBAABAAAAAA==.Restofarian:BAABNQAECn8nAAMJAAkKjiJ/DABaAwAJAAkKjiJ/DABaAwADAAQKURDt2gDbAAAAAA==.',
Rh='Rhaegaria:BAAANQADCgEIAQAAAA==.Rhaegarina:BAAANQADCgQIBAAAAA==.Rhagnor:BAABNQAECn8UAAIhAAYKrRCeHQCCAQAhAAYKrRCeHQCCAQAAAA==.',
Ri='Rianon:BAAANQADCgEIAQABNQAECgcIDwABAAAAAA==.Rizzy:BAABNQAECn80AAMFAAkK4w+cSwDjAQAFAAkK4w+cSwDjAQAiAAcKmgcfWQA+AQAAAA==.',
Ro='Rotinshot:BAACNQAFFH8GAAIQAAMKRBNhFwD7AAAQAAMKRBNhFwD7AAA1AAQKfx0AAxAACQqYG5QqAO0CABAACQqYG5QqAO0CABMAAgopBct7AE4AAAAA.',
Ru='Rutikee:BAABNQAECn8oAAMSAAgK8A2jLgCiAQASAAgK8A2jLgCiAQAEAAIKiQMkowBQAAAAAA==.',
Ry='Ryomensukuna:BAAANQAFFAIIAgAAAA==.',
Sa='Sandrill:BAAANQAECgQJBQABNQAECgkJLAAPAOkbAA==.Savior:BAAANQAECgIIAgAAAA==.',
Sc='Scrabble:BAAANQADCggICAAAAA==.',
Se='Seamisty:BAAANQADCgIJAgAAAA==.Seastorm:BAAANQADCgQIBAAAAA==.Seizon:BAAANQAECgQICQAAAA==.Senseicanz:BAAANQADCgYIBgAAAA==.Serom:BAAANQAECgUICgAAAA==.Sethic:BAAANQADCgYJBAAAAA==.',
Sh='Shadowguidem:BAAANQADCgMIAwAAAA==.Sharkie:BAAANQADCggJCwAAAA==.Sharkyn:BAAANQADCgQIBAAAAA==.Sharpshôôter:BAAANQADCgUIBQAAAA==.Sherunn:BAAANQAECgQICAAAAA==.Shimakaze:BAABNQAECn8bAAIQAAcKgQkhswCZAQAQAAcKgQkhswCZAQAAAA==.Shmitty:BAAANQAECgYICwABNQAFFAMIBwARAA0bAA==.Shooters:BAAANQAECgYIEwAAAA==.Shymistress:BAABNQAECn8jAAIQAAgK/RxRRACdAgAQAAgK/RxRRACdAgAAAA==.Shåmmy:BAABNQAECn8rAAIJAAkKlhTLSQA4AgAJAAkKlhTLSQA4AgAAAA==.',
Si='Sindralea:BAAANQAECgYIEwAAAA==.',
Sk='Skiá:BAABNQAECn8lAAIXAAgKihzPCADAAgAXAAgKihzPCADAAgAAAA==.',
Sl='Slayerkitty:BAAANQABCgEIAQAAAA==.Slicedbread:BAAANQAECgEIAQAAAA==.',
So='Songatsu:BAAANQADCgQIBAAAAA==.',
Sp='Spareparts:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Splaat:BAAANQADCgIIAgAAAA==.Splàsh:BAAANQAFFAIIAgAAAA==.',
St='Stoneboot:BAABNQAECn8eAAICAAcKBBkxeAA4AgACAAcKBBkxeAA4AgAAAA==.Stonefist:BAAANQAECgEIAQABNQAFFAMIBwARAA0bAA==.Stormfox:BAAANQAECgYIDwAAAA==.Strawhat:BAAANQAECgQICwAAAA==.',
Su='Suljin:BAAANQADCgUIBQAAAA==.Sumaria:BAAANQAECgMICAAAAA==.Superman:BAAANQADCgMIAwAAAA==.',
Sw='Sweetvixen:BAAANQAECgQIBAAAAA==.',
Sy='Sylvanasthot:BAAANQADCgMIAwAAAA==.',
Ta='Tabiaia:BAAANQADCgIIAgAAAA==.Taler:BAAANQAECgQIDgAAAA==.Tannuk:BAABNQAECn8oAAIfAAgK0Bw6EgB7AgAfAAgK0Bw6EgB7AgAAAA==.Tarz:BAAANQABCgIIAgAAAA==.Tauru:BAAANQAECgIIAgAAAA==.',
Te='Tea:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Teessedra:BAAANQADCgUIBQAAAA==.Terdanator:BAABNQAECn8iAAIDAAgKrx36MgCqAgADAAgKrx36MgCqAgAAAA==.',
Th='Thekingbak:BAAANQAECgEIAQABNQAECggIEAABAAAAAA==.Thundaris:BAAANQABCgMIAwAAAA==.',
Ti='Tiari:BAABNQAECn8mAAIeAAgKxhXWVAAYAgAeAAgKxhXWVAAYAgAAAA==.Tidepod:BAAANQAECgEIAQAAAA==.',
To='Totems:BAAANQAECgcIEgABNQAECgIIAgABAAAAAA==.',
Tr='Tridius:BAABNQAECn9BAAMOAAkKISPJBwCFAwAOAAkKISPJBwCFAwANAAEKAABfcwA8AAAAAA==.Trixx:BAAANQAECgUICwAAAA==.',
Tu='Tuffcracker:BAAANQAECgQICAAAAA==.Turdanator:BAAANQAECgMIAwAAAA==.',
Tw='Twinturboj:BAAANQAECgUICAAAAA==.Twittle:BAAANQAECgQICQAAAA==.',
Ty='Tylovastus:BAAANQAECgcIDAAAAA==.Tyrmin:BAAANQAECgEIAQAAAA==.',
Ub='Ube:BAABNQAECn8bAAIgAAgKjx9mRgCzAgAgAAgKjx9mRgCzAgAAAA==.',
Ur='Uriah:BAAANQAECgUIDQAAAA==.Ursúla:BAAANQAECggIDQABNQAFFAUIEQAEAA4ZAA==.Urïah:BAAANQADCgYICQABNQAECgUIDQABAAAAAA==.',
Ut='Utherr:BAAANQAECggICAAAAA==.',
Va='Valaravaus:BAAANQADCggICwAAAA==.Varjo:BAAANQADCgQIBAAAAA==.Vashirr:BAAANQADCgIIAgAAAA==.',
Ve='Vergus:BAAANQADCgYIBgAAAA==.',
Vi='Viral:BAAANQAECggICQAAAA==.',
Vo='Vonnie:BAAANQAECgQIBQAAAA==.',
['Vé']='Végeta:BAAANQAECgQIDAABNQAECgkJJgAWACsXAA==.',
Wa='Wardwhelp:BAAANQADCggJEQAAAA==.',
Wh='Whitecoma:BAAANQABCgIIAgAAAA==.',
Wo='Wooloo:BAACNQAFFH8NAAQIAAYKZhpIGAA3AQAIAAQKYxdIGAA3AQAcAAEKAABzCQBaAAAHAAEKbiN2FgBXAAA1AAQKfyIAAwcACQpbH4kPAAMCAAgABgo0JhxJAHQCAAcABwp3G4kPAAMCAAAA.',
Wy='Wynona:BAACNQAFFH8FAAIPAAIKTwcFTQCJAAAPAAIKTwcFTQCJAAA1AAQKfyUAAg8ACQr9Fil1AJMCAA8ACQr9Fil1AJMCAAAA.',
Xa='Xanagore:BAABNQAECn8eAAMgAAcKSRJVqACzAQAgAAcKSRJVqACzAQAGAAMKWAvcNACIAAAAAA==.',
Xk='Xkwon:BAAANQADCggIDgAAAA==.Xkwøn:BAACNQAFFH8KAAIjAAIK1BpLAgCrAAAjAAIK1BpLAgCrAAA1AAQKfy0AAiMACQp5ItwBAFUDACMACQp5ItwBAFUDAAAA.Xkwønn:BAAANQADCgUICgAAAA==.Xkwønxø:BAAANQAECgcIDgAAAA==.',
Xu='Xunie:BAAANQADCggIKwAAAA==.',
Yl='Yloh:BAABNQAECn8eAAQOAAkKMCTwBgCMAwAOAAkKMCTwBgCMAwANAAYK4wXjVwClAAAMAAIK3Q0EIABfAAAAAA==.',
Yo='Yoquiere:BAAANQAECgMIAwAAAA==.',
Za='Zaisplash:BAAANQAECgUICgAAAA==.Zana:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.Zaphi:BAAANQADCgcIBwABNQAECgUICwABAAAAAA==.Zaretan:BAAANQADCggIGQAAAA==.',
Zb='Zbrute:BAABNQAECn8ZAAIQAAgKvRDtcwAmAgAQAAgKvRDtcwAmAgAAAA==.',
Ze='Zees:BAAANQAECggIAQAAAA==.',
Zo='Zokohjin:BAACNQAFFH8SAAQiAAUKfBUJDAAXAQAiAAQK+hMJDAAXAQAFAAMKEg7vEgDZAAAZAAEKAAD6MwAqAAA1AAQKfxsAAwUACQr6FKc5ADoCAAUACQr6FKc5ADoCACIABAoyGRFoAPYAAAAA.',
Zu='Zulpher:BAAANQADCggIIAAAAA==.',
['Ðe']='Ðepz:BAAANQAECgUIEQAAAA==.',
['Øk']='Økwøn:BAACNQAFFH8HAAIPAAQKJRR3LAAkAQAPAAQKJRR3LAAkAQA1AAQKfx0AAg8ACQp3IHMYAHMDAA8ACQp3IHMYAHMDAAAA.',
['ße']='ßeorn:BAAANQABCgIIAgAAAA==.',
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
