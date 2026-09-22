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

local lookup = {'Warlock-Demonology','Druid-Restoration','Unknown-Unknown','Mage-Frost','Mage-Arcane','Shaman-Elemental','Shaman-Restoration','Warrior-Arms','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Devastation','Rogue-Assassination','DemonHunter-Havoc','Druid-Guardian','Druid-Feral','Druid-Balance','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Holy','Paladin-Retribution',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Absol:BAABNQAECoEYAAIBAAgKeR/wFQDlAgABAAgKeR/wFQDlAgAAAA==.',
Ac='Achilles:BAAANQAECggIDwAAAA==.',
Ae='Aerís:BAAANQADCgIIAgAAAA==.',
Ah='Ahsokatano:BAAANQAECgUICwAAAA==.',
Ai='Ailing:BAAANQADCgYIDAAAAA==.Aimspet:BAAANQADCggJCAAAAA==.',
Ak='Akasha:BAAANQABCgMJBwAAAA==.Akos:BAAANQADCggJEAABNQAECggJJAACAJUVAA==.',
Al='Alzaeryan:BAAANQAECgQIBAAAAA==.',
Am='Amonet:BAAANQADCgcJFgAAAA==.',
An='Anamis:BAAANQAECgUJCAAAAA==.Angras:BAAANQAECgYIDQAAAA==.',
Ap='Aphalock:BAAANQAECgYIDgAAAA==.',
Ar='Ariûs:BAAANQAECgIJAgAAAA==.Arlin:BAAANQADCgcJDQAAAA==.Arlorian:BAAANQAECgYIDwAAAA==.Arrenn:BAAANQAECgMJBQAAAA==.Arrowsmites:BAAANQAECgUICQAAAA==.',
As='Askelad:BAAANQAECgMIAwAAAA==.',
Au='Aubani:BAAANQAECgUJCQAAAA==.',
Ay='Ayperos:BAAANQAECgYIDgAAAA==.',
Ba='Bakedpally:BAAANQAECgQJBwAAAA==.Bakedwarrior:BAAANQADCgIIAgAAAA==.Bambalina:BAAANQADCggJCgAAAA==.Bandomar:BAAANQAECgEJAQAAAA==.Baragnis:BAAANQAECgUIBQAAAA==.',
Be='Beavur:BAAANQAECgQJBQAAAA==.Beck:BAAANQAECgcIDAAAAA==.Bereth:BAAANQADCgcJFgAAAA==.Berreydingle:BAAANQADCggJFwAAAA==.',
Bi='Bigboii:BAAANQADCgYIBgAAAA==.Bigkitty:BAAANQAECgIIAgABNQAECgYJDgADAAAAAA==.Bikinibrenda:BAAANQADCgYIBgAAAA==.',
Bl='Blackhuuf:BAAANQADCgUIBQAAAA==.Blitzedbust:BAAANQADCggJDQAAAA==.Bloodmender:BAAANQADCgYIBwABNQAECgYIDQADAAAAAA==.Bluesummer:BAAANQADCgcJFAABNQAECgUJCQADAAAAAA==.',
Bo='Bobeh:BAAANQADCggIFAABNQADCgEIAQADAAAAAA==.Bolts:BAAANQABCgEIAQAAAA==.Boomskittles:BAAANQABCgMIAwAAAA==.Borat:BAAANQAECgYIDgABNQADCgYIDwADAAAAAA==.Borsam:BAAANQABCgYICAAAAA==.',
Br='Brendameeks:BAAANQADCgQIBAAAAA==.Broadzinatl:BAAANQAECgIJAgAAAA==.Brom:BAAANQAECgIJAgAAAA==.Brutesse:BAAANQAECgQIBAAAAA==.',
['Bè']='Bètflèch:BAAANQAECgEJAQAAAA==.',
Ca='Cad:BAAANQADCgYIEAAAAA==.Calytrix:BAEANQAECgcJEgAAAA==.Captnhammer:BAAANQADCgEIAQAAAA==.Carnelian:BAAANQADCgcJEwAAAA==.Castration:BAAANQADCgYICQAAAA==.',
Ce='Ceylan:BAAANQAECgUJCQAAAA==.',
Ch='Charsifood:BAAANQAECgYJDAAAAA==.Cheatpriest:BAAANQAECgcJEwAAAA==.Chepis:BAAANQADCgcJEAAAAA==.Chesthyr:BAAANQADCgcIDgAAAA==.Chestoe:BAAANQAECgMIBAAAAA==.Chitchatted:BAAANQADCgIIAgAAAA==.',
Ci='Cindrethresh:BAAANQADCgMIAwAAAA==.',
Co='Cognition:BAAANQAECgYIDwAAAA==.Coldvengance:BAAANQAECgUJCQAAAA==.',
Cr='Cranknstein:BAAANQADCggJCAABNQADCggIEQADAAAAAA==.Crazh:BAAANQAECgIIAwAAAA==.Crazycalla:BAAANQADCgYJCwAAAA==.Croven:BAAANQADCgUIBQAAAA==.',
Cu='Cuensour:BAAANQADCgcJDQAAAA==.Cutemenace:BAAANQADCgIIAgABNQAFFAIIAgADAAAAAA==.',
Cy='Cymindel:BAAANQAECgcJEAAAAA==.',
Da='Dakotà:BAAANQAECgMJBAAAAA==.Darc:BAAANQAECgEJAQAAAA==.Daredayo:BAAANQADCgIIAgAAAA==.Darklorising:BAAANQAECgEJAQAAAA==.',
De='Dejno:BAAANQAECgYIEAAAAA==.Deleted:BAAANQADCgUIBQABNQAECgYIDQADAAAAAA==.Dethra:BAAANQAECgIIBAAAAA==.Dezign:BAACNQAFFIEIAAMEAAUKWiBgAQDLAAAFAAQKuB0wDQCLAQAEAAIKkh1gAQDLAAA1AAQKgSAAAwQACQoGJSUCAPMCAAUACQoSIzgZAFMDAAQABwp8JCUCAPMCAAAA.',
Do='Dolgorukov:BAAANQAECgUJCAAAAA==.Dologony:BAAANQAECgIIBAAAAA==.',
Dr='Draccosa:BAAANQADCgIIAgAAAA==.Dragonmage:BAAANQAECgQJBgAAAA==.Drakhan:BAAANQADCgIJAgAAAA==.Drakma:BAAANQAECgEIAgAAAA==.Drastio:BAAANQADCgMIAwAAAA==.Drikken:BAAANQAECgcJEwAAAA==.Drmaker:BAAANQAECgEJAQAAAA==.Druj:BAEANQADCgcIBwABNQAECgcJEgADAAAAAA==.',
Du='Durasan:BAAANQADCgMIAwAAAA==.',
['Dö']='Dötdötdead:BAAANQAECgEIAQAAAA==.',
Ef='Effindin:BAAANQADCgYIBgAAAA==.Effinsick:BAAANQADCggIFwAAAA==.',
Ei='Eisheth:BAAANQADCgYICwAAAA==.',
El='Ellysiaa:BAAANQADCggJHwAAAA==.',
Em='Emmakyn:BAAANQAECgEJAQAAAA==.',
En='Endjinns:BAAANQADCggICAAAAA==.Enyxea:BAAANQAECgIJAgAAAA==.',
Er='Erodin:BAAANQADCgYICwAAAA==.',
Es='Esman:BAAANQADCgMIAwAAAA==.',
Ey='Eyedontknow:BAAANQAECgIIAgAAAA==.',
Ez='Ezzka:BAAANQAECgUIDAABNQAECgYIEAADAAAAAA==.',
Fa='Faceless:BAAANQAECgYIBQAAAA==.Failroots:BAAANQAECgIIAgAAAA==.False:BAAANQAECgIIAgAAAA==.Farzix:BAAANQAECgQJBwAAAA==.Façade:BAAANQAECgcIDgAAAA==.',
Fe='Fefifabrizio:BAAANQAECgEIAQAAAA==.Felix:BAAANQAECgEIAgAAAA==.Felraena:BAAANQADCgIIAgAAAA==.',
Fi='Finnagas:BAAANQAECgEJAQAAAA==.Finnw:BAAANQABCgcJCgAAAA==.Firelite:BAAANQAECgEJAgAAAA==.',
Fl='Flairadin:BAAANQAECgUJCQAAAA==.Flexo:BAAANQAECgEIAQAAAA==.',
Fo='Fookmii:BAAANQADCgUIBgAAAA==.',
Fr='Frogfist:BAAANQAECgMIAwAAAA==.Frowdawn:BAAANQAECgMIBgAAAA==.',
Ga='Garythenpc:BAAANQADCgcJFgAAAA==.',
Ge='Genericeric:BAAANQADCgcICAAAAA==.',
Gi='Gidgett:BAAANQADCgcIDQAAAA==.',
Gl='Glacialkitty:BAAANQAECgUICQAAAA==.Glizzygoblin:BAAANQADCgQIBAAAAA==.',
Go='Gobibug:BAAANQADCgIJAgAAAA==.Googoobler:BAAANQADCggIEgAAAA==.Goudalovin:BAAANQADCgQIBAABNQAECgYJDgADAAAAAA==.Goudanight:BAAANQADCgIIAgABNQAECgYJDgADAAAAAA==.Goudatime:BAAANQAECgIIAgABNQAECgYJDgADAAAAAA==.',
Gr='Greenknight:BAAANQADCggICQAAAA==.Greenmagus:BAAANQAECgEJAQAAAA==.Grenadon:BAAANQADCgcJFQAAAA==.Greyni:BAAANQABCgEIAQAAAA==.',
Ha='Hakibalboa:BAAANQAECgcJEwAAAA==.Hakitua:BAAANQADCgYIBgAAAA==.Harick:BAAANQADCgQIBAAAAA==.Hazard:BAAANQAECgUJCQAAAA==.',
He='Heis:BAAANQADCgcJDQAAAA==.Hellboii:BAAANQAECgYJDAAAAA==.Heyitsrat:BAAANQAECgMJBgAAAA==.',
Ho='Holo:BAABNQAECoEcAAMGAAkKCiFqFAALAwAGAAgK2CBqFAALAwAHAAkKHw80QgDkAQAAAA==.Housemom:BAAANQADCggIGQAAAA==.',
Hu='Huntem:BAAANQADCgMIAgAAAA==.Huuginn:BAAANQADCgIIAgAAAA==.',
Ib='Ibbert:BAAANQADCgEJAQAAAA==.',
Ic='Icculus:BAAANQAECgEIAQAAAA==.',
Im='Imaresmashy:BAAANQABCgIIAQABNQAECgEJAQADAAAAAA==.Iminyou:BAAANQAECgYIDQAAAA==.',
Io='Iolz:BAAANQABCgQIBgABNQAECggJGQAIAN0TAA==.',
Ja='Jaenei:BAAANQAECgIJAgAAAA==.Janet:BAAANQADCgYIBgABNQAECgYIEQADAAAAAA==.',
Je='Jeeb:BAAANQAECgUIEAAAAA==.',
Ji='Jinxta:BAAANQAECgUJBwAAAA==.',
Jo='Joansnow:BAAANQADCggICgAAAA==.Joeeo:BAAANQAECgcJEAAAAA==.',
Ju='July:BAAANQAECgIJAgAAAA==.Julytonidas:BAAANQAECgEIAQAAAA==.',
Ka='Kaimargonar:BAAANQAECgEIAQAAAA==.Kaitoi:BAAANQAECgIIAgAAAA==.Kamakizeg:BAAANQAECgMIBQAAAA==.Kamayla:BAAANQADCgYIBgAAAA==.Kateria:BAAANQADCgUIBQABNQAECgYIEAADAAAAAA==.Katimalice:BAAANQADCgQJDQAAAA==.',
Ke='Keathry:BAAANQADCgcJCgAAAA==.Keyzeus:BAAANQAECgEIAQAAAA==.',
Kh='Khui:BAABNQAECoEgAAMJAAkKKCMwAgB3AwAJAAkKKCMwAgB3AwAKAAUK6R6OHgCmAQAAAA==.',
Ki='Killatu:BAAANQABCgcICQAAAA==.Killerdeath:BAAANQAECgEJAQAAAA==.',
Kn='Knìghtmàrè:BAABNQAECoEeAAMLAAkKciLJBwBlAwALAAkK1yDJBwBlAwAMAAQKOxykUQA1AQAAAA==.',
Ko='Koltharaz:BAABNQAECoEdAAINAAkKExrDBgDmAgANAAkKExrDBgDmAgAAAA==.Korloff:BAAANQADCggIEwABNQAECgIIAwADAAAAAQ==.Kozan:BAAANQAECgIIAwAAAQ==.',
Kr='Krazsz:BAAANQADCgQIBAAAAA==.Krazylock:BAAANQAECgQJBQAAAA==.',
Ku='Kumah:BAAANQABCgEIAQAAAA==.Kungfuupanda:BAAANQAECgUICgAAAA==.',
Ky='Kylar:BAAANQADCgEIAQAAAA==.',
La='Lateralus:BAABNQAECoEeAAILAAgKfCJaDgAPAwALAAgKfCJaDgAPAwAAAA==.Latt:BAAANQAECgEIAQABNQAECggJHgALAHwiAA==.Lawluss:BAAANQAECgMIBgAAAA==.',
Le='Legacyshot:BAAANQAECgEJAQAAAQ==.Lelwani:BAAANQADCgEIAQAAAA==.',
Li='Lickthecrit:BAAANQAECgEJAQAAAA==.Lightguard:BAAANQADCgcIBAAAAA==.Lighthouse:BAAANQAECgYIEgAAAA==.Lileth:BAAANQADCggICQAAAA==.',
Lo='Lolhahabaha:BAAANQADCggIEgAAAA==.Lonê:BAAANQAECgEJAQAAAA==.Loopie:BAAANQADCgMIAwAAAA==.Lorax:BAAANQAECgYICAAAAA==.',
Lu='Luckÿ:BAAANQAECgEJAQAAAA==.Luminah:BAAANQABCgIIAQAAAA==.',
Ly='Lypally:BAAANQAECgYIDAAAAA==.',
['Lï']='Lïllïth:BAAANQAECgIJBQAAAA==.Lïly:BAAANQADCgcICwABNQAECgEJAQADAAAAAA==.',
['Ló']='Lóla:BAAANQAECgQICgAAAA==.',
Ma='Madeah:BAABNQAFFIEGAAIOAAUKww7lAQCyAQAOAAUKww7lAQCyAQAAAA==.Madforge:BAAANQAECgYJDQAAAA==.Magegrizz:BAAANQAECgQICAAAAA==.Magnyson:BAAANQADCgIJAgAAAA==.Mahimahi:BAAANQADCgYICgAAAA==.Manahole:BAAANQAECgcIEgAAAA==.Mariacuras:BAAANQAECgQIBgAAAA==.Marijwana:BAAANQAECgMJBAAAAA==.Martis:BAAANQAECgYICwAAAA==.Marynne:BAAANQAECgQIBgAAAA==.Mazuko:BAAANQAECgUJCAAAAA==.',
Me='Mecandry:BAAANQAECgUICwAAAA==.Mecks:BAAANQADCgEIAQAAAA==.Meepe:BAAANQADCgcIDQAAAA==.Melivant:BAAANQAECgMIBAAAAA==.Meranda:BAAANQAECgYJDgAAAA==.Merriklade:BAAANQAECgUIBwAAAA==.Merrikoid:BAAANQAECgIIAgAAAA==.',
Mi='Mico:BAAANQAECgEIAgAAAA==.',
Mo='Morbidstyle:BAAANQADCgcIDAABNQAECggIGQAGABwQAA==.Morgoth:BAAANQAECgYJEgAAAA==.Morthos:BAAANQADCgcICgAAAA==.Mosry:BAAANQAECgYJDwAAAA==.',
My='Myora:BAEANQADCgIIAgABNQAECgcJEgADAAAAAA==.Mythundirus:BAAANQAECgQJBgAAAA==.',
['Mà']='Màrli:BAAANQAECgQJCwAAAA==.',
['Mâ']='Mâgs:BAAANQAECgUJCQAAAA==.',
Na='Nakasid:BAAANQAECgcIEgAAAA==.Nashoba:BAAANQADCgYJCwAAAA==.Natooka:BAAANQADCgUIBQAAAA==.',
Ne='Nein:BAAANQAECgIIAwAAAA==.Neins:BAAANQADCgYIEAABNQAECgIIAwADAAAAAA==.Nevaehstar:BAABNQAECoEbAAIFAAgK9g1hjAD4AQAFAAgK9g1hjAD4AQAAAA==.',
Ni='Nijun:BAEANQAECgUJCQAAAA==.Nik:BAAANQADCggIIwAAAA==.Nikolia:BAAANQAECgQIBgAAAA==.Ninetynine:BAAANQADCgQIBAAAAA==.Nini:BAAANQAECgMJAwAAAA==.Ninx:BAAANQADCgUICQAAAA==.',
No='Noivana:BAAANQABCgEIAQABNQAECgkJIgAPAH4gAA==.',
Ny='Nystel:BAAANQADCgEIAQAAAA==.',
Ol='Ollichi:BAAANQADCgIIAgAAAA==.',
Or='Ornn:BAAANQAECgQJBAABNQAECggJGAABAHkfAA==.',
Os='Osoroshi:BAAANQADCgYJBgABNQAECgUICwADAAAAAA==.',
Pa='Paladrak:BAAANQADCgIIAgAAAA==.Patronous:BAAANQADCgYIDAAAAA==.',
Ph='Phenol:BAAANQABCgIIAgAAAA==.',
Po='Polog:BAAANQAECgEIAQABNQAECgYIDQADAAAAAA==.Porkchoplust:BAAANQADCgUIBQAAAA==.Porkribs:BAAANQAECgUICQAAAA==.',
Pu='Puca:BAAANQADCgcJFgAAAA==.Pumdmuc:BAAANQAECgQJBgABNQAECgcJEgADAAAAAA==.',
Qu='Quikglaives:BAAANQADCggICAAAAA==.Quille:BAAANQAECgYIDQAAAA==.',
Ra='Ragretts:BAAANQAECgEIAQAAAA==.Rahhem:BAAANQADCgYIBgAAAA==.Ranmo:BAAANQAECgcIDQAAAA==.Ratkol:BAAANQABCgIIAgAAAA==.Raysdknight:BAAANQADCgIJBwAAAA==.',
Re='Redrek:BAAANQADCgYJFgAAAA==.Redshunter:BAAANQADCgQIBAAAAA==.Redwinter:BAAANQAECgUJCQAAAA==.Reikisong:BAAANQADCgIIAwAAAA==.Reiluune:BAAANQADCgQIAwABNQAECgQICgADAAAAAA==.Remmie:BAAANQADCgUIBwAAAA==.',
Rh='Rhagurion:BAABNQAECoEYAAIQAAkKTiWUAADXAwAQAAkKTiWUAADXAwAAAA==.',
Ri='Riqua:BAAANQAECgEJAQAAAA==.',
Ro='Rockmonsta:BAAANQADCgYJCgAAAA==.Roxies:BAAANQAECgMJAwAAAA==.',
Rp='Rpg:BAAANQAECgUIDQAAAA==.',
Sa='Saeti:BAABNQAECoEYAAQRAAkK9h67AwDyAgARAAgKCyG7AwDyAgACAAIKMxIfQAB9AAASAAEKTA4uhAAuAAAAAA==.Sapplesauce:BAAANQADCggICQAAAA==.',
Se='Seethrowwar:BAAANQAFFAEJAQAAAA==.Senbit:BAAANQAECgUIBgAAAA==.Serenìty:BAAANQAECgUIBwAAAA==.Seresin:BAABNQAECoEkAAMCAAgKlRUWFAArAgACAAgKlRUWFAArAgASAAUKNwjoWwDZAAAAAA==.',
Sh='Shadý:BAAANQAECgMJBgAAAA==.Shamanoodles:BAAANQADCggIFAABNQAECgYIDQADAAAAAA==.Shortwarrior:BAAANQAECgMIBgAAAA==.',
Si='Sidraya:BAAANQAECgEJAQAAAA==.Silent:BAABNQAECoEZAAIIAAgK3ROAVwAPAgAIAAgK3ROAVwAPAgAAAA==.Silverserqet:BAAANQAECgIIAgAAAA==.',
Sm='Smileyriley:BAAANQADCgUJBQAAAA==.',
So='Sonbit:BAAANQADCggJDwAAAA==.Sooki:BAAANQAECgMIBQAAAA==.Sophie:BAAANQAECgQIBAAAAA==.Soulber:BAAANQAECgIJAgAAAA==.',
Ss='Ssenbit:BAAANQADCgcIBwAAAA==.',
St='Sternhoof:BAAANQABCgMIAwAAAA==.Stigma:BAAANQADCggIFQAAAA==.Stylos:BAAANQAECgMJAwAAAA==.',
Su='Summersong:BAAANQADCgQIBAAAAA==.',
Sw='Swowtitbang:BAAANQADCggIFAAAAA==.',
Te='Tegbolt:BAAANQAECgcJDQAAAA==.Tekko:BAAANQAECgYIDgAAAA==.',
Th='Theholymatt:BAAANQAECgcJEwAAAA==.Thendari:BAAANQAECgUJEgAAAA==.Theodus:BAAANQAECgYIDwAAAA==.Therayen:BAAANQADCgYJCwAAAA==.',
Ti='Tiferis:BAABNQAECoEdAAITAAkKZRuJFADoAgATAAkKZRuJFADoAgAAAA==.Tigerclawss:BAAANQADCgQIBAAAAA==.Tislam:BAAANQAECgIJAgAAAA==.',
To='Tobiquer:BAAANQAECgYIDgAAAA==.Torolf:BAAANQADCggIDAAAAA==.',
Tr='Traydra:BAAANQADCgUIBwAAAA==.Trinbug:BAAANQADCgEIAQAAAA==.Troglodyte:BAAANQAECggIEwAAAA==.',
Ts='Tsonokwabain:BAAANQAECgQIBgAAAA==.Tsunami:BAAANQADCgMIAwAAAA==.',
Tw='Twistdog:BAAANQABCgQIBgAAAA==.',
Ty='Tye:BAAANQAECgUJCAAAAA==.Tyranastrasz:BAAANQAECgYJEgAAAA==.Tyye:BAAANQAECgQJBgAAAA==.',
['Tâ']='Tâjik:BAAANQAECgQJBwAAAA==.',
Ul='Ulquiorra:BAABNQAECoEdAAMUAAkKtxrREwCFAgAUAAcK6B7REwCFAgAVAAMKxwr9FQCYAAAAAA==.',
Ut='Uthers:BAAANQADCgYIAgAAAA==.',
Va='Vaethund:BAAANQAECgIJAgAAAA==.Valgavoth:BAAANQAECgYJDQAAAA==.',
Ve='Velara:BAAANQAECgQIBAAAAA==.Velinna:BAAANQADCgUIBwABNQAECgEIAQADAAAAAA==.',
Vi='Viriex:BAAANQADCgIIAgAAAA==.Vitoria:BAAANQAECgIIAgAAAA==.',
Vo='Voidlighter:BAABNQAECoEYAAIWAAgKDx7BGwCrAgAWAAgKDx7BGwCrAgAAAA==.Volundr:BAAANQAECgUJCQAAAA==.Vonvaughan:BAAANQADCgYJDwABNQAECgIJAgADAAAAAA==.',
Vy='Vynel:BAAANQADCgMIAwABNQAECggJHAAGAOkdAA==.Vynirion:BAAANQAECgEIAQAAAA==.',
Wa='Wargtar:BAAANQAECgQIDgAAAA==.',
We='Weabe:BAAANQAECgEJAQAAAA==.',
Wh='Whiterrina:BAAANQADCgIJAgAAAA==.Whitespring:BAAANQADCgQJBAABNQAECgUJCQADAAAAAA==.',
Wy='Wyrdhoof:BAAANQAECgEJAQAAAA==.Wyrdo:BAAANQADCgYIBgAAAA==.',
['Wù']='Wùsthof:BAAANQAECgcJEwAAAA==.',
Xa='Xandrios:BAAANQAECgEJAQAAAA==.',
Xi='Xiae:BAAANQAECgUJCQAAAA==.',
Ya='Yasuke:BAAANQADCgUJBQAAAA==.',
Ye='Yet:BAAANQADCgYIDwAAAA==.',
Yi='Yiffweaver:BAAANQAECgEIAQAAAA==.',
Yo='Yokochan:BAAANQABCgIIAgAAAA==.Yokoriazen:BAABNQAECoEYAAIXAAcKexSTZwDGAQAXAAcKexSTZwDGAQAAAA==.',
Za='Zaraeliana:BAAANQAECgMJBAAAAA==.Zarastraza:BAAANQAECgUJBgAAAA==.',
Ze='Zephnor:BAAANQAECgIJBQAAAA==.',
Zh='Zhao:BAAANQADCgYIBgAAAA==.',
Zm='Zmona:BAAANQAECgQIBAAAAA==.',
Zu='Zulrok:BAAANQAECgUICQAAAA==.',
['Áb']='Ábsurd:BAAANQADCggICQABNQABCgIIAQADAAAAAA==.',
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
