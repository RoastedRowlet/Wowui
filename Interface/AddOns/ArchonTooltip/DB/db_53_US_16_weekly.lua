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

local lookup = {'Priest-Holy','Druid-Restoration','Priest-Shadow','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Druid-Balance','DeathKnight-Frost','Warrior-Fury','Warrior-Arms','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Monk-Brewmaster','Mage-Arcane','Mage-Fire','DeathKnight-Unholy','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Warlock-Affliction','Warlock-Demonology','Shaman-Enhancement','Rogue-Outlaw','Monk-Mistweaver','Druid-Guardian','DeathKnight-Blood','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Discipline','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Monk-Windwalker',}
local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abavok:BAAANQADCgcIBwAAAA==.Absoul:BAABNQAECoEwAAIBAAkK3hhfKwB9AgABAAkK3hhfKwB9AgAAAA==.Abyssian:BAAANQAECgUIBQAAAA==.',
Ac='Acedia:BAAANQAECgUICQAAAA==.',
Ad='Adellas:BAABNQAECoEfAAICAAgKEBYbGAAvAgACAAgKEBYbGAAvAgAAAA==.Adern:BAABNQAECoElAAIDAAkK5hdREQCrAgADAAkK5hdREQCrAgAAAA==.Adon:BAAANQADCgUIBQABNQADCgYJBgAEAAAAAA==.Adonn:BAABNQAECoEfAAMFAAgKeBsGSABwAgAFAAgKeBsGSABwAgAGAAIKlQv5TgBNAAAAAA==.Adonshadriel:BAAANQADCgYJBgAAAA==.',
Ae='Aelali:BAAANQAECgYICgAAAA==.',
Af='Afador:BAAANQADCggJCAABNQAECgUICQAEAAAAAA==.',
Al='Aladestar:BAABNQAECoEdAAMHAAgKCxqHJwBbAgAHAAgKCxqHJwBbAgACAAQKVxXkNgD6AAAAAA==.Albinodh:BAAANQAECgEIAQAAAA==.Alderleise:BAAANQADCgcIBwAAAA==.Alexein:BAABNQAECoEhAAIIAAkKIBQVIwAgAgAIAAkKIBQVIwAgAgAAAA==.',
Am='Amets:BAAANQAECgYICgAAAA==.Amorae:BAAANQADCggIDwAAAA==.',
An='Anabel:BAAANQAECgEIAQAAAA==.Andorsi:BAAANQAECgEIAQAAAA==.',
Ar='Arachne:BAAANQAECgYIDwAAAA==.Aracianluz:BAAANQADCgcICwABNQAECgEJAQAEAAAAAA==.Arak:BAAANQADCgIIAgAAAA==.Arce:BAAANQADCggIDwABNQAECgUIEAAEAAAAAA==.Arysia:BAAANQAECgEIAQAAAA==.Aryya:BAAANQADCgIIAgAAAA==.',
As='Ascaris:BAAANQAECgQICgAAAA==.',
Av='Avalan:BAABNQAECoEcAAQJAAgKpBsWDACsAQAKAAgKFhaZWQA6AgALAAYKLhw4EADGAQAJAAYKIRgWDACsAQAAAA==.Avanolatwo:BAAANQADCgYIBgABNQAECggIHwAMAIMUAA==.Avashammy:BAABNQAECoEfAAMMAAgKgxSPRgD5AQAMAAgKgxSPRgD5AQANAAYKDw2AeQBfAQAAAA==.Aviendah:BAAANQAECgMIBAAAAA==.',
Aw='Awsomeonet:BAAANQAECggICAAAAA==.',
Az='Azdfghop:BAACNQAFFIEMAAMOAAcKFRI+BQDCAQAOAAYKpQ4+BQDCAQAPAAIK6BwXEwC4AAA1AAQKgSEAAw4ACQpjH6QRALACAA4ACQofHqQRALACAA8AAQryJjz9AG8AAAAA.Azzinotica:BAAANQADCgIIAgAAAA==.',
Ba='Baalsanaro:BAAANQADCggIDQABNQADCggIHgAEAAAAAA==.Babeshot:BAABNQAECoEcAAIPAAgKEwpyagDlAQAPAAgKEwpyagDlAQAAAA==.Baelgar:BAAANQAECgMIAwAAAA==.',
Bi='Bigbear:BAAANQADCggICAABNQAECgcIFgAQAH0TAA==.Biggy:BAAANQADCgIIAgAAAA==.Bignose:BAAANQADCgQIBAABNQAFFAQIBQARACAmAA==.Binksy:BAAANQAECgUIBQAAAA==.',
Bl='Blaaze:BAAANQADCgYIBgAAAA==.Blackfrost:BAAANQAECggICgAAAA==.Blaiddyd:BAAANQAECgYIEwAAAA==.Bloodboi:BAAANQADCgYIBgAAAA==.',
Br='Brandawn:BAAANQADCggIGAAAAA==.',
Bu='Burndasheep:BAABNQAECoEbAAMSAAgKOhKNjwAfAgASAAgKOhKNjwAfAgATAAEKew1/CQBBAAAAAA==.',
['Bæ']='Bæyy:BAAANQAECgQICAAAAA==.',
Ca='Caspias:BAEANQADCggJEgAAAA==.Caylynn:BAAANQADCggIKwAAAA==.Caynelin:BAAANQAECgEIAQAAAA==.',
Ch='Chaoslock:BAABNQAECoEWAAIQAAcKfRMNFADCAQAQAAcKfRMNFADCAQAAAA==.Chetter:BAAANQAECggJBgAAAA==.Chicknfajita:BAAANQAECgcICQAAAA==.Chickpea:BAAANQADCggIGwAAAA==.',
Co='Cocytus:BAAANQADCgQIDQAAAA==.Colbith:BAAANQAECgUICQAAAA==.Corblixx:BAAANQAECgEIAQAAAA==.Cordaddy:BAAANQAECgEIAQABNQAECggIGAAMAFElAA==.Cordelvo:BAAANQAECgUICAAAAA==.Cordragu:BAABNQAECoEYAAIMAAgKUSVGCgBPAwAMAAgKUSVGCgBPAwAAAA==.Cordran:BAAANQAECgEIAQABNQAECggIGAAMAFElAA==.Corraa:BAAANQADCgEIAQAAAA==.',
Cr='Crakum:BAAANQAECgYIEwAAAA==.Crinn:BAABNQAECoEbAAMUAAcKjA1zTgByAQAUAAcKjA1zTgByAQAIAAIKrgU+eQBNAAAAAA==.Crizmon:BAABNQAECoEbAAIIAAgKjyGSDgDnAgAIAAgKjyGSDgDnAgAAAA==.',
Da='Damorthyx:BAAANQAECgYIEgAAAA==.Darazarke:BAACNQAFFIEQAAIVAAUKWxG9BgCaAQAVAAUKWxG9BgCaAQA1AAQKgSAAAhUACQqEFnoRAGUCABUACQqEFnoRAGUCAAAA.Darkquill:BAAANQAECgYIEwAAAA==.Daspoof:BAAANQADCgYIBgAAAA==.Dayquil:BAEANQADCgcIBwAAAA==.',
De='Deadaddie:BAAANQADCgcIBwAAAA==.Deamoneyes:BAAANQAECgQIBgAAAA==.Deathkauf:BAAANQADCgUIBwAAAA==.Demolitions:BAAANQAECggICAAAAA==.Dezatra:BAAANQADCgcIBgAAAA==.',
Dh='Dhonaan:BAAANQADCgEIAQAAAA==.',
Di='Dieselcon:BAABNQAECoEgAAIGAAgKbRG8HACrAQAGAAgKbRG8HACrAQAAAA==.Diprivan:BAABNQAECoEXAAMWAAgKRRjmGQBbAgAWAAgKRRjmGQBbAgAXAAMK2hSANADWAAAAAA==.',
Do='Dolobrik:BAAANQABCgYIBwAAAA==.Domdog:BAABNQAECoEdAAISAAcKXgmszgCXAQASAAcKXgmszgCXAQAAAA==.Domína:BAAANQAECgQIBgAAAA==.Dontforget:BAAANQAECgEIAQAAAA==.Doomdealer:BAAANQAECgUIBQAAAA==.Doomed:BAAANQAECgQIDwAAAA==.Doonya:BAAANQADCgEIAQABNQADCgUIDQAEAAAAAA==.Dottee:BAAANQAECggIAwAAAA==.Dougwalker:BAAANQADCgIIAgAAAA==.',
Dr='Dracodaddy:BAAANQADCgIIAgAAAA==.Draftymonk:BAAANQAECgQICAABNQAECgYICgAEAAAAAA==.Drage:BAAANQAECgcIEwAAAA==.Drax:BAABNQAECoEVAAMYAAYKbgwkCwBqAQAYAAYKbgwkCwBqAQAZAAIKVgSG9QBeAAAAAA==.Dreadgar:BAAANQAECgEIAQABNQAECgYIEgAEAAAAAA==.Dritzzagain:BAAANQAECgIIAgAAAA==.Dritzzcat:BAAANQADCgEIAQAAAA==.',
Dw='Dwreck:BAAANQAECgUICgAAAA==.',
Ed='Ediann:BAAANQAECgEIAQAAAA==.',
El='Elandrus:BAAANQAECgQIBAABNQAECgcIHwASABgUAA==.Eldarine:BAAANQADCgUIBQAAAA==.',
Em='Emmara:BAAANQAECgUIEQAAAA==.',
En='Enitar:BAAANQADCgcIBwABNQAECggIGwASADoSAA==.',
Er='Erata:BAAANQAECgIIBQAAAA==.Erlik:BAAANQADCgMIBAAAAA==.Erzakzaktraz:BAAANQADCgYIBgABNQADCgcIBgAEAAAAAA==.',
Ev='Evullight:BAAANQADCgEJAQAAAA==.',
Ez='Ezlok:BAAANQAECgYIEgAAAA==.',
Fa='Falerin:BAAANQAECggIEQAAAA==.',
Fe='Feenex:BAAANQAECgQIBQAAAA==.',
Fi='Fillorey:BAAANQADCggICAABNQAECgcIHwASABgUAA==.Firedealer:BAABNQAECoEfAAMOAAgKthABJgDTAQAOAAgKEA8BJgDTAQAPAAQKAhWiuAAmAQAAAA==.',
Fl='Flappy:BAAANQAECgIIBAABNQAECggIGwAMANASAA==.Flashmaster:BAAANQAECgQIBAAAAA==.Flawlessheal:BAAANQADCgMIAwAAAA==.Fluffybutt:BAAANQADCggIDQAAAA==.',
Fo='Fossora:BAAANQADCgcIBgAAAA==.',
Fr='Freyiah:BAAANQADCgYJBgAAAA==.',
Fy='Fyatre:BAAANQAECgMIAwAAAA==.',
Ga='Galath:BAAANQAECgUJCAABNQAECgMIAwAEAAAAAA==.',
Ge='Gerree:BAAANQADCgYICgAAAA==.Gerry:BAAANQADCgcIDAABNQAECgcIEAAEAAAAAA==.',
Gg='Ggkando:BAAANQAECgQIBwAAAA==.',
Gi='Gingerail:BAAANQAECgQIBAAAAA==.',
Gl='Glory:BAAANQAECgUIDAAAAA==.',
Go='Goochsquirts:BAAANQAECgYIEwAAAA==.Govna:BAAANQADCggIFAAAAA==.',
Gr='Grakkaem:BAAANQAECgMJBAAAAA==.Grannet:BAAANQADCgMIAwAAAA==.Gravedygger:BAABNQAECoEcAAIPAAgKWBTlSQBDAgAPAAgKWBTlSQBDAgAAAA==.Greenfear:BAAANQABCgQIBAAAAA==.Grenswood:BAAANQAECgcIDQAAAA==.Grimmkin:BAABNQAECoEZAAIaAAkKnhWPCQCqAgAaAAkKnhWPCQCqAgAAAA==.Grind:BAAANQADCgYJBwABNQAECgUICQAEAAAAAA==.Growl:BAAANQADCgUJBQAAAA==.Grumbo:BAAANQADCgcIBgAAAA==.',
Gu='Guuldurak:BAAANQADCgcIBgAAAA==.',
Ha='Hailcat:BAAANQAECgMIAwABNQAECggIFQAZAJEJAA==.Handivhe:BAAANQADCgYIBgAAAA==.Hasew:BAABNQAECoEdAAIPAAcKeRo9TwAzAgAPAAcKeRo9TwAzAgAAAA==.',
He='He:BAAANQADCggIHAABNQAECgUIEAAEAAAAAA==.Helpimßlind:BAAANQAECgQIBQAAAA==.Hera:BAABNQAECoEhAAIPAAkKkCZeAQDnAwAPAAkKkCZeAQDnAwAAAA==.Heyner:BAABNQAECoEdAAIbAAgK4hF+BwAPAgAbAAgK4hF+BwAPAgAAAA==.',
Hi='Hinral:BAABNQAECoEfAAIcAAkKfyJzAwBcAwAcAAkKfyJzAwBcAwAAAA==.',
Ho='Holyluz:BAAANQAECgEJAQAAAA==.',
Hy='Hymns:BAAANQAECggIAgAAAA==.',
['Hë']='Hëll:BAABNQAECoEVAAMZAAgKkQm2hAB5AQAZAAcKwAm2hAB5AQAQAAEKRQhtcAAxAAAAAA==.',
Il='Illaynne:BAAANQAECgUIDgAAAA==.',
Im='Imani:BAABNQAECoEhAAIaAAkKVAvHDgA8AgAaAAkKVAvHDgA8AgAAAA==.Immensepain:BAAANQAECgEJAQAAAA==.',
In='Inoshikacho:BAAANQAECgYIEgAAAA==.Involio:BAAANQADCgEIAQAAAA==.',
Ir='Irishmecha:BAABNQAECoEhAAIWAAkKYh0MDQDlAgAWAAkKYh0MDQDlAgAAAA==.Irishpaws:BAAANQAECgEIAQAAAA==.Ironshot:BAAANQADCggIBgAAAA==.',
Is='Isaeus:BAAANQAECgEIAQAAAA==.',
It='Itharillys:BAABNQAECoEZAAIPAAcKPBKtagDlAQAPAAcKPBKtagDlAQAAAA==.',
Ja='Jaadu:BAAANQADCgQIBAAAAA==.Jangus:BAAANQAECgQIBgABNQAECgUICQAEAAAAAA==.',
Je='Jeefus:BAAANQAECgYIAgAAAA==.Jeennkiins:BAAANQADCgYIBgABNQAECgMIAwAEAAAAAA==.Jenifur:BAAANQAECgIJAgABNQAECggIGgABAGUhAA==.Jezzako:BAAANQADCggIIAAAAA==.',
Jo='Johali:BAAANQAECgQIBQAAAA==.Jozan:BAAANQADCgYIDAAAAA==.',
Ju='Justise:BAAANQADCgIIAgABNQADCgYJCwAEAAAAAA==.',
['Jö']='Jöhnblaze:BAABNQAECoEZAAIKAAgKHQzYhAC4AQAKAAgKHQzYhAC4AQAAAA==.',
Ka='Kaga:BAAANQADCgEJAQABNQAECggIGwASADoSAA==.Kailys:BAABNQAECoEdAAIGAAgKNA/IHgCVAQAGAAgKNA/IHgCVAQAAAA==.Kaisana:BAAANQAECgYICwAAAA==.Kaishias:BAAANQAECgcIDQAAAA==.Kaldrek:BAAANQAECgMIAwAAAA==.Kandoh:BAAANQADCggIEwABNQAECgQIBwAEAAAAAA==.Kankuró:BAABNQAECoEYAAIPAAgK7hzeMgCSAgAPAAgK7hzeMgCSAgAAAA==.Karelleira:BAAANQADCgUIBQAAAA==.Katighthole:BAAANQAECgIIBQAAAA==.',
Ki='Killahmike:BAAANQAECgQIBgAAAA==.Killudead:BAAANQAECgIIAgAAAA==.Kishana:BAAANQADCgcIBgAAAA==.',
Ko='Kodetra:BAAANQAECgMIBAAAAA==.Kolgrim:BAAANQAECgYICgAAAA==.Kong:BAAANQABCgYIBwAAAA==.Korvuk:BAAANQAECgQIBAAAAA==.',
Kr='Krom:BAAANQAECggIEQAAAA==.Krysta:BAABNQAECoEaAAMBAAgKZSHFIQCvAgABAAgKZSHFIQCvAgADAAEKOA0XZgAqAAAAAA==.',
Ky='Kynris:BAAANQADCggIEQABNQAECgcIHwASABgUAA==.',
La='Lanaal:BAAANQADCgEIAQAAAA==.Lancewh:BAAANQADCgcIDAAAAA==.Lanciwinluna:BAAANQADCgQIBAAAAA==.Lancywinelia:BAAANQADCgQIBgAAAA==.Lauryssa:BAAANQADCggICAAAAA==.',
Le='Legg:BAAANQABCgMIAwAAAA==.Legolâs:BAAANQADCgUIBQAAAA==.Leonora:BAAANQAECgMIAQAAAA==.Leviathañ:BAAANQADCgIIAgABNQAECgUICgAEAAAAAA==.Lezene:BAAANQADCggIFAAAAA==.',
Li='Linstriker:BAABNQAECoEYAAIdAAcKjh6WCQBqAgAdAAcKjh6WCQBqAgABNQAFFAUICgAMAAMiAA==.',
Lo='Lorette:BAABNQAECoEVAAMBAAgKOxowMABmAgABAAgKOxowMABmAgADAAQKmhTgNwARAQAAAA==.',
Lu='Lucethegoose:BAAANQADCgQIBAAAAA==.Luckynyx:BAAANQADCgMIAwAAAA==.Lunate:BAAANQADCgQIBAABNQAECgkJGwADAEEgAA==.Lunavere:BAAANQADCgQIBQAAAA==.',
Ma='Machotedan:BAABNQAECoEdAAIFAAgK9B3JPwCMAgAFAAgK9B3JPwCMAgAAAA==.Macmittens:BAAANQADCgcIDgAAAA==.Mamadrag:BAAANQAECgMIAwAAAA==.Managua:BAAANQADCgEIAQAAAA==.Mandwa:BAAANQADCggIGAABNQAECggIGwASADoSAA==.Mario:BAAANQAECgUICgAAAA==.Masivewin:BAAANQAECgEIAQAAAA==.Mastashifta:BAAANQADCggIGwAAAA==.Mataa:BAABNQAECoEfAAISAAcKGBREqwDhAQASAAcKGBREqwDhAQAAAA==.Matryoshka:BAAANQADCgUIDQAAAA==.Maxxim:BAAANQADCgYIFAAAAA==.Mayihmpurleg:BAAANQADCgYIBgABNQAECggIHwAOALYQAA==.',
Me='Meta:BAAANQADCggIDgAAAA==.',
Mi='Mistaya:BAAANQADCgUIBQABNQAECgQICQAEAAAAAA==.Mists:BAAANQAFFAQIBAAAAA==.Miththrawndo:BAABNQAECoEcAAIeAAgK6wwVSgCMAQAeAAgK6wwVSgCMAQAAAA==.',
Mo='Momjeans:BAABNQAECoEaAAISAAkKdxm1RwDQAgASAAkKdxm1RwDQAgAAAA==.',
Mu='Muu:BAAANQADCgYICAAAAA==.',
My='Mydaan:BAAANQADCgEIAQAAAA==.Mythunsarian:BAAANQADCggIDwAAAA==.',
['Má']='Mákï:BAAANQAECgUIDAAAAA==.',
['Mä']='Mäylä:BAAANQAECgYICgAAAA==.',
['Mí']='Míst:BAABNQAECoEiAAIFAAgKwBWsWwAvAgAFAAgKwBWsWwAvAgAAAA==.',
Na='Narlis:BAABNQAECoEfAAIUAAgKQyOVEQD5AgAUAAgKQyOVEQD5AgAAAA==.',
Ne='Nephie:BAAANQAECgYICwAAAA==.Nezqk:BAABNQAECoEhAAQUAAkKBRmpMAAQAgAUAAgKPhipMAAQAgAeAAgKlROBOwDUAQAIAAQK4hOgTgD0AAAAAA==.',
Ni='Niano:BAAANQABCgIIAgAAAA==.',
Nm='Nmnenthe:BAAANQAECgYIDgAAAA==.',
No='Notrealword:BAAANQAECgIIAgABNQAECgcIHQAPAHkaAA==.Noxluminous:BAAANQABCgIIAgAAAA==.',
Ob='Obin:BAAANQAECgUIEAAAAA==.',
Oc='Occasionally:BAAANQAECgIIAgAAAA==.',
Om='Ominious:BAABNQAECoEbAAMNAAcKphSBgwBEAQANAAUKzRaBgwBEAQAaAAQK0w/DHAAeAQABNQABCgEIAQAEAAAAAA==.Omnius:BAAANQAECgYIEwAAAA==.Omnya:BAAANQAECgYIBgABNQABCgEIAQAEAAAAAA==.',
Ow='Owendriel:BAAANQAFFAIIAgAAAA==.',
Pa='Paleigh:BAAANQABCgYICwAAAA==.Pandress:BAAANQAECgQIBwAAAA==.Pankake:BAAANQADCgIIAgABNQAECggIHQAfAFwgAA==.Paralysis:BAABNQAECoEgAAIgAAkK+RS0FgB7AgAgAAkK+RS0FgB7AgAAAA==.',
Pe='Peetza:BAAANQADCgYIBgABNQAECggIHQAfAFwgAA==.Peryite:BAABNQAECoEdAAMBAAgKdhW6QwAQAgABAAgKVhS6QwAQAgAhAAQK6xDPEADkAAAAAA==.',
Ph='Phaedrana:BAAANQAECgMIAwAAAA==.',
Pi='Pisscat:BAAANQAECgIIBQAAAA==.',
Po='Pocketdragon:BAABNQAECoEdAAMiAAcKxhKvCwBIAQAjAAcKxgz1GAB7AQAiAAYKHRGvCwBIAQAAAA==.',
Pr='Prideindeath:BAAANQADCgUIBQAAAA==.Promiscuity:BAAANQAECgUIBgAAAA==.Prængle:BAAANQADCgYIAwAAAA==.',
Ps='Psoas:BAABNQAECoEbAAMDAAkKQSAbBwBLAwADAAkKQSAbBwBLAwABAAIK4BDRsQCDAAAAAA==.Psypriest:BAEBNQAECoEXAAIBAAgKnhZiNQBPAgABAAgKnhZiNQBPAgABNQAFFAYIEgABAJsLAA==.',
Qu='Quaichang:BAAANQADCgYIBgAAAA==.',
Ra='Rabbi:BAABNQAECoEaAAIDAAgKfx6pEAC1AgADAAgKfx6pEAC1AgAAAA==.Rahfna:BAAANQADCgcIDwAAAA==.Railænu:BAAANQADCggIDgAAAA==.Rainmist:BAAANQADCgYIBgAAAA==.',
Re='Reesespbc:BAAANQAECgYIDQAAAA==.Reina:BAAANQAECgEIAQABNQAECggIGgABAGUhAA==.Reinz:BAAANQAECgIIAgAAAA==.Rektagar:BAABNQAECoEdAAINAAgK5iHkGAAJAwANAAgK5iHkGAAJAwABNQAFFAYIEgAPAJwhAA==.Ressandra:BAAANQADCgMIBgAAAA==.Rezo:BAAANQAECgEIAgAAAA==.',
Ri='Riverarose:BAAANQADCggIFAAAAA==.',
Ro='Roar:BAAANQAECgEIAQABNQAECgUICQAEAAAAAA==.',
Ry='Rysi:BAAANQADCgQIBAAAAA==.',
['Rò']='Ròs:BAABNQAECoEhAAIGAAkKLR/YBwDyAgAGAAkKLR/YBwDyAgAAAA==.',
['Rö']='Rös:BAAANQADCgEIAQABNQAECgkJIQAGAC0fAA==.',
Sa='Saberie:BAAANQADCggJFgABNQADCgMIBgAEAAAAAA==.Salaria:BAAANQAECgUIDQAAAA==.Salina:BAEANQAECgYJCwAAAA==.Sandstique:BAABNQAECoEbAAIMAAgKYSSRDAA5AwAMAAgKYSSRDAA5AwAAAA==.Sandweaver:BAAANQADCgcIBwAAAA==.Sanjira:BAAANQADCgYIBgAAAA==.Sarlak:BAABNQAECoEdAAMPAAgKgRq7MACZAgAPAAgKgRq7MACZAgAOAAEK8AZkcwAtAAAAAA==.Sarusuby:BAABNQAECoEfAAIdAAgKvAzSFgB3AQAdAAgKvAzSFgB3AQAAAA==.Satae:BAABNQAECoEdAAIfAAgKXCAuAwDvAgAfAAgKXCAuAwDvAgAAAA==.',
Sc='Schufft:BAAANQAECgYIDwAAAA==.Scottydh:BAAANQADCgYJBgABNQAECggIHgAeAIQgAA==.Scottymac:BAABNQAECoEeAAIeAAgKhCDAFQDRAgAeAAgKhCDAFQDRAgAAAA==.Scottypal:BAAANQAECgEIAQABNQAECggIHgAeAIQgAA==.',
Se='Seatah:BAAANQAECgMIAwAAAA==.Seba:BAAANQAECgEIAgAAAA==.Seetah:BAAANQAECgcIEAAAAA==.',
Sh='Shadaddy:BAABNQAECoEZAAMSAAkKFCDUSQDKAgASAAgK9x/USQDKAgAkAAMKjR5NGADuAAABNQADCgcIBwAEAAAAAA==.Shal:BAAANQAECgYIDAAAAA==.Shamanluz:BAAANQADCgIIAgABNQAECgEJAQAEAAAAAA==.Shamommy:BAAANQADCgUIBAAAAA==.Shamtaz:BAAANQABCgEIAQAAAA==.Shimmerstar:BAABNQAECoEZAAIFAAkKTRwoSQBsAgAFAAkKTRwoSQBsAgAAAA==.Shroomgirl:BAAANQAECgUIBQAAAA==.',
Si='Silexe:BAAANQAECgUICAAAAA==.Sitga:BAAANQADCgIIAgAAAA==.',
Sl='Slipperyboi:BAAANQAECgQICQAAAA==.Slÿ:BAAANQAECgIIAgAAAA==.',
So='Solarion:BAAANQAECgQIBwABNQAECgYIEgAEAAAAAA==.Soldraca:BAAANQADCgYIEQAAAA==.',
St='Stats:BAAANQAECgUICQAAAA==.Stutters:BAAANQAECgcIEwAAAA==.',
Su='Subayyru:BAAANQADCgEIAQABNQAECgQICAAEAAAAAA==.Sudachi:BAAANQADCgYIBgABNQAFFAUKCAAlABUbAA==.Sunnyräy:BAAANQAECgMIAwAAAA==.Suthrheimr:BAAANQAECgcIEAAAAA==.',
['Sý']='Sýndrá:BAAANQAECgYIDQAAAA==.',
Ta='Takafune:BAAANQADCgQIBQAAAA==.Talespin:BAAANQADCgcIBwAAAA==.Talysiah:BAAANQAECgQICQAAAA==.Tavok:BAAANQAECgYIEAAAAA==.Tazbis:BAAANQAECgIIAgAAAA==.',
Te='Teishuku:BAABNQAECoEfAAIFAAgKaQ/UeQDWAQAFAAgKaQ/UeQDWAQAAAA==.Teusday:BAAANQAECgUIEAAAAA==.',
Th='Thiux:BAAANQAECgYIEAAAAA==.Thoeleden:BAAANQAECgMIBAABNQAFFAUICgAMAAMiAA==.Thotsnprayrs:BAAANQADCggICAABNQAECgQIDwAEAAAAAA==.Thrappy:BAABNQAECoEbAAMMAAgK0BKmaAB7AQAMAAcK/w+maAB7AQANAAUKSBhNegBdAQAAAA==.Thryna:BAAANQADCgEIAQAAAA==.',
Ti='Tinsoon:BAAANQADCggIHwAAAA==.Tintaglia:BAABNQAECoEfAAMZAAgKDBaZRABDAgAZAAgKDBaZRABDAgAYAAEKZBGIJwA1AAABNQAECgUICgAEAAAAAA==.Tirtun:BAABNQAECoEcAAIkAAgK7B68AwDDAgAkAAgK7B68AwDDAgAAAA==.',
Tr='Triggeer:BAAANQAECgYIDQAAAA==.Trolldemort:BAAANQADCgYIBgABNQAECggIGwAZAEAaAA==.',
Tu='Tully:BAAANQAECgQIBwAAAA==.Tunkhan:BAAANQABCggIDAAAAA==.',
Tw='Twelvekill:BAABNQAECoEhAAIPAAkKrR9zFAAgAwAPAAkKrR9zFAAgAwAAAA==.',
Ty='Tyliaa:BAABNQAECoEXAAIMAAcK7BspOgAvAgAMAAcK7BspOgAvAgABNQAECgMIAwAEAAAAAA==.',
Ul='Ultramon:BAAANQAECgUICQAAAA==.',
Un='Unbreakabull:BAAANQADCgEIAgAAAA==.Unwell:BAAANQAECgYIDAABNQAECgkJHQAKALAcAA==.',
Ur='Urgoochness:BAAANQADCgQIBAAAAA==.Urikhai:BAAANQADCggIAgAAAA==.',
Va='Vainglorious:BAAANQADCggIEwABNQAECgUIDAAEAAAAAA==.Valanora:BAABNQAECoEaAAIYAAgKqxIbBQA0AgAYAAgKqxIbBQA0AgAAAA==.Valerie:BAAANQADCggIGAABNQAECgkJGwAPABkYAA==.Valinaxius:BAAANQADCggIGAAAAA==.Vapturov:BAAANQADCggIGAAAAA==.',
Ve='Veeks:BAABNQAECoEZAAINAAcK1AvxbACEAQANAAcK1AvxbACEAQAAAA==.Velikirn:BAAANQAECgUIBgAAAA==.Velydia:BAAANQAECgYIBgAAAA==.Venefica:BAAANQAECgEIAQAAAA==.Verdracee:BAAANQABCgMIAwABNQAECgEIAQAEAAAAAA==.Versø:BAAANQAECgYJDwAAAA==.Veryzi:BAAANQAECgEIAgAAAA==.',
Vi='Vine:BAAANQADCgIIAgAAAA==.',
Vl='Vlyrae:BAAANQADCgMIAwABNQABCgEIAQAEAAAAAA==.',
Vo='Voidhearted:BAABNQAECoEsAAIDAAgKOxHRHgD6AQADAAgKOxHRHgD6AQAAAA==.Vonzuo:BAAANQAECgIIAgAAAA==.',
Vu='Vukodlak:BAAANQADCgYIBgABNQAECgUICgAEAAAAAA==.',
['Vì']='Vìolet:BAAANQADCgMIAwABNQAECgYIEwAEAAAAAA==.',
Wa='Warriorwuu:BAAANQABCgIIAgAAAA==.Wayshua:BAAANQADCgEIAQAAAA==.',
We='Werkajerk:BAAANQADCggICAABNQAFFAUICgAMAAMiAA==.Werkjathal:BAACNQAFFIEKAAIMAAUKAyKsAwAAAgAMAAUKAyKsAwAAAgA1AAQKgSIAAgwACQqvJncAAOEDAAwACQqvJncAAOEDAAAA.',
Wi='Wibbles:BAAANQADCgcICwAAAA==.Wigarthan:BAAANQADCgEIAQAAAA==.',
Wo='Wolfblitzer:BAABNQAECoEZAAIFAAgKExapYQAdAgAFAAgKExapYQAdAgAAAA==.Worldbane:BAAANQAECgcIEwAAAA==.',
Wr='Wraithlash:BAAANQAECggIDgAAAA==.',
Wt='Wtyczka:BAAANQABCgUIBQAAAA==.',
Wu='Wuulock:BAAANQABCgEJAQAAAA==.',
Wy='Wynnhrt:BAAANQADCggICAAAAA==.',
Xa='Xalatath:BAAANQAECgYIBgAAAA==.Xanakmando:BAAANQADCggIFQAAAA==.Xanthos:BAAANQADCgIIAgAAAA==.',
Xi='Xianyu:BAAANQAECgMICAAAAA==.',
Ya='Yarian:BAAANQAECgMIAwAAAA==.',
Yu='Yuck:BAAANQAECgIIAgABNQAFFAUICgAMAAMiAA==.',
Za='Zachhunter:BAACNQAFFIESAAMPAAYKnCHdBQCWAQAPAAQKRiLdBQCWAQAOAAMKhBg2DgD3AAA1AAQKgScAAw4ACQp5JF8OANgCAA4ACApxI18OANgCAA8ABwp5H71KAEACAAAA.Zachmage:BAAANQADCggIDgAAAA==.Zan:BAABNQAECoEhAAMNAAkKHx6mFwATAwANAAkKHx6mFwATAwAMAAIKNw/ZzwBwAAAAAA==.',
Ze='Zeronation:BAAANQADCgYICAAAAA==.',
Zi='Zinar:BAAANQABCggIDgAAAA==.',
Zu='Zultrix:BAAANQADCggIEQAAAA==.',
Zy='Zylaeri:BAAANQAECgYICAAAAA==.',
['Éo']='Éowyn:BAAANQADCgEIAQAAAA==.',
['Ël']='Ëllër:BAAANQAECgUIBgAAAA==.',
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
