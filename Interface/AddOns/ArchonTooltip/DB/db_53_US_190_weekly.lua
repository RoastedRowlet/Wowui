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

local lookup = {'Mage-Arcane','Priest-Holy','Paladin-Retribution','Warlock-Demonology','Hunter-BeastMastery','Hunter-Survival','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','Warrior-Arms','Druid-Balance','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','Priest-Shadow','Unknown-Unknown','Shaman-Enhancement','Paladin-Holy','Evoker-Devastation','Warrior-Protection','Warrior-Fury','DemonHunter-Vengeance','Hunter-Marksmanship','Paladin-Protection','Druid-Guardian','Druid-Feral','DeathKnight-Frost','DemonHunter-Devourer','Warlock-Affliction','Warlock-Destruction','Shaman-Elemental','DemonHunter-Havoc','Evoker-Preservation','Druid-Restoration','Mage-Frost','Mage-Fire','Monk-Brewmaster',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aarazi:BAABNQAECn81AAIBAAoKuBsjJABmAgABAAoKuBsjJABmAgAAAA==.',
Ab='Abbinormal:BAAANQADCgYIHAAAAA==.Abolish:BAAANQABCgIIAgAAAA==.',
Ad='Adïrael:BAAANQABCggIEwAAAA==.',
Ae='Aeriss:BAAANQADCgYIDAAAAA==.Aethena:BAAANQADCgUIBQABNQAECgcIIgACAHcPAA==.Aezili:BAAANQADCgcIDQAAAA==.',
Ag='Agamotto:BAAANQADCgMIAwAAAA==.Agerol:BAABNQAECn8kAAIDAAgKJh+uXQB/AgADAAgKJh+uXQB/AgAAAA==.',
Ah='Ahaego:BAABNQAECn8bAAIEAAgK4Q67UgBrAQAEAAgK4Q67UgBrAQAAAA==.Ahnari:BAAANQAECgIIAgAAAA==.',
Ak='Akkadien:BAAANQAECgcIEQAAAA==.Akumunter:BAABNQAECn8wAAMFAAoK3xlHKwDsAgAFAAoK1hlHKwDsAgAGAAEKkg20DABJAAAAAA==.',
Al='Alacardias:BAABNQAECn8oAAIDAAkKCB29RADGAgADAAkKCB29RADGAgAAAA==.Alihuntress:BAAANQADCgQIBQAAAA==.Alleril:BAABNQAECn8kAAMHAAoKkRL2BwAVAgAHAAkKmRD2BwAVAgAIAAkKbQ9ENgCRAQAAAA==.Allthesnacks:BAAANQAECggICwAAAA==.Aloe:BAAANQADCgYICQAAAA==.',
Am='Amarynth:BAAANQADCgQIBAAAAA==.Amäri:BAACNQAFFH8IAAICAAIK1yIFIwDIAAACAAIK1yIFIwDIAAA1AAQKfxoAAwIACAoiJGYhAOkCAAIACAoQJGYhAOkCAAkABArUGMEQAB0BAAAA.',
An='Anassand:BAAANQAECggIEQABNQAECgkJHQAKABkUAA==.Anatomic:BAAANQADCgIIAgABNQAECgcIIgACAHcPAA==.Andicandy:BAAANQAECgEIAQABNQAECgkJJAALAK4XAA==.Andimorph:BAABNQAECn8kAAILAAkKrhcvMQBYAgALAAkKrhcvMQBYAgAAAA==.Angeleria:BAAANQADCgUIBQAAAA==.',
Ap='Apazz:BAABNQAECn8tAAIFAAkKUxXIbQA3AgAFAAkKUxXIbQA3AgAAAA==.',
Aq='Aqualight:BAAANQAECggICgABNQAECgoKMgAMAGgkAA==.Aquashade:BAAANQAECgUIBQABNQAECgoKMgAMAGgkAA==.Aquaterra:BAABNQAECn8yAAIMAAoKaCSuDQBTAwAMAAoKaCSuDQBTAwAAAA==.Aquina:BAAANQAECgcIDQABNQAECgoKMgAMAGgkAA==.',
Ar='Arakadia:BAABNQAECn9BAAMNAAoKehWpHACPAQANAAoKmBKpHACPAQAOAAMKxRrlaABiAAAAAA==.Arcaina:BAAANQAECgQIBwAAAA==.Artoriaz:BAAANQADCgcJCwAAAA==.Aruteeru:BAABNQAECn8hAAMPAAgKDhlXGAD5AQAPAAgKDhlXGAD5AQAQAAgKIhMZLwCeAQAAAA==.',
As='Aseanna:BAABNQAECn8ZAAMRAAkKKhEkFACJAQARAAkKKhEkFACJAQACAAIKHw9xrgBmAAAAAA==.Astraen:BAAANQADCgQIBgAAAA==.',
Au='Augmentussy:BAAANQADCggICAABNQAECgoKKwAQAI0lAA==.Auxiliater:BAAANQADCgEIAQAAAA==.Auxiliator:BAAANQADCgYIBgAAAA==.Auxlox:BAAANQADCgcIBwAAAA==.Auxshadow:BAAANQABCgIIAgABNQADCgYIBgASAAAAAA==.',
Av='Avarous:BAABNQAECn8rAAMCAAkKLRrbHwBjAgACAAkKLRrbHwBjAgARAAEKAABvigAgAAAAAA==.Avataroffury:BAAANQAECgQIBAABNQAECgkJHQAKABkUAA==.',
Ax='Axará:BAAANQADCgQIBAAAAA==.Axel:BAAANQADCgUIBwAAAA==.',
Ay='Ayala:BAACNQAFFH8NAAIDAAQKxB0cEgAvAQADAAQKxB0cEgAvAQA1AAQKfx8AAgMACgpsJFERAO0CAAMACgpsJFERAO0CAAAA.',
Az='Azaireos:BAAANQADCgYIDQAAAA==.Azulpunkt:BAABNQAECn8bAAITAAoKQxalEQBPAgATAAoKQxalEQBPAgAAAA==.',
Ba='Baddaboomkin:BAAANQADCgEIAQAAAA==.Bananashamma:BAAANQAECgcIEQAAAA==.Barbedwire:BAAANQAECggIAwAAAA==.',
Be='Bearmao:BAABNQAECn89AAIFAAoKIh+5GwCBAgAFAAoKIh+5GwCBAgAAAA==.Belfas:BAAANQAECgQIBQAAAA==.Bellah:BAAANQABCgIIAgAAAA==.Bellybutton:BAAANQAECgcIDwAAAA==.',
Bi='Bigpeach:BAAANQADCgEIAQAAAA==.Biltong:BAABNQAECn8cAAIUAAkK/hD7NwC9AQAUAAkK/hD7NwC9AQAAAA==.',
Bl='Blackpink:BAAANQADCgUIBQAAAA==.Bladesinger:BAAANQADCgYIBgAAAA==.Bludnite:BAACNQAFFH8GAAIOAAQKCQoYEACkAAAOAAQKCQoYEACkAAA1AAQKfykAAw4ACQq/GpUuAFkCAA4ACApGHZUuAFkCAA0AAQoQCU1tADUAAAAA.',
Bo='Bokchoi:BAAANQAECgUIBQAAAA==.Boom:BAAANQADCgQICAAAAA==.',
Br='Brey:BAAANQAECgcICwAAAA==.Bruute:BAABNQAECn89AAIKAAoK6yHQFQBiAwAKAAoK6yHQFQBiAwAAAA==.',
Bu='Budplatinum:BAABNQAECn8WAAIVAAcKhwTuEADDAAAVAAcKhwTuEADDAAAAAA==.',
['Bâ']='Bâït:BAAANQAECggIBwAAAA==.',
['Bå']='Båcon:BAAANQAECgEIAQAAAA==.',
Ca='Cairo:BAABNQAECn8nAAMWAAkK9iC5CwB+AgAKAAkKPxxiVACNAgAWAAcKFiO5CwB+AgAAAA==.Calai:BAAANQADCggICAAAAA==.Capitalchaos:BAABNQAECn88AAMXAAkKYBaGCwAKAgAXAAkKYBaGCwAKAgAKAAEKDgYZVgEwAAABNQAECgoKNQABAFQSAA==.Capnbeni:BAAANQADCgMIAwAAAA==.Cassandraa:BAAANQADCgQIBwAAAA==.Castingchaos:BAABNQAECn81AAIBAAoKVBLHpgA0AgABAAoKVBLHpgA0AgAAAA==.',
Ce='Cell:BAABNQAECn81AAIYAAoKiSJvAgBdAwAYAAoKiSJvAgBdAwAAAA==.Ceviche:BAAANQAECgcIDgAAAA==.Ceàrrdòrn:BAABNQAECn8eAAIDAAgK+BSsmQAgAQADAAgK+BSsmQAgAQAAAA==.',
Ch='Chibí:BAAANQADCggIFgABNQAECggIDgASAAAAAA==.Chillzmatic:BAAANQAECgIIBgAAAA==.Chirri:BAAANQADCgYIBgAAAA==.Chudbucket:BAABNQAECn8aAAMFAAgKFBm/jQDuAQAFAAcKcRu/jQDuAQAZAAMKJQ6MZwCOAAAAAA==.',
Ci='Cica:BAAANQAECgMIAwAAAA==.Cirillø:BAAANQAECgUIBQABNQAECgoKQAAaAJIlAA==.',
Cl='Clovergold:BAACNQAFFH8KAAIDAAQKoQzpDgDPAAADAAQKoQzpDgDPAAA1AAQKfycAAgMACgozGjtPAKcCAAMACgozGjtPAKcCAAAA.Clyde:BAABNQAECn8bAAMbAAcKgQyLMQASAQAbAAcKgQyLMQASAQAcAAMKMgSZNgBmAAAAAA==.',
Co='Confearacy:BAAANQAECggICAAAAA==.Corbis:BAABNQAECn8WAAMNAAcKSQ12gAAbAQANAAYKIw52gAAbAQAdAAUK/AavdgDIAAAAAA==.Cowpuss:BAAANQADCgQIBAABNQAECgcIEQASAAAAAA==.',
Cr='Creekdeath:BAAANQAECggICAAAAA==.Crevarus:BAAANQADCgUJDAAAAA==.Crimsonjeybi:BAAANQAECgcJCAAAAA==.Crunchwich:BAAANQAECgUIDgAAAA==.Cryos:BAAANQAECgIIAQAAAA==.',
Cu='Cutename:BAAANQAECgQIBAAAAA==.',
Cy='Cy:BAAANQAECgUIBQABNQAECgoKIQADAF4hAA==.Cynamyn:BAAANQAECgUIDgAAAA==.',
Cz='Czeskilight:BAAANQADCgIIAgAAAA==.',
['Cö']='Cömet:BAAANQADCgcICAAAAA==.',
Da='Daane:BAAANQADCgYIDQAAAA==.Daevarys:BAAANQAECgEIAQAAAA==.Dakhran:BAAANQADCgIIBAAAAA==.Dakkä:BAAANQADCggIBwAAAA==.Dan:BAABNQAECn8sAAIdAAoKphllHQCfAgAdAAoKphllHQCfAgAAAA==.Danthrax:BAABNQAECn8YAAIXAAoKDBUWBgDjAQAXAAoKDBUWBgDjAQAAAA==.Darkdemon:BAABNQAECn8hAAIeAAcK3gjePwBNAQAeAAcK3gjePwBNAQAAAA==.Darlord:BAAANQAECgQIBgAAAA==.Dawnliht:BAAANQADCgIIAgAAAA==.',
De='Deagle:BAAANQABCgIIBAABNQAECgoKKwAQAI0lAA==.Deandrya:BAAANQAECggIBwAAAA==.Deedubbya:BAAANQADCgcIBwAAAA==.Delryd:BAAANQAECgUICgAAAA==.Demonetized:BAAANQAECgQIBAAAAA==.Demônlock:BAAANQAECgUICwAAAA==.Desideria:BAABNQAECn8oAAMfAAkKJwz/BQBvAQAfAAkKJwz/BQBvAQAEAAIK0gcuLAFlAAAAAA==.Despondence:BAACNQAFFH8HAAIeAAMKmhR0DQDUAAAeAAMKmhR0DQDUAAA1AAQKfzoAAh4ACgouIBsHAGADAB4ACgouIBsHAGADAAAA.Desynn:BAAANQAECgYJDgAAAA==.',
Di='Divinesyn:BAAANQAECgIIAgAAAA==.Divonah:BAAANQADCgMIAwAAAA==.',
Dj='Djelysium:BAAANQAECgQIBwAAAA==.Djtaki:BAABNQAECn84AAIHAAoKGBlDGAC6AgAHAAoKGBlDGAC6AgAAAA==.',
Do='Dogwater:BAAANQADCgYIBgABNQAFFAYIFwAcAD4jAA==.Doncarlos:BAACNQAFFH8JAAIFAAIKYAW8GgB9AAAFAAIKYAW8GgB9AAA1AAQKf0AAAgUACgpiH8MUAEsDAAUACgpiH8MUAEsDAAAA.Dorn:BAAANQAECgEIAQAAAA==.Dotty:BAAANQAECgEIAQAAAA==.Dottzz:BAAANQADCgYIBgAAAA==.Downbeatxo:BAECNQAFFH8YAAMgAAcKURRRAwDgAAAEAAUKhBqIDgCQAQAgAAMKOhBRAwDgAAA1AAQKfy8AAwQACgpcIrsSAJMCAAQACgpcIrsSAJMCACAABAomGmAtABcBAAAA.',
Dr='Drdevoted:BAAANQADCgIIAgAAAA==.Drippie:BAAANQADCgcIFwAAAA==.Dròòid:BAAANQADCgQJBAABNQAFFAQIBgAOAAkKAA==.',
Du='Dubdred:BAAANQAECgIIAgAAAA==.Duhon:BAAANQADCgQIBAAAAA==.Dumptruck:BAAANQAECggIEQABNQAECgoKIQADAF4hAA==.',
Dw='Dwín:BAABNQAECn8dAAIFAAoKQgabtACbAQAFAAoKQgabtACbAQAAAA==.',
['Dê']='Dêals:BAABNQAECn8hAAIUAAgKOxqTRwBIAgAUAAgKOxqTRwBIAgAAAA==.',
Ed='Edgelordxx:BAAANQAECgEIAQAAAA==.',
El='Elasper:BAAANQADCgcICQAAAA==.Eliselyia:BAAANQADCgYIJgAAAA==.Ellierose:BAAANQAECgcIEgAAAA==.',
Em='Emelianas:BAAANQAECgQICAABNQAECgoKQQANAHoVAA==.Ems:BAAANQAECgEIAQAAAA==.',
En='Enaelna:BAAANQAECgEIAQAAAA==.Enjin:BAABNQAECn8+AAMFAAoKCSJUCwD3AgAFAAoKCSJUCwD3AgAGAAMK/RyJDgC7AAAAAA==.Enragedbeef:BAAANQAECgUIBQABNQAECgoKPwACABwVAA==.Entheogen:BAABNQAECn8gAAMhAAcKmRHKQgBJAQAhAAcKmRHKQgBJAQAMAAQK7hPkxwDYAAAAAA==.',
Eo='Eogan:BAAANQADCgIIAwAAAA==.',
Ep='Epichuntard:BAAANQAECgQICQAAAA==.',
Er='Erolas:BAAANQADCgQIBwAAAA==.',
Es='Essay:BAABNQAECn8cAAIFAAoK6RbtOQD5AQAFAAoK6RbtOQD5AQAAAA==.',
Et='Ethereall:BAABNQAECn8XAAMeAAkKxRisHABwAgAeAAkKxRisHABwAgAiAAMKOQH4kQA3AAAAAA==.',
Eu='Eudora:BAAANQADCggICAABNQAECgoKKwAQAI0lAA==.',
Ev='Evalilly:BAAANQADCgYIBgAAAA==.Evanessance:BAAANQADCgYIBwAAAA==.Evilice:BAABNQAECn84AAIDAAkKZRH5WQCpAQADAAkKZRH5WQCpAQAAAA==.Evoka:BAABNQAECn8WAAIjAAcKMw88EABoAQAjAAcKMw88EABoAQAAAA==.',
Fa='Faavibear:BAAANQAECggIAQAAAA==.Fallendevout:BAAANQAECgQICAAAAA==.Fallentroll:BAABNQAECn8dAAMNAAkKmhlKPQAqAgANAAkKKBlKPQAqAgAOAAMK7Rw8jADQAAAAAA==.Fatdoinkers:BAABNQAECn8hAAQDAAoKXiFhIgB/AgADAAkKXiFhIgB/AgAUAAIKowx6pQBsAAAaAAIKjhmNZwBFAAAAAA==.Fatman:BAAANQADCgcICAABNQADCgIIAwASAAAAAA==.Faydark:BAAANQADCgQIBAAAAA==.Fayia:BAAANQADCggIDgAAAA==.Fayye:BAABNQAECn8YAAIUAAcKdg8CSAB2AQAUAAcKdg8CSAB2AQAAAA==.',
Fe='Felbeks:BAAANQAECgQIBAABNQAECgoKLQAOACogAA==.',
Fi='Fireflydh:BAAANQADCgYIBgABNQAECgoKHgAgAPcSAA==.Firragol:BAAANQABCgYICgAAAA==.Firèflyjd:BAABNQAECn8eAAQgAAoK9xKpFAB0AAAEAAcKmxCdbAAlAQAgAAIK4xepFAB0AAAfAAIK8BSTGABHAAAAAA==.Fishstick:BAAANQADCggIGAAAAA==.',
Fl='Floatpass:BAACNQAFFH8GAAIBAAMKKxluEwD9AAABAAMKKxluEwD9AAA1AAQKfzgAAgEACgr9IX0gAFgDAAEACgr9IX0gAFgDAAAA.',
Fo='Foot:BAAANQADCgcJCQAAAA==.',
Fr='Frizz:BAAANQAECgQIBwAAAA==.Froey:BAEANQAECgMIAwAAAA==.',
Fu='Fuzzypally:BAABNQAECn8YAAIUAAoKjx64IQDmAgAUAAoKjx64IQDmAgAAAA==.Fuzzyshadow:BAAANQAECgQIBAAAAA==.Fuzzytotems:BAAANQAECgcIDgAAAA==.',
['Fá']='Fáavi:BAAANQAECgQIBAAAAA==.',
Ga='Gali:BAAANQADCgQJBAABNQAFFAQIBgAOAAkKAA==.Galiagante:BAAANQADCggJDAAAAA==.Gallynna:BAABNQAECn8tAAQEAAgKphLCewDxAQAEAAgKKRHCewDxAQAgAAMKVRCcWgBxAAAfAAMKhwuxJABcAAAAAA==.Galorfax:BAABNQAECn8lAAIbAAkK5h+KCABPAgAbAAkK5h+KCABPAgAAAA==.Galushi:BAAANQADCgYIDQAAAA==.Garm:BAABNQAECn82AAIFAAoK1iFUEgBXAwAFAAoK1iFUEgBXAwABNQAECgoKPQAKAOshAA==.',
Ge='Gelinea:BAAANQADCgYIDQAAAA==.Gerlton:BAAANQADCgQIBAAAAA==.Gernar:BAAANQADCgUIBwAAAA==.',
Gi='Gilgaroth:BAABNQAECn81AAMHAAkKqRnJDACzAQAIAAkKKxdNJAABAgAHAAgKLBnJDACzAQAAAA==.Girlslove:BAAANQADCgIIAgABNQAFFAYIFwAcAD4jAA==.',
Gn='Gnoskill:BAAANQABCgQICgAAAA==.',
Go='Gobo:BAABNQAECn8WAAIhAAgKBRZEXwAEAgAhAAgKBRZEXwAEAgAAAA==.',
Gr='Graysonn:BAAANQADCggIGQAAAA==.Greafox:BAABNQAECn8kAAMMAAoKSiQQBgCVAwAMAAoKSiQQBgCVAwAhAAUKHxR/rgA2AQAAAA==.Grrimreaperr:BAAANQADCgcIBwAAAA==.Grýla:BAAANQADCgUIBQAAAA==.',
Gu='Guildenstern:BAABNQAECn8aAAMHAAoK5Bx8AwC5AgAHAAoKKxx8AwC5AgAIAAIKZhitjQBPAAABNQAFFAYIFwAcAD4jAA==.Gundrakk:BAAANQAECgYIEQAAAA==.Gunnr:BAAANQAECgQICQABNQAECggIDgASAAAAAA==.Gunthorian:BAAANQAECgMJAwAAAA==.',
Ha='Handsomemonk:BAAANQADCgMIBAABNQAECgoKIQADAF4hAA==.Hansi:BAAANQAECgMIAwAAAA==.Harbringer:BAAANQADCgQIBAABNQAECgkJHAAUAP4QAA==.',
He='Heart:BAAANQAECgUIAwABNQAECgkJIwADAIsfAA==.Heid:BAAANQADCgYIDQAAAA==.Helldozer:BAAANQADCgcICQAAAA==.Heytherepal:BAAANQADCgUIBQAAAA==.',
Hi='Higanbana:BAACNQAFFH8hAAIeAAcKiB5xAQCXAQAeAAcKiB5xAQCXAQA1AAQKfzoAAh4ACgpoJPIFAHIDAB4ACgpoJPIFAHIDAAAA.Himawari:BAABNQAECn8gAAIDAAkKIiCTQwDKAgADAAkKIiCTQwDKAgABNQAFFAcIIQAeAIgeAA==.Himejoshi:BAACNQAFFH8XAAIcAAYKPiNOAABwAgAcAAYKPiNOAABwAgA1AAQKf0AAAhwACgrVJi0AAJQDABwACgrVJi0AAJQDAAAA.Hippocampus:BAABNQAECn8nAAIMAAcKgiOxEQDCAgAMAAcKgiOxEQDCAgAAAA==.Hirys:BAABNQAECn8XAAIIAAgKKxNvGwD7AQAIAAgKKxNvGwD7AQAAAA==.',
Ho='Holybeks:BAAANQAECgEIAgABNQAECgoKLQAOACogAA==.Holydaddy:BAAANQAECgYICQAAAA==.Holysmite:BAAANQAECgQIBAABNQAECggICgASAAAAAA==.Hoppadk:BAABNQAECn8tAAIOAAoKKiAlGgDdAgAOAAoKKiAlGgDdAgAAAA==.Hotdoggin:BAAANQADCgEIAQABNQAECgoKIQADAF4hAA==.Hotshotzz:BAAANQAECgMIAwABNQAECggIIwADAF0fAA==.',
Hu='Huntfosho:BAAANQAECgQIBQAAAA==.Huntsmedown:BAAANQADCgYICQAAAA==.',
['Há']='Háldrin:BAACNQAFFH8RAAMZAAUKoxoKCADqAAAZAAQKiRwKCADqAAAFAAEK8BTUHgBgAAA1AAQKfy4AAxkACgpfIsYLAB0DABkACgq1IcYLAB0DAAUAAQo0JnRCAVsAAAAA.',
['Hö']='Hölybeary:BAABNQAECn8XAAMUAAkKqg66SQBvAQAUAAgKXAy6SQBvAQAaAAYK7QcRSwC/AAAAAA==.',
Ia='Iamprepared:BAAANQABCgEIAQAAAA==.',
Ic='Icybacon:BAAANQAECgQIBAAAAA==.Icëcrëam:BAAANQADCggICAAAAA==.',
Ih='Ihavegrass:BAAANQAECgYIEgAAAA==.',
Im='Imbue:BAABNQAECn8sAAIYAAoKgx0QAwBuAgAYAAoKgx0QAwBuAgAAAA==.Imbuer:BAAANQAECgQICAAAAA==.',
In='Innil:BAABNQAECn8dAAICAAoKdiVCAgDHAwACAAoKdiVCAgDHAwAAAA==.Inora:BAAANQABCgMIAwAAAA==.',
It='Itzapazz:BAAANQADCggIDAAAAA==.',
Ja='Jaurel:BAAANQADCgMIAwAAAA==.',
Je='Jessiks:BAAANQAECgIIAgAAAA==.Jessix:BAAANQAECggIEAAAAA==.Jezebel:BAABNQAECn8gAAMEAAoKPxQ6TgBpAgAEAAoKgRI6TgBpAgAgAAEKoRf3awBIAAAAAA==.',
Ji='Jimfowler:BAAANQADCgIIAgAAAA==.Jirito:BAAANQAECgMJAwAAAA==.',
Jo='Jomadead:BAABNQAECn8aAAIOAAcKBBWXJwBdAQAOAAcKBBWXJwBdAQABNQAECgoKGgAMAOgSAA==.Jomas:BAABNQAECn8aAAIMAAoK6BLpVQAQAgAMAAoK6BLpVQAQAgAAAA==.Jovaar:BAAANQADCgYIBgAAAA==.',
Ju='Judera:BAABNQAECn84AAMDAAoKAxrtOAAVAgADAAoKAxrtOAAVAgAaAAEKYRIiSgA1AAAAAA==.',
Ka='Kaing:BAABNQAECn8fAAIXAAYKkA2UFgAyAQAXAAYKkA2UFgAyAQAAAA==.Kaladen:BAABNQAECn8aAAQkAAoKTyIpBwBQAwAkAAoKTyIpBwBQAwALAAEKlhIqrQA8AAAbAAEKvxccXQA7AAAAAA==.Kalec:BAAANQADCgUJBQAAAA==.Kalysti:BAAANQAECggIFwAAAQ==.Kaoticmagus:BAAANQABCgMIAwABNQADCgYIEwASAAAAAA==.Kaoticnature:BAAANQADCgYIEwAAAA==.Karolg:BAABNQAECn8ZAAIOAAcKXRwtHACxAQAOAAcKXRwtHACxAQAAAA==.Katostrafic:BAABNQAECn8qAAMJAAoKmxUwCQDIAQAJAAcKcBUwCQDIAQACAAkKWhSsRwCSAQAAAA==.Katrynna:BAAANQADCgYIEwAAAA==.',
Ke='Kelarra:BAAANQADCgQIBgAAAA==.',
Kh='Khromscarin:BAACNQAFFH8JAAIYAAIKLBlYAgCUAAAYAAIKLBlYAgCUAAA1AAQKfz0AAxgACgpNICACALkCABgACgpNICACALkCAB4ABwrVDdc2AI0BAAAA.',
Ki='Killidan:BAABNQAECn8qAAIeAAoKGhzeEwDJAgAeAAoKGhzeEwDJAgAAAA==.Kirklees:BAAANQAECgQIBwAAAA==.Kitsuchan:BAABNQAECn8fAAQBAAoKriHnSgDsAgABAAkKwyHnSgDsAgAlAAMK2iLtJADHAAAmAAEKAADCBwAAAAABNQAECggIGgAiAC8kAA==.',
Kk='Kkthx:BAAANQADCgcIBwABNQAECgoKPwACABwVAA==.',
Ko='Kodama:BAABNQAECn8mAAIhAAkKUguuTQAkAQAhAAkKUguuTQAkAQAAAA==.Koi:BAAANQADCgcIEgAAAA==.Kookiemon:BAAANQAECgYIBwAAAA==.Kookiesplz:BAAANQADCggICAAAAA==.Kopili:BAAANQADCgUIBwAAAA==.',
Kr='Krekdas:BAAANQADCgUIBQAAAA==.Kromag:BAAANQADCgYIBgAAAA==.',
Ku='Kunpochiken:BAAANQADCgIIAgABNQAECgoKKgAJAJsVAA==.',
Ky='Kyanna:BAAANQAECgUIDgAAAA==.',
La='Lader:BAABNQAFFH8GAAIDAAYKHwCWMgBGAAADAAYKHwCWMgBGAAAAAA==.Ladifantasie:BAAANQADCgUIBQAAAA==.Laria:BAABNQAECn8VAAIeAAgKshWSJQAZAgAeAAgKshWSJQAZAgAAAA==.Laurebeth:BAAANQAECgQIBAAAAA==.Laxinmedium:BAAANQADCgYIDQAAAA==.',
Le='Leenei:BAAANQAECgQIBwAAAA==.Lenlaar:BAAANQAECgUIDgAAAA==.Levande:BAACNQAFFH8HAAICAAMKkg+KFgDOAAACAAMKkg+KFgDOAAA1AAQKfyoAAwIACgrsHFsKADkDAAIACgrsHFsKADkDABEAAgq7DSM3AHAAAAAA.',
Li='Lifeblume:BAAANQADCggIHAAAAA==.Lildevil:BAAANQADCgUIBgAAAA==.Lilithandria:BAAANQAECgcIEQAAAA==.Linamar:BAAANQAECgUICAAAAA==.',
Lo='Loaq:BAABNQAECn8yAAMCAAoK9hPbRgBSAgACAAoK9hPbRgBSAgAJAAMK4giBHACBAAAAAA==.Lockzrockz:BAAANQAECgUIAgAAAA==.Lodshan:BAAANQABCgEIAQAAAA==.Longbottom:BAAANQAECggICQABNQAECgoKIQADAF4hAA==.Loot:BAAANQAECggIEAAAAA==.Lorbert:BAAANQAECgQIBgABNQAECgoKKAAKADMVAA==.Lostalot:BAABNQAECn8uAAIFAAgKvBUGXwBZAgAFAAgKvBUGXwBZAgAAAA==.',
Lu='Luxæterna:BAABNQAECn9BAAIDAAoKDB2aLABLAgADAAoKDB2aLABLAgAAAA==.',
Ly='Lyphiara:BAAANQADCggIGgABNQAECggIMAAPAOYgAA==.',
Ma='Malice:BAABNQAECn8VAAMfAAgKghUnCgDYAQAfAAgKghUnCgDYAQAgAAIKZAUFaQBPAAAAAA==.Mandwandos:BAABNQAECn8bAAQMAAoKIBijdwClAQAMAAgKqBWjdwClAQAhAAkKtQpkjQCCAQATAAEKAADxLgAAAAAAAA==.Maraliss:BAAANQAECgQICQAAAA==.',
Me='Meiri:BAAANQADCgEIAQABNQAFFAMICAAWADESAA==.Melaunis:BAAANQADCgYIDwAAAA==.Meowzer:BAABNQAECn8ZAAQbAAUKaRTgNACMAAALAAUKZxFXbAAZAQAcAAQKtA0BLwCaAAAbAAUKrA/gNACMAAABNQAECgoKPwACABwVAA==.Merginator:BAAANQAECgIIAgAAAA==.Meteora:BAACNQAFFH8IAAIWAAMKMRLsBADEAAAWAAMKMRLsBADEAAA1AAQKfx8AAhYACgoYG3wMAG0CABYACgoYG3wMAG0CAAAA.',
Mi='Mideel:BAAANQAECgUIDgAAAA==.Midesis:BAAANQAECgQIBAAAAA==.Midesisheals:BAAANQAECgIIAgAAAA==.Migolbearcow:BAABNQAECn8yAAIbAAkKpxdEDwBwAgAbAAkKpxdEDwBwAgAAAA==.Missed:BAAANQAECgIJAwAAAA==.Missedweaver:BAAANQADCgYICAABNQAECgIJAwASAAAAAA==.Missrae:BAAANQADCggIFwAAAA==.',
Mk='Mk:BAEANQADCgIIAgABNQAECgkJMAAQAFYeAA==.',
Ml='Mlglock:BAAANQADCgMIAwAAAA==.',
Mo='Moiira:BAAANQAECgEIAQAAAA==.Monyshot:BAAANQADCgUICwAAAA==.Moondizzle:BAAANQAECgIIAgAAAA==.Mooniè:BAAANQAECggIEgAAAA==.Moosenuts:BAABNQAECn8UAAIEAAcKaBBTkgC5AQAEAAcKaBBTkgC5AQAAAA==.Moriavus:BAABNQAECn8qAAIfAAoKxxeyBACLAgAfAAoKxxeyBACLAgAAAA==.Morocha:BAABNQAECn8aAAIPAAcK6Q0JKQArAQAPAAcK6Q0JKQArAQAAAA==.Mortèm:BAAANQAECgIIAgAAAA==.Moxxie:BAAANQABCggIEwABNQADCggIMQASAAAAAA==.',
Mu='Muragore:BAAANQAECgQICQAAAA==.',
My='Mychropien:BAABNQAECn8gAAMNAAkK7h3lIgC6AgANAAkK7h3lIgC6AgAOAAMK+geJjgAhAAAAAA==.Myylus:BAAANQADCgYIFAAAAA==.',
['Mö']='Mökes:BAABNQAECn85AAIgAAoKmSQCAQCbAwAgAAoKmSQCAQCbAwAAAA==.',
Na='Nadroj:BAAANQADCgYIIAAAAA==.Nancydru:BAAANQAECgYIEAAAAA==.Naosu:BAAANQADCgcICAAAAA==.Nax:BAAANQAECgUICwAAAA==.Nazzersaurus:BAABNQAECn8aAAIkAAcKYxnYJQD0AQAkAAcKYxnYJQD0AQAAAA==.',
Ne='Nec:BAAANQAECgEIAQAAAA==.Necrøtic:BAABNQAECn8lAAMlAAkKDRBWDQDcAQAlAAkK4A9WDQDcAQABAAQKqgYijgGqAAAAAA==.Nekomata:BAAANQABCgIIAwAAAA==.Nekosmasta:BAAANQABCgIIAgAAAA==.Neodin:BAAANQAECgUICAAAAA==.Nevermiss:BAABNQAECn8wAAIPAAkKdBdyDQC0AQAPAAkKdBdyDQC0AQAAAA==.',
Ni='Nightjewel:BAAANQADCgYIDQAAAA==.',
No='Notmewasyou:BAABNQAECn8aAAILAAYK2wJihwC1AAALAAYK2wJihwC1AAAAAA==.',
Nu='Nuali:BAABNQAECn8oAAMDAAgKZBrHZABsAgADAAgK+hnHZABsAgAaAAgKBhHiGQAwAQAAAA==.Numi:BAAANQADCggIDQAAAA==.',
Od='Odysseus:BAAANQADCgUICQAAAA==.',
Ok='Okameshiz:BAAANQADCggIDQAAAA==.',
On='Onlyspins:BAAANQAECgYIBwAAAA==.',
Or='Orý:BAABNQAECn8+AAIhAAoKWxsbLADOAgAhAAoKWxsbLADOAgAAAA==.',
Os='Oslatem:BAAANQADCgcICQAAAA==.',
Ox='Oxosorrel:BAAANQABCggIEQAAAA==.',
Oz='Ozzmodious:BAAANQADCgUIEAAAAA==.',
Pa='Pajonn:BAAANQADCgMIAwAAAA==.Paladan:BAABNQAECn8pAAMaAAkKVyBfBwAtAwAaAAkKVyBfBwAtAwADAAMKaR+E1gC5AAAAAA==.Paladanny:BAAANQAECgMIAwAAAA==.Palagi:BAABNQAECn8gAAMcAAYKlgXbHQCSAAAcAAYKlgXbHQCSAAAkAAEKugTsfQAjAAAAAA==.Pallu:BAAANQADCgQIBAAAAA==.Pallyana:BAAANQAECgcIEQAAAA==.Pallyfosho:BAAANQAECgIIAgAAAA==.Pallymcbeall:BAAANQAECgMIBAAAAA==.Paprikaman:BAAANQAECgUIDgAAAA==.Parallax:BAAANQAECgEIAQAAAA==.Pariahrain:BAABNQAECn8YAAMaAAgKbBc8GwAUAgAaAAgKbBc8GwAUAgADAAIKyQKPhwFPAAABNQAFFAMIBgABADUIAA==.Parishealton:BAABNQAECn8hAAMkAAoKWCD0CQAnAwAkAAoKWCD0CQAnAwALAAMKvQFvpgBMAAAAAA==.Payday:BAAANQADCgYICwAAAA==.Pazzuzu:BAAANQADCgcICwAAAA==.',
Pe='Penjamin:BAAANQAECgMIAwABNQAECgoKIQADAF4hAA==.Perprotrus:BAAANQADCgQIBAABNQAFFAQIBgAOAAkKAA==.',
Ph='Phatboi:BAAANQAECgMIAwAAAA==.',
Po='Poulsbo:BAAANQAECgQIBAAAAA==.Pozole:BAAANQAECgcIDQAAAA==.',
Pr='Prominence:BAABNQAECn8gAAIGAAoKNR52AQCsAgAGAAoKNR52AQCsAgAAAA==.Promisques:BAAANQAECgEIAQAAAA==.Protectapear:BAAANQABCgEIAQAAAA==.Prozak:BAABNQAECn8oAAIMAAkKXBRSYgDnAQAMAAkKXBRSYgDnAQAAAA==.',
Pw='Pwomf:BAAANQAECggIEAAAAA==.',
Py='Pyneapple:BAAANQADCgQIBAABNQAECgoKPwACABwVAA==.Pyrolily:BAAANQAECgYIEgAAAA==.',
Qu='Question:BAAANQADCgIIAwAAAA==.Qulung:BAAANQADCggIFAAAAA==.',
Ra='Rabyd:BAAANQAECgEIAQAAAA==.Raegasm:BAAANQADCgYICwAAAA==.Raght:BAAANQAECgIIAgAAAA==.Raha:BAAANQAECgMIBQAAAA==.Ramue:BAAANQADCgcIDgAAAA==.Raskela:BAABNQAECn8cAAMPAAkKpxO3GADyAQAPAAkKpxO3GADyAQAQAAcKdhQrMQCOAQAAAA==.Rastakan:BAAANQAECgUICQABNQAECgoKPQAKAOshAA==.Razal:BAAANQADCggIDQAAAA==.',
Re='Reesespiecez:BAAANQAECgcJCwAAAA==.Rellidana:BAAANQAECgYICgAAAA==.Remove:BAAANQAECgUIBQAAAA==.Reprieve:BAAANQAECgUICQAAAA==.Retradormi:BAAANQAECgEIAQAAAA==.Rexi:BAABNQAECn8hAAIRAAkKCg6VJwDuAQARAAkKCg6VJwDuAQAAAA==.',
Ri='Rickcando:BAAANQAECgUIDgAAAA==.Ricshard:BAABNQAECn8pAAMgAAcKyhUrFAB3AAAEAAUK1RTjegABAQAgAAMKtBcrFAB3AAAAAA==.Ridjeckgron:BAAANQADCgcICQAAAA==.Rissiia:BAAANQADCgQIBAAAAA==.',
Rm='Rmft:BAAANQADCgYIHgABNQAECgkJLAAKAIkWAA==.',
Ro='Roomnboard:BAAANQAECgMIAwAAAA==.Rotter:BAAANQADCgQIBAAAAA==.Roughluver:BAAANQAECgMIAgABNQAECgoKPwACABwVAA==.',
Ru='Ruben:BAAANQADCgEIAgAAAA==.Rungar:BAAANQAECgQICwAAAA==.',
Rv='Rvoker:BAAANQADCgQIBAAAAA==.',
Ry='Rylia:BAAANQADCgcICQAAAA==.Ryuk:BAAANQADCgMIAwAAAA==.Ryñ:BAAANQAECggIDAAAAA==.',
['Rà']='Ràein:BAABNQAECn8qAAMgAAcKMA9UBwADAQAgAAcKMA9UBwADAQAEAAEK0QKv9QAfAAAAAA==.',
['Ró']='Ród:BAABNQAECn8jAAIDAAgKXR9IbwBRAgADAAgKXR9IbwBRAgAAAA==.',
['Rø']='Røth:BAAANQADCgcIEgAAAA==.',
Sa='Saalira:BAAANQADCgcIEAAAAA==.Sabellice:BAABNQAECn8sAAIDAAgKxg1+gQBOAQADAAgKxg1+gQBOAQAAAA==.Sakonna:BAABNQAECn8fAAIRAAkKQRV8IAA1AgARAAkKQRV8IAA1AgAAAA==.Salinoria:BAAANQAECgQICQABNQAECggIKAADAGQaAA==.Saltyfingers:BAAANQADCgcIBwAAAA==.Sandymaw:BAAANQADCgQIBAABNQAECgoKPwACABwVAA==.Sarlius:BAABNQAECn86AAIFAAoKQyXpAgDYAwAFAAoKQyXpAgDYAwAAAA==.Sassybuns:BAAANQABCgQIBAAAAA==.Satyrical:BAABNQAECn8jAAIDAAkKix/OKABeAgADAAkKix/OKABeAgAAAA==.Savin:BAAANQAECgQIBwAAAA==.',
Sc='Scavenger:BAAANQAECgUIDQAAAA==.Scorchin:BAAANQAECggIAgAAAA==.Scrumptiøus:BAAANQAECgQICAABNQAECgoKKgAJAJsVAA==.',
Se='Selkamonk:BAABNQAECn8wAAMPAAgK5iD0CgDXAgAPAAgK5iD0CgDXAgAQAAIKDgamSwAsAAAAAA==.Seniorbold:BAABNQAECn8cAAIDAAoK9BezQgDMAgADAAoK9BezQgDMAgAAAA==.Sentrina:BAACNQAFFH8HAAIjAAQKIg76DACPAAAjAAQKIg76DACPAAA1AAQKfy8AAiMACgqJGigNANMCACMACgqJGigNANMCAAAA.Seraph:BAAANQAECggICAAAAA==.Seshy:BAABNQAECn8/AAMCAAoKHBXQTQA7AgACAAoKHBXQTQA7AgARAAkK9RcmIAA5AgAAAA==.Seshymutedme:BAAANQAECggIEQABNQAECgoKPwACABwVAA==.',
Sh='Shamanagins:BAAANQADCgEIAQAAAA==.Shannon:BAAANQADCgYIBgABNQAECgcIGAAUAHYPAA==.Shannoon:BAABNQAECn8ZAAIaAAcK9QjLJwDGAAAaAAcK9QjLJwDGAAAAAA==.Sharr:BAAANQADCgYJDAAAAA==.Shekzeer:BAABNQAECn8rAAQQAAoKjSXlAADnAwAQAAoKjSXlAADnAwAPAAYK0hzxGgDSAQAnAAMK8yALIwC/AAAAAA==.Shiverr:BAABNQAECn8hAAIlAAcKMQcmGQAtAQAlAAcKMQcmGQAtAQAAAA==.Shockakan:BAAANQABCgQIBAAAAA==.Shockazulu:BAAANQADCgIIAgAAAA==.Shocktard:BAAANQAECgEIAQABNQAECgkJHQAKABkUAA==.',
Si='Siatraz:BAAANQAECgEIAQABNQAECgoKHgAgAPcSAA==.Siegatrox:BAAANQAECgIIAgAAAA==.Silgan:BAAANQADCgYIBgAAAA==.Silverbain:BAAANQADCgQIBAAAAA==.',
Sk='Skizem:BAAANQABCgcIEQAAAA==.Skott:BAAANQADCggIMQAAAA==.Skïnnyßetch:BAAANQADCgcIBwAAAA==.',
Sl='Sleepadin:BAAANQAFFAIIAwAAAA==.Sleepyr:BAAANQAECgYIDQAAAA==.',
Sm='Smokeymage:BAAANQAECgMIAwAAAA==.',
Sn='Snowi:BAAANQADCgYIBgABNQAECggIDgASAAAAAA==.Snowstorm:BAAANQAECgEIAQAAAA==.',
So='Soakra:BAABNQAECn8iAAIMAAkK7xbaRABOAgAMAAkK7xbaRABOAgAAAA==.Solignis:BAACNQAFFH8oAAMXAAcKTSYKAAApAgAXAAcKTSYKAAApAgAKAAQK6R5WFACIAQA1AAQKf0gAAxcACgrkJgUAAB4EABcACgrkJgUAAB4EAAoACQp/Ju8HALMDAAAA.Solxeen:BAAANQADCggICAAAAA==.Soniviolence:BAABNQAECn8xAAIKAAoK0CBoGwBKAwAKAAoK0CBoGwBKAwAAAA==.Soohots:BAABNQAECn8eAAMkAAkK4B2JFAClAgAkAAgK3RyJFAClAgALAAQKLxDsjQCfAAAAAA==.Sourskittlz:BAAANQADCgQIBAAAAA==.',
Sp='Sparklehappy:BAABNQAECn8WAAMZAAYKrxl9OgB8AQAZAAUKihl9OgB8AQAFAAEKQRoJRgFTAAAAAA==.Splìff:BAAANQADCgYIBgAAAA==.Sppazz:BAAANQADCgcIBwAAAA==.',
St='Starshield:BAAANQAECgIIAgABNQAECgkJGAANAHYWAA==.Stausa:BAAANQADCgcIBwAAAA==.Steeljustice:BAAANQAECggICAAAAA==.Stormcreek:BAABNQAECn8fAAMMAAcKphYfTABlAQAMAAcKphYfTABlAQAhAAIKnQJlzgApAAAAAA==.Storri:BAABNQAECn9HAAMCAAoK1xmfFADBAgACAAoK1xmfFADBAgARAAUKwgYbVAC9AAAAAA==.',
Su='Sufferinhero:BAAANQAECgEIAQABNQAFFAIICQAYACwZAA==.Suzuya:BAAANQAECgEIAQAAAA==.',
Sv='Svetty:BAAANQADCggICAAAAA==.',
Sw='Swiftly:BAAANQAECggIDwAAAA==.Swiftmage:BAACNQAFFH8oAAMlAAcKhiUVAAAaAgAlAAcKhiUVAAAaAgABAAUKvR0cGgCpAQA1AAQKf0UAAyUACgrgJg8AAAcEACUACgrgJg8AAAcEAAEACQoqJeMYAHEDAAAA.Switchboard:BAAANQADCgYICgAAAA==.',
Sx='Sxkittn:BAAANQADCgQIBAAAAA==.',
Sy='Sygh:BAAANQAECgEIAQABNQAECgkJIwADAIsfAA==.Syltru:BAAANQADCgUIBQAAAA==.Syndragonkin:BAABNQAECn8sAAIFAAgKcBcdXgCEAQAFAAgKcBcdXgCEAQAAAA==.Syndrome:BAAANQADCggIDgAAAA==.Synger:BAAANQADCgYIEAAAAA==.',
Ta='Taima:BAAANQABCgEIAQAAAA==.Talyndis:BAACNQAFFH8eAAIZAAgKWR27AgB4AgAZAAgKWR27AgB4AgA1AAQKfzcAAhkACgovJcUBAC8DABkACgovJcUBAC8DAAAA.Tamyr:BAAANQADCgIIAgAAAA==.Tazadar:BAAANQADCggIGQAAAA==.Taze:BAAANQAECgUJBwABNQAFFAQIBgAOAAkKAA==.Tazjiingo:BAAANQADCgIIBAAAAA==.',
Te='Ted:BAAANQADCggIEAAAAA==.Terrika:BAABNQAECn8hAAIFAAgKwQrxigD0AQAFAAgKwQrxigD0AQAAAA==.Tetshajeh:BAACNQAFFH8JAAIKAAIKbRdfGQCVAAAKAAIKbRdfGQCVAAA1AAQKf0wAAwoACgp/IZMYAFYDAAoACgp/IZMYAFYDABYAAwrQGOIrANkAAAAA.Teyliana:BAAANQAECgUIDgAAAA==.',
Th='Thebigchud:BAAANQAECgUIBwAAAA==.Thillarick:BAABNQAECn8sAAIKAAkKiRYOQgDGAQAKAAkKiRYOQgDGAQAAAA==.Thiss:BAAANQABCgYIAwAAAA==.Thromanor:BAAANQAECgUIBAAAAA==.Thwip:BAABNQAECn83AAMZAAoKRCFjCwAjAgAFAAoKRCGaLADoAgAZAAkK1RRjCwAjAgAAAA==.',
Ti='Tikwid:BAABNQAECn8lAAIBAAgKhwXdpgD5AAABAAgKhwXdpgD5AAAAAA==.Tiranmyashol:BAABNQAECn8oAAIKAAoKMxXcaABVAgAKAAoKMxXcaABVAgAAAA==.',
To='Tomoya:BAAANQAECgcIEgAAAA==.Too:BAAANQAECgIIAQAAAA==.Toothdk:BAAANQAECgUIDgAAAA==.Torfnar:BAAANQAECgcIBwAAAA==.Tormmentor:BAAANQAECgQICQAAAA==.',
Tr='Treebreak:BAAANQAECgUIDwAAAA==.',
Ty='Tyrandrea:BAAANQADCgcICQAAAA==.',
Ud='Udari:BAAANQAECgcICgAAAA==.Udarii:BAAANQAECgMIAwAAAA==.',
Um='Umàdbrah:BAABNQAECn8rAAIFAAgKpCAfJABUAgAFAAgKpCAfJABUAgAAAA==.',
Un='Unbelievable:BAABNQAECn8gAAIiAAkKawlnKABVAQAiAAkKawlnKABVAQAAAA==.Unprovoked:BAABNQAECn8iAAIBAAkKwh5dVwDRAgABAAkKwh5dVwDRAgAAAA==.',
Va='Valamor:BAABNQAECn8pAAMaAAcKZhEVGgAuAQAaAAcKZhEVGgAuAQAUAAUK4Ae1zQDgAAAAAA==.Varenea:BAAANQADCgYIBgAAAA==.Varia:BAAANQAECgEIAQABNQAECgkJHQAKABkUAA==.',
Ve='Veefib:BAABNQAECn8rAAMhAAkKxBjjQAByAgAhAAkKxBjjQAByAgAMAAIKpwqCqgBkAAAAAA==.Velicerus:BAAANQAECgEIAQAAAA==.Velvettwitch:BAABNQAECn8qAAIgAAkKrQ/MBABPAQAgAAkKrQ/MBABPAQAAAA==.Vendler:BAAANQAECgcIEQAAAA==.Verahla:BAAANQADCgYIHwAAAA==.Vermis:BAABNQAECn8tAAIdAAgKoBDoOQAzAQAdAAgKoBDoOQAzAQAAAA==.Veryaverage:BAABNQAECn8ZAAMBAAcKaBGIawBwAQABAAcKaBGIawBwAQAmAAMKaAnkAwCgAAAAAA==.Vexation:BAAANQAECgQIBQAAAA==.',
Vi='Vicarious:BAABNQAECn8jAAIMAAoKARzmIAA+AgAMAAoKARzmIAA+AgAAAA==.Vidreaux:BAABNQAECn8xAAMBAAkKKgw08ACqAQABAAgKUAw08ACqAQAlAAIKDwu2IQBmAAAAAA==.Villaraa:BAAANQADCgEIAQAAAA==.Vivid:BAAANQADCggICwAAAA==.',
Vo='Voidofvoids:BAAANQAECgUIBQAAAA==.Volke:BAAANQAECgUICQAAAA==.Volkennoria:BAAANQADCgcIBwABNQAECggIKQAFADobAA==.Votingromney:BAAANQAECgcICgABNQAECgoKKwAQAI0lAA==.Vowz:BAAANQADCgMIAwAAAA==.',
Vu='Vulpe:BAABNQAECn8pAAIFAAgKOht1XABgAgAFAAgKOht1XABgAgAAAA==.',
Vy='Vyolenta:BAAANQADCgIIAgAAAA==.',
['Vë']='Vëxhunter:BAAANQAECggICgAAAA==.',
Wa='Waldorf:BAAANQAECgUICAAAAA==.Wallegator:BAAANQAECgEIAQABNQAECgcIJwAkAIMgAA==.Walleroot:BAAANQAECgUIBQABNQAECgcIJwAkAIMgAA==.',
We='Weinersoup:BAAANQAECgQIDAAAAA==.',
Wh='Whitewhitch:BAAANQADCgIIAwAAAA==.Whosethetank:BAAANQAECgMIBwAAAA==.',
Wo='Wolfpup:BAAANQAECggICQABNQAECgoKOAADAAMaAA==.Wolfíe:BAAANQADCgUIBQAAAA==.Worstelf:BAABNQAECn8fAAMCAAgKPBoYQABqAgACAAgKPBoYQABqAgARAAYKgiIAIgAlAgAAAA==.',
Ww='Wwalle:BAAANQADCgQIBQABNQAECgcIJwAkAIMgAA==.',
Xa='Xanathos:BAAANQAECgYIBgABNQAECgoKOgAFAEMlAA==.',
Xi='Xilstar:BAAANQADCgUIBQAAAA==.',
Xz='Xzavier:BAAANQADCgYIDQAAAA==.',
Yf='Yfelshammy:BAABNQAECn8wAAIMAAoKsBQMTAAzAgAMAAoKsBQMTAAzAgAAAA==.',
Yv='Yvaldi:BAAANQAECgYIBgABNQAFFAIICAACANciAA==.Yvonnél:BAAANQAECgEIAQABNQAECgcIEQASAAAAAA==.',
Za='Zaknafein:BAAANQAECgUICQAAAA==.Zanebusby:BAABNQAECn8tAAIgAAoKsx4MAQBvAgAgAAoKsx4MAQBvAgAAAA==.Zankru:BAAANQADCgYIBwAAAA==.Zaraë:BAAANQADCggIDgAAAA==.Zaria:BAAANQAECgcIDgABNQAECgoKKwAQAI0lAA==.Zartash:BAABNQAECn8UAAIeAAgK3ANQLgC2AAAeAAgK3ANQLgC2AAAAAA==.Zatharis:BAAANQAECgQIDQAAAA==.',
Ze='Zelik:BAAANQAECgYIBwABNQAECgoKOgAFAEMlAA==.Zenezin:BAAANQAECgMIAwABNQAECgkJHQAKABkUAA==.Zerax:BAAANQAECgYIDAABNQAECgoKPQAKAOshAA==.Zevellian:BAAANQADCggIDgABNQAECgcIEQASAAAAAA==.',
Zm='Zmona:BAABNQAECn8dAAIKAAkKGRSjhQAOAgAKAAkKGRSjhQAOAgAAAA==.',
Zo='Zolrath:BAAANQABCgQIAgAAAA==.',
['Ãm']='Ãmpstar:BAAANQADCgMIAwAAAA==.',
['Äm']='Ämpstarr:BAAANQADCgEIAQAAAA==.',
['Çy']='Çyanide:BAAANQADCgQICgABNQAECgkJIwADAIsfAA==.',
['Ðr']='Ðragonshaft:BAABNQAECn8xAAIFAAkK9hSvbAA5AgAFAAkK9hSvbAA5AgAAAA==.Ðreadlokz:BAAANQADCgQIBAAAAA==.',
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
