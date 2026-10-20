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

local lookup = {'Mage-Arcane','Priest-Holy','Paladin-Retribution','Warlock-Demonology','Paladin-Holy','Hunter-BeastMastery','Hunter-Survival','Rogue-Assassination','Priest-Discipline','Warrior-Arms','Druid-Balance','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','Unknown-Unknown','Priest-Shadow','Shaman-Enhancement','Shaman-Elemental','Warrior-Protection','Warrior-Fury','DemonHunter-Vengeance','Hunter-Marksmanship','Paladin-Protection','Druid-Guardian','Druid-Feral','DeathKnight-Frost','DemonHunter-Devourer','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Rogue-Subtlety','Druid-Restoration','Mage-Frost','Mage-Fire','Evoker-Preservation','Monk-Brewmaster',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aarazi:BAABNQAECn8sAAIBAAgKVCA6GACvAQABAAgKVCA6GACvAQAAAA==.',
Ab='Abbinormal:BAAANQADCgYIHAAAAA==.Abolish:BAAANQAECgEIAgAAAA==.',
Ad='Adïrael:BAAANQABCggIEAAAAA==.',
Ae='Aeriss:BAAANQADCgYIDAAAAA==.Aethena:BAAANQADCgUIBQABNQAECgYIHAACALkNAA==.Aezili:BAAANQAECgEIAQAAAA==.',
Ag='Agamotto:BAAANQADCgMIAwAAAA==.Agerol:BAABNQAECn8jAAIDAAgK9B7fFQDPAQADAAgK9B7fFQDPAQAAAA==.',
Ah='Ahaego:BAABNQAECn8UAAIEAAYKkQ5pawCsAAAEAAYKkQ5pawCsAAAAAA==.Ahnari:BAAANQAECgIIAgAAAA==.',
Ak='Akkadien:BAABNQAECn8UAAMFAAgK8xw9NwCHAgAFAAgK8xw9NwCHAgADAAQKVgQoZgF8AAAAAA==.Akumunter:BAABNQAECn8qAAMGAAoK3xlHKwDsAgAGAAoK1hlHKwDsAgAHAAEKkg0qCQBMAAAAAA==.',
Al='Alacardias:BAABNQAECn8kAAIDAAgKiR29RADGAgADAAgKiR29RADGAgAAAA==.Alihuntress:BAAANQADCgQIBQAAAA==.Alleril:BAABNQAECn8aAAIIAAkKig/xAgAnAgAIAAkKig/xAgAnAgAAAA==.Allthesnacks:BAAANQAECggICgAAAA==.Aloe:BAAANQADCgYICQAAAA==.',
Am='Amarynth:BAAANQADCgQIBAAAAA==.Amäri:BAACNQAFFH8IAAICAAIK1yIFIwDIAAACAAIK1yIFIwDIAAA1AAQKfxoAAwIACAoiJGYhAOkCAAIACAoQJGYhAOkCAAkABArUGMEQAB0BAAAA.',
An='Anassand:BAAANQAECggIDgABNQAECgkJHQAKABkUAA==.Anatomic:BAAANQADCgIIAgABNQAECgYIHAACALkNAA==.Andimorph:BAABNQAECn8gAAILAAkKbRYvMQBYAgALAAkKbRYvMQBYAgAAAA==.Angeleria:BAAANQAECgEIAQAAAA==.',
Ap='Apazz:BAABNQAECn8oAAIGAAkKKRXIbQA3AgAGAAkKKRXIbQA3AgAAAA==.',
Aq='Aqualight:BAAANQAECggIDAABNQAECgoKLAAMAMkiAA==.Aquashade:BAAANQAECgUIBgABNQAECgoKLAAMAMkiAA==.Aquaterra:BAABNQAECn8sAAIMAAoKySKuDQBTAwAMAAoKySKuDQBTAwAAAA==.Aquina:BAAANQAECgcIEAABNQAECgoKLAAMAMkiAA==.',
Ar='Arakadia:BAABNQAECn84AAMNAAoK0BIzDQB3AQANAAoKihEzDQB3AQAOAAIKixTbpQCIAAAAAA==.Arcaina:BAAANQAECgMIAwAAAA==.Artoriaz:BAAANQADCgcJCwAAAA==.Aruteeru:BAABNQAECn8dAAMPAAgKuBpXGAD5AQAPAAcKbRlXGAD5AQAQAAgKdA8ZLwCeAQAAAA==.',
As='Aseanna:BAAANQAECgUIEQAAAA==.Astraen:BAAANQADCgQIBgAAAA==.',
At='Athira:BAAANQAECgEIAQAAAA==.',
Au='Augmentussy:BAAANQADCggICAABNQAECgoKKwAQAI0lAA==.Auxiliater:BAAANQADCgEIAQAAAA==.Auxiliator:BAAANQADCgYIBgAAAA==.Auxlox:BAAANQADCgcIBwAAAA==.Auxshadow:BAAANQABCgIIAgABNQADCgYIBgARAAAAAA==.',
Av='Avarous:BAABNQAECn8jAAMCAAgKeRfAEgDeAQACAAgKeRfAEgDeAQASAAEKAABvigAgAAAAAA==.Avataroffury:BAAANQAECgQIBAABNQAECgkJHQAKABkUAA==.',
Ax='Axará:BAAANQADCgQIBAAAAA==.Axel:BAAANQADCgUIBwAAAA==.',
Ay='Ayala:BAACNQAFFH8MAAIDAAMKQyAcEgAvAQADAAMKQyAcEgAvAQA1AAQKfx8AAgMACgpsJKoBACcDAAMACgpsJKoBACcDAAAA.',
Az='Azaireos:BAAANQADCgYIDQAAAA==.Azulpunkt:BAABNQAECn8YAAITAAkKKhelEQBPAgATAAkKKhelEQBPAgAAAA==.',
Ba='Baddaboomkin:BAAANQADCgEIAQAAAA==.Bananashamma:BAABNQAECn8ZAAMMAAkKvB2mOAB8AgAMAAgKfx2mOAB8AgAUAAYK3A3zswArAQAAAA==.Barbedwire:BAAANQAECggIAwAAAA==.',
Be='Bearmao:BAABNQAECn8xAAIGAAoK3hoCEwDZAQAGAAoK3hoCEwDZAQAAAA==.Belfas:BAAANQAECgUICAAAAA==.Bellah:BAAANQABCgIIAgAAAA==.Bellybutton:BAAANQAECgcIDgAAAA==.',
Bi='Bigpeach:BAAANQADCgEIAQAAAA==.Biltong:BAABNQAECn8WAAIFAAkKjQ9MGwCDAQAFAAkKjQ9MGwCDAQAAAA==.',
Bl='Blackpink:BAAANQADCgUIBQAAAA==.Bludnite:BAACNQAFFH8GAAIOAAQKCQojCgCxAAAOAAQKCQojCgCxAAA1AAQKfygAAg4ACApGHZUuAFkCAA4ACApGHZUuAFkCAAAA.',
Bo='Bokchoi:BAAANQAECgUIBQAAAA==.Boom:BAAANQADCgQICAAAAA==.',
Br='Brey:BAAANQAECgcIDAAAAA==.Bruute:BAABNQAECn82AAIKAAoK2R/QFQBiAwAKAAoK2R/QFQBiAwAAAA==.',
Bu='Budplatinum:BAAANQAECgUIEAAAAA==.',
['Bâ']='Bâït:BAAANQAECggIBwAAAA==.',
['Bå']='Båcon:BAAANQADCgcIBwAAAA==.',
Ca='Cairo:BAABNQAECn8nAAMVAAkK9iC5CwB+AgAKAAkKPxxiVACNAgAVAAcKFiO5CwB+AgAAAA==.Calai:BAAANQADCggICAAAAA==.Capitalchaos:BAABNQAECn81AAMWAAgKXheGCwAKAgAWAAgKXheGCwAKAgAKAAEKDgYZVgEwAAABNQAECgoKMAABAGcRAA==.Capnbeni:BAAANQADCgMIAwAAAA==.Cassandraa:BAAANQADCgQIBwAAAA==.Castingchaos:BAABNQAECn8wAAIBAAoKZxHHpgA0AgABAAoKZxHHpgA0AgAAAA==.',
Ce='Cell:BAABNQAECn8xAAIXAAoKiSJvAgBdAwAXAAoKiSJvAgBdAwAAAA==.Ceviche:BAAANQAECgcICwAAAA==.Ceàrrdòrn:BAABNQAECn8XAAIDAAgKGBTfyACKAQADAAgKGBTfyACKAQAAAA==.',
Ch='Chibí:BAAANQADCggIFgABNQAECggIDgARAAAAAA==.Chillzmatic:BAAANQAECgIIBwAAAA==.Chudbucket:BAABNQAECn8YAAMGAAcKfRm/jQDuAQAGAAYKaBy/jQDuAQAYAAMKJQ6MZwCOAAAAAA==.',
Ci='Cica:BAAANQAECgMIAwAAAA==.Cirillø:BAAANQAECgEIAQABNQAECgoKNQAZAIolAA==.',
Cl='Clovergold:BAACNQAFFH8JAAIDAAMKoQy1CADcAAADAAMKoQy1CADcAAA1AAQKfyUAAgMACgozGjtPAKcCAAMACgozGjtPAKcCAAAA.Clyde:BAABNQAECn8bAAMaAAcKgQyLMQASAQAaAAcKgQyLMQASAQAbAAMKMgSZNgBmAAAAAA==.',
Co='Corbis:BAABNQAECn8WAAMNAAcKSQ12gAAbAQANAAYKIw52gAAbAQAcAAUK/AavdgDIAAAAAA==.Cowpuss:BAAANQADCgQIBAABNQAECggIDwARAAAAAA==.',
Cr='Crevarus:BAAANQAECgEIAQAAAA==.Crimsonjeybi:BAAANQAECgcJCAAAAA==.Crunchwich:BAAANQAECgUIDAAAAA==.Cryos:BAAANQAECgIIAQAAAA==.',
Cu='Cutename:BAAANQAECgQIBAAAAA==.',
Cy='Cy:BAAANQAECgMIAwABNQAECgoKGQADAJAdAA==.Cynamyn:BAAANQAECgUIDAAAAA==.',
Cz='Czeskilight:BAAANQADCgIIAgAAAA==.',
['Cö']='Cömet:BAAANQADCgcICAAAAA==.',
Da='Daane:BAAANQADCgYIDQAAAA==.Daevarys:BAAANQAECgEIAQAAAA==.Dakhran:BAAANQADCgIJBAAAAA==.Dakkä:BAAANQADCggIBwAAAA==.Dan:BAABNQAECn8mAAIcAAoKxxcCBQAWAgAcAAoKxxcCBQAWAgAAAA==.Danthrax:BAABNQAECn8VAAIWAAoKMhOKAQD3AQAWAAoKMhOKAQD3AQAAAA==.Darkdemon:BAABNQAECn8hAAIdAAcK3ghpGgDaAAAdAAcK3ghpGgDaAAAAAA==.Darlord:BAAANQAECgQIBwAAAA==.Dawnliht:BAAANQADCgIIAgAAAA==.',
De='Deagle:BAAANQABCgIIBAABNQAECgoKKwAQAI0lAA==.Deandrya:BAAANQAECggIBgAAAA==.Deedubbya:BAAANQADCgcIBwAAAA==.Delryd:BAAANQAECgUIDAAAAA==.Demônlock:BAAANQAECgQICQAAAA==.Desideria:BAABNQAECn8gAAMeAAgKgA2JAgBYAQAeAAgKgA2JAgBYAQAEAAIK0gcuLAFlAAAAAA==.Despondence:BAACNQAFFH8GAAIdAAMKmhR0DQDUAAAdAAMKmhR0DQDUAAA1AAQKfzMAAh0ACgraHxsHAGADAB0ACgraHxsHAGADAAAA.Desynn:BAAANQAECgYJEAAAAA==.',
Di='Divinesyn:BAAANQADCgYIBgAAAA==.',
Dj='Djelysium:BAAANQAECgQICQAAAA==.Djtaki:BAABNQAECn80AAIIAAoKpxhDGAC6AgAIAAoKpxhDGAC6AgAAAA==.',
Do='Dogwater:BAAANQADCgYIBgABNQAFFAYIFwAbAD4jAA==.Doncarlos:BAACNQAFFH8HAAIGAAIKYAV8EQB/AAAGAAIKYAV8EQB/AAA1AAQKfzYAAgYACgqWHcMUAEsDAAYACgqWHcMUAEsDAAAA.Dorn:BAAANQADCgUIBQAAAA==.Dotty:BAAANQAECgEIAgAAAA==.Dottzz:BAAANQADCgYIBgAAAA==.Downbeatxo:BAECNQAFFH8XAAMfAAcKURRRAwDgAAAEAAUKhBqIDgCQAQAfAAMKOhBRAwDgAAA1AAQKfycAAwQACgqrIeAxAMECAAQACQqdIeAxAMECAB8ABAomGmAtABcBAAAA.',
Dr='Drdevoted:BAAANQADCgIIAgAAAA==.Drippie:BAAANQADCgYIEAAAAA==.Dròòid:BAAANQADCgQJBAABNQAFFAQIBgAOAAkKAA==.',
Du='Dubdred:BAAANQAECgIIAwAAAA==.Duhon:BAAANQAECgEIAwAAAA==.Dumptruck:BAAANQAECggIEgABNQAECgoKGQADAJAdAA==.',
Dw='Dwín:BAABNQAECn8dAAIGAAoKQgabtACbAQAGAAoKQgabtACbAQAAAA==.',
['Dê']='Dêals:BAABNQAECn8fAAIFAAgKORoKJQBPAQAFAAgKORoKJQBPAQAAAA==.',
Ed='Edgelordxx:BAAANQAECgEIAQAAAA==.',
El='Elasper:BAAANQAECgEIAQAAAA==.Eliselyia:BAAANQADCgYIIgAAAA==.Ellierose:BAABNQAECn8UAAICAAgKRwi+igB2AQACAAgKRwi+igB2AQAAAA==.',
Em='Emelianas:BAAANQAECgQIBAABNQAECgoKOAANANASAA==.Ems:BAAANQAECgEIAQAAAA==.',
En='Enjin:BAABNQAECn81AAMGAAoKeB3LIgAMAwAGAAoKYB3LIgAMAwAHAAMK/RyJDgC7AAAAAA==.Enragedbeef:BAAANQAECgUIBwABNQAECgoKOgASAOcUAA==.Entheogen:BAABNQAECn8ZAAMUAAYK2xJoJQAmAQAUAAYK2xJoJQAmAQAMAAQK7hPkxwDYAAAAAA==.',
Eo='Eogan:BAAANQADCgIIAwAAAA==.',
Ep='Epichuntard:BAAANQAECgQICwAAAA==.',
Er='Erolas:BAAANQADCgQIBwAAAA==.',
Es='Essay:BAABNQAECn8UAAIGAAoKwhRQXABgAgAGAAoKwhRQXABgAgAAAA==.',
Et='Ethereall:BAABNQAECn8XAAMdAAkKxRisHABwAgAdAAkKxRisHABwAgAgAAMKOQH4kQA3AAAAAA==.',
Eu='Eudora:BAAANQADCggICAABNQAECgoKKwAQAI0lAA==.',
Ev='Evalilly:BAAANQADCgYIBgAAAA==.Evanessance:BAAANQADCgYIBwAAAA==.Evilice:BAABNQAECn8xAAIDAAkKYA+pJACSAQADAAkKYA+pJACSAQAAAA==.Evoka:BAAANQAECgcIDwAAAA==.',
Fa='Faavibear:BAAANQAECggIAQAAAA==.Fallendevout:BAAANQAECgQICwAAAA==.Fallentroll:BAABNQAECn8dAAMNAAkKmhlKPQAqAgANAAkKKBlKPQAqAgAOAAMK7Rw8jADQAAAAAA==.Fatdoinkers:BAABNQAECn8ZAAQDAAoKkB0uRgDCAgADAAkKkB0uRgDCAgAZAAIKjhmNZwBFAAAFAAEK6AY/kgA6AAAAAA==.Fatman:BAAANQADCgcICAABNQADCgIIAwARAAAAAA==.Faydark:BAAANQADCgQIBAAAAA==.Fayia:BAAANQADCggIDgAAAA==.Fayye:BAAANQAECgYIEgAAAA==.',
Fi='Fireflydh:BAAANQADCgYIBgABNQAECgUIEgARAAAAAA==.Firragol:BAAANQABCgYICgAAAA==.Firèflyjd:BAAANQAECgUIEgAAAA==.Fishstick:BAAANQADCggIGAAAAA==.',
Fl='Floatpass:BAABNQAECn8zAAIBAAoKKyB9IABYAwABAAoKKyB9IABYAwAAAA==.',
Fo='Foot:BAAANQAECgEIAQAAAA==.',
Fr='Frizz:BAAANQAECgMIAwAAAA==.Froey:BAEANQAECgMIAwAAAA==.',
Fu='Fuzzypally:BAABNQAECn8YAAIFAAoKjx64IQDmAgAFAAoKjx64IQDmAgAAAA==.Fuzzytotems:BAAANQAECgcIDgAAAA==.',
['Fá']='Fáavi:BAAANQAECgQIBAAAAA==.',
Ga='Gali:BAAANQADCgQJBAABNQAFFAQIBgAOAAkKAA==.Galiagante:BAAANQADCggJDAAAAA==.Gallynna:BAABNQAECn8mAAQEAAgKChHCewDxAQAEAAgKChHCewDxAQAfAAIKdQ+cWgBxAAAeAAIKOA2xJABcAAAAAA==.Galorfax:BAABNQAECn8dAAIaAAgKmSB8DQCOAgAaAAgKmSB8DQCOAgAAAA==.Galushi:BAAANQADCgYIDQAAAA==.Garm:BAABNQAECn8tAAIGAAoKLCBUEgBXAwAGAAoKLCBUEgBXAwABNQAECgoKNgAKANkfAA==.',
Ge='Gelinea:BAAANQAECgEIAQAAAA==.Genovese:BAAANQADCgYJDAABNQAECgcIFgANAEkNAA==.Gernar:BAAANQADCgUIBwAAAA==.',
Gi='Gilgaroth:BAABNQAECn8rAAMIAAkKhRh0BQDIAQAhAAkKhhPLFwAfAgAIAAgKihh0BQDIAQAAAA==.Girlslove:BAAANQADCgIIAgABNQAFFAYIFwAbAD4jAA==.',
Go='Gobo:BAABNQAECn8WAAIUAAgKBRZEXwAEAgAUAAgKBRZEXwAEAgAAAA==.',
Gr='Graysonn:BAAANQADCggIGQAAAA==.Greafox:BAABNQAECn8eAAMMAAoKSiQQBgCVAwAMAAoKSiQQBgCVAwAUAAUKHxR/rgA2AQAAAA==.Grrimreaperr:BAAANQADCgcIBwAAAA==.Grýla:BAAANQADCgUIBQAAAA==.',
Gu='Guildenstern:BAAANQAECggIDgABNQAFFAYIFwAbAD4jAA==.Gundrakk:BAABNQAECn8YAAIiAAcKqhVtMQCPAQAiAAcKqhVtMQCPAQAAAA==.Gunnr:BAAANQAECgQICgABNQAECggIDgARAAAAAA==.Gunthorian:BAAANQAECgMJBAAAAA==.',
Ha='Hame:BAAANQAECgEIAQAAAA==.Handsomemonk:BAAANQADCgMIBAABNQAECgoKGQADAJAdAA==.Hansi:BAAANQAECgMIBQAAAA==.',
He='Heart:BAAANQAECgUIBAABNQAECgkJGwADAMwbAA==.Heid:BAAANQADCgYIDQAAAA==.Helldozer:BAAANQAECgEIAQAAAA==.',
Hi='Higanbana:BAACNQAFFH8gAAIdAAYKtyB6AQBIAQAdAAYKtyB6AQBIAQA1AAQKfzIAAh0ACgpdI/IFAHIDAB0ACgpdI/IFAHIDAAAA.Himawari:BAABNQAECn8fAAIDAAgKDyCTQwDKAgADAAgKDyCTQwDKAgABNQAFFAYIIAAdALcgAA==.Himejoshi:BAACNQAFFH8XAAIbAAYKPiNOAABwAgAbAAYKPiNOAABwAgA1AAQKfzYAAhsACgpNJioBAMsDABsACgpNJioBAMsDAAAA.Hippocampus:BAABNQAECn8dAAIMAAYKNiQICwATAgAMAAYKNiQICwATAgAAAA==.Hirys:BAABNQAECn8XAAIhAAgKKxNvGwD7AQAhAAgKKxNvGwD7AQAAAA==.',
Ho='Holybeks:BAAANQAECgEIBAABNQAECgoKJwAOAB8fAA==.Holydaddy:BAAANQAECgQIBgAAAA==.Holysmite:BAAANQAECgQIBAABNQAECgcICQARAAAAAA==.Hoppadk:BAABNQAECn8nAAIOAAoKHx8lGgDdAgAOAAoKHx8lGgDdAgAAAA==.Hotdoggin:BAAANQADCgEIAQABNQAECgoKGQADAJAdAA==.Hotshotzz:BAAANQAECgMIAwABNQAECggIIwADAF0fAA==.',
Hu='Huntfosho:BAAANQAECgQIBAAAAA==.Huntsmedown:BAAANQADCgYICQAAAA==.',
['Há']='Háldrin:BAACNQAFFH8MAAIYAAQKiRzUBQDXAAAYAAQKiRzUBQDXAAA1AAQKfy0AAxgACgo+IsYLAB0DABgACgqVIcYLAB0DAAYAAQo0JnRCAVsAAAAA.',
['Hö']='Hölybeary:BAAANQAECggIDQAAAA==.',
Ia='Iamprepared:BAAANQAECgEIAQAAAA==.',
Ic='Icybacon:BAAANQAECgQIBQAAAA==.Icëcrëam:BAAANQADCggICAAAAA==.',
Ih='Ihavegrass:BAAANQAECgUIDAAAAA==.',
Im='Imbue:BAABNQAECn8mAAIXAAgKwx6PAQD9AQAXAAgKwx6PAQD9AQAAAA==.Imbuer:BAAANQAECgQICAAAAA==.',
In='Innil:BAABNQAECn8aAAICAAoKdiVCAgDHAwACAAoKdiVCAgDHAwAAAA==.Inora:BAAANQABCgMIAwAAAA==.',
It='Itzapazz:BAAANQADCggIDAAAAA==.',
Ja='Jaurel:BAAANQADCgMIAwAAAA==.',
Je='Jessiks:BAAANQAECgIIAgAAAA==.Jessix:BAAANQAECggIEAAAAA==.Jezebel:BAABNQAECn8fAAMEAAkK2hU6TgBpAgAEAAkK3BM6TgBpAgAfAAEKoRf3awBIAAAAAA==.',
Ji='Jimfowler:BAAANQADCgIIAgAAAA==.Jirito:BAAANQAECgMJBAAAAA==.',
Jo='Jomadead:BAAANQAECgcIEwABNQAECgoKGAAMAKYSAA==.Jomas:BAABNQAECn8YAAIMAAoKphLpVQAQAgAMAAoKphLpVQAQAgAAAA==.Jovaar:BAAANQADCgYIBgAAAA==.',
Ju='Judera:BAABNQAECn8wAAMDAAoKQxdGEgDpAQADAAoKQxdGEgDpAQAZAAEKYRIqNAA5AAAAAA==.Juditis:BAAANQAECgEIAQAAAA==.',
Ka='Kaing:BAABNQAECn8WAAIWAAYKkA2UFgAyAQAWAAYKkA2UFgAyAQAAAA==.Kaladen:BAABNQAECn8YAAQiAAoKHyIpBwBQAwAiAAoKHyIpBwBQAwALAAEKlhIqrQA8AAAaAAEKvxccXQA7AAAAAA==.Kalec:BAAANQADCgUJBQAAAA==.Kalysti:BAAANQAECggIGgAAAQ==.Kaoticnature:BAAANQADCgYIDQAAAA==.Karolg:BAAANQAECgYIEwAAAA==.Katostrafic:BAABNQAECn8oAAMCAAoKchWiGACuAQAJAAcKcBUwCQDIAQACAAkKLRSiGACuAQAAAA==.Katrynna:BAAANQADCgYIEwAAAA==.',
Ke='Kelarra:BAAANQADCgQIBgAAAA==.',
Kh='Khromscarin:BAACNQAFFH8HAAIXAAIKuxbMAQCDAAAXAAIKuxbMAQCDAAA1AAQKfzMAAxcACgrPHEwDADUDABcACgrPHEwDADUDAB0ABwrVDdc2AI0BAAAA.',
Ki='Kiaradarkpaw:BAAANQAECgEIAwAAAA==.Killidan:BAABNQAECn8mAAIdAAoKGhzeEwDJAgAdAAoKGhzeEwDJAgAAAA==.Kirklees:BAAANQAECgMIBAAAAA==.Kitsuchan:BAABNQAECn8bAAQBAAoKFyHnSgDsAgABAAkKFyHnSgDsAgAjAAMK2iJMDADEAAAkAAEKAADMBAAAAAABNQAECggIGgAgAC8kAA==.',
Kk='Kkthx:BAAANQADCgcIBwABNQAECgoKOgASAOcUAA==.',
Ko='Kodama:BAABNQAECn8fAAIUAAkK3QnQkgB1AQAUAAkK3QnQkgB1AQAAAA==.Koi:BAAANQADCgcIEgABNQAECggIJQAXACoeAA==.Kookiemon:BAAANQAECgYIBgAAAA==.Kookiesplz:BAAANQADCggICAAAAA==.Kopili:BAAANQADCgUIBwAAAA==.',
Kr='Krekdas:BAAANQADCgUIBQAAAA==.Kromag:BAAANQADCgYIBgAAAA==.',
Ku='Kunpochiken:BAAANQADCgIIAgABNQAECgoKKAACAHIVAA==.',
Ky='Kyanna:BAAANQAECgUIDAAAAA==.',
La='Lader:BAABNQAFFH8GAAIDAAYKHwCWMgBGAAADAAYKHwCWMgBGAAAAAA==.Ladifantasie:BAAANQADCgUIBQAAAA==.Laria:BAABNQAECn8VAAIdAAgKshWSJQAZAgAdAAgKshWSJQAZAgAAAA==.Laxinmedium:BAAANQADCgYIDQAAAA==.',
Le='Leenei:BAAANQAECgMIBAAAAA==.Lenlaar:BAAANQAECgUIDAAAAA==.Levande:BAABNQAECn8iAAMCAAoKRhaTBwBxAgACAAoKRhaTBwBxAgASAAIKuw3qIQB9AAAAAA==.',
Li='Lifeblume:BAAANQADCggIFQAAAA==.Lildevil:BAAANQADCgUIBAAAAA==.Lilithandria:BAAANQAECggIDwAAAA==.Linamar:BAAANQAECgUICAAAAA==.Litenpr:BAAANQAECgEIAgAAAA==.',
Lo='Loaq:BAABNQAECn8uAAMCAAkKXxXbRgBSAgACAAkKXxXbRgBSAgAJAAMK4giBHACBAAAAAA==.Lockzrockz:BAAANQAECgUIAwAAAA==.Longbottom:BAAANQAECggICwABNQAECgoKGQADAJAdAA==.Loot:BAAANQAECggIEAAAAA==.Lorbert:BAAANQAECgMIAwABNQAECgoKJgAKACoUAA==.Lostalot:BAABNQAECn8nAAIGAAgKPRUGXwBZAgAGAAgKPRUGXwBZAgAAAA==.',
Lu='Luxæterna:BAABNQAECn86AAIDAAoK6BtuCABbAgADAAoK6BtuCABbAgAAAA==.',
Ly='Lyphiara:BAAANQADCggIGgABNQAECggIKQAPAOYgAA==.',
Ma='Malice:BAABNQAECn8VAAMeAAgKghUnCgDYAQAeAAgKghUnCgDYAQAfAAIKZAUFaQBPAAAAAA==.Mandwandos:BAABNQAECn8XAAMMAAoKIBijdwClAQAMAAgKqBWjdwClAQAUAAkKHglkjQCCAQAAAA==.Maraliss:BAAANQAECgUIDAAAAA==.',
Me='Meiri:BAAANQADCgEIAQABNQAFFAMICAAVADESAA==.Melaunis:BAAANQADCgYIDwAAAA==.Meowzer:BAABNQAECn8VAAQaAAUKlBJtHgCeAAALAAUKZxFXbAAZAQAaAAUKrA9tHgCeAAAbAAQK1AcBLwCaAAABNQAECgoKOgASAOcUAA==.Meteora:BAACNQAFFH8IAAIVAAMKMRLsBADEAAAVAAMKMRLsBADEAAA1AAQKfx8AAhUACgoYG3wMAG0CABUACgoYG3wMAG0CAAAA.',
Mi='Mideel:BAAANQAECgUIDAAAAA==.Midesis:BAAANQAECgUIBAAAAA==.Midesisheals:BAAANQAECgIIAgAAAA==.Migolbearcow:BAABNQAECn8tAAIaAAkKdRdEDwBwAgAaAAkKdRdEDwBwAgAAAA==.Missed:BAAANQAECgIJAwAAAA==.Missedweaver:BAAANQADCgYICAABNQAECgIJAwARAAAAAA==.Missrae:BAAANQADCggIEgAAAA==.',
Mk='Mk:BAEANQADCgIIAgABNQAECgkJJwAQABYcAA==.',
Ml='Mlglock:BAAANQADCgMIAwAAAA==.',
Mo='Moiira:BAAANQAECgEIAgAAAA==.Monyshot:BAAANQADCgUICwAAAA==.Moondizzle:BAAANQAECgMIBAAAAA==.Mooniè:BAAANQAECgUIDgAAAA==.Moosenuts:BAAANQAECgcIEAAAAA==.Moriavus:BAABNQAECn8qAAIeAAoKxxeyBACLAgAeAAoKxxeyBACLAgAAAA==.Morocha:BAABNQAECn8aAAIPAAcK6Q0JKQArAQAPAAcK6Q0JKQArAQAAAA==.Mortèm:BAAANQAECgIIAgAAAA==.Moxxie:BAAANQABCggIEwABNQADCggILgARAAAAAA==.',
Mu='Muragore:BAAANQAECgQICwAAAA==.',
My='Mychropien:BAABNQAECn8eAAMNAAkK7h3lIgC6AgANAAkK7h3lIgC6AgAOAAMK+gdpbQAjAAAAAA==.Myylus:BAAANQADCgYIFAAAAA==.',
['Mö']='Mökes:BAABNQAECn8zAAIfAAoKACQCAQCbAwAfAAoKACQCAQCbAwAAAA==.',
Na='Nadroj:BAAANQADCgUIGgAAAA==.Nancydru:BAAANQAECgUICwAAAA==.Naosu:BAAANQADCgEJAQAAAA==.Nax:BAAANQAECgQIDAAAAA==.Nazzersaurus:BAABNQAECn8aAAIiAAcKYxnYJQD0AQAiAAcKYxnYJQD0AQAAAA==.',
Ne='Nec:BAAANQAECgEIAgAAAA==.Necrøtic:BAABNQAECn8hAAMjAAkKDRBWDQDcAQAjAAkK4A9WDQDcAQABAAQKqgYijgGqAAAAAA==.Nekomata:BAAANQABCgIIAwAAAA==.Neodin:BAAANQAECgUICAAAAA==.Nevermiss:BAABNQAECn8nAAIPAAkKdBfkFgAPAgAPAAkKdBfkFgAPAgAAAA==.',
Ni='Nightjewel:BAAANQADCgYIDQAAAA==.',
No='Noggs:BAAANQAECgEIAQAAAA==.Notmewasyou:BAABNQAECn8ZAAILAAYK2wJihwC1AAALAAYK2wJihwC1AAAAAA==.',
Nu='Nuali:BAABNQAECn8hAAMDAAgK+hnHZABsAgADAAgK+hnHZABsAgAZAAYKzxIQHwCbAAAAAA==.Numi:BAAANQADCggIDQAAAA==.',
Od='Odysseus:BAAANQADCgUICQAAAA==.',
Ok='Okameshiz:BAAANQADCggJDQAAAA==.',
On='Onlyspins:BAAANQAECgYICAAAAA==.',
Or='Orý:BAABNQAECn84AAIUAAoKWRrbBQARAgAUAAoKWRrbBQARAgAAAA==.',
Os='Oslatem:BAAANQAECgEIAQAAAA==.',
Ox='Oxosorrel:BAAANQAECgEIBgAAAA==.',
Oz='Ozzmodious:BAAANQADCgUIEAAAAA==.',
Pa='Paladan:BAABNQAECn8mAAIZAAkKVyBfBwAtAwAZAAkKVyBfBwAtAwAAAA==.Paladanny:BAAANQAECgMIAwAAAA==.Palagi:BAABNQAECn8bAAMbAAYKcQNYFAB8AAAbAAYKcQNYFAB8AAAiAAEKugTsfQAjAAAAAA==.Pallu:BAAANQADCgQIBAAAAA==.Pallyana:BAABNQAECn8XAAIFAAkKzRoYMgCdAgAFAAkKzRoYMgCdAgAAAA==.Pallyfosho:BAAANQAECgIIAgAAAA==.Pallymcbeall:BAAANQAECgIIAgAAAA==.Paprikaman:BAAANQAECgUIDAAAAA==.Parallax:BAAANQAECgEIAQAAAA==.Pariahrain:BAAANQAECgYIEwABNQAECgoKJQABANkPAA==.Parishealton:BAABNQAECn8fAAMiAAkKox/0CQAnAwAiAAkKox/0CQAnAwALAAMKvQFvpgBMAAAAAA==.Payday:BAAANQADCgYICwAAAA==.Pazzuzu:BAAANQADCgUIBQAAAA==.',
Pe='Penjamin:BAAANQAECgMIAwABNQAECgoKGQADAJAdAA==.Perprotrus:BAAANQAECgEIAQABNQAFFAQIBgAOAAkKAA==.',
Po='Poulsbo:BAAANQADCgcIBgAAAA==.Pozole:BAAANQAECgcIDwAAAA==.',
Pr='Prominence:BAABNQAECn8WAAIHAAYKzh9XBwAGAgAHAAYKzh9XBwAGAgAAAA==.Promisques:BAAANQAECgEIBAAAAA==.Prozak:BAABNQAECn8jAAIMAAkKARNSYgDnAQAMAAkKARNSYgDnAQAAAA==.',
Pw='Pwomf:BAAANQAECgYICAAAAA==.',
Py='Pyneapple:BAAANQADCgQIBAABNQAECgoKOgASAOcUAA==.Pyrolily:BAAANQAECgYIDwAAAA==.',
Qu='Question:BAAANQADCgIIAwAAAA==.Qulung:BAAANQADCggIFAAAAA==.',
Ra='Rabyd:BAAANQADCggICAAAAA==.Raegasm:BAAANQADCgYICwAAAA==.Raght:BAAANQADCgEIAQAAAA==.Raha:BAAANQAECgIIAgAAAA==.Ramue:BAAANQADCgcIDgAAAA==.Raskela:BAABNQAECn8cAAMPAAkKpxO3GADyAQAPAAkKpxO3GADyAQAQAAcKdhQrMQCOAQAAAA==.Rastakan:BAAANQAECgYICQABNQAECgoKNgAKANkfAA==.Razal:BAAANQADCggIDQAAAA==.',
Re='Reesespiecez:BAAANQAECgcJDAAAAA==.Rellidana:BAAANQAECgQICAAAAA==.Remove:BAAANQAECgUIBQAAAA==.Reprieve:BAAANQAECgUICgAAAA==.Retradormi:BAAANQAECgEIAQAAAA==.Rexi:BAABNQAECn8hAAISAAkKCg6VJwDuAQASAAkKCg6VJwDuAQAAAA==.',
Ri='Rickcando:BAAANQAECgUIEgAAAA==.Ricshard:BAABNQAECn8iAAMEAAcKyhXwPgAQAQAEAAUK1RTwPgAQAQAfAAMKtBc3CQCLAAAAAA==.Ridjeckgron:BAAANQAECgEIAQAAAA==.Rissiia:BAAANQADCgQIBAAAAA==.',
Rm='Rmft:BAAANQADCgYIGgABNQAECggIJQAKAAAYAA==.',
Ro='Roomnboard:BAAANQAECgMIBQAAAA==.Rotter:BAAANQADCgQIBAAAAA==.Roughluver:BAAANQAECgQIAwABNQAECgoKOgASAOcUAA==.',
Ru='Ruben:BAAANQADCgEIAgAAAA==.Rungar:BAAANQAECgQIDQAAAA==.',
Rv='Rvoker:BAAANQADCgQIBAAAAA==.',
Ry='Rylia:BAAANQAECgEIAQAAAA==.Ryuk:BAAANQADCgMIAwAAAA==.Ryñ:BAAANQAECgEIBAAAAA==.',
['Rà']='Ràein:BAABNQAECn8lAAIfAAYKTA1yBQDRAAAfAAYKTA1yBQDRAAAAAA==.',
['Ró']='Ród:BAABNQAECn8jAAIDAAgKXR9IbwBRAgADAAgKXR9IbwBRAgAAAA==.',
['Rø']='Røth:BAAANQADCgYIDAAAAA==.',
Sa='Saalira:BAAANQADCgcIEAAAAA==.Sabellice:BAABNQAECn8kAAIDAAgKhgWyaQDyAAADAAgKhgWyaQDyAAAAAA==.Sakonna:BAABNQAECn8fAAISAAkKQRV8IAA1AgASAAkKQRV8IAA1AgAAAA==.Salinoria:BAAANQAECgQIDAABNQAECggIIQADAPoZAA==.Sandymaw:BAAANQADCgQIBAABNQAECgoKOgASAOcUAA==.Sarlius:BAABNQAECn82AAIGAAoKBSLpAgDYAwAGAAoKBSLpAgDYAwAAAA==.Sassybuns:BAAANQABCgQIBAAAAA==.Satyrical:BAABNQAECn8bAAIDAAkKzBtGEQDxAQADAAkKzBtGEQDxAQAAAA==.Savin:BAAANQAECgQICAAAAA==.',
Sc='Scavenger:BAAANQAECgUIDQAAAA==.Scorchin:BAAANQAECggIAwAAAA==.Scrumptiøus:BAAANQAECgUIBgABNQAECgoKKAACAHIVAA==.',
Se='Selkamonk:BAABNQAECn8pAAMPAAgK5iD0CgDXAgAPAAgK5iD0CgDXAgAQAAIKDgYDOQAvAAAAAA==.Seniorbold:BAABNQAECn8aAAIDAAoK3hezQgDMAgADAAoK3hezQgDMAgAAAA==.Sentrina:BAACNQAFFH8HAAIlAAQKIg5NCACZAAAlAAQKIg5NCACZAAA1AAQKfy4AAiUACgp9GigNANMCACUACgp9GigNANMCAAAA.Seraph:BAAANQAECgIIBAAAAA==.Seshy:BAABNQAECn86AAMSAAoK5xQmIAA5AgASAAgK3hgmIAA5AgACAAoKQxNtLABLAQAAAA==.Seshymutedme:BAAANQAECggIEwABNQAECgoKOgASAOcUAA==.Sethan:BAAANQAECgEIAQAAAA==.',
Sh='Shamanagins:BAAANQADCgEIAQAAAA==.Shannon:BAAANQADCgYIBgABNQAECgYIEgARAAAAAA==.Shannoon:BAAANQAECgYIEwAAAA==.Sharr:BAAANQADCgYJDAAAAA==.Shekzeer:BAABNQAECn8rAAQQAAoKjSXlAADnAwAQAAoKjSXlAADnAwAPAAYK0hzxGgDSAQAmAAMK8yALIwC/AAAAAA==.Shiverr:BAABNQAECn8eAAIjAAcK1QYmGQAtAQAjAAcK1QYmGQAtAQAAAA==.Shockakan:BAAANQABCgQIBAAAAA==.Shockazulu:BAAANQADCgIIAgAAAA==.Shocktard:BAAANQAECgEIAQABNQAECgkJHQAKABkUAA==.',
Si='Siatraz:BAAANQAECgEIAgABNQAECgUIEgARAAAAAA==.Siegatrox:BAAANQAECgIIAgAAAA==.Silgan:BAAANQADCgYIBgAAAA==.Silverbain:BAAANQADCgQIBAAAAA==.',
Sk='Skizem:BAAANQAECgEIBAAAAA==.Skott:BAAANQADCggILgAAAA==.Skïnnyßetch:BAAANQADCgcIBwAAAA==.',
Sl='Sleepadin:BAAANQAFFAEIAQAAAA==.Sleepyr:BAAANQAECgYIEAAAAA==.',
Sm='Smokeymage:BAAANQADCgcIBwAAAA==.',
Sn='Snowi:BAAANQADCgYIBgABNQAECggIDgARAAAAAA==.Snowstorm:BAAANQAECgEIAgAAAA==.',
So='Soakra:BAABNQAECn8iAAIMAAkK7xbaRABOAgAMAAkK7xbaRABOAgAAAA==.Solignis:BAACNQAFFH8hAAMWAAYKHCYUAAChAgAWAAYKHCYUAAChAgAKAAQK6R5WFACIAQA1AAQKfzwAAxYACgrkJgUAAB4EABYACgrkJgUAAB4EAAoACQp/Ju8HALMDAAAA.Solxeen:BAAANQADCggICAAAAA==.Soniviolence:BAABNQAECn8oAAIKAAkKlCBoGwBKAwAKAAkKlCBoGwBKAwAAAA==.Soohots:BAABNQAECn8cAAMiAAkK4B3YCQCaAQAiAAgK3RzYCQCaAQALAAQKLxDsjQCfAAAAAA==.Sourskittlz:BAAANQADCgQIBAAAAA==.',
Sp='Sparklehappy:BAABNQAECn8UAAMYAAYKrxl9OgB8AQAYAAUKihl9OgB8AQAGAAEKQRoJRgFTAAAAAA==.Splìff:BAAANQADCgYIBgAAAA==.Sppazz:BAAANQADCgcIBwAAAA==.',
St='Stausa:BAAANQADCgcIBwAAAA==.Steeljustice:BAAANQAECggICAAAAA==.Stormcreek:BAABNQAECn8YAAMMAAYKehn0MwAUAQAMAAYKehn0MwAUAQAUAAEKAAAzSAEqAAAAAA==.Storri:BAABNQAECn85AAMCAAoK7xYoEwDaAQACAAoK7xYoEwDaAQASAAUKwgYbVAC9AAAAAA==.Styló:BAAANQAECgEIAgAAAA==.',
Su='Sufferinhero:BAAANQAECgEIAQABNQAFFAIIBwAXALsWAA==.Suzuya:BAAANQADCggIFAAAAA==.',
Sw='Swiftly:BAAANQAECgcICwAAAA==.Swiftmage:BAACNQAFFH8hAAMjAAYKIyIZAACPAQABAAUKvR0cGgCpAQAjAAYKIyIZAACPAQA1AAQKfzsAAyMACgrMJg8AAAcEACMACgrMJg8AAAcEAAEACQoqJeMYAHEDAAAA.Switchboard:BAAANQADCgYICgAAAA==.',
Sx='Sxkittn:BAAANQADCgQIBAAAAA==.',
Sy='Sygh:BAAANQAECgEIAgABNQAECgkJGwADAMwbAA==.Syltru:BAAANQADCgUIBQAAAA==.Syndragonkin:BAABNQAECn8lAAIGAAcKzhgcfAAWAgAGAAcKzhgcfAAWAgAAAA==.Syndrome:BAAANQADCggIDgAAAA==.Synger:BAAANQADCgYIEAAAAA==.',
Ta='Taima:BAAANQABCgEIAQAAAA==.Talyndis:BAACNQAFFH8eAAIYAAgKWR27AgB4AgAYAAgKWR27AgB4AgA1AAQKfy4AAhgACgpiI3QHAFkDABgACgpiI3QHAFkDAAAA.Tamyr:BAAANQADCgIIAgAAAA==.Tazadar:BAAANQADCgcIFwAAAA==.Taze:BAAANQAECgUJBwABNQAFFAQIBgAOAAkKAA==.Tazjiingo:BAAANQADCgIIBAAAAA==.',
Te='Ted:BAAANQADCggIEAAAAA==.Terrika:BAABNQAECn8dAAIGAAgKnwrxigD0AQAGAAgKnwrxigD0AQAAAA==.Tetshajeh:BAACNQAFFH8HAAIKAAIKFRHNEgCHAAAKAAIKFRHNEgCHAAA1AAQKf0IAAwoACgp5IEoLAAwCAAoACgp5IEoLAAwCABUAAwrQGOIrANkAAAAA.Teyliana:BAAANQAECgQIDAAAAA==.',
Th='Thebigchud:BAAANQAECgYIBgAAAA==.Thillarick:BAABNQAECn8lAAIKAAgKABjuGwCUAQAKAAgKABjuGwCUAQAAAA==.Thiss:BAAANQABCgYIAwAAAA==.Thromanor:BAAANQAECgUIBQAAAA==.Thwip:BAABNQAECn8sAAMGAAoKRCGaLADoAgAGAAoKRCGaLADoAgAYAAcKVRGzPgBdAQAAAA==.',
Ti='Tikwid:BAABNQAECn8lAAIBAAgKhwX5VgAPAQABAAgKhwX5VgAPAQAAAA==.Tiranmyashol:BAABNQAECn8mAAIKAAoKKhTcaABVAgAKAAoKKhTcaABVAgAAAA==.',
To='Tomoya:BAABNQAECn8UAAMFAAgKuhgPSABGAgAFAAgKuhgPSABGAgAZAAEKAABodQAnAAAAAA==.Too:BAAANQAECgIIAgAAAA==.Toothdk:BAAANQAECgQICgAAAA==.Tormmentor:BAAANQAECgQICgAAAA==.',
Tr='Treebreak:BAAANQAECgQIEwAAAA==.',
Ty='Tyrandrea:BAAANQAECgEIAQAAAA==.',
Ud='Udari:BAAANQAECgcICAAAAA==.Udarii:BAAANQAECgMIBQAAAA==.',
Um='Umàdbrah:BAABNQAECn8jAAIGAAgK6xrZCAA4AgAGAAgK6xrZCAA4AgAAAA==.',
Un='Unbelievable:BAABNQAECn8YAAIgAAgKwQeLIAD5AAAgAAgKwQeLIAD5AAAAAA==.Unprovoked:BAABNQAECn8iAAIBAAkKwh5dVwDRAgABAAkKwh5dVwDRAgAAAA==.',
Va='Valamor:BAABNQAECn8iAAMZAAcKvg8fDQAxAQAZAAcKvg8fDQAxAQAFAAUK4Ae1zQDgAAAAAA==.Varenea:BAAANQADCgYIBgAAAA==.Varia:BAAANQAECgEIBAABNQAECgkJHQAKABkUAA==.',
Ve='Veefib:BAABNQAECn8oAAMUAAkKDhnjQAByAgAUAAgK9xrjQAByAgAMAAIKpwrHcQBuAAAAAA==.Velvettwitch:BAABNQAECn8kAAIfAAgKoBBSEgDiAQAfAAgKoBBSEgDiAQAAAA==.Vendler:BAAANQAECgcIEgAAAA==.Verahla:BAAANQADCgYIHAAAAA==.Vermis:BAABNQAECn8lAAIcAAcK5hAgLADsAAAcAAcK5hAgLADsAAAAAA==.Veryaverage:BAAANQAECgcIEgAAAA==.Vexation:BAAANQAECgIIAgAAAA==.',
Vi='Vicarious:BAABNQAECn8ZAAIMAAgKURoiPgBnAgAMAAgKURoiPgBnAgAAAA==.Vidreaux:BAABNQAECn8xAAMBAAkKKgwbTwAdAQABAAgKUAwbTwAdAQAjAAIKDwt8EgBuAAAAAA==.Villaraa:BAAANQADCgEIAQAAAA==.Vivid:BAAANQAECgEIAQAAAA==.',
Vo='Voidofvoids:BAAANQAECgUIBQAAAA==.Volke:BAAANQAECgUICQAAAA==.Votingromney:BAAANQAECgcICwABNQAECgoKKwAQAI0lAA==.Vowz:BAAANQADCgMIAwAAAA==.',
Vu='Vulpe:BAABNQAECn8pAAIGAAgKOht1XABgAgAGAAgKOht1XABgAgAAAA==.',
Vy='Vyolenta:BAAANQADCgIIAgAAAA==.',
['Vë']='Vëxhunter:BAAANQAECgcICQAAAA==.',
Wa='Waldorf:BAAANQAECgUICAAAAA==.Wallegator:BAAANQAECgEIAQABNQAECgcIIAAiAOgfAA==.Walleroot:BAAANQAECgUIBQABNQAECgcIIAAiAOgfAA==.Waptoed:BAAANQAECgEIAQAAAA==.',
We='Weinersoup:BAAANQAECgUIDQAAAA==.',
Wh='Whitewhitch:BAAANQADCgIIAwAAAA==.Whosethetank:BAAANQAECgMICAAAAA==.',
Wo='Wolfpup:BAAANQAECggIDQABNQAECgoKMAADAEMXAA==.Wolfíe:BAAANQADCgUIBQAAAA==.Worstelf:BAABNQAECn8fAAMCAAgKPBoYQABqAgACAAgKPBoYQABqAgASAAYKgiIAIgAlAgAAAA==.',
Ww='Wwalle:BAAANQADCgIIAgABNQAECgcIIAAiAOgfAA==.',
Xa='Xanathos:BAAANQABCgEIAQABNQAECgoKNgAGAAUiAA==.',
Xi='Xilstar:BAAANQADCgUIBQAAAA==.',
Xz='Xzavier:BAAANQADCgYIDQAAAA==.',
Yf='Yfelshammy:BAABNQAECn8rAAIMAAoKLBQMTAAzAgAMAAoKLBQMTAAzAgAAAA==.',
Yv='Yvaldi:BAAANQAECgYIBgABNQAFFAIICAACANciAA==.Yvonnél:BAAANQADCggIIgAAAA==.',
Za='Zaknafein:BAAANQAECgUICQAAAA==.Zanebusby:BAABNQAECn8mAAIfAAoKNRlpAwAOAwAfAAoKNRlpAwAOAwAAAA==.Zankru:BAAANQADCgYIBwAAAA==.Zaraë:BAAANQADCggIDgAAAA==.Zaria:BAAANQAECgcIDgABNQAECgoKKwAQAI0lAA==.Zartash:BAABNQAECn8UAAIdAAgK3AN2HADKAAAdAAgK3AN2HADKAAAAAA==.Zatharis:BAAANQAECgQIEAAAAA==.',
Ze='Zelik:BAAANQAECgMIBQABNQAECgoKNgAGAAUiAA==.Zenezin:BAAANQAECgMIBAABNQAECgkJHQAKABkUAA==.Zerax:BAAANQAECgUIBwABNQAECgoKNgAKANkfAA==.Zevellian:BAAANQAECgEIAQABNQAECggIFAAFAPMcAA==.',
Zm='Zmona:BAABNQAECn8dAAIKAAkKGRRmLgBSAQAKAAkKGRRmLgBSAQAAAA==.',
Zo='Zolrath:BAAANQABCgQIAgAAAA==.',
['Ãm']='Ãmpstar:BAAANQADCgMIAwAAAA==.',
['Äm']='Ämpstarr:BAAANQADCgEIAQAAAA==.',
['Çy']='Çyanide:BAAANQADCgQICgABNQAECgkJGwADAMwbAA==.',
['Ðr']='Ðragonshaft:BAABNQAECn8sAAIGAAkKiBOvbAA5AgAGAAkKiBOvbAA5AgAAAA==.Ðreadlokz:BAAANQAECgEIAQAAAA==.',
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
