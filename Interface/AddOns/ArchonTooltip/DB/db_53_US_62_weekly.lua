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

local lookup = {'Paladin-Holy','Hunter-BeastMastery','Unknown-Unknown','Warrior-Arms','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Rogue-Assassination','Druid-Balance','Paladin-Retribution','Mage-Arcane','Monk-Brewmaster','Priest-Holy','Monk-Windwalker','DeathKnight-Blood','DeathKnight-Unholy','Rogue-Subtlety','Druid-Guardian','Mage-Frost','Priest-Shadow','Druid-Feral','DemonHunter-Devourer','DeathKnight-Frost','Hunter-Marksmanship','DemonHunter-Havoc','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','Rogue-Outlaw','Shaman-Enhancement','Warrior-Protection','DemonHunter-Vengeance','Evoker-Preservation','Evoker-Devastation','Druid-Restoration','Paladin-Protection','Evoker-Augmentation','Priest-Discipline','Hunter-Survival',}
local provider = {region='US',realm="Dath'Remar",name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaronius:BAAANQAECgEIAQAAAA==.',
Ab='Abduhl:BAAANQABCgEIAQAAAA==.',
Ad='Ade:BAAANQAECgcIEwAAAA==.Adezardre:BAAANQAECgQIBgAAAA==.Admetriell:BAAANQAECgIIAgABNQAECggIHgABAFsJAA==.Advosary:BAAANQADCggIEAAAAA==.',
Af='Affection:BAAANQADCgMJAwAAAA==.Afflictid:BAAANQABCgIIAgAAAA==.Afterburn:BAAANQAECgQIBAAAAA==.',
Ai='Aigmokthar:BAABNQAECoEiAAICAAgKeBg8OQB6AgACAAgKeBg8OQB6AgAAAA==.',
Ak='Akiriah:BAAANQADCggICAAAAA==.Akirial:BAAANQAECgcIEgABNQAECgcIEwADAAAAAA==.Aklo:BAAANQAECgIIAgAAAA==.',
Al='Alamysia:BAAANQADCgYICwAAAA==.Albertfist:BAAANQADCgMIAwAAAA==.Aletech:BAAANQAECgMIAwAAAA==.Ali:BAAANQAECgYIEwAAAA==.Aliesá:BAAANQAECgMIBAAAAA==.Alilea:BAAANQAECgMIAwAAAA==.Alimagus:BAAANQAECggIDQABNQAFFAUIBgAEAAcWAA==.Alisandrah:BAACNQAFFIEOAAQFAAYKNA83CQByAQAFAAUKnQw3CQByAQAGAAEKJByQEQBdAAAHAAEKjBFQCQBMAAA1AAQKgSYABAYACQrxI8IJAEsCAAUACApmIwEXAAADAAYABwrBHsIJAEsCAAcAAQrDGSUhAEcAAAAA.Alison:BAAANQAECgIIAgAAAA==.Allakeer:BAABNQAECoEfAAIIAAkK8x7OGwBKAgAIAAkK8x7OGwBKAgAAAA==.Allure:BAAANQADCggICAABNQAECgcIFwAJAKcSAA==.Altarios:BAAANQADCggIHAAAAA==.Alyyix:BAAANQADCgYIGwAAAA==.',
Am='Amber:BAAANQAECgMJBQAAAA==.Amberlicious:BAAANQABCggIFgABNQAECgMJBQADAAAAAA==.Amberlily:BAAANQADCggIDgABNQAECgMJBQADAAAAAA==.Ambertastic:BAAANQADCgcIGwABNQAECgMJBQADAAAAAA==.Amilandris:BAABNQAECoExAAIJAAkK/iBQDQBDAwAJAAkK/iBQDQBDAwAAAA==.Amitié:BAAANQADCgYIBgAAAA==.',
An='Analalea:BAAANQAECgEIAQAAAA==.Analdrainal:BAABNQAECoEdAAIEAAgK1iPbGgAuAwAEAAgK1iPbGgAuAwAAAA==.Anghellic:BAAANQADCgYJBgAAAA==.Annaris:BAAANQADCggIGQAAAA==.',
Ap='Apophani:BAAANQADCggIGgAAAA==.Appolo:BAABNQAECoEXAAMKAAcKvSF7PgCRAgAKAAcKvSF7PgCRAgABAAEKOBjA4wBKAAAAAA==.',
Ar='Arcanegasm:BAABNQAECoEVAAILAAgK4x5QZACGAgALAAgK4x5QZACGAgAAAA==.Archii:BAAANQADCgcIBwABNQAECggIIQALAAAXAA==.Archslayer:BAAANQAECgUICgAAAA==.Aresdeekx:BAAANQAECgUICAABNQAECgkJHAAMAP8bAA==.Arneus:BAAANQAECgIIBAAAAA==.Arnir:BAAANQAECgYIEwAAAA==.Arriving:BAABNQAECoEdAAIFAAgKCg9wYwDdAQAFAAgKCg9wYwDdAQAAAA==.Artaq:BAAANQAECgIIBgAAAA==.Artoriöus:BAAANQADCgQIBAABNQAECggIBgADAAAAAA==.Arvanon:BAAANQAECgUIEwAAAA==.',
As='Ashaandra:BAAANQADCgUIBQAAAA==.Ashanar:BAAANQAECgUIDgAAAA==.Asharla:BAAANQAECgUICwAAAA==.Ashbringa:BAAANQAECgMICAAAAA==.Ashhman:BAAANQAECgUICQAAAA==.Ashhunt:BAABNQAECoEkAAICAAgKxx7rIgDTAgACAAgKxx7rIgDTAgAAAA==.Ashmend:BAAANQAECgQIBgAAAA==.Asorrow:BAAANQAECgQICAABNQAFFAMIBQALAH4VAA==.Assatur:BAAANQAECgIIAgAAAA==.Astarna:BAAANQAECgUIDAAAAA==.Asteríx:BAAANQADCgUICQAAAA==.Astier:BAAANQADCgEIAQAAAA==.',
At='Atiatal:BAAANQAECgEIAQAAAA==.Atlasursidae:BAAANQAECgQICAAAAA==.Atoniah:BAAANQAECgQICAAAAA==.',
Au='Auraz:BAABNQAECoEVAAINAAgKMyV6BwBqAwANAAgKMyV6BwBqAwAAAA==.',
Av='Avelinna:BAAANQAECgMIBgABNQAECgUIBQADAAAAAA==.',
Aw='Awan:BAAANQADCgYIFQABNQAECgMICAADAAAAAA==.',
Az='Aztrayel:BAAANQAECgMIBAAAAA==.',
Ba='Baalial:BAAANQAECgQICQAAAA==.Baboya:BAAANQAECggIAQAAAA==.Baelgrim:BAAANQAECgIIAwAAAA==.Balanoth:BAAANQADCgQIBAAAAA==.Baly:BAAANQADCgYIDAABNQAECgkJGwAFAOsWAA==.Bangbangbro:BAAANQAECgYIDwAAAA==.Barium:BAAANQADCgYIEAAAAA==.',
Be='Belfrostbolt:BAAANQAECgQIBQAAAA==.Bentt:BAAANQABCgcICgAAAA==.Bettÿ:BAAANQADCgYIBgABNQAECgUICQADAAAAAA==.',
Bi='Bigjawden:BAAANQADCggIGAAAAA==.Billbee:BAAANQAECgIIBAAAAA==.Bimbohaggins:BAAANQAECgMIBAABNQAECgQIEgADAAAAAA==.Bimbò:BAAANQAECgYIEwAAAA==.Binchicken:BAAANQAECgQIBgAAAA==.Bingler:BAAANQABCgMIAwAAAA==.',
Bj='Bjornhammerz:BAAANQADCgYIBgABNQAECgYICgADAAAAAA==.Bjornshockz:BAAANQAECgYICgAAAA==.',
Bl='Blackvelvet:BAAANQADCgQIBAABNQADCgYIDAADAAAAAA==.Blaz:BAAANQAECgQIDAAAAA==.Blockz:BAAANQADCggIDwAAAA==.Bloodboi:BAAANQADCgcIDgABNQAECgQIBgADAAAAAA==.Bloodyeddy:BAAANQAECgEIAQAAAA==.Bluecups:BAAANQAECgUIDAAAAA==.Bluey:BAAANQAECgMIAwAAAA==.',
Bo='Bobbyboom:BAAANQAECgQIBgAAAA==.Bonedecays:BAAANQADCgMIBAAAAA==.Bontoad:BAAANQAECgMICAAAAA==.',
Br='Brewaresx:BAABNQAECoEcAAMMAAkK/xsKBgC0AgAMAAkK/xsKBgC0AgAOAAYKUwIiQgCaAAAAAA==.Brewboy:BAAANQADCgIIAgABNQAECgQIBgADAAAAAA==.Broxaschor:BAAANQABCgQIAwAAAA==.Brutus:BAABNQAECoEaAAIPAAcKfiArIAB8AgAPAAcKfiArIAB8AgAAAA==.',
Bu='Bubbleduck:BAAANQAECgIJAgAAAA==.Buggzz:BAABNQAECoEeAAICAAcKvCS1JADLAgACAAcKvCS1JADLAgAAAA==.',
Bz='Bzlthazyr:BAABNQAECoEbAAIQAAkK/RlUIQB4AgAQAAkK/RlUIQB4AgAAAA==.',
Ca='Cahtbl:BAAANQAECgIIBAAAAA==.Calasandria:BAAANQAECgIJAgABNQAECggIGQARAC8PAA==.Callin:BAAANQAECgMIBAAAAA==.Calyx:BAAANQADCgYICQAAAA==.Caoimhe:BAAANQADCgIIAgABNQAECgUIDAADAAAAAA==.Cartier:BAAANQAECgQIBgABNQAECgcIFwAJAKcSAA==.Casay:BAAANQAECgYIDQAAAA==.Casbot:BAABNQAECoElAAMRAAkKkRh7CQDGAgARAAkKkRh7CQDGAgAIAAMK+QapXwCVAAAAAA==.Cashmere:BAAANQAECgYIEAABNQAECgcIFwAJAKcSAA==.Castalight:BAAANQAECgQJBgAAAA==.Castlebravo:BAAANQADCgYIBgAAAA==.',
Ce='Cerrylune:BAAANQADCgQIBAAAAA==.',
Ch='Changes:BAAANQADCgcIEgAAAA==.Charish:BAAANQADCgEIAQAAAA==.Charlee:BAAANQADCgcIEgAAAA==.Chirran:BAABNQAECoE2AAISAAgK4SAoBQD2AgASAAgK4SAoBQD2AgAAAA==.Chxdzilla:BAACNQAFFIEJAAIEAAQKIQtDEgAlAQAEAAQKIQtDEgAlAQA1AAQKgSsAAgQACQq8GxUrAOMCAAQACQq8GxUrAOMCAAAA.Chârlie:BAAANQADCgMIAwABNQAECgMIAwADAAAAAA==.',
Ci='Cinnamõn:BAAANQABCgYICwAAAA==.Citryn:BAAANQAECgEIAQABNQAECgkJJwAOAIchAA==.',
Co='Codexo:BAAANQADCggICAAAAA==.Colpamia:BAAANQABCgIIAgAAAA==.Corldrin:BAAANQAECgMIAwAAAA==.Coronis:BAAANQAECgUICQAAAA==.Corriana:BAAANQAECgUIBQAAAA==.Corwin:BAAANQADCgYIGwAAAA==.',
Cr='Crazee:BAACNQAFFIEHAAMTAAMKIxiBBwBdAAALAAIKFhTeLACxAAATAAEKPSCBBwBdAAA1AAQKgSkAAwsACQrxIoQWAGkDAAsACQrxIoQWAGkDABMAAQqFIkosAFsAAAAA.Cruz:BAAANQAECgQICgAAAA==.Crystalflame:BAAANQAECgYIEQAAAA==.Crìsp:BAAANQADCgYICwABNQAECgcIBwADAAAAAA==.',
Ct='Ctshammy:BAAANQAECgUIDQAAAA==.',
Cu='Cultistt:BAABNQAECoEfAAIUAAgKWwocKgCFAQAUAAgKWwocKgCFAQAAAA==.Cursedyou:BAAANQAECgUIDgAAAA==.Curserot:BAAANQAECgYIEAAAAA==.Cuteselenes:BAAANQADCgIIAgAAAA==.',
Cy='Cynal:BAABNQAECoEdAAICAAgK1BM2SwA/AgACAAgK1BM2SwA/AgAAAA==.',
Da='Daddyy:BAAANQAECgQICAABNQAFFAMIBwATACMYAA==.Dammo:BAAANQADCggIGgAAAA==.Dantallion:BAAANQADCgUICAABNQAECgIIAwADAAAAAA==.Dardroc:BAAANQADCgMIAwAAAA==.Darkholme:BAABNQAECoEVAAQVAAcKOBJxFwARAQAJAAYKmgq7VAA0AQAVAAQKkRNxFwARAQASAAMK6hjzJgDSAAAAAA==.Darkk:BAAANQADCgcIDQAAAA==.Darthdraik:BAAANQAECgUICgAAAA==.',
Dc='Dcver:BAABNQAECoEzAAIFAAgKuh8+JgC2AgAFAAgKuh8+JgC2AgAAAA==.',
Dd='Ddraigfach:BAAANQABCgMIAwAAAA==.',
De='Deademeat:BAAANQADCgMIAwAAAA==.Deadlynewbz:BAABNQAECoEhAAMIAAkKHSVZAQDDAwAIAAkKHSVZAQDDAwARAAMKth+sMAD8AAAAAA==.Deathboom:BAAANQADCgUIBQABNQAECgkJKQAWAOQbAA==.Deathbow:BAAANQADCgcIBwAAAA==.Deathbyshoe:BAAANQAECgMICAAAAA==.Deathchain:BAAANQADCgUIBQAAAA==.Deathivy:BAAANQADCgcIIAAAAA==.Deathjam:BAABNQAECoEXAAMQAAYK+RYcSwCCAQAQAAYK+RYcSwCCAQAXAAEKMA7JgAA5AAAAAA==.Deathmore:BAAANQAECgMIBwAAAA==.Deathshrine:BAAANQADCggIDQAAAA==.Decypha:BAABNQAECoEaAAIYAAcKCRd4IQABAgAYAAcKCRd4IQABAgAAAA==.Deidius:BAAANQADCgUIBQAAAA==.Deiwos:BAAANQAECgQIDgAAAA==.Delichtable:BAAANQADCgcIGwABNQAECgUICgADAAAAAA==.Deltora:BAAANQAECgEIAQABNQAECgYJCgADAAAAAA==.Demodog:BAAANQAECgQIEgAAAA==.Demoneddy:BAAANQAECgMIAwAAAA==.Demonicnight:BAAANQAECgcIEAAAAA==.Derryth:BAAANQAECgYIEgAAAA==.Devpro:BAAANQAECgYIEgAAAA==.Devrothas:BAAANQADCgIJAgABNQAECgYIEgADAAAAAA==.Deweysan:BAAANQAFFAEIAQAAAA==.Dexillo:BAACNQAFFIELAAIZAAUKAQu6BgB7AQAZAAUKAQu6BgB7AQA1AAQKgSYAAxkACQoVHFgVALQCABkACQoVHFgVALQCABYACArwDjYoAMQBAAAA.',
Dh='Dhaveira:BAAANQAECgcIEQAAAA==.',
Di='Diggyhole:BAAANQADCgIIAgAAAA==.Divinegirly:BAAANQAECgUIDAAAAA==.',
Do='Dodgeanaxe:BAACNQAFFIEHAAIEAAMK/w9bFwDeAAAEAAMK/w9bFwDeAAA1AAQKgT8AAgQACQrQIRoSAF0DAAQACQrQIRoSAF0DAAAA.Dojoe:BAAANQAECgIIBgABNQAECgcIEgADAAAAAA==.Dorá:BAAANQAECgQIBQAAAA==.',
Dr='Dracnock:BAABNQAECoEbAAIaAAgKdQ4vCgDcAQAaAAgKdQ4vCgDcAQAAAA==.Drapary:BAAANQADCggICAABNQAECgMIAwADAAAAAA==.Drinian:BAAANQAECgQICAAAAA==.',
Du='Ducker:BAACNQAFFIEIAAIOAAQKICX8AwCpAQAOAAQKICX8AwCpAQA1AAQKgSEAAg4ACQpUJn0BAMUDAA4ACQpUJn0BAMUDAAAA.',
Dy='Dylexd:BAAANQAECgcIEgAAAA==.',
['Dã']='Dãwn:BAAANQAECgIIAgABNQAECgMIAwADAAAAAA==.',
Ea='Eatmybolts:BAAANQAECgYIBgAAAA==.',
Ec='Eccentricity:BAAANQAECgUIDAAAAA==.',
El='Eldarion:BAAANQAECgMIBQAAAA==.Electricmon:BAAANQAECgUIDwABNQAFFAMIBwAEAP8PAA==.Elementi:BAAANQADCgIIAgAAAA==.Elfy:BAAANQADCgQIBAABNQAECgIJAgADAAAAAA==.Eliasidris:BAAANQAECgUICwABNQAECgkJHgAYAKoLAA==.Elmaco:BAABNQAECoEYAAMFAAgKlx01OwBkAgAFAAcKUx01OwBkAgAGAAIKtx05QACtAAAAAA==.Elphkilla:BAAANQADCggICAAAAA==.Elroth:BAAANQADCgYICgAAAA==.Elseapi:BAAANQAECgUIDgAAAA==.Elyssae:BAABNQAECoEdAAILAAgKdSBFRwDRAgALAAgKdSBFRwDRAgAAAA==.',
En='Endarios:BAAANQAECgMIBQAAAA==.Endsplit:BAAANQAECgUIDQAAAA==.Ent:BAAANQAECgIIBAAAAA==.',
Er='Erzalockhart:BAAANQAECgMIAwAAAA==.',
Es='Esmaralda:BAAANQADCggIGwAAAA==.',
Et='Etnie:BAAANQADCgYIBgAAAA==.',
Ev='Everleaf:BAAANQADCgQIBgAAAA==.Eviion:BAABNQAECoEZAAMbAAgK/haWOwApAgAbAAgK/haWOwApAgAcAAIKtgf/5QBUAAABNQAECgkJHgAYAKoLAA==.',
Ez='Ezoth:BAAANQAECgQIBQAAAA==.',
Fa='Fallendivine:BAABNQAECoEdAAILAAgKRgw2tADOAQALAAgKRgw2tADOAQAAAA==.Fausts:BAAANQAECggIBgAAAA==.',
Fe='Fearen:BAAANQADCgUICgAAAA==.Feetenjoyer:BAAANQADCgMJAwAAAA==.Feipo:BAACNQAFFIEFAAMTAAMKtRWeAwCuAAATAAIKLBieAwCuAAALAAEKxhDIQQBSAAA1AAQKgSAAAgsACQo0HLeqAOIBAAsACQo0HLeqAOIBAAAA.Felissa:BAAANQAECgIIAgABNQAECgQIBgADAAAAAA==.Fensmage:BAAANQAECgcICAAAAA==.Feralbuffkty:BAABNQAECoEaAAIQAAkKKx+tFwDEAgAQAAkKKx+tFwDEAgAAAA==.Fere:BAABNQAECoEbAAIdAAgKKCCPAwDCAgAdAAgKKCCPAwDCAgAAAA==.Feurekt:BAABNQAECoE2AAIEAAgKaiDlLQDXAgAEAAgKaiDlLQDXAgAAAA==.',
Fi='Finitaur:BAAANQADCgQIBwAAAA==.Fiz:BAAANQADCggICAABNQAFFAQIBwAHAEwMAA==.',
Fl='Flashinlight:BAAANQAECgUICgAAAA==.Flashstép:BAABNQAECoEZAAMRAAgKLw9HFwABAgARAAgKLw9HFwABAgAIAAEKpgc9dQA4AAAAAA==.Flipside:BAAANQAECgcIEgAAAA==.',
Fo='Fomor:BAAANQAECgYIDgAAAA==.Forbs:BAAANQAECgMIAgAAAA==.Foreignerr:BAACNQAFFIEGAAIEAAUKBxYMCwCaAQAEAAUKBxYMCwCaAQA1AAQKgSQAAgQACQqfH14gABMDAAQACQqfH14gABMDAAAA.',
Fr='Franziscka:BAAANQADCggIGwAAAA==.Friggincute:BAAANQADCgEIAQAAAA==.Frogstomp:BAAANQADCgQIBAAAAA==.',
Fu='Furbold:BAAANQAECgYIDwABNQAECggIDwADAAAAAA==.',
['Fí']='Fíredup:BAAANQAECgUIBwABNQAECgkJGQAEADQXAA==.',
Ga='Galeira:BAAANQAECgMIBwAAAA==.Gallene:BAACNQAFFIERAAIEAAUKfB0vCQC6AQAEAAUKfB0vCQC6AQA1AAQKgUsAAgQACQo8JbYEAMQDAAQACQo8JbYEAMQDAAAA.Gandallf:BAAANQADCgUIEQABNQAECgMIBgADAAAAAA==.Garakarak:BAAANQAECgYIDAAAAA==.Garthinian:BAAANQADCgYICQAAAA==.Garthpally:BAAANQADCgUIBQAAAA==.',
Ge='Genimaculata:BAABNQAECoEaAAIMAAcK6xyWCgArAgAMAAcK6xyWCgArAgAAAA==.Germ:BAAANQADCgIIAgAAAA==.Gerothos:BAAANQADCgQIBAAAAA==.Geîsha:BAAANQADCgMIAwAAAA==.',
Gh='Ghislaine:BAAANQADCggIDQAAAA==.Ghöst:BAAANQAECgQIBAABNQAECggIBgADAAAAAA==.',
Gi='Girthquake:BAAANQAECgYIDAABNQAECgcIIQAEAKciAA==.',
Gl='Gladios:BAAANQAECgEJAQAAAA==.Glarry:BAAANQADCggICAABNQAECgkJHgABAC8eAA==.Glidelicator:BAABNQAECoEdAAIZAAgKZAwGMQDBAQAZAAgKZAwGMQDBAQAAAA==.Glittervein:BAAANQADCgUIBQABNQADCgMIAwADAAAAAA==.',
Go='Goodasnew:BAAANQADCggJGwAAAA==.Gooditoshoes:BAAANQAECgEIAgAAAA==.Gortopia:BAAANQADCgYIDwAAAA==.Goshin:BAAANQADCgYICQAAAA==.Gosublood:BAAANQAECggIDwAAAA==.Gosupriest:BAAANQAECgcIEAABNQAECggIDwADAAAAAA==.Gozhancesham:BAAANQADCgUIBQAAAA==.',
Gr='Graggy:BAABNQAECoEeAAMBAAkKLx57EAAlAwABAAkKLx57EAAlAwAKAAEKmwvfRAE4AAAAAA==.Grapejelly:BAABNQAECoEhAAIWAAgKRR+MDgDfAgAWAAgKRR+MDgDfAgAAAA==.Grashk:BAAANQAECgUIDQAAAA==.Grimbel:BAAANQAECgUIDQAAAA==.Grimcritical:BAAANQAECgMIAwAAAA==.',
['Gø']='Gødspeed:BAAANQAECgIIAwAAAA==.',
Ha='Hadeshunt:BAAANQAECgUIEwAAAA==.Halibelle:BAAANQADCgYJBgAAAA==.Halzarius:BAAANQAECgQIEwAAAA==.Handyshammy:BAABNQAECoEgAAIeAAgK4iDzBQAGAwAeAAgK4iDzBQAGAwAAAA==.Handywar:BAABNQAECoEaAAIEAAcKTBgOeQDbAQAEAAcKTBgOeQDbAQABNQAECggIIAAeAOIgAA==.Hans:BAAANQAECgUIDgAAAA==.Happyheala:BAAANQAECgUIBQAAAA==.Harleybear:BAAANQADCgcIFAAAAA==.',
Hi='Hitamnya:BAAANQABCgQIBgABNQAECgkJHgAYAKoLAA==.',
Ho='Holyknox:BAAANQAECggIDwAAAA==.Holymender:BAAANQADCggJDgAAAA==.Holymick:BAAANQAECggIDwAAAA==.',
Hu='Hulkamania:BAAANQADCgUICAAAAA==.Humble:BAAANQAECggIDwAAAA==.',
Hy='Hydromender:BAAANQAECgcIEgAAAA==.Hyperactiv:BAAANQAECgQIBgAAAA==.Hypothermia:BAAANQAECgMIAwABNQAECgUICgADAAAAAA==.',
['Hô']='Hôllôw:BAAANQAECggIDAAAAA==.',
['Hø']='Høpeless:BAABNQAECoEaAAIBAAgK+xE/RgALAgABAAgK+xE/RgALAgAAAA==.',
Ic='Icyblast:BAAANQAECgIIBAAAAA==.Icycookiex:BAAANQAECgQIBAABNQAECgcIEQADAAAAAA==.Icymilkyx:BAAANQAECgcIEQAAAA==.',
Ig='Igneel:BAAANQADCgYIDAAAAA==.',
Il='Illigniteyou:BAABNQAECoE7AAILAAgKsyHlNwD7AgALAAgKsyHlNwD7AgAAAA==.Illiranii:BAAANQADCgYIBgABNQAECgUIBQADAAAAAA==.Illumine:BAAANQAECgEIAQAAAA==.',
In='Inosolan:BAAANQAECgUICQAAAA==.Inurfacevegi:BAAANQAECgUIBwAAAA==.',
Io='Iolololol:BAAANQAECgUICAABNQAFFAIIAwAQAA8FAA==.Iozt:BAAANQAFFAEIAQAAAA==.',
Ir='Ironpork:BAAANQADCgcIBwAAAA==.Irralis:BAAANQAECgUIBQABNQAFFAYIEQALADYiAA==.Irritable:BAAANQAECgUIDgAAAA==.Irvina:BAABNQAECoElAAICAAcKgBtHUwAnAgACAAcKgBtHUwAnAgAAAA==.Irvinebrown:BAAANQADCgIIBAABNQAECgcIJQACAIAbAA==.Irvinia:BAAANQADCggIHAABNQAECgcIJQACAIAbAA==.',
Is='Iskarius:BAAANQAECgUJCAAAAA==.Istenn:BAAANQAECgUICQAAAA==.',
It='Ithyl:BAAANQAECgMIBAAAAA==.Itzshammy:BAABNQAECoEdAAIbAAgK7yDrGgDSAgAbAAgK7yDrGgDSAgAAAA==.',
Iv='Ivanoviaa:BAAANQADCgMIAwAAAA==.',
Ix='Ixiöm:BAAANQAECgEIAQABNQAECggIBgADAAAAAA==.',
Ja='Jabmojorjo:BAAANQADCgMIAwAAAA==.Jackdaw:BAAANQABCgIIAgAAAA==.Janinda:BAABNQAECoEbAAIKAAgKHSTcKgDhAgAKAAgKHSTcKgDhAgAAAA==.Jastina:BAAANQAECgUIDAAAAA==.Jaszz:BAAANQAECgcIEQAAAA==.',
Jb='Jb:BAAANQAECgcIBwAAAA==.',
Je='Jelly:BAAANQADCggIFgAAAA==.Jengil:BAAANQAECgQIBgAAAA==.Jengol:BAAANQADCgcIBwAAAA==.Jesto:BAABNQAECoEwAAIfAAgKFSDqBQDNAgAfAAgKFSDqBQDNAgAAAA==.',
Jh='Jhonn:BAAANQAECgQICQAAAA==.',
Ji='Jincuiki:BAAANQAECgIIAgAAAA==.',
Jo='Jodiefroster:BAAANQAECgEIAQAAAA==.Joeseppe:BAAANQAECgYIDAABNQAECgcIEgADAAAAAA==.Joeslildk:BAAANQAECgcIEgAAAA==.Joshst:BAAANQADCgcIIwAAAA==.Josta:BAAANQAECgcIDwABNQAECggIMAAfABUgAA==.Josto:BAAANQAECgYIBgABNQAECggIMAAfABUgAA==.Jovyll:BAAANQAECgUICwAAAA==.Joyboyluffy:BAAANQAECgEJAQAAAA==.',
Ju='Jurodice:BAABNQAECoEeAAIBAAgKWwkFZACdAQABAAgKWwkFZACdAQAAAA==.',
['Jå']='Jårko:BAAANQADCgYICwAAAA==.',
Ka='Kaahla:BAAANQADCgEIAQAAAA==.Kaelinth:BAAANQADCgcICgAAAA==.Kaelyth:BAAANQAECgUIDgAAAA==.Kamakazie:BAAANQAECgQICAAAAA==.Kamelle:BAAANQADCggIEgAAAA==.Karmerre:BAAANQAECgIIAwAAAA==.Karramerre:BAAANQADCgUIBQABNQAECgIIAwADAAAAAA==.Kaydeebug:BAAANQAECgQIDwAAAA==.Kayna:BAABNQAECoEkAAIOAAcKdA4IKQBuAQAOAAcKdA4IKQBuAQAAAA==.',
Ke='Kellanis:BAAANQAECgcIEQAAAA==.Kelugar:BAAANQADCgIIAgAAAA==.Kerenarye:BAACNQAFFIEHAAIgAAQKux7JAQDcAAAgAAQKux7JAQDcAAA1AAQKgRQAAyAACQrPH9ACAAUDACAACAotItACAAUDABYABwoKCggyAG0BAAAA.Keyez:BAAANQAECgYIBgABNQAECggIHAAUAKILAA==.',
Kh='Khaladore:BAABNQAECoEWAAIBAAgKfh73GwDXAgABAAgKfh73GwDXAgAAAA==.Kharazhan:BAAANQAECgYIDwAAAA==.',
Ki='Kiilbill:BAAANQAECgIIBAABNQAECgQIEgADAAAAAA==.Killshotbob:BAAANQAECgIIBAAAAA==.Kinkyheaven:BAAANQAECgQIBgAAAA==.Kinnigit:BAABNQAECoEgAAIXAAcKYghxRAAzAQAXAAcKYghxRAAzAQAAAA==.Kinstalz:BAAANQAECgYIDAAAAA==.Kiotia:BAAANQADCgYIFQAAAA==.Kipp:BAAANQAECgYIEAAAAA==.Kiril:BAAANQADCgUIBQAAAA==.Kirky:BAAANQADCgUJCgAAAA==.Kitenna:BAAANQADCgIIAgABNQAECgYIEwADAAAAAA==.Kithraah:BAABNQAECoEdAAMXAAgKjBAnMgCtAQAXAAgK/g4nMgCtAQAQAAcKywx5VgBRAQABNQAFFAEIAQADAAAAAA==.Kithrah:BAAANQAFFAEIAQAAAA==.Kithrâh:BAAANQAECgEIAQABNQAFFAEIAQADAAAAAA==.',
Kn='Knifeparty:BAAANQAECgYICwAAAA==.',
Ko='Kolugar:BAABNQAECoEiAAIPAAkKESTLBQCDAwAPAAkKESTLBQCDAwAAAA==.Konkar:BAAANQAECgYIEgAAAA==.',
Kr='Kradon:BAAANQAECgUIDAAAAA==.Kreedan:BAAANQADCgcJBwABNQAECgcIFgAEADAWAA==.Kruphix:BAABNQAECoEUAAMVAAcKARgfCwAUAgAVAAcKxhcfCwAUAgASAAQKiBaeIgD3AAAAAA==.Krysania:BAAANQADCgQIBAABNQAECggIFgABAH4eAA==.',
Ku='Kudreanne:BAAANQADCgYIGwAAAA==.Kuri:BAAANQADCggICAAAAA==.Kuzzo:BAAANQAECgIIAgAAAA==.',
La='Laiceeshay:BAABNQAECoEeAAICAAgKBBHzUgAoAgACAAgKBBHzUgAoAgAAAA==.Lars:BAAANQAECgYIEAAAAA==.Larxe:BAAANQAECgYICwAAAA==.',
Le='Legendaïry:BAAANQAECgQIBgAAAA==.Letmedie:BAABNQAECoEdAAMaAAYKpAtZEQA5AQAaAAYKKgtZEQA5AQAEAAYKzwYNugAbAQAAAA==.Lexillo:BAAANQAECgUICAAAAA==.',
Li='Liaravara:BAAANQAECgEIAQABNQAECgUIBwADAAAAAA==.Lightmender:BAAANQADCgQIBAAAAA==.Lightschamp:BAAANQADCgQIBAABNQAECgQIBgADAAAAAA==.Lilhunty:BAAANQADCgMIAwAAAA==.Lilldemon:BAAANQADCgcIDgAAAA==.Lizzo:BAABNQAECoEhAAMhAAcKJx1QEwBJAgAhAAcKJx1QEwBJAgAiAAIKmAiuLQBiAAAAAA==.',
Lo='Locksorry:BAAANQABCggICAABNQAFFAUICQAFAKYMAA==.Lorieyxo:BAAANQAECgMIBAAAAA==.Lorrim:BAAANQAECgQICAAAAA==.Louron:BAAANQADCgYIBgAAAA==.',
Lu='Luena:BAAANQAECgcIBwAAAA==.Lunabi:BAAANQAECgcIEwABNQAECgkJJwAOAIchAA==.Lute:BAAANQADCgYIBgAAAA==.Luxdae:BAAANQADCgEIAQAAAA==.',
Ly='Lyrannia:BAABNQAECoEhAAILAAgKGxtHYQCOAgALAAgKGxtHYQCOAgAAAA==.Lyrindanna:BAAANQADCgEIAQAAAA==.Lyth:BAABNQAECoEdAAIMAAgKGB+JBQDIAgAMAAgKGB+JBQDIAgAAAA==.',
['Lá']='Láiken:BAAANQADCgYJGwAAAA==.',
Ma='Madmoxxie:BAAANQADCgUIBQAAAA==.Mageapayne:BAAANQADCgYJBgAAAA==.Magetom:BAAANQAECgEIAQAAAA==.Maghan:BAAANQADCgQICAAAAA==.Magicus:BAAANQAECgcICgAAAA==.Magikaze:BAAANQAECgcIEwAAAA==.Mahgo:BAAANQAECgYICgAAAA==.Maidenkio:BAAANQADCgEIAQAAAA==.Maikara:BAAANQAECgIIBQAAAA==.Majinoodle:BAAANQADCgcIBwAAAA==.Malfalcator:BAAANQADCgMIAwAAAA==.Mantori:BAAANQADCgEIAQAAAA==.Marieh:BAAANQAECgMIAwAAAA==.Marleer:BAAANQADCggICAABNQAECgQIDQADAAAAAA==.Martha:BAAANQABCgcICAAAAA==.Maryberry:BAAANQAECgQIBAAAAA==.Massan:BAAANQADCgUIBQAAAA==.Masscarnage:BAABNQAECoEpAAIFAAgKIB1QJgC2AgAFAAgKIB1QJgC2AgAAAA==.Maywina:BAABNQAECoEZAAILAAgKhyGoPADuAgALAAgKhyGoPADuAgABNQAECgkJMQAJAP4gAA==.Mazhun:BAAANQAECgYIEAAAAA==.',
Me='Meaculpa:BAABNQAECoEeAAMKAAcK2hMqggC/AQAKAAcK2hMqggC/AQABAAQK7gP2wwChAAAAAA==.Mediqua:BAAANQADCgQIAQAAAA==.Megaflame:BAAANQADCgYIGAAAAA==.Mekkii:BAAANQADCgIIAgABNQAFFAIIAwAQAA8FAA==.Mekky:BAACNQAFFIEDAAIQAAIKDwVZEQB7AAAQAAIKDwVZEQB7AAA1AAQKgSUAAhAACQqMGsEfAIQCABAACQqMGsEfAIQCAAAA.Melonheadx:BAAANQADCgIIAgAAAA==.Meltharion:BAAANQAECgEJAgAAAA==.Mercerful:BAAANQADCgUICQAAAA==.Mereaux:BAAANQADCggICwAAAA==.Methex:BAAANQAECgcIDQAAAA==.Metzger:BAAANQAECgIIBAAAAA==.',
Mi='Mingi:BAAANQADCggIEwABNQAECgcIHAAGAAEYAA==.Minigore:BAABNQAECoErAAICAAgKtiB/IgDVAgACAAgKtiB/IgDVAgAAAA==.Mirya:BAAANQAECgMIBAAAAA==.Mishamigo:BAAANQAECgYIEAAAAA==.Missharmony:BAAANQAECgUIDQAAAA==.Misstickles:BAAANQAECgQICgAAAA==.',
Mo='Moistfisting:BAAANQADCggICAABNQAFFAQICAAJAK8YAA==.Moistpawjob:BAACNQAFFIEIAAIJAAMKrxgcDwADAQAJAAMKrxgcDwADAQA1AAQKgSIAAwkACQqpJJMKAGADAAkACQqpJJMKAGADACMAAgoOGx5IAJEAAAAA.Moistpole:BAAANQADCgcJDAAAAA==.Mojostormale:BAAANQADCgEIAQAAAA==.Monanarr:BAAANQADCgEIAgABNQAECgQICgADAAAAAA==.Monmonk:BAAANQAECgQICgAAAA==.Monotok:BAAANQADCgQIAQAAAA==.Moograin:BAAANQABCgQIBAAAAA==.Moonalisa:BAAANQADCgcIIAAAAA==.Moondropz:BAAANQAECgMIAwAAAA==.Moonsblood:BAAANQAECgQICwAAAA==.Moontara:BAAANQAECgcIDwAAAA==.Moopsy:BAAANQAECgQIDwAAAA==.Mops:BAAANQAECgQIBgAAAA==.',
Mu='Muldoom:BAAANQABCgYIBgAAAA==.Mur:BAAANQAECgUIDQAAAA==.Murdertoys:BAAANQADCgcIBwAAAA==.',
My='Mycotoxin:BAAANQAECgMIBwAAAA==.Myoxidae:BAAANQADCgEIAQAAAA==.Myrrdan:BAAANQAECgcIDAAAAA==.Myrrh:BAAANQADCgEIAQAAAA==.Mysst:BAAANQAECgUIDAAAAA==.Mysteerie:BAAANQAECgYIEAAAAA==.Mythlogic:BAABNQAECoEZAAIjAAYKzwgdNQAIAQAjAAYKzwgdNQAIAQAAAA==.Mythsham:BAAANQADCgcIGAAAAA==.',
['Má']='Mángo:BAABNQAECoEdAAMFAAgKaBLzXQDvAQAFAAgKeRDzXQDvAQAGAAUKFwtBKwAPAQAAAA==.',
['Mí']='Místress:BAAANQAECgEJAQAAAA==.',
['Mù']='Mùshu:BAAANQADCgYIBgAAAA==.',
Na='Nardaran:BAAANQAECggIDAAAAA==.Natsumi:BAAANQAECgMIAwABNQAECgkJKAAPAIEdAA==.',
Ne='Needcoffee:BAAANQAECgEIAQAAAA==.Neemixa:BAAANQAECgMIBAAAAA==.Neonh:BAAANQADCggIGgAAAA==.Nereval:BAAANQAECgQIBAABNQAECgkJMQAJAP4gAA==.',
Ni='Nicksshaman:BAAANQADCgEIAQAAAA==.Nightwissh:BAAANQAECgUIDgAAAA==.Nitestar:BAAANQADCgUIEAAAAA==.Nitevoker:BAAANQAECgMIBgAAAA==.',
No='Nocturnus:BAAANQADCgQJDAAAAA==.Nordvoker:BAABNQAECoEcAAIhAAgKtwleHwCYAQAhAAgKtwleHwCYAQAAAA==.Nospheratu:BAABNQAECoE4AAILAAkKhxv/SgDHAgALAAkKhxv/SgDHAgABNQADCgYIBgADAAAAAA==.',
Nu='Nubu:BAAANQADCggIHAAAAA==.Nukin:BAAANQABCgIJAgAAAA==.',
Ny='Nycepala:BAAANQADCggIGgAAAA==.Nylaith:BAAANQADCgUIBQAAAA==.Nyni:BAECNQAFFIENAAIPAAUKoguiDAAkAQAPAAUKoguiDAAkAQA1AAQKgScAAg8ACQo1GUQeAIoCAA8ACQo1GUQeAIoCAAAA.Nythshade:BAAANQADCgcIDAAAAA==.Nyxe:BAEANQAECgEIAQABNQAFFAUIDQAPAKILAA==.',
['Nü']='Nümnüts:BAAANQAECgIIBAAAAA==.',
Of='Offworlder:BAAANQADCggIFwAAAA==.',
Ol='Olokun:BAAANQABCgYJBwAAAA==.',
On='Onlyhoofs:BAEBNQAECoEfAAIbAAkKkBs1HwC5AgAbAAkKkBs1HwC5AgAAAA==.Onyq:BAAANQAECgYIBgABNQAFFAQIBwAgALseAA==.',
Oo='Oofm:BAABNQAECoEgAAMMAAcKugsYGgDpAAAMAAYKMwcYGgDpAAAOAAMKsg8ZPQC/AAAAAA==.Oospider:BAAANQAECgIIBgAAAA==.',
Op='Ophearia:BAAANQADCgcIFQAAAA==.Optimiss:BAAANQAECgUIDAAAAA==.',
Or='Orcboy:BAABNQAECoEWAAIEAAcKMBbleQDZAQAEAAcKMBbleQDZAQAAAA==.Ordia:BAAANQADCgcIDgAAAA==.Orken:BAAANQADCgEIAQAAAA==.Orthanu:BAAANQADCgUIBQAAAA==.',
Os='Osamul:BAAANQADCgYIBgAAAA==.',
Oz='Ozxenia:BAAANQAECgEIAQAAAA==.',
Pa='Paieth:BAAANQAECgYIEgAAAA==.Palacid:BAAANQAECggICAAAAA==.Paladerp:BAABNQAECoEhAAIBAAgKiCagBACXAwABAAgKiCagBACXAwAAAA==.Palaresx:BAAANQAECgQIBwABNQAECgkJHAAMAP8bAA==.Palean:BAAANQABCgQIAgAAAA==.Pallyshunter:BAABNQAECoEhAAICAAgKIRo4NwCBAgACAAgKIRo4NwCBAgAAAA==.Pancake:BAAANQAECgQIBAAAAA==.Panchamp:BAAANQADCgcJDgAAAA==.Pandamourne:BAAANQADCgcICQAAAA==.Pandori:BAABNQAECoEaAAIbAAcKUib+EgAFAwAbAAcKUib+EgAFAwAAAA==.Panetar:BAAANQABCggICAAAAA==.Parchmentham:BAABNQAECoEgAAMNAAgKnRteMQBgAgANAAgKnRteMQBgAgAUAAEKnhC6YgAxAAAAAA==.Paryniux:BAAANQAECgMIAwAAAA==.Patience:BAAANQAECgcIBgAAAA==.',
Pe='Peridrax:BAAANQADCggJCAAAAA==.',
Ph='Phenergen:BAAANQADCggICAABNQAECgIIAwADAAAAAA==.',
Pi='Pinchiy:BAAANQADCgQIBAAAAA==.Pinkpanthir:BAAANQAECgUIDQAAAA==.',
Pj='Pjay:BAAANQAECgIIAwAAAA==.',
Pl='Plisky:BAAANQAECgMIBAAAAA==.',
Po='Pollywaffle:BAAANQADCggIDAAAAA==.Portals:BAAANQADCggIEAAAAA==.Poùnd:BAAANQADCgcIEwABNQAECgkJGQAEADQXAA==.',
Pr='Praiseme:BAAANQADCgYIEwAAAA==.Predz:BAAANQAECgYIEAAAAA==.Predzious:BAAANQAECgQIBQABNQAECgYIEAADAAAAAA==.Prepaired:BAAANQADCggICAABNQAFFAYIIAAHAIYaAA==.Pretzelmix:BAAANQADCgYIBgAAAA==.Priestiitute:BAAANQADCgUIBQAAAA==.',
Ps='Psyreq:BAAANQAECgUIBwAAAA==.',
Pu='Pucker:BAAANQADCgQIBAABNQAECgUIGgAhAN4TAA==.Punkey:BAAANQAECgYIDgAAAA==.Purplemad:BAAANQADCgEIAQAAAA==.',
Qu='Quartquartma:BAAANQAECgMICAAAAA==.',
Ra='Raedia:BAAANQADCgMIAwAAAA==.Raft:BAAANQADCggICAAAAA==.Rahll:BAAANQABCggIDgAAAA==.Raindrops:BAAANQADCggICAAAAA==.Rainsberg:BAAANQADCgUIBQAAAA==.Raje:BAAANQADCggIDgAAAA==.Ravachiar:BAABNQAECoEaAAIWAAYKxhXPLACaAQAWAAYKxhXPLACaAQABNQAECgcIFwAEAMQUAA==.Ravenathas:BAAANQADCgUIEgABNQAECgIIBAADAAAAAA==.Ravenimus:BAAANQAECgIIBAAAAA==.Ravic:BAAANQAECggICgAAAA==.Razeld:BAAANQADCggIGgAAAA==.Razhun:BAAANQAECgUIDAAAAA==.Razia:BAAANQAECgIIAwAAAA==.Razzax:BAAANQADCgUIBQAAAA==.Razzmata:BAABNQAECoEXAAIKAAgKChtDSABvAgAKAAgKChtDSABvAgAAAA==.',
Re='Reckendorf:BAAANQAECgEIAgAAAA==.Redefine:BAAANQAECgQJBwAAAA==.Reflet:BAAANQAECgUJBgAAAA==.Rell:BAAANQAECgYIBwAAAA==.Rentress:BAAANQADCgYIFwAAAA==.Resolution:BAAANQADCggICAAAAA==.Restik:BAAANQADCggIFQAAAA==.Revyre:BAAANQAECgQJBAAAAA==.Rexxnaar:BAAANQAECgQICAAAAA==.Rexy:BAABNQAECoEaAAMJAAgKkhsLIgCHAgAJAAgKkhsLIgCHAgAjAAUKJh4QJgCOAQAAAA==.',
Rh='Rhiari:BAAANQADCggICAABNQAECgMIBQADAAAAAA==.Rhiotannis:BAAANQAECgYIDAAAAA==.Rhombus:BAAANQADCgYIBgAAAA==.Rhots:BAAANQAECgYJEAAAAA==.',
Ri='Ricketyrekt:BAAANQADCgcIBwAAAA==.Rimara:BAABNQAECoEZAAIGAAYKGQjuJwAiAQAGAAYKGQjuJwAiAQAAAA==.Rishari:BAAANQAECgMIAwAAAA==.',
Ro='Rocadin:BAAANQAECgYIEAAAAA==.Rocmon:BAAANQADCgYIBgABNQAECgYIEAADAAAAAA==.Rorisala:BAAANQADCgYICwABNQAECgUIBwADAAAAAA==.Rottlee:BAAANQAECgEIAQAAAA==.Rowshamboe:BAAANQADCgYIGwAAAA==.Rozabella:BAABNQAECoEaAAIJAAcK9Bm0LQArAgAJAAcK9Bm0LQArAgAAAA==.',
Ru='Rune:BAAANQAECgIIAgABNQAECggIFgAWAMEWAA==.',
['Rê']='Rêdemption:BAAANQAECgIIAgAAAA==.Rêdylive:BAAANQAECgQICQAAAA==.',
['Rï']='Rïkku:BAAANQAECgYJCgAAAA==.',
['Rø']='Røgue:BAAANQADCgIIBQABNQAECgMIBQADAAAAAA==.',
Sa='Saelska:BAAANQAECgEIAQAAAA==.Sahven:BAAANQADCgYICQAAAA==.Sakuraharu:BAABNQAECoEgAAILAAcKvRFztgDJAQALAAcKvRFztgDJAQAAAA==.Sakuraharune:BAAANQAECgYIDwAAAA==.Sakuraharuno:BAABNQAECoEhAAIRAAgKfR/eBwDnAgARAAgKfR/eBwDnAgAAAA==.Sakuura:BAAANQAECgUIDgAAAA==.Sarang:BAAANQAECgYJEQAAAA==.Sassystrasza:BAAANQADCgQIBAAAAA==.Savagepaw:BAAANQAECgcIEQAAAA==.',
Sc='Scarbi:BAAANQAECgEJAQAAAA==.Scarbz:BAAANQAECgYIEAAAAA==.Scrtchnsniff:BAAANQABCgQIAwAAAA==.',
Se='Sehun:BAAANQADCgcIFQABNQAECgcIHAAGAAEYAA==.Selennys:BAAANQAECgIIBQAAAA==.Selest:BAAANQAECgQICAAAAA==.',
Sh='Shadowkain:BAAANQAECgUIDAAAAA==.Shadowtrix:BAAANQADCggICAAAAA==.Shadøws:BAABNQAECoEaAAIRAAgKdAieHADJAQARAAgKdAieHADJAQAAAA==.Shagz:BAAANQADCgYIGAAAAA==.Shallios:BAAANQADCgYIEAAAAA==.Shamajov:BAAANQADCgYIDgABNQAECgUICwADAAAAAA==.Shamankiing:BAAANQADCgYIDAAAAA==.Shamannigans:BAAANQAECgMIBgAAAA==.Shammyhagar:BAAANQAECgIIAwAAAA==.Shamnow:BAAANQADCgEIAQAAAA==.Sharkweek:BAAANQAECgQIBAABNQAECgkJHAAMAP8bAA==.Shaytan:BAAANQAECgQICgAAAA==.Sheogorath:BAABNQAECoEkAAIkAAgKESBRCgC3AgAkAAgKESBRCgC3AgAAAA==.Shocksocks:BAAANQAECgYIEQAAAA==.Shoujian:BAAANQAECgQJCAAAAA==.',
Si='Sianien:BAAANQAECgcICAAAAA==.Sickology:BAABNQAECoEjAAIKAAgK6BMsagADAgAKAAgK6BMsagADAgAAAA==.Siinatra:BAABNQAECoEYAAMBAAkKaBhpIAC9AgABAAkKaBhpIAC9AgAKAAQKDB5srgBQAQAAAA==.Siinatrah:BAABNQAECoEaAAMKAAkKoCIBEwBbAwAKAAkKoCIBEwBbAwABAAMKZAnDugC3AAABNQAECgkJGAABAGgYAA==.Silverstarr:BAAANQADCgYIDAAAAA==.Sinnafein:BAAANQADCgcIBwAAAA==.Siohban:BAAANQAECgUIDAAAAA==.Sionel:BAAANQADCgUIBQABNQADCgYICgADAAAAAA==.Siphirahah:BAAANQAECgUICgAAAA==.',
Sk='Skürge:BAAANQAECgMIBQAAAA==.',
Sl='Slapntits:BAAANQABCgcIDQAAAA==.Slimreaper:BAAANQAECggIEAAAAA==.Slothination:BAABNQAECoEaAAIVAAgKhyDfBADqAgAVAAgKhyDfBADqAgABNQAECgkJGgAQACsfAA==.Slurrydots:BAABNQAECoEfAAMNAAkKjRwvEQAUAwANAAkKjRwvEQAUAwAUAAMKVgdOTgB5AAAAAA==.',
Sm='Smellymango:BAAANQAECgMJAwAAAA==.',
Sn='Snaglvr:BAAANQADCgQJBQAAAA==.Snappyb:BAAANQADCgIIAgAAAA==.Snorichäun:BAAANQAECgMIAwAAAA==.Snowtownz:BAABNQAECoEcAAMiAAgKERgfDQBbAgAiAAgKERgfDQBbAgAlAAIKOwpFGQBQAAAAAA==.Snörichäun:BAAANQADCgcIEAAAAA==.Snöríchäûn:BAAANQAECgIIAgAAAA==.',
So='Soiboii:BAAANQADCgQJBAAAAA==.Sokraxx:BAACNQAFFIEFAAIfAAMKASTNAQA9AQAfAAMKASTNAQA9AQA1AAQKgR8AAh8ACQrSJQ4IAIkCAB8ACQrSJQ4IAIkCAAAA.Sonozap:BAABNQAECoEYAAIcAAgKowzQWADIAQAcAAgKowzQWADIAQAAAA==.Sonyc:BAAANQADCgQIBAAAAA==.Soothlocked:BAAANQAECgIIBQAAAA==.Soraflash:BAAANQADCggICAAAAA==.Soulreaperau:BAAANQAECgEJAQAAAA==.',
Sp='Spearzy:BAAANQAECgQIBgABNQAECgkJGQAEADQXAA==.Spicedgoat:BAAANQAECgMIAwAAAA==.Spinandwin:BAABNQAECoEhAAIEAAcKpyL1OACrAgAEAAcKpyL1OACrAgAAAA==.Springroll:BAABNQAECoEbAAIOAAgKbB6NEQCRAgAOAAgKbB6NEQCRAgAAAA==.',
Sq='Squishikayla:BAAANQADCgMIAwAAAA==.Squishyman:BAABNQAECoEeAAILAAgKvBO1kAAcAgALAAgKvBO1kAAcAgAAAA==.',
Sr='Sram:BAABNQAECoEiAAMXAAkKISIdBwBOAwAXAAkKISIdBwBOAwAPAAEKcwgktQAnAAAAAA==.Srbenda:BAAANQADCgUJDgAAAA==.',
Ss='Sstormmy:BAABNQAECoEhAAICAAgKuRAqWAAZAgACAAgKuRAqWAAZAgAAAA==.',
St='Stabit:BAAANQAECgUIBgAAAA==.Starless:BAAANQAECgQJBQAAAA==.Starmyst:BAAANQADCgYIBgAAAA==.Steelbull:BAABNQAECoEXAAIEAAcKxBSMeQDaAQAEAAcKxBSMeQDaAQAAAA==.Steelmyth:BAABNQAECoEXAAIgAAgKBhKWCgDPAQAgAAgKBhKWCgDPAQAAAA==.Steeven:BAAANQADCgIIAgAAAA==.Stev:BAAANQAECgEIAQAAAA==.Strìder:BAAANQAECgIIAgAAAA==.Strîder:BAAANQAECgYIEwAAAA==.',
Su='Summerskye:BAAANQAECgcIEwAAAA==.',
Sy='Sy:BAABNQAECoEZAAMUAAcKPhzVGgApAgAUAAcKPhzVGgApAgANAAIKsBH+ugBdAAABNQAECgkJGwAQAP0ZAA==.Sycamore:BAAANQAECgUICgAAAA==.Sydor:BAAANQADCggJLwAAAA==.Sylennia:BAAANQAECgEJAgAAAA==.Sylvatrix:BAAANQAECgUIDAAAAA==.Symbiont:BAAANQADCgcIGQAAAA==.',
Sz='Szarni:BAAANQAECgQICgAAAA==.',
Ta='Tabitrisao:BAAANQAECgEIAQAAAA==.Talastor:BAAANQADCgMJAwAAAA==.Tamarin:BAAANQABCgIIAgAAAA==.Taridalas:BAAANQAECgUIBwAAAA==.Taucetid:BAAANQAECgQICQAAAA==.Tazington:BAABNQAECoEXAAIKAAcKnhVdewDSAQAKAAcKnhVdewDSAQAAAA==.Tazmage:BAAANQADCgcIBwAAAA==.Tazuki:BAAANQABCgIIAgAAAA==.',
Te='Tehsharp:BAABNQAECoEXAAMCAAcKcR/XRABTAgACAAcKcR/XRABTAgAYAAEKIwjocAAwAAAAAA==.Tehwarrior:BAAANQABCgcIBwAAAA==.Telraena:BAAANQAECgUICgAAAA==.Terokkar:BAAANQAECgUIDgAAAA==.Tesalach:BAAANQAECgQIBwAAAA==.Teul:BAABNQAECoEXAAMBAAkKcwevWQDCAQABAAkKcwevWQDCAQAKAAQKSQNSDwGMAAABNQAECgkJKAAbAMITAA==.',
Th='Thalorian:BAAANQAECgUJCAAAAA==.Thananerion:BAAANQADCgMIAwAAAA==.Thealiaa:BAAANQADCgIIAgAAAA==.Thehexorcist:BAAANQADCggIDQAAAA==.Thiea:BAABNQAECoEcAAMKAAgKbRYkZwAMAgAKAAgKbRYkZwAMAgAkAAEKwAt3XgAmAAAAAA==.Thorel:BAAANQADCgcICAABNQAECgkJHgAYAKoLAA==.Thorrimar:BAAANQADCgUIBQAAAA==.Thorsake:BAAANQAECgYIEAAAAA==.Thromgorr:BAABNQAECoEZAAMbAAgKRx8cHADLAgAbAAgKRx8cHADLAgAcAAEKbxik6wBHAAAAAA==.Thunderboo:BAAANQADCgYIBgABNQAECgkJGQAEADQXAA==.Thundercant:BAAANQAECggIEgABNQAFFAcIEAAmAJgUAA==.Thunderpog:BAACNQAFFIEQAAMmAAcKmBQ4AAB7AgAmAAcKmBQ4AAB7AgAUAAEKCg3EEQBGAAA1AAQKgR0ABBQACQr8HakUAHwCABQACApNHakUAHwCAA0ABwq3F0NcAKsBACYABAoUHbcMADYBAAAA.',
Ti='Tillicity:BAABNQAECoEoAAMbAAkKCBqYKwB1AgAbAAkKCBqYKwB1AgAcAAIKbxsVyACeAAAAAA==.Tilzabeth:BAAANQADCgQICgABNQAECgkJKAAbAAgaAA==.Timewarp:BAAANQADCggIBQAAAA==.Tinhu:BAAANQAECgEIAQAAAA==.Tinypi:BAAANQAECgYICwAAAA==.Titanuss:BAAANQADCgcIBwAAAA==.Tivarah:BAAANQADCggICwAAAA==.',
To='Tomahawk:BAAANQADCgEIAQAAAA==.Toosuss:BAAANQADCgcIEQAAAA==.Topshot:BAABNQAECoEXAAICAAcKuyMPJQDKAgACAAcKuyMPJQDKAgAAAA==.Torags:BAAANQADCgQIBAAAAA==.Totemorlusta:BAAANQADCgMIAwABNQADCgMIBAADAAAAAA==.',
Tr='Trazendeath:BAAANQADCgMIAwAAAA==.Treesome:BAABNQAECoEXAAIJAAcKpxKAPQC5AQAJAAcKpxKAPQC5AQAAAA==.Treesource:BAAANQAECgQIBQAAAA==.Trigaa:BAAANQADCggIDAAAAA==.Trojans:BAAANQAECgEIAQAAAA==.',
Ts='Tsaiko:BAAANQAECgIIBAAAAA==.',
Tu='Tuku:BAAANQADCgQIBQABNQAECgMIBgADAAAAAA==.',
Tw='Twirls:BAABNQAECoEZAAMEAAkKNBcDVQBJAgAEAAgKkxcDVQBJAgAaAAEKPBThJABBAAAAAA==.Twirlshair:BAAANQADCgUIBQAAAA==.',
Ty='Tynzel:BAAANQAECgUICAAAAA==.Tyvaria:BAAANQADCgcIEQAAAA==.',
['Tà']='Tàkhisis:BAAANQAECgIIBQAAAA==.',
Ul='Ullbenxt:BAAANQAECgIIAgAAAA==.',
Um='Umf:BAAANQADCggIEQABNQAECggIIAANAJ0bAA==.',
Un='Underwhelmed:BAAANQAECgMJBAAAAA==.Unitofglory:BAAANQADCgIIAgABNQAECggIIgANAPUkAA==.Unitoflife:BAABNQAECoEiAAINAAgK9ST4BwBkAwANAAgK9ST4BwBkAwAAAA==.Unitofshapes:BAAANQAECgUJCQABNQAECggIIgANAPUkAA==.',
Up='Upndown:BAAANQAECgIIAgAAAA==.',
Va='Valanar:BAAANQADCgMIAwAAAA==.Valdormu:BAAANQAECgYJDgAAAA==.Vanador:BAAANQAECgQIBQAAAA==.Vanarel:BAAANQAECgEIAQAAAA==.Vanel:BAAANQAECgMIAwAAAA==.Vannbeef:BAAANQAECgUIDAAAAA==.Varthlight:BAAANQAECgUICgAAAA==.',
Ve='Veinytotem:BAAANQADCgUIBQAAAA==.Veloran:BAACNQAFFIEMAAMCAAMK9g0lDgD4AAACAAMK9g0lDgD4AAAYAAEKjwcNHABDAAA1AAQKgT8ABAIACQoDG0onAMACAAIACQpzGkonAMACABgACAoiD4gsAJEBACcAAgrkC38NAGUAAAAA.Venomsspawn:BAAANQAECgYIEwAAAA==.Vernonia:BAAANQADCgcICAAAAA==.Vexahlia:BAAANQADCgQJBgAAAA==.Veyrathor:BAAANQADCgIIAgAAAA==.',
Vi='Vio:BAACNQAFFIEXAAIbAAcKgBhKAQB+AgAbAAcKgBhKAQB+AgA1AAQKgS0AAxsACQrTJIQEAJADABsACQrTJIQEAJADABwABArYF+qTABsBAAAA.Virtues:BAAANQADCgMIAwAAAA==.Virtus:BAAANQADCgYIBwAAAA==.Viserys:BAAANQAECgQIBwAAAA==.',
Vo='Voidtouched:BAAANQADCgYIBgABNQAECgkJGQAEADQXAA==.Vows:BAAANQAECgQICAAAAA==.',
Vu='Vuruul:BAAANQADCgYIDAAAAA==.',
Vy='Vypërz:BAABNQAECoEhAAMbAAgKKSXjCgBIAwAbAAgKKSXjCgBIAwAcAAEKOggr+gA0AAAAAA==.Vyral:BAABNQAECoEhAAIPAAgKiQz2SACRAQAPAAgKiQz2SACRAQAAAA==.',
Wa='Wabssevo:BAAANQAECgQIBAABNQAFFAYIDQABAHQTAA==.Wabssjnr:BAACNQAFFIENAAIBAAYKdBPUAwD5AQABAAYKdBPUAwD5AQA1AAQKgSAAAgEACQqGIQ8HAHoDAAEACQqGIQ8HAHoDAAAA.Wararesx:BAAANQADCgUIBwABNQAECgkJHAAMAP8bAA==.Warizard:BAAANQAECgUIEwAAAA==.Wattanuhbii:BAAANQADCgQJBAAAAA==.Wayz:BAAANQAECgIIAgAAAA==.Wayzpala:BAAANQADCggIDAAAAA==.',
We='Weyoun:BAAANQAECgUICQAAAA==.',
Wh='Wheetie:BAAANQAECgUIEAAAAA==.',
Wi='Williwaw:BAAANQAECgIIAwAAAA==.Winterstormm:BAAANQAECgUIDQAAAA==.',
Wn='Wno:BAAANQADCgcIBwAAAA==.',
Wo='Wobbuffet:BAACNQAFFIEHAAIcAAQKgiNCBwCgAQAcAAQKgiNCBwCgAQA1AAQKgR4AAhwACQp/JAIFALQDABwACQp/JAIFALQDAAAA.Wolfen:BAAANQADCgcIDgAAAA==.',
Wy='Wyrnn:BAABNQAECoEcAAIXAAgKCSNqDAABAwAXAAgKCSNqDAABAwAAAA==.',
['Wå']='Wåyz:BAAANQADCggICAAAAA==.',
Xa='Xaniran:BAAANQADCgYICAAAAA==.Xaye:BAAANQAECgQIBQAAAA==.',
Xe='Xelbino:BAAANQADCgEIAQAAAA==.',
Xi='Xiaobi:BAABNQAECoEnAAMOAAkKhyEjBgBOAwAOAAkKhyEjBgBOAwAMAAYKrhB9FQBBAQAAAA==.Xiiath:BAAANQAECgQIBAAAAA==.Xintar:BAAANQADCggIEAAAAA==.Xiomana:BAAANQAECgMIBgAAAA==.Xion:BAABNQAECoEcAAMGAAcKARhaGwCDAQAFAAcKUhOxXwDpAQAGAAUKohpaGwCDAQAAAA==.',
Xy='Xyluna:BAAANQADCgYIBgABNQAECgkJJgANANccAA==.',
Ye='Yebanned:BAAANQADCggICAABNQAFFAYIHQACACobAA==.Yellowajah:BAAANQAECgQIEwABNQAECgkJKgAEAP0bAA==.',
Yi='Yify:BAAANQADCgUIBQABNQAECgIIBAADAAAAAA==.',
Yn='Yneva:BAAANQAECgEIAgAAAA==.',
Yo='Yogan:BAAANQADCgQIBAAAAA==.',
Yw='Ywrensire:BAAANQADCgQIBAAAAA==.',
Za='Zaabra:BAAANQAECgMIBgAAAA==.Zaion:BAAANQAECgMIBgAAAA==.',
Ze='Zealis:BAAANQAECgUICAAAAA==.Zebby:BAAANQAECgYIEQAAAA==.Zedar:BAAANQAECgUJBQABNQAECggIMwAFALofAA==.Zerull:BAAANQADCgYIBgAAAA==.',
Zh='Zhi:BAAANQAECgQICwAAAA==.',
Zi='Zilin:BAAANQAECgQIDQAAAA==.',
Zo='Zolce:BAAANQAECgIIAgABNQAECgYJDwADAAAAAA==.',
Zu='Zurbi:BAAANQAECgEIAQABNQAECgkJJwAOAIchAA==.Zuularok:BAAANQADCgUIBQAAAA==.',
Zy='Zybaxos:BAABNQAECoEkAAIJAAgKaCAeGADaAgAJAAgKaCAeGADaAgAAAA==.Zyth:BAAANQAECgUIBwAAAA==.',
Zz='Zzro:BAAANQADCggICgAAAA==.',
['Àw']='Àwkward:BAAANQADCgQIAwAAAA==.',
['Ãr']='Ãrçâñîst:BAAANQAECgMIAwAAAA==.',
['År']='Årchon:BAAANQAECgQIBAABNQAECgYIEAADAAAAAA==.Årtix:BAAANQADCgYIBgABNQADCgYICgADAAAAAA==.',
['Îs']='Îssy:BAAANQAECgUICAAAAA==.',
['Ôr']='Ôrkásh:BAAANQADCgcIDgAAAA==.',
['Öm']='Ömegoss:BAAANQAECgQIDwAAAA==.',
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
