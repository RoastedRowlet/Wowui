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

local lookup = {'Monk-Windwalker','Priest-Shadow','Hunter-Survival','Rogue-Subtlety','Priest-Discipline','Priest-Holy','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Augmentation','Shaman-Restoration','Paladin-Retribution','Unknown-Unknown','DemonHunter-Havoc','Druid-Balance','Druid-Restoration','Shaman-Elemental','Warlock-Affliction','Mage-Frost','Paladin-Holy','DeathKnight-Blood','Druid-Feral','Warrior-Fury','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Evoker-Devastation','Paladin-Protection','Monk-Mistweaver','Warrior-Protection','Druid-Guardian','Mage-Fire','Rogue-Outlaw','Evoker-Preservation','Rogue-Assassination','DemonHunter-Vengeance','Monk-Brewmaster','Shaman-Enhancement',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Ablestract:BAAALgADCggJCQAAAA==.',
Ac='Acid:BAAALgAECggJEQAAAA==.',
Ad='Adam:BAAALgAFFAEJAgABLgAFFAEJBQABAB4mAA==.Adreane:BAAALgAECgMJBAAAAA==.',
Af='Aftrlyfe:BAAALgAECgkJCQAAAA==.',
Ai='Aiyana:BAAALgADCgkJEQAAAA==.',
Ak='Akamma:BAAALgAECgcJDgAAAA==.Akarimos:BAAALgADCgMJAwAAAA==.',
Al='Alealle:BAAALgADCgMJAwAAAA==.Algeriono:BAAALgAECgMJAwAAAA==.Aliluna:BAAALgAECgYJEAAAAA==.Alirain:BAAALgAECgUJBwAAAA==.Alispere:BAAALgADCgUJBQAAAA==.Aliwings:BAAALgAECgQJCAAAAA==.Alizaranna:BAAALgADCgEJAQABLgAECgYJGAACAOkVAA==.',
Am='Amarokk:BAABLgAECn8iAAIDAAgJwAgVJwBmAQADAAgJwAgVJwBmAQAAAA==.Ameliae:BAAALgAECgEJAQAAAA==.',
An='Ancestor:BAABLgAECn8bAAIEAAcJjxM3IQCHAQAEAAcJjxM3IQCHAQAAAA==.Anish:BAAALgAECgEJAQAAAA==.',
Aq='Aqurore:BAAALgADCgYJBgAAAA==.',
Ar='Archaia:BAAALgAECgUJCQAAAA==.Argorok:BAAALgAFFAEJAQAAAA==.Aryi:BAABLgAECn8UAAQFAAkJCgXfRgDpAAAFAAgJMwPfRgDpAAAGAAMJZgllVwB3AAACAAIJvQS6egBEAAAAAA==.',
As='Askim:BAAALgADCgcJBwAAAA==.Assyla:BAAALgAECgEJAQAAAA==.Astraeos:BAABLgAFFH8GAAIHAAMJKx54YwD6AAAHAAMJKx54YwD6AAAAAA==.',
Au='Auv:BAACLgAFFH8QAAMHAAQJESaEBwCtAQAHAAQJESaEBwCtAQAIAAEJlQBjGwA6AAAuAAQKfxQAAwgABwmJJkMTALEBAAcABQkZJl9MAOMBAAgABAkgJkMTALEBAAEuAAUUBQkPAAkADCQA.',
Av='Avarii:BAAALgAECgEJAQAAAA==.',
Aw='Awekeha:BAAALgADCgIJAgAAAA==.',
Ax='Axël:BAAALgAFFAEJAQABLgAFFAMJBgAKAKsaAA==.',
Ay='Aylranoa:BAAALgADCgkJCQAAAA==.',
Az='Azimondius:BAACLgAFFH8XAAILAAUJCRpbIwBBAQALAAUJCRpbIwBBAQAuAAQKfzcAAgsACQlyIWcFAAgDAAsACQlyIWcFAAgDAAAA.Azmora:BAAALgAECgcJDwAAAA==.Azzix:BAAALgADCgQJBQAAAA==.',
Ba='Baddragons:BAAALgADCgYJBgAAAA==.Bandit:BAAALgAECgEJAQAAAA==.Bastis:BAAALgAECgEJBAABLgAFFAQJFAAMANAmAA==.Batreaux:BAAALgAFFAEJAgAAAA==.',
Be='Beaman:BAAALgADCgEJAQAAAA==.Bearkake:BAAALgAECgMJBgAAAA==.Bellgrande:BAAALgADCgYJBgAAAA==.Belthora:BAAALgAECgYJCAAAAA==.Bepallylol:BAACLgAFFH8NAAINAAUJ2hMLIACAAQANAAUJ2hMLIACAAQAuAAQKfxkAAg0ACAlyH7EtAGwCAA0ACAlyH7EtAGwCAAAA.',
Bi='Bigkeith:BAAALgADCgEJAQAAAA==.Biraj:BAAALgADCggJEAABLgAECgcJLQANAHYIAA==.',
Bl='Blaqichan:BAAALgADCgEJAwABLgADCgQJBQAOAAAAAA==.Blight:BAAALgADCgcJBQAAAA==.Bloodybecky:BAAALgAECgQJBQAAAA==.',
Bo='Boahancawk:BAAALgADCgkJCQAAAA==.',
Br='Brakiyamis:BAAALgAECgEJAgAAAA==.Brewmastah:BAAALgAECgYJDAABLgAECgUJBwAOAAAAAA==.Briarynth:BAAALgAECgEJAQAAAA==.Browntotem:BAAALgADCgUJCAAAAA==.',
Bu='Bubblecheeks:BAAALgAECgQJBQAAAA==.Bubblehëarth:BAAALgAECgYJDwAAAA==.Bubby:BAABLgAECn8WAAIHAAcJPx2OQQAIAgAHAAcJPx2OQQAIAgAAAA==.Bucklebunnie:BAAALgADCgEJAQABLgAFFAUJEQAPAFQYAA==.Bulgestomper:BAAALgAECgcJDQAAAA==.Bullzaye:BAAALgAECgQJBAAAAA==.Burbuja:BAABLgAECn8WAAIGAAcJqBDYMQA/AQAGAAcJqBDYMQA/AQAAAA==.',
Ca='Cadfile:BAAALgAECgQJBgAAAA==.Calimari:BAAALgAECgMJAwAAAA==.Careco:BAAALgADCgYJBgAAAA==.Carpetcrumbs:BAAALgAECgUJBQAAAA==.Catnsevrmeme:BAAALgAECgQJBwAAAA==.',
Ce='Cecilio:BAAALgAECgMJAwAAAA==.Cel:BAAALgAECgEJAgAAAA==.Celzara:BAAALgAECgEJAQAAAA==.Cernunnös:BAAALgADCgIJAgAAAA==.Cetraa:BAACLgAFFH8GAAMQAAMJnguIMwCsAAAQAAMJnguIMwCsAAARAAEJtRgIaABHAAAuAAQKfysAAxAACQm7GpANAH4CABAACQm7GpANAH4CABEAAQkTDkjWACwAAAAA.',
Ch='Chastise:BAAALgAECgkJDwAAAA==.Chewÿ:BAAALgAECgcJBAAAAA==.Chii:BAAALgADCgEJAQAAAA==.Chocobro:BAAALgAECgYJCQAAAA==.Chäös:BAAALgAECgUJBQAAAA==.',
Cl='Clingy:BAAALgAECgQJBgAAAA==.',
Co='Cobble:BAACLgAFFH8GAAISAAMJvQooOACnAAASAAMJvQooOACnAAAuAAQKfx0AAhIACAkTGGAeAOwBABIACAkTGGAeAOwBAAAA.Colhap:BAABLgAECn8ZAAICAAcJJhzLIQDJAQACAAcJJhzLIQDJAQAAAA==.Conjure:BAACLgAFFH8FAAITAAMJpwiMCgDNAAATAAMJpwiMCgDNAAAuAAQKfzQAAwgACAlOFyMIAMgBAAgABwm5GSMIAMgBAAcACAmZDVqCADMBAAAA.Corbina:BAABLgAECn8jAAIUAAgJ6iJ2NQCeAgAUAAgJ6iJ2NQCeAgAAAA==.Cousinlarry:BAAALgADCgIJAgABLgADCgQJBQAOAAAAAA==.',
Cr='Cramlutin:BAAALgADCgUJBQAAAA==.Cru:BAAALgAECgkJDgAAAA==.Crui:BAAALgADCgcJBwAAAA==.',
Cu='Culligan:BAACLgAFFH8KAAIUAAMJ+xfpdQD0AAAUAAMJ+xfpdQD0AAAuAAQKf3sAAhQACQnfHsIWAM4CABQACQnfHsIWAM4CAAAA.Cuttingcrew:BAAALgADCggJCAAAAA==.',
Cy='Cyclones:BAAALgADCgYJBgABLgAECgUJBQAOAAAAAA==.Cygwin:BAABLgAECn86AAMMAAkJtBu3EADGAgAMAAkJtBu3EADGAgASAAMJZxFPbACfAAAAAA==.',
Da='Daarius:BAAALgADCgYJBgAAAA==.Darcfrost:BAAALgAECgEJAgAAAA==.Darcyonys:BAAALgAECgIJBQAAAA==.Dariao:BAAALgAECgIJAgABLgAECgkJLQAJAM8ZAA==.Darkironsham:BAAALgAFFAEJAQAAAA==.Darklon:BAAALgAECgkJEwAAAA==.Darknescomez:BAAALgAECgQJCAABLgAECgkJMQASAOYYAA==.Darkpun:BAAALgADCgcJCQAAAA==.Darîus:BAAALgAECgMJAwAAAA==.Dat:BAAALgAECgcJAQABLgAFFAIJBwAUAPkYAA==.Datmage:BAACLgAFFH8HAAIUAAIJ+RgJmgCZAAAUAAIJ+RgJmgCZAAAuAAQKfxkAAhQABwl4H3FeAB8CABQABwl4H3FeAB8CAAAA.',
De='Deathshockz:BAAALgAECgQJBQABLgAECgUJBQAOAAAAAA==.Deedeet:BAAALgAECgUJBQAAAA==.Deku:BAAALgAFFAEJAwAAAA==.Demunzz:BAAALgADCgUJCQAAAA==.Deriah:BAABLgAECn8pAAINAAgJoBQ3UADxAQANAAgJoBQ3UADxAQAAAA==.Derpatron:BAABLgAECn8UAAMNAAkJzggejABWAQANAAkJzggejABWAQAVAAEJuQ6gkwA3AAAAAA==.Destruction:BAABLgAECn8XAAIWAAkJfQVYLAD2AAAWAAkJfQVYLAD2AAAAAA==.Devo:BAECLgAFFH8LAAIXAAQJOReqBwApAQAXAAQJOReqBwApAQAuAAQKfxQAAhcACQm9H0oDAOACABcACQm9H0oDAOACAAAA.',
Di='Digoxin:BAAALgAECgEJAgAAAA==.Dingers:BAAALgAECggJDwABLgAECgkJEQAOAAAAAA==.Disgusti:BAAALgAECggJEwAAAA==.Divinespark:BAABLgAECn8jAAIGAAgJMRXULACTAQAGAAgJMRXULACTAQAAAA==.',
Dk='Dkins:BAAALgAECgIJAgAAAA==.',
Do='Dogeform:BAAALgADCgEJAQAAAA==.Doinkbigs:BAABLgAECn8iAAIHAAgJXQ3lbQBfAQAHAAgJXQ3lbQBfAQAAAA==.Doomo:BAAALgADCgYJBgABLgABCgQJBAAOAAAAAA==.Dotsfired:BAAALgADCgQJBAAAAA==.Dotñtrot:BAAALgAFFAIJAgABLgAFFAMJCwAMADUZAA==.',
Dr='Draeneisham:BAAALgAFFAEJAQAAAA==.Draethno:BAAALgAECgQJBAAAAA==.Dredd:BAAALgAECgQJDQAAAA==.Drewsilla:BAAALgAECgYJDwAAAA==.Druidrose:BAAALgAECgMJAwAAAA==.Druidtrix:BAAALgADCgYJCwAAAA==.Drylogic:BAABLgAECn8yAAIRAAkJAx9lCwAGAwARAAkJAx9lCwAGAwAAAA==.',
Du='Duckworth:BAAALgAECgEJAQAAAA==.Dulcey:BAAALgAECgYJBwABLgAFFAMJBgAQAJ4LAA==.Duruk:BAABLgAECn8cAAIHAAcJnhpWQADaAQAHAAcJnhpWQADaAQAAAA==.Dustbroom:BAAALgAECgEJAQAAAA==.',
Ea='Eap:BAAALgAECgcJDwAAAA==.Eazye:BAACLgAFFH8UAAICAAQJxxFMHQAAAQACAAQJxxFMHQAAAQAuAAQKfzcAAgIACQlXHFAPAGUCAAIACQlXHFAPAGUCAAAA.',
Eb='Ebone:BAAALgADCgMJAQAAAA==.',
Ec='Ectoscourge:BAAALgADCgcJBgAAAA==.',
Ed='Edgeffs:BAABLgAECn8fAAMYAAkJlwrgNAB1AQAYAAkJZAngNAB1AQAZAAUJZQj5JADFAAAAAA==.',
Ek='Eklipse:BAAALgADCgMJAwABLgABCgQJBAAOAAAAAA==.',
El='Elentiya:BAABLgAECn8kAAMGAAkJvxyYDgB1AgAGAAkJvxyYDgB1AgAFAAEJegd7WgAtAAAAAA==.Elphzz:BAABLgAECn8YAAIEAAgJ+BL1HgADAgAEAAgJ+BL1HgADAgAAAA==.',
Em='Emoose:BAAALgAECgEJAQAAAA==.',
Er='Eriius:BAAALgAECgcJEwAAAA==.',
Ev='Evestar:BAAALgADCgEJAQAAAA==.',
Ez='Ez:BAACLgAFFH8VAAMaAAcJWBVpFAAfAQAaAAYJZhBpFAAfAQAbAAIJuBn7ewCXAAAuAAQKfyoAAxoACAn0H6UYAGcCABoACAn0H6UYAGcCABsAAgmXDecXAT4AAAAA.Ezarath:BAABLgAECn8tAAIcAAgJdwxDCwBfAQAcAAgJdwxDCwBfAQAAAA==.',
Fa='Fadedaf:BAABLgAECn8UAAIJAAYJjQ0viwANAQAJAAYJjQ0viwANAQAAAA==.',
Fe='Felenn:BAAALgADCgYJDQABLgAECgcJLQANAHYIAA==.Felorc:BAAALgAECgYJCwAAAA==.Fentun:BAAALgAFFAEJAQAAAA==.Feyla:BAAALgAECgUJCQAAAA==.',
Fi='Finnikey:BAAALgAECgIJBAAAAA==.Firstone:BAAALgADCgYJBgAAAA==.',
Fo='Foofs:BAAALgADCgUJBQAAAA==.Foulmuffn:BAAALgADCgYJCQAAAA==.Foulplay:BAAALgADCgMJAwAAAA==.Fovos:BAAALgAECgEJAQAAAA==.',
Fr='Freakonleash:BAABLgAECn8YAAIYAAgJ/Rn7GQB8AgAYAAgJ/Rn7GQB8AgAAAA==.Frimbooze:BAAALgAECgYJBwAAAA==.',
Fu='Fuegodotz:BAAALgADCgUJBQABLgAECgkJJAAKALEcAA==.Fumonkchu:BAAALgADCgIJAQAAAA==.',
['Fé']='Féarôshima:BAAALgAECgEJAQABLgAECgkJMQASAOYYAA==.',
Ga='Ganjåfarian:BAAALgAECgIJAgAAAA==.',
Ge='Gekatta:BAAALgAECgYJEAAAAA==.Gelektrael:BAABLgAECn8kAAMHAAkJuA3WeQBFAQAHAAgJ0QrWeQBFAQAIAAIJnBQaMQBWAAAAAA==.',
Gh='Ghostdk:BAAALgAECgcJCAABLgAFFAUJGgANAFUlAA==.Ghostwarrior:BAAALgADCgMJAwABLgAFFAUJGgANAFUlAA==.Ghostzz:BAACLgAFFH8aAAINAAUJVSU2FgCuAQANAAUJVSU2FgCuAQAuAAQKf1wAAw0ACQlLJigBAIcDAA0ACQlLJigBAIcDAB0ABQkSHqoaAD8BAAAA.',
Gl='Glarb:BAAALgAECgIJAwAAAA==.Glzygldiator:BAACLgAFFH8OAAIKAAMJ1BhXLgDhAAAKAAMJ1BhXLgDhAAAuAAQKfykAAgoACAkWH747AA8CAAoACAkWH747AA8CAAAA.',
Gn='Gnomelock:BAAALgAFFAEJAQABLgAFFAEJBQABAB4mAA==.',
Go='Gobblin:BAAALgAECgUJDQAAAA==.Gotbandaids:BAAALgAECgEJAQAAAA==.Govegan:BAAALgADCgQJBwAAAA==.',
Gr='Graavey:BAAALgAECgcJAwABLgAFFAMJCwAMADUZAA==.Greyhairs:BAABLgAECn8UAAIbAAcJqQ84fQA/AQAbAAcJqQ84fQA/AQAAAA==.Grimthor:BAAALgAECgcJBwAAAA==.Grippy:BAACLgAFFH8HAAIJAAMJRwZlbgCmAAAJAAMJRwZlbgCmAAAuAAQKfyYAAgkACAl/HUoiAIQCAAkACAl/HUoiAIQCAAAA.Gromit:BAACLgAFFH8eAAIGAAcJXh3wAwApAgAGAAcJXh3wAwApAgAuAAQKfyQAAwYACQlNIZMDACEDAAYACQlNIZMDACEDAAUAAgmnEUdKAG0AAAAA.Grym:BAAALgADCgcJDgAAAA==.',
Gu='Gustófwind:BAACLgAFFH8IAAIBAAQJJSHaCQB5AQABAAQJJSHaCQB5AQAuAAQKfyAAAwEACQnKIXkEAA4DAAEACQnKIXkEAA4DAB4AAwnMEspyALgAAAAA.',
Ha='Hackey:BAAALgAECgkJCgAAAA==.Haldire:BAABLgAECn8VAAIdAAcJxh3kCwADAgAdAAcJxh3kCwADAgAAAA==.Harrypotture:BAAALgADCgEJAQAAAA==.Haschel:BAABLgAECn8wAAMZAAkJriBpBADSAgAZAAkJriBpBADSAgAfAAMJ9Q6JOACFAAAAAA==.',
He='Hexerfender:BAAALgAECgUJBQAAAA==.Heypal:BAAALgADCgUJCwAAAA==.',
Ho='Hofarmer:BAABLgAECn8YAAIgAAkJUhOXFQCiAQAgAAkJUhOXFQCiAQAAAA==.Holychris:BAAALgADCgEJAQAAAA==.Holycöw:BAAALgADCgkJCQAAAA==.Holywood:BAAALgAECgYJBwAAAA==.',
Hu='Hurtak:BAAALgAECgcJDgAAAA==.',
Hy='Hycisan:BAABLgAECn8xAAIVAAkJMRzeCgDdAgAVAAkJMRzeCgDdAgAAAA==.Hysteria:BAAALgAECgIJAgAAAA==.',
Ic='Icanlust:BAAALgADCgIJAgAAAA==.Icant:BAAALgADCgEJAgABLgADCgQJBQAOAAAAAA==.Icon:BAAALgAECgQJBQAAAA==.Icydoodad:BAAALgAECgIJAwAAAA==.',
Ig='Ignis:BAAALgADCgMJAwAAAA==.',
Io='Iocomotive:BAAALgAFFAEJAQAAAA==.',
Is='Iskaru:BAAALgAECgEJAQABLgAECgYJDwAOAAAAAA==.',
Ja='Jacklawin:BAAALgAECgMJAwAAAA==.Jasmyn:BAAALgADCgQJBAAAAA==.',
Jb='Jbirdlol:BAAALgADCgUJBAAAAA==.',
Je='Jenziserrin:BAAALgAECgEJAQAAAA==.Jesse:BAAALgAECgYJEAABLgAFFAIJBwAVAHYXAA==.Jetmage:BAABLgAECn8gAAIhAAkJRyToAADgAgAhAAkJRyToAADgAgAAAA==.',
Ji='Jire:BAAALgAECgUJDQAAAA==.Jittkal:BAAALgADCgMJAwAAAA==.',
Jo='Josh:BAAALgADCgMJAgAAAA==.',
Jp='Jpally:BAABLgAECn8XAAMVAAcJ2AaySgAPAQAVAAcJ2AaySgAPAQANAAUJSwRA7AC3AAAAAA==.',
Ju='Jurassthicc:BAAALgAECgEJBAAAAA==.',
Jw='Jwøww:BAAALgADCgEJAgABLgADCgQJBQAOAAAAAA==.',
Ka='Kafka:BAAALgADCgcJBgAAAA==.Kanastra:BAABLgAECn8dAAIJAAkJrBuxHABlAgAJAAkJrBuxHABlAgABLgAFFAUJFwALAAkaAA==.Karraa:BAABLgAECn8nAAIfAAgJeBm3EADbAQAfAAgJeBm3EADbAQAAAA==.Katil:BAAALgAECgEJAQAAAA==.Kaylib:BAABLgAECn8sAAIhAAkJJxDkAwDFAQAhAAkJJxDkAwDFAQAAAA==.',
Ke='Kea:BAAALgADCgIJAgABLgAECgUJCQAOAAAAAA==.Kerze:BAABLgAECn8UAAIfAAYJlhFZKQDlAAAfAAYJlhFZKQDlAAAAAA==.Kesatrix:BAABLgAECn8qAAIeAAkJnBNcIAASAgAeAAkJnBNcIAASAgAAAA==.Kesi:BAAALgADCgQJBAAAAA==.',
Kh='Khai:BAAALgAECgQJBAAAAA==.Khazador:BAAALgADCgkJEgABLgAECgkJGwAHALkXAA==.Khaztharion:BAAALgADCggJCAABLgAECgkJGwAHALkXAA==.Khendrick:BAABLgAECn8aAAINAAkJ1w8nXQC1AQANAAkJ1w8nXQC1AQAAAA==.',
Ki='Kilerwolf:BAAALgADCgIJAgAAAA==.Kimsmage:BAAALgADCgYJBgAAAA==.Kirdo:BAAALgAECgEJAQAAAA==.Kith:BAAALgAECgEJAgAAAA==.Kitridge:BAAALgAECgcJDQAAAA==.Kittykatt:BAABLgAECn87AAIQAAkJDCC/BgDpAgAQAAkJDCC/BgDpAgAAAA==.',
Ko='Kolchak:BAAALgADCgYJDQAAAA==.Korel:BAAALgAECgcJDAAAAA==.',
Kr='Kraggo:BAAALgAECgcJDQAAAA==.Krimzin:BAACLgAFFH8YAAINAAUJzSFiJgBpAQANAAUJzSFiJgBpAQAuAAQKfxwAAw0ACQlnIc4XANoCAA0ACAkOIc4XANoCABUABQlTDwRgALIAAAAA.',
Ku='Kumala:BAAALgAECgMJBQAAAA==.Kungao:BAAALgAECgUJBQAAAA==.',
Ky='Kylea:BAAALgAECgQJBAAAAA==.',
La='Laffiel:BAAALgADCgQJBAAAAA==.Landoh:BAABLgAECn8kAAIUAAkJ+CH2FwDHAgAUAAkJ+CH2FwDHAgAAAA==.Larg:BAAALgAECgEJAQAAAA==.Larsen:BAABLgAECn8kAAISAAkJZR44FABHAgASAAkJZR44FABHAgAAAA==.',
Le='Leap:BAABLgAECn8fAAMXAAgJ/Bo3DQDdAQAXAAcJIxs3DQDdAQAgAAYJRhXpIgAzAQAAAA==.Lefthorn:BAAALgADCgIJAgAAAA==.Lenneth:BAAALgAECgIJAgAAAA==.',
Li='Lightofdawn:BAAALgAECgMJAwAAAA==.Lightstyle:BAAALgADCgMJAwAAAA==.Lilow:BAABLgAECn85AAICAAkJIhKIHgDPAQACAAkJIhKIHgDPAQAAAA==.',
Ll='Llarker:BAABLgAECn8tAAQNAAcJdgggvwAHAQANAAcJdgggvwAHAQAdAAYJHAPjOAB3AAAVAAIJvQEkjQAvAAAAAA==.',
Lo='Lockendron:BAAALgADCgQJBAAAAA==.Locketharion:BAAALgADCgQJBAAAAA==.Lockpebbles:BAAALgADCgMJAwAAAA==.Lokomachina:BAABLgAECn8UAAIbAAcJLyETHwBLAgAbAAcJLyETHwBLAgAAAA==.Lonesdove:BAAALgADCgEJAQAAAA==.',
Lu='Lucyna:BAAALgAECgMJAwABLgAECgkJJAAiAPUiAA==.Luminia:BAAALgAECgUJBQAAAA==.Lunacy:BAAALgAECgQJBgAAAA==.',
Ly='Lynngosa:BAABLgAECn8iAAMjAAcJcxKiEwCMAQAjAAcJcxKiEwCMAQALAAcJHAgDUADqAAAAAA==.Lyrana:BAAALgADCgQJBAAAAA==.Lyrasa:BAAALgADCgQJBAAAAA==.',
Ma='Maelidrael:BAAALgAECgMJAwABLgAFFAIJBQAUADwRAA==.Magiks:BAAALgAFFAEJAQAAAA==.Magisterium:BAABLgAECn8sAAMGAAgJ8gQQPgD0AAAGAAgJ8gQQPgD0AAACAAEJ/QEtmQAXAAAAAA==.Malady:BAABLgAECn8sAAICAAkJwCAOCQC9AgACAAkJwCAOCQC9AgAAAA==.Malakyde:BAAALgADCgMJAwAAAA==.Malt:BAABLgAECn8ZAAIJAAgJvCCkOQDdAQAJAAgJvCCkOQDdAQAAAA==.Malthorial:BAAALgADCgEJAQAAAA==.Mario:BAABLgAFFH8FAAIBAAEJHiYkNQBrAAABAAEJHiYkNQBrAAAAAA==.Mattenom:BAAALgADCgYJCAAAAA==.Maulware:BAAALgADCgEJAQAAAA==.',
Mb='Mbrodh:BAAALgAECgQJBAAAAA==.Mbrosmites:BAAALgAECgcJCwAAAA==.',
Md='Mdeag:BAAALgAECgUJEwAAAA==.',
Me='Mefistofeles:BAACLgAFFH8QAAIEAAMJFBRKJgDsAAAEAAMJFBRKJgDsAAAuAAQKfyMAAgQACAlmGEAXAN4BAAQACAlmGEAXAN4BAAAA.Meingaree:BAABLgAECn8ZAAIIAAgJjxiyBgDvAQAIAAgJjxiyBgDvAQAAAA==.Merlinus:BAABLgAECn8lAAINAAcJ4gq0lABTAQANAAcJ4gq0lABTAQAAAA==.Merton:BAAALgADCggJDAAAAA==.',
Mi='Mightyguzz:BAABLgAECn9AAAIfAAkJmhOTEQDNAQAfAAkJmhOTEQDNAQAAAA==.Miku:BAAALgAECgMJBAAAAA==.Mitchelle:BAAALgAECgMJBQAAAA==.',
Mo='Moirayne:BAAALgAECgYJBQAAAA==.Moomkin:BAABLgAECn8oAAIQAAgJgwyvNgA3AQAQAAgJgwyvNgA3AQAAAA==.',
My='Mythicblade:BAAALgADCgEJAQAAAA==.',
['Mø']='Møønchild:BAAALgAECgkJDAAAAA==.',
Na='Nai:BAAALgAECgQJDAAAAA==.Nanaish:BAAALgAECgEJAQAAAA==.Narpul:BAABLgAECn8rAAIdAAkJBB68BACpAgAdAAkJBB68BACpAgAAAA==.Natë:BAACLgAFFH8QAAIfAAMJOhg6HQCmAAAfAAMJOhg6HQCmAAAuAAQKfzAAAh8ACQkvIWUDACMDAB8ACQkvIWUDACMDAAAA.Nazend:BAAALgADCgQJBwAAAA==.',
Ne='Necrotalon:BAAALgAECgcJEAAAAA==.Nelosi:BAAALgAECgMJCAAAAA==.Neondh:BAACLgAFFH8VAAIJAAQJPSRLIwCZAQAJAAQJPSRLIwCZAQAuAAQKfzQAAgkACQmIJA4NABcDAAkACQmIJA4NABcDAAAA.Nerzhùl:BAABLgAECn8lAAISAAkJGgkcOwBFAQASAAkJGgkcOwBFAQAAAA==.',
Nh='Nharuna:BAACLgAFFH8HAAIbAAMJnwaZawDAAAAbAAMJnwaZawDAAAAuAAQKfzgAAhsACQnbE9o0AAUCABsACQnbE9o0AAUCAAAA.',
Ni='Nickolaos:BAAALgAECgEJAQAAAA==.Nieloriel:BAABLgAECn85AAMVAAkJkBK8KgC3AQAVAAkJkBK8KgC3AQANAAgJmgp7lABIAQAAAA==.Nightwishing:BAAALgAECgQJBAAAAA==.Niupiadps:BAAALgAECgIJAgAAAA==.Niykee:BAABLgAECn8kAAQiAAkJ9SIuAwB0AgAiAAYJhSQuAwB0AgAEAAcJPiKmHAAaAgAkAAcJCx5mBgARAgAAAA==.',
No='Noboundss:BAABLgAECn8ZAAMJAAgJ+A0IcQA8AQAJAAcJFQ8IcQA8AQAPAAMJPwjnWwBRAAAAAA==.Nobóunds:BAAALgAECgkJEAAAAA==.Nomnoms:BAAALgAECgYJEQAAAA==.Nomoreheals:BAAALgAECgYJDQAAAA==.Notkarl:BAAALgAECgIJAwAAAA==.Nowimpissed:BAACLgAFFH8PAAMDAAMJ9SEMGAANAQADAAMJ9SEMGAANAQAbAAEJvyDWHgBkAAAuAAQKfxcABAMABgnEHnITAAsCAAMABgnEHnITAAsCABsABAkPFsp5APoAABoABAnmDzBbANcAAAAA.Noztra:BAACLgAFFH8RAAIUAAQJqAjBbQANAQAUAAQJqAjBbQANAQAuAAQKfywAAhQACAnjF/BKAPgBABQACAnjF/BKAPgBAAAA.',
Nu='Nuker:BAAALgAECgEJAQAAAA==.',
Ny='Nysrogh:BAAALgAECgUJEgABLgAFFAQJFAARADQXAA==.',
Ob='Obsideon:BAAALgAECggJEwAAAA==.',
Oc='Octoknight:BAAALgADCgEJAQAAAA==.',
Oh='Ohgr:BAAALgAECgYJDgAAAA==.Ohshifty:BAABLgAECn80AAMQAAkJ0xBWJACkAQAQAAkJ0xBWJACkAQARAAQJbAQEogBqAAAAAA==.',
Ol='Olan:BAAALgAECgYJCAAAAA==.Olie:BAABLgAECn8bAAIbAAgJ9wmddABSAQAbAAgJ9wmddABSAQAAAA==.',
Or='Orbsicles:BAABLgAECn8fAAQlAAkJiR9iAwCmAgAlAAkJiR9iAwCmAgAPAAEJKBpEXgBMAAAJAAEJtgsJFgEvAAAAAA==.',
Ou='Ouragan:BAAALgAECgUJCAAAAA==.',
Pa='Paedrig:BAAALgADCgIJAgAAAA==.Papitomyrey:BAABLgAECn8gAAMYAAkJKCQlBwDrAgAYAAkJKCQlBwDrAgAZAAUJYh3/NgDkAAABLgAFFAMJBQAeAMATAA==.Paramedic:BAAALgADCgIJAgAAAA==.Passtheflask:BAABLgAECn8eAAIHAAcJGgcPqwDsAAAHAAcJGgcPqwDsAAAAAA==.',
Pe='Perdition:BAAALgAECgEJAgAAAA==.Pestílence:BAACLgAFFH8JAAIKAAMJHBgOwQChAAAKAAMJHBgOwQChAAAuAAQKfz8AAwoACQk1IjIYALMCAAoACQk1IjIYALMCABYAAQnEEZBHACoAAAAA.',
Ph='Phaesphoros:BAABLgAECn8gAAIMAAkJXxDQSgCAAQAMAAkJXxDQSgCAAQAAAA==.Phenor:BAAALgAECgQJBAAAAA==.',
Po='Poe:BAAALgADCgYJBgABLgAECgcJFQAUAOEXAA==.Powpow:BAABLgAECn83AAIEAAkJ2BrHCACXAgAEAAkJ2BrHCACXAgAAAA==.',
Pr='Prejudice:BAABLgAECn8dAAIVAAkJnxSUHQAUAgAVAAkJnxSUHQAUAgAAAA==.Primévil:BAAALgAECgYJBgABLgAECgkJMQASAOYYAA==.Priscilla:BAAALgAECgEJAgAAAA==.Prowlcow:BAABLgAECn8yAAMRAAkJdRcaHABiAgARAAkJdRcaHABiAgAXAAIJDxbfNACEAAAAAA==.',
Ps='Psychosis:BAABLgAECn8uAAIKAAkJ5B3GJgBmAgAKAAkJ5B3GJgBmAgAAAA==.',
Pu='Putrescence:BAAALgADCgEJAQAAAA==.',
['Pû']='Pûff:BAAALgAECgcJDwAAAA==.',
Qm='Qmpel:BAAALgADCgMJAwAAAA==.',
Ra='Raiiz:BAACLgAFFH8IAAIUAAMJBBBmLAAFAQAUAAMJBBBmLAAFAQAuAAQKfyYAAhQACAkhHI4/AHoCABQACAkhHI4/AHoCAAAA.Rainhoof:BAABLgAECn8kAAMXAAkJsRjQCwD3AQAXAAgJOhnQCwD3AQARAAYJlweAhwDHAAAAAA==.Ralneth:BAACLgAFFH8ZAAMLAAgJphCxDwD+AQALAAcJgRCxDwD+AQAcAAQJXRToAwAOAQAuAAQKfyQAAxwACAmrIFADAOsCABwACAmfH1ADAOsCAAsABgnYG0IYAA8CAAAA.Ranare:BAAALgAECgYJBgAAAA==.Randomtask:BAAALgADCgUJBgAAAA==.Rapala:BAABLgAECn8mAAIHAAkJ+hxwGwB+AgAHAAkJ+hxwGwB+AgAAAA==.Rapalaa:BAAALgAECgcJDwABLgAECgkJJgAHAPocAA==.Raspútin:BAABLgAECn8zAAMmAAkJqBlDDgBSAgAmAAkJqBlDDgBSAgABAAQJ8AfVVQC5AAAAAA==.Rawkfice:BAAALgADCggJFAAAAA==.',
Re='Redlefevoker:BAAALgADCgYJCQAAAA==.Renfield:BAAALgADCgYJCAAAAA==.Revok:BAAALgAECgcJCwAAAA==.Revoker:BAAALgADCgYJCAAAAA==.',
Ri='Riordan:BAAALgAFFAEJAgAAAA==.Rivvetear:BAAALgADCgYJBgAAAA==.',
Rj='Rjolz:BAACLgAFFH8OAAIKAAQJZiC/NACOAQAKAAQJZiC/NACOAQAuAAQKfzgAAgoACQn7JccDAGMDAAoACQn7JccDAGMDAAAA.',
Ro='Roflchopr:BAAALgAECgcJDQAAAA==.Roguish:BAAALgAECgEJAQAAAA==.Rootzi:BAAALgAECgIJAwABLgAECgkJJAAKALEcAA==.Rootzidk:BAABLgAECn8kAAIKAAkJsRyRNAAqAgAKAAkJsRyRNAAqAgAAAA==.Roshaka:BAAALgAECgUJBwAAAA==.',
Ru='Rucks:BAABLgAECn8jAAMBAAkJ1Bo5GQDkAQABAAkJIRM5GQDkAQAmAAYJzBrULQCiAQAAAA==.',
Ry='Ryzze:BAAALgADCgYJBgAAAA==.',
Sa='Saelem:BAAALgAECgYJBgAAAA==.Saigonbeer:BAAALgAECgMJAwAAAA==.Sandalfon:BAAALgAECgYJDwAAAA==.Sanleron:BAABLgAECn8WAAMdAAgJWCGBDQDpAQAdAAYJFiKBDQDpAQANAAUJtBrIogAxAQAAAA==.Sarith:BAAALgAECgQJAQABLgAECgUJBQAOAAAAAA==.Saske:BAAALgADCgMJBwABLgAECgEJAQAOAAAAAA==.',
Sc='Scarab:BAAALgAECgYJBgAAAA==.Scargon:BAAALgAECgcJEAAAAA==.Schizandrol:BAAALgAECgQJBAAAAA==.',
Se='Selidori:BAAALgADCgYJBgAAAA==.Seralicht:BAACLgAFFH8RAAIGAAYJLxWoCgCZAQAGAAYJLxWoCgCZAQAuAAQKfyIAAwYACAmGHhwQAGUCAAYACAmGHhwQAGUCAAIAAQmKC6aFADEAAAAA.',
Sh='Shadowclawz:BAAALgAECgQJBQAAAA==.Shaliri:BAAALgADCgEJBAAAAA==.Shamanata:BAAALgAECgEJAgAAAA==.Sharayse:BAABLgAECn8hAAIUAAkJWgysawChAQAUAAkJWgysawChAQAAAA==.Sharmee:BAAALgAECgkJEQAAAA==.Shishy:BAAALgAECgMJBgAAAA==.Shockohôlic:BAABLgAECn8xAAQSAAkJ5hi9FABBAgASAAkJ5hi9FABBAgAMAAYJ/xC7agAWAQAnAAEJoAphKwA4AAAAAA==.Shocky:BAAALgAECgcJCgAAAA==.',
Sk='Skullkìng:BAABLgAECn8jAAIKAAkJuhSaSgDgAQAKAAkJuhSaSgDgAQAAAA==.',
Sl='Slingablade:BAACLgAFFH8LAAIJAAQJHQbdXADRAAAJAAQJHQbdXADRAAAuAAQKfyQAAwkACQliFu0tAAwCAAkACQlpFe0tAAwCAA8AAwlNEQRCAKkAAAAA.',
Sm='Smashnskullz:BAAALgAECgQJBgABLgAECgUJBQAOAAAAAA==.',
Sn='Sniffsniff:BAACLgAFFH8JAAINAAMJxyV+SQAVAQANAAMJxyV+SQAVAQAuAAQKfykAAw0ACAlHJQYKAEEDAA0ACAlHJQYKAEEDABUAAQnBHsd9AE4AAAEuAAUUBAkUAAwA0CYA.',
So='Solvi:BAABLgAECn8fAAIRAAcJ9xdKVQA4AQARAAcJ9xdKVQA4AQAAAA==.Sonira:BAAALgADCgMJBQAAAA==.Soulbrand:BAABLgAECn8kAAICAAkJMwkILgBpAQACAAkJMwkILgBpAQAAAA==.Southpawclaw:BAAALgAECgEJAQABLgAECggJFwAnAPAfAA==.',
Sp='Spellz:BAABLgAECn8lAAICAAgJ0x8sDACNAgACAAgJ0x8sDACNAgAAAA==.Spoo:BAAALgAECgIJAwAAAA==.Spuggle:BAAALgAECgQJBAAAAA==.',
St='Stabathuh:BAAALgADCgYJBgAAAA==.Starman:BAAALgAECgkJCQAAAA==.Stoopiddk:BAAALgAECgEJAQABLgAECgIJAwAOAAAAAA==.Stoopidmonk:BAAALgADCgMJAwABLgAECgIJAwAOAAAAAA==.Stoopidrood:BAAALgADCgQJBAABLgAECgIJAwAOAAAAAA==.Stoopidtroll:BAAALgADCgUJBQABLgAECgIJAwAOAAAAAA==.Stormclaw:BAABLgAECn8cAAIlAAkJiAzaDQBwAQAlAAkJiAzaDQBwAQAAAA==.Straeka:BAAALgAECgIJAgAAAA==.Stëvë:BAAALgAECgIJBAABLgAECgYJDwAOAAAAAA==.',
Su='Sufiya:BAABLgAECn8gAAIbAAkJLw+eUQCpAQAbAAkJLw+eUQCpAQAAAA==.Suhwoo:BAAALgAECgcJDwAAAA==.Sumig:BAAALgADCgEJBAAAAA==.',
Sw='Swiftarrows:BAAALgAECgEJAgAAAA==.',
Sy='Sylvershadow:BAABLgAECn8mAAIbAAgJJxV1RwDHAQAbAAgJJxV1RwDHAQAAAA==.Sym:BAAALgADCgcJCQAAAA==.',
Ta='Taintedsoulv:BAAALgADCgUJBgAAAA==.Taliri:BAAALgADCgEJAQABLgADCgQJBQAOAAAAAA==.Tandarilada:BAAALgAFFAEJBAAAAA==.Tanknspankn:BAAALgAECgkJDAAAAA==.Tankurface:BAAALgAECgEJAgAAAA==.',
Th='Thalvint:BAACLgAFFH8MAAIZAAQJSRsOEwA+AQAZAAQJSRsOEwA+AQAuAAQKfzMAAxkACQmHI/QCAAoDABkACQmHI/QCAAoDABgABgnVEiJbAEIBAAAA.Theblackhand:BAABLgAECn8dAAMSAAYJ1RXTSgAcAQASAAUJaxPTSgAcAQAMAAYJrQ+7dAD6AAAAAA==.Thefira:BAAALgADCgkJCQAAAA==.Thickdk:BAABLgAECn8aAAIKAAgJHRZTbgCtAQAKAAgJHRZTbgCtAQAAAA==.Thoriel:BAAALgAECgEJAgAAAA==.',
Ti='Timefall:BAAALgAECgkJDgAAAA==.Titanic:BAAALgAECgcJEAAAAA==.',
To='Tomcruise:BAAALgAECgkJEQAAAA==.Toshiro:BAAALgADCgcJBwAAAA==.Totemlyawsum:BAABLgAFFH8LAAISAAQJDg0XKQDrAAASAAQJDg0XKQDrAAAAAA==.Touch:BAAALgAECgEJAQAAAA==.Touchymcfeel:BAAALgADCgMJAwAAAA==.',
Tr='Trckr:BAAALgADCgIJAgAAAA==.Treeiage:BAAALgAECgUJCAAAAA==.Trooblu:BAAALgAECgYJEgAAAA==.',
Tw='Twotone:BAAALgAECgEJAQAAAA==.',
['Té']='Téz:BAABLgAECn8YAAICAAYJ6RWUMwBJAQACAAYJ6RWUMwBJAQAAAA==.',
['Tê']='Têzeret:BAAALgAECgEJAgAAAA==.',
Ul='Ulkthar:BAABLgAECn8wAAIYAAgJ2BPKKAAZAgAYAAgJ2BPKKAAZAgABLgAECggJGQAUAO8TAA==.Ultrauchuva:BAAALgADCgEJAQAAAA==.',
Un='Unholyhammer:BAAALgADCgIJAgABLgAECgUJBQAOAAAAAA==.',
Va='Vacunamatata:BAAALgAECgEJAQAAAA==.Vanarn:BAAALgADCgEJAQABLgADCgQJBQAOAAAAAA==.Vanlin:BAABLgAECn8kAAIRAAkJWh4aDwDaAgARAAkJWh4aDwDaAgAAAA==.',
Ve='Vexxdr:BAACLgAFFH8HAAIRAAMJxwsNRgCYAAARAAMJxwsNRgCYAAAuAAQKfx8AAhEACAkcEtc5AL4BABEACAkcEtc5AL4BAAEuAAUUAwkHAAwAqwUA.Vexxs:BAACLgAFFH8HAAIMAAMJqwUzXwCFAAAMAAMJqwUzXwCFAAAuAAQKfxsAAgwACQnIFQQgAEwCAAwACQnIFQQgAEwCAAAA.',
Vi='Virtey:BAAALgADCgUJBQAAAA==.Virtuous:BAAALgADCgYJBwAAAA==.',
Vl='Vladzy:BAAALgADCgcJAwAAAA==.',
Vo='Voidsuzu:BAAALgAECgMJAwABLgAECgkJNwAdALkUAA==.Vormedicus:BAAALgAECgcJEAABLgAECgkJMwAmAKgZAA==.',
Vu='Vulperas:BAABLgAECn82AAISAAkJHxD1KACkAQASAAkJHxD1KACkAQAAAA==.',
Vy='Vynastallan:BAABLgAECn8cAAMbAAcJhSOMIABCAgAbAAcJhSOMIABCAgAaAAEJehfShgA1AAAAAA==.Vyper:BAEBLgAECn8lAAILAAgJcxnhHgDfAQALAAgJcxnhHgDfAQABLgAFFAQJCwAXADkXAA==.',
Wa='Waroo:BAABLgAECn8iAAIQAAgJORJ/JACjAQAQAAgJORJ/JACjAQAAAA==.',
We='Wellcole:BAAALgADCgYJBgAAAA==.Wenden:BAAALgAFFAEJAwAAAA==.Wengo:BAAALgADCgkJCgAAAA==.',
Wi='Wilbert:BAAALgADCgEJAQAAAA==.Winniethepo:BAAALgAECgQJBAAAAA==.Witherflow:BAAALgAECgQJBQAAAA==.',
Wo='Woodey:BAAALgADCgcJCAAAAA==.',
Wu='Wulffric:BAABLgAECn8XAAIDAAcJYxJKJQBzAQADAAcJYxJKJQBzAQAAAA==.',
Xe='Xeo:BAAALgADCgMJAwAAAA==.',
Ya='Yachirú:BAABLgAECn83AAIdAAkJuRR7DgDYAQAdAAkJuRR7DgDYAQAAAA==.Yahkisoba:BAAALgAECgEJAQAAAA==.',
Ye='Yessir:BAAALgAECgEJAQABLgAECgkJGgABAA4XAA==.',
Yi='Yiang:BAABLgAECn8nAAIBAAkJ0R3aCQCjAgABAAkJ0R3aCQCjAgAAAA==.',
Yl='Ylndrysa:BAABLgAECn9DAAMRAAkJoBnQGAB8AgARAAkJoBnQGAB8AgAQAAMJoRi4UADGAAAAAA==.',
Yt='Ytho:BAAALgADCgYJBgAAAA==.',
Za='Zalithar:BAABLgAECn8VAAIJAAgJZgXPmADrAAAJAAgJZgXPmADrAAAAAA==.',
Ze='Zedrock:BAACLgAFFH8FAAIUAAIJPBFfmwCXAAAUAAIJPBFfmwCXAAAuAAQKfz8AAhQACQk0IgUKACgDABQACQk0IgUKACgDAAAA.Zekodian:BAAALgADCgcJDQAAAA==.Zentner:BAABLgAECn8uAAMQAAkJXx8vCwCfAgAQAAkJXx8vCwCfAgAgAAQJPAodJAB8AAAAAA==.Zeropistol:BAABLgAECn8aAAIUAAgJNQMrzAD0AAAUAAgJNQMrzAD0AAAAAA==.Zexrous:BAAALgADCgEJAQAAAA==.',
Zh='Zhas:BAABLgAECn8VAAIGAAcJGxWAKwBoAQAGAAcJGxWAKwBoAQAAAA==.',
Zu='Zuro:BAABLgAECn8cAAMbAAkJFQ0LWACXAQAbAAkJFQ0LWACXAQAaAAEJCgHPmQAaAAAAAA==.',
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
