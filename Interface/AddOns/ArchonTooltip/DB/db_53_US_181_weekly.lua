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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Priest-Holy','Shaman-Elemental','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Blood','Warrior-Fury','Druid-Restoration','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Hunter-Marksmanship','Warlock-Affliction','Warlock-Destruction','Monk-Windwalker','Monk-Brewmaster','Priest-Shadow','DemonHunter-Havoc','Druid-Balance','Mage-Frost','Hunter-Survival','DemonHunter-Devourer','Mage-Arcane','Rogue-Outlaw',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abert:BAAANQAECgUIEAAAAA==.',
Ac='Acts:BAAANQADCgYICgAAAA==.',
Ad='Adalinda:BAAANQADCgQIBAABNQAECgoKLwABAIgiAA==.Adra:BAAANQADCggICAAAAA==.Adrelorà:BAAANQADCgcIDQAAAA==.',
Ae='Aerähn:BAAANQABCggIKwAAAA==.',
Ag='Agathahaknes:BAAANQADCgEIAQAAAA==.Agnor:BAABNQAECn8nAAICAAcKrBYATQDgAQACAAcKrBYATQDgAQAAAA==.',
Ai='Aindria:BAAANQADCggICAAAAA==.',
Al='Alatir:BAAANQADCgYIFAAAAA==.',
Am='Ameri:BAAANQAECgEIAQABNQAFFAcIEAADANYbAA==.Ammeka:BAAANQABCggIEgAAAA==.',
An='Anahline:BAAANQAECgEIAQAAAA==.Andre:BAAANQAECggICAABNQAFFAUIDgAEANIQAA==.Anjaini:BAAANQADCgEJAQAAAA==.Antibubble:BAABNQAECn8xAAIDAAoKMB9GFADqAgADAAoKMB9GFADqAgAAAA==.Antimatter:BAAANQAFFAEIAQAAAA==.Anwal:BAABNQAECn8vAAMBAAoKiCKvCgAcAwABAAoKiCKvCgAcAwAFAAcKRQ7g4wBUAQAAAA==.',
Ar='Arceilth:BAAANQAECgQIBQAAAA==.Argus:BAAANQADCgIIAgAAAA==.Arissidis:BAAANQAECgEIAQAAAA==.Arithfury:BAABNQAECn8rAAIGAAkKchlSRAC+AQAGAAkKchlSRAC+AQAAAA==.Arkaius:BAAANQADCggICgAAAA==.Articuno:BAAANQADCgUICQAAAA==.',
As='Ashwynn:BAAANQAECgUICQAAAA==.Aske:BAAANQAECgUIBwAAAA==.',
At='Atalnoa:BAAANQADCgYICAAAAA==.',
Au='Aura:BAAANQADCgIIAgABNQAECgkJHgAHAEYSAA==.',
Az='Azuresun:BAABNQAECn8bAAIIAAUK3AfYewCnAAAIAAUK3AfYewCnAAAAAA==.',
Ba='Ballak:BAAANQAECgIIAgAAAA==.Bambeeno:BAAANQABCgYIBgAAAA==.Barnardo:BAAANQABCgIJAgAAAA==.Bassmasta:BAABNQAECn8mAAIJAAoKBR9mHAAmAwAJAAoKBR9mHAAmAwAAAA==.Baston:BAAANQADCgQIBAAAAA==.',
Be='Beatin:BAAANQAECgQIBwAAAA==.Belinda:BAAANQAECgIIAgAAAA==.Bentö:BAAANQADCgcIBwAAAA==.Beny:BAAANQAECgYIEQAAAA==.',
Bi='Biscüits:BAAANQADCgQIBAAAAA==.',
Bl='Blackskillz:BAAANQAECgMIAwABNQAECggIIgAGAJ8TAA==.Bloodstorm:BAAANQAECgIIAQAAAA==.Bloopydoo:BAAANQAECgUIDAAAAA==.Bluefisch:BAAANQADCgEIAQAAAA==.',
Bo='Boiorix:BAAANQADCgEIAQABNQAECgQIBwAKAAAAAA==.Borim:BAAANQAECgYIBwAAAA==.',
Br='Braincell:BAAANQAECgQIBAAAAA==.Brandymae:BAAANQADCgYIBgAAAA==.Brassidas:BAAANQAECgEIAQAAAA==.Brbpoopin:BAAANQADCgYIDwAAAA==.Bromancehomo:BAAANQADCgUIBgAAAA==.Bruwdfyre:BAAANQAECggIEQAAAA==.',
Bu='Bubbleshield:BAAANQADCgcIBwAAAA==.',
Ca='Castani:BAAANQAECgcIEAAAAA==.',
Ce='Celestyal:BAAANQAECgQIBwAAAA==.',
Ch='Choshi:BAAANQADCgMIAwABNQAECgUIDgAKAAAAAA==.',
Ci='Cindy:BAAANQAECgcICwABNQAECggIIgAKAAAAAQ==.',
Co='Confidential:BAAANQADCgIIAgAAAA==.Cootpal:BAABNQAECn8yAAIFAAoKGxlfUQChAgAFAAoKGxlfUQChAgAAAA==.',
Cr='Crazyloon:BAAANQAECgYIEAAAAA==.Crewdle:BAAANQADCggICAAAAA==.',
Cy='Cynawyne:BAAANQABCgMIAwABNQADCgcIFQAKAAAAAA==.Cynthea:BAAANQABCgYIDQAAAA==.',
['Cö']='Cörinthian:BAAANQADCgEIAQAAAA==.',
Da='Daddybod:BAABNQAECn8nAAMDAAkKhQ3eKACOAQADAAkKhQ3eKACOAQALAAYKlAbWUQChAAAAAA==.Daladin:BAAANQADCggICAABNQAECgoKKgAGAHIdAA==.Dalasaursrex:BAABNQAECn8qAAMGAAoKch1TUACZAgAGAAoKch1TUACZAgAMAAEKAAD3OQAhAAAAAA==.Dangerfiëld:BAAANQAECgIIAQAAAA==.Dawnwell:BAAANQADCgYICgAAAA==.',
De='Deadfisch:BAAANQADCgQIBAABNQADCggIGQAKAAAAAA==.Deathknig:BAAANQADCggICAAAAA==.Demious:BAABNQAECn8UAAIJAAcK6REbkADpAQAJAAcK6REbkADpAQAAAA==.Demmu:BAAANQABCgMIAQAAAA==.Demonfister:BAAANQAECgYICAAAAA==.Demonkiller:BAAANQAECgIIBQAAAA==.Desorion:BAAANQABCgIIAgAAAA==.Dethstriker:BAAANQAECgcIEwAAAA==.Dethwyrm:BAAANQABCgIIAgAAAA==.Devolu:BAAANQADCgUICAAAAA==.',
Di='Didi:BAAANQADCggIAQAAAA==.Dilfzdormu:BAAANQADCgYIBgAAAA==.Dindaratwo:BAABNQAECn8mAAINAAkKZgqcIgBIAQANAAkKZgqcIgBIAQAAAA==.',
Dj='Djunglebook:BAAANQAECgUIBQAAAA==.',
Do='Dokta:BAAANQAECgUIEQAAAA==.Dontula:BAAANQAECgIIAgAAAA==.',
Dr='Drathal:BAAANQAECgQIBAAAAA==.Druaa:BAAANQADCgQIBAABNQAECgUIDgAKAAAAAA==.',
Du='Dumolin:BAAANQAECgIIAQAAAA==.',
Ec='Eclïpse:BAAANQABCgIIAgAAAA==.',
Ed='Eddiedean:BAAANQAECggIDgAAAA==.Edric:BAAANQADCgcIGAAAAA==.',
El='Electolytic:BAAANQAECgUIBAAAAA==.Elfgonewild:BAAANQADCgUIBgAAAA==.Ellessra:BAAANQADCgcIDwAAAA==.Elma:BAAANQADCggICAAAAA==.Elnegrouno:BAABNQAECn8iAAIGAAgKnxMUewAnAgAGAAgKnxMUewAnAgAAAA==.',
Er='Eragone:BAAANQAECgMIBAAAAA==.Eragora:BAAANQADCgUICQAAAA==.Errdrick:BAAANQAECgUICwAAAA==.',
Et='Etoro:BAAANQADCgIIAgAAAA==.',
Fa='Faeyri:BAAANQAECgQIBgAAAA==.Fawntastic:BAAANQADCggIEAAAAA==.',
Fe='Feeri:BAAANQAECgEIAQAAAA==.Feyrbrand:BAABNQAECn8mAAIOAAoK+w8TDgCVAQAOAAoK+w8TDgCVAQAAAA==.',
Fi='Fischnchips:BAAANQADCgQIBAAAAA==.Fischticuffs:BAAANQADCggIGQAAAA==.',
Fo='Fourid:BAABNQAECn8XAAIGAAkKZxP2pADAAQAGAAkKZxP2pADAAQAAAA==.',
Fr='Frostfirer:BAAANQADCgIIAgAAAA==.',
Ga='Gallyn:BAABNQAECn8xAAMPAAoKvhsYGQC0AgAPAAoKxRkYGQC0AgAQAAQKgxg0SQA5AQAAAA==.',
Gi='Giizmo:BAAANQADCgYIBgAAAA==.',
Gl='Glacierrock:BAAANQADCgMIAwAAAA==.Gloria:BAABNQAECn8pAAIEAAoKkRflHwBFAgAEAAoKkRflHwBFAgAAAA==.Glyndor:BAAANQADCgYIBgAAAA==.',
Go='Googlyboogli:BAAANQAECgMIBAAAAA==.',
Gr='Grail:BAAANQAECgEIAQAAAA==.Grogar:BAAANQADCgIIAgAAAA==.',
Gu='Gunslinger:BAAANQAECgUIDQAAAA==.',
Ha='Halenicion:BAAANQAECgIIAQAAAA==.Hankthetank:BAAANQADCgYIBgAAAA==.Hazza:BAAANQADCgUIBQABNQAFFAQICAARAFkQAA==.',
Hi='Hippoltyos:BAABNQAECn8rAAIHAAkKQBKgNwDaAQAHAAkKQBKgNwDaAQAAAA==.',
Ho='Honestlee:BAAANQADCgMIAwAAAA==.Honourablee:BAAANQADCgQIBAAAAA==.',
Hu='Hunkacrap:BAAANQABCgIIAgAAAA==.Huntaa:BAAANQADCggIEgABNQAECgUIDgAKAAAAAA==.Huntardiness:BAABNQAECn8fAAMJAAkKTBPITAC2AQAJAAgKbhXITAC2AQASAAcKbgisRwAfAQAAAA==.',
Hy='Hymnals:BAACNQAFFH8LAAMMAAUKVBpqAQAsAQAMAAQKBhpqAQAsAQAGAAMKRRlDIwDkAAA1AAQKfyAAAwwACgoKJs8CAI8CAAYACQqHJMQlACIDAAwABwqeJM8CAI8CAAAA.',
Ic='Icealia:BAAANQAECgMIBAABNQAFFAIIBQANAC4EAA==.',
Is='Isus:BAAANQAECgMIAwAAAA==.',
Iv='Ive:BAABNQAECn9CAAQRAAoK9SKFGQAhAwARAAkK0iKFGQAhAwATAAUKISIeDgByAQAUAAMKGyCsLQAVAQAAAA==.',
Ja='Jadeflower:BAAANQAECgQIBAAAAA==.Jarnunvosk:BAAANQADCgMIAwAAAA==.Jasmindinn:BAAANQAECgcIBgAAAA==.Jayber:BAAANQAECgEIAQAAAA==.',
Ji='Jimbearlushi:BAACNQAFFH8NAAIVAAUKOBTaCQAuAQAVAAUKOBTaCQAuAQA1AAQKfywAAxUACgofHbIOAAACABUACgofHbIOAAACABYABwr9FXoVAIwBAAAA.',
Ju='Judelly:BAAANQAECgIIAgAAAA==.Juicebox:BAAANQAECgcIDAAAAA==.Justjakk:BAAANQADCgEIAgAAAA==.',
Ka='Kabball:BAAANQAECgEIAQAAAA==.Kabr:BAAANQADCgYICQAAAA==.Kalez:BAAANQADCggIEQAAAA==.Kalibar:BAAANQAECgYIEgAAAA==.Kamakaz:BAABNQAECn8eAAMEAAoKjhWsaADSAQAEAAoKjhWsaADSAQAIAAcKCQqSSgAuAQAAAA==.Kamasdruid:BAAANQAECggIBwAAAA==.Kamasmage:BAAANQAECgYIBQAAAA==.Kandi:BAAANQADCgMIAwAAAA==.Kaviryon:BAAANQADCgIIBAAAAA==.Kaywhy:BAABNQAECn8xAAIXAAoKzR6LEQDjAgAXAAoKzR6LEQDjAgAAAA==.',
Ki='Kichack:BAAANQADCgMIBQAAAA==.Kimchie:BAAANQADCgMIAwAAAA==.Kinqanduin:BAAANQADCggIFAAAAA==.',
Kj='Kjdh:BAABNQAECn9AAAIYAAoK8R+fCwBQAwAYAAoK8R+fCwBQAwAAAA==.',
Kn='Knuckles:BAABNQAECn8WAAIGAAcKSw0ebQBAAQAGAAcKSw0ebQBAAQAAAA==.',
Ko='Koanu:BAAANQADCggIDAAAAA==.Kob:BAABNQAECn8WAAQRAAgKVwgPvQBTAQARAAgKAAgPvQBTAQATAAEKTAggMAA1AAAUAAEKNgHmiAAaAAAAAA==.Kogun:BAAANQAECgIIAgAAAA==.Kozalth:BAAANQADCgcIFwAAAA==.',
Kt='Ktom:BAABNQAECn8zAAIIAAoK3SB0EwBWAwAIAAoK3SB0EwBWAwAAAA==.',
Ku='Kurayami:BAAANQAECgQIBAAAAA==.',
La='Lancelot:BAAANQAECgIIAwAAAA==.Lawndown:BAAANQADCgIIAgAAAA==.Lawnsifer:BAAANQADCgMIAwAAAA==.',
Li='Litchlord:BAAANQADCgYIBgAAAA==.Liv:BAAANQAECgYICAAAAA==.',
Lo='Loax:BAAANQADCgUJBQAAAA==.Loek:BAAANQADCgUIBQAAAA==.Longpong:BAAANQAECgQICgAAAA==.Louhi:BAAANQAECgQIBQAAAA==.Loveshaq:BAAANQAECgUIBQAAAA==.',
Lu='Lunar:BAABNQAECn8kAAIZAAoK9hfzJgCcAgAZAAoK9hfzJgCcAgAAAA==.',
Ly='Lystat:BAAANQAECgQIBAAAAA==.',
Ma='Magra:BAABNQAECn8eAAIaAAkK0A8gEQCVAQAaAAkK0A8gEQCVAQAAAA==.Magêyalook:BAAANQADCgMIAwABNQAECgcIHAAQAL4NAA==.Malogg:BAAANQABCggIFAAAAA==.Manzz:BAAANQADCggICwAAAA==.Mariahscary:BAABNQAECn8nAAIRAAkKpAxelgCuAQARAAkKpAxelgCuAQAAAA==.Marisol:BAAANQAECgEIAgAAAA==.Maskimxul:BAAANQABCgEIAQAAAA==.Mattob:BAAANQADCgYIFAAAAA==.Maznificent:BAAANQADCgYIGAAAAA==.',
Me='Meandmypal:BAACNQAFFH8QAAIbAAcK9RtDAABAAgAbAAcK9RtDAABAAgA1AAQKfzQAAhsACgrSJIQAADUDABsACgrSJIQAADUDAAAA.Meatspinz:BAAANQADCggIDQAAAA==.Meesodead:BAABNQAECn8dAAIDAAkKLQ7QMQBcAQADAAkKLQ7QMQBcAQAAAA==.Mello:BAABNQAECn8hAAIGAAkKXRaIQgDFAQAGAAkKXRaIQgDFAQAAAA==.Mesteris:BAAANQADCggICAAAAA==.Metalhead:BAAANQADCgYIBgAAAA==.',
Mi='Midiane:BAAANQAECgIIAgAAAA==.Mirba:BAAANQAECgUIBwAAAA==.',
Mk='Mknight:BAAANQAECgQIDQAAAA==.',
Mo='Moments:BAAANQADCggICAAAAA==.Monsterdeath:BAAANQAECgIJAgAAAA==.',
['Må']='Måladroit:BAAANQADCgIIAgAAAA==.',
Na='Nareík:BAABNQAECn8tAAMcAAoK+BDxGgBZAQAYAAgKYhBMOwDcAQAcAAoKAQ3xGgBZAQAAAA==.Nazarath:BAAANQABCgIIAgAAAA==.',
Ne='Neeru:BAAANQABCgIIAgABNQAECgoKKwABAEMUAA==.Neriak:BAABNQAECn8wAAIZAAgKlBZ8IQB5AQAZAAgKlBZ8IQB5AQAAAA==.Newa:BAAANQAECgEIAQAAAA==.',
Ni='Nightwater:BAACNQAFFH8FAAINAAIKLgQiDQBqAAANAAIKLgQiDQBqAAA1AAQKfycAAw0ACgqqEwYhACECAA0ACgqqEwYhACECABkAAQoQBaW1AC0AAAAA.',
Ob='Obouuld:BAAANQADCgQIBAAAAA==.',
Or='Orchop:BAAANQADCgUIBgAAAA==.Orenrim:BAAANQADCgMIAwABNQAECgQIBAAKAAAAAA==.',
Os='Osanyin:BAAANQADCgcIGwABNQAECgQIBgAKAAAAAA==.',
Pa='Paado:BAAANQADCgEIAQAAAA==.Paulterian:BAAANQAECgQICAAAAA==.',
Pe='Pentagonjr:BAAANQADCgUIBQAAAA==.',
Pf='Pffthmgcdrgn:BAAANQADCgQICAAAAA==.',
Ph='Phinehas:BAAANQADCggJCAAAAA==.',
Po='Poldalina:BAAANQADCgcIIQAAAA==.',
Pr='Pr:BAAANQADCgYIBgAAAA==.Priesaa:BAAANQAECgQICAABNQAECgUIDgAKAAAAAA==.Proverbs:BAAANQABCgIIAgAAAA==.',
Pu='Pumplord:BAAANQADCgIIAgAAAA==.',
Qe='Qeynos:BAABNQAECn8bAAMCAAcK4g4mOADcAAACAAcK4g4mOADcAAALAAEKAAC52wAiAAAAAA==.',
Ql='Qlona:BAAANQAECgYIBgAAAA==.',
Qu='Quazeemoto:BAAANQAECgQIBAAAAA==.',
Ra='Raalen:BAAANQABCgYICwAAAA==.Rainknuckles:BAABNQAECn8sAAIBAAoKzBv+MQCdAgABAAoKzBv+MQCdAgAAAA==.Ratrenot:BAAANQADCggIDAAAAA==.Ravael:BAAANQADCgUIBwAAAA==.Rayshano:BAAANQADCggICAABNQAECgcICwAKAAAAAA==.',
Re='Redfisch:BAAANQADCgUIBQABNQADCggIGQAKAAAAAA==.Resia:BAAANQADCggIEAAAAA==.Retailsucks:BAAANQADCgcIFQAAAA==.Revocsid:BAAANQADCgYIGgAAAA==.Rezza:BAAANQADCgUIBgAAAA==.',
Ri='Ridethewave:BAAANQADCgIIAgAAAA==.Rikka:BAAANQADCgQIBAAAAA==.',
Ro='Rottingtree:BAABNQAECn8YAAMaAAcKEw2vFgBIAQAaAAcKEw2vFgBIAQAdAAEK5AKT0AEuAAAAAA==.',
Ru='Rustynails:BAABNQAECn8uAAIeAAoKkRZnAQAmAgAeAAoKkRZnAQAmAgAAAA==.',
Ry='Ryvalz:BAAANQAECgYICQAAAA==.',
Sa='Sacrafischal:BAAANQADCgcICwAAAA==.Saibur:BAAANQAECgUIBwAAAA==.Sazzul:BAAANQAECgcIEgAAAA==.',
Sc='Scynx:BAAANQAECgEIAgAAAA==.',
Se='Seaka:BAABNQAECn8vAAMNAAkKfxf1GAB1AgANAAkKfxf1GAB1AgAZAAMKFhF/kQCRAAAAAA==.Sernix:BAAANQAECgMIDAAAAA==.',
Sh='Shadegrim:BAAANQAECgEIAQAAAA==.Shamanic:BAAANQADCggIHAAAAA==.Shamany:BAAANQAECgUIDgAAAA==.Shamnick:BAAANQAECgYIBgAAAA==.Shariya:BAAANQAECgQIBAAAAA==.Shiftyfans:BAAANQADCgcIIQAAAA==.Shivon:BAAANQAECgQIBAAAAA==.',
Sl='Slamin:BAAANQADCgYIBwAAAA==.',
Sn='Snowaxe:BAAANQADCgIIAgAAAA==.Snowwind:BAAANQAECgQICAAAAA==.',
So='Solthea:BAAANQABCgMIBAAAAA==.Sonar:BAABNQAECn8+AAIJAAoKIx3FJwD5AgAJAAoKIx3FJwD5AgAAAA==.Sonasham:BAAANQADCgcIIQAAAA==.Sonnybear:BAAANQADCgcIIQAAAA==.Soulhatcher:BAAANQAECggIBgAAAA==.Soulslinger:BAAANQABCgQIBQAAAA==.Soxs:BAAANQAECgUICQAAAA==.',
Sp='Spawnofdeath:BAAANQAECgIIAwAAAA==.Spectrelok:BAAANQAECgMIBAAAAA==.Spectrepunch:BAAANQAECgUICwAAAA==.',
St='Steàlthy:BAABNQAECn8cAAIQAAcKvg03JACnAQAQAAcKvg03JACnAQAAAA==.Stickychikn:BAAANQADCgYIBgAAAA==.Stompygnome:BAAANQAECgcIEwAAAA==.',
Sy='Syrila:BAABNQAECn8dAAIBAAkKJRLWLAD1AQABAAkKJRLWLAD1AQAAAA==.',
Ta='Tartanus:BAAANQADCgQIBAAAAA==.Tayzetv:BAAANQADCgcIBwABNQAECgQIBQAKAAAAAA==.',
Te='Teramiah:BAAANQADCgMIAwAAAA==.',
Th='Thorall:BAAANQADCgQIAwAAAA==.Thylight:BAAANQADCgIIAgAAAA==.',
Ti='Tippy:BAACNQAFFH8QAAIDAAcK1hvwAwDlAQADAAcK1hvwAwDlAQA1AAQKfy8AAgMACgopJTASAPwCAAMACgopJTASAPwCAAAA.',
To='Tombstone:BAABNQAECn8zAAMPAAoKjhllGgCqAgAPAAoKzxdlGgCqAgAQAAYKaRcFPgBqAQAAAA==.Toowongfoo:BAACNQAFFH8UAAIVAAcKzgslBAAaAQAVAAcKzgslBAAaAQA1AAQKfzcAAhUACgoeISQEAAMDABUACgoeISQEAAMDAAAA.',
Ug='Uglysham:BAABNQAECn8nAAIEAAgKGh9SEADQAgAEAAgKGh9SEADQAgAAAA==.',
Um='Umbranecros:BAAANQADCgQIBQAAAA==.',
Un='Underdog:BAAANQAECgUIDgAAAA==.',
Us='Usui:BAAANQADCgUIBQAAAA==.',
Va='Vaerie:BAAANQADCgYIBgAAAA==.Vagindivin:BAAANQAECggIEgAAAA==.Valyteil:BAAANQAECgUIBQAAAA==.',
Ve='Venngance:BAAANQAECgUIBwAAAA==.Vercingetorx:BAAANQADCgIIAgAAAA==.',
Vi='Virus:BAABNQAECn8XAAMRAAgK6w2VRQCVAQARAAgK6w2VRQCVAQAUAAIKuQMYbQBFAAAAAA==.',
Vo='Void:BAAANQAECggICQAAAA==.Voidkity:BAAANQAECgUICwAAAA==.',
Wa='Wakax:BAAANQAFFAEIAQAAAA==.Walberson:BAAANQADCgcIBwAAAA==.Walkleydk:BAAANQAECggICAAAAA==.Warfield:BAAANQAECgUIEQAAAA==.Warmoose:BAAANQADCggICAABNQAECggIEgAKAAAAAA==.',
We='Weediez:BAAANQADCgYJCAAAAA==.',
Wi='Wildfrost:BAABNQAECn8ZAAIdAAUKQAJKkwGgAAAdAAUKQAJKkwGgAAAAAA==.Willienelson:BAAANQAECggIDgAAAA==.',
Wr='Wrathsome:BAAANQAECgUIBwAAAA==.',
Wy='Wyrmboy:BAAANQABCgQIBQAAAA==.Wyterd:BAABNQAECn8fAAIJAAgKVxIDVgCbAQAJAAgKVxIDVgCbAQAAAA==.',
Xa='Xaernach:BAAANQADCgQIBgAAAA==.Xalome:BAAANQADCgUIEwAAAA==.',
Xo='Xoxo:BAAANQAFFAEIAQABNQAFFAMIAwAKAAAAAA==.',
Yo='Yoing:BAAANQADCggICAABNQADCggICAAKAAAAAA==.',
Za='Zarkus:BAAANQAECgMIBAAAAA==.Zaruknark:BAAANQAECggIEQAAAA==.',
['Àl']='Àlexia:BAAANQAECgIIAwAAAA==.',
['Ño']='Ñoog:BAAANQADCgUIBQAAAA==.',
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
