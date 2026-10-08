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

local lookup = {'Priest-Holy','DeathKnight-Unholy','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Mage-Arcane','Rogue-Assassination','Hunter-Survival','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Shaman-Restoration','Paladin-Protection','Shaman-Elemental','Priest-Shadow','Mage-Frost','DeathKnight-Frost','Evoker-Preservation','Evoker-Augmentation','Monk-Mistweaver','Rogue-Subtlety','Paladin-Retribution','Warrior-Arms','Warrior-Protection','DemonHunter-Devourer','Druid-Balance','DemonHunter-Vengeance','Monk-Windwalker','Druid-Guardian','Druid-Restoration','Shaman-Enhancement','Warrior-Fury','Rogue-Outlaw',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaric:BAAANQADCgUICQAAAA==.',
Ae='Aedaris:BAABNQAECoFLAAIBAAgKuRWhUgAAAgABAAgKuRWhUgAAAgAAAA==.',
Ak='Akirik:BAAANQADCgYICgAAAA==.',
Al='Albert:BAAANQADCggICAAAAA==.Alf:BAAANQADCgYIEgAAAA==.Allayt:BAAANQAECgQIBQAAAA==.Aloremirin:BAAANQADCggICQAAAA==.',
Am='Ametrigos:BAAANQAECgYIDQAAAA==.',
Ar='Artzlayer:BAABNQAECoEoAAICAAkKPyA5FQD4AgACAAkKPyA5FQD4AgAAAA==.Aríes:BAABNQAECoFPAAIDAAgKxhZjKQArAgADAAgKxhZjKQArAgAAAA==.',
As='Ashbourne:BAAANQAECgYIDAAAAA==.',
Av='Avakyn:BAAANQAECggIEQAAAA==.',
Aw='Awry:BAEBNQAECoFCAAICAAgKPx86JgCEAgACAAgKPx86JgCEAgAAAA==.Awuuga:BAAANQAECgIIAgABNQAECggIHwAEAGYOAA==.Aww:BAAANQADCgEIAQAAAA==.',
Az='Azmo:BAACNQAFFIEPAAQFAAUKVhAKDACiAAAEAAMK1g+HHADjAAAFAAIKFxEKDACiAAAGAAEKowYBDwA+AAA1AAQKgScABAUACQp7IkIEANwCAAUACArsIEIEANwCAAQABwo9HZdPAEUCAAYAAgoHIUkbAIQAAAAA.',
Ba='Badds:BAAANQAECgEIAQAAAA==.Barad:BAAANQADCgMIAwAAAA==.',
Be='Beastroll:BAAANQADCggIFAAAAA==.Berserkk:BAAANQAECgcIDwAAAA==.Bewbs:BAAANQAECgQICQABNQAECgcIDAAHAAAAAA==.',
Bi='Bicksmage:BAABNQAECoEZAAIIAAkKABdufgBpAgAIAAkKABdufgBpAgAAAA==.Bigdaddyclap:BAAANQAECggIEAABNQAFFAcIFgAEAJkYAA==.Bigdaddylock:BAACNQAFFIEWAAQEAAcKmRgwAwAqAgAEAAYKbRYwAwAqAgAFAAIKwSLJBQC/AAAGAAEK9By7CABRAAA1AAQKgR0ABAQACQrxIuw5AIsCAAQACAquIuw5AIsCAAUABgpHGO4bAIYBAAYAAQrgJuYcAHMAAAAA.',
Bl='Blerdwerd:BAAANQADCgYIBgABNQAECgcIDwAHAAAAAA==.',
Bo='Bobafatt:BAAANQAECgIIAgAAAA==.Bombdiggity:BAAANQAECgQICgAAAA==.Bonnierotted:BAAANQAECgQIBAABNQAFFAUICQAJAPEcAA==.',
Br='Brallix:BAAANQAECgYIBwABNQAFFAUIDQAEAP0ZAA==.Bräinfreeze:BAAANQAECggICwAAAA==.',
['Bã']='Bãllz:BAAANQABCgQIBAAAAA==.',
Ca='Cakebringer:BAAANQAECgEIAQAAAA==.Catrit:BAAANQADCgIIAgAAAA==.',
Ch='Chich:BAAANQADCgQIBAAAAA==.Chud:BAABNQAECoEUAAIKAAgKXh6WAgDvAgAKAAgKXh6WAgDvAgAAAA==.',
Ci='Cig:BAAANQADCgIIAgAAAA==.',
Cl='Clocky:BAABNQAECoEXAAILAAgKxBGyTwAMAgALAAgKxBGyTwAMAgAAAA==.Cloneofhunt:BAACNQAFFIENAAIMAAQKLBwCCwBsAQAMAAQKLBwCCwBsAQA1AAQKgSAAAwwACQrrJRAIAI4DAAwACQrrJRAIAI4DAA0AAgo8FGJgAH4AAAAA.',
Co='Cocopop:BAAANQADCgQIBAAAAA==.Combustanut:BAAANQADCgMIAwAAAA==.Comillazz:BAABNQAECoEmAAIOAAkK3hkkIwCEAgAOAAkK3hkkIwCEAgAAAA==.Comillpeace:BAAANQABCgUIBwAAAA==.',
Cr='Creepydude:BAAANQABCgUIBwAAAA==.Crusher:BAAANQAECgIIAgABNQAFFAYIFwAPAG4dAA==.',
Cu='Cultiran:BAAANQAECgUIEAABNQAECggIFAAKAF4eAA==.Curby:BAABNQAECoFPAAIQAAgKehWTHgDHAQAQAAgKehWTHgDHAQAAAA==.Cursedfennec:BAAANQADCgIJAgAAAA==.',
Da='Damge:BAAANQAECgQIDgAAAA==.Damnnyou:BAABNQAECoEeAAMRAAkKjR0zHgD7AgARAAkKjR0zHgD7AgAPAAcKJxFLZgCqAQAAAA==.Dandiwa:BAAANQADCgMIAwAAAA==.Danky:BAAANQAECgQICAAAAA==.',
De='Deadicated:BAABNQAECoFJAAIBAAgKiRgaQgA9AgABAAgKiRgaQgA9AgAAAA==.Deathshunter:BAABNQAECoEaAAMMAAgKZiQUFQAxAwAMAAgKZiQUFQAxAwANAAEKbBdVdAA8AAABNQAFFAUICwACADsdAA==.Debsi:BAAANQAECgIIAgABNQAECgYICQAHAAAAAA==.Declined:BAAANQAECgQIBgAAAA==.Deeper:BAAANQAECggIEwAAAA==.Deepest:BAABNQAECoEdAAIJAAkKWBr3EQDNAgAJAAkKWBr3EQDNAgAAAA==.Deloraine:BAACNQAFFIEbAAMSAAcKRiCCAgA1AgASAAYKJh+CAgA1AgABAAMK7QhzGwDaAAA1AAQKgTwAAxIACQpRJOAEAHsDABIACQpRJOAEAHsDAAEAAQoFBe/cAD8AAAAA.Deminos:BAAANQADCgEIAQAAAA==.Demonblaze:BAAANQAECggIDwAAAA==.Demonicfaith:BAAANQADCggIEAABNQAECgkJFwAEAKcLAA==.Dendrendas:BAAANQADCgQIBAAAAA==.Dernheart:BAAANQADCgQIBAAAAA==.Destrohacka:BAABNQAECoEcAAMTAAgKdRF5FQAxAQAIAAYKew0IAAFnAQATAAUKXRJ5FQAxAQAAAA==.',
Di='Diaodai:BAAANQABCgMIAwAAAA==.Disckin:BAAANQADCgEIAQAAAA==.',
Do='Doomvedas:BAAANQAECgQIBAAAAA==.',
Dr='Dracaena:BAAANQAECggIDAABNQAECgkJHgARAI0dAA==.Dracodeath:BAACNQAFFIEIAAIUAAQKNBFWBwA0AQAUAAQKNBFWBwA0AQA1AAQKgSUAAhQACQoVIHUQAO0CABQACQoVIHUQAO0CAAAA.Dracular:BAABNQAECoEpAAMVAAkKBxNFFgA7AgAVAAkKBxNFFgA7AgAWAAUKBxMDDgA7AQAAAA==.Draining:BAABNQAECoEnAAMEAAgK0h/4HwDuAgAEAAgKdx/4HwDuAgAGAAEKCiXfHQBtAAAAAA==.Drakos:BAAANQAECgEIAQAAAA==.Drakraryz:BAAANQAECgQIBAAAAA==.Drekavach:BAAANQAECgUICwAAAA==.Drownedfish:BAAANQAECgMIAwAAAA==.',
Ed='Edifis:BAAANQADCgYIBgAAAA==.',
Ej='Ejzok:BAABNQAECoEzAAMIAAkK1B5xLwAiAwAIAAkK6x1xLwAiAwATAAIK8x2MIwCwAAAAAA==.Ejzox:BAABNQAECoEoAAIXAAkKiRz5BwD2AgAXAAkKiRz5BwD2AgABNQAECgkJMwAIANQeAA==.',
El='Elibaba:BAABNQAECoEXAAIIAAgKAhtJbwCKAgAIAAgKAhtJbwCKAgAAAA==.',
Em='Emopapa:BAABNQAECoFEAAIOAAkKOCOrBwByAwAOAAkKOCOrBwByAwAAAA==.',
En='Endlessdh:BAAANQAECgEIAQAAAA==.',
Er='Erihunter:BAAANQAECgMIBgAAAA==.Err:BAABNQAECoEdAAMJAAkKxBxKHgBjAgAJAAgKohtKHgBjAgAYAAYKqBjjHQDOAQAAAA==.',
Ev='Evening:BAAANQAECgMIAwAAAA==.',
Ez='Ezelia:BAABNQAECoEmAAMLAAkK4BZVJgC4AgALAAkK4BZVJgC4AgAZAAcKqgpa3QAnAQABNQAFFAUIFwABAMoTAA==.',
Fa='Faelune:BAAANQAECgQIBAAAAA==.Falcor:BAAANQADCgYIBgAAAA==.',
Fl='Flameshock:BAAANQADCgcICAAAAA==.Flesh:BAAANQADCggIDwAAAA==.',
Fo='Foamypuppy:BAAANQAECgEIAQAAAA==.',
Fr='Freshie:BAAANQAECgMIAwAAAA==.',
Fu='Fullmoonride:BAAANQADCgYIFQAAAA==.Funkymajik:BAAANQAECgQIBAAAAA==.Furiosa:BAAANQABCgYIBgAAAA==.Furyfork:BAABNQAECoEYAAIaAAgKGAt6lQC+AQAaAAgKGAt6lQC+AQAAAA==.',
Ga='Ganin:BAABNQAECoEUAAILAAgKfBtyJQC8AgALAAgKfBtyJQC8AgAAAA==.Garugala:BAABNQAECoErAAIZAAkKmiQrCwCaAwAZAAkKmiQrCwCaAwAAAA==.',
Ge='Gengár:BAAANQAECgQIBAABNQAECgQICQAHAAAAAA==.',
Gh='Ghalorin:BAAANQAECgMIAwAAAA==.',
Gi='Gigachad:BAABNQAECoEcAAMbAAkKXxSwDwABAgAbAAgK+RWwDwABAgAaAAQKtApt7wDQAAAAAA==.Gingarthas:BAABNQAECoEWAAICAAgKDx04SADPAQACAAgKDx04SADPAQAAAA==.',
Gr='Grapespliter:BAAANQAECgcIEQAAAA==.Grimefiend:BAAANQAFFAEIAQAAAA==.Grimetime:BAABNQAECoEXAAIIAAgK0hl/gQBjAgAIAAgK0hl/gQBjAgABNQAFFAEIAQAHAAAAAA==.Grriinn:BAAANQAECgYIBgAAAA==.',
Ha='Handwarm:BAABNQAECoEpAAIRAAcKJRWrXwDTAQARAAcKJRWrXwDTAQAAAA==.Hanokano:BAAANQAECgUICAABNQAECgkJNwAEACghAA==.',
He='Heartdh:BAABNQAECoEhAAMDAAkK4RvvFwC7AgADAAkK4RvvFwC7AgAcAAMKJg0ITwCkAAAAAA==.Hellkai:BAABNQAECoEtAAMGAAgKySCRAgDVAgAGAAcK0yORAgDVAgAEAAUKTRRMswA5AQAAAA==.Herrion:BAACNQAFFIENAAQEAAUK/RlnFwAGAQAEAAMKNhZnFwAGAQAFAAEKICBPEgBhAAAGAAEKLh8UBwBdAAA1AAQKgS0AAwQACQqTJMEqAMECAAQABwqZJMEqAMECAAUABQowF0QdAHsBAAAA.',
Hi='Hippy:BAACNQAFFIEKAAIdAAUK3hsiCQC2AQAdAAUK3hsiCQC2AQA1AAQKgRsAAh0ACQoAIwwRACsDAB0ACQoAIwwRACsDAAE1AAQKAwgFAAcAAAAA.',
Ho='Hog:BAAANQAECgYIDQABNQAECgMIBQAHAAAAAA==.Holytanky:BAAANQADCgMIBgAAAA==.',
Hu='Hukani:BAAANQAECgYIDQAAAA==.Huskar:BAABNQAECoEbAAIMAAcKLheqbgAIAgAMAAcKLheqbgAIAgAAAA==.',
Hw='Hwanjeabb:BAABNQAECoEnAAIOAAkKRRP3NgANAgAOAAkKRRP3NgANAgAAAA==.',
['Hë']='Hëcate:BAAANQABCgMIAwAAAA==.',
Ig='Ignis:BAAANQAECggIEAAAAA==.',
Il='Ilillillill:BAAANQADCgcJBwAAAA==.Illiroman:BAABNQAECoEdAAMeAAkK3wwhDwCTAQAeAAgKNw4hDwCTAQADAAcKmAMGVQAAAQAAAA==.',
Im='Imntprepared:BAAANQAECggIEQAAAA==.',
In='Infectîon:BAAANQAECggIEwAAAA==.',
Ji='Jimjum:BAABNQAECoE4AAIBAAkKKyC3EgAgAwABAAkKKyC3EgAgAwAAAA==.',
Ju='Jubeaint:BAAANQADCgYIDAABNQAECgYIFAAPAN4bAA==.',
Ka='Kaaru:BAABNQAECoEdAAIBAAgKRRQCUwD+AQABAAgKRRQCUwD+AQAAAA==.Kagarl:BAAANQAECgQICQABNQAFFAUIDQAEAP0ZAA==.Kaiforst:BAAANQADCggICAABNQAECgkJKgAZAGYcAA==.Kairon:BAABNQAECoEqAAIZAAkKZhycMwDdAgAZAAkKZhycMwDdAgAAAA==.',
Kh='Khaydub:BAAANQAECgQICAAAAA==.',
Ki='Kickstarter:BAABNQAECoEfAAQEAAgKZg4JpwBVAQAEAAYKCA4JpwBVAQAFAAIKgA+gVgBxAAAGAAEKcwWyLgAsAAAAAA==.Kiewkajee:BAAANQAECggIEAAAAA==.Kiosk:BAABNQAECoEeAAIIAAgK9BW1ogAcAgAIAAgK9BW1ogAcAgAAAA==.Kiwichaos:BAACNQAFFIEIAAIcAAMKoQx8CwDWAAAcAAMKoQx8CwDWAAA1AAQKgSsAAhwACQrYHIgQANsCABwACQrYHIgQANsCAAAA.',
Kr='Krellis:BAABNQAECoEUAAIfAAcKYByyHwAFAgAfAAcKYByyHwAFAgAAAA==.',
Ku='Kurozuka:BAAANQADCgUIBQAAAA==.',
Kv='Kvôthe:BAAANQAECgQIBAAAAA==.',
Ky='Kynralol:BAABNQAECoEfAAIIAAgKFR5NSQDhAgAIAAgKFR5NSQDhAgAAAA==.',
La='Lagalot:BAAANQAECgYIDwAAAA==.',
Le='Legham:BAAANQADCgYIBAAAAA==.Legolazz:BAABNQAECoEkAAMMAAkKxhyXJwDaAgAMAAkKxhyXJwDaAgANAAQKUwy1SwDUAAAAAA==.Lenatheplug:BAACNQAFFIEJAAIJAAUK8RygAwDbAQAJAAUK8RygAwDbAQA1AAQKgRgAAgkACQqbIKYbAHcCAAkACQqbIKYbAHcCAAAA.',
Li='Lightfinder:BAAANQAECgUIBQAAAA==.Lionisse:BAAANQAECgcIBwAAAA==.',
Ll='Llewser:BAABNQAECoEeAAIIAAcKkxsrlAA7AgAIAAcKkxsrlAA7AgAAAA==.',
Lo='Loongzokluad:BAABNQAECoEmAAIbAAkKNRGiEADvAQAbAAkKNRGiEADvAQAAAA==.Louisvuitton:BAAANQAECgQJBQAAAA==.',
Lu='Luckydews:BAAANQAECgUIDgAAAA==.Lumina:BAAANQAECgcIDgABNQAFFAYIFwAPAG4dAA==.',
['Lì']='Lìnkinbark:BAAANQADCgYIBQAAAA==.',
Ma='Madará:BAAANQADCgEIAQAAAA==.Maggot:BAAANQADCgUIDQAAAA==.Mathusorn:BAAANQAECgQIBAAAAA==.Maÿcé:BAABNQAECoEWAAMLAAgKpAxPfgB1AQALAAcKSgpPfgB1AQAZAAMKpAnKNgGGAAABNQAFFAEIAgAHAAAAAA==.',
Mi='Mirair:BAAANQADCgUIBQAAAA==.Miralisa:BAAANQAECgQIBAAAAA==.Mirant:BAAANQADCggICAAAAA==.Mirisha:BAAANQABCgcJCQAAAA==.Miststep:BAAANQADCggJGAAAAA==.',
Mo='Mooferax:BAAANQADCggJCAAAAA==.Moondeity:BAAANQAECgUIBAAAAA==.Morphio:BAABNQAECoEpAAIMAAkKhCKgBwCTAwAMAAkKhCKgBwCTAwAAAA==.Morêl:BAAANQAECgEJAQAAAA==.',
My='Mystified:BAAANQAECgUICgAAAA==.Mythira:BAAANQADCgMIAwABNQAECggITwAOAMsfAA==.',
Mz='Mzzlock:BAAANQADCgMIAwAAAA==.',
['Mà']='Màyce:BAAANQAFFAEIAgAAAA==.',
Nb='Nb:BAABNQAECoEpAAIVAAkK5hfVDgCoAgAVAAkK5hfVDgCoAgAAAA==.',
Ne='Nelena:BAAANQADCgUIBwAAAA==.Ness:BAACNQAFFIEFAAIOAAIKoBJjHACDAAAOAAIKoBJjHACDAAA1AAQKgSUAAg4ACQpSIm8MAD4DAA4ACQpSIm8MAD4DAAAA.Nevell:BAAANQAECggIEgABNQAFFAUIDQAEAP0ZAA==.',
Ni='Nikola:BAACNQAFFIEHAAMgAAMKfA6cBACoAAAgAAMKHQmcBACoAAAdAAEKPB3/HwBZAAA1AAQKgSwABCAACQp6GhYTAO4BAB0ACAoyGPQpAGQCACAACQrvEBYTAO4BACEABApLEeQ7AAoBAAAA.Nimro:BAACNQAFFIEPAAIbAAUKbxjFAQB7AQAbAAUKbxjFAQB7AQA1AAQKgTMAAhsACQrTIm8IAKICABsACQrTIm8IAKICAAAA.Niub:BAAANQAECgQIBAAAAA==.',
No='Nongmicky:BAABNQAECoEXAAIiAAgK3B1ODQB/AgAiAAgK3B1ODQB/AgAAAA==.',
Nu='Nueng:BAAANQAECgMIAwAAAA==.Nuferax:BAAANQAECgQIBAAAAA==.Nuisadv:BAAANQAECgYIDwAAAA==.',
Oa='Oaf:BAAANQADCgEIAQAAAA==.',
Od='Oddesa:BAAANQAECgIIAgAAAA==.',
Of='Offwithye:BAAANQAECgYICQAAAA==.',
Oh='Ohanna:BAAANQAECgEIAQAAAA==.',
Ok='Okiji:BAAANQAECgUJDQAAAA==.',
Om='Ominae:BAAANQAECgQIBAAAAA==.',
Or='Oranlord:BAAANQADCggJCgAAAA==.Orgilord:BAAANQADCgcIDQAAAA==.',
Pa='Palliative:BAABNQAECoEsAAILAAcKEhwJQABGAgALAAcKEhwJQABGAgAAAA==.Pallidnim:BAABNQAECoEWAAIOAAgKtB0FHgCoAgAOAAgKtB0FHgCoAgAAAA==.Pallystine:BAAANQAECgcJEAAAAA==.Pandarendk:BAAANQADCggIDwAAAA==.',
Pe='Pearson:BAAANQADCgQIBgAAAA==.',
Ph='Phatmage:BAABNQAECoEtAAIIAAkKLCDQKwAtAwAIAAkKLCDQKwAtAwABNQAFFAQICQAEAKoWAA==.Phatmonk:BAAANQAFFAEIAQABNQAFFAQICQAEAKoWAA==.Phatpriest:BAAANQAFFAIIAgABNQAFFAQICQAEAKoWAA==.Phatwarlock:BAACNQAFFIEJAAMEAAQKqhZhJgCfAAAEAAMKOhdhJgCfAAAFAAEK/BTJFgBTAAA1AAQKgSYABAQACQrhIZAMAFUDAAQACQqzIZAMAFUDAAYAAgp4FtwbAH0AAAUAAQrMJTJXAHAAAAAA.',
Pi='Pix:BAACNQAFFIETAAMSAAYKByLLAwDyAQASAAUKZSHLAwDyAQABAAMKLg+DGQDtAAA1AAQKgR0AAhIACQowJUAGAGQDABIACQowJUAGAGQDAAAA.',
Pl='Pleasuremax:BAABNQAECoEZAAIMAAgKtxQdYQAqAgAMAAgKtxQdYQAqAgAAAA==.',
Po='Poofyfeesh:BAABNQAECoEXAAIBAAgK4RlSNQBxAgABAAgK4RlSNQBxAgAAAA==.Pookkook:BAAANQABCgQIBAAAAA==.Popshot:BAAANQADCgUICgAAAA==.Porpus:BAAANQADCgcIEAABNQAECgYICwAHAAAAAA==.Porthub:BAAANQADCgUIBQAAAA==.',
Pr='Praxis:BAAANQAECgYIDwAAAA==.Preast:BAAANQADCggICAABNQAECgcIEgAHAAAAAA==.Procist:BAAANQABCgMIAwABNQAECgkJIgAhAIQiAA==.',
Py='Pyrusdk:BAABNQAECoEjAAMCAAkKmRTDOAAdAgACAAkKmRTDOAAdAgAOAAMKOQxFkgCcAAAAAA==.Pyruslock:BAAANQAECggIAQAAAA==.',
Qe='Qermack:BAAANQADCgcJCQAAAA==.',
Ra='Raìn:BAAANQADCgUIBQAAAA==.',
Re='Rednutts:BAAANQAECgYICAAAAA==.Rekt:BAAANQAECgcIDAAAAA==.',
Ri='Riggs:BAACNQAFFIEdAAMaAAcKuSUrAQDsAgAaAAcKryQrAQDsAgAjAAUK9iBYAAAAAgA1AAQKgSMAAxoACQqZJu4KAJgDABoACQqAJu4KAJgDACMABArYJXgNALgBAAAA.',
Rn='Rnc:BAABNQAECoEXAAICAAkK2x01HADHAgACAAkK2x01HADHAgAAAA==.',
Ro='Roaroaroar:BAAANQADCgYICAAAAA==.Rodger:BAAANQAECgcIEgAAAA==.Rolâyne:BAAANQADCgcIBwAAAA==.Ronfirestorm:BAAANQADCgYIDAABNQAECgkJFwAEAKcLAA==.Roninn:BAABNQAECoErAAIhAAkKECLSAwB6AwAhAAkKECLSAwB6AwAAAA==.Ronlock:BAABNQAECoEXAAIEAAkKpwt8nQBsAQAEAAkKpwt8nQBsAQAAAA==.',
Rw='Rwen:BAABNQAECoErAAIMAAcKnQYYsgBsAQAMAAcKnQYYsgBsAQAAAA==.',
['Rô']='Rôlayne:BAAANQAECgIIAwAAAA==.',
Sa='Sadakos:BAAANQAECgQIEQAAAA==.Salvare:BAABNQAECoEeAAIkAAkK4BhkBACxAgAkAAkK4BhkBACxAgAAAA==.Sarielsia:BAAANQAECgQICQAAAA==.Sarielsiá:BAAANQADCgYIBgABNQAECgQICQAHAAAAAA==.Sauron:BAAANQADCgYIDwABNQAECgkJOQAaAJAcAA==.Sazzart:BAAANQADCgcIBwAAAA==.',
Sc='Sciodeekay:BAABNQAECoE7AAIOAAkKdiCLDgApAwAOAAkKdiCLDgApAwAAAA==.Sciohunter:BAAANQAECgMIAwAAAA==.Scioscioz:BAAANQAECgEIAQAAAA==.Scwisgar:BAABNQAECoEfAAIOAAgKQhpHLgA/AgAOAAgKQhpHLgA/AgAAAA==.',
Se='Sedge:BAABNQAECoEoAAIJAAkK1CLBBQBiAwAJAAkK1CLBBQBiAwAAAA==.Sewerface:BAAANQAECgQICAAAAA==.',
Sh='Shadowind:BAABNQAECoEwAAIMAAkK3iGqCgB3AwAMAAkK3iGqCgB3AwAAAA==.Shadowz:BAAANQADCggIDAAAAA==.Shambulance:BAAANQADCggIFgAAAA==.Shammalxs:BAACNQAFFIEJAAIRAAQKwhE8DwA8AQARAAQKwhE8DwA8AQA1AAQKgS0AAhEACQrVIMYTAEADABEACQrVIMYTAEADAAAA.Shamoc:BAABNQAECoEVAAIPAAkKUiJeBwB4AwAPAAkKUiJeBwB4AwABNQAECgkJIgAhAIQiAA==.Shanki:BAAANQABCgMIAwAAAA==.Sharpknife:BAABNQAECoEbAAMNAAgK5yJJCwATAwANAAgKByJJCwATAwAMAAYK3RcPnACcAQAAAA==.Shiesty:BAAANQADCgUIBQAAAA==.Shinieedin:BAAANQAECgIIAgABNQAECggIGAAdAMYYAA==.Shivd:BAAANQAECgUIDQAAAA==.',
Sk='Skizzyy:BAAANQADCgQIBAABNQADCgYIBgAHAAAAAA==.',
Sl='Slowjoe:BAAANQAECgcIDwAAAA==.',
Sm='Smacedh:BAAANQADCgIIAgAAAA==.Smallheals:BAAANQADCgEJAQAAAA==.',
Sn='Sneakyfella:BAAANQAECggIDAAAAA==.Sneekin:BAAANQAECgEIAQAAAA==.',
So='Solidus:BAAANQAECggICQAAAA==.',
Sp='Spardã:BAAANQAECgYIDAAAAA==.Spoonfed:BAAANQAECgIIAgAAAA==.',
Sq='Squiish:BAAANQAECgcICAAAAA==.',
St='Starwraith:BAAANQADCgYIBgABNQAFFAMIBQARAHELAA==.Stgeorge:BAABNQAECoEeAAIWAAgKEA6YCQC4AQAWAAgKEA6YCQC4AQAAAA==.Stickypriest:BAABNQAECoFPAAMSAAgKtSB8EADWAgASAAgKtSB8EADWAgABAAIKPhvcxgCMAAAAAA==.Strawhats:BAACNQAFFIEYAAMIAAcK4CAjBgA5AgAIAAYKvCAjBgA5AgATAAEKtSH9CABgAAA1AAQKgSEAAggACQrcJGUcAFwDAAgACQrcJGUcAFwDAAAA.Streamliner:BAABNQAECoEgAAIYAAkKIBCLFAAyAgAYAAkKIBCLFAAyAgAAAA==.Stunks:BAAANQAECgEIAQAAAA==.',
Su='Sultan:BAAANQADCgYIDAAAAA==.',
Sy='Sy:BAAANQADCggIDQAAAA==.',
Ta='Talletalanot:BAAANQAECgQICwABNQAECgkJIwARAE4hAA==.Tarlenm:BAABNQAECoEiAAMhAAkKhCIWBAB2AwAhAAkKhCIWBAB2AwAgAAUKWRzbGACiAQAAAA==.',
Td='Tdk:BAAANQAECggICQAAAA==.',
Te='Terrafirm:BAAANQADCgQJBAAAAA==.Testaltesta:BAAANQADCggIDgAAAA==.Testaxltesta:BAAANQAECgUICQABNQADCggIDgAHAAAAAA==.',
Th='Thickstick:BAAANQAECgEIAQAAAA==.Thon:BAABNQAECoEYAAIZAAkKoRBwdgARAgAZAAkKoRBwdgARAgAAAA==.Thunderbelly:BAABNQAECoEdAAIPAAkKjRjGMwBqAgAPAAkKjRjGMwBqAgAAAA==.',
To='Totems:BAACNQAFFIEXAAIPAAYKbh3RAwAmAgAPAAYKbh3RAwAmAgA1AAQKgTAAAw8ACQoSJeIBAL8DAA8ACQoSJeIBAL8DABEAAQosCVcZATEAAAAA.',
Tr='Traktorbeam:BAAANQADCgYIEgAAAA==.Trass:BAABNQAECoE3AAQEAAkKKCGjCgBlAwAEAAkKKCGjCgBlAwAFAAMKgxRHPwC7AAAGAAEKyg2rKgA4AAAAAA==.Trisse:BAAANQAECgQICQAAAA==.',
Tu='Tuzz:BAABNQAECoEkAAIUAAkKHyIhCQBDAwAUAAkKHyIhCQBDAwAAAA==.',
Un='Unphayzed:BAAANQADCgYIBgABNQAECgkJIQAJAP4aAA==.',
Va='Vaelreth:BAAANQADCgcIBwAAAA==.Varaestia:BAAANQAECgUIEwAAAA==.Varg:BAABNQAECoEbAAMOAAkKgiHgCwBEAwAOAAkKgiHgCwBEAwAUAAMKNRXUbQCjAAAAAA==.Varthloukker:BAAANQABCgQIBQAAAA==.',
Ve='Vermeil:BAAANQAECgMIBAAAAA==.Vermillion:BAABNQAECoEeAAIQAAkKEhcqFwAZAgAQAAkKEhcqFwAZAgAAAA==.Verzik:BAAANQAECgYIDgAAAA==.',
Vi='Vib:BAAANQAECgUIDgAAAA==.Vicia:BAAANQADCgYIBwAAAA==.Viczrei:BAAANQAECgcIDAAAAA==.',
Vr='Vråg:BAAANQAECgIIAgAAAA==.',
Vv='Vvenator:BAABNQAECoEZAAMZAAYK4xUQogClAQAZAAYK4xUQogClAQALAAEK2B6k9QBYAAAAAA==.',
Vy='Vynessa:BAABNQAECoEgAAILAAgK/SLTEQAvAwALAAgK/SLTEQAvAwAAAA==.',
['Vè']='Vèè:BAAANQAECgUJBQABNQAECgkJHQAJAMQcAA==.',
Wa='Wakkytabbaky:BAAANQAECgQIBAAAAA==.Waterwaterz:BAABNQAECoEyAAMIAAkKJBnUbgCLAgAIAAkKihbUbgCLAgATAAUKBBWuFQAvAQAAAA==.Waylm:BAAANQAECgcIDgABNQAFFAUIDQAEAP0ZAA==.',
Wc='Wchin:BAABNQAECoElAAIIAAkKcSFvHgBWAwAIAAkKcSFvHgBWAwAAAA==.',
We='Weareleigon:BAAANQAECggICAAAAA==.Wedlock:BAAANQADCgQJBAAAAA==.Welcumshot:BAAANQAECgYICQAAAA==.Wendyy:BAAANQAECgQICAABNQAFFAcIEAAEAMIXAA==.',
Wh='Whaka:BAABNQAECoEbAAMMAAkKzhxcJQDjAgAMAAkKzhxcJQDjAgANAAEKGxEodAA9AAAAAA==.',
Wo='Wound:BAAANQADCgEIAgABNQAECgkJOAAKAJIjAA==.',
Xi='Xiera:BAAANQAECgQIBAAAAA==.',
Ya='Yaminosaishi:BAAANQAECgUIBQAAAA==.Yamiprays:BAAANQAECgYICQAAAA==.',
Yo='Yozzao:BAAANQADCggIDAAAAA==.',
Za='Zaler:BAAANQAECgUIBQAAAA==.',
Ze='Zenak:BAAANQAECgMIAwAAAA==.Zenath:BAABNQAECoEbAAIVAAkKHSIPAwCCAwAVAAkKHSIPAwCCAwABNQAFFAUIDQAEAP0ZAA==.Zerithra:BAABNQAECoFPAAIOAAgKyx90HACzAgAOAAgKyx90HACzAgAAAA==.',
Zi='Zilbam:BAAANQAECgUIBQAAAA==.Zinaak:BAAANQAECgIIAgAAAA==.',
Zm='Zmonk:BAAANQADCgEIAQAAAA==.',
Zz='Zzdeathnight:BAAANQAECgEIAQAAAA==.Zzdruid:BAAANQADCgcIDQAAAA==.Zzhunter:BAAANQADCgYIBgAAAA==.Zzpriest:BAAANQAECgIIAwAAAA==.',
['Ôx']='Ôx:BAAANQADCgcIBQAAAA==.',
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
