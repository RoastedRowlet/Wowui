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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane','Monk-Windwalker','Rogue-Subtlety','Rogue-Assassination','Hunter-Marksmanship','Warrior-Arms','Priest-Holy','Priest-Shadow','Warlock-Demonology','DeathKnight-Blood','Paladin-Retribution','Paladin-Holy','Shaman-Elemental','Monk-Brewmaster','Druid-Balance','Warlock-Affliction','Warlock-Destruction','Paladin-Protection','Warrior-Protection','DemonHunter-Havoc','Warrior-Fury','Mage-Frost','Priest-Discipline','Druid-Restoration','Hunter-Survival','Druid-Guardian','DemonHunter-Devourer','Evoker-Devastation','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abracadavr:BAAANQADCgUICQAAAA==.Absolomb:BAAANQABCgMIAwAAAA==.',
Ac='Acell:BAABNQAECn+aAAIBAAoK4iRTBQC4AwABAAoK4iRTBQC4AwAAAA==.',
Ad='Addison:BAAANQAECgUICQAAAA==.Adeleas:BAAANQAECgEIAgABNQAECgUICwACAAAAAA==.Adêrna:BAABNQAECn8/AAIDAAoKFBxOFwDnAgADAAoKFBxOFwDnAgAAAA==.',
Ag='Agate:BAABNQAECn8XAAIEAAoKIQRZKgCbAAAEAAoKIQRZKgCbAAAAAA==.Agba:BAABNQAECn8jAAMFAAkKmxMmUQDPAQAFAAkKmxMmUQDPAQAGAAEKqAn2tgAoAAAAAA==.Aglain:BAAANQADCgMIAwAAAA==.',
Ai='Aibrean:BAAANQAECgUICwAAAA==.Aiché:BAAANQADCgUIBQAAAA==.',
Ak='Aksul:BAAANQADCggICwAAAA==.',
Al='Alaala:BAAANQADCgUIBQAAAA==.Alaidan:BAAANQAECgcICwAAAA==.Alanus:BAABNQAECn85AAIHAAoKAA/8ZwDTAQAHAAoKAA/8ZwDTAQAAAA==.Alarion:BAAANQAECgUIDAAAAA==.Aliën:BAAANQAECgQICgAAAA==.Altana:BAAANQAECgIIAgABNQAECgcICAACAAAAAA==.Alydrus:BAAANQADCgcICAAAAA==.',
An='Angryelf:BAAANQAECgIIAwAAAA==.Angrymanjibs:BAAANQAECgIIAwAAAA==.Anitasummon:BAAANQAECgEIAwAAAA==.Annahe:BAABNQAECn82AAIIAAoKgRjWEgAhAgAIAAoKgRjWEgAhAgAAAA==.Annale:BAAANQADCgYIBgABNQAECgoKNgAIAIEYAA==.Annane:BAAANQAECgEIAQABNQAECgoKNgAIAIEYAA==.Anub:BAABNQAECn8lAAMJAAoKLBOjQwDXAQAJAAkKMRSjQwDXAQAKAAcKww1/TACPAQAAAA==.Anzala:BAAANQAECgMIBAAAAA==.',
Ar='Armsmaster:BAABNQAECn9CAAMFAAoKCyDaJgCgAgAFAAoKCyDaJgCgAgAGAAEK9ROspwA+AAAAAA==.Arrann:BAAANQAECgUICwAAAA==.Artemistha:BAAANQAECgYIDgAAAA==.',
Av='Avengharambe:BAAANQADCggIDwAAAA==.Avielle:BAAANQADCgUIBQAAAA==.',
Aw='Awakemage:BAAANQADCgYIBgAAAA==.',
['Aø']='Aøi:BAACNQAFFH8aAAIIAAcKKR31AQB/AgAIAAcKKR31AQB/AgA1AAQKfysAAggACgpsJfwFAHEDAAgACgpsJfwFAHEDAAAA.',
Ba='Baey:BAAANQABCgEIAQAAAA==.Bam:BAABNQAECn8gAAIHAAoKExhSVAAGAgAHAAoKExhSVAAGAgAAAA==.Barelycastin:BAABNQAECn89AAIDAAoKtA/RSwDMAQADAAoKtA/RSwDMAQAAAA==.',
Be='Beatnmameat:BAAANQAECgEIAgAAAA==.Beautiful:BAAANQAECgQIBwAAAA==.Beleriand:BAAANQAECgYIEQAAAA==.Belgarathh:BAAANQAECgYICgAAAA==.Bellei:BAAANQADCgcIBwAAAA==.Bellíon:BAAANQADCgEIAQAAAA==.',
Bl='Blacat:BAABNQAECn8WAAIEAAkKqA84EAAHAgAEAAkKqA84EAAHAgAAAA==.Blacksirloin:BAAANQADCgYIBgABNQAECgUIBgACAAAAAA==.Bloodshunter:BAABNQAECn8bAAMBAAkKah4uOADCAgABAAgK8SAuOADCAgALAAUK5g9iUADqAAAAAA==.',
Bo='Borda:BAAANQAECgUIDAAAAA==.',
Br='Brendenhunt:BAAANQADCggICAAAAA==.Broomhilda:BAAANQADCgcICAAAAA==.',
Bu='Buddypal:BAAANQAECgMIAwAAAA==.Buddypriest:BAAANQADCgIIAgABNQAECgMIAwACAAAAAA==.',
['Bâ']='Bâm:BAAANQAECgYIDgABNQAECgoKIAAHABMYAA==.',
Ca='Caidi:BAAANQAECgYIDgAAAA==.Calatixa:BAAANQADCgQIBAAAAA==.Carini:BAABNQAECn8xAAIHAAoK2w4KawDLAQAHAAoK2w4KawDLAQAAAA==.Catheryne:BAAANQAECgQIBAAAAA==.',
Ch='Chelsgrin:BAAANQAECgUICQABNQAECgkJFgAMAFkZAA==.Chickynuggy:BAAANQADCgcIBwAAAA==.Chrischan:BAAANQABCgMIAQAAAA==.Chónk:BAAANQAECgUIDAAAAA==.',
Cl='Clûtch:BAABNQAECn8jAAIFAAoKpRpeJQCqAgAFAAoKpRpeJQCqAgAAAA==.',
Co='Coldphoenix:BAAANQADCgEIAQAAAA==.Corvax:BAAANQADCgYIBgAAAA==.Corynthe:BAABNQAECn8/AAINAAkK9x0PMQBpAgANAAkK9x0PMQBpAgAAAA==.',
Cr='Crickie:BAAANQAECgYIEAAAAA==.Croftypongue:BAAANQADCgcIBwAAAA==.Crovaxis:BAABNQAECn86AAILAAoKYRknEQAeAgALAAoKYRknEQAeAgAAAA==.',
Da='Daddychill:BAAANQAECgUIBQAAAA==.Daedrìc:BAAANQADCgQIBAAAAA==.Damagetaken:BAAANQAECgYIDgAAAA==.Darktalyn:BAABNQAECn89AAMOAAoK8w0MGgC0AQAOAAoK8w0MGgC0AQANAAUKuBWbdgBeAQAAAA==.Dawi:BAAANQAECgIIAgAAAA==.',
De='Deathgrip:BAAANQADCgUIBgAAAA==.Deathhawkzz:BAABNQAECn8pAAIPAAkKORzPSwBwAgAPAAkKORzPSwBwAgAAAA==.Deekura:BAABNQAECn83AAMFAAkKhAw3MQBRAQAFAAgKbg03MQBRAQAQAAgKNgShVADdAAAAAA==.Deeyon:BAAANQAECgUICQAAAA==.Delusion:BAAANQAECgEIAgAAAA==.Demmin:BAAANQAECgcICAABNQAECgcIGAAMAPEGAA==.Dezireth:BAABNQAECn8wAAIBAAoKtAufiQD3AQABAAoKtAufiQD3AQAAAA==.',
Dh='Dhadzen:BAAANQAECgQICAAAAA==.Dhakastyr:BAAANQAECggICAAAAA==.',
Di='Dinak:BAAANQADCggIIwAAAA==.Dionan:BAABNQAECn83AAIRAAoKdRCPhwCoAQARAAoKdRCPhwCoAQAAAA==.Dirt:BAAANQAECgEIAgAAAA==.',
Do='Docs:BAABNQAECn8uAAMSAAoKpRfRMABMAgASAAoKpRfRMABMAgARAAYKMwts+QArAQAAAA==.Doks:BAABNQAECn86AAMDAAoKgxzMIACjAgADAAoKgxzMIACjAgATAAEKAAD4MAE4AAAAAA==.',
Dr='Dragana:BAAANQAECgIIBgAAAA==.Dragomalfoy:BAAANQADCgYIBgAAAA==.Dragster:BAAANQAECgYIBwAAAA==.Dragõn:BAAANQAECgEIAgAAAA==.Dreadmyr:BAAANQADCgUIBQAAAA==.Dreamfýre:BAAANQABCgIIAgAAAA==.Dridae:BAAANQAECgEIAQAAAA==.Drusilvia:BAAANQADCgcIBwAAAA==.',
Ea='Ealara:BAAANQADCggIDwAAAA==.',
Ec='Echidna:BAAANQADCggICAABNQAFFAgIHgASAHsEAA==.',
El='Elendor:BAAANQABCgYICQAAAA==.',
Em='Emiira:BAAANQADCggIFQAAAA==.',
En='Enthaii:BAAANQAECgEIAQAAAA==.',
Er='Erithil:BAAANQADCgYIBgABNQAECggIEwACAAAAAA==.',
Es='Espe:BAABNQAECn8yAAIUAAoK4xbABwDRAQAUAAoK4xbABwDRAQAAAA==.',
Eu='Euli:BAAANQADCgMIBAABNQAFFAcIGwAQAOIZAA==.',
Ev='Everayn:BAABNQAECn8+AAMSAAcKbRV1bQDPAQASAAcKbRV1bQDPAQARAAUK7AmCFAH9AAABNQAECgoKmgABAOIkAA==.',
Ex='Exhalo:BAABNQAECn8rAAIMAAoKFBUPcQBAAgAMAAoKFBUPcQBAAgAAAA==.Exil:BAAANQAECgYIDAAAAA==.',
Fa='Fallen:BAABNQAECn8lAAIVAAoKzRNcIQDeAQAVAAoKzRNcIQDeAQAAAA==.Fallenvoid:BAAANQADCgEIAQAAAA==.Fangg:BAAANQAECgQIDQAAAA==.Fasebreaker:BAAANQADCgcIBwAAAA==.Faynor:BAABNQAECn8pAAIUAAgKtSERBQAWAwAUAAgKtSERBQAWAwAAAA==.Faynór:BAABNQAECn8WAAIQAAgK6xTrIwDMAQAQAAgK6xTrIwDMAQABNQAECggIKQAUALUhAA==.',
Fe='Felwhisper:BAAANQAECgUIBQAAAA==.Feuerblut:BAAANQADCgQIBAAAAA==.',
Fi='Finalycalm:BAAANQAECgUIBQAAAA==.Finimus:BAAANQAECgIIAgAAAA==.Finlok:BAAANQABCgMIAgAAAA==.Firêfly:BAAANQAECgUIBQAAAA==.',
Fl='Flingpooh:BAAANQAECgYIEQAAAA==.Flloran:BAABNQAECn8hAAIVAAcKGgeiRQD6AAAVAAcKGgeiRQD6AAAAAA==.',
Fo='Foxylox:BAAANQADCgYIBgAAAA==.',
Fr='Fraggle:BAECNQAFFH8WAAISAAcKSRPYDACSAQASAAcKSRPYDACSAQA1AAQKf0MAAxIACgpZHs0fAPACABIACgpZHs0fAPACABEABwqxE/mqAGMBAAAA.Frogchi:BAABNQAECn8YAAMNAAYKHQQ4sgC6AAANAAYKHQQ4sgC6AAAOAAEK6AZzgAAqAAAAAA==.Frostbité:BAAANQAECgUICQAAAA==.Fruit:BAAANQAECgYIDwAAAA==.',
Fu='Fubarut:BAAANQADCggIDAAAAA==.Fumikiko:BAAANQADCgYICgABNQAECgcICAACAAAAAA==.Funnybluffy:BAAANQAECgEIBQAAAA==.Fuzzbâll:BAAANQABCgYICQAAAA==.',
['Fí']='Físh:BAAANQADCgcICAABNQAECgcICAACAAAAAA==.',
Ga='Gali:BAAANQAECgEIAQAAAA==.Gallows:BAAANQAECgIIBQAAAA==.Gargybyn:BAAANQADCgUIBwAAAA==.',
Gi='Girliepop:BAABNQAECn8aAAMSAAkKNxJRUwC1AQASAAkKNxJRUwC1AQARAAQKxAIfkgFCAAAAAA==.',
Gl='Glaistiguain:BAABNQAECn81AAQWAAoKbCCsAwC2AgAWAAoKSiCsAwC2AgAXAAUKRSGMBgBfAQAPAAEKAACHOAFFAAABNQAECgoKQgAFAAsgAA==.Glifin:BAABNQAECn8UAAIBAAYKfQl22wBKAQABAAYKfQl22wBKAQAAAA==.Glizzeldra:BAAANQADCgUIBQAAAA==.Gloomstalkin:BAAANQAECgQICQABNQAECgoKQAAQAPsUAA==.Glynna:BAAANQADCgUIBQAAAA==.',
Go='Gooning:BAABNQAECn8fAAMYAAoKPyN5AwAxAwAYAAoKPyN5AwAxAwARAAEKlA0wlwE9AAABNQAFFAYICwAQAE4WAA==.',
Gr='Gr:BAABNQAECn83AAIKAAoKDgr9EgCSAQAKAAoKDgr9EgCSAQAAAA==.Grasha:BAAANQAECgEIAQAAAA==.Gryffs:BAABNQAECn8vAAMZAAoKAh+TBwBgAgAZAAoKAh+TBwBgAgAMAAgKlg6urACtAQAAAA==.Gràvity:BAAANQAECgQIAwAAAA==.',
Gu='Guanino:BAAANQADCggIDQAAAA==.Gutts:BAAANQAECgMIAwABNQAECgoKNAAJACUeAA==.',
Gw='Gworg:BAAANQADCgEIAQAAAA==.',
['Gì']='Gìzmo:BAAANQAECgQIBQAAAA==.',
Ha='Halartion:BAABNQAECn8WAAIMAAkKWRkragBSAgAMAAkKWRkragBSAgAAAA==.Happirogue:BAAANQAECgYIBgABNQAFFAYIFQAaAM0dAA==.Haruun:BAAANQAECgQIDQAAAA==.',
He='Helridden:BAABNQAECn8eAAIMAAgK3QnugABwAQAMAAgK3QnugABwAQAAAA==.Hesmydaddy:BAABNQAECn8+AAINAAoKpAYBaQCKAQANAAoKpAYBaQCKAQAAAA==.',
Ho='Hoztok:BAAANQAECgQIBAAAAA==.',
Ic='Icemann:BAAANQABCggICAAAAA==.',
Im='Imherdaddy:BAABNQAECn9AAAIQAAoK+xRhJQDBAQAQAAoK+xRhJQDBAQAAAA==.',
It='Itakemeds:BAAANQADCgYJDAABNQAECgQICAACAAAAAA==.',
Ja='Jaderean:BAAANQAECgMJAwAAAA==.Jake:BAAANQAECgMIAwABNQAECgoKKgAbAMQYAA==.Jarrack:BAABNQAECn89AAMHAAkK2hQ4bADIAQAHAAkKMxM4bADIAQAcAAQKrBaaIQDcAAAAAA==.Jaye:BAAANQABCgUICQAAAA==.',
Je='Jessicae:BAABNQAECn8pAAMNAAoKqBZWWQDBAQANAAoKqBZWWQDBAQAdAAEKfg2oKgAvAAAAAA==.Jeuno:BAAANQADCggIDgABNQAECgcICAACAAAAAA==.',
Ji='Jivederpy:BAABNQAECn8sAAIMAAkK0x5QTACkAgAMAAkK0x5QTACkAgAAAA==.',
Ju='Juicybooty:BAAANQAECgEIAQAAAA==.Junazeena:BAABNQAECn8bAAMTAAgKKAUYuwAcAQATAAgKKAUYuwAcAQADAAYKdAO6zgDKAAAAAA==.',
Ka='Kahlisto:BAAANQAECggICAAAAA==.Katrina:BAAANQAECggIEQAAAA==.Kayfabe:BAABNQAECn8jAAIHAAoK9ATwDgF0AQAHAAoK9ATwDgF0AQAAAA==.',
Ke='Keirasti:BAAANQAECgUICwAAAA==.Keishilda:BAAANQAECgQIBAAAAA==.Keladria:BAAANQAECgUICwAAAA==.Kelirra:BAAANQAECgQIBAAAAA==.Kenel:BAABNQAECn8/AAIVAAoKnhAMJgC4AQAVAAoKnhAMJgC4AQAAAA==.Kerea:BAABNQAECn8/AAIeAAkKiAXAOgAQAQAeAAkKiAXAOgAQAQAAAA==.Kermitt:BAAANQADCgQIBAAAAA==.Keyarga:BAAANQADCgcIDwABNQAECgkJFwAfAMoSAA==.',
Kh='Khazadoom:BAAANQAECgUIDAAAAA==.Khazargon:BAABNQAECn8hAAIRAAoKBxwHTAA2AgARAAoKBxwHTAA2AgAAAA==.',
Ki='Kicken:BAABNQAECn87AAQXAAkK+xH9GgCAAAAPAAcKmA73jwAmAQAXAAIKaRf9GgCAAAAWAAEKdxQeJgBGAAAAAA==.Kiitsuna:BAAANQADCgYIBgAAAA==.Kittyflerp:BAAANQADCgEJAQAAAA==.Kittyperry:BAACNQAFFH8GAAIVAAYKtRKFBwCVAQAVAAYKtRKFBwCVAQA1AAQKfyUABQQACgrGIaoFAKcCABUACQrJIasNAMACAAQACQoJHaoFAKcCACAACQppFXcZAN4BAB4AAgpjCI9lAG8AAAAA.Kizmo:BAAANQAECgcICQAAAA==.',
Ko='Korthelan:BAABNQAECn8/AAIhAAoK2hNoJQAaAgAhAAoK2hNoJQAaAgAAAA==.Kothara:BAABNQAECn8+AAIBAAkKiRS/awA7AgABAAkKiRS/awA7AgAAAA==.',
Kr='Krimzin:BAACNQAFFH8PAAIBAAgK+RfSCwCSAQABAAgK+RfSCwCSAQA1AAQKf0MAAgEACgofJisCAIIDAAEACgofJisCAIIDAAAA.Krystine:BAABNQAECn8XAAIeAAgKohbaJACvAQAeAAgKohbaJACvAQAAAA==.',
Ks='Kserasera:BAABNQAECn9DAAIVAAoKpBXUGgAeAgAVAAoKpBXUGgAeAgAAAA==.',
Ku='Kuball:BAABNQAECn80AAIJAAoKJR6bDwCCAgAJAAoKJR6bDwCCAgAAAA==.Kuchiki:BAAANQADCgEIAQAAAA==.Kukuruku:BAAANQAECgUIBQAAAA==.Kumari:BAABNQAECn8qAAMDAAoKSQHw0gDBAAADAAoKSQHw0gDBAAATAAEKkwEUBgEeAAAAAA==.Kungfü:BAAANQADCgYIBgAAAA==.Kurailatha:BAAANQADCgEIAQAAAA==.',
['Kî']='Kîllara:BAAANQADCgUIBQAAAA==.',
Le='Lebronjames:BAABNQAECn8iAAIFAAoKBx8WJQCrAgAFAAoKBx8WJQCrAgAAAA==.Letheos:BAABNQAECn9IAAIQAAoKICQfCgBkAwAQAAoKICQfCgBkAwAAAA==.Levanas:BAAANQADCgEIAQAAAA==.',
Li='Librarte:BAABNQAECn8dAAIRAAoKsgfyzACBAQARAAoKsgfyzACBAQAAAA==.Limmewinks:BAAANQADCgUIBQABNQAECgIIAQACAAAAAA==.Litty:BAABNQAECn8aAAIHAAcKuxZ4ogBNAQAHAAcKuxZ4ogBNAQAAAA==.',
Lo='Loalu:BAAANQAECgEIAQAAAA==.Locktärd:BAAANQAECgQIBAABNQAFFAYICwAQAE4WAA==.Lox:BAABNQAECn8+AAIXAAkKFhE/DgAVAgAXAAkKFhE/DgAVAgAAAA==.',
Lu='Lunatick:BAAANQAECgIIAQABNQAECggIBwACAAAAAA==.',
Ly='Lydirn:BAAANQAECgMIBAAAAA==.',
['Lí']='Lítterbox:BAAANQAECgIIAgAAAA==.',
Ma='Magedzen:BAAANQADCgEIAQAAAA==.Magicguy:BAABNQAECn8pAAIHAAoKABaylgBTAgAHAAoKABaylgBTAgAAAA==.Mahariel:BAABNQAECn8qAAIBAAoKjgrVagDSAQABAAoKjgrVagDSAQAAAA==.Mahdy:BAABNQAECn9GAAIRAAoKdRqGRQBKAgARAAoKdRqGRQBKAgAAAA==.Mahoe:BAAANQAECgEIAgAAAA==.Malva:BAABNQAECn8yAAIDAAoKxhecIQCeAgADAAoKxhecIQCeAgAAAA==.Manrypurp:BAABNQAECn8aAAIhAAoKyA/3GQDLAQAhAAoKyA/3GQDLAQAAAA==.Marcie:BAABNQAECn84AAIVAAkKdguqMgBeAQAVAAkKdguqMgBeAQAAAA==.Marracopa:BAAANQAECgEIAwAAAA==.Martinriggz:BAABNQAECn8aAAIHAAkKCAHVNQFSAAAHAAkKCAHVNQFSAAAAAA==.',
Mc='Mchammer:BAAANQADCgIIAgAAAA==.',
Me='Meatyloaf:BAAANQAECgQIBwAAAA==.Medsedation:BAABNQAECn9GAAINAAoKixNWPwAnAgANAAoKixNWPwAnAgAAAA==.Melkedrik:BAAANQAECgQIBwAAAA==.Melleren:BAAANQAECggICAAAAA==.Meridiane:BAAANQADCgEIAQAAAA==.Mesomorph:BAAANQADCgQIBAAAAA==.',
Mi='Mirei:BAABNQAECn88AAINAAkKUw67YACnAQANAAkKUw67YACnAQAAAA==.Mitsurugi:BAAANQAECgEIAQABNQAECgoKPgAMAPEQAA==.',
Mo='Mojam:BAAANQAECgEIAgAAAA==.Moolander:BAAANQADCgUIBQAAAA==.Moovidlin:BAABNQAECn8YAAIMAAcK8QaixwDRAAAMAAcK8QaixwDRAAAAAA==.Morinnas:BAAANQAECgEIAQAAAA==.',
Mu='Mushhead:BAAANQAECgYJDwAAAA==.Mustepin:BAAANQADCgUIBQABNQAECgoKKgAbAMQYAA==.',
My='Mythantherox:BAAANQAECgIIAgABNQAFFAIIBwAiAGcdAA==.',
Na='Nachtaugen:BAAANQADCgcICQAAAA==.Nanlaria:BAAANQAECgEIAQAAAA==.Nanyline:BAAANQAECgEIAQAAAA==.Naoko:BAAANQAECgEIAQAAAA==.',
Ne='Nellas:BAAANQAECgEIAQAAAA==.Neon:BAAANQAECgMIAwAAAA==.Nethershade:BAABNQAECn8sAAIKAAgKtBtYDgDVAQAKAAgKtBtYDgDVAQAAAA==.Netherstörm:BAAANQAECgcIDQAAAA==.',
Ni='Niclea:BAAANQADCgUIBQAAAA==.Nightelm:BAAANQAECgcICAAAAA==.',
No='Noborû:BAAANQAECgYIDgABNQAECgoKIwAFAKUaAA==.Noslien:BAAANQAECgEIAQAAAA==.Nostradamuz:BAABNQAECn86AAIYAAoKXxrcEQD3AQAYAAoKXxrcEQD3AQAAAA==.',
Ny='Nymneria:BAAANQAECgQIBwAAAA==.Nyxiera:BAABNQAECn9MAAIZAAoK9BdhDQBcAgAZAAoK9BdhDQBcAgABNQAECgoKUQAZAC0aAA==.Nyxstonia:BAABNQAECn9RAAQZAAoKLRr4BwDVAgAZAAoKLRr4BwDVAgAbAAYKKwxHFgA3AQAMAAQKKAKUIQEzAAAAAA==.',
['Nä']='Nämi:BAAANQAECgYIDQAAAA==.',
Ol='Olierra:BAAANQADCgUIBQAAAA==.',
Om='Omnissiah:BAAANQABCgYIBgAAAA==.',
Or='Oreshin:BAAANQAECgUICAAAAA==.Orihimei:BAAANQABCggIDAAAAA==.Ornac:BAAANQADCgMIAwAAAA==.Orphantrope:BAAANQABCgEIAQAAAA==.',
Ot='Otto:BAABNQAECn89AAIRAAkKixPgfgC6AQARAAkKixPgfgC6AQAAAA==.Ottomagus:BAAANQADCgcIDAAAAA==.',
Pa='Palliate:BAAANQAECgEIAQABNQADCgUIBQACAAAAAA==.Pampoovy:BAEANQADCgYJBgABNQAECgoKOwAfAO8YAA==.',
Pb='Pbjam:BAAANQAECggICAAAAA==.',
Pe='Persephoneia:BAABNQAECn82AAIOAAoKRwr+HACSAQAOAAoKRwr+HACSAQAAAA==.',
Ph='Phobos:BAAANQABCgIIAgABNQAECgIIBQACAAAAAA==.',
Pi='Piperclip:BAAANQADCgYIBgAAAA==.Pitnick:BAAANQADCgEIAQAAAA==.',
Po='Poraichu:BAAANQADCggICAAAAA==.',
Pr='Preacherman:BAAANQAECgQICQAAAA==.Priority:BAAANQADCgQIBAAAAA==.',
Pu='Punjistake:BAAANQAECggICQAAAA==.Purplevane:BAAANQAECgMIAwAAAA==.',
Qu='Quna:BAAANQADCgIIAgAAAA==.',
Ra='Rabies:BAAANQADCgYICwAAAA==.Rageoverrun:BAAANQAECgIIAgAAAA==.Ragequit:BAAANQAECgMIAwABNQAECgoKKgAYAOkbAA==.Ranson:BAAANQAECggICAAAAA==.Ravenloare:BAAANQAECgEIAQAAAA==.',
Re='Reaverheim:BAAANQAECgcICgAAAA==.Remuz:BAAANQADCgYIBgAAAA==.',
Ri='Rilz:BAABNQAECn8/AAMFAAoKaB/0DQCPAgAFAAoKaB/0DQCPAgAGAAIKjQ78lQBpAAAAAA==.',
Ro='Rockasham:BAABNQAECn8oAAITAAkKtgs0eAC5AQATAAkKtgs0eAC5AQAAAA==.Rodgerwabbet:BAAANQADCgMIAwAAAA==.Rottn:BAABNQAECn8qAAIYAAoK6Rt2DwAdAgAYAAoK6Rt2DwAdAgAAAA==.',
Sa='Safmen:BAABNQAECn8VAAIZAAkKhgc/IwAvAQAZAAkKhgc/IwAvAQAAAA==.Saintdivine:BAAANQAECgEIAQABNQAECgQIBAACAAAAAA==.Sanikoa:BAAANQAECgUIBQAAAA==.Saraid:BAABNQAECn89AAQeAAoKkhJBJAC1AQAeAAoKkhJBJAC1AQAgAAcK9AkKPAC9AAAVAAUKSg3QjQCfAAAAAA==.Saravase:BAAANQAECgEIAgAAAA==.',
Se='Sev:BAAANQAECgIIAgAAAA==.Señorcleave:BAAANQADCgQICgAAAA==.',
Sh='Shadk:BAEBNQAECn89AAQQAAoKnBU9LgCKAQAQAAkKBRc9LgCKAQAFAAIKTgdv6QArAAAGAAIKAABfzQAAAAAAAA==.Shadowstorm:BAABNQAECn9BAAIjAAoKDhZaEAD7AQAjAAoKDhZaEAD7AQAAAA==.Shelal:BAAANQADCggICAAAAA==.Shiki:BAAANQADCggIDwABNQAECgkJPAANAFMOAA==.Shinoto:BAAANQADCgYIDQABNQAECggIJAAMACcYAA==.',
Si='Sieghart:BAAANQAECgEIAgAAAA==.Silvein:BAACNQAFFH8MAAISAAcKxhAgDgCAAQASAAcKxhAgDgCAAQA1AAQKfzYAAxIACgqWIVUQAEoDABIACQqKI1UQAEoDABgACQp4DlEhAE0BAAAA.Silverpower:BAAANQAECgUIBQAAAA==.',
Sk='Skyë:BAAANQADCgcIBwABNQAECgcICAACAAAAAA==.',
Sn='Snowynn:BAAANQAECgEIAgAAAA==.',
So='Sorrybro:BAAANQAECgQIBQAAAA==.',
Sp='Spycatcher:BAAANQADCgQIBgAAAA==.Spyro:BAABNQAECn8iAAQiAAoKOhK5HgBoAQAiAAcKmgm5HgBoAQAkAAgKlQytKwBNAQAlAAQKWQyHFgDKAAAAAA==.Spyroo:BAABNQAECn8gAAIlAAkKKA5mCgDKAQAlAAkKKA5mCgDKAQAAAA==.',
Sr='Sron:BAABNQAECn82AAIBAAoK5BVwXgBbAgABAAoK5BVwXgBbAgAAAA==.',
St='Stankboy:BAAANQABCgQIBwAAAA==.',
Su='Sumwhiteguy:BAAANQAECgEIAQAAAA==.Suzuka:BAAANQADCgEIAQABNQAECgkJPAANAFMOAA==.',
Sw='Swooze:BAABNQAECn8ZAAMHAAgKfxaewwD9AQAHAAgK/hSewwD9AQAcAAEKgBJDRAA7AAAAAA==.',
Sy='Syndar:BAAANQADCgQIBAABNQAECgoKJQATACseAA==.',
Sz='Szuzette:BAAANQAECgMIBQABNQAECgQICQACAAAAAA==.',
Ta='Tankcontrols:BAAANQAECgYIEAAAAA==.Tarlyn:BAABNQAECn8pAAISAAoKBR98EgAYAwASAAoKBR98EgAYAwAAAA==.',
Te='Temuadêrna:BAAANQADCgYIBgAAAA==.',
Th='Thaenet:BAAANQADCgUIBwAAAA==.Thevelo:BAAANQAECgUIBQABNQAECgkJFwAfAMoSAA==.Thunderkatze:BAABNQAECn8aAAIjAAkKCQlJGADjAQAjAAkKCQlJGADjAQAAAA==.Thánátós:BAAANQAECgQIBgAAAA==.',
Ti='Tinyfubar:BAAANQADCgEIAQAAAA==.Tissaia:BAAANQAECgEIAQAAAA==.',
To='Toberson:BAAANQAECgEIAQAAAA==.Tootsunami:BAAANQADCgEIAQAAAA==.Topu:BAABNQAECn8ZAAQDAAgKHx3CSgA4AgADAAgKHx3CSgA4AgAjAAIKrREtLwB4AAATAAEKGAzJNAE0AAAAAA==.',
Tr='Tradarynn:BAAANQAECgQIBAAAAA==.Trek:BAAANQAECggIAQAAAA==.',
Tw='Twinkles:BAAANQADCgMIAwAAAA==.',
Ty='Tyviae:BAAANQAECgcIEAAAAA==.',
Un='Unacceptable:BAAANQAECgUIDgAAAA==.',
Ur='Urais:BAAANQAECgMIAwABNQAECgoKRQALAMUjAA==.',
Us='Usdaprime:BAACNQAFFH8FAAIVAAIKPAeBGwBrAAAVAAIKPAeBGwBrAAA1AAQKfy4AAhUACgoYEGwkAMQBABUACgoYEGwkAMQBAAAA.',
Va='Valhalia:BAABNQAECn8uAAMXAAoK5CCLAQCYAgAXAAkK5CCLAQCYAgAPAAMKxRNE2wCJAAAAAA==.Vanira:BAAANQADCgYIBgAAAA==.Vanrien:BAAANQADCggICAAAAA==.Varaelitha:BAAANQAECgQIBQAAAA==.Vashni:BAAANQAECgEIAQAAAA==.',
Ve='Velinariae:BAAANQAECgIIAQAAAA==.Velo:BAAANQADCggICAABNQAECgkJFwAfAMoSAA==.Vengful:BAABNQAECn8XAAMaAAcKFRoERQCeAQAaAAYKMxYERQCeAQAmAAIK1RzCIwCiAAAAAA==.Vexy:BAAANQADCgMJBQAAAA==.',
Vh='Vhalúryn:BAAANQAECgUICwAAAA==.',
Vi='Vicerion:BAAANQADCgYIBgAAAA==.Vira:BAAANQADCgIIAgAAAA==.',
Vo='Vorumbrae:BAAANQAECgUIBwAAAA==.',
Wa='Wali:BAABNQAECn8vAAIPAAoKmRLzRgDuAQAPAAoKmRLzRgDuAQAAAA==.',
Wh='Whatupbruh:BAAANQAECgQIBAAAAA==.',
Wi='Wildefaux:BAAANQADCggICAAAAA==.',
Wo='Wooties:BAABNQAECn8xAAIKAAoKKhPKDADxAQAKAAoKKhPKDADxAQABNQAECgoKOgADAIMcAA==.',
Wy='Wyleriya:BAABNQAECn8xAAIXAAkKsQ1YBwBLAQAXAAkKsQ1YBwBLAQAAAA==.',
Xa='Xaluhn:BAAANQADCgQIBAAAAA==.',
Xc='Xcella:BAAANQAECgEIAgAAAA==.',
Xe='Xenophon:BAAANQADCgcIBwAAAA==.',
Xu='Xurael:BAAANQAECgUIEAAAAA==.',
Xy='Xyn:BAAANQADCgcIBwABNQAECgUICwACAAAAAA==.',
Ye='Yelhsa:BAAANQAECgYIDQAAAA==.Yelizaveta:BAABNQAECn8dAAIBAAcKbwR8zwD5AAABAAcKbwR8zwD5AAAAAA==.',
Yl='Ylfcwen:BAAANQADCgYIBgAAAA==.',
Yu='Yukiri:BAAANQAECgQIDgAAAA==.Yumei:BAAANQAECgcIBgABNQAECggIGQADAB8dAA==.',
Za='Zalarah:BAAANQAECgUIDAAAAA==.Zarathusa:BAAANQADCgQIBAAAAA==.Zardan:BAAANQAECgYIEQAAAA==.',
Ze='Zeppik:BAAANQADCgYIDAAAAA==.',
Zu='Zuggerker:BAABNQAECn8/AAIMAAkK9ReBYQBpAgAMAAkK9ReBYQBpAgAAAA==.',
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
