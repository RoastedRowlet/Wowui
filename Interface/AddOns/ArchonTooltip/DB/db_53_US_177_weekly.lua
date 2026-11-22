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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane','Monk-Windwalker','Rogue-Subtlety','Rogue-Assassination','Hunter-Marksmanship','Paladin-Protection','Warrior-Arms','Priest-Holy','Priest-Shadow','Warlock-Demonology','DeathKnight-Blood','Paladin-Retribution','Paladin-Holy','Shaman-Elemental','Monk-Brewmaster','Druid-Balance','Warlock-Affliction','Warlock-Destruction','Warrior-Protection','DemonHunter-Havoc','Warrior-Fury','Mage-Frost','Priest-Discipline','Druid-Restoration','Hunter-Survival','Druid-Guardian','DemonHunter-Devourer','Evoker-Devastation','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abracadavr:BAAANQADCgUICQAAAA==.Absolomb:BAAANQADCgEIAQAAAA==.',
Ac='Acell:BAABNQAECn+iAAIBAAoKByVTBQC4AwABAAoKByVTBQC4AwAAAA==.',
Ad='Addison:BAAANQAECgUICQAAAA==.Adeleas:BAAANQADCggIFwABNQAECgYICgACAAAAAA==.Adêrna:BAABNQAECn8/AAIDAAoKFBwrGgDlAgADAAoKFBwrGgDlAgAAAA==.',
Ag='Agate:BAABNQAECn8XAAIEAAoKIQS5LgCbAAAEAAoKIQS5LgCbAAAAAA==.Agba:BAABNQAECn8jAAMFAAkKmxMmUQDPAQAFAAkKmxMmUQDPAQAGAAEKqAn2tgAoAAAAAA==.Aglain:BAAANQADCgMIAwAAAA==.',
Ai='Aibrean:BAAANQAECgUICwAAAA==.Aiché:BAAANQADCgUIBQAAAA==.',
Ak='Aksul:BAAANQADCggICwAAAA==.',
Al='Alaala:BAAANQADCgUIBQAAAA==.Alaidan:BAAANQAECgcICgAAAA==.Alanus:BAABNQAECn85AAIHAAoKAA9fbwDTAQAHAAoKAA9fbwDTAQAAAA==.Alarion:BAAANQAECgUICgAAAA==.Alderon:BAAANQABCgYIEQAAAA==.Aliën:BAAANQAECgQICgAAAA==.Altana:BAAANQAECgIIAgABNQAECgcICAACAAAAAA==.Alydrus:BAAANQADCgcICAAAAA==.',
An='Angryelf:BAAANQAECgIIAwAAAA==.Angrymanjibs:BAAANQAECgIIAwAAAA==.Anitasummon:BAAANQAECgQIBQAAAA==.Annahe:BAABNQAECn82AAIIAAoKgRiEFAAgAgAIAAoKgRiEFAAgAgAAAA==.Annale:BAAANQADCgYIBgABNQAECgoKNgAIAIEYAA==.Anub:BAABNQAECn8lAAMJAAoKLBPuSgDVAQAJAAkKMRTuSgDVAQAKAAcKww1/TACPAQAAAA==.Anzala:BAAANQAECgMIBAAAAA==.',
Ar='Armsmaster:BAABNQAECn9CAAMFAAoKCyDaJgCgAgAFAAoKCyDaJgCgAgAGAAEK9ROspwA+AAAAAA==.Arrann:BAAANQAECgUICgAAAA==.Artemistha:BAAANQAECgYIDgAAAA==.',
Av='Avengharambe:BAAANQAECgUIBQAAAA==.Avielle:BAAANQADCgUIBQAAAA==.',
Aw='Awakemage:BAAANQADCgYIBgAAAA==.',
['Aø']='Aøi:BAACNQAFFH8aAAIIAAcKKR31AQB/AgAIAAcKKR31AQB/AgA1AAQKfysAAggACgpsJfwFAHEDAAgACgpsJfwFAHEDAAAA.',
Ba='Baey:BAAANQABCgEIAQAAAA==.Bam:BAABNQAECn8gAAIHAAoKExijWgAFAgAHAAoKExijWgAFAgAAAA==.Barelycastin:BAABNQAECn89AAIDAAoKtA/sUgDHAQADAAoKtA/sUgDHAQAAAA==.',
Be='Beautiful:BAAANQAECgQIBwAAAA==.Beleriand:BAAANQAECgYIEQAAAA==.Belgarathh:BAAANQAECgYICgAAAA==.Bellei:BAAANQADCgcIBwAAAA==.Bellíon:BAAANQADCgEIAQAAAA==.',
Bl='Blacat:BAABNQAECn8WAAIEAAkKqA84EAAHAgAEAAkKqA84EAAHAgAAAA==.Blacksirloin:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.Bloodshunter:BAABNQAECn8bAAMBAAkKah4uOADCAgABAAgK8SAuOADCAgALAAUK5g9iUADqAAAAAA==.',
Bo='Bonejovi:BAAANQADCgYIBgABNQAECgoKLQAMAOkbAA==.Borda:BAAANQAECgYIDQAAAA==.',
Br='Brendenhunt:BAAANQADCggICAAAAA==.Broomhilda:BAAANQADCggIDgAAAA==.',
Bu='Buddypal:BAAANQAECgMIAwAAAA==.Buddypriest:BAAANQADCgIIAgABNQAECgMIAwACAAAAAA==.',
['Bâ']='Bâm:BAAANQAECgYICwABNQAECgoKIAAHABMYAA==.',
Ca='Caidi:BAAANQAECgYICwAAAA==.Calatixa:BAAANQADCgQIBAAAAA==.Carini:BAABNQAECn8xAAIHAAoK2w7qcgDKAQAHAAoK2w7qcgDKAQAAAA==.Catheryne:BAAANQAECgQIBAAAAA==.',
Ch='Chelsgrin:BAAANQAECgUICQABNQAECgkJFgANAFkZAA==.Chickynuggy:BAAANQADCgcIBwAAAA==.Chrischan:BAAANQABCgMIAQAAAA==.Chónk:BAAANQAECgYICgAAAA==.',
Cl='Clûtch:BAABNQAECn8jAAIFAAoKpRpeJQCqAgAFAAoKpRpeJQCqAgAAAA==.',
Co='Coldphoenix:BAAANQADCgEIAgAAAA==.Corvax:BAAANQADCgYIBgAAAA==.Corynthe:BAABNQAECn9IAAIOAAoKtx3IJwCwAgAOAAoKtx3IJwCwAgAAAA==.',
Cr='Crickie:BAAANQAECgUIEwAAAA==.Croftypongue:BAAANQADCgcIBwAAAA==.Crovaxis:BAABNQAECn86AAILAAoKYRmLEgAZAgALAAoKYRmLEgAZAgAAAA==.',
Da='Daddychill:BAAANQAECgUIBQAAAA==.Daedrìc:BAAANQADCgQIBAAAAA==.Damagetaken:BAAANQAECgYIDAAAAA==.Darktalyn:BAABNQAECn89AAMPAAoK8w0RHAC0AQAPAAoK8w0RHAC0AQAOAAUKuBW0fwBaAQAAAA==.Dawi:BAAANQAECgIIAgAAAA==.',
De='Deathgrip:BAAANQADCgUIBgAAAA==.Deathhawkzz:BAABNQAECn8pAAIQAAkKORzPSwBwAgAQAAkKORzPSwBwAgAAAA==.Deekura:BAABNQAECn83AAMFAAkKhAxiNABPAQAFAAgKbg1iNABPAQARAAgKNgQAWgDYAAAAAA==.Deeyon:BAAANQAECgUICQAAAA==.Delusion:BAAANQAECgEIAQAAAA==.Demmin:BAAANQAECgcIBwABNQAECgkJHAANAAwHAA==.Dezireth:BAABNQAECn8wAAIBAAoKtAufiQD3AQABAAoKtAufiQD3AQAAAA==.',
Dh='Dhadzen:BAAANQAECgQIBgAAAA==.Dhakastyr:BAAANQAECggICAAAAA==.',
Di='Dinak:BAAANQADCggIKAAAAA==.Dionan:BAABNQAECn83AAISAAoKdRBtlACjAQASAAoKdRBtlACjAQAAAA==.',
Do='Docs:BAABNQAECn8uAAMTAAoKpRfdNwA8AgATAAoKpRfdNwA8AgASAAYKMwts+QArAQAAAA==.Doks:BAABNQAECn86AAMDAAoKgxwJJQCdAgADAAoKgxwJJQCdAgAUAAEKAAD4MAE4AAAAAA==.',
Dr='Dragana:BAAANQAECgIIAwAAAA==.Dragomalfoy:BAAANQADCgYIBgAAAA==.Dragster:BAAANQAECgYIBwAAAA==.Dragõn:BAAANQADCgEIAQAAAA==.Dreadmyr:BAAANQADCgUIBQAAAA==.Dreamfýre:BAAANQABCgIIAgAAAA==.Dridae:BAAANQAECgEIAQAAAA==.Drusilvia:BAAANQADCgcIBwAAAA==.',
Ea='Ealara:BAAANQADCggIDwAAAA==.',
Ec='Echidna:BAAANQADCggICAABNQAFFAgIHgATAHsEAA==.',
El='Elendor:BAAANQABCgYICQAAAA==.',
Em='Emiira:BAAANQADCggIFQAAAA==.',
En='Enthaii:BAAANQAECgEIAQAAAA==.',
Er='Erithil:BAAANQADCgYIBgABNQAECggIGwATANQYAA==.',
Es='Espe:BAABNQAECn8yAAIVAAoK4xZdCADRAQAVAAoK4xZdCADRAQAAAA==.',
Eu='Euli:BAAANQADCgMIBAABNQAFFAcIGwARAOIZAA==.',
Ev='Everayn:BAABNQAECn8+AAMTAAcKbRV1bQDPAQATAAcKbRV1bQDPAQASAAUK7AmCFAH9AAABNQAECgoKogABAAclAA==.',
Ex='Exhalo:BAABNQAECn8rAAINAAoKFBUPcQBAAgANAAoKFBUPcQBAAgAAAA==.Exil:BAAANQAECgUIDgAAAA==.',
Fa='Fallen:BAABNQAECn8mAAIWAAoKEBXGIQDvAQAWAAoKEBXGIQDvAQAAAA==.Fallenvoid:BAAANQADCgEIAQAAAA==.Fangg:BAAANQAECgQIDwAAAA==.Fasebreaker:BAAANQADCgcICAAAAA==.Faynor:BAABNQAECn8pAAIVAAgKtSERBQAWAwAVAAgKtSERBQAWAwABNQAECgkJHwARANsUAA==.Faynór:BAABNQAECn8fAAIRAAkK2xS6HAAXAgARAAkK2xS6HAAXAgAAAA==.',
Fe='Felwhisper:BAAANQAECgUIBQAAAA==.Feuerblut:BAAANQADCgQIBAAAAA==.',
Fi='Finalycalm:BAAANQAECgUIBAAAAA==.Finimus:BAAANQAECgIIAgAAAA==.Finlok:BAAANQABCgMIAgAAAA==.Firêfly:BAAANQAECgUIBQAAAA==.',
Fl='Flingpooh:BAAANQAECgYIEQAAAA==.Flloran:BAABNQAECn8hAAIWAAcKGgckSgD5AAAWAAcKGgckSgD5AAAAAA==.',
Fo='Foxylox:BAAANQADCgYIBgAAAA==.',
Fr='Fraggle:BAECNQAFFH8WAAITAAcKSRPYDACSAQATAAcKSRPYDACSAQA1AAQKf0MAAxMACgpZHs0fAPACABMACgpZHs0fAPACABIABwqxE/K6AFwBAAAA.Frogchi:BAAANQAECgYIEwAAAA==.Frostbité:BAAANQAECgUICQAAAA==.Fruit:BAAANQAECgYIDgAAAA==.',
Fu='Fubarut:BAAANQADCggIDAAAAA==.Fumikiko:BAAANQADCgYICgABNQAECgcICAACAAAAAA==.Funnybluffy:BAAANQAECgEIAQAAAA==.Fuzzbâll:BAAANQABCgYICQAAAA==.',
['Fí']='Físh:BAAANQADCgcICAABNQAECgcICAACAAAAAA==.',
Ga='Gali:BAAANQAECgEIAQAAAA==.Gallows:BAAANQAECgUIBQAAAA==.Gargybyn:BAAANQADCgUIBwAAAA==.',
Gi='Girliepop:BAABNQAECn8aAAMTAAkKNxJYWgCuAQATAAkKNxJYWgCuAQASAAQKxAIfkgFCAAAAAA==.',
Gl='Glaistiguain:BAABNQAECn81AAQXAAoKbCCsAwC2AgAXAAoKSiCsAwC2AgAYAAUKRSFQBwBeAQAQAAEKAACHOAFFAAABNQAECgoKQgAFAAsgAA==.Glifin:BAABNQAECn8WAAIBAAYKfQl22wBKAQABAAYKfQl22wBKAQAAAA==.Glizzeldra:BAAANQADCgUIBQAAAA==.Gloomstalkin:BAAANQAECgQICQABNQAECgoKQAARAPsUAA==.Glynna:BAAANQADCgUIBQAAAA==.',
Go='Gooning:BAABNQAECn8fAAMMAAoKPyPPAwAvAwAMAAoKPyPPAwAvAwASAAEKlA0wlwE9AAABNQAFFAYIDAARAE4WAA==.',
Gr='Gr:BAABNQAECn83AAIKAAoKDgpQFACPAQAKAAoKDgpQFACPAQAAAA==.Gryffs:BAABNQAECn8zAAMZAAoKaB8kCABnAgAZAAoKaB8kCABnAgANAAgKlg6urACtAQAAAA==.Gràvity:BAAANQAECgQIAwAAAA==.',
Gu='Guanino:BAAANQADCggIDQAAAA==.Gutts:BAAANQAECgMIAwABNQAECgoKNgAJACUeAA==.',
Gw='Gworg:BAAANQADCgEIAQAAAA==.',
['Gì']='Gìzmo:BAAANQAECgQIBQAAAA==.',
Ha='Halartion:BAABNQAECn8WAAINAAkKWRkragBSAgANAAkKWRkragBSAgAAAA==.Happirogue:BAAANQAECgYIBgABNQAFFAcIHAAaAHgcAA==.Haruun:BAAANQAECgQIDQAAAA==.',
He='Helridden:BAABNQAECn8nAAINAAkKsQsUaQDGAQANAAkKsQsUaQDGAQAAAA==.Hesmydaddy:BAABNQAECn8+AAIOAAoKpAaTbwCNAQAOAAoKpAaTbwCNAQAAAA==.',
Ho='Hoztok:BAAANQAECgQIBAAAAA==.',
Ic='Icemann:BAAANQABCggICAAAAA==.',
Im='Imherdaddy:BAABNQAECn9AAAIRAAoK+xSOKAC6AQARAAoK+xSOKAC6AQAAAA==.',
It='Itakemeds:BAAANQADCgYJDAABNQAECgQICAACAAAAAA==.',
Ja='Jaderean:BAAANQAECgMIAwAAAA==.Jake:BAAANQAECgMIAwABNQAECgoKKgAbAMQYAA==.Jarrack:BAABNQAECn9FAAMHAAoKDBWZUgAaAgAHAAoKmhOZUgAaAgAcAAQKrBaaIQDcAAAAAA==.Jaye:BAAANQABCgUICQAAAA==.',
Je='Jessicae:BAABNQAECn8pAAMOAAoKqBaXYQD8AQAOAAoKqBaXYQD8AQAdAAEKfg2oKgAvAAAAAA==.Jeuno:BAAANQADCggIDgABNQAECgcICAACAAAAAA==.',
Ji='Jivederpy:BAABNQAECn8tAAINAAkK/h5QTACkAgANAAkK/h5QTACkAgAAAA==.',
Ju='Juicybooty:BAAANQADCgYIDAAAAA==.Junazeena:BAABNQAECn8jAAMUAAkKRQYodgApAQAUAAkKRQYodgApAQADAAYKdAO6zgDKAAAAAA==.',
Ka='Kahlisto:BAAANQAECggICAAAAA==.Kaji:BAAANQAECgMIAwABNQAECgYICgACAAAAAA==.Kalistus:BAAANQADCgEIBQAAAA==.Katrina:BAAANQAECggIDwAAAA==.Kayfabe:BAABNQAECn8jAAIHAAoK9ATwDgF0AQAHAAoK9ATwDgF0AQAAAA==.',
Ke='Keirasti:BAAANQAECgYICgAAAA==.Keishilda:BAAANQAECgQIBAAAAA==.Keladria:BAAANQAECgUICQAAAA==.Kelirra:BAAANQAECgQIBAAAAA==.Kenel:BAABNQAECn8/AAIWAAoKnhAGKQC3AQAWAAoKnhAGKQC3AQAAAA==.Kerea:BAABNQAECn9IAAIeAAoKeAXkOQAuAQAeAAoKeAXkOQAuAQAAAA==.Kermitt:BAAANQADCggICwAAAA==.Keyarga:BAAANQADCgcIEAABNQAECgkJFwAfAMoSAA==.',
Kh='Khazadoom:BAAANQAECgYICgAAAA==.Khazargon:BAABNQAECn8hAAISAAoKBxyZVAAwAgASAAoKBxyZVAAwAgAAAA==.',
Ki='Kicken:BAABNQAECn9AAAQQAAoKYhHKfwBhAQAQAAgKXQ7KfwBhAQAYAAIKaRd+HACDAAAXAAEKdxTCKABGAAAAAA==.Kiitsuna:BAAANQADCgYIBgAAAA==.Kittyflerp:BAAANQADCgEJAQAAAA==.Kittyperry:BAACNQAFFH8HAAIWAAYKvRNgCQCSAQAWAAYKvRNgCQCSAQA1AAQKfyUABQQACgrGIVQGAKMCABYACQrJIcYOAL4CAAQACQoJHVQGAKMCACAACQppFXcZAN4BAB4AAgpjCI9lAG8AAAAA.Kizmo:BAAANQAECgcICAAAAA==.',
Ko='Korthelan:BAABNQAECn8/AAIhAAoK2hNoJQAaAgAhAAoK2hNoJQAaAgAAAA==.Kothara:BAABNQAECn9CAAIBAAoKtBIYXQAOAgABAAoKtBIYXQAOAgAAAA==.',
Kr='Krimzin:BAACNQAFFH8PAAIBAAgK+RfSCwCSAQABAAgK+RfSCwCSAQA1AAQKf0MAAgEACgofJsYCAH8DAAEACgofJsYCAH8DAAAA.Krystine:BAAANQAECgYIEwAAAA==.',
Ks='Kserasera:BAABNQAECn9EAAIWAAoK7BXRGwAoAgAWAAoK7BXRGwAoAgAAAA==.',
Ku='Kuball:BAABNQAECn82AAIJAAoKJR6bDwCCAgAJAAoKJR6bDwCCAgAAAA==.Kuchiki:BAAANQADCgEIAQAAAA==.Kukuruku:BAAANQAECgUIBQAAAA==.Kumari:BAABNQAECn8qAAMDAAoKSQHw0gDBAAADAAoKSQHw0gDBAAAUAAEKkwEpEgEeAAAAAA==.Kungfü:BAAANQADCggIDQAAAA==.Kurailatha:BAAANQADCgEIAgAAAA==.',
['Kî']='Kîllara:BAAANQADCgUIBQAAAA==.',
Le='Lebronjames:BAABNQAECn8iAAIFAAoKBx8WJQCrAgAFAAoKBx8WJQCrAgAAAA==.Letheos:BAABNQAECn9MAAIRAAoKWiQfCgBkAwARAAoKWiQfCgBkAwAAAA==.Levanas:BAAANQADCgEIAgAAAA==.',
Li='Librarte:BAABNQAECn8dAAISAAoKsgfyzACBAQASAAoKsgfyzACBAQAAAA==.Limmewinks:BAAANQADCgUIBQAAAA==.Litty:BAABNQAECn8aAAIHAAcKuxb3rABKAQAHAAcKuxb3rABKAQAAAA==.',
Lo='Loalu:BAAANQAECgEIAQAAAA==.Locktärd:BAAANQAECgQIBAABNQAFFAYIDAARAE4WAA==.Lox:BAABNQAECn9HAAIYAAoKsxCYBQCaAQAYAAoKsxCYBQCaAQAAAA==.',
Lu='Lunatick:BAAANQAECgIIAQABNQAECggIBAACAAAAAA==.',
Ly='Lydirn:BAAANQAECgMIBAAAAA==.',
['Lí']='Lítterbox:BAAANQAECgIIAgAAAA==.',
Ma='Magedzen:BAAANQADCgEIAQAAAA==.Magicguy:BAABNQAECn8qAAIHAAoKZhaylgBTAgAHAAoKZhaylgBTAgAAAA==.Mahariel:BAABNQAECn8xAAIBAAoKRgvobQDmAQABAAoKRgvobQDmAQAAAA==.Mahdy:BAABNQAECn9KAAISAAoKzxq4SQBNAgASAAoKzxq4SQBNAgAAAA==.Mahoe:BAAANQAECgEIAQAAAA==.Malva:BAABNQAECn8yAAIDAAoKxhcEJgCXAgADAAoKxhcEJgCXAgAAAA==.Manrypurp:BAABNQAECn8bAAIhAAoKwQ88GwDRAQAhAAoKwQ88GwDRAQAAAA==.Marcie:BAABNQAECn9BAAIWAAoKaQs3LwCMAQAWAAoKaQs3LwCMAQAAAA==.Martinriggz:BAABNQAECn8dAAIHAAkKCAFRPwFSAAAHAAkKCAFRPwFSAAAAAA==.',
Mc='Mchammer:BAAANQADCgIIAgAAAA==.',
Me='Meatyloaf:BAAANQAECgQIBwAAAA==.Medsedation:BAABNQAECn9GAAIOAAoKixNzRgAeAgAOAAoKixNzRgAeAgAAAA==.Melkedrik:BAAANQAECgQIBwAAAA==.Melleren:BAAANQAECggICAAAAA==.Meridiane:BAAANQADCgEIAQAAAA==.Mesomorph:BAAANQADCggIDQAAAA==.',
Mi='Mirei:BAABNQAECn9BAAIOAAoKcA0FXADPAQAOAAoKcA0FXADPAQAAAA==.Mitsurugi:BAAANQAECgEIAQABNQAECgoKPgANAPEQAA==.',
Mo='Moolander:BAAANQADCgUIBQAAAA==.Moovidlin:BAABNQAECn8cAAINAAkKDAfdpwAsAQANAAkKDAfdpwAsAQAAAA==.',
Mu='Mushhead:BAAANQAECgYJDwAAAA==.Mustepin:BAAANQADCgUIBQABNQAECgoKKgAbAMQYAA==.',
My='Mythantherox:BAAANQAECgIIAgABNQAFFAIIBwAiAGcdAA==.',
Na='Nachtaugen:BAAANQADCgcICQAAAA==.Nanlaria:BAAANQADCgEIAQAAAA==.',
Ne='Neon:BAAANQAECgMIAwAAAA==.Nethershade:BAABNQAECn8wAAIKAAkKfxyTCQBHAgAKAAkKfxyTCQBHAgAAAA==.Netherstörm:BAAANQAECggIDQAAAA==.',
Ni='Niclea:BAAANQADCgUIBQAAAA==.Nightelm:BAAANQAECgcICAAAAA==.',
No='Noborû:BAAANQAECgYIDgABNQAECgoKIwAFAKUaAA==.Noslien:BAAANQAECgEIAQAAAA==.Nostradamuz:BAABNQAECn86AAIMAAoKXxqvEwDyAQAMAAoKXxqvEwDyAQAAAA==.',
Ny='Nymneria:BAAANQAECgQIBwAAAA==.Nyxiera:BAABNQAECn9UAAIZAAoKFxhhDQBcAgAZAAoKFxhhDQBcAgABNQAECgoKVQAZAC4aAA==.Nyxstonia:BAABNQAECn9VAAQZAAoKLhr4BwDVAgAZAAoKLhr4BwDVAgAbAAYKKwxHFgA3AQANAAQKKAKaLAEzAAAAAA==.',
['Nä']='Nämi:BAAANQAECgYIDAAAAA==.',
Ol='Olierra:BAAANQADCgUIBQAAAA==.',
Om='Omnissiah:BAAANQABCgYIBgAAAA==.',
Or='Oreshin:BAAANQAECgUICAAAAA==.Orihimei:BAAANQADCgEIAgAAAA==.Ornac:BAAANQADCgMIAwAAAA==.Orphantrope:BAAANQABCgEIAQAAAA==.',
Ot='Otto:BAABNQAECn89AAISAAkKixNiiwC1AQASAAkKixNiiwC1AQAAAA==.Ottomagus:BAAANQADCgcIDAAAAA==.',
Pa='Palliate:BAAANQADCgYIBgABNQADCgUIBQACAAAAAA==.Pampoovy:BAEANQADCgYJBgABNQAECgoKRQAfAJYaAA==.',
Pb='Pbjam:BAAANQAECggICAAAAA==.',
Pe='Persephoneia:BAABNQAECn82AAIPAAoKRwpZHwCSAQAPAAoKRwpZHwCSAQAAAA==.',
Ph='Phobos:BAAANQABCgIIAgABNQAECgUIBQACAAAAAA==.',
Pi='Piperclip:BAAANQADCgYIBgAAAA==.Pitnick:BAAANQADCgIIAQAAAA==.',
Po='Poraichu:BAAANQADCggICQAAAA==.',
Pr='Preacherman:BAAANQAECgQIBgAAAA==.Priority:BAAANQADCgQIBAAAAA==.',
Pu='Punjistake:BAAANQAECggICAAAAA==.Purplevane:BAAANQAECgMIAwAAAA==.',
Qu='Quna:BAAANQADCgIIAgAAAA==.',
Ra='Rabies:BAAANQADCgcIEQAAAA==.Rageoverrun:BAAANQAECgIIAgAAAA==.Ragequit:BAAANQAECgMIAwABNQAECgoKLQAMAOkbAA==.Ranson:BAAANQAECggICAAAAA==.Ravenloare:BAAANQAECgEIAQAAAA==.',
Re='Reaverheim:BAAANQAECgcICQAAAA==.Remuz:BAAANQADCgYIBgAAAA==.Rey:BAAANQADCggIEQABNQAECgYICgACAAAAAA==.',
Ri='Rilz:BAABNQAECn8/AAMFAAoKaB9DDwCKAgAFAAoKaB9DDwCKAgAGAAIKjQ78lQBpAAAAAA==.',
Ro='Rockasham:BAABNQAECn8oAAIUAAkKtgs0eAC5AQAUAAkKtgs0eAC5AQAAAA==.Rodgerwabbet:BAAANQADCgMIAwAAAA==.Rottn:BAABNQAECn8tAAIMAAoK6Rs2EQAXAgAMAAoK6Rs2EQAXAgAAAA==.',
Sa='Safmen:BAABNQAECn8VAAIZAAkKhgc/IwAvAQAZAAkKhgc/IwAvAQAAAA==.Saintdivine:BAAANQADCgIIAgABNQAECgQIBAACAAAAAA==.Sanikoa:BAAANQAECgUIBQAAAA==.Saraid:BAABNQAECn89AAQeAAoKkhKgJwC0AQAeAAoKkhKgJwC0AQAgAAcK9AmSQAC8AAAWAAUKSg3QjQCfAAAAAA==.Saravase:BAAANQADCggIDQAAAA==.',
Se='Sev:BAAANQAECgIIAgAAAA==.Señorcleave:BAAANQADCgQICgAAAA==.',
Sh='Shadk:BAEBNQAECn89AAQRAAoKnBVwMgCBAQARAAkKBRdwMgCBAQAFAAIKTgdv6QArAAAGAAIKAABfzQAAAAAAAA==.Shadowstorm:BAABNQAECn9BAAIjAAoKDhZwEQBSAgAjAAoKDhZwEQBSAgAAAA==.Shelal:BAAANQADCggICAAAAA==.Shiki:BAAANQAECgUIBQABNQAECgoKQQAOAHANAA==.Shinoto:BAAANQADCgYIDQABNQAECgkJJgANAG0YAA==.',
Si='Sieghart:BAAANQADCgEIAQAAAA==.Silvein:BAACNQAFFH8MAAITAAcKxhAgDgCAAQATAAcKxhAgDgCAAQA1AAQKfzYAAxMACgqWIVUQAEoDABMACQqKI1UQAEoDAAwACQp4Dm4kAEsBAAAA.Silverpower:BAAANQAECgUIBQAAAA==.',
Sk='Skyë:BAAANQADCgcIBwABNQAECgcICAACAAAAAA==.',
Sn='Snowynn:BAAANQAECgEIAQAAAA==.',
So='Sorrybro:BAAANQAECgQICQAAAA==.',
Sp='Spycatcher:BAAANQADCgQIBgAAAA==.Spyro:BAABNQAECn8iAAQiAAoKOhK5HgBoAQAiAAcKmgm5HgBoAQAkAAgKlQytKwBNAQAlAAQKWQyHFgDKAAAAAA==.Spyroo:BAABNQAECn8gAAIlAAkKKA5mCgDKAQAlAAkKKA5mCgDKAQAAAA==.',
Sr='Sron:BAABNQAECn82AAIBAAoK5BVwXgBbAgABAAoK5BVwXgBbAgAAAA==.',
St='Stankboy:BAAANQABCgQIBwAAAA==.',
Su='Sumwhiteguy:BAAANQABCgYICAAAAA==.Suzuka:BAAANQADCgEIAgABNQAECgoKQQAOAHANAA==.',
Sw='Swooze:BAABNQAECn8ZAAMHAAgKfxaewwD9AQAHAAgK/hSewwD9AQAcAAEKgBJDRAA7AAAAAA==.',
Sy='Syndar:BAAANQADCgQIBAABNQAECgoKJQAUACseAA==.',
Sz='Szuzette:BAAANQAECgMIBQABNQAECgQICQACAAAAAA==.',
Ta='Talwaz:BAAANQAECgMIAwAAAA==.Tankcontrols:BAAANQAECgYIEgAAAA==.Tarlyn:BAABNQAECn8xAAITAAoKBR8xFQAPAwATAAoKBR8xFQAPAwAAAA==.',
Te='Temuadêrna:BAAANQADCgYIBgAAAA==.',
Th='Thaenet:BAAANQADCgUIBwAAAA==.Thevelo:BAAANQAECgUIBQABNQAECgkJFwAfAMoSAA==.Thunderkatze:BAABNQAECn8aAAIjAAkKCQlJGADjAQAjAAkKCQlJGADjAQAAAA==.Thánátós:BAAANQAECgQIBgAAAA==.',
Ti='Tinyfubar:BAAANQADCgEIAgAAAA==.Tissaia:BAAANQADCgIIAgAAAA==.',
To='Tootsunami:BAAANQADCgEIAgAAAA==.Topu:BAABNQAECn8ZAAQDAAgKHx3CSgA4AgADAAgKHx3CSgA4AgAjAAIKrREtLwB4AAAUAAEKGAzJNAE0AAAAAA==.',
Tr='Tradarynn:BAAANQAECgQIBAAAAA==.Trek:BAAANQAECggIAQAAAA==.',
Tw='Twinkles:BAAANQADCgMIAwAAAA==.',
Ty='Tyviae:BAAANQAECgcIDwAAAA==.',
Un='Unacceptable:BAAANQAECgUIDgAAAA==.',
Ur='Urais:BAAANQAECgMIAwABNQAECgoKRQALAMUjAA==.',
Us='Usdaprime:BAACNQAFFH8FAAIWAAIKPAduHgBrAAAWAAIKPAduHgBrAAA1AAQKfy4AAhYACgoYEEMnAMMBABYACgoYEEMnAMMBAAAA.',
Va='Valhalia:BAABNQAECn8vAAMYAAoK5CC3AQCXAgAYAAkK5CC3AQCXAgAQAAMKxRMU5QCHAAAAAA==.Vanira:BAAANQADCgYIBgAAAA==.Vanrien:BAAANQADCggICAAAAA==.Varaelitha:BAAANQAECgQIBAAAAA==.',
Ve='Velo:BAAANQADCggICAABNQAECgkJFwAfAMoSAA==.Vengful:BAABNQAECn8XAAMaAAcKFRoERQCeAQAaAAYKMxYERQCeAQAmAAIK1RzCIwCiAAAAAA==.Vexy:BAAANQADCgMJBQAAAA==.',
Vh='Vhalúryn:BAAANQAECgUICQAAAA==.',
Vi='Vicerion:BAAANQADCggIDAAAAA==.Vira:BAAANQADCgIIAgAAAA==.',
Vl='Vlue:BAAANQADCgQIBAAAAA==.',
Vo='Vorumbrae:BAAANQAECgUIBwAAAA==.',
Wa='Waaghh:BAAANQAECgQIBAABNQAECgkJIAAJAEkHAA==.Wali:BAABNQAECn8vAAIQAAoKmRKbTQDrAQAQAAoKmRKbTQDrAQAAAA==.',
Wh='Whatupbruh:BAAANQAECgQIBAAAAA==.',
Wi='Wildefaux:BAAANQADCggICAAAAA==.',
Wo='Wooties:BAABNQAECn8xAAIKAAoKKhO8DQDuAQAKAAoKKhO8DQDuAQABNQAECgoKOgADAIMcAA==.',
Wy='Wyleriya:BAABNQAECn8xAAIYAAkKsQ1xCABGAQAYAAkKsQ1xCABGAQAAAA==.',
Xa='Xaluhn:BAAANQADCgQIBAAAAA==.',
Xc='Xcella:BAAANQAECgEIAQAAAA==.',
Xe='Xenophon:BAAANQADCgcIBwAAAA==.',
Xu='Xurael:BAAANQAECgUIEAAAAA==.',
Xy='Xyn:BAAANQADCgcIBwABNQAECgYICgACAAAAAA==.',
Ye='Yelhsa:BAAANQAECgYIDAAAAA==.Yelizaveta:BAABNQAECn8jAAIBAAcKbwRD3QD3AAABAAcKbwRD3QD3AAAAAA==.',
Yl='Ylfcwen:BAAANQADCgYIBgAAAA==.',
Yu='Yukiri:BAAANQAECgQIDgAAAA==.Yumei:BAAANQAECgcIBgABNQAECggIGQADAB8dAA==.',
Za='Zalarah:BAAANQAECgYICgAAAA==.Zarathusa:BAAANQADCgQIBAAAAA==.Zardan:BAABNQAECn8VAAIYAAgKGQ8PCgAmAQAYAAgKGQ8PCgAmAQAAAA==.',
Ze='Zeppik:BAAANQADCgYIDAAAAA==.',
Zu='Zuggerker:BAABNQAECn9IAAINAAoKNhfyPgBHAgANAAoKNhfyPgBHAgAAAA==.',
['Äo']='Äoibheil:BAAANQADCgEIAQAAAA==.',
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
