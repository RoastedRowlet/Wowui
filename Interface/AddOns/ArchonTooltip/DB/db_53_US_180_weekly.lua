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

local lookup = {'Rogue-Subtlety','Monk-Brewmaster','Warlock-Demonology','Priest-Holy','Warrior-Fury','Mage-Arcane','Warlock-Destruction','Druid-Restoration','Druid-Balance','Paladin-Holy','Paladin-Retribution','Priest-Shadow','Priest-Discipline','Paladin-Protection','Unknown-Unknown','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Unholy','Druid-Guardian','Hunter-BeastMastery','Monk-Mistweaver','Hunter-Survival','Monk-Windwalker','Warrior-Arms','Warrior-Protection','Evoker-Preservation','Shaman-Enhancement','Evoker-Augmentation','Hunter-Marksmanship','Druid-Feral','Mage-Frost','Rogue-Assassination','Shaman-Elemental','Shaman-Restoration','DemonHunter-Vengeance','DeathKnight-Frost',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Acid:BAACNQAFFH8JAAIBAAYK3gbODwANAQABAAYK3gbODwANAQA1AAQKfzoAAgEACgp8GJwNAJwCAAEACgp8GJwNAJwCAAAA.',
Ae='Aela:BAAANQAECgEIAQABNQAFFAYICQACANYWAA==.Aelin:BAAANQAECgUIBwAAAA==.',
Af='Affliction:BAAANQADCgEIAQAAAA==.',
Al='Alanispally:BAAANQADCgcICwAAAA==.Alkanz:BAABNQAECn8mAAIDAAoKFAw0WwDDAQADAAoKFAw0WwDDAQAAAA==.Allinaa:BAAANQAECggICgAAAA==.Alya:BAABNQAECn9NAAIEAAoKGB0mIQDXAgAEAAoKGB0mIQDXAgAAAA==.',
Am='Amelvia:BAAANQADCgMIAwAAAA==.',
An='Anika:BAABNQAECn8lAAIFAAoK3wkuEQCSAQAFAAoK3wkuEQCSAQAAAA==.Anshi:BAAANQAECgUIBgABNQAECgkJLQAGAMoYAA==.',
Ar='Archspìre:BAAANQAECgEIAQAAAA==.Arise:BAAANQADCgIIAgAAAA==.Arlyx:BAABNQAECn8tAAMDAAoKhCGyUADiAQADAAkKuSKyUADiAQAHAAUK0hZyJwA8AQAAAA==.Arnwaz:BAABNQAECn8VAAMIAAgKNhPBNQBuAQAIAAgKNhPBNQBuAQAJAAMKbQcCkACWAAAAAA==.Arthuria:BAABNQAECn8pAAMKAAoKtBJuegBGAQAKAAkK0xJuegBGAQALAAcK+A/RFwH4AAAAAA==.',
As='Ashzazul:BAAANQABCggIJgAAAA==.Ashzia:BAAANQABCgIIAgAAAA==.Asianverstop:BAABNQAECn8iAAQEAAoKbSFuRwBQAgAEAAkK1iBuRwBQAgAMAAkKmx9fEQBEAgANAAEKihwQFQBRAAAAAA==.',
At='Atelwen:BAAANQADCgYJBgAAAA==.',
Ba='Baf:BAABNQAECn8wAAILAAoK3yOFGABiAwALAAoK3yOFGABiAwAAAA==.Banano:BAAANQAECgIIAgAAAA==.Banjodave:BAAANQAECggIEAAAAA==.',
Be='Berfomat:BAABNQAECn8uAAIOAAoKDiDoBwAiAwAOAAoKDiDoBwAiAwAAAA==.Berfsteals:BAAANQADCgIIBAAAAA==.Berfy:BAAANQAECgMIAwAAAA==.',
Bj='Bjorn:BAAANQAECgYICQAAAA==.',
Bl='Black:BAAANQADCggIEAAAAA==.Blackky:BAAANQAECgQIBgAAAA==.Bloodyfupa:BAAANQADCgEIAQAAAA==.Bloomyvfd:BAABNQAECn8rAAIKAAoKARuwEgAlAwAKAAoKARuwEgAlAwAAAA==.',
Bo='Bocc:BAAANQADCgQIBQABNQAECgcIEAAPAAAAAA==.Boxxylove:BAAANQADCggIGgABNQAECgoKTQAEABgdAA==.',
Br='Brockz:BAAANQADCgQIBwAAAA==.',
Bu='Bulldan:BAAANQABCgIIAQAAAA==.',
['Bî']='Bîa:BAABNQAECn9LAAILAAoKpyOlKgAdAwALAAoKpyOlKgAdAwAAAA==.',
Ca='Cavalis:BAABNQAECn86AAQHAAoKdhYOFAC5AAADAAgKBBEhggDhAQAQAAYKQRX6FgDPAAAHAAUKXxcOFAC5AAAAAA==.',
Ce='Ceedk:BAACNQAFFH8JAAIRAAUKIyGqDACKAQARAAUKIyGqDACKAQA1AAQKfyEAAxIACQrIJsERACkDABIACQrIJsERACkDABEABwrYIbgsAGQCAAE1AAUUCAgYAAkACh0A.Ceesh:BAAANQAECggIBwABNQAFFAgIGAAJAAodAA==.',
Ch='Cherradan:BAAANQADCggICQAAAA==.Chickenparm:BAAANQAECgIIAgAAAA==.Chll:BAAANQAECgIIAgABNQAFFAcIEwASAHIdAA==.',
Cj='Cjjackpot:BAAANQADCgYJCwAAAA==.',
Co='Cobb:BAAANQAECgcIEAAAAA==.Coorsbanquet:BAAANQADCgMIAwAAAA==.',
Cr='Creativezd:BAACNQAFFH8YAAMJAAgKCh3pAwB6AgAJAAgKMxrpAwB6AgATAAUKXSIsAQDrAQA1AAQKfyUAAxMACQpSI4sRAB8CABMACAr2IosRAB8CAAkABgpjISEmAMsBAAAA.Crowley:BAAANQAECgMICgAAAA==.',
Da='Dadgoo:BAAANQAECgYICgAAAA==.Damnskippy:BAAANQAECgcICgAAAA==.Dannÿ:BAABNQAECn8lAAQEAAgK8B5QRQAjAgAEAAgK8B5QRQAjAgAMAAUK2hCVQwAYAQANAAMKRAshGwCPAAAAAA==.Darkire:BAABNQAECn8fAAIUAAoK6BRNVAAjAgAUAAoK6BRNVAAjAgAAAA==.',
De='Deathlegion:BAAANQADCgUICAAAAA==.Deathroll:BAABNQAECn8sAAIVAAoKphPXFAAuAgAVAAoKphPXFAAuAgAAAA==.Deaux:BAAANQAECggICwAAAA==.Demosucc:BAACNQAFFH8aAAMDAAcKKxvFDQBNAQADAAYKTRzFDQBNAQAHAAEKphZDGQBSAAA1AAQKfyQABAMACgo5Ix8hAAADAAMACQrnIx8hAAADABAABwpQFRIKAKsBAAcAAQp3HuxtAEMAAAAA.Dethandra:BAAANQADCggICAAAAA==.',
Di='Diabolic:BAAANQAECgUIBQAAAA==.',
Dk='Dkchilly:BAACNQAFFH8TAAISAAcKch22AQC8AQASAAcKch22AQC8AQA1AAQKfzIAAhIACgrEIlUgAMkCABIACgrEIlUgAMkCAAAA.',
Do='Doomward:BAAANQAECggIDwAAAA==.Dorien:BAABNQAECn8pAAMWAAkKnRr6AgDxAgAWAAkKXBj6AgDxAgAUAAgKFxp2YABWAgAAAA==.',
Dw='Dwish:BAAANQAECggIAQAAAA==.',
['Då']='Dårk:BAAANQADCgEIAQABNQABCgIIAgAPAAAAAA==.',
El='Elysele:BAAANQADCgUIBQABNQAECgoKPgAEAPoSAA==.',
Er='Erale:BAAANQAECgcIDQAAAA==.',
Fa='Faewryn:BAABNQAECn8oAAIKAAoK3Ri4OAA3AgAKAAoK3Ri4OAA3AgAAAA==.Falekia:BAAANQAECgcICgAAAA==.Falnaz:BAAANQAECgIIAwAAAA==.Fay:BAACNQAFFH8JAAICAAYK1hbkAwAiAQACAAYK1hbkAwAiAQA1AAQKfzkAAwIACgqaIuEDAEgDAAIACgqaIuEDAEgDABcAAQqSBwJhACwAAAAA.',
Fe='Fellus:BAAANQADCgIIAgAAAA==.Fengmeng:BAAANQADCggIEwAAAA==.',
Fi='Fishnchimps:BAAANQAECggIDAAAAA==.',
Fr='Freezah:BAAANQAECgUIBgAAAA==.Frogz:BAAANQADCgYIBgAAAA==.Fríeren:BAAANQAECgYIEAAAAA==.',
Fu='Fupalicious:BAAANQAECgUIEQABNQAECgYIHAARAHIVAA==.Furrburger:BAAANQAECgMIAwAAAA==.',
Ga='Gaiserik:BAABNQAECn8ZAAQYAAkKOBMnfwAdAgAYAAgKbRUnfwAdAgAFAAEKUg7hMQA5AAAZAAEKnwQ4SgAoAAAAAA==.Galad:BAAANQAECggICwAAAA==.Garlictoast:BAAANQADCgYJBgAAAA==.',
Gi='Gillgamesh:BAAANQAECgcICwAAAA==.',
Go='Goochegg:BAAANQADCgUIBQAAAA==.',
Gr='Gragolf:BAAANQAECggIDAAAAA==.Greggor:BAAANQAECgUICAAAAA==.Griffin:BAAANQADCggIDgAAAA==.Grippyfupa:BAAANQAECgQIBwAAAA==.',
Gu='Gulzerak:BAABNQAECn8aAAMDAAoKOiE+WADLAQADAAgKHCA+WADLAQAHAAIKlCRNPgDJAAABNQAFFAYIFgAaACohAA==.Gustabo:BAAANQADCgIIAgAAAA==.',
Ha='Harby:BAAANQAECgMIAwAAAA==.Harnatauren:BAAANQADCggIJwAAAA==.Hawtynaughty:BAAANQADCgYIBgAAAA==.',
He='Helcular:BAABNQAECn8UAAIHAAcKXgSJLgARAQAHAAcKXgSJLgARAQAAAA==.Hexuz:BAABNQAECn8tAAIbAAoKQxKxDgB/AgAbAAoKQxKxDgB/AgAAAA==.',
Hi='Hittu:BAABNQAECn8bAAIYAAoK3QWSxADrAAAYAAoK3QWSxADrAAAAAA==.',
Ho='Holyblunt:BAACNQAFFH8PAAILAAYKoBzgCgA6AQALAAYKoBzgCgA6AQA1AAQKfzQAAgsACgq/JegQAIUDAAsACgq/JegQAIUDAAAA.',
Id='Idk:BAAANQAECgcIEQAAAA==.',
Ik='Ikisscutemen:BAABNQAECn8jAAMaAAkK2hcGCwB9AgAaAAkK2hcGCwB9AgAcAAcK2xjTBwAmAgABNQAECgoKIgAEAG0hAA==.',
In='Inthezone:BAABNQAECn8YAAMUAAcKxBL1kADnAQAUAAcKxBL1kADnAQAdAAUKEAZJUwDaAAAAAA==.Invisus:BAABNQAECn8nAAIFAAkKCByIBQB9AgAFAAkKCByIBQB9AgAAAA==.',
Is='Ispayders:BAAANQAECgEIAQAAAA==.',
Ja='Jarlan:BAACNQAFFH8FAAIYAAMKkhZZJADcAAAYAAMKkhZZJADcAAA1AAQKfyoAAhgACQrNIWAyAPYCABgACQrNIWAyAPYCAAAA.Jarlhun:BAAANQADCggIEgABNQAFFAMIBQAYAJIWAA==.Jarmon:BAABNQAECn8ZAAIXAAYK4x8JJAAFAgAXAAYK4x8JJAAFAgABNQAFFAMIBQAYAJIWAA==.',
Jo='Joolian:BAACNQAFFH8GAAIeAAQKwxtVAQD/AAAeAAQKwxtVAQD/AAA1AAQKfywABB4ACgq8JdAAAHkDAB4ACgq8JdAAAHkDAAkAAgoiGMOhAFkAAAgAAQoGGf9vAEUAAAE1AAUUCAgcAB8ACxYA.Joolianr:BAABNQAECn8ZAAMgAAgKcxWCJwD5AAABAAgKdRQSWQCjAQAgAAUKkhSCJwD5AAABNQAFFAgIHAAfAAsWAA==.',
Ju='Justin:BAABNQAECn8vAAIRAAoKZhiELQBgAgARAAoKZhiELQBgAgAAAA==.',
Ka='Kaiveza:BAAANQAECgYICwABNQAFFAgIFQADAL0cAA==.Katara:BAAANQADCggICQAAAA==.Kattsumoto:BAACNQAFFH8NAAMVAAYKcBeFAwDCAQAVAAYKcBeFAwDCAQAXAAEKBQjGFAAzAAA1AAQKfzgAAxUACgq+IkUFAE0DABUACgq+IkUFAE0DABcABgrrEwxGAOwAAAAA.',
Ke='Ketharion:BAABNQAECn8+AAMKAAoKaBdBOgAwAgAKAAoKaBdBOgAwAgALAAUKgAmRFgH6AAAAAA==.',
Kh='Khato:BAAANQAECgMICAAAAA==.',
Ku='Kurazan:BAACNQAFFH8XAAIYAAcKmBvWCgCpAQAYAAcKmBvWCgCpAQA1AAQKfzYAAhgACgoNI55CAMICABgACgoNI55CAMICAAAA.Kurisu:BAABNQAECn8fAAIDAAcK4w2k2wASAQADAAcK4w2k2wASAQAAAA==.',
La='Lafaymignon:BAAANQABCgIIAgAAAA==.Lanfear:BAAANQAECgMIAwAAAA==.Lavabolter:BAAANQAECgEIAQAAAA==.Laîlyne:BAABNQAECn8xAAMhAAoK0BYYLQAnAgAhAAoK0BYYLQAnAgAiAAIKagUg6wBHAAAAAA==.',
Le='Leo:BAAANQAECgcICwAAAA==.Leone:BAAANQAECgYIDwAAAA==.',
Li='Lilany:BAAANQADCgEIAQAAAA==.Lilath:BAAANQAECgEIAQAAAA==.',
Lo='Logical:BAABNQAECn9FAAILAAoKzR2MLwCkAgALAAoKzR2MLwCkAgAAAA==.',
Lu='Lucit:BAAANQAECgMIAgABNQAECgoKLQADAIQhAA==.Lute:BAABNQAECn8mAAIRAAgK8BxeIQCpAgARAAgK8BxeIQCpAgAAAA==.',
['Lá']='Lárien:BAAANQAECgQIBgAAAA==.',
Ma='Manon:BAACNQAFFH8IAAIiAAUKRAyTEgA3AQAiAAUKRAyTEgA3AQA1AAQKfzAAAyIACgpaD+FiAOUBACIACgpaD+FiAOUBACEACQrLBi+YAGgBAAAA.Maxacry:BAAANQADCgIIAgAAAA==.Maxstoke:BAAANQAECggIDQAAAA==.',
Mc='Mcchungus:BAABNQAECn8XAAIUAAoKPw9vYAAGAgAUAAoKPw9vYAAGAgAAAA==.',
Me='Meowmixx:BAAANQAECgEIAQAAAA==.',
Mi='Mischief:BAAANQADCgYICwAAAA==.',
Mo='Morewyn:BAAANQAECgEIAQAAAA==.Mortred:BAAANQAECgEIAQAAAA==.',
Mt='Mtd:BAAANQAECgYIBwABNQAECgoKQgAWADoeAA==.Mth:BAABNQAECn8dAAMWAAgKqhliBgA2AgAWAAgKqhliBgA2AgAdAAUKigrrTAD+AAABNQAECgoKQgAWADoeAA==.',
Na='Nadok:BAAANQAECggIDgAAAA==.Nancyy:BAAANQABCgIIAgAAAA==.Naz:BAAANQAECgIIAgAAAA==.',
Ni='Nickignomaj:BAAANQAECgUIBQABNQAECgoKNAAYAPkdAA==.Nisara:BAAANQAECgMIAwAAAA==.',
No='Norina:BAAANQADCgYICwAAAA==.',
Ob='Obv:BAABNQAECn8ZAAIjAAkKjBgICwAjAgAjAAkKjBgICwAjAgAAAA==.',
Om='Omantul:BAABNQAECn8dAAIiAAgKERdHXAD6AQAiAAgKERdHXAD6AQAAAA==.',
Oo='Oobie:BAAANQADCgYIBgAAAA==.',
Ow='Owocoxl:BAAANQAECgcIDwABNQAFFAgIHQAgAPAPAA==.',
Oz='Ozziee:BAAANQAECgMIBQAAAA==.Ozzthehunter:BAAANQADCgIIAgAAAA==.',
Pa='Pants:BAAANQADCggIGgAAAA==.Paroguei:BAAANQAECgYIDAABNQAECgoKLgAKAPwiAA==.',
Ph='Phakes:BAABNQAECn8VAAIdAAgKTAocJQBAAQAdAAgKTAocJQBAAQAAAA==.Phengzera:BAAANQAECgMIAwAAAA==.Phizz:BAAANQADCggICgABNQAFFAgIJAAGADEeAA==.',
Pl='Pllwprincess:BAAANQADCgIIAgAAAA==.',
Po='Pocky:BAAANQAECgQIBAAAAA==.Poofty:BAAANQADCgUIBQAAAA==.',
Pr='Predator:BAACNQAFFH8dAAIYAAgKdCZ+AQD+AgAYAAgKdCZ+AQD+AgA1AAQKf0gAAhgACgrYJtgBAIgDABgACgrYJtgBAIgDAAAA.Prolove:BAAANQAECgIIAQAAAA==.',
Pu='Puke:BAABNQAECn8gAAIjAAgKriTpAgBGAwAjAAgKriTpAgBGAwAAAA==.Purpledisco:BAAANQADCggICAABNQAECgoKTQAEABgdAA==.Purplepower:BAABNQAECn8iAAIYAAgKoRlTdAA4AgAYAAgKoRlTdAA4AgAAAA==.',
Pw='Pwincess:BAAANQAECgQIBAAAAA==.',
Qw='Qwelmo:BAAANQADCgEJAgAAAA==.',
Ri='Rigaud:BAAANQADCgMIAwAAAA==.',
Ro='Roaka:BAAANQABCgIIAgAAAA==.Rolypoly:BAAANQAECgUIBQAAAA==.',
Ry='Ryø:BAABNQAECn8mAAMTAAoKahZXGwDJAQATAAoK9BRXGwDJAQAeAAQK1wsRLwCZAAAAAA==.',
Se='Seigler:BAABNQAECn8zAAIWAAoKqAuzCAC+AQAWAAoKqAuzCAC+AQAAAA==.Senne:BAAANQAECgQIBgAAAA==.Seraphym:BAAANQAECgUIBwAAAA==.',
Sh='Shaviji:BAAANQAECggICQAAAA==.Shigzen:BAAANQAECgIIAwABNQADCggICQAPAAAAAA==.Shore:BAABNQAECn9CAAMWAAoKOh5IAQBoAwAWAAoKOh5IAQBoAwAdAAMK5A27YgCeAAAAAA==.Shuralya:BAABNQAECn9dAAILAAoKgSPdFQBtAwALAAoKgSPdFQBtAwAAAA==.',
Sk='Skoob:BAAANQAECgMIAgAAAA==.',
So='Sonofabirch:BAAANQADCgMIAwAAAA==.',
Sp='Spokelse:BAABNQAECn8pAAIkAAgKyQT/YwATAQAkAAgKyQT/YwATAQAAAA==.',
St='Stirling:BAAANQADCgUIBQABNQADCgYIDQAPAAAAAA==.Striga:BAAANQABCgEIAQAAAA==.',
Su='Sully:BAAANQADCggIDgAAAA==.Survas:BAACNQAFFH8FAAIBAAIK8AetKQA4AAABAAIK8AetKQA4AAA1AAQKfysAAgEACgrxEkgTAFECAAEACgrxEkgTAFECAAAA.',
Ta='Tavgoesboom:BAAANQAECgQIBQABNQAECggIDAAPAAAAAA==.',
Te='Terrin:BAABNQAECn8eAAIYAAoKFxaFdACmAQAYAAoKFxaFdACmAQAAAA==.Texmexdruid:BAAANQADCggIDgAAAA==.',
Th='Tharkun:BAABNQAECn8YAAIGAAcKthropgA0AgAGAAcKthropgA0AgAAAA==.Thedagda:BAAANQAECgQIAwAAAA==.Thunderlinkx:BAAANQAECgEIAQABNQAECgcIDQAPAAAAAA==.',
Ti='Titlecard:BAAANQAECgEIAgAAAA==.',
To='Tora:BAAANQAFFAEIAQAAAA==.',
Tr='Triage:BAABNQAECn8eAAIGAAkKBxkMlgBUAgAGAAkKBxkMlgBUAgAAAA==.',
Ts='Tsu:BAEBNQAECn8VAAILAAgK9QflzQA7AQALAAgK9QflzQA7AQAAAA==.Tsuko:BAEANQAECgIIAgABNQAECggIFQALAPUHAA==.',
Tu='Tul:BAABNQAECn8hAAIKAAoKXh4XHgDMAgAKAAoKXh4XHgDMAgAAAA==.',
Tw='Twotoedfupa:BAABNQAECn8cAAIRAAYKchWuYwBjAQARAAYKchWuYwBjAQAAAA==.',
Ty='Tyrias:BAABNQAECn8eAAILAAkKkAVygQFXAAALAAkKkAVygQFXAAAAAA==.',
Ug='Ugin:BAABNQAECn8eAAMSAAoKsQtaVADAAQASAAoKhwtaVADAAQAkAAMKJAqvhwCTAAAAAA==.',
Um='Umbrasyl:BAAANQAECgMIAwAAAA==.',
Un='Unclecharlie:BAAANQAECgUIBQABNQAFFAUIBgAkAMQbAA==.Undeadrogue:BAAANQADCgQIBAAAAA==.',
Va='Vasrin:BAABNQAECn8wAAIbAAoKEiJQBgAhAwAbAAoKEiJQBgAhAwAAAA==.',
Vo='Voidomo:BAABNQAECn9AAAQQAAoKOBctBgBPAgAQAAgKKxctBgBPAgADAAkKEwuSsABvAQAHAAUKgBdREQDKAAAAAA==.Vonbearback:BAAANQADCgIIAwAAAA==.',
Wa='Waterlance:BAAANQAECgEIAQAAAA==.',
Wh='Whatchashots:BAAANQADCggICAAAAA==.',
Wi='Wisecraic:BAAANQAECgUICQAAAA==.',
Wo='Wocoxl:BAACNQAFFH8dAAMgAAgK8A8zAwA3AgAgAAcKYRIzAwA3AgABAAIKwAM2KABFAAA1AAQKf0QAAwEACgqwH2YXAMICAAEACgoCHmYXAMICACAACQoFHUkkAGYCAAAA.',
Wu='Wutank:BAAANQADCgMIAwAAAA==.',
Xe='Xendamo:BAAANQADCggIEAAAAA==.',
Xo='Xoid:BAAANQAECggICQAAAA==.',
Ya='Yaracklea:BAAANQAECgQICQAAAA==.',
Yi='Yinokiea:BAAANQAECgMIBgAAAA==.',
Yo='Yomaaln:BAAANQABCgQIBAAAAA==.',
['Yü']='Yüki:BAAANQADCgYICQAAAA==.',
Za='Zabaniya:BAAANQAECgQIBAAAAA==.',
Ze='Zenedict:BAAANQAECgcIDwAAAA==.',
Zh='Zharsha:BAAANQADCggICQAAAA==.',
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
