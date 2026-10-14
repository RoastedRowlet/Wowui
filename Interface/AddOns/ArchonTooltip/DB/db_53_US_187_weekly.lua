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

local lookup = {'Unknown-Unknown','Mage-Arcane','Hunter-BeastMastery','DemonHunter-Vengeance','DemonHunter-Devourer','Rogue-Subtlety','Paladin-Retribution','Evoker-Devastation','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Brewmaster','Paladin-Protection','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Mage-Frost','Priest-Holy','Priest-Shadow','Druid-Feral','Druid-Balance','Warrior-Protection','Monk-Mistweaver','Druid-Guardian','DemonHunter-Havoc','Evoker-Preservation','Evoker-Augmentation','Warlock-Demonology','DeathKnight-Blood','Priest-Discipline','Druid-Restoration','Hunter-Marksmanship',}
local provider = {region='US',realm='Sentinels',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Absqwas:BAAANQADCgUIDAABNQADCgYIBgABAAAAAA==.',
Ac='Actaeon:BAAANQAECgEIAQAAAA==.',
Ad='Adaina:BAABNQAECn8hAAICAAgKuQxb1gDXAQACAAgKuQxb1gDXAQAAAA==.',
Ae='Ae:BAAANQADCgMIAwAAAA==.Aetherstrike:BAAANQADCgYIDAAAAA==.',
Ah='Aheeaheehahe:BAABNQAECn8sAAIDAAkKlhpsMgDTAgADAAkKlhpsMgDTAgAAAA==.',
Ai='Ailanissa:BAAANQAECgYIDgAAAA==.Ailasaa:BAABNQAECn8vAAMEAAkKeiZbAADkAwAEAAkKeiZbAADkAwAFAAYKOBasMgCoAQAAAA==.Ainsley:BAAANQADCgUIBQAAAA==.',
Al='Alynddra:BAAANQAECgQICgAAAA==.',
An='Anbraxas:BAAANQAECgIIBAAAAA==.Antonson:BAABNQAECn8fAAIGAAgKcg6lGwD1AQAGAAgKcg6lGwD1AQAAAA==.',
Ao='Ao:BAAANQAECggIEgAAAA==.',
As='Astovidatu:BAAANQAECggIAgAAAA==.',
At='Atanukki:BAAANQAECgUICgABNQAECggIEQABAAAAAA==.',
Au='Auroranova:BAABNQAECn8hAAIHAAcK0w02ywB/AQAHAAcK0w02ywB/AQAAAA==.',
Ax='Axél:BAAANQAECgIIBAAAAA==.',
Ay='Ayblinkin:BAAANQADCgYJBgABNQAFFAMIBwAIADsDAA==.',
Ba='Ball:BAAANQAECgIIAgAAAA==.Balthazaar:BAAANQAECgEIAQAAAA==.',
Be='Berzquaza:BAAANQADCgYIBgAAAA==.',
Bl='Bluedreamm:BAAANQAECgEIAQAAAA==.',
Br='Braei:BAAANQAECgIIBAAAAA==.Brilleleante:BAAANQADCgcIEQAAAA==.Broxmorn:BAAANQADCgIIAgAAAA==.',
Ca='Canimai:BAAANQAECgEIAgAAAA==.',
Ch='Chettybetty:BAAANQAECgIIAgAAAA==.',
Co='Cojul:BAABNQAECn8eAAIJAAgK1x2uBADbAgAJAAgK1x2uBADbAgAAAA==.',
Cr='Crazynaga:BAAANQADCggIDgAAAA==.Crisspy:BAABNQAECn8hAAMKAAkKQgdofgCNAQAKAAkKQgdofgCNAQALAAcK8wZUogBMAQAAAA==.',
Cu='Cubes:BAACNQAFFH8VAAIMAAcKZyQlAQC9AgAMAAcKZyQlAQC9AgA1AAQKfycAAwwACQqLJosGAGYDAAwACQqLJosGAGYDAA0ABgrEHawUAJUBAAAA.',
De='Deadlylight:BAAANQAECgQIEAAAAA==.Deathcrocker:BAEANQAECggIDwABNQAFFAcIIAAOADMlAA==.Demoniko:BAAANQADCgQIBAAAAA==.Denounce:BAACNQAFFH8MAAIPAAUKlB1SCADaAQAPAAUKlB1SCADaAQA1AAQKfyQAAg8ACQqIJRsDAL8DAA8ACQqIJRsDAL8DAAAA.Depthrootme:BAAANQAECgEIAgAAAA==.Dertrois:BAAANQAECgEIAQAAAA==.',
Di='Diddlerprime:BAAANQADCggIDwAAAA==.',
Do='Dogs:BAAANQAECgIIBQABNQAFFAUIFQADAIYmAA==.Domar:BAAANQAECgIIBAAAAA==.Doomslayer:BAABNQAECn8fAAMQAAkKgxnnMwBYAgAQAAkKCBjnMwBYAgARAAYKRRe3TgBzAQAAAA==.Dothippo:BAABNQAECn8bAAIJAAgKARK9DwAAAgAJAAgKARK9DwAAAgAAAA==.',
Dr='Drachunter:BAAANQADCgUICwAAAA==.',
Ea='Easy:BAABNQAECn8ZAAIDAAgK0h9nKQDxAgADAAgK0h9nKQDxAgAAAA==.',
Eh='Ehrathorn:BAAANQADCgYIBgAAAA==.',
El='Elennoxx:BAAANQAECgIIBAAAAA==.',
Et='Etta:BAAANQADCgYIEQAAAA==.',
Ex='Exarchstrike:BAAANQADCgYIDgAAAA==.',
Fa='Fayce:BAAANQAECgEIAQAAAA==.',
Fe='Feledara:BAAANQAECgEIAQAAAA==.Ferne:BAAANQADCgYICQAAAA==.Feylen:BAAANQAECgEJAQAAAA==.',
Fl='Floof:BAAANQADCgMIAwAAAA==.',
Fr='Frieren:BAACNQAFFH8fAAMCAAcKvyQlAgDQAgACAAcK5yMlAgDQAgASAAEKAiLrCgBjAAA1AAQKfysAAgIACQo4JtMRAIsDAAIACQo4JtMRAIsDAAAA.',
Ge='Gencrocker:BAECNQAFFH8gAAIOAAcKMyVeAADzAgAOAAcKMyVeAADzAgA1AAQKfxUAAg4ACQqGIG4MANECAA4ACQqGIG4MANECAAAA.Getoffenris:BAAANQAECgIIBAAAAA==.',
Gl='Gloryhammer:BAAANQAECggICAAAAA==.',
Go='Gobbs:BAAANQAECggIEgAAAA==.',
Gr='Gratagnan:BAAANQABCgEIAQAAAA==.Grimmi:BAAANQADCgEIAQAAAA==.Grosh:BAAANQADCgYJBgAAAA==.',
Ha='Haldrian:BAAANQAECgIIBAAAAA==.',
Ho='Hollydaye:BAAANQAECgMICQAAAA==.Holyhota:BAACNQAFFH8IAAITAAQKDRA2FwA1AQATAAQKDRA2FwA1AQA1AAQKfx8AAxMACQp+HDgnAMsCABMACQp+HDgnAMsCABQAAwqXENxWAKsAAAAA.Holymolly:BAAANQADCgYIBgAAAA==.Holyrhota:BAAANQAECgEIAQABNQAFFAQICAATAA0QAA==.Holystrike:BAAANQADCgYIFwAAAA==.Hop:BAABNQAECn8kAAMVAAgKZhgKCgCbAgAVAAgKZhgKCgCbAgAWAAIKsQbspQBIAAAAAA==.',
Il='Ilos:BAAANQABCggIDgAAAA==.',
Ir='Iraedies:BAAANQABCgIIAgAAAA==.Ironborn:BAAANQAECgMIBAAAAA==.',
Iv='Ivakor:BAAANQAECgQIBgAAAA==.',
Ja='Jaes:BAAANQADCgQIBQAAAA==.Jaszuny:BAABNQAECn8fAAIEAAgKqA2rEQCRAQAEAAgKqA2rEQCRAQAAAA==.',
Je='Jeeyell:BAABNQAECn8mAAIXAAgK/RpWDgBGAgAXAAgK/RpWDgBGAgAAAA==.Jezlyn:BAAANQAECgEIAQAAAA==.',
Jo='Johnnyblaze:BAAANQADCgEIAQAAAA==.Johyah:BAACNQAFFH8KAAIYAAYKsRC/AwCwAQAYAAYKsRC/AwCwAQA1AAQKfycAAhgACQqVH/oHAA8DABgACQqVH/oHAA8DAAAA.',
['Jö']='Jösîah:BAAANQADCgEIAQAAAA==.',
Ka='Kalafuzz:BAAANQAECgYIBgABNQAECgkJKgAOADQiAA==.Karkara:BAABNQAECn8ZAAIRAAgK+hbxMwAIAgARAAgK+hbxMwAIAgAAAA==.Karrthus:BAAANQAECgUIBgAAAA==.Katsumotosan:BAAANQADCgQIBAAAAA==.',
Ke='Kemstrio:BAABNQAECn8WAAMZAAcKAh6GEwAlAgAZAAYKkyCGEwAlAgAWAAEKLBG2qABBAAABNQAFFAMICQAEADogAA==.Kev:BAABNQAECn8bAAMCAAgKNxo3qgAsAgACAAcKeBo3qgAsAgASAAEK8hgPPQBJAAAAAA==.',
Ko='Kombatgodess:BAAANQADCgYIDAAAAA==.Kordraan:BAAANQAECgEIAQAAAA==.',
Kr='Krael:BAAANQAECggIBgAAAA==.',
Ks='Kspboop:BAEANQAECgcIBAAAAA==.',
Ku='Kurag:BAAANQAECgEIAQAAAA==.Kurvios:BAABNQAECn8dAAMaAAcKayCEIQCLAgAaAAcKayCEIQCLAgAEAAEK5hnlLABMAAABNQAECggIKwAUAO4fAA==.Kuurgan:BAAANQAECgQIDAAAAA==.',
Kv='Kvasir:BAAANQAECgMICAABNQAECggIHgAJANcdAA==.',
Li='Lichkingstoy:BAACNQAFFH8JAAIHAAMK8RA5FwDpAAAHAAMK8RA5FwDpAAA1AAQKfzsAAgcACQqCH8U0APcCAAcACQqCH8U0APcCAAAA.Light:BAAANQAECggIBAABNQAECggIGQADANIfAA==.Lizardboi:BAABNQAECn8UAAQbAAgKUBY4FwBEAgAbAAgKUBY4FwBEAgAIAAIKgwLbOABDAAAcAAEKAAARKAAfAAAAAA==.',
Ma='Magicstrike:BAAANQADCgcIEgAAAA==.Manistas:BAAANQADCgMIAwAAAA==.Manta:BAAANQAECgcIEQAAAA==.',
Mi='Miracle:BAAANQAECgIIBAAAAA==.Mirana:BAAANQADCgIIAgAAAA==.',
Mo='Morelinne:BAAANQADCgUIDQAAAA==.',
My='Mykeexd:BAAANQADCgQIBAAAAA==.Mykehoochie:BAAANQADCgQIAwAAAA==.',
Na='Nabarke:BAAANQAECgIIBAAAAA==.Naidomsa:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Nathanos:BAAANQAECgIIBQABNQAECggIKwAUAO4fAA==.Naturestrike:BAAANQADCggIIAAAAA==.',
Ne='Nezath:BAAANQAECggIDgABNQAECgkJMAAdADgbAA==.',
Ni='Nier:BAAANQAECgMIBgAAAA==.',
No='Noisemarine:BAABNQAECn8iAAIXAAgKSgn8HQBhAQAXAAgKSgn8HQBhAQAAAA==.Nooxi:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Nospheratus:BAABNQAECn8XAAMZAAgKIhY1FQAPAgAZAAgK+hU1FQAPAgAVAAQKiQ2cJQDdAAABNQAFFAMICAAeAAwOAA==.Noub:BAAANQADCgYJBgAAAA==.',
Nx='Nx:BAAANQAECgEIAQAAAA==.',
Ny='Nylianna:BAACNQAFFH8OAAIHAAUKKR9cCQCvAQAHAAUKKR9cCQCvAQA1AAQKfyIAAgcACQpIIsI5AOcCAAcACQpIIsI5AOcCAAAA.',
Ob='Obilesk:BAAANQADCgcIBwAAAA==.',
Og='Ogganborn:BAAANQAECgMIBAAAAA==.',
Ph='Phoenïx:BAAANQAECgEIAQAAAA==.',
Pi='Pikal:BAAANQAECgcIEwAAAA==.',
Pr='Priestaline:BAABNQAECn8dAAILAAgK9xNqZADwAQALAAgK9xNqZADwAQAAAA==.Priestigory:BAABNQAECn8XAAINAAgK8BOtEADbAQANAAgK8BOtEADbAQAAAA==.Prosper:BAAANQAECgEIAQAAAA==.',
Pv='Pvtcrocker:BAEBNQAFFH8IAAIZAAUKzBJKAgB1AQAZAAUKzBJKAgB1AQABNQAFFAcIIAAOADMlAA==.',
Qu='Quintus:BAABNQAECn8aAAIHAAkKrhaXPADdAgAHAAkKrhaXPADdAgAAAA==.',
Ra='Ra:BAAANQAECggIDwAAAA==.Railiana:BAAANQADCgQIBAAAAA==.Ravelin:BAAANQADCgYIDAAAAA==.',
Re='Regrowth:BAAANQADCggIEwAAAA==.Remaxed:BAAANQAECgIIAgAAAA==.',
Ri='Riqis:BAAANQABCgIIAgAAAA==.',
Ru='Rummornia:BAAANQAECgUICwAAAA==.',
Sa='Sathenazagos:BAAANQAECgIIAgAAAA==.',
Se='Selesnia:BAAANQAECggIDAAAAA==.Sephiran:BAABNQAECn8rAAMUAAgK7h+fDgAEAwAUAAgK7h+fDgAEAwAfAAQK9g+wFADbAAAAAA==.Seppuku:BAAANQAECgYIEAAAAA==.',
Sh='Shaami:BAACNQAFFH8WAAMgAAcKqBNRAgA9AgAgAAcKqBNRAgA9AgAWAAEKAACsKAA9AAA1AAQKfyoAAyAACQr9GoYdAEACACAACQr9GoYdAEACABYABgoPIJVAAPQBAAAA.Shaomei:BAABNQAECn8bAAMDAAkK9RZ8PgCtAgADAAkK9RZ8PgCtAgAhAAIKygbPdQBgAAAAAA==.',
Si='Sicario:BAAANQADCgEIAQAAAA==.',
Sk='Skye:BAAANQAECggICgABNQAFFAkJJgAUAPkhAA==.',
St='Stabbingfang:BAAANQAECgEIAQABNQAECgQICgABAAAAAA==.Stdot:BAAANQAECgMIBAAAAA==.Stephirollsa:BAAANQAECgEIAQAAAA==.Stormstrike:BAAANQAECgMIAwAAAA==.Stothyr:BAAANQAECgUICAABNQAECgkJLwAEAHomAA==.Strangulus:BAAANQABCgYIBgAAAA==.',
Sw='Sway:BAAANQAECggICwABNQAECggIGQADANIfAA==.',
Sy='Symwarrior:BAAANQADCgQIBAAAAA==.',
Ta='Taluria:BAAANQAECgIIBAAAAA==.Tayann:BAAANQAECgMIBAAAAA==.',
Ti='Tikimon:BAAANQADCgcIGQAAAA==.Tindi:BAAANQADCgQIBAAAAA==.Tinkernine:BAABNQAECn8YAAMWAAcK/AjSYgA/AQAWAAcK/AjSYgA/AQAgAAEKjwE/hAATAAAAAA==.',
To='Tobofrog:BAAANQAECggIBwAAAA==.',
Tu='Turaht:BAABNQAECn8oAAMQAAkK9xepOQA6AgAQAAkK0hWpOQA6AgAeAAYK7xgDVgCZAQABNQAECgEIAgABAAAAAA==.',
Ty='Tyrgrim:BAAANQAECgIIBAAAAA==.Tyronius:BAAANQADCgUIBQAAAA==.',
Ul='Uldyssian:BAABNQAECn8nAAIgAAgKqBzXEwCpAgAgAAgKqBzXEwCpAgABNQAFFAUIDgAHACkfAA==.',
Uw='Uwuforyou:BAAANQAECgcIEQAAAA==.',
Uz='Uzumaki:BAAANQAECgMIBgAAAA==.',
Ve='Velawynn:BAACNQAFFH8VAAITAAcKOxdFBABgAgATAAcKOxdFBABgAgA1AAQKfy4AAxMACQplIKQQAEADABMACQplIKQQAEADABQAAQokGHhuAEkAAAAA.',
Vo='Voidâge:BAACNQAFFH8JAAICAAQKuxCXKgAxAQACAAQKuxCXKgAxAQA1AAQKfxwAAgIACQqBHXhxAJoCAAIACQqBHXhxAJoCAAAA.',
Wy='Wysterian:BAAANQAECgEIAQAAAA==.',
Xe='Xenu:BAABNQAECn8kAAIdAAgK5BhqRwB5AgAdAAgK5BhqRwB5AgAAAA==.',
Ya='Yanyan:BAAANQADCggICAAAAA==.',
Yu='Yukionna:BAAANQADCgQIAwAAAA==.',
Zu='Zubang:BAAANQAECggIBQAAAA==.',
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
