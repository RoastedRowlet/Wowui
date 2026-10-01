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

local lookup = {'Mage-Arcane','Priest-Shadow','Priest-Holy','Unknown-Unknown','DeathKnight-Frost','Druid-Balance','Paladin-Holy','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Protection','Hunter-BeastMastery','Monk-Windwalker','Monk-Brewmaster','Paladin-Protection','Paladin-Retribution','Shaman-Enhancement','Druid-Restoration','Evoker-Devastation',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abàddón:BAAANQADCgYIDAAAAA==.',
Ac='Acidburn:BAAANQADCgYICgAAAA==.',
Al='Alluna:BAAANQAECgEIAQAAAA==.Alorillan:BAAANQADCggIDQAAAA==.Altabrew:BAAANQADCgMIAwAAAA==.Altair:BAAANQAECgYICAAAAA==.',
An='Anker:BAAANQAECgEIAQABNQAECgkJIAABABkeAA==.Anomalien:BAAANQAECgMIAwAAAA==.',
Ap='Apocalyspe:BAAANQAECgcIDgAAAA==.Appless:BAABNQAECoEhAAMCAAkKWBZBGwAlAgACAAgKvhRBGwAlAgADAAQK0ASyngDEAAAAAA==.',
Ar='Aridella:BAAANQAECgYIDwAAAA==.',
Az='Azusie:BAAANQAECgYIEQAAAA==.',
Ba='Bablepopye:BAAANQAECgMIAwAAAA==.Baddate:BAAANQAECgEIAQAAAA==.Baddragøn:BAAANQAECgYIDAAAAA==.Balthaas:BAAANQAECgQICQAAAA==.Bangen:BAAANQAECgEIAQAAAA==.Baulters:BAAANQADCgYIBgAAAA==.Baylor:BAAANQADCgUIBQAAAA==.',
Be='Beenn:BAAANQADCgcJDAAAAA==.Belael:BAAANQADCgcIBwAAAA==.Benrent:BAAANQADCgEIAQABNQADCgcJDAAEAAAAAA==.',
Bi='Biinks:BAAANQADCggIEwAAAA==.Billywitchdr:BAAANQAECgYIEgAAAA==.Bisharp:BAAANQADCggICAABNQAECggIEgAEAAAAAA==.',
Bl='Blazingelf:BAAANQADCgMIAwAAAA==.Blindedbý:BAAANQABCgQIBAAAAA==.Bluetoykawi:BAABNQAECoEcAAIFAAgKGA5+NQCWAQAFAAgKGA5+NQCWAQAAAA==.',
Bo='Bonedelivery:BAAANQABCgIIAgAAAA==.',
Br='Breloom:BAAANQAECgYIBgABNQAECggIEgAEAAAAAA==.',
Bu='Bulkathos:BAAANQADCgcIDAABNQAECgQIBAAEAAAAAA==.',
['Bé']='Béorñ:BAAANQAECgYIBgABNQAECgcICgAEAAAAAA==.',
Ch='Charita:BAEANQAECgcIDQABNQAECgcJEgAEAAAAAA==.Charming:BAEANQAECgcJEgAAAA==.',
Cl='Clanker:BAAANQAECgMIAwAAAA==.Clark:BAAANQADCgEIAQAAAA==.Clouds:BAAANQADCggICAAAAA==.',
Co='Coffeecat:BAAANQADCgYICQAAAA==.Contrlurself:BAAANQADCgQIBAABNQAECgcIFwAGAIQOAA==.Cowret:BAABNQAECoEfAAIHAAgKJCF+FQABAwAHAAgKJCF+FQABAwAAAA==.',
Cr='Crowleyy:BAAANQADCgUIBQAAAA==.',
Da='Dademurphy:BAAANQADCgIIAgAAAA==.Darc:BAAANQADCgcIBwAAAA==.Darkfoxdemon:BAABNQAECoEXAAMIAAcKfBkZCQD/AQAIAAcKfBkZCQD/AQAJAAUKMQ4MSQALAQAAAA==.Darkjager:BAAANQADCgcIBwAAAA==.Darkstaff:BAAANQADCgMIAwAAAA==.Darkways:BAAANQADCgYIBgAAAA==.Darlah:BAAANQADCggIEAAAAA==.Dayyva:BAAANQAECgQICAAAAA==.',
De='Deadcobra:BAAANQADCgMIBQAAAA==.Deangilberry:BAAANQADCgQICQAAAA==.Delindeyn:BAAANQADCgYIEQAAAA==.Deltria:BAAANQADCggIDQAAAA==.Demonrot:BAAANQADCggIFgAAAA==.Deviltank:BAAANQADCgQJBAAAAA==.',
Di='Diaboliq:BAAANQAECgEIAQAAAA==.Digmyearth:BAAANQADCgYIBgAAAA==.Dilea:BAAANQAECgEIAQAAAA==.',
Dk='Dkon:BAABNQAECoEVAAMKAAcKhBSIVQBYAQAKAAcKjA2IVQBYAQALAAUKphghWABKAQAAAA==.',
Do='Doppler:BAAANQAECgUICQAAAA==.',
Dr='Dracomyst:BAAANQADCggIAgAAAA==.Driver:BAEANQAECggICAAAAA==.Drruz:BAAANQADCggICwAAAA==.',
Du='Dumbledorr:BAAANQAECgIIAgAAAQ==.Durzoe:BAAANQAECgUIDAAAAA==.',
Dv='Dvsmage:BAAANQADCgcIDQABNQAECgEIAQAEAAAAAA==.',
Dw='Dwod:BAAANQAECgcIEgAAAA==.',
['Dí']='Díscø:BAEANQAFFAIIAgAAAA==.',
Er='Errita:BAAANQADCgEIAQAAAA==.Ershulie:BAAANQABCggIHwAAAA==.',
Ew='Ewt:BAABNQAECoEWAAIMAAcK4RegDwDRAQAMAAcK4RegDwDRAQAAAA==.',
Fe='Felhound:BAAANQADCgIIAgAAAA==.Felussi:BAAANQAECgYIEQAAAA==.',
Fi='Finnster:BAABNQAECoEZAAINAAcKgQh5owBVAQANAAcKgQh5owBVAQAAAA==.Fionna:BAAANQADCgQIBAAAAA==.',
Fl='Flameon:BAAANQABCgcICgAAAA==.Flarixi:BAAANQADCgMIAwAAAA==.Fleurminator:BAAANQAECgYICwAAAA==.',
Fr='Fractor:BAAANQADCgYICwAAAA==.Frieia:BAAANQAECgMIAwAAAA==.Frostface:BAAANQADCgcICwAAAA==.Frozenjade:BAAANQADCgIIAgAAAA==.',
Fu='Fubuki:BAACNQAFFIEJAAMOAAUKGwgCBwARAQAOAAQKfgkCBwARAQAPAAEKjALUCAAsAAA1AAQKgSUAAg4ACQrzH4QNAM8CAA4ACQrzH4QNAM8CAAAA.',
Ga='Galarína:BAAANQAECgYIEgAAAA==.Gallitha:BAAANQADCgUIBQAAAA==.Gamewarden:BAAANQADCggIDgABNQAECgYIEwAEAAAAAA==.Gandora:BAAANQAECgYIEwAAAA==.Gauge:BAAANQAECgcICwAAAA==.',
Ge='Getoffme:BAAANQAECgUICAAAAA==.',
Gk='Gkmc:BAAANQAFFAIIAgABNQAFFAcIDwABACEhAA==.',
Go='Gobbomode:BAAANQADCgYIBgAAAA==.Gorbino:BAABNQAECoEfAAIQAAgKZCMyBgAZAwAQAAgKZCMyBgAZAwAAAA==.',
Gr='Greasemunkey:BAAANQAECgQICgAAAA==.Gretchaen:BAAANQAECgIIBAAAAA==.Griiv:BAABNQAECoEiAAIRAAgKEiaDEwBYAwARAAgKEiaDEwBYAwAAAA==.Grislydemon:BAAANQADCggICAAAAA==.Grislydoom:BAAANQAECgEIAQAAAA==.Grislyshock:BAABNQAECoEYAAISAAcKNRkJDwA3AgASAAcKNRkJDwA3AgAAAA==.',
Ha='Hakunamatata:BAAANQADCgYIBgAAAA==.Hamburger:BAAANQAECgUIBwAAAA==.Hammerhard:BAAANQADCgIIAgAAAA==.Harcones:BAAANQADCgMJAwAAAA==.',
He='Heights:BAAANQADCgMIAwABNQAECgQIBgAEAAAAAA==.Heliosan:BAAANQAECgUIEQAAAA==.Hemoblast:BAAANQADCgIIAgAAAA==.Hemolight:BAAANQADCgYIDAAAAA==.',
Hr='Hrshoo:BAAANQAECggIDAAAAA==.',
['Hä']='Hädês:BAAANQADCggIAgAAAA==.',
Je='Jeannaah:BAAANQAECgUIBwABNQAECgEIAQAEAAAAAA==.Jekyl:BAAANQADCgMIAwAAAA==.Jekyll:BAAANQADCgUIBQAAAA==.',
Ju='Judgment:BAAANQABCgEJAQAAAA==.',
['Já']='Jáckyboy:BAAANQAECgYIEgAAAA==.',
Ka='Kalestra:BAAANQAECgYIEAAAAA==.Kalithos:BAAANQADCgEIAQAAAA==.Kayelalynn:BAABNQAECoEXAAIGAAcKhA4YRQCLAQAGAAcKhA4YRQCLAQAAAA==.',
Kd='Kd:BAAANQADCggIDAAAAA==.',
Ke='Keeghor:BAAANQAECggIEgABNQAECggIIgARABImAA==.Kendô:BAAANQADCgYIBwABNQAECgQIBgAEAAAAAA==.Keyahi:BAAANQAFFAEIAQABNQAECgEIAQAEAAAAAA==.',
Kh='Khaean:BAAANQAECgUIDwAAAA==.',
Ki='Kickandpunch:BAAANQAECgcIEAAAAA==.Kiilan:BAAANQADCgEIAQAAAA==.Kilan:BAAANQAECgMIBAAAAA==.Kimuraakid:BAAANQAECgEIAQAAAA==.',
Ko='Kocaman:BAAANQADCgIIAgAAAA==.Korladin:BAAANQADCgYICQAAAA==.',
Kr='Krutree:BAAANQAECgQIBgAAAA==.',
Ku='Kutbrezbek:BAAANQABCgYICgAAAA==.',
Ky='Kyleata:BAAANQAECgYIEwAAAA==.Kyokin:BAABNQAECoEeAAIRAAkK2BkLMgDCAgARAAkK2BkLMgDCAgAAAA==.Kyzula:BAAANQAECgQIDAAAAA==.',
['Kê']='Kêndo:BAAANQADCgEIAQABNQAECgQIBgAEAAAAAA==.',
La='Lagrandè:BAAANQAECgYIEgAAAA==.',
Li='Lillyith:BAAANQADCgcIBwAAAA==.Lilylocks:BAAANQAECgQIBQAAAA==.Littlelo:BAAANQADCgQIBAAAAA==.',
Ly='Lyanah:BAABNQAECoEZAAITAAgK8AgPJwCEAQATAAgK8AgPJwCEAQAAAA==.Lycota:BAAANQADCggIBwAAAA==.Lyriell:BAAANQADCgYIBgAAAA==.',
Ma='Maelius:BAAANQADCgQIBAABNQAECgcIFgAMAOEXAA==.Maggrus:BAAANQABCgYIDAAAAA==.Malical:BAAANQADCgEIAQAAAA==.Manshöön:BAAANQADCgUIBQABNQADCggIEAAEAAAAAA==.Matheney:BAAANQAECgUIBgABNQADCgYIBgAEAAAAAA==.Mattlock:BAAANQAECgYIEQAAAA==.Maverick:BAAANQABCggIDAAAAA==.',
Mc='Mctubby:BAAANQADCgYJCwAAAA==.',
Md='Mdead:BAAANQABCgcICAAAAA==.',
Me='Meigz:BAAANQADCgcIDgAAAA==.Melinda:BAAANQAECgUIDQAAAA==.Mewtwo:BAAANQAECgMIAwAAAA==.',
Mi='Milenzha:BAAANQADCgIJBAAAAA==.Misaoh:BAAANQAECgEIAQAAAA==.',
Mo='Moonreína:BAAANQAECgMIBQAAAA==.Moons:BAAANQADCgYIBgABNQAECgkJPAANAKYkAA==.Moontann:BAAANQADCggICgAAAA==.Moreia:BAAANQADCgMIAwAAAA==.Mousse:BAAANQAECgMIBAAAAA==.',
Mu='Murdalok:BAAANQAECgMIAwAAAA==.',
My='Mysharona:BAAANQADCgYIBgAAAA==.',
Mz='Mzbiscuit:BAAANQADCgYIEQABNQADCgcIBwAEAAAAAA==.',
Na='Narberal:BAAANQADCggIEgABNQAECgkJKQAHANcmAA==.Nasene:BAAANQAECgYICQAAAA==.Nataltharion:BAAANQADCgIIAgAAAA==.Natstryker:BAAANQAECgYIEwAAAA==.Naturemyth:BAAANQADCgYIBgAAAA==.',
Ne='Necromyst:BAAANQADCggIAQAAAA==.',
No='Noctyra:BAAANQADCgYJDAAAAA==.',
Om='Omcmoneyshot:BAAANQADCgYIBgAAAA==.',
Or='Organa:BAAANQAECgMIBAAAAA==.',
Pa='Palarina:BAAANQAECgQJBAABNQAECgYIEgAEAAAAAA==.Palyomie:BAAANQAECgYIDgAAAA==.',
Ph='Pho:BAAANQAECgYIEwAAAA==.',
Pl='Playwityou:BAAANQADCggIDQAAAA==.Plugley:BAAANQAECgUIBgAAAA==.',
Po='Poweedman:BAAANQAECgMIAQAAAA==.',
Pu='Pumpkins:BAAANQAECgYIBgAAAA==.',
['Pë']='Përdü:BAAANQADCggIDQAAAA==.',
Ra='Raethu:BAAANQABCgIIAgAAAA==.Rakunn:BAAANQAECgQIBQABNQAECgUIGQAQALQRAA==.Ratapew:BAAANQADCgcICAAAAA==.Ratheen:BAAANQABCggIEQAAAA==.Raytar:BAAANQAECgMIBQAAAA==.',
Re='Relaxx:BAAANQAECgIIAQAAAA==.Renn:BAAANQAECgQICAAAAA==.',
Ri='Riltonge:BAAANQAECgMIBAAAAA==.',
Ro='Roachdirt:BAAANQAECgUJDgAAAA==.Robean:BAAANQADCgQJBAAAAA==.Rogun:BAAANQAECgEIAQAAAA==.Roxoxoxanne:BAAANQADCgcICgAAAA==.',
Ru='Rustybray:BAAANQAECgYIEAAAAA==.',
Sa='Sageghost:BAAANQABCggIDAAAAA==.Sandryus:BAAANQAECgEIAQAAAA==.Sangol:BAAANQADCgIIAgAAAA==.Sarabi:BAAANQAECgMIBAAAAA==.Saralina:BAAANQAECgUICAABNQAECggIJAAHAPQeAA==.',
Sc='Schnee:BAAANQAECgUICgAAAA==.Schutzhund:BAAANQADCgcIDQAAAA==.',
Se='Sekha:BAAANQADCgQIBAABNQAECgcIEwAEAAAAAA==.Sena:BAAANQADCgYIBgAAAA==.Serelia:BAAANQADCgYIBgAAAA==.',
Sh='Shadoweave:BAAANQAECgEIAQABNQAFFAYIFAANAPAMAA==.Shalalia:BAAANQAECgEIAQAAAA==.Shambean:BAAANQAECgEIAQAAAA==.Shavox:BAAANQABCgUICQAAAA==.Shhanks:BAAANQAECgIIAgAAAA==.Shieldster:BAAANQAECgcIDwAAAA==.Shnizelnazee:BAAANQAECgUIDgAAAA==.',
Si='Silvie:BAAANQADCgcIBwAAAA==.',
Sm='Smokeyb:BAABNQAECoEaAAIRAAgK8RKKdwDdAQARAAgK8RKKdwDdAQAAAA==.',
Sn='Sneevie:BAAANQADCgcIBwAAAA==.Snorehees:BAAANQAECgYIDQAAAA==.',
So='Solaeris:BAAANQADCggIDQAAAA==.Solarth:BAAANQADCgIIAgABNQAECgYIEwAEAAAAAA==.Songstar:BAABNQAECoEXAAINAAcKXh1ISQBFAgANAAcKXh1ISQBFAgAAAA==.Soullraven:BAAANQADCgUIDgAAAA==.',
Sp='Spaceboat:BAAANQAECgUJDQAAAA==.Spy:BAAANQADCgQIBAAAAA==.Spàz:BAAANQABCgMIAgAAAA==.',
St='Staavon:BAAANQADCggIIgAAAA==.Stalvis:BAAANQABCgIIAgAAAA==.Starblaze:BAAANQAECgEIAgAAAA==.',
Su='Sugarhoof:BAAANQAECgEIAQAAAA==.Sugarlick:BAAANQAECgMIAwAAAA==.Sugarpop:BAABNQAECoEkAAIHAAgK9B7lGADqAgAHAAgK9B7lGADqAgAAAA==.Suplazindh:BAAANQAECgMIBgABNQAFFAcIGAAUAI0iAA==.',
Sw='Swiftstrike:BAAANQADCggJBQAAAA==.',
Sy='Sylvqt:BAAANQABCgYICQAAAA==.Syrebriel:BAAANQADCggIEAAAAA==.',
Ta='Taediah:BAAANQAECgEIAQAAAA==.Tanjiro:BAAANQAECgIIAQAAAA==.Tanthanalas:BAAANQADCgUIBwAAAA==.',
Tg='Tgoat:BAAANQADCgEIAQAAAA==.',
Th='Theoutcast:BAAANQADCgIJAgAAAA==.Thesarius:BAAANQAECgMIAwAAAA==.',
Ti='Timeless:BAAANQAECgQIBAAAAA==.Tinymeatgang:BAAANQADCgUIBwAAAA==.',
To='Toetagger:BAAANQAECgUIDAAAAA==.Tonymaster:BAAANQAECgQIBgAAAA==.Toucannon:BAAANQAECggIEgAAAA==.',
Tr='Trackinoobs:BAAANQADCgcIBwAAAA==.Trashiepanda:BAAANQADCgQIBQAAAA==.Traumanurse:BAAANQADCgcIBwABNQAECgMIBAAEAAAAAA==.Treealia:BAAANQABCgIIAgAAAA==.',
Ty='Tyrrial:BAAANQAECgEIAQAAAA==.Tyshus:BAAANQAECgIIBAAAAA==.',
Ua='Ualmar:BAAANQAECgYICAAAAA==.',
Ur='Urgrannargru:BAAANQABCgIIAgAAAA==.',
Ut='Uthgardt:BAAANQAECgUICwAAAA==.',
Va='Valarion:BAAANQAECgYIEwAAAA==.Validimus:BAAANQADCgEIAQAAAA==.Valorían:BAAANQAECgYIEgAAAA==.Vanfro:BAAANQAECgMIAwAAAA==.Varthayn:BAAANQAECgYIEQAAAA==.Varue:BAAANQAECggJBwAAAA==.',
Ve='Velandriel:BAAANQADCgEIAQABNQAECgYIEwAEAAAAAA==.Verksquirt:BAAANQAECgYICwAAAA==.Verra:BAAANQAECgEIAQAAAA==.Vestaria:BAAANQADCgQIBAAAAA==.',
Vo='Volbain:BAAANQAECgMIBQAAAA==.',
Vu='Vulpsinculta:BAAANQAECgQIBAAAAA==.',
Wa='Warboar:BAAANQADCgIIAgAAAA==.Wasntmee:BAAANQADCgYJBgABNQADCgcIBwAEAAAAAA==.',
We='Weaz:BAAANQADCggIGgAAAA==.',
Wi='Wichita:BAAANQAECgYIEQAAAA==.',
Wt='Wtfguën:BAAANQAECgMIBAAAAA==.',
Xb='Xbean:BAAANQAECgMIBAAAAA==.',
Xo='Xorman:BAAANQADCgcJEAAAAA==.',
Xy='Xyo:BAAANQAECgcIDgAAAA==.',
Xz='Xzairi:BAAANQAECgcIEwAAAA==.',
Zi='Zinora:BAAANQADCgcICgAAAA==.Ziyue:BAAANQAECgMIBgAAAA==.',
Zn='Zn:BAABNQAECoEcAAIHAAgKCxX2OgA6AgAHAAgKCxX2OgA6AgAAAA==.',
['Àd']='Àddixt:BAAANQABCgIIAgAAAA==.',
['Òm']='Òmcmoneyshot:BAAANQADCgUIBQAAAA==.',
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
