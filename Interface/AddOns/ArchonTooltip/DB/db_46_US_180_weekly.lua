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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Paladin-Protection','Hunter-Marksmanship','Paladin-Holy','Mage-Frost','Warrior-Protection','Evoker-Augmentation','Monk-Brewmaster','Priest-Discipline','Priest-Shadow','Monk-Mistweaver','Hunter-Survival','DeathKnight-Unholy','Evoker-Devastation','Evoker-Preservation','Warrior-Arms','Druid-Feral','Monk-Windwalker','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Restoration','Shaman-Enhancement','Druid-Restoration','Mage-Arcane','Rogue-Subtlety','DemonHunter-Vengeance','DeathKnight-Blood','Mage-Fire','DeathKnight-Frost','Druid-Guardian',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=46,date='2026-05-16',data={Ai='Aisling:BAAALgADCgYJBgAAAA==.',
Al='Alanispally:BAAALgADCgIJAQAAAA==.Algryn:BAAALgADCgUJBQAAAA==.Alkanz:BAAALgAECgkJDgAAAA==.Allinaa:BAABLgAECn8cAAIBAAkJwA6vMwC9AQABAAkJwA6vMwC9AQAAAA==.',
Am='Amorvea:BAAALgADCgUJBQABLgAECgIJAgACAAAAAA==.',
An='Angron:BAAALgADCgIJBQAAAA==.Anika:BAABLgAECn8uAAIDAAkJ6wyaHwClAQADAAkJ6wyaHwClAQAAAA==.',
Ar='Arcade:BAAALgAECgEJAgAAAA==.Arlyx:BAACLgAFFH8LAAMEAAQJwxAFUADfAAAEAAMJyRAFUADfAAAFAAIJpw8/FgBSAAAuAAQKfyYABAQACAkqHtUjABUCAAQABwlaGtUjABUCAAUAAwnzFohHAJgAAAYAAgnoBzQfAHcAAAAA.Arnwaz:BAAALgAECgUJCwAAAA==.Arthuria:BAAALgAECggJDAAAAA==.',
As='Aslan:BAAALgADCgQJBwAAAA==.',
At='Atelwen:BAAALgAECgcJBwAAAA==.',
Av='Avelyn:BAAALgAECgcJCgAAAA==.',
Ba='Babyruthie:BAAALgAECgMJBAAAAA==.Baf:BAACLgAFFH8IAAIHAAQJaxdFIABGAQAHAAQJaxdFIABGAQAuAAQKfxoAAgcABwl3HYY+ACsCAAcABwl3HYY+ACsCAAAA.Bayside:BAAALgAECgYJEQAAAA==.',
Be='Bearfomat:BAAALgAFFAIJAgAAAA==.Beefis:BAAALgAECgUJCwAAAA==.Beenjuicin:BAAALgAFFAEJAgABLgAFFAIJAgACAAAAAA==.Berfomat:BAABLgAECn8nAAIIAAkJ1CHiAQDgAgAIAAkJ1CHiAQDgAgAAAA==.',
Bi='Bingchilling:BAACLgAFFH8SAAIJAAUJyRLpCgBrAQAJAAUJyRLpCgBrAQAuAAQKfzAAAgkACQnqHAgMAOoCAAkACQnqHAgMAOoCAAAA.',
Bj='Bjorn:BAAALgAFFAEJAQAAAA==.',
Bl='Bloomyvfd:BAABLgAECn8YAAIKAAYJVB6mGgDlAQAKAAYJVB6mGgDlAQAAAA==.',
Bo='Bombuur:BAAALgAECgQJBAAAAA==.Bonniebadass:BAAALgAECgYJEwAAAA==.Bottle:BAAALgAECgcJDAAAAA==.Boxxylove:BAAALgAECgQJBAAAAA==.',
Br='Bravas:BAAALgAECgcJBQAAAA==.Brimscythe:BAAALgADCgQJBAAAAA==.Broxar:BAAALgADCgcJCwAAAA==.',
['Bî']='Bîa:BAABLgAECn8bAAIHAAcJgiJ3HwBIAgAHAAcJgiJ3HwBIAgAAAA==.',
Ca='Cablemstache:BAAALgADCgcJBwAAAA==.Calisti:BAABLgAECn8qAAILAAcJtxrVZgAJAgALAAcJtxrVZgAJAgAAAA==.Cavalis:BAABLgAECn8uAAQEAAkJfRt6LADqAQAEAAgJvhd6LADqAQAGAAUJshexEgABAQAFAAQJNxq8EQDfAAAAAA==.',
Ce='Ceedh:BAAALgAFFAMJBAAAAA==.Ceejr:BAACLgAFFH8ZAAMDAAgJhiKlAQDoAQADAAUJ5iKlAQDoAQAMAAUJuiANAwDFAQAuAAQKfyYAAwMACQlpJSQBAMQDAAMACQlpJSQBAMQDAAwABgldH9MNAL4BAAAA.Cerovallen:BAAALgAECgYJCQAAAA==.',
Ch='Chailee:BAAALgADCgEJAQAAAA==.Cherish:BAAALgADCgMJAwABLgAECgUJCgACAAAAAA==.Chillum:BAAALgAECgIJAgABLgAFFAQJCQANAOIPAA==.Chimneybeans:BAAALgADCgcJBwAAAA==.',
Co='Corny:BAAALgAECgUJCwAAAA==.',
Cr='Creativez:BAABLgAFFH8HAAIOAAIJNRmzGACoAAAOAAIJNRmzGACoAAAAAA==.Creativezd:BAAALgAFFAIJAgABLgAFFAIJBwAOADUZAA==.',
Da='Damnskippy:BAAALgAECgQJBwAAAA==.Dannÿ:BAABLgAECn8cAAMPAAcJnhWlHwB1AQAPAAYJ+halHwB1AQAQAAEJTAovbQAiAAAAAA==.Dantè:BAAALgAECgIJAgAAAA==.Daris:BAAALgADCgMJAwAAAA==.Darkire:BAACLgAFFH8GAAIBAAMJpAvzOADkAAABAAMJpAvzOADkAAAuAAQKfyIAAgEACAmKGoM4AMwBAAEACAmKGoM4AMwBAAAA.Darkstar:BAAALgADCgUJBQAAAA==.Darkwarriorx:BAAALgADCgQJAgAAAA==.',
De='Deathlegion:BAAALgAECgQJBAAAAA==.Deathroll:BAABLgAECn8oAAIRAAkJNRl2CwCBAgARAAkJNRl2CwCBAgAAAA==.Delarus:BAAALgAECgEJAQAAAA==.Demonarmor:BAAALgAECgMJCAABLgAECgcJCAACAAAAAA==.',
Di='Diddley:BAAALgADCgMJAwAAAA==.',
Do='Dogmatik:BAAALgAECgEJAQABLgAECgMJAwACAAAAAA==.Dontah:BAAALgADCgcJBwABLgAECgkJJgASAKkhAA==.Doomward:BAABLgAECn8cAAITAAcJMBMgXwBlAQATAAcJMBMgXwBlAQAAAA==.Dorien:BAABLgAECn8mAAMSAAkJqSGRAgDvAgASAAkJqSGRAgDvAgABAAEJ5BMwzABDAAAAAA==.',
Dr='Drachilly:BAACLgAFFH8JAAINAAQJ4g8IHAAjAQANAAQJ4g8IHAAjAQAuAAQKfyAABA0ACAkoHv4VACkCAA0ACAmSHf4VACkCABQABgknHj0QANgBABUAAQkPArA2ABsAAAAA.Dragnar:BAABLgAECn8jAAIBAAkJlwzuPQC3AQABAAkJlwzuPQC3AQAAAA==.Drakbonespur:BAAALgAECgcJBwAAAA==.Drhealzgood:BAAALgADCgYJBgAAAA==.Droggo:BAAALgADCgIJAgAAAA==.',
Ev='Evilvdduck:BAAALgAECgEJAQAAAA==.',
Ey='Eysia:BAAALgADCgUJBQAAAA==.',
Fa='Faewryn:BAAALgAECgkJCgAAAA==.Faeya:BAAALgADCgEJAQABLgADCgUJCAACAAAAAA==.Falekia:BAAALgAECgEJAQAAAA==.Fay:BAACLgAFFH8KAAIOAAQJIRbUFgAkAQAOAAQJIRbUFgAkAQAuAAQKfx0AAg4ACAnJIewSAHoCAA4ACAnJIewSAHoCAAAA.',
Fe='Felltown:BAAALgADCgMJAwAAAA==.',
Fi='Firstblood:BAAALgAECgYJCQAAAA==.Fishnchimps:BAABLgAFFH8FAAIRAAMJDRQ6HADcAAARAAMJDRQ6HADcAAAAAA==.',
Fu='Furrburger:BAAALgADCgIJAgAAAA==.',
Ga='Gaiserik:BAABLgAECn8mAAIWAAgJKiEdBACTAgAWAAgJKiEdBACTAgAAAA==.Galenda:BAAALgADCgQJBQAAAA==.Gandolph:BAAALgADCgEJAQAAAA==.Garduhm:BAAALgADCgYJCQABLgAECgIJAgACAAAAAA==.Garlictoast:BAAALgAECgQJBwAAAA==.',
Ge='Gearsofhate:BAAALgAECgEJAgAAAA==.Gehenna:BAAALgADCgYJCgAAAA==.',
Go='Goldenorder:BAAALgAECgcJCAAAAA==.Gome:BAAALgADCgcJGwABLgAFFAMJBQARAA0UAA==.',
Gr='Gracile:BAAALgADCgEJAQAAAA==.Gragolf:BAABLgAECn8dAAIBAAkJPhOvLADbAQABAAkJPhOvLADbAQAAAA==.Greggor:BAAALgAECgYJDQAAAA==.Gronkus:BAAALgAECgYJBwAAAA==.',
Gu='Gustabo:BAABLgAECn8bAAIXAAYJGyKoCADiAQAXAAYJGyKoCADiAQAAAA==.',
Ha='Haslin:BAAALgADCgEJAQAAAA==.Havibonespur:BAABLgAECn8XAAMOAAYJXQtVOgDYAAAOAAYJXQtVOgDYAAAYAAEJyQSXhQAgAAABLgAECgcJBwACAAAAAA==.',
He='Healir:BAABLgAECn8TAAMPAAgJZyJEEQAIAgAPAAgJZyJEEQAIAgAQAAQJnh/ULAB3AQAAAA==.Healmepls:BAAALgADCgYJCgABLgAFFAUJDAAZAHcPAA==.Hellsong:BAAALgAECgEJAQAAAA==.Helor:BAABLgAECn8XAAMaAAkJcRZlLgDGAQAaAAkJcRZlLgDGAQAbAAUJ3RXDLgBXAQAAAA==.',
Ho='Holydeath:BAAALgAECgYJEQAAAA==.Hotpocketz:BAAALgADCgcJCQABLgAECggJFwADACoXAA==.',
Hu='Hunterish:BAAALgADCgEJAQAAAA==.',
Ia='Iadrithe:BAAALgADCgYJBgAAAA==.',
In='Inspectadeck:BAAALgAECgMJBAAAAA==.Invisus:BAAALgAFFAEJAQAAAA==.',
Is='Ispayderj:BAAALgAECgMJBAAAAA==.',
Ja='Jahy:BAAALgADCgIJAgAAAA==.Jake:BAABLgAECn8iAAIHAAkJziVfBQB3AwAHAAkJziVfBQB3AwAAAA==.Jarlan:BAACLgAFFH8PAAIWAAQJjB9EBgBtAQAWAAQJjB9EBgBtAQAuAAQKfygAAhYACAmRI7sBACMDABYACAmRI7sBACMDAAAA.Jarlhun:BAABLgAECn8YAAIJAAcJAhryCQBJAQAJAAcJAhryCQBJAQABLgAFFAQJDwAWAIwfAA==.',
Je='Jellous:BAACLgAFFH8GAAMaAAIJpQbJYQByAAAaAAIJBgXJYQByAAAbAAEJZwv7DQBOAAAuAAQKfyoAAxsACQmCF5MTADgCABsACAl5GJMTADgCABoACQlkFN4zACoCAAAA.Jethereal:BAAALgADCgcJBwABLgAFFAIJBgAaAKUGAA==.',
Ju='Jurista:BAAALgADCgYJBgAAAA==.Justin:BAAALgAECgYJBgAAAA==.',
Ke='Ketharion:BAABLgAECn8rAAMKAAkJ5RWoEgAzAgAKAAkJ5RWoEgAzAgAHAAEJigs9OgEyAAAAAA==.Kevamin:BAAALgAECgYJEwAAAA==.',
Kh='Khaela:BAAALgAECgIJAgAAAA==.Khato:BAAALgAECggJDAAAAA==.',
Ki='Killya:BAAALgADCgEJAQAAAA==.Kirasha:BAAALgADCgcJBwAAAA==.',
Ku='Kulfa:BAAALgADCgcJCgAAAA==.Kurailos:BAAALgADCggJCAAAAA==.Kurisu:BAAALgAECgQJCAAAAA==.',
La='Lailyne:BAAALgAECgkJEAAAAA==.Lake:BAAALgAECgUJBQAAAA==.',
Le='Learned:BAAALgAECggJEwAAAA==.Leo:BAABLgAECn8ZAAIMAAgJRByfCAApAgAMAAgJRByfCAApAgAAAA==.Leone:BAAALgAECgYJBwAAAA==.',
Li='Lilany:BAACLgAFFH8FAAIcAAMJuAwBRQBwAAAcAAMJuAwBRQBwAAAuAAQKfxUAAhwACQlPFhQqALwBABwACQlPFhQqALwBAAAA.Lillymeii:BAAALgAECgEJAQAAAA==.Linova:BAAALgADCgUJBQAAAA==.Lithrak:BAABLgAECn8wAAIdAAkJ0B8nAwCRAgAdAAkJ0B8nAwCRAgAAAA==.',
Lo='Logical:BAAALgAECgEJAQAAAA==.Lorakine:BAAALgADCgUJBQAAAA==.',
Lu='Luciferr:BAAALgADCgEJAQAAAA==.Lucit:BAAALgADCgEJAQABLgAFFAQJCwAEAMMQAA==.Lute:BAAALgAECgQJCAAAAA==.',
Ly='Lyric:BAAALgADCgcJDAABLgAFFAQJCgAOACEWAA==.',
['Lá']='Lárien:BAABLgAECn8XAAIeAAcJsxRuNACDAQAeAAcJsxRuNACDAQAAAA==.',
Ma='Mable:BAAALgADCggJCAAAAA==.Magicmicah:BAAALgADCgcJBwAAAA==.Manon:BAACLgAFFH8KAAIcAAQJ/Ra2FgBAAQAcAAQJ/Ra2FgBAAQAuAAQKfxsAAxwACAk6FxEtANYBABwABwkmGREtANYBABkAAQm+B56CACYAAAAA.',
Mc='Mcchungus:BAAALgAFFAEJAQAAAA==.',
Me='Meliodas:BAAALgAECgQJBgAAAA==.Menghao:BAABLgAECn8WAAMLAAcJ3wX5mAAPAQALAAcJ3wX5mAAPAQAfAAIJ3AFqGgBEAAAAAA==.Meowmixx:BAAALgAECgcJAwAAAA==.',
Mi='Mikayybrew:BAAALgADCgUJBQAAAA==.Mischief:BAACLgAFFH8IAAIGAAQJZwbHAgARAQAGAAQJZwbHAgARAQAuAAQKfzUAAgYACQlNHQsCAGkCAAYACQlNHQsCAGkCAAAA.',
Mk='Mk:BAEALgAECgQJCQABLgAECggJNwAYAGsjAA==.',
Mo='Moneyfupa:BAAALgAECgUJBQAAAA==.Mooage:BAACLgAFFH8GAAILAAIJYiDBMwDLAAALAAIJYiDBMwDLAAAuAAQKfzMAAgsACQmcJN4HABYDAAsACQmcJN4HABYDAAAA.Morewyn:BAABLgAECn8eAAIBAAgJVRHEMwDgAQABAAgJVRHEMwDgAQAAAA==.Mozoh:BAAALgADCgMJAwABLgAECgIJAgACAAAAAA==.',
Ne='Nerrgall:BAAALgADCgcJBwAAAA==.',
Ni='Nickignomaj:BAABLgAECn8ZAAQYAAgJJw3pIgBGAQAYAAgJJw3pIgBGAQARAAQJLBElRwC+AAAOAAUJswbiSQCeAAABLgAFFAIJBQAWANcQAA==.Nidhogg:BAAALgADCgcJBwABLgAECgkJIQAcANcaAA==.Nisara:BAAALgAECgYJCgAAAA==.',
No='Noellie:BAAALgAFFAEJAgAAAA==.Noobdestroya:BAAALgAECgQJDwAAAA==.Nosfuratu:BAAALgADCgkJCQAAAA==.',
Ny='Nymi:BAAALgADCgYJBgAAAA==.',
Of='Offline:BAAALgADCgcJCwAAAA==.',
Ol='Oldbutcool:BAAALgADCgEJAgAAAA==.',
Om='Omantul:BAABLgAECn8hAAMcAAkJ1xqGIgAQAgAcAAgJDRqGIgAQAgAZAAYJUBk/OQD6AAAAAA==.',
Or='Orangez:BAAALgAECgMJBAAAAA==.',
Ou='Ouija:BAAALgAECgEJAQAAAA==.',
Ow='Owocoxl:BAAALgADCgYJCwABLgAFFAUJEAAgAMYQAA==.',
Pa='Painfull:BAABLgAECn8jAAIaAAgJpB2uIgACAgAaAAgJpB2uIgACAgAAAA==.Pants:BAAALgAECgEJAQAAAA==.Paz:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.',
Ph='Phakes:BAAALgAECgUJCAAAAA==.Phengzera:BAAALgAECgcJEQAAAA==.Phizz:BAABLgAFFH8FAAIaAAQJZA6HMAAVAQAaAAQJZA6HMAAVAQAAAA==.',
Po='Po:BAAALgADCgcJDQABLgAFFAUJDQAaACARAA==.Pontius:BAAALgADCgMJAwABLgAECgkJDgACAAAAAA==.',
Pr='Prowlborn:BAAALgADCgEJAQAAAA==.',
Pu='Puke:BAABLgAECn8dAAIhAAkJlyEiAQDwAgAhAAkJlyEiAQDwAgAAAA==.Pumpkinspice:BAAALgADCgUJBgAAAA==.Purplepower:BAAALgAECgMJBAAAAA==.',
Ra='Rarim:BAAALgAECgkJDgAAAA==.',
Re='Reaperfive:BAAALgADCgcJBwAAAA==.Redbonespur:BAAALgADCgcJBwABLgAECgcJBwACAAAAAA==.',
Ri='Rimtardo:BAAALgAECgQJBwAAAA==.Rio:BAAALgAECgMJAwABLgAECggJIwAEACsUAA==.',
Ro='Rotdaddy:BAABLgAECn8aAAIgAAgJ4BEUIAA3AQAgAAgJ4BEUIAA3AQAAAA==.Roxxev:BAAALgADCgcJBwAAAA==.',
Ry='Ryø:BAAALgAECgkJDgAAAA==.',
Sa='Saintrandy:BAAALgADCgMJAwAAAA==.',
Sc='Scorch:BAAALgADCgcJCgAAAA==.',
Se='Seraphym:BAAALgADCgYJCAAAAA==.',
Sh='Shaviji:BAAALgAECgcJBwAAAA==.Shinra:BAAALgADCgEJAQAAAA==.Shore:BAABLgAECn8XAAMSAAkJ/hf5EgDNAQASAAkJ1xf5EgDNAQAJAAUJLBPxFgCiAAAAAA==.Shrekw:BAAALgAECgYJDwAAAA==.Shuralya:BAACLgAFFH8PAAMHAAQJDxQ8IgBBAQAHAAQJDxQ8IgBBAQAKAAMJURJUIADQAAAuAAQKfz4AAwcACQleHjQKAOMCAAcACQleHjQKAOMCAAoACQk9GH0gABcCAAAA.',
Si='Silverhorn:BAAALgADCgQJBAAAAA==.Siouxsie:BAAALgADCgcJCgAAAA==.',
Sm='Smoldnrg:BAAALgAECgUJBQAAAA==.',
So='Sofka:BAABLgAECn8fAAMiAAkJBw5uGgB+AQAiAAkJBw5uGgB+AQATAAEJMgHwOwEbAAAAAA==.Sourpatch:BAAALgAECgIJAgAAAA==.',
St='Stilts:BAAALgAECgcJEwAAAA==.Stradynia:BAAALgAECggJDQAAAA==.Stuart:BAAALgADCgMJAwABLgAECgIJAgACAAAAAA==.Stócky:BAAALgAECgcJEgAAAA==.',
Su='Sui:BAAALgADCgUJCAAAAA==.Survas:BAACLgAFFH8GAAIgAAMJfg60GgDmAAAgAAMJfg60GgDmAAAuAAQKfx0AAiAACAmqGfocABcCACAACAmqGfocABcCAAAA.',
Sw='Swobu:BAAALgAECgEJAQAAAA==.',
Sy='Sylwynn:BAAALgADCgUJCAAAAA==.',
['Sá']='Sárkány:BAAALgADCgcJCQAAAA==.',
Ta='Talanaz:BAAALgAECgYJDAAAAA==.Taleah:BAAALgAECgEJAgAAAA==.Taleb:BAAALgAECgYJEAABLgAECgcJDQACAAAAAA==.Tardor:BAAALgADCgMJAwAAAA==.Tavgoesboom:BAAALgAFFAIJAgABLgAFFAMJBQARAA0UAA==.Tawna:BAAALgAECgQJBQAAAA==.',
Te='Tealan:BAABLgAECn8VAAQNAAgJuRZGKAB7AQANAAcJSxVGKAB7AQAVAAYJmhTVJwA1AQAUAAEJOQjJQAAvAAAAAA==.Tenyi:BAAALgAECgMJAwAAAA==.Terrin:BAAALgAECgQJBQABLgAECgcJDQACAAAAAA==.',
To='Toospooky:BAAALgAECgYJDgAAAA==.Tovlacar:BAAALgAECgUJBgABLgAECgkJMAAPAOwPAA==.Toyboy:BAAALgAECgMJAwAAAA==.',
Tr='Triage:BAABLgAECn8UAAQfAAcJbx9sBAAFAgAfAAUJCSRsBAAFAgALAAQJihie7gAcAQAjAAEJTRYeDAA+AAAAAA==.Trolladin:BAAALgAECgEJAQAAAA==.Tronarn:BAAALgAECgcJDQAAAA==.',
Ty='Tyrias:BAAALgAECggJAwAAAA==.',
Ug='Ugin:BAABLgAECn8qAAMkAAkJPhcMBQD4AQAkAAkJFxYMBQD4AQATAAgJ6RCRXwBjAQAAAA==.',
Um='Umaydie:BAAALgAECgIJAwAAAA==.Umbrasyl:BAAALgAECgUJBgAAAA==.',
Un='Unclecharlie:BAAALgAECgUJCQABLgAFFAQJBQAkAOwYAA==.Unholylukers:BAAALgAECgIJAwAAAA==.Unit:BAAALgADCgcJCwAAAA==.',
Va='Valkrit:BAAALgADCgIJAgAAAA==.Vasrin:BAABLgAECn8uAAIdAAkJ5iF8AQDtAgAdAAkJ5iF8AQDtAgAAAA==.',
Ve='Velaria:BAAALgADCgYJEAABLgAECgYJDAACAAAAAA==.Veon:BAAALgADCgYJBgAAAA==.Verlehn:BAAALgADCgcJBgAAAA==.',
Vo='Voidomo:BAAALgAECgkJEgAAAA==.',
Wa='Walden:BAABLgAECn8WAAIlAAcJsxXMFQAuAQAlAAcJsxXMFQAuAQAAAA==.Waterlance:BAAALgAECgEJAwAAAA==.',
Wi='Wisecraic:BAAALgADCgcJDQAAAA==.Wispi:BAAALgAECgQJBAAAAA==.',
Wo='Wocoxl:BAACLgAFFH8QAAIgAAUJxhAoDQBVAQAgAAUJxhAoDQBVAQAuAAQKfycAAiAACQlIHbUGACQDACAACQlIHbUGACQDAAAA.',
Xe='Xerah:BAAALgADCggJDgAAAA==.',
Ya='Yaracklea:BAAALgAECggJDwAAAA==.',
Yi='Yingu:BAAALgADCgEJAQAAAA==.',
['Yü']='Yüki:BAAALgAECgEJAQAAAA==.',
Za='Zabaniya:BAAALgADCgEJAQAAAA==.Zac:BAAALgADCgYJDAAAAA==.Zacceptable:BAABLgAECn8VAAIfAAcJUhSCCQBRAQAfAAcJUhSCCQBRAQAAAA==.Zaida:BAAALgADCgUJBQABLgAECgIJAgACAAAAAA==.',
Ze='Zeale:BAABLgAECn8jAAIEAAgJKxRjPgClAQAEAAgJKxRjPgClAQAAAA==.Zenedict:BAAALgAFFAEJAQAAAA==.',
Zh='Zharsha:BAAALgADCgkJCQAAAA==.',
['Áç']='Áçe:BAAALgADCgMJAwAAAA==.',
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
