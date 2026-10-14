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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Priest-Holy','Priest-Shadow','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Destruction','Rogue-Assassination','Paladin-Holy','Warrior-Arms','Mage-Arcane','Unknown-Unknown','Druid-Balance','Druid-Feral','Monk-Mistweaver','Hunter-BeastMastery','Warrior-Fury','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian','DeathKnight-Frost','Monk-Brewmaster','Monk-Windwalker','Evoker-Devastation','DemonHunter-Havoc','Warrior-Protection','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Rogue-Subtlety',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Absol:BAABNQAECn8oAAMBAAkKkiOgAACaAwABAAkKgSOgAACaAwACAAgKUB+YPACaAgAAAA==.',
Ac='Achilles:BAABNQAECn8mAAMDAAkKQRM2lgDyAQADAAkKGhA2lgDyAQAEAAMKmBVnSgC9AAAAAA==.',
Ad='Adenox:BAAANQAECgMIAwAAAA==.',
Ae='Aeon:BAAANQAECgIIAwAAAA==.Aerís:BAAANQADCgIIAgAAAA==.',
Ah='Ahsokatano:BAABNQAECn8fAAMFAAcKahv6SAA7AgAFAAcKahv6SAA7AgAGAAEKAAA4OgEuAAAAAA==.',
Ai='Ailing:BAAANQADCgYIDAAAAA==.Aimspet:BAAANQAECgQICwAAAA==.Airocket:BAAANQADCgMIAwAAAA==.',
Ak='Akasha:BAAANQABCgMIBwAAAA==.Akos:BAAANQAECgYIBgABNQAECgkJRAAHAPsYAA==.',
Al='Alzaeryan:BAAANQAECgYIEgAAAA==.',
Am='Am:BAAANQADCgYIBgAAAA==.Amonet:BAAANQADCgcIFwAAAA==.',
An='Anamis:BAABNQAECn8eAAMIAAgK/xZbUgApAgAIAAgK/xZbUgApAgAJAAEKHwUhgAAoAAAAAA==.Angras:BAABNQAECn8YAAMKAAYKogvzhwDbAAAKAAUKwwzzhwDbAAALAAUK0gZNmgDHAAAAAA==.',
Ap='Aphalock:BAABNQAECn8gAAIMAAcKtwSNKQAuAQAMAAcKtwSNKQAuAQAAAA==.',
Ar='Ariûs:BAAANQAECgUIDgAAAA==.Arlin:BAAANQADCgcIDgAAAA==.Arlorian:BAABNQAECn8sAAINAAgKDQtQPgDQAQANAAgKDQtQPgDQAQAAAA==.Arrenn:BAAANQAECgMIBgAAAA==.Arrowsmites:BAAANQAECgcIEgAAAA==.',
As='Askelad:BAAANQAECgUIEQAAAA==.',
Au='Aubani:BAABNQAECn8fAAMOAAgKRA9pbADPAQAOAAgKRA9pbADPAQADAAYKmg++5gBHAQAAAA==.',
Ax='Axelot:BAAANQADCgQIBAAAAA==.',
Ay='Ayperos:BAABNQAECn8oAAIPAAgK2wzuoADGAQAPAAgK2wzuoADGAQAAAA==.',
Ba='Bakedpally:BAAANQAECgYIEQAAAA==.Bakedwarrior:BAAANQADCgIIAgAAAA==.Bandomar:BAAANQAECgIIAwAAAA==.Baniemo:BAAANQABCggIEAAAAA==.Banigor:BAAANQAECgQIBAAAAA==.Baragnis:BAAANQAECgUIBQAAAA==.',
Be='Beavur:BAAANQAECgUIDgAAAA==.Beck:BAABNQAECn8cAAIDAAcKpSOmRwC6AgADAAcKpSOmRwC6AgAAAA==.Beggars:BAAANQAECgQIBAAAAA==.Bereth:BAAANQADCgcIFwAAAA==.Berreydingle:BAAANQADCggJFwAAAA==.',
Bi='Bigboii:BAAANQAECgEIAQAAAA==.Bigkitty:BAAANQAECgIIAgABNQAECggIHgAQAO0UAA==.Bikinibrenda:BAAANQAECgMIBgAAAA==.',
Bl='Blackhuuf:BAAANQADCgUIBQAAAA==.Blitzedbust:BAAANQADCggIFQAAAA==.Bloodmender:BAAANQADCgYIBwABNQAECgIIAgARAAAAAA==.Bluesummer:BAAANQAECgYIBgABNQAECgcIHAAKAEAgAA==.',
Bo='Bobeh:BAAANQAECgEIAgABNQADCgEIAQARAAAAAA==.Bolts:BAAANQABCgEIAQAAAA==.Boomskittles:BAAANQABCgMIAwAAAA==.Borat:BAABNQAECn8iAAIQAAkK+iOACQCyAwAQAAkK+iOACQCyAwAAAA==.Borsam:BAAANQABCgcICQAAAA==.',
Br='Brendameeks:BAAANQADCgQIBAAAAA==.Broadzinatl:BAAANQAECgIIAgAAAA==.Brom:BAAANQAECgQIBgAAAA==.Brutesse:BAAANQAECgQIDAAAAA==.Bròly:BAAANQADCgMIAwAAAA==.',
Bu='Buttercups:BAAANQADCgMIAwAAAA==.',
['Bè']='Bètflèch:BAAANQAECgIIAgAAAA==.',
['Bø']='Bøss:BAAANQADCggIEgAAAA==.',
Ca='Cad:BAAANQADCgYIEAAAAA==.Calytrix:BAEBNQAECn8jAAMSAAgKbxVNOgAcAgASAAgKbxVNOgAcAgATAAEKXxEYPwA5AAAAAA==.Captnhammer:BAAANQADCgEIAQAAAA==.Carnelian:BAAANQADCgcIFAAAAA==.Castration:BAAANQADCgYICQAAAA==.',
Ce='Ceylan:BAAANQAECgcIEwAAAA==.',
Ch='Charlz:BAAANQADCggIDgAAAA==.Charsifood:BAAANQAECgcIDgAAAA==.Chat:BAABNQAECn8XAAIUAAgKaiYKAwCEAwAUAAgKaiYKAwCEAwAAAA==.Cheatpriest:BAABNQAECn8lAAIIAAgKMhLhZgDmAQAIAAgKMhLhZgDmAQAAAA==.Chepis:BAAANQADCgcJEAAAAA==.Chesthyr:BAAANQADCgcIDgAAAA==.Chestoe:BAAANQAECgUIDQAAAA==.Chitchatted:BAAANQADCgIIAgAAAA==.',
Ci='Cindrethresh:BAAANQADCgMIAwAAAA==.',
Co='Cognition:BAABNQAECn8pAAIVAAgK4SLYHQAfAwAVAAgK4SLYHQAfAwAAAA==.Coldvengance:BAABNQAECn8cAAIWAAgKtgc+EwBpAQAWAAgKtgc+EwBpAQAAAA==.',
Cr='Cranknstein:BAAANQADCggJCAABNQADCggIEQARAAAAAA==.Crazh:BAAANQAECgIIAwAAAA==.Crazycalla:BAAANQAECgMIBAAAAA==.Croven:BAAANQADCgUIBQAAAA==.',
Cu='Cuensour:BAAANQADCgcJDQAAAA==.Cutemenace:BAAANQADCgIIAgABNQAFFAMIAwARAAAAAA==.',
Cy='Cymindel:BAABNQAECn8lAAIKAAgKfhUsOgAbAgAKAAgKfhUsOgAbAgAAAA==.Cyphr:BAAANQAECgQIBAAAAA==.',
Da='Dakotà:BAAANQAECgUIEgAAAA==.Darc:BAAANQAECgUICQAAAA==.Daredayo:BAAANQADCgIIAgAAAA==.Darkangelz:BAAANQADCgYIBgAAAA==.Darklorising:BAAANQAECgIIAgAAAA==.Darktroll:BAAANQADCgYICAAAAA==.',
De='Dejno:BAABNQAECn8WAAMWAAcKlSDlCQAwAgAWAAYKxCLlCQAwAgAPAAIK/BQ5JQGFAAAAAA==.Deleted:BAAANQADCgUIBQABNQAECgIIAgARAAAAAA==.Dethra:BAAANQAECgQIDgAAAA==.Dezign:BAACNQAFFH8YAAMXAAYKniEkAQB8AQAQAAUKeR72EwDSAQAXAAQKpSMkAQB8AQA1AAQKfzYAAxcACQoWJk8AAN0DABcACQoMJk8AAN0DABAACQo7JEcZAHADAAAA.',
Do='Dolgorukov:BAABNQAECn8eAAIVAAgKhw3SkQDiAQAVAAgKhw3SkQDiAQAAAA==.Dologony:BAAANQAECgYIDAAAAA==.',
Dr='Draccosa:BAAANQADCgIIAgAAAA==.Dracigor:BAAANQABCgcIFAAAAA==.Dragonmage:BAAANQAECgUICwAAAA==.Drakhan:BAAANQAECgUIBQAAAA==.Drakma:BAAANQAECgMIBQAAAA==.Drastio:BAAANQADCgMIAwAAAA==.Drikken:BAABNQAECn8sAAMYAAgK/hdvCwAVAgAYAAgK/hdvCwAVAgAZAAcKFhFJNACcAQAAAA==.Drmaker:BAAANQAECgEIAgAAAA==.Druj:BAEANQADCgcIBwABNQAECggIIwASAG8VAA==.',
Du='Durasan:BAAANQADCgMIAwAAAA==.',
['Dö']='Dötdötdead:BAAANQAECgUICAAAAA==.',
Ef='Effindin:BAAANQADCgYIBgAAAA==.Effinsick:BAAANQAECgQIBAAAAA==.',
Ei='Eisheth:BAAANQAECgEIAQAAAA==.',
El='Elerav:BAAANQAECgQIBwAAAA==.Ellysiaa:BAAANQADCggIHwAAAA==.',
Em='Emmakyn:BAABNQAECn8XAAMSAAgKGhDIQQDtAQASAAgKcg/IQQDtAQAaAAEK3BZxWgA8AAAAAA==.',
En='Endjinns:BAAANQADCggICAAAAA==.Enyxea:BAAANQAECgMIBAAAAA==.',
Er='Erodin:BAAANQADCgYICwAAAA==.',
Es='Esman:BAAANQADCgMIAwAAAA==.',
Ey='Eyedontknow:BAAANQAECgUIDgAAAA==.',
Ez='Ezzka:BAABNQAECn8lAAMLAAgKuiCJFQAMAwALAAgKlCCJFQAMAwAKAAIKxhuFqAB8AAAAAA==.',
Fa='Faceless:BAAANQAECgYIBQAAAA==.Failroots:BAAANQAECgIIAgAAAA==.False:BAAANQAECgIIAgAAAA==.Farnsworth:BAAANQAECgUIBQAAAA==.Farzix:BAAANQAECgUIEQAAAA==.Fatherdrew:BAAANQAECgcIDQAAAA==.Façade:BAABNQAECn8dAAMbAAkKYROMNgD5AQAbAAgKZxWMNgD5AQALAAcKrw8+bABeAQAAAA==.',
Fe='Fefifabrizio:BAAANQAECgEIAQAAAA==.Felix:BAAANQAECgQIDAAAAA==.Felraena:BAAANQADCgIIAgAAAA==.',
Fi='Finnagas:BAAANQAECgEJAQAAAA==.Finnw:BAAANQABCgcJCgAAAA==.Firelite:BAAANQAECgUIDAAAAA==.',
Fl='Flairadin:BAABNQAECn8fAAIOAAgKbxoSPQBuAgAOAAgKbxoSPQBuAgAAAA==.Flee:BAAANQAECgEIAQAAAA==.Fleromars:BAAANQADCgYIBgABNQAECgEIAQARAAAAAA==.Flexo:BAAANQAECgQIBQABNQAECgUIBQARAAAAAA==.',
Fo='Fookmii:BAAANQADCgUIBgAAAA==.',
Fr='Frogfist:BAAANQAECgMIAwAAAA==.Frowdawn:BAABNQAECn8WAAINAAYKvgkKXQA7AQANAAYKvgkKXQA7AQAAAA==.',
Ga='Garbanzo:BAAANQAECgUIBQAAAA==.Garythenpc:BAAANQADCgcIFwAAAA==.',
Ge='Genericeric:BAAANQAECgUIBQAAAA==.Getsumei:BAAANQAECgYIBgAAAA==.',
Gh='Ghyaros:BAAANQADCgIIAgABNQAFFAQICgAUANAkAA==.',
Gi='Gidgett:BAAANQADCgcIFAAAAA==.Gilas:BAAANQADCgcIBwAAAA==.',
Gl='Glacialkitty:BAABNQAECn8dAAIHAAgKiwVPPwAlAQAHAAgKiwVPPwAlAQAAAA==.Glizzygoblin:BAAANQADCgQIBAAAAA==.',
Go='Gobibug:BAAANQADCgIJAgAAAA==.Googoobler:BAAANQAECgEIAQAAAA==.Goudalovin:BAAANQADCgQIBAABNQAECggIHgAQAO0UAA==.Goudanight:BAAANQADCgIIAgABNQAECggIHgAQAO0UAA==.Goudatime:BAAANQAECgUIDgABNQAECggIHgAQAO0UAA==.',
Gr='Greenknight:BAAANQADCggICQAAAA==.Greenmagus:BAAANQAECgEJAQAAAA==.Grenadon:BAAANQADCgcIFgAAAA==.Greyni:BAAANQABCgEIAQAAAA==.',
Ha='Hakibalboa:BAABNQAECn8sAAIcAAkKoAsCEwCxAQAcAAkKoAsCEwCxAQAAAA==.Hakitua:BAAANQADCgYIBgAAAA==.Harick:BAAANQADCgQIBAAAAA==.Hazard:BAABNQAECn8fAAIWAAgKnAyMDwCvAQAWAAgKnAyMDwCvAQAAAA==.',
He='Heis:BAAANQADCgcIDgAAAA==.Hellboii:BAAANQAECgcIDgAAAA==.Heyitsrat:BAABNQAECn8bAAIDAAcKSgcu5QBKAQADAAcKSgcu5QBKAQAAAA==.',
Ho='Hollowtips:BAAANQADCggIEgAAAA==.Holo:BAABNQAECn8oAAMGAAkKmiS+GAAyAwAGAAgK8CS+GAAyAwAFAAkKHw/TcwCsAQAAAA==.Holyangus:BAAANQAECgQIBQAAAA==.Housemom:BAAANQAECgUICQAAAA==.',
Hu='Huntem:BAAANQADCgMIAgAAAA==.Huuginn:BAAANQADCggICgAAAA==.',
Ib='Ibbert:BAAANQADCggIEgAAAA==.',
Ic='Icculus:BAAANQAECgIIAwAAAA==.',
Im='Imaresmashy:BAAANQADCgIIAgABNQAECgQIBQARAAAAAA==.Iminyou:BAABNQAECn8eAAIGAAgKJhVaXwAAAgAGAAgKJhVaXwAAAgAAAA==.',
Io='Iolz:BAAANQABCgQIBgABNQAECgkJJQAPACkXAA==.',
Ja='Jaenei:BAAANQAECgMIBAAAAA==.Janet:BAAANQADCgYIBgABNQAECgkJKwAIABUkAA==.',
Je='Jeeb:BAABNQAECn8nAAIQAAcK7g4f6AC2AQAQAAcK7g4f6AC2AQAAAA==.',
Ji='Jinxta:BAABNQAECn8dAAIMAAgKqRz9BADQAgAMAAgKqRz9BADQAgAAAA==.',
Jo='Joansnow:BAAANQAECgcIBwAAAA==.Joeeo:BAABNQAECn8pAAMIAAkK+xq8KQC/AgAIAAkK+xq8KQC/AgAJAAcKighOPgA2AQAAAA==.',
Ju='July:BAAANQAECgMIBAAAAA==.Julytonidas:BAABNQAECn8YAAIQAAgKPxjXmABOAgAQAAgKPxjXmABOAgAAAA==.Jurac:BAAANQADCggIDQAAAA==.',
Ka='Kaimargonar:BAAANQAECgUIDQAAAA==.Kaitoi:BAAANQAECgUIDgAAAA==.Kamakizeg:BAAANQAECgUIEwAAAA==.Kamayla:BAAANQADCgYIBgAAAA==.Kateria:BAAANQAECgMIAwABNQAECggIJQALALogAA==.Katimalice:BAAANQADCgQJDQAAAA==.',
Ke='Keathry:BAAANQADCgcICwAAAA==.Keyzeus:BAAANQAECgIIAwAAAA==.',
Kh='Khas:BAAANQADCgMIAwAAAA==.Khui:BAACNQAFFH8KAAIUAAQK0CTpAwCnAQAUAAQK0CTpAwCnAQA1AAQKfyoAAxQACQqeI58EAFoDABQACQqeI58EAFoDAB0ABQqUHXM0AG0BAAAA.',
Ki='Killatu:BAAANQABCggIDQAAAA==.Killerdeath:BAAANQAECgMIAwAAAA==.',
Kn='Knìghtmàrè:BAACNQAFFH8JAAMLAAUKxxBvDwAQAQALAAQK7w5vDwAQAQAKAAMKhRTgHgCPAAA1AAQKfygAAwsACQpxI9cTABgDAAsACQpxI9cTABgDAAoABwocHWo0ADgCAAAA.',
Ko='Koltharaz:BAACNQAFFH8GAAIeAAIK4h/3CQDBAAAeAAIK4h/3CQDBAAA1AAQKfycAAh4ACQqKG44JANYCAB4ACQqKG44JANYCAAAA.Korloff:BAAANQADCggIEwABNQAECgIIAwARAAAAAQ==.Kozan:BAAANQAECgIIAwAAAQ==.',
Kr='Krazsz:BAAANQADCgQIBAAAAA==.Krazylock:BAAANQAECgQICAAAAA==.',
Ku='Kumah:BAAANQABCgEIAQAAAA==.Kungfuupanda:BAAANQAECgYIEQAAAA==.',
Ky='Kylar:BAAANQAECgQIBgAAAA==.',
La='Lateralus:BAABNQAECn8eAAILAAgKsSKgLwBvAgALAAgKsSKgLwBvAgAAAA==.Latt:BAAANQAECgQICgABNQAECggIHgALALEiAA==.Lawluss:BAABNQAECn8WAAIVAAUKQBZZuwCIAQAVAAUKQBZZuwCIAQAAAA==.Layonface:BAAANQAECgQICAAAAA==.',
Le='Legacyshot:BAAANQAECgQIBQAAAQ==.Lelwani:BAAANQADCgEIAQAAAA==.',
Li='Lickthecrit:BAAANQAECgMIAwAAAA==.Lightguard:BAAANQADCggICQAAAA==.Lighthouse:BAABNQAECn8oAAMOAAgKOxcxSgA9AgAOAAgKOxcxSgA9AgADAAMK+QZOWQGJAAAAAA==.Lightload:BAAANQAECgQICAAAAA==.Lileth:BAAANQAECgEIAQAAAA==.',
Lo='Lolhahabaha:BAAANQAECgMIBgAAAA==.Lonê:BAAANQAECgIIAgAAAA==.Loopie:BAAANQAECgEIAQAAAA==.Lorax:BAAANQAECgYICAAAAA==.',
Lu='Luckÿ:BAAANQAECgEJAQAAAA==.Luminah:BAAANQABCgIIAQAAAA==.',
Ly='Lypally:BAABNQAECn8nAAIDAAgKngQw8gAyAQADAAgKngQw8gAyAQAAAA==.',
['Lï']='Lïllïth:BAABNQAECn8bAAIVAAcKdQa+vgCAAQAVAAcKdQa+vgCAAQAAAA==.Lïly:BAAANQAECgIIAgABNQAECgQIBQARAAAAAA==.',
['Ló']='Lóla:BAABNQAECn8gAAIZAAgKvB69EgDSAgAZAAgKvB69EgDSAgAAAA==.',
Ma='Madeah:BAABNQAFFH8WAAINAAcKbhRmAgBcAgANAAcKbhRmAgBcAgAAAA==.Madforge:BAABNQAECn8oAAIFAAgKZxlxRwBBAgAFAAgKZxlxRwBBAgAAAA==.Magegrizz:BAAANQAECgYIDgAAAA==.Magnyson:BAAANQAECggICAAAAA==.Mahimahi:BAAANQADCgYICgAAAA==.Manahole:BAABNQAECn8oAAIQAAkKsB0LQAAFAwAQAAkKsB0LQAAFAwAAAA==.Mariacuras:BAAANQAECggIEwAAAA==.Marijwana:BAAANQAECgUICwAAAA==.Martis:BAABNQAECn8hAAIbAAkKxwhOSACVAQAbAAkKxwhOSACVAQAAAA==.Marynne:BAABNQAECn8dAAIHAAcKyApqPQAyAQAHAAcKyApqPQAyAQAAAA==.Mazuko:BAABNQAECn8cAAIfAAgKfxVCLwAoAgAfAAgKfxVCLwAoAgAAAA==.',
Mc='Mctank:BAAANQADCgMIBQAAAA==.',
Me='Mecandry:BAABNQAECn8pAAIVAAgKWBVpZABKAgAVAAgKWBVpZABKAgAAAA==.Mecks:BAAANQADCgcIEwAAAA==.Meepe:BAAANQADCgcIDQAAAA==.Melivant:BAAANQAECgYIEwAAAA==.Meranda:BAABNQAECn8eAAIQAAgK7RQApwAzAgAQAAgK7RQApwAzAgAAAA==.Merriklade:BAABNQAECn8dAAMWAAgKbg2cEgB1AQAWAAcKmA6cEgB1AQAPAAcK7wUk0wBFAQAAAA==.Merrikoid:BAAANQAECgUIDgAAAA==.Merrikwolf:BAAANQADCgYIBgAAAA==.',
Mi='Mico:BAAANQAECgQIDAAAAA==.Missyjelliot:BAAANQADCgEIAQAAAA==.',
Mo='Morbidstyle:BAAANQADCgcIDAABNQAECgkJKQAGAOUTAA==.Morgoth:BAABNQAECn8oAAICAAgKARrRUQBcAgACAAgKARrRUQBcAgAAAA==.Morthos:BAAANQADCgcICgAAAA==.Mosry:BAABNQAECn8oAAIKAAgKZx/DGwDOAgAKAAgKZx/DGwDOAgABNQABCgQIBgARAAAAAA==.Mourneblood:BAAANQADCgUIBQAAAA==.',
My='Myora:BAEANQADCgIIAgABNQAECggIIwASAG8VAA==.Mythundirus:BAAANQAECgYIEQAAAA==.',
['Mà']='Màrli:BAABNQAECn8gAAIKAAgK/hipOwASAgAKAAgK/hipOwASAgAAAA==.',
['Mâ']='Mâgs:BAABNQAECn8dAAIEAAgKRA35LQBqAQAEAAgKRA35LQBqAQAAAA==.',
Na='Nakasid:BAABNQAECn8lAAMIAAkKBhE/TgA2AgAIAAkKBhE/TgA2AgAJAAUKBgccTwDSAAAAAA==.Nashoba:BAAANQADCgYJCwAAAA==.Natooka:BAAANQADCgUIBQAAAA==.',
Ne='Nein:BAAANQAECgMICAAAAA==.Neins:BAAANQADCgYIEAABNQAECgMICAARAAAAAA==.Nevaehstar:BAABNQAECn8tAAIQAAgKnQ/KwwD7AQAQAAgKnQ/KwwD7AQAAAA==.',
Ni='Nibuto:BAAANQAECgUICgAAAA==.Nijun:BAEBNQAECn8gAAIIAAgK+guJegCmAQAIAAgK+guJegCmAQAAAA==.Nik:BAAANQAECgYICgAAAA==.Nikolia:BAAANQAECgQIDwAAAA==.Ninetynine:BAAANQADCgQIBAAAAA==.Nini:BAAANQAECgUIDAAAAA==.Ninx:BAAANQADCgUICQAAAA==.',
No='Noivana:BAAANQABCgEIAQABNQAFFAUIDAAfALMbAA==.',
Ny='Nystel:BAAANQADCgEIAQAAAA==.',
Ol='Ollichi:BAAANQADCgIIAgAAAA==.',
Or='Ornn:BAAANQAECgYICQABNQAECgkJKAABAJIjAA==.',
Os='Osoroshi:BAAANQADCgYJBgABNQAECggIKQAVAFgVAA==.',
Ov='Overtime:BAAANQADCggIEQAAAA==.',
Pa='Padmê:BAAANQADCgMIAwAAAA==.Paladrak:BAAANQADCgIIAgAAAA==.Pandamared:BAAANQADCgIIAgAAAA==.Patronous:BAAANQADCgYIDAAAAA==.',
Ph='Phenol:BAAANQADCgEIAQAAAA==.',
Po='Polog:BAAANQAECgIIAgAAAA==.Porkchoplust:BAAANQADCgUIBQAAAA==.Porkribs:BAABNQAECn8aAAIOAAcKMh3WRABQAgAOAAcKMh3WRABQAgAAAA==.',
Pu='Puca:BAAANQADCgcIFwAAAA==.Pumdmuc:BAAANQAECgUIDwABNQAECgkJJgAFAFseAA==.Punchymcheal:BAAANQAECgIIBAABNQAECgkJMAAIAHccAA==.',
Qu='Quikglaives:BAAANQAECgEIAQAAAA==.Quille:BAABNQAECn8cAAIVAAcKNSFIVAByAgAVAAcKNSFIVAByAgAAAA==.',
Ra='Ragretts:BAAANQAECgEIAQAAAA==.Rahhem:BAAANQADCgYIBgAAAA==.Ranmo:BAAANQAECgcIDwAAAA==.Ratkol:BAAANQABCgIIAgAAAA==.Raysdknight:BAAANQADCgIJBwAAAA==.',
Re='Recbra:BAAANQABCgUIBQAAAA==.Redrek:BAAANQADCgcIIgAAAA==.Redshunter:BAAANQADCgYIDAAAAA==.Redwinter:BAABNQAECn8cAAIKAAcKQCAHLABmAgAKAAcKQCAHLABmAgAAAA==.Reikisong:BAAANQAECgIIAgAAAA==.Reiluune:BAAANQADCgQIAwABNQAECggIIAAZALweAA==.Remmie:BAAANQADCgUIBwAAAA==.',
Rh='Rhagurion:BAABNQAECn8xAAIaAAkKMCa3AADtAwAaAAkKMCa3AADtAwAAAA==.',
Ri='Riqua:BAAANQAECgMIBQAAAA==.',
Ro='Rockmonsta:BAAANQADCgYJCgAAAA==.Rockys:BAAANQABCgQIBQAAAA==.Roxies:BAAANQAECgMIBgAAAA==.',
Rp='Rpg:BAABNQAECn8YAAIQAAgKJBqslwBQAgAQAAgKJBqslwBQAgAAAA==.',
Ru='Runes:BAAANQAECgUIBgAAAA==.',
Sa='Saeti:BAABNQAECn8vAAUTAAkKcyNUBQAnAwATAAgKcyNUBQAnAwAHAAQK4Ay5TgDLAAASAAIKeBb/mQBsAAAaAAEKxB+tUQBWAAAAAA==.Sanbit:BAAANQADCggIFAAAAA==.Santhaenis:BAAANQADCgcICQAAAA==.Sapplesauce:BAAANQADCggICQAAAA==.',
Se='Seethrowwar:BAABNQAECn8iAAMPAAkKuh7fOgDYAgAPAAkKaB7fOgDYAgAgAAYKQRZyGwB+AQAAAA==.Senbit:BAAANQAECgUIDQAAAA==.Serenìty:BAAANQAECgUIDAAAAA==.Seresin:BAABNQAECn9EAAMHAAkK+xgcFQCbAgAHAAkK+xgcFQCbAgASAAUKkwUSgQDHAAAAAA==.',
Sh='Shadý:BAABNQAECn8bAAIVAAcKHwRT4QA5AQAVAAcKHwRT4QA5AQAAAA==.Shamanoodles:BAAANQADCggIFAABNQAECgIIAgARAAAAAA==.Shortwarrior:BAAANQAECgUIDwAAAA==.',
Si='Sianu:BAAANQAECgEIAQABNQAECgcIHQAHAMgKAA==.Sidraya:BAAANQAECgQICAAAAA==.Silent:BAABNQAECn8lAAIPAAkKKReCaABTAgAPAAkKKReCaABTAgAAAA==.Silverserqet:BAAANQAECgUIDgAAAA==.',
Sl='Slipknaught:BAAANQABCgQIBQABNQAECgcIBwARAAAAAA==.',
Sm='Smileyriley:BAAANQADCgUIBQAAAA==.',
Sn='Sneakylinks:BAAANQADCgIIAgABNQAECggIGAAQACQaAA==.',
So='Sonbit:BAAANQADCggJDwAAAA==.Sooki:BAAANQAECgMIBQAAAA==.Sophie:BAAANQAECgQIDgAAAA==.Soulber:BAAANQAECgMIBAAAAA==.',
Ss='Ssenbit:BAAANQADCggIGwAAAA==.Ssonbit:BAAANQADCggIEAAAAA==.',
St='Stefeana:BAAANQADCgYIBgAAAA==.Sternhoof:BAAANQABCgMIAwAAAA==.Stigma:BAAANQADCggIFQABNQAECgcIDQARAAAAAA==.Stylos:BAABNQAECn8bAAIhAAgK2A5QFQAPAgAhAAgK2A5QFQAPAgAAAA==.',
Su='Summersong:BAAANQADCgQIBAAAAA==.',
Sw='Swarli:BAAANQADCgIIAgAAAA==.Swowtitbang:BAAANQAECgMIBgAAAA==.',
Sy='Sylven:BAAANQAECgQIBAABNQAECggILAAGAJggAA==.',
Te='Tegbolt:BAABNQAECn8dAAMGAAgKeRV2ZQDsAQAGAAgKghN2ZQDsAQAhAAcKLhKQGwCmAQAAAA==.Teghorn:BAAANQAECggICAABNQAECggIHQAGAHkVAA==.Tekko:BAABNQAECn8qAAMaAAkKKxkdDQCQAgAaAAgKfRwdDQCQAgATAAEKOQXWTgAQAAAAAA==.Tempestrike:BAAANQAECggIEwAAAA==.',
Th='Theholymatt:BAABNQAECn8oAAIOAAgKpyQGEgA9AwAOAAgKpyQGEgA9AwAAAA==.Thendari:BAABNQAECn84AAIMAAgKzAsbEwDYAQAMAAgKzAsbEwDYAQAAAA==.Theodus:BAABNQAECn8kAAIQAAgKoRMvtgAVAgAQAAgKoRMvtgAVAgAAAA==.Therayen:BAAANQADCgYJCwAAAA==.',
Ti='Tiferis:BAABNQAECn8oAAIOAAkKrR2mHgD1AgAOAAkKrR2mHgD1AgAAAA==.Tigerclawss:BAAANQADCggIGQAAAA==.Tislam:BAAANQAECgMIBAAAAA==.',
To='Tobiquer:BAABNQAECn8pAAIIAAgKPCKGGQANAwAIAAgKPCKGGQANAwAAAA==.Torolf:BAAANQAECgEIAQAAAA==.',
Tq='Tqco:BAAANQADCgMIAwABNQAECgkJKgAaACsZAA==.',
Tr='Traydra:BAAANQADCgUIBwAAAA==.Trinbug:BAAANQADCgEIAQAAAA==.Troglodyte:BAABNQAECn8xAAIGAAkKrCJyCQCaAwAGAAkKrCJyCQCaAwAAAA==.',
Ts='Tsonokwabain:BAAANQAECgYIEAAAAA==.Tsunami:BAAANQADCgMIAwAAAA==.',
Tw='Twistdog:BAAANQABCgQIBgAAAA==.',
Ty='Tye:BAAANQAECggIEwAAAA==.Tyranastrasz:BAABNQAECn8jAAQeAAgK1QUbHgBtAQAeAAgK1QUbHgBtAQAiAAIK8wJqSgBKAAAjAAEKTQAKKQANAAAAAA==.Tyye:BAABNQAECn8YAAIWAAYKdSNRCABhAgAWAAYKdSNRCABhAgAAAA==.',
['Tâ']='Tâjik:BAABNQAECn8fAAIkAAkKsARQKQB2AQAkAAkKsARQKQB2AQAAAA==.',
Ul='Ulquiorra:BAACNQAFFH8JAAMZAAMKog5SDQDUAAAZAAMKog5SDQDUAAAYAAEKQAhmBwBCAAA1AAQKfysAAxkACQo5ILkPAPICABkACAo5ILkPAPICABgABAoIDZcgAL0AAAAA.',
Ut='Uthers:BAAANQADCgYIAgAAAA==.',
Va='Vaethund:BAAANQAECgMIBAAAAA==.Valgavoth:BAAANQAECgcIEQAAAA==.Vanthion:BAAANQADCgIIAgAAAA==.',
Ve='Velara:BAAANQAECgQIBQAAAA==.Velinna:BAAANQADCgUIBwABNQAECgEIAQARAAAAAA==.Venekor:BAAANQADCgIIAgAAAA==.',
Vi='Viriex:BAAANQADCgIIAgAAAA==.Vitoria:BAAANQAECgQIBgAAAA==.',
Vo='Voidlighter:BAABNQAECn8wAAIIAAkKdxyDIwDcAgAIAAkKdxyDIwDcAgAAAA==.Volundr:BAABNQAECn8eAAIgAAgK9RbnDQBOAgAgAAgK9RbnDQBOAgAAAA==.Vonvaughan:BAAANQAECgIIAgABNQAECgIIAgARAAAAAA==.',
Vy='Vynel:BAAANQADCgMIAwABNQAECggILAAGAJggAA==.Vynirion:BAAANQAECgEIAQAAAA==.',
Wa='Wardellmo:BAAANQADCgQIBAAAAA==.Wargtar:BAABNQAECn8bAAINAAcKCBncMgAMAgANAAcKCBncMgAMAgAAAA==.',
We='Weabe:BAAANQAECgIIAwAAAA==.',
Wh='Whiterrina:BAAANQADCgIJAgAAAA==.Whitespring:BAAANQAECgQIBwABNQAECgcIHAAKAEAgAA==.',
Wo='Wolfgarou:BAAANQABCgIIAgAAAA==.',
Wy='Wyrdo:BAAANQADCgYIBgAAAA==.',
['Wù']='Wùsthof:BAABNQAECn8fAAIVAAkKYApLhwD5AQAVAAkKYApLhwD5AQAAAA==.',
Xa='Xandrios:BAAANQAECgEJAQAAAA==.',
Xi='Xiae:BAABNQAECn8fAAIGAAgK6RbeSwBEAgAGAAgK6RbeSwBEAgAAAA==.',
Ya='Yasuke:BAAANQADCgUJBQAAAA==.',
Ye='Yet:BAAANQAECgEIAQABNQAECgkJIgAQAPojAA==.',
Yi='Yiffweaver:BAAANQAECgEIAQAAAA==.',
Yo='Yokochan:BAAANQABCgIIAgAAAA==.Yokoriazen:BAABNQAECn8rAAIDAAkKDBdlXwB3AgADAAkKDBdlXwB3AgAAAA==.',
Za='Zakaradin:BAAANQADCgcICAABNQAECgIIAwARAAAAAA==.Zandigor:BAAANQABCggIFAAAAA==.Zaraeliana:BAAANQAECgMIBAAAAA==.Zarastraza:BAABNQAECn8hAAMiAAcKtRI1IgC3AQAiAAcKtRI1IgC3AQAeAAUKFQsyJQAPAQAAAA==.',
Ze='Zephnor:BAABNQAECn8bAAMaAAcKahDLIwByAQAaAAYKxBLLIwByAQASAAcKHgnmYQBDAQAAAA==.',
Zh='Zhao:BAAANQADCgYIBgAAAA==.',
Zm='Zmona:BAAANQAECgQIBAAAAA==.',
Zo='Zorsche:BAAANQAECgEIAQAAAA==.',
Zu='Zulrok:BAABNQAECn8fAAIPAAgKlhAGnwDLAQAPAAgKlhAGnwDLAQAAAA==.',
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
