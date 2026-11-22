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

local lookup = {'Mage-Arcane','Priest-Holy','Paladin-Retribution','Warlock-Demonology','Hunter-BeastMastery','Hunter-Survival','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','DeathKnight-Frost','DeathKnight-Unholy','Druid-Balance','Paladin-Holy','Shaman-Restoration','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','Priest-Shadow','Paladin-Protection','Unknown-Unknown','Shaman-Enhancement','DemonHunter-Havoc','Warrior-Arms','Evoker-Devastation','Warrior-Protection','Warrior-Fury','DemonHunter-Vengeance','Hunter-Marksmanship','Druid-Guardian','Druid-Feral','DemonHunter-Devourer','Evoker-Augmentation','Warlock-Destruction','Warlock-Affliction','Shaman-Elemental','Evoker-Preservation','Druid-Restoration','Mage-Frost','Mage-Fire','Monk-Brewmaster',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aarazi:BAABNQAECn8+AAIBAAoKnxyMRQD4AgABAAoKnxyMRQD4AgAAAA==.',
Ab='Abbinormal:BAAANQADCggIHwAAAA==.',
Ad='Adïrael:BAAANQABCggIFQAAAA==.',
Ae='Aeriss:BAAANQADCggIDgAAAA==.Aethena:BAAANQADCgUIBQABNQAECgcIMwACAEsVAA==.Aezili:BAAANQADCgcIDQAAAA==.',
Ag='Agamotto:BAAANQADCgMIAwAAAA==.Agerol:BAABNQAECn88AAIDAAoK6B0XNgCMAgADAAoK6B0XNgCMAgAAAA==.',
Ah='Ahaego:BAABNQAECn8mAAIEAAkKZhAGXQC9AQAEAAkKZhAGXQC9AQAAAA==.Ahnari:BAAANQAECgIIAgAAAA==.',
Ak='Akkadien:BAAANQAECgcIEQAAAA==.Akumunter:BAABNQAECn9CAAMFAAoKIx1HKwDsAgAFAAoKIx1HKwDsAgAGAAcKGwzlCQA9AQAAAA==.',
Al='Alacardias:BAABNQAECn8yAAIDAAoK8xu9RADGAgADAAoK8xu9RADGAgAAAA==.Alette:BAAANQAECgMIAwAAAA==.Alihuntress:BAAANQADCgQIBQAAAA==.Alleril:BAABNQAECn8kAAMHAAoKkRI2DgDmAQAHAAkKmRA2DgDmAQAIAAkKbQ9TXgCRAQAAAA==.Allthesnacks:BAAANQAECggIEQAAAA==.Aloe:BAAANQADCgYICQAAAA==.',
Am='Amarynth:BAAANQADCgQIBAAAAA==.Amäri:BAACNQAFFH8IAAICAAIK1yIFIwDIAAACAAIK1yIFIwDIAAA1AAQKfxoAAwIACAoiJGYhAOkCAAIACAoQJGYhAOkCAAkABArUGMEQAB0BAAAA.',
An='Anassand:BAABNQAECn8fAAMKAAkKkx0pGgB4AgAKAAkKFxspGgB4AgALAAYKBBl+WgCmAQAAAA==.Anatomic:BAAANQADCgIIAgABNQAECgcIMwACAEsVAA==.Andicandy:BAABNQAECn8UAAIEAAkKyRWdTgDoAQAEAAkKyRWdTgDoAQABNQAECgkJJAAMAK4XAA==.Andimorph:BAABNQAECn8kAAIMAAkKrhcvMQBYAgAMAAkKrhcvMQBYAgAAAA==.Angeleria:BAAANQADCgUIBQAAAA==.',
Ap='Apazz:BAABNQAECn9BAAIFAAoKcRVHTwAvAgAFAAoKcRVHTwAvAgAAAA==.',
Aq='Aqualight:BAABNQAECn8eAAMNAAoKixrNFgABAwANAAoKixrNFgABAwADAAcK1Qa17ABDAQABNQAECgoKNQAOAGgkAA==.Aquashade:BAAANQAECgUIBQABNQAECgoKNQAOAGgkAA==.Aquaterra:BAABNQAECn81AAIOAAoKaCSuDQBTAwAOAAoKaCSuDQBTAwAAAA==.Aquina:BAAANQAECgcIDwABNQAECgoKNQAOAGgkAA==.',
Ar='Arakadia:BAACNQAFFH8FAAILAAIK3Ae1DQB+AAALAAIK3Ae1DQB+AAA1AAQKf1gAAwsACgoSGDocAAICAAsACgowFTocAAICAA8AAwrFGtulAIgAAAAA.Aravena:BAAANQADCgEIAQAAAA==.Arcaina:BAAANQAECgQICwAAAA==.Artoriaz:BAAANQADCgcJCwAAAA==.Aruteeru:BAABNQAECn8sAAMQAAkKpRhXGAD5AQAQAAkKpRhXGAD5AQARAAgKIhMZLwCeAQAAAA==.',
As='Aseanna:BAABNQAECn8pAAMSAAoKjhN4FgD7AQASAAoKjhN4FgD7AQACAAMKbwwszQCMAAAAAA==.Astariél:BAAANQAECgIIAgABNQAECgcIFwATABUJAA==.Astraen:BAAANQADCgQIBgAAAA==.',
At='Athira:BAAANQABCgIIAgAAAA==.',
Au='Augmentussy:BAAANQADCggICAABNQAECgoKKwARAI0lAA==.Auxiliater:BAAANQADCgEIAQAAAA==.Auxiliator:BAAANQADCgYIBgAAAA==.Auxlox:BAAANQADCgcIBwAAAA==.Auxshadow:BAAANQABCgIIAgABNQADCgYIBgAUAAAAAA==.',
Av='Avarous:BAABNQAECn9HAAMCAAoKORvJIADaAgACAAoKORvJIADaAgASAAEKAABvigAgAAAAAA==.Avataroffury:BAAANQAECgQIBAABNQAECgkJHwAKAJMdAA==.',
Ax='Axará:BAAANQADCgQIBAAAAA==.Axel:BAAANQADCgUIBwAAAA==.',
Ay='Ayala:BAACNQAFFH8OAAIDAAUKLh0cEgAvAQADAAUKLh0cEgAvAQA1AAQKfykAAgMACgoeJfIIAFUDAAMACgoeJfIIAFUDAAAA.',
Az='Azaireos:BAAANQADCggIDwAAAA==.Azulpunkt:BAABNQAECn8lAAIVAAoK/helEQBPAgAVAAoK/helEQBPAgAAAA==.',
Ba='Baddaboomkin:BAAANQADCgEIAQAAAA==.Bananashamma:BAAANQAECggIEgAAAA==.Barbedwire:BAAANQAECggICwAAAA==.',
Be='Bearmao:BAABNQAECn9MAAIFAAoKWCH4HQDJAgAFAAoKWCH4HQDJAgAAAA==.Belfas:BAAANQAECgQIBQAAAA==.Belladon:BAAANQAECgUICAABNQAECgkJFAAWABQZAA==.Bellah:BAAANQABCgIIAgAAAA==.Bellybutton:BAABNQAECn8UAAIVAAcKSwoQJAD3AAAVAAcKSwoQJAD3AAAAAA==.',
Bi='Bigpeach:BAAANQADCgEIAgAAAA==.Biltong:BAABNQAECn8iAAINAAkK8xQ8QgALAgANAAkK8xQ8QgALAgAAAA==.',
Bl='Blackpink:BAAANQADCgUIBgAAAA==.Bladesinger:BAAANQADCgYICAAAAA==.Blaupunkt:BAAANQADCgEIAQAAAA==.Bludnite:BAACNQAFFH8GAAIPAAQKCQpxHgCaAAAPAAQKCQpxHgCaAAA1AAQKfyoABA8ACQq/GpUuAFkCAA8ACApGHZUuAFkCAAsAAQoQCZKJADQAAAoAAQpkA6i/ACMAAAAA.',
Bo='Bokchoi:BAAANQAECgUIBQAAAA==.Boom:BAAANQADCgQICAAAAA==.',
Br='Brey:BAAANQAECgcICwAAAA==.Bruute:BAABNQAECn9FAAIXAAoKOyPQFQBiAwAXAAoKOyPQFQBiAwAAAA==.',
Bu='Budplatinum:BAABNQAECn8hAAIYAAgKLQXsFADnAAAYAAgKLQXsFADnAAAAAA==.',
['Bâ']='Bâït:BAAANQAECggIBwAAAA==.',
['Bå']='Båcon:BAAANQAECgEIAQAAAA==.',
Ca='Cairo:BAABNQAECn8nAAMZAAkK9iC5CwB+AgAXAAkKPxxiVACNAgAZAAcKFiO5CwB+AgAAAA==.Calai:BAAANQADCggICAAAAA==.Cammel:BAAANQADCgEIAQAAAA==.Capitalchaos:BAABNQAECn9BAAMaAAkKthaGCwAKAgAaAAkKthaGCwAKAgAXAAEKDgYZVgEwAAABNQAECgoKNwABAFQSAA==.Capnbeni:BAAANQADCgMIAwAAAA==.Cassandraa:BAAANQADCgQIBwAAAA==.Castingchaos:BAABNQAECn83AAIBAAoKVBLHpgA0AgABAAoKVBLHpgA0AgAAAA==.',
Ce='Cell:BAABNQAECn81AAIbAAoKiSJvAgBdAwAbAAoKiSJvAgBdAwAAAA==.Ceviche:BAABNQAECn8WAAIRAAkKWB/AEgA2AgARAAkKWB/AEgA2AgAAAA==.Ceàrrdòrn:BAABNQAECn8tAAMDAAkKoxTNqQB7AQADAAkKoxTNqQB7AQANAAEKTgO4DAEdAAAAAA==.',
Ch='Chibí:BAAANQADCggIFgABNQAECggIDgAUAAAAAA==.Chillzmatic:BAAANQAECgIIBgAAAA==.Chirri:BAAANQADCgcICwAAAA==.Chudbucket:BAABNQAECn8pAAMFAAgKKhyETQAzAgAFAAcKQiCETQAzAgAcAAMKJQ6MZwCOAAAAAA==.',
Ci='Cica:BAAANQAECgMIAwAAAA==.Cirillø:BAAANQAECgYICQABNQAECgoKRAATAMMlAA==.',
Cl='Clobbopus:BAAANQAECgEIAQAAAA==.Clovergold:BAACNQAFFH8KAAIDAAQKoQwuGgDCAAADAAQKoQwuGgDCAAA1AAQKfygAAgMACgozGjtPAKcCAAMACgozGjtPAKcCAAAA.Cluladin:BAAANQAECgMIAwABNQAECgoKNQARAMQdAA==.Clyde:BAABNQAECn8bAAMdAAcKgQyLMQASAQAdAAcKgQyLMQASAQAeAAMKMgSZNgBmAAAAAA==.',
Co='Coheed:BAAANQAECgEIAQABNQAECgoKGwADAFYLAA==.Confearacy:BAAANQAECggICAAAAA==.Corbis:BAABNQAECn8WAAMLAAcKSQ12gAAbAQALAAYKIw52gAAbAQAKAAUK/AavdgDIAAAAAA==.Cowpuss:BAAANQAECgEIAQABNQAECgkJFAAWABQZAA==.',
Cr='Crazydavis:BAAANQAECgIIAgAAAA==.Creekdeath:BAAANQAECggIDQAAAA==.Crevarus:BAAANQADCgUJDAAAAA==.Crimsonjeybi:BAAANQAECgcICAAAAA==.Cruesify:BAAANQAECgUIBwABNQAECgoKLAAJAJsVAA==.Crunchwich:BAABNQAECn8WAAIPAAYKlg55ZQCzAAAPAAYKlg55ZQCzAAAAAA==.Cryos:BAAANQAECgIIAQAAAA==.',
Cu='Cutename:BAAANQAECgUIBQAAAA==.',
Cy='Cy:BAAANQAECgUIBQABNQAECgoKJgADAAYjAA==.Cynamyn:BAABNQAECn8dAAICAAYKFwdIqgDgAAACAAYKFwdIqgDgAAAAAA==.',
Cz='Czeskilight:BAAANQADCgIIAgAAAA==.',
['Cö']='Cömet:BAAANQADCgcICAAAAA==.',
Da='Daane:BAAANQADCggIDwAAAA==.Dabadwarrior:BAAANQAECgUIBQAAAA==.Daevarys:BAAANQAECgEIAQAAAA==.Dakhran:BAAANQADCgIIBQAAAA==.Dakkä:BAAANQADCggIBwAAAA==.Dan:BAABNQAECn9AAAIKAAoK0BplHQCfAgAKAAoK0BplHQCfAgAAAA==.Danthrael:BAAANQAECgEIAQAAAA==.Danthrax:BAABNQAECn8jAAIaAAoK6BqRBgBYAgAaAAoK6BqRBgBYAgAAAA==.Darkdemon:BAABNQAECn82AAIfAAkKfwv3JQBrAQAfAAkKfwv3JQBrAQAAAA==.Darlord:BAAANQAECgUIDwAAAA==.Dawnliht:BAAANQADCgIIAgAAAA==.',
De='Deagle:BAAANQABCgIIBAABNQAECgoKKwARAI0lAA==.Deandrya:BAABNQAECn8ZAAMIAAoKhwZHcgBSAQAIAAoKhwZHcgBSAQAHAAEKQAL6rwAZAAAAAA==.Deedubbya:BAAANQADCgcIBwAAAA==.Delryd:BAABNQAECn8WAAMYAAYKEwQ4HACFAAAYAAYK4AM4HACFAAAgAAYKmwM2HACFAAAAAA==.Demonetized:BAAANQAECgQIBAAAAA==.Demônlock:BAABNQAECn8eAAMEAAkKBhclUgDeAQAEAAkKkBYlUgDeAQAhAAEKcxd0bABHAAAAAA==.Desideria:BAABNQAECn9EAAMiAAoKUQ2UCQC3AQAiAAoKUQ2UCQC3AQAEAAIK0gcuLAFlAAAAAA==.Despondence:BAACNQAFFH8HAAIfAAMKmhR0DQDUAAAfAAMKmhR0DQDUAAA1AAQKf1QAAx8ACgowIhsHAGADAB8ACgowIhsHAGADABsAAgq/GB0rAEYAAAAA.Desynn:BAAANQAECgYJDgAAAA==.',
Di='Divinesyn:BAABNQAECn8hAAICAAoKtglxYwC2AQACAAoKtglxYwC2AQAAAA==.Divonah:BAAANQADCgQIBAAAAA==.',
Dj='Djelysium:BAAANQAECgUICwAAAA==.Djtaki:BAABNQAECn9FAAMHAAoK/htDGAC6AgAHAAoK/htDGAC6AgAIAAcKAg+tewA1AQAAAA==.',
Do='Dogwater:BAAANQADCgYIBgABNQAFFAcIGQAeAM8fAA==.Doncarlos:BAACNQAFFH8MAAIFAAMKAQZqGQDIAAAFAAMKAQZqGQDIAAA1AAQKf1kAAgUACgrHH8MUAEsDAAUACgrHH8MUAEsDAAAA.Dorn:BAAANQAECgEIAQAAAA==.Dotty:BAAANQAECgEIAQAAAA==.Dottzz:BAAANQADCgYIBgAAAA==.Downbeatxo:BAECNQAFFH8aAAQhAAgK5hNRAwDgAAAEAAUKhBqIDgCQAQAhAAMKOhBRAwDgAAAiAAEKzRE/EQBVAAA1AAQKfzwABAQACgpdI3ERAOUCAAQACgpdI3ERAOUCACEABAomGmAtABcBACIAAgq+GrMbAJ4AAAAA.',
Dr='Dragonswòrd:BAAANQADCggIHQAAAA==.Drdevoted:BAAANQADCgIIAgAAAA==.Drippie:BAAANQADCgcIGQAAAA==.Dròòid:BAAANQADCgQJBAABNQAFFAQIBgAPAAkKAA==.',
Du='Dubdred:BAAANQAECgIIAgAAAA==.Duhon:BAAANQADCgQIBAAAAA==.Dumptruck:BAAANQAECggIEQABNQAECgoKJgADAAYjAA==.',
Dw='Dwín:BAABNQAECn8dAAIFAAoKQgabtACbAQAFAAoKQgabtACbAQAAAA==.',
['Dê']='Dêals:BAABNQAECn8hAAINAAgKOxqTRwBIAgANAAgKOxqTRwBIAgAAAA==.',
['Dü']='Dümpy:BAAANQADCgMIAwAAAA==.',
Ed='Edgelordxx:BAAANQAECgMIBAAAAA==.',
Ee='Eev:BAAANQADCgIIAgAAAA==.',
El='Elasper:BAAANQADCgcICQAAAA==.Eliselyia:BAAANQAECgEIAQAAAA==.Ellierose:BAABNQAECn8eAAICAAoKHwiIfwBaAQACAAoKHwiIfwBaAQAAAA==.',
Em='Emelianas:BAAANQAFFAEIAQABNQAFFAIIBQALANwHAA==.Ems:BAAANQAECgIIAgAAAA==.',
En='Enaelna:BAAANQAECgEIAQAAAA==.Endimion:BAAANQADCgIIAgAAAA==.Enjin:BAABNQAECn9TAAMFAAoKTCQiCABLAwAFAAoKTCQiCABLAwAGAAMK/RyJDgC7AAAAAA==.Enragedbeef:BAAANQAECgUIBQABNQAFFAQIBwACAO8JAA==.Entheogen:BAABNQAECn8wAAMjAAkKXxHuQwDEAQAjAAkKXxHuQwDEAQAOAAQK7hPkxwDYAAAAAA==.',
Eo='Eogan:BAAANQADCgIIAwAAAA==.',
Ep='Epichuntard:BAAANQAECgQICQAAAA==.',
Er='Erolas:BAAANQADCgQIBwAAAA==.',
Es='Essay:BAABNQAECn8rAAIFAAoK7RveRQBGAgAFAAoK7RveRQBGAgAAAA==.',
Et='Ethereall:BAABNQAECn8XAAMfAAkKxRisHABwAgAfAAkKxRisHABwAgAWAAMKOQH4kQA3AAAAAA==.',
Eu='Eudora:BAAANQADCggICAABNQAECgoKKwARAI0lAA==.',
Ev='Evalilly:BAAANQADCgYIBgAAAA==.Evanessance:BAAANQADCgYIBwAAAA==.Evilice:BAABNQAECn88AAIDAAkK/xF5lwCeAQADAAkK/xF5lwCeAQAAAA==.Evoka:BAABNQAECn8mAAIkAAkKmQ3aEwC7AQAkAAkKmQ3aEwC7AQAAAA==.',
Fa='Faavibear:BAAANQAECggIAQAAAA==.Fallendevout:BAAANQAECgUICAAAAA==.Fallenhero:BAAANQAECgcICAAAAA==.Fallentroll:BAABNQAECn8dAAMLAAkKmhlKPQAqAgALAAkKKBlKPQAqAgAPAAMK7Rw8jADQAAAAAA==.Fatdoinkers:BAABNQAECn8mAAQDAAoKBiOqNwCGAgADAAoKBiOqNwCGAgANAAIKowwq1gBpAAATAAIKjhmNZwBFAAAAAA==.Fatman:BAAANQADCgcICAABNQADCgIIAwAUAAAAAA==.Faydark:BAAANQADCgQIBAAAAA==.Fayia:BAAANQADCggIDgAAAA==.Fayye:BAABNQAECn8jAAINAAgKpBD/WgCsAQANAAgKpBD/WgCsAQAAAA==.',
Fe='Felbeks:BAAANQAECgQIBAABNQAECgoKNAAPADshAA==.',
Fi='Fireflydh:BAAANQADCgYIBgABNQAECgoKKQAiAKMTAA==.Firetotems:BAAANQADCgEIAQABNQAECgoKKQAiAKMTAA==.Firragol:BAAANQABCgYICgAAAA==.Firèflyjd:BAABNQAECn8pAAQiAAoKoxMXFAD1AAAEAAgKOBLVfQBmAQAiAAYKKhAXFAD1AAAhAAIK4xeMHgB1AAAAAA==.Fishstick:BAAANQADCggIGAAAAA==.',
Fl='Floatpass:BAACNQAFFH8LAAIBAAUKIhsEFQBLAQABAAUKIhsEFQBLAQA1AAQKf0UAAgEACgqBIwUPABUDAAEACgqBIwUPABUDAAAA.',
Fo='Foot:BAAANQADCgcJCQAAAA==.',
Fr='Frizz:BAAANQAECgUIEAAAAA==.Froey:BAEANQAECgMIAwAAAA==.',
Fu='Fuzzypally:BAABNQAECn8fAAINAAoKfB+4IQDmAgANAAoKfB+4IQDmAgAAAA==.Fuzzyshadow:BAAANQAECgQIBAAAAA==.Fuzzytotems:BAAANQAECgcIDgAAAA==.',
['Fá']='Fáavi:BAAANQAECgQIBAAAAA==.',
Ga='Gali:BAAANQADCgQJBAABNQAFFAQIBgAPAAkKAA==.Galiagante:BAAANQADCggJDAAAAA==.Gallynna:BAABNQAECn8tAAQEAAgKphLCewDxAQAEAAgKKRHCewDxAQAhAAMKVRCcWgBxAAAiAAMKhwuxJABcAAAAAA==.Galorfax:BAABNQAECn9BAAIdAAoKuR9XCAC/AgAdAAoKuR9XCAC/AgAAAA==.Galushi:BAAANQADCggIDwAAAA==.Garm:BAABNQAECn87AAIFAAoKXiNUEgBXAwAFAAoKXiNUEgBXAwABNQAECgoKRQAXADsjAA==.',
Ge='Gelinea:BAAANQADCgYIDgAAAA==.Gerlton:BAAANQADCgQIBQAAAA==.Gernar:BAAANQADCgUICwAAAA==.',
Gi='Gilgaroth:BAABNQAECn9LAAMIAAoKFRzzJgBnAgAIAAoKLhrzJgBnAgAHAAgKLBlTFACPAQAAAA==.Girlslove:BAAANQADCgIIAgABNQAFFAcIGQAeAM8fAA==.',
Gn='Gnoskill:BAAANQAECgMIAwAAAA==.',
Go='Gobo:BAABNQAECn8WAAIjAAgKBRZEXwAEAgAjAAgKBRZEXwAEAgAAAA==.',
Gr='Graysonn:BAAANQADCggIGQAAAA==.Greafox:BAABNQAECn8mAAMOAAoKSiQQBgCVAwAOAAoKSiQQBgCVAwAjAAUKHxR/rgA2AQAAAA==.Grrimreaperr:BAAANQADCgcIBwAAAA==.Grýla:BAAANQADCgUIBQAAAA==.',
Gu='Guildenstern:BAABNQAECn8oAAMHAAoKECP8AgAbAwAHAAoKECP8AgAbAwAIAAIKZhjjzQBPAAABNQAFFAcIGQAeAM8fAA==.Gundrakk:BAAANQAECgYIEQAAAA==.Gunnr:BAAANQAECgQICQABNQAECggIDgAUAAAAAA==.Gunthorian:BAAANQAECgMJAwAAAA==.',
Ha='Handsomemonk:BAAANQADCgMIBAABNQAECgoKJgADAAYjAA==.Hansi:BAAANQAECgQIAwAAAA==.Harbringer:BAAANQAECgUIBQABNQAECgkJIgANAPMUAA==.',
He='Heart:BAAANQAECgUIAwABNQAECgkJKgADAIsfAA==.Heid:BAAANQADCggIDwAAAA==.Helldozer:BAAANQADCgcICQAAAA==.Heytherepal:BAAANQAECgQIBgAAAA==.',
Hi='Higanbana:BAACNQAFFH8hAAIfAAcKiB5wAwAkAgAfAAcKiB5wAwAkAgA1AAQKfz4AAh8ACgq4JfIFAHIDAB8ACgq4JfIFAHIDAAAA.Himawari:BAABNQAECn8gAAIDAAkKIiCTQwDKAgADAAkKIiCTQwDKAgABNQAFFAcIIQAfAIgeAA==.Himejoshi:BAACNQAFFH8ZAAIeAAcKzx9OAABwAgAeAAcKzx9OAABwAgA1AAQKf1IAAh4ACgrXJjMAAJoDAB4ACgrXJjMAAJoDAAAA.Hippocampus:BAABNQAECn8uAAIOAAoK9B8hCgB7AwAOAAoK9B8hCgB7AwAAAA==.Hirys:BAABNQAECn8XAAIIAAgKKxNvGwD7AQAIAAgKKxNvGwD7AQAAAA==.',
Ho='Holybeks:BAAANQAECgEIAgABNQAECgoKNAAPADshAA==.Holydaddy:BAAANQAECgYICQAAAA==.Holysmite:BAAANQAECgQIBAABNQAECggIDwAUAAAAAA==.Hoppadk:BAABNQAECn80AAIPAAoKOyElGgDdAgAPAAoKOyElGgDdAgAAAA==.Hotdoggin:BAAANQADCgEIAQABNQAECgoKJgADAAYjAA==.Hotshotzz:BAAANQAECgMIAwABNQAECgkJJwADAOgcAA==.',
Hr='Hrunting:BAAANQAECgQIBAAAAA==.',
Hu='Huntfosho:BAAANQAECgQIBgAAAA==.Huntsmedown:BAAANQADCgYICwAAAA==.',
['Há']='Háldrin:BAACNQAFFH8SAAMcAAYK6BfnCwAjAQAcAAUKphjnCwAjAQAFAAEK8BTXLQBbAAA1AAQKfzYAAxwACgpfIsYLAB0DABwACgq1IcYLAB0DAAUAAQo0Ju4kAWsAAAAA.',
['Hö']='Hölybeary:BAABNQAECn8jAAMNAAkKVw0AWAC2AQANAAkKVw0AWAC2AQATAAYK7QcRSwC/AAAAAA==.',
Ic='Icybacon:BAAANQAECgQIBAAAAA==.Icëcrëam:BAAANQADCggICAAAAA==.',
Ih='Ihavegrass:BAABNQAECn8UAAMFAAYK6wz2AgH/AAAFAAYK6wz2AgH/AAAcAAEKswT5bQAtAAAAAA==.',
Il='Illyeris:BAAANQAECgIIAwAAAA==.',
Im='Imbue:BAABNQAECn8yAAIbAAoKMh78BACAAgAbAAoKMh78BACAAgAAAA==.Imbuer:BAAANQAECgQICAAAAA==.',
In='Innil:BAABNQAECn8nAAMCAAoKdiVCAgDHAwACAAoKdiVCAgDHAwAJAAEK6B7qEwBZAAAAAA==.Inora:BAAANQABCgMIAwAAAA==.',
It='Itzapazz:BAAANQADCggIIAAAAA==.',
Ja='Jagr:BAAANQADCgEIAQAAAA==.Jaurel:BAAANQADCgMIAwAAAA==.',
Je='Jessiks:BAAANQAECgIIAgAAAA==.Jessix:BAABNQAECn8WAAMEAAoKfh8KLwDKAgAEAAoKSR8KLwDKAgAhAAIK9RPWUQCKAAAAAA==.Jezebel:BAABNQAECn8uAAMEAAoKMRc6TgBpAgAEAAoKWxU6TgBpAgAhAAQKDxNOHgB2AAAAAA==.',
Ji='Jiaoe:BAAANQADCgIIAwAAAA==.Jimfowler:BAAANQADCgIIAgAAAA==.Jirito:BAAANQAECgMJAwAAAA==.',
Jo='Jomadead:BAABNQAECn8qAAIPAAkKlRR1IQDvAQAPAAkKlRR1IQDvAQABNQAECgoKGgAOAOgSAA==.Jomas:BAABNQAECn8aAAIOAAoK6BLpVQAQAgAOAAoK6BLpVQAQAgAAAA==.Jovaar:BAAANQADCggICAAAAA==.',
Ju='Judera:BAABNQAECn9OAAMDAAoKjBygPgBvAgADAAoKjBygPgBvAgATAAEKYRIDZgAxAAAAAA==.',
Ka='Kaing:BAABNQAECn8nAAIaAAcKXw2UFgAyAQAaAAcKXw2UFgAyAQAAAA==.Kaladen:BAABNQAECn8dAAQlAAoK7CIpBwBQAwAlAAoK7CIpBwBQAwAMAAEKlhIqrQA8AAAdAAEKvxccXQA7AAAAAA==.Kalec:BAAANQADCgUJBQAAAA==.Kalysti:BAAANQAECggIIAAAAQ==.Kaoticmagus:BAAANQADCgEIAQABNQADCgYIEwAUAAAAAA==.Kaoticnature:BAAANQADCgYIEwAAAA==.Karolg:BAABNQAECn8cAAIPAAcKXRxdLgCYAQAPAAcKXRxdLgCYAQAAAA==.Katostrafic:BAABNQAECn8sAAMJAAoKmxUwCQDIAQAJAAcKcBUwCQDIAQACAAkKWhQrewBoAQAAAA==.Katrynna:BAAANQADCgYIEwAAAA==.',
Ke='Kelarra:BAAANQADCgQIBgAAAA==.',
Kh='Khromscarin:BAACNQAFFH8MAAIbAAMK6xOdAgC+AAAbAAMK6xOdAgC+AAA1AAQKf1wAAxsACgqVIpUCAPECABsACgqVIpUCAPECAB8ABwrVDdc2AI0BAAAA.',
Ki='Killidan:BAABNQAECn8uAAIfAAoKpB3eEwDJAgAfAAoKpB3eEwDJAgAAAA==.Kirklees:BAAANQAECgUICQAAAA==.Kitsuchan:BAABNQAECn8hAAQBAAoK0yLnSgDsAgABAAkKEiPnSgDsAgAmAAMK2iLtJADHAAAnAAEKAAAxEAAAAAAAAA==.',
Kk='Kkthx:BAAANQADCgcIBwABNQAFFAQIBwACAO8JAA==.',
Ko='Kodama:BAABNQAECn80AAIjAAoKlwtvUwCNAQAjAAoKlwtvUwCNAQAAAA==.Koi:BAAANQADCgcIEgABNQAECgkJLwAbABofAA==.Kookiemon:BAAANQAECgYIBwAAAA==.Kookiesplz:BAAANQADCggICAAAAA==.Kopili:BAAANQADCgUIBwAAAA==.',
Kr='Krekdas:BAAANQADCgUIBQAAAA==.Kromag:BAAANQADCgYIBgABNQAECggICwAUAAAAAA==.',
Ku='Kunpochiken:BAAANQAECgYICAABNQAECgoKLAAJAJsVAA==.',
Ky='Kyanna:BAABNQAECn8bAAIMAAYKzAT8ZQCPAAAMAAYKzAT8ZQCPAAAAAA==.Kyoshi:BAAANQAECgUIBQAAAA==.',
La='Lader:BAABNQAFFH8PAAIDAAkKtADCLQBUAAADAAkKtADCLQBUAAAAAA==.Ladifantasie:BAAANQAECgQICgAAAA==.Laria:BAABNQAECn8VAAIfAAgKshWSJQAZAgAfAAgKshWSJQAZAgAAAA==.Laurebeth:BAABNQAECn8bAAMlAAgKKAaOPwANAQAlAAgKKAaOPwANAQAMAAcKKgkFRgAMAQAAAA==.Laxinmedium:BAAANQADCggIDwAAAA==.',
Le='Leenei:BAAANQAECgUIDAAAAA==.Lenlaar:BAABNQAECn8hAAIDAAkKqRX+gADLAQADAAkKqRX+gADLAQAAAA==.Levande:BAACNQAFFH8KAAICAAMK1hASJADDAAACAAMK1hASJADDAAA1AAQKfzIAAwIACgoYIGgKAJQDAAIACgoYIGgKAJQDABIAAgq7DaNPAG0AAAAA.',
Li='Lifeblume:BAAANQADCggIJgAAAA==.Lightnning:BAAANQAECgMIAwAAAA==.Lildevil:BAAANQADCgUIBwAAAA==.Lilithandria:BAABNQAECn8UAAIWAAkKFBnQPADRAQAWAAkKFBnQPADRAQAAAA==.Linamar:BAAANQAECgUICQAAAA==.Littlefishy:BAAANQADCgMIAwAAAA==.',
Lo='Loaq:BAABNQAECn8yAAMCAAoK9hPbRgBSAgACAAoK9hPbRgBSAgAJAAMK4giBHACBAAAAAA==.Lockzrockz:BAAANQAECgUIAgAAAA==.Lodshan:BAAANQADCgEIAQAAAA==.Longbottom:BAAANQAECggICQABNQAECgoKJgADAAYjAA==.Loot:BAABNQAECn8aAAMTAAkKiQCbdwAOAAATAAkKggCbdwAOAAADAAgKWwChxAELAAAAAA==.Lorbert:BAAANQAECgQIBgABNQAECgoKKAAXADMVAA==.Lostalot:BAABNQAECn8xAAIFAAkK3hQGXwBZAgAFAAkK3hQGXwBZAgAAAA==.',
Lu='Luxæterna:BAABNQAECn9EAAIDAAoKvSBZRQBZAgADAAoKvSBZRQBZAgAAAA==.',
Ly='Lyphiara:BAAANQADCggIGgABNQAECgkJMwAQAGofAA==.',
Ma='Malice:BAABNQAECn8VAAMiAAgKghUnCgDYAQAiAAgKghUnCgDYAQAhAAIKZAUFaQBPAAAAAA==.Mandwandos:BAABNQAECn8cAAQOAAoKIBijdwClAQAOAAgKqBWjdwClAQAjAAkKtQpkjQCCAQAVAAEKAABCPgAAAAAAAA==.Maraliss:BAABNQAECn8XAAIeAAYK7Q0YJwDJAAAeAAYK7Q0YJwDJAAAAAA==.',
Me='Meiri:BAAANQADCgEIAQABNQAFFAMICAAZADESAA==.Melaunis:BAAANQAECgUICgAAAA==.Mellwynn:BAAANQADCgUIBQAAAA==.Meowzer:BAABNQAECn8dAAQMAAUKaRRXbAAZAQAMAAUKZxFXbAAZAQAeAAQKtA0BLwCaAAAdAAUKrA8iTwCCAAABNQAFFAQIBwACAO8JAA==.Merginator:BAAANQAECgUIBwAAAA==.Meteora:BAACNQAFFH8IAAIZAAMKMRLsBADEAAAZAAMKMRLsBADEAAA1AAQKfx8AAhkACgoYG3wMAG0CABkACgoYG3wMAG0CAAAA.Methisto:BAAANQADCgcIBwAAAA==.',
Mi='Mideel:BAABNQAECn8bAAInAAYKdwnEBgDIAAAnAAYKdwnEBgDIAAAAAA==.Mideheals:BAAANQAECgIIAgAAAA==.Midesis:BAAANQAECgQIBQAAAA==.Migolbearcow:BAABNQAECn9GAAIdAAoKUxdEDwBwAgAdAAoKUxdEDwBwAgAAAA==.Missed:BAAANQAECgIJAwAAAA==.Missedweaver:BAAANQADCgYICAABNQAECgIJAwAUAAAAAA==.Missrae:BAAANQADCggIGAAAAA==.',
Mk='Mk:BAEANQADCgIIAgABNQAECgoKPQARAFkfAA==.',
Ml='Mlglock:BAAANQADCgMIAwAAAA==.',
Mo='Moiira:BAAANQAECgEIAQAAAA==.Monyshot:BAAANQADCgcIDQAAAA==.Moondizzle:BAAANQAECgIIAgAAAA==.Mooniè:BAABNQAECn8mAAMmAAoKJQSqJADJAAAmAAoK7wOqJADJAAABAAcKKAKMBwGoAAAAAA==.Moosenuts:BAABNQAECn8WAAIEAAgKJQ9TkgC5AQAEAAgKJQ9TkgC5AQAAAA==.Moriavus:BAABNQAECn8qAAIiAAoKxxeyBACLAgAiAAoKxxeyBACLAgAAAA==.Morocha:BAABNQAECn8dAAIQAAgKDQ4JKQArAQAQAAgKDQ4JKQArAQAAAA==.Mortèm:BAAANQAECgIIAgAAAA==.Moxxie:BAAANQADCgEIAQABNQAECgQIBAAUAAAAAA==.',
Mu='Muragore:BAAANQAECgUICgAAAA==.',
My='Mychropien:BAABNQAECn80AAMLAAoKVyHRFQBAAgALAAoKVyHRFQBAAgAPAAMKURuvkQBLAAAAAA==.Myylus:BAAANQADCgYIFAAAAA==.',
['Mö']='Mökes:BAABNQAECn89AAIhAAoK0yQCAQCbAwAhAAoK0yQCAQCbAwAAAA==.',
Na='Nadroj:BAAANQADCggIIwAAAA==.Nancydru:BAABNQAECn8bAAIdAAcK2xV2HwCHAQAdAAcK2xV2HwCHAQAAAA==.Naosu:BAAANQADCggIEQAAAA==.Nax:BAABNQAECn8bAAIBAAcK9wvWxwAYAQABAAcK9wvWxwAYAQAAAA==.Nazzersaurus:BAABNQAECn8aAAIlAAcKYxnYJQD0AQAlAAcKYxnYJQD0AQAAAA==.',
Ne='Nec:BAAANQAECgEIAQAAAA==.Necronite:BAAANQAECgMIAwABNQAECgcIIwAOANEXAA==.Necrøtic:BAABNQAECn83AAMmAAoKPhUPCQAZAgAmAAoKPhUPCQAZAgABAAQKqgYijgGqAAAAAA==.Nekomata:BAAANQADCgEIAQAAAA==.Nekosmasta:BAAANQADCgEIAQAAAA==.Neodin:BAAANQAECgYICwAAAA==.Nevermiss:BAABNQAECn9KAAIQAAoKlRhIDwAlAgAQAAoKlRhIDwAlAgAAAA==.',
Ni='Nightjewel:BAAANQADCggIDwAAAA==.',
No='Notmewasyou:BAABNQAECn8hAAMMAAcKSANihwC1AAAMAAcKSANihwC1AAAlAAQKpAH4cQA+AAAAAA==.',
Nu='Nuali:BAABNQAECn8rAAMDAAkKeBnHZABsAgADAAkKHRnHZABsAgATAAgKBhE1KwAdAQAAAA==.Numi:BAAANQADCggIDQAAAA==.',
Od='Odysseus:BAAANQADCgUICQAAAA==.',
Ok='Okameshiz:BAAANQADCggIDQAAAA==.',
On='Onlyspins:BAAANQAECgcIBwAAAA==.',
Or='Orý:BAABNQAECn9EAAIjAAoK1hsbLADOAgAjAAoK1hsbLADOAgAAAA==.',
Os='Oslatem:BAAANQADCgcICQAAAA==.',
Ox='Oxosorrel:BAAANQABCggIEQAAAA==.',
Oz='Ozzmodious:BAAANQADCgcIEwAAAA==.',
Pa='Pajonn:BAABNQAECn8bAAIjAAoK0g/mQgDIAQAjAAoK0g/mQgDIAQAAAA==.Paladan:BAABNQAECn8wAAMTAAoK3iFfBwAtAwATAAoK3iFfBwAtAwADAAMKaR/jLgGlAAAAAA==.Paladanny:BAAANQAECgUIDgAAAA==.Palagi:BAABNQAECn8oAAMlAAcKKA2+TADJAAAlAAYKUAm+TADJAAAeAAYKlgUuMgCIAAAAAA==.Pallu:BAAANQADCgQIBAAAAA==.Pallyana:BAAANQAECggIEgAAAA==.Pallyfosho:BAAANQAECgIIAgAAAA==.Pallymcbeall:BAAANQAECgMIBAAAAA==.Paprikaman:BAABNQAECn8bAAMFAAYKcAJAHAHHAAAFAAYKcAJAHAHHAAAcAAEKNwHeeQAbAAAAAA==.Parallax:BAAANQAECgIIAgAAAA==.Pariahrain:BAABNQAECn8hAAMTAAgKFRk8GwAUAgATAAgKFRk8GwAUAgADAAIKyQKPhwFPAAABNQAFFAQIDAAmAEcKAA==.Parishealton:BAABNQAECn8qAAMlAAoKWCD0CQAnAwAlAAoKWCD0CQAnAwAMAAMKvQFvpgBMAAAAAA==.Payday:BAAANQADCgYICwAAAA==.Pazzuzu:BAAANQADCgcIDAAAAA==.',
Pe='Penjamin:BAAANQAECgQIBwABNQAECgoKJgADAAYjAA==.Perprotrus:BAAANQADCgQIBAABNQAFFAQIBgAPAAkKAA==.',
Ph='Phatboi:BAAANQAECgQIBwAAAA==.',
Po='Poulsbo:BAAANQAECgUIDQAAAA==.Powerup:BAAANQAECgQIBAAAAA==.Pozole:BAAANQAECgcIDQAAAA==.',
Pr='Prominence:BAABNQAECn8vAAIGAAoKOCEmAgC/AgAGAAoKOCEmAgC/AgAAAA==.Promisques:BAAANQAECgEIAQAAAA==.Protectapear:BAAANQABCgEIAQAAAA==.Prozak:BAABNQAECn80AAIOAAoKyRW7MgBSAgAOAAoKyRW7MgBSAgAAAA==.Prozakmd:BAAANQADCggICgAAAA==.',
Pw='Pwomf:BAABNQAECn8hAAIDAAoK+QxzigC3AQADAAoK+QxzigC3AQAAAA==.',
Py='Pyneapple:BAAANQADCgQIBAABNQAFFAQIBwACAO8JAA==.Pyrolily:BAABNQAECn8cAAImAAgKtwYwHwDxAAAmAAgKtwYwHwDxAAAAAA==.',
Qu='Question:BAAANQADCgIIAwAAAA==.Qulung:BAAANQADCggIFAAAAA==.',
Ra='Rabyd:BAAANQAECgMIAwAAAA==.Raegasm:BAAANQADCgYIEAAAAA==.Raght:BAAANQAECgIIAgAAAA==.Raha:BAAANQAECgYIDwAAAA==.Raithe:BAAANQADCgYIBgAAAA==.Ramue:BAAANQADCgcIDgAAAA==.Raskela:BAABNQAECn8cAAMQAAkKpxO3GADyAQAQAAkKpxO3GADyAQARAAcKdhQrMQCOAQAAAA==.Rastakan:BAAANQAECgUICQABNQAECgoKRQAXADsjAA==.Razal:BAAANQADCggIDQAAAA==.',
Re='Reesespiecez:BAAANQAECgcICwAAAA==.Rellidana:BAAANQAECggICgAAAA==.Remove:BAAANQAECgUIBQAAAA==.Reprieve:BAAANQAECgUICQAAAA==.Retradormi:BAAANQAECgQICQAAAA==.Rexi:BAABNQAECn8hAAISAAkKCg6VJwDuAQASAAkKCg6VJwDuAQAAAA==.',
Ri='Rickcando:BAABNQAECn8WAAIjAAYK2xRMbwDSAQAjAAYK2xRMbwDSAQAAAA==.Ricshard:BAABNQAECn9AAAQEAAkKLBYeXwC4AQAEAAcKzRceXwC4AQAhAAMKtBdNHQB9AAAiAAMKNwijIwBgAAAAAA==.Ridjeckgron:BAAANQADCgcICQAAAA==.Rissiia:BAAANQADCgQIBAAAAA==.',
Rm='Rmft:BAAANQAECgUIBgABNQAECgoKSAAXAOMaAA==.',
Ro='Roomnboard:BAAANQAECgMIAwAAAA==.Rotter:BAAANQADCgQIBQAAAA==.Roughluver:BAAANQAECgUIBgABNQAFFAQIBwACAO8JAA==.',
Ru='Ruben:BAAANQADCgEIAgAAAA==.Rungar:BAAANQAECgQICwAAAA==.',
Rv='Rvoker:BAAANQADCgQIBAAAAA==.',
Ry='Rydmytotem:BAAANQAECggIEAAAAA==.Ryuk:BAAANQADCgMIAwAAAA==.Ryñ:BAABNQAECn8XAAIFAAoKfhkyQABVAgAFAAoKfhkyQABVAgAAAA==.',
['Rà']='Ràein:BAABNQAECn8vAAQhAAgK5A7pCQAoAQAhAAgK5A7pCQAoAQAiAAEKzwixLQA5AAAEAAEK0QL5JQEfAAAAAA==.',
['Ró']='Ród:BAABNQAECn8nAAIDAAkK6BxIbwBRAgADAAkK6BxIbwBRAgAAAA==.',
['Rø']='Røth:BAAANQADCgcIEgAAAA==.',
Sa='Saalira:BAAANQADCggIEgAAAA==.Sabellice:BAABNQAECn9HAAIDAAoKpBPDZQAGAgADAAoKpBPDZQAGAgAAAA==.Sakonna:BAABNQAECn8fAAISAAkKQRV8IAA1AgASAAkKQRV8IAA1AgAAAA==.Salinoria:BAAANQAECgQICQABNQAECgkJKwADAHgZAA==.Saltyfingers:BAAANQADCggIEgAAAA==.Sandymaw:BAAANQADCgQIBAABNQAFFAQIBwACAO8JAA==.Sarlius:BAABNQAECn8+AAIFAAoKRyXpAgDYAwAFAAoKRyXpAgDYAwAAAA==.Sassybuns:BAAANQABCgQIBAAAAA==.Satyrical:BAABNQAECn8qAAIDAAkKix8sVgAsAgADAAkKix8sVgAsAgAAAA==.Savin:BAAANQAECgYIEQAAAA==.',
Sc='Scavenger:BAAANQAECgYIDgAAAA==.Scorchin:BAAANQAECggIEAAAAA==.Scrumptiøus:BAAANQAECgUIEAABNQAECgoKLAAJAJsVAA==.',
Se='Selkamonk:BAABNQAECn8zAAMQAAkKah/0CgDXAgAQAAkKah/0CgDXAgARAAIKDgaGYQArAAAAAA==.Seniorbold:BAABNQAECn8pAAIDAAoKwhmzQgDMAgADAAoKwhmzQgDMAgAAAA==.Sentrina:BAACNQAFFH8IAAIkAAUKJAx0EADOAAAkAAUKJAx0EADOAAA1AAQKfzUAAiQACgqYHSgNANMCACQACgqYHSgNANMCAAAA.Seraph:BAAANQAECgcIDQAAAA==.Seshy:BAACNQAFFH8HAAMCAAQK7wkhJQC8AAACAAMKxwYhJQC8AAASAAIKTQcMEgB9AAA1AAQKf00AAwIACgpsHN8mALUCAAIACgpsHN8mALUCABIACQr1FyYgADkCAAAA.Seshymutedme:BAAANQAECggIEQABNQAFFAQIBwACAO8JAA==.',
Sh='Shamanagins:BAAANQADCgEIAQAAAA==.Shannon:BAAANQADCgYIBgABNQAECggIIwANAKQQAA==.Shannoon:BAABNQAECn8jAAITAAgKIglTNADjAAATAAgKIglTNADjAAAAAA==.Sharr:BAAANQADCgYIDAAAAA==.Shekzeer:BAABNQAECn8rAAQRAAoKjSXlAADnAwARAAoKjSXlAADnAwAQAAYK0hzxGgDSAQAoAAMK8yALIwC/AAAAAA==.Shiverr:BAABNQAECn8uAAImAAgK1gcmGQAtAQAmAAgK1gcmGQAtAQAAAA==.Shockakan:BAAANQABCgQIBAAAAA==.Shockazulu:BAAANQADCgIIAgAAAA==.Shocktard:BAAANQAECgEIAQABNQAECgkJHwAKAJMdAA==.',
Si='Siatraz:BAAANQAECgQIBQABNQAECgoKKQAiAKMTAA==.Siegatrox:BAAANQAECgIIAgAAAA==.Silgan:BAAANQADCgYIBgAAAA==.Silverbain:BAAANQADCgQIBAAAAA==.Sinnon:BAAANQAECgMIAwAAAA==.',
Sk='Skizem:BAAANQADCgEIAQAAAA==.Skott:BAAANQAECgQIBAAAAA==.Skïnnyßetch:BAAANQADCgcIBwAAAA==.',
Sl='Sleepadin:BAABNQAECn8bAAIDAAoKVgsp0QB5AQADAAoKVgsp0QB5AQAAAA==.Sleepyr:BAAANQAECgYIDQAAAA==.',
Sm='Smokeymage:BAABNQAECn8UAAIBAAYKKAaM2QD5AAABAAYKKAaM2QD5AAAAAA==.',
Sn='Snowi:BAAANQADCgYIBgABNQAECggIDgAUAAAAAA==.Snowstorm:BAAANQAECgEIAQAAAA==.',
So='Soakra:BAABNQAECn8jAAIOAAoK/hbaRABOAgAOAAoK/hbaRABOAgAAAA==.Solignis:BAACNQAFFH8rAAMaAAgKQyYPAABtAgAaAAgKQyYPAABtAgAXAAQK6R5WFACIAQA1AAQKf14AAxoACgoDJwUAAB4EABoACgoDJwUAAB4EABcACQqUJu8HALMDAAAA.Solxeen:BAAANQADCggICAAAAA==.Soniviolence:BAABNQAECn82AAIXAAoK0CBoGwBKAwAXAAoK0CBoGwBKAwAAAA==.Soohots:BAACNQAFFH8GAAIlAAMKmBq+CwD7AAAlAAMKmBq+CwD7AAA1AAQKfx4AAyUACQrgHYkUAKUCACUACArdHIkUAKUCAAwABAovEOyNAJ8AAAAA.Sourskittlz:BAAANQADCgQIBAAAAA==.',
Sp='Sparklehappy:BAABNQAECn8cAAMcAAkKexgWLAAKAQAcAAgKLxgWLAAKAQAFAAEKQRoJRgFTAAAAAA==.Splìff:BAAANQADCgYIBgAAAA==.Sppazz:BAAANQADCgcIBwAAAA==.',
St='Starshield:BAAANQAECgIIAgABNQAECgkJGAALAHYWAA==.Stausa:BAAANQADCgcIBwAAAA==.Steeljustice:BAAANQAECggICAAAAA==.Stormcreek:BAABNQAECn8jAAMOAAcK0RcPcABjAQAOAAcK0RcPcABjAQAjAAIKnQIkCwEpAAAAAA==.Storri:BAACNQAFFH8HAAICAAIKWxZ9KwCJAAACAAIKWxZ9KwCJAAA1AAQKf1wAAwIACgraHN8bAPsCAAIACgraHN8bAPsCABIABQrCBhtUAL0AAAAA.',
Su='Sufferinhero:BAAANQAECgEIAQABNQAFFAMIDAAbAOsTAA==.Suzuya:BAAANQAECgUICQAAAA==.',
Sv='Svetty:BAAANQAECggICwAAAA==.',
Sw='Swiftly:BAABNQAECn8UAAMIAAgKoyBTMAA7AgAIAAcKJSJTMAA7AgAHAAcKextTGgBSAQAAAA==.Swiftmage:BAACNQAFFH8rAAMmAAgKEiMvAABPAgAmAAgKEiMvAABPAgABAAUKvR0cGgCpAQA1AAQKf00AAyYACgruJg8AAAcEACYACgruJg8AAAcEAAEACQoqJeMYAHEDAAAA.Switchboard:BAAANQADCgYICgAAAA==.',
Sx='Sxkittn:BAAANQADCgcICwAAAA==.',
Sy='Sygh:BAAANQAECgEIAQABNQAECgkJKgADAIsfAA==.Syltru:BAAANQADCgUIBQAAAA==.Syndragonkin:BAABNQAECn80AAIFAAkKixV6dwDOAQAFAAkKixV6dwDOAQAAAA==.Syndrome:BAAANQADCggIDgAAAA==.Synger:BAAANQADCgYIEAAAAA==.',
Ta='Taima:BAAANQABCgEIAQAAAA==.Talyndis:BAACNQAFFH8xAAIcAAoKAiJTAAAuAwAcAAoKAiJTAAAuAwA1AAQKfzsAAhwACgo4JbYEAAkDABwACgo4JbYEAAkDAAAA.Tamyr:BAAANQADCgIIAgAAAA==.Tazadar:BAAANQAECgQIBAAAAA==.Taze:BAAANQAECgUJBwABNQAFFAQIBgAPAAkKAA==.Tazjiingo:BAAANQADCgIIBAAAAA==.',
Te='Terrika:BAABNQAECn8oAAIFAAkKvwvxigD0AQAFAAkKvwvxigD0AQAAAA==.Tetshajeh:BAACNQAFFH8MAAIXAAMKLBZ3GwDYAAAXAAMKLBZ3GwDYAAA1AAQKf2EAAxcACgp/IpMYAFYDABcACgp6IpMYAFYDABkABwr7HdUPALkBAAAA.Teyliana:BAABNQAECn8bAAIQAAYK6Qj/JgDMAAAQAAYK6Qj/JgDMAAAAAA==.',
Th='Thebigchud:BAAANQAECgUICgAAAA==.Thillarick:BAABNQAECn9IAAIXAAoK4xrgLwB/AgAXAAoK4xrgLwB/AgAAAA==.Thiss:BAAANQADCgEIAQAAAA==.Thromanor:BAAANQAECgYIBQAAAA==.Thwip:BAABNQAECn86AAMFAAoKRCGaLADoAgAFAAoKRCGaLADoAgAcAAkKChXFEwAHAgAAAA==.Thänatøs:BAAANQAECgEIAQAAAA==.',
Ti='Tikwid:BAABNQAECn8lAAIBAAgKhwUK3wDvAAABAAgKhwUK3wDvAAAAAA==.Tiranmyashol:BAABNQAECn8oAAIXAAoKMxXcaABVAgAXAAoKMxXcaABVAgAAAA==.',
To='Tomoya:BAAANQAECgcIEgAAAA==.Too:BAAANQAECgIIAQAAAA==.Toothdk:BAABNQAECn8XAAILAAUKWRU0RgDwAAALAAUKWRU0RgDwAAAAAA==.Torfnar:BAABNQAECn8jAAIGAAoKJgmqBgDLAQAGAAoKJgmqBgDLAQAAAA==.Tormmentor:BAABNQAECn8aAAMOAAkKTxFbWQCvAQAOAAkKTxFbWQCvAQAjAAIK/AKkEgEdAAAAAA==.',
Tr='Treebreak:BAAANQAECgUIEAAAAA==.',
Tu='Tugmydangle:BAAANQAECggIDwAAAA==.',
Ty='Tyrandrea:BAAANQADCgcICQAAAA==.',
['Tô']='Tôxin:BAAANQAECggIBgAAAA==.',
Ud='Udari:BAAANQAFFAIIAgAAAA==.Udarii:BAAANQAECgcICQAAAA==.',
Um='Umàdbrah:BAABNQAECn9BAAIFAAgKNyHvLACOAgAFAAgKNyHvLACOAgAAAA==.',
Un='Unbelievable:BAABNQAECn8oAAIWAAkKvgqxOgBWAQAWAAkKvgqxOgBWAQAAAA==.Unprovoked:BAABNQAECn8iAAIBAAkKwh5dVwDRAgABAAkKwh5dVwDRAgAAAA==.',
Uw='Uwntme:BAAANQADCgEIAQAAAA==.',
Va='Valamor:BAABNQAECn84AAMTAAgKexGnIABqAQATAAgKexGnIABqAQANAAUK4Ae1zQDgAAAAAA==.Varenea:BAAANQADCgYIBgAAAA==.Varia:BAAANQAECgEIAQABNQAECgkJHwAKAJMdAA==.',
Ve='Veefib:BAABNQAECn85AAMjAAoK9hnjQAByAgAjAAoK9hnjQAByAgAOAAMKLg8uvQCfAAAAAA==.Velicerus:BAAANQAECgQIBAAAAA==.Velvettwitch:BAABNQAECn8yAAIhAAkKGRO7BgBxAQAhAAkKGRO7BgBxAQAAAA==.Vendler:BAABNQAECn8VAAIXAAkKnQcbugCLAQAXAAkKnQcbugCLAQAAAA==.Verahla:BAAANQAECgEIAQAAAA==.Vermis:BAABNQAECn8/AAIKAAoKzhCoMgDcAQAKAAoKzhCoMgDcAQAAAA==.Veryaverage:BAABNQAECn8oAAMnAAgKXhOABAA8AQABAAgKIhIxeAC9AQAnAAYKPRCABAA8AQAAAA==.Vexation:BAAANQAECgUIDwAAAA==.',
Vi='Vicarious:BAACNQAFFH8GAAIOAAMKDQbmHQCxAAAOAAMKDQbmHQCxAAA1AAQKfz8AAg4ACgrlHP8wAFsCAA4ACgrlHP8wAFsCAAAA.Vidreaux:BAABNQAECn87AAMBAAoK4AsjgwCjAQABAAoKYQsjgwCjAQAmAAIKDwtSMgBiAAAAAA==.Villaraa:BAAANQADCgEIAQAAAA==.Vivid:BAAANQAECgQICQAAAA==.',
Vo='Voidofvoids:BAAANQAECgYICwAAAA==.Volke:BAAANQAECgUICQAAAA==.Volkennoria:BAAANQADCgcIBwABNQAECggIKQAFADobAA==.Voluntas:BAAANQAECgMIAwAAAA==.Votingromney:BAAANQAECgcICgABNQAECgoKKwARAI0lAA==.Vowz:BAAANQADCgMIAwAAAA==.',
Vu='Vulpe:BAABNQAECn8pAAIFAAgKOht1XABgAgAFAAgKOht1XABgAgAAAA==.',
Vy='Vyolenta:BAAANQADCgIIAgAAAA==.',
['Vë']='Vëxhunter:BAAANQAECggIDwAAAA==.',
Wa='Waldorf:BAAANQAECgUICAAAAA==.Wallegator:BAAANQAECgEIAQABNQAECgkJPgAlANsgAA==.Walleroot:BAAANQAECgUIBQABNQAECgkJPgAlANsgAA==.',
We='Weinersoup:BAAANQAECgQIDAAAAA==.',
Wh='Whitewhitch:BAAANQADCgIIAwAAAA==.Whosethetank:BAAANQAECgMIBwAAAA==.',
Wo='Wolfpup:BAAANQAECggICwABNQAECgoKTgADAIwcAA==.Wolfíe:BAAANQADCgUIBQAAAA==.Worstelf:BAABNQAECn8nAAMCAAkKuh4YQABqAgACAAgKPyEYQABqAgASAAgKkx4AIgAlAgAAAA==.',
Ww='Wwalle:BAAANQAECgEIAgABNQAECgkJPgAlANsgAA==.Wwallee:BAAANQADCgMIAwABNQAECgkJPgAlANsgAA==.',
Xa='Xanathos:BAAANQAECgcICwABNQAECgoKPgAFAEclAA==.',
Xi='Xilstar:BAAANQADCgUIBQAAAA==.',
Xz='Xzavier:BAAANQADCggIDwAAAA==.',
Yf='Yfelshammy:BAABNQAECn88AAIOAAoKiBUMTAAzAgAOAAoKiBUMTAAzAgAAAA==.',
Yv='Yvaldi:BAAANQAECgYIBgABNQAFFAIICAACANciAA==.Yvonnél:BAAANQAECgIIAQABNQAECgkJFAAWABQZAA==.',
Za='Zaknafein:BAAANQAECgUICQAAAA==.Zanebusby:BAABNQAECn86AAIhAAoKux9SAQDAAgAhAAoKux9SAQDAAgAAAA==.Zankru:BAAANQADCgYIBwAAAA==.Zaraë:BAAANQADCggIDgAAAA==.Zaria:BAAANQAECgcIDgABNQAECgoKKwARAI0lAA==.Zartash:BAABNQAECn8UAAIfAAgK3AMEPwCuAAAfAAgK3AMEPwCuAAAAAA==.Zatharis:BAABNQAECn8lAAIFAAoKLAg+eADNAQAFAAoKLAg+eADNAQAAAA==.',
Ze='Zelik:BAAANQAECgYICgABNQAECgoKPgAFAEclAA==.Zenezin:BAAANQAECgMIAwABNQAECgkJHwAKAJMdAA==.Zerax:BAABNQAECn8YAAMmAAgKnxGVFQA+AQABAAgKfgh4sgBAAQAmAAcKtxOVFQA+AQABNQAECgoKRQAXADsjAA==.Zevellian:BAAANQADCggIDgABNQAECgcIEQAUAAAAAA==.',
Zm='Zmona:BAABNQAECn8dAAIXAAkKGRSjhQAOAgAXAAkKGRSjhQAOAgABNQAECgkJHwAKAJMdAA==.',
Zo='Zolrath:BAAANQABCgQIAgAAAA==.',
['Ãm']='Ãmpstar:BAAANQAECgEIAQAAAA==.',
['Äm']='Ämpstarr:BAAANQADCgEIAQAAAA==.',
['Çy']='Çyanide:BAAANQADCgQICgABNQAECgkJKgADAIsfAA==.',
['Ðr']='Ðragonshaft:BAABNQAECn9CAAIFAAoKRhVgUwAmAgAFAAoKRhVgUwAmAgAAAA==.Ðreadlokz:BAAANQADCgQIBAAAAA==.',
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
