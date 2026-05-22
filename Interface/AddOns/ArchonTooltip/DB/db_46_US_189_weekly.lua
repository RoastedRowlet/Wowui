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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','Evoker-Augmentation','Paladin-Retribution','Druid-Balance','Druid-Restoration','Priest-Shadow','Mage-Frost','Shaman-Restoration','DeathKnight-Blood','Priest-Holy','Warrior-Fury','Warrior-Arms','Priest-Discipline','Rogue-Subtlety','Hunter-Marksmanship','Hunter-BeastMastery','Evoker-Devastation','DeathKnight-Unholy','Paladin-Protection','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','Druid-Guardian','Paladin-Holy','Mage-Fire','Shaman-Elemental','Rogue-Outlaw','Rogue-Assassination','Hunter-Survival','Druid-Feral','Monk-Brewmaster','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Ablestract:BAAALgADCggJCQAAAA==.',
Ac='Acid:BAAALgAECgYJCwAAAA==.',
Ad='Adreane:BAAALgAECgMJBAAAAA==.',
Af='Aftrlyfe:BAAALgAECgkJCAAAAA==.',
Ai='Aiyana:BAAALgADCgkJEQAAAA==.',
Ak='Akamma:BAAALgAECgcJDQAAAA==.Akarimos:BAAALgADCgMJAwAAAA==.',
Al='Alealle:BAAALgADCgMJAwAAAA==.Algeriono:BAAALgADCgQJBAAAAA==.Alirain:BAAALgAECgUJBwAAAA==.Alispere:BAAALgADCgUJBQAAAA==.Aliwings:BAAALgAECgEJAgAAAA==.Alizaranna:BAAALgADCgEJAQABLgAECgYJDAABAAAAAA==.',
Am='Amarokk:BAAALgAECgUJEQAAAA==.Ameliae:BAAALgAECgEJAQAAAA==.',
An='Ancestor:BAAALgAECgQJCgAAAA==.Anish:BAAALgAECgEJAQAAAA==.',
Aq='Aqurore:BAAALgADCgYJBgAAAA==.',
Ar='Archaia:BAAALgAECgMJAwAAAA==.Aryi:BAAALgAECggJCAAAAA==.',
As='Askim:BAAALgADCgcJBwAAAA==.Assyla:BAAALgAECgEJAQAAAA==.Astraeos:BAAALgAECggJCwAAAA==.',
Au='Auv:BAACLgAFFH8QAAMCAAQJESaEBwCtAQACAAQJESaEBwCtAQADAAEJlQBjGwA6AAAuAAQKfxQAAwMABwmJJkMTALEBAAIABQkZJl9MAOMBAAMABAkgJkMTALEBAAEuAAUUBQkKAAQADCQA.',
Aw='Awekeha:BAAALgADCgIJAgAAAA==.',
Ax='Axël:BAAALgAFFAEJAQABLgAFFAIJBAABAAAAAA==.',
Ay='Aylranoa:BAAALgADCgkJCQAAAA==.',
Az='Azimondius:BAACLgAFFH8KAAIFAAMJ2BWMJAD3AAAFAAMJ2BWMJAD3AAAuAAQKfyUAAgUACAmkH+ILALcCAAUACAmkH+ILALcCAAAA.Azmora:BAAALgAECgYJCgAAAA==.Azzix:BAAALgADCgQJBQAAAA==.',
Ba='Baddragons:BAAALgADCgYJBgAAAA==.Bandit:BAAALgAECgEJAQAAAA==.Bastis:BAAALgAECgEJBAABLgAFFAMJCQAGAMclAA==.Batreaux:BAAALgAFFAEJAQAAAA==.',
Be='Beaman:BAAALgADCgEJAQAAAA==.Bearkake:BAAALgAECgMJBgAAAA==.Bellgrande:BAAALgADCgYJBgAAAA==.Belthora:BAAALgADCgUJBQAAAA==.Bepallylol:BAACLgAFFH8FAAIGAAUJtwj0GwBSAQAGAAUJtwj0GwBSAQAuAAQKfxgAAgYACAliHbEtAGwCAAYACAliHbEtAGwCAAAA.',
Bi='Bigkeith:BAAALgADCgEJAQAAAA==.Biraj:BAAALgADCggJDgABLgAECgYJGQAGAJcFAA==.',
Bl='Blaqichan:BAAALgADCgEJAwABLgADCgQJBQABAAAAAA==.Blight:BAAALgADCgcJBQAAAA==.Bloodybecky:BAAALgAECgQJBQAAAA==.',
Br='Brewmastah:BAAALgAECgUJBQAAAA==.Browntotem:BAAALgADCgUJCAAAAA==.',
Bu='Bubblecheeks:BAAALgAECgQJBQAAAA==.Bubblehëarth:BAAALgAECgYJCQAAAA==.Bubby:BAABLgAECn8WAAICAAcJPx2OQQAIAgACAAcJPx2OQQAIAgAAAA==.Burbuja:BAAALgAECgUJDgAAAA==.',
Ca='Cadfile:BAAALgAECgQJBgAAAA==.Careco:BAAALgADCgYJBgAAAA==.Carpetcrumbs:BAAALgAECgUJBQAAAA==.Catnsevrmeme:BAAALgAECgEJAgAAAA==.',
Ce='Cecilio:BAAALgAECgMJAwAAAA==.Cel:BAAALgAECgEJAgAAAA==.Celzara:BAAALgAECgEJAQAAAA==.Cetraa:BAABLgAECn8UAAMHAAgJmRXxGACtAQAHAAgJmRXxGACtAQAIAAEJEw7zsAArAAAAAA==.',
Ch='Chastise:BAAALgAECgkJDAAAAA==.Chewÿ:BAAALgAECgcJAwAAAA==.Chii:BAAALgADCgEJAQAAAA==.Chocobro:BAAALgAECgQJBwAAAA==.Chäös:BAAALgAECgUJBQAAAA==.',
Cl='Clingy:BAAALgAECgEJAQAAAA==.',
Co='Cobble:BAAALgAECgcJDQAAAA==.Colhap:BAABLgAECn8ZAAIJAAcJJhzLIQDJAQAJAAcJJhzLIQDJAQAAAA==.Conjure:BAABLgAECn8mAAMCAAgJlxB1YQBAAQACAAgJmQ11YQBAAQADAAMJDxcgHACKAAAAAA==.Corbina:BAABLgAECn8jAAIKAAgJ6iIuJQBIAgAKAAgJ6iIuJQBIAgAAAA==.Cousinlarry:BAAALgADCgIJAgABLgADCgQJBQABAAAAAA==.',
Cr='Cramlutin:BAAALgADCgUJBQAAAA==.Cru:BAAALgAECgkJDgAAAA==.Crui:BAAALgADCgcJBwAAAA==.',
Cu='Culligan:BAABLgAECn9QAAIKAAkJKhneJwA6AgAKAAkJKhneJwA6AgAAAA==.Cuttingcrew:BAAALgADCggJCAAAAA==.',
Cy='Cygwin:BAABLgAECn8nAAILAAgJjxZKHAAUAgALAAgJjxZKHAAUAgAAAA==.',
Da='Darcfrost:BAAALgAECgEJAQAAAA==.Darcyonys:BAAALgAECgIJBQAAAA==.Dariao:BAAALgAECgIJAgABLgAECgkJKwAEAM8ZAA==.Darklon:BAAALgAECgkJEwAAAA==.Darkpun:BAAALgADCgcJCQAAAA==.Darîus:BAAALgAECgMJAwAAAA==.Dat:BAAALgAECgcJAQABLgAFFAIJBwAKAPkYAA==.Datmage:BAACLgAFFH8HAAIKAAIJ+RjdawCuAAAKAAIJ+RjdawCuAAAuAAQKfxkAAgoABwl3H3FeAB8CAAoABwl3H3FeAB8CAAAA.',
De='Deathshockz:BAAALgAECgQJBQABLgAECgUJBQABAAAAAA==.Demunzz:BAAALgADCgUJCQAAAA==.Deriah:BAABLgAECn8pAAIGAAgJoBQ3UADxAQAGAAgJoBQ3UADxAQAAAA==.Derpatron:BAAALgAECggJEAAAAA==.Destruction:BAABLgAECn8WAAIMAAgJuAWHJgC+AAAMAAgJuAWHJgC+AAAAAA==.Devo:BAEALgAFFAIJBAAAAA==.',
Di='Dingers:BAAALgAECggJCAABLgAECgkJGgAFAEIXAA==.Disgusti:BAAALgAECggJDwAAAA==.Divinespark:BAABLgAECn8jAAINAAgJMRXjHgCGAQANAAgJMRXjHgCGAQAAAA==.',
Dk='Dkins:BAAALgAECgIJAgAAAA==.',
Do='Dogeform:BAAALgADCgEJAQAAAA==.Doinkbigs:BAABLgAECn8iAAICAAgJXQ1oUABtAQACAAgJXQ1oUABtAQAAAA==.Doomo:BAAALgADCgYJBgABLgABCgQJBAABAAAAAA==.Dotsfired:BAAALgADCgQJBAAAAA==.Dotñtrot:BAAALgAFFAIJAgABLgAFFAMJCgALADUZAA==.',
Dr='Draeneisham:BAAALgAFFAEJAQAAAA==.Dredd:BAAALgAECgQJCAAAAA==.Drewsilla:BAAALgAECgUJCgAAAA==.Druidrose:BAAALgAECgMJAwAAAA==.Druidtrix:BAAALgADCgYJCwAAAA==.Drylogic:BAABLgAECn8qAAIIAAgJGB+0DQCtAgAIAAgJGB+0DQCtAgAAAA==.',
Du='Duckworth:BAAALgAECgEJAQAAAA==.Duruk:BAAALgAECgQJBAAAAA==.Dustbroom:BAAALgAECgEJAQAAAA==.',
Ea='Eap:BAAALgAECgcJDwAAAA==.Eazye:BAACLgAFFH8KAAIJAAMJ+wvvFwDkAAAJAAMJ+wvvFwDkAAAuAAQKfzAAAgkACAk9GxsRAAECAAkACAk9GxsRAAECAAAA.',
Eb='Ebone:BAAALgADCgMJAQAAAA==.',
Ec='Ectoscourge:BAAALgADCgcJBgAAAA==.',
Ed='Edgeffs:BAABLgAECn8eAAMOAAgJewpUMAA/AQAOAAgJHAlUMAA/AQAPAAUJZQj5JADFAAAAAA==.',
Ek='Eklipse:BAAALgADCgMJAwABLgABCgQJBAABAAAAAA==.',
El='Elentiya:BAABLgAECn8gAAMNAAkJ6RqYDgB1AgANAAkJ6RqYDgB1AgAQAAEJegd7WgAtAAAAAA==.Elphzz:BAABLgAECn8UAAIRAAgJ+BL1HgADAgARAAgJ+BL1HgADAgAAAA==.',
Em='Emoose:BAAALgAECgEJAQAAAA==.',
Er='Eriius:BAAALgAECgUJDQAAAA==.',
Ev='Evestar:BAAALgADCgEJAQAAAA==.',
Ez='Ez:BAACLgAFFH8UAAMSAAYJWRhVDwDzAAASAAUJ6hJVDwDzAAATAAIJuBk+SACkAAAuAAQKfyoAAxIACAnlH6UYAGcCABIACAnlH6UYAGcCABMAAgmXDanKAEQAAAAA.Ezarath:BAABLgAECn8XAAIUAAYJGAVuEAC+AAAUAAYJGAVuEAC+AAAAAA==.',
Fa='Fadedaf:BAABLgAECn8UAAIEAAYJjQ15iwC2AAAEAAYJjQ15iwC2AAAAAA==.',
Fe='Felenn:BAAALgADCgYJDQABLgAECgYJGQAGAJcFAA==.Felorc:BAAALgAECgYJCwAAAA==.Feyla:BAAALgAECgUJCQAAAA==.',
Fo='Foofs:BAAALgADCgUJBQAAAA==.Foulmuffn:BAAALgADCgYJCQAAAA==.Foulplay:BAAALgADCgMJAwAAAA==.Fovos:BAAALgAECgEJAQAAAA==.',
Fr='Freakonleash:BAABLgAECn8YAAIOAAgJ/Rn7GQB8AgAOAAgJ/Rn7GQB8AgAAAA==.',
Fu='Fuegodotz:BAAALgADCgUJBQABLgAECgkJIgAVABYdAA==.Fumonkchu:BAAALgADCgIJAQAAAA==.',
Ga='Ganjåfarian:BAAALgAECgIJAgAAAA==.',
Ge='Gekatta:BAAALgAECgYJEAAAAA==.Gelektrael:BAABLgAECn8jAAMCAAgJjgtqWwBPAQACAAgJ0ApqWwBPAQADAAEJXAz9dQAvAAAAAA==.',
Gh='Ghostwarrior:BAAALgADCgMJAwABLgAFFAQJBwAGAOYXAA==.Ghostzz:BAACLgAFFH8HAAIGAAQJ5heJFABrAQAGAAQJ5heJFABrAQAuAAQKf0wAAwYACQl7I8UFABcDAAYACQl7I8UFABcDABYABQkSHloSAEsBAAAA.',
Gl='Glzygldiator:BAACLgAFFH8OAAIVAAMJ1BhXLgDhAAAVAAMJ1BhXLgDhAAAuAAQKfykAAhUACAkWHzwmACUCABUACAkWHzwmACUCAAAA.',
Gn='Gnomelock:BAAALgAFFAEJAQABLgAFFAEJAgABAAAAAA==.',
Go='Gobblin:BAAALgAECgUJDQAAAA==.Gotbandaids:BAAALgAECgEJAQAAAA==.Govegan:BAAALgADCgQJBwAAAA==.',
Gr='Graavey:BAAALgAECgcJAwABLgAFFAMJCgALADUZAA==.Greyhairs:BAAALgAECgYJDwAAAA==.Grimthor:BAAALgAECgcJBwAAAA==.Grippy:BAACLgAFFH8HAAIEAAMJRwaZSADAAAAEAAMJRwaZSADAAAAuAAQKfyYAAgQACAl/HUoiAIQCAAQACAl/HUoiAIQCAAAA.Gromit:BAACLgAFFH8UAAINAAYJfBWPAwDHAQANAAYJfBWPAwDHAQAuAAQKfyQAAw0ACQlNIZMDACEDAA0ACQlNIZMDACEDABAAAgmnEUdKAG0AAAAA.Grym:BAAALgADCgcJDgAAAA==.',
Gu='Gustófwind:BAABLgAECn8dAAMXAAkJGSC2AwDsAgAXAAkJGSC2AwDsAgAYAAMJyxL4RQC5AAAAAA==.',
Ha='Haldire:BAAALgAECgIJBwAAAA==.Harrypotture:BAAALgADCgEJAQAAAA==.Haschel:BAABLgAECn8pAAMPAAkJPB1PBQBrAgAPAAkJHB1PBQBrAgAZAAMJ9Q6JOACFAAAAAA==.',
He='Hexerfender:BAAALgAECgUJBQAAAA==.Heypal:BAAALgADCgUJCwAAAA==.',
Ho='Hofarmer:BAABLgAECn8VAAIaAAkJ5hKgDQCfAQAaAAkJ5hKgDQCfAQAAAA==.Holychris:BAAALgADCgEJAQAAAA==.Holycöw:BAAALgADCgkJCQAAAA==.Holywood:BAAALgAECgYJBwAAAA==.',
Hu='Hurtak:BAAALgAECgYJCQAAAA==.',
Hy='Hycisan:BAABLgAECn8eAAIbAAgJIxtADgBpAgAbAAgJIxtADgBpAgAAAA==.',
Ic='Icanlust:BAAALgADCgIJAgAAAA==.Icant:BAAALgADCgEJAgABLgADCgQJBQABAAAAAA==.Icon:BAAALgAECgMJAwAAAA==.Icydoodad:BAAALgADCgQJBAABLgADCgUJBQABAAAAAA==.',
Ig='Ignis:BAAALgADCgMJAwAAAA==.',
Is='Iskaru:BAAALgAECgEJAQABLgAECgYJCQABAAAAAA==.',
Ja='Jacklawin:BAAALgAECgMJAwAAAA==.Jasmyn:BAAALgADCgMJAwAAAA==.',
Jb='Jbirdlol:BAAALgADCgUJBAAAAA==.',
Je='Jesse:BAAALgAECgYJEAABLgAFFAIJBwAbAHYXAA==.Jetmage:BAABLgAECn8gAAIcAAkJRiToAADgAgAcAAkJRiToAADgAgAAAA==.',
Ji='Jire:BAAALgAECgUJDQAAAA==.Jittkal:BAAALgADCgMJAwAAAA==.',
Jo='Josh:BAAALgADCgMJAgAAAA==.',
Jp='Jpally:BAABLgAECn8XAAMbAAcJ1wYcOgARAQAbAAcJ1wYcOgARAQAGAAUJSwRA7AC3AAAAAA==.',
Ju='Jurassthicc:BAAALgAECgEJAwAAAA==.',
Jw='Jwøww:BAAALgADCgEJAgABLgADCgQJBQABAAAAAA==.',
Ka='Kafka:BAAALgADCgcJBgAAAA==.Kanastra:BAABLgAECn8cAAIEAAgJtR2QGgA0AgAEAAgJtR2QGgA0AgABLgAFFAMJCgAFANgVAA==.Karraa:BAABLgAECn8fAAIZAAgJeRcWDQDMAQAZAAgJeRcWDQDMAQAAAA==.Katil:BAAALgAECgEJAQAAAA==.Kaylib:BAABLgAECn8kAAIcAAgJAQzSAwBwAQAcAAgJAQzSAwBwAQAAAA==.',
Ke='Kea:BAAALgADCgIJAgABLgAECgUJCQABAAAAAA==.Kerze:BAABLgAECn8UAAIZAAYJlhGyHAABAQAZAAYJlhGyHAABAQAAAA==.Kesatrix:BAABLgAECn8eAAIYAAcJAw96LQA6AQAYAAcJAw96LQA6AQAAAA==.Kesi:BAAALgADCgQJBAAAAA==.',
Kh='Khai:BAAALgAECgQJBAAAAA==.Khazador:BAAALgADCgkJEgABLgAECggJGAACAHsXAA==.Khaztharion:BAAALgADCggJCAABLgAECggJGAACAHsXAA==.Khendrick:BAAALgAECgcJEwAAAA==.',
Ki='Kimsmage:BAAALgADCgYJBgAAAA==.Kith:BAAALgAECgEJAgAAAA==.Kitridge:BAAALgAECgcJBwAAAA==.Kittykatt:BAABLgAECn8qAAIHAAgJYByLDgAjAgAHAAgJYByLDgAjAgAAAA==.',
Ko='Kolchak:BAAALgADCgYJDQAAAA==.Korel:BAAALgAECgYJCgAAAA==.',
Kr='Kraggo:BAAALgAECgYJCQAAAA==.Krimzin:BAACLgAFFH8PAAIGAAQJMh48EgB1AQAGAAQJMh48EgB1AQAuAAQKfxwAAwYACQlnIc4XANoCAAYACAkOIc4XANoCABsABQlTD4ZKALsAAAAA.',
Ku='Kumala:BAAALgAECgMJBQAAAA==.',
Ky='Kylea:BAAALgAECgQJBAAAAA==.',
La='Laffiel:BAAALgADCgQJBAAAAA==.Landoh:BAABLgAECn8jAAIKAAgJYCJAGgCEAgAKAAgJYCJAGgCEAgAAAA==.Larsen:BAABLgAECn8jAAIdAAgJcR76EgAFAgAdAAgJcR76EgAFAgAAAA==.',
Le='Leap:BAAALgAECgYJDgAAAA==.Lefthorn:BAAALgADCgIJAgAAAA==.Lenneth:BAAALgAECgIJAgAAAA==.',
Li='Lightofdawn:BAAALgAECgMJAwAAAA==.Lightstyle:BAAALgADCgMJAwAAAA==.Lilow:BAABLgAECn8rAAIJAAkJ+xFTFADdAQAJAAkJ+xFTFADdAQAAAA==.',
Ll='Llarker:BAABLgAECn8ZAAMGAAYJlwUvuwDBAAAGAAYJjwUvuwDBAAAWAAYJSwGPLwBcAAAAAA==.',
Lo='Lockendron:BAAALgADCgQJBAAAAA==.Locketharion:BAAALgADCgQJBAAAAA==.Lockpebbles:BAAALgADCgMJAwAAAA==.Lokomachina:BAABLgAECn8UAAITAAcJLyETHwBLAgATAAcJLyETHwBLAgAAAA==.Lonesdove:BAAALgADCgEJAQAAAA==.',
Lu='Luminia:BAAALgADCgcJDwAAAA==.Lunacy:BAAALgAECgEJAQAAAA==.',
Ly='Lynngosa:BAAALgAECgQJBAAAAA==.Lyrana:BAAALgADCgQJBAAAAA==.Lyrasa:BAAALgADCgQJBAAAAA==.',
Ma='Maelidrael:BAAALgAECgIJAgABLgAECggJLQAKAEMbAA==.Magisterium:BAABLgAECn8ZAAINAAYJiANYUwDqAAANAAYJiANYUwDqAAAAAA==.Malady:BAABLgAECn8jAAIJAAgJbSEWEAAOAgAJAAgJbSEWEAAOAgAAAA==.Malakyde:BAAALgADCgMJAwAAAA==.Malt:BAABLgAECn8ZAAIEAAgJuyDQJwDmAQAEAAgJuyDQJwDmAQAAAA==.Malthorial:BAAALgADCgEJAQAAAA==.Mario:BAAALgAFFAEJAgAAAA==.Mattenom:BAAALgADCgYJCAAAAA==.Maulware:BAAALgADCgEJAQAAAA==.',
Mb='Mbrodh:BAAALgAECgQJBAAAAA==.Mbrosmites:BAAALgAECgIJAwAAAA==.',
Md='Mdeag:BAAALgAECgMJBgAAAA==.',
Me='Mefistofeles:BAACLgAFFH8FAAIRAAMJLw46GgDsAAARAAMJLw46GgDsAAAuAAQKfxsAAhEACAl/F6oTALEBABEACAl/F6oTALEBAAAA.Meingaree:BAAALgAECgYJDQAAAA==.Merlinus:BAABLgAECn8lAAIGAAcJ4gq0lABTAQAGAAcJ4gq0lABTAQAAAA==.Merton:BAAALgADCggJDAAAAA==.',
Mi='Mightyguzz:BAABLgAECn8zAAIZAAgJqg+SFABaAQAZAAgJqg+SFABaAQAAAA==.Mitchelle:BAAALgAECgMJBQAAAA==.',
Mo='Moomkin:BAABLgAECn8oAAIHAAgJgwwMKAA1AQAHAAgJgwwMKAA1AQAAAA==.',
My='Mythicblade:BAAALgADCgEJAQAAAA==.',
['Mø']='Møønchild:BAAALgAECgMJAwAAAA==.',
Na='Nai:BAAALgAECgQJDAAAAA==.Nanaish:BAAALgADCgIJAgAAAA==.Narpul:BAABLgAECn8mAAIWAAgJNxtHDgCIAQAWAAgJNxtHDgCIAQAAAA==.Natë:BAACLgAFFH8OAAIZAAMJOhipEQDQAAAZAAMJOhipEQDQAAAuAAQKfzAAAhkACQkvIWUDACMDABkACQkvIWUDACMDAAAA.Nazend:BAAALgADCgQJBAAAAA==.',
Ne='Necrotalon:BAAALgAECgYJDAAAAA==.Nelosi:BAAALgAECgMJCAAAAA==.Neondh:BAACLgAFFH8KAAIEAAMJYSPFJQA1AQAEAAMJYSPFJQA1AQAuAAQKfywAAgQACAmSJA4NABcDAAQACAmSJA4NABcDAAAA.Nerzhùl:BAABLgAECn8iAAIdAAkJwgj+KQBLAQAdAAkJwgj+KQBLAQAAAA==.',
Nh='Nharuna:BAABLgAECn8jAAITAAgJJxHNPgCSAQATAAgJJxHNPgCSAQAAAA==.',
Ni='Nickolaos:BAAALgAECgEJAQAAAA==.Nieloriel:BAABLgAECn8oAAMbAAgJBBOzMAC+AQAbAAgJBBOzMAC+AQAGAAgJcgbj0ADoAAAAAA==.Nightwishing:BAAALgAECgQJBAAAAA==.Niupiadps:BAAALgAECgIJAgAAAA==.Niykee:BAABLgAECn8fAAQeAAgJXyKEBADpAQARAAcJPiKmHAAaAgAfAAcJDx5mBgARAgAeAAUJ3COEBADpAQAAAA==.',
No='Noboundss:BAAALgAECgcJEgAAAA==.Nobóunds:BAAALgAECgkJDwAAAA==.Nomnoms:BAAALgAECgYJDgAAAA==.Nomoreheals:BAAALgAECgYJBwAAAA==.Notkarl:BAAALgAECgIJAwAAAA==.Nowimpissed:BAACLgAFFH8NAAMgAAMJ9x+HEAANAQAgAAMJ9x+HEAANAQATAAEJvyDWHgBkAAAuAAQKfxUABCAABgnGHssMABgCACAABgnGHssMABgCABMABAkPFsp5APoAABIABAnmDzBbANcAAAAA.Noztra:BAACLgAFFH8FAAIKAAMJbASRYwDUAAAKAAMJbASRYwDUAAAuAAQKfx4AAgoABwkSDjC1AHUBAAoABwkSDjC1AHUBAAAA.',
Nu='Nuker:BAAALgAECgEJAQAAAA==.',
Ny='Nysrogh:BAAALgAECgUJDQABLgAFFAQJCwAIAPsSAA==.',
Ob='Obsideon:BAAALgAECggJEwAAAA==.',
Oh='Ohgr:BAAALgAECgUJBQAAAA==.Ohshifty:BAABLgAECn80AAMHAAkJ0xCtGQClAQAHAAkJ0xCtGQClAQAIAAQJbASwgwBtAAAAAA==.',
Ol='Olan:BAAALgAECgYJBgAAAA==.Olie:BAABLgAECn8bAAITAAgJ9wkBTgBgAQATAAgJ9wkBTgBgAQAAAA==.',
Or='Orbsicles:BAAALgAECggJEAAAAA==.',
Ou='Ouragan:BAAALgAECgEJAQAAAA==.',
Pa='Paedrig:BAAALgADCgIJAgAAAA==.Papitomyrey:BAABLgAECn8eAAMOAAgJviT9BgCyAgAOAAgJviT9BgCyAgAPAAUJYh0XIgD0AAABLgAECgkJJQAXAG0fAA==.Paramedic:BAAALgADCgIJAgAAAA==.Passtheflask:BAABLgAECn8eAAICAAcJGQfBhAD0AAACAAcJGQfBhAD0AAAAAA==.',
Pe='Perdition:BAAALgAECgEJAQAAAA==.Pestílence:BAACLgAFFH8JAAIVAAMJHBh5fQBkAAAVAAMJHBh5fQBkAAAuAAQKfz8AAxUACQkyIiINAMoCABUACQkyIiINAMoCAAwAAQnEEZBHACoAAAAA.',
Ph='Phaesphoros:BAABLgAECn8dAAILAAkJXxCwNACCAQALAAkJXxCwNACCAQAAAA==.Phenor:BAAALgAECgQJBAAAAA==.',
Po='Poe:BAAALgADCgYJBgABLgAECgcJFQAKAOEXAA==.Powpow:BAABLgAECn8XAAIRAAYJdhUVHwA/AQARAAYJdhUVHwA/AQAAAA==.',
Pr='Prejudice:BAABLgAECn8cAAIbAAgJ/RSDGgDmAQAbAAgJ/RSDGgDmAQAAAA==.Primévil:BAAALgADCgEJAQABLgAECggJJQAdANUXAA==.Prowlcow:BAABLgAECn8lAAIIAAgJ+Bf8GwAfAgAIAAgJ+Bf8GwAfAgAAAA==.',
Ps='Psychosis:BAABLgAECn8uAAIVAAkJ4h3HFgB+AgAVAAkJ4h3HFgB+AgAAAA==.',
Pu='Putrescence:BAAALgADCgEJAQAAAA==.',
['Pû']='Pûff:BAAALgAECgcJDwAAAA==.',
Qm='Qmpel:BAAALgADCgMJAwAAAA==.',
Ra='Raiiz:BAACLgAFFH8IAAIKAAMJBBBmLAAFAQAKAAMJBBBmLAAFAQAuAAQKfyYAAgoACAkhHI4/AHoCAAoACAkhHI4/AHoCAAAA.Rainhoof:BAABLgAECn8jAAMhAAgJOhkcBwANAgAhAAgJOhkcBwANAgAIAAUJYAiAhwDHAAAAAA==.Ralneth:BAACLgAFFH8VAAMFAAgJphBtBAAyAgAFAAcJgRBtBAAyAgAUAAMJABnoAwAOAQAuAAQKfyQAAxQACAmrIFADAOsCABQACAmfH1ADAOsCAAUABgnYG0IYAA8CAAAA.Randomtask:BAAALgADCgUJBgAAAA==.Rapala:BAABLgAECn8iAAICAAkJXBxAEwB9AgACAAkJXBxAEwB9AgAAAA==.Rapalaa:BAAALgAECgIJAwABLgAECgkJIgACAFwcAA==.Raspútin:BAABLgAECn8pAAMiAAgJihalFgC4AQAiAAgJihalFgC4AQAXAAQJ8AfVVQC5AAAAAA==.Rawkfice:BAAALgADCggJEwAAAA==.',
Re='Renfield:BAAALgADCgYJBwAAAA==.Revok:BAAALgAECgcJCwAAAA==.Revoker:BAAALgADCgYJCAAAAA==.',
Ri='Riordan:BAAALgAFFAEJAgAAAA==.Rivvetear:BAAALgADCgYJBgAAAA==.',
Rj='Rjolz:BAACLgAFFH8HAAIVAAMJOyFZRgDeAAAVAAMJOyFZRgDeAAAuAAQKfzMAAhUACQndJYgBAHADABUACQndJYgBAHADAAAA.',
Ro='Roflchopr:BAAALgADCgEJAQAAAA==.Rootzi:BAAALgAECgIJAwABLgAECgkJIgAVABYdAA==.Rootzidk:BAABLgAECn8iAAIVAAgJFh1EMwDtAQAVAAgJFh1EMwDtAQAAAA==.',
Ru='Rucks:BAABLgAECn8iAAMXAAgJORqTGACdAQAXAAgJbBGTGACdAQAiAAYJzBokJwA6AQAAAA==.',
Sa='Saelem:BAAALgAECgYJBgAAAA==.Sandalfon:BAAALgAECgYJCwAAAA==.Sanleron:BAAALgAECgQJBAAAAA==.Sarith:BAAALgAECgEJAQAAAA==.Saske:BAAALgADCgMJBwABLgAECgEJAQABAAAAAA==.',
Sc='Scargon:BAAALgAECgQJBwAAAA==.',
Se='Selidori:BAAALgADCgYJBgAAAA==.Seralicht:BAACLgAFFH8RAAINAAYJLxUKAwDaAQANAAYJLxUKAwDaAQAuAAQKfxoAAw0ACAkOHRwQAGUCAA0ACAkOHRwQAGUCAAkAAQmKC+9hADQAAAAA.',
Sh='Shaliri:BAAALgADCgEJBAAAAA==.Shamanata:BAAALgADCgIJAgAAAA==.Sharayse:BAABLgAECn8hAAIKAAkJWgx/TQCyAQAKAAkJWgx/TQCyAQAAAA==.Sharmee:BAAALgAECgYJBwAAAA==.Shockohôlic:BAABLgAECn8lAAQdAAgJ1RdlFwDYAQAdAAgJ1RdlFwDYAQALAAYJTxCeSwBUAQAjAAEJoAphKwA4AAAAAA==.Shocky:BAAALgAECgcJCgAAAA==.',
Sk='Skullkìng:BAABLgAECn8jAAIVAAkJuhSKMgDwAQAVAAkJuhSKMgDwAQAAAA==.',
Sl='Slingablade:BAABLgAECn8dAAMEAAkJ/REOMQC5AQAEAAkJcBEOMQC5AQAkAAEJ2BJnSAA5AAAAAA==.',
Sm='Smashnskullz:BAAALgAECgQJBgABLgAECgUJBQABAAAAAA==.',
Sn='Sniffsniff:BAACLgAFFH8JAAIGAAMJxyWaIgBAAQAGAAMJxyWaIgBAAQAuAAQKfykAAwYACAlHJQYKAEEDAAYACAlHJQYKAEEDABsAAQnCHklkAFEAAAAA.',
So='Solvi:BAABLgAECn8fAAIIAAcJ9heRRAA2AQAIAAcJ9heRRAA2AQAAAA==.Sonira:BAAALgADCgMJBQAAAA==.Soulbrand:BAABLgAECn8jAAIJAAgJiQkxJwA/AQAJAAgJiQkxJwA/AQAAAA==.Southpawclaw:BAAALgAECgEJAQABLgAECggJFwAjAPAfAA==.',
Sp='Spellz:BAABLgAECn8dAAIJAAcJOx7iEQD4AQAJAAcJOx7iEQD4AQAAAA==.Spuggle:BAAALgAECgQJBAAAAA==.',
St='Stabathuh:BAAALgADCgYJBgAAAA==.Starman:BAAALgAECgkJCQAAAA==.Stoopidrood:BAAALgADCgQJBAABLgADCgUJBQABAAAAAA==.Stoopidtroll:BAAALgADCgUJBQAAAA==.Stormclaw:BAABLgAECn8bAAIlAAgJ/wvtCwBEAQAlAAgJ/wvtCwBEAQAAAA==.Straeka:BAAALgAECgIJAgAAAA==.',
Su='Sufiya:BAABLgAECn8gAAITAAkJLw80NAC7AQATAAkJLw80NAC7AQAAAA==.Suhwoo:BAAALgAECgcJDwAAAA==.Sumig:BAAALgADCgEJBAAAAA==.',
Sy='Sylvershadow:BAABLgAECn8aAAITAAcJgA9mUQBWAQATAAcJgA9mUQBWAQAAAA==.Sym:BAAALgADCgcJCQAAAA==.',
Ta='Taintedsoulv:BAAALgADCgUJBgAAAA==.Taliri:BAAALgADCgEJAQABLgADCgQJBQABAAAAAA==.Tandarilada:BAAALgAFFAEJBAAAAA==.Tanknspankn:BAAALgAECgUJBwAAAA==.Tankurface:BAAALgAECgEJAQAAAA==.',
Th='Thalvint:BAACLgAFFH8FAAIPAAIJEB/VFQC2AAAPAAIJEB/VFQC2AAAuAAQKfzIAAw8ACQlXI0oBABsDAA8ACQlXI0oBABsDAA4ABgnVEiJbAEIBAAAA.Theblackhand:BAABLgAECn8dAAMdAAYJ1RXTSgAcAQAdAAUJaxPTSgAcAQALAAYJrQ//UwD+AAAAAA==.Thefira:BAAALgADCgkJCQAAAA==.Thickdk:BAABLgAECn8aAAIVAAgJHRZTbgCtAQAVAAgJHRZTbgCtAQAAAA==.Thoriel:BAAALgAECgEJAgAAAA==.',
Ti='Timefall:BAAALgAECgkJDgAAAA==.Titanic:BAAALgAECgcJEAAAAA==.',
To='Tomcruise:BAAALgAECggJDgABLgAECgkJGgAFAEIXAA==.Toshiro:BAAALgADCgcJBwAAAA==.Totemlyawsum:BAABLgAFFH8FAAIdAAIJ1QbqLgB6AAAdAAIJ1QbqLgB6AAAAAA==.Touchymcfeel:BAAALgADCgMJAwAAAA==.',
Tr='Trckr:BAAALgADCgIJAgAAAA==.Treeiage:BAAALgAECgUJCAAAAA==.Trooblu:BAAALgAECgYJEgAAAA==.',
Tw='Twotone:BAAALgAECgEJAQAAAA==.',
['Té']='Téz:BAAALgAECgYJDAAAAA==.',
['Tê']='Têzeret:BAAALgAECgEJAgAAAA==.',
Ul='Ulkthar:BAABLgAECn8wAAIOAAgJ2BPKKAAZAgAOAAgJ2BPKKAAZAgAAAA==.Ultrauchuva:BAAALgADCgEJAQAAAA==.',
Va='Vanarn:BAAALgADCgEJAQABLgADCgQJBQABAAAAAA==.Vanlin:BAABLgAECn8jAAIIAAgJTx44EQCDAgAIAAgJTx44EQCDAgAAAA==.',
Ve='Vexxdr:BAABLgAECn8fAAIIAAgJHBLXOQC+AQAIAAgJHBLXOQC+AQAAAA==.Vexxs:BAAALgAECgYJEAABLgAECggJHwAIABwSAA==.',
Vi='Virtey:BAAALgADCgUJBQAAAA==.Virtuous:BAAALgADCgYJBwAAAA==.',
Vl='Vladzy:BAAALgADCgcJAwAAAA==.',
Vo='Voidsuzu:BAAALgAECgMJAwABLgAECggJLAAWALAUAA==.Vormedicus:BAAALgAECgIJAgABLgAECggJKQAiAIoWAA==.',
Vu='Vulperas:BAABLgAECn8lAAIdAAkJJg4dKQBRAQAdAAkJJg4dKQBRAQAAAA==.',
Vy='Vynastallan:BAABLgAECn8cAAMTAAcJhSNZHQAoAgATAAcJhSNZHQAoAgASAAEJehfShgA1AAAAAA==.Vyper:BAEBLgAECn8lAAIFAAgJchnBFQDhAQAFAAgJchnBFQDhAQABLgAFFAIJBAABAAAAAA==.',
Wa='Waroo:BAABLgAECn8cAAIHAAgJ7g3WIgBYAQAHAAgJ7g3WIgBYAQAAAA==.',
We='Wellcole:BAAALgADCgYJBgAAAA==.Wenden:BAAALgAFFAEJAQAAAA==.Wengo:BAAALgADCgkJCgAAAA==.',
Wi='Wilbert:BAAALgADCgEJAQAAAA==.Winniethepo:BAAALgAECgQJBAAAAA==.Witherflow:BAAALgAECgIJAgAAAA==.',
Wo='Woodey:BAAALgADCgcJCAAAAA==.',
Wu='Wulffric:BAAALgAECgYJDwAAAA==.',
Xe='Xeo:BAAALgADCgMJAwAAAA==.',
Ya='Yachirú:BAABLgAECn8sAAIWAAgJsBS4DQCSAQAWAAgJsBS4DQCSAQAAAA==.',
Yi='Yiang:BAABLgAECn8mAAIXAAkJ3B1jBQC+AgAXAAkJ3B1jBQC+AgAAAA==.',
Yl='Ylndrysa:BAABLgAECn85AAMIAAgJWxiCIAD+AQAIAAgJWxiCIAD+AQAHAAMJoRgjOwDNAAAAAA==.',
Yt='Ytho:BAAALgADCgYJBgAAAA==.',
Za='Zalithar:BAAALgAECgkJDgAAAA==.',
Ze='Zedrock:BAABLgAECn8tAAIKAAgJQxs8KwAsAgAKAAgJQxs8KwAsAgAAAA==.Zekodian:BAAALgADCgcJDQAAAA==.Zentner:BAABLgAECn8qAAMHAAgJYR+lCwBPAgAHAAgJYR+lCwBPAgAaAAQJPAodJAB8AAAAAA==.Zeropistol:BAABLgAECn8aAAIKAAgJNAMBoQABAQAKAAgJNAMBoQABAQAAAA==.Zexrous:BAAALgADCgEJAQAAAA==.',
Zh='Zhas:BAAALgAECgYJDwAAAA==.',
Zu='Zuro:BAABLgAECn8YAAMTAAgJzA07SgBrAQATAAgJzA07SgBrAQASAAEJCgHPmQAaAAAAAA==.',
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
