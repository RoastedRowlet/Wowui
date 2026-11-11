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

local lookup = {'Mage-Arcane','Priest-Holy','Paladin-Retribution','Warlock-Demonology','Hunter-BeastMastery','Hunter-Survival','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','DeathKnight-Frost','DeathKnight-Unholy','Druid-Balance','Shaman-Restoration','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','Priest-Shadow','Unknown-Unknown','Shaman-Enhancement','Shaman-Elemental','DemonHunter-Havoc','Paladin-Holy','Warrior-Arms','Evoker-Devastation','Warrior-Protection','Warrior-Fury','DemonHunter-Vengeance','Hunter-Marksmanship','Paladin-Protection','Druid-Guardian','Druid-Feral','DemonHunter-Devourer','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Druid-Restoration','Mage-Frost','Mage-Fire','Monk-Brewmaster',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aarazi:BAABNQAECn8+AAIBAAoKnxyMRQD4AgABAAoKnxyMRQD4AgAAAA==.',
Ab='Abbinormal:BAAANQADCggIHgAAAA==.Abolish:BAAANQABCgIIAgAAAA==.',
Ad='Adïrael:BAAANQABCggIFQAAAA==.',
Ae='Aeriss:BAAANQADCggIDgAAAA==.Aethena:BAAANQADCgUIBQABNQAECgcILwACAEsVAA==.Aezili:BAAANQADCgcIDQAAAA==.',
Ag='Agamotto:BAAANQADCgMIAwAAAA==.Agerol:BAABNQAECn80AAIDAAkKSx8hRgBIAgADAAkKSx8hRgBIAgAAAA==.',
Ah='Ahaego:BAABNQAECn8eAAIEAAgK4Q6LdQBmAQAEAAgK4Q6LdQBmAQAAAA==.Ahnari:BAAANQAECgIIAgAAAA==.',
Ak='Akkadien:BAAANQAECgcIEQAAAA==.Akumunter:BAABNQAECn88AAMFAAoKEhtHKwDsAgAFAAoKEhtHKwDsAgAGAAcKGwwnCQA9AQAAAA==.',
Al='Alacardias:BAABNQAECn8yAAIDAAoK8xu9RADGAgADAAoK8xu9RADGAgAAAA==.Alette:BAAANQAECgMIAwAAAA==.Alihuntress:BAAANQADCgQIBQAAAA==.Alleril:BAABNQAECn8kAAMHAAoKkRIbDQDrAQAHAAkKmRAbDQDrAQAIAAkKbQ+vVQCRAQAAAA==.Allthesnacks:BAAANQAECggIEgAAAA==.Aloe:BAAANQADCgYICQAAAA==.',
Am='Amarynth:BAAANQADCgQIBAAAAA==.Amäri:BAACNQAFFH8IAAICAAIK1yIFIwDIAAACAAIK1yIFIwDIAAA1AAQKfxoAAwIACAoiJGYhAOkCAAIACAoQJGYhAOkCAAkABArUGMEQAB0BAAAA.',
An='Anassand:BAABNQAECn8fAAMKAAkKkx19FwCAAgAKAAkKFxt9FwCAAgALAAYKBBl+WgCmAQAAAA==.Anatomic:BAAANQADCgIIAgABNQAECgcILwACAEsVAA==.Andicandy:BAAANQAECgcIEQABNQAECgkJJAAMAK4XAA==.Andimorph:BAABNQAECn8kAAIMAAkKrhcvMQBYAgAMAAkKrhcvMQBYAgAAAA==.Angeleria:BAAANQADCgUIBQAAAA==.',
Ap='Apazz:BAABNQAECn8+AAIFAAoKcRWCRgAxAgAFAAoKcRWCRgAxAgAAAA==.',
Aq='Aqualight:BAAANQAECgcIEwABNQAECgoKNQANAGgkAA==.Aquashade:BAAANQAECgUIBgABNQAECgoKNQANAGgkAA==.Aquaterra:BAABNQAECn81AAINAAoKaCSuDQBTAwANAAoKaCSuDQBTAwAAAA==.Aquina:BAAANQAECgcIEAABNQAECgoKNQANAGgkAA==.',
Ar='Arakadia:BAABNQAECn9RAAMLAAoKdhZRJQCiAQALAAoKlBNRJQCiAQAOAAMKxRrUggBcAAAAAA==.Arcaina:BAAANQAECgQICwAAAA==.Artoriaz:BAAANQADCgcJCwAAAA==.Aruteeru:BAABNQAECn8nAAMPAAkKpRhXGAD5AQAPAAkKpRhXGAD5AQAQAAgKIhMZLwCeAQAAAA==.',
As='Aseanna:BAABNQAECn8iAAMRAAkKsBJgGgCxAQARAAkKsBJgGgCxAQACAAIKHw862ABbAAAAAA==.Astraen:BAAANQADCgQIBgAAAA==.',
At='Athira:BAAANQAECgEIAQAAAA==.',
Au='Augmentussy:BAAANQADCggICAABNQAECgoKKwAQAI0lAA==.Auxiliater:BAAANQADCgEIAQAAAA==.Auxiliator:BAAANQADCgYIBgAAAA==.Auxlox:BAAANQADCgcIBwAAAA==.Auxshadow:BAAANQABCgIIAgABNQADCgYIBgASAAAAAA==.',
Av='Avarous:BAABNQAECn89AAMCAAoK1RmQHwDOAgACAAoK1RmQHwDOAgARAAEKAABvigAgAAAAAA==.Avataroffury:BAAANQAECgQIBAABNQAECgkJHwAKAJMdAA==.',
Ax='Axará:BAAANQADCgQIBAAAAA==.Axel:BAAANQADCgUIBwAAAA==.',
Ay='Ayala:BAACNQAFFH8OAAIDAAUKLh0cEgAvAQADAAUKLh0cEgAvAQA1AAQKfycAAgMACgoeJUsHAFwDAAMACgoeJUsHAFwDAAAA.',
Az='Azaireos:BAAANQADCggIDwAAAA==.Azulpunkt:BAABNQAECn8lAAITAAoK/he1EAD1AQATAAoK/he1EAD1AQAAAA==.',
Ba='Baddaboomkin:BAAANQADCgEIAQAAAA==.Bananashamma:BAABNQAECn8cAAMNAAoKgh6mOAB8AgANAAoKgh6mOAB8AgAUAAYK3A3zswArAQAAAA==.Barbedwire:BAAANQAECggIDAAAAA==.',
Be='Bearmao:BAABNQAECn9MAAIFAAoKWCG1GQDRAgAFAAoKWCG1GQDRAgAAAA==.Belfas:BAAANQAECgQIBQAAAA==.Belladon:BAAANQAECgUICQABNQAECgkJFAAVABQZAA==.Bellah:BAAANQABCgIIAgAAAA==.Bellybutton:BAABNQAECn8UAAITAAcKSwqpIQD4AAATAAcKSwqpIQD4AAAAAA==.',
Bi='Bigpeach:BAAANQADCgEIAQAAAA==.Biltong:BAABNQAECn8iAAIWAAkK8xTfPAARAgAWAAkK8xTfPAARAgAAAA==.',
Bl='Blackpink:BAAANQADCgUIBQAAAA==.Bladesinger:BAAANQADCgYIBgAAAA==.Bludnite:BAACNQAFFH8GAAIOAAQKCQqZGACYAAAOAAQKCQqZGACYAAA1AAQKfyoABA4ACQq/GpUuAFkCAA4ACApGHZUuAFkCAAsAAQoQCfqDADQAAAoAAQpkAx+2ACMAAAAA.',
Bo='Bokchoi:BAAANQAECgUIBQAAAA==.Boom:BAAANQADCgQICAAAAA==.',
Br='Brey:BAAANQAECgcICwAAAA==.Bruute:BAABNQAECn9FAAIXAAoKOyPQFQBiAwAXAAoKOyPQFQBiAwAAAA==.',
Bu='Budplatinum:BAABNQAECn8fAAIYAAcKHgXuFQDFAAAYAAcKHgXuFQDFAAAAAA==.',
['Bâ']='Bâït:BAAANQAECggIBwAAAA==.',
['Bå']='Båcon:BAAANQAECgEIAQAAAA==.',
Ca='Cairo:BAABNQAECn8nAAMZAAkK9iC5CwB+AgAXAAkKPxxiVACNAgAZAAcKFiO5CwB+AgAAAA==.Calai:BAAANQADCggICAAAAA==.Capitalchaos:BAABNQAECn8/AAMaAAkKthaGCwAKAgAaAAkKthaGCwAKAgAXAAEKDgYZVgEwAAABNQAECgoKNwABAFQSAA==.Capnbeni:BAAANQADCgMIAwAAAA==.Cassandraa:BAAANQADCgQIBwAAAA==.Castingchaos:BAABNQAECn83AAIBAAoKVBLHpgA0AgABAAoKVBLHpgA0AgAAAA==.',
Ce='Cell:BAABNQAECn81AAIbAAoKiSJvAgBdAwAbAAoKiSJvAgBdAwAAAA==.Ceviche:BAABNQAECn8WAAIQAAkKWB8iEQA5AgAQAAkKWB8iEQA5AgAAAA==.Ceàrrdòrn:BAABNQAECn8oAAIDAAgKFBXfyACKAQADAAgKFBXfyACKAQAAAA==.',
Ch='Chibí:BAAANQADCggIFgABNQAECggIEAASAAAAAA==.Chillzmatic:BAAANQAECgIIBwAAAA==.Chirri:BAAANQADCgcICwAAAA==.Chudbucket:BAABNQAECn8gAAMFAAgKyBq/jQDuAQAFAAcKbh2/jQDuAQAcAAMKJQ6MZwCOAAAAAA==.',
Ci='Cica:BAAANQAECgMIAwAAAA==.Cirillø:BAAANQAECgYICwABNQAECgoKRAAdAMMlAA==.',
Cl='Clobbopus:BAAANQAECgEIAQAAAA==.Clovergold:BAACNQAFFH8KAAIDAAQKoQwjFwDFAAADAAQKoQwjFwDFAAA1AAQKfygAAgMACgozGjtPAKcCAAMACgozGjtPAKcCAAAA.Cluladin:BAAANQAECgMIAwABNQAECgoKLgAQAGcdAA==.Clyde:BAABNQAECn8bAAMeAAcKgQyLMQASAQAeAAcKgQyLMQASAQAfAAMKMgSZNgBmAAAAAA==.',
Co='Confearacy:BAAANQAECggICQAAAA==.Corbis:BAABNQAECn8WAAMLAAcKSQ12gAAbAQALAAYKIw52gAAbAQAKAAUK/AavdgDIAAAAAA==.Cowpuss:BAAANQAECgEIAQABNQAECgkJFAAVABQZAA==.',
Cr='Creekdeath:BAAANQAECggIDAAAAA==.Crevarus:BAAANQADCgUJDAAAAA==.Crimsonjeybi:BAAANQAECgcICAAAAA==.Cruesify:BAAANQAECgQIBAABNQAECgoKLAAJAJsVAA==.Crunchwich:BAAANQAECgUIDwAAAA==.Cryos:BAAANQAECgIIAQAAAA==.',
Cu='Cutename:BAAANQAECgQIBAAAAA==.',
Cy='Cy:BAAANQAECgUIBQABNQAECgoKJgADAAYjAA==.Cynamyn:BAABNQAECn8YAAICAAYKgwbJtACzAAACAAYKgwbJtACzAAAAAA==.',
Cz='Czeskilight:BAAANQADCgIIAgAAAA==.',
['Cö']='Cömet:BAAANQADCgcICAAAAA==.',
Da='Daane:BAAANQADCggIDwAAAA==.Dabadwarrior:BAAANQAECgUIBQAAAA==.Daevarys:BAAANQAECgEIAQAAAA==.Dakhran:BAAANQADCgIIBAAAAA==.Dakkä:BAAANQADCggIBwAAAA==.Dan:BAABNQAECn88AAIKAAoK0BplHQCfAgAKAAoK0BplHQCfAgAAAA==.Danthrax:BAABNQAECn8gAAIaAAoK7RnNBgA8AgAaAAoK7RnNBgA8AgAAAA==.Darkdemon:BAABNQAECn8wAAIgAAgKwwsaKQA6AQAgAAgKwwsaKQA6AQAAAA==.Darlord:BAAANQAECgUICwAAAA==.Dawnliht:BAAANQADCgIIAgAAAA==.',
De='Deagle:BAAANQABCgIIBAABNQAECgoKKwAQAI0lAA==.Deandrya:BAABNQAECn8YAAMIAAoKIAbybQA/AQAIAAoKIAbybQA/AQAHAAEKQAL6rwAZAAAAAA==.Deedubbya:BAAANQADCgcIBwAAAA==.Delryd:BAAANQAECgYIDwAAAA==.Demonetized:BAAANQAECgQIBAAAAA==.Demônlock:BAABNQAECn8XAAMEAAgKbhcOZQCTAQAEAAgKZBYOZQCTAQAhAAEKcxd0bABHAAAAAA==.Desideria:BAABNQAECn86AAMiAAoKqgwwCQCrAQAiAAoKqgwwCQCrAQAEAAIK0gcuLAFlAAAAAA==.Despondence:BAACNQAFFH8HAAIgAAMKmhR0DQDUAAAgAAMKmhR0DQDUAAA1AAQKf00AAyAACgoKIRsHAGADACAACgoKIRsHAGADABsAAgq/GEcoAEcAAAAA.Desynn:BAAANQAECgYJDgAAAA==.',
Di='Divinesyn:BAABNQAECn8VAAICAAkKmQejdQBhAQACAAkKmQejdQBhAQAAAA==.Divonah:BAAANQADCgQIBAAAAA==.',
Dj='Djelysium:BAAANQAECgQIBwAAAA==.Djtaki:BAABNQAECn9BAAMHAAoK/htDGAC6AgAHAAoK/htDGAC6AgAIAAUKgwryngCnAAAAAA==.',
Do='Dogwater:BAAANQADCgYIBgABNQAFFAcIGQAfAM8fAA==.Doncarlos:BAACNQAFFH8MAAIFAAMKAQbgFgDKAAAFAAMKAQbgFgDKAAA1AAQKf1UAAgUACgrHH8MUAEsDAAUACgrHH8MUAEsDAAAA.Dorn:BAAANQAECgEIAQAAAA==.Dotty:BAAANQAECgEIAQAAAA==.Dottzz:BAAANQADCgYIBgAAAA==.Downbeatxo:BAECNQAFFH8ZAAMhAAcKURRRAwDgAAAEAAUKhBqIDgCQAQAhAAMKOhBRAwDgAAA1AAQKfzsABAQACgpdI7wOAO4CAAQACgpdI7wOAO4CACEABAomGmAtABcBACIAAQpTGJQlAEgAAAAA.',
Dr='Dragonswòrd:BAAANQADCggIDwAAAA==.Drdevoted:BAAANQADCgIIAgAAAA==.Drippie:BAAANQADCgcIGQAAAA==.Dròòid:BAAANQADCgQJBAABNQAFFAQIBgAOAAkKAA==.',
Du='Dubdred:BAAANQAECgIIAgAAAA==.Duhon:BAAANQADCgQIBAAAAA==.Dumptruck:BAAANQAECggIEQABNQAECgoKJgADAAYjAA==.',
Dw='Dwín:BAABNQAECn8dAAIFAAoKQgabtACbAQAFAAoKQgabtACbAQAAAA==.',
['Dê']='Dêals:BAABNQAECn8hAAIWAAgKOxqTRwBIAgAWAAgKOxqTRwBIAgAAAA==.',
['Dü']='Dümpy:BAAANQADCgMIAwAAAA==.',
Ed='Edgelordxx:BAAANQAECgIIBQAAAA==.',
Ee='Eev:BAAANQADCgIIAgAAAA==.',
El='Elasper:BAAANQAECgEIAQAAAA==.Eliselyia:BAAANQAECgEIAgAAAA==.Ellierose:BAABNQAECn8eAAICAAoKHwiReQBVAQACAAoKHwiReQBVAQAAAA==.',
Em='Emelianas:BAAANQAFFAEIAQABNQAECgoKUQALAHYWAA==.Ems:BAAANQAECgIIAgAAAA==.',
En='Enaelna:BAAANQAECgEIAQAAAA==.Enjin:BAABNQAECn9MAAMFAAoKNSTmCAA9AwAFAAoKNSTmCAA9AwAGAAMK/RyJDgC7AAAAAA==.Enragedbeef:BAAANQAECgUIBQABNQAFFAQIBwACAO8JAA==.Entheogen:BAABNQAECn8sAAMUAAgKVhAMTwCFAQAUAAgKVhAMTwCFAQANAAQK7hPkxwDYAAAAAA==.',
Eo='Eogan:BAAANQADCgIIAwAAAA==.',
Ep='Epichuntard:BAAANQAECgQICQAAAA==.',
Er='Erolas:BAAANQADCgQIBwAAAA==.',
Es='Essay:BAABNQAECn8nAAIFAAoKtxtlQwA6AgAFAAoKtxtlQwA6AgAAAA==.',
Et='Ethereall:BAABNQAECn8XAAMgAAkKxRisHABwAgAgAAkKxRisHABwAgAVAAMKOQH4kQA3AAAAAA==.',
Eu='Eudora:BAAANQADCggICAABNQAECgoKKwAQAI0lAA==.',
Ev='Evalilly:BAAANQADCgYIBgAAAA==.Evanessance:BAAANQADCgYIBwAAAA==.Evilice:BAABNQAECn88AAIDAAkK/xE/igCjAQADAAkK/xE/igCjAQAAAA==.Evoka:BAABNQAECn8eAAIjAAgKbg63FACRAQAjAAgKbg63FACRAQAAAA==.',
Fa='Faavibear:BAAANQAECggIAQAAAA==.Fallendevout:BAAANQAECgUICAAAAA==.Fallenhero:BAAANQAECgYIBgAAAA==.Fallentroll:BAABNQAECn8dAAMLAAkKmhlKPQAqAgALAAkKKBlKPQAqAgAOAAMK7Rw8jADQAAAAAA==.Fatdoinkers:BAABNQAECn8mAAQDAAoKBiOKMQCPAgADAAoKBiOKMQCPAgAWAAIKowwQzABsAAAdAAIKjhmNZwBFAAAAAA==.Fatman:BAAANQADCgcICAABNQADCgIIAwASAAAAAA==.Faydark:BAAANQADCgQIBAAAAA==.Fayia:BAAANQADCggIDgAAAA==.Fayye:BAABNQAECn8hAAIWAAcK9RBVYgB+AQAWAAcK9RBVYgB+AQAAAA==.',
Fe='Felbeks:BAAANQAECgQIBAABNQAECgoKNAAOADshAA==.',
Fi='Fireflydh:BAAANQADCgYIBgABNQAECgoKJgAEAKMTAA==.Firetotems:BAAANQAECgEIAQABNQAECgoKJgAEAKMTAA==.Firragol:BAAANQABCgYICgAAAA==.Firèflyjd:BAABNQAECn8mAAQEAAoKoxNddABpAQAEAAgKOBJddABpAQAiAAUKKw+2FwCyAAAhAAIK4xeTHAB1AAAAAA==.Fishstick:BAAANQADCggIGAAAAA==.',
Fl='Floatpass:BAACNQAFFH8KAAIBAAQK4hw8HQD7AAABAAQK4hw8HQD7AAA1AAQKf0MAAgEACgqBI30gAFgDAAEACgqBI30gAFgDAAAA.',
Fo='Foot:BAAANQADCgcJCQAAAA==.',
Fr='Frizz:BAAANQAECgQIDAAAAA==.Froey:BAEANQAECgMIAwAAAA==.',
Fu='Fuzzynuttz:BAAANQAECggIAQAAAA==.Fuzzypally:BAABNQAECn8fAAIWAAoKfB+4IQDmAgAWAAoKfB+4IQDmAgAAAA==.Fuzzyshadow:BAAANQAECgQIBAAAAA==.Fuzzytotems:BAAANQAECgcIDgAAAA==.',
['Fá']='Fáavi:BAAANQAECgQIBAAAAA==.',
Ga='Gali:BAAANQADCgQJBAABNQAFFAQIBgAOAAkKAA==.Galiagante:BAAANQADCggJDAAAAA==.Gallynna:BAABNQAECn8tAAQEAAgKphLCewDxAQAEAAgKKRHCewDxAQAhAAMKVRCcWgBxAAAiAAMKhwuxJABcAAAAAA==.Galorfax:BAABNQAECn83AAIeAAoKCR/aCQCRAgAeAAoKCR/aCQCRAgAAAA==.Galushi:BAAANQADCggIDwAAAA==.Garm:BAABNQAECn87AAIFAAoKXiMaEAAJAwAFAAoKXiMaEAAJAwABNQAECgoKRQAXADsjAA==.',
Ge='Gelinea:BAAANQADCgYIDQAAAA==.Gerlton:BAAANQADCgQIBAAAAA==.Gernar:BAAANQADCgUICwAAAA==.',
Gi='Gilgaroth:BAABNQAECn9DAAMIAAoKbxuDJABkAgAIAAoKiBmDJABkAgAHAAgKLBkDEwCSAQAAAA==.Girlslove:BAAANQADCgIIAgABNQAFFAcIGQAfAM8fAA==.',
Gn='Gnoskill:BAAANQAECgQIBgAAAA==.',
Go='Gobo:BAABNQAECn8WAAIUAAgKBRZEXwAEAgAUAAgKBRZEXwAEAgAAAA==.',
Gr='Graysonn:BAAANQADCggIGQAAAA==.Greafox:BAABNQAECn8mAAMNAAoKSiQQBgCVAwANAAoKSiQQBgCVAwAUAAUKHxR/rgA2AQAAAA==.Grrimreaperr:BAAANQADCgcIBwAAAA==.Grýla:BAAANQADCgUIBQAAAA==.',
Gu='Guildenstern:BAABNQAECn8oAAMHAAoKECOwAgAhAwAHAAoKECOwAgAhAwAIAAIKZhi5wQBPAAABNQAFFAcIGQAfAM8fAA==.Gundrakk:BAAANQAECgYIEgAAAA==.Gunnr:BAAANQAECgQICQABNQAECggIEAASAAAAAA==.Gunthorian:BAAANQAECgMJAwAAAA==.',
Ha='Handsomemonk:BAAANQADCgMIBAABNQAECgoKJgADAAYjAA==.Hansi:BAAANQAECgMIBQAAAA==.Harbringer:BAAANQAECgUIBgABNQAECgkJIgAWAPMUAA==.',
He='Heart:BAAANQAECgUIAwABNQAECgkJKgADAIsfAA==.Heid:BAAANQADCggIDwAAAA==.Helldozer:BAAANQADCgcICQAAAA==.Heytherepal:BAAANQAECgQIBwAAAA==.',
Hi='Higanbana:BAACNQAFFH8hAAIgAAcKiB7zAgB9AQAgAAcKiB7zAgB9AQA1AAQKfz4AAiAACgq4JfIFAHIDACAACgq4JfIFAHIDAAAA.Himawari:BAABNQAECn8gAAIDAAkKIiCTQwDKAgADAAkKIiCTQwDKAgABNQAFFAcIIQAgAIgeAA==.Himejoshi:BAACNQAFFH8ZAAIfAAcKzx9OAABwAgAfAAcKzx9OAABwAgA1AAQKf1IAAh8ACgrXJi4AAJsDAB8ACgrXJi4AAJsDAAAA.Hippocampus:BAABNQAECn8uAAINAAoK9B+4CACAAwANAAoK9B+4CACAAwAAAA==.Hirys:BAABNQAECn8XAAIIAAgKKxNvGwD7AQAIAAgKKxNvGwD7AQAAAA==.',
Ho='Holybeks:BAAANQAECgEIAgABNQAECgoKNAAOADshAA==.Holydaddy:BAAANQAECgYICQAAAA==.Holysmite:BAAANQAECgQIBAABNQAECggIDwASAAAAAA==.Hoppadk:BAABNQAECn80AAIOAAoKOyElGgDdAgAOAAoKOyElGgDdAgAAAA==.Hotdoggin:BAAANQADCgEIAQABNQAECgoKJgADAAYjAA==.Hotshotzz:BAAANQAECgMIAwABNQAECggIIwADAF0fAA==.',
Hu='Huntfosho:BAAANQAECgQICQAAAA==.Huntsmedown:BAAANQADCgYICQAAAA==.',
['Há']='Háldrin:BAACNQAFFH8SAAMcAAYK6BfuCQAlAQAcAAUKphjuCQAlAQAFAAEK8BQvKgBbAAA1AAQKfzYAAxwACgpfIsYLAB0DABwACgq1IcYLAB0DAAUAAQo0Jl4XAWwAAAAA.',
['Hö']='Hölybeary:BAABNQAECn8gAAMWAAkKYAx+UwC0AQAWAAkKYAx+UwC0AQAdAAYK7QcRSwC/AAAAAA==.',
Ia='Iamprepared:BAAANQABCgEIAQAAAA==.',
Ic='Icybacon:BAAANQAECgQIBAAAAA==.Icëcrëam:BAAANQADCggICAAAAA==.',
Ih='Ihavegrass:BAABNQAECn8UAAMFAAYK6wz2AgH/AAAFAAYK6wz2AgH/AAAcAAEKswRSaQAtAAAAAA==.',
Il='Illyeris:BAAANQAECgIIAwAAAA==.',
Im='Imbue:BAABNQAECn8yAAIbAAoKMh6EBACCAgAbAAoKMh6EBACCAgAAAA==.Imbuer:BAAANQAECgQICQAAAA==.',
In='Innil:BAABNQAECn8nAAMCAAoKdiVCAgDHAwACAAoKdiVCAgDHAwAJAAEK6B6HEgBbAAAAAA==.Inora:BAAANQABCgMIAwAAAA==.',
It='Itzapazz:BAAANQADCggIGwAAAA==.',
Ja='Jaurel:BAAANQADCgMIAwAAAA==.',
Je='Jessiks:BAAANQAECgIIBgAAAA==.Jessix:BAABNQAECn8WAAMEAAoKfh8KLwDKAgAEAAoKSR8KLwDKAgAhAAIK9RPWUQCKAAAAAA==.Jezebel:BAABNQAECn8uAAMEAAoKMRc6TgBpAgAEAAoKWxU6TgBpAgAhAAQKDxNRHAB3AAAAAA==.',
Ji='Jiaoe:BAAANQADCgIIAgAAAA==.Jimfowler:BAAANQADCgIIAgAAAA==.Jirito:BAAANQAECgMJAwAAAA==.',
Jo='Jomadead:BAABNQAECn8iAAIOAAgK6hRtJgC7AQAOAAgK6hRtJgC7AQABNQAECgoKGgANAOgSAA==.Jomas:BAABNQAECn8aAAINAAoK6BLpVQAQAgANAAoK6BLpVQAQAgAAAA==.Jovaar:BAAANQADCggICAAAAA==.',
Ju='Judera:BAABNQAECn9HAAMDAAoKzBtOQwBQAgADAAoKzBtOQwBQAgAdAAEKYRKPYAAxAAAAAA==.',
Ka='Kaing:BAABNQAECn8nAAIaAAcKXw2UFgAyAQAaAAcKXw2UFgAyAQAAAA==.Kaladen:BAABNQAECn8dAAQkAAoK7CIpBwBQAwAkAAoK7CIpBwBQAwAMAAEKlhIqrQA8AAAeAAEKvxccXQA7AAAAAA==.Kalec:BAAANQADCgUJBQAAAA==.Kalos:BAAANQAECgEIAwAAAA==.Kalysti:BAAANQAECggIIgAAAQ==.Kaoticmagus:BAAANQAECgEIAQABNQAECgEIAQASAAAAAA==.Kaoticnature:BAAANQAECgEIAQAAAA==.Karolg:BAABNQAECn8cAAIOAAcKXRxRKwCbAQAOAAcKXRxRKwCbAQAAAA==.Katostrafic:BAABNQAECn8sAAMJAAoKmxUwCQDIAQAJAAcKcBUwCQDIAQACAAkKWhSDcAByAQAAAA==.Katrynna:BAAANQADCgYIEwAAAA==.',
Ke='Kelarra:BAAANQADCgQIBgAAAA==.',
Kh='Khromscarin:BAACNQAFFH8MAAIbAAMK6xNJAgDBAAAbAAMK6xNJAgDBAAA1AAQKf1MAAxsACgotIoYCAOgCABsACgotIoYCAOgCACAABwrVDdc2AI0BAAAA.',
Ki='Kiaradarkpaw:BAAANQAECgEIAQAAAA==.Killidan:BAABNQAECn8uAAIgAAoKpB3eEwDJAgAgAAoKpB3eEwDJAgAAAA==.Kirklees:BAAANQAECgUICwAAAA==.Kitsuchan:BAABNQAECn8hAAQBAAoK0yLnSgDsAgABAAkKEiPnSgDsAgAlAAMK2iLtJADHAAAmAAEKAACJDgAAAAAAAA==.',
Kk='Kkthx:BAAANQADCgcIBwABNQAFFAQIBwACAO8JAA==.',
Ko='Kodama:BAABNQAECn8yAAIUAAoKLgs+XgBUAQAUAAoKLgs+XgBUAQAAAA==.Koi:BAAANQADCgcIEgABNQAECgkJLwAbABofAA==.Kookiemon:BAAANQAECgYICAAAAA==.Kookiesplz:BAAANQADCggICAAAAA==.Kopili:BAAANQADCgUIBwAAAA==.',
Kr='Krekdas:BAAANQADCgUIBQAAAA==.Kromag:BAAANQADCgYIBgABNQAECggICgASAAAAAA==.',
Ku='Kunpochiken:BAAANQAECgYICAABNQAECgoKLAAJAJsVAA==.',
Ky='Kyanna:BAABNQAECn8WAAIMAAYKcQSIawBuAAAMAAYKcQSIawBuAAAAAA==.Kyoshi:BAAANQAECgUIBQAAAA==.',
La='Lader:BAABNQAFFH8PAAIDAAkKtACpKgBTAAADAAkKtACpKgBTAAAAAA==.Ladifantasie:BAAANQAECgQICAAAAA==.Laria:BAABNQAECn8VAAIgAAgKshWSJQAZAgAgAAgKshWSJQAZAgAAAA==.Laurebeth:BAAANQAFFAEIAQAAAA==.Laxinmedium:BAAANQADCggIDwAAAA==.',
Le='Leenei:BAAANQAECgQICAAAAA==.Lenlaar:BAABNQAECn8cAAIDAAkKKBTUqQBlAQADAAkKKBTUqQBlAQAAAA==.Levande:BAACNQAFFH8KAAICAAMK1hDRHwDMAAACAAMK1hDRHwDMAAA1AAQKfzIAAwIACgoYIG4JAJIDAAIACgoYIG4JAJIDABEAAgq7DbFKAG0AAAAA.',
Li='Lifeblume:BAAANQADCggIIwAAAA==.Lightnning:BAAANQAECgMIBAAAAA==.Lildevil:BAAANQADCgUIBgAAAA==.Lilithandria:BAABNQAECn8UAAIVAAkKFBnQPADRAQAVAAkKFBnQPADRAQAAAA==.Linamar:BAAANQAECgUICgAAAA==.Littlefishy:BAAANQADCgMIAwAAAA==.',
Lo='Loaq:BAABNQAECn8yAAMCAAoK9hPbRgBSAgACAAoK9hPbRgBSAgAJAAMK4giBHACBAAAAAA==.Lockzrockz:BAAANQAECgUIAwAAAA==.Lodshan:BAAANQAECgEIAQAAAA==.Longbottom:BAAANQAECggICQABNQAECgoKJgADAAYjAA==.Loot:BAAANQAECggIEQAAAA==.Lorbert:BAAANQAECgQIBgABNQAECgoKKAAXADMVAA==.Lostalot:BAABNQAECn8xAAIFAAkK3hQGXwBZAgAFAAkK3hQGXwBZAgAAAA==.',
Lu='Luxæterna:BAABNQAECn9EAAIDAAoKvSAyPQBlAgADAAoKvSAyPQBlAgAAAA==.',
Ly='Lyphiara:BAAANQADCggIGgABNQAECgkJMwAPAGofAA==.',
Ma='Malice:BAABNQAECn8VAAMiAAgKghUnCgDYAQAiAAgKghUnCgDYAQAhAAIKZAUFaQBPAAAAAA==.Mandwandos:BAABNQAECn8cAAQNAAoKIBijdwClAQANAAgKqBWjdwClAQAUAAkKtQpkjQCCAQATAAEKAAC7OgAAAAAAAA==.Maraliss:BAABNQAECn8UAAIfAAUKfQzrJADmAAAfAAUKfQzrJADmAAAAAA==.',
Me='Meiri:BAAANQADCgEIAQABNQAFFAMICAAZADESAA==.Melaunis:BAAANQAECgQIBgAAAA==.Meowzer:BAABNQAECn8dAAQMAAUKaRRXbAAZAQAMAAUKZxFXbAAZAQAfAAQKtA0BLwCaAAAeAAUKrA/ySQCDAAABNQAFFAQIBwACAO8JAA==.Merginator:BAAANQAECgUIBwAAAA==.Meteora:BAACNQAFFH8IAAIZAAMKMRLsBADEAAAZAAMKMRLsBADEAAA1AAQKfx8AAhkACgoYG3wMAG0CABkACgoYG3wMAG0CAAAA.Methisto:BAAANQADCgcIBwAAAA==.',
Mi='Mideel:BAABNQAECn8WAAImAAYK3QhNBgD7AAAmAAYK3QhNBgD7AAAAAA==.Midesis:BAAANQAECgQICgAAAA==.Midesisheals:BAAANQAECgIIBwAAAA==.Migolbearcow:BAABNQAECn9DAAIeAAoK/BZEDwBwAgAeAAoK/BZEDwBwAgAAAA==.Missed:BAAANQAECgIJAwAAAA==.Missedweaver:BAAANQADCgYICAABNQAECgIJAwASAAAAAA==.Missrae:BAAANQADCggIFwAAAA==.',
Mk='Mk:BAEANQADCgIIAgABNQAECgoKPQAQAFkfAA==.Mkaliaz:BAAANQAECgEIAgAAAA==.',
Ml='Mlglock:BAAANQADCgMIAwAAAA==.',
Mo='Moiira:BAAANQAECgEIAQAAAA==.Monyshot:BAAANQADCgcIDQAAAA==.Moondizzle:BAAANQAECgIIAgAAAA==.Mooniè:BAABNQAECn8jAAMlAAoK7wOqJADJAAAlAAoK7wOqJADJAAABAAYKAQLoEwGDAAAAAA==.Moosenuts:BAABNQAECn8VAAIEAAcKaBBTkgC5AQAEAAcKaBBTkgC5AQAAAA==.Moriavus:BAABNQAECn8qAAIiAAoKxxeyBACLAgAiAAoKxxeyBACLAgAAAA==.Morocha:BAABNQAECn8dAAIPAAgKDQ4JKQArAQAPAAgKDQ4JKQArAQAAAA==.Mortèm:BAAANQAECgIIAgAAAA==.Moxxie:BAAANQABCggIEwABNQAECgQIBAASAAAAAA==.',
Mu='Muragore:BAAANQAECgUICwAAAA==.',
My='Mychropien:BAABNQAECn8tAAMLAAoKUyHlIgC6AgALAAoKUyHlIgC6AgAOAAMKURu9iwBMAAAAAA==.Myylus:BAAANQADCgYIFAAAAA==.',
['Mö']='Mökes:BAABNQAECn89AAIhAAoK0yQCAQCbAwAhAAoK0yQCAQCbAwAAAA==.',
Na='Nadroj:BAAANQADCggIIgAAAA==.Nancydru:BAABNQAECn8ZAAIeAAYKaRSdJwAzAQAeAAYKaRSdJwAzAQAAAA==.Naosu:BAAANQADCggIEAAAAA==.Nax:BAABNQAECn8aAAIBAAcK9wu6vQAZAQABAAcK9wu6vQAZAQAAAA==.Nazagos:BAAANQAECgEIAQABNQAECgoKPgAFAEclAA==.Nazzersaurus:BAABNQAECn8aAAIkAAcKYxnYJQD0AQAkAAcKYxnYJQD0AQAAAA==.',
Ne='Nec:BAAANQAECgEIAQAAAA==.Necronite:BAAANQADCgMIAwABNQAECgcIIwANANEXAA==.Necrøtic:BAABNQAECn80AAMlAAoKPRSaCAANAgAlAAoKPRSaCAANAgABAAQKqgYijgGqAAAAAA==.Nekomata:BAAANQAECgEIAQAAAA==.Nekosmasta:BAAANQABCgIIAgAAAA==.Neodin:BAAANQAECggIDgAAAA==.Nevermiss:BAABNQAECn9DAAIPAAoKehc5DwAMAgAPAAoKehc5DwAMAgAAAA==.',
Ni='Nightjewel:BAAANQADCggIDwAAAA==.',
No='Notmewasyou:BAABNQAECn8hAAMMAAcKSANihwC1AAAMAAcKSANihwC1AAAkAAQKpAHQawA+AAAAAA==.',
Nu='Nuali:BAABNQAECn8rAAMDAAkKeBnHZABsAgADAAkKHRnHZABsAgAdAAgKBhHZJwAeAQAAAA==.Numi:BAAANQADCggIDQAAAA==.',
Od='Odysseus:BAAANQADCgUICQAAAA==.',
Ok='Okameshiz:BAAANQADCggIDQAAAA==.',
On='Onlyquakes:BAAANQAECggIAgAAAA==.Onlyspins:BAAANQAECgYIBwAAAA==.',
Or='Orý:BAABNQAECn9EAAIUAAoK1hsbLADOAgAUAAoK1hsbLADOAgAAAA==.',
Os='Oslatem:BAAANQADCgcICQAAAA==.',
Ox='Oxosorrel:BAAANQAECgEIAQAAAA==.',
Oz='Ozzmodious:BAAANQADCgcIEgAAAA==.',
Pa='Pajonn:BAAANQAECggIEgAAAA==.Paladan:BAABNQAECn8wAAMdAAoK3iFfBwAtAwAdAAoK3iFfBwAtAwADAAMKaR9/HQGpAAAAAA==.Paladanny:BAAANQAECgYIDQAAAA==.Palagi:BAABNQAECn8jAAMfAAYKlgXKLQCIAAAfAAYKlgXKLQCIAAAkAAMKpwg9ZQBTAAAAAA==.Pallu:BAAANQADCgQIBAAAAA==.Pallyana:BAABNQAECn8aAAIWAAoKHBsYMgCdAgAWAAoKHBsYMgCdAgAAAA==.Pallyfosho:BAAANQAECgIIAgAAAA==.Pallymcbeall:BAAANQAECgMIBAAAAA==.Paprikaman:BAABNQAECn8WAAIFAAYKcAJAHAHHAAAFAAYKcAJAHAHHAAAAAA==.Parallax:BAAANQAECgEIAQAAAA==.Pariahrain:BAABNQAECn8hAAMdAAgKFRk8GwAUAgAdAAgKFRk8GwAUAgADAAIKyQKPhwFPAAABNQAFFAQICgAlADUIAA==.Parishealton:BAABNQAECn8pAAMkAAoKWCD0CQAnAwAkAAoKWCD0CQAnAwAMAAMKvQFvpgBMAAAAAA==.Payday:BAAANQADCgYICwAAAA==.Pazzuzu:BAAANQADCgcICwAAAA==.',
Pe='Penjamin:BAAANQAECgQICAABNQAECgoKJgADAAYjAA==.Perprotrus:BAAANQADCgQIBAABNQAFFAQIBgAOAAkKAA==.',
Ph='Phatboi:BAAANQAECgQIBwAAAA==.',
Po='Poulsbo:BAAANQAECgQICgAAAA==.Powerup:BAAANQAECgQIBQAAAA==.Pozole:BAAANQAECgcIDQAAAA==.',
Pr='Prominence:BAABNQAECn8vAAIGAAoKOCHiAQDFAgAGAAoKOCHiAQDFAgAAAA==.Promisques:BAAANQAECgEIAQAAAA==.Protectapear:BAAANQAECgEIAwAAAA==.Prozak:BAABNQAECn8xAAINAAkKjBeCNQAvAgANAAkKjBeCNQAvAgAAAA==.Prozakmd:BAAANQADCggICAAAAA==.',
Pw='Pwomf:BAABNQAECn8YAAIDAAoKpwkMpgBsAQADAAoKpwkMpgBsAQAAAA==.',
Py='Pyneapple:BAAANQADCgQIBAABNQAFFAQIBwACAO8JAA==.Pyrolily:BAABNQAECn8XAAIlAAcKKQYwHwDxAAAlAAcKKQYwHwDxAAAAAA==.',
Qu='Question:BAAANQADCgIIAwAAAA==.Qulung:BAAANQADCggIFAAAAA==.',
Ra='Rabyd:BAAANQAECgMIBgAAAA==.Raegasm:BAAANQADCgYIEAAAAA==.Raght:BAAANQAECgIIAgAAAA==.Raha:BAAANQAECgYIEAAAAA==.Raithe:BAAANQADCgYIBgAAAA==.Ramue:BAAANQADCgcIDgAAAA==.Raskela:BAABNQAECn8cAAMPAAkKpxO3GADyAQAPAAkKpxO3GADyAQAQAAcKdhQrMQCOAQAAAA==.Rastakan:BAAANQAECgUIDAABNQAECgoKRQAXADsjAA==.Razal:BAAANQADCggIDQAAAA==.',
Re='Reesespiecez:BAAANQAECgcICwAAAA==.Rellidana:BAAANQAECggICwAAAA==.Remove:BAAANQAECgUIBQAAAA==.Reprieve:BAAANQAECgUICQAAAA==.Reshani:BAAANQAECgEIAwAAAA==.Retradormi:BAAANQAECgQICwAAAA==.Rexi:BAABNQAECn8hAAIRAAkKCg6VJwDuAQARAAkKCg6VJwDuAQAAAA==.',
Ri='Rickcando:BAABNQAECn8WAAIUAAYK2xRMbwDSAQAUAAYK2xRMbwDSAQAAAA==.Ricshard:BAABNQAECn84AAQEAAgK8hTXeABeAQAEAAYKaBbXeABeAQAhAAMKtBddGwB+AAAiAAIKMAv+KgA4AAAAAA==.Ridjeckgron:BAAANQADCgcICQAAAA==.Rissiia:BAAANQADCgQIBAAAAA==.',
Rm='Rmft:BAAANQAECgUICAABNQAECgoKPgAXAAEZAA==.',
Ro='Roa:BAAANQAECgEIAQAAAA==.Roomnboard:BAAANQAECgMIAwAAAA==.Rotter:BAAANQADCgQIBAAAAA==.Roughluver:BAAANQAECgUICQABNQAFFAQIBwACAO8JAA==.',
Ru='Ruben:BAAANQADCgEIAgAAAA==.Rungar:BAAANQAECgQICwAAAA==.',
Rv='Rvoker:BAAANQADCgQIBAAAAA==.',
Ry='Rya:BAAANQAECgEIAQAAAA==.Rydmytotem:BAAANQAECggICgAAAA==.Rylia:BAAANQADCgcICQAAAA==.Ryuk:BAAANQADCgMIAwAAAA==.Ryukyu:BAAANQAECgEIAQAAAA==.Ryñ:BAABNQAECn8XAAIFAAoKfhlpOABZAgAFAAoKfhlpOABZAgAAAA==.',
['Rà']='Ràein:BAABNQAECn8uAAMhAAgK5A63CAAsAQAhAAgK5A63CAAsAQAEAAEK0QJeHAEfAAAAAA==.',
['Ró']='Ród:BAABNQAECn8jAAIDAAgKXR9IbwBRAgADAAgKXR9IbwBRAgAAAA==.',
['Rø']='Røth:BAAANQADCgcIEgAAAA==.',
Sa='Saalira:BAAANQADCggIEgAAAA==.Sabellice:BAABNQAECn87AAIDAAkK2BHSgQC0AQADAAkK2BHSgQC0AQAAAA==.Sakonna:BAABNQAECn8fAAIRAAkKQRV8IAA1AgARAAkKQRV8IAA1AgAAAA==.Salinoria:BAAANQAECgQICQABNQAECgkJKwADAHgZAA==.Saltyfingers:BAAANQADCgcIBwAAAA==.Sandymaw:BAAANQADCgQIBAABNQAFFAQIBwACAO8JAA==.Sarlius:BAABNQAECn8+AAIFAAoKRyXpAgDYAwAFAAoKRyXpAgDYAwAAAA==.Sassybuns:BAAANQABCgQIBAAAAA==.Satyrical:BAABNQAECn8qAAIDAAkKix8lTAA2AgADAAkKix8lTAA2AgAAAA==.Savin:BAAANQAECgUIEQAAAA==.',
Sc='Scavenger:BAAANQAECgYIDgAAAA==.Scorchin:BAAANQAECggIEAAAAA==.Scrumptiøus:BAAANQAECgUIDAABNQAECgoKLAAJAJsVAA==.',
Se='Selkamonk:BAABNQAECn8zAAMPAAkKah/0CgDXAgAPAAkKah/0CgDXAgAQAAIKDga0XAArAAAAAA==.Seniorbold:BAABNQAECn8jAAIDAAoKwhmzQgDMAgADAAoKwhmzQgDMAgAAAA==.Sentrina:BAACNQAFFH8IAAIjAAUKJAyaDgDTAAAjAAUKJAyaDgDTAAA1AAQKfzUAAiMACgqYHSgNANMCACMACgqYHSgNANMCAAAA.Seraph:BAAANQAECgcIEAAAAA==.Seshy:BAACNQAFFH8HAAMCAAQK7wk6IQDAAAACAAMKxwY6IQDAAAARAAIKTQdaEAB9AAA1AAQKf00AAwIACgpsHEkiAL0CAAIACgpsHEkiAL0CABEACQr1FyYgADkCAAAA.Seshymutedme:BAAANQAECggIEQABNQAFFAQIBwACAO8JAA==.',
Sh='Shamanagins:BAAANQADCgEIAQAAAA==.Shannon:BAAANQADCgYIBgABNQAECgcIIQAWAPUQAA==.Shannoon:BAABNQAECn8iAAIdAAcKuQlsNADPAAAdAAcKuQlsNADPAAAAAA==.Sharr:BAAANQADCgYJDAAAAA==.Shekzeer:BAABNQAECn8rAAQQAAoKjSXlAADnAwAQAAoKjSXlAADnAwAPAAYK0hzxGgDSAQAnAAMK8yALIwC/AAAAAA==.Shiverr:BAABNQAECn8uAAIlAAgK1gcmGQAtAQAlAAgK1gcmGQAtAQAAAA==.Shockakan:BAAANQABCgQIBAAAAA==.Shockazulu:BAAANQADCgIIAgAAAA==.Shocktard:BAAANQAECgEIAQABNQAECgkJHwAKAJMdAA==.',
Si='Siatraz:BAAANQAECgQIBgABNQAECgoKJgAEAKMTAA==.Siegatrox:BAAANQAECgIIAgAAAA==.Silgan:BAAANQADCgYIBgAAAA==.Silverbain:BAAANQADCgQIBAAAAA==.Sinnon:BAAANQAECgMIAwAAAA==.',
Sk='Skizem:BAAANQAECgIIBwAAAA==.Skott:BAAANQAECgQIBAAAAA==.Skïnnyßetch:BAAANQADCgcIBwAAAA==.',
Sl='Sleepadin:BAABNQAECn8ZAAIDAAoKegop0QB5AQADAAoKegop0QB5AQAAAA==.Sleepyr:BAAANQAECgYIDQAAAA==.',
Sm='Smokeymage:BAAANQAECgYIDgAAAA==.',
Sn='Snowi:BAAANQADCgYIBgABNQAECggIEAASAAAAAA==.Snowstorm:BAAANQAECgEIAQAAAA==.',
So='Soakra:BAABNQAECn8jAAINAAoK/hbaRABOAgANAAoK/hbaRABOAgAAAA==.Solignis:BAACNQAFFH8pAAMaAAcKTSYUAAChAgAaAAcKTSYUAAChAgAXAAQK6R5WFACIAQA1AAQKf1sAAxoACgoDJwUAAB4EABoACgoDJwUAAB4EABcACQqUJu8HALMDAAAA.Solxeen:BAAANQADCggICAAAAA==.Soniviolence:BAABNQAECn82AAIXAAoK0CBoGwBKAwAXAAoK0CBoGwBKAwAAAA==.Soohots:BAACNQAFFH8GAAIkAAMKmBpeCgD/AAAkAAMKmBpeCgD/AAA1AAQKfx4AAyQACQrgHYkUAKUCACQACArdHIkUAKUCAAwABAovEOyNAJ8AAAAA.Sourskittlz:BAAANQADCgQIBAAAAA==.',
Sp='Sparklehappy:BAABNQAECn8aAAMcAAkKexhlKgADAQAcAAgKLxhlKgADAQAFAAEKQRoJRgFTAAAAAA==.Splìff:BAAANQADCgYIBgAAAA==.Sppazz:BAAANQADCgcIBwAAAA==.',
St='Starshield:BAAANQAECgIIAwABNQAECgkJGAALAHYWAA==.Stausa:BAAANQADCgcIBwAAAA==.Steeljustice:BAAANQAECggICAAAAA==.Stormcreek:BAABNQAECn8jAAMNAAcK0RftZgBqAQANAAcK0RftZgBqAQAUAAIKnQJi/wApAAAAAA==.Storri:BAACNQAFFH8FAAICAAIKNBR0KACIAAACAAIKNBR0KACIAAA1AAQKf1IAAwIACgqZG4cjALUCAAIACgqZG4cjALUCABEABQrCBhtUAL0AAAAA.',
Su='Sufferinhero:BAAANQAECgEIAQABNQAFFAMIDAAbAOsTAA==.Suzuya:BAAANQAECgMIBAAAAA==.',
Sv='Svetty:BAAANQAECggICgAAAA==.',
Sw='Swiftly:BAABNQAECn8UAAMIAAgKoyDFKwA9AgAIAAcKJSLFKwA9AgAHAAcKexv9GABVAQAAAA==.Swiftmage:BAACNQAFFH8pAAMlAAcKhiU5AABhAgAlAAcKhiU5AABhAgABAAUKvR0cGgCpAQA1AAQKf0sAAyUACgruJg8AAAcEACUACgruJg8AAAcEAAEACQoqJeMYAHEDAAAA.Switchboard:BAAANQADCgYICgAAAA==.',
Sx='Sxkittn:BAAANQADCgcICwAAAA==.',
Sy='Sygh:BAAANQAECgEIAQABNQAECgkJKgADAIsfAA==.Syltru:BAAANQADCgUIBQAAAA==.Syndragonkin:BAABNQAECn80AAIFAAkKixWmawDQAQAFAAkKixWmawDQAQAAAA==.Syndrome:BAAANQADCggIDgAAAA==.Synger:BAAANQADCgYIEAAAAA==.',
Ta='Taima:BAAANQABCgEIAQAAAA==.Talyndis:BAACNQAFFH8pAAIcAAkKJyEKAQCgAgAcAAkKJyEKAQCgAgA1AAQKfzsAAhwACgo4JTMEAA4DABwACgo4JTMEAA4DAAAA.Tamyr:BAAANQADCgIIAgAAAA==.Tazadar:BAAANQAECgEIAwAAAA==.Taze:BAAANQAECgUJBwABNQAFFAQIBgAOAAkKAA==.Tazjiingo:BAAANQADCgIIBAAAAA==.',
Te='Terrika:BAABNQAECn8jAAIFAAgKwQrxigD0AQAFAAgKwQrxigD0AQAAAA==.Tetshajeh:BAACNQAFFH8MAAIXAAMKLBZLGADYAAAXAAMKLBZLGADYAAA1AAQKf14AAxcACgp6IpMYAFYDABcACgp6IpMYAFYDABkABQp5HDAeAPcAAAAA.Teyliana:BAABNQAECn8WAAIPAAYKTQhbKACvAAAPAAYKTQhbKACvAAAAAA==.',
Th='Thebigchud:BAAANQAECgYIDQAAAA==.Thillarick:BAABNQAECn8+AAIXAAoKARnBOABPAgAXAAoKARnBOABPAgAAAA==.Thiss:BAAANQAECgEIAwAAAA==.Thromanor:BAAANQAECgUIBAAAAA==.Thwip:BAABNQAECn86AAMFAAoKRCGaLADoAgAFAAoKRCGaLADoAgAcAAkKChVREgAKAgAAAA==.Thänatøs:BAAANQAECgEIAgAAAA==.',
Ti='Tikwid:BAABNQAECn8lAAIBAAgKhwWy1ADvAAABAAgKhwWy1ADvAAAAAA==.Tiranmyashol:BAABNQAECn8oAAIXAAoKMxXcaABVAgAXAAoKMxXcaABVAgAAAA==.',
To='Tomoya:BAAANQAECgcIEgAAAA==.Too:BAAANQAECgIIAQAAAA==.Toothdk:BAABNQAECn8XAAILAAUKWRWxQgDxAAALAAUKWRWxQgDxAAAAAA==.Torfnar:BAABNQAECn8aAAIGAAoKSQhlBgC9AQAGAAoKSQhlBgC9AQAAAA==.Tormmentor:BAAANQAECgUIEAAAAA==.',
Tr='Treebreak:BAAANQAECgUIDwAAAA==.',
Tu='Tugmydangle:BAAANQAECgYIDAAAAA==.',
Ty='Tyrandrea:BAAANQADCgcICQAAAA==.',
['Tô']='Tôxin:BAAANQAECggIBgAAAA==.',
Ud='Udari:BAAANQAECgcIDgAAAA==.Udarii:BAAANQAECgcICQAAAA==.',
Um='Umàdbrah:BAABNQAECn86AAIFAAgK7yDhKgCHAgAFAAgK7yDhKgCHAgAAAA==.',
Un='Unbelievable:BAABNQAECn8mAAIVAAkKSQr2NgBTAQAVAAkKSQr2NgBTAQAAAA==.Unprovoked:BAABNQAECn8iAAIBAAkKwh5dVwDRAgABAAkKwh5dVwDRAgAAAA==.',
Uw='Uwntme:BAAANQAECgEIAQAAAA==.',
Va='Valamor:BAABNQAECn84AAMdAAgKexGRHQBtAQAdAAgKexGRHQBtAQAWAAUK4Ae1zQDgAAAAAA==.Varenea:BAAANQADCgYIBgAAAA==.Varia:BAAANQAECgEIAQABNQAECgkJHwAKAJMdAA==.',
Ve='Veefib:BAABNQAECn85AAMUAAoK9hn0MQD7AQAUAAoK9hn0MQD7AQANAAMKLg/fswCgAAAAAA==.Velicerus:BAAANQAECgQIBQAAAA==.Velvettwitch:BAABNQAECn8wAAIhAAkKGRPxBQB0AQAhAAkKGRPxBQB0AQAAAA==.Vendler:BAABNQAECn8VAAIXAAkKnQcbugCLAQAXAAkKnQcbugCLAQAAAA==.Verahla:BAAANQAECgEIAQAAAA==.Vermis:BAABNQAECn8/AAIKAAoKzhDZLQDhAQAKAAoKzhDZLQDhAQAAAA==.Veryaverage:BAABNQAECn8oAAMmAAgKXhP/AwA8AQABAAgKIhKdbwC/AQAmAAYKPRD/AwA8AQAAAA==.Vexation:BAAANQAECgQICwAAAA==.',
Vi='Vicarious:BAACNQAFFH8GAAINAAMKDQYqGwCxAAANAAMKDQYqGwCxAAA1AAQKfzYAAg0ACgrlHAMsAF8CAA0ACgrlHAMsAF8CAAAA.Vidreaux:BAABNQAECn86AAMBAAkKKgxbkAByAQABAAkKmAtbkAByAQAlAAIKDwtyLgBkAAAAAA==.Villaraa:BAAANQADCgEIAQAAAA==.Vivid:BAAANQAECgQICAAAAA==.',
Vo='Voidofvoids:BAAANQAECgYICwAAAA==.Volke:BAAANQAECgUICQAAAA==.Volkennoria:BAAANQADCgcIBwABNQAECggIKQAFADobAA==.Votingromney:BAAANQAECgcICgABNQAECgoKKwAQAI0lAA==.Vowz:BAAANQADCgMIAwAAAA==.',
Vu='Vulpe:BAABNQAECn8pAAIFAAgKOht1XABgAgAFAAgKOht1XABgAgAAAA==.',
Vy='Vyolenta:BAAANQADCgIIAgAAAA==.',
['Vë']='Vëxhunter:BAAANQAECggIDwAAAA==.',
Wa='Waldorf:BAAANQAECgUICAAAAA==.Wallegator:BAAANQAECgEIAQABNQAECggINgAkACMiAA==.Walleroot:BAAANQAECgUIBQABNQAECggINgAkACMiAA==.',
We='Weinersoup:BAAANQAECgQIDgAAAA==.',
Wh='Whitewhitch:BAAANQADCgIIAwAAAA==.Whosethetank:BAAANQAECgMICAAAAA==.',
Wi='Wickedgnome:BAAANQAECgEIAQAAAA==.',
Wo='Wolfpup:BAAANQAECggICwABNQAECgoKRwADAMwbAA==.Wolfíe:BAAANQADCgUIBQAAAA==.Worstelf:BAABNQAECn8kAAMCAAgKPyEYQABqAgACAAgKPyEYQABqAgARAAYKgiIAIgAlAgAAAA==.',
Ww='Wwalle:BAAANQAECgEIAgABNQAECggINgAkACMiAA==.Wwallee:BAAANQADCgMIAwABNQAECggINgAkACMiAA==.',
Xa='Xanathos:BAAANQAECgcIDwABNQAECgoKPgAFAEclAA==.',
Xi='Xilstar:BAAANQADCgUIBQAAAA==.',
Xz='Xzavier:BAAANQADCggIDwAAAA==.',
Yf='Yfelshammy:BAABNQAECn84AAINAAoKiBUMTAAzAgANAAoKiBUMTAAzAgAAAA==.',
Yv='Yvaldi:BAAANQAECgYIBgABNQAFFAIICAACANciAA==.Yvonnél:BAAANQAECgIIAgABNQAECgkJFAAVABQZAA==.',
Za='Zaknafein:BAAANQAECgUICQAAAA==.Zanebusby:BAABNQAECn84AAIhAAoKux84AQDAAgAhAAoKux84AQDAAgAAAA==.Zankru:BAAANQADCgYIBwAAAA==.Zaraë:BAAANQADCggIDgAAAA==.Zaria:BAAANQAECgcIDgABNQAECgoKKwAQAI0lAA==.Zartash:BAABNQAECn8UAAIgAAgK3AMgPACuAAAgAAgK3AMgPACuAAAAAA==.Zatharis:BAABNQAECn8ZAAIFAAYKpwRg+gAPAQAFAAYKpwRg+gAPAQAAAA==.',
Ze='Zelik:BAAANQAECgYIDQABNQAECgoKPgAFAEclAA==.Zenezin:BAAANQAECgMIAwABNQAECgkJHwAKAJMdAA==.Zerax:BAABNQAECn8YAAMlAAgKnxFkEwA+AQABAAgKfgjnqABAAQAlAAcKtxNkEwA+AQABNQAECgoKRQAXADsjAA==.Zevellian:BAAANQADCggIDgABNQAECgcIEQASAAAAAA==.',
Zm='Zmona:BAABNQAECn8dAAIXAAkKGRSjhQAOAgAXAAkKGRSjhQAOAgABNQAECgkJHwAKAJMdAA==.',
Zo='Zolrath:BAAANQABCgQIAgAAAA==.',
['Ãm']='Ãmpstar:BAAANQAECgEIAQAAAA==.',
['Äm']='Ämpstarr:BAAANQADCgEIAQAAAA==.',
['Çy']='Çyanide:BAAANQADCgQICgABNQAECgkJKgADAIsfAA==.',
['Ðr']='Ðragonshaft:BAABNQAECn9CAAIFAAoKRhUzSQAqAgAFAAoKRhUzSQAqAgAAAA==.Ðreadlokz:BAAANQADCgQIBAAAAA==.',
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
