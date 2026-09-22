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

local lookup = {'Mage-Arcane','Priest-Shadow','Priest-Holy','Unknown-Unknown','Paladin-Holy','Monk-Windwalker','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Druid-Restoration','Evoker-Devastation',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abàddón:BAAANQADCgYIDAAAAA==.',
Ac='Acidburn:BAAANQADCgYICgAAAA==.',
Al='Alluna:BAAANQADCgUJDgAAAA==.Alorillan:BAAANQADCgcIDAAAAA==.Altabrew:BAAANQADCgMIAwAAAA==.Altair:BAAANQAECgIIAgAAAA==.',
An='Anker:BAAANQAECgEIAQABNQAECgkJHwABABkeAA==.Anomalien:BAAANQAECgMIAwAAAA==.',
Ap='Apocalyspe:BAAANQAECgcIBwAAAA==.Appless:BAABNQAECoEXAAMCAAgKIxMYIAC+AQACAAcK2RAYIAC+AQADAAQKzQMthwDDAAAAAA==.',
Ar='Aridella:BAAANQAECgYIDgAAAA==.',
Az='Azusie:BAAANQAECgUICwAAAA==.',
Ba='Bablepopye:BAAANQAECgMIAwAAAA==.Baddate:BAAANQADCggIEwAAAA==.Baddragøn:BAAANQAECgUIBgAAAA==.Balthaas:BAAANQAECgQICAAAAA==.Bangen:BAAANQAECgEIAQAAAA==.Baulters:BAAANQADCgYIBgAAAA==.Baylor:BAAANQADCgUIBQAAAA==.',
Be='Beenn:BAAANQADCgcJDAAAAA==.Belael:BAAANQADCgcIBwAAAA==.Benrent:BAAANQADCgEIAQABNQADCgcJDAAEAAAAAA==.',
Bi='Biinks:BAAANQADCggJEQAAAA==.Billywitchdr:BAAANQAECgYJDAAAAA==.Bisharp:BAAANQADCggICAABNQAECggIEgAEAAAAAA==.',
Bl='Blazingelf:BAAANQADCgMIAwAAAA==.Blindedbý:BAAANQABCgQIBAAAAA==.Bluetoykawi:BAAANQAECgcIEwAAAA==.',
Bo='Bonedelivery:BAAANQABCgIIAgAAAA==.',
Br='Breloom:BAAANQAECgYIBgABNQAECggIEgAEAAAAAA==.',
Bu='Bulkathos:BAAANQADCgYJCwABNQAECgQJBAAEAAAAAA==.',
['Bé']='Béorñ:BAAANQADCggIEAABNQAECgcJBgAEAAAAAA==.',
Ch='Charita:BAEANQAECgYJBgABNQAECgcJEgAEAAAAAA==.Charming:BAEANQAECgcJEgAAAA==.',
Cl='Clark:BAAANQADCgEIAQAAAA==.Clouds:BAAANQADCggICAABNQAECgUIBgAEAAAAAA==.',
Co='Coffeecat:BAAANQADCgMJAwABNQADCgYICAAEAAAAAA==.Contrlurself:BAAANQADCgQIBAABNQAECgYJDgAEAAAAAA==.Cowret:BAABNQAECoEYAAIFAAgKsyCTEQD+AgAFAAgKsyCTEQD+AgAAAA==.',
Cr='Crowleyy:BAAANQADCgUIBQAAAA==.',
Da='Dademurphy:BAAANQADCgIIAgAAAA==.Darc:BAAANQADCgcIBwAAAA==.Darkfoxdemon:BAAANQAECgYJDgAAAA==.Darkjager:BAAANQADCgcIBwAAAA==.Darkstaff:BAAANQADCgMJAwAAAA==.Darkways:BAAANQADCgYIBgAAAA==.Darlah:BAAANQADCggIEAAAAA==.Dayyva:BAAANQAECgQICAAAAA==.',
De='Deadcobra:BAAANQADCgMIBQAAAA==.Deangilberry:BAAANQADCgQICQAAAA==.Delindeyn:BAAANQADCgYIDAAAAA==.Deltria:BAAANQADCgcJDAAAAA==.Demonrot:BAAANQADCggIFgAAAA==.Deviltank:BAAANQADCgQJBAAAAA==.',
Di='Diaboliq:BAAANQADCggIIAAAAA==.Dilea:BAAANQAECgEIAQAAAA==.',
Dk='Dkon:BAAANQAECgYJDgAAAA==.',
Do='Doppler:BAAANQAECgMIAwAAAA==.',
Dr='Dracomyst:BAAANQADCggIAgAAAA==.Driver:BAEANQAECggICgAAAA==.Drruz:BAAANQADCgIIAgAAAA==.',
Du='Dumbledorr:BAAANQAECgIIAgAAAQ==.Durzoe:BAAANQAECgUIBwAAAA==.',
Dv='Dvsmage:BAAANQADCgYJBgABNQAECgEIAQAEAAAAAA==.',
Dw='Dwod:BAAANQAECgcIDAAAAA==.',
['Dí']='Díscø:BAEANQAECgcIDgAAAA==.',
Er='Ershulie:BAAANQABCggJHwAAAA==.',
Ew='Ewt:BAAANQAECgYJDgAAAA==.',
Fe='Felhound:BAAANQADCgEJAQAAAA==.Felussi:BAAANQAECgYJCwAAAA==.',
Fi='Finnster:BAAANQAECgYJEAAAAA==.Fionna:BAAANQADCgQIBAAAAA==.',
Fl='Flameon:BAAANQABCgcICAAAAA==.Flarixi:BAAANQADCgMIAwAAAA==.Fleurminator:BAAANQAECgQIBQAAAA==.',
Fr='Fractor:BAAANQADCgYICwAAAA==.Frieia:BAAANQADCgYJDgAAAA==.Frostface:BAAANQADCgcICwAAAA==.',
Fu='Fubuki:BAACNQAFFIEFAAIGAAMKnwoSBgDbAAAGAAMKnwoSBgDbAAA1AAQKgSIAAgYACQrvHy0KAOQCAAYACQrvHy0KAOQCAAAA.',
Ga='Galarína:BAAANQAECgYJDAAAAA==.Gallitha:BAAANQADCgUIBQAAAA==.Gamewarden:BAAANQADCgYIBgABNQAECgUIDQAEAAAAAA==.Gandora:BAAANQAECgUIDQAAAA==.Gauge:BAAANQAECgcICwAAAA==.',
Ge='Getoffme:BAAANQAECgMIAwAAAA==.',
Gk='Gkmc:BAAANQAECgYJBwABNQAFFAcJDwABACEhAA==.',
Go='Gobbomode:BAAANQADCgYIBgAAAA==.Gorbino:BAABNQAECoEYAAIHAAgKWyASBwDjAgAHAAgKWyASBwDjAgAAAA==.',
Gr='Greasemunkey:BAAANQAECgQICgAAAA==.Gretchaen:BAAANQAECgEJAgAAAA==.Griiv:BAABNQAECoEgAAIIAAgKFCZmDgBhAwAIAAgKFCZmDgBhAwAAAA==.Grislydemon:BAAANQADCggICAAAAA==.Grislydoom:BAAANQADCgEIAQAAAA==.Grislyshock:BAAANQAECgUIDwAAAA==.',
Ha='Hakunamatata:BAAANQADCgYIBgAAAA==.Hamburger:BAAANQAECgUIBwAAAA==.Hammerhard:BAAANQADCgIIAgAAAA==.Harcones:BAAANQADCgMJAwAAAA==.',
He='Heights:BAAANQADCgMIAwABNQAECgQIBgAEAAAAAA==.Heliosan:BAAANQAECgUIDAAAAA==.Hemoblast:BAAANQADCgIIAgAAAA==.Hemolight:BAAANQADCgYIDAAAAA==.',
Hr='Hrshoo:BAAANQAECggICwAAAA==.',
['Hä']='Hädês:BAAANQADCggJAQAAAA==.',
Je='Jeannaah:BAAANQAECgUJBgABNQAECgEIAQAEAAAAAA==.Jekyl:BAAANQADCgMIAwAAAA==.Jekyll:BAAANQADCgUIBQAAAA==.',
Ju='Judgment:BAAANQABCgEJAQAAAA==.',
['Já']='Jáckyboy:BAAANQAECgUIEQAAAA==.',
Ka='Kalestra:BAAANQAECgYJCgAAAA==.Kayelalynn:BAAANQAECgYJDgAAAA==.',
Kd='Kd:BAAANQADCgUJBQAAAA==.',
Ke='Keeghor:BAAANQAECgcJCwABNQAECggIIAAIABQmAA==.Kendô:BAAANQADCgEIAQABNQAECgMJAwAEAAAAAA==.Keyahi:BAAANQAFFAEIAQABNQAECgEIAQAEAAAAAA==.',
Kh='Khaean:BAAANQAECgQJCgAAAA==.',
Ki='Kickandpunch:BAAANQAECgcIEAAAAA==.Kilan:BAAANQAECgEIAQAAAA==.Kimuraakid:BAAANQAECgEIAQAAAA==.',
Ko='Korladin:BAAANQADCgYICQAAAA==.',
Kr='Krutree:BAAANQAECgQIBgAAAA==.',
Ku='Kutbrezbek:BAAANQABCgYICgAAAA==.',
Ky='Kyleata:BAAANQAECgUIDQAAAA==.Kyokin:BAABNQAECoEVAAIIAAkKDxbMMQCQAgAIAAkKDxbMMQCQAgAAAA==.Kyzula:BAAANQAECgQICgAAAA==.',
['Kê']='Kêndo:BAAANQADCgEIAQABNQAECgMJAwAEAAAAAA==.',
La='Lagrandè:BAAANQAECgYJDAAAAA==.',
Li='Lilylocks:BAAANQAECgQJBAAAAA==.Littlelo:BAAANQADCgQIBAAAAA==.',
Ly='Lyanah:BAAANQAECgYIDwAAAA==.Lycota:BAAANQADCggJBwAAAA==.Lyriell:BAAANQADCgYIBgAAAA==.',
Ma='Maelius:BAAANQADCgQIBAABNQAECgYJDgAEAAAAAA==.Maggrus:BAAANQABCgYIDAAAAA==.Malical:BAAANQADCgEIAQAAAA==.Manshöön:BAAANQADCgQIBAABNQADCggIEAAEAAAAAA==.Matheney:BAAANQAECgUIBgABNQAFFAYJDQAJAAwWAA==.Mattlock:BAAANQAECgUICwAAAA==.Maverick:BAAANQABCgUICQAAAA==.',
Mc='Mctubby:BAAANQADCgYJCwAAAA==.',
Md='Mdead:BAAANQABCgcICAAAAA==.',
Me='Meigz:BAAANQADCgcJBwAAAA==.Melinda:BAAANQAECgQJCAAAAA==.Mewtwo:BAAANQAECgMIAwAAAA==.',
Mi='Milenzha:BAAANQADCgIJBAAAAA==.Misaoh:BAAANQADCgcJEQAAAA==.',
Mo='Moonreína:BAAANQAECgEIAgAAAA==.Moons:BAAANQADCgYIBgABNQAECgkJLgAJAKYkAA==.Moontann:BAAANQADCggICgAAAA==.Moreia:BAAANQADCgMIAwAAAA==.Mousse:BAAANQAECgEJAQAAAA==.',
My='Mysharona:BAAANQADCgYIBgAAAA==.',
Mz='Mzbiscuit:BAAANQADCgYIEQAAAA==.',
Na='Narberal:BAAANQADCggIEgABNQAECgcICQAEAAAAAA==.Nasene:BAAANQAECgUICAAAAA==.Nataltharion:BAAANQADCgIIAgAAAA==.Natstryker:BAAANQAECgUJDQAAAA==.Naturemyth:BAAANQADCgYIBgAAAA==.',
Ne='Necromyst:BAAANQADCggIAQAAAA==.',
No='Noctyra:BAAANQADCgYJDAAAAA==.',
Or='Organa:BAAANQAECgEJAQAAAA==.',
Pa='Palarina:BAAANQAECgQJBAABNQAECgYJDAAEAAAAAA==.Palyomie:BAAANQAECgYIDgAAAA==.',
Ph='Pho:BAAANQAECgUIDQAAAA==.',
Pl='Playwityou:BAAANQADCgcIDAAAAA==.Plugley:BAAANQAECgUIBgAAAA==.',
Pu='Pumpkins:BAAANQAECgYIBgAAAA==.',
['Pë']='Përdü:BAAANQADCgcJDAAAAA==.',
Ra='Rakunn:BAAANQADCggIGQABNQAECgQJEgAEAAAAAA==.Ratapew:BAAANQADCgYJBwAAAA==.Ratheen:BAAANQABCgcJDwAAAA==.Raytar:BAAANQAECgMIBQAAAA==.',
Re='Renn:BAAANQAECgQICAAAAA==.',
Ri='Riltonge:BAAANQAECgEIAgAAAA==.',
Ro='Roachdirt:BAAANQAECgUJDgAAAA==.Robean:BAAANQADCgQJBAAAAA==.Roxoxoxanne:BAAANQADCgcICgAAAA==.',
Ru='Rustybray:BAAANQAECgUICgAAAA==.',
Sa='Sageghost:BAAANQABCggIDAAAAA==.Sangol:BAAANQADCgIIAgAAAA==.Sarabi:BAAANQAECgEJAQAAAA==.Saralina:BAAANQAECgIJAwABNQAECgcIHgAFANMiAA==.',
Sc='Schnee:BAAANQAECgUIBwAAAA==.Schutzhund:BAAANQADCgUIBgAAAA==.',
Se='Sekha:BAAANQADCgQIBAABNQAECgYIDQAEAAAAAA==.Sena:BAAANQADCgYIBgAAAA==.Serelia:BAAANQADCgYIBgAAAA==.',
Sh='Shadoweave:BAAANQAECgEIAQABNQAFFAQIBgAKAEEIAA==.Shalalia:BAAANQADCgcIEAAAAA==.Shambean:BAAANQAECgEIAQAAAA==.Shavox:BAAANQABCgUICQAAAA==.Shieldster:BAAANQAECgcICQAAAA==.Shnizelnazee:BAAANQAECgUJCQAAAA==.',
Sm='Smokeyb:BAAANQAECgYIEAAAAA==.',
Sn='Snorehees:BAAANQAECgQIBwAAAA==.',
So='Solaeris:BAAANQADCggIDQAAAA==.Songstar:BAAANQAECgYJDgAAAA==.Soullraven:BAAANQADCgUJDgAAAA==.',
Sp='Spaceboat:BAAANQAECgUJDQAAAA==.Spy:BAAANQADCgQIBAAAAA==.Spàz:BAAANQABCgMIAgAAAA==.',
St='Staavon:BAAANQADCggIIAAAAA==.Stalvis:BAAANQABCgIIAgAAAA==.Starblaze:BAAANQAECgEIAgAAAA==.',
Su='Sugarhoof:BAAANQADCgUJDgAAAA==.Sugarlick:BAAANQADCggIHwAAAA==.Sugarpop:BAABNQAECoEeAAIFAAcK0yLMGQDCAgAFAAcK0yLMGQDCAgAAAA==.Suplazindh:BAAANQAECgMIAwABNQAFFAcJEwALALsgAA==.',
Sw='Swiftstrike:BAAANQADCggJBQAAAA==.',
Sy='Syrebriel:BAAANQADCggIEAAAAA==.',
Ta='Taediah:BAAANQADCgUIBQAAAA==.Tanjiro:BAAANQADCgMJBAAAAA==.Tanthanalas:BAAANQADCgQIBAAAAA==.',
Tg='Tgoat:BAAANQADCgEIAQAAAA==.',
Th='Theoutcast:BAAANQADCgIJAgAAAA==.',
Ti='Timeless:BAAANQAECgQJBAAAAA==.Tinymeatgang:BAAANQADCgUIBwAAAA==.',
To='Toetagger:BAAANQAECgUJBwAAAA==.Tonymaster:BAAANQAECgQIBgAAAA==.Toucannon:BAAANQAECggIEgAAAA==.',
Tr='Trashiepanda:BAAANQADCgQIBQAAAA==.Treealia:BAAANQABCgIIAgAAAA==.',
Ty='Tyrrial:BAAANQADCgYIEAAAAA==.Tyshus:BAAANQAECgIJAgAAAA==.',
Ua='Ualmar:BAAANQAECgIJAgAAAA==.',
Ut='Uthgardt:BAAANQAECgUJBgAAAA==.',
Va='Valarion:BAAANQAECgUJDQAAAA==.Validimus:BAAANQADCgEIAQAAAA==.Valorían:BAAANQAECgUJDAAAAA==.Varthayn:BAAANQAECgUICwAAAA==.Varue:BAAANQAECggJBwAAAA==.',
Ve='Verksquirt:BAAANQAECgUJBQAAAA==.Verra:BAAANQAECgEIAQAAAA==.Vestaria:BAAANQADCgQIBAAAAA==.',
Vo='Volbain:BAAANQAECgEIAgAAAA==.',
Vu='Vulpsinculta:BAAANQAECgIJAQAAAA==.',
['Vï']='Vïrùs:BAAANQAECgUIDwAAAA==.',
Wa='Warboar:BAAANQADCgIIAgAAAA==.Wasntmee:BAAANQADCgYJBgABNQADCgYIEQAEAAAAAA==.',
We='Weaz:BAAANQADCggIEgAAAA==.',
Wi='Wichita:BAAANQAECgUICwAAAA==.',
Wt='Wtfguën:BAAANQAECgEJAQAAAA==.',
Xb='Xbean:BAAANQAECgEJAQAAAA==.',
Xo='Xorman:BAAANQADCgcJEAAAAA==.',
Xy='Xyo:BAAANQAECgcJCQAAAA==.',
Xz='Xzairi:BAAANQAECgYIDQAAAA==.',
Zi='Zinora:BAAANQADCgcICgAAAA==.Ziyue:BAAANQAECgMIBgAAAA==.',
Zn='Zn:BAAANQAECgYJEQAAAA==.',
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
