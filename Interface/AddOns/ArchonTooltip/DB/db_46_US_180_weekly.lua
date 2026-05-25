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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Unknown-Unknown','Warrior-Fury','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Druid-Guardian','Paladin-Protection','Hunter-Marksmanship','Paladin-Holy','Mage-Frost','Warrior-Protection','Evoker-Augmentation','Monk-Brewmaster','Priest-Discipline','Priest-Shadow','Monk-Mistweaver','Hunter-Survival','DeathKnight-Unholy','Evoker-Devastation','Evoker-Preservation','Warrior-Arms','Druid-Feral','Monk-Windwalker','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Holy','Shaman-Restoration','Shaman-Enhancement','Druid-Restoration','Mage-Arcane','Rogue-Subtlety','DemonHunter-Vengeance','DeathKnight-Blood','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=46,date='2026-05-23',data={Ai='Aisling:BAAALgADCgYJBgAAAA==.',
Al='Alanispally:BAAALgADCgIJAQAAAA==.Algryn:BAAALgADCgUJBQAAAA==.Alkanz:BAABLgAECn8UAAIBAAkJKQwxYACpAQABAAkJKQwxYACpAQAAAA==.Allinaa:BAABLgAECn8cAAICAAkJwQ7nPwC3AQACAAkJwQ7nPwC3AQAAAA==.',
Am='Amorvea:BAAALgADCgUJBQABLgAECgIJAgADAAAAAA==.',
An='Angron:BAAALgADCgIJBQAAAA==.Anika:BAACLgAFFH8GAAIEAAMJPwLjLgCoAAAEAAMJPwLjLgCoAAAuAAQKfzAAAgQACQnrDBQmAKIBAAQACQnrDBQmAKIBAAAA.',
Ar='Arcade:BAAALgAECgEJAgAAAA==.Arlyx:BAACLgAFFH8LAAMBAAQJwxDWXgDaAAABAAMJyRDWXgDaAAAFAAIJpw85GwBPAAAuAAQKfycABAEACAkTH5EnACQCAAEABwlCG5EnACQCAAUAAwnzFohHAJgAAAYAAgnoBzQfAHcAAAAA.Arnwaz:BAAALgAECgYJDAAAAA==.Arthuria:BAAALgAECggJDAAAAA==.',
As='Aslan:BAAALgADCgQJBwAAAA==.',
At='Atelwen:BAAALgAECgcJBwAAAA==.',
Av='Avelyn:BAAALgAFFAIJAgAAAA==.',
Ba='Babyruthie:BAAALgAECgMJBAAAAA==.Baf:BAACLgAFFH8MAAIHAAQJaxf6KgA5AQAHAAQJaxf6KgA5AQAuAAQKfxoAAgcABwl3HYY+ACsCAAcABwl3HYY+ACsCAAAA.Bayside:BAAALgAECgYJEQAAAA==.',
Be='Bearfomat:BAABLgAFFH8FAAIIAAMJFh4CCQARAQAIAAMJFh4CCQARAQAAAA==.Beefis:BAAALgAECgUJCwAAAA==.Beenjuicin:BAAALgAFFAEJAgABLgAFFAIJAgADAAAAAA==.Berfomat:BAABLgAECn8oAAIJAAkJ1CGbAgDZAgAJAAkJ1CGbAgDZAgAAAA==.',
Bi='Bingchilling:BAACLgAFFH8SAAIKAAUJyRLpCgBrAQAKAAUJyRLpCgBrAQAuAAQKfzAAAgoACQnqHAgMAOoCAAoACQnqHAgMAOoCAAAA.',
Bj='Bjorn:BAAALgAFFAEJAQAAAA==.',
Bl='Bloomyvfd:BAABLgAECn8lAAILAAYJHyALGgAOAgALAAYJHyALGgAOAgAAAA==.',
Bo='Bombuur:BAAALgAECgQJCAAAAA==.Bonniebadass:BAAALgAECgYJEwAAAA==.Bottle:BAABLgAECn8UAAIEAAgJOxsJGAAKAgAEAAgJOxsJGAAKAgAAAA==.Boxxylove:BAAALgAECgQJBAAAAA==.',
Br='Bravas:BAAALgAECgcJBQAAAA==.Brimscythe:BAAALgADCgQJBAAAAA==.Broxar:BAAALgADCgcJCwAAAA==.',
['Bî']='Bîa:BAABLgAECn8cAAIHAAgJuyKZFQCkAgAHAAgJuyKZFQCkAgAAAA==.',
Ca='Cablemstache:BAAALgADCgcJBwAAAA==.Calisti:BAABLgAECn8tAAIMAAcJ/xvVZgAJAgAMAAcJ/xvVZgAJAgAAAA==.Capybubger:BAAALgAECggJCAAAAA==.Cavalis:BAACLgAFFH8HAAMBAAMJJg99ZADOAAABAAMJ3gt9ZADOAAAGAAEJSg6nGgBIAAAuAAQKfzAABAEACQl/G3svAAICAAEACAkUGXsvAAICAAYABQmyF7ESAAEBAAUABAk3GsETAOQAAAAA.',
Ce='Ceedh:BAAALgAFFAMJBAAAAA==.Ceejr:BAACLgAFFH8ZAAMEAAgJhCKlAQDoAQAEAAUJ5iKlAQDoAQANAAUJuCA6BQCuAQAuAAQKfyoAAwQACQlpJSQBAMQDAAQACQlpJSQBAMQDAA0ABgmLIi4NAPEBAAAA.Cerovallen:BAAALgAECgYJCQAAAA==.',
Ch='Chailee:BAAALgADCgEJAQAAAA==.Cherish:BAAALgADCgMJAwABLgAECgUJCgADAAAAAA==.Chillum:BAAALgAECgIJAgABLgAFFAQJDQAOAMsSAA==.Chimneybeans:BAAALgADCgcJBwAAAA==.',
Co='Corny:BAAALgAECgUJCwAAAA==.',
Cr='Creativez:BAABLgAFFH8IAAIPAAIJxRmzGACoAAAPAAIJxRmzGACoAAABLgAFFAQJBgAIAHAXAA==.Creativezd:BAABLgAFFH8GAAIIAAQJcBdUDQDVAAAIAAQJcBdUDQDVAAAAAA==.',
Da='Dadgoo:BAAALgAECgEJAgAAAA==.Damnskippy:BAAALgAECgcJDQAAAA==.Dannÿ:BAABLgAECn8iAAMQAAcJwxU1JQB2AQAQAAYJJBc1JQB2AQARAAMJow60TgCjAAAAAA==.Dantè:BAAALgAECgIJAgAAAA==.Daris:BAAALgADCgMJAwAAAA==.Darkire:BAACLgAFFH8GAAICAAMJpAtcSADXAAACAAMJpAtcSADXAAAuAAQKfykAAgIACAkQHA4qAAsCAAIACAkQHA4qAAsCAAAA.Darkstar:BAAALgADCgUJBQAAAA==.Darkwarriorx:BAAALgADCgQJAgAAAA==.',
De='Deathlegion:BAAALgAECgQJBAAAAA==.Deathroll:BAABLgAECn8oAAISAAkJNhmtDgCAAgASAAkJNhmtDgCAAgAAAA==.Delarus:BAAALgAECgEJAQAAAA==.Demonarmor:BAAALgAECgMJCAABLgAECgcJCAADAAAAAA==.',
Di='Diddley:BAAALgADCgMJAwAAAA==.',
Do='Dogmatik:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.Dontah:BAAALgADCgcJBwABLgAFFAMJBwATAK0eAA==.Doomward:BAABLgAECn8iAAIUAAcJMBOgcgBZAQAUAAcJMBOgcgBZAQAAAA==.Dorien:BAACLgAFFH8HAAITAAMJrR4XEgAdAQATAAMJrR4XEgAdAQAuAAQKfygAAxMACQmoIb8DAOICABMACQmoIb8DAOICAAIAAQnkExHpAEEAAAAA.',
Dr='Drachilly:BAACLgAFFH8NAAIOAAQJyxK5HwAdAQAOAAQJyxK5HwAdAQAuAAQKfyEABA4ACAkoHv4VACkCAA4ACAmSHf4VACkCABUABgknHj0QANgBABYAAQkPAmE8ABsAAAAA.Dragnar:BAABLgAECn8jAAICAAkJlwzuPQC3AQACAAkJlwzuPQC3AQAAAA==.Drakbonespur:BAAALgAECgcJCgAAAA==.Drhealzgood:BAAALgADCgYJBgAAAA==.Droggo:BAAALgADCgIJAgAAAA==.',
Ev='Evilvdduck:BAAALgAECgEJAQAAAA==.',
Ey='Eysia:BAAALgADCgUJCAAAAA==.',
Fa='Faewryn:BAAALgAECgkJEQAAAA==.Faeya:BAAALgADCgEJAQABLgADCgUJCAADAAAAAA==.Falekia:BAAALgAECgEJAQAAAA==.Fay:BAACLgAFFH8OAAIPAAQJ3BigFwA2AQAPAAQJ3BigFwA2AQAuAAQKfx4AAg8ACAnJIewSAHoCAA8ACAnJIewSAHoCAAAA.',
Fe='Felltown:BAAALgADCgMJAwAAAA==.',
Fi='Firstblood:BAAALgAECgYJCQAAAA==.Fishnchimps:BAABLgAFFH8IAAISAAMJyRe7IgDeAAASAAMJyRe7IgDeAAAAAA==.',
Fu='Fupalicious:BAAALgAECgYJBwABLgAECgUJBwADAAAAAA==.Furrburger:BAAALgADCgIJAgAAAA==.',
Ga='Gaiserik:BAABLgAECn8pAAIXAAgJKiGwBQCJAgAXAAgJKiGwBQCJAgAAAA==.Galenda:BAAALgADCgQJBQAAAA==.Gandolph:BAAALgADCgEJAQAAAA==.Garduhm:BAAALgADCgYJCQABLgAECgIJAgADAAAAAA==.Garlictoast:BAAALgAECgQJBwAAAA==.',
Ge='Gearsofhate:BAAALgAECgEJAgAAAA==.Gehenna:BAAALgADCgYJCgAAAA==.',
Go='Goldenorder:BAAALgAECggJCgAAAA==.Gome:BAAALgADCgcJGwABLgAFFAMJCAASAMkXAA==.',
Gr='Gracile:BAAALgADCgEJAQAAAA==.Gragolf:BAABLgAECn8dAAICAAkJPRN4NwDVAQACAAkJPRN4NwDVAQAAAA==.Greggor:BAAALgAECgYJDQAAAA==.Gronkus:BAAALgAECgYJBwAAAA==.',
Gu='Gustabo:BAABLgAECn8bAAIYAAYJGyLVCgDcAQAYAAYJGyLVCgDcAQAAAA==.',
Ha='Haslin:BAAALgADCgEJAQAAAA==.Havibonespur:BAABLgAECn8XAAMPAAYJXQuZQQDXAAAPAAYJXQuZQQDXAAAZAAEJyQSilwAgAAABLgAECgcJCgADAAAAAA==.',
He='Healir:BAABLgAECn8TAAMQAAgJZiIFFQAEAgAQAAgJZiIFFQAEAgARAAQJnh/ULAB3AQAAAA==.Healmepls:BAAALgADCgYJCgABLgAFFAUJDAAaAHcPAA==.Hellsong:BAAALgAECgEJAQAAAA==.Helor:BAABLgAECn8XAAMbAAkJcRakNADTAQAbAAkJcRakNADTAQAcAAUJ3RXDLgBXAQAAAA==.',
Hi='Hiéi:BAAALgAECgEJAQAAAA==.',
Ho='Holydeath:BAABLgAECn8YAAIdAAcJwB0PEABDAgAdAAcJwB0PEABDAgAAAA==.Hotpocketz:BAAALgADCgcJCQABLgAECggJFwAEACoXAA==.',
Hu='Hunterish:BAAALgADCgEJAQAAAA==.',
Ia='Iadrithe:BAAALgADCgYJBgAAAA==.',
In='Inspectadeck:BAAALgAECgMJBAAAAA==.Invisus:BAAALgAFFAEJAQAAAA==.',
Is='Ispayderj:BAAALgAECgMJBAAAAA==.',
Ja='Jahy:BAAALgADCgIJAgAAAA==.Jake:BAABLgAECn8iAAIHAAkJziVfBQB3AwAHAAkJziVfBQB3AwAAAA==.Jarlan:BAACLgAFFH8UAAIXAAUJbyLSBwB3AQAXAAUJbyLSBwB3AQAuAAQKfygAAhcACAmRI7sBACMDABcACAmRI7sBACMDAAAA.Jarlhun:BAABLgAECn8dAAIKAAcJjh01BwDwAQAKAAcJjh01BwDwAQABLgAFFAUJFAAXAG8iAA==.',
Je='Jellous:BAACLgAFFH8GAAMbAAIJpQbmbwBtAAAbAAIJBgXmbwBtAAAcAAEJZwv7DQBOAAAuAAQKfyoAAxwACQmCF5MTADgCABwACAl5GJMTADgCABsACQllFN4zACoCAAAA.Jethereal:BAAALgADCgcJBwABLgAFFAIJBgAbAKUGAA==.',
Ju='Jurista:BAAALgADCgYJBgAAAA==.Justin:BAAALgAECgYJBgAAAA==.',
Ke='Ketharion:BAABLgAECn8rAAMLAAkJ5RVqFwAmAgALAAkJ5RVqFwAmAgAHAAEJiguDYAEyAAAAAA==.Kevamin:BAAALgAECgYJEwAAAA==.',
Kh='Khaela:BAAALgAECgIJAgAAAA==.Khato:BAAALgAECggJDgAAAA==.',
Ki='Killya:BAAALgADCgEJAQAAAA==.Kirasha:BAAALgADCgcJBwAAAA==.',
Ku='Kulfa:BAAALgADCgcJCgAAAA==.Kurailos:BAAALgADCggJCAAAAA==.Kurisu:BAAALgAECgQJCAAAAA==.',
La='Lailyne:BAABLgAECn8eAAQTAAkJ+BNoIQBxAQATAAcJIA1oIQBxAQAKAAYJ8A2mRgA6AQACAAUJexSWfwAQAQAAAA==.Lake:BAAALgAECgcJDAAAAA==.',
Le='Learned:BAABLgAECn8UAAIUAAgJzAordgBRAQAUAAgJzAordgBRAQAAAA==.Leo:BAABLgAECn8ZAAINAAgJSRz/CgAbAgANAAgJSRz/CgAbAgAAAA==.Leone:BAAALgAECgYJBwAAAA==.',
Li='Lilany:BAACLgAFFH8HAAIeAAMJugyhPgC2AAAeAAMJugyhPgC2AAAuAAQKfxUAAh4ACQlPFs8yALgBAB4ACQlPFs8yALgBAAAA.Lillymeii:BAAALgAECgEJAQAAAA==.Linova:BAAALgADCgUJBQAAAA==.Lithrak:BAABLgAECn8wAAIfAAkJ0B8rBADfAgAfAAkJ0B8rBADfAgAAAA==.',
Lo='Logical:BAAALgAECgYJBgAAAA==.Lorakine:BAAALgADCgUJBQAAAA==.',
Lu='Luciferr:BAAALgADCgEJAQAAAA==.Lucit:BAAALgAECgYJBwABLgAFFAQJCwABAMMQAA==.Lute:BAAALgAECgQJCAAAAA==.',
Ly='Lyric:BAAALgADCgcJDAABLgAFFAQJDgAPANwYAA==.',
['Lá']='Lárien:BAABLgAECn8XAAIgAAcJsxScOwCDAQAgAAcJsxScOwCDAQAAAA==.',
Ma='Mable:BAAALgADCggJCAAAAA==.Magicmicah:BAAALgADCgcJBwAAAA==.Manon:BAACLgAFFH8OAAIeAAQJMxh6HgA4AQAeAAQJMxh6HgA4AQAuAAQKfxwAAx4ACAllFhEtANYBAB4ACAllFhEtANYBABoAAQm+B9KVACUAAAAA.',
Mc='Mcchungus:BAABLgAECn8XAAMCAAcJxxaeVQB0AQACAAcJlRWeVQB0AQATAAUJgBKTLgAOAQAAAA==.',
Me='Meliodas:BAAALgAECgQJBgAAAA==.Menghao:BAABLgAECn8WAAMMAAcJ3wU3sAAGAQAMAAcJ3wU3sAAGAQAhAAIJ3AFqGgBEAAAAAA==.Meowmixx:BAAALgAECgcJAwAAAA==.',
Mi='Mikayybrew:BAAALgADCgUJBQAAAA==.Mischief:BAACLgAFFH8NAAIGAAUJAxCpAgBGAQAGAAUJAxCpAgBGAQAuAAQKfzkAAgYACQlOHd0CAGkCAAYACQlOHd0CAGkCAAAA.',
Mk='Mk:BAEALgAECgQJCQABLgAECggJOwAZAGsjAA==.',
Mo='Mooage:BAACLgAFFH8GAAIMAAIJYiDBMwDLAAAMAAIJYiDBMwDLAAAuAAQKfzMAAgwACQmcJBcMAGQDAAwACQmcJBcMAGQDAAAA.Morewyn:BAABLgAECn8nAAICAAkJVBLKLQD8AQACAAkJVBLKLQD8AQAAAA==.Mozoh:BAAALgADCgMJAwABLgAECgIJAgADAAAAAA==.',
Na='Nalock:BAAALgAECgEJAQAAAA==.',
Ne='Nerrgall:BAAALgADCgcJBwAAAA==.',
Ni='Nickignomaj:BAABLgAECn8hAAQZAAgJkxo3DwAuAgAZAAgJkxo3DwAuAgASAAQJLBElRwC+AAAPAAUJswZiUgCeAAABLgAFFAIJBQAXANcQAA==.Nidhogg:BAAALgADCgcJBwABLgAECgkJIQAeANcaAA==.Nisara:BAAALgAECggJEgAAAA==.',
No='Noellie:BAAALgAFFAEJAgAAAA==.Noobdestroya:BAAALgAECgQJDwAAAA==.Nosfuratu:BAAALgADCgkJCQAAAA==.',
Ny='Nymi:BAAALgADCgYJBgAAAA==.',
Of='Offline:BAAALgADCgcJCwAAAA==.',
Ol='Oldbutcool:BAAALgADCgEJAgAAAA==.',
Om='Omantul:BAABLgAECn8hAAMeAAkJ1xqGIgAQAgAeAAgJDRqGIgAQAgAaAAYJUBlIRADyAAAAAA==.',
Or='Orangez:BAAALgAECgMJBAAAAA==.',
Ou='Ouija:BAAALgAECgEJAQAAAA==.',
Ow='Owocoxl:BAAALgADCgYJCwABLgAFFAUJEgAiALkQAA==.',
Pa='Painfull:BAABLgAECn8jAAIbAAgJpB1DKAALAgAbAAgJpB1DKAALAgAAAA==.Pants:BAAALgAECgEJAQAAAA==.Paz:BAAALgADCgcJBwABLgAECgIJAgADAAAAAA==.',
Ph='Phakes:BAAALgAECgUJCAAAAA==.Phengzera:BAABLgAECn8WAAIMAAcJMBX3dADoAQAMAAcJMBX3dADoAQAAAA==.Phizz:BAABLgAFFH8JAAIbAAQJKxOTMwAiAQAbAAQJKxOTMwAiAQAAAA==.',
Po='Po:BAAALgADCgcJDQABLgAFFAUJDgAbACARAA==.Pontius:BAAALgADCgMJAwABLgAECgkJDgADAAAAAA==.',
Pr='Prowlborn:BAAALgADCgEJAQAAAA==.',
Pu='Puke:BAABLgAECn8mAAIjAAkJ9SRjAABWAwAjAAkJ9SRjAABWAwAAAA==.Pumpkinspice:BAAALgADCgUJBgAAAA==.Purplepower:BAAALgAECgMJBAAAAA==.',
Ra='Rarim:BAAALgAECgkJDgAAAA==.',
Re='Reaperfive:BAAALgADCgcJBwAAAA==.Redbonespur:BAAALgADCgcJBwABLgAECgcJCgADAAAAAA==.',
Ri='Rimtardo:BAAALgAECgQJBwAAAA==.Rio:BAAALgAECgMJAwABLgAFFAQJBgABAMAHAA==.',
Ro='Rotdaddy:BAABLgAECn8aAAIiAAgJ4BGHLQCVAQAiAAgJ4BGHLQCVAQAAAA==.Roxxev:BAAALgADCgcJBwAAAA==.',
Ry='Ryø:BAABLgAECn8cAAMgAAkJsgdkWwBAAQAgAAkJsgdkWwBAAQAIAAgJhwcJKgDFAAAAAA==.',
Sa='Saintrandy:BAAALgADCgMJAwAAAA==.Saphiel:BAAALgAECgEJAQAAAA==.',
Sc='Scorch:BAAALgADCgcJCgAAAA==.',
Se='Seraphym:BAAALgADCgYJCAAAAA==.',
Sh='Shaviji:BAAALgAECgcJBwAAAA==.Shinra:BAAALgADCgEJAQAAAA==.Shore:BAABLgAECn8eAAMTAAkJ8xvoCQBoAgATAAkJ8xvoCQBoAgAKAAYJQRJIEQAgAQAAAA==.Shrekw:BAAALgAECgcJEAAAAA==.Shuralya:BAACLgAFFH8TAAMHAAQJfxtmHQBeAQAHAAQJfxtmHQBeAQALAAMJURKNJgDBAAAuAAQKf0MAAwcACQkhJA0EAEoDAAcACQkhJA0EAEoDAAsACQk9GH0gABcCAAAA.',
Si='Silverhorn:BAAALgAECggJDgAAAA==.Siouxsie:BAAALgADCgcJCgAAAA==.',
Sm='Smoldnrg:BAAALgAECgUJBQAAAA==.',
So='Sofka:BAABLgAECn8fAAMkAAkJCQ5uGgB+AQAkAAkJCQ5uGgB+AQAUAAEJMgHwOwEbAAAAAA==.Sourpatch:BAAALgAECgIJAgAAAA==.',
St='Stilts:BAABLgAECn8UAAMfAAcJpxwWCgDkAQAfAAcJpxwWCgDkAQAeAAQJsAVNfwCWAAAAAA==.Stradynia:BAAALgAECggJDwAAAA==.Stuart:BAAALgADCgMJAwABLgAECgIJAgADAAAAAA==.Stócky:BAAALgAECgcJEwAAAA==.',
Su='Sui:BAAALgADCgUJCAAAAA==.Survas:BAACLgAFFH8GAAIiAAMJfg5dIADeAAAiAAMJfg5dIADeAAAuAAQKfx4AAiIACAmqGfocABcCACIACAmqGfocABcCAAAA.',
Sw='Swobu:BAAALgAECgEJAQAAAA==.',
Sy='Sylwynn:BAAALgADCgUJCAAAAA==.',
['Sá']='Sárkány:BAAALgADCgcJCQAAAA==.',
Ta='Talanaz:BAAALgAECgYJDAAAAA==.Taleah:BAAALgAECgEJAgAAAA==.Taleb:BAAALgAECgYJEAABLgAECgcJDQADAAAAAA==.Tardor:BAAALgADCgMJAwAAAA==.Tavgoesboom:BAAALgAFFAIJAgABLgAFFAMJCAASAMkXAA==.Tawna:BAAALgAECgQJBQAAAA==.',
Te='Tealan:BAABLgAECn8VAAQOAAgJuRZGKAB7AQAOAAcJSxVGKAB7AQAWAAYJmhTVJwA1AQAVAAEJOQjJQAAvAAAAAA==.Tenyi:BAAALgAECgMJAwAAAA==.Terrin:BAAALgAECgQJBQABLgAECgcJDQADAAAAAA==.',
To='Toospooky:BAAALgAECgYJDgAAAA==.Tovlacar:BAAALgAECgUJBgABLgAECgkJMAAQAO0PAA==.Toyboy:BAAALgAECgQJBAAAAA==.',
Tr='Triage:BAABLgAECn8UAAQhAAcJbx9sBAAFAgAhAAUJCSRsBAAFAgAMAAQJihie7gAcAQAlAAEJTRbXDQA+AAAAAA==.Trolladin:BAAALgAECgEJAQAAAA==.Tronarn:BAAALgAECgcJDQAAAA==.',
Ty='Tyrias:BAAALgAECggJAwAAAA==.',
Ug='Ugin:BAACLgAFFH8GAAMmAAMJbQVnDwC4AAAmAAMJbQVnDwC4AAAUAAIJ5wNivgB6AAAuAAQKfyoAAyYACQk+F0EHAOEBACYACQkXFkEHAOEBABQACAnsEF1vAGABAAAA.',
Um='Umaydie:BAAALgAECgIJAwAAAA==.Umbrasyl:BAAALgAECgUJBgAAAA==.',
Un='Unclecharlie:BAAALgAECgUJCQABLgAFFAQJCQAmALsbAA==.Unholylukers:BAAALgAECgIJAwAAAA==.Unit:BAAALgADCgcJCwAAAA==.',
Va='Valkrit:BAAALgADCgIJAgAAAA==.Vasrin:BAABLgAECn8wAAIfAAkJ5iFbAgDZAgAfAAkJ5iFbAgDZAgAAAA==.',
Ve='Velaria:BAAALgADCgYJEAABLgAECgYJDAADAAAAAA==.Veon:BAAALgADCgYJBgAAAA==.Verlehn:BAAALgADCgcJBgAAAA==.',
Vo='Voidomo:BAAALgAFFAEJAQAAAA==.Vonbearback:BAAALgAECgEJAQAAAA==.',
Wa='Walden:BAABLgAECn8XAAIIAAcJJhbkFwBRAQAIAAcJJhbkFwBRAQAAAA==.Waterlance:BAAALgAECgEJBAAAAA==.',
Wi='Wisecraic:BAAALgADCgcJDQAAAA==.Wispi:BAAALgAECgQJBAAAAA==.',
Wo='Wocoxl:BAACLgAFFH8SAAIiAAUJuRAhEwBHAQAiAAUJuRAhEwBHAQAuAAQKfycAAiIACQlIHbUGACQDACIACQlIHbUGACQDAAAA.',
Xe='Xerah:BAAALgADCggJDgAAAA==.',
Ya='Yaracklea:BAAALgAECggJEQAAAA==.',
Yi='Yingu:BAAALgADCgEJAQAAAA==.',
['Yü']='Yüki:BAAALgAECgIJAgAAAA==.',
Za='Zabaniya:BAAALgADCgEJAQAAAA==.Zac:BAAALgADCgYJDAAAAA==.Zacceptable:BAABLgAECn8VAAIhAAcJWBSCCQBRAQAhAAcJWBSCCQBRAQAAAA==.Zaida:BAAALgADCgUJBQABLgAECgIJAgADAAAAAA==.',
Ze='Zeale:BAACLgAFFH8GAAIBAAQJwAcdTgADAQABAAQJwAcdTgADAQAuAAQKfysAAgEACQkeGD4cAGECAAEACQkeGD4cAGECAAAA.Zenedict:BAABLgAECn8WAAMeAAkJJBo4FAB9AgAeAAkJJBo4FAB9AgAaAAIJygkOcgBcAAAAAA==.',
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
