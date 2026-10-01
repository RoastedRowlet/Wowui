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

local lookup = {'DeathKnight-Blood','Unknown-Unknown','Priest-Shadow','Druid-Balance','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Druid-Feral','Shaman-Enhancement','Monk-Windwalker','Evoker-Preservation','Evoker-Devastation','DemonHunter-Havoc','DeathKnight-Frost','Evoker-Augmentation','DemonHunter-Devourer','DemonHunter-Vengeance','Paladin-Holy','Paladin-Retribution','Mage-Arcane','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Monk-Mistweaver','Priest-Holy','Druid-Guardian','Hunter-BeastMastery','Warlock-Affliction',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Aceroth:BAAANQAECgUIDAAAAA==.Achärd:BAAANQAECggIEAAAAA==.',
Ae='Aelin:BAABNQAECoEcAAIBAAgKow8wQQC2AQABAAgKow8wQQC2AQAAAA==.Aerillidan:BAAANQAECgEIAQAAAA==.',
Ak='Akinna:BAAANQABCgYJBgAAAA==.',
Al='Alaysia:BAAANQADCgYIBgAAAA==.Alestair:BAAANQAECgcIDwAAAA==.Alythra:BAAANQADCgcIBwAAAA==.',
Am='Amorsith:BAAANQAECgYIEQAAAA==.Ampluslues:BAAANQADCgMIAgABNQADCggICAACAAAAAA==.',
An='Angrä:BAAANQAECgQJBAAAAA==.',
Ar='Arakfalas:BAAANQADCggIDgAAAA==.Argentnox:BAAANQADCgUIBQABNQAECgUIEgACAAAAAA==.Argoz:BAAANQAECgYIEAAAAA==.Arrethyn:BAAANQAECgcICAAAAA==.',
As='Asbell:BAAANQAECgcIDAAAAA==.Aspectz:BAAANQABCgMIAwAAAA==.',
At='Atsidi:BAAANQAECgYIDwAAAA==.',
Ax='Axecutioner:BAAANQAECgQIBAAAAA==.',
Az='Azaelara:BAAANQAECgUIDAAAAA==.Azaëlle:BAAANQADCgYIDAAAAA==.Azshaura:BAAANQADCgIIAgAAAA==.',
Ba='Badmojojojo:BAAANQAECgUIEgAAAA==.Bankhand:BAAANQAECgYIEQAAAA==.Bartab:BAAANQAECgMIBAAAAA==.',
Be='Beazle:BAAANQABCggIDgAAAA==.Beefytotems:BAAANQAECgYICAABNQAECggICQACAAAAAA==.Benjamin:BAABNQAECoEZAAIDAAkKzRtuEQCoAgADAAkKzRtuEQCoAgAAAA==.',
Bi='Bibistraz:BAAANQAECgYIEwAAAA==.',
Bl='Blenny:BAAANQAECgMIAwAAAA==.Blitzkrîeg:BAAANQAECgYIEQAAAA==.',
Bo='Boeboe:BAAANQAECgYICQAAAA==.Boomloomly:BAABNQAECoEfAAMEAAgK/iH8EgALAwAEAAgK/iH8EgALAwAFAAIKzAkCUABiAAAAAA==.Borgymorgy:BAAANQADCgEIAQAAAA==.',
Br='Brightblade:BAAANQADCgcIBwAAAA==.Bruzande:BAAANQAECgYJEAAAAA==.Brynjolf:BAAANQADCgYIBgAAAA==.',
Bu='Bumbaweatuna:BAAANQADCgEIAQAAAA==.Burncycle:BAAANQADCgYIBgAAAA==.Burntt:BAAANQABCgYIBgAAAA==.Buttjeans:BAABNQAECoEbAAMGAAgKEiGPJwCwAgAGAAcKpyGPJwCwAgAHAAIKUxJ+SwCHAAAAAA==.',
Ca='Catastrophez:BAAANQADCgcIBwAAAA==.',
Ce='Celine:BAAANQAECgUIDAAAAA==.Ceo:BAAANQAECgEIAQAAAA==.',
Ch='Chev:BAAANQADCgUIBQAAAA==.Chickynuggy:BAAANQAECgQICQAAAA==.Chillypickle:BAAANQAECgMIBAAAAA==.Christopher:BAABNQAECoEYAAIBAAkKqiFhDAAtAwABAAkKqiFhDAAtAwAAAA==.Chronicbuds:BAAANQAECgYIDQAAAA==.',
Cl='Cloudcaller:BAAANQADCgYIBgABNQAECggIGgAIAJcHAA==.Clyde:BAAANQADCgYJBgAAAA==.',
Co='Cobrakai:BAAANQAECgQIBgAAAA==.Cochuata:BAAANQAECgUIDAAAAA==.',
Cr='Crabbypatty:BAAANQADCgcICwABNQABCgQIBAACAAAAAA==.Cripstaet:BAAANQADCgYIBgAAAA==.Crow:BAAANQAECgEIAQAAAA==.Crusadinvee:BAAANQADCggICAAAAA==.',
Cu='Curse:BAAANQAECgQICAABNQAECgYIEAACAAAAAA==.',
Da='Dairydefendr:BAAANQAECgYIDwAAAA==.Damage:BAAANQADCgYIBgAAAA==.Damyn:BAABNQAECoEaAAIJAAgKYRbACwB8AgAJAAgKYRbACwB8AgAAAA==.Darogue:BAAANQADCggICAAAAA==.Darthsparrow:BAAANQAECgMIAwAAAA==.',
De='Deathaxe:BAAANQADCgUIBQABNQAECgUIDAACAAAAAA==.Deathsgrace:BAAANQAECgUIDAAAAA==.Delia:BAAANQABCggIDgAAAA==.Demark:BAAANQAECgQIBAAAAA==.Demonicneon:BAAANQAECgYICwAAAA==.Devana:BAAANQAECgYIEwAAAA==.',
Di='Diabolicque:BAAANQAECgEIAQAAAA==.Diddycated:BAEANQAECgUIBQABNQAECgkJIAAKAB0WAA==.Dingus:BAAANQAECgYIEQAAAA==.',
Dk='Dk:BAAANQADCgYIDQABNQAECgYIEAACAAAAAA==.',
Do='Doode:BAABNQAECoEdAAMLAAgKUAlhHwCYAQALAAgKUAlhHwCYAQAMAAEKmAL5OAAjAAAAAA==.Doody:BAAANQADCgYIEAABNQAECggIHQALAFAJAA==.',
Dr='Dreastotems:BAAANQAECgEIAgAAAA==.Drennifer:BAAANQAECgQICgAAAA==.',
Eb='Ebtyrone:BAAANQADCgQIBAAAAA==.',
Em='Emmerson:BAAANQADCgQIBQAAAA==.Emphasis:BAAANQAECgEIAQABNQAECggIGAANANgVAA==.',
Es='Escanór:BAAANQADCgUIBwAAAA==.',
Fa='Fajitajones:BAAANQADCgUICgAAAA==.',
Fo='Fooksdh:BAAANQADCggICAAAAA==.Fooksdk:BAABNQAECoEdAAMOAAgK6RXqJQAJAgAOAAgK6RXqJQAJAgABAAUKTwelegDAAAAAAA==.Fooksdruid:BAAANQAECgQIBAAAAA==.Forestpimp:BAAANQAECgQICQAAAA==.',
Fu='Fullometal:BAABNQAECoEYAAIIAAgKVRZNCQBIAgAIAAgKVRZNCQBIAgAAAA==.Furojin:BAAANQAECgUIBQABNQAECgUIEgACAAAAAA==.',
Ga='Galroot:BAABNQAECoEbAAIFAAcKbiU6CgDwAgAFAAcKbiU6CgDwAgAAAA==.Galstad:BAAANQABCgEIAQAAAA==.Garrett:BAAANQADCgEIAQAAAA==.',
Ge='Geff:BAAANQADCgQIBAAAAA==.',
Gi='Girthhquake:BAAANQAECgQIBQAAAA==.Gisokaashi:BAAANQADCgcJCwAAAA==.',
Gn='Gnomepwner:BAAANQADCgcIBwAAAA==.',
Go='Gothick:BAAANQAECgMIAwAAAA==.',
Gr='Grimréaper:BAAANQADCgIIAgAAAA==.',
Gu='Guts:BAAANQAECgEIAQAAAA==.',
Ha='Harryhoudini:BAAANQAECgEJAQAAAA==.',
He='Healforfun:BAABNQAECoEhAAIFAAgKZhrDFABaAgAFAAgKZhrDFABaAgAAAA==.Heilung:BAABNQAECoEfAAMPAAgKExMXBwDtAQAPAAgKExMXBwDtAQAMAAEKJwEEOgAdAAAAAA==.',
Hi='Hippokleides:BAAANQADCgYICgAAAA==.Hirradee:BAABNQAECoEkAAIQAAkKERVjFwByAgAQAAkKERVjFwByAgAAAA==.',
Ho='Holyzeal:BAAANQADCgUIBQAAAA==.Honatuto:BAAANQAECgQIBAAAAA==.',
Hu='Hubelez:BAAANQAECgcIEQAAAA==.',
Hy='Hyacine:BAAANQADCggICAAAAA==.',
Ic='Icecweam:BAAANQADCgYIBgAAAA==.Icthelight:BAAANQAECgMIAwAAAA==.',
Ii='Iista:BAAANQAECgEIAQAAAA==.',
Ir='Irontuskss:BAAANQAECgEIAQAAAA==.',
Iz='Iznthyr:BAAANQABCgIIAgAAAA==.',
Ja='Jayar:BAABNQAECoEYAAMNAAgK2BUFJwAUAgANAAgK2BUFJwAUAgARAAEKWQhRKAAmAAAAAA==.',
Jd='Jdawgg:BAAANQADCggIIwAAAA==.',
Jo='Jorley:BAAANQADCggIDwAAAA==.',
Jr='Jrwriter:BAAANQAECgYIEAAAAA==.',
Jy='Jym:BAAANQAECgYICwAAAA==.',
Ka='Kaijin:BAABNQAECoEcAAIKAAgKhhYeGwAOAgAKAAgKhhYeGwAOAgAAAA==.Kalasting:BAAANQAECgMIBgABNQAECgcIEgACAAAAAA==.Kalyr:BAAANQAECgYICgAAAA==.Kandrianna:BAAANQAECgYIEQAAAA==.',
Ke='Keraasi:BAABNQAECoEdAAMSAAgKHRK7RgAJAgASAAgKHRK7RgAJAgATAAEKYwebTAEzAAAAAA==.Kevinv:BAAANQADCgEIAQAAAA==.',
Kh='Khristine:BAAANQADCgQIBAABNQAECggIGAANANgVAA==.',
Ki='Kikai:BAAANQADCgUICQAAAA==.Kilrav:BAAANQAECgYIDwAAAA==.Kimberlee:BAAANQAECggICQAAAA==.Kiryanna:BAAANQAECgQIBQAAAA==.Kitiara:BAAANQAECgQJBAAAAA==.',
Kl='Klayah:BAAANQAECgQICQAAAA==.',
Ko='Koogz:BAAANQAECgQIBQAAAA==.Kordelia:BAAANQAECgUIEQABNQAECgYIEwACAAAAAA==.Korgmafx:BAAANQADCgUIEAAAAA==.',
Kr='Kratosol:BAAANQAECgEJAQAAAA==.',
La='Larke:BAAANQAECgIIAwAAAA==.',
Le='Leilany:BAAANQAECgQICAAAAA==.Lethäl:BAAANQADCgIIAgAAAA==.',
Li='Littledirk:BAAANQADCgcIAgAAAA==.',
Ll='Llillies:BAAANQAECgEIAQAAAA==.',
Lu='Lugnuts:BAAANQAECgQIBQAAAA==.',
Ma='Magebuff:BAABNQAECoEqAAIUAAkKqB7gMQAMAwAUAAkKqB7gMQAMAwAAAA==.Malroy:BAAANQADCgYIBgAAAA==.',
Mc='Mcheals:BAAANQADCgcIDgAAAA==.',
Mi='Miidniter:BAAANQAECgQIBAAAAA==.',
Mo='Monsunami:BAAANQAECgQJCAAAAA==.Moogar:BAABNQAECoEdAAMVAAgKliC8FAD6AgAVAAgKliC8FAD6AgAWAAEKuwOx+AA2AAAAAA==.Moolinda:BAAANQAECgMIAwAAAA==.Moonlock:BAAANQADCggICAAAAA==.Morte:BAAANQADCgIIAgAAAA==.Moònflower:BAAANQAECgIIAgAAAA==.',
['Mø']='Møøse:BAAANQAECgYIEQAAAA==.',
Na='Namegoeshere:BAAANQAECgMIAwABNQAECgUIEgACAAAAAA==.Nanwu:BAAANQAECgYIEwAAAA==.Narcyon:BAAANQAECgcIEgAAAA==.',
Ne='Neonfel:BAAANQADCggICAAAAA==.',
Nh='Nhox:BAAANQAECgEIBAAAAA==.Nhöxx:BAAANQADCgIIAwAAAA==.',
No='Noobîtîs:BAAANQADCgcIDAAAAA==.Notmaxxie:BAAANQAECgIIAwAAAA==.',
Ny='Nystiae:BAAANQADCggICAAAAA==.',
Ob='Obz:BAAANQAECgcIEQAAAA==.',
Od='Oddlylight:BAAANQAECgQICAAAAA==.',
Ol='Ollie:BAAANQADCgIIAgAAAA==.',
Pa='Pandicated:BAEBNQAECoEgAAQKAAkKHRaCGwAIAgAKAAkKWBCCGwAIAgAXAAcKHBPYDwCqAQAYAAEKWwAYSAATAAAAAA==.',
Pe='Pelondar:BAAANQADCggIDgAAAA==.',
Ph='Phalanx:BAAANQADCgYIDgAAAA==.',
Pl='Plaguedoctor:BAAANQADCgQJBAAAAA==.',
Po='Pookalicious:BAAANQADCgQIBAAAAA==.Pookiebear:BAAANQADCgIIAgAAAA==.Possessed:BAAANQADCgYICgAAAA==.',
Pr='Prìdè:BAAANQAECgYIDwAAAA==.',
Pu='Punjana:BAAANQABCgMIAwAAAA==.',
Ra='Raike:BAAANQADCgMIAwAAAA==.Razmae:BAAANQAECgMIAwAAAA==.',
Re='Rennala:BAAANQAECgEIAQAAAA==.',
Ri='Riptide:BAAANQAECgYIEwAAAA==.Risto:BAAANQAECgUIDAAAAA==.',
Ro='Rockon:BAAANQAECgcIEgABNQADCgcIDgACAAAAAA==.Roden:BAAANQABCgMIAwAAAA==.Ronzertnin:BAAANQAECgUIDAAAAA==.Roxen:BAAANQADCggIFQAAAA==.',
Ru='Runananako:BAAANQAECgMIBgAAAA==.',
['Ré']='Réaper:BAAANQADCgcIDwAAAA==.Rénji:BAAANQAECgYIDgAAAA==.',
Sa='Salana:BAAANQAECgIIAwAAAA==.San:BAAANQAECggIEAABNQAFFAIIBgAZAHgOAA==.Sandroin:BAAANQAECgEIAQAAAA==.Sarah:BAAANQADCggIDAABNQAECggIIgAZAGshAA==.',
Sc='Scarf:BAAANQAECgYIDwAAAA==.',
Sh='Shiggy:BAAANQADCggICAAAAA==.Shinerbock:BAAANQAECgYIDwAAAA==.Shipoopi:BAAANQAECgYIEAAAAA==.Shock:BAAANQAECgcIEgAAAA==.Shortnshady:BAAANQAECgYIDwAAAA==.',
Si='Sithen:BAAANQAECgMIAwAAAA==.',
Sk='Skankadin:BAAANQADCgYICQABNQAECgIIBAACAAAAAA==.Skankerella:BAAANQAECgIIBAAAAA==.Skiatrochia:BAAANQADCggICAABNQAECgkJJAAQABEVAA==.Skipuscales:BAAANQAECgcIEgAAAA==.',
Sm='Smoaky:BAABNQAECoEaAAIIAAgKlweMEgBhAQAIAAgKlweMEgBhAQAAAA==.',
So='Soul:BAABNQAECoEkAAMEAAkKlxyEEgAPAwAEAAkKlxyEEgAPAwAaAAQKoQt5KwCtAAAAAA==.Soulscorcher:BAAANQADCggIFAAAAA==.Soulsurvivor:BAAANQADCgEIAQABNQAECgUIDQACAAAAAA==.Sovietpanda:BAAANQADCgUICAAAAA==.',
Sp='Spanky:BAAANQAECgQIBQAAAA==.Spankyohs:BAAANQADCgcJDAAAAA==.Spindles:BAAANQAECgEIAQAAAA==.Spineless:BAAANQADCgQIBAAAAA==.Spiritgun:BAAANQAECgEIAQABNQAECgYIEAACAAAAAA==.',
St='Stimpack:BAAANQAECgUIDQAAAA==.',
Su='Sutures:BAAANQADCgYIDgAAAA==.',
['Sö']='Sönja:BAAANQAECgIIBAAAAA==.',
Ta='Tará:BAAANQAECgUJCQAAAA==.',
Te='Techpriest:BAAANQADCgYIBwAAAA==.Tehblink:BAAANQAECgYIEQAAAA==.Tenative:BAAANQAECgIIAgABNQAECggIGwAGABIhAA==.Tenoch:BAAANQAECgMIBgAAAA==.Terah:BAAANQADCgIIAgAAAA==.',
To='Toomez:BAAANQADCggICgAAAA==.Touchmydemon:BAAANQAECgMIBQAAAA==.',
Tr='Trea:BAABNQAECoEYAAIbAAcKKRMEbADhAQAbAAcKKRMEbADhAQAAAA==.',
Tu='Tupkiss:BAABNQAECoEbAAIDAAcKqSC5EgCXAgADAAcKqSC5EgCXAgAAAA==.',
Ty='Tygrand:BAAANQAECgEIAQABNQAECggIGgAIAJcHAA==.',
Va='Vazer:BAAANQABCgMIAwAAAA==.',
Wa='Waffledead:BAABNQAECoEaAAQcAAgKNBqKCwBfAQAcAAUKDhiKCwBfAQAGAAQK8huwnwAyAQAHAAMKXBurLwD1AAAAAA==.Wafflelight:BAAANQADCgcIBwAAAA==.Warpfiend:BAAANQAECgUICwAAAA==.',
We='Wek:BAAANQADCgUIBQAAAA==.Wetnugget:BAAANQAECgEIAgAAAA==.',
Wi='Winnie:BAAANQADCgEIAQAAAA==.',
Wo='Wolfnhowz:BAAANQAECgIIAgAAAA==.',
Yu='Yura:BAAANQADCgEIAQAAAA==.Yuriko:BAAANQADCgYIDAAAAA==.',
Za='Zandragon:BAAANQADCgQIBAAAAA==.',
Ze='Zebubblez:BAAANQAECgIIAwAAAA==.',
Zg='Zgux:BAAANQAECgQIBwAAAA==.',
Zo='Zoêy:BAAANQADCggIHQAAAA==.',
Zu='Zuraki:BAAANQAECgQIBgAAAA==.',
Zz='Zzin:BAAANQABCgEIAQAAAA==.',
['Ço']='Çountèr:BAAANQAECgIIAgAAAA==.',
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
