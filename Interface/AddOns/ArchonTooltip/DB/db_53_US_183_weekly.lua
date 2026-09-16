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

local lookup = {'Priest-Holy','Unknown-Unknown','Druid-Guardian','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Warrior-Arms','Rogue-Subtlety','Druid-Restoration','Druid-Balance','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Mage-Frost','DeathKnight-Frost','DeathKnight-Unholy','Priest-Discipline','Shaman-Elemental','Paladin-Holy','Shaman-Restoration','Mage-Arcane','Mage-Fire','Priest-Shadow','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Brewmaster','Paladin-Protection','DemonHunter-Devourer','Monk-Mistweaver','Rogue-Assassination','Monk-Windwalker','Warlock-Affliction','DeathKnight-Blood',}
local provider = {region='US',realm='Saurfang',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abbeyroad:BAAANQAECgMIBAAAAA==.',
Ad='Adnauseam:BAAANQAECgYIEgAAAA==.',
Ae='Aedaenia:BAAANQAECgEIAQAAAA==.Aelyndara:BAAANQAECgEIAQAAAA==.',
Ag='Agave:BAAANQADCggIFgAAAA==.Aglerion:BAAANQADCgYIBgAAAA==.',
Ah='Ahavah:BAAANQABCgYIBgAAAA==.Ahlya:BAAANQAECgYIEwAAAA==.',
Ai='Aime:BAAANQAECggIBwAAAA==.Aimei:BAAANQAECgQIBgAAAA==.Aiphaton:BAAANQAECgEIAgAAAA==.',
Aj='Ajchmiel:BAAANQADCgcIDwAAAA==.',
Ak='Akanea:BAAANQADCgQICQAAAA==.Ake:BAABNQAECoEVAAIBAAgJHRjZIgA4AgABAAgJHRjZIgA4AgAAAA==.Akàmè:BAAANQAECgUIBwAAAA==.',
Al='Aldavir:BAAANQAECgIIAgABNQAECgcIEgACAAAAAA==.Aldavyr:BAAANQAECgcIEgAAAA==.Aldrick:BAAANQADCgUIBQAAAA==.Alienas:BAAANQAECgMIBQAAAA==.Alighieri:BAAANQAECgEIAQAAAA==.Alinassa:BAAANQAECgYIDAAAAA==.Alinnarra:BAAANQADCggICAABNQAECgYIDAACAAAAAA==.Allacore:BAAANQADCgYIDgAAAA==.Alponyoman:BAAANQAFFAEIAQAAAA==.',
Am='Amaizen:BAAANQADCgYIDgAAAA==.Ameilioli:BAAANQABCgIIBAAAAA==.Amorthian:BAAANQADCggICAAAAA==.',
An='Andrak:BAAANQADCgYIDQAAAA==.Angelock:BAAANQABCgEIAQAAAA==.Angertotem:BAAANQADCgcICQABNQAECgYICwACAAAAAA==.Angkor:BAAANQAECgQIBwAAAA==.Angrboda:BAAANQAECgEIAQABNQAECgIIAwACAAAAAA==.Angusmac:BAAANQAECgEIAQAAAA==.Anhailah:BAAANQAECgYIEwAAAA==.Animos:BAAANQAECgQIBgAAAA==.Annarah:BAAANQAECgYIDAAAAA==.Anselo:BAAANQAECgIIAgAAAA==.Anthropocene:BAAANQAECgQICQAAAA==.',
Ap='Appowulf:BAABNQAECoEWAAIDAAgJFSC0AgD2AgADAAgJFSC0AgD2AgAAAA==.',
Aq='Aquamangue:BAAANQAECgcIDgAAAA==.Aquamoon:BAAANQADCggICQAAAA==.',
Ar='Aragornne:BAAANQAECgQIBgAAAA==.Arcanemage:BAAANQAECgIIAgAAAA==.Archeuz:BAAANQADCggIFwAAAA==.Arkdan:BAAANQAECgEIAQAAAA==.Arnoon:BAAANQAECgYIDgAAAA==.Arogance:BAAANQAECgcIEAAAAA==.',
As='Ashreever:BAAANQADCggIDQAAAA==.Asmodan:BAAANQAECgEIAQAAAA==.',
At='Attonrand:BAAANQAECgQIBAAAAA==.',
Au='Augment:BAAANQABCgIIAwAAAA==.Ausarrow:BAAANQAECgQIBwAAAA==.Ausdruid:BAAANQAECgQIBQAAAA==.',
Av='Avellar:BAAANQADCgIIBAAAAA==.Avianori:BAAANQADCgcIDQAAAA==.',
Ax='Axalotel:BAAANQADCgIIAgAAAA==.Axelfoley:BAAANQADCgcICQAAAA==.',
Az='Azraezel:BAAANQAECgEIBAAAAQ==.Azyrael:BAAANQADCgUIBQABNQAECgEIBAACAAAAAQ==.Azzinot:BAAANQADCgYIDgAAAA==.Azziy:BAAANQADCgYIBgAAAA==.',
['Aã']='Aãri:BAAANQAECgQIBAABNQAECgYIDAACAAAAAA==.',
Ba='Babàyaga:BAAANQADCgQIBAABNQAECgQICgACAAAAAA==.Baelrog:BAAANQADCggIDgABNQAECgQICQACAAAAAA==.Barthom:BAABNQAECoEnAAIEAAgJARGGNgAfAgAEAAgJARGGNgAfAgAAAA==.Baràk:BAABNQAECoElAAMEAAcJLA9XWACZAQAEAAYJZBBXWACZAQAFAAUJPwqDKgAYAQAAAA==.',
Be='Bearzlock:BAAANQAECgYIEAAAAA==.Bearzmage:BAAANQAECgMIAwABNQAECgYIEAACAAAAAA==.Beatrix:BAAANQAECgIIAgAAAA==.Bedebah:BAAANQAECgYIDAAAAA==.Beebeecee:BAAANQAECggICAAAAA==.Beerington:BAAANQAECgUICAAAAA==.Behemoth:BAAANQAECgEIAQAAAA==.Belirisa:BAAANQADCgEIAQAAAA==.Berknerkem:BAAANQADCggIFAAAAA==.Bewmz:BAAANQAECgQIBgAAAA==.',
Bi='Bigboomz:BAAANQAECgIIAgAAAA==.Bigoltrollop:BAAANQAECgQIBQAAAA==.Biscuitcapes:BAAANQADCggIEAAAAA==.Bison:BAAANQADCgMIAwAAAA==.Bistavert:BAAANQAECgcIDAAAAA==.',
Bl='Blinkinpark:BAAANQADCgYIDAAAAA==.Bllissbubble:BAAANQADCggICAABNQAECgUICAACAAAAAA==.Bllissterine:BAAANQADCggICAABNQAECgUICAACAAAAAA==.Bllissticks:BAAANQAECgUICAAAAA==.Bllisstrix:BAAANQADCggICAABNQAECgUICAACAAAAAA==.Blxckbeef:BAABNQAECoEXAAIGAAcJrQkKZwBmAQAGAAcJrQkKZwBmAQAAAA==.',
Bo='Bombsquad:BAAANQAECgIIAgABNQAECgkJHQAHABolAA==.Boomie:BAAANQADCgYIBgAAAA==.Bornewithit:BAABNQAECoElAAIIAAcJkhqzDgBCAgAIAAcJkhqzDgBCAgAAAA==.Borttheblade:BAAANQAECgYIDwABNQAFFAEIAQACAAAAAA==.',
Br='Brandyshot:BAAANQAECgQIBgAAAA==.Brewberry:BAAANQAECgIIAgAAAA==.Brewtalîty:BAAANQAECgMIBQAAAA==.Briar:BAAANQADCggIDgAAAA==.Brownman:BAAANQADCgcICAAAAA==.Brush:BAAANQAECgYIEAAAAA==.Bruvski:BAAANQAECgQIBgAAAA==.',
Bu='Bumsrush:BAAANQADCgUIBQAAAA==.Bunniex:BAAANQADCgcIDQAAAA==.Bustacrime:BAAANQAECggICQAAAA==.',
Bw='Bwthhybl:BAAANQAECgQIBgAAAA==.',
By='Bytes:BAAANQAECgYIDAAAAA==.',
['Bü']='Bünny:BAAANQAECgQICgAAAA==.',
Ca='Cairnless:BAAANQAECgYICAAAAA==.Cakesrlife:BAAANQAECgUICQAAAA==.Calafiori:BAAANQADCggICAAAAA==.Camilletrois:BAAANQABCgIIAwAAAA==.Captcinder:BAAANQADCgMIAwAAAA==.Carabine:BAAANQAECgYICgAAAA==.Caselorc:BAAANQADCgYIDwABNQADCgcICgACAAAAAA==.Cata:BAAANQAECgQICgAAAA==.Catscythe:BAAANQADCggIGQAAAA==.Cauthon:BAAANQAECgEIAQAAAA==.Cavemanwar:BAAANQAFFAEIAQAAAA==.',
Ce='Celendra:BAAANQAECgMIAwAAAA==.Celtic:BAACNQAFFIELAAIJAAYJ2BGcAADyAQAJAAYJ2BGcAADyAQA1AAQKgRkAAwkACQkQGG0JAKQCAAkACQkQGG0JAKQCAAoABAl0FQhEABkBAAAA.Ceredan:BAAANQADCgcIDAAAAA==.Cethul:BAAANQADCgcIBwABNQAECgcIEwACAAAAAA==.',
Ch='Challisa:BAAANQADCgEIAQAAAA==.Chaoskane:BAAANQAECgIIAgAAAA==.Charnaby:BAABNQAECoEfAAMLAAgJAB7hNAABAgALAAYJphzhNAABAgAMAAIJDSLXMgDBAAAAAA==.Cheeksmasher:BAAANQAECgEIAQAAAA==.Cheesesteaks:BAAANQADCgcIDwAAAA==.Chellê:BAAANQAECgIIAwAAAA==.Chicknburgah:BAACNQAFFIEGAAIHAAQJww4jBwBLAQAHAAQJww4jBwBLAQA1AAQKgSEAAwcACQmUIXYNAF0DAAcACQkOIXYNAF0DAA0AAwmtH+MMABUBAAAA.Chillhunter:BAAANQAECggIBwAAAA==.Chillyia:BAAANQADCgcIDgABNQAECgYIEAACAAAAAA==.Chocorondo:BAAANQAECgcIEQAAAA==.Chokystafish:BAAANQADCgUIBQAAAA==.Chonkmagic:BAAANQAECgQICQAAAA==.Chowhai:BAAANQAECgIIAgAAAA==.',
Ci='Ciaraa:BAAANQADCgEIAQAAAA==.Cindymore:BAAANQADCgYIBgABNQAECgYICAACAAAAAA==.Circus:BAAANQAECgUICwAAAA==.',
Cl='Clawtism:BAAANQADCggICAAAAA==.',
Co='Cobólt:BAAANQADCgUICgAAAA==.Cocola:BAAANQADCgUIBwAAAA==.Colanius:BAAANQADCgQIBAABNQAECgYIDAAOAM8HAA==.Corte:BAABNQAECoEnAAIPAAcJIRIDHQCdAQAPAAcJIRIDHQCdAQAAAA==.Coverghoul:BAABNQAECoEbAAIQAAgJRBLNKAD0AQAQAAgJRBLNKAD0AQABNQAECggJGwAQAEQSAA==.',
Cr='Crazedorc:BAAANQAECgcIDgAAAA==.Creamymoot:BAAANQADCggIEwABNQAECgEIAQACAAAAAA==.Crispyjeww:BAAANQAECggIBgAAAA==.Croescrane:BAAANQAECgYIDgAAAA==.Crooked:BAAANQAECgQIBgAAAA==.Crossblessër:BAAANQAECgQIBwABNQABCgQIBQACAAAAAA==.',
Cy='Cynthus:BAABNQAECoEfAAMBAAcJFB65HgBUAgABAAcJFB65HgBUAgARAAEJjwX2GwArAAAAAA==.',
['Cé']='Cérberus:BAAANQAECgQIBQAAAA==.',
Da='Daltonus:BAAANQAECggICAAAAA==.Damador:BAAANQAECgYIEAAAAA==.Damisia:BAAANQAECgUIBwAAAA==.Damuss:BAAANQAFFAEIAQAAAA==.Danirumi:BAAANQAECgQICwAAAA==.Danithir:BAAANQADCgQIBQAAAA==.Danndk:BAAANQAECgYIEAAAAA==.Danndruid:BAAANQADCgEIAQAAAA==.Dannpriest:BAAANQAECgEIAQAAAA==.Dannsham:BAAANQADCgIIAwAAAA==.Darkiller:BAAANQADCgEIAgAAAA==.Darkpriest:BAAANQAECggIAQAAAA==.Darksox:BAAANQAECgIIAgAAAA==.Daylisha:BAAANQAECgQIBwAAAA==.Dayn:BAAANQAECgEIAQAAAA==.Dazzles:BAABNQAECoEaAAILAAYJ4xt4NgD5AQALAAYJ4xt4NgD5AQAAAA==.',
De='Deablohuntsu:BAAANQADCggICAAAAA==.Deabloknight:BAAANQAECgQICQAAAA==.Deablosrage:BAAANQAECgIIBQAAAA==.Deadotz:BAAANQABCgYICAAAAA==.Deathraider:BAAANQAECgQICgAAAA==.Ded:BAAANQAECgcIEwAAAA==.Demonboog:BAAANQAECgcIBwAAAA==.Demongasher:BAAANQADCgYICQAAAA==.Demonlag:BAAANQABCgcICQAAAA==.Demonmus:BAAANQADCggIDwAAAA==.Demonpandaz:BAAANQAECgQICAAAAA==.Dessa:BAAANQAECgMIAwABNQAECgYICwACAAAAAA==.Dessane:BAAANQAECgYICwAAAA==.Dexdragoon:BAAANQAECgUIDwAAAA==.',
Di='Dijonmustard:BAAANQADCggIHAAAAA==.Diora:BAAANQAECgcIEAAAAA==.Divineon:BAAANQAECgEIAQAAAA==.Dizzydrunk:BAAANQAECgEIAQABNQAECgMIBQACAAAAAA==.',
Dk='Dkdence:BAAANQAECgcIEwAAAA==.',
Do='Dodo:BAAANQAECgMIBQAAAA==.Dominationn:BAAANQADCgYIBgAAAA==.Donfandangle:BAAANQADCggIEAAAAA==.Donkeykongg:BAABNQAECoEeAAISAAkJESGkCABiAwASAAkJESGkCABiAwAAAA==.Doofyspally:BAAANQADCgYIBgAAAA==.Doomadin:BAABNQAECoEZAAITAAcJ8h7fGwCCAgATAAcJ8h7fGwCCAgAAAA==.Dora:BAAANQAECgQICAAAAA==.Dovarkin:BAAANQAECgcICgAAAA==.',
Dr='Drabsysham:BAACNQAFFIEGAAIUAAIJPxcMCgCrAAAUAAIJPxcMCgCrAAA1AAQKgSEAAxQACQkcHpsKABcDABQACQkcHpsKABcDABIAAwkZGYN2AOwAAAAA.Dracarsynimz:BAEANQAECgYIIQAAAQ==.Draczr:BAAANQAECgYIEwAAAA==.Dragonbunny:BAAANQADCgMIAwAAAA==.Dragrit:BAAANQADCgYIBgABNQAECgkJIQAOAHgiAA==.Dragrito:BAAANQAECgUIBQABNQAECgkJIQAOAHgiAA==.Dragritt:BAAANQAECgMIBAABNQAECgkJIQAOAHgiAA==.Dragritto:BAABNQAECoEhAAQOAAkJeCK1AQDjAgAOAAcJ7CS1AQDjAgAVAAgJ8x5VNQC8AgAWAAIJXRpEBACqAAAAAA==.Dragsham:BAAANQADCgQIBAABNQAECgkJIQAOAHgiAA==.Dragsnek:BAAANQADCgMIAwABNQAECgkJIQAOAHgiAA==.Dragönshade:BAABNQAECoEnAAIXAAgJhRQmEQBUAgAXAAgJhRQmEQBUAgAAAA==.Drakage:BAAANQADCgMIAwAAAA==.Drakana:BAAANQAECgUICAAAAA==.Draykora:BAAANQAECgcIEAAAAA==.Drazzig:BAAANQADCgMIAwAAAA==.Dreambreaker:BAAANQAECgIIAwAAAA==.Drekavoc:BAAANQADCgIIAgABNQADCgMIBgACAAAAAA==.Drewzus:BAAANQAECgEIAQAAAA==.Drexanoth:BAAANQADCgQIBAAAAA==.Drusindra:BAAANQADCgcIDwAAAA==.',
Du='Dudeman:BAAANQAECgQIBgAAAA==.Durabull:BAAANQADCgYICQAAAA==.',
Dw='Dwarfz:BAAANQAECgQICAAAAA==.',
Ea='Earthbreaker:BAAANQAECgEIAgAAAA==.',
Ed='Edavv:BAAANQADCgQICAABNQAECgcIGwAYAFUQAA==.Edmo:BAAANQAECgcIDgAAAA==.Edrandil:BAAANQAECgUIDwAAAA==.',
Ee='Eevula:BAAANQADCgEIAgAAAA==.',
Ei='Eiluaq:BAAANQADCggIGAAAAA==.Eirianna:BAAANQADCggIEAAAAA==.',
El='Elcrabbette:BAAANQAECgQIBwAAAA==.Elegant:BAAANQAECgQIBQAAAA==.Elemelôn:BAAANQAECgEIAgABNQAECggIJwAXAIUUAA==.Elundara:BAAANQAECgcIEgAAAA==.',
Eq='Eq:BAAANQADCggIFAAAAA==.',
Es='Estardra:BAAANQAECgYICwAAAA==.',
Eu='Euri:BAAANQADCggICAAAAA==.',
Ev='Evelice:BAABNQAECoEMAAMOAAYJzwc+GwBrAAAVAAUJowcW0AAZAQAOAAIJrgk+GwBrAAAAAA==.Everla:BAAANQABCggICgAAAA==.Evialsong:BAAANQADCgUIBQAAAA==.Evokiia:BAAANQADCgYICQABNQAECgkJGQAXAPgTAA==.',
Ex='Exajoule:BAAANQADCgUIBQABNQAECggIJwAEAAERAA==.Exiledpally:BAAANQADCgQIBAAAAA==.',
Fa='Faeryall:BAABNQAECoEYAAILAAcJHhDUQgDBAQALAAcJHhDUQgDBAQAAAA==.Fahkmoi:BAAANQADCgYIBgAAAA==.Fakeyoda:BAAANQAECgYICwAAAA==.Falua:BAAANQAECgQIBAAAAA==.Famiine:BAAANQADCggICwAAAA==.Fannychmela:BAAANQAECgEIAQAAAA==.Faranight:BAAANQAECgIIAwAAAA==.Faright:BAAANQAECgMIBgAAAA==.Fatherspark:BAAANQAECgEIAQAAAA==.Fatherursid:BAAANQADCggIEQABNQAECgcIHQAJAHEXAA==.',
Fe='Feara:BAAANQAECgUICAAAAA==.Fefeasa:BAAANQADCgQIBQAAAA==.Feistyfist:BAAANQAECgQIBQAAAA==.Fekzak:BAAANQADCgcICgAAAA==.Felmeup:BAAANQADCgEIAQAAAA==.Fenglei:BAAANQADCgcIDQABNQAFFAQIBgAVAJQOAA==.Fengliu:BAACNQAFFIEGAAMVAAQJlA4pCgBPAQAVAAQJTQ4pCgBPAQAOAAEJegOFBQBFAAA1AAQKgSEAAxUACQlXH9QrAOICABUACQmVHtQrAOICAA4AAgl8IE8UALQAAAAA.Fengmin:BAAANQADCggIEAABNQAFFAQIBgAVAJQOAA==.Fennik:BAAANQADCgIIAgAAAA==.Fenriz:BAAANQAECgQIBgAAAA==.',
Fi='Fieryroota:BAABNQAECoEfAAIVAAcJSCGIQQCNAgAVAAcJSCGIQQCNAgAAAA==.Findewin:BAAANQAECgQIBgAAAA==.Fiyerite:BAAANQAECgcIDAAAAA==.Fizzypal:BAAANQAECgYICgAAAA==.',
Fl='Flameeater:BAAANQAECgUICgAAAA==.Flynnyzyzz:BAABNQAECoElAAISAAcJZiZLDgAbAwASAAcJZiZLDgAbAwAAAA==.',
Fo='Focksea:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Folk:BAAANQABCgIIAgAAAA==.Formidable:BAAANQAECgQIBAABNQAECgcIJQAIAJIaAA==.Fotcjermaine:BAAANQABCgIIAgAAAA==.',
Fr='Franked:BAAANQAECgMIAwAAAA==.Frogster:BAAANQADCgMIAwAAAA==.Frogwash:BAAANQADCgMIAwABNQAECgUIBgACAAAAAA==.Frozenmole:BAAANQADCgQICAABNQAECgQIBAACAAAAAA==.',
Fu='Furrylock:BAABNQAECoEaAAMMAAcJLwrLGgBpAQAMAAcJLwrLGgBpAQALAAEJfQERzQAkAAAAAA==.Fuzzlicia:BAAANQADCgcIDQABNQAECgQIBQACAAAAAA==.Fuzzyballs:BAAANQAECgEIAQAAAA==.',
Fy='Fyaha:BAAANQADCggICAAAAA==.Fylson:BAAANQADCggICAAAAA==.',
['Fú']='Fúzzlë:BAAANQAECgQIBQAAAA==.',
Ga='Gadgetgeek:BAAANQADCgMIAwAAAA==.Galeidan:BAAANQAECgQIBQAAAA==.Gameoftroll:BAAANQAECgcIEwAAAA==.Gamumush:BAAANQAECgcIEwAAAA==.Gamush:BAAANQADCgYIBgABNQAECgcIEwACAAAAAA==.Gargola:BAAANQADCgYIBwAAAA==.Garntek:BAAANQAECgIIAwAAAA==.Garryx:BAAANQADCgcIBwAAAA==.Garstomp:BAAANQAECgEIAQABNQAECgMIAwACAAAAAA==.Garókk:BAAANQADCgYIDwAAAA==.',
Ge='Geauxphreigh:BAAANQAECgUIBgAAAA==.',
Gh='Ghostbom:BAAANQADCgcICQAAAA==.',
Gi='Giggels:BAAANQAECgcIDwAAAA==.Gilletté:BAAANQAECgIIAwAAAA==.Gillydor:BAAANQABCgIIAwAAAA==.',
Gl='Glaiviture:BAAANQAECgEIAgAAAA==.',
Go='Goodgravy:BAAANQADCgMIAwAAAA==.Gorenrisao:BAAANQAECgEIAgABNQAECgYIDAAOAM8HAA==.Gothmommy:BAAANQADCgcIBwAAAA==.Gotsalt:BAAANQAECgcIEwAAAA==.Gotsdots:BAABNQAECoEgAAMMAAkJ5hlQCgApAgALAAgJ8BcmJQBTAgAMAAcJ3hdQCgApAgAAAA==.',
Gr='Greendoor:BAAANQAECgUICwAAAA==.Gren:BAAANQADCgYIDgAAAA==.Gretl:BAAANQADCgYIBgAAAA==.Griimmjjow:BAAANQADCgYIBgAAAA==.Growvert:BAABNQAFFIEIAAIKAAQJyBNOBQBVAQAKAAQJyBNOBQBVAQAAAA==.',
['Gé']='Gémini:BAAANQADCgIIAgAAAA==.',
['Gø']='Gødslapp:BAAANQAECgYICwAAAA==.',
Ha='Hahwei:BAAANQAECgIIAgABNQAECgIIAgACAAAAAA==.Hailej:BAAANQADCgcICAABNQAECgcIEwACAAAAAA==.Hakine:BAAANQADCggIDAAAAA==.Halianubran:BAAANQAECgMIBAABNQAECgYIDAAOAM8HAA==.Halliday:BAAANQAECgcIEwAAAA==.Harraktas:BAAANQAECgQIBgAAAA==.Harrowhark:BAAANQAECgEIAQAAAA==.Harvestmoon:BAAANQADCgQIBAAAAA==.Haxxor:BAAANQADCggIEAAAAA==.',
He='Healiia:BAABNQAECoEZAAMXAAkJ+BMHFwD1AQAXAAcJFBIHFwD1AQABAAQJ3whSXwD1AAAAAA==.Hedalexa:BAAANQADCgUIBQAAAA==.Hellsîng:BAAANQAECgcIEwABNQAECgkJIAAMAOYZAA==.Hellà:BAAANQADCggIFwAAAA==.Hendo:BAAANQAECgIIAwAAAA==.Hepatitan:BAAANQADCgIIAgAAAA==.Hester:BAAANQADCgQIBgAAAA==.Hexecuted:BAAANQADCggIHAAAAA==.Heyyaits:BAABNQAECoEeAAIHAAkJrSEGCgB8AwAHAAkJrSEGCgB8AwAAAA==.',
Hi='Hikahi:BAAANQAECgQIBgAAAA==.',
Ho='Holdmyaggro:BAAANQAECgQICgAAAA==.Holdmyballz:BAAANQAECgYIEQAAAA==.Hollowlight:BAAANQAECgIIAgAAAA==.Hollyballz:BAAANQADCgYIBgAAAA==.Holyberry:BAABNQAECoEgAAMTAAcJNBk8JgA9AgATAAcJNBk8JgA9AgAGAAEJkAvW5AA4AAAAAA==.Holè:BAAANQAECgUIDQABNQAECgYIDAACAAAAAA==.Hornigoat:BAAANQADCgcIBwAAAA==.Hotstreakqt:BAAANQADCggIEAAAAA==.Hotzug:BAAANQADCgIIAgAAAA==.Houyix:BAAANQAECgYIDQAAAA==.Howdowhodo:BAAANQADCgUIDgAAAA==.',
Hr='Hreeza:BAAANQAECgEIAQAAAA==.',
Hu='Humabon:BAAANQADCgUICwAAAA==.Huntingjohn:BAAANQADCgYIBwAAAA==.Huntssy:BAAANQAECgUIBwAAAA==.Huuag:BAAANQAECgIIAwAAAA==.',
Hy='Hynobear:BAAANQABCgQIBgAAAA==.Hypersleep:BAAANQAECgIIAwAAAA==.',
['Hì']='Hìkàrì:BAAANQADCgMIAwAAAA==.',
['Hö']='Hötnhòrdey:BAAANQAECgQIBwAAAA==.',
['Hø']='Høstile:BAAANQADCgQICAAAAA==.',
Id='Idtrappthat:BAAANQADCgYIBgAAAA==.',
Ii='Ii:BAAANQAECgQIBAAAAA==.Iisildur:BAABNQAECoEbAAIYAAcJVRB2BwCRAQAYAAcJVRB2BwCRAQAAAA==.',
Il='Ilse:BAAANQADCgUIBQAAAA==.',
Im='Imaginative:BAABNQAECoEdAAIJAAkJWx66BAAYAwAJAAkJWx66BAAYAwAAAA==.Imcooked:BAABNQAECoEeAAIVAAkJ0yHUEQBeAwAVAAkJ0yHUEQBeAwAAAA==.Imfiredupp:BAAANQAECggIAQAAAA==.Imladrisse:BAAANQAECgQIBAAAAA==.',
In='Inamoonstar:BAAANQADCgUIBQAAAA==.Inkmouse:BAAANQAECgUICAAAAA==.',
Ir='Irispearl:BAAANQADCgQICAAAAA==.Ironfistt:BAABNQAECoEbAAIVAAkJViXgBAC4AwAVAAkJViXgBAC4AwAAAA==.',
Is='Isolde:BAAANQADCgYIDwAAAA==.',
Iv='Ivar:BAAANQAECgYIDQAAAA==.',
Ja='Jacksmash:BAAANQAECgQIBAAAAA==.Jaganoto:BAAANQADCggICAAAAA==.Jaideep:BAAANQAECgQICAAAAA==.Jalarin:BAAANQADCgMIBgAAAA==.Jaminmyclam:BAAANQAECgEIAgAAAA==.Jamitydk:BAEANQAECgUICwAAAA==.Jarnzarn:BAAANQADCggIEAAAAA==.Jarviltinn:BAAANQAECgcIEwAAAA==.',
Je='Jelia:BAAANQAECgcIEwAAAA==.Jelyah:BAAANQAECgQIBgABNQAECgcIEwACAAAAAA==.Jerô:BAAANQAECgIIAgAAAA==.',
Jf='Jf:BAAANQADCgMIBAAAAA==.',
Jh='Jhorlith:BAAANQADCggIDgAAAA==.',
Jo='Jobbey:BAAANQAECgEIAQAAAA==.Jonkerstien:BAAANQAECgYIEAAAAA==.Jorgie:BAAANQAECgQIBAABNQAECgYICwACAAAAAA==.Joyous:BAAANQAECgIIAwAAAA==.',
Ju='Jubearz:BAAANQADCgcIBwAAAA==.Juelz:BAAANQADCgQIBQAAAA==.Jumbosausage:BAAANQAECgMIBQAAAA==.Jungchi:BAAANQADCggIHAAAAA==.Junior:BAAANQAECgcICgAAAA==.',
['Jú']='Júdgemental:BAAANQADCgYICgAAAA==.',
Ka='Kadinde:BAAANQADCgQIBAAAAA==.Kaeliela:BAAANQAECgEIAQAAAA==.Kahahn:BAAANQAECgQIBAAAAA==.Kakana:BAAANQADCgcIEgAAAA==.Kalantiaw:BAAANQADCgYICgAAAA==.Kamui:BAAANQAECgcIEAAAAA==.Kanamè:BAAANQAECgQIBQABNQAECgUICAACAAAAAA==.Kandrays:BAAANQADCgYICAABNQAECggIIgAVAAkfAA==.Kanfer:BAAANQAECgEIAQAAAA==.Kariala:BAAANQAECgYICwAAAA==.Karosanna:BAAANQAECgIIAgAAAA==.Kastager:BAAANQADCgcICgAAAA==.Katilaine:BAAANQADCggIEAAAAA==.Kayadrac:BAAANQAECgcIEgAAAA==.Kazimir:BAAANQADCgcICQAAAA==.',
Ke='Keksiq:BAAANQAECgYIEwAAAA==.Keshae:BAABNQAECoEeAAMRAAcJkgjbBwBvAQARAAcJkgjbBwBvAQAXAAIJSAM5PwBVAAAAAA==.',
Ki='Kidfork:BAAANQAECgQIDQAAAA==.Killasham:BAAANQAECgQIBgAAAA==.Killika:BAAANQAECgQIBAABNQAECgcIEQACAAAAAA==.Kinndred:BAABNQAECoEcAAIZAAYJkw21JwBmAQAZAAYJkw21JwBmAQAAAA==.Kintolina:BAAANQADCgQIBgAAAA==.Kiralia:BAABNQAECoElAAISAAcJ0xIYNADsAQASAAcJ0xIYNADsAQAAAA==.Kirigolmer:BAAANQADCggIHAAAAA==.',
Kn='Kngleonidas:BAAANQAECgQICAAAAA==.',
Ko='Koder:BAAANQAECgIIAgAAAA==.Kokoy:BAAANQAECgcIEgAAAA==.Kouchin:BAAANQADCgIIAgAAAA==.Koutomba:BAAANQADCgEIAQAAAA==.',
Kr='Krackd:BAAANQADCggICQAAAA==.Kraelyk:BAAANQAECgEIAQAAAA==.Krash:BAAANQAECgIIAgAAAA==.Krazan:BAAANQAECgMIBgAAAA==.Krunkisdead:BAAANQADCgIIAgAAAA==.Krygore:BAAANQAECgQIBgAAAA==.',
Ku='Kunali:BAAANQAECgEIAQAAAA==.Kunehoboy:BAAANQADCggIEAAAAA==.Kungfufeet:BAAANQADCgUIDQAAAA==.Kurtcobang:BAAANQAECgUIBgAAAA==.Kushie:BAAANQAECgQIBwAAAA==.',
Kx='Kxngchrxs:BAAANQADCgMIAwAAAA==.',
['Ká']='Kál:BAAANQAECgQIBwAAAA==.',
['Kø']='Kørndawg:BAAANQADCgcIGwAAAA==.',
La='Lagior:BAEANQAECgQICgAAAA==.Laikaboss:BAAANQADCgQIBAAAAA==.Lakandula:BAAANQADCgQIBwAAAA==.Lasind:BAAANQADCggIEAAAAA==.Lawu:BAAANQAECgcIEwAAAA==.Laytonfrost:BAAANQAECgEIAgABNQAECgQICgACAAAAAA==.',
Le='Learrit:BAAANQAECgUICwAAAA==.Lecorpse:BAAANQAECgEIAQAAAA==.Lemmìwìnks:BAAANQADCgcIDQABNQABCgQIBQACAAAAAA==.Lendis:BAAANQADCgIIAgAAAA==.Leviathran:BAAANQAECgEIAQAAAA==.',
Li='Librawitch:BAAANQADCgQIBQAAAA==.Lick:BAAANQADCgcIBwABNQAECgUICwACAAAAAA==.Lifaène:BAAANQADCgYIDAAAAA==.Lightarcc:BAAANQAECgQIBQAAAA==.Lightklobe:BAAANQAECggIAwAAAA==.Lihan:BAAANQADCggIHAAAAA==.Lilcarabine:BAAANQADCggIDAABNQAECgYICgACAAAAAA==.Lilindrena:BAAANQADCgYIDwAAAA==.Lilmentyb:BAABNQAECoEYAAIKAAcJ5w3TMACiAQAKAAcJ5w3TMACiAQAAAA==.Lilmis:BAAANQAECgQIBgAAAA==.Liorawr:BAAANQAECgIIAgAAAA==.Lipids:BAAANQADCgcIGAAAAA==.Lissuin:BAAANQAECgQICAAAAA==.',
Ll='Llandrei:BAAANQADCgcIEgAAAA==.',
Lo='Locnár:BAAANQAECgUICgAAAA==.Loeth:BAAANQAECgIIAQAAAA==.Lollobionda:BAAANQAECgMIBAAAAA==.Loono:BAAANQAECgQIBAAAAA==.Lorathiel:BAAANQADCgUIBQAAAA==.',
Lu='Luffytoe:BAAANQADCgMIAwABNQAECgkJGgASAJMgAA==.Lugunar:BAEANQADCgcIBwABNQAECgQICgACAAAAAA==.Lulingqï:BAAANQADCggIFQAAAA==.Lululapoon:BAAANQADCgYICQAAAA==.Luminei:BAAANQAECgUICAAAAA==.Lunakiss:BAAANQAECgEIAQAAAA==.Lutz:BAAANQAECgIIAwAAAA==.',
Ly='Lynestra:BAAANQAECgcIDAAAAA==.Lynmei:BAAANQADCgcIDwAAAA==.Lyrisa:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Lyth:BAAANQADCgIIAgAAAA==.Lythor:BAAANQAECgQICQAAAA==.',
Ma='Mackyla:BAAANQAECgUICAAAAA==.Macáronì:BAAANQADCgIIAgAAAA==.Mafdett:BAAANQAECgIIAgAAAA==.Mafilrion:BAABNQAECoEXAAIQAAkJTx+2CAA+AwAQAAkJTx+2CAA+AwAAAA==.Magicae:BAEANQAECgYIDwABNQADCgMIAwACAAAAAA==.Magiia:BAAANQADCgUIBQABNQAECgkJGQAXAPgTAA==.Magnestra:BAAANQADCgMIAwAAAA==.Manicmonk:BAAANQADCgUIBQAAAA==.Mantova:BAAANQAECgQICQAAAA==.Masholy:BAAANQADCggICAABNQAECgcIDAACAAAAAA==.Matt:BAAANQAECgQIBgAAAA==.Matthxw:BAAANQAECggIDwAAAA==.Mayomonk:BAAANQADCgMIAwAAAA==.Mayzh:BAAANQAECgIIAwAAAA==.',
Mc='Mcbain:BAAANQAECgIIAgAAAA==.',
Md='Mdma:BAAANQADCggIDgAAAA==.',
Me='Melahna:BAAANQAECgYIEwAAAA==.Melisand:BAAANQAECggIBwAAAA==.Melwyn:BAAANQAECgIIAgAAAA==.',
Mg='Mgunit:BAAANQAECgQIBgAAAA==.',
Mi='Mikotö:BAAANQAECgEIAQABNQAECgUIBwACAAAAAA==.Milkyjoe:BAAANQAECgcIEQAAAA==.Milkymaid:BAAANQADCggICAABNQAECgcIEwACAAAAAA==.Milkysprayed:BAAANQAECgcIEwAAAA==.Mistajeeves:BAAANQAECgEIAQAAAA==.Mistweaved:BAAANQADCgQIBAAAAA==.Mithras:BAAANQADCggIDAAAAA==.Mithrasxox:BAAANQADCgEIAQABNQADCggIDAACAAAAAA==.',
Mo='Mochinator:BAAANQAECgYIDAAAAA==.Modigularna:BAAANQADCgYICAAAAA==.Mojojojo:BAAANQADCgUIBQABNQAECgMIBQACAAAAAA==.Mollydooker:BAAANQAECgQICAAAAA==.Monkess:BAAANQADCgIIAgAAAA==.Monkeymagick:BAAANQAECgIIAwAAAA==.Monklips:BAAANQAECgIIAgAAAA==.Mookeeper:BAAANQADCggIEAAAAA==.Morbidfetus:BAAANQADCgIIAgAAAA==.Mortassus:BAAANQADCgMIAwABNQAECgIIAgACAAAAAA==.Mortelunes:BAAANQADCgMIAwAAAA==.Mortira:BAAANQAECgUIDwAAAA==.Morzierz:BAAANQAECgQIBgAAAA==.Mottie:BAAANQADCgQIBAABNQADCgYICgACAAAAAA==.Mouldybum:BAAANQAECgYIBgAAAA==.Mozrael:BAAANQAECgEIAQAAAA==.',
Mu='Muaddib:BAAANQAECgEIAQABNQAECgYIDAAOAM8HAA==.Mumimilkies:BAAANQADCggIEAABNQAECgQICwACAAAAAA==.Mummadudu:BAAANQADCgUIBgAAAA==.Murkroz:BAAANQAECgYIDgAAAA==.',
My='Mycelia:BAAANQADCgQIBAAAAA==.Mymistyboo:BAAANQADCgcIBwAAAA==.Myrkvitill:BAAANQADCgYICwABNQAECgIIAwACAAAAAA==.Mystfyre:BAAANQADCggIEAAAAA==.',
['Më']='Mëphistò:BAAANQAECgYICgAAAA==.',
['Mò']='Mòònshine:BAAANQAECgQIBQABNQABCgQIBQACAAAAAA==.',
Na='Naeirm:BAAANQADCgUIBQAAAA==.Naissa:BAAANQADCgMIAwAAAA==.Namewaståken:BAAANQADCggIDAAAAA==.Nasdarath:BAAANQAECgEIAQAAAA==.Nasha:BAAANQAECgEIAQABNQAECgUICAACAAAAAA==.Nato:BAAANQAECgYIEAAAAA==.Nattiee:BAAANQAECgYIDwAAAA==.Naturefire:BAAANQABCgUIBwAAAA==.Navimie:BAEANQAECgQIBgAAAA==.',
Ne='Neff:BAAANQAECgEIAQAAAA==.Negus:BAAANQAECgYIDAAAAA==.Nelphey:BAAANQAECgQIBgAAAA==.Nephamar:BAAANQAECgEIAQAAAA==.',
Nh='Nhael:BAAANQAECgIIAwAAAA==.',
Ni='Nialdo:BAAANQAECgUICgAAAA==.Nickwindfury:BAAANQAECgUIDAAAAA==.Nightfarer:BAAANQAECgMIAwABNQAECgYICwACAAAAAA==.Nightshift:BAAANQAECgEIAQAAAA==.Nikko:BAAANQADCgMIAwAAAA==.Niklasmunn:BAAANQAECgQIBAABNQAECgUIDAACAAAAAA==.Nikno:BAAANQAECgQICgAAAA==.Nimaara:BAAANQADCgIIAgAAAA==.Ningal:BAAANQADCggIBwAAAA==.Nips:BAAANQAFFAEIAQAAAA==.Nipsymcgeé:BAAANQAECgEIAQAAAA==.Nitegorh:BAAANQADCgEIAQAAAA==.Nixea:BAAANQADCgQIBwAAAA==.',
No='Nogin:BAAANQADCgYIBwAAAA==.Nomby:BAABNQAECoEYAAIaAAgJCiT/AQBKAwAaAAgJCiT/AQBKAwAAAA==.Noperope:BAAANQAECgEIAQAAAA==.Norinari:BAAANQAECgEIAQABNQAECgMIBQACAAAAAA==.Nostradamos:BAAANQADCgEIAQAAAA==.Novnaholycow:BAAANQADCgYICAAAAA==.Noyou:BAAANQAECgQICQAAAA==.',
['Ná']='Námewastaken:BAAANQADCgYIBgAAAA==.',
['Nè']='Nèos:BAAANQAECgYICAAAAA==.',
['Ní']='Níhilus:BAAANQAECgEIAQAAAA==.',
['Nô']='Nôx:BAAANQAECgMIAwAAAA==.',
['Nÿ']='Nÿmber:BAAANQADCggIFgAAAA==.',
Ob='Obake:BAAANQAECgIIAgABNQAECgUIDAACAAAAAA==.Obamalives:BAAANQAECgcIEAAAAA==.Obsolve:BAAANQAECgUICAAAAA==.',
Ol='Olddrekky:BAAANQAECgYICQAAAA==.Oldegregg:BAAANQAECgcICQABNQAFFAEIAQACAAAAAA==.Oldtimér:BAAANQADCgYIEwABNQAECgQIBwACAAAAAA==.',
On='Onikage:BAAANQAECgcIEwAAAA==.Onlyfrends:BAAANQAECgQIBQAAAA==.',
Oo='Oolanna:BAAANQADCgcIBwAAAA==.Ooragnak:BAAANQAECgIIAgAAAA==.',
Or='Orb:BAAANQADCggIDgABNQAECgUIBgACAAAAAA==.Orobos:BAAANQAECggIBgAAAA==.',
Ot='Otai:BAAANQABCgYIBAAAAA==.Othentik:BAAANQAECgYIBwAAAA==.Otl:BAAANQAECgIIAgAAAA==.',
Ov='Overt:BAAANQAECgYIDQABNQAFFAQICAAKAMgTAA==.',
Ox='Ox:BAAANQADCgYIBgAAAA==.',
Pa='Pakaluta:BAAANQADCgIIAgAAAA==.Palaboodledo:BAABNQAECoEYAAIbAAcJzR6zCABwAgAbAAcJzR6zCABwAgAAAA==.Palarsynimz:BAEANQADCggIEAABNQAECgYIIQACAAAAAA==.Pallyative:BAAANQAECgEIAQAAAA==.Palomar:BAAANQAECgIIAwAAAA==.Pancake:BAAANQAECgQIBgAAAA==.Para:BAAANQAECgYIEwAAAA==.Pavlovaa:BAAANQAECgQIBgAAAA==.',
Pe='Peepeedemon:BAABNQAECoEUAAQcAAcJjRSrGQAXAgAcAAcJjRSrGQAXAgAYAAIJzgYmFQBKAAAZAAEJGwQZUgAsAAAAAA==.Peleiades:BAAANQAECggIEQAAAA==.Petitenova:BAAANQAECgEIAgAAAA==.Pewbute:BAAANQADCgEIAQABNQADCgUIBQACAAAAAA==.Pewpews:BAAANQAECgQICgAAAA==.',
Ph='Phetusdeletu:BAAANQAECgQIBgAAAA==.',
Pi='Pirrin:BAAANQAECgYIEwAAAA==.',
Pk='Pk:BAAANQAFFAMIBAAAAA==.Pks:BAAANQAFFAEIAgABNQAFFAMIBAACAAAAAA==.',
Pn='Pnau:BAAANQAECgUIBwAAAA==.',
Po='Pokepoke:BAAANQADCgYIBgAAAA==.Pownrz:BAAANQAFFAEIAQAAAA==.Pownzz:BAAANQAECgMIBAABNQAFFAEIAQACAAAAAA==.',
Pr='Pranto:BAAANQADCggIEAAAAA==.Privilege:BAAANQAECgMIAwAAAA==.',
Ps='Psycthyr:BAAANQADCgcIFwABNQAECgMICQACAAAAAA==.',
Pu='Purrpleelff:BAAANQAECgYIDAAAAA==.',
Pw='Pwrwrdboner:BAAANQADCggIFQABNQADCggIDAACAAAAAA==.',
Py='Pyrande:BAAANQADCgUICgABNQAECgIIAgACAAAAAA==.Pyrhic:BAAANQADCgMIAwAAAA==.Pyrobee:BAAANQADCgQIBAABNQADCggICAACAAAAAA==.',
['Pä']='Pändörä:BAAANQADCgcICwABNQAECgEIAQACAAAAAA==.',
Qa='Qasqiri:BAAANQAECgMIBgAAAA==.',
Qu='Quack:BAAANQAECgIIAwAAAA==.Queeshi:BAAANQADCgYIDgAAAA==.',
['Qà']='Qài:BAAANQADCgEIAQAAAA==.',
Ra='Ragilas:BAAANQAECgIIAQABNQAECgkJHAAVAC8fAA==.Ragileus:BAAANQADCgIIAgABNQAECgkJHAAVAC8fAA==.Rahj:BAAANQAECgMIAwAAAA==.Rainbowbash:BAAANQADCgMIBgAAAA==.Rainz:BAAANQAECgUICwAAAA==.Rambro:BAAANQAECgYIDAABNQAECgcIEQACAAAAAA==.Ranfin:BAAANQAECgYIEAAAAA==.Raqzel:BAAANQADCgEIAQAAAA==.Rare:BAAANQAECgMIBAAAAA==.Rarox:BAAANQADCgIIAgAAAA==.Ravinstep:BAABNQAECoEWAAITAAkJQgxdKgAlAgATAAkJQgxdKgAlAgAAAA==.Rawkalot:BAAANQAECgYIDQABNQAECgcIEQACAAAAAA==.Razs:BAAANQAECgIIAgAAAA==.Razzles:BAAANQAECgMICAABNQAECgYIGgALAOMbAA==.',
Re='Redpal:BAABNQAECoE0AAIGAAkJhyCkDwAmAwAGAAkJhyCkDwAmAwAAAA==.Reduvia:BAAANQAECgQIBQAAAA==.Reekin:BAAANQAECgQIBAABNQAECgIIAgACAAAAAA==.Regí:BAAANQADCggIDgAAAA==.Rendover:BAAANQADCgUICAAAAA==.Revyfox:BAAANQAECgEIAgAAAA==.',
Rh='Rheagz:BAAANQABCgQIBwAAAA==.Rhyseyj:BAAANQADCggIDgAAAA==.',
Ri='Rielta:BAAANQAECgIIAgAAAA==.Rightround:BAAANQADCgcIBwAAAA==.Rikthewizard:BAAANQADCgQIBQAAAA==.Rimrap:BAAANQAECgEIAQAAAA==.Rimurlzul:BAAANQADCgIIAgABNQAECgQICAACAAAAAA==.',
Ro='Robapaladin:BAAANQADCggICwAAAA==.Robbington:BAAANQADCgcIGAAAAA==.Rocketts:BAAANQADCggIEAAAAA==.Rokket:BAAANQAECgQICAAAAA==.',
Ru='Ruthia:BAAANQAECgUICwAAAA==.Ruumn:BAAANQAECgEIAQAAAA==.',
Ry='Rylaras:BAAANQAECgQIBAAAAA==.Ryogen:BAAANQAECgIIAwAAAA==.',
['Rê']='Rêvy:BAAANQAECgUIDQAAAA==.',
Sa='Sabretoothed:BAAANQAECgIIAgAAAA==.Saifere:BAAANQAECgcIDgAAAA==.Saiphere:BAAANQADCgYIBgABNQAECgcIDgACAAAAAA==.Sajyah:BAAANQAECgYIBgABNQAECgcIEQACAAAAAA==.Samanas:BAABNQAECoEWAAIUAAkJviKFBwA/AwAUAAkJviKFBwA/AwABNQAECgkJHwAJAP0jAA==.Sambali:BAAANQADCggIFQAAAA==.Samgamgee:BAAANQADCgYICwAAAA==.Samonki:BAABNQAECoEcAAIdAAkJBiMFAgBmAwAdAAkJBiMFAgBmAwAAAA==.Samotem:BAAANQAECgMIBAABNQAECgkJHAAdAAYjAA==.Sanctify:BAAANQAECgEIAQAAAA==.Santera:BAAANQAECgIIAwAAAA==.Saphìra:BAAANQABCgQIBQAAAA==.Saridana:BAAANQADCgQIBgAAAA==.Satire:BAAANQAECgEIAQAAAA==.Savriel:BAAANQAECgYIEwAAAA==.',
Sc='Schnoogans:BAAANQAECgYIDQAAAA==.Scottieboi:BAABNQAECoEiAAIVAAgJCR/vKwDhAgAVAAgJCR/vKwDhAgAAAA==.Scratchies:BAAANQAECgcIDgAAAA==.Screamdemons:BAAANQADCggIFgAAAA==.Scyadin:BAABNQAECoEYAAITAAkJIxESGgCPAgATAAkJIxESGgCPAgAAAA==.Scyler:BAABNQAECoEfAAIUAAkJmyK2BABsAwAUAAkJmyK2BABsAwAAAA==.',
Se='Seffyre:BAAANQAECgUICAAAAA==.Seilyre:BAABNQAECoEWAAMUAAcJlxWQTwBrAQAUAAYJcROQTwBrAQASAAEJAxeDrABDAAAAAA==.Sekuta:BAABNQAECoEcAAMIAAkJRyBnBQADAwAIAAgJyCBnBQADAwAeAAMJMxe+MADfAAAAAA==.Seltic:BAAANQAECgIIAwAAAA==.Senessara:BAAANQAECgQIBAAAAA==.Senjougahara:BAAANQAECgEIAgAAAA==.Seregios:BAAANQAECgYICgAAAA==.Sevrus:BAAANQAECgQIBgAAAA==.Seyn:BAAANQADCggIKwAAAA==.',
Sg='Sgtsquat:BAAANQAECgYIDwAAAA==.',
Sh='Shabria:BAAANQAECgQICwAAAA==.Shadowguy:BAAANQAECgMIAgAAAA==.Shadowthief:BAABNQAECoElAAIBAAcJEBVCLwDrAQABAAcJEBVCLwDrAQAAAA==.Shaetore:BAAANQAECggIEwAAAA==.Shagbark:BAAANQAECgUICQAAAA==.Shambuu:BAABNQAECoEbAAMUAAgJihx7FACzAgAUAAgJihx7FACzAgASAAIJGhofkwCNAAAAAA==.Shamclicked:BAAANQADCggICAABNQAECgcIEQACAAAAAA==.Shammytammy:BAAANQADCggIHQAAAA==.Sharmtor:BAAANQAECgcIEwAAAA==.Sharzam:BAAANQADCgMIAwAAAA==.Shauthra:BAAANQADCgYIEwAAAA==.Shazamza:BAAANQADCgUIBwAAAA==.Shazzles:BAAANQADCgUICgABNQAECgYIGgALAOMbAA==.Sheldelphine:BAAANQAECgUICgAAAA==.Shellemental:BAAANQADCgYIBgABNQAECgUICgACAAAAAA==.Shellstalker:BAAANQADCgEIAQABNQAECgUICgACAAAAAA==.Shenhua:BAAANQAECgUICgAAAA==.Sherber:BAAANQADCgYIBgABNQADCgYIBgACAAAAAA==.Shin:BAAANQAECgcIEwAAAA==.Shiné:BAAANQAECgEIAQAAAA==.Shoccymilk:BAAANQADCggIEQAAAA==.Shoop:BAAANQAECgEIAQAAAA==.Shyftzilla:BAAANQADCgIIAgAAAA==.Shåmanigans:BAAANQAECgQICgAAAA==.',
Si='Siasham:BAAANQAECgMIAwABNQAECgcIDgACAAAAAA==.Sidis:BAAANQAECgYIDAABNQAECgYIDAACAAAAAA==.Sifer:BAAANQADCgIIAgABNQAECgcIDgACAAAAAA==.Sindrawrei:BAAANQADCgQIBAAAAA==.Sixxpal:BAABNQAECoEdAAITAAcJGhc8LwAIAgATAAcJGhc8LwAIAgAAAA==.',
Sk='Skanktank:BAABNQAECoEcAAIbAAgJ9xVTDAAVAgAbAAgJ9xVTDAAVAgAAAA==.Skankvoker:BAAANQAECgQIBgABNQAECggIHAAbAPcVAA==.Skarrovectis:BAAANQADCgEIAQAAAA==.Skathlok:BAAANQAECgYIEwAAAA==.Skest:BAAANQAECgQICQAAAA==.Skidstains:BAAANQAECgIIAgAAAA==.Skindeep:BAAANQAECgQIBQAAAA==.Skragrott:BAABNQAECoEYAAIXAAgJeB97CAAHAwAXAAgJeB97CAAHAwAAAA==.Skullçrusher:BAAANQAECgIIAwAAAA==.Skybomb:BAAANQADCggIEAAAAA==.Skúmi:BAAANQADCgQIBAABNQAECgIIAwACAAAAAA==.',
Sl='Slaphealz:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Slashycrisps:BAAANQAECgQIBQAAAA==.Slobfather:BAAANQAECgQIBAAAAA==.',
Sm='Smacknzug:BAAANQAECgEIAQAAAA==.Smashmedaddy:BAAANQAECgYIDwAAAA==.',
Sn='Snapp:BAAANQAECgEIAQAAAA==.Sneaksham:BAAANQAECgcIEgAAAA==.Sneakswar:BAAANQAECgQIEgAAAA==.Snowbind:BAAANQAECgYIBgAAAA==.',
So='Sofarogue:BAAANQAECgYIDAAAAA==.Solitiaire:BAAANQADCggICAAAAA==.Solvy:BAAANQAECgEIAQAAAA==.Sonara:BAAANQAECggICQAAAA==.Soondead:BAAANQAECgUICwAAAA==.Soulmonk:BAAANQADCgcIDwAAAA==.',
Sp='Sparkies:BAAANQAECgUICwAAAA==.Spieluhr:BAAANQAECgMIBQAAAA==.Spiritwhislr:BAAANQAECgIIAwAAAA==.Splatzor:BAAANQAECgQIBgAAAA==.',
St='Stabilitas:BAABNQAECoElAAIfAAcJtRHgFgC/AQAfAAcJtRHgFgC/AQAAAA==.Stalgic:BAAANQAECgEIAQABNQAECgYIBwACAAAAAA==.Stalsurge:BAAANQAECgYIBwAAAA==.Starborne:BAABNQAECoEnAAIZAAgJrx1VDwCYAgAZAAgJrx1VDwCYAgAAAA==.Sthöly:BAAANQAECgIIAgABNQAECgcIDAACAAAAAA==.Stocky:BAAANQADCgUIBQABNQAECggIGwAbANIRAA==.Stockyx:BAABNQAECoEbAAIbAAgJ0hEeEADHAQAbAAgJ0hEeEADHAQAAAA==.Strat:BAAANQADCggIDgAAAA==.',
Su='Sudamon:BAAANQADCgEIAQAAAA==.Summoninc:BAABNQAECoEdAAILAAgJLBESMgAOAgALAAgJLBESMgAOAgAAAA==.Sunila:BAAANQAECgcIEgAAAA==.Suntigerr:BAAANQAECgUICwAAAA==.Superhanz:BAAANQADCgYIBgAAAA==.Suyasha:BAAANQAECgYIDAAAAA==.',
Sw='Swalala:BAAANQADCgIIAgAAAA==.Sweetmemeboy:BAAANQAECgYICwAAAA==.Swipes:BAAANQADCgYIBgAAAA==.',
Sy='Sylvias:BAAANQAECgQIBwAAAA==.Syreandrena:BAAANQAECgYIEgAAAA==.Syse:BAAANQADCgYIBgAAAA==.Syvan:BAAANQAECgQICAABNQAECgYIEAACAAAAAA==.',
['Sã']='Sãmael:BAABNQAECoElAAIYAAcJyR1MAwBmAgAYAAcJyR1MAwBmAgAAAA==.',
['Sé']='Séhkmet:BAAANQADCggIFgAAAA==.',
['Só']='Sól:BAAANQADCggICgAAAA==.',
Ta='Tabbandit:BAAANQAECgQIBgAAAA==.Taffatups:BAAANQADCgYIDgAAAA==.Talena:BAAANQAECgMIAwABNQAECgkJFwAZAOciAA==.Talkingtree:BAAANQADCgcIBwAAAA==.Tallysmeller:BAAANQAECgUICAAAAA==.Talorus:BAABNQAECoEXAAIZAAkJ5yJDAwCLAwAZAAkJ5yJDAwCLAwAAAA==.Tankox:BAAANQAECgEIAgAAAA==.Tanwahhlock:BAABNQAECoEYAAQLAAgJeRq3IwBbAgALAAcJIBu3IwBbAgAMAAQJNxbCIwAbAQAgAAEJnAeMGQBCAAAAAA==.Tarhata:BAAANQADCgYIDQAAAA==.Tarot:BAAANQAECgIIAwAAAA==.Tatantaca:BAABNQAECoEdAAIIAAcJMBPSEgAGAgAIAAcJMBPSEgAGAgAAAA==.',
Te='Teknoman:BAAANQAECgcICQAAAA==.Tena:BAAANQAECgMIAwAAAA==.Tenå:BAAANQAECgIIAgABNQAECgMIAwACAAAAAA==.Teranzil:BAAANQAECgUICAAAAA==.Terly:BAAANQAECgIIAwAAAA==.Terrafirma:BAAANQADCgcIBwABNQAECgIIAwACAAAAAA==.Teár:BAAANQADCgcIBwABNQAECgkJHAAUAJ8gAA==.Teär:BAABNQAECoEcAAIUAAkJnyCABwA/AwAUAAkJnyCABwA/AwAAAA==.',
Th='Thadd:BAAANQADCgMIAwAAAA==.Thalidomide:BAABNQAECoEYAAIVAAYJ5gsjrQBeAQAVAAYJ5gsjrQBeAQAAAA==.Thastir:BAAANQADCgYICwABNQAECgEIAQACAAAAAA==.Theavenger:BAAANQAECgQIBgAAAA==.Thedis:BAAANQADCgUIBgAAAA==.Thomus:BAAANQAECgYICwAAAA==.Thormuss:BAAANQADCgUICQABNQAFFAEIAQACAAAAAA==.Thundèrthigh:BAAANQADCgYIHgAAAA==.Thuxis:BAAANQAECgcIEwAAAA==.Thânãtös:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.',
Ti='Timmymage:BAAANQAECgYIBgAAAA==.Tishenya:BAAANQADCgYIBwAAAA==.',
To='Toezrmeanae:BAAANQAECgcIEwAAAA==.Tokot:BAABNQAECoEdAAMJAAcJcRfxEwDgAQAJAAcJcRfxEwDgAQAKAAEJXhK+bgA1AAAAAA==.Tolandrea:BAAANQADCgUIBQABNQADCggIDgACAAAAAA==.Tombstone:BAAANQAECgEIAQAAAA==.Tomsshaman:BAABNQAECoEYAAIUAAcJIhLcOgDCAQAUAAcJIhLcOgDCAQAAAA==.Toniqjin:BAAANQAECgQICAAAAA==.Toot:BAAANQADCgQIBAABNQAECgUIBgACAAAAAA==.Toowhiskay:BAABNQAECoEbAAMKAAcJnweMRQAPAQAKAAUJ0AiMRQAPAQAJAAUJowi6JAAGAQAAAA==.Toridin:BAAANQADCgYIBgAAAA==.Tormentess:BAABNQAECoEhAAIZAAcJnhCZHQDZAQAZAAcJnhCZHQDZAQAAAA==.',
Tr='Translatov:BAAANQADCggIDAAAAA==.Trashlok:BAAANQADCgIIAgAAAA==.Trinitylimit:BAAANQAECgQICgAAAA==.Tripletd:BAAANQADCgYIDAAAAA==.Tripo:BAAANQADCgEIAQAAAA==.Trippen:BAAANQAECgYIBgAAAA==.Trippy:BAAANQAECgUIBwAAAA==.Trixiest:BAAANQAECgEIAQAAAA==.Truuesham:BAAANQADCgMIAwAAAA==.',
Tu='Tulasham:BAAANQADCgIIAgABNQAECgUIBQACAAAAAA==.Tulathros:BAAANQAECgUIBQAAAA==.',
Tw='Twinkabell:BAAANQADCgEIAQAAAA==.',
Tx='Txci:BAAANQAECgYIDQAAAA==.',
Ty='Tylorän:BAAANQAECgEIAQAAAA==.',
['Tê']='Tên:BAAANQADCgMIAwABNQAECgMIAwACAAAAAA==.',
Uc='Uchi:BAAANQAECgcIEgAAAA==.Uchuyagi:BAAANQAECgcIEwAAAA==.',
Um='Umbrasanctum:BAEANQADCgMIAwAAAA==.',
Un='Unbjörn:BAAANQAECgEIAQAAAA==.Unc:BAAANQAECgQIBgAAAA==.Unholysneaks:BAAANQAECgEIAgAAAA==.',
Va='Valetudo:BAAANQAECgIIAwAAAA==.Valheru:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Vampiregirl:BAAANQABCgEIAQAAAA==.Vance:BAAANQAECgQICAAAAA==.Varayne:BAAANQADCgYIDAAAAA==.',
Ve='Veenus:BAAANQAECgQICAAAAA==.Veladoris:BAAANQAECgQIBwAAAA==.Velaryas:BAAANQADCgEIAQAAAA==.Velinoe:BAAANQAECgIIAwAAAA==.Velkorvasa:BAAANQADCgcIFAAAAA==.Velledara:BAAANQADCgYICgABNQAECgYIDAAOAM8HAA==.Velthuria:BAAANQAECgEIAQAAAA==.Velíne:BAAANQAECgYIBgAAAA==.Verdari:BAAANQAECgEIAQAAAA==.Verlene:BAAANQAECgQICAAAAA==.',
Vi='Vindicatar:BAAANQAECgUICwAAAA==.Vindicator:BAAANQAECgIIAwAAAA==.Virek:BAAANQAECgEIAQAAAA==.Vivarna:BAAANQADCgQIBwAAAA==.',
Vo='Voidtree:BAABNQAECoEbAAIJAAgJ+xsnDQBZAgAJAAgJ+xsnDQBZAgAAAA==.Voostab:BAAANQADCgMIAwAAAA==.Vortoxin:BAAANQAECgIIAgAAAA==.',
Vp='Vpallyonekey:BAAANQAECgQIBgAAAA==.',
Vu='Vulpelle:BAAANQADCggIEAAAAA==.Vuvuzela:BAAANQAECgEIAQAAAA==.',
Vv='Vvuvvu:BAAANQADCgYIBgAAAA==.',
Vy='Vyeagra:BAAANQAECgMICQAAAA==.',
['Ví']='Vírus:BAAANQADCgEIAQABNQAECgQICgACAAAAAA==.',
Wa='Walshy:BAABNQAECoEnAAIhAAgJzB3DEgChAgAhAAgJzB3DEgChAgAAAA==.Wantiwanti:BAAANQAECgcIEgAAAA==.Warrvx:BAAANQAECgQICAAAAA==.Wartor:BAAANQADCgYICAAAAA==.Wawilou:BAAANQADCgUIBQABNQAECgcIEwACAAAAAA==.Waxillium:BAAANQAECgIIAwAAAA==.',
We='Well:BAAANQAECgIIAwAAAA==.Wengor:BAAANQADCgYIBgAAAA==.Werglerps:BAABNQAECoEdAAMRAAkJfheYAgCDAgARAAgJahiYAgCDAgABAAgJAxEeLAD+AQAAAA==.',
Wh='Wholegrains:BAAANQAECgEIAgABNQAECgIIAwACAAAAAA==.Whytefall:BAAANQADCgUIBgAAAA==.Whytek:BAAANQAECgQICQAAAA==.Whytelust:BAAANQADCgcIGgAAAA==.Whyter:BAAANQADCgIIAgAAAA==.',
Wi='Windcier:BAAANQAECgUIAQABNQAECgYIDgACAAAAAA==.Windrider:BAAANQAECgUICwAAAA==.Wirtle:BAAANQAECgcIEwAAAA==.Wisefrog:BAAANQADCggIDgAAAA==.',
Wo='Worgdeeznuts:BAAANQADCgUIBQAAAA==.',
Wr='Wrathlon:BAAANQAECgYIDAAAAA==.',
Ws='Wsz:BAAANQADCggIDgAAAA==.',
Wu='Wunbee:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.',
Xa='Xandraevia:BAAANQADCgYIDwAAAA==.Xannar:BAAANQAECgQICQAAAA==.Xarmina:BAABNQAECoEfAAMJAAkJ/SMuAQCbAwAJAAkJ/SMuAQCbAwAKAAEJ3BmnaABKAAAAAA==.',
Xe='Xerron:BAAANQAECgIIAgAAAA==.',
Ye='Yeamn:BAAANQAECgIIAgABNQAECgkJFgATAEIMAA==.Yetzira:BAAANQADCgEIAQAAAA==.',
Yo='Yodashaman:BAABNQAECoEdAAIUAAcJHA6lRwCJAQAUAAcJHA6lRwCJAQAAAA==.',
Yr='Yrbane:BAAANQADCgYIDQAAAA==.',
Za='Zaifer:BAAANQADCgYICgABNQAECgcIDgACAAAAAA==.Zalanil:BAAANQADCgUIBQAAAA==.Zalayä:BAAANQADCgYIBgABNQAECgcIEwACAAAAAA==.Zaljan:BAACNQAFFIERAAIUAAcJCxweAADEAgAUAAcJCxweAADEAgA1AAQKgRkAAhQACQlWGVQVAKwCABQACQlWGVQVAKwCAAAA.Zavrall:BAAANQADCgQIBAAAAA==.Zavul:BAAANQAECgQIBgAAAA==.',
Ze='Zehphyzou:BAAANQAECgEIAQAAAA==.Zeldonn:BAAANQADCggICQAAAA==.Zemu:BAAANQADCggICAAAAA==.Zendaiya:BAAANQADCgYIBgAAAA==.Zeriera:BAAANQAECgIIBAABNQAECgYIEAACAAAAAA==.',
Zh='Zhànshi:BAAANQAECgQIBwAAAA==.',
Zi='Zidiuz:BAAANQAECgYICwAAAA==.Zippizap:BAAANQAECgUICwAAAA==.',
['Âl']='Âlîse:BAAANQAECgEIAQAAAA==.',
['Är']='Ärtorias:BAAANQABCgIIAgAAAA==.',
['Äx']='Äxel:BAAANQADCgMIAgAAAA==.',
['Év']='Évelyn:BAAANQAECgYICQAAAA==.',
['Ðe']='Ðed:BAAANQAECgIIAgAAAA==.',
['Öz']='Öz:BAAANQADCgYIBwAAAA==.',
['ßl']='ßluè:BAAANQAECgEIAQAAAA==.',
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
