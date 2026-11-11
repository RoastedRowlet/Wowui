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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane','Shaman-Restoration','Evoker-Devastation','Evoker-Augmentation','Paladin-Retribution','Warrior-Arms','Priest-Holy','Shaman-Elemental','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Blood','Warrior-Fury','Druid-Restoration','Warrior-Protection','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','Warlock-Demonology','Hunter-Marksmanship','Warlock-Affliction','Warlock-Destruction','Monk-Windwalker','Monk-Brewmaster','Priest-Shadow','DemonHunter-Havoc','Druid-Balance','Mage-Frost','Hunter-Survival','DemonHunter-Devourer','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abert:BAAANQAECgUIEAAAAA==.',
Ac='Acts:BAAANQAECgUIBQAAAA==.',
Ad='Adalinda:BAAANQADCgQIBAABNQAFFAIIBQABAK4XAA==.Adra:BAAANQADCggICAAAAA==.Adrelorà:BAAANQADCgcIDQAAAA==.',
Ae='Aerähn:BAAANQABCggIKwAAAA==.',
Ag='Agathahaknes:BAAANQADCgEIAQAAAA==.Agnor:BAABNQAECn8rAAICAAkKqRMATQDgAQACAAkKqRMATQDgAQAAAA==.',
Ai='Aindria:BAAANQADCggICAAAAA==.',
Al='Alatir:BAAANQADCggIFgAAAA==.',
Am='Ameri:BAAANQAECgEIAQABNQAFFAcIEAADANYbAA==.Ammeka:BAAANQABCggIEgAAAA==.',
An='Anahline:BAAANQAECgEIAQAAAA==.Andre:BAABNQAECn8VAAIEAAkKuhSFcAC9AQAEAAkKuhSFcAC9AQABNQAFFAYIEwAFAEETAA==.Anjaini:BAAANQADCgIIAgAAAA==.Antibubble:BAABNQAECn8xAAIDAAoKMB9GFADqAgADAAoKMB9GFADqAgAAAA==.Antimatter:BAABNQAECn8cAAMGAAkKihcHBwAaAgAHAAkKTRRBBQAeAgAGAAkKdhUHBwAaAgAAAA==.Anwal:BAACNQAFFH8FAAIBAAIKrhfeGACsAAABAAIKrhfeGACsAAA1AAQKfzcAAwEACgrAIwgNAFEDAAEACgrAIwgNAFEDAAgABwpFDuDjAFQBAAAA.',
Ar='Arceilth:BAAANQAECgYIDAAAAA==.Argus:BAAANQADCgIIAgAAAA==.Arissidis:BAAANQAECgEIAQAAAA==.Arithana:BAAANQAECgUIBgABNQAECgkJKwAJAHIZAA==.Arithfury:BAABNQAECn8rAAIJAAkKchmOawBPAgAJAAkKchmOawBPAgAAAA==.Arkaius:BAAANQADCggICgAAAA==.Articuno:BAAANQADCgUICQAAAA==.',
As='Ashwynn:BAAANQAECgYIDQAAAA==.Aske:BAAANQAECgYIDwAAAA==.',
At='Atalnoa:BAAANQADCgYICAAAAA==.',
Au='Aura:BAAANQADCgIIAgABNQAECgkJHgAKAEYSAA==.',
Az='Azuresun:BAABNQAECn8gAAILAAUK3AdLoQCwAAALAAUK3AdLoQCwAAAAAA==.',
Ba='Balerion:BAAANQAECgEIAwAAAA==.Ballak:BAAANQAECgIIAgAAAA==.Bambeeno:BAAANQABCgYIBgAAAA==.Barnardo:BAAANQABCgIJAgAAAA==.Bassmasta:BAABNQAECn8rAAIMAAoKpiJmHAAmAwAMAAoKpiJmHAAmAwAAAA==.Baston:BAAANQAECgQIBAAAAA==.',
Be='Beatin:BAAANQAECgQIBwAAAA==.Belinda:BAAANQAECgIIAgAAAA==.Bentö:BAAANQADCgcIBwAAAA==.Beny:BAAANQAECgYIEQAAAA==.',
Bi='Biscüits:BAAANQADCgQIBAAAAA==.',
Bl='Blackskillz:BAAANQAECgMIAwABNQAECggIIgAJAJ8TAA==.Bloodstorm:BAAANQAECgIIAgAAAA==.Bloopydoo:BAAANQAECgYIEgAAAA==.Bluefisch:BAAANQADCgEIAQAAAA==.',
Bo='Boiorix:BAAANQADCgEIAQABNQAECgQIBwANAAAAAA==.Borim:BAAANQAECgUIEQAAAA==.',
Br='Braincell:BAAANQAECgQIBAAAAA==.Brandymae:BAAANQADCgYIBgAAAA==.Brassidas:BAAANQAECgEIAQAAAA==.Brbpoopin:BAAANQADCgYIDwAAAA==.Bromancehomo:BAAANQADCgUIBgAAAA==.Bruwdfyre:BAAANQAECggIEQAAAA==.',
Bu='Bubbleshield:BAAANQADCgcIBwAAAA==.',
Ca='Castani:BAAANQAECgcIEAAAAA==.',
Ce='Celestyal:BAAANQAECgQIBwAAAA==.',
Ch='Choshi:BAAANQADCgMIAwABNQAECgYIGwAFAOoYAA==.',
Ci='Cindy:BAAANQAECggIGQABNQAFFAEIAgANAAAAAQ==.',
Co='Coast:BAAANQAECgUIBQAAAA==.Confidential:BAAANQADCgIIAgAAAA==.Cootpal:BAABNQAECn80AAIIAAoKGxlfUQChAgAIAAoKGxlfUQChAgAAAA==.',
Cr='Crazyloon:BAAANQAECgYIEAAAAA==.Crewdle:BAAANQADCggICAAAAA==.',
Cy='Cynawyne:BAAANQABCgMIAwABNQADCgcIFQANAAAAAA==.Cynthea:BAAANQABCgYIDQAAAA==.',
['Cö']='Cörinthian:BAAANQAECgQIBAAAAA==.',
Da='Daddybod:BAACNQAFFH8HAAIDAAIK8gYaFwBzAAADAAIK8gYaFwBzAAA1AAQKfzQAAwMACgqKDwotAOYBAAMACgqKDwotAOYBAA4ABgpBB2RmAKMAAAAA.Daladin:BAAANQADCggICAABNQAECgoKLgAJAAYeAA==.Dalasaursrex:BAABNQAECn8uAAMJAAoKBh5TUACZAgAJAAoKch1TUACZAgAPAAUK5hxVEQBKAQAAAA==.Dangerfiëld:BAAANQAECgIIAgAAAA==.Dawnwell:BAAANQADCgYICgAAAA==.',
De='Deadfisch:BAAANQADCgQIBAABNQADCggIGQANAAAAAA==.Deathknig:BAAANQADCggICAAAAA==.Demious:BAABNQAECn8UAAIMAAcK6REbkADpAQAMAAcK6REbkADpAQAAAA==.Demmu:BAAANQABCgMIAQAAAA==.Demonfister:BAAANQAECgYICAAAAA==.Demonkiller:BAAANQAECgIICAAAAA==.Desorion:BAAANQABCgIIAgAAAA==.Dethstriker:BAAANQAECgcIEwAAAA==.Dethwyrm:BAAANQABCgIIAgAAAA==.Devolu:BAAANQAECgEIAQAAAA==.Devvmonk:BAAANQADCgQIBAABNQAECgMIBgANAAAAAA==.',
Di='Didi:BAAANQADCggIAQAAAA==.Dilfzdormu:BAAANQADCgYIBgAAAA==.Dindaratwo:BAABNQAECn8yAAIQAAkKCgspLwBaAQAQAAkKCgspLwBaAQAAAA==.',
Dj='Djunglebook:BAAANQAECgUIBQAAAA==.',
Do='Dokta:BAABNQAECn8ZAAIRAAcK3gy+HAAFAQARAAcK3gy+HAAFAQAAAA==.Dontula:BAAANQAECgIIAgAAAA==.',
Dr='Drathal:BAAANQAECgQIBAAAAA==.Druaa:BAAANQADCgQIBAABNQAECgYIGwAFAOoYAA==.',
Du='Dumolin:BAAANQAECgIIAQAAAA==.Dusknoir:BAAANQAECgEIAgAAAA==.',
Ec='Eclïpse:BAAANQABCgIIAgAAAA==.',
Ed='Eddiedean:BAAANQAECggIDgAAAA==.Edric:BAAANQADCggIGgAAAA==.',
El='Electolytic:BAAANQAECgUIBQAAAA==.Elfgonewild:BAAANQAECgEIAQAAAA==.Ellessra:BAAANQADCgcIDwAAAA==.Elma:BAAANQADCggICAAAAA==.Elnegrouno:BAABNQAECn8iAAIJAAgKnxMUewAnAgAJAAgKnxMUewAnAgAAAA==.',
Er='Eragone:BAAANQAECgMIBAAAAA==.Eragora:BAAANQADCgUICQAAAA==.Errdrick:BAAANQAECgYIEwAAAA==.',
Et='Etoro:BAAANQADCgIIAgAAAA==.',
Ev='Evokaa:BAAANQADCgUIBQABNQAECgYIGwAFAOoYAA==.',
Fa='Faeyri:BAAANQAECgYIDgAAAA==.Fawntastic:BAAANQADCggIEAAAAA==.',
Fe='Feeri:BAAANQAECgEIAwAAAA==.Feyrbrand:BAABNQAECn8rAAISAAoKQhH4EgCyAQASAAoKQhH4EgCyAQAAAA==.',
Fi='Fischnchips:BAAANQADCgQIBAAAAA==.Fischticuffs:BAAANQADCggIGQAAAA==.',
Fl='Flagellation:BAAANQAECgQIBAAAAA==.',
Fo='Fourid:BAABNQAECn8eAAIJAAkK+xYlZQC7AQAJAAkK+xYlZQC7AQAAAA==.',
Fr='Frostfirer:BAAANQADCgIIAgAAAA==.',
Fu='Fuyu:BAAANQAECgEIAQAAAA==.',
Ga='Gallyn:BAABNQAECn89AAMTAAoKqRzsGgCeAgAUAAoKxRkYGQC0AgATAAkKGBrsGgCeAgAAAA==.',
Gi='Giizmo:BAAANQADCgYIBgAAAA==.',
Gl='Glacierrock:BAAANQADCgMIAwAAAA==.Gloria:BAABNQAECn82AAIFAAoKVho1IgCaAgAFAAoKVho1IgCaAgAAAA==.Glyndor:BAAANQADCgYIBgAAAA==.',
Go='Googlyboogli:BAAANQAECgMICQAAAA==.',
Gr='Grail:BAAANQAECgEIAQAAAA==.Grogar:BAAANQADCgIIAgAAAA==.',
Gu='Gunslinger:BAAANQAECgUIDQAAAA==.',
Ha='Halenicion:BAAANQAECgIIAQAAAA==.Hankthetank:BAAANQADCgYIBgAAAA==.Hazza:BAAANQADCgUIBQABNQAFFAQICAAVAFkQAA==.',
Hi='Hippoltyos:BAABNQAECn86AAIKAAoKjhSuMgBhAgAKAAoKjhSuMgBhAgAAAA==.',
Ho='Honestlee:BAAANQADCgMIAwAAAA==.Honourablee:BAAANQADCgQIBAAAAA==.',
Hu='Hunkacrap:BAAANQABCgIIAgAAAA==.Huntaa:BAAANQADCggIEgABNQAECgYIGwAFAOoYAA==.Huntardiness:BAABNQAECn8tAAMWAAkK3RTyGQCiAQAMAAkKoxP/SQAoAgAWAAkKtgzyGQCiAQAAAA==.',
Hy='Hymnals:BAACNQAFFH8LAAMPAAUKVBpqAQAsAQAPAAQKBhpqAQAsAQAJAAMKRRlDIwDkAAA1AAQKfyUAAw8ACgoPJs4EAIYCAAkACQqHJMQlACIDAA8ABwqlJM4EAIYCAAAA.',
Ic='Icealia:BAAANQAECgMIBQABNQAFFAQICwAQABMEAA==.',
In='Inazuma:BAAANQAECgEIAgAAAA==.',
Is='Isus:BAAANQAECgMIAwAAAA==.',
Iv='Ive:BAABNQAECn9KAAQVAAoKUSOFGQAhAwAVAAkKNiOFGQAhAwAXAAUKLiIeDgByAQAYAAMKGyCsLQAVAQAAAA==.',
Ja='Jadeflower:BAAANQAECgQIBQAAAA==.Jarnunvosk:BAAANQADCgMIAwAAAA==.Jasmindinn:BAAANQAECgcIBgAAAA==.Jayber:BAAANQAECgEIAQAAAA==.',
Ji='Jimbearlushi:BAACNQAFFH8NAAIZAAUKOBTaCQAuAQAZAAUKOBTaCQAuAQA1AAQKfy8AAxkACgrkHgEUABICABkACgrkHgEUABICABoABwr9FXoVAIwBAAAA.Jiujitsu:BAAANQAECgEIAgAAAA==.',
Ju='Judelly:BAAANQAECgIIAgAAAA==.Juicebox:BAAANQAECggIEwAAAA==.Justjakk:BAAANQADCgEIAgAAAA==.',
Ka='Kabball:BAAANQAECgEIAwAAAA==.Kabr:BAAANQADCgYICQAAAA==.Kalez:BAAANQADCggIEQAAAA==.Kalibar:BAABNQAECn8XAAIBAAgKoxqiLgBXAgABAAgKoxqiLgBXAgAAAA==.Kamakaz:BAABNQAECn8pAAMFAAoKzhidMgA9AgAFAAoKzhidMgA9AgALAAcKCQp9bAArAQAAAA==.Kamasdruid:BAAANQAECggICAAAAA==.Kamasmage:BAAANQAECgYIBQAAAA==.Kandi:BAAANQADCgMIAwAAAA==.Kaviryon:BAAANQAECgEIBAAAAA==.Kaywhy:BAABNQAECn8xAAIbAAoKzR6LEQDjAgAbAAoKzR6LEQDjAgAAAA==.',
Ki='Kichack:BAAANQAECgEIAgAAAA==.Kimchie:BAAANQAECgIIAgAAAA==.Kinqanduin:BAAANQADCggIFAAAAA==.',
Kj='Kjdh:BAABNQAECn9KAAIcAAoKpSGfCwBQAwAcAAoKpSGfCwBQAwAAAA==.',
Kn='Knowndeath:BAAANQAECgIIAgABNQAECgkJLgARAAgeAA==.Knuckles:BAABNQAECn8bAAIJAAgKyAweggBtAQAJAAgKyAweggBtAQAAAA==.',
Ko='Koanu:BAAANQADCggIDAAAAA==.Kob:BAABNQAECn8WAAQVAAgKVwgPvQBTAQAVAAgKAAgPvQBTAQAXAAEKTAggMAA1AAAYAAEKNgHmiAAaAAAAAA==.Kogun:BAAANQAECgIIAwAAAA==.Kozalth:BAAANQADCgcIFwAAAA==.',
Kt='Ktom:BAABNQAECn82AAILAAoK3iB0EwBWAwALAAoK3iB0EwBWAwAAAA==.',
Ku='Kurayami:BAAANQAECgQIBQAAAA==.',
La='Lancelot:BAAANQAECgIIBQAAAA==.Lawndown:BAAANQADCgIIAgAAAA==.Lawnsifer:BAAANQADCgMIAwAAAA==.',
Li='Litchlord:BAAANQADCgYIBgAAAA==.Liv:BAAANQAECgcIDAAAAA==.',
Lo='Loax:BAAANQADCgUJBQAAAA==.Loek:BAAANQADCgUIBQAAAA==.Longpong:BAAANQAECgQICgAAAA==.Louhi:BAAANQAECgQICwAAAA==.Loveshaq:BAAANQAECgUIBQAAAA==.',
Lu='Lunar:BAABNQAECn8sAAIdAAoK8xjzJgCcAgAdAAoK8xjzJgCcAgAAAA==.',
Ly='Lystat:BAAANQAECgQIBAAAAA==.',
Ma='Magra:BAABNQAECn8qAAIeAAoKYg+xCwDHAQAeAAoKYg+xCwDHAQAAAA==.Magêyalook:BAAANQADCgMIAwABNQAECgkJIgATAA8NAA==.Malogg:BAAANQABCggIFAAAAA==.Manzz:BAAANQAECgEIAQAAAA==.Mariahscary:BAABNQAECn83AAIVAAoKhw3LXgCkAQAVAAoKhw3LXgCkAQAAAA==.Marisol:BAAANQAECgEIAwAAAA==.Maskimxul:BAAANQABCgEIAQAAAA==.Mattob:BAAANQADCggIFgAAAA==.Maznificent:BAAANQADCgYIHQAAAA==.',
Me='Meandmypal:BAACNQAFFH8QAAIfAAcK9RtDAABAAgAfAAcK9RtDAABAAgA1AAQKfz8AAh8ACgqeJVcAAHIDAB8ACgqeJVcAAHIDAAAA.Meatspinz:BAAANQADCggIDQAAAA==.Meesodead:BAABNQAECn8pAAMDAAoKIw/UOwCYAQADAAoKrQ3UOwCYAQAOAAUKUQyTWADPAAAAAA==.Mello:BAABNQAECn8vAAIJAAoKWRjwNQBZAgAJAAoKWRjwNQBZAgAAAA==.Mesteris:BAAANQADCggICAAAAA==.Metalhead:BAAANQADCgYIBgAAAA==.',
Mi='Midiane:BAAANQAECgIIAgAAAA==.Mirba:BAAANQAECgYIDwAAAA==.',
Mk='Mknight:BAAANQAECgQIEgAAAA==.',
Mo='Moments:BAAANQADCggICAAAAA==.Monsterdeath:BAAANQAECgIJAgAAAA==.',
['Må']='Måladroit:BAAANQADCgIIAgAAAA==.',
Na='Nareík:BAABNQAECn83AAMgAAoKgxLiHgCXAQAcAAgKYhBMOwDcAQAgAAoKRxDiHgCXAQAAAA==.Nazarath:BAAANQABCgIIAgAAAA==.',
Ne='Neeru:BAAANQABCgIIAgABNQAECgMIBQANAAAAAA==.Neriak:BAABNQAECn8+AAIdAAkKlBViKACmAQAdAAkKlBViKACmAQAAAA==.Newa:BAAANQAECgEIAQAAAA==.',
Ni='Nightwater:BAACNQAFFH8LAAIQAAQKEwQMDADSAAAQAAQKEwQMDADSAAA1AAQKfygAAxAACgqqEwYhACECABAACgqqEwYhACECAB0AAQoQBaW1AC0AAAAA.',
No='Nonoka:BAAANQAECgEIAQAAAA==.',
Ob='Obouuld:BAAANQADCgQIBAAAAA==.',
Or='Orchop:BAAANQADCgUIBgAAAA==.Orenrim:BAAANQADCgMIAwABNQAECgQIBAANAAAAAA==.',
Os='Osanyin:BAAANQAECgEIAgABNQAECgUIBwANAAAAAA==.',
Pa='Paado:BAAANQADCgEIAQAAAA==.Paulterian:BAAANQAECgYIEQAAAA==.',
Pe='Pentagonjr:BAAANQADCgUIBQAAAA==.',
Pf='Pffthmgcdrgn:BAAANQADCgQICAAAAA==.',
Ph='Phinehas:BAAANQADCggJCAAAAA==.',
Po='Poldalina:BAAANQADCggIIwAAAA==.',
Pr='Pr:BAAANQADCgYIBgAAAA==.Priesaa:BAAANQAECgQIEAABNQAECgYIGwAFAOoYAA==.Proverbs:BAAANQAECgEIAQAAAA==.',
Pu='Pumplord:BAAANQADCgIIAgAAAA==.',
Qe='Qeynos:BAABNQAECn8bAAMCAAcK4g7/dABEAQACAAcK4g7/dABEAQAOAAEKAAC52wAiAAAAAA==.',
Ql='Qlona:BAAANQAECggIEwAAAA==.',
Qu='Quazeemoto:BAAANQAECgQIBAAAAA==.',
Ra='Raalen:BAAANQABCgYICwAAAA==.Rainknuckles:BAABNQAECn8/AAIBAAoK3x0AFgD3AgABAAoK3x0AFgD3AgAAAA==.Ratrenot:BAAANQADCggIDAAAAA==.Ravael:BAAANQADCgUIBwAAAA==.Rayshano:BAAANQADCggICAABNQAECgcICwANAAAAAA==.',
Re='Redfisch:BAAANQADCgUIBQABNQADCggIGQANAAAAAA==.Reliablé:BAAANQAECgUICQABNQAECgYICQANAAAAAA==.Resia:BAAANQADCggIEAAAAA==.Retailsucks:BAAANQADCgcIFQAAAA==.Revocsid:BAAANQADCggIHAAAAA==.Rezza:BAAANQADCgUIBgAAAA==.',
Ri='Ridethewave:BAAANQADCgIIAgAAAA==.Rikka:BAAANQADCgQIBAAAAA==.',
Ro='Rottingtree:BAABNQAECn8dAAMeAAcKEw2vFgBIAQAeAAcKEw2vFgBIAQAEAAEK5AKT0AEuAAAAAA==.',
Ru='Rustynails:BAABNQAECn8uAAIhAAoKkRbjBACxAgAhAAoKkRbjBACxAgAAAA==.',
Ry='Ryvalz:BAAANQAECgYIDgAAAA==.',
Sa='Sacrafischal:BAAANQADCgcICwAAAA==.Saibur:BAAANQAECgYIDwAAAA==.Sazzul:BAABNQAECn8ZAAIiAAgKxhQMEQDvAQAiAAgKxhQMEQDvAQAAAA==.',
Sc='Scynx:BAAANQAECgEIAgAAAA==.',
Se='Seaka:BAABNQAECn9BAAMQAAoKvhn1GAB1AgAQAAoKvhn1GAB1AgAdAAMKFhF/kQCRAAAAAA==.Sernix:BAAANQAECgQIEAAAAA==.',
Sh='Shadegrim:BAAANQAECgEIAQAAAA==.Shamanic:BAAANQAECggIEgAAAA==.Shamany:BAABNQAECn8bAAQFAAYK6hi8YAB+AQAFAAYK6hi8YAB+AQAiAAUKCgwdIwApAQALAAEKAABgIAEAAAAAAA==.Shamnick:BAAANQAECgYIBgAAAA==.Shariya:BAAANQAECgYIEAAAAA==.Shiftyfans:BAAANQAECgcIBwAAAA==.Shivon:BAAANQAECgQIBAAAAA==.',
Sl='Slamin:BAAANQADCgYIBwAAAA==.',
Sn='Snowaxe:BAAANQADCgIIAgAAAA==.Snowwind:BAAANQAECgUIEAAAAA==.',
So='Solthea:BAAANQABCgQIBgAAAA==.Sonar:BAABNQAECn9TAAIMAAoKnyARGgDQAgAMAAoKnyARGgDQAgAAAA==.Sonasham:BAAANQADCggIIwAAAA==.Sonnybear:BAAANQADCggIIwAAAA==.Soulhatcher:BAAANQAECggIEgAAAA==.Soulslinger:BAAANQABCgQIBQAAAA==.Soxs:BAAANQAECgYICQAAAA==.',
Sp='Spawnofdeath:BAAANQAECgIIAwAAAA==.Spectrelok:BAAANQAECgMIBAAAAA==.Spectrepunch:BAABNQAECn8VAAIZAAYKRQfrRgDnAAAZAAYKRQfrRgDnAAAAAA==.',
St='Steàlthy:BAABNQAECn8iAAITAAkKDw1HXAB7AQATAAkKDw1HXAB7AQAAAA==.Stickychikn:BAAANQADCgYIBgAAAA==.Stompygnome:BAABNQAECn8YAAMRAAgKgA91IABKAQARAAQKWB11IABKAQAJAAgKNQU2ugDtAAAAAA==.',
Sy='Syrila:BAABNQAECn8rAAIBAAkKCxRdQQD7AQABAAkKCxRdQQD7AQAAAA==.',
Ta='Tartanus:BAAANQADCgQIBAAAAA==.Tayzetv:BAAANQADCgcIBwABNQAECgQIBQANAAAAAA==.',
Te='Teramiah:BAAANQADCgMIAwAAAA==.',
Th='Thorall:BAAANQADCgQIAwAAAA==.Thylight:BAAANQADCgIIAgAAAA==.',
Ti='Tippy:BAACNQAFFH8QAAIDAAcK1hvwAwDlAQADAAcK1hvwAwDlAQA1AAQKf0IAAgMACgpzJU0HACoDAAMACgpzJU0HACoDAAAA.',
To='Tombstone:BAABNQAECn84AAMUAAoKjhllGgCqAgAUAAoKzxdlGgCqAgATAAYKaRcdYABtAQAAAA==.Toowongfoo:BAACNQAFFH8UAAIZAAcKzguiBgAUAQAZAAcKzguiBgAUAQA1AAQKf0EAAxkACgoeIaYHAOcCABkACgoeIaYHAOcCABoACApLGWgGAAcCAAAA.',
Ty='Tygrana:BAAANQADCgYIBgAAAA==.',
Ug='Uglysham:BAABNQAECn8xAAIFAAkK9x66EwAIAwAFAAkK9x66EwAIAwAAAA==.',
Um='Umbranecros:BAAANQADCgQIBQAAAA==.',
Un='Underdog:BAABNQAECn8cAAMWAAgKUxMzHgBuAQAWAAgKUxMzHgBuAQAMAAEKVw7oNwFCAAAAAA==.Unpredictabl:BAAANQAECgUIBgAAAA==.',
Us='Usui:BAAANQAECgEIAgAAAA==.',
Va='Vaerie:BAAANQADCgYIBgAAAA==.Vagindivin:BAABNQAECn8gAAMjAAoK4RgfCQDCAQAjAAoK4RgfCQDCAQAcAAEKggbqmwAnAAAAAA==.Valyteil:BAAANQAECgUICwAAAA==.',
Ve='Venngance:BAAANQAECgYIDwAAAA==.Vercingetorx:BAAANQADCgIIAgAAAA==.',
Vi='Virus:BAABNQAECn8iAAMVAAgKKBAzYAChAQAVAAgKKBAzYAChAQAYAAIKuQMYbQBFAAAAAA==.',
Vo='Void:BAAANQAECggIEQAAAA==.Voidkity:BAABNQAECn8WAAMbAAcKXhFSMQDrAAAbAAYKCA5SMQDrAAAKAAUKYgVRuACqAAAAAA==.',
Wa='Wakax:BAABNQAECn8iAAIPAAkKyRcjCQD1AQAPAAkKyRcjCQD1AQAAAA==.Walberson:BAAANQADCgcIBwAAAA==.Walkleydk:BAAANQAECggICQAAAA==.Warfield:BAAANQAECgUIEQAAAA==.Warmoose:BAAANQADCggICAABNQAECgoKIAAjAOEYAA==.',
We='Weediez:BAAANQADCgYJCAAAAA==.',
Wi='Wildfrost:BAABNQAECn8gAAIEAAUKQAL/DQGNAAAEAAUKQAL/DQGNAAAAAA==.Willienelson:BAAANQAECggIDgAAAA==.',
Wr='Wrathsome:BAAANQAECgYIDwAAAA==.',
Wy='Wyrmboy:BAAANQABCgQIBQAAAA==.Wyterd:BAABNQAECn8jAAIMAAgKVxLXhQCRAQAMAAgKVxLXhQCRAQAAAA==.',
Xa='Xaernach:BAAANQADCgQIBgAAAA==.Xalome:BAAANQADCgUIEwAAAA==.',
Xo='Xoxo:BAAANQAFFAEIAQABNQAFFAQIBAANAAAAAA==.',
Ya='Yanza:BAAANQADCgQIBAAAAA==.',
Yo='Yoing:BAAANQADCggICAABNQADCggICAANAAAAAA==.',
Za='Zarkus:BAAANQAECgUIDgAAAA==.Zaruknark:BAABNQAECn8bAAIMAAkKFgnacwC7AQAMAAkKFgnacwC7AQAAAA==.',
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
