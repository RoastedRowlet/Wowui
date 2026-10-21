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

local lookup = {'Paladin-Protection','Warrior-Arms','Priest-Holy','DemonHunter-Devourer','Druid-Restoration','Unknown-Unknown','Shaman-Restoration','Druid-Balance','Shaman-Elemental','Mage-Arcane','Monk-Windwalker','Rogue-Assassination','DemonHunter-Vengeance','Druid-Feral','Monk-Brewmaster','Paladin-Holy','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Mage-Frost','Monk-Mistweaver','DemonHunter-Havoc','Evoker-Augmentation','Paladin-Retribution','Hunter-Marksmanship','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Outlaw','Warrior-Protection','Priest-Shadow','Druid-Guardian','Evoker-Devastation','Mage-Fire','Priest-Discipline',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abysslicker:BAAANQADCggIFAAAAA==.',
Ac='Achooe:BAABNQAECn8eAAIBAAcK0QMdIACUAAABAAcK0QMdIACUAAAAAA==.',
Ad='Ado:BAAANQAECgYIDgAAAA==.Adversity:BAABNQAFFH8GAAICAAQKBRCzJQDTAAACAAQKBRCzJQDTAAAAAA==.',
Ae='Aegeus:BAAANQADCggICQAAAA==.Aenil:BAAANQADCgMIAwAAAA==.Aevintz:BAAANQAECgcICgAAAA==.',
Ai='Aiolii:BAAANQAECgUICwAAAA==.Aisling:BAAANQADCgQIBAAAAA==.',
Ak='Akiras:BAAANQABCgYIDAAAAA==.',
Al='Alcestis:BAAANQADCgIIAgAAAA==.Aldea:BAAANQAECgUIDwABNQAECgkJIAADAOoUAA==.Alyndrya:BAABNQAECn80AAIEAAoKuxDGBADNAQAEAAoKuxDGBADNAQAAAA==.',
Am='Amithralia:BAABNQAECn8lAAIFAAcKICGBBwDJAQAFAAcKICGBBwDJAQAAAA==.',
An='Anejo:BAAANQAECgQIBAAAAA==.Ankari:BAAANQADCgEIAQAAAA==.Ansdusk:BAAANQAECgIIAwABNQAECgUICwAGAAAAAA==.Anzarna:BAAANQAECgIIAgABNQAECgIIAgAGAAAAAA==.',
Ao='Aohikari:BAAANQAECgQICAABNQAFFAcIGgAHAIkYAA==.',
Ap='Aprigity:BAAANQAECgYICwAAAA==.',
Aq='Aquaten:BAAANQAECgUIEgAAAA==.',
Ar='Arashinigon:BAABNQAECn8aAAMFAAYKwhQ6QQAdAQAFAAUKqBE6QQAdAQAIAAYK3wyKIwDZAAAAAA==.Arceus:BAAANQAECgQIBQAAAA==.Arick:BAAANQAECgYIEwAAAA==.Ark:BAABNQAECn9JAAMHAAoK+SYSAAAFBAAHAAoK+SYSAAAFBAAJAAEKAADSGAFdAAAAAA==.',
At='Atanker:BAAANQADCgMIAwAAAA==.',
Au='Aunn:BAAANQAECgYICgAAAA==.Aureia:BAAANQAECggIDgAAAA==.Auriea:BAAANQAECgIIAgABNQAECggIDgAGAAAAAA==.',
Ax='Axon:BAABNQAECn8lAAIKAAcKLQqrWAAMAQAKAAcKLQqrWAAMAQAAAA==.',
Ba='Baaku:BAAANQAECgQIBgAAAA==.Baelhay:BAAANQAECgUIEgAAAA==.Ballard:BAAANQADCgMIAwAAAA==.Bashon:BAABNQAECn8vAAMHAAkK1BrmCAA0AgAHAAkK1BrmCAA0AgAJAAEKAAABWQEgAAAAAA==.Battlebot:BAAANQAECgUIDAAAAA==.',
Be='Beet:BAABNQAECn8oAAILAAgKFCGHAgAyAgALAAgKFCGHAgAyAgAAAA==.Belgaron:BAAANQAECgQIBAABNQAECgkJKgALALMUAA==.Belitha:BAABNQAECn8nAAIEAAoKwR68AgAeAgAEAAoKwR68AgAeAgAAAA==.Belmaris:BAABNQAECn8hAAIMAAcKexrEDQBXAQAMAAcKexrEDQBXAQAAAA==.Beriana:BAAANQAECgQIBAABNQAECgYICAAGAAAAAA==.Betëlgeuse:BAAANQADCgUICQAAAA==.',
Bi='Bigcupcakes:BAAANQAECgUICgAAAA==.Bigdruid:BAAANQAECgIIAwABNQAECgQIBAAGAAAAAA==.Bimbosuzi:BAAANQAECgUIDAAAAA==.Bingbing:BAAANQADCgUIBAAAAA==.Binghealing:BAAANQADCgEIAQAAAA==.',
Bl='Blasteyes:BAABNQAECn8gAAINAAgK1xiKCQBOAgANAAgK1xiKCQBOAgAAAA==.Bloomharvest:BAAANQADCgEIAQAAAA==.Bluegrass:BAABNQAECn8wAAIOAAoKoRrQAAB9AgAOAAoKoRrQAAB9AgAAAA==.',
Bo='Borc:BAAANQADCgcIGwAAAA==.Borik:BAABNQAECn8hAAIPAAYKNyE9AwB7AQAPAAYKNyE9AwB7AQAAAA==.Borknagar:BAAANQADCgcIFAAAAA==.',
Br='Brat:BAAANQADCgcIBwABNQAFFAcIHwADAOAeAA==.Brighteye:BAAANQAECgQIBAAAAA==.Brindis:BAAANQAECgMIBQAAAA==.Brisket:BAAANQADCggIGwAAAA==.Brutalicious:BAAANQADCgIIAgAAAA==.',
Bu='Bubblebut:BAABNQAECn8eAAIQAAgKsR6PDgDoAQAQAAgKsR6PDgDoAQAAAA==.Bubbs:BAAANQADCgQIBAABNQAECgoKKgALAAglAA==.Buckme:BAABNQAECn8pAAIRAAoK4RiyMwDRAgARAAoK4RiyMwDRAgAAAA==.Bulova:BAAANQAECgMIAwAAAA==.Bunnygirl:BAAANQAECgIIAgABNQAFFAcIFAASAKIiAA==.',
By='Byungsoon:BAAANQADCgQIBAAAAA==.',
['Bà']='Bàal:BAABNQAECn8hAAMTAAoKqxJjUwBcAgATAAoKqxJjUwBcAgASAAEKNxFMcwA7AAAAAA==.',
Ca='Caiphage:BAAANQADCgcIBwAAAA==.Caladelm:BAAANQAECgQICgAAAA==.Caralhan:BAAANQAECgUIDQAAAA==.Castelo:BAAANQADCggICgAAAA==.',
Ce='Cedra:BAABNQAECn87AAMKAAoK9yKQGAByAwAKAAoK4CKQGAByAwAUAAEKniZBMgBxAAAAAA==.Cegeo:BAABNQAECn8lAAISAAgKUxF+AgA+AQASAAgKUxF+AgA+AQAAAA==.Celari:BAAANQAECgEIAQAAAA==.Centric:BAAANQADCgcIBwAAAA==.',
Ch='Cheepdeeps:BAABNQAECn8uAAICAAkKNBpfCwALAgACAAkKNBpfCwALAgAAAA==.Chelea:BAAANQADCgcICgAAAA==.Chidora:BAAANQADCgcIBwAAAA==.Chocoworm:BAAANQADCgMIAgAAAA==.Chìpotle:BAAANQADCgYICgAAAA==.',
Ci='Ciennajewel:BAAANQAECgcIDgAAAA==.Cirdle:BAABNQAECn8gAAIRAAcK7xDfUgALAQARAAcK7xDfUgALAQAAAA==.',
Co='Cobalt:BAECNQAFFH8IAAITAAIKUBMsEgCNAAATAAIKUBMsEgCNAAA1AAQKfygAAhMACgrFG7wgAAEDABMACgrFG7wgAAEDAAE1AAUUBQgJABMAmRIA.Coolkid:BAAANQAECgMJBAAAAA==.Corntard:BAAANQADCggIGAAAAA==.',
Cr='Crazynlazy:BAABNQAECn8bAAIJAAcKcgOy0QDwAAAJAAcKcgOy0QDwAAAAAA==.Crucifixea:BAABNQAECn8cAAMQAAkKxxNNSABGAgAQAAgKoBVNSABGAgABAAkKQRKOLwBiAQABNQAFFAIICAADAMIcAA==.Cruxsader:BAAANQADCggIEAAAAA==.Crystyl:BAAANQAECgcIDgAAAA==.',
Ct='Ctesias:BAAANQADCgYIBgAAAA==.',
Cu='Cuddly:BAAANQAECgcIBwABNQAFFAQIBAAGAAAAAA==.Cute:BAAANQAECgYIBgABNQAFFAcIHwADAOAeAA==.',
Cy='Cymoril:BAABNQAECn8vAAICAAkK6xhSCwALAgACAAkK6xhSCwALAgAAAA==.',
Da='Daamass:BAAANQAECgIIAgAAAA==.Daddy:BAACNQAFFH8NAAIVAAUKlCWpAAASAgAVAAUKlCWpAAASAgA1AAQKf7AAAhUACgrtJgEAAJYEABUACgrtJgEAAJYEAAAA.Dagyrr:BAAANQADCgEIAQAAAA==.Dalman:BAAANQAECgQIBgAAAA==.Dalmin:BAAANQADCggICAAAAA==.Dalov:BAAANQAECggIDgAAAA==.Darkcarnival:BAABNQAECn8gAAITAAcKqBb0IgBiAQATAAcKqBb0IgBiAQAAAA==.Darkkill:BAAANQADCgMIAwABNQAECgoKKQAHAFQjAA==.Darthraider:BAAANQAECgUIBwAAAA==.Dasnotgood:BAAANQADCggIHwAAAA==.',
De='Deemon:BAABNQAECn8gAAMEAAgKEhdvEAAvAQAEAAcKtxhvEAAvAQAWAAIK2w46gAB2AAAAAA==.Delathatha:BAAANQADCgcICwAAAA==.Demiish:BAAANQADCgEIAQAAAA==.Demorjan:BAAANQADCggICAAAAA==.Denard:BAAANQADCgUIDQABNQADCggIGwAGAAAAAA==.Denarias:BAAANQADCgUJBQABNQAECgIIAgAGAAAAAA==.Denevien:BAAANQAECgYIDAAAAA==.Desdemona:BAAANQAECgcIDgAAAA==.Dethiaris:BAAANQAECgQICQAAAA==.',
Di='Diablojr:BAAANQAECgUIDAAAAA==.Dianimal:BAAANQAECgMIAwAAAA==.Distroya:BAAANQAECgQIBAAAAA==.',
Dk='Dkaiseremp:BAABNQAECn8WAAIXAAkKWAjtCwCcAQAXAAkKWAjtCwCcAQAAAA==.',
Do='Dobutsu:BAAANQAECggIDwAAAA==.Doomace:BAABNQAECn8yAAIYAAoKMRK8fwAqAgAYAAoKMRK8fwAqAgAAAA==.',
Dr='Draaka:BAAANQADCgYIDgAAAA==.Dragee:BAAANQAECgUIBQABNQAECggIIAAEABIXAA==.Dragon:BAAANQAECggICAAAAA==.Driftyshaman:BAAANQAECgIIAgAAAA==.Droopy:BAAANQAECgUIBQAAAA==.Dræghoule:BAAANQAECgcIDQAAAA==.',
Du='Durnik:BAABNQAECn8bAAMRAAcKPCEwGQC1AQARAAcKPCEwGQC1AQAZAAEKAADLkQAuAAABNQAECgkJKgALALMUAA==.',
Dw='Dworflundgrn:BAABNQAECn8YAAIaAAcKQwgxEAD+AAAaAAcKQwgxEAD+AAAAAA==.',
Dy='Dyamí:BAABNQAECn8hAAIKAAcKhRXoNABVAQAKAAcKhRXoNABVAQAAAA==.',
['Dá']='Dánte:BAAANQAECgYICQAAAA==.',
Eg='Eglosira:BAAANQADCgMIBQAAAA==.',
El='Elbuhero:BAABNQAECn8qAAMFAAgKJwezNgBmAQAFAAgKJwezNgBmAQAIAAUK+xX/XQBZAQAAAA==.Eldiablo:BAAANQAECgMIBwAAAA==.Electric:BAAANQAECgQIDQAAAA==.Elementstone:BAAANQAECgIIAgAAAA==.Elendish:BAAANQADCgIIAgAAAA==.Eleven:BAABNQAECn8nAAIKAAcK/QZweADNAAAKAAcK/QZweADNAAAAAA==.Eliasevo:BAAANQADCgcIBwABNQAECgoKKQAHAFQjAA==.Elrythe:BAABNQAECn89AAIRAAoKsxrVAwCjAgARAAoKsxrVAwCjAgAAAA==.',
Er='Eraleth:BAAANQAECgUICAABNQAECgoKJwAEAMEeAA==.',
Fa='Faben:BAAANQADCgUIBQAAAA==.Faced:BAAANQAECgUICwAAAA==.Fatalii:BAAANQAECgcIDQAAAA==.',
Fe='Felebash:BAAANQAECgUICgAAAA==.Felfireflux:BAAANQADCgYIDAAAAA==.Fellirane:BAAANQADCgUIBQAAAA==.',
Fi='Fistdaddy:BAAANQADCgYJDwAAAA==.',
Fl='Floofies:BAABNQAECn8vAAIaAAoKaSRXAQCtAwAaAAoKaSRXAQCtAwAAAA==.Floofthulu:BAAANQAECgEIAQABNQAECgoKLwAaAGkkAA==.Fluffalo:BAABNQAECn8oAAIJAAoKWCB5BgADAgAJAAoKWCB5BgADAgABNQAECgoKLwAaAGkkAA==.',
Fo='Foxypocket:BAAANQAECgUIDwAAAA==.',
Fr='Fredrickk:BAAANQAECgQICQAAAA==.',
Fu='Furcas:BAAANQAECgIIAgAAAA==.Furrglur:BAAANQAECgIIAgABNQAECgoKLwAaAGkkAA==.Furrylight:BAAANQAECgEIAQABNQAECgoKIgAHAE0gAA==.Furryphase:BAABNQAECn8iAAMHAAoKTSB6HgDxAgAHAAoKTSB6HgDxAgAJAAEKAACcVwEhAAAAAA==.Fuzzington:BAAANQAECgcICwABNQAECgoKLwAaAGkkAA==.Fuzzydunlop:BAAANQADCgUIBgAAAA==.',
Fz='Fzoul:BAAANQADCgYIBgAAAA==.',
Ga='Gaith:BAAANQAECgYIBgAAAA==.Galnier:BAAANQAECgYICwAAAA==.Gandoomi:BAAANQABCgIIAgAAAA==.',
Gh='Ghosted:BAAANQAECgMIBQAAAA==.',
Gl='Glaur:BAABNQAECn8hAAIHAAgKMBNAcQC4AQAHAAgKMBNAcQC4AQAAAA==.',
Go='Goatjira:BAAANQAECgEIAQAAAA==.',
Gr='Grimgor:BAAANQAECgQIBAABNQAECgYIFQAbAFIeAA==.Gripisrdy:BAABNQAECn8aAAQcAAcKNx0yOgA6AgAcAAYKjyAyOgA6AgAbAAYKVBnWSgCPAQAdAAIK2w+lqACAAAAAAA==.',
Gu='Gunslingr:BAABNQAECn8pAAIeAAoKECDEAADMAQAeAAoKECDEAADMAQAAAA==.',
Gw='Gweetow:BAAANQAECgEIAQAAAA==.',
Gy='Gymsharklyfe:BAAANQAECggIBgAAAA==.',
Ha='Hairyjolene:BAAANQADCggIEgAAAA==.Handsome:BAABNQAECn8hAAMZAAoKzhviEgDLAgAZAAkKuRviEgDLAgARAAcK9hXMxwByAQABNQAFFAIICAADAMIcAA==.',
He='Headpats:BAAANQAFFAIIAgABNQAFFAQIBAAGAAAAAA==.Hearthisrdy:BAAANQAECgYIBgAAAA==.Helmshammer:BAAANQAECgYIBAAAAA==.Hexwhisper:BAAANQAECgQIBAAAAA==.Heycarlos:BAABNQAECn85AAMbAAkKdiKTBgB5AwAbAAkKdiKTBgB5AwAcAAIKrwfJzQBRAAAAAA==.',
Hi='Hikaripala:BAAANQADCgYIBgABNQAFFAcIGgAHAIkYAA==.Hikarishaman:BAACNQAFFH8aAAMHAAcKiRiZCgClAQAHAAUKDhaZCgClAQAJAAQKmhuMEgBGAQA1AAQKfykAAwkACgrOGiZPADsCAAkACQoYGSZPADsCAAcACQopHShPACgCAAAA.Hime:BAABNQAECn8dAAIYAAcKjgflegDUAAAYAAcKjgflegDUAAAAAA==.',
Ho='Holyblimblam:BAAANQAECgMIBwAAAA==.Honeypieheal:BAAANQAECgMIAwAAAA==.Horabad:BAAANQAECgIIAwAAAA==.Hosemachine:BAABNQAECn8WAAIcAAgKWhkLOgA7AgAcAAgKWhkLOgA7AgAAAA==.',
Hu='Hulque:BAAANQADCgYIBgAAAA==.Humper:BAAANQADCgEIAQAAAA==.',
['Hè']='Hèri:BAAANQAECgMIAwAAAA==.Hèrifire:BAAANQAECgUICAAAAA==.',
Ic='Icyshadow:BAAANQAECgUIEQAAAA==.',
Id='Idouna:BAAANQADCgEIAQAAAA==.',
Ih='Ihalo:BAAANQAECgYIEAAAAA==.',
Il='Illinesh:BAAANQADCgYICgAAAA==.',
Ir='Ironpaw:BAAANQAECgUJDAAAAA==.',
It='Ithildur:BAAANQADCgQIBAAAAA==.',
Ja='Jadde:BAAANQADCgYIBgAAAA==.Jadienne:BAAANQAECgQIDAAAAA==.Jameson:BAAANQAECgUIDAAAAA==.Jangewinde:BAAANQAECgQICAAAAA==.Jasmind:BAAANQAECgcIEQAAAA==.Jaywu:BAAANQADCggICAAAAA==.',
Ji='Jiwà:BAABNQAECn8tAAMHAAkKtRMuVgAPAgAHAAkKtRMuVgAPAgAJAAcKnwKexgAFAQAAAA==.',
Jo='Joshjb:BAAANQAECgIIAgAAAA==.Joss:BAAANQADCgIIAgAAAA==.',
Ka='Kaguro:BAABNQAECn8gAAIeAAkKsw1WCgDWAQAeAAkKsw1WCgDWAQAAAA==.Kahless:BAAANQADCgcIEQAAAA==.Kaibab:BAAANQADCgEIAQAAAA==.Kakwaa:BAAANQAECgIJAwAAAA==.Kalix:BAAANQABCgUICAAAAA==.Kaliyah:BAAANQAECgUIDgAAAA==.Kattrin:BAAANQADCgYIEAAAAA==.Kayleebear:BAAANQADCgQIBAAAAA==.',
Ke='Kerplaa:BAAANQADCgMIAwAAAA==.Keyadistor:BAABNQAECn8VAAQbAAYKUh7dPgDPAQAbAAYK6x3dPgDPAQAdAAEKkCP+sABpAAAcAAEKAACz5gAuAAAAAA==.',
Kh='Khazabrew:BAABNQAECn8tAAIPAAkKjR0TAQAhAgAPAAkKjR0TAQAhAgAAAA==.',
Ki='Kiamara:BAAANQAECgcIDgAAAA==.Kinderlin:BAABNQAECn8qAAIYAAoKfhKnKQCCAQAYAAoKfhKnKQCCAQAAAA==.Kirbun:BAABNQAECn8rAAIKAAkK+xyJZwCvAgAKAAkK+xyJZwCvAgAAAA==.Kizchaos:BAAANQAECgMIBAAAAA==.',
Ko='Komurash:BAABNQAECn8fAAMCAAkKiBHsOQAzAQACAAkKiBHsOQAzAQAfAAIKRgM8PABVAAAAAA==.Korstruck:BAAANQAECgUIBQAAAA==.Kotys:BAAANQADCgUIBQAAAA==.',
Kr='Kravvelocity:BAAANQABCggIBgAAAA==.',
Ku='Kungbrew:BAAANQAECgEIAQABNQAECgUIEQAGAAAAAA==.',
La='Lancaban:BAAANQADCggIHQAAAQ==.',
Le='Lethalarrow:BAABNQAECn8YAAIRAAgK8Ay/JwB7AQARAAgK8Ay/JwB7AQAAAA==.Lethalpally:BAAANQADCggICAAAAA==.Lewismr:BAAANQADCgUIDQABNQAECggKIgAYAD0UAA==.Lewisr:BAABNQAECn8iAAIYAAgKPRSbSAA0AQAYAAgKPRSbSAA0AQAAAA==.',
Li='Ligahoo:BAAANQADCggJDwAAAA==.Lilysweets:BAAANQADCgcICgAAAA==.',
Lo='Loralynn:BAAANQADCgQIBAABNQAECgoKOQAQAKAYAA==.Lorianne:BAAANQAECgUIBQABNQAECgoKOQAQAKAYAA==.Lorryanne:BAABNQAECn85AAMQAAoKoBgyCABCAgAQAAoKoBgyCABCAgAYAAUKQAaRlgCsAAAAAA==.',
Lu='Lucianas:BAAANQAECgYIDAAAAA==.Lunacat:BAAANQAECgQICQABNQADCgYJDwAGAAAAAA==.Luxdaddy:BAAANQAECgcICAABNQADCgYJDwAGAAAAAA==.',
Ly='Lysi:BAAANQAECgUICwAAAA==.',
Ma='Madaea:BAABNQAECn8oAAIVAAoKoRqGEgBUAgAVAAoKoRqGEgBUAgAAAA==.Madameuyen:BAAANQAECgEIAQAAAA==.Madlyn:BAAANQAECgQIBwAAAA==.Magepuppy:BAABNQAECn8cAAMKAAgK+hQ/ygDxAQAKAAcKTxU/ygDxAQAUAAEKTxM9QABEAAAAAA==.Makavali:BAAANQAECggIEQABNQAECgkJTwAQAAsTAA==.Makavalii:BAABNQAECn9PAAMQAAkKCxM/UAArAgAQAAkKCxM/UAArAgAYAAkK9xX3QABEAQAAAA==.Malanimus:BAAANQAECgQICAAAAA==.Malevola:BAAANQAECgEIAQAAAA==.Malholis:BAAANQAECgUICwAAAA==.Mandorallen:BAAANQAECgQIBAABNQAECgkJKgALALMUAA==.Matagi:BAABNQAECn8qAAIRAAkK6hPIEgDbAQARAAkK6hPIEgDbAQAAAA==.Mate:BAAANQADCgUIBQABNQADCggIGwAGAAAAAA==.',
Me='Meatloaf:BAAANQADCgQIBAAAAA==.Meeseks:BAABNQAECn8rAAIcAAkKmxhaDQB1AQAcAAkKmxhaDQB1AQAAAA==.Megabyte:BAAANQAECgQJBAAAAA==.Melbeast:BAAANQAECgcICAAAAA==.Melorea:BAAANQAECgEIAgAAAA==.Merdin:BAABNQAECn8YAAIKAAUKKgtZaQDqAAAKAAUKKgtZaQDqAAAAAA==.Methmartion:BAAANQAECgUIDwAAAA==.',
Mi='Mignon:BAAANQADCgYIBgABNQADCggIGwAGAAAAAA==.Milougheh:BAAANQAECggIAgAAAA==.Minós:BAAANQADCgUIBQAAAA==.Mish:BAAANQAECgQIBAAAAA==.Missiah:BAABNQAECn8gAAIBAAcKpQVLHQCnAAABAAcKpQVLHQCnAAAAAA==.',
Mo='Molfise:BAAANQADCgYIBQAAAA==.Monna:BAAANQABCgIIAgAAAA==.Moonfell:BAABNQAECn8jAAIDAAgK8RKeMwAxAQADAAgK8RKeMwAxAQAAAA==.Moonlilly:BAAANQAECgcIDgAAAA==.Mopp:BAAANQAECgQICgAAAA==.Morganthe:BAAANQADCggIEAAAAA==.Mornîngstar:BAAANQAECgYIDAAAAA==.',
Mx='Mxtemlen:BAAANQAECgQIBAABNQAECggIHAAQAHcSAA==.',
My='Mylilhunter:BAAANQAECgYIEQAAAA==.Myrtheli:BAAANQADCggICAABNQAECgkJIAADAOoUAA==.Mysticx:BAAANQAECggICAAAAA==.',
Na='Nachtelf:BAABNQAECn8zAAIRAAkKdBnIGAC3AQARAAkKdBnIGAC3AQAAAA==.Nagan:BAAANQAECgYIDAAAAA==.Natadawn:BAAANQADCgYIBgAAAA==.Natalone:BAABNQAECn8uAAIUAAkKHiX1AQBhAwAUAAkKHiX1AQBhAwAAAA==.Nathel:BAAANQAECgUIEQAAAA==.',
Ne='Nerisa:BAAANQADCgUIBQAAAA==.',
Ni='Nirra:BAAANQAECgIIAgAAAA==.',
No='Noctis:BAAANQAECgYICwAAAA==.Notoriginal:BAABNQAECn8eAAIcAAkKTQwyCQCiAQAcAAkKTQwyCQCiAQAAAA==.Novatron:BAAANQAECgUIEQAAAA==.',
Nu='Nuked:BAABNQAECn8UAAIKAAYKuxddAAGNAQAKAAYKuxddAAGNAQAAAA==.',
['Né']='Néith:BAAANQADCgQIBAAAAA==.',
Od='Odor:BAAANQAECgMIAwAAAA==.',
Og='Ograskygazer:BAAANQAECgUIDwAAAA==.',
Oi='Oieg:BAAANQABCgUIBAAAAA==.',
Om='Omee:BAABNQAECn8WAAMEAAcKfg3pDwAzAQAEAAcKfg3pDwAzAQAWAAEKAABPlwAuAAABNQAECgoKJwARADEcAA==.Omegaone:BAAANQADCgcIBwAAAA==.',
On='Oneil:BAAANQADCgMJAwAAAA==.Onlyshrimps:BAAANQAECgYIBgAAAA==.',
Or='Oralena:BAAANQAECgUIDwAAAA==.Orioncheats:BAABNQAECn8xAAMcAAkKGhbXBgDBAQAcAAkKGhbXBgDBAQAdAAEKAAA/vQBNAAAAAA==.',
Ow='Owo:BAAANQAECgEIAQAAAA==.',
Ox='Oxygën:BAABNQAECn8bAAIKAAgKzxIaHgCYAQAKAAgKzxIaHgCYAQAAAA==.',
Pa='Palomita:BAAANQADCgIIAgAAAA==.',
Pe='Ped:BAAANQAECgEIAQABNQAECgkJIAADAOoUAA==.Pedarias:BAABNQAECn8gAAMDAAkK6hRTaQDiAQADAAkK6hRTaQDiAQAgAAEKAABTlgANAAAAAA==.Peon:BAAANQAECgYIDgAAAA==.Perstephanie:BAAANQADCgQIBAAAAA==.',
Ph='Pharune:BAABNQAECn8gAAIhAAcKPA3PFQDVAAAhAAcKPA3PFQDVAAAAAA==.Phredrick:BAAANQAECgMIAwAAAA==.',
Pi='Piemanninty:BAAANQAECgIJBQAAAA==.',
Pl='Plandemic:BAAANQAECgEIAQAAAA==.',
Po='Pockithealz:BAAANQADCgQIBAABNQAECgcIDQAGAAAAAA==.Pokerface:BAAANQAECgQIBgAAAA==.Ponky:BAAANQAECgIIAgABNQAECgoKLQAQACcZAA==.Poongwoon:BAAANQADCgMIAwAAAA==.Pounces:BAAANQAFFAQIBAAAAA==.',
Pr='Precious:BAAANQAECgIIBQABNQAFFAcIHwADAOAeAA==.',
Pu='Puppet:BAAANQAECgcIEAABNQAFFAcIHwADAOAeAA==.',
Py='Pymura:BAAANQADCgQIBAAAAA==.',
['Pí']='Píongá:BAAANQADCgEIAQAAAA==.',
Qe='Qee:BAAANQAECgEIAQABNQAECggIIAAEABIXAA==.',
Qu='Quattro:BAABNQAECn8eAAIiAAgKNg9dGgCjAQAiAAgKNg9dGgCjAQAAAA==.',
Ra='Racecar:BAAANQAECgUIDQAAAA==.Raezil:BAAANQAECgQICQABNQAECgoKIQATAKsSAA==.Raivyn:BAABNQAECn8qAAILAAkKsxQBKgDOAQALAAkKsxQBKgDOAQAAAA==.Rathmora:BAAANQADCggIFgAAAA==.Raylaira:BAAANQAECgIIAgABNQAECgIIAgAGAAAAAA==.Raziel:BAAANQADCgYIBgAAAA==.',
Re='Remnants:BAAANQADCggIEwAAAA==.Renard:BAABNQAECn81AAIFAAoKJCPtAABmAwAFAAoKJCPtAABmAwAAAA==.Reposado:BAAANQAECgUICAAAAA==.Revelare:BAABNQAECn8aAAIHAAcKFBd8ZwDWAQAHAAcKFBd8ZwDWAQAAAA==.Rexbie:BAAANQAECgcICwAAAA==.',
Rh='Rhylee:BAAANQAECgQIBwAAAA==.',
Ri='Rianne:BAAANQADCgUIBQAAAA==.Riptidepod:BAABNQAECn8cAAMHAAoKjBrbJgDJAgAHAAoKjBrbJgDJAgAJAAEKAACrRgErAAAAAA==.',
Rm='Rmplstiltskn:BAAANQADCgQIBAAAAA==.',
Ro='Robberttrest:BAABNQAECn8YAAIRAAUKWwl87QAmAQARAAUKWwl87QAmAQAAAA==.Rockyhunter:BAAANQAECgYIBwABNQAECgoKMQAdALAbAA==.Rockyhunterr:BAABNQAECn8xAAIdAAoKsBuRAwA1AgAdAAoKsBuRAwA1AgAAAA==.Rockymage:BAAANQADCgYIBgAAAA==.Rockyrogue:BAAANQADCggICAABNQAECgoKMQAdALAbAA==.Rockywarlock:BAAANQAECgEIAQABNQAECgoKMQAdALAbAA==.Rockywarrior:BAAANQADCgYICgABNQAECgoKMQAdALAbAA==.Rooth:BAAANQAECgUICQAAAA==.Roryn:BAABNQAECn88AAIYAAoKCCTDAQAiAwAYAAoKCCTDAQAiAwAAAA==.',
Ru='Rubï:BAAANQAECgcIDgAAAA==.Rugiaas:BAACNQAFFH8hAAIQAAYKPSOqAgB+AgAQAAYKPSOqAgB+AgA1AAQKfzkAAxAACgoFJc4EAKoDABAACgoFJc4EAKoDABgABApyFs35ACsBAAAA.Rugian:BAAANQAECgQIBQABNQAFFAYIIQAQAD0jAA==.',
Ry='Ryuka:BAAANQAECgcIEQAAAA==.',
['Râ']='Râezil:BAAANQADCgIIAgABNQAECgoKIQATAKsSAA==.',
Sa='Sabriiel:BAAANQADCgIIAwABNQAECgQIBgAGAAAAAA==.Samyria:BAAANQAECgQICAAAAA==.Satyaru:BAABNQAECn8nAAQPAAgKag/sEQDHAQAPAAgKag/sEQDHAQAVAAQKkgg/OwCYAAALAAEKAAAIcwAmAAAAAA==.Saucy:BAAANQAECgUIEQAAAA==.',
Se='Sedona:BAAANQAECgYICQAAAA==.Selarra:BAABNQAECn8dAAIDAAgKIw5cfACkAQADAAgKIw5cfACkAQAAAA==.Seric:BAABNQAECn8gAAMfAAgKWg8pGwCHAQAfAAgKWg8pGwCHAQACAAMK+wE5TQE5AAAAAA==.Sethuriel:BAAANQAECggIDgAAAA==.',
Sh='Shadowdancèr:BAAANQADCgEJAQAAAA==.Shalzith:BAAANQAECgEIAQAAAA==.Shenandoah:BAAANQADCgYIBgAAAA==.Shockadelica:BAAANQADCgYIBgAAAA==.',
Si='Sitheretta:BAAANQAECgQIBAAAAA==.',
Sk='Skoto:BAAANQAECgQIBAAAAA==.',
Sm='Smartfood:BAAANQAECggICwAAAA==.Smoochybooty:BAAANQAECgMIBAAAAA==.',
So='Solnar:BAABNQAECn8cAAMQAAgKdxJZYAD3AQAQAAgKdxJZYAD3AQAYAAQK8QyVRwGuAAAAAA==.',
Sp='Specter:BAAANQAECggICAAAAA==.Splashdaddy:BAACNQAFFH8NAAIHAAcKjQ/ICQCzAQAHAAcKjQ/ICQCzAQA1AAQKfzkAAgcACgqGIGwLAA8CAAcACgqGIGwLAA8CAAE1AAMKBgkPAAYAAAAA.Spoiled:BAAANQADCggICAABNQAFFAcIHwADAOAeAA==.',
Sr='Srìracha:BAAANQAECggIBAAAAA==.',
St='Staks:BAAANQADCgcIFAAAAA==.Starii:BAAANQAECgYIDgAAAA==.Stormieskye:BAABNQAECn8sAAIJAAkKmhK9CwC1AQAJAAkKmhK9CwC1AQAAAA==.Striga:BAAANQADCgcIBwAAAA==.',
Su='Summonme:BAAANQAECgIIAgAAAA==.Suzume:BAAANQAECgQIBAABNQAFFAcIGgAHAIkYAA==.',
Sw='Sweetshot:BAAANQADCgEIAQAAAA==.',
Sy='Sylvancura:BAAANQADCgQIBAAAAA==.Synestra:BAAANQAECgUICwAAAA==.',
Ta='Taea:BAAANQAECgUICgAAAA==.Taeus:BAABNQAECn8sAAQUAAoKVh/iBgCLAgAUAAoKVh/iBgCLAgAKAAcKMRff0wDfAQAjAAEKPw9zDAA/AAAAAA==.Taintedkoma:BAAANQAECgMIAwABNQAECgUIDwAGAAAAAA==.Talagark:BAAANQADCgYIBgAAAA==.Talanat:BAAANQADCgIIAgAAAA==.Taurenator:BAABNQAECn8eAAIfAAoKQyCkBgD5AgAfAAoKQyCkBgD5AgAAAA==.',
Te='Teheez:BAAANQADCgIIAgAAAA==.Tenthrol:BAAANQABCgMIBQAAAA==.Teranidas:BAAANQAECgIIAgAAAA==.Teratrendera:BAAANQAECgQIEQAAAA==.Teron:BAAANQAECgMJBAAAAA==.Tesx:BAAANQAECgIIAQAAAA==.',
Th='Thavis:BAABNQAECn8hAAMTAAgK6RCPMQA0AQATAAgKbg6PMQA0AQASAAQKwgxVOwDUAAAAAA==.Thdoris:BAAANQADCgQIBAAAAA==.Thetimelord:BAAANQAECgMIBQAAAA==.Thewarrior:BAAANQAECgcIDgAAAA==.Thrask:BAAANQADCgQIBAAAAA==.',
Ti='Ticktac:BAAANQAECgYJBgAAAA==.Tik:BAAANQADCggIDgAAAA==.Tilted:BAABNQAECn8bAAIYAAkK2hY4kwD9AQAYAAkK2hY4kwD9AQAAAA==.Tinkr:BAABNQAECn8lAAIdAAgKcBfnEgBKAQAdAAgKcBfnEgBKAQAAAA==.',
To='Tobi:BAAANQADCgYIBgAAAA==.Toewzix:BAAANQADCgQIBAAAAA==.Tom:BAAANQAECgUICAABNQAECgoKIQATAKsSAA==.Torrey:BAABNQAECn8fAAMNAAkKCQp7BwD/AAAEAAkKngmuNACdAQANAAgKEQh7BwD/AAAAAA==.Totemsareus:BAABNQAECn8pAAMHAAoKVCMgCACAAwAHAAoKVCMgCACAAwAJAAIKigdZFQFjAAAAAA==.Toxx:BAAANQAECgEIAQABNQAECgoKJwARADEcAA==.',
Tr='Tradd:BAACNQAFFH8IAAIDAAIKwhzVJACwAAADAAIKwhzVJACwAAA1AAQKfzMABAMACgpNICMOAFMDAAMACgpNICMOAFMDACQABwrDDr4MAGwBACAABwpMCpccAKUAAAAA.Trallor:BAABNQAECn8eAAICAAcKAw4VvgCBAQACAAcKAw4VvgCBAQAAAA==.Trhall:BAAANQAECgEIAQAAAA==.Tristyana:BAABNQAECn8uAAIRAAkKaBACGwCsAQARAAkKaBACGwCsAQAAAA==.',
Ts='Tsiddahn:BAABNQAECn8kAAIDAAkK9RqmKADHAgADAAkK9RqmKADHAgAAAA==.Tsunâde:BAABNQAECn8qAAMLAAoKCCVWAQCWAgALAAoKCCVWAQCWAgAVAAUKmxEXFwCMAAAAAA==.',
Ty='Tylurien:BAABNQAECn8gAAIQAAcKSSZXBQCEAgAQAAcKSSZXBQCEAgAAAA==.Tyrael:BAABNQAECn8ZAAIBAAgKsg9/DgAiAQABAAgKsg9/DgAiAQABNQADCgMIBgAGAAAAAA==.',
Uk='Ukon:BAAANQADCgYIBgAAAA==.',
Ul='Ulangi:BAAANQAECgEIAQAAAA==.',
Un='Un:BAAANQADCgcIAQAAAA==.',
Ur='Urbanprey:BAABNQAECn8dAAISAAgK2gl4IABsAQASAAgK2gl4IABsAQAAAA==.',
Va='Valenhi:BAAANQAECgEIAQAAAA==.Valkoinen:BAAANQADCgMIBgAAAA==.Valora:BAABNQAECn8uAAIDAAoKCB5mBADXAgADAAoKCB5mBADXAgAAAA==.Valoria:BAAANQAECgIIAwAAAA==.Vanille:BAAANQAECgUIEQAAAA==.Vargen:BAAANQAECgQICAAAAA==.Varonika:BAAANQAECgUIBwAAAA==.Vayla:BAABNQAECn8qAAIfAAkKRx2+DQBVAgAfAAkKRx2+DQBVAgAAAA==.',
Vb='Vbv:BAAANQAECgMIAwAAAA==.',
Ve='Vedik:BAAANQAECgQIBQAAAA==.Vegasduc:BAAANQADCgQIBAAAAA==.Vegasducks:BAABNQAECn8fAAIKAAcKPgg3AAGNAQAKAAcKPgg3AAGNAQAAAA==.Velara:BAAANQADCgYIDAAAAA==.Veld:BAAANQAECgcIDQAAAA==.Velithara:BAAANQADCgYJBgAAAA==.Veralyn:BAAANQADCgQIBAAAAA==.',
Vi='Violet:BAAANQAECgUIEgAAAA==.',
Vy='Vyla:BAAANQABCgcIDAAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUIBQAAAA==.',
Wa='Wardancer:BAAANQAECgUIBQAAAA==.Warfise:BAAANQAECgUICAAAAA==.Warspriest:BAABNQAECn8eAAIgAAcKcRygBgCOAQAgAAcKcRygBgCOAQAAAA==.Warwizard:BAABNQAECn9DAAIQAAkKDyRrAQBVAwAQAAkKDyRrAQBVAwAAAA==.',
Wd='Wdemperor:BAABNQAECn8WAAMfAAcK+QKTMACxAAAfAAcK4gKTMACxAAACAAMKzgNQvABAAAABNQAECgkJFgAXAFgIAA==.',
We='Webin:BAAANQAECgEIAQAAAA==.',
Wh='Whispaknight:BAAANQAECgEIAQABNQAECgEIAQAGAAAAAA==.Whisperwiind:BAAANQADCgcIBwABNQAECgEIAQAGAAAAAA==.Whisperz:BAAANQADCgYIBgABNQAECgEIAQAGAAAAAA==.',
Wi='Wickedywaque:BAAANQADCgUIBQAAAA==.Wickerchickn:BAAANQAECgQJBwAAAA==.Wiisper:BAAANQAECgEIAQAAAA==.Wilshammy:BAAANQADCgYIGAAAAA==.Winterhunter:BAAANQADCgEIAQAAAA==.',
Wo='Wonkyponky:BAABNQAECn8tAAIQAAoKJxndJwDJAgAQAAoKJxndJwDJAgAAAA==.',
Wr='Wrathbarrage:BAAANQAECgYICwABNQAECgkJKgAhAOMQAA==.Wrathchoi:BAAANQAECgUIBQAAAA==.Wrathstorm:BAABNQAECn8qAAMhAAkK4xB/DgAgAQAhAAkKuBB/DgAgAQAOAAEKKQp8HwA3AAAAAA==.',
Ya='Yazahk:BAAANQADCggIFgAAAA==.Yazjani:BAAANQADCgIIAgAAAA==.Yazoth:BAAANQADCgEIAQAAAA==.Yazoura:BAAANQADCggIDwAAAA==.Yazwynn:BAAANQADCgcIDgAAAA==.',
Ye='Yezgraine:BAACNQAFFH8aAAIdAAcK+iDKAQCdAgAdAAcK+iDKAQCdAgA1AAQKfyMAAx0ACgqJInkIALEBAB0ACgqJInkIALEBABsAAQrdHM6dAFYAAAAA.',
Yo='Yookock:BAAANQADCggIDgAAAA==.',
Za='Zagyg:BAAANQADCgQIBAAAAA==.',
Ze='Zeddiccus:BAAANQAECgcIEQAAAA==.Zeva:BAAANQAECgQICAAAAA==.',
Zo='Zonzmik:BAAANQABCgYIBAAAAA==.Zorrokiller:BAAANQADCgQIBAAAAA==.Zorvoth:BAAANQADCgQIBAABNQAECgIIAgAGAAAAAA==.',
Zu='Zurazaee:BAAANQAECgUIEgAAAA==.',
['Él']='Élle:BAAANQADCgcICAAAAA==.',
['Ér']='Éric:BAABNQAECn8uAAIhAAkKeQmtDgAeAQAhAAkKeQmtDgAeAQAAAA==.',
['Ïr']='Ïridescent:BAAANQAECgIIAgAAAA==.',
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
