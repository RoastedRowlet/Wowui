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

local lookup = {'Unknown-Unknown','Warrior-Arms','Warlock-Demonology','Mage-Frost','Mage-Arcane','Druid-Feral','Hunter-Marksmanship','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Destruction','Druid-Balance','Druid-Guardian','Paladin-Holy','Monk-Windwalker','Warrior-Fury','Priest-Shadow','Paladin-Retribution','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver','Hunter-BeastMastery','Paladin-Protection','Shaman-Elemental','Shaman-Enhancement','Rogue-Assassination','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Protection','Monk-Brewmaster','Priest-Discipline',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=53,date='2026-09-22',data={Ad='Addy:BAAANQAECgcJEAAAAA==.Adelethe:BAAANQADCgYIBgAAAA==.Aditu:BAAANQADCgMIAwAAAA==.',
Ae='Aestian:BAAANQAECgMIBAAAAA==.',
Ah='Ahhotep:BAAANQADCgEIAQAAAA==.',
Ai='Ailysely:BAAANQADCgUJDgAAAA==.Aispere:BAAANQADCgIJAwABNQADCgYJEgABAAAAAA==.',
Al='Alerzhulan:BAAANQAECgUICwAAAA==.Aletheia:BAAANQADCggICAAAAA==.Alfurn:BAAANQADCgIIAgAAAA==.Aliveknightt:BAAANQADCggICAAAAA==.Alledria:BAAANQAECgUJBQAAAA==.Alorely:BAAANQAECgQJBgAAAA==.',
Am='Amanara:BAAANQAECgIJAwAAAA==.Amoonia:BAAANQADCgUICgAAAA==.',
An='Anciientpaw:BAAANQAECgcIEgAAAA==.Andrasomnius:BAAANQAECgQIBAAAAA==.Angbar:BAAANQAECgQJCAAAAA==.Anguirus:BAAANQAECgYJDgAAAA==.Anuksunàmun:BAAANQADCgYIDAAAAA==.',
Aq='Aqulenas:BAAANQAECgEIAQAAAA==.',
Ar='Arakhan:BAAANQADCggIEAAAAA==.Arcadian:BAABNQAECoEbAAICAAgKGA5PZgDcAQACAAgKGA5PZgDcAQAAAA==.Arceeprime:BAAANQADCgcICQAAAA==.Arextheelder:BAAANQAECgQJBQAAAA==.Argentum:BAAANQADCggICAABNQAECgcJEAABAAAAAA==.Armorscales:BAABNQAECoEdAAIDAAkK/x8AEQAFAwADAAkK/x8AEQAFAwAAAA==.Arntraz:BAAANQAECgIIAwAAAA==.Arrabbiato:BAAANQAECggJBAAAAA==.Arronaxx:BAAANQADCgYIEAAAAA==.Arçadia:BAAANQAECgIIAgAAAA==.',
As='Ashnikko:BAAANQADCgYIBgAAAA==.Ashtori:BAAANQABCgQIBgAAAA==.Asprika:BAAANQAECgQIBAAAAA==.Astayoni:BAAANQAECgEIAQAAAA==.Asterfleur:BAAANQADCgYIBwABNQAECgQIBQABAAAAAA==.Astrine:BAABNQAECoEXAAMEAAkKuREnDwA+AQAFAAkKPA4AcgA9AgAEAAYKOhEnDwA+AQAAAA==.',
At='Ataraxya:BAAANQAECgEJAgAAAA==.',
Au='Auberon:BAABNQAECoEaAAIGAAgKQRKoCAAaAgAGAAgKQRKoCAAaAgAAAA==.Aufta:BAAANQAECgUJCgAAAA==.Aumer:BAAANQABCggICwAAAA==.',
Az='Azi:BAABNQAECoEeAAIHAAkKhR1kDQDQAgAHAAkKhR1kDQDQAgAAAA==.Azurite:BAAANQADCgYIDwAAAA==.Azurus:BAAANQABCgEIAQAAAA==.',
Ba='Backpedal:BAAANQADCggJFQAAAA==.Badankhadonk:BAABNQAECoEkAAIIAAkKVySYAgCoAwAIAAkKVySYAgCoAwAAAA==.Bakkutteh:BAAANQABCgIIBQAAAA==.Bakuhiko:BAAANQAECgMJAwAAAA==.Balen:BAAANQAECgEJAgAAAA==.Bandersin:BAAANQADCgUIBQAAAA==.Bansheex:BAAANQADCgQIBAAAAA==.',
Be='Beefmuffinz:BAABNQAECoEWAAIJAAgKzBmSGwCLAgAJAAgKzBmSGwCLAgAAAA==.Beethozart:BAAANQADCgUJCAAAAA==.Belcebu:BAAANQABCggIDgAAAA==.Belholy:BAAANQAECgIJAgAAAA==.Bellafleur:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Bendeekay:BAABNQAECoEhAAIKAAkKniHCBwBWAwAKAAkKniHCBwBWAwAAAA==.Benilok:BAAANQAECgUICAAAAA==.Bethgibbons:BAAANQADCgUJCAAAAA==.',
Bg='Bgpocalypse:BAAANQADCgYIBgAAAA==.',
Bi='Bigsuccubus:BAAANQADCgYJBgAAAA==.',
Bl='Blackblood:BAAANQAECgQJCgAAAA==.Bloodache:BAAANQAECgUJBwAAAA==.Blux:BAAANQAECgIIAgAAAA==.',
Bo='Boil:BAAANQAECgUICgAAAA==.Bonemarrow:BAAANQAECgIIAgAAAA==.',
Br='Brakeable:BAAANQADCgIJBAAAAA==.Braké:BAAANQAECgQJCgAAAA==.Brewskies:BAAANQAECgYIEQAAAA==.Brightstar:BAAANQADCgUIBQAAAA==.Brionthicc:BAAANQAECgMIAwABNQAECgkJJQALADEdAA==.Brownington:BAABNQAECoEXAAQMAAgKfyNdKQAdAgAMAAYKaiFdKQAdAgANAAMKNSTsFAA9AQAGAAIKJyGkGAC/AAAAAA==.Bruhilda:BAAANQAECgQJCAAAAA==.Brìonik:BAABNQAECoElAAMLAAkKMR2bBQCgAgALAAgKJB2bBQCgAgADAAcKMRfdQwANAgAAAA==.',
Bu='Bubbleroundi:BAABNQAECoEZAAIOAAgKJgiHUwCkAQAOAAgKJgiHUwCkAQAAAA==.Bubudder:BAAANQAECgYJEwAAAA==.Buffstuff:BAAANQAECgUIBgAAAA==.',
Ca='Caeviro:BAAANQAECgUICQAAAA==.Canadaishere:BAAANQADCgEIAQAAAA==.Cantheartitz:BAAANQAECgQJCAAAAA==.Catdav:BAAANQAECgIJAgAAAA==.',
Ch='Charbol:BAAANQADCgQIBAABNQADCgYIBwABAAAAAA==.Chelraani:BAAANQAECgEJAgAAAA==.Chess:BAAANQAECgUIBQAAAA==.Chiichard:BAAANQADCgYICAAAAA==.Chunkamonk:BAAANQADCgQIBAAAAA==.',
Ci='Cigar:BAAANQADCgUICQABNQAECgYIEAABAAAAAA==.',
Cl='Clazzicola:BAABNQAECoEbAAIPAAkKkx7sCwDDAgAPAAkKkx7sCwDDAgAAAA==.',
Co='Combatwombat:BAAANQABCgEIAQAAAA==.Conjredcukee:BAAANQAECgIIAgAAAA==.Cowdeer:BAAANQAECgQIBgAAAA==.',
Cp='Cptncrush:BAAANQAECgQJCgAAAA==.',
Cr='Creamsickle:BAAANQABCgIIBAAAAA==.',
Cu='Cupcakes:BAAANQADCgcIEwAAAA==.Cutethulu:BAAANQAECgcIDwAAAA==.',
Cy='Cydarr:BAAANQADCgQIBAAAAA==.Cyther:BAABNQAECoElAAIQAAkKHSVFAADXAwAQAAkKHSVFAADXAwAAAA==.',
Da='Dadbodftw:BAAANQAECgMICQAAAA==.Daddylight:BAAANQAECgQIBwAAAA==.Daelyn:BAAANQADCgYIAgAAAA==.Dakk:BAAANQADCggICAAAAA==.Darkdottie:BAAANQAECgQICgAAAA==.Darkenstormy:BAAANQAECgEIAQAAAA==.Darkmage:BAAANQADCgMJAgAAAA==.',
De='Deadlight:BAAANQAECgcJEQAAAA==.Deadtofall:BAAANQADCgYIDwAAAA==.Deathshikzs:BAABNQAECoEXAAIKAAYKbhm3OQCuAQAKAAYKbhm3OQCuAQAAAA==.Decix:BAAANQAECgIIAgABNQAECgkJGAARALEbAA==.Deet:BAAANQADCgMJAwAAAA==.Deity:BAAANQAECgMIBQABNQAECgYJDAABAAAAAA==.Demonllxll:BAAANQAECgQIDQAAAA==.Demontime:BAAANQADCgMIAwAAAA==.Desolation:BAAANQAECgYIEQAAAA==.Despia:BAAANQAECgEJAgAAAA==.Devastacia:BAAANQADCggICAAAAA==.',
Di='Dicot:BAAANQAECgEJAgAAAA==.Diety:BAAANQAECgYJDAAAAA==.Dimension:BAAANQAECgEIAQAAAA==.Disconnect:BAAANQABCgUICAAAAA==.',
Dj='Djpallyd:BAABNQAECoEWAAISAAgKow97YgDWAQASAAgKow97YgDWAQAAAA==.',
Do='Dotmami:BAAANQAECgUJBQAAAA==.Doughy:BAAANQADCggIEAAAAA==.',
Dr='Dragonu:BAABNQAECoEjAAMTAAkKEx04BgAZAwATAAkKEx04BgAZAwAUAAEKIQ2YLgA1AAAAAA==.Draktyr:BAABNQAECoEhAAMCAAkKIh9XGAAmAwACAAkKIh9XGAAmAwAQAAEKLAY1JAAuAAAAAA==.Drlovely:BAAANQADCgQJBAAAAA==.Droody:BAAANQABCgIIAgAAAA==.',
El='Ellalais:BAAANQAECgQJCgAAAA==.Ellismom:BAAANQAECgYIEQAAAA==.',
En='Enamorada:BAAANQAECgEJAQABNQAECgUJCwABAAAAAA==.Enchanceurpp:BAAANQADCgcJEAAAAA==.End:BAAANQAECgIIAgAAAA==.',
Eo='Eolyndyn:BAAANQADCgEJAQAAAA==.',
Er='Ereithelda:BAABNQAECoElAAIVAAkKHiFvAgBsAwAVAAkKHiFvAgBsAwAAAA==.Ericka:BAAANQADCgYIBwAAAA==.Erina:BAAANQABCggIDwAAAA==.Erowid:BAAANQADCggICwABNQAECgkJIwATABMdAA==.Errutu:BAAANQAECgYIEQAAAA==.',
Ev='Evox:BAAANQADCgcIEgAAAA==.',
Fa='Fann:BAAANQAECgQJCgAAAA==.Fauna:BAAANQADCggICAAAAA==.',
Fe='Feathiir:BAAANQADCgEIAQAAAA==.Fewz:BAABNQAECoEmAAMEAAkKFyVeAAC6AwAEAAkKFyVeAAC6AwAFAAEKEA/HWgFDAAAAAA==.',
Fl='Flakflap:BAAANQAECgUIBQABNQAECgkJJgAKABYfAA==.Flakov:BAAANQADCggIDgABNQAECgkJJgAKABYfAA==.Flaktop:BAABNQAECoEmAAIKAAkKFh95DwDxAgAKAAkKFh95DwDxAgAAAA==.Flatplate:BAAANQADCgUIBQAAAA==.Fler:BAAANQAECgQIBQAAAA==.',
Fo='Forbacon:BAAANQAECgYJDAAAAA==.Force:BAAANQAECgQJCgAAAA==.Fouris:BAAANQADCggICwAAAA==.',
Fr='Fridgie:BAABNQAECoEjAAIWAAkKIiB5FwDuAgAWAAkKIiB5FwDuAgAAAA==.Friggenmage:BAAANQAECgYICgAAAA==.Frostbitte:BAAANQADCgEIAQAAAA==.Frozenruby:BAAANQABCggIDgAAAA==.Frozenturtle:BAAANQAECgMJBAAAAA==.',
Ft='Ftwiamtank:BAAANQAECgIIAgAAAA==.',
Fu='Fuerte:BAAANQABCgQIAwAAAA==.',
Ga='Garcutt:BAABNQAECoEkAAIFAAkK6Bo/QQDHAgAFAAkK6Bo/QQDHAgAAAA==.',
Ge='Geddan:BAAANQADCgYICAAAAA==.Genericpal:BAABNQAECoEZAAIXAAgKdiLlBQAGAwAXAAgKdiLlBQAGAwAAAA==.Geritol:BAAANQADCggICAAAAA==.',
Gi='Gichio:BAAANQAECgUIBQAAAA==.Ginrai:BAAANQADCgUIBQAAAA==.',
Gl='Gladstone:BAAANQAECgMJBQAAAA==.',
Gn='Gnawbear:BAEANQAECgYIEQAAAA==.',
Go='Goatassassin:BAAANQAECgUICQAAAA==.Goatshifter:BAAANQAECgMIBAABNQAECgUICQABAAAAAA==.',
Gr='Grayeyes:BAAANQADCgMIAwAAAA==.Greenngoblin:BAAANQAECgQIBQAAAA==.Grämps:BAAANQADCgYIBgAAAA==.',
Gu='Guino:BAAANQADCgYJCwAAAA==.',
Gw='Gwenelly:BAAANQADCgYJCQAAAA==.',
Ha='Hamnqueso:BAAANQADCgYJDgAAAA==.Hardeesdelux:BAAANQADCgUICQABNQAECgEJAQABAAAAAA==.Hazis:BAABNQAECoEpAAIKAAkK+h30DQACAwAKAAkK+h30DQACAwAAAA==.',
Hi='Hinala:BAAANQAECgYJEwAAAA==.',
Ho='Holy:BAAANQAECgUIBQABNQAECgkJJgAYAHUbAA==.Holydad:BAAANQADCgcIBwAAAA==.Honeybutter:BAABNQAECoEcAAMCAAkKkCTwBQCvAwACAAkKkCTwBQCvAwAQAAEKdRPFHwBBAAAAAA==.Hordebreaker:BAAANQABCgIIAgAAAA==.',
Hu='Huesitos:BAAANQAECgQICQAAAA==.Huntzilla:BAAANQADCgYICwAAAA==.Huukend:BAAANQAECgYIDwAAAA==.',
In='Inanitas:BAAANQADCggICAAAAA==.Innominot:BAAANQADCgUJBQAAAA==.',
Ja='Jackoldean:BAAANQADCgMJBQAAAA==.Jacques:BAAANQADCggJCAAAAA==.Jadaveon:BAAANQAECgUIBQAAAA==.Jalene:BAAANQAECgIJAgAAAA==.Jargen:BAAANQADCgYIBwAAAA==.',
Je='Jettadari:BAAANQAECgYICgABNQAECgkJGAASAEIfAA==.Jettadin:BAABNQAECoEYAAISAAkKQh/aFQArAwASAAkKQh/aFQArAwAAAA==.',
Jt='Jt:BAAANQAECgEJAQAAAA==.',
Jw='Jwalker:BAAANQADCgQIBQAAAA==.',
['Jë']='Jëks:BAABNQAECoEeAAMIAAkKziDxEwDmAgAIAAkKziDxEwDmAgAZAAQK7QzVGwDsAAAAAA==.',
Ka='Kakozaps:BAABNQAECoEuAAMZAAkKUCGOAwA5AwAZAAkK3R2OAwA5AwAYAAgKxSChGgDYAgAAAA==.Kallar:BAAANQAECgUJBwABNQAECgYJDAABAAAAAA==.Kargle:BAAANQABCgEIAQAAAA==.Kayeera:BAAANQAECgEIAQAAAA==.Kaylrandi:BAAANQADCgIIBwAAAA==.Kayna:BAAANQAECgUIBQAAAA==.',
Ke='Kearza:BAAANQADCgYJCgAAAA==.Keiyona:BAAANQADCgIIAgABNQAECgQIDAABAAAAAA==.Kennethv:BAAANQAECgIJAwAAAA==.Keny:BAAANQAECgUJBgAAAA==.Kero:BAAANQADCgcICgABNQAECgYJDAABAAAAAA==.Kev:BAAANQAECggIBgAAAA==.',
Kh='Khibanee:BAAANQAECgEJAQAAAA==.Khiell:BAABNQAECoEWAAMQAAgKyxUuBwABAgAQAAcKWxYuBwABAgACAAIKxw8z4AByAAAAAA==.Khrominius:BAAANQAECgQJCQAAAA==.',
Ki='Kinigit:BAAANQAECgUJCgABNQAECgkJJgAMAKAfAA==.Kirïtö:BAAANQADCgMIAwAAAA==.Kitaradin:BAAANQAECgUIDgAAAA==.',
Kn='Knghtmre:BAABNQAECoEdAAIFAAkKwBFLZwBaAgAFAAkKwBFLZwBaAgAAAA==.',
Ko='Konpalitaa:BAAANQAECgEIAQAAAA==.',
Kr='Kragon:BAAANQADCggICAAAAA==.Krátos:BAAANQAECgYIBgAAAA==.',
Ku='Kuranaa:BAAANQADCgYJEgAAAA==.Kurulak:BAAANQAECgYIEQAAAA==.',
Ky='Kymru:BAAANQADCgYICQAAAA==.',
La='Lacerveza:BAAANQAECgEIAQAAAA==.Lahyanhou:BAAANQAECgEIAQAAAA==.Lawanorder:BAAANQADCggIBwAAAA==.',
Le='Leriope:BAAANQAECgYIEQAAAA==.',
Li='Lichfiend:BAAANQADCgYICgAAAA==.Lickyez:BAAANQABCgEIAQAAAA==.Lihpfu:BAAANQAECgQJCwABNQAECggIGwACAOQcAA==.Lilem:BAAANQADCgYICAAAAA==.',
Lj='Lj:BAAANQAECgYIEQAAAA==.',
Lu='Luxure:BAAANQAECgEIAQAAAA==.',
Ma='Maegan:BAAANQADCgcJFQAAAA==.Mager:BAAANQAECgEIAQAAAA==.Mageshyte:BAABNQAECoEiAAIFAAkKMhyKPADWAgAFAAkKMhyKPADWAgABNQAFFAEIAQABAAAAAA==.Magolock:BAAANQAECgMIBwABNQAECgMIBwABAAAAAA==.Magus:BAAANQADCggICAAAAA==.Maidrim:BAABNQAECoElAAIaAAkKmCDYCAD9AgAaAAkKmCDYCAD9AgAAAA==.Mamajumbo:BAAANQAECgIJAgAAAA==.Mana:BAABNQAECoEmAAIYAAkKdRu+FwDtAgAYAAkKdRu+FwDtAgAAAA==.Marellias:BAAANQAECgcICwABNQAECggIGQASAOolAA==.Marikel:BAAANQADCgYJCAAAAA==.Marlea:BAAANQAECgYICwAAAA==.Maruka:BAABNQAECoEWAAIDAAkKdhsGEAAMAwADAAkKdhsGEAAMAwAAAA==.',
Me='Meletha:BAAANQADCggICAAAAA==.Metahorfasis:BAAANQADCgcIBwAAAA==.',
Mi='Michaelken:BAAANQAECgQJBQAAAA==.Midari:BAAANQADCgEIAQAAAA==.Mierin:BAAANQADCgUIBQAAAA==.Mierín:BAAANQAECgIJAgAAAA==.Migrains:BAAANQAECgYIEAAAAA==.Milkmesloppy:BAAANQADCgYIBgABNQAECgkJHQADAP8fAA==.Miskaabin:BAAANQAECgQJBwAAAA==.Missdemon:BAAANQADCggICAAAAA==.',
Mo='Mojodaddy:BAAANQABCgQIBgAAAA==.Mojogreens:BAAANQADCgUIBgAAAA==.Monsart:BAAANQADCgUJCAAAAA==.Montura:BAAANQADCgQIBAAAAA==.Moonie:BAAANQADCgYICwAAAA==.Moonpetals:BAAANQADCgMJBQAAAA==.Moralizdormi:BAAANQAECgUJDQAAAA==.',
Mp='Mpd:BAAANQAECgEJAgAAAA==.',
My='Mylendria:BAAANQABCgYIBwAAAA==.Mystique:BAAANQAECgQIBwAAAA==.',
['Mí']='Míerín:BAABNQAECoEkAAIWAAkK8CRaBACgAwAWAAkK8CRaBACgAwAAAA==.',
Na='Naama:BAAANQADCgQJBQAAAA==.Naelih:BAAANQADCggIDAAAAA==.Natlès:BAAANQAECgMIAwABNQAECgQJBAABAAAAAA==.Natzu:BAAANQAECgMIAwAAAA==.Naushan:BAAANQADCgIJAgAAAA==.Nazari:BAABNQAECoEZAAISAAkKhBKSVQACAgASAAkKhBKSVQACAgAAAA==.',
Ne='Necronu:BAAANQADCggICAABNQAECgkJIwATABMdAA==.',
Ni='Nikkolos:BAAANQADCgUIBQAAAA==.',
No='Nogusta:BAABNQAECoEkAAICAAkKaxadQQBgAgACAAkKaxadQQBgAgAAAA==.Notdecix:BAABNQAECoEYAAMRAAkKsRvyEACQAgARAAgKexryEACQAgAbAAgKXRYyLABLAgAAAA==.',
Nu='Nuggets:BAAANQAECgQIBAAAAA==.',
Ob='Obyss:BAAANQADCgQIBAAAAA==.',
On='Onlyshams:BAAANQAECgYIBwAAAA==.Onulock:BAAANQADCggICAABNQAECgkJIwATABMdAA==.',
Oo='Oorggtejedor:BAAANQADCgUIBQAAAA==.',
Or='Orondo:BAAANQAECgIJAgAAAA==.',
Os='Ospfiend:BAAANQADCgYIBgAAAA==.',
Ou='Oumura:BAAANQAECgQIBAAAAA==.',
Pa='Pallyoop:BAAANQAECgcIDgAAAA==.Papilock:BAAANQADCgUIBQABNQAECgUJCwABAAAAAA==.Pathalogical:BAAANQADCgUIBQABNQAECgQIDQABAAAAAA==.Patharok:BAAANQADCgMJAwABNQAECgQIDQABAAAAAA==.Pathator:BAAANQAECgIIAgABNQAECgQIDQABAAAAAA==.Patheros:BAAANQABCgUJBQABNQAECgQIDQABAAAAAA==.Paxmansigh:BAAANQADCgcIHgAAAA==.',
Ph='Phantöm:BAABNQAECoEWAAIQAAYKGRykBwDvAQAQAAYKGRykBwDvAQAAAA==.',
Pl='Placcid:BAAANQAECgYICQAAAA==.Planknstein:BAAANQAECgEIAQAAAA==.Plantoor:BAAANQAECgYIEAAAAA==.',
Po='Pockett:BAAANQADCgUIBgAAAA==.Ponarp:BAAANQAECgQJCgAAAA==.Porkchop:BAAANQAECgYIEQAAAA==.',
Pr='Prismclaw:BAAANQAECgYIEQAAAA==.Processing:BAABNQAECoElAAIMAAkK7R2dFgDHAgAMAAkK7R2dFgDHAgAAAA==.',
Pu='Puddleheal:BAAANQAECgEJAQAAAA==.Puffdamagic:BAABNQAECoEaAAITAAgKSA2PGQC0AQATAAgKSA2PGQC0AQAAAA==.',
Pw='Pwnstarz:BAAANQADCgYIEQAAAA==.',
Py='Pyous:BAAANQADCgUJCgAAAA==.',
Qp='Qplus:BAAANQAECgQJCgAAAA==.',
Qs='Qstorm:BAAANQADCgYJBgAAAA==.',
Qu='Quaenie:BAAANQAECgQICgAAAA==.Quintin:BAAANQAECgEJAQAAAA==.',
Ra='Ragetotem:BAAANQADCgIIAgAAAA==.Ragewarg:BAAANQAECgEIAQAAAA==.Raginsteel:BAAANQADCgYICwAAAA==.Ralvarr:BAAANQAECgIIAgAAAA==.Rayleigh:BAAANQAECgIJAwABNQADCgMIAwABAAAAAA==.',
Re='Redchord:BAAANQAECgEIAQAAAA==.Regidør:BAAANQAFFAIIAwAAAA==.Relik:BAAANQAECgQJCgAAAA==.',
Rh='Rhaspus:BAAANQAECgIIAgAAAA==.',
Ri='Rilliccine:BAAANQADCgYIBgAAAA==.Rilliguine:BAAANQADCgQIBAAAAA==.Rillinetti:BAAANQAECgUJCgAAAA==.Rillini:BAAANQAECgMJBAAAAA==.Rilliti:BAAANQADCgcJEgAAAA==.Risky:BAAANQADCgIIAgABNQADCggJFAABAAAAAA==.Rivertam:BAAANQADCggICAAAAA==.',
Ro='Robotnik:BAAANQAECgIIAQAAAA==.Rogu:BAAANQADCgYIEAAAAA==.Rondon:BAAANQAECgEJAgAAAA==.Rookdh:BAABNQAECoEkAAIcAAkKbx0fDgDlAgAcAAkKbx0fDgDlAgAAAA==.Rosey:BAAANQAECgUJCgAAAA==.Royale:BAAANQAECgQIBgAAAA==.',
Ru='Rudyeightbal:BAAANQADCgYIBgAAAA==.Rum:BAAANQADCggIHAAAAA==.Rustedbarrel:BAAANQAECgUIBwAAAA==.',
Sa='Saelyres:BAAANQAECgIIAwAAAA==.Sagesse:BAAANQADCggJFAAAAA==.Samifleur:BAAANQAECgQIBQAAAA==.Sammy:BAAANQAECgQICgAAAA==.Santaclaaws:BAABNQAECoEoAAMdAAkKWiJZCQAeAwAdAAgKHiNZCQAeAwAcAAIK4hqhUACRAAAAAA==.Santafuego:BAAANQAECgUJBQABNQAECgkJKAAdAFoiAA==.Santapal:BAABNQAECoEhAAMOAAkK7RuOEgD3AgAOAAkK7RuOEgD3AgASAAEKBATcLgEsAAABNQAECgkJKAAdAFoiAA==.Saphotic:BAAANQAECgcICwABNQAECgkJGAARALEbAA==.Sayvil:BAAANQAECgYJDAAAAQ==.',
Se='Semmers:BAAANQAECgUJCgAAAA==.Sensational:BAAANQAECgIIAgAAAA==.Septiria:BAAANQAECgEJAQAAAA==.Sergio:BAAANQADCgYJCQAAAA==.Seyren:BAAANQADCgQIBAAAAA==.',
Sh='Shabelly:BAAANQADCgYJBgABNQADCgYIBgABAAAAAA==.Shalash:BAAANQADCgYIBgABNQAECgkJGQAaANkaAA==.Shamadeano:BAAANQADCgcIFgAAAA==.Shamanshikz:BAAANQAECgQJCAABNQAECgYIFwAKAG4ZAA==.Shamiska:BAAANQAECggJAQAAAA==.Shampooh:BAAANQADCggJFAAAAA==.Shamrockk:BAAANQADCggICAAAAA==.Shaokhan:BAAANQAECgcJEgAAAA==.Sharazzy:BAAANQAECgEJAQAAAA==.Sharpcukuee:BAAANQAECgEIAQAAAA==.Shian:BAAANQAECgEJAgAAAA==.Shieldee:BAAANQAECgYIDgAAAA==.Shigaraki:BAAANQADCgQIBAAAAA==.Shikzzs:BAAANQAECgQJCQABNQAECgYIFwAKAG4ZAA==.Shockeei:BAABNQAECoEhAAIFAAkKNiLaFABlAwAFAAkKNiLaFABlAwAAAA==.Shortdon:BAAANQADCgEIAQAAAA==.Shortebus:BAAANQADCggJFQAAAA==.',
Si='Sighh:BAAANQADCgEIAQAAAA==.Sighhy:BAAANQADCggJCAAAAA==.Sijth:BAABNQAECoEnAAMOAAcKtx0KKABqAgAOAAcKtx0KKABqAgASAAQKZw9FzADLAAAAAA==.Silvereyes:BAAANQABCgYIBgAAAA==.Silverwar:BAAANQAECgYJDAAAAA==.Simmune:BAEBNQAECoElAAIOAAkKeCEFBgB2AwAOAAkKeCEFBgB2AwAAAA==.Sinrei:BAAANQABCgEIAQAAAA==.Six:BAAANQADCggICAAAAA==.Sixior:BAAANQAECgYJDAAAAA==.Sixogue:BAAANQADCggJCAAAAA==.Sixpath:BAAANQADCgQIAgAAAA==.',
Sk='Skarn:BAAANQABCgEIAQAAAA==.Skepti:BAAANQAECgYJDAAAAA==.Skreep:BAAANQADCgUIBQAAAA==.',
Sl='Slybiscuit:BAAANQAECgQJCAAAAA==.',
Sm='Smeeta:BAAANQAECgcIEwAAAA==.',
Sn='Sneakerbaby:BAAANQADCgYIBgAAAA==.',
So='Soram:BAAANQADCgYIBgAAAA==.Soulreaver:BAAANQADCgQIBAAAAA==.Sourdevil:BAAANQABCgIJBQAAAA==.Soùl:BAAANQAECgIJAgAAAA==.',
Sp='Sparkley:BAAANQAECgQIBAABNQAECggIGgATAEgNAA==.Spike:BAAANQADCgcIEAAAAA==.',
St='Starlara:BAAANQABCgYICAAAAA==.Stazz:BAAANQAECgYIEAAAAA==.Steelerayne:BAAANQAECgIJAwAAAA==.Stonecrab:BAAANQAECgcIDQAAAA==.Stormcontrol:BAAANQAECgYJDgAAAA==.Stormii:BAAANQADCgcJDQAAAA==.Stormtotem:BAAANQADCgYIDQAAAA==.Strangerdk:BAAANQAECgQICAAAAA==.Styless:BAAANQABCgYIBwAAAA==.Stðne:BAAANQADCgMIAwAAAA==.',
Sv='Svenraiden:BAAANQABCgEIAQAAAA==.',
Sw='Swagboyxx:BAAANQADCgQIBAAAAA==.Swishersweet:BAABNQAECoEZAAINAAgK0Qa3FQAyAQANAAgK0Qa3FQAyAQAAAA==.Swordfish:BAAANQAECgEIAQAAAA==.',
Sy='Sybrooke:BAAANQADCgYICQAAAA==.Syrinne:BAAANQADCgEIAQAAAA==.',
Ta='Tabrieus:BAAANQAECgYIEQAAAA==.Taegia:BAAANQADCgUIBQABNQAECgkJJQAVAB4hAA==.Talanth:BAAANQAECgQJCQAAAA==.Talbott:BAAANQADCgEIAQAAAA==.Tarrisx:BAAANQADCgEJAQABNQAECgcIEwABAAAAAA==.Tayon:BAAANQAECgIJAwAAAA==.Tayvin:BAAANQADCgEIAQAAAA==.',
Te='Termana:BAABNQAECoElAAIeAAkKViV0AADXAwAeAAkKViV0AADXAwAAAA==.',
Th='Thar:BAAANQADCgUJBQAAAA==.Thassa:BAAANQADCgEIAQAAAA==.Thatsmypurse:BAAANQADCggJCAAAAA==.Theodoró:BAAANQAECgYJCgAAAA==.Thereza:BAAANQAECgMIAwAAAA==.Thug:BAAANQADCgcIFQAAAA==.',
Ti='Tiferet:BAAANQAECgYJDAAAAA==.Tigiw:BAAANQADCgYICgAAAA==.Tinysunshine:BAAANQAECgIJAgAAAA==.Tinyt:BAAANQADCgMIAwAAAA==.Titonatty:BAAANQABCgQIBAAAAA==.',
To='Tolenkar:BAAANQAECgQJCgAAAA==.Tomato:BAABNQAECoEcAAMLAAkKfReGBwBuAgALAAgK/RiGBwBuAgADAAQKERQWlwAGAQAAAA==.Torfelori:BAAANQAECgQIBAAAAA==.Torvalar:BAAANQAECgYIEQAAAA==.Tove:BAAANQAECgYJCwAAAA==.',
Tr='Trûth:BAAANQAECggIDwAAAA==.',
Tu='Turdyl:BAABNQAECoEYAAISAAgKcQ2WawC6AQASAAgKcQ2WawC6AQAAAA==.',
Ty='Tyfelsion:BAAANQAECgEIAQAAAA==.Tyrelline:BAAANQAECgIJAgAAAA==.Tystrolf:BAAANQADCggICgAAAA==.',
['Tá']='Tárris:BAAANQAECgQIBAABNQAECgcIEwABAAAAAA==.',
['Tô']='Tôx:BAABNQAECoEZAAMYAAgKXh2+IQCjAgAYAAgKXh2+IQCjAgAIAAMKOAm5pAChAAAAAA==.',
Um='Umbranwings:BAAANQAECgQJCAAAAA==.',
Un='Unheardjp:BAAANQADCgMIBQAAAA==.',
Ur='Ursus:BAAANQAECgQIBgAAAA==.',
Va='Vaerix:BAAANQAECgYIBwAAAA==.Valydrin:BAAANQAECgUICwAAAA==.',
Ve='Vexadrine:BAABNQAECoEmAAIfAAkKox6MAwANAwAfAAkKox6MAwANAwAAAA==.',
Vo='Vorkhan:BAAANQADCgEIAQAAAA==.',
Vy='Vysis:BAABNQAECoEiAAQRAAkK0RXwEACQAgARAAkK0RXwEACQAgAbAAcKDx/BHwCPAgAgAAMKTQxzEAC4AAAAAA==.',
['Ví']='Ví:BAAANQADCgYJBgAAAA==.',
Wa='Waroby:BAAANQABCgEIAQAAAA==.',
We='Weebdestroya:BAAANQADCgIIAgAAAA==.',
Wh='Whisperfål:BAAANQADCgIIAgAAAA==.',
Wi='Wickèr:BAAANQAECgUJDQAAAA==.Wieldblade:BAAANQAECgcIEQAAAA==.',
Wo='Woolverine:BAAANQAECgIJAgAAAA==.',
Wu='Wunderbar:BAAANQAECgEJAgAAAA==.',
Wy='Wyldfire:BAABNQAECoEmAAIMAAkKoB9kDAA6AwAMAAkKoB9kDAA6AwAAAA==.',
Xa='Xanith:BAAANQADCgYIBgAAAA==.',
Xi='Xia:BAAANQADCgYIBgAAAA==.',
Yi='Yia:BAAANQAECgMIBwAAAA==.Yilnara:BAAANQAECgEIAQAAAA==.',
Ys='Ysa:BAABNQAECoEXAAMPAAgKciUKBABuAwAPAAgKciUKBABuAwAVAAIK5Ap9LgBvAAAAAA==.',
Za='Zarich:BAAANQAECgUJCQAAAA==.',
Ze='Zekkun:BAAANQADCggICAAAAA==.',
Zo='Zoga:BAEANQADCgUJBQABNQAECgUJCwABAAAAAA==.Zogah:BAEANQADCgQIBAABNQAECgUJCwABAAAAAA==.Zoganian:BAEANQAECgIIAwABNQAECgUJCwABAAAAAA==.',
Zu='Zullthornp:BAAANQADCgUICQAAAA==.',
Zy='Zyaire:BAAANQABCgQIBQAAAA==.',
['Æb']='Æbony:BAAANQABCgIIAgAAAA==.',
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
