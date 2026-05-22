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

local lookup = {'Mage-Frost','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Paladin-Protection','Warlock-Affliction','Warlock-Destruction','Rogue-Outlaw','Warlock-Demonology','Hunter-BeastMastery','Hunter-Survival','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','Druid-Restoration','Warrior-Fury','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Shaman-Enhancement','DeathKnight-Blood','DeathKnight-Frost','Hunter-Marksmanship','Warrior-Protection','DemonHunter-Vengeance','Druid-Balance','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Rogue-Subtlety','Monk-Windwalker','Mage-Fire','Priest-Holy','Druid-Guardian','Druid-Feral',}
local provider = {region='US',realm='Vashj',name='US',type='weekly',zone=46,date='2026-05-17',data={Ac='Achlyss:BAAALgAECgEJAQAAAA==.',
Ad='Adanto:BAAALgADCgEJAQAAAA==.Addequation:BAAALgAECgIJBQAAAA==.Adivh:BAAALgADCgEJAQAAAA==.',
Ah='Ahtreyou:BAAALgADCgIJAgAAAA==.',
Al='Alatär:BAABLgAECn8aAAIBAAgJQxfHcABiAQABAAgJQxfHcABiAQAAAA==.Allorna:BAAALgAECgcJBwAAAA==.',
An='Angelona:BAACLgAFFH8RAAIBAAQJCSOOHgCNAQABAAQJCSOOHgCNAQAuAAQKfyIAAgEACAkcJmQNAFoDAAEACAkcJmQNAFoDAAAA.Angelonah:BAAALgAECgQJBAAAAA==.Angelsenvy:BAABLgAECn8uAAMCAAkJMCDPDACzAgACAAkJMCDPDACzAgADAAEJ9gm/TAEuAAABLgAECgQJBAAEAAAAAA==.Anthela:BAAALgADCgcJBwAAAA==.',
Ar='Arabeth:BAAALgADCgMJAgAAAA==.Archadis:BAABLgAECn8eAAQDAAgJvhnCNgBIAgADAAgJEhnCNgBIAgACAAMJWRsmRQDlAAAFAAEJdhsoNgBKAAAAAA==.Archmond:BAABLgAECn8VAAMGAAcJJhczCwCIAQAGAAYJPxUzCwCIAQAHAAMJVROtPgC6AAAAAA==.Ardric:BAAALgADCgEJAQAAAA==.Arthek:BAAALgAECgUJCQAAAA==.',
As='Ashes:BAAALgAECgEJAQAAAA==.Ashteru:BAABLgAECn8iAAICAAgJqRnvEABPAgACAAgJqRnvEABPAgAAAA==.Ashthundér:BAABLgAECn8WAAIIAAYJKhj7BACpAQAIAAYJKhj7BACpAQABLgAFFAIJAgAEAAAAAA==.',
Av='Avyhn:BAACLgAFFH8JAAIJAAQJGR5/IwBWAQAJAAQJGR5/IwBWAQAuAAQKfyAAAwkACQmgJVYBAHMDAAkACAmgJVYBAHMDAAcAAgl3JONBAK0AAAEuAAUUCAkkAAkAaiMA.',
Az='Azlia:BAAALgAECgUJBQAAAA==.',
Ba='Baaka:BAABLgAECn8rAAMKAAgJiA5aRwCCAQAKAAgJiA5aRwCCAQALAAEJyQF0UwAnAAAAAA==.Bahumat:BAAALgADCgMJAwAAAA==.Bale:BAAALgAECgEJAQAAAA==.Barquiel:BAABLgAECn8nAAMFAAgJIx5rBwAaAgAFAAgJIx5rBwAaAgADAAMJpg4L1gCmAAAAAA==.Batimo:BAAALgAECgQJBAAAAA==.Bayle:BAAALgADCgMJAwAAAA==.',
Be='Beamin:BAAALgADCgQJBAAAAA==.Beaversrock:BAAALgADCgcJEQAAAA==.Behp:BAAALgADCgcJBgAAAA==.Bellithia:BAABLgAECn8hAAMMAAgJTx+aCQCSAgAMAAgJTx+aCQCSAgANAAEJNQtDaAAwAAAAAA==.',
Bi='Bielsebub:BAAALgADCgUJBQAAAA==.Biological:BAAALgAECgEJAQAAAA==.',
Bk='Bkdh:BAAALgAECgYJEAAAAA==.',
Bl='Blackmon:BAABLgAFFH8FAAIOAAIJmwn8mgCWAAAOAAIJmwn8mgCWAAAAAA==.Blitzkreig:BAAALgAECgYJCQAAAA==.Bløødy:BAAALgAECgEJAQABLgAECgUJBgAEAAAAAA==.',
Bo='Boomboombear:BAAALgAECgcJDQAAAA==.Boomya:BAABLgAECn8fAAIPAAgJ0RiYGQA7AgAPAAgJ0RiYGQA7AgAAAA==.',
Br='Britneyspear:BAABLgAECn8mAAMQAAgJlRhXNQDUAQAQAAcJ7BtXNQDUAQARAAUJZg8tJAD3AAAAAA==.Broken:BAAALgADCgMJBwAAAA==.',
Bu='Bubbulubb:BAABLgAECn8hAAIOAAkJXRfBRAAnAgAOAAkJXRfBRAAnAgAAAA==.Bullthing:BAABLgAECn8lAAQCAAgJzCM2CQC8AgACAAcJXyM2CQC8AgADAAQJCRZ33wDOAAAFAAEJixueNABQAAAAAA==.',
Ca='Caladrial:BAAALgADCgMJAwAAAA==.Calex:BAABLgAECn8jAAMSAAgJkRsDHwCiAQASAAcJ1h8DHwCiAQATAAUJaiDWOgCWAQAAAA==.Cassyn:BAAALgAECgEJBAAAAA==.',
Ch='Chansey:BAABLgAECn8kAAIMAAkJWRzfCACuAgAMAAkJWRzfCACuAgAAAA==.Charged:BAAALgAECgMJBAAAAA==.Chesna:BAABLgAECn8nAAMUAAgJgR0MDQAxAgAUAAgJgR0MDQAxAgAVAAUJJwdaSQCzAAAAAA==.Chipsbambee:BAABLgAECn8jAAIKAAgJXQ07WQBPAQAKAAgJXQ07WQBPAQAAAA==.Chttr:BAAALgAECgMJBAAAAA==.Chttrbox:BAACLgAFFH8aAAMWAAcJaiJxAAD2AQAWAAYJVyRxAAD2AQATAAUJ2xKxDAAPAQAuAAQKfzQAAxYACQnbJX8BAPICABYACAk7Jn8BAPICABMACQlGGcQiAA4CAAAA.',
Co='Combust:BAACLgAFFH8HAAIBAAQJXRIrOQBIAQABAAQJXRIrOQBIAQAuAAQKfz0AAgEACQknIHkMAOoCAAEACQknIHkMAOoCAAAA.Corstar:BAAALgADCgUJBQAAAA==.',
Cr='Crigillin:BAAALgADCgMJAwAAAA==.Crux:BAAALgAECgQJCAAAAA==.',
Da='Dalexios:BAAALgADCgYJAQAAAA==.Dallan:BAAALgADCgQJBAAAAA==.Daniella:BAAALgADCgYJBgAAAA==.Danyy:BAAALgAECgEJAQAAAA==.Dao:BAACLgAFFH8IAAITAAMJzBR5EwDDAAATAAMJzBR5EwDDAAAuAAQKfxUAAxMACAnEHMISAIACABMACAnEHMISAIACABIABAl+BIRkAGUAAAAA.Darkhelmet:BAAALgADCggJDAAAAA==.Darkwarspark:BAAALgADCgQJAwAAAA==.',
De='Deadrat:BAAALgAECgUJBwAAAA==.Deathvader:BAAALgADCgYJBgAAAA==.Delaomega:BAABLgAECn8xAAMXAAkJvAr+GgA3AQAXAAkJvAr+GgA3AQAOAAEJjQaGHQExAAAAAA==.Derey:BAAALgADCgEJAgAAAA==.Devien:BAAALgADCgcJBwAAAA==.',
Di='Diber:BAAALgAECgMJAwAAAA==.Divinebovin:BAAALgADCgcJCAAAAA==.',
Dr='Drakvor:BAABLgAECn8uAAMXAAkJShXpCgBoAgAXAAkJShXpCgBoAgAOAAEJcQHlOwEbAAAAAA==.Drash:BAABLgAECn8nAAMYAAcJmA6DDgAfAQAYAAcJ8AyDDgAfAQAXAAMJFBAoMQCRAAAAAA==.Drazgal:BAAALgADCgcJCQAAAA==.Dreni:BAAALgAECgEJAQAAAA==.',
Du='Duhai:BAAALgAECgUJAwAAAA==.Dumbledore:BAABLgAECn8pAAIXAAkJ/hkICQA/AgAXAAkJ/hkICQA/AgAAAA==.Dumpnloads:BAAALgADCgEJAgAAAA==.Durotagg:BAAALgAFFAEJAQAAAA==.',
['Dí']='Dím:BAAALgAECgYJBwAAAA==.',
Ea='Eaterofholes:BAAALgAECgEJAQAAAA==.',
Ed='Edubijes:BAAALgAECgMJAwABLgAECgcJGwAQAMQQAA==.',
Eg='Egres:BAAALgAECgYJCwAAAA==.',
El='Elemequation:BAAALgAECgEJBAAAAA==.Elfguy:BAAALgADCgcJEwAAAA==.',
En='Endléss:BAABLgAECn8qAAILAAgJCBrsEADyAQALAAgJCBrsEADyAQAAAA==.Envision:BAAALgADCgQJAwABLgAECgUJCAAEAAAAAA==.',
Er='Erbium:BAAALgAECgQJBQAAAA==.Eremetrii:BAEALgAFFAEJAQAAAA==.',
Es='Eshwyn:BAAALgAECgYJBgAAAA==.Esquandolas:BAAALgADCgcJDgAAAA==.',
Ev='Evotibs:BAABLgAECn8bAAMZAAcJGAwgEwDvAAAZAAcJGAwgEwDvAAALAAUJZQavMgDOAAAAAA==.',
Fe='Fec:BAAALgAECgEJAQABLgAECgkJMAAaAHQfAA==.',
Fi='Fibaldrachi:BAABLgAECn8qAAIbAAgJDSQIAgC0AgAbAAgJDSQIAgC0AgAAAA==.',
Fr='Fragnarr:BAAALgADCgQJBAAAAA==.Frosting:BAACLgAFFH8HAAIBAAMJjg7zWwDwAAABAAMJjg7zWwDwAAAuAAQKfyEAAgEACAnqHa8sACwCAAEACAnqHa8sACwCAAAA.',
Ga='Galaxy:BAAALgADCgMJBQAAAA==.',
Gh='Ghantu:BAABLgAECn8YAAISAAcJBR+LGgDGAQASAAcJBR+LGgDGAQAAAA==.Ghunk:BAAALgADCgYJBgAAAA==.',
Go='Goldennight:BAAALgADCgYJCQAAAA==.Gornathia:BAAALgAECgcJDQAAAA==.',
Gr='Grandall:BAAALgAECgEJAwAAAA==.Gruon:BAABLgAECn8nAAIcAAcJEQytMAAOAQAcAAcJEQytMAAOAQAAAA==.',
Gu='Gulzan:BAABLgAECn8XAAISAAgJfBDFLQBBAQASAAgJfBDFLQBBAQAAAA==.',
['Gø']='Gøkû:BAAALgAECgYJDgAAAA==.',
Ha='Hacks:BAABLgAECn8jAAIaAAgJAxGREwBwAQAaAAgJAxGREwBwAQAAAA==.Haymakerxd:BAABLgAECn8WAAIOAAgJqCPHBgAZAwAOAAgJqCPHBgAZAwAAAA==.',
He='Healtastic:BAAALgADCgcJBwAAAA==.Heealzz:BAAALgAECgYJDQAAAA==.Helendir:BAAALgAECgIJAgAAAA==.',
Hu='Huntercobra:BAAALgADCgUJBwAAAA==.Huntsagee:BAAALgADCgUJCAAAAA==.',
Hy='Hyacinthe:BAABLgAECn8mAAQGAAgJWRzgAwBQAgAGAAgJWRzgAwBQAgAJAAMJCgzAuQCdAAAHAAQJ2hFEGwCaAAAAAA==.Hypernova:BAAALgADCgMJAwAAAA==.',
Ib='Ibogaine:BAAALgADCgIJAgAAAA==.',
Ic='Iceshep:BAAALgAECgUJBQAAAA==.',
Id='Iden:BAAALgAECgYJCQAAAA==.Idtrapthát:BAAALgADCgMJAwAAAA==.',
Il='Illidanswife:BAAALgAECgYJDAAAAA==.Iluvatar:BAAALgADCgQJBAAAAA==.',
Im='Immamageboi:BAABLgAECn8hAAIBAAYJrQi4rQD0AAABAAYJrQi4rQD0AAAAAA==.',
In='Infernal:BAAALgAECgcJCgAAAA==.Ingo:BAAALgADCgcJBwAAAA==.Inspiremoon:BAAALgAECgYJEAAAAA==.Interror:BAAALgAECgYJDgAAAA==.',
Ir='Iranos:BAABLgAECn8nAAMDAAgJqyA7FwCCAgADAAgJqyA7FwCCAgAFAAIJLgxTMwBVAAAAAA==.Irishpryde:BAAALgAECgEJAQAAAA==.',
Ja='Jackiechanda:BAAALgAECgQJCQAAAA==.Jaraxxus:BAAALgAECgUJCQABLgAECgYJDQAEAAAAAA==.',
Je='Jelipa:BAAALgADCgEJAQABLgAECgcJGwAQAMQQAA==.',
Jo='Johnnylaw:BAAALgAECgMJAwAAAA==.Joshns:BAAALgADCgEJAQAAAA==.',
Ka='Kaellyn:BAAALgAECgQJBwAAAA==.Kaicelius:BAAALgAECgMJAwAAAA==.Kaimari:BAAALgADCgcJBwAAAA==.Kaloesh:BAAALgADCgQJBAABLgAECggJJwAHAGoeAA==.Kanakana:BAABLgAECn8gAAITAAgJvBuuHwAHAgATAAgJvBuuHwAHAgAAAA==.',
Ke='Kendana:BAAALgADCgYJDgAAAA==.Keyadron:BAAALgAECgUJCAAAAA==.',
Ki='Kindly:BAAALgAECgEJAgAAAA==.Kirab:BAAALgAECggJEwAAAA==.Kirinmor:BAAALgADCggJCAAAAA==.Kis:BAAALgAECgUJBwAAAA==.Kisten:BAABLgAECn8WAAIJAAgJdQP1lADjAAAJAAgJdQP1lADjAAAAAA==.',
Ko='Kogorn:BAAALgADCgIJAgAAAA==.Kosmos:BAAALgAECgcJDAABLgAFFAEJAQAEAAAAAA==.',
Kr='Kreid:BAAALgAECgcJEgAAAA==.Kreìd:BAAALgADCgEJAQABLgAECgcJEgAEAAAAAA==.',
Ku='Kungfoupanda:BAAALgAECgEJAQAAAA==.',
Ky='Kyrr:BAAALgAFFAMJAwAAAA==.',
La='Larbear:BAAALgADCgIJAgAAAA==.Larrysham:BAAALgADCgEJAQAAAA==.',
Le='Lemén:BAABLgAECn8jAAIdAAgJGxPDRgBxAQAdAAgJGxPDRgBxAQAAAA==.Lenore:BAAALgAECgMJAwAAAA==.',
Li='Lierax:BAABLgAECn8tAAMeAAkJTh6XCQCHAgAeAAkJTh6XCQCHAgAfAAUJHBTxIQAbAQAAAA==.Lightpheonix:BAAALgADCgUJBQAAAA==.Ligmaw:BAAALgAECgQJCwAAAA==.Lildonny:BAAALgADCgYJBgAAAA==.Lilia:BAAALgAFFAcJBAAAAA==.Lilrobo:BAAALgADCgcJDQAAAA==.Linaei:BAABLgAECn8pAAINAAkJxAw6HQCTAQANAAkJxAw6HQCTAQAAAA==.Linestia:BAAALgAECgEJAgABLgAECgYJCwAEAAAAAA==.Littlewingz:BAABLgAECn8iAAIgAAgJaCNJAgAdAwAgAAgJaCNJAgAdAwAAAA==.',
Lo='Lockinflame:BAAALgAFFAIJAgAAAA==.Loka:BAAALgAECgEJAQAAAA==.',
['Lá']='Lálatina:BAAALgAECgEJAQAAAA==.',
Ma='Magnataur:BAAALgADCgQJBQAAAA==.Mahdek:BAAALgAECgMJBAABLgAECgUJBgAEAAAAAA==.Maladreks:BAAALgAECgEJAQAAAA==.Mascro:BAAALgADCgIJAgAAAA==.Maverrus:BAAALgADCgMJAwABLgAECgYJCwAEAAAAAA==.Mawz:BAABLgAECn8aAAIWAAgJ2hxuBwADAgAWAAgJ2hxuBwADAgAAAA==.Mayormcçhees:BAAALgADCgMJAwAAAA==.',
Me='Mecat:BAABLgAECn8hAAIPAAkJ6yJjCQD8AgAPAAkJ6yJjCQD8AgAAAA==.Meedlefinger:BAAALgAECgQJBQAAAA==.Megatonne:BAAALgADCgkJCQAAAA==.Melathia:BAABLgAECn8bAAIJAAcJ9QnjjQDwAAAJAAcJ9QnjjQDwAAAAAA==.Meliza:BAAALgAECgQJBwAAAA==.Melløw:BAAALgAECgEJAgAAAA==.',
Mo='Mommyshere:BAAALgADCgEJAQAAAA==.Monilara:BAAALgAECgQJBQAAAA==.Morman:BAAALgAECgkJAgAAAA==.',
Mu='Musclebear:BAACLgAFFH8IAAIhAAQJmQkhFQAiAQAhAAQJmQkhFQAiAQAuAAQKfxUAAiEACAkaFdkWAJsBACEACAkaFdkWAJsBAAAA.',
My='Mythaux:BAAALgADCgMJAwABLgAECggJJwAHAGoeAA==.',
['Mâ']='Mâk:BAAALgADCggJCAAAAA==.',
Ne='Neero:BAABLgAECn8eAAIdAAcJfxs+NAC3AQAdAAcJfxs+NAC3AQAAAA==.Nelena:BAABLgAECn8pAAITAAcJaQqyTAAoAQATAAcJaQqyTAAoAQAAAA==.Nenyve:BAAALgADCgQJBQAAAA==.Nerodrachen:BAAALgADCgMJAwAAAA==.Newgrim:BAAALgADCgMJAwAAAA==.Newurt:BAAALgAECgQJBgAAAA==.Nezhyt:BAABLgAECn8nAAMHAAgJah7hAgA2AgAHAAgJtB3hAgA2AgAGAAUJeh5qDQApAQAAAA==.',
Ni='Nicolbolas:BAABLgAECn8iAAMeAAkJNRYXFQDxAQAeAAkJNRYXFQDxAQAgAAIJewIVRQBHAAAAAA==.Nightshow:BAAALgADCgUJBQAAAA==.',
No='Nori:BAACLgAFFH8HAAIWAAMJtyJDBgD7AAAWAAMJtyJDBgD7AAAuAAQKfxQAAhYABwmeJV0DAJACABYABwmeJV0DAJACAAEuAAUUBwkiAAEAqiQA.Notdragon:BAAALgADCgIJAgAAAA==.Notorious:BAABLgAECn8aAAMgAAgJyhenBwBDAgAgAAgJyhenBwBDAgAeAAMJYBCmVQCPAAAAAA==.',
Nt='Ntaicen:BAAALgADCgMJAwAAAA==.',
Os='Osiris:BAAALgADCgYJBgAAAA==.',
Pa='Pap:BAAALgADCgYJCAAAAA==.Papavodou:BAAALgADCgQJBAAAAA==.Paýp:BAABLgAECn8cAAMgAAgJdwOiGQD/AAAgAAgJdwOiGQD/AAAeAAYJ5AiLOgD7AAAAAA==.',
Pe='Pentasaurusr:BAABLgAECn8eAAMJAAcJSh+bQAAMAgAJAAYJSh+bQAAMAgAHAAIJ6BkiTACJAAAAAA==.',
Pl='Platemedic:BAAALgAECgYJBwAAAA==.',
Po='Polevik:BAAALgAECgMJAwABLgAECggJJwAHAGoeAA==.Pookkee:BAAALgAECgYJCwAAAA==.Porkahantas:BAAALgAECgYJEwAAAA==.Portgasdace:BAAALgAECgEJAgAAAA==.',
Pp='Ppat:BAAALgAECgYJEQAAAA==.',
Py='Pyromainiac:BAAALgADCgEJAQAAAA==.',
Qu='Queteimporta:BAABLgAECn8bAAQQAAcJxBDJNwAnAQAQAAcJwgvJNwAnAQAaAAMJ3BSXKgClAAARAAQJ6gnvSwBEAAAAAA==.',
Ra='Rayeona:BAAALgADCgYJBgAAAA==.',
Re='Recheals:BAAALgAECgcJCAABLgAECgcJGgAhAPgYAA==.Recmod:BAABLgAECn8aAAIhAAcJ+BjsGgBzAQAhAAcJ+BjsGgBzAQAAAA==.Rendover:BAAALgAECgYJBwAAAA==.Return:BAABLgAECn8wAAIaAAkJdB/kBQDXAgAaAAkJdB/kBQDXAgAAAA==.',
Rh='Rhimeholt:BAABLgAECn8gAAMVAAkJ7hoYDACDAgAVAAkJ7hoYDACDAgAiAAEJgQpheAAwAAAAAA==.',
Ri='Rikoria:BAAALgAECgYJDQAAAA==.',
Ro='Roussalina:BAAALgAECgEJBAAAAA==.',
Ry='Ryahask:BAABLgAECn8qAAIWAAkJNxCsCQDLAQAWAAkJNxCsCQDLAQAAAA==.',
['Rä']='Rädagast:BAAALgADCgIJAgAAAA==.',
Sa='Sadisticrage:BAABLgAECn82AAIDAAkJBR9oEACxAgADAAkJBR9oEACxAgAAAA==.Sae:BAAALgAECgMJAwAAAA==.Sammyshoes:BAAALgAECggJDwAAAA==.Sanguine:BAAALgAECgYJCgAAAA==.',
Sc='Scrimbo:BAAALgAECgQJBQAAAA==.',
Se='Seaturtles:BAAALgADCgYJBgAAAA==.Seeturtle:BAABLgAECn8lAAMjAAkJ7x4KAwD4AQAjAAcJZyEKAwD4AQABAAgJJhrHTwCyAQAAAA==.Sellassie:BAAALgADCgYJDwAAAA==.Selvala:BAAALgAECgEJAQAAAA==.Selûne:BAAALgAECgIJAgAAAA==.Senthara:BAAALgAECgUJBQAAAA==.',
Sh='Shadow:BAABLgAECn8UAAIOAAcJexAUawBVAQAOAAcJexAUawBVAQAAAA==.Shera:BAAALgADCgYJCwAAAA==.Shooter:BAAALgAECgEJAQAAAA==.Shxggy:BAAALgAECgEJAQAAAA==.',
Sk='Skull:BAAALgAECgEJAQAAAA==.',
Sl='Slippie:BAAALgAECgMJAwAAAA==.',
Sm='Smell:BAABLgAECn83AAIDAAkJkhmdJwAmAgADAAkJkhmdJwAmAgAAAA==.',
So='Solheim:BAABLgAECn8WAAIDAAgJVCXmCwDYAgADAAgJVCXmCwDYAgAAAA==.',
Sp='Spacemonk:BAAALgAECgQJCAAAAA==.Spire:BAAALgAFFAIJAgAAAA==.Sproutling:BAABLgAECn8nAAMPAAgJgQedUQAPAQAPAAgJgQedUQAPAQAcAAYJ5QUSQwC2AAAAAA==.',
St='Stearphen:BAAALgAECggJEgAAAA==.Stormy:BAAALgADCgEJAQAAAA==.Stumpi:BAAALgAECgcJDwAAAA==.',
Sw='Swazti:BAABLgAECn8eAAIJAAgJUhL9RgCUAQAJAAgJUhL9RgCUAQAAAA==.',
Ta='Tashir:BAAALgADCgcJBwABLgAECgkJAgAEAAAAAA==.Taurnil:BAABLgAECn8pAAIGAAcJJRq9BwCZAQAGAAcJJRq9BwCZAQAAAA==.',
Te='Teledor:BAAALgAECgQJBgAAAA==.Telperion:BAAALgADCgYJBgAAAA==.',
Ti='Timika:BAABLgAECn8nAAMkAAgJXBfbEwD7AQAkAAgJXBfbEwD7AQAMAAYJ+wkYLwAUAQAAAA==.Tinysunn:BAAALgADCgYJBgAAAA==.',
To='Topharius:BAAALgADCgIJAgAAAA==.Toscc:BAAALgAECgMJBAAAAA==.',
Ty='Typeshift:BAABLgAFFH8KAAIlAAQJMxyyAwBlAQAlAAQJMxyyAwBlAQAAAA==.',
Uc='Uchtdwarf:BAAALgAECgQJBAAAAA==.',
Ue='Uen:BAAALgAECgQJBwABLgAFFAYJGQAeAFcYAA==.',
Uk='Ukan:BAAALgADCgQJAwAAAA==.',
Ux='Uxx:BAAALgAECgYJDQAAAA==.',
Va='Vaeron:BAABLgAECn8UAAIhAAcJLBkdEwDDAQAhAAcJLBkdEwDDAQAAAA==.',
Ve='Velithria:BAAALgADCgUJBQAAAA==.Vengeancez:BAABLgAECn8bAAIQAAkJvwt8KgAPAgAQAAkJvwt8KgAPAgAAAA==.Venomsecho:BAABLgAECn8jAAImAAkJ1hQeCgDNAQAmAAkJ1hQeCgDNAQAAAA==.Versacé:BAAALgADCgEJAQAAAA==.',
Vi='Vicodin:BAAALgAECgEJAwAAAA==.Videl:BAAALgADCgEJAQAAAA==.Visionaries:BAAALgAECgUJCAAAAA==.',
Vo='Voldemort:BAAALgADCgcJBwAAAA==.Vorrixa:BAAALgAECgYJCQAAAA==.',
We='Weathergirl:BAAALgAECgcJCgAAAA==.',
Wh='Whisky:BAAALgAECgQJBAAAAA==.',
Wi='Winniethefu:BAABLgAECn8jAAIVAAgJ0BiZFwADAgAVAAgJ0BiZFwADAgAAAA==.Wisps:BAAALgADCgEJAQABLgAECgYJBgAEAAAAAA==.',
Wo='Wolffire:BAAALgAECgMJAgABLgAECgQJCAAEAAAAAA==.',
Wy='Wy:BAAALgAECgYJDwAAAA==.',
Xa='Xanna:BAAALgAECgEJAQAAAA==.',
Xy='Xylith:BAACLgAFFH8GAAIFAAMJGhN6BwC4AAAFAAMJGhN6BwC4AAAuAAQKfycAAgUACAmlItwCAPsCAAUACAmlItwCAPsCAAAA.',
Ye='Yellowman:BAAALgADCgYJBgAAAA==.',
Yu='Yungdon:BAAALgADCggJCAAAAA==.Yunàlestrà:BAAALgAECgQJCwAAAA==.',
Za='Zach:BAABLgAECn8hAAIBAAkJcBl0PACFAgABAAkJcBl0PACFAgAAAA==.',
Zy='Zylith:BAAALgAECgQJBQAAAA==.',
['Äv']='Ävatar:BAABLgAECn8UAAIVAAcJiwVaPADzAAAVAAcJiwVaPADzAAAAAA==.',
['Ðe']='Ðeath:BAAALgAECgUJBQAAAA==.',
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
