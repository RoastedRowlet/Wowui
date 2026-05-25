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

local lookup = {'Unknown-Unknown','Hunter-Survival','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Augmentation','Paladin-Retribution','DemonHunter-Havoc','Druid-Balance','Druid-Restoration','Shaman-Elemental','Priest-Shadow','Mage-Frost','Shaman-Restoration','DeathKnight-Blood','Druid-Feral','Priest-Holy','Warrior-Fury','Warrior-Arms','Priest-Discipline','Rogue-Subtlety','Hunter-Marksmanship','Hunter-BeastMastery','Evoker-Devastation','Paladin-Protection','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','Druid-Guardian','Paladin-Holy','Mage-Fire','Rogue-Outlaw','Rogue-Assassination','Monk-Brewmaster','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Ablestract:BAAALgADCggJCQAAAA==.',
Ac='Acid:BAAALgAECggJDgAAAA==.',
Ad='Adam:BAAALgAFFAEJAgABLgAFFAEJAwABAAAAAA==.Adreane:BAAALgAECgMJBAAAAA==.',
Af='Aftrlyfe:BAAALgAECgkJCQAAAA==.',
Ai='Aiyana:BAAALgADCgkJEQAAAA==.',
Ak='Akamma:BAAALgAECgcJDgAAAA==.Akarimos:BAAALgADCgMJAwAAAA==.',
Al='Alealle:BAAALgADCgMJAwAAAA==.Algeriono:BAAALgAECgMJAwAAAA==.Aliluna:BAAALgAECgYJCgAAAA==.Alirain:BAAALgAECgUJBwAAAA==.Alispere:BAAALgADCgUJBQAAAA==.Aliwings:BAAALgAECgEJAgAAAA==.Alizaranna:BAAALgADCgEJAQABLgAECgYJEAABAAAAAA==.',
Am='Amarokk:BAABLgAECn8WAAICAAYJ7QeVMQD5AAACAAYJ7QeVMQD5AAAAAA==.Ameliae:BAAALgAECgEJAQAAAA==.',
An='Ancestor:BAAALgAECgYJEwAAAA==.Anish:BAAALgAECgEJAQAAAA==.',
Aq='Aqurore:BAAALgADCgYJBgAAAA==.',
Ar='Archaia:BAAALgAECgQJBQAAAA==.Argorok:BAAALgAFFAEJAQAAAA==.Aryi:BAAALgAECggJDQAAAA==.',
As='Askim:BAAALgADCgcJBwAAAA==.Assyla:BAAALgAECgEJAQAAAA==.Astraeos:BAAALgAFFAMJAwAAAA==.',
Au='Auv:BAACLgAFFH8QAAMDAAQJESaEBwCtAQADAAQJESaEBwCtAQAEAAEJlQBjGwA6AAAuAAQKfxQAAwQABwmJJkMTALEBAAMABQkZJl9MAOMBAAQABAkgJkMTALEBAAEuAAUUBQkNAAUADCQA.',
Aw='Awekeha:BAAALgADCgIJAgAAAA==.',
Ax='Axël:BAAALgAFFAEJAQABLgAFFAMJBgAGAKsaAA==.',
Ay='Aylranoa:BAAALgADCgkJCQAAAA==.',
Az='Azimondius:BAACLgAFFH8MAAIHAAQJuRVTHAAuAQAHAAQJuRVTHAAuAQAuAAQKfywAAgcACQnnH20KAJUCAAcACQnnH20KAJUCAAAA.Azmora:BAAALgAECgcJDgAAAA==.Azzix:BAAALgADCgQJBQAAAA==.',
Ba='Baddragons:BAAALgADCgYJBgAAAA==.Bandit:BAAALgAECgEJAQAAAA==.Bastis:BAAALgAECgEJBAABLgAFFAMJCQAIAMclAA==.Batreaux:BAAALgAFFAEJAgAAAA==.',
Be='Beaman:BAAALgADCgEJAQAAAA==.Bearkake:BAAALgAECgMJBgAAAA==.Bellgrande:BAAALgADCgYJBgAAAA==.Belthora:BAAALgAECgYJCAAAAA==.Bepallylol:BAACLgAFFH8HAAIIAAUJcwzuHwBVAQAIAAUJcwzuHwBVAQAuAAQKfxgAAggACAliHbEtAGwCAAgACAliHbEtAGwCAAAA.',
Bi='Bigkeith:BAAALgADCgEJAQAAAA==.Biraj:BAAALgADCggJEAABLgAECgcJIAAIANsHAA==.',
Bl='Blaqichan:BAAALgADCgEJAwABLgADCgQJBQABAAAAAA==.Blight:BAAALgADCgcJBQAAAA==.Bloodybecky:BAAALgAECgQJBQAAAA==.',
Br='Brakiyamis:BAAALgAECgEJAQAAAA==.Brewmastah:BAAALgAECgYJCgABLgAECgUJBwABAAAAAA==.Browntotem:BAAALgADCgUJCAAAAA==.',
Bu='Bubblecheeks:BAAALgAECgQJBQAAAA==.Bubblehëarth:BAAALgAECgYJCgAAAA==.Bubby:BAABLgAECn8WAAIDAAcJPx2OQQAIAgADAAcJPx2OQQAIAgAAAA==.Bucklebunnie:BAAALgADCgEJAQABLgAFFAUJCQAJANkIAA==.Burbuja:BAAALgAECgYJEwAAAA==.',
Ca='Cadfile:BAAALgAECgQJBgAAAA==.Careco:BAAALgADCgYJBgAAAA==.Carpetcrumbs:BAAALgAECgUJBQAAAA==.Catnsevrmeme:BAAALgAECgEJAgAAAA==.',
Ce='Cecilio:BAAALgAECgMJAwAAAA==.Cel:BAAALgAECgEJAgAAAA==.Celzara:BAAALgAECgEJAQAAAA==.Cetraa:BAABLgAECn8cAAMKAAgJNBjLFgDuAQAKAAgJNBjLFgDuAQALAAEJEw7rwQAsAAAAAA==.',
Ch='Chastise:BAAALgAECgkJDQAAAA==.Chewÿ:BAAALgAECgcJAwAAAA==.Chii:BAAALgADCgEJAQAAAA==.Chocobro:BAAALgAECgYJCQAAAA==.Chäös:BAAALgAECgUJBQAAAA==.',
Cl='Clingy:BAAALgAECgEJAQAAAA==.',
Co='Cobble:BAABLgAECn8WAAIMAAgJKhFdKgByAQAMAAgJKhFdKgByAQAAAA==.Colhap:BAABLgAECn8ZAAINAAcJJhzLIQDJAQANAAcJJhzLIQDJAQAAAA==.Conjure:BAABLgAECn8vAAMEAAgJpBVgBwCwAQAEAAcJyRdgBwCwAQADAAgJmQ30bgBGAQAAAA==.Corbina:BAABLgAECn8jAAIOAAgJ6iJ2NQCeAgAOAAgJ6iJ2NQCeAgAAAA==.Cousinlarry:BAAALgADCgIJAgABLgADCgQJBQABAAAAAA==.',
Cr='Cramlutin:BAAALgADCgUJBQAAAA==.Cru:BAAALgAECgkJDgAAAA==.Crui:BAAALgADCgcJBwAAAA==.',
Cu='Culligan:BAABLgAECn9nAAIOAAkJgxkxJwBiAgAOAAkJgxkxJwBiAgAAAA==.Cuttingcrew:BAAALgADCggJCAAAAA==.',
Cy='Cygwin:BAABLgAECn8uAAIPAAgJ5RefHAA5AgAPAAgJ5RefHAA5AgAAAA==.',
Da='Darcfrost:BAAALgAECgEJAQAAAA==.Darcyonys:BAAALgAECgIJBQAAAA==.Dariao:BAAALgAECgIJAgABLgAECgkJLQAFAM8ZAA==.Darklon:BAAALgAECgkJEwAAAA==.Darkpun:BAAALgADCgcJCQAAAA==.Darîus:BAAALgAECgMJAwAAAA==.Dat:BAAALgAECgcJAQABLgAFFAIJBwAOAPkYAA==.Datmage:BAACLgAFFH8HAAIOAAIJ+RhRewCoAAAOAAIJ+RhRewCoAAAuAAQKfxkAAg4ABwl4H3FeAB8CAA4ABwl4H3FeAB8CAAAA.',
De='Deathshockz:BAAALgAECgQJBQABLgAECgUJBQABAAAAAA==.Demunzz:BAAALgADCgUJCQAAAA==.Deriah:BAABLgAECn8pAAIIAAgJoBQ3UADxAQAIAAgJoBQ3UADxAQAAAA==.Derpatron:BAAALgAECggJEQAAAA==.Destruction:BAABLgAECn8WAAIQAAgJuQU8KwDOAAAQAAgJuQU8KwDOAAAAAA==.Devo:BAEBLgAFFH8HAAIRAAMJmhEeCQDuAAARAAMJmhEeCQDuAAAAAA==.',
Di='Dingers:BAAALgAECggJCAABLgAECgkJDwABAAAAAA==.Disgusti:BAAALgAECggJEwAAAA==.Divinespark:BAABLgAECn8jAAISAAgJMRXULACTAQASAAgJMRXULACTAQAAAA==.',
Dk='Dkins:BAAALgAECgIJAgAAAA==.',
Do='Dogeform:BAAALgADCgEJAQAAAA==.Doinkbigs:BAABLgAECn8iAAIDAAgJXQ36WwB1AQADAAgJXQ36WwB1AQAAAA==.Doomo:BAAALgADCgYJBgABLgABCgQJBAABAAAAAA==.Dotsfired:BAAALgADCgQJBAAAAA==.Dotñtrot:BAAALgAFFAIJAgABLgAFFAMJCwAPADUZAA==.',
Dr='Draeneisham:BAAALgAFFAEJAQAAAA==.Dredd:BAAALgAECgQJCQAAAA==.Drewsilla:BAAALgAECgYJDQAAAA==.Druidrose:BAAALgAECgMJAwAAAA==.Druidtrix:BAAALgADCgYJCwAAAA==.Drylogic:BAABLgAECn8tAAILAAkJnB4fCgD7AgALAAkJnB4fCgD7AgAAAA==.',
Du='Duckworth:BAAALgAECgEJAQAAAA==.Duruk:BAAALgAECgcJDAAAAA==.Dustbroom:BAAALgAECgEJAQAAAA==.',
Ea='Eap:BAAALgAECgcJDwAAAA==.Eazye:BAACLgAFFH8NAAINAAMJMQ9TGwDoAAANAAMJMQ9TGwDoAAAuAAQKfzYAAg0ACQlXHMQLAHECAA0ACQlXHMQLAHECAAAA.',
Eb='Ebone:BAAALgADCgMJAQAAAA==.',
Ec='Ectoscourge:BAAALgADCgcJBgAAAA==.',
Ed='Edgeffs:BAABLgAECn8eAAMTAAgJewpXOAA/AQATAAgJHAlXOAA/AQAUAAUJZQj5JADFAAAAAA==.',
Ek='Eklipse:BAAALgADCgMJAwABLgABCgQJBAABAAAAAA==.',
El='Elentiya:BAABLgAECn8hAAMSAAkJvxyYDgB1AgASAAkJvxyYDgB1AgAVAAEJegd7WgAtAAAAAA==.Elphzz:BAABLgAECn8WAAIWAAgJ+BL1HgADAgAWAAgJ+BL1HgADAgAAAA==.',
Em='Emoose:BAAALgAECgEJAQAAAA==.',
Er='Eriius:BAAALgAECgYJEgAAAA==.',
Ev='Evestar:BAAALgADCgEJAQAAAA==.',
Ez='Ez:BAACLgAFFH8UAAMXAAYJWRjXEgDvAAAXAAUJ6hLXEgDvAAAYAAIJuBnEWQCcAAAuAAQKfyoAAxcACAn0H6UYAGcCABcACAn0H6UYAGcCABgAAgmXDZXmAEQAAAAA.Ezarath:BAABLgAECn8iAAIZAAYJDgi1EADcAAAZAAYJDgi1EADcAAAAAA==.',
Fa='Fadedaf:BAABLgAECn8UAAIFAAYJjQ0viwANAQAFAAYJjQ0viwANAQAAAA==.',
Fe='Felenn:BAAALgADCgYJDQABLgAECgcJIAAIANsHAA==.Felorc:BAAALgAECgYJCwAAAA==.Fentun:BAAALgAECgMJAwAAAA==.Feyla:BAAALgAECgUJCQAAAA==.',
Fi='Finnikey:BAAALgAECgIJAgAAAA==.Firstone:BAAALgADCgYJBgAAAA==.',
Fo='Foofs:BAAALgADCgUJBQAAAA==.Foulmuffn:BAAALgADCgYJCQAAAA==.Foulplay:BAAALgADCgMJAwAAAA==.Fovos:BAAALgAECgEJAQAAAA==.',
Fr='Freakonleash:BAABLgAECn8YAAITAAgJ/Rn7GQB8AgATAAgJ/Rn7GQB8AgAAAA==.Frimbooze:BAAALgAECgYJBgAAAA==.',
Fu='Fuegodotz:BAAALgADCgUJBQABLgAECgkJIgAGABcdAA==.Fumonkchu:BAAALgADCgIJAQAAAA==.',
Ga='Ganjåfarian:BAAALgAECgIJAgAAAA==.',
Ge='Gekatta:BAAALgAECgYJEAAAAA==.Gelektrael:BAABLgAECn8jAAMDAAgJjwsuZwBYAQADAAgJ0QouZwBYAQAEAAEJXAz9dQAvAAAAAA==.',
Gh='Ghostdk:BAAALgADCggJCAABLgAFFAUJDAAIAPMdAA==.Ghostwarrior:BAAALgADCgMJAwABLgAFFAUJDAAIAPMdAA==.Ghostzz:BAACLgAFFH8MAAIIAAUJ8x0wFgB6AQAIAAUJ8x0wFgB6AQAuAAQKf0wAAwgACQl7I90IAAoDAAgACQl7I90IAAoDABoABQkSHiMWAEQBAAAA.',
Gl='Glarb:BAAALgAECgEJAgAAAA==.Glzygldiator:BAACLgAFFH8OAAIGAAMJ1BhXLgDhAAAGAAMJ1BhXLgDhAAAuAAQKfykAAgYACAkWH4wwABkCAAYACAkWH4wwABkCAAAA.',
Gn='Gnomelock:BAAALgAFFAEJAQABLgAFFAEJAwABAAAAAA==.',
Go='Gobblin:BAAALgAECgUJDQAAAA==.Gotbandaids:BAAALgAECgEJAQAAAA==.Govegan:BAAALgADCgQJBwAAAA==.',
Gr='Graavey:BAAALgAECgcJAwABLgAFFAMJCwAPADUZAA==.Greyhairs:BAAALgAECgcJEQAAAA==.Grimthor:BAAALgAECgcJBwAAAA==.Grippy:BAACLgAFFH8HAAIFAAMJRwa6VAC6AAAFAAMJRwa6VAC6AAAuAAQKfyYAAgUACAl/HUoiAIQCAAUACAl/HUoiAIQCAAAA.Gromit:BAACLgAFFH8YAAISAAYJXxzCAwDtAQASAAYJXxzCAwDtAQAuAAQKfyQAAxIACQlNIZMDACEDABIACQlNIZMDACEDABUAAgmnEUdKAG0AAAAA.Grym:BAAALgADCgcJDgAAAA==.',
Gu='Gustófwind:BAACLgAFFH8FAAIbAAMJEyGlDgAkAQAbAAMJEyGlDgAkAQAuAAQKfx8AAxsACQnIISYDABgDABsACQnIISYDABgDABwAAwnMEnhWALgAAAAA.',
Ha='Haldire:BAAALgAECgIJBwAAAA==.Harrypotture:BAAALgADCgEJAQAAAA==.Haschel:BAABLgAECn8wAAMUAAkJriAGAwDjAgAUAAkJriAGAwDjAgAdAAMJ9Q6JOACFAAAAAA==.',
He='Hexerfender:BAAALgAECgUJBQAAAA==.Heypal:BAAALgADCgUJCwAAAA==.',
Ho='Hofarmer:BAABLgAECn8YAAIeAAkJUhM2EACoAQAeAAkJUhM2EACoAQAAAA==.Holychris:BAAALgADCgEJAQAAAA==.Holycöw:BAAALgADCgkJCQAAAA==.Holywood:BAAALgAECgYJBwAAAA==.',
Hu='Hurtak:BAAALgAECgcJCwAAAA==.',
Hy='Hycisan:BAABLgAECn8mAAIfAAgJJR0YDQCaAgAfAAgJJR0YDQCaAgAAAA==.',
Ic='Icanlust:BAAALgADCgIJAgAAAA==.Icant:BAAALgADCgEJAgABLgADCgQJBQABAAAAAA==.Icon:BAAALgAECgMJAwAAAA==.Icydoodad:BAAALgADCgQJBAABLgADCgUJBQABAAAAAA==.',
Ig='Ignis:BAAALgADCgMJAwAAAA==.',
Io='Iocomotive:BAAALgAECgYJCgAAAA==.',
Is='Iskaru:BAAALgAECgEJAQABLgAECgYJCgABAAAAAA==.',
Ja='Jacklawin:BAAALgAECgMJAwAAAA==.Jasmyn:BAAALgADCgQJBAAAAA==.',
Jb='Jbirdlol:BAAALgADCgUJBAAAAA==.',
Je='Jesse:BAAALgAECgYJEAABLgAFFAIJBwAfAHYXAA==.Jetmage:BAABLgAECn8gAAIgAAkJRyToAADgAgAgAAkJRyToAADgAgAAAA==.',
Ji='Jire:BAAALgAECgUJDQAAAA==.Jittkal:BAAALgADCgMJAwAAAA==.',
Jo='Josh:BAAALgADCgMJAgAAAA==.',
Jp='Jpally:BAABLgAECn8XAAMfAAcJ2AbxQQARAQAfAAcJ2AbxQQARAQAIAAUJSwRA7AC3AAAAAA==.',
Ju='Jurassthicc:BAAALgAECgEJAwAAAA==.',
Jw='Jwøww:BAAALgADCgEJAgABLgADCgQJBQABAAAAAA==.',
Ka='Kafka:BAAALgADCgcJBgAAAA==.Kanastra:BAABLgAECn8cAAIFAAgJth1NIQAvAgAFAAgJth1NIQAvAgABLgAFFAQJDAAHALkVAA==.Karraa:BAABLgAECn8hAAIdAAgJeBfJDwDDAQAdAAgJeBfJDwDDAQAAAA==.Katil:BAAALgAECgEJAQAAAA==.Kaylib:BAABLgAECn8lAAIgAAgJUw0xBACAAQAgAAgJUw0xBACAAQAAAA==.',
Ke='Kea:BAAALgADCgIJAgABLgAECgUJCQABAAAAAA==.Kerze:BAABLgAECn8UAAIdAAYJlhEEIgD3AAAdAAYJlhEEIgD3AAAAAA==.Kesatrix:BAABLgAECn8mAAIcAAcJ0RMTKQCVAQAcAAcJ0RMTKQCVAQAAAA==.Kesi:BAAALgADCgQJBAAAAA==.',
Kh='Khai:BAAALgAECgQJBAAAAA==.Khazador:BAAALgADCgkJEgABLgAECggJGAADAHwXAA==.Khaztharion:BAAALgADCggJCAABLgAECggJGAADAHwXAA==.Khendrick:BAABLgAECn8ZAAIIAAgJRw/uZACGAQAIAAgJRw/uZACGAQAAAA==.',
Ki='Kimsmage:BAAALgADCgYJBgAAAA==.Kith:BAAALgAECgEJAgAAAA==.Kitridge:BAAALgAECgcJBwAAAA==.Kittykatt:BAABLgAECn8zAAIKAAkJxRsEDABvAgAKAAkJxRsEDABvAgAAAA==.',
Ko='Kolchak:BAAALgADCgYJDQAAAA==.Korel:BAAALgAECgYJCwAAAA==.',
Kr='Kraggo:BAAALgAECgYJCQAAAA==.Krimzin:BAACLgAFFH8UAAIIAAUJhSE1FQB/AQAIAAUJhSE1FQB/AQAuAAQKfxwAAwgACQlnIc4XANoCAAgACAkOIc4XANoCAB8ABQlTD+lUALYAAAAA.',
Ku='Kumala:BAAALgAECgMJBQAAAA==.',
Ky='Kylea:BAAALgAECgQJBAAAAA==.',
La='Laffiel:BAAALgADCgQJBAAAAA==.Landoh:BAABLgAECn8jAAIOAAgJYCLZIgB2AgAOAAgJYCLZIgB2AgAAAA==.Larsen:BAABLgAECn8jAAIMAAgJch4dGAD3AQAMAAgJch4dGAD3AQAAAA==.',
Le='Leap:BAABLgAECn8YAAMRAAcJrxgfDADBAQARAAcJrxgfDADBAQAeAAQJlQtaJwBjAAAAAA==.Lefthorn:BAAALgADCgIJAgAAAA==.Lenneth:BAAALgAECgIJAgAAAA==.',
Li='Lightofdawn:BAAALgAECgMJAwAAAA==.Lightstyle:BAAALgADCgMJAwAAAA==.Lilow:BAABLgAECn8zAAINAAkJ/BE5GQDXAQANAAkJ/BE5GQDXAQAAAA==.',
Ll='Llarker:BAABLgAECn8gAAMIAAcJ2wciowARAQAIAAcJ2wciowARAQAaAAYJSwFqNgBbAAAAAA==.',
Lo='Lockendron:BAAALgADCgQJBAAAAA==.Locketharion:BAAALgADCgQJBAAAAA==.Lockpebbles:BAAALgADCgMJAwAAAA==.Lokomachina:BAABLgAECn8UAAIYAAcJLyETHwBLAgAYAAcJLyETHwBLAgAAAA==.Lonesdove:BAAALgADCgEJAQAAAA==.',
Lu='Luminia:BAAALgAECgUJBQAAAA==.Lunacy:BAAALgAECgEJAQAAAA==.',
Ly='Lynngosa:BAAALgAECgcJDAAAAA==.Lyrana:BAAALgADCgQJBAAAAA==.Lyrasa:BAAALgADCgQJBAAAAA==.',
Ma='Maelidrael:BAAALgAECgIJAgABLgAECgkJLgAOAMsaAA==.Magisterium:BAABLgAECn8gAAMSAAcJawQwQADHAAASAAYJsgQwQADHAAANAAEJ/QFffgAYAAAAAA==.Malady:BAABLgAECn8sAAINAAkJwCCOBgDMAgANAAkJwCCOBgDMAgAAAA==.Malakyde:BAAALgADCgMJAwAAAA==.Malt:BAABLgAECn8ZAAIFAAgJvCC5MADkAQAFAAgJvCC5MADkAQAAAA==.Malthorial:BAAALgADCgEJAQAAAA==.Mario:BAAALgAFFAEJAwAAAA==.Mattenom:BAAALgADCgYJCAAAAA==.Maulware:BAAALgADCgEJAQAAAA==.',
Mb='Mbrodh:BAAALgAECgQJBAAAAA==.Mbrosmites:BAAALgAECgIJBAAAAA==.',
Md='Mdeag:BAAALgAECgUJDwAAAA==.',
Me='Mefistofeles:BAACLgAFFH8IAAIWAAMJLBIGHQD4AAAWAAMJLBIGHQD4AAAuAAQKfyIAAhYACAlmGC4SAPEBABYACAlmGC4SAPEBAAAA.Meingaree:BAABLgAECn8UAAIEAAcJIhd7CACXAQAEAAcJIhd7CACXAQAAAA==.Merlinus:BAABLgAECn8lAAIIAAcJ4gq0lABTAQAIAAcJ4gq0lABTAQAAAA==.Merton:BAAALgADCggJDAAAAA==.',
Mi='Mightyguzz:BAABLgAECn85AAIdAAkJjw/0EACwAQAdAAkJjw/0EACwAQAAAA==.Miku:BAAALgAECgMJBAAAAA==.Mitchelle:BAAALgAECgMJBQAAAA==.',
Mo='Moirayne:BAAALgAECgYJBQAAAA==.Moomkin:BAABLgAECn8oAAIKAAgJgwwLLgA6AQAKAAgJgwwLLgA6AQAAAA==.',
My='Mythicblade:BAAALgADCgEJAQAAAA==.',
['Mø']='Møønchild:BAAALgAECgMJAwAAAA==.',
Na='Nai:BAAALgAECgQJDAAAAA==.Nanaish:BAAALgADCgIJAgAAAA==.Narpul:BAABLgAECn8rAAIaAAkJBB5wAwC0AgAaAAkJBB5wAwC0AgAAAA==.Natë:BAACLgAFFH8QAAIdAAMJOhhdFQDLAAAdAAMJOhhdFQDLAAAuAAQKfzAAAh0ACQkvIWUDACMDAB0ACQkvIWUDACMDAAAA.Nazend:BAAALgADCgQJBwAAAA==.',
Ne='Necrotalon:BAAALgAECgYJDAAAAA==.Nelosi:BAAALgAECgMJCAAAAA==.Neondh:BAACLgAFFH8NAAIFAAMJSyQQKgA+AQAFAAMJSyQQKgA+AQAuAAQKfzEAAgUACQmFJA4NABcDAAUACQmFJA4NABcDAAAA.Nerzhùl:BAABLgAECn8lAAIMAAkJGgmWMABPAQAMAAkJGgmWMABPAQAAAA==.',
Nh='Nharuna:BAABLgAECn8oAAIYAAgJ1xIxRACpAQAYAAgJ1xIxRACpAQAAAA==.',
Ni='Nickolaos:BAAALgAECgEJAQAAAA==.Nieloriel:BAABLgAECn85AAMfAAkJkBJtJAC8AQAfAAkJkBJtJAC8AQAIAAgJmgrYdgBgAQAAAA==.Nightwishing:BAAALgAECgQJBAAAAA==.Niupiadps:BAAALgAECgIJAgAAAA==.Niykee:BAABLgAECn8gAAQhAAkJziIdAwBRAgAhAAYJMyQdAwBRAgAWAAcJPiKmHAAaAgAiAAcJCx5mBgARAgAAAA==.',
No='Noboundss:BAABLgAECn8UAAMFAAgJ0AoldwAMAQAFAAcJZwsldwAMAQAJAAMJPwiUSQBUAAAAAA==.Nobóunds:BAAALgAECgkJEAAAAA==.Nomnoms:BAAALgAECgYJEQAAAA==.Nomoreheals:BAAALgAECgYJDQAAAA==.Notkarl:BAAALgAECgIJAwAAAA==.Nowimpissed:BAACLgAFFH8PAAMCAAMJ9SHJEAAqAQACAAMJ9SHJEAAqAQAYAAEJvyDWHgBkAAAuAAQKfxUABAIABgnEHtEQAA0CAAIABgnEHtEQAA0CABgABAkPFsp5APoAABcABAnmDzBbANcAAAAA.Noztra:BAACLgAFFH8IAAIOAAMJsQdebgDYAAAOAAMJsQdebgDYAAAuAAQKfyMAAg4ABwmmDzC1AHUBAA4ABwmmDzC1AHUBAAAA.',
Nu='Nuker:BAAALgAECgEJAQAAAA==.',
Ny='Nysrogh:BAAALgAECgUJEgABLgAFFAQJDwALAPsSAA==.',
Ob='Obsideon:BAAALgAECggJEwAAAA==.',
Oh='Ohgr:BAAALgAECgYJCwAAAA==.Ohshifty:BAABLgAECn80AAMKAAkJ0xDZHQCrAQAKAAkJ0xDZHQCrAQALAAQJbAThkQBtAAAAAA==.',
Ol='Olan:BAAALgAECgYJBgAAAA==.Olie:BAABLgAECn8bAAIYAAgJ9wl3XgBdAQAYAAgJ9wl3XgBdAQAAAA==.',
Or='Orbsicles:BAAALgAECggJEgAAAA==.',
Ou='Ouragan:BAAALgAECgQJBAAAAA==.',
Pa='Paedrig:BAAALgADCgIJAgAAAA==.Papitomyrey:BAABLgAECn8gAAMTAAkJKCSIBAABAwATAAkJKCSIBAABAwAUAAUJYh0GLADsAAAAAA==.Paramedic:BAAALgADCgIJAgAAAA==.Passtheflask:BAABLgAECn8eAAIDAAcJGgcmlwD4AAADAAcJGgcmlwD4AAAAAA==.',
Pe='Perdition:BAAALgAECgEJAQAAAA==.Pestílence:BAACLgAFFH8JAAIGAAMJHBhhjAC1AAAGAAMJHBhhjAC1AAAuAAQKfz8AAwYACQk1IjUSAL0CAAYACQk1IjUSAL0CABAAAQnEEZBHACoAAAAA.',
Ph='Phaesphoros:BAABLgAECn8gAAIPAAkJXxCAPgCCAQAPAAkJXxCAPgCCAQAAAA==.Phenor:BAAALgAECgQJBAAAAA==.',
Po='Poe:BAAALgADCgYJBgABLgAECgcJFQAOAOEXAA==.Powpow:BAABLgAECn8fAAIWAAgJXxi1DwAOAgAWAAgJXxi1DwAOAgAAAA==.',
Pr='Prejudice:BAABLgAECn8cAAIfAAgJ/RTeHwDeAQAfAAgJ/RTeHwDeAQAAAA==.Primévil:BAAALgAECgYJBgABLgAECggJJwAMADAYAA==.Priscilla:BAAALgAECgEJAgAAAA==.Prowlcow:BAABLgAECn8pAAILAAkJdRfpFwBkAgALAAkJdRfpFwBkAgAAAA==.',
Ps='Psychosis:BAABLgAECn8uAAIGAAkJ5B02HgBxAgAGAAkJ5B02HgBxAgAAAA==.',
Pu='Putrescence:BAAALgADCgEJAQAAAA==.',
['Pû']='Pûff:BAAALgAECgcJDwAAAA==.',
Qm='Qmpel:BAAALgADCgMJAwAAAA==.',
Ra='Raiiz:BAACLgAFFH8IAAIOAAMJBBBmLAAFAQAOAAMJBBBmLAAFAQAuAAQKfyYAAg4ACAkhHI4/AHoCAA4ACAkhHI4/AHoCAAAA.Rainhoof:BAABLgAECn8jAAMRAAgJOhkECQAFAgARAAgJOhkECQAFAgALAAUJYAiAhwDHAAAAAA==.Ralneth:BAACLgAFFH8XAAMHAAgJphCGBwAdAgAHAAcJgRCGBwAdAgAZAAMJABnoAwAOAQAuAAQKfyQAAxkACAmrIFADAOsCABkACAmfH1ADAOsCAAcABgnYG0IYAA8CAAAA.Ranare:BAAALgAECgYJBgAAAA==.Randomtask:BAAALgADCgUJBgAAAA==.Rapala:BAABLgAECn8mAAIDAAkJ+hyLFQCMAgADAAkJ+hyLFQCMAgAAAA==.Rapalaa:BAAALgAECgcJDAABLgAECgkJJgADAPocAA==.Raspútin:BAABLgAECn8yAAMjAAkJuRgZDQBGAgAjAAkJuRgZDQBGAgAbAAQJ8AfVVQC5AAAAAA==.Rawkfice:BAAALgADCggJFAAAAA==.',
Re='Redlefevoker:BAAALgADCgYJCQAAAA==.Renfield:BAAALgADCgYJBwAAAA==.Revok:BAAALgAECgcJCwAAAA==.Revoker:BAAALgADCgYJCAAAAA==.',
Ri='Riordan:BAAALgAFFAEJAgAAAA==.Rivvetear:BAAALgADCgYJBgAAAA==.',
Rj='Rjolz:BAACLgAFFH8KAAIGAAMJ1CUMPABLAQAGAAMJ1CUMPABLAQAuAAQKfzYAAgYACQn7JRoCAG8DAAYACQn7JRoCAG8DAAAA.',
Ro='Roflchopr:BAAALgAECgYJBwAAAA==.Roguish:BAAALgADCgcJCQAAAA==.Rootzi:BAAALgAECgIJAwABLgAECgkJIgAGABcdAA==.Rootzidk:BAABLgAECn8iAAIGAAgJFx26QADfAQAGAAgJFx26QADfAQAAAA==.',
Ru='Rucks:BAABLgAECn8iAAMbAAgJORq8HgCPAQAbAAgJbBG8HgCPAQAjAAYJzBpFLQA0AQAAAA==.',
Sa='Saelem:BAAALgAECgYJBgAAAA==.Sandalfon:BAAALgAECgYJDgAAAA==.Sanleron:BAAALgAFFAEJAQAAAA==.Sarith:BAAALgAECgQJAQAAAA==.Saske:BAAALgADCgMJBwABLgAECgEJAQABAAAAAA==.',
Sc='Scargon:BAAALgAECgQJBwAAAA==.',
Se='Selidori:BAAALgADCgYJBgAAAA==.Seralicht:BAACLgAFFH8RAAISAAYJLxXyBADLAQASAAYJLxXyBADLAQAuAAQKfxoAAxIACAkOHRwQAGUCABIACAkOHRwQAGUCAA0AAQmKC/JuADQAAAAA.',
Sh='Shaliri:BAAALgADCgEJBAAAAA==.Shamanata:BAAALgADCgMJAwAAAA==.Sharayse:BAABLgAECn8hAAIOAAkJWgxGWgCyAQAOAAkJWgxGWgCyAQAAAA==.Sharmee:BAAALgAECgYJCAAAAA==.Shishy:BAAALgADCgYJCwAAAA==.Shockohôlic:BAABLgAECn8nAAQMAAgJMBikGwDXAQAMAAgJMBikGwDXAQAPAAYJTxCeSwBUAQAkAAEJoAphKwA4AAAAAA==.Shocky:BAAALgAECgcJCgAAAA==.',
Sk='Skullkìng:BAABLgAECn8jAAIGAAkJuhTaPADsAQAGAAkJuhTaPADsAQAAAA==.',
Sl='Slingablade:BAACLgAFFH8HAAIFAAMJ7AXAVwCuAAAFAAMJ7AXAVwCuAAAuAAQKfx8AAwUACQn3En04AMMBAAUACQlxEX04AMMBAAkAAwlNEY81AK4AAAAA.',
Sm='Smashnskullz:BAAALgAECgQJBgABLgAECgUJBQABAAAAAA==.',
Sn='Sniffsniff:BAACLgAFFH8JAAIIAAMJxyVYLgAyAQAIAAMJxyVYLgAyAQAuAAQKfykAAwgACAlHJQYKAEEDAAgACAlHJQYKAEEDAB8AAQnBHqVvAE8AAAAA.',
So='Solvi:BAABLgAECn8fAAILAAcJ9xcaTQA3AQALAAcJ9xcaTQA3AQAAAA==.Sonira:BAAALgADCgMJBQAAAA==.Soulbrand:BAABLgAECn8jAAINAAgJiQmKLABJAQANAAgJiQmKLABJAQAAAA==.Southpawclaw:BAAALgAECgEJAQABLgAECggJFwAkAPAfAA==.',
Sp='Spellz:BAABLgAECn8kAAINAAgJIB9cCgCHAgANAAgJIB9cCgCHAgAAAA==.Spoo:BAAALgADCgYJCAAAAA==.Spuggle:BAAALgAECgQJBAAAAA==.',
St='Stabathuh:BAAALgADCgYJBgAAAA==.Starman:BAAALgAECgkJCQAAAA==.Stoopidrood:BAAALgADCgQJBAABLgADCgUJBQABAAAAAA==.Stoopidtroll:BAAALgADCgUJBQAAAA==.Stormclaw:BAABLgAECn8bAAIlAAgJ/wtWDgA9AQAlAAgJ/wtWDgA9AQAAAA==.Straeka:BAAALgAECgIJAgAAAA==.Stëvë:BAAALgAECgEJAgABLgAECgYJCgABAAAAAA==.',
Su='Sufiya:BAABLgAECn8gAAIYAAkJLw95QAC1AQAYAAkJLw95QAC1AQAAAA==.Suhwoo:BAAALgAECgcJDwAAAA==.Sumig:BAAALgADCgEJBAAAAA==.',
Sy='Sylvershadow:BAABLgAECn8aAAIYAAcJgA/GYwBQAQAYAAcJgA/GYwBQAQAAAA==.Sym:BAAALgADCgcJCQAAAA==.',
Ta='Taintedsoulv:BAAALgADCgUJBgAAAA==.Taliri:BAAALgADCgEJAQABLgADCgQJBQABAAAAAA==.Tandarilada:BAAALgAFFAEJBAAAAA==.Tanknspankn:BAAALgAECgUJBwAAAA==.Tankurface:BAAALgAECgEJAgAAAA==.',
Th='Thalvint:BAACLgAFFH8IAAIUAAMJ4ReQFgDlAAAUAAMJ4ReQFgDlAAAuAAQKfzIAAxQACQlXIx0CAA0DABQACQlXIx0CAA0DABMABgnVEiJbAEIBAAAA.Theblackhand:BAABLgAECn8dAAMMAAYJ1RXTSgAcAQAMAAUJaxPTSgAcAQAPAAYJrQ+gYgD8AAAAAA==.Thefira:BAAALgADCgkJCQAAAA==.Thickdk:BAABLgAECn8aAAIGAAgJHRZTbgCtAQAGAAgJHRZTbgCtAQAAAA==.Thoriel:BAAALgAECgEJAgAAAA==.',
Ti='Timefall:BAAALgAECgkJDgAAAA==.Titanic:BAAALgAECgcJEAAAAA==.',
To='Tomcruise:BAAALgAECgkJDwAAAA==.Toshiro:BAAALgADCgcJBwAAAA==.Totemlyawsum:BAABLgAFFH8IAAIMAAMJ3AkkKQDBAAAMAAMJ3AkkKQDBAAAAAA==.Touchymcfeel:BAAALgADCgMJAwAAAA==.',
Tr='Trckr:BAAALgADCgIJAgAAAA==.Treeiage:BAAALgAECgUJCAAAAA==.Trooblu:BAAALgAECgYJEgAAAA==.',
Tw='Twotone:BAAALgAECgEJAQAAAA==.',
['Té']='Téz:BAAALgAECgYJEAAAAA==.',
['Tê']='Têzeret:BAAALgAECgEJAgAAAA==.',
Ul='Ulkthar:BAABLgAECn8wAAITAAgJ2BPKKAAZAgATAAgJ2BPKKAAZAgAAAA==.Ultrauchuva:BAAALgADCgEJAQAAAA==.',
Un='Unholyhammer:BAAALgADCgIJAgABLgAECgUJBQABAAAAAA==.',
Va='Vanarn:BAAALgADCgEJAQABLgADCgQJBQABAAAAAA==.Vanlin:BAABLgAECn8jAAILAAgJUB6+FACCAgALAAgJUB6+FACCAgAAAA==.',
Ve='Vexxdr:BAACLgAFFH8FAAILAAMJZgnvNwCzAAALAAMJZgnvNwCzAAAuAAQKfx8AAgsACAkcEtc5AL4BAAsACAkcEtc5AL4BAAAA.Vexxs:BAABLgAECn8XAAIPAAkJlxTVHQAxAgAPAAkJlxTVHQAxAgABLgAFFAMJBQALAGYJAA==.',
Vi='Virtey:BAAALgADCgUJBQAAAA==.Virtuous:BAAALgADCgYJBwAAAA==.',
Vl='Vladzy:BAAALgADCgcJAwAAAA==.',
Vo='Voidsuzu:BAAALgAECgMJAwABLgAECgkJMgAaAC0UAA==.Vormedicus:BAAALgAECgIJAwABLgAECgkJMgAjALkYAA==.',
Vu='Vulperas:BAABLgAECn8lAAIMAAkJJg7cMABNAQAMAAkJJg7cMABNAQAAAA==.',
Vy='Vynastallan:BAABLgAECn8cAAMYAAcJhSNqKAASAgAYAAcJhSNqKAASAgAXAAEJehfShgA1AAAAAA==.Vyper:BAEBLgAECn8lAAIHAAgJcxnxGQDnAQAHAAgJcxnxGQDnAQABLgAFFAMJBwARAJoRAA==.',
Wa='Waroo:BAABLgAECn8cAAIKAAgJ6g2PKABcAQAKAAgJ6g2PKABcAQAAAA==.',
We='Wellcole:BAAALgADCgYJBgAAAA==.Wenden:BAAALgAFFAEJAgAAAA==.Wengo:BAAALgADCgkJCgAAAA==.',
Wi='Wilbert:BAAALgADCgEJAQAAAA==.Winniethepo:BAAALgAECgQJBAAAAA==.Witherflow:BAAALgAECgIJAgAAAA==.',
Wo='Woodey:BAAALgADCgcJCAAAAA==.',
Wu='Wulffric:BAABLgAECn8UAAICAAYJThMvKgAtAQACAAYJThMvKgAtAQAAAA==.',
Xe='Xeo:BAAALgADCgMJAwAAAA==.',
Ya='Yachirú:BAABLgAECn8yAAIaAAkJLRTyCwDaAQAaAAkJLRTyCwDaAQAAAA==.Yahkisoba:BAAALgAECgEJAQAAAA==.',
Ye='Yessir:BAAALgAECgEJAQABLgAECggJGQAbACUZAA==.',
Yi='Yiang:BAABLgAECn8nAAIbAAkJ0R0HBwC5AgAbAAkJ0R0HBwC5AgAAAA==.',
Yl='Ylndrysa:BAABLgAECn9BAAMLAAgJDRu4GwBFAgALAAgJDRu4GwBFAgAKAAMJoRi3RADHAAAAAA==.',
Yt='Ytho:BAAALgADCgYJBgAAAA==.',
Za='Zalithar:BAABLgAECn8VAAIFAAgJZgVsgQD0AAAFAAgJZgVsgQD0AAAAAA==.',
Ze='Zedrock:BAABLgAECn8uAAIOAAkJyxokJABwAgAOAAkJyxokJABwAgAAAA==.Zekodian:BAAALgADCgcJDQAAAA==.Zentner:BAABLgAECn8uAAMKAAkJXx+tCAClAgAKAAkJXx+tCAClAgAeAAQJPAodJAB8AAAAAA==.Zeropistol:BAABLgAECn8aAAIOAAgJNQMkswABAQAOAAgJNQMkswABAQAAAA==.Zexrous:BAAALgADCgEJAQAAAA==.',
Zh='Zhas:BAAALgAECgcJEQAAAA==.',
Zu='Zuro:BAABLgAECn8aAAMYAAgJzA3eWABrAQAYAAgJzA3eWABrAQAXAAEJCgHPmQAaAAAAAA==.',
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
