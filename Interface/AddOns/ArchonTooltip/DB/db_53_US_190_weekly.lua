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

local lookup = {'Mage-Arcane','Priest-Holy','Paladin-Retribution','Warlock-Demonology','Hunter-BeastMastery','Hunter-Survival','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','DeathKnight-Frost','DeathKnight-Unholy','Warrior-Arms','Druid-Balance','Shaman-Restoration','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','Priest-Shadow','Unknown-Unknown','Shaman-Enhancement','Paladin-Holy','Evoker-Devastation','Warrior-Protection','Warrior-Fury','DemonHunter-Vengeance','Hunter-Marksmanship','Paladin-Protection','Druid-Guardian','Druid-Feral','DemonHunter-Devourer','Warlock-Affliction','Warlock-Destruction','Shaman-Elemental','DemonHunter-Havoc','Evoker-Preservation','Druid-Restoration','Mage-Frost','Mage-Fire','Monk-Brewmaster',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aarazi:BAABNQAECn8+AAIBAAoKnxzRLQBqAgABAAoKnxzRLQBqAgAAAA==.',
Ab='Abbinormal:BAAANQADCggIHgAAAA==.Abolish:BAAANQABCgIIAgAAAA==.',
Ad='Adïrael:BAAANQABCggIFQAAAA==.',
Ae='Aeriss:BAAANQADCgYIDAAAAA==.Aethena:BAAANQADCgUIBQABNQAECgcIKwACAOcPAA==.Aezili:BAAANQADCgcIDQAAAA==.',
Ag='Agamotto:BAAANQADCgMIAwAAAA==.Agerol:BAABNQAECn8sAAIDAAkKqh6wSwATAgADAAkKqh6wSwATAgAAAA==.',
Ah='Ahaego:BAABNQAECn8bAAIEAAgK4Q4eZwBnAQAEAAgK4Q4eZwBnAQAAAA==.Ahnari:BAAANQAECgIIAgAAAA==.',
Ak='Akkadien:BAAANQAECgcIEQAAAA==.Akumunter:BAABNQAECn81AAMFAAoKEhtHKwDsAgAFAAoKEhtHKwDsAgAGAAIKkg2ADwBJAAAAAA==.',
Al='Alacardias:BAABNQAECn8vAAIDAAkKCB29RADGAgADAAkKCB29RADGAgAAAA==.Alette:BAAANQADCggICAAAAA==.Alihuntress:BAAANQADCgQIBQAAAA==.Alleril:BAABNQAECn8kAAMHAAoKkRKTCwDwAQAHAAkKmRCTCwDwAQAIAAkKbQ9wSwCGAQAAAA==.Allthesnacks:BAAANQAECggIEQAAAA==.Aloe:BAAANQADCgYICQAAAA==.',
Am='Amarynth:BAAANQADCgQIBAAAAA==.Amäri:BAACNQAFFH8IAAICAAIK1yIFIwDIAAACAAIK1yIFIwDIAAA1AAQKfxoAAwIACAoiJGYhAOkCAAIACAoQJGYhAOkCAAkABArUGMEQAB0BAAAA.',
An='Anassand:BAABNQAECn8YAAMKAAkKPB1KJgDpAQAKAAgKsRpKJgDpAQALAAYKBBl+WgCmAQABNQAECgkJHQAMABkUAA==.Anatomic:BAAANQADCgIIAgABNQAECgcIKwACAOcPAA==.Andicandy:BAAANQAECgYIBwABNQAECgkJJAANAK4XAA==.Andimorph:BAABNQAECn8kAAINAAkKrhcvMQBYAgANAAkKrhcvMQBYAgAAAA==.Angeleria:BAAANQADCgUIBQAAAA==.',
Ap='Apazz:BAABNQAECn81AAIFAAkKUxXIbQA3AgAFAAkKUxXIbQA3AgAAAA==.',
Aq='Aqualight:BAAANQAECgcIDAABNQAECgoKNAAOAGgkAA==.Aquashade:BAAANQAECgUIBQABNQAECgoKNAAOAGgkAA==.Aquaterra:BAABNQAECn80AAIOAAoKaCSuDQBTAwAOAAoKaCSuDQBTAwAAAA==.Aquina:BAAANQAECgcIDQABNQAECgoKNAAOAGgkAA==.',
Ar='Arakadia:BAABNQAECn9LAAMLAAoKLRYkIgCdAQALAAoKSxMkIgCdAQAPAAMKxRpaeQBeAAAAAA==.Arcaina:BAAANQAECgQIBwAAAA==.Artoriaz:BAAANQADCgcJCwAAAA==.Aruteeru:BAABNQAECn8lAAMQAAkKpRhXGAD5AQAQAAkKpRhXGAD5AQARAAgKIhMZLwCeAQAAAA==.',
As='Aseanna:BAABNQAECn8ZAAMSAAkKKhHmGgCEAQASAAkKKhHmGgCEAQACAAIKHw/PyABhAAAAAA==.Astraen:BAAANQADCgQIBgAAAA==.',
At='Athira:BAAANQABCgIIAgAAAA==.',
Au='Augmentussy:BAAANQADCggICAABNQAECgoKKwARAI0lAA==.Auxiliater:BAAANQADCgEIAQAAAA==.Auxiliator:BAAANQADCgYIBgAAAA==.Auxlox:BAAANQADCgcIBwAAAA==.Auxshadow:BAAANQABCgIIAgABNQADCgYIBgATAAAAAA==.',
Av='Avarous:BAABNQAECn8zAAMCAAkK9xohKgBtAgACAAkK9xohKgBtAgASAAEKAABvigAgAAAAAA==.Avataroffury:BAAANQAECgQIBAABNQAECgkJHQAMABkUAA==.',
Ax='Axará:BAAANQADCgQIBAAAAA==.Axel:BAAANQADCgUIBwAAAA==.',
Ay='Ayala:BAACNQAFFH8OAAIDAAUKLh0cEgAvAQADAAUKLh0cEgAvAQA1AAQKfx8AAgMACgpsJOgdAMsCAAMACgpsJOgdAMsCAAAA.',
Az='Azaireos:BAAANQADCgYIDQAAAA==.Azulpunkt:BAABNQAECn8kAAIUAAoK/hdKDgD6AQAUAAoK/hdKDgD6AQAAAA==.',
Ba='Baddaboomkin:BAAANQADCgEIAQAAAA==.Bananashamma:BAAANQAECgcIEQAAAA==.Barbedwire:BAAANQAECggICwAAAA==.',
Be='Bearmao:BAABNQAECn9FAAIFAAoKHyHYFQDQAgAFAAoKHyHYFQDQAgAAAA==.Belfas:BAAANQAECgQIBQAAAA==.Belladon:BAAANQAECgMIAwABNQAECgcIEgATAAAAAA==.Bellah:BAAANQABCgIIAgAAAA==.Bellybutton:BAABNQAECn8UAAIUAAcKSwp+HgD5AAAUAAcKSwp+HgD5AAAAAA==.',
Bi='Bigpeach:BAAANQADCgEIAQAAAA==.Biltong:BAABNQAECn8eAAIVAAkKuBHtRgDFAQAVAAkKuBHtRgDFAQAAAA==.',
Bl='Blackpink:BAAANQADCgUIBQAAAA==.Bladesinger:BAAANQADCgYIBgAAAA==.Bludnite:BAACNQAFFH8GAAIPAAQKCQrmFACaAAAPAAQKCQrmFACaAAA1AAQKfyoABA8ACQq/GpUuAFkCAA8ACApGHZUuAFkCAAsAAQoQCbN7ADUAAAoAAQpkAzCoACQAAAAA.',
Bo='Bokchoi:BAAANQAECgUIBQAAAA==.Boom:BAAANQADCgQICAAAAA==.',
Br='Brey:BAAANQAECgcICwAAAA==.Bruute:BAABNQAECn9CAAIMAAoKDyPQFQBiAwAMAAoKDyPQFQBiAwAAAA==.',
Bu='Budplatinum:BAABNQAECn8bAAIWAAcKBQUEFADGAAAWAAcKBQUEFADGAAAAAA==.',
['Bâ']='Bâït:BAAANQAECggIBwAAAA==.',
['Bå']='Båcon:BAAANQAECgEIAQAAAA==.',
Ca='Cairo:BAABNQAECn8nAAMXAAkK9iC5CwB+AgAMAAkKPxxiVACNAgAXAAcKFiO5CwB+AgAAAA==.Calai:BAAANQADCggICAAAAA==.Capitalchaos:BAABNQAECn89AAMYAAkKthaGCwAKAgAYAAkKthaGCwAKAgAMAAEKDgYZVgEwAAABNQAECgoKNwABAFQSAA==.Capnbeni:BAAANQADCgMIAwAAAA==.Cassandraa:BAAANQADCgQIBwAAAA==.Castingchaos:BAABNQAECn83AAIBAAoKVBLHpgA0AgABAAoKVBLHpgA0AgAAAA==.',
Ce='Cell:BAABNQAECn81AAIZAAoKiSJvAgBdAwAZAAoKiSJvAgBdAwAAAA==.Ceviche:BAAANQAECggIEQAAAA==.Ceàrrdòrn:BAABNQAECn8jAAIDAAgK+BTfyACKAQADAAgK+BTfyACKAQAAAA==.',
Ch='Chibí:BAAANQADCggIFgABNQAECggIDgATAAAAAA==.Chillzmatic:BAAANQAECgIIBgAAAA==.Chirri:BAAANQADCgcIBwAAAA==.Chudbucket:BAABNQAECn8eAAMFAAgKyBq/jQDuAQAFAAcKbh2/jQDuAQAaAAMKJQ6MZwCOAAAAAA==.',
Ci='Cica:BAAANQAECgMIAwAAAA==.Cirillø:BAAANQAECgYICQABNQAECgoKRAAbAMMlAA==.',
Cl='Clobbopus:BAAANQAECgEIAQAAAA==.Clovergold:BAACNQAFFH8KAAIDAAQKoQyzEwDIAAADAAQKoQyzEwDIAAA1AAQKfygAAgMACgozGjtPAKcCAAMACgozGjtPAKcCAAAA.Clyde:BAABNQAECn8bAAMcAAcKgQyLMQASAQAcAAcKgQyLMQASAQAdAAMKMgSZNgBmAAAAAA==.',
Co='Confearacy:BAAANQAECggICAAAAA==.Corbis:BAABNQAECn8WAAMLAAcKSQ12gAAbAQALAAYKIw52gAAbAQAKAAUK/AavdgDIAAAAAA==.Cowpuss:BAAANQAECgEIAQABNQAECgcIEgATAAAAAA==.',
Cr='Creekdeath:BAAANQAECggICAAAAA==.Crevarus:BAAANQADCgUJDAAAAA==.Crimsonjeybi:BAAANQAECgcICAAAAA==.Crunchwich:BAAANQAECgUIDgAAAA==.Cryos:BAAANQAECgIIAQAAAA==.',
Cu='Cutename:BAAANQAECgQIBAAAAA==.',
Cy='Cy:BAAANQAECgUIBQABNQAECgoKJQADAAYjAA==.Cynamyn:BAAANQAECgUIDgAAAA==.',
Cz='Czeskilight:BAAANQADCgIIAgAAAA==.',
['Cö']='Cömet:BAAANQADCgcICAAAAA==.',
Da='Daane:BAAANQADCgYIDQAAAA==.Dabadwarrior:BAAANQAECgUIBQAAAA==.Daevarys:BAAANQAECgEIAQAAAA==.Dakhran:BAAANQADCgIIBAAAAA==.Dakkä:BAAANQADCggIBwAAAA==.Dan:BAABNQAECn80AAIKAAoKzhplHQCfAgAKAAoKzhplHQCfAgAAAA==.Danthrax:BAABNQAECn8cAAIYAAoKIhjpBgAUAgAYAAoKIhjpBgAUAgAAAA==.Darkdemon:BAABNQAECn8hAAIeAAcK3gjePwBNAQAeAAcK3gjePwBNAQAAAA==.Darlord:BAAANQAECgMIBgAAAA==.Dawnliht:BAAANQADCgIIAgAAAA==.',
De='Deagle:BAAANQABCgIIBAABNQAECgoKKwARAI0lAA==.Deandrya:BAAANQAECggIDwAAAA==.Deedubbya:BAAANQADCgcIBwAAAA==.Delryd:BAAANQAECgQICgAAAA==.Demonetized:BAAANQAECgQIBAAAAA==.Demônlock:BAAANQAECgcIDgAAAA==.Desideria:BAABNQAECn8wAAMfAAkKZQ3ECACBAQAfAAkKZQ3ECACBAQAEAAIK0gcuLAFlAAAAAA==.Despondence:BAACNQAFFH8HAAIeAAMKmhR0DQDUAAAeAAMKmhR0DQDUAAA1AAQKf0MAAx4ACgrLIBsHAGADAB4ACgrLIBsHAGADABkAAgq/GM8kAEgAAAAA.Desynn:BAAANQAECgYJDgAAAA==.',
Di='Divinesyn:BAAANQAECgcICQAAAA==.Divonah:BAAANQADCgQIBAAAAA==.',
Dj='Djelysium:BAAANQAECgQIBwAAAA==.Djtaki:BAABNQAECn88AAIHAAoK/hsiDwCyAQAHAAoK/hsiDwCyAQAAAA==.',
Do='Dogwater:BAAANQADCgYIBgABNQAFFAcIGQAdAM8fAA==.Doncarlos:BAACNQAFFH8MAAIFAAMKAQbNEwDPAAAFAAMKAQbNEwDPAAA1AAQKf08AAgUACgrHH8MUAEsDAAUACgrHH8MUAEsDAAAA.Dorn:BAAANQAECgEIAQAAAA==.Dotty:BAAANQAECgEIAQAAAA==.Dottzz:BAAANQADCgYIBgAAAA==.Downbeatxo:BAECNQAFFH8ZAAMgAAcKURRRAwDgAAAEAAUKhBqIDgCQAQAgAAMKOhBRAwDgAAA1AAQKfzgAAwQACgpSIy0MAPACAAQACgpSIy0MAPACACAABAomGmAtABcBAAAA.',
Dr='Dragonswòrd:BAAANQADCggICAAAAA==.Drdevoted:BAAANQADCgIIAgAAAA==.Drippie:BAAANQADCgcIGQAAAA==.Dròòid:BAAANQADCgQJBAABNQAFFAQIBgAPAAkKAA==.',
Du='Dubdred:BAAANQAECgIIAgAAAA==.Duhon:BAAANQADCgQIBAAAAA==.Dumptruck:BAAANQAECggIEQABNQAECgoKJQADAAYjAA==.',
Dw='Dwín:BAABNQAECn8dAAIFAAoKQgabtACbAQAFAAoKQgabtACbAQAAAA==.',
['Dê']='Dêals:BAABNQAECn8hAAIVAAgKOxqTRwBIAgAVAAgKOxqTRwBIAgAAAA==.',
['Dü']='Dümpy:BAAANQADCgMIAwAAAA==.',
Ed='Edgelordxx:BAAANQAECgEIAgAAAA==.',
Ee='Eev:BAAANQADCgIIAgAAAA==.',
El='Elasper:BAAANQADCgcICQAAAA==.Eliselyia:BAAANQAECgEIAQAAAA==.Ellierose:BAABNQAECn8YAAICAAoKGwe+igB2AQACAAoKGwe+igB2AQAAAA==.',
Em='Emelianas:BAAANQAECgQICAABNQAECgoKSwALAC0WAA==.Ems:BAAANQAECgIIAgAAAA==.',
En='Enaelna:BAAANQAECgEIAQAAAA==.Enjin:BAABNQAECn9FAAMFAAoKNiOjCgAhAwAFAAoKNiOjCgAhAwAGAAMK/RyJDgC7AAAAAA==.Enragedbeef:BAAANQAECgUIBQABNQAFFAQIBwACAO8JAA==.Entheogen:BAABNQAECn8oAAMhAAgKVhBgRQCFAQAhAAgKVhBgRQCFAQAOAAQK7hPkxwDYAAAAAA==.',
Eo='Eogan:BAAANQADCgIIAwAAAA==.',
Ep='Epichuntard:BAAANQAECgQICQAAAA==.',
Er='Erolas:BAAANQADCgQIBwAAAA==.',
Es='Essay:BAABNQAECn8jAAIFAAoKRBurOQAyAgAFAAoKRBurOQAyAgAAAA==.',
Et='Ethereall:BAABNQAECn8XAAMeAAkKxRisHABwAgAeAAkKxRisHABwAgAiAAMKOQH4kQA3AAAAAA==.',
Eu='Eudora:BAAANQADCggICAABNQAECgoKKwARAI0lAA==.',
Ev='Evalilly:BAAANQADCgYIBgAAAA==.Evanessance:BAAANQADCgYIBwAAAA==.Evilice:BAABNQAECn88AAIDAAkK/xFxdwCfAQADAAkK/xFxdwCfAQAAAA==.Evoka:BAABNQAECn8eAAIjAAgKbg5REgCUAQAjAAgKbg5REgCUAQAAAA==.',
Fa='Faavibear:BAAANQAECggIAQAAAA==.Fallendevout:BAAANQAECgUICAAAAA==.Fallentroll:BAABNQAECn8dAAMLAAkKmhlKPQAqAgALAAkKKBlKPQAqAgAPAAMK7Rw8jADQAAAAAA==.Fatdoinkers:BAABNQAECn8lAAQDAAoKBiOaKACXAgADAAoKBiOaKACXAgAVAAIKowxvvgBsAAAbAAIKjhmNZwBFAAAAAA==.Fatman:BAAANQADCgcICAABNQADCgIIAwATAAAAAA==.Faydark:BAAANQADCgQIBAAAAA==.Fayia:BAAANQADCggIDgAAAA==.Fayye:BAABNQAECn8dAAIVAAcKdg+YXgBrAQAVAAcKdg+YXgBrAQAAAA==.',
Fe='Felbeks:BAAANQAECgQIBAABNQAECgoKMQAPAF8gAA==.',
Fi='Fireflydh:BAAANQADCgYIBgABNQAECgoKIAAfAPcSAA==.Firragol:BAAANQABCgYICgAAAA==.Firèflyjd:BAABNQAECn8gAAQfAAoK9xIMFACyAAAEAAcKmxCrjQAKAQAfAAQKKw8MFACyAAAgAAIK4xdFGwBwAAAAAA==.Fishstick:BAAANQADCggIGAAAAA==.',
Fl='Floatpass:BAACNQAFFH8IAAIBAAMK4hw4FwAFAQABAAMK4hw4FwAFAQA1AAQKfz4AAgEACgqBI30gAFgDAAEACgqBI30gAFgDAAAA.',
Fo='Foot:BAAANQADCgcJCQAAAA==.',
Fr='Frizz:BAAANQAECgQIBwAAAA==.Froey:BAEANQAECgMIAwAAAA==.',
Fu='Fuzzypally:BAABNQAECn8cAAIVAAoKfB+4IQDmAgAVAAoKfB+4IQDmAgAAAA==.Fuzzyshadow:BAAANQAECgQIBAAAAA==.Fuzzytotems:BAAANQAECgcIDgAAAA==.',
['Fá']='Fáavi:BAAANQAECgQIBAAAAA==.',
Ga='Gali:BAAANQADCgQJBAABNQAFFAQIBgAPAAkKAA==.Galiagante:BAAANQADCggJDAAAAA==.Gallynna:BAABNQAECn8tAAQEAAgKphLCewDxAQAEAAgKKRHCewDxAQAgAAMKVRCcWgBxAAAfAAMKhwuxJABcAAAAAA==.Galorfax:BAABNQAECn8tAAIcAAkK5h+/CwBLAgAcAAkK5h+/CwBLAgAAAA==.Galushi:BAAANQADCgYIDQAAAA==.Garm:BAABNQAECn87AAIFAAoKXiPiCwAWAwAFAAoKXiPiCwAWAwABNQAECgoKQgAMAA8jAA==.',
Ge='Gelinea:BAAANQADCgYIDQAAAA==.Gerlton:BAAANQADCgQIBAAAAA==.Gernar:BAAANQADCgUICwAAAA==.',
Gi='Gilgaroth:BAABNQAECn87AAMHAAoKTRrmEACZAQAIAAoK0BdKLQARAgAHAAgKLBnmEACZAQAAAA==.Girlslove:BAAANQADCgIIAgABNQAFFAcIGQAdAM8fAA==.',
Gn='Gnoskill:BAAANQADCgYIBgAAAA==.',
Go='Gobo:BAABNQAECn8WAAIhAAgKBRZEXwAEAgAhAAgKBRZEXwAEAgAAAA==.',
Gr='Graysonn:BAAANQADCggIGQAAAA==.Greafox:BAABNQAECn8mAAMOAAoKSiQQBgCVAwAOAAoKSiQQBgCVAwAhAAUKHxR/rgA2AQAAAA==.Grrimreaperr:BAAANQADCgcIBwAAAA==.Grýla:BAAANQADCgUIBQAAAA==.',
Gu='Guildenstern:BAABNQAECn8kAAMHAAoKRR8UBADUAgAHAAoKRR8UBADUAgAIAAIKZhgZrwBNAAABNQAFFAcIGQAdAM8fAA==.Gundrakk:BAAANQAECgYIEQAAAA==.Gunnr:BAAANQAECgUICQABNQAECggIDgATAAAAAA==.Gunthorian:BAAANQAECgMJAwAAAA==.',
Ha='Handsomemonk:BAAANQADCgMIBAABNQAECgoKJQADAAYjAA==.Hansi:BAAANQAECgMIAwAAAA==.Harbringer:BAAANQAECgUIBQABNQAECgkJHgAVALgRAA==.',
He='Heart:BAAANQAECgUIAwABNQAECgkJKgADAIsfAA==.Heid:BAAANQADCgYIDQAAAA==.Helldozer:BAAANQADCgcICQAAAA==.Heytherepal:BAAANQAECgQIBQAAAA==.',
Hi='Higanbana:BAACNQAFFH8hAAIeAAcKiB5JAgCCAQAeAAcKiB5JAgCCAQA1AAQKfzoAAh4ACgpoJPIFAHIDAB4ACgpoJPIFAHIDAAAA.Himawari:BAABNQAECn8gAAIDAAkKIiCTQwDKAgADAAkKIiCTQwDKAgABNQAFFAcIIQAeAIgeAA==.Himejoshi:BAACNQAFFH8ZAAIdAAcKzx9OAABwAgAdAAcKzx9OAABwAgA1AAQKf0oAAh0ACgrWJjIAAJkDAB0ACgrWJjIAAJkDAAAA.Hippocampus:BAABNQAECn8sAAIOAAkKUB+kDQAwAwAOAAkKUB+kDQAwAwAAAA==.Hirys:BAABNQAECn8XAAIIAAgKKxNvGwD7AQAIAAgKKxNvGwD7AQAAAA==.',
Ho='Holybeks:BAAANQAECgEIAgABNQAECgoKMQAPAF8gAA==.Holydaddy:BAAANQAECgYICQAAAA==.Holysmite:BAAANQAECgQIBAABNQAECggICwATAAAAAA==.Hoppadk:BAABNQAECn8xAAIPAAoKXyAlGgDdAgAPAAoKXyAlGgDdAgAAAA==.Hotdoggin:BAAANQADCgEIAQABNQAECgoKJQADAAYjAA==.Hotshotzz:BAAANQAECgMIAwABNQAECggIIwADAF0fAA==.',
Hu='Huntfosho:BAAANQAECgQIBgAAAA==.Huntsmedown:BAAANQADCgYICQAAAA==.',
['Há']='Háldrin:BAACNQAFFH8RAAMaAAUKoxq1CwDbAAAaAAQKiRy1CwDbAAAFAAEK8BT6JQBbAAA1AAQKfzAAAxoACgpfIsYLAB0DABoACgq1IcYLAB0DAAUAAQo0JnRCAVsAAAAA.',
['Hö']='Hölybeary:BAABNQAECn8gAAMVAAkKYAxSSADAAQAVAAkKYAxSSADAAQAbAAYK7QcRSwC/AAAAAA==.',
Ia='Iamprepared:BAAANQABCgEIAQAAAA==.',
Ic='Icybacon:BAAANQAECgQIBAAAAA==.Icëcrëam:BAAANQADCggICAAAAA==.',
Ih='Ihavegrass:BAABNQAECn8UAAMFAAYK6wz2AgH/AAAFAAYK6wz2AgH/AAAaAAEKswTnYwAtAAAAAA==.',
Im='Imbue:BAABNQAECn8yAAIZAAoKMh7HAwCJAgAZAAoKMh7HAwCJAgAAAA==.Imbuer:BAAANQAECgQICAAAAA==.',
In='Innil:BAABNQAECn8gAAICAAoKdiVCAgDHAwACAAoKdiVCAgDHAwAAAA==.Inora:BAAANQABCgMIAwAAAA==.',
It='Itzapazz:BAAANQADCggIFAAAAA==.',
Ja='Jaurel:BAAANQADCgMIAwAAAA==.',
Je='Jessiks:BAAANQAECgIIAgAAAA==.Jessix:BAAANQAECggIEwAAAA==.Jezebel:BAABNQAECn8qAAMEAAoKyRU6TgBpAgAEAAoK8xM6TgBpAgAgAAQKDxNsGQB3AAAAAA==.',
Ji='Jiaoe:BAAANQADCgEIAQAAAA==.Jimfowler:BAAANQADCgIIAgAAAA==.Jirito:BAAANQAECgMJAwAAAA==.',
Jo='Jomadead:BAABNQAECn8iAAIPAAgK6hSBIQDCAQAPAAgK6hSBIQDCAQABNQAECgoKGgAOAOgSAA==.Jomas:BAABNQAECn8aAAIOAAoK6BLpVQAQAgAOAAoK6BLpVQAQAgAAAA==.Jovaar:BAAANQADCgYIBgAAAA==.',
Ju='Judera:BAABNQAECn9AAAMDAAoKzBsUNwBaAgADAAoKzBsUNwBaAgAbAAEKYRJqWAAyAAAAAA==.',
Ka='Kaing:BAABNQAECn8mAAIYAAcKXw2UFgAyAQAYAAcKXw2UFgAyAQAAAA==.Kaladen:BAABNQAECn8dAAQkAAoK7CIpBwBQAwAkAAoK7CIpBwBQAwANAAEKlhIqrQA8AAAcAAEKvxccXQA7AAAAAA==.Kalec:BAAANQADCgUJBQAAAA==.Kalysti:BAAANQAECggIHAAAAQ==.Kaoticmagus:BAAANQABCgMIAwABNQADCgYIEwATAAAAAA==.Kaoticnature:BAAANQADCgYIEwAAAA==.Karolg:BAABNQAECn8bAAIPAAcKXRz5JQChAQAPAAcKXRz5JQChAQAAAA==.Katostrafic:BAABNQAECn8sAAMJAAoKmxUwCQDIAQAJAAcKcBUwCQDIAQACAAkKWhSyYQB/AQAAAA==.Katrynna:BAAANQADCgYIEwAAAA==.',
Ke='Kelarra:BAAANQADCgQIBgAAAA==.',
Kh='Khromscarin:BAACNQAFFH8MAAIZAAMK6xP3AQDEAAAZAAMK6xP3AQDEAAA1AAQKf0oAAxkACgotIisCAOsCABkACgotIisCAOsCAB4ABwrVDdc2AI0BAAAA.',
Ki='Killidan:BAABNQAECn8uAAIeAAoKpB3eEwDJAgAeAAoKpB3eEwDJAgAAAA==.Kirklees:BAAANQAECgUIBwAAAA==.Kitsuchan:BAABNQAECn8hAAQBAAoK0yLnSgDsAgABAAkKEiPnSgDsAgAlAAMK2iLtJADHAAAmAAEKAAAJDAAAAAABNQAECggIGgAiAC8kAA==.',
Kk='Kkthx:BAAANQADCgcIBwABNQAFFAQIBwACAO8JAA==.',
Ko='Kodama:BAABNQAECn8rAAIhAAkKUgskYQAnAQAhAAkKUgskYQAnAQAAAA==.Koi:BAAANQADCgcIEgABNQAECgkJLwAZABofAA==.Kookiemon:BAAANQAECgYIBwAAAA==.Kookiesplz:BAAANQADCggICAAAAA==.Kopili:BAAANQADCgUIBwAAAA==.',
Kr='Krekdas:BAAANQADCgUIBQAAAA==.Kromag:BAAANQADCgYIBgABNQAECgYIBgATAAAAAA==.',
Ku='Kunpochiken:BAAANQAECgQIBAABNQAECgoKLAAJAJsVAA==.',
Ky='Kyanna:BAAANQAECgUIDgAAAA==.Kyoshi:BAAANQAECgUIBQAAAA==.',
La='Lader:BAABNQAFFH8PAAIDAAkKtACZJgBPAAADAAkKtACZJgBPAAAAAA==.Ladifantasie:BAAANQAECgQIBAAAAA==.Laria:BAABNQAECn8VAAIeAAgKshWSJQAZAgAeAAgKshWSJQAZAgAAAA==.Laurebeth:BAAANQAFFAEIAQAAAA==.Laxinmedium:BAAANQADCgYIDQAAAA==.',
Le='Leenei:BAAANQAECgQIBwAAAA==.Lenlaar:BAAANQAECgcIEQAAAA==.Levande:BAACNQAFFH8KAAICAAMK1hCmGwDRAAACAAMK1hCmGwDRAAA1AAQKfzIAAwIACgoYIO4GAKUDAAIACgoYIO4GAKUDABIAAgq7DZ5DAG0AAAAA.',
Li='Lifeblume:BAAANQADCggIHAAAAA==.Lightnning:BAAANQAECgMIAwAAAA==.Lildevil:BAAANQADCgUIBgAAAA==.Lilithandria:BAAANQAECgcIEgAAAA==.Linamar:BAAANQAECgUICQAAAA==.',
Lo='Loaq:BAABNQAECn8yAAMCAAoK9hPbRgBSAgACAAoK9hPbRgBSAgAJAAMK4giBHACBAAAAAA==.Lockzrockz:BAAANQAECgUIAgAAAA==.Lodshan:BAAANQABCgEIAQAAAA==.Longbottom:BAAANQAECggICQABNQAECgoKJQADAAYjAA==.Loot:BAAANQAECggIEAAAAA==.Lorbert:BAAANQAECgQIBgABNQAECgoKKAAMADMVAA==.Lostalot:BAABNQAECn8xAAIFAAkK3hQGXwBZAgAFAAkK3hQGXwBZAgAAAA==.',
Lu='Luxæterna:BAABNQAECn9DAAIDAAoKvSA1MQByAgADAAoKvSA1MQByAgAAAA==.',
Ly='Lyphiara:BAAANQADCggIGgABNQAECgkJMwAQAGofAA==.',
Ma='Malice:BAABNQAECn8VAAMfAAgKghUnCgDYAQAfAAgKghUnCgDYAQAgAAIKZAUFaQBPAAAAAA==.Mandwandos:BAABNQAECn8bAAQOAAoKIBijdwClAQAOAAgKqBWjdwClAQAhAAkKtQpkjQCCAQAUAAEKAABGNgAAAAAAAA==.Maraliss:BAAANQAECgQIDQAAAA==.',
Me='Meiri:BAAANQADCgEIAQABNQAFFAMICAAXADESAA==.Melaunis:BAAANQAECgQIBQAAAA==.Meowzer:BAABNQAECn8dAAQNAAUKaRRXbAAZAQANAAUKZxFXbAAZAQAdAAQKtA0BLwCaAAAcAAUKrA/1QQCFAAABNQAFFAQIBwACAO8JAA==.Merginator:BAAANQAECgUIBgAAAA==.Meteora:BAACNQAFFH8IAAIXAAMKMRLsBADEAAAXAAMKMRLsBADEAAA1AAQKfx8AAhcACgoYG3wMAG0CABcACgoYG3wMAG0CAAAA.',
Mi='Mideel:BAAANQAECgUIDgAAAA==.Midesis:BAAANQAECgQIBQAAAA==.Midesisheals:BAAANQAECgIIAgAAAA==.Migolbearcow:BAABNQAECn86AAIcAAkKcRhEDwBwAgAcAAkKcRhEDwBwAgAAAA==.Missed:BAAANQAECgIJAwAAAA==.Missedweaver:BAAANQADCgYICAABNQAECgIJAwATAAAAAA==.Missrae:BAAANQADCggIFwAAAA==.',
Mk='Mk:BAEANQADCgIIAgABNQAECgoKNAARACEfAA==.',
Ml='Mlglock:BAAANQADCgMIAwAAAA==.',
Mo='Moiira:BAAANQAECgEIAQAAAA==.Monyshot:BAAANQADCgUICwAAAA==.Moondizzle:BAAANQAECgIIAgAAAA==.Mooniè:BAABNQAECn8dAAMlAAoK7wOqJADJAAAlAAoK7wOqJADJAAABAAUKqwH1GwFkAAAAAA==.Moosenuts:BAABNQAECn8UAAIEAAcKaBBTkgC5AQAEAAcKaBBTkgC5AQAAAA==.Moriavus:BAABNQAECn8qAAIfAAoKxxeyBACLAgAfAAoKxxeyBACLAgAAAA==.Morocha:BAABNQAECn8cAAIQAAgKDQ4JKQArAQAQAAgKDQ4JKQArAQAAAA==.Mortèm:BAAANQAECgIIAgAAAA==.Moxxie:BAAANQABCggIEwABNQAECgQIBAATAAAAAA==.',
Mu='Muragore:BAAANQAECgQICQAAAA==.',
My='Mychropien:BAABNQAECn8nAAMLAAoKAyHlIgC6AgALAAoKAyHlIgC6AgAPAAMKURtFggBNAAAAAA==.Myylus:BAAANQADCgYIFAAAAA==.',
['Mö']='Mökes:BAABNQAECn86AAIgAAoKmSQCAQCbAwAgAAoKmSQCAQCbAwAAAA==.',
Na='Nadroj:BAAANQADCggIIgAAAA==.Nancydru:BAABNQAECn8VAAIcAAYKohLrJgAWAQAcAAYKohLrJgAWAQAAAA==.Naosu:BAAANQADCggIEAAAAA==.Nax:BAAANQAECgUIDwAAAA==.Nazzersaurus:BAABNQAECn8aAAIkAAcKYxnYJQD0AQAkAAcKYxnYJQD0AQAAAA==.',
Ne='Nec:BAAANQAECgEIAQAAAA==.Necrøtic:BAABNQAECn8tAAMlAAkKOhPhCQDEAQAlAAkKOhPhCQDEAQABAAQKqgYijgGqAAAAAA==.Nekomata:BAAANQABCgIIAwAAAA==.Nekosmasta:BAAANQABCgIIAgAAAA==.Neodin:BAAANQAECgUICQAAAA==.Nevermiss:BAABNQAECn86AAIQAAkKuRg9DwDgAQAQAAkKuRg9DwDgAQAAAA==.',
Ni='Nightjewel:BAAANQADCgYIDQAAAA==.',
No='Notmewasyou:BAABNQAECn8hAAMNAAcKSANihwC1AAANAAcKSANihwC1AAAkAAQKpAGiYgA+AAAAAA==.',
Nu='Nuali:BAABNQAECn8rAAMDAAkKeBnHZABsAgADAAkKHRnHZABsAgAbAAgKBhE5IgAoAQAAAA==.Numi:BAAANQADCggIDQAAAA==.',
Od='Odysseus:BAAANQADCgUICQAAAA==.',
Ok='Okameshiz:BAAANQADCggIDQAAAA==.',
On='Onlyspins:BAAANQAECgYIBwAAAA==.',
Or='Orý:BAABNQAECn9EAAIhAAoK1hsbLADOAgAhAAoK1hsbLADOAgAAAA==.',
Os='Oslatem:BAAANQADCgcICQAAAA==.',
Ox='Oxosorrel:BAAANQABCggIEQAAAA==.',
Oz='Ozzmodious:BAAANQADCgcIEgAAAA==.',
Pa='Pajonn:BAAANQAECgcIBwAAAA==.Paladan:BAABNQAECn8tAAMbAAoKgCFfBwAtAwAbAAoKgCFfBwAtAwADAAMKaR/NAAGuAAAAAA==.Paladanny:BAAANQAECgQIBgAAAA==.Palagi:BAABNQAECn8jAAMdAAYKlgUbJwCKAAAdAAYKlgUbJwCKAAAkAAMKpwh0XABTAAAAAA==.Pallu:BAAANQADCgQIBAAAAA==.Pallyana:BAAANQAECgcIEQAAAA==.Pallyfosho:BAAANQAECgIIAgAAAA==.Pallymcbeall:BAAANQAECgMIBAAAAA==.Paprikaman:BAAANQAECgUIDgAAAA==.Parallax:BAAANQAECgEIAQAAAA==.Pariahrain:BAABNQAECn8fAAMbAAgKHxg8GwAUAgAbAAgKHxg8GwAUAgADAAIKyQKPhwFPAAABNQAFFAMIBgABADUIAA==.Parishealton:BAABNQAECn8hAAMkAAoKWCD0CQAnAwAkAAoKWCD0CQAnAwANAAMKvQFvpgBMAAAAAA==.Payday:BAAANQADCgYICwAAAA==.Pazzuzu:BAAANQADCgcICwAAAA==.',
Pe='Penjamin:BAAANQAECgQIBwABNQAECgoKJQADAAYjAA==.Perprotrus:BAAANQADCgQIBAABNQAFFAQIBgAPAAkKAA==.',
Ph='Phatboi:BAAANQAECgQIBwAAAA==.',
Po='Poulsbo:BAAANQAECgQIBAAAAA==.Powerup:BAAANQAECgQIBAAAAA==.Pozole:BAAANQAECgcIDQAAAA==.',
Pr='Prominence:BAABNQAECn8qAAIGAAoKOCGUAQDUAgAGAAoKOCGUAQDUAgAAAA==.Promisques:BAAANQAECgEIAQAAAA==.Protectapear:BAAANQABCgEIAQAAAA==.Prozak:BAABNQAECn8rAAIOAAkKixVSYgDnAQAOAAkKixVSYgDnAQAAAA==.Prozakmd:BAAANQADCggICAAAAA==.',
Pw='Pwomf:BAAANQAECggIEAAAAA==.',
Py='Pyneapple:BAAANQADCgQIBAABNQAFFAQIBwACAO8JAA==.Pyrolily:BAABNQAECn8VAAIlAAcKKQYwHwDxAAAlAAcKKQYwHwDxAAAAAA==.',
Qu='Question:BAAANQADCgIIAwAAAA==.Qulung:BAAANQADCggIFAAAAA==.',
Ra='Rabyd:BAAANQAECgIIAQAAAA==.Raegasm:BAAANQADCgYICwAAAA==.Raght:BAAANQAECgIIAgAAAA==.Raha:BAAANQAECgcIDQAAAA==.Ramue:BAAANQADCgcIDgAAAA==.Raskela:BAABNQAECn8cAAMQAAkKpxO3GADyAQAQAAkKpxO3GADyAQARAAcKdhQrMQCOAQAAAA==.Rastakan:BAAANQAECgUICQABNQAECgoKQgAMAA8jAA==.Razal:BAAANQADCggIDQAAAA==.',
Re='Reesespiecez:BAAANQAECgcJCwAAAA==.Rellidana:BAAANQAECgYICgAAAA==.Remove:BAAANQAECgUIBQAAAA==.Reprieve:BAAANQAECgUICQAAAA==.Retradormi:BAAANQAECgQIBQAAAA==.Rexi:BAABNQAECn8hAAISAAkKCg6VJwDuAQASAAkKCg6VJwDuAQAAAA==.',
Ri='Rickcando:BAABNQAECn8WAAIhAAYK2xRMbwDSAQAhAAYK2xRMbwDSAQAAAA==.Ricshard:BAABNQAECn8xAAQgAAgKRhT5GAB7AAAEAAUK1RQ1lAD7AAAgAAMKtBf5GAB7AAAfAAIKMAutJQA4AAAAAA==.Ridjeckgron:BAAANQADCgcICQAAAA==.Rissiia:BAAANQADCgQIBAAAAA==.',
Rm='Rmft:BAAANQAECgEIAQABNQAECgkJNAAMAGgXAA==.',
Ro='Roomnboard:BAAANQAECgMIAwAAAA==.Rotter:BAAANQADCgQIBAAAAA==.Roughluver:BAAANQAECgMIAgABNQAFFAQIBwACAO8JAA==.',
Ru='Ruben:BAAANQADCgEIAgAAAA==.Rungar:BAAANQAECgQICwAAAA==.',
Rv='Rvoker:BAAANQADCgQIBAAAAA==.',
Ry='Rylia:BAAANQADCgcICQAAAA==.Ryuk:BAAANQADCgMIAwAAAA==.Ryñ:BAAANQAECggIEwAAAA==.',
['Rà']='Ràein:BAABNQAECn8uAAMgAAgK5A5kBwAwAQAgAAgK5A5kBwAwAQAEAAEK0QJhDgEfAAAAAA==.',
['Ró']='Ród:BAABNQAECn8jAAIDAAgKXR9IbwBRAgADAAgKXR9IbwBRAgAAAA==.',
['Rø']='Røth:BAAANQADCgcIEgAAAA==.',
Sa='Saalira:BAAANQADCgcIEAAAAA==.Sabellice:BAABNQAECn80AAIDAAkKuxFMdQCkAQADAAkKuxFMdQCkAQAAAA==.Sakonna:BAABNQAECn8fAAISAAkKQRV8IAA1AgASAAkKQRV8IAA1AgAAAA==.Salinoria:BAAANQAECgQICQABNQAECgkJKwADAHgZAA==.Saltyfingers:BAAANQADCgcIBwAAAA==.Sandymaw:BAAANQADCgQIBAABNQAFFAQIBwACAO8JAA==.Sarlius:BAABNQAECn8+AAIFAAoKRyXpAgDYAwAFAAoKRyXpAgDYAwAAAA==.Sassybuns:BAAANQABCgQIBAAAAA==.Satyrical:BAABNQAECn8qAAIDAAkKix/wPgA9AgADAAkKix/wPgA9AgAAAA==.Savin:BAAANQAECgQICwAAAA==.',
Sc='Scavenger:BAAANQAECgYIDgAAAA==.Scorchin:BAAANQAECggICQAAAA==.Scrumptiøus:BAAANQAECgUICgABNQAECgoKLAAJAJsVAA==.',
Se='Selkamonk:BAABNQAECn8zAAMQAAkKah/0CgDXAgAQAAkKah/0CgDXAgARAAIKDgZIVgArAAAAAA==.Seniorbold:BAABNQAECn8cAAIDAAoK9BezQgDMAgADAAoK9BezQgDMAgAAAA==.Sentrina:BAACNQAFFH8IAAIjAAUKJAx/DADUAAAjAAUKJAx/DADUAAA1AAQKfzUAAiMACgqYHSgNANMCACMACgqYHSgNANMCAAAA.Seraph:BAAANQAECgcIDAAAAA==.Seshy:BAACNQAFFH8HAAMCAAQK7wn2HADFAAACAAMKxwb2HADFAAASAAIKTQctDgCBAAA1AAQKf0MAAwIACgooF9BNADsCAAIACgooF9BNADsCABIACQr1FyYgADkCAAAA.Seshymutedme:BAAANQAECggIEQABNQAFFAQIBwACAO8JAA==.',
Sh='Shamanagins:BAAANQADCgEIAQAAAA==.Shannon:BAAANQADCgYIBgABNQAECgcIHQAVAHYPAA==.Shannoon:BAABNQAECn8eAAIbAAcK9QgwMQDFAAAbAAcK9QgwMQDFAAAAAA==.Sharr:BAAANQADCgYJDAAAAA==.Shekzeer:BAABNQAECn8rAAQRAAoKjSXlAADnAwARAAoKjSXlAADnAwAQAAYK0hzxGgDSAQAnAAMK8yALIwC/AAAAAA==.Shiverr:BAABNQAECn8oAAIlAAgKLgcmGQAtAQAlAAgKLgcmGQAtAQAAAA==.Shockakan:BAAANQABCgQIBAAAAA==.Shockazulu:BAAANQADCgIIAgAAAA==.Shocktard:BAAANQAECgEIAQABNQAECgkJHQAMABkUAA==.',
Si='Siatraz:BAAANQAECgYIBQABNQAECgoKIAAfAPcSAA==.Siegatrox:BAAANQAECgIIAgAAAA==.Silgan:BAAANQADCgYIBgAAAA==.Silverbain:BAAANQADCgQIBAAAAA==.Sinnon:BAAANQAECgMIAwAAAA==.',
Sk='Skizem:BAAANQABCgcIEQAAAA==.Skott:BAAANQAECgQIBAAAAA==.Skïnnyßetch:BAAANQADCgcIBwAAAA==.',
Sl='Sleepadin:BAABNQAECn8ZAAIDAAoKegop0QB5AQADAAoKegop0QB5AQAAAA==.Sleepyr:BAAANQAECgYIDQAAAA==.',
Sm='Smokeymage:BAAANQAECgUICAAAAA==.',
Sn='Snowi:BAAANQADCgYIBgABNQAECggIDgATAAAAAA==.Snowstorm:BAAANQAECgEIAQAAAA==.',
So='Soakra:BAABNQAECn8jAAIOAAoK/hbaRABOAgAOAAoK/hbaRABOAgAAAA==.Solignis:BAACNQAFFH8pAAMYAAcKTSYPAAAOAgAYAAcKTSYPAAAOAgAMAAQK6R5WFACIAQA1AAQKf1QAAxgACgrzJgUAAB4EABgACgrzJgUAAB4EAAwACQqUJu8HALMDAAAA.Solxeen:BAAANQADCggICAAAAA==.Soniviolence:BAABNQAECn82AAIMAAoK0CBoGwBKAwAMAAoK0CBoGwBKAwAAAA==.Soohots:BAACNQAFFH8GAAIkAAMKmBoACQAJAQAkAAMKmBoACQAJAQA1AAQKfx4AAyQACQrgHYkUAKUCACQACArdHIkUAKUCAA0ABAovEOyNAJ8AAAAA.Sourskittlz:BAAANQADCgQIBAAAAA==.',
Sp='Sparklehappy:BAABNQAECn8YAAMaAAgKBhh9OgB8AQAaAAcKkxd9OgB8AQAFAAEKQRoJRgFTAAAAAA==.Splìff:BAAANQADCgYIBgAAAA==.Sppazz:BAAANQADCgcIBwAAAA==.',
St='Starshield:BAAANQAECgIIAgABNQAECgkJGAALAHYWAA==.Stausa:BAAANQADCgcIBwAAAA==.Steeljustice:BAAANQAECggICAAAAA==.Stormcreek:BAABNQAECn8hAAMOAAcKpha7YwBZAQAOAAcKpha7YwBZAQAhAAIKnQKN7QApAAAAAA==.Storri:BAABNQAECn9NAAMCAAoKWxoqHwCzAgACAAoKWxoqHwCzAgASAAUKwgYbVAC9AAAAAA==.',
Su='Sufferinhero:BAAANQAECgEIAQABNQAFFAMIDAAZAOsTAA==.Suzuya:BAAANQAECgEIAQAAAA==.',
Sv='Svetty:BAAANQAECgYIBgAAAA==.',
Sw='Swiftly:BAAANQAECgcIEAAAAA==.Swiftmage:BAACNQAFFH8pAAMlAAcKhiUqAAALAgAlAAcKhiUqAAALAgABAAUKvR0cGgCpAQA1AAQKf0oAAyUACgruJg8AAAcEACUACgruJg8AAAcEAAEACQoqJeMYAHEDAAAA.Switchboard:BAAANQADCgYICgAAAA==.',
Sx='Sxkittn:BAAANQADCgcICwAAAA==.',
Sy='Sygh:BAAANQAECgEIAQABNQAECgkJKgADAIsfAA==.Syltru:BAAANQADCgUIBQAAAA==.Syndragonkin:BAABNQAECn8yAAIFAAgKcBccfAAWAgAFAAgKcBccfAAWAgAAAA==.Syndrome:BAAANQADCggIDgAAAA==.Synger:BAAANQADCgYIEAAAAA==.',
Ta='Taima:BAAANQABCgEIAQAAAA==.Talyndis:BAACNQAFFH8gAAIaAAkKhBy7AgB4AgAaAAkKhBy7AgB4AgA1AAQKfzsAAhoACgo4JVQDABkDABoACgo4JVQDABkDAAAA.Tamyr:BAAANQADCgIIAgAAAA==.Tazadar:BAAANQADCggIIQAAAA==.Taze:BAAANQAECgUJBwABNQAFFAQIBgAPAAkKAA==.Tazjiingo:BAAANQADCgIIBAAAAA==.',
Te='Terrika:BAABNQAECn8jAAIFAAgKwQrxigD0AQAFAAgKwQrxigD0AQAAAA==.Tetshajeh:BAACNQAFFH8MAAIMAAMKLBZ6FADdAAAMAAMKLBZ6FADdAAA1AAQKf1UAAwwACgp6IsYTAO8CAAwACgp6IsYTAO8CABcAAwrQGOIrANkAAAAA.Teyliana:BAAANQAECgYIDgAAAA==.',
Th='Thebigchud:BAAANQAECgUICAAAAA==.Thillarick:BAABNQAECn80AAIMAAkKaBdcTQDlAQAMAAkKaBdcTQDlAQAAAA==.Thiss:BAAANQABCgYIAwAAAA==.Thromanor:BAAANQAECgUIBAAAAA==.Thwip:BAABNQAECn85AAMFAAoKRCGaLADoAgAFAAoKRCGaLADoAgAaAAkKChUMEAAKAgAAAA==.Thänatøs:BAAANQAECgEIAQAAAA==.',
Ti='Tikwid:BAABNQAECn8lAAIBAAgKhwUywwD3AAABAAgKhwUywwD3AAAAAA==.Tiranmyashol:BAABNQAECn8oAAIMAAoKMxXcaABVAgAMAAoKMxXcaABVAgAAAA==.',
To='Tomoya:BAAANQAECgcIEgAAAA==.Too:BAAANQAECgIIAQAAAA==.Toothdk:BAAANQAECgUIEgAAAA==.Torfnar:BAAANQAECgcIDgAAAA==.Tormmentor:BAAANQAECgQIDQAAAA==.',
Tr='Treebreak:BAAANQAECgUIDwAAAA==.',
Tu='Tugmydangle:BAAANQAECgQIBAAAAA==.',
Ty='Tyrandrea:BAAANQADCgcICQAAAA==.',
['Tô']='Tôxin:BAAANQAECggIBgAAAA==.',
Ud='Udari:BAAANQAECgcICwAAAA==.Udarii:BAAANQAECgcICQAAAA==.',
Um='Umàdbrah:BAABNQAECn8zAAIFAAgKpCDJKABxAgAFAAgKpCDJKABxAgAAAA==.',
Un='Unbelievable:BAABNQAECn8mAAIiAAkKSQr5MABSAQAiAAkKSQr5MABSAQAAAA==.Unprovoked:BAABNQAECn8iAAIBAAkKwh5dVwDRAgABAAkKwh5dVwDRAgAAAA==.',
Va='Valamor:BAABNQAECn8xAAMbAAgKRhHBGgBlAQAbAAgKRhHBGgBlAQAVAAUK4Ae1zQDgAAAAAA==.Varenea:BAAANQADCgYIBgAAAA==.Varia:BAAANQAECgEIAQABNQAECgkJHQAMABkUAA==.',
Ve='Veefib:BAABNQAECn8xAAMhAAkKbBnjQAByAgAhAAkKbBnjQAByAgAOAAIKpwrhxABjAAAAAA==.Velicerus:BAAANQAECgQIBAAAAA==.Velvettwitch:BAABNQAECn8sAAIgAAkKxRFzBQBmAQAgAAkKxRFzBQBmAQAAAA==.Vendler:BAAANQAECgcIEQAAAA==.Verahla:BAAANQAECgEIAQAAAA==.Vermis:BAABNQAECn83AAIKAAoKxxA/LADDAQAKAAoKxxA/LADDAQAAAA==.Veryaverage:BAABNQAECn8hAAMBAAgKkxE5ZQC9AQABAAgKkxE5ZQC9AQAmAAMKaAkOBgCVAAAAAA==.Vexation:BAAANQAECgQIBwAAAA==.',
Vi='Vicarious:BAACNQAFFH8GAAIOAAMKDQYcGACxAAAOAAMKDQYcGACxAAA1AAQKfywAAg4ACgoBHKMvADECAA4ACgoBHKMvADECAAAA.Vidreaux:BAABNQAECn86AAMBAAkKKgzvggB0AQABAAkKmAvvggB0AQAlAAIKDwvVKQBkAAAAAA==.Villaraa:BAAANQADCgEIAQAAAA==.Vivid:BAAANQAECgQIBAAAAA==.',
Vo='Voidofvoids:BAAANQAECgYICwAAAA==.Volke:BAAANQAECgUICQAAAA==.Volkennoria:BAAANQADCgcIBwABNQAECggIKQAFADobAA==.Votingromney:BAAANQAECgcICgABNQAECgoKKwARAI0lAA==.Vowz:BAAANQADCgMIAwAAAA==.',
Vu='Vulpe:BAABNQAECn8pAAIFAAgKOht1XABgAgAFAAgKOht1XABgAgAAAA==.',
Vy='Vyolenta:BAAANQADCgIIAgAAAA==.',
['Vë']='Vëxhunter:BAAANQAECggICwAAAA==.',
Wa='Waldorf:BAAANQAECgUICAAAAA==.Wallegator:BAAANQAECgEIAQABNQAECggILwAkAE0gAA==.Walleroot:BAAANQAECgUIBQABNQAECggILwAkAE0gAA==.',
We='Weinersoup:BAAANQAECgQIDAAAAA==.',
Wh='Whitewhitch:BAAANQADCgIIAwAAAA==.Whosethetank:BAAANQAECgMIBwAAAA==.',
Wo='Wolfpup:BAAANQAECggICwABNQAECgoKQAADAMwbAA==.Wolfíe:BAAANQADCgUIBQAAAA==.Worstelf:BAABNQAECn8kAAMCAAgKPyEYQABqAgACAAgKPyEYQABqAgASAAYKgiIAIgAlAgAAAA==.',
Ww='Wwalle:BAAANQAECgEIAgABNQAECggILwAkAE0gAA==.Wwallee:BAAANQADCgMIAwABNQAECggILwAkAE0gAA==.',
Xa='Xanathos:BAAANQAECgcICwABNQAECgoKPgAFAEclAA==.',
Xi='Xilstar:BAAANQADCgUIBQAAAA==.',
Xz='Xzavier:BAAANQADCgYIDQAAAA==.',
Yf='Yfelshammy:BAABNQAECn80AAIOAAoKiBUMTAAzAgAOAAoKiBUMTAAzAgAAAA==.',
Yv='Yvaldi:BAAANQAECgYIBgABNQAFFAIICAACANciAA==.Yvonnél:BAAANQAECgEIAQABNQAECgcIEgATAAAAAA==.',
Za='Zaknafein:BAAANQAECgUICQAAAA==.Zanebusby:BAABNQAECn8xAAIgAAoKsx5pAwAOAwAgAAoKsx5pAwAOAwAAAA==.Zankru:BAAANQADCgYIBwAAAA==.Zaraë:BAAANQADCggIDgAAAA==.Zaria:BAAANQAECgcIDgABNQAECgoKKwARAI0lAA==.Zartash:BAABNQAECn8UAAIeAAgK3ANSNwCvAAAeAAgK3ANSNwCvAAAAAA==.Zatharis:BAAANQAECgQIEQAAAA==.',
Ze='Zelik:BAAANQAECgYICgABNQAECgoKPgAFAEclAA==.Zenezin:BAAANQAECgMIAwABNQAECgkJHQAMABkUAA==.Zerax:BAAANQAECgYIEQABNQAECgoKQgAMAA8jAA==.Zevellian:BAAANQADCggIDgABNQAECgcIEQATAAAAAA==.',
Zm='Zmona:BAABNQAECn8dAAIMAAkKGRSjhQAOAgAMAAkKGRSjhQAOAgAAAA==.',
Zo='Zolrath:BAAANQABCgQIAgAAAA==.',
['Ãm']='Ãmpstar:BAAANQAECgEIAQAAAA==.',
['Äm']='Ämpstarr:BAAANQADCgEIAQAAAA==.',
['Çy']='Çyanide:BAAANQADCgQICgABNQAECgkJKgADAIsfAA==.',
['Ðr']='Ðragonshaft:BAABNQAECn85AAIFAAkKHxXbVQDdAQAFAAkKHxXbVQDdAQAAAA==.Ðreadlokz:BAAANQADCgQIBAAAAA==.',
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
