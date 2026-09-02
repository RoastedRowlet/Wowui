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

local lookup = {'Unknown-Unknown','Evoker-Preservation','Rogue-Subtlety','DeathKnight-Frost','Priest-Holy',}
local provider = {region='US',realm='Stormrage',name='US',type='subscribers',zone=53,date='2026-09-01',data={Ae='Aeondale:BAEANQAECgYICQAAAA==.',
Ag='Agamo:BAEANQADCgYIBgAAAA==.',
Ai='Aisllin:BAEANQAFFAIIAgAAAA==.',
Al='Alahno:BAEANQAECgUIBwAAAA==.Alascene:BAEANQAECgUIBgABNQAFFAIIAgABAAAAAA==.Alvanys:BAEANQAECgMIAwAAAA==.',
Am='Amarindre:BAEANQAECggIDQAAAA==.',
An='Anniestraza:BAEANQAECgUICQAAAA==.',
Ar='Archítecture:BAEANQAECgEIAQAAAA==.Artemisdeath:BAEANQADCgQIBAAAAA==.Artemisshock:BAEANQADCgMIAwABNQADCgQIBAABAAAAAA==.',
As='Ashjik:BAEANQAECgYICgAAAA==.Askaori:BAEANQAECgEIAQABNQAFFAUIBwACAJoXAA==.Asrei:BAEANQAECgEIAQABNQAFFAUIBwACAJoXAA==.',
At='Atemae:BAEANQAECgEIAQAAAA==.Atemea:BAEANQADCgYICgABNQAECgEIAQABAAAAAA==.',
Ay='Ayrriiss:BAEANQAECgEIAQABNQABCgEIAQABAAAAAA==.',
Az='Azraelis:BAEANQADCggICAABNQAECgcIDQABAAAAAA==.Azraelisa:BAEANQAECgcIDQAAAA==.',
Bi='Bignumbyguy:BAEBNQAECoEPAAIDAAkJ9yNGAADUAwmODQAAAgBgAHUNAAACAGMAfw0AAAIAXgCpDQAAAgBZAFwNAAACAF4AXQ0AAAIAYABlDQAAAQBGAKQNAAABAFYAMw0AAAEAYwADAAkJ9yNGAADUAwmODQAAAgBgAHUNAAACAGMAfw0AAAIAXgCpDQAAAgBZAFwNAAACAF4AXQ0AAAIAYABlDQAAAQBGAKQNAAABAFYAMw0AAAEAYwAAAA==.',
Bl='Blunch:BAEANQAECgYICQAAAA==.',
Bo='Boodybear:BAEANQADCgcIDQAAAA==.Bopboopbonk:BAEANQAECggIDwABNQAECgMIAwABAAAAAA==.Bottlepops:BAEANQAECgYICgAAAA==.',
Br='Brandanawitz:BAEANQADCgQIAwABNQAECgQIBQABAAAAAA==.Breezyxd:BAEANQAECgcIBwAAAA==.',
Bu='Bungiegrips:BAEANQAECgIIAgAAAA==.Burstinsider:BAEANQAECgcIDAAAAA==.Butterballed:BAEANQAECgYICAABNQAECgcICwABAAAAAA==.Butterloc:BAEANQAECgUIBwABNQAECgcICwABAAAAAA==.',
['Bá']='Bádderdragon:BAEANQAECgUIBwAAAA==.',
['Bô']='Bônëbrëàkèr:BAEANQADCgYICgABNQAECgEIAQABAAAAAA==.',
Ca='Calypsix:BAEANQAECgQIBQAAAA==.Caräntyr:BAEANQAECgQIBAAAAA==.',
Ce='Celanlor:BAEANQADCgYIBgABNQAECggIDQABAAAAAA==.',
Ch='Chainsnight:BAEANQADCggIEAAAAA==.Cherle:BAEANQAECgcIBwAAAA==.Chipotlea:BAEANQAECgUIBQAAAA==.Chubbwing:BAEANQADCgEIAQABNQAECgcICwABAAAAAA==.',
Co='Corpulence:BAEANQAECgcICwAAAA==.',
Cr='Crocop:BAEANQAECgEIAQAAAA==.Cryomuffin:BAEANQAECgIIAgAAAA==.',
Cy='Cynderryke:BAEANQAECgYICgAAAA==.',
Da='Danowarr:BAEANQAECgIIAgAAAA==.Darkknive:BAEANQADCgYICwAAAA==.',
De='Deadjak:BAEANQADCgYIBgABNQAECgMIAwABAAAAAA==.Defarus:BAEANQAFFAIIAgAAAA==.Delusionol:BAEANQAECgcIDgAAAA==.Destoresto:BAEANQADCggIEAABNQAECggIDgABAAAAAA==.Destoshot:BAEANQAECggIDgAAAA==.',
Di='Diamondclaw:BAEANQADCggICQAAAA==.',
Dr='Draggionn:BAEANQAECgMIAwAAAA==.Drik:BAEANQADCgcIDAAAAA==.',
Dt='Dtdpreacher:BAEANQADCggIDgAAAA==.',
Du='Dudly:BAEANQAECgQIBAABNQAECggIDwABAAAAAA==.',
['Dâ']='Dâenys:BAEANQAECgUICAAAAA==.',
Ec='Eclip:BAEANQADCgYICAAAAA==.',
Ed='Ediot:BAEANQAECggIDQAAAA==.Edwardehlrik:BAEANQAECgIIAwABNQAECggIDgABAAAAAA==.',
Eo='Eolianna:BAEANQAECgQICAAAAA==.',
Er='Eritiya:BAEANQAECgYICwAAAA==.',
Ev='Evynne:BAEANQADCggIBwAAAA==.',
Ex='Exeuro:BAEANQABCgQIBAAAAA==.Exezen:BAEANQADCggIDAABNQAECgQICAABAAAAAA==.',
Fi='Fieslock:BAEANQAECgcIDQAAAA==.Fiessham:BAEANQADCggIDgABNQAECgcIDQABAAAAAA==.Finäljüry:BAEBNQAECoEMAAIEAAcJ3Bs8AwBFAgeODQAAAgBdAHUNAAACAFQAfw0AAAIAVgCpDQAAAQAEAFwNAAABAEUAXQ0AAAIASgAzDQAAAgBVAAQABwncGzwDAEUCB44NAAACAF0AdQ0AAAIAVAB/DQAAAgBWAKkNAAABAAQAXA0AAAEARQBdDQAAAgBKADMNAAACAFUAAAA=.',
Fo='Foxiez:BAEANQADCgYIDAAAAA==.',
Fr='Fridayo:BAEANQADCgYIBgABNQAECggIDgABAAAAAA==.Fridayoclock:BAEANQADCggICAABNQAECggIDgABAAAAAA==.Fridayoglock:BAEANQAECggIDgAAAA==.Fridayojock:BAEANQAECgIIAgABNQAECggIDgABAAAAAA==.Frohmark:BAEANQAECgQIBQAAAA==.Frozenwing:BAEANQADCggIDwAAAA==.',
['Fê']='Fêrôz:BAEANQADCgcICwAAAA==.',
Ga='Gabbi:BAEANQAECgEIAQABNQAECgQIBAABAAAAAA==.Gabriellá:BAEANQAECgEIAQABNQAECgQIBAABAAAAAA==.Galeaim:BAEANQAECgQIBAAAAA==.Garahn:BAEANQADCgcIDAAAAA==.',
Ge='Genericdrud:BAEANQAECggICwAAAA==.Genericwar:BAEANQADCgcIBwABNQAECggICwABAAAAAA==.Gerosdrk:BAEANQAECgcICgAAAA==.Gesen:BAEANQAECgcIDAAAAA==.',
Gi='Gillihanh:BAEANQADCgYIBgABNQAECggIDwABAAAAAA==.Gillihanwl:BAEANQAECggIDwAAAA==.Gilo:BAEANQAECgYIBwAAAA==.Gingybear:BAEANQADCgYIBgAAAA==.',
Gl='Gloomrift:BAEANQADCgUIBQABNQAECgEIAQABAAAAAA==.Gloomwick:BAEANQAECgEIAQAAAA==.',
Go='Goonrat:BAEANQADCgMIAwABNQAECgMIAwABAAAAAA==.Gorelguul:BAEANQADCgUIBQABNQADCgUIBQABAAAAAA==.',
Gr='Greenbeansgo:BAEANQAECgMIAwAAAA==.Gregmâge:BAEANQAECgcIDQAAAA==.Grisdele:BAEANQADCgUIBwABNQADCgYIBQABAAAAAA==.',
Gu='Guildmaster:BAEANQAFFAMIAwAAAA==.',
Ha='Hastedtome:BAEANQADCgUIBwAAAA==.Hazmina:BAEANQADCgQICAAAAA==.',
He='Heartshine:BAEANQAECgEIAQAAAA==.Hekid:BAEANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Hu='Hughjanius:BAEANQAECgQIBgAAAA==.Hugron:BAEANQADCgQIBAAAAA==.Humf:BAEANQAECgIIAgAAAA==.Huuky:BAEANQAECgcIDQAAAA==.',
['Hë']='Hëxster:BAEANQAECgUICAAAAA==.',
Ic='Icemonkey:BAEANQAECgUIBQABNQAECgUIBQABAAAAAA==.',
Im='Imhopeless:BAEANQAFFAIIAgAAAA==.Immortalíty:BAEANQAECgQIBAAAAA==.',
Is='Ishanna:BAEANQADCggICQABNQAFFAUIBgAFAHYYAA==.',
Je='Jerstadh:BAEANQAECgQIBQAAAA==.',
Ji='Jinarcana:BAEANQAECgYICAAAAA==.Jirste:BAEANQAECgIIAgABNQAECgQIBQABAAAAAA==.',
Jj='Jjuussttiinn:BAEANQAECgEIAQABNQABCgEIAQABAAAAAA==.',
Ka='Kahluaz:BAEANQADCgYICgABNQAECgcIBwABAAAAAA==.Kalondk:BAEANQADCggIDgAAAA==.Kazereth:BAEANQAECggIDwAAAA==.',
Ki='Killadeathjr:BAEANQADCgIIAQABNQADCgUIBQABAAAAAA==.Kiví:BAEANQAECggIDAAAAA==.',
Ky='Kylealtlock:BAEANQAECgIIAgABNQAFFAIIAgABAAAAAA==.Kyleblinks:BAEANQAECgYIDAABNQAFFAIIAgABAAAAAA==.Kylewl:BAEANQAFFAIIAgAAAA==.Kyntarlus:BAEANQABCgQICAABNQADCgUIBQABAAAAAA==.Kysarra:BAEANQAECgQIBAABNQAFFAIIAgABAAAAAA==.Kyssandra:BAEANQAFFAIIAgAAAA==.',
Le='Levence:BAEANQADCggICAAAAA==.',
Li='Libx:BAEANQAFFAEIAQABNQAECgYIDAABAAAAAA==.Libzvoker:BAEANQAECgMIAwAAAA==.Lilyythe:BAEANQADCgUIBQABNQAECgEIAQABAAAAAA==.Listhuh:BAEANQADCgYIBgABNQAFFAEIAQABAAAAAA==.',
Lu='Luneli:BAEANQADCggIEAABNQAECggIDAABAAAAAA==.Lunilocks:BAEANQAECgQIBAABNQAECggIDAABAAAAAA==.',
['Lø']='Løäding:BAEANQAECgQICAAAAA==.',
Ma='Mazn:BAEANQADCgUIBwAAAA==.',
Me='Me:BAEANQAECgMIAwABNQAFFAMIAwABAAAAAA==.Mecönium:BAEANQAECgEIAQAAAA==.Menaray:BAEANQAECgMIAwABNQAECgYICAABAAAAAA==.Meppi:BAEANQAECgcIDAAAAA==.',
Mi='Mikethepure:BAEANQAECgQICQAAAA==.',
Mo='Moff:BAEANQABCgQIBgAAAA==.Momodh:BAEANQAECgYIBwABNQAECggIBgABAAAAAA==.Momussie:BAEANQAECggIBgAAAA==.Monsternos:BAEANQAECgcIAgAAAA==.Moonblase:BAEANQAECgUIBQAAAA==.Morchies:BAEANQADCgUIBgABNQAECgUIBQABAAAAAA==.Mossberg:BAEANQAECgcIDAAAAA==.Mousehopium:BAEANQADCgcIBgAAAA==.',
My='Mynïel:BAEANQADCgUIBQAAAA==.',
['Mú']='Múrdërhôbô:BAEANQAECgEIAQAAAA==.',
Na='Nahuall:BAEANQADCgYICgAAAA==.Natralana:BAEANQADCgUIBQAAAA==.',
Ne='Necromalt:BAEANQADCgYIBgABNQAECgQIBQABAAAAAA==.Nelfling:BAEANQAECgQIBQAAAA==.',
No='Norxxonx:BAEANQADCgQIBwABNQAECgQIBgABAAAAAA==.Notrogtuah:BAEANQAECgIIAgAAAA==.Noxxiq:BAEANQADCgYIBgAAAA==.',
Ny='Nynaevy:BAEANQAECgMIAwABNQAECgQICAABAAAAAA==.',
Oh='Ohmspacedk:BAEANQADCggICAAAAA==.',
Om='Omnidor:BAEANQAECgUIBgAAAA==.',
Or='Orphanmakr:BAEANQADCgUIBQAAAA==.',
Pa='Painkus:BAEANQADCgMIBgABNQAECgMIAwABAAAAAA==.Pawtection:BAEANQADCgcIBwABNQAECgQIBgABAAAAAA==.',
Pe='Pengadin:BAEANQAECgcIDQAAAA==.Petrsykora:BAEANQADCgcICAABNQAECgcIDAABAAAAAA==.',
Po='Pocketzzmeat:BAEANQADCgQIBAABNQAECgcIDQABAAAAAA==.Pocketzzmonk:BAEANQAECgQIBAABNQAECgcIDQABAAAAAA==.Pocketzzsham:BAEANQAECgQIBAABNQAECgcIDQABAAAAAA==.Pontíf:BAEANQADCgcIDQAAAA==.',
Pr='Praxivoker:BAEANQADCgYIDAAAAA==.Prinkkus:BAEANQAECgMIAwAAAA==.',
Qu='Quietplease:BAEANQADCgcIBwAAAA==.',
Re='Reddy:BAEANQAFFAMIBAAAAA==.Redryder:BAEANQAECgEIAQABNQABCgEIAQABAAAAAA==.Rehobooam:BAEANQADCggIDgABNQAECgMIBAABAAAAAA==.Relreaux:BAEANQAECggICQAAAA==.Revthnksimai:BAEANQAECgEIAQABNQAECgQIBgABAAAAAA==.',
Ro='Roidington:BAEANQAECgQIBAAAAA==.Rolyon:BAEANQAFFAIIAgAAAA==.Rortimag:BAEANQAECgEIAQAAAA==.Rortimis:BAEANQADCgEIAQABNQAECgEIAQABAAAAAA==.Rowlond:BAEANQADCgUICAAAAA==.',
Ru='Rubmyhots:BAEANQAECggICQAAAA==.',
Ry='Ryecoke:BAEANQADCggIEAAAAA==.Rykala:BAEANQAECgUIBQABNQAECgYICgABAAAAAA==.Rykemage:BAEANQAECgEIAQABNQAECgYICgABAAAAAA==.',
Sa='Sahjurn:BAEANQADCgIIAgABNQAECgUIBQABAAAAAA==.Savory:BAEANQAECgEIAQAAAA==.',
Sc='Scooty:BAEANQAECgQIBQABNQAECgcICwABAAAAAA==.',
Se='Senndh:BAEANQAECgcIDQAAAA==.Settek:BAEANQAECgcICwAAAA==.',
Sh='Shadizar:BAEANQAECgYICgAAAA==.Shambith:BAEANQAECgQIBgAAAA==.Shikiryougi:BAEANQAECgQIBAAAAA==.Shingrip:BAEANQADCgYICwAAAA==.Shyviolet:BAEANQADCgcIBwAAAA==.',
Si='Sioken:BAEANQAECgQIBgAAAA==.',
Sm='Smouke:BAEANQAECgIIAgABNQAECggIDwABAAAAAA==.',
So='Sokosage:BAEANQADCgIIAgABNQAECgUIBQABAAAAAA==.Somegal:BAEANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Sp='Splather:BAEANQADCggICAAAAA==.',
Sq='Squirtamus:BAEANQAECgQICAABNQAECggIDgABAAAAAA==.Squirtamussy:BAEANQAECggIDgAAAA==.Squrlshamz:BAEANQADCggIFAAAAA==.Sqz:BAEANQAECgIIAgAAAA==.',
St='Staskylock:BAEANQAECgMIAwABNQAECgcIDQABAAAAAA==.Staskym:BAEANQAECgcIDQAAAA==.Stebhunter:BAEANQADCgUIBQABNQAECggIDQABAAAAAA==.Stonetides:BAEANQAECgQIBAAAAA==.Stormdoc:BAEANQADCgMIAwABNQADCgYIDAABAAAAAA==.Strongpal:BAEANQAECgYICQABNQAECgcIDQABAAAAAA==.',
Su='Sudac:BAEANQADCgUIBQABNQADCggIDgABAAAAAA==.',
Sy='Sykora:BAEANQAECgcIDAAAAA==.Sylrisia:BAEANQAECgcIDQAAAA==.',
['Sö']='Sömegüy:BAEANQAECgQIBAABNQAECgQIBAABAAAAAA==.',
Ta='Taliendra:BAEANQADCggIDgAAAA==.',
Te='Tegualbrew:BAEANQADCgYIBgABNQAECgQIBQABAAAAAA==.Tegualdruid:BAEANQAECgQIBQAAAA==.Temuula:BAEANQADCggICAABNQAECggIBgABAAAAAA==.Tequíla:BAEANQADCgYICQAAAA==.',
Th='Thefonzo:BAEANQAECgUICgAAAA==.Theldrassen:BAEANQAECgIIAgAAAA==.Thrazad:BAEANQADCgEIAQABNQAECgQIBQABAAAAAA==.',
To='Torjack:BAEANQAECgIIBAAAAA==.Toströng:BAEANQAECgcIDQAAAA==.',
Tr='Triillaiin:BAEANQADCgYIBgAAAA==.Trovyria:BAEANQAECgYICQAAAA==.',
Ty='Tyromezz:BAEANQAFFAEIAQAAAA==.',
['Tâ']='Tâhra:BAEANQADCgYIBQAAAA==.',
['Tý']='Týýr:BAEANQAECgEIAQAAAA==.',
Va='Valkdk:BAEANQADCgcIBwAAAA==.Valkhunter:BAEANQAECgEIAQABNQADCgcIBwABAAAAAA==.Valksham:BAEANQAECgQIBQABNQADCgcIBwABAAAAAA==.Vamprinkus:BAEANQAFFAIIAgABNQAECgMIAwABAAAAAA==.Vayeatee:BAEANQAECggIDgAAAA==.',
Ve='Vehqq:BAEANQAECgMIAwABNQAFFAEIAQABAAAAAA==.Vehqqdk:BAEANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Vehqqw:BAEANQAFFAEIAQAAAA==.Vengmaxxing:BAEANQADCggIDAAAAA==.Verekoo:BAEANQAECgYICAAAAA==.',
Vi='Viveus:BAEANQAECgQIBQAAAA==.Viveush:BAEANQADCgQIBAABNQAECgQIBQABAAAAAA==.',
Vo='Vonsnuffles:BAEANQAECggIDAAAAA==.',
Wa='Wagovinci:BAEANQAECgQIBQAAAA==.Waterrblastr:BAEANQADCgYIBgABNQABCgEIAQABAAAAAA==.',
We='Wetbox:BAEANQAECgcIDQAAAA==.',
Wi='Wildeclaw:BAEANQADCgYIBgAAAA==.Windowblight:BAEANQAECgEIAQAAAA==.Windwärd:BAEANQAECgQIBgABNQADCgYICQABAAAAAA==.',
Wo='Wokowage:BAEANQAECgUIBQAAAA==.',
['Wé']='Wébs:BAEANQADCgYICgAAAA==.',
Xe='Xernwar:BAEANQABCgIIAgABNQAECggIEAABAAAAAA==.',
Yv='Yvairel:BAEANQAECgcIDAABNQAECgcICwABAAAAAA==.',
Za='Zaffia:BAEANQAECgcICwAAAA==.Zatheor:BAEANQAECgUIBQABNQAECgcICwABAAAAAA==.',
Ze='Zedj:BAEANQAECgIIAgAAAA==.',
Zi='Zilthorn:BAEANQAECgEIAQABNQABCgEIAQABAAAAAA==.Zimbzy:BAEANQAECgYIBwAAAA==.Zirleficent:BAEANQADCgYICwAAAA==.',
['Åd']='Ådaptive:BAEANQAECgEIAQAAAA==.',
['Ír']='Íranem:BAEANQAECgYICAAAAA==.',
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
