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

local lookup = {'Priest-Holy','DeathKnight-Unholy','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Rogue-Assassination','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Shaman-Restoration','Paladin-Protection','Priest-Shadow','DeathKnight-Frost','Evoker-Preservation','Mage-Arcane','Paladin-Holy','Paladin-Retribution','Shaman-Elemental','DemonHunter-Devourer','Warrior-Protection','Druid-Guardian','Druid-Balance','Druid-Restoration','Shaman-Enhancement','Warrior-Fury','Warrior-Arms','Mage-Frost',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaric:BAAANQADCgUICQAAAA==.',
Ae='Aedaris:BAABNQAECoEvAAIBAAgKphRXOAAMAgABAAgKphRXOAAMAgAAAA==.',
Ak='Akirik:BAAANQADCgYJCQAAAA==.',
Al='Alf:BAAANQADCgYIEgAAAA==.Allayt:BAAANQAECgQIBAAAAA==.Aloremirin:BAAANQADCgMIAwAAAA==.',
Am='Ametrigos:BAAANQAECgUJCgAAAA==.',
Ar='Artzlayer:BAABNQAECoEdAAICAAkKKh7LDQAWAwACAAkKKh7LDQAWAwAAAA==.Aríes:BAABNQAECoEzAAIDAAgKAxLmIAASAgADAAgKAxLmIAASAgAAAA==.',
As='Ashbourne:BAAANQAECgYIDAAAAA==.',
Av='Avakyn:BAAANQAECgcJCgAAAA==.',
Aw='Awry:BAEBNQAECoEvAAICAAgK2hw1GQCeAgACAAgK2hw1GQCeAgAAAA==.Awuuga:BAAANQAECgIIAgABNQAECgcIHgAEAL0PAA==.Aww:BAAANQADCgEIAQAAAA==.',
Az='Azmo:BAACNQAFFIEGAAMEAAMKrwyKFgCjAAAEAAIKBBGKFgCjAAAFAAEKBgQXFgBIAAA1AAQKgSAABAUACQrUIAwDAPYCAAUACArsIAwDAPYCAAQABgrQHFNQAN8BAAYAAgoHIe4TAIsAAAAA.',
Ba='Badds:BAAANQAECgEJAQAAAA==.Barad:BAAANQADCgMIAwAAAA==.',
Be='Beastroll:BAAANQADCggJEAAAAA==.Berserkk:BAAANQAECgcJBwAAAA==.Bewbs:BAAANQAECgQICQABNQAECgcJCQAHAAAAAA==.',
Bi='Bicksmage:BAAANQAECgcJEQAAAA==.Bigdaddyclap:BAAANQAECgYIBwABNQAFFAcJEQAEAB8XAA==.Bigdaddylock:BAACNQAFFIERAAQEAAcKHxeaAwCrAQAEAAUKRBKaAwCrAQAFAAIKwSIsAwDOAAAGAAEK9BxrBABZAAA1AAQKgRwABAQACQrxIlcdALgCAAQACAquIlcdALgCAAUABgpHGKoWAJ8BAAYAAQrgJrYVAHQAAAAA.',
Bl='Blerdwerd:BAAANQADCgYIBgABNQAECgYJBgAHAAAAAA==.',
Bo='Bobafatt:BAAANQADCgcJFAAAAA==.Bombdiggity:BAAANQAECgIJAwAAAA==.Bonnierotted:BAAANQAECgQIBAABNQAECgkJFwAIAJsgAA==.',
Br='Brallix:BAAANQAECgQIBAABNQAECgkJKAAEAIokAA==.Bräinfreeze:BAAANQAECggIBwAAAA==.',
['Bã']='Bãllz:BAAANQABCgQIBAAAAA==.',
Ca='Cakebringer:BAAANQAECgEJAQAAAA==.Catrit:BAAANQADCgIIAgAAAA==.',
Ch='Chich:BAAANQADCgQIBAAAAA==.Christina:BAAANQAECgMIAwAAAA==.Chud:BAAANQAECgUJCQABNQAECgUJDAAHAAAAAA==.',
Ci='Cig:BAAANQADCgIIAgAAAA==.',
Cl='Clocky:BAAANQAECgcJDAAAAA==.Cloneofhunt:BAACNQAFFIEFAAIJAAMKsiI5BgA2AQAJAAMKsiI5BgA2AQA1AAQKgRkAAwkACQrhJQEDALgDAAkACQrhJQEDALgDAAoAAgrPEqpGAIoAAAAA.',
Co='Cocopop:BAAANQADCgQIBAAAAA==.Combustanut:BAAANQADCgMIAwAAAA==.Comillazz:BAABNQAECoEaAAILAAgKhBZpKgAJAgALAAgKhBZpKgAJAgAAAA==.',
Cr='Crusher:BAAANQAECgIJAgABNQAFFAUICwAMANkRAA==.',
Cu='Cultiran:BAAANQAECgUJDAAAAA==.Curby:BAABNQAECoEzAAINAAgKqw2rGgCKAQANAAgKqw2rGgCKAQAAAA==.Cursedfennec:BAAANQADCgIJAgAAAA==.',
Da='Damge:BAAANQAECgQIBgAAAA==.Damnnyou:BAAANQAECgcJEgAAAA==.Dandiwa:BAAANQADCgMIAwAAAA==.Danky:BAAANQAECgQICAAAAA==.',
De='Deadicated:BAABNQAECoEtAAIBAAgKChEvPQD0AQABAAgKChEvPQD0AQAAAA==.Deathshunter:BAAANQAECgYIDQABNQAECgkJIAACACYlAA==.Debsi:BAAANQAECgIIAgAAAA==.Declined:BAAANQAECgQIBgAAAA==.Deeper:BAAANQAECggICwAAAA==.Deepest:BAAANQAECggIEQAAAA==.Deloraine:BAACNQAFFIEaAAMOAAYK7SO7BQAyAQAOAAMKlCK7BQAyAQABAAMK7gjrDgDoAAA1AAQKgTsAAw4ACQpvIScEAH8DAA4ACQpvIScEAH8DAAEAAQoxBdCmAD8AAAAA.Demonblaze:BAAANQADCgQIBAAAAA==.Demonicfaith:BAAANQADCggIEAABNQAECgkJFwAEAKcLAA==.Dendrendas:BAAANQADCgQIBAAAAA==.Destrohacka:BAAANQAECgYIDwAAAA==.',
Di='Disckin:BAAANQADCgEIAQAAAA==.',
Dr='Dracaena:BAAANQAECgQJBAABNQAECgcJEgAHAAAAAA==.Dracodeath:BAABNQAECoEeAAIPAAkK8h55CgAAAwAPAAkK8h55CgAAAwAAAA==.Dracular:BAABNQAECoEdAAIQAAgKOBOoFAAGAgAQAAgKOBOoFAAGAgAAAA==.Draining:BAABNQAECoEWAAMEAAgKyxuDKgB3AgAEAAgKpxqDKgB3AgAGAAEK/CTRFgBrAAAAAA==.Drakos:BAAANQAECgEIAQAAAA==.Drownedfish:BAAANQADCgIJAgAAAA==.',
Ed='Edifis:BAAANQADCgYIBgAAAA==.',
Ej='Ejzok:BAABNQAECoEbAAIRAAcKthwtYABuAgARAAcKthwtYABuAgAAAA==.Ejzox:BAAANQAECgcIEgABNQAECgcIGwARALYcAA==.',
El='Elibaba:BAAANQAECgcJDgAAAA==.',
Em='Emopapa:BAABNQAECoEvAAILAAkKwSG2BwBWAwALAAkKwSG2BwBWAwAAAA==.',
En='Endlessdh:BAAANQAECgEIAQAAAA==.',
Er='Erihunter:BAAANQAECgIIAgAAAA==.Err:BAAANQAECggJEAAAAA==.',
Ez='Ezelia:BAABNQAECoEiAAMSAAkK3RbkbQBJAQASAAkK3RbkbQBJAQATAAcKqgpZlwBAAQABNQAFFAUJDQABAMoTAA==.',
Fa='Faelune:BAAANQADCggJDAAAAA==.',
Fl='Flameshock:BAAANQADCgcIBwAAAA==.Flesh:BAAANQADCggIDwAAAA==.',
Fu='Fullmoonride:BAAANQADCgYJCgAAAA==.Funkymajik:BAAANQADCggJFgAAAA==.Furiosa:BAAANQABCgYIBgAAAA==.Furyfork:BAAANQAECgcICwAAAA==.',
Ga='Ganin:BAAANQAECgYIDwAAAA==.Garugala:BAABNQAECoEaAAITAAgKriIuGAAbAwATAAgKriIuGAAbAwAAAA==.',
Ge='Gengár:BAAANQADCggJEAABNQAECgEIAgAHAAAAAA==.',
Gh='Ghalorin:BAAANQAECgMIAwAAAA==.',
Gi='Gigachad:BAAANQAECggJEAAAAA==.Gingarthas:BAAANQAECgUIDgAAAA==.',
Gr='Grapespliter:BAAANQAECgYIDQAAAA==.Grimefiend:BAAANQAFFAEJAQAAAA==.Grimetime:BAABNQAECoEVAAIRAAgKGhcSXwBxAgARAAgKGhcSXwBxAgABNQAFFAEJAQAHAAAAAA==.Grriinn:BAAANQAECgYIBgAAAA==.',
Ha='Handwarm:BAABNQAECoEYAAIUAAcKWBFtSgDJAQAUAAcKWBFtSgDJAQAAAA==.Hanokano:BAAANQADCgYIBgABNQAECgkJJgAEABEdAA==.',
He='Heartdh:BAAANQAECgcJEQAAAA==.Hellkai:BAABNQAECoEhAAMGAAcKCCP1AQDKAgAGAAcKCCP1AQDKAgAEAAQKYBaCkAAWAQAAAA==.Herrion:BAABNQAECoEoAAMEAAkKiiT3FgDfAgAEAAcKjST3FgDfAgAFAAUKMBeKGACOAQAAAA==.',
Hi='Hippy:BAAANQAFFAMJAwAAAA==.',
Ho='Hog:BAAANQAECgUJCAABNQAFFAMJAwAHAAAAAA==.Holytanky:BAAANQADCgMIBgAAAA==.',
Hu='Hukani:BAAANQAECgQIBwAAAA==.Huskar:BAAANQAECgQJCgAAAA==.',
Hw='Hwanjeabb:BAABNQAECoEXAAILAAgKqRE7NgDAAQALAAgKqRE7NgDAAQAAAA==.',
Ig='Ignis:BAAANQAECgcJDgAAAA==.',
Il='Ilillillill:BAAANQADCgcJBwAAAA==.Illiroman:BAAANQAECgcIEAAAAA==.',
Im='Imntprepared:BAAANQAECgcJCAAAAA==.',
In='Infectîon:BAAANQAECggJEwAAAA==.',
Ji='Jimjum:BAABNQAECoEnAAIBAAkKrxdkHQCfAgABAAkKrxdkHQCfAgAAAA==.',
Ju='Jubeaint:BAAANQADCgYIDAABNQAECgYIEwAHAAAAAA==.',
Ka='Kaaru:BAAANQAECgcJEwAAAA==.Kagarl:BAAANQAECgIJAwABNQAECgkJKAAEAIokAA==.Kaiforst:BAAANQADCggJCAABNQAECggJGQATAKQZAA==.Kairon:BAABNQAECoEZAAITAAgKpBnPQABPAgATAAgKpBnPQABPAgAAAA==.',
Ki='Kickstarter:BAABNQAECoEeAAQEAAcKvQ+2gwA5AQAEAAUK1Q+2gwA5AQAFAAIKgA+oSwB4AAAGAAEKcwW6JAAtAAAAAA==.Kiewkajee:BAAANQAECgQIBAAAAA==.Kiosk:BAABNQAECoEcAAIRAAcKcxdDjgD0AQARAAcKcxdDjgD0AQAAAA==.Kiwichaos:BAABNQAECoElAAIVAAkK+BdNDwDCAgAVAAkK+BdNDwDCAgAAAA==.',
Kr='Krellis:BAAANQAECgcJEgAAAA==.',
Ku='Kurozuka:BAAANQADCgUIBQAAAA==.',
Kv='Kvôthe:BAAANQADCggJFgAAAA==.',
Ky='Kynralol:BAAANQAFFAEIAQAAAA==.',
La='Lagalot:BAAANQAECgMIBAAAAA==.',
Le='Legham:BAAANQADCgYIBAAAAA==.Legolazz:BAABNQAECoEXAAMJAAgKsxqSKACTAgAJAAgKsxqSKACTAgAKAAIKbghgTgBrAAAAAA==.Lenatheplug:BAABNQAECoEXAAIIAAkKmyCfBwARAwAIAAkKmyCfBwARAwAAAA==.',
Li='Lightfinder:BAAANQAECgEIAQAAAA==.',
Ll='Llewser:BAAANQAECgUJDQAAAA==.',
Lo='Loongzokluad:BAABNQAECoEZAAIWAAkKQg5hDADdAQAWAAkKQg5hDADdAQAAAA==.Louisvuitton:BAAANQAECgQJBQAAAA==.',
Lu='Luckydews:BAAANQAECgUIDgAAAA==.',
['Lì']='Lìnkinbark:BAAANQADCgYIBQAAAA==.',
Ma='Maggot:BAAANQADCgUIDQAAAA==.Maÿcé:BAABNQAECoEUAAMSAAcKWQ0nbABOAQASAAYKugonbABOAQATAAMKpAkh5ACTAAAAAA==.',
Mi='Mirant:BAAANQADCggICAAAAA==.Mirisha:BAAANQABCgcJCQAAAA==.Miststep:BAAANQADCggJGAAAAA==.',
Mo='Mooferax:BAAANQADCggJCAAAAA==.Moondeity:BAAANQAECgUIBAAAAA==.Morphio:BAABNQAECoEYAAIJAAgKCSFoEwAJAwAJAAgKCSFoEwAJAwAAAA==.Morêl:BAAANQAECgEJAQAAAA==.',
My='Mystified:BAAANQADCgYIBgAAAA==.Mythira:BAAANQADCgMIAwABNQAECggJMwALAJoeAA==.',
['Mà']='Màyce:BAAANQAECgUIBQABNQAECggIFAASAFkNAA==.',
Nb='Nb:BAABNQAECoEdAAIQAAkKaRLLDwBcAgAQAAkKaRLLDwBcAgAAAA==.',
Ne='Nelena:BAAANQADCgIIAgAAAA==.Ness:BAABNQAECoEeAAILAAkKvyElCABPAwALAAkKvyElCABPAwAAAA==.Nevell:BAAANQAECggIDgABNQAECgkJKAAEAIokAA==.',
Ni='Nikola:BAABNQAECoEkAAQXAAkKtw32DQC0AQAXAAkKIQ32DQC0AQAYAAgKkwjNPQCGAQAZAAQKSxHvKwAVAQAAAA==.Nimro:BAABNQAECoEoAAIWAAkKbCHVAQBrAwAWAAkKbCHVAQBrAwAAAA==.Niub:BAAANQADCggIEgAAAA==.',
No='Nongmicky:BAABNQAECoEXAAIaAAgK3B3PBwCxAgAaAAgK3B3PBwCxAgAAAA==.',
Nu='Nueng:BAAANQAECgMJAwAAAA==.Nuferax:BAAANQADCggJFgAAAA==.Nuisadv:BAAANQAECgYJDAAAAA==.',
Oa='Oaf:BAAANQADCgEIAQAAAA==.',
Ok='Okiji:BAAANQAECgUJDQAAAA==.',
Om='Ominae:BAAANQAECgQIBAAAAA==.',
Or='Oranlord:BAAANQADCggJCgAAAA==.Orgilord:BAAANQADCgcIBwAAAA==.',
Pa='Palliative:BAABNQAECoEYAAISAAcK3RK9UACvAQASAAcK3RK9UACvAQAAAA==.Pallidnim:BAAANQAECgcJDQAAAA==.Pallystine:BAAANQAECgcJEAAAAA==.Pandarendk:BAAANQADCggICQAAAA==.',
Pe='Pearson:BAAANQADCgQIBgAAAA==.',
Ph='Phatmage:BAABNQAECoEjAAIRAAkK6B4LNADxAgARAAkK6B4LNADxAgABNQAECgkJEwAEAGQeAA==.Phatpriest:BAAANQADCgUIBQABNQAECgkJEwAEAGQeAA==.Phatwarlock:BAABNQAECoETAAMEAAkKZB71CgA2AwAEAAkKZB71CgA2AwAGAAIKeBY0FACHAAAAAA==.',
Pi='Pix:BAACNQAFFIEKAAMOAAUKmBsXBAB2AQAOAAQK+h0XBAB2AQABAAIKphXKEgCuAAA1AAQKgR0AAg4ACQowJf8BALIDAA4ACQowJf8BALIDAAAA.',
Pl='Pleasuremax:BAAANQAECgYIDwAAAA==.',
Po='Poofyfeesh:BAAANQAECgcJDgAAAA==.Popshot:BAAANQADCgUICgAAAA==.Porpus:BAAANQADCgcIEAABNQAECgIJAgAHAAAAAA==.',
Pr='Praxis:BAAANQAECgYIDwAAAA==.Preast:BAAANQADCggICAABNQAECgYJEQAHAAAAAA==.',
Py='Pyrusdk:BAABNQAECoEdAAMCAAkKGBReIQBZAgACAAkKGBReIQBZAgALAAEKwg6AmgAuAAAAAA==.',
Qe='Qermack:BAAANQADCgcJCQAAAA==.',
Ra='Raìn:BAAANQADCgUIBQAAAA==.',
Re='Rednutts:BAAANQAECgYICAAAAA==.Rekt:BAAANQAECgcJCQAAAA==.',
Ri='Riggs:BAACNQAFFIEQAAMbAAYKdCUfAAAHAgAbAAUK5yAfAAAHAgAcAAUKCSJKBAD4AQA1AAQKgR8AAxwACQpYJqgGAKcDABwACQrJJagGAKcDABsABArYJRIJAMIBAAAA.',
Rn='Rnc:BAAANQAECgcIDQAAAA==.',
Ro='Rodger:BAAANQAECgYJEQAAAA==.Ronfirestorm:BAAANQADCgYIDAABNQAECgkJFwAEAKcLAA==.Roninn:BAABNQAECoEZAAIZAAgKIyDhCADkAgAZAAgKIyDhCADkAgAAAA==.Ronlock:BAABNQAECoEXAAIEAAkKpwvCbAB+AQAEAAkKpwvCbAB+AQAAAA==.',
Rw='Rwen:BAABNQAECoErAAIJAAcKnQameQCCAQAJAAcKnQameQCCAQAAAA==.',
['Rô']='Rôlayne:BAAANQADCggJJAAAAA==.',
Sa='Sadakos:BAAANQAECgQJDQAAAA==.Salvare:BAAANQAECggJEAAAAA==.Sarielsia:BAAANQAECgEIAgAAAA==.Sarielsiá:BAAANQADCgYIBgABNQAECgEIAgAHAAAAAA==.Sauron:BAAANQADCgYIDwABNQAECggIIwAcAP8aAA==.',
Sc='Sciodeekay:BAABNQAECoExAAILAAkKUR7WDAARAwALAAkKUR7WDAARAwAAAA==.Sciohunter:BAAANQAECgMIAwAAAA==.Scioscioz:BAAANQAECgEIAQAAAA==.Scwisgar:BAAANQAECgYIEQAAAA==.',
Se='Sedge:BAABNQAECoEaAAIIAAkK4yB6BQA7AwAIAAkK4yB6BQA7AwAAAA==.Sewerface:BAAANQAECgQICAAAAA==.',
Sh='Shadowind:BAABNQAECoEhAAIJAAgKph6dGwDUAgAJAAgKph6dGwDUAgAAAA==.Shambulance:BAAANQADCggJDQAAAA==.Shammalxs:BAABNQAECoElAAIUAAkKxB1TFgD7AgAUAAkKxB1TFgD7AgAAAA==.Shamoc:BAAANQAECgQJDAABNQAECgcJEwAHAAAAAA==.Sharpknife:BAAANQAFFAEJAQAAAA==.Shiesty:BAAANQADCgUIBQAAAA==.Shivd:BAAANQADCgUIBQAAAA==.',
Sk='Skizzyy:BAAANQADCgQIBAABNQAECgkJHQAUAOITAA==.',
Sl='Slowjoe:BAAANQAECgcIDwAAAA==.',
Sm='Smacedh:BAAANQADCgIIAgAAAA==.Smallheals:BAAANQADCgEJAQAAAA==.',
Sn='Sneakyfella:BAAANQAECgcJCAAAAA==.',
So='Solidus:BAAANQADCggIBgAAAA==.',
Sp='Spoonfed:BAAANQAECgIIAgAAAA==.',
Sq='Squiish:BAAANQAECgcICAAAAA==.',
St='Starwraith:BAAANQADCgYIBgAAAA==.Stgeorge:BAAANQAECggIEAAAAA==.Stickypriest:BAABNQAECoEzAAMOAAgKJxyKDwCnAgAOAAgKJxyKDwCnAgABAAIKPhuhkgCTAAAAAA==.Strawhats:BAACNQAFFIEWAAMRAAcKkR9IAgBTAgARAAYKNR9IAgBTAgAdAAEKtSGIAwBrAAA1AAQKgR4AAhEACQrVJAMNAI4DABEACQrVJAMNAI4DAAAA.Streamliner:BAAANQAECgcIEAAAAA==.Stunks:BAAANQAECgEIAQAAAA==.',
Su='Sultan:BAAANQADCgYIDAAAAA==.',
Sy='Sy:BAAANQADCggIDQAAAA==.',
Ta='Talletalanot:BAAANQAECgIJBgABNQAECggJGAAUAP4fAA==.Tarlenm:BAAANQAECgcJEwAAAA==.',
Te='Terrafirm:BAAANQADCgQJBAAAAA==.Testaltesta:BAAANQADCggIDgAAAA==.Testaxltesta:BAAANQAECgUICQABNQADCggIDgAHAAAAAA==.',
Th='Thon:BAAANQAECgcJEQAAAA==.Thunderbelly:BAAANQAECgYJEwAAAA==.',
To='Totems:BAACNQAFFIELAAIMAAUK2RHzBACZAQAMAAUK2RHzBACZAQA1AAQKgSoAAwwACQoJJfMAANEDAAwACQoJJfMAANEDABQAAQosCZDWADgAAAAA.',
Tr='Traktorbeam:BAAANQADCgYICwAAAA==.Trass:BAABNQAECoEmAAQEAAkKER36HwCqAgAEAAgK3Bz6HwCqAgAFAAMKgxR3NgDEAAAGAAEKyg0gIQA5AAAAAA==.Trisse:BAAANQAECgQIBAAAAA==.',
Tu='Tuzz:BAABNQAECoEaAAIPAAkKWR+KCgD/AgAPAAkKWR+KCgD/AgAAAA==.',
Un='Unphayzed:BAAANQADCgYIBgABNQAECggJGAAIAGAZAA==.',
Va='Vaelreth:BAAANQADCgcIBwAAAA==.Varaestia:BAAANQAECgUIDwAAAA==.Varg:BAAANQAECgcJEQAAAA==.Varthloukker:BAAANQABCgQIBQAAAA==.',
Ve='Vermeil:BAAANQAECgEIAQAAAA==.Vermillion:BAABNQAECoEZAAINAAkKvxbcCwBnAgANAAkKvxbcCwBnAgAAAA==.Verzik:BAAANQAECgQJBAAAAA==.',
Vi='Vib:BAAANQAECgQJCQAAAA==.Vicia:BAAANQADCgYIBwAAAA==.Viczrei:BAAANQAECgcJDAAAAA==.',
Vv='Vvenator:BAAANQAECgQJBwAAAA==.',
Vy='Vynessa:BAABNQAECoEXAAISAAcKvSCgHwCcAgASAAcKvSCgHwCcAgAAAA==.',
['Vè']='Vèè:BAAANQAECgUJBQABNQAECggJEAAHAAAAAA==.',
Wa='Wakkytabbaky:BAAANQAECgQJBAAAAA==.Waterwaterz:BAABNQAECoEmAAMRAAkK6BRMaQBVAgARAAkKJRNMaQBVAgAdAAMKZRJMGQC4AAAAAA==.Waylm:BAAANQADCggICAABNQAECgkJKAAEAIokAA==.',
Wc='Wchin:BAABNQAECoEYAAIRAAgKVBw8TgCgAgARAAgKVBw8TgCgAgAAAA==.',
We='Weareleigon:BAAANQADCgYJDAAAAA==.Wedlock:BAAANQADCgQJBAAAAA==.Wendyy:BAAANQAECgQICAABNQAECgkJHQAFAIUeAA==.',
Wh='Whaka:BAAANQAECgcIDwAAAA==.',
Wo='Wound:BAAANQADCgEIAgAAAA==.',
Xi='Xiera:BAAANQADCggJEAAAAA==.',
Yo='Yozzao:BAAANQADCggIDAAAAA==.',
Ze='Zenak:BAAANQAECgMJAwAAAA==.Zenath:BAAANQAECgcJCgABNQAECgkJKAAEAIokAA==.Zerithra:BAABNQAECoEzAAILAAgKmh57FwCfAgALAAgKmh57FwCfAgAAAA==.',
Zi='Zinaak:BAAANQAECgIJAgAAAA==.',
Zm='Zmonk:BAAANQADCgEJAQAAAA==.',
Zz='Zzdeathnight:BAAANQAECgEIAQAAAA==.Zzdruid:BAAANQADCgcIDQAAAA==.',
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
