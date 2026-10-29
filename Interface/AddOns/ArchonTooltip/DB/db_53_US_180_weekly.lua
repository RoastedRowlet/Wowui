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

local lookup = {'Monk-Brewmaster','Warlock-Demonology','Priest-Holy','Warrior-Fury','Mage-Arcane','Warlock-Destruction','Druid-Restoration','Druid-Balance','Paladin-Holy','Paladin-Retribution','Priest-Shadow','Priest-Discipline','Paladin-Protection','Unknown-Unknown','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Unholy','Druid-Guardian','Hunter-BeastMastery','Monk-Mistweaver','Hunter-Survival','Warrior-Arms','Evoker-Preservation','Shaman-Enhancement','Evoker-Augmentation','Hunter-Marksmanship','Monk-Windwalker','Druid-Feral','Mage-Frost','Shaman-Elemental','Shaman-Restoration','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Frost',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=53,date='2026-10-27',data={Ae='Aela:BAAANQAECgEIAQABNQAFFAQIBwABALUTAA==.Aelin:BAAANQAECgQIBwAAAA==.',
Af='Affliction:BAAANQADCgEIAQAAAA==.',
Al='Alanispally:BAAANQADCgcIBwAAAA==.Alkanz:BAABNQAECn8cAAICAAoKmwmHqQCAAQACAAoKmwmHqQCAAQAAAA==.Allinaa:BAAANQAECggICgAAAA==.Alya:BAABNQAECn81AAIDAAoK3hmbLQCyAgADAAoK3hmbLQCyAgAAAA==.',
An='Anika:BAABNQAECn8hAAIEAAoKdwkuEQCSAQAEAAoKdwkuEQCSAQAAAA==.Anshi:BAAANQAECgQIBAABNQAECggIIQAFAPMXAA==.',
Ar='Archspìre:BAAANQAECgEIAQAAAA==.Arise:BAAANQADCgIIAgAAAA==.Arlyx:BAABNQAECn8lAAMCAAoK8R4yXQBAAgACAAgK0SEyXQBAAgAGAAUK0hZyJwA8AQAAAA==.Arnwaz:BAABNQAECn8VAAMHAAgKNhPBNQBuAQAHAAgKNhPBNQBuAQAIAAMKbQcCkACWAAAAAA==.Arthuria:BAABNQAECn8cAAMJAAgKEBMXrAAoAQAJAAcKRhMXrAAoAQAKAAYKshPRFwH4AAAAAA==.',
As='Ashzazul:BAAANQABCggIIAAAAA==.Asianverstop:BAABNQAECn8ZAAQDAAoKbSFuRwBQAgADAAkK1iBuRwBQAgALAAUKORsTSwDrAAAMAAEKihwODgBSAAAAAA==.',
At='Atelwen:BAAANQADCgYJBgAAAA==.',
Ba='Baf:BAABNQAECn8tAAIKAAkK7SOFGABiAwAKAAkK7SOFGABiAwAAAA==.Banano:BAAANQAECgIIAgAAAA==.Banjodave:BAAANQAECggIDAAAAA==.',
Be='Berfomat:BAABNQAECn8qAAINAAoKDiDoBwAiAwANAAoKDiDoBwAiAwAAAA==.Berfsteals:BAAANQADCgIIBAAAAA==.Berfy:BAAANQAECgMIAwAAAA==.',
Bj='Bjorn:BAAANQAECgYICQAAAA==.',
Bl='Black:BAAANQADCggICgAAAA==.Blackky:BAAANQAECgEIAgAAAA==.Bloodyfupa:BAAANQADCgEIAQAAAA==.Bloomyvfd:BAABNQAECn8aAAIJAAYKxR09KQAJAgAJAAYKxR09KQAJAgAAAA==.',
Bo='Bocc:BAAANQADCgQIBQABNQAECgcIEAAOAAAAAA==.Boombip:BAAANQABCgMIAwAAAA==.Boxxylove:BAAANQADCggIGgABNQAECgoKNQADAN4ZAA==.',
Br='Brockz:BAAANQADCgQIBwAAAA==.',
Bu='Bulldan:BAAANQABCgIIAQAAAA==.',
['Bî']='Bîa:BAABNQAECn88AAIKAAkKJCGlKgAdAwAKAAkKJCGlKgAdAwAAAA==.',
Ca='Cavalis:BAABNQAECn82AAQGAAoKVxW3CwDDAAACAAgKBBEhggDhAQAGAAUKXxe3CwDDAAAPAAQKPBBRGQC+AAAAAA==.',
Ce='Ceedk:BAACNQAFFH8JAAIQAAUKIyGqDACKAQAQAAUKIyGqDACKAQA1AAQKfyEAAxEACQrIJsERACkDABEACQrIJsERACkDABAABwrYIbgsAGQCAAE1AAUUBwgWAAgA9CEA.Ceesh:BAAANQAECggIBwABNQAFFAcIFgAIAPQhAA==.',
Ch='Cherradan:BAAANQADCggICAAAAA==.Chickenparm:BAAANQAECgIIAgAAAA==.Chll:BAAANQAECgIIAgABNQAFFAUIDAARAAQZAA==.',
Cj='Cjjackpot:BAAANQADCgYJCwAAAA==.',
Co='Cobb:BAAANQAECgcIEAAAAA==.Coorsbanquet:BAAANQADCgMIAwAAAA==.',
Cr='Creativezd:BAACNQAFFH8WAAMIAAcK9CHpAwB6AgAIAAcKjB7pAwB6AgASAAUKXSIsAQDrAQA1AAQKfx4AAwgACQqJIM4YAM4BAAgABgorIM4YAM4BABIABwr6IvwVAGMBAAAA.Crowley:BAAANQAECgMICgAAAA==.',
Da='Dadgoo:BAAANQAECgYICgAAAA==.Damnskippy:BAAANQAECgUICQAAAA==.Dannÿ:BAABNQAECn8fAAQDAAgKVx5PJQA/AgADAAgKVx5PJQA/AgALAAUK2hCVQwAYAQAMAAMKRAshGwCPAAAAAA==.Darkire:BAABNQAECn8XAAITAAcKmhiOqwCuAQATAAcKmhiOqwCuAQAAAA==.',
De='Deathlegion:BAAANQADCgUIBQAAAA==.Deathroll:BAABNQAECn8rAAIUAAoKphPXFAAuAgAUAAoKphPXFAAuAgAAAA==.Deaux:BAAANQAECggICwAAAA==.Demosucc:BAACNQAFFH8aAAMCAAcKKxulBQBbAQACAAYKTRylBQBbAQAGAAEKphZDGQBSAAA1AAQKfxwAAwIACgo5Ix8hAAADAAIACQrnIx8hAAADAAYAAQp3HuxtAEMAAAAA.Dethandra:BAAANQADCggICAAAAA==.',
Di='Diabolic:BAAANQAECgUIBQAAAA==.',
Dk='Dkchilly:BAACNQAFFH8MAAIRAAUKBBnQAwAJAQARAAUKBBnQAwAJAQA1AAQKfy0AAhEACgqyIlUgAMkCABEACgqyIlUgAMkCAAAA.',
Do='Doomward:BAAANQAECgUIBwAAAA==.Dorien:BAABNQAECn8pAAMVAAkKnRr6AgDxAgAVAAkKXBj6AgDxAgATAAgKFxp2YABWAgAAAA==.',
['Då']='Dårk:BAAANQADCgEIAQABNQABCgIIAgAOAAAAAA==.',
El='Elysele:BAAANQADCgUIBQABNQAECgoKOQADAPoSAA==.',
Er='Erale:BAAANQAECgcIDQAAAA==.',
Fa='Faewryn:BAABNQAECn8eAAIJAAoKVRjFSwA6AgAJAAoKVRjFSwA6AgAAAA==.Falekia:BAAANQAECgcICgAAAA==.Falnaz:BAAANQAECgIIAwAAAA==.Fay:BAACNQAFFH8HAAIBAAQKtRMPAwDXAAABAAQKtRMPAwDXAAA1AAQKfzUAAgEACgqLIeEDAEgDAAEACgqLIeEDAEgDAAAA.',
Fe='Fellus:BAAANQADCgIIAgAAAA==.Fengmeng:BAAANQADCggIEwAAAA==.',
Fi='Fishnchimps:BAAANQAECggIDAAAAA==.',
Fr='Freezah:BAAANQAECgUIBgAAAA==.Fríeren:BAAANQAECgYIEAAAAA==.',
Fu='Fupalicious:BAAANQAECgUIEQABNQAECgYIHAAQAHIVAA==.Furrburger:BAAANQAECgMIAwAAAA==.',
Ga='Gaiserik:BAABNQAECn8XAAMWAAgKpxUnfwAdAgAWAAgKbRUnfwAdAgAEAAEKUg7hMQA5AAAAAA==.Galad:BAAANQAECggICwAAAA==.Garlictoast:BAAANQADCgYJBgAAAA==.',
Gi='Gillgamesh:BAAANQAECgcICwAAAA==.',
Go='Goochegg:BAAANQADCgUIBQAAAA==.',
Gr='Gragolf:BAAANQAECggIDAAAAA==.Greggor:BAAANQAECgUICAAAAA==.Griffin:BAAANQADCggIDgAAAA==.Grippyfupa:BAAANQAECgQIBwAAAA==.',
Gu='Gulzerak:BAABNQAECn8aAAMCAAoKOiGVMgDhAQACAAgKHCCVMgDhAQAGAAIKlCRNPgDJAAABNQAFFAYIFgAXACohAA==.Gustabo:BAAANQADCgIIAgAAAA==.',
Ha='Harnatauren:BAAANQADCgcIDgAAAA==.Hawtynaughty:BAAANQADCgYIBgAAAA==.',
He='Helcular:BAAANQAECgYIDAAAAA==.Hexuz:BAABNQAECn8mAAIYAAoKExKxDgB/AgAYAAoKExKxDgB/AgAAAA==.',
Hi='Hittu:BAAANQAECggIBQAAAA==.',
Ho='Holyblunt:BAACNQAFFH8NAAIKAAUKcxtCCwDsAAAKAAUKcxtCCwDsAAA1AAQKfy8AAgoACgoDJegQAIUDAAoACgoDJegQAIUDAAAA.Hotboydragon:BAABNQAECn8VAAMZAAcKzRjTBwAmAgAZAAcKzRjTBwAmAgAXAAcKzBTWDAC2AQABNQAECgoKGQADAG0hAA==.',
Id='Idk:BAAANQAECgcIEQAAAA==.',
In='Inthezone:BAABNQAECn8YAAMTAAcKxBL1kADnAQATAAcKxBL1kADnAQAaAAUKEAZJUwDaAAAAAA==.Invisus:BAABNQAECn8gAAIEAAkKNBvhAgCLAgAEAAkKNBvhAgCLAgAAAA==.',
Is='Ispayders:BAAANQAECgEIAQAAAA==.',
Ja='Jarlan:BAACNQAFFH8FAAIWAAMKkhZZJADcAAAWAAMKkhZZJADcAAA1AAQKfyoAAhYACQrNIWAyAPYCABYACQrNIWAyAPYCAAAA.Jarlhun:BAAANQADCggIEgABNQAFFAMIBQAWAJIWAA==.Jarmon:BAABNQAECn8ZAAIbAAYK4x8JJAAFAgAbAAYK4x8JJAAFAgABNQAFFAMIBQAWAJIWAA==.',
Jo='Joolian:BAABNQAECn8YAAQcAAoKKSAEAwC6AgAcAAkKKSAEAwC6AgAIAAIKIhjDoQBZAAAHAAEKBhn/bwBFAAABNQAFFAcIGQAdAG8UAA==.Joolianr:BAAANQAECgcICwABNQAFFAcIGQAdAG8UAA==.',
Ju='Justin:BAABNQAECn8vAAIQAAoKZhiELQBgAgAQAAoKZhiELQBgAgAAAA==.',
Ka='Katara:BAAANQADCggICAAAAA==.Kattsumoto:BAACNQAFFH8JAAMUAAUK3xhgAgCGAQAUAAUK3xhgAgCGAQAbAAEKBQj4DgA6AAA1AAQKfzEAAxQACgqMIUUFAE0DABQACgqMIUUFAE0DABsABgrrE54tALsAAAAA.',
Ke='Ketharion:BAABNQAECn80AAMJAAoKGxfVHQBWAgAJAAoKGxfVHQBWAgAKAAUKgAmRFgH6AAAAAA==.',
Kh='Khato:BAAANQAECgMICAAAAA==.',
Ku='Kurazan:BAACNQAFFH8QAAIWAAUKVh95DAD/AAAWAAUKVh95DAD/AAA1AAQKfy4AAhYACgrQIZ5CAMICABYACgrQIZ5CAMICAAAA.Kurisu:BAABNQAECn8fAAICAAcK4w2k2wASAQACAAcK4w2k2wASAQAAAA==.',
La='Lafaymignon:BAAANQABCgIIAgAAAA==.Lavabolter:BAAANQAECgEIAQAAAA==.Laîlyne:BAABNQAECn8hAAMeAAoKVRTGOwBlAQAeAAoKVRTGOwBlAQAfAAIKagXIuABKAAAAAA==.',
Le='Leo:BAAANQAECgcICwAAAA==.Leone:BAAANQAECgYIDwAAAA==.',
Li='Lilany:BAAANQABCgIIAgAAAA==.Lilath:BAAANQAECgEIAQAAAA==.',
Lo='Logical:BAABNQAECn8uAAIKAAoKNRoKNQAkAgAKAAoKNRoKNQAkAgAAAA==.',
Lu='Lute:BAABNQAECn8mAAIQAAgK8BxeIQCpAgAQAAgK8BxeIQCpAgAAAA==.',
['Lá']='Lárien:BAAANQAECgQIBgAAAA==.',
Ma='Manon:BAACNQAFFH8GAAIfAAMKLRCsEQDEAAAfAAMKLRCsEQDEAAA1AAQKfy0AAx8ACgo3D+FiAOUBAB8ACgo3D+FiAOUBAB4ACQrLBi+YAGgBAAAA.Maxacry:BAAANQADCgIIAgAAAA==.Maxstoke:BAAANQAECgcIDQABNQAECgoKIQAIAKgeAA==.',
Mc='Mcchungus:BAAANQAECgcIEAAAAA==.',
Me='Meowmixx:BAAANQAECgEIAQAAAA==.',
Mi='Mischief:BAAANQADCgYICwAAAA==.',
Mo='Morewyn:BAAANQAECgEIAQAAAA==.Mortred:BAAANQAECgEIAQAAAA==.',
Mt='Mtd:BAAANQAECgYIBwABNQAECgoKQgAVADoeAA==.Mth:BAABNQAECn8dAAMVAAgKqhliBgA2AgAVAAgKqhliBgA2AgAaAAUKigrrTAD+AAABNQAECgoKQgAVADoeAA==.',
Na='Nadok:BAAANQAECggIDgAAAA==.Nancyy:BAAANQABCgIIAgAAAA==.Naz:BAAANQAECgIIAgAAAA==.',
Ni='Nickignomaj:BAAANQAECgUIBQABNQAECgoKMAAWAPkdAA==.Nisara:BAAANQAECgMIAwAAAA==.',
No='Norina:BAAANQADCgYICwAAAA==.',
Ob='Obv:BAABNQAECn8ZAAIgAAkKjBhEBwCOAQAgAAkKjBhEBwCOAQAAAA==.',
Om='Omantul:BAABNQAECn8dAAIfAAgKERdHXAD6AQAfAAgKERdHXAD6AQAAAA==.',
Oo='Oobie:BAAANQADCgYIBgAAAA==.',
Ow='Owocoxl:BAAANQAECgYICQABNQAFFAcIGwAhAGESAA==.',
Oz='Ozziee:BAAANQAECgMIBQAAAA==.Ozzthehunter:BAAANQADCgIIAgAAAA==.',
Pa='Pants:BAAANQADCggIGQAAAA==.Paroguei:BAAANQAECgYICgABNQAECgoKKgAJAMkiAA==.',
Ph='Phakes:BAAANQAECgYIDAAAAA==.Phengzera:BAAANQAECgMIAwAAAA==.Phizz:BAAANQADCggICgABNQAFFAgIJAAFADEeAA==.',
Pl='Pllwprincess:BAAANQADCgIIAgAAAA==.',
Po='Poofty:BAAANQADCgUIBQAAAA==.',
Pr='Predator:BAACNQAFFH8bAAIWAAcKgiZ+AQD+AgAWAAcKgiZ+AQD+AgA1AAQKf0QAAhYACgrrJQIEANgDABYACgrrJQIEANgDAAAA.Prolove:BAAANQAECgIIAQAAAA==.',
Pu='Puke:BAABNQAECn8gAAIgAAgKriTpAgBGAwAgAAgKriTpAgBGAwAAAA==.Purpledisco:BAAANQADCggICAABNQAECgoKNQADAN4ZAA==.Purplepower:BAABNQAECn8iAAIWAAgKoRlTdAA4AgAWAAgKoRlTdAA4AgAAAA==.',
Pw='Pwincess:BAAANQAECgQIBAAAAA==.',
Qw='Qwelmo:BAAANQADCgEJAgAAAA==.',
Ri='Rigaud:BAAANQADCgMIAwAAAA==.',
Ro='Roaka:BAAANQABCgIIAgAAAA==.Rolypoly:BAAANQAECgUIBQAAAA==.',
Ry='Ryø:BAABNQAECn8cAAISAAoK9BRXGwDJAQASAAoK9BRXGwDJAQAAAA==.',
Se='Seigler:BAABNQAECn8fAAIVAAgKnAuzCAC+AQAVAAgKnAuzCAC+AQAAAA==.Senne:BAAANQAECgQIBAAAAA==.Seraphym:BAAANQADCgUIBQAAAA==.',
Sh='Shaviji:BAAANQAECggICAAAAA==.Shigzen:BAAANQAECgIIAwABNQADCggICQAOAAAAAA==.Shore:BAABNQAECn9CAAMVAAoKOh5IAQBoAwAVAAoKOh5IAQBoAwAaAAMK5A27YgCeAAAAAA==.Shuralya:BAABNQAECn9JAAIKAAoKCCPdFQBtAwAKAAoKCCPdFQBtAwAAAA==.',
Sk='Skoob:BAAANQAECgMIAgAAAA==.',
So='Sonofabirch:BAAANQADCgMIAwAAAA==.',
St='Striga:BAAANQABCgEIAQAAAA==.',
Su='Sully:BAAANQADCggIDgAAAA==.Survas:BAABNQAECn8qAAIiAAkKZBNIEwBRAgAiAAkKZBNIEwBRAgAAAA==.',
Ta='Tavgoesboom:BAAANQAECgQIBQABNQAECggIDAAOAAAAAA==.',
Te='Terrin:BAAANQAECgcIEQAAAA==.Texmexdruid:BAAANQADCggIDgAAAA==.',
Th='Tharkun:BAABNQAECn8UAAIFAAcKthropgA0AgAFAAcKthropgA0AgAAAA==.Thunderlinkx:BAAANQAECgEIAQABNQAECgcIDQAOAAAAAA==.',
Ti='Titlecard:BAAANQAECgEIAgAAAA==.',
To='Tora:BAAANQAECggICAAAAA==.',
Tr='Triage:BAABNQAECn8eAAIFAAkKBxkMlgBUAgAFAAkKBxkMlgBUAgAAAA==.',
Ts='Tsu:BAEANQAECgYIBwAAAA==.Tsuko:BAEANQAECgIIAgABNQAECgYIBwAOAAAAAA==.',
Tu='Tul:BAABNQAECn8dAAIJAAoKUB6YDQDzAgAJAAoKUB6YDQDzAgAAAA==.',
Tw='Twotoedfupa:BAABNQAECn8cAAIQAAYKchWuYwBjAQAQAAYKchWuYwBjAQAAAA==.',
Ty='Tyrias:BAABNQAECn8eAAIKAAkKkAVygQFXAAAKAAkKkAVygQFXAAAAAA==.',
Ug='Ugin:BAABNQAECn8eAAMRAAoKsQtaVADAAQARAAoKhwtaVADAAQAjAAMKJAqvhwCTAAAAAA==.',
Um='Umbrasyl:BAAANQAECgMIAwAAAA==.',
Un='Unclecharlie:BAAANQAECgQIBQABNQAECgoKLgARAH0lAA==.Undeadrogue:BAAANQADCgQIBAAAAA==.',
Va='Vasrin:BAABNQAECn8sAAIYAAoKCSFQBgAhAwAYAAoKCSFQBgAhAwAAAA==.',
Vo='Voidomo:BAABNQAECn87AAQPAAoKLBUtBgBPAgAPAAgKKxctBgBPAgACAAkKEwvLeAAGAQAGAAQKiBaQEgCGAAAAAA==.Vonbearback:BAAANQADCgIIAwAAAA==.',
Wa='Waterlance:BAAANQAECgEIAQAAAA==.',
Wh='Whatchashots:BAAANQADCggICAAAAA==.',
Wi='Wisecraic:BAAANQAECgEIAgAAAA==.',
Wo='Wocoxl:BAACNQAFFH8bAAIhAAcKYRIzAwA3AgAhAAcKYRIzAwA3AgA1AAQKfzcAAyEACgoNH2QRAHcBACIACgrbGXgnAOwBACEACQoFHWQRAHcBAAAA.',
Wu='Wutank:BAAANQADCgMIAwAAAA==.',
Xe='Xendamo:BAAANQADCggIEAAAAA==.',
Xo='Xoid:BAAANQADCggICAAAAA==.',
Ya='Yaracklea:BAAANQAECgQICQAAAA==.',
Yi='Yinokiea:BAAANQAECgMIBgAAAA==.',
Yo='Yomaaln:BAAANQABCgIIAgAAAA==.',
['Yü']='Yüki:BAAANQADCgYICAAAAA==.',
Za='Zabaniya:BAAANQAECgQIBAAAAA==.',
Ze='Zenedict:BAAANQAECgcIDwAAAA==.',
Zh='Zharsha:BAAANQADCggICAAAAA==.',
Zs='Zsofi:BAABNQAECn8xAAIDAAoKMR7fJwDKAgADAAoKMR7fJwDKAgAAAA==.',
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
