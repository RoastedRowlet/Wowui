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

local lookup = {'Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Warrior-Arms','Monk-Brewmaster','Warrior-Fury','Druid-Balance','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Mage-Arcane','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Havoc','Warlock-Affliction','Priest-Shadow','Rogue-Assassination','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Warrior-Protection','Druid-Feral','Druid-Guardian','Evoker-Augmentation','Rogue-Outlaw','Evoker-Preservation','Druid-Restoration','Rogue-Subtlety','DemonHunter-Devourer','DemonHunter-Vengeance',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=53,date='2026-10-13',data={Ae='Aegrias:BAABNQAECn8aAAIBAAkKAx/5QwDGAgABAAkKAx/5QwDGAgAAAA==.Aerodria:BAABNQAECn8sAAICAAkKuBq4EQCCAgACAAkKuBq4EQCCAgAAAA==.',
Al='Alanril:BAAANQADCgMIAwAAAA==.Alarthevel:BAAANQAECgMIBAAAAA==.Albince:BAAANQADCgQIBAAAAA==.',
Am='Amellis:BAAANQADCgIIAgAAAA==.',
An='Andeduty:BAAANQADCgIIAgABNQADCggIDgADAAAAAA==.Andreaswar:BAAANQAECgMIAwAAAA==.Anniferal:BAAANQAECgMIBAABNQAFFAUIDAAEADQYAA==.Annisseda:BAACNQAFFH8MAAIEAAUKNBgkDwC+AQAEAAUKNBgkDwC+AQA1AAQKfxkAAgQACApVIpxNAJ0CAAQACApVIpxNAJ0CAAAA.Anzak:BAAANQAECgQIBQAAAA==.',
Ar='Ardrayshock:BAAANQABCgcJCgAAAA==.Ardrek:BAAANQADCggICAAAAA==.Arrhythmia:BAAANQAECgQIBQABNQAFFAQIDAADAAAAAQ==.',
As='Astrayn:BAAANQADCgIIAgAAAA==.',
Az='Azala:BAAANQAECgIIAgAAAA==.Azryx:BAAANQADCgcICQABNQAECgkJHwAFAEIgAA==.Azzy:BAACNQAFFH8QAAIEAAUKOBToEwCHAQAEAAUKOBToEwCHAQA1AAQKfzgAAwQACQpyJDERAHcDAAQACQo2JDERAHcDAAYACQpAILEDABMDAAAA.',
Ba='Bananski:BAAANQADCgcIBwAAAA==.',
Be='Beefychunks:BAABNQAECn8cAAIEAAgKPRvBXQBwAgAEAAgKPRvBXQBwAgAAAA==.',
Bi='Bigdraco:BAAANQADCgQIBQAAAA==.Biggums:BAAANQADCgQIBAAAAA==.Bigpapapump:BAAANQAECgMIAwAAAA==.Billyspikepd:BAAANQAECgUIEQAAAA==.Billyspikepr:BAAANQADCggIDQABNQAECgUIEQADAAAAAA==.Billyspikerg:BAAANQAECgUIDQABNQAECgUIEQADAAAAAA==.',
Bl='Black:BAAANQADCgIIAgAAAA==.Blobcat:BAABNQAECn8hAAIHAAgK5RSeNQA6AgAHAAgK5RSeNQA6AgAAAA==.Blobknight:BAAANQAECgUICgAAAA==.Bloodhase:BAABNQAECn8YAAMIAAkK5xlLIwByAgAIAAkK5xlLIwByAgAJAAQK3A45oQC1AAAAAA==.Bluecard:BAACNQAFFH8JAAMKAAQKohbMHAAPAQAKAAMKQRjMHAAPAQALAAEKYhMLGwBQAAA1AAQKfx4AAwoACQquH29OAGYCAAoABwpsH29OAGYCAAsAAwo7IcdFAK4AAAAA.',
Bo='Bothenheim:BAACNQAFFH8MAAIBAAUKpR7hBwDMAQABAAUKpR7hBwDMAQA1AAQKfxYAAgEACApfG493ADkCAAEACApfG493ADkCAAAA.Bowdaddy:BAAANQAECgYIEQAAAA==.',
Br='Breakdown:BAAANQAECgUIDQAAAA==.Brewsimmons:BAAANQADCggIEAABNQAFFAcIFAAMAJQKAA==.',
Bu='Bublz:BAAANQADCgIIAgAAAA==.Bumpinuglies:BAAANQADCgYICQAAAA==.',
Ca='Cailey:BAAANQAECggICgABNQAECggICgADAAAAAA==.Calcshortfor:BAAANQADCgQIBAAAAA==.Callamdrake:BAAANQADCgQJBQAAAA==.Callamsvoid:BAAANQAECgEIAQAAAA==.Calyrex:BAAANQADCgEIAQAAAA==.Camazotz:BAAANQAECgcIBwAAAA==.Capulse:BAACNQAFFH8NAAINAAUK0xnfCgCaAQANAAUK0xnfCgCaAQA1AAQKfxYAAw0ABwrCINVfAOsBAA0ABgqeItVfAOsBAA4ABAqSFV3IAP0AAAAA.',
Ce='Centri:BAABNQAECn8iAAMPAAkKNiF6BQC5AgAPAAcKWCJ6BQC5AgAQAAkKTxtgfQCDAgAAAA==.',
Ch='Chowa:BAAANQAECgEIAQAAAA==.',
Cl='Clapdatazz:BAAANQAECgcICwAAAA==.Cleverlev:BAAANQADCgUIBwABNQAECgkJJQARADAeAA==.',
Co='Colapse:BAAANQADCgMIAwAAAA==.',
Cr='Crunchrr:BAAANQADCgEIAQAAAA==.',
Cu='Cubensis:BAAANQADCgcJFgAAAA==.',
Cy='Cyiera:BAAANQAECggICgAAAA==.',
Da='Daeland:BAAANQAECgcICAAAAA==.Daisyshot:BAABNQAECn8uAAMSAAkKpSLRGQAwAwASAAgKfyTRGQAwAwATAAYKYBlcOwBwAQAAAA==.',
De='Deathsgrace:BAAANQADCggICQAAAA==.Decima:BAABNQAECn8ZAAIHAAgKsAcwWABwAQAHAAgKsAcwWABwAQAAAA==.Dejustinfox:BAAANQADCgQIBwAAAA==.Demeter:BAACNQAFFH8JAAMTAAUKchMnEwAIAQATAAQKchMnEwAIAQASAAIKGBecKACSAAA1AAQKfxoAAxMACQpSHmYgAEgCABMACAqEHWYgAEgCABIABArJFS7+AAIBAAAA.Demonpunter:BAABNQAECn8aAAIUAAcKaB7EJQBrAgAUAAcKaB7EJQBrAgABNQAFFAUIDwAVACAlAA==.',
Di='Diabloa:BAAANQADCgQICAAAAA==.Diamba:BAAANQAECgQIBgAAAA==.Dinoscarr:BAAANQAECgQIBAAAAA==.',
Do='Doohickey:BAAANQAECgQIBQABNQAECgYICwADAAAAAA==.Doohicky:BAAANQAECgYICwAAAA==.Dorgrim:BAAANQADCgMIAwAAAA==.Dotsndash:BAABNQAECn8oAAIWAAkK2xkRGACSAgAWAAkK2xkRGACSAgAAAA==.',
Dp='Dpsshaman:BAAANQABCgYIBgABNQAECggIFQAXAAAfAA==.',
Du='Dungpoo:BAAANQADCgEIAQAAAA==.',
Ea='Eargox:BAAANQAECgMIBAAAAA==.',
Ee='Eesa:BAAANQAECggICQAAAA==.',
El='Elinia:BAAANQADCgMIBAAAAA==.Elmdor:BAAANQAECgMIAwAAAA==.Elyndra:BAAANQAECgMIBQAAAA==.',
En='Eniacoc:BAAANQAECgEIAQAAAA==.',
Ex='Excentric:BAAANQAECgIIAgABNQAECgkJIgAPADYhAA==.',
Fa='Faithlyn:BAAANQADCgEIAQABNQAECgIIAgADAAAAAA==.Falarth:BAABNQAECn8aAAIYAAcKJRX7UwCiAQAYAAcKJRX7UwCiAQAAAA==.Falloutman:BAAANQAECgUIDQAAAA==.Farther:BAAANQADCgUICQABNQAFFAUIEgAQADwZAA==.Fayne:BAAANQADCgcICQAAAA==.',
Fe='Felfart:BAAANQADCgUIBQAAAA==.',
Fi='Firefox:BAACNQAFFH8FAAIYAAIKXhGSIgByAAAYAAIKXhGSIgByAAA1AAQKfxkAAhgACQomGPI2ACsCABgACQomGPI2ACsCAAE1AAUUBAgEAAMAAAAA.',
Fl='Flechillas:BAAANQADCgcIDQAAAA==.Flán:BAAANQAECgcIEAAAAA==.',
Fr='Fraternite:BAAANQAECgMIAwAAAA==.',
Fu='Furrymoon:BAAANQADCgcIBwAAAA==.',
Ga='Gabriellad:BAAANQAECgIIAwAAAA==.',
Ge='Gerrakha:BAAANQADCgYIBgABNQAECgEIBQADAAAAAA==.',
Gi='Giterdonee:BAACNQAFFH8LAAMGAAUKOxXPAgCpAAAEAAMKOxWWIgDkAAAGAAIKAADPAgCpAAA1AAQKfyQAAwYACQo5HosFAMUCAAYACQpWHIsFAMUCAAQABgp+F6ivAKABAAAA.',
Go='Gorr:BAAANQADCgMIAwABNQAECgIIAgADAAAAAA==.Gotchoo:BAABNQAECn8WAAIIAAYK4RXkSwCCAQAIAAYK4RXkSwCCAQABNQADCgQIBAADAAAAAA==.Gothmommy:BAABNQAECn8nAAIZAAgKQxyxQQBhAgAZAAgKQxyxQQBhAgAAAA==.',
Gr='Grilledchis:BAAANQADCgIIAgAAAA==.Groldin:BAAANQADCgUIBQAAAA==.Grumble:BAAANQAECgQIBAAAAA==.',
['Gõ']='Gõtchoo:BAAANQADCgQIBAAAAA==.',
Ha='Hairball:BAAANQAECgYIEwAAAA==.Hammerthumb:BAAANQADCgcICQABNQAECgcIFgAHAGsLAA==.Hardawn:BAAANQABCgEIAQABNQAFFAUIEgAQADwZAA==.',
Ho='Hotsoup:BAAANQADCgQJBAAAAA==.Hozzluzzak:BAAANQADCggICAAAAA==.',
Hy='Hyara:BAABNQAECn84AAISAAkKZCRJCACaAwASAAkKZCRJCACaAwAAAA==.',
['Hù']='Hùñtarð:BAAANQAECgEIAgAAAA==.',
Ic='Iceagent:BAAANQABCgMIAwAAAA==.',
Im='Imnaked:BAAANQADCgYIBgAAAA==.',
In='Invisimitch:BAAANQADCgEIAQAAAA==.',
Ip='Ips:BAAANQADCgIIAgABNQADCgUIBQADAAAAAA==.',
Jo='Jordi:BAABNQAECn8jAAISAAgKtB3sPQCuAgASAAgKtB3sPQCuAgAAAA==.Jotarcyon:BAAANQABCgIJAgAAAA==.',
Ju='Jukkes:BAAANQADCggIEwAAAA==.Justinfox:BAAANQADCgEIAQAAAA==.Juukess:BAAANQAECgIIAgAAAA==.',
Ka='Kannarri:BAAANQAECgMIBAAAAA==.Kanree:BAACNQAFFH8RAAIRAAUKnATfBQA9AQARAAUKnATfBQA9AQA1AAQKfzgAAhEACQrbE3MXAAICABEACQrbE3MXAAICAAAA.Kayaa:BAAANQADCggICAAAAA==.',
Ke='Kea:BAACNQAFFH8JAAMaAAQK2xo0AQBvAQAaAAQK2xo0AQBvAQAZAAEKbBZbMQBQAAA1AAQKf0YABBoACQrAJVIAAMEDABoACQoGJVIAAMEDABkACQrJJAEFAKEDABYABAonGYs9ADsBAAAA.Kek:BAAANQAECgUIDAAAAA==.',
Kh='Khaalid:BAAANQADCgQIBAABNQAECgkJHwAFAEIgAA==.Kharok:BAABNQAECn8aAAMbAAgKoiC1CADEAgAbAAgKoiC1CADEAgAEAAYKVRjGpAC8AQABNQAECgkJHwAFAEIgAA==.',
Ki='Kincane:BAAANQADCgcICQAAAA==.',
Ko='Korxin:BAACNQAFFH8IAAMSAAUKnQxfGgDiAAASAAMKUxFfGgDiAAATAAMKtgQPFwDNAAA1AAQKfzEAAxIACQpKIQUyANQCABIACQpKIQUyANQCABMABwpODQc9AGUBAAAA.Kota:BAAANQADCgEIAQAAAA==.',
Ku='Kurnhaspios:BAAANQADCgQIBAAAAA==.Kurquaan:BAAANQAECgMIBAAAAA==.',
Ky='Kydraeth:BAAANQAECgEIAQAAAA==.',
La='Lanstyn:BAABNQAECn8vAAIaAAgK6RnEBAByAgAaAAgK6RnEBAByAgABNQAECgkJHwAFAEIgAA==.Laufey:BAABNQAECn8kAAIQAAcKJxa9swAaAgAQAAcKJxa9swAaAgAAAA==.',
Le='Lemone:BAAANQADCgUIBQAAAA==.Lemonsk:BAAANQADCgUICAAAAA==.Lennox:BAAANQADCgQIBAAAAA==.Lenton:BAAANQAECgEIAQAAAA==.',
Li='Lightfury:BAAANQADCgYIDAAAAA==.Limone:BAAANQAECgEIAQAAAA==.Listradra:BAAANQADCgQIBAAAAA==.',
Lo='Loganwater:BAAANQADCgQIBAAAAA==.Loinari:BAAANQADCgUIDQAAAA==.Lokano:BAAANQADCgIIAgAAAA==.',
Lu='Ludmylha:BAAANQAECgIIBAAAAA==.Luisda:BAAANQADCggIFwAAAA==.Lull:BAAANQADCggIEQAAAA==.Lushil:BAAANQAFFAEIAQAAAA==.',
Ly='Lyrea:BAAANQAECggICAAAAA==.',
Ma='Magidragon:BAAANQADCgQIBAAAAA==.Man:BAAANQADCgUIBQAAAA==.Marsangel:BAAANQADCgEIAQAAAA==.Maxerella:BAAANQADCgUIBQAAAA==.Maybell:BAAANQAECgQIBQAAAA==.',
Me='Meepmeepmomp:BAAANQADCgUIBQAAAA==.Megumín:BAAANQADCgUIBQAAAA==.Melt:BAACNQAFFH8TAAQLAAUK2xuDCACwAAALAAIK5xiDCACwAAAKAAIKwyGrKgCtAAAVAAEKAAD8CABcAAA1AAQKfzUAAwoACQrYIm0jAPQCAAoACArrIm0jAPQCAAsABArrIBsgAG4BAAAA.Mepha:BAACNQAFFH8JAAIJAAMKJw/FEgDcAAAJAAMKJw/FEgDcAAA1AAQKfyIAAwkACQocHBM/AB8CAAkACAocHBM/AB8CAAgACArhDEZKAIsBAAAA.Meridia:BAAANQADCgMIAwAAAA==.',
Mi='Miike:BAAANQADCgEIAQABNQAFFAUIEgAQADwZAA==.Mike:BAACNQAFFH8SAAIQAAUKPBkLGACyAQAQAAUKPBkLGACyAQA1AAQKf1cAAxAACQqxI40SAIkDABAACQqxI40SAIkDAA8ABQqUD+MeAPAAAAAA.Mikevoker:BAAANQADCgEIAQABNQAFFAUIEgAQADwZAA==.Mipz:BAAANQADCgUIBQAAAA==.Misfitdk:BAAANQAECggIAgAAAA==.Misfitmagi:BAAANQAECgIIAgAAAA==.Mistfox:BAAANQADCgYIDAAAAA==.Mistmommy:BAABNQAECn8hAAIRAAgKzxF8GwDHAQARAAgKzxF8GwDHAQAAAA==.',
Mo='Mollieann:BAAANQAECgIIAgAAAA==.Mommon:BAAANQADCgEIAQAAAA==.Morrighan:BAAANQADCgMIAwAAAA==.',
['Mâ']='Mâlus:BAAANQAECgUICAAAAA==.',
['Mä']='Märs:BAAANQADCgYICgAAAA==.',
Na='Nadra:BAAANQADCgYIBgAAAA==.Naminé:BAAANQADCgQIBAABNQAECgcIJAAQACcWAA==.Naroka:BAAANQAECgQIBQAAAA==.Nattyrav:BAACNQAFFH8IAAIOAAQKGRW3EgA/AQAOAAQKGRW3EgA/AQA1AAQKfyUAAw4ACQp/GmY8AIECAA4ACQp/GmY8AIECAA0AAQpQHU8IAVEAAAAA.',
Ne='Neemesis:BAAANQAECgQIBAAAAA==.Nemonk:BAAANQAECgcIDAABNQAECgcIDQADAAAAAA==.Nemoz:BAAANQAECgcIDQAAAA==.Nerfling:BAAANQADCgYICAAAAA==.',
No='Nocter:BAAANQAECgUIBQAAAA==.Noktor:BAAANQADCgYIBgAAAA==.Noktra:BAAANQAECgQIDwAAAA==.',
Ny='Nylah:BAAANQAECgUIBgABNQAFFAUIEAALAIUSAA==.Nymura:BAAANQAECgUIEgAAAA==.',
Oa='Oakhugger:BAABNQAECn8WAAQHAAcKawsJbwAKAQAHAAUKYQoJbwAKAQAcAAMKSgsaLgCbAAAdAAIKqwOLWQA+AAAAAA==.',
Ol='Olyvivia:BAAANQADCgUIBQAAAA==.',
Om='Omgega:BAABNQAECn8gAAIBAAcKoBZ9lgDyAQABAAcKoBZ9lgDyAQAAAA==.',
On='Onichan:BAAANQAECgEIAQABNQAFFAcIFAAOAOMbAA==.Onimeek:BAABNQAECn8tAAIUAAkKMBlqJQBuAgAUAAkKMBlqJQBuAgAAAA==.Onionknightt:BAAANQAECgEIAQAAAA==.',
Or='Oryn:BAAANQAECggIEAABNQAFFAEIAQADAAAAAA==.Oryx:BAAANQADCgEIAQAAAA==.',
Os='Osoloco:BAAANQADCgUIAwAAAA==.',
Pa='Palmpower:BAAANQADCgYICQAAAA==.Palpitations:BAAANQAECgEIAQAAAA==.Paper:BAAANQAFFAQIDAAAAQ==.',
Pe='Peacefullev:BAABNQAECn8lAAIRAAkKMB5dCQDzAgARAAkKMB5dCQDzAgAAAA==.Pepegá:BAAANQAECgEIAQAAAA==.Pewpewpew:BAAANQAECgUIBQAAAA==.',
Ph='Phantomthief:BAAANQAECggICAAAAA==.',
Pi='Pipeleto:BAABNQAECn82AAIEAAkKRCAdJQAiAwAEAAkKRCAdJQAiAwAAAA==.Pizzaroll:BAABNQAECn8yAAIeAAkKyRX7BACiAgAeAAkKyRX7BACiAgAAAA==.',
Po='Podvoddonut:BAAANQADCgYIBgAAAA==.',
Pr='Previdius:BAAANQADCgUIBQAAAA==.Priesstess:BAAANQADCgYICQAAAA==.',
['Pé']='Pépega:BAAANQADCgQIBwAAAA==.',
Ri='Riellus:BAAANQADCgcIBwAAAA==.Riiu:BAAANQAECgEIAQABNQAECggILgABAC0kAA==.Riven:BAAANQADCgYIBgAAAA==.Rixin:BAECNQAFFH8KAAMJAAQK/BwVEQD1AAAJAAMK/BwVEQD1AAAYAAEKAADIOgAcAAA1AAQKfykAAgkACQpxIDAbAOcCAAkACQpxIDAbAOcCAAAA.',
Ro='Rokom:BAACNQAFFH8JAAMGAAMK2BmpAgCyAAAGAAIK/yGpAgCyAAAEAAEKsBGkOwBHAAA1AAQKfyYAAwYACQrOG8gNANUBAAYABgokHcgNANUBAAQABAptGMXnAA8BAAAA.Roonrano:BAAANQADCggJCAAAAA==.',
Ru='Rumpus:BAAANQADCgcIBwAAAA==.Runed:BAAANQAECgEIAQAAAA==.',
Ry='Ryuk:BAAANQADCgYICgAAAA==.',
Sa='Salla:BAAANQADCgYICQAAAA==.Sanlennicus:BAAANQAECgEIAQAAAA==.Saphh:BAAANQAECgEIAQABNQAFFAQIDwAIAHIYAA==.Saudencheek:BAAANQAECgQIBAAAAA==.',
Se='Seanster:BAABNQAECn8eAAMXAAkK+xL1IQByAgAXAAkK+xL1IQByAgAfAAMKQQIwGABeAAABNQAFFAUIEAALAIUSAA==.Senecca:BAABNQAECn8lAAIHAAgKZx2QIADGAgAHAAgKZx2QIADGAgAAAA==.',
Sh='Shadowlily:BAAANQADCgMIAwABNQADCggIHAADAAAAAA==.Shadowms:BAABNQAECn8jAAIgAAkKiBk9DQDRAgAgAAkKiBk9DQDRAgAAAA==.Shadowxd:BAABNQAECn8fAAQhAAkKhxslDwDfAgAhAAkKhxslDwDfAgAdAAEKAAA8XgAzAAAHAAEKHAb9twAmAAAAAA==.Shamanpwnz:BAAANQAECgQIBgAAAA==.Shambassador:BAAANQAECggIEQAAAA==.Shamwowha:BAAANQADCgQIBAAAAA==.Sharkdancer:BAAANQAFFAIIAgABNQAFFAYIDgARAJMhAA==.Shaulana:BAAANQADCggIHAAAAA==.Shenwu:BAABNQAECn8aAAIFAAgKmBimDQAdAgAFAAgKmBimDQAdAgAAAA==.Shirokuma:BAACNQAFFH8NAAMHAAUKTBf6EQBFAQAHAAQKTBf6EQBFAQAdAAEKAACxCABfAAA1AAQKfx8AAwcACQo2HHgaAPMCAAcACQo2HHgaAPMCAB0AAQrxF2dTAFAAAAAA.Shocktopuus:BAAANQADCgQIBAAAAA==.Shwizzle:BAAANQADCggIDgAAAA==.',
Si='Sidvicious:BAAANQADCgUIBAAAAA==.',
Sk='Sköllati:BAAANQAECgQIBAAAAA==.',
Sm='Smarty:BAAANQAECgQIBAAAAA==.',
Sn='Sneakylev:BAABNQAECn8gAAMiAAkKMxL8HQDfAQAiAAgKmwz8HQDfAQAXAAQKHhEQawD9AAABNQAECgkJJQARADAeAA==.',
So='Solari:BAABNQAECn8yAAMjAAkKiSTeAgCrAwAjAAkKiSTeAgCrAwAkAAUKIBglFwA4AQAAAA==.Soleon:BAAANQAECgUICQAAAA==.Solune:BAAANQAECgYIDAAAAA==.Souprage:BAAANQAECgMIBgAAAA==.',
Sp='Spypal:BAAANQADCgYIDAAAAA==.',
St='Stabwei:BAAANQADCggICAAAAA==.',
Su='Sugirokimami:BAAANQAECgIIAgABNQAECgQIBgADAAAAAA==.',
Sw='Swagmastrflx:BAAANQADCgQIBAAAAA==.Swëëtdee:BAAANQADCgMICAAAAA==.',
Ta='Taehausx:BAAANQAFFAEIAQABNQAFFAUIBwACAJATAA==.Taraka:BAAANQADCggICAAAAA==.',
Td='Tdolokk:BAAANQADCggIFwAAAA==.',
Te='Teeward:BAAANQADCgYIBgAAAA==.Tenath:BAAANQAECgUICQAAAA==.Terribleturd:BAAANQAECgEIAQAAAA==.',
Th='Thaleon:BAAANQADCggICAAAAA==.Thauriel:BAAANQAECgEIAQAAAA==.Theexecution:BAAANQADCgMIAwAAAA==.Therella:BAAANQADCgUIBQAAAA==.',
To='Totemtotebag:BAABNQAECn8XAAINAAQK7Bd/rgAOAQANAAQK7Bd/rgAOAQABNQAECgkJIgAdAF0lAA==.',
Tr='Treshaleth:BAAANQADCgQIBAAAAA==.Tripodg:BAAANQAECgEIAQAAAA==.Trollztoll:BAAANQADCgIIAgAAAA==.',
Tw='Twiddletime:BAAANQAECgQIBAAAAA==.',
['Tï']='Tïggy:BAAANQAECgMIAwAAAA==.',
Un='Una:BAAANQAECgYIBwAAAA==.Unholymisfit:BAAANQAECgIIBAAAAA==.Unholytato:BAAANQADCgQIBAAAAA==.',
Ur='Ursok:BAAANQAECgEIAQABNQAECgkJHwAFAEIgAA==.',
Ut='Uthok:BAAANQADCgEJAQAAAA==.',
Uz='Uzol:BAAANQADCgcICAAAAA==.',
Va='Vacalocà:BAAANQAECgIIAgAAAA==.Valerian:BAAANQAECgcIDQAAAA==.Van:BAAANQADCgQIBAAAAA==.',
Ve='Veinke:BAAANQAECgcIEwAAAA==.Velanthir:BAAANQADCggIFAAAAA==.Verd:BAEANQAFFAEIAQAAAA==.Veronica:BAAANQABCgYIBgAAAA==.Versaacee:BAAANQADCgYIBgAAAA==.Vessarind:BAAANQADCgUIBQAAAA==.',
Vi='Vivrian:BAAANQADCgUIBQAAAA==.',
['Vä']='Vänillaicë:BAAANQADCgcIBwABNQADCggIHAADAAAAAA==.',
Wa='Waally:BAAANQAECgQIBQAAAA==.Wahwoo:BAAANQADCggIDgABNQADCggIHAADAAAAAA==.',
We='Weebsora:BAAANQAECgQIBQAAAA==.',
Wo='Worldtree:BAAANQADCgEIAQAAAA==.',
Xa='Xaelthira:BAAANQADCgcIBwAAAA==.',
Ya='Yadhi:BAABNQAECn8fAAIFAAkKQiD4AgBrAwAFAAkKQiD4AgBrAwAAAA==.',
Yi='Yimomo:BAABNQAECn8nAAIZAAgKqh7MMwCWAgAZAAgKqh7MMwCWAgAAAA==.',
Za='Zalconn:BAABNQAECn8gAAMiAAkKmSPACwC4AgAiAAcKOCTACwC4AgAXAAQKVyGSUQBxAQAAAA==.Zarrona:BAAANQAECgIIAwABNQAECgcIJAAQACcWAA==.Zayah:BAAANQAFFAIIAwAAAA==.',
Zi='Zikony:BAAANQAECgUIBAAAAA==.',
Zu='Zuber:BAABNQAECn8uAAIXAAkKxyHkBwBVAwAXAAkKxyHkBwBVAwAAAA==.',
['År']='Årtimus:BAAANQADCgYIDAAAAA==.',
['Üw']='Üwü:BAAANQAECgYIEQAAAA==.',
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
