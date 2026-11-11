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

local lookup = {'Rogue-Subtlety','Monk-Brewmaster','Warlock-Demonology','Priest-Holy','Warrior-Fury','Mage-Arcane','Warlock-Destruction','Druid-Restoration','Druid-Balance','Paladin-Holy','Paladin-Retribution','Priest-Shadow','Priest-Discipline','Monk-Mistweaver','Paladin-Protection','Unknown-Unknown','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Unholy','Druid-Guardian','Hunter-BeastMastery','Hunter-Survival','Warrior-Arms','Warrior-Protection','Evoker-Preservation','Shaman-Enhancement','Evoker-Augmentation','Hunter-Marksmanship','Monk-Windwalker','Druid-Feral','Mage-Frost','Rogue-Assassination','Shaman-Elemental','Shaman-Restoration','DemonHunter-Vengeance','DeathKnight-Frost',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Acid:BAACNQAFFH8JAAIBAAYK3gYDDgANAQABAAYK3gYDDgANAQA1AAQKfzkAAgEACgpRF5wNAJwCAAEACgpRF5wNAJwCAAAA.',
Ae='Aela:BAAANQAECgEIAQABNQAFFAYICQACANYWAA==.Aelin:BAAANQAECgUICAAAAA==.',
Af='Affliction:BAAANQADCgEIAQAAAA==.',
Al='Alanispally:BAAANQADCgcICwAAAA==.Alkanz:BAABNQAECn8mAAIDAAoKFAyzUwDFAQADAAoKFAyzUwDFAQAAAA==.Allinaa:BAAANQAECggICgAAAA==.Alya:BAABNQAECn9FAAIEAAoK5BqbLQCyAgAEAAoK5BqbLQCyAgAAAA==.',
Am='Amelvia:BAAANQADCgMIAwAAAA==.',
An='Anika:BAABNQAECn8lAAIFAAoK3wkuEQCSAQAFAAoK3wkuEQCSAQAAAA==.Anshi:BAAANQAECgUIBgABNQAECgkJKgAGAKwWAA==.',
Ar='Archspìre:BAAANQAECgEIAwAAAA==.Arise:BAAANQADCgIIAgAAAA==.Arlyx:BAABNQAECn8tAAMDAAoKhCFOSQDmAQADAAkKuSJOSQDmAQAHAAUK0hZyJwA8AQAAAA==.Arnwaz:BAABNQAECn8VAAMIAAgKNhPBNQBuAQAIAAgKNhPBNQBuAQAJAAMKbQcCkACWAAAAAA==.Arthuria:BAABNQAECn8jAAMKAAoKtBL7cgBJAQAKAAkK0xL7cgBJAQALAAcK+A/RFwH4AAAAAA==.',
As='Ashfia:BAAANQAECgEIBAAAAA==.Ashmegan:BAAANQAECgEIBAAAAA==.Ashrom:BAAANQAECgEIAwAAAA==.Ashzazul:BAAANQAECgEIBQAAAA==.Ashzia:BAAANQAECgEIBAAAAA==.Asianverstop:BAABNQAECn8eAAQEAAoKbSFuRwBQAgAEAAkK1iBuRwBQAgAMAAgKCB/CFgDhAQANAAEKihy/EwBRAAAAAA==.',
At='Atelwen:BAAANQADCgYJBgAAAA==.',
Ba='Baf:BAABNQAECn8wAAILAAoK3yOFGABiAwALAAoK3yOFGABiAwAAAA==.Banano:BAAANQAECgIIAgAAAA==.Banjodave:BAABNQAECn8XAAIOAAoKpQtBGQBWAQAOAAoKpQtBGQBWAQAAAA==.',
Be='Berfomat:BAABNQAECn8uAAIPAAoKDiDoBwAiAwAPAAoKDiDoBwAiAwAAAA==.Berfsteals:BAAANQADCgIIBAAAAA==.Berfy:BAAANQAECgMIAwAAAA==.',
Bj='Bjorn:BAAANQAECgYICQAAAA==.',
Bl='Black:BAAANQADCggIEAAAAA==.Blackky:BAAANQAECgQICAAAAA==.Bloodyfupa:BAAANQADCgEIAQAAAA==.Bloomyvfd:BAABNQAECn8pAAIKAAoK8xpHEAAtAwAKAAoK8xpHEAAtAwAAAA==.',
Bo='Bocc:BAAANQADCgQIBQABNQAECgcIEAAQAAAAAA==.Boombip:BAAANQAECgEIAwAAAA==.Boxxylove:BAAANQADCggIGgABNQAECgoKRQAEAOQaAA==.',
Br='Brockz:BAAANQADCgQIBwAAAA==.',
Bu='Bulldan:BAAANQABCgIIAQAAAA==.',
['Bî']='Bîa:BAABNQAECn9JAAILAAoKcyOlKgAdAwALAAoKcyOlKgAdAwAAAA==.',
Ca='Cavalis:BAABNQAECn86AAQHAAoKdhY2EgC7AAADAAgKBBEhggDhAQARAAYKQRVzFADWAAAHAAUKXxc2EgC7AAAAAA==.',
Ce='Ceedk:BAACNQAFFH8JAAISAAUKIyGqDACKAQASAAUKIyGqDACKAQA1AAQKfyEAAxMACQrIJsERACkDABMACQrIJsERACkDABIABwrYIbgsAGQCAAE1AAUUCAgYAAkACh0A.Ceesh:BAAANQAECggICQABNQAFFAgIGAAJAAodAA==.',
Ch='Cherradan:BAAANQADCggICAAAAA==.Chickenparm:BAAANQAECgIIAgAAAA==.Chll:BAAANQAECgIIAgABNQAFFAYIEgATAAYeAA==.',
Cj='Cjjackpot:BAAANQADCgYJCwAAAA==.',
Co='Cobb:BAAANQAECgcIEAAAAA==.Coorsbanquet:BAAANQADCgMIAwAAAA==.',
Cr='Creativezd:BAACNQAFFH8YAAMJAAgKCh3pAwB6AgAJAAgKMxrpAwB6AgAUAAUKXSIsAQDrAQA1AAQKfyUAAxQACQpSIxEQACICABQACAr2IhEQACICAAkABgpjIV8jAM0BAAAA.Crowley:BAAANQAECgMICwAAAA==.',
Da='Dadgoo:BAAANQAECgYICgAAAA==.Damnskippy:BAAANQAECgcIDAAAAA==.Dannÿ:BAABNQAECn8lAAQEAAgK8B6KPgArAgAEAAgK8B6KPgArAgAMAAUK2hCVQwAYAQANAAMKRAshGwCPAAAAAA==.Darkire:BAABNQAECn8fAAIVAAoK6BTGSgAmAgAVAAoK6BTGSgAmAgAAAA==.',
De='Deathlegion:BAAANQADCgUIBQAAAA==.Deathroll:BAABNQAECn8sAAIOAAoKphPXFAAuAgAOAAoKphPXFAAuAgAAAA==.Deaux:BAAANQAECggICwAAAA==.Demosucc:BAACNQAFFH8aAAMDAAcKKxsjCwBVAQADAAYKTRwjCwBVAQAHAAEKphZDGQBSAAA1AAQKfyQABAMACgo5Ix8hAAADAAMACQrnIx8hAAADABEABwpQFdEIALQBAAcAAQp3HuxtAEMAAAAA.Dethandra:BAAANQADCggICAAAAA==.',
Di='Diabolic:BAAANQAECgUIBQAAAA==.',
Dk='Dkchilly:BAACNQAFFH8SAAITAAYKBh6YAgBnAQATAAYKBh6YAgBnAQA1AAQKfzEAAhMACgrEIlUgAMkCABMACgrEIlUgAMkCAAAA.',
Do='Doomward:BAAANQAECgYIDgAAAA==.Dorien:BAABNQAECn8pAAMWAAkKnRr6AgDxAgAWAAkKXBj6AgDxAgAVAAgKFxp2YABWAgAAAA==.',
Dw='Dwish:BAAANQAECggIBAAAAA==.',
['Då']='Dårk:BAAANQADCgEIAQABNQABCgIIAgAQAAAAAA==.',
El='Elysele:BAAANQADCgUIBQABNQAECgoKPgAEAPoSAA==.',
Er='Erale:BAAANQAECgcIDQAAAA==.',
Fa='Faewryn:BAABNQAECn8oAAIKAAoK3RhOMwA/AgAKAAoK3RhOMwA/AgAAAA==.Falekia:BAAANQAECgcICgAAAA==.Falnaz:BAAANQAECgIIAwAAAA==.Fay:BAACNQAFFH8JAAICAAYK1hYrAwAuAQACAAYK1hYrAwAuAQA1AAQKfzgAAgIACgqaIuEDAEgDAAIACgqaIuEDAEgDAAAA.',
Fe='Fellus:BAAANQADCgIIAgAAAA==.Fengmeng:BAAANQADCggIEwAAAA==.',
Fi='Fishnchimps:BAAANQAECggIDAAAAA==.',
Fr='Freezah:BAAANQAECgUIBgAAAA==.Frogz:BAAANQADCgYIBgAAAA==.Fríeren:BAAANQAECgYIEAAAAA==.',
Fu='Fupalicious:BAAANQAECgUIEQABNQAECgYIHAASAHIVAA==.Furrburger:BAAANQAECgMIAwAAAA==.',
Ga='Gaiserik:BAABNQAECn8ZAAQXAAkKOBMnfwAdAgAXAAgKbRUnfwAdAgAFAAEKUg7hMQA5AAAYAAEKnwTTRQAoAAAAAA==.Galad:BAAANQAECggICwAAAA==.Garlictoast:BAAANQADCgYJBgAAAA==.',
Gi='Gillgamesh:BAAANQAECgcICwAAAA==.',
Go='Goochegg:BAAANQADCgUIBQAAAA==.',
Gr='Gragolf:BAAANQAECggIDAAAAA==.Greggor:BAAANQAECgUICAAAAA==.Griffin:BAAANQADCggIDgAAAA==.Grippyfupa:BAAANQAECgQIBwAAAA==.',
Gu='Gulzerak:BAABNQAECn8aAAMDAAoKOiHSUADOAQADAAgKHCDSUADOAQAHAAIKlCRNPgDJAAABNQAFFAYIFgAZACohAA==.Gustabo:BAAANQADCgIIAgAAAA==.',
Ha='Harby:BAAANQAECgMIAwAAAA==.Harnatauren:BAAANQADCggIHgAAAA==.Hawtynaughty:BAAANQADCgYIBgAAAA==.',
He='Helcular:BAAANQAECgcIEAAAAA==.Hexuz:BAABNQAECn8tAAIaAAoKQxKxDgB/AgAaAAoKQxKxDgB/AgAAAA==.',
Hi='Hittu:BAAANQAECggIEgAAAA==.',
Ho='Holyblunt:BAACNQAFFH8OAAILAAUKcxtWEwDcAAALAAUKcxtWEwDcAAA1AAQKfzIAAgsACgq/JegQAIUDAAsACgq/JegQAIUDAAAA.',
Id='Idk:BAAANQAECgcIEgAAAA==.',
Ik='Ikisscutemen:BAABNQAECn8iAAMZAAkKUhUtDABLAgAZAAkKUhUtDABLAgAbAAcK2xjTBwAmAgABNQAECgoKHgAEAG0hAA==.',
In='Inthezone:BAABNQAECn8YAAMVAAcKxBL1kADnAQAVAAcKxBL1kADnAQAcAAUKEAZJUwDaAAAAAA==.Invisus:BAABNQAECn8lAAIFAAkKNBuvBQBjAgAFAAkKNBuvBQBjAgAAAA==.',
Is='Ispayders:BAAANQAECgEIAQAAAA==.',
Ja='Jarlan:BAACNQAFFH8FAAIXAAMKkhZZJADcAAAXAAMKkhZZJADcAAA1AAQKfyoAAhcACQrNIWAyAPYCABcACQrNIWAyAPYCAAAA.Jarlhun:BAAANQADCggIEgABNQAFFAMIBQAXAJIWAA==.Jarmon:BAABNQAECn8ZAAIdAAYK4x8JJAAFAgAdAAYK4x8JJAAFAgABNQAFFAMIBQAXAJIWAA==.',
Jo='Joolian:BAACNQAFFH8FAAIeAAQKwxsmAQABAQAeAAQKwxsmAQABAQA1AAQKfygABB4ACgq8Jb0AAHgDAB4ACgq8Jb0AAHgDAAkAAgoiGMOhAFkAAAgAAQoGGf9vAEUAAAE1AAUUCAgcAB8ACxYA.Joolianr:BAABNQAECn8ZAAMgAAgKcxUHJgD7AAABAAgKdRSMUAClAQAgAAUKkhQHJgD7AAABNQAFFAgIHAAfAAsWAA==.',
Ju='Justin:BAABNQAECn8vAAISAAoKZhiELQBgAgASAAoKZhiELQBgAgAAAA==.',
Ka='Kaiveza:BAAANQAECgYICgABNQAFFAcIFAADADMgAA==.Katara:BAAANQADCggICAAAAA==.Kattsumoto:BAACNQAFFH8NAAMOAAYKcBfqAgDOAQAOAAYKcBfqAgDOAQAdAAEKBQhxEwA2AAA1AAQKfzgAAw4ACgq+IkUFAE0DAA4ACgq+IkUFAE0DAB0ABgrrEwxGAOwAAAAA.',
Ke='Ketharion:BAABNQAECn8+AAMKAAoKaBfDMwA9AgAKAAoKaBfDMwA9AgALAAUKgAmRFgH6AAAAAA==.',
Kh='Khato:BAAANQAECgMICQAAAA==.',
Ku='Kurazan:BAACNQAFFH8WAAIXAAYKsRm6DQBHAQAXAAYKsRm6DQBHAQA1AAQKfzUAAhcACgoFI55CAMICABcACgoFI55CAMICAAAA.Kurisu:BAABNQAECn8fAAIDAAcK4w2k2wASAQADAAcK4w2k2wASAQAAAA==.',
La='Lafaymignon:BAAANQABCgIIAgAAAA==.Lanfear:BAAANQAECgMIBAAAAA==.Lavabolter:BAAANQAECgEIAQAAAA==.Laîlyne:BAABNQAECn8rAAMhAAoKzxRcLwAHAgAhAAoKzxRcLwAHAgAiAAIKagUT4gBHAAAAAA==.',
Le='Leo:BAAANQAECgcICwAAAA==.Leone:BAAANQAECgYIDwAAAA==.',
Li='Lilany:BAAANQABCgIIAgAAAA==.Lilath:BAAANQAECgEIAQAAAA==.',
Lo='Logical:BAABNQAECn9AAAILAAoKSBzAOAB0AgALAAoKSBzAOAB0AgAAAA==.Lost:BAAANQAECgEIAQAAAA==.',
Lu='Lucit:BAAANQAECgMIAwABNQAECgoKLQADAIQhAA==.Lute:BAABNQAECn8mAAISAAgK8BxeIQCpAgASAAgK8BxeIQCpAgAAAA==.',
['Lá']='Lárien:BAAANQAECgQIBgAAAA==.',
Ma='Manon:BAACNQAFFH8IAAIiAAUKRAxeEAA3AQAiAAUKRAxeEAA3AQA1AAQKfzAAAyIACgpaD+FiAOUBACIACgpaD+FiAOUBACEACQrLBi+YAGgBAAAA.Maxacry:BAAANQADCgIIAgAAAA==.Maxstoke:BAAANQAECggIDQAAAA==.',
Mc='Mcchungus:BAABNQAECn8XAAIVAAoKPw/VVQAJAgAVAAoKPw/VVQAJAgAAAA==.',
Me='Meowmixx:BAAANQAECgEIAQAAAA==.',
Mi='Mischief:BAAANQADCgYICwAAAA==.',
Mo='Morewyn:BAAANQAECgEIAwAAAA==.Mortred:BAAANQAECgEIAQAAAA==.',
Mt='Mtd:BAAANQAECgYICAABNQAECgoKQgAWADoeAA==.Mth:BAABNQAECn8dAAMWAAgKqhliBgA2AgAWAAgKqhliBgA2AgAcAAUKigrrTAD+AAABNQAECgoKQgAWADoeAA==.',
Na='Nadok:BAAANQAECggIDwAAAA==.Nancyy:BAAANQAECgEIAQAAAA==.Naz:BAAANQAECgIIAgAAAA==.',
Ni='Nickignomaj:BAAANQAECgUIBQABNQAECgoKNAAXAPkdAA==.Nisara:BAAANQAECgMIAwAAAA==.',
No='Norina:BAAANQADCgYICwAAAA==.',
Ob='Obv:BAABNQAECn8ZAAIjAAkKjBgICwAjAgAjAAkKjBgICwAjAgAAAA==.',
Om='Omantul:BAABNQAECn8dAAIiAAgKERdHXAD6AQAiAAgKERdHXAD6AQAAAA==.',
Oo='Oobie:BAAANQADCgYIBgAAAA==.',
Ow='Owocoxl:BAAANQAECgcIEQABNQAFFAgIHQAgAPAPAA==.',
Oz='Ozziee:BAAANQAECgMIBQAAAA==.Ozzthehunter:BAAANQADCgIIAgAAAA==.',
Pa='Pants:BAAANQADCggIGQAAAA==.Paroguei:BAAANQAECgYIDwABNQAECgoKLQAKAMkiAA==.',
Ph='Phakes:BAABNQAECn8VAAIcAAgKTAqwIgBBAQAcAAgKTAqwIgBBAQAAAA==.Phengzera:BAAANQAECgMIBAAAAA==.Phizz:BAAANQADCggICgABNQAFFAgIJAAGADEeAA==.',
Pl='Pllwprincess:BAAANQADCgIIAgAAAA==.',
Po='Pocky:BAAANQAECgQIBQAAAA==.Poofty:BAAANQADCgUIBQAAAA==.',
Pr='Predator:BAACNQAFFH8dAAIXAAgKdCZ+AQD+AgAXAAgKdCZ+AQD+AgA1AAQKf0gAAhcACgrYJnYBAIsDABcACgrYJnYBAIsDAAAA.Prolove:BAAANQAECgIIAgAAAA==.',
Pu='Puke:BAABNQAECn8gAAIjAAgKriTpAgBGAwAjAAgKriTpAgBGAwAAAA==.Purpledisco:BAAANQADCggICAABNQAECgoKRQAEAOQaAA==.Purplepower:BAABNQAECn8iAAIXAAgKoRlTdAA4AgAXAAgKoRlTdAA4AgAAAA==.',
Pw='Pwincess:BAAANQAECgQIBAAAAA==.',
Qi='Qin:BAAANQAECggIAQAAAA==.',
Qw='Qwelmo:BAAANQADCgEJAgAAAA==.',
Ra='Radkil:BAAANQAECgEIAgAAAA==.',
Ri='Rigaud:BAAANQADCgMIAwAAAA==.',
Ro='Roaka:BAAANQABCgIIAgAAAA==.Rolypoly:BAAANQAECgUIBQAAAA==.',
Ry='Ryø:BAABNQAECn8mAAMUAAoKahZXGwDJAQAUAAoK9BRXGwDJAQAeAAQK1wuuKgCaAAAAAA==.',
Se='Seigler:BAABNQAECn8rAAIWAAkKbguzCAC+AQAWAAkKbguzCAC+AQAAAA==.Senne:BAAANQAECgQIBwAAAA==.Seraphym:BAAANQAECgIIBAAAAA==.',
Sh='Shaviji:BAAANQAECggICgAAAA==.Shigzen:BAAANQAECgIIAwABNQADCggICQAQAAAAAA==.Shore:BAABNQAECn9CAAMWAAoKOh5IAQBoAwAWAAoKOh5IAQBoAwAcAAMK5A27YgCeAAAAAA==.Shuralya:BAABNQAECn9dAAILAAoKgSPCEwAQAwALAAoKgSPCEwAQAwAAAA==.',
Sk='Skoob:BAAANQAECgMIAgAAAA==.',
So='Sonofabirch:BAAANQADCgMIAwAAAA==.',
Sp='Spokelse:BAABNQAECn8pAAIkAAgKyQT/YwATAQAkAAgKyQT/YwATAQAAAA==.',
St='Striga:BAAANQABCgEIAQAAAA==.',
Su='Sully:BAAANQADCggIDgAAAA==.Survas:BAACNQAFFH8FAAIBAAIK8AeFJgA4AAABAAIK8AeFJgA4AAA1AAQKfysAAgEACgrxEkgTAFECAAEACgrxEkgTAFECAAAA.',
Ta='Tavgoesboom:BAAANQAECgQIBQABNQAECggIDAAQAAAAAA==.',
Te='Terrin:BAABNQAECn8eAAIXAAoKFxbOagCqAQAXAAoKFxbOagCqAQAAAA==.Texmexdruid:BAAANQADCggIDgAAAA==.',
Th='Tharkun:BAABNQAECn8YAAIGAAcKthropgA0AgAGAAcKthropgA0AgAAAA==.Thedagda:BAAANQAECgQIBAAAAA==.Thunderlinkx:BAAANQAECgEIAQABNQAECgcIDQAQAAAAAA==.',
Ti='Titlecard:BAAANQAECgEIAgAAAA==.',
To='Tora:BAAANQAFFAEIAQAAAA==.',
Tr='Triage:BAABNQAECn8eAAIGAAkKBxkMlgBUAgAGAAkKBxkMlgBUAgAAAA==.',
Ts='Tsu:BAEBNQAECn8UAAILAAgKGwdaxgAyAQALAAgKGwdaxgAyAQAAAA==.Tsuko:BAEANQAECgIIAgABNQAECggIFAALABsHAA==.',
Tu='Tul:BAABNQAECn8hAAIKAAoKXh6FGgDUAgAKAAoKXh6FGgDUAgAAAA==.',
Tw='Twotoedfupa:BAABNQAECn8cAAISAAYKchWuYwBjAQASAAYKchWuYwBjAQAAAA==.',
Ty='Tyrias:BAABNQAECn8eAAILAAkKkAVygQFXAAALAAkKkAVygQFXAAAAAA==.',
Ug='Ugin:BAABNQAECn8eAAMTAAoKsQtaVADAAQATAAoKhwtaVADAAQAkAAMKJAqvhwCTAAAAAA==.',
Um='Umbrasyl:BAAANQAECgMIBAAAAA==.',
Un='Unclecharlie:BAAANQAECgUIBgABNQAFFAUIBgAkAMQbAA==.Undeadrogue:BAAANQADCgQIBAAAAA==.',
Va='Vasrin:BAABNQAECn8wAAIaAAoKEiJQBgAhAwAaAAoKEiJQBgAhAwAAAA==.',
Vo='Voidomo:BAABNQAECn9AAAQRAAoKOBctBgBPAgARAAgKKxctBgBPAgADAAkKEwuSsABvAQAHAAUKgBfXDwDLAAAAAA==.Vonbearback:BAAANQADCgIIAwAAAA==.Voxtek:BAAANQAECgEIAQAAAA==.',
Wa='Waterlance:BAAANQAECgEIAgAAAA==.',
Wh='Whatchashots:BAAANQADCggICAAAAA==.',
Wi='Wisecraic:BAAANQAECgQIBwAAAA==.',
Wo='Wocoxl:BAACNQAFFH8dAAMgAAgK8A8zAwA3AgAgAAcKYRIzAwA3AgABAAIKwAMgJQBFAAA1AAQKf0QAAwEACgqwH1wVAMUCAAEACgoCHlwVAMUCACAACQoFHQsXAGYBAAAA.',
Wu='Wutank:BAAANQADCgMIAwAAAA==.',
Xe='Xendamo:BAAANQADCggIEAAAAA==.',
Xo='Xoid:BAAANQAECggICgAAAA==.',
Ya='Yaracklea:BAAANQAECgQICQAAAA==.',
Yi='Yinokiea:BAAANQAECgMIBgAAAA==.',
Yo='Yomaaln:BAAANQAECgEIAQAAAA==.',
['Yü']='Yüki:BAAANQADCgYICAAAAA==.',
Za='Zabaniya:BAAANQAECgQIBAAAAA==.',
Ze='Zenedict:BAAANQAECgcIDwAAAA==.',
Zh='Zharsha:BAAANQADCggICAAAAA==.',
Zs='Zsofi:BAABNQAECn81AAIEAAoKMR7fJwDKAgAEAAoKMR7fJwDKAgAAAA==.',
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
