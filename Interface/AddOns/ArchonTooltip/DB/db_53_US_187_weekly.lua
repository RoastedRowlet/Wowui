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

local lookup = {'Unknown-Unknown','Mage-Arcane','Hunter-BeastMastery','DemonHunter-Vengeance','DemonHunter-Devourer','Rogue-Subtlety','Druid-Restoration','Druid-Feral','Paladin-Retribution','Evoker-Devastation','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Protection','Paladin-Holy','DemonHunter-Havoc','DeathKnight-Frost','Mage-Frost','Priest-Holy','Priest-Shadow','Druid-Guardian','Druid-Balance','Warrior-Protection','Monk-Mistweaver','Warlock-Demonology','Priest-Discipline','Hunter-Marksmanship',}
local provider = {region='US',realm='Sentinels',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Absqwas:BAAANQADCgUIDAABNQADCgYIBgABAAAAAA==.',
Ac='Actaeon:BAAANQABCgEIAQAAAA==.',
Ad='Adaina:BAABNQAECn8wAAICAAoKHw1pcwCYAQACAAoKHw1pcwCYAQAAAA==.',
Ae='Ae:BAAANQADCgMIAwAAAA==.Aetherstrike:BAAANQAECgQIBAAAAA==.',
Ah='Aheeaheehahe:BAABNQAECn8+AAIDAAoKBB1QJgB7AgADAAoKBB1QJgB7AgAAAA==.',
Ai='Ailanissa:BAAANQAECgcIDgAAAA==.Ailasaa:BAABNQAECn8/AAMEAAoKjCZbAADkAwAEAAoKjCZbAADkAwAFAAYKOBZLMwCoAQAAAA==.Ainsley:BAAANQADCgUIBQAAAA==.',
Al='Alynddra:BAAANQAECgQICAAAAA==.',
An='Anbraxas:BAAANQAECgIIBAAAAA==.Antonson:BAABNQAECn8sAAIGAAoK/BH8GwD1AQAGAAoK/BH8GwD1AQAAAA==.',
Ao='Ao:BAABNQAECn8dAAMHAAoKehxSEwBKAgAHAAkKOB5SEwBKAgAIAAQKRQbjLACrAAAAAA==.',
As='Asdanot:BAAANQAECgEIAQAAAA==.Astovidatu:BAABNQAECn8YAAIJAAoKCgqPgwCFAQAJAAoKCgqPgwCFAQAAAA==.',
At='Atanukki:BAAANQAECgUICgABNQAECgkJHgAJAN8jAA==.',
Au='Auroranova:BAABNQAECn8qAAIJAAgK6QxKzgB/AQAJAAgK6QxKzgB/AQAAAA==.',
Ax='Axél:BAAANQAECgUIEAAAAA==.',
Ay='Ayblinkin:BAAANQADCgYJBgABNQAFFAMIBwAKADsDAA==.',
Ba='Ball:BAAANQAECggICAABNQAECggIEAABAAAAAA==.Balthazaar:BAAANQAECgEIAQAAAA==.',
Be='Berzquaza:BAAANQADCgYIBgAAAA==.',
Bl='Bluedreamm:BAAANQAECgEIAQAAAA==.',
Br='Braei:BAAANQAECgIIBAAAAA==.Brilleleante:BAAANQADCgcIEQAAAA==.Broxmorn:BAAANQADCgIIAgAAAA==.',
Ca='Canimai:BAAANQAECggIDwAAAA==.Cappe:BAAANQABCgIIAgAAAA==.',
Ch='Chettybetty:BAAANQAECgYICQAAAA==.',
Co='Cojul:BAABNQAECn8lAAILAAgK1x21BADaAgALAAgK1x21BADaAgAAAA==.',
Cr='Crazynaga:BAAANQADCggIDgAAAA==.Crisspy:BAABNQAECn8hAAMMAAkKQge/fwCNAQAMAAkKQge/fwCNAQANAAcK8wZrpABMAQAAAA==.',
Cu='Cubes:BAACNQAFFH8VAAIOAAcKZyQ0AQC9AgAOAAcKZyQ0AQC9AgA1AAQKfzEAAw4ACgqKJrQGAGYDAA4ACgqKJrQGAGYDAA8ABgrEHekUAJQBAAAA.',
De='Deadlylight:BAABNQAECn8eAAIJAAkKEwnxpgBAAQAJAAkKEwnxpgBAAQAAAA==.Deathcrocker:BAEBNQAECn8jAAMQAAoKNCFACgDVAgAQAAoKNCFACgDVAgARAAMKqQIG4wAxAAABNQAFFAgIIwASAEwkAA==.Demoniko:BAAANQADCgQIBAAAAA==.Denounce:BAACNQAFFH8MAAITAAUKlB2YCADZAQATAAUKlB2YCADZAQA1AAQKfyoAAhMACgq/JTIDAL4DABMACgq/JTIDAL4DAAAA.Depthrootme:BAAANQAECgEIAQABNQAECgoKKwAUAJMXAA==.',
Di='Diddlerprime:BAAANQADCggIDwAAAA==.',
Do='Dogs:BAAANQAECgIIBgABNQAFFAcIHQADAHIhAA==.Domar:BAAANQAECgIIBAAAAA==.Doomslayer:BAABNQAECn8fAAMRAAkKgxluNABYAgARAAkKCBhuNABYAgAVAAYKRRc2UABzAQAAAA==.Dothippo:BAABNQAECn8lAAILAAkK9BO+BACDAQALAAkK9BO+BACDAQAAAA==.',
Dr='Drachunter:BAAANQADCgUIDwAAAA==.',
Du='Dumach:BAAANQADCggIDQAAAA==.',
Ea='Easy:BAABNQAECn8wAAIDAAkKuCHTEADyAgADAAkKuCHTEADyAgAAAA==.',
Eh='Ehrathorn:BAAANQADCgYIBgAAAA==.',
El='Elennoxx:BAAANQAECgIIBAAAAA==.Elonaara:BAAANQADCgcIBgAAAA==.',
Et='Etta:BAAANQADCgYIFgAAAA==.',
Ex='Exarchstrike:BAAANQAECgIIAgAAAA==.',
Fa='Fayce:BAAANQABCgYICgAAAA==.',
Fe='Feledara:BAAANQAECgQIBQAAAA==.Ferne:BAAANQADCgYICQAAAA==.Feylen:BAAANQAECgYICQAAAA==.',
Fl='Floof:BAAANQADCgMIAwAAAA==.',
Fr='Frieren:BAACNQAFFH8oAAMCAAcKvyRNAgDQAgACAAcK5yNNAgDQAgAWAAEKAiI0CwBiAAA1AAQKfzgAAgIACgoKJk0SAIkDAAIACgoKJk0SAIkDAAAA.',
Ge='Gencrocker:BAECNQAFFH8jAAISAAgKTCRiAADzAgASAAgKTCRiAADzAgA1AAQKfxgAAhIACgoLIZEMANECABIACgoLIZEMANECAAAA.Getoffenris:BAAANQAECgIIBAAAAA==.',
Gl='Gloryhammer:BAAANQAECggICAAAAA==.',
Go='Gobbs:BAABNQAECn8eAAIGAAoK9xLvFwAeAgAGAAoK9xLvFwAeAgAAAA==.Golduck:BAAANQAECggIEAAAAA==.',
Gr='Gratagnan:BAAANQABCgEIAQAAAA==.Grimmi:BAAANQADCgEIAQAAAA==.Grosh:BAAANQADCgYIBgAAAA==.',
Ha='Haldrian:BAAANQAECgIIBAAAAA==.',
Ho='Hollydaye:BAAANQAECgQIDQAAAA==.Holyhota:BAACNQAFFH8IAAIXAAQKDRDNFwA1AQAXAAQKDRDNFwA1AQA1AAQKfx8AAxcACQp+HOEnAMoCABcACQp+HOEnAMoCABgAAwqXEONXAKsAAAAA.Holymolly:BAAANQADCgYIBgAAAA==.Holystrike:BAAANQADCgYIFwAAAA==.Hop:BAABNQAECn8zAAQIAAoK+RgyCgCaAgAIAAoK+RgyCgCaAgAZAAQK3A3ZPQCYAAAaAAIKsQbApwBIAAAAAA==.',
Il='Ilos:BAAANQABCggIGQAAAA==.',
Ir='Iraedies:BAAANQABCgIIAgAAAA==.Ironborn:BAAANQAECgUIEAAAAA==.',
Iv='Ivakor:BAAANQAECgcIDgAAAA==.',
Ja='Jaes:BAAANQADCgUIBgAAAA==.Jaszuny:BAABNQAECn83AAIEAAoKDw6dCwBjAQAEAAoKDw6dCwBjAQAAAA==.',
Je='Jeeyell:BAABNQAECn8mAAIbAAgK/RqJDgBFAgAbAAgK/RqJDgBFAgAAAA==.Jezlyn:BAAANQAECgEIAQAAAA==.',
Jo='Jo:BAAANQADCgYIDAAAAA==.Johnnyblaze:BAAANQADCgEIAQAAAA==.Johyah:BAACNQAFFH8KAAIcAAYKsRDXAwCwAQAcAAYKsRDXAwCwAQA1AAQKfzQAAhwACgpvIR4IAA8DABwACgpvIR4IAA8DAAAA.',
['Jö']='Jösîah:BAAANQADCgEIAQAAAA==.',
Ka='Kalafuzz:BAAANQAECgYIBgABNQAFFAQICAASAKUYAA==.Karkara:BAABNQAECn8eAAMVAAkKYxjxNAAIAgAVAAgK+hbxNAAIAgAQAAUKmhgRQgANAQAAAA==.Karrthis:BAAANQAECgUIDgAAAA==.Karrthus:BAAANQAECgUIBQABNQAECgUIDgABAAAAAA==.Katsumotosan:BAAANQADCgcICwAAAA==.',
Ke='Kemstrio:BAABNQAECn8eAAMZAAgKzx7sEwAlAgAZAAcKuiDsEwAlAgAaAAMKuhotQwDnAAABNQAFFAUIDwAEANYfAA==.Kev:BAABNQAECn8mAAMWAAoK7Rt0CgC1AQACAAkKzRqiqwArAgAWAAYKnh10CgC1AQAAAA==.',
Ko='Kombatgodess:BAAANQADCgYIDAAAAA==.Kordraan:BAAANQADCgQIBAAAAA==.',
Kr='Krael:BAAANQAECggIBgAAAA==.',
Ks='Kspboop:BAEANQAECgcIBAAAAA==.',
Ku='Kurag:BAAANQAECgEIAQAAAA==.Kurvios:BAABNQAECn8wAAMEAAkKtB+WBABbAgAUAAkKnh0eIgCKAgAEAAkKzh2WBABbAgABNQAECgoKPQAYAMQeAA==.Kuurgan:BAAANQAECgQIDAAAAA==.',
Kv='Kvasir:BAAANQAECgMIBgABNQAECggIJQALANcdAA==.',
Li='Lichkingstoy:BAACNQAFFH8MAAIJAAUK6xDmFwDpAAAJAAUK6xDmFwDpAAA1AAQKf1MAAgkACgo2IeI1APYCAAkACgo2IeI1APYCAAAA.Light:BAAANQAECggIBAABNQAECgkJMAADALghAA==.Lilmist:BAAANQAECgQIBAAAAA==.Lizardboi:BAAANQAECgcIEQAAAA==.',
Ll='Llilth:BAAANQADCgEIAQAAAA==.',
Ma='Magicstrike:BAAANQADCgcIEgAAAA==.Manistas:BAAANQADCgMIAwAAAA==.Manta:BAAANQAECgcIDwAAAA==.',
Mi='Miracle:BAAANQAECgIIBAAAAA==.Mirana:BAAANQADCgIIAgAAAA==.',
Mo='Morelinne:BAAANQADCgUIDQAAAA==.',
My='Mykeexd:BAAANQADCgQIBAAAAA==.Mykehoochie:BAAANQADCgQIAwAAAA==.',
Na='Nabarke:BAAANQAECgIIBAAAAA==.Naidomsa:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Nathanos:BAAANQAECgQIBwABNQAECgoKPQAYAMQeAA==.Naturestrike:BAAANQAECgUIBQAAAA==.',
Ne='Nexaliah:BAAANQAECgMIBQABNQAFFAcIFAAJACMYAA==.Nezath:BAAANQAECggIDgABNQAECgoKOgAdAAsiAA==.',
Ni='Nier:BAAANQAECgQICgAAAA==.',
No='Noisemarine:BAABNQAECn8uAAIbAAkKdA1qHgBhAQAbAAkKdA1qHgBhAQAAAA==.Nooxi:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Nospheratus:BAABNQAECn8jAAMIAAoKnhhlDAC5AQAZAAoKiROUFQAQAgAIAAkK9BNlDAC5AQABNQAFFAUIDAAQAIgMAA==.Noub:BAAANQADCgYJBgAAAA==.',
Nx='Nx:BAAANQAECgEIAQAAAA==.',
Ny='Nylianna:BAACNQAFFH8UAAIJAAcKIxhJBACIAQAJAAcKIxhJBACIAQA1AAQKfysAAgkACgo3JOk6AOYCAAkACgo3JOk6AOYCAAAA.',
Ob='Obilesk:BAAANQADCgcIBwAAAA==.',
Og='Ogganborn:BAAANQAECgYIDgAAAA==.',
Ph='Phoenïx:BAAANQABCgYICQAAAA==.',
Pi='Pikal:BAABNQAECn8cAAQJAAoKgQ18kABrAQAJAAkKgQ18kABrAQATAAUKIwMm4wC6AAASAAEKAAADeAAlAAAAAA==.',
Pr='Priestaline:BAABNQAECn8oAAINAAoKcRUkNwC/AQANAAoKcRUkNwC/AQAAAA==.Priestigory:BAABNQAECn8gAAMPAAoKARRkCQCDAQAPAAkKpBRkCQCDAQAOAAEKjg9EUAA7AAAAAA==.Prosper:BAAANQAECgEIAQAAAA==.',
Pv='Pvtcrocker:BAEBNQAFFH8IAAIZAAUKzBJYAgB1AQAZAAUKzBJYAgB1AQABNQAFFAgIIwASAEwkAA==.',
Qu='Quintus:BAABNQAECn8tAAIJAAoK/RxINQBhAgAJAAoK/RxINQBhAgAAAA==.',
Ra='Ra:BAAANQAECggIEAAAAA==.Railiana:BAAANQADCgQIBAAAAA==.',
Re='Regrowth:BAAANQADCggIIAAAAA==.Remaxed:BAAANQAECgIIAgAAAA==.',
Ri='Rimkalzkal:BAAANQADCggICAAAAA==.Riqis:BAAANQABCgIIAgAAAA==.',
Ru='Rummornia:BAAANQAECgUICwAAAA==.',
Sa='Sathenazagos:BAAANQAECgIIAgAAAA==.',
Se='Selesnia:BAAANQAECggIEwAAAA==.Sephiran:BAABNQAECn89AAQYAAoKxB6yCgCLAgAYAAoKxB6yCgCLAgAeAAQK9g/cFADbAAAXAAEKXAdO4AA0AAAAAA==.Seppuku:BAAANQAECgYICwAAAA==.',
Sh='Shaami:BAACNQAFFH8WAAMHAAcKqBOBAgA6AgAHAAcKqBOBAgA6AgAaAAEKAABPKQA9AAA1AAQKfzcAAxoACgpnHggUAFACABoACgpnHggUAFACAAcACgojG9gdAEECAAAA.Shaomei:BAABNQAECn8qAAMDAAoK5R3HPwCrAgADAAoK5R3HPwCrAgAfAAIKygZfdwBgAAAAAA==.',
Si='Sicario:BAAANQAECgMIBgAAAA==.',
Sk='Skye:BAAANQAECggIDQABNQAFFAkJMgAYAMAjAA==.',
St='Stabbingfang:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.Stdot:BAAANQAECgMIBAABNQAECgoKKwAUAJMXAA==.Stephirollsa:BAAANQAECgEIAQAAAA==.Stormstrike:BAAANQAECgMIBAAAAA==.Stothyr:BAAANQAECgcICwABNQAECgoKPwAEAIwmAA==.Strangulus:BAAANQABCgYIBgAAAA==.',
Sw='Sway:BAAANQAECggICQABNQAECgkJMAADALghAA==.',
Sy='Symwarrior:BAAANQADCgQIBAAAAA==.',
Ta='Taluria:BAAANQAECgIIBAAAAA==.Tayann:BAAANQAECgMIAwAAAA==.',
Ti='Tikimon:BAAANQADCggIGQAAAA==.Tindi:BAAANQADCgQIBAAAAA==.Tinkernine:BAABNQAECn8cAAMaAAcKdAm9YwA/AQAaAAcKdAm9YwA/AQAHAAEKjwF7hgATAAAAAA==.',
To='Tobofrog:BAAANQAECggIBgAAAA==.',
Tu='Turaht:BAABNQAECn80AAMRAAoKnRgzOgA6AgARAAoKhRQzOgA6AgAQAAgKphgkPwAaAQABNQAECggIDwABAAAAAA==.',
Ty='Tyrgrim:BAAANQAECgIIBAAAAA==.Tyronius:BAAANQADCgUIBQAAAA==.',
Ul='Uldyssian:BAABNQAECn9DAAQHAAoKnBsiFACpAgAHAAkKhx0iFACpAgAaAAcKyAzIMQBCAQAZAAkK9ArtJQAdAQABNQAFFAcIFAAJACMYAA==.',
Uw='Uwuforyou:BAABNQAECn8rAAIUAAoKkxcVFgA2AgAUAAoKkxcVFgA2AgAAAA==.',
Uz='Uzumaki:BAAANQAECgYIEAAAAA==.',
Ve='Velawynn:BAACNQAFFH8VAAIXAAcKOxeLBABgAgAXAAcKOxeLBABgAgA1AAQKfzkAAxcACgrkIPgQAEADABcACgrkIPgQAEADABgAAQokGONvAEkAAAAA.',
Vo='Voidâge:BAACNQAFFH8LAAMCAAYKsw+fKwAxAQACAAUKxA2fKwAxAQAWAAEKbxfqCgBeAAA1AAQKfyEAAgIACgphHYpyAJgCAAIACgphHYpyAJgCAAAA.',
Wy='Wysterian:BAAANQADCggIDQAAAA==.',
Xe='Xenu:BAACNQAFFH8HAAIdAAQKmQWoFgDEAAAdAAQKmQWoFgDEAAA1AAQKf0IAAh0ACgqvG/geAHQCAB0ACgqvG/geAHQCAAAA.',
Ya='Yanyan:BAAANQADCggICAAAAA==.',
Yu='Yukionna:BAAANQADCgQIAwAAAA==.',
Za='Zallann:BAAANQAECgQIBQAAAA==.',
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
