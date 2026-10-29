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

local lookup = {'Unknown-Unknown','Mage-Arcane','Hunter-BeastMastery','DemonHunter-Vengeance','DemonHunter-Devourer','Rogue-Subtlety','Paladin-Retribution','Evoker-Devastation','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Protection','Paladin-Holy','DeathKnight-Frost','Mage-Frost','Priest-Holy','Priest-Shadow','Druid-Feral','Druid-Balance','Warrior-Protection','Monk-Mistweaver','Druid-Guardian','DemonHunter-Havoc','Warlock-Demonology','Priest-Discipline','Druid-Restoration','Hunter-Marksmanship',}
local provider = {region='US',realm='Sentinels',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Absqwas:BAAANQADCgUIDAABNQADCgYIBgABAAAAAA==.',
Ac='Actaeon:BAAANQABCgEIAQAAAA==.',
Ad='Adaina:BAABNQAECn8qAAICAAoKegwDYACOAQACAAoKegwDYACOAQAAAA==.',
Ae='Ae:BAAANQADCgMIAwAAAA==.Aetherstrike:BAAANQAECgQIBAAAAA==.',
Ah='Aheeaheehahe:BAABNQAECn87AAIDAAoK+BwMGQCQAgADAAoK+BwMGQCQAgAAAA==.',
Ai='Ailanissa:BAAANQAECgcIDgAAAA==.Ailasaa:BAABNQAECn85AAMEAAoKgCZbAADkAwAEAAoKgCZbAADkAwAFAAYKOBZLMwCoAQAAAA==.Ainsley:BAAANQADCgUIBQAAAA==.',
Al='Alynddra:BAAANQAECgQICAAAAA==.',
An='Anbraxas:BAAANQAECgIIBAAAAA==.Antonson:BAABNQAECn8oAAIGAAoKeRH8GwD1AQAGAAoKeRH8GwD1AQAAAA==.',
Ao='Ao:BAAANQAECggIEgAAAA==.',
As='Asdanot:BAAANQAECgEIAQAAAA==.Astovidatu:BAAANQAECggICgAAAA==.',
At='Atanukki:BAAANQAECgUICgABNQAECgkJGwAHAEUiAA==.',
Au='Auroranova:BAABNQAECn8qAAIHAAgK6Qw6kQAvAQAHAAgK6Qw6kQAvAQAAAA==.',
Ax='Axél:BAAANQAECgQICwAAAA==.',
Ay='Ayblinkin:BAAANQADCgYJBgABNQAFFAMIBwAIADsDAA==.',
Ba='Ball:BAAANQAECggICAABNQAECggIEAABAAAAAA==.Balthazaar:BAAANQAECgEIAQAAAA==.',
Be='Berzquaza:BAAANQADCgYIBgAAAA==.',
Bl='Bluedreamm:BAAANQAECgEIAQAAAA==.',
Br='Braei:BAAANQAECgIIBAAAAA==.Brilleleante:BAAANQADCgcIEQAAAA==.Broxmorn:BAAANQADCgIIAgAAAA==.',
Ca='Canimai:BAAANQAECggICgAAAA==.Cappe:BAAANQABCgIIAgAAAA==.',
Ch='Chettybetty:BAAANQAECgMIBAAAAA==.',
Co='Cojul:BAABNQAECn8lAAIJAAgK1x21BADaAgAJAAgK1x21BADaAgAAAA==.',
Cr='Crazynaga:BAAANQADCggIDgAAAA==.Crisspy:BAABNQAECn8hAAMKAAkKQge/fwCNAQAKAAkKQge/fwCNAQALAAcK8wZrpABMAQAAAA==.',
Cu='Cubes:BAACNQAFFH8VAAIMAAcKZyQ0AQC9AgAMAAcKZyQ0AQC9AgA1AAQKfzEAAwwACgqKJrQGAGYDAAwACgqKJrQGAGYDAA0ABgrEHekUAJQBAAAA.',
De='Deadlylight:BAABNQAECn8WAAIHAAYKswhhHQHuAAAHAAYKswhhHQHuAAAAAA==.Deathcrocker:BAEBNQAECn8bAAMOAAoKrSAMCADQAgAOAAoKrSAMCADQAgAPAAMKqQIG4wAxAAABNQAFFAgIIwAQAEwkAA==.Demoniko:BAAANQADCgQIBAAAAA==.Denounce:BAACNQAFFH8MAAIRAAUKlB2YCADZAQARAAUKlB2YCADZAQA1AAQKfyoAAhEACgq/JTIDAL4DABEACgq/JTIDAL4DAAAA.Depthrootme:BAAANQAECgEIAQAAAA==.',
Di='Diddlerprime:BAAANQADCggIDwAAAA==.',
Do='Dogs:BAAANQAECgIIBQABNQAFFAcIHQADAHIhAA==.Domar:BAAANQAECgIIBAAAAA==.Doomslayer:BAABNQAECn8fAAMPAAkKgxluNABYAgAPAAkKCBhuNABYAgASAAYKRRc2UABzAQAAAA==.Dothippo:BAABNQAECn8dAAIJAAkKchLYDwAAAgAJAAkKchLYDwAAAgAAAA==.',
Dr='Drachunter:BAAANQADCgUIDwAAAA==.',
Du='Dumach:BAAANQADCggIDQAAAA==.',
Ea='Easy:BAABNQAECn8nAAIDAAkKhyBKFwCbAgADAAkKhyBKFwCbAgAAAA==.',
Eh='Ehrathorn:BAAANQADCgYIBgAAAA==.',
El='Elennoxx:BAAANQAECgIIBAAAAA==.Elonaara:BAAANQADCgcIBgAAAA==.',
Et='Etta:BAAANQADCgYIFgAAAA==.',
Ex='Exarchstrike:BAAANQADCgYIDgAAAA==.',
Fa='Fayce:BAAANQABCgYICgAAAA==.',
Fe='Feledara:BAAANQAECgQIBQAAAA==.Ferne:BAAANQADCgYICQAAAA==.Feylen:BAAANQAECgYICQAAAA==.',
Fl='Floof:BAAANQADCgMIAwAAAA==.',
Fr='Frieren:BAACNQAFFH8nAAMCAAcKvyRNAgDQAgACAAcK5yNNAgDQAgATAAEKAiI0CwBiAAA1AAQKfzYAAgIACgoJJlgHACMDAAIACgoJJlgHACMDAAAA.',
Ge='Gencrocker:BAECNQAFFH8jAAIQAAgKTCRiAADzAgAQAAgKTCRiAADzAgA1AAQKfxcAAhAACgoLIZEMANECABAACgoLIZEMANECAAAA.Getoffenris:BAAANQAECgIIBAAAAA==.',
Gl='Gloryhammer:BAAANQAECggICAAAAA==.',
Go='Gobbs:BAABNQAECn8VAAIGAAkKXhPvFwAeAgAGAAkKXhPvFwAeAgAAAA==.Golduck:BAAANQAECggIEAAAAA==.',
Gr='Gratagnan:BAAANQABCgEIAQAAAA==.Grimmi:BAAANQADCgEIAQAAAA==.Grosh:BAAANQADCgYIBgAAAA==.',
Ha='Haldrian:BAAANQAECgIIBAAAAA==.',
Ho='Hollydaye:BAAANQAECgQIDQAAAA==.Holyhota:BAACNQAFFH8IAAIUAAQKDRDNFwA1AQAUAAQKDRDNFwA1AQA1AAQKfx8AAxQACQp+HOEnAMoCABQACQp+HOEnAMoCABUAAwqXEONXAKsAAAAA.Holymolly:BAAANQADCgYIBgAAAA==.Holystrike:BAAANQADCgYIFwAAAA==.Hop:BAABNQAECn8rAAMWAAoKNxgyCgCaAgAWAAoKNxgyCgCaAgAXAAIKsQbApwBIAAAAAA==.',
Il='Ilos:BAAANQABCggIFQAAAA==.',
Ir='Iraedies:BAAANQABCgIIAgAAAA==.Ironborn:BAAANQAECgQICwAAAA==.',
Iv='Ivakor:BAAANQAECggIBwAAAA==.',
Ja='Jaes:BAAANQADCgUIBgAAAA==.Jaszuny:BAABNQAECn8tAAIEAAkK6Q0OCwAvAQAEAAkK6Q0OCwAvAQAAAA==.',
Je='Jeeyell:BAABNQAECn8mAAIYAAgK/RqJDgBFAgAYAAgK/RqJDgBFAgAAAA==.Jezlyn:BAAANQAECgEIAQAAAA==.',
Jo='Jo:BAAANQADCgYIDAAAAA==.Johnnyblaze:BAAANQADCgEIAQAAAA==.Johyah:BAACNQAFFH8KAAIZAAYKsRDXAwCwAQAZAAYKsRDXAwCwAQA1AAQKfysAAhkACgohIB4IAA8DABkACgohIB4IAA8DAAAA.',
['Jö']='Jösîah:BAAANQADCgEIAQAAAA==.',
Ka='Kalafuzz:BAAANQAECgYIBgABNQAFFAIIBgAQALwVAA==.Karkara:BAABNQAECn8dAAMSAAgK2xnxNAAIAgASAAgK+hbxNAAIAgAOAAQKnBtpQADfAAAAAA==.Karrthis:BAAANQAECgUICQAAAA==.Karrthus:BAAANQAECgUIBQABNQAECgUICQABAAAAAA==.Katsumotosan:BAAANQADCgcICwAAAA==.',
Ke='Kemstrio:BAABNQAECn8dAAMaAAgKzx7sEwAlAgAaAAYKkyDsEwAlAgAXAAMKuhruNQD0AAABNQAFFAUIDQAEAMEfAA==.Kev:BAABNQAECn8eAAMCAAoKZRqiqwArAgACAAkKmhqiqwArAgATAAEK8hjYPQBJAAAAAA==.',
Ko='Kombatgodess:BAAANQADCgYIDAAAAA==.Kordraan:BAAANQADCgQIBAAAAA==.',
Kr='Krael:BAAANQAECggIBgAAAA==.',
Ks='Kspboop:BAEANQAECgcIBAAAAA==.',
Ku='Kurag:BAAANQAECgEIAQAAAA==.Kurvios:BAABNQAECn8oAAMEAAkKZx0DBwCUAQAbAAkK7RweIgCKAgAEAAgKzRgDBwCUAQABNQAECgoKNQAVAMQeAA==.Kuurgan:BAAANQAECgQIDAAAAA==.',
Kv='Kvasir:BAAANQAECgMIBgABNQAECggIJQAJANcdAA==.',
Li='Lichkingstoy:BAACNQAFFH8MAAIHAAUK6xDmFwDpAAAHAAUK6xDmFwDpAAA1AAQKf0wAAgcACgqyIOI1APYCAAcACgqyIOI1APYCAAAA.Light:BAAANQAECggIBAABNQAECgkJJwADAIcgAA==.Lizardboi:BAAANQAECgcIEQAAAA==.',
Ll='Llilth:BAAANQADCgEIAQAAAA==.',
Ma='Magicstrike:BAAANQADCgcIEgAAAA==.Manistas:BAAANQADCgMIAwAAAA==.Manta:BAAANQAECgcIDwAAAA==.',
Mi='Miracle:BAAANQAECgIIBAAAAA==.Mirana:BAAANQADCgIIAgAAAA==.',
Mo='Morelinne:BAAANQADCgUIDQAAAA==.',
My='Mykeexd:BAAANQADCgQIBAAAAA==.Mykehoochie:BAAANQADCgQIAwAAAA==.',
Na='Nabarke:BAAANQAECgIIBAAAAA==.Naidomsa:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Nathanos:BAAANQAECgQIBwABNQAECgoKNQAVAMQeAA==.Naturestrike:BAAANQAECgUIBQAAAA==.',
Ne='Nexaliah:BAAANQAECgMIBQABNQAFFAYIEwAHAL8cAA==.Nezath:BAAANQAECggIDgABNQAECgoKOgAcAAsiAA==.',
Ni='Nier:BAAANQAECgQICgAAAA==.',
No='Noisemarine:BAABNQAECn8qAAIYAAkKWgpqHgBhAQAYAAkKWgpqHgBhAQAAAA==.Nooxi:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Nospheratus:BAABNQAECn8gAAMaAAoKdBWUFQAQAgAaAAoKiROUFQAQAgAWAAcKUxIDDwA7AQABNQAFFAUICgAOAIgMAA==.Noub:BAAANQADCgYJBgAAAA==.',
Nx='Nx:BAAANQAECgEIAQAAAA==.',
Ny='Nylianna:BAACNQAFFH8TAAIHAAYKvxyjBABJAQAHAAYKvxyjBABJAQA1AAQKfyoAAgcACgo3JOk6AOYCAAcACgo3JOk6AOYCAAAA.',
Ob='Obilesk:BAAANQADCgcIBwAAAA==.',
Og='Ogganborn:BAAANQAECgYIDAAAAA==.',
Ph='Phoenïx:BAAANQABCgYICQAAAA==.',
Pi='Pikal:BAABNQAECn8VAAQHAAkKSA5A1gBvAQAHAAgKSA5A1gBvAQARAAUKIwMm4wC6AAAQAAEKAAADeAAlAAAAAA==.',
Pr='Priestaline:BAABNQAECn8iAAILAAoKwBPGZQDvAQALAAoKwBPGZQDvAQAAAA==.Priestigory:BAABNQAECn8ZAAMNAAoKARTsEADaAQANAAkKpBTsEADaAQAMAAEKjg8qRgA7AAAAAA==.Prosper:BAAANQAECgEIAQAAAA==.',
Pv='Pvtcrocker:BAEBNQAFFH8IAAIaAAUKzBJYAgB1AQAaAAUKzBJYAgB1AQABNQAFFAgIIwAQAEwkAA==.',
Qu='Quintus:BAABNQAECn8mAAIHAAkK5x7VPQDcAgAHAAkK5x7VPQDcAgAAAA==.',
Ra='Ra:BAAANQAECggIEAAAAA==.Railiana:BAAANQADCgQIBAAAAA==.',
Re='Regrowth:BAAANQADCggIIAAAAA==.Remaxed:BAAANQAECgIIAgAAAA==.',
Ri='Rimkalzkal:BAAANQADCggICAAAAA==.Riqis:BAAANQABCgIIAgAAAA==.',
Ru='Rummornia:BAAANQAECgUICwAAAA==.',
Sa='Sathenazagos:BAAANQAECgIIAgAAAA==.',
Se='Selesnia:BAAANQAECggIDgAAAA==.Sephiran:BAABNQAECn81AAQVAAoKxB7WDgAEAwAVAAoKxB7WDgAEAwAdAAQK9g/cFADbAAAUAAEKXAfvyAA0AAAAAA==.Seppuku:BAAANQAECgYICwAAAA==.',
Sh='Shaami:BAACNQAFFH8WAAMeAAcKqBOBAgA6AgAeAAcKqBOBAgA6AgAXAAEKAABPKQA9AAA1AAQKfzQAAxcACgpnHgoOAGkCABcACgpnHgoOAGkCAB4ACgpPGtgdAEECAAAA.Shaomei:BAABNQAECn8nAAMDAAoKdhzHPwCrAgADAAoKdhzHPwCrAgAfAAIKygZfdwBgAAAAAA==.',
Si='Sicario:BAAANQAECgMIBgAAAA==.',
Sk='Skye:BAAANQAECggIDQABNQAFFAkJLAAVAAciAA==.',
St='Stabbingfang:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.Stdot:BAAANQAECgMIBAAAAA==.Stephirollsa:BAAANQAECgEIAQAAAA==.Stormstrike:BAAANQAECgMIBAAAAA==.Stothyr:BAAANQAECgcICgABNQAECgoKOQAEAIAmAA==.Strangulus:BAAANQABCgYIBgAAAA==.',
Sw='Sway:BAAANQAECggICQABNQAECgkJJwADAIcgAA==.',
Sy='Symwarrior:BAAANQADCgQIBAAAAA==.',
Ta='Taluria:BAAANQAECgIIBAAAAA==.Tayann:BAAANQAECgMIAwAAAA==.',
Ti='Tikimon:BAAANQADCggIGQAAAA==.Tindi:BAAANQADCgQIBAAAAA==.Tinkernine:BAABNQAECn8cAAMXAAcKdAm9YwA/AQAXAAcKdAm9YwA/AQAeAAEKjwF7hgATAAAAAA==.',
To='Tobofrog:BAAANQAECggIBgAAAA==.',
Tu='Turaht:BAABNQAECn8wAAMPAAoKZRZwHACQAQAOAAYK7xjIVgCYAQAPAAoKhRRwHACQAQABNQAECggICgABAAAAAA==.',
Ty='Tyrgrim:BAAANQAECgIIBAAAAA==.Tyronius:BAAANQADCgUIBQAAAA==.',
Ul='Uldyssian:BAABNQAECn86AAMeAAoKnBsiFACpAgAeAAkKhx0iFACpAgAaAAkK9AolHAApAQABNQAFFAYIEwAHAL8cAA==.',
Uw='Uwuforyou:BAABNQAECn8hAAIbAAoKuhFMGADiAQAbAAoKuhFMGADiAQAAAA==.',
Uz='Uzumaki:BAAANQAECgYICQAAAA==.',
Ve='Velawynn:BAACNQAFFH8VAAIUAAcKOxeLBABgAgAUAAcKOxeLBABgAgA1AAQKfzkAAxQACgrkIPgQAEADABQACgrkIPgQAEADABUAAQokGONvAEkAAAAA.',
Vo='Voidâge:BAACNQAFFH8KAAICAAUKxA2fKwAxAQACAAUKxA2fKwAxAQA1AAQKfyAAAgIACgo8HYpyAJgCAAIACgo8HYpyAJgCAAAA.',
Wy='Wysterian:BAAANQADCggIDQAAAA==.',
Xe='Xenu:BAABNQAECn85AAIcAAoK/xgLHQBQAgAcAAoK/xgLHQBQAgAAAA==.',
Ya='Yanyan:BAAANQADCggICAAAAA==.',
Yu='Yukionna:BAAANQADCgQIAwAAAA==.',
Za='Zallann:BAAANQAECgEIAQAAAA==.',
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
