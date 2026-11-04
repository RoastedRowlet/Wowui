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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Priest-Holy','Shaman-Elemental','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Blood','Warrior-Fury','Druid-Restoration','Warrior-Protection','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','Warlock-Demonology','Hunter-Marksmanship','Warlock-Affliction','Warlock-Destruction','Monk-Windwalker','Monk-Brewmaster','Priest-Shadow','DemonHunter-Havoc','Druid-Balance','Mage-Frost','Hunter-Survival','DemonHunter-Devourer','Mage-Arcane','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abert:BAAANQAECgUIEAAAAA==.',
Ac='Acts:BAAANQADCgYICgAAAA==.',
Ad='Adalinda:BAAANQADCgQIBAABNQAFFAIIBQABAK4XAA==.Adra:BAAANQADCggICAAAAA==.Adrelorà:BAAANQADCgcIDQAAAA==.',
Ae='Aerähn:BAAANQABCggIKwAAAA==.',
Ag='Agathahaknes:BAAANQADCgEIAQAAAA==.Agnor:BAABNQAECn8rAAICAAkKqRP8KgBbAQACAAkKqRP8KgBbAQAAAA==.',
Ai='Aindria:BAAANQADCggICAAAAA==.',
Al='Alatir:BAAANQADCggIFgAAAA==.',
Am='Ameri:BAAANQAECgEIAQABNQAFFAcIEAADANYbAA==.Ammeka:BAAANQABCggIEgAAAA==.',
An='Anahline:BAAANQAECgEIAQAAAA==.Andre:BAAANQAECggICAABNQAFFAYIEwAEAEETAA==.Anjaini:BAAANQADCgIIAgAAAA==.Antibubble:BAABNQAECn8xAAIDAAoKMB9GFADqAgADAAoKMB9GFADqAgAAAA==.Antimatter:BAAANQAFFAIIAwAAAA==.Anwal:BAACNQAFFH8FAAIBAAIKrhfZFQCtAAABAAIKrhfZFQCtAAA1AAQKfzcAAwEACgrAI4wKAFoDAAEACgrAI4wKAFoDAAUABwpFDuDjAFQBAAAA.',
Ar='Arceilth:BAAANQAECgYICwAAAA==.Argus:BAAANQADCgIIAgAAAA==.Arissidis:BAAANQAECgEIAQAAAA==.Arithfury:BAABNQAECn8rAAIGAAkKchmOawBPAgAGAAkKchmOawBPAgAAAA==.Arkaius:BAAANQADCggICgAAAA==.Articuno:BAAANQADCgUICQAAAA==.',
As='Ashwynn:BAAANQAECgUICQAAAA==.Aske:BAAANQAECgYIDQAAAA==.',
At='Atalnoa:BAAANQADCgYICAAAAA==.',
Au='Aura:BAAANQADCgIIAgABNQAECgkJHgAHAEYSAA==.',
Az='Azuresun:BAABNQAECn8gAAIIAAUK3AeikQCwAAAIAAUK3AeikQCwAAAAAA==.',
Ba='Ballak:BAAANQAECgIIAgAAAA==.Bambeeno:BAAANQABCgYIBgAAAA==.Barnardo:BAAANQABCgIJAgAAAA==.Bassmasta:BAABNQAECn8qAAIJAAoKaSJmHAAmAwAJAAoKaSJmHAAmAwAAAA==.Baston:BAAANQAECgQIBAAAAA==.',
Be='Beatin:BAAANQAECgQIBwAAAA==.Belinda:BAAANQAECgIIAgAAAA==.Bentö:BAAANQADCgcIBwAAAA==.Beny:BAAANQAECgYIEQAAAA==.',
Bi='Biscüits:BAAANQADCgQIBAAAAA==.',
Bl='Blackskillz:BAAANQAECgMIAwABNQAECggIIgAGAJ8TAA==.Bloodstorm:BAAANQAECgIIAQAAAA==.Bloopydoo:BAAANQAECgYIDQAAAA==.Bluefisch:BAAANQADCgEIAQAAAA==.',
Bo='Boiorix:BAAANQADCgEIAQABNQAECgQIBwAKAAAAAA==.Borim:BAAANQAECgUICgAAAA==.',
Br='Braincell:BAAANQAECgQIBAAAAA==.Brandymae:BAAANQADCgYIBgAAAA==.Brassidas:BAAANQAECgEIAQAAAA==.Brbpoopin:BAAANQADCgYIDwAAAA==.Bromancehomo:BAAANQADCgUIBgAAAA==.Bruwdfyre:BAAANQAECggIEQAAAA==.',
Bu='Bubbleshield:BAAANQADCgcIBwAAAA==.',
Ca='Castani:BAAANQAECgcIEAAAAA==.',
Ce='Celestyal:BAAANQAECgQIBwAAAA==.',
Ch='Choshi:BAAANQADCgMIAwABNQAECgYIGwAEAOoYAA==.',
Ci='Cindy:BAAANQAECggIDQABNQAFFAEIAQAKAAAAAQ==.',
Co='Confidential:BAAANQADCgIIAgAAAA==.Cootpal:BAABNQAECn80AAIFAAoKGxlfUQChAgAFAAoKGxlfUQChAgAAAA==.',
Cr='Crazyloon:BAAANQAECgYIEAAAAA==.Crewdle:BAAANQADCggICAAAAA==.',
Cy='Cynawyne:BAAANQABCgMIAwABNQADCgcIFQAKAAAAAA==.Cynthea:BAAANQABCgYIDQAAAA==.',
['Cö']='Cörinthian:BAAANQADCgEIAQAAAA==.',
Da='Daddybod:BAACNQAFFH8FAAIDAAIK8gYBFAB3AAADAAIK8gYBFAB3AAA1AAQKfy4AAwMACgpfDbkrAMYBAAMACgpfDbkrAMYBAAsABgpBB8deAKMAAAAA.Daladin:BAAANQADCggICAABNQAECgoKLgAGAAYeAA==.Dalasaursrex:BAABNQAECn8uAAMGAAoKBh5TUACZAgAGAAoKch1TUACZAgAMAAUK5hyNDgBSAQAAAA==.Dangerfiëld:BAAANQAECgIIAQAAAA==.Dawnwell:BAAANQADCgYICgAAAA==.',
De='Deadfisch:BAAANQADCgQIBAABNQADCggIGQAKAAAAAA==.Deathknig:BAAANQADCggICAAAAA==.Demious:BAABNQAECn8UAAIJAAcK6REbkADpAQAJAAcK6REbkADpAQAAAA==.Demmu:BAAANQABCgMIAQAAAA==.Demonfister:BAAANQAECgYICAAAAA==.Demonkiller:BAAANQAECgIIBQAAAA==.Desorion:BAAANQABCgIIAgAAAA==.Dethstriker:BAAANQAECgcIEwAAAA==.Dethwyrm:BAAANQABCgIIAgAAAA==.Devolu:BAAANQADCgUICAAAAA==.Devvmonk:BAAANQADCgQIBAABNQAECgMIBgAKAAAAAA==.',
Di='Didi:BAAANQADCggIAQAAAA==.Dilfzdormu:BAAANQADCgYIBgAAAA==.Dindaratwo:BAABNQAECn8sAAINAAkKCgu4KQBXAQANAAkKCgu4KQBXAQAAAA==.',
Dj='Djunglebook:BAAANQAECgUIBQAAAA==.',
Do='Dokta:BAABNQAECn8YAAIOAAcKcgvWGQD/AAAOAAcKcgvWGQD/AAAAAA==.Dontula:BAAANQAECgIIAgAAAA==.',
Dr='Drathal:BAAANQAECgQIBAAAAA==.Druaa:BAAANQADCgQIBAABNQAECgYIGwAEAOoYAA==.',
Du='Dumolin:BAAANQAECgIIAQAAAA==.',
Ec='Eclïpse:BAAANQABCgIIAgAAAA==.',
Ed='Eddiedean:BAAANQAECggIDgAAAA==.Edric:BAAANQADCggIGgAAAA==.',
El='Electolytic:BAAANQAECgUIBAAAAA==.Elfgonewild:BAAANQADCgUIBgAAAA==.Ellessra:BAAANQADCgcIDwAAAA==.Elma:BAAANQADCggICAAAAA==.Elnegrouno:BAABNQAECn8iAAIGAAgKnxMUewAnAgAGAAgKnxMUewAnAgAAAA==.',
Er='Eragone:BAAANQAECgMIBAAAAA==.Eragora:BAAANQADCgUICQAAAA==.Errdrick:BAAANQAECgYIEQAAAA==.',
Et='Etoro:BAAANQADCgIIAgAAAA==.',
Fa='Faeyri:BAAANQAECgYIDAAAAA==.Fawntastic:BAAANQADCggIEAAAAA==.',
Fe='Feeri:BAAANQAECgEIAgAAAA==.Feyrbrand:BAABNQAECn8qAAIPAAoKQhHTEAC0AQAPAAoKQhHTEAC0AQAAAA==.',
Fi='Fischnchips:BAAANQADCgQIBAAAAA==.Fischticuffs:BAAANQADCggIGQAAAA==.',
Fl='Flagellation:BAAANQAECgQIBAAAAA==.',
Fo='Fourid:BAABNQAECn8dAAIGAAkK+xbAVwDAAQAGAAkK+xbAVwDAAQAAAA==.',
Fr='Frostfirer:BAAANQADCgIIAgAAAA==.',
Ga='Gallyn:BAABNQAECn86AAMQAAoKnxy6GACSAgARAAoKxRkYGQC0AgAQAAkKnxm6GACSAgAAAA==.',
Gi='Giizmo:BAAANQADCgYIBgAAAA==.',
Gl='Glacierrock:BAAANQADCgMIAwAAAA==.Gloria:BAABNQAECn8yAAIEAAoKxhh5IwB2AgAEAAoKxhh5IwB2AgAAAA==.Glyndor:BAAANQADCgYIBgAAAA==.',
Go='Googlyboogli:BAAANQAECgMIBgAAAA==.',
Gr='Grail:BAAANQAECgEIAQAAAA==.Grogar:BAAANQADCgIIAgAAAA==.',
Gu='Gunslinger:BAAANQAECgUIDQAAAA==.',
Ha='Halenicion:BAAANQAECgIIAQAAAA==.Hankthetank:BAAANQADCgYIBgAAAA==.Hazza:BAAANQADCgUIBQABNQAFFAQICAASAFkQAA==.',
Hi='Hippoltyos:BAABNQAECn8zAAIHAAoKCBExPwAFAgAHAAoKCBExPwAFAgAAAA==.',
Ho='Honestlee:BAAANQADCgMIAwAAAA==.Honourablee:BAAANQADCgQIBAAAAA==.',
Hu='Hunkacrap:BAAANQABCgIIAgAAAA==.Huntaa:BAAANQADCggIEgABNQAECgYIGwAEAOoYAA==.Huntardiness:BAABNQAECn8nAAMJAAkKoxOnPAAoAgAJAAkKoxOnPAAoAgATAAcKbgisRwAfAQAAAA==.',
Hy='Hymnals:BAACNQAFFH8LAAMMAAUKVBpqAQAsAQAMAAQKBhpqAQAsAQAGAAMKRRlDIwDkAAA1AAQKfyQAAwwACgoPJvUDAIsCAAYACQqHJMQlACIDAAwABwqlJPUDAIsCAAAA.',
Ic='Icealia:BAAANQAECgMIBAABNQAFFAMICAANAPAEAA==.',
Is='Isus:BAAANQAECgMIAwAAAA==.',
Iv='Ive:BAABNQAECn9IAAQSAAoKUSOFGQAhAwASAAkKNiOFGQAhAwAUAAUKLiIeDgByAQAVAAMKGyCsLQAVAQAAAA==.',
Ja='Jadeflower:BAAANQAECgQIBAAAAA==.Jarnunvosk:BAAANQADCgMIAwAAAA==.Jasmindinn:BAAANQAECgcIBgAAAA==.Jayber:BAAANQAECgEIAQAAAA==.',
Ji='Jimbearlushi:BAACNQAFFH8NAAIWAAUKOBTaCQAuAQAWAAUKOBTaCQAuAQA1AAQKfy8AAxYACgrkHlERABcCABYACgrkHlERABcCABcABwr9FXoVAIwBAAAA.',
Ju='Judelly:BAAANQAECgIIAgAAAA==.Juicebox:BAAANQAECggIEwAAAA==.Justjakk:BAAANQADCgEIAgAAAA==.',
Ka='Kabball:BAAANQAECgEIAwAAAA==.Kabr:BAAANQADCgYICQAAAA==.Kalez:BAAANQADCggIEQAAAA==.Kalibar:BAABNQAECn8UAAIBAAcKjxjBOgD5AQABAAcKjxjBOgD5AQAAAA==.Kamakaz:BAABNQAECn8kAAMEAAoKuBdQLABDAgAEAAoKuBdQLABDAgAIAAcKCQrtXwArAQAAAA==.Kamasdruid:BAAANQAECggIBwAAAA==.Kamasmage:BAAANQAECgYIBQAAAA==.Kandi:BAAANQADCgMIAwAAAA==.Kaviryon:BAAANQADCgIIBAAAAA==.Kaywhy:BAABNQAECn8xAAIYAAoKzR6LEQDjAgAYAAoKzR6LEQDjAgAAAA==.',
Ki='Kichack:BAAANQADCgMIBQAAAA==.Kimchie:BAAANQAECgIIAgAAAA==.Kinqanduin:BAAANQADCggIFAAAAA==.',
Kj='Kjdh:BAABNQAECn9GAAIZAAoKTCGfCwBQAwAZAAoKTCGfCwBQAwAAAA==.',
Kn='Knowndeath:BAAANQAECgIIAgABNQAECgkJJwAOALUcAA==.Knuckles:BAABNQAECn8YAAIGAAcKSw1ShQBEAQAGAAcKSw1ShQBEAQAAAA==.',
Ko='Koanu:BAAANQADCggIDAAAAA==.Kob:BAABNQAECn8WAAQSAAgKVwgPvQBTAQASAAgKAAgPvQBTAQAUAAEKTAggMAA1AAAVAAEKNgHmiAAaAAAAAA==.Kogun:BAAANQAECgIIAwAAAA==.Kozalth:BAAANQADCgcIFwAAAA==.',
Kt='Ktom:BAABNQAECn82AAIIAAoK3iB0EwBWAwAIAAoK3iB0EwBWAwAAAA==.',
Ku='Kurayami:BAAANQAECgQIBAAAAA==.',
La='Lancelot:BAAANQAECgIIAwAAAA==.Lawndown:BAAANQADCgIIAgAAAA==.Lawnsifer:BAAANQADCgMIAwAAAA==.',
Li='Litchlord:BAAANQADCgYIBgAAAA==.Liv:BAAANQAECgcICQAAAA==.',
Lo='Loax:BAAANQADCgUJBQAAAA==.Loek:BAAANQADCgUIBQAAAA==.Longpong:BAAANQAECgQICgAAAA==.Louhi:BAAANQAECgQIBwAAAA==.Loveshaq:BAAANQAECgUIBQAAAA==.',
Lu='Lunar:BAABNQAECn8oAAIaAAoK1BjzJgCcAgAaAAoK1BjzJgCcAgAAAA==.',
Ly='Lystat:BAAANQAECgQIBAAAAA==.',
Ma='Magra:BAABNQAECn8mAAIbAAkK0A86DACNAQAbAAkK0A86DACNAQAAAA==.Magêyalook:BAAANQADCgMIAwABNQAECgkJIgAQAA8NAA==.Malogg:BAAANQABCggIFAAAAA==.Manzz:BAAANQADCggICwAAAA==.Mariahscary:BAABNQAECn8vAAISAAoKtAxVWQCPAQASAAoKtAxVWQCPAQAAAA==.Marisol:BAAANQAECgEIAgAAAA==.Maskimxul:BAAANQABCgEIAQAAAA==.Mattob:BAAANQADCggIFgAAAA==.Maznificent:BAAANQADCgYIGwAAAA==.',
Me='Meandmypal:BAACNQAFFH8QAAIcAAcK9RtDAABAAgAcAAcK9RtDAABAAgA1AAQKfz0AAhwACgqBJUkAAHgDABwACgqBJUkAAHgDAAAA.Meatspinz:BAAANQADCggIDQAAAA==.Meesodead:BAABNQAECn8iAAIDAAkKXA6JPABtAQADAAkKXA6JPABtAQAAAA==.Mello:BAABNQAECn8rAAIGAAoKthcLMABYAgAGAAoKthcLMABYAgAAAA==.Mesteris:BAAANQADCggICAAAAA==.Metalhead:BAAANQADCgYIBgAAAA==.',
Mi='Midiane:BAAANQAECgIIAgAAAA==.Mirba:BAAANQAECgYIDQAAAA==.',
Mk='Mknight:BAAANQAECgMIEAAAAA==.',
Mo='Moments:BAAANQADCggICAAAAA==.Monsterdeath:BAAANQAECgIJAgAAAA==.',
['Må']='Måladroit:BAAANQADCgIIAgAAAA==.',
Na='Nareík:BAABNQAECn8zAAMdAAoKAhJ9GwCYAQAZAAgKYhBMOwDcAQAdAAoKxg99GwCYAQAAAA==.Nazarath:BAAANQABCgIIAgAAAA==.',
Ne='Neeru:BAAANQABCgIIAgAAAA==.Neriak:BAABNQAECn82AAIaAAgKlBZTKwBtAQAaAAgKlBZTKwBtAQAAAA==.Newa:BAAANQAECgEIAQAAAA==.',
Ni='Nightwater:BAACNQAFFH8IAAINAAMK8ASkDAClAAANAAMK8ASkDAClAAA1AAQKfygAAw0ACgqqEwYhACECAA0ACgqqEwYhACECABoAAQoQBaW1AC0AAAAA.',
Ob='Obouuld:BAAANQADCgQIBAAAAA==.',
Or='Orchop:BAAANQADCgUIBgAAAA==.Orenrim:BAAANQADCgMIAwABNQAECgQIBAAKAAAAAA==.',
Os='Osanyin:BAAANQADCggIHQABNQAECgQIBgAKAAAAAA==.',
Pa='Paado:BAAANQADCgEIAQAAAA==.Paulterian:BAAANQAECgUIDQAAAA==.',
Pe='Pentagonjr:BAAANQADCgUIBQAAAA==.',
Pf='Pffthmgcdrgn:BAAANQADCgQICAAAAA==.',
Ph='Phinehas:BAAANQADCggJCAAAAA==.',
Po='Poldalina:BAAANQADCggIIwAAAA==.',
Pr='Pr:BAAANQADCgYIBgAAAA==.Priesaa:BAAANQAECgQIDAABNQAECgYIGwAEAOoYAA==.Proverbs:BAAANQABCgIIAgAAAA==.',
Pu='Pumplord:BAAANQADCgIIAgAAAA==.',
Qe='Qeynos:BAABNQAECn8bAAMCAAcK4g7/dABEAQACAAcK4g7/dABEAQALAAEKAAC52wAiAAAAAA==.',
Ql='Qlona:BAAANQAECgYIDQAAAA==.',
Qu='Quazeemoto:BAAANQAECgQIBAAAAA==.',
Ra='Raalen:BAAANQABCgYICwAAAA==.Rainknuckles:BAABNQAECn88AAIBAAoK3x1mEgD8AgABAAoK3x1mEgD8AgAAAA==.Ratrenot:BAAANQADCggIDAAAAA==.Ravael:BAAANQADCgUIBwAAAA==.Rayshano:BAAANQADCggICAABNQAECgcICwAKAAAAAA==.',
Re='Redfisch:BAAANQADCgUIBQABNQADCggIGQAKAAAAAA==.Resia:BAAANQADCggIEAAAAA==.Retailsucks:BAAANQADCgcIFQAAAA==.Revocsid:BAAANQADCggIHAAAAA==.Rezza:BAAANQADCgUIBgAAAA==.',
Ri='Ridethewave:BAAANQADCgIIAgAAAA==.Rikka:BAAANQADCgQIBAAAAA==.',
Ro='Rottingtree:BAABNQAECn8dAAMbAAcKEw2vFgBIAQAbAAcKEw2vFgBIAQAeAAEK5AKT0AEuAAAAAA==.',
Ru='Rustynails:BAABNQAECn8uAAIfAAoKkRbqAQAXAgAfAAoKkRbqAQAXAgAAAA==.',
Ry='Ryvalz:BAAANQAECgYICgAAAA==.',
Sa='Sacrafischal:BAAANQADCgcICwAAAA==.Saibur:BAAANQAECgYIDQAAAA==.Sazzul:BAABNQAECn8WAAIgAAcKOBVdEgCtAQAgAAcKOBVdEgCtAQAAAA==.',
Sc='Scynx:BAAANQAECgEIAgAAAA==.',
Se='Seaka:BAABNQAECn84AAMNAAoKJxj1GAB1AgANAAoKJxj1GAB1AgAaAAMKFhF/kQCRAAAAAA==.Sernix:BAAANQAECgMIDgAAAA==.',
Sh='Shadegrim:BAAANQAECgEIAQAAAA==.Shamanic:BAAANQAECggICAAAAA==.Shamany:BAABNQAECn8bAAQEAAYK6hiFVQCLAQAEAAYK6hiFVQCLAQAgAAUKCgwdIwApAQAIAAEKAACQDAEAAAAAAA==.Shamnick:BAAANQAECgYIBgAAAA==.Shariya:BAAANQAECgYICgAAAA==.Shiftyfans:BAAANQADCggIIwAAAA==.Shivon:BAAANQAECgQIBAAAAA==.',
Sl='Slamin:BAAANQADCgYIBwAAAA==.',
Sn='Snowaxe:BAAANQADCgIIAgAAAA==.Snowwind:BAAANQAECgQICAAAAA==.',
So='Solthea:BAAANQABCgQIBgAAAA==.Sonar:BAABNQAECn9HAAIJAAoKnyDtFQDQAgAJAAoKnyDtFQDQAgAAAA==.Sonasham:BAAANQADCggIIwAAAA==.Sonnybear:BAAANQADCggIIwAAAA==.Soulhatcher:BAAANQAECggIDwAAAA==.Soulslinger:BAAANQABCgQIBQAAAA==.Soxs:BAAANQAECgUICQAAAA==.',
Sp='Spawnofdeath:BAAANQAECgIIAwAAAA==.Spectrelok:BAAANQAECgMIBAAAAA==.Spectrepunch:BAAANQAECgUIDwAAAA==.',
St='Steàlthy:BAABNQAECn8iAAIQAAkKDw3pUABxAQAQAAkKDw3pUABxAQAAAA==.Stickychikn:BAAANQADCgYIBgAAAA==.Stompygnome:BAABNQAECn8VAAMOAAcK6hB1IABKAQAOAAQKWB11IABKAQAGAAcK6AQquADSAAAAAA==.',
Sy='Syrila:BAABNQAECn8lAAIBAAkKTBOjOgD6AQABAAkKTBOjOgD6AQAAAA==.',
Ta='Tartanus:BAAANQADCgQIBAAAAA==.Tayzetv:BAAANQADCgcIBwABNQAECgQIBQAKAAAAAA==.',
Te='Teramiah:BAAANQADCgMIAwAAAA==.',
Th='Thorall:BAAANQADCgQIAwAAAA==.Thylight:BAAANQADCgIIAgAAAA==.',
Ti='Tippy:BAACNQAFFH8QAAIDAAcK1hvwAwDlAQADAAcK1hvwAwDlAQA1AAQKfzgAAgMACgpSJTASAPwCAAMACgpSJTASAPwCAAAA.',
To='Tombstone:BAABNQAECn84AAMRAAoKjhllGgCqAgARAAoKzxdlGgCqAgAQAAYKaRcqUgBsAQAAAA==.Toowongfoo:BAACNQAFFH8UAAIWAAcKzgttBQAXAQAWAAcKzgttBQAXAQA1AAQKf0AAAxYACgoeIY4GAO0CABYACgoeIY4GAO0CABcACApLGY8FAAgCAAAA.',
Ty='Tygrana:BAAANQADCgYIBgAAAA==.',
Ug='Uglysham:BAABNQAECn8tAAIEAAkK9x7lDwAVAwAEAAkK9x7lDwAVAwAAAA==.',
Um='Umbranecros:BAAANQADCgQIBQAAAA==.',
Un='Underdog:BAABNQAECn8WAAMTAAcKTBPDIAArAQATAAcKTBPDIAArAQAJAAEKVw7yJQFCAAAAAA==.Unpredictabl:BAAANQAECgUIBQAAAA==.',
Us='Usui:BAAANQADCgUIBQAAAA==.',
Va='Vaerie:BAAANQADCgYIBgAAAA==.Vagindivin:BAABNQAECn8ZAAMhAAkKXBaIDAD9AQAhAAgKARmIDAD9AQAZAAEKggbqmwAnAAAAAA==.Valyteil:BAAANQAECgUIBwAAAA==.',
Ve='Venngance:BAAANQAECgYIDQAAAA==.Vercingetorx:BAAANQADCgIIAgAAAA==.',
Vi='Virus:BAABNQAECn8cAAMSAAgKKBCIVQCaAQASAAgKKBCIVQCaAQAVAAIKuQMYbQBFAAAAAA==.',
Vo='Void:BAAANQAECggIEQAAAA==.Voidkity:BAAANQAECgYIEQAAAA==.',
Wa='Wakax:BAABNQAECn8iAAIMAAkKyRdxBwD9AQAMAAkKyRdxBwD9AQAAAA==.Walberson:BAAANQADCgcIBwAAAA==.Walkleydk:BAAANQAECggICAAAAA==.Warfield:BAAANQAECgUIEQAAAA==.Warmoose:BAAANQADCggICAABNQAECgkJGQAhAFwWAA==.',
We='Weediez:BAAANQADCgYJCAAAAA==.',
Wi='Wildfrost:BAABNQAECn8dAAIeAAUKQAJJCQF/AAAeAAUKQAJJCQF/AAAAAA==.Willienelson:BAAANQAECggIDgAAAA==.',
Wr='Wrathsome:BAAANQAECgYIDQAAAA==.',
Wy='Wyrmboy:BAAANQABCgQIBQAAAA==.Wyterd:BAABNQAECn8jAAIJAAgKVxJTdwCGAQAJAAgKVxJTdwCGAQAAAA==.',
Xa='Xaernach:BAAANQADCgQIBgAAAA==.Xalome:BAAANQADCgUIEwAAAA==.',
Xo='Xoxo:BAAANQAFFAEIAQABNQAFFAQIBAAKAAAAAA==.',
Ya='Yanza:BAAANQADCgQIBAAAAA==.',
Yo='Yoing:BAAANQADCggICAABNQADCggICAAKAAAAAA==.',
Za='Zarkus:BAAANQAECgUICAAAAA==.Zaruknark:BAABNQAECn8XAAIJAAkKFgkxgABxAQAJAAkKFgkxgABxAQAAAA==.',
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
