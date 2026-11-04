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

local lookup = {'Monk-Brewmaster','Warlock-Demonology','Priest-Holy','Warrior-Fury','Mage-Arcane','Warlock-Destruction','Druid-Restoration','Druid-Balance','Paladin-Holy','Paladin-Retribution','Priest-Shadow','Priest-Discipline','Paladin-Protection','Unknown-Unknown','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Unholy','Druid-Guardian','Hunter-BeastMastery','Monk-Mistweaver','Hunter-Survival','Warrior-Arms','Warrior-Protection','Evoker-Preservation','Shaman-Enhancement','Evoker-Augmentation','Hunter-Marksmanship','Monk-Windwalker','Druid-Feral','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Shaman-Restoration','DemonHunter-Vengeance','DeathKnight-Frost',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=53,date='2026-11-03',data={Ae='Aela:BAAANQAECgEIAQABNQAFFAQIBwABALUTAA==.Aelin:BAAANQAECgQIBwAAAA==.',
Af='Affliction:BAAANQADCgEIAQAAAA==.',
Al='Alanispally:BAAANQADCgcICwAAAA==.Alkanz:BAABNQAECn8iAAICAAoKngq9VgCWAQACAAoKngq9VgCWAQAAAA==.Allinaa:BAAANQAECggICgAAAA==.Alya:BAABNQAECn88AAIDAAoK4BmbLQCyAgADAAoK4BmbLQCyAgAAAA==.',
An='Anika:BAABNQAECn8lAAIEAAoK3wkuEQCSAQAEAAoK3wkuEQCSAQAAAA==.Anshi:BAAANQAECgQIBAABNQAECgkJJwAFAHQWAA==.',
Ar='Archspìre:BAAANQAECgEIAQAAAA==.Arise:BAAANQADCgIIAgAAAA==.Arlyx:BAABNQAECn8qAAMCAAoKpB8yXQBAAgACAAgKvyIyXQBAAgAGAAUK0hZyJwA8AQAAAA==.Arnwaz:BAABNQAECn8VAAMHAAgKNhPBNQBuAQAHAAgKNhPBNQBuAQAIAAMKbQcCkACWAAAAAA==.Arthuria:BAABNQAECn8fAAMJAAkKxBIXrAAoAQAJAAgK6RIXrAAoAQAKAAcK+A/RFwH4AAAAAA==.',
As='Ashzazul:BAAANQABCggIJAAAAA==.Ashzia:BAAANQABCgIIAgAAAA==.Asianverstop:BAABNQAECn8eAAQDAAoKbSFuRwBQAgADAAkK1iBuRwBQAgALAAgKCB/iEwDkAQAMAAEKihyFEQBSAAAAAA==.',
At='Atelwen:BAAANQADCgYJBgAAAA==.',
Ba='Baf:BAABNQAECn8vAAIKAAoKlyOFGABiAwAKAAoKlyOFGABiAwAAAA==.Banano:BAAANQAECgIIAgAAAA==.Banjodave:BAAANQAECggIEAAAAA==.',
Be='Berfomat:BAABNQAECn8uAAINAAoKDiDoBwAiAwANAAoKDiDoBwAiAwAAAA==.Berfsteals:BAAANQADCgIIBAAAAA==.Berfy:BAAANQAECgMIAwAAAA==.',
Bj='Bjorn:BAAANQAECgYICQAAAA==.',
Bl='Black:BAAANQADCggIEAAAAA==.Blackky:BAAANQAECgQIBgAAAA==.Bloodyfupa:BAAANQADCgEIAQAAAA==.Bloomyvfd:BAABNQAECn8iAAIJAAcK/x2BJgBmAgAJAAcK/x2BJgBmAgAAAA==.',
Bo='Bocc:BAAANQADCgQIBQABNQAECgcIEAAOAAAAAA==.Boombip:BAAANQABCgMIAwAAAA==.Boxxylove:BAAANQADCggIGgABNQAECgoKPAADAOAZAA==.',
Br='Brockz:BAAANQADCgQIBwAAAA==.',
Bu='Bulldan:BAAANQABCgIIAQAAAA==.',
['Bî']='Bîa:BAABNQAECn9CAAIKAAoKAyKlKgAdAwAKAAoKAyKlKgAdAwAAAA==.',
Ca='Cavalis:BAABNQAECn86AAQGAAoKdhYAEAC8AAACAAgKBBEhggDhAQAPAAYKQRUBEQDZAAAGAAUKXxcAEAC8AAAAAA==.',
Ce='Ceedk:BAACNQAFFH8JAAIQAAUKIyGqDACKAQAQAAUKIyGqDACKAQA1AAQKfyEAAxEACQrIJsERACkDABEACQrIJsERACkDABAABwrYIbgsAGQCAAE1AAUUCAgYAAgACh0A.Ceesh:BAAANQAECggIBwABNQAFFAgIGAAIAAodAA==.',
Ch='Cherradan:BAAANQADCggICAAAAA==.Chickenparm:BAAANQAECgIIAgAAAA==.Chll:BAAANQAECgIIAgABNQAFFAYIEgARAAYeAA==.',
Cj='Cjjackpot:BAAANQADCgYJCwAAAA==.',
Co='Cobb:BAAANQAECgcIEAAAAA==.Coorsbanquet:BAAANQADCgMIAwAAAA==.',
Cr='Creativezd:BAACNQAFFH8YAAMIAAgKCh3pAwB6AgAIAAgKMxrpAwB6AgASAAUKXSIsAQDrAQA1AAQKfyEAAxIACQqJIqsOABICABIACAoRIqsOABICAAgABgpjIVAfANABAAAA.Crowley:BAAANQAECgMICgAAAA==.',
Da='Dadgoo:BAAANQAECgYICgAAAA==.Damnskippy:BAAANQAECgUICQAAAA==.Dannÿ:BAABNQAECn8kAAQDAAgK8B7INAA2AgADAAgK8B7INAA2AgALAAUK2hCVQwAYAQAMAAMKRAshGwCPAAAAAA==.Darkire:BAABNQAECn8fAAITAAoK6BRmQAAdAgATAAoK6BRmQAAdAgAAAA==.',
De='Deathlegion:BAAANQADCgUIBQAAAA==.Deathroll:BAABNQAECn8sAAIUAAoKphPXFAAuAgAUAAoKphPXFAAuAgAAAA==.Deaux:BAAANQAECggICwAAAA==.Demosucc:BAACNQAFFH8aAAMCAAcKKxuLCABWAQACAAYKTRyLCABWAQAGAAEKphZDGQBSAAA1AAQKfyMABAIACgo5Ix8hAAADAAIACQrnIx8hAAADAA8ABgq5FF4JAHABAAYAAQp3HuxtAEMAAAAA.Dethandra:BAAANQADCggICAAAAA==.',
Di='Diabolic:BAAANQAECgUIBQAAAA==.',
Dk='Dkchilly:BAACNQAFFH8SAAIRAAYKBh7iAQBvAQARAAYKBh7iAQBvAQA1AAQKfzAAAhEACgrEIlUgAMkCABEACgrEIlUgAMkCAAAA.',
Do='Doomward:BAAANQAECgYIDQAAAA==.Dorien:BAABNQAECn8pAAMVAAkKnRr6AgDxAgAVAAkKXBj6AgDxAgATAAgKFxp2YABWAgAAAA==.',
['Då']='Dårk:BAAANQADCgEIAQABNQABCgIIAgAOAAAAAA==.',
El='Elysele:BAAANQADCgUIBQABNQAECgoKPgADAPoSAA==.',
Er='Erale:BAAANQAECgcIDQAAAA==.',
Fa='Faewryn:BAABNQAECn8kAAIJAAoKXBijLABBAgAJAAoKXBijLABBAgAAAA==.Falekia:BAAANQAECgcICgAAAA==.Falnaz:BAAANQAECgIIAwAAAA==.Fay:BAACNQAFFH8HAAIBAAQKtRMtBADUAAABAAQKtRMtBADUAAA1AAQKfzcAAgEACgp4IuEDAEgDAAEACgp4IuEDAEgDAAAA.',
Fe='Fellus:BAAANQADCgIIAgAAAA==.Fengmeng:BAAANQADCggIEwAAAA==.',
Fi='Fishnchimps:BAAANQAECggIDAAAAA==.',
Fr='Freezah:BAAANQAECgUIBgAAAA==.Frogz:BAAANQADCgYIBgAAAA==.Fríeren:BAAANQAECgYIEAAAAA==.',
Fu='Fupalicious:BAAANQAECgUIEQABNQAECgYIHAAQAHIVAA==.Furrburger:BAAANQAECgMIAwAAAA==.',
Ga='Gaiserik:BAABNQAECn8ZAAQWAAkKOBMnfwAdAgAWAAgKbRUnfwAdAgAEAAEKUg7hMQA5AAAXAAEKnwRcPwAoAAAAAA==.Galad:BAAANQAECggICwAAAA==.Garlictoast:BAAANQADCgYJBgAAAA==.',
Gi='Gillgamesh:BAAANQAECgcICwAAAA==.',
Go='Goochegg:BAAANQADCgUIBQAAAA==.',
Gr='Gragolf:BAAANQAECggIDAAAAA==.Greggor:BAAANQAECgUICAAAAA==.Griffin:BAAANQADCggIDgAAAA==.Grippyfupa:BAAANQAECgQIBwAAAA==.',
Gu='Gulzerak:BAABNQAECn8aAAMCAAoKOiHkRADRAQACAAgKHCDkRADRAQAGAAIKlCRNPgDJAAABNQAFFAYIFgAYACohAA==.Gustabo:BAAANQADCgIIAgAAAA==.',
Ha='Harnatauren:BAAANQADCggIFgAAAA==.Hawtynaughty:BAAANQADCgYIBgAAAA==.',
He='Helcular:BAAANQAECgYIDAAAAA==.Hexuz:BAABNQAECn8pAAIZAAoKExKxDgB/AgAZAAoKExKxDgB/AgAAAA==.',
Hi='Hittu:BAAANQAECggIBQAAAA==.',
Ho='Holyblunt:BAACNQAFFH8OAAIKAAUKcxv2DwDgAAAKAAUKcxv2DwDgAAA1AAQKfzEAAgoACgoDJegQAIUDAAoACgoDJegQAIUDAAAA.',
Id='Idk:BAAANQAECgcIEQAAAA==.',
Ik='Ikisscutemen:BAABNQAECn8cAAMaAAkKDBjTBwAmAgAaAAcK2xjTBwAmAgAYAAkKpxKMDAAaAgABNQAECgoKHgADAG0hAA==.',
In='Inthezone:BAABNQAECn8YAAMTAAcKxBL1kADnAQATAAcKxBL1kADnAQAbAAUKEAZJUwDaAAAAAA==.Invisus:BAABNQAECn8iAAIEAAkKNBuVBABuAgAEAAkKNBuVBABuAgAAAA==.',
Is='Ispayders:BAAANQAECgEIAQAAAA==.',
Ja='Jarlan:BAACNQAFFH8FAAIWAAMKkhZZJADcAAAWAAMKkhZZJADcAAA1AAQKfyoAAhYACQrNIWAyAPYCABYACQrNIWAyAPYCAAAA.Jarlhun:BAAANQADCggIEgABNQAFFAMIBQAWAJIWAA==.Jarmon:BAABNQAECn8ZAAIcAAYK4x8JJAAFAgAcAAYK4x8JJAAFAgABNQAFFAMIBQAWAJIWAA==.',
Jo='Joolian:BAACNQAFFH8FAAIdAAQKwxvaAQC0AAAdAAQKwxvaAQC0AAA1AAQKfyAABB0ACgoAJFoBAEwDAB0ACQoAJFoBAEwDAAgAAgoiGMOhAFkAAAcAAQoGGf9vAEUAAAE1AAUUBwgaAB4AbxQA.Joolianr:BAABNQAECn8UAAMfAAcKvxQ2RQCgAQAfAAcKdRQ2RQCgAQAgAAMKFxRDPwB/AAABNQAFFAcIGgAeAG8UAA==.',
Ju='Justin:BAABNQAECn8vAAIQAAoKZhiELQBgAgAQAAoKZhiELQBgAgAAAA==.',
Ka='Kaiveza:BAAANQAECgIIAgABNQAFFAcIFAACADMgAA==.Katara:BAAANQADCggICAAAAA==.Kattsumoto:BAACNQAFFH8NAAMUAAYKcBdGAgDSAQAUAAYKcBdGAgDSAQAcAAEKBQiZEQA2AAA1AAQKfzUAAxQACgq5IkUFAE0DABQACgq5IkUFAE0DABwABgrrEwxGAOwAAAAA.',
Ke='Ketharion:BAABNQAECn86AAMJAAoKaBcdLABEAgAJAAoKaBcdLABEAgAKAAUKgAmRFgH6AAAAAA==.',
Kh='Khato:BAAANQAECgMICAAAAA==.',
Ku='Kurazan:BAACNQAFFH8WAAIWAAYKsRm+CgBMAQAWAAYKsRm+CgBMAQA1AAQKfzEAAhYACgoBI55CAMICABYACgoBI55CAMICAAAA.Kurisu:BAABNQAECn8fAAICAAcK4w2k2wASAQACAAcK4w2k2wASAQAAAA==.',
La='Lafaymignon:BAAANQABCgIIAgAAAA==.Lanfear:BAAANQAECgMIAwAAAA==.Lavabolter:BAAANQAECgEIAQAAAA==.Laîlyne:BAABNQAECn8nAAMhAAoKWBR4KQAFAgAhAAoKWBR4KQAFAgAiAAIKagWc0gBKAAAAAA==.',
Le='Leo:BAAANQAECgcICwAAAA==.Leone:BAAANQAECgYIDwAAAA==.',
Li='Lilany:BAAANQABCgIIAgAAAA==.Lilath:BAAANQAECgEIAQAAAA==.',
Lo='Logical:BAABNQAECn8xAAIKAAoKzBo0SAAdAgAKAAoKzBo0SAAdAgAAAA==.',
Lu='Lucit:BAAANQAECgIIAgABNQAECgoKKgACAKQfAA==.Lute:BAABNQAECn8mAAIQAAgK8BxeIQCpAgAQAAgK8BxeIQCpAgAAAA==.',
['Lá']='Lárien:BAAANQAECgQIBgAAAA==.',
Ma='Manon:BAACNQAFFH8GAAIiAAMKLRBmFgC/AAAiAAMKLRBmFgC/AAA1AAQKfy8AAyIACgo3D+FiAOUBACIACgo3D+FiAOUBACEACQrLBi+YAGgBAAAA.Maxacry:BAAANQADCgIIAgAAAA==.Maxstoke:BAAANQAECggIDQAAAA==.',
Mc='Mcchungus:BAAANQAECggIEwAAAA==.',
Me='Meowmixx:BAAANQAECgEIAQAAAA==.',
Mi='Mischief:BAAANQADCgYICwAAAA==.',
Mo='Morewyn:BAAANQAECgEIAQAAAA==.Mortred:BAAANQAECgEIAQAAAA==.',
Mt='Mtd:BAAANQAECgYIBwABNQAECgoKQgAVADoeAA==.Mth:BAABNQAECn8dAAMVAAgKqhliBgA2AgAVAAgKqhliBgA2AgAbAAUKigrrTAD+AAABNQAECgoKQgAVADoeAA==.',
Na='Nadok:BAAANQAECggIDgAAAA==.Nancyy:BAAANQABCgIIAgAAAA==.Naz:BAAANQAECgIIAgAAAA==.',
Ni='Nickignomaj:BAAANQAECgUIBQABNQAECgoKMAAWAPkdAA==.Nisara:BAAANQAECgMIAwAAAA==.',
No='Norina:BAAANQADCgYICwAAAA==.',
Ob='Obv:BAABNQAECn8ZAAIjAAkKjBgICwAjAgAjAAkKjBgICwAjAgAAAA==.',
Om='Omantul:BAABNQAECn8dAAIiAAgKERdHXAD6AQAiAAgKERdHXAD6AQAAAA==.',
Oo='Oobie:BAAANQADCgYIBgAAAA==.',
Ow='Owocoxl:BAAANQAECgYICwABNQAFFAgIHQAgAPAPAA==.',
Oz='Ozziee:BAAANQAECgMIBQAAAA==.Ozzthehunter:BAAANQADCgIIAgAAAA==.',
Pa='Pants:BAAANQADCggIGQAAAA==.Paroguei:BAAANQAECgYICwABNQAECgoKKwAJAMkiAA==.',
Ph='Phakes:BAAANQAECgYIEgAAAA==.Phengzera:BAAANQAECgMIAwAAAA==.Phizz:BAAANQADCggICgABNQAFFAgIJAAFADEeAA==.',
Pl='Pllwprincess:BAAANQADCgIIAgAAAA==.',
Po='Pocky:BAAANQAECgQIBAAAAA==.Poofty:BAAANQADCgUIBQAAAA==.',
Pr='Predator:BAACNQAFFH8dAAIWAAgKdCZ+AQD+AgAWAAgKdCZ+AQD+AgA1AAQKf0cAAhYACgrYJgIBAI8DABYACgrYJgIBAI8DAAAA.Prolove:BAAANQAECgIIAQAAAA==.',
Pu='Puke:BAABNQAECn8gAAIjAAgKriTpAgBGAwAjAAgKriTpAgBGAwAAAA==.Purpledisco:BAAANQADCggICAABNQAECgoKPAADAOAZAA==.Purplepower:BAABNQAECn8iAAIWAAgKoRlTdAA4AgAWAAgKoRlTdAA4AgAAAA==.',
Pw='Pwincess:BAAANQAECgQIBAAAAA==.',
Qw='Qwelmo:BAAANQADCgEJAgAAAA==.',
Ri='Rigaud:BAAANQADCgMIAwAAAA==.',
Ro='Roaka:BAAANQABCgIIAgAAAA==.Rolypoly:BAAANQAECgUIBQAAAA==.',
Ry='Ryø:BAABNQAECn8iAAISAAoK9BRXGwDJAQASAAoK9BRXGwDJAQAAAA==.',
Se='Seigler:BAABNQAECn8lAAIVAAkKDguzCAC+AQAVAAkKDguzCAC+AQAAAA==.Senne:BAAANQAECgQIBQAAAA==.Seraphym:BAAANQAECgIIAgAAAA==.',
Sh='Shaviji:BAAANQAECggICAAAAA==.Shigzen:BAAANQAECgIIAwABNQADCggICQAOAAAAAA==.Shore:BAABNQAECn9CAAMVAAoKOh5IAQBoAwAVAAoKOh5IAQBoAwAbAAMK5A27YgCeAAAAAA==.Shuralya:BAABNQAECn9TAAIKAAoKZSPdFQBtAwAKAAoKZSPdFQBtAwAAAA==.',
Sk='Skoob:BAAANQAECgMIAgAAAA==.',
So='Sonofabirch:BAAANQADCgMIAwAAAA==.',
St='Striga:BAAANQABCgEIAQAAAA==.',
Su='Sully:BAAANQADCggIDgAAAA==.Survas:BAABNQAECn8rAAIfAAoK8RJIEwBRAgAfAAoK8RJIEwBRAgAAAA==.',
Ta='Tavgoesboom:BAAANQAECgQIBQABNQAECggIDAAOAAAAAA==.',
Te='Terrin:BAABNQAECn8bAAIWAAkKhxb2gwARAgAWAAkKhxb2gwARAgAAAA==.Texmexdruid:BAAANQADCggIDgAAAA==.',
Th='Tharkun:BAABNQAECn8UAAIFAAcKthropgA0AgAFAAcKthropgA0AgAAAA==.Thedagda:BAAANQAECgMIAwAAAA==.Thunderlinkx:BAAANQAECgEIAQABNQAECgcIDQAOAAAAAA==.',
Ti='Titlecard:BAAANQAECgEIAgAAAA==.',
To='Tora:BAAANQAFFAEIAQAAAA==.',
Tr='Triage:BAABNQAECn8eAAIFAAkKBxkMlgBUAgAFAAkKBxkMlgBUAgAAAA==.',
Ts='Tsu:BAEANQAECgcIDQAAAA==.Tsuko:BAEANQAECgIIAgABNQAECgcIDQAOAAAAAA==.',
Tu='Tul:BAABNQAECn8gAAIJAAoKXh5lFQDhAgAJAAoKXh5lFQDhAgAAAA==.',
Tw='Twotoedfupa:BAABNQAECn8cAAIQAAYKchWuYwBjAQAQAAYKchWuYwBjAQAAAA==.',
Ty='Tyrias:BAABNQAECn8eAAIKAAkKkAVygQFXAAAKAAkKkAVygQFXAAAAAA==.',
Ug='Ugin:BAABNQAECn8eAAMRAAoKsQtaVADAAQARAAoKhwtaVADAAQAkAAMKJAqvhwCTAAAAAA==.',
Um='Umbrasyl:BAAANQAECgMIAwAAAA==.',
Un='Unclecharlie:BAAANQAECgQIBQABNQAECgoKMAARAIclAA==.Undeadrogue:BAAANQADCgQIBAAAAA==.',
Va='Vasrin:BAABNQAECn8wAAIZAAoKEiJQBgAhAwAZAAoKEiJQBgAhAwAAAA==.',
Vo='Voidomo:BAABNQAECn89AAQPAAoKLBUtBgBPAgAPAAgKKxctBgBPAgACAAkKEwuSsABvAQAGAAQKiBb8FwCCAAAAAA==.Vonbearback:BAAANQADCgIIAwAAAA==.',
Wa='Waterlance:BAAANQAECgEIAQAAAA==.',
Wh='Whatchashots:BAAANQADCggICAAAAA==.',
Wi='Wisecraic:BAAANQAECgEIAgAAAA==.',
Wo='Wocoxl:BAACNQAFFH8dAAMgAAgK8A8zAwA3AgAgAAcKYRIzAwA3AgAfAAIKwAMcIQBFAAA1AAQKfz4AAx8ACgoNH3EeAGkCAB8ACgrEGnEeAGkCACAACQoFHRgVAGoBAAAA.',
Wu='Wutank:BAAANQADCgMIAwAAAA==.',
Xe='Xendamo:BAAANQADCggIEAAAAA==.',
Xo='Xoid:BAAANQAECgYIBgAAAA==.',
Ya='Yaracklea:BAAANQAECgQICQAAAA==.',
Yi='Yinokiea:BAAANQAECgMIBgAAAA==.',
Yo='Yomaaln:BAAANQABCgQIBAAAAA==.',
['Yü']='Yüki:BAAANQADCgYICAAAAA==.',
Za='Zabaniya:BAAANQAECgQIBAAAAA==.',
Ze='Zenedict:BAAANQAECgcIDwAAAA==.',
Zh='Zharsha:BAAANQADCggICAAAAA==.',
Zs='Zsofi:BAABNQAECn81AAIDAAoKMR7fJwDKAgADAAoKMR7fJwDKAgAAAA==.',
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
