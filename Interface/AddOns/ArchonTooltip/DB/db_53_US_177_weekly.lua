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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane','Monk-Windwalker','Rogue-Assassination','Rogue-Subtlety','Hunter-Marksmanship','Warrior-Arms','Priest-Holy','Priest-Shadow','Warlock-Demonology','Paladin-Retribution','Paladin-Holy','Shaman-Elemental','Monk-Brewmaster','DeathKnight-Blood','Druid-Balance','Warlock-Affliction','Warlock-Destruction','Warrior-Protection','DemonHunter-Havoc','Warrior-Fury','Mage-Frost','Priest-Discipline','Druid-Restoration','DemonHunter-Devourer','Evoker-Devastation','Paladin-Protection','Hunter-Survival','Druid-Guardian','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abracadavr:BAAANQADCgUICQAAAA==.Absolomb:BAAANQABCgMIAwAAAA==.',
Ac='Acell:BAABNQAECn9rAAIBAAoKTiNTBQC4AwABAAoKTiNTBQC4AwAAAA==.',
Ad='Addison:BAAANQAECgUICQAAAA==.Adeleas:BAAANQAECgEIAgABNQAECgYIDAACAAAAAA==.Adêrna:BAABNQAECn81AAIDAAkKFRyqAwDUAgADAAkKFRyqAwDUAgAAAA==.',
Af='Aftermathz:BAAANQAECgEIAQAAAA==.',
Ag='Agate:BAABNQAECn8WAAIEAAoKIQQ/DwC0AAAEAAoKIQQ/DwC0AAAAAA==.Agba:BAABNQAECn8jAAMFAAkKmxP2HQD6AAAFAAkKmxP2HQD6AAAGAAEKqAn2tgAoAAAAAA==.Aglain:BAAANQADCgMIAwAAAA==.',
Ai='Aibrean:BAAANQAECgYIDQAAAA==.Aiché:BAAANQADCgUIBQAAAA==.',
Ak='Aksul:BAAANQADCggICwAAAA==.',
Al='Alaala:BAAANQADCgUIBQAAAA==.Alaidan:BAAANQAECgUIBwAAAA==.Alanus:BAABNQAECn8qAAIHAAkKYA7IFwCxAQAHAAkKYA7IFwCxAQAAAA==.Alarion:BAAANQAECgYIDQAAAA==.Aliën:BAAANQAECgQICAAAAA==.Altana:BAAANQAECgIIBAABNQAECgcICgACAAAAAA==.Alydrus:BAAANQAECgEIAQAAAA==.',
An='Angryelf:BAAANQAECgIIBQAAAA==.Angrymanjibs:BAAANQAECgIIAwAAAA==.Anitasummon:BAAANQAECgEIAQAAAA==.Annahe:BAABNQAECn8mAAIIAAkKBBdzAwABAgAIAAkKBBdzAwABAgAAAA==.Annale:BAAANQADCgYIBgABNQAECgkJJgAIAAQXAA==.Anub:BAABNQAECn8dAAMJAAoK0Q1/TACPAQAJAAcKww1/TACPAQAKAAQK6g1/KgC1AAAAAA==.Anzala:BAAANQAECgMIBAAAAA==.',
Ar='Armsmaster:BAABNQAECn83AAMFAAoK9R7aJgCgAgAFAAoK9R7aJgCgAgAGAAEK9ROspwA+AAAAAA==.Arrann:BAAANQAECgUIDQAAAA==.Artemistha:BAAANQAECgYIDgAAAA==.',
Av='Avengharambe:BAAANQADCggIDwAAAA==.Avielle:BAAANQADCgUIBQAAAA==.',
Aw='Awakemage:BAAANQADCgYIBgAAAA==.',
['Aø']='Aøi:BAACNQAFFH8aAAIIAAcKKR31AQB/AgAIAAcKKR31AQB/AgA1AAQKfyIAAggACgpgI/wFAHEDAAgACgpgI/wFAHEDAAAA.',
Ba='Baey:BAAANQABCgEIAQAAAA==.Bam:BAAANQAECggIEwAAAA==.Barelycastin:BAABNQAECn8tAAIDAAkKtQ2wHgBvAQADAAkKtQ2wHgBvAQAAAA==.',
Be='Beautiful:BAAANQADCgYIDgAAAA==.Beleriand:BAAANQAECgYIEgAAAA==.Belgarathh:BAAANQAECgYICgAAAA==.Bellei:BAAANQADCgcIBwAAAA==.Bellíon:BAAANQADCgEIAQAAAA==.Belsnickel:BAAANQAECgEIAQAAAA==.',
Bl='Blacat:BAABNQAECn8WAAIEAAkKqA84EAAHAgAEAAkKqA84EAAHAgAAAA==.Blacksirloin:BAAANQADCgYIBgABNQAECgQICQACAAAAAA==.Blitzcomets:BAAANQAECgEIAgAAAA==.Bloodshunter:BAABNQAECn8bAAMBAAkKah4uOADCAgABAAgK8SAuOADCAgALAAUK5g9iUADqAAAAAA==.Blutauren:BAAANQAECgYICgAAAA==.',
Bo='Borda:BAAANQAECgUIDQAAAA==.',
Br='Brendenhunt:BAAANQADCggICAAAAA==.Broomhilda:BAAANQABCggIDAAAAA==.',
Bu='Buddypal:BAAANQAECgMIAwAAAA==.Buddypriest:BAAANQADCgIIAgABNQAECgMIAwACAAAAAA==.',
['Bâ']='Bâm:BAAANQAECgMIBAABNQAECggIEwACAAAAAA==.',
Ca='Caidi:BAAANQAECgQIBwAAAA==.Carini:BAABNQAECn8nAAIHAAgKJREtJACEAQAHAAgKJREtJACEAQAAAA==.Catheryne:BAAANQAECgQIBAAAAA==.',
Ch='Chelsgrin:BAAANQAECgUICQABNQAECggIFAAMAHYbAA==.Chickynuggy:BAAANQADCgcIBwAAAA==.Chrischan:BAAANQABCgMIAQAAAA==.Chónk:BAAANQAECgYIDAAAAA==.',
Cl='Clûtch:BAABNQAECn8eAAIFAAkKKxxeJQCqAgAFAAkKKxxeJQCqAgAAAA==.',
Co='Corvax:BAAANQADCgYIBgAAAA==.Corynthe:BAABNQAECn8pAAINAAgKIB7LCgA4AgANAAgKIB7LCgA4AgAAAA==.',
Cr='Crickie:BAAANQAECgQIBwAAAA==.Croftypongue:BAAANQADCgcIBwAAAA==.Crovaxis:BAABNQAECn8qAAILAAkK2RiKAwDhAQALAAkK2RiKAwDhAQAAAA==.',
Da='Daddychill:BAAANQAECgUIBQAAAA==.Daedrìc:BAAANQADCgQIBAAAAA==.Damagetaken:BAAANQAECgYIBwAAAA==.Darktalyn:BAABNQAECn8tAAIOAAkKVwxqCQBdAQAOAAkKVwxqCQBdAQAAAA==.Dawi:BAAANQAECgIIAwAAAA==.',
De='Deathgrip:BAAANQADCgUIBgAAAA==.Deathhawkzz:BAABNQAECn8nAAIPAAkKgxrPSwBwAgAPAAkKgxrPSwBwAgAAAA==.Deekura:BAABNQAECn8eAAIFAAgKTAutEgBHAQAFAAgKTAutEgBHAQAAAA==.Delusion:BAAANQADCgEIAQAAAA==.Demmin:BAAANQADCgcIBwABNQAECgUIEgACAAAAAA==.Dezireth:BAABNQAECn8wAAIBAAoKtAt2UgAMAQABAAoKtAt2UgAMAQAAAA==.',
Dh='Dhakastyr:BAAANQAECggICAAAAA==.',
Di='Dinak:BAAANQADCggIGwAAAA==.Dionan:BAABNQAECn8nAAIQAAkKzw6ONQBgAQAQAAkKzw6ONQBgAQAAAA==.Dirt:BAAANQAECgEIAQAAAA==.',
Do='Docs:BAABNQAECn8fAAMRAAoKeRdSDAABAgARAAoKeRdSDAABAgAQAAYKMwts+QArAQAAAA==.Doks:BAABNQAECn8pAAMDAAoKeBoxHAB9AQADAAoKeBoxHAB9AQASAAEKAAD4MAE4AAAAAA==.',
Dr='Dragana:BAAANQAECgIIBAAAAA==.Dragster:BAAANQAECgYIBwAAAA==.Dragõn:BAAANQADCgEIAQAAAA==.Dreadmyr:BAAANQADCgUIBQAAAA==.Dreamfýre:BAAANQAECgEIAQAAAA==.Dridae:BAAANQAECgEIAQAAAA==.Drusilvia:BAAANQADCgcIBwAAAA==.',
Ea='Ealara:BAAANQADCggIDwAAAA==.',
Ec='Echidna:BAAANQADCggICAABNQAFFAcIGwARAPwBAA==.',
El='Elendor:BAAANQABCgYICQAAAA==.',
Em='Emiira:BAAANQAECgEIAQAAAA==.',
En='Enthaii:BAAANQAECgEIAQAAAA==.',
Er='Erithil:BAAANQADCgYIBgABNQAECgcIEwACAAAAAA==.',
Es='Espe:BAABNQAECn8sAAITAAkKhhUQAgC5AQATAAkKhhUQAgC5AQAAAA==.',
Eu='Euli:BAAANQADCgMIBAABNQAFFAYIGgAUADQYAA==.',
Ev='Everayn:BAABNQAECn8+AAMRAAcKbRV1bQDPAQARAAcKbRV1bQDPAQAQAAUK7AmCFAH9AAABNQAECgoKawABAE4jAA==.',
Ex='Exhalo:BAABNQAECn8rAAIMAAoKFBXNKwBaAQAMAAoKFBXNKwBaAQAAAA==.Exil:BAAANQAECgEIAQAAAA==.',
Fa='Fallen:BAABNQAECn8XAAIVAAgK7BJFQgDuAQAVAAgK7BJFQgDuAQAAAA==.Fallenvoid:BAAANQADCgEIAQAAAA==.Fasebreaker:BAAANQABCggIDgAAAA==.Faynor:BAABNQAECn8pAAITAAgKtSHJAQDLAQATAAgKtSHJAQDLAQAAAA==.',
Fe='Felwhisper:BAAANQAECgUIBQAAAA==.',
Fi='Finalycalm:BAAANQAECgUIBwAAAA==.Finimus:BAAANQAECgIJAwAAAA==.Finlok:BAAANQABCgMIAgAAAA==.Firêfly:BAAANQAECgUIBgAAAA==.',
Fl='Flingpooh:BAAANQAECgYIDgAAAA==.Flloran:BAABNQAECn8VAAIVAAUKgAcHMACfAAAVAAUKgAcHMACfAAAAAA==.',
Fr='Fraggle:BAECNQAFFH8SAAIRAAUKSRPYDACSAQARAAUKSRPYDACSAQA1AAQKfzEAAxEACgr0G80fAPACABEACgr0G80fAPACABAAAQpKDW6fATcAAAAA.Frogchi:BAAANQAECgYIEgAAAA==.Frostbité:BAAANQADCggIGgAAAA==.Frostybasham:BAAANQAECgEIAQAAAA==.Fruit:BAAANQAECgQICwAAAA==.',
Fu='Fubarut:BAAANQABCggIGAAAAA==.Fumikiko:BAAANQADCgYICgABNQAECgcICgACAAAAAA==.Funnybluffy:BAAANQAECgEIAgAAAA==.Fuzzbâll:BAAANQABCgYICQAAAA==.',
['Fí']='Físh:BAAANQADCgcICAABNQAECgcICgACAAAAAA==.',
Ga='Gali:BAAANQAECgEIAgAAAA==.Galindrael:BAAANQAECgEIAQAAAA==.Gargybyn:BAAANQADCgUIBwAAAA==.',
Gi='Girliepop:BAAANQAECgYICwAAAA==.',
Gl='Glaistiguain:BAABNQAECn8nAAQWAAkKVR+sAwC2AgAWAAgKPiCsAwC2AgAXAAQKTh9ZIQBmAQAPAAEKAACHOAFFAAABNQAECgoKNwAFAPUeAA==.Glifin:BAAANQAECggIDgAAAA==.Glizzeldra:BAAANQADCgUIBQAAAA==.Gloomstalkin:BAAANQAECgQICgABNQAECgkJMwAUAI4UAA==.Glynna:BAAANQADCgUIBQAAAA==.',
Go='Gooning:BAAANQAFFAEIAQABNQAFFAYICwAUAE4WAA==.',
Gr='Gr:BAABNQAECn8oAAIJAAkKAwjfCgB3AQAJAAkKAwjfCgB3AQAAAA==.Grasha:BAAANQAECgEIAgAAAA==.Gryffs:BAABNQAECn8kAAMYAAkKhRuMAwCrAQAMAAgKlg6urACtAQAYAAkKshmMAwCrAQAAAA==.Gràvity:BAAANQAECgQIBwABNQAECgYIAgACAAAAAA==.',
Gu='Guanino:BAAANQADCggIDQAAAA==.Gutts:BAAANQAECgIIAwABNQAECggIKQAKAHgcAA==.',
Gw='Gworg:BAAANQADCgEIAQAAAA==.',
['Gì']='Gìzmo:BAAANQAECgQIBwAAAA==.',
Ha='Halartion:BAABNQAECn8UAAIMAAgKdhsragBSAgAMAAgKdhsragBSAgAAAA==.Happirogue:BAAANQAECgYIBwABNQAFFAYIEwAZAM0dAA==.Haruun:BAAANQAECgQIBQAAAA==.',
He='Helridden:BAABNQAECn8UAAIMAAcKHgbzWgDjAAAMAAcKHgbzWgDjAAAAAA==.Hesmydaddy:BAABNQAECn8xAAINAAkKnwahHQCRAQANAAkKnwahHQCRAQAAAA==.',
Ho='Hoztok:BAAANQAECgQIBQAAAA==.',
Ic='Icemann:BAAANQAECgEIAwAAAA==.',
Im='Imherdaddy:BAABNQAECn8zAAIUAAkKjhQ9CQCnAQAUAAkKjhQ9CQCnAQAAAA==.',
It='Itakemeds:BAAANQADCgYJDAABNQAECgMIBQACAAAAAA==.',
Ja='Jaderean:BAAANQAECgMJBAAAAA==.Jake:BAAANQAECgMIAwABNQAECggIIwAaAEQZAA==.Jarrack:BAABNQAECn8pAAMHAAgKDhRGIgCKAQAHAAgKFhFGIgCKAQAbAAQKrBaaIQDcAAAAAA==.Jaye:BAAANQABCgUICQAAAA==.',
Je='Jessicae:BAABNQAECn8jAAMNAAkKGBgTHwCJAQANAAkKGBgTHwCJAQAcAAEKfg2oKgAvAAAAAA==.Jeuno:BAAANQADCggIDgABNQAECgcICgACAAAAAA==.',
Ji='Jivederpy:BAABNQAECn8eAAIMAAgKgx3UEwC8AQAMAAgKgx3UEwC8AQAAAA==.',
Ju='Juicybooty:BAAANQADCgYIDAAAAA==.Junazeena:BAABNQAECn8ZAAMDAAcKmQa6zgDKAAADAAYKdAO6zgDKAAASAAcKzQR+VwCOAAAAAA==.',
Ka='Kayfabe:BAABNQAECn8fAAIHAAkKZwTwDgF0AQAHAAkKZwTwDgF0AQAAAA==.',
Ke='Keirasti:BAAANQAECgYIDAAAAA==.Keishilda:BAAANQAECgIIAgAAAA==.Keladria:BAAANQAECgYIDAAAAA==.Kelirra:BAAANQAECgIIAgAAAA==.Kenel:BAABNQAECn8yAAIVAAkKMhCzCQCfAQAVAAkKMhCzCQCfAQAAAA==.Kerea:BAABNQAECn8pAAIdAAgK5ATOGQD1AAAdAAgK5ATOGQD1AAAAAA==.Kermitt:BAAANQABCggIFwAAAA==.Keyarga:BAAANQADCgYICgABNQAECggIDwACAAAAAA==.',
Kh='Khazadoom:BAAANQAECgYIDAAAAA==.Khazargon:BAAANQAECggIEAAAAA==.',
Ki='Kicken:BAABNQAECn8jAAMPAAgKHRGzSQD2AAAPAAYK9g2zSQD2AAAXAAIKaRcVCgB8AAAAAA==.Kiitsuna:BAAANQADCgYIBgAAAA==.Kittyflerp:BAAANQADCgEJAQAAAA==.Kittyperry:BAAANQAECggIEgAAAA==.',
Ko='Korthelan:BAABNQAECn8wAAIeAAkK1xQBBwCfAQAeAAkK1xQBBwCfAQAAAA==.Kothara:BAABNQAECn8oAAIBAAgKKRQbHgCfAQABAAgKKRQbHgCfAQAAAA==.',
Kr='Krimzin:BAACNQAFFH8NAAIBAAYK3xXSCwCSAQABAAYK3xXSCwCSAQA1AAQKfy4AAgEACgpBIewgABMDAAEACgpBIewgABMDAAAA.Krystine:BAAANQAECgUIEAAAAA==.',
Ks='Kserasera:BAABNQAECn8qAAIVAAoKwA3NPAAQAgAVAAoKwA3NPAAQAgAAAA==.',
Ku='Kuball:BAABNQAECn8pAAIKAAgKeBzeCQCXAQAKAAgKeBzeCQCXAQAAAA==.Kukuruku:BAAANQAECgUIBgAAAA==.Kumari:BAABNQAECn8kAAIDAAoKQQHw0gDBAAADAAoKQQHw0gDBAAAAAA==.',
['Kî']='Kîllara:BAAANQADCgUIBQAAAA==.',
Le='Lebronjames:BAABNQAECn8gAAIFAAgKAyEWJQCrAgAFAAgKAyEWJQCrAgAAAA==.Letheos:BAABNQAECn86AAIUAAoKbCIfCgBkAwAUAAoKbCIfCgBkAwAAAA==.Levanas:BAAANQADCgEIAQAAAA==.',
Li='Librarte:BAABNQAECn8ZAAIQAAoKsgfyzACBAQAQAAoKsgfyzACBAQAAAA==.Limmewinks:BAAANQADCgUIBQAAAA==.Litty:BAABNQAECn8UAAIHAAcKfREbVgARAQAHAAcKfREbVgARAQAAAA==.',
Lo='Loalu:BAAANQAECgEIAQAAAA==.Locktärd:BAAANQAECgQJBQABNQAFFAYICwAUAE4WAA==.Lox:BAABNQAECn8oAAIXAAgKNRE/DgAVAgAXAAgKNRE/DgAVAgAAAA==.',
Lu='Lunatick:BAAANQAECgIIAQABNQAECggIAwACAAAAAA==.',
Ly='Lydirn:BAAANQAECgMIBAAAAA==.',
['Lí']='Lítterbox:BAAANQAECgIIAgAAAA==.',
Ma='Magedzen:BAAANQADCgEIAQAAAA==.Magicguy:BAABNQAECn8jAAIHAAcKORuylgBTAgAHAAcKORuylgBTAgAAAA==.Mahariel:BAABNQAECn8cAAIBAAcKjwkURgAoAQABAAcKjwkURgAoAQAAAA==.Mahdy:BAABNQAECn8uAAIQAAoKFBQreQA6AgAQAAoKFBQreQA6AgAAAA==.Mahoe:BAAANQADCgEIAQAAAA==.Malva:BAABNQAECn8iAAIDAAkKARL/DAD7AQADAAkKARL/DAD7AQAAAA==.Manrypurp:BAAANQAECgYIBgAAAA==.Marcie:BAABNQAECn8iAAIVAAgKfQv+TgCjAQAVAAgKfQv+TgCjAQAAAA==.Marracopa:BAAANQAECgEIAwAAAA==.Martinriggz:BAAANQAECgYIDwAAAA==.',
Mc='Mchammer:BAAANQAECgEIAgAAAA==.',
Me='Meatyloaf:BAAANQAECgQICQAAAA==.Medsedation:BAABNQAECn8zAAINAAkKXxBDKABdAQANAAkKXxBDKABdAQAAAA==.Melkedrik:BAAANQAECgQICQAAAA==.Melleren:BAAANQAECgcICgAAAA==.Meridiane:BAAANQADCgEIAQAAAA==.',
Mi='Mirei:BAABNQAECn8jAAINAAgKnQ5nGgCjAQANAAgKnQ5nGgCjAQAAAA==.',
Mo='Moolander:BAAANQADCgUIBQAAAA==.Moovidlin:BAAANQAECgUIEgAAAA==.',
Mu='Mushhead:BAAANQAECgYJEAAAAA==.Mustepin:BAAANQADCgUIBQABNQAECggIIwAaAEQZAA==.',
My='Myrrdiache:BAAANQAECgEIAQAAAA==.Mythantherox:BAAANQAECgIIAgABNQAFFAIIBwAfAGcdAA==.Myzrybow:BAAANQAECgEIAQAAAA==.',
Na='Nanlaria:BAAANQADCgEIAQAAAA==.',
Ne='Neon:BAAANQAECgMIAwAAAA==.Nethershade:BAABNQAECn8bAAIJAAgKexl9BADmAQAJAAgKexl9BADmAQAAAA==.Netherstörm:BAAANQAECgMICAAAAA==.',
Ni='Niclea:BAAANQADCgUIBQAAAA==.Nightelm:BAAANQAECgcICgAAAA==.',
No='Noborû:BAAANQAECgYIDgABNQAECgkJHgAFACscAA==.Noslien:BAAANQAECgEIAQAAAA==.Nostradamuz:BAABNQAECn8uAAIgAAkKmhf2BAC3AQAgAAkKmhf2BAC3AQAAAA==.',
Ny='Nymneria:BAAANQAECgQICQAAAA==.Nyxiera:BAABNQAECn81AAIYAAoKdRZhDQBcAgAYAAoKdRZhDQBcAgABNQAECgoKPwAYABYZAA==.Nyxstonia:BAABNQAECn8/AAQYAAoKFhn4BwDVAgAYAAoKFhn4BwDVAgAaAAYKKwxHFgA3AQAMAAEKAAClZgEfAAAAAA==.',
['Nä']='Nämi:BAAANQAECgYIDgAAAA==.',
Ol='Olierra:BAAANQADCgUIBQAAAA==.',
Om='Omnissiah:BAAANQABCgYIBgAAAA==.',
Or='Oreshin:BAAANQAECgUIDAAAAA==.Ornac:BAAANQADCgMIAwAAAA==.Orphantrope:BAAANQABCgEIAQAAAA==.',
Ot='Otto:BAABNQAECn8nAAIQAAgKcBCzQABFAQAQAAgKcBCzQABFAQAAAA==.Ottomagus:BAAANQADCgcIDAAAAA==.',
Pa='Palliate:BAAANQADCgYIBgABNQADCgUIBQACAAAAAA==.Pampoovy:BAEANQADCgYJBgABNQAECgoKMwAhAC0YAA==.',
Pe='Persephoneia:BAABNQAECn8nAAIOAAkK5wl+CgBPAQAOAAkK5wl+CgBPAQAAAA==.',
Ph='Phobos:BAAANQABCgIIAgAAAA==.',
Pi='Piperclip:BAAANQADCgYIBgAAAA==.',
Po='Poraichu:BAAANQADCggICAAAAA==.',
Pr='Preacherman:BAAANQAECgUICAAAAA==.Priority:BAAANQADCgQIBAAAAA==.',
Pu='Purplevane:BAAANQAECgMIAwAAAA==.',
Ra='Rabies:BAAANQABCggICwAAAA==.Rageoverrun:BAAANQAECgIIAwAAAA==.Ragequit:BAAANQAECgMJBAABNQAECggIIAAgAHgbAA==.Ranson:BAAANQAECggICAAAAA==.Ravenloare:BAAANQADCgYIEwAAAA==.',
Re='Reaverheim:BAAANQAECgEIAQAAAA==.Remuz:BAAANQADCgYIBgAAAA==.',
Ri='Rilz:BAABNQAECn8uAAMFAAkKVRzLAgA3AgAFAAkKVRzLAgA3AgAGAAIKjQ78lQBpAAAAAA==.',
Ro='Rockasham:BAABNQAECn8mAAISAAkKMAs0eAC5AQASAAkKMAs0eAC5AQAAAA==.Rodgerwabbet:BAAANQADCgMIAwAAAA==.Rottn:BAABNQAECn8gAAIgAAgKeBv2BQChAQAgAAgKeBv2BQChAQAAAA==.',
Sa='Safmen:BAAANQAECggIEAAAAA==.Sanikoa:BAAANQAECgUIBQAAAA==.Saraid:BAABNQAECn8tAAQdAAkKMRWkDQBjAQAdAAgKNROkDQBjAQAVAAQKgBDQjQCfAAAiAAEKuQ2cYwAtAAAAAA==.Saravase:BAAANQADCgcICAAAAA==.Saurot:BAAANQADCgcICQAAAA==.',
Se='Sempiternus:BAAANQAECgEIAQAAAA==.Sev:BAAANQAECgIIBAAAAA==.Señorcleave:BAAANQADCgQICgAAAA==.',
Sh='Shadk:BAEBNQAECn8vAAQUAAoK6xN/CACwAQAUAAkKFhV/CACwAQAFAAIKTgdv6QArAAAGAAIKAABfzQAAAAAAAA==.Shadowstorm:BAABNQAECn8zAAIjAAkKLBXjAwDUAQAjAAkKLBXjAwDUAQAAAA==.Shelal:BAAANQADCggICAAAAA==.Shiki:BAAANQADCggIDwABNQAECggIIwANAJ0OAA==.Shinoto:BAAANQADCgYIDQABNQAECggIHQAMAGIVAA==.',
Si='Silvein:BAACNQAFFH8LAAIRAAYKFxAgDgCAAQARAAYKFxAgDgCAAQA1AAQKfyQAAxEACgoQH1UQAEoDABEACQq8IFUQAEoDACAAAwoVAicuAFAAAAAA.Silverpower:BAAANQAECgUIBQAAAA==.Silverstead:BAAANQAECgEIAQAAAA==.',
Sk='Skyë:BAAANQADCgcIBwABNQAECgcICgACAAAAAA==.',
Sn='Snowynn:BAAANQADCgEIAQAAAA==.',
So='Sorrybro:BAAANQADCgcIDwAAAA==.',
Sp='Spycatcher:BAAANQADCgMIBAAAAA==.Spyro:BAABNQAECn8iAAQfAAoKOhK5HgBoAQAfAAcKmgm5HgBoAQAkAAgKlQytKwBNAQAlAAQKWQyHFgDKAAAAAA==.Spyroo:BAABNQAECn8YAAIlAAgKCQ9mCgDKAQAlAAgKCQ9mCgDKAQAAAA==.',
Sr='Sron:BAABNQAECn8sAAIBAAgK+Rl0GQC0AQABAAgK+Rl0GQC0AQAAAA==.',
St='Stankboy:BAAANQABCgQIBwAAAA==.',
Sw='Swooze:BAABNQAECn8ZAAMHAAgKfxaewwD9AQAHAAgK/hSewwD9AQAbAAEKgBJDRAA7AAAAAA==.',
Sy='Syndar:BAAANQADCgQIBAABNQAECgcIDAACAAAAAA==.',
Sz='Szuzette:BAAANQAECgMIBwABNQAECgQICgACAAAAAA==.',
Ta='Tankcontrols:BAAANQAECgMIBgAAAA==.Tarlyn:BAAANQAECgYIEQABNQAECgkJHAARAMwTAA==.',
Te='Temuadêrna:BAAANQADCgYIBgAAAA==.',
Th='Thaenet:BAAANQADCgUIBwAAAA==.Thevelo:BAAANQAECgYIBgABNQAECggIDwACAAAAAA==.Thunderkatze:BAABNQAECn8aAAIjAAkKCQlJGADjAQAjAAkKCQlJGADjAQAAAA==.Thánátós:BAAANQAECgQICAAAAA==.',
Ti='Tissaia:BAAANQADCgIIAgAAAA==.',
To='Topu:BAABNQAECn8ZAAQDAAgKHx3CSgA4AgADAAgKHx3CSgA4AgAjAAIKrREtLwB4AAASAAEKGAzJNAE0AAAAAA==.',
Tr='Tradarynn:BAAANQADCgYIBgAAAA==.',
Tw='Twinkles:BAAANQADCgMIAwAAAA==.',
Ty='Tyviae:BAAANQAECgQICAAAAA==.',
Un='Unacceptable:BAAANQAECgUIEQAAAA==.',
Ur='Urais:BAAANQAECgMIAwABNQAECgoKMwALALIjAA==.',
Us='Usdaprime:BAABNQAECn8ZAAIVAAkKQwtcTQCsAQAVAAkKQwtcTQCsAQAAAA==.',
Va='Valhalia:BAABNQAECn8eAAMXAAkKUx/dAADIAQAXAAgKUx/dAADIAQAPAAMKZQ5rFQGfAAAAAA==.Vanira:BAAANQADCgYIBgAAAA==.Vanrien:BAAANQADCggICAAAAA==.Varaelitha:BAAANQAECgEIAQAAAA==.',
Ve='Velo:BAAANQADCgQIBAABNQAECggIDwACAAAAAA==.Vengful:BAABNQAECn8XAAMZAAcKFRoERQCeAQAZAAYKMxYERQCeAQAmAAIK1RzCIwCiAAAAAA==.Vexy:BAAANQADCgMJBQAAAA==.',
Vh='Vhalúryn:BAAANQAECgYIDAAAAA==.',
Vi='Vira:BAAANQADCgIIAgAAAA==.',
Vo='Vorumbrae:BAAANQAECgUIBwAAAA==.',
Wa='Wali:BAABNQAECn8gAAIPAAgKVBTRFQCeAQAPAAgKVBTRFQCeAQAAAA==.',
Wh='Whatupbruh:BAAANQAECgQIBAAAAA==.',
Wi='Wildefaux:BAAANQADCggICAAAAA==.',
Wo='Wooties:BAABNQAECn8ZAAIJAAkKwQshPADhAQAJAAkKwQshPADhAQABNQAECgoKKQADAHgaAA==.',
Wy='Wyleriya:BAABNQAECn8oAAIXAAkKbg0rAgBQAQAXAAkKbg0rAgBQAQAAAA==.',
Xa='Xaluhn:BAAANQADCgQIBAAAAA==.',
Xc='Xcella:BAAANQAECgEIAQAAAA==.',
Xe='Xenophon:BAAANQADCgcIBwAAAA==.',
Xu='Xurael:BAAANQAECgYIEwAAAA==.',
Ye='Yelhsa:BAAANQAECgYIDgAAAA==.Yelizaveta:BAAANQAECgMIDwAAAA==.',
Yl='Ylfcwen:BAAANQAECgEIAQAAAA==.',
Yu='Yukiri:BAAANQAECgUIDAAAAA==.Yumei:BAAANQAECgcIBwABNQAECggIGQADAB8dAA==.',
Za='Zalarah:BAAANQAECgUIDgAAAA==.Zarathusa:BAAANQADCgQIBAAAAA==.Zardan:BAAANQAECgQIDgAAAA==.',
Ze='Zeppik:BAAANQADCgYIDAAAAA==.',
Zu='Zuggerker:BAABNQAECn8pAAIMAAgKXhjAGgCaAQAMAAgKXhjAGgCaAQAAAA==.',
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
