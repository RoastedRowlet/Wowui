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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane','Monk-Windwalker','Rogue-Subtlety','Rogue-Assassination','Hunter-Marksmanship','Warrior-Arms','Priest-Holy','Priest-Shadow','Warlock-Demonology','Paladin-Retribution','Paladin-Holy','Shaman-Elemental','Monk-Brewmaster','DeathKnight-Blood','Druid-Balance','Warlock-Affliction','Warlock-Destruction','Paladin-Protection','Warrior-Protection','DemonHunter-Havoc','Warrior-Fury','Mage-Frost','Priest-Discipline','Druid-Restoration','DemonHunter-Devourer','Evoker-Devastation','Hunter-Survival','Druid-Guardian','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abracadavr:BAAANQADCgUICQAAAA==.Absolomb:BAAANQABCgMIAwAAAA==.',
Ac='Acell:BAABNQAECn94AAIBAAoKfiNTBQC4AwABAAoKfiNTBQC4AwAAAA==.',
Ad='Addison:BAAANQAECgUICQAAAA==.Adeleas:BAAANQADCggIFgABNQAECgUICQACAAAAAA==.Adêrna:BAABNQAECn82AAIDAAkKFRwyEwCyAgADAAkKFRwyEwCyAgAAAA==.',
Ag='Agate:BAABNQAECn8XAAIEAAoKIQT4GgCpAAAEAAoKIQT4GgCpAAAAAA==.Agba:BAABNQAECn8jAAMFAAkKmxMmUQDPAQAFAAkKmxMmUQDPAQAGAAEKqAn2tgAoAAAAAA==.Aglain:BAAANQADCgMIAwAAAA==.',
Ai='Aibrean:BAAANQAECgUICwAAAA==.Aiché:BAAANQADCgUIBQAAAA==.',
Ak='Aksul:BAAANQADCggICwAAAA==.',
Al='Alaala:BAAANQADCgUIBQAAAA==.Alaidan:BAAANQAECgUIBwAAAA==.Alanus:BAABNQAECn8wAAIHAAkKpA4ZWwCcAQAHAAkKpA4ZWwCcAQAAAA==.Alarion:BAAANQAECgUICgAAAA==.Aliën:BAAANQAECgQICgAAAA==.Altana:BAAANQAECgIIAgABNQAECgcICAACAAAAAA==.Alydrus:BAAANQADCgcICAAAAA==.',
An='Angryelf:BAAANQAECgIIAwAAAA==.Angrymanjibs:BAAANQAECgIIAwAAAA==.Anitasummon:BAAANQADCgUIDAAAAA==.Annahe:BAABNQAECn8tAAIIAAkKMhijEADbAQAIAAkKMhijEADbAQAAAA==.Annale:BAAANQADCgYIBgABNQAECgkJLQAIADIYAA==.Anub:BAABNQAECn8lAAMJAAoKLBOwKgDWAQAJAAkKMRSwKgDWAQAKAAcKww1/TACPAQAAAA==.Anzala:BAAANQAECgMIBAAAAA==.',
Ar='Armsmaster:BAABNQAECn84AAMFAAoKHR/aJgCgAgAFAAoKHR/aJgCgAgAGAAEK9ROspwA+AAAAAA==.Arrann:BAAANQAECgUICgAAAA==.Artemistha:BAAANQAECgYIDgAAAA==.',
Av='Avengharambe:BAAANQADCggIDwAAAA==.Avielle:BAAANQADCgUIBQAAAA==.',
Aw='Awakemage:BAAANQADCgYIBgAAAA==.',
['Aø']='Aøi:BAACNQAFFH8aAAIIAAcKKR31AQB/AgAIAAcKKR31AQB/AgA1AAQKfysAAggACgpsJcoDAAsDAAgACgpsJcoDAAsDAAAA.',
Ba='Baey:BAAANQABCgEIAQAAAA==.Bam:BAABNQAECn8WAAIHAAkKZxlaSQDWAQAHAAkKZxlaSQDWAQAAAA==.Barelycastin:BAABNQAECn80AAIDAAkKMQ+IQACVAQADAAkKMQ+IQACVAQAAAA==.',
Be='Beautiful:BAAANQAECgQIBAAAAA==.Beleriand:BAAANQAECgYIEQAAAA==.Belgarathh:BAAANQAECgYICgAAAA==.Bellei:BAAANQADCgcIBwAAAA==.Bellíon:BAAANQADCgEIAQAAAA==.',
Bl='Blacat:BAABNQAECn8WAAIEAAkKqA84EAAHAgAEAAkKqA84EAAHAgAAAA==.Blacksirloin:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.Bloodshunter:BAABNQAECn8bAAMBAAkKah4uOADCAgABAAgK8SAuOADCAgALAAUK5g9iUADqAAAAAA==.Blutauren:BAAANQAECgYICgAAAA==.',
Bo='Borda:BAAANQAECgUICgAAAA==.',
Br='Brendenhunt:BAAANQADCggICAAAAA==.Broomhilda:BAAANQABCggIDAAAAA==.',
Bu='Buddypal:BAAANQAECgMIAwAAAA==.Buddypriest:BAAANQADCgIIAgABNQAECgMIAwACAAAAAA==.',
['Bâ']='Bâm:BAAANQAECgUICQABNQAECgkJFgAHAGcZAA==.',
Ca='Caidi:BAAANQAECgQIBgAAAA==.Carini:BAABNQAECn8oAAIHAAgKTBFFcgBgAQAHAAgKTBFFcgBgAQAAAA==.Catheryne:BAAANQAECgQIBAAAAA==.',
Ch='Chelsgrin:BAAANQAECgUICQABNQAECggIFAAMAHYbAA==.Chickynuggy:BAAANQADCgcIBwAAAA==.Chrischan:BAAANQABCgMIAQAAAA==.Chónk:BAAANQAECgUICQAAAA==.',
Cl='Clûtch:BAABNQAECn8fAAIFAAkKKxxeJQCqAgAFAAkKKxxeJQCqAgAAAA==.',
Co='Corvax:BAAANQADCgYIBgAAAA==.Corynthe:BAABNQAECn8wAAINAAgK5h4jJgA5AgANAAgK5h4jJgA5AgAAAA==.',
Cr='Crickie:BAAANQAECgQICQAAAA==.Croftypongue:BAAANQADCgcIBwAAAA==.Crovaxis:BAABNQAECn8xAAILAAkKLBlmDgDmAQALAAkKLBlmDgDmAQAAAA==.',
Da='Daddychill:BAAANQAECgUIBQAAAA==.Daedrìc:BAAANQADCgQIBAAAAA==.Damagetaken:BAAANQAECgYIDAAAAA==.Darktalyn:BAABNQAECn80AAMOAAkKVwwYFwBhAQAOAAkKVwwYFwBhAQANAAIKZgnxsQBeAAAAAA==.Dawi:BAAANQAECgIIAgAAAA==.',
De='Deathgrip:BAAANQADCgUIBgAAAA==.Deathhawkzz:BAABNQAECn8pAAIPAAkKORzPSwBwAgAPAAkKORzPSwBwAgAAAA==.Deekura:BAABNQAECn8mAAIFAAgKUQ2pIgBfAQAFAAgKUQ2pIgBfAQAAAA==.Deeyon:BAAANQAECgIIAwAAAA==.Delusion:BAAANQADCgEIAQAAAA==.Demmin:BAAANQAECgcIBwAAAA==.Dezireth:BAABNQAECn8wAAIBAAoKtAufiQD3AQABAAoKtAufiQD3AQAAAA==.',
Dh='Dhakastyr:BAAANQAECggICAAAAA==.',
Di='Dinak:BAAANQADCggIGwAAAA==.Dionan:BAABNQAECn8uAAIQAAkK/Q4DfQBXAQAQAAkK/Q4DfQBXAQAAAA==.',
Do='Docs:BAABNQAECn8nAAMRAAoKeRdkHgBSAgARAAoKeRdkHgBSAgAQAAYKMwts+QArAQAAAA==.Doks:BAABNQAECn8yAAMDAAoK6xrmJAAlAgADAAoK6xrmJAAlAgASAAEKAAD4MAE4AAAAAA==.',
Dr='Dragana:BAAANQAECgEIAwAAAA==.Dragster:BAAANQAECgYIBwAAAA==.Dragõn:BAAANQADCgEIAQAAAA==.Dreadmyr:BAAANQADCgUIBQAAAA==.Dreamfýre:BAAANQABCgIIAgAAAA==.Dridae:BAAANQAECgEIAQAAAA==.Drusilvia:BAAANQADCgcIBwAAAA==.',
Ea='Ealara:BAAANQADCggIDwAAAA==.',
Ec='Echidna:BAAANQADCggICAABNQAFFAcIGwARAPwBAA==.',
El='Elendor:BAAANQABCgYICQAAAA==.',
Em='Emiira:BAAANQADCggIFQAAAA==.',
En='Enthaii:BAAANQAECgEIAQAAAA==.',
Er='Erithil:BAAANQADCgYIBgABNQAECggIGwARANQYAA==.',
Es='Espe:BAABNQAECn8tAAITAAkK2RZfBgClAQATAAkK2RZfBgClAQAAAA==.',
Eu='Euli:BAAANQADCgMIBAABNQAFFAYIGgAUADQYAA==.',
Ev='Everayn:BAABNQAECn8+AAMRAAcKbRV1bQDPAQARAAcKbRV1bQDPAQAQAAUK7AmCFAH9AAABNQAECgoKeAABAH4jAA==.',
Ex='Exhalo:BAABNQAECn8rAAIMAAoKFBUPcQBAAgAMAAoKFBUPcQBAAgAAAA==.Exil:BAAANQAECgQIBgAAAA==.',
Fa='Fallen:BAABNQAECn8bAAIVAAkKQBRFQgDuAQAVAAkKQBRFQgDuAQAAAA==.Fallenvoid:BAAANQADCgEIAQAAAA==.Fangg:BAAANQAECgQIBgAAAA==.Fasebreaker:BAAANQABCggIDgAAAA==.Faynor:BAABNQAECn8pAAITAAgKtSERBQAWAwATAAgKtSERBQAWAwAAAA==.Faynór:BAAANQAECgcIBwABNQAECggIKQATALUhAA==.',
Fe='Felwhisper:BAAANQAECgUIBQAAAA==.',
Fi='Finalycalm:BAAANQAECgUIBAAAAA==.Finimus:BAAANQAECgIJAgAAAA==.Finlok:BAAANQABCgMIAgAAAA==.Firêfly:BAAANQAECgUIBQAAAA==.',
Fl='Flingpooh:BAAANQAECgYIDgAAAA==.Flloran:BAABNQAECn8aAAIVAAYKGQccPgDNAAAVAAYKGQccPgDNAAAAAA==.',
Fr='Fraggle:BAECNQAFFH8UAAIRAAYKARLYDACSAQARAAYKARLYDACSAQA1AAQKfzsAAxEACgqaHc0fAPACABEACgqaHc0fAPACABAABgrqEYm/AN0AAAAA.Frogchi:BAAANQAECgUIEQAAAA==.Frostbité:BAAANQAECgQIBAAAAA==.Fruit:BAAANQAECgQICAAAAA==.',
Fu='Fubarut:BAAANQADCggICAAAAA==.Fumikiko:BAAANQADCgYICgABNQAECgcICAACAAAAAA==.Funnybluffy:BAAANQAECgEIAQAAAA==.Fuzzbâll:BAAANQABCgYICQAAAA==.',
['Fí']='Físh:BAAANQADCgcICAABNQAECgcICAACAAAAAA==.',
Ga='Gali:BAAANQAECgEIAQAAAA==.Gargybyn:BAAANQADCgUIBwAAAA==.',
Gi='Girliepop:BAAANQAECgYICQAAAA==.',
Gl='Glaistiguain:BAABNQAECn8xAAQWAAoK5R+sAwC2AgAWAAkKoh+sAwC2AgAXAAUKRSEjBABqAQAPAAEKAACHOAFFAAABNQAECgoKOAAFAB0fAA==.Glifin:BAAANQAECggIDwAAAA==.Glizzeldra:BAAANQADCgUIBQAAAA==.Gloomstalkin:BAAANQAECgQICQABNQAECgkJOQAUAI4UAA==.Glynna:BAAANQADCgUIBQAAAA==.',
Go='Gooning:BAABNQAECn8VAAMYAAoKOiEMAwAJAwAYAAoKOiEMAwAJAwAQAAEKlA0wlwE9AAABNQAFFAYICwAUAE4WAA==.',
Gr='Gr:BAABNQAECn8vAAIKAAkKeQnOEAB9AQAKAAkKeQnOEAB9AQAAAA==.Gryffs:BAABNQAECn8nAAMZAAkKdh0VBwD5AQAZAAkKdh0VBwD5AQAMAAgKlg6urACtAQAAAA==.Gràvity:BAAANQAECgQIAwAAAA==.',
Gu='Guanino:BAAANQADCggIDQAAAA==.Gutts:BAAANQAECgIIAQABNQAECggIKgAJADsfAA==.',
Gw='Gworg:BAAANQADCgEIAQAAAA==.',
['Gì']='Gìzmo:BAAANQAECgQIBQAAAA==.',
Ha='Halartion:BAABNQAECn8UAAIMAAgKdhsragBSAgAMAAgKdhsragBSAgAAAA==.Happirogue:BAAANQAECgYIBgABNQAFFAYIFAAaAM0dAA==.Haruun:BAAANQAECgQIBgAAAA==.',
He='Helridden:BAABNQAECn8XAAIMAAcKFQfmfwAUAQAMAAcKFQfmfwAUAQAAAA==.Hesmydaddy:BAABNQAECn83AAINAAkK9waITwBzAQANAAkK9waITwBzAQAAAA==.',
Ho='Hoztok:BAAANQAECgQIBAAAAA==.',
Ic='Icemann:BAAANQABCggICAAAAA==.',
Im='Imherdaddy:BAABNQAECn85AAIUAAkKjhRXIgCBAQAUAAkKjhRXIgCBAQAAAA==.',
It='Itakemeds:BAAANQADCgYJDAABNQAECgMIBAACAAAAAA==.',
Ja='Jaderean:BAAANQAECgMJAwAAAA==.Jake:BAAANQAECgMIAwABNQAECgoKKgAbAMQYAA==.Jarrack:BAABNQAECn8wAAMHAAgKjxQFagB0AQAHAAgKlxEFagB0AQAcAAQKrBaaIQDcAAAAAA==.Jaye:BAAANQABCgUICQAAAA==.',
Je='Jessicae:BAABNQAECn8kAAMNAAkKGBifRgCWAQANAAkKGBifRgCWAQAdAAEKfg2oKgAvAAAAAA==.Jeuno:BAAANQADCggIDgABNQAECgcICAACAAAAAA==.',
Ji='Jivederpy:BAABNQAECn8lAAIMAAkK+RvTMgALAgAMAAkK+RvTMgALAgAAAA==.',
Ju='Juicybooty:BAAANQADCgYIDAAAAA==.Junazeena:BAABNQAECn8ZAAMSAAcKzQQYuwAcAQASAAcKzQQYuwAcAQADAAYKdAO6zgDKAAAAAA==.',
Ka='Kayfabe:BAABNQAECn8jAAIHAAoK9ATwDgF0AQAHAAoK9ATwDgF0AQAAAA==.',
Ke='Keirasti:BAAANQAECgUICQAAAA==.Keishilda:BAAANQAECgQIBAAAAA==.Keladria:BAAANQAECgUICQAAAA==.Kelirra:BAAANQAECgQIBAAAAA==.Kenel:BAABNQAECn84AAIVAAkKZRD2HgCQAQAVAAkKZRD2HgCQAQAAAA==.Kerea:BAABNQAECn8wAAIeAAgKRQWFLgDwAAAeAAgKRQWFLgDwAAAAAA==.Kermitt:BAAANQADCgQIBAAAAA==.Keyarga:BAAANQADCgYICgABNQAECgcIDgACAAAAAA==.',
Kh='Khazadoom:BAAANQAECgUICQAAAA==.Khazargon:BAABNQAECn8YAAIQAAoK7heXYQCWAQAQAAoK7heXYQCWAQAAAA==.',
Ki='Kicken:BAABNQAECn8qAAMXAAgK8BGDEwB9AAAPAAYKMw+OfwD3AAAXAAIKaReDEwB9AAAAAA==.Kiitsuna:BAAANQADCgYIBgAAAA==.Kittyflerp:BAAANQADCgEJAQAAAA==.Kittyperry:BAAANQAECggIEgAAAA==.Kizmo:BAAANQADCgQIBAAAAA==.',
Ko='Korthelan:BAABNQAECn83AAIfAAkK1xSHFwB+AQAfAAkK1xSHFwB+AQAAAA==.Kothara:BAABNQAECn8vAAIBAAgKBxW/awA7AgABAAgKBxW/awA7AgAAAA==.',
Kr='Krimzin:BAACNQAFFH8OAAIBAAcKFRjSCwCSAQABAAcKFRjSCwCSAQA1AAQKfzIAAgEACgpLJewgABMDAAEACgpLJewgABMDAAAA.Krystine:BAAANQAECgUIDQAAAA==.',
Ks='Kserasera:BAABNQAECn8uAAIVAAoKLRHNPAAQAgAVAAoKLRHNPAAQAgAAAA==.',
Ku='Kuball:BAABNQAECn8qAAIJAAgKOx+bDwCCAgAJAAgKOx+bDwCCAgAAAA==.Kuchiki:BAAANQADCgEIAQAAAA==.Kukuruku:BAAANQAECgUIBQAAAA==.Kumari:BAABNQAECn8pAAIDAAoKSQHw0gDBAAADAAoKSQHw0gDBAAAAAA==.Kungfü:BAAANQADCgYIBgAAAA==.',
['Kî']='Kîllara:BAAANQADCgUIBQAAAA==.',
Le='Lebronjames:BAABNQAECn8iAAIFAAoKBx8WJQCrAgAFAAoKBx8WJQCrAgAAAA==.Letheos:BAABNQAECn9AAAIUAAoKziIfCgBkAwAUAAoKziIfCgBkAwAAAA==.Levanas:BAAANQADCgEIAQAAAA==.',
Li='Librarte:BAABNQAECn8dAAIQAAoKsgfyzACBAQAQAAoKsgfyzACBAQAAAA==.Limmewinks:BAAANQADCgUIBQAAAA==.Litty:BAABNQAECn8YAAIHAAcKThOgoQADAQAHAAcKThOgoQADAQAAAA==.',
Lo='Loalu:BAAANQAECgEIAQAAAA==.Locktärd:BAAANQAECgQJBAABNQAFFAYICwAUAE4WAA==.Lox:BAABNQAECn8vAAIXAAgKWxE/DgAVAgAXAAgKWxE/DgAVAgAAAA==.',
Lu='Lunatick:BAAANQAECgIIAQABNQAECggIAwACAAAAAA==.',
Ly='Lydirn:BAAANQAECgMIBAAAAA==.',
['Lí']='Lítterbox:BAAANQAECgIIAgAAAA==.',
Ma='Magedzen:BAAANQADCgEIAQAAAA==.Magicguy:BAABNQAECn8kAAIHAAcKORuylgBTAgAHAAcKORuylgBTAgAAAA==.Mahariel:BAABNQAECn8iAAIBAAkKcQjBbABfAQABAAkKcQjBbABfAQAAAA==.Mahdy:BAABNQAECn82AAIQAAoKhxedOgAPAgAQAAoKhxedOgAPAgAAAA==.Mahoe:BAAANQADCgEIAQAAAA==.Malva:BAABNQAECn8pAAIDAAkKghWuIwAsAgADAAkKghWuIwAsAgAAAA==.Manrypurp:BAAANQAECgYIDAAAAA==.Marcie:BAABNQAECn8pAAIVAAgKoAuFLQAjAQAVAAgKoAuFLQAjAQAAAA==.Marracopa:BAAANQABCggICQAAAA==.Martinriggz:BAAANQAECgYIDAAAAA==.',
Mc='Mchammer:BAAANQADCgIIAgAAAA==.',
Me='Meatyloaf:BAAANQAECgQIBwAAAA==.Medsedation:BAABNQAECn86AAINAAkKeRNNOQDSAQANAAkKeRNNOQDSAQAAAA==.Melkedrik:BAAANQAECgQIBwAAAA==.Melleren:BAAANQAECgcICAAAAA==.Meridiane:BAAANQADCgEIAQAAAA==.',
Mi='Mirei:BAABNQAECn8rAAINAAgKXw9wSQCLAQANAAgKXw9wSQCLAQAAAA==.Mitsurugi:BAAANQAECgEIAQABNQAECgoKNwAMADMQAA==.',
Mo='Moolander:BAAANQADCgUIBQAAAA==.Moovidlin:BAAANQAECgYIEgABNQAECgcIBwACAAAAAA==.',
Mu='Mushhead:BAAANQAECgYJDwAAAA==.Mustepin:BAAANQADCgUIBQABNQAECgoKKgAbAMQYAA==.',
My='Mythantherox:BAAANQAECgIIAgABNQAFFAIIBwAgAGcdAA==.',
Na='Nachtaugen:BAAANQADCgcICQAAAA==.Nanlaria:BAAANQADCgEIAQAAAA==.',
Ne='Neon:BAAANQAECgMIAwAAAA==.Nethershade:BAABNQAECn8cAAIKAAgKexknCwDPAQAKAAgKexknCwDPAQAAAA==.Netherstörm:BAAANQAECgcIDQAAAA==.',
Ni='Niclea:BAAANQADCgUIBQAAAA==.Nightelm:BAAANQAECgcICAAAAA==.',
No='Noborû:BAAANQAECgYIDgABNQAECgkJHwAFACscAA==.Noslien:BAAANQAECgEIAQAAAA==.Nostradamuz:BAABNQAECn8yAAIYAAoKMRZ9DgC2AQAYAAoKMRZ9DgC2AQAAAA==.',
Ny='Nymneria:BAAANQAECgQIBwAAAA==.Nyxiera:BAABNQAECn89AAIZAAoKyxcXCQC7AQAZAAoKyxcXCQC7AQABNQAECgoKSgAZANQZAA==.Nyxstonia:BAABNQAECn9KAAQZAAoK1Bn4BwDVAgAZAAoK1Bn4BwDVAgAbAAYKKwxHFgA3AQAMAAQKKALa9gAzAAAAAA==.',
['Nä']='Nämi:BAAANQAECgYIDAAAAA==.',
Ol='Olierra:BAAANQADCgUIBQAAAA==.',
Om='Omnissiah:BAAANQABCgYIBgAAAA==.',
Or='Oreshin:BAAANQAECgUICAAAAA==.Ornac:BAAANQADCgMIAwAAAA==.Orphantrope:BAAANQABCgEIAQAAAA==.',
Ot='Otto:BAABNQAECn8uAAIQAAgKUxPNbgB3AQAQAAgKUxPNbgB3AQAAAA==.Ottomagus:BAAANQADCgcIDAAAAA==.',
Pa='Palliate:BAAANQADCgYIBgABNQADCgUIBQACAAAAAA==.Pampoovy:BAEANQADCgYJBgABNQAECgoKNgAhAJsYAA==.',
Pe='Persephoneia:BAABNQAECn8tAAIOAAkKHQq1GABOAQAOAAkKHQq1GABOAQAAAA==.',
Ph='Phobos:BAAANQABCgIIAgAAAA==.',
Pi='Piperclip:BAAANQADCgYIBgAAAA==.',
Po='Poraichu:BAAANQADCggICAAAAA==.',
Pr='Preacherman:BAAANQAECgQIBgAAAA==.Priority:BAAANQADCgQIBAAAAA==.',
Pu='Punjistake:BAAANQAECggICAAAAA==.Purplevane:BAAANQAECgMIAwAAAA==.',
Qu='Quna:BAAANQADCgIIAgAAAA==.',
Ra='Rabies:BAAANQADCgMIBAAAAA==.Rageoverrun:BAAANQAECgIIAgAAAA==.Ragequit:BAAANQAECgMJAwABNQAECggIIAAYAHgbAA==.Ranson:BAAANQAECggICAAAAA==.Ravenloare:BAAANQAECgEIAQAAAA==.',
Re='Reaverheim:BAAANQAECgEIAQAAAA==.Remuz:BAAANQADCgYIBgAAAA==.',
Ri='Rilz:BAABNQAECn81AAMFAAkK3B4PDwAsAgAFAAkK3B4PDwAsAgAGAAIKjQ78lQBpAAAAAA==.',
Ro='Rockasham:BAABNQAECn8oAAISAAkKtgs0eAC5AQASAAkKtgs0eAC5AQAAAA==.Rodgerwabbet:BAAANQADCgMIAwAAAA==.Rottn:BAABNQAECn8gAAIYAAgKeBviEwBrAQAYAAgKeBviEwBrAQAAAA==.',
Sa='Safmen:BAAANQAECggIEwAAAA==.Sanikoa:BAAANQAECgUIBQAAAA==.Saraid:BAABNQAECn80AAQeAAkKMRVFIgBKAQAeAAgKNRNFIgBKAQAiAAcKvwkaKgDDAAAVAAUKSg3QjQCfAAAAAA==.Saravase:BAAANQADCgcICAAAAA==.',
Se='Sev:BAAANQAECgIIAgAAAA==.Señorcleave:BAAANQADCgQICgAAAA==.',
Sh='Shadk:BAEBNQAECn82AAQUAAoKiRTmIACLAQAUAAkKyhXmIACLAQAFAAIKTgdv6QArAAAGAAIKAABfzQAAAAAAAA==.Shadowstorm:BAABNQAECn85AAIjAAkKLBVwEQBSAgAjAAkKLBVwEQBSAgAAAA==.Shelal:BAAANQADCggICAAAAA==.Shiki:BAAANQADCggIDwABNQAECggIKwANAF8PAA==.Shinoto:BAAANQADCgYIDQABNQAECggIIwAMACcYAA==.',
Si='Silvein:BAACNQAFFH8LAAIRAAYKFxAgDgCAAQARAAYKFxAgDgCAAQA1AAQKfy0AAxEACgoFIFUQAEoDABEACQrMIVUQAEoDABgACQo1DKUWAE4BAAAA.Silverpower:BAAANQAECgUIBQAAAA==.',
Sk='Skyë:BAAANQADCgcIBwABNQAECgcICAACAAAAAA==.',
Sn='Snowynn:BAAANQADCgEIAQAAAA==.',
So='Sorrybro:BAAANQADCgcIDwAAAA==.',
Sp='Spycatcher:BAAANQADCgQIBgAAAA==.Spyro:BAABNQAECn8iAAQgAAoKOhK5HgBoAQAgAAcKmgm5HgBoAQAkAAgKlQytKwBNAQAlAAQKWQyHFgDKAAAAAA==.Spyroo:BAABNQAECn8aAAIlAAkKng1mCgDKAQAlAAkKng1mCgDKAQAAAA==.',
Sr='Sron:BAABNQAECn8tAAIBAAgK+RlwXgBbAgABAAgK+RlwXgBbAgAAAA==.',
St='Stankboy:BAAANQABCgQIBwAAAA==.',
Su='Sumwhiteguy:BAAANQABCgYICAAAAA==.',
Sw='Swooze:BAABNQAECn8ZAAMHAAgKfxaewwD9AQAHAAgK/hSewwD9AQAcAAEKgBJDRAA7AAAAAA==.',
Sy='Syndar:BAAANQADCgQIBAABNQAECgoKIwASACseAA==.',
Sz='Szuzette:BAAANQAECgMIBQABNQAECgQICQACAAAAAA==.',
Ta='Tankcontrols:BAAANQAECgQICQAAAA==.Tarlyn:BAABNQAECn8bAAIRAAoKsxuxDgDmAgARAAoKsxuxDgDmAgAAAA==.',
Te='Temuadêrna:BAAANQADCgYIBgAAAA==.',
Th='Thaenet:BAAANQADCgUIBwAAAA==.Thevelo:BAAANQAECgUIBQABNQAECgcIDgACAAAAAA==.Thunderkatze:BAABNQAECn8aAAIjAAkKCQlJGADjAQAjAAkKCQlJGADjAQAAAA==.Thánátós:BAAANQAECgQIBgAAAA==.',
Ti='Tissaia:BAAANQADCgIIAgAAAA==.',
To='Topu:BAABNQAECn8ZAAQDAAgKHx3CSgA4AgADAAgKHx3CSgA4AgAjAAIKrREtLwB4AAASAAEKGAzJNAE0AAAAAA==.',
Tr='Tradarynn:BAAANQAECgQIBAAAAA==.Trek:BAAANQAECggIAQAAAA==.',
Tw='Twinkles:BAAANQADCgMIAwAAAA==.',
Ty='Tyviae:BAAANQAECgcIDQAAAA==.',
Un='Unacceptable:BAAANQAECgUIDgAAAA==.',
Ur='Urais:BAAANQAECgMIAwABNQAECgoKOwALALIjAA==.',
Us='Usdaprime:BAABNQAECn8jAAIVAAoKQAt/KABDAQAVAAoKQAt/KABDAQAAAA==.',
Va='Valhalia:BAABNQAECn8lAAMXAAkKeiE8AQBSAgAXAAgKeiE8AQBSAgAPAAMKZQ5rFQGfAAAAAA==.Vanira:BAAANQADCgYIBgAAAA==.Vanrien:BAAANQADCggICAAAAA==.Varaelitha:BAAANQAECgQIBAAAAA==.',
Ve='Velo:BAAANQADCggICAABNQAECgcIDgACAAAAAA==.Vengful:BAABNQAECn8XAAMaAAcKFRoERQCeAQAaAAYKMxYERQCeAQAmAAIK1RzCIwCiAAAAAA==.Vexy:BAAANQADCgMJBQAAAA==.',
Vh='Vhalúryn:BAAANQAECgUICQAAAA==.',
Vi='Vira:BAAANQADCgIIAgAAAA==.',
Vo='Vorumbrae:BAAANQAECgUIBwAAAA==.',
Wa='Wali:BAABNQAECn8nAAIPAAkKmRLQPwCqAQAPAAkKmRLQPwCqAQAAAA==.',
Wh='Whatupbruh:BAAANQAECgQIBAAAAA==.',
Wi='Wildefaux:BAAANQADCggICAAAAA==.',
Wo='Wooties:BAABNQAECn8fAAIKAAkKtQ6IHgAOAQAKAAkKtQ6IHgAOAQABNQAECgoKMgADAOsaAA==.',
Wy='Wyleriya:BAABNQAECn8uAAIXAAkKsQ2SBABXAQAXAAkKsQ2SBABXAQAAAA==.',
Xa='Xaluhn:BAAANQADCgQIBAAAAA==.',
Xc='Xcella:BAAANQAECgEIAQAAAA==.',
Xe='Xenophon:BAAANQADCgcIBwAAAA==.',
Xu='Xurael:BAAANQAECgYIEAAAAA==.',
Xy='Xyn:BAAANQADCgcIBwABNQAECgUICQACAAAAAA==.',
Ye='Yelhsa:BAAANQAECgYIDAAAAA==.Yelizaveta:BAAANQAECgMICwAAAA==.',
Yl='Ylfcwen:BAAANQADCgYIBgAAAA==.',
Yu='Yukiri:BAAANQAECgQIDgAAAA==.Yumei:BAAANQAECgcIBgABNQAECggIGQADAB8dAA==.',
Za='Zalarah:BAAANQAECgUICQAAAA==.Zarathusa:BAAANQADCgQIBAAAAA==.Zardan:BAAANQAECgQIDgAAAA==.',
Ze='Zeppik:BAAANQADCgYIDAAAAA==.',
Zu='Zuggerker:BAABNQAECn8wAAIMAAgKsBiBYQBpAgAMAAgKsBiBYQBpAgAAAA==.',
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
