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

local lookup = {'Unknown-Unknown','Mage-Arcane','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Rogue-Subtlety','Druid-Restoration','Warrior-Arms','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Holy','Shaman-Restoration','Mage-Frost','Mage-Fire','Priest-Shadow','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Priest-Holy','Monk-Windwalker','DemonHunter-Havoc','DemonHunter-Vengeance','DeathKnight-Blood',}
local provider = {region='US',realm='Saurfang',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abbeyroad:BAAANQAECgEIAQAAAA==.',
Ad='Adnauseam:BAAANQAECgYIDgAAAA==.',
Ae='Aedaenia:BAAANQADCggIDgAAAA==.Aelyndara:BAAANQADCgQICAAAAA==.',
Ag='Agave:BAAANQADCggIDgAAAA==.Aglerion:BAAANQADCgYIBgAAAA==.',
Ah='Ahavah:BAAANQABCgYIBgAAAA==.Ahlya:BAAANQAECgUIDQAAAA==.',
Ai='Aime:BAAANQAECggIBgAAAA==.Aimei:BAAANQAECgIIAgAAAA==.Aiphaton:BAAANQAECgEIAQAAAA==.',
Aj='Ajchmiel:BAAANQADCgYIDgAAAA==.',
Ak='Akanea:BAAANQADCgQIBgAAAA==.Ake:BAAANQAECgcIDAAAAA==.Akàmè:BAAANQAECgQIBgAAAA==.',
Al='Aldavyr:BAAANQAECgcIDQAAAA==.Aldrick:BAAANQADCgUIBQAAAA==.Alienas:BAAANQAECgEIAQAAAA==.Alighieri:BAAANQAECgEIAQAAAA==.Alinassa:BAAANQAECgQIBgAAAA==.Alinnarra:BAAANQADCggICAABNQAECgQIBgABAAAAAA==.Allacore:BAAANQADCgUICAAAAA==.Alponyoman:BAAANQAECgcIBwAAAA==.',
Am='Amaizen:BAAANQADCgUICAAAAA==.Ameilioli:BAAANQABCgIIBAAAAA==.Amorthian:BAAANQADCggICAAAAA==.',
An='Andrak:BAAANQADCgUIBwAAAA==.Angelock:BAAANQABCgEIAQAAAA==.Angertotem:BAAANQADCgcICQABNQAECgMIBQABAAAAAA==.Angkor:BAAANQAECgIIAgAAAA==.Angrboda:BAAANQADCggICQABNQAECgEIAQABAAAAAA==.Angusmac:BAAANQADCggIDwAAAA==.Anhailah:BAAANQAECgUIDQAAAA==.Animos:BAAANQAECgQIBAAAAA==.Annarah:BAAANQAECgQIBgAAAA==.Anselo:BAAANQADCgUIBQAAAA==.Anthropocene:BAAANQAECgEIAQAAAA==.',
Ap='Appowulf:BAAANQAECgcIDQAAAA==.',
Aq='Aquamangue:BAAANQAECgYIBwAAAA==.',
Ar='Aragornne:BAAANQAECgQIBAAAAA==.Arcanemage:BAAANQADCggIEAAAAA==.Archeuz:BAAANQADCgcIDwAAAA==.Arkdan:BAAANQAECgEIAQAAAA==.Arnoon:BAAANQAECgYICAAAAA==.Arogance:BAAANQAECgYICgAAAA==.',
As='Ashreever:BAAANQADCggIDQAAAA==.Asmodan:BAAANQAECgEIAQAAAA==.',
At='Attonrand:BAAANQADCggIEAAAAA==.',
Au='Augment:BAAANQABCgIIAwAAAA==.Ausarrow:BAAANQAECgMIAwAAAA==.Ausdruid:BAAANQAECgEIAQAAAA==.',
Av='Avianori:BAAANQADCgYIBgAAAA==.Avie:BAACNQAFFIEFAAICAAIJPx/SCADGAAACAAIJPx/SCADGAAA1AAQKgRgAAgIACQkpJNIFAJkDAAIACQkpJNIFAJkDAAAA.',
Ax='Axalotel:BAAANQADCgIIAgAAAA==.Axelfoley:BAAANQADCgcICQAAAA==.',
Az='Azraezel:BAAANQAECgEIAwAAAQ==.Azyrael:BAAANQADCgUIBQABNQAECgEIAwABAAAAAQ==.Azzinot:BAAANQADCgUICAAAAA==.',
['Aã']='Aãri:BAAANQADCggICwABNQAECgQIBgABAAAAAA==.',
Ba='Babàyaga:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Barthom:BAABNQAECoEaAAIDAAcJ4g7WOgCeAQADAAcJ4g7WOgCeAQAAAA==.Baràk:BAABNQAECoEXAAMDAAcJXw7eOgCdAQADAAYJdQ/eOgCdAQAEAAEJ3Qd4OABDAAAAAA==.',
Be='Bearzlock:BAAANQAECgUICgAAAA==.Bearzmage:BAAANQAECgMIAwABNQAECgUICgABAAAAAA==.Beatrix:BAAANQADCggIEAAAAA==.Bedebah:BAAANQAECgQIBgAAAA==.Beebeecee:BAAANQAECggICAAAAA==.Beerington:BAAANQAECgMIAwAAAA==.Behemoth:BAAANQAECgEIAQAAAA==.Belirisa:BAAANQADCgEIAQAAAA==.Berknerkem:BAAANQADCggIEwAAAA==.Bewmz:BAAANQAECgIIAgAAAA==.',
Bi='Bigboomz:BAAANQADCgYIBgAAAA==.Bigoltrollop:BAAANQAECgEIAQAAAA==.Biscuitcapes:BAAANQADCgYIDgAAAA==.Bison:BAAANQADCgMIAwAAAA==.',
Bl='Blinkinpark:BAAANQADCgYIDAAAAA==.Bllissterine:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.Bllissticks:BAAANQAECgMIAwAAAA==.Bllisstrix:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.Blxckbeef:BAABNQAECoEXAAIFAAcJrQn3QACFAQAFAAcJrQn3QACFAQAAAA==.',
Bo='Bombsquad:BAAANQAECgIIAgABNQAECggIEwABAAAAAA==.Boomie:BAAANQADCgYIBgAAAA==.Bornewithit:BAABNQAECoEXAAIGAAcJoxcIDABFAgAGAAcJoxcIDABFAgAAAA==.Borttheblade:BAAANQAECgYICwABNQAECgcIBwABAAAAAA==.',
Br='Brandyshot:BAAANQAECgIIAgAAAA==.Brewtalîty:BAAANQAECgIIAgAAAA==.Briar:BAAANQADCggIDgAAAA==.Brush:BAAANQAECgYICgAAAA==.Bruvski:BAAANQAECgMIAgAAAA==.',
Bu='Bunniex:BAAANQADCgYIBgAAAA==.',
Bw='Bwthhybl:BAAANQAECgIIAgAAAA==.',
By='Bytes:BAAANQAECgUIBgAAAA==.',
['Bü']='Bünny:BAAANQAECgMIBgAAAA==.',
Ca='Cairnless:BAAANQAECgYICAAAAA==.Cakesrlife:BAAANQAECgUIBwAAAA==.Camilletrois:BAAANQABCgIIAwAAAA==.Captcinder:BAAANQADCgMIAwAAAA==.Carabine:BAAANQAECgQIBAAAAA==.Caselorc:BAAANQADCgUIDQAAAA==.Cata:BAAANQAECgMIAwAAAA==.Catscythe:BAAANQADCggIEgAAAA==.Cauthon:BAAANQAECgEIAQAAAA==.Cavemanwar:BAAANQAECgcIBwAAAA==.',
Ce='Celtic:BAABNQAFFIEHAAIHAAUJ+hR2AADBAQAHAAUJ+hR2AADBAQAAAA==.Ceredan:BAAANQADCgcIDAAAAA==.',
Ch='Challisa:BAAANQADCgEIAQAAAA==.Chaoskane:BAAANQADCgcIEwAAAA==.Charnaby:BAAANQAECgUIDgAAAA==.Cheeksmasher:BAAANQAECgEIAQAAAA==.Cheesesteaks:BAAANQADCgcIDwAAAA==.Chellê:BAAANQAECgEIAQAAAA==.Chicknburgah:BAABNQAECoEYAAMIAAkJfxvrFADgAgAIAAkJfxvrFADgAgAJAAEJkRjlEgBLAAAAAA==.Chillyia:BAAANQADCgcIBwABNQAECgYICgABAAAAAA==.Chocorondo:BAAANQAECgYICgAAAA==.Chokystafish:BAAANQADCgUIBQAAAA==.Chonkmagic:BAAANQAECgEIAQAAAA==.Chowhai:BAAANQADCgMIAwAAAA==.',
Ci='Ciaraa:BAAANQADCgEIAQAAAA==.Circus:BAAANQAECgQIBgAAAA==.',
Cl='Clawtism:BAAANQADCggICAAAAA==.',
Co='Cobólt:BAAANQADCgUICgAAAA==.Cocola:BAAANQADCgUIBQAAAA==.Colanius:BAAANQADCgQIBAABNQAECgMIBgABAAAAAA==.Corte:BAABNQAECoEaAAIKAAcJDBFKEACfAQAKAAcJDBFKEACfAQAAAA==.Coverghoul:BAABNQAECoEbAAILAAgJRBI8HgAKAgALAAgJRBI8HgAKAgABNQAECggJGwALAEQSAA==.',
Cr='Crazedorc:BAAANQAECgUIBwAAAA==.Creamymoot:BAAANQADCgcIDAAAAA==.Crispyjeww:BAAANQAECggIBgAAAA==.Croescrane:BAAANQAECgQICAAAAA==.Crooked:BAAANQAECgIIAgAAAA==.Crossblessër:BAAANQAECgMIAwABNQABCgMIAwABAAAAAA==.',
Cy='Cynthus:BAAANQAECgcIEQAAAA==.',
['Cé']='Cérberus:BAAANQAECgEIAQAAAA==.',
Da='Damador:BAAANQAECgYICgAAAA==.Damisia:BAAANQAECgIIAgAAAA==.Damuss:BAAANQAECgEIAQABNQAECgcICQABAAAAAA==.Danirumi:BAAANQAECgIIAwAAAA==.Danithir:BAAANQADCgQIBQAAAA==.Danndk:BAAANQAECgYICwAAAA==.Danndruid:BAAANQADCgEIAQAAAA==.Dannsham:BAAANQADCgIIAwAAAA==.Darkiller:BAAANQADCgEIAgAAAA==.Darksox:BAAANQADCggIFQAAAA==.Daylisha:BAAANQAECgIIAwAAAA==.Dayn:BAAANQAECgEIAQAAAA==.Dazzles:BAAANQAECgQIDAAAAA==.',
De='Deablohuntsu:BAAANQADCggICAAAAA==.Deabloknight:BAAANQAECgQIBQAAAA==.Deablosrage:BAAANQAECgIIBQAAAA==.Deadotz:BAAANQABCgYICAAAAA==.Deathraider:BAAANQAECgMIBgAAAA==.Ded:BAAANQAECgcIDQAAAA==.Demonboog:BAAANQADCgUIAQAAAA==.Demongasher:BAAANQADCgIIAwAAAA==.Demonmus:BAAANQADCgcIDQAAAA==.Demonpandaz:BAAANQAECgQIBQAAAA==.Dessa:BAAANQADCggIEwABNQAECgQIBQABAAAAAA==.Dessane:BAAANQAECgQIBQAAAA==.Dexdragoon:BAAANQAECgUICgAAAA==.',
Di='Dijonmustard:BAAANQADCggIFAAAAA==.Diora:BAAANQAECgUICQAAAA==.',
Dk='Dkdence:BAAANQAECgcIDAAAAA==.',
Do='Dodo:BAAANQAECgEIAQAAAA==.Donfandangle:BAAANQADCgYIDgAAAA==.Donkeykongg:BAAANQAECgcIEgAAAA==.Doofyspally:BAAANQADCgYIBgAAAA==.Doomadin:BAABNQAECoEXAAIMAAcJ8h7pEQCOAgAMAAcJ8h7pEQCOAgAAAA==.Dora:BAAANQAECgQIBAAAAA==.Dovarkin:BAAANQAECgcICgAAAA==.',
Dr='Drabsysham:BAABNQAECoEZAAINAAkJJR1rDQC3AgANAAkJJR1rDQC3AgAAAA==.Dracarsynimz:BAEANQAECgYIFQAAAQ==.Draczr:BAAANQAECgQIBwAAAA==.Dragonbunny:BAAANQADCgMIAwAAAA==.Dragrit:BAAANQADCgYIBgABNQAECgkJFwAOAGYhAA==.Dragrito:BAAANQADCggICAABNQAECgkJFwAOAGYhAA==.Dragritt:BAAANQAECgMIBAABNQAECgkJFwAOAGYhAA==.Dragritto:BAABNQAECoEXAAQOAAkJZiHpAAD5AgAOAAcJ5CTpAAD5AgACAAcJrRw8RgAeAgAPAAEJKBZ3BABOAAAAAA==.Dragsham:BAAANQADCgQIBAABNQAECgkJFwAOAGYhAA==.Dragönshade:BAABNQAECoEaAAIQAAcJsg99EwDSAQAQAAcJsg99EwDSAQAAAA==.Drakage:BAAANQADCgMIAwAAAA==.Drakana:BAAANQAECgMIAwAAAA==.Draykora:BAAANQAECgYICQAAAA==.Drazzig:BAAANQADCgMIAwAAAA==.Dreambreaker:BAAANQAECgEIAQAAAA==.Drekavoc:BAAANQADCgIIAgABNQADCgMIBgABAAAAAA==.Drewzus:BAAANQAECgEIAQAAAA==.Drexanoth:BAAANQADCgQIBAAAAA==.Drusindra:BAAANQADCgYIDgAAAA==.',
Du='Dudeman:BAAANQAECgIIAgAAAA==.Durabull:BAAANQADCgEIAQAAAA==.',
Dw='Dwarfz:BAAANQAECgQICAAAAA==.',
Ea='Earthbreaker:BAAANQAECgEIAgAAAA==.',
Ed='Edavv:BAAANQADCgQICAABNQAECgUICgABAAAAAA==.Edmo:BAAANQAECgYICAAAAA==.Edrandil:BAAANQAECgUICgAAAA==.',
Ee='Eevula:BAAANQADCgEIAQAAAA==.',
Ei='Eiluaq:BAAANQADCggIGAAAAA==.Eirianna:BAAANQADCgYIDgAAAA==.',
El='Elcrabbette:BAAANQAECgMIAwAAAA==.Elegant:BAAANQAECgEIAQAAAA==.Elemelôn:BAAANQADCggIHQABNQAECgcIGgAQALIPAA==.Elundara:BAAANQAECgcIDAAAAA==.',
Eq='Eq:BAAANQADCggIFAAAAA==.',
Es='Estardra:BAAANQAECgUIBQAAAA==.',
Ev='Evelice:BAAANQAECgMIBgAAAA==.Evilnattie:BAAANQAECgUICQAAAA==.Evokiia:BAAANQADCgUIBQABNQAECgcIDAABAAAAAA==.',
Ex='Exajoule:BAAANQADCgUIBQABNQAECgcIGgADAOIOAA==.Exiledpally:BAAANQADCgQIBAAAAA==.',
Fa='Faeryall:BAAANQAECgQICgAAAA==.Fahkmoi:BAAANQADCgYIBgAAAA==.Fakeyoda:BAAANQAECgQIBQAAAA==.Falua:BAAANQAECgQIBAAAAA==.Famiine:BAAANQADCgUIBQAAAA==.Faranight:BAAANQAECgEIAQAAAA==.Faright:BAAANQAECgIIAgAAAA==.Fatherspark:BAAANQADCggICQAAAA==.Fatherursid:BAAANQADCgIIBAABNQAECgUIDgABAAAAAA==.',
Fe='Feara:BAAANQAECgQIBQAAAA==.Fefeasa:BAAANQADCgQIBQAAAA==.Feistyfist:BAAANQAECgEIAQAAAA==.Fekzak:BAAANQADCgIIAgAAAA==.Felmeup:BAAANQADCgEIAQAAAA==.Fenglei:BAAANQADCgcIDQABNQAECgkJGAACAO8dAA==.Fengliu:BAABNQAECoEYAAMCAAkJ7x1wHQDmAgACAAkJ7x1wHQDmAgAOAAEJjBvnGQBDAAAAAA==.Fengmin:BAAANQADCggIEAABNQAECgkJGAACAO8dAA==.Fennik:BAAANQADCgIIAgAAAA==.Fenriz:BAAANQAECgIIAgAAAA==.',
Fi='Fieryroota:BAABNQAECoEVAAICAAcJeyDUKgCbAgACAAcJeyDUKgCbAgAAAA==.Findewin:BAAANQAECgIIAgAAAA==.Fiyerite:BAAANQAECgcIDAAAAA==.Fizzypal:BAAANQAECgQIBAAAAA==.',
Fl='Flameeater:BAAANQAECgQIBQAAAA==.Flynnyzyzz:BAABNQAECoEXAAIRAAcJuCVNCgANAwARAAcJuCVNCgANAwAAAA==.',
Fo='Folk:BAAANQABCgIIAgAAAA==.Fotcjermaine:BAAANQABCgIIAgAAAA==.',
Fr='Franked:BAAANQADCgUIBQAAAA==.Frogster:BAAANQADCgMIAwAAAA==.Frogwash:BAAANQADCgMIAwABNQAECgUIBgABAAAAAA==.',
Fu='Furrylock:BAAANQAECgQIDAAAAA==.Fuzzlicia:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Fuzzyballs:BAAANQAECgEIAQAAAA==.',
Fy='Fyaha:BAAANQADCggICAAAAA==.Fylson:BAAANQADCggICAAAAA==.',
['Fú']='Fúzzlë:BAAANQAECgEIAQAAAA==.',
Ga='Gadgetgeek:BAAANQADCgMIAwAAAA==.Galeidan:BAAANQAECgEIAQAAAA==.Gameoftroll:BAAANQAECgcIDAAAAA==.Gamumush:BAAANQAECgcIDAAAAA==.Gamush:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Gargola:BAAANQADCgYIBgAAAA==.Garntek:BAAANQAECgEIAQAAAA==.Garstomp:BAAANQAECgEIAQAAAA==.Garókk:BAAANQADCgYIDQAAAA==.',
Ge='Geauxphreigh:BAAANQAECgUIBgAAAA==.',
Gh='Ghostbom:BAAANQADCgcICQAAAA==.',
Gi='Giggels:BAAANQAECgQICAAAAA==.Gilletté:BAAANQAECgEIAQAAAA==.',
Gl='Glaiviture:BAAANQAECgEIAQAAAA==.',
Go='Goodgravy:BAAANQADCgMIAwAAAA==.Gorenrisao:BAAANQAECgEIAgABNQAECgMIBgABAAAAAA==.Gotsalt:BAAANQAECgcIDAAAAA==.Gotsdots:BAABNQAECoEYAAMSAAkJBxk3EgBwAgASAAgJEhc3EgBwAgATAAcJQBXXCwABAgAAAA==.',
Gr='Greendoor:BAAANQAECgQIBgAAAA==.Gren:BAAANQADCgUICAAAAA==.Griimmjjow:BAAANQADCgYIBgAAAA==.Growvert:BAAANQAFFAMIAwAAAA==.',
['Gé']='Gémini:BAAANQADCgIIAgAAAA==.',
['Gø']='Gødslapp:BAAANQAECgQIBQAAAA==.',
Ha='Hahwei:BAAANQADCgYICwAAAA==.Hailej:BAAANQADCgcICAABNQAECgcIDAABAAAAAA==.Hakine:BAAANQADCggICwAAAA==.Halianubran:BAAANQAECgEIAQABNQAECgMIBgABAAAAAA==.Halliday:BAAANQAECgYIDAAAAA==.Harraktas:BAAANQAECgQIBgAAAA==.Harrowhark:BAAANQAECgEIAQAAAA==.Harvestmoon:BAAANQADCgQIBAAAAA==.Haxxor:BAAANQADCggIEAAAAA==.',
He='Healiia:BAAANQAECgcIDAAAAA==.Hellsîng:BAAANQAECggIDAABNQAECgkJGAASAAcZAA==.Hellà:BAAANQADCgcIDwAAAA==.Hendo:BAAANQAECgEIAQAAAA==.Hepatitan:BAAANQADCgIIAgAAAA==.Hester:BAAANQADCgQIBgAAAA==.Hexecuted:BAAANQADCggIFAAAAA==.Heyyaits:BAAANQAECgcIEgAAAA==.',
Hi='Hikahi:BAAANQAECgIIAgAAAA==.',
Ho='Holdmyaggro:BAAANQAECgQICgAAAA==.Holdmyballz:BAAANQAECgQIBgAAAA==.Hollyballz:BAAANQADCgYIBgAAAA==.Holyberry:BAAANQAECgUIEAAAAA==.Holè:BAAANQAECgUICQABNQAECgYIBgABAAAAAA==.Hotstreakqt:BAAANQADCgYIDgAAAA==.Hotzug:BAAANQADCgIIAgAAAA==.Houyix:BAAANQAECgMIAwAAAA==.Howdowhodo:BAAANQADCgUIDQAAAA==.',
Hr='Hreeza:BAAANQADCggIFAAAAA==.',
Hu='Humabon:BAAANQADCgUIBgAAAA==.Huntingjohn:BAAANQADCgYIBgAAAA==.Huntssy:BAAANQAECgQIBgAAAA==.Huuag:BAAANQAECgIIAwAAAA==.',
Hy='Hynobear:BAAANQABCgQIBgAAAA==.Hypersleep:BAAANQAECgEIAQAAAA==.',
['Hì']='Hìkàrì:BAAANQADCgMIAwAAAA==.',
['Hö']='Hötnhòrdey:BAAANQAECgIIAwAAAA==.',
['Hø']='Høstile:BAAANQADCgQICAAAAA==.',
Id='Idtrappthat:BAAANQADCgYIBgAAAA==.',
Ii='Ii:BAAANQADCggIDwAAAA==.Iisildur:BAAANQAECgUICgAAAA==.',
Im='Imaginative:BAAANQAECgcIEQAAAA==.Imcooked:BAAANQAECgcIEgAAAA==.Imfiredupp:BAAANQAECggIAQAAAA==.Imladrisse:BAAANQADCggIEwAAAA==.',
In='Inamoonstar:BAAANQADCgUIBQAAAA==.Inkmouse:BAAANQAECgUICAAAAA==.',
Ir='Irispearl:BAAANQADCgQICAAAAA==.Ironfistt:BAAANQAECgcIEgAAAA==.',
Is='Isolde:BAAANQADCgYIDwAAAA==.',
Iv='Ivar:BAAANQAECgYICwAAAA==.',
Ja='Jacksmash:BAAANQADCggIFgAAAA==.Jaganoto:BAAANQADCggICAAAAA==.Jaideep:BAAANQAECgQIBAAAAA==.Jalarin:BAAANQADCgMIBgAAAA==.Jaminmyclam:BAAANQAECgEIAQAAAA==.Jamitydk:BAEANQAECgQIBgAAAA==.Jarnzarn:BAAANQADCggIEAAAAA==.Jarviltinn:BAAANQAECgUICQAAAA==.',
Je='Jelia:BAAANQAECgcIDAAAAA==.Jelyah:BAAANQAECgQIBAABNQAECgcIDAABAAAAAA==.Jerô:BAAANQADCggIEAAAAA==.',
Jf='Jf:BAAANQADCgEIAQAAAA==.',
Jo='Jobbey:BAAANQAECgEIAQAAAA==.Jonkerstien:BAAANQAECgYICgAAAA==.Jorgie:BAAANQADCggIFAABNQAECgUIBQABAAAAAA==.Joyous:BAAANQAECgEIAQAAAA==.',
Ju='Jubearz:BAAANQADCgcIBwAAAA==.Juelz:BAAANQADCgIIAgAAAA==.Jumbosausage:BAAANQAECgIIAwAAAA==.Jungchi:BAAANQADCggIFAAAAA==.Junior:BAAANQAECgcICgAAAA==.',
['Jú']='Júdgemental:BAAANQADCgQIBAAAAA==.',
Ka='Kaeliela:BAAANQADCgcIBwAAAA==.Kahahn:BAAANQABCgIIAwAAAA==.Kakana:BAAANQADCgYIDAAAAA==.Kalantiaw:BAAANQADCgQIBAAAAA==.Kamui:BAAANQAECgYICgAAAA==.Kanamè:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Kandrays:BAAANQADCgIIAgABNQAECgUIEAABAAAAAA==.Kanfer:BAAANQADCggIEAAAAA==.Kariala:BAAANQAECgQIBQAAAA==.Kastager:BAAANQADCgMIAwABNQADCgUIDQABAAAAAA==.Katilaine:BAAANQADCgYIDgAAAA==.Kayadrac:BAAANQAECgYICwAAAA==.Kazimir:BAAANQADCgcIBwAAAA==.',
Ke='Keksiq:BAAANQAECgUIDQAAAA==.Keshae:BAAANQAECgUIDgAAAA==.',
Ki='Kidfork:BAAANQAECgIIBQAAAA==.Killasham:BAAANQAECgIIAgAAAA==.Killika:BAAANQADCgYICwABNQAECgYICgABAAAAAA==.Kinndred:BAAANQAECgUIEAAAAA==.Kintolina:BAAANQADCgIIAgAAAA==.Kiralia:BAABNQAECoEXAAIRAAcJPhDBJwDXAQARAAcJPhDBJwDXAQAAAA==.Kirigolmer:BAAANQADCggIFAAAAA==.',
Kn='Kngleonidas:BAAANQAECgQIBAAAAA==.',
Ko='Kokoy:BAAANQAECgYICwAAAA==.Kouchin:BAAANQADCgIIAgAAAA==.',
Kr='Krackd:BAAANQADCggICQAAAA==.Kraelyk:BAAANQADCgYICgAAAA==.Krazan:BAAANQAECgMIBgAAAA==.Krunkisdead:BAAANQADCgIIAgAAAA==.Krygore:BAAANQAECgIIAgAAAA==.',
Ku='Kunali:BAAANQADCgYIDAAAAA==.Kunehoboy:BAAANQADCgYIBgAAAA==.Kungfufeet:BAAANQADCgUICQAAAA==.Kurtcobang:BAAANQAECgUIBgAAAA==.Kushie:BAAANQAECgIIAwAAAA==.',
['Ká']='Kál:BAAANQAECgIIAwAAAA==.',
['Kø']='Kørndawg:BAAANQADCgYIEgAAAA==.',
La='Lagior:BAEANQAECgMIBgAAAA==.Laikaboss:BAAANQADCgQIBAAAAA==.Lakandula:BAAANQADCgQIBAAAAA==.Lasind:BAAANQADCgYIDgAAAA==.Lawu:BAAANQAECgcIDAAAAA==.Laytonfrost:BAAANQADCgUICgABNQAECgIIAgABAAAAAA==.',
Le='Learrit:BAAANQAECgQIBgAAAA==.Lecorpse:BAAANQADCggIDgAAAA==.Lemmìwìnks:BAAANQADCgYIBgABNQABCgMIAwABAAAAAA==.Lendis:BAAANQADCgIIAgAAAA==.Leviathran:BAAANQAECgEIAQAAAA==.',
Li='Librawitch:BAAANQADCgMIAwAAAA==.Lifaène:BAAANQADCgYIDAAAAA==.Lightarcc:BAAANQAECgEIAQAAAA==.Lightklobe:BAAANQAECggIAQAAAA==.Lihan:BAAANQADCggIFAAAAA==.Lilcarabine:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Lilindrena:BAAANQADCgYIDwAAAA==.Lilmentyb:BAAANQAECgUICgAAAA==.Lilmis:BAAANQAECgIIAgAAAA==.Liorawr:BAAANQADCggIEwAAAA==.Lipids:BAAANQADCgcIEgAAAA==.Lissuin:BAAANQAECgMIBAAAAA==.',
Ll='Llandrei:BAAANQADCgcIEgAAAA==.',
Lo='Locnár:BAAANQAECgMIBQAAAA==.Lollobionda:BAAANQAECgIIAwAAAA==.Loono:BAAANQAECgQIBAAAAA==.Lorathiel:BAAANQADCgUIBQAAAA==.',
Lu='Luffytoe:BAAANQADCgMIAwABNQAECggIEwABAAAAAA==.Lulingqï:BAAANQADCggIDgAAAA==.Lululapoon:BAAANQADCgYICQAAAA==.Luminei:BAAANQAECgIIAwAAAA==.Lunakiss:BAAANQADCgYIBgAAAA==.Lutz:BAAANQAECgEIAQAAAA==.',
Ly='Lynestra:BAAANQAECgcIDAAAAA==.Lynmei:BAAANQADCgYIDgAAAA==.Lyth:BAAANQADCgIIAgAAAA==.Lythor:BAAANQAECgEIAQAAAA==.',
Ma='Mackyla:BAAANQAECgMIAwAAAA==.Macáronì:BAAANQADCgIIAgAAAA==.Mafdett:BAAANQADCggIFAAAAA==.Mafilrion:BAAANQAECggIDAAAAA==.Magicae:BAEANQAECgUICwAAAA==.Magiia:BAAANQADCgUIBQABNQAECgcIDAABAAAAAA==.Magnestra:BAAANQADCgMIAwAAAA==.Manicmonk:BAAANQADCgUIBQAAAA==.Mantova:BAAANQAECgQIBQAAAA==.Masholy:BAAANQADCggICAABNQAECgQIBgABAAAAAA==.Matt:BAAANQAECgIIAgAAAA==.Matthxw:BAAANQAECgYICAAAAA==.Mayomonk:BAAANQADCgMIAwAAAA==.Mayzh:BAAANQAECgEIAQAAAA==.',
Mc='Mcbain:BAAANQADCggIEwAAAA==.',
Md='Mdma:BAAANQADCggIDgAAAA==.',
Me='Melahna:BAAANQAECgUIDQAAAA==.Melwyn:BAAANQADCgcIEwAAAA==.',
Mg='Mgunit:BAAANQAECgIIAgAAAA==.',
Mi='Mikotö:BAAANQADCggICAABNQAECgQIBgABAAAAAA==.Milkyjoe:BAAANQAECgcIDgAAAA==.Milkysprayed:BAAANQAECgcIDAAAAA==.Mistajeeves:BAAANQADCgYIBgAAAA==.Mistweaved:BAAANQADCgQIBAAAAA==.Mithras:BAAANQADCgcICAAAAA==.Mithrasxox:BAAANQADCgEIAQABNQADCgcICAABAAAAAA==.',
Mo='Mochinator:BAAANQAECgQIBgAAAA==.Modigularna:BAAANQADCgUIBwAAAA==.Mojojojo:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Mollydooker:BAAANQAECgQICAAAAA==.Monkess:BAAANQADCgIIAgAAAA==.Monkeymagick:BAAANQAECgEIAQAAAA==.Monklips:BAAANQAECgIIAgAAAA==.Morbidfetus:BAAANQADCgIIAgAAAA==.Mortassus:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Mortelunes:BAAANQADCgMIAwAAAA==.Mortira:BAAANQAECgQIBgAAAA==.Morzierz:BAAANQAECgIIAgAAAA==.Mottie:BAAANQADCgQIBAABNQADCgYICgABAAAAAA==.Mouldybum:BAAANQADCgQIBAAAAA==.Mozrael:BAAANQAECgEIAQAAAA==.',
Mu='Muaddib:BAAANQAECgEIAQABNQAECgMIBgABAAAAAA==.Mummadudu:BAAANQADCgUIBgAAAA==.Murkroz:BAAANQAECgYICgAAAA==.',
My='Mycelia:BAAANQADCgQIBAAAAA==.Mymistyboo:BAAANQADCgcIBwAAAA==.Myrkvitill:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Mystfyre:BAAANQADCgYIDgAAAA==.',
['Më']='Mëphistò:BAAANQAECgQIBAAAAA==.',
['Mò']='Mòònshine:BAAANQAECgEIAQABNQABCgMIAwABAAAAAA==.',
Na='Naeirm:BAAANQADCgUIBQAAAA==.Naissa:BAAANQADCgMIAwAAAA==.Namewaståken:BAAANQADCggIDAAAAA==.Nasdarath:BAAANQADCgYICwAAAA==.Nato:BAAANQAECgYICgAAAA==.Naturefire:BAAANQABCgUIBgAAAA==.Navimie:BAEANQAECgIIAgAAAA==.',
Ne='Neff:BAAANQAECgEIAQAAAA==.Negus:BAAANQAECgQIBgAAAA==.Nelphey:BAAANQAECgQIBgAAAA==.Nephamar:BAAANQADCggIDgAAAA==.',
Nh='Nhael:BAAANQAECgEIAQAAAA==.',
Ni='Nialdo:BAAANQAECgQIBQAAAA==.Nickwindfury:BAAANQAECgQIBwAAAA==.Nightfarer:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Nightshift:BAAANQADCgYIBgAAAA==.Nikko:BAAANQADCgMIAwAAAA==.Niklasmunn:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.Nikno:BAAANQAECgMIAwAAAA==.Nips:BAAANQAECgYIDAAAAA==.Nipsymcgeé:BAAANQAECgEIAQAAAA==.Nitegorh:BAAANQADCgEIAQAAAA==.Nixea:BAAANQADCgQIBwAAAA==.',
No='Nogin:BAAANQADCgYIBwAAAA==.Nomby:BAAANQAECgYIDQAAAA==.Noobishly:BAAANQADCgcICAAAAA==.Noperope:BAAANQADCggICQAAAA==.Norinari:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Nostradamos:BAAANQADCgEIAQAAAA==.Novnaholycow:BAAANQADCgYICAAAAA==.Noyou:BAAANQAECgQIBQAAAA==.',
['Nè']='Nèos:BAAANQAECgIIAgAAAA==.',
['Ní']='Níhilus:BAAANQAECgEIAQAAAA==.',
['Nô']='Nôx:BAAANQADCgcIBwAAAA==.',
['Nÿ']='Nÿmber:BAAANQADCggIDgAAAA==.',
Ob='Obake:BAAANQAECgIIAgABNQAECgQIBwABAAAAAA==.Obamalives:BAAANQAECgQICQAAAA==.Obsolve:BAAANQAECgMIAwAAAA==.',
Ol='Olddrekky:BAAANQAECgMIAwAAAA==.Oldegregg:BAAANQAECgcICQAAAA==.Oldtimér:BAAANQADCgYIDQABNQAECgMIAwABAAAAAA==.',
On='Onikage:BAAANQAECgcIDAAAAA==.Onlyfrends:BAAANQAECgEIAQAAAA==.',
Oo='Oolanna:BAAANQADCgcIBwAAAA==.Ooragnak:BAAANQAECgIIAgAAAA==.',
Or='Orb:BAAANQADCggIDgABNQAECgEIAQABAAAAAA==.Orobos:BAAANQAECggIBgAAAA==.',
Ot='Othentik:BAAANQAECgYIBwAAAA==.Otl:BAAANQAECgEIAQAAAA==.',
Ov='Overt:BAAANQAECgUICAABNQAFFAMIAwABAAAAAA==.',
Pa='Palaboodledo:BAAANQAECgUICgAAAA==.Palarsynimz:BAEANQADCggIEAABNQAECgYIFQABAAAAAA==.Pallyative:BAAANQAECgEIAQAAAA==.Palomar:BAAANQAECgEIAQAAAA==.Pancake:BAAANQAECgIIAgAAAA==.Para:BAAANQAECgQICAAAAA==.Pavlovaa:BAAANQAECgIIAgAAAA==.',
Pe='Peepeedemon:BAAANQAECgcIDQAAAA==.Peleiades:BAAANQAECgYICAAAAA==.Pewbute:BAAANQADCgEIAQABNQADCgUIBQABAAAAAA==.Pewpews:BAAANQAECgQIBgAAAA==.',
Ph='Phetusdeletu:BAAANQAECgIIAgAAAA==.',
Pi='Pirrin:BAAANQAECgYIDQAAAA==.',
Pk='Pk:BAAANQAECgcIBwABNQAFFAEIAQABAAAAAA==.Pks:BAAANQAFFAEIAQAAAA==.',
Pn='Pnau:BAAANQAECgIIAgAAAA==.',
Po='Pownrz:BAAANQAECgcIBwAAAA==.Pownzz:BAAANQADCggICAABNQAECgcIBwABAAAAAA==.',
Pr='Privilege:BAAANQADCgYIDAAAAA==.',
Ps='Psycthyr:BAAANQADCgcIEQABNQAECgMIAwABAAAAAA==.',
Pu='Purrpleelff:BAAANQAECgYICAAAAA==.',
Pw='Pwrwrdboner:BAAANQADCgcIDgABNQADCgcICAABAAAAAA==.',
Py='Pyrande:BAAANQADCgUIBQABNQADCgcIEwABAAAAAA==.Pyrhic:BAAANQADCgMIAwAAAA==.',
['Pä']='Pändörä:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Qa='Qasqiri:BAAANQAECgMIAwAAAA==.',
Qu='Quack:BAAANQAECgEIAQAAAA==.Queeshi:BAAANQADCgUICAAAAA==.',
['Qà']='Qài:BAAANQADCgEIAQAAAA==.',
Ra='Ragilas:BAAANQADCggICAABNQAECgcIEQABAAAAAA==.Rahj:BAAANQAECgMIAwAAAA==.Rainbowbash:BAAANQADCgMIBgAAAA==.Rainz:BAAANQAECgQIBgAAAA==.Rambro:BAAANQAECgQIBgABNQAECgYICgABAAAAAA==.Ranfin:BAAANQAECgYICgAAAA==.Raqzel:BAAANQADCgEIAQAAAA==.Rare:BAAANQAECgIIAgAAAA==.Rarox:BAAANQADCgIIAgAAAA==.Ravinstep:BAAANQAECgYIDAAAAA==.Rawkalot:BAAANQAECgUIBwABNQAECgYICgABAAAAAA==.Razs:BAAANQADCggIDwAAAA==.Razzles:BAAANQAECgMIBQABNQAECgQIDAABAAAAAA==.',
Re='Redpal:BAABNQAECoEiAAIFAAkJMR7qDAD2AgAFAAkJMR7qDAD2AgAAAA==.Reduvia:BAAANQAECgEIAQAAAA==.Reekin:BAAANQAECgIIAgABNQABCgMIAgABAAAAAA==.Regí:BAAANQADCgYIBgAAAA==.Rendover:BAAANQADCgUICAAAAA==.Revyfox:BAAANQADCgEIAgAAAA==.',
Rh='Rheagz:BAAANQABCgQIBQAAAA==.',
Ri='Rielta:BAAANQADCggIFgAAAA==.Rightround:BAAANQADCgcIBwAAAA==.Rimrap:BAAANQADCgIIAgAAAA==.Rimurlzul:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.',
Ro='Robapaladin:BAAANQADCggICwAAAA==.Robbington:BAAANQADCgcIEQAAAA==.Rocketts:BAAANQADCgYIDgAAAA==.Rokket:BAAANQAECgIIBQAAAA==.',
Ru='Ruthia:BAAANQAECgQIBgAAAA==.Ruumn:BAAANQADCggIFQAAAA==.',
Ry='Rylaras:BAAANQADCggIEwAAAA==.Ryogen:BAAANQAECgEIAQAAAA==.',
['Rê']='Rêvy:BAAANQAECgIIAwAAAA==.',
Sa='Sabretoothed:BAAANQADCgcIEwAAAA==.Saifere:BAAANQAECgUIBwAAAA==.Sajyah:BAAANQADCggICAABNQAECgYICgABAAAAAA==.Samanas:BAAANQAECgcIEAABNQAECggIEgABAAAAAA==.Sambali:BAAANQADCgYIDQAAAA==.Samgamgee:BAAANQADCgYICwAAAA==.Samonki:BAABNQAECoEYAAIUAAkJ4SErAQB4AwAUAAkJ4SErAQB4AwAAAA==.Samotem:BAAANQAECgMIBAABNQAECgkJGAAUAOEhAA==.Sanctify:BAAANQAECgEIAQAAAA==.Santera:BAAANQAECgEIAQAAAA==.Saridana:BAAANQADCgQIBgAAAA==.Satire:BAAANQAECgEIAQAAAA==.Savriel:BAAANQAECgUIDQAAAA==.',
Sc='Schnoogans:BAAANQAECgUICAAAAA==.Scottieboi:BAAANQAECgUIEAAAAA==.Scratchies:BAAANQAECgYIBwAAAA==.Screamdemons:BAAANQADCgYIDgAAAA==.Scyadin:BAAANQAECgQIBAAAAA==.Scyler:BAABNQAECoEYAAINAAgJHCOKCgDeAgANAAgJHCOKCgDeAgAAAA==.',
Se='Seffyre:BAAANQAECgMIAwAAAA==.Seilyre:BAAANQAECgQICAAAAA==.Sekuta:BAAANQAECggIEgAAAA==.Seltic:BAAANQAECgEIAQAAAA==.Senessara:BAAANQADCggIEwAAAA==.Senjougahara:BAAANQAECgEIAQAAAA==.Seregios:BAAANQAECgQIBQAAAA==.Sevrus:BAAANQAECgIIAgAAAA==.Seyn:BAAANQADCggIHgAAAA==.',
Sg='Sgtsquat:BAAANQAECgQICAAAAA==.',
Sh='Shabria:BAAANQAECgIIAwAAAA==.Shadowthief:BAABNQAECoEXAAIVAAcJJBN6JQDCAQAVAAcJJBN6JQDCAQAAAA==.Shaetore:BAAANQAECggIDAAAAA==.Shagbark:BAAANQAECgQIBAAAAA==.Shambuu:BAAANQAECgQICQAAAA==.Shammytammy:BAAANQADCggIFQAAAA==.Sharmtor:BAAANQAECgcIDAAAAA==.Sharzam:BAAANQADCgMIAwAAAA==.Shauthra:BAAANQADCgYIDQAAAA==.Shazamza:BAAANQADCgUIBwAAAA==.Shazzles:BAAANQADCgUICgABNQAECgQIDAABAAAAAA==.Sheldelphine:BAAANQAECgQIBQAAAA==.Shellemental:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Shellstalker:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Shenhua:BAAANQAECgQIBQAAAA==.Sherber:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Shin:BAAANQAECgcIDAAAAA==.Shiné:BAAANQAECgEIAQAAAA==.Shoccymilk:BAAANQADCggIDAAAAA==.Shyftzilla:BAAANQADCgIIAgAAAA==.Shåmanigans:BAAANQAECgMIAwAAAA==.',
Si='Siasham:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.Sidis:BAAANQAECgQIBgABNQAECgQIBgABAAAAAA==.Sindrawrei:BAAANQADCgQIBAAAAA==.Sixxpal:BAAANQAECgUIEAAAAA==.',
Sk='Skanktank:BAAANQAECgUIDQAAAA==.Skankvoker:BAAANQAECgQIBQABNQAECgUIDQABAAAAAA==.Skarrovectis:BAAANQADCgEIAQAAAA==.Skathlok:BAAANQAECgUIDQAAAA==.Skest:BAAANQAECgEIAQAAAA==.Skidstains:BAAANQADCgcIDQAAAA==.Skindeep:BAAANQAECgEIAQAAAA==.Skragrott:BAAANQAECgcIDQAAAA==.Skullçrusher:BAAANQAECgEIAQAAAA==.Skybomb:BAAANQADCggIDgAAAA==.',
Sl='Slashycrisps:BAAANQAECgEIAQAAAA==.Slobfather:BAAANQADCgIIBQAAAA==.',
Sm='Smacknzug:BAAANQADCgcIDAAAAA==.Smashmedaddy:BAAANQAECgUICQAAAA==.',
Sn='Snapp:BAAANQADCggIEAAAAA==.Sneaksham:BAAANQAECgYIBwAAAA==.Sneakswar:BAAANQAECgQIEgAAAA==.Snowbind:BAAANQADCggIDgAAAA==.',
So='Sofarogue:BAAANQAECgQIBgAAAA==.Solitiaire:BAAANQADCggICAAAAA==.Solvy:BAAANQAECgEIAQAAAA==.Sonara:BAAANQAECggIBAAAAA==.Soondead:BAAANQAECgMIBgAAAA==.Soulmonk:BAAANQADCgYICAAAAA==.',
Sp='Sparkies:BAAANQAECgQICAAAAA==.Spieluhr:BAAANQAECgIIAgAAAA==.Spiritwhislr:BAAANQAECgEIAQAAAA==.Splatzor:BAAANQAECgIIAgAAAA==.',
St='Stabilitas:BAABNQAECoEXAAIWAAcJ/A/kEQCsAQAWAAcJ/A/kEQCsAQAAAA==.Stalsurge:BAAANQAECgIIAgAAAA==.Starborne:BAABNQAECoEaAAIXAAcJmBvHDQAsAgAXAAcJmBvHDQAsAgAAAA==.Sthöly:BAAANQADCgcIDQABNQAECgQIBgABAAAAAA==.Stockyx:BAAANQAECgcIEQAAAA==.',
Su='Sudamon:BAAANQADCgEIAQAAAA==.Summoninc:BAABNQAECoEVAAISAAYJMg+uOgBnAQASAAYJMg+uOgBnAQAAAA==.Sunila:BAAANQAECgcIDAAAAA==.Suntigerr:BAAANQAECgQIBgAAAA==.Superhanz:BAAANQADCgYIBgAAAA==.Suyasha:BAAANQAECgQIBgAAAA==.',
Sw='Swalala:BAAANQADCgIIAgAAAA==.Sweetmemeboy:BAAANQAECgQIBQAAAA==.Swipes:BAAANQADCgYIBgAAAA==.',
Sy='Sylvias:BAAANQAECgMIAwAAAA==.Syreandrena:BAAANQAECgUIDgAAAA==.Syse:BAAANQADCgYIBgAAAA==.Syvan:BAAANQAECgQIBAAAAA==.',
['Sã']='Sãmael:BAABNQAECoEXAAIYAAcJUA16BQBwAQAYAAcJUA16BQBwAQAAAA==.',
['Sé']='Séhkmet:BAAANQADCggIDgAAAA==.',
['Só']='Sól:BAAANQADCggICgAAAA==.',
Ta='Tabbandit:BAAANQAECgIIAgAAAA==.Taffatups:BAAANQADCgUICAAAAA==.Talena:BAAANQAECgMIAwABNQAECgcIDwABAAAAAA==.Talkingtree:BAAANQADCgcIBwAAAA==.Tallysmeller:BAAANQAECgMIAwAAAA==.Talorus:BAAANQAECgcIDwAAAA==.Tanwahhlock:BAAANQAECgcIDQAAAA==.Tarhata:BAAANQADCgMIBQAAAA==.Tarot:BAAANQAECgEIAQAAAA==.Tatantaca:BAAANQAECgUIEAAAAA==.',
Te='Teknoman:BAAANQAECgEIAQAAAA==.Tena:BAAANQAECgEIAQAAAA==.Teranzil:BAAANQAECgMIAwAAAA==.Terly:BAAANQAECgEIAQAAAA==.Teár:BAAANQADCgcIBwABNQAECgcIEQABAAAAAA==.Teär:BAAANQAECgcIEQAAAA==.',
Th='Thalidomide:BAAANQAECgUIEAAAAA==.Thastir:BAAANQADCgYICwABNQADCggIEAABAAAAAA==.Theavenger:BAAANQAECgQIBQAAAA==.Thedis:BAAANQADCgUIBgAAAA==.Thomus:BAAANQAECgQIBQAAAA==.Thormuss:BAAANQADCgUICQABNQAECgcICQABAAAAAA==.Thundèrthigh:BAAANQADCgYIEgAAAA==.Thuxis:BAAANQAECgcIDAAAAA==.Thânãtös:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Ti='Timmymage:BAAANQABCgEIAQAAAA==.Tishenya:BAAANQADCgYIBwAAAA==.',
To='Toezrmeanae:BAAANQAECgQICAAAAA==.Tokot:BAAANQAECgUIDgAAAA==.Tombstone:BAAANQAECgEIAQAAAA==.Tomsshaman:BAAANQAECgUICgAAAA==.Toniqjin:BAAANQAECgIIAgAAAA==.Toot:BAAANQADCgQIBAABNQAECgUIBgABAAAAAA==.Toowhiskay:BAAANQAECgcIDwAAAA==.Toridin:BAAANQADCgYIBgAAAA==.Tormentess:BAAANQAECgcIEwAAAA==.',
Tr='Translatov:BAAANQADCgUIBQAAAA==.Trashlok:BAAANQADCgIIAgAAAA==.Trinitylimit:BAAANQAECgIIAgAAAA==.Tripletd:BAAANQADCgMIBgAAAA==.Tripo:BAAANQADCgEIAQAAAA==.Trippy:BAAANQAECgEIAgAAAA==.Trixiest:BAAANQADCggIFgAAAA==.Truuesham:BAAANQADCgMIAwAAAA==.',
Tu='Tulasham:BAAANQADCgIIAgABNQAECgUIBQABAAAAAA==.Tulathros:BAAANQAECgUIBQAAAA==.',
Tw='Twinkabell:BAAANQADCgEIAQAAAA==.',
Tx='Txci:BAAANQAECgcIBwAAAA==.',
Ty='Tylorän:BAAANQADCggICwAAAA==.',
['Tê']='Tên:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Uc='Uchi:BAAANQAECgYICwAAAA==.Uchuyagi:BAAANQAECgcIDAAAAA==.',
Un='Unbjörn:BAAANQADCggICAAAAA==.Unc:BAAANQAECgIIAgAAAA==.',
Va='Valetudo:BAAANQAECgEIAQAAAA==.Vampiregirl:BAAANQABCgEIAQAAAA==.Vance:BAAANQAECgQIBAAAAA==.Varayne:BAAANQADCgYIDAAAAA==.',
Ve='Veenus:BAAANQAECgQIBQAAAA==.Veladoris:BAAANQAECgMIAwAAAA==.Velinoe:BAAANQAECgEIAQAAAA==.Velkorvasa:BAAANQADCgYIDQAAAA==.Velledara:BAAANQADCgUIBQABNQAECgMIBgABAAAAAA==.Velthuria:BAAANQADCggIDgAAAA==.Verdari:BAAANQAECgEIAQAAAA==.Verlene:BAAANQADCggIDQAAAA==.',
Vi='Vindicatar:BAAANQAECgUICwAAAA==.Vindicator:BAAANQAECgEIAQAAAA==.Virek:BAAANQADCgYIDgAAAA==.Vivarna:BAAANQADCgQIBwAAAA==.',
Vo='Voidtree:BAAANQAECgcIEQAAAA==.Voostab:BAAANQADCgMIAwAAAA==.Vortoxin:BAAANQAECgIIAgAAAA==.',
Vp='Vpallyonekey:BAAANQAECgIIAgAAAA==.',
Vu='Vulpelle:BAAANQADCggICAAAAA==.Vuvuzela:BAAANQADCggIDgAAAA==.',
Vy='Vyeagra:BAAANQAECgMIAwAAAA==.',
['Ví']='Vírus:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.',
Wa='Walshy:BAABNQAECoEaAAIZAAcJrRnxGAAIAgAZAAcJrRnxGAAIAgAAAA==.Wantiwanti:BAAANQAECgYICwAAAA==.Warrvx:BAAANQADCgQIBAAAAA==.Wartor:BAAANQADCgYICAAAAA==.Waxillium:BAAANQAECgEIAQAAAA==.',
We='Well:BAAANQAECgEIAQAAAA==.Wengor:BAAANQADCgYIBgAAAA==.Werglerps:BAAANQAECggIEwAAAA==.',
Wh='Wholegrains:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Whytek:BAAANQAECgEIAQAAAA==.Whytelust:BAAANQADCgcIDQAAAA==.',
Wi='Windcier:BAAANQAECgQIAQABNQAECgYICAABAAAAAA==.Windrider:BAAANQAECgQIBgAAAA==.Wirtle:BAAANQAECgYIDAAAAA==.Wisefrog:BAAANQADCggIDgAAAA==.',
Wo='Worgdeeznuts:BAAANQADCgUIBQAAAA==.',
Wr='Wrathlon:BAAANQAECgQIBgAAAA==.',
Xa='Xandraevia:BAAANQADCgYIDwAAAA==.Xannar:BAAANQAECgQIBQAAAA==.Xarmina:BAAANQAECggIEgAAAA==.',
Ye='Yetzira:BAAANQADCgEIAQAAAA==.',
Yo='Yodashaman:BAAANQAECgUIEAAAAA==.',
Yr='Yrbane:BAAANQADCgUICAAAAA==.',
Za='Zaifer:BAAANQADCgUIBwABNQAECgUIBwABAAAAAA==.Zalayä:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Zaljan:BAACNQAFFIELAAINAAUJihnoAADZAQANAAUJihnoAADZAQA1AAQKgRkAAg0ACQlWGbQLAM4CAA0ACQlWGbQLAM4CAAAA.Zavrall:BAAANQADCgQIBAAAAA==.Zavul:BAAANQAECgIIAgAAAA==.',
Ze='Zehphyzou:BAAANQADCggICQAAAA==.Zeldonn:BAAANQABCgUIBQAAAA==.Zemu:BAAANQADCggICAAAAA==.Zendaiya:BAAANQADCgYIBgAAAA==.',
Zh='Zhànshi:BAAANQAECgMIAwAAAA==.',
Zi='Zidiuz:BAAANQAECgQIBQAAAA==.Zippizap:BAAANQAECgQIBgAAAA==.',
['Âl']='Âlîse:BAAANQAECgEIAQAAAA==.',
['Är']='Ärtorias:BAAANQABCgIIAgAAAA==.',
['Äx']='Äxel:BAAANQADCgMIAgAAAA==.',
['Év']='Évelyn:BAAANQAECgYICQAAAA==.',
['Ðe']='Ðed:BAAANQAECgIIAgAAAA==.',
['Öz']='Öz:BAAANQADCgYIBgAAAA==.',
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
