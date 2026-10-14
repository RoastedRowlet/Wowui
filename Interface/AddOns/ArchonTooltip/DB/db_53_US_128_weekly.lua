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

local lookup = {'Warrior-Arms','Mage-Arcane','Mage-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Protection','Unknown-Unknown','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Druid-Restoration','DeathKnight-Blood','Paladin-Protection','Priest-Holy','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Druid-Guardian','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Shaman-Enhancement','Priest-Discipline','Paladin-Holy','Druid-Balance','Druid-Feral','Shaman-Restoration','Warrior-Fury','Warlock-Affliction','Priest-Shadow','DemonHunter-Vengeance','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Kargath',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaryn:BAAANQADCggICAABNQAECgcIHQABAOsKAA==.',
Ab='Abracadabruh:BAABNQAECn8WAAICAAgKshHevwADAgACAAgKshHevwADAgAAAA==.Absynthia:BAABNQAECn8YAAMDAAcKUAu6EgB5AQADAAcKUAu6EgB5AQACAAYK5AF9ewHFAAAAAA==.',
Ac='Academe:BAAANQAECgEIAQAAAA==.Accalon:BAAANQADCgYIBgAAAA==.',
Ad='Adérai:BAAANQAECgYICAAAAA==.',
Ae='Aellopus:BAABNQAECn8bAAMEAAkKzhXmFQCxAgAEAAkKzhXmFQCxAgAFAAQK0RS2XwD4AAAAAA==.Aero:BAABNQAECn8dAAMBAAcK6wpUtACUAQABAAcK6wpUtACUAQAGAAEKAAC4PwA9AAAAAA==.',
Ag='Agròm:BAAANQADCgQIBAABNQADCgcICwAHAAAAAA==.',
Ak='Akata:BAAANQADCgYIDAAAAA==.Akku:BAAANQADCgYIBwAAAA==.',
Al='Alanwake:BAABNQAECn8pAAQIAAkKERtcCwCwAgAIAAkKGxpcCwCwAgAJAAUKOhnLDwA+AQAKAAMKGQOZRgBmAAAAAA==.Aldourolf:BAAANQABCgQIBAAAAA==.Alomeo:BAEANQADCgYJCwAAAA==.Alphasmash:BAAANQAECgIIAgAAAA==.',
Am='Amiliane:BAAANQAECgUIEgAAAA==.Amilmean:BAAANQAECgMIAwAAAA==.Amoradine:BAAANQAECgIIAgAAAA==.Amz:BAAANQAECgIIAwAAAA==.',
An='Anadrien:BAABNQAECn8dAAILAAgKFRVtIwAGAgALAAgKFRVtIwAGAgAAAA==.Ancelagon:BAAANQADCgYIBwAAAA==.Andrae:BAAANQAECgQIBAAAAA==.Angrimia:BAABNQAECn8bAAIMAAcK2Bl+OgAZAgAMAAcK2Bl+OgAZAgAAAA==.Annussa:BAAANQAECgEIAQAAAA==.Antal:BAAANQADCgcIBwAAAA==.',
Ar='Arboria:BAAANQAECggIAgAAAA==.Arcadya:BAAANQADCgcIBwAAAA==.Archielgh:BAAANQADCgUIBQAAAA==.Ardbeg:BAAANQABCgcIDwAAAA==.Arduin:BAABNQAECn8XAAINAAYKiBKbMQBPAQANAAYKiBKbMQBPAQAAAA==.Aremethea:BAAANQAECgUIEgAAAA==.Aronk:BAAANQADCggIHAABNQAECgYIFgAMAMMEAA==.Arore:BAAANQADCgMJBQABNQAECgYIFgAMAMMEAA==.Aroreck:BAAANQADCgcICwABNQAECgYIFgAMAMMEAA==.Arorepriest:BAAANQAECgEIAQABNQAECgYIFgAMAMMEAA==.Articulaté:BAACNQAFFH8FAAIOAAIKHyUZIADZAAAOAAIKHyUZIADZAAA1AAQKfxwAAg4ACApRIUghAOcCAA4ACApRIUghAOcCAAAA.Arîel:BAAANQADCggICAAAAA==.',
As='Asbjorn:BAAANQAECgUIDQAAAA==.Ashvoyager:BAAANQABCgIIAgAAAA==.',
At='Atheania:BAAANQAECgIIAgAAAA==.Atheanos:BAAANQAECgIIAQAAAA==.Attack:BAAANQADCgQIBQABNQAFFAQIBQACAK8VAA==.',
Av='Avestara:BAABNQAECn8bAAIOAAcKECOJLAC0AgAOAAcKECOJLAC0AgAAAA==.',
Ay='Ayohec:BAAANQAECggICAAAAA==.',
Az='Azoril:BAABNQAECn8mAAIPAAkK9xIJgwAdAgAPAAkK9xIJgwAdAgAAAA==.Azùla:BAAANQAECgYIEAAAAA==.',
['Aí']='Aídeen:BAABNQAECn8XAAICAAgKuAIMNAExAQACAAgKuAIMNAExAQAAAA==.',
Ba='Babs:BAAANQADCgEIAQAAAA==.Badmooddude:BAAANQAECgQICAAAAA==.Baelnorn:BAABNQAECn8cAAMQAAcK5R59bAAUAgAQAAYKPB99bAAUAgARAAEKix2dZQBXAAAAAA==.Bains:BAAANQADCgcIBwAAAA==.Barrex:BAAANQAECgIIBQAAAA==.Basak:BAAANQAECgYICgABNQAFFAQICgAHAAAAAQ==.Basken:BAABNQAECn8eAAISAAcK8AfeuACNAQASAAcK8AfeuACNAQAAAA==.Batôsai:BAAANQAECgEIAQAAAA==.',
Be='Beardiso:BAAANQAECgYIDgAAAA==.Beastcleave:BAAANQAECgQICAAAAA==.Beelz:BAABNQAECn8YAAITAAcK7Q2SKABNAQATAAcK7Q2SKABNAQAAAA==.Bekens:BAAANQAECgcIEgAAAA==.Belaraariaae:BAAANQADCggIDQABNQAECgcJFgAUAG0gAA==.Benipal:BAACNQAFFH8HAAIPAAMKTwndGgDMAAAPAAMKTwndGgDMAAA1AAQKfzkAAw8ACQpNG8RUAJQCAA8ACQpNG8RUAJQCAA0ACAr/D+slAKwBAAAA.Bernardboggs:BAABNQAECn8eAAMVAAgK3xslGQB3AgAVAAgKwhglGQB3AgAUAAcKoRlmEADiAQAAAA==.',
Bh='Bheefknight:BAABNQAECn8ZAAQMAAkKXQxJZABeAQAMAAgK0AxJZABeAQAWAAIKcQmc0ABIAAAXAAEKqgFJvgAZAAAAAA==.Bheeftotemz:BAAANQADCgUICQAAAA==.',
Bi='Bierbro:BAABNQAECn8XAAMXAAkKjBfxKABMAgAXAAkKjBfxKABMAgAWAAEKawEw9wAeAAAAAA==.Bigsofty:BAAANQAECggICQAAAA==.Billiam:BAAANQAECgEIAQAAAA==.Billié:BAABNQAECn8kAAMQAAgKhhptVgBPAgAQAAgKhhptVgBPAgARAAEKehtuaQBNAAABNQAECggILAAYAJggAA==.Bizron:BAAANQADCgYIBgAAAA==.',
Bl='Blightheaded:BAAANQAECgQIBAAAAA==.Blumir:BAABNQAECn8WAAMKAAkKPhCbIQC/AQAKAAgKZg2bIQC/AQAIAAMKextQKgDSAAAAAA==.',
Bo='Bogatyri:BAAANQADCgIIAgAAAA==.Bomgan:BAABNQAECn8cAAMZAAcKnxcGKQAAAgAZAAcK1BQGKQAAAgASAAEKfx3FPgFaAAAAAA==.Bonchonn:BAACNQAFFH8FAAISAAIKwhtvHwCyAAASAAIKwhtvHwCyAAA1AAQKfy0AAhIACQpmJDQHAKMDABIACQpmJDQHAKMDAAAA.Bonkula:BAAANQAECgUIDQAAAA==.Boognar:BAAANQADCgEIAQAAAA==.Boon:BAAANQAECgcICAAAAA==.Bops:BAAANQADCggIDQAAAA==.Borque:BAABNQAECn8gAAMBAAkKDBwxQgDAAgABAAkKQxsxQgDAAgAGAAMK0h4aJwACAQAAAA==.Bosenmorimei:BAAANQADCgIIAgAAAA==.',
Br='Brae:BAAANQAECgMIBwAAAA==.Bralitha:BAAANQADCgQIBAAAAA==.Brazonk:BAAANQAECgUICgAAAA==.Brewzco:BAABNQAECn8mAAIUAAkK5yJHAgCJAwAUAAkK5yJHAgCJAwAAAA==.Bricifergoat:BAAANQAECgMIAwABNQAECgkJHAAWAAMmAA==.Briciferkong:BAABNQAECn8cAAIWAAkKAyYWEQAtAwAWAAkKAyYWEQAtAwAAAA==.Brickedup:BAAANQAECgEIAQAAAA==.Brightblayde:BAAANQAECgYIEwAAAA==.',
Bu='Buanto:BAAANQAECgIIAwAAAA==.Bubblegumm:BAAANQAECgEIAQAAAA==.Bubbletea:BAAANQAECgUIEwABNQAECgEIAQAHAAAAAA==.Butterball:BAABNQAECn8dAAMBAAkKmxtFagBPAgABAAgKmxtFagBPAgAGAAIKowZYPQBKAAAAAA==.Butterknight:BAAANQAECggIEQAAAA==.',
Ca='Candlelock:BAAANQAECgIIAwAAAA==.Candlewic:BAAANQAECgQIBgAAAA==.Casey:BAAANQADCgYIBgAAAA==.Cathal:BAAANQABCgYICgAAAA==.Cattroll:BAAANQAECgcIDQAAAA==.',
Ce='Celithila:BAAANQAECgUIEQAAAA==.Celithvia:BAAANQAECgUICQAAAA==.Cervantés:BAABNQAECn8kAAMaAAkKFBndIwBkAgAaAAgKbhbdIwBkAgAbAAQKghuPMQAsAQAAAA==.',
Ch='Chaosknight:BAABNQAECn8YAAMXAAcKuiIwGgC2AgAXAAcKlCIwGgC2AgAWAAQKcSN7bQBaAQAAAA==.Charginatyou:BAAANQADCggIDwABNQAECggIJgAcAHEQAA==.Charla:BAAANQADCgUIBwABNQAECggIKQASAFgVAA==.Chelsea:BAAANQADCggICgAAAA==.Chise:BAABNQAECn8dAAIdAAgKihtHBACLAgAdAAgKihtHBACLAgAAAA==.Chiza:BAAANQADCgUIBwAAAA==.Chob:BAAANQADCgcICwAAAA==.',
Cl='Clarry:BAAANQAECgEIAQAAAA==.Clyde:BAAANQAECgEIAQAAAA==.Clydk:BAAANQAECgIIAwAAAA==.',
Co='Coachbeard:BAABNQAECn8iAAIeAAgK+Rh4RQBNAgAeAAgK+Rh4RQBNAgAAAA==.Colzaratha:BAAANQAECgcIEwAAAA==.Conrow:BAAANQADCgQIBAAAAA==.Coorsbanquet:BAABNQAECn8WAAIVAAYKjR9RIAAnAgAVAAYKjR9RIAAnAgAAAA==.Copernicus:BAAANQAECgYICwAAAA==.Corian:BAAANQADCgQIBAAAAA==.Corndog:BAABNQAECn8lAAMCAAkK5BkXqAAwAgACAAgK+xcXqAAwAgADAAIK3hy9LACTAAAAAA==.Corpsereth:BAAANQADCggICAAAAA==.Cozzworth:BAAANQADCgEIAQAAAA==.',
Cr='Cronchybacon:BAAANQADCgcIBwAAAA==.',
Cu='Cudguzzler:BAAANQAECgIIAgAAAA==.Cursegoesmoo:BAAANQAECgYIEwAAAA==.Cursehoots:BAABNQAECn8rAAIfAAkKeyIuDgBXAwAfAAkKeyIuDgBXAwAAAA==.',
Cy='Cygna:BAAANQADCgQIBAAAAA==.Cyntheria:BAABNQAECn8lAAIPAAgKjRyAYwBsAgAPAAgKjRyAYwBsAgAAAA==.',
Da='Daddybeàr:BAABNQAECn8nAAULAAkKVR9xDAACAwALAAkKVR9xDAACAwAgAAQKnxYHJQDiAAATAAIKOgqjSACCAAAfAAIKdhFMngBeAAAAAA==.Daendron:BAAANQAECgYIBgAAAA==.Daerian:BAAANQADCggIDwAAAA==.Dangereuse:BAAANQAECgcIBwAAAA==.Darksaxon:BAABNQAECn8ZAAIGAAcKihhHEwDuAQAGAAcKihhHEwDuAQAAAA==.Darorek:BAABNQAECn8WAAIMAAYKwwTqjADKAAAMAAYKwwTqjADKAAAAAA==.Darthpaw:BAAANQADCgYIBgAAAA==.Darthsidd:BAAANQAECgMIAgAAAA==.',
De='Deathnethal:BAAANQADCgYIBgAAAA==.Deathweaver:BAABNQAECn8mAAMaAAkKGiUgAgC9AwAaAAkKGiUgAgC9AwAbAAgK4yIYCQDjAgAAAA==.Debumanko:BAAANQADCggIDgAAAA==.Decima:BAAANQADCggIGwAAAA==.Deeneye:BAAANQADCgYIEAABNQAECgUIDAAHAAAAAA==.Delerai:BAAANQAECgQICQAAAA==.Dellgado:BAAANQAECgUICwAAAA==.Deme:BAAANQAECgUIBgAAAA==.Demonbains:BAAANQAECgEIAQAAAA==.Demonica:BAAANQAECgYIDQAAAA==.Demonscythe:BAAANQADCgcIEQAAAA==.Dendrax:BAABNQAECn8fAAMRAAgKYgduTACZAAAQAAcKOAYIwgBCAQARAAMK/AluTACZAAAAAA==.Dented:BAAANQABCgQIBAAAAA==.Deviance:BAAANQAECgIIAwAAAA==.Dezwar:BAAANQADCgEIAQABNQAFFAYIGAADAJ4hAA==.',
Di='Dissonance:BAAANQADCgUIBQAAAA==.',
Dj='Djanga:BAAANQADCgYIBgABNQAECgcIHQAeAKojAA==.Djdazzle:BAAANQAECgEIAgAAAA==.',
Do='Dogbearcat:BAAANQADCgQIBAABNQAFFAMIAwAHAAAAAA==.Dorito:BAABNQAECn8VAAMMAAkKHx37MgBAAgAMAAYKpiP7MgBAAgAWAAUK9hb7awBfAQAAAA==.',
Dr='Draekon:BAAANQAECgIIAgAAAA==.Dragooned:BAACNQAFFH8KAAIDAAUKPRUUAQCCAQADAAUKPRUUAQCCAQA1AAQKfyIAAgMACQqOJUMCAEsDAAMACQqOJUMCAEsDAAAA.Drahhrak:BAAANQADCgQIBwAAAA==.Drango:BAAANQAECgYICwAAAA==.Draugdae:BAAANQAECgUIEgAAAA==.Draxtor:BAAANQADCgQIBAAAAA==.Drinksomuch:BAABNQAECn8cAAIUAAcKChLtFACRAQAUAAcKChLtFACRAQAAAA==.Drizzlin:BAAANQADCgYIBgAAAA==.Drleche:BAAANQADCgEIAQAAAA==.Drob:BAEANQAECgYIEAAAAA==.Drocket:BAEBNQAECn8YAAIMAAcKqRPkUACvAQAMAAcKqRPkUACvAQAAAA==.Drome:BAAANQAECgEIAQABNQAECgUIEQAHAAAAAA==.Drukhi:BAABNQAECn8hAAISAAgKGyLPIwAGAwASAAgKGyLPIwAGAwAAAA==.',
Du='Dudetotems:BAAANQAECggIEwAAAA==.Dungrough:BAAANQAECgUICgAAAA==.Durtkal:BAABNQAECn8nAAMQAAgKOBPIgwDYAQAQAAcKNxDIgwDYAQARAAIK9Rs6SgCfAAAAAA==.',
Dy='Dyonn:BAAANQAECgUIEgAAAA==.',
Ef='Efarel:BAABNQAECn8fAAIBAAgKaBLbfwAYAgABAAgKaBLbfwAYAgAAAA==.Efdis:BAAANQADCgIIAgAAAA==.',
Ei='Eienarinna:BAAANQADCgYIBgAAAA==.Eilana:BAABNQAECn8fAAMMAAkKnhaaKAB5AgAMAAkKnhaaKAB5AgAWAAcKfAauhQAFAQABNQAFFAMIAwAHAAAAAA==.Eilària:BAAANQADCgYIEQAAAA==.',
El='Ellipisis:BAAANQABCgUIBQABNQAECgkJHAAPABkVAA==.Elsa:BAABNQAECn8iAAMDAAgKVAjVIgDSAAACAAgKjQY9/wCMAQADAAUKagnVIgDSAAAAAA==.',
Em='Emma:BAAANQADCggJDgAAAA==.',
En='Eneco:BAABNQAECn8mAAIOAAkK8yHxDABaAwAOAAkK8yHxDABaAwAAAA==.Enserath:BAAANQADCgYICwAAAA==.',
Eu='Eurythmics:BAABNQAECn8cAAISAAcKThCtmQDQAQASAAcKThCtmQDQAQAAAA==.',
Ev='Evonahh:BAAANQADCgUICAAAAA==.',
Ex='Exelion:BAABNQAECn8iAAIOAAgKQh6xKADEAgAOAAgKQh6xKADEAgAAAA==.Explogan:BAAANQAECgEIAQAAAA==.',
Ez='Ezanah:BAAANQADCgIIBAAAAA==.Ezrack:BAAANQADCgYICAABNQAECgIIAgAHAAAAAA==.',
Fa='Faaith:BAAANQADCgcIFwAAAA==.Fahooquazaad:BAAANQAECgEIAQAAAA==.Faithráven:BAAANQADCgMIAwAAAA==.Fancie:BAAANQADCggIEAABNQAECggIHgAXAG4JAA==.Fancy:BAABNQAECn8YAAIVAAkKXhZCHwAyAgAVAAkKXhZCHwAyAgAAAA==.',
Fe='Feetlesmcdee:BAAANQAECgUIEAAAAA==.Felfáádaern:BAAANQAECgEIAQAAAA==.Felporch:BAAANQAECgIIAwAAAA==.',
Fi='Fitzy:BAABNQAECn8WAAMNAAYKChpGLAB3AQANAAUKdx1GLAB3AQAeAAIKhQM3DwFSAAAAAA==.',
Fl='Flowermound:BAAANQAECgMIBwAAAA==.',
Fo='Fourqto:BAABNQAECn8cAAMRAAcKCQlkIABsAQARAAcK6ghkIABsAQAQAAYK8gQW3gAIAQAAAA==.Fox:BAACNQAFFH8RAAIOAAUKqyBwCQDtAQAOAAUKqyBwCQDtAQA1AAQKfyMAAg4ACQryIgMaAAoDAA4ACQryIgMaAAoDAAAA.',
Fr='Freya:BAAANQADCgUIBQAAAA==.',
Fu='Fujikujaku:BAABNQAECn8VAAMLAAcK7QuYNwBbAQALAAcK7QuYNwBbAQAfAAYKygbMbwAGAQAAAA==.Fulmetal:BAABNQAECn8cAAIPAAgKUAy7uwCfAQAPAAgKUAy7uwCfAQAAAA==.Funji:BAABNQAECn8dAAIYAAcKmR87QABxAgAYAAcKmR87QABxAgAAAA==.Funkalicious:BAABNQAECn8ZAAMhAAgKDQqEkABbAQAhAAgKDQqEkABbAQAYAAMKeAgm/ACSAAAAAA==.',
['Fé']='Félo:BAABNQAECn8fAAMQAAkKuR9ZGAAlAwAQAAkKaR1ZGAAlAwARAAQKsiVYFgC5AQAAAA==.',
Ga='Gaila:BAABNQAECn8sAAMYAAgKmCCwIQAAAwAYAAgKmCCwIQAAAwAcAAYKEh/+FwDjAQAAAA==.Garathor:BAAANQABCgQIBQAAAA==.Garrosh:BAAANQABCgMIAwAAAA==.Garthoneeye:BAAANQADCggIHgAAAA==.Gazreyna:BAAANQAECgUICQAAAA==.',
Ge='Genryusai:BAAANQAECgQIBQAAAA==.Genós:BAABNQAECn8iAAQBAAgKYBl5cwA3AgABAAgKYBl5cwA3AgAGAAMK0hXELgC6AAAiAAEKywwoNAAxAAAAAA==.Gerardo:BAAANQAECgUIEgAAAA==.',
Gi='Gigarawr:BAAANQAECgMIBgABNQAECgYJCQAHAAAAAA==.Ginnee:BAABNQAECn8XAAQjAAcKQRMDCwC+AQAjAAYKxhEDCwC+AQAQAAUKbA+B3gAHAQARAAIKiA4vVwB4AAAAAA==.',
Gl='Glakattack:BAABNQAECn8hAAICAAgKAAmS8ACmAQACAAgKAAmS8ACmAQAAAA==.Glein:BAABNQAECn8lAAQPAAkKbyREEACHAwAPAAkK8yNEEACHAwAeAAUKOwkmwQD1AAANAAIKryOCSADHAAAAAA==.Gleivoker:BAAANQAECgUICAABNQAECgkJJQAPAG8kAA==.',
Gn='Gnomeisbis:BAAANQADCggICAAAAA==.',
Go='Gongfu:BAAANQADCgEIAQAAAA==.Gooeyquiver:BAAANQADCgMIBQAAAA==.',
Gr='Graestoke:BAAANQAECgYICwABNQAFFAIIBQAkAJ8WAA==.Granthar:BAAANQADCgUIBQAAAA==.Greasermorty:BAAANQADCgMIAwAAAA==.Grimbrew:BAAANQAECgEIAQAAAA==.Grimixtalis:BAAANQADCggIDwAAAA==.Growls:BAABNQAECn8gAAQTAAgKjiCrCQDWAgATAAgK1R+rCQDWAgAgAAUKKhkXGQBnAQALAAQKWBRlRQD+AAAAAA==.Grumpyazpapa:BAAANQAECgIIAgABNQAECggILQAPADQHAA==.Grundlegnome:BAAANQAECgcIDQABNQAECgkJNwAaAHMiAA==.',
Gu='Gurri:BAAANQAECgUICwAAAA==.',
['Gõ']='Gõldenchild:BAAANQAECgQIBgAAAA==.',
Ha='Habenero:BAAANQAECgUIBwAAAA==.Hairypitts:BAAANQAECgYIDgAAAA==.Hajari:BAAANQADCgUIBQAAAA==.Happychaos:BAAANQAECgQIBAAAAA==.Haraniantha:BAABNQAECn8WAAIUAAcKbSBpDQAiAgAUAAcKbSBpDQAiAgAAAA==.Hatean:BAAANQAECgIIAgAAAA==.Hathor:BAABNQAECn8YAAICAAgKTAuL3QDKAQACAAgKTAuL3QDKAQAAAA==.Hazzbek:BAAANQADCgcIDwAAAA==.',
He='Heiboss:BAAANQAECgQICgABNQAECggIIAAMAO8kAA==.Heibub:BAAANQAECgMIBQABNQAECggIIAAMAO8kAA==.Heiranir:BAABNQAECn8XAAIgAAgK2BiiCgCKAgAgAAgK2BiiCgCKAgABNQAECggIIAAMAO8kAA==.Heiretic:BAAANQAECgUICgABNQAECggIIAAMAO8kAA==.Heithyr:BAAANQADCgMIBAABNQAECggIIAAMAO8kAA==.Helos:BAAANQADCgcICgAAAA==.Hemit:BAAANQAECgQIBgABNQAFFAIIBQAkAJ8WAA==.',
Hi='Hikikomori:BAAANQAECgEIAQABNQAECggIQwAMAFwlAA==.Hildegarde:BAABNQAECn8eAAIPAAgK4BYAfQAsAgAPAAgK4BYAfQAsAgAAAA==.Himura:BAAANQAECggICAAAAA==.Hinomiko:BAAANQAECgUIDAABNQAECgUIEAAHAAAAAA==.Hiyori:BAAANQADCgcIBwABNQAECgQICQAHAAAAAA==.',
Ho='Holycowch:BAAANQADCgEIAQAAAA==.Hootiedixon:BAAANQADCgIIAgAAAA==.Hotdog:BAAANQAECgUIBQABNQAECgkJJQACAOQZAA==.',
Hu='Huran:BAABNQAECn8gAAMMAAgK7yTMEAAlAwAMAAgK7yTMEAAlAwAWAAEKAADtzwBJAAAAAA==.',
Hx='Hx:BAAANQADCgMIAwABNQAECgYIEAAHAAAAAA==.',
Ia='Iatemydad:BAAANQAECgYIEgAAAA==.',
Ic='Icéehawt:BAEANQAECgUICwABNQADCgUIBQAHAAAAAA==.',
Ig='Ignignokt:BAEBNQAECn8fAAMSAAkKDiOzJAACAwASAAgKrCWzJAACAwAZAAQKFBcHSgAMAQAAAA==.',
Im='Imagine:BAABNQAECn8eAAIhAAkK/CItCgBuAwAhAAkK/CItCgBuAwAAAA==.',
In='Inarush:BAABNQAECn8oAAIlAAgKzgy5EQCQAQAlAAgKzgy5EQCQAQAAAA==.',
Ir='Ironshield:BAAANQAECgQIBAABNQAECgkJJQAYAKAYAA==.',
Iw='Iwishiknew:BAAANQAECgcIEAAAAA==.',
Iz='Iztras:BAAANQADCgEIAQAAAA==.',
Ja='Jabbtrak:BAAANQAECgYIEgAAAA==.Jabttrak:BAABNQAECn8aAAIOAAgKohpsMACkAgAOAAgKohpsMACkAgAAAA==.Jacklowry:BAABNQAECn8bAAImAAkKPQNSEQD6AAAmAAkKPQNSEQD6AAAAAA==.Jakiepoobear:BAABNQAECn8oAAIZAAkKuxYAGgCDAgAZAAkKuxYAGgCDAgAAAA==.Jalador:BAAANQADCggICAAAAA==.Jambie:BAABNQAECn8VAAMQAAcKOQxXpQCEAQAQAAcKOQxXpQCEAQARAAEKGgZlgAArAAAAAA==.',
Je='Jedery:BAABNQAECn8ZAAINAAcKVw/0LQBqAQANAAcKVw/0LQBqAQAAAA==.',
Ji='Jivepepper:BAAANQADCggIDwAAAA==.',
Jo='Jolynn:BAABNQAECn8YAAMnAAgKdgzfBgAaAgAnAAgKdgzfBgAaAgASAAcKmQII6AAsAQAAAA==.Joroldess:BAABNQAECn8fAAINAAgKmh7mDgCsAgANAAgKmh7mDgCsAgAAAA==.Joyo:BAAANQADCgUIDAAAAA==.',
Ju='Juzam:BAAANQADCgYIEwAAAA==.',
Ka='Kahghär:BAAANQAECgYIDAABNQAFFAUIEAAmAO4bAA==.Kahlly:BAABNQAECn8XAAISAAYK2Bd3nADKAQASAAYK2Bd3nADKAQAAAA==.Kahndumb:BAAANQAECgYIDAAAAA==.Kaida:BAAANQAECgMIBwAAAA==.Kaio:BAAANQAECgcIDwAAAA==.Kalahan:BAAANQAECgIIAwAAAA==.Kaotut:BAAANQAECgEIAQAAAA==.Kardrion:BAAANQAECgEJAQAAAA==.Karigyn:BAABNQAECn8cAAIaAAcK9SFlFwC9AgAaAAcK9SFlFwC9AgAAAA==.Kaskaa:BAAANQADCggIDAAAAA==.Katelina:BAAANQAECgQICQAAAA==.Katren:BAAANQADCgMIAwAAAA==.Katrienne:BAABNQAECn8dAAINAAcK0ginNQA1AQANAAcK0ginNQA1AQAAAA==.Katrya:BAAANQABCgQIBAABNQAECgcIHQANANIIAA==.Kaylid:BAABNQAECn8ZAAImAAgKRg8xCgDZAQAmAAgKRg8xCgDZAQAAAA==.Kazzoth:BAABNQAECn8hAAISAAgKLguRjQDrAQASAAgKLguRjQDrAQAAAA==.',
Ke='Keilen:BAAANQADCgYICQAAAA==.Keiyo:BAAANQAECgMIAwAAAA==.Kelzie:BAAANQADCgMIAwAAAA==.Ketsuana:BAAANQADCgcIDQABNQAECgUIFwACABwCAA==.Ketsukusai:BAAANQAECgEIAQAAAA==.',
Kh='Khally:BAAANQADCggIDgAAAA==.',
Ki='Kilen:BAAANQABCgUICQAAAA==.Kilimanjaro:BAAANQADCgcIDwAAAA==.Killjôy:BAAANQADCgIIAgAAAA==.Kimjongboom:BAABNQAECn8hAAIfAAkKKiT7DABhAwAfAAkKKiT7DABhAwAAAA==.',
Kl='Klax:BAAANQAECgYIBgAAAA==.Klondor:BAAANQAECgUIBQAAAA==.Klz:BAAANQAECgYIBwAAAA==.Klzx:BAAANQAECgUIDAAAAA==.',
Ko='Komo:BAACNQAFFH8IAAIQAAYKZBwSCADpAQAQAAYKZBwSCADpAQA1AAQKfyEAAxAACQrLH3gcABEDABAACQrLH3gcABEDABEAAQoAAKZhAGAAAAAA.Konokusotare:BAAANQAECgQICQAAAA==.Korbi:BAAANQADCgYICgABNQAECggIIgAhAC4MAA==.Korbs:BAABNQAECn8iAAMbAAgKthI8GQANAgAbAAgKqBE8GQANAgAaAAUK9A1qYQAnAQAAAA==.Kortek:BAAANQADCgUIBQAAAA==.Korvold:BAABNQAECn8nAAIBAAgKbhv5YABnAgABAAgKbhv5YABnAgAAAA==.',
Kr='Krak:BAAANQABCgYICAAAAA==.Kralkor:BAAANQADCgQIAwAAAA==.Kreckon:BAAANQAECgQICgAAAA==.Kronn:BAAANQAECgUICgABNQAECggIHQAOAFsZAA==.',
Ks='Kschnell:BAAANQADCgQIBQABNQAFFAQIBQACAK8VAA==.',
Ku='Kukulkan:BAAANQAECgQIDQAAAA==.Kuulan:BAABNQAECn8iAAIPAAgKrxbHgwAcAgAPAAgKrxbHgwAcAgAAAA==.',
Ky='Kythra:BAAANQAECgEIAQAAAA==.',
La='Lanstin:BAAANQADCgUIBgAAAA==.',
Le='Leafpool:BAAANQADCgYIBgAAAA==.Leancuisine:BAAANQAECgUICAAAAA==.Leetlebug:BAAANQAECgEIAQAAAA==.Leofull:BAAANQAECgUICQAAAA==.Lettÿ:BAAANQAECgcIEgAAAA==.Lexapro:BAAANQAECgEJAQAAAA==.',
Li='Lickemraw:BAAANQADCgQIBAAAAA==.Lightzwrath:BAAANQAECgYIDAABNQAECggIIgATAFwSAA==.Lilithphage:BAAANQAECgQIBgAAAA==.Lilstorm:BAAANQADCgMIAwAAAA==.',
Lo='Lockbealady:BAAANQADCgYIBgAAAA==.Lockdiso:BAAANQAECgcIBAAAAA==.Lorebeard:BAAANQAECgQIBQAAAA==.Loreix:BAAANQAECgUIEwAAAA==.Loreous:BAAANQADCgUIBQABNQAECggIHQAOAFsZAA==.Lowping:BAAANQAECgEIAQAAAA==.',
Lr='Lrock:BAAANQABCgYIBwAAAA==.',
Lu='Luther:BAAANQADCgQIBQABNQAECgcICAAHAAAAAA==.Luvinz:BAAANQAECgUIEgAAAA==.Luxuria:BAAANQAECgQIBwAAAA==.',
Ly='Lycanbear:BAAANQAECggIBgAAAA==.Lycanhunter:BAAANQAECgQICAAAAA==.Lycanknight:BAAANQADCgEIAQAAAA==.Lycansham:BAAANQAECgEIAQAAAA==.Lyse:BAEANQAECgQICAAAAA==.',
Ma='Maarc:BAAANQAECgUIDgAAAA==.Machantu:BAAANQADCggIDgAAAA==.Madfurion:BAAANQAECgYIEwAAAA==.Magebot:BAABNQAECn8kAAIDAAcKPw0hEgCBAQADAAcKPw0hEgCBAQAAAA==.Maggotbag:BAAANQADCgYICgAAAA==.Magicmandan:BAAANQADCgUIBQAAAA==.Magikstik:BAAANQAECgUICQAAAA==.Mahgrim:BAAANQADCgMIAwAAAA==.Majestic:BAACNQAFFH8FAAICAAQKrxUrKgAzAQACAAQKrxUrKgAzAQA1AAQKfzUAAgIACQq0I7kTAIQDAAIACQq0I7kTAIQDAAAA.Maliná:BAAANQADCgEIAQABNQAECgQIBAAHAAAAAA==.Malvenue:BAAANQADCgMIBAAAAA==.Marchesa:BAAANQADCgcIBwAAAA==.Markdashaman:BAAANQADCgIIAgAAAA==.Mauwy:BAABNQAECn8aAAMYAAgKshbnVwAYAgAYAAgKshbnVwAYAgAhAAMKLwaA7wCGAAAAAA==.',
Mc='Mcbullseye:BAAANQAECgUIBQAAAA==.',
Me='Megarah:BAAANQADCgYIFgAAAA==.Mepkaelpto:BAAANQADCgYIBgAAAA==.Meretrix:BAABNQAECn8XAAIPAAcK6Ai+4QBRAQAPAAcK6Ai+4QBRAQAAAA==.Mersadie:BAABNQAECn8dAAIeAAcKqiMoJQDUAgAeAAcKqiMoJQDUAgAAAA==.Metanya:BAAANQAECgYIDAAAAA==.Mew:BAAANQAECgUICQAAAA==.',
Mi='Miateh:BAAANQAECgQIBgAAAA==.Mimicme:BAABNQAECn8nAAISAAkKciKJDAB5AwASAAkKciKJDAB5AwAAAA==.Mirajanê:BAAANQAECgMIBAAAAA==.Mitchell:BAAANQAECgUICgAAAA==.Miwah:BAABNQAECn8XAAMCAAUKHAJAhAG2AAACAAUKHAJAhAG2AAADAAEKAACuTgAoAAAAAA==.Mizzheals:BAAANQAECgUIEQAAAA==.',
Mo='Mogarr:BAAANQADCgcICwAAAA==.Monkhei:BAAANQADCgEIAQABNQAECggIIAAMAO8kAA==.Moocifer:BAABNQAECn8bAAIPAAgKdxDKrgC8AQAPAAgKdxDKrgC8AQAAAA==.Mooglewing:BAAANQAECgQICwAAAA==.Moomoobrncow:BAAANQAECgYIDwAAAA==.Mooriahdairy:BAAANQAECgQIBAAAAA==.Moorrigån:BAAANQADCgIIAgAAAA==.Mordicanta:BAABNQAECn8dAAIMAAcKrRcZTgC6AQAMAAcKrRcZTgC6AQAAAA==.Morgannon:BAAANQADCgUIBQAAAA==.Morphies:BAAANQADCgEIAQAAAA==.',
Mu='Muerr:BAABNQAECn8cAAISAAgKcSJXJgD9AgASAAgKcSJXJgD9AgAAAA==.Muerrizond:BAAANQAECgIIAgABNQAECggIHAASAHEiAA==.Muggel:BAAANQADCggIFQAAAA==.Mumraa:BAAANQAECgQIBgAAAA==.Mushroohead:BAAANQAECgQIEwAAAA==.',
My='Mysterbyrnes:BAAANQAECgUICQAAAA==.Myykiel:BAAANQAECgYIDwAAAA==.',
Na='Naia:BAAANQAECgIIAgABNQAECgkJJgAUAOciAA==.Naina:BAAANQAECgUIEgAAAA==.Najaja:BAAANQAECgQICwAAAA==.Namii:BAAANQAECgYICwAAAA==.Narsum:BAAANQADCgYIBgAAAA==.Natacha:BAAANQAECgQICQAAAA==.Navadurga:BAABNQAECn8ZAAILAAkKHQs+NwBeAQALAAkKHQs+NwBeAQAAAA==.',
Ne='Necro:BAABNQAECn9DAAIMAAgKXCVtCgBgAwAMAAgKXCVtCgBgAwAAAA==.Nedrali:BAAANQAECgUIBQABNQAECggIGgAYALIWAA==.Nedrina:BAAANQADCgcIBwABNQAECggIGgAYALIWAA==.Netrath:BAAANQAECgIIAgAAAA==.',
Ni='Nidom:BAAANQAECgIIAgAAAA==.Nighammer:BAAANQAECgcIDQAAAA==.Nimeesha:BAAANQADCgMJAwAAAA==.Ninmah:BAAANQADCggIHgAAAA==.Nirø:BAAANQAECgIIAwAAAA==.',
No='Nooki:BAABNQAECn8dAAMOAAgKWxkJSgBEAgAOAAgKWxkJSgBEAgAkAAIKHxh3XACOAAAAAA==.Notgretuh:BAAANQAECgcIDgAAAA==.',
Ny='Nyrikah:BAAANQAECgEIAQAAAA==.Nyxa:BAAANQADCgYIBgAAAA==.',
Ob='Obidiah:BAAANQAECgYIEQAAAA==.',
Od='Oddearth:BAAANQAECgEIAQAAAA==.',
Om='Omegablivet:BAAANQADCgMJAwAAAA==.',
Op='Ophirri:BAAANQADCgYIBgAAAA==.',
Or='Orah:BAAANQADCgYIEAAAAA==.',
Pa='Palagem:BAAANQAECgUIEgAAAA==.Palidingo:BAAANQADCgEIAQAAAA==.Palinyes:BAABNQAECn8cAAIPAAgKyR0yVgCQAgAPAAgKyR0yVgCQAgAAAA==.Pandabutz:BAAANQAECgYIEwAAAA==.Pandahands:BAAANQADCgIIAgAAAA==.Panduh:BAAANQAECgUIDQAAAA==.Pandussy:BAAANQAECgcIBwAAAA==.Papabill:BAABNQAECn8tAAIPAAgKNAfE1gBnAQAPAAgKNAfE1gBnAQAAAA==.Papaharny:BAABNQAECn8cAAMYAAcKeAINzQD0AAAYAAcKeAINzQD0AAAcAAEKdgEwOwAaAAABNQAECggILQAPADQHAA==.Paragorn:BAAANQAECgUIEAAAAA==.Pattee:BAAANQAECgYIEgAAAA==.Pawp:BAAANQABCgIIAgAAAA==.',
Pe='Pech:BAAANQAECgEIAgABNQAECgYJCQAHAAAAAA==.Pechay:BAAANQADCgIJBAABNQAECgYJCQAHAAAAAA==.Peenidin:BAABNQAECn8hAAIeAAgKEyCcIQDlAgAeAAgKEyCcIQDlAgAAAA==.Peepo:BAABNQAECn83AAIaAAkKcyJPBwBcAwAaAAkKcyJPBwBcAwAAAA==.Pemerd:BAABNQAECn8cAAIfAAcKnR1jLQBuAgAfAAcKnR1jLQBuAgAAAA==.',
Ph='Phoze:BAABNQAECn8XAAMeAAYKnRCNqwAmAQAeAAUKZRCNqwAmAQANAAUKUQgOSwC6AAAAAA==.Phozzack:BAAANQAECgEIAQAAAA==.Phyai:BAAANQAECgYIEwAAAA==.',
Pl='Pliny:BAABNQAECn8lAAIYAAkKoBiTRQBcAgAYAAkKoBiTRQBcAgAAAA==.',
Pn='Pnutt:BAAANQAECgMIBAAAAA==.',
Po='Pocahauntas:BAAANQAECgIIAgABNQAFFAYIFQAEABMaAA==.Porphyriia:BAAANQADCggICAAAAA==.',
Pr='Priestglein:BAAANQADCgUIBQABNQAECgkJJQAPAG8kAA==.Promethyus:BAAANQADCgcIEwAAAA==.Promidan:BAAANQAECgQIBgABNQADCggIDAAHAAAAAA==.Prymus:BAABNQAECn8qAAINAAgKSyGVDADPAgANAAgKSyGVDADPAgAAAA==.Pryxi:BAABNQAECn8fAAIDAAgKhRAmDQDdAQADAAgKhRAmDQDdAQAAAA==.',
Pu='Punkalicious:BAAANQAECgYIDQAAAA==.',
Py='Pyrogar:BAAANQADCgYIBgAAAA==.Pythius:BAAANQAECgQIBgAAAA==.',
['Pó']='Pótatò:BAAANQAECgIIAgAAAA==.',
Qu='Quetip:BAAANQADCgMIAwAAAA==.Quiksylver:BAABNQAECn8pAAQeAAgKPBlqQABhAgAeAAgKPBlqQABhAgAPAAMKNBDMSwGfAAANAAMKpgIIXwBbAAAAAA==.',
Ra='Rakael:BAAANQADCgcIBwAAAA==.Randumb:BAAANQAECgEIAQAAAA==.Ratshot:BAABNQAECn88AAISAAkKOSH6CQCNAwASAAkKOSH6CQCNAwABNQAECgkJRwAEAHMkAA==.Rawty:BAAANQADCgUICQAAAA==.Rayse:BAAANQADCgYIBgAAAA==.',
Re='Red:BAABNQAECn8eAAIXAAgKZBu1KwA7AgAXAAgKZBu1KwA7AgAAAA==.Relgul:BAAANQADCgYICwAAAA==.Rellster:BAABNQAECn8jAAMBAAkKXBLYeQAmAgABAAkKXBLYeQAmAgAiAAEKFAtRNQAuAAAAAA==.Renix:BAAANQADCgUIBQAAAA==.Rennyo:BAABNQAECn8iAAMVAAgKsyH8DQD8AgAVAAgKgSH8DQD8AgAUAAUKfxtAFACcAQAAAA==.Resonance:BAAANQADCggIFwAAAA==.Rexion:BAAANQAECgUIEQAAAA==.Rezator:BAAANQAECgEIAQAAAA==.',
Ri='Rigg:BAAANQAECgQIBAAAAA==.Riggsy:BAAANQAECgUIEwABNQAECgQIBAAHAAAAAA==.Riggz:BAAANQADCgYIBgABNQAECgQIBAAHAAAAAA==.Riggzbuffs:BAAANQADCgYICwABNQAECgQIBAAHAAAAAA==.Rivenp:BAAANQADCggIGgAAAA==.',
Ro='Rocknroll:BAABNQAECn8VAAISAAcKKhT2jwDlAQASAAcKKhT2jwDlAQAAAA==.Rokbiter:BAAANQAECgIIBAAAAA==.Roll:BAAANQAFFAMIAwAAAA==.Rothound:BAAANQAECgQIBgAAAA==.Rozgrez:BAABNQAECn8cAAMQAAcK1BzUdwD3AQAQAAYKJh3UdwD3AQARAAMK3xpIMgD7AAAAAA==.',
Ru='Runefflck:BAABNQAECn8eAAMjAAcKBxuqBwAdAgAjAAcKBxuqBwAdAgAQAAEKSgb8RAEuAAAAAA==.Runenomore:BAAANQAECgMIAwAAAA==.Russbus:BAACNQAFFH8KAAIPAAUKYxJtCwCOAQAPAAUKYxJtCwCOAQA1AAQKfx8AAg8ACQoRGrxyAEUCAA8ACQoRGrxyAEUCAAAA.',
Ry='Rynari:BAAANQADCgcIEgABNQAECggIIwAWAEgNAA==.Rynmorelle:BAABNQAECn8jAAIWAAgKSA07VwCwAQAWAAgKSA07VwCwAQAAAA==.',
['Ré']='Réven:BAABNQAECn8iAAMFAAgKLCCaFwDbAgAFAAgKLCCaFwDbAgAEAAUKtxrgPwBHAQAAAA==.',
['Rí']='Rínoah:BAAANQADCggIFgAAAA==.',
['Rô']='Rôckbôttôm:BAAANQAECgcICgAAAA==.',
Sa='Sakamoto:BAAANQADCgYIBgAAAA==.Sakura:BAABNQAECn8VAAIVAAgKBxmQIwAGAgAVAAgKBxmQIwAGAgAAAA==.Sane:BAABNQAECn8YAAQXAAcKbBg2PwDHAQAXAAcKKRY2PwDHAQAMAAUKlxJvegALAQAWAAQKZxTijADtAAAAAA==.Saoiirse:BAAANQAECgMIBAAAAA==.',
Sc='Schadow:BAAANQADCgYIBgAAAA==.',
Se='Searshaa:BAAANQADCgcIBwAAAA==.Seershaa:BAAANQADCgYIBgAAAA==.Seriux:BAAANQADCgUIBQAAAA==.Sevencharlie:BAAANQAECgUIDQAAAA==.',
Sh='Shadowfate:BAABNQAECn8hAAIOAAgKTxIRZQDsAQAOAAgKTxIRZQDsAQAAAA==.Shadê:BAAANQADCgYIBgAAAA==.Shaftted:BAAANQADCggICgABNQAECgEIAQAHAAAAAA==.Shamanyou:BAAANQADCgEIAQAAAA==.Shamiqua:BAABNQAECn8ZAAIhAAcKFBMZdQCoAQAhAAcKFBMZdQCoAQAAAA==.Shamutty:BAAANQAECgQIBAABNQAFFAIIBQAkAJ8WAA==.Shentao:BAABNQAECn8gAAIVAAgKBgawOgA5AQAVAAgKBgawOgA5AQAAAA==.Shinjô:BAAANQAECgcIDgAAAA==.Shirikao:BAAANQAECgEIAQAAAA==.Shiroishi:BAAANQAECgUIEAAAAA==.Shivaray:BAAANQAECgQJBAAAAA==.Shocklesner:BAABNQAECn8WAAIYAAgKCxYkSQBOAgAYAAgKCxYkSQBOAgAAAA==.Shomade:BAAANQADCgQIBwAAAA==.Shouganai:BAAANQAECgQICwAAAA==.Shupaz:BAAANQAECgYIBgAAAA==.Shyanne:BAAANQAECgEIAQAAAA==.',
Si='Sifu:BAAANQAECgYIEQAAAA==.Silentstabs:BAAANQADCgQIBAAAAA==.Silverlight:BAAANQAECgUICAAAAA==.Simira:BAAANQAECggICAAAAA==.Simp:BAAANQADCgQIBAAAAA==.Sinaar:BAAANQADCgQIBAAAAA==.Sindena:BAAANQAECgQIBAAAAA==.',
Sk='Skyemage:BAAANQADCggIFAAAAA==.',
Sl='Sloked:BAAANQAECgcIDgAAAA==.Slokep:BAAANQADCgQIBAAAAA==.Slokes:BAAANQADCgIIAgAAAA==.Slotz:BAABNQAECn8dAAIeAAcKBRHhegClAQAeAAcKBRHhegClAQAAAA==.',
Sm='Smitepanda:BAAANQADCgcICAAAAA==.',
Sn='Sneeze:BAAANQADCgcIFQAAAA==.Snekashifty:BAAANQAECgUICAAAAA==.Snowsham:BAAANQADCgUJBQAAAA==.',
So='Sonarr:BAAANQAECgQICgAAAA==.Sosukeaizen:BAAANQAECgUIBQAAAA==.Sozzle:BAAANQADCgUIBQABNQAFFAQIBQACAK8VAA==.',
Sp='Spark:BAAANQAECgUICgAAAA==.Spicymeat:BAAANQAECgcJEgABNQAFFAQIBQACAK8VAA==.Sputty:BAACNQAFFH8FAAIkAAIKnxZAEQCpAAAkAAIKnxZAEQCpAAA1AAQKfx4AAiQACQqdHqsPAPgCACQACQqdHqsPAPgCAAAA.',
Sq='Squanto:BAAANQAECgYICQABNQAFFAQIBQACAK8VAA==.',
St='Stalken:BAAANQADCgYJCwAAAA==.Stealthdiso:BAAANQADCgUIBQAAAA==.Stesha:BAABNQAECn8eAAIPAAcKowhp4gBQAQAPAAcKowhp4gBQAQAAAA==.Stonedfrog:BAAANQAECgEIAQAAAA==.Stonefather:BAAANQADCgUIBQAAAA==.Stïtches:BAAANQAECgUIEQAAAA==.Stönk:BAAANQAECgUICQAAAA==.',
Su='Sugarlumps:BAAANQADCgEIAQAAAA==.Sungiver:BAAANQADCgUIBQAAAA==.Superdaman:BAAANQADCgEIAQAAAA==.',
Sw='Swaggles:BAABNQAECn8bAAInAAcKgiCfBACUAgAnAAcKgiCfBACUAgAAAA==.Swïtches:BAAANQAECgMIAwAAAA==.',
Sy='Sygon:BAABNQAECn8dAAIZAAcKjwpcPQBiAQAZAAcKjwpcPQBiAQAAAA==.Sylm:BAAANQAECgQIBAABNQAFFAYIBgAYAE0MAA==.Sylvannaa:BAAANQADCgcICAAAAA==.Symbr:BAAANQAECgcIDAAAAA==.Synglace:BAAANQAECgIIAwAAAA==.Syntherizena:BAAANQADCgcIBwAAAA==.',
Ta='Tacitus:BAABNQAECn8YAAIiAAcKthPADgC/AQAiAAcKthPADgC/AQAAAA==.Tairrad:BAAANQADCgUIBQABNQAECgUIDAAHAAAAAA==.Takara:BAAANQADCgUIBQAAAA==.Takeru:BAABNQAECn8aAAIOAAgKgQs8ewCjAQAOAAgKgQs8ewCjAQAAAA==.Talasmar:BAAANQADCgMIAwAAAA==.Taliessin:BAAANQAECgEIAQAAAA==.Talistian:BAAANQADCgIIAgAAAA==.Tarirn:BAAANQADCgYICwAAAA==.Tauntsinpvp:BAAANQAECgQIBwAAAA==.Taylia:BAAANQADCgYJBgABNQAECggIHQAdAIobAA==.Tazwomann:BAAANQAECgYIBwAAAA==.',
Te='Teaqo:BAAANQADCgUIBQAAAA==.Tebde:BAAANQAECgMIBQAAAA==.Tejina:BAAANQAECgEIAQAAAA==.Telinda:BAAANQABCgIIAgAAAA==.Tempestrasza:BAAANQADCgcICwAAAA==.Tendonitis:BAAANQABCgQIBAAAAA==.Teppe:BAABNQAECn8ZAAITAAgK1xTjFAASAgATAAgK1xTjFAASAgAAAA==.Terial:BAAANQAECgcIEQAAAA==.Terranovian:BAAANQAECgUICQAAAA==.',
Th='Thajeebus:BAABNQAECn8ZAAIfAAUKoRuxWgBkAQAfAAUKoRuxWgBkAQAAAA==.Thebigstein:BAAANQAECggIDgAAAA==.Thecapt:BAABNQAECn8lAAIiAAkKhxbkBwBvAgAiAAkKhxbkBwBvAgAAAA==.Theôdöræ:BAAANQAECgUICAAAAA==.Thunderkiss:BAAANQADCggICAAAAA==.',
Ti='Tiaoma:BAAANQADCggIDgAAAA==.Tiarlena:BAAANQABCgIIAgAAAA==.Tindle:BAAANQAECgEIAQAAAA==.Tinylock:BAAANQADCgUICQAAAA==.Tinymich:BAAANQADCgUIBwABNQAECggIIgAVALMhAA==.',
Tj='Tjhookèr:BAAANQAECgEIAQAAAA==.',
To='Toetoms:BAAANQAECgQIBwAAAA==.Toletheus:BAABNQAECn8cAAITAAgKGiUABQBOAwATAAgKGiUABQBOAwAAAA==.Tomin:BAAANQADCgIIAgAAAA==.Toreshii:BAAANQADCgUICQAAAA==.Totamic:BAAANQABCgIIAgAAAA==.Totemique:BAAANQAECgQIBAABNQAECgkJIAABAAwcAA==.Totumfknpole:BAAANQADCgMIAwAAAA==.',
Tr='Trashkantz:BAAANQAECgQICwABNQAFFAcIGQACAMghAA==.Treeperson:BAABNQAECn8YAAILAAcKbB0QHQBGAgALAAcKbB0QHQBGAgAAAA==.Trickyric:BAABNQAECn8cAAIPAAkKGRVlbwBNAgAPAAkKGRVlbwBNAgAAAA==.Trinak:BAAANQADCgQICAAAAA==.Trowel:BAAANQAECgQIBAABNQAFFAIIBQAkAJ8WAA==.',
Ts='Tsuyoimono:BAAANQAECgUIEAAAAA==.',
Tu='Turtleclap:BAAANQAECgQIBAAAAA==.',
Tw='Twistandgrip:BAABNQAECn8uAAIWAAkKjxLyRAACAgAWAAkKjxLyRAACAgAAAA==.Twylan:BAAANQADCgQIBAAAAA==.',
Ty='Tydroin:BAAANQADCgUIBQAAAA==.Tyinthor:BAAANQAECgMIBgAAAA==.Tytoalba:BAABNQAECn8eAAIeAAgK2iCpHgD1AgAeAAgK2iCpHgD1AgAAAA==.',
Un='Unholylean:BAAANQAECgQIBgAAAA==.',
Ur='Uratsukasama:BAAANQAECgUIDwAAAA==.Urza:BAABNQAECn8dAAMPAAgKvgVqCQEIAQAPAAgKvgVqCQEIAQAeAAcKgwGqAAFyAAAAAA==.',
Va='Vacaite:BAAANQAECgIIAgAAAA==.Vagiant:BAABNQAECn8hAAIgAAgK6RPDDwAPAgAgAAgK6RPDDwAPAgAAAA==.Vangers:BAAANQABCgMIAwAAAA==.Vangie:BAAANQAECgYICAAAAA==.Vangnaw:BAAANQAECgUIDAAAAA==.Vanya:BAAANQAECgYIEgAAAA==.Vasso:BAAANQADCgYIFgAAAA==.Vayln:BAAANQAECgcIDQAAAA==.',
Ve='Veildreya:BAAANQABCgQIBAAAAA==.Veinygamer:BAABNQAECn8jAAIBAAkK2x7OMwDvAgABAAkK2x7OMwDvAgAAAA==.Veldian:BAAANQAECgYIEAAAAA==.Velveen:BAABNQAECn8iAAMhAAgKLgyIhwB0AQAhAAgKLgyIhwB0AQAYAAcKzQhSnwBUAQAAAA==.Vexahalia:BAABNQAECn8mAAQSAAkKthxKPQCwAgASAAkKthxKPQCwAgAZAAUK6APLXgCnAAAnAAIKzwtBEAByAAAAAA==.',
Vi='Vicarious:BAAANQAECggIDwAAAA==.Viciouslump:BAAANQADCggICAAAAA==.Vilebloom:BAEANQAECgYIDwAAAA==.Vilewyrm:BAEANQADCgcIEgABNQAECgYIDwAHAAAAAA==.Violetblade:BAAANQADCgQIBAAAAA==.Viridius:BAAANQAECgEIAgAAAA==.',
Vo='Voidmulan:BAEANQADCgUIBQAAAA==.Voluga:BAAANQAECgEIAgAAAA==.',
Vr='Vraak:BAAANQAECgQIBAAAAA==.',
Vu='Vulkius:BAAANQADCgMIAwAAAA==.',
['Ví']='Víólént:BAABNQAECn8gAAMUAAgKhhcDDwD/AQAUAAgKhhcDDwD/AQAVAAYKEgwyQQAIAQAAAA==.',
Wa='Wagguslight:BAAANQAECgYICwAAAA==.',
We='Werstshot:BAAANQADCggIEwAAAA==.',
Wh='Whateverdude:BAABNQAECn8gAAISAAkKdg0YZwBEAgASAAkKdg0YZwBEAgAAAA==.',
Wi='Wicketlock:BAAANQAECgQIBAAAAA==.Wiickett:BAABNQAECn8gAAMIAAkKjwwkFgDnAQAIAAkKjwwkFgDnAQAKAAUK2AKaOwC5AAAAAA==.Wildesel:BAAANQAECgQIBgAAAA==.Willaá:BAABNQAECn8eAAMXAAgKbglPVQBRAQAXAAcK7AlPVQBRAQAMAAcK3gPShwDbAAAAAA==.Wilson:BAAANQAECgYIEwABNQAECgcICAAHAAAAAA==.Wizzpeaver:BAAANQADCgcIBwAAAA==.',
Wo='Wonderwizard:BAAANQADCgIIAgAAAA==.',
Wr='Wrathhoof:BAAANQAECgQIBQABNQAECggIIgATAFwSAA==.',
Xy='Xylias:BAAANQAECgYIEAAAAA==.',
['Xá']='Xánada:BAAANQADCggIDQABNQAECgEIAQAHAAAAAA==.',
Yo='Yorril:BAAANQADCgUIBQAAAA==.',
Yu='Yucca:BAABNQAECn8aAAMWAAcK0gz9bABbAQAWAAcKvAz9bABbAQAMAAUK4wehjADLAAAAAA==.Yuda:BAAANQAECgQIBgABNQAECgkJJgAOAPMhAA==.Yukiteru:BAAANQAECgEIAQAAAA==.Yurito:BAAANQADCgYIBgAAAA==.',
Za='Zabrina:BAAANQADCgcICQABNQAECgcIHgAPAKMIAA==.Zachie:BAAANQAECgcIEQAAAA==.Zakutin:BAAANQAECgIIAwAAAA==.Zappybains:BAABNQAECn8cAAIhAAcK/h7RPwBeAgAhAAcK/h7RPwBeAgAAAA==.Zarakii:BAAANQAECgMIBwAAAA==.',
Ze='Zekken:BAAANQADCgMIAwAAAA==.Zelaira:BAAANQADCgMIAwABNQAECggIIwAWAEgNAA==.',
Zi='Zigzagga:BAAANQADCgQIBAAAAA==.',
Zo='Zoinks:BAAANQADCgQIBQAAAA==.Zorandar:BAAANQAECgMIAwAAAA==.',
Zu='Zupaz:BAAANQADCgQIBAABNQAECgYIBgAHAAAAAA==.',
Zy='Zylluz:BAABNQAECn8iAAMWAAgKjh5XLQB7AgAWAAgK7R1XLQB7AgAXAAcK/BG8SwCDAQAAAA==.',
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
