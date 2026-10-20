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

local lookup = {'Mage-Frost','Monk-Brewmaster','Warlock-Demonology','Priest-Holy','Warrior-Fury','Mage-Arcane','Warlock-Destruction','Druid-Restoration','Druid-Balance','Paladin-Holy','Paladin-Retribution','Priest-Shadow','Priest-Discipline','Paladin-Protection','Unknown-Unknown','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Unholy','Druid-Guardian','Hunter-BeastMastery','Monk-Mistweaver','Hunter-Survival','Evoker-Preservation','Shaman-Enhancement','Hunter-Marksmanship','Warrior-Arms','Monk-Windwalker','Shaman-Elemental','Shaman-Restoration','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Frost',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Ado:BAAANQAECgQIBAABNQAFFAcIGAABAG8UAA==.',
Ae='Aela:BAAANQAECgEIAgABNQAFFAIIBQACAA4YAA==.Aelin:BAAANQAECgQIBwAAAA==.',
Af='Affliction:BAAANQADCgEIAQAAAA==.',
Ai='Aimer:BAAANQAECgUIDwABNQAFFAcIGAABAG8UAA==.',
Al='Alkanz:BAABNQAECn8cAAIDAAoKmwnGXwDCAAADAAoKmwnGXwDCAAAAAA==.Allinaa:BAAANQAECgcICgAAAA==.Alya:BAABNQAECn8yAAIEAAoK3hmbLQCyAgAEAAoK3hmbLQCyAgAAAA==.',
An='Anika:BAABNQAECn8hAAIFAAoKdwkuEQCSAQAFAAoKdwkuEQCSAQAAAA==.Anshi:BAAANQAECgQIBAABNQAECggIHQAGAPMXAA==.',
Ar='Archspìre:BAAANQAECgIIAgAAAA==.Arise:BAAANQADCgIIAgAAAA==.Arlyx:BAABNQAECn8hAAMDAAoKJB7kMAA2AQAHAAUK0hZyJwA8AQADAAgKvyDkMAA2AQAAAA==.Arnwaz:BAABNQAECn8UAAMIAAcKzRLBNQBuAQAIAAcKzRLBNQBuAQAJAAMKbQcCkACWAAAAAA==.Arthuria:BAABNQAECn8aAAMKAAYKhxIXrAAoAQAKAAUKthIXrAAoAQALAAYKshPRFwH4AAAAAA==.',
As='Ashfia:BAAANQAECgEIBQAAAA==.Ashmegan:BAAANQAECgEIBAAAAA==.Ashrom:BAAANQAECgEIBAAAAA==.Ashzazul:BAAANQAECgEIBAAAAA==.Ashzia:BAAANQAECgEIBAAAAA==.Asianverstop:BAABNQAECn8WAAQEAAoKbSFuRwBQAgAEAAkK1iBuRwBQAgAMAAUKORvxHACiAAANAAEKihyECABVAAAAAA==.',
At='Atelwen:BAAANQADCgYJBgAAAA==.',
Ba='Baf:BAABNQAECn8tAAILAAkK7SOFGABiAwALAAkK7SOFGABiAwAAAA==.Banano:BAAANQAECgIIAgAAAA==.Banjodave:BAAANQAECggIDQAAAA==.',
Be='Berfomat:BAABNQAECn8kAAIOAAoKbh/oBwAiAwAOAAoKbh/oBwAiAwAAAA==.Berfsteals:BAAANQADCgIIBAAAAA==.Berfy:BAAANQAECgMIAwAAAA==.',
Bj='Bjorn:BAAANQAECgYICgAAAA==.',
Bl='Black:BAAANQADCggICgAAAA==.Blackky:BAAANQAECgEIAgAAAA==.Bloodyfupa:BAAANQADCgEIAQAAAA==.Bloomyvfd:BAAANQAECgQIEwAAAA==.',
Bo='Bocc:BAAANQADCgQIBQABNQAECgcIEAAPAAAAAA==.Boombip:BAAANQAECgEIAQAAAA==.Boxxylove:BAAANQADCggIGgABNQAECgoKMgAEAN4ZAA==.',
Br='Brockz:BAAANQADCgQIBwAAAA==.Broxar:BAAANQAECgEIAQAAAA==.',
Bu='Bulldan:BAAANQABCgIIAQAAAA==.',
['Bî']='Bîa:BAABNQAECn82AAILAAgKHCOlKgAdAwALAAgKHCOlKgAdAwAAAA==.',
Ca='Cavalis:BAABNQAECn8wAAQHAAoKjBMlBQDXAAADAAcKrBAhggDhAQAHAAUKXxclBQDXAAAQAAQKWw9RGQC+AAAAAA==.',
Ce='Ceedk:BAACNQAFFH8JAAIRAAUKIyGqDACKAQARAAUKIyGqDACKAQA1AAQKfyEAAxIACQrIJsERACkDABIACQrIJsERACkDABEABwrYIbgsAGQCAAE1AAUUBwgWAAkA9CEA.Ceesh:BAAANQAECggIBwABNQAFFAcIFgAJAPQhAA==.',
Ch='Cherradan:BAAANQADCggICAAAAA==.Chickenparm:BAAANQAECgIIAgAAAA==.Chll:BAAANQAECgIIAgABNQAFFAUICQASABcOAA==.',
Ci='Citizenmagi:BAAANQAECgEIAQAAAA==.',
Cj='Cjjackpot:BAAANQADCgYJCwAAAA==.',
Co='Cobb:BAAANQAECgcIEAAAAA==.Coorsbanquet:BAAANQADCgMIAwAAAA==.',
Cr='Creativezd:BAABNQAFFH8WAAMJAAcK9CHpAwB6AgAJAAcKjB7pAwB6AgATAAUKXSIsAQDrAQAAAA==.Crowley:BAAANQAECgMIDQAAAA==.',
Da='Dadgoo:BAAANQAECgYIDQAAAA==.Damnskippy:BAAANQAECgUICgAAAA==.Dannÿ:BAABNQAECn8ZAAQEAAgK+BveDwD6AQAEAAcK8R7eDwD6AQAMAAUK2hCVQwAYAQANAAMKRAshGwCPAAAAAA==.Darkire:BAABNQAECn8TAAIUAAUKvRiOqwCuAQAUAAUKvRiOqwCuAQAAAA==.',
De='Deathlegion:BAAANQADCgUIBQAAAA==.Deathroll:BAABNQAECn8mAAIVAAoKphPXFAAuAgAVAAoKphPXFAAuAgAAAA==.Deaux:BAAANQAECggICwAAAA==.Demosucc:BAACNQAFFH8ZAAMDAAYKyhpXBQASAQADAAUKLBxXBQASAQAHAAEKphYJCABXAAA1AAQKfxsAAwMACgo5Ix8hAAADAAMACQrnIx8hAAADAAcAAQp3HuxtAEMAAAAA.',
Di='Diabolic:BAAANQAECgUIBQAAAA==.',
Dk='Dkchilly:BAACNQAFFH8JAAISAAUKFw4YAwDrAAASAAUKFw4YAwDrAAA1AAQKfykAAhIACgr7H1UgAMkCABIACgr7H1UgAMkCAAAA.',
Do='Doomward:BAAANQAECgEIBAAAAA==.Dorien:BAABNQAECn8pAAMWAAkKnRr6AgDxAgAWAAkKXBj6AgDxAgAUAAgKFxp2YABWAgAAAA==.',
['Då']='Dårk:BAAANQADCgEIAQABNQABCgIIAgAPAAAAAA==.',
El='Elysele:BAAANQADCgUIBQABNQAECgoKLwAEAPoSAA==.',
Er='Erale:BAAANQAECgcIDwAAAA==.',
Fa='Faewryn:BAABNQAECn8cAAIKAAoKcRfFSwA6AgAKAAoKcRfFSwA6AgAAAA==.Falekia:BAAANQAECgcICwAAAA==.Falnaz:BAAANQAECgIIAwAAAA==.Fay:BAACNQAFFH8FAAICAAIKDhjAAgCdAAACAAIKDhjAAgCdAAA1AAQKfzAAAgIACgqLIeEDAEgDAAIACgqLIeEDAEgDAAAA.',
Fe='Fellus:BAAANQADCgIIAgAAAA==.Fengmeng:BAAANQADCggIEwAAAA==.',
Fi='Fishnchimps:BAAANQAECggIDwAAAA==.',
Fr='Freezah:BAAANQAECgEIAQAAAA==.Fríeren:BAAANQAECgYIEwAAAA==.',
Fu='Fupalicious:BAAANQAECgUIEgABNQAECgYIFwARAHIVAA==.',
Ga='Gaiserik:BAAANQAECggIEQAAAA==.Galad:BAAANQAECggIDAAAAA==.Garlictoast:BAAANQADCgYJBgAAAA==.',
Gi='Gillgamesh:BAAANQAECgcICwAAAA==.',
Go='Goochegg:BAAANQADCgUIBQAAAA==.',
Gr='Gracile:BAAANQAECgEIAQAAAA==.Gragolf:BAAANQAECgcICwAAAA==.Greggor:BAAANQAECgUICQAAAA==.Griffin:BAAANQADCggIDgAAAA==.Grippyfupa:BAAANQAECgQICAAAAA==.',
Gu='Gulzerak:BAAANQAFFAQIBAABNQAFFAYIFgAXACohAA==.Gustabo:BAAANQADCgIIAgAAAA==.',
Ha='Harnatauren:BAAANQADCgcIBwAAAA==.Hawtynaughty:BAAANQADCgYIBgAAAA==.',
He='Helcular:BAAANQAECgYIEAAAAA==.Hexuz:BAABNQAECn8jAAIYAAkK4RCxDgB/AgAYAAkK4RCxDgB/AgAAAA==.',
Ho='Holyblunt:BAACNQAFFH8NAAILAAUKcxsRBgD9AAALAAUKcxsRBgD9AAA1AAQKfy8AAgsACgoDJegQAIUDAAsACgoDJegQAIUDAAAA.Hotboydragon:BAAANQAECgcIDgABNQAECgoKFgAEAG0hAA==.',
Id='Idk:BAAANQAECggIEAAAAA==.',
In='Inthezone:BAABNQAECn8YAAMUAAcKxBL1kADnAQAUAAcKxBL1kADnAQAZAAUKEAZJUwDaAAAAAA==.Invisus:BAABNQAECn8WAAIFAAcKdReUDgDFAQAFAAcKdReUDgDFAQAAAA==.',
Is='Ispayders:BAAANQAECgEIAQAAAA==.',
Ja='Jarlan:BAACNQAFFH8FAAIaAAMKkhZZJADcAAAaAAMKkhZZJADcAAA1AAQKfyoAAhoACQrNIWAyAPYCABoACQrNIWAyAPYCAAAA.Jarlhun:BAAANQAECgEIAQABNQAFFAMIBQAaAJIWAA==.Jarmon:BAABNQAECn8ZAAIbAAYK4x8JJAAFAgAbAAYK4x8JJAAFAgABNQAFFAMIBQAaAJIWAA==.',
Ju='Justin:BAABNQAECn8rAAIRAAoKQhiELQBgAgARAAoKQhiELQBgAgAAAA==.',
Ka='Katakuri:BAAANQAECgUIBQAAAA==.Katara:BAAANQADCggICAAAAA==.Kattsumoto:BAABNQAECn8tAAMVAAoKjCFFBQBNAwAVAAoKjCFFBQBNAwAbAAYK6xMlHQDAAAAAAA==.',
Ke='Ketharion:BAABNQAECn8uAAMKAAkKNxTPDQDwAQAKAAkKNxTPDQDwAQALAAUKgAmRFgH6AAAAAA==.',
Kh='Khato:BAAANQAECgMICgAAAA==.',
Ku='Kurazan:BAACNQAFFH8NAAIaAAUK8B13CAD2AAAaAAUK8B13CAD2AAA1AAQKfyoAAhoACgoKIJ5CAMICABoACgoKIJ5CAMICAAAA.Kurisu:BAABNQAECn8fAAIDAAcK4w2k2wASAQADAAcK4w2k2wASAQAAAA==.',
La='Lafaymignon:BAAANQABCgIIAgAAAA==.Lavabolter:BAAANQAECgEIAQAAAA==.Laîlyne:BAABNQAECn8cAAMcAAoKJxDDcQDLAQAcAAkKgRHDcQDLAQAdAAEKtAIHpAAnAAAAAA==.',
Le='Leo:BAAANQAECgcICwAAAA==.Leone:BAAANQAECgYIDwAAAA==.',
Li='Lilath:BAAANQAECgEIAgAAAA==.',
Lo='Logical:BAABNQAECn8kAAILAAkKfBZZPgBKAQALAAkKfBZZPgBKAQAAAA==.',
Lu='Lute:BAABNQAECn8mAAIRAAgK8BxeIQCpAgARAAgK8BxeIQCpAgAAAA==.',
['Lá']='Lárien:BAAANQAECgQIBwAAAA==.',
Ma='Manon:BAABNQAECn8sAAMdAAoKcRHhYgDlAQAdAAkK+A/hYgDlAQAcAAkKywYvmABoAQAAAA==.Maxacry:BAAANQADCgIIAgAAAA==.Maxstoke:BAAANQAECgcIBwABNQAECggIJwAcAGkiAA==.',
Mc='Mcchungus:BAAANQAECgcICgAAAA==.',
Me='Meowmixx:BAAANQAECgEIAQAAAA==.',
Mi='Mischief:BAAANQADCgYICwAAAA==.',
Mo='Morewyn:BAAANQADCggICAAAAA==.Mortred:BAAANQAECgEIAQAAAA==.',
Mt='Mtd:BAAANQAECgUIBQABNQAECgoKPAAWAF4dAA==.Mth:BAABNQAECn8YAAMWAAgKjhZiBgA2AgAWAAgKjhZiBgA2AgAZAAUKigrrTAD+AAABNQAECgoKPAAWAF4dAA==.',
Na='Nadok:BAAANQAECggIDgAAAA==.Naz:BAAANQAECgIIAgAAAA==.',
Ni='Nickignomaj:BAAANQAECgUIBgABNQAECgoKKQAaAD4cAA==.Nisara:BAAANQAECgMIBAAAAA==.',
No='Norina:BAAANQADCgYICwAAAA==.',
Ob='Obv:BAABNQAECn8WAAIeAAkKSxY0AwCDAQAeAAkKSxY0AwCDAQAAAA==.',
Om='Omantul:BAABNQAECn8cAAIdAAcKMBlHXAD6AQAdAAcKMBlHXAD6AQAAAA==.',
Oo='Oobie:BAAANQADCgYIBgAAAA==.',
Ow='Owocoxl:BAAANQAECgYIBwABNQAFFAcIGwAfAGESAA==.',
Oz='Ozziee:BAAANQAECgMIBwAAAA==.Ozzthehunter:BAAANQADCgIIAgAAAA==.',
Pa='Pants:BAAANQADCggIGQAAAA==.Paroguei:BAAANQAECgcICQABNQAECgoKIgAKAKsiAA==.',
Ph='Phakes:BAAANQAECgYIBQAAAA==.Phengzera:BAAANQAECgQIAwAAAA==.Phizz:BAAANQADCggICgABNQAFFAcIIgAGALkeAA==.',
Pl='Pllwprincess:BAAANQADCgIIAgAAAA==.',
Po='Poofty:BAAANQADCgUIBQAAAA==.',
Pr='Predator:BAACNQAFFH8bAAIaAAcKgiZ+AQD+AgAaAAcKgiZ+AQD+AgA1AAQKfzoAAhoACgqBIgIEANgDABoACgqBIgIEANgDAAAA.',
Pu='Puke:BAABNQAECn8ZAAIeAAgKriTpAgBGAwAeAAgKriTpAgBGAwAAAA==.Purpledisco:BAAANQADCggICAABNQAECgoKMgAEAN4ZAA==.Purplepower:BAABNQAECn8iAAIaAAgKoRlTdAA4AgAaAAgKoRlTdAA4AgAAAA==.',
Pw='Pwincess:BAAANQAECgQIBAAAAA==.',
Qw='Qwelmo:BAAANQADCgEJAgAAAA==.',
Ri='Rigaud:BAAANQADCgMIAwAAAA==.',
Ro='Roaka:BAAANQAECgEIAQAAAA==.Rolypoly:BAAANQAECgUIBQAAAA==.',
Ry='Ryaine:BAAANQAECgEIAQAAAA==.Ryø:BAABNQAECn8cAAITAAoK9BRXGwDJAQATAAoK9BRXGwDJAQAAAA==.',
Se='Seigler:BAABNQAECn8bAAIWAAgKHguzCAC+AQAWAAgKHguzCAC+AQAAAA==.Senne:BAAANQAECgIIAgAAAA==.Seraphym:BAAANQADCgUIBQAAAA==.',
Sh='Shaviji:BAAANQAECggIDgAAAA==.Shigzen:BAAANQAECgIIAwABNQADCggICQAPAAAAAA==.Shore:BAABNQAECn88AAMWAAoKXh1IAQBoAwAWAAoKXh1IAQBoAwAZAAMK5A27YgCeAAAAAA==.Shuralya:BAABNQAECn8/AAILAAoKiiG/DAAbAgALAAoKiiG/DAAbAgAAAA==.',
Sk='Skoob:BAAANQAECgMIAwAAAA==.',
So='Sonofabirch:BAAANQADCgMIAwAAAA==.',
St='Striga:BAAANQABCgEIAQAAAA==.',
Su='Sully:BAAANQADCggIDgAAAA==.Survas:BAABNQAECn8oAAIgAAkK0BJIEwBRAgAgAAkK0BJIEwBRAgAAAA==.',
Ta='Tavgoesboom:BAAANQAECgQICAABNQAECggIDwAPAAAAAA==.',
Te='Terrin:BAAANQAECgcIEAAAAA==.Texmexdruid:BAAANQADCggIDgAAAA==.',
Th='Tharkun:BAABNQAECn8UAAIGAAcKthropgA0AgAGAAcKthropgA0AgAAAA==.Thedagda:BAAANQADCggICAAAAA==.Thunderlinkx:BAAANQAECgEIAgABNQAECgcIDwAPAAAAAA==.',
Ti='Titlecard:BAAANQAECgEIAgAAAA==.',
Tr='Triage:BAABNQAECn8bAAIGAAkK2BgMlgBUAgAGAAkK2BgMlgBUAgAAAA==.',
Ts='Tsu:BAEANQADCgEIAQABNQAECgUIEwAPAAAAAA==.Tsuko:BAEANQAECgIIAgABNQAECgUIEwAPAAAAAA==.',
Tu='Tul:BAAANQAECggIEwAAAA==.',
Tw='Twotoedfupa:BAABNQAECn8XAAIRAAYKchWuYwBjAQARAAYKchWuYwBjAQAAAA==.',
Ty='Tyrias:BAABNQAECn8eAAILAAkKkAVygQFXAAALAAkKkAVygQFXAAAAAA==.',
Ug='Ugin:BAABNQAECn8eAAMSAAoKsQtaVADAAQASAAoKhwtaVADAAQAhAAMKJAqvhwCTAAAAAA==.',
Um='Umbrasyl:BAAANQAECgIIBAAAAA==.',
Un='Unclecharlie:BAAANQAECgQIBQABNQAECgoKJQASAJ8kAA==.Undeadrogue:BAAANQADCgQIBAAAAA==.',
Va='Vasrin:BAABNQAECn8mAAIYAAoKtSBQBgAhAwAYAAoKtSBQBgAhAwAAAA==.',
Vo='Voidomo:BAABNQAECn8xAAQQAAoK6xQtBgBPAgAQAAgKKxctBgBPAgADAAkKyQqSsABvAQAHAAQKiBaWPADPAAAAAA==.Vonbearback:BAAANQADCgIIAwAAAA==.',
Wa='Waterlance:BAAANQAECgEIAQAAAA==.',
Wh='Whatchashots:BAAANQADCggICAAAAA==.',
Wi='Wisecraic:BAAANQAECgEIBAAAAA==.',
Wo='Wocoxl:BAACNQAFFH8bAAIfAAcKYRIzAwA3AgAfAAcKYRIzAwA3AgA1AAQKfy8AAx8ACgoFHTsKAH4BACAACAp2FdQeANoBAB8ACQoFHTsKAH4BAAAA.',
Wu='Wutank:BAAANQADCgMIAwAAAA==.',
Xe='Xendamo:BAAANQADCggIEAAAAA==.',
Ya='Yaracklea:BAAANQAECgQIDAAAAA==.',
Yi='Yinokiea:BAAANQAECgMIBgAAAA==.',
['Yü']='Yüki:BAAANQADCgYICAAAAA==.',
Za='Zabaniya:BAAANQADCggIHQAAAA==.',
Ze='Zenedict:BAAANQAECgcIEgAAAA==.',
Zh='Zharsha:BAAANQADCggICAAAAA==.',
Zs='Zsofi:BAABNQAECn8rAAIEAAoKihzYEgDdAQAEAAoKihzYEgDdAQAAAA==.',
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
