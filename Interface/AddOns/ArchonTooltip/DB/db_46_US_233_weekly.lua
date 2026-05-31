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

local lookup = {'Hunter-Marksmanship','Mage-Frost','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Paladin-Protection','Warlock-Affliction','Warlock-Destruction','Rogue-Outlaw','Warlock-Demonology','Hunter-BeastMastery','Hunter-Survival','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Blood','Druid-Restoration','Warrior-Fury','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Shaman-Enhancement','DeathKnight-Frost','Warrior-Protection','DemonHunter-Vengeance','Druid-Balance','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','Monk-Windwalker','Mage-Fire','Priest-Holy','Druid-Guardian','Druid-Feral',}
local provider = {region='US',realm='Vashj',name='US',type='weekly',zone=46,date='2026-05-31',data={Ab='Abeloth:BAAALgAECgEJAQABLgAECgcJGwABABgMAA==.',
Ac='Achlyss:BAAALgAECgEJAQAAAA==.',
Ad='Adanto:BAAALgADCgEJAQAAAA==.Addequation:BAAALgAECgIJBQAAAA==.Adivh:BAAALgADCgEJAQAAAA==.',
Ah='Ahtreyou:BAAALgADCgIJAgAAAA==.',
Al='Alatär:BAABLgAECn8aAAICAAgJQxeiggBZAQACAAgJQxeiggBZAQAAAA==.Allorna:BAAALgAECgcJBwAAAA==.',
An='Angelona:BAACLgAFFH8XAAICAAUJCSM4NQBtAQACAAUJCSM4NQBtAQAuAAQKfyMAAgIACAkcJmQNAFoDAAIACAkcJmQNAFoDAAAA.Angelonah:BAAALgAECgQJBAAAAA==.Angelsenvy:BAABLgAECn8/AAMDAAkJmCAsCgDVAgADAAkJmCAsCgDVAgAEAAEJ9gm+hQEqAAABLgAECgYJCQAFAAAAAA==.Anthela:BAAALgADCgcJBwAAAA==.',
Ar='Arabeth:BAAALgADCgMJAgAAAA==.Archadis:BAABLgAECn8jAAQEAAgJvhnCNgBIAgAEAAgJEhnCNgBIAgADAAUJVhRyPQA7AQAGAAMJNRkMJQDTAAAAAA==.Archmond:BAABLgAECn8VAAMHAAcJJhczCwCIAQAHAAYJPxUzCwCIAQAIAAMJVROtPgC6AAAAAA==.Ardric:BAAALgADCgEJAQAAAA==.Arthek:BAAALgAECgUJCgAAAA==.',
As='Ashes:BAAALgAECgEJAQAAAA==.Ashteru:BAABLgAECn8jAAIDAAgJqhmLFgBBAgADAAgJqhmLFgBBAgAAAA==.Ashthundér:BAABLgAECn8WAAIJAAYJKhj7BACpAQAJAAYJKhj7BACpAQABLgAFFAQJBQAKAGoWAA==.',
Av='Avyhn:BAACLgAFFH8UAAMKAAYJZiXNCQAoAgAKAAYJZiXNCQAoAgAHAAEJAADuJgAAAAAuAAQKfyAAAwoACQmhJUQCAGsDAAoACAmhJUQCAGsDAAgAAgl3JONBAK0AAAEuAAUUCAkwAAoAKCYA.',
Az='Azlia:BAAALgAECgUJBQAAAA==.',
['Aë']='Aëolus:BAAALgADCgYJBgAAAA==.',
Ba='Baaka:BAABLgAECn80AAMLAAgJRxDHUACaAQALAAgJRxDHUACaAQAMAAEJyQEnYwAkAAAAAA==.Bahumat:BAAALgADCgMJAwAAAA==.Bale:BAAALgAECgkJCQAAAA==.Barquiel:BAABLgAECn8zAAMGAAkJ6h33BQB3AgAGAAkJ6h33BQB3AgAEAAUJrw0+vADxAAAAAA==.Batimo:BAAALgAECgQJBAAAAA==.Bayle:BAAALgADCgMJAwAAAA==.',
Be='Beamin:BAAALgADCgQJBAAAAA==.Beaversrock:BAAALgADCgcJEQAAAA==.Behp:BAAALgADCgcJBgAAAA==.Bellithia:BAABLgAECn8lAAMNAAkJPh4GCQDJAgANAAkJPh4GCQDJAgAOAAEJNQtdewAwAAAAAA==.Belyne:BAAALgAECgEJAQABLgAECgkJJQANAD4eAA==.',
Bi='Bielsebub:BAAALgADCgUJBQAAAA==.Biological:BAAALgAECgEJAQAAAA==.',
Bk='Bkdh:BAAALgAECgYJEAAAAA==.',
Bl='Blackmon:BAACLgAFFH8LAAIPAAMJeA/fhwDZAAAPAAMJeA/fhwDZAAAuAAQKfxUAAw8ACQkMF6NmAIcBAA8ACQkMF6NmAIcBABAABgl3BxA7AI8AAAAA.Blitzkreig:BAAALgAECgYJCQAAAA==.Bløødy:BAAALgAECgEJAQABLgAECgUJBgAFAAAAAA==.',
Bo='Boomboombear:BAAALgAECgcJDQAAAA==.Boomya:BAABLgAECn8fAAIRAAgJ0hhRHwA6AgARAAgJ0hhRHwA6AgAAAA==.',
Br='Britneyspear:BAABLgAECn8mAAMSAAgJlRhXNQDUAQASAAcJ7BtXNQDUAQATAAUJZg9MLwD0AAAAAA==.Broken:BAAALgADCgMJBwAAAA==.',
Bu='Bubbulubb:BAABLgAECn8hAAIPAAkJXRfBRAAnAgAPAAkJXRfBRAAnAgAAAA==.Bullthing:BAABLgAECn8qAAQDAAkJ1CKaAgBzAwADAAkJ1CKaAgBzAwAEAAQJCRZ33wDOAAAGAAEJixs2PwBOAAAAAA==.',
Ca='Caladrial:BAAALgADCgMJAwAAAA==.Calex:BAABLgAECn8xAAMUAAgJBCFxEQBQAgAUAAgJBCFxEQBQAgAVAAUJaiDWOgCWAQAAAA==.Cassyn:BAAALgAECgEJBAAAAA==.',
Ch='Chansey:BAABLgAECn8nAAINAAkJnB7fCACuAgANAAkJnB7fCACuAgAAAA==.Charged:BAAALgAECgMJBAAAAA==.Chesna:BAABLgAECn8qAAMWAAkJSx3SCQCGAgAWAAkJSx3SCQCGAgAXAAUJJwdaSQCzAAAAAA==.Chinchulin:BAAALgAECgQJAwAAAA==.Chipsbambee:BAABLgAECn8pAAILAAgJxg3SXgBzAQALAAgJxg3SXgBzAQAAAA==.Chttr:BAAALgAECgMJBAAAAA==.Chttrbox:BAACLgAFFH8lAAMYAAcJpyIKAQD9AQAYAAYJfiQKAQD9AQAVAAUJExO4IgA7AQAuAAQKfzQAAxgACQnbJXECAOUCABgACAk7JnECAOUCABUACQlGGcQiAA4CAAAA.',
Co='Combust:BAACLgAFFH8MAAICAAQJURm7RABDAQACAAQJURm7RABDAQAuAAQKf0MAAgIACQmgIsUMAAADAAIACQmgIsUMAAADAAAA.Corstar:BAAALgADCgUJBQAAAA==.',
Cr='Crigillin:BAAALgADCgMJAwAAAA==.Crux:BAAALgAECgQJCAAAAA==.',
Da='Dalexios:BAAALgADCgYJAQAAAA==.Dallan:BAAALgADCgcJCgAAAA==.Daniella:BAAALgADCgYJBgAAAA==.Danyy:BAAALgAECgEJAQAAAA==.Dao:BAACLgAFFH8IAAIVAAMJzBR5EwDDAAAVAAMJzBR5EwDDAAAuAAQKfxUAAxUACAnEHMISAIACABUACAnEHMISAIACABQABAl+BJ55AGIAAAAA.Darelina:BAAALgADCgYJDQAAAA==.Darkhelmet:BAAALgADCggJDAAAAA==.Darkwarspark:BAAALgADCgQJAwAAAA==.',
De='Deathvader:BAAALgADCgcJDAAAAA==.Delaomega:BAABLgAECn86AAMQAAkJvQo1IgApAQAQAAkJvQo1IgApAQAPAAEJjQbjVgEuAAAAAA==.Derey:BAAALgADCgEJAgAAAA==.Devien:BAAALgADCgcJBwAAAA==.',
Di='Diber:BAAALgAECgMJAwAAAA==.Divinebovin:BAAALgADCgcJCAAAAA==.',
Dr='Drakvader:BAAALgAECgIJAwABLgAECgcJGwABABgMAA==.Drakvor:BAABLgAECn8uAAMQAAkJShXpCgBoAgAQAAkJShXpCgBoAgAPAAEJcQHlOwEbAAAAAA==.Drash:BAABLgAECn89AAMZAAgJChTRCgCkAQAZAAgJIRPRCgCkAQAQAAMJFBD2OwCLAAAAAA==.Drazgal:BAAALgADCgcJCQAAAA==.Dreni:BAAALgAECgEJAQAAAA==.',
Du='Duhai:BAAALgAECgUJBAAAAA==.Dumbledore:BAABLgAECn8tAAIQAAkJGhshDAAxAgAQAAkJGhshDAAxAgAAAA==.Dumpnloads:BAAALgADCgEJAgAAAA==.Durotagg:BAAALgAFFAEJAQAAAA==.',
['Dí']='Dím:BAAALgAECgYJCAAAAA==.',
Ea='Eaterofholes:BAAALgAECgYJBwAAAA==.',
Ed='Edubijes:BAAALgAECgcJCgABLgAECgcJHQASALESAA==.',
Eg='Egres:BAAALgAECgYJCwAAAA==.',
El='Elemequation:BAAALgAECgEJBAAAAA==.Elfguy:BAAALgADCgcJEwAAAA==.',
En='Endléss:BAABLgAECn8rAAIMAAgJOhq2EgAHAgAMAAgJOhq2EgAHAgAAAA==.Envision:BAAALgADCgQJAwABLgAECgUJCAAFAAAAAA==.',
Er='Erbium:BAAALgAECgQJBQAAAA==.Eremetrii:BAEALgAFFAEJAQAAAA==.',
Es='Eshwyn:BAAALgAECgYJBgAAAA==.Esquandolas:BAAALgADCgcJGAAAAA==.',
Ev='Evotibs:BAABLgAECn8bAAMBAAcJGAyoFgDsAAABAAcJGAyoFgDsAAAMAAUJZQaTPADHAAAAAA==.',
Fe='Fec:BAAALgAECgYJDQABLgAECgkJPwAaAHQfAA==.',
Fi='Fibaldrachi:BAABLgAECn8vAAIbAAkJ9SNEAQAUAwAbAAkJ9SNEAQAUAwAAAA==.',
Fr='Fragnarr:BAAALgADCgQJBAAAAA==.Frosting:BAACLgAFFH8JAAICAAMJIxAEcgDeAAACAAMJIxAEcgDeAAAuAAQKfyEAAgIACAnrHas4ACACAAIACAnrHas4ACACAAAA.',
Ga='Galaxy:BAAALgADCgMJBQAAAA==.',
Gh='Ghantu:BAABLgAECn8aAAIUAAgJ/hwaGgD7AQAUAAgJ/hwaGgD7AQAAAA==.Ghunk:BAAALgADCgYJBgAAAA==.',
Go='Goldennight:BAAALgADCgYJCQAAAA==.Gornathia:BAAALgAECgcJDQAAAA==.',
Gr='Grandall:BAAALgAECgEJAwAAAA==.Grimsteel:BAAALgAECgMJAwAAAA==.Gruon:BAABLgAECn84AAIcAAgJ0gxALwBJAQAcAAgJ0gxALwBJAQAAAA==.',
Gu='Gulzan:BAABLgAECn8fAAIUAAgJUBUkIADKAQAUAAgJUBUkIADKAQAAAA==.',
['Gø']='Gøkû:BAAALgAECgYJDgAAAA==.',
Ha='Hacks:BAABLgAECn8kAAIaAAgJBBHzGABfAQAaAAgJBBHzGABfAQAAAA==.Haymakerxd:BAABLgAECn8WAAIPAAgJqCPGCgAKAwAPAAgJqCPGCgAKAwAAAA==.',
He='Healtastic:BAAALgADCgcJBwAAAA==.Heealzz:BAAALgAECgYJDQAAAA==.Helendir:BAAALgAECgIJAgAAAA==.',
Hu='Huntsagee:BAAALgADCgUJCAAAAA==.',
Hy='Hyacinthe:BAABLgAECn8tAAQHAAkJ9RvgAwBQAgAHAAkJ9RvgAwBQAgAIAAQJ3BGVHgCiAAAKAAMJCgwh1wCZAAAAAA==.Hypernova:BAAALgADCgMJAwAAAA==.',
Ib='Ibogaine:BAAALgADCgIJAgAAAA==.',
Ic='Iceshep:BAAALgAECgYJCAAAAA==.',
Id='Iden:BAAALgAECgYJCQAAAA==.Idtrapthát:BAAALgADCgMJAwAAAA==.',
Il='Illidanswife:BAAALgAECgYJDAAAAA==.Iluvatar:BAAALgADCgQJBAAAAA==.',
Im='Immamageboi:BAABLgAECn8kAAICAAcJLQiOtAAAAQACAAcJLQiOtAAAAQAAAA==.',
In='Infernal:BAAALgAECgcJCgAAAA==.Ingo:BAAALgADCgkJDgAAAA==.Inspiremoon:BAAALgAECgYJEAAAAA==.Interror:BAAALgAECgYJDgAAAA==.',
Ip='Ipak:BAAALgADCgEJAQAAAA==.',
Ir='Iranos:BAABLgAECn8nAAMEAAgJqiAQIQBtAgAEAAgJqiAQIQBtAgAGAAIJLgw1OwBbAAAAAA==.Irishpryde:BAAALgAECgEJAQAAAA==.',
Ja='Jackiechanda:BAAALgAECgQJCQAAAA==.Jaraxxus:BAAALgAECgUJCQABLgAECgYJDQAFAAAAAA==.',
Je='Jelipa:BAAALgADCgEJAQABLgAECgcJHQASALESAA==.',
Jo='Johnnylaw:BAAALgAECgMJAwAAAA==.Joshns:BAAALgADCgEJAQAAAA==.',
Ka='Kaellyn:BAAALgAECgYJCQAAAA==.Kaicelius:BAAALgAECgMJAwAAAA==.Kaimari:BAAALgADCgcJBwAAAA==.Kaloesh:BAAALgADCgQJBAABLgAFFAEJAQAFAAAAAA==.Kanakana:BAABLgAECn8nAAIVAAgJlR+FFACPAgAVAAgJlR+FFACPAgAAAA==.',
Ke='Kendana:BAAALgADCgYJDgAAAA==.Keyadron:BAAALgAECgUJCAAAAA==.',
Ki='Kindly:BAAALgAECgEJAgAAAA==.Kirab:BAABLgAECn8XAAIGAAgJoAXnLQCbAAAGAAgJoAXnLQCbAAAAAA==.Kirinmor:BAAALgADCggJCAAAAA==.Kis:BAAALgAECgUJBwAAAA==.Kisten:BAABLgAECn8XAAIKAAgJhQPcqQDlAAAKAAgJhQPcqQDlAAAAAA==.',
Ko='Kogorn:BAAALgADCgIJAgAAAA==.Korja:BAAALgAECgEJAQAAAA==.Kosmos:BAAALgAECgcJEAABLgAFFAIJAgAFAAAAAA==.',
Kr='Kreid:BAABLgAECn8cAAIXAAgJKRvxEQBxAgAXAAgJKRvxEQBxAgAAAA==.Kreìd:BAAALgADCgEJAQABLgAECggJHAAXACkbAA==.',
Ku='Kungfoupanda:BAAALgAECgIJAwAAAA==.',
Ky='Kyrr:BAAALgAFFAQJBAAAAA==.',
La='Larbear:BAAALgADCgIJAgAAAA==.Larrysham:BAAALgADCgEJAQAAAA==.',
Le='Lemén:BAABLgAECn8sAAIdAAkJoBXJLwDzAQAdAAkJoBXJLwDzAQAAAA==.Lenore:BAAALgAECgMJAwAAAA==.',
Li='Lierax:BAABLgAECn8tAAMeAAkJTh5uDAB+AgAeAAkJTh5uDAB+AgAfAAUJHBTxIQAbAQAAAA==.Lightpheonix:BAAALgADCgUJBQAAAA==.Ligmaw:BAAALgAECgQJCwAAAA==.Lildonny:BAAALgAECgEJAQAAAA==.Lilia:BAAALgAFFAcJBAAAAA==.Lilrobo:BAAALgADCgcJDQAAAA==.Linaei:BAABLgAECn8vAAIOAAkJsw+7HgCzAQAOAAkJsw+7HgCzAQAAAA==.Linestia:BAAALgAECgEJAgABLgAECgYJCwAFAAAAAA==.Littlewingz:BAABLgAECn8qAAIgAAgJzSPRAgAjAwAgAAgJzSPRAgAjAwAAAA==.',
Lo='Lobotomy:BAAALgAFFAQJBAAAAA==.Lockinflame:BAACLgAFFH8FAAIKAAQJahZFMABaAQAKAAQJahZFMABaAQAuAAQKfxQAAgoACAlRINoYAIQCAAoACAlRINoYAIQCAAAA.Lockinload:BAAALgAFFAMJAwAAAA==.Loka:BAAALgAECgEJAQAAAA==.',
['Lá']='Lálatina:BAAALgAECgMJAwAAAA==.',
Ma='Magnataur:BAAALgADCgQJBQAAAA==.Mahdek:BAAALgAECgMJBAABLgAECgUJBgAFAAAAAA==.Maladreks:BAAALgAECgEJAQAAAA==.Malsandre:BAAALgADCgUJBQABLgAECgkJLQAHAPUbAA==.Mascro:BAAALgADCgIJAgAAAA==.Maverrus:BAAALgADCgMJAwABLgAECgYJCwAFAAAAAA==.Mawz:BAABLgAECn8aAAIYAAgJ2hyrCgDzAQAYAAgJ2hyrCgDzAQAAAA==.Mayormcçhees:BAAALgADCgMJAwAAAA==.',
Me='Mecat:BAACLgAFFH8HAAIRAAIJQyL8NQDHAAARAAIJQyL8NQDHAAAuAAQKfyEAAhEACQnrImMJAPwCABEACQnrImMJAPwCAAAA.Meedlefinger:BAAALgAECgQJBQAAAA==.Megatonne:BAAALgADCgkJCQAAAA==.Melathia:BAABLgAECn8eAAIKAAkJQQnYbgBUAQAKAAkJQQnYbgBUAQAAAA==.Meliza:BAAALgAECgQJBwAAAA==.Melløw:BAAALgAECgEJAgAAAA==.',
Mo='Mommyshere:BAAALgADCgEJAQAAAA==.Monilara:BAAALgAECgQJBQAAAA==.Morman:BAAALgAECgkJBgAAAA==.',
Mu='Musclebear:BAACLgAFFH8JAAIhAAQJmQk9HQATAQAhAAQJmQk9HQATAQAuAAQKfxgAAiEACAkJF6YXAMYBACEACAkJF6YXAMYBAAAA.',
My='Mythaux:BAAALgADCgMJAwABLgAFFAEJAQAFAAAAAA==.',
['Mâ']='Mâk:BAAALgADCggJCAAAAA==.',
Na='Napalm:BAAALgAECgUJBQABLgAECgkJLgACAIYcAA==.',
Ne='Neero:BAABLgAECn8jAAIdAAcJrBy6NwDSAQAdAAcJrBy6NwDSAQAAAA==.Nelena:BAABLgAECn84AAIVAAgJ4Qm4VABFAQAVAAgJ4Qm4VABFAQAAAA==.Nenyve:BAAALgADCgQJBQAAAA==.Nerodrachen:BAAALgADCgMJAwAAAA==.Newgrim:BAAALgADCgMJAwAAAA==.Newurt:BAAALgAECgQJCwAAAA==.Nezhyt:BAABLgAECn8qAAMIAAgJ4B6MAwBBAgAIAAgJKh6MAwBBAgAHAAUJeh4mEwAZAQABLgAFFAEJAQAFAAAAAA==.',
Ni='Nicolbolas:BAABLgAECn8iAAMeAAkJNRZ7GQDzAQAeAAkJNRZ7GQDzAQAgAAIJewIVRQBHAAAAAA==.Nightshow:BAAALgADCgUJBQAAAA==.',
No='Nori:BAACLgAFFH8KAAIYAAQJ1yVfAgCfAQAYAAQJ1yVfAgCfAQAuAAQKfxkAAhgABwnrJXAEAJYCABgABwnrJXAEAJYCAAEuAAUUCAksAAIAUiQA.Notdragon:BAAALgADCgMJBQAAAA==.Notorious:BAABLgAECn8jAAMgAAkJgRYpBwB4AgAgAAkJgRYpBwB4AgAeAAMJYRB8XQCdAAAAAA==.',
Nt='Ntaicen:BAAALgADCgMJAwAAAA==.',
Os='Osiris:BAAALgADCgYJBgAAAA==.',
Pa='Pandalin:BAAALgAECgEJAQAAAA==.Pap:BAAALgADCgYJCAAAAA==.Papavodou:BAAALgADCgQJBAAAAA==.Paýp:BAABLgAECn8tAAMeAAkJIhXFEwAoAgAeAAkJIhXFEwAoAgAgAAgJdwO7HQD7AAAAAA==.',
Pe='Pelgryn:BAAALgADCgUJBQAAAA==.Pentasaurusr:BAABLgAECn8eAAMKAAcJSh+bQAAMAgAKAAYJSh+bQAAMAgAIAAIJ6BkiTACJAAAAAA==.',
Pl='Platemedic:BAAALgAECgYJBwAAAA==.',
Po='Polevik:BAAALgAFFAEJAQAAAA==.Pookkee:BAAALgAECgYJCwAAAA==.Porkahantas:BAAALgAECgYJEwAAAA==.Portgasdace:BAAALgAECgEJAwAAAA==.',
Pp='Ppat:BAAALgAECgYJEQAAAA==.',
Py='Pyromainiac:BAAALgADCgEJAQAAAA==.',
Qu='Queteimporta:BAABLgAECn8dAAQSAAcJsRJoQgAmAQASAAcJuwxoQgAmAQAaAAMJ3BQPMwCaAAATAAQJ0guaWABZAAAAAA==.',
Ra='Ratamahatta:BAAALgAECgMJAwAAAA==.Rayeona:BAAALgAECgYJCwAAAA==.',
Re='Recheals:BAAALgAECggJCQAAAA==.Recmod:BAABLgAECn8dAAMhAAcJ+BiOIgBoAQAhAAcJ+BiOIgBoAQAiAAEJSxGUIQBBAAABLgAECggJCQAFAAAAAA==.Rendover:BAAALgAECgYJBwAAAA==.Return:BAABLgAECn8/AAIaAAkJdB/kBQDXAgAaAAkJdB/kBQDXAgAAAA==.Reze:BAAALgAECgYJBwAAAA==.',
Rh='Rhimeholt:BAABLgAECn8gAAMXAAkJ7hodEACFAgAXAAkJ7hodEACFAgAjAAEJgQpEkwAtAAAAAA==.',
Ri='Rikoria:BAAALgAECgYJDQAAAA==.',
Ro='Roussalina:BAAALgAECgEJBAAAAA==.Roxagar:BAAALgAECgQJBQABLgAECgcJGwABABgMAA==.',
Ry='Ryahask:BAABLgAECn8vAAIYAAkJwxHACwDcAQAYAAkJwxHACwDcAQAAAA==.',
['Rä']='Rädagast:BAAALgADCgIJAgAAAA==.',
Sa='Sadisticrage:BAABLgAECn89AAIEAAkJrR+aEQDGAgAEAAkJrR+aEQDGAgAAAA==.Sae:BAAALgAECgMJAwAAAA==.Sammyshoes:BAAALgAECggJDwAAAA==.Sanguine:BAAALgAECgYJCgAAAA==.',
Sc='Scottklam:BAAALgAECgYJCwAAAA==.Scrimbo:BAAALgAECgQJBQAAAA==.',
Se='Seaturtles:BAAALgADCgYJBgAAAA==.Seeturtle:BAABLgAECn8lAAMkAAkJ9B4KAwD4AQAkAAcJZyEKAwD4AQACAAgJLBpsYgCiAQAAAA==.Sellassie:BAAALgADCgYJDwAAAA==.Selvala:BAAALgAECgEJAgAAAA==.Selyste:BAAALgAECgEJAgAAAA==.Selûne:BAAALgAECgIJAgAAAA==.Senthara:BAAALgAECgYJCgAAAA==.',
Sh='Shadow:BAABLgAECn8bAAIPAAgJjhLtVgCvAQAPAAgJjhLtVgCvAQAAAA==.Shera:BAAALgADCgYJCwAAAA==.Shooter:BAAALgAECgEJAQAAAA==.Shxggy:BAAALgAECgEJAQAAAA==.',
Sk='Skull:BAAALgAECgEJAQAAAA==.',
Sl='Slagathor:BAAALgAECgMJAwAAAA==.Slippie:BAAALgAECgMJAwAAAA==.Slipstreamer:BAAALgADCgEJAQAAAA==.',
Sm='Smell:BAABLgAECn9EAAIEAAkJkhlXLQA0AgAEAAkJkhlXLQA0AgAAAA==.',
So='Solheim:BAACLgAFFH8IAAIEAAMJ5yFdNgApAQAEAAMJ5yFdNgApAQAuAAQKfxYAAgQACAlTJZ8RAMYCAAQACAlTJZ8RAMYCAAAA.',
Sp='Spacemonk:BAAALgAECgQJCAAAAA==.Spire:BAAALgAFFAIJAgAAAA==.Sproutling:BAABLgAECn8qAAMRAAkJkQkmSgBVAQARAAkJkQkmSgBVAQAcAAcJYAUjSgDJAAAAAA==.',
St='Stearphen:BAABLgAECn8VAAMaAAkJYBVbEQC/AQAaAAkJYBVbEQC/AQASAAEJ5wOhsAAqAAAAAA==.Stormy:BAAALgADCgEJAQAAAA==.Stumpi:BAAALgAECgcJDwAAAA==.',
Sw='Swazti:BAABLgAECn8eAAIKAAgJUxI6VACVAQAKAAgJUxI6VACVAQAAAA==.',
Ta='Tashir:BAAALgADCgcJBwABLgAECgkJBgAFAAAAAA==.Taurnil:BAACLgAFFH8IAAIHAAIJpQtlDACWAAAHAAIJpQtlDACWAAAuAAQKfzgAAgcACAnUGA4GAAECAAcACAnUGA4GAAECAAAA.',
Te='Teledor:BAAALgAECgQJBgAAAA==.Teloiv:BAAALgADCggJBwAAAA==.Telperion:BAAALgADCgYJBgAAAA==.',
Th='Thadontrump:BAAALgAECgMJBAAAAA==.',
Ti='Tibidari:BAAALgAECgEJAQABLgAECgcJGwABABgMAA==.Timika:BAABLgAECn82AAMlAAgJfBttFwAAAgAlAAgJCxhtFwAAAgANAAYJ7xbiIgCWAQAAAA==.Tinysunn:BAAALgADCgYJBgAAAA==.',
To='Topharius:BAAALgADCgIJAgAAAA==.Toscc:BAAALgAECgMJBAAAAA==.',
Tr='Trales:BAAALgAECgYJBgAAAA==.',
Ty='Typeshift:BAABLgAFFH8QAAImAAUJlh/YBQBzAQAmAAUJlh/YBQBzAQAAAA==.',
Uc='Uchtdwarf:BAAALgAECgQJBAAAAA==.',
Ue='Uen:BAAALgAECgQJBwABLgAFFAcJHAAeALoWAA==.',
Uk='Ukan:BAAALgADCgQJAwAAAA==.',
Ux='Uxx:BAAALgAECgYJEwAAAA==.',
Va='Vaeron:BAABLgAECn8VAAIhAAcJ3huTFgDSAQAhAAcJ3huTFgDSAQAAAA==.',
Ve='Veckna:BAAALgADCgEJAQAAAA==.Velithria:BAAALgADCgUJBQAAAA==.Vengeancez:BAABLgAECn8iAAISAAkJKxB8KgAPAgASAAkJKxB8KgAPAgAAAA==.Venomsecho:BAABLgAECn8jAAInAAkJ2BQiDQDEAQAnAAkJ2BQiDQDEAQAAAA==.Venomshexo:BAAALgAECgEJAQAAAA==.Verboux:BAAALgAECgEJAQAAAA==.Versacé:BAAALgADCgEJAQAAAA==.',
Vi='Vicodin:BAAALgAECgEJAwAAAA==.Videl:BAAALgAECgEJAQAAAA==.Visionaries:BAAALgAECgUJCAAAAA==.',
Vo='Voldemort:BAAALgADCgcJBwAAAA==.Vorrixa:BAAALgAECggJEAAAAA==.',
We='Weathergirl:BAAALgAECgkJEwAAAA==.',
Wh='Whisky:BAAALgAECgYJCQAAAA==.',
Wi='Winniethefu:BAABLgAECn8jAAIXAAgJ0BiZFwADAgAXAAgJ0BiZFwADAgAAAA==.Wisps:BAAALgADCgEJAQABLgAECgYJBgAFAAAAAA==.',
Wo='Wolffire:BAAALgAECgMJAgABLgAECgQJCAAFAAAAAA==.',
Wy='Wy:BAAALgAECgYJDwAAAA==.',
Xa='Xanna:BAAALgAECgEJAgAAAA==.',
Xy='Xylith:BAACLgAFFH8GAAIGAAMJGhP4AwCeAAAGAAMJGhP4AwCeAAAuAAQKfycAAgYACAmlItwCAPsCAAYACAmlItwCAPsCAAAA.',
Ye='Yellowman:BAAALgADCgYJBgAAAA==.',
Yu='Yungdon:BAAALgADCggJCAAAAA==.Yunàlestrà:BAABLgAECn8bAAMKAAkJQg5yRQDAAQAKAAkJQg5yRQDAAQAIAAEJmAeQdgAuAAAAAA==.',
Za='Zach:BAABLgAECn8uAAICAAkJhhz0HACaAgACAAkJhhz0HACaAgAAAA==.',
Zm='Zmagez:BAAALgAECgYJDgAAAA==.',
Zy='Zylith:BAAALgAECgQJBQAAAA==.',
['Äv']='Ävatar:BAABLgAECn8UAAIXAAcJiwVaPADzAAAXAAcJiwVaPADzAAAAAA==.',
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
