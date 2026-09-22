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

local lookup = {'Priest-Holy','Druid-Restoration','Priest-Shadow','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Druid-Balance','Shaman-Restoration','DeathKnight-Frost','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Monk-Brewmaster','DeathKnight-Unholy','Evoker-Preservation','Mage-Arcane','Monk-Mistweaver','Shaman-Enhancement','Rogue-Assassination','DeathKnight-Blood','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Druid-Guardian','Monk-Windwalker','Warlock-Demonology','Warlock-Affliction','Mage-Frost','Warrior-Arms',}
local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abavok:BAAANQADCgcIBwAAAA==.Absoul:BAABNQAECoEoAAIBAAgKNRvXLABHAgABAAgKNRvXLABHAgAAAA==.Abyssian:BAAANQADCgYIBgAAAA==.',
Ac='Acedia:BAAANQAECgQJCAAAAA==.',
Ad='Adellas:BAABNQAECoEbAAICAAgKUxNhFwD8AQACAAgKUxNhFwD8AQAAAA==.Adern:BAABNQAECoEfAAIDAAgKDhaaFABYAgADAAgKDhaaFABYAgAAAA==.Adon:BAAANQADCgUIBQABNQADCgYJBgAEAAAAAA==.Adonn:BAABNQAECoEbAAMFAAgKeBtIOgBrAgAFAAgKeBtIOgBrAgAGAAIKlQscQgBSAAAAAA==.Adonshadriel:BAAANQADCgYJBgAAAA==.',
Ae='Aelali:BAAANQAECgEIBAAAAA==.',
Af='Afador:BAAANQADCggJCAABNQAECgUJBgAEAAAAAA==.',
Al='Aladestar:BAABNQAECoEdAAMHAAgKCxp9HwBzAgAHAAgKCxp9HwBzAgACAAQKVxU2LgD/AAAAAA==.Albinodh:BAAANQAECgEIAQAAAA==.Alchemy:BAAANQABCgEIAQABNQAFFAMIBQAIAIckAA==.Alderleise:BAAANQADCgcIBwAAAA==.Alexein:BAABNQAECoEdAAIJAAgKGRR+IAD1AQAJAAgKGRR+IAD1AQAAAA==.',
Am='Amets:BAAANQAECgUICQAAAA==.Amorae:BAAANQADCggICAAAAA==.',
An='Anabel:BAAANQAECgEIAQAAAA==.Andorsi:BAAANQADCggIEAAAAA==.',
Ar='Arachne:BAAANQAECgYIDwAAAA==.Aracianluz:BAAANQADCgcICwABNQAECgEJAQAEAAAAAA==.Arak:BAAANQADCgIIAgAAAA==.Arce:BAAANQADCgcIDAAAAA==.Arysia:BAAANQAECgEJAQAAAA==.Aryya:BAAANQADCgIIAgAAAA==.',
As='Ascaris:BAAANQAECgQJCAAAAA==.',
Av='Avalan:BAAANQAECgYJEQAAAA==.Avanolatwo:BAAANQADCgYJBgABNQAECggJGwAIALARAA==.Avashammy:BAABNQAECoEbAAMIAAgKsBEeRADcAQAIAAgKsBEeRADcAQAKAAYKXgy2ZQBkAQAAAA==.Aviendah:BAAANQAECgMIBAAAAA==.',
Aw='Awsomeonet:BAAANQAECggICAAAAA==.',
Az='Azdfghop:BAACNQAFFIELAAMLAAYKRROwBQCMAQALAAUKYQ+wBQCMAQAMAAIK6BySDAC/AAA1AAQKgR4AAwsACQrtHtsNAMkCAAsACQqpHdsNAMkCAAwAAQryJsHZAHEAAAAA.Azzinotica:BAAANQADCgEIAQAAAA==.',
Ba='Baalsanaro:BAAANQADCggIDQABNQADCggIFgAEAAAAAA==.Babeshot:BAAANQAECgYJEQAAAA==.Baelgar:BAAANQAECgMIAwAAAA==.',
Bi='Biggy:BAAANQADCgIIAgAAAA==.Bignose:BAAANQADCgQIBAABNQAECgkJGgANAKYmAA==.',
Bl='Blaaze:BAAANQADCgYIBgAAAA==.Blackfrost:BAAANQAECggICAAAAA==.Blaiddyd:BAAANQAECgUIDQAAAA==.Bloodboi:BAAANQADCgYJBgAAAA==.',
Br='Brandawn:BAAANQADCgYJFgAAAA==.',
Bu='Burndasheep:BAAANQAECgYJEAAAAA==.',
['Bæ']='Bæyy:BAAANQAECgQIBAAAAA==.',
Ca='Caspias:BAEANQADCggJEgAAAA==.Caylynn:BAAANQADCggIJAAAAA==.Caynelin:BAAANQADCgIIAgAAAA==.',
Ch='Chaoslock:BAAANQAECgYIEgAAAA==.Chetter:BAAANQAECggJBgAAAA==.Chickpea:BAAANQADCggIFwAAAA==.',
Co='Cocytus:BAAANQADCgQIDQAAAA==.Colbith:BAAANQAECgUICQAAAA==.Cordelvo:BAAANQAECgMJAwAAAA==.Cordragu:BAAANQAECgYJDwAAAA==.Corraa:BAAANQADCgEIAQAAAA==.',
Cr='Crakum:BAAANQAECgUJDQAAAA==.Crinn:BAABNQAECoEWAAMOAAcKuArfPwCWAQAOAAcKuArfPwCWAQAJAAIKrgUhZABPAAAAAA==.Crizmon:BAAANQAECgcJEgAAAA==.',
Da='Damorthyx:BAAANQAECgUIDAAAAA==.Darazarke:BAACNQAFFIELAAIPAAUKlgqEBQCDAQAPAAUKlgqEBQCDAQA1AAQKgR0AAg8ACQpGFsUOAG4CAA8ACQpGFsUOAG4CAAAA.Darkquill:BAAANQAECgYJDQAAAA==.Daspoof:BAAANQADCgYJBgAAAA==.Dayquil:BAEANQADCgcIBwABNQAECggJDAAEAAAAAA==.',
De='Deadaddie:BAAANQADCgcIBwAAAA==.Deamoneyes:BAAANQAECgQIBgAAAA==.Deathkauf:BAAANQADCgUIBwAAAA==.Dezatra:BAAANQADCgcIBgAAAA==.',
Dh='Dhonaan:BAAANQADCgEIAQAAAA==.',
Di='Dieselcon:BAABNQAECoEaAAIGAAgKkA5xFwCtAQAGAAgKkA5xFwCtAQAAAA==.Diprivan:BAAANQAECgYIDwAAAA==.',
Do='Dolobrik:BAAANQABCgYIBwAAAA==.Domdog:BAABNQAECoEWAAIQAAcKgQj6tQCYAQAQAAcKgQj6tQCYAQAAAA==.Domína:BAAANQAECgQJBgAAAA==.Dontforget:BAAANQAECgEIAQAAAA==.Doomdealer:BAAANQADCgcICAAAAA==.Doomed:BAAANQAECgQICwAAAA==.Dottee:BAAANQAECggIAwAAAA==.Dougwalker:BAAANQADCgIIAgAAAA==.',
Dr='Dracodaddy:BAAANQADCgIIAgAAAA==.Draftymonk:BAAANQAECgQIBgABNQAECgYJCAAEAAAAAA==.Drage:BAAANQAECgYJDAAAAA==.Drax:BAAANQAECgYIDwAAAA==.Dritzzagain:BAAANQAECgIJAQAAAA==.',
Dw='Dwreck:BAAANQAECgUICgAAAA==.',
Ed='Ediann:BAAANQADCgcICgAAAA==.',
El='Elandrus:BAAANQADCgcICQABNQAECgYIGQAQADESAA==.Eldarine:BAAANQADCgUIBQAAAA==.',
Em='Emmara:BAAANQAECgUIDAAAAA==.',
Er='Erata:BAAANQAECgIIAwAAAA==.Erlik:BAAANQADCgEIAQAAAA==.Erzakzaktraz:BAAANQADCgYIBgABNQADCgcIBgAEAAAAAA==.',
Ev='Evullight:BAAANQADCgEJAQAAAA==.',
Ez='Ezlok:BAAANQAECgYIDgAAAA==.',
Fa='Falerin:BAAANQAECgcJDAAAAA==.',
Fe='Feenex:BAAANQAECgEJAQAAAA==.',
Fi='Firedealer:BAABNQAECoEbAAILAAgKEA8mHwDuAQALAAgKEA8mHwDuAQAAAA==.',
Fl='Flappy:BAAANQAECgIIAgABNQAECgYJEAAEAAAAAA==.Flashmaster:BAAANQAECgQJAwAAAA==.Flawlessheal:BAAANQADCgMIAwAAAA==.Fluffybutt:BAAANQADCggIDQAAAA==.',
Fo='Fossora:BAAANQADCgcIBgAAAA==.',
Fr='Freyiah:BAAANQADCgYJBgAAAA==.',
Ga='Galath:BAAANQAECgUJCAABNQAECgMIAwAEAAAAAA==.Gameover:BAAANQABCgEIAgAAAA==.',
Ge='Gerree:BAAANQADCgYICgAAAA==.Gerry:BAAANQADCgQIBQABNQAECgYICQAEAAAAAA==.',
Gg='Ggkando:BAAANQAECgMIAwAAAA==.',
Gi='Gingerail:BAAANQADCgcIEgAAAA==.',
Gl='Glory:BAAANQAECgQIBwAAAA==.',
Go='Goochsquirts:BAAANQAECgYJDwAAAA==.Govna:BAAANQADCggIFAAAAA==.',
Gr='Grakkaem:BAAANQAECgMJBAAAAA==.Gravedygger:BAAANQAECgYJEQAAAA==.Greenfear:BAAANQABCgQJBAAAAA==.Grenswood:BAAANQAECgYJDAAAAA==.Grimmkin:BAAANQAECggJEgAAAA==.Grind:BAAANQADCgYJBwABNQAECgUJBgAEAAAAAA==.Growl:BAAANQADCgUJBQAAAA==.Grumbo:BAAANQADCgcIBgAAAA==.',
Gu='Guuldurak:BAAANQADCgcIBgAAAA==.',
Ha='Hailcat:BAAANQADCgUJBgABNQAECgcIEAAEAAAAAA==.Handivhe:BAAANQADCgYJBgAAAA==.Hasew:BAABNQAECoEWAAIMAAYKixYpaAC1AQAMAAYKixYpaAC1AQAAAA==.',
He='He:BAAANQADCggJFAAAAA==.Helpimßlind:BAAANQAECgIIAwAAAA==.Hera:BAABNQAECoEdAAIMAAgKsCanBgCBAwAMAAgKsCanBgCBAwAAAA==.Heyner:BAAANQAECgYJEgAAAA==.',
Hi='Hinral:BAABNQAECoEbAAIRAAgKIiJNBQAJAwARAAgKIiJNBQAJAwAAAA==.',
Ho='Holyluz:BAAANQAECgEJAQAAAA==.',
Hy='Hymns:BAAANQAECggIAgAAAA==.',
['Hë']='Hëll:BAAANQAECgcIEAAAAA==.',
Il='Illaynne:BAAANQAECgQJCgAAAA==.',
Im='Imani:BAABNQAECoEdAAISAAgKzAq6DgAEAgASAAgKzAq6DgAEAgAAAA==.Immensepain:BAAANQAECgEJAQAAAA==.',
In='Inoshikacho:BAAANQAECgYJEQAAAA==.',
Ir='Irishmecha:BAABNQAECoEdAAITAAgK9RzwDgCfAgATAAgK9RzwDgCfAgAAAA==.Irishpaws:BAAANQAECgEIAQAAAA==.Ironshot:BAAANQADCggIBgAAAA==.',
It='Itharillys:BAAANQAECgYJDwAAAA==.',
Ja='Jaadu:BAAANQADCgQJBAAAAA==.Jangus:BAAANQAECgIJAgABNQAECgUJBgAEAAAAAA==.',
Je='Jeennkiins:BAAANQADCgYIBgABNQAECgMIAwAEAAAAAA==.Jenifur:BAAANQAECgIJAgABNQAECgYJEQAEAAAAAA==.Jezzako:BAAANQADCggJGQAAAA==.',
Jo='Johali:BAAANQAECgEJAQAAAA==.Jozan:BAAANQADCgYJDAAAAA==.',
Ju='Justise:BAAANQADCgIIAgABNQADCgYJCwAEAAAAAA==.',
['Jö']='Jöhnblaze:BAAANQAECgcJEwAAAA==.',
Ka='Kaga:BAAANQADCgEJAQABNQAECgYJEAAEAAAAAA==.Kailys:BAAANQAECgUIEgAAAA==.Kaisana:BAAANQAECgYICwAAAA==.Kaishias:BAAANQAECgYJBgAAAA==.Kaldrek:BAAANQAECgMIAwAAAA==.Kandoh:BAAANQADCgYICwABNQAECgMIAwAEAAAAAA==.Kankuró:BAAANQAFFAEJAQAAAA==.Karelleira:BAAANQADCgUIBQAAAA==.Katighthole:BAAANQAECgIIAwAAAA==.',
Ki='Killahmike:BAAANQAECgQIBgAAAA==.Killudead:BAAANQADCgQIBAAAAA==.Kishana:BAAANQADCgcIBgAAAA==.',
Ko='Kodetra:BAAANQAECgMIAwAAAA==.Kolgrim:BAAANQAECgUJCAAAAA==.Korvuk:BAAANQAECgQIBAAAAA==.',
Kr='Krom:BAAANQAECggIDAAAAA==.Krysta:BAAANQAECgYJEQAAAA==.',
Ky='Kynris:BAAANQADCggJEAABNQAECgYIGQAQADESAA==.',
La='Lancewh:BAAANQADCgcIDAAAAA==.Lanciwinluna:BAAANQADCgQIBAAAAA==.Lancywinelia:BAAANQADCgQIBgAAAA==.',
Le='Legg:BAAANQABCgMIAwAAAA==.Legolâs:BAAANQADCgUIBQAAAA==.Leviathañ:BAAANQADCgIIAgABNQAECgUICgAEAAAAAA==.Lezene:BAAANQADCgYJEgAAAA==.',
Li='Linstriker:BAAANQAECgYJEQABNQAFFAMIBQAIAIckAA==.',
Lo='Lorette:BAAANQAECgcJEAAAAA==.Lornarcos:BAAANQABCgYJBwAAAA==.',
Lu='Lucethegoose:BAAANQADCgQIBAAAAA==.Lunate:BAAANQADCgQIBAABNQAECgYJDwAEAAAAAA==.Lunavere:BAAANQADCgQIBQAAAA==.',
Ma='Machotedan:BAAANQAECgYJEgAAAA==.Macmittens:BAAANQADCgUJBwAAAA==.Mamadrag:BAAANQAECgIIAwAAAA==.Managua:BAAANQADCgEJAQAAAA==.Mandwa:BAAANQADCggJGAABNQAECgYJEAAEAAAAAA==.Mario:BAAANQAECgQJBQAAAA==.Masivewin:BAAANQAECgEIAQAAAA==.Mastashifta:BAAANQADCgYJGQAAAA==.Mataa:BAABNQAECoEZAAIQAAYKMRIhvACKAQAQAAYKMRIhvACKAQAAAA==.Matryoshka:BAAANQADCgQICAAAAA==.Maxxim:BAAANQADCgYIEAAAAA==.Mayihmpurleg:BAAANQADCgYJBgABNQAECggJGwALABAPAA==.',
Me='Meta:BAAANQADCggIDgAAAA==.',
Mi='Mishaps:BAAANQABCgEIAQAAAA==.Missaoife:BAAANQABCgEIAQAAAA==.Mistaya:BAAANQADCgUIBQABNQAECgQICQAEAAAAAA==.Mists:BAAANQAECgMIAwAAAA==.Miththrawndo:BAAANQAECgcIEwAAAA==.',
Mo='Mohrgyn:BAAANQABCgEIAQAAAA==.Momjeans:BAAANQAECggJEgAAAA==.',
Mu='Muu:BAAANQADCgYICAAAAA==.',
My='Mydaan:BAAANQADCgEIAQAAAA==.Mythunsarian:BAAANQADCggIDwAAAA==.',
['Má']='Mákï:BAAANQAECgQJBwAAAA==.',
['Mä']='Mäylä:BAAANQAECgMIBAAAAA==.',
['Mí']='Míst:BAABNQAECoEbAAIFAAgKWhRxTwAXAgAFAAgKWhRxTwAXAgAAAA==.',
Na='Narlis:BAAANQAECgcJEwAAAA==.',
Ne='Nephie:BAAANQAECgYICwAAAA==.Nezqk:BAABNQAECoEdAAMOAAgK/BlxIABgAgAOAAgKPhhxIABgAgAUAAgKlROVLwDoAQAAAA==.',
Ni='Niano:BAAANQABCgIIAgAAAA==.',
Nm='Nmnenthe:BAAANQAECgQJCAAAAA==.',
No='Notrealword:BAAANQAECgIIAgABNQAECgYJFgAMAIsWAA==.Noxluminous:BAAANQABCgIIAgAAAA==.',
Ob='Obin:BAAANQAECgUJCwAAAA==.',
Oc='Occasionally:BAAANQAECgIIAgAAAA==.',
Ok='Okukoy:BAAANQABCgEIAQAAAA==.',
Om='Ominious:BAAANQAECgYJEQABNQABCgEIAQAEAAAAAA==.Omnius:BAAANQAECgUIDQAAAA==.',
Ow='Owendriel:BAAANQAECgcICwAAAA==.',
Pa='Paleigh:BAAANQABCgYIDQAAAA==.Pandress:BAAANQAECgMIAwAAAA==.Pankake:BAAANQADCgIIAgABNQAECgYJEgAEAAAAAA==.Paralysis:BAABNQAECoEcAAIVAAgKGxHBHAAaAgAVAAgKGxHBHAAaAgAAAA==.',
Pe='Peetza:BAAANQADCgYIBgABNQAECgYJEgAEAAAAAA==.Peryite:BAAANQAECgYJEgAAAA==.',
Ph='Phaedrana:BAAANQAECgMIAwAAAA==.',
Pi='Pisscat:BAAANQAECgIIAwAAAA==.',
Po='Pocketdragon:BAABNQAECoEZAAMWAAcKaRAiCwAdAQAXAAcKxgyiFQCTAQAWAAUKDg8iCwAdAQAAAA==.',
Pr='Prideindeath:BAAANQADCgUIBQAAAA==.Promiscuity:BAAANQAECgQJBQAAAA==.Prængle:BAAANQADCgYIAwAAAA==.',
Ps='Psoas:BAAANQAECgYJDwAAAA==.Psypriest:BAEANQAECgcIEAABNQAFFAUIDAABAP4KAA==.',
Qu='Quaichang:BAAANQADCgYIBgAAAA==.',
Ra='Rabbi:BAAANQAECgYIDQAAAA==.Radaster:BAAANQABCgEIAQAAAA==.Rahfna:BAAANQADCgcIDwAAAA==.Railænu:BAAANQADCggIDgAAAA==.Rainmist:BAAANQADCgYIBgAAAA==.',
Re='Reesespbc:BAAANQAECgYJDQAAAA==.Reina:BAAANQADCggJFQABNQAECgYJEQAEAAAAAA==.Reinz:BAAANQADCgYIBgAAAA==.Rektagar:BAAANQAECgcJEgABNQAFFAYJDAAMAIQZAA==.Ressandra:BAAANQADCgMIBgAAAA==.Rezo:BAAANQAECgEIAgAAAA==.',
Ri='Riverarose:BAAANQADCggIFAAAAA==.',
Ro='Roar:BAAANQADCgEIAQABNQAECgUJBgAEAAAAAA==.',
Ry='Rysi:BAAANQADCgQIBAAAAA==.',
['Rò']='Ròs:BAABNQAECoEdAAIGAAgKQh8ICADFAgAGAAgKQh8ICADFAgAAAA==.',
['Rö']='Rös:BAAANQADCgEIAQABNQAECggIHQAGAEIfAA==.',
Sa='Saberie:BAAANQADCggJFgABNQADCgMIBgAEAAAAAA==.Salaria:BAAANQAECgUJCAAAAA==.Salina:BAEANQAECgYJCwAAAA==.Sandstique:BAAANQAECgYJEAAAAA==.Sandweaver:BAAANQADCgcIBwAAAA==.Sanjira:BAAANQADCgYJBgAAAA==.Sarlak:BAAANQAECgcJEgAAAA==.Sarusuby:BAABNQAECoEbAAIYAAgKrwysEACBAQAYAAgKrwysEACBAQAAAA==.Satae:BAAANQAECgYJEgAAAA==.',
Sc='Schufft:BAAANQAECgQICQAAAA==.Scottydh:BAAANQADCgYJBgABNQAECggJGQAUAIQgAA==.Scottymac:BAABNQAECoEZAAIUAAgKhCCYEADkAgAUAAgKhCCYEADkAgAAAA==.Scottypal:BAAANQAECgEIAQABNQAECggJGQAUAIQgAA==.',
Se='Seba:BAAANQAECgEIAgAAAA==.Seetah:BAAANQAECgcJDQAAAA==.',
Sh='Shadaddy:BAAANQAECgYJEgABNQADCgcIBwAEAAAAAA==.Shal:BAAANQAECgMIBgAAAA==.Shamanluz:BAAANQADCgIIAgABNQAECgEJAQAEAAAAAA==.Shamommy:BAAANQADCgUIBAAAAA==.Shamtaz:BAAANQABCgEIAQAAAA==.Shimmerstar:BAABNQAECoEZAAIFAAkKTRzQMwCHAgAFAAkKTRzQMwCHAgAAAA==.Shroomgirl:BAAANQAECgUIBQAAAA==.',
Si='Silexe:BAAANQAECgIIAwAAAA==.',
Sl='Slipperyboi:BAAANQAECgQICQAAAA==.Slÿ:BAAANQAECgIIAgAAAA==.',
Sm='Smokintotems:BAAANQABCgEIAQAAAA==.',
So='Solarion:BAAANQAECgQJBQABNQAECgYIDgAEAAAAAA==.Soldraca:BAAANQADCgYIEQAAAA==.',
St='Stats:BAAANQAECgUJBgAAAA==.Stutters:BAAANQAECgUJDAAAAA==.',
Su='Sudachi:BAAANQADCgYIBgABNQAECgkKHAAZAKcgAA==.Sunnyräy:BAAANQADCgUJBQAAAA==.Suthrheimr:BAAANQAECgYICQAAAA==.',
['Sý']='Sýndrá:BAAANQAECgUJDAAAAA==.',
Ta='Takafune:BAAANQADCgQIBQAAAA==.Talysiah:BAAANQAECgQICQAAAA==.Tavok:BAAANQAECgUIDAAAAA==.Tazbis:BAAANQAECgIIAgAAAA==.',
Te='Teishuku:BAABNQAECoEbAAIFAAgK1w6KYgDWAQAFAAgK1w6KYgDWAQAAAA==.Teusday:BAAANQAECgQJCwAAAA==.',
Th='Thiux:BAAANQAECgUICgAAAA==.Thoeleden:BAAANQAECgEIAgABNQAFFAMIBQAIAIckAA==.Thotsnprayrs:BAAANQADCggICAABNQAECgQICwAEAAAAAA==.Thrappy:BAAANQAECgYJEAAAAA==.Thryna:BAAANQADCgEIAQAAAA==.',
Ti='Tinsoon:BAAANQADCgYIFAAAAA==.Tintaglia:BAABNQAECoEbAAMaAAgKwhSwOgAzAgAaAAgKwhSwOgAzAgAbAAEKZBH+IQA3AAABNQAECgQJBQAEAAAAAA==.Tirtun:BAABNQAECoEbAAIcAAgK7B5GAgDqAgAcAAgK7B5GAgDqAgAAAA==.',
Tr='Triggeer:BAAANQAECgUICQAAAA==.Trolldemort:BAAANQADCgYIBgABNQAECggIGwAaAEAaAA==.',
Tu='Tully:BAAANQAECgMJAwAAAA==.Tunkhan:BAAANQABCgYIBgAAAA==.',
Tw='Twelvekill:BAABNQAECoEdAAIMAAgKDh+1HADOAgAMAAgKDh+1HADOAgAAAA==.',
Ty='Tyliaa:BAAANQAECgcIEQABNQAECgIIAwAEAAAAAA==.',
Ul='Ultramon:BAAANQAECgQJBAAAAA==.',
Un='Unbreakabull:BAAANQADCgEIAQAAAA==.Unwell:BAAANQAECgYIBgABNQAECggIGAAdAIkdAA==.',
Ur='Urgoochness:BAAANQADCgQIBAAAAA==.Urikhai:BAAANQADCggIAgAAAA==.',
Va='Vainglorious:BAAANQADCggIEwABNQAECgQIBwAEAAAAAA==.Valanora:BAAANQAECgYJEQAAAA==.Valerie:BAAANQADCggIEgAAAA==.Valinaxius:BAAANQADCgYJFgAAAA==.Vapturov:BAAANQADCgYJFgAAAA==.',
Ve='Veeks:BAAANQAECgYJDwAAAA==.Velikirn:BAAANQAECgQJBAAAAA==.Venefica:BAAANQAECgEJAQAAAA==.Verdracee:BAAANQABCgMIBAABNQAECgEIAQAEAAAAAA==.Versø:BAAANQAECgYJDwAAAA==.Veryzi:BAAANQAECgEIAgAAAA==.',
Vi='Vine:BAAANQADCgIIAgAAAA==.',
Vl='Vlyrae:BAAANQADCgMIAwABNQABCgEIAQAEAAAAAA==.',
Vo='Voidhearted:BAABNQAECoEcAAIDAAgK/Ag9IgClAQADAAgK/Ag9IgClAQAAAA==.Vonzuo:BAAANQAECgIIAgAAAA==.',
Vu='Vukodlak:BAAANQADCgYJBgABNQAECgQJBQAEAAAAAA==.',
Wa='Warriorwuu:BAAANQABCgIIAgAAAA==.',
We='Werkajerk:BAAANQADCggICAABNQAFFAMIBQAIAIckAA==.Werkjathal:BAACNQAFFIEFAAIIAAMKhyQjBwBHAQAIAAMKhyQjBwBHAQA1AAQKgR8AAggACQqvJkUAAO4DAAgACQqvJkUAAO4DAAAA.',
Wi='Wibbles:BAAANQADCgcICwAAAA==.Wigarthan:BAAANQADCgEIAQAAAA==.',
Wo='Wolfblitzer:BAAANQAECgYJEQAAAA==.Worldbane:BAAANQAECgYIDQAAAA==.',
Wt='Wtyczka:BAAANQABCgUIBgAAAA==.',
Wu='Wuulock:BAAANQABCgEJAQAAAA==.',
Xa='Xanakmando:BAAANQADCgYJEwAAAA==.Xanthos:BAAANQADCgIIAgAAAA==.',
Xi='Xianyu:BAAANQAECgMIBgAAAA==.',
Ya='Yarian:BAAANQAECgMIAwAAAA==.',
Yu='Yuck:BAAANQAECgIIAgABNQAFFAMIBQAIAIckAA==.',
Za='Zachhunter:BAACNQAFFIEMAAMMAAYKhBmuAwCRAQAMAAQKNB6uAwCRAQALAAMKwg3wCwDoAAA1AAQKgSQAAwsACQpQI0gLAO8CAAsACAr2IkgLAO8CAAwABgojHS1qAK8BAAAA.Zachmage:BAAANQADCgYIBgAAAA==.Zan:BAABNQAECoEdAAMKAAgKhB/jGgDWAgAKAAgKhB/jGgDWAgAIAAIKNw+CtAB6AAAAAA==.',
Zi='Zinar:BAAANQABCggJDwAAAA==.',
Zu='Zultrix:BAAANQADCgYJDwAAAA==.',
Zy='Zylaeri:BAAANQAECgUJBwAAAA==.',
['Éo']='Éowyn:BAAANQADCgEIAQAAAA==.',
['Ël']='Ëllër:BAAANQAECgEJAQAAAA==.',
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
