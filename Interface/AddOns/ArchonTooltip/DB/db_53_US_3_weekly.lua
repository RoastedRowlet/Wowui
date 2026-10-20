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

local lookup = {'Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Warrior-Arms','Monk-Brewmaster','Warrior-Fury','Druid-Balance','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Mage-Frost','Mage-Arcane','Monk-Mistweaver','Hunter-Marksmanship','DemonHunter-Havoc','Warlock-Affliction','Priest-Shadow','DeathKnight-Blood','DemonHunter-Vengeance','Monk-Windwalker','Priest-Holy','Hunter-Survival','Priest-Discipline','Warrior-Protection','Druid-Feral','Druid-Guardian','Evoker-Augmentation','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation','Druid-Restoration','DemonHunter-Devourer','Rogue-Subtlety',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=53,date='2026-10-20',data={Ae='Aegrias:BAABNQAECn8cAAIBAAkKAx8yRQDFAgABAAkKAx8yRQDFAgAAAA==.Aerodria:BAABNQAECn81AAICAAoKABmDBADDAQACAAoKABmDBADDAQAAAA==.',
Al='Alanril:BAAANQADCgMIAwAAAA==.Alarthevel:BAAANQAECgMIBAAAAA==.Albince:BAAANQADCgQIBAAAAA==.',
Am='Amant:BAAANQADCggICQAAAA==.Amellis:BAAANQADCgIIAgAAAA==.',
An='Andeduty:BAAANQADCgYICAABNQADCggIFgADAAAAAA==.Andreaswar:BAAANQAECgMIAwAAAA==.Anniferal:BAAANQAECgMIBAABNQAFFAUIDwAEAK8bAA==.Annisseda:BAACNQAFFH8PAAIEAAUKrxubDwC9AQAEAAUKrxubDwC9AQA1AAQKfx0AAgQACQpaIJopAGEBAAQACQpaIJopAGEBAAAA.Anzak:BAAANQAECgQIBQAAAA==.',
Ar='Araelina:BAAANQADCgIIAgAAAA==.Ardrayshock:BAAANQABCgcJCgAAAA==.Ardrek:BAAANQADCggICAAAAA==.Arrhythmia:BAAANQAECgQICAABNQAFFAUIDwADAAAAAQ==.',
As='Astrayn:BAAANQADCgIIAgAAAA==.',
Az='Azala:BAAANQAECgIIAgAAAA==.Azryx:BAAANQADCgcICQABNQAECgoKJQAFAGMfAA==.Azzy:BAACNQAFFH8WAAIEAAYKABKzBgAQAQAEAAYKABKzBgAQAQA1AAQKfzwAAwQACgpVIKARAHYDAAQACgohIKARAHYDAAYACQpAILYDABMDAAAA.',
Ba='Bananski:BAAANQADCgcIBwAAAA==.',
Be='Beeflocks:BAAANQAECgIIAwABNQAECgkJIAAEAIUZAA==.Beefychunks:BAABNQAECn8gAAIEAAkKhRkzXwBvAgAEAAkKhRkzXwBvAgAAAA==.',
Bi='Bigdraco:BAAANQADCgQIBQAAAA==.Biggums:BAAANQADCgQIBAAAAA==.Bigpapapump:BAAANQAECgMIAwAAAA==.Billyspikepd:BAABNQAECn8YAAMBAAYKWBLp2ABpAQABAAYKWBLp2ABpAQACAAEK/glWewAhAAAAAA==.Billyspikepr:BAAANQADCggIDQABNQAECgYIGAABAFgSAA==.Billyspikerg:BAAANQAECgYIDQABNQAECgYIGAABAFgSAA==.',
Bl='Black:BAAANQADCgMIAwAAAA==.Blobcat:BAABNQAECn8iAAIHAAgK5RQyNgA5AgAHAAgK5RQyNgA5AgAAAA==.Blobknight:BAAANQAECgUIDwAAAA==.Bloodhase:BAABNQAECn8aAAMIAAkKmhrhIwByAgAIAAkKmhrhIwByAgAJAAQK3A7RogC1AAAAAA==.Bluecard:BAACNQAFFH8MAAMKAAQKihdxDACxAAAKAAMKnhlxDACxAAALAAEKYhPWGgBQAAA1AAQKfyIAAwoACgokHwQaAIkBAAoACArXHgQaAIkBAAsAAwo7IS1GAK4AAAAA.',
Bo='Bothenheim:BAACNQAFFH8PAAIBAAUKpR4UCADLAQABAAUKpR4UCADLAQA1AAQKfxoAAgEACQqjG6EsAHoBAAEACQqjG6EsAHoBAAAA.Bowdaddy:BAABNQAECn8eAAIMAAgKmhRzRgAoAQAMAAgKmhRzRgAoAQAAAA==.',
Br='Breakdown:BAABNQAECn8WAAIGAAYKXAlOCwDHAAAGAAYKXAlOCwDHAAAAAA==.Brewsimmons:BAAANQADCggIEAABNQAFFAcIFAANAJQKAA==.',
Bu='Bublz:BAAANQADCgIIAgAAAA==.Bumpinuglies:BAAANQADCgYICQAAAA==.',
Ca='Cailey:BAAANQAECggICgABNQAECggICgADAAAAAA==.Calcshortfor:BAAANQADCgQIBAAAAA==.Callamdrake:BAAANQADCgQJBQAAAA==.Callamsvoid:BAAANQAECgEIAQAAAA==.Calyrex:BAAANQADCgEIAQAAAA==.Camazotz:BAAANQAECgcICAAAAA==.Capulse:BAACNQAFFH8QAAIOAAUK0xkpCwCaAQAOAAUK0xkpCwCaAQA1AAQKfxoABA4ACAo6HvxgAOsBAA4ABgqeIvxgAOsBAA8ABQr/FFpJALIAABAAAQoMAnwhADcAAAAA.Careglobo:BAAANQAECgEIAQAAAA==.Caylen:BAAANQAECggIAgABNQAFFAUIEAAOANMZAA==.',
Ce='Centri:BAABNQAECn8iAAMRAAkKNiGGBQC4AgARAAcKWCKGBQC4AgASAAkKTxsNfgCCAgAAAA==.',
Ch='Chowa:BAAANQAECgEIAQAAAA==.',
Cl='Clapdatazz:BAAANQAECggICwAAAA==.Cleverlev:BAAANQADCggIDAABNQAFFAMIBQATAHILAA==.',
Co='Colapse:BAAANQADCgMIAwAAAA==.',
Cr='Crunchrr:BAAANQADCgEIAQAAAA==.',
Cu='Cubensis:BAAANQADCgcJFgAAAA==.',
Cy='Cyiera:BAAANQAECggICgAAAA==.',
Da='Daeland:BAAANQAECgcIDwAAAA==.Daisyshot:BAABNQAECn83AAMMAAoKMiClBQBzAgAMAAkKbiGlBQBzAgAUAAYKYBkQPABwAQAAAA==.Dalsham:BAAANQADCggIBgAAAA==.',
De='Deathsgrace:BAAANQADCggICgAAAA==.Decima:BAABNQAECn8cAAIHAAkKJgcRWQBwAQAHAAkKJgcRWQBwAQAAAA==.Dejustinfox:BAAANQADCgQIBwAAAA==.Demeter:BAACNQAFFH8NAAMUAAYKohddBQDgAAAUAAQK4xVdBQDgAAAMAAMK+hmhEwBkAAA1AAQKfxwAAxQACgpRHsEgAEgCABQACQqgHcEgAEgCAAwABArJFVkBAQIBAAAA.Demonpunter:BAABNQAECn8bAAIVAAcKaB5WJgBrAgAVAAcKaB5WJgBrAgABNQAFFAUIEAAWACAlAA==.',
Di='Diabloa:BAAANQADCgQICAAAAA==.Diamba:BAAANQAECgUIBwAAAA==.Dinoscarr:BAAANQAECgQIBAAAAA==.',
Do='Doohickey:BAAANQAECgYICgABNQAECgYICwADAAAAAA==.Doohicky:BAAANQAECgYICwAAAA==.Dorgrim:BAAANQADCgMIAwAAAA==.Dotsndash:BAABNQAECn8vAAIXAAoKXxiIBgCPAQAXAAoKXxiIBgCPAQAAAA==.',
Du='Dungpoo:BAAANQADCgEIAQAAAA==.',
Ea='Eargox:BAAANQAECgMIBAAAAA==.',
Ee='Eesa:BAAANQAECggICQAAAA==.',
El='Elinia:BAAANQADCgMIBAAAAA==.Elleteliara:BAAANQAECgEIAQAAAA==.Elmdor:BAAANQAECgQIAwAAAA==.Elyndra:BAAANQAECgUICQAAAA==.',
En='Eniacoc:BAAANQAECgEIAQAAAA==.',
Ev='Everas:BAAANQAECgMIAwAAAA==.',
Ex='Excentric:BAAANQAECgIIAgABNQAECgkJIgARADYhAA==.Excentrics:BAAANQADCgUIBQABNQAECgkJIgARADYhAA==.',
Fa='Faithlyn:BAAANQADCgEIAQABNQAECgIIAgADAAAAAA==.Falarth:BAABNQAECn8aAAIYAAcKJRXJVAChAQAYAAcKJRXJVAChAQAAAA==.Falloutman:BAABNQAECn8YAAICAAgKwhsNBADQAQACAAgKwhsNBADQAQAAAA==.Farther:BAAANQADCgUICQABNQAFFAYIFgASANQbAA==.Fayne:BAAANQADCgcICQAAAA==.',
Fe='Felfart:BAAANQADCgUIBQAAAA==.',
Fi='Firefox:BAACNQAFFH8FAAIYAAIKXhEnIwByAAAYAAIKXhEnIwByAAA1AAQKfxwAAhgACgofGHs3ACsCABgACgofGHs3ACsCAAE1AAUUBQgHABkALhgA.',
Fl='Flechillas:BAAANQADCgcIDQAAAA==.Flán:BAABNQAECn8YAAIaAAkKBhDJKgDGAQAaAAkKBhDJKgDGAQAAAA==.',
Fr='Fraternite:BAAANQAECgQIBwAAAA==.',
Fu='Furrymoon:BAAANQADCgcIBwAAAA==.',
Ga='Gabriellad:BAAANQAECgQICAAAAA==.',
Ge='Gerrakha:BAAANQADCgYIBgABNQAECgEIBQADAAAAAA==.',
Gi='Giterdonee:BAACNQAFFH8PAAMEAAYKZRP4BQAgAQAEAAQKZRP4BQAgAQAGAAIKAADcAgCpAAA1AAQKfyYAAwYACgoiH5oFAMYCAAYACgp8HZoFAMYCAAQABgp+F4GxAKEBAAAA.',
Go='Gorr:BAAANQADCgMIBgABNQAECgIIAgADAAAAAA==.Gotchoo:BAABNQAECn8cAAIIAAgKIRFPJwADAQAIAAgKIRFPJwADAQABNQAECgIIAgADAAAAAA==.Gothmommy:BAABNQAECn8pAAIbAAgKQxzPQgBhAgAbAAgKQxzPQgBhAgAAAA==.',
Gr='Grilledchis:BAAANQADCgIIAgAAAA==.Groldin:BAAANQAECggICAAAAA==.Grumble:BAAANQAECgQIBAAAAA==.',
['Gõ']='Gõtchoo:BAAANQAECgIIAgAAAA==.',
Ha='Hairball:BAABNQAECn8VAAIcAAgKyhHRBwDqAQAcAAgKyhHRBwDqAQAAAA==.Hammerthumb:BAAANQADCgcICQABNQAECggIHQAHAOYKAA==.Hardawn:BAAANQABCgEIAQABNQAFFAYIFgASANQbAA==.',
Ho='Hotsoup:BAAANQADCgQJBAAAAA==.Hozzluzzak:BAAANQADCggICAAAAA==.',
Hy='Hyara:BAABNQAECn88AAIMAAoKvCKGCACZAwAMAAoKvCKGCACZAwAAAA==.',
['Hù']='Hùñtarð:BAAANQAECgEIAgAAAA==.',
Ic='Iceagent:BAAANQABCgMIAwAAAA==.',
Im='Imnaked:BAAANQADCgYIBgAAAA==.',
In='Invisimitch:BAAANQADCgEIAQAAAA==.',
Ip='Ips:BAAANQADCgIIAgABNQADCgUIBQADAAAAAA==.',
Ji='Jifman:BAAANQADCgYIBgAAAA==.',
Jo='Joffrey:BAAANQADCgYIBgAAAA==.Jordi:BAABNQAECn8pAAIMAAgKxx5nPwCsAgAMAAgKxx5nPwCsAgAAAA==.Jotarcyon:BAAANQABCgIJAgAAAA==.',
Ju='Jukkes:BAAANQADCggIEwAAAA==.Justinfox:BAAANQADCgEIAQAAAA==.Juukess:BAAANQAECgIIAgAAAA==.',
Ka='Kannarri:BAAANQAECgMIBgAAAA==.Kanree:BAACNQAFFH8VAAITAAYKFwW2AgD8AAATAAYKFwW2AgD8AAA1AAQKfzwAAhMACgqnErQXAAICABMACgqnErQXAAICAAAA.Kayaa:BAAANQADCggICAAAAA==.',
Ke='Kea:BAACNQAFFH8NAAMbAAQKlx9BBgB8AQAbAAQK/x1BBgB8AQAdAAQK2xo7AQBvAQA1AAQKf0sABB0ACgqFJVQAAMEDAB0ACQoGJVQAAMEDABsACgpaJSAFAKADABcABAonGSc+ADsBAAAA.Kek:BAABNQAECn8VAAIIAAcKewc0KQD6AAAIAAcKewc0KQD6AAAAAA==.',
Kh='Khaalid:BAAANQADCgQIBAABNQAECgoKJQAFAGMfAA==.Kharok:BAABNQAECn8lAAQGAAkKAyGtAQDuAQAeAAgK9iDNCADDAgAGAAgKzRqtAQDuAQAEAAYKVRjxpgC8AQABNQAECgoKJQAFAGMfAA==.',
Ki='Killhordex:BAAANQADCgIIAgAAAA==.Kincane:BAAANQADCgcICQAAAA==.',
Ko='Korxin:BAACNQAFFH8MAAMMAAYKxRH+GgDiAAAMAAQKDBT+GgDiAAAUAAQKBgeQCACWAAA1AAQKfzMAAwwACgrHIQYzANMCAAwACgrHIQYzANMCABQABwrqDb89AGUBAAAA.Kota:BAAANQADCgEIAQAAAA==.',
Ku='Kurnhaspios:BAAANQADCgQIBAAAAA==.Kurquaan:BAAANQAECgMIBAAAAA==.',
Ky='Kydraeth:BAAANQAECgEIAQAAAA==.',
La='Lanstyn:BAABNQAECn8vAAIdAAgK6RnTBAByAgAdAAgK6RnTBAByAgABNQAECgoKJQAFAGMfAA==.Laufey:BAABNQAECn8qAAISAAgKyhXbXQACAQASAAgKyhXbXQACAQAAAA==.',
Le='Lemone:BAAANQADCgUIBQAAAA==.Lemonsk:BAAANQADCgUICAAAAA==.Lennox:BAAANQADCgQIBAAAAA==.Lenton:BAAANQAECgEIAQAAAA==.',
Li='Lightfury:BAAANQADCgYIDAAAAA==.Limone:BAAANQAECgEIAQAAAA==.Listradra:BAAANQADCgQIBAAAAA==.',
Lo='Loganwater:BAAANQADCgQIBAAAAA==.Loinari:BAAANQADCgUIDQAAAA==.Lokano:BAAANQADCgIIAgAAAA==.',
Lu='Ludmylha:BAAANQAECgIIBAAAAA==.Luisda:BAAANQADCggIFwAAAA==.Lull:BAAANQADCggIEQAAAA==.Lushil:BAAANQAFFAEIAQAAAA==.',
Ly='Lyrea:BAAANQAECggICAAAAA==.',
Ma='Magidragon:BAAANQADCgQIBAAAAA==.Man:BAAANQADCgUIBQAAAA==.Marsangel:BAAANQADCgEIAQAAAA==.Maxerella:BAAANQADCgUIBQAAAA==.Maybell:BAAANQAECgQICQAAAA==.',
Me='Meepmeepmomp:BAAANQADCgUIBQAAAA==.Megumín:BAAANQAECgEIAQAAAA==.Melt:BAACNQAFFH8ZAAQLAAYKFxkvAgCrAAALAAIK5xgvAgCrAAAKAAMKRxniDQCnAAAWAAEKAAA6CQBcAAA1AAQKfzkAAwoACgqwHlQkAPMCAAoACQooHlQkAPMCAAsABArrIFAgAG4BAAAA.Mepha:BAACNQAFFH8OAAIJAAUKZxL/AgDvAAAJAAUKZxL/AgDvAAA1AAQKfyQAAwkACgqpHJk/AB8CAAkACQqpHJk/AB8CAAgACArhDJ9LAIsBAAAA.Meridia:BAAANQADCgMIAwAAAA==.',
Mi='Miike:BAAANQADCgEIAQABNQAFFAYIFgASANQbAA==.Mike:BAACNQAFFH8WAAISAAYK1BsZBQBbAQASAAYK1BsZBQBbAQA1AAQKf1kAAxIACgoEJAITAIcDABIACgoEJAITAIcDABEABQqUD0cfAPAAAAAA.Mikevoker:BAAANQADCgEIAQABNQAFFAYIFgASANQbAA==.Mipz:BAAANQADCgUIBQAAAA==.Misfitdk:BAAANQAECggIAgAAAA==.Misfitmagi:BAAANQAECgIIAgAAAA==.Misfittotem:BAAANQAECgIIAQAAAA==.Mistfox:BAAANQADCgYIDAAAAA==.Mistmommy:BAABNQAECn8kAAITAAkKdhHDGwDHAQATAAkKdhHDGwDHAQAAAA==.',
Mo='Mollieann:BAAANQAECgIIAgAAAA==.Mommon:BAAANQADCgEIAQAAAA==.Morrighan:BAAANQADCgMIAwAAAA==.',
['Mâ']='Mâlus:BAAANQAECgUICAAAAA==.',
['Mä']='Märs:BAAANQADCgYICgAAAA==.',
Na='Nadra:BAAANQAECgIIAQAAAA==.Naminé:BAAANQADCgQIBAABNQAECggIKgASAMoVAA==.Naroka:BAAANQAECgQIBQAAAA==.Nattyrav:BAACNQAFFH8IAAIPAAQKGRUpEwA/AQAPAAQKGRUpEwA/AQA1AAQKfyUAAw8ACQp/Ghg9AIECAA8ACQp/Ghg9AIECAA4AAQpQHW0LAVEAAAAA.',
Ne='Neemesis:BAAANQAECgQIBAAAAA==.Nemonk:BAAANQAECggIDAABNQAECggIEAADAAAAAA==.Nemoz:BAAANQAECggIEAAAAA==.Nerfling:BAAANQADCgYICAAAAA==.',
No='Nocter:BAAANQAECgUIBQAAAA==.Noktor:BAAANQADCgYIBgAAAA==.Noktra:BAAANQAECgUIDwAAAA==.Nosey:BAAANQADCgUIBQAAAA==.',
Ny='Nylah:BAAANQAECgYIBgABNQAFFAUIEAALAIUSAA==.Nymura:BAABNQAECn8eAAIBAAcKVg6TWQARAQABAAcKVg6TWQARAQAAAA==.',
Oa='Oakhugger:BAABNQAECn8dAAQHAAgK5gr6IQDhAAAHAAYKiQn6IQDhAAAfAAQKigrmLgCbAAAgAAIKqwPFWwA+AAAAAA==.',
Ol='Olyvivia:BAAANQADCgUIBQAAAA==.',
Om='Omgega:BAABNQAECn8jAAIBAAgKxhMbmQDxAQABAAgKxhMbmQDxAQAAAA==.',
On='Onichan:BAAANQAECgEIAQABNQAFFAcIFQAPAOMbAA==.Onimeek:BAABNQAECn8xAAIVAAoKURfyJQBuAgAVAAoKURfyJQBuAgAAAA==.Onionknightt:BAAANQAECgEIAQAAAA==.',
Or='Oryn:BAAANQAECggIEQABNQAFFAEIAQADAAAAAA==.Oryx:BAAANQADCgEIAQAAAA==.',
Os='Osoloco:BAAANQADCgUIAwAAAA==.',
Pa='Palmpower:BAAANQADCgYICQAAAA==.Palpitations:BAAANQAECgEIAQAAAA==.Paper:BAAANQAFFAUIDwAAAQ==.',
Pe='Peacefullev:BAACNQAFFH8FAAITAAMKcgtwAwC6AAATAAMKcgtwAwC6AAA1AAQKfysAAhMACgppHIoJAPICABMACgppHIoJAPICAAAA.Pepegá:BAAANQAECgIIAQAAAA==.Pewpewpew:BAAANQAECgUICQAAAA==.',
Ph='Phantomthief:BAAANQAECggICAAAAA==.',
Pi='Pipeleto:BAABNQAECn8/AAIEAAoK4B6KCgAVAgAEAAoK4B6KCgAVAgAAAA==.Pizzaroll:BAABNQAECn82AAIhAAoKdhQIBQCiAgAhAAoKdhQIBQCiAgAAAA==.',
Po='Podvoddonut:BAAANQADCgYIBgAAAA==.',
Pr='Previdius:BAAANQADCgUIBQAAAA==.Priesstess:BAAANQADCgYICQAAAA==.',
['Pé']='Pépega:BAAANQADCgQIBwAAAA==.',
Ri='Riellus:BAAANQAECgMIAgAAAA==.Riiu:BAAANQAECgYIBwABNQAECgkJNQABAPckAA==.Riven:BAAANQADCgYIBgAAAA==.Rixin:BAECNQAFFH8NAAMJAAUKFB5FBACzAAAJAAQKFB5FBACzAAAYAAEKAACbOwAcAAA1AAQKfy0AAgkACgqAHW8bAOcCAAkACgqAHW8bAOcCAAAA.',
Ro='Rokom:BAACNQAFFH8JAAMGAAMK2BmyAgCyAAAGAAIK/yGyAgCyAAAEAAEKsBGWPABHAAA1AAQKfygAAwYACgrjG+MNANUBAAYABwoCHeMNANUBAAQABAptGDHqABABAAAA.Roonrano:BAAANQADCggJCAAAAA==.',
Ru='Rumpus:BAAANQADCgcIBwAAAA==.Runed:BAAANQAECgEIAQAAAA==.',
Ry='Ryuk:BAAANQADCgYICgAAAA==.',
Sa='Salla:BAAANQADCgYICQAAAA==.Sanlennicus:BAAANQAECgIIAgAAAA==.Saphh:BAAANQAECgEIAQABNQAFFAQIDwAIAHIYAA==.Saudencheek:BAAANQAECgQIBAAAAA==.',
Se='Seanster:BAABNQAECn8eAAMiAAkK+xKkIgBxAgAiAAkK+xKkIgBxAgAjAAMKQQJhGABeAAABNQAFFAUIEAALAIUSAA==.Senecca:BAABNQAECn8oAAIHAAkK9Rr6IADFAgAHAAkK9Rr6IADFAgAAAA==.',
Sh='Shadowlily:BAAANQADCgMIAwABNQADCggIJAADAAAAAA==.Shadowms:BAABNQAECn8pAAIkAAoKbBmvBQB/AQAkAAoKbBmvBQB/AQAAAA==.Shadowxd:BAABNQAECn8nAAQlAAoKqBuCBwDJAQAlAAoKqBuCBwDJAQAgAAEKAACJYAAzAAAHAAEKHAYOugAmAAAAAA==.Shamanpwnz:BAAANQAECgQIBgAAAA==.Shambassador:BAAANQAECggIEQAAAA==.Shamwowha:BAAANQADCgQIBAAAAA==.Sharkdancer:BAABNQAECn8UAAImAAkKaB6OFQC4AgAmAAkKaB6OFQC4AgABNQAFFAYIDgATAJMhAA==.Shaulana:BAAANQADCggIJAAAAA==.Shenwu:BAABNQAECn8dAAIFAAkKLxfRDQAcAgAFAAkKLxfRDQAcAgAAAA==.Shirokuma:BAACNQAFFH8RAAMHAAUKdRhWBgD6AAAHAAQKdRhWBgD6AAAgAAEKAADwCABfAAA1AAQKfyMAAwcACgrOGrsaAPMCAAcACgrOGrsaAPMCACAAAQrxFz5VAFAAAAAA.Shocktopuus:BAAANQADCgQIBAAAAA==.Shwizzle:BAAANQADCggIDgAAAA==.',
Si='Sidvicious:BAAANQADCgUIBAAAAA==.',
Sk='Sköllati:BAAANQAECgQIBAAAAA==.',
Sl='Slingshotz:BAAANQAECgEIAQAAAA==.',
Sm='Smarty:BAAANQAECgUIBAAAAA==.',
Sn='Sneakylev:BAABNQAECn8oAAMnAAkKjhNXGQAUAQAnAAgKxA1XGQAUAQAiAAQKfBOYIQDNAAABNQAFFAMIBQATAHILAA==.',
So='Solari:BAABNQAECn83AAMmAAoKqiT0AgCrAwAmAAoKqiT0AgCrAwAZAAUKIBhkFwA4AQAAAA==.Soleon:BAAANQAECgYIDgAAAA==.Solune:BAAANQAECgYIDAAAAA==.Souprage:BAAANQAECgMIBgAAAA==.',
Sp='Spypal:BAAANQADCgYIDAAAAA==.',
St='Stabwei:BAAANQADCggICAAAAA==.',
Su='Sugirokimami:BAAANQAECgQICAABNQAECgUIBwADAAAAAA==.',
Sw='Swagmastrflx:BAAANQADCgQIBAAAAA==.Swëëtdee:BAAANQADCgMICAAAAA==.',
Ta='Taehausx:BAAANQAFFAEIAQABNQAFFAYICQACABgTAA==.Taraka:BAAANQAECgQIBAAAAA==.',
Td='Tdolokk:BAAANQADCggIFwAAAA==.',
Te='Teeward:BAAANQADCgYIBgAAAA==.Tenath:BAAANQAECgUICQAAAA==.Terribleturd:BAAANQAECgEIAQAAAA==.',
Th='Thaleon:BAAANQADCggICAAAAA==.Thauriel:BAAANQAECgEIAQAAAA==.Theexecution:BAAANQAECgMIAQAAAA==.Therella:BAAANQADCgUIBQAAAA==.',
To='Totemtotebag:BAABNQAECn8XAAIOAAQK7BdpsAAOAQAOAAQK7BdpsAAOAQABNQAECgoKKAAgALkkAA==.',
Tr='Treshaleth:BAAANQADCgQIBAAAAA==.Tripodg:BAAANQAECgQICQAAAA==.Trollztoll:BAAANQADCgIIAgAAAA==.',
Tw='Twiddletime:BAAANQAECgQIBgAAAA==.',
['Tï']='Tïggy:BAAANQAECgQIBgAAAA==.',
Un='Una:BAAANQAECgYIDQAAAA==.Unholymisfit:BAAANQAECgIIBQAAAA==.Unholytato:BAAANQADCgQIBAAAAA==.',
Ur='Ursok:BAAANQAECgEIAQABNQAECgoKJQAFAGMfAA==.',
Ut='Uthok:BAAANQADCgEJAQAAAA==.',
Uz='Uzol:BAAANQADCgcICAAAAA==.',
Va='Vacalocà:BAAANQAECgIIAgAAAA==.Valerian:BAAANQAECgcIEQAAAA==.Van:BAAANQADCgQIBAAAAA==.',
Ve='Veinke:BAABNQAECn8YAAIZAAgKJRk0CwAfAgAZAAgKJRk0CwAfAgAAAA==.Velanthir:BAAANQADCggIFAAAAA==.Verd:BAEANQAFFAEIAQAAAA==.Veronica:BAAANQABCgYIBgAAAA==.Versaacee:BAAANQADCgYIBgAAAA==.Vessarind:BAAANQADCgUIBQAAAA==.',
Vi='Vivrian:BAAANQADCgUIBQAAAA==.',
['Vä']='Vänillaicë:BAAANQADCgcIBwABNQADCggIJAADAAAAAA==.',
Wa='Waally:BAAANQAECgQIBQAAAA==.Wahwoo:BAAANQADCggIDgABNQADCggIJAADAAAAAA==.',
We='Weebsora:BAAANQAECgQIBQAAAA==.',
Wo='Worldtree:BAAANQADCgEIAQAAAA==.',
Xa='Xaelthira:BAAANQADCgcIBwAAAA==.',
Ya='Yadhi:BAABNQAECn8lAAIFAAoKYx//AgBrAwAFAAoKYx//AgBrAwAAAA==.',
Yi='Yimomo:BAABNQAECn8pAAIbAAkKKh6iNACVAgAbAAkKKh6iNACVAgAAAA==.',
Za='Zalconn:BAABNQAECn8nAAMnAAkK0yOYAgBSAgAnAAgKmCOYAgBSAgAiAAQKVyHeUgBxAQAAAA==.Zarrona:BAAANQAECgIIAwABNQAECggIKgASAMoVAA==.Zayah:BAAANQAFFAIIAwAAAA==.',
Zi='Zikony:BAAANQAECgUIBQAAAA==.',
Zu='Zuber:BAABNQAECn83AAIiAAoK8SAVAQDHAgAiAAoK8SAVAQDHAgAAAA==.',
['År']='Årtimus:BAAANQADCgYIDAAAAA==.',
['Öw']='Öwö:BAAANQAECgQIBAAAAA==.',
['Üw']='Üwü:BAABNQAECn8ZAAMNAAgKphjXEADPAQANAAgKphjXEADPAQABAAQKmRBrHAHvAAAAAA==.',
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
