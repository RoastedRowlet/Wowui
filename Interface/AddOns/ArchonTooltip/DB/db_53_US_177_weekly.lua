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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane','Monk-Windwalker','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Hunter-Marksmanship','Warrior-Arms','Priest-Holy','Priest-Shadow','Warlock-Demonology','Paladin-Retribution','Paladin-Holy','Shaman-Elemental','Monk-Brewmaster','DeathKnight-Blood','Druid-Balance','Warlock-Affliction','Warlock-Destruction','Warrior-Protection','DemonHunter-Havoc','Mage-Frost','Priest-Discipline','Druid-Restoration','DemonHunter-Devourer','Warrior-Fury','Evoker-Devastation','Paladin-Protection','Hunter-Survival','Druid-Guardian','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abracadavr:BAAANQADCgUICQAAAA==.Absolomb:BAAANQABCgMIAwAAAA==.',
Ac='Acell:BAABNQAECn9fAAIBAAkKZCQ8BQC5AwABAAkKZCQ8BQC5AwAAAA==.',
Ad='Addison:BAAANQAECgUICQAAAA==.Adeleas:BAAANQAECgEIAgABNQAECgQICwACAAAAAA==.Adêrna:BAABNQAECn8sAAIDAAgK8RunOgByAgADAAgK8RunOgByAgAAAA==.',
Af='Aftermathz:BAAANQAECgEIAQAAAA==.',
Ag='Agate:BAAANQAECggIAgAAAA==.Agba:BAABNQAECn8fAAMEAAgKLhV2UADOAQAEAAgKLhV2UADOAQAFAAEKqAldswAoAAAAAA==.Aglain:BAAANQADCgMIAwAAAA==.',
Ai='Aibrean:BAAANQAECgQICAAAAA==.Aiché:BAAANQADCgUIBQAAAA==.',
Ak='Aksul:BAAANQADCggICwAAAA==.',
Al='Alaala:BAAANQADCgUIBQAAAA==.Alaidan:BAAANQAECgUIBwAAAA==.Alanus:BAABNQAECn8iAAIGAAgKPg+MyADyAQAGAAgKPg+MyADyAQAAAA==.Alarion:BAAANQAECgQIDAAAAA==.Aliën:BAAANQAECgQIBAAAAA==.Altana:BAAANQAECgIIBAABNQAECgcICgACAAAAAA==.Alydrus:BAAANQAECgEIAQAAAA==.',
An='Angryelf:BAAANQAECgIIBQAAAA==.Angrymanjibs:BAAANQAECgIIAwAAAA==.Anitasummon:BAAANQAECgEIAQAAAA==.Annahe:BAABNQAECn8eAAIHAAgKBxc6IAAoAgAHAAgKBxc6IAAoAgAAAA==.Annale:BAAANQADCgYIBgABNQAECggIHgAHAAcXAA==.Anub:BAABNQAECn8aAAMIAAkKgg43SwCPAQAIAAcKww03SwCPAQAJAAMKXxAJPwC6AAAAAA==.Anzala:BAAANQAECgMIAwAAAA==.',
Ar='Armsmaster:BAABNQAECn8zAAMEAAgKFCFtJgCgAgAEAAgKFCFtJgCgAgAFAAEK9RNHpAA+AAAAAA==.Arrann:BAAANQAECgQIDAAAAA==.Artemistha:BAAANQAECgUIDAAAAA==.',
Av='Avengharambe:BAAANQADCggIDwAAAA==.Avielle:BAAANQADCgUIBQAAAA==.',
['Aø']='Aøi:BAACNQAFFH8aAAIHAAcKKR3dAQCAAgAHAAcKKR3dAQCAAgA1AAQKfx8AAgcACQq3JNQFAHEDAAcACQq3JNQFAHEDAAAA.',
Ba='Baey:BAAANQABCgEIAQAAAA==.Bam:BAAANQAECgcIDgAAAA==.Barelycastin:BAABNQAECn8lAAIDAAgKog2CeACeAQADAAgKog2CeACeAQAAAA==.',
Be='Beautiful:BAAANQADCgYICwAAAA==.Beleriand:BAAANQAECgYIDgAAAA==.Belgarathh:BAAANQAECgYICgAAAA==.Bellei:BAAANQADCgcIBwAAAA==.Bellíon:BAAANQADCgEIAQAAAA==.Belsnickel:BAAANQAECgEIAQAAAA==.',
Bl='Blacat:BAABNQAECn8WAAIKAAkKqA//DwAJAgAKAAkKqA//DwAJAgAAAA==.Blacksirloin:BAAANQADCgYIBgABNQAECgQICQACAAAAAA==.Blitzcomets:BAAANQAECgEIAgAAAA==.Bloodshunter:BAABNQAECn8cAAMBAAkKah7hNgDEAgABAAgK8SDhNgDEAgALAAUK5g+aRgAhAQAAAA==.Blutauren:BAAANQAECgYICAAAAA==.',
Bo='Borda:BAAANQAECgUIDQAAAA==.',
Br='Brendenhunt:BAAANQADCggICAAAAA==.Broomhilda:BAAANQABCggIDAAAAA==.',
Bu='Buddypal:BAAANQAECgMIAwAAAA==.Buddypriest:BAAANQADCgIIAgABNQAECgMIAwACAAAAAA==.',
['Bâ']='Bâm:BAAANQAECgEIAQABNQAECgcIDgACAAAAAA==.',
Ca='Caidi:BAAANQAECgMIBAAAAA==.Carini:BAABNQAECn8gAAIGAAgKCw9GwwD8AQAGAAgKCw9GwwD8AQAAAA==.Catheryne:BAAANQAECgQIBAAAAA==.',
Ch='Chelsgrin:BAAANQAECgUICQABNQAECggIFAAMAHYbAA==.Chickynuggy:BAAANQADCgcIBwAAAA==.Chrischan:BAAANQABCgMIAQAAAA==.Chónk:BAAANQAECgQICwAAAA==.',
Cl='Clûtch:BAABNQAECn8bAAIEAAgKYh4DJQCpAgAEAAgKYh4DJQCpAgAAAA==.',
Co='Corvax:BAAANQADCgYIBgAAAA==.Corynthe:BAABNQAECn8iAAINAAgKShuAQABlAgANAAgKShuAQABlAgAAAA==.',
Cr='Crickie:BAAANQAECgQIBwAAAA==.Croftypongue:BAAANQADCgcIBwAAAA==.Crovaxis:BAABNQAECn8iAAILAAcKrh3HIwAsAgALAAcKrh3HIwAsAgAAAA==.',
Da='Daddychill:BAAANQAECgUIBQAAAA==.Daedrìc:BAAANQADCgQIBAAAAA==.Damagetaken:BAAANQAECgYIBwAAAA==.Darktalyn:BAABNQAECn8lAAIOAAgKxA2VKQDXAQAOAAgKxA2VKQDXAQAAAA==.Dawi:BAAANQAECgIIAwAAAA==.',
De='Deathgrip:BAAANQADCgUIBgAAAA==.Deathhawkzz:BAABNQAECn8jAAIPAAgKXRxUSgBxAgAPAAgKXRxUSgBxAgAAAA==.Deekura:BAABNQAECn8WAAIEAAcKuQshawBiAQAEAAcKuQshawBiAQAAAA==.Delusion:BAAANQADCgEIAQAAAA==.Dezireth:BAABNQAECn8pAAIBAAgKxw2NhwD4AQABAAgKxg2NhwD4AQAAAA==.',
Dh='Dhakastyr:BAAANQAECggICAAAAA==.',
Di='Dinak:BAAANQADCggIGwAAAA==.Dionan:BAABNQAECn8fAAIQAAgKCg+fpwDLAQAQAAgKCg+fpwDLAQAAAA==.Dirt:BAAANQAECgEIAQAAAA==.',
Do='Docs:BAABNQAECn8ZAAMRAAgKrxR+VAAZAgARAAgKrxR+VAAZAgAQAAYKMwva9QArAQAAAA==.Doks:BAABNQAECn8jAAMDAAkK0RnLNACKAgADAAkK0RnLNACKAgASAAEKAACbLAE4AAAAAA==.',
Dr='Dragana:BAAANQAECgEIAwAAAA==.Dragster:BAAANQAECgEIAQAAAA==.Dragõn:BAAANQADCgEIAQAAAA==.Dreadmyr:BAAANQADCgUIBQAAAA==.Dreamfýre:BAAANQAECgEIAQAAAA==.Dridae:BAAANQAECgEIAQAAAA==.Drusilvia:BAAANQADCgcIBwAAAA==.',
Ea='Ealara:BAAANQADCggIDwAAAA==.',
Ec='Echidna:BAAANQADCggICAABNQAFFAcIGwARAPwBAA==.',
El='Elendor:BAAANQABCgYICQAAAA==.',
Em='Emiira:BAAANQAECgEIAQAAAA==.',
En='Enthaii:BAAANQAECgEIAQAAAA==.',
Er='Erithil:BAAANQADCgYIBgABNQAECgYIDQACAAAAAA==.',
Es='Espe:BAABNQAECn8kAAITAAcKoBkqDwD7AQATAAcKoBkqDwD7AQAAAA==.',
Eu='Euli:BAAANQADCgMIBAABNQAFFAYIGgAUADQYAA==.',
Ev='Everayn:BAABNQAECn8+AAMRAAcKbRWCbADPAQARAAcKbRWCbADPAQAQAAUK7AmGEAH9AAABNQAECgkJXwABAGQkAA==.',
Ex='Exhalo:BAABNQAECn8kAAIMAAkKUxS1bwBAAgAMAAkKUxS1bwBAAgAAAA==.Exil:BAAANQAECgEIAQAAAA==.',
Fa='Fallen:BAABNQAECn8WAAIVAAgK7BKpQQDuAQAVAAgK7BKpQQDuAQAAAA==.Fasebreaker:BAAANQABCgcICQAAAA==.Faynor:BAABNQAECn8iAAITAAgKtSECBQAXAwATAAgKtSECBQAXAwAAAA==.',
Fe='Felwhisper:BAAANQAECgUIBQAAAA==.',
Fi='Finalycalm:BAAANQAECgQIBwAAAA==.Finimus:BAAANQAECgIJAwAAAA==.Finlok:BAAANQABCgMIAgAAAA==.Firêfly:BAAANQAECgUIBgAAAA==.',
Fl='Flingpooh:BAAANQAECgQIBwAAAA==.Flloran:BAAANQAECgQIEAAAAA==.',
Fr='Fraggle:BAECNQAFFH8RAAIRAAUK2hJ8DACSAQARAAUK2hJ8DACSAQA1AAQKfy0AAxEACQrZHHQfAPACABEACQrZHHQfAPACABAAAQpKDWOZATcAAAAA.Frogchi:BAAANQAECgUIEAAAAA==.Frostbité:BAAANQADCggIGgAAAA==.Frostybasham:BAAANQAECgEIAQAAAA==.Fruit:BAAANQAECgQICwAAAA==.',
Fu='Fubarut:BAAANQABCggIFwAAAA==.Fumikiko:BAAANQADCgYICgABNQAECgcICgACAAAAAA==.Funnybluffy:BAAANQAECgEIAgAAAA==.Fuzzbâll:BAAANQABCgYICQAAAA==.',
['Fí']='Físh:BAAANQADCgcICAABNQAECgcICgACAAAAAA==.',
Ga='Gali:BAAANQAECgEIAgAAAA==.Galindrael:BAAANQAECgEIAQAAAA==.Gargybyn:BAAANQADCgUIBwAAAA==.',
Gi='Girliepop:BAAANQAECgQIBgAAAA==.',
Gl='Glaistiguain:BAABNQAECn8mAAQWAAgKQiKhAwC3AgAWAAcK8COhAwC3AgAXAAQKTh8vIQBmAQAPAAEKAACtNAFFAAABNQAECggIMwAEABQhAA==.Glifin:BAAANQAECgYIDgAAAA==.Glizzeldra:BAAANQADCgUIBQAAAA==.Gloomstalkin:BAAANQAECgQICgABNQAECggIKgAUAEYVAA==.Glynna:BAAANQADCgUIBQAAAA==.',
Go='Gooning:BAAANQAECgEIAQABNQAFFAYICwAUAE4WAA==.',
Gr='Gr:BAABNQAECn8gAAIIAAcK/AjKSwCMAQAIAAcK/AjKSwCMAQAAAA==.Grasha:BAAANQAECgEIAgAAAA==.Gryffs:BAABNQAECn8gAAMYAAgKIxosDQBdAgAYAAgK0xksDQBdAgAMAAgKKBRedgAvAgAAAA==.Gràvity:BAAANQAECgEIBAABNQAECgYIAgACAAAAAA==.',
Gu='Guanino:BAAANQADCgcIDAAAAA==.Gutts:BAAANQAECgIIAwABNQAECgcIIgAJAGIgAA==.',
Gw='Gworg:BAAANQADCgEIAQAAAA==.',
['Gì']='Gìzmo:BAAANQAECgQIBwAAAA==.',
Ha='Halartion:BAABNQAECn8UAAIMAAgKdhvLaABSAgAMAAgKdhvLaABSAgAAAA==.Happirogue:BAAANQAECgYIBwABNQAFFAYIEwAZAM0dAA==.Haruun:BAAANQAECgQIBQAAAA==.',
He='Helridden:BAAANQAECgcIDgAAAA==.Hesmydaddy:BAABNQAECn8oAAINAAgKoAX6jABrAQANAAgKoAX6jABrAQAAAA==.',
Ho='Hoztok:BAAANQAECgQIBQAAAA==.',
Ic='Icemann:BAAANQAECgEIAwAAAA==.',
Im='Imherdaddy:BAABNQAECn8qAAIUAAgKRhXvQAD3AQAUAAgKRhXvQAD3AQAAAA==.',
It='Itakemeds:BAAANQADCgYJDAABNQAECgMIBQACAAAAAA==.',
Ja='Jaderean:BAAANQAECgMJBAAAAA==.Jarrack:BAABNQAECn8iAAMGAAgKDhTqsAAfAgAGAAgKFhHqsAAfAgAaAAQKrBYuIQDdAAAAAA==.Jaye:BAAANQABCgUICQAAAA==.',
Je='Jessicae:BAABNQAECn8eAAMNAAgKQRdcYAD8AQANAAgKQRdcYAD8AQAbAAEKfg0rKgAvAAAAAA==.Jeuno:BAAANQADCggIDgABNQAECgcICgACAAAAAA==.',
Ji='Jivederpy:BAABNQAECn8XAAIMAAgK9xvnSgClAgAMAAgK9xvnSgClAgAAAA==.',
Ju='Juicybooty:BAAANQADCgYIDAAAAA==.Junazeena:BAABNQAECn8UAAMSAAcK7QO/uAAcAQASAAcK7QO/uAAcAQADAAYKdAOGzADKAAAAAA==.',
Ka='Kayfabe:BAABNQAECn8bAAIGAAgKxwR6DAF0AQAGAAgKxwR6DAF0AQAAAA==.',
Ke='Keirasti:BAAANQAECgQICwAAAA==.Keishilda:BAAANQAECgIIAgAAAA==.Keladria:BAAANQAECgQICwAAAA==.Kelirra:BAAANQAECgIIAgAAAA==.Kenel:BAABNQAECn8pAAIVAAgKrA9EQAD2AQAVAAgKrA9EQAD2AQAAAA==.Kerea:BAABNQAECn8iAAIcAAgKMAT9QQAUAQAcAAgKMAT9QQAUAQAAAA==.Kermitt:BAAANQABCggIFgAAAA==.Keyarga:BAAANQADCgYICgABNQAECgQIDQACAAAAAA==.',
Kh='Khazadoom:BAAANQAECgQICwAAAA==.Khazargon:BAAANQAECgcICAAAAA==.',
Ki='Kicken:BAABNQAECn8bAAMPAAcK9xFrxgA5AQAPAAUKVg5rxgA5AQAXAAIKaRcSUQCLAAAAAA==.Kiitsuna:BAAANQADCgYIBgAAAA==.Kittyflerp:BAAANQADCgEJAQAAAA==.Kittyperry:BAAANQAECggIEAAAAA==.',
Ko='Korthelan:BAABNQAECn8nAAIdAAgKxhMAJQAaAgAdAAgKxhMAJQAaAgAAAA==.Kothara:BAABNQAECn8hAAIBAAgKKRQxagA8AgABAAgKKRQxagA8AgAAAA==.',
Kr='Krimzin:BAACNQAFFH8MAAIBAAUKcxt9CwCSAQABAAUKcxt9CwCSAQA1AAQKfyoAAgEACQo+JVIgABQDAAEACQo+JVIgABQDAAAA.Krystine:BAAANQAECgQICwAAAA==.',
Ks='Kserasera:BAABNQAECn8mAAIVAAkKIQ4zPAAQAgAVAAkKIQ4zPAAQAgAAAA==.',
Ku='Kuball:BAABNQAECn8iAAIJAAcKYiBZDwCDAgAJAAcKYiBZDwCDAgAAAA==.Kukuruku:BAAANQAECgUIBgAAAA==.Kumari:BAAANQAECggIEAAAAA==.',
['Kî']='Kîllara:BAAANQADCgUIBQAAAA==.',
Le='Lebronjames:BAABNQAECn8gAAIEAAgKAyG5JACrAgAEAAgKAyG5JACrAgAAAA==.Letheos:BAABNQAECn82AAIUAAkKiSL3CQBlAwAUAAkKiSL3CQBlAwAAAA==.Levanas:BAAANQADCgEIAQAAAA==.',
Li='Librarte:BAABNQAECn8YAAIQAAkKIAjqyQCBAQAQAAkKIAjqyQCBAQAAAA==.Limmewinks:BAAANQADCgUIBQAAAA==.Litty:BAAANQAECgUIEQAAAA==.',
Lo='Loalu:BAAANQAECgEIAQAAAA==.Locktärd:BAAANQAECgQJBQABNQAFFAYICwAUAE4WAA==.Lox:BAABNQAECn8hAAIXAAgKHhAoDgAWAgAXAAgKHhAoDgAWAgAAAA==.',
Lu='Lunatick:BAAANQAECgIIAQABNQAECggIAwACAAAAAA==.',
Ly='Lydirn:BAAANQAECgEIAQAAAA==.',
['Lí']='Lítterbox:BAAANQAECgIIAgAAAA==.',
Ma='Magedzen:BAAANQADCgEIAQAAAA==.Magicguy:BAABNQAECn8hAAIGAAcK3RpBlQBVAgAGAAcK3RpBlQBVAgAAAA==.Mahariel:BAABNQAECn8UAAIBAAYKLAiM0wBUAQABAAYKLAiM0wBUAQAAAA==.Mahdy:BAABNQAECn8qAAIQAAkK5xRXdwA6AgAQAAkK5xRXdwA6AgAAAA==.Mahoe:BAAANQADCgEIAQAAAA==.Malva:BAABNQAECn8aAAIDAAcKCwi2oQAtAQADAAcKCwi2oQAtAQAAAA==.Manrypurp:BAAANQAECgIIAgAAAA==.Marcie:BAABNQAECn8iAAIVAAgKfQs3TgCjAQAVAAgKfQs3TgCjAQAAAA==.Marracopa:BAAANQAECgEIAwAAAA==.Martinriggz:BAAANQAECgUICwAAAA==.',
Mc='Mchammer:BAAANQAECgEIAgAAAA==.',
Me='Meatyloaf:BAAANQAECgQICQAAAA==.Medsedation:BAABNQAECn8rAAINAAgKDQ8VcgDCAQANAAgKDQ8VcgDCAQAAAA==.Melkedrik:BAAANQAECgQICQAAAA==.Melleren:BAAANQAECgcICgAAAA==.Meridiane:BAAANQADCgEIAQAAAA==.',
Mi='Mirei:BAABNQAECn8bAAINAAcKmg/NhACEAQANAAcKmg/NhACEAQAAAA==.',
Mo='Moolander:BAAANQADCgUIBQAAAA==.Moovidlin:BAAANQAECgUIDQAAAA==.',
Mu='Mushhead:BAAANQAECgYJEAAAAA==.Mustepin:BAAANQADCgUJBQABNQAECggIHwAeAP4YAA==.',
My='Myrrdiache:BAAANQAECgEIAQAAAA==.Mythantherox:BAAANQADCgcIDQABNQAFFAIIBQAfAGcdAA==.Myzrybow:BAAANQAECgEIAQAAAA==.',
Na='Nanlaria:BAAANQADCgEIAQAAAA==.',
Ne='Neon:BAAANQAECgMIAwAAAA==.Nethershade:BAAANQAECgYIEwAAAA==.Netherstörm:BAAANQAECgMICAAAAA==.',
Ni='Niclea:BAAANQADCgUIBQAAAA==.Nightelm:BAAANQAECgcICgAAAA==.',
No='Noborû:BAAANQAECgQIBAABNQAECggIGwAEAGIeAA==.Noslien:BAAANQAECgEIAQAAAA==.Nostradamuz:BAABNQAECn8lAAIgAAgKBBpVFQBUAgAgAAgKBBpVFQBUAgAAAA==.',
Ny='Nymneria:BAAANQAECgQICQAAAA==.Nyxiera:BAABNQAECn8sAAIYAAkKfhczDQBdAgAYAAkKfhczDQBdAgABNQAECgkJOAAYADobAA==.Nyxstonia:BAABNQAECn84AAQYAAkKOhvdBwDWAgAYAAkKOhvdBwDWAgAeAAYKKwwRFgA3AQAMAAEKAAACYgEfAAAAAA==.',
['Nä']='Nämi:BAAANQAECgUICQAAAA==.',
Ol='Olierra:BAAANQADCgUIBQAAAA==.',
Om='Omnissiah:BAAANQABCgYIBgAAAA==.',
Or='Oreshin:BAAANQAECgUIDAAAAA==.Ornac:BAAANQADCgMIAwAAAA==.Orphantrope:BAAANQABCgEIAQAAAA==.',
Ot='Otto:BAABNQAECn8gAAIQAAgK8A8howDVAQAQAAgK8A8howDVAQAAAA==.Ottomagus:BAAANQADCgcIDAAAAA==.',
Pa='Palliate:BAAANQADCgYIBgABNQADCgUIBQACAAAAAA==.Pampoovy:BAEANQADCgYJBgABNQAECggIKgAhAGYVAA==.',
Pe='Persephoneia:BAABNQAECn8fAAIOAAgK5QhMMwCFAQAOAAgK5QhMMwCFAQAAAA==.',
Ph='Phobos:BAAANQABCgIIAgAAAA==.',
Pi='Piperclip:BAAANQADCgYIBgAAAA==.',
Po='Poraichu:BAAANQABCgYIBgAAAA==.',
Pr='Preacherman:BAAANQAECgMIBwAAAA==.Priority:BAAANQADCgQIBAAAAA==.',
Pu='Purplevane:BAAANQAECgMIAwAAAA==.',
Ra='Rabies:BAAANQABCggICwAAAA==.Rageoverrun:BAAANQAECgIIAwAAAA==.Ragequit:BAAANQAECgMJBAABNQAECgkJGwAgAJAYAA==.Ranson:BAAANQAECggICAAAAA==.Ravenloare:BAAANQADCgYIDwAAAA==.',
Re='Reaverheim:BAAANQAECgEIAQAAAA==.Remuz:BAAANQADCgYIBgAAAA==.',
Ri='Rilz:BAABNQAECn8lAAMEAAgKih7rIADEAgAEAAgKih7rIADEAgAFAAIKjQ7hkgBpAAAAAA==.',
Ro='Rockasham:BAABNQAECn8kAAISAAgKcAyBdgC6AQASAAgKcAyBdgC6AQAAAA==.Rodgerwabbet:BAAANQADCgMIAwAAAA==.Rottn:BAABNQAECn8bAAIgAAkKkBgYFgBMAgAgAAkKkBgYFgBMAgAAAA==.',
Sa='Safmen:BAAANQAECggIDgAAAA==.Saintdivine:BAAANQADCgEIAQAAAA==.Sanikoa:BAAANQAECgUIBQAAAA==.Saraid:BAABNQAECn8lAAQcAAgK1hQtMACVAQAcAAcKhBItMACVAQAVAAMK2xRYjACfAAAiAAEKuQ0lYQAtAAAAAA==.Saravase:BAAANQADCgcICAAAAA==.Saurot:BAAANQADCgcICQAAAA==.',
Se='Sempiternus:BAAANQAECgEIAQAAAA==.Sev:BAAANQAECgIIBAAAAA==.Señorcleave:BAAANQADCgQICgAAAA==.',
Sh='Shadk:BAEBNQAECn8nAAQUAAkKBBVRRgDdAQAUAAcKgBpRRgDdAQAEAAIKTgck5wArAAAFAAIKAABCyQAAAAAAAA==.Shadowstorm:BAABNQAECn8qAAIjAAgKzxY4EQBTAgAjAAgKzxY4EQBTAgAAAA==.Shelal:BAAANQADCggICAAAAA==.Shiki:BAAANQADCggIDwABNQAECgcIGwANAJoPAA==.Shinoto:BAAANQADCgYIDQABNQAECgcIFwAMAFkVAA==.',
Si='Silvein:BAACNQAFFH8KAAIRAAUKYRHGDQCAAQARAAUKYRHGDQCAAQA1AAQKfx8AAxEACQq+ISMQAEoDABEACAr1IyMQAEoDACAAAQoAAHZ2ACUAAAAA.Silverpower:BAAANQAECgUIBQAAAA==.Silverstead:BAAANQAECgEIAQAAAA==.',
Sk='Skyë:BAAANQADCgcIBwABNQAECgcICgACAAAAAA==.',
Sn='Snowynn:BAAANQADCgEIAQAAAA==.',
So='Sorrybro:BAAANQADCgcIDAAAAA==.',
Sp='Spycatcher:BAAANQADCgMIBAAAAA==.Spyro:BAABNQAECn8gAAQfAAkKUg97HgBoAQAfAAcKmgl7HgBoAQAkAAYKkA5fKwBNAQAlAAQKWQxNFgDKAAAAAA==.Spyroo:BAAANQAECgcIEgAAAA==.',
Sr='Sron:BAABNQAECn8lAAIBAAgK+RnfXABcAgABAAgK+RnfXABcAgAAAA==.',
St='Stankboy:BAAANQABCgQIBwAAAA==.',
Sw='Swooze:BAABNQAECn8ZAAMGAAgKfxbmwQD+AQAGAAgK/hTmwQD+AQAaAAEKgBJwQwA7AAAAAA==.',
Sy='Syndar:BAAANQADCgQIBAABNQAECggIFwASAAgeAA==.',
Sz='Szuzette:BAAANQAECgMIBwABNQAECgQICgACAAAAAA==.',
Ta='Tankcontrols:BAAANQAECgIIBAAAAA==.Tarlyn:BAAANQAECgQIDgABNQAECggIFQARABUSAA==.',
Te='Temuadêrna:BAAANQADCgYIBgAAAA==.',
Th='Thaenet:BAAANQADCgUIBwAAAA==.Thevelo:BAAANQAECgYIBgABNQAECgQIDQACAAAAAA==.Thunderkatze:BAABNQAECn8aAAIjAAkKCQnyFwDkAQAjAAkKCQnyFwDkAQAAAA==.Thánátós:BAAANQAECgQICAAAAA==.',
To='Topu:BAABNQAECn8YAAQDAAcK9RzFSQA4AgADAAcK9RzFSQA4AgAjAAIKrRGWLgB4AAASAAEKGAwkMAE1AAAAAA==.',
Tr='Tradarynn:BAAANQADCgYIBgAAAA==.',
Tw='Twinkles:BAAANQADCgMIAwAAAA==.',
Ty='Tyviae:BAAANQAECgQIBAAAAA==.',
Un='Unacceptable:BAAANQAECgUIEQAAAA==.',
Ur='Urais:BAAANQAECgMIAwABNQAECgcIAQACAAAAAA==.',
Us='Usdaprime:BAABNQAECn8WAAIVAAgKrwyVTACsAQAVAAgKrwyVTACsAQAAAA==.',
Va='Valhalia:BAABNQAECn8WAAMXAAgK4iG7BQC3AgAXAAcK4iG7BQC3AgAPAAMKiwwEEgGfAAAAAA==.Vanira:BAAANQADCgYIBgAAAA==.Vanrien:BAAANQADCggICAAAAA==.Varaelitha:BAAANQAECgEIAQAAAA==.',
Ve='Vengful:BAABNQAECn8XAAMZAAcKFRokRACeAQAZAAYKMxYkRACeAQAmAAIK1Rw/IwCiAAAAAA==.Vexy:BAAANQADCgMJBQAAAA==.',
Vh='Vhalúryn:BAAANQAECgQICwAAAA==.',
Vi='Vira:BAAANQADCgIIAgAAAA==.',
Vo='Vorumbrae:BAAANQAECgUIBwAAAA==.',
Wa='Wali:BAABNQAECn8ZAAIPAAcK6RWgjwC6AQAPAAcK6RWgjwC6AQAAAA==.',
Wh='Whatupbruh:BAAANQAECgQIBAAAAA==.',
Wi='Wildefaux:BAAANQADCggICAAAAA==.',
Wo='Wooties:BAAANQAECggIDwABNQAECgkJIwADANEZAA==.',
Wy='Wyleriya:BAABNQAECn8gAAIXAAgKhAvsEwDQAQAXAAgKhAvsEwDQAQAAAA==.',
Xa='Xaluhn:BAAANQADCgQIBAAAAA==.',
Xc='Xcella:BAAANQADCggIKQAAAA==.',
Xe='Xenophon:BAAANQADCgcIBwAAAA==.',
Xu='Xurael:BAAANQAECgYIDwAAAA==.',
Ye='Yelhsa:BAAANQAECgUICQAAAA==.Yelizaveta:BAAANQAECgMIDgAAAA==.',
Yl='Ylfcwen:BAAANQAECgEIAQAAAA==.',
Yu='Yukiri:BAAANQAECgUICwAAAA==.Yumei:BAAANQAECgYIBwABNQAECgcIGAADAPUcAA==.',
Za='Zalarah:BAAANQAECgQIDQAAAA==.Zardan:BAAANQAECgQICgAAAA==.',
Ze='Zeppik:BAAANQADCgYICgAAAA==.',
Zu='Zuggerker:BAABNQAECn8iAAIMAAgKXhg1YABqAgAMAAgKXhg1YABqAgAAAA==.',
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
