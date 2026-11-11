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

local lookup = {'Unknown-Unknown','Mage-Arcane','Hunter-BeastMastery','DemonHunter-Vengeance','DemonHunter-Devourer','Rogue-Subtlety','Druid-Restoration','Druid-Feral','Paladin-Retribution','Evoker-Devastation','Warrior-Fury','Warrior-Protection','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Protection','Paladin-Holy','DemonHunter-Havoc','DeathKnight-Frost','Mage-Frost','Priest-Holy','Priest-Shadow','Druid-Guardian','Druid-Balance','Monk-Mistweaver','Mage-Fire','Warlock-Demonology','Priest-Discipline','Hunter-Marksmanship',}
local provider = {region='US',realm='Sentinels',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Absqwas:BAAANQADCgUIDAABNQADCgYIBgABAAAAAA==.',
Ac='Actaeon:BAAANQABCgEIAQAAAA==.',
Ad='Adaina:BAABNQAECn82AAICAAoKUQ3dfgCaAQACAAoKUQ3dfgCaAQAAAA==.',
Ae='Ae:BAAANQADCgMIAwAAAA==.Aetherstrike:BAAANQAECgUICQAAAA==.',
Ah='Aheeaheehahe:BAABNQAECn9HAAIDAAoKiB2NKACQAgADAAoKiB2NKACQAgAAAA==.',
Ai='Ailanissa:BAAANQAECggIEgAAAA==.Ailasaa:BAABNQAECn8/AAMEAAoKjCZbAADkAwAEAAoKjCZbAADkAwAFAAYKOBZLMwCoAQAAAA==.Ainsley:BAAANQADCgUIBQAAAA==.',
Al='Alynddra:BAAANQAECgQICAAAAA==.',
An='Anbraxas:BAAANQAECgIIBAAAAA==.Antonson:BAABNQAECn80AAIGAAoKABL8GwD1AQAGAAoKABL8GwD1AQAAAA==.',
Ao='Ao:BAABNQAECn8dAAMHAAoKehwCFwBHAgAHAAkKOB4CFwBHAgAIAAQKRQbjLACrAAAAAA==.',
As='Asdanot:BAAANQAECgEIAQAAAA==.Astovidatu:BAABNQAECn8bAAIJAAoKjQt2jgCaAQAJAAoKjQt2jgCaAQAAAA==.',
At='Atanukki:BAAANQAECgUICwABNQAECgkJHgAJAN8jAA==.',
Au='Auroranova:BAABNQAECn8xAAIJAAkKnQySqQBlAQAJAAkKnQySqQBlAQAAAA==.',
Ax='Axél:BAAANQAECgUIEAAAAA==.',
Ay='Ayblinkin:BAAANQADCgYJBgABNQAFFAMIBwAKADsDAA==.Aylaani:BAAANQADCgYIBgAAAA==.',
Ba='Ball:BAAANQAECggICwABNQAECggIEAABAAAAAA==.Balthazaar:BAAANQAECgEIAQAAAA==.',
Be='Berzquaza:BAAANQADCgYIBgAAAA==.',
Bl='Bluedreamm:BAAANQAECgEIAgAAAA==.',
Br='Braei:BAAANQAECgIIBAAAAA==.Brilleleante:BAAANQADCgcIEQAAAA==.Broxmorn:BAAANQADCgIIAgAAAA==.',
Ca='Canimai:BAABNQAECn8WAAMLAAoKLhl7CgDRAQALAAoK3BB7CgDRAQAMAAcK7h4LDgC/AQAAAA==.Cappe:BAAANQAECgEIAgAAAA==.',
Ch='Chettybetty:BAAANQAECgYIDAAAAA==.',
Co='Cojul:BAABNQAECn8lAAINAAgK1x21BADaAgANAAgK1x21BADaAgAAAA==.',
Cr='Crazynaga:BAAANQADCggIDgAAAA==.Crisspy:BAABNQAECn8hAAMOAAkKQge/fwCNAQAOAAkKQge/fwCNAQAPAAcK8wZrpABMAQAAAA==.',
Cu='Cubes:BAACNQAFFH8WAAIQAAgK1CQ0AQC9AgAQAAgK1CQ0AQC9AgA1AAQKfzoAAxAACgrKJqIAAIcDABAACgrKJqIAAIcDABEABgrEHekUAJQBAAAA.',
De='Deadlylight:BAABNQAECn8oAAIJAAoK5QkEkQCVAQAJAAoK5QkEkQCVAQAAAA==.Deathcrocker:BAECNQAFFH8GAAISAAYKxBQgDAAlAQASAAYKxBQgDAAlAQA1AAQKfyMAAxIACgo0IQYMAMwCABIACgo0IQYMAMwCABMAAwqpAgbjADEAAAE1AAUUCAgkABQATCQA.Demoniko:BAAANQADCgQIBAAAAA==.Denounce:BAACNQAFFH8MAAIVAAUKlB2YCADZAQAVAAUKlB2YCADZAQA1AAQKfyoAAhUACgq/JTIDAL4DABUACgq/JTIDAL4DAAAA.Depthrootme:BAAANQAECgEIAQABNQAECgoKNAAWAKEaAA==.',
Di='Diddlerprime:BAAANQADCggIDwAAAA==.Diocletian:BAAANQAECgIIAQAAAA==.',
Do='Dogs:BAAANQAECgIICQABNQAFFAcIHQADAHIhAA==.Domar:BAAANQAECgIIBAAAAA==.Doomslayer:BAABNQAECn8fAAMTAAkKgxluNABYAgATAAkKCBhuNABYAgAXAAYKRRc2UABzAQAAAA==.Dothippo:BAABNQAECn8tAAINAAkKyxQeBADGAQANAAkKyxQeBADGAQAAAA==.',
Dr='Drachunter:BAAANQADCgUIDwAAAA==.',
Du='Dumach:BAAANQADCggIDQAAAA==.',
Ea='Easy:BAABNQAECn8wAAIDAAkKuCEdFgDlAgADAAkKuCEdFgDlAgAAAA==.',
Eh='Ehrathorn:BAAANQADCgYIBgAAAA==.',
El='Elennoxx:BAAANQAECgIIBAAAAA==.Elonaara:BAAANQADCgcIBgAAAA==.',
En='Enixia:BAAANQAECgEIAQAAAA==.',
Et='Etta:BAAANQADCgYIFgAAAA==.',
Ex='Exarchstrike:BAAANQAECgIIAgAAAA==.',
Fa='Fayce:BAAANQABCgYICgAAAA==.',
Fe='Feledara:BAAANQAECggIDgAAAA==.Ferne:BAAANQADCgYICQAAAA==.Feylen:BAAANQAECgYIDAAAAA==.',
Fl='Floof:BAAANQADCgMIAwAAAA==.',
Fr='Frieren:BAACNQAFFH8qAAMCAAgKBiJNAgDQAgACAAgKUiFNAgDQAgAYAAEKAiI0CwBiAAA1AAQKfzkAAgIACgoKJk0SAIkDAAIACgoKJk0SAIkDAAAA.',
Ge='Gencrocker:BAECNQAFFH8kAAIUAAgKTCRiAADzAgAUAAgKTCRiAADzAgA1AAQKfxgAAhQACgoLIZEMANECABQACgoLIZEMANECAAAA.Getoffenris:BAAANQAECgIIBAAAAA==.',
Gl='Gloryhammer:BAAANQAECggICAAAAA==.',
Go='Gobbs:BAABNQAECn8eAAIGAAoK9xLvFwAeAgAGAAoK9xLvFwAeAgAAAA==.Golduck:BAAANQAECggIEAAAAA==.',
Gr='Gratagnan:BAAANQABCgEIAQAAAA==.Grimmi:BAAANQADCgEIAQAAAA==.Grosh:BAAANQADCgYIBgAAAA==.',
Ha='Haldrian:BAAANQAECgIIBAAAAA==.',
Ho='Hollydaye:BAABNQAECn8ZAAICAAYKMgIJDwGLAAACAAYKMgIJDwGLAAAAAA==.Holyhota:BAACNQAFFH8IAAIZAAQKDRDNFwA1AQAZAAQKDRDNFwA1AQA1AAQKfx8AAxkACQp+HOEnAMoCABkACQp+HOEnAMoCABoAAwqXEONXAKsAAAAA.Holymolly:BAAANQADCgYIBgAAAA==.Holystrike:BAAANQADCgYIFwAAAA==.Hop:BAABNQAECn8zAAQIAAoK+RgyCgCaAgAIAAoK+RgyCgCaAgAbAAQK3A22RQCUAAAcAAIKsQbApwBIAAAAAA==.',
Il='Ilos:BAAANQABCggIHQAAAA==.',
Ir='Iraedies:BAAANQABCgIIAgAAAA==.Ironborn:BAAANQAECgUIEgAAAA==.',
Iv='Ivakor:BAAANQAECgcIEQAAAA==.',
Ja='Jaes:BAAANQADCgUIBgAAAA==.Jaszuny:BAABNQAECn9AAAIEAAoK2A8wCwCMAQAEAAoK2A8wCwCMAQAAAA==.',
Je='Jeeyell:BAABNQAECn8mAAIMAAgK/RqJDgBFAgAMAAgK/RqJDgBFAgAAAA==.Jezlyn:BAAANQAECgEIAQAAAA==.',
Jo='Jo:BAAANQADCgYIDAAAAA==.Johnnyblaze:BAAANQAECgEIAQAAAA==.Johyah:BAACNQAFFH8LAAIdAAcKmhHXAwCwAQAdAAcKmhHXAwCwAQA1AAQKfzQAAh0ACgpvIR4IAA8DAB0ACgpvIR4IAA8DAAAA.',
['Jö']='Jösîah:BAAANQADCgEIAQAAAA==.',
Ka='Kalafuzz:BAAANQAECgYIBgABNQAFFAUIDQAUAFEaAA==.Karkara:BAABNQAECn8fAAMXAAoKPxnxNAAIAgAXAAgK+hbxNAAIAgASAAYK8Bk+NQBkAQAAAA==.Karrthis:BAABNQAECn8XAAIQAAgK6AZRLwAKAQAQAAgK6AZRLwAKAQAAAA==.Karrthus:BAAANQAECgUIBQABNQAECggIFwAQAOgGAA==.Katsumotosan:BAAANQADCgcICwAAAA==.',
Ke='Kemstrio:BAABNQAECn8fAAMbAAgKzx7sEwAlAgAbAAcKuiDsEwAlAgAcAAQKMRscOQA5AQABNQAFFAUIEQAEANYfAA==.Kev:BAABNQAECn8uAAQYAAoKYxzwCAAEAgACAAkKzRqiqwArAgAYAAcK3xzwCAAEAgAeAAIKZBkmBwCbAAAAAA==.',
Ko='Kombatgodess:BAAANQADCgcIEwAAAA==.Kordraan:BAAANQADCgQIBAAAAA==.',
Kr='Krael:BAAANQAECggICAAAAA==.',
Ks='Kspboop:BAEANQAECgcIBAAAAA==.',
Ku='Kurag:BAAANQAECgEIAQAAAA==.Kurvios:BAABNQAECn80AAMEAAoKCCBuBQBUAgAWAAoKKh8eIgCKAgAEAAkKzh1uBQBUAgABNQAECgoKPwAaAMQeAA==.Kuurgan:BAAANQAECgQIDAAAAA==.',
Kv='Kvasir:BAAANQAECgMIBgABNQAECggIJQANANcdAA==.',
La='Lalasmira:BAAANQAECgIIAQAAAA==.',
Li='Lichkingstoy:BAACNQAFFH8MAAIJAAUK6xDmFwDpAAAJAAUK6xDmFwDpAAA1AAQKf1cAAgkACgpXIeI1APYCAAkACgpXIeI1APYCAAAA.Light:BAAANQAECggIBAABNQAECgkJMAADALghAA==.Lilmist:BAAANQAECgQIBAAAAA==.Lizardboi:BAAANQAECgcIEQAAAA==.',
Ll='Llilth:BAAANQADCgEIAQAAAA==.',
Ma='Magicstrike:BAAANQADCgcIEgAAAA==.Manistas:BAAANQADCgMIAwAAAA==.Manta:BAAANQAECgcIDwAAAA==.',
Mi='Miracle:BAAANQAECgIIBAAAAA==.Mirana:BAAANQADCgIIAgAAAA==.',
Mo='Morelinne:BAAANQADCgUIDQAAAA==.',
My='Mykeexd:BAAANQAECgEIAQAAAA==.Mykehoochie:BAAANQADCgQIAwAAAA==.',
Na='Nabarke:BAAANQAECgIIBAAAAA==.Naidomsa:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Nathanos:BAAANQAECgQICAABNQAECgoKPwAaAMQeAA==.Naturestrike:BAAANQAECgUIBQAAAA==.',
Ne='Nexaliah:BAAANQAECgMIBgABNQAFFAcIFAAJACMYAA==.Nezath:BAABNQAECn8WAAIKAAgKWABsKQAIAAAKAAgKWABsKQAIAAABNQAECgoKOwAfAAsiAA==.',
Ni='Nier:BAAANQAECgYICwAAAA==.',
No='Noisemarine:BAACNQAFFH8GAAIMAAIK0wRdBgBbAAAMAAIK0wRdBgBbAAA1AAQKfzIAAgwACQrGDWoeAGEBAAwACQrGDWoeAGEBAAAA.Nooxi:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Nospheratus:BAABNQAECn8qAAMIAAoKBB9gBQCyAgAIAAkK7RxgBQCyAgAbAAoK4BSUFQAQAgABNQAFFAUIDAASAIgMAA==.Noub:BAAANQADCgYIBgAAAA==.',
Nu='Nugs:BAAANQAECgIIAgAAAA==.',
Nx='Nx:BAAANQAECgEIAQAAAA==.',
Ny='Nylianna:BAACNQAFFH8UAAIJAAcKIxj4BQB/AQAJAAcKIxj4BQB/AQA1AAQKfywAAgkACgpTJOk6AOYCAAkACgpTJOk6AOYCAAAA.',
Ob='Obilesk:BAAANQADCgcIBwAAAA==.',
Og='Ogganborn:BAAANQAECgYIDwAAAA==.',
Ph='Phoenïx:BAAANQABCgYICQAAAA==.',
Pi='Pikal:BAABNQAECn8kAAQJAAoKow2LngB7AQAJAAkKow2LngB7AQAVAAgKeAjUfAAsAQAUAAEKAAADeAAlAAAAAA==.',
Pr='Priestaline:BAABNQAECn8tAAIPAAoKvhVDOwDRAQAPAAoKvhVDOwDRAQAAAA==.Priestigory:BAABNQAECn8nAAMRAAoKxBTmCACtAQARAAkKghXmCACtAQAQAAEKjg/EVgA6AAAAAA==.Prosper:BAAANQAECgEIAQAAAA==.',
Pv='Pvtcrocker:BAEBNQAFFH8IAAIbAAUKzBJYAgB1AQAbAAUKzBJYAgB1AQABNQAFFAgIJAAUAEwkAA==.',
Qu='Quintus:BAABNQAECn8vAAIJAAoKnx+YKgCqAgAJAAoKnx+YKgCqAgAAAA==.',
Ra='Ra:BAAANQAECggIEAAAAA==.Railiana:BAAANQADCgQIBAAAAA==.',
Re='Regrowth:BAAANQADCggIIAAAAA==.Remaxed:BAAANQAECgIIAgAAAA==.',
Ri='Rimkalzkal:BAAANQADCggICAAAAA==.Riqis:BAAANQABCgIIAgAAAA==.',
Ru='Rummornia:BAAANQAECgUICwAAAA==.',
Sa='Sathenazagos:BAAANQAECgIIAgAAAA==.',
Se='Selesnia:BAABNQAECn8bAAIHAAcKoxunHwDjAQAHAAcKoxunHwDjAQAAAA==.Sephiran:BAABNQAECn8/AAQaAAoKxB7WDgAEAwAaAAoKxB7WDgAEAwAgAAQK9g/cFADbAAAZAAIKPwqTzwBwAAAAAA==.Seppuku:BAAANQAECgcIDQAAAA==.',
Sh='Shaami:BAACNQAFFH8XAAMHAAgKVxGBAgA6AgAHAAgKVxGBAgA6AgAcAAEKAABPKQA9AAA1AAQKf0AAAxwACgqYIIUKAOsCABwACgqYIIUKAOsCAAcACgojG9gdAEECAAAA.Shaomei:BAABNQAECn8qAAMDAAoK5R3HPwCrAgADAAoK5R3HPwCrAgAhAAIKygZfdwBgAAAAAA==.',
Si='Sicario:BAAANQAECgMIBgAAAA==.',
Sk='Skye:BAAANQAECggIDgABNQAFFAkJOAAaAPwjAA==.',
St='Stabbingfang:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.Stdot:BAAANQAECgMIBAABNQAECgoKNAAWAKEaAA==.Stephirollsa:BAAANQAECgEIAQAAAA==.Stormstrike:BAAANQAECgMIBQAAAA==.Stothyr:BAAANQAECgcICwABNQAECgoKPwAEAIwmAA==.Strangulus:BAAANQABCgYIBgAAAA==.',
Sw='Sway:BAAANQAECggICQABNQAECgkJMAADALghAA==.',
Sy='Symwarrior:BAAANQADCgQIBAAAAA==.',
Ta='Taluria:BAAANQAECgIIBwAAAA==.Tayann:BAAANQAECgMIAwAAAA==.',
Ti='Tikimon:BAAANQADCggIGQAAAA==.Tindi:BAAANQADCgQIBAAAAA==.Tinkernine:BAABNQAECn8cAAMcAAcKdAm9YwA/AQAcAAcKdAm9YwA/AQAHAAEKjwF7hgATAAAAAA==.',
To='Tobofrog:BAAANQAECggIBgAAAA==.',
Tr='Trastine:BAAANQAECgEIAQAAAA==.',
Tu='Turaht:BAABNQAECn81AAMTAAoKDRkzOgA6AgATAAoKhRQzOgA6AgASAAgKOxlHQQArAQABNQAECgoKFgALAC4ZAA==.',
Ty='Tyrgrim:BAAANQAECgIIBAAAAA==.Tyronius:BAAANQADCgUIBQAAAA==.',
Ul='Uldyssian:BAABNQAECn9NAAQHAAoKVyGUCwD7AgAHAAkK4yGUCwD7AgAcAAcKyAylNwBBAQAbAAkK9AqdKwAaAQABNQAFFAcIFAAJACMYAA==.',
Uw='Uwuforyou:BAABNQAECn80AAIWAAoKoRqPEgCAAgAWAAoKoRqPEgCAAgAAAA==.',
Uz='Uzumaki:BAAANQAECgcIEgAAAA==.',
Ve='Velawynn:BAACNQAFFH8WAAIZAAgKARWLBABgAgAZAAgKARWLBABgAgA1AAQKfzkAAxkACgrkIPgQAEADABkACgrkIPgQAEADABoAAQokGONvAEkAAAAA.',
Vo='Voidâge:BAACNQAFFH8LAAMCAAYKsw+fKwAxAQACAAUKxA2fKwAxAQAYAAEKbxeIDQBVAAA1AAQKfyEAAgIACgphHYpyAJgCAAIACgphHYpyAJgCAAAA.',
Wo='Wolfez:BAAANQAECgYIBgABNQAECgoKPwAaAMQeAA==.',
Wy='Wysterian:BAAANQADCggIDQAAAA==.',
Xe='Xenu:BAACNQAFFH8IAAIfAAQKnAjYGQDJAAAfAAQKnAjYGQDJAAA1AAQKf0IAAh8ACgqvGzAmAGkCAB8ACgqvGzAmAGkCAAAA.',
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
