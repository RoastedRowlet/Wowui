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

local lookup = {'DemonHunter-Havoc','Unknown-Unknown','Paladin-Retribution','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Warlock-Demonology','Mage-Frost','Mage-Arcane','Druid-Feral','Monk-Windwalker','Monk-Mistweaver','Hunter-Marksmanship','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Outlaw','Paladin-Protection','Monk-Brewmaster','Warlock-Destruction','Druid-Guardian','Druid-Balance','Paladin-Holy','Evoker-Augmentation','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','Druid-Restoration','Hunter-BeastMastery','Rogue-Assassination','Shaman-Enhancement','DemonHunter-Devourer','Priest-Holy','Warrior-Protection','Hunter-Survival','DemonHunter-Vengeance','Warlock-Affliction',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Actualape:BAAANQAECgQIBgAAAA==.',
Ad='Addy:BAABNQAECn8nAAIBAAgKRhgiJwBhAgABAAgKRhgiJwBhAgAAAA==.Adelethe:BAAANQADCgYIBgAAAA==.Aditu:BAAANQADCgMIAwAAAA==.',
Ae='Aestian:BAAANQAECgUIEAAAAA==.',
Ah='Ahhotep:BAAANQADCgEIAQAAAA==.',
Ai='Ailysely:BAAANQAECgIIAwAAAA==.Aispere:BAAANQAECgEIAgABNQAECgMIBgACAAAAAA==.',
Al='Alerzhulan:BAAANQAECgUIEAAAAA==.Aletheia:BAAANQADCggICAAAAA==.Alfurn:BAAANQADCgIIAgAAAA==.Aliveknightt:BAAANQADCggICAAAAA==.Alledria:BAABNQAECn8YAAIDAAgKPw7AowDUAQADAAgKPw7AowDUAQAAAA==.Alorely:BAABNQAECn8aAAMEAAcKvw90MgCLAQAEAAcKvw90MgCLAQAFAAMKWxCDGQCeAAAAAA==.',
Am='Amanara:BAAANQAECgUIEQAAAA==.Amoonia:BAAANQADCgYIEAAAAA==.',
An='Anciientpaw:BAABNQAECn8eAAMGAAgKux+CLgClAgAGAAgKux+CLgClAgAHAAMKIg1c8gCqAAAAAA==.Andrasomnius:BAAANQAECgQIBAAAAA==.Angbar:BAAANQAECgcIDwAAAA==.Anguirus:BAABNQAECn8hAAIHAAgKDQQ+qABAAQAHAAgKDQQ+qABAAQAAAA==.Anitax:BAAANQAECgcIDQABNQAECgkJGwAHAAwbAA==.Anuksunàmun:BAAANQADCgYIDAAAAA==.',
Ao='Aoman:BAAANQAECgEIAQAAAA==.',
Aq='Aqulenas:BAAANQAECgEIAQAAAA==.',
Ar='Arakhan:BAAANQADCggIFAAAAA==.Arcadian:BAABNQAECn8yAAMIAAgKExEnjwDyAQAIAAgK3hAnjwDyAQAJAAIKBREpJQCCAAAAAA==.Arceeprime:BAAANQAECgIIAgAAAA==.Arextheelder:BAAANQAECgUIDAAAAA==.Argentum:BAAANQADCggICAABNQAECggIJwABAEYYAA==.Armorscales:BAABNQAECn8dAAIKAAkKfSABMwC6AgAKAAkKfSABMwC6AgAAAA==.Arntraz:BAAANQAECgIIAwAAAA==.Arrabbiato:BAAANQAECggIEwAAAA==.Arronaxx:BAAANQADCgYIEAAAAA==.Arçadia:BAAANQAECgIIAgAAAA==.',
As='Ashnikko:BAAANQADCggIDQAAAA==.Ashtori:BAAANQABCgQIBgAAAA==.Asprika:BAAANQAECgcIEgAAAA==.Astayoni:BAAANQAECgQIBgAAAA==.Asterfleur:BAAANQAECgQIBAABNQAECgUIBgACAAAAAA==.Astrine:BAABNQAECn8gAAMLAAkKKxWwGwAQAQAMAAkKOxOIoQA9AgALAAYKng+wGwAQAQAAAA==.',
At='Ataraxya:BAAANQAECgYICgAAAA==.',
Au='Auberon:BAABNQAECn8kAAINAAkKKBmmCQClAgANAAkKKBmmCQClAgAAAA==.Aufta:BAABNQAECn8dAAMOAAcKowfMQgD8AAAOAAYKowfMQgD8AAAPAAYKNgU8MgDTAAAAAA==.Aumer:BAAANQADCggICAAAAA==.Aura:BAAANQADCgcIBwAAAA==.',
Az='Azi:BAACNQAFFH8NAAIQAAUKjRRXCwCEAQAQAAUKjRRXCwCEAQA1AAQKfysAAhAACQqlIFoRANoCABAACQqlIFoRANoCAAAA.Azurite:BAAANQADCgYIFQAAAA==.',
Ba='Backpedal:BAAANQAECgQIBAAAAA==.Badankhadonk:BAACNQAFFH8NAAMGAAUK/BzsCAC9AQAGAAUK/BzsCAC9AQAHAAEK1g6uLwBJAAA1AAQKfzcAAwYACQr7JF0FAJsDAAYACQr7JF0FAJsDAAcABAoXHVaoAD8BAAAA.Bakkutteh:BAAANQABCgIIBAAAAA==.Bakuhiko:BAAANQAECgUICAAAAA==.Balen:BAAANQAECgUICwAAAA==.Bandersin:BAAANQADCgUIBQAAAA==.Bansheex:BAAANQADCgQIBAAAAA==.Bariden:BAAANQADCgQIBAAAAA==.',
Be='Beefmuffinz:BAACNQAFFH8JAAIRAAUKNBOrCACLAQARAAUKNBOrCACLAQA1AAQKfyIAAhEACAq3IMgYAPcCABEACAq3IMgYAPcCAAAA.Beethozart:BAAANQADCggIEgAAAA==.Belcebu:BAAANQABCggIDgAAAA==.Belholy:BAAANQAECgUIEQAAAA==.Beliice:BAAANQADCgIIAgABNQAECgUIEQACAAAAAA==.Bellafleur:BAAANQAECgQICAABNQAECgUIBgACAAAAAA==.Bellawesome:BAAANQABCgQIBAAAAA==.Bendeekay:BAACNQAFFH8OAAISAAUKiyJ9CwCYAQASAAUKiyJ9CwCYAQA1AAQKfzAAAhIACQopIwcJAHADABIACQopIwcJAHADAAAA.Benilok:BAAANQAECgYIEQAAAA==.Bethgibbons:BAAANQADCgUJCAAAAA==.',
Bf='Bfh:BAAANQADCggIDAAAAA==.',
Bg='Bgpocalypse:BAAANQADCgYIBgAAAA==.',
Bi='Bigsuccubus:BAAANQAECgEIAQAAAA==.',
Bl='Blackblood:BAABNQAECn8eAAIBAAcKqgvRRwCEAQABAAcKqgvRRwCEAQAAAA==.Bloodache:BAAANQAECgcIEQAAAA==.Blux:BAAANQAECgMIBQAAAA==.',
Bo='Boil:BAABNQAECn8iAAITAAcKxASkEAAPAQATAAcKxASkEAAPAQAAAA==.Bonemarrow:BAAANQAECgMIBQAAAA==.Bordin:BAAANQADCgEIAQAAAA==.Bows:BAAANQAECggICAAAAA==.',
Br='Brakeable:BAAANQAECgYIBgAAAA==.Braké:BAABNQAECn8XAAIUAAcKFiGZFABcAgAUAAcKFiGZFABcAgAAAA==.Brewskies:BAABNQAECn8sAAIVAAgKXSNwBAAvAwAVAAgKXSNwBAAvAwAAAA==.Brightstar:BAAANQADCgUIBQAAAA==.Brioche:BAAANQADCgUIBgAAAA==.Brionthicc:BAAANQAECgMIBQABNQAFFAUIDwAWAMURAA==.Brownington:BAABNQAECn8iAAQXAAkKDCNpGADlAQAYAAYKwB+MPQAIAgAXAAUKfSJpGADlAQANAAIK0yGuKgC3AAAAAA==.Bruhilda:BAAANQAECgUIDQAAAA==.Brìonik:BAACNQAFFH8PAAMWAAUKxREHCgCpAAAKAAMKHgpRJADgAAAWAAIKbRkHCgCpAAA1AAQKfzIAAxYACQr8HSUHAJQCABYACApiGyUHAJQCAAoABwoXGrdvAAwCAAAA.',
Bu='Bubbleroundi:BAABNQAECn8xAAIZAAkKMhD0UAAlAgAZAAkKMhD0UAAlAgAAAA==.Bubudder:BAABNQAECn8uAAIRAAkKYiJMDABXAwARAAkKYiJMDABXAwAAAA==.Buffstuff:BAABNQAECn8fAAIaAAgKDw+NCgDEAQAaAAgKDw+NCgDEAQAAAA==.Burgerlock:BAAANQAECgEIAQAAAA==.',
Ca='Caeviro:BAAANQAECgYIEAAAAA==.Canadaishere:BAAANQADCgMIAwAAAA==.Cantheartitz:BAAANQAECgQICgAAAA==.Catdav:BAAANQAECgUIEQAAAA==.',
Ch='Charbol:BAAANQADCgQICAABNQADCggIEQACAAAAAA==.Chelraani:BAAANQAECgYIEwAAAA==.Chess:BAAANQAECgcICwAAAA==.Chiichard:BAAANQADCgYICAAAAA==.Chunkamonk:BAAANQADCgQIBgAAAA==.',
Ci='Ciarianna:BAAANQADCgcIBwABNQAECggIJwABAEYYAA==.Cigar:BAAANQADCgUICQABNQAECgYIEAACAAAAAA==.',
Cl='Clazzicola:BAACNQAFFH8JAAIOAAQKThqICQAyAQAOAAQKThqICQAyAQA1AAQKfyEAAg4ACQpTIbEVAKECAA4ACQpTIbEVAKECAAAA.',
Co='Combatwombat:BAAANQABCgEIAQAAAA==.Conjredcukee:BAAANQAECgMICgAAAA==.Coogsayer:BAAANQADCgIIAgAAAA==.Cowdeer:BAAANQAECgQIBgAAAA==.Cowgoboom:BAAANQADCgUIBQAAAA==.',
Cp='Cptncrush:BAABNQAECn8dAAMGAAcKKxzkVQANAgAGAAcKKxzkVQANAgAHAAMKexO55wDBAAAAAA==.',
Cr='Creamsickle:BAAANQABCgIIBAAAAA==.Creature:BAAANQAECgEIAwAAAA==.',
Cu='Cupcakes:BAAANQADCgcIEwAAAA==.Cutethulu:BAABNQAECn8hAAIEAAkKaBThHwA4AgAEAAkKaBThHwA4AgAAAA==.',
Cy='Cydarr:BAAANQADCgQIBAAAAA==.Cyther:BAACNQAFFH8PAAIJAAUKTBqTAADPAQAJAAUKTBqTAADPAQA1AAQKfzIAAgkACQqdJcoAALwDAAkACQqdJcoAALwDAAAA.',
Da='Dadbodftw:BAAANQAECgQIEQAAAA==.Daddylight:BAABNQAECn8YAAIDAAYK2gtS6QBCAQADAAYK2gtS6QBCAQAAAA==.Daelyn:BAAANQADCgYIAgAAAA==.Dakk:BAAANQADCggICAAAAA==.Darkdottie:BAAANQAECgYIDgAAAA==.Darkenstormy:BAAANQAECgEIAQAAAA==.Darkmage:BAAANQADCgQIAwAAAA==.Dayday:BAAANQAECggICAAAAA==.',
De='Deadlight:BAABNQAECn8rAAIbAAkKVxBiNwD0AQAbAAkKVxBiNwD0AQAAAA==.Deadtofall:BAAANQADCgcIFQAAAA==.Deathshikzs:BAABNQAECn8hAAISAAgKuBtQKgBwAgASAAgKuBtQKgBwAgABNQAECgkJGwAHAAwbAA==.Decix:BAAANQAECgIIAgABNQAFFAQIDAAEAH8VAA==.Deet:BAAANQADCgMJAwAAAA==.Deity:BAABNQAECn8ZAAMJAAkKsx4vAwAsAwAJAAkKsx4vAwAsAwAIAAIK8BKLKQF6AAABNQAECgkJIQAOAIcaAA==.Demonllxll:BAAANQAECgUIDgAAAA==.Demontime:BAAANQADCgcIDAABNQAECgQIBAACAAAAAA==.Desolation:BAABNQAECn8rAAIMAAgKMCPUNQAeAwAMAAgKMCPUNQAeAwAAAA==.Despia:BAAANQAECgYIEwAAAA==.Devastacia:BAAANQADCggICAAAAA==.',
Di='Dicot:BAAANQAECgYIEwAAAA==.Diety:BAABNQAECn8hAAIOAAkKhxoGEwC/AgAOAAkKhxoGEwC/AgAAAA==.Dimension:BAAANQAECgEIAQAAAA==.Disconnect:BAAANQABCgUICQAAAA==.',
Dj='Djpallyd:BAABNQAECn8fAAIDAAkK0xb+gAAiAgADAAkK0xb+gAAiAgAAAA==.',
Do='Dotmami:BAAANQAECgcICwAAAA==.Doughy:BAAANQADCggIEAAAAA==.',
Dr='Dragonu:BAABNQAECn84AAMcAAkKdiHoBABeAwAcAAkKdiHoBABeAwAdAAEKAAD7OwA1AAABNQAFFAQIBAACAAAAAA==.Draktyr:BAACNQAFFH8JAAIIAAQK5BCdGgA5AQAIAAQK5BCdGgA5AQA1AAQKfy8AAwgACQoUI4IXAFoDAAgACQoUI4IXAFoDAAkAAQoAAFc1AC4AAAAA.Drlovely:BAAANQADCgQIBAAAAA==.Droody:BAAANQABCgIIAgAAAA==.',
El='Elianda:BAAANQADCggIDgAAAA==.Ellalais:BAAANQAECgQICgAAAA==.Ellismom:BAABNQAECn8rAAIRAAgKfx0RLwBxAgARAAgKfx0RLwBxAgAAAA==.',
En='Enamorada:BAAANQAECgIIBAABNQAECggIHAAGAKwZAA==.Enchanceurpp:BAAANQADCggIGQAAAA==.End:BAAANQAECgUIBwAAAA==.',
Eo='Eolyndin:BAAANQADCgQIBAAAAA==.Eolyndyn:BAAANQADCgQIBQAAAA==.',
Er='Ereithelda:BAACNQAFFH8OAAIPAAUK7hY6BACWAQAPAAUK7hY6BACWAQA1AAQKfzIAAg8ACQofJI8DAHcDAA8ACQofJI8DAHcDAAAA.Ericka:BAAANQADCgYIBwAAAA==.Erina:BAAANQABCggIDwAAAA==.Erowid:BAAANQADCggICwABNQAFFAQIBAACAAAAAA==.Errutu:BAABNQAECn8sAAIeAAgK+hB3GgABAgAeAAgK+hB3GgABAgAAAA==.',
Ev='Evox:BAAANQAECgUIDgAAAA==.',
Fa='Falgar:BAAANQAECgQIBAAAAA==.Fann:BAABNQAECn8eAAIfAAcKwwaqQQAWAQAfAAcKwwaqQQAWAQAAAA==.Fargrim:BAAANQADCggIEQAAAA==.Fauna:BAAANQADCggICAAAAA==.',
Fe='Feathiir:BAAANQADCgIIAgAAAA==.Fewz:BAACNQAFFH8OAAMLAAUKlCNwAAD9AQALAAUKlCNwAAD9AQAMAAEKAADGYgA/AAA1AAQKfzUAAwsACQo8JmoAANMDAAsACQo8JmoAANMDAAwAAQoQD/y8ATwAAAAA.',
Fl='Flakflap:BAAANQAECgUIBQABNQAFFAIIBQASADsPAA==.Flakov:BAAANQADCggIDgABNQAFFAIIBQASADsPAA==.Flaktop:BAACNQAFFH8FAAISAAIKOw82IwBvAAASAAIKOw82IwBvAAA1AAQKfy8AAhIACQqGHsQfALICABIACQqGHsQfALICAAAA.Flatplate:BAAANQADCgUIBQAAAA==.Fler:BAAANQAECgQIBQAAAA==.Fluffie:BAAANQABCgcICgAAAA==.',
Fo='Forbacon:BAABNQAECn8hAAMSAAgKcBlgNQA0AgASAAgKcBlgNQA0AgAbAAMKrAl6hACUAAAAAA==.Force:BAABNQAECn8YAAMbAAcKigSdZAAGAQAbAAcKigSdZAAGAQARAAEKRwNo8gAiAAAAAA==.Fouris:BAAANQAECgIIAwAAAA==.',
Fr='Fridgie:BAACNQAFFH8PAAIgAAUKghJzCgChAQAgAAUKghJzCgChAQA1AAQKfzAAAiAACQr2I7wZADEDACAACQr2I7wZADEDAAAA.Friggenmage:BAAANQAECgYICgAAAA==.Frostbitte:BAAANQADCgEIAQAAAA==.Frozenruby:BAAANQABCggIDQAAAA==.Frozenturtle:BAAANQAECgYIEgAAAA==.',
Ft='Ftwiamtank:BAAANQAECggIEwAAAA==.',
Fu='Fuerte:BAAANQABCgQIAwAAAA==.',
Ga='Garcutt:BAACNQAFFH8KAAIMAAUKegn+HwCBAQAMAAUKegn+HwCBAQA1AAQKfywAAgwACQrqHD5rAKcCAAwACQrqHD5rAKcCAAAA.',
Ge='Geddan:BAAANQADCgYICAAAAA==.Genericck:BAAANQAFFAIIAgAAAA==.Genericdh:BAAANQAFFAEIAQAAAA==.Genericpal:BAABNQAECn8qAAMUAAkKFSEBCgD6AgAUAAgKQSQBCgD6AgADAAMKUQ9AQgGvAAAAAA==.Geritol:BAAANQADCggICAAAAA==.',
Gi='Gichio:BAAANQAECgUIBQAAAA==.Ginrai:BAAANQADCgUIBQAAAA==.',
Gl='Gladstone:BAAANQAECgMIBQAAAA==.',
Gn='Gnawbear:BAEBNQAECn8kAAIhAAkKzRb7KQA/AgAhAAkKzRb7KQA/AgAAAA==.',
Go='Goatassassin:BAABNQAECn8iAAMeAAgKwhLCFQAzAgAeAAgKwhLCFQAzAgAhAAIKawr7jQBuAAAAAA==.Goatshifter:BAAANQAECgMIBAABNQAECggIIgAeAMISAA==.Gobogoolina:BAAANQADCgYIDgAAAA==.',
Gr='Grayeyes:BAAANQADCgMIAwAAAA==.Greenngoblin:BAAANQAECgQIBQAAAA==.Grämps:BAAANQADCgYIBgAAAA==.',
Gu='Guino:BAAANQAECgQIBwAAAA==.',
Gw='Gwenelly:BAAANQADCgYICQAAAA==.',
Ha='Haikuu:BAAANQADCgcIBwAAAA==.Hamnqueso:BAAANQADCgYIDgABNQAECgQIEQACAAAAAA==.Hardeesdelux:BAAANQAECgQICAAAAA==.Hazis:BAACNQAFFH8GAAISAAQK5hExFQAGAQASAAQK5hExFQAGAQA1AAQKfzMAAhIACQrkHZ4VAP0CABIACQrkHZ4VAP0CAAAA.',
Hi='Hinala:BAABNQAECn8mAAISAAkKSAsWVQCdAQASAAkKSAsWVQCdAQAAAA==.',
Ho='Holy:BAAANQAECgUIBQABNQAFFAUIBwAHAEwLAA==.Holydad:BAAANQADCgcIBwAAAA==.Honeybutter:BAABNQAECn82AAMIAAkKMyavAgDmAwAIAAkKMyavAgDmAwAJAAEKAADvMAA6AAAAAA==.Hordebreaker:BAAANQABCgIIAgAAAA==.',
Hu='Huesitos:BAAANQAECgUIDQAAAA==.Huntzilla:BAAANQADCgYICwAAAA==.Huukend:BAABNQAECn8qAAIgAAgKlCKBIwAHAwAgAAgKlCKBIwAHAwAAAA==.',
In='Inanitas:BAAANQADCggICAAAAA==.Innominot:BAAANQAECgQIBQAAAA==.',
Ir='Irukox:BAAANQAECgMIAwAAAA==.',
Ja='Jackoldean:BAAANQADCgUICwAAAA==.Jacques:BAAANQADCggICAAAAA==.Jadaveon:BAAANQAECgUIBQAAAA==.Jalene:BAAANQAECgQICgAAAA==.Jargen:BAAANQADCgYIBwABNQADCggIEQACAAAAAA==.',
Je='Jettabae:BAAANQAECgIIBAABNQAFFAUIDwADAFgLAA==.Jettadari:BAAANQAECgYICgABNQAFFAUIDwADAFgLAA==.Jettadin:BAACNQAFFH8PAAIDAAUKWAtrDQBwAQADAAUKWAtrDQBwAQA1AAQKfyUAAgMACQo9IqUoACEDAAMACQo9IqUoACEDAAAA.',
Jt='Jt:BAAANQAECgcICwAAAA==.',
Jw='Jwalker:BAAANQADCgQIBQAAAA==.',
['Jë']='Jëks:BAACNQAFFH8PAAIGAAUKDBcKCgCqAQAGAAUKDBcKCgCqAQA1AAQKfysAAwYACQoyIjYYABEDAAYACQoyIjYYABEDACIABApkDugoAM8AAAAA.',
Ka='Kakozaps:BAACNQAFFH8KAAMiAAUKnxhNAgC4AQAiAAUKnxhNAgC4AQAHAAEKmAzpMABGAAA1AAQKf0MAAyIACQq2JBoCAI8DACIACQqzJBoCAI8DAAcACAo7IMc3AJUCAAAA.Kalid:BAAANQAECgIIAgAAAA==.Kallar:BAAANQAECgcIEgABNQAECgcIGAACAAAAAA==.Kathrynne:BAAANQAECgQIBQAAAA==.Kayeera:BAAANQAECgYIDAAAAA==.Kaylrandi:BAAANQADCgYIGAAAAA==.Kayna:BAAANQAECgUIBQAAAA==.',
Ke='Kearza:BAAANQAECgUICgAAAA==.Keiyona:BAAANQADCgIIAgABNQAECgYIFwADAJgcAA==.Kennethv:BAAANQAECgUIEQAAAA==.Keny:BAAANQAECgUJBgABNQAECgYIDwACAAAAAA==.Kero:BAAANQADCgcICgABNQAECgcIGAACAAAAAA==.Kethie:BAAANQADCgcIBwAAAA==.Kethra:BAAANQADCgQIBAAAAA==.Kev:BAAANQAECggIBAAAAA==.',
Kh='Khalesie:BAAANQADCgIIBAAAAA==.Khibanee:BAAANQAECgQICQAAAA==.Khiell:BAABNQAECn8hAAMJAAgKIxlDCQBCAgAJAAcKsBpDCQBCAgAIAAIKxw/2MgFmAAAAAA==.Khrominius:BAABNQAECn8XAAIMAAcKAhMG4QDDAQAMAAcKAhMG4QDDAQAAAA==.',
Ki='Killthirsty:BAAANQADCgcIBwABNQAECgQIBAACAAAAAA==.Kinigit:BAAANQAECgUJCgABNQAFFAUIDgAYAAwbAA==.Kirïtö:BAAANQAECgUIBQAAAA==.Kitaradin:BAAANQAECgUIDgAAAA==.',
Kn='Knghtmre:BAACNQAFFH8HAAIMAAMKHw90OQDaAAAMAAMKHw90OQDaAAA1AAQKfycAAgwACQozGPFwAJwCAAwACQozGPFwAJwCAAAA.',
Ko='Komamura:BAAANQAECgMIAwAAAA==.Konpalitaa:BAAANQAECgEIAQAAAA==.',
Kr='Kragon:BAAANQADCggICAAAAA==.Krátos:BAABNQAECn8dAAIIAAgK1Rh7YwBhAgAIAAgK1Rh7YwBhAgAAAA==.',
Ku='Kungphu:BAAANQADCgYIBwAAAA==.Kuranaa:BAAANQAECgMIBgAAAA==.Kurulak:BAABNQAECn8jAAIjAAgKUw0MMAC9AQAjAAgKUw0MMAC9AQAAAA==.',
Ky='Kymru:BAAANQADCgYICQAAAA==.Kynn:BAAANQADCgMIAwAAAA==.',
La='Lacerveza:BAAANQAECgMIBQAAAA==.Lahyanhou:BAAANQAECgEIAQAAAA==.Lawanorder:BAAANQADCggIBwAAAA==.Laylah:BAAANQAECgEIAQAAAA==.',
Le='Leriope:BAABNQAECn8sAAIKAAgKdhHxgQDdAQAKAAgKdhHxgQDdAQAAAA==.',
Li='Lichfiend:BAAANQADCgYICgAAAA==.Lihpfu:BAAANQAECgUIDQABNQAECgkJIwAIAIMcAA==.Lilem:BAAANQADCgcICwAAAA==.Limboh:BAAANQADCgcIBwAAAA==.',
Lj='Lj:BAABNQAECn8jAAIZAAgKAh1KNQCMAgAZAAgKAh1KNQCMAgAAAA==.',
Lu='Luxure:BAAANQAECgEIAQAAAA==.',
Ma='Maegan:BAAANQADCgcIHwAAAA==.Mager:BAAANQAECgIIAwAAAA==.Mageshyte:BAACNQAFFH8IAAIMAAUK8QwGIgBwAQAMAAUK8QwGIgBwAQA1AAQKfzEAAgwACQrjH7NDAPwCAAwACQrjH7NDAPwCAAAA.Magolock:BAAANQAECgUIDwAAAA==.Magus:BAAANQADCggICAAAAA==.Maidrim:BAACNQAFFH8JAAIhAAUKthX8BgCmAQAhAAUKthX8BgCmAQA1AAQKfy8AAiEACQo5IYQSAOUCACEACQo5IYQSAOUCAAAA.Mamajumbo:BAABNQAECn8WAAIgAAcKARcLiQD1AQAgAAcKARcLiQD1AQAAAA==.Mana:BAACNQAFFH8HAAIHAAUKTAs7EQBSAQAHAAUKTAs7EQBSAQA1AAQKfzIAAgcACQoHHacqANMCAAcACQoHHacqANMCAAAA.Marellias:BAABNQAECn8YAAMgAAgKbx6vLgDfAgAgAAgKbx6vLgDfAgAQAAEK7wb5jwAuAAABNQAECggIHwADANglAA==.Marikel:BAAANQAECgQIBwAAAA==.Marlea:BAABNQAECn8gAAMIAAcKvRZafgAbAgAIAAcKvRZafgAbAgAJAAEKAACFKgBaAAAAAA==.Maruka:BAABNQAECn81AAIKAAkKjSKaDwBSAwAKAAkKjSKaDwBSAwAAAA==.Matthiias:BAAANQAECgIIAgAAAA==.Mawenzi:BAAANQADCggICAABNQAECgcIIQAkADASAA==.',
Me='Meletha:BAAANQADCggICAAAAA==.Meronpan:BAAANQADCgYICwAAAA==.Metahorfasis:BAAANQADCgcIBwAAAA==.',
Mi='Michaelken:BAABNQAECn8ZAAIZAAcKFhTybgDIAQAZAAcKFhTybgDIAQAAAA==.Midari:BAAANQADCgEIAQAAAA==.Mierin:BAAANQADCgUIBQAAAA==.Mierín:BAAANQAECgIJAgAAAA==.Migrains:BAABNQAECn8rAAIUAAgKvh15DgCyAgAUAAgKvh15DgCyAgAAAA==.Mileyvyrus:BAAANQAFFAEIAQABNQAFFAQIDQAlAAghAA==.Milkmesloppy:BAAANQADCgYIBgABNQAECgkJHQAKAH0gAA==.Miskaabin:BAABNQAECn8aAAMUAAcKoBNIJwCgAQAUAAcKoBNIJwCgAQADAAUKLAdQIwHeAAAAAA==.Missdemon:BAAANQADCggICAAAAA==.',
Mo='Mogral:BAAANQADCgUICAAAAA==.Mojodaddy:BAAANQABCgQIBgAAAA==.Mojogreens:BAAANQADCgUICwAAAA==.Monsart:BAAANQADCggIFQAAAA==.Montura:BAAANQADCgQIBAAAAA==.Moonie:BAAANQADCgYICwAAAA==.Moonpetals:BAAANQADCgMJBQAAAA==.Moralizdormi:BAABNQAECn8mAAIaAAgK2AkEDQB9AQAaAAgK2AkEDQB9AQAAAA==.Moregana:BAAANQAECgEIAQAAAA==.Mortiis:BAAANQAECgcIBwAAAA==.',
Mp='Mpd:BAAANQAECgUIBgAAAA==.',
My='Mylendria:BAAANQABCgYIBwAAAA==.Mystique:BAAANQAECgUICwAAAA==.Mytmo:BAAANQADCgMIAwAAAA==.',
['Mí']='Míerín:BAACNQAFFH8JAAIgAAQKrxsrEABSAQAgAAQKrxsrEABSAQA1AAQKfzMAAiAACQrqJX4FALYDACAACQrqJX4FALYDAAAA.',
Na='Naama:BAAANQADCgcIEgAAAA==.Naelih:BAAANQAECgcIEgAAAA==.Nargo:BAAANQABCgMIAQAAAA==.Natlès:BAAANQAECgMIAwABNQAECgcICwACAAAAAA==.Natzu:BAAANQAECgMIBQAAAA==.Naushan:BAAANQADCgIIAgAAAA==.Nazari:BAACNQAFFH8GAAIDAAQKMQPkFgDtAAADAAQKMQPkFgDtAAA1AAQKfygAAgMACQo+GKaKAAwCAAMACQo+GKaKAAwCAAAA.',
Ne='Necronu:BAAANQADCggICAABNQAFFAQIBAACAAAAAA==.',
Ni='Nikkolos:BAAANQADCgUIBQAAAA==.',
No='Nogusta:BAACNQAFFH8MAAIIAAUKVQpBFgBuAQAIAAUKVQpBFgBuAQA1AAQKfzEAAggACQqSGs9PAJcCAAgACQqSGs9PAJcCAAAA.Notdecix:BAACNQAFFH8MAAMEAAQKfxUODQADAQAEAAMKfxUODQADAQAkAAIKcAEcLwBiAAA1AAQKfyUAAwQACQpwHxkOAAsDAAQACQpwHxkOAAsDACQACApdFitXABkCAAAA.',
Nu='Nuggets:BAAANQAECgUICQAAAA==.',
Ob='Obyss:BAAANQADCgUIBQAAAA==.',
Od='Odinsrain:BAAANQAECgUIBgABNQAFFAIIBQAZAAkYAA==.',
On='Onlyshams:BAAANQAECgYICQAAAA==.Onubolt:BAAANQADCgMIAwABNQAFFAQIBAACAAAAAA==.Onulock:BAAANQAFFAQIBAAAAA==.',
Oo='Oorggtejedor:BAAANQADCgUIBQAAAA==.',
Or='Orondo:BAAANQAECgUIEAAAAA==.',
Os='Ospfiend:BAAANQADCgYIBgAAAA==.',
Ou='Oumura:BAAANQAECgQIBAAAAA==.',
Pa='Palinia:BAAANQAECgcICAAAAA==.Pallyoop:BAABNQAECn8ZAAMZAAgKTAt3fACgAQAZAAgKTAt3fACgAQADAAYKkgVbFQH1AAAAAA==.Pandarina:BAAANQADCgYIEAAAAA==.Papilock:BAAANQADCgUIBQABNQAECggIHAAGAKwZAA==.Pathalogical:BAAANQADCggIDwABNQAECggICAACAAAAAA==.Patharok:BAAANQADCgMIAwABNQAECggICAACAAAAAA==.Pathator:BAAANQAECgYICwABNQAECggICAACAAAAAA==.Patheros:BAAANQAECggICAAAAA==.Patholan:BAAANQADCggICAABNQAECggICAACAAAAAA==.Patholans:BAAANQADCgEIAQABNQAECggICAACAAAAAA==.Paxmansigh:BAAANQAECgMIBwAAAA==.',
Ph='Phantöm:BAABNQAECn8pAAIJAAcK8RygCABXAgAJAAcK8RygCABXAgAAAA==.',
Pl='Placcid:BAABNQAECn8jAAIgAAgK+Q9GdwAdAgAgAAgK+Q9GdwAdAgAAAA==.Planknstein:BAAANQAECggICgAAAA==.Plantoor:BAABNQAECn8qAAImAAgKqhXmBQBLAgAmAAgKqhXmBQBLAgAAAA==.',
Po='Pockett:BAAANQAECgIIAgAAAA==.Ponarp:BAAANQAECgQJCgAAAA==.Porkchop:BAABNQAECn8sAAMHAAgKowqGdwC3AQAHAAgKowqGdwC3AQAGAAgKHw/jeACdAQAAAA==.',
Pr='Primøs:BAAANQAECgUIBQAAAA==.Prismclaw:BAABNQAECn8bAAILAAgKVA/LDwCnAQALAAgKVA/LDwCnAQAAAA==.Processing:BAACNQAFFH8PAAIYAAUK+Q86CwC3AQAYAAUK+Q86CwC3AQA1AAQKfzIAAhgACQrCISsWABMDABgACQrCISsWABMDAAAA.',
Pu='Puddle:BAAANQAECgUIDQAAAA==.Puddleheal:BAAANQAECgEIAQABNQAECgQICAACAAAAAA==.Puffdamagic:BAABNQAECn8xAAMcAAkKGg3EHwDWAQAcAAkKGg3EHwDWAQAaAAgKswfWDQBqAQAAAA==.',
Pw='Pwnstarz:BAAANQADCgYIEQAAAA==.',
Py='Pyous:BAAANQAECgUIBQAAAA==.',
Qi='Qirstbytt:BAAANQADCgUIBQAAAA==.',
Qp='Qplus:BAABNQAECn8eAAIgAAcK0wu+rACnAQAgAAcK0wu+rACnAQAAAA==.',
Qs='Qstorm:BAAANQADCgcIDQAAAA==.',
Qu='Quaenie:BAABNQAECn8dAAIkAAcKGw/7hwB6AQAkAAcKGw/7hwB6AQAAAA==.Quintin:BAAANQAECgUIBQAAAA==.',
Ra='Ragetotem:BAAANQADCgIIAgAAAA==.Ragewarg:BAAANQAECgEIAQAAAA==.Raginsteel:BAAANQADCgYICwAAAA==.Ralvarr:BAAANQAECgQICAAAAA==.Rayleigh:BAAANQAECgUIEQABNQAECgUIBQACAAAAAA==.',
Re='Reckligence:BAAANQADCgIIAgAAAA==.Redchord:BAAANQAECgQICAAAAA==.Regidør:BAABNQAFFH8HAAMDAAQKjRdPFgDzAAADAAMKjRdPFgDzAAAZAAEKxQ9/JgBSAAAAAA==.Regixa:BAAANQAECgcIDAAAAA==.Relik:BAABNQAECn8bAAMlAAcKuBDJIwAlAQAlAAYKVw/JIwAlAQAIAAUKkgw38wDyAAAAAA==.',
Rh='Rhaelia:BAAANQADCgUIBQAAAA==.Rhaspus:BAAANQAECgUIEAAAAA==.',
Ri='Rillenne:BAAANQAECgQIBAAAAA==.Rilliccine:BAAANQAECgIIAgAAAA==.Rilliguine:BAAANQADCgQIBQAAAA==.Rillinetti:BAABNQAECn8dAAIKAAcK5BJAkwCxAQAKAAcK5BJAkwCxAQAAAA==.Rillini:BAAANQAECgQICAAAAA==.Rilliti:BAAANQAECgIIAgAAAA==.Risky:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.Rivertam:BAAANQADCggICAAAAA==.',
Ro='Robotnik:BAAANQAECgIIAQAAAA==.Rogu:BAAANQADCgYIEAAAAA==.Rondon:BAAANQAECgYIEwAAAA==.Rookdh:BAACNQAFFH8PAAIBAAUKPxJnCQCQAQABAAUKPxJnCQCQAQA1AAQKfzEAAgEACQomICMUAPkCAAEACQomICMUAPkCAAAA.Rosey:BAABNQAECn8bAAIDAAcKTBDjwwCOAQADAAcKTBDjwwCOAQAAAA==.Royale:BAAANQAECgYIEgAAAA==.',
Ru='Rudeus:BAAANQAECgQIBgAAAA==.Rudyeightbal:BAAANQADCgYIBgAAAA==.Rum:BAAANQADCggIJAAAAA==.Rustedbarrel:BAAANQAECgUIBwAAAA==.',
Sa='Saelyres:BAAANQAECggIDAAAAA==.Sagesse:BAAANQADCggJFAAAAA==.Saisera:BAAANQAECgQIBAAAAA==.Samifleur:BAAANQAECgUIBgAAAA==.Sammy:BAABNQAECn8eAAMDAAcK+AlQ2ABkAQADAAcK+AlQ2ABkAQAZAAEKaQFqNgEbAAAAAA==.Santaclaaws:BAACNQAFFH8LAAIjAAUKdh+hBQDRAQAjAAUKdh+hBQDRAQA1AAQKfzgAAyMACQpLJbECAK8DACMACQpLJbECAK8DAAEAAgo/HP14AI0AAAAA.Santafuego:BAAANQAECgUICgABNQAFFAUICwAjAHYfAA==.Santapal:BAABNQAECn8sAAMZAAkKvRy+IQDkAgAZAAkKvRy+IQDkAgADAAEKBAQuuAEpAAABNQAFFAUICwAjAHYfAA==.Saphotic:BAAANQAFFAEIAQABNQAFFAQIDAAEAH8VAA==.Saydragon:BAAANQADCgQIBAAAAA==.Sayvil:BAAANQAECgcIGAAAAQ==.',
Se='Selbor:BAAANQAECgUICQAAAA==.Semmers:BAABNQAECn8VAAIPAAgK8QurIQB1AQAPAAgK8QurIQB1AQAAAA==.Sensational:BAAANQAECggIEgAAAA==.Septiria:BAAANQAECgQICAAAAA==.Sergio:BAAANQADCgcIDwAAAA==.Seyren:BAAANQADCgQIBAAAAA==.',
Sh='Shabelly:BAAANQADCgYJBgABNQADCgYIBgACAAAAAA==.Shalash:BAAANQADCgYIBgABNQAFFAMIBwAhABgLAA==.Shamadeano:BAAANQAECgUICgAAAA==.Shamanshikz:BAABNQAECn8bAAIHAAkKDBv4MwCmAgAHAAkKDBv4MwCmAgAAAA==.Shamiska:BAAANQAECggIEQAAAA==.Shammerdown:BAAANQADCgIIAgAAAA==.Shampooh:BAAANQAECgEIAQAAAA==.Shamrockk:BAAANQADCggICAAAAA==.Shaokhan:BAABNQAECn8qAAIGAAkKaxqnKAC/AgAGAAkKaxqnKAC/AgAAAA==.Sharazzy:BAAANQAECgIIAgAAAA==.Sharpcukuee:BAAANQAECgEIAQAAAA==.Shian:BAAANQAECgYIEwAAAA==.Shieldee:BAABNQAECn8fAAIDAAgKoBmIbgBPAgADAAgKoBmIbgBPAgAAAA==.Shigaraki:BAAANQAECgcICgAAAA==.Shikzzs:BAABNQAECn8cAAInAAgKYyEfBAAMAwAnAAgKYyEfBAAMAwABNQAECgkJGwAHAAwbAA==.Shockeei:BAABNQAECn8rAAIMAAkKHSSqIQBUAwAMAAkKHSSqIQBUAwAAAA==.Shortdon:BAAANQADCgEIAQAAAA==.Shortebus:BAAANQAECgQIBAAAAA==.',
Si='Sighh:BAAANQADCgEIAQAAAA==.Sighhy:BAAANQADCggIDQAAAA==.Sijth:BAABNQAECn9TAAMZAAgK7R7+JgDLAgAZAAgK7R7+JgDLAgADAAQKbRH4PQG2AAAAAA==.Silvereyes:BAAANQADCgIIAgAAAA==.Silverwar:BAABNQAECn8iAAIlAAgK6Bo1DABwAgAlAAgK6Bo1DABwAgAAAA==.Simmi:BAEANQAECgUIBwABNQAFFAUIDgAZAIkbAA==.Simmune:BAECNQAFFH8OAAIZAAUKiRt0BwDrAQAZAAUKiRt0BwDrAQA1AAQKfysAAhkACQo5Ir0LAGkDABkACQo5Ir0LAGkDAAAA.Sinarala:BAAANQADCggIEQAAAA==.Sirlavan:BAAANQADCgcIBwAAAA==.Sixpath:BAAANQADCgQIAgAAAA==.',
Sk='Skanknstein:BAAANQAECgIIAgAAAA==.Skepti:BAABNQAECn8dAAIgAAgKxB7EOwC0AgAgAAgKxB7EOwC0AgAAAA==.Skreep:BAAANQADCgUIBQAAAA==.',
Sl='Slybiscuit:BAABNQAECn8fAAIiAAcKeQbJHQCAAQAiAAcKeQbJHQCAAQAAAA==.',
Sm='Smeeta:BAABNQAECn8rAAISAAkKCyBGFgD4AgASAAkKCyBGFgD4AgAAAA==.Smokesmash:BAAANQADCgcIBwAAAA==.',
Sn='Sneakerbaby:BAAANQADCgYIBgAAAA==.',
So='Solaace:BAAANQADCgcIBwABNQAECgQICwACAAAAAA==.Soram:BAAANQADCgYIBgAAAA==.Sosa:BAAANQAECgMIBwAAAA==.Soulreaver:BAAANQADCgQIBAAAAA==.Sourdevil:BAAANQABCgIJBAAAAA==.Soùl:BAAANQAECgQICgAAAA==.',
Sp='Sparkley:BAAANQAECgUICQABNQAECgkJMQAcABoNAA==.Spike:BAAANQAECgYIDAAAAA==.Spinspinspin:BAAANQAECgYIBgAAAA==.',
St='Starlara:BAAANQADCgYIBgAAAA==.Stazz:BAABNQAECn8pAAIgAAgKowmwngDFAQAgAAgKowmwngDFAQAAAA==.Steelerayne:BAAANQAECgUIDgAAAA==.Stian:BAAANQAECgIIAgAAAA==.Stonecrab:BAAANQAECgcIDQAAAA==.Stormcontrol:BAABNQAECn8bAAIHAAgK+xFPawDbAQAHAAgK+xFPawDbAQAAAA==.Stormii:BAAANQAECgEIAQAAAA==.Stormtotem:BAAANQAECgEIAQAAAA==.Strangerdk:BAAANQAECgYIEwABNQAECgcICAACAAAAAA==.Styless:BAAANQABCgYIBwAAAA==.Stðne:BAAANQADCgMIAwAAAA==.',
Sv='Svenraiden:BAAANQABCgEIAQAAAA==.',
Sw='Swagboyxx:BAAANQADCgQIBAAAAA==.Swishersweet:BAABNQAECn8xAAIXAAgKsgqgJwBUAQAXAAgKsgqgJwBUAQAAAA==.Swordfish:BAAANQAECgQIBgAAAA==.',
Sy='Sybrooke:BAAANQAECgEIAQAAAA==.Sydran:BAAANQADCgMIAwAAAA==.Syrinne:BAAANQADCgEIAQAAAA==.',
Ta='Tabrieus:BAABNQAECn8sAAILAAgKISIVAwAdAwALAAgKISIVAwAdAwAAAA==.Taegia:BAAANQADCgUIBQABNQAFFAUIDgAPAO4WAA==.Talanth:BAABNQAECn8YAAIhAAcKCwydRgClAQAhAAcKCwydRgClAQAAAA==.Talbott:BAAANQADCgEIAQAAAA==.Tandisong:BAAANQADCgEIAQAAAA==.Tanitie:BAAANQADCgEIAQAAAA==.Tanknstein:BAAANQABCgMIAwAAAA==.Tarrisx:BAAANQADCgEJAQABNQAECgkJKwASAAsgAA==.Tashi:BAAANQADCggIDgAAAA==.Tayon:BAAANQAECgUIDAAAAA==.Tayvin:BAAANQADCgEIAQAAAA==.',
Te='Tearza:BAAANQADCgIIAgAAAA==.Termana:BAACNQAFFH8NAAIlAAQKCCFDAgB+AQAlAAQKCCFDAgB+AQA1AAQKfzIAAiUACQrEJcIAANkDACUACQrEJcIAANkDAAAA.',
Th='Thar:BAAANQADCgUJBQAAAA==.Thassa:BAAANQADCgEIAQAAAA==.Thegame:BAAANQADCgQIBAAAAA==.Theodoró:BAAANQAECggIEwAAAA==.Thereza:BAAANQAECgUICQAAAA==.Thiccpickle:BAAANQAECgEIAQABNQAECgcICwACAAAAAA==.Thug:BAAANQADCgcIFQAAAA==.Thundersylph:BAAANQABCgUIBgAAAA==.',
Ti='Tiferet:BAABNQAECn8jAAMkAAgK1x5LKgC9AgAkAAgK1x5LKgC9AgAEAAIK7wWKbQBLAAAAAA==.Tigiw:BAAANQAECgUICgAAAA==.Tinysunshine:BAAANQAECgUIDQAAAA==.Tinyt:BAAANQADCgMIAwAAAA==.Titonatty:BAAANQABCgQIBAAAAA==.',
To='Tolenkar:BAABNQAECn8eAAIgAAcKahjLjgDoAQAgAAcKahjLjgDoAQAAAA==.Tomato:BAACNQAFFH8JAAMWAAQKUgsiEACVAAAWAAIKSgwiEACVAAAKAAIKYwmoMwCPAAA1AAQKfykAAxYACQrMG2sGAKUCABYACAo5HWsGAKUCAAoABAqrFz3bAA4BAAAA.Torfelori:BAAANQAECgQICAAAAA==.Torvalar:BAABNQAECn8rAAIDAAgK7hLHkQD8AQADAAgK7hLHkQD8AQAAAA==.Tove:BAABNQAECn8aAAIHAAgKkQn8gwCXAQAHAAgKkQn8gwCXAQAAAA==.',
Tr='Trûth:BAAANQAECggIDwAAAA==.',
Tu='Turdyl:BAABNQAECn8hAAIDAAkKNg+8nwDdAQADAAkKNg+8nwDdAQAAAA==.',
Tw='Twindadlock:BAAANQABCgIIAgABNQAECgQIEQACAAAAAA==.',
Ty='Tyfelsion:BAAANQAECgEIAQAAAA==.Tyraz:BAAANQADCgUIBQAAAA==.Tyrelline:BAAANQAECgIJAgAAAA==.Tystrolf:BAAANQADCggIEQAAAA==.',
['Tá']='Tárris:BAABNQAECn8eAAIKAAgKUh3wQACMAgAKAAgKUh3wQACMAgABNQAECgkJKwASAAsgAA==.',
['Tæ']='Tægia:BAAANQAECgMIAwAAAA==.',
['Tô']='Tôx:BAABNQAECn8bAAMHAAgK9h0pQQBtAgAHAAgK9h0pQQBtAgAGAAMKOAnC6wCOAAAAAA==.',
Um='Umbranwings:BAABNQAECn8aAAQdAAYKqAj6IwAgAQAdAAYKqAj6IwAgAQAcAAYKAgMmNwDXAAAaAAEKAADdJgAmAAAAAA==.',
Un='Unheardjp:BAAANQAECgEIAQAAAA==.',
Ur='Ursus:BAABNQAECn8bAAIYAAgKbAkWUgCPAQAYAAgKbAkWUgCPAQAAAA==.',
Va='Vaerix:BAAANQAECgYIDQAAAA==.Valydrin:BAABNQAECn8lAAMkAAgK/RbuYAD6AQAkAAgK/RbuYAD6AQAEAAMKjwWgYQB1AAAAAA==.',
Ve='Veera:BAAANQADCgQIBAAAAA==.Vexadrine:BAACNQAFFH8PAAIVAAUKwBLJAwByAQAVAAUKwBLJAwByAQA1AAQKfzMAAhUACQpcHyYFABIDABUACQpcHyYFABIDAAAA.Vexiana:BAAANQAECgIIAgABNQAFFAUIDwAVAMASAA==.',
Vo='Vorkhan:BAAANQADCgEIAQAAAA==.',
Vu='Vuldrak:BAAANQAECggICAAAAA==.',
Vy='Vysis:BAACNQAFFH8NAAIEAAUKgRJ2CACCAQAEAAUKgRJ2CACCAQA1AAQKfzQABAQACQojHJ8PAPgCAAQACQojHJ8PAPgCACQABwpOIOZcAAcCAAUABQrUGtwKAJUBAAAA.',
['Ví']='Ví:BAAANQAECgEIAQAAAA==.',
Wa='Warstorm:BAAANQAECgQIBAAAAA==.',
We='Weebdestroya:BAAANQADCgIIAgAAAA==.',
Wh='Whisperfål:BAAANQADCgIIAgAAAA==.',
Wi='Wickèr:BAABNQAECn8gAAQVAAgK6xcnDgASAgAVAAgK6xcnDgASAgAOAAUKFxB9QQAFAQAPAAQKWQhmOgCZAAAAAA==.Widgit:BAAANQADCgUIDAAAAA==.Wieldblade:BAABNQAECn8sAAMDAAgKGBVmgwAdAgADAAgKGBVmgwAdAgAZAAYK0BDEkgBjAQAAAA==.',
Wo='Woolverine:BAAANQAECgUIEAAAAA==.',
Wu='Wunderbar:BAAANQAECgYIEwAAAA==.',
Wy='Wyldfire:BAACNQAFFH8OAAIYAAUKDBtbCwC1AQAYAAUKCxtbCwC1AQA1AAQKfzUAAhgACQpRI8YIAIgDABgACQpRI8YIAIgDAAAA.',
Xa='Xanith:BAAANQAECgcIDQAAAA==.Xanyth:BAAANQADCggICAAAAA==.',
Xi='Xia:BAAANQADCgYIBgAAAA==.',
Ya='Yardly:BAAANQADCggIEQAAAA==.',
Yi='Yia:BAAANQAECgUIDgABNQAECgUIDwACAAAAAA==.Yilnara:BAAANQAECgEIAQAAAA==.',
Ys='Ysa:BAABNQAECn8bAAMOAAkKIyNrBgBoAwAOAAkKIyNrBgBoAwAPAAIK5AoLQgBjAAAAAA==.',
Za='Zalerodora:BAAANQADCgEIAQABNQAECgUIEAACAAAAAA==.Zarich:BAABNQAECn8dAAIoAAgKOxsrBACgAgAoAAgKOxsrBACgAgAAAA==.',
Ze='Zekkun:BAAANQADCggICAAAAA==.',
Zo='Zoga:BAEANQADCgUIBQABNQAECgcIHAAGAC0eAA==.Zogah:BAEANQAECgQIBAABNQAECgcIHAAGAC0eAA==.Zoganian:BAEANQAECgQICQABNQAECgcIHAAGAC0eAA==.Zoghog:BAAANQAECgQIBgAAAA==.Zogula:BAEANQADCgYIBgABNQAECgcIHAAGAC0eAA==.',
Zu='Zullthornp:BAAANQADCgUICQAAAA==.',
Zy='Zyaire:BAAANQABCgQIBQAAAA==.',
['Æb']='Æbony:BAAANQABCgIIAgAAAA==.',
['Ço']='Çosmos:BAAANQADCgUIBwAAAA==.',
['Év']='Évélýn:BAAANQADCgUIBQAAAA==.',
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
