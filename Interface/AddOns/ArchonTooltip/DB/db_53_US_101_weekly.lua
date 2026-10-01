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

local lookup = {'Unknown-Unknown','Monk-Mistweaver','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Warlock-Demonology','Shaman-Restoration','Druid-Guardian','Druid-Balance','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','Warlock-Destruction','Warrior-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Protection','Paladin-Holy','Shaman-Enhancement','Evoker-Devastation','DeathKnight-Frost','Paladin-Retribution','Warlock-Affliction','Monk-Windwalker',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aastrid:BAAANQADCgYIBgAAAA==.',
Ad='Adorabúll:BAAANQADCgEIAQAAAA==.',
Ae='Aevriia:BAAANQADCgIIAgAAAA==.',
Al='Aldric:BAAANQADCgIIAgAAAA==.Althenzdormu:BAAANQAECgQICgAAAA==.Altruist:BAAANQAECgMIBQABNQAECgYIEAABAAAAAA==.',
Am='Amaethon:BAAANQAECgQIBgAAAA==.',
An='Ancaera:BAAANQADCggIDQAAAA==.Andalikus:BAAANQAECgYIEQAAAA==.Andorra:BAAANQADCgMIBQAAAA==.Andybocelli:BAAANQADCgYIBgAAAA==.Anrien:BAAANQAECgYIDwAAAA==.',
Ar='Ari:BAAANQADCgcIBwAAAA==.Around:BAAANQAECgQIBgAAAA==.',
As='Asharal:BAAANQADCgYIBgAAAA==.',
At='Atriste:BAAANQAECgYIEAAAAA==.',
Au='Aunyx:BAAANQAECgYIDwAAAA==.',
Az='Azenoth:BAAANQADCggIGgAAAA==.',
Ba='Babajaga:BAAANQADCgIJAgAAAA==.Baloth:BAAANQADCgYJBgABNQAECgUIDwABAAAAAA==.',
Be='Beej:BAABNQAECoEbAAICAAgK7xS9EgD+AQACAAgK7xS9EgD+AQAAAA==.',
Bi='Biggooch:BAAANQAECgYICgAAAA==.Bison:BAAANQADCgcJBwAAAA==.',
Bl='Blackrose:BAAANQADCgUIBwABNQAECgQIBQABAAAAAA==.Blightbeard:BAAANQAECgQIBwAAAA==.Blîss:BAAANQAECgQIBgAAAA==.',
Br='Brayliel:BAAANQADCgQIBQAAAA==.Brut:BAAANQAECgQIBwABNQAECgkJHAADACseAA==.',
Bu='Bumpy:BAAANQADCggICAAAAA==.Bustus:BAAANQAECgYIDwAAAA==.',
Ca='Calinia:BAAANQABCgMIBQAAAA==.Carole:BAABNQAECoEfAAMEAAgKiyAnGQC4AgAEAAgKiyAnGQC4AgAFAAQKYRTXdADUAAAAAA==.Caroll:BAABNQAECoEcAAQDAAkKKx7mDADvAgADAAgKiB/mDADvAgAGAAQK/xXGjAD7AAAHAAMKQgtbFQCYAAAAAA==.Carsomavra:BAAANQADCgQICAAAAA==.Cathercy:BAAANQAECgQICQAAAA==.',
Ch='Chrollo:BAAANQAECgQICgAAAA==.Chunt:BAAANQADCgYIDQAAAA==.',
Cl='Cloggy:BAAANQADCgYIBgABNQAECgkJJAAIAMMjAA==.',
Co='Corannis:BAAANQAECgYIEAAAAA==.Corax:BAAANQADCgQIBgAAAA==.',
Cr='Cranberries:BAAANQAECgEIAQABNQAECgkJIwAJAGwKAA==.Cravedog:BAABNQAECoEsAAMKAAgKmCPCAwAwAwAKAAgKmCPCAwAwAwALAAMK9QsKeACQAAAAAA==.Creepi:BAAANQAECgQICQAAAA==.Cromgabhar:BAAANQADCgYJBgABNQAECgQJBQABAAAAAA==.',
Cu='Cupcáke:BAAANQAECgcICQAAAA==.Curthodnes:BAAANQADCgIJAgAAAA==.',
Da='Damaso:BAAANQAECgQIBAAAAA==.Damik:BAAANQAECgEIAQAAAA==.Darku:BAAANQAECgYIDwAAAA==.Darlàrk:BAAANQAECgQIBAAAAA==.Dawnmane:BAAANQAECggICAABNQAECggJGwAKAPojAA==.',
De='Delderach:BAAANQAECgQICQAAAA==.Denin:BAAANQAECgUICgAAAA==.Derphardigan:BAAANQADCgYIBgABNQAECgQJBQABAAAAAA==.',
Di='Dirkette:BAAANQAECgUIDAAAAA==.',
Dk='Dkxsmurfx:BAAANQADCgYICAAAAA==.',
Do='Dokai:BAAANQAECgUIDwAAAA==.',
Dr='Dracmiz:BAAANQADCgcICAAAAA==.Drathan:BAAANQADCgMJAwAAAA==.',
Dt='Dthnght:BAAANQADCgQIBwAAAA==.',
Du='Duskweaver:BAAANQADCgIIAgAAAA==.',
Ea='Earthboy:BAAANQADCgIIAgABNQAECgkJHAADACseAA==.',
El='Elaenei:BAAANQADCgYIDAAAAA==.Eliance:BAAANQAECgQICQAAAA==.Elienn:BAAANQADCgQJCwAAAA==.',
Er='Errius:BAAANQAECgUIDwAAAA==.',
Es='Esh:BAAANQADCgQIBAABNQAECgcIDwABAAAAAA==.',
Eu='Eunja:BAEANQADCgcIEwAAAQ==.',
Fa='Facetious:BAAANQADCgIIAgAAAA==.',
Fi='Filharmonic:BAAANQADCgUJEQAAAA==.',
Fo='Foid:BAACNQAFFIEJAAMMAAMKnBvMAAAlAQAMAAMKnBvMAAAlAQANAAEKWA1VLQBEAAA1AAQKgRYAAwwACQp3I9QBAEADAAwACQp3I9QBAEADAA0AAQobArsuARQAAAE1AAUUAwoJAAwAnBsA.',
Fu='Furiah:BAAANQADCgYICwAAAA==.Fusaa:BAABNQAECoEeAAIIAAgKehIVWAABAgAIAAgKehIVWAABAgAAAA==.',
Ga='Gahzoo:BAAANQADCgYIDwAAAA==.Garretjax:BAAANQADCgYIEwAAAA==.Garuda:BAAANQAECgUICQAAAA==.',
Ge='Gelst:BAAANQADCgQJCwAAAA==.Gerbs:BAAANQADCgYIBgAAAA==.Gerbzarrion:BAAANQAECgQICQAAAA==.Getherdone:BAAANQADCgUICAAAAA==.',
Gi='Gilgador:BAAANQAECgcIDQAAAA==.',
Gr='Grassfed:BAAANQAECgQIBAAAAA==.',
Gu='Guilehart:BAAANQABCgIIAQAAAA==.',
Ha='Hap:BAAANQAECgMIAwAAAA==.Hawknnib:BAAANQAECgQJBQAAAA==.',
Ho='Hothala:BAAANQADCgYIDwAAAA==.',
Hu='Hunterpulled:BAABNQAECoEwAAIOAAgK3BMSUQAuAgAOAAgK3BMSUQAuAgAAAA==.',
Ic='Icnothing:BAAANQADCgcIEAAAAA==.',
In='Infectedarms:BAAANQAECgUIBwAAAA==.',
Ip='Ipwnallnoobs:BAAANQAECgYIDgAAAA==.',
Ir='Irisila:BAAANQADCggIEwABNQAECgQIBgABAAAAAA==.',
Ja='Jaskilz:BAAANQADCgQIBgAAAA==.Jaypharyn:BAAANQAECgQICQAAAA==.Jazel:BAAANQADCgQICAAAAA==.',
Jo='Johalea:BAAANQADCgQJCwAAAA==.',
Ju='Juliå:BAAANQADCgQJBwAAAA==.',
['Jå']='Jåsper:BAAANQAECgQICgAAAA==.',
Ka='Kahea:BAEANQADCgYIBgABNQAECgYICQABAAAAAA==.Kaileena:BAAANQAECgYIEAAAAA==.Kasia:BAAANQAECgQICgAAAA==.Kassani:BAAANQADCgEJAQAAAA==.Kasuga:BAAANQADCgQIBAABNQAECgkJGgAPACIeAA==.',
Ki='Kieler:BAAANQAECgQIBQAAAA==.Kierrings:BAAANQAECgQIBwAAAA==.Kikala:BAAANQADCgMIAwAAAA==.Kirarah:BAAANQAECgYIEAAAAA==.Kizune:BAAANQADCgcIBwAAAA==.',
Kl='Klauss:BAAANQAECgYIEgAAAA==.Klax:BAAANQADCgYIDAAAAA==.',
Ko='Kordjin:BAAANQADCgIIAgAAAA==.',
Kr='Krornik:BAAANQADCgYIDgABNQAECgEIAQABAAAAAA==.',
Ku='Kuyaros:BAAANQADCgUIBQAAAA==.',
['Kí']='Kíhanna:BAAANQAECgYIEgAAAA==.',
Le='Legenddairy:BAABNQAECoEfAAIKAAgKCRUvDwDtAQAKAAgKCRUvDwDtAQAAAA==.',
Li='Liemach:BAAANQADCgIIAgAAAA==.',
Lj='Ljósálfr:BAABNQAECoEYAAIQAAcKOyJyBwCaAgAQAAcKOyJyBwCaAgAAAA==.',
Lo='Lochramae:BAAANQAECgUICgAAAA==.',
Lu='Lunaluvegood:BAAANQADCgUIBQAAAA==.Lunargaze:BAABNQAECoEjAAMRAAkKph2/DQDrAgARAAkKvhy/DQDrAgASAAQKGR7cPwBPAQAAAA==.',
['Lâ']='Lâriel:BAAANQAECgUICgAAAA==.',
Ma='Madmartigan:BAAANQAECgQJBQAAAA==.Mamimisan:BAAANQAECgUICAAAAA==.Matix:BAAANQABCggIFQAAAA==.',
Me='Mechadockie:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.',
Mi='Miklo:BAAANQADCgUIBQAAAA==.Mirah:BAAANQADCgMIAwAAAA==.Mistazee:BAAANQAECgUIAQAAAA==.Mizan:BAAANQAECgYIBwABNQAECgkJIQATAMYbAA==.Mizeroni:BAABNQAECoEhAAMTAAkKxhu7CgCwAgATAAkKxhu7CgCwAgAUAAEKjAT07QA1AAAAAA==.Mizkat:BAAANQADCgcIAQABNQAECgkJIQATAMYbAA==.Mizky:BAAANQADCgQIBAAAAA==.',
Mo='Mormra:BAAANQADCggIGQAAAA==.',
Mt='Mtruckski:BAAANQABCgIIAgABNQAECgQIBwABAAAAAA==.',
My='Myoo:BAAANQADCgUIBQAAAA==.',
['Më']='Mërcy:BAAANQADCgQJBwAAAA==.',
Na='Naklus:BAAANQADCgUICQAAAA==.',
Ne='Neilia:BAAANQAECgYICwABNQAECgcIDQABAAAAAA==.Neropoison:BAAANQADCgIIAwAAAA==.Nessamos:BAAANQADCgIIAgAAAA==.',
Ni='Nikalkhano:BAAANQADCgYICQAAAA==.',
Nl='Nlani:BAAANQAECgMJAwAAAA==.',
Nu='Nuvi:BAAANQADCgUICAAAAA==.',
Oc='Octarius:BAAANQAECgIIAgABNQAECgQIBgABAAAAAA==.',
On='Onomirigaru:BAAANQAECgYIEgAAAA==.',
Op='Oproer:BAAANQADCggICAAAAA==.',
Ox='Oxygentank:BAAANQAECgYIBgAAAA==.',
Pa='Parne:BAAANQADCgUIBQAAAA==.',
Pi='Piccolo:BAAANQAECggIAQAAAA==.Pips:BAAANQADCgYIBgABNQAECgYIFQAEAMUKAA==.',
Pl='Platura:BAAANQAECgYIEAAAAA==.',
Pv='Pvp:BAAANQADCgMIAwAAAA==.',
Ra='Raezune:BAAANQABCgYICwAAAA==.Rajia:BAAANQAECgYIEAAAAA==.Ranron:BAAANQAECgMIAwAAAA==.Rassaphore:BAAANQADCggIDwAAAA==.Raínbow:BAAANQADCgcJCgABNQAECgMIBAABAAAAAA==.',
Re='Reapin:BAAANQAECgQICgAAAA==.Rezeldâ:BAAANQADCgYIDwAAAA==.',
Rh='Rhaegalsh:BAAANQAECgcIEQAAAA==.',
Ri='Rionach:BAAANQAECgUIDwAAAA==.Rivon:BAAANQADCggIGgAAAA==.',
Ru='Runeneya:BAAANQAECggJBwAAAA==.',
Sa='Sangle:BAAANQADCgEIAQAAAA==.',
Sc='Schtzngigllz:BAAANQADCgQIBAABNQADCggIGQABAAAAAA==.Scoop:BAAANQAECgYIDgAAAA==.',
Se='Seanan:BAABNQAECoEcAAIVAAgKdyI6BAA5AwAVAAgKdyI6BAA5AwAAAA==.Seera:BAAANQADCgIIAgAAAA==.Seran:BAABNQAECoEeAAIUAAgKPQYdbwB4AQAUAAgKPQYdbwB4AQAAAA==.',
Sh='Shammwow:BAAANQAECgYICAAAAA==.Shamoo:BAAANQAECgYIBgAAAA==.Shaudis:BAAANQAECgYIEQAAAA==.Shiftyshape:BAAANQAECgEJAQAAAA==.Shigurexx:BAAANQAECgYIEAAAAA==.Shoe:BAABNQAECoEcAAIWAAgKPBY3DwAtAgAWAAgKPBY3DwAtAgAAAA==.Shootup:BAAANQADCgQJCQAAAA==.',
Sl='Slapurdaddy:BAAANQADCgUJCQAAAA==.',
So='Somassen:BAAANQAECgUIDwAAAA==.Sonashee:BAAANQAECgcIDQAAAA==.Sorender:BAAANQADCgYICwAAAA==.',
St='Steelbutt:BAAANQADCggIFwAAAA==.',
Su='Supersoakêr:BAAANQAECgQIBAABNQAECgcIDQABAAAAAA==.Surii:BAAANQADCgYICwAAAA==.',
Ta='Talene:BAAANQADCgUIBgAAAA==.Tamarins:BAAANQAECgQICgAAAA==.Tappy:BAABNQAECoEaAAIGAAcKJhEhYwCRAQAGAAcKJhEhYwCRAQAAAA==.',
Te='Terkarakk:BAABNQAECoEbAAIKAAgK+iN9AwA8AwAKAAgK+iN9AwA8AwAAAA==.',
Th='Thirryn:BAAANQAECgYIDwAAAA==.Thorybos:BAAANQAECgUIDAAAAA==.',
Ti='Tippy:BAAANQAECgEIAgAAAA==.',
To='Toom:BAAANQAECgQICQAAAA==.',
Tr='Traylinna:BAAANQADCgEIAQAAAA==.Trophyhubby:BAAANQAECgUIDwAAAA==.',
Tu='Tuknark:BAAANQADCgQJCwAAAA==.',
Ty='Tyeren:BAAANQAECgUICgAAAA==.Tyeriel:BAACNQAFFIEFAAIXAAMKnQxxCQDcAAAXAAMKnQxxCQDcAAA1AAQKgSQAAxcACQqsG1IXAIoCABcACQohG1IXAIoCAAQAAwqtFFKDAKYAAAAA.Typpy:BAAANQADCgUIBQAAAA==.',
Tz='Tzuriel:BAEBNQAECoEXAAMTAAcK4SJICgC4AgATAAcK4SJICgC4AgAYAAUK+hLizQALAQAAAA==.',
Va='Valkyriewing:BAAANQAECgQICQAAAA==.Valvet:BAAANQADCggIGgAAAA==.',
Ve='Velaste:BAAANQADCgQIBAAAAA==.',
Vi='Vikril:BAAANQAECgYIEQAAAA==.Vincenzo:BAAANQADCgUICgAAAA==.',
Vo='Volkanoth:BAAANQAECgUIBwAAAA==.',
Vy='Vylus:BAAANQAECgYJEAAAAA==.',
['Vá']='Vásh:BAAANQAECgYIEAAAAA==.',
We='Webjibaro:BAAANQADCgUICgAAAA==.Weeblewobble:BAAANQADCgQJCwAAAA==.Weili:BAAANQAECgQICAAAAA==.',
Wh='Whiney:BAAANQAECgIIAgABNQAECgYICQABAAAAAA==.',
Wi='Wikidfiend:BAAANQADCgQIBQAAAA==.William:BAAANQAECgUICAAAAA==.Windee:BAAANQADCgYICgAAAA==.Wishi:BAAANQADCgQIBAAAAA==.',
Wr='Wrast:BAAANQAECgUIBAAAAA==.Wravyn:BAAANQAECgUIDwAAAA==.',
Xa='Xalted:BAAANQADCgUJCQAAAA==.Xandria:BAAANQADCgUIBQAAAA==.Xaylios:BAAANQAECgYIBwAAAA==.',
Xy='Xyara:BAABNQAECoEjAAQPAAkKMBZBJAA8AQAIAAYKzxYUbQC/AQAPAAUK2RFBJAA8AQAZAAMKLA//EgDKAAAAAA==.',
Yo='Yoghurt:BAABNQAECoEYAAMMAAcK/hfRCAAEAgAMAAcK/hfRCAAEAgANAAEKtAIUJAEoAAAAAA==.',
Yu='Yunlan:BAAANQAECgEIAQAAAA==.',
Za='Zalidus:BAAANQAECgQIBgAAAA==.Zanthor:BAAANQAECgQIBAABNQAECgkJIwAaAJYQAA==.',
Ze='Zehnia:BAAANQABCgcIDQAAAA==.Zephira:BAAANQADCgUIBQAAAA==.',
Zi='Zibzab:BAAANQAECgQICQAAAA==.',
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
