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

local lookup = {'Monk-Windwalker','Priest-Shadow','Hunter-Survival','Rogue-Subtlety','Priest-Discipline','Priest-Holy','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Augmentation','Shaman-Restoration','Paladin-Retribution','Unknown-Unknown','DemonHunter-Havoc','Druid-Balance','Druid-Restoration','Shaman-Elemental','Mage-Frost','Paladin-Holy','DeathKnight-Blood','Druid-Feral','Warrior-Fury','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Evoker-Devastation','Paladin-Protection','Monk-Mistweaver','Warrior-Protection','Druid-Guardian','Mage-Fire','Rogue-Outlaw','Evoker-Preservation','Rogue-Assassination','DemonHunter-Vengeance','Monk-Brewmaster','Shaman-Enhancement',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Ablestract:BAAALgADCggJCQAAAA==.',
Ac='Acid:BAAALgAECggJEAAAAA==.',
Ad='Adam:BAAALgAFFAEJAgABLgAFFAEJBQABAB4mAA==.Adreane:BAAALgAECgMJBAAAAA==.',
Af='Aftrlyfe:BAAALgAECgkJCQAAAA==.',
Ai='Aiyana:BAAALgADCgkJEQAAAA==.',
Ak='Akamma:BAAALgAECgcJDgAAAA==.Akarimos:BAAALgADCgMJAwAAAA==.',
Al='Alealle:BAAALgADCgMJAwAAAA==.Algeriono:BAAALgAECgMJAwAAAA==.Aliluna:BAAALgAECgYJEAAAAA==.Alirain:BAAALgAECgUJBwAAAA==.Alispere:BAAALgADCgUJBQAAAA==.Aliwings:BAAALgAECgQJCAAAAA==.Alizaranna:BAAALgADCgEJAQABLgAECgYJGAACAOkVAA==.',
Am='Amarokk:BAABLgAECn8eAAIDAAcJCgiMLgAtAQADAAcJCgiMLgAtAQAAAA==.Ameliae:BAAALgAECgEJAQAAAA==.',
An='Ancestor:BAABLgAECn8ZAAIEAAYJghagJQBZAQAEAAYJghagJQBZAQAAAA==.Anish:BAAALgAECgEJAQAAAA==.',
Aq='Aqurore:BAAALgADCgYJBgAAAA==.',
Ar='Archaia:BAAALgAECgUJCQAAAA==.Argorok:BAAALgAFFAEJAQAAAA==.Aryi:BAABLgAECn8UAAQFAAkJCgWLQwDqAAAFAAgJMwOLQwDqAAAGAAMJZgmVVAB3AAACAAIJvQS1cgBMAAAAAA==.',
As='Askim:BAAALgADCgcJBwAAAA==.Assyla:BAAALgAECgEJAQAAAA==.Astraeos:BAABLgAFFH8GAAIHAAMJKx5pWwACAQAHAAMJKx5pWwACAQAAAA==.',
Au='Auv:BAACLgAFFH8QAAMHAAQJESaEBwCtAQAHAAQJESaEBwCtAQAIAAEJlQBjGwA6AAAuAAQKfxQAAwgABwmJJkMTALEBAAcABQkZJl9MAOMBAAgABAkgJkMTALEBAAEuAAUUBQkPAAkADCQA.',
Av='Avarii:BAAALgAECgEJAQAAAA==.',
Aw='Awekeha:BAAALgADCgIJAgAAAA==.',
Ax='Axël:BAAALgAFFAEJAQABLgAFFAMJBgAKAKsaAA==.',
Ay='Aylranoa:BAAALgADCgkJCQAAAA==.',
Az='Azimondius:BAACLgAFFH8UAAILAAUJCRqQHwBHAQALAAUJCRqQHwBHAQAuAAQKfzUAAgsACQlyISsFAAkDAAsACQlyISsFAAkDAAAA.Azmora:BAAALgAECgcJDwAAAA==.Azzix:BAAALgADCgQJBQAAAA==.',
Ba='Baddragons:BAAALgADCgYJBgAAAA==.Bandit:BAAALgAECgEJAQAAAA==.Bastis:BAAALgAECgEJBAABLgAFFAQJDQAMALEmAA==.Batreaux:BAAALgAFFAEJAgAAAA==.',
Be='Beaman:BAAALgADCgEJAQAAAA==.Bearkake:BAAALgAECgMJBgAAAA==.Bellgrande:BAAALgADCgYJBgAAAA==.Belthora:BAAALgAECgYJCAAAAA==.Bepallylol:BAACLgAFFH8KAAINAAUJ0hDOKgBOAQANAAUJ0hDOKgBOAQAuAAQKfxkAAg0ACAlyH7EtAGwCAA0ACAlyH7EtAGwCAAAA.',
Bi='Bigkeith:BAAALgADCgEJAQAAAA==.Biraj:BAAALgADCggJEAABLgAECgcJLQANAHYIAA==.',
Bl='Blaqichan:BAAALgADCgEJAwABLgADCgQJBQAOAAAAAA==.Blight:BAAALgADCgcJBQAAAA==.Bloodybecky:BAAALgAECgQJBQAAAA==.',
Br='Brakiyamis:BAAALgAECgEJAgAAAA==.Brewmastah:BAAALgAECgYJDAABLgAECgUJBwAOAAAAAA==.Briarynth:BAAALgAECgEJAQAAAA==.Browntotem:BAAALgADCgUJCAAAAA==.',
Bu='Bubblecheeks:BAAALgAECgQJBQAAAA==.Bubblehëarth:BAAALgAECgYJDwAAAA==.Bubby:BAABLgAECn8WAAIHAAcJPx2OQQAIAgAHAAcJPx2OQQAIAgAAAA==.Bucklebunnie:BAAALgADCgEJAQABLgAFFAUJEQAPAFQYAA==.Bulgestomper:BAAALgAECgcJDQAAAA==.Bullzaye:BAAALgAECgQJBAAAAA==.Burbuja:BAABLgAECn8VAAIGAAcJqBAgMABAAQAGAAcJqBAgMABAAQAAAA==.',
Ca='Cadfile:BAAALgAECgQJBgAAAA==.Calimari:BAAALgAECgMJAwAAAA==.Careco:BAAALgADCgYJBgAAAA==.Carpetcrumbs:BAAALgAECgUJBQAAAA==.Catnsevrmeme:BAAALgAECgEJAwAAAA==.',
Ce='Cecilio:BAAALgAECgMJAwAAAA==.Cel:BAAALgAECgEJAgAAAA==.Celzara:BAAALgAECgEJAQAAAA==.Cernunnös:BAAALgADCgIJAgAAAA==.Cetraa:BAACLgAFFH8GAAMQAAMJngszMACsAAAQAAMJngszMACsAAARAAEJtRg0YwBIAAAuAAQKfyoAAxAACAnrGykSADsCABAACAnrGykSADsCABEAAQkTDmHRACwAAAAA.',
Ch='Chastise:BAAALgAECgkJDgAAAA==.Chewÿ:BAAALgAECgcJAwAAAA==.Chii:BAAALgADCgEJAQAAAA==.Chocobro:BAAALgAECgYJCQAAAA==.Chäös:BAAALgAECgUJBQAAAA==.',
Cl='Clingy:BAAALgAECgEJAgAAAA==.',
Co='Cobble:BAABLgAECn8dAAISAAgJExjnHADtAQASAAgJExjnHADtAQAAAA==.Colhap:BAABLgAECn8ZAAICAAcJJhzLIQDJAQACAAcJJhzLIQDJAQAAAA==.Conjure:BAABLgAECn80AAMIAAgJTheTBwDMAQAIAAcJuRmTBwDMAQAHAAgJmQ3bfAA6AQAAAA==.Corbina:BAABLgAECn8jAAITAAgJ6iJ2NQCeAgATAAgJ6iJ2NQCeAgAAAA==.Cousinlarry:BAAALgADCgIJAgABLgADCgQJBQAOAAAAAA==.',
Cr='Cramlutin:BAAALgADCgUJBQAAAA==.Cru:BAAALgAECgkJDgAAAA==.Crui:BAAALgADCgcJBwAAAA==.',
Cu='Culligan:BAACLgAFFH8HAAITAAMJShNgdADnAAATAAMJShNgdADnAAAuAAQKf3oAAhMACQnfHl0VANMCABMACQnfHl0VANMCAAAA.Cuttingcrew:BAAALgADCggJCAAAAA==.',
Cy='Cyclones:BAAALgADCgYJBgABLgAECgUJBQAOAAAAAA==.Cygwin:BAABLgAECn83AAMMAAgJDRybGAB5AgAMAAgJDRybGAB5AgASAAMJZxHeZwCfAAAAAA==.',
Da='Daarius:BAAALgADCgYJBgAAAA==.Darcfrost:BAAALgAECgEJAgAAAA==.Darcyonys:BAAALgAECgIJBQAAAA==.Dariao:BAAALgAECgIJAgABLgAECgkJLQAJAM8ZAA==.Darkironsham:BAAALgAFFAEJAQAAAA==.Darklon:BAAALgAECgkJEwAAAA==.Darknescomez:BAAALgAECgQJCAABLgAECggJKQASADAYAA==.Darkpun:BAAALgADCgcJCQAAAA==.Darîus:BAAALgAECgMJAwAAAA==.Dat:BAAALgAECgcJAQABLgAFFAIJBwATAPkYAA==.Datmage:BAACLgAFFH8HAAITAAIJ+RhhkgCaAAATAAIJ+RhhkgCaAAAuAAQKfxkAAhMABwl4H3FeAB8CABMABwl4H3FeAB8CAAAA.',
De='Deathshockz:BAAALgAECgQJBQABLgAECgUJBQAOAAAAAA==.Deedeet:BAAALgAECgUJBQAAAA==.Deku:BAAALgAFFAEJAgAAAA==.Demunzz:BAAALgADCgUJCQAAAA==.Deriah:BAABLgAECn8pAAINAAgJoBQ3UADxAQANAAgJoBQ3UADxAQAAAA==.Derpatron:BAABLgAECn8UAAMNAAkJzggNhgBYAQANAAkJzggNhgBYAQAUAAEJuQ6gkwA3AAAAAA==.Destruction:BAABLgAECn8WAAIVAAgJuQWYMQDMAAAVAAgJuQWYMQDMAAAAAA==.Devo:BAECLgAFFH8LAAIWAAQJORfDBgAyAQAWAAQJORfDBgAyAQAuAAQKfxQAAhYACQm9H/kCAOMCABYACQm9H/kCAOMCAAAA.',
Di='Dingers:BAAALgAECggJCAABLgAECgkJDwAOAAAAAA==.Disgusti:BAAALgAECggJEwAAAA==.Divinespark:BAABLgAECn8jAAIGAAgJMRXULACTAQAGAAgJMRXULACTAQAAAA==.',
Dk='Dkins:BAAALgAECgIJAgAAAA==.',
Do='Dogeform:BAAALgADCgEJAQAAAA==.Doinkbigs:BAABLgAECn8iAAIHAAgJXQ2raABnAQAHAAgJXQ2raABnAQAAAA==.Doomo:BAAALgADCgYJBgABLgABCgQJBAAOAAAAAA==.Dotsfired:BAAALgADCgQJBAAAAA==.Dotñtrot:BAAALgAFFAIJAgABLgAFFAMJCwAMADUZAA==.',
Dr='Draeneisham:BAAALgAFFAEJAQAAAA==.Dredd:BAAALgAECgQJDQAAAA==.Drewsilla:BAAALgAECgYJDwAAAA==.Druidrose:BAAALgAECgMJAwAAAA==.Druidtrix:BAAALgADCgYJCwAAAA==.Drylogic:BAABLgAECn8yAAIRAAkJAx/YCgAGAwARAAkJAx/YCgAGAwAAAA==.',
Du='Duckworth:BAAALgAECgEJAQAAAA==.Dulcey:BAAALgAECgEJAQABLgAFFAMJBgAQAJ4LAA==.Duruk:BAABLgAECn8aAAIHAAcJnhpgPgDdAQAHAAcJnhpgPgDdAQAAAA==.Dustbroom:BAAALgAECgEJAQAAAA==.',
Ea='Eap:BAAALgAECgcJDwAAAA==.Eazye:BAACLgAFFH8RAAICAAQJ5A7RHAD2AAACAAQJ5A7RHAD2AAAuAAQKfzcAAgIACQlXHIoOAGgCAAIACQlXHIoOAGgCAAAA.',
Eb='Ebone:BAAALgADCgMJAQAAAA==.',
Ec='Ectoscourge:BAAALgADCgcJBgAAAA==.',
Ed='Edgeffs:BAABLgAECn8eAAMXAAgJewoRQAA8AQAXAAgJHAkRQAA8AQAYAAUJZQj5JADFAAAAAA==.',
Ek='Eklipse:BAAALgADCgMJAwABLgABCgQJBAAOAAAAAA==.',
El='Elentiya:BAABLgAECn8kAAMGAAkJvxyYDgB1AgAGAAkJvxyYDgB1AgAFAAEJegd7WgAtAAAAAA==.Elphzz:BAABLgAECn8YAAIEAAgJ+BL1HgADAgAEAAgJ+BL1HgADAgAAAA==.',
Em='Emoose:BAAALgAECgEJAQAAAA==.',
Er='Eriius:BAAALgAECgYJEgAAAA==.',
Ev='Evestar:BAAALgADCgEJAQAAAA==.',
Ez='Ez:BAACLgAFFH8VAAMZAAcJWBUBEwAhAQAZAAYJZhABEwAhAQAaAAIJuBlUcQCcAAAuAAQKfyoAAxkACAn0H6UYAGcCABkACAn0H6UYAGcCABoAAgmXDeEJAUEAAAAA.Ezarath:BAABLgAECn8sAAIbAAgJdwysCgBkAQAbAAgJdwysCgBkAQAAAA==.',
Fa='Fadedaf:BAABLgAECn8UAAIJAAYJjQ0viwANAQAJAAYJjQ0viwANAQAAAA==.',
Fe='Felenn:BAAALgADCgYJDQABLgAECgcJLQANAHYIAA==.Felorc:BAAALgAECgYJCwAAAA==.Fentun:BAAALgAFFAEJAQAAAA==.Feyla:BAAALgAECgUJCQAAAA==.',
Fi='Finnikey:BAAALgAECgIJBAAAAA==.Firstone:BAAALgADCgYJBgAAAA==.',
Fo='Foofs:BAAALgADCgUJBQAAAA==.Foulmuffn:BAAALgADCgYJCQAAAA==.Foulplay:BAAALgADCgMJAwAAAA==.Fovos:BAAALgAECgEJAQAAAA==.',
Fr='Freakonleash:BAABLgAECn8YAAIXAAgJ/Rn7GQB8AgAXAAgJ/Rn7GQB8AgAAAA==.Frimbooze:BAAALgAECgYJBwAAAA==.',
Fu='Fuegodotz:BAAALgADCgUJBQABLgAECgkJJAAKALEcAA==.Fumonkchu:BAAALgADCgIJAQAAAA==.',
['Fé']='Féarôshima:BAAALgAECgEJAQABLgAECggJKQASADAYAA==.',
Ga='Ganjåfarian:BAAALgAECgIJAgAAAA==.',
Ge='Gekatta:BAAALgAECgYJEAAAAA==.Gelektrael:BAABLgAECn8jAAMHAAgJjwtCdABMAQAHAAgJ0QpCdABMAQAIAAEJXAz9dQAvAAAAAA==.',
Gh='Ghostdk:BAAALgAECgcJCAABLgAFFAUJFQANAFUlAA==.Ghostwarrior:BAAALgADCgMJAwABLgAFFAUJFQANAFUlAA==.Ghostzz:BAACLgAFFH8VAAINAAUJVSUEEgC0AQANAAUJVSUEEgC0AQAuAAQKf1IAAw0ACQmbI8wIABsDAA0ACQmbI8wIABsDABwABQkSHp4ZAEABAAAA.',
Gl='Glarb:BAAALgAECgIJAwAAAA==.Glzygldiator:BAACLgAFFH8OAAIKAAMJ1BhXLgDhAAAKAAMJ1BhXLgDhAAAuAAQKfykAAgoACAkWHyo5ABMCAAoACAkWHyo5ABMCAAAA.',
Gn='Gnomelock:BAAALgAFFAEJAQABLgAFFAEJBQABAB4mAA==.',
Go='Gobblin:BAAALgAECgUJDQAAAA==.Gotbandaids:BAAALgAECgEJAQAAAA==.Govegan:BAAALgADCgQJBwAAAA==.',
Gr='Graavey:BAAALgAECgcJAwABLgAFFAMJCwAMADUZAA==.Greyhairs:BAABLgAECn8UAAIaAAcJqQ+gdgBGAQAaAAcJqQ+gdgBGAQAAAA==.Grimthor:BAAALgAECgcJBwAAAA==.Grippy:BAACLgAFFH8HAAIJAAMJRwY2ZwCqAAAJAAMJRwY2ZwCqAAAuAAQKfyYAAgkACAl/HUoiAIQCAAkACAl/HUoiAIQCAAAA.Gromit:BAACLgAFFH8eAAIGAAcJXh0QAwAyAgAGAAcJXh0QAwAyAgAuAAQKfyQAAwYACQlNIZMDACEDAAYACQlNIZMDACEDAAUAAgmnEUdKAG0AAAAA.Grym:BAAALgADCgcJDgAAAA==.',
Gu='Gustófwind:BAACLgAFFH8IAAIBAAQJJSGVCACBAQABAAQJJSGVCACBAQAuAAQKfyAAAwEACQnKIRgEABEDAAEACQnKIRgEABEDAB0AAwnMEkJrALgAAAAA.',
Ha='Hackey:BAAALgAECgMJAwAAAA==.Haldire:BAAALgAECgcJDgAAAA==.Harrypotture:BAAALgADCgEJAQAAAA==.Haschel:BAABLgAECn8wAAMYAAkJriARBADVAgAYAAkJriARBADVAgAeAAMJ9Q6JOACFAAAAAA==.',
He='Hexerfender:BAAALgAECgUJBQAAAA==.Heypal:BAAALgADCgUJCwAAAA==.',
Ho='Hofarmer:BAABLgAECn8YAAIfAAkJUhNPFACiAQAfAAkJUhNPFACiAQAAAA==.Holychris:BAAALgADCgEJAQAAAA==.Holycöw:BAAALgADCgkJCQAAAA==.Holywood:BAAALgAECgYJBwAAAA==.',
Hu='Hurtak:BAAALgAECgcJDgAAAA==.',
Hy='Hycisan:BAABLgAECn8uAAIUAAkJMRw1CgDfAgAUAAkJMRw1CgDfAgAAAA==.',
Ic='Icanlust:BAAALgADCgIJAgAAAA==.Icant:BAAALgADCgEJAgABLgADCgQJBQAOAAAAAA==.Icon:BAAALgAECgQJBQAAAA==.Icydoodad:BAAALgAECgEJAQAAAA==.',
Ig='Ignis:BAAALgADCgMJAwAAAA==.',
Io='Iocomotive:BAAALgAFFAEJAQAAAA==.',
Is='Iskaru:BAAALgAECgEJAQABLgAECgYJDwAOAAAAAA==.',
Ja='Jacklawin:BAAALgAECgMJAwAAAA==.Jasmyn:BAAALgADCgQJBAAAAA==.',
Jb='Jbirdlol:BAAALgADCgUJBAAAAA==.',
Je='Jesse:BAAALgAECgYJEAABLgAFFAIJBwAUAHYXAA==.Jetmage:BAABLgAECn8gAAIgAAkJRyToAADgAgAgAAkJRyToAADgAgAAAA==.',
Ji='Jire:BAAALgAECgUJDQAAAA==.Jittkal:BAAALgADCgMJAwAAAA==.',
Jo='Josh:BAAALgADCgMJAgAAAA==.',
Jp='Jpally:BAABLgAECn8XAAMUAAcJ2Aa8SAAPAQAUAAcJ2Aa8SAAPAQANAAUJSwRA7AC3AAAAAA==.',
Ju='Jurassthicc:BAAALgAECgEJBAAAAA==.',
Jw='Jwøww:BAAALgADCgEJAgABLgADCgQJBQAOAAAAAA==.',
Ka='Kafka:BAAALgADCgcJBgAAAA==.Kanastra:BAABLgAECn8cAAIJAAgJth35JQApAgAJAAgJth35JQApAgABLgAFFAUJFAALAAkaAA==.Karraa:BAABLgAECn8nAAIeAAgJeBnFDwDgAQAeAAgJeBnFDwDgAQAAAA==.Katil:BAAALgAECgEJAQAAAA==.Kaylib:BAABLgAECn8qAAIgAAgJZRDUBACEAQAgAAgJZRDUBACEAQAAAA==.',
Ke='Kea:BAAALgADCgIJAgABLgAECgUJCQAOAAAAAA==.Kerze:BAABLgAECn8UAAIeAAYJlhGKJwDoAAAeAAYJlhGKJwDoAAAAAA==.Kesatrix:BAABLgAECn8qAAIdAAkJnBOXHgAQAgAdAAkJnBOXHgAQAgAAAA==.Kesi:BAAALgADCgQJBAAAAA==.',
Kh='Khai:BAAALgAECgQJBAAAAA==.Khazador:BAAALgADCgkJEgABLgAECgkJGwAHALkXAA==.Khaztharion:BAAALgADCggJCAABLgAECgkJGwAHALkXAA==.Khendrick:BAABLgAECn8aAAINAAkJ1w/fWAC3AQANAAkJ1w/fWAC3AQAAAA==.',
Ki='Kimsmage:BAAALgADCgYJBgAAAA==.Kirdo:BAAALgAECgEJAQAAAA==.Kith:BAAALgAECgEJAgAAAA==.Kitridge:BAAALgAECgcJDQAAAA==.Kittykatt:BAABLgAECn80AAIQAAkJxRurDgBnAgAQAAkJxRurDgBnAgAAAA==.',
Ko='Kolchak:BAAALgADCgYJDQAAAA==.Korel:BAAALgAECgcJDAAAAA==.',
Kr='Kraggo:BAAALgAECgYJCQAAAA==.Krimzin:BAACLgAFFH8YAAINAAUJzSEQIABxAQANAAUJzSEQIABxAQAuAAQKfxwAAw0ACQlnIc4XANoCAA0ACAkOIc4XANoCABQABQlTD4JdALMAAAAA.',
Ku='Kumala:BAAALgAECgMJBQAAAA==.Kungao:BAAALgAECgUJBQAAAA==.',
Ky='Kylea:BAAALgAECgQJBAAAAA==.',
La='Laffiel:BAAALgADCgQJBAAAAA==.Landoh:BAABLgAECn8jAAITAAgJYCKtKQBtAgATAAgJYCKtKQBtAgAAAA==.Larg:BAAALgADCgYJBgAAAA==.Larsen:BAABLgAECn8jAAISAAgJch6aHADwAQASAAgJch6aHADwAQAAAA==.',
Le='Leap:BAABLgAECn8eAAMWAAcJght2DADfAQAWAAcJIxt2DADfAQAfAAUJoBQLLADtAAAAAA==.Lefthorn:BAAALgADCgIJAgAAAA==.Lenneth:BAAALgAECgIJAgAAAA==.',
Li='Lightofdawn:BAAALgAECgMJAwAAAA==.Lightstyle:BAAALgADCgMJAwAAAA==.Lilow:BAABLgAECn85AAICAAkJIhIlHQDUAQACAAkJIhIlHQDUAQAAAA==.',
Ll='Llarker:BAABLgAECn8tAAQNAAcJdghRuAAHAQANAAcJdghRuAAHAQAcAAYJHAPWNgB3AAAUAAIJvQHbiAAvAAAAAA==.',
Lo='Lockendron:BAAALgADCgQJBAAAAA==.Locketharion:BAAALgADCgQJBAAAAA==.Lockpebbles:BAAALgADCgMJAwAAAA==.Lokomachina:BAABLgAECn8UAAIaAAcJLyETHwBLAgAaAAcJLyETHwBLAgAAAA==.Lonesdove:BAAALgADCgEJAQAAAA==.',
Lu='Lucyna:BAAALgAECgMJAwABLgAECgkJJAAhAPUiAA==.Luminia:BAAALgAECgUJBQAAAA==.Lunacy:BAAALgAECgEJAgAAAA==.',
Ly='Lynngosa:BAABLgAECn8aAAMiAAcJww/dFAB1AQAiAAcJww/dFAB1AQALAAcJHAjlTADtAAAAAA==.Lyrana:BAAALgADCgQJBAAAAA==.Lyrasa:BAAALgADCgQJBAAAAA==.',
Ma='Maelidrael:BAAALgAECgMJAwABLgAFFAIJBQATADwRAA==.Magiks:BAAALgAECgYJBgAAAA==.Magisterium:BAABLgAECn8pAAMGAAgJ8gT9OwD1AAAGAAgJ8gT9OwD1AAACAAEJ/QG5kQAYAAAAAA==.Malady:BAABLgAECn8sAAICAAkJwCCRCADBAgACAAkJwCCRCADBAgAAAA==.Malakyde:BAAALgADCgMJAwAAAA==.Malt:BAABLgAECn8ZAAIJAAgJvCBaNwDdAQAJAAgJvCBaNwDdAQAAAA==.Malthorial:BAAALgADCgEJAQAAAA==.Mario:BAABLgAFFH8FAAIBAAEJHibDMgBtAAABAAEJHibDMgBtAAAAAA==.Mattenom:BAAALgADCgYJCAAAAA==.Maulware:BAAALgADCgEJAQAAAA==.',
Mb='Mbrodh:BAAALgAECgQJBAAAAA==.Mbrosmites:BAAALgAECgcJCwAAAA==.',
Md='Mdeag:BAAALgAECgUJEAAAAA==.',
Me='Mefistofeles:BAACLgAFFH8NAAIEAAMJFBSqIwDyAAAEAAMJFBSqIwDyAAAuAAQKfyMAAgQACAlmGBYWAN8BAAQACAlmGBYWAN8BAAAA.Meingaree:BAABLgAECn8YAAIIAAgJ1RR7CAC1AQAIAAgJ1RR7CAC1AQAAAA==.Merlinus:BAABLgAECn8lAAINAAcJ4gq0lABTAQANAAcJ4gq0lABTAQAAAA==.Merton:BAAALgADCggJDAAAAA==.',
Mi='Mightyguzz:BAABLgAECn9AAAIeAAkJmhOuEADRAQAeAAkJmhOuEADRAQAAAA==.Miku:BAAALgAECgMJBAAAAA==.Mitchelle:BAAALgAECgMJBQAAAA==.',
Mo='Moirayne:BAAALgAECgYJBQAAAA==.Moomkin:BAABLgAECn8oAAIQAAgJgwyKNAA4AQAQAAgJgwyKNAA4AQAAAA==.',
My='Mythicblade:BAAALgADCgEJAQAAAA==.',
['Mø']='Møønchild:BAAALgAECgMJAwAAAA==.',
Na='Nai:BAAALgAECgQJDAAAAA==.Nanaish:BAAALgAECgEJAQAAAA==.Narpul:BAABLgAECn8rAAIcAAkJBB5oBACsAgAcAAkJBB5oBACsAgAAAA==.Natë:BAACLgAFFH8QAAIeAAMJOhgFGwCwAAAeAAMJOhgFGwCwAAAuAAQKfzAAAh4ACQkvIWUDACMDAB4ACQkvIWUDACMDAAAA.Nazend:BAAALgADCgQJBwAAAA==.',
Ne='Necrotalon:BAAALgAECgcJEAAAAA==.Nelosi:BAAALgAECgMJCAAAAA==.Neondh:BAACLgAFFH8SAAIJAAQJDCSOIACWAQAJAAQJDCSOIACWAQAuAAQKfzQAAgkACQmIJA4NABcDAAkACQmIJA4NABcDAAAA.Nerzhùl:BAABLgAECn8lAAISAAkJGgmOOABFAQASAAkJGgmOOABFAQAAAA==.',
Nh='Nharuna:BAACLgAFFH8FAAIaAAIJHwhCfwCGAAAaAAIJHwhCfwCGAAAuAAQKfzYAAhoACAlJFd9DAMoBABoACAlJFd9DAMoBAAAA.',
Ni='Nickolaos:BAAALgAECgEJAQAAAA==.Nieloriel:BAABLgAECn85AAMUAAkJkBJaKQC4AQAUAAkJkBJaKQC4AQANAAgJmgojjgBKAQAAAA==.Nightwishing:BAAALgAECgQJBAAAAA==.Niupiadps:BAAALgAECgIJAgAAAA==.Niykee:BAABLgAECn8kAAQhAAkJ9SIGAwB0AgAhAAYJhSQGAwB0AgAEAAcJPiKmHAAaAgAjAAcJCx5mBgARAgAAAA==.',
No='Noboundss:BAABLgAECn8VAAMJAAgJ+gp+gwAMAQAJAAcJmAt+gwAMAQAPAAMJPwjzVgBRAAAAAA==.Nobóunds:BAAALgAECgkJEAAAAA==.Nomnoms:BAAALgAECgYJEQAAAA==.Nomoreheals:BAAALgAECgYJDQAAAA==.Notkarl:BAAALgAECgIJAwAAAA==.Nowimpissed:BAACLgAFFH8PAAMDAAMJ9SE7FgAOAQADAAMJ9SE7FgAOAQAaAAEJvyDWHgBkAAAuAAQKfxcABAMABgnEHp4SABACAAMABgnEHp4SABACABoABAkPFsp5APoAABkABAnmDzBbANcAAAAA.Noztra:BAACLgAFFH8OAAITAAQJjAjVZwANAQATAAQJjAjVZwANAQAuAAQKfysAAhMACAlZFytJAPkBABMACAlZFytJAPkBAAAA.',
Nu='Nuker:BAAALgAECgEJAQAAAA==.',
Ny='Nysrogh:BAAALgAECgUJEgABLgAFFAQJFAARADQXAA==.',
Ob='Obsideon:BAAALgAECggJEwAAAA==.',
Oc='Octoknight:BAAALgADCgEJAQAAAA==.',
Oh='Ohgr:BAAALgAECgYJDgAAAA==.Ohshifty:BAABLgAECn80AAMQAAkJ0xDXIgClAQAQAAkJ0xDXIgClAQARAAQJbASYngBqAAAAAA==.',
Ol='Olan:BAAALgAECgYJCAAAAA==.Olie:BAABLgAECn8bAAIaAAgJ9wkjbgBYAQAaAAgJ9wkjbgBYAQAAAA==.',
Or='Orbsicles:BAABLgAECn8YAAIkAAkJQR8PBgAsAgAkAAkJQR8PBgAsAgAAAA==.',
Ou='Ouragan:BAAALgAECgUJCAAAAA==.',
Pa='Paedrig:BAAALgADCgIJAgAAAA==.Papitomyrey:BAABLgAECn8gAAMXAAkJKCRpBgDxAgAXAAkJKCRpBgDxAgAYAAUJYh0aNQDmAAABLgAFFAMJBQAdAMATAA==.Paramedic:BAAALgADCgIJAgAAAA==.Passtheflask:BAABLgAECn8eAAIHAAcJGgdApgDvAAAHAAcJGgdApgDvAAAAAA==.',
Pe='Perdition:BAAALgAECgEJAQAAAA==.Pestílence:BAACLgAFFH8JAAIKAAMJHBgDsgClAAAKAAMJHBgDsgClAAAuAAQKfz8AAwoACQk1IrgWALYCAAoACQk1IrgWALYCABUAAQnEEZBHACoAAAAA.',
Ph='Phaesphoros:BAABLgAECn8gAAIMAAkJXxAQSACAAQAMAAkJXxAQSACAAQAAAA==.Phenor:BAAALgAECgQJBAAAAA==.',
Po='Poe:BAAALgADCgYJBgABLgAECgcJFQATAOEXAA==.Powpow:BAABLgAECn8mAAIEAAkJWBeDDABRAgAEAAkJWBeDDABRAgAAAA==.',
Pr='Prejudice:BAABLgAECn8cAAIUAAgJ/RRkJADZAQAUAAgJ/RRkJADZAQAAAA==.Primévil:BAAALgAECgYJBgABLgAECggJKQASADAYAA==.Priscilla:BAAALgAECgEJAgAAAA==.Prowlcow:BAABLgAECn8yAAMRAAkJdRdJGwBiAgARAAkJdRdJGwBiAgAWAAIJDxbhMQCDAAAAAA==.',
Ps='Psychosis:BAABLgAECn8uAAIKAAkJ5B3QJABpAgAKAAkJ5B3QJABpAgAAAA==.',
Pu='Putrescence:BAAALgADCgEJAQAAAA==.',
['Pû']='Pûff:BAAALgAECgcJDwAAAA==.',
Qm='Qmpel:BAAALgADCgMJAwAAAA==.',
Ra='Raiiz:BAACLgAFFH8IAAITAAMJBBBmLAAFAQATAAMJBBBmLAAFAQAuAAQKfyYAAhMACAkhHI4/AHoCABMACAkhHI4/AHoCAAAA.Rainhoof:BAABLgAECn8jAAMWAAgJOhkHCwD8AQAWAAgJOhkHCwD8AQARAAUJYAiAhwDHAAAAAA==.Ralneth:BAACLgAFFH8ZAAMLAAgJphAPDQAIAgALAAcJgRAPDQAIAgAbAAQJXRToAwAOAQAuAAQKfyQAAxsACAmrIFADAOsCABsACAmfH1ADAOsCAAsABgnYG0IYAA8CAAAA.Ranare:BAAALgAECgYJBgAAAA==.Randomtask:BAAALgADCgUJBgAAAA==.Rapala:BAABLgAECn8mAAIHAAkJ+hw5GgCBAgAHAAkJ+hw5GgCBAgAAAA==.Rapalaa:BAAALgAECgcJDwABLgAECgkJJgAHAPocAA==.Raspútin:BAABLgAECn8zAAMlAAkJqBmiDQBUAgAlAAkJqBmiDQBUAgABAAQJ8AfVVQC5AAAAAA==.Rawkfice:BAAALgADCggJFAAAAA==.',
Re='Redlefevoker:BAAALgADCgYJCQAAAA==.Renfield:BAAALgADCgYJBwAAAA==.Revok:BAAALgAECgcJCwAAAA==.Revoker:BAAALgADCgYJCAAAAA==.',
Ri='Riordan:BAAALgAFFAEJAgAAAA==.Rivvetear:BAAALgADCgYJBgAAAA==.',
Rj='Rjolz:BAACLgAFFH8OAAIKAAQJZiDmLACVAQAKAAQJZiDmLACVAQAuAAQKfzgAAgoACQn7JVYDAGgDAAoACQn7JVYDAGgDAAAA.',
Ro='Roflchopr:BAAALgAECgcJDQAAAA==.Roguish:BAAALgAECgEJAQAAAA==.Rootzi:BAAALgAECgIJAwABLgAECgkJJAAKALEcAA==.Rootzidk:BAABLgAECn8kAAIKAAkJsRyIMgAsAgAKAAkJsRyIMgAsAgAAAA==.Roshaka:BAAALgAECgIJAwAAAA==.',
Ru='Rucks:BAABLgAECn8iAAMBAAgJORqSIwCIAQAlAAYJzBrULQCiAQABAAgJbBGSIwCIAQAAAA==.',
Ry='Ryzze:BAAALgADCgYJBgAAAA==.',
Sa='Saelem:BAAALgAECgYJBgAAAA==.Saigonbeer:BAAALgAECgMJAwAAAA==.Sandalfon:BAAALgAECgYJDwAAAA==.Sanleron:BAAALgAFFAMJBAAAAA==.Sarith:BAAALgAECgQJAQAAAA==.Saske:BAAALgADCgMJBwABLgAECgEJAQAOAAAAAA==.',
Sc='Scarab:BAAALgAECgYJBgAAAA==.Scargon:BAAALgAECgUJDQAAAA==.',
Se='Selidori:BAAALgADCgYJBgAAAA==.Seralicht:BAACLgAFFH8RAAIGAAYJLxUqCQCfAQAGAAYJLxUqCQCfAQAuAAQKfx0AAwYACAlAHhwQAGUCAAYACAlAHhwQAGUCAAIAAQmKC2aAADEAAAAA.',
Sh='Shadowclawz:BAAALgAECgEJAQAAAA==.Shaliri:BAAALgADCgEJBAAAAA==.Shamanata:BAAALgAECgEJAgAAAA==.Sharayse:BAABLgAECn8hAAITAAkJWgxqZwCnAQATAAkJWgxqZwCnAQAAAA==.Sharmee:BAAALgAECgkJEQAAAA==.Shishy:BAAALgAECgMJAwAAAA==.Shockohôlic:BAABLgAECn8pAAQSAAgJMBjqIADOAQASAAgJMBjqIADOAQAMAAYJ/xCeSwBUAQAmAAEJoAphKwA4AAAAAA==.Shocky:BAAALgAECgcJCgAAAA==.',
Sk='Skullkìng:BAABLgAECn8jAAIKAAkJuhRIRgDoAQAKAAkJuhRIRgDoAQAAAA==.',
Sl='Slingablade:BAACLgAFFH8LAAIJAAQJHQYfVgDYAAAJAAQJHQYfVgDYAAAuAAQKfyQAAwkACQliFj8sAAsCAAkACQlpFT8sAAsCAA8AAwlNEYw+AKoAAAAA.',
Sm='Smashnskullz:BAAALgAECgQJBgABLgAECgUJBQAOAAAAAA==.',
Sn='Sniffsniff:BAACLgAFFH8JAAINAAMJxyV9QAAcAQANAAMJxyV9QAAcAQAuAAQKfykAAw0ACAlHJQYKAEEDAA0ACAlHJQYKAEEDABQAAQnBHkB6AE4AAAEuAAUUBAkNAAwAsSYA.',
So='Solvi:BAABLgAECn8fAAIRAAcJ9xduUwA4AQARAAcJ9xduUwA4AQAAAA==.Sonira:BAAALgADCgMJBQAAAA==.Soulbrand:BAABLgAECn8jAAICAAgJiQmjMwBCAQACAAgJiQmjMwBCAQAAAA==.Southpawclaw:BAAALgAECgEJAQABLgAECggJFwAmAPAfAA==.',
Sp='Spellz:BAABLgAECn8lAAICAAgJ0x+MCwCRAgACAAgJ0x+MCwCRAgAAAA==.Spoo:BAAALgAECgIJAgAAAA==.Spuggle:BAAALgAECgQJBAAAAA==.',
St='Stabathuh:BAAALgADCgYJBgAAAA==.Starman:BAAALgAECgkJCQAAAA==.Stoopidmonk:BAAALgADCgMJAwABLgAECgEJAQAOAAAAAA==.Stoopidrood:BAAALgADCgQJBAABLgAECgEJAQAOAAAAAA==.Stoopidtroll:BAAALgADCgUJBQABLgAECgEJAQAOAAAAAA==.Stormclaw:BAABLgAECn8bAAIkAAgJ/wthEAA3AQAkAAgJ/wthEAA3AQAAAA==.Straeka:BAAALgAECgIJAgAAAA==.Stëvë:BAAALgAECgIJBAABLgAECgYJDwAOAAAAAA==.',
Su='Sufiya:BAABLgAECn8gAAIaAAkJLw+GTACwAQAaAAkJLw+GTACwAQAAAA==.Suhwoo:BAAALgAECgcJDwAAAA==.Sumig:BAAALgADCgEJBAAAAA==.',
Sw='Swiftarrows:BAAALgAECgEJAgAAAA==.',
Sy='Sylvershadow:BAABLgAECn8gAAIaAAgJ2hJYTQCuAQAaAAgJ2hJYTQCuAQAAAA==.Sym:BAAALgADCgcJCQAAAA==.',
Ta='Taintedsoulv:BAAALgADCgUJBgAAAA==.Taliri:BAAALgADCgEJAQABLgADCgQJBQAOAAAAAA==.Tandarilada:BAAALgAFFAEJBAAAAA==.Tanknspankn:BAAALgAECgkJDAAAAA==.Tankurface:BAAALgAECgEJAgAAAA==.',
Th='Thalvint:BAACLgAFFH8MAAIYAAQJSRt1EABEAQAYAAQJSRt1EABEAQAuAAQKfzMAAxgACQmHI6ICAA4DABgACQmHI6ICAA4DABcABgnVEiJbAEIBAAAA.Theblackhand:BAABLgAECn8dAAMSAAYJ1RXTSgAcAQASAAUJaxPTSgAcAQAMAAYJrQ+ZcAD6AAAAAA==.Thefira:BAAALgADCgkJCQAAAA==.Thickdk:BAABLgAECn8aAAIKAAgJHRZTbgCtAQAKAAgJHRZTbgCtAQAAAA==.Thoriel:BAAALgAECgEJAgAAAA==.',
Ti='Timefall:BAAALgAECgkJDgAAAA==.Titanic:BAAALgAECgcJEAAAAA==.',
To='Tomcruise:BAAALgAECgkJDwAAAA==.Toshiro:BAAALgADCgcJBwAAAA==.Totemlyawsum:BAABLgAFFH8LAAISAAQJDg35JAD6AAASAAQJDg35JAD6AAAAAA==.Touch:BAAALgAECgEJAQAAAA==.Touchymcfeel:BAAALgADCgMJAwAAAA==.',
Tr='Trckr:BAAALgADCgIJAgAAAA==.Treeiage:BAAALgAECgUJCAAAAA==.Trooblu:BAAALgAECgYJEgAAAA==.',
Tw='Twotone:BAAALgAECgEJAQAAAA==.',
['Té']='Téz:BAABLgAECn8YAAICAAYJ6RUVMgBKAQACAAYJ6RUVMgBKAQAAAA==.',
['Tê']='Têzeret:BAAALgAECgEJAgAAAA==.',
Ul='Ulkthar:BAABLgAECn8wAAIXAAgJ2BPKKAAZAgAXAAgJ2BPKKAAZAgAAAA==.Ultrauchuva:BAAALgADCgEJAQAAAA==.',
Un='Unholyhammer:BAAALgADCgIJAgABLgAECgUJBQAOAAAAAA==.',
Va='Vacunamatata:BAAALgAECgEJAQAAAA==.Vanarn:BAAALgADCgEJAQABLgADCgQJBQAOAAAAAA==.Vanlin:BAABLgAECn8jAAIRAAgJUB6uFwCAAgARAAgJUB6uFwCAAgAAAA==.',
Ve='Vexxdr:BAACLgAFFH8HAAIRAAMJxwsYQQCnAAARAAMJxwsYQQCnAAAuAAQKfx8AAhEACAkcEtc5AL4BABEACAkcEtc5AL4BAAEuAAUUAwkHAAwAqwUA.Vexxs:BAACLgAFFH8HAAIMAAMJqwV5WACJAAAMAAMJqwV5WACJAAAuAAQKfxoAAgwACQmXFJYjACsCAAwACQmXFJYjACsCAAAA.',
Vi='Virtey:BAAALgADCgUJBQAAAA==.Virtuous:BAAALgADCgYJBwAAAA==.',
Vl='Vladzy:BAAALgADCgcJAwAAAA==.',
Vo='Voidsuzu:BAAALgAECgMJAwABLgAECgkJNwAcALkUAA==.Vormedicus:BAAALgAECgIJAwABLgAECgkJMwAlAKgZAA==.',
Vu='Vulperas:BAABLgAECn8uAAISAAkJfQ5cMABvAQASAAkJfQ5cMABvAQAAAA==.',
Vy='Vynastallan:BAABLgAECn8cAAMaAAcJhSOMIABCAgAaAAcJhSOMIABCAgAZAAEJehfShgA1AAAAAA==.Vyper:BAEBLgAECn8lAAILAAgJcxnLHQDhAQALAAgJcxnLHQDhAQABLgAFFAQJCwAWADkXAA==.',
Wa='Waroo:BAABLgAECn8iAAIQAAgJORL5IgCkAQAQAAgJORL5IgCkAQAAAA==.',
We='Wellcole:BAAALgADCgYJBgAAAA==.Wenden:BAAALgAFFAEJAwAAAA==.Wengo:BAAALgADCgkJCgAAAA==.',
Wi='Wilbert:BAAALgADCgEJAQAAAA==.Winniethepo:BAAALgAECgQJBAAAAA==.Witherflow:BAAALgAECgMJBAAAAA==.',
Wo='Woodey:BAAALgADCgcJCAAAAA==.',
Wu='Wulffric:BAABLgAECn8WAAIDAAcJYxJAJAB2AQADAAcJYxJAJAB2AQAAAA==.',
Xe='Xeo:BAAALgADCgMJAwAAAA==.',
Ya='Yachirú:BAABLgAECn83AAIcAAkJuRS9DQDbAQAcAAkJuRS9DQDbAQAAAA==.Yahkisoba:BAAALgAECgEJAQAAAA==.',
Ye='Yessir:BAAALgAECgEJAQABLgAECgkJGgABAA4XAA==.',
Yi='Yiang:BAABLgAECn8nAAIBAAkJ0R0QCQCpAgABAAkJ0R0QCQCpAgAAAA==.',
Yl='Ylndrysa:BAABLgAECn9DAAMRAAkJoBkJGAB9AgARAAkJoBkJGAB9AgAQAAMJoRjPTQDGAAAAAA==.',
Yt='Ytho:BAAALgADCgYJBgAAAA==.',
Za='Zalithar:BAABLgAECn8VAAIJAAgJZgXMkwDrAAAJAAgJZgXMkwDrAAAAAA==.',
Ze='Zedrock:BAACLgAFFH8FAAITAAIJPBGjkwCXAAATAAIJPBGjkwCXAAAuAAQKfzwAAhMACQmfIWILABkDABMACQmfIWILABkDAAAA.Zekodian:BAAALgADCgcJDQAAAA==.Zentner:BAABLgAECn8uAAMQAAkJXx+dCgCgAgAQAAkJXx+dCgCgAgAfAAQJPAodJAB8AAAAAA==.Zeropistol:BAABLgAECn8aAAITAAgJNQNqxgD6AAATAAgJNQNqxgD6AAAAAA==.Zexrous:BAAALgADCgEJAQAAAA==.',
Zh='Zhas:BAABLgAECn8VAAIGAAcJGxXHKQBsAQAGAAcJGxXHKQBsAQAAAA==.',
Zu='Zuro:BAABLgAECn8bAAMaAAgJ9Q2WZQBsAQAaAAgJ9Q2WZQBsAQAZAAEJCgHPmQAaAAAAAA==.',
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
