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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=53,date='2026-09-01',data={Ad='Addy:BAAANQAECgEIAQAAAA==.Adelethe:BAAANQADCgYIBgAAAA==.',
Ae='Aestian:BAAANQADCgcICQAAAA==.',
Ai='Ailysely:BAAANQADCgQIBQAAAA==.Aispere:BAAANQADCgEIAQABNQADCgQIBgABAAAAAA==.',
Al='Alerzhulan:BAAANQADCgYIDAAAAA==.Aliveknightt:BAAANQADCggICAAAAA==.Alorely:BAAANQADCgYIDAAAAA==.',
Am='Amanara:BAAANQADCgQIBAAAAA==.Amoonia:BAAANQADCgUIBQAAAA==.',
An='Anciientpaw:BAAANQAECgQIBQAAAA==.Andrasomnius:BAAANQADCgcIBwAAAA==.Angbar:BAAANQADCggIDgAAAA==.Anguirus:BAAANQAECgEIAQAAAA==.Anuksunàmun:BAAANQADCgYIDAAAAA==.',
Aq='Aqulenas:BAAANQAECgEIAQAAAA==.',
Ar='Arcadian:BAAANQAECgQIBgAAAA==.Arceeprime:BAAANQADCgEIAgAAAA==.Arextheelder:BAAANQADCgYICQAAAA==.Armorscales:BAAANQAECgYICgAAAA==.Arçadia:BAAANQAECgIIAgAAAA==.',
As='Astayoni:BAAANQADCgQIBgAAAA==.Astrine:BAAANQADCggICAAAAA==.',
At='Ataraxya:BAAANQADCgQICAAAAA==.',
Au='Auberon:BAAANQAECgQIBAAAAA==.Aufta:BAAANQADCgcIDQAAAA==.Aumer:BAAANQABCgIIAgAAAA==.',
Az='Azi:BAAANQAECgcICwAAAA==.Azurite:BAAANQADCgYIBgAAAA==.',
Ba='Backpedal:BAAANQADCgcIDAAAAA==.Badankhadonk:BAAANQAECgYIBgAAAA==.Balen:BAAANQADCgYIBgAAAA==.Bandersin:BAAANQADCgUIBQAAAA==.',
Be='Beethozart:BAAANQADCgMIAwAAAA==.Belcebu:BAAANQABCgQIBAAAAA==.Belholy:BAAANQADCgYICwAAAA==.Bendeekay:BAAANQAECgYIBgAAAA==.Bethgibbons:BAAANQADCgQIBQAAAA==.',
Bg='Bgpocalypse:BAAANQADCgYIBgAAAA==.',
Bl='Blackblood:BAAANQADCggIDgAAAA==.Bloodache:BAAANQADCggIDAAAAA==.Blux:BAAANQADCgYIBgAAAA==.',
Bo='Boil:BAAANQADCgYICwAAAA==.Bonemarrow:BAAANQADCgYIBgAAAA==.',
Br='Brakeable:BAAANQADCgIIAgAAAA==.Braké:BAAANQADCggIDgAAAA==.Brewskies:BAAANQAECgEIAQAAAA==.Brightstar:BAAANQADCgUIBQAAAA==.Brionthicc:BAAANQAECgIIAgABNQAECgcICwABAAAAAA==.Brownington:BAAANQAECgEIAQAAAA==.Bruhilda:BAAANQADCgYICQAAAA==.Brìonik:BAAANQAECgcICwAAAA==.',
Bu='Bubbleroundi:BAAANQAECgMIAwAAAA==.Bubudder:BAAANQAECgEIAQAAAA==.Buffstuff:BAAANQAECgEIAQAAAA==.',
Ca='Caeviro:BAAANQAECgEIAQAAAA==.Cantheartitz:BAAANQAECgEIAQAAAA==.Catdav:BAAANQADCgYICQAAAA==.',
Ch='Chelraani:BAAANQADCgYIBgAAAA==.Chiichard:BAAANQADCgIIAgAAAA==.Chunkamonk:BAAANQADCgQIBAAAAA==.',
Ci='Cigar:BAAANQADCgUIBQABNQAECgUIBQABAAAAAA==.',
Cl='Clazzicola:BAAANQAECgYICAAAAA==.',
Co='Cowdeer:BAAANQADCgYIDgAAAA==.',
Cp='Cptncrush:BAAANQADCgYIDAAAAA==.',
Cu='Cutethulu:BAAANQADCggIDAAAAA==.',
Cy='Cyther:BAAANQAECgcICwAAAA==.',
Da='Dadbodftw:BAAANQADCgUIBQAAAA==.Daddylight:BAAANQADCgcICgAAAA==.Dakk:BAAANQADCggICAAAAA==.Darkdottie:BAAANQADCgcICwAAAA==.Darkenstormy:BAAANQADCgYICwAAAA==.Dayday:BAAANQADCggICAAAAA==.',
De='Deadlight:BAAANQAECgMIAwAAAA==.Deadtofall:BAAANQADCgQIBAAAAA==.Deathshikzs:BAAANQAECgYIDAAAAA==.Decix:BAAANQAECgIIAgABNQAECgcICwABAAAAAA==.Deity:BAAANQADCgIIAgABNQADCggIBwABAAAAAA==.Demonllxll:BAAANQAECgEIAQAAAA==.Desolation:BAAANQAECgEIAQAAAA==.Despia:BAAANQADCgYICgAAAA==.',
Di='Dicot:BAAANQADCgYICgAAAA==.Diety:BAAANQADCggIBwAAAA==.Dimension:BAAANQABCgMIAwAAAA==.Disconnect:BAAANQABCgQIBAAAAA==.',
Dj='Djpallyd:BAAANQAECgIIAwAAAA==.',
Do='Doughy:BAAANQADCggICAAAAA==.',
Dr='Dragonu:BAAANQAECgUIBQAAAA==.Draktyr:BAAANQAECgcIBwAAAA==.Droody:BAAANQABCgIIAgAAAA==.',
El='Ellalais:BAAANQADCggIDgAAAA==.Ellismom:BAAANQAECgEIAQAAAA==.',
En='End:BAAANQADCgMIAwABNQADCgYIBgABAAAAAA==.',
Er='Ereithelda:BAAANQAECgcICwAAAA==.Ericka:BAAANQADCgEIAQAAAA==.Erowid:BAAANQADCggICAABNQAECgUIBQABAAAAAA==.Errutu:BAAANQAECgEIAQAAAA==.',
Ev='Evox:BAAANQADCgYICwAAAA==.',
Fa='Fann:BAAANQADCggIDgAAAA==.',
Fe='Feathiir:BAAANQADCgEIAQAAAA==.Fewz:BAAANQAECgYICgAAAA==.',
Fl='Flakov:BAAANQADCggIDgABNQAECgYICgABAAAAAA==.Flaktop:BAAANQAECgYICgAAAA==.Flatplate:BAAANQADCgUIBQAAAA==.Fler:BAAANQAECgEIAQAAAA==.',
Fo='Forbacon:BAAANQADCggIDQAAAA==.Force:BAAANQADCggIDgAAAA==.Fouris:BAAANQADCgUIBgAAAA==.',
Fr='Fridgie:BAAANQAECgcICwAAAA==.Friggenmage:BAAANQAECgYICgAAAA==.Frozenruby:BAAANQABCgQIBQAAAA==.Frozenturtle:BAAANQADCgcICwAAAA==.',
Ft='Ftwiamtank:BAAANQADCgMIAwABNQADCggIEwABAAAAAA==.',
Ga='Garcutt:BAAANQAECgYICgAAAA==.',
Ge='Geddan:BAAANQADCgQIBgAAAA==.Genericpal:BAAANQAECgQIBAAAAA==.',
Gi='Ginrai:BAAANQADCgUIBQAAAA==.',
Gl='Gladstone:BAAANQADCgQIBAAAAA==.',
Gn='Gnawbear:BAEANQAECgEIAQAAAA==.',
Go='Goatshifter:BAAANQAECgEIAQAAAA==.',
Gr='Grayeyes:BAAANQADCgMIAwAAAA==.Greenngoblin:BAAANQADCgYIBgAAAA==.Grämps:BAAANQADCgYIBgAAAA==.',
Gu='Guino:BAAANQADCgUIBQAAAA==.',
Gw='Gwenelly:BAAANQADCgYICQAAAA==.',
Ha='Hamnqueso:BAAANQADCgQIBAAAAA==.Hardeesdelux:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Hazis:BAAANQAECgYICgAAAA==.',
Hi='Hinala:BAAANQAECgQIBgAAAA==.',
Ho='Holy:BAAANQADCggIDgABNQAECgYICgABAAAAAA==.Hordebreaker:BAAANQABCgIIAgAAAA==.',
Hu='Huesitos:BAAANQAECgIIAgAAAA==.Huukend:BAAANQAECgEIAQAAAA==.',
In='Innominot:BAAANQADCgUIBQAAAA==.',
Ja='Jadaveon:BAAANQADCggIDgAAAA==.Jalene:BAAANQADCgEIAQAAAA==.',
Je='Jettadari:BAAANQAECgYICgAAAA==.Jettadin:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.',
Jw='Jwalker:BAAANQADCgQIBQAAAA==.',
['Jë']='Jëks:BAAANQAECgcICwAAAA==.',
Ka='Kakozaps:BAAANQAECgcICwAAAA==.Kallar:BAAANQADCggIDgAAAA==.Kataradin:BAAANQAECgEIAQAAAA==.Kayeera:BAAANQADCgQIBgAAAA==.Kaylrandi:BAAANQADCgIIBAAAAA==.',
Ke='Kearza:BAAANQADCgUIBQAAAA==.Keiyona:BAAANQADCgIIAgABNQADCgcIDQABAAAAAA==.Kennethv:BAAANQADCgYICwAAAA==.Keny:BAAANQAECgEIAQAAAA==.Kero:BAAANQADCgMIAwABNQADCggIDgABAAAAAA==.',
Kh='Khibanee:BAAANQADCgcICwAAAA==.Khiell:BAAANQAECgYIBgAAAA==.Khrominius:BAAANQADCggIDgAAAA==.',
Ki='Kinigit:BAAANQADCggICAABNQAECgYICgABAAAAAA==.Kirïtö:BAAANQADCgMIAwAAAA==.',
Kn='Knghtmre:BAAANQAECgUIBwAAAA==.',
Ku='Kuranaa:BAAANQADCgQIBgAAAA==.Kurulak:BAAANQAECgEIAQAAAA==.',
Ky='Kymru:BAAANQADCgUIBgAAAA==.',
La='Lacerveza:BAAANQADCgUIBwAAAA==.',
Le='Leriope:BAAANQAECgEIAQAAAA==.',
Li='Lichfiend:BAAANQADCgYICgAAAA==.Lihpfu:BAAANQADCggIEAABNQAECgMIBgABAAAAAA==.Lilem:BAAANQADCgIIAgAAAA==.',
Lj='Lj:BAAANQAECgEIAQAAAA==.',
Lu='Luxure:BAAANQADCgUIBQAAAA==.',
Ma='Maegan:BAAANQADCgcIDQAAAA==.Mager:BAAANQADCgQIBQAAAA==.Mageshyte:BAAANQAECgcICQAAAA==.Maidrim:BAAANQAECgcICwAAAA==.Mamajumbo:BAAANQADCgcIDQAAAA==.Mana:BAAANQAECgYICgAAAA==.Marellias:BAAANQADCggICQABNQAECgcIBwABAAAAAA==.Marikel:BAAANQADCgIIAgAAAA==.',
Me='Meletha:BAAANQADCggICAAAAA==.',
Mi='Michaelken:BAAANQADCggIDgAAAA==.Midari:BAAANQADCgEIAQAAAA==.Mierin:BAAANQADCgUIBQAAAA==.Migrains:BAAANQAECgEIAQAAAA==.Milkmesloppy:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.Miskaabin:BAAANQADCgYICwAAAA==.',
Mo='Mojogreens:BAAANQADCgUIBQAAAA==.Moralizdormi:BAAANQAECgEIAQAAAA==.',
Mp='Mpd:BAAANQADCggICQAAAA==.',
My='Mystique:BAAANQADCgYIDAAAAA==.',
['Mí']='Míerín:BAAANQAECgYICgAAAA==.',
Na='Naama:BAAANQADCgEIAQAAAA==.Naushan:BAAANQADCgIIAgAAAA==.Nazari:BAAANQAECgYICgAAAA==.',
Ne='Necronu:BAAANQADCggICAABNQAECgUIBQABAAAAAA==.',
No='Nogusta:BAAANQAECgcICwAAAA==.',
Nu='Nuggets:BAAANQADCgYICwAAAA==.',
Ob='Obyss:BAAANQADCgQIBAAAAA==.',
On='Onlyshams:BAAANQAECgIIAwAAAA==.',
Oo='Oorggtejedor:BAAANQADCgUIBQAAAA==.',
Or='Orondo:BAAANQADCgYICwAAAA==.',
Ou='Oumura:BAAANQADCgcIBwAAAA==.',
Pa='Paxmansigh:BAAANQADCgYIDAAAAA==.',
Ph='Phantöm:BAAANQAECgQIBAAAAA==.',
Pl='Placcid:BAAANQAECgEIAQAAAA==.Planknstein:BAAANQADCgQIBgAAAA==.Plantoor:BAAANQADCggIEAAAAA==.',
Po='Pockett:BAAANQADCgMIAwAAAA==.Ponarp:BAAANQADCgMIAwAAAA==.Porkchop:BAAANQAECgEIAQAAAA==.',
Pr='Prismclaw:BAAANQAECgEIAQAAAA==.Processing:BAAANQAECgcICwAAAA==.',
Pu='Puddleheal:BAAANQADCgYIBgAAAA==.Puffdamagic:BAAANQAECgQIBAAAAA==.',
Pw='Pwnstarz:BAAANQADCgQIBgAAAA==.',
Py='Pyous:BAAANQADCgUICgAAAA==.',
Qp='Qplus:BAAANQADCggIDgAAAA==.',
Qu='Quaenie:BAAANQADCggIDgAAAA==.Quintin:BAAANQADCgUICAAAAA==.',
Ra='Ragewarg:BAAANQAECgEIAQAAAA==.Raginsteel:BAAANQADCgYICAAAAA==.Ralvarr:BAAANQADCgQIBAAAAA==.Rayleigh:BAAANQADCgYICwABNQADCgMIAwABAAAAAA==.',
Re='Redchord:BAAANQADCgYIDAAAAA==.Regidør:BAAANQAECgYICAAAAA==.Relik:BAAANQADCggIDgAAAA==.',
Ri='Rillini:BAAANQADCgcIDAAAAA==.',
Ro='Rogu:BAAANQADCgUIBQAAAA==.Rondon:BAAANQADCgYICgAAAA==.Rookdh:BAAANQAECgcICwAAAA==.Royale:BAAANQADCgcICwAAAA==.',
Ru='Rudyeightbal:BAAANQADCgYIBgAAAA==.Rum:BAAANQADCggICAAAAA==.Rustedbarrel:BAAANQAECgMIAwAAAA==.',
Sa='Saelyres:BAAANQADCgcICwAAAA==.Samifleur:BAAANQADCggICAAAAA==.Sammy:BAAANQADCggIDgAAAA==.Santaclaaws:BAAANQAECgYICwAAAA==.Santapal:BAAANQAECgUIBwABNQAECgYICwABAAAAAA==.Saphotic:BAAANQAECgcICwAAAA==.Sayvil:BAAANQADCggIDgABNQADCggIDgABAAAAAQ==.',
Se='Semmers:BAAANQADCggIDwAAAA==.Sensational:BAAANQADCgUIBQAAAA==.Seyren:BAAANQADCgQIBAAAAA==.',
Sh='Shalash:BAAANQADCgUIBQABNQAECgUIBgABAAAAAA==.Shamadeano:BAAANQADCgYICAAAAA==.Shamiska:BAAANQADCgUIBQAAAA==.Shampooh:BAAANQADCgUIBgAAAA==.Shaokhan:BAAANQADCggIDwAAAA==.Shian:BAAANQADCgYICgAAAA==.Shieldee:BAAANQAECgEIAQAAAA==.Shikzzs:BAAANQAECgQIBgAAAA==.Shockeei:BAAANQAECgQIBgAAAA==.',
Si='Sighh:BAAANQADCgEIAQAAAA==.Sijth:BAAANQAECgQIBgAAAA==.Silverwar:BAAANQADCggICAAAAA==.Simmune:BAEANQAECgcICwAAAA==.Sixior:BAAANQADCggIDQAAAA==.Sixpath:BAAANQADCgQIAgAAAA==.',
Sk='Skepti:BAAANQADCgYICQAAAA==.',
Sl='Slybiscuit:BAAANQADCgcIDAAAAA==.',
Sm='Smeeta:BAAANQAECgIIAgAAAA==.',
So='Soram:BAAANQADCgYIBgAAAA==.Soùl:BAAANQADCggIDgAAAA==.',
Sp='Spike:BAAANQADCgIIAgAAAA==.',
St='Stabystâb:BAAANQADCgUICQAAAA==.Stazz:BAAANQAECgEIAQAAAA==.Steelerayne:BAAANQADCgYICwAAAA==.Stonecrab:BAAANQAECgEIAQAAAA==.Stormcontrol:BAAANQADCgIIAgAAAA==.Strangerdk:BAAANQADCgcIDQAAAA==.Styless:BAAANQABCgIIAgAAAA==.',
Sw='Swishersweet:BAAANQAECgQIBAAAAA==.Swordfish:BAAANQADCgQIBgAAAA==.',
Sy='Sybrooke:BAAANQADCgUIBgAAAA==.Syrinne:BAAANQADCgEIAQAAAA==.',
Ta='Tabrieus:BAAANQAECgEIAQAAAA==.Talanth:BAAANQADCggIDgAAAA==.Tayon:BAAANQADCgEIAQAAAA==.Tayvin:BAAANQADCgEIAQAAAA==.',
Te='Termana:BAAANQAECgcICwAAAA==.',
Th='Thug:BAAANQADCgcIDgAAAA==.',
Ti='Tiferet:BAAANQADCggIDQAAAA==.Tigiw:BAAANQADCgUIBQAAAA==.Tinysunshine:BAAANQADCgUIBQAAAA==.Titonatty:BAAANQABCgIIAgAAAA==.',
To='Tolenkar:BAAANQADCggIDgAAAA==.Tomato:BAAANQAECgMIAwAAAA==.Torvalar:BAAANQAECgEIAQAAAA==.Tove:BAAANQADCggIDQAAAA==.',
Tu='Turdyl:BAAANQAECgIIAgAAAA==.',
Ty='Tyfelsion:BAAANQADCggIDQAAAA==.Tyrelline:BAAANQAECgIIAgAAAA==.',
['Tô']='Tôx:BAAANQAECgMIAwAAAA==.',
Un='Unheardjp:BAAANQADCgMIAwAAAA==.',
Ur='Ursus:BAAANQADCgcICgAAAA==.',
Va='Vaerix:BAAANQADCggIDwAAAA==.Valydrin:BAAANQAECgEIAQAAAA==.',
Vy='Vysis:BAAANQAECgcICAAAAA==.',
We='Weebdestroya:BAAANQADCgIIAgAAAA==.',
Wi='Wickèr:BAAANQAECgIIAgAAAA==.Wieldblade:BAAANQAECgIIAgAAAA==.',
Wu='Wunderbar:BAAANQADCgYICgAAAA==.',
Wy='Wyldfire:BAAANQAECgYICgAAAA==.',
Yi='Yilnara:BAAANQADCgYIBwAAAA==.',
Ys='Ysa:BAAANQAECgMIAwAAAA==.',
Za='Zarich:BAAANQAECgIIAQAAAA==.',
Ze='Zekkun:BAAANQADCggICAAAAA==.',
Zo='Zoganian:BAEANQADCgEIAQAAAA==.',
['Æb']='Æbony:BAAANQABCgIIAgAAAA==.',
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
