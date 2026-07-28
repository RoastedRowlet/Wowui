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

local lookup = {'Monk-Windwalker','Hunter-Survival','Hunter-BeastMastery','Priest-Holy','Rogue-Subtlety','Priest-Discipline','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Augmentation','Unknown-Unknown','Shaman-Restoration','Paladin-Retribution','Druid-Balance','DemonHunter-Havoc','Druid-Restoration','Shaman-Elemental','Warlock-Affliction','Mage-Frost','Paladin-Holy','DeathKnight-Blood','Druid-Feral','Warrior-Fury','Warrior-Arms','Hunter-Marksmanship','Evoker-Devastation','DeathKnight-Frost','Paladin-Protection','Monk-Mistweaver','Warrior-Protection','Druid-Guardian','Mage-Fire','Rogue-Outlaw','Evoker-Preservation','Rogue-Assassination','DemonHunter-Vengeance','Monk-Brewmaster','Shaman-Enhancement',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=46,date='2026-07-28',data={Ab='Ablestract:BAAALgAECgMJAwAAAA==.',
Ac='Achilios:BAAALgAECggJCQAAAA==.Acid:BAAALgAECggJEQAAAA==.',
Ad='Adam:BAAALgAFFAEJAgABLgAFFAEJBQABAB4mAA==.Adanikke:BAAALgAECgcJCQAAAA==.Adreane:BAAALgAECgMJBAAAAA==.',
Af='Aftrlyfe:BAAALgAECgkJCQAAAA==.',
Ai='Aiyana:BAAALgADCgkJEQAAAA==.',
Ak='Akamma:BAABLgAECn8UAAMCAAcJ2wnSCACXAAADAAcJ2wlJlAAXAQACAAQJqgXSCACXAAAAAA==.Akarimos:BAAALgADCgMJAwAAAA==.',
Al='Alealle:BAAALgADCgMJAwAAAA==.Algeriono:BAAALgAECgcJDgAAAA==.Aliluna:BAAALgAFFAEJAwAAAA==.Alirain:BAAALgAFFAEJAgAAAA==.Alispere:BAAALgADCgUJBQAAAA==.Aliwings:BAAALgAFFAEJAgAAAA==.Alizaranna:BAAALgADCgEJAQABLgAECgYJJAAEAJEaAA==.',
Am='Amarokk:BAABLgAECn8oAAICAAkJpAwzBAAuAQACAAkJpAwzBAAuAQAAAA==.Ameliae:BAAALgAECgEJAQAAAA==.',
An='Ancestor:BAABLgAECn8bAAIFAAcJjxPDIQCHAQAFAAcJjxPDIQCHAQAAAA==.Anish:BAAALgAECgEJAQAAAA==.',
Aq='Aqurore:BAAALgADCgYJBgAAAA==.',
Ar='Archaia:BAAALgAECgUJCQAAAA==.Argorok:BAAALgAFFAEJAQAAAA==.Aryi:BAABLgAECn8VAAQGAAkJIAczSADlAAAGAAgJiwUzSADlAAAEAAMJZgm8WAB3AAAHAAIJvQRTfQBDAAAAAA==.',
As='Askim:BAAALgADCgcJBwAAAA==.Assyla:BAAALgAECgEJAQAAAA==.Astraeos:BAABLgAFFH8HAAIIAAMJKx6AZgD5AAAIAAMJKx6AZgD5AAAAAA==.',
At='Atherionn:BAAALgADCgEJAgAAAA==.',
Au='Auv:BAACLgAFFH8QAAMIAAQJESaEBwCtAQAIAAQJESaEBwCtAQAJAAEJlQBjGwA6AAAuAAQKfxQAAwkABwmJJkMTALEBAAgABQkZJl9MAOMBAAkABAkgJkMTALEBAAEuAAUUBgkPAAoADCQA.',
Av='Avarii:BAAALgAECgEJAgAAAA==.',
Aw='Awekeha:BAAALgADCgIJAgAAAA==.',
Ax='Axël:BAAALgAFFAEJAQABLgAFFAMJBwALAKsaAA==.',
Ay='Aylranoa:BAAALgADCgkJCQAAAA==.',
Az='Azimondius:BAACLgAFFH8bAAIMAAUJCRoTJQA8AQAMAAUJCRoTJQA8AQAuAAQKfzoAAgwACQlyIYgFAAcDAAwACQlyIYgFAAcDAAAA.Azmora:BAAALgAECgcJDwAAAA==.Azzix:BAAALgADCgQJBQABLgAECgEJAQANAAAAAA==.',
['Aí']='Aímee:BAAALgAECgEJAgAAAA==.',
Ba='Baddragons:BAAALgADCgYJBgAAAA==.Bandit:BAAALgAECgEJAQAAAA==.Bastis:BAAALgAECgEJBAABLgAFFAQJFAAOANAmAA==.Batreaux:BAAALgAFFAEJAgAAAA==.',
Be='Beaman:BAAALgADCgEJAQAAAA==.Bearkake:BAAALgAECgMJBgAAAA==.Bellgrande:BAAALgADCgYJBgAAAA==.Belthora:BAAALgAECgYJCAAAAA==.Bepallylol:BAACLgAFFH8PAAIPAAUJ2hMkIgB/AQAPAAUJ2hMkIgB/AQAuAAQKfxkAAg8ACAlyH7EtAGwCAA8ACAlyH7EtAGwCAAAA.',
Bh='Bhindi:BAAALgAECgMJAwABLgAFFAMJBgAQAJ4LAA==.',
Bi='Bigkeith:BAAALgADCgEJAQAAAA==.Biraj:BAAALgADCggJEAABLgAECgcJLwAPAP8IAA==.',
Bl='Blanká:BAAALgADCgEJAQAAAA==.Blaqichan:BAAALgADCgEJAwABLgAECgEJAQANAAAAAA==.Blastøise:BAAALgAFFAEJAQAAAA==.Blight:BAAALgADCgcJBQAAAA==.Bloodybecky:BAAALgAECgQJBQAAAA==.',
Bo='Boahancawk:BAAALgADCgkJCQAAAA==.',
Br='Brakiyamis:BAAALgAECgEJAgAAAA==.Brewmastah:BAAALgAECgYJDAABLgAECgUJBwANAAAAAA==.Briarynth:BAAALgAECgEJAQAAAA==.Bristlebane:BAAALgADCgEJAQAAAA==.Browntotem:BAAALgADCgUJCAAAAA==.',
Bu='Bubblecheeks:BAAALgAECgQJBQAAAA==.Bubblehëarth:BAAALgAECgYJDwAAAA==.Bubby:BAABLgAECn8WAAIIAAcJPx2OQQAIAgAIAAcJPx2OQQAIAgAAAA==.Bucklebunnie:BAAALgADCgEJAQABLgAFFAUJEQARAFQYAA==.Bulgestomper:BAAALgAECgcJDQAAAA==.Bullzaye:BAAALgAECgQJBAAAAA==.Burbuja:BAABLgAECn8ZAAIEAAgJKBGiMgA/AQAEAAgJKBGiMgA/AQAAAA==.',
Ca='Cadfile:BAAALgAECgQJBgAAAA==.Caine:BAAALgAECgQJBgAAAA==.Calimari:BAAALgAECgMJAwAAAA==.Careco:BAAALgADCgYJBgAAAA==.Carpetcrumbs:BAAALgAECgUJBQAAAA==.Castr:BAAALgAFFAEJAgABLgADCgUJBQANAAAAAA==.Catnsevrmeme:BAAALgAECgQJCAAAAA==.',
Ce='Cecilio:BAAALgAECgMJAwAAAA==.Cel:BAAALgAECgEJAgAAAA==.Celzara:BAAALgAECgEJAQAAAA==.Cernunnös:BAAALgADCgUJBQAAAA==.Cetraa:BAACLgAFFH8GAAMQAAMJngsJNQCrAAAQAAMJngsJNQCrAAASAAEJtRgJagBHAAAuAAQKfysAAxAACQm7GvINAHsCABAACQm7GvINAHsCABIAAQkTDmfYACwAAAAA.',
Ch='Chastise:BAAALgAECgkJEwAAAA==.Chewÿ:BAAALgAECgcJBAAAAA==.Chii:BAAALgADCgEJAQAAAA==.Chocobro:BAAALgAECgYJCQAAAA==.Chäös:BAAALgAECgUJBQAAAA==.',
Cl='Clingy:BAAALgAECgQJCQAAAA==.',
Co='Cobble:BAACLgAFFH8IAAITAAMJvQoEOgCnAAATAAMJvQoEOgCnAAAuAAQKfx0AAhMACAkTGNYeAOsBABMACAkTGNYeAOsBAAAA.Colhap:BAABLgAECn8ZAAIHAAcJJhzLIQDJAQAHAAcJJhzLIQDJAQAAAA==.Conjure:BAACLgAFFH8LAAMUAAMJ1g+WBQDOAAAUAAMJ1g+WBQDOAAAIAAEJ8gJb0gA4AAAuAAQKfzQAAwkACAlOF2gIAMcBAAkABwm5GWgIAMcBAAgACAmZDa+EADABAAAA.Corbina:BAABLgAECn8jAAIVAAgJ6iJ2NQCeAgAVAAgJ6iJ2NQCeAgAAAA==.Coughingbaby:BAAALgAECgEJAQAAAA==.Cousinlarry:BAAALgADCgIJAgABLgAECgEJAQANAAAAAA==.',
Cr='Cramlutin:BAAALgADCgUJBQAAAA==.Cru:BAAALgAECgkJDgAAAA==.Crui:BAAALgADCgcJBwAAAA==.',
Cu='Culligan:BAACLgAFFH8PAAIVAAMJexl0NwDdAAAVAAMJexl0NwDdAAAuAAQKf40AAhUACQlkIPICAM4CABUACQlkIPICAM4CAAAA.Cuttingcrew:BAAALgADCggJCAAAAA==.',
Cy='Cyclones:BAAALgADCgYJBgABLgAECgUJBQANAAAAAA==.Cygwin:BAABLgAECn9HAAMOAAkJ0x4hAgDAAgAOAAkJ0x4hAgDAAgATAAMJZxEmbgCfAAAAAA==.',
Da='Daarius:BAAALgADCgYJBgAAAA==.Dabswfel:BAAALgAECgUJBQAAAA==.Darcfrost:BAAALgAECgEJAgAAAA==.Darcyonys:BAAALgAECgIJBQAAAA==.Dariao:BAAALgAECgIJAgABLgAECgkJLQAKAM8ZAA==.Darkironsham:BAAALgAFFAEJAQAAAA==.Darklon:BAAALgAECgkJEwAAAA==.Darknescomez:BAAALgAECgQJCAABLgAECgkJMQATAOYYAA==.Darkpun:BAAALgADCgcJCQAAAA==.Darîus:BAAALgAECgMJAwAAAA==.Dat:BAAALgAECgcJAQABLgAFFAIJBwAVAPkYAA==.Datmage:BAACLgAFFH8HAAIVAAIJ+RjEnACSAAAVAAIJ+RjEnACSAAAuAAQKfxkAAhUABwl4H3FeAB8CABUABwl4H3FeAB8CAAAA.',
De='Deathshockz:BAAALgAECgQJBQABLgAECgUJBQANAAAAAA==.Deedeet:BAAALgAECgkJBQAAAA==.Deku:BAAALgAFFAEJAwAAAA==.Demunzz:BAAALgAECgEJAQAAAA==.Deriah:BAABLgAECn8pAAIPAAgJoBQ3UADxAQAPAAgJoBQ3UADxAQAAAA==.Derpatron:BAABLgAECn8UAAMPAAkJzgj5jgBUAQAPAAkJzgj5jgBUAQAWAAEJuQ6gkwA3AAAAAA==.Destruction:BAABLgAECn8XAAIXAAkJfQVVLQDzAAAXAAkJfQVVLQDzAAAAAA==.Devo:BAECLgAFFH8LAAIYAAQJORcGCAApAQAYAAQJORcGCAApAQAuAAQKfxYAAhgACQm9H14DAOACABgACQm9H14DAOACAAAA.',
Di='Diabelo:BAAALgAECgQJBAAAAA==.Digoxin:BAAALgAECgEJAwAAAA==.Dingers:BAAALgAECggJDwABLgAECgkJFAAPAHQYAA==.Disgusti:BAAALgAECggJEwAAAA==.Divinespark:BAABLgAECn8jAAIEAAgJMRXULACTAQAEAAgJMRXULACTAQAAAA==.',
Dk='Dkins:BAAALgAECgIJAgAAAA==.',
Do='Dogeform:BAAALgADCgEJAQAAAA==.Doinkbigs:BAABLgAECn8iAAIIAAgJXQ0ncABaAQAIAAgJXQ0ncABaAQAAAA==.Doomo:BAAALgADCgYJBgABLgABCgQJBAANAAAAAA==.Dotsfired:BAAALgADCgQJBAAAAA==.Dotñtrot:BAAALgAFFAIJAgABLgAFFAMJCwAOADUZAA==.',
Dr='Draeneisham:BAAALgAFFAEJAQAAAA==.Draethno:BAAALgAECgQJBAAAAA==.Drambush:BAAALgAECgUJBQAAAA==.Dredd:BAAALgAECgQJDQAAAA==.Drewsilla:BAABLgAECn8aAAIVAAYJ6wo+IwC4AAAVAAYJ6wo+IwC4AAAAAA==.Druidrose:BAAALgAECgMJAwAAAA==.Druidtrix:BAAALgADCgYJCwAAAA==.Drylogic:BAABLgAECn8yAAISAAkJAx+YCwAGAwASAAkJAx+YCwAGAwAAAA==.',
Du='Duckworth:BAAALgAECgEJAQAAAA==.Dulcey:BAABLgAECn8oAAMGAAkJJhVoAgBMAgAGAAkJJhVoAgBMAgAHAAUJchNxCwDoAAABLgAFFAMJBgAQAJ4LAA==.Duruk:BAABLgAECn9CAAMIAAkJEiTGAAA+AwAIAAkJEiTGAAA+AwAUAAMJOBhtCACSAAAAAA==.Dustbroom:BAAALgAECgIJAgAAAA==.',
Dy='Dynaveir:BAAALgAECgIJAgAAAA==.',
['Dà']='Dàvë:BAAALgAECgEJAQABLgAECgIJBAANAAAAAA==.',
Ea='Eap:BAAALgAECgcJDwAAAA==.Eartha:BAAALgAECgUJCAAAAA==.Eazye:BAACLgAFFH8UAAIHAAQJxxE5HgAAAQAHAAQJxxE5HgAAAQAuAAQKfzcAAgcACQlXHIEPAGMCAAcACQlXHIEPAGMCAAAA.',
Eb='Ebone:BAAALgADCgMJAQAAAA==.',
Ec='Ectoscourge:BAAALgADCgcJBgAAAA==.',
Ed='Edgeffs:BAABLgAECn8fAAMZAAkJlwoxNgBvAQAZAAkJZAkxNgBvAQAaAAUJZQj5JADFAAAAAA==.',
Ek='Eklipse:BAAALgADCgMJAwABLgABCgQJBAANAAAAAA==.',
El='Elentiya:BAABLgAECn8kAAMEAAkJvxyYDgB1AgAEAAkJvxyYDgB1AgAGAAEJegd7WgAtAAAAAA==.Elphzz:BAABLgAECn8YAAIFAAgJ+BL1HgADAgAFAAgJ+BL1HgADAgAAAA==.',
Em='Emoose:BAAALgAECgEJAQAAAA==.',
Er='Eriius:BAABLgAECn8UAAIPAAgJMBJStgAWAQAPAAgJMBJStgAWAQAAAA==.',
Ev='Evestar:BAAALgADCgEJAQAAAA==.',
Ez='Ez:BAACLgAFFH8VAAMbAAcJWBVFFQAaAQAbAAYJZhBFFQAaAQADAAIJuBksgQCXAAAuAAQKfyoAAxsACAn0H6UYAGcCABsACAn0H6UYAGcCAAMAAgmXDfwdAT4AAAAA.Ezarath:BAABLgAECn80AAIcAAkJgQxpCwBfAQAcAAkJgQxpCwBfAQAAAA==.',
Fa='Fadedaf:BAABLgAECn8UAAIKAAYJjQ3iuAC5AAAKAAYJjQ3iuAC5AAAAAA==.',
Fe='Felenn:BAAALgADCgYJDQABLgAECgcJLwAPAP8IAA==.Felorc:BAAALgAECgYJCwAAAA==.Fentun:BAAALgAFFAEJAQAAAA==.Feyla:BAAALgAECgUJCQAAAA==.',
Fi='Finnikey:BAAALgAECgIJBAAAAA==.Firstone:BAAALgADCgYJBgAAAA==.',
Fo='Foofs:BAAALgADCgUJBQAAAA==.Foulmuffn:BAAALgADCgYJCQAAAA==.Foulplay:BAAALgADCgMJAwAAAA==.Fovos:BAAALgAECgEJAQAAAA==.',
Fr='Freakonleash:BAABLgAECn8YAAIZAAgJ/Rn7GQB8AgAZAAgJ/Rn7GQB8AgAAAA==.Free:BAABLgAECn8UAAISAAgJsAlrCQANAQASAAgJsAlrCQANAQAAAA==.Frimbooze:BAAALgAECgYJBwAAAA==.',
Fu='Fuegodotz:BAAALgADCgUJBQABLgAECgkJJAALALEcAA==.Fumonkchu:BAAALgADCgIJAQAAAA==.',
['Fé']='Féarôshima:BAAALgAECgEJAQABLgAECgkJMQATAOYYAA==.',
Ga='Ganjåfarian:BAAALgAECgIJAgAAAA==.',
Gd='Gdayum:BAAALgAECgMJAwAAAA==.',
Ge='Gekatta:BAAALgAECgYJEAAAAA==.Gelektrael:BAABLgAECn8kAAMIAAkJuA3XewBBAQAIAAgJ0QrXewBBAQAJAAIJnBQoMgBWAAAAAA==.Getchya:BAAALgAECgEJAQABLgAECgIJBAANAAAAAA==.',
Gh='Ghoostt:BAAALgAECgcJEQABLgAFFAcJIwAPAIcfAA==.Ghostdk:BAABLgAFFH8HAAIdAAQJgwSrCwDVAAAdAAQJgwSrCwDVAAABLgAFFAcJIwAPAIcfAA==.Ghostwarrior:BAAALgADCgMJAwABLgAFFAcJIwAPAIcfAA==.Ghostzz:BAACLgAFFH8jAAIPAAcJhx+3BwD7AQAPAAcJhx+3BwD7AQAuAAQKf2cAAw8ACQl0JksBAIUDAA8ACQl0JksBAIUDAB4ABQkSHhcbAD8BAAAA.',
Gl='Glarb:BAAALgAECgYJDAAAAA==.Glzygldiator:BAACLgAFFH8OAAILAAMJ1BhXLgDhAAALAAMJ1BhXLgDhAAAuAAQKfykAAgsACAkWH+A8AA4CAAsACAkWH+A8AA4CAAAA.',
Gn='Gnomelock:BAAALgAFFAEJAQABLgAFFAEJBQABAB4mAA==.',
Go='Gobblin:BAAALgAECgUJDQAAAA==.Gotbandaids:BAAALgAECgIJAgAAAA==.Govegan:BAAALgADCgQJBwAAAA==.',
Gr='Graavey:BAAALgAECgcJAwABLgAFFAMJCwAOADUZAA==.Greyhairs:BAABLgAECn8VAAIDAAcJqQ/OfwA/AQADAAcJqQ/OfwA/AQAAAA==.Grifter:BAAALgAECgEJAQAAAA==.Grimthor:BAAALgAECgcJBwAAAA==.Grippy:BAACLgAFFH8HAAIKAAMJRwZFcQCmAAAKAAMJRwZFcQCmAAAuAAQKfyYAAgoACAl/HUoiAIQCAAoACAl/HUoiAIQCAAAA.Gromgar:BAAALgAECgMJAwAAAA==.Gromit:BAACLgAFFH8iAAIEAAgJ+Rp8AgBzAgAEAAgJ+Rp8AgBzAgAuAAQKfy0AAwQACQlXIZMDACEDAAQACQlXIZMDACEDAAYAAgmnEUdKAG0AAAAA.Grym:BAAALgADCgcJDgAAAA==.',
Gu='Gustófwind:BAACLgAFFH8IAAIBAAQJJSFzCgB4AQABAAQJJSFzCgB4AQAuAAQKfyAAAwEACQnKIZkEAA0DAAEACQnKIZkEAA0DAB8AAwnMEmh2ALgAAAAA.',
Ha='Hackey:BAAALgAFFAEJAQAAAA==.Haldire:BAABLgAECn8VAAIeAAcJxh0mDAACAgAeAAcJxh0mDAACAgAAAA==.Harrypotture:BAAALgADCgEJAQAAAA==.Haschel:BAABLgAECn8wAAMaAAkJriCKBADRAgAaAAkJriCKBADRAgAgAAMJ9Q6JOACFAAAAAA==.Haunterx:BAAALgAFFAEJAgAAAA==.',
He='Hexerfender:BAAALgAECgUJBQAAAA==.Heypal:BAAALgADCgYJDwAAAA==.',
Ho='Hofarmer:BAABLgAECn8YAAIhAAkJUhMfFgCjAQAhAAkJUhMfFgCjAQAAAA==.Holychris:BAAALgADCgEJAQAAAA==.Holycöw:BAAALgADCgkJCQAAAA==.Holywood:BAAALgAECgYJBwAAAA==.',
Hu='Hurtak:BAAALgAECgcJEwAAAA==.',
Hy='Hycisan:BAABLgAECn80AAIWAAkJdRwVCwDcAgAWAAkJdRwVCwDcAgAAAA==.Hysteria:BAAALgAECgMJBQAAAA==.',
Ic='Icanlust:BAAALgADCgIJAgAAAA==.Icant:BAAALgADCgEJAgABLgAECgEJAQANAAAAAA==.Icon:BAAALgAECgQJBQAAAA==.Icydoodad:BAAALgAECgIJBAAAAA==.',
Ie='Iesous:BAAALgAECgEJAgAAAA==.',
Ig='Ignis:BAAALgADCgMJAwAAAA==.',
Il='Ilovekayla:BAAALgAFFAEJAgAAAA==.',
Io='Iocomotive:BAAALgAFFAEJAQAAAA==.',
Is='Iskaru:BAAALgAECgEJAQABLgAECgYJDwANAAAAAA==.',
Ja='Jacklawin:BAAALgAECgMJAwAAAA==.Jasmyn:BAAALgADCgQJBAAAAA==.',
Jb='Jbirdlol:BAAALgADCgUJBAAAAA==.',
Je='Jesse:BAAALgAECgYJEAABLgAFFAIJBwAWAHYXAA==.Jetmage:BAABLgAECn8gAAIiAAkJRyToAADgAgAiAAkJRyToAADgAgAAAA==.',
Ji='Jire:BAAALgAECgUJDQAAAA==.Jittkal:BAAALgADCgMJAwAAAA==.',
Jo='Josh:BAAALgADCgMJAgAAAA==.',
Jp='Jpally:BAABLgAECn8XAAMWAAcJ2AbKSwAMAQAWAAcJ2AbKSwAMAQAPAAUJSwRA7AC3AAAAAA==.',
Ju='Jurassthicc:BAAALgAECgEJBQAAAA==.',
Jw='Jwøww:BAAALgAECgEJAQAAAA==.',
Ka='Kafka:BAAALgADCgcJBgAAAA==.Kanastra:BAABLgAECn8dAAIKAAkJrBssHQBlAgAKAAkJrBssHQBlAgABLgAFFAUJGwAMAAkaAA==.Karraa:BAABLgAECn89AAIgAAkJSxqKAQBKAgAgAAkJSxqKAQBKAgAAAA==.Katil:BAAALgAECgEJAQAAAA==.Kaylib:BAABLgAECn8sAAIiAAkJJxABBADFAQAiAAkJJxABBADFAQAAAA==.',
Ke='Kea:BAAALgADCgIJAgABLgAECgUJCQANAAAAAA==.Kenergy:BAAALgAECgUJCQAAAA==.Kerze:BAABLgAECn8UAAIgAAYJlhHwKQDlAAAgAAYJlhHwKQDlAAAAAA==.Kesatrix:BAABLgAECn8tAAIfAAkJSRQPIQAUAgAfAAkJSRQPIQAUAgAAAA==.Kesi:BAAALgADCgQJBAAAAA==.',
Kh='Khai:BAAALgAECgQJBAAAAA==.Khazador:BAAALgADCgkJEgABLgAECgkJHQAIALkXAA==.Khaztharion:BAAALgADCggJCAABLgAECgkJHQAIALkXAA==.Khendrick:BAABLgAECn8aAAIPAAkJ1w8pXwCzAQAPAAkJ1w8pXwCzAQAAAA==.',
Ki='Kilerwolf:BAAALgADCgIJAgAAAA==.Kimsmage:BAAALgADCgYJBgAAAA==.Kirdo:BAAALgAECgEJAQAAAA==.Kith:BAAALgAECgEJAgAAAA==.Kitridge:BAAALgAECgcJDQAAAA==.Kittykatt:BAACLgAFFH8UAAIQAAQJixvkCwBFAQAQAAQJixvkCwBFAQAuAAQKfzwAAhAACQkMIOUGAOgCABAACQkMIOUGAOgCAAAA.',
Ko='Kolchak:BAAALgADCgYJDQAAAA==.Korel:BAAALgAECgcJDAAAAA==.',
Kr='Kraggo:BAAALgAFFAEJAQAAAA==.Krimzin:BAACLgAFFH8YAAIPAAUJzSFcKQBmAQAPAAUJzSFcKQBmAQAuAAQKfxwAAw8ACQlnIc4XANoCAA8ACAkOIc4XANoCABYABQlTD3phALAAAAAA.',
Ku='Kumala:BAAALgAECgMJBQAAAA==.Kungao:BAAALgAECgUJBQAAAA==.',
Ky='Kylea:BAAALgAECgQJBAAAAA==.',
La='Laffiel:BAAALgADCgQJBAAAAA==.Landoh:BAABLgAECn8kAAIVAAkJ+CGWGADGAgAVAAkJ+CGWGADGAgAAAA==.Larg:BAAALgAECgcJBgAAAA==.Larsen:BAABLgAECn8kAAITAAkJZR6QFABGAgATAAkJZR6QFABGAgAAAA==.Lastshot:BAAALgAECgUJBQAAAA==.',
Le='Leap:BAABLgAECn8nAAMYAAkJOBt4DQDeAQAYAAcJIxt4DQDeAQAhAAkJxxXcBQA7AQAAAA==.Lefthorn:BAAALgADCgIJAgAAAA==.Lenneth:BAAALgAECgIJAgAAAA==.',
Li='Lightofdawn:BAAALgAECgMJAwAAAA==.Lightstyle:BAAALgADCgMJAwAAAA==.Lilow:BAABLgAECn85AAIHAAkJIhKGHwDJAQAHAAkJIhKGHwDJAQAAAA==.',
Ll='Llarker:BAABLgAECn8vAAQPAAcJ/wgewwAEAQAPAAcJ/wgewwAEAQAeAAYJHAO0OQB3AAAWAAIJvQEXkQAtAAAAAA==.',
Lo='Lockendron:BAAALgADCgQJBAAAAA==.Locketharion:BAAALgADCgQJBAAAAA==.Lockpebbles:BAAALgADCgMJAwAAAA==.Lokomachina:BAABLgAECn8UAAIDAAcJLyETHwBLAgADAAcJLyETHwBLAgAAAA==.Lonesdove:BAAALgAECgEJAQAAAA==.',
Lu='Lucyna:BAAALgAECgMJAwABLgAECgkJJQAjAPUiAA==.Luminia:BAAALgAECgUJCQAAAA==.Lunacy:BAAALgAECgQJCQAAAA==.',
Ly='Lynngosa:BAABLgAECn85AAMkAAkJEhaJAQDTAQAkAAgJQhWJAQDTAQAMAAgJLRJVAwCOAQAAAA==.Lyrana:BAAALgADCgQJBAAAAA==.Lyrasa:BAAALgADCgQJBAAAAA==.',
Ma='Maelidrael:BAAALgAECggJCwABLgAFFAIJBQAVADwRAA==.Magiks:BAAALgAFFAEJAQAAAA==.Magisterium:BAABLgAECn8vAAMEAAkJwAf2PgD0AAAEAAkJwAf2PgD0AAAHAAEJ/QFDnAAXAAAAAA==.Malady:BAABLgAECn8sAAIHAAkJwCA+CQC7AgAHAAkJwCA+CQC7AgAAAA==.Malakyde:BAAALgADCgMJAwAAAA==.Malt:BAABLgAECn8ZAAIKAAgJvCB7OgDdAQAKAAgJvCB7OgDdAQAAAA==.Malthorial:BAAALgADCgEJAQAAAA==.Mario:BAABLgAFFH8FAAIBAAEJHiYWNwBrAAABAAEJHiYWNwBrAAAAAA==.Mattenom:BAAALgADCgYJCAAAAA==.Maulware:BAAALgADCgEJAQAAAA==.',
Mb='Mbrodh:BAAALgAECgQJBAAAAA==.Mbrosmites:BAAALgAECgcJCwAAAA==.',
Md='Mdeag:BAABLgAECn8WAAMZAAUJ9hY2EAC8AAAZAAQJ9RY2EAC8AAAaAAUJDA5/RwCtAAAAAA==.',
Me='Mefistofeles:BAACLgAFFH8RAAIFAAMJFBRxJwDsAAAFAAMJFBRxJwDsAAAuAAQKfyMAAgUACAlmGJ8XAN4BAAUACAlmGJ8XAN4BAAAA.Meingaree:BAABLgAECn8hAAIJAAkJxhzbAAA7AgAJAAkJxhzbAAA7AgAAAA==.Merlinus:BAABLgAECn8lAAIPAAcJ4gq0lABTAQAPAAcJ4gq0lABTAQAAAA==.Merton:BAAALgADCggJDAAAAA==.',
Mi='Mightyguzz:BAABLgAECn9AAAIgAAkJmhPbEQDMAQAgAAkJmhPbEQDMAQAAAA==.Miku:BAAALgAECgMJBAAAAA==.Mingi:BAAALgAECgcJCAAAAA==.Misericordia:BAABLgAECn8VAAIHAAkJtg/+BACLAQAHAAkJtg/+BACLAQAAAA==.Mitchelle:BAAALgAECgMJBQAAAA==.',
Mo='Moirayne:BAAALgAECgYJBQAAAA==.Moomkin:BAABLgAECn8pAAIQAAgJgwyDNwA3AQAQAAgJgwyDNwA3AQAAAA==.',
My='Mythicblade:BAAALgADCgEJAQAAAA==.',
['Mø']='Møønchild:BAAALgAECgkJEAAAAA==.',
Na='Nai:BAAALgAECgQJDAAAAA==.Nanaish:BAAALgAECgEJAgAAAA==.Narpul:BAABLgAECn8rAAIeAAkJBB7eBACpAgAeAAkJBB7eBACpAgAAAA==.Nastysavage:BAAALgADCgMJAwAAAA==.Natë:BAACLgAFFH8TAAIgAAMJOhgsDwCyAAAgAAMJOhgsDwCyAAAuAAQKfzAAAiAACQkvIWUDACMDACAACQkvIWUDACMDAAAA.Nazend:BAAALgADCgQJBwAAAA==.Nazera:BAAALgADCgEJAQAAAA==.',
Ne='Necrotalon:BAAALgAECggJEQAAAA==.Nelosi:BAAALgAECgMJCAAAAA==.Neondh:BAACLgAFFH8VAAIKAAQJPSSvJQCWAQAKAAQJPSSvJQCWAQAuAAQKfzQAAgoACQmIJA4NABcDAAoACQmIJA4NABcDAAAA.Nerzhùl:BAABLgAECn8lAAITAAkJGglcPABEAQATAAkJGglcPABEAQAAAA==.',
Nh='Nharuna:BAACLgAFFH8SAAIDAAQJzQjHJwD7AAADAAQJzQjHJwD7AAAuAAQKfzgAAgMACQnbEyI2AAUCAAMACQnbEyI2AAUCAAAA.',
Ni='Nickolaos:BAAALgAECgEJAgAAAA==.Nieloriel:BAABLgAECn9BAAMWAAkJwhSCAwDaAQAWAAkJwhSCAwDaAQAPAAgJmgrSlwBFAQAAAA==.Nightwishing:BAAALgAECgQJBAAAAA==.Niupiadps:BAAALgAECgIJAgAAAA==.Niykee:BAABLgAECn8lAAQjAAkJ9SI6AwByAgAjAAYJhSQ6AwByAgAFAAcJPiKmHAAaAgAlAAcJCx5mBgARAgAAAA==.',
No='Noboundss:BAACLgAFFH8GAAMKAAIJDAuAPQBwAAAKAAIJDAuAPQBwAAARAAEJjgbfHwA4AAAuAAQKfx0AAwoACAm6EXQRAOsAAAoABwkBEnQRAOsAABEAAwmID6IZAEgAAAAA.Nobóunds:BAAALgAECgkJEAABLgAFFAIJBgAKAAwLAA==.Nomnoms:BAAALgAECgYJEgAAAA==.Nomoreheals:BAAALgAECgYJDQAAAA==.Notkarl:BAAALgAECgIJAwAAAA==.Nowimpissed:BAACLgAFFH8PAAMCAAMJ9SGsGAANAQACAAMJ9SGsGAANAQADAAEJvyDWHgBkAAAuAAQKfxcABAIABgnEHpUTAAkCAAIABgnEHpUTAAkCAAMABAkPFsp5APoAABsABAnmDzBbANcAAAAA.Noztra:BAACLgAFFH8iAAIVAAQJpQzULQALAQAVAAQJpQzULQALAQAuAAQKfywAAhUACAnjF+dLAPcBABUACAnjF+dLAPcBAAAA.',
Nu='Nu:BAAALgADCgkJEwAAAA==.Nuker:BAAALgAECgEJAQAAAA==.',
Ny='Nysrogh:BAAALgAECgUJEgABLgAFFAQJFAASADQXAA==.',
Ob='Obsideon:BAAALgAECggJEwAAAA==.',
Oc='Octoknight:BAAALgAECgEJAQAAAA==.',
Oh='Ohgr:BAABLgAECn8dAAIZAAYJaiBgBAC0AQAZAAYJaiBgBAC0AQAAAA==.Ohshifty:BAABLgAECn80AAMQAAkJ0xApJQCiAQAQAAkJ0xApJQCiAQASAAQJbASMowBqAAAAAA==.',
Ol='Olan:BAAALgAECgYJDAAAAA==.Olie:BAABLgAECn8bAAIDAAgJ9wnYdgBSAQADAAgJ9wnYdgBSAQAAAA==.',
Or='Orbsicles:BAABLgAECn8uAAQmAAkJHyPVAQD9AgAmAAkJHyPVAQD9AgARAAEJKBqSYABMAAAKAAEJtgvvGgEvAAAAAA==.Oriøn:BAAALgADCgYJBgAAAA==.',
Ou='Ouragan:BAAALgAECgUJCAAAAA==.',
Pa='Paedrig:BAAALgAECgEJAgAAAA==.Papitomyrey:BAABLgAECn8gAAMZAAkJKCReBwDpAgAZAAkJKCReBwDpAgAaAAUJYh07OADkAAABLgAFFAMJBQAfAMATAA==.Paramedic:BAAALgADCgIJAgAAAA==.Passtheflask:BAABLgAECn8eAAIIAAcJGgcNrQDpAAAIAAcJGgcNrQDpAAAAAA==.',
Pe='Perdition:BAAALgAECgEJAgAAAA==.Pestílence:BAACLgAFFH8MAAILAAMJsxzqjgDtAAALAAMJsxzqjgDtAAAuAAQKfz8AAwsACQk1IrAYALICAAsACQk1IrAYALICABcAAQnEEZBHACoAAAAA.',
Ph='Phaesphoros:BAABLgAECn8gAAIOAAkJXxDvSwCAAQAOAAkJXxDvSwCAAQAAAA==.Phenor:BAAALgAECgQJBAAAAA==.',
Pi='Picklepea:BAAALgADCgkJEAAAAA==.',
Po='Poe:BAAALgADCgYJBgABLgAECgcJFQAVAOEXAA==.Powpow:BAACLgAFFH8FAAIFAAIJVAtMPQBGAAAFAAIJVAtMPQBGAAAuAAQKfzwAAgUACQkIHQAJAJUCAAUACQkIHQAJAJUCAAAA.',
Pr='Prejudice:BAABLgAECn8dAAIWAAkJnxTqHQATAgAWAAkJnxTqHQATAgAAAA==.Primévil:BAAALgAECgYJBgABLgAECgkJMQATAOYYAA==.Priscilla:BAAALgAECgEJAgAAAA==.Prowlcow:BAABLgAECn8yAAMSAAkJdRd6HABjAgASAAkJdRd6HABjAgAYAAIJDxYsNgCEAAAAAA==.',
Ps='Psychosis:BAABLgAECn8uAAILAAkJ5B1BJwBlAgALAAkJ5B1BJwBlAgAAAA==.',
Pu='Purpetua:BAABLgAECn8XAAIDAAYJpg2sGgDvAAADAAYJpg2sGgDvAAAAAA==.Putrescence:BAAALgADCgEJAQAAAA==.',
['Pû']='Pûff:BAAALgAECgcJDwAAAA==.',
Qm='Qmpel:BAAALgADCgMJAwAAAA==.',
Ra='Raiiz:BAACLgAFFH8IAAIVAAMJBBBmLAAFAQAVAAMJBBBmLAAFAQAuAAQKfyYAAhUACAkhHI4/AHoCABUACAkhHI4/AHoCAAAA.Rainhoof:BAABLgAECn8kAAMYAAkJsRgIDAD5AQAYAAgJOhkIDAD5AQASAAYJlweAhwDHAAAAAA==.Ralneth:BAACLgAFFH8hAAQMAAkJABDFEAD7AQAMAAgJ4A/FEAD7AQAcAAQJXRToAwAOAQAkAAEJ2QECGwAjAAAuAAQKfyQAAxwACAmrIFADAOsCABwACAmfH1ADAOsCAAwABgnYG0IYAA8CAAAA.Randomtask:BAAALgADCgUJBgAAAA==.Rapala:BAABLgAECn8mAAIIAAkJ+hz2GwB9AgAIAAkJ+hz2GwB9AgAAAA==.Rapalaa:BAAALgAECgcJDwABLgAECgkJJgAIAPocAA==.Raspútin:BAACLgAFFH8GAAMnAAQJxBhaCQBCAQAnAAQJxBhaCQBCAQABAAEJ+ALfIgAsAAAuAAQKfzUAAycACQmoGX0OAFICACcACQmoGX0OAFICAAEABAnwB9VVALkAAAAA.Ravos:BAAALgAECgYJBgAAAA==.Rawkfice:BAAALgADCggJFwAAAA==.',
Re='Redlefevoker:BAAALgADCgYJCQAAAA==.Renfield:BAAALgADCgYJCAAAAA==.Revok:BAAALgAECgcJDwAAAA==.Revoker:BAAALgADCgYJCAAAAA==.',
Ri='Riordan:BAAALgAFFAEJAgAAAA==.Rivvetear:BAAALgADCgYJBgAAAA==.',
Rj='Rjolz:BAACLgAFFH8OAAILAAQJZiBiOACLAQALAAQJZiBiOACLAQAuAAQKfzsAAgsACQn7JQAEAGIDAAsACQn7JQAEAGIDAAAA.',
Ro='Roflchopr:BAAALgAECggJEQAAAA==.Roflkin:BAAALgAECgEJAQAAAA==.Roguish:BAAALgAECgEJAQAAAA==.Rootzi:BAAALgAECgIJAwABLgAECgkJJAALALEcAA==.Rootzidk:BAABLgAECn8kAAILAAkJsRxLNQAqAgALAAkJsRxLNQAqAgAAAA==.',
Ru='Rucks:BAABLgAECn8jAAMBAAkJ1Br1GQDhAQABAAkJIRP1GQDhAQAnAAYJzBrULQCiAQAAAA==.',
Ry='Ryzze:BAAALgADCgYJBgAAAA==.',
Sa='Sachi:BAAALgADCgYJBgAAAA==.Saelem:BAAALgAECgYJBgAAAA==.Saigonbeer:BAAALgAECgMJAwAAAA==.Sandalfon:BAAALgAECgYJDwAAAA==.Sanleron:BAACLgAFFH8FAAIeAAMJ5RDxDACqAAAeAAMJ5RDxDACqAAAuAAQKfxYAAx4ACAlYIcYNAOkBAB4ABgkWIsYNAOkBAA8ABQm0GiWlADABAAAA.Sarith:BAAALgAECgQJAQABLgAECgUJBQANAAAAAA==.Saske:BAAALgADCgMJBwABLgAECgEJAQANAAAAAA==.',
Sc='Scarab:BAAALgAECgYJBgAAAA==.Scargon:BAAALgAECgcJEAAAAA==.Schizandrol:BAAALgAECgQJBAAAAA==.',
Se='Selidori:BAAALgADCgYJBgAAAA==.Seralicht:BAACLgAFFH8SAAIEAAYJ+RU9CwCXAQAEAAYJ+RU9CwCXAQAuAAQKfyIAAwQACAmGHhwQAGUCAAQACAmGHhwQAGUCAAcAAQmKCyWIADEAAAAA.',
Sh='Shadowclawz:BAAALgAECgQJCAAAAA==.Shaliri:BAAALgADCgEJBAAAAA==.Shamanata:BAAALgAECgEJAgAAAA==.Sharayse:BAABLgAECn8hAAIVAAkJWgxbbQCgAQAVAAkJWgxbbQCgAQAAAA==.Sharmee:BAAALgAECgkJEQAAAA==.Shennong:BAAALgAECgEJAQAAAA==.Shishy:BAAALgAECgUJCgAAAA==.Shockohôlic:BAABLgAECn8xAAQTAAkJ5hgjFQBAAgATAAkJ5hgjFQBAAgAOAAYJ/xB/bAAWAQAoAAEJoAphKwA4AAAAAA==.Shocky:BAAALgAECgcJCgAAAA==.Sháde:BAAALgADCgIJAgAAAA==.',
Sk='Skadie:BAAALgAECgkJDwABLgAECgkJOQAkABIWAA==.Skullkìng:BAABLgAECn8jAAILAAkJuhSMTADdAQALAAkJuhSMTADdAQAAAA==.',
Sl='Slingablade:BAACLgAFFH8OAAIKAAQJ/wZvXwDRAAAKAAQJ/wZvXwDRAAAuAAQKfyUAAwoACQliFoQuAA0CAAoACQlpFYQuAA0CABEAAwm9Ey5DAKkAAAAA.',
Sm='Smashnskullz:BAAALgAECgQJBgABLgAECgUJBQANAAAAAA==.',
Sn='Sniffsniff:BAACLgAFFH8JAAIPAAMJxyW2TQATAQAPAAMJxyW2TQATAQAuAAQKfykAAw8ACAlHJQYKAEEDAA8ACAlHJQYKAEEDABYAAQnBHhx/AE4AAAEuAAUUBAkUAA4A0CYA.',
So='Solvi:BAABLgAECn8fAAISAAcJ9xfzVQA4AQASAAcJ9xfzVQA4AQAAAA==.Sonira:BAAALgADCgQJCAAAAA==.Soulbrand:BAABLgAECn8kAAIHAAkJMwmGLwBhAQAHAAkJMwmGLwBhAQAAAA==.Southpawclaw:BAAALgAECgEJAQABLgAECggJGAAoAPAfAA==.',
Sp='Spellz:BAABLgAECn8lAAIHAAgJ0x9pDACKAgAHAAgJ0x9pDACKAgAAAA==.Spoo:BAAALgAECgIJAwAAAA==.Spuggle:BAAALgAECgQJBAAAAA==.',
St='Stabathuh:BAAALgADCgYJBgAAAA==.Stoopiddk:BAAALgAECgEJAwABLgAECgIJBAANAAAAAA==.Stoopidelf:BAAALgAECgEJAwABLgAECgIJBAANAAAAAA==.Stoopidmonk:BAAALgAECgEJAQABLgAECgIJBAANAAAAAA==.Stoopidrood:BAAALgAECgEJAQABLgAECgIJBAANAAAAAA==.Stoopidtroll:BAAALgADCgUJBQABLgAECgIJBAANAAAAAA==.Stoopidwarur:BAAALgAECgEJBAABLgAECgIJBAANAAAAAA==.Stormclaw:BAABLgAECn8cAAImAAkJiAwZDgBwAQAmAAkJiAwZDgBwAQAAAA==.Straeka:BAAALgAECgIJAgABLgAECgkJQwASAKAZAA==.Stëvë:BAAALgAECgIJBAABLgAECgYJDwANAAAAAA==.',
Su='Sufiya:BAABLgAECn8gAAIDAAkJLw9GUwCpAQADAAkJLw9GUwCpAQAAAA==.Suhwoo:BAAALgAECgcJDwAAAA==.Sumig:BAAALgADCgEJBAAAAA==.',
Sw='Swiftarrows:BAAALgAECgEJAgAAAA==.',
Sy='Sylvershadow:BAABLgAECn8pAAIDAAkJLBU0SQDGAQADAAkJLBU0SQDGAQAAAA==.Sym:BAAALgADCgcJCQAAAA==.Syzz:BAAALgAECgEJAQAAAA==.',
Ta='Taintedsoulv:BAAALgADCgUJBgAAAA==.Taliri:BAAALgADCgEJAQABLgAECgEJAQANAAAAAA==.Tandarilada:BAAALgAFFAEJBAAAAA==.Tanknspankn:BAAALgAECgkJDAAAAA==.Tankurface:BAAALgAECgEJAgAAAA==.',
Th='Thalvint:BAACLgAFFH8MAAIaAAQJSRs5FAA8AQAaAAQJSRs5FAA8AQAuAAQKfzMAAxoACQmHIxUDAAkDABoACQmHIxUDAAkDABkABgnVEiJbAEIBAAAA.Theblackhand:BAABLgAECn8dAAMTAAYJ1RXTSgAcAQATAAUJaxPTSgAcAQAOAAYJrQ+TdgD6AAAAAA==.Thefira:BAAALgADCgkJCQAAAA==.Thickdk:BAABLgAECn8aAAILAAgJHRZTbgCtAQALAAgJHRZTbgCtAQAAAA==.Thoriel:BAAALgAECgEJAgAAAA==.',
Ti='Timefall:BAAALgAECgkJDgAAAA==.Titanic:BAAALgAECgcJEAAAAA==.',
To='Tomcruise:BAABLgAECn8UAAIPAAkJdBipQgD+AQAPAAkJdBipQgD+AQAAAA==.Toshiro:BAAALgADCgcJBwAAAA==.Totemlyawsum:BAABLgAFFH8LAAITAAQJDg2RKgDrAAATAAQJDg2RKgDrAAAAAA==.Touch:BAAALgAECgEJAQAAAA==.Touchymcfeel:BAAALgADCgMJAwAAAA==.',
Tr='Trckr:BAAALgADCgIJAgAAAA==.Treeiage:BAAALgAECgUJCAAAAA==.Trooblu:BAAALgAECgYJEgAAAA==.',
Tw='Twotone:BAAALgAECgQJBgAAAA==.',
['Té']='Téz:BAABLgAECn8kAAMEAAYJkRqpBACgAQAEAAUJuB2pBACgAQAHAAYJvhcECQAdAQAAAA==.',
['Tê']='Têzeret:BAAALgAECgEJAgAAAA==.',
Ul='Ulkthar:BAABLgAECn8wAAIZAAgJ2BPKKAAZAgAZAAgJ2BPKKAAZAgABLgAFFAUJCgAVAMUKAA==.Ultrauchuva:BAAALgAECgEJBAAAAA==.',
Un='Unholyhammer:BAAALgADCgIJAgABLgAECgUJBQANAAAAAA==.',
Us='Usaya:BAAALgADCgEJAQAAAA==.',
Va='Vacunamatata:BAAALgAECgEJAQAAAA==.Vanarn:BAAALgADCgEJAQABLgAECgEJAQANAAAAAA==.Vanlin:BAABLgAECn8kAAISAAkJWh5QDwDaAgASAAkJWh5QDwDaAgAAAA==.Varedïs:BAAALgAECgEJAQABLgAFFAUJHAALANgLAA==.',
Ve='Velirayvia:BAAALgAECgYJDgAAAA==.Vexxdr:BAACLgAFFH8OAAISAAMJ2xPRFQC9AAASAAMJ2xPRFQC9AAAuAAQKfx8AAhIACAkcEtc5AL4BABIACAkcEtc5AL4BAAEuAAUUBQkPAA4A5hQA.Vexxs:BAACLgAFFH8PAAIOAAUJ5hR1EwApAQAOAAUJ5hR1EwApAQAuAAQKfxsAAg4ACQnIFasgAEsCAA4ACQnIFasgAEsCAAAA.',
Vi='Virtey:BAAALgADCgUJBQAAAA==.Virtuous:BAAALgADCgYJBwAAAA==.',
Vl='Vladzy:BAAALgADCgcJAwAAAA==.',
Vo='Voidsuzu:BAAALgAECgQJBwABLgAECgkJPAAeAGAVAA==.Vormedicus:BAABLgAECn8WAAIEAAcJrxtLBAC1AQAEAAcJrxtLBAC1AQABLgAFFAQJBgAnAMQYAA==.',
Vu='Vulperas:BAABLgAECn9RAAITAAkJshTGAwDbAQATAAkJshTGAwDbAQAAAA==.',
Vy='Vynastallan:BAABLgAECn8cAAMDAAcJhSOMIABCAgADAAcJhSOMIABCAgAbAAEJehfShgA1AAAAAA==.Vyper:BAEBLgAECn8lAAIMAAgJcxmIHwDcAQAMAAgJcxmIHwDcAQABLgAFFAQJCwAYADkXAA==.',
Wa='Waroo:BAABLgAECn8iAAIQAAgJORICJQCjAQAQAAgJORICJQCjAQAAAA==.',
We='Wellcole:BAAALgADCgYJBgAAAA==.Wenden:BAAALgAFFAEJAwAAAA==.Wengo:BAAALgAECgEJAQAAAA==.',
Wh='Whitesnow:BAAALgAECgIJAgAAAA==.',
Wi='Wilbert:BAAALgADCgEJAQAAAA==.Winniethepo:BAAALgAECgQJBAAAAA==.Witherflow:BAAALgAECgQJBQAAAA==.',
Wo='Woodey:BAAALgADCgcJCAAAAA==.',
Wu='Wulffric:BAABLgAECn8aAAICAAgJJBLkJQBuAQACAAgJJBLkJQBuAQAAAA==.',
Xe='Xeo:BAAALgADCgMJAwAAAA==.',
Ya='Yachirú:BAABLgAECn88AAIeAAkJYBXDDgDXAQAeAAkJYBXDDgDXAQAAAA==.Yahkisoba:BAAALgAECgEJAQAAAA==.',
Ye='Yessir:BAAALgAECgEJAQABLgAECgkJGgABAA4XAA==.',
Yi='Yiang:BAABLgAECn8nAAIBAAkJ0R0YCgCiAgABAAkJ0R0YCgCiAgAAAA==.',
Yl='Ylndrysa:BAABLgAECn9DAAMSAAkJoBkbGQB9AgASAAkJoBkbGQB9AgAQAAMJoRgCUgDGAAAAAA==.',
Yt='Ytho:BAAALgADCgYJBgAAAA==.',
Za='Zalithar:BAABLgAECn8VAAIKAAgJZgUdmwDrAAAKAAgJZgUdmwDrAAAAAA==.',
Ze='Zedrock:BAACLgAFFH8FAAIVAAIJPBHQngCPAAAVAAIJPBHQngCPAAAuAAQKf0AAAhUACQk0Il4KACcDABUACQk0Il4KACcDAAAA.Zekodian:BAAALgADCgcJDQAAAA==.Zentner:BAABLgAECn8uAAMQAAkJXx9OCwCeAgAQAAkJXx9OCwCeAgAhAAQJPAodJAB8AAAAAA==.Zeropistol:BAABLgAECn8aAAIVAAgJNQPzzgDzAAAVAAgJNQPzzgDzAAAAAA==.Zexrous:BAAALgADCgEJAQAAAA==.',
Zh='Zhas:BAABLgAECn8WAAIEAAcJfhVELABoAQAEAAcJfhVELABoAQAAAA==.',
Zi='Ziminiar:BAAALgAECgEJAQAAAA==.',
Zu='Zuro:BAABLgAECn8cAAMDAAkJFQ29WQCXAQADAAkJFQ29WQCXAQAbAAEJCgHPmQAaAAAAAA==.',
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
