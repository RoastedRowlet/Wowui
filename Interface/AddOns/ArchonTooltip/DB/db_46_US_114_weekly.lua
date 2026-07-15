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

local lookup = {'Paladin-Retribution','DeathKnight-Unholy','Warlock-Affliction','Warlock-Demonology','Rogue-Assassination','Priest-Holy','Druid-Guardian','Druid-Feral','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Warlock-Destruction','Priest-Shadow','Unknown-Unknown','DeathKnight-Blood','Rogue-Subtlety','Hunter-Survival','Paladin-Holy','Priest-Discipline','Monk-Mistweaver','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','Paladin-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','Monk-Windwalker','Druid-Balance','DemonHunter-Devourer','DeathKnight-Frost',}
local provider = {region='US',realm="Gul'dan",name='US',type='weekly',zone=46,date='2026-07-12',data={Ae='Aeri:BAAALgAECgYJDAAAAA==.',
Al='Alastormoody:BAAALgADCgcJDAAAAA==.Alelover:BAAALgADCgUJBQAAAA==.Allaria:BAABLgAECn8aAAIBAAcJRhAkEAAZAQABAAcJRhAkEAAZAQAAAA==.Almadíon:BAAALgADCgcJCAAAAA==.',
Am='Amosian:BAAALgADCgIJAgAAAA==.',
An='Ana:BAAALgADCgMJAwAAAA==.',
Ao='Aoemomma:BAAALgAECgUJBwAAAA==.',
Ar='Arin:BAAALgAECgIJAwABLgAFFAMJCgACAEEmAA==.',
As='Asuya:BAAALgADCgIJAwAAAA==.',
At='Atreyun:BAAALgAECgEJAQAAAA==.',
Au='Aural:BAAALgAECgkJBgAAAA==.',
Az='Azög:BAAALgADCgUJBQAAAA==.',
Ba='Babysocks:BAAALgAECgYJBgAAAA==.',
Bc='Bc:BAACLgAFFH8HAAMDAAMJ3RmVCgDTAAADAAIJpSKVCgDTAAAEAAIJGRc5jwCmAAAuAAQKfxsAAgQACAn4JjEDAI0DAAQACAn4JjEDAI0DAAAA.',
Be='Beep:BAABLgAECn8lAAIEAAcJRh+JOgAiAgAEAAcJRh+JOgAiAgAAAA==.Belcebut:BAAALgADCgUJBQAAAA==.',
Bl='Blackthunder:BAAALgAECggJDQAAAA==.Blight:BAAALgAECgIJBAABLgAECgkJIgAFADAWAA==.',
Bo='Bobert:BAAALgADCgcJBgAAAA==.Bofadz:BAAALgADCgYJBgAAAA==.Boome:BAAALgAECgYJCwABLgAFFAMJBgABANMJAA==.Boozecruise:BAAALgADCgIJAgAAAA==.Boozedrat:BAAALgAFFAEJAwABLgAFFAYJHAAEAOgaAA==.Bowyn:BAABLgAECn8XAAIGAAYJHhNoOgBSAQAGAAYJHhNoOgBSAQAAAA==.',
Bu='Bubblnbiotch:BAAALgAECgQJBAAAAA==.Budleaf:BAABLgAECn8gAAQHAAYJbBOgCwCJAAAIAAUJ3BOUIwDtAAAHAAYJTQygCwCJAAAJAAEJ1AaD6gAjAAAAAA==.Bunkley:BAABLgAECn8tAAQKAAgJuxNtLwCDAQAKAAgJuxNtLwCDAQALAAYJDQxgeQDzAAAMAAMJTQqrLACUAAAAAA==.Butterknives:BAAALgAECgEJAQAAAA==.Buttshark:BAAALgAECgEJAQAAAA==.',
By='Byege:BAACLgAFFH8cAAMEAAYJ6Bo7LgCMAQAEAAYJvhg7LgCMAQADAAEJThm1DABVAAAuAAQKfycAAwQACQnHH8YYAI8CAAQACQmjH8YYAI8CAA0ABQnOF7IbAHABAAAA.',
Ca='Cantfireme:BAAALgAECgYJEwABLgAFFAMJBgABANMJAA==.Cardhunter:BAAALgADCgYJBgAAAA==.',
Ch='Champilon:BAAALgAECgEJAQAAAA==.Chaoticus:BAAALgAECgYJDQABLgAECggJIgAOAJgOAA==.Charizards:BAAALgADCgYJDQAAAA==.Charmahnder:BAAALgAECgIJAgAAAA==.',
Co='Coma:BAAALgAECgMJBAAAAA==.',
Cr='Crunbard:BAAALgAECggJDwAAAA==.',
Cu='Culdan:BAABLgAECn8aAAMNAAYJ+QkDHQDAAAANAAYJ+QkDHQDAAAAEAAQJlgRh5wCPAAAAAA==.',
Da='Dalirus:BAABLgAFFH8GAAILAAIJIwgSNwBXAAALAAIJIwgSNwBXAAABLgAFFAMJBgABANMJAA==.Danahe:BAAALgAFFAEJAQABLgAFFAIJBAAPAAAAAA==.Darci:BAAALgAECgcJEQABLgAECgQJCAAPAAAAAA==.Darksuaza:BAAALgAECggJEgAAAA==.Darthwizard:BAAALgADCgIJAgAAAA==.Dasbunk:BAABLgAECn8YAAMQAAYJYhQTBQARAQAQAAYJYhQTBQARAQACAAEJkwr4QgAlAAAAAA==.Dayman:BAAALgADCgYJBgAAAA==.',
De='Deadblue:BAABLgAECn87AAINAAkJ+xniAwBOAgANAAkJ+xniAwBOAgAAAA==.Deathblows:BAAALgAECgUJCAAAAA==.Deekay:BAAALgADCgcJFAAAAA==.',
Di='Diogee:BAAALgAECgMJBgAAAA==.Dirge:BAABLgAECn8iAAMFAAkJMBYcCADOAQAFAAgJJhQcCADOAQARAAcJOgo4CQClAAAAAA==.Discipline:BAAALgAECgYJDAABLgAFFAgJJAASACwWAA==.Divinate:BAAALgAECgIJAgAAAA==.',
Dk='Dkpitador:BAAALgADCgEJAQAAAA==.',
Do='Doomhead:BAABLgAECn8YAAICAAgJ2AiBkwBAAQACAAgJ2AiBkwBAAQAAAA==.',
Dr='Drakki:BAAALgADCgUJBQAAAA==.Dreadfaith:BAAALgAECgYJBgAAAA==.',
Du='Durzii:BAACLgAFFH8FAAITAAIJuiLnMACxAAATAAIJuiLnMACxAAAuAAQKfxkAAxMACQmqIKESAH0CABMACAneIaESAH0CAAEAAQntGY1pAU0AAAEuAAUUBAkNABAADxMA.',
Ea='Eatmybeef:BAAALgADCgYJCgAAAA==.',
Ev='Evilynn:BAAALgAECgMJAwAAAA==.',
Ex='Extinctionus:BAAALgAECgcJDQAAAA==.',
Fe='Fernn:BAAALgADCgQJBAAAAA==.',
Fi='Fia:BAACLgAFFH8GAAICAAMJ4xZqVACRAAACAAMJ4xZqVACRAAAuAAQKfzgAAwIACQkdEyJXAMABAAIACQnBDyJXAMABABAACAnLEsUaAIcBAAAA.',
Fo='Fondra:BAAALgAECgkJBgAAAA==.',
Fu='Furor:BAAALgAECgQJBAABLgAECgkJIgAFADAWAA==.',
Ge='Genaro:BAAALgAECgIJBwAAAA==.',
Gi='Gibraltar:BAAALgADCgUJBQAAAA==.',
Go='Gokujang:BAAALgAECgcJEgABLgAECgkJKgAUACYbAA==.Goremont:BAAALgADCgQJBQAAAA==.Gorlok:BAAALgAECgUJBQAAAA==.',
Gr='Greendot:BAACLgAFFH8UAAIJAAQJ1RU4KQAXAQAJAAQJ1RU4KQAXAQAuAAQKfy8AAgkACQntIscDAIUDAAkACQntIscDAIUDAAEuAAUUBQkKABUAvhgA.',
Gu='Gulvid:BAACLgAFFH8HAAIEAAIJlx1HlACZAAAEAAIJlx1HlACZAAAuAAQKfxgAAwQABwlkIUZYAJQBAAQABwlkIUZYAJQBAA0AAQkAAKpcAFgAAAEuAAUUCAkcAAQAPhQA.',
Ha='Haluak:BAABLgAECn8uAAIKAAkJphq1FQA6AgAKAAkJphq1FQA6AgAAAA==.',
He='Healthyself:BAAALgAECgcJDQAAAA==.',
Hi='Hinamoria:BAAALgAECgUJBwAAAA==.',
Ho='Hothawk:BAAALgAECgYJDAABLgAFFAMJBgABANMJAA==.Hottah:BAAALgADCgEJAQAAAA==.Houndtamer:BAABLgAECn9KAAIWAAkJuRcpCgB7AQAWAAkJuRcpCgB7AQAAAA==.',
Hp='Hpyflowers:BAAALgADCgQJBAAAAA==.',
Hr='Hruoth:BAAALgAECgYJBgAAAA==.',
Ic='Iceshooting:BAAALgAECgQJBwAAAA==.',
Is='Ishtar:BAABLgAECn8ZAAMXAAYJ9BzVhADIAQAXAAYJCRnVhADIAQAYAAMJzRkuDwDQAAAAAA==.',
It='Itshela:BAACLgAFFH8bAAMCAAcJfxjCKADGAQACAAYJfxjCKADGAQAQAAEJAAAiWQAAAAAuAAQKfx8AAgIACQl+IvEHAHgBAAIACQl+IvEHAHgBAAAA.',
Ja='Jayrad:BAABLgAECn8XAAMEAAgJ7grzgQA1AQAEAAgJSgnzgQA1AQADAAQJyQkGGgCnAAAAAA==.',
Je='Jehnovah:BAAALgADCgMJAwAAAA==.Jellybeanz:BAAALgADCggJDQAAAA==.',
Jo='Jordybear:BAAALgAECgQJBAAAAA==.Jorkoh:BAAALgAECgMJBgAAAA==.',
Ju='Juicer:BAAALgADCgMJBgAAAA==.',
Ka='Kaiige:BAAALgAECgQJBAAAAA==.Kairos:BAAALgAECgYJCgAAAA==.Kanê:BAAALgAFFAMJAwAAAA==.',
Ke='Kehlayr:BAAALgADCgMJAwAAAA==.Keiiry:BAAALgADCgMJAwAAAA==.Kenshinth:BAABLgAECn8YAAIXAAcJbxRfgAB2AQAXAAcJbxRfgAB2AQAAAA==.Kethrym:BAAALgAECgIJAgAAAA==.',
Kh='Khanor:BAAALgAECgYJEQAAAA==.',
Ki='Kiltro:BAAALgAECgQJBgAAAA==.Kimchichi:BAABLgAECn8qAAIBAAkJDiErDQD7AgABAAkJDiErDQD7AgAAAA==.Kintaro:BAAALgADCgYJDwAAAA==.Kissmybubble:BAAALgADCgEJAQAAAA==.',
Ko='Kogorko:BAAALgAECgMJBQAAAA==.',
Kr='Kry:BAAALgAECgIJAgAAAA==.',
['Kë']='Këarra:BAAALgAECgQJBwAAAA==.',
La='Labotimizer:BAAALgAECggJDwAAAA==.Lapaladin:BAAALgADCgYJBwAAAA==.Lapriestess:BAAALgAECgcJEgAAAA==.Latoya:BAABLgAFFH8FAAIXAAMJPwdmjQC+AAAXAAMJPwdmjQC+AAAAAA==.',
Le='Lemontea:BAACLgAFFH8KAAIVAAUJvhhHDQB1AQAVAAUJvhhHDQB1AQAuAAQKfxUAAhUABgn1HgMDABECABUABgn1HgMDABECAAAA.',
Li='Lilbeemo:BAAALgAECgUJCgAAAA==.Lilyana:BAAALgAECgYJDQAAAA==.Liongs:BAAALgAECgcJEQABLgAECgcJGAAXAG8UAA==.Litharidk:BAABLgAECn8dAAICAAgJ5B8aNAAuAgACAAgJ5B8aNAAuAgAAAA==.',
Lo='Lollmaster:BAAALgAECgMJAwAAAA==.Lolmasterr:BAAALgAECgYJCwAAAA==.Lotion:BAAALgAFFAEJAQAAAA==.Loudog:BAAALgAECgYJBwAAAA==.Loxyblue:BAAALgAECgQJBAAAAA==.',
Lu='Luckyxpain:BAACLgAFFH8GAAIBAAMJ0wkaLgC5AAABAAMJ0wkaLgC5AAAuAAQKf04AAwEACQkTHHgqAFcCAAEACQkBHHgqAFcCABkACAltEocbADsBAAAA.',
Ly='Lykos:BAAALgAECgIJAgAAAA==.',
Ma='Madoff:BAAALgAECgQJCAAAAA==.Makok:BAABLgAECn8nAAMaAAkJDxkDBgA7AgAaAAkJDxkDBgA7AgAbAAEJ7AnycQAzAAAAAA==.Makoks:BAAALgAECgQJBAAAAA==.Malaise:BAAALgAECggJCgABLgAECgkJMAAcAP4gAA==.Marcey:BAAALgADCgYJBgAAAA==.Marsvolta:BAAALgAECgkJCwAAAA==.',
Me='Melancholic:BAABLgAECn8wAAMcAAkJ/iBKCQDNAgAcAAkJ/iBKCQDNAgAdAAEJxQTMhAAlAAAAAA==.Mellisa:BAABLgAECn8fAAMCAAkJcxEscwB9AQACAAgJ2w8scwB9AQAQAAUJdROsKgADAQAAAA==.Memory:BAAALgAECgEJBgAAAA==.',
Mi='Milkingman:BAAALgAFFAIJAgAAAA==.',
Mm='Mmnmjomg:BAAALgAECgEJAQAAAA==.',
Mo='Moltar:BAAALgADCgUJBQAAAA==.Mooshmoo:BAAALgAECgEJAQAAAA==.Morpheus:BAAALgAECgYJBwABLgAFFAMJCgAeAA0hAA==.',
Mu='Murog:BAABLgAECn8dAAMLAAgJSQ25TwBzAQALAAgJSQ25TwBzAQAMAAYJPQPwKQCpAAAAAA==.',
Na='Nazarite:BAAALgAECgYJDwAAAA==.',
Ne='Nephlok:BAAALgAECggJCQAAAA==.Nero:BAAALgAFFAEJAQAAAA==.',
Ni='Nightdisco:BAAALgAECgQJBAAAAA==.',
No='Noctyra:BAAALgAECgQJCAAAAA==.Nokthrog:BAAALgAECgEJAQAAAA==.Nomaana:BAAALgAECgMJAwAAAA==.Norael:BAAALgADCgIJAgAAAA==.',
Og='Ogthunder:BAAALgAECgEJAgAAAA==.',
Op='Ophellia:BAAALgAECgEJAQAAAA==.',
Pa='Painfel:BAAALgAECgEJAQABLgAECggJFgALAJkZAA==.',
Po='Poodie:BAAALgADCgEJAQAAAA==.',
Pu='Pureformance:BAAALgADCgcJBwABLgAFFAkJKAAJALAhAA==.Purrformance:BAACLgAFFH8oAAMJAAkJsCEhAgAsAwAJAAkJsCEhAgAsAwAfAAEJwwaBUQA0AAAuAAQKfyIAAgkACQmiJQwBAKcDAAkACQmiJQwBAKcDAAAA.',
Py='Pyrophobiac:BAACLgAFFH8fAAMEAAgJDxnhEQArAgAEAAgJDxnhEQArAgANAAIJWAJKDwB/AAAuAAQKfyMAAwQACQnaI4ADAIcDAAQACQmYI4ADAIcDAA0ABwmhHUcHAFQCAAAA.',
Ra='Ra:BAABLgAECn8sAAIbAAgJbh/9CwBnAgAbAAgJbh/9CwBnAgAAAA==.Radagast:BAACLgAFFH8aAAIgAAQJLRBoIADqAAAgAAQJLRBoIADqAAAuAAQKfzMAAyAACQlJGmExAAACACAACQmoGGExAAACABsABwmOEwgkAFgBAAAA.Radditz:BAAALgAECgYJCwAAAA==.Rafiki:BAAALgAECgEJAQAAAA==.Rand:BAAALgADCgcJDgAAAA==.',
Ri='Riv:BAAALgAECgMJAwAAAA==.',
Ro='Ronni:BAAALgAECgUJCwAAAA==.Roxyfox:BAAALgAECgcJDQAAAA==.Royvaz:BAABLgAECn8cAAMLAAkJwBfHBADcAQALAAkJwBfHBADcAQAMAAUJzBmzBADtAAAAAA==.',
Sa='Salea:BAAALgAECgIJAgAAAA==.Sarryn:BAAALgADCgcJBwAAAA==.',
Sc='Scale:BAAALgAECgMJAwAAAA==.Schwiifty:BAAALgAECgMJDwAAAA==.',
Se='Serica:BAAALgAECgkJBgAAAA==.Serik:BAAALgADCgEJAQAAAA==.',
Sh='Shadorodo:BAAALgADCgIJAgAAAA==.Shakaboom:BAAALgAFFAEJAQAAAA==.Shakazoom:BAAALgAECgQJBAAAAA==.Shammyhaggar:BAAALgADCgYJBgAAAA==.Shanzian:BAAALgAECgUJCAAAAA==.Sheffers:BAAALgADCgEJAgAAAA==.Sheffurs:BAABLgAECn87AAIHAAkJ0gOJOwC4AAAHAAkJ0gOJOwC4AAAAAA==.Shepardl:BAACLgAFFH8mAAITAAgJYyUCAQA3AwATAAgJYyUCAQA3AwAuAAQKfyEAAhMACAnkJhoBAIEDABMACAnkJhoBAIEDAAAA.Shmorc:BAAALgAECgQJBAAAAA==.Shredemdown:BAAALgAECgcJCQAAAA==.Shukaku:BAAALgAECgQJBQAAAA==.Shárkbait:BAAALgAECgEJAQABLgAFFAMJBwAQAB4LAA==.',
Sk='Skadoosher:BAAALgAECgUJBQAAAA==.Skyratt:BAAALgAECgEJAgAAAA==.',
Sl='Sleepielight:BAABLgAFFH8FAAIBAAIJaxH0jQCWAAABAAIJaxH0jQCWAAAAAA==.',
Sm='Smackemz:BAAALgAECgYJCQAAAA==.Smacmywand:BAAALgAECgIJBgAAAA==.',
So='Sollasi:BAAALgADCgMJBgAAAA==.Sortie:BAACLgAFFH8JAAMTAAUJtAXVCgAdAQATAAUJtAXVCgAdAQABAAQJ4gHdlwCHAAAuAAQKfzsAAxMACQlYDTQtAKoBABMACQlYDTQtAKoBAAEACAkLCiCnAC0BAAAA.',
Sp='Spookybolt:BAAALgAECgEJAQAAAA==.Spoons:BAAALgAECgQJBAABLgAFFAUJFgAVAEocAA==.Spyromu:BAAALgAECgUJCwAAAA==.',
St='Stealman:BAAALgADCgcJBwAAAA==.Steeleman:BAAALgADCgQJAgAAAA==.',
Su='Succinic:BAAALgAECggJEAAAAA==.Suffer:BAAALgAECgUJCAAAAA==.',
Sw='Swiss:BAABLgAECn8bAAITAAgJrw1ONACsAQATAAgJrw1ONACsAQAAAA==.',
Sy='Sylphvaria:BAAALgAECgIJAgAAAA==.Syren:BAAALgADCgcJBgAAAA==.',
Te='Tegridy:BAABLgAECn8WAAIWAAYJ4BFbhQA0AQAWAAYJ4BFbhQA0AQAAAA==.Teko:BAAALgADCgYJCwAAAA==.Tetsuma:BAAALgADCgIJAgAAAA==.',
Th='Thegoose:BAAALgAECgIJAgAAAA==.Themans:BAAALgAECgYJDgAAAA==.Thunderrod:BAABLgAECn8nAAIWAAgJtBfOPgC0AQAWAAgJtBfOPgC0AQAAAA==.',
Ti='Tim:BAAALgAECgYJCAAAAA==.',
To='To:BAAALgAECgIJAgAAAA==.Tovisar:BAAALgAECgMJCQAAAA==.',
Tr='Traessa:BAAALgAECgEJAQAAAA==.',
Tu='Turkturkletn:BAAALgADCgcJEQAAAA==.',
Tw='Twogg:BAAALgAECgYJDgAAAA==.',
Ug='Ugin:BAAALgADCgYJBgAAAA==.Uglykasanova:BAAALgAECgYJEQAAAA==.',
Ul='Ulfrir:BAAALgAECgcJDQAAAA==.',
Un='Ungawdlyluck:BAAALgADCgYJBgABLgAFFAMJBgABANMJAA==.',
Va='Valindra:BAAALgAECgkJCQAAAA==.Vanillamint:BAAALgAECgEJAgAAAA==.Vastian:BAAALgAECgUJDgAAAA==.Vaynard:BAAALgAECgQJBAAAAA==.',
Vi='Violet:BAAALgAECgMJBQAAAA==.Vitre:BAAALgAECgUJBwAAAA==.',
Wa='Walkthrew:BAAALgAFFAIJBAAAAA==.Wanshi:BAAALgAECgcJBgAAAA==.Waq:BAABLgAECn8ZAAMDAAgJrREmAgBRAQADAAcJ0BMmAgBRAQAEAAEJ2wTOYAEhAAAAAA==.Watbhappn:BAAALgADCgYJBgAAAA==.',
We='Wexew:BAACLgAFFH8FAAMMAAIJEx5EEQC0AAAMAAIJEx5EEQC0AAAKAAEJngvmWQA2AAAuAAQKfxsAAwwACQkGHGIHAFcCAAwACQnvGmIHAFcCAAoABQkKFb5KAB0BAAAA.Wexo:BAAALgAECgEJAQABLgAFFAIJBQAMABMeAA==.Wexwex:BAAALgAFFAIJBAABLgAFFAIJBQAMABMeAA==.Wexxew:BAAALgAFFAEJAQABLgAFFAIJBQAMABMeAA==.',
Wi='Wishing:BAABLgAECn8cAAITAAgJlBSVHgAOAgATAAgJlBSVHgAOAgAAAA==.',
Wu='Wundertot:BAAALgAECgYJBgABLgAFFAQJDQAXAN8NAA==.Wunderwazard:BAACLgAFFH8NAAIXAAQJ3w0WawANAQAXAAQJ3w0WawANAQAuAAQKfywAAhcACQlVH3AjAI8CABcACQlVH3AjAI8CAAAA.',
Xe='Xevikan:BAABLgAECn8bAAMCAAcJDBVJiQBSAQACAAcJDBVJiQBSAQAhAAEJHwgEQAAnAAAAAA==.',
Ya='Yadead:BAAALgAECgcJDQAAAA==.',
Za='Zaeren:BAAALgAECgUJBgABLgAFFAMJCgAeAA0hAA==.Zangief:BAAALgADCgYJBwAAAA==.Zaylen:BAAALgAECgYJEwABLgAFFAMJCgAeAA0hAA==.',
Ze='Zendjin:BAAALgADCgYJDQAAAA==.Zenlore:BAAALgADCgYJBgAAAA==.Zerog:BAAALgAECgQJBAAAAA==.',
Zi='Zistormstout:BAABLgAECn9LAAIKAAkJ2R1nAgD1AQAKAAkJ2R1nAgD1AQAAAA==.',
Zu='Zuhgonemad:BAAALgAECgQJBgAAAA==.',
['Äl']='Älektra:BAABLgAECn8gAAIgAAgJvATyngDlAAAgAAgJvATyngDlAAAAAA==.',
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
