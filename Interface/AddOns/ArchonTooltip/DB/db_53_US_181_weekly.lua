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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Priest-Holy','Shaman-Elemental','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Blood','Warrior-Fury','Druid-Restoration','Evoker-Preservation','Rogue-Assassination','Hunter-Marksmanship','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Monk-Windwalker','Monk-Brewmaster','Priest-Shadow','DemonHunter-Havoc','Druid-Balance','Mage-Frost','Rogue-Subtlety','Hunter-Survival','DemonHunter-Devourer','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abert:BAAANQAECgUICgAAAA==.',
Ac='Acts:BAAANQADCgYICgAAAA==.',
Ad='Adalinda:BAAANQADCgQIBAABNQAECgoKJwABAOcaAA==.Adrelorà:BAAANQADCgcIDQAAAA==.',
Ae='Aerähn:BAAANQABCggIKQAAAA==.',
Ag='Agathahaknes:BAAANQADCgEIAQAAAA==.Agnor:BAABNQAECn8gAAICAAcKrBYATQDgAQACAAcKrBYATQDgAQAAAA==.',
Ai='Aindria:BAAANQADCggICAAAAA==.',
Al='Alatir:BAAANQADCgYIDgAAAA==.',
Am='Ameri:BAAANQAECgEIAQABNQAFFAcIEAADANYbAA==.Ammeka:BAAANQABCggIEgAAAA==.',
An='Anahline:BAAANQAECgEIAQAAAA==.Andre:BAAANQAECggICwABNQAFFAUIDAAEAAcPAA==.Anjaini:BAAANQADCgEJAQAAAA==.Antibubble:BAABNQAECn8xAAIDAAoKMB9GFADqAgADAAoKMB9GFADqAgAAAA==.Antimatter:BAAANQAECgEIAQAAAA==.Anwal:BAABNQAECn8nAAMBAAoK5xpvDgDpAQABAAoK5xpvDgDpAQAFAAcKRQ7g4wBUAQAAAA==.',
Ar='Arceilth:BAAANQAECgMIAgAAAA==.Argus:BAAANQADCgIIAgAAAA==.Arissidis:BAAANQAECgEIAQAAAA==.Arithfury:BAABNQAECn8mAAIGAAkKFhlsFgCvAQAGAAkKFhlsFgCvAQAAAA==.Arkaius:BAAANQADCggICgAAAA==.Articuno:BAAANQADCgUICQAAAA==.Arwenloa:BAAANQAECgEIAQABNQAECgcIGwAEAPMRAA==.',
As='Ashwynn:BAAANQAECgUIBwAAAA==.Aske:BAAANQAECgMIAgAAAA==.',
At='Atalnoa:BAAANQADCgYICAAAAA==.',
Au='Aura:BAAANQADCgIIAgABNQAECggIHAAHALYTAA==.',
Az='Azuresun:BAABNQAECn8WAAIIAAUKtAcQRQC9AAAIAAUKtAcQRQC9AAAAAA==.',
Ba='Ballak:BAAANQAECgIIAwAAAA==.Bambeeno:BAAANQABCgYIBgAAAA==.Barnardo:BAAANQABCgIJAgAAAA==.Bassmasta:BAABNQAECn8lAAIJAAoKVB5mHAAmAwAJAAoKVB5mHAAmAwAAAA==.Baston:BAAANQADCgQIBAAAAA==.',
Be='Beatin:BAAANQAECgQICAAAAA==.Belinda:BAAANQAECgIIAgAAAA==.Bentö:BAAANQADCgcIBwAAAA==.Beny:BAAANQAECgYIEQAAAA==.',
Bl='Blackskillz:BAAANQAECgMIBwABNQAECggIIgAGAJ8TAA==.Bloodstorm:BAAANQAECgIIAwAAAA==.Bloopydoo:BAAANQAECgQICQAAAA==.Bluefisch:BAAANQADCgEIAQAAAA==.',
Bo='Boiorix:BAAANQADCgEIAQABNQAECgQIBwAKAAAAAA==.Borim:BAAANQAECgQIBgAAAA==.',
Br='Braincell:BAAANQAECgEIAQAAAA==.Brassidas:BAAANQAECgEIAQAAAA==.Brbpoopin:BAAANQADCgYICQAAAA==.Bromancehomo:BAAANQADCgUIBgAAAA==.Brotems:BAAANQAECgEIAQAAAA==.Bruwdfyre:BAAANQAECggIEwAAAA==.',
Bu='Bubbleshield:BAAANQADCgcIBwAAAA==.',
Ca='Castani:BAAANQAECgcIDAAAAA==.',
Ce='Celestyal:BAAANQAECgQIBwAAAA==.',
Ch='Choshi:BAAANQADCgMIAwABNQAECgQIDwAKAAAAAA==.',
Ci='Cindy:BAAANQAECgUIBQABNQAECggIHgAKAAAAAQ==.',
Co='Confidential:BAAANQADCgIIAgAAAA==.Cootpal:BAABNQAECn8uAAIFAAkKIRtfUQChAgAFAAkKIRtfUQChAgAAAA==.',
Cr='Crazyloon:BAAANQAECgYIEwAAAA==.',
Cy='Cynawyne:BAAANQAECgEIAQAAAA==.Cynthea:BAAANQABCgYICwAAAA==.',
['Cö']='Cörinthian:BAAANQADCgEIAQAAAA==.',
Da='Daddybod:BAABNQAECn8eAAMDAAkKLQxcSACcAQADAAgKLQxcSACcAQALAAYKlAYAMgCuAAAAAA==.Dalasaursrex:BAABNQAECn8oAAMGAAoKghtTUACZAgAGAAoKghtTUACZAgAMAAEKAAD3OQAhAAAAAA==.Dangerfiëld:BAAANQAECgIIAwAAAA==.Dawnwell:BAAANQADCgYICgAAAA==.',
De='Deadfisch:BAAANQADCgQIBAABNQADCggIGQAKAAAAAA==.Deathknig:BAAANQADCggICAAAAA==.Demious:BAABNQAECn8UAAIJAAcK6REbkADpAQAJAAcK6REbkADpAQAAAA==.Demmu:BAAANQAECgEIAQAAAA==.Demonfister:BAAANQAECgYICAAAAA==.Demonkiller:BAAANQAECgMIBQAAAA==.Desorion:BAAANQAECgEIBAAAAA==.Dethstriker:BAAANQAECgcIEwAAAA==.Dethwyrm:BAAANQABCgIIAgAAAA==.Devolu:BAAANQAECgEIAQAAAA==.',
Di='Didi:BAAANQADCggIAQAAAA==.Dilfzdormu:BAAANQADCgYIBgAAAA==.Dindaratwo:BAABNQAECn8mAAINAAkKZgpjDgBbAQANAAkKZgpjDgBbAQAAAA==.',
Dj='Djunglebook:BAAANQAECgUIBQAAAA==.',
Do='Dokta:BAAANQAECgUIDAAAAA==.Dontula:BAAANQAECgIIAgAAAA==.',
Dr='Drathal:BAAANQAECgQIBQAAAA==.Druaa:BAAANQADCgQIBAABNQAECgQIDwAKAAAAAA==.',
Du='Dumolin:BAAANQAECgIIAQAAAA==.',
Ec='Eclïpse:BAAANQAECgEIAQAAAA==.',
Ed='Eddiedean:BAAANQAECggIEQAAAA==.Edric:BAAANQADCgcIEgAAAA==.',
El='Electolytic:BAAANQAECgYIBQAAAA==.Elfgonewild:BAAANQADCgUIBgAAAA==.Ellessra:BAAANQADCgcIDwAAAA==.Elma:BAAANQADCggICAAAAA==.Elnegrouno:BAABNQAECn8iAAIGAAgKnxMUewAnAgAGAAgKnxMUewAnAgAAAA==.',
Er='Eragone:BAAANQAECgEIAQAAAA==.Eragora:BAAANQADCgUICQAAAA==.Errdrick:BAAANQAECgUICQAAAA==.',
Et='Etoro:BAAANQADCgIIAgAAAA==.',
Fa='Faeyri:BAAANQAECgMIAgAAAA==.Fawntastic:BAAANQADCggIEAAAAA==.',
Fe='Feeri:BAAANQAECgEJAQAAAA==.Feyrbrand:BAABNQAECn8eAAIOAAgKuw0VIwCvAQAOAAgKuw0VIwCvAQAAAA==.',
Fi='Fischnchips:BAAANQADCgQIBAAAAA==.Fischticuffs:BAAANQADCggIGQAAAA==.',
Fo='Fourid:BAABNQAECn8VAAIGAAkKrw+DSAAPAQAGAAkKrw+DSAAPAQAAAA==.',
Fr='Frostfirer:BAAANQADCgIIAgAAAA==.',
Ga='Gallyn:BAABNQAECn8tAAIPAAoKxRkYGQC0AgAPAAoKxRkYGQC0AgAAAA==.',
Gi='Giizmo:BAAANQADCgYIBgAAAA==.',
Gl='Glacierrock:BAAANQADCgMIAwAAAA==.Gloria:BAABNQAECn8fAAIEAAoKlRasXAD5AQAEAAoKlRasXAD5AQAAAA==.Glyndor:BAAANQADCgYIBgAAAA==.',
Go='Googlyboogli:BAAANQAECgMIAwAAAA==.',
Gr='Grogar:BAAANQAECgEIAQAAAA==.',
Gu='Gunslinger:BAAANQAECgUIDwAAAA==.',
Ha='Halenicion:BAAANQAECgIIAQAAAA==.Hankthetank:BAAANQADCgYIBgAAAA==.',
Hi='Hippoltyos:BAABNQAECn8oAAIHAAkKZRF1FQDFAQAHAAkKZRF1FQDFAQAAAA==.',
Ho='Honestlee:BAAANQADCgMIAwAAAA==.Honourablee:BAAANQADCgQIBAAAAA==.',
Hu='Hunkacrap:BAAANQABCgIIAgAAAA==.Huntaa:BAAANQAECgEIAQABNQAECgQIDwAKAAAAAA==.Huntardiness:BAABNQAECn8ZAAMJAAkKfw9uRAAsAQAJAAYKkhRuRAAsAQAQAAcKbgisRwAfAQAAAA==.',
Hy='Hymnals:BAACNQAFFH8LAAMMAAUKVBpqAQAsAQAMAAQKBhpqAQAsAQAGAAMKRRlDIwDkAAA1AAQKfxoAAwYACgoAJsQlACIDAAYACQqHJMQlACIDAAwAAwrGJu4EAF4BAAAA.',
Ic='Icealia:BAAANQAECgEIAQABNQAECgoKJgANAMwRAA==.',
Is='Isus:BAAANQAECgMIBgAAAA==.',
Iv='Ive:BAABNQAECn8+AAQRAAoK9SK+CgD+AQARAAkK0iK+CgD+AQASAAUKISIeDgByAQATAAMKGyCsLQAVAQAAAA==.',
Ja='Jadeflower:BAAANQADCgcIBwAAAA==.Jarnunvosk:BAAANQADCgMIAwAAAA==.Jasmindinn:BAAANQAECgcIBwAAAA==.Jayber:BAAANQAECgEIAQAAAA==.',
Ji='Jimbearlushi:BAACNQAFFH8NAAIUAAUKOBTaCQAuAQAUAAUKOBTaCQAuAQA1AAQKfyQAAxQACgreGaQfADICABQACgrIGKQfADICABUABwr9FXoVAIwBAAAA.',
Ju='Judelly:BAAANQAECgIIAgAAAA==.Juicebox:BAAANQAECgYICQAAAA==.Justjakk:BAAANQADCgEIAgAAAA==.',
Ka='Kabball:BAAANQAECgEIAQAAAA==.Kabr:BAAANQADCgYICQAAAA==.Kalez:BAAANQAECgEIAQAAAA==.Kalibar:BAAANQAECgYIDAAAAA==.Kamakaz:BAABNQAECn8ZAAMEAAkKMhasaADSAQAEAAgKLhSsaADSAQAIAAcKCQpaGgBUAQAAAA==.Kamasdruid:BAAANQAECggIBwAAAA==.Kamasmage:BAAANQAECgYIBQAAAA==.Kandi:BAAANQADCgMIAwAAAA==.Kaviryon:BAAANQADCgIIBAAAAA==.Kaywhy:BAABNQAECn8xAAIWAAoKzR44AgAqAgAWAAoKzR44AgAqAgAAAA==.',
Ki='Kichack:BAAANQADCgMJBQAAAA==.Kimchie:BAAANQADCgMIAwAAAA==.Kinqanduin:BAAANQADCggIFAAAAA==.',
Kj='Kjdh:BAABNQAECn83AAIXAAoKsB+fCwBQAwAXAAoKsB+fCwBQAwAAAA==.',
Kn='Knuckles:BAAANQAECgYIDwAAAA==.',
Ko='Koanu:BAAANQAECgEIAQAAAA==.Kob:BAABNQAECn8WAAQRAAgKVwgPvQBTAQARAAgKAAgPvQBTAQASAAEKTAggMAA1AAATAAEKNgHmiAAaAAAAAA==.Kogun:BAAANQAECgEIAQAAAA==.Kozalth:BAAANQADCgcIFwAAAA==.',
Kt='Ktom:BAABNQAECn8tAAIIAAoKniB0EwBWAwAIAAoKniB0EwBWAwAAAA==.',
Ku='Kurayami:BAAANQAECgQIBAAAAA==.',
La='Lancelot:BAAANQAECgIIAwAAAA==.Lawndown:BAAANQADCgIIAgAAAA==.Lawnsifer:BAAANQADCgMIAwAAAA==.',
Li='Litchlord:BAAANQADCgYIBgAAAA==.Liv:BAAANQAECgYICAAAAA==.',
Lo='Loax:BAAANQADCgUJBQAAAA==.Loek:BAAANQADCgUIBQAAAA==.Longpong:BAAANQAECgQICgAAAA==.Louhi:BAAANQAECgEIAgAAAA==.Loveshaq:BAAANQAECgUIBgAAAA==.',
Lu='Lunar:BAABNQAECn8gAAIYAAoKOhbzJgCcAgAYAAoKOhbzJgCcAgAAAA==.',
Ly='Lystat:BAAANQAECgQIBAAAAA==.',
Ma='Magra:BAABNQAECn8cAAIZAAgKVg4gEQCVAQAZAAgKVg4gEQCVAQAAAA==.Magêyalook:BAAANQADCgMIAwABNQAECgcIFQAaAL4NAA==.Malogg:BAAANQABCggIFAAAAA==.Manzz:BAAANQADCggICAAAAA==.Mariahscary:BAABNQAECn8nAAIRAAkKpAwyRAADAQARAAkKpAwyRAADAQAAAA==.Marisol:BAAANQAECgEIAQAAAA==.Maskimxul:BAAANQABCgEIAQAAAA==.Mattob:BAAANQADCgYIDgAAAA==.Maznificent:BAAANQADCgUIEgAAAA==.',
Me='Meandmypal:BAACNQAFFH8QAAIbAAcK9RtDAABAAgAbAAcK9RtDAABAAgA1AAQKfysAAhsACgqMJCsBAHIDABsACgqMJCsBAHIDAAAA.Meatspinz:BAAANQADCggIDQAAAA==.Meesodead:BAABNQAECn8WAAIDAAkK5wssHwApAQADAAkK5wssHwApAQAAAA==.Mello:BAABNQAECn8YAAIGAAgKQhQYUAD9AAAGAAgKQhQYUAD9AAAAAA==.Mesteris:BAAANQADCggICAAAAA==.Metalhead:BAAANQADCgYIBgAAAA==.',
Mi='Midiane:BAAANQAECgIIAwAAAA==.Miney:BAAANQAECgEIAQAAAA==.Mirba:BAAANQAECgMIAgAAAA==.',
Mk='Mknight:BAAANQAECgMIDQAAAA==.',
Mo='Moments:BAAANQADCggICAAAAA==.Monsterdeath:BAAANQAECgIJAgAAAA==.',
['Må']='Måladroit:BAAANQADCgIIAgAAAA==.',
Na='Nareík:BAABNQAECn8oAAMcAAoKQRDiCQB0AQAXAAgKYhBMOwDcAQAcAAoKXAviCQB0AQAAAA==.Nazarath:BAAANQABCgIIAgAAAA==.',
Ne='Neeru:BAAANQABCgIIAgABNQAECgcIIQABAFATAA==.Neriak:BAABNQAECn8qAAIYAAgKlBZ4DwBeAQAYAAgKlBZ4DwBeAQAAAA==.Newa:BAAANQAECgEIAQAAAA==.',
Ni='Nightwater:BAABNQAECn8mAAMNAAoKzBEGIQAhAgANAAoKzBEGIQAhAgAYAAEKEAWltQAtAAAAAA==.',
Or='Orchop:BAAANQADCgUIBgAAAA==.Orenrim:BAAANQADCgMIAwABNQAECgQIBQAKAAAAAA==.',
Os='Osanyin:BAAANQADCgcIGwABNQAECgUICAAKAAAAAA==.',
Pa='Paado:BAAANQADCgEIAQAAAA==.Paulterian:BAAANQAECgQIBAAAAA==.',
Pf='Pffthmgcdrgn:BAAANQAECgEIAQAAAA==.',
Ph='Phinehas:BAAANQADCggJCAAAAA==.',
Po='Poldalina:BAAANQADCgcIGwAAAA==.',
Pr='Pr:BAAANQADCgYIBgAAAA==.Priesaa:BAAANQAECgQICAABNQAECgQIDwAKAAAAAA==.Proverbs:BAAANQABCgIIAgAAAA==.',
Pu='Pumplord:BAAANQADCgIIAgAAAA==.',
Qe='Qeynos:BAABNQAECn8bAAMCAAcK4g62HwDuAAACAAcK4g62HwDuAAALAAEKAAC52wAiAAAAAA==.',
Qu='Quazeemoto:BAAANQAECgQICgAAAA==.',
Ra='Raalen:BAAANQABCgYICwAAAA==.Rainknuckles:BAABNQAECn8lAAIBAAoK5Rj+MQCdAgABAAoK5Rj+MQCdAgAAAA==.Ratrenot:BAAANQAECgEIAgAAAA==.Ravael:BAAANQADCgUIBwAAAA==.Rayshano:BAAANQADCggICAABNQAECgcIDQAKAAAAAA==.',
Re='Redfisch:BAAANQADCgUIBQABNQADCggIGQAKAAAAAA==.Resia:BAAANQADCggIEAAAAA==.Retailsucks:BAAANQADCgcIEAAAAA==.Revocsid:BAAANQADCgYIFAAAAA==.Rezza:BAAANQADCgUIBgAAAA==.',
Ri='Ridethewave:BAAANQADCgIIAgAAAA==.Rikka:BAAANQADCgMIAwAAAA==.',
Ro='Rottingtree:BAAANQAECgYIEQAAAA==.',
Ru='Rustynails:BAABNQAECn8qAAIdAAoK8xVEAABMAgAdAAoK8xVEAABMAgAAAA==.',
Ry='Ryvalz:BAAANQAECgYICQAAAA==.',
Sa='Sacrafischal:BAAANQADCgcICwAAAA==.Sazzul:BAAANQAECgYICwAAAA==.',
Sc='Scynx:BAAANQAECgEIBQAAAA==.',
Se='Seaka:BAABNQAECn8uAAMNAAkKfxf1GAB1AgANAAkKfxf1GAB1AgAYAAMKFhF/kQCRAAAAAA==.Sernix:BAAANQAECgMIEQAAAA==.',
Sh='Shadegrim:BAAANQAECgEIAgAAAA==.Shamanic:BAAANQADCggIHAAAAA==.Shamany:BAAANQAECgQIDwAAAA==.Shamnick:BAAANQAECgYIBgAAAA==.Shariya:BAAANQAECgQIBAAAAA==.Shiftyfans:BAAANQADCgcIGwAAAA==.Shivon:BAAANQAECgQIBQAAAA==.',
Sl='Slamin:BAAANQADCgYIBwAAAA==.',
Sn='Snowaxe:BAAANQADCgIIAgAAAA==.Snowwind:BAAANQAECgUICAAAAA==.',
So='Solthea:BAAANQABCgMIBAAAAA==.Sonar:BAABNQAECn8vAAIJAAoKIx3FJwD5AgAJAAoKIx3FJwD5AgAAAA==.Sonasham:BAAANQADCgcIGwAAAA==.Sonnybear:BAAANQADCgcIGwAAAA==.Soulhatcher:BAAANQADCgEIAQAAAA==.Soulslinger:BAAANQABCgQIBQAAAA==.Soxs:BAAANQAECgUICgAAAA==.',
Sp='Spawnofdeath:BAAANQAECgIIBQAAAA==.Spectrelok:BAAANQAECgMIBwAAAA==.Spectrepunch:BAAANQAECgUICQAAAA==.',
St='Steàlthy:BAABNQAECn8VAAIaAAcKvg03JACnAQAaAAcKvg03JACnAQAAAA==.Stickychikn:BAAANQADCgYIBgAAAA==.Stompygnome:BAAANQAECgYIDgAAAA==.',
Sy='Syrila:BAABNQAECn8VAAIBAAkKhw5JGQCPAQABAAkKhw5JGQCPAQAAAA==.',
Ta='Tartanus:BAAANQADCgQIBAAAAA==.Tayzetv:BAAANQADCgcIBwABNQAECgQICAAKAAAAAA==.',
Te='Teramiah:BAAANQADCgMIAwAAAA==.',
Th='Thebe:BAAANQAECgEIAQAAAA==.Thorall:BAAANQADCgQIAwAAAA==.Thylight:BAAANQADCgIIAgAAAA==.',
Ti='Tippy:BAACNQAFFH8QAAIDAAcK1hvwAwDlAQADAAcK1hvwAwDlAQA1AAQKfysAAgMACgocIDASAPwCAAMACgocIDASAPwCAAAA.',
To='Tombstone:BAABNQAECn8tAAIPAAoKzxdlGgCqAgAPAAoKzxdlGgCqAgAAAA==.Toowongfoo:BAACNQAFFH8TAAIUAAYKZA0XBADdAAAUAAYKZA0XBADdAAA1AAQKfy0AAhQACgo6HWcVAKgCABQACgo6HWcVAKgCAAAA.',
Tu='Tunechi:BAAANQAECgEIAQAAAA==.',
Ug='Uglysham:BAABNQAECn8eAAIEAAcKWB8dCgAgAgAEAAcKWB8dCgAgAgAAAA==.',
Um='Umbranecros:BAAANQADCgEIAQAAAA==.',
Un='Underdog:BAAANQAECgYIDgAAAA==.',
Us='Usui:BAAANQADCgUIBQAAAA==.',
Va='Vaerie:BAAANQADCgYIBgAAAA==.Vagindivin:BAAANQAECggIEQAAAA==.Valyteil:BAAANQAECgMIAwAAAA==.',
Ve='Venngance:BAAANQAECgMIAgAAAA==.',
Vi='Virus:BAAANQAECgYIDwAAAA==.',
Vo='Voidkity:BAAANQAECgUICQAAAA==.',
Wa='Wakax:BAAANQAECgUIDwAAAA==.Walberson:BAAANQADCgcIBwAAAA==.Walkleydk:BAAANQAECggICAAAAA==.Warfield:BAAANQAECgUIEwAAAA==.Warmoose:BAAANQAECgEIAQABNQAECggIEQAKAAAAAA==.',
We='Weediez:BAAANQADCgYJCAAAAA==.',
Wi='Wildfrost:BAABNQAECn8XAAIeAAQKHQJKkwGgAAAeAAQKHQJKkwGgAAAAAA==.Willienelson:BAAANQAECggIDgAAAA==.',
Wr='Wrathsome:BAAANQAECgMIAgAAAA==.',
Wy='Wyrmboy:BAAANQABCgQIBQAAAA==.Wyterd:BAABNQAECn8YAAIJAAcKow6kUgALAQAJAAcKow6kUgALAQAAAA==.',
Xa='Xaernach:BAAANQADCgQIBgAAAA==.Xalome:BAAANQAECgEIAQAAAA==.',
Xo='Xoxo:BAAANQAFFAEIAQABNQAFFAMIAwAKAAAAAA==.',
Za='Zarkus:BAAANQAECgMIAwAAAA==.Zaruknark:BAAANQAECgYIDwAAAA==.',
['Àl']='Àlexia:BAAANQAECgMIBAAAAA==.',
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
