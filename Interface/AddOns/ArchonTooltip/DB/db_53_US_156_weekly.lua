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

local lookup = {'Hunter-Marksmanship','Priest-Holy','Priest-Shadow','Shaman-Enhancement','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','DeathKnight-Frost','Druid-Balance','Paladin-Holy','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Paladin-Protection','Mage-Arcane','Paladin-Retribution','Druid-Restoration','Druid-Guardian','Hunter-Survival','Druid-Feral','Evoker-Devastation','Warrior-Arms','Warrior-Fury',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abàddón:BAAANQADCgYIDAAAAA==.',
Ac='Acidburn:BAAANQADCgYICgAAAA==.',
Al='Alluna:BAAANQAECgEIAQAAAA==.Alorillan:BAAANQAECgMIAwAAAA==.Altabrew:BAAANQADCgMIAwAAAA==.Altair:BAAANQAECgYIDQAAAA==.',
An='Anker:BAAANQAECgEIAQABNQAECgkJFwABACcXAA==.Anomalien:BAAANQAECgMIAwAAAA==.',
Ap='Apocalyspe:BAAANQAECgcIEAAAAA==.Appless:BAABNQAECoEoAAMCAAkKnxXrSwAZAgACAAgKrxPrSwAZAgADAAgKxRRkIAAQAgAAAA==.',
Ar='Aridella:BAAANQAECgYIDwAAAA==.',
Az='Azusie:BAABNQAECoEaAAIEAAgKLg/UEgAYAgAEAAgKLg/UEgAYAgAAAA==.',
Ba='Bablepopye:BAAANQAECgMIAwAAAA==.Baddate:BAAANQAECgEIAQAAAA==.Baddragøn:BAAANQAECgcIEwAAAA==.Balthaas:BAAANQAECgcIEAAAAA==.Bangen:BAAANQAECgEIAQAAAA==.Baulters:BAAANQADCgYIBgAAAA==.Baylor:BAAANQADCgUIBQAAAA==.',
Be='Beenn:BAAANQADCgcJDAAAAA==.Belael:BAAANQADCgcIBwAAAA==.Benrent:BAAANQADCgEIAQABNQADCgcJDAAFAAAAAA==.',
Bi='Biinks:BAAANQADCggIEwAAAA==.Billywitchdr:BAABNQAECoEcAAMGAAcK3hYzdwCMAQAGAAYKxhUzdwCMAQAHAAEK6QzUAwEzAAAAAA==.Bisharp:BAAANQADCggICAABNQAECggIEgAFAAAAAA==.',
Bl='Blazingelf:BAAANQADCgMIAwAAAA==.Blindedbý:BAAANQABCgQIBAAAAA==.Bluetoykawi:BAABNQAECoEnAAIIAAgK3BF0MQDiAQAIAAgK3BF0MQDiAQAAAA==.',
Bo='Bonedelivery:BAAANQABCgIIAgAAAA==.',
Br='Breloom:BAAANQAECgYIBgABNQAECggIEgAFAAAAAA==.',
Bu='Bulkathos:BAAANQAECgEIAQABNQAECgYICgAFAAAAAA==.',
['Bé']='Béorñ:BAAANQAECgYICgABNQAECggIEAAFAAAAAA==.',
Ca='Cariandria:BAAANQADCgYIBgAAAA==.',
Ch='Charita:BAEANQAECggIEAAAAA==.Charming:BAEANQAECgcJEgABNQAECggIEAAFAAAAAA==.',
Cl='Clanker:BAAANQAECgQIAwAAAA==.Clark:BAAANQADCgEIAQAAAA==.Clouds:BAAANQADCggICAABNQAECgcIEAAFAAAAAA==.',
Co='Coffeecat:BAAANQADCgYIDwAAAA==.Contrlurself:BAAANQADCgQIBAABNQAECggIHwAJAKcQAA==.Cowret:BAABNQAECoEnAAIKAAkK8SB1DABWAwAKAAkK8SB1DABWAwAAAA==.',
Cr='Crowleyy:BAAANQADCgUIBQAAAA==.',
Da='Dademurphy:BAAANQADCgIIAgAAAA==.Darc:BAAANQADCgcIBwAAAA==.Darkfoxdemon:BAABNQAECoEfAAQLAAgKbxhbCQAkAgALAAgKbxhbCQAkAgAMAAYKZQyNTgAmAQANAAYKrgQ0QgAKAQAAAA==.Darkjager:BAAANQADCgcIBwAAAA==.Darkstaff:BAAANQADCgMIAwAAAA==.Darkways:BAAANQADCgYIBgAAAA==.Darlah:BAAANQADCggIFwAAAA==.Dayyva:BAAANQAECgQICgAAAA==.',
De='Deadcobra:BAAANQADCgMIBQAAAA==.Deangilberry:BAAANQADCgQICQAAAA==.Delindeyn:BAAANQADCgYIEgAAAA==.Deltria:BAAANQAECgMIAwAAAA==.Demonrot:BAAANQADCggIFgAAAA==.Deviltank:BAAANQADCgQIBAAAAA==.',
Di='Diaboliq:BAAANQAECgIIAwAAAA==.Diefenbaker:BAAANQADCgcIBwAAAA==.Digmyearth:BAAANQADCgYIBgAAAA==.Dilea:BAAANQAECgEIAQAAAA==.',
Dk='Dkon:BAABNQAECoEXAAMOAAcK3hd4UwCEAQAOAAcK5xB4UwCEAQAPAAUKphjbbwAwAQAAAA==.',
Do='Doppler:BAAANQAECgUIDgAAAA==.',
Dr='Dracomyst:BAAANQADCggIAgAAAA==.Driver:BAEANQAECggICAAAAA==.Drruz:BAAANQADCggIEwAAAA==.',
Du='Dumbledorr:BAAANQAECgIIAgAAAQ==.Durzoe:BAAANQAECgUIDAAAAA==.',
Dv='Dvsmage:BAAANQADCgcIDQABNQAECgEIAQAFAAAAAA==.',
Dw='Dwod:BAABNQAECoEaAAMIAAcK+hSTNADNAQAIAAcK+hSTNADNAQAOAAMK0QUaoABzAAAAAA==.',
['Dí']='Díscø:BAEBNQAECoEXAAIDAAkKbxlwFgCEAgADAAkKbxlwFgCEAgAAAA==.',
Er='Errita:BAAANQADCgEIAQAAAA==.Ershulie:BAAANQABCggIJQAAAA==.',
Ew='Ewt:BAABNQAECoEeAAIQAAgK7RYuEAD4AQAQAAgK7RYuEAD4AQAAAA==.',
Fa='Fastnine:BAAANQAECgUIBQABNQAECggIEgAFAAAAAA==.',
Fe='Felhound:BAAANQAECgMIAwAAAA==.Felussi:BAABNQAECoEcAAMRAAgKeBEtZwAAAgARAAgKeBEtZwAAAgASAAEKtRTxagBAAAAAAA==.',
Fi='Finnster:BAABNQAECoEfAAITAAcKdgkrtgBjAQATAAcKdgkrtgBjAQAAAA==.Fionna:BAAANQADCgQIBAAAAA==.',
Fl='Flameon:BAAANQABCgcICgAAAA==.Flarixi:BAAANQADCgcICgAAAA==.Fleurminator:BAAANQAECgYICwAAAA==.',
Fr='Fractor:BAAANQADCgYICwAAAA==.Frieia:BAAANQAECgQIBwAAAA==.Frostface:BAAANQADCgcICwAAAA==.Frozenjade:BAAANQADCgIIAgAAAA==.',
Fu='Fubuki:BAACNQAFFIENAAMUAAUKdAupCAASAQAUAAQKrg2pCAASAQAVAAEKjAJsCgAqAAA1AAQKgSgAAhQACQqZIb4NAOYCABQACQqZIb4NAOYCAAAA.',
Ga='Galapriest:BAAANQAECgEIAQAAAA==.Galarína:BAABNQAECoEcAAMWAAgKGiA0CgDJAgAWAAgKGiA0CgDJAgAUAAEK0AtBXgA1AAAAAA==.Gallitha:BAAANQADCgUIBQAAAA==.Gamewarden:BAAANQADCggIDgABNQAECgcIHAACANQaAA==.Gandora:BAABNQAECoEdAAQPAAgKZw3DUwCbAQAPAAgKGA3DUwCbAQAIAAMKpwbbdwB/AAAOAAEKQxH4uwAyAAAAAA==.Gauge:BAAANQAECgcIDQABNQAECggIHQAXAKsYAA==.',
Ge='Getoffme:BAAANQAECgUICAAAAA==.',
Gk='Gkmc:BAABNQAFFIEFAAIPAAMKUCD+CwAiAQAPAAMKUCD+CwAiAQABNQAFFAcIDwAYACEhAA==.',
Go='Gobbomode:BAAANQADCgYIBgAAAA==.Gorbino:BAABNQAECoEnAAIXAAkKOiQ6AgCjAwAXAAkKOiQ6AgCjAwAAAA==.',
Gr='Greasemunkey:BAAANQAECgUIDwAAAA==.Gretchaen:BAAANQAECgQICAAAAA==.Griiv:BAABNQAECoEoAAIZAAgKKSYeFwBVAwAZAAgKKSYeFwBVAwABNQAECgkJGAAEAIQhAA==.Grislydemon:BAAANQADCggICAAAAA==.Grislydoom:BAAANQAECgEIAQAAAA==.Grislyshock:BAABNQAECoEcAAIEAAcKKRq3EQAuAgAEAAcKKRq3EQAuAgAAAA==.',
Ha='Hakunamatata:BAAANQADCgYIBgAAAA==.Hamburger:BAAANQAECgUICAAAAA==.Hammerhard:BAAANQADCgIIAgAAAA==.Harcones:BAAANQADCgMJAwAAAA==.',
He='Heights:BAAANQADCgMIAwABNQAECgQIBgAFAAAAAA==.Heliosan:BAAANQAECgUIEwAAAA==.Hellelements:BAAANQADCgYIBgABNQAECggIHQAXAKsYAA==.Hemoblast:BAAANQADCgIIAgAAAA==.Hemolight:BAAANQADCgYIDAAAAA==.',
Hr='Hrshoo:BAAANQAFFAEIAQAAAA==.',
['Hä']='Hädês:BAAANQAECgMIAwAAAA==.',
Je='Jeannaah:BAAANQAECgUIBwABNQAECgEIAQAFAAAAAA==.Jekyl:BAAANQADCgMIAwAAAA==.Jekyll:BAAANQADCgUIBQAAAA==.',
Ju='Judgment:BAAANQABCgEJAQAAAA==.',
['Já']='Jáckyboy:BAABNQAECoEiAAMaAAkKzR8SFgBwAgAaAAcK5R0SFgBwAgAJAAcK5BUcQQDIAQAAAA==.',
Ka='Kalestra:BAABNQAECoEaAAMJAAcK3xmONQAVAgAJAAcK3xmONQAVAgAbAAcKRAj+JgAXAQAAAA==.Kalithos:BAAANQAECgMIAwAAAA==.Kayelalynn:BAABNQAECoEfAAIJAAgKpxDPPQDeAQAJAAgKpxDPPQDeAQAAAA==.Kaymoo:BAAANQABCgIIAgAAAA==.',
Kd='Kd:BAAANQADCggIDAAAAA==.',
Ke='Keeghor:BAABNQAECoEYAAIEAAkKhCHBAgB2AwAEAAkKhCHBAgB2AwAAAA==.Kendô:BAAANQADCgYIBwABNQAECgQICgAFAAAAAA==.Keyahi:BAAANQAFFAEIAQABNQAECgEIAQAFAAAAAA==.',
Kh='Khaean:BAABNQAECoEaAAIcAAcKBR7eBABdAgAcAAcKBR7eBABdAgAAAA==.',
Ki='Kickandpunch:BAAANQAECgcIEAAAAA==.Kiilan:BAAANQADCgEIAQAAAA==.Kilan:BAAANQAECgMIBAAAAA==.Kimuraakid:BAAANQAECgEIAQAAAA==.',
Ko='Kocaman:BAAANQADCgIIAgAAAA==.Korladin:BAAANQADCgYICQAAAA==.',
Kr='Krutree:BAAANQAECgQIBgAAAA==.',
Ku='Kungfubean:BAAANQADCgcIBwABNQAECgEIAQAFAAAAAA==.Kutbrezbek:BAAANQABCgYICgAAAA==.',
Ky='Kyleata:BAABNQAECoEeAAITAAcKChzLWQA9AgATAAcKChzLWQA9AgAAAA==.Kylz:BAAANQABCggICQAAAA==.Kyokin:BAABNQAECoEiAAMZAAkK8xmsQQCqAgAZAAkK8xmsQQCqAgAXAAEKTgiZawAkAAAAAA==.Kyryn:BAAANQADCgMIAwAAAA==.Kyzula:BAAANQAECgQIEAAAAA==.',
['Kê']='Kêndo:BAAANQADCgEIAQABNQAECgQICgAFAAAAAA==.',
La='Lagrandè:BAABNQAECoEcAAIOAAcKrBrTNwAJAgAOAAcKrBrTNwAJAgAAAA==.',
Li='Liandrai:BAAANQAECgIIAgAAAA==.Lillyith:BAAANQADCgcIDgAAAA==.Lilylocks:BAAANQAECgQIBQAAAA==.Littlelo:BAAANQADCgcIBwAAAA==.',
Ly='Lyanah:BAABNQAECoEhAAQaAAgK8AgrLgB0AQAaAAgK8AgrLgB0AQAdAAYKhgnxGQAoAQAJAAIKJQVDkwBWAAAAAA==.Lycota:BAAANQADCggIBwAAAA==.Lyriell:BAAANQADCgYIBgAAAA==.',
Ma='Maelius:BAAANQADCgQIBAABNQAECggIHgAQAO0WAA==.Maggrus:BAAANQABCgYIDAAAAA==.Malical:BAAANQADCgEIAQAAAA==.Manshöön:BAAANQADCgUIBQABNQADCggIEAAFAAAAAA==.Matheney:BAAANQAECgUIBgABNQADCgYIBgAFAAAAAA==.Mattlock:BAABNQAECoEdAAISAAgKoRVgCgBIAgASAAgKoRVgCgBIAgAAAA==.Maverick:BAAANQABCggIDAAAAA==.',
Mc='Mctubby:BAAANQADCgYJCwAAAA==.',
Md='Mdead:BAAANQABCgcICAAAAA==.',
Me='Meigz:BAAANQADCgcIFQAAAA==.Melinda:BAABNQAECoEUAAIHAAcKjBNIaACkAQAHAAcKjBNIaACkAQAAAA==.Mewtwo:BAAANQAECgMIAwAAAA==.',
Mi='Milenzha:BAAANQAECgEIAQAAAA==.Misaoh:BAAANQAECgQIBQAAAA==.',
Mo='Moonreína:BAAANQAECgQICQAAAA==.Moons:BAAANQADCgYIBgABNQAECgkJPAATAKYkAA==.Moontann:BAAANQADCggICgAAAA==.Moreia:BAAANQADCgMIAwAAAA==.Mousse:BAAANQAECgQICAAAAA==.',
Mu='Murdalok:BAAANQAECgQIAwAAAA==.',
My='Mysharona:BAAANQADCgYIBgAAAA==.',
Mz='Mzbiscuit:BAAANQADCgYIEQABNQADCgcIDgAFAAAAAA==.',
Na='Narberal:BAAANQADCggIFgABNQAECgkJLwAKANcmAA==.Nasene:BAAANQAECgcIDgAAAA==.Nataltharion:BAAANQADCgcICQAAAA==.Natstryker:BAABNQAECoEdAAMVAAgKcyQ7AwBMAwAVAAgKcyQ7AwBMAwAWAAYKKAeUKQD5AAAAAA==.Naturemyth:BAAANQADCgYIBgAAAA==.',
Ne='Necromyst:BAAANQADCggIAQAAAA==.',
No='Noctyra:BAAANQADCgYJDAAAAA==.',
Ok='Okaminooni:BAAANQADCgcIBwAAAA==.',
Om='Omcmoneyshot:BAAANQADCgcIDQAAAA==.',
Or='Organa:BAAANQAECgQICAAAAA==.',
Pa='Palarina:BAAANQAECgQIBwABNQAECggIHAAWABogAA==.Palyomie:BAAANQAECgYIDgAAAA==.',
Ph='Pho:BAABNQAECoEcAAICAAcK1BofQgA9AgACAAcK1BofQgA9AgAAAA==.',
Pl='Playwityou:BAAANQAECgMIAwAAAA==.Plugley:BAAANQAECgUIBgAAAA==.',
Po='Poweedman:BAAANQAECgQIAQAAAA==.',
Pu='Pumpkins:BAAANQAECgYIBgAAAA==.',
['Pë']='Përdü:BAAANQAECgMIAwAAAA==.',
Ra='Raethu:BAAANQABCgIIAgAAAA==.Rakunn:BAAANQAECgUICgAAAA==.Ratapew:BAAANQAECgMIAwAAAA==.Ratheen:BAAANQABCggIEwAAAA==.Raytar:BAAANQAECgMIBQAAAA==.',
Re='Relaxx:BAAANQAECgIIAgAAAA==.Renn:BAAANQAECgQICAAAAA==.',
Rh='Rhordrin:BAAANQAECgQIBAABNQAECgcIDgAFAAAAAA==.',
Ri='Riltonge:BAAANQAECgMIBAAAAA==.',
Ro='Roachdirt:BAAANQAECgUJDgAAAA==.Robean:BAAANQADCgQJBAAAAA==.Rogun:BAAANQAECgEIAQAAAA==.Roxoxoxanne:BAAANQADCgcICgAAAA==.',
Ru='Rustybray:BAABNQAECoEcAAIGAAgK3wbtegCCAQAGAAgK3wbtegCCAQAAAA==.',
Sa='Sageghost:BAAANQABCggIDgAAAA==.Sandryus:BAAANQAECgQIBgAAAA==.Sangol:BAAANQAECgEIAQAAAA==.Sarabi:BAAANQAECgQICAAAAA==.Saralina:BAAANQAECgUICAABNQAECggIJgAKAL0gAA==.',
Sc='Schnee:BAAANQAECgUICgAAAA==.Schutzhund:BAAANQADCggIEQAAAA==.',
Se='Sekha:BAAANQADCgQIBAABNQAECgkJHAAJAG4VAA==.Sena:BAAANQADCgYIBgAAAA==.Serelia:BAAANQADCgYIBgAAAA==.',
Sh='Shadoweave:BAAANQAECgQIBQABNQAFFAYIGgATACUPAA==.Shalalia:BAAANQAECgEIAQAAAA==.Shambean:BAAANQAECgEIAQAAAA==.Shavox:BAAANQABCgUICQAAAA==.Shhanks:BAAANQAECgIIAgAAAA==.Shieldster:BAABNQAECoEaAAIXAAgKFgRRNwADAQAXAAgKFgRRNwADAQAAAA==.Shnizelnazee:BAAANQAECgYIDwAAAA==.',
Si='Siege:BAAANQAECgQIBAABNQAECggIJQAIAMYkAA==.Silvie:BAAANQADCgcIBwAAAA==.',
Sm='Smokeyb:BAABNQAECoEeAAIZAAkKnhL2dgAPAgAZAAkKnhL2dgAPAgAAAA==.',
Sn='Sneevie:BAAANQADCggIDwAAAA==.Snorehees:BAAANQAECgcIEQAAAA==.',
So='Solaeris:BAAANQADCggIDQAAAA==.Solarth:BAAANQADCgIIAgABNQAECggIGQAMAEMQAA==.Songstar:BAABNQAECoEfAAITAAgKWB+KMQC1AgATAAgKWB+KMQC1AgAAAA==.Soullraven:BAAANQADCgUIDgAAAA==.',
Sp='Spaceboat:BAAANQAECgUIEQAAAA==.Sped:BAAANQAECgYIBgAAAA==.Spy:BAAANQADCgQIBAAAAA==.Spàz:BAAANQABCgMIAgAAAA==.',
St='Staavon:BAAANQAECgIIAgAAAA==.Stalvis:BAAANQABCgIIAgAAAA==.Starblaze:BAAANQAECgQIBgAAAA==.Steeda:BAAANQADCggICAAAAA==.',
Su='Sugarhoof:BAAANQAECgEIAgAAAA==.Sugarlick:BAAANQAECgQIBwAAAA==.Sugarpop:BAABNQAECoEmAAIKAAgKvSBJGwD0AgAKAAgKvSBJGwD0AgAAAA==.Suplazindh:BAAANQAECgMIBgABNQAFFAcIGgAeAEYkAA==.',
Sw='Swiftstrike:BAAANQADCggJBQAAAA==.',
Sy='Sylvqt:BAAANQABCgYICQAAAA==.Syrebriel:BAAANQADCggIEAAAAA==.',
Ta='Taediah:BAAANQAECgEIAQAAAA==.Tanjiro:BAAANQAECgcICAAAAA==.Tanthanalas:BAAANQADCgUIBwAAAA==.Tazetack:BAAANQAECgIIAgAAAA==.',
Tg='Tgoat:BAAANQADCgEIAQAAAA==.',
Th='Thenâ:BAAANQADCgUIBQAAAA==.Theoutcast:BAAANQADCgIJAgAAAA==.Thesarius:BAAANQAECgQIAwAAAA==.',
Ti='Timeless:BAAANQAECgYICgAAAA==.Tinymeatgang:BAAANQADCgUIBwAAAA==.',
To='Toetagger:BAAANQAECgUIDAAAAA==.Tonymaster:BAAANQAECgQICgAAAA==.Toucannon:BAAANQAECggIEgAAAA==.',
Tr='Trackinoobs:BAAANQADCgcIDgAAAA==.Trashiepanda:BAAANQADCgQIBQAAAA==.Traumanurse:BAAANQADCgcIBwABNQAECgQICAAFAAAAAA==.Treealia:BAAANQABCgIIAgAAAA==.',
Ty='Tyrrial:BAAANQAECgIIAwAAAA==.Tyshus:BAAANQAECgIIBAAAAA==.',
Ua='Ualmar:BAAANQAECgcIDwAAAA==.',
Ur='Urgrannargru:BAAANQABCgIIAgAAAA==.',
Ut='Uthgardt:BAAANQAECgUICwAAAA==.',
Va='Valarion:BAABNQAECoEdAAIfAAgKeAhlpACWAQAfAAgKeAhlpACWAQAAAA==.Validimus:BAAANQADCgEIAQAAAA==.Valorían:BAABNQAECoEbAAQQAAgK0x6pBwC5AgAQAAgK0x6pBwC5AgAgAAMKwhbaGgDUAAAfAAIKkA8rGAFtAAAAAA==.Vanfro:BAAANQAECgQIAwAAAA==.Varthayn:BAABNQAECoEdAAIYAAgKuRnicACGAgAYAAgKuRnicACGAgAAAA==.Varue:BAAANQAECggJBwAAAA==.',
Ve='Velandriel:BAAANQADCgEIAQABNQAECggIGQAMAEMQAA==.Verksquirt:BAAANQAECgYICwAAAA==.Verra:BAAANQAECgEIAQAAAA==.Vestaria:BAAANQADCgQIBAAAAA==.',
Vo='Volbain:BAAANQAECgQICQAAAA==.',
Vu='Vulpsinculta:BAAANQAECgQICAAAAA==.',
Wa='Warboar:BAAANQADCgIIAgAAAA==.Wasntmee:BAAANQADCgYJBgABNQADCgcIDgAFAAAAAA==.',
We='Weaz:BAAANQADCggIJAAAAA==.',
Wi='Wichita:BAABNQAECoEdAAIOAAgKfhj2LwA1AgAOAAgKfhj2LwA1AgAAAA==.Wildbean:BAAANQADCgMIAwAAAA==.',
Wt='Wtfguën:BAAANQAECgQICAAAAA==.Wtftiff:BAAANQADCgcIBwAAAA==.',
Xa='Xanfel:BAAANQABCgQIBgAAAA==.',
Xb='Xbean:BAAANQAECgQICAAAAA==.',
Xo='Xorman:BAAANQADCgcJEAAAAA==.',
Xy='Xyo:BAAANQAECgcIEAAAAA==.',
Xz='Xzairi:BAABNQAECoEcAAMJAAkKbhVsKQBoAgAJAAkKbhVsKQBoAgAaAAEKoQncbgAiAAAAAA==.',
Ze='Zenezal:BAAANQAECgQIBAAAAA==.',
Zi='Zinora:BAAANQADCgcICgAAAA==.Ziyue:BAAANQAECgUICwAAAA==.',
Zn='Zn:BAABNQAECoEeAAIKAAgKCxV7RQAxAgAKAAgKCxV7RQAxAgAAAA==.',
['Àd']='Àddixt:BAAANQABCgIIAgAAAA==.',
['Òm']='Òmcmoneyshot:BAAANQADCgYICwAAAA==.',
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
