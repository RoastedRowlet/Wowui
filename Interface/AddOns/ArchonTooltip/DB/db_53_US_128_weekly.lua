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

local lookup = {'Unknown-Unknown','Mage-Arcane','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Druid-Restoration','Priest-Holy','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Warrior-Arms','Warrior-Protection','Rogue-Assassination','Rogue-Subtlety','Shaman-Enhancement','Priest-Discipline','Paladin-Holy','Monk-Windwalker','Mage-Frost','Druid-Balance','Druid-Feral','Druid-Guardian','Paladin-Protection','Shaman-Restoration','Warrior-Fury','Priest-Shadow','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Devourer','Warlock-Affliction','DemonHunter-Havoc','Hunter-Survival',}
local provider = {region='US',realm='Kargath',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaryn:BAAANQADCggICAABNQAECgYIEQABAAAAAA==.',
Ab='Abracadabruh:BAABNQAECoEVAAICAAgKCxNOqgAMAgACAAgKCxNOqgAMAgAAAA==.Absynthia:BAAANQAECgYIDwAAAA==.',
Ac='Academe:BAAANQADCggICwAAAA==.Accalon:BAAANQADCgYIBgAAAA==.',
Ad='Adérai:BAAANQAECgYICAAAAA==.',
Ae='Aellopus:BAAANQAECgcIEgAAAA==.Aero:BAAANQAECgYIEQAAAA==.',
Ag='Agròm:BAAANQADCgQIBAABNQADCgcICwABAAAAAA==.',
Ak='Akata:BAAANQADCgYICQAAAA==.Akku:BAAANQADCgYIBwAAAA==.',
Al='Alanwake:BAABNQAECoEmAAQDAAgKxxq/DQBpAgADAAgKvhm/DQBpAgAEAAUKSxjADQBDAQAFAAMKGQOaQQBnAAAAAA==.Aldourolf:BAAANQABCgQIBAAAAA==.Alomeo:BAEANQADCgYJCwAAAA==.Alphasmash:BAAANQAECgIIAgAAAA==.',
Am='Amiliane:BAAANQAECgUIDgAAAA==.Amilmean:BAAANQAECgEJAQAAAA==.Amoradine:BAAANQAECgIIAgAAAA==.Amz:BAAANQAECgIIAwAAAA==.',
An='Anadrien:BAABNQAECoEaAAIGAAcKXRbxJADNAQAGAAcKXRbxJADNAQAAAA==.Ancelagon:BAAANQADCgYIBwAAAA==.Andrae:BAAANQAECgQIBAAAAA==.Angrimia:BAAANQAECgYIEQAAAA==.Annussa:BAAANQAECgEIAQAAAA==.Antal:BAAANQADCgcIBwAAAA==.',
Ar='Arboria:BAAANQAECggIAgAAAA==.Arcadya:BAAANQADCgcIBwAAAA==.Archielgh:BAAANQADCgUIBQAAAA==.Ardbeg:BAAANQABCgcIDwAAAA==.Arduin:BAAANQAECgUIEQAAAA==.Aremethea:BAAANQAECgUIDQAAAA==.Aronk:BAAANQADCggIHAABNQAECgUIDwABAAAAAA==.Arore:BAAANQADCgMJBQABNQAECgUIDwABAAAAAA==.Aroreck:BAAANQADCgQIBAABNQAECgUIDwABAAAAAA==.Arorepriest:BAAANQADCggICwABNQAECgUIDwABAAAAAA==.Articulaté:BAABNQAECoEZAAIHAAgKUSF0GgDyAgAHAAgKUSF0GgDyAgAAAA==.Arîel:BAAANQADCggICAAAAA==.',
As='Asbjorn:BAAANQAECgUICAAAAA==.Ashvoyager:BAAANQABCgIIAgAAAA==.',
At='Atheanos:BAAANQAECgIIAQAAAA==.Attack:BAAANQADCgQIBQABNQAECgkJMQACAMsiAA==.',
Av='Avestara:BAAANQAECgYIEQAAAA==.',
Ay='Ayohec:BAAANQAECggICAAAAA==.',
Az='Azoril:BAABNQAECoEeAAIIAAgKORPUiQDfAQAIAAgKORPUiQDfAQAAAA==.Azùla:BAAANQAECgQICgAAAA==.',
['Aí']='Aídeen:BAAANQAECgcIDwAAAA==.',
Ba='Babs:BAAANQADCgEIAQAAAA==.Badmooddude:BAAANQAECgMIBAAAAA==.Baelnorn:BAABNQAECoEYAAMJAAcKDB7TYwAKAgAJAAYKDB/TYwAKAgAKAAEKCBjWZgBIAAAAAA==.Bains:BAAANQADCgcIBwAAAA==.Barrex:BAAANQAECgIIBQAAAA==.Basak:BAAANQAECgQIBAABNQAFFAIIBwABAAAAAQ==.Basken:BAABNQAECoEZAAILAAcK3gc9pACLAQALAAcK3gc9pACLAQAAAA==.Batôsai:BAAANQAECgEIAQAAAA==.',
Be='Beardiso:BAAANQAECgYIDgAAAA==.Beastcleave:BAAANQAECgQICAAAAA==.Beelz:BAAANQAECgYIEQAAAA==.Bekens:BAAANQAECgYIDAAAAA==.Belaraariaae:BAAANQADCggIDQABNQAECgcJFgAMAEUgAA==.Benipal:BAABNQAECoExAAIIAAkKoBzgPwCwAgAIAAkKoBzgPwCwAgAAAA==.Bernardboggs:BAAANQAECgYIEwAAAA==.',
Bh='Bheefknight:BAABNQAECoEXAAQNAAkK9ArmWQBpAQANAAgKHQvmWQBpAQAOAAIKcQn5vwBJAAAPAAEKqgFopQAZAAAAAA==.Bheeftotemz:BAAANQADCgUICQAAAA==.',
Bi='Bierbro:BAABNQAECoEWAAMPAAgKTxmBKAAhAgAPAAgKTxmBKAAhAgAOAAEKawG44wAeAAAAAA==.Bigsofty:BAAANQAECgIIAwAAAA==.Billiam:BAAANQAECgEIAQAAAA==.Billié:BAABNQAECoEgAAMJAAgKPRm5SQBYAgAJAAgKPRm5SQBYAgAKAAEKehsYZABPAAABNQAECggIKQAQANEhAA==.Bizron:BAAANQADCgYIBgAAAA==.',
Bl='Blightheaded:BAAANQAECgQIBAAAAA==.Blumir:BAAANQAECgcIDwAAAA==.',
Bo='Bogatyri:BAAANQADCgIIAgAAAA==.Bomgan:BAAANQAECgYIEAAAAA==.Bonchonn:BAABNQAECoEoAAILAAkKLiT9CACGAwALAAkKLiT9CACGAwAAAA==.Bonkula:BAAANQAECgUICAAAAA==.Boognar:BAAANQADCgEIAQAAAA==.Boon:BAAANQAECgEIAQABNQAECgYIEwABAAAAAA==.Bops:BAAANQADCggIDQAAAA==.Borque:BAABNQAECoEZAAMRAAcKASDxXgBSAgARAAcKOR7xXgBSAgASAAMK0h6FIgAHAQAAAA==.Bosenmorimei:BAAANQADCgIIAgAAAA==.',
Br='Brae:BAAANQAECgMIBwAAAA==.Brazonk:BAAANQAECgUICQAAAA==.Brewzco:BAABNQAECoEfAAIMAAcKuiGJBwCkAgAMAAcKuiGJBwCkAgAAAA==.Bricifergoat:BAAANQAECgMIAwABNQAECgkJHAAOAP8kAA==.Briciferkong:BAABNQAECoEcAAIOAAkK/ySADQA4AwAOAAkK/ySADQA4AwAAAA==.Brickedup:BAAANQAECgEIAQAAAA==.Brightblayde:BAAANQAECgYIEwAAAA==.',
Bu='Buanto:BAAANQAECgEIAQAAAA==.Bubblegumm:BAAANQADCgYICQAAAA==.Bubbletea:BAAANQAECgUIDgABNQADCgYICQABAAAAAA==.Butterball:BAABNQAECoEaAAMRAAkKDhkdZQBAAgARAAgKNRsdZQBAAgASAAIKPQdONgBLAAAAAA==.Butterknight:BAAANQAECgYICwAAAA==.',
Ca='Candlelock:BAAANQAECgIIAwAAAA==.Candlewic:BAAANQAECgIIAgAAAA==.Cathal:BAAANQABCgYICgAAAA==.Cattroll:BAAANQAECgYICAAAAA==.',
Ce='Celithila:BAAANQAECgUIDQAAAA==.Celithvia:BAAANQAECgMIBAAAAA==.Cervantés:BAABNQAECoEdAAMTAAcK1BkQTQBCAQATAAQKyhoQTQBCAQAUAAQKqRhsLQA3AQAAAA==.',
Ch='Chaosknight:BAAANQAECgYIDgAAAA==.Charginatyou:BAAANQADCggIDwABNQAECggIJAAVABoTAA==.Charla:BAAANQADCgUIBwABNQAECggIIwALAG4UAA==.Chelsea:BAAANQADCggICgAAAA==.Chise:BAABNQAECoEcAAIWAAgKEhuGAwCdAgAWAAgKEhuGAwCdAgAAAA==.Chiza:BAAANQADCgUIBwAAAA==.Chob:BAAANQADCgcICwAAAA==.',
Cl='Clarry:BAAANQAECgEIAQAAAA==.Clyde:BAAANQAECgEIAQAAAA==.Clydk:BAAANQAECgIIAwAAAA==.',
Co='Coachbeard:BAABNQAECoEbAAIXAAgKzhVDSgAfAgAXAAgKzhVDSgAfAgAAAA==.Colzaratha:BAAANQAECgQIDAAAAA==.Conrow:BAAANQADCgQIBAAAAA==.Coorsbanquet:BAABNQAECoETAAIYAAYKsx/4HAAjAgAYAAYKsx/4HAAjAgAAAA==.Copernicus:BAAANQAECgQIBAAAAA==.Corian:BAAANQADCgQIBAAAAA==.Corndog:BAABNQAECoEjAAMCAAkKSBkEjwBGAgACAAgKxRcEjwBGAgAZAAIK3hyaJgCaAAAAAA==.Corpsereth:BAAANQADCggICAAAAA==.Cozzworth:BAAANQADCgEIAQAAAA==.',
Cr='Cronchybacon:BAAANQADCgcIBwAAAA==.',
Cu='Cudguzzler:BAAANQAECgIIAgAAAA==.Cursegoesmoo:BAAANQAECgYIDgAAAA==.Cursehoots:BAABNQAECoEoAAIaAAkK5iItDABbAwAaAAkK5iItDABbAwAAAA==.',
Cy='Cygna:BAAANQADCgQIBAAAAA==.Cyntheria:BAABNQAECoEfAAIIAAgKAhxpUwByAgAIAAgKAhxpUwByAgAAAA==.',
Da='Daddybeàr:BAABNQAECoEnAAUGAAkKVR/zCQANAwAGAAkKVR/zCQANAwAbAAQKXxYbHwDsAAAcAAIK6RXxOwCEAAAaAAIKIA7DkABeAAAAAA==.Daendron:BAAANQAECgYIBgAAAA==.Darksaxon:BAAANQAECgYIDgAAAA==.Darorek:BAAANQAECgUIDwAAAA==.',
De='Deathnethal:BAAANQADCgYIBgAAAA==.Deathweaver:BAABNQAECoEkAAMTAAkK9CRbAQDMAwATAAkK9CRbAQDMAwAUAAgKDiONBwD4AgAAAA==.Debumanko:BAAANQADCggIDgAAAA==.Decima:BAAANQADCggIEwAAAA==.Deeneye:BAAANQADCgYIEAABNQAECgUIBwABAAAAAA==.Delerai:BAAANQAECgIIAwAAAA==.Dellgado:BAAANQAECgUIBwAAAA==.Deme:BAAANQAECgUIBgAAAA==.Demonbains:BAAANQAECgEIAQAAAA==.Demonica:BAAANQAECgUIDAAAAA==.Demonscythe:BAAANQADCgcIEQAAAA==.Dendrax:BAABNQAECoEZAAMKAAcKWghZSgCVAAAJAAYKKQdjwgAYAQAKAAMKeghZSgCVAAAAAA==.Dented:BAAANQABCgQIBAAAAA==.Deviance:BAAANQAECgIIAwAAAA==.Dezwar:BAAANQADCgEIAQABNQAFFAYIEwAZADwhAA==.',
Di='Dissonance:BAAANQADCgUIBQAAAA==.',
Dj='Djanga:BAAANQADCgYIBgABNQAECgYIEgABAAAAAA==.Djdazzle:BAAANQAECgEIAQAAAA==.',
Do='Dogbearcat:BAAANQADCgQIBAABNQAFFAMIAwABAAAAAA==.Dorito:BAAANQAFFAEIAQAAAA==.',
Dr='Dragooned:BAACNQAFFIEKAAIZAAUKLhS0AACKAQAZAAUKLhS0AACKAQA1AAQKgSIAAhkACQrPJYcBAGEDABkACQrPJYcBAGEDAAAA.Drahhrak:BAAANQADCgQIBwAAAA==.Drango:BAAANQAECgUICgAAAA==.Draugdae:BAAANQAECgUIDQAAAA==.Draxtor:BAAANQADCgQIBAAAAA==.Drinksomuch:BAAANQAECgYIEQAAAA==.Drizzlin:BAAANQADCgYIBgAAAA==.Drleche:BAAANQADCgEIAQAAAA==.Drob:BAEANQAECgYIDgAAAA==.Drocket:BAEANQAECgYIEQAAAA==.Drome:BAAANQADCgcIDwABNQAECgQIDAABAAAAAA==.Drukhi:BAABNQAECoEaAAILAAgKzCHpHwD8AgALAAgKzCHpHwD8AgAAAA==.',
Du='Dudetotems:BAAANQAECgcIEAAAAA==.Dungrough:BAAANQAECgUICgAAAA==.Durtkal:BAABNQAECoEfAAMJAAgKTBTFcwDcAQAJAAcKSBPFcwDcAQAKAAIKQxjWTACNAAAAAA==.',
Dy='Dyonn:BAAANQAECgUIDQAAAA==.',
Ef='Efarel:BAABNQAECoEeAAIRAAgKDRTqawAuAgARAAgKDRTqawAuAgAAAA==.Efdis:BAAANQADCgIIAgAAAA==.',
Ei='Eienarinna:BAAANQADCgYIBgAAAA==.Eilana:BAABNQAECoEdAAMNAAkKiBjmJQByAgANAAkKiBjmJQByAgAOAAcKTAaiegAHAQABNQAFFAMIAwABAAAAAA==.Eilària:BAAANQADCgQICwAAAA==.',
El='Elsa:BAABNQAECoEbAAMZAAgKLwgvHgDUAAACAAgKrAXq6ACSAQAZAAUKCgovHgDUAAAAAA==.',
Em='Emma:BAAANQADCggJDgAAAA==.',
En='Eneco:BAABNQAECoEmAAIHAAkK8yF1CQBmAwAHAAkK8yF1CQBmAwAAAA==.Enserath:BAAANQADCgYICwAAAA==.',
Eu='Eurythmics:BAAANQAECgYIEAAAAA==.',
Ev='Evonahh:BAAANQADCgQIBAAAAA==.',
Ex='Exelion:BAABNQAECoEbAAIHAAgKjx0kJQC6AgAHAAgKjx0kJQC6AgAAAA==.Explogan:BAAANQAECgEIAQAAAA==.',
Ez='Ezanah:BAAANQADCgIIBAAAAA==.Ezrack:BAAANQADCgYICAABNQAECgIIAgABAAAAAA==.',
Fa='Faaith:BAAANQADCgcIFwAAAA==.Fahooquazaad:BAAANQADCggIKgAAAA==.Fancie:BAAANQADCggIEAABNQAECggIGAAPAMYJAA==.Fancy:BAAANQAECgcIEwAAAA==.',
Fe='Feetlesmcdee:BAAANQAECgUIDQAAAA==.Felfáádaern:BAAANQADCgEJAQAAAA==.Felporch:BAAANQAECgIIAwAAAA==.',
Fi='Fitzy:BAABNQAECoEWAAMdAAYKnRsXJQCJAQAdAAUK/B0XJQCJAQAXAAIKhQOH9wBUAAAAAA==.',
Fl='Flowermound:BAAANQAECgMIBQAAAA==.',
Fo='Fourqto:BAAANQAECgYIEAAAAA==.Fox:BAACNQAFFIENAAIHAAUKNR4+CADlAQAHAAUKNR4+CADlAQA1AAQKgSMAAgcACQryIt4TABkDAAcACQryIt4TABkDAAAA.',
Fr='Freya:BAAANQADCgUIBQAAAA==.',
Fu='Fujikujaku:BAAANQAECgYIDgAAAA==.Fulmetal:BAAANQAECgcIEgAAAA==.Funji:BAAANQAECgYIEgAAAA==.Funkalicious:BAABNQAECoEZAAMeAAgKDQoyfwBgAQAeAAgKDQoyfwBgAQAQAAMKxQu34wCSAAAAAA==.',
['Fé']='Félo:BAABNQAECoEYAAMKAAcKvSQaIwBNAQAJAAUKQSPoZwD+AQAKAAMKsiUaIwBNAQAAAA==.',
Ga='Gaila:BAABNQAECoEpAAMQAAgK0SHlHAADAwAQAAgKWCHlHAADAwAVAAYKPSHYEwAEAgAAAA==.Garathor:BAAANQABCgQIBQAAAA==.Garrosh:BAAANQABCgMIAwAAAA==.Garthoneeye:BAAANQADCggIFgAAAA==.Gazreyna:BAAANQAECgMIBAAAAA==.',
Ge='Genryusai:BAAANQAECgQIBAAAAA==.Genós:BAABNQAECoEbAAMRAAgKyhiSZABCAgARAAgKyhiSZABCAgAfAAEKywxKLgAzAAAAAA==.Gerardo:BAAANQAECgUIDQAAAA==.',
Gi='Gigarawr:BAAANQAECgMIBgABNQAECgYJCQABAAAAAA==.Ginnee:BAAANQAECgYIEAAAAA==.',
Gl='Glakattack:BAABNQAECoEhAAICAAgKeQk21wCyAQACAAgKeQk21wCyAQAAAA==.Glein:BAABNQAECoEdAAQIAAgKFCPxNQDVAgAIAAgKpyLxNQDVAgAdAAIKaCN7QADMAAAXAAQKqwgMywC+AAAAAA==.Gleivoker:BAAANQAECgUICAABNQAECggIHQAIABQjAA==.',
Gn='Gnomeisbis:BAAANQADCggICAAAAA==.',
Go='Gongfu:BAAANQADCgEIAQAAAA==.Gooeyquiver:BAAANQADCgMIBQAAAA==.',
Gr='Graestoke:BAAANQAECgQICAABNQAECgkJHgAgAFsfAA==.Granthar:BAAANQADCgUIBQAAAA==.Greasermorty:BAAANQADCgMIAwAAAA==.Grimixtalis:BAAANQADCggIDwAAAA==.Growls:BAABNQAECoEcAAQcAAcKDCL4CQCaAgAcAAcKbiH4CQCaAgAbAAUKVBkYFQBwAQAGAAEKQwkJaQAwAAAAAA==.Grundlegnome:BAAANQAECgcIDQABNQAECgkJLgATAOghAA==.',
Gu='Gurri:BAAANQAECgUICwAAAA==.',
['Gõ']='Gõldenchild:BAAANQAECgIIAgAAAA==.',
Ha='Habenero:BAAANQAECgMIBAAAAA==.Hairypitts:BAAANQAECgUIDQAAAA==.Happychaos:BAAANQAECgQIBAAAAA==.Haraniantha:BAABNQAECoEWAAIMAAcKRSCiCwAwAgAMAAcKRSCiCwAwAgAAAA==.Hatean:BAAANQAECgIIAgAAAA==.Hathor:BAAANQAECgQIDwAAAA==.Hazzbek:BAAANQADCgcIDwAAAA==.',
He='Heiboss:BAAANQAECgIIBAABNQAECggIHgANAFQkAA==.Heibub:BAAANQAECgEIAQABNQAECggIHgANAFQkAA==.Heiranir:BAAANQAECgUIEAABNQAECggIHgANAFQkAA==.Heiretic:BAAANQAECgUICgABNQAECggIHgANAFQkAA==.Heithyr:BAAANQADCgMIBAABNQAECggIHgANAFQkAA==.Helos:BAAANQADCgcICgAAAA==.Hemit:BAAANQAECgQIBgABNQAECgkJHgAgAFsfAA==.',
Hi='Hikikomori:BAAANQAECgEIAQABNQAECgcIPgANAC8lAA==.Hildegarde:BAAANQAECgYIEwAAAA==.Himura:BAAANQAECggICAAAAA==.Hinomiko:BAAANQAECgUIDAAAAA==.',
Ho='Holycowch:BAAANQADCgEIAQAAAA==.Hootiedixon:BAAANQADCgIIAgAAAA==.Hotdog:BAAANQAECgUIBQABNQAECgkJIwACAEgZAA==.',
Hu='Huran:BAABNQAECoEeAAINAAgKVCRzDQA0AwANAAgKVCRzDQA0AwAAAA==.',
Hx='Hx:BAAANQADCgMIAwABNQAECgQICgABAAAAAA==.',
Ia='Iatemydad:BAAANQAECgYIEgAAAA==.',
Ic='Icéehawt:BAEANQAECgUICwABNQADCgUIBQABAAAAAA==.',
Ig='Ignignokt:BAEBNQAECoEcAAMLAAkK/CI8HAANAwALAAgKQSU8HAANAwAhAAQKchOyRgDyAAAAAA==.',
Im='Imagine:BAABNQAECoEcAAIeAAgKVyQYEAAtAwAeAAgKVyQYEAAtAwAAAA==.',
In='Inarush:BAABNQAECoEgAAIiAAcKCg5GEQBqAQAiAAcKCg5GEQBqAQAAAA==.',
Ir='Ironshield:BAAANQAECgQIBAABNQAECgkJJQAQAKYYAA==.',
Iw='Iwishiknew:BAAANQAECgYIDgAAAA==.',
Iz='Iztras:BAAANQADCgEIAQAAAA==.',
Ja='Jabbtrak:BAAANQAECgYIEgAAAA==.Jabttrak:BAAANQAECgcICgAAAA==.Jacklowry:BAAANQAECgUIDwAAAA==.Jakiepoobear:BAABNQAECoEhAAIhAAgKxhdnHwA3AgAhAAgKxhdnHwA3AgAAAA==.Jalador:BAAANQADCggICAAAAA==.Jambie:BAAANQAECgcIEQAAAA==.',
Je='Jedery:BAAANQAECgYIDgAAAA==.',
Ji='Jivepepper:BAAANQADCggIDwAAAA==.',
Jo='Jolynn:BAAANQAECgcIDgAAAA==.Joroldess:BAABNQAECoEbAAIdAAgKrRy5DgCMAgAdAAgKrRy5DgCMAgAAAA==.Joyo:BAAANQADCgUIDAAAAA==.',
Ju='Juzam:BAAANQADCgYIEwAAAA==.',
Ka='Kahghär:BAAANQAECgUICgAAAA==.Kahlly:BAAANQAECgUIDwAAAA==.Kahndumb:BAAANQAECgYICAAAAA==.Kaida:BAAANQAECgMIBwAAAA==.Kaio:BAAANQAECgcIDgAAAA==.Kalahan:BAAANQAECgIIAwAAAA==.Kaotut:BAAANQADCgQIAwAAAA==.Kardrion:BAAANQAECgEJAQAAAA==.Karigyn:BAAANQAECgYIEQAAAA==.Kaskaa:BAAANQADCggIDAAAAA==.Katelina:BAAANQAECgQICQAAAA==.Katren:BAAANQADCgMIAwAAAA==.Katrienne:BAAANQAECgYIEQAAAA==.Katrya:BAAANQABCgQIBAABNQAECgYIEQABAAAAAA==.Kaylid:BAAANQAECgYIEQAAAA==.Kazzoth:BAABNQAECoEaAAILAAgKuwrxgQDZAQALAAgKuwrxgQDZAQAAAA==.',
Ke='Keilen:BAAANQADCgQIAwAAAA==.Keiyo:BAAANQADCggIFgAAAA==.Ketsuana:BAAANQADCgcIDQABNQAECgQIEAABAAAAAA==.Ketsukusai:BAAANQADCggJDwAAAA==.',
Kh='Khally:BAAANQADCggICwAAAA==.',
Ki='Kilen:BAAANQABCgUICQAAAA==.Kilimanjaro:BAAANQADCgcIDwAAAA==.Killjôy:BAAANQADCgIIAgAAAA==.Kimjongboom:BAABNQAECoEfAAIaAAkKbCQaCwBlAwAaAAkKbCQaCwBlAwAAAA==.',
Kl='Klax:BAAANQADCgcJDAAAAA==.Klondor:BAAANQAECgMIAwAAAA==.Klz:BAAANQAECgIIAQAAAA==.Klzx:BAAANQAECgUICwAAAA==.',
Ko='Komo:BAACNQAFFIEIAAIJAAYKFhZrBQDvAQAJAAYKFhZrBQDvAQA1AAQKgSEAAwkACQpGIdsTACgDAAkACQpGIdsTACgDAAoAAQrJIb5dAGEAAAAA.Konokusotare:BAAANQAECgQIBQAAAA==.Korbi:BAAANQADCgYICgABNQAECgcIHAAQAGoIAA==.Korbs:BAABNQAECoEaAAMUAAgK9A87GAAJAgAUAAgKag87GAAJAgATAAEKQRLxhQA9AAAAAA==.Kortek:BAAANQADCgUIBQAAAA==.Korvold:BAABNQAECoEeAAIRAAcKCRsUZwA7AgARAAcKCRsUZwA7AgAAAA==.',
Kr='Krak:BAAANQABCgYICAAAAA==.Kralkor:BAAANQADCgQIAwAAAA==.Kreckon:BAAANQAECgQIBgAAAA==.Kronn:BAAANQAECgUICgABNQAECggIFgAHAFsZAA==.',
Ks='Kschnell:BAAANQADCgQIBQABNQAECgkJMQACAMsiAA==.',
Ku='Kukulkan:BAAANQAECgQIDQAAAA==.Kuulan:BAABNQAECoEbAAIIAAgKqRZndQATAgAIAAgKqRZndQATAgAAAA==.',
Ky='Kythra:BAAANQAECgEIAQAAAA==.',
La='Lanstin:BAAANQADCgUIBgAAAA==.',
Le='Leafpool:BAAANQADCgYIBgAAAA==.Leancuisine:BAAANQAECgUIBgAAAA==.Leetlebug:BAAANQADCggIDwAAAA==.Leofull:BAAANQAECgUICQAAAA==.Lettÿ:BAAANQAECgUIDQAAAA==.Lexapro:BAAANQAECgEJAQAAAA==.',
Li='Lickemraw:BAAANQADCgQIBAAAAA==.Lightzwrath:BAAANQAECgYIDAABNQAECggIGwAcAEgLAA==.Lilithphage:BAAANQAECgMIBQAAAA==.Lilstorm:BAAANQADCgMIAwAAAA==.Littlenewt:BAAANQADCgYIBgAAAA==.',
Lo='Lockbealady:BAAANQADCgYIBgAAAA==.Lockdiso:BAAANQAECgcIAgAAAA==.Lorebeard:BAAANQAECgQIBQAAAA==.Loreix:BAAANQAECgUIDgAAAA==.Loreous:BAAANQADCgUIBQABNQAECggIFgAHAFsZAA==.',
Lr='Lrock:BAAANQABCgYIAwAAAA==.',
Lu='Luther:BAAANQADCgQIBQABNQAECgYIEwABAAAAAA==.Luvinez:BAAANQADCggIEAAAAA==.Luvinz:BAAANQAECgUIDQAAAA==.Luxuria:BAAANQAECgQIBwAAAA==.',
Ly='Lycanhunter:BAAANQAECgQICAAAAA==.Lycansham:BAAANQAECgEIAQAAAA==.Lyse:BAEANQAECgIIBAAAAA==.',
Ma='Maarc:BAAANQAECgUICQAAAA==.Machantu:BAAANQADCggIDgAAAA==.Madfurion:BAAANQAECgUIDQAAAA==.Magebot:BAABNQAECoEeAAIZAAcKMBDhDwB/AQAZAAcKMBDhDwB/AQAAAA==.Maggotbag:BAAANQADCgYICgAAAA==.Magicmandan:BAAANQADCgUIBQAAAA==.Magikstik:BAAANQAECgUICQAAAA==.Mahgrim:BAAANQADCgMIAwAAAA==.Majestic:BAABNQAECoExAAICAAkKyyK9GwBfAwACAAkKyyK9GwBfAwAAAA==.Maliná:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Malvenue:BAAANQADCgMIBAAAAA==.Marchesa:BAAANQADCgcIBwAAAA==.Markdashaman:BAAANQADCgIIAgAAAA==.Mauwy:BAABNQAECoEZAAMQAAgKRRZ8WQDpAQAQAAcKSxh8WQDpAQAeAAMKLwYJ3ACGAAAAAA==.',
Mc='Mcbullseye:BAAANQAECgUIBQAAAA==.',
Me='Megarah:BAAANQADCgYIFgAAAA==.Mepkaelpto:BAAANQADCgYIBgAAAA==.Meretrix:BAAANQAECgYIEAAAAA==.Mersadie:BAAANQAECgYIEgAAAA==.Metanya:BAAANQAECgYICgAAAA==.Mew:BAAANQAECgUICQAAAA==.',
Mi='Miateh:BAAANQAECgQIBAAAAA==.Mimicme:BAABNQAECoEfAAILAAgK2yEdIAD7AgALAAgK2yEdIAD7AgAAAA==.Mirajanê:BAAANQAECgMIBAAAAA==.Mitchell:BAAANQAECgUICgAAAA==.Miwah:BAAANQAECgQIEAAAAA==.Mizzheals:BAAANQAECgUIEQAAAA==.',
Mo='Mogarr:BAAANQADCgcICwAAAA==.Monkhei:BAAANQADCgEIAQABNQAECggIHgANAFQkAA==.Moocifer:BAABNQAECoEbAAIIAAgKRhEXkwDJAQAIAAgKRhEXkwDJAQAAAA==.Mooglewing:BAAANQAECgQIBwAAAA==.Moomoobrncow:BAAANQAECgYICQAAAA==.Mooriahdairy:BAAANQAECgQIBAAAAA==.Moorrigån:BAAANQADCgIIAgAAAA==.Mordicanta:BAAANQAECgYIEgAAAA==.Morgannon:BAAANQADCgUIBQAAAA==.Morphies:BAAANQADCgEIAQAAAA==.',
Mu='Muerr:BAABNQAECoEXAAILAAgKxiKcHwD9AgALAAgKxiKcHwD9AgAAAA==.Muerrizond:BAAANQADCgcIDQABNQAECggIFwALAMYiAA==.Muggel:BAAANQADCggIFQAAAA==.Mumraa:BAAANQAECgQIBgAAAA==.Mushroohead:BAAANQAECgQICwAAAA==.',
My='Mysterbyrnes:BAAANQAECgUIBQAAAA==.Myykiel:BAAANQAECgYICQAAAA==.',
Na='Naia:BAAANQAECgIIAgABNQAECgcIHwAMALohAA==.Naina:BAAANQAECgUIDQAAAA==.Najaja:BAAANQAECgMIBwAAAA==.Namii:BAAANQAECgUICQAAAA==.Narsum:BAAANQADCgYIBgAAAA==.Natacha:BAAANQAECgMIBQAAAA==.Navadurga:BAABNQAECoEZAAIGAAkKHQvzLwBmAQAGAAkKHQvzLwBmAQAAAA==.',
Ne='Necro:BAABNQAECoE+AAINAAcKLyXkEwD3AgANAAcKLyXkEwD3AgAAAA==.Nedrali:BAAANQAECgUIBQABNQAECggIGQAQAEUWAA==.Nedrina:BAAANQADCgcIBwABNQAECggIGQAQAEUWAA==.Netrath:BAAANQAECgIIAgAAAA==.',
Ni='Nidom:BAAANQAECgIIAgAAAA==.Nighammer:BAAANQAECgQIBgAAAA==.Nimeesha:BAAANQADCgMJAwAAAA==.Ninmah:BAAANQADCggIFwAAAA==.Nirø:BAAANQAECgIIAwAAAA==.',
No='Nooki:BAABNQAECoEWAAMHAAgKWxmuPQBPAgAHAAgKWxmuPQBPAgAgAAIKEhOJVwB7AAAAAA==.Notgretuh:BAAANQAECgcIDgAAAA==.',
Ny='Nyrikah:BAAANQADCggIGwAAAA==.',
Ob='Obidiah:BAAANQAECgYIEQAAAA==.',
Od='Oddearth:BAAANQAECgEIAQAAAA==.',
Om='Omegablivet:BAAANQADCgMJAwAAAA==.',
Or='Orah:BAAANQADCgYICwAAAA==.',
Pa='Palagem:BAAANQAECgUIDQAAAA==.Palidingo:BAAANQADCgEIAQAAAA==.Palinyes:BAAANQAECgYIEAAAAA==.Pandabutz:BAAANQAECgYIDQAAAA==.Pandahands:BAAANQADCgIIAgAAAA==.Panduh:BAAANQAECgUICAAAAA==.Pandussy:BAAANQAECgcIBwAAAA==.Papabill:BAABNQAECoEoAAIIAAgKXwf4vABqAQAIAAgKXwf4vABqAQAAAA==.Papaharny:BAABNQAECoEYAAMQAAcKKwIiuwDtAAAQAAcKKwIiuwDtAAAVAAEKdgGJNAAcAAABNQAECggIKAAIAF8HAA==.Paragorn:BAAANQAECgUICwAAAA==.Pattee:BAAANQAECgYIDAAAAA==.Pawp:BAAANQABCgIIAgAAAA==.',
Pe='Pech:BAAANQAECgEIAgABNQAECgYJCQABAAAAAA==.Pechay:BAAANQADCgIJBAABNQAECgYJCQABAAAAAA==.Peenidin:BAABNQAECoEaAAIXAAgKBiDpHADpAgAXAAgKBiDpHADpAgAAAA==.Peepo:BAABNQAECoEuAAITAAkK6CFfBgBXAwATAAkK6CFfBgBXAwAAAA==.Pemerd:BAABNQAECoEWAAIaAAcKwx0nKwBcAgAaAAcKwx0nKwBcAgAAAA==.',
Ph='Phoze:BAAANQAECgUIDwAAAA==.Phozzack:BAAANQADCggIEgAAAA==.Phyai:BAAANQAECgUIDwAAAA==.',
Pl='Pliny:BAABNQAECoElAAIQAAkKphijOABtAgAQAAkKphijOABtAgAAAA==.',
Pn='Pnutt:BAAANQAECgMIBAAAAA==.',
Po='Pocahauntas:BAAANQAECgIIAgAAAA==.Porphyriia:BAAANQADCggICAAAAA==.',
Pr='Priestglein:BAAANQADCgUIBQABNQAECggIHQAIABQjAA==.Promethyus:BAAANQADCgcIDQAAAA==.Promidan:BAAANQAECgQIBgABNQADCggIDAABAAAAAA==.Prymus:BAABNQAECoEiAAIdAAgKgB+gDQCeAgAdAAgKgB+gDQCeAgAAAA==.Pryxi:BAABNQAECoEbAAIZAAcK5hFpDgCYAQAZAAcK5hFpDgCYAQAAAA==.',
Pu='Punkalicious:BAAANQAECgYIDQAAAA==.',
Py='Pyrogar:BAAANQADCgYIBgAAAA==.Pythius:BAAANQAECgQIBgAAAA==.',
['Pó']='Pótatò:BAAANQAECgIIAgAAAA==.',
Qu='Quetip:BAAANQADCgMIAwAAAA==.Quiksylver:BAABNQAECoEhAAQXAAgKLhnINwBpAgAXAAgKLhnINwBpAgAIAAMKRhDGJwGiAAAdAAMKfAL+VABcAAAAAA==.',
Ra='Rakael:BAAANQADCgcIBwAAAA==.Randumb:BAAANQADCgUIBQAAAA==.Ratshot:BAABNQAECoEzAAILAAkKRRxkHwD+AgALAAkKRRxkHwD+AgABNQAECgkJOgAjACQjAA==.Rawty:BAAANQADCgUICQAAAA==.Rayse:BAAANQADCgYIBgAAAA==.',
Re='Red:BAABNQAECoEWAAIPAAcKLBskLQAAAgAPAAcKLBskLQAAAgAAAA==.Relgul:BAAANQADCgYICwAAAA==.Rellster:BAABNQAECoEeAAMRAAgKehLzfAAAAgARAAgKehLzfAAAAgAfAAEKFAsNLgAzAAAAAA==.Renix:BAAANQADCgUIBQAAAA==.Rennyo:BAABNQAECoEcAAIYAAcK2SKhEQCzAgAYAAcK2SKhEQCzAgAAAA==.Resonance:BAAANQADCggJFwAAAA==.Rexion:BAAANQAECgQIDAAAAA==.Rezator:BAAANQAECgEIAQAAAA==.',
Ri='Rigg:BAAANQADCggIEAAAAA==.Riggsy:BAAANQAECgUIDgABNQADCggIEAABAAAAAA==.Riggzbuffs:BAAANQADCgYICwABNQADCggIEAABAAAAAA==.Rivenp:BAAANQADCggIGgAAAA==.',
Ro='Rocknroll:BAABNQAECoEVAAILAAcKDRdweQDtAQALAAcKDRdweQDtAQAAAA==.Rokbiter:BAAANQAECgIIAwAAAA==.Roll:BAAANQAFFAMIAwAAAA==.Rothound:BAAANQAECgQIBgAAAA==.Rozgrez:BAAANQAECgYIEQAAAA==.',
Ru='Runefflck:BAABNQAECoEaAAMkAAcKZxn3BgAQAgAkAAcKZxn3BgAQAgAJAAEKSgaZJwExAAAAAA==.Russbus:BAACNQAFFIEFAAIIAAMK3wfbFQDGAAAIAAMK3wfbFQDGAAA1AAQKgR0AAggACQoSGcJpADICAAgACQoSGcJpADICAAAA.',
Ry='Rynari:BAAANQADCgcIDAABNQAECggIHwAOABgPAA==.Rynmorelle:BAABNQAECoEfAAIOAAgKGA+aTgCxAQAOAAgKGA+aTgCxAQAAAA==.',
['Ré']='Réven:BAABNQAECoEbAAMlAAgKqx6ZFwC+AgAlAAgKqx6ZFwC+AgAjAAUKthoVOABcAQAAAA==.',
['Rí']='Rínoah:BAAANQADCgYIDQAAAA==.',
['Rô']='Rôckbôttôm:BAAANQAECgcIBwAAAA==.',
Sa='Sakura:BAAANQAECgcIEwAAAA==.Sane:BAABNQAECoEYAAQPAAcKeBm2MQDgAQAPAAcKVRa2MQDgAQANAAUKGRIobwATAQAOAAQKPhd+gQDvAAAAAA==.Saoiirse:BAAANQAECgMIBAAAAA==.',
Se='Searshaa:BAAANQADCgcIBwAAAA==.Seershaa:BAAANQADCgYIBgAAAA==.Seriux:BAAANQADCgUIBQAAAA==.Sevencharlie:BAAANQAECgUICAAAAA==.',
Sh='Shadowfate:BAABNQAECoEZAAIHAAgKQhLRVgDwAQAHAAgKQhLRVgDwAQAAAA==.Shadê:BAAANQADCgYIBgAAAA==.Shaftted:BAAANQADCgQIBAABNQADCggIGwABAAAAAA==.Shamanyou:BAAANQADCgEIAQAAAA==.Shamiqua:BAAANQAECgYIDgAAAA==.Shamutty:BAAANQADCgQIBAABNQAECgkJHgAgAFsfAA==.Shentao:BAABNQAECoEYAAIYAAgKCAQBOQAUAQAYAAgKCAQBOQAUAQAAAA==.Shinjô:BAAANQAECgcIDQAAAA==.Shirikao:BAAANQADCgYIBgAAAA==.Shiroishi:BAAANQAECgQICwAAAA==.Shivaray:BAAANQAECgQJBAAAAA==.Shocklesner:BAAANQAECgYIDgAAAA==.Shomade:BAAANQADCgQIBwAAAA==.Shouganai:BAAANQAECgQIBwAAAA==.Shupaz:BAAANQAECgIIAwAAAA==.',
Si='Sifu:BAAANQAECgYICwAAAA==.Silverlight:BAAANQAECgUICAAAAA==.Simira:BAAANQAECggIBgAAAA==.Simp:BAAANQADCgQIBAAAAA==.Sinaar:BAAANQADCgQIBAAAAA==.Sindena:BAAANQAECgQIBAAAAA==.',
Sk='Skyemage:BAAANQADCggIFAAAAA==.',
Sl='Sloked:BAAANQAECgcIDgAAAA==.Slokep:BAAANQADCgQIBAAAAA==.Slokes:BAAANQADCgIIAgAAAA==.Slotz:BAAANQAECgYIEQAAAA==.',
Sm='Smitepanda:BAAANQADCgcICAAAAA==.',
Sn='Sneeze:BAAANQADCgcIFQAAAA==.Snekashifty:BAAANQAECgMIAwAAAA==.Snowsham:BAAANQADCgUJBQAAAA==.',
So='Sonarr:BAAANQAECgMIBgAAAA==.Sozzle:BAAANQADCgUIBQABNQAECgkJMQACAMsiAA==.',
Sp='Spark:BAAANQAECgQIBQAAAA==.Spicymeat:BAAANQAECgcJEgABNQAECgkJMQACAMsiAA==.Sputty:BAABNQAECoEeAAIgAAkKWx+TDAALAwAgAAkKWx+TDAALAwAAAA==.',
Sq='Squanto:BAAANQAECgYICQABNQAECgkJMQACAMsiAA==.',
St='Stalken:BAAANQADCgYJCwAAAA==.Stealthdiso:BAAANQADCgUIBQAAAA==.Stesha:BAABNQAECoEXAAIIAAcKZgr+xwBSAQAIAAcKZgr+xwBSAQAAAA==.Stonedfrog:BAAANQADCggIGwAAAA==.Stonefather:BAAANQADCgUIBQAAAA==.Stïtches:BAAANQAECgUIDAAAAA==.Stönk:BAAANQAECgMIBAAAAA==.',
Su='Sugarlumps:BAAANQADCgEIAQAAAA==.Sungiver:BAAANQADCgUIBQAAAA==.Superdaman:BAAANQADCgEIAQAAAA==.',
Sw='Swaggles:BAAANQAECgYIEAAAAA==.Swïtches:BAAANQADCgYIBgAAAA==.',
Sy='Sygon:BAAANQAECgYIEgAAAA==.Sylm:BAAANQAECgQIBAABNQAECgkJNQAQAM8hAA==.Sylvannaa:BAAANQADCgEIAQAAAA==.Symbr:BAAANQAECgYICgAAAA==.Synglace:BAAANQAECgEIAQAAAA==.Syntherizena:BAAANQADCgcIBwAAAA==.',
Ta='Tacitus:BAAANQAECgYIEQAAAA==.Tairrad:BAAANQADCgUIBQABNQAECgUIBwABAAAAAA==.Takara:BAAANQADCgUIBQAAAA==.Takeru:BAAANQAECgYIEwAAAA==.Talasmar:BAAANQADCgMIAwAAAA==.Taliessin:BAAANQADCgYICgAAAA==.Talistian:BAAANQADCgIIAgAAAA==.Tarirn:BAAANQADCgYICwAAAA==.Tauntsinpvp:BAAANQAECgQIBwAAAA==.Taylia:BAAANQADCgYJBgABNQAECggIHAAWABIbAA==.Tazwomann:BAAANQAECgYIBgAAAA==.',
Te='Teaqo:BAAANQADCgUIBQABNQAECggIIQAcANAaAA==.Tebde:BAAANQAECgIIAgAAAA==.Tejina:BAAANQADCggICAAAAA==.Telinda:BAAANQABCgIIAgAAAA==.Tempestrasza:BAAANQADCgcICwAAAA==.Tendonitis:BAAANQABCgQIBAAAAA==.Teppe:BAAANQAECgYIEAAAAA==.Terial:BAAANQAECgYICwAAAA==.Terranovian:BAAANQAECgUIBwAAAA==.',
Th='Thajeebus:BAABNQAECoEZAAIaAAUK6RhBUQBtAQAaAAUK6RhBUQBtAQAAAA==.Thebigstein:BAAANQAECggIDgAAAA==.Thecapt:BAABNQAECoElAAIfAAkKQxY/BgCDAgAfAAkKQxY/BgCDAgAAAA==.Theôdöræ:BAAANQAECgIIAwAAAA==.Thunderkiss:BAAANQADCggICAAAAA==.',
Ti='Tiaoma:BAAANQADCggIDgAAAA==.Tiarlena:BAAANQABCgIIAgAAAA==.Tindle:BAAANQADCggICAAAAA==.Tinylock:BAAANQADCgUICQAAAA==.Tinymich:BAAANQADCgUIBwABNQAECgcIHAAYANkiAA==.',
Tj='Tjhookèr:BAAANQAECgEIAQAAAA==.',
To='Toetoms:BAAANQAECgQIBwAAAA==.Toletheus:BAABNQAECoEbAAIcAAgKwCQQBABNAwAcAAgKwCQQBABNAwAAAA==.Tomin:BAAANQADCgIIAgAAAA==.Toreshii:BAAANQADCgUICQAAAA==.Totamic:BAAANQABCgIIAgAAAA==.Totemique:BAAANQAECgQIBAABNQAECgcIGQARAAEgAA==.Totumfknpole:BAAANQADCgMIAwAAAA==.',
Tr='Trashkantz:BAAANQAECgQICgABNQAFFAYIFwACAFIjAA==.Treeperson:BAAANQAECgYIEQAAAA==.Trickyric:BAABNQAECoEaAAIIAAgK3BfAbwAiAgAIAAgK3BfAbwAiAgAAAA==.Trinak:BAAANQADCgQICAAAAA==.Trowel:BAAANQAECgQIBAABNQAECgkJHgAgAFsfAA==.',
Ts='Tsuyoimono:BAAANQAECgUICwABNQAECgUIDAABAAAAAA==.',
Tu='Turtleclap:BAAANQAECgMIAwAAAA==.',
Tw='Twistandgrip:BAABNQAECoEmAAIOAAgKkRM9RwDUAQAOAAgKkRM9RwDUAQAAAA==.Twylan:BAAANQADCgQIBAAAAA==.',
Ty='Tydroin:BAAANQADCgUIBQAAAA==.Tyinthor:BAAANQAECgMIBgAAAA==.Tytoalba:BAABNQAECoEWAAIXAAgKDiCGHQDmAgAXAAgKDiCGHQDmAgAAAA==.',
Un='Unholylean:BAAANQAECgIIAgAAAA==.',
Ur='Uratsukasama:BAAANQAECgUICgAAAA==.Urza:BAABNQAECoEVAAMIAAgKpwUfCAHZAAAIAAgKpwUfCAHZAAAXAAcKgwEo6wByAAAAAA==.',
Va='Vacaite:BAAANQADCgcIBwAAAA==.Vagiant:BAABNQAECoEcAAIbAAgKaRTMDAAeAgAbAAgKaRTMDAAeAgAAAA==.Vangers:BAAANQABCgMIAwAAAA==.Vangie:BAAANQAECgYICAAAAA==.Vangnaw:BAAANQAECgQICAAAAA==.Vanya:BAAANQAECgYIDAAAAA==.Vasso:BAAANQADCgYIFgAAAA==.Vayln:BAAANQAECgcIDQAAAA==.',
Ve='Veildreya:BAAANQABCgQIBAAAAA==.Veinygamer:BAABNQAECoEhAAIRAAgK7x7xQwClAgARAAgK7x7xQwClAgAAAA==.Veldian:BAAANQAECgYIEAAAAA==.Velveen:BAABNQAECoEcAAMQAAcKaggqjABVAQAQAAcKaggqjABVAQAeAAcK2gz0hwBIAQAAAA==.Vexahalia:BAABNQAECoEiAAQLAAkKqhLQYwAjAgALAAkKqhLQYwAjAgAhAAUK5wSMVACsAAAmAAIKzwuSDgB2AAAAAA==.',
Vi='Vicarious:BAAANQAECgcIDgAAAA==.Viciouslump:BAAANQADCggICAAAAA==.Vilebloom:BAEANQAECgYICQAAAA==.Vilewyrm:BAEANQADCgcIEgABNQAECgYICQABAAAAAA==.Violetblade:BAAANQADCgQIBAAAAA==.Viridius:BAAANQAECgEIAgAAAA==.',
Vo='Voidmulan:BAEANQADCgUIBQAAAA==.Voluga:BAAANQAECgEIAgAAAA==.',
Vr='Vraak:BAAANQADCggIJAAAAA==.',
Wa='Wagguslight:BAAANQAECgUICQAAAA==.',
We='Werstshot:BAAANQADCggIEwAAAA==.',
Wh='Whateverdude:BAAANQAECgYIEQAAAA==.',
Wi='Wicketlock:BAAANQAECgQIBAAAAA==.Wiickett:BAABNQAECoEgAAMDAAkKtQz5EwDvAQADAAkKtQz5EwDvAQAFAAUK2AIyNwC9AAAAAA==.Wildesel:BAAANQAECgQIAwAAAA==.Willaá:BAABNQAECoEYAAMPAAgKxglsSABSAQAPAAcKLQpsSABSAQANAAcK/QM0fADiAAAAAA==.Wilson:BAAANQAECgYIEwAAAA==.Wizzpeaver:BAAANQADCgcIBwAAAA==.',
Wo='Wonderwizard:BAAANQADCgIIAgAAAA==.',
Wr='Wrathhoof:BAAANQAECgQIBQABNQAECggIGwAcAEgLAA==.',
Xy='Xylias:BAAANQAECgQICgAAAA==.',
['Xá']='Xánada:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.',
Yo='Yorril:BAAANQADCgUIBQAAAA==.',
Yu='Yucca:BAAANQAECgUIEQAAAA==.Yuda:BAAANQAECgQIBgABNQAECgkJJgAHAPMhAA==.Yukiteru:BAAANQAECgEIAQAAAA==.Yurito:BAAANQADCgYIBgAAAA==.',
Za='Zabrina:BAAANQADCgcICQABNQAECgcIFwAIAGYKAA==.Zachie:BAAANQAECgcICwAAAA==.Zakutin:BAAANQAECgIIAwAAAA==.Zappybains:BAAANQAECgYIEQAAAA==.Zarakii:BAAANQAECgMIBQAAAA==.',
Ze='Zekken:BAAANQADCgMIAwAAAA==.Zelaira:BAAANQADCgMIAwABNQAECggIHwAOABgPAA==.',
Zi='Zigzagga:BAAANQADCgQIBAAAAA==.',
Zo='Zoinks:BAAANQADCgQIBQAAAA==.Zorandar:BAAANQAECgMIAwAAAA==.',
Zu='Zupaz:BAAANQADCgQIBAABNQAECgIIAwABAAAAAA==.',
Zy='Zylluz:BAABNQAECoEbAAMOAAgKyhzdKAB1AgAOAAgKUhzdKAB1AgAPAAcKwxEDPgCRAQAAAA==.',
['Äs']='Ästen:BAAANQAECgQIBwAAAA==.',
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
