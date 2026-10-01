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

local lookup = {'Priest-Holy','DeathKnight-Unholy','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Shaman-Elemental','Rogue-Assassination','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Shaman-Restoration','Paladin-Protection','Priest-Shadow','Mage-Arcane','Mage-Frost','DeathKnight-Frost','Evoker-Preservation','Evoker-Augmentation','Monk-Mistweaver','Rogue-Subtlety','Paladin-Holy','Paladin-Retribution','Warrior-Protection','Warrior-Arms','DemonHunter-Devourer','Druid-Balance','DemonHunter-Vengeance','Monk-Windwalker','Druid-Guardian','Druid-Restoration','Shaman-Enhancement','Warrior-Fury','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaric:BAAANQADCgUICQAAAA==.',
Ae='Aedaris:BAABNQAECoE9AAIBAAgKphQ+SAD9AQABAAgKphQ+SAD9AQAAAA==.',
Ak='Akirik:BAAANQADCgYICgAAAA==.',
Al='Alf:BAAANQADCgYIEgAAAA==.Allayt:BAAANQAECgQIBQAAAA==.Aloremirin:BAAANQADCgYIBgAAAA==.',
Am='Ametrigos:BAAANQAECgYIDQAAAA==.',
Ar='Artzlayer:BAABNQAECoEiAAICAAkKLR+QFADfAgACAAkKLR+QFADfAgAAAA==.Aríes:BAABNQAECoFBAAIDAAgKOBSjJwAPAgADAAgKOBSjJwAPAgAAAA==.',
As='Ashbourne:BAAANQAECgYIDAAAAA==.',
Av='Avakyn:BAAANQAECggIEQAAAA==.',
Aw='Awry:BAEBNQAECoE9AAICAAgKCB/XHACaAgACAAgKCB/XHACaAgAAAA==.Awuuga:BAAANQAECgIIAgABNQAECgcIHgAEAL0PAA==.Aww:BAAANQADCgEIAQAAAA==.',
Az='Azmo:BAACNQAFFIELAAQFAAUKww4tCgCqAAAEAAMKNQ07FgDgAAAFAAIKFxEtCgCqAAAGAAEKowY6DABCAAA1AAQKgSMABAUACQoxIbwDAOgCAAUACArsILwDAOgCAAQABwpjG5lJADICAAYAAgoHIdIXAIoAAAAA.',
Ba='Badds:BAAANQAECgEIAQAAAA==.Barad:BAAANQADCgMIAwAAAA==.',
Be='Beastroll:BAAANQADCggIEgAAAA==.Berserkk:BAAANQAECgcICQAAAA==.Bewbs:BAAANQAECgQICQABNQAECgcICgAHAAAAAA==.',
Bi='Bicksmage:BAAANQAECgcJEQAAAA==.Bigdaddyclap:BAAANQAECggIDgABNQAFFAcIEwAEAEIYAA==.Bigdaddylock:BAACNQAFFIETAAQEAAcKQhiAAgAbAgAEAAYKYBWAAgAbAgAFAAIKwSLnBADEAAAGAAEK9ByUBgBUAAA1AAQKgR0ABAQACQrxIowrAJ8CAAQACAquIowrAJ8CAAUABgpHGJIZAJIBAAYAAQrgJtQZAHMAAAAA.',
Bl='Blerdwerd:BAAANQADCgYIBgABNQAFFAUICwAIADoZAA==.',
Bo='Bobafatt:BAAANQAECgIIAgAAAA==.Bombdiggity:BAAANQAECgIIBQAAAA==.Bonnierotted:BAAANQAECgQIBAABNQAFFAUIBwAJAAscAA==.',
Br='Brallix:BAAANQAECgQIBAABNQAFFAUICQAEAAUUAA==.Bräinfreeze:BAAANQAECggICwAAAA==.',
['Bã']='Bãllz:BAAANQABCgQIBAAAAA==.',
Ca='Cakebringer:BAAANQAECgEJAQAAAA==.Catrit:BAAANQADCgIIAgAAAA==.',
Ch='Chich:BAAANQADCgQIBAAAAA==.Christina:BAAANQAECgUICQAAAA==.Chud:BAAANQAECgUIDQABNQAECgUIEAAHAAAAAA==.',
Ci='Cig:BAAANQADCgIIAgAAAA==.',
Cl='Clocky:BAAANQAECgcIEQAAAA==.Cloneofhunt:BAACNQAFFIEJAAIKAAQKLBzbBwBpAQAKAAQKLBzbBwBpAQA1AAQKgR0AAwoACQrrJegEAKUDAAoACQrrJegEAKUDAAsAAgo8FJ1TAIQAAAAA.',
Co='Cocopop:BAAANQADCgQIBAAAAA==.Combustanut:BAAANQADCgMIAwAAAA==.Comillazz:BAABNQAECoEiAAIMAAkKChcgKQA/AgAMAAkKChcgKQA/AgAAAA==.',
Cr='Creepydude:BAAANQABCgUIBgAAAA==.Crusher:BAAANQAECgIIAgABNQAFFAYIEQANAIIUAA==.',
Cu='Cultiran:BAAANQAECgUIEAAAAA==.Curby:BAABNQAECoFBAAIOAAgKBhVkGQDRAQAOAAgKBhVkGQDRAQAAAA==.Cursedfennec:BAAANQADCgIJAgAAAA==.',
Da='Damge:BAAANQAECgQICgAAAA==.Damnnyou:BAABNQAECoEeAAMIAAkKjR15FwAUAwAIAAkKjR15FwAUAwANAAcKJxGiWACzAQAAAA==.Dandiwa:BAAANQADCgMIAwAAAA==.Danky:BAAANQAECgQICAAAAA==.',
De='Deadicated:BAABNQAECoE7AAIBAAgKKhSTSAD8AQABAAgKKhSTSAD8AQAAAA==.Deathshunter:BAAANQAECgcIEwABNQAFFAUICAACAM4cAA==.Debsi:BAAANQAECgIIAgABNQAECgMIAwAHAAAAAA==.Declined:BAAANQAECgQIBgAAAA==.Deeper:BAAANQAECggIDgAAAA==.Deepest:BAABNQAECoEXAAIJAAkK5RgZDwDLAgAJAAkK5RgZDwDLAgAAAA==.Deloraine:BAACNQAFFIEeAAMPAAYK8SNFCAAcAQAPAAMKlCJFCAAcAQABAAMK7gg6FQDkAAA1AAQKgT4AAw8ACQrOIWIFAGoDAA8ACQrOIWIFAGoDAAEAAQoxBe7DAD8AAAAA.Deminos:BAAANQADCgEIAQAAAA==.Demonblaze:BAAANQAECgcICQABNQAECgkJIgAQAKETAA==.Demonicfaith:BAAANQADCggIEAABNQAECgkJFwAEAKcLAA==.Dendrendas:BAAANQADCgQIBAAAAA==.Dernheart:BAAANQADCgQIBAAAAA==.Destrohacka:BAABNQAECoEaAAMRAAgKdRGDEQBKAQARAAUKXRKDEQBKAQAQAAUKVg44BQEyAQAAAA==.',
Di='Diaodai:BAAANQABCgMIAwAAAA==.Disckin:BAAANQADCgEIAQAAAA==.',
Dr='Dracaena:BAAANQAECgQIBAABNQAECgkJHgAIAI0dAA==.Dracodeath:BAACNQAFFIEFAAISAAQK7AuBBgAhAQASAAQK7AuBBgAhAQA1AAQKgSIAAhIACQr7H+0MAPsCABIACQr7H+0MAPsCAAAA.Dracular:BAABNQAECoEmAAMTAAkKBxOnEwBEAgATAAkKBxOnEwBEAgAUAAMKtxX+EADKAAAAAA==.Draining:BAABNQAECoEaAAMEAAgK0x3JNQB4AgAEAAgKrhzJNQB4AgAGAAEKCiWbGgBtAAAAAA==.Drakos:BAAANQAECgEIAQAAAA==.Drekavach:BAAANQAECgQICAAAAA==.Drownedfish:BAAANQAECgMIAwAAAA==.',
Ed='Edifis:BAAANQADCgYIBgAAAA==.',
Ej='Ejzok:BAABNQAECoElAAMQAAkKtRoCPADvAgAQAAkKYRoCPADvAgARAAEKNRoTLwBOAAAAAA==.Ejzox:BAABNQAECoEcAAIVAAkKrBTkDQBgAgAVAAkKrBTkDQBgAgABNQAECgkJJQAQALUaAA==.',
El='Elibaba:BAAANQAECgcIEwAAAA==.',
Em='Emopapa:BAABNQAECoE/AAIMAAkKdiKwBwBoAwAMAAkKdiKwBwBoAwAAAA==.',
En='Endlessdh:BAAANQAECgEIAQAAAA==.',
Er='Erihunter:BAAANQAECgMIBAAAAA==.Err:BAABNQAECoEbAAMJAAkKuxvkGQBbAgAJAAgKkBrkGQBbAgAWAAUK4BgIIgCTAQAAAA==.',
Ev='Evening:BAAANQAECgMIAwAAAA==.',
Ez='Ezelia:BAABNQAECoEkAAMXAAkK4BbdHwDAAgAXAAkK4BbdHwDAAgAYAAcKqgpivgAtAQABNQAFFAUIEgABAMoTAA==.',
Fa='Faelune:BAAANQAECgQIBAAAAA==.',
Fl='Flameshock:BAAANQADCgcICAAAAA==.Flesh:BAAANQADCggIDwABNQAECggIHAAXADYPAA==.',
Fu='Fullmoonride:BAAANQADCgYIEAAAAA==.Funkymajik:BAAANQAECgQIBAAAAA==.Furiosa:BAAANQABCgYIBgAAAA==.Furyfork:BAAANQAECgcIEAAAAA==.',
Ga='Ganin:BAAANQAECggIEgAAAA==.Garugala:BAABNQAECoEiAAIYAAkKUSRWCACkAwAYAAkKUSRWCACkAwAAAA==.',
Ge='Gengár:BAAANQADCggJEAABNQAECgQIBgAHAAAAAA==.',
Gh='Ghalorin:BAAANQAECgMIAwAAAA==.',
Gi='Gigachad:BAABNQAECoEXAAMZAAkKExN7DgDqAQAZAAgKhBR7DgDqAQAaAAEKjgd1GwEyAAAAAA==.Gingarthas:BAABNQAECoEUAAICAAYKLhyQXgAwAQACAAYKLhyQXgAwAQAAAA==.',
Gr='Grapespliter:BAAANQAECgYIDwAAAA==.Grimefiend:BAAANQAFFAEIAQAAAA==.Grimetime:BAABNQAECoEWAAIQAAgK0hkRbAB0AgAQAAgK0hkRbAB0AgABNQAFFAEIAQAHAAAAAA==.Grriinn:BAAANQAECgYIBgAAAA==.',
Ha='Handwarm:BAABNQAECoEjAAIIAAcKzRKiWADIAQAIAAcKzRKiWADIAQAAAA==.Hanokano:BAAANQAECgUIBQABNQAECgkJLwAEAAAgAA==.',
He='Heartdh:BAABNQAECoEdAAMDAAkKmRuxEwDFAgADAAkKmRuxEwDFAgAbAAMKJg2gSACoAAAAAA==.Hellkai:BAABNQAECoEnAAMGAAgKHiBsAgDGAgAGAAcKWyNsAgDGAgAEAAUK5BMgmgBAAQAAAA==.Herrion:BAACNQAFFIEJAAQEAAUKBRQ3FQDnAAAEAAMKJA83FQDnAAAFAAEK7h+SEwBZAAAGAAEKvxZkCABPAAA1AAQKgSsAAwQACQqKJK0hAMoCAAQABwqNJK0hAMoCAAUABQowFxsbAIYBAAAA.',
Hi='Hippy:BAACNQAFFIEGAAIcAAQK2RuBCgBqAQAcAAQK2RuBCgBqAQA1AAQKgRkAAhwACQrQIjUOADkDABwACQrQIjUOADkDAAE1AAQKAggCAAcAAAAA.',
Ho='Hog:BAAANQAECgYIDQABNQAECgIIAgAHAAAAAA==.Holytanky:BAAANQADCgMIBgAAAA==.',
Hu='Hukani:BAAANQAECgQIBwAAAA==.Huskar:BAAANQAECgYIEAAAAA==.',
Hw='Hwanjeabb:BAABNQAECoEfAAIMAAkKqxKqMgADAgAMAAkKqxKqMgADAgAAAA==.',
Ig='Ignis:BAAANQAECgcIDwAAAA==.',
Il='Ilillillill:BAAANQADCgcJBwAAAA==.Illiroman:BAABNQAECoEYAAMdAAgKyQtMDwBfAQAdAAcKKg1MDwBfAQADAAcKmAMSSQALAQAAAA==.',
Im='Imntprepared:BAAANQAECgcIDQAAAA==.',
In='Infectîon:BAAANQAECggJEwAAAA==.',
Ji='Jimjum:BAABNQAECoExAAIBAAkKBx1JEQATAwABAAkKBx1JEQATAwAAAA==.',
Ju='Jubeaint:BAAANQADCgYIDAABNQAECgYIFAANAN4bAA==.',
Ka='Kaaru:BAABNQAECoEXAAIBAAgKbhLbTgDiAQABAAgKbhLbTgDiAQAAAA==.Kagarl:BAAANQAECgIIAwABNQAFFAUICQAEAAUUAA==.Kaiforst:BAAANQADCggICAABNQAECgkJIQAYALgaAA==.Kairon:BAABNQAECoEhAAIYAAkKuBpzNwCsAgAYAAkKuBpzNwCsAgAAAA==.',
Ki='Kickstarter:BAABNQAECoEeAAQEAAcKvQ8PoAAxAQAEAAUK1Q8PoAAxAQAFAAIKgA/fUQB0AAAGAAEKcwUhKgAsAAAAAA==.Kiewkajee:BAAANQAECgUICgAAAA==.Kiosk:BAABNQAECoEcAAIQAAcKdBedrADeAQAQAAcKdBedrADeAQAAAA==.Kiwichaos:BAABNQAECoEoAAIbAAkKHhwiDwDXAgAbAAkKHhwiDwDXAgAAAA==.',
Kr='Krellis:BAABNQAECoEUAAIeAAcKYBwnGgAZAgAeAAcKYBwnGgAZAgAAAA==.',
Ku='Kurozuka:BAAANQADCgUIBQAAAA==.',
Kv='Kvôthe:BAAANQAECgQIBAAAAA==.',
Ky='Kynralol:BAAANQAFFAEIAQAAAA==.',
La='Lagalot:BAAANQAECgYICgAAAA==.',
Le='Legham:BAAANQADCgYIBAAAAA==.Legolazz:BAABNQAECoEgAAMKAAkKxhxSHADzAgAKAAkKxhxSHADzAgALAAQKUwxNQgDbAAAAAA==.Lenatheplug:BAACNQAFFIEHAAIJAAUKCxw9AgDeAQAJAAUKCxw9AgDeAQA1AAQKgRgAAgkACQqbIIgUAI0CAAkACQqbIIgUAI0CAAAA.',
Li='Lightfinder:BAAANQAECgEIAQAAAA==.',
Ll='Llewser:BAAANQAECgYIEgAAAA==.',
Lo='Loongzokluad:BAABNQAECoEgAAIZAAkKpxAFDgD0AQAZAAkKpxAFDgD0AQAAAA==.Louisvuitton:BAAANQAECgQJBQAAAA==.',
Lu='Luckydews:BAAANQAECgUIDgAAAA==.Lumina:BAAANQAECgcIBwABNQAFFAYIEQANAIIUAA==.',
['Lì']='Lìnkinbark:BAAANQADCgYIBQAAAA==.',
Ma='Madará:BAAANQADCgEIAQAAAA==.Maggot:BAAANQADCgUIDQAAAA==.Maÿcé:BAABNQAECoEWAAMXAAgKpAwjbQB/AQAXAAcKSgojbQB/AQAYAAMKpAkGEQGJAAAAAA==.',
Mi='Mirant:BAAANQADCggICAAAAA==.Mirisha:BAAANQABCgcJCQAAAA==.Miststep:BAAANQADCggJGAAAAA==.',
Mo='Mooferax:BAAANQADCggJCAAAAA==.Moondeity:BAAANQAECgUIBAAAAA==.Morphio:BAABNQAECoEgAAIKAAgK4iKSEwAnAwAKAAgK4iKSEwAnAwAAAA==.Morêl:BAAANQAECgEJAQAAAA==.',
My='Mystified:BAAANQAECgUIBQAAAA==.Mythira:BAAANQADCgMIAwABNQAECggIQQAMAEQfAA==.',
['Mà']='Màyce:BAAANQAECgcICwABNQAECggIFgAXAKQMAA==.',
Nb='Nb:BAABNQAECoEmAAITAAkKOBZ9DgCUAgATAAkKOBZ9DgCUAgAAAA==.',
Ne='Nelena:BAAANQADCgQIBAAAAA==.Ness:BAABNQAECoEiAAIMAAkKUiKJCQBPAwAMAAkKUiKJCQBPAwAAAA==.Nevell:BAAANQAECggIEAABNQAFFAUICQAEAAUUAA==.',
Ni='Nikola:BAABNQAECoEmAAQfAAkKcw9XEQDHAQAfAAkK3Q5XEQDHAQAcAAgKkwipSAB2AQAgAAQKSxHpMwARAQAAAA==.Nimro:BAACNQAFFIEKAAIZAAUKFBVRAQB2AQAZAAUKFBVRAQB2AQA1AAQKgS4AAhkACQrNIr0GALICABkACQrNIr0GALICAAAA.Niub:BAAANQADCggIEgAAAA==.',
No='Nongmicky:BAABNQAECoEXAAIhAAgK3B2JCgCVAgAhAAgK3B2JCgCVAgAAAA==.',
Nu='Nueng:BAAANQAECgMIAwAAAA==.Nuferax:BAAANQAECgQIBAAAAA==.Nuisadv:BAAANQAECgYIDAAAAA==.',
Oa='Oaf:BAAANQADCgEIAQAAAA==.',
Od='Oddesa:BAAANQADCggIDQAAAA==.',
Of='Offwithye:BAAANQAECgMIAwAAAA==.',
Ok='Okiji:BAAANQAECgUJDQAAAA==.',
Om='Ominae:BAAANQAECgQIBAAAAA==.',
Or='Oranlord:BAAANQADCggJCgAAAA==.Orgilord:BAAANQADCgcIBwAAAA==.',
Pa='Palliative:BAABNQAECoEkAAIXAAcKUxOCXwCsAQAXAAcKUxOCXwCsAQAAAA==.Pallidnim:BAAANQAECgcIEgAAAA==.Pallystine:BAAANQAECgcJEAAAAA==.Pandarendk:BAAANQADCggICQAAAA==.',
Pe='Pearson:BAAANQADCgQIBgAAAA==.',
Ph='Phatmage:BAABNQAECoEnAAIQAAkKLh8uOAD6AgAQAAkKLh8uOAD6AgABNQAFFAMIBQAEAN8SAA==.Phatmonk:BAAANQABCgIIAgABNQAFFAMIBQAEAN8SAA==.Phatpriest:BAAANQAECgYIBgABNQAFFAMIBQAEAN8SAA==.Phatwarlock:BAACNQAFFIEFAAMEAAMK3xIVHwChAAAEAAIK0BEVHwChAAAFAAEK/BQAAAAAAAA1AAQKgR4ABAQACQqzIY0HAG8DAAQACQqzIY0HAG8DAAYAAgp4FncYAIIAAAUAAQrhFlxiAEYAAAAA.',
Pi='Pix:BAACNQAFFIEPAAMPAAUKCCAuAwDdAQAPAAUKCCAuAwDdAQABAAIKphUNGgCqAAA1AAQKgR0AAg8ACQowJS4EAH8DAA8ACQowJS4EAH8DAAAA.',
Pl='Pleasuremax:BAABNQAECoEXAAIKAAgK3RMDUwAnAgAKAAgK3RMDUwAnAgAAAA==.',
Po='Poofyfeesh:BAAANQAECgcIEwAAAA==.Popshot:BAAANQADCgUICgAAAA==.Porpus:BAAANQADCgcIEAABNQAECgMIBQAHAAAAAA==.Porthub:BAAANQADCgUIBQAAAA==.',
Pr='Praxis:BAAANQAECgYIDwAAAA==.Preast:BAAANQADCggICAABNQAECgYJEQAHAAAAAA==.',
Py='Pyrusdk:BAABNQAECoEeAAMCAAkKGBQHMAAUAgACAAkKGBQHMAAUAgAMAAEKwg50rgAuAAAAAA==.Pyruslock:BAAANQAECggIAQAAAA==.',
Qe='Qermack:BAAANQADCgcJCQAAAA==.',
Ra='Raìn:BAAANQADCgUIBQAAAA==.',
Re='Rednutts:BAAANQAECgYICAAAAA==.Rekt:BAAANQAECgcICgAAAA==.',
Ri='Riggs:BAACNQAFFIEXAAMaAAcKBiLTAADoAgAaAAcKBiHTAADoAgAiAAUK5yA+AAAEAgA1AAQKgSEAAxoACQpcJrUIAJ4DABoACQo4JrUIAJ4DACIABArYJXELALwBAAAA.',
Rn='Rnc:BAABNQAECoEVAAICAAgKRx2MHACcAgACAAgKRx2MHACcAgAAAA==.',
Ro='Roaroaroar:BAAANQADCgYIBgAAAA==.Rodger:BAAANQAECgYJEQAAAA==.Ronfirestorm:BAAANQADCgYIDAABNQAECgkJFwAEAKcLAA==.Roninn:BAABNQAECoEiAAIgAAkK2iCaBABdAwAgAAkK2iCaBABdAwAAAA==.Ronlock:BAABNQAECoEXAAIEAAkKpwswhwByAQAEAAkKpwswhwByAQAAAA==.',
Rw='Rwen:BAABNQAECoErAAIKAAcKnQZLlwByAQAKAAcKnQZLlwByAQAAAA==.',
['Rô']='Rôlayne:BAAANQAECgEIAQAAAA==.',
Sa='Sadakos:BAAANQAECgQIEQAAAA==.Salvare:BAABNQAECoEYAAIjAAkKvROmBQBfAgAjAAkKvROmBQBfAgAAAA==.Sarielsia:BAAANQAECgQIBgAAAA==.Sarielsiá:BAAANQADCgYIBgABNQAECgQIBgAHAAAAAA==.Sauron:BAAANQADCgYIDwABNQAECggILwAEAOgiAA==.',
Sc='Sciodeekay:BAABNQAECoE4AAIMAAkK9R7DDgAUAwAMAAkK9R7DDgAUAwAAAA==.Sciohunter:BAAANQAECgMIAwAAAA==.Scioscioz:BAAANQAECgEIAQAAAA==.Scwisgar:BAABNQAECoEcAAIMAAgKVxn3JwBIAgAMAAgKVxn3JwBIAgAAAA==.',
Se='Sedge:BAABNQAECoEfAAIJAAkKLiKsBgA9AwAJAAkKLiKsBgA9AwAAAA==.Sewerface:BAAANQAECgQICAAAAA==.',
Sh='Shadowind:BAABNQAECoEoAAIKAAkKJB+6EwAmAwAKAAkKJB+6EwAmAwAAAA==.Shadowz:BAAANQADCgcIBwAAAA==.Shambulance:BAAANQADCggIFgAAAA==.Shammalxs:BAABNQAECoEoAAIIAAkKUx/sFwARAwAIAAkKUx/sFwARAwAAAA==.Shamoc:BAAANQAECgQIEAABNQAECgkJHgAgAIQiAA==.Shanki:BAAANQABCgMIAwAAAA==.Sharpknife:BAABNQAECoEZAAMLAAgK5yKkCQAcAwALAAgK8SCkCQAcAwAKAAYK3RePggCmAQAAAA==.Shiesty:BAAANQADCgUIBQAAAA==.Shivd:BAAANQAECgQIBAAAAA==.',
Sk='Skizzyy:BAAANQADCgQIBAABNQADCgYIBgAHAAAAAA==.',
Sl='Slowjoe:BAAANQAECgcIDwAAAA==.',
Sm='Smacedh:BAAANQADCgIIAgAAAA==.Smallheals:BAAANQADCgEJAQAAAA==.',
Sn='Sneakyfella:BAAANQAECgcJCAAAAA==.Sneekin:BAAANQADCgMIAwAAAA==.',
So='Solidus:BAAANQAECggICAAAAA==.',
Sp='Spardã:BAAANQAECgYIBgAAAA==.Spoonfed:BAAANQAECgIIAgAAAA==.',
Sq='Squiish:BAAANQAECgcICAAAAA==.',
St='Starwraith:BAAANQADCgYIBgABNQAFFAMIBQAIAHELAA==.Stgeorge:BAABNQAECoEYAAIUAAgKtwnECQCEAQAUAAgKtwnECQCEAQAAAA==.Stickypriest:BAABNQAECoFBAAMPAAgKhSAGDgDfAgAPAAgKhSAGDgDfAgABAAIKPhtargCQAAAAAA==.Strawhats:BAACNQAFFIEXAAMQAAcK8B+LBAA8AgAQAAYKpB+LBAA8AgARAAEKtSFEBgBlAAA1AAQKgSEAAhAACQrcJOUTAHQDABAACQrcJOUTAHQDAAAA.Streamliner:BAABNQAECoEaAAIWAAkKGw3wFwD6AQAWAAkKGw3wFwD6AQAAAA==.Stunks:BAAANQAECgEIAQAAAA==.',
Su='Sultan:BAAANQADCgYIDAAAAA==.',
Sy='Sy:BAAANQADCggIDQAAAA==.',
Ta='Talletalanot:BAAANQAECgIIBwABNQAECgkJHwAIALsfAA==.Tarlenm:BAABNQAECoEeAAMgAAkKhCLpAgCGAwAgAAkKhCLpAgCGAwAfAAEKZw/6PgA1AAAAAA==.',
Td='Tdk:BAAANQAECgIIAgAAAA==.',
Te='Terrafirm:BAAANQADCgQJBAAAAA==.Testaltesta:BAAANQADCggIDgAAAA==.Testaxltesta:BAAANQAECgUICQABNQADCggIDgAHAAAAAA==.',
Th='Thon:BAAANQAECgcIEwAAAA==.Thunderbelly:BAABNQAECoEbAAINAAgKSBphNgBAAgANAAgKSBphNgBAAgAAAA==.',
To='Totems:BAACNQAFFIERAAINAAYKghTtAwD3AQANAAYKghTtAwD3AQA1AAQKgS4AAw0ACQoJJV4BAMUDAA0ACQoJJV4BAMUDAAgAAQosCTH4ADYAAAAA.',
Tr='Traktorbeam:BAAANQADCgYIDwAAAA==.Trass:BAABNQAECoEvAAQEAAkKACA6CgBWAwAEAAkKACA6CgBWAwAFAAMKgxQrOwDAAAAGAAEKyg1sJgA4AAAAAA==.Trisse:BAAANQAECgQICAAAAA==.',
Tu='Tuzz:BAABNQAECoEhAAISAAkKkiHUBwBDAwASAAkKkiHUBwBDAwAAAA==.',
Un='Unphayzed:BAAANQADCgYIBgAAAA==.',
Va='Vaelreth:BAAANQADCgcIBwAAAA==.Varaestia:BAAANQAECgUIEwAAAA==.Varg:BAAANQAECggIEgAAAA==.Varthloukker:BAAANQABCgQIBQAAAA==.',
Ve='Vermeil:BAAANQAECgMIBAAAAA==.Vermillion:BAABNQAECoEcAAIOAAkKEhedEQA4AgAOAAkKEhedEQA4AgAAAA==.Verzik:BAAANQAECgUIDAAAAA==.',
Vi='Vib:BAAANQAECgQIDQAAAA==.Vicia:BAAANQADCgYIBwAAAA==.Viczrei:BAAANQAECgcIDAAAAA==.',
Vr='Vråg:BAAANQADCggIDwAAAA==.',
Vv='Vvenator:BAAANQAECgQIDAAAAA==.',
Vy='Vynessa:BAABNQAECoEcAAIXAAcKxyMqGwDcAgAXAAcKxyMqGwDcAgAAAA==.',
['Vè']='Vèè:BAAANQAECgUJBQABNQAECgkJGwAJALsbAA==.',
Wa='Wakkytabbaky:BAAANQAECgQJBAAAAA==.Waterwaterz:BAABNQAECoEpAAMQAAkK6BQyggA/AgAQAAkKJRMyggA/AgARAAMKZRLVHwCuAAAAAA==.Waylm:BAAANQAECgcIDgABNQAFFAUICQAEAAUUAA==.',
Wc='Wchin:BAABNQAECoEdAAIQAAkKdB9vKgAjAwAQAAkKdB9vKgAjAwAAAA==.',
We='Weareleigon:BAAANQAECggICAAAAA==.Wedlock:BAAANQADCgQJBAAAAA==.Welcumshot:BAAANQAECgYIBgAAAA==.Wendyy:BAAANQAECgQICAABNQAFFAcICQAEAEETAA==.',
Wh='Whaka:BAABNQAECoEYAAMKAAkKzhz3HADvAgAKAAkKzhz3HADvAgALAAEKGxEBZgA+AAAAAA==.',
Wo='Wound:BAAANQADCgEIAgABNQAECgkJLgAkAPMiAA==.',
Xi='Xiera:BAAANQAECgQIBAAAAA==.',
Ya='Yamiprays:BAAANQAECgMIAwAAAA==.',
Yo='Yozzao:BAAANQADCggIDAAAAA==.',
Za='Zaler:BAAANQAECgUIBQAAAA==.',
Ze='Zenak:BAAANQAECgMIAwAAAA==.Zenath:BAAANQAECggIEwABNQAFFAUICQAEAAUUAA==.Zerithra:BAABNQAECoFBAAIMAAgKRB/hGgClAgAMAAgKRB/hGgClAgAAAA==.',
Zi='Zilbam:BAAANQAECgUIBQAAAA==.Zinaak:BAAANQAECgIIAgAAAA==.',
Zm='Zmonk:BAAANQADCgEIAQAAAA==.',
Zz='Zzdeathnight:BAAANQAECgEIAQAAAA==.Zzdruid:BAAANQADCgcIDQAAAA==.',
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
