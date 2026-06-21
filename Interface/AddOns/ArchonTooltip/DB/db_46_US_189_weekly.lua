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
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Ablestract:BAAALgADCggJCQAAAA==.',
Ac='Acid:BAAALgAECggJEQAAAA==.',
Ad='Adam:BAAALgAFFAEJAgABLgAFFAEJBQABAB4mAA==.Adreane:BAAALgAECgMJBAAAAA==.',
Af='Aftrlyfe:BAAALgAECgkJCQAAAA==.',
Ai='Aiyana:BAAALgADCgkJEQAAAA==.',
Ak='Akamma:BAAALgAECgcJDgAAAA==.Akarimos:BAAALgADCgMJAwAAAA==.',
Al='Alealle:BAAALgADCgMJAwAAAA==.Algeriono:BAAALgAECgMJAwAAAA==.Aliluna:BAAALgAECgYJEAAAAA==.Alirain:BAAALgAFFAEJAQAAAA==.Alispere:BAAALgADCgUJBQAAAA==.Aliwings:BAAALgAECgQJCQAAAA==.Alizaranna:BAAALgADCgEJAQABLgAECgYJGAACAOkVAA==.',
Am='Amarokk:BAABLgAECn8jAAIDAAgJwAiZJwBiAQADAAgJwAiZJwBiAQAAAA==.Ameliae:BAAALgAECgEJAQAAAA==.',
An='Ancestor:BAABLgAECn8bAAIEAAcJjxPDIQCHAQAEAAcJjxPDIQCHAQAAAA==.Anish:BAAALgAECgEJAQAAAA==.',
Aq='Aqurore:BAAALgADCgYJBgAAAA==.',
Ar='Archaia:BAAALgAECgUJCQAAAA==.Argorok:BAAALgAFFAEJAQAAAA==.Aryi:BAABLgAECn8UAAQFAAkJCgUzSADlAAAFAAgJMwMzSADlAAAGAAMJZgm5WAB3AAACAAIJvQRNfQBDAAAAAA==.',
As='Askim:BAAALgADCgcJBwAAAA==.Assyla:BAAALgAECgEJAQAAAA==.Astraeos:BAABLgAFFH8HAAIHAAMJKx6cZgD5AAAHAAMJKx6cZgD5AAAAAA==.',
Au='Auv:BAACLgAFFH8QAAMHAAQJESaEBwCtAQAHAAQJESaEBwCtAQAIAAEJlQBjGwA6AAAuAAQKfxQAAwgABwmJJkMTALEBAAcABQkZJl9MAOMBAAgABAkgJkMTALEBAAEuAAUUBQkPAAkADCQA.',
Av='Avarii:BAAALgAECgEJAgAAAA==.',
Aw='Awekeha:BAAALgADCgIJAgAAAA==.',
Ax='Axël:BAAALgAFFAEJAQABLgAFFAMJBgAKAKsaAA==.',
Ay='Aylranoa:BAAALgADCgkJCQAAAA==.',
Az='Azimondius:BAACLgAFFH8XAAILAAUJCRobJQA8AQALAAUJCRobJQA8AQAuAAQKfzoAAgsACQlyIYgFAAcDAAsACQlyIYgFAAcDAAAA.Azmora:BAAALgAECgcJDwAAAA==.Azzix:BAAALgADCgQJBQAAAA==.',
['Aí']='Aímee:BAAALgAECgEJAgAAAA==.',
Ba='Baddragons:BAAALgADCgYJBgAAAA==.Bandit:BAAALgAECgEJAQAAAA==.Bastis:BAAALgAECgEJBAABLgAFFAQJFAAMANAmAA==.Batreaux:BAAALgAFFAEJAgAAAA==.',
Be='Beaman:BAAALgADCgEJAQAAAA==.Bearkake:BAAALgAECgMJBgAAAA==.Bellgrande:BAAALgADCgYJBgAAAA==.Belthora:BAAALgAECgYJCAAAAA==.Bepallylol:BAACLgAFFH8OAAINAAUJ2hM4IgB/AQANAAUJ2hM4IgB/AQAuAAQKfxkAAg0ACAlyH7EtAGwCAA0ACAlyH7EtAGwCAAAA.',
Bi='Bigkeith:BAAALgADCgEJAQAAAA==.Biraj:BAAALgADCggJEAABLgAECgcJLQANAHYIAA==.',
Bl='Blaqichan:BAAALgADCgEJAwABLgADCgQJBQAOAAAAAA==.Blight:BAAALgADCgcJBQAAAA==.Bloodybecky:BAAALgAECgQJBQAAAA==.',
Bo='Boahancawk:BAAALgADCgkJCQAAAA==.',
Br='Brakiyamis:BAAALgAECgEJAgAAAA==.Brewmastah:BAAALgAECgYJDAABLgAECgUJBwAOAAAAAA==.Briarynth:BAAALgAECgEJAQAAAA==.Browntotem:BAAALgADCgUJCAAAAA==.',
Bu='Bubblecheeks:BAAALgAECgQJBQAAAA==.Bubblehëarth:BAAALgAECgYJDwAAAA==.Bubby:BAABLgAECn8WAAIHAAcJPx2OQQAIAgAHAAcJPx2OQQAIAgAAAA==.Bucklebunnie:BAAALgADCgEJAQABLgAFFAUJEQAPAFQYAA==.Bulgestomper:BAAALgAECgcJDQAAAA==.Bullzaye:BAAALgAECgQJBAAAAA==.Burbuja:BAABLgAECn8XAAIGAAgJtA+dMgA/AQAGAAgJtA+dMgA/AQAAAA==.',
Ca='Cadfile:BAAALgAECgQJBgAAAA==.Calimari:BAAALgAECgMJAwAAAA==.Careco:BAAALgADCgYJBgAAAA==.Carpetcrumbs:BAAALgAECgUJBQAAAA==.Catnsevrmeme:BAAALgAECgQJBwAAAA==.',
Ce='Cecilio:BAAALgAECgMJAwAAAA==.Cel:BAAALgAECgEJAgAAAA==.Celzara:BAAALgAECgEJAQAAAA==.Cernunnös:BAAALgADCgUJBQAAAA==.Cetraa:BAACLgAFFH8GAAMQAAMJngsMNQCrAAAQAAMJngsMNQCrAAARAAEJtRgKagBHAAAuAAQKfysAAxAACQm7GvENAHsCABAACQm7GvENAHsCABEAAQkTDmnYACwAAAAA.',
Ch='Chastise:BAAALgAECgkJDwAAAA==.Chewÿ:BAAALgAECgcJBAAAAA==.Chii:BAAALgADCgEJAQAAAA==.Chocobro:BAAALgAECgYJCQAAAA==.Chäös:BAAALgAECgUJBQAAAA==.',
Cl='Clingy:BAAALgAECgQJBgAAAA==.',
Co='Cobble:BAACLgAFFH8GAAISAAMJvQoGOgCnAAASAAMJvQoGOgCnAAAuAAQKfx0AAhIACAkTGNgeAOsBABIACAkTGNgeAOsBAAAA.Colhap:BAABLgAECn8ZAAICAAcJJhzLIQDJAQACAAcJJhzLIQDJAQAAAA==.Conjure:BAACLgAFFH8IAAMTAAMJWwnZCgDPAAATAAMJWwnZCgDPAAAHAAEJ8gJj0gA4AAAuAAQKfzQAAwgACAlOF2gIAMcBAAgABwm5GWgIAMcBAAcACAmZDauEADABAAAA.Corbina:BAABLgAECn8jAAIUAAgJ6iJ2NQCeAgAUAAgJ6iJ2NQCeAgAAAA==.Cousinlarry:BAAALgADCgIJAgABLgADCgQJBQAOAAAAAA==.',
Cr='Cramlutin:BAAALgADCgUJBQAAAA==.Cru:BAAALgAECgkJDgAAAA==.Crui:BAAALgADCgcJBwAAAA==.',
Cu='Culligan:BAACLgAFFH8KAAIUAAMJ+xc5dwDsAAAUAAMJ+xc5dwDsAAAuAAQKf3wAAhQACQnfHlgXAM0CABQACQnfHlgXAM0CAAAA.Cuttingcrew:BAAALgADCggJCAAAAA==.',
Cy='Cyclones:BAAALgADCgYJBgABLgAECgUJBQAOAAAAAA==.Cygwin:BAABLgAECn88AAMMAAkJwBwlEQDGAgAMAAkJwBwlEQDGAgASAAMJZxEibgCfAAAAAA==.',
Da='Daarius:BAAALgADCgYJBgAAAA==.Darcfrost:BAAALgAECgEJAgAAAA==.Darcyonys:BAAALgAECgIJBQAAAA==.Dariao:BAAALgAECgIJAgABLgAECgkJLQAJAM8ZAA==.Darkironsham:BAAALgAFFAEJAQAAAA==.Darklon:BAAALgAECgkJEwAAAA==.Darknescomez:BAAALgAECgQJCAABLgAECgkJMQASAOYYAA==.Darkpun:BAAALgADCgcJCQAAAA==.Darîus:BAAALgAECgMJAwAAAA==.Dat:BAAALgAECgcJAQABLgAFFAIJBwAUAPkYAA==.Datmage:BAACLgAFFH8HAAIUAAIJ+RjSnACSAAAUAAIJ+RjSnACSAAAuAAQKfxkAAhQABwl4H3FeAB8CABQABwl4H3FeAB8CAAAA.',
De='Deathshockz:BAAALgAECgQJBQABLgAECgUJBQAOAAAAAA==.Deedeet:BAAALgAECgkJBQAAAA==.Deku:BAAALgAFFAEJAwAAAA==.Demunzz:BAAALgADCgUJCQAAAA==.Deriah:BAABLgAECn8pAAINAAgJoBQ3UADxAQANAAgJoBQ3UADxAQAAAA==.Derpatron:BAABLgAECn8UAAMNAAkJzgj4jgBUAQANAAkJzgj4jgBUAQAVAAEJuQ6gkwA3AAAAAA==.Destruction:BAABLgAECn8XAAIWAAkJfQVSLQDzAAAWAAkJfQVSLQDzAAAAAA==.Devo:BAECLgAFFH8LAAIXAAQJORcHCAApAQAXAAQJORcHCAApAQAuAAQKfxQAAhcACQm9H14DAOACABcACQm9H14DAOACAAAA.',
Di='Diabelo:BAAALgAECgIJAgAAAA==.Digoxin:BAAALgAECgEJAgAAAA==.Dingers:BAAALgAECggJDwABLgAECgkJEgAOAAAAAA==.Disgusti:BAAALgAECggJEwAAAA==.Divinespark:BAABLgAECn8jAAIGAAgJMRXULACTAQAGAAgJMRXULACTAQAAAA==.',
Dk='Dkins:BAAALgAECgIJAgAAAA==.',
Do='Dogeform:BAAALgADCgEJAQAAAA==.Doinkbigs:BAABLgAECn8iAAIHAAgJXQ0mcABaAQAHAAgJXQ0mcABaAQAAAA==.Doomo:BAAALgADCgYJBgABLgABCgQJBAAOAAAAAA==.Dotsfired:BAAALgADCgQJBAAAAA==.Dotñtrot:BAAALgAFFAIJAgABLgAFFAMJCwAMADUZAA==.',
Dr='Draeneisham:BAAALgAFFAEJAQAAAA==.Draethno:BAAALgAECgQJBAAAAA==.Dredd:BAAALgAECgQJDQAAAA==.Drewsilla:BAAALgAECgYJDwAAAA==.Druidrose:BAAALgAECgMJAwAAAA==.Druidtrix:BAAALgADCgYJCwAAAA==.Drylogic:BAABLgAECn8yAAIRAAkJAx+WCwAGAwARAAkJAx+WCwAGAwAAAA==.',
Du='Duckworth:BAAALgAECgEJAQAAAA==.Dulcey:BAAALgAECgYJCAABLgAFFAMJBgAQAJ4LAA==.Duruk:BAABLgAECn8hAAIHAAgJCh5GJQBJAgAHAAgJCh5GJQBJAgAAAA==.Dustbroom:BAAALgAECgEJAQAAAA==.',
['Dà']='Dàvë:BAAALgAECgEJAQABLgAECgIJBAAOAAAAAA==.',
Ea='Eap:BAAALgAECgcJDwAAAA==.Eazye:BAACLgAFFH8UAAICAAQJxxE5HgAAAQACAAQJxxE5HgAAAQAuAAQKfzcAAgIACQlXHIEPAGMCAAIACQlXHIEPAGMCAAAA.',
Eb='Ebone:BAAALgADCgMJAQAAAA==.',
Ec='Ectoscourge:BAAALgADCgcJBgAAAA==.',
Ed='Edgeffs:BAABLgAECn8fAAMYAAkJlwowNgBvAQAYAAkJZAkwNgBvAQAZAAUJZQj5JADFAAAAAA==.',
Ek='Eklipse:BAAALgADCgMJAwABLgABCgQJBAAOAAAAAA==.',
El='Elentiya:BAABLgAECn8kAAMGAAkJvxyYDgB1AgAGAAkJvxyYDgB1AgAFAAEJegd7WgAtAAAAAA==.Elphzz:BAABLgAECn8YAAIEAAgJ+BL1HgADAgAEAAgJ+BL1HgADAgAAAA==.',
Em='Emoose:BAAALgAECgEJAQAAAA==.',
Er='Eriius:BAABLgAECn8UAAINAAgJNRJUtgAWAQANAAgJNRJUtgAWAQAAAA==.',
Ev='Evestar:BAAALgADCgEJAQAAAA==.',
Ez='Ez:BAACLgAFFH8VAAMaAAcJWBVSFQAaAQAaAAYJZhBSFQAaAQAbAAIJuBksgQCXAAAuAAQKfyoAAxoACAn0H6UYAGcCABoACAn0H6UYAGcCABsAAgmXDfcdAT4AAAAA.Ezarath:BAABLgAECn8vAAIcAAgJdwxqCwBfAQAcAAgJdwxqCwBfAQAAAA==.',
Fa='Fadedaf:BAABLgAECn8UAAIJAAYJjQ3juAC5AAAJAAYJjQ3juAC5AAAAAA==.',
Fe='Felenn:BAAALgADCgYJDQABLgAECgcJLQANAHYIAA==.Felorc:BAAALgAECgYJCwAAAA==.Fentun:BAAALgAFFAEJAQAAAA==.Feyla:BAAALgAECgUJCQAAAA==.',
Fi='Finnikey:BAAALgAECgIJBAAAAA==.Firstone:BAAALgADCgYJBgAAAA==.',
Fo='Foofs:BAAALgADCgUJBQAAAA==.Foulmuffn:BAAALgADCgYJCQAAAA==.Foulplay:BAAALgADCgMJAwAAAA==.Fovos:BAAALgAECgEJAQAAAA==.',
Fr='Freakonleash:BAABLgAECn8YAAIYAAgJ/Rn7GQB8AgAYAAgJ/Rn7GQB8AgAAAA==.Free:BAAALgAECgUJBQAAAA==.Frimbooze:BAAALgAECgYJBwAAAA==.',
Fu='Fuegodotz:BAAALgADCgUJBQABLgAECgkJJAAKALEcAA==.Fumonkchu:BAAALgADCgIJAQAAAA==.',
['Fé']='Féarôshima:BAAALgAECgEJAQABLgAECgkJMQASAOYYAA==.',
Ga='Ganjåfarian:BAAALgAECgIJAgAAAA==.',
Gd='Gdayum:BAAALgADCgEJAQAAAA==.',
Ge='Gekatta:BAAALgAECgYJEAAAAA==.Gelektrael:BAABLgAECn8kAAMHAAkJuA3UewBBAQAHAAgJ0QrUewBBAQAIAAIJnBQnMgBWAAAAAA==.',
Gh='Ghostdk:BAAALgAFFAQJBAABLgAFFAYJHAANAKAiAA==.Ghostwarrior:BAAALgADCgMJAwABLgAFFAYJHAANAKAiAA==.Ghostzz:BAACLgAFFH8cAAINAAYJoCJ7GACsAQANAAYJoCJ7GACsAQAuAAQKf10AAw0ACQlIJksBAIUDAA0ACQlIJksBAIUDAB0ABQkSHhcbAD8BAAAA.',
Gl='Glarb:BAAALgAECgIJAwAAAA==.Glzygldiator:BAACLgAFFH8OAAIKAAMJ1BhXLgDhAAAKAAMJ1BhXLgDhAAAuAAQKfykAAgoACAkWH908AA4CAAoACAkWH908AA4CAAAA.',
Gn='Gnomelock:BAAALgAFFAEJAQABLgAFFAEJBQABAB4mAA==.',
Go='Gobblin:BAAALgAECgUJDQAAAA==.Gotbandaids:BAAALgAECgEJAQAAAA==.Govegan:BAAALgADCgQJBwAAAA==.',
Gr='Graavey:BAAALgAECgcJAwABLgAFFAMJCwAMADUZAA==.Greyhairs:BAABLgAECn8VAAIbAAcJqQ/UfwA/AQAbAAcJqQ/UfwA/AQAAAA==.Grifter:BAAALgAECgEJAQAAAA==.Grimthor:BAAALgAECgcJBwAAAA==.Grippy:BAACLgAFFH8HAAIJAAMJRwZRcQCmAAAJAAMJRwZRcQCmAAAuAAQKfyYAAgkACAl/HUoiAIQCAAkACAl/HUoiAIQCAAAA.Gromgar:BAAALgAECgMJAwAAAA==.Gromit:BAACLgAFFH8hAAIGAAgJ+Rp7AgBzAgAGAAgJ+Rp7AgBzAgAuAAQKfyQAAwYACQlNIZMDACEDAAYACQlNIZMDACEDAAUAAgmnEUdKAG0AAAAA.Grym:BAAALgADCgcJDgAAAA==.',
Gu='Gustófwind:BAACLgAFFH8IAAIBAAQJJSFzCgB4AQABAAQJJSFzCgB4AQAuAAQKfyAAAwEACQnKIZkEAA0DAAEACQnKIZkEAA0DAB4AAwnMEmR2ALgAAAAA.',
Ha='Hackey:BAAALgAECgkJCgAAAA==.Haldire:BAABLgAECn8VAAIdAAcJxh0mDAACAgAdAAcJxh0mDAACAgAAAA==.Harrypotture:BAAALgADCgEJAQAAAA==.Haschel:BAABLgAECn8wAAMZAAkJriCKBADRAgAZAAkJriCKBADRAgAfAAMJ9Q6JOACFAAAAAA==.Haunterx:BAAALgAECgQJAQAAAA==.',
He='Hexerfender:BAAALgAECgUJBQAAAA==.Heypal:BAAALgADCgUJCwAAAA==.',
Ho='Hofarmer:BAABLgAECn8YAAIgAAkJUhMeFgCjAQAgAAkJUhMeFgCjAQAAAA==.Holychris:BAAALgADCgEJAQAAAA==.Holycöw:BAAALgADCgkJCQAAAA==.Holywood:BAAALgAECgYJBwAAAA==.',
Hu='Hurtak:BAAALgAECgcJDgAAAA==.',
Hy='Hycisan:BAABLgAECn8yAAIVAAkJMRwUCwDcAgAVAAkJMRwUCwDcAgAAAA==.Hysteria:BAAALgAECgIJAgAAAA==.',
Ic='Icanlust:BAAALgADCgIJAgAAAA==.Icant:BAAALgADCgEJAgABLgADCgQJBQAOAAAAAA==.Icon:BAAALgAECgQJBQAAAA==.Icydoodad:BAAALgAECgIJBAAAAA==.',
Ie='Iesous:BAAALgAECgEJAQAAAA==.',
Ig='Ignis:BAAALgADCgMJAwAAAA==.',
Io='Iocomotive:BAAALgAFFAEJAQAAAA==.',
Is='Iskaru:BAAALgAECgEJAQABLgAECgYJDwAOAAAAAA==.',
Ja='Jacklawin:BAAALgAECgMJAwAAAA==.Jasmyn:BAAALgADCgQJBAAAAA==.',
Jb='Jbirdlol:BAAALgADCgUJBAAAAA==.',
Je='Jenziserrin:BAAALgAECgEJAgAAAA==.Jesse:BAAALgAECgYJEAABLgAFFAIJBwAVAHYXAA==.Jetmage:BAABLgAECn8gAAIhAAkJRyToAADgAgAhAAkJRyToAADgAgAAAA==.',
Ji='Jire:BAAALgAECgUJDQAAAA==.Jittkal:BAAALgADCgMJAwAAAA==.',
Jo='Josh:BAAALgADCgMJAgAAAA==.',
Jp='Jpally:BAABLgAECn8XAAMVAAcJ2AbKSwAMAQAVAAcJ2AbKSwAMAQANAAUJSwRA7AC3AAAAAA==.',
Ju='Jurassthicc:BAAALgAECgEJBQAAAA==.',
Jw='Jwøww:BAAALgADCgEJAgABLgADCgQJBQAOAAAAAA==.',
Ka='Kafka:BAAALgADCgcJBgAAAA==.Kanastra:BAABLgAECn8dAAIJAAkJrBsuHQBlAgAJAAkJrBsuHQBlAgABLgAFFAUJFwALAAkaAA==.Karraa:BAABLgAECn8oAAIfAAkJKhgMEQDaAQAfAAkJKhgMEQDaAQAAAA==.Katil:BAAALgAECgEJAQAAAA==.Kaylib:BAABLgAECn8sAAIhAAkJJxABBADFAQAhAAkJJxABBADFAQAAAA==.',
Ke='Kea:BAAALgADCgIJAgABLgAECgUJCQAOAAAAAA==.Kerze:BAABLgAECn8UAAIfAAYJlhHxKQDlAAAfAAYJlhHxKQDlAAAAAA==.Kesatrix:BAABLgAECn8qAAIeAAkJnBMPIQAUAgAeAAkJnBMPIQAUAgAAAA==.Kesi:BAAALgADCgQJBAAAAA==.',
Kh='Khai:BAAALgAECgQJBAAAAA==.Khazador:BAAALgADCgkJEgABLgAECgkJGwAHALkXAA==.Khaztharion:BAAALgADCggJCAABLgAECgkJGwAHALkXAA==.Khendrick:BAABLgAECn8aAAINAAkJ1w8sXwCzAQANAAkJ1w8sXwCzAQAAAA==.',
Ki='Kilerwolf:BAAALgADCgIJAgAAAA==.Kimsmage:BAAALgADCgYJBgAAAA==.Kirdo:BAAALgAECgEJAQAAAA==.Kith:BAAALgAECgEJAgAAAA==.Kitridge:BAAALgAECgcJDQAAAA==.Kittykatt:BAACLgAFFH8IAAIQAAMJ1RKWAwDKAAAQAAMJ1RKWAwDKAAAuAAQKfzsAAhAACQkMIOUGAOgCABAACQkMIOUGAOgCAAAA.',
Ko='Kolchak:BAAALgADCgYJDQAAAA==.Korel:BAAALgAECgcJDAAAAA==.',
Kr='Kraggo:BAAALgAFFAEJAQAAAA==.Krimzin:BAACLgAFFH8YAAINAAUJzSFwKQBmAQANAAUJzSFwKQBmAQAuAAQKfxwAAw0ACQlnIc4XANoCAA0ACAkOIc4XANoCABUABQlTD3thALAAAAAA.',
Ku='Kumala:BAAALgAECgMJBQAAAA==.Kungao:BAAALgAECgUJBQAAAA==.',
Ky='Kylea:BAAALgAECgQJBAAAAA==.',
La='Laffiel:BAAALgADCgQJBAAAAA==.Landoh:BAABLgAECn8kAAIUAAkJ+CGXGADGAgAUAAkJ+CGXGADGAgAAAA==.Larg:BAAALgAECgEJAQAAAA==.Larsen:BAABLgAECn8kAAISAAkJZR6RFABGAgASAAkJZR6RFABGAgAAAA==.',
Le='Leap:BAABLgAECn8jAAMXAAkJYBp3DQDeAQAXAAcJIxt3DQDeAQAgAAcJVxaoIwAzAQAAAA==.Lefthorn:BAAALgADCgIJAgAAAA==.Lenneth:BAAALgAECgIJAgAAAA==.',
Li='Lightofdawn:BAAALgAECgMJAwAAAA==.Lightstyle:BAAALgADCgMJAwAAAA==.Lilow:BAABLgAECn85AAICAAkJIhKGHwDJAQACAAkJIhKGHwDJAQAAAA==.',
Ll='Llarker:BAABLgAECn8tAAQNAAcJdggdwwAEAQANAAcJdggdwwAEAQAdAAYJHAOyOQB3AAAVAAIJvQEakQAtAAAAAA==.',
Lo='Lockendron:BAAALgADCgQJBAAAAA==.Locketharion:BAAALgADCgQJBAAAAA==.Lockpebbles:BAAALgADCgMJAwAAAA==.Lokomachina:BAABLgAECn8UAAIbAAcJLyETHwBLAgAbAAcJLyETHwBLAgAAAA==.Lonesdove:BAAALgADCgEJAQAAAA==.',
Lu='Lucyna:BAAALgAECgMJAwABLgAECgkJJAAiAPUiAA==.Luminia:BAAALgAECgUJCAAAAA==.Lunacy:BAAALgAECgQJBgAAAA==.',
Ly='Lynngosa:BAABLgAECn8nAAMjAAgJJRI2EQC3AQAjAAgJJRI2EQC3AQALAAcJHAi9UQDoAAAAAA==.Lyrana:BAAALgADCgQJBAAAAA==.Lyrasa:BAAALgADCgQJBAAAAA==.',
Ma='Maelidrael:BAAALgAECgMJAwABLgAFFAIJBQAUADwRAA==.Magiks:BAAALgAFFAEJAQAAAA==.Magisterium:BAABLgAECn8tAAMGAAgJ4AfxPgD0AAAGAAgJ4AfxPgD0AAACAAEJ/QE7nAAXAAAAAA==.Malady:BAABLgAECn8sAAICAAkJwCA+CQC7AgACAAkJwCA+CQC7AgAAAA==.Malakyde:BAAALgADCgMJAwAAAA==.Malt:BAABLgAECn8ZAAIJAAgJvCB5OgDdAQAJAAgJvCB5OgDdAQAAAA==.Malthorial:BAAALgADCgEJAQAAAA==.Mario:BAABLgAFFH8FAAIBAAEJHiYYNwBrAAABAAEJHiYYNwBrAAAAAA==.Mattenom:BAAALgADCgYJCAAAAA==.Maulware:BAAALgADCgEJAQAAAA==.',
Mb='Mbrodh:BAAALgAECgQJBAAAAA==.Mbrosmites:BAAALgAECgcJCwAAAA==.',
Md='Mdeag:BAABLgAECn8WAAMYAAUJ9hapAgDAAAAYAAQJ9RapAgDAAAAZAAUJDA58RwCtAAAAAA==.',
Me='Mefistofeles:BAACLgAFFH8QAAIEAAMJFBR1JwDsAAAEAAMJFBR1JwDsAAAuAAQKfyMAAgQACAlmGJ4XAN4BAAQACAlmGJ4XAN4BAAAA.Meingaree:BAABLgAECn8aAAIIAAgJjxjkBgDuAQAIAAgJjxjkBgDuAQAAAA==.Merlinus:BAABLgAECn8lAAINAAcJ4gq0lABTAQANAAcJ4gq0lABTAQAAAA==.Merton:BAAALgADCggJDAAAAA==.',
Mi='Mightyguzz:BAABLgAECn9AAAIfAAkJmhPcEQDMAQAfAAkJmhPcEQDMAQAAAA==.Miku:BAAALgAECgMJBAAAAA==.Mitchelle:BAAALgAECgMJBQAAAA==.',
Mo='Moirayne:BAAALgAECgYJBQAAAA==.Moomkin:BAABLgAECn8oAAIQAAgJgwx/NwA3AQAQAAgJgwx/NwA3AQAAAA==.',
My='Mythicblade:BAAALgADCgEJAQAAAA==.',
['Mø']='Møønchild:BAAALgAECgkJDQAAAA==.',
Na='Nai:BAAALgAECgQJDAAAAA==.Nanaish:BAAALgAECgEJAgAAAA==.Narpul:BAABLgAECn8rAAIdAAkJBB7eBACpAgAdAAkJBB7eBACpAgAAAA==.Natë:BAACLgAFFH8TAAIfAAMJOhgVAgDVAAAfAAMJOhgVAgDVAAAuAAQKfzAAAh8ACQkvIWUDACMDAB8ACQkvIWUDACMDAAAA.Nazend:BAAALgADCgQJBwAAAA==.',
Ne='Necrotalon:BAAALgAECgcJEQAAAA==.Nelosi:BAAALgAECgMJCAAAAA==.Neondh:BAACLgAFFH8VAAIJAAQJPSTAJQCWAQAJAAQJPSTAJQCWAQAuAAQKfzQAAgkACQmIJA4NABcDAAkACQmIJA4NABcDAAAA.Nerzhùl:BAABLgAECn8lAAISAAkJGglZPABEAQASAAkJGglZPABEAQAAAA==.',
Nh='Nharuna:BAACLgAFFH8KAAIbAAMJpQfnBwDIAAAbAAMJpQfnBwDIAAAuAAQKfzgAAhsACQnbEyM2AAUCABsACQnbEyM2AAUCAAAA.',
Ni='Nickolaos:BAAALgAECgEJAQAAAA==.Nieloriel:BAABLgAECn86AAMVAAkJkBKTKwC0AQAVAAkJkBKTKwC0AQANAAgJmgrUlwBFAQAAAA==.Nightwishing:BAAALgAECgQJBAAAAA==.Niupiadps:BAAALgAECgIJAgAAAA==.Niykee:BAABLgAECn8kAAQiAAkJ9SI6AwByAgAiAAYJhSQ6AwByAgAEAAcJPiKmHAAaAgAkAAcJCx5mBgARAgAAAA==.',
No='Noboundss:BAABLgAECn8aAAMJAAgJJQ6GcgA9AQAJAAcJSg+GcgA9AQAPAAMJPwjLXgBQAAAAAA==.Nobóunds:BAAALgAECgkJEAAAAA==.Nomnoms:BAAALgAECgYJEgAAAA==.Nomoreheals:BAAALgAECgYJDQAAAA==.Notkarl:BAAALgAECgIJAwAAAA==.Nowimpissed:BAACLgAFFH8PAAMDAAMJ9SGtGAANAQADAAMJ9SGtGAANAQAbAAEJvyDWHgBkAAAuAAQKfxcABAMABgnEHpgTAAkCAAMABgnEHpgTAAkCABsABAkPFsp5APoAABoABAnmDzBbANcAAAAA.Noztra:BAACLgAFFH8UAAIUAAQJKAkdCgDRAAAUAAQJKAkdCgDRAAAuAAQKfywAAhQACAnjF+pLAPcBABQACAnjF+pLAPcBAAAA.',
Nu='Nuker:BAAALgAECgEJAQAAAA==.',
Ny='Nysrogh:BAAALgAECgUJEgABLgAFFAQJFAARADQXAA==.',
Ob='Obsideon:BAAALgAECggJEwAAAA==.',
Oc='Octoknight:BAAALgADCgEJAQAAAA==.',
Oh='Ohgr:BAABLgAECn8UAAIYAAYJoxw+KwCoAQAYAAYJoxw+KwCoAQAAAA==.Ohshifty:BAABLgAECn80AAMQAAkJ0xAmJQCiAQAQAAkJ0xAmJQCiAQARAAQJbASNowBqAAAAAA==.',
Ol='Olan:BAAALgAECgYJDAAAAA==.Olie:BAABLgAECn8bAAIbAAgJ9wnbdgBSAQAbAAgJ9wnbdgBSAQAAAA==.',
Or='Orbsicles:BAABLgAECn8oAAQlAAkJ/SHVAQD9AgAlAAkJ/SHVAQD9AgAPAAEJKBqPYABMAAAJAAEJtgvqGgEvAAAAAA==.',
Ou='Ouragan:BAAALgAECgUJCAAAAA==.',
Pa='Paedrig:BAAALgADCgIJAgAAAA==.Papitomyrey:BAABLgAECn8gAAMYAAkJKCRdBwDpAgAYAAkJKCRdBwDpAgAZAAUJYh06OADkAAABLgAFFAMJBQAeAMATAA==.Paramedic:BAAALgADCgIJAgAAAA==.Passtheflask:BAABLgAECn8eAAIHAAcJGgcNrQDpAAAHAAcJGgcNrQDpAAAAAA==.',
Pe='Perdition:BAAALgAECgEJAgAAAA==.Pestílence:BAACLgAFFH8KAAIKAAMJsxzxjgDtAAAKAAMJsxzxjgDtAAAuAAQKfz8AAwoACQk1Iq8YALICAAoACQk1Iq8YALICABYAAQnEEZBHACoAAAAA.',
Ph='Phaesphoros:BAABLgAECn8gAAIMAAkJXxDqSwCAAQAMAAkJXxDqSwCAAQAAAA==.Phenor:BAAALgAECgQJBAAAAA==.',
Po='Poe:BAAALgADCgYJBgABLgAECgcJFQAUAOEXAA==.Powpow:BAABLgAECn83AAIEAAkJ2Br+CACVAgAEAAkJ2Br+CACVAgAAAA==.',
Pr='Prejudice:BAABLgAECn8dAAIVAAkJnxTqHQATAgAVAAkJnxTqHQATAgAAAA==.Primévil:BAAALgAECgYJBgABLgAECgkJMQASAOYYAA==.Priscilla:BAAALgAECgEJAgAAAA==.Prowlcow:BAABLgAECn8yAAMRAAkJdRd8HABjAgARAAkJdRd8HABjAgAXAAIJDxYtNgCEAAAAAA==.',
Ps='Psychosis:BAABLgAECn8uAAIKAAkJ5B1AJwBlAgAKAAkJ5B1AJwBlAgAAAA==.',
Pu='Putrescence:BAAALgADCgEJAQAAAA==.',
['Pû']='Pûff:BAAALgAECgcJDwAAAA==.',
Qm='Qmpel:BAAALgADCgMJAwAAAA==.',
Ra='Raiiz:BAACLgAFFH8IAAIUAAMJBBBmLAAFAQAUAAMJBBBmLAAFAQAuAAQKfyYAAhQACAkhHI4/AHoCABQACAkhHI4/AHoCAAAA.Rainhoof:BAABLgAECn8kAAMXAAkJsRgGDAD5AQAXAAgJOhkGDAD5AQARAAYJlweAhwDHAAAAAA==.Ralneth:BAACLgAFFH8ZAAMLAAgJphDcEAD6AQALAAcJgRDcEAD6AQAcAAQJXRToAwAOAQAuAAQKfyQAAxwACAmrIFADAOsCABwACAmfH1ADAOsCAAsABgnYG0IYAA8CAAAA.Ranare:BAAALgAECgYJBgAAAA==.Randomtask:BAAALgADCgUJBgAAAA==.Rapala:BAABLgAECn8mAAIHAAkJ+hz2GwB9AgAHAAkJ+hz2GwB9AgAAAA==.Rapalaa:BAAALgAECgcJDwABLgAECgkJJgAHAPocAA==.Raspútin:BAABLgAECn8zAAMmAAkJqBl8DgBSAgAmAAkJqBl8DgBSAgABAAQJ8AfVVQC5AAAAAA==.Rawkfice:BAAALgADCggJFAAAAA==.',
Re='Redlefevoker:BAAALgADCgYJCQAAAA==.Renfield:BAAALgADCgYJCAAAAA==.Revok:BAAALgAECgcJCwAAAA==.Revoker:BAAALgADCgYJCAAAAA==.',
Ri='Riordan:BAAALgAFFAEJAgAAAA==.Rivvetear:BAAALgADCgYJBgAAAA==.',
Rj='Rjolz:BAACLgAFFH8OAAIKAAQJZiBuOACLAQAKAAQJZiBuOACLAQAuAAQKfzgAAgoACQn7JQAEAGIDAAoACQn7JQAEAGIDAAAA.',
Ro='Roflchopr:BAAALgAECgcJDgAAAA==.Roguish:BAAALgAECgEJAQAAAA==.Rootzi:BAAALgAECgIJAwABLgAECgkJJAAKALEcAA==.Rootzidk:BAABLgAECn8kAAIKAAkJsRxJNQAqAgAKAAkJsRxJNQAqAgAAAA==.Roshaka:BAAALgAECgUJCAAAAA==.',
Ru='Rucks:BAABLgAECn8jAAMBAAkJ1BrzGQDhAQABAAkJIRPzGQDhAQAmAAYJzBrULQCiAQAAAA==.',
Ry='Ryzze:BAAALgADCgYJBgAAAA==.',
Sa='Saelem:BAAALgAECgYJBgAAAA==.Saigonbeer:BAAALgAECgMJAwAAAA==.Sandalfon:BAAALgAECgYJDwAAAA==.Sanleron:BAABLgAECn8WAAMdAAgJWCHGDQDpAQAdAAYJFiLGDQDpAQANAAUJtBompQAwAQAAAA==.Sarith:BAAALgAECgQJAQABLgAECgUJBQAOAAAAAA==.Saske:BAAALgADCgMJBwABLgAECgEJAQAOAAAAAA==.',
Sc='Scarab:BAAALgAECgYJBgAAAA==.Scargon:BAAALgAECgcJEAAAAA==.Schizandrol:BAAALgAECgQJBAAAAA==.',
Se='Selidori:BAAALgADCgYJBgAAAA==.Seralicht:BAACLgAFFH8RAAIGAAYJLxU9CwCXAQAGAAYJLxU9CwCXAQAuAAQKfyIAAwYACAmGHhwQAGUCAAYACAmGHhwQAGUCAAIAAQmKCxyIADEAAAAA.',
Sh='Shadowclawz:BAAALgAECgQJBQAAAA==.Shaliri:BAAALgADCgEJBAAAAA==.Shamanata:BAAALgAECgEJAgAAAA==.Sharayse:BAABLgAECn8hAAIUAAkJWgxabQCgAQAUAAkJWgxabQCgAQAAAA==.Sharmee:BAAALgAECgkJEQAAAA==.Shennong:BAAALgAECgEJAQAAAA==.Shishy:BAAALgAECgMJBgAAAA==.Shockohôlic:BAABLgAECn8xAAQSAAkJ5hgkFQBAAgASAAkJ5hgkFQBAAgAMAAYJ/xB4bAAWAQAnAAEJoAphKwA4AAAAAA==.Shocky:BAAALgAECgcJCgAAAA==.Sháde:BAAALgADCgIJAgAAAA==.',
Sk='Skullkìng:BAABLgAECn8jAAIKAAkJuhSHTADdAQAKAAkJuhSHTADdAQAAAA==.',
Sl='Slingablade:BAACLgAFFH8LAAIJAAQJHQZ8XwDRAAAJAAQJHQZ8XwDRAAAuAAQKfyQAAwkACQliFoYuAA0CAAkACQlpFYYuAA0CAA8AAwlNEStDAKkAAAAA.',
Sm='Smashnskullz:BAAALgAECgQJBgABLgAECgUJBQAOAAAAAA==.',
Sn='Sniffsniff:BAACLgAFFH8JAAINAAMJxyXITQATAQANAAMJxyXITQATAQAuAAQKfykAAw0ACAlHJQYKAEEDAA0ACAlHJQYKAEEDABUAAQnBHiB/AE4AAAEuAAUUBAkUAAwA0CYA.',
So='Solvi:BAABLgAECn8fAAIRAAcJ9xf2VQA4AQARAAcJ9xf2VQA4AQAAAA==.Sonira:BAAALgADCgMJBQAAAA==.Soulbrand:BAABLgAECn8kAAICAAkJMwmCLwBhAQACAAkJMwmCLwBhAQAAAA==.Southpawclaw:BAAALgAECgEJAQABLgAECggJGAAnAPAfAA==.',
Sp='Spellz:BAABLgAECn8lAAICAAgJ0x9qDACKAgACAAgJ0x9qDACKAgAAAA==.Spoo:BAAALgAECgIJAwAAAA==.Spuggle:BAAALgAECgQJBAAAAA==.',
St='Stabathuh:BAAALgADCgYJBgAAAA==.Starman:BAAALgAECgkJCQAAAA==.Stoopiddk:BAAALgAECgEJAwABLgAECgIJBAAOAAAAAA==.Stoopidelf:BAAALgAECgEJAwABLgAECgIJBAAOAAAAAA==.Stoopidmonk:BAAALgAECgEJAQABLgAECgIJBAAOAAAAAA==.Stoopidrood:BAAALgAECgEJAQABLgAECgIJBAAOAAAAAA==.Stoopidtroll:BAAALgADCgUJBQABLgAECgIJBAAOAAAAAA==.Stoopidwarur:BAAALgAECgEJBAABLgAECgIJBAAOAAAAAA==.Stormclaw:BAABLgAECn8cAAIlAAkJiAwZDgBwAQAlAAkJiAwZDgBwAQAAAA==.Straeka:BAAALgAECgIJAgAAAA==.Stëvë:BAAALgAECgIJBAABLgAECgYJDwAOAAAAAA==.',
Su='Sufiya:BAABLgAECn8gAAIbAAkJLw9HUwCpAQAbAAkJLw9HUwCpAQAAAA==.Suhwoo:BAAALgAECgcJDwAAAA==.Sumig:BAAALgADCgEJBAAAAA==.',
Sw='Swiftarrows:BAAALgAECgEJAgAAAA==.',
Sy='Sylvershadow:BAABLgAECn8oAAIbAAkJMBUySQDGAQAbAAkJMBUySQDGAQAAAA==.Sym:BAAALgADCgcJCQAAAA==.',
Ta='Taintedsoulv:BAAALgADCgUJBgAAAA==.Taliri:BAAALgADCgEJAQABLgADCgQJBQAOAAAAAA==.Tandarilada:BAAALgAFFAEJBAAAAA==.Tanknspankn:BAAALgAECgkJDAAAAA==.Tankurface:BAAALgAECgEJAgAAAA==.',
Th='Thalvint:BAACLgAFFH8MAAIZAAQJSRs8FAA8AQAZAAQJSRs8FAA8AQAuAAQKfzMAAxkACQmHIxUDAAkDABkACQmHIxUDAAkDABgABgnVEiJbAEIBAAAA.Theblackhand:BAABLgAECn8dAAMSAAYJ1RXTSgAcAQASAAUJaxPTSgAcAQAMAAYJrQ+LdgD6AAAAAA==.Thefira:BAAALgADCgkJCQAAAA==.Thickdk:BAABLgAECn8aAAIKAAgJHRZTbgCtAQAKAAgJHRZTbgCtAQAAAA==.Thoriel:BAAALgAECgEJAgAAAA==.',
Ti='Timefall:BAAALgAECgkJDgAAAA==.Titanic:BAAALgAECgcJEAAAAA==.',
To='Tomcruise:BAAALgAECgkJEgAAAA==.Toshiro:BAAALgADCgcJBwAAAA==.Totemlyawsum:BAABLgAFFH8LAAISAAQJDg2PKgDrAAASAAQJDg2PKgDrAAAAAA==.Touch:BAAALgAECgEJAQAAAA==.Touchymcfeel:BAAALgADCgMJAwAAAA==.',
Tr='Trckr:BAAALgADCgIJAgAAAA==.Treeiage:BAAALgAECgUJCAAAAA==.Trooblu:BAAALgAECgYJEgAAAA==.',
Tw='Twotone:BAAALgAECgEJAQAAAA==.',
['Té']='Téz:BAABLgAECn8YAAICAAYJ6RX9MwBIAQACAAYJ6RX9MwBIAQAAAA==.',
['Tê']='Têzeret:BAAALgAECgEJAgAAAA==.',
Ul='Ulkthar:BAABLgAECn8wAAIYAAgJ2BPKKAAZAgAYAAgJ2BPKKAAZAgABLgAECgkJIQAUANYXAA==.Ultrauchuva:BAAALgAECgEJAQAAAA==.',
Un='Unholyhammer:BAAALgADCgIJAgABLgAECgUJBQAOAAAAAA==.',
Va='Vacunamatata:BAAALgAECgEJAQAAAA==.Vanarn:BAAALgADCgEJAQABLgADCgQJBQAOAAAAAA==.Vanlin:BAABLgAECn8kAAIRAAkJWh5PDwDaAgARAAkJWh5PDwDaAgAAAA==.',
Ve='Velirayvia:BAAALgAECgQJBQAAAA==.Vexxdr:BAACLgAFFH8JAAIRAAMJZAw8RwCZAAARAAMJZAw8RwCZAAAuAAQKfx8AAhEACAkcEtc5AL4BABEACAkcEtc5AL4BAAEuAAUUAwkKAAwANw4A.Vexxs:BAACLgAFFH8KAAIMAAMJNw57BgCkAAAMAAMJNw57BgCkAAAuAAQKfxsAAgwACQnIFaogAEsCAAwACQnIFaogAEsCAAAA.',
Vi='Virtey:BAAALgADCgUJBQAAAA==.Virtuous:BAAALgADCgYJBwAAAA==.',
Vl='Vladzy:BAAALgADCgcJAwAAAA==.',
Vo='Voidsuzu:BAAALgAECgMJAwABLgAECgkJNwAdALkUAA==.Vormedicus:BAAALgAECgcJEgABLgAECgkJMwAmAKgZAA==.',
Vu='Vulperas:BAABLgAECn89AAISAAkJdhDXKACoAQASAAkJdhDXKACoAQAAAA==.',
Vy='Vynastallan:BAABLgAECn8cAAMbAAcJhSOMIABCAgAbAAcJhSOMIABCAgAaAAEJehfShgA1AAAAAA==.Vyper:BAEBLgAECn8lAAILAAgJcxmIHwDcAQALAAgJcxmIHwDcAQABLgAFFAQJCwAXADkXAA==.',
Wa='Waroo:BAABLgAECn8iAAIQAAgJORL/JACjAQAQAAgJORL/JACjAQAAAA==.',
We='Wellcole:BAAALgADCgYJBgAAAA==.Wenden:BAAALgAFFAEJAwAAAA==.Wengo:BAAALgADCgkJCgAAAA==.',
Wi='Wilbert:BAAALgADCgEJAQAAAA==.Winniethepo:BAAALgAECgQJBAAAAA==.Witherflow:BAAALgAECgQJBQAAAA==.',
Wo='Woodey:BAAALgADCgcJCAAAAA==.',
Wu='Wulffric:BAABLgAECn8YAAIDAAgJ1xDjJQBuAQADAAgJ1xDjJQBuAQAAAA==.',
Xe='Xeo:BAAALgADCgMJAwAAAA==.',
Ya='Yachirú:BAABLgAECn83AAIdAAkJuRTDDgDXAQAdAAkJuRTDDgDXAQAAAA==.Yahkisoba:BAAALgAECgEJAQAAAA==.',
Ye='Yessir:BAAALgAECgEJAQABLgAECgkJGgABAA4XAA==.',
Yi='Yiang:BAABLgAECn8nAAIBAAkJ0R0ZCgCiAgABAAkJ0R0ZCgCiAgAAAA==.',
Yl='Ylndrysa:BAABLgAECn9DAAMRAAkJoBkcGQB9AgARAAkJoBkcGQB9AgAQAAMJoRj7UQDGAAAAAA==.',
Yt='Ytho:BAAALgADCgYJBgAAAA==.',
Za='Zalithar:BAABLgAECn8VAAIJAAgJZgUdmwDrAAAJAAgJZgUdmwDrAAAAAA==.',
Ze='Zedrock:BAACLgAFFH8FAAIUAAIJPBHfngCPAAAUAAIJPBHfngCPAAAuAAQKfz8AAhQACQk0ImEKACcDABQACQk0ImEKACcDAAAA.Zekodian:BAAALgADCgcJDQAAAA==.Zentner:BAABLgAECn8uAAMQAAkJXx9OCwCeAgAQAAkJXx9OCwCeAgAgAAQJPAodJAB8AAAAAA==.Zeropistol:BAABLgAECn8aAAIUAAgJNQPtzgDzAAAUAAgJNQPtzgDzAAAAAA==.Zexrous:BAAALgADCgEJAQAAAA==.',
Zh='Zhas:BAABLgAECn8WAAIGAAcJfhU/LABoAQAGAAcJfhU/LABoAQAAAA==.',
Zi='Ziminiar:BAAALgAECgEJAQAAAA==.',
Zu='Zuro:BAABLgAECn8cAAMbAAkJFQ29WQCXAQAbAAkJFQ29WQCXAQAaAAEJCgHPmQAaAAAAAA==.',
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
