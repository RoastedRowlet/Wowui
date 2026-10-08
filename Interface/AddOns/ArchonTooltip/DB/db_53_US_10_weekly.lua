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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Monk-Mistweaver','Hunter-BeastMastery','Paladin-Holy','Warlock-Demonology','Warrior-Fury','Priest-Holy','Mage-Arcane','Hunter-Marksmanship','Druid-Restoration','Monk-Windwalker','Paladin-Protection','Priest-Shadow','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Arms','Rogue-Assassination','Mage-Frost','Warlock-Destruction','Warlock-Affliction','Shaman-Restoration','Warrior-Protection','Druid-Feral','Druid-Guardian','Druid-Balance','Shaman-Enhancement','Hunter-Survival','Evoker-Devastation','Evoker-Augmentation','Rogue-Subtlety','Evoker-Preservation','Priest-Discipline','Monk-Brewmaster','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm="Aman'Thul",name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aanubus:BAAANQADCggJDQABNQAECggIBgABAAAAAA==.Aarek:BAAANQABCgYIBgABNQAECgYIBwABAAAAAA==.',
Ab='Abyssalmaw:BAABNQAECoEVAAICAAYK7gGUSQDTAAACAAYK7gGUSQDTAAAAAA==.',
Ac='Achillesqt:BAAANQADCgIIAgAAAA==.Acionna:BAAANQAECgQIBAAAAA==.',
Ad='Ada:BAAANQADCgIIAgAAAA==.Adekeahokeha:BAAANQADCgYIBQAAAA==.Adrenalin:BAABNQAECoEgAAIDAAkKwBJedAAWAgADAAkKwBJedAAWAgAAAA==.',
Ae='Aedros:BAAANQAECgcICwAAAA==.Aegis:BAAANQADCgIIAgAAAA==.Aellan:BAABNQAECoEbAAMEAAcK7yEdGgCTAgAEAAcK1SEdGgCTAgAFAAMKlCS8cwAhAQAAAA==.Aeorin:BAAANQADCgIIAgAAAA==.',
Af='Afflexion:BAAANQAECgYIDAAAAA==.Afterlyfe:BAAANQADCggIEAAAAA==.',
Ag='Agonier:BAAANQAECgEIAQAAAA==.',
Ai='Airyn:BAAANQADCgUIBQAAAA==.',
Aj='Ajira:BAAANQADCgcIDwAAAA==.',
Ak='Akiaki:BAAANQAECgIIAwAAAA==.',
Al='Aladk:BAABNQAECoEkAAMGAAkKJyIJCwBNAwAGAAkKJyIJCwBNAwAFAAEKUwIj4AAhAAAAAA==.Alaevo:BAAANQADCgQIBQABNQAECgkJJAAGACciAA==.Alafus:BAAANQAECggIEAABNQAECgkJJAAGACciAA==.Alaldras:BAAANQAECgEIAgAAAA==.Alalock:BAAANQAECggIDwABNQAECgkJJAAGACciAA==.Alaria:BAAANQAECgYIEwABNQAECgkJMAAHADEiAA==.Alarian:BAABNQAECoEnAAIIAAkKXSNKBwCXAwAIAAkKXSNKBwCXAwAAAA==.Aldai:BAAANQAECgIIAgAAAA==.Alendros:BAAANQAECgIIAgAAAA==.Alexsia:BAAANQADCgEIAQAAAA==.Aliiah:BAAANQADCggICgAAAA==.Alir:BAABNQAECoElAAIFAAkKIh6zIgCbAgAFAAkKIh6zIgCbAgAAAA==.Alista:BAAANQADCgIIAgAAAA==.Alle:BAAANQAECgIIAgAAAA==.Allen:BAAANQAECgUIBgAAAA==.Allyren:BAABNQAECoEhAAIJAAgKjRjMPQBPAgAJAAgKjRjMPQBPAgAAAA==.Allythriea:BAAANQAECgQICAAAAA==.',
Am='Ambertwo:BAAANQAECgYIDAAAAA==.Amelesteu:BAAANQAECgEIAQAAAA==.Amitheria:BAABNQAECoEVAAIJAAcKLBbKWQDpAQAJAAcKLBbKWQDpAQAAAA==.',
An='Andreb:BAAANQAECgYIEgAAAA==.Andromyda:BAAANQAECgQICAAAAA==.Angelofnite:BAAANQAECgMIBgAAAA==.Angelofpower:BAAANQADCgYIBwAAAA==.Angelzspirit:BAAANQABCgYICAAAAA==.Angrychicken:BAAANQAFFAEIAQAAAA==.Ankh:BAAANQAECgYIEwAAAA==.Anklebreakr:BAAANQADCgMIAwABNQAECggIFQAKAGofAA==.Antopanto:BAABNQAECoEcAAILAAgKrBOMCQAWAgALAAgKrBOMCQAWAgAAAA==.Anubiset:BAAANQADCgUIBQAAAA==.',
Ar='Aralia:BAAANQAECgIIAgAAAA==.Arasmina:BAABNQAECoElAAIJAAkKjiRwAwCzAwAJAAkKjiRwAwCzAwAAAA==.Arcanystra:BAAANQAECgIIBAAAAA==.Arcathal:BAABNQAECoEsAAIMAAkKCB7nFAATAwAMAAkKCB7nFAATAwAAAA==.Arcshottx:BAABNQAECoEYAAINAAgKOw6OvgDjAQANAAgKOw6OvgDjAQAAAA==.Arkio:BAAANQADCgcIBwAAAA==.Arliis:BAABNQAECoEgAAMJAAcKCSVFHgDiAgAJAAcKCSVFHgDiAgADAAEK+gegdQEzAAAAAA==.Arniy:BAAANQADCgYJDQABNQAECgkJMAAHADEiAA==.Artey:BAABNQAECoElAAIOAAkKNBykDwDcAgAOAAkKNBykDwDcAgAAAA==.Arthérmis:BAAANQADCgYIBgABNQAECggIKgAPAF4VAA==.',
As='Ascot:BAAANQADCgYJBwABNQAECggIHQAQALcQAA==.Asenathe:BAAANQADCggIAgAAAA==.Ashaad:BAABNQAECoEZAAIRAAcKXxXoIgCdAQARAAcKXxXoIgCdAQAAAA==.Asyluun:BAAANQAECgMIBQAAAA==.',
At='Atorvas:BAAANQADCgQIBAAAAA==.',
Au='Auchioane:BAABNQAECoEYAAISAAcKmAjJNQBOAQASAAcKmAjJNQBOAQAAAA==.Aurelyia:BAAANQAECgUIEAAAAA==.',
Aw='Awakenimg:BAAANQADCgEIAQAAAA==.',
Ay='Ayhai:BAAANQAECgQIBAAAAA==.',
Az='Azador:BAAANQAECgYIEQAAAA==.Azael:BAAANQAECgQIBAAAAA==.Azarion:BAAANQADCgEIAQAAAA==.Azayzel:BAAANQAECgIIAgAAAA==.Azemm:BAAANQAECgYIBgABNQAECgQIBgABAAAAAA==.Azza:BAAANQADCgcIDAAAAA==.',
['Aé']='Aérfen:BAAANQAECgEIAQAAAA==.',
Ba='Backburner:BAAANQADCgMIAwAAAA==.Badvoodoo:BAABNQAECoEhAAIGAAcKCxnsPQDpAQAGAAcKCxnsPQDpAQAAAA==.Balahara:BAAANQADCgYIBgAAAA==.Balfor:BAABNQAECoEUAAITAAUKFiNNXgDXAQATAAUKFiNNXgDXAQAAAA==.Bandarpallie:BAAANQAECgQICAAAAA==.Bara:BAAANQABCgMIAwAAAA==.Battlepope:BAAANQADCgIIBAAAAA==.Baynage:BAAANQAECgYIBgAAAA==.',
Be='Beastah:BAAANQADCgUJCAAAAA==.Beauxmax:BAAANQADCgYIBgAAAA==.Beefkakes:BAAANQADCggIGAAAAA==.Belest:BAABNQAECoEdAAIDAAcKvw24sACFAQADAAcKvw24sACFAQAAAA==.Belfhee:BAAANQADCgEIAQAAAA==.Belkelmor:BAAANQAECgQICAAAAA==.Bellaros:BAAANQAECgQIBgAAAA==.Belyana:BAAANQADCgIIAgAAAA==.Belè:BAABNQAECoEtAAMUAAgK5BqEIgBgAgAUAAgK5BqEIgBgAgAVAAIKVBJZIwBuAAAAAA==.Beorm:BAAANQADCgYICgAAAA==.Bermagi:BAAANQAECgQIEAAAAA==.',
Bi='Biders:BAAANQADCgEIAQAAAA==.Bigarchrules:BAAANQAECgEIAQAAAA==.Bigbanana:BAAANQAECgUIDgAAAA==.Bigbouncer:BAAANQADCgUIBQAAAA==.Bigdaddy:BAABNQAECoEoAAIWAAkKSRwkLwDuAgAWAAkKSRwkLwDuAgAAAA==.Bigole:BAAANQAECgUIBQAAAA==.Bigrilla:BAAANQAECgMIAwAAAA==.Bigsecksi:BAAANQAECgMIAwAAAA==.Bilbearbagns:BAAANQAECgYIBwAAAA==.Billkills:BAAANQADCgIIAgAAAA==.Billpie:BAAANQAECgUICgAAAA==.Billyblobby:BAAANQAECgIIAgAAAA==.Billyrolls:BAAANQADCgEIAQAAAA==.Binkei:BAAANQAECggIDwAAAA==.Bitee:BAAANQAECgQIBQAAAA==.',
Bl='Blacklight:BAAANQAECgQICQAAAA==.Blacksky:BAAANQAECgQICAAAAA==.Blade:BAABNQAECoEgAAIXAAgK9hwCFwCeAgAXAAgK9hwCFwCeAgAAAA==.Blastette:BAAANQADCggIKAAAAA==.Blayze:BAABNQAECoEaAAIDAAcK/QaF0wA6AQADAAcK/QaF0wA6AQAAAA==.Bloodclaw:BAAANQABCgUIBwAAAA==.Bloodgimp:BAABNQAECoEbAAMEAAgK3RnvMQDeAQAEAAcK0hXvMQDeAQAFAAYK4xd5XQBzAQAAAA==.Bloodlust:BAAANQAECgcIDQAAAA==.Bloodslay:BAABNQAECoElAAIWAAgKeBspTgCFAgAWAAgKeBspTgCFAgAAAA==.Bloodtank:BAAANQADCgYIBgAAAA==.Blossomstars:BAAANQADCgEIAgAAAA==.Bluebrood:BAAANQAECgUICgAAAA==.',
Bo='Boenarrow:BAAANQAECgQIBwAAAA==.Bojack:BAAANQAECgYIDAAAAA==.Bombshot:BAAANQAECgQICgAAAA==.Boomdeeznutz:BAAANQADCgUICwAAAA==.Boomkinbill:BAAANQADCgEIAQAAAA==.Boproblem:BAAANQADCgUIBQAAAA==.Botmage:BAABNQAECoEYAAMNAAgKiR/+WQC6AgANAAgKRx/+WQC6AgAYAAEK+RozNwBIAAAAAA==.Bovinei:BAAANQAECgQICgAAAA==.',
Br='Brackk:BAAANQADCggIHAAAAA==.Braedaevia:BAABNQAECoEfAAQZAAgKXBFkEADuAQAZAAgKxxBkEADuAQAKAAUKqgU75wDNAAAaAAMKCgroGACfAAAAAA==.Brahnson:BAAANQADCgQICAAAAA==.Brawlzdeep:BAAANQADCgQIBAAAAA==.Breldyr:BAAANQAECggIEQAAAA==.Brettskiog:BAAANQAECgcIBwAAAA==.Bronnir:BAAANQADCgYICAAAAA==.Brotis:BAAANQAECgQIBwAAAA==.Brylen:BAACNQAFFIEaAAITAAgKxSKSAADmAgATAAgKxSKSAADmAgA1AAQKgRsAAhMACQprJmwEAMEDABMACQprJmwEAMEDAAAA.',
Bu='Bubbleblonde:BAAANQAECgMIAwABNQAECggIMwAKALEWAA==.Bubblebtch:BAAANQAECgQIBwAAAA==.Bubblerat:BAAANQAECgMIAwAAAA==.Bullus:BAAANQAECgMIBAAAAA==.Buntz:BAABNQAECoElAAIWAAkKRiQQEQByAwAWAAkKRiQQEQByAwAAAA==.',
Ca='Caain:BAAANQAECgUIBwAAAA==.Caalypso:BAABNQAECoEsAAIbAAgKSh8zKwCTAgAbAAgKSh8zKwCTAgAAAA==.Caileron:BAAANQAECgQICAAAAA==.Cakesnpies:BAABNQAECoEjAAMIAAgKRBZzUwBOAgAIAAgKRBZzUwBOAgAOAAMKrwWTYQB6AAAAAA==.Callamedic:BAAANQADCggIBwABNQAECggIBgABAAAAAA==.Callofdeath:BAAANQAECgIIAwAAAA==.Cancelyn:BAAANQADCgYIBwAAAA==.Cantplaymage:BAAANQABCgQIBAAAAA==.Capsmasher:BAAANQADCgYIBgAAAA==.Carb:BAAANQAECgYIDwAAAA==.Cashehm:BAAANQAECgUICgAAAA==.Caströ:BAABNQAECoEkAAMHAAgKYxNqFgDmAQAHAAgKYxNqFgDmAQAQAAEKhRXmWwA9AAAAAA==.',
Cc='Cclla:BAAANQAECggIEAABNQADCggICAABAAAAAA==.Ccllaa:BAAANQADCggICAAAAA==.',
Ce='Cecilbgnome:BAAANQADCgYIAgAAAA==.Celad:BAABNQAECoEkAAIGAAgK/h/UFgDgAgAGAAgK/h/UFgDgAgAAAA==.Cenedra:BAABNQAECoEfAAIOAAgKixx/GQByAgAOAAgKixx/GQByAgAAAA==.',
Ch='Chaihard:BAAANQADCgUIBQAAAA==.Cheesenonion:BAAANQADCgYICwABNQAECggIJQAXALQZAA==.Chocolates:BAAANQADCgIIAgAAAA==.Chromitez:BAABNQAECoEkAAIFAAgKAya6CQBeAwAFAAgKAya6CQBeAwAAAA==.Chroren:BAAANQAECgcIDQAAAA==.Chubberz:BAAANQADCggICgABNQAECgkJJAAJAFUWAA==.Churlish:BAABNQAECoElAAIXAAkKPBNNHwBcAgAXAAkKPBNNHwBcAgAAAA==.',
Cl='Claptothetop:BAABNQAECoEUAAIWAAgKpxZbZABDAgAWAAgKpxZbZABDAgAAAA==.Clawyaeyeout:BAAANQADCgQIBAAAAA==.Cleavís:BAABNQAECoEhAAIcAAgK3CPCBQDxAgAcAAgK3CPCBQDxAgAAAA==.Clla:BAAANQAECgYICAABNQADCggICAABAAAAAA==.Cllaa:BAABNQAECoElAAMDAAkKtBzHOQDGAgADAAkKyhvHOQDGAgARAAMKJx3fOQDzAAABNQADCggICAABAAAAAA==.Cllu:BAAANQAECgcICwAAAA==.',
Co='Cogedor:BAAANQADCgEIAQAAAA==.Colourzz:BAAANQADCgYJBgAAAA==.Conflict:BAAANQAECgMIAwAAAA==.Coobs:BAAANQADCgYIBgAAAA==.Corepia:BAAANQAECgUIEgAAAA==.Cozymonday:BAABNQAECoEoAAMdAAgKhh0BCQCKAgAdAAgKVRsBCQCKAgAeAAUKFSGzFwCwAQAAAA==.',
Cr='Cramberly:BAABNQAECoEZAAMPAAcK2SKaEACzAgAPAAcK2SKaEACzAgAeAAEKdhtGRwBIAAAAAA==.Craystone:BAAANQADCgQIBAAAAA==.Crayzdruid:BAAANQADCgQIBAAAAA==.Crikeys:BAAANQADCgYIEAAAAA==.Crispynips:BAAANQADCggIFQAAAA==.Cristeria:BAEBNQAECoEaAAIMAAcKsCE0JwCwAgAMAAcKsCE0JwCwAgAAAA==.Crnreaper:BAAANQAECgQICgAAAA==.Crotch:BAAANQABCgIIAgAAAA==.',
Cu='Custodes:BAAANQADCgYJEQAAAA==.',
Cy='Cyradis:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.',
Da='Dabita:BAABNQAECoEiAAIIAAcK0RUgcQABAgAIAAcK0RUgcQABAgAAAA==.Daewong:BAABNQAECoEwAAMHAAkKMSJmAwBpAwAHAAkKMSJmAwBpAwAQAAEKuQMgYwAqAAAAAA==.Dagami:BAAANQAECgQIBAAAAA==.Daiganzan:BAAANQAECgMIAwAAAA==.Daisuke:BAAANQAECgMIBAAAAA==.Dajango:BAABNQAECoEhAAMIAAgKjCSWEABNAwAIAAgKjCSWEABNAwAOAAMKRwnlXACLAAAAAA==.Daknar:BAABNQAECoEgAAMKAAgKgSG3HQD4AgAKAAgKgSG3HQD4AgAZAAIK7h9lRQClAAAAAA==.Dalenvoidy:BAAANQAECgQICAAAAA==.Damâ:BAAANQADCgYIBgAAAA==.Dandal:BAAANQAECgYICAAAAA==.Dandrassil:BAAANQAECgIIAQAAAA==.Danukku:BAAANQADCggICAABNQAECgYIEwABAAAAAA==.Darkelas:BAAANQAECgEIAQAAAA==.Darknessbull:BAABNQAECoEhAAIWAAkKgBwbNwDQAgAWAAkKgBwbNwDQAgAAAA==.Daronn:BAABNQAECoElAAMRAAgKSiIVCwDJAgARAAgKxx8VCwDJAgADAAUK9R9oqACXAQAAAA==.Darthas:BAAANQAECgUICgAAAA==.Dashhunt:BAAANQAECgYIEwAAAA==.Dashlock:BAAANQAECgYIBgABNQAECgYIEwABAAAAAA==.Dashmagic:BAAANQADCgUIBQABNQAECgYIEwABAAAAAA==.Davy:BAAANQAECggIGwAAAQ==.Dawnbladedk:BAAANQADCgIIAgAAAA==.Daxigar:BAAANQAECgQICAAAAA==.',
De='Deadlyyrage:BAAANQAECggICAAAAA==.Deadschoo:BAAANQAECgYICAABNQAFFAUIEwAfALIYAA==.Deathkill:BAAANQADCggIFQAAAA==.Deekay:BAAANQADCgYICAAAAA==.Deeri:BAAANQAECgYIDwAAAA==.Defyndk:BAAANQADCgIIAgABNQAECgQICgABAAAAAA==.Defynds:BAAANQAECgQICgAAAA==.Demonesla:BAAANQADCgYIEAAAAA==.Demoslayer:BAAANQADCgUICwAAAA==.Denardiir:BAAANQAECgUIEAABNQAECgcIHwAcAJsXAA==.Desir:BAABNQAECoEjAAIUAAgKtBuRIABvAgAUAAgKtBuRIABvAgAAAA==.Desperate:BAAANQADCgUICgAAAA==.Destanna:BAAANQADCgYIEAAAAA==.Destiny:BAAANQAECgUIBQABNQAECgYIEAABAAAAAA==.Detoxic:BAAANQAECgEIAwAAAA==.Dewdeath:BAAANQAECgUICgAAAA==.Dewdvoker:BAAANQAECgEJAQAAAA==.',
Di='Diabsoule:BAAANQADCgIIAgAAAA==.Dilendra:BAAANQAECgIIAgABNQAECgcIIQAGAAsZAA==.Diman:BAAANQAECgIIAgAAAA==.Dinee:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.Dingodash:BAAANQAECgMIAwAAAA==.Dinngo:BAAANQABCgMIAwAAAA==.Dirge:BAAANQAECgQIBAAAAA==.Diseased:BAABNQAECoEhAAIGAAcKQCRMGADUAgAGAAcKQCRMGADUAgAAAA==.Dizzimajizz:BAABNQAECoEmAAICAAgKDyFyDwDnAgACAAgKDyFyDwDnAgAAAA==.',
Dm='Dmgfordays:BAABNQAECoEbAAILAAgKiRUgCQAiAgALAAgKiRUgCQAiAgAAAA==.',
Do='Dogê:BAABNQAECoEmAAISAAkKcw68IQACAgASAAkKcw68IQACAgAAAA==.Domme:BAAANQAECggIGQAAAQ==.Dornag:BAAANQADCgMIBgAAAA==.Dovakin:BAAANQADCgYICgAAAA==.Downpour:BAAANQAECgYICgAAAA==.',
Dr='Dragonhopes:BAAANQADCgYIBgAAAA==.Drated:BAAANQADCggIEAABNQAECgkJKAAKAEwSAA==.Drazalgor:BAAANQADCggJIQAAAA==.Dread:BAAANQAECgEIAQABNQAFFAgIGgATAMUiAA==.Drepung:BAABNQAECoEdAAMQAAgKtxCNLgBwAQAQAAcKzQ6NLgBwAQAHAAcKcAfDJQAgAQAAAA==.Dretlok:BAABNQAECoEgAAIPAAgK8Bb0HQAVAgAPAAgK8Bb0HQAVAgAAAA==.Droopyclam:BAAANQABCgQIBAAAAA==.Dryreach:BAAANQADCgEIAQAAAA==.',
Du='Duatani:BAAANQAECgEIAQAAAA==.Duck:BAAANQADCgYICQAAAA==.Duckpunch:BAAANQAECgQIBgAAAA==.Dukhan:BAABNQAECoEeAAIgAAgKkwauFwC/AQAgAAgKkwauFwC/AQAAAA==.Dukkhadk:BAAANQAECgYIDwAAAA==.Durinsoñ:BAABNQAECoEkAAIJAAgKtxj6PQBOAgAJAAgKtxj6PQBOAgAAAA==.Durzy:BAAANQAECgEJAQABNQAECggIIgAfAH0lAA==.Duskaryn:BAAANQAECggIBgAAAA==.',
Dw='Dwagoon:BAAANQADCgQICAAAAA==.Dworglaranna:BAAANQADCgQIBAABNQAECggIGgADANwNAA==.',
Dy='Dying:BAAANQAECgQIBAAAAA==.Dylanspally:BAABNQAECoEaAAIDAAgKKxfjbwAiAgADAAgKKxfjbwAiAgAAAA==.Dyrtylox:BAAANQADCgcICAAAAA==.',
['Dô']='Dôclock:BAAANQADCgMIAwAAAA==.',
Ea='Eaglekick:BAABNQAECoEaAAIDAAgKzxwwRgCcAgADAAgKzxwwRgCcAgAAAA==.Easilyamused:BAAANQAECgUIEAAAAA==.',
Ec='Eclips:BAAANQAECgEIAgAAAA==.',
Ed='Eddo:BAAANQAECgIIBAAAAA==.Edrissa:BAAANQAECgIIBAAAAA==.',
Eg='Egosumvacca:BAAANQADCgYIBgAAAA==.',
El='Elandiel:BAABNQAECoEoAAQKAAkKTBJPbQDvAQAKAAgKUxBPbQDvAQAZAAQKuQ3ZMwDoAAAaAAEK4wHrMAAgAAAAAA==.Elladale:BAABNQAECoEYAAMYAAcKGyHHEQBhAQANAAcKlB/KggBgAgAYAAQKxx7HEQBhAQAAAA==.Ellaxstrasza:BAAANQADCggIEgAAAA==.Elleryl:BAAANQAECggIEwAAAA==.Ellisen:BAAANQADCgcIDgAAAA==.Elryk:BAAANQAECgIIAgAAAA==.Elsaemonk:BAAANQAECgQIBwAAAA==.Elynna:BAAANQAECggICgAAAA==.',
Em='Emmaroids:BAAANQAECgQIBAAAAA==.',
En='Enjoi:BAAANQADCgQIBAAAAA==.Enoc:BAAANQAECgUIDwAAAA==.',
Er='Ero:BAAANQABCgcJBwAAAA==.Eruráma:BAAANQAECgYIDAABNQAECggIHwAQACAkAA==.',
Et='Etyeehaw:BAABNQAECoFCAAIhAAgKoCSjAQBBAwAhAAgKoCSjAQBBAwAAAA==.',
Ev='Evaêlfie:BAAANQADCgYICQAAAA==.Eviltank:BAAANQAECgYIDwAAAA==.',
Ez='Ezzbot:BAABNQAECoEYAAINAAgK9iKFMQAdAwANAAgK9iKFMQAdAwAAAA==.',
Fa='Fabulously:BAAANQAECgYIEAABNQAECggIJgALAKQTAA==.Fallèn:BAAANQAECgQICgAAAA==.Falnyr:BAABNQAECoFBAAIiAAgKWiPTBQAeAwAiAAgKWiPTBQAeAwAAAA==.Fanchone:BAAANQADCggIDAAAAA==.Fandahvis:BAAANQAECgQICQAAAA==.Fanney:BAAANQADCgIIAgAAAA==.Faroosh:BAAANQADCgYICAAAAA==.Fartshart:BAABNQAECoEbAAIJAAcK0hOBZQDBAQAJAAcK0hOBZQDBAQAAAA==.Favorite:BAAANQAECgEIAQAAAA==.',
Fe='Fearus:BAAANQABCgYICAAAAA==.Felanthropy:BAABNQAECoEkAAIUAAYK5xUMPwCNAQAUAAYK5xUMPwCNAQAAAA==.Felbunny:BAABNQAECoEXAAIUAAgKSxJqNADXAQAUAAgKSxJqNADXAQAAAA==.Felfliction:BAAANQABCgEIAQAAAA==.Felfrost:BAAANQABCgYIBgABNQABCgcICAABAAAAAA==.Felinae:BAAANQAECgEIAgAAAQ==.Felmagus:BAAANQAECgQIBgAAAA==.Felrrak:BAACNQAFFIERAAIUAAUKRwljCQBiAQAUAAUKRwljCQBiAQA1AAQKgUgAAhQACQriHMYWAMYCABQACQriHMYWAMYCAAAA.Felscalan:BAAANQABCgYIBgAAAA==.Felstro:BAAANQAECgcIEwAAAA==.Felwynbrooke:BAABNQAECoEpAAIhAAgKrRsDBACQAgAhAAgKrRsDBACQAgAAAA==.Ferynis:BAAANQAECgMIBAAAAA==.',
Fi='Firekhan:BAABNQAECoEiAAIZAAkKJRxNAwADAwAZAAkKJRxNAwADAwAAAA==.Fistful:BAABNQAECoElAAIHAAkK/A3QGADCAQAHAAkK/A3QGADCAQAAAA==.',
Fl='Flador:BAABNQAECoEfAAIbAAgKYR+IOwBJAgAbAAgKYR+IOwBJAgAAAA==.Flickatotem:BAAANQAECgUICQABNQAECggIPAAjAJEFAA==.Florinka:BAAANQAECgYIDAAAAA==.Fluffydecay:BAAANQADCgEIAQABNQAECgkJHgAKAMQYAA==.Flumble:BAAANQADCgQICAAAAA==.Fluticasone:BAAANQAECgIIBAAAAA==.',
Fo='Foghum:BAAANQAECgYIBgAAAA==.Forgedhorny:BAAANQAECgQIBAAAAA==.Forxiga:BAAANQAECgcICgAAAA==.Fourcheeks:BAABNQAECoErAAIJAAkKOxXdOABkAgAJAAkKOxXdOABkAgAAAA==.Fourthchild:BAAANQADCgQIBAAAAA==.Foxcalibur:BAAANQADCgIIAgAAAA==.Fozzydk:BAAANQADCgYIBgAAAA==.',
Fr='Frell:BAAANQADCgYIBwAAAA==.Frez:BAAANQAECgIIBAAAAA==.Frierén:BAAANQADCggIFAAAAA==.Frisli:BAAANQAECgYIEAAAAA==.Frostburn:BAAANQABCgIIAQABNQADCggIHgABAAAAAA==.Frostlass:BAAANQAECgQICQAAAA==.Frostveil:BAAANQAECgMIAwABNQAECggIBgABAAAAAA==.Frostyflakez:BAAANQAECgYIDQAAAA==.Frostyfruit:BAABNQAECoEaAAINAAgK7iDVVADGAgANAAgK7iDVVADGAgAAAA==.',
Fu='Furnous:BAABNQAECoE6AAMNAAgKJBn9fgBoAgANAAgKJBn9fgBoAgAYAAEK6BCHQAA0AAAAAA==.Fuzzydks:BAAANQAECgYIBgABNQAECgcIDQABAAAAAA==.',
Ga='Gaius:BAAANQADCgQIBAAAAA==.Galenddrel:BAAANQADCgQIBgAAAA==.Gant:BAAANQADCgYIDgAAAA==.Gargamus:BAAANQAECgQIBQAAAA==.',
Ge='Gegor:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.Gemashdk:BAAANQAECgEIAQABNQAECggIHAAkAPkUAA==.Gemashrogue:BAABNQAECoEcAAIkAAgK+RQqFgAfAgAkAAgK+RQqFgAfAgAAAA==.Gemtastic:BAAANQAECgIIAgAAAA==.Georgieanne:BAAANQADCggIIwAAAA==.',
Gh='Ghazali:BAAANQADCggICAAAAA==.Gheru:BAAANQAECgMIBAAAAA==.Ghoolies:BAAANQADCggIIQABNQAECggIHwAdALgUAA==.',
Gi='Gigadeekay:BAAANQADCgYICwAAAA==.Gildartz:BAAANQAECgYIBwAAAA==.',
Gl='Glitterspark:BAAANQAECgMIBQAAAA==.Glittr:BAABNQAECoEbAAMUAAcKABhnLQAMAgAUAAcK8hdnLQAMAgACAAYKMQ9xOABZAQABNQAFFAUIEQAiAFsOAA==.Glitty:BAACNQAFFIERAAMiAAUKWw5BBwD7AAAiAAMKRhdBBwD7AAAlAAMKGwanDwDAAAA1AAQKgUEAAyIACQqJIpsFACQDACIACQqJIpsFACQDACUABgpuHRsgALQBAAAA.Glodslock:BAAANQAECgQICgAAAA==.',
Go='Goated:BAAANQADCggIHgAAAA==.Goliathxx:BAAANQAECgEIAgAAAA==.Golokaann:BAAANQABCgIIAgAAAA==.Gonewe:BAAANQAECgQIBwAAAA==.Gongaga:BAAANQADCgYICQAAAA==.Googam:BAABNQAECoEmAAMMAAkKwSQOAgDCAwAMAAkKwSQOAgDCAwAmAAEKvRUEIgBAAAAAAA==.Gornuts:BAAANQAECgYIEwAAAA==.Gosly:BAABNQAECoEoAAISAAkK/h+bCgAlAwASAAkK/h+bCgAlAwAAAA==.Gozhuntsurv:BAAANQABCgQIBQAAAA==.Gozrogueolaw:BAAANQADCgUIBQAAAA==.',
Gr='Grailliford:BAABNQAECoEjAAMFAAYKggz+cAAsAQAFAAYKggz+cAAsAQAGAAMKigOSpABlAAAAAA==.Grayfox:BAAANQAECgQIBAAAAA==.Greeneyes:BAAANQADCgYICQAAAA==.Grelle:BAAANQADCggIDAAAAA==.Grimlock:BAAANQADCggICAAAAA==.Grimthursday:BAAANQADCggJHQABNQAECggIHwAbAEUgAA==.Grip:BAAANQAECgcIDwAAAA==.Groxigar:BAAANQADCgQIBAAAAA==.Groxom:BAAANQADCgUIBQAAAA==.Grumpu:BAAANQADCgcIDwAAAA==.Grutok:BAAANQAECgYIBwAAAA==.',
Gu='Guzwar:BAAANQAECgYIDAAAAA==.',
Gw='Gwydeon:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.',
Gy='Gyftable:BAAANQAECgYIEwAAAA==.Gyokuro:BAAANQABCgYIBwAAAA==.Gypsierose:BAABNQAECoEfAAISAAYKoQXCRADoAAASAAYKoQXCRADoAAAAAA==.',
['Gí']='Gíngervítis:BAAANQADCgEIAQAAAA==.',
['Gï']='Gïmli:BAAANQAECgEIAQAAAA==.',
Ha='Haahuna:BAAANQADCgIIAgAAAA==.Hairytoad:BAABNQAECoExAAIfAAcK8wzjUgBjAQAfAAcK8wzjUgBjAQAAAA==.Hakoda:BAAANQAECgIIAgAAAA==.Halleburn:BAAANQAECgQIBQAAAA==.Hardlightsgt:BAAANQADCgQIBAAAAA==.Harriet:BAAANQADCgMIAwAAAA==.Harubless:BAAANQAECgcICAAAAA==.Haruchi:BAAANQAECgMIBAABNQAFFAcIHgACAGggAA==.Harushear:BAACNQAFFIEeAAICAAcKaCCjAAC4AgACAAcKaCCjAAC4AgA1AAQKgSoAAgIACQprJvUAAOMDAAIACQprJvUAAOMDAAAA.Harushorn:BAAANQAECgUIBwAAAA==.Haruvion:BAAANQAECgcJBwABNQAFFAcIHgACAGggAA==.Harvester:BAABNQAECoEeAAIaAAgKMCQOAQBTAwAaAAgKMCQOAQBTAwAAAA==.Hathrein:BAAANQADCgIIAgAAAA==.Havocbringer:BAABNQAECoEYAAIUAAgKRw5gNQDQAQAUAAgKRw5gNQDQAQAAAA==.',
He='Headaxe:BAAANQAECgQIEAAAAA==.Healmemutt:BAAANQAECgQIBQAAAA==.Hearte:BAABNQAECoEsAAIgAAkKZx/hAwBTAwAgAAkKZx/hAwBTAwAAAA==.Hellweaver:BAAANQAECgYICgAAAA==.Hermano:BAAANQAECgUIEQABNQAECggIKgAPAF4VAA==.Hermiscuous:BAABNQAECoEqAAIPAAgKXhVtHAAmAgAPAAgKXhVtHAAmAgAAAA==.Hermy:BAAANQAECgYICwABNQAECggIKgAPAF4VAA==.Herpys:BAAANQADCgYIBgAAAA==.Hexmachine:BAABNQAECoEbAAITAAgKdRT5SwAaAgATAAgKdRT5SwAaAgAAAA==.Hexstorm:BAAANQABCgYIBgAAAA==.',
Hi='Hinotori:BAAANQADCgcIGgAAAA==.Hinters:BAABNQAECoEZAAIYAAcKhyK0BACzAgAYAAcKhyK0BACzAgAAAA==.',
Ho='Hogglee:BAAANQADCgYIBgAAAA==.Holing:BAABNQAECoElAAIDAAkKiiGOIAApAwADAAkKiiGOIAApAwAAAA==.Holybm:BAAANQADCgUICgAAAA==.Holyhealz:BAEANQAECgEIAgAAAA==.Holymama:BAAANQAECgYJBgAAAA==.Holymoly:BAAANQADCgEIAQAAAA==.Honeyduke:BAABNQAECoEbAAIQAAkKsRPRHgAOAgAQAAkKsRPRHgAOAgAAAA==.Hopenottodie:BAABNQAECoEYAAIGAAYKwQaEdgD4AAAGAAYKwQaEdgD4AAAAAA==.Hopes:BAAANQAECgYIEwAAAA==.',
Hr='Hrulgath:BAAANQADCgQIAwAAAA==.',
Hu='Humbler:BAAANQADCgcICAAAAA==.Huntum:BAAANQADCgUIBQAAAA==.Huntzha:BAAANQAECgYIEAAAAA==.',
Hy='Hyndis:BAAANQAECgMIBAAAAA==.Hyorinmâru:BAAANQAECgUIEwAAAA==.',
['Hí']='Híppiechick:BAAANQAECgUIEAAAAA==.',
Ia='Iamoutofammo:BAAANQAECgUIDQAAAA==.Ianix:BAABNQAECoEfAAMYAAgKMxcKEgBdAQANAAgKJhZAlAA7AgAYAAYKSRcKEgBdAQAAAA==.',
Ic='Icanhelp:BAAANQADCgUJBQAAAA==.Iceni:BAABNQAECoEhAAIDAAgKEB+EVwBmAgADAAgKEB+EVwBmAgAAAA==.Icepick:BAAANQADCggICAABNQAECggIBgABAAAAAA==.',
Id='Idíot:BAAANQAECgQICAAAAA==.',
If='Ifelforu:BAABNQAECoEaAAICAAgKbxvMFQCcAgACAAgKbxvMFQCcAgAAAA==.',
Ih='Ihaslegs:BAAANQAECgEIAQAAAA==.Ihitstuf:BAAANQAECgMIBAAAAA==.',
Il='Ilidun:BAAANQABCgIJAQAAAA==.Illimoo:BAAANQAECgcIDwAAAA==.Ilumminus:BAAANQADCgQIBwABNQAECgIIAgABAAAAAA==.',
Im='Imoldgrèg:BAAANQADCgMIAwABNQAECggIJAAJALcYAA==.',
In='Incineratus:BAABNQAECoEiAAICAAgKWxW2IAApAgACAAgKWxW2IAApAgAAAA==.Ineci:BAAANQADCggIKAAAAA==.Infurrnal:BAABNQAECoEVAAIKAAgKah8rKgDDAgAKAAgKah8rKgDDAgAAAA==.Innerpeace:BAAANQAECgQICgAAAA==.Inspirez:BAAANQADCgYIFwAAAA==.Instamissed:BAAANQADCgcIDAAAAA==.Intolerence:BAAANQADCggIHAAAAA==.',
Ip='Ipooptotems:BAAANQAECgQIBwAAAA==.',
Ir='Ironbeard:BAAANQADCgMIAwAAAA==.',
Is='Ishathon:BAAANQAECgEIAQAAAA==.Ishootstuff:BAABNQAECoEkAAIIAAgK4B5eLQDEAgAIAAgK4B5eLQDEAgAAAA==.Ismellyummy:BAAANQADCgMIAwAAAA==.',
It='Itsnotbatman:BAABNQAECoEkAAIIAAgKDhYKUgBRAgAIAAgKDhYKUgBRAgAAAA==.',
Iv='Ivanra:BAABNQAECoEnAAIhAAkKViIZAQBrAwAhAAkKViIZAQBrAwAAAA==.',
Iy='Iyna:BAAANQADCgUIBQAAAA==.',
Iz='Izlek:BAABNQAECoEfAAIPAAgKvAmkLgBwAQAPAAgKvAmkLgBwAQAAAA==.',
['Iì']='Iìe:BAABNQAECoEbAAMJAAcK2h+ZNwBpAgAJAAcK2h+ZNwBpAgADAAYKIhLlyABQAQAAAA==.',
Ja='Jagermaster:BAAANQADCgYIEAAAAA==.Janeygirl:BAABNQAECoEbAAIIAAcKUQtTkQC1AQAIAAcKUQtTkQC1AQAAAA==.',
Jc='Jcx:BAAANQADCgcIDwABNQAECgQICgABAAAAAA==.',
Je='Jeningo:BAAANQABCgcICAAAAA==.Jeningze:BAAANQAECgMIAwAAAA==.Jestiny:BAAANQAECgYIEAAAAA==.Jezebel:BAAANQADCggIKAAAAA==.',
Jo='Johannuz:BAAANQAECgcIEAAAAA==.Johngoblikon:BAAANQAECgUIDwAAAA==.Johnyf:BAAANQAECgQICAAAAA==.Jonessy:BAAANQAECgUIBQABNQAECggIGAAnANQSAA==.Jonesy:BAABNQAECoEYAAInAAgK1BJcEQCwAQAnAAgK1BJcEQCwAQAAAA==.Joneszy:BAAANQAFFAIIBAAAAA==.Jononononono:BAABNQAECoElAAIHAAgKQhxxDQCIAgAHAAgKQhxxDQCIAgAAAA==.Jonz:BAABNQAECoEjAAIDAAgK6Rr5WwBaAgADAAgK6Rr5WwBaAgAAAA==.Jorabelia:BAAANQAECgYIDgAAAA==.Joshington:BAABNQAECoEmAAIIAAgK/iSxDQBgAwAIAAgK/iSxDQBgAwAAAA==.Jotuunnz:BAAANQADCgUIBQAAAA==.Jox:BAAANQADCgQIBAAAAA==.',
Ju='Justkidding:BAAANQAECgQIBgAAAA==.Juícyfruít:BAAANQABCgQIBwAAAA==.',
Ka='Kahlia:BAAANQADCggIGwAAAA==.Kaiden:BAAANQADCgYICQAAAA==.Kalanix:BAABNQAECoEeAAIIAAYKqgdJxQBDAQAIAAYKqgdJxQBDAQAAAA==.Kaledor:BAAANQADCgEIAQAAAA==.Kalji:BAAANQADCgcIBwABNQAECgkJMAAHADEiAA==.Kamakaize:BAAANQAECggIEQAAAA==.Kanatari:BAAANQAECgQIBgAAAA==.Kansch:BAAANQADCgMIAwABNQAECggINQAPANkcAA==.Karaleigh:BAABNQAECoEmAAIHAAgKxgtSHgB4AQAHAAgKxgtSHgB4AQAAAA==.Katallia:BAAANQAECgUIEAAAAA==.Kateley:BAABNQAECoEZAAINAAkKYQVo+wBwAQANAAkKYQVo+wBwAQAAAA==.Kattadin:BAAANQAECgQIBQAAAA==.Kaybs:BAABNQAECoEcAAIIAAgKpw05iQDHAQAIAAgKpw05iQDHAQAAAA==.Kaysa:BAAANQAECgUIBAAAAA==.',
Ke='Keanoo:BAAANQAECgQICwAAAA==.Keanuu:BAAANQADCgMIAwAAAA==.Kekai:BAAANQABCgQICQAAAA==.Kelanthus:BAABNQAECoEgAAICAAgKLwU0MwCDAQACAAgKLwU0MwCDAQAAAA==.Kellalas:BAAANQADCggIFQAAAA==.Kelvinator:BAAANQAECgQIBwAAAA==.Kernni:BAAANQAECgYIDgAAAA==.Kes:BAAANQAFFAIIAwAAAA==.Kews:BAAANQADCgcIDQAAAA==.',
Kh='Khades:BAAANQADCgMIAwAAAA==.Kharkk:BAAANQAECgQIBQAAAA==.',
Ki='Kiingtoad:BAAANQAECgQIBAAAAA==.Kiluu:BAAANQAECgQIBAAAAA==.Kirisera:BAAANQAECgIIAwAAAA==.Kirstii:BAAANQADCgYIDwAAAA==.Kitkatzippy:BAAANQADCgQJBAAAAA==.Kittymik:BAEBNQAECoEhAAQfAAgK0xrXKwBYAgAfAAgK0xjXKwBYAgAPAAYKtyFWHAAnAgAdAAUKmheNFQBoAQAAAA==.Kixa:BAAANQADCgQIBAABNQAECggIIQATAPITAA==.',
Kl='Klawfel:BAAANQAECgUIBgAAAA==.',
Kn='Knöwledge:BAAANQADCgYICgABNQAECgQICAABAAAAAA==.',
Ko='Kohatu:BAAANQABCgIIAgAAAA==.Komoekomoe:BAAANQADCgUIAgAAAA==.Kormath:BAAANQAECgYIDwAAAA==.Korrack:BAAANQAECgQIBwAAAA==.Korruptoor:BAAANQABCgQIBAAAAA==.Kotath:BAAANQADCgUIBwAAAA==.Kowbruh:BAAANQADCgYIEgAAAA==.Kower:BAAANQADCgYICQAAAA==.',
Kr='Krianlan:BAAANQAECgEJAQABNQAECggIBgABAAAAAA==.',
Ku='Kuddy:BAABNQAECoEdAAIJAAkKxBVuOgBeAgAJAAkKxBVuOgBeAgAAAA==.Kumamizu:BAAANQAECgQIBwAAAA==.',
Kw='Kwee:BAAANQAECgcICwAAAA==.Kwr:BAAANQAECgQICQAAAA==.Kwyn:BAAANQADCggIKAABNQAECggIIQADAG0QAA==.',
Ky='Kyeon:BAAANQAECgEIAQAAAA==.Kyxa:BAAANQADCgYIBgABNQAECggIIQATAPITAA==.',
['Kè']='Kèw:BAAANQAECgQICAAAAA==.',
La='Lacronista:BAAANQAECgQIBwAAAA==.Lagavulin:BAABNQAECoEdAAIYAAkKuh1mAwDwAgAYAAkKuh1mAwDwAgABNQAFFAUIEwAfALIYAA==.Lalatinaford:BAAANQAECgIIAgAAAA==.Lambdadelta:BAAANQADCgIIAgAAAA==.Landacious:BAAANQADCgUIBQAAAA==.Lanthendis:BAAANQADCgEJAQAAAA==.Lastroll:BAAANQADCgYIBgABNQAECggIHwAbAEUgAA==.Layy:BAAANQAECgIIAgAAAA==.Lazerchìckèn:BAAANQADCgQIBAAAAA==.',
Le='Lebronjr:BAABNQAECoEnAAIRAAkKmSGJBABaAwARAAkKmSGJBABaAwAAAA==.Leella:BAAANQAECgYIBgAAAA==.Leere:BAAANQADCgYIBgAAAA==.Leeshpal:BAAANQADCgYICAAAAA==.Legolash:BAABNQAECoEhAAIIAAgKRhruRwBuAgAIAAgKRhruRwBuAgAAAA==.Lemerix:BAAANQADCgUIBwAAAA==.Leniisha:BAAANQAECgUIDAAAAA==.Lewy:BAAANQAECggIEAAAAA==.Lexicon:BAABNQAECoEcAAIDAAcKDhpfeAAMAgADAAcKDhpfeAAMAgAAAA==.Lexxen:BAACNQAFFIEKAAIMAAQKQxxpDwB0AQAMAAQKQxxpDwB0AQA1AAQKgS0AAgwACQofIlUHAHoDAAwACQofIlUHAHoDAAAA.Leàfy:BAABNQAECoEcAAIPAAgK4xUyHAAoAgAPAAgK4xUyHAAoAgAAAA==.',
Li='Lightblade:BAABNQAECoEeAAIRAAYKLw/hMgAhAQARAAYKLw/hMgAhAQAAAA==.Lightees:BAAANQAECgQIBgAAAA==.Lilibewhan:BAAANQABCgEIAQAAAA==.Limonae:BAABNQAECoEbAAINAAcKPBhnqgAMAgANAAcKPBhnqgAMAgAAAA==.Lindel:BAAANQAECgQIBAAAAA==.Lisellee:BAAANQAECgIIAgABNQAECgQIBgABAAAAAA==.',
Ll='Lljunior:BAAANQABCgMIAwAAAA==.',
Lo='Locha:BAAANQAECgEIAgAAAA==.Lockfox:BAAANQADCgEIAQAAAA==.Lockstøck:BAAANQAECgUICAAAAA==.Longicorn:BAAANQADCgYIBgABNQAECgkJKgAJAG0gAA==.Lostváyne:BAAANQADCgYJBgAAAA==.Lovemylamb:BAAANQAECgEIAQABNQAFFAYIFQAZAIcbAA==.',
Ls='Ls:BAABNQAECoEoAAIKAAkKBxUcRABpAgAKAAkKBxUcRABpAgAAAA==.',
Lu='Ludal:BAAANQADCggIJwAAAA==.Luketism:BAABNQAECoESAAINAAgKaRWmlwAzAgANAAgKaRWmlwAzAgAAAA==.Lunarrage:BAAANQAECgEIAQAAAA==.Lunen:BAABNQAECoElAAIeAAkKXRytCAC7AgAeAAkKXRytCAC7AgAAAA==.Lusidity:BAAANQADCggIDgAAAA==.',
Ly='Lyraria:BAAANQADCgIIAgAAAA==.Lythorn:BAAANQAECgUICAAAAA==.',
['Lè']='Lèpton:BAAANQAECgEIAwAAAA==.',
['Lé']='Léäf:BAABNQAECoEXAAMJAAcKYCHEKwCeAgAJAAcKYCHEKwCeAgADAAUKigcqAAHmAAAAAA==.',
['Lõ']='Lõx:BAABNQAECoElAAMKAAgKHiIKGgAJAwAKAAgKHiIKGgAJAwAaAAIK0iEEFgDCAAAAAA==.',
Ma='Macloven:BAAANQAECgIIAgAAAA==.Madamgrey:BAABNQAECoEcAAIMAAgKSAvmawCkAQAMAAgKSAvmawCkAQAAAA==.Maebyfunke:BAAANQADCggICAAAAA==.Magestørm:BAABNQAECoEdAAINAAkKwBVabQCOAgANAAkKwBVabQCOAgAAAA==.Magicboi:BAAANQAECgMIBgAAAA==.Magicmagnus:BAAANQAECgQIBAAAAA==.Magictacos:BAABNQAECoEoAAISAAgKIR8uEQDMAgASAAgKIR8uEQDMAgAAAA==.Magistrasza:BAABNQAECoElAAINAAkKzwuurgADAgANAAkKzwuurgADAgAAAA==.Majkusanagi:BAABNQAECoEYAAIHAAgKZQqoHwBmAQAHAAgKZQqoHwBmAQAAAA==.Makisig:BAABNQAECoEcAAIfAAgKnRNBNQAXAgAfAAgKnRNBNQAXAgAAAA==.Malfy:BAAANQAECgEIAQAAAA==.Malvnaire:BAAANQAECgcIDwAAAA==.Mancrak:BAAANQADCgIIAgAAAA==.Maraach:BAABNQAECoEfAAIDAAgK7RKefgD8AQADAAgK7RKefgD8AQAAAA==.Mariandor:BAAANQAECgQICgAAAA==.Marlinn:BAABNQAECoEkAAIIAAkK5w+iWQA9AgAIAAkK5w+iWQA9AgABNQAFFAcIGgAQAMEYAA==.Marlos:BAAANQAECgYIDwAAAA==.Marrmite:BAAANQADCgYIBgAAAA==.Marthaus:BAAANQADCgcJEgABNQAECgcIHwAHADYPAA==.Martmist:BAABNQAECoEfAAIHAAcKNg+cHgB0AQAHAAcKNg+cHgB0AQAAAA==.Massivepump:BAAANQAECgIIBAAAAA==.Mateo:BAAANQADCggIEgABNQAECgIIAgABAAAAAA==.Mathias:BAAANQAECgYIDAAAAA==.Mattiass:BAAANQAECgMIBgAAAA==.Mattrik:BAABNQAECoEhAAITAAgK8hOOYgDJAQATAAgK8hOOYgDJAQAAAA==.Maulyou:BAAANQAECgYIBgAAAA==.Maximilia:BAABNQAECoEqAAICAAkKjSAtCQA6AwACAAkKjSAtCQA6AwAAAA==.Maydayx:BAABNQAECoEhAAIDAAgKDh/dPwCwAgADAAgKDh/dPwCwAgABNQAFFAUIGQAUAHMZAA==.',
Mc='Mcdoom:BAABNQAECoEeAAIKAAkKxBg8PQB/AgAKAAkKxBg8PQB/AgAAAA==.Mcduff:BAAANQAECgQIBAAAAA==.',
Me='Meaningreen:BAAANQADCgcIEAAAAA==.Mekuntizichi:BAAANQADCgcICAAAAA==.Melazaelf:BAAANQADCgYIEAAAAA==.Melzas:BAAANQADCgIIAgAAAA==.Mermoo:BAAANQAECgIIAwAAAA==.Merriot:BAAANQADCgEIAgABNQAECggIEAABAAAAAA==.Messages:BAAANQAECgQIBAAAAA==.',
Mi='Midknîght:BAAANQADCgIIAgABNQAECgQICgABAAAAAA==.Midwa:BAACNQAFFIEYAAIDAAYKzCOoAQBuAgADAAYKzCOoAQBuAgA1AAQKgSkAAgMACQrcJosEAM8DAAMACQrcJosEAM8DAAAA.Miishah:BAAANQAECgcIDQAAAA==.Minisaph:BAAANQADCgcIBwAAAA==.Missfun:BAABNQAECoEcAAITAAgKAxdkRAA5AgATAAgKAxdkRAA5AgAAAA==.Mistel:BAAANQAECgcIDwAAAA==.Mistyfuzz:BAAANQAECgQIDQAAAA==.Mithrendir:BAAANQAECgIIAgAAAA==.',
Mj='Mjolnirr:BAAANQADCgcIDQAAAA==.',
Mo='Mogimp:BAAANQADCgQIBwABNQAECggIGwAEAN0ZAA==.Moguette:BAABNQAECoEfAAIDAAgK5wmSqQCUAQADAAgK5wmSqQCUAQABNQAECggIHwADAO0SAA==.Moistroll:BAAANQAECgEIAQABNQAECgkJHgAKAMQYAA==.Molith:BAAANQABCgYICAAAAA==.Monkkha:BAAANQADCgYICAAAAA==.Montecarlo:BAABNQAECoElAAQXAAgKtBnFHABvAgAXAAgKtBnFHABvAgAkAAIK/A+dQgBzAAAoAAIKkQe+FgBeAAAAAA==.Moonemerald:BAAANQADCgEIAQAAAA==.Moonfish:BAAANQADCgEIAQAAAA==.Moonhill:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Moonrain:BAAANQADCgIIAgAAAA==.Moordenaar:BAABNQAECoEhAAMFAAgK5RZxRADhAQAFAAgK5RZxRADhAQAEAAYK+gyhTQA0AQAAAA==.Moosy:BAAANQAECgQICAAAAA==.Morala:BAAANQADCgYIBgAAAA==.Morathia:BAAANQADCgIIAgAAAA==.Morgainne:BAAANQAECgIIAgAAAA==.Morphia:BAAANQADCgYIBgAAAA==.Morsoc:BAAANQAECgYIDQAAAA==.Mortarius:BAAANQAECgQICAAAAA==.Movicol:BAAANQAECgUIDAAAAA==.Mozan:BAAANQADCgYIBgAAAA==.Mozire:BAAANQAECgQICgAAAA==.Moñklee:BAAANQADCgUIBgABNQADCgcIDQABAAAAAA==.',
Ms='Msheal:BAAANQAECgEIAQAAAA==.',
Mt='Mth:BAAANQAECggIEQAAAA==.Mtnaan:BAAANQAECgMIBAAAAA==.',
Mu='Muerteamigo:BAAANQADCgMIAQAAAA==.Murz:BAAANQADCggIEQAAAA==.Musch:BAAANQAECgQIDAABNQAECggINQAPANkcAA==.Musde:BAABNQAECoE1AAMPAAgK2RwfFACIAgAPAAgK2RwfFACIAgAfAAEKIgVXsQAeAAAAAA==.Musterick:BAAANQAECgIIBQAAAA==.Muther:BAABNQAECoEXAAIbAAcKNw4ifwBgAQAbAAcKNw4ifwBgAQAAAA==.',
My='Myctlan:BAAANQAECgEIAQAAAA==.Mylie:BAAANQABCggICwAAAA==.Myrddn:BAAANQAECgQICAAAAA==.Myrdhin:BAAANQADCggICAABNQAECgYIDwABAAAAAA==.Myrdi:BAAANQADCgYICgABNQAECgYIDwABAAAAAA==.Myrsham:BAAANQAECgYIDwAAAA==.Mytearsheal:BAABNQAECoEeAAITAAYKUA67jgBOAQATAAYKUA67jgBOAQAAAA==.Mythbrediir:BAABNQAECoEfAAIcAAcKmxfGEADtAQAcAAcKmxfGEADtAQAAAA==.',
['Mü']='Müläflaga:BAAANQAECgQIBAAAAA==.',
Na='Naadina:BAAANQADCgcIHAAAAA==.Nadazarter:BAABNQAECoEYAAIDAAYKEgmA3gAkAQADAAYKEgmA3gAkAQAAAA==.Naggo:BAAANQAECgEIAQAAAA==.Naloiiha:BAAANQADCgUIBQAAAA==.Nalph:BAAANQAECggIEAAAAA==.Narassii:BAAANQADCgMIAwAAAA==.Narmaak:BAAANQADCgQIBAAAAA==.Nathun:BAAANQAECgIIBAAAAA==.Navillas:BAABNQAECoEjAAIPAAYKfhtUJADUAQAPAAYKfhtUJADUAQAAAA==.Nayha:BAAANQAECgEIAQAAAA==.',
Ne='Nebulachimi:BAABNQAECoFBAAIfAAkKMAvpPADkAQAfAAkKMAvpPADkAQAAAA==.Nebulahikari:BAAANQADCgYJBgAAAA==.Nebularyu:BAAANQAECgQICQAAAA==.Nedimus:BAABNQAECoEgAAIDAAcKeBOPnwCrAQADAAcKeBOPnwCrAQABNQAECgEIAgABAAAAAA==.Nekhrimah:BAABNQAECoEnAAMpAAgKiRDZAwBwAQANAAgKiRCgqQAOAgApAAcK8gnZAwBwAQAAAA==.Neoaerith:BAABNQAECoEfAAQMAAgK3giecQCPAQAMAAgK3giecQCPAQAmAAEKtwD8LQAXAAASAAEKXgHoggAXAAAAAA==.Nerii:BAAANQAECgIIAwAAAA==.Nerpthas:BAAANQAECgQICAAAAA==.Neverlinkx:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Ni='Niagarafall:BAAANQADCgIIAgAAAA==.Nidalàp:BAAANQADCgcIBwAAAA==.Nieriality:BAABNQAECoEnAAISAAcKkBQkKADBAQASAAcKkBQkKADBAQAAAA==.Nightshana:BAAANQADCgEIAQAAAA==.Nilin:BAABNQAECoEaAAIIAAgKjRwHQQCDAgAIAAgKjRwHQQCDAgAAAA==.Nina:BAABNQAECoEWAAIeAAkKoh1EBgABAwAeAAkKoh1EBgABAwABNQAECgQIBgABAAAAAA==.Ninylz:BAAANQADCgcIBwAAAA==.Nippen:BAAANQADCgIIAwAAAA==.Nisulus:BAAANQADCggIIAAAAA==.Niteañgel:BAAANQAECgUICQAAAA==.Niç:BAAANQAECgYIEQAAAA==.',
No='Noala:BAAANQADCgQIBAAAAA==.Noctuana:BAAANQADCgYIIAABNQAECgYIEAABAAAAAA==.Nojruh:BAAANQADCgQICAAAAA==.North:BAABNQAECoEvAAQeAAkKNhYpDgBDAgAeAAkKNhYpDgBDAgAfAAMKswMGiwB0AAAdAAEKXAfOPAAlAAAAAA==.Notbeezy:BAABNQAECoEaAAIDAAgKySRNHgAzAwADAAgKySRNHgAzAwAAAA==.Nothappy:BAAANQADCgUIBQAAAA==.Nox:BAACNQAFFIEHAAISAAQK2gz5CQAjAQASAAQK2gz5CQAjAQA1AAQKgRoAAhIACQq5G84VAI0CABIACQq5G84VAI0CAAAA.',
Nu='Numbnut:BAAANQADCgQIBAAAAA==.Numbskull:BAAANQADCgYICgAAAA==.Numnutts:BAABNQAECoEkAAIdAAgKOgr2EgCZAQAdAAgKOgr2EgCZAQAAAA==.Nutelle:BAAANQADCgYIBwAAAA==.',
Ny='Nymera:BAAANQADCgQIBAAAAA==.',
['Nè']='Nèrp:BAABNQAECoEkAAMJAAkKVRbgMgB9AgAJAAkKVRbgMgB9AgADAAEKGhD3bgE3AAAAAA==.',
['Nú']='Númenórean:BAABNQAECoEcAAIIAAcKjwm1pACKAQAIAAcKjwm1pACKAQAAAA==.',
['Nü']='Nüts:BAABNQAECoEfAAIdAAgKuBSVDgDwAQAdAAgKuBSVDgDwAQAAAA==.',
Oa='Oathorr:BAAANQADCgQIBAAAAA==.',
Ob='Obadiah:BAAANQADCgcIEwAAAA==.Obsidianshot:BAAANQADCggIGAAAAA==.',
Oc='Oceansiron:BAAANQADCgQIBAAAAA==.Ochayethenoo:BAAANQADCgcIBwAAAA==.',
Od='Oddmoos:BAAANQADCgEIAQAAAA==.',
Og='Ogriv:BAAANQADCggIDgAAAA==.',
Oi='Oii:BAAANQAECgEIAQAAAA==.',
Ok='Okthanx:BAAANQADCgUIBQAAAA==.',
Ol='Olos:BAAANQAECgUIBQAAAA==.Oluchronus:BAAANQADCgYIBwAAAA==.Olunaija:BAAANQAECgYIEAAAAA==.',
Om='Omm:BAEANQAECgQIBgAAAA==.Omninan:BAAANQABCgEIAQAAAA==.',
On='Onlyclaws:BAAANQAECggICgAAAA==.',
Oo='Oos:BAAANQADCgQIBAAAAA==.',
Or='Oroqen:BAAANQAECgYIEQAAAA==.',
Ou='Ouchiheal:BAABNQAECoEZAAIbAAcKoRJWdAB/AQAbAAcKoRJWdAB/AQAAAA==.',
Ov='Overhealer:BAACNQAFFIEFAAIMAAIKfg2PIgCbAAAMAAIKfg2PIgCbAAA1AAQKgSIAAwwACQo/F6swAIQCAAwACQo/F6swAIQCACYAAgpkA/AfAE4AAAAA.',
['Oà']='Oàthor:BAAANQAECgQIBwAAAA==.',
Pa='Pachi:BAAANQAECgEIAgAAAA==.Paladinmilan:BAAANQADCgIIAgAAAA==.Paladipuss:BAAANQADCggIEgAAAA==.Paladumb:BAACNQAFFIERAAIDAAUKIBGcCQCDAQADAAUKIBGcCQCDAQA1AAQKgU4AAwMACQrzHxgrAP4CAAMACQrzHxgrAP4CABEAAQoQCihtACIAAAAA.Palatism:BAAANQAECgYIDgAAAA==.Pallywings:BAABNQAECoEUAAIDAAcKww/KoQCmAQADAAcKww/KoQCmAQAAAA==.Panchovy:BAACNQAFFIEaAAIQAAcKwRjxAQBYAgAQAAcKwRjxAQBYAgA1AAQKgScAAhAACQpNInMLAAYDABAACQpNInMLAAYDAAAA.Parrexion:BAAANQADCgEIAQAAAA==.',
Pe='Peculiar:BAAANQAECgUIDgAAAA==.Pegor:BAAANQAECgMIBAABNQAECgQIBwABAAAAAA==.Pegz:BAAANQADCgYIBgAAAA==.Pegzpaladin:BAAANQADCgcIBwAAAA==.Peps:BAAANQADCggICAAAAA==.Peseshet:BAAANQAECgUIDwAAAA==.',
Ph='Phantom:BAAANQAECgQIBAAAAA==.Phazonicide:BAAANQAECgMIBgAAAA==.Phlaea:BAABNQAECoEeAAISAAgKaBtoFgCFAgASAAgKaBtoFgCFAgAAAA==.',
Pi='Pieata:BAAANQADCggIFAAAAA==.',
Pl='Plazistank:BAAANQADCggICAABNQAECgcIGAAYABshAA==.Plazzmma:BAAANQADCgMIBgABNQAECgcIGAAYABshAA==.Plplplpl:BAAANQAECgEIAQAAAA==.',
Po='Pogo:BAAANQAECgUICwABNQAECgYIDwABAAAAAA==.Poisoning:BAAANQAECgUIBQAAAA==.Poknat:BAAANQADCggICAAAAA==.Polkievoke:BAAANQADCgUJBQAAAA==.Pomdoes:BAAANQADCgMIAwAAAA==.Poppylotus:BAAANQADCggJKgAAAA==.Poppyrift:BAAANQAECgMICgAAAA==.Powerrager:BAAANQAECgEIAQAAAA==.',
Pr='Precioùs:BAABNQAECoEfAAIbAAgKRSCoGgDqAgAbAAgKRSCoGgDqAgAAAA==.Prettyhectic:BAABNQAECoEfAAIbAAcKYyBNMAB6AgAbAAcKYyBNMAB6AgAAAA==.Priincebun:BAAANQAECggICAAAAA==.Primate:BAAANQAECgMIAwAAAA==.Prinsesdonut:BAABNQAECoEhAAINAAgKVRGewwDZAQANAAgKVRGewwDZAQAAAA==.Projecjx:BAAANQADCgYICgAAAA==.Protagonist:BAACNQAFFIERAAIUAAUKySJ4BAD1AQAUAAUKySJ4BAD1AQA1AAQKgSYAAxQACQpLJG0PAA8DABQACAo3JG0PAA8DAAIABQpVFL0/ABwBAAE1AAUUCAgaABMAxSIA.Proz:BAAANQAECgIIAgAAAA==.Prozium:BAABNQAECoEfAAIEAAgKUiOyDQAMAwAEAAgKUiOyDQAMAwABNQAECgIIAgABAAAAAA==.',
Pu='Purepassion:BAAANQADCgMIAwAAAA==.Purifythis:BAAANQADCgMIAwAAAA==.Purson:BAAANQAECgEIAQAAAA==.',
Py='Pyrotic:BAAANQADCgYICAAAAA==.Pyschotic:BAAANQADCggIEgAAAA==.',
['Pä']='Pänya:BAAANQADCgcIDAAAAA==.',
['Pê']='Pêpsï:BAAANQABCgEIAQAAAA==.',
Qu='Quag:BAAANQADCgYJCAAAAA==.Quinny:BAABNQAECoEhAAMDAAgKbRCImQC5AQADAAgKbRCImQC5AQAJAAMKuAKY7ABuAAAAAA==.Quintar:BAABNQAECoE8AAIMAAkKsB0FFAAYAwAMAAkKsB0FFAAYAwAAAA==.',
Ra='Raagnar:BAAANQAECgMIAwAAAA==.Rabbage:BAABNQAECoEhAAMXAAkK6yHgCQAmAwAXAAgKtiPgCQAmAwAkAAEKkRP2RwBDAAAAAA==.Radaghast:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Raeka:BAABNQAECoEfAAMQAAgKICQhCQAqAwAQAAgKICQhCQAqAwAHAAEKhwyKRgAuAAAAAA==.Raenda:BAAANQADCgYICgAAAA==.Ragarlem:BAAANQAECgQIBAAAAA==.Ragefright:BAAANQAECgYIBgABNQAFFAQIBwASANoMAA==.Rageie:BAAANQAECgYIDwAAAA==.Rageieboop:BAAANQAECgcIDgAAAA==.Ragemore:BAABNQAECoEfAAIOAAgKeRfzHQBFAgAOAAgKeRfzHQBFAgAAAA==.Raggorg:BAAANQADCgcICAABNQAECgYIBwABAAAAAA==.Rahvine:BAAANQAECgIIAgAAAA==.Raiteq:BAABNQAECoEgAAMNAAkKOyP4IABNAwANAAkK4CH4IABNAwApAAcKkSFEAQCeAgAAAA==.Raitev:BAAANQAECgMIAwABNQAECgkJIAANADsjAA==.Ramirezz:BAAANQADCggJCAABNQAECgQICgABAAAAAA==.Ranmaoo:BAAANQAECggICgABNQAECgQIBgABAAAAAA==.Raputami:BAABNQAECoEpAAMTAAkK0RPSPgBQAgATAAkK0RPSPgBQAgAbAAIKIwhe8gBTAAAAAA==.Rastoons:BAAANQAECgQICAAAAA==.Rawlôck:BAABNQAECoElAAMKAAkKoRtqLgCzAgAKAAkKoRtqLgCzAgAZAAMKsxDCQwCrAAAAAA==.Raxor:BAAANQAECgMIBQAAAA==.Raya:BAABNQAECoEbAAMbAAcKJhjwUwDpAQAbAAcKJhjwUwDpAQATAAEKVgszIQEsAAAAAA==.',
Rd='Rde:BAAANQAECgcIDwAAAA==.',
Re='Reaperknight:BAAANQAECggIBgAAAA==.Redoctobah:BAAANQAECgQICAAAAA==.Regret:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Reignrott:BAABNQAECoEdAAMGAAgKqhWyOgD5AQAGAAgKqhWyOgD5AQAFAAIKGQU3vQBPAAAAAA==.Reika:BAAANQAECgQIBAAAAA==.Replaceable:BAAANQABCgIIAwABNQAECggIDQABAAAAAA==.Reptizzle:BAAANQADCgQIBAAAAA==.Restorer:BAAANQAECgEIBAAAAA==.Retalica:BAAANQAECgYIDwAAAA==.Retrishi:BAABNQAECoEkAAMgAAgK7hwiEABLAgAgAAcKIBwiEABLAgATAAUKEBKVnAAuAQAAAA==.Retxbladés:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Revelstat:BAAANQADCgQIBgAAAA==.Reverb:BAAANQAECggIEgAAAA==.Rexonon:BAAANQAECgQIBAABNQAECgkJGwATACoTAA==.Rexsham:BAABNQAECoEbAAMTAAkKKhMWTAAaAgATAAkKKhMWTAAaAgAbAAEKliVb6QBnAAAAAA==.Rexyclog:BAAANQAECgQICAAAAA==.Reyku:BAAANQAECgYIEAAAAA==.Reynasong:BAAANQADCgYIDAAAAA==.',
Rh='Rhydon:BAAANQAECgEIAQAAAA==.',
Ri='Ricard:BAAANQAECgIIBAAAAA==.Rickettsia:BAABNQAECoEhAAMZAAgKsxJTLgAHAQAKAAUKjQ/BuAAtAQAZAAQK7RRTLgAHAQAAAA==.Rig:BAAANQADCggJCAABNQAECgkJJAAWAFYbAA==.Rildis:BAAANQAECgQICAABNQAECgUIEwABAAAAAA==.Rippen:BAAANQADCgYIDQAAAA==.Ritasu:BAAANQAECgMIBAAAAA==.',
Rl='Rlain:BAAANQADCgQIBAABNQAECggIGgADANwNAA==.',
Ro='Robyngdfelow:BAABNQAECoEiAAIXAAgKwh8bDgDzAgAXAAgKwh8bDgDzAgAAAA==.Rohovart:BAAANQAECgQICAAAAA==.Rollingrick:BAABNQAECoEkAAMmAAgK+hnTBgD/AQAmAAYKph3TBgD/AQAMAAcKWA0PcgCOAQAAAA==.',
Rp='Rpro:BAAANQADCgEIAQAAAA==.',
Rr='Rroach:BAABNQAECoEhAAIRAAgK1hYHGwDsAQARAAgK1hYHGwDsAQAAAA==.',
Ru='Rubyblues:BAAANQADCgEIAgAAAA==.Runaway:BAAANQAECgIIAgAAAA==.Rustycrack:BAAANQAECgUIEQAAAA==.Ruul:BAAANQAECgEIAQAAAA==.',
Ry='Ryana:BAAANQABCgMIAwAAAA==.Ryilla:BAAANQAECgYIDwAAAA==.Rynoe:BAAANQAECgYIDgAAAA==.Ryri:BAAANQAECgUICQAAAA==.Ryujinx:BAAANQADCgEIAQAAAA==.Ryukendo:BAAANQAECgUICQAAAA==.',
['Rá']='Ráric:BAAANQAECgIIAgAAAA==.',
Sa='Saata:BAAANQAECgQIBgAAAA==.Sableman:BAAANQAECgQIBgAAAA==.Saccromycaes:BAAANQAECggIDwAAAA==.Saclem:BAAANQAECgQICAAAAA==.Saha:BAAANQAECgQICgAAAA==.Saintayah:BAAANQAECgYIEgAAAA==.Salokin:BAAANQAECgEIAQABNQAFFAYIFAAGAN0cAA==.Salorellin:BAABNQAECoElAAMCAAkKdyGKEgDBAgACAAgKDyGKEgDBAgAUAAQKLiGPQgB1AQAAAA==.Sandrèena:BAABNQAECoEaAAIDAAgK3A2erACNAQADAAgK3A2erACNAQAAAA==.Sanity:BAAANQAECgEJAQAAAA==.Sarakatawen:BAAANQAECgQICAAAAA==.Sarumash:BAAANQAECgMIAwAAAA==.Satanah:BAAANQAECgQIBwAAAA==.Satomi:BAAANQAECgYIDgAAAA==.Satre:BAABNQAECoEkAAIjAAgKVhsMBQB/AgAjAAgKVhsMBQB/AgAAAA==.',
Sc='Scratchsniff:BAAANQAECgYICAAAAA==.',
Se='Seculoe:BAABNQAECoEWAAIPAAcKPRbbIwDZAQAPAAcKPRbbIwDZAQAAAA==.Seedypete:BAAANQADCgcIDQAAAA==.Seemébloody:BAAANQAECgUICwAAAA==.Seldarine:BAAANQAECgcIDwAAAA==.Selten:BAAANQAECgYIDwAAAA==.Selvaggio:BAAANQABCgQIBgAAAA==.Sendel:BAAANQADCgQIBAAAAA==.Senele:BAAANQAECgEIAgAAAA==.Senescence:BAACNQAFFIEVAAQZAAYKhxveBQC+AAAKAAMKcxkhGAD+AAAZAAIK/xzeBQC+AAAaAAEK0R4mBwBcAAA1AAQKgS4ABAoACQpcJVUoAMsCAAoABwoEJVUoAMsCABkABQobIAMUAMcBABoAAwq8IpkRAAkBAAAA.Serperior:BAAANQAECgQIBAABNQAECgQIBgABAAAAAA==.Sesshomar:BAAANQADCgEIAQAAAA==.',
Sh='Sh:BAABNQAECoEVAAIFAAgK2h5sKwBmAgAFAAgK2h5sKwBmAgAAAA==.Shadopaw:BAABNQAECoEnAAIfAAYKYBclRgCqAQAfAAYKYBclRgCqAQAAAA==.Shadowrae:BAAANQAECgYIDAABNQAECgcIDwABAAAAAA==.Shadowsyy:BAAANQADCgcIBwAAAA==.Shadyllama:BAABNQAECoEhAAIMAAgK0A6newBtAQAMAAgK0A6newBtAQAAAA==.Shamkat:BAAANQAECgQIBAAAAA==.Shammah:BAABNQAECoEkAAIRAAgKDBawGwDlAQARAAgKDBawGwDlAQAAAA==.Shammbulance:BAAANQADCgIJAgAAAA==.Shamuoo:BAAANQADCgQIBAAAAA==.Sharlo:BAAANQADCgcIFQAAAA==.Sharnie:BAABNQAECoEhAAIGAAgKNxNcRADKAQAGAAgKNxNcRADKAQAAAA==.Shear:BAAANQAECggICwAAAA==.Shellatrix:BAABNQAECoEkAAInAAgKJRlMDQAGAgAnAAgKJRlMDQAGAgAAAA==.Shepp:BAABNQAECoEbAAILAAgKdB1jBQCjAgALAAgKdB1jBQCjAgAAAA==.Shinhati:BAAANQAECgIIAgAAAA==.Shommy:BAAANQADCggICAAAAA==.Shootette:BAABNQAECoEeAAIIAAgKKw3bigDEAQAIAAgKKw3bigDEAQAAAA==.Shutenz:BAAANQAECgYICwABNQAECggILQAGABIlAA==.Shãmtastic:BAAANQADCgYIBgAAAA==.',
Si='Silandryn:BAAANQAECgIJAgAAAA==.Sinderela:BAABNQAECoEZAAIDAAgKlQbOxwBSAQADAAgKlQbOxwBSAQAAAA==.Sinisterwing:BAABNQAECoEWAAIkAAcKTQ5bHwDAAQAkAAcKTQ5bHwDAAQAAAA==.Siolani:BAAANQADCgUICAAAAA==.',
Sk='Skeptikk:BAABNQAECoElAAMTAAkKlhteRAA5AgATAAgKSxpeRAA5AgAbAAEKCgRjBwEuAAAAAA==.Skinnery:BAAANQAECgQICAAAAA==.Skrull:BAABNQAECoEkAAQiAAgKXwm8GQCPAQAiAAgKSgi8GQCPAQAlAAYK3QYrLQAWAQAjAAQKtgdsFQCxAAAAAA==.',
Sl='Slateray:BAAANQAECgcIDwAAAA==.Slipnslide:BAAANQAECgUICQAAAA==.Slyr:BAAANQAECgUICgAAAA==.',
Sm='Smaky:BAAANQAECgcIEQAAAA==.Smaque:BAABNQAECoEyAAIWAAgKWSBfNgDTAgAWAAgKWSBfNgDTAgAAAA==.Smegging:BAAANQADCgYICQAAAA==.',
Sn='Snaare:BAAANQADCgYJDAAAAA==.',
So='Solcaris:BAAANQAECgQICgAAAA==.Sorie:BAAANQAECggIDwAAAA==.Soulwishper:BAAANQAECgYIDwAAAA==.Sourstraps:BAAANQADCgMIAwAAAA==.Soùlstealer:BAAANQADCgQIBAAAAA==.',
Sp='Sparkdead:BAAANQADCgYICgAAAA==.Spazzimitazz:BAAANQADCgIIAgAAAA==.Spazzy:BAABNQAECoEkAAIbAAcKySLgKwCPAgAbAAcKySLgKwCPAgAAAA==.Spelltickle:BAAANQADCgEIAQAAAA==.Spenna:BAAANQAECgYIDwAAAA==.Spudacus:BAABNQAECoEYAAMYAAcKth1/FAA9AQANAAYKBhiM1AC4AQAYAAQKgiB/FAA9AQAAAA==.Spuddk:BAABNQAECoElAAIFAAkK7hekLQBZAgAFAAkK7hekLQBZAgAAAA==.Spudsham:BAAANQAECggIDgABNQAECgkJJQAFAO4XAA==.',
St='Stabforcash:BAACNQAFFIEcAAMXAAcKFCVSAAAFAwAXAAcKFCVSAAAFAwAkAAEKGgq2EABUAAA1AAQKgRsAAxcACQrZI1cHAEkDABcACQrZI1cHAEkDACQABwoUBjopAGEBAAAA.Starleaf:BAAANQADCgQIBgAAAA==.Stellarluse:BAAANQAECgQICAAAAA==.Stickler:BAABNQAECoEfAAIGAAgKPySsDAA7AwAGAAgKPySsDAA7AwAAAA==.Stonkerella:BAAANQADCgIIAgAAAA==.Stonque:BAAANQADCgcIBwABNQAECggIMgAWAFkgAA==.Stormchief:BAAANQAECgMIAwAAAA==.Stormgoat:BAAANQADCgYIBwAAAA==.Stormie:BAAANQAECgUIDAAAAA==.Stormrider:BAABNQAECoEcAAITAAgKPBwcMQCRAgATAAgKPBwcMQCRAgAAAA==.Streuth:BAABNQAECoElAAIcAAkKLCVtAQCvAwAcAAkKLCVtAQCvAwAAAA==.Strummer:BAACNQAFFIERAAIIAAUKLSOTBADtAQAIAAUKLSOTBADtAQA1AAQKgU0AAwgACQq5JEIGAKIDAAgACQq5JEIGAKIDAA4AAgpTFcVnAGgAAAAA.Stubbyholder:BAAANQADCggICAAAAA==.',
Su='Subaru:BAAANQAECgIIAgABNQAECggIDQABAAAAAA==.Subaruu:BAAANQAECggIDQAAAA==.Subsiding:BAAANQAECgQIBwAAAA==.Subtera:BAAANQADCgcIBwAAAA==.Supagroova:BAAANQAECgIIAgAAAA==.Supernothing:BAAANQAECgYIEgAAAA==.Superswede:BAABNQAECoEVAAIdAAYKESLXCgBRAgAdAAYKESLXCgBRAgAAAA==.Susurrus:BAAANQADCgUIBQAAAA==.',
Sw='Switchdoctor:BAAANQADCggIEwABNQAECggIBgABAAAAAA==.Sworf:BAABNQAECoE2AAITAAkKAx7oHQD8AgATAAkKAx7oHQD8AgAAAA==.',
Sy='Syaarhunter:BAAANQAECgYICgAAAA==.Syaarknight:BAAANQADCgYJBwAAAA==.Syaarpally:BAAANQAECgUICAAAAA==.Syazar:BAAANQAECgYIDAAAAA==.Sylanthia:BAAANQAECgcIEwAAAA==.Sylblades:BAAANQAECgYIBwAAAA==.Sylwizard:BAAANQABCgEIAQAAAA==.',
['Só']='Sóg:BAAANQAECgEIAgABNQAECgkJKQAKAN4hAA==.',
['Sø']='Søbz:BAAANQADCggJIwAAAA==.Søg:BAABNQAECoEpAAQKAAkK3iGRRQBkAgAKAAcK+B6RRQBkAgAaAAMKAyXHDgA9AQAZAAEKOSUIWQBsAAAAAA==.',
['Sù']='Sùnjin:BAAANQAECgMIAwABNQAECggIGwAEAN0ZAA==.',
Ta='Tabknight:BAABNQAECoEsAAIGAAkK/hjBHgCjAgAGAAkK/hjBHgCjAgAAAA==.Taelron:BAAANQAECgIIAgAAAA==.Taelstard:BAABNQAECoEfAAIIAAYKKhHboACSAQAIAAYKKhHboACSAQAAAA==.Taichook:BAAANQAECgEIAQABNQAECggIQwADAB0jAA==.Tainui:BAAANQADCgIIBAAAAA==.Taithos:BAABNQAECoFDAAIDAAgKHSOULwDsAgADAAgKHSOULwDsAgAAAA==.Taizen:BAAANQAECgcIBgAAAA==.Talanardonis:BAAANQADCgYIBgAAAA==.Tanktough:BAAANQAECgUIBQAAAA==.Tarago:BAABNQAECoExAAIFAAgKXCMKHADHAgAFAAgKXCMKHADHAgAAAA==.Taranisis:BAAANQAECgYIEQAAAA==.Targetone:BAABNQAECoEVAAIIAAcKEhcvbgAJAgAIAAcKEhcvbgAJAgAAAA==.Tasall:BAAANQAECgQIBAAAAA==.Tauntflaunt:BAABNQAECoEhAAMFAAkKXCGHFgDuAgAFAAkKXCGHFgDuAgAGAAEKOgNZ2gAKAAAAAA==.Tayy:BAAANQADCgEIAQAAAA==.',
Te='Tech:BAABNQAECoEeAAIQAAgKGyXOBgBPAwAQAAgKGyXOBgBPAwAAAA==.Tempø:BAAANQAECgEJAgAAAA==.Tenkris:BAAANQAECgUICwAAAA==.Tenleigh:BAAANQAECgQICgAAAA==.Tenzero:BAAANQADCgYJBgAAAA==.Terroria:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Terrorizor:BAABNQAECoEjAAIFAAYKnBUtWwB8AQAFAAYKnBUtWwB8AQAAAA==.',
Th='Thalía:BAAANQADCggIHwAAAA==.Thargroar:BAABNQAECoEqAAIdAAkKIyOeAQCjAwAdAAkKIyOeAQCjAwAAAA==.Thazix:BAAANQADCgYIEAABNQAECggIJAAGAP4fAA==.Theboysavior:BAAANQAECgEIAQAAAA==.Thefluffyman:BAAANQAECgcIEgAAAA==.Themetzi:BAAANQADCgUIBQAAAA==.Thiss:BAABNQAECoEkAAIIAAgK4CJUHAANAwAIAAgK4CJUHAANAwAAAA==.Thordak:BAAANQAECgUIEAAAAA==.Thoridian:BAAANQADCgQIBwAAAA==.Thunderfella:BAAANQADCggICAAAAA==.Thurlarra:BAAANQADCgEIAQAAAA==.Thùnder:BAAANQADCgYICQAAAA==.',
Ti='Tidewalker:BAAANQADCgYIFQAAAA==.Tigolbits:BAAANQADCgcICgAAAA==.Tiroo:BAAANQADCgMIAwABNQAECgcIIAAJAAklAA==.Titdor:BAAANQADCgIIAgAAAA==.',
To='Tobythemonk:BAABNQAECoEeAAIHAAkKmRp7CwCvAgAHAAkKmRp7CwCvAgAAAA==.Toehacker:BAABNQAECoEfAAIWAAgKPiG3MQDlAgAWAAgKPiG3MQDlAgAAAA==.Toliman:BAAANQADCgYIEAAAAA==.Tolkarkiller:BAABNQAECoEXAAIgAAcKqROJFAD3AQAgAAcKqROJFAD3AQAAAA==.Tomarr:BAEBNQAECoElAAIbAAkKPAprawCbAQAbAAkKPAprawCbAQABNQAECggIFwAbAOMNAA==.Tomarv:BAEANQADCgYIBwABNQAECggIFwAbAOMNAA==.Tonsham:BAAANQADCgYIBwAAAA==.Totemspanker:BAAANQAECgQIBgAAAA==.Totoki:BAAANQADCggICAAAAA==.Touchitonce:BAAANQAECgQIEQAAAA==.Toxic:BAAANQADCgIIAgAAAA==.Toóz:BAABNQAECoEoAAMTAAkKkRUmPgBTAgATAAkKkRUmPgBTAgAbAAcK0ASOmwAUAQAAAA==.',
Tr='Trailblayxur:BAABNQAECoEcAAIjAAgKOA10CgCdAQAjAAgKOA10CgCdAQAAAA==.Traser:BAAANQADCgYJDAAAAA==.Trickyknight:BAABNQAECoFWAAMFAAkKTiT7BACaAwAFAAkKGCT7BACaAwAGAAgKsB9FGADUAgAAAA==.Trickymage:BAAANQADCgUIBQAAAA==.Trinityheals:BAAANQAECgEIAgAAAA==.',
Tu='Tuckerius:BAAANQAECgIIAgAAAA==.Turahk:BAABNQAECoEcAAIRAAgK7BmMEwBGAgARAAgK7BmMEwBGAgAAAA==.Turtlesoup:BAABNQAECoEfAAIIAAcK5BFBfwDfAQAIAAcK5BFBfwDfAQAAAA==.',
Tw='Twofoottall:BAAANQAECgEIAQAAAA==.',
Ty='Tylendorian:BAAANQABCgEIAQAAAA==.Tylerolothus:BAAANQAECgYIBwAAAA==.Tynndera:BAAANQAECgYIEAAAAA==.Tyrawr:BAAANQAECgQIBAABNQAFFAYIFwAGABkaAA==.Tyth:BAABNQAECoEhAAMaAAgKaRnABQA+AgAaAAgKaRnABQA+AgAKAAEKywinLgErAAAAAA==.',
['Tí']='Tím:BAABNQAECoEcAAIDAAgKoiHQMQDkAgADAAgKoiHQMQDkAgAAAA==.',
Ud='Udderlyfuzzy:BAAANQAECgQICgABNQAECgkJHgAKAMQYAA==.',
Un='Unclefister:BAAANQAECggICAAAAA==.Unclegrandpa:BAAANQADCgQIBgAAAA==.',
Ur='Uranbraug:BAAANQABCgIIAgAAAA==.Urnot:BAAANQAECgQIBAABNQAFFAQICAAKAAoNAA==.Urôt:BAACNQAFFIEIAAIKAAQKCg2DEwAuAQAKAAQKCg2DEwAuAQA1AAQKgRcAAgoACAqdGiw3AJQCAAoACAqdGiw3AJQCAAAA.',
Uw='Uwusue:BAAANQAFFAIIAgAAAA==.',
Va='Vaeline:BAAANQABCgUIBgAAAA==.Valac:BAACNQAFFIEXAAIGAAYKGRphBgDfAQAGAAYKGRphBgDfAQA1AAQKgSoAAgYACQrfIt0LAEQDAAYACQrfIt0LAEQDAAAA.Valkyrie:BAABNQAECoEcAAIRAAkKkSFsBABdAwARAAkKkSFsBABdAwAAAA==.Valothos:BAABNQAECoEwAAIJAAcKWBZkWADuAQAJAAcKWBZkWADuAQAAAA==.Valtiell:BAABNQAECoElAAIkAAkKfh7zBgAGAwAkAAkKfh7zBgAGAwAAAA==.Valuri:BAABNQAECoEdAAMTAAgKXwwoaQC0AQATAAgKXwwoaQC0AQAbAAQKRgx/vQDDAAAAAA==.Varainne:BAABNQAECoEhAAQZAAgKPBecLgAFAQAKAAUKMhM8pQBaAQAZAAMK9h2cLgAFAQAaAAEK8QIFMQAfAAAAAA==.Varidina:BAAANQAECgEIAgAAAA==.',
Ve='Vegimitê:BAAANQADCgUJBQAAAA==.Vegymite:BAAANQADCgEIAQAAAA==.Velgath:BAABNQAECoEyAAIkAAkKuxxpCADnAgAkAAkKuxxpCADnAgAAAA==.Velisea:BAAANQAECgEIAQABNQAECgcIGAAYABshAA==.Velkhana:BAAANQAECgcIEQAAAA==.Velmorra:BAABNQAECoEYAAIkAAgK3Q3vGQD3AQAkAAgK3Q3vGQD3AQAAAA==.Venser:BAAANQADCgUIBQAAAA==.Veratis:BAAANQAECgMIAwAAAA==.Vesperatears:BAAANQADCgUICAAAAA==.',
Vi='Victoria:BAABNQAECoEZAAIhAAcKNheoBQAwAgAhAAcKNheoBQAwAgAAAA==.Vinee:BAAANQAECgQIBwAAAA==.Vioneva:BAABNQAECoEjAAIIAAgKPRCnbAANAgAIAAgKPRCnbAANAgAAAA==.Viscelock:BAABNQAECoEjAAILAAkKMRBpCQAZAgALAAkKMRBpCQAZAgAAAA==.Vivyregosa:BAACNQAFFIETAAINAAYKYRCsDgDeAQANAAYKYRCsDgDeAQA1AAQKgSsAAg0ACQr7HbxJAOACAA0ACQr7HbxJAOACAAAA.',
Vo='Voidaira:BAAANQADCgUIBQAAAA==.Volda:BAAANQAECgEIAQAAAA==.',
Vx='Vxi:BAACNQAFFIEXAAIXAAcK6hzYAACnAgAXAAcK6hzYAACnAgA1AAQKgRkAAhcACQoKIVQRANMCABcACQoKIVQRANMCAAAA.',
Vy='Vynarion:BAAANQADCgMIAwAAAA==.',
Wa='Wagglehoof:BAAANQADCgcIDAAAAA==.Wain:BAAANQAECgMIBAAAAA==.Wakantanka:BAAANQAECgQICAAAAA==.Wanglord:BAAANQAECgYIEwAAAA==.Wardõn:BAAANQADCggICwAAAA==.Warpig:BAAANQADCgUIBgAAAA==.Warriormilan:BAAANQAECgIIAgAAAA==.Waxedtaco:BAAANQAECgQICgAAAA==.',
Wh='Wheato:BAABNQAECoEiAAMfAAgKfSV+DQBPAwAfAAgKPSV+DQBPAwAeAAMKOCIYJgAeAQAAAA==.Wheyprotein:BAAANQAECgQIBAAAAA==.Whipshot:BAAANQADCggICQAAAA==.Whiteflame:BAAANQAECgcICwAAAA==.Whiteopal:BAABNQAECoEkAAIMAAgKZRLOUgD/AQAMAAgKZRLOUgD/AQAAAA==.Whorship:BAAANQAECggIDAAAAA==.',
Wi='Willownera:BAAANQABCgIIAwAAAA==.Willowsun:BAAANQAECgIIAgAAAA==.Winterzap:BAAANQAECgUIBQAAAA==.Wipe:BAAANQADCggICAABNQAFFAgIGgATAMUiAA==.',
Wo='Wolfyhunter:BAAANQADCggJCAAAAA==.',
Wr='Wrathkiller:BAAANQADCgcJBwAAAA==.',
Wu='Wulfrick:BAAANQADCgMIBQAAAA==.',
['Wí']='Wítchypoo:BAAANQAECgUIEAAAAA==.',
['Wú']='Wúlf:BAAANQADCgQIBAAAAA==.',
Xa='Xalatoth:BAAANQAECgUIBQAAAA==.Xane:BAAANQADCggIIAAAAA==.Xanetia:BAAANQAECgQICwAAAA==.Xatir:BAAANQADCgQIBwAAAA==.',
Xb='Xbladês:BAAANQAECgMIAwAAAA==.',
Xi='Xinee:BAAANQAECgMIBAABNQAECgQIBwABAAAAAA==.Xinful:BAAANQADCgUJBQABNQAECgEJAQABAAAAAA==.Xint:BAAANQABCgEIAQAAAA==.',
Xj='Xjaryl:BAAANQADCgcIDgAAAA==.',
Xo='Xoger:BAAANQABCgQIBAAAAA==.',
Xy='Xyandris:BAAANQAECgQIBwAAAA==.',
['Xï']='Xïbalba:BAAANQABCgIJAgAAAA==.',
Ya='Yamasharma:BAAANQADCgYJFgAAAA==.',
Ye='Yeehaww:BAAANQAECgQIDAAAAA==.',
Yi='Yifa:BAAANQAECggICgAAAA==.',
Yy='Yykes:BAAANQABCgIIAgAAAA==.',
Za='Zaharax:BAABNQAECoEiAAIYAAYKKgsEFwAeAQAYAAYKKgsEFwAeAQAAAA==.Zaharaxis:BAAANQADCgEIAQAAAA==.Zaharis:BAAANQAECgUICAAAAA==.Zanakari:BAAANQADCgYJFAAAAA==.Zasilia:BAAANQADCgUIBQAAAA==.Zass:BAAANQADCgQIBAAAAA==.',
Ze='Zensetrazath:BAABNQAECoElAAMlAAkKChYgEACUAgAlAAkKChYgEACUAgAiAAQKrA7iJAD3AAAAAA==.Zerath:BAAANQADCgYIBwAAAA==.',
Zh='Zhanqui:BAABNQAECoEbAAIPAAgKzQ1pKQChAQAPAAgKzQ1pKQChAQAAAA==.',
Zi='Ziba:BAABNQAECoElAAIIAAkKeRksNQCpAgAIAAkKeRksNQCpAgAAAA==.Zilithus:BAAANQADCgYIBgABNQAECgYIBwABAAAAAA==.Zingermage:BAEANQAECgcICwABNQAFFAQIBwAFAI4kAA==.Zipzamzoom:BAAANQADCggIAgABNQAECggIBgABAAAAAA==.',
Zo='Zoroo:BAAANQAECgQIDwAAAA==.',
Zr='Zross:BAAANQADCgcIDQAAAA==.',
Zu='Zudo:BAAANQAECgUIDgAAAA==.Zuthrais:BAACNQAFFIEMAAITAAUK5APhDgBBAQATAAUK5APhDgBBAQA1AAQKgUQAAhMACQpwEjVFADUCABMACQpwEjVFADUCAAAA.Zuulik:BAAANQADCgYIDgAAAA==.Zuuls:BAAANQADCggJCwAAAA==.',
Zz='Zz:BAACNQAFFIESAAIgAAcK7xV1AAB6AgAgAAcK7xV1AAB6AgA1AAQKgSsAAiAACQpIJrIAANMDACAACQpIJrIAANMDAAAA.',
['Án']='Ángelpie:BAAANQAECgEIAgAAAA==.',
['Är']='Ärrôw:BAAANQADCgYIAgAAAA==.',
['Ås']='Åshka:BAAANQABCgQIAgAAAA==.',
['Él']='Élryk:BAAANQAECgIIAQAAAA==.',
['Ôl']='Ôliver:BAAANQADCgUIBQAAAA==.',
['ßa']='ßankai:BAAANQAECgUIBgABNQAECgUIEwABAAAAAA==.',
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
