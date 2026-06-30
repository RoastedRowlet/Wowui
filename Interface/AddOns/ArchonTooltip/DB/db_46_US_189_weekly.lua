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

local lookup = {'Monk-Windwalker','Priest-Holy','Hunter-Survival','Rogue-Subtlety','Priest-Discipline','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Augmentation','Shaman-Restoration','Paladin-Retribution','Druid-Balance','Unknown-Unknown','DemonHunter-Havoc','Druid-Restoration','Shaman-Elemental','Warlock-Affliction','Mage-Frost','Paladin-Holy','DeathKnight-Blood','Druid-Feral','Warrior-Fury','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Evoker-Devastation','Paladin-Protection','Monk-Mistweaver','Warrior-Protection','Druid-Guardian','Mage-Fire','Rogue-Outlaw','Evoker-Preservation','Rogue-Assassination','DemonHunter-Vengeance','Monk-Brewmaster','Shaman-Enhancement',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Ablestract:BAAALgADCggJCQAAAA==.',
Ac='Acid:BAAALgAECggJEQAAAA==.',
Ad='Adam:BAAALgAFFAEJAgABLgAFFAEJBQABAB4mAA==.Adreane:BAAALgAECgMJBAAAAA==.',
Af='Aftrlyfe:BAAALgAECgkJCQAAAA==.',
Ai='Aiyana:BAAALgADCgkJEQAAAA==.',
Ak='Akamma:BAAALgAECgcJDgAAAA==.Akarimos:BAAALgADCgMJAwAAAA==.',
Al='Alealle:BAAALgADCgMJAwAAAA==.Algeriono:BAAALgAECgMJBAAAAA==.Aliluna:BAAALgAFFAEJAQAAAA==.Alirain:BAAALgAFFAEJAQAAAA==.Alispere:BAAALgADCgUJBQAAAA==.Aliwings:BAAALgAFFAEJAQAAAA==.Alizaranna:BAAALgADCgEJAQABLgAECgYJIgACAP0ZAA==.',
Am='Amarokk:BAABLgAECn8jAAIDAAgJwAiaJwBiAQADAAgJwAiaJwBiAQAAAA==.Ameliae:BAAALgAECgEJAQAAAA==.',
An='Ancestor:BAABLgAECn8bAAIEAAcJjxPDIQCHAQAEAAcJjxPDIQCHAQAAAA==.Anish:BAAALgAECgEJAQAAAA==.',
Aq='Aqurore:BAAALgADCgYJBgAAAA==.',
Ar='Archaia:BAAALgAECgUJCQAAAA==.Argorok:BAAALgAFFAEJAQAAAA==.Aryi:BAABLgAECn8VAAQFAAkJIAczSADlAAAFAAgJiwUzSADlAAACAAMJZgm8WAB3AAAGAAIJvQRTfQBDAAAAAA==.',
As='Askim:BAAALgADCgcJBwAAAA==.Assyla:BAAALgAECgEJAQAAAA==.Astraeos:BAABLgAFFH8HAAIHAAMJKx6AZgD5AAAHAAMJKx6AZgD5AAAAAA==.',
Au='Auv:BAACLgAFFH8QAAMHAAQJESaEBwCtAQAHAAQJESaEBwCtAQAIAAEJlQBjGwA6AAAuAAQKfxQAAwgABwmJJkMTALEBAAcABQkZJl9MAOMBAAgABAkgJkMTALEBAAEuAAUUBgkPAAkADCQA.',
Av='Avarii:BAAALgAECgEJAgAAAA==.',
Aw='Awekeha:BAAALgADCgIJAgAAAA==.',
Ax='Axël:BAAALgAFFAEJAQABLgAFFAMJBwAKAKsaAA==.',
Ay='Aylranoa:BAAALgADCgkJCQAAAA==.',
Az='Azimondius:BAACLgAFFH8bAAILAAUJCRoTJQA8AQALAAUJCRoTJQA8AQAuAAQKfzoAAgsACQlyIYgFAAcDAAsACQlyIYgFAAcDAAAA.Azmora:BAAALgAECgcJDwAAAA==.Azzix:BAAALgADCgQJBQAAAA==.',
['Aí']='Aímee:BAAALgAECgEJAgAAAA==.',
Ba='Baddragons:BAAALgADCgYJBgAAAA==.Bandit:BAAALgAECgEJAQAAAA==.Bastis:BAAALgAECgEJBAABLgAFFAQJFAAMANAmAA==.Batreaux:BAAALgAFFAEJAgAAAA==.',
Be='Beaman:BAAALgADCgEJAQAAAA==.Bearkake:BAAALgAECgMJBgAAAA==.Bellgrande:BAAALgADCgYJBgAAAA==.Belthora:BAAALgAECgYJCAAAAA==.Bepallylol:BAACLgAFFH8PAAINAAUJ2hMkIgB/AQANAAUJ2hMkIgB/AQAuAAQKfxkAAg0ACAlyH7EtAGwCAA0ACAlyH7EtAGwCAAAA.',
Bh='Bhindi:BAAALgAECgMJAwABLgAFFAMJBgAOAJ4LAA==.',
Bi='Bigkeith:BAAALgADCgEJAQAAAA==.Biraj:BAAALgADCggJEAABLgAECgcJLwANAP8IAA==.',
Bl='Blaqichan:BAAALgADCgEJAwABLgADCgQJBQAPAAAAAA==.Blight:BAAALgADCgcJBQAAAA==.Bloodybecky:BAAALgAECgQJBQAAAA==.',
Bo='Boahancawk:BAAALgADCgkJCQAAAA==.',
Br='Brakiyamis:BAAALgAECgEJAgAAAA==.Brewmastah:BAAALgAECgYJDAABLgAECgUJBwAPAAAAAA==.Briarynth:BAAALgAECgEJAQAAAA==.Browntotem:BAAALgADCgUJCAAAAA==.',
Bu='Bubblecheeks:BAAALgAECgQJBQAAAA==.Bubblehëarth:BAAALgAECgYJDwAAAA==.Bubby:BAABLgAECn8WAAIHAAcJPx2OQQAIAgAHAAcJPx2OQQAIAgAAAA==.Bucklebunnie:BAAALgADCgEJAQABLgAFFAUJEQAQAFQYAA==.Bulgestomper:BAAALgAECgcJDQAAAA==.Bullzaye:BAAALgAECgQJBAAAAA==.Burbuja:BAABLgAECn8ZAAICAAgJKxGiMgA/AQACAAgJKxGiMgA/AQAAAA==.',
Ca='Cadfile:BAAALgAECgQJBgAAAA==.Calimari:BAAALgAECgMJAwAAAA==.Careco:BAAALgADCgYJBgAAAA==.Carpetcrumbs:BAAALgAECgUJBQAAAA==.Castr:BAAALgAFFAEJAgABLgADCgUJBQAPAAAAAA==.Catnsevrmeme:BAAALgAECgQJCAAAAA==.',
Ce='Cecilio:BAAALgAECgMJAwAAAA==.Cel:BAAALgAECgEJAgAAAA==.Celzara:BAAALgAECgEJAQAAAA==.Cernunnös:BAAALgADCgUJBQAAAA==.Cetraa:BAACLgAFFH8GAAMOAAMJngsJNQCrAAAOAAMJngsJNQCrAAARAAEJtRgJagBHAAAuAAQKfysAAw4ACQm7GvINAHsCAA4ACQm7GvINAHsCABEAAQkTDmfYACwAAAAA.',
Ch='Chastise:BAAALgAECgkJDwAAAA==.Chewÿ:BAAALgAECgcJBAAAAA==.Chii:BAAALgADCgEJAQAAAA==.Chocobro:BAAALgAECgYJCQAAAA==.Chäös:BAAALgAECgUJBQAAAA==.',
Cl='Clingy:BAAALgAECgQJBwAAAA==.',
Co='Cobble:BAACLgAFFH8IAAISAAMJvQoGEwB6AAASAAMJvQoGEwB6AAAuAAQKfx0AAhIACAkTGNYeAOsBABIACAkTGNYeAOsBAAAA.Colhap:BAABLgAECn8ZAAIGAAcJJhzLIQDJAQAGAAcJJhzLIQDJAQAAAA==.Conjure:BAACLgAFFH8LAAMTAAMJ1g/9AQDmAAATAAMJ1g/9AQDmAAAHAAEJ8gJb0gA4AAAuAAQKfzQAAwgACAlOF2gIAMcBAAgABwm5GWgIAMcBAAcACAmZDa+EADABAAAA.Corbina:BAABLgAECn8jAAIUAAgJ6iJ2NQCeAgAUAAgJ6iJ2NQCeAgAAAA==.Coughingbaby:BAAALgAECgEJAQAAAA==.Cousinlarry:BAAALgADCgIJAgABLgADCgQJBQAPAAAAAA==.',
Cr='Cramlutin:BAAALgADCgUJBQAAAA==.Cru:BAAALgAECgkJDgAAAA==.Crui:BAAALgADCgcJBwAAAA==.',
Cu='Culligan:BAACLgAFFH8NAAIUAAMJexnkHQDkAAAUAAMJexnkHQDkAAAuAAQKf4YAAhQACQn8H7wBAIwCABQACQn8H7wBAIwCAAAA.Cuttingcrew:BAAALgADCggJCAAAAA==.',
Cy='Cyclones:BAAALgADCgYJBgABLgAECgUJBQAPAAAAAA==.Cygwin:BAABLgAECn9CAAMMAAkJqR2AAQBGAgAMAAkJqR2AAQBGAgASAAMJZxEmbgCfAAAAAA==.',
Da='Daarius:BAAALgADCgYJBgAAAA==.Dabswfel:BAAALgAECgUJBQAAAA==.Darcfrost:BAAALgAECgEJAgAAAA==.Darcyonys:BAAALgAECgIJBQAAAA==.Dariao:BAAALgAECgIJAgABLgAECgkJLQAJAM8ZAA==.Darkironsham:BAAALgAFFAEJAQAAAA==.Darklon:BAAALgAECgkJEwAAAA==.Darknescomez:BAAALgAECgQJCAABLgAECgkJMQASAOYYAA==.Darkpun:BAAALgADCgcJCQAAAA==.Darîus:BAAALgAECgMJAwAAAA==.Dat:BAAALgAECgcJAQABLgAFFAIJBwAUAPkYAA==.Datmage:BAACLgAFFH8HAAIUAAIJ+RjEnACSAAAUAAIJ+RjEnACSAAAuAAQKfxkAAhQABwl4H3FeAB8CABQABwl4H3FeAB8CAAAA.',
De='Deathshockz:BAAALgAECgQJBQABLgAECgUJBQAPAAAAAA==.Deedeet:BAAALgAECgkJBQAAAA==.Deku:BAAALgAFFAEJAwAAAA==.Demunzz:BAAALgADCgUJCQAAAA==.Deriah:BAABLgAECn8pAAINAAgJoBQ3UADxAQANAAgJoBQ3UADxAQAAAA==.Derpatron:BAABLgAECn8UAAMNAAkJzgj5jgBUAQANAAkJzgj5jgBUAQAVAAEJuQ6gkwA3AAAAAA==.Destruction:BAABLgAECn8XAAIWAAkJfQVVLQDzAAAWAAkJfQVVLQDzAAAAAA==.Devo:BAECLgAFFH8LAAIXAAQJORcGCAApAQAXAAQJORcGCAApAQAuAAQKfxYAAhcACQm9H14DAOACABcACQm9H14DAOACAAAA.',
Di='Diabelo:BAAALgAECgQJBAAAAA==.Digoxin:BAAALgAECgEJAwAAAA==.Dingers:BAAALgAECggJDwABLgAECgkJEgAPAAAAAA==.Disgusti:BAAALgAECggJEwAAAA==.Divinespark:BAABLgAECn8jAAICAAgJMRXULACTAQACAAgJMRXULACTAQAAAA==.',
Dk='Dkins:BAAALgAECgIJAgAAAA==.',
Do='Dogeform:BAAALgADCgEJAQAAAA==.Doinkbigs:BAABLgAECn8iAAIHAAgJXQ0ncABaAQAHAAgJXQ0ncABaAQAAAA==.Doomo:BAAALgADCgYJBgABLgABCgQJBAAPAAAAAA==.Dotsfired:BAAALgADCgQJBAAAAA==.Dotñtrot:BAAALgAFFAIJAgABLgAFFAMJCwAMADUZAA==.',
Dr='Draeneisham:BAAALgAFFAEJAQAAAA==.Draethno:BAAALgAECgQJBAAAAA==.Dredd:BAAALgAECgQJDQAAAA==.Drewsilla:BAAALgAECgYJDwAAAA==.Druidrose:BAAALgAECgMJAwAAAA==.Druidtrix:BAAALgADCgYJCwAAAA==.Drylogic:BAABLgAECn8yAAIRAAkJAx+YCwAGAwARAAkJAx+YCwAGAwAAAA==.',
Du='Duckworth:BAAALgAECgEJAQAAAA==.Dulcey:BAAALgAECggJDwABLgAFFAMJBgAOAJ4LAA==.Duruk:BAABLgAECn8oAAIHAAgJRiHjAACaAgAHAAgJRiHjAACaAgAAAA==.Dustbroom:BAAALgAECgEJAQAAAA==.',
['Dà']='Dàvë:BAAALgAECgEJAQABLgAECgIJBAAPAAAAAA==.',
Ea='Eap:BAAALgAECgcJDwAAAA==.Eazye:BAACLgAFFH8UAAIGAAQJxxE5HgAAAQAGAAQJxxE5HgAAAQAuAAQKfzcAAgYACQlXHIEPAGMCAAYACQlXHIEPAGMCAAAA.',
Eb='Ebone:BAAALgADCgMJAQAAAA==.',
Ec='Ectoscourge:BAAALgADCgcJBgAAAA==.',
Ed='Edgeffs:BAABLgAECn8fAAMYAAkJlwoxNgBvAQAYAAkJZAkxNgBvAQAZAAUJZQj5JADFAAAAAA==.',
Ek='Eklipse:BAAALgADCgMJAwABLgABCgQJBAAPAAAAAA==.',
El='Elentiya:BAABLgAECn8kAAMCAAkJvxyYDgB1AgACAAkJvxyYDgB1AgAFAAEJegd7WgAtAAAAAA==.Elphzz:BAABLgAECn8YAAIEAAgJ+BL1HgADAgAEAAgJ+BL1HgADAgAAAA==.',
Em='Emoose:BAAALgAECgEJAQAAAA==.',
Er='Eriius:BAABLgAECn8UAAINAAgJNRJStgAWAQANAAgJNRJStgAWAQAAAA==.',
Ev='Evestar:BAAALgADCgEJAQAAAA==.',
Ez='Ez:BAACLgAFFH8VAAMaAAcJWBVFFQAaAQAaAAYJZhBFFQAaAQAbAAIJuBksgQCXAAAuAAQKfyoAAxoACAn0H6UYAGcCABoACAn0H6UYAGcCABsAAgmXDfwdAT4AAAAA.Ezarath:BAABLgAECn8wAAIcAAkJzwtpCwBfAQAcAAkJzwtpCwBfAQAAAA==.',
Fa='Fadedaf:BAABLgAECn8UAAIJAAYJjQ3iuAC5AAAJAAYJjQ3iuAC5AAAAAA==.',
Fe='Felenn:BAAALgADCgYJDQABLgAECgcJLwANAP8IAA==.Felorc:BAAALgAECgYJCwAAAA==.Fentun:BAAALgAFFAEJAQAAAA==.Feyla:BAAALgAECgUJCQAAAA==.',
Fi='Finnikey:BAAALgAECgIJBAAAAA==.Firstone:BAAALgADCgYJBgAAAA==.',
Fo='Foofs:BAAALgADCgUJBQAAAA==.Foulmuffn:BAAALgADCgYJCQAAAA==.Foulplay:BAAALgADCgMJAwAAAA==.Fovos:BAAALgAECgEJAQAAAA==.',
Fr='Freakonleash:BAABLgAECn8YAAIYAAgJ/Rn7GQB8AgAYAAgJ/Rn7GQB8AgAAAA==.Free:BAAALgAECgYJCgAAAA==.Frimbooze:BAAALgAECgYJBwAAAA==.',
Fu='Fuegodotz:BAAALgADCgUJBQABLgAECgkJJAAKALEcAA==.Fumonkchu:BAAALgADCgIJAQAAAA==.',
['Fé']='Féarôshima:BAAALgAECgEJAQABLgAECgkJMQASAOYYAA==.',
Ga='Ganjåfarian:BAAALgAECgIJAgAAAA==.',
Gd='Gdayum:BAAALgADCgEJAQAAAA==.',
Ge='Gekatta:BAAALgAECgYJEAAAAA==.Gelektrael:BAABLgAECn8kAAMHAAkJuA3XewBBAQAHAAgJ0QrXewBBAQAIAAIJnBQoMgBWAAAAAA==.',
Gh='Ghostdk:BAAALgAFFAQJBAABLgAFFAYJIgANAKAiAA==.Ghostwarrior:BAAALgADCgMJAwABLgAFFAYJIgANAKAiAA==.Ghostzz:BAACLgAFFH8iAAINAAYJoCJpAwDfAQANAAYJoCJpAwDfAQAuAAQKf10AAw0ACQlIJksBAIUDAA0ACQlIJksBAIUDAB0ABQkSHhcbAD8BAAAA.',
Gl='Glarb:BAAALgAECgYJDAAAAA==.Glzygldiator:BAACLgAFFH8OAAIKAAMJ1BhXLgDhAAAKAAMJ1BhXLgDhAAAuAAQKfykAAgoACAkWH+A8AA4CAAoACAkWH+A8AA4CAAAA.',
Gn='Gnomelock:BAAALgAFFAEJAQABLgAFFAEJBQABAB4mAA==.',
Go='Gobblin:BAAALgAECgUJDQAAAA==.Gotbandaids:BAAALgAECgEJAQAAAA==.Govegan:BAAALgADCgQJBwAAAA==.',
Gr='Graavey:BAAALgAECgcJAwABLgAFFAMJCwAMADUZAA==.Greyhairs:BAABLgAECn8VAAIbAAcJqQ/OfwA/AQAbAAcJqQ/OfwA/AQAAAA==.Grifter:BAAALgAECgEJAQAAAA==.Grimthor:BAAALgAECgcJBwAAAA==.Grippy:BAACLgAFFH8HAAIJAAMJRwZFcQCmAAAJAAMJRwZFcQCmAAAuAAQKfyYAAgkACAl/HUoiAIQCAAkACAl/HUoiAIQCAAAA.Gromgar:BAAALgAECgMJAwAAAA==.Gromit:BAACLgAFFH8hAAICAAgJ+Rp8AgBzAgACAAgJ+Rp8AgBzAgAuAAQKfygAAwIACQlNIZMDACEDAAIACQlNIZMDACEDAAUAAgmnEUdKAG0AAAAA.Grym:BAAALgADCgcJDgAAAA==.',
Gu='Gustófwind:BAACLgAFFH8IAAIBAAQJJSFzCgB4AQABAAQJJSFzCgB4AQAuAAQKfyAAAwEACQnKIZkEAA0DAAEACQnKIZkEAA0DAB4AAwnMEmh2ALgAAAAA.',
Ha='Hackey:BAAALgAFFAEJAQAAAA==.Haldire:BAABLgAECn8VAAIdAAcJxh0mDAACAgAdAAcJxh0mDAACAgAAAA==.Harrypotture:BAAALgADCgEJAQAAAA==.Haschel:BAABLgAECn8wAAMZAAkJriCKBADRAgAZAAkJriCKBADRAgAfAAMJ9Q6JOACFAAAAAA==.Haunterx:BAAALgAECgUJAwAAAA==.',
He='Hexerfender:BAAALgAECgUJBQAAAA==.Heypal:BAAALgADCgUJCwAAAA==.',
Ho='Hofarmer:BAABLgAECn8YAAIgAAkJUhMfFgCjAQAgAAkJUhMfFgCjAQAAAA==.Holychris:BAAALgADCgEJAQAAAA==.Holycöw:BAAALgADCgkJCQAAAA==.Holywood:BAAALgAECgYJBwAAAA==.',
Hu='Hurtak:BAAALgAECgcJEAAAAA==.',
Hy='Hycisan:BAABLgAECn8yAAIVAAkJMRwVCwDcAgAVAAkJMRwVCwDcAgAAAA==.Hysteria:BAAALgAECgMJAwAAAA==.',
Ic='Icanlust:BAAALgADCgIJAgAAAA==.Icant:BAAALgADCgEJAgABLgADCgQJBQAPAAAAAA==.Icon:BAAALgAECgQJBQAAAA==.Icydoodad:BAAALgAECgIJBAAAAA==.',
Ie='Iesous:BAAALgAECgEJAgAAAA==.',
Ig='Ignis:BAAALgADCgMJAwAAAA==.',
Io='Iocomotive:BAAALgAFFAEJAQAAAA==.',
Is='Iskaru:BAAALgAECgEJAQABLgAECgYJDwAPAAAAAA==.',
Ja='Jacklawin:BAAALgAECgMJAwAAAA==.Jasmyn:BAAALgADCgQJBAAAAA==.',
Jb='Jbirdlol:BAAALgADCgUJBAAAAA==.',
Je='Jenziserrin:BAAALgAECgEJAgAAAA==.Jesse:BAAALgAECgYJEAABLgAFFAIJBwAVAHYXAA==.Jetmage:BAABLgAECn8gAAIhAAkJRyToAADgAgAhAAkJRyToAADgAgAAAA==.',
Ji='Jire:BAAALgAECgUJDQAAAA==.Jittkal:BAAALgADCgMJAwAAAA==.',
Jo='Josh:BAAALgADCgMJAgAAAA==.',
Jp='Jpally:BAABLgAECn8XAAMVAAcJ2AbKSwAMAQAVAAcJ2AbKSwAMAQANAAUJSwRA7AC3AAAAAA==.',
Ju='Jurassthicc:BAAALgAECgEJBQAAAA==.',
Jw='Jwøww:BAAALgADCgEJAgABLgADCgQJBQAPAAAAAA==.',
Ka='Kafka:BAAALgADCgcJBgAAAA==.Kanastra:BAABLgAECn8dAAIJAAkJrBssHQBlAgAJAAkJrBssHQBlAgABLgAFFAUJGwALAAkaAA==.Karraa:BAABLgAECn8qAAIfAAkJXRgLEQDaAQAfAAkJXRgLEQDaAQAAAA==.Katil:BAAALgAECgEJAQAAAA==.Kaylib:BAABLgAECn8sAAIhAAkJJxABBADFAQAhAAkJJxABBADFAQAAAA==.',
Ke='Kea:BAAALgADCgIJAgABLgAECgUJCQAPAAAAAA==.Kenergy:BAAALgAECgUJCQAAAA==.Kerze:BAABLgAECn8UAAIfAAYJlhHwKQDlAAAfAAYJlhHwKQDlAAAAAA==.Kesatrix:BAABLgAECn8tAAIeAAkJSRQPIQAUAgAeAAkJSRQPIQAUAgAAAA==.Kesi:BAAALgADCgQJBAAAAA==.',
Kh='Khai:BAAALgAECgQJBAAAAA==.Khazador:BAAALgADCgkJEgABLgAECgkJHQAHALkXAA==.Khaztharion:BAAALgADCggJCAABLgAECgkJHQAHALkXAA==.Khendrick:BAABLgAECn8aAAINAAkJ1w8pXwCzAQANAAkJ1w8pXwCzAQAAAA==.',
Ki='Kilerwolf:BAAALgADCgIJAgAAAA==.Kimsmage:BAAALgADCgYJBgAAAA==.Kirdo:BAAALgAECgEJAQAAAA==.Kith:BAAALgAECgEJAgAAAA==.Kitridge:BAAALgAECgcJDQAAAA==.Kittykatt:BAACLgAFFH8KAAIOAAMJ3xUqCgDaAAAOAAMJ3xUqCgDaAAAuAAQKfz0AAg4ACQkMIOUGAOgCAA4ACQkMIOUGAOgCAAAA.',
Ko='Kolchak:BAAALgADCgYJDQAAAA==.Korel:BAAALgAECgcJDAAAAA==.',
Kr='Kraggo:BAAALgAFFAEJAQAAAA==.Krimzin:BAACLgAFFH8YAAINAAUJzSFcKQBmAQANAAUJzSFcKQBmAQAuAAQKfxwAAw0ACQlnIc4XANoCAA0ACAkOIc4XANoCABUABQlTD3phALAAAAAA.',
Ku='Kumala:BAAALgAECgMJBQAAAA==.Kungao:BAAALgAECgUJBQAAAA==.',
Ky='Kylea:BAAALgAECgQJBAAAAA==.',
La='Laffiel:BAAALgADCgQJBAAAAA==.Landoh:BAABLgAECn8kAAIUAAkJ+CGWGADGAgAUAAkJ+CGWGADGAgAAAA==.Larg:BAAALgAECgEJAQAAAA==.Larsen:BAABLgAECn8kAAISAAkJZR6QFABGAgASAAkJZR6QFABGAgAAAA==.',
Le='Leap:BAABLgAECn8nAAMgAAkJHRtiAgBCAQAXAAcJIxt4DQDeAQAgAAkJqxViAgBCAQAAAA==.Lefthorn:BAAALgADCgIJAgAAAA==.Lenneth:BAAALgAECgIJAgAAAA==.',
Li='Lightofdawn:BAAALgAECgMJAwAAAA==.Lightstyle:BAAALgADCgMJAwAAAA==.Lilow:BAABLgAECn85AAIGAAkJIhKGHwDJAQAGAAkJIhKGHwDJAQAAAA==.',
Ll='Llarker:BAABLgAECn8vAAQNAAcJ/wgewwAEAQANAAcJ/wgewwAEAQAdAAYJHAO0OQB3AAAVAAIJvQEXkQAtAAAAAA==.',
Lo='Lockendron:BAAALgADCgQJBAAAAA==.Locketharion:BAAALgADCgQJBAAAAA==.Lockpebbles:BAAALgADCgMJAwAAAA==.Lokomachina:BAABLgAECn8UAAIbAAcJLyETHwBLAgAbAAcJLyETHwBLAgAAAA==.Lonesdove:BAAALgADCgEJAQAAAA==.',
Lu='Lucyna:BAAALgAECgMJAwABLgAECgkJJQAiAPUiAA==.Luminia:BAAALgAECgUJCAAAAA==.Lunacy:BAAALgAECgQJBwAAAA==.',
Ly='Lynngosa:BAABLgAECn8uAAMjAAgJLxWTAADLAQAjAAgJLxWTAADLAQALAAcJHAi8UQDoAAAAAA==.Lyrana:BAAALgADCgQJBAAAAA==.Lyrasa:BAAALgADCgQJBAAAAA==.',
Ma='Maelidrael:BAAALgAECgMJAwABLgAFFAIJBQAUADwRAA==.Magiks:BAAALgAFFAEJAQAAAA==.Magisterium:BAABLgAECn8tAAMCAAgJ3gf2PgD0AAACAAgJ3gf2PgD0AAAGAAEJ/QFDnAAXAAAAAA==.Malady:BAABLgAECn8sAAIGAAkJwCA+CQC7AgAGAAkJwCA+CQC7AgAAAA==.Malakyde:BAAALgADCgMJAwAAAA==.Malt:BAABLgAECn8ZAAIJAAgJvCB7OgDdAQAJAAgJvCB7OgDdAQAAAA==.Malthorial:BAAALgADCgEJAQAAAA==.Mario:BAABLgAFFH8FAAIBAAEJHiYWNwBrAAABAAEJHiYWNwBrAAAAAA==.Mattenom:BAAALgADCgYJCAAAAA==.Maulware:BAAALgADCgEJAQAAAA==.',
Mb='Mbrodh:BAAALgAECgQJBAAAAA==.Mbrosmites:BAAALgAECgcJCwAAAA==.',
Md='Mdeag:BAABLgAECn8WAAMYAAUJ9hYuBwDBAAAYAAQJ9RYuBwDBAAAZAAUJDA5/RwCtAAAAAA==.',
Me='Mefistofeles:BAACLgAFFH8QAAIEAAMJFBRxJwDsAAAEAAMJFBRxJwDsAAAuAAQKfyMAAgQACAlmGJ8XAN4BAAQACAlmGJ8XAN4BAAAA.Meingaree:BAABLgAECn8hAAIIAAkJyRxMAAA5AgAIAAkJyRxMAAA5AgAAAA==.Merlinus:BAABLgAECn8lAAINAAcJ4gq0lABTAQANAAcJ4gq0lABTAQAAAA==.Merton:BAAALgADCggJDAAAAA==.',
Mi='Mightyguzz:BAABLgAECn9AAAIfAAkJmhPbEQDMAQAfAAkJmhPbEQDMAQAAAA==.Miku:BAAALgAECgMJBAAAAA==.Misericordia:BAAALgAECgUJCAAAAA==.Mitchelle:BAAALgAECgMJBQAAAA==.',
Mo='Moirayne:BAAALgAECgYJBQAAAA==.Moomkin:BAABLgAECn8oAAIOAAgJgwyDNwA3AQAOAAgJgwyDNwA3AQAAAA==.',
My='Mythicblade:BAAALgADCgEJAQAAAA==.',
['Mø']='Møønchild:BAAALgAECgkJEAAAAA==.',
Na='Nai:BAAALgAECgQJDAAAAA==.Nanaish:BAAALgAECgEJAgAAAA==.Narpul:BAABLgAECn8rAAIdAAkJBB7eBACpAgAdAAkJBB7eBACpAgAAAA==.Natë:BAACLgAFFH8TAAIfAAMJOhgKBwDGAAAfAAMJOhgKBwDGAAAuAAQKfzAAAh8ACQkvIWUDACMDAB8ACQkvIWUDACMDAAAA.Nazend:BAAALgADCgQJBwAAAA==.',
Ne='Necrotalon:BAAALgAECgcJEQAAAA==.Nelosi:BAAALgAECgMJCAAAAA==.Neondh:BAACLgAFFH8VAAIJAAQJPSSvJQCWAQAJAAQJPSSvJQCWAQAuAAQKfzQAAgkACQmIJA4NABcDAAkACQmIJA4NABcDAAAA.Nerzhùl:BAABLgAECn8lAAISAAkJGglcPABEAQASAAkJGglcPABEAQAAAA==.',
Nh='Nharuna:BAACLgAFFH8MAAIbAAMJvgdSGwDMAAAbAAMJvgdSGwDMAAAuAAQKfzgAAhsACQnbEyI2AAUCABsACQnbEyI2AAUCAAAA.',
Ni='Nickolaos:BAAALgAECgEJAgAAAA==.Nieloriel:BAABLgAECn9BAAMVAAkJxxRiAQDlAQAVAAkJxxRiAQDlAQANAAgJmgrSlwBFAQAAAA==.Nightwishing:BAAALgAECgQJBAAAAA==.Niupiadps:BAAALgAECgIJAgAAAA==.Niykee:BAABLgAECn8lAAQiAAkJ9SI6AwByAgAiAAYJhSQ6AwByAgAEAAcJPiKmHAAaAgAkAAcJCx5mBgARAgAAAA==.',
No='Noboundss:BAABLgAECn8bAAMJAAgJZg+EcgA9AQAJAAcJSg+EcgA9AQAQAAMJiA/RCwBHAAAAAA==.Nobóunds:BAAALgAECgkJEAAAAA==.Nomnoms:BAAALgAECgYJEgAAAA==.Nomoreheals:BAAALgAECgYJDQAAAA==.Notkarl:BAAALgAECgIJAwAAAA==.Nowimpissed:BAACLgAFFH8PAAMDAAMJ9SGsGAANAQADAAMJ9SGsGAANAQAbAAEJvyDWHgBkAAAuAAQKfxcABAMABgnEHpUTAAkCAAMABgnEHpUTAAkCABsABAkPFsp5APoAABoABAnmDzBbANcAAAAA.Noztra:BAACLgAFFH8XAAIUAAQJKAkBIgDLAAAUAAQJKAkBIgDLAAAuAAQKfywAAhQACAnjF+dLAPcBABQACAnjF+dLAPcBAAAA.',
Nu='Nu:BAAALgADCgMJAwAAAA==.Nuker:BAAALgAECgEJAQAAAA==.',
Ny='Nysrogh:BAAALgAECgUJEgABLgAFFAQJFAARADQXAA==.',
Ob='Obsideon:BAAALgAECggJEwAAAA==.',
Oc='Octoknight:BAAALgADCgEJAQAAAA==.',
Oh='Ohgr:BAABLgAECn8dAAIYAAYJaiCiAQDBAQAYAAYJaiCiAQDBAQAAAA==.Ohshifty:BAABLgAECn80AAMOAAkJ0xApJQCiAQAOAAkJ0xApJQCiAQARAAQJbASMowBqAAAAAA==.',
Ol='Olan:BAAALgAECgYJDAAAAA==.Olie:BAABLgAECn8bAAIbAAgJ9wnYdgBSAQAbAAgJ9wnYdgBSAQAAAA==.',
Or='Orbsicles:BAABLgAECn8oAAQlAAkJ/SHVAQD9AgAlAAkJ/SHVAQD9AgAQAAEJKBqSYABMAAAJAAEJtgvvGgEvAAAAAA==.Oriøn:BAAALgADCgYJBgAAAA==.',
Ou='Ouragan:BAAALgAECgUJCAAAAA==.',
Pa='Paedrig:BAAALgAECgEJAQAAAA==.Papitomyrey:BAABLgAECn8gAAMYAAkJKCReBwDpAgAYAAkJKCReBwDpAgAZAAUJYh07OADkAAABLgAFFAMJBQAeAMATAA==.Paramedic:BAAALgADCgIJAgAAAA==.Passtheflask:BAABLgAECn8eAAIHAAcJGgcNrQDpAAAHAAcJGgcNrQDpAAAAAA==.',
Pe='Perdition:BAAALgAECgEJAgAAAA==.Pestílence:BAACLgAFFH8LAAIKAAMJsxzqjgDtAAAKAAMJsxzqjgDtAAAuAAQKfz8AAwoACQk1IrAYALICAAoACQk1IrAYALICABYAAQnEEZBHACoAAAAA.',
Ph='Phaesphoros:BAABLgAECn8gAAIMAAkJXxDvSwCAAQAMAAkJXxDvSwCAAQAAAA==.Phenor:BAAALgAECgQJBAAAAA==.',
Po='Poe:BAAALgADCgYJBgABLgAECgcJFQAUAOEXAA==.Powpow:BAABLgAECn83AAIEAAkJ2BoACQCVAgAEAAkJ2BoACQCVAgAAAA==.',
Pr='Prejudice:BAABLgAECn8dAAIVAAkJnxTqHQATAgAVAAkJnxTqHQATAgAAAA==.Primévil:BAAALgAECgYJBgABLgAECgkJMQASAOYYAA==.Priscilla:BAAALgAECgEJAgAAAA==.Prowlcow:BAABLgAECn8yAAMRAAkJdRd6HABjAgARAAkJdRd6HABjAgAXAAIJDxYsNgCEAAAAAA==.',
Ps='Psychosis:BAABLgAECn8uAAIKAAkJ5B1BJwBlAgAKAAkJ5B1BJwBlAgAAAA==.',
Pu='Purpetua:BAAALgAECgQJBAAAAA==.Putrescence:BAAALgADCgEJAQAAAA==.',
['Pû']='Pûff:BAAALgAECgcJDwAAAA==.',
Qm='Qmpel:BAAALgADCgMJAwAAAA==.',
Ra='Raiiz:BAACLgAFFH8IAAIUAAMJBBBmLAAFAQAUAAMJBBBmLAAFAQAuAAQKfyYAAhQACAkhHI4/AHoCABQACAkhHI4/AHoCAAAA.Rainhoof:BAABLgAECn8kAAMXAAkJsRgIDAD5AQAXAAgJOhkIDAD5AQARAAYJlweAhwDHAAAAAA==.Ralneth:BAACLgAFFH8aAAMLAAkJ+w/FEAD7AQALAAgJ2g/FEAD7AQAcAAQJXRToAwAOAQAuAAQKfyQAAxwACAmrIFADAOsCABwACAmfH1ADAOsCAAsABgnYG0IYAA8CAAAA.Randomtask:BAAALgADCgUJBgAAAA==.Rapala:BAABLgAECn8mAAIHAAkJ+hz2GwB9AgAHAAkJ+hz2GwB9AgAAAA==.Rapalaa:BAAALgAECgcJDwABLgAECgkJJgAHAPocAA==.Raspútin:BAABLgAECn8zAAMmAAkJqBl9DgBSAgAmAAkJqBl9DgBSAgABAAQJ8AfVVQC5AAAAAA==.Ravos:BAAALgAECgYJBgAAAA==.Rawkfice:BAAALgADCggJFAAAAA==.',
Re='Redlefevoker:BAAALgADCgYJCQAAAA==.Renfield:BAAALgADCgYJCAAAAA==.Revok:BAAALgAECgcJCwAAAA==.Revoker:BAAALgADCgYJCAAAAA==.',
Ri='Riordan:BAAALgAFFAEJAgAAAA==.Rivvetear:BAAALgADCgYJBgAAAA==.',
Rj='Rjolz:BAACLgAFFH8OAAIKAAQJZiBiOACLAQAKAAQJZiBiOACLAQAuAAQKfzsAAgoACQn7JQAEAGIDAAoACQn7JQAEAGIDAAAA.',
Ro='Roflchopr:BAAALgAECggJEQAAAA==.Roflkin:BAAALgAECgEJAQAAAA==.Roguish:BAAALgAECgEJAQAAAA==.Rootzi:BAAALgAECgIJAwABLgAECgkJJAAKALEcAA==.Rootzidk:BAABLgAECn8kAAIKAAkJsRxLNQAqAgAKAAkJsRxLNQAqAgAAAA==.Roshaka:BAAALgAECgcJEQAAAA==.',
Ru='Rucks:BAABLgAECn8jAAMBAAkJ1Br1GQDhAQABAAkJIRP1GQDhAQAmAAYJzBrULQCiAQAAAA==.',
Ry='Ryzze:BAAALgADCgYJBgAAAA==.',
Sa='Saelem:BAAALgAECgYJBgAAAA==.Saigonbeer:BAAALgAECgMJAwAAAA==.Sandalfon:BAAALgAECgYJDwAAAA==.Sanleron:BAACLgAFFH8FAAIdAAMJ5RDxDACqAAAdAAMJ5RDxDACqAAAuAAQKfxYAAx0ACAlYIcYNAOkBAB0ABgkWIsYNAOkBAA0ABQm0GiWlADABAAAA.Sarith:BAAALgAECgQJAQABLgAECgUJBQAPAAAAAA==.Saske:BAAALgADCgMJBwABLgAECgEJAQAPAAAAAA==.',
Sc='Scarab:BAAALgAECgYJBgAAAA==.Scargon:BAAALgAECgcJEAAAAA==.Schizandrol:BAAALgAECgQJBAAAAA==.',
Se='Selidori:BAAALgADCgYJBgAAAA==.Seralicht:BAACLgAFFH8SAAICAAYJ+RU9CwCXAQACAAYJ+RU9CwCXAQAuAAQKfyIAAwIACAmGHhwQAGUCAAIACAmGHhwQAGUCAAYAAQmKCyWIADEAAAAA.',
Sh='Shadowclawz:BAAALgAECgQJBgAAAA==.Shaliri:BAAALgADCgEJBAAAAA==.Shamanata:BAAALgAECgEJAgAAAA==.Sharayse:BAABLgAECn8hAAIUAAkJWgxbbQCgAQAUAAkJWgxbbQCgAQAAAA==.Sharmee:BAAALgAECgkJEQAAAA==.Shennong:BAAALgAECgEJAQAAAA==.Shishy:BAAALgAECgUJCgAAAA==.Shockohôlic:BAABLgAECn8xAAQSAAkJ5hgjFQBAAgASAAkJ5hgjFQBAAgAMAAYJ/xB/bAAWAQAnAAEJoAphKwA4AAAAAA==.Shocky:BAAALgAECgcJCgAAAA==.Sháde:BAAALgADCgIJAgAAAA==.',
Sk='Skullkìng:BAABLgAECn8jAAIKAAkJuhSMTADdAQAKAAkJuhSMTADdAQAAAA==.',
Sl='Slingablade:BAACLgAFFH8NAAIJAAQJ/wZvXwDRAAAJAAQJ/wZvXwDRAAAuAAQKfyUAAwkACQliFoQuAA0CAAkACQlpFYQuAA0CABAAAwm9Ey5DAKkAAAAA.',
Sm='Smashnskullz:BAAALgAECgQJBgABLgAECgUJBQAPAAAAAA==.',
Sn='Sniffsniff:BAACLgAFFH8JAAINAAMJxyW2TQATAQANAAMJxyW2TQATAQAuAAQKfykAAw0ACAlHJQYKAEEDAA0ACAlHJQYKAEEDABUAAQnBHhx/AE4AAAEuAAUUBAkUAAwA0CYA.',
So='Solvi:BAABLgAECn8fAAIRAAcJ9xfzVQA4AQARAAcJ9xfzVQA4AQAAAA==.Sonira:BAAALgADCgMJBQAAAA==.Soulbrand:BAABLgAECn8kAAIGAAkJMwmGLwBhAQAGAAkJMwmGLwBhAQAAAA==.Southpawclaw:BAAALgAECgEJAQABLgAECggJGAAnAPAfAA==.',
Sp='Spellz:BAABLgAECn8lAAIGAAgJ0x9pDACKAgAGAAgJ0x9pDACKAgAAAA==.Spoo:BAAALgAECgIJAwAAAA==.Spuggle:BAAALgAECgQJBAAAAA==.',
St='Stabathuh:BAAALgADCgYJBgAAAA==.Starman:BAAALgAECgkJCQAAAA==.Stoopiddk:BAAALgAECgEJAwABLgAECgIJBAAPAAAAAA==.Stoopidelf:BAAALgAECgEJAwABLgAECgIJBAAPAAAAAA==.Stoopidmonk:BAAALgAECgEJAQABLgAECgIJBAAPAAAAAA==.Stoopidrood:BAAALgAECgEJAQABLgAECgIJBAAPAAAAAA==.Stoopidtroll:BAAALgADCgUJBQABLgAECgIJBAAPAAAAAA==.Stoopidwarur:BAAALgAECgEJBAABLgAECgIJBAAPAAAAAA==.Stormclaw:BAABLgAECn8cAAIlAAkJiAwZDgBwAQAlAAkJiAwZDgBwAQAAAA==.Straeka:BAAALgAECgIJAgABLgAECgkJQwARAKAZAA==.Stëvë:BAAALgAECgIJBAABLgAECgYJDwAPAAAAAA==.',
Su='Sufiya:BAABLgAECn8gAAIbAAkJLw9GUwCpAQAbAAkJLw9GUwCpAQAAAA==.Suhwoo:BAAALgAECgcJDwAAAA==.Sumig:BAAALgADCgEJBAAAAA==.',
Sw='Swiftarrows:BAAALgAECgEJAgAAAA==.',
Sy='Sylvershadow:BAABLgAECn8pAAIbAAkJMBU0SQDGAQAbAAkJMBU0SQDGAQAAAA==.Sym:BAAALgADCgcJCQAAAA==.',
Ta='Taintedsoulv:BAAALgADCgUJBgAAAA==.Taliri:BAAALgADCgEJAQABLgADCgQJBQAPAAAAAA==.Tandarilada:BAAALgAFFAEJBAAAAA==.Tanknspankn:BAAALgAECgkJDAAAAA==.Tankurface:BAAALgAECgEJAgAAAA==.',
Th='Thalvint:BAACLgAFFH8MAAIZAAQJSRs5FAA8AQAZAAQJSRs5FAA8AQAuAAQKfzMAAxkACQmHIxUDAAkDABkACQmHIxUDAAkDABgABgnVEiJbAEIBAAAA.Theblackhand:BAABLgAECn8dAAMSAAYJ1RXTSgAcAQASAAUJaxPTSgAcAQAMAAYJrQ+TdgD6AAAAAA==.Thefira:BAAALgADCgkJCQAAAA==.Thickdk:BAABLgAECn8aAAIKAAgJHRZTbgCtAQAKAAgJHRZTbgCtAQAAAA==.Thoriel:BAAALgAECgEJAgAAAA==.',
Ti='Timefall:BAAALgAECgkJDgAAAA==.Titanic:BAAALgAECgcJEAAAAA==.',
To='Tomcruise:BAAALgAECgkJEgAAAA==.Toshiro:BAAALgADCgcJBwAAAA==.Totemlyawsum:BAABLgAFFH8LAAISAAQJDg2RKgDrAAASAAQJDg2RKgDrAAAAAA==.Touch:BAAALgAECgEJAQAAAA==.Touchymcfeel:BAAALgADCgMJAwAAAA==.',
Tr='Trckr:BAAALgADCgIJAgAAAA==.Treeiage:BAAALgAECgUJCAAAAA==.Trooblu:BAAALgAECgYJEgAAAA==.',
Tw='Twotone:BAAALgAECgQJBgAAAA==.',
['Té']='Téz:BAABLgAECn8iAAMCAAYJ/RntAgBNAQACAAQJ/hztAgBNAQAGAAYJvhdVBQDTAAAAAA==.',
['Tê']='Têzeret:BAAALgAECgEJAgAAAA==.',
Ul='Ulkthar:BAABLgAECn8wAAIYAAgJ2BPKKAAZAgAYAAgJ2BPKKAAZAgABLgAECgkJIQAUANYXAA==.Ultrauchuva:BAAALgAECgEJAQAAAA==.',
Un='Unholyhammer:BAAALgADCgIJAgABLgAECgUJBQAPAAAAAA==.',
Va='Vacunamatata:BAAALgAECgEJAQAAAA==.Vanarn:BAAALgADCgEJAQABLgADCgQJBQAPAAAAAA==.Vanlin:BAABLgAECn8kAAIRAAkJWh5QDwDaAgARAAkJWh5QDwDaAgAAAA==.',
Ve='Velirayvia:BAAALgAECgQJBgAAAA==.Vexxdr:BAACLgAFFH8LAAIRAAMJZAw3RwCZAAARAAMJZAw3RwCZAAAuAAQKfx8AAhEACAkcEtc5AL4BABEACAkcEtc5AL4BAAEuAAUUAwkLAAwANw4A.Vexxs:BAACLgAFFH8LAAIMAAMJNw4wFwCWAAAMAAMJNw4wFwCWAAAuAAQKfxsAAgwACQnIFasgAEsCAAwACQnIFasgAEsCAAAA.',
Vi='Virtey:BAAALgADCgUJBQAAAA==.Virtuous:BAAALgADCgYJBwAAAA==.',
Vl='Vladzy:BAAALgADCgcJAwAAAA==.',
Vo='Voidsuzu:BAAALgAECgMJAwABLgAECgkJNwAdALkUAA==.Vormedicus:BAABLgAECn8UAAICAAcJ/hnOAgBXAQACAAcJ/hnOAgBXAQABLgAECgkJMwAmAKgZAA==.',
Vu='Vulperas:BAABLgAECn8/AAISAAkJJxHWKACoAQASAAkJJxHWKACoAQAAAA==.',
Vy='Vynastallan:BAABLgAECn8cAAMbAAcJhSOMIABCAgAbAAcJhSOMIABCAgAaAAEJehfShgA1AAAAAA==.Vyper:BAEBLgAECn8lAAILAAgJcxmIHwDcAQALAAgJcxmIHwDcAQABLgAFFAQJCwAXADkXAA==.',
Wa='Waroo:BAABLgAECn8iAAIOAAgJORICJQCjAQAOAAgJORICJQCjAQAAAA==.',
We='Wellcole:BAAALgADCgYJBgAAAA==.Wenden:BAAALgAFFAEJAwAAAA==.Wengo:BAAALgADCgkJCgAAAA==.',
Wi='Wilbert:BAAALgADCgEJAQAAAA==.Winniethepo:BAAALgAECgQJBAAAAA==.Witherflow:BAAALgAECgQJBQAAAA==.',
Wo='Woodey:BAAALgADCgcJCAAAAA==.',
Wu='Wulffric:BAABLgAECn8aAAIDAAgJJRLkJQBuAQADAAgJJRLkJQBuAQAAAA==.',
Xe='Xeo:BAAALgADCgMJAwAAAA==.',
Ya='Yachirú:BAABLgAECn83AAIdAAkJuRTDDgDXAQAdAAkJuRTDDgDXAQAAAA==.Yahkisoba:BAAALgAECgEJAQAAAA==.',
Ye='Yessir:BAAALgAECgEJAQABLgAECgkJGgABAA4XAA==.',
Yi='Yiang:BAABLgAECn8nAAIBAAkJ0R0YCgCiAgABAAkJ0R0YCgCiAgAAAA==.',
Yl='Ylndrysa:BAABLgAECn9DAAMRAAkJoBkbGQB9AgARAAkJoBkbGQB9AgAOAAMJoRgCUgDGAAAAAA==.',
Yt='Ytho:BAAALgADCgYJBgAAAA==.',
Za='Zalithar:BAABLgAECn8VAAIJAAgJZgUdmwDrAAAJAAgJZgUdmwDrAAAAAA==.',
Ze='Zedrock:BAACLgAFFH8FAAIUAAIJPBHQngCPAAAUAAIJPBHQngCPAAAuAAQKfz8AAhQACQk0Il4KACcDABQACQk0Il4KACcDAAAA.Zekodian:BAAALgADCgcJDQAAAA==.Zentner:BAABLgAECn8uAAMOAAkJXx9OCwCeAgAOAAkJXx9OCwCeAgAgAAQJPAodJAB8AAAAAA==.Zeropistol:BAABLgAECn8aAAIUAAgJNQPzzgDzAAAUAAgJNQPzzgDzAAAAAA==.Zexrous:BAAALgADCgEJAQAAAA==.',
Zh='Zhas:BAABLgAECn8WAAICAAcJfhVELABoAQACAAcJfhVELABoAQAAAA==.',
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
