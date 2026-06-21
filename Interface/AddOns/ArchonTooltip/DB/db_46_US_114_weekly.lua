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

local lookup = {'Paladin-Retribution','DeathKnight-Unholy','Warlock-Affliction','Warlock-Demonology','Priest-Holy','Druid-Feral','Druid-Guardian','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Warlock-Destruction','Priest-Shadow','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Hunter-Survival','Paladin-Holy','DeathKnight-Blood','Priest-Discipline','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','Paladin-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','Monk-Windwalker','Druid-Balance','DemonHunter-Devourer','Monk-Mistweaver','DeathKnight-Frost',}
local provider = {region='US',realm="Gul'dan",name='US',type='weekly',zone=46,date='2026-06-20',data={Ae='Aeri:BAAALgAECgYJDAAAAA==.',
Al='Alastormoody:BAAALgADCgcJDAAAAA==.Alelover:BAAALgADCgUJBQAAAA==.Allaria:BAABLgAECn8UAAIBAAcJPw6RvQAMAQABAAcJPw6RvQAMAQAAAA==.Almadíon:BAAALgADCgcJCAAAAA==.',
Am='Amosian:BAAALgADCgIJAgAAAA==.',
An='Ana:BAAALgADCgMJAwAAAA==.',
Ao='Aoemomma:BAAALgADCgcJBwAAAA==.',
Ar='Arin:BAAALgAECgIJAwABLgAFFAMJCgACAEEmAA==.',
As='Asuya:BAAALgADCgIJAwAAAA==.',
Az='Azög:BAAALgADCgUJBQAAAA==.',
Ba='Babysocks:BAAALgAECgYJBgAAAA==.',
Bc='Bc:BAACLgAFFH8HAAMDAAMJ3RmVCgDTAAADAAIJpSKVCgDTAAAEAAIJGRdQjwCmAAAuAAQKfxsAAgQACAn4JjEDAI0DAAQACAn4JjEDAI0DAAAA.',
Be='Beep:BAABLgAECn8lAAIEAAcJRh+JOgAiAgAEAAcJRh+JOgAiAgAAAA==.',
Bl='Blackthunder:BAAALgAECggJDAAAAA==.',
Bo='Bobert:BAAALgADCgcJBgAAAA==.Bofadz:BAAALgADCgYJBgAAAA==.Boozecruise:BAAALgADCgIJAgAAAA==.Boozedrat:BAAALgAFFAEJAwABLgAFFAYJGQAEAOgaAA==.Bowyn:BAABLgAECn8XAAIFAAYJHhNoOgBSAQAFAAYJHhNoOgBSAQAAAA==.',
Bu='Bubblnbiotch:BAAALgADCgEJAQAAAA==.Budleaf:BAABLgAECn8aAAQGAAYJlhKUIwDtAAAGAAUJ0BKUIwDtAAAHAAYJFwx7OwC4AAAIAAEJ1AaE6gAjAAAAAA==.Bunkley:BAABLgAECn8rAAQJAAgJtRFrLwCDAQAJAAgJtRFrLwCDAQAKAAYJDQxYeQDzAAALAAMJTQqrLACUAAAAAA==.Butterknives:BAAALgAECgEJAQAAAA==.Buttshark:BAAALgADCgcJBwAAAA==.',
By='Byege:BAACLgAFFH8ZAAMEAAYJ6BpiLgCMAQAEAAYJvhhiLgCMAQADAAEJThmNAgBaAAAuAAQKfycAAwQACQnHH8YYAI8CAAQACQmjH8YYAI8CAAwABQnOF7IbAHABAAAA.',
Ca='Cantfireme:BAAALgAECgYJDwABLgAECgkJRQABADobAA==.Cardhunter:BAAALgADCgYJBgAAAA==.',
Ch='Champilon:BAAALgAECgEJAQAAAA==.Chaoticus:BAAALgAECgYJDQABLgAECggJIgANAJgOAA==.Charizards:BAAALgADCgYJDQAAAA==.Charmahnder:BAAALgAECgIJAgAAAA==.',
Co='Coma:BAAALgAECgMJBAAAAA==.',
Cr='Crunbard:BAAALgAECggJDwAAAA==.',
Cu='Culdan:BAABLgAECn8aAAMMAAYJ+QkBHQDAAAAMAAYJ+QkBHQDAAAAEAAQJlgRf5wCPAAAAAA==.',
Da='Dalirus:BAAALgAECgUJCgABLgAECgkJRQABADobAA==.Danahe:BAAALgAFFAEJAQABLgAFFAIJBAAOAAAAAA==.Darci:BAAALgAECgcJEQABLgAECgQJCAAOAAAAAA==.Darksuaza:BAAALgAECggJEQAAAA==.Darthwizard:BAAALgADCgIJAgAAAA==.Dasbunk:BAAALgAECgYJEAAAAA==.Dayman:BAAALgADCgYJBgAAAA==.',
De='Deadblue:BAABLgAECn87AAIMAAkJ+xniAwBOAgAMAAkJ+xniAwBOAgAAAA==.Deathblows:BAAALgAECgUJCAAAAA==.Deekay:BAAALgADCgcJFAAAAA==.',
Di='Diogee:BAAALgAECgMJBgAAAA==.Dirge:BAABLgAECn8bAAMPAAkJphHQCQCeAQAPAAgJUBHQCQCeAQAQAAcJfAfJNAAEAQAAAA==.Discipline:BAAALgAECgYJDAABLgAFFAgJJAARACwWAA==.Divinate:BAAALgAECgIJAgAAAA==.',
Dk='Dkpitador:BAAALgADCgEJAQAAAA==.',
Do='Doomhead:BAABLgAECn8YAAICAAgJ2AiAkwBAAQACAAgJ2AiAkwBAAQAAAA==.',
Dr='Drakki:BAAALgADCgUJBQAAAA==.Dreadfaith:BAAALgAECgYJBgAAAA==.',
Du='Durzii:BAACLgAFFH8FAAISAAIJuiLlMACxAAASAAIJuiLlMACxAAAuAAQKfxkAAxIACQmqIKESAH0CABIACAneIaESAH0CAAEAAQntGYdpAU0AAAEuAAUUBAkMABMAHBAA.',
Ea='Eatmybeef:BAAALgADCgYJCgAAAA==.',
Ex='Extinctionus:BAAALgAECgYJCwAAAA==.',
Fe='Fernn:BAAALgADCgQJBAAAAA==.',
Fi='Fia:BAABLgAECn84AAMCAAkJHRMgVwDAAQACAAkJwQ8gVwDAAQATAAgJyxLDGgCHAQAAAA==.',
Fo='Fondra:BAAALgAECgYJBgAAAA==.',
Fu='Furor:BAAALgAECgQJBAABLgAECgkJGwAPAKYRAA==.',
Ge='Genaro:BAAALgAECgIJBwAAAA==.',
Gi='Gibraltar:BAAALgADCgUJBQAAAA==.',
Go='Gokujang:BAAALgAECgcJDgABLgAECgkJJwAUAPQZAA==.Goremont:BAAALgADCgQJBQAAAA==.Gorlok:BAAALgAECgUJBQAAAA==.',
Gr='Greendot:BAACLgAFFH8TAAIIAAQJ1RVBKQAXAQAIAAQJ1RVBKQAXAQAuAAQKfy8AAggACQntIscDAIUDAAgACQntIscDAIUDAAAA.',
Gu='Gulvid:BAACLgAFFH8HAAIEAAIJlx1clACZAAAEAAIJlx1clACZAAAuAAQKfxgAAwQABwlkIUdYAJQBAAQABwlkIUdYAJQBAAwAAQkAAKpcAFgAAAAA.',
Ha='Haluak:BAABLgAECn8rAAIJAAkJtRm2FQA6AgAJAAkJtRm2FQA6AgAAAA==.',
He='Healthyself:BAAALgAECgYJCwAAAA==.',
Ho='Hothawk:BAAALgAECgYJBwABLgAECgkJRQABADobAA==.Houndtamer:BAABLgAECn8/AAIVAAkJ0RZURQDRAQAVAAkJ0RZURQDRAQAAAA==.',
Hp='Hpyflowers:BAAALgADCgQJBAAAAA==.',
Hr='Hruoth:BAAALgAECgYJBgAAAA==.',
Ic='Iceshooting:BAAALgAECgQJBwAAAA==.',
Is='Ishtar:BAABLgAECn8ZAAMWAAYJ9BzVhADIAQAWAAYJCRnVhADIAQAXAAMJzRkuDwDQAAAAAA==.',
It='Itshela:BAACLgAFFH8bAAMCAAcJfxjWKADGAQACAAYJfxjWKADGAQATAAEJAAAjWQAAAAAuAAQKfxsAAgIABwk4I+tNAAkCAAIABwk4I+tNAAkCAAAA.',
Ja='Jayrad:BAABLgAECn8VAAMEAAgJSgnvgQA1AQAEAAgJSgnvgQA1AQADAAQJYQQGGgCnAAAAAA==.',
Je='Jehnovah:BAAALgADCgMJAwAAAA==.Jellybeanz:BAAALgADCggJDQAAAA==.',
Jo='Jordybear:BAAALgAECgQJBAAAAA==.Jorkoh:BAAALgAECgMJBgAAAA==.',
Ju='Juicer:BAAALgADCgMJBgAAAA==.',
Ka='Kaiige:BAAALgAECgQJBAAAAA==.Kairos:BAAALgAECgYJCgAAAA==.Kanê:BAAALgAFFAMJAwAAAA==.',
Ke='Kehlayr:BAAALgADCgMJAwAAAA==.Keiiry:BAAALgADCgMJAwAAAA==.Kenshinth:BAABLgAECn8WAAIWAAcJERRhgAB2AQAWAAcJERRhgAB2AQAAAA==.Kethrym:BAAALgAECgIJAgAAAA==.',
Kh='Khanor:BAAALgAECgYJEQAAAA==.',
Ki='Kiltro:BAAALgAECgQJBgAAAA==.Kimchichi:BAABLgAECn8nAAIBAAkJ2yApDQD7AgABAAkJ2yApDQD7AgAAAA==.Kintaro:BAAALgADCgYJDwAAAA==.Kissmybubble:BAAALgADCgEJAQAAAA==.',
Ko='Kogorko:BAAALgAECgMJBQAAAA==.',
Kr='Kry:BAAALgAECgIJAgAAAA==.',
['Kë']='Këarra:BAAALgAECgQJBwAAAA==.',
La='Labotimizer:BAAALgAECggJDwAAAA==.Lapaladin:BAAALgADCgYJBwAAAA==.Lapriestess:BAAALgAECgYJEQAAAA==.Latoya:BAABLgAFFH8FAAIWAAMJPweDjQC+AAAWAAMJPweDjQC+AAAAAA==.',
Le='Lemontea:BAAALgAFFAEJAQABLgAFFAQJEwAIANUVAA==.',
Li='Lilbeemo:BAAALgAECgUJCgAAAA==.Lilyana:BAAALgAECgYJCwAAAA==.Liongs:BAAALgAECgcJCgABLgAECgcJFgAWABEUAA==.Litharidk:BAABLgAECn8dAAICAAgJ5B8ZNAAuAgACAAgJ5B8ZNAAuAgAAAA==.',
Lo='Lolmasterr:BAAALgAECgEJAQAAAA==.Lotion:BAAALgAECgEJAgAAAA==.Loudog:BAAALgAECgYJBwAAAA==.Loxyblue:BAAALgAECgQJBAAAAA==.',
Lu='Luckyxpain:BAABLgAECn9FAAMBAAkJOht7KgBXAgABAAkJJxt7KgBXAgAYAAcJLBGHGwA7AQAAAA==.',
Ly='Lykos:BAAALgAECgIJAgAAAA==.',
Ma='Madoff:BAAALgAECgQJCAAAAA==.Makok:BAABLgAECn8nAAMZAAkJDxkCBgA7AgAZAAkJDxkCBgA7AgAaAAEJ7AnycQAzAAAAAA==.Malaise:BAAALgAECggJCgABLgAECgkJLgAbAHwgAA==.',
Me='Melancholic:BAABLgAECn8uAAMbAAkJfCBICQDNAgAbAAkJfCBICQDNAgAcAAEJxQTMhAAlAAAAAA==.Mellisa:BAABLgAECn8fAAMCAAkJcxEqcwB9AQACAAgJ2w8qcwB9AQATAAUJdROpKgADAQAAAA==.Memory:BAAALgAECgEJBQAAAA==.',
Mi='Milkingman:BAAALgAFFAIJAgAAAA==.',
Mo='Moltar:BAAALgADCgUJBQAAAA==.Mooshmoo:BAAALgAECgEJAQAAAA==.Morpheus:BAAALgAECgYJBgABLgAFFAMJBwAdABUeAA==.',
Mu='Murog:BAABLgAECn8dAAMKAAgJSQ20TwBzAQAKAAgJSQ20TwBzAQALAAYJPQPvKQCpAAAAAA==.',
Na='Nazarite:BAAALgAECgYJDwAAAA==.',
Ne='Nephlok:BAAALgAECggJCQAAAA==.',
Ni='Nightdisco:BAAALgAECgQJBAAAAA==.',
No='Noctyra:BAAALgAECgQJCAAAAA==.Nomaana:BAAALgAECgMJAwAAAA==.Norael:BAAALgADCgIJAgAAAA==.',
Og='Ogthunder:BAAALgAECgEJAQAAAA==.',
Op='Ophellia:BAAALgAECgEJAQAAAA==.',
Pu='Pureformance:BAAALgADCgcJBwABLgAFFAgJJwAIAFUjAA==.Purrformance:BAACLgAFFH8nAAMIAAgJVSMhAgAsAwAIAAgJVSMhAgAsAwAeAAEJwwaFUQA0AAAuAAQKfyIAAggACQmiJQwBAKcDAAgACQmiJQwBAKcDAAAA.',
Py='Pyrophobiac:BAACLgAFFH8fAAMEAAgJDxnyEQArAgAEAAgJDxnyEQArAgAMAAIJWAJKDwB/AAAuAAQKfyMAAwQACQnaI4ADAIcDAAQACQmYI4ADAIcDAAwABwmhHUcHAFQCAAAA.',
Ra='Ra:BAABLgAECn8qAAIaAAgJbh/+CwBnAgAaAAgJbh/+CwBnAgAAAA==.Radagast:BAACLgAFFH8WAAIfAAQJNw0yUQD6AAAfAAQJNw0yUQD6AAAuAAQKfzEAAx8ACAkQGmMxAAACAB8ACAkzGGMxAAACABoABwmOEwUkAFgBAAAA.Radditz:BAAALgAECgYJCwAAAA==.Rafiki:BAAALgAECgEJAQAAAA==.Rand:BAAALgADCgcJDgAAAA==.',
Ri='Riv:BAAALgAECgMJAwAAAA==.',
Ro='Ronni:BAAALgAECgUJCgAAAA==.Roxyfox:BAAALgAECgYJCwAAAA==.Royvaz:BAABLgAECn8WAAMKAAkJmRZ8IABMAgAKAAkJmRZ8IABMAgALAAQJWgrjLACSAAAAAA==.',
Sa='Salea:BAAALgAECgIJAgAAAA==.Sarryn:BAAALgADCgcJBwAAAA==.',
Sc='Scale:BAAALgAECgMJAwAAAA==.Schwiifty:BAAALgAECgMJDgAAAA==.',
Se='Serik:BAAALgADCgEJAQAAAA==.',
Sh='Shadorodo:BAAALgADCgIJAgAAAA==.Shakaboom:BAAALgAFFAEJAQAAAA==.Shakazoom:BAAALgAECgQJBAAAAA==.Sheffers:BAAALgADCgEJAQAAAA==.Sheffurs:BAABLgAECn87AAIHAAkJ0gOIOwC4AAAHAAkJ0gOIOwC4AAAAAA==.Shepardl:BAACLgAFFH8mAAISAAgJYyUEAQA3AwASAAgJYyUEAQA3AwAuAAQKfyEAAhIACAnkJhoBAIEDABIACAnkJhoBAIEDAAAA.Shredemdown:BAAALgAECgcJCQAAAA==.Shukaku:BAAALgAECgQJBAAAAA==.Shárkbait:BAAALgAECgEJAQABLgAFFAMJBwATAB4LAA==.',
Sk='Skadoosher:BAAALgAECgUJBQAAAA==.Skyratt:BAAALgAECgEJAgAAAA==.',
Sl='Sleepielight:BAAALgAFFAIJBAAAAA==.',
Sm='Smackemz:BAAALgAECgYJCQAAAA==.Smacmywand:BAAALgAECgIJBgAAAA==.',
So='Sollasi:BAAALgADCgMJBgAAAA==.Sortie:BAABLgAECn87AAMSAAkJWA0wLQCqAQASAAkJWA0wLQCqAQABAAgJCwogpwAtAQAAAA==.',
Sp='Spookybolt:BAAALgAECgEJAQAAAA==.Spoons:BAAALgAECgQJBAABLgAFFAUJFgAgAEocAA==.Spyromu:BAAALgAECgUJCwAAAA==.',
St='Stealman:BAAALgADCgcJBwAAAA==.Steeleman:BAAALgADCgQJAgAAAA==.',
Su='Succinic:BAAALgAECggJEAAAAA==.Suffer:BAAALgAECgUJCAAAAA==.',
Sw='Swiss:BAABLgAECn8bAAISAAgJrw1ONACsAQASAAgJrw1ONACsAQAAAA==.',
Sy='Sylphvaria:BAAALgADCgUJBQAAAA==.Syren:BAAALgADCgcJBgAAAA==.',
Te='Tegridy:BAABLgAECn8VAAIVAAYJpBFehQA0AQAVAAYJpBFehQA0AQAAAA==.Teko:BAAALgADCgYJCwAAAA==.',
Th='Thegoose:BAAALgAECgIJAgAAAA==.Themans:BAAALgAECgYJDgAAAA==.Thunderrod:BAABLgAECn8nAAIVAAgJtBfOPgC0AQAVAAgJtBfOPgC0AQAAAA==.',
Ti='Tim:BAAALgAECgMJAwAAAA==.',
To='To:BAAALgAECgIJAgAAAA==.Tovisar:BAAALgAECgMJCQAAAA==.',
Tr='Traessa:BAAALgADCgYJBgAAAA==.',
Tu='Turkturkletn:BAAALgADCgcJEQAAAA==.',
Tw='Twogg:BAAALgAECgYJDgAAAA==.',
Ug='Ugin:BAAALgADCgYJBgAAAA==.Uglykasanova:BAAALgAECgYJEQAAAA==.',
Ul='Ulfrir:BAAALgAECgcJDQAAAA==.',
Va='Vanillamint:BAAALgAECgEJAgAAAA==.Vastian:BAAALgAECgUJDgAAAA==.Vaynard:BAAALgAECgQJBAAAAA==.',
Vi='Violet:BAAALgAECgMJBQAAAA==.Vitre:BAAALgAECgUJBwAAAA==.',
Wa='Walkthrew:BAAALgAECgcJBwAAAA==.Wanshi:BAAALgAECgcJBgAAAA==.Waq:BAABLgAECn8ZAAMDAAgJrRF7AABeAQADAAcJ0BN7AABeAQAEAAEJ2wTOYAEhAAAAAA==.',
We='Wexew:BAACLgAFFH8FAAMLAAIJEx5GEQC0AAALAAIJEx5GEQC0AAAJAAEJngvoWQA2AAAuAAQKfxsAAwsACQkGHGIHAFcCAAsACQnvGmIHAFcCAAkABQkKFb5KAB0BAAAA.Wexwex:BAAALgAFFAIJAwABLgAFFAIJBQALABMeAA==.Wexxew:BAAALgAFFAEJAQABLgAFFAIJBQALABMeAA==.',
Wi='Wishing:BAABLgAECn8bAAISAAgJlBSWHgAOAgASAAgJlBSWHgAOAgAAAA==.',
Wu='Wundertot:BAAALgAECgYJBgABLgAFFAQJCwAWAN8NAA==.Wunderwazard:BAACLgAFFH8LAAIWAAQJ3w0wawANAQAWAAQJ3w0wawANAQAuAAQKfywAAhYACQlVH3MjAI8CABYACQlVH3MjAI8CAAAA.',
Xe='Xevikan:BAABLgAECn8bAAMCAAcJDBVJiQBSAQACAAcJDBVJiQBSAQAhAAEJHwgEQAAnAAAAAA==.',
Ya='Yadead:BAAALgAECgcJDQAAAA==.',
Za='Zangief:BAAALgADCgYJBwAAAA==.Zaylen:BAAALgAECgYJEwABLgAFFAMJBwAdABUeAA==.',
Ze='Zendjin:BAAALgADCgYJDQAAAA==.Zenlore:BAAALgADCgYJBgAAAA==.',
Zi='Zistormstout:BAABLgAECn9AAAIJAAkJ0xzGEwBOAgAJAAkJ0xzGEwBOAgAAAA==.',
Zu='Zuhgonemad:BAAALgAECgQJBgAAAA==.',
['Äl']='Älektra:BAABLgAECn8gAAIfAAgJvATxngDlAAAfAAgJvATxngDlAAAAAA==.',
['Ñe']='Ñeph:BAAALgAECgkJDgAAAA==.',
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
