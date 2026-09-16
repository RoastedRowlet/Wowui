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

local lookup = {'Druid-Restoration','Unknown-Unknown','Mage-Arcane','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Devastation','DemonHunter-Havoc','Druid-Balance','DemonHunter-Devourer','DemonHunter-Vengeance',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Absol:BAAANQAECgYIDgAAAA==.',
Ac='Achilles:BAAANQAECggIDQAAAA==.',
Ae='Aerís:BAAANQADCgIIAgAAAA==.',
Ah='Ahsokatano:BAAANQAECgQIBgAAAA==.',
Ai='Ailing:BAAANQADCgYIDAAAAA==.',
Ak='Akasha:BAAANQABCgIIBAAAAA==.Akos:BAAANQADCggIEAABNQAECgcIGAABACQNAA==.',
Al='Alzaeryan:BAAANQADCggICwAAAA==.',
Am='Amonet:BAAANQADCgYIDwAAAA==.',
An='Anamis:BAAANQAECgIIAwAAAA==.Angras:BAAANQAECgUIBwAAAA==.',
Ap='Aphalock:BAAANQAECgUICQAAAA==.',
Ar='Ariûs:BAAANQAECgIIAgAAAA==.Arlin:BAAANQADCgYIBgAAAA==.Arlorian:BAAANQAECgUIBwAAAA==.Arrenn:BAAANQAECgMIBAAAAA==.Arrowsmites:BAAANQAECgIIBAAAAA==.',
As='Askelad:BAAANQADCgUICgAAAA==.',
Au='Aubani:BAAANQAECgIIBAAAAA==.',
Ay='Ayperos:BAAANQAECgQICAAAAA==.',
Ba='Bakedpally:BAAANQAECgQIBgAAAA==.Bakedwarrior:BAAANQADCgIIAgAAAA==.Bandomar:BAAANQADCggIFQAAAA==.Baragnis:BAAANQAECgUIBQAAAA==.',
Be='Beavur:BAAANQAECgEIAQAAAA==.Beck:BAAANQAECgQIBQAAAA==.Bereth:BAAANQADCgYIDwAAAA==.Berreydingle:BAAANQADCggIEQAAAA==.',
Bi='Bigboii:BAAANQADCgYIBgAAAA==.Bigkitty:BAAANQAECgIIAgABNQAECgUICAACAAAAAA==.Bikinibrenda:BAAANQADCgYIBgAAAA==.',
Bl='Blackhuuf:BAAANQADCgUIBQAAAA==.Blitzedbust:BAAANQADCggIDQAAAA==.Bloodmender:BAAANQADCgYIBwABNQAECgQIBwACAAAAAA==.Bluesummer:BAAANQADCgcIFAABNQAECgMIBAACAAAAAA==.',
Bo='Bobeh:BAAANQADCggIFAABNQADCgEIAQACAAAAAA==.Bolts:BAAANQABCgEIAQAAAA==.Boomskittles:BAAANQABCgMIAwAAAA==.Borat:BAAANQAECgUIBwABNQADCgYICwACAAAAAA==.Borsam:BAAANQABCgQIBAAAAA==.',
Br='Brendameeks:BAAANQADCgQIBAAAAA==.Broadzinatl:BAAANQADCgUIBQABNQADCgYICgACAAAAAA==.Brom:BAAANQAECgEIAQAAAA==.',
['Bè']='Bètflèch:BAAANQADCgcIDgAAAA==.',
Ca='Cad:BAAANQADCgYIEAAAAA==.Calytrix:BAEANQAECgUICwAAAA==.Captnhammer:BAAANQADCgEIAQAAAA==.Carnelian:BAAANQADCgUIDAAAAA==.Castration:BAAANQADCgYICQAAAA==.',
Ce='Ceylan:BAAANQAECgIIBAAAAA==.',
Ch='Charsifood:BAAANQAECgQIBgAAAA==.Cheatpriest:BAAANQAECgUIDAAAAA==.Chepis:BAAANQADCgUICwAAAA==.Chesthyr:BAAANQADCgcIDgAAAA==.Chestoe:BAAANQAECgEIAQAAAA==.Chitchatted:BAAANQADCgIIAgAAAA==.',
Ci='Cindrethresh:BAAANQADCgMIAwAAAA==.',
Co='Cognition:BAAANQAECgQICQAAAA==.Coldvengance:BAAANQAECgMIBAAAAA==.',
Cr='Cranknstein:BAAANQADCggICAABNQADCggIEQACAAAAAA==.Crazh:BAAANQAECgIIAwAAAA==.Crazycalla:BAAANQADCgYICwAAAA==.Croven:BAAANQADCgUIBQAAAA==.',
Cu='Cuensour:BAAANQADCgcIDQAAAA==.Cutemenace:BAAANQADCgIIAgABNQAECgcIDQACAAAAAA==.',
Cy='Cymindel:BAAANQAECgUIDAAAAA==.',
Da='Dakotà:BAAANQAECgEIAQAAAA==.Darc:BAAANQADCggIDgAAAA==.Daredayo:BAAANQADCgIIAgAAAA==.Darklorising:BAAANQADCgYIBgAAAA==.',
De='Dejno:BAAANQAECgQICgAAAA==.Deleted:BAAANQADCgUIBQABNQAECgQIBwACAAAAAA==.Dethra:BAAANQAECgIIBAAAAA==.Dezign:BAABNQAECoEYAAIDAAkJEiPBDQB3AwADAAkJEiPBDQB3AwAAAA==.',
Do='Dolgorukov:BAAANQAECgIIAwAAAA==.Dologony:BAAANQAECgIIAgAAAA==.',
Dr='Draccosa:BAAANQADCgIIAgAAAA==.Dragonmage:BAAANQAECgIIAgAAAA==.Drakma:BAAANQAECgEIAQAAAA==.Drastio:BAAANQADCgMIAwAAAA==.Drikken:BAAANQAECgUIDAAAAA==.Drmaker:BAAANQAECgEIAQAAAA==.Druj:BAEANQADCgcIBwABNQAECgUICwACAAAAAA==.',
Du='Durasan:BAAANQADCgMIAwAAAA==.',
['Dö']='Dötdötdead:BAAANQADCgMIBAAAAA==.',
Ef='Effindin:BAAANQADCgYIBgAAAA==.Effinsick:BAAANQADCggIFwAAAA==.',
Ei='Eisheth:BAAANQADCgYICwAAAA==.',
El='Ellysiaa:BAAANQADCggIFwAAAA==.',
Em='Emmakyn:BAAANQAECgEIAQAAAA==.',
En='Endjinns:BAAANQADCggICAAAAA==.Enyxea:BAAANQADCgYIBgAAAA==.',
Er='Erodin:BAAANQADCgYIBgAAAA==.',
Es='Esman:BAAANQADCgMIAwAAAA==.',
Ey='Eyedontknow:BAAANQADCggIGgAAAA==.',
Ez='Ezzka:BAAANQAECgQIBwABNQAECgUICgACAAAAAA==.',
Fa='Faceless:BAAANQAECgYIBQAAAA==.Failroots:BAAANQAECgIIAgAAAA==.False:BAAANQADCgcIDQAAAA==.Farzix:BAAANQAECgMIAwAAAA==.Façade:BAAANQAECgYIDQAAAA==.',
Fe='Fefifabrizio:BAAANQAECgEIAQAAAA==.Felix:BAAANQADCgYIBgAAAA==.Felraena:BAAANQADCgIIAgAAAA==.',
Fi='Finnagas:BAAANQAECgEIAQAAAA==.Finnw:BAAANQABCgcICgAAAA==.Firelite:BAAANQAECgEIAQAAAA==.',
Fl='Flairadin:BAAANQAECgMIBAAAAA==.Flexo:BAAANQAECgEIAQAAAA==.',
Fo='Fookmii:BAAANQADCgUIBgAAAA==.',
Fr='Frogfist:BAAANQAECgMIAwAAAA==.Frowdawn:BAAANQAECgIIAwAAAA==.',
Fy='Fyf:BAAANQADCggIBwABNQADCggIEQACAAAAAA==.',
Ga='Garythenpc:BAAANQADCgYIDwAAAA==.',
Ge='Genericeric:BAAANQADCgcICAAAAA==.',
Gi='Gidgett:BAAANQADCgcIDQAAAA==.',
Gl='Glacialkitty:BAAANQAECgIIBAAAAA==.Glizzygoblin:BAAANQADCgQIBAAAAA==.',
Go='Gobibug:BAAANQADCgIIAgAAAA==.Googoobler:BAAANQADCggIEgAAAA==.Goudanight:BAAANQADCgIIAgABNQAECgUICAACAAAAAA==.Goudatime:BAAANQADCggIGgABNQAECgUICAACAAAAAA==.',
Gr='Greenknight:BAAANQADCggICQAAAA==.Greenmagus:BAAANQAECgEIAQAAAA==.Grenadon:BAAANQADCgYIDgAAAA==.Greyni:BAAANQABCgEIAQAAAA==.',
Ha='Hakibalboa:BAAANQAECgYIDgAAAA==.Hakitua:BAAANQADCgYIBgAAAA==.Harick:BAAANQADCgQIBAAAAA==.Hazard:BAAANQAECgMIBAAAAA==.',
He='Heis:BAAANQADCgYIBgAAAA==.Hellboii:BAAANQAECgQIBgAAAA==.Heyitsrat:BAAANQAECgIIAwAAAA==.',
Ho='Holo:BAABNQAECoEYAAMEAAkJTyNBIQBoAgAEAAYJcCNBIQBoAgAFAAkJHw9IMAD5AQAAAA==.Housemom:BAAANQADCggIFQAAAA==.',
Hu='Huntem:BAAANQADCgMIAgAAAA==.',
Ic='Icculus:BAAANQADCggIFQAAAA==.',
Im='Iminyou:BAAANQAECgUIBwAAAA==.',
Io='Iolz:BAAANQABCgQIBgABNQAECgYIDwACAAAAAA==.',
Ja='Jaenei:BAAANQADCggIDAAAAA==.Janet:BAAANQADCgYIBgABNQAECgUICwACAAAAAA==.',
Je='Jeeb:BAAANQAECgQICQAAAA==.',
Ji='Jinxta:BAAANQAECgIIAgAAAA==.',
Jo='Joansnow:BAAANQADCggICgAAAA==.Joeeo:BAAANQAECgUICQAAAA==.',
Ju='July:BAAANQADCggIDAAAAA==.',
Ka='Kaimargonar:BAAANQAECgEIAQAAAA==.Kaitoi:BAAANQADCggIGQAAAA==.Kamakizeg:BAAANQAECgIIAgAAAA==.Kamayla:BAAANQADCgYIBgAAAA==.Kateria:BAAANQADCgUIBQABNQAECgUICgACAAAAAA==.Katimalice:BAAANQADCgQICQAAAA==.',
Ke='Keathry:BAAANQADCgMIAwAAAA==.Keyzeus:BAAANQADCggIFQAAAA==.',
Kh='Khui:BAABNQAECoEcAAMGAAkJCiODAQCCAwAGAAkJCiODAQCCAwAHAAMJpyEsIwARAQAAAA==.',
Ki='Killatu:BAAANQABCgcICQAAAA==.Killerdeath:BAAANQADCgEIAQAAAA==.',
Kn='Knìghtmàrè:BAABNQAECoEbAAMIAAkJ1yCLBQB5AwAIAAkJ1yCLBQB5AwAJAAIJ1hJtbAB7AAAAAA==.',
Ko='Koltharaz:BAABNQAECoEZAAIKAAgJ1hm7BwCjAgAKAAgJ1hm7BwCjAgAAAA==.Korloff:BAAANQADCggIEwABNQAECgEIAQACAAAAAQ==.Kozan:BAAANQAECgEIAQAAAQ==.',
Kr='Krazsz:BAAANQADCgQIBAAAAA==.Krazylock:BAAANQAECgEIAQAAAA==.',
Ku='Kumah:BAAANQABCgEIAQAAAA==.Kungfuupanda:BAAANQAECgQIBwAAAA==.',
La='Lateralus:BAAANQAECgcIEwAAAA==.Latt:BAAANQAECgEIAQABNQAECgcIEwACAAAAAA==.Lawluss:BAAANQAECgEIAQAAAA==.',
Le='Legacyshot:BAAANQADCggIDwAAAQ==.Lelwani:BAAANQADCgEIAQAAAA==.',
Li='Lightguard:BAAANQADCgcIAwAAAA==.Lighthouse:BAAANQAECgUIDAAAAA==.Lileth:BAAANQADCgcIBwAAAA==.',
Lo='Lolhahabaha:BAAANQADCggIEgAAAA==.Lonê:BAAANQADCgEIAQAAAA==.Loopie:BAAANQADCgMIAwAAAA==.Lorax:BAAANQAECgYICAAAAA==.',
Lu='Luckÿ:BAAANQADCggIDQAAAA==.Luminah:BAAANQABCgIIAQAAAA==.',
Ly='Lypally:BAAANQAECgUICQAAAA==.',
['Lï']='Lïllïth:BAAANQAECgIIAwAAAA==.Lïly:BAAANQADCgQIBAABNQADCggIDwACAAAAAA==.',
['Ló']='Lóla:BAAANQAECgQIBgAAAA==.',
Ma='Madeah:BAAANQAFFAEIAQAAAA==.Madforge:BAAANQAECgUIBwAAAA==.Magegrizz:BAAANQAECgQICAAAAA==.Mahimahi:BAAANQADCgYICgAAAA==.Manahole:BAAANQAECgYICwAAAA==.Mariacuras:BAAANQAECgQIBQAAAA==.Marijwana:BAAANQAECgMIAwAAAA==.Martis:BAAANQAECgMIBAAAAA==.Marynne:BAAANQAECgIIAgAAAA==.Mazuko:BAAANQAECgMIAwAAAA==.',
Me='Mecandry:BAAANQAECgQIBgAAAA==.Mecks:BAAANQADCgEIAQAAAA==.Meepe:BAAANQADCgcIDQAAAA==.Melivant:BAAANQAECgEIAQAAAA==.Meranda:BAAANQAECgUICAAAAA==.Merriklade:BAAANQAECgMIBAAAAA==.Merrikoid:BAAANQADCggIGgAAAA==.',
Mi='Mico:BAAANQADCgYICwAAAA==.',
Mo='Morbidstyle:BAAANQADCgcIDAABNQAECgQIDwACAAAAAA==.Morgoth:BAAANQAECgUIDAAAAA==.Morthos:BAAANQADCgcICgAAAA==.Mosry:BAAANQAECgUICQAAAA==.',
My='Myora:BAEANQADCgIIAgABNQAECgUICwACAAAAAA==.Mythundirus:BAAANQAECgIIAgAAAA==.',
['Mà']='Màrli:BAAANQAECgQICAAAAA==.',
['Mâ']='Mâgs:BAAANQAECgIIBAAAAA==.',
Na='Nakasid:BAAANQAECgcICgAAAA==.Nashoba:BAAANQADCgYICwAAAA==.Natooka:BAAANQADCgUIBQAAAA==.',
Ne='Nein:BAAANQAECgEIAQAAAA==.Neins:BAAANQADCgYIEAABNQAECgEIAQACAAAAAA==.Nevaehstar:BAAANQAECgUIEQAAAA==.',
Ni='Nijun:BAEANQAECgIIBAAAAA==.Nik:BAAANQADCggIGwAAAA==.Nikolia:BAAANQAECgMIBAAAAA==.Nini:BAAANQADCggIEAAAAA==.Ninx:BAAANQADCgUICQAAAA==.',
No='Noivana:BAAANQABCgEIAQABNQAECgkJIAALAH4gAA==.',
Ny='Nystel:BAAANQADCgEIAQAAAA==.',
Ol='Ollichi:BAAANQADCgIIAgAAAA==.',
Or='Ornn:BAAANQAECgQIBAABNQAECgYIDgACAAAAAA==.',
Os='Osoroshi:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.',
Pa='Paladrak:BAAANQADCgIIAgAAAA==.Patronous:BAAANQADCgYIDAAAAA==.',
Ph='Phenol:BAAANQABCgIIAgAAAA==.',
Po='Polog:BAAANQAECgEIAQABNQAECgQIBwACAAAAAA==.Porkchoplust:BAAANQADCgUIBQAAAA==.Porkribs:BAAANQAECgQICAAAAA==.',
Pu='Puca:BAAANQADCgYIDwAAAA==.Pumdmuc:BAAANQAECgIIAgABNQAECgYICwACAAAAAA==.',
Qu='Quikglaives:BAAANQADCggICAAAAA==.Quille:BAAANQAECgYIDQAAAA==.',
Ra='Ragretts:BAAANQAECgEIAQAAAA==.Rahhem:BAAANQADCgYIBgAAAA==.Ranmo:BAAANQAECgcIDQAAAA==.Ratkol:BAAANQABCgIIAgAAAA==.Raysdknight:BAAANQADCgIIBQAAAA==.',
Re='Redrek:BAAANQADCgYIEAAAAA==.Redwinter:BAAANQAECgMIBAAAAA==.Reikisong:BAAANQADCgEIAQAAAA==.Remmie:BAAANQADCgUIBwAAAA==.',
Rh='Rhagurion:BAAANQAECggIDgAAAA==.',
Ri='Riqua:BAAANQADCggIFAAAAA==.',
Ro='Rockmonsta:BAAANQADCgYICAAAAA==.Roxies:BAAANQADCgQIBAAAAA==.',
Rp='Rpg:BAAANQAECgUIDQAAAA==.',
Sa='Saeti:BAAANQAECggIEQAAAA==.Sapplesauce:BAAANQADCggICQAAAA==.',
Se='Seethrowwar:BAAANQAECgcIEAAAAA==.Senbit:BAAANQAECgEIAQAAAA==.Serenìty:BAAANQAECgIIAgAAAA==.Seresin:BAABNQAECoEYAAMBAAcJJA1SGQCNAQABAAcJJA1SGQCNAQAMAAUJNwjvTADkAAAAAA==.',
Sh='Shadý:BAAANQAECgIIAwAAAA==.Shamanoodles:BAAANQADCggIFAABNQAECgQIBwACAAAAAA==.Shortwarrior:BAAANQAECgIIAwAAAA==.',
Si='Sidraya:BAAANQADCgcIEwAAAA==.Silent:BAAANQAECgYIDwAAAA==.Silverserqet:BAAANQADCggIGgAAAA==.Sinbit:BAAANQADCggICQAAAA==.',
So='Sooki:BAAANQAECgMIBQAAAA==.Sophie:BAAANQAECgQIBAAAAA==.Soulber:BAAANQADCggIDAAAAA==.',
Ss='Ssenbit:BAAANQABCgUIBQAAAA==.',
St='Sternhoof:BAAANQABCgMIAwAAAA==.Stigma:BAAANQADCggIFQAAAA==.Stylos:BAAANQADCggIEAAAAA==.',
Su='Summersong:BAAANQADCgQIBAAAAA==.',
Sw='Swowtitbang:BAAANQADCggIDQAAAA==.',
Te='Tegbolt:BAAANQAECgYICwAAAA==.Tekko:BAAANQAECgQICAAAAA==.',
Th='Theholymatt:BAAANQAECgUIDAAAAA==.Thendari:BAAANQAECgQICgAAAA==.Theodus:BAAANQAECgYICgAAAA==.Therayen:BAAANQADCgYICwAAAA==.',
Ti='Tiferis:BAAANQAECgcIEgAAAA==.Tigerclawss:BAAANQADCgQIBAAAAA==.Tislam:BAAANQADCgYIBgAAAA==.',
To='Tobiquer:BAAANQAECgQICAAAAA==.Torolf:BAAANQADCgYICgAAAA==.',
Tr='Traydra:BAAANQADCgUIBwAAAA==.Trinbug:BAAANQADCgEIAQAAAA==.Troglodyte:BAAANQAECgcICwAAAA==.',
Ts='Tsonokwabain:BAAANQAECgIIAgAAAA==.Tsunami:BAAANQADCgMIAwAAAA==.',
Tw='Twistdog:BAAANQABCgQIBgAAAA==.',
Ty='Tye:BAAANQAECgMIAwAAAA==.Tyranastrasz:BAAANQAECgUIDAAAAA==.Tyye:BAAANQAECgQIBAAAAA==.',
['Tâ']='Tâjik:BAAANQAECgQIBwAAAA==.',
Ul='Ulquiorra:BAABNQAECoEVAAMNAAkJyhVMFwA1AgANAAcJlBhMFwA1AgAOAAMJxwqBEACZAAAAAA==.',
Ut='Uthers:BAAANQADCgYIAgAAAA==.',
Va='Vaethund:BAAANQADCgYIBgAAAA==.Valgavoth:BAAANQAECgQIBwAAAA==.',
Ve='Velara:BAAANQADCgYIBwAAAA==.Velinna:BAAANQADCgUIBwABNQAECgEIAQACAAAAAA==.',
Vi='Viriex:BAAANQADCgIIAgAAAA==.Vitoria:BAAANQADCgcIDAAAAA==.',
Vo='Voidlighter:BAAANQAECgYIDQAAAA==.Volundr:BAAANQAECgMIBAAAAA==.Vonvaughan:BAAANQADCgYICgAAAA==.',
Vy='Vynel:BAAANQADCgMIAwABNQAECgUIEQACAAAAAA==.Vynirion:BAAANQAECgEIAQAAAA==.',
Wa='Wargtar:BAAANQAECgQIBQAAAA==.',
We='Weabe:BAAANQADCggICAAAAA==.',
Wh='Whitespring:BAAANQADCgQIBAABNQAECgMIBAACAAAAAA==.',
Wy='Wyrdhoof:BAAANQADCgcIEwAAAA==.Wyrdo:BAAANQADCgYIBgAAAA==.',
['Wù']='Wùsthof:BAAANQAECgYIDAAAAA==.',
Xa='Xandrios:BAAANQAECgEIAQAAAA==.',
Xi='Xiae:BAAANQAECgMIBAAAAA==.',
Ya='Yasuke:BAAANQADCgUIBQAAAA==.',
Ye='Yet:BAAANQADCgYICwAAAA==.',
Yi='Yiffweaver:BAAANQAECgEIAQAAAA==.',
Yo='Yokochan:BAAANQABCgIIAgAAAA==.Yokoriazen:BAAANQAECgYIDwAAAA==.',
Za='Zaraeliana:BAAANQAECgEIAQAAAA==.Zarastraza:BAAANQAECgEIAQAAAA==.',
Ze='Zephnor:BAAANQAECgIIAwAAAA==.',
Zh='Zhao:BAAANQADCgYIBgAAAA==.',
Zm='Zmona:BAAANQAECgQIBAAAAA==.',
Zu='Zulrok:BAAANQAECgIIBAAAAA==.',
['Áb']='Ábsurd:BAAANQADCggICQABNQABCgIIAQACAAAAAA==.',
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
