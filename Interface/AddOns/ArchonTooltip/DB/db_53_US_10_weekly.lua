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

local lookup = {'Unknown-Unknown','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Monk-Mistweaver','Hunter-BeastMastery','Paladin-Holy','Warlock-Demonology','Priest-Holy','Hunter-Marksmanship','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Arms','Rogue-Assassination','Warlock-Destruction','Warlock-Affliction','Shaman-Restoration','Monk-Windwalker','Warrior-Protection','Paladin-Protection','Druid-Feral','Druid-Guardian','Druid-Balance','DemonHunter-Devourer','Warrior-Fury','Priest-Shadow','Druid-Restoration','Shaman-Enhancement','Hunter-Survival','Mage-Arcane','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Evoker-Preservation','Monk-Brewmaster','Rogue-Subtlety','Rogue-Outlaw','Mage-Fire','Priest-Discipline',}
local provider = {region='US',realm="Aman'Thul",name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aadonis:BAAANQADCgIIAwAAAA==.Aanubus:BAAANQADCggJDQABNQADCggIHgABAAAAAA==.Aarek:BAAANQABCgYIBgABNQAECgUIBwABAAAAAA==.',
Ab='Abyssalmaw:BAAANQAECgUIDwAAAA==.',
Ac='Achillesqt:BAAANQADCgIIAgAAAA==.Acionna:BAAANQADCggIHAAAAA==.',
Ad='Ada:BAAANQADCgIIAgAAAA==.Adekeahokeha:BAAANQADCgYIBQAAAA==.Adrenalin:BAABNQAECoEZAAICAAgKSRLtcADvAQACAAgKSRLtcADvAQAAAA==.',
Ae='Aedros:BAAANQAECgQIBQAAAA==.Aegis:BAAANQADCgIIAgAAAA==.Aellan:BAABNQAECoEVAAMDAAcK+CAfIAA8AgADAAcKkh8fIAA8AgAEAAMKlCQmXQA2AQAAAA==.Aeorin:BAAANQADCgIIAgAAAA==.',
Af='Afflexion:BAAANQAECgYIDAAAAA==.Afterlyfe:BAAANQADCggICAAAAA==.',
Ag='Agonier:BAAANQAECgEIAQAAAA==.',
Aj='Ajira:BAAANQADCgcIDwAAAA==.',
Ak='Akiaki:BAAANQAECgEIAgAAAA==.',
Al='Aladk:BAABNQAECoEiAAMFAAkKHiHnCgA/AwAFAAkKHiHnCgA/AwAEAAEKUwKqwAAhAAAAAA==.Alafus:BAAANQAECgYICgABNQAECgkJIgAFAB4hAA==.Alaldras:BAAANQAECgEIAgAAAA==.Alalock:BAAANQAECggIDgABNQAECgkJIgAFAB4hAA==.Alaria:BAAANQAECgYIEwABNQAECgkJLAAGAGohAA==.Alarian:BAABNQAECoEgAAIHAAgKfyMqFgAVAwAHAAgKfyMqFgAVAwAAAA==.Aldai:BAAANQAECgIIAgAAAA==.Alendros:BAAANQAECgIIAgAAAA==.Alexsia:BAAANQADCgEIAQAAAA==.Aliiah:BAAANQADCggICgAAAA==.Alir:BAABNQAECoElAAIEAAkKIh5GFgDQAgAEAAkKIh5GFgDQAgAAAA==.Alista:BAAANQADCgIIAgAAAA==.Alle:BAAANQAECgIIAgAAAA==.Allen:BAAANQAECgUIBgAAAA==.Allyren:BAABNQAECoEaAAIIAAcKFhd6SQD+AQAIAAcKFhd6SQD+AQAAAA==.Allythriea:BAAANQAECgIIBAAAAA==.',
Am='Ambertwo:BAAANQAECgYIDAAAAA==.Amitheria:BAAANQAECgYIEAAAAA==.',
An='Andreb:BAAANQAECgUIDQAAAA==.Andromyda:BAAANQAECgIIBAAAAA==.Angelofnite:BAAANQAECgIIBAAAAA==.Angelofpower:BAAANQADCgYIBwAAAA==.Angelzspirit:BAAANQABCgYICAAAAA==.Angrychicken:BAAANQAFFAEIAQAAAA==.Ankh:BAAANQAECgYIEwAAAA==.Anklebreakr:BAAANQADCgMIAwABNQAECggIFQAJAGofAA==.Antopanto:BAAANQAECgcIEwAAAA==.Anubiset:BAAANQADCgUIBQAAAA==.',
Ar='Aralia:BAAANQAECgIIAgAAAA==.Arasmina:BAABNQAECoElAAIIAAkKjiSXAgC5AwAIAAkKjiSXAgC5AwAAAA==.Arcanystra:BAAANQAECgIIBAAAAA==.Arcathal:BAABNQAECoEkAAIKAAgK2CAAGQDiAgAKAAgK2CAAGQDiAgAAAA==.Arcshottx:BAAANQAECgUIDgAAAA==.Arliis:BAABNQAECoEaAAIIAAcKCSXSGADqAgAIAAcKCSXSGADqAgAAAA==.Arniy:BAAANQADCgYJDQABNQAECgkJLAAGAGohAA==.Artey:BAABNQAECoEcAAILAAgKthkyGQBaAgALAAgKthkyGQBaAgAAAA==.',
As='Ascot:BAAANQADCgYJBwABNQAECgcIGwAGAHAHAA==.Asenathe:BAAANQADCggIAgAAAA==.Ashaad:BAAANQAECgUIEAAAAA==.Asyluun:BAAANQAECgIIAwAAAA==.',
At='Atorvas:BAAANQADCgMIAwAAAA==.',
Au='Auchioane:BAAANQAECgYIEwAAAA==.Aurelyia:BAAANQAECgUICwAAAA==.',
Aw='Awakenimg:BAAANQADCgEIAQAAAA==.',
Ay='Ayhai:BAAANQAECgQIBAAAAA==.',
Az='Azador:BAAANQAECgYIEQAAAA==.Azael:BAAANQAECgQIBAAAAA==.Azarion:BAAANQADCgEIAQAAAA==.Azayzel:BAAANQAECgIIAgAAAA==.Azemm:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.Azza:BAAANQADCgcICgAAAA==.',
['Aé']='Aérfen:BAAANQADCgIJAgAAAA==.',
Ba='Backburner:BAAANQADCgMIAwAAAA==.Badvoodoo:BAABNQAECoEcAAIFAAcKwhe3PADOAQAFAAcKwhe3PADOAQAAAA==.Balahara:BAAANQADCgYIBgAAAA==.Balfor:BAABNQAECoEUAAIMAAUKFiOfUADlAQAMAAUKFiOfUADlAQAAAA==.Bandarpallie:BAAANQAECgMIBAAAAA==.Bara:BAAANQABCgMIAwAAAA==.Battlepope:BAAANQADCgIIBAAAAA==.Baynage:BAAANQAECgYIBgAAAA==.',
Be='Beastah:BAAANQADCgUJCAAAAA==.Beauxmax:BAAANQADCgYIBgAAAA==.Beefkakes:BAAANQADCggIGAAAAA==.Belest:BAAANQAECgYIEAAAAA==.Belfhee:BAAANQADCgEIAQAAAA==.Belkelmor:BAAANQAECgIIBAAAAA==.Bellaros:BAAANQAECgQIBgAAAA==.Belyana:BAAANQADCgIIAgAAAA==.Belè:BAABNQAECoEiAAMNAAgKnBlyHgBfAgANAAgKnBlyHgBfAgAOAAIKVBLoHQB2AAAAAA==.Beorm:BAAANQADCgYICgAAAA==.Bermagi:BAAANQAECgQICwAAAA==.',
Bi='Biders:BAAANQADCgEIAQAAAA==.Bigarchrules:BAAANQAECgEIAQAAAA==.Bigbanana:BAAANQAECgUICgAAAA==.Bigdaddy:BAABNQAECoEoAAIPAAkKSRxHIwAGAwAPAAkKSRxHIwAGAwAAAA==.Bigole:BAAANQAECgUIBQAAAA==.Bigrilla:BAAANQAECgMIAwAAAA==.Bigsecksi:BAAANQAECgMIAwAAAA==.Bilbearbagns:BAAANQAECgIIAgAAAA==.Billkills:BAAANQADCgIIAgAAAA==.Billpie:BAAANQAECgQICAAAAA==.Billyblobby:BAAANQAECgIIAgAAAA==.Binkei:BAAANQAECggICgAAAA==.Bitee:BAAANQAECgQIBAAAAA==.',
Bl='Blacklight:BAAANQAECgMIAwAAAA==.Blacksky:BAAANQAECgQIBAAAAA==.Blade:BAABNQAECoEZAAIQAAcKdRykHgAyAgAQAAcKdRykHgAyAgAAAA==.Blastette:BAAANQADCgcIIAAAAA==.Blayze:BAABNQAECoEaAAICAAcK/QZltQBAAQACAAcK/QZltQBAAQAAAA==.Bloodclaw:BAAANQABCgUIBwAAAA==.Bloodgimp:BAABNQAECoEVAAMDAAgKmxigMwCjAQADAAcKcBKgMwCjAQAEAAYK4xd9SQCKAQAAAA==.Bloodlust:BAAANQAECgcIDQAAAA==.Bloodslay:BAABNQAECoEdAAIPAAgKMxPaaAALAgAPAAgKMxPaaAALAgAAAA==.Bloodtank:BAAANQADCgYIBgAAAA==.Bluebrood:BAAANQAECgIIBQAAAA==.',
Bo='Boenarrow:BAAANQAECgMIAwAAAA==.Bojack:BAAANQAECgYIDAAAAA==.Bombshot:BAAANQAECgMIBgAAAA==.Boomdeeznutz:BAAANQADCgUICwAAAA==.Boomkinbill:BAAANQADCgEIAQAAAA==.Boproblem:BAAANQADCgUIBQAAAA==.Botmage:BAAANQAECgcIEwAAAA==.Bovinei:BAAANQAECgMIBgAAAA==.',
Br='Brackk:BAAANQADCggIHAAAAA==.Braedaevia:BAABNQAECoEbAAQRAAgKWg4eEgDVAQARAAgKvw0eEgDVAQAJAAQKyAaSyQDUAAASAAMKCgrcFQCiAAAAAA==.Brahnson:BAAANQADCgQICAAAAA==.Brawlzdeep:BAAANQADCgQIBAAAAA==.Breldyr:BAAANQAECgcIDwAAAA==.Bronnir:BAAANQADCgYICAAAAA==.Brotis:BAAANQAECgMIAwAAAA==.Brylen:BAACNQAFFIEYAAIMAAcKOyNGAADvAgAMAAcKOyNGAADvAgA1AAQKgRsAAgwACQprJtACANADAAwACQprJtACANADAAAA.',
Bu='Bubbleblonde:BAAANQAECgMIAwABNQAECggIKgAJAKUUAA==.Bubblebtch:BAAANQAECgQIBAAAAA==.Bubblerat:BAAANQAECgMIAwAAAA==.Bullus:BAAANQAECgEIAQAAAA==.Buntz:BAABNQAECoElAAIPAAkKRiQfCwCLAwAPAAkKRiQfCwCLAwAAAA==.',
Ca='Caain:BAAANQAECgQIBAAAAA==.Caalypso:BAABNQAECoEmAAITAAcKAB8FNwA9AgATAAcKAB8FNwA9AgAAAA==.Caileron:BAAANQAECgQIBgAAAA==.Cakesnpies:BAABNQAECoEbAAMHAAgKSxWOSgBBAgAHAAgKSxWOSgBBAgALAAMKrwVbVQB+AAAAAA==.Callamedic:BAAANQADCggIBwABNQADCggIHgABAAAAAA==.Callofdeath:BAAANQAECgIIAwAAAA==.Cancelyn:BAAANQADCgYIBwAAAA==.Cantplaymage:BAAANQABCgQIBAAAAA==.Capsmasher:BAAANQADCgYIBgAAAA==.Carb:BAAANQAECgYIDgAAAA==.Cashehm:BAAANQAECgUIBQAAAA==.Caströ:BAABNQAECoEdAAMGAAcKehOGGACfAQAGAAcKehOGGACfAQAUAAEKhRX8TwBAAAAAAA==.',
Cc='Ccllaa:BAAANQADCggICAAAAA==.',
Ce='Cecilbgnome:BAAANQADCgYIAgAAAA==.Celad:BAABNQAECoEcAAIFAAgKwR3zGAC1AgAFAAgKwR3zGAC1AgAAAA==.Cenedra:BAABNQAECoEYAAILAAgKgBqBFwBtAgALAAgKgBqBFwBtAgAAAA==.',
Ch='Chaihard:BAAANQADCgUIBQAAAA==.Cheesenonion:BAAANQADCgYICwABNQAECggIHgAQAGkYAA==.Chocolates:BAAANQADCgIIAgAAAA==.Chromitez:BAABNQAECoEcAAIEAAgKOCVjCgBFAwAEAAgKOCVjCgBFAwAAAA==.Chroren:BAAANQAECgcIDQAAAA==.Chubberz:BAAANQADCggICgABNQAECggIHAAIAGETAA==.Churlish:BAABNQAECoEiAAIQAAkKvxLWFwBtAgAQAAkKvxLWFwBtAgAAAA==.',
Cl='Claptothetop:BAAANQAECgYIDQAAAA==.Clawyaeyeout:BAAANQADCgQIBAAAAA==.Cleavís:BAABNQAECoEZAAIVAAcKUiX9BADuAgAVAAcKUiX9BADuAgAAAA==.Cllaa:BAABNQAECoEeAAMCAAgKpRohVwA+AgACAAgKnxghVwA+AgAWAAMKJx1AMQD9AAABNQADCggICAABAAAAAA==.Cllu:BAAANQAECgYICgAAAA==.',
Co='Cogedor:BAAANQADCgEIAQAAAA==.Colourzz:BAAANQADCgYJBgAAAA==.Conflict:BAAANQAECgMIAwAAAA==.Coobs:BAAANQADCgYIBgAAAA==.Corepia:BAAANQAECgUIDQAAAA==.Cozymonday:BAABNQAECoEhAAMXAAgKVx0oBwCOAgAXAAgKJhsoBwCOAgAYAAUKFSENEgC8AQAAAA==.',
Cr='Cramberly:BAAANQAECgYIEAAAAA==.Craystone:BAAANQADCgQIBAAAAA==.Crayzdruid:BAAANQADCgQIBAAAAA==.Crikeys:BAAANQADCgYIDQAAAA==.Crispynips:BAAANQADCggIFQAAAA==.Cristeria:BAEANQAECgYIDAAAAA==.Crnreaper:BAAANQAECgMIBgAAAA==.Crotch:BAAANQABCgIIAgAAAA==.',
Cu='Custodes:BAAANQADCgYJEQAAAA==.',
Cy='Cyradis:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.',
Da='Dabita:BAABNQAECoEcAAIHAAYKmhJFiQCVAQAHAAYKmhJFiQCVAQAAAA==.Daewong:BAABNQAECoEsAAMGAAkKaiF5AwBbAwAGAAkKaiF5AwBbAwAUAAEKuQOWVgAsAAAAAA==.Dagami:BAAANQADCggIHQAAAA==.Daiganzan:BAAANQAECgMIAwAAAA==.Daisuke:BAAANQAECgEIAQAAAA==.Dajango:BAABNQAECoEaAAMHAAcKQSROIgDVAgAHAAcKQSROIgDVAgALAAMKRwk2UQCOAAAAAA==.Daknar:BAABNQAECoEYAAMJAAgKlR8lGgDvAgAJAAgKlB8lGgDvAgARAAIK7h8HQQCqAAAAAA==.Dalenvoidy:BAAANQAECgQIBAAAAA==.Damâ:BAAANQADCgYIBgAAAA==.Dandal:BAAANQAECgQIBAAAAA==.Darkelas:BAAANQADCggICAAAAA==.Darknessbull:BAABNQAECoEdAAIPAAgKfxzhQgCHAgAPAAgKfxzhQgCHAgAAAA==.Daronn:BAABNQAECoEfAAMWAAgK7iChGADaAQAWAAUKIiKhGADaAQACAAUK9R9yiwCmAQAAAA==.Darthas:BAAANQAECgQIBQAAAA==.Dashhunt:BAAANQAECgYIEwAAAA==.Dashlock:BAAANQAECgYIBgABNQAECgYIEwABAAAAAA==.Dashmagic:BAAANQADCgUIBQABNQAECgYIEwABAAAAAA==.Davy:BAAANQAECggIGwAAAQ==.Dawnbladedk:BAAANQADCgIIAgAAAA==.Daxigar:BAAANQAECgIIBAAAAA==.',
De='Deadschoo:BAAANQAECgYIBAABNQAFFAUIEQAZAN0XAA==.Deathkill:BAAANQADCgcIDQAAAA==.Deekay:BAAANQADCgYICAAAAA==.Deeri:BAAANQAECgUIDgAAAA==.Defyndk:BAAANQADCgIIAgABNQAECgMIBgABAAAAAA==.Defynds:BAAANQAECgMIBgAAAA==.Demonesla:BAAANQADCgYIDQAAAA==.Demoslayer:BAAANQADCgUICwAAAA==.Denardiir:BAAANQAECgQICgABNQAECgcIGAAVAIQVAA==.Desir:BAABNQAECoEeAAINAAgKNBviHABrAgANAAgKNBviHABrAgAAAA==.Desperate:BAAANQADCgUICgAAAA==.Destanna:BAAANQADCgYIDQAAAA==.Detoxic:BAAANQAECgEIAgAAAA==.Dewdeath:BAAANQAECgUICgAAAA==.Dewdvoker:BAAANQAECgEJAQAAAA==.',
Di='Diabsoule:BAAANQADCgIIAgAAAA==.Dilendra:BAAANQAECgIIAgABNQAECgcIHAAFAMIXAA==.Diman:BAAANQAECgIIAgAAAA==.Dinee:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Dingodash:BAAANQAECgMIAwAAAA==.Diseased:BAABNQAECoEZAAIFAAcK+iM7FgDNAgAFAAcK+iM7FgDNAgAAAA==.Dizzimajizz:BAABNQAECoEeAAIaAAgKlh58DQDvAgAaAAgKlh58DQDvAgAAAA==.',
Dm='Dmgfordays:BAABNQAECoEXAAIbAAgKNBWiBwAmAgAbAAgKNBWiBwAmAgAAAA==.',
Do='Dogê:BAABNQAECoEeAAIcAAgKCA7sIgDMAQAcAAgKCA7sIgDMAQAAAA==.Domme:BAAANQAECggIFQAAAQ==.Dornag:BAAANQADCgMIBgAAAA==.Dovakin:BAAANQADCgYICgAAAA==.Downpour:BAAANQAECgQIBAAAAA==.',
Dr='Dragonhopes:BAAANQADCgYIBgAAAA==.Drated:BAAANQADCggIEAABNQAECgkJJgAJAIIRAA==.Drazalgor:BAAANQADCggJIQAAAA==.Dread:BAAANQAECgEIAQABNQAFFAcIGAAMADsjAA==.Drepung:BAABNQAECoEbAAMGAAcKcAfTIQAhAQAGAAcKcAfTIQAhAQAUAAUK6hAKMgAXAQAAAA==.Dretlok:BAABNQAECoEZAAIdAAcK4BaPHwDWAQAdAAcK4BaPHwDWAQAAAA==.Droopyclam:BAAANQABCgQIBAAAAA==.Dryreach:BAAANQADCgEIAQAAAA==.',
Du='Duatani:BAAANQAECgEIAQAAAA==.Duck:BAAANQADCgYICQAAAA==.Duckpunch:BAAANQAECgQIBgAAAA==.Dukhan:BAABNQAECoEeAAIeAAgKkwZ1FADKAQAeAAgKkwZ1FADKAQAAAA==.Dukkhadk:BAAANQAECgUICQAAAA==.Durinsoñ:BAABNQAECoEcAAIIAAgKzhONQwAWAgAIAAgKzhONQwAWAgAAAA==.Durzy:BAAANQAECgEJAQABNQAECggIIgAZAH0lAA==.Duskaryn:BAAANQAECggIBgAAAA==.',
Dw='Dwagoon:BAAANQADCgQIBAAAAA==.Dworglaranna:BAAANQADCgQIBAABNQAECgYIDgABAAAAAA==.',
Dy='Dying:BAAANQAECgQIBAAAAA==.Dylanspally:BAAANQAECgcIEgAAAA==.Dyrtylox:BAAANQADCgUIBQAAAA==.',
['Dô']='Dôclock:BAAANQADCgMIAwAAAA==.',
Ea='Eaglekick:BAAANQAECgYIEAAAAA==.Earendill:BAAANQADCgMIAwAAAA==.Easilyamused:BAAANQAECgUICwAAAA==.',
Ec='Eclips:BAAANQAECgEIAQAAAA==.',
Ed='Eddo:BAAANQAECgIIAgAAAA==.Edrissa:BAAANQAECgIIAgAAAA==.',
Eg='Egosumvacca:BAAANQADCgYIBgAAAA==.',
El='Elandiel:BAABNQAECoEmAAQJAAkKghGAXwDqAQAJAAgKbw+AXwDqAQARAAQKuQ1sMADxAAASAAEK4wERLAAgAAAAAA==.Elladale:BAAANQAECgYIDwAAAA==.Ellaxstrasza:BAAANQADCggIEgAAAA==.Elleryl:BAAANQAECggICgAAAA==.Ellisen:BAAANQADCgcIDgAAAA==.Elryk:BAAANQAECgIIAgAAAA==.Elsaemonk:BAAANQAECgMIAwAAAA==.Elynna:BAAANQAECggICAAAAA==.',
Em='Emmaroids:BAAANQAECgMIAwAAAA==.',
En='Enjoi:BAAANQADCgQIBAAAAA==.Enoc:BAAANQAECgQICgAAAA==.',
Er='Ero:BAAANQABCgcJBwAAAA==.Eruráma:BAAANQAECgYIDAABNQAECgcIGAAUAEMlAA==.',
Et='Etyeehaw:BAABNQAECoE0AAIfAAgKACRaAQBDAwAfAAgKACRaAQBDAwAAAA==.',
Ev='Evaêlfie:BAAANQADCgYICQAAAA==.Eviltank:BAAANQAECgUICQAAAA==.',
Ez='Ezzbot:BAABNQAECoEXAAIgAAgKaiLdKgAhAwAgAAgKaiLdKgAhAwAAAA==.',
Fa='Fabulously:BAAANQAECgYIDgABNQAECgcIIwAbAKMUAA==.Fallèn:BAAANQAECgMIBgAAAA==.Falnyr:BAABNQAECoE+AAIhAAgKViOwBAAuAwAhAAgKViOwBAAuAwAAAA==.Fanchone:BAAANQADCggIDAAAAA==.Fandahvis:BAAANQAECgQICQAAAA==.Fanney:BAAANQADCgIIAgAAAA==.Faroosh:BAAANQADCgYICAAAAA==.Fartshart:BAAANQAECgYIEAAAAA==.Favorite:BAAANQAECgEIAQAAAA==.',
Fe='Fearus:BAAANQABCgYICAAAAA==.Felanthropy:BAAANQAECgUIEwAAAA==.Felbunny:BAABNQAECoEXAAINAAgKSxJ9KwDvAQANAAgKSxJ9KwDvAQAAAA==.Felfliction:BAAANQABCgEIAQAAAA==.Felinae:BAAANQAECgEIAgAAAQ==.Felmagus:BAAANQAECgQIBgAAAA==.Felrrak:BAACNQAFFIERAAINAAUKRwnlBgB1AQANAAUKRwnlBgB1AQA1AAQKgUUAAg0ACQriHJUQAOcCAA0ACQriHJUQAOcCAAAA.Felscalan:BAAANQABCgYIBgAAAA==.Felstro:BAAANQAECgUIDAAAAA==.Felwynbrooke:BAABNQAECoEiAAIfAAgKrRtTAwCcAgAfAAgKrRtTAwCcAgAAAA==.Ferynis:BAAANQAECgEIAgAAAA==.',
Fi='Firekhan:BAABNQAECoEaAAIRAAkK8hn5AwDgAgARAAkK8hn5AwDgAgAAAA==.Fistful:BAABNQAECoElAAIGAAkK/A0JFQDWAQAGAAkK/A0JFQDWAQAAAA==.',
Fl='Flador:BAAANQAECgYIEwAAAA==.Flickatotem:BAAANQAECgQIBAABNQAECggILQAiAO4DAA==.Florinka:BAAANQAECgQIBgAAAA==.Fluffydecay:BAAANQADCgEIAQABNQAECggIGwAJAGUbAA==.Flumble:BAAANQADCgQICAAAAA==.Fluticasone:BAAANQAECgIIAgAAAA==.',
Fo='Forgedhorny:BAAANQADCgYIDAAAAA==.Forxiga:BAAANQAECgcICgAAAA==.Fourcheeks:BAABNQAECoEkAAIIAAgKRRaKPgAqAgAIAAgKRRaKPgAqAgAAAA==.Fourthchild:BAAANQADCgQIBAAAAA==.Fozzydk:BAAANQADCgYIBgAAAA==.',
Fr='Frell:BAAANQADCgQIBAAAAA==.Frez:BAAANQAECgIIBAAAAA==.Frierén:BAAANQADCggIFAAAAA==.Frisli:BAAANQAECgQIBAAAAA==.Frostburn:BAAANQABCgIIAQABNQADCggIHgABAAAAAA==.Frostlass:BAAANQAECgQIBwAAAA==.Frostveil:BAAANQAECgMIAwABNQAECggIBgABAAAAAA==.Frostyflakez:BAAANQAECgYIDQAAAA==.Frostyfruit:BAABNQAECoEaAAIgAAgK7iCYQwDbAgAgAAgK7iCYQwDbAgAAAA==.',
Fu='Furnous:BAABNQAECoEzAAMgAAgKgBW9gwA7AgAgAAgKgBW9gwA7AgAjAAEK6BB3OQA2AAAAAA==.Fuzzydks:BAAANQAECgYIBgABNQAECgcIDQABAAAAAA==.',
Ga='Gaius:BAAANQADCgQIBAAAAA==.Galenddrel:BAAANQADCgIIAwAAAA==.Gant:BAAANQADCgYIDgAAAA==.Gargamus:BAAANQAECgQIBQAAAA==.',
Ge='Gegor:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Gemashdk:BAAANQADCggIDgABNQAECgYIEAABAAAAAA==.Gemashrogue:BAAANQAECgYIEAAAAA==.Gemtastic:BAAANQADCgQJBAAAAA==.Georgieanne:BAAANQADCggIGQAAAA==.',
Gh='Ghazali:BAAANQADCggICAAAAA==.Gheru:BAAANQAECgMIBAAAAA==.Ghoolies:BAAANQADCgYJGQABNQAECgYIEwABAAAAAA==.',
Gi='Gigadeekay:BAAANQADCgYICwAAAA==.Gildartz:BAAANQAECgYIBwAAAA==.',
Gl='Glitterspark:BAAANQAECgMIBQAAAA==.Glittr:BAAANQAECgYIEgABNQAFFAUIEQAhAFUOAA==.Glitty:BAACNQAFFIERAAMhAAUKVQ4CBgADAQAhAAMKRhcCBgADAQAkAAMKGwbODADRAAA1AAQKgT0AAyEACQqJIi4EAD0DACEACQqJIi4EAD0DACQABQoJHtkcALoBAAAA.Glodslock:BAAANQAECgMIBgAAAA==.',
Go='Goated:BAAANQADCggIHgAAAA==.Goliathxx:BAAANQAECgEIAgAAAA==.Golokaann:BAAANQABCgIIAgAAAA==.Gonewe:BAAANQAECgMIBQAAAA==.Gongaga:BAAANQADCgYICQAAAA==.Googam:BAABNQAECoEeAAIKAAgKhSUwBwBtAwAKAAgKhSUwBwBtAwAAAA==.Gornuts:BAAANQAECgUIEgAAAA==.Gosly:BAABNQAECoEgAAIcAAgK9CA4DQDqAgAcAAgK9CA4DQDqAgAAAA==.Gozhuntsurv:BAAANQABCgEIAQAAAA==.Gozrogueolaw:BAAANQADCgUIBQAAAA==.',
Gr='Grailliford:BAAANQAECgUIEwAAAA==.Grayfox:BAAANQAECgQIBAAAAA==.Greeneyes:BAAANQADCgYICQAAAA==.Grelle:BAAANQADCggIDAAAAA==.Grimlock:BAAANQADCggICAAAAA==.Grimthursday:BAAANQADCggJHQABNQAECggIGQATAPodAA==.Grip:BAAANQAECgcIDwAAAA==.Groxigar:BAAANQADCgQIBAAAAA==.Groxom:BAAANQADCgUIBQAAAA==.Grumpu:BAAANQADCgcIDwAAAA==.Grutok:BAAANQAECgUIBwAAAA==.',
Gu='Guzwar:BAAANQAECgYIDAAAAA==.',
Gw='Gwydeon:BAAANQADCgMIAwABNQAECgEJAQABAAAAAA==.',
Gy='Gyftable:BAAANQAECgUIEgAAAA==.Gyokuro:BAAANQABCgYIBwAAAA==.Gypsierose:BAAANQAECgQIDwAAAA==.',
['Gí']='Gíngervítis:BAAANQADCgEIAQAAAA==.',
['Gï']='Gïmli:BAAANQAECgEIAQAAAA==.',
['Gò']='Gòrilla:BAAANQADCgYICgAAAA==.',
Ha='Haahuna:BAAANQADCgIIAgAAAA==.Hairytoad:BAABNQAECoElAAIZAAYKewxyVQAwAQAZAAYKewxyVQAwAQAAAA==.Hakoda:BAAANQAECgIIAgAAAA==.Halleburn:BAAANQAECgQIBAAAAA==.Hardlightsgt:BAAANQADCgIIAgAAAA==.Harriet:BAAANQADCgMIAwAAAA==.Harubless:BAAANQAECgcIBwAAAA==.Haruchi:BAAANQAECgIIAgABNQAFFAcIFwAaALQfAA==.Harushear:BAACNQAFFIEXAAIaAAcKtB/HAACeAgAaAAcKtB/HAACeAgA1AAQKgSgAAhoACQpqJqIAAO0DABoACQpqJqIAAO0DAAAA.Harushorn:BAAANQAECgUIBwAAAA==.Haruvion:BAAANQAECgcJBwABNQAFFAcIFwAaALQfAA==.Harvester:BAAANQAECgYIEgAAAA==.Havocbringer:BAAANQAECgYIDwAAAA==.',
He='Headaxe:BAAANQAECgQIDAAAAA==.Healmemutt:BAAANQAECgQIBQAAAA==.Hearte:BAABNQAECoEkAAIeAAgKvx1LCADIAgAeAAgKvx1LCADIAgAAAA==.Hellweaver:BAAANQAECgYIBgAAAA==.Hermano:BAAANQAECgUIEQABNQAECggIIQAdAFMRAA==.Hermiscuous:BAABNQAECoEhAAIdAAgKUxGOHgDhAQAdAAgKUxGOHgDhAQAAAA==.Hermy:BAAANQAECgYICwABNQAECggIIQAdAFMRAA==.Herpys:BAAANQADCgYIBgAAAA==.Hexmachine:BAAANQAECgYIEAAAAA==.Hexstorm:BAAANQABCgYIBgAAAA==.',
Hi='Hinotori:BAAANQADCgYIFAAAAA==.Hinters:BAAANQAECgYIEAAAAA==.',
Ho='Hogglee:BAAANQADCgYIBgAAAA==.Holing:BAABNQAECoElAAICAAkKiiF9FgBHAwACAAkKiiF9FgBHAwAAAA==.Holybm:BAAANQADCgUICgAAAA==.Holyhealz:BAEANQAECgEJAgAAAA==.Holymama:BAAANQAECgYJBgAAAA==.Holymoly:BAAANQADCgEIAQAAAA==.Honeyduke:BAAANQAECgcIEQAAAA==.Hopenottodie:BAAANQAECgUIEQAAAA==.Hopes:BAAANQAECgYIEwAAAA==.',
Hr='Hrulgath:BAAANQADCgQIAwAAAA==.',
Hu='Humbler:BAAANQADCgcICAAAAA==.Huntum:BAAANQADCgUIBQAAAA==.Huntzha:BAAANQAECgUICgAAAA==.',
Hy='Hyndis:BAAANQAECgEIAgAAAA==.Hyorinmâru:BAAANQAECgUIEwAAAA==.',
['Hí']='Híppiechick:BAAANQAECgUIEAAAAA==.',
Ia='Iamoutofammo:BAAANQAECgUICAAAAA==.Ianix:BAAANQAECgcIEwAAAA==.',
Ic='Icanhelp:BAAANQADCgUJBQAAAA==.Iceni:BAABNQAECoEZAAICAAcKsB6nTABgAgACAAcKsB6nTABgAgAAAA==.Icepick:BAAANQADCggICAABNQADCggIHgABAAAAAA==.',
Id='Idíot:BAAANQAECgQIBgAAAA==.',
If='Ifelforu:BAAANQAECgcIEQAAAA==.',
Ih='Ihaslegs:BAAANQAECgEIAQAAAA==.Ihitstuf:BAAANQAECgIIAgAAAA==.',
Il='Ilidun:BAAANQABCgIJAQAAAA==.Illimoo:BAAANQAECgUICAAAAA==.Ilumminus:BAAANQADCgQIBwABNQADCggIHwABAAAAAA==.',
Im='Imoldgrèg:BAAANQADCgMIAwABNQAECggIHAAIAM4TAA==.',
In='Incineratus:BAABNQAECoEbAAIaAAgKxw/CIQABAgAaAAgKxw/CIQABAgAAAA==.Ineci:BAAANQADCgcIIAAAAA==.Infurrnal:BAABNQAECoEVAAIJAAgKah8CHgDbAgAJAAgKah8CHgDbAgAAAA==.Innerpeace:BAAANQAECgIIBgAAAA==.Inspirez:BAAANQADCgYIFgAAAA==.Instamissed:BAAANQADCgcIDAAAAA==.Intolerence:BAAANQADCggIFwAAAA==.',
Ip='Ipooptotems:BAAANQAECgIIAwAAAA==.',
Ir='Ironbeard:BAAANQADCgMIAwAAAA==.',
Is='Ishathon:BAAANQAECgEIAQAAAA==.Ishootstuff:BAABNQAECoEfAAIHAAgKNBvjQABfAgAHAAgKNBvjQABfAgAAAA==.Ismellyummy:BAAANQADCgMIAwAAAA==.',
It='Itsnotbatman:BAABNQAECoEcAAIHAAgKTROmTgA1AgAHAAgKTROmTgA1AgAAAA==.',
Iv='Ivanra:BAABNQAECoEfAAIfAAgK9yHiAQAQAwAfAAgK9yHiAQAQAwAAAA==.',
Iy='Iyna:BAAANQADCgUIBQAAAA==.',
Iz='Izlek:BAABNQAECoEXAAIdAAcKzQp/KgBlAQAdAAcKzQp/KgBlAQAAAA==.',
['Iì']='Iìe:BAABNQAECoEbAAMIAAcK2h/CLgBxAgAIAAcK2h/CLgBxAgACAAYKIhKcqgBZAQAAAA==.',
Ja='Jagermaster:BAAANQADCgYIDQAAAA==.Janeygirl:BAABNQAECoEVAAIHAAcKHAozgACrAQAHAAcKHAozgACrAQAAAA==.',
Jc='Jcx:BAAANQADCgcIDwABNQAECgIIBgABAAAAAA==.',
Je='Jeningo:BAAANQABCgcICAAAAA==.Jeningze:BAAANQAECgMIAwAAAA==.Jestiny:BAAANQAECgYIDQAAAA==.Jezebel:BAAANQADCgcIIAAAAA==.',
Jo='Johannuz:BAAANQAECgcIEAAAAA==.Johngoblikon:BAAANQAECgQICgAAAA==.Johnyf:BAAANQAECgIIBAAAAA==.Jonessy:BAAANQAECgUIBQABNQAECggJGAAlANQSAA==.Jonesy:BAABNQAECoEYAAIlAAgK1BIDDwC7AQAlAAgK1BIDDwC7AQAAAA==.Joneszy:BAAANQAFFAEIAQAAAA==.Jononononono:BAABNQAECoEjAAIGAAgK7RufCwCSAgAGAAgK7RufCwCSAgAAAA==.Jonz:BAABNQAECoEVAAICAAgKRBn/TgBYAgACAAgKRBn/TgBYAgAAAA==.Jorabelia:BAAANQAECgUICAAAAA==.Joshington:BAABNQAECoEfAAIHAAcKnySUHgDnAgAHAAcKnySUHgDnAgAAAA==.Jotuunnz:BAAANQADCgUIBQAAAA==.Jox:BAAANQADCgQIBAAAAA==.',
Ju='Juícyfruít:BAAANQABCgQIBwAAAA==.',
Ka='Kahlia:BAAANQADCgcIFgAAAA==.Kaiden:BAAANQADCgYICQAAAA==.Kalanix:BAAANQAECgQIDwAAAA==.Kaledor:BAAANQADCgEIAQAAAA==.Kalji:BAAANQADCgcIBwABNQAECgkJLAAGAGohAA==.Kamakaize:BAAANQAECgQIBQAAAA==.Kanatari:BAAANQAECgQIBgAAAA==.Kansch:BAAANQADCgMIAwABNQAECggIMgAdAGQcAA==.Karaleigh:BAABNQAECoEkAAIGAAgKuQtjGgCAAQAGAAgKuQtjGgCAAQAAAA==.Katallia:BAAANQAECgUICwAAAA==.Kateley:BAAANQAECgYIDAAAAA==.Kattadin:BAAANQAECgQIBQAAAA==.Kaybs:BAAANQAECgYIEAAAAA==.',
Ke='Keanoo:BAAANQAECgQICQAAAA==.Kekai:BAAANQABCgQICQAAAA==.Kelanthus:BAABNQAECoEZAAIaAAgKEwSzMQBxAQAaAAgKEwSzMQBxAQAAAA==.Kellalas:BAAANQADCgcIEgAAAA==.Kelvinator:BAAANQAECgIIAwAAAA==.Kernni:BAAANQAECgQICAAAAA==.Kes:BAAANQAFFAEIAQAAAA==.Kews:BAAANQADCgYICwAAAA==.',
Kh='Khades:BAAANQADCgMIAwAAAA==.',
Ki='Kiluu:BAAANQADCggICAAAAA==.Kirisera:BAAANQAECgIIAwAAAA==.Kirstii:BAAANQADCgYICQAAAA==.Kitkatzippy:BAAANQADCgQJBAAAAA==.Kittymik:BAEBNQAECoEZAAQdAAcKSSHeFwAyAgAdAAYKtyHeFwAyAgAZAAUK0hT4TgBSAQAXAAQKLRdCFgAiAQAAAA==.Kixa:BAAANQADCgQIBAABNQAECgcIGQAMAEcTAA==.',
Kl='Klawfel:BAAANQAECgEIAQAAAA==.',
Kn='Knöwledge:BAAANQADCgQIBAABNQAECgIIBAABAAAAAA==.',
Ko='Kohatu:BAAANQABCgIIAgAAAA==.Komoekomoe:BAAANQADCgUIAgAAAA==.Kormath:BAAANQAECgUICQAAAA==.Korrack:BAAANQAECgMIBgAAAA==.Korruptoor:BAAANQABCgQIBAAAAA==.Kotath:BAAANQADCgUIBwAAAA==.Kowbruh:BAAANQADCgYIDwAAAA==.Kower:BAAANQADCgQIBAAAAA==.',
Kr='Krianlan:BAAANQAECgEJAQABNQAECggIBgABAAAAAA==.',
Ku='Kuddy:BAABNQAECoEdAAIIAAkKwBVgMQBlAgAIAAkKwBVgMQBlAgAAAA==.Kumamizu:BAAANQAECgIIAwAAAA==.',
Kw='Kwee:BAAANQAECgcIBwAAAA==.Kwr:BAAANQAECgQIBQAAAA==.Kwyn:BAAANQADCgcIIAABNQAECgcIGQACAFENAA==.',
Ky='Kyeon:BAAANQADCgYICgAAAA==.Kyxa:BAAANQADCgYIBgABNQAECgcIGQAMAEcTAA==.',
['Kè']='Kèw:BAAANQAECgQIBAAAAA==.',
La='Lacronista:BAAANQAECgQIBwAAAA==.Lagavulin:BAABNQAECoEWAAIjAAcK5CAcBQCFAgAjAAcK5CAcBQCFAgABNQAFFAUIEQAZAN0XAA==.Lalatinaford:BAAANQAECgIIAgAAAA==.Lambdadelta:BAAANQADCgIIAgAAAA==.Landacious:BAAANQADCgUIBQAAAA==.Lanthendis:BAAANQADCgEJAQAAAA==.Lazerchìckèn:BAAANQADCgQIBAAAAA==.',
Le='Lebronjr:BAABNQAECoEeAAIWAAgKKhxhDQB9AgAWAAgKKhxhDQB9AgAAAA==.Leella:BAAANQAECgYIBgAAAA==.Leere:BAAANQADCgYIBgAAAA==.Leeshpal:BAAANQADCgYICAAAAA==.Legolash:BAABNQAECoEaAAIHAAcKphieXgAGAgAHAAcKphieXgAGAgAAAA==.Lemerix:BAAANQADCgUIBwAAAA==.Leniisha:BAAANQAECgUIBwAAAA==.Lewy:BAAANQAECggICwAAAA==.Lexicon:BAABNQAECoEWAAICAAcKKxmMaAAIAgACAAcKKxmMaAAIAgAAAA==.Lexxen:BAACNQAFFIEGAAIKAAQKxBeMDABoAQAKAAQKxBeMDABoAQA1AAQKgSgAAgoACQqzIaQGAHQDAAoACQqzIaQGAHQDAAAA.Leàfy:BAABNQAECoEcAAIdAAgK4xW3FwA0AgAdAAgK4xW3FwA0AgAAAA==.',
Li='Lightblade:BAABNQAECoEYAAIWAAYKqQ3qLQAUAQAWAAYKqQ3qLQAUAQAAAA==.Lilibewhan:BAAANQABCgEIAQAAAA==.Limonae:BAAANQAECgUIEwAAAA==.Lisellee:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.',
Ll='Lljunior:BAAANQABCgMIAwAAAA==.',
Lo='Locha:BAAANQAECgEIAgAAAA==.Lockfox:BAAANQADCgEIAQAAAA==.Lockstøck:BAAANQAECgUICAAAAA==.Longicorn:BAAANQADCgYIBgABNQAECgkJJgAIAH8fAA==.Lostváyne:BAAANQADCgYJBgAAAA==.Lovemylamb:BAAANQAECgEIAQABNQAFFAYIDwARAIoXAA==.',
Ls='Ls:BAABNQAECoEbAAIJAAkKLxQQPwBWAgAJAAkKLxQQPwBWAgAAAA==.',
Lu='Ludal:BAAANQADCgcIHwAAAA==.Luketism:BAAANQAECggIEgAAAA==.Lunarrage:BAAANQADCgUIBQAAAA==.Lunen:BAABNQAECoElAAIYAAkKXRxqBgDKAgAYAAkKXRxqBgDKAgAAAA==.Lusidity:BAAANQADCggIDgAAAA==.',
Ly='Lyraria:BAAANQADCgIIAgAAAA==.Lythorn:BAAANQAECgUIBwAAAA==.',
['Lè']='Lèpton:BAAANQAECgEIAwAAAA==.',
['Lé']='Léäf:BAABNQAECoEVAAMIAAcKHCARKQCOAgAIAAcKHCARKQCOAgACAAUKigeD3QDsAAAAAA==.',
['Lõ']='Lõx:BAABNQAECoEeAAMJAAgKYCEaFwD/AgAJAAgKYCEaFwD/AgASAAIK0iENEwDJAAAAAA==.',
Ma='Macloven:BAAANQAECgIJAgAAAA==.Madamgrey:BAABNQAECoEXAAIKAAgKvgf1ZACKAQAKAAgKvgf1ZACKAQAAAA==.Maebyfunke:BAAANQADCggICAAAAA==.Magestørm:BAABNQAECoEYAAIgAAkKgRWMYACQAgAgAAkKgRWMYACQAgAAAA==.Magicboi:BAAANQAECgMIAwAAAA==.Magicmagnus:BAAANQADCggJGAAAAA==.Magictacos:BAABNQAECoEhAAIcAAgKkB7WDwDDAgAcAAgKkB7WDwDDAgAAAA==.Magistrasza:BAABNQAECoElAAIgAAkKzwvRmAAKAgAgAAkKzwvRmAAKAgAAAA==.Majkusanagi:BAABNQAECoEXAAIGAAcK7wrIHwA6AQAGAAcK7wrIHwA6AQAAAA==.Makisig:BAAANQAECgcIEQAAAA==.Malfy:BAAANQAECgEIAQAAAA==.Malvnaire:BAAANQAECgYICwAAAA==.Mancrak:BAAANQADCgIIAgAAAA==.Maraach:BAAANQAECgcIEwAAAA==.Mariandor:BAAANQAECgMIBgAAAA==.Marlinn:BAABNQAECoEiAAIHAAkK1g4tTAA8AgAHAAkK1g4tTAA8AgABNQAFFAYIEwAUAEoYAA==.Marlos:BAAANQAECgUICQAAAA==.Marrmite:BAAANQADCgYIBgAAAA==.Marthaus:BAAANQADCgcJEgABNQAECgcIGQAGADYPAA==.Martmist:BAABNQAECoEZAAIGAAcKNg+AGgB+AQAGAAcKNg+AGgB+AQAAAA==.Massivepump:BAAANQAECgIIAgAAAA==.Mateo:BAAANQADCggIEgABNQAECgIIAgABAAAAAA==.Mathias:BAAANQAECgYIDAAAAA==.Mattiass:BAAANQAECgMIBgAAAA==.Mattrik:BAABNQAECoEZAAIMAAcKRxPsVwDLAQAMAAcKRxPsVwDLAQAAAA==.Maulyou:BAAANQAECgYIBgAAAA==.Maximilia:BAABNQAECoEiAAIaAAgKUiG3DgDdAgAaAAgKUiG3DgDdAgAAAA==.Maydayx:BAABNQAECoEgAAICAAgKDh8mLwDOAgACAAgKDh8mLwDOAgABNQAFFAUIEwANADgZAA==.',
Mc='Mcdoom:BAABNQAECoEbAAIJAAgKZRt4MgCEAgAJAAgKZRt4MgCEAgAAAA==.Mcduff:BAAANQADCggIGgAAAA==.',
Me='Meaningreen:BAAANQADCgcIEAAAAA==.Mekuntizichi:BAAANQADCgcICAAAAA==.Melazaelf:BAAANQADCgYIDQAAAA==.Melzas:BAAANQADCgIIAgAAAA==.Mermoo:BAAANQAECgIIAgAAAA==.Messages:BAAANQAECgQIBAAAAA==.',
Mi='Midknîght:BAAANQADCgIIAgABNQAECgMIBgABAAAAAA==.Midwa:BAACNQAFFIETAAICAAYK8yJfAQBVAgACAAYK8yJfAQBVAgA1AAQKgScAAgIACQrcJoECAOIDAAIACQrcJoECAOIDAAAA.Miishah:BAAANQAECgcIDQAAAA==.Minisaph:BAAANQADCgcIBwAAAA==.Missfun:BAAANQAECgYIEQAAAA==.Mistel:BAAANQAECgYICwAAAA==.Mistyfuzz:BAAANQAECgQIDQAAAA==.Mithrendir:BAAANQADCggIHwAAAA==.',
Mj='Mjolnirr:BAAANQADCgYIBgAAAA==.',
Mo='Mogimp:BAAANQADCgQIBwABNQAECggIFQADAJsYAA==.Moguette:BAAANQAECgcIEwABNQAECgcIEwABAAAAAA==.Moistroll:BAAANQAECgEIAQABNQAECggIGwAJAGUbAA==.Molith:BAAANQABCgYICAAAAA==.Monkkha:BAAANQADCgYICAAAAA==.Montecarlo:BAABNQAECoEeAAQQAAgKaRgbGwBQAgAQAAgKaRgbGwBQAgAmAAIK/A8FPgB4AAAnAAIKkQcnFQBgAAAAAA==.Moonfish:BAAANQADCgEIAQAAAA==.Moonhill:BAAANQAECgEIAQABNQAFFAUIDAAQAGQRAA==.Moonrain:BAAANQADCgIIAgAAAA==.Moordenaar:BAABNQAECoEaAAMEAAcKYRTpRACfAQAEAAcKYRTpRACfAQADAAYK+gxXQgBAAQAAAA==.Moosy:BAAANQAECgQIBwAAAA==.Morala:BAAANQADCgYIBgAAAA==.Morathia:BAAANQADCgIIAgAAAA==.Morgainne:BAAANQADCgEIAQAAAA==.Morphia:BAAANQADCgYIBgAAAA==.Morsoc:BAAANQAECgYIDAAAAA==.Mortarius:BAAANQAECgIIBAAAAA==.Movicol:BAAANQAECgUIBwAAAA==.Mozire:BAAANQAECgMIBgAAAA==.Moñklee:BAAANQADCgUIBgABNQADCgcIDQABAAAAAA==.',
Ms='Msheal:BAAANQADCgYIBgAAAA==.',
Mt='Mth:BAAANQAECggIEAAAAA==.Mtnaan:BAAANQAECgIIAgAAAA==.',
Mu='Muerteamigo:BAAANQADCgMIAQAAAA==.Murz:BAAANQADCggIEQAAAA==.Musch:BAAANQAECgQIBAABNQAECggIMgAdAGQcAA==.Musde:BAABNQAECoEyAAMdAAgKZBybEQCFAgAdAAgKZBybEQCFAgAZAAEKIgV5oAAfAAAAAA==.Musterick:BAAANQAECgIIBQAAAA==.Muther:BAAANQAECgYIEwAAAA==.',
My='Myctlan:BAAANQAECgEIAQAAAA==.Mylie:BAAANQABCggICgAAAA==.Myrddn:BAAANQAECgQIBgAAAA==.Myrdi:BAAANQADCgYICgABNQAECgUICQABAAAAAA==.Myrsham:BAAANQAECgUICQAAAA==.Mytearsheal:BAAANQAECgUIEQAAAA==.Mythbrediir:BAABNQAECoEYAAIVAAcKhBWyDwDQAQAVAAcKhBWyDwDQAQAAAA==.',
['Mü']='Müläflaga:BAAANQAECgQIBAAAAA==.',
Na='Naadina:BAAANQADCgcIHAAAAA==.Nadazarter:BAAANQAECgQICgAAAA==.Naggo:BAAANQADCgYIBwAAAA==.Naloiiha:BAAANQADCgUIBQAAAA==.Nalph:BAAANQAECgYICwAAAA==.Narassii:BAAANQADCgMIAwAAAA==.Narmaak:BAAANQADCgQIBAAAAA==.Nathun:BAAANQAECgIIBAAAAA==.Navillas:BAAANQAECgUIEwAAAA==.Nayha:BAAANQAECgEIAQAAAA==.',
Ne='Nebulachimi:BAABNQAECoE8AAIZAAkKOworOADfAQAZAAkKOworOADfAQAAAA==.Nebulahikari:BAAANQADCgYJBgAAAA==.Nebularyu:BAAANQAECgQICAAAAA==.Nedimus:BAABNQAECoEgAAICAAcKeBOlggC9AQACAAcKeBOlggC9AQABNQAECgEIAgABAAAAAA==.Nekhrimah:BAABNQAECoEXAAMoAAgKlQxFAwCBAQAgAAgKmwoAtQDMAQAoAAcK8glFAwCBAQAAAA==.Neoaerith:BAABNQAECoEXAAQKAAgKNAedZQCHAQAKAAgKNAedZQCHAQApAAEKtwCcKAAZAAAcAAEKXgHdcwAYAAAAAA==.Nerii:BAAANQAECgIIAwAAAA==.Nerpthas:BAAANQAECgQICAAAAA==.Neverlinkx:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Ni='Niagarafall:BAAANQADCgIIAgAAAA==.Nidalàp:BAAANQADCgcIBwAAAA==.Nieriality:BAABNQAECoEaAAIcAAYKuRGxLABuAQAcAAYKuRGxLABuAQAAAA==.Nightshana:BAAANQADCgEIAQAAAA==.Nilin:BAAANQAECgcIEQAAAA==.Nina:BAAANQAECggIDAABNQAECgEIAgABAAAAAA==.Nippen:BAAANQADCgIIAwAAAA==.Nisulus:BAAANQADCggIIAAAAA==.Niteañgel:BAAANQAECgIIBAAAAA==.Niç:BAAANQAECgYIEAAAAA==.',
No='Noala:BAAANQADCgQIBAAAAA==.Noctuana:BAAANQADCgYIGgABNQAECgUICgABAAAAAA==.Nojruh:BAAANQADCgQICAAAAA==.North:BAABNQAECoEnAAIYAAkKpROrDAAkAgAYAAkKpROrDAAkAgAAAA==.Notbeezy:BAAANQAECgcIEgAAAA==.Nothappy:BAAANQADCgUIBQAAAA==.Nox:BAACNQAFFIEFAAIcAAMKOw7OCQDwAAAcAAMKOw7OCQDwAAA1AAQKgRkAAhwACQq5G4QRAKcCABwACQq5G4QRAKcCAAAA.',
Nu='Numbnut:BAAANQADCgQIBAAAAA==.Numbskull:BAAANQADCgYICgAAAA==.Numnutts:BAABNQAECoEcAAIXAAgKpQeYEQB1AQAXAAgKpQeYEQB1AQAAAA==.Nutelle:BAAANQADCgYIBwAAAA==.',
['Nè']='Nèrp:BAABNQAECoEcAAMIAAgKYRNWRgALAgAIAAgKYRNWRgALAgACAAEKGhBVQwE5AAAAAA==.',
['Nú']='Númenórean:BAABNQAECoEcAAIHAAcKjwlkiwCQAQAHAAcKjwlkiwCQAQAAAA==.',
['Nü']='Nüts:BAAANQAECgYIEwAAAA==.',
Oa='Oathorr:BAAANQADCgQIBAAAAA==.',
Ob='Obadiah:BAAANQADCgcIEwAAAA==.Obsidianshot:BAAANQADCgcIEAAAAA==.',
Oc='Oceansiron:BAAANQADCgQIBAAAAA==.Ochayethenoo:BAAANQADCgcIBwAAAA==.',
Od='Oddmoos:BAAANQADCgEIAQAAAA==.',
Og='Ogriv:BAAANQADCggIDgAAAA==.',
Oi='Oii:BAAANQAECgEIAQAAAA==.',
Ol='Olunaija:BAAANQAECgUICQAAAA==.',
Om='Omm:BAEANQAECgQIBgAAAA==.Omninan:BAAANQABCgEIAQAAAA==.',
On='Onlyclaws:BAAANQAECggICgAAAA==.',
Oo='Oos:BAAANQADCgQIBAAAAA==.',
Or='Oroqen:BAAANQAECgUICwAAAA==.',
Ou='Ouchiheal:BAABNQAECoEZAAITAAcKoRLgZQCEAQATAAcKoRLgZQCEAQAAAA==.',
Ov='Overhealer:BAABNQAECoEgAAMKAAkKPxeVJwCQAgAKAAkKPxeVJwCQAgApAAIKZAMjHABRAAAAAA==.',
['Oà']='Oàthor:BAAANQAECgMIBQAAAA==.',
Pa='Pachi:BAAANQAECgEIAgAAAA==.Paladinmilan:BAAANQADCgIIAgAAAA==.Paladipuss:BAAANQADCggIEgAAAA==.Paladumb:BAACNQAFFIERAAICAAUKHRF7BgCRAQACAAUKHRF7BgCRAQA1AAQKgUwAAwIACQrzH2geABwDAAIACQrzH2geABwDABYAAQoQCr9fACQAAAAA.Palatism:BAAANQAECgYIDgAAAA==.Pallywings:BAAANQAECgcIDQAAAA==.Panchovy:BAACNQAFFIETAAIUAAYKShh3AgALAgAUAAYKShh3AgALAgA1AAQKgSUAAhQACQpKIuUIABwDABQACQpKIuUIABwDAAAA.Parrexion:BAAANQADCgEIAQAAAA==.',
Pe='Peculiar:BAAANQAECgUICQAAAA==.Pegor:BAAANQAECgMIAwABNQAECgQIBgABAAAAAA==.Pegz:BAAANQADCgYIBgAAAA==.Pegzpaladin:BAAANQADCgcIBwAAAA==.Peps:BAAANQADCggICAAAAA==.Peseshet:BAAANQAECgQICgAAAA==.',
Ph='Phantom:BAAANQADCgQIBQAAAA==.Phazonicide:BAAANQAECgIIAwAAAA==.Phlaea:BAAANQAECgYIEwAAAA==.',
Pi='Pieata:BAAANQADCggIFAAAAA==.',
Pl='Plazistank:BAAANQADCggICAABNQAECgYIDwABAAAAAA==.Plazzmma:BAAANQADCgMIBgABNQAECgYIDwABAAAAAA==.',
Po='Pogo:BAAANQAECgQICQABNQAECgYIDgABAAAAAA==.Poisoning:BAAANQAECgUIBQAAAA==.Poknat:BAAANQADCggICAAAAA==.Polkievoke:BAAANQADCgUJBQAAAA==.Pomdoes:BAAANQADCgMIAwAAAA==.Poppylotus:BAAANQADCggJKgAAAA==.Poppyrift:BAAANQAECgIIBAAAAA==.Postee:BAAANQADCggIHgAAAA==.Powerrager:BAAANQAECgEIAQAAAA==.',
Pr='Precioùs:BAABNQAECoEZAAITAAgK+h1cIACyAgATAAgK+h1cIACyAgAAAA==.Prettyhectic:BAABNQAECoEdAAITAAcKZyAPOwArAgATAAcKZyAPOwArAgAAAA==.Priincebun:BAAANQAECggICAAAAA==.Primate:BAAANQAECgMIAwAAAA==.Prinsesdonut:BAABNQAECoEZAAIgAAcKCxK7swDPAQAgAAcKCxK7swDPAQAAAA==.Projecjx:BAAANQADCgYICgAAAA==.Protagonist:BAACNQAFFIENAAINAAQKICNzBQCgAQANAAQKICNzBQCgAQA1AAQKgSMAAw0ACQo7JPILACIDAA0ACAokJPILACIDABoABQpVFEg6ACMBAAE1AAUUBwgYAAwAOyMA.Proz:BAAANQADCgcIDQAAAA==.Prozium:BAABNQAECoEZAAIDAAgKTyL3DAD7AgADAAgKTyL3DAD7AgABNQADCgcIDQABAAAAAA==.',
Pu='Purifythis:BAAANQADCgMIAwAAAA==.Purson:BAAANQAECgEIAQAAAA==.',
Py='Pyrotic:BAAANQADCgYICAAAAA==.Pyschotic:BAAANQADCggIDAAAAA==.',
['Pä']='Pänya:BAAANQADCgcIDAAAAA==.',
['Pê']='Pêpsï:BAAANQABCgEIAQAAAA==.',
Qu='Quag:BAAANQADCgYJCAAAAA==.Quinny:BAABNQAECoEZAAMCAAcKUQ1tmwB+AQACAAcKUQ1tmwB+AQAIAAMKuAIQ1QBwAAAAAA==.Quintar:BAABNQAECoEsAAIKAAkK4hxcGQDgAgAKAAkK4hxcGQDgAgAAAA==.',
Ra='Raagnar:BAAANQAECgMIAwAAAA==.Rabbage:BAABNQAECoEXAAMQAAgKIiHkDwDAAgAQAAcKEyPkDwDAAgAmAAEKkRNpQwBDAAAAAA==.Radaghast:BAAANQADCgUIBQABNQADCggIHwABAAAAAA==.Raeka:BAABNQAECoEYAAMUAAcKQyW7DADcAgAUAAcKQyW7DADcAgAGAAEKhwyqPwAuAAAAAA==.Raenda:BAAANQADCgYICgAAAA==.Ragarlem:BAAANQAECgQIBAAAAA==.Ragefright:BAAANQAECgYIBgABNQAFFAMIBQAcADsOAA==.Rageie:BAAANQAECgUICQAAAA==.Rageieboop:BAAANQAECgMIBwAAAA==.Ragemore:BAABNQAECoEZAAILAAgKWhHwJADeAQALAAgKWhHwJADeAQAAAA==.Raggorg:BAAANQADCgEIAQABNQAECgYIBwABAAAAAA==.Rahvine:BAAANQADCggIHAAAAA==.Raiteq:BAABNQAECoEdAAMoAAgKNyQBAQCzAgAgAAgKsCK6LwASAwAoAAcKkSEBAQCzAgAAAA==.Raitev:BAAANQAECgMIAwABNQAECggIHQAoADckAA==.Ramirezz:BAAANQADCggJCAABNQAECgMIBgABAAAAAA==.Ranmaoo:BAAANQAECggICgABNQAECgEIAgABAAAAAA==.Raputami:BAABNQAECoEhAAMMAAgKehIrRgAPAgAMAAgKehIrRgAPAgATAAIKIwiS2wBTAAAAAA==.Rastoons:BAAANQAECgQIBgAAAA==.Rawlôck:BAABNQAECoElAAMJAAkKoRu9IQDKAgAJAAkKoRu9IQDKAgARAAMKsxCLPwCvAAAAAA==.Raxor:BAAANQAECgMIBQAAAA==.Raya:BAAANQAECgYIEAAAAA==.',
Rd='Rde:BAAANQAECgYICwAAAA==.',
Re='Redfoxxy:BAAANQADCgUIAgAAAA==.Redoctobah:BAAANQAECgIIBAAAAA==.Regret:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Reignrott:BAAANQAECgUIEwAAAA==.Reika:BAAANQAECgQIBAAAAA==.Replaceable:BAAANQABCgIIAwABNQAECggICAABAAAAAA==.Reptizzle:BAAANQADCgQIBAAAAA==.Restorer:BAAANQAECgEIBAAAAA==.Retalica:BAAANQAECgUICQAAAA==.Retrishi:BAABNQAECoEdAAMeAAgK0BsYDgBKAgAeAAcK2hoYDgBKAgAMAAUKEBJHiAA4AQAAAA==.Retxbladés:BAAANQADCgcIEAAAAA==.Revelstat:BAAANQADCgQIBgAAAA==.Reverb:BAAANQAECgcIEAAAAA==.Rexonon:BAAANQAECgQIBAABNQAECggIGgAMAJcUAA==.Rexsham:BAABNQAECoEaAAMMAAgKlxQJRwAMAgAMAAgKlxQJRwAMAgATAAEKliXc0gBoAAAAAA==.Rexyclog:BAAANQAECgQIBgAAAA==.Reyku:BAAANQAECgYIDQAAAA==.Reynasong:BAAANQADCgYIDAAAAA==.',
Rh='Rhydon:BAAANQAECgEIAQAAAA==.',
Ri='Ricard:BAAANQAECgIIAgAAAA==.Rickettsia:BAABNQAECoEaAAMRAAcKyRHKLAAFAQARAAQKRBTKLAAFAQAJAAQK0g3hvwDpAAAAAA==.Rig:BAAANQADCggJCAABNQAECggIHAAPAE4bAA==.Rildis:BAAANQAECgQICAABNQAECgUIEwABAAAAAA==.Rippen:BAAANQADCgYIDQAAAA==.Ritasu:BAAANQAECgMIBAAAAA==.',
Rl='Rlain:BAAANQADCgQIBAABNQAECgYIDgABAAAAAA==.',
Ro='Robyngdfelow:BAABNQAECoEbAAIQAAgKtB6HDQDfAgAQAAgKtB6HDQDfAgAAAA==.Rohovart:BAAANQAECgIIBAAAAA==.Rollingrick:BAABNQAECoEdAAMpAAgKEhgFBgD9AQApAAYKHB0FBgD9AQAKAAUKLArWhgAPAQAAAA==.',
Rp='Rpro:BAAANQADCgEIAQAAAA==.',
Rr='Rroach:BAABNQAECoEaAAIWAAcKjRbEHgCVAQAWAAcKjRbEHgCVAQAAAA==.',
Ru='Runaway:BAAANQAECgIIAgABNQAFFAUIDAAQAGQRAA==.Rustycrack:BAAANQAECgUIDAAAAA==.Ruul:BAAANQAECgEIAQAAAA==.',
Ry='Ryana:BAAANQABCgMIAwAAAA==.Ryilla:BAAANQAECgQICQAAAA==.Rynoe:BAAANQAECgUICQAAAA==.Ryri:BAAANQADCgQIBAAAAA==.Ryujinx:BAAANQADCgEIAQAAAA==.Ryukendo:BAAANQAECgMIBAAAAA==.',
['Rá']='Ráric:BAAANQAECgIIAgAAAA==.',
['Ré']='Rémymartin:BAAANQADCggJDgABNQADCggIHgABAAAAAA==.',
Sa='Saata:BAAANQAECgEIAgAAAA==.Sableman:BAAANQADCgYIEQAAAA==.Saccromycaes:BAAANQAECgcIDAAAAA==.Saclem:BAAANQAECgMIBAAAAA==.Saha:BAAANQAECgQICAAAAA==.Saintayah:BAAANQAECgYIEgAAAA==.Salokin:BAAANQAECgEIAQABNQAFFAYIEAAFAC8cAA==.Salorellin:BAABNQAECoElAAMaAAkKdyGdDwDSAgAaAAgKDyGdDwDSAgANAAQKLiEVOQCDAQAAAA==.Sandrèena:BAAANQAECgYIDgAAAA==.Sanity:BAAANQAECgEJAQAAAA==.Sarakatawen:BAAANQAECgIIBAAAAA==.Sarumash:BAAANQAECgMIAwAAAA==.Satanah:BAAANQAECgMIAwAAAA==.Satomi:BAAANQAECgUICAAAAA==.Satre:BAABNQAECoEdAAIiAAgKghlFBQBPAgAiAAgKghlFBQBPAgAAAA==.',
Se='Seculoe:BAAANQAECgYIEgAAAA==.Seedypete:BAAANQADCgcIDQAAAA==.Seemébloody:BAAANQAECgQIBQAAAA==.Seldarine:BAAANQAECgYICwAAAA==.Selten:BAAANQAECgUICQAAAA==.Selvaggio:BAAANQABCgQIBgAAAA==.Sendel:BAAANQADCgQIBAAAAA==.Senele:BAAANQAECgEIAgAAAA==.Senescence:BAACNQAFFIEPAAQRAAYKihd9BADIAAAJAAMKJxaHEQACAQARAAIK/xx9BADIAAASAAEKyxAhCgBKAAA1AAQKgSsABAkACQr5JPwhAMgCAAkABwqFJPwhAMgCABEABQobIJoSAM8BABIAAwq8IkEPABIBAAAA.Serperior:BAAANQAECgQIBAABNQAECgEIAgABAAAAAA==.Sesshomar:BAAANQADCgEIAQAAAA==.',
Sh='Sh:BAAANQAECggIEwAAAA==.Shadopaw:BAABNQAECoEdAAIZAAYKFRYIQgCeAQAZAAYKFRYIQgCeAQAAAA==.Shadowrae:BAAANQAECgMIBgABNQAECgUICAABAAAAAA==.Shadowsyy:BAAANQADCgcIBwAAAA==.Shadyllama:BAABNQAECoEZAAIKAAcKmw6TaQB4AQAKAAcKmw6TaQB4AQAAAA==.Shamkat:BAAANQAECgQIBAAAAA==.Shammah:BAABNQAECoEcAAIWAAgKmxQFGgDLAQAWAAgKmxQFGgDLAQAAAA==.Shammbulance:BAAANQADCgIJAgAAAA==.Shamuoo:BAAANQADCgQIBAAAAA==.Sharlo:BAAANQADCgcIFQAAAA==.Sharnie:BAABNQAECoEZAAIFAAcK9BGtQwCpAQAFAAcK9BGtQwCpAQAAAA==.Shear:BAAANQAECggIBwAAAA==.Shellatrix:BAABNQAECoEdAAIlAAgKJRlcCwAVAgAlAAgKJRlcCwAVAgAAAA==.Shepp:BAAANQAECgYIEAAAAA==.Shommy:BAAANQADCggICAAAAA==.Shootette:BAAANQAECgYIEgAAAA==.Shutenz:BAAANQAECgQIBAABNQAECggIJQAFAIQkAA==.Shãmtastic:BAAANQADCgYIBgAAAA==.',
Si='Silandryn:BAAANQAECgIJAgAAAA==.Sinderela:BAABNQAECoEXAAICAAgKQwZ4qQBcAQACAAgKQwZ4qQBcAQAAAA==.Sinisterwing:BAABNQAECoEWAAImAAcKTQ5THADLAQAmAAcKTQ5THADLAQAAAA==.Siolani:BAAANQADCgUICAAAAA==.',
Sk='Skeptikk:BAABNQAECoElAAMMAAkKlhvVNwBRAgAMAAgKSxrVNwBRAgATAAEKCgSk6gA2AAAAAA==.Skinnery:BAAANQAECgIIBAAAAA==.Skrull:BAABNQAECoEcAAQhAAgKaQgFHQA+AQAhAAcK4wcFHQA+AQAkAAYK3Qb8KAAbAQAiAAQKtgdPEgC1AAAAAA==.',
Sl='Slateray:BAAANQAECgcJDwAAAA==.Slipnslide:BAAANQAECgUIBQAAAA==.Slyr:BAAANQAECgUIBQAAAA==.',
Sm='Smaky:BAAANQAECgUICgAAAA==.Smaque:BAABNQAECoErAAIPAAgKRh8oMwDCAgAPAAgKRh8oMwDCAgAAAA==.Smegging:BAAANQADCgYICQAAAA==.',
Sn='Snaare:BAAANQADCgYJDAAAAA==.',
So='Solcaris:BAAANQAECgMIBgAAAA==.Sorie:BAAANQAECgQIBQAAAA==.Soulwishper:BAAANQAECgUICQAAAA==.Sourstraps:BAAANQADCgMIAwAAAA==.Soùlstealer:BAAANQADCgQIBAAAAA==.',
Sp='Sparkdead:BAAANQADCgQIBwAAAA==.Spazzimitazz:BAAANQADCgIIAgAAAA==.Spazzy:BAABNQAECoEeAAITAAcKXiLSJwCIAgATAAcKXiLSJwCIAgAAAA==.Spenna:BAAANQAECgUICAAAAA==.Spudacus:BAAANQAECgYIEwAAAA==.Spuddk:BAABNQAECoEiAAIEAAkK6RUsJwBOAgAEAAkK6RUsJwBOAgAAAA==.Spudsham:BAAANQAECgUJCAABNQAECgkJIgAEAOkVAA==.',
St='Stabforcash:BAACNQAFFIEXAAMQAAcK3CMkAAD/AgAQAAcK3CMkAAD/AgAmAAEKGgqlDgBUAAA1AAQKgRkAAxAACQrZI9oEAGEDABAACQrZI9oEAGEDACYABwoUBv0lAGoBAAAA.Starleaf:BAAANQADCgQIBgAAAA==.Stellarluse:BAAANQAECgQIBgAAAA==.Stickler:BAABNQAECoEYAAIFAAgKCCTiCgA/AwAFAAgKCCTiCgA/AwAAAA==.Stonkerella:BAAANQADCgIIAgAAAA==.Stonque:BAAANQADCgcIBwABNQAECggIKwAPAEYfAA==.Stormchief:BAAANQAECgMIAwAAAA==.Stormgoat:BAAANQADCgYIBwAAAA==.Stormie:BAAANQAECgQIBwAAAA==.Stormrider:BAABNQAECoEcAAIMAAgKOxzkNABfAgAMAAgKOxzkNABfAgAAAA==.Streuth:BAABNQAECoElAAIVAAkKLCXZAADBAwAVAAkKLCXZAADBAwAAAA==.Strummer:BAACNQAFFIERAAIHAAUKLSNYAgACAgAHAAUKLSNYAgACAgA1AAQKgUoAAwcACQpJJBAFAKQDAAcACQpJJBAFAKQDAAsAAgpTFU9bAGkAAAAA.Stubbyholder:BAAANQADCggICAAAAA==.',
Su='Subaru:BAAANQAECgIIAgABNQAECgYICgABAAAAAA==.Subaruu:BAAANQAECgYICgAAAA==.Subsiding:BAAANQAECgMIAwAAAA==.Subtera:BAAANQADCgcIBwAAAA==.Supagroova:BAAANQADCgMJAwAAAA==.Supernothing:BAAANQAECgUIDAAAAA==.Superswede:BAAANQAECgYIDgAAAA==.Susurrus:BAAANQADCgUIBQAAAA==.',
Sw='Switchdoctor:BAAANQADCggIEwABNQADCggIHgABAAAAAA==.Sworf:BAABNQAECoEuAAIMAAkK5xorIgDJAgAMAAkK5xorIgDJAgAAAA==.',
Sy='Syaarhunter:BAAANQAECgQIBAAAAA==.Syaarknight:BAAANQADCgYJBwAAAA==.Syaarpally:BAAANQAECgMIAwAAAA==.Syazar:BAAANQAECgYIDAAAAA==.Sylanthia:BAAANQAECgYIEgAAAA==.Sylblades:BAAANQAECgUIBQAAAA==.Sylwizard:BAAANQABCgEIAQAAAA==.',
['Só']='Sóg:BAAANQAECgEIAgABNQAECggIIQAJAM8jAA==.',
['Sø']='Søbz:BAAANQADCggJIwAAAA==.Søg:BAABNQAECoEhAAQJAAgKzyPbTgAgAgAJAAYKEyHbTgAgAgASAAMKAyWqDABDAQARAAEKOSXAVABtAAAAAA==.',
['Sù']='Sùnjin:BAAANQAECgMIAwABNQAECggIFQADAJsYAA==.',
Ta='Tabknight:BAABNQAECoEkAAIFAAgKDBYdLQAmAgAFAAgKDBYdLQAmAgAAAA==.Taelron:BAAANQAECgIIAgAAAA==.Taelstard:BAAANQAECgQIDwAAAA==.Taichook:BAAANQAECgEIAQABNQAECggINQACAO4iAA==.Taithos:BAABNQAECoE1AAICAAgK7iIIJgD3AgACAAgK7iIIJgD3AgAAAA==.Taizen:BAAANQAECgcIBgAAAA==.Talanardonis:BAAANQADCgYIBgAAAA==.Tanktough:BAAANQAECgUIBQAAAA==.Tarago:BAABNQAECoEoAAIEAAgKXCMTEQD+AgAEAAgKXCMTEQD+AgAAAA==.Taranisis:BAAANQAECgYIDwAAAA==.Targetone:BAABNQAECoEUAAIHAAcKEhcMWAAZAgAHAAcKEhcMWAAZAgAAAA==.Tasall:BAAANQAECgQIBAAAAA==.Tauntflaunt:BAABNQAECoEgAAMEAAkKXCHwDAAqAwAEAAkKXCHwDAAqAwAFAAEKOgNxxwAKAAAAAA==.Tayy:BAAANQADCgEIAQAAAA==.',
Te='Tech:BAAANQAECgUIEwAAAA==.Tempø:BAAANQAECgEJAgAAAA==.Tenkris:BAAANQAECgMIBgAAAA==.Tenleigh:BAAANQAECgMIBgAAAA==.Tenzero:BAAANQADCgYJBgAAAA==.Terroria:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Terrorizor:BAAANQAECgUIEwAAAA==.',
Th='Thalía:BAAANQADCggIHwAAAA==.Thargroar:BAABNQAECoEiAAIXAAgKxiMSAwBCAwAXAAgKxiMSAwBCAwAAAA==.Thazix:BAAANQADCgYIDQABNQAECggIHAAFAMEdAA==.Theboysavior:BAAANQAECgEIAQAAAA==.Thefluffyman:BAAANQAECgcIEAAAAA==.Themetzi:BAAANQADCgUIBQAAAA==.Thiss:BAABNQAECoEcAAIHAAgKOR/ZJADKAgAHAAgKOR/ZJADKAgAAAA==.Thordak:BAAANQAECgUICwAAAA==.Thoridian:BAAANQADCgQIBwAAAA==.Thunderfella:BAAANQADCggICAAAAA==.Thurlarra:BAAANQADCgEIAQAAAA==.Thùnder:BAAANQADCgYICQAAAA==.',
Ti='Tidewalker:BAAANQADCgYIEgAAAA==.Tigolbits:BAAANQADCgUIBQAAAA==.Tiroo:BAAANQADCgMIAwABNQAECgcIGgAIAAklAA==.Titdor:BAAANQADCgIIAgAAAA==.',
To='Tobythemonk:BAABNQAECoEdAAIGAAgKARvyDAB1AgAGAAgKARvyDAB1AgAAAA==.Toehacker:BAABNQAECoEaAAIPAAgKtx/8OQCnAgAPAAgKtx/8OQCnAgAAAA==.Toliman:BAAANQADCgYIDQAAAA==.Tolkarkiller:BAAANQAECgYIDwAAAA==.Tomarr:BAEBNQAECoElAAITAAkKPApzWwCoAQATAAkKPApzWwCoAQABNQAECgUIDAABAAAAAA==.Tomarv:BAEANQADCgYIBwABNQAECgUIDAABAAAAAA==.Tonsham:BAAANQADCgYIBwAAAA==.Totemspanker:BAAANQAECgIIAgAAAA==.Totoki:BAAANQADCggICAAAAA==.Touchitonce:BAAANQAECgQIEAAAAA==.Toxic:BAAANQADCgIIAgAAAA==.Toóz:BAABNQAECoEgAAMMAAgKdhVoQQAkAgAMAAgKdhVoQQAkAgATAAcKXwSFiwAVAQAAAA==.',
Tr='Trailblayxur:BAAANQAECgYIEQAAAA==.Traser:BAAANQADCgYJDAAAAA==.Trickyknight:BAABNQAECoFJAAMEAAkKwiJXBACYAwAEAAkKwiJXBACYAwAFAAgKBx5iGwChAgAAAA==.Trickymage:BAAANQADCgUIBQAAAA==.Trinityheals:BAAANQAECgEIAQAAAA==.',
Tu='Tuckerius:BAAANQADCgYIBwAAAA==.Turahk:BAAANQAECgYIEQAAAA==.Turtlesoup:BAABNQAECoEZAAIHAAcKyQ9BcQDTAQAHAAcKyQ9BcQDTAQAAAA==.',
Tw='Twofoottall:BAAANQAECgEJAQAAAA==.',
Ty='Tylendorian:BAAANQABCgEIAQAAAA==.Tylerolothus:BAAANQAECgYIBwAAAA==.Tynndera:BAAANQAECgUICgAAAA==.Tyrawr:BAAANQAECgQIBAABNQAFFAYIEQAFAHYYAA==.Tyth:BAABNQAECoEZAAMSAAcKTxlOBQAsAgASAAcKTxlOBQAsAgAJAAEKywgtEAEtAAAAAA==.',
['Tí']='Tím:BAABNQAECoEWAAICAAcKqh97SwBkAgACAAcKqh97SwBkAgAAAA==.',
Ud='Udderlyfuzzy:BAAANQAECgQICgABNQAECggIGwAJAGUbAA==.',
Un='Unclefister:BAAANQAECggIBwAAAA==.Unclegrandpa:BAAANQADCgQIBgAAAA==.',
Ur='Uranbraug:BAAANQABCgIIAgAAAA==.Urnot:BAAANQAECgQIBAABNQAFFAMIBAABAAAAAA==.Urôt:BAAANQAFFAMIBAAAAA==.',
Uw='Uwusue:BAAANQAECgYIBwAAAA==.',
Va='Vaeline:BAAANQABCgUIBgAAAA==.Valac:BAACNQAFFIERAAIFAAYKdhjnBADfAQAFAAYKdhjnBADfAQA1AAQKgScAAgUACQrfIuYIAFcDAAUACQrfIuYIAFcDAAAA.Valkyrie:BAAANQAECgcIEgAAAA==.Valothos:BAABNQAECoEmAAIIAAcKLhVCTgDtAQAIAAcKLhVCTgDtAQAAAA==.Valtiell:BAABNQAECoElAAImAAkKfh61BQAYAwAmAAkKfh61BQAYAwAAAA==.Valuri:BAAANQAECgYIEwAAAA==.Varainne:BAABNQAECoEZAAMRAAgKVRbwKwAKAQAJAAUKwRFfkABYAQARAAMK9h3wKwAKAQAAAA==.',
Ve='Vegimitê:BAAANQADCgUJBQAAAA==.Vegymite:BAAANQADCgEIAQAAAA==.Velgath:BAABNQAECoEwAAImAAkKShx8CADaAgAmAAkKShx8CADaAgAAAA==.Velisea:BAAANQAECgEIAQABNQAECgYIDwABAAAAAA==.Velkhana:BAAANQAECgcIEQAAAA==.Velmorra:BAAANQAECgUIDQAAAA==.Veratis:BAAANQAECgEJAQAAAA==.Vesperatears:BAAANQADCgMIAwAAAA==.',
Vi='Victoria:BAAANQAECgUIEAAAAA==.Vinee:BAAANQAECgQIBgAAAA==.Vioneva:BAABNQAECoEbAAIHAAcKLxAGcQDUAQAHAAcKLxAGcQDUAQAAAA==.Viscelock:BAABNQAECoEbAAIbAAgKow5LCgDZAQAbAAgKow5LCgDZAQAAAA==.Vivyregosa:BAACNQAFFIERAAIgAAYKoQ5TCgDlAQAgAAYKoQ5TCgDlAQA1AAQKgScAAiAACQr7HTNGANQCACAACQr7HTNGANQCAAAA.',
Vo='Volda:BAAANQAECgEIAQAAAA==.',
Vx='Vxi:BAACNQAFFIESAAIQAAYKyxwZAQBEAgAQAAYKyxwZAQBEAgA1AAQKgRkAAhAACQoKIXEMAOwCABAACQoKIXEMAOwCAAAA.',
Wa='Wagglehoof:BAAANQADCgcIDAAAAA==.Wain:BAAANQAECgEIAgAAAA==.Wakantanka:BAAANQAECgQIBgAAAA==.Wanglord:BAAANQAECgYIEAAAAA==.Wardõn:BAAANQADCgcICAAAAA==.Warpig:BAAANQADCgUIBgAAAA==.Warriormilan:BAAANQAECgIIAgAAAA==.Waxedtaco:BAAANQAECgMIBgAAAA==.',
Wh='Wheato:BAABNQAECoEiAAMZAAgKfSXFCgBeAwAZAAgKPSXFCgBeAwAYAAMKOCIGHgAjAQAAAA==.Wheyprotein:BAAANQADCggIEAAAAA==.Whipshot:BAAANQADCggICQAAAA==.Whiteflame:BAAANQAECgYICgAAAA==.Whiteopal:BAABNQAECoEcAAIKAAgKvQ1hUgDTAQAKAAgKvQ1hUgDTAQAAAA==.Whorship:BAAANQAECgQIBAAAAA==.',
Wi='Willownera:BAAANQABCgIIAwAAAA==.Willowsun:BAAANQAECgIIAgAAAA==.Winterzap:BAAANQAECgUIBQAAAA==.Wipe:BAAANQADCggICAABNQAFFAcIGAAMADsjAA==.',
Wo='Wolfyhunter:BAAANQADCggJCAAAAA==.',
Wr='Wrathkiller:BAAANQADCgcJBwAAAA==.',
Wu='Wulfrick:BAAANQADCgMIBQAAAA==.',
['Wí']='Wítchypoo:BAAANQAECgUICwAAAA==.',
['Wú']='Wúlf:BAAANQADCgQIBAAAAA==.',
Xa='Xalatoth:BAAANQAECgUIBQAAAA==.Xane:BAAANQADCgcIGAAAAA==.Xanetia:BAAANQAECgQIBwAAAA==.Xatir:BAAANQADCgQIBwAAAA==.',
Xi='Xinee:BAAANQAECgMIAwABNQAECgQIBgABAAAAAA==.Xinful:BAAANQADCgUJBQABNQAECgEJAQABAAAAAA==.Xint:BAAANQABCgEIAQAAAA==.',
Xj='Xjaryl:BAAANQADCgcIDgAAAA==.',
Xo='Xoger:BAAANQABCgQIBAAAAA==.',
Xy='Xyandris:BAAANQAECgQJBgAAAA==.',
['Xï']='Xïbalba:BAAANQABCgIJAgAAAA==.',
Ya='Yamasharma:BAAANQADCgYJFgAAAA==.',
Ye='Yeehaww:BAAANQAECgQIDAAAAA==.',
Yi='Yifa:BAAANQAECgYIBgAAAA==.',
Yy='Yykes:BAAANQABCgIIAgAAAA==.',
Za='Zaharax:BAAANQAECgQIEQAAAA==.Zaharis:BAAANQAECgUICAAAAA==.Zanakari:BAAANQADCgYJFAAAAA==.Zasilia:BAAANQADCgUIBQAAAA==.Zass:BAAANQADCgQIBAAAAA==.',
Ze='Zensetrazath:BAABNQAECoEYAAMkAAgKXxdyGwDPAQAkAAYK5hhyGwDPAQAhAAQK2wvKIwDdAAAAAA==.Zerath:BAAANQADCgYIBwAAAA==.',
Zh='Zhanqui:BAAANQAECgYIEQAAAA==.',
Zi='Ziba:BAABNQAECoElAAIHAAkKeRm8JwC+AgAHAAkKeRm8JwC+AgAAAA==.Zilithus:BAAANQADCgYIBgABNQAECgYIBwABAAAAAA==.Zingermage:BAEANQAECgcICwABNQAECggIGAAEAE4kAA==.Zipzamzoom:BAAANQADCggIAgABNQADCggIHgABAAAAAA==.',
Zo='Zoroo:BAAANQAECgQIDwAAAA==.',
Zr='Zross:BAAANQADCgcIDQAAAA==.',
Zu='Zudo:BAAANQAECgUIDgAAAA==.Zuthrais:BAACNQAFFIEMAAIMAAUK5AMhCwBFAQAMAAUK5AMhCwBFAQA1AAQKgT4AAgwACQq3EYE6AEMCAAwACQq3EYE6AEMCAAAA.Zuulik:BAAANQADCgYIDgAAAA==.Zuuls:BAAANQADCggJCwAAAA==.',
Zz='Zz:BAACNQAFFIERAAIeAAcK7xU7AACMAgAeAAcK7xU7AACMAgA1AAQKgSgAAh4ACQpIJmwAAOUDAB4ACQpIJmwAAOUDAAAA.',
['Án']='Ángelpie:BAAANQAECgEIAgAAAA==.',
['Är']='Ärrôw:BAAANQADCgYIAgAAAA==.',
['Ås']='Åshka:BAAANQABCgQIAgAAAA==.',
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
