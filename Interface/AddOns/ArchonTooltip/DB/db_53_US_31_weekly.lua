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

local lookup = {'Unknown-Unknown','Warlock-Affliction','DeathKnight-Unholy','Paladin-Retribution','Druid-Balance','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Frost','Hunter-BeastMastery','Rogue-Outlaw','Rogue-Assassination','Warrior-Arms','Druid-Feral','Priest-Holy','Paladin-Holy','Mage-Frost','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','Monk-Windwalker','Shaman-Elemental','Priest-Discipline','Rogue-Subtlety','Shaman-Restoration','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Mage-Arcane','Priest-Shadow','Paladin-Protection','DemonHunter-Devourer','Warrior-Protection','Druid-Guardian','Warrior-Fury','DemonHunter-Vengeance',}
local provider = {region='US',realm='BlackDragonflight',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aarkan:BAAANQAECgYIDwAAAA==.',
Ac='Acaelis:BAAANQAECggIBgAAAA==.Acanialyn:BAAANQADCgYICwAAAA==.',
Ad='Adamastor:BAAANQAECgMIAwABNQAECgQIDAABAAAAAA==.Adamastora:BAAANQADCgQIBAABNQAECgQIDAABAAAAAA==.Adea:BAABNQAECoEjAAICAAgK3xKsBgAZAgACAAgK3xKsBgAZAgAAAA==.',
Ae='Aeiro:BAABNQAECoEgAAIDAAgKLx58KQBxAgADAAgKLx58KQBxAgAAAA==.Aetheriel:BAAANQAECgQICgAAAA==.',
Ai='Aireez:BAAANQADCgUIBQAAAA==.Airrin:BAAANQAECgMIBQAAAA==.',
Aj='Ajoseywales:BAABNQAECoEcAAIEAAkK6CJRIgAiAwAEAAkK6CJRIgAiAwAAAA==.',
Ak='Akatala:BAAANQAECgYIEwAAAA==.Akunda:BAAANQAECgIIAgAAAA==.',
Al='Alaanth:BAAANQABCggIDgAAAA==.Alamaania:BAAANQAECgYICwAAAA==.Alaterial:BAAANQADCgUIBQAAAA==.Alexz:BAAANQADCgcICAAAAA==.Aloha:BAACNQAFFIEQAAMFAAUKfxoRCQC4AQAFAAUKfxoRCQC4AQAGAAEKzQIHEwBBAAA1AAQKgTAAAwUACQqZJG8DAL4DAAUACQqZJG8DAL4DAAYAAwrvDLFTAIoAAAAA.Aluriel:BAABNQAECoEgAAQHAAkK0Bg5RwBfAgAHAAkKBBY5RwBfAgACAAIKiyAjGACoAAAIAAEKfxb+aQBCAAAAAA==.',
Am='Ambellína:BAAANQADCgcIBwAAAA==.Amenrah:BAAANQADCgQIBAAAAA==.',
An='Androse:BAABNQAECoEnAAIEAAkK+h3dMADnAgAEAAkK+h3dMADnAgAAAA==.',
Ap='Apollon:BAAANQAECgQIBAAAAA==.',
Ar='Arclîght:BAABNQAECoEcAAIJAAkKQwpwOAC6AQAJAAkKQwpwOAC6AQAAAA==.Argyle:BAAANQAECgYIDwAAAA==.Arilu:BAAANQAECgIJBAAAAA==.Arkerite:BAAANQADCggIDwAAAA==.Arnix:BAAANQAECgUIBQABNQAECgUIBwABAAAAAA==.Aruj:BAABNQAECoEiAAQKAAkKIBeGMgAlAgAKAAcK0BuGMgAlAgALAAkKHw9kMwDUAQADAAEKNgi10AAvAAAAAA==.Aruz:BAAANQAECggICAAAAA==.',
As='Ashkari:BAABNQAECoEbAAILAAgKQR39HAB7AgALAAgKQR39HAB7AgAAAA==.Asteraceae:BAAANQADCgEIAQABNQAECgcIHgAMAO0TAA==.Astrea:BAAANQADCgEIAQAAAA==.',
At='Athenis:BAAANQAECgIIAgAAAA==.Atulan:BAAANQAECgYIAgAAAA==.',
Au='Auphelia:BAAANQADCgQIBQAAAA==.',
Av='Aviendho:BAAANQAECgUICQAAAA==.',
Ay='Ayhanu:BAAANQADCgEIAQABNQAECggIHAANAGocAA==.Ayllata:BAAANQAECgQICAAAAA==.',
Az='Azmythr:BAACNQAFFIEVAAIOAAYKeSUaAQCKAgAOAAYKeSUaAQCKAgA1AAQKgRsAAw4ACQocJtcDAIkDAA4ACQocJtcDAIkDAA0AAgr0G94UAIUAAAAA.Azzaerial:BAAANQADCgIIAgAAAA==.Azzrael:BAAANQADCgEIAQAAAA==.',
Ba='Barek:BAABNQAECoETAAIEAAcKhx7+SgCMAgAEAAcKhx7+SgCMAgAAAA==.Bartahk:BAABNQAECoEWAAIPAAgKnxl2TgCEAgAPAAgKnxl2TgCEAgAAAA==.Barto:BAAANQADCggICAAAAA==.Baxtercham:BAAANQAECgYIBgABNQADCgQIBAABAAAAAA==.Baxterpala:BAAANQAECggIEwABNQADCgQIBAABAAAAAA==.Baxters:BAAANQAECgYIBgABNQADCgQIBAABAAAAAA==.',
Be='Belenn:BAAANQAECgQIBwAAAA==.Belquise:BAAANQADCgYIDAAAAA==.Benosh:BAAANQAECgQIBAAAAA==.Betræÿer:BAAANQAECgQIBAAAAA==.Beyondthedk:BAAANQAECgMJBAAAAA==.',
Bi='Bigkahunas:BAABNQAECoEzAAIMAAgKhh9LLwC9AgAMAAgKhh9LLwC9AgAAAA==.Bigman:BAAANQADCgQIBAAAAA==.Bignut:BAAANQADCgYICwABNQAECgkJKAAQADAjAA==.Bigzacky:BAABNQAECoEZAAIRAAkKDSSaBACaAwARAAkKDSSaBACaAwAAAA==.Bilcaster:BAABNQAECoEcAAMHAAcKHgm2ngBqAQAHAAcKHgm2ngBqAQAIAAMKJwRpVQB0AAAAAA==.Billytell:BAAANQADCggJCAABNQAECgYIAgABAAAAAA==.',
Bj='Björntorock:BAAANQADCggICAAAAA==.',
Bl='Bladlast:BAABNQAECoEeAAISAAgKbBPeUQAFAgASAAgKbBPeUQAFAgAAAA==.Blankee:BAACNQAFFIEQAAITAAUKpR1qAADJAQATAAUKpR1qAADJAQA1AAQKgSQAAhMACQrsJdcAAJcDABMACQrsJdcAAJcDAAAA.Blankey:BAAANQAECggIDQAAAA==.Blargo:BAAANQAECgUIBQAAAA==.Bloodraven:BAAANQAECgQICAAAAA==.Bloomthetank:BAAANQADCgQIBAAAAA==.',
Bo='Bobloblawl:BAEANQADCggJCAAAAA==.Bombisevil:BAACNQAFFIESAAQMAAYKzhEPDQBNAQAMAAQKLxAPDQBNAQAUAAQKHQnGAAAvAQAVAAMKEBKiEwDQAAA1AAQKgSIABAwACQq0Iow/AIgCAAwABwpdJIw/AIgCABQABwpIHvkGAOgBABUABAoBEsdDAAcBAAAA.Boomins:BAAANQAECgMIBQAAAA==.Booz:BAAANQADCgEIAQABNQAECgUIBQABAAAAAA==.Booze:BAABNQAECoEdAAMWAAkK/yI1BQA2AwAWAAkK/yI1BQA2AwAXAAQKIiF1LACDAQABNQAECgUIBQABAAAAAA==.Bophades:BAAANQADCgYICwAAAA==.Borbadin:BAAANQAECgYIAgAAAA==.Borgîr:BAABNQAECoEmAAIYAAkK3hr5KAC7AgAYAAkK3hr5KAC7AgAAAA==.Bossee:BAABNQAECoEdAAIRAAkKmR0CEAAxAwARAAkKmR0CEAAxAwABNQAFFAUIEAATAKUdAA==.Bowfdeez:BAAANQADCggICQAAAA==.',
Br='Bracven:BAAANQADCgYICgAAAA==.Bradadin:BAAANQAECgMIBgAAAA==.Bradmage:BAAANQADCgEIAQABNQAECgMIBgABAAAAAA==.Bralex:BAAANQABCgIIAgAAAA==.Braydor:BAAANQAECgQIBwAAAA==.Broggzal:BAAANQAECgQIDQAAAA==.Bruisy:BAABNQAECoEaAAMRAAgKsCESEgAkAwARAAgKsCESEgAkAwAZAAQKfxt7DQBGAQABNQAECgUIBQABAAAAAA==.Brusque:BAAANQAECgEIAgAAAA==.',
Bu='Bubblerus:BAAANQAECgUIBQAAAA==.Bubbleturts:BAAANQAECgQIBAAAAA==.Bullpal:BAAANQADCgUIBQAAAA==.Burmiya:BAAANQADCgcIDAAAAA==.Buzzlightwgt:BAAANQABCgIIBAAAAA==.',
Bw='Bwomdalah:BAAANQAECgQIBQAAAA==.Bwonurmomdi:BAAANQADCgYICAAAAA==.',
Ca='Caffeineboy:BAAANQABCgQIBwAAAA==.Caitastrophe:BAABNQAECoEYAAIaAAcKtRFKHgDLAQAaAAcKtRFKHgDLAQAAAA==.Calyssta:BAABNQAECoEiAAMYAAgKaB0WKwCvAgAYAAgKaB0WKwCvAgAbAAYKmSEpRAAlAgAAAA==.Cantbeatcook:BAAANQAECgYIEwAAAA==.Cantou:BAABNQAECoEdAAIQAAgKIxxsCACcAgAQAAgKIxxsCACcAgAAAA==.Captcosmo:BAAANQAECgYIDAAAAA==.Catchdahands:BAAANQAECgQIBAABNQAFFAQICQAcAL8aAA==.',
Ch='Chaosbrand:BAAANQAECgYIDgAAAA==.Chaoticks:BAAANQADCgEJAQABNQAECgIIAgABAAAAAA==.Charízard:BAAANQAECggIAQAAAA==.Chickenfried:BAAANQAECgEIAgAAAA==.Chico:BAAANQAECgQIDAAAAA==.Chillax:BAAANQAECgEIAQAAAA==.Chills:BAAANQAECggIDQABNQAECgkJKgAWAFgdAA==.Chithris:BAAANQAECgQIBAAAAA==.Chodoge:BAABNQAECoEsAAQdAAkKkx6NBgALAwAdAAkKjx6NBgALAwAeAAUKVw8FLAAiAQAfAAMKqxsLEQD4AAAAAA==.Chopsooey:BAAANQAECgIIAwAAAA==.Choriza:BAAANQADCgcIBwAAAA==.Chriglol:BAAANQAECggIAQAAAA==.Chrisdk:BAAANQAECgYIDwAAAA==.Chungi:BAAANQADCgYICgAAAA==.',
Ci='Ciilokkar:BAAANQAECgQIBQABNQAECggIHgAgAGUaAA==.Ciimagi:BAABNQAECoEeAAIgAAgKZRo7dQB9AgAgAAgKZRo7dQB9AgAAAA==.Cirno:BAABNQAECoEeAAIhAAgKYBqmGQBfAgAhAAgKYBqmGQBfAgAAAA==.',
Cl='Clamcast:BAABNQAECoETAAIgAAgKOx0KWQC8AgAgAAgKOx0KWQC8AgAAAA==.Clawsome:BAAANQADCgUIBQAAAA==.Cleetarus:BAABNQAECoEsAAMMAAgKIB0MOACgAgAMAAgKIB0MOACgAgAVAAIKQgRLbgBQAAAAAA==.Clíché:BAAANQAECgQICgAAAA==.',
Co='Cocodiablo:BAABNQAECoEiAAILAAgK9h2bHAB/AgALAAgK9h2bHAB/AgAAAA==.Cocoñut:BAAANQAECgEIAQAAAA==.Consecrasian:BAAANQAECgEIAQAAAA==.Constantino:BAAANQAECgYIEQAAAA==.Contagious:BAAANQADCgYIBgAAAA==.Copenfist:BAAANQAECggIDgABNQAECggIHgAYAAciAA==.Copenshock:BAABNQAECoEeAAIYAAgKByJ1HAAGAwAYAAgKByJ1HAAGAwAAAA==.Coraa:BAAANQAECgYIEgAAAA==.',
Cr='Crataegus:BAAANQADCgEIAQABNQAECgcIHgAKAA8aAA==.Creammachine:BAAANQAECgcIEwABNQAECgkJKAAQADAjAA==.Creepsly:BAAANQADCgMIAwAAAA==.',
Cu='Curseddemon:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Cursedflight:BAAANQAECgQIBAAAAA==.Cursedpsyko:BAAANQABCgEIAQAAAA==.',
Cw='Cwem:BAABNQAECoEVAAMEAAgKrBi6WABjAgAEAAgKrBi6WABjAgAiAAEKWgZycwAaAAAAAA==.',
Da='Daddee:BAEANQADCgMIAwABNQAECggIKgAgAFYhAA==.Dagobert:BAAANQAECgQIEAAAAA==.Damien:BAAANQADCggIDgABNQAECggIHgAPACgKAA==.Dancemagic:BAAANQADCgYIBgAAAA==.Daolin:BAAANQADCgQIBAAAAA==.Darkian:BAAANQAECgQIBAAAAA==.Dasani:BAAANQAECgcIEAABNQAECgcIEAABAAAAAA==.Davinia:BAAANQAECgUICwAAAA==.',
De='Dean:BAABNQAECoEaAAIjAAgK/BrOGgBmAgAjAAgK/BrOGgBmAgAAAA==.Deathsidhe:BAAANQAECggIBgAAAA==.Deithknight:BAAANQADCggICgAAAA==.Demonchainz:BAAANQAECgYIBwAAAA==.Demoncook:BAAANQAECgIIBAABNQAECgYIEwABAAAAAA==.Demono:BAAANQAECgQIBAAAAA==.Demons:BAAANQAECgYICQAAAA==.Denishath:BAAANQABCgEIAQAAAA==.Depression:BAACNQAFFIELAAIeAAUKUAmmCgBRAQAeAAUKUAmmCgBRAQA1AAQKgRkAAh4ACArvFIsUAFICAB4ACArvFIsUAFICAAE1AAUUBQgKABYAzhMA.Deputymeow:BAAANQADCgcIDgAAAA==.Desalination:BAAANQADCggICQABNQAFFAUIEAAFAH8aAA==.Desiusrye:BAABNQAECoEeAAIPAAgKKAoCnACsAQAPAAgKKAoCnACsAQAAAA==.Deusvûlt:BAAANQAECggIAQAAAA==.Deyjavaknadi:BAAANQADCgYIGQAAAA==.Deûsvûlt:BAAANQAECggJAgAAAA==.',
Di='Diela:BAAANQADCgcIBwAAAA==.Digitalis:BAAANQAECgMIAwAAAA==.Dikaiosýni:BAAANQADCgEIAQABNQAECgcIGgAkAFMVAA==.Diona:BAAANQADCggIDQAAAA==.Disco:BAACNQAFFIEVAAIRAAYKMRxLBQAkAgARAAYKMRxLBQAkAgA1AAQKgSEAAxEACQr7JZ4GAIIDABEACQq8JZ4GAIIDABkACApNHdADAIwCAAAA.Divinesmite:BAABNQAECoEYAAMRAAUKUxgzhABQAQARAAUKUxgzhABQAQAhAAMKhgXXWAB0AAAAAA==.',
Dk='Dkandy:BAABNQAECoElAAILAAgKrSWXBwBXAwALAAgKrSWXBwBXAwAAAA==.Dkykin:BAACNQAFFIEFAAIFAAIKqBIXGgCfAAAFAAIKqBIXGgCfAAA1AAQKgSQAAgUACQr1ICsXAPYCAAUACQr1ICsXAPYCAAAA.',
Do='Dotsrus:BAABNQAECoEgAAIHAAkKLiF8CgBmAwAHAAkKLiF8CgBmAwAAAA==.Downfawl:BAABNQAECoEdAAMLAAgKjhLyMQDeAQALAAgKIxLyMQDeAQADAAQKNxE6jADOAAABNQAFFAUICwAFAMQKAA==.',
Dr='Dracculus:BAAANQAECgUICwAAAA==.Draginballz:BAAANQAECgYIEQAAAA==.Dragonuts:BAAANQADCgEIAQAAAA==.Drakthor:BAAANQAECgQIBwAAAA==.Draxus:BAAANQADCggICAAAAA==.Dreamsteam:BAAANQADCgYIBgAAAA==.Dregar:BAABNQAECoEXAAIXAAcKxxYJJwC3AQAXAAcKxxYJJwC3AQAAAA==.Dresdenn:BAAANQADCggIEAAAAA==.Drogamel:BAAANQADCgEIAQAAAA==.Drstab:BAAANQAECgUIEQAAAA==.Drujitsu:BAAANQADCgEIAQAAAA==.Drágám:BAAANQAECgMIAwAAAA==.',
Du='Duck:BAAANQAECgMIBAAAAA==.Dundrin:BAAANQADCgUIBwAAAA==.Durf:BAAANQAECgUICgAAAA==.Duska:BAABNQAECoEYAAIEAAcKTAZ63QAmAQAEAAcKTAZ63QAmAQAAAA==.',
Dy='Dyondra:BAAANQAECgYIDwAAAA==.Dyspare:BAAANQAECgEIAQAAAA==.',
['Dî']='Dîmmu:BAAANQADCggIEAAAAA==.',
Ea='Eamoon:BAAANQAECgQIBAAAAA==.Eatchikn:BAAANQAECgcIEwAAAA==.',
Ed='Edah:BAAANQADCggIDwAAAA==.',
Ee='Eeblez:BAAANQADCgIIAgAAAA==.Eevah:BAABNQAECoEeAAMMAAcK7RN/cgD+AQAMAAcK7RN/cgD+AQAVAAUKRg3mQQAUAQAAAA==.',
El='Elementsmash:BAAANQAECgMJAwAAAA==.Elepanda:BAAANQAECgQICAAAAA==.Eleventeen:BAAANQAECgYIEAAAAA==.Ellipsisfear:BAAANQADCgUIBQAAAA==.Elosai:BAAANQAECgcIEwAAAA==.',
Em='Emesis:BAAANQADCgUIBQAAAA==.',
Er='Erzsi:BAAANQABCgcIEgAAAA==.',
Es='Eseri:BAAANQAECgcIDwABNQAECggIDwABAAAAAA==.Esreaver:BAAANQAECgQIBwAAAA==.',
Fa='Failing:BAAANQADCgEIAQABNQAECgUIDwABAAAAAA==.Fangaxe:BAACNQAFFIENAAIkAAQKOBthAgA5AQAkAAQKOBthAgA5AQA1AAQKgSAAAyQACQpjIL8EABYDACQACQpjIL8EABYDAA8ABQobGuakAJUBAAAA.Fangbane:BAAANQAFFAEIAgAAAA==.',
Fe='Felaequitas:BAABNQAECoEcAAIEAAgKJhDakwDHAQAEAAgKJhDakwDHAQAAAA==.Feltaco:BAAANQADCgUJCQABNQAECgQIBAABAAAAAA==.Fentastic:BAAANQAECgEIAQAAAA==.Fentrock:BAAANQAECgYICAAAAA==.',
Fi='Fidelius:BAAANQADCgUJBQAAAA==.Fisticuffs:BAABNQAECoEcAAIWAAcK+Q0xIABgAQAWAAcK+Q0xIABgAQAAAA==.',
Fl='Flameburg:BAAANQADCgQJBAAAAA==.Floshotmoo:BAABNQAECoEbAAIGAAcKpQtMMwBLAQAGAAcKpQtMMwBLAQAAAA==.',
Fo='Forestasian:BAAANQAECgcIDgAAAA==.Foxytotem:BAAANQADCggIBQAAAA==.',
Fr='Fragii:BAABNQAECoEdAAMMAAcKxBGrfADlAQAMAAcKxBGrfADlAQAUAAEKHQmlEQAxAAAAAA==.Frierenn:BAAANQADCgYICAAAAA==.Friggi:BAAANQADCggIFAAAAA==.',
Ga='Galakrond:BAAANQAECgEJAQAAAA==.Galaxum:BAAANQADCgEIAQAAAA==.Galford:BAAANQADCgUJBQAAAA==.Galindrae:BAAANQAECgQIBAAAAA==.Garana:BAAANQAECgEIAQABNQADCgYIDAABAAAAAA==.Garzha:BAAANQADCgYIDAAAAA==.Gaypoc:BAAANQAECgUIBQAAAA==.',
Ge='Gehenna:BAAANQAECgQIBwAAAA==.Gelado:BAAANQADCgYICQAAAA==.Gershas:BAABNQAECoEqAAIPAAgK+yBwMADpAgAPAAgK+yBwMADpAgAAAA==.Gezebel:BAAANQAECgYIEQAAAA==.',
Gh='Ghiberti:BAAANQAECgYIDwAAAA==.Ghostvaladra:BAAANQADCgMIAwAAAA==.Ghouldamn:BAAANQADCggIJAAAAA==.Ghðst:BAAANQAECgYIEQAAAA==.',
Gl='Glarghal:BAABNQAECoEoAAIRAAkKUiADEgAkAwARAAkKUiADEgAkAwAAAA==.Glasscanon:BAAANQADCggIGAAAAA==.',
Gn='Gnomagi:BAAANQADCgMIAwABNQAECggIHgAgAGUaAA==.',
Go='Gokuu:BAAANQAECgQIBQAAAA==.Golnada:BAABNQAECoEkAAIcAAgKGhP+EAA7AgAcAAgKGhP+EAA7AgAAAA==.Goodmamita:BAAANQAECgIIAgAAAA==.Gooseymane:BAAANQAECgUIBQAAAA==.Goosily:BAAANQADCgEIAQAAAA==.',
Gr='Grapebevrage:BAAANQAECgcIEgAAAA==.Greentouch:BAAANQADCgQIBAAAAA==.Grewt:BAACNQAFFIELAAIFAAUKxArQDQBbAQAFAAUKxArQDQBbAQA1AAQKgSEAAgUACQrfHP0dAL4CAAUACQrfHP0dAL4CAAAA.Grögin:BAABNQAECoEYAAIgAAcKxBKEygDMAQAgAAcKxBKEygDMAQAAAA==.',
Gu='Gulunga:BAAANQAECgUICAAAAA==.',
Gw='Gwashington:BAAANQAECgUIDwAAAA==.',
Ha='Halestormdh:BAABNQAECoEiAAIjAAkKpBd4FwCKAgAjAAkKpBd4FwCKAgAAAA==.Haolin:BAAANQADCgYJBgAAAA==.Harps:BAAANQAECgQIBQAAAA==.Harvyr:BAAANQAECgYICAABNQAECgcJEwABAAAAAA==.Hate:BAAANQAECgYICwAAAA==.Hathaw:BAAANQAECgEIAgAAAA==.Hayhay:BAAANQADCggIFwAAAA==.',
He='Helghast:BAAANQAECgQIBAAAAA==.Herja:BAAANQAECgQIBQAAAA==.Hey:BAAANQADCgYIBgAAAA==.',
Hi='Hidebound:BAABNQAECoEVAAINAAgKow8ECQDsAQANAAgKow8ECQDsAQAAAA==.Hisouka:BAABNQAECoEaAAIgAAcKJguN6QCQAQAgAAcKJguN6QCQAQABNQAECgkJMgAMAFAkAA==.',
Ho='Hobgoblinn:BAACNQAFFIEPAAIYAAUK6BQDCQCtAQAYAAUK6BQDCQCtAQA1AAQKgSwAAhgACQrrHa0cAAUDABgACQrrHa0cAAUDAAAA.Hodordog:BAAANQAECgYIDgAAAA==.Holybel:BAAANQADCgQIBAAAAA==.Holydiver:BAAANQADCgUIBQABNQAECgkJGwAFALQaAA==.Holydragon:BAAANQADCgYIBgAAAA==.Honeydutchtv:BAACNQAFFIENAAIEAAYKTx90AgBCAgAEAAYKTx90AgBCAgA1AAQKgSMAAgQACQoXI64sAPgCAAQACQoXI64sAPgCAAAA.Hopezbanyruu:BAAANQAECgYICAABNQAECgcIEQABAAAAAA==.Hopezblinky:BAAANQAECgcIEQAAAA==.Hopezherbz:BAAANQAECgYICQABNQAECgcIEQABAAAAAA==.Hordecore:BAAANQADCgYIEQAAAA==.Horsebananas:BAAANQADCgcIBgABNQAECgYIDwABAAAAAA==.',
Hu='Hubbo:BAAANQAECgYIBgAAAA==.Hugedonut:BAABNQAECoEiAAMJAAgKxhi4KwAZAgAJAAgKxhi4KwAZAgAjAAMKMAfbUQCMAAAAAA==.Hutchand:BAAANQADCgUIBQABNQAECggIJQAUAM0aAA==.',
Hy='Hypojin:BAABNQAECoEfAAIFAAgKpxM4OQD8AQAFAAgKpxM4OQD8AQAAAA==.',
Ic='Iceaged:BAABNQAECoEiAAMTAAcKTyTDBACvAgATAAcKrCLDBACvAgAgAAYKliN/kQBBAgAAAA==.Iceyhot:BAAANQADCgQIBAAAAA==.',
Il='Illos:BAABNQAECoEcAAINAAgKahyHBACsAgANAAgKahyHBACsAgAAAA==.',
Im='Imheated:BAAANQAECggIDAAAAA==.',
In='Integra:BAAANQAECgYIEgAAAA==.Intentions:BAAANQAECgEIAQAAAA==.',
It='Itadori:BAAANQAECgcIEAAAAA==.Itashi:BAAANQADCgEIAQAAAA==.Itheron:BAAANQADCgUIBQAAAA==.',
Ja='Jacknsally:BAAANQAECgIIAgAAAA==.Javijin:BAAANQABCgEJAQAAAA==.',
Jb='Jbandzz:BAAANQADCgYICAAAAA==.Jbruner:BAAANQAECgQIBQAAAA==.',
Je='Jessbae:BAABNQAECoEeAAIWAAgKuho+DwBlAgAWAAgKuho+DwBlAgAAAA==.Jessibelle:BAAANQAECgUICgAAAA==.Jez:BAAANQADCgYIGwAAAA==.Jezeel:BAAANQAECggIDwAAAA==.',
Ji='Jimmypage:BAABNQAECoEoAAQQAAkKMCPqAQCUAwAQAAkKwyLqAQCUAwAlAAUKsA2HLwDWAAAFAAEKtA2RoQAyAAAAAA==.',
Jo='Jonesstorm:BAAANQADCgMIAwAAAA==.',
Ju='Juicedmoose:BAABNQAECoEeAAQLAAgKsxv6KAAdAgALAAgKAxf6KAAdAgAKAAQKZCCAVwBzAQADAAMK5xOdmwCiAAAAAA==.Junundu:BAAANQAECggIBAAAAA==.',
Jv='Jvmec:BAAANQAECgYIDQAAAA==.',
Ka='Kaelissa:BAAANQADCgQIBAAAAA==.Kaelisse:BAAANQADCgQIBAAAAA==.Kaelstrada:BAABNQAECoEeAAIKAAcKDxo1NAAdAgAKAAcKDxo1NAAdAgAAAA==.Kaendndeydra:BAAANQADCgQIBgAAAA==.Kaennä:BAAANQAECgQJBgAAAA==.Kailash:BAAANQAECgMIAwAAAA==.Kaldorlon:BAAANQADCgcJCAAAAA==.Kaldresden:BAAANQADCgUIBQAAAA==.Kalladin:BAAANQAECgUIBgABNQAECgYIAgABAAAAAA==.Kallivan:BAAANQAECgQICAABNQAECgkJIgAEAOIiAA==.Kandakai:BAAANQADCgIIAgAAAA==.Karmageddon:BAAANQADCgcIBwAAAA==.Karmasuture:BAAANQAECgMIAwAAAA==.Karmasuturè:BAAANQAECggIDwAAAA==.Karmasuturé:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Kasha:BAAANQAECgIIAgAAAA==.Kattah:BAAANQAECgYIEQAAAA==.Kavikk:BAABNQAECoEYAAMMAAYKGh8ZawAQAgAMAAUKGCUZawAQAgAVAAEKJAFMjQATAAAAAA==.',
Ke='Keestermon:BAAANQADCgQIBAAAAA==.Kenbo:BAAANQADCgQIBAABNQAECggIHAANAGocAA==.Keymaster:BAAANQAECgQIDAAAAA==.',
Kh='Kharmod:BAAANQAECgIIBAABNQADCgQIBAABAAAAAA==.',
Ki='Kindrella:BAAANQAECgcIEQAAAA==.Kirbe:BAAANQAECgYIEQAAAA==.',
Kn='Knoctürnal:BAABNQAECoEnAAMLAAkKJCFTDwD5AgALAAkKJCFTDwD5AgADAAIKxgLVwgBDAAAAAA==.',
Ko='Kootiekween:BAAANQADCgcICwAAAA==.Kopaka:BAAANQADCgUIBQAAAA==.Kotetsu:BAABNQAECoEjAAMJAAkK/xm+EwDhAgAJAAkK/xm+EwDhAgAjAAEK6AJoZgAmAAAAAA==.Koufax:BAAANQAECgcIAwAAAA==.Kozzmo:BAAANQADCgUICAAAAA==.Kozzy:BAABNQAECoEYAAIJAAgKaBc1LgAGAgAJAAgKaBc1LgAGAgAAAA==.',
Kr='Krellian:BAAANQAECgIIAgAAAA==.',
Ky='Kylene:BAAANQADCgMIAwAAAA==.Kylisse:BAAANQADCgcIFQAAAA==.Kyma:BAAANQAECggIEAAAAA==.',
['Kä']='Känakä:BAAANQADCgcIDgABNQAECggIJQAUAM0aAA==.',
La='Labrys:BAAANQAECgUICgAAAA==.Laolin:BAAANQADCgYIBgAAAA==.Lasagna:BAABNQAECoEYAAIlAAgKsAR8KQAEAQAlAAgKsAR8KQAEAQAAAA==.Lastina:BAAANQAECgUICwAAAA==.Laufeyenjoy:BAAANQAECgYIAQAAAA==.Laysia:BAABNQAECoEcAAMWAAYKASKeEABLAgAWAAYKASKeEABLAgAXAAUKvRBzOAAYAQABNQAECgkJIgAEAOIiAA==.Lazypos:BAAANQAECgcIDAAAAA==.',
Le='Leecy:BAABNQAECoEvAAImAAgKPRTWCQAOAgAmAAgKPRTWCQAOAgAAAA==.Leget:BAAANQADCggICgAAAA==.Lelianne:BAAANQADCgUIBQAAAA==.Lewa:BAAANQAECgYIDAAAAA==.',
Li='Lillithen:BAAANQAFFAEIAQAAAA==.Limpytof:BAAANQADCgEIAQAAAA==.Linzalina:BAABNQAECoEUAAMiAAYKJhmVIwCXAQAiAAYKihiVIwCXAQAEAAMKwBICIwGrAAAAAA==.Litehand:BAAANQAECgUIBwAAAA==.Lixandrya:BAAANQAECgIIAgAAAA==.Lizbeth:BAAANQADCgQIBAAAAA==.',
Ll='Lliana:BAAANQABCgIIBAAAAA==.',
Lo='Lockrian:BAABNQAECoEmAAMHAAkKFyUwIgDkAgAHAAcK5SQwIgDkAgAIAAIKxiXWNgDbAAAAAA==.Locktober:BAAANQADCgYIBQAAAA==.Locose:BAACNQAFFIEUAAIFAAYKGxtMBQAaAgAFAAYKGxtMBQAaAgA1AAQKgSEAAgUACQqtI0YVAAcDAAUACQqtI0YVAAcDAAAA.Lolrush:BAACNQAFFIEVAAInAAYKAQadAQA9AQAnAAYKAQadAQA9AQA1AAQKgSEAAycACQqVDFwOAKMBACcACQqVDFwOAKMBAAkAAwrZCF5rAJUAAAAA.Longstrongg:BAAANQADCgUIBgAAAA==.Lostdragon:BAAANQAECgUICAAAAA==.Lovesoaked:BAAANQAECgEIAQAAAA==.Lovetea:BAABNQAECoElAAIWAAkKXSPHAgB8AwAWAAkKXSPHAgB8AwAAAA==.Loxier:BAABNQAECoEcAAQRAAgKLRF1XgDVAQARAAgKLRF1XgDVAQAZAAMKLghjGQCGAAAhAAIKUwMzZQBFAAAAAA==.',
Lu='Lugosh:BAAANQADCgQICgAAAA==.Lumendevout:BAAANQADCgUIBQAAAA==.Lumenshift:BAABNQAECoEeAAQGAAcKPB9VFgBsAgAGAAcKPB9VFgBsAgAFAAYKEBntQQDDAQAQAAEKthTkMQBFAAAAAA==.Lunaumbra:BAAANQADCgcIBwAAAA==.',
Ly='Lyall:BAABNQAECoEfAAIFAAgKRA4WQADPAQAFAAgKRA4WQADPAQAAAA==.Lyrnn:BAABNQAECoEcAAMaAAgK4hg+EABnAgAaAAgK4hg+EABnAgAOAAMKmQ3QbgCiAAAAAA==.',
['Lé']='Léx:BAAANQAECggIDAAAAA==.',
Ma='Maddman:BAAANQADCgIIAgAAAA==.Madheallz:BAAANQAECgMIBAAAAA==.Magecook:BAAANQAECgQIBgABNQAECgYIEwABAAAAAA==.Mainmoon:BAABNQAECoEfAAIXAAgKLhnyHAAkAgAXAAgKLhnyHAAkAgAAAA==.Majinmuu:BAABNQAECoEeAAMFAAgKuhgVLABWAgAFAAgKuhgVLABWAgAQAAMKagcdKwB1AAAAAA==.Malchor:BAABNQAECoEWAAIDAAgKkRTzTAC4AQADAAgKkRTzTAC4AQAAAA==.Manyas:BAAANQADCgUIDAAAAA==.Maolin:BAAANQADCggIEwAAAA==.Massimo:BAAANQAECgQIBgAAAA==.Matilda:BAAANQADCgQIBAAAAA==.Maximoo:BAAANQAECggIAQAAAA==.Mañgos:BAAANQAECgEIAQAAAA==.',
Me='Meagle:BAAANQADCgUIBQAAAA==.Megabonk:BAAANQAECgQICQAAAA==.Megthepriest:BAABNQAECoEYAAMRAAcKZRw7RgAuAgARAAYKBSA7RgAuAgAhAAQKHQ0KSQDOAAAAAA==.Menge:BAAANQADCgcIEQAAAA==.Menotorp:BAAANQADCgIIAgAAAA==.Mercifer:BAAANQADCgYIDAAAAA==.Mescareyarch:BAAANQAECggIDwAAAA==.',
Mi='Micha:BAAANQAFFAIIAgABNQAFFAMIBgAgALYKAA==.Mightduy:BAABNQAECoEbAAIXAAgKDB7yFACIAgAXAAgKDB7yFACIAgAAAA==.Misdirect:BAAANQAECgcIDAAAAA==.',
Mo='Moistbimbo:BAAANQABCgYIBgAAAA==.Monkheals:BAAANQAECgEIAQAAAA==.Montoia:BAAANQADCgMIAwAAAA==.Mooina:BAAANQAECgIIAgABNQAECgcIGgAkAFMVAA==.Moontzu:BAAANQADCgcIKgAAAA==.Morik:BAAANQAECgYIEAABNQAECgcIEgABAAAAAA==.Morph:BAABNQAECoEZAAMQAAcKuxjdDQADAgAQAAcKehfdDQADAgAlAAQKPRULLADwAAAAAA==.Mosha:BAAANQAECgUICwAAAA==.',
Mu='Mufasaclawsw:BAAANQAECgQIBAAAAA==.Muraina:BAAANQAECgQIBgAAAA==.Muscles:BAABNQAECoEXAAIVAAcK1RRpLADEAQAVAAcK1RRpLADEAQAAAA==.Muspel:BAAANQAECgYICQAAAA==.',
My='Mylittlepwny:BAAANQADCgYIBwAAAA==.Myrciless:BAAANQADCggICAAAAA==.',
['Mò']='Mòon:BAABNQAECoEqAAMWAAkKWB1CCQDcAgAWAAkKWB1CCQDcAgAXAAEKaQjEZgAkAAAAAA==.',
Na='Narcu:BAAANQADCgUJBQAAAA==.Narios:BAAANQAECgEIAgAAAA==.Nate:BAACNQAFFIEPAAMTAAUKihiWAACdAQATAAUKihiWAACdAQAgAAUK4glKIABCAQA1AAQKgSoAAyAACQpiH507AAIDACAACQpXHp07AAIDABMAAwrsIZIWACMBAAAA.',
Ne='Nephthys:BAABNQAECoEwAAMVAAkK4CLZBAB9AwAVAAkK4CLZBAB9AwAUAAEKuAqxEQAxAAAAAA==.Nerubus:BAABNQAECoEZAAIgAAgK/xwhfABuAgAgAAgK/xwhfABuAgAAAA==.Neso:BAAANQAECgUIEQAAAA==.Nexkaa:BAACNQAFFIERAAIgAAYKjiC2BQBAAgAgAAYKjiC2BQBAAgA1AAQKgTAAAiAACQqsJBUKAKsDACAACQqsJBUKAKsDAAAA.',
Ni='Niissia:BAAANQADCggJCAAAAA==.Nimbus:BAACNQAFFIEIAAIYAAQKhxNUDQBaAQAYAAQKhxNUDQBaAQA1AAQKgSAAAhgACQogIwQLAIMDABgACQogIwQLAIMDAAE1AAUUBwgQABgA4xcA.Nimi:BAEBNQAECoEgAAIkAAgK/Qx8GAB5AQAkAAgK/Qx8GAB5AQAAAA==.Nindara:BAABNQAECoEbAAIdAAcKSxX2FADdAQAdAAcKSxX2FADdAQAAAA==.',
No='Nokonda:BAAANQADCgMIAwAAAA==.Nonhealer:BAABNQAECoEZAAIbAAgKNRQxUwDtAQAbAAgKNRQxUwDtAQAAAA==.Norisse:BAAANQADCgYIDwAAAA==.Novå:BAAANQAECgQIBgAAAA==.',
Ob='Oballi:BAAANQADCggICAAAAA==.',
Og='Ogopogo:BAAANQADCgUIBQAAAA==.',
Ol='Olcadan:BAAANQADCgYICQAAAA==.Oliandia:BAAANQADCgcIDQABNQAECgcIGAARAGUcAA==.',
On='Onlydans:BAABNQAECoEgAAIJAAgKDgtgOwCmAQAJAAgKDgtgOwCmAQAAAA==.Onlysins:BAAANQAECgQIBQAAAA==.Onlyslams:BAAANQAECgQIBQABNQAECgQICQABAAAAAA==.',
Oo='Oofish:BAAANQADCgEIAQAAAA==.',
Or='Orcslug:BAAANQADCgQIAgAAAA==.Ordani:BAAANQADCgEIAQABNQAECgkJIgAEAOIiAA==.Orm:BAABNQAECoEgAAIGAAgKohEdJADWAQAGAAgKohEdJADWAQAAAA==.',
Ou='Ouilyjambon:BAAANQAECgIIAwAAAA==.',
Ov='Overlooker:BAAANQAECgUIBQAAAA==.Overlordzor:BAAANQADCgQIBQAAAA==.',
Pa='Palanth:BAAANQAECgMIAwAAAA==.Pannfried:BAAANQADCgEIAQAAAA==.Panorama:BAABNQAECoEbAAMWAAcKKQuuIgBDAQAWAAcKKQuuIgBDAQAXAAEKlgcKZAApAAAAAA==.Pastor:BAAANQAECgIIAQABNQAFFAMIBgAgALYKAA==.Patrik:BAABNQAECoEaAAIjAAcKmiPaEQDJAgAjAAcKmiPaEQDJAgAAAA==.',
Pe='Pearlzinha:BAAANQAECgMICAAAAA==.Peonanoob:BAAANQADCgYIBgAAAA==.',
Ph='Phrost:BAAANQABCgMIAwAAAA==.Phuga:BAAANQAECgcIEwAAAA==.',
Po='Poets:BAABNQAECoEXAAIEAAkKLR0aMADqAgAEAAkKLR0aMADqAgAAAA==.Pollysocket:BAAANQAECgUICQABNQAECgkJKAAQADAjAA==.Ponix:BAAANQAECgQIBAAAAA==.Pookenstein:BAAANQADCgMIAwABNQAECggIHgAWALoaAA==.',
Pr='Preservasian:BAAANQADCgcIDQAAAA==.Prettyfrosty:BAAANQAECgUIEAAAAA==.',
Ps='Psykolight:BAAANQADCgMIAwAAAA==.',
Pu='Puffsummons:BAABNQAECoEeAAMHAAgKchE+eQDNAQAHAAcKSxE+eQDNAQAIAAIK0xGeUwB5AAAAAA==.Purify:BAABNQAECoEeAAIRAAgKzg1iZwC0AQARAAgKzg1iZwC0AQAAAA==.Puxxyslayer:BAAANQAECgYICAAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Py='Pyrannor:BAAANQAECgUICgAAAA==.Pyx:BAAANQADCggICAAAAA==.',
Qu='Quinifer:BAABNQAECoEqAAIDAAkKHR5AIgCdAgADAAkKHR5AIgCdAgAAAA==.Quintera:BAAANQAECgMIAwAAAA==.',
Ra='Raau:BAAANQADCgcIDQABNQAECgkJJQAFABQNAA==.Radamantys:BAABNQAECoEyAAIMAAkKUCQ6AwDJAwAMAAkKUCQ6AwDJAwAAAA==.Ragnaroc:BAAANQADCgQIBQAAAA==.Randysavagge:BAAANQAECgcIDAABNQAECggILAAMACAdAA==.Ravensword:BAAANQAECgEIAQAAAA==.Razdurin:BAAANQAECgQICAAAAA==.Razenseth:BAABNQAECoErAAIeAAkKHx1eCwDfAgAeAAkKHx1eCwDfAgAAAA==.',
Re='Regenerate:BAABNQAECoEZAAIbAAkKrQ3pVQDiAQAbAAkKrQ3pVQDiAQAAAA==.Relanne:BAAANQAECgYICwAAAA==.Restorasian:BAAANQAECgYIEAAAAA==.Retnewb:BAABNQAECoEbAAIiAAcKYx/EEQBeAgAiAAcKYx/EEQBeAgAAAA==.Retpetition:BAAANQADCgIIAgAAAA==.Revecca:BAAANQADCgQIBAAAAA==.',
Rh='Rhaskos:BAAANQADCgEIAQABNQAECgYIGAAMABofAA==.Rhiannah:BAAANQADCgEIAQAAAA==.',
Ri='Rikez:BAAANQAECgQJBwAAAA==.',
Ro='Robeartoe:BAAANQAECgMIAwAAAA==.Roidrage:BAAANQADCgIIAgAAAA==.Rokrin:BAABNQAECoEYAAMDAAkKmByiKAB2AgADAAkKmByiKAB2AgAKAAEKSAdjyAAkAAAAAA==.Roleplay:BAAANQAECgYIEgAAAA==.Rorindar:BAAANQAECgIIAgAAAA==.Rose:BAABNQAECoEbAAIMAAcK5hzwUQBSAgAMAAcK5hzwUQBSAgAAAA==.Rowsdower:BAABNQAECoEeAAImAAgKLhJoCgAAAgAmAAgKLhJoCgAAAgAAAA==.',
Ru='Rubez:BAABNQAECoEgAAIgAAgKAQ26uADvAQAgAAgKAQ26uADvAQAAAA==.Rucca:BAAANQAECgQICAAAAA==.Rulia:BAAANQADCggICwAAAA==.',
['Rí']='Rínzler:BAAANQAECgcIDAABNQAECggIEQABAAAAAA==.',
Sa='Saerah:BAAANQAECgQIBQAAAA==.Sandya:BAAANQAECgUIBQAAAA==.Sans:BAABNQAECoEqAAMYAAkKQBNHRQA1AgAYAAkKQBNHRQA1AgAbAAkKHBXgQgAqAgAAAA==.Saphea:BAABNQAECoEpAAISAAgK0R+RHQDmAgASAAgK0R+RHQDmAgAAAA==.Sarlalia:BAAANQADCggICAABNQAECggIEQABAAAAAA==.Sarutobi:BAAANQAECgUIBgABNQAECgkJIwAJAP8ZAA==.Sathrenus:BAAANQADCgYIDgAAAA==.',
Sc='Scarletraven:BAAANQAECgYIEQAAAA==.',
Se='Seifer:BAAANQAECggIEQAAAA==.Selistras:BAAANQAECgQICQAAAA==.Selri:BAAANQADCgQICAAAAA==.',
Sh='Shadowwarrio:BAAANQAECgQIBwAAAA==.Shadø:BAAANQADCgQIBwAAAA==.Shammÿ:BAACNQAFFIEFAAIYAAMKhAQUGADPAAAYAAMKhAQUGADPAAA1AAQKgS0AAhgACQq4HscYAB0DABgACQq4HscYAB0DAAAA.Shedim:BAAANQAECgUIBQAAAA==.Shiftinman:BAAANQADCgYIBgAAAA==.Shocktea:BAAANQAECgEIAQAAAA==.Shovelhead:BAAANQADCgUICQAAAA==.Shunt:BAAANQAECgQIBAAAAA==.Shuraina:BAAANQAECgQIBwAAAA==.Shylachase:BAAANQAECgUIDgAAAA==.Shyllamae:BAAANQADCggIFgAAAA==.',
Si='Sinisteria:BAAANQADCgUJBQABNQAECgkJJwALACQhAA==.Sinisterion:BAAANQAECgcIDgABNQAECgkJJwALACQhAA==.',
Sk='Skybreaker:BAAANQAECgUICgABNQAECgYIDgABAAAAAA==.Skylane:BAAANQAECgYIEQAAAA==.',
Sm='Smokestrider:BAAANQADCgUIBQAAAA==.',
Sn='Snacck:BAAANQAECgIIAgAAAA==.Snanth:BAABNQAECoEkAAMgAAkKDB8KWwC3AgAgAAgKqR4KWwC3AgATAAMKwhR+IADEAAAAAA==.Sniperq:BAAANQAECgMIBgAAAA==.Snowcreeks:BAAANQAECgYIEQAAAA==.Snurbin:BAAANQADCgEJAQAAAA==.Snuudle:BAABNQAECoEcAAMHAAkKOhgnQQByAgAHAAkKOhgnQQByAgAIAAEK4gmDdQAyAAAAAA==.',
So='Sonniy:BAAANQADCgYIAgAAAA==.',
Sp='Spalling:BAAANQAECgUICgAAAA==.Spauunn:BAAANQAECgIIAgAAAA==.Spelleria:BAAANQADCgUIBQAAAA==.Spleenless:BAAANQADCgcIBwABNQAECggIAQABAAAAAA==.Spoon:BAEBNQAECoEqAAIgAAgKViHZPQD8AgAgAAgKViHZPQD8AgAAAA==.',
St='Starcommand:BAAANQAECgMJAwAAAA==.Steelhide:BAAANQAECgYIEQAAAA==.Stoopedholy:BAAANQAECgYIEwABNQAFFAcIEAACAKIHAA==.Stubborn:BAABNQAECoEbAAMFAAkKtBpNMQAyAgAFAAgKShlNMQAyAgAGAAIK5wSvYABJAAAAAA==.Stubborndk:BAAANQAECgMIAwABNQAECgkJGwAFALQaAA==.',
Su='Sumata:BAAANQAECgcICQABNQAECgcIGgAkAFMVAA==.Sumato:BAABNQAECoEaAAMkAAcKUxVlFgCWAQAkAAcKkRNlFgCWAQAPAAQKRg/TAAGpAAAAAA==.',
Sy='Syllata:BAABNQAECoEqAAIGAAkKYCI+BgBMAwAGAAkKYCI+BgBMAwAAAA==.Sylvianna:BAABNQAECoEeAAIVAAkKjBHeHgA8AgAVAAkKjBHeHgA8AgAAAA==.',
['Sî']='Sîd:BAAANQAECgcIBwAAAA==.',
['Sï']='Sïd:BAAANQAECgYIBgAAAA==.',
Ta='Tadra:BAAANQADCgYICgABNQAECgkJKgAWAFgdAA==.Taladen:BAAANQADCggICQAAAA==.Talahon:BAAANQADCggICAABNQAECgUIBwABAAAAAA==.Tayswiftie:BAAANQADCggIAgAAAA==.',
Te='Tenebrion:BAAANQADCgcIBwAAAA==.Tenneland:BAAANQADCgUIBQAAAA==.Teppic:BAABNQAECoEZAAIaAAgKYQ0xGwDqAQAaAAgKYQ0xGwDqAQAAAA==.Terawar:BAABNQAECoEeAAMPAAgKSyUHGQBJAwAPAAgKHCUHGQBJAwAmAAEK1yYxIwBwAAAAAA==.Terrorîst:BAAANQABCggIDgABNQAECgUIDwABAAAAAA==.Tetadesanti:BAABNQAECoEXAAIKAAcKmg/0VgB1AQAKAAcKmg/0VgB1AQAAAA==.',
Th='Thaljadrak:BAAANQAECgQIBwAAAA==.Thebadthing:BAAANQAECgIIAgABNQAECgkJIQAbAEAfAA==.Thenazalth:BAAANQAECgEIAQAAAA==.Therealmundy:BAAANQADCgUJBQAAAA==.Therla:BAAANQAECgIIBAABNQAECgUIBwABAAAAAA==.Thuggish:BAAANQADCgYIBgAAAA==.Thunderbum:BAAANQAECgEIAQAAAA==.Thundron:BAABNQAECoEiAAIEAAkK4iLfFwBSAwAEAAkK4iLfFwBSAwAAAA==.',
Ti='Tiandrel:BAAANQADCgMIBAAAAA==.Tiny:BAABNQAECoEYAAISAAgKqhzRLACYAgASAAgKqhzRLACYAgAAAA==.Tinydingo:BAAANQAECgUIDgAAAA==.Tinysham:BAAANQADCggJEAAAAA==.Tiraflecha:BAAANQADCgYIBgAAAA==.Titamao:BAAANQADCgUICAAAAA==.Tizzt:BAAANQABCgQICAABNQAECgUICQABAAAAAA==.',
To='Tokun:BAAANQAECgUICAABNQAECgkJMgAMAFAkAA==.Tooktalligo:BAAANQADCgEIAQAAAA==.Toper:BAAANQADCgQIBAAAAA==.Torrak:BAAANQADCgMIAwAAAA==.Totenschein:BAAANQAECgQIDAABNQADCgYIBgABAAAAAA==.',
Tr='Travisaur:BAAANQADCgcICgABNQAECgkJIQAbAEAfAA==.Trixibell:BAAANQAECgcIDwAAAA==.Trouble:BAAANQAECgQIBAABNQAECgkJMAAVAOAiAA==.',
Ty='Tylethian:BAAANQAECgMIBQAAAA==.',
Un='Uninterested:BAAANQAECgYIEQAAAA==.',
Ur='Urudeathcow:BAAANQAECgEIAgAAAA==.Urupally:BAAANQADCgEIAQAAAA==.Urver:BAAANQAECgcJEwAAAA==.',
Us='Username:BAAANQAECgIIBwAAAA==.',
Va='Vaelendrii:BAAANQAECgQIBQAAAA==.Valhallo:BAAANQAECgcIBwABNQAFFAQIBgAbAPsWAA==.Valistrasza:BAAANQAECgIIAwABNQAECgcIHgAMAO0TAA==.Valpina:BAAANQAECgYICQAAAA==.',
Ve='Veeronica:BAAANQAECgEIAQAAAA==.Velthari:BAAANQADCgcICQAAAA==.Venomlock:BAAANQADCgYJEAAAAA==.Verst:BAAANQADCgcJBwAAAA==.',
Vh='Vhx:BAAANQAECgYIEQAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Vixelle:BAAANQAECgEIAgAAAA==.',
Vl='Vladdracule:BAAANQADCgcIBwAAAA==.Vladski:BAAANQAECgYIEAAAAA==.',
Vm='Vmjecd:BAAANQAECgUICgAAAA==.Vmjecm:BAAANQAECgQIBAAAAA==.Vmjecw:BAAANQAECgcIDwAAAA==.',
Vo='Voidspauun:BAAANQAECgYIEwAAAA==.Vortsex:BAAANQAECgUIDQAAAA==.',
['Vï']='Vïxenô:BAACNQAFFIEGAAIbAAQK+xZCDQBMAQAbAAQK+xZCDQBMAQA1AAQKgSsAAhsACQpGIo0KAFgDABsACQpGIo0KAFgDAAAA.',
Wa='Warxiez:BAAANQADCgUIBQAAAA==.Washiki:BAAANQADCgcIBwAAAA==.',
Wh='Whirt:BAABNQAECoEfAAIgAAgKdgc/4wCcAQAgAAgKdgc/4wCcAQAAAA==.Whý:BAAANQADCgcIBwABNQAECgkJKgAWAFgdAA==.',
Wi='Widowmaker:BAABNQAECoEnAAQDAAkKGyETDQA7AwADAAkKGyETDQA7AwALAAUKnRaPVgADAQAKAAEKlAhOxgAmAAAAAA==.Wigglez:BAAANQADCgYIFgAAAA==.Williece:BAAANQABCgQICwAAAA==.Wishes:BAAANQAECgQJBwAAAA==.',
Wo='Wocalax:BAAANQAECgIIBQAAAA==.',
Xa='Xandine:BAAANQABCgIIBAAAAA==.Xavilic:BAABNQAECoEaAAIXAAcKSBoQHgAXAgAXAAcKSBoQHgAXAgAAAA==.',
Xe='Xenyen:BAAANQADCggIDQABNQAECgkJNgAcANoWAA==.',
Xm='Xmaxpower:BAAANQAECgUIDAAAAA==.',
Ya='Yacht:BAAANQAECgQICAAAAA==.',
Ye='Yeb:BAAANQADCgQJBAAAAA==.',
Yo='Yohei:BAAANQAECgUIBgAAAA==.Yonbon:BAAANQAECgEIAgAAAA==.',
Za='Zadrial:BAAANQAECgIIAwABNQAECgcIHgAKAA8aAA==.Zahlxr:BAABNQAECoEdAAMSAAcKGx9JNQBzAgASAAcKGx9JNQBzAgAEAAUKIRWJ0ABAAQAAAA==.Zanix:BAAANQADCgYIBgAAAA==.Zappyboy:BAABNQAECoEhAAIbAAkKQB+nFgABAwAbAAkKQB+nFgABAwAAAA==.Zapra:BAAANQADCgYIBgAAAA==.Zapraz:BAAANQAECgQICQABNQAECgYIGAAMABofAA==.',
Ze='Zeero:BAAANQAFFAEIAQAAAA==.Zenrah:BAAANQAECgUIDwABNQAFFAEIAQABAAAAAA==.Zeraphole:BAAANQADCggIDgAAAA==.Zergturts:BAABNQAECoEYAAIgAAcKuBCA0QC+AQAgAAcKuBCA0QC+AQAAAA==.Zerolith:BAAANQADCggJCAAAAA==.Zethryx:BAAANQAECgUJBQAAAA==.',
Zi='Zif:BAAANQAECgcIDAAAAA==.Zify:BAAANQAECgcIEQAAAA==.Zitalan:BAAANQADCggICAAAAA==.',
Zm='Zmamaz:BAABNQAECoEeAAIMAAgKghdEQgB/AgAMAAgKghdEQgB/AgAAAA==.',
Zo='Zoidbergmd:BAABNQAECoEyAAQCAAkKkhkBDQBjAQAHAAYKjxaBiACiAQACAAUKkhcBDQBjAQAIAAIKbQ6SWQBqAAAAAA==.Zomat:BAAANQAECgIIAwAAAA==.Zoob:BAAANQADCgYIBgABNQAECgUIBQABAAAAAA==.Zorbrix:BAABNQAECoEgAAInAAgKKhx9BgCGAgAnAAgKKhx9BgCGAgAAAA==.',
Zr='Zrre:BAAANQADCggICAAAAA==.',
Zu='Zulgeteb:BAAANQAECgYICQAAAA==.',
Zy='Zy:BAAANQAECgQICAABNQAFFAcIGAAjAG8eAA==.Zynner:BAABNQAECoEjAAIVAAkKuB9qEQDIAgAVAAkKuB9qEQDIAgABNQABCgQIAwABAAAAAA==.',
Zz='Zztank:BAABNQAECoEeAAIiAAgK+R/DCwC9AgAiAAgK+R/DCwC9AgAAAA==.',
['Zí']='Zí:BAAANQAECgUICQAAAA==.',
['Äi']='Äiøn:BAAANQADCgYIBwAAAA==.',
['Ça']='Çarnage:BAAANQADCgIIAgAAAA==.',
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
