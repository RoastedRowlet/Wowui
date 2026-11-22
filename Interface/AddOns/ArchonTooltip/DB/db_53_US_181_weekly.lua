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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane','Shaman-Restoration','Evoker-Augmentation','Evoker-Devastation','Paladin-Retribution','Warrior-Arms','Priest-Holy','Shaman-Elemental','Hunter-BeastMastery','Mage-Frost','Unknown-Unknown','DeathKnight-Blood','Warrior-Fury','Druid-Restoration','Warrior-Protection','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','Warlock-Demonology','Hunter-Marksmanship','Hunter-Survival','Warlock-Affliction','Warlock-Destruction','Monk-Windwalker','Monk-Brewmaster','Priest-Shadow','DemonHunter-Havoc','Druid-Balance','DemonHunter-Devourer','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abert:BAAANQAECgUIEAAAAA==.',
Ac='Acts:BAAANQAECgUIBQAAAA==.',
Ad='Adalinda:BAAANQADCgQIBAABNQAFFAIIBQABAK4XAA==.Adra:BAAANQADCggICAAAAA==.Adrelorà:BAAANQADCgcIDQAAAA==.',
Ae='Aerähn:BAAANQABCggIKwAAAA==.',
Ag='Agathahaknes:BAAANQADCgEIAQAAAA==.Agnor:BAABNQAECn8rAAICAAkKqRMATQDgAQACAAkKqRMATQDgAQAAAA==.',
Ai='Aindria:BAAANQADCggICAAAAA==.',
Al='Alatir:BAAANQADCggIFgAAAA==.',
Am='Ameri:BAAANQAECgEIAQABNQAFFAgIEQADAKUcAA==.Ammeka:BAAANQABCggIEgAAAA==.',
An='Anahline:BAAANQAECgEIAQAAAA==.Andre:BAABNQAECn8VAAIEAAkKuhRyeAC9AQAEAAkKuhRyeAC9AQABNQAFFAYIEwAFAEETAA==.Anjaini:BAAANQADCgIIAgAAAA==.Antibubble:BAABNQAECn8xAAIDAAoKMB9GFADqAgADAAoKMB9GFADqAgAAAA==.Antimatter:BAABNQAECn8lAAMGAAkKihdnBQAsAgAGAAkKphVnBQAsAgAHAAkKdhWdBwAYAgAAAA==.Anwal:BAACNQAFFH8FAAIBAAIKrheOGwCoAAABAAIKrheOGwCoAAA1AAQKfzcAAwEACgrAI8MOAEwDAAEACgrAI8MOAEwDAAgABwpFDuDjAFQBAAAA.',
Ar='Arceilth:BAAANQAECgYICwAAAA==.Argus:BAAANQADCgIIAgAAAA==.Arissidis:BAAANQAECgUIBQAAAA==.Arithana:BAAANQAECgUIBQABNQAECgkJKwAJAHIZAA==.Arithfury:BAABNQAECn8rAAIJAAkKchmOawBPAgAJAAkKchmOawBPAgAAAA==.Arkaius:BAAANQADCggICgAAAA==.Articuno:BAAANQADCgUICQAAAA==.Arwenloa:BAAANQAECgQIBAABNQAECgkJJgAFAPYOAA==.',
As='Ashwynn:BAAANQAECgcIEAAAAA==.Aske:BAAANQAECgYIDQAAAA==.',
At='Atalnoa:BAAANQADCgYICAAAAA==.',
Au='Aura:BAAANQADCgIIAgABNQAECgkJHgAKAEYSAA==.',
Az='Azuresun:BAABNQAECn8gAAILAAUK3AePywD8AAALAAUK3AePywD8AAAAAA==.',
Ba='Ballak:BAAANQAECgIIAgAAAA==.Bambeeno:BAAANQABCgYIBgAAAA==.Barnardo:BAAANQABCgIJAgAAAA==.Bassmasta:BAABNQAECn8rAAIMAAoKpiJmHAAmAwAMAAoKpiJmHAAmAwAAAA==.Baston:BAAANQAECgQIBAAAAA==.',
Be='Beatin:BAAANQAECgQIBwAAAA==.Belinda:BAAANQAECgIIAgAAAA==.Bentö:BAAANQADCgcIBwAAAA==.Beny:BAAANQAECgYIEQAAAA==.',
Bi='Biscüits:BAAANQADCgQIBAAAAA==.',
Bl='Blackskillz:BAAANQAECgMIAwABNQAECggIIgAJAJ8TAA==.Bloodstorm:BAAANQAECgIIAQAAAA==.Bloopydoo:BAABNQAECn8WAAINAAYKmAsIHwDcAAANAAYKmAsIHwDcAAAAAA==.Bluefisch:BAAANQADCgEIAQAAAA==.',
Bo='Boiorix:BAAANQADCgEIAQABNQAECgQIBwAOAAAAAA==.Borim:BAAANQAECgUIDQAAAA==.',
Br='Braincell:BAAANQAECgQIBAAAAA==.Brandymae:BAAANQADCgYIBgAAAA==.Brassidas:BAAANQAECgEIAQAAAA==.Brbpoopin:BAAANQADCgYIDwAAAA==.Bromancehomo:BAAANQADCgUIBgAAAA==.Bruwdfyre:BAAANQAECggIEQAAAA==.',
Bu='Bubbleshield:BAAANQADCgcIBwAAAA==.',
Ca='Cassdaman:BAAANQAECgEIAQAAAA==.Castani:BAAANQAECggIEQAAAA==.',
Ce='Celestyal:BAAANQAECgQIBwAAAA==.',
Ch='Choshi:BAAANQADCgMIAwABNQAECgYIGwAFAOoYAA==.',
Ci='Cindy:BAAANQAECggIGwABNQAFFAEIAgAOAAAAAQ==.',
Co='Coast:BAAANQAECgUICgAAAA==.Confidential:BAAANQADCgIIAgAAAA==.Cootpal:BAABNQAECn80AAIIAAoKGxlfUQChAgAIAAoKGxlfUQChAgAAAA==.',
Cr='Crazyloon:BAAANQAECgYIEAAAAA==.Crewdle:BAAANQADCggICAAAAA==.',
Cy='Cynawyne:BAAANQABCgMIAwABNQADCgcIFgAOAAAAAA==.Cynthea:BAAANQABCgYIDQAAAA==.',
['Cö']='Cörinthian:BAAANQAECgYICAAAAA==.',
Da='Daddybod:BAACNQAFFH8HAAIDAAIK8gakGQBwAAADAAIK8gakGQBwAAA1AAQKfzQAAwMACgqKD8cxAOEBAAMACgqKD8cxAOEBAA8ABgpBB1dsAJ0AAAAA.Daladin:BAAANQADCggICAABNQAECgoKLgAJAAYeAA==.Dalasaursrex:BAABNQAECn8uAAMJAAoKBh5TUACZAgAJAAoKch1TUACZAgAQAAUK5hw5EwBFAQAAAA==.Dangerfiëld:BAAANQAECgIIAQAAAA==.Dawnwell:BAAANQADCgYICgAAAA==.',
De='Deadfisch:BAAANQADCgQIBAABNQADCggIGQAOAAAAAA==.Deathknig:BAAANQADCggICAAAAA==.Demious:BAABNQAECn8UAAIMAAcK6REbkADpAQAMAAcK6REbkADpAQAAAA==.Demmu:BAAANQABCgMIAQAAAA==.Demonfister:BAAANQAECgYICAAAAA==.Demonkiller:BAAANQAECgIIBQAAAA==.Demonseeds:BAAANQAECgEIAQAAAA==.Desorion:BAAANQABCgIIAgAAAA==.Dethstriker:BAAANQAECgcIEwAAAA==.Dethwyrm:BAAANQABCgIIAgAAAA==.Devolu:BAAANQAECgUIBQAAAA==.Devvmonk:BAAANQADCgQIBAABNQAECgMIBgAOAAAAAA==.',
Di='Didi:BAAANQADCggIAQAAAA==.Dilfzdormu:BAAANQADCgYIBgAAAA==.Dindaratwo:BAABNQAECn8zAAIRAAoK9ArLLgB5AQARAAoK9ArLLgB5AQAAAA==.',
Dj='Djunglebook:BAAANQAECgUIBQAAAA==.',
Do='Dokta:BAABNQAECn8ZAAISAAcK3gxLHwADAQASAAcK3gxLHwADAQAAAA==.Dontula:BAAANQAECgIIAgAAAA==.',
Dr='Drathal:BAAANQAECgQIBAAAAA==.Druaa:BAAANQADCgQIBAABNQAECgYIGwAFAOoYAA==.',
Du='Dumolin:BAAANQAECgIIAQAAAA==.',
Ec='Eclïpse:BAAANQABCgIIAgAAAA==.',
Ed='Eddiedean:BAAANQAECggIDgAAAA==.Edric:BAAANQADCggIGgAAAA==.',
El='Electolytic:BAAANQAECgUIBAAAAA==.Elfgonewild:BAAANQAECgEIAQAAAA==.Ellessra:BAAANQADCgcIDwAAAA==.Elma:BAAANQADCggICQAAAA==.Elnegrouno:BAABNQAECn8iAAIJAAgKnxMUewAnAgAJAAgKnxMUewAnAgAAAA==.',
Er='Eragone:BAAANQAECgMIBAAAAA==.Eragora:BAAANQADCgUICQAAAA==.Errdrick:BAAANQAECgYIEQAAAA==.',
Et='Etoro:BAAANQADCgIIAgAAAA==.',
Ev='Evokaa:BAAANQADCgUIBQABNQAECgYIGwAFAOoYAA==.',
Fa='Faeyri:BAABNQAECn8bAAILAAoK5BHeOADxAQALAAoK5BHeOADxAQAAAA==.Fawntastic:BAAANQADCggIEAAAAA==.',
Fe='Feeri:BAAANQAECgEIAgAAAA==.Feyrbrand:BAABNQAECn8rAAITAAoKQhFxFACwAQATAAoKQhFxFACwAQAAAA==.',
Fi='Fischnchips:BAAANQADCgQIBAAAAA==.Fischticuffs:BAAANQADCggIGQAAAA==.',
Fl='Flagellation:BAAANQAECgQIBAAAAA==.',
Fo='Fourid:BAABNQAECn8eAAIJAAkK+xYtbgC3AQAJAAkK+xYtbgC3AQAAAA==.',
Fr='Frostfirer:BAAANQADCgIIAgAAAA==.',
Ga='Gallyn:BAABNQAECn89AAMUAAoKqRxXHQCcAgAVAAoKxRkYGQC0AgAUAAkKGBpXHQCcAgAAAA==.',
Gi='Giizmo:BAAANQADCgYIBgAAAA==.',
Gl='Glacierrock:BAAANQADCgMIAwAAAA==.Gloria:BAABNQAECn83AAIFAAoKVhpqJgCVAgAFAAoKVhpqJgCVAgAAAA==.Glyndor:BAAANQADCgYIBgAAAA==.',
Go='Googlyboogli:BAAANQAECgMIBwAAAA==.',
Gr='Grail:BAAANQAECgEIAQAAAA==.Grogar:BAAANQADCgIIAgAAAA==.',
Gu='Gunslinger:BAAANQAECgUIDQAAAA==.',
Ha='Halenicion:BAAANQAECgIIAQAAAA==.Hankthetank:BAAANQADCgYIBgAAAA==.Hazza:BAAANQADCgUIBQABNQAFFAQICAAWAFkQAA==.',
Hi='Hippoltyos:BAABNQAECn89AAIKAAoKjhQvOgBTAgAKAAoKjhQvOgBTAgAAAA==.',
Ho='Honestlee:BAAANQADCgMIAwAAAA==.Honourablee:BAAANQADCgQIBAAAAA==.',
Hu='Hunkacrap:BAAANQABCgIIAgAAAA==.Huntaa:BAAANQADCggIEwABNQAECgYIGwAFAOoYAA==.Huntardiness:BAABNQAECn81AAQXAAkK5BUWFgDnAQAMAAkKoxM7VAAjAgAXAAkK+g4WFgDnAQAYAAQKQQ48DQDLAAAAAA==.',
Hy='Hymnals:BAACNQAFFH8LAAMQAAUKVBpqAQAsAQAQAAQKBhpqAQAsAQAJAAMKRRlDIwDkAAA1AAQKfyUAAxAACgoPJm0FAIICAAkACQqHJMQlACIDABAABwqlJG0FAIICAAAA.',
Ic='Icealia:BAAANQAECgMIBAABNQAFFAQIDQARABMEAA==.',
Is='Isus:BAAANQAECgMIAwAAAA==.',
Iv='Ive:BAABNQAECn9LAAQWAAoKUSOFGQAhAwAWAAkKNiOFGQAhAwAZAAUKLiIeDgByAQAaAAMKGyCsLQAVAQAAAA==.',
Ja='Jadeflower:BAAANQAECgQIBAAAAA==.Jarnunvosk:BAAANQADCgMIAwAAAA==.Jasmindinn:BAAANQAECgcIBgAAAA==.Jayber:BAAANQAECgEIAQAAAA==.',
Ji='Jimbearlushi:BAACNQAFFH8NAAIbAAUKOBTaCQAuAQAbAAUKOBTaCQAuAQA1AAQKfy8AAxsACgrkHtsVABACABsACgrkHtsVABACABwABwr9FXoVAIwBAAAA.',
Ju='Judelly:BAAANQAECgIIAgAAAA==.Juicebox:BAAANQAECggIEwAAAA==.Justjakk:BAAANQADCgEIAgAAAA==.',
Ka='Kabball:BAAANQAECgEIAwAAAA==.Kabr:BAAANQADCgYICQAAAA==.Kalez:BAAANQADCggIEQAAAA==.Kalibar:BAABNQAECn8XAAIBAAgKoxrGMwBPAgABAAgKoxrGMwBPAgAAAA==.Kamakaz:BAABNQAECn8pAAMFAAoKzhhQOAA4AgAFAAoKzhhQOAA4AgALAAcKCQo+dQArAQAAAA==.Kamasdruid:BAAANQAECggIBwAAAA==.Kamasmage:BAAANQAECgYIBQAAAA==.Kandi:BAAANQADCgMIAwAAAA==.Kaywhy:BAABNQAECn8xAAIdAAoKzR6LEQDjAgAdAAoKzR6LEQDjAgAAAA==.',
Ki='Kichack:BAAANQADCgMIBgAAAA==.Kimchie:BAAANQAECgIIAgAAAA==.Kinqanduin:BAAANQADCggIFAAAAA==.',
Kj='Kjdh:BAABNQAECn9PAAIeAAoKbSKfCwBQAwAeAAoKbSKfCwBQAwAAAA==.',
Kn='Knowndeath:BAAANQAECgIIAgABNQAECgkJLgASAAgeAA==.Knuckles:BAABNQAECn8bAAIJAAgKyAzeiwBrAQAJAAgKyAzeiwBrAQAAAA==.',
Ko='Koanu:BAAANQADCggIDAAAAA==.Kob:BAABNQAECn8WAAQWAAgKVwgPvQBTAQAWAAgKAAgPvQBTAQAZAAEKTAggMAA1AAAaAAEKNgHmiAAaAAAAAA==.Kogun:BAAANQAECgIIAwAAAA==.Kozalth:BAAANQADCgcIFwAAAA==.',
Kt='Ktom:BAABNQAECn82AAILAAoK3iB0EwBWAwALAAoK3iB0EwBWAwAAAA==.',
Ku='Kurayami:BAAANQAECgQIBAAAAA==.',
La='Lancelot:BAAANQAECgIIAwAAAA==.Lawndown:BAAANQADCgIIAgAAAA==.Lawnsifer:BAAANQADCgMIAwAAAA==.',
Li='Litchlord:BAAANQADCgYIBgAAAA==.Liv:BAAANQAECggICgAAAA==.',
Lo='Loax:BAAANQADCgUJBQAAAA==.Loek:BAAANQADCgUIBQAAAA==.Longpong:BAAANQAECgQICgAAAA==.Louhi:BAAANQAECgQIDwAAAA==.Loveshaq:BAAANQAECgUIBQAAAA==.',
Lu='Lunar:BAABNQAECn8xAAIfAAoKoBosHgAQAgAfAAoKoBosHgAQAgAAAA==.',
Ly='Lystat:BAAANQAECgQIBAAAAA==.',
Ma='Magra:BAABNQAECn8tAAINAAoKYg87DQDFAQANAAoKYg87DQDFAQAAAA==.Magêyalook:BAAANQADCgMIAwABNQAECgoKJQAUAG0NAA==.Malogg:BAAANQABCggIFAAAAA==.Manzz:BAAANQADCggICwAAAA==.Mariahscary:BAABNQAECn88AAIWAAoK2w45VwDOAQAWAAoK2w45VwDOAQAAAA==.Marisol:BAAANQAECgMIBQAAAA==.Maskimxul:BAAANQABCgEIAQAAAA==.Mattob:BAAANQADCggIFgAAAA==.Maznificent:BAAANQADCgYIIAAAAA==.',
Me='Meandmypal:BAACNQAFFH8QAAIYAAcK9RtDAABAAgAYAAcK9RtDAABAAgA1AAQKfz8AAhgACgqeJWEAAHADABgACgqeJWEAAHADAAAA.Meatspinz:BAAANQADCggIDQAAAA==.Meesodead:BAABNQAECn8uAAMDAAoKIw9+QACZAQADAAoK/g1+QACZAQAPAAUKUQxuXgDJAAAAAA==.Mello:BAABNQAECn8xAAIJAAoKWRidOQBaAgAJAAoKWRidOQBaAgAAAA==.Mesteris:BAAANQADCggICQAAAA==.Metalhead:BAAANQADCgYIBgAAAA==.',
Mi='Mickie:BAAANQADCgEIAQAAAA==.Midiane:BAAANQAECgIIAgAAAA==.Mirba:BAAANQAECgYIDQAAAA==.',
Mk='Mknight:BAABNQAECn8YAAMCAAUKNAOTuQB6AAACAAQKqwKTuQB6AAADAAQKNAODngBfAAAAAA==.',
Mo='Moments:BAAANQADCggICAAAAA==.Monsterdeath:BAAANQAECgIJAgAAAA==.',
['Må']='Måladroit:BAAANQADCgIIAgAAAA==.',
Na='Nareík:BAABNQAECn84AAMgAAoKgxKHIQCTAQAeAAgKYhBMOwDcAQAgAAoKRxCHIQCTAQAAAA==.Nazarath:BAAANQABCgIIAgAAAA==.',
Ne='Neeru:BAAANQABCgIIAgABNQAECgMIAwAOAAAAAA==.Neriak:BAABNQAECn9EAAIfAAkK9RXZJgDGAQAfAAkK9RXZJgDGAQAAAA==.Newa:BAAANQAECgEIAQAAAA==.',
Ni='Nightwater:BAACNQAFFH8NAAIRAAQKEwRuDQDSAAARAAQKEwRuDQDSAAA1AAQKfygAAxEACgqqEwYhACECABEACgqqEwYhACECAB8AAQoQBaW1AC0AAAAA.',
Ob='Obouuld:BAAANQADCgQIBAAAAA==.',
Or='Orchop:BAAANQADCgUIBgAAAA==.Orenrim:BAAANQADCgMIAwABNQAECgQIBAAOAAAAAA==.',
Os='Osanyin:BAAANQAECgEIAQABNQAECgUIBgAOAAAAAA==.',
Pa='Paado:BAAANQADCgEIAQAAAA==.Paulterian:BAABNQAECn8UAAMBAAYKkRALdABZAQABAAYKkRALdABZAQAIAAQKfwN4XQGKAAAAAA==.',
Pe='Pentagonjr:BAAANQADCgUIBQAAAA==.',
Pf='Pffthmgcdrgn:BAAANQADCgQICAAAAA==.',
Ph='Phinehas:BAAANQADCggJCAAAAA==.',
Po='Poldalina:BAAANQADCggIIwAAAA==.',
Pr='Pr:BAAANQADCgYIBgAAAA==.Priesaa:BAAANQAECgQIDAABNQAECgYIGwAFAOoYAA==.Proverbs:BAAANQABCgIIAgAAAA==.',
Pu='Pumplord:BAAANQADCgIIAgAAAA==.',
Qe='Qeynos:BAABNQAECn8bAAMCAAcK4g7/dABEAQACAAcK4g7/dABEAQAPAAEKAAC52wAiAAAAAA==.',
Ql='Qlona:BAABNQAECn8UAAILAAkKdBfsJQBPAgALAAkKdBfsJQBPAgAAAA==.',
Qu='Quazeemoto:BAAANQAECgQIBAAAAA==.',
Ra='Raalen:BAAANQABCgYICwAAAA==.Rainknuckles:BAABNQAECn9FAAIBAAoKAx84FAAYAwABAAoKAx84FAAYAwAAAA==.Ratrenot:BAAANQADCggIDQAAAA==.Ravael:BAAANQADCgUIBwAAAA==.Rayshano:BAAANQADCggICAABNQAECgcICwAOAAAAAA==.',
Re='Redfisch:BAAANQADCgUIBgABNQADCggIGQAOAAAAAA==.Reliablé:BAAANQAECggICAAAAA==.Resia:BAAANQADCggIEAAAAA==.Retailsucks:BAAANQADCgcIFQAAAA==.Revocsid:BAAANQADCggIHAAAAA==.Rezza:BAAANQADCgUIBgAAAA==.',
Ri='Ridethewave:BAAANQADCgIIAgAAAA==.Rikka:BAAANQADCgQIBAAAAA==.',
Ro='Rottingtree:BAABNQAECn8dAAMNAAcKEw2vFgBIAQANAAcKEw2vFgBIAQAEAAEK5AKT0AEuAAAAAA==.',
Ru='Rustynails:BAABNQAECn8uAAIhAAoKkRbjBACxAgAhAAoKkRbjBACxAgAAAA==.',
Ry='Ryvalz:BAAANQAECgYICgAAAA==.',
Sa='Sacrafischal:BAAANQADCgcICwAAAA==.Saibur:BAAANQAECgYIDQAAAA==.Sazzul:BAABNQAECn8ZAAIiAAgKxhSvEgDsAQAiAAgKxhSvEgDsAQAAAA==.',
Sc='Scynx:BAAANQAECgEIAgAAAA==.',
Se='Seaka:BAABNQAECn9IAAMRAAoKvhn1GAB1AgARAAoKvhn1GAB1AgAfAAMKFhF/kQCRAAAAAA==.Sernix:BAAANQAECgQIDgAAAA==.',
Sh='Shadegrim:BAAANQAECgEIAQAAAA==.Shamanic:BAABNQAECn8ZAAILAAkKAw6FRADCAQALAAkKAw6FRADCAQAAAA==.Shamany:BAABNQAECn8bAAQFAAYK6hgxaAB9AQAFAAYK6hgxaAB9AQAiAAUKCgwdIwApAQALAAEKAAAmLQEAAAAAAA==.Shamnick:BAAANQAECgYIBgAAAA==.Shariya:BAABNQAECn8VAAIWAAYKEwWevQDWAAAWAAYKEwWevQDWAAAAAA==.Shiftyfans:BAAANQAECgcIBwAAAA==.Shivon:BAAANQAECgQIBAAAAA==.',
Sl='Slamin:BAAANQADCgYIBwAAAA==.',
Sn='Snowaxe:BAAANQADCgIIAgAAAA==.Snowwind:BAAANQAECgUIDQAAAA==.',
So='Solthea:BAAANQABCgQIBgAAAA==.Sonar:BAABNQAECn9TAAIMAAoKnyD3HgDEAgAMAAoKnyD3HgDEAgAAAA==.Sonasham:BAAANQADCggIIwAAAA==.Sonnybear:BAAANQADCggIIwAAAA==.Soulhatcher:BAABNQAECn8YAAIUAAkKnQnIWwCaAQAUAAkKnQnIWwCaAQAAAA==.Soulslinger:BAAANQABCgQIBQAAAA==.Soxs:BAAANQAECgUICQAAAA==.',
Sp='Spawnofdeath:BAAANQAECgIIAwAAAA==.Spectrelok:BAAANQAECgMIBAAAAA==.Spectrepunch:BAABNQAECn8VAAIbAAYKRQfrRgDnAAAbAAYKRQfrRgDnAAAAAA==.',
St='Steàlthy:BAABNQAECn8lAAIUAAoKbQ05VAC0AQAUAAoKbQ05VAC0AQAAAA==.Stickychikn:BAAANQADCgYIBgAAAA==.Stompygnome:BAABNQAECn8YAAMSAAgKgA91IABKAQASAAQKWB11IABKAQAJAAgKNQVLxADsAAAAAA==.',
Sy='Syrila:BAABNQAECn8xAAIBAAkKlhWwOwApAgABAAkKlhWwOwApAgAAAA==.',
Ta='Tartanus:BAAANQADCgQIBAAAAA==.Tayzetv:BAAANQADCgcIBwABNQAECgQIBQAOAAAAAA==.',
Te='Teramiah:BAAANQADCgMIAwAAAA==.',
Th='Thorall:BAAANQADCgQIAwAAAA==.Thylight:BAAANQADCgIIAgAAAA==.',
Ti='Tippy:BAACNQAFFH8RAAIDAAgKpRzwAwDlAQADAAgKpRzwAwDlAQA1AAQKf0YAAgMACgpzJbEGADcDAAMACgpzJbEGADcDAAAA.',
To='Tombstone:BAABNQAECn84AAMVAAoKjhllGgCqAgAVAAoKzxdlGgCqAgAUAAYKaRdEagBsAQAAAA==.Toowongfoo:BAACNQAFFH8WAAIbAAgKKQrGBQBYAQAbAAgKKQrGBQBYAQA1AAQKf0oAAxsACgpuISQHAPwCABsACgpuISQHAPwCABwACApLGfoGAAcCAAAA.',
Ty='Tygrana:BAAANQADCgYIBwAAAA==.',
Ug='Uglysham:BAABNQAECn8xAAIFAAkK9x6VFgACAwAFAAkK9x6VFgACAwAAAA==.',
Um='Umbranecros:BAAANQADCgQIBgAAAA==.',
Un='Underdog:BAABNQAECn8dAAMXAAgKiBNqHwB3AQAXAAgKiBNqHwB3AQAMAAEKVw6ZRAFCAAAAAA==.Unpredictabl:BAAANQAECgUIBQAAAA==.',
Us='Usui:BAAANQADCgUIBQAAAA==.',
Va='Vaerie:BAAANQADCgYIBgAAAA==.Vagindivin:BAABNQAECn8gAAMjAAoK4RgvCgDAAQAjAAoK4RgvCgDAAQAeAAEKggbqmwAnAAAAAA==.Valyteil:BAAANQAECgUICAAAAA==.',
Ve='Venngance:BAAANQAECgYIDQAAAA==.Vercingetorx:BAAANQADCgIIAgAAAA==.',
Vi='Virus:BAABNQAECn8oAAMWAAkKHRC6VQDTAQAWAAkKkA+6VQDTAQAaAAQKsQ0yHwByAAAAAA==.',
Vo='Void:BAAANQAECggIEQAAAA==.Voidkity:BAABNQAECn8WAAMdAAcKXhEFNQDqAAAdAAYKCA4FNQDqAAAKAAUKYgUcvQCzAAAAAA==.',
Wa='Wakax:BAABNQAECn8iAAIQAAkKyRdgCgDxAQAQAAkKyRdgCgDxAQAAAA==.Walberson:BAAANQADCgcIBwAAAA==.Walkleydk:BAAANQAECggICQAAAA==.Warfield:BAAANQAECgUIEQAAAA==.Warmoose:BAAANQADCggICAABNQAECgoKIAAjAOEYAA==.',
We='Weediez:BAAANQADCgYJCAAAAA==.',
Wi='Wildfrost:BAABNQAECn8iAAIEAAYKVAJsAwGvAAAEAAYKVAJsAwGvAAAAAA==.Willienelson:BAAANQAECggIDgAAAA==.',
Wr='Wrathsome:BAAANQAECgYIDQAAAA==.',
Wy='Wyrmboy:BAAANQABCgQIBQAAAA==.Wyterd:BAABNQAECn8jAAIMAAgKVxLYkgCQAQAMAAgKVxLYkgCQAQAAAA==.',
Xa='Xaernach:BAAANQADCgQIBgAAAA==.Xalome:BAAANQADCgUIEwAAAA==.',
Xo='Xoxo:BAAANQAFFAEIAQABNQAFFAQIBAAOAAAAAA==.',
Xy='Xypherus:BAAANQADCgEIAQAAAA==.',
Ya='Yanza:BAAANQADCgQIBAAAAA==.',
Yo='Yoing:BAAANQADCggICAABNQADCggICAAOAAAAAA==.',
Za='Zarkus:BAAANQAECgUICwAAAA==.Zaruknark:BAABNQAECn8bAAIMAAkKFgkUgAC6AQAMAAkKFgkUgAC6AQAAAA==.',
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
