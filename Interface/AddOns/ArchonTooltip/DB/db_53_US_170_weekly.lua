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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Priest-Holy','Priest-Shadow','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Destruction','Rogue-Assassination','Paladin-Holy','Warrior-Arms','Mage-Arcane','Unknown-Unknown','Druid-Balance','Hunter-BeastMastery','Warrior-Fury','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Devourer','DeathKnight-Frost','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Evoker-Devastation','DemonHunter-Havoc','Druid-Guardian','Druid-Feral','Warrior-Protection','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Rogue-Subtlety',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Absol:BAABNQAECoElAAMBAAkKVyNxAACpAwABAAkKQCNxAACpAwACAAgKeR+4LQC2AgAAAA==.',
Ac='Achilles:BAABNQAECoEiAAMDAAkKJBJgfQD/AQADAAkKXxBgfQD/AQAEAAMKAhN4RQCxAAAAAA==.',
Ae='Aeon:BAAANQAECgEIAQAAAA==.Aerís:BAAANQADCgIIAgAAAA==.',
Ah='Ahsokatano:BAABNQAECoEcAAMFAAcKERpTRQAhAgAFAAcKERpTRQAhAgAGAAEK1w0THQEuAAAAAA==.',
Ai='Ailing:BAAANQADCgYIDAAAAA==.Aimspet:BAAANQAECgQICAAAAA==.',
Ak='Akasha:BAAANQABCgMIBwAAAA==.Akos:BAAANQADCggJEAABNQAECgkJOwAHAMIYAA==.',
Al='Alzaeryan:BAAANQAECgUIDQAAAA==.',
Am='Am:BAAANQADCgYIBgAAAA==.Amonet:BAAANQADCgcIFwAAAA==.',
An='Anamis:BAABNQAECoEXAAMIAAgK+hVLRwAqAgAIAAgK+hVLRwAqAgAJAAEKHwUScwApAAAAAA==.Angras:BAABNQAECoEYAAMKAAYK4wpwfADhAAAKAAUKpAtwfADhAAALAAUKAAZGjgDIAAAAAA==.',
Ap='Aphalock:BAABNQAECoEZAAIMAAcKPgWlKAAoAQAMAAcKPgWlKAAoAQAAAA==.',
Ar='Ariûs:BAAANQAECgQICQAAAA==.Arlin:BAAANQADCgcIDgAAAA==.Arlorian:BAABNQAECoEkAAINAAgKxAvLMgDXAQANAAgKxAvLMgDXAQAAAA==.Arrenn:BAAANQAECgMJBQAAAA==.Arrowsmites:BAAANQAECgcIEQAAAA==.',
As='Askelad:BAAANQAECgUIDQAAAA==.',
Au='Aubani:BAABNQAECoEbAAMOAAgKRA9PXQDdAQAOAAgKRA9PXQDdAQADAAUKkwwQ8wD+AAAAAA==.',
Ay='Ayperos:BAABNQAECoEgAAIPAAgKpQsLlADCAQAPAAgKpQsLlADCAQAAAA==.',
Ba='Bakedpally:BAAANQAECgUIDAAAAA==.Bakedwarrior:BAAANQADCgIIAgAAAA==.Bandomar:BAAANQAECgIIAwAAAA==.Baragnis:BAAANQAECgUIBQAAAA==.',
Be='Beavur:BAAANQAECgUICgAAAA==.Beck:BAABNQAECoEaAAIDAAcK/yNENgDTAgADAAcK/yNENgDTAgAAAA==.Bereth:BAAANQADCgcIFwAAAA==.Berreydingle:BAAANQADCggJFwAAAA==.',
Bi='Bigboii:BAAANQAECgEIAQAAAA==.Bigkitty:BAAANQAECgIIAgABNQAECggIGAAQAK8SAA==.Bikinibrenda:BAAANQAECgMIBQAAAA==.',
Bl='Blackhuuf:BAAANQADCgUIBQAAAA==.Blitzedbust:BAAANQADCggIFQAAAA==.Bloodmender:BAAANQADCgYIBwABNQAECgkJHwAQAC0iAA==.Bluesummer:BAAANQADCgcIFAABNQAECgcIFgAKADMeAA==.',
Bo='Bobeh:BAAANQAECgEIAgABNQADCgEIAQARAAAAAA==.Bolts:BAAANQABCgEIAQAAAA==.Boomskittles:BAAANQABCgMIAwAAAA==.Borat:BAABNQAECoEaAAIQAAgKfSEXOgAFAwAQAAgKfSEXOgAFAwABNQADCgYIDwARAAAAAA==.Borsam:BAAANQABCgcICQAAAA==.',
Br='Brendameeks:BAAANQADCgQIBAAAAA==.Broadzinatl:BAAANQAECgIIAgAAAA==.Brom:BAAANQAECgQIBgAAAA==.Brutesse:BAAANQAECgQICAAAAA==.Bròly:BAAANQADCgMIAwAAAA==.',
Bu='Buttercups:BAAANQADCgMIAwAAAA==.',
['Bè']='Bètflèch:BAAANQAECgEIAQAAAA==.',
['Bø']='Bøss:BAAANQADCgYICQAAAA==.',
Ca='Cad:BAAANQADCgYIEAAAAA==.Calytrix:BAEBNQAECoEfAAISAAgK+BYnMwAlAgASAAgK+BYnMwAlAgAAAA==.Captnhammer:BAAANQADCgEIAQAAAA==.Carnelian:BAAANQADCgcIFAAAAA==.Castration:BAAANQADCgYICQAAAA==.',
Ce='Ceylan:BAAANQAECgcIEAAAAA==.',
Ch='Charlz:BAAANQADCggICAAAAA==.Charsifood:BAAANQAECgcIDgAAAA==.Chat:BAAANQAECggIDwAAAA==.Cheatpriest:BAABNQAECoElAAIIAAgKMhLkVgDwAQAIAAgKMhLkVgDwAQAAAA==.Chepis:BAAANQADCgcJEAAAAA==.Chesthyr:BAAANQADCgcIDgAAAA==.Chestoe:BAAANQAECgQICAAAAA==.Chitchatted:BAAANQADCgIIAgAAAA==.',
Ci='Cindrethresh:BAAANQADCgMIAwAAAA==.',
Co='Cognition:BAABNQAECoEjAAITAAgK5yI3GAAhAwATAAgK5yI3GAAhAwAAAA==.Coldvengance:BAABNQAECoEWAAIUAAgKWgeiEQBjAQAUAAgKWgeiEQBjAQAAAA==.',
Cr='Cranknstein:BAAANQADCggJCAABNQADCggIEQARAAAAAA==.Crazh:BAAANQAECgIIAwAAAA==.Crazycalla:BAAANQAECgMIAwAAAA==.Croven:BAAANQADCgUIBQAAAA==.',
Cu='Cuensour:BAAANQADCgcJDQAAAA==.Cutemenace:BAAANQADCgIIAgABNQAFFAMIAwARAAAAAA==.',
Cy='Cymindel:BAABNQAECoEiAAIKAAgKNxUDNgATAgAKAAgKNxUDNgATAgAAAA==.Cyphr:BAAANQABCgYIBwAAAA==.',
Da='Dakotà:BAAANQAECgUIDQAAAA==.Darc:BAAANQAECgQICAAAAA==.Daredayo:BAAANQADCgIIAgAAAA==.Darkangelz:BAAANQADCgYIBgAAAA==.Darklorising:BAAANQAECgIIAgAAAA==.Darktroll:BAAANQADCgYICAAAAA==.',
De='Dejno:BAABNQAECoEUAAMUAAcKyiD9BwBDAgAUAAYKpSL9BwBDAgAPAAIK/BT2CwGMAAAAAA==.Deleted:BAAANQADCgUIBQABNQAECgkJHwAQAC0iAA==.Dethra:BAAANQAECgQIDQAAAA==.Dezign:BAACNQAFFIETAAMVAAYKPCHaAgDVAAAQAAUKRh92DgDgAQAVAAIKUSXaAgDVAAA1AAQKgSkAAxUACQrmJYcAALsDABUACQpYJYcAALsDABAACQoSI8gwAB8DAAAA.',
Do='Dolgorukov:BAABNQAECoEaAAITAAgKGgyqfQDjAQATAAgKGgyqfQDjAQAAAA==.Dologony:BAAANQAECgUICQAAAA==.',
Dr='Draccosa:BAAANQADCgIIAgAAAA==.Dragonmage:BAAANQAECgUICwAAAA==.Drakhan:BAAANQADCgIJAgAAAA==.Drakma:BAAANQAECgMIBQAAAA==.Drastio:BAAANQADCgMIAwAAAA==.Drikken:BAABNQAECoEmAAMWAAgKwReQCQAeAgAWAAgKwReQCQAeAgAXAAcK/Q+6LQCxAQAAAA==.Drmaker:BAAANQAECgEIAgAAAA==.Druj:BAEANQADCgcIBwABNQAECggIHwASAPgWAA==.',
Du='Durasan:BAAANQADCgMIAwAAAA==.',
['Dö']='Dötdötdead:BAAANQAECgMIAwAAAA==.',
Ef='Effindin:BAAANQADCgYIBgAAAA==.Effinsick:BAAANQADCggIFwAAAA==.',
Ei='Eisheth:BAAANQADCggIFgAAAA==.',
El='Elerav:BAAANQAECgMIAwAAAA==.Ellysiaa:BAAANQADCggJHwAAAA==.',
Em='Emmakyn:BAAANQAECgcIDgAAAA==.',
En='Endjinns:BAAANQADCggICAAAAA==.Enyxea:BAAANQAECgMIBAAAAA==.',
Er='Erodin:BAAANQADCgYICwAAAA==.',
Es='Esman:BAAANQADCgMIAwAAAA==.',
Ey='Eyedontknow:BAAANQAECgUIDAAAAA==.',
Ez='Ezzka:BAABNQAECoEdAAMLAAgKFiEJFQD6AgALAAgK7iAJFQD6AgAKAAIKxhs/mwCCAAAAAA==.',
Fa='Faceless:BAAANQAECgYIBQAAAA==.Failroots:BAAANQAECgIIAgAAAA==.False:BAAANQAECgIIAgAAAA==.Farnsworth:BAAANQAECgUIBQAAAA==.Farzix:BAAANQAECgUIDAAAAA==.Fatherdrew:BAAANQAECgYIBgAAAA==.Façade:BAABNQAECoEdAAMYAAkKTBP9KgAPAgAYAAgKzxT9KgAPAgALAAcK8g6RYgBgAQAAAA==.',
Fe='Fefifabrizio:BAAANQAECgEIAQAAAA==.Felix:BAAANQAECgEIBAAAAA==.Felraena:BAAANQADCgIIAgAAAA==.',
Fi='Finnagas:BAAANQAECgEJAQAAAA==.Finnw:BAAANQABCgcJCgAAAA==.Firelite:BAAANQAECgUIBwAAAA==.',
Fl='Flairadin:BAABNQAECoEYAAIOAAgKbRXmRQAwAgAOAAgKbRXmRQAwAgAAAA==.Fleromars:BAAANQADCgYIBgAAAA==.Flexo:BAAANQAECgQIBQABNQAECgUIBQARAAAAAA==.',
Fo='Fookmii:BAAANQADCgUIBgAAAA==.',
Fr='Frogfist:BAAANQAECgMIAwAAAA==.Frowdawn:BAAANQAECgUIDwAAAA==.',
Ga='Garbanzo:BAAANQAECgUIBQAAAA==.Garythenpc:BAAANQADCgcIFwAAAA==.',
Ge='Genericeric:BAAANQAECgQIBAAAAA==.Getsumei:BAAANQAECgYIBgAAAA==.',
Gi='Gidgett:BAAANQADCgcIFAAAAA==.',
Gl='Glacialkitty:BAABNQAECoEaAAIHAAgKdAVENwAtAQAHAAgKdAVENwAtAQAAAA==.Glizzygoblin:BAAANQADCgQIBAAAAA==.',
Go='Gobibug:BAAANQADCgIJAgAAAA==.Googoobler:BAAANQAECgEIAQAAAA==.Goudalovin:BAAANQADCgQIBAABNQAECggIGAAQAK8SAA==.Goudanight:BAAANQADCgIIAgABNQAECggIGAAQAK8SAA==.Goudatime:BAAANQAECgUIDAABNQAECggIGAAQAK8SAA==.',
Gr='Greenknight:BAAANQADCggICQAAAA==.Greenmagus:BAAANQAECgEJAQAAAA==.Grenadon:BAAANQADCgcIFgAAAA==.Greyni:BAAANQABCgEIAQAAAA==.',
Ha='Hakibalboa:BAABNQAECoEjAAIZAAgKlA0/EwCPAQAZAAgKlA0/EwCPAQAAAA==.Hakitua:BAAANQADCgYIBgAAAA==.Harick:BAAANQADCgQIBAAAAA==.Hazard:BAABNQAECoEYAAIUAAgK9QpgDgClAQAUAAgK9QpgDgClAQAAAA==.',
He='Heis:BAAANQADCgcIDgAAAA==.Hellboii:BAAANQAECgcIDQAAAA==.Heyitsrat:BAAANQAECgUIDwAAAA==.',
Ho='Hollowtips:BAAANQADCgYICgAAAA==.Holo:BAABNQAECoEkAAMGAAkKeSPKGAAdAwAGAAgKliPKGAAdAwAFAAkKHw8RZgCrAQAAAA==.Housemom:BAAANQAECgQIBQAAAA==.',
Hu='Huntem:BAAANQADCgMIAgAAAA==.Huuginn:BAAANQADCggICgAAAA==.',
Ib='Ibbert:BAAANQADCgUICgAAAA==.',
Ic='Icculus:BAAANQAECgIIAwAAAA==.',
Im='Imaresmashy:BAAANQADCgIIAgABNQAECgMIBAARAAAAAA==.Iminyou:BAABNQAECoEZAAIGAAcKSBF4bACqAQAGAAcKSBF4bACqAQAAAA==.',
Io='Iolz:BAAANQABCgQIBgABNQAECggIIgAPAMwVAA==.',
Ja='Jaenei:BAAANQAECgMIBAAAAA==.Janet:BAAANQADCgYIBgABNQAECggIIwAIAC8lAA==.',
Je='Jeeb:BAABNQAECoEfAAIQAAcKmxBU0QC+AQAQAAcKmxBU0QC+AQAAAA==.',
Ji='Jinxta:BAABNQAECoEWAAIMAAgKzB0CBQDCAgAMAAgKzB0CBQDCAgAAAA==.',
Jo='Joansnow:BAAANQADCggICgAAAA==.Joeeo:BAABNQAECoEhAAMIAAgKDRsGNAB2AgAIAAgKDRsGNAB2AgAJAAcKiwe/NwBAAQAAAA==.',
Ju='July:BAAANQAECgMIBAAAAA==.Julytonidas:BAAANQAECgcIDwAAAA==.Jurac:BAAANQADCgUIBQAAAA==.',
Ka='Kaimargonar:BAAANQAECgUICAAAAA==.Kaitoi:BAAANQAECgUIDAAAAA==.Kamakizeg:BAAANQAECgUIDgAAAA==.Kamayla:BAAANQADCgYIBgAAAA==.Kateria:BAAANQADCgUIBQABNQAECggIHQALABYhAA==.Katimalice:BAAANQADCgQJDQAAAA==.',
Ke='Keathry:BAAANQADCgcICwAAAA==.Keyzeus:BAAANQAECgIIAwAAAA==.',
Kh='Khas:BAAANQADCgMIAwAAAA==.Khui:BAACNQAFFIEGAAIaAAMKBCXQBABLAQAaAAMKBCXQBABLAQA1AAQKgScAAxoACQqeI2kDAGgDABoACQqeI2kDAGgDABsABQrpHn8tAHkBAAAA.',
Ki='Killatu:BAAANQABCggIDQAAAA==.Killerdeath:BAAANQAECgEIAQAAAA==.',
Kn='Knìghtmàrè:BAACNQAFFIEHAAMKAAUKKwp8GQCeAAALAAMKpwQZEgCyAAAKAAMKSA98GQCeAAA1AAQKgScAAwsACQr3I6cPACUDAAsACQr3I6cPACUDAAoABwpxHYYsAEkCAAAA.',
Ko='Koltharaz:BAABNQAECoEkAAIcAAkKwhu9CADVAgAcAAkKwhu9CADVAgAAAA==.Korloff:BAAANQADCggIEwABNQAECgIIAwARAAAAAQ==.Kozan:BAAANQAECgIIAwAAAQ==.',
Kr='Krazsz:BAAANQADCgQIBAAAAA==.Krazylock:BAAANQAECgQICAAAAA==.',
Ku='Kumah:BAAANQABCgEIAQAAAA==.Kungfuupanda:BAAANQAECgYIEQAAAA==.',
Ky='Kylar:BAAANQAECgQIBAAAAA==.',
La='Lateralus:BAABNQAECoEeAAILAAgKfCJiJwB9AgALAAgKfCJiJwB9AgAAAA==.Latt:BAAANQAECgIIAgABNQAECggIHgALAHwiAA==.Lawluss:BAAANQAECgUIEgAAAA==.Layonface:BAAANQAECgQIBAAAAA==.',
Le='Legacyshot:BAAANQAECgMIBAAAAQ==.Lelwani:BAAANQADCgEIAQAAAA==.',
Li='Lickthecrit:BAAANQAECgMIAwAAAA==.Lightguard:BAAANQADCggIBwAAAA==.Lighthouse:BAABNQAECoEmAAMOAAgKGxdTPwBJAgAOAAgKGxdTPwBJAgADAAMKkgZZMwGMAAAAAA==.Lightload:BAAANQAECgQIBAAAAA==.Lileth:BAAANQAECgEIAQAAAA==.',
Lo='Lolhahabaha:BAAANQAECgMIBAAAAA==.Lonê:BAAANQAECgIIAgAAAA==.Loopie:BAAANQAECgEIAQAAAA==.Lorax:BAAANQAECgYICAAAAA==.',
Lu='Luckÿ:BAAANQAECgEJAQAAAA==.Luminah:BAAANQABCgIIAQAAAA==.',
Ly='Lypally:BAABNQAECoEfAAIDAAgKzQPd3AAoAQADAAgKzQPd3AAoAQAAAA==.',
['Lï']='Lïllïth:BAAANQAECgYIDwAAAA==.Lïly:BAAANQAECgIIAgABNQAECgMIBAARAAAAAA==.',
['Ló']='Lóla:BAABNQAECoEaAAIXAAcK3yCnFwCIAgAXAAcK3yCnFwCIAgAAAA==.',
Ma='Madeah:BAABNQAFFIEQAAINAAYK3xHzAgD/AQANAAYK3xHzAgD/AQAAAA==.Madforge:BAABNQAECoEgAAIFAAgKNxjKQwAnAgAFAAgKNxjKQwAnAgAAAA==.Magegrizz:BAAANQAECgYIDgAAAA==.Magnyson:BAAANQAECggICAAAAA==.Mahimahi:BAAANQADCgYICgAAAA==.Manahole:BAABNQAECoEhAAIQAAgKuhsDcQCGAgAQAAgKuhsDcQCGAgAAAA==.Mariacuras:BAAANQAECgYIEQAAAA==.Marijwana:BAAANQAECgMIBgAAAA==.Martis:BAABNQAECoEbAAIYAAcK1QjzSQBJAQAYAAcK1QjzSQBJAQAAAA==.Marynne:BAAANQAECgYIEQAAAA==.Mazuko:BAABNQAECoEVAAIdAAcKURcfMgDoAQAdAAcKURcfMgDoAQAAAA==.',
Me='Mecandry:BAABNQAECoEjAAITAAgKbhQFVwBEAgATAAgKbhQFVwBEAgAAAA==.Mecks:BAAANQADCgcIDQAAAA==.Meepe:BAAANQADCgcIDQAAAA==.Melivant:BAAANQAECgUIDQAAAA==.Meranda:BAABNQAECoEYAAIQAAgKrxLdqAAPAgAQAAgKrxLdqAAPAgAAAA==.Merriklade:BAAANQAECgcIEgAAAA==.Merrikoid:BAAANQAECgQICgAAAA==.Merrikwolf:BAAANQADCgYIBgAAAA==.',
Mi='Mico:BAAANQAECgEIBAAAAA==.',
Mo='Morbidstyle:BAAANQADCgcIDAABNQAECggIIgAGAFsUAA==.Morgoth:BAABNQAECoElAAICAAgKXhmdRwBeAgACAAgKXhmdRwBeAgAAAA==.Morthos:BAAANQADCgcICgAAAA==.Mosry:BAABNQAECoEgAAIKAAcKgR85KABjAgAKAAcKgR85KABjAgABNQABCgQIBgARAAAAAA==.Mourneblood:BAAANQADCgUIBQAAAA==.',
My='Myora:BAEANQADCgIIAgABNQAECggIHwASAPgWAA==.Mythundirus:BAAANQAECgUICwAAAA==.',
['Mà']='Màrli:BAAANQAECgcIEwAAAA==.',
['Mâ']='Mâgs:BAABNQAECoEaAAIEAAgKYwzzJwByAQAEAAgKYwzzJwByAQAAAA==.',
Na='Nakasid:BAABNQAECoEgAAMIAAkKsxD5RAAzAgAIAAkKsxD5RAAzAgAJAAUKCAcURwDZAAAAAA==.Nashoba:BAAANQADCgYJCwAAAA==.Natooka:BAAANQADCgUIBQAAAA==.',
Ne='Nein:BAAANQAECgMIBwAAAA==.Neins:BAAANQADCgYIEAABNQAECgMIBwARAAAAAA==.Nevaehstar:BAABNQAECoEqAAIQAAgKChBqrwACAgAQAAgKChBqrwACAgAAAA==.',
Ni='Nibuto:BAAANQAECgUIBQAAAA==.Nijun:BAEBNQAECoEbAAIIAAgKlAvcawCkAQAIAAgKlAvcawCkAQAAAA==.Nik:BAAANQAECgQIBAAAAA==.Nikolia:BAAANQAECgQIDwAAAA==.Ninetynine:BAAANQADCgQIBAAAAA==.Nini:BAAANQAECgUIDAAAAA==.Ninx:BAAANQADCgUICQAAAA==.',
No='Noivana:BAAANQABCgEIAQABNQAFFAQICAAdAIQWAA==.',
Ny='Nystel:BAAANQADCgEIAQAAAA==.',
Ol='Ollichi:BAAANQADCgIIAgAAAA==.',
Or='Ornn:BAAANQAECgYIBwABNQAECgkJJQABAFcjAA==.',
Os='Osoroshi:BAAANQADCgYJBgABNQAECggIIwATAG4UAA==.',
Ov='Overtime:BAAANQADCggIDAAAAA==.',
Pa='Padmê:BAAANQADCgMIAwAAAA==.Paladrak:BAAANQADCgIIAgAAAA==.Pandamared:BAAANQADCgEIAQAAAA==.Patronous:BAAANQADCgYIDAAAAA==.',
Ph='Phenol:BAAANQADCgEIAQAAAA==.',
Po='Polog:BAAANQAECgIIAgABNQAECgkJHwAQAC0iAA==.Porkchoplust:BAAANQADCgUIBQAAAA==.Porkchopw:BAAANQABCgQIBAAAAA==.Porkribs:BAABNQAECoEYAAIOAAcKahwbQABGAgAOAAcKahwbQABGAgAAAA==.',
Pu='Puca:BAAANQADCgcIFwAAAA==.Pumdmuc:BAAANQAECgUIDwABNQAECggIIAAFAPccAA==.Punchymcheal:BAAANQAECgIIAwABNQAECgkJKQAIAHccAA==.',
Qu='Quikglaives:BAAANQAECgEIAQAAAA==.Quille:BAABNQAECoEYAAITAAcKdCEhQwB9AgATAAcKdCEhQwB9AgAAAA==.',
Ra='Ragretts:BAAANQAECgEIAQAAAA==.Rahhem:BAAANQADCgYIBgAAAA==.Ranmo:BAAANQAECgcIDwAAAA==.Ratkol:BAAANQABCgIIAgAAAA==.Raysdknight:BAAANQADCgIJBwAAAA==.',
Re='Recbra:BAAANQABCgUIBQAAAA==.Redrek:BAAANQADCgYIGwAAAA==.Redshunter:BAAANQADCgUIBgAAAA==.Redwinter:BAABNQAECoEWAAIKAAcKMx72KABfAgAKAAcKMx72KABfAgAAAA==.Reikisong:BAAANQAECgEIAQAAAA==.Reiluune:BAAANQADCgQIAwABNQAECgcIGgAXAN8gAA==.Remmie:BAAANQADCgUIBwAAAA==.',
Rh='Rhagurion:BAABNQAECoEpAAIeAAkKTSaOAADwAwAeAAkKTSaOAADwAwAAAA==.',
Ri='Riqua:BAAANQAECgIIAwAAAA==.',
Ro='Rockmonsta:BAAANQADCgYJCgAAAA==.Rockys:BAAANQABCgQIBQAAAA==.Roxies:BAAANQAECgMIBgAAAA==.',
Rp='Rpg:BAABNQAECoEWAAIQAAgKOxnjfQBrAgAQAAgKOxnjfQBrAgAAAA==.',
Ru='Runes:BAAANQAECgEIAgAAAA==.',
Sa='Saeti:BAABNQAECoEoAAUfAAkKYyEZBAAzAwAfAAgKxiMZBAAzAwAHAAIKMxLwVwB1AAASAAIKYhJOjABvAAAeAAEKxB/xQgBZAAAAAA==.Sanbit:BAAANQADCggICgAAAA==.Santhaenis:BAAANQADCgIIAgAAAA==.Sapplesauce:BAAANQADCggICQAAAA==.',
Se='Seethrowwar:BAABNQAECoEiAAMPAAkKgR/8LQDyAgAPAAkKQR/8LQDyAgAgAAYKcxZhFwCIAQAAAA==.Senbit:BAAANQAECgUIDQAAAA==.Serenìty:BAAANQAECgUIDAAAAA==.Seresin:BAABNQAECoE7AAMHAAkKwhhJEQCqAgAHAAkKwhhJEQCqAgASAAUKNwj1dQDKAAAAAA==.',
Sh='Shadý:BAAANQAECgUIDwAAAA==.Shamanoodles:BAAANQADCggIFAABNQAECgkJHwAQAC0iAA==.Shortwarrior:BAAANQAECgQICgAAAA==.',
Si='Sianu:BAAANQADCggIDwABNQAECgYIEQARAAAAAA==.Sidraya:BAAANQAECgIIBAAAAA==.Silent:BAABNQAECoEiAAIPAAgKzBWGeQAJAgAPAAgKzBWGeQAJAgAAAA==.Silverserqet:BAAANQAECgUIDAAAAA==.',
Sm='Smileyriley:BAAANQADCgUIBQAAAA==.',
Sn='Sneakylinks:BAAANQADCgIIAgABNQAECggIFgAQADsZAA==.',
So='Sonbit:BAAANQADCggJDwAAAA==.Sooki:BAAANQAECgMIBQAAAA==.Sophie:BAAANQAECgQICgAAAA==.Soulber:BAAANQAECgMIBAAAAA==.',
Ss='Ssenbit:BAAANQADCgcIEwAAAA==.Ssonbit:BAAANQADCggICAAAAA==.',
St='Stefeana:BAAANQADCgYIBgAAAA==.Sternhoof:BAAANQABCgMIAwAAAA==.Stigma:BAAANQADCggIFQABNQAECgYIBgARAAAAAA==.Stylos:BAAANQAECgcIEAAAAA==.',
Su='Summersong:BAAANQADCgQIBAAAAA==.',
Sw='Swowtitbang:BAAANQAECgMIBAAAAA==.',
Sy='Sylven:BAAANQADCgYIBgABNQAECggIKQAGANEhAA==.',
Te='Tegbolt:BAABNQAECoEdAAMGAAgKIRScVQD2AQAGAAgKpxKcVQD2AQAhAAcKHhFMFwDGAQAAAA==.Tekko:BAABNQAECoEhAAIeAAgK0BqJDABgAgAeAAgK0BqJDABgAgAAAA==.Tempestrike:BAAANQAECggICwAAAA==.',
Th='Theholymatt:BAABNQAECoElAAIOAAgKpySfDgBGAwAOAAgKpySfDgBGAwAAAA==.Thendari:BAABNQAECoEqAAIMAAYK9QvsIwBIAQAMAAYK9QvsIwBIAQAAAA==.Theodus:BAABNQAECoEdAAIQAAcKlxOYxwDSAQAQAAcKlxOYxwDSAQAAAA==.Therayen:BAAANQADCgYJCwAAAA==.',
Ti='Tiferis:BAABNQAECoElAAIOAAkK7xwoHADuAgAOAAkK7xwoHADuAgAAAA==.Tigerclawss:BAAANQADCgcIEAAAAA==.Tislam:BAAANQAECgMIBAAAAA==.',
To='Tobiquer:BAABNQAECoEhAAIIAAgKPCLKEwAZAwAIAAgKPCLKEwAZAwAAAA==.Torolf:BAAANQADCggIEwAAAA==.',
Tr='Traydra:BAAANQADCgUIBwAAAA==.Trinbug:BAAANQADCgEIAQAAAA==.Troglodyte:BAABNQAECoErAAIGAAkKTiMeBwClAwAGAAkKTiMeBwClAwAAAA==.',
Ts='Tsonokwabain:BAAANQAECgQICgAAAA==.Tsunami:BAAANQADCgMIAwAAAA==.',
Tw='Twistdog:BAAANQABCgQIBgAAAA==.',
Ty='Tye:BAAANQAECgcIEQAAAA==.Tyranastrasz:BAABNQAECoEjAAQcAAgK6Qa9GwBzAQAcAAgK6Qa9GwBzAQAiAAIK8wIzRQBKAAAjAAEKTQC+JAANAAAAAA==.Tyye:BAAANQAECgYIEgAAAA==.',
['Tâ']='Tâjik:BAABNQAECoEXAAIkAAgKkwOOKgBUAQAkAAgKkwOOKgBUAQAAAA==.',
Ul='Ulquiorra:BAACNQAFFIEGAAIXAAMKiw64CgDpAAAXAAMKiw64CgDpAAA1AAQKgSUAAxcACQrIGxoUALACABcACAr8HRoUALACABYAAwrHCq4gAI0AAAAA.',
Ut='Uthers:BAAANQADCgYIAgAAAA==.',
Va='Vaethund:BAAANQAECgMIBAAAAA==.Valgavoth:BAAANQAECgcIEAAAAA==.Vanthion:BAAANQADCgIIAgAAAA==.',
Ve='Velara:BAAANQAECgQIBQAAAA==.Velinna:BAAANQADCgUIBwABNQAECgEIAQARAAAAAA==.Venekor:BAAANQADCgIIAgAAAA==.',
Vi='Viriex:BAAANQADCgIIAgAAAA==.Vitoria:BAAANQAECgIIAgAAAA==.',
Vo='Voidlighter:BAABNQAECoEpAAIIAAkKdxzYGwDrAgAIAAkKdxzYGwDrAgAAAA==.Volundr:BAABNQAECoEXAAIgAAgKpBYNDwANAgAgAAgKpBYNDwANAgAAAA==.Vonvaughan:BAAANQAECgIIAgABNQAECgIIAgARAAAAAA==.',
Vy='Vynel:BAAANQADCgMIAwABNQAECggIKQAGANEhAA==.Vynirion:BAAANQAECgEIAQAAAA==.',
Wa='Wardellmo:BAAANQADCgQIBAAAAA==.Wargtar:BAABNQAECoEZAAINAAcKORofKAAeAgANAAcKORofKAAeAgAAAA==.',
We='Weabe:BAAANQAECgIIAwAAAA==.',
Wh='Whiterrina:BAAANQADCgIJAgAAAA==.Whitespring:BAAANQAECgMIAwABNQAECgcIFgAKADMeAA==.',
Wo='Wolfgarou:BAAANQABCgIIAgAAAA==.',
Wy='Wyrdo:BAAANQADCgYIBgAAAA==.',
['Wù']='Wùsthof:BAABNQAECoEeAAITAAgK6QiZiADJAQATAAgK6QiZiADJAQAAAA==.',
Xa='Xandrios:BAAANQAECgEJAQAAAA==.',
Xi='Xiae:BAABNQAECoEYAAIGAAgKiBdNQgBBAgAGAAgKiBdNQgBBAgAAAA==.',
Ya='Yasuke:BAAANQADCgUJBQAAAA==.',
Ye='Yet:BAAANQADCgYIDwAAAA==.',
Yi='Yiffweaver:BAAANQAECgEIAQAAAA==.',
Yo='Yokochan:BAAANQABCgIIAgAAAA==.Yokoriazen:BAABNQAECoEjAAIDAAkKeBUCYABOAgADAAkKeBUCYABOAgAAAA==.',
Za='Zakaradin:BAAANQADCgYIBgABNQAECgIIAwARAAAAAA==.Zaraeliana:BAAANQAECgMIBAAAAA==.Zarastraza:BAABNQAECoEgAAMiAAcKtRKXHwC7AQAiAAcKtRKXHwC7AQAcAAQKiwzbJgDdAAAAAA==.',
Ze='Zephnor:BAAANQAECgYIDwAAAA==.',
Zh='Zhao:BAAANQADCgYIBgAAAA==.',
Zm='Zmona:BAAANQAECgQIBAAAAA==.',
Zo='Zorsche:BAAANQAECgEIAQAAAA==.',
Zu='Zulrok:BAABNQAECoEbAAIPAAgKnQ+liQDeAQAPAAgKnQ+liQDeAQAAAA==.',
['Áb']='Ábsurd:BAAANQAECgYICAABNQABCgIIAQARAAAAAA==.',
['Ðr']='Ðre:BAAANQAECgMIAwAAAA==.',
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
