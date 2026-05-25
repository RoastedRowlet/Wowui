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

local lookup = {'Hunter-Marksmanship','Mage-Frost','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Paladin-Protection','Warlock-Affliction','Warlock-Destruction','Rogue-Outlaw','Mage-Fire','Warlock-Demonology','Hunter-BeastMastery','Hunter-Survival','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','Druid-Restoration','Warrior-Fury','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Shaman-Enhancement','DeathKnight-Blood','DeathKnight-Frost','Warrior-Protection','DemonHunter-Vengeance','Druid-Balance','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Rogue-Subtlety','Monk-Windwalker','Priest-Holy','Druid-Guardian','Druid-Feral',}
local provider = {region='US',realm='Vashj',name='US',type='weekly',zone=46,date='2026-05-24',data={Ab='Abeloth:BAAALgAECgEJAQABLgAECgcJGwABABgMAA==.',
Ac='Achlyss:BAAALgAECgEJAQAAAA==.',
Ad='Adanto:BAAALgADCgEJAQAAAA==.Addequation:BAAALgAECgIJBQAAAA==.Adivh:BAAALgADCgEJAQAAAA==.',
Ah='Ahtreyou:BAAALgADCgIJAgAAAA==.',
Al='Alatär:BAABLgAECn8aAAICAAgJQxc9fwBfAQACAAgJQxc9fwBfAQAAAA==.Allorna:BAAALgAECgcJBwAAAA==.',
An='Angelona:BAACLgAFFH8SAAICAAUJCSMIKwB7AQACAAUJCSMIKwB7AQAuAAQKfyMAAgIACAkcJmQNAFoDAAIACAkcJmQNAFoDAAAA.Angelonah:BAAALgAECgQJBAAAAA==.Angelsenvy:BAABLgAECn81AAMDAAkJmCDPDACzAgADAAkJmCDPDACzAgAEAAEJ9gkMeQEqAAABLgAECgYJCQAFAAAAAA==.Anthela:BAAALgADCgcJBwAAAA==.',
Ar='Arabeth:BAAALgADCgMJAgAAAA==.Archadis:BAABLgAECn8eAAQEAAgJvhnCNgBIAgAEAAgJEhnCNgBIAgADAAMJWRudTADhAAAGAAEJdhtxPABIAAAAAA==.Archmond:BAABLgAECn8VAAMHAAcJJhczCwCIAQAHAAYJPxUzCwCIAQAIAAMJVROtPgC6AAAAAA==.Ardric:BAAALgADCgEJAQAAAA==.Arthek:BAAALgAECgUJCgAAAA==.',
As='Ashes:BAAALgAECgEJAQAAAA==.Ashteru:BAABLgAECn8jAAIDAAgJqhmUFABGAgADAAgJqhmUFABGAgAAAA==.Ashthundér:BAABLgAECn8WAAIJAAYJKhj7BACpAQAJAAYJKhj7BACpAQABLgAFFAQJCwAKAMMZAA==.',
Av='Avyhn:BAACLgAFFH8PAAMLAAYJiyEWDADvAQALAAUJiyEWDADvAQAHAAEJAACeIAAAAAAuAAQKfyAAAwsACQmhJdcBAHADAAsACAmhJdcBAHADAAgAAgl3JONBAK0AAAEuAAUUCAklAAsAaiMA.',
Az='Azlia:BAAALgAECgUJBQAAAA==.',
Ba='Baaka:BAABLgAECn8rAAMMAAgJiA7IUwB7AQAMAAgJiA7IUwB7AQANAAEJyQEDXQAkAAAAAA==.Bahumat:BAAALgADCgMJAwAAAA==.Bale:BAAALgAECgEJAQAAAA==.Barquiel:BAABLgAECn8qAAMGAAkJcx05BgBdAgAGAAkJcx05BgBdAgAEAAQJsA030ADQAAAAAA==.Batimo:BAAALgAECgQJBAAAAA==.Bayle:BAAALgADCgMJAwAAAA==.',
Be='Beamin:BAAALgADCgQJBAAAAA==.Beaversrock:BAAALgADCgcJEQAAAA==.Behp:BAAALgADCgcJBgAAAA==.Bellithia:BAABLgAECn8kAAMOAAkJHx4SCADSAgAOAAkJHx4SCADSAgAPAAEJNQulcwAwAAAAAA==.Belyne:BAAALgADCgEJAQAAAA==.',
Bi='Bielsebub:BAAALgADCgUJBQAAAA==.Biological:BAAALgAECgEJAQAAAA==.',
Bk='Bkdh:BAAALgAECgYJEAAAAA==.',
Bl='Blackmon:BAABLgAFFH8IAAIQAAMJUg0NfADeAAAQAAMJUg0NfADeAAAAAA==.Blitzkreig:BAAALgAECgYJCQAAAA==.Bløødy:BAAALgAECgEJAQABLgAECgUJBgAFAAAAAA==.',
Bo='Boomboombear:BAAALgAECgcJDQAAAA==.Boomya:BAABLgAECn8fAAIRAAgJ0hg9HQA6AgARAAgJ0hg9HQA6AgAAAA==.',
Br='Britneyspear:BAABLgAECn8mAAMSAAgJlRhXNQDUAQASAAcJ7BtXNQDUAQATAAUJZg/GKQD8AAAAAA==.Broken:BAAALgADCgMJBwAAAA==.',
Bu='Bubbulubb:BAABLgAECn8hAAIQAAkJXRfBRAAnAgAQAAkJXRfBRAAnAgAAAA==.Bullthing:BAABLgAECn8qAAQDAAkJ1CIlAgB3AwADAAkJ1CIlAgB3AwAEAAQJCRZ33wDOAAAGAAEJixu6OgBOAAAAAA==.',
Ca='Caladrial:BAAALgADCgMJAwAAAA==.Calex:BAABLgAECn8tAAMUAAgJSyA9FAAgAgAUAAgJSyA9FAAgAgAVAAUJaiDWOgCWAQAAAA==.Cassyn:BAAALgAECgEJBAAAAA==.Cathedrian:BAAALgADCgUJBQAAAA==.',
Ch='Chansey:BAABLgAECn8kAAIOAAkJWRzfCACuAgAOAAkJWRzfCACuAgAAAA==.Charged:BAAALgAECgMJBAAAAA==.Chesna:BAABLgAECn8oAAMWAAgJgR1IDwAqAgAWAAgJgR1IDwAqAgAXAAUJJwdaSQCzAAAAAA==.Chipsbambee:BAABLgAECn8kAAIMAAgJxg1GZQBPAQAMAAgJxg1GZQBPAQAAAA==.Chttr:BAAALgAECgMJBAAAAA==.Chttrbox:BAACLgAFFH8gAAMYAAcJnSK6AAD5AQAYAAYJcyS6AAD5AQAVAAUJExOxDAAPAQAuAAQKfzQAAxgACQnbJRUCAOgCABgACAk7JhUCAOgCABUACQlGGcQiAA4CAAAA.',
Co='Combust:BAACLgAFFH8LAAICAAQJXBj0OgBPAQACAAQJXBj0OgBPAQAuAAQKf0IAAgIACQl2Im0LAAkDAAIACQl2Im0LAAkDAAAA.Corstar:BAAALgADCgUJBQAAAA==.',
Cr='Crigillin:BAAALgADCgMJAwAAAA==.Crux:BAAALgAECgQJCAAAAA==.',
Da='Dalexios:BAAALgADCgYJAQAAAA==.Dallan:BAAALgADCgcJCgAAAA==.Daniella:BAAALgADCgYJBgAAAA==.Danyy:BAAALgAECgEJAQAAAA==.Dao:BAACLgAFFH8IAAIVAAMJzBR5EwDDAAAVAAMJzBR5EwDDAAAuAAQKfxUAAxUACAnEHMISAIACABUACAnEHMISAIACABQABAl+BBJxAGIAAAAA.Darelina:BAAALgADCgUJBQAAAA==.Darkhelmet:BAAALgADCggJDAAAAA==.Darkwarspark:BAAALgADCgQJAwAAAA==.',
De='Deadrat:BAAALgAECgYJCAAAAA==.Deathvader:BAAALgADCgcJDAAAAA==.Delaomega:BAABLgAECn8xAAMZAAkJvQqSHwAqAQAZAAkJvQqSHwAqAQAQAAEJjQbgOwExAAAAAA==.Derey:BAAALgADCgEJAgAAAA==.Devien:BAAALgADCgcJBwAAAA==.',
Di='Diber:BAAALgAECgMJAwAAAA==.Divinebovin:BAAALgADCgcJCAAAAA==.',
Dr='Drakvader:BAAALgAECgEJAQABLgAECgcJGwABABgMAA==.Drakvor:BAABLgAECn8uAAMZAAkJShXpCgBoAgAZAAkJShXpCgBoAgAQAAEJcQHlOwEbAAAAAA==.Drash:BAABLgAECn8xAAMaAAcJyhFhDgBGAQAaAAcJVRBhDgBGAQAZAAMJFBCBNwCNAAAAAA==.Drazgal:BAAALgADCgcJCQAAAA==.Dreni:BAAALgAECgEJAQAAAA==.',
Du='Duhai:BAAALgAECgUJBAAAAA==.Dumbledore:BAABLgAECn8pAAIZAAkJ/RlKCwAvAgAZAAkJ/RlKCwAvAgAAAA==.Dumpnloads:BAAALgADCgEJAgAAAA==.Durotagg:BAAALgAFFAEJAQAAAA==.',
['Dí']='Dím:BAAALgAECgYJCAAAAA==.',
Ea='Eaterofholes:BAAALgAECgEJAgAAAA==.',
Ed='Edubijes:BAAALgAECgYJCQABLgAECgcJHQASALESAA==.',
Eg='Egres:BAAALgAECgYJCwAAAA==.',
El='Elemequation:BAAALgAECgEJBAAAAA==.Elfguy:BAAALgADCgcJEwAAAA==.',
En='Endléss:BAABLgAECn8qAAINAAgJCRppFADoAQANAAgJCRppFADoAQAAAA==.Envision:BAAALgADCgQJAwABLgAECgUJCAAFAAAAAA==.',
Er='Erbium:BAAALgAECgQJBQAAAA==.Eremetrii:BAEALgAFFAEJAQAAAA==.',
Es='Eshwyn:BAAALgAECgYJBgAAAA==.Esquandolas:BAAALgADCgcJEgAAAA==.',
Ev='Evotibs:BAABLgAECn8bAAMBAAcJGAwrFQDvAAABAAcJGAwrFQDvAAANAAUJZQbnOADIAAAAAA==.',
Fe='Fec:BAAALgAECgYJBgABLgAECgkJNwAbAHQfAA==.',
Fi='Fibaldrachi:BAABLgAECn8tAAIcAAkJ9SMJAQAYAwAcAAkJ9SMJAQAYAwAAAA==.',
Fr='Fragnarr:BAAALgADCgQJBAAAAA==.Frosting:BAACLgAFFH8IAAICAAMJIxDoZwDpAAACAAMJIxDoZwDpAAAuAAQKfyEAAgIACAnrHWAzAC8CAAIACAnrHWAzAC8CAAAA.',
Ga='Galaxy:BAAALgADCgMJBQAAAA==.',
Gh='Ghantu:BAABLgAECn8ZAAIUAAgJ8BwpGQDwAQAUAAgJ8BwpGQDwAQAAAA==.Ghunk:BAAALgADCgYJBgAAAA==.',
Go='Goldennight:BAAALgADCgYJCQAAAA==.Gornathia:BAAALgAECgcJDQAAAA==.',
Gr='Grandall:BAAALgAECgEJAwAAAA==.Gruon:BAABLgAECn8xAAIdAAcJvw06MwAgAQAdAAcJvw06MwAgAQAAAA==.',
Gu='Gulzan:BAABLgAECn8YAAIUAAgJfBBrNAA+AQAUAAgJfBBrNAA+AQAAAA==.',
['Gø']='Gøkû:BAAALgAECgYJDgAAAA==.',
Ha='Hacks:BAABLgAECn8kAAIbAAgJBBGQFgBrAQAbAAgJBBGQFgBrAQAAAA==.Haymakerxd:BAABLgAECn8WAAIQAAgJqCMZCQAOAwAQAAgJqCMZCQAOAwAAAA==.',
He='Healtastic:BAAALgADCgcJBwAAAA==.Heealzz:BAAALgAECgYJDQAAAA==.Helendir:BAAALgAECgIJAgAAAA==.',
Hu='Huntercobra:BAAALgADCgUJBwAAAA==.Huntsagee:BAAALgADCgUJCAAAAA==.',
Hy='Hyacinthe:BAABLgAECn8oAAQHAAkJ9RvgAwBQAgAHAAkJ9RvgAwBQAgAIAAQJ3BFgHACkAAALAAMJCgymywCcAAAAAA==.Hypernova:BAAALgADCgMJAwAAAA==.',
Ib='Ibogaine:BAAALgADCgIJAgAAAA==.',
Ic='Iceshep:BAAALgAECgYJBwAAAA==.',
Id='Iden:BAAALgAECgYJCQAAAA==.Idtrapthát:BAAALgADCgMJAwAAAA==.',
Il='Illidanswife:BAAALgAECgYJDAAAAA==.Iluvatar:BAAALgADCgQJBAAAAA==.',
Im='Immamageboi:BAABLgAECn8kAAICAAcJLQhUowAeAQACAAcJLQhUowAeAQAAAA==.',
In='Infernal:BAAALgAECgcJCgAAAA==.Ingo:BAAALgADCgcJBwAAAA==.Inspiremoon:BAAALgAECgYJEAAAAA==.Interror:BAAALgAECgYJDgAAAA==.',
Ip='Ipak:BAAALgADCgEJAQAAAA==.',
Ir='Iranos:BAABLgAECn8nAAMEAAgJqiBqHQB5AgAEAAgJqiBqHQB5AgAGAAIJLgwHNwBcAAAAAA==.Irishpryde:BAAALgAECgEJAQAAAA==.',
Ja='Jackiechanda:BAAALgAECgQJCQAAAA==.Jaraxxus:BAAALgAECgUJCQABLgAECgYJDQAFAAAAAA==.',
Je='Jelipa:BAAALgADCgEJAQABLgAECgcJHQASALESAA==.',
Jo='Johnnylaw:BAAALgAECgMJAwAAAA==.Joshns:BAAALgADCgEJAQAAAA==.',
Ka='Kaellyn:BAAALgAECgUJCAAAAA==.Kaicelius:BAAALgAECgMJAwAAAA==.Kaimari:BAAALgADCgcJBwAAAA==.Kaloesh:BAAALgADCgQJBAABLgAECggJKgAIAOAeAA==.Kanakana:BAABLgAECn8nAAIVAAgJlR8REgCUAgAVAAgJlR8REgCUAgAAAA==.',
Ke='Kendana:BAAALgADCgYJDgAAAA==.Keyadron:BAAALgAECgUJCAAAAA==.',
Ki='Kindly:BAAALgAECgEJAgAAAA==.Kirab:BAABLgAECn8VAAIGAAgJeQUtKwCZAAAGAAgJeQUtKwCZAAAAAA==.Kirinmor:BAAALgADCggJCAAAAA==.Kis:BAAALgAECgUJBwAAAA==.Kisten:BAABLgAECn8XAAILAAgJhQOKoADqAAALAAgJhQOKoADqAAAAAA==.',
Ko='Kogorn:BAAALgADCgIJAgAAAA==.Kosmos:BAAALgAECgcJDAABLgAFFAEJAQAFAAAAAA==.',
Kr='Kreid:BAABLgAECn8ZAAIXAAgJABu4EABrAgAXAAgJABu4EABrAgAAAA==.Kreìd:BAAALgADCgEJAQABLgAECggJGQAXAAAbAA==.',
Ku='Kungfoupanda:BAAALgAECgIJAgAAAA==.',
Ky='Kyrr:BAAALgAFFAMJAwAAAA==.',
La='Larbear:BAAALgADCgIJAgAAAA==.Larrysham:BAAALgADCgEJAQAAAA==.',
Le='Lemén:BAABLgAECn8rAAIeAAgJZBQlQwCeAQAeAAgJZBQlQwCeAQAAAA==.Lenore:BAAALgAECgMJAwAAAA==.',
Li='Lierax:BAABLgAECn8tAAMfAAkJTh6ACwCHAgAfAAkJTh6ACwCHAgAgAAUJHBTxIQAbAQAAAA==.Lightpheonix:BAAALgADCgUJBQAAAA==.Ligmaw:BAAALgAECgQJCwAAAA==.Lildonny:BAAALgADCgYJBgAAAA==.Lilia:BAAALgAFFAcJBAAAAA==.Lilrobo:BAAALgADCgcJDQAAAA==.Linaei:BAABLgAECn8vAAIPAAkJsw+LGgDOAQAPAAkJsw+LGgDOAQAAAA==.Linestia:BAAALgAECgEJAgABLgAECgYJCwAFAAAAAA==.Littlewingz:BAABLgAECn8oAAIhAAgJzSOWAgAkAwAhAAgJzSOWAgAkAwAAAA==.',
Lo='Lockinflame:BAABLgAECn8UAAILAAgJUSBjFgCJAgALAAgJUSBjFgCJAgABLgAFFAQJCwAKAMMZAA==.Loka:BAAALgAECgEJAQAAAA==.',
['Lá']='Lálatina:BAAALgAECgIJAgAAAA==.',
Ma='Magnataur:BAAALgADCgQJBQAAAA==.Mahdek:BAAALgAECgMJBAABLgAECgUJBgAFAAAAAA==.Maladreks:BAAALgAECgEJAQAAAA==.Malsandre:BAAALgADCgUJBQABLgAECgkJKAAHAPUbAA==.Mascro:BAAALgADCgIJAgAAAA==.Maverrus:BAAALgADCgMJAwABLgAECgYJCwAFAAAAAA==.Mawz:BAABLgAECn8aAAIYAAgJ2hxkCQD3AQAYAAgJ2hxkCQD3AQAAAA==.Mayormcçhees:BAAALgADCgMJAwAAAA==.',
Me='Mecat:BAACLgAFFH8GAAIRAAIJQyJMMgDKAAARAAIJQyJMMgDKAAAuAAQKfyEAAhEACQnrImMJAPwCABEACQnrImMJAPwCAAAA.Meedlefinger:BAAALgAECgQJBQAAAA==.Megatonne:BAAALgADCgkJCQAAAA==.Melathia:BAABLgAECn8cAAILAAgJVQk2gwAgAQALAAgJVQk2gwAgAQAAAA==.Meliza:BAAALgAECgQJBwAAAA==.Melløw:BAAALgAECgEJAgAAAA==.',
Mo='Mommyshere:BAAALgADCgEJAQAAAA==.Monilara:BAAALgAECgQJBQAAAA==.Morman:BAAALgAECgkJAgAAAA==.',
Mu='Musclebear:BAACLgAFFH8JAAIiAAQJmQmUGQAcAQAiAAQJmQmUGQAcAQAuAAQKfxgAAiIACAkJF2gVANABACIACAkJF2gVANABAAAA.',
My='Mythaux:BAAALgADCgMJAwABLgAECggJKgAIAOAeAA==.',
['Mâ']='Mâk:BAAALgADCggJCAAAAA==.',
Na='Napalm:BAAALgAECgUJBQABLgAECgkJJwACAMUaAA==.',
Ne='Neero:BAABLgAECn8jAAIeAAcJrBz4MwDYAQAeAAcJrBz4MwDYAQAAAA==.Nelena:BAABLgAECn83AAIVAAgJ4QlETgBHAQAVAAgJ4QlETgBHAQAAAA==.Nenyve:BAAALgADCgQJBQAAAA==.Nerodrachen:BAAALgADCgMJAwAAAA==.Newgrim:BAAALgADCgMJAwAAAA==.Newurt:BAAALgAECgQJCgAAAA==.Nezhyt:BAABLgAECn8qAAMIAAgJ4B4XAwBHAgAIAAgJKh4XAwBHAgAHAAUJeh73EAAhAQAAAA==.',
Ni='Nicolbolas:BAABLgAECn8iAAMfAAkJNRaqFwD8AQAfAAkJNRaqFwD8AQAhAAIJewIVRQBHAAAAAA==.Nightshow:BAAALgADCgUJBQAAAA==.',
No='Nori:BAACLgAFFH8HAAIYAAMJtyJfCADzAAAYAAMJtyJfCADzAAAuAAQKfxkAAhgABwnrJeMDAJgCABgABwnrJeMDAJgCAAEuAAUUCAkoAAIAUiQA.Notdragon:BAAALgADCgIJAgAAAA==.Notorious:BAABLgAECn8jAAMhAAkJgRZ7BgB9AgAhAAkJgRZ7BgB9AgAfAAMJYRCEWwCeAAAAAA==.',
Nt='Ntaicen:BAAALgADCgMJAwAAAA==.',
Os='Osiris:BAAALgADCgYJBgAAAA==.',
Pa='Pap:BAAALgADCgYJCAAAAA==.Papavodou:BAAALgADCgQJBAAAAA==.Paýp:BAABLgAECn8kAAMfAAgJ1RGEIgCnAQAfAAgJ1RGEIgCnAQAhAAgJdwNMHAD7AAAAAA==.',
Pe='Pentasaurusr:BAABLgAECn8eAAMLAAcJSh+bQAAMAgALAAYJSh+bQAAMAgAIAAIJ6BkiTACJAAAAAA==.',
Pl='Platemedic:BAAALgAECgYJBwAAAA==.',
Po='Polevik:BAAALgAECgQJBgABLgAECggJKgAIAOAeAA==.Pookkee:BAAALgAECgYJCwAAAA==.Porkahantas:BAAALgAECgYJEwAAAA==.Portgasdace:BAAALgAECgEJAwAAAA==.',
Pp='Ppat:BAAALgAECgYJEQAAAA==.',
Py='Pyromainiac:BAAALgADCgEJAQAAAA==.',
Qu='Queteimporta:BAABLgAECn8dAAQSAAcJsRKOPQAqAQASAAcJuwyOPQAqAQAbAAMJ3BScLwCeAAATAAQJ0guEUABaAAAAAA==.',
Ra='Rayeona:BAAALgADCgYJBgAAAA==.',
Re='Recheals:BAAALgAECggJCQAAAA==.Recmod:BAABLgAECn8aAAIiAAcJ+BjPIABlAQAiAAcJ+BjPIABlAQABLgAECggJCQAFAAAAAA==.Rendover:BAAALgAECgYJBwAAAA==.Return:BAABLgAECn83AAIbAAkJdB/kBQDXAgAbAAkJdB/kBQDXAgAAAA==.Reze:BAAALgAECgYJBwAAAA==.',
Rh='Rhimeholt:BAABLgAECn8gAAMXAAkJ7hqQDgCFAgAXAAkJ7hqQDgCFAgAjAAEJgQrQhQAvAAAAAA==.',
Ri='Rikoria:BAAALgAECgYJDQAAAA==.',
Ro='Roussalina:BAAALgAECgEJBAAAAA==.',
Ry='Ryahask:BAABLgAECn8vAAIYAAkJwxGFCgDeAQAYAAkJwxGFCgDeAQAAAA==.',
['Rä']='Rädagast:BAAALgADCgIJAgAAAA==.',
Sa='Sadisticrage:BAABLgAECn89AAIEAAkJrR8UDwDUAgAEAAkJrR8UDwDUAgAAAA==.Sae:BAAALgAECgMJAwAAAA==.Sammyshoes:BAAALgAECggJDwAAAA==.Sanguine:BAAALgAECgYJCgAAAA==.',
Sc='Scottklam:BAAALgAECgYJCwAAAA==.Scrimbo:BAAALgAECgQJBQAAAA==.',
Se='Seaturtles:BAAALgADCgYJBgAAAA==.Seeturtle:BAABLgAECn8lAAMKAAkJ9B4KAwD4AQAKAAcJZyEKAwD4AQACAAgJLBpzXACvAQAAAA==.Sellassie:BAAALgADCgYJDwAAAA==.Selvala:BAAALgAECgEJAgAAAA==.Selyste:BAAALgAECgEJAQAAAA==.Selûne:BAAALgAECgIJAgAAAA==.Senthara:BAAALgAECgUJBQAAAA==.',
Sh='Shadow:BAABLgAECn8bAAIQAAgJjhIwUACyAQAQAAgJjhIwUACyAQAAAA==.Shera:BAAALgADCgYJCwAAAA==.Shooter:BAAALgAECgEJAQAAAA==.Shxggy:BAAALgAECgEJAQAAAA==.',
Sk='Skull:BAAALgAECgEJAQAAAA==.',
Sl='Slippie:BAAALgAECgMJAwAAAA==.Slipstreamer:BAAALgADCgEJAQAAAA==.',
Sm='Smell:BAABLgAECn89AAIEAAkJkhm7KAA/AgAEAAkJkhm7KAA/AgAAAA==.',
So='Solheim:BAACLgAFFH8FAAIEAAMJTRrYPQAQAQAEAAMJTRrYPQAQAQAuAAQKfxYAAgQACAlTJTsPANMCAAQACAlTJTsPANMCAAAA.',
Sp='Spacemonk:BAAALgAECgQJCAAAAA==.Spire:BAAALgAFFAIJAgAAAA==.Sproutling:BAABLgAECn8oAAMRAAgJggf7WAAPAQARAAgJggf7WAAPAQAdAAcJYAU6RQDJAAAAAA==.',
St='Stearphen:BAABLgAECn8VAAMbAAkJYBV7DwDKAQAbAAkJYBV7DwDKAQASAAEJ5wOhsAAqAAAAAA==.Stormy:BAAALgADCgEJAQAAAA==.Stumpi:BAAALgAECgcJDwAAAA==.',
Sw='Swazti:BAABLgAECn8eAAILAAgJUxIhTgCcAQALAAgJUxIhTgCcAQAAAA==.',
Ta='Tashir:BAAALgADCgcJBwABLgAECgkJAgAFAAAAAA==.Taurnil:BAACLgAFFH8HAAIHAAIJmQkKCgCSAAAHAAIJmQkKCgCSAAAuAAQKfzcAAgcACAnVGGIGAOYBAAcACAnVGGIGAOYBAAAA.',
Te='Teledor:BAAALgAECgQJBgAAAA==.Telperion:BAAALgADCgYJBgAAAA==.',
Th='Thadontrump:BAAALgAECgMJBAAAAA==.',
Ti='Tibidari:BAAALgAECgEJAQABLgAECgcJGwABABgMAA==.Timika:BAABLgAECn8vAAMkAAgJFxhIFQAGAgAkAAgJCxhIFQAGAgAOAAYJtw6yLwA0AQAAAA==.Tinysunn:BAAALgADCgYJBgAAAA==.',
To='Topharius:BAAALgADCgIJAgAAAA==.Toscc:BAAALgAECgMJBAAAAA==.',
Tr='Trales:BAAALgAECgYJBgAAAA==.',
Ty='Typeshift:BAABLgAFFH8OAAIlAAQJdB+bBAB2AQAlAAQJdB+bBAB2AQAAAA==.',
Uc='Uchtdwarf:BAAALgAECgQJBAAAAA==.',
Ue='Uen:BAAALgAECgQJBwABLgAFFAYJGgAfAFcYAA==.',
Uk='Ukan:BAAALgADCgQJAwAAAA==.',
Ux='Uxx:BAAALgAECgYJDgAAAA==.',
Va='Vaeron:BAABLgAECn8VAAIiAAcJ3htfFADbAQAiAAcJ3htfFADbAQAAAA==.',
Ve='Veckna:BAAALgADCgEJAQAAAA==.Velithria:BAAALgADCgUJBQAAAA==.Vengeancez:BAABLgAECn8iAAISAAkJKxB8KgAPAgASAAkJKxB8KgAPAgAAAA==.Venomsecho:BAABLgAECn8jAAImAAkJ2BTRCwDMAQAmAAkJ2BTRCwDMAQAAAA==.Versacé:BAAALgADCgEJAQAAAA==.',
Vi='Vicodin:BAAALgAECgEJAwAAAA==.Videl:BAAALgADCgEJAQAAAA==.Visionaries:BAAALgAECgUJCAAAAA==.',
Vo='Voldemort:BAAALgADCgcJBwAAAA==.Vorrixa:BAAALgAECgcJCgAAAA==.',
We='Weathergirl:BAAALgAECgkJEwAAAA==.',
Wh='Whisky:BAAALgAECgYJCQAAAA==.',
Wi='Winniethefu:BAABLgAECn8jAAIXAAgJ0BiZFwADAgAXAAgJ0BiZFwADAgAAAA==.Wisps:BAAALgADCgEJAQABLgAECgYJBgAFAAAAAA==.',
Wo='Wolffire:BAAALgAECgMJAgABLgAECgQJCAAFAAAAAA==.',
Wy='Wy:BAAALgAECgYJDwAAAA==.',
Xa='Xanna:BAAALgAECgEJAQAAAA==.',
Xy='Xylith:BAACLgAFFH8GAAIGAAMJGhP4AwCeAAAGAAMJGhP4AwCeAAAuAAQKfycAAgYACAmlItwCAPsCAAYACAmlItwCAPsCAAAA.',
Ye='Yellowman:BAAALgADCgYJBgAAAA==.',
Yu='Yungdon:BAAALgADCggJCAAAAA==.Yunàlestrà:BAAALgAECgcJEgAAAA==.',
Za='Zach:BAABLgAECn8nAAICAAkJxRq4IACCAgACAAkJxRq4IACCAgAAAA==.',
Zm='Zmagez:BAAALgAECgUJBgAAAA==.',
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
