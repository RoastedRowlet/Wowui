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

local lookup = {'Unknown-Unknown','Hunter-Survival','Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Augmentation','Shaman-Restoration','Paladin-Retribution','DemonHunter-Havoc','Priest-Holy','Druid-Balance','Druid-Restoration','Shaman-Elemental','Priest-Shadow','Mage-Frost','Paladin-Holy','DeathKnight-Blood','Druid-Feral','Warrior-Fury','Warrior-Arms','Priest-Discipline','Hunter-Marksmanship','Hunter-BeastMastery','Evoker-Devastation','Paladin-Protection','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','Druid-Guardian','Mage-Fire','Rogue-Outlaw','Evoker-Preservation','Rogue-Assassination','DemonHunter-Vengeance','Monk-Brewmaster','Shaman-Enhancement',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Ablestract:BAAALgADCggJCQAAAA==.',
Ac='Acid:BAAALgAECggJDwAAAA==.',
Ad='Adam:BAAALgAFFAEJAgABLgAFFAEJBAABAAAAAA==.Adreane:BAAALgAECgMJBAAAAA==.',
Af='Aftrlyfe:BAAALgAECgkJCQAAAA==.',
Ai='Aiyana:BAAALgADCgkJEQAAAA==.',
Ak='Akamma:BAAALgAECgcJDgAAAA==.Akarimos:BAAALgADCgMJAwAAAA==.',
Al='Alealle:BAAALgADCgMJAwAAAA==.Algeriono:BAAALgAECgMJAwAAAA==.Aliluna:BAAALgAECgYJCwAAAA==.Alirain:BAAALgAECgUJBwAAAA==.Alispere:BAAALgADCgUJBQAAAA==.Aliwings:BAAALgAECgEJBAAAAA==.Alizaranna:BAAALgADCgEJAQABLgAECgYJEwABAAAAAA==.',
Am='Amarokk:BAABLgAECn8eAAICAAcJCginLAAuAQACAAcJCginLAAuAQAAAA==.Ameliae:BAAALgAECgEJAQAAAA==.',
An='Ancestor:BAABLgAECn8ZAAIDAAYJghagIwBdAQADAAYJghagIwBdAQAAAA==.Anish:BAAALgAECgEJAQAAAA==.',
Aq='Aqurore:BAAALgADCgYJBgAAAA==.',
Ar='Archaia:BAAALgAECgUJCQAAAA==.Argorok:BAAALgAFFAEJAQAAAA==.Aryi:BAAALgAECgkJEgAAAA==.',
As='Askim:BAAALgADCgcJBwAAAA==.Assyla:BAAALgAECgEJAQAAAA==.Astraeos:BAABLgAFFH8GAAIEAAMJKx5kVAAJAQAEAAMJKx5kVAAJAQAAAA==.',
Au='Auv:BAACLgAFFH8QAAMEAAQJESaEBwCtAQAEAAQJESaEBwCtAQAFAAEJlQBjGwA6AAAuAAQKfxQAAwUABwmJJkMTALEBAAQABQkZJl9MAOMBAAUABAkgJkMTALEBAAEuAAUUBQkNAAYADCQA.',
Aw='Awekeha:BAAALgADCgIJAgAAAA==.',
Ax='Axël:BAAALgAFFAEJAQABLgAFFAMJBgAHAKsaAA==.',
Ay='Aylranoa:BAAALgADCgkJCQAAAA==.',
Az='Azimondius:BAACLgAFFH8QAAIIAAQJCRloHQA9AQAIAAQJCRloHQA9AQAuAAQKfzMAAggACQlYId0EAP8CAAgACQlYId0EAP8CAAAA.Azmora:BAAALgAECgcJDgAAAA==.Azzix:BAAALgADCgQJBQAAAA==.',
Ba='Baddragons:BAAALgADCgYJBgAAAA==.Bandit:BAAALgAECgEJAQAAAA==.Bastis:BAAALgAECgEJBAABLgAFFAQJDQAJALEmAA==.Batreaux:BAAALgAFFAEJAgAAAA==.',
Be='Beaman:BAAALgADCgEJAQAAAA==.Bearkake:BAAALgAECgMJBgAAAA==.Bellgrande:BAAALgADCgYJBgAAAA==.Belthora:BAAALgAECgYJCAAAAA==.Bepallylol:BAACLgAFFH8IAAIKAAUJfgyeKABHAQAKAAUJfgyeKABHAQAuAAQKfxgAAgoACAliHbEtAGwCAAoACAliHbEtAGwCAAAA.',
Bi='Bigkeith:BAAALgADCgEJAQAAAA==.Biraj:BAAALgADCggJEAABLgAECgcJJwAKAHYIAA==.',
Bl='Blaqichan:BAAALgADCgEJAwABLgADCgQJBQABAAAAAA==.Blight:BAAALgADCgcJBQAAAA==.Bloodybecky:BAAALgAECgQJBQAAAA==.',
Br='Brakiyamis:BAAALgAECgEJAQAAAA==.Brewmastah:BAAALgAECgYJCgABLgAECgUJBwABAAAAAA==.Browntotem:BAAALgADCgUJCAAAAA==.',
Bu='Bubblecheeks:BAAALgAECgQJBQAAAA==.Bubblehëarth:BAAALgAECgYJDwAAAA==.Bubby:BAABLgAECn8WAAIEAAcJPx2OQQAIAgAEAAcJPx2OQQAIAgAAAA==.Bucklebunnie:BAAALgADCgEJAQABLgAFFAUJDQALAMkNAA==.Bulgestomper:BAAALgAECgQJBgAAAA==.Bullzaye:BAAALgAECgQJBAAAAA==.Burbuja:BAABLgAECn8UAAIMAAYJvBHwMgAkAQAMAAYJvBHwMgAkAQAAAA==.',
Ca='Cadfile:BAAALgAECgQJBgAAAA==.Careco:BAAALgADCgYJBgAAAA==.Carpetcrumbs:BAAALgAECgUJBQAAAA==.Catnsevrmeme:BAAALgAECgEJAgAAAA==.',
Ce='Cecilio:BAAALgAECgMJAwAAAA==.Cel:BAAALgAECgEJAgAAAA==.Celzara:BAAALgAECgEJAQAAAA==.Cernunnös:BAAALgADCgIJAgAAAA==.Cetraa:BAACLgAFFH8GAAMNAAMJngsXLACsAAANAAMJngsXLACsAAAOAAEJtRipXABKAAAuAAQKfyMAAw0ACAmEGykSADECAA0ACAmEGykSADECAA4AAQkTDgzLACwAAAAA.',
Ch='Chastise:BAAALgAECgkJDgAAAA==.Chewÿ:BAAALgAECgcJAwAAAA==.Chii:BAAALgADCgEJAQAAAA==.Chocobro:BAAALgAECgYJCQAAAA==.Chäös:BAAALgAECgUJBQAAAA==.',
Cl='Clingy:BAAALgAECgEJAQAAAA==.',
Co='Cobble:BAABLgAECn8dAAIPAAgJExjxGgDxAQAPAAgJExjxGgDxAQAAAA==.Colhap:BAABLgAECn8ZAAIQAAcJJhzLIQDJAQAQAAcJJhzLIQDJAQAAAA==.Conjure:BAABLgAECn80AAMFAAgJThf1BgDOAQAFAAcJuRn1BgDOAQAEAAgJmQ05dwBAAQAAAA==.Corbina:BAABLgAECn8jAAIRAAgJ6iJ2NQCeAgARAAgJ6iJ2NQCeAgAAAA==.Cousinlarry:BAAALgADCgIJAgABLgADCgQJBQABAAAAAA==.',
Cr='Cramlutin:BAAALgADCgUJBQAAAA==.Cru:BAAALgAECgkJDgAAAA==.Crui:BAAALgADCgcJBwAAAA==.',
Cu='Culligan:BAACLgAFFH8FAAIRAAMJAwvZdADYAAARAAMJAwvZdADYAAAuAAQKf3EAAhEACQnfHsUTAM4CABEACQnfHsUTAM4CAAAA.Cuttingcrew:BAAALgADCggJCAAAAA==.',
Cy='Cyclones:BAAALgADCgYJBgABLgAECgUJBQABAAAAAA==.Cygwin:BAABLgAECn81AAMJAAgJoRs/FwB3AgAJAAgJoRs/FwB3AgAPAAMJZxETYwCfAAAAAA==.',
Da='Daarius:BAAALgADCgYJBgAAAA==.Darcfrost:BAAALgAECgEJAQAAAA==.Darcyonys:BAAALgAECgIJBQAAAA==.Dariao:BAAALgAECgIJAgABLgAECgkJLQAGAM8ZAA==.Darkironsham:BAAALgAFFAEJAQAAAA==.Darklon:BAAALgAECgkJEwAAAA==.Darknescomez:BAAALgAECgQJCAABLgAECggJJwAPADAYAA==.Darkpun:BAAALgADCgcJCQAAAA==.Darîus:BAAALgAECgMJAwAAAA==.Dat:BAAALgAECgcJAQABLgAFFAIJBwARAPkYAA==.Datmage:BAACLgAFFH8HAAIRAAIJ+RhmiACdAAARAAIJ+RhmiACdAAAuAAQKfxkAAhEABwl4H3FeAB8CABEABwl4H3FeAB8CAAAA.',
De='Deathshockz:BAAALgAECgQJBQABLgAECgUJBQABAAAAAA==.Demunzz:BAAALgADCgUJCQAAAA==.Deriah:BAABLgAECn8pAAIKAAgJoBQ3UADxAQAKAAgJoBQ3UADxAQAAAA==.Derpatron:BAABLgAECn8UAAMKAAkJzgixgABSAQAKAAkJzgixgABSAQASAAEJuQ6gkwA3AAAAAA==.Destruction:BAABLgAECn8WAAITAAgJuQXrLgDNAAATAAgJuQXrLgDNAAAAAA==.Devo:BAEBLgAFFH8LAAIUAAQJORegBQA3AQAUAAQJORegBQA3AQAAAA==.',
Di='Dingers:BAAALgAECggJCAABLgAECgkJDwABAAAAAA==.Disgusti:BAAALgAECggJEwAAAA==.Divinespark:BAABLgAECn8jAAIMAAgJMRXULACTAQAMAAgJMRXULACTAQAAAA==.',
Dk='Dkins:BAAALgAECgIJAgAAAA==.',
Do='Dogeform:BAAALgADCgEJAQAAAA==.Doinkbigs:BAABLgAECn8iAAIEAAgJXQ1AYwBuAQAEAAgJXQ1AYwBuAQAAAA==.Doomo:BAAALgADCgYJBgABLgABCgQJBAABAAAAAA==.Dotsfired:BAAALgADCgQJBAAAAA==.Dotñtrot:BAAALgAFFAIJAgABLgAFFAMJCwAJADUZAA==.',
Dr='Draeneisham:BAAALgAFFAEJAQAAAA==.Dredd:BAAALgAECgQJDQAAAA==.Drewsilla:BAAALgAECgYJDwAAAA==.Druidrose:BAAALgAECgMJAwAAAA==.Druidtrix:BAAALgADCgYJCwAAAA==.Drylogic:BAABLgAECn8xAAIOAAkJAx8yCgAHAwAOAAkJAx8yCgAHAwAAAA==.',
Du='Duckworth:BAAALgAECgEJAQAAAA==.Duruk:BAABLgAECn8VAAIEAAcJIxjqSAC0AQAEAAcJIxjqSAC0AQAAAA==.Dustbroom:BAAALgAECgEJAQAAAA==.',
Ea='Eap:BAAALgAECgcJDwAAAA==.Eazye:BAACLgAFFH8RAAIQAAQJ5A4iGgADAQAQAAQJ5A4iGgADAQAuAAQKfzcAAhAACQlXHFYNAGMCABAACQlXHFYNAGMCAAAA.',
Eb='Ebone:BAAALgADCgMJAQAAAA==.',
Ec='Ectoscourge:BAAALgADCgcJBgAAAA==.',
Ed='Edgeffs:BAABLgAECn8eAAMVAAgJewr6PAA8AQAVAAgJHAn6PAA8AQAWAAUJZQj5JADFAAAAAA==.',
Ek='Eklipse:BAAALgADCgMJAwABLgABCgQJBAABAAAAAA==.',
El='Elentiya:BAABLgAECn8kAAMMAAkJvxyYDgB1AgAMAAkJvxyYDgB1AgAXAAEJegd7WgAtAAAAAA==.Elphzz:BAABLgAECn8YAAIDAAgJ+BL1HgADAgADAAgJ+BL1HgADAgAAAA==.',
Em='Emoose:BAAALgAECgEJAQAAAA==.',
Er='Eriius:BAAALgAECgYJEgAAAA==.',
Ev='Evestar:BAAALgADCgEJAQAAAA==.',
Ez='Ez:BAACLgAFFH8VAAMYAAcJWBVxEAAmAQAYAAYJZhBxEAAmAQAZAAIJuBlLZwCcAAAuAAQKfyoAAxgACAn0H6UYAGcCABgACAn0H6UYAGcCABkAAgmXDSL5AEQAAAAA.Ezarath:BAABLgAECn8pAAIaAAYJywuSDwAAAQAaAAYJywuSDwAAAQAAAA==.',
Fa='Fadedaf:BAABLgAECn8UAAIGAAYJjQ0viwANAQAGAAYJjQ0viwANAQAAAA==.',
Fe='Felenn:BAAALgADCgYJDQABLgAECgcJJwAKAHYIAA==.Felorc:BAAALgAECgYJCwAAAA==.Fentun:BAAALgAFFAEJAQAAAA==.Feyla:BAAALgAECgUJCQAAAA==.',
Fi='Finnikey:BAAALgAECgIJBAAAAA==.Firstone:BAAALgADCgYJBgAAAA==.',
Fo='Foofs:BAAALgADCgUJBQAAAA==.Foulmuffn:BAAALgADCgYJCQAAAA==.Foulplay:BAAALgADCgMJAwAAAA==.Fovos:BAAALgAECgEJAQAAAA==.',
Fr='Freakonleash:BAABLgAECn8YAAIVAAgJ/Rn7GQB8AgAVAAgJ/Rn7GQB8AgAAAA==.Frimbooze:BAAALgAECgYJBwAAAA==.',
Fu='Fuegodotz:BAAALgADCgUJBQABLgAECgkJIgAHABcdAA==.Fumonkchu:BAAALgADCgIJAQAAAA==.',
['Fé']='Féarôshima:BAAALgAECgEJAQABLgAECggJJwAPADAYAA==.',
Ga='Ganjåfarian:BAAALgAECgIJAgAAAA==.',
Ge='Gekatta:BAAALgAECgYJEAAAAA==.Gelektrael:BAABLgAECn8jAAMEAAgJjwvmbgBSAQAEAAgJ0QrmbgBSAQAFAAEJXAz9dQAvAAAAAA==.',
Gh='Ghostdk:BAAALgADCggJCAABLgAFFAUJEAAKAIAfAA==.Ghostwarrior:BAAALgADCgMJAwABLgAFFAUJEAAKAIAfAA==.Ghostzz:BAACLgAFFH8QAAIKAAUJgB/2FwCBAQAKAAUJgB/2FwCBAQAuAAQKf1AAAwoACQmbI4UHAB4DAAoACQmbI4UHAB4DABsABQkSHhwYAEIBAAAA.',
Gl='Glarb:BAAALgAECgIJAwAAAA==.Glzygldiator:BAACLgAFFH8OAAIHAAMJ1BhXLgDhAAAHAAMJ1BhXLgDhAAAuAAQKfykAAgcACAkWH3I1ABUCAAcACAkWH3I1ABUCAAAA.',
Gn='Gnomelock:BAAALgAFFAEJAQABLgAFFAEJBAABAAAAAA==.',
Go='Gobblin:BAAALgAECgUJDQAAAA==.Gotbandaids:BAAALgAECgEJAQAAAA==.Govegan:BAAALgADCgQJBwAAAA==.',
Gr='Graavey:BAAALgAECgcJAwABLgAFFAMJCwAJADUZAA==.Greyhairs:BAAALgAECgcJEgAAAA==.Grimthor:BAAALgAECgcJBwAAAA==.Grippy:BAACLgAFFH8HAAIGAAMJRwaCXgCyAAAGAAMJRwaCXgCyAAAuAAQKfyYAAgYACAl/HUoiAIQCAAYACAl/HUoiAIQCAAAA.Gromit:BAACLgAFFH8cAAIMAAYJhxxSBQDaAQAMAAYJhxxSBQDaAQAuAAQKfyQAAwwACQlNIZMDACEDAAwACQlNIZMDACEDABcAAgmnEUdKAG0AAAAA.Grym:BAAALgADCgcJDgAAAA==.',
Gu='Gustófwind:BAACLgAFFH8IAAIcAAQJJSEeBwCGAQAcAAQJJSEeBwCGAQAuAAQKfyAAAxwACQnKIZwDABYDABwACQnKIZwDABYDAB0AAwnMEtVhALkAAAAA.',
Ha='Haldire:BAAALgAECgIJBwAAAA==.Harrypotture:BAAALgADCgEJAQAAAA==.Haschel:BAABLgAECn8wAAMWAAkJriCsAwDZAgAWAAkJriCsAwDZAgAeAAMJ9Q6JOACFAAAAAA==.',
He='Hexerfender:BAAALgAECgUJBQAAAA==.Heypal:BAAALgADCgUJCwAAAA==.',
Ho='Hofarmer:BAABLgAECn8YAAIfAAkJUhOEEgClAQAfAAkJUhOEEgClAQAAAA==.Holychris:BAAALgADCgEJAQAAAA==.Holycöw:BAAALgADCgkJCQAAAA==.Holywood:BAAALgAECgYJBwAAAA==.',
Hu='Hurtak:BAAALgAECgcJCwAAAA==.',
Hy='Hycisan:BAABLgAECn8qAAISAAkJGBx+CQDgAgASAAkJGBx+CQDgAgAAAA==.',
Ic='Icanlust:BAAALgADCgIJAgAAAA==.Icant:BAAALgADCgEJAgABLgADCgQJBQABAAAAAA==.Icon:BAAALgAECgQJBQAAAA==.Icydoodad:BAAALgADCgQJBAABLgADCgUJBQABAAAAAA==.',
Ig='Ignis:BAAALgADCgMJAwAAAA==.',
Io='Iocomotive:BAAALgAFFAEJAQAAAA==.',
Is='Iskaru:BAAALgAECgEJAQABLgAECgYJDwABAAAAAA==.',
Ja='Jacklawin:BAAALgAECgMJAwAAAA==.Jasmyn:BAAALgADCgQJBAAAAA==.',
Jb='Jbirdlol:BAAALgADCgUJBAAAAA==.',
Je='Jesse:BAAALgAECgYJEAABLgAFFAIJBwASAHYXAA==.Jetmage:BAABLgAECn8gAAIgAAkJRyToAADgAgAgAAkJRyToAADgAgAAAA==.',
Ji='Jire:BAAALgAECgUJDQAAAA==.Jittkal:BAAALgADCgMJAwAAAA==.',
Jo='Josh:BAAALgADCgMJAgAAAA==.',
Jp='Jpally:BAABLgAECn8XAAMSAAcJ2AbwRQAQAQASAAcJ2AbwRQAQAQAKAAUJSwRA7AC3AAAAAA==.',
Ju='Jurassthicc:BAAALgAECgEJAwAAAA==.',
Jw='Jwøww:BAAALgADCgEJAgABLgADCgQJBQABAAAAAA==.',
Ka='Kafka:BAAALgADCgcJBgAAAA==.Kanastra:BAABLgAECn8cAAIGAAgJth00JAApAgAGAAgJth00JAApAgABLgAFFAQJEAAIAAkZAA==.Karraa:BAABLgAECn8jAAIeAAgJpxgUEADPAQAeAAgJpxgUEADPAQAAAA==.Katil:BAAALgAECgEJAQAAAA==.Kaylib:BAABLgAECn8oAAIgAAgJOQ7OBAByAQAgAAgJOQ7OBAByAQAAAA==.',
Ke='Kea:BAAALgADCgIJAgABLgAECgUJCQABAAAAAA==.Kerze:BAABLgAECn8UAAIeAAYJlhEzJQDuAAAeAAYJlhEzJQDuAAAAAA==.Kesatrix:BAABLgAECn8pAAIdAAkJphJAHwD4AQAdAAkJphJAHwD4AQAAAA==.Kesi:BAAALgADCgQJBAAAAA==.',
Kh='Khai:BAAALgAECgQJBAAAAA==.Khazador:BAAALgADCgkJEgABLgAECggJGAAEAHwXAA==.Khaztharion:BAAALgADCggJCAABLgAECggJGAAEAHwXAA==.Khendrick:BAABLgAECn8ZAAIKAAgJRw+zcAByAQAKAAgJRw+zcAByAQAAAA==.',
Ki='Kimsmage:BAAALgADCgYJBgAAAA==.Kith:BAAALgAECgEJAgAAAA==.Kitridge:BAAALgAECgcJDQAAAA==.Kittykatt:BAABLgAECn8zAAINAAkJxRt7DQBsAgANAAkJxRt7DQBsAgAAAA==.',
Ko='Kolchak:BAAALgADCgYJDQAAAA==.Korel:BAAALgAECgYJCwAAAA==.',
Kr='Kraggo:BAAALgAECgYJCQAAAA==.Krimzin:BAACLgAFFH8YAAIKAAUJzSE4GQB8AQAKAAUJzSE4GQB8AQAuAAQKfxwAAwoACQlnIc4XANoCAAoACAkOIc4XANoCABIABQlTD4VZALYAAAAA.',
Ku='Kumala:BAAALgAECgMJBQAAAA==.Kungao:BAAALgAECgUJBQAAAA==.',
Ky='Kylea:BAAALgAECgQJBAAAAA==.',
La='Laffiel:BAAALgADCgQJBAAAAA==.Landoh:BAABLgAECn8jAAIRAAgJYCK1JgBqAgARAAgJYCK1JgBqAgAAAA==.Larsen:BAABLgAECn8jAAIPAAgJch6yGgD0AQAPAAgJch6yGgD0AQAAAA==.',
Le='Leap:BAABLgAECn8dAAMUAAcJghtxCwDiAQAUAAcJIxtxCwDiAQAfAAUJ5BJcLADXAAAAAA==.Lefthorn:BAAALgADCgIJAgAAAA==.Lenneth:BAAALgAECgIJAgAAAA==.',
Li='Lightofdawn:BAAALgAECgMJAwAAAA==.Lightstyle:BAAALgADCgMJAwAAAA==.Lilow:BAABLgAECn85AAIQAAkJIhIUGwDQAQAQAAkJIhIUGwDQAQAAAA==.',
Ll='Llarker:BAABLgAECn8nAAQKAAcJdghxsgD/AAAKAAcJdghxsgD/AAAbAAYJSwGsOgBbAAASAAIJvQGXgwAvAAAAAA==.',
Lo='Lockendron:BAAALgADCgQJBAAAAA==.Locketharion:BAAALgADCgQJBAAAAA==.Lockpebbles:BAAALgADCgMJAwAAAA==.Lokomachina:BAABLgAECn8UAAIZAAcJLyETHwBLAgAZAAcJLyETHwBLAgAAAA==.Lonesdove:BAAALgADCgEJAQAAAA==.',
Lu='Lucyna:BAAALgAECgMJAwABLgAECgkJIQAhAM4iAA==.Luminia:BAAALgAECgUJBQAAAA==.Lunacy:BAAALgAECgEJAQAAAA==.',
Ly='Lynngosa:BAABLgAECn8VAAMiAAcJLw7FFQBfAQAiAAcJLw7FFQBfAQAIAAcJHAh4SgDdAAAAAA==.Lyrana:BAAALgADCgQJBAAAAA==.Lyrasa:BAAALgADCgQJBAAAAA==.',
Ma='Maelidrael:BAAALgAECgIJAgABLgAECgkJMwARANscAA==.Magiks:BAAALgAECgUJBQAAAA==.Magisterium:BAABLgAECn8iAAMMAAgJKgRRPgDhAAAMAAcJXgRRPgDhAAAQAAEJ/QF9iAAYAAAAAA==.Malady:BAABLgAECn8sAAIQAAkJwCCtBwC8AgAQAAkJwCCtBwC8AgAAAA==.Malakyde:BAAALgADCgMJAwAAAA==.Malt:BAABLgAECn8ZAAIGAAgJvCCoNADdAQAGAAgJvCCoNADdAQAAAA==.Malthorial:BAAALgADCgEJAQAAAA==.Mario:BAAALgAFFAEJBAAAAA==.Mattenom:BAAALgADCgYJCAAAAA==.Maulware:BAAALgADCgEJAQAAAA==.',
Mb='Mbrodh:BAAALgAECgQJBAAAAA==.Mbrosmites:BAAALgAECgcJCwAAAA==.',
Md='Mdeag:BAAALgAECgUJDwAAAA==.',
Me='Mefistofeles:BAACLgAFFH8KAAIDAAMJLBJdIQDvAAADAAMJLBJdIQDvAAAuAAQKfyMAAgMACAlmGH0UAOUBAAMACAlmGH0UAOUBAAAA.Meingaree:BAABLgAECn8XAAIFAAgJ1RTvBgDOAQAFAAgJ1RTvBgDOAQAAAA==.Merlinus:BAABLgAECn8lAAIKAAcJ4gq0lABTAQAKAAcJ4gq0lABTAQAAAA==.Merton:BAAALgADCggJDAAAAA==.',
Mi='Mightyguzz:BAABLgAECn8+AAIeAAkJmhM+DwDcAQAeAAkJmhM+DwDcAQAAAA==.Miku:BAAALgAECgMJBAAAAA==.Mitchelle:BAAALgAECgMJBQAAAA==.',
Mo='Moirayne:BAAALgAECgYJBQAAAA==.Moomkin:BAABLgAECn8oAAINAAgJgwznMQA5AQANAAgJgwznMQA5AQAAAA==.',
My='Mythicblade:BAAALgADCgEJAQAAAA==.',
['Mø']='Møønchild:BAAALgAECgMJAwAAAA==.',
Na='Nai:BAAALgAECgQJDAAAAA==.Nanaish:BAAALgAECgEJAQAAAA==.Narpul:BAABLgAECn8rAAIbAAkJBB7+AwCvAgAbAAkJBB7+AwCvAgAAAA==.Natë:BAACLgAFFH8QAAIeAAMJOhh/GAC8AAAeAAMJOhh/GAC8AAAuAAQKfzAAAh4ACQkvIWUDACMDAB4ACQkvIWUDACMDAAAA.Nazend:BAAALgADCgQJBwAAAA==.',
Ne='Necrotalon:BAAALgAECgcJDgAAAA==.Nelosi:BAAALgAECgMJCAAAAA==.Neondh:BAACLgAFFH8SAAIGAAQJDCTNGgCgAQAGAAQJDCTNGgCgAQAuAAQKfzQAAgYACQmIJA4NABcDAAYACQmIJA4NABcDAAAA.Nerzhùl:BAABLgAECn8lAAIPAAkJGgmjNABNAQAPAAkJGgmjNABNAQAAAA==.',
Nh='Nharuna:BAABLgAECn8vAAIZAAgJpxRsQgDDAQAZAAgJpxRsQgDDAQAAAA==.',
Ni='Nickolaos:BAAALgAECgEJAQAAAA==.Nieloriel:BAABLgAECn85AAMSAAkJkBI6JwC6AQASAAkJkBI6JwC6AQAKAAgJmgqRiQBCAQAAAA==.Nightwishing:BAAALgAECgQJBAAAAA==.Niupiadps:BAAALgAECgIJAgAAAA==.Niykee:BAABLgAECn8hAAQhAAkJziIzAwBeAgAhAAYJUSQzAwBeAgADAAcJPiKmHAAaAgAjAAcJCx5mBgARAgAAAA==.',
No='Noboundss:BAABLgAECn8UAAMGAAgJ0AqGgAACAQAGAAcJZwuGgAACAQALAAMJPwiOUQBRAAAAAA==.Nobóunds:BAAALgAECgkJEAAAAA==.Nomnoms:BAAALgAECgYJEQAAAA==.Nomoreheals:BAAALgAECgYJDQAAAA==.Notkarl:BAAALgAECgIJAwAAAA==.Nowimpissed:BAACLgAFFH8PAAMCAAMJ9SGJEwAkAQACAAMJ9SGJEwAkAQAZAAEJvyDWHgBkAAAuAAQKfxcABAIABgnEHmkRABMCAAIABgnEHmkRABMCABkABAkPFsp5APoAABgABAnmDzBbANcAAAAA.Noztra:BAACLgAFFH8KAAIRAAMJIgmRdwDTAAARAAMJIgmRdwDTAAAuAAQKfysAAhEACAlZF+5EAPUBABEACAlZF+5EAPUBAAAA.',
Nu='Nuker:BAAALgAECgEJAQAAAA==.',
Ny='Nysrogh:BAAALgAECgUJEgABLgAFFAQJEwAOABYWAA==.',
Ob='Obsideon:BAAALgAECggJEwAAAA==.',
Oh='Ohgr:BAAALgAECgYJDgAAAA==.Ohshifty:BAABLgAECn80AAMNAAkJ0xChIACpAQANAAkJ0xChIACpAQAOAAQJbATimABtAAAAAA==.',
Ol='Olan:BAAALgAECgYJCAAAAA==.Olie:BAABLgAECn8bAAIZAAgJ9wkmZwBdAQAZAAgJ9wkmZwBdAQAAAA==.',
Or='Orbsicles:BAABLgAECn8YAAIkAAkJQR99BQA2AgAkAAkJQR99BQA2AgAAAA==.',
Ou='Ouragan:BAAALgAECgUJCAAAAA==.',
Pa='Paedrig:BAAALgADCgIJAgAAAA==.Papitomyrey:BAABLgAECn8gAAMVAAkJKCSHBQD3AgAVAAkJKCSHBQD3AgAWAAUJYh1UMQDnAAABLgAECgkJJQAcAG4fAA==.Paramedic:BAAALgADCgIJAgAAAA==.Passtheflask:BAABLgAECn8eAAIEAAcJGgfnnwD1AAAEAAcJGgfnnwD1AAAAAA==.',
Pe='Perdition:BAAALgAECgEJAQAAAA==.Pestílence:BAACLgAFFH8JAAIHAAMJHBj+nwCsAAAHAAMJHBj+nwCsAAAuAAQKfz8AAwcACQk1IqoUALkCAAcACQk1IqoUALkCABMAAQnEEZBHACoAAAAA.',
Ph='Phaesphoros:BAABLgAECn8gAAIJAAkJXxDnQwCCAQAJAAkJXxDnQwCCAQAAAA==.Phenor:BAAALgAECgQJBAAAAA==.',
Po='Poe:BAAALgADCgYJBgABLgAECgcJFQARAOEXAA==.Powpow:BAABLgAECn8kAAIDAAkJWBeECwBVAgADAAkJWBeECwBVAgAAAA==.',
Pr='Prejudice:BAABLgAECn8cAAISAAgJ/RSVIgDaAQASAAgJ/RSVIgDaAQAAAA==.Primévil:BAAALgAECgYJBgABLgAECggJJwAPADAYAA==.Priscilla:BAAALgAECgEJAgAAAA==.Prowlcow:BAABLgAECn8yAAMOAAkJdRf+GQBjAgAOAAkJdRf+GQBjAgAUAAIJDxY6LgCEAAAAAA==.',
Ps='Psychosis:BAABLgAECn8uAAIHAAkJ5B0cIgBqAgAHAAkJ5B0cIgBqAgAAAA==.',
Pu='Putrescence:BAAALgADCgEJAQAAAA==.',
['Pû']='Pûff:BAAALgAECgcJDwAAAA==.',
Qm='Qmpel:BAAALgADCgMJAwAAAA==.',
Ra='Raiiz:BAACLgAFFH8IAAIRAAMJBBBmLAAFAQARAAMJBBBmLAAFAQAuAAQKfyYAAhEACAkhHI4/AHoCABEACAkhHI4/AHoCAAAA.Rainhoof:BAABLgAECn8jAAMUAAgJOhkgCgD+AQAUAAgJOhkgCgD+AQAOAAUJYAiAhwDHAAAAAA==.Ralneth:BAACLgAFFH8YAAMIAAgJphCUCgAOAgAIAAcJgRCUCgAOAgAaAAQJXRToAwAOAQAuAAQKfyQAAxoACAmrIFADAOsCABoACAmfH1ADAOsCAAgABgnYG0IYAA8CAAAA.Ranare:BAAALgAECgYJBgAAAA==.Randomtask:BAAALgADCgUJBgAAAA==.Rapala:BAABLgAECn8mAAIEAAkJ+hxPGACGAgAEAAkJ+hxPGACGAgAAAA==.Rapalaa:BAAALgAECgcJDwABLgAECgkJJgAEAPocAA==.Raspútin:BAABLgAECn8yAAMlAAkJuRhdDgBBAgAlAAkJuRhdDgBBAgAcAAQJ8AfVVQC5AAAAAA==.Rawkfice:BAAALgADCggJFAAAAA==.',
Re='Redlefevoker:BAAALgADCgYJCQAAAA==.Renfield:BAAALgADCgYJBwAAAA==.Revok:BAAALgAECgcJCwAAAA==.Revoker:BAAALgADCgYJCAAAAA==.',
Ri='Riordan:BAAALgAFFAEJAgAAAA==.Rivvetear:BAAALgADCgYJBgAAAA==.',
Rj='Rjolz:BAACLgAFFH8OAAIHAAQJZiAnJACbAQAHAAQJZiAnJACbAQAuAAQKfzcAAgcACQn7JcoCAGsDAAcACQn7JcoCAGsDAAAA.',
Ro='Roflchopr:BAAALgAECgcJDAAAAA==.Roguish:BAAALgAECgEJAQAAAA==.Rootzi:BAAALgAECgIJAwABLgAECgkJIgAHABcdAA==.Rootzidk:BAABLgAECn8iAAIHAAgJFx0NRwDbAQAHAAgJFx0NRwDbAQAAAA==.',
Ru='Rucks:BAABLgAECn8iAAMcAAgJORp2IQCNAQAcAAgJbBF2IQCNAQAlAAYJzBoYMAAxAQAAAA==.',
Sa='Saelem:BAAALgAECgYJBgAAAA==.Sandalfon:BAAALgAECgYJDgAAAA==.Sanleron:BAAALgAFFAEJAQAAAA==.Sarith:BAAALgAECgQJAQAAAA==.Saske:BAAALgADCgMJBwABLgAECgEJAQABAAAAAA==.',
Sc='Scargon:BAAALgAECgQJDAAAAA==.',
Se='Selidori:BAAALgADCgYJBgAAAA==.Seralicht:BAACLgAFFH8RAAIMAAYJLxX/BgCzAQAMAAYJLxX/BgCzAQAuAAQKfx0AAwwACAlAHhwQAGUCAAwACAlAHhwQAGUCABAAAQmKCwl4ADIAAAAA.',
Sh='Shaliri:BAAALgADCgEJBAAAAA==.Shamanata:BAAALgAECgEJAQAAAA==.Sharayse:BAABLgAECn8hAAIRAAkJWgxQZwCVAQARAAkJWgxQZwCVAQAAAA==.Sharmee:BAAALgAECgkJEQAAAA==.Shishy:BAAALgAECgMJAwAAAA==.Shockohôlic:BAABLgAECn8nAAQPAAgJMBi2HgDTAQAPAAgJMBi2HgDTAQAJAAYJTxCeSwBUAQAmAAEJoAphKwA4AAAAAA==.Shocky:BAAALgAECgcJCgAAAA==.',
Sk='Skullkìng:BAABLgAECn8jAAIHAAkJuhSGQgDoAQAHAAkJuhSGQgDoAQAAAA==.',
Sl='Slingablade:BAACLgAFFH8LAAIGAAQJHQZpTgDfAAAGAAQJHQZpTgDfAAAuAAQKfyEAAwYACQn2FFYvAPMBAAYACQn9E1YvAPMBAAsAAwlNEUA6AK0AAAAA.',
Sm='Smashnskullz:BAAALgAECgQJBgABLgAECgUJBQABAAAAAA==.',
Sn='Sniffsniff:BAACLgAFFH8JAAIKAAMJxyURNwAmAQAKAAMJxyURNwAmAQAuAAQKfykAAwoACAlHJQYKAEEDAAoACAlHJQYKAEEDABIAAQnBHsx1AE4AAAEuAAUUBAkNAAkAsSYA.',
So='Solvi:BAABLgAECn8fAAIOAAcJ9xcHUQA4AQAOAAcJ9xcHUQA4AQAAAA==.Sonira:BAAALgADCgMJBQAAAA==.Soulbrand:BAABLgAECn8jAAIQAAgJiQmUMgAuAQAQAAgJiQmUMgAuAQAAAA==.Southpawclaw:BAAALgAECgEJAQABLgAECggJFwAmAPAfAA==.',
Sp='Spellz:BAABLgAECn8kAAIQAAgJIB/SCwB5AgAQAAgJIB/SCwB5AgAAAA==.Spoo:BAAALgADCgYJCQAAAA==.Spuggle:BAAALgAECgQJBAAAAA==.',
St='Stabathuh:BAAALgADCgYJBgAAAA==.Starman:BAAALgAECgkJCQAAAA==.Stoopidrood:BAAALgADCgQJBAABLgADCgUJBQABAAAAAA==.Stoopidtroll:BAAALgADCgUJBQAAAA==.Stormclaw:BAABLgAECn8bAAIkAAgJ/wt/DwA5AQAkAAgJ/wt/DwA5AQAAAA==.Straeka:BAAALgAECgIJAgAAAA==.Stëvë:BAAALgAECgIJBAABLgAECgYJDwABAAAAAA==.',
Su='Sufiya:BAABLgAECn8gAAIZAAkJLw8bRwC0AQAZAAkJLw8bRwC0AQAAAA==.Suhwoo:BAAALgAECgcJDwAAAA==.Sumig:BAAALgADCgEJBAAAAA==.',
Sw='Swiftarrows:BAAALgAECgEJAgAAAA==.',
Sy='Sylvershadow:BAABLgAECn8eAAIZAAgJfhAeTwCcAQAZAAgJfhAeTwCcAQAAAA==.Sym:BAAALgADCgcJCQAAAA==.',
Ta='Taintedsoulv:BAAALgADCgUJBgAAAA==.Taliri:BAAALgADCgEJAQABLgADCgQJBQABAAAAAA==.Tandarilada:BAAALgAFFAEJBAAAAA==.Tanknspankn:BAAALgAECgkJDAAAAA==.Tankurface:BAAALgAECgEJAgAAAA==.',
Th='Thalvint:BAACLgAFFH8MAAIWAAQJSRuDDQBKAQAWAAQJSRuDDQBKAQAuAAQKfzMAAxYACQmHI1UCABIDABYACQmHI1UCABIDABUABgnVEiJbAEIBAAAA.Theblackhand:BAABLgAECn8dAAMPAAYJ1RXTSgAcAQAPAAUJaxPTSgAcAQAJAAYJrQ8JawD7AAAAAA==.Thefira:BAAALgADCgkJCQAAAA==.Thickdk:BAABLgAECn8aAAIHAAgJHRZTbgCtAQAHAAgJHRZTbgCtAQAAAA==.Thoriel:BAAALgAECgEJAgAAAA==.',
Ti='Timefall:BAAALgAECgkJDgAAAA==.Titanic:BAAALgAECgcJEAAAAA==.',
To='Tomcruise:BAAALgAECgkJDwAAAA==.Toshiro:BAAALgADCgcJBwAAAA==.Totemlyawsum:BAABLgAFFH8LAAIPAAQJDg3fIAAAAQAPAAQJDg3fIAAAAQAAAA==.Touch:BAAALgAECgEJAQAAAA==.Touchymcfeel:BAAALgADCgMJAwAAAA==.',
Tr='Trckr:BAAALgADCgIJAgAAAA==.Treeiage:BAAALgAECgUJCAAAAA==.Trooblu:BAAALgAECgYJEgAAAA==.',
Tw='Twotone:BAAALgAECgEJAQAAAA==.',
['Té']='Téz:BAAALgAECgYJEwAAAA==.',
['Tê']='Têzeret:BAAALgAECgEJAgAAAA==.',
Ul='Ulkthar:BAABLgAECn8wAAIVAAgJ2BPKKAAZAgAVAAgJ2BPKKAAZAgAAAA==.Ultrauchuva:BAAALgADCgEJAQAAAA==.',
Un='Unholyhammer:BAAALgADCgIJAgABLgAECgUJBQABAAAAAA==.',
Va='Vacunamatata:BAAALgAECgEJAQAAAA==.Vanarn:BAAALgADCgEJAQABLgADCgQJBQABAAAAAA==.Vanlin:BAABLgAECn8jAAIOAAgJUB5oFgCBAgAOAAgJUB5oFgCBAgAAAA==.',
Ve='Vexxdr:BAACLgAFFH8FAAIOAAMJZgmSPgCoAAAOAAMJZgmSPgCoAAAuAAQKfx8AAg4ACAkcEtc5AL4BAA4ACAkcEtc5AL4BAAAA.Vexxs:BAABLgAECn8aAAIJAAkJlxRQIQAtAgAJAAkJlxRQIQAtAgABLgAFFAMJBQAOAGYJAA==.',
Vi='Virtey:BAAALgADCgUJBQAAAA==.Virtuous:BAAALgADCgYJBwAAAA==.',
Vl='Vladzy:BAAALgADCgcJAwAAAA==.',
Vo='Voidsuzu:BAAALgAECgMJAwABLgAECgkJNwAbALkUAA==.Vormedicus:BAAALgAECgIJAwABLgAECgkJMgAlALkYAA==.',
Vu='Vulperas:BAABLgAECn8uAAIPAAkJfQ70LAB3AQAPAAkJfQ70LAB3AQAAAA==.',
Vy='Vynastallan:BAABLgAECn8cAAMZAAcJhSOMIABCAgAZAAcJhSOMIABCAgAYAAEJehfShgA1AAAAAA==.Vyper:BAEBLgAECn8lAAIIAAgJcxn3GwDdAQAIAAgJcxn3GwDdAQABLgAFFAQJCwAUADkXAA==.',
Wa='Waroo:BAABLgAECn8iAAINAAgJORIJIQCmAQANAAgJORIJIQCmAQAAAA==.',
We='Wellcole:BAAALgADCgYJBgAAAA==.Wenden:BAAALgAFFAEJAwAAAA==.Wengo:BAAALgADCgkJCgAAAA==.',
Wi='Wilbert:BAAALgADCgEJAQAAAA==.Winniethepo:BAAALgAECgQJBAAAAA==.Witherflow:BAAALgAECgIJAwAAAA==.',
Wo='Woodey:BAAALgADCgcJCAAAAA==.',
Wu='Wulffric:BAABLgAECn8VAAICAAYJdhQUKgBAAQACAAYJdhQUKgBAAQAAAA==.',
Xe='Xeo:BAAALgADCgMJAwAAAA==.',
Ya='Yachirú:BAABLgAECn83AAIbAAkJuRSNDADhAQAbAAkJuRSNDADhAQAAAA==.Yahkisoba:BAAALgAECgEJAQAAAA==.',
Ye='Yessir:BAAALgAECgEJAQABLgAECgkJGgAcAA4XAA==.',
Yi='Yiang:BAABLgAECn8nAAIcAAkJ0R07CACvAgAcAAkJ0R07CACvAgAAAA==.',
Yl='Ylndrysa:BAABLgAECn9DAAMOAAkJoBnaFgB9AgAOAAkJoBnaFgB9AgANAAMJoRgTSgDHAAAAAA==.',
Yt='Ytho:BAAALgADCgYJBgAAAA==.',
Za='Zalithar:BAABLgAECn8VAAIGAAgJZgWKjgDkAAAGAAgJZgWKjgDkAAAAAA==.',
Ze='Zedrock:BAABLgAECn8zAAIRAAkJ2xx3HwCMAgARAAkJ2xx3HwCMAgAAAA==.Zekodian:BAAALgADCgcJDQAAAA==.Zentner:BAABLgAECn8uAAMNAAkJXx/ACQCjAgANAAkJXx/ACQCjAgAfAAQJPAodJAB8AAAAAA==.Zeropistol:BAABLgAECn8aAAIRAAgJNQNywwDmAAARAAgJNQNywwDmAAAAAA==.Zexrous:BAAALgADCgEJAQAAAA==.',
Zh='Zhas:BAAALgAECgcJEwAAAA==.',
Zu='Zuro:BAABLgAECn8bAAMZAAgJ9Q1GXwBwAQAZAAgJ9Q1GXwBwAQAYAAEJCgHPmQAaAAAAAA==.',
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
