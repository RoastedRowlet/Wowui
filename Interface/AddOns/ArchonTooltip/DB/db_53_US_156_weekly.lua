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

local lookup = {'Mage-Arcane','Unknown-Unknown','Monk-Windwalker','Paladin-Retribution','Hunter-BeastMastery',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abàddón:BAAANQADCgYIBgAAAA==.',
Ac='Acidburn:BAAANQADCgYICgAAAA==.',
Al='Alluna:BAAANQADCgQICQAAAA==.Alorillan:BAAANQADCgUIBgAAAA==.Altabrew:BAAANQADCgMIAwAAAA==.Altair:BAAANQAECgEIAQAAAA==.',
An='Anker:BAAANQAECgEIAQABNQAECgkJGAABAGgcAA==.Anomalien:BAAANQAECgMIAwAAAA==.',
Ap='Appless:BAAANQAECgYIDQAAAA==.',
Ar='Aridella:BAAANQAECgYIDgAAAA==.',
Az='Azusie:BAAANQAECgQIBgAAAA==.',
Ba='Baddate:BAAANQADCgYICwAAAA==.Baddragøn:BAAANQAECgEIAQAAAA==.Balthaas:BAAANQAECgQICAAAAA==.Bangen:BAAANQAECgEIAQAAAA==.Baulters:BAAANQADCgYIBgAAAA==.Baylor:BAAANQADCgUIBQAAAA==.',
Be='Beenn:BAAANQADCgYICQAAAA==.Belael:BAAANQADCgcIBwAAAA==.Benrent:BAAANQADCgEIAQABNQADCgYICQACAAAAAA==.',
Bi='Biinks:BAAANQADCgcIEAAAAA==.Billywitchdr:BAAANQAECgMIBgAAAA==.Bisharp:BAAANQADCggICAABNQAECggIEAACAAAAAA==.',
Bl='Blazingelf:BAAANQADCgMIAwAAAA==.Blindedbý:BAAANQABCgQIBAAAAA==.Bluetoykawi:BAAANQAECgYIDAAAAA==.',
Bo='Bonedelivery:BAAANQABCgIIAgAAAA==.',
Br='Breloom:BAAANQAECgYIBgABNQAECggIEAACAAAAAA==.',
Bu='Bulkathos:BAAANQADCgUIBgABNQADCggIHAACAAAAAA==.',
['Bé']='Béorñ:BAAANQADCggIEAAAAA==.',
Ch='Charita:BAEANQAECgEIAQABNQAECgYIEAACAAAAAA==.Charming:BAEANQAECgYIEAAAAA==.',
Cl='Clark:BAAANQADCgEIAQAAAA==.Clouds:BAAANQADCggICAAAAA==.',
Co='Contrlurself:BAAANQADCgQIBAABNQAECgQICAACAAAAAA==.Cowret:BAAANQAECgYIDwAAAA==.',
Cr='Crowleyy:BAAANQADCgUIBQAAAA==.',
Da='Dademurphy:BAAANQADCgIIAgAAAA==.Darc:BAAANQADCgcIBwAAAA==.Darkfoxdemon:BAAANQAECgQICAAAAA==.Darkjager:BAAANQADCgcIBwAAAA==.Darkstaff:BAAANQADCgMIAwAAAA==.Darlah:BAAANQADCggIDgAAAA==.Dayyva:BAAANQAECgQICAAAAA==.',
De='Deadcobra:BAAANQADCgMIBQAAAA==.Deangilberry:BAAANQADCgQICQAAAA==.Delindeyn:BAAANQADCgEIAQAAAA==.Deltria:BAAANQADCgUIBgAAAA==.Demonrot:BAAANQADCgcIDgAAAA==.',
Di='Diaboliq:BAAANQADCgcIGAAAAA==.Dilea:BAAANQAECgEIAQAAAA==.',
Dk='Dkon:BAAANQAECgUICAAAAA==.',
Dr='Dracomyst:BAAANQADCggIAgAAAA==.Drruz:BAAANQADCgIIAgAAAA==.',
Du='Dumbledorr:BAAANQAECgIIAgAAAQ==.Durzoe:BAAANQAECgIIAgAAAA==.',
Dw='Dwod:BAAANQAECgQIBAAAAA==.',
['Dí']='Díscø:BAEANQAECgcIDgAAAA==.',
Er='Ershulie:BAAANQABCggIHQAAAA==.',
Ew='Ewt:BAAANQAECgQICAAAAA==.',
Fe='Felussi:BAAANQAECgQIBQAAAA==.',
Fi='Finnster:BAAANQAECgUICgAAAA==.Fionna:BAAANQADCgQIBAAAAA==.',
Fl='Flameon:BAAANQABCgcICAAAAA==.Flarixi:BAAANQADCgMIAwAAAA==.Fleurminator:BAAANQAECgQIBQAAAA==.',
Fr='Fractor:BAAANQADCgYICwAAAA==.Frieia:BAAANQADCgYIDgAAAA==.Frostface:BAAANQADCgQIBAAAAA==.',
Fu='Fubuki:BAABNQAECoEeAAIDAAkJcx/rBgD/AgADAAkJcx/rBgD/AgAAAA==.',
Ga='Galarína:BAAANQAECgQIBgAAAA==.Gallitha:BAAANQADCgUIBQAAAA==.Gandora:BAAANQAECgQICAAAAA==.Gauge:BAAANQAECgcICwAAAA==.',
Gk='Gkmc:BAAANQAECgYIBwABNQAFFAYIDQABAIQgAA==.',
Go='Gobbomode:BAAANQADCgYIBgAAAA==.Gorbino:BAAANQAECgYIDwAAAA==.',
Gr='Greasemunkey:BAAANQAECgQIBgAAAA==.Gretchaen:BAAANQAECgEIAQAAAA==.Griiv:BAABNQAECoEVAAIEAAgJ8yNBDQA+AwAEAAgJ8yNBDQA+AwAAAA==.Grislydemon:BAAANQADCggICAAAAA==.Grislydoom:BAAANQADCgEIAQAAAA==.Grislyshock:BAAANQAECgUICgAAAA==.',
Ha='Hakunamatata:BAAANQADCgYIBgAAAA==.Hamburger:BAAANQAECgIIAgAAAA==.Hammerhard:BAAANQADCgIIAgAAAA==.',
He='Heights:BAAANQADCgMIAwABNQAECgQIBgACAAAAAA==.Heliosan:BAAANQAECgQIBwAAAA==.Hemoblast:BAAANQADCgIIAgAAAA==.Hemolight:BAAANQADCgYIDAAAAA==.',
Hr='Hrshoo:BAAANQAECggICgAAAA==.',
['Hä']='Hädês:BAAANQADCggIAQAAAA==.',
Je='Jeannaah:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.Jekyl:BAAANQADCgMIAwAAAA==.Jekyll:BAAANQADCgUIBQAAAA==.',
['Já']='Jáckyboy:BAAANQAECgQICAAAAA==.',
Ka='Kalestra:BAAANQAECgMIBAAAAA==.Kayelalynn:BAAANQAECgQICAAAAA==.',
Kd='Kd:BAAANQADCgQIBAAAAA==.',
Ke='Keeghor:BAAANQAECgUIBQABNQAECggIFQAEAPMjAA==.Kendô:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.Keyahi:BAAANQAFFAEIAQABNQAECgEIAQACAAAAAA==.',
Kh='Khaean:BAAANQAECgQIBgAAAA==.',
Ki='Kickandpunch:BAAANQAECgcIEAAAAA==.Kilan:BAAANQADCgcIEgAAAA==.Kimuraakid:BAAANQAECgEIAQAAAA==.',
Ko='Korladin:BAAANQADCgYICQAAAA==.',
Kr='Krutree:BAAANQAECgQIBgAAAA==.',
Ku='Kutbrezbek:BAAANQABCgYICgAAAA==.',
Ky='Kyleata:BAAANQAECgQICAAAAA==.Kyokin:BAAANQAECggIDQAAAA==.Kyzula:BAAANQAECgQIBQAAAA==.',
['Kê']='Kêndo:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.',
La='Lagrandè:BAAANQAECgMIBgAAAA==.',
Li='Lilylocks:BAAANQAECgEIAQAAAA==.Littlelo:BAAANQADCgQIBAAAAA==.',
Ly='Lyanah:BAAANQAECgYICQAAAA==.Lyriell:BAAANQADCgYIBgAAAA==.',
Ma='Maggrus:BAAANQABCgYIDAAAAA==.Malical:BAAANQADCgEIAQAAAA==.Manshöön:BAAANQADCgQIBAABNQADCggIEAACAAAAAA==.Matheney:BAAANQAECgQIBAABNQAFFAUIBwAFADcRAA==.Mattlock:BAAANQAECgIIAgAAAA==.Maverick:BAAANQABCgUIBwAAAA==.',
Mc='Mctubby:BAAANQADCgYIBgAAAA==.',
Md='Mdead:BAAANQABCgcICAAAAA==.',
Me='Meigz:BAAANQADCgEIAQAAAA==.Melinda:BAAANQAECgQIBAAAAA==.Mewtwo:BAAANQAECgMIAwAAAA==.',
Mi='Milenzha:BAAANQADCgIIAwAAAA==.Misaoh:BAAANQADCgYICgAAAA==.',
Mo='Moonreína:BAAANQAECgEIAQAAAA==.Moons:BAAANQADCgYIBgABNQAECgkJJgAFAGckAA==.Moontann:BAAANQADCggICgAAAA==.Moreia:BAAANQADCgMIAwAAAA==.Mousse:BAAANQADCgcIDQAAAA==.',
My='Mysharona:BAAANQADCgYIBgAAAA==.',
Mz='Mzbiscuit:BAAANQADCgYIEQAAAA==.',
Na='Narberal:BAAANQADCggIEgABNQAECgcICAACAAAAAA==.Nasene:BAAANQAECgQIBwAAAA==.Natstryker:BAAANQAECgQICAAAAA==.Naturemyth:BAAANQADCgYIBgAAAA==.',
Ne='Necromyst:BAAANQADCggIAQAAAA==.',
No='Noctyra:BAAANQADCgMIBgAAAA==.',
Or='Organa:BAAANQADCgcIFQAAAA==.',
Pa='Palarina:BAAANQADCggIFQABNQAECgQIBgACAAAAAA==.Palyomie:BAAANQAECgUICAAAAA==.',
Ph='Pho:BAAANQAECgQICAAAAA==.',
Pl='Playwityou:BAAANQADCgUIBgAAAA==.Plugley:BAAANQAECgEIAQAAAA==.',
['Pë']='Përdü:BAAANQADCgUIBgAAAA==.',
Ra='Rakunn:BAAANQADCggIEwABNQAECgQICwACAAAAAA==.Ratapew:BAAANQADCgUIBgAAAA==.Ratheen:BAAANQABCgYICgAAAA==.Raytar:BAAANQAECgIIBAAAAA==.',
Re='Renn:BAAANQAECgQICAAAAA==.',
Ri='Riltonge:BAAANQAECgEIAQAAAA==.',
Ro='Roachdirt:BAAANQAECgQICQAAAA==.Robean:BAAANQADCgQIBAAAAA==.Roxoxoxanne:BAAANQADCgcICgAAAA==.',
Ru='Rustybray:BAAANQAECgEIAQAAAA==.',
Sa='Sageghost:BAAANQABCgUIBgAAAA==.Sangôl:BAAANQADCgIIAgABNQAECgYICwACAAAAAA==.Sarabi:BAAANQADCgcIFAAAAA==.Saralina:BAAANQAECgEIAQABNQAECgYIEAACAAAAAA==.',
Sc='Schnee:BAAANQAECgQIBgAAAA==.Schutzhund:BAAANQADCgUIBgAAAA==.',
Se='Sekha:BAAANQADCgQIBAABNQAECgQIBwACAAAAAA==.Sena:BAAANQADCgYIBgAAAA==.Serelia:BAAANQADCgYIBgAAAA==.',
Sh='Shadoweave:BAAANQAECgEIAQABNQAFFAYIDwAFAEQMAA==.Shalalia:BAAANQADCgcICwAAAA==.Shambean:BAAANQAECgEIAQAAAA==.Shavox:BAAANQABCgUICQAAAA==.Shieldster:BAAANQAECgIIAgAAAA==.Shnizelnazee:BAAANQAECgMIBAAAAA==.',
Sm='Smokeyb:BAAANQAECgQICQAAAA==.',
Sn='Snorehees:BAAANQAECgIIAgAAAA==.',
So='Solaeris:BAAANQADCggIDQAAAA==.Songstar:BAAANQAECgQICAAAAA==.Soullraven:BAAANQADCgUICgAAAA==.',
Sp='Spaceboat:BAAANQAECgUICQAAAA==.Spy:BAAANQADCgQIBAAAAA==.Spàz:BAAANQABCgMIAgAAAA==.',
St='Staavon:BAAANQADCgcIGAAAAA==.Starblaze:BAAANQADCggIEwAAAA==.',
Su='Sugarhoof:BAAANQADCgUICQAAAA==.Sugarlick:BAAANQADCggIGAAAAA==.Sugarpop:BAAANQAECgYIEAAAAA==.',
Sw='Swiftstrike:BAAANQADCggIBQAAAA==.',
Sy='Syrebriel:BAAANQADCggIEAAAAA==.',
Ta='Tanjiro:BAAANQADCgEIAQAAAA==.',
Tg='Tgoat:BAAANQADCgEIAQAAAA==.',
Ti='Timeless:BAAANQADCggIHAAAAA==.Tinymeatgang:BAAANQADCgUIBwAAAA==.',
To='Toetagger:BAAANQAECgIIAgAAAA==.Tonymaster:BAAANQAECgMIAwAAAA==.Toucannon:BAAANQAECggIEAAAAA==.',
Tr='Treealia:BAAANQABCgIIAgAAAA==.',
Ty='Tyrrial:BAAANQADCgYIEAAAAA==.Tyshus:BAAANQAECgEIAQAAAA==.',
Ua='Ualmar:BAAANQABCgUIBQAAAA==.',
Ut='Uthgardt:BAAANQAECgEIAQAAAA==.',
Va='Valarion:BAAANQAECgQICAAAAA==.Validimus:BAAANQADCgEIAQAAAA==.Valorían:BAAANQAECgQICAAAAA==.Varthayn:BAAANQAECgIIAgAAAA==.Varue:BAAANQAECggIAgAAAA==.',
Ve='Verra:BAAANQAECgEIAQAAAA==.Vestaria:BAAANQADCgQIBAAAAA==.',
Vo='Volbain:BAAANQAECgEIAQAAAA==.',
Vu='Vulpsinculta:BAAANQADCgcIFgAAAA==.',
['Vï']='Vïrùs:BAAANQAECgUIDwAAAA==.',
Wa='Warboar:BAAANQADCgIIAgAAAA==.Wasntmee:BAAANQADCgEIAQABNQADCgYIEQACAAAAAA==.',
We='Weaz:BAAANQADCgYICgAAAA==.',
Wi='Wichita:BAAANQAECgIIAgAAAA==.',
Wt='Wtfguën:BAAANQADCgcIFQAAAA==.',
Xb='Xbean:BAAANQADCgcIFgAAAA==.',
Xo='Xorman:BAAANQADCgcIEAAAAA==.',
Xy='Xyo:BAAANQAECgMIAwAAAA==.',
Xz='Xzairi:BAAANQAECgQIBwAAAA==.',
Zi='Zinora:BAAANQADCgcICgAAAA==.Ziyue:BAAANQAECgMIBgAAAA==.',
Zn='Zn:BAAANQAECgUICwAAAA==.',
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
