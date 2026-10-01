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

local lookup = {'DemonHunter-Havoc','Unknown-Unknown','Shaman-Elemental','Warrior-Arms','Warlock-Demonology','Mage-Arcane','Mage-Frost','Druid-Feral','Hunter-Marksmanship','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Monk-Brewmaster','Warlock-Destruction','Druid-Guardian','Druid-Balance','Paladin-Holy','Monk-Windwalker','Priest-Shadow','Warrior-Fury','DeathKnight-Frost','Paladin-Retribution','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver','Rogue-Subtlety','Hunter-BeastMastery','Paladin-Protection','Rogue-Assassination','Shaman-Enhancement','DemonHunter-Devourer','Priest-Holy','Hunter-Survival','Evoker-Augmentation','Warrior-Protection','Priest-Discipline',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Actualape:BAAANQAECgEIAQAAAA==.',
Ad='Addy:BAABNQAECoEaAAIBAAgK+BfGIQBCAgABAAgK+BfGIQBCAgAAAA==.Adelethe:BAAANQADCgYIBgAAAA==.Aditu:BAAANQADCgMIAwAAAA==.',
Ae='Aestian:BAAANQAECgUICQAAAA==.',
Ah='Ahhotep:BAAANQADCgEIAQAAAA==.',
Ai='Ailysely:BAAANQADCgUJDgAAAA==.Aispere:BAAANQADCgIJAwABNQAECgEIAQACAAAAAA==.',
Al='Alerzhulan:BAAANQAECgUIDQAAAA==.Aletheia:BAAANQADCggICAAAAA==.Alfurn:BAAANQADCgIIAgAAAA==.Aliveknightt:BAAANQADCggICAAAAA==.Alledria:BAAANQAECgYIDQAAAA==.Alorely:BAAANQAECgUICwAAAA==.',
Am='Amanara:BAAANQAECgQIBwAAAA==.Amoonia:BAAANQADCgUICgAAAA==.',
An='Anciientpaw:BAAANQAECgcIEgAAAA==.Andrasomnius:BAAANQAECgQIBAAAAA==.Angbar:BAAANQAECgQIDAAAAA==.Anguirus:BAABNQAECoEXAAIDAAcKvgP+mgALAQADAAcKvgP+mgALAQAAAA==.Anuksunàmun:BAAANQADCgYIDAAAAA==.',
Aq='Aqulenas:BAAANQAECgEIAQAAAA==.',
Ar='Arakhan:BAAANQADCggIEAAAAA==.Arcadian:BAABNQAECoEjAAIEAAgKBA/6dQDkAQAEAAgKBA/6dQDkAQAAAA==.Arceeprime:BAAANQADCgcICQAAAA==.Arextheelder:BAAANQAECgQICAAAAA==.Argentum:BAAANQADCggICAABNQAECggIGgABAPgXAA==.Armorscales:BAABNQAECoEdAAIFAAkK/x9oGwDpAgAFAAkK/x9oGwDpAgAAAA==.Arntraz:BAAANQAECgIIAwAAAA==.Arrabbiato:BAAANQAECggICAAAAA==.Arronaxx:BAAANQADCgYIEAAAAA==.Arçadia:BAAANQAECgIIAgAAAA==.',
As='Ashnikko:BAAANQADCgYIBgAAAA==.Ashtori:BAAANQABCgQIBgAAAA==.Asprika:BAAANQAECgQICAAAAA==.Astayoni:BAAANQAECgIIAwAAAA==.Asterfleur:BAAANQADCgYIBwABNQAECgQIBQACAAAAAA==.Astrine:BAABNQAECoEgAAMGAAkK2xTicQBlAgAGAAkKlBLicQBlAgAHAAYKOhEvEwAyAQAAAA==.',
At='Ataraxya:BAAANQAECgIIBAAAAA==.',
Au='Auberon:BAABNQAECoEbAAIIAAgKQRKACwAHAgAIAAgKQRKACwAHAgAAAA==.Aufta:BAAANQAECgUIDwAAAA==.Aumer:BAAANQABCggICwAAAA==.Aura:BAAANQADCgcIBwAAAA==.',
Az='Azi:BAACNQAFFIEFAAIJAAMKLg+FEADUAAAJAAMKLg+FEADUAAA1AAQKgSMAAgkACQqAHqoOANUCAAkACQqAHqoOANUCAAAA.Azurite:BAAANQADCgYIFQAAAA==.',
Ba='Backpedal:BAAANQADCggIHAAAAA==.Badankhadonk:BAABNQAECoEtAAIKAAkK+yRlAgCvAwAKAAkK+yRlAgCvAwAAAA==.Bakkutteh:BAAANQABCgIIBAAAAA==.Bakuhiko:BAAANQAECgMIAwAAAA==.Balen:BAAANQAECgMIBAAAAA==.Bandersin:BAAANQADCgUIBQAAAA==.Bansheex:BAAANQADCgQIBAAAAA==.',
Be='Beefmuffinz:BAABNQAECoEZAAILAAgK6xybGgCrAgALAAgK6xybGgCrAgAAAA==.Beethozart:BAAANQADCgUICAAAAA==.Belcebu:BAAANQABCggIDgAAAA==.Belholy:BAAANQAECgUIBwAAAA==.Beliice:BAAANQADCgIIAgABNQAECgUIBwACAAAAAA==.Bellafleur:BAAANQADCggICgABNQAECgQIBQACAAAAAA==.Bellawesome:BAAANQABCgQIBAAAAA==.Bendeekay:BAACNQAFFIEFAAIMAAIKDBpBFQCaAAAMAAIKDBpBFQCaAAA1AAQKgSoAAgwACQpmIvQGAHEDAAwACQpmIvQGAHEDAAAA.Benilok:BAAANQAECgUIDQAAAA==.Bethgibbons:BAAANQADCgUJCAAAAA==.',
Bg='Bgpocalypse:BAAANQADCgYIBgAAAA==.',
Bi='Bigsuccubus:BAAANQAECgEIAQAAAA==.',
Bl='Blackblood:BAAANQAECgUIDwAAAA==.Bloodache:BAAANQAECgYIDQAAAA==.Blux:BAAANQAECgIIAgAAAA==.',
Bo='Boil:BAAANQAECgYIEAAAAA==.Bonemarrow:BAAANQAECgMIBQAAAA==.',
Br='Brakeable:BAAANQADCgIJBAAAAA==.Braké:BAAANQAECgQJCgAAAA==.Brewskies:BAABNQAECoEcAAINAAgKnSNQAwA0AwANAAgKnSNQAwA0AwAAAA==.Brightstar:BAAANQADCgUIBQAAAA==.Brioche:BAAANQADCgEIAQAAAA==.Brionthicc:BAAANQAECgMIBQABNQAFFAMIBgAOAKYTAA==.Brownington:BAABNQAECoEgAAQPAAgKmyMdFQCMAQAQAAYKjyFFLwAgAgAPAAQKZiIdFQCMAQAIAAIK0yEaHgDAAAAAAA==.Bruhilda:BAAANQAECgQICwAAAA==.Brìonik:BAACNQAFFIEGAAMOAAMKphP2BwCyAAAOAAIKxRf2BwCyAAAFAAEKaAubLgBNAAA1AAQKgSoAAw4ACQogHjMGAJoCAA4ACAokHTMGAJoCAAUABwqqGNdSABICAAAA.',
Bu='Bubbleroundi:BAABNQAECoEhAAIRAAgKUAurWwC6AQARAAgKUAurWwC6AQAAAA==.Bubudder:BAABNQAECoEcAAILAAgKySTrDQAfAwALAAgKySTrDQAfAwAAAA==.Buffstuff:BAAANQAECgcIDQAAAA==.Burgerlock:BAAANQAECgEIAQAAAA==.',
Ca='Caeviro:BAAANQAECgYIDwAAAA==.Canadaishere:BAAANQADCgMIAwAAAA==.Cantheartitz:BAAANQAECgQJCAAAAA==.Catdav:BAAANQAECgUIBwAAAA==.',
Ch='Charbol:BAAANQADCgQIBAABNQADCggICAACAAAAAA==.Chelraani:BAAANQAECgUIBwAAAA==.Chess:BAAANQAECgUIBQAAAA==.Chiichard:BAAANQADCgYICAAAAA==.Chunkamonk:BAAANQADCgQIBgAAAA==.',
Ci='Ciarianna:BAAANQADCgcIBwABNQAECggIGgABAPgXAA==.Cigar:BAAANQADCgUICQABNQAECgYIEAACAAAAAA==.',
Cl='Clazzicola:BAABNQAECoEdAAISAAkKMSD1DgC5AgASAAkKMSD1DgC5AgAAAA==.',
Co='Combatwombat:BAAANQABCgEIAQAAAA==.Conjredcukee:BAAANQAECgMIBQAAAA==.Coogsayer:BAAANQADCgIIAgAAAA==.Cowdeer:BAAANQAECgQIBgAAAA==.',
Cp='Cptncrush:BAAANQAECgUIDwAAAA==.',
Cr='Creamsickle:BAAANQABCgIIBAAAAA==.Creature:BAAANQAECgEIAQAAAA==.',
Cu='Cupcakes:BAAANQADCgcIEwAAAA==.Cutethulu:BAABNQAECoEZAAITAAgK3BPQHAARAgATAAgK3BPQHAARAgAAAA==.',
Cy='Cydarr:BAAANQADCgQIBAAAAA==.Cyther:BAACNQAFFIEGAAIUAAMKrhjpAAAPAQAUAAMKrhjpAAAPAQA1AAQKgSoAAhQACQonJXYAAMUDABQACQonJXYAAMUDAAAA.',
Da='Dadbodftw:BAAANQAECgQIDQAAAA==.Daddylight:BAAANQAECgUIDAAAAA==.Daelyn:BAAANQADCgYIAgAAAA==.Dakk:BAAANQADCggICAAAAA==.Darkdottie:BAAANQAECgQICgAAAA==.Darkenstormy:BAAANQAECgEIAQAAAA==.Darkmage:BAAANQADCgQIAwAAAA==.',
De='Deadlight:BAABNQAECoEcAAIVAAgKYQ1CMgCsAQAVAAgKYQ1CMgCsAQAAAA==.Deadtofall:BAAANQADCgYIDwAAAA==.Deathshikzs:BAABNQAECoEdAAIMAAcKWBxGKwAxAgAMAAcKWBxGKwAxAgAAAA==.Decix:BAAANQAECgIIAgABNQAFFAIIBQATAP8VAA==.Deet:BAAANQADCgMJAwAAAA==.Deity:BAAANQAECgYICQABNQAECggIEwACAAAAAA==.Demonllxll:BAAANQAECgUIDgAAAA==.Demontime:BAAANQADCgcIBwAAAA==.Desolation:BAABNQAECoEbAAIGAAgKcCNXKgAjAwAGAAgKcCNXKgAjAwAAAA==.Despia:BAAANQAECgUIBwAAAA==.Devastacia:BAAANQADCggICAAAAA==.',
Di='Dicot:BAAANQAECgUIBwAAAA==.Diety:BAAANQAECggIEwAAAA==.Dimension:BAAANQAECgEIAQAAAA==.Disconnect:BAAANQABCgUIBwAAAA==.',
Dj='Djpallyd:BAABNQAECoEaAAIWAAgKpBCQewDSAQAWAAgKpBCQewDSAQAAAA==.',
Do='Dotmami:BAAANQAECgYICgAAAA==.Doughy:BAAANQADCggIEAAAAA==.',
Dr='Dragonu:BAABNQAECoErAAMXAAkK5h7eBQAzAwAXAAkK5h7eBQAzAwAYAAEKIQ2bMwA1AAAAAA==.Draktyr:BAABNQAECoEmAAMEAAkKOSCsHAAlAwAEAAkKOSCsHAAlAwAUAAEKLAYNKgAuAAAAAA==.Drlovely:BAAANQADCgQJBAAAAA==.Droody:BAAANQABCgIIAgAAAA==.',
El='Ellalais:BAAANQAECgQICgAAAA==.Ellismom:BAABNQAECoEbAAILAAcKUR6+KwAuAgALAAcKUR6+KwAuAgAAAA==.Elyon:BAAANQADCggICAAAAA==.',
En='Enamorada:BAAANQAECgEJAQAAAA==.Enchanceurpp:BAAANQADCggIGQAAAA==.End:BAAANQAECgIIAgAAAA==.',
Eo='Eolyndyn:BAAANQADCgQIBQAAAA==.',
Er='Ereithelda:BAACNQAFFIEFAAIZAAMK1RbRBAD/AAAZAAMK1RbRBAD/AAA1AAQKgSoAAhkACQofJMcBAJMDABkACQofJMcBAJMDAAAA.Ericka:BAAANQADCgYIBwAAAA==.Erina:BAAANQABCggIDwAAAA==.Erowid:BAAANQADCggICwABNQAECgkJKwAXAOYeAA==.Errutu:BAABNQAECoEcAAIaAAgKAxK4FAAdAgAaAAgKAxK4FAAdAgAAAA==.',
Ev='Evox:BAAANQAECgQIBAAAAA==.',
Fa='Fann:BAAANQAECgUIDwAAAA==.Fargrim:BAAANQADCggICAAAAA==.Fauna:BAAANQADCggICAAAAA==.',
Fe='Feathiir:BAAANQADCgEIAQAAAA==.Fewz:BAACNQAFFIEFAAIHAAIKYyQRAgDRAAAHAAIKYyQRAgDRAAA1AAQKgS8AAwcACQpbJUoAANIDAAcACQpbJUoAANIDAAYAAQoQD66BAUEAAAAA.',
Fl='Flakflap:BAAANQAECgUIBQABNQAFFAIIBQAMADsPAA==.Flakov:BAAANQADCggIDgABNQAFFAIIBQAMADsPAA==.Flaktop:BAACNQAFFIEFAAIMAAIKOw+BGAB8AAAMAAIKOw+BGAB8AAA1AAQKgS8AAgwACQoZH24UANwCAAwACQoZH24UANwCAAAA.Flatplate:BAAANQADCgUIBQAAAA==.Fler:BAAANQAECgQIBQAAAA==.',
Fo='Forbacon:BAAANQAECgcIEwAAAA==.Force:BAAANQAECgUIDgAAAA==.Fouris:BAAANQADCggICwAAAA==.',
Fr='Fridgie:BAACNQAFFIEGAAIbAAMKoRDLDQD7AAAbAAMKoRDLDQD7AAA1AAQKgSgAAhsACQqQIkwUACEDABsACQqQIkwUACEDAAAA.Friggenmage:BAAANQAECgYICgAAAA==.Frostbitte:BAAANQADCgEIAQAAAA==.Frozenruby:BAAANQABCggIDQAAAA==.Frozenturtle:BAAANQAECgMIBwAAAA==.',
Ft='Ftwiamtank:BAAANQAECgQIBQABNQAECgYIDwACAAAAAA==.',
Fu='Fuerte:BAAANQABCgQIAwAAAA==.',
Ga='Garcutt:BAABNQAECoEpAAIGAAkKbxw1SADPAgAGAAkKbxw1SADPAgAAAA==.',
Ge='Geddan:BAAANQADCgYICAAAAA==.Genericdh:BAAANQAFFAEIAQAAAA==.Genericpal:BAABNQAECoEeAAIcAAgKDiPEBgAKAwAcAAgKDiPEBgAKAwAAAA==.Geritol:BAAANQADCggICAAAAA==.',
Gi='Gichio:BAAANQAECgUIBQAAAA==.Ginrai:BAAANQADCgUIBQAAAA==.',
Gl='Gladstone:BAAANQAECgMIBQAAAA==.',
Gn='Gnawbear:BAEBNQAECoEYAAIdAAcKNxR1KQDbAQAdAAcKNxR1KQDbAQAAAA==.',
Go='Goatassassin:BAAANQAECgYIDwAAAA==.Goatshifter:BAAANQAECgMIBAABNQAECgYIDwACAAAAAA==.Gobogoolina:BAAANQADCgMIAwAAAA==.',
Gr='Grayeyes:BAAANQADCgMIAwAAAA==.Greenngoblin:BAAANQAECgQIBQAAAA==.Grämps:BAAANQADCgYIBgAAAA==.',
Gu='Guino:BAAANQAECgMIAwAAAA==.',
Gw='Gwenelly:BAAANQADCgYICQAAAA==.',
Ha='Haikuu:BAAANQADCgcIBwAAAA==.Hamnqueso:BAAANQADCgYIDgABNQAECgQIDQACAAAAAA==.Hardeesdelux:BAAANQAECgQIBAAAAA==.Hazis:BAABNQAECoExAAIMAAkKAR+KDgAWAwAMAAkKAR+KDgAWAwAAAA==.',
Hi='Hinala:BAABNQAECoEbAAIMAAkKTQrWSACSAQAMAAkKTQrWSACSAQAAAA==.',
Ho='Holy:BAAANQAECgUIBQABNQAECgkJLwADAEwcAA==.Holydad:BAAANQADCgcIBwAAAA==.Honeybutter:BAABNQAECoEhAAMEAAkKkCTJCQCVAwAEAAkKkCTJCQCVAwAUAAEKdROEJQA+AAAAAA==.Hordebreaker:BAAANQABCgIIAgAAAA==.',
Hu='Huesitos:BAAANQAECgUIDQAAAA==.Huntzilla:BAAANQADCgYICwAAAA==.Huukend:BAABNQAECoEaAAIbAAgK1SA1HwDkAgAbAAgK1SA1HwDkAgAAAA==.',
In='Inanitas:BAAANQADCggICAAAAA==.Innominot:BAAANQAECgEIAQAAAA==.',
Ir='Irukox:BAAANQADCgIIAwAAAA==.',
Ja='Jackoldean:BAAANQADCgMIBgAAAA==.Jacques:BAAANQADCggICAAAAA==.Jadaveon:BAAANQAECgUIBQAAAA==.Jalene:BAAANQAECgQIBgAAAA==.Jargen:BAAANQADCgYIBwABNQADCggICAACAAAAAA==.',
Je='Jettadari:BAAANQAECgYICgABNQAFFAMIBgAWAI8MAA==.Jettadin:BAACNQAFFIEGAAIWAAMKjwwSDwDfAAAWAAMKjwwSDwDfAAA1AAQKgR0AAhYACQobIAcdACMDABYACQobIAcdACMDAAAA.',
Jt='Jt:BAAANQAECgEIAQAAAA==.',
Jw='Jwalker:BAAANQADCgQIBQAAAA==.',
['Jë']='Jëks:BAACNQAFFIEGAAIKAAMKwBlpDQAHAQAKAAMKwBlpDQAHAQA1AAQKgSMAAwoACQotIdgUAPkCAAoACQotIdgUAPkCAB4ABArtDPgfAOIAAAAA.',
Ka='Kakozaps:BAACNQAFFIEGAAMeAAMKLRpxAgANAQAeAAMKLRpxAgANAQADAAEKmAyrIgBHAAA1AAQKgTUAAx4ACQpEIpgCAGwDAB4ACQpNIZgCAGwDAAMACArFIO8jAL4CAAAA.Kallar:BAAANQAECgYIDQABNQAECgYIEgACAAAAAA==.Kayeera:BAAANQAECgIIAwAAAA==.Kaylrandi:BAAANQADCgQICwAAAA==.Kayna:BAAANQAECgUIBQAAAA==.',
Ke='Kearza:BAAANQAECgMIAwAAAA==.Keiyona:BAAANQADCgIIAgABNQAECgUIEQACAAAAAA==.Kennethv:BAAANQAECgQIBwAAAA==.Keny:BAAANQAECgUJBgAAAA==.Kero:BAAANQADCgcICgABNQAECgYIEgACAAAAAA==.Kethra:BAAANQABCgQICAAAAA==.Kev:BAAANQAECggIAgAAAA==.',
Kh='Khalesie:BAAANQADCgIIBAAAAA==.Khibanee:BAAANQAECgEIAgAAAA==.Khiell:BAABNQAECoEaAAMUAAgKDBd2CAAOAgAUAAcKyhd2CAAOAgAEAAIKxw8z/wBtAAAAAA==.Khrominius:BAAANQAECgQICQAAAA==.',
Ki='Kinigit:BAAANQAECgUJCgABNQAFFAIIBQAQAAoUAA==.Kirïtö:BAAANQADCgMIAwAAAA==.Kitaradin:BAAANQAECgUIDgAAAA==.',
Kn='Knghtmre:BAABNQAECoEeAAIGAAkK7BG2gQBAAgAGAAkK7BG2gQBAAgAAAA==.',
Ko='Komamura:BAAANQAECgMIAwAAAA==.Konpalitaa:BAAANQAECgEIAQAAAA==.',
Kr='Kragon:BAAANQADCggICAAAAA==.Krátos:BAAANQAECgcICwAAAA==.',
Ku='Kuranaa:BAAANQAECgEIAQAAAA==.Kurulak:BAABNQAECoEbAAIfAAcKBQt5LgCMAQAfAAcKBQt5LgCMAQAAAA==.',
Ky='Kymru:BAAANQADCgYICQAAAA==.',
La='Lacerveza:BAAANQAECgEIAQAAAA==.Lahyanhou:BAAANQAECgEIAQAAAA==.Lawanorder:BAAANQADCggIBwAAAA==.',
Le='Leriope:BAABNQAECoEcAAIFAAgKXRArYQDkAQAFAAgKXRArYQDkAQAAAA==.',
Li='Lichfiend:BAAANQADCgYICgAAAA==.Lihpfu:BAAANQAECgUIDQABNQAECggIHwAEAKAdAA==.Lilem:BAAANQADCgYICAAAAA==.Limboh:BAAANQADCgcIBwAAAA==.',
Lj='Lj:BAABNQAECoEbAAIRAAgK5RwUJgCdAgARAAgK5RwUJgCdAgAAAA==.',
Lu='Luxure:BAAANQAECgEIAQAAAA==.',
Ma='Maegan:BAAANQADCgcIGwAAAA==.Mager:BAAANQAECgEIAQAAAA==.Mageshyte:BAABNQAECoEoAAIGAAkKCx3FSADNAgAGAAkKCx3FSADNAgABNQAECgkJHgARAMwlAA==.Magolock:BAAANQAECgQICgAAAA==.Magus:BAAANQADCggICAAAAA==.Maidrim:BAABNQAECoEqAAIdAAkKmCDaCwD0AgAdAAkKmCDaCwD0AgAAAA==.Mamajumbo:BAAANQAECgYICAAAAA==.Mana:BAABNQAECoEvAAIDAAkKTBznHADtAgADAAkKTBznHADtAgAAAA==.Marellias:BAAANQAECggIEQABNQAECggIGwAWAOolAA==.Marikel:BAAANQAECgMIAwAAAA==.Marlea:BAAANQAECgYIDgAAAA==.Maruka:BAABNQAECoEmAAIFAAkKyh4PEAAqAwAFAAkKyh4PEAAqAwAAAA==.',
Me='Meletha:BAAANQADCggICAAAAA==.Meronpan:BAAANQADCgIIAgAAAA==.Metahorfasis:BAAANQADCgcIBwAAAA==.',
Mi='Michaelken:BAAANQAECgUICgAAAA==.Midari:BAAANQADCgEIAQAAAA==.Mierin:BAAANQADCgUIBQAAAA==.Mierín:BAAANQAECgIJAgAAAA==.Migrains:BAABNQAECoEbAAIcAAgK+RkTEQA/AgAcAAgK+RkTEQA/AgAAAA==.Milkmesloppy:BAAANQADCgYIBgABNQAECgkJHQAFAP8fAA==.Miskaabin:BAAANQAECgQICwAAAA==.Missdemon:BAAANQADCggICAAAAA==.',
Mo='Mogral:BAAANQABCgMIAwAAAA==.Mojodaddy:BAAANQABCgQIBgAAAA==.Mojogreens:BAAANQADCgUICwAAAA==.Monsart:BAAANQADCggIEAAAAA==.Montura:BAAANQADCgQIBAAAAA==.Moonie:BAAANQADCgYICwAAAA==.Moonpetals:BAAANQADCgMJBQAAAA==.Moralizdormi:BAAANQAECgUIEgAAAA==.',
Mp='Mpd:BAAANQAECgQIBQAAAA==.',
My='Mylendria:BAAANQABCgYIBwAAAA==.Mystique:BAAANQAECgUICwAAAA==.',
['Mí']='Míerín:BAABNQAECoEtAAIbAAkKhiUmAwDBAwAbAAkKhiUmAwDBAwAAAA==.',
Na='Naama:BAAANQADCgQJBQAAAA==.Naelih:BAAANQAECgUIBQAAAA==.Natlès:BAAANQAECgMIAwABNQAECgQJBAACAAAAAA==.Natzu:BAAANQAECgMIBQAAAA==.Naushan:BAAANQADCgIIAgAAAA==.Nazari:BAABNQAECoEgAAIWAAkKsRZBXQArAgAWAAkKsRZBXQArAgAAAA==.',
Ne='Necronu:BAAANQADCggICAABNQAECgkJKwAXAOYeAA==.',
Ni='Nikkolos:BAAANQADCgUIBQAAAA==.',
No='Nogusta:BAACNQAFFIEGAAIEAAMKsAlIGQDLAAAEAAMKsAlIGQDLAAA1AAQKgSkAAgQACQrhFlxKAG0CAAQACQrhFlxKAG0CAAAA.Notdecix:BAACNQAFFIEFAAMTAAIK/xU3DACpAAATAAIK/xU3DACpAAAgAAEKQwAIKgAoAAA1AAQKgR0AAxMACQo1HQkOAN8CABMACQo1HQkOAN8CACAACApdFnA6ADkCAAAA.',
Nu='Nuggets:BAAANQAECgQIBAAAAA==.',
Ob='Obyss:BAAANQADCgQIBAAAAA==.',
On='Onlyshams:BAAANQAECgYIBwAAAA==.Onulock:BAAANQAECgUIBQABNQAECgkJKwAXAOYeAA==.',
Oo='Oorggtejedor:BAAANQADCgUIBQAAAA==.',
Or='Orondo:BAAANQAECgQIBgAAAA==.',
Os='Ospfiend:BAAANQADCgYIBgAAAA==.',
Ou='Oumura:BAAANQAECgQIBAAAAA==.',
Pa='Pallyoop:BAAANQAECgcIEgAAAA==.Pandarina:BAAANQADCgYIBgAAAA==.Papilock:BAAANQADCgUIBQABNQAECgEJAQACAAAAAA==.Pathalogical:BAAANQADCgcIDAABNQAECgUIDgACAAAAAA==.Patharok:BAAANQADCgMJAwABNQAECgUIDgACAAAAAA==.Pathator:BAAANQAECgIIAgABNQAECgUIDgACAAAAAA==.Patheros:BAAANQABCgUJBQABNQAECgUIDgACAAAAAA==.Patholans:BAAANQADCgEIAQABNQAECgUIDgACAAAAAA==.Paxmansigh:BAAANQAECgIIAwAAAA==.',
Ph='Phantöm:BAABNQAECoEcAAIUAAcKjRzRBgA/AgAUAAcKjRzRBgA/AgAAAA==.',
Pl='Placcid:BAAANQAECgcIEAAAAA==.Planknstein:BAAANQAECggIAgAAAA==.Plantoor:BAABNQAECoEcAAIhAAgK6BQ4BABdAgAhAAgK6BQ4BABdAgAAAA==.',
Po='Pockett:BAAANQADCgYIBwAAAA==.Ponarp:BAAANQAECgQJCgAAAA==.Porkchop:BAABNQAECoEcAAMKAAgKtwwqZACKAQAKAAgKtwwqZACKAQADAAQKgQUavAC/AAAAAA==.',
Pr='Prismclaw:BAABNQAECoEbAAIHAAgKlhAgCgDXAQAHAAgKlhAgCgDXAQAAAA==.Processing:BAACNQAFFIEGAAIQAAMKcguVEQDZAAAQAAMKcguVEQDZAAA1AAQKgSoAAhAACQrMHnwYANcCABAACQrMHnwYANcCAAAA.',
Pu='Puddle:BAAANQAECgQIBAAAAA==.Puddleheal:BAAANQAECgEIAQABNQAECgQIBAACAAAAAA==.Puffdamagic:BAABNQAECoEiAAMXAAgKSA3pHQCsAQAXAAgKSA3pHQCsAQAiAAgK6Ak/CgB1AQAAAA==.',
Pw='Pwnstarz:BAAANQADCgYIEQAAAA==.',
Py='Pyous:BAAANQADCgUJCgAAAA==.',
Qp='Qplus:BAAANQAECgUIDwAAAA==.',
Qs='Qstorm:BAAANQADCgcIDQAAAA==.',
Qu='Quaenie:BAAANQAECgUIDwAAAA==.Quintin:BAAANQAECgQIBAAAAA==.',
Ra='Ragetotem:BAAANQADCgIIAgAAAA==.Ragewarg:BAAANQAECgEIAQAAAA==.Raginsteel:BAAANQADCgYICwAAAA==.Ralvarr:BAAANQAECgQIBgAAAA==.Rayleigh:BAAANQAECgQIBwABNQADCgMIAwACAAAAAA==.',
Re='Redchord:BAAANQAECgEIAQAAAA==.Regidør:BAAANQAFFAIIAwAAAA==.Relik:BAAANQAECgUIDgAAAA==.',
Rh='Rhaspus:BAAANQAECgQIBgAAAA==.',
Ri='Rilliccine:BAAANQADCgYIBgAAAA==.Rilliguine:BAAANQADCgQIBAAAAA==.Rillinetti:BAAANQAECgUIDwAAAA==.Rillini:BAAANQAECgMIBAAAAA==.Rilliti:BAAANQADCgcJEgAAAA==.Risky:BAAANQADCgIIAgABNQADCggIFAACAAAAAA==.Rivertam:BAAANQADCggICAAAAA==.',
Ro='Robotnik:BAAANQAECgIIAQAAAA==.Rogu:BAAANQADCgYIEAAAAA==.Rondon:BAAANQAECgUIBwAAAA==.Rookdh:BAACNQAFFIEGAAIBAAMKkwY9DADQAAABAAMKkwY9DADQAAA1AAQKgSkAAgEACQrlH9UNAAgDAAEACQrlH9UNAAgDAAAA.Rosey:BAAANQAECgUIDQAAAA==.Royale:BAAANQAECgYIDAAAAA==.',
Ru='Rudeus:BAAANQAECgEIAQAAAA==.Rudyeightbal:BAAANQADCgYIBgAAAA==.Rum:BAAANQADCggIIwAAAA==.Rustedbarrel:BAAANQAECgUIBwAAAA==.',
Sa='Saelyres:BAAANQAECgIIAwAAAA==.Sagesse:BAAANQADCggJFAAAAA==.Saisera:BAAANQAECgQIBAAAAA==.Samifleur:BAAANQAECgQIBQAAAA==.Sammy:BAAANQAECgUIDwAAAA==.Santaclaaws:BAABNQAECoExAAMfAAkKhiSYBQBpAwAfAAgKjyWYBQBpAwABAAIK4hp3XwCOAAAAAA==.Santafuego:BAAANQAECgUICgABNQAECgkJMQAfAIYkAA==.Santapal:BAABNQAECoEnAAMRAAkK7RvNGADqAgARAAkK7RvNGADqAgAWAAEKBASWXAErAAABNQAECgkJMQAfAIYkAA==.Saphotic:BAAANQAECgcICwABNQAFFAIIBQATAP8VAA==.Saydragon:BAAANQADCgQIBAAAAA==.Sayvil:BAAANQAECgYIEgAAAQ==.',
Se='Selbor:BAAANQADCgMIAwAAAA==.Semmers:BAAANQAECgYIEAAAAA==.Sensational:BAAANQAECgcICAAAAA==.Septiria:BAAANQAECgMIBAAAAA==.Sergio:BAAANQADCgcICgAAAA==.Seyren:BAAANQADCgQIBAAAAA==.',
Sh='Shabelly:BAAANQADCgYJBgABNQADCgYIBgACAAAAAA==.Shalash:BAAANQADCgYIBgABNQAECgkJGwAdANkaAA==.Shamadeano:BAAANQADCgcIFgAAAA==.Shamanshikz:BAAANQAECgcIDgABNQAECgcIHQAMAFgcAA==.Shamiska:BAAANQAECggIAgAAAA==.Shampooh:BAAANQADCggIFAAAAA==.Shamrockk:BAAANQADCggICAAAAA==.Shaokhan:BAABNQAECoEdAAIKAAgKShWtSgDoAQAKAAgKShWtSgDoAQAAAA==.Sharazzy:BAAANQAECgIIAgAAAA==.Sharpcukuee:BAAANQAECgEIAQAAAA==.Shian:BAAANQAECgUIBwAAAA==.Shieldee:BAABNQAECoEXAAIWAAgK8haaXQAqAgAWAAgK8haaXQAqAgAAAA==.Shigaraki:BAAANQAECgYIBgAAAA==.Shikzzs:BAAANQAECgQIDAABNQAECgcIHQAMAFgcAA==.Shockeei:BAABNQAECoEmAAIGAAkKrCJyHgBLAwAGAAkKrCJyHgBLAwAAAA==.Shortdon:BAAANQADCgEIAQAAAA==.Shortebus:BAAANQADCggIHQAAAA==.',
Si='Sighh:BAAANQADCgEIAQAAAA==.Sighhy:BAAANQADCggIDQAAAA==.Sijth:BAABNQAECoE1AAMRAAgKRxzgIAC7AgARAAgKRxzgIAC7AgAWAAQKZw/89QC/AAAAAA==.Silvereyes:BAAANQABCgYIBQAAAA==.Silverwar:BAAANQAECgYIEgAAAA==.Simmi:BAEANQAECgQIBAABNQAFFAMIBgARAOgeAA==.Simmune:BAECNQAFFIEGAAIRAAMK6B5dDAAnAQARAAMK6B5dDAAnAQA1AAQKgSYAAhEACQolIuAGAHwDABEACQolIuAGAHwDAAAA.Sirlavan:BAAANQADCgcIBwAAAA==.Six:BAAANQADCggICAAAAA==.Sixior:BAAANQAECgYIEgAAAA==.Sixogue:BAAANQADCggIDwAAAA==.Sixpath:BAAANQADCgQIAgAAAA==.',
Sk='Skanknstein:BAAANQADCgQIBAAAAA==.Skepti:BAAANQAECgYIDwAAAA==.Skreep:BAAANQADCgUIBQAAAA==.',
Sl='Slybiscuit:BAAANQAECgUIDQAAAA==.',
Sm='Smeeta:BAABNQAECoEbAAIMAAgKgBoFIwBoAgAMAAgKgBoFIwBoAgAAAA==.',
Sn='Sneakerbaby:BAAANQADCgYIBgAAAA==.',
So='Soram:BAAANQADCgYIBgAAAA==.Sosa:BAAANQAECgIIAgABNQAFFAUIDwAcABshAA==.Soulreaver:BAAANQADCgQIBAAAAA==.Sourdevil:BAAANQABCgIJBAAAAA==.Soùl:BAAANQAECgQIBgAAAA==.',
Sp='Sparkley:BAAANQAECgQIBAABNQAECggIIgAXAEgNAA==.Spike:BAAANQAECgQIBAAAAA==.',
St='Starlara:BAAANQABCgYICAAAAA==.Stazz:BAABNQAECoEbAAIbAAgKRAbbgQCnAQAbAAgKRAbbgQCnAQAAAA==.Steelerayne:BAAANQAECgQIBwAAAA==.Stonecrab:BAAANQAECgcIDQAAAA==.Stormcontrol:BAABNQAECoEWAAIDAAcKbA3taACRAQADAAcKbA3taACRAQAAAA==.Stormii:BAAANQAECgEIAQAAAA==.Stormtotem:BAAANQAECgEIAQAAAA==.Strangerdk:BAAANQAECgYIDgAAAA==.Styless:BAAANQABCgYIBwAAAA==.Stðne:BAAANQADCgMIAwAAAA==.',
Sv='Svenraiden:BAAANQABCgEIAQAAAA==.',
Sw='Swagboyxx:BAAANQADCgQIBAAAAA==.Swishersweet:BAABNQAECoEhAAIPAAgKDwejHAAwAQAPAAgKDwejHAAwAQAAAA==.Swordfish:BAAANQAECgIIAwAAAA==.',
Sy='Sybrooke:BAAANQADCgYIDQAAAA==.Syrinne:BAAANQADCgEIAQAAAA==.',
Ta='Tabrieus:BAABNQAECoEcAAIHAAgKoSH9AgDtAgAHAAgKoSH9AgDtAgAAAA==.Taegia:BAAANQADCgUIBQABNQAFFAMIBQAZANUWAA==.Talanth:BAAANQAECgUIDgAAAA==.Talbott:BAAANQADCgEIAQAAAA==.Tarrisx:BAAANQADCgEJAQABNQAECggIGwAMAIAaAA==.Tayon:BAAANQAECgQIBwAAAA==.Tayvin:BAAANQADCgEIAQAAAA==.',
Te='Termana:BAACNQAFFIEGAAIjAAMKlSAUAgAVAQAjAAMKlSAUAgAVAQA1AAQKgSoAAiMACQpmJcAAAMgDACMACQpmJcAAAMgDAAAA.',
Th='Thar:BAAANQADCgUJBQAAAA==.Thassa:BAAANQADCgEIAQAAAA==.Theodoró:BAAANQAECgYICgAAAA==.Thereza:BAAANQAECgQIBAAAAA==.Thug:BAAANQADCgcIFQAAAA==.',
Ti='Tiferet:BAAANQAECgYIEgAAAA==.Tigiw:BAAANQAECgMIAwAAAA==.Tinysunshine:BAAANQAECgMIBAAAAA==.Tinyt:BAAANQADCgMIAwAAAA==.Titonatty:BAAANQABCgQIBAAAAA==.',
To='Tolenkar:BAAANQAECgUIDwAAAA==.Tomato:BAABNQAECoEhAAMOAAkKoRmHBwB5AgAOAAgKDxuHBwB5AgAFAAQKxxREsgAGAQAAAA==.Torfelori:BAAANQAECgQIBQAAAA==.Torvalar:BAABNQAECoEcAAIWAAgKgxCedgDfAQAWAAgKgxCedgDfAQAAAA==.Tove:BAAANQAECgYIDwAAAA==.',
Tr='Trûth:BAABNQAECoEXAAITAAgKfQSxQQDMAAATAAgKfQSxQQDMAAAAAA==.',
Tu='Turdyl:BAABNQAECoEfAAIWAAgKeA7WgADCAQAWAAgKeA7WgADCAQAAAA==.',
Tw='Twindadlock:BAAANQABCgIIAgABNQAECgQIDQACAAAAAA==.',
Ty='Tyfelsion:BAAANQAECgEIAQAAAA==.Tyrelline:BAAANQAECgIJAgAAAA==.Tystrolf:BAAANQADCggIEQAAAA==.',
['Tá']='Tárris:BAAANQAECgUIEQABNQAECggIGwAMAIAaAA==.',
['Tô']='Tôx:BAABNQAECoEbAAMDAAgKyB2tKgCXAgADAAgKyB2tKgCXAgAKAAMKOAnHvwCWAAAAAA==.',
Um='Umbranwings:BAAANQAECgUIDQAAAA==.',
Un='Unheardjp:BAAANQADCgMIBQAAAA==.',
Ur='Ursus:BAAANQAECgYIDAAAAA==.',
Va='Vaerix:BAAANQAECgYIDQAAAA==.Valydrin:BAAANQAECgYIEQAAAA==.',
Ve='Vexadrine:BAACNQAFFIEGAAINAAMKkxKDBADaAAANAAMKkxKDBADaAAA1AAQKgSsAAg0ACQrIHlAEAAQDAA0ACQrIHlAEAAQDAAAA.',
Vo='Vorkhan:BAAANQADCgEIAQAAAA==.',
Vy='Vysis:BAABNQAECoEpAAQTAAkK4RqzDgDVAgATAAkK4RqzDgDVAgAgAAcKTiAbKQCIAgAkAAMKTQypEwCxAAAAAA==.',
['Ví']='Ví:BAAANQAECgEIAQAAAA==.',
We='Weebdestroya:BAAANQADCgIIAgAAAA==.',
Wh='Whisperfål:BAAANQADCgIIAgAAAA==.',
Wi='Wickèr:BAAANQAECgUIEgAAAA==.Wieldblade:BAABNQAECoEcAAMWAAgKoBRFZQASAgAWAAgKoBRFZQASAgARAAIK2AqP2ABmAAAAAA==.',
Wo='Woolverine:BAAANQAECgQIBgAAAA==.',
Wu='Wunderbar:BAAANQAECgUIBwAAAA==.',
Wy='Wyldfire:BAACNQAFFIEFAAIQAAIKChS/FQChAAAQAAIKChS/FQChAAA1AAQKgS8AAhAACQpaImAHAIMDABAACQpaImAHAIMDAAAA.',
Xa='Xanith:BAAANQAECgEIAQAAAA==.Xanyth:BAAANQADCggICAAAAA==.',
Xi='Xia:BAAANQADCgYIBgAAAA==.',
Ya='Yardly:BAAANQADCgMIAgAAAA==.',
Yi='Yia:BAAANQAECgQICAABNQAECgQICgACAAAAAA==.Yilnara:BAAANQAECgEIAQAAAA==.',
Ys='Ysa:BAABNQAECoEZAAMSAAgKciVRBgBKAwASAAgKciVRBgBKAwAZAAIK5AqnNQBoAAAAAA==.',
Za='Zarich:BAAANQAECgYIDwAAAA==.',
Ze='Zekkun:BAAANQADCggICAAAAA==.',
Zo='Zoga:BAEANQADCgUJBQABNQAECgUIEAACAAAAAA==.Zogah:BAEANQADCgQIBAABNQAECgUIEAACAAAAAA==.Zoganian:BAEANQAECgIIAwABNQAECgUIEAACAAAAAA==.',
Zu='Zullthornp:BAAANQADCgUICQAAAA==.',
Zy='Zyaire:BAAANQABCgQIBQAAAA==.',
['Æb']='Æbony:BAAANQABCgIIAgAAAA==.',
['Ço']='Çosmos:BAAANQADCgQIBAAAAA==.',
['Év']='Évélýn:BAAANQADCgUIBQAAAA==.',
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
