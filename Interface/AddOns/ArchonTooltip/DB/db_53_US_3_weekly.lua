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

local lookup = {'Paladin-Retribution','Paladin-Protection','Warrior-Arms','Unknown-Unknown','Priest-Discipline','Warrior-Fury','Druid-Balance','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Shaman-Restoration','Mage-Arcane','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Affliction','Priest-Shadow','DeathKnight-Blood','Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost','Mage-Frost','Shaman-Elemental','Druid-Feral','Druid-Guardian','DemonHunter-Havoc','Evoker-Augmentation','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation','Monk-Brewmaster','Rogue-Subtlety','DemonHunter-Devourer','DemonHunter-Vengeance',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=53,date='2026-10-06',data={Ae='Aegrias:BAABNQAECoEaAAIBAAkK5B6YMgDhAgABAAkK5B6YMgDhAgAAAA==.Aerodria:BAABNQAECoEsAAICAAkKOxtzDQChAgACAAkKOxtzDQChAgAAAA==.',
Al='Alanril:BAAANQADCgMIAwAAAA==.Alarthevel:BAAANQAECgMIBAAAAA==.Albince:BAAANQADCgQIBAAAAA==.',
Am='Amellis:BAAANQADCgIIAgAAAA==.',
An='Andreaswar:BAAANQAECgMIAwAAAA==.Anniferal:BAAANQAECgMIBAABNQAFFAUICQADAPIcAA==.Annisseda:BAACNQAFFIEJAAIDAAUK8hxKCwDKAQADAAUK8hxKCwDKAQA1AAQKgRYAAgMACAoiIh1DAKgCAAMACAoiIh1DAKgCAAAA.Anzak:BAAANQAECgQIBQAAAA==.',
Ar='Ardrayshock:BAAANQABCgcJCgAAAA==.Arrhythmia:BAAANQAECgIIAgABNQAFFAQICQAEAAAAAQ==.',
As='Astrayn:BAAANQADCgIIAgAAAA==.',
Az='Azala:BAAANQAECgIIAgAAAA==.Azryx:BAAANQADCgcICQABNQAECggILwAFAOkZAA==.Azzy:BAACNQAFFIENAAIDAAUKhA86EACFAQADAAUKhA86EACFAQA1AAQKgTUAAwMACQq4JNQLAJIDAAMACQpeJNQLAJIDAAYACQonIbcCACgDAAAA.',
Ba='Bananski:BAAANQADCgcIBwAAAA==.',
Be='Beefychunks:BAAANQAECgYIEwAAAA==.',
Bi='Bigdraco:BAAANQADCgQIBQAAAA==.Biggums:BAAANQADCgQIBAAAAA==.Billyspikepd:BAAANQAECgUIDQAAAA==.Billyspikepr:BAAANQADCggIDQABNQAECgUIDQAEAAAAAA==.Billyspikerg:BAAANQAECgUIBwABNQAECgUIDQAEAAAAAA==.',
Bl='Black:BAAANQADCgIIAgAAAA==.Blobcat:BAABNQAECoEZAAIHAAgKPxWbNgAOAgAHAAgKPxWbNgAOAgAAAA==.Blobknight:BAAANQAECgUIBQAAAA==.Bloodhase:BAAANQAECggIEgAAAA==.Bluecard:BAACNQAFFIEGAAMIAAQK6BFDHADkAAAIAAMKahFDHADkAAAJAAEKYhPsFgBTAAA1AAQKgRsAAwgACQpqHt1OAEgCAAgABwrMHt1OAEgCAAkAAwquFUVCALAAAAAA.',
Bo='Bothenheim:BAABNQAFFIEJAAIBAAUKERyQBQDcAQABAAUKERyQBQDcAQAAAA==.Bowdaddy:BAAANQAECgYIDQAAAA==.',
Br='Breakdown:BAAANQAECgUIDQAAAA==.Brewsimmons:BAAANQADCggIEAABNQAFFAcIEwAKAJQKAA==.',
Bu='Bublz:BAAANQADCgIIAgAAAA==.Bumpinuglies:BAAANQADCgMIAwAAAA==.',
Ca='Cailey:BAAANQAECggICgABNQAECggICgAEAAAAAA==.Calcshortfor:BAAANQADCgQIBAAAAA==.Callamdrake:BAAANQADCgQJBQAAAA==.Callamsvoid:BAAANQAECgEIAQAAAA==.Calyrex:BAAANQADCgEJAQAAAA==.Camazotz:BAAANQADCgYIBgAAAA==.Capulse:BAABNQAFFIEJAAILAAUKSBViCQCZAQALAAUKSBViCQCZAQAAAA==.',
Ce='Centri:BAABNQAECoEbAAIMAAkKOhuDZQCfAgAMAAkKOhuDZQCfAgAAAA==.',
Ch='Chowa:BAAANQAECgEIAQAAAA==.',
Cl='Clapdatazz:BAAANQAECgQICAAAAA==.Cleverlev:BAAANQADCgUIBwABNQAECggIHQANALIeAA==.',
Co='Colapse:BAAANQADCgMIAwAAAA==.',
Cr='Crunchrr:BAAANQADCgEIAQAAAA==.',
Cu='Cubensis:BAAANQADCgcJFgAAAA==.',
Cy='Cyiera:BAAANQAECggICgAAAA==.',
Da='Daeland:BAAANQAECgEIAQAAAA==.Daisyshot:BAABNQAECoEuAAMOAAkKOSO8EQBFAwAOAAgKryS8EQBFAwAPAAYKERzvNAB6AQAAAA==.',
De='Deathsgrace:BAAANQADCggICQAAAA==.Decima:BAABNQAECoEZAAIHAAgKNQelTwB1AQAHAAgKNQelTwB1AQAAAA==.Dejustinfox:BAAANQADCgQIBwAAAA==.Demeter:BAACNQAFFIEIAAMPAAUKBw0tEAANAQAPAAQKqw4tEAANAQAOAAIKyQ7uIACaAAA1AAQKgRkAAw8ACQq1HUkbAF8CAA8ACAoGHUkbAF8CAA4ABArJFePkAAYBAAAA.Demonpunter:BAAANQAECgUIEgABNQAFFAUIDAAQAEsjAA==.',
Di='Diabloa:BAAANQADCgQICAAAAA==.Diamba:BAAANQAECgIIAgAAAA==.Dinoscarr:BAAANQAECgQIBAAAAA==.',
Do='Doohickey:BAAANQAECgIIAgAAAA==.Doohicky:BAAANQAECgYIBgAAAA==.Dorgrim:BAAANQADCgMIAwAAAA==.Dotsndash:BAABNQAECoEoAAIRAAkK7hhEFACiAgARAAkK7hhEFACiAgAAAA==.',
Dp='Dpsshaman:BAAANQABCgYIBgABNQAFFAUIDwAPAE8VAA==.',
Du='Dungpoo:BAAANQADCgEIAQAAAA==.',
Ea='Eargox:BAAANQAECgMIBAAAAA==.',
Ee='Eesa:BAAANQAECggICQAAAA==.',
El='Elinia:BAAANQADCgMIBAAAAA==.Elmdor:BAAANQAECgMIAwAAAA==.Elyndra:BAAANQAECgMIBQAAAA==.',
En='Eniacoc:BAAANQAECgEIAQAAAA==.',
Ex='Excentric:BAAANQAECgIIAgABNQAECgkJGwAMADobAA==.',
Fa='Faithlyn:BAAANQADCgEIAQABNQAECgEIAQAEAAAAAA==.Falarth:BAAANQAECgUIEQAAAA==.Falloutman:BAAANQAECgUICAAAAA==.Farther:BAAANQADCgUICQABNQAFFAUIDgAMAMwTAA==.Fayne:BAAANQADCgcICQAAAA==.',
Fe='Felfart:BAAANQADCgUIBQAAAA==.',
Fi='Firefox:BAACNQAFFIEFAAISAAIKXhFoHQB8AAASAAIKXhFoHQB8AAA1AAQKgRkAAhIACQq1GMAuADwCABIACQq1GMAuADwCAAAA.',
Fl='Flechillas:BAAANQADCgcIDQAAAA==.Flán:BAAANQAECgUICgAAAA==.',
Fr='Fraternite:BAAANQAECgMIAwAAAA==.',
Fu='Furrymoon:BAAANQADCgcIBwAAAA==.',
Ga='Gabriellad:BAAANQAECgEIAQAAAA==.',
Ge='Gerrakha:BAAANQADCgYIBgABNQAECgEIAQAEAAAAAA==.',
Gi='Giterdonee:BAACNQAFFIEJAAMGAAUKexIrAgCzAAADAAMKiBCtHQDeAAAGAAIKZxUrAgCzAAA1AAQKgSMAAwYACQqZHx0EAN4CAAYACQoiHh0EAN4CAAMABgrDFVuaALEBAAAA.',
Go='Gotchoo:BAAANQAECgQIDwABNQADCgQIBAAEAAAAAA==.Gothmommy:BAABNQAECoEgAAITAAgKQxz0NQBuAgATAAgKQxz0NQBuAgAAAA==.',
Gr='Grilledchis:BAAANQADCgIIAgAAAA==.Groldin:BAAANQADCgEIAQABNQADCgQIBAAEAAAAAA==.Grumble:BAAANQAECgQIBAAAAA==.',
['Gõ']='Gõtchoo:BAAANQADCgQIBAAAAA==.',
Ha='Hairball:BAAANQAECgUIDQAAAA==.Hammerthumb:BAAANQADCgcICQABNQAECgcIFgAHADgMAA==.Hardawn:BAAANQABCgEIAQABNQAFFAUIDgAMAMwTAA==.',
Ho='Hotsoup:BAAANQADCgQJBAAAAA==.Hozzluzzak:BAAANQADCggICAAAAA==.',
Hy='Hyara:BAABNQAECoE0AAIOAAkKsyOcBwCTAwAOAAkKsyOcBwCTAwAAAA==.',
['Hù']='Hùñtarð:BAAANQAECgEIAgAAAA==.',
Ic='Iceagent:BAAANQABCgMIAwAAAA==.',
Im='Imnaked:BAAANQADCgYIBgAAAA==.',
In='Invisimitch:BAAANQADCgEIAQAAAA==.',
Ip='Ips:BAAANQADCgIIAgABNQADCgUIBQAEAAAAAA==.',
Jo='Jordi:BAABNQAECoEdAAIOAAgKxRtWPgCLAgAOAAgKxRtWPgCLAgAAAA==.Jotarcyon:BAAANQABCgIJAgAAAA==.',
Ju='Jukkes:BAAANQADCgcICwAAAA==.Justinfox:BAAANQADCgEIAQAAAA==.Juukess:BAAANQAECgIIAgAAAA==.',
Ka='Kannarri:BAAANQAECgEIAQAAAA==.Kanree:BAACNQAFFIEOAAINAAUKDwTRBABLAQANAAUKDwTRBABLAQA1AAQKgTUAAg0ACQq8ErQUAAQCAA0ACQq8ErQUAAQCAAAA.Kayaa:BAAANQADCggICAAAAA==.',
Ke='Kea:BAACNQAFFIEFAAMFAAIKxRYeAgCgAAAFAAIKxRYeAgCgAAATAAEKbBYTKQBZAAA1AAQKgTkABAUACQoSJVEAALEDAAUACQqFI1EAALEDABMACQoWJHcGAIMDABEAAwp9EoNQAKIAAAAA.Kek:BAAANQAECgUIBwAAAA==.',
Kh='Khaalid:BAAANQADCgQIBAABNQAECggILwAFAOkZAA==.Kharok:BAAANQAECgcIEgABNQAECggILwAFAOkZAA==.',
Ki='Kincane:BAAANQADCgcICQAAAA==.',
Ko='Korxin:BAACNQAFFIEHAAMOAAUKFg+TFADtAAAOAAMKtg6TFADtAAAPAAIKpg/yFgCYAAA1AAQKgS4AAw4ACQp7IYQlAOICAA4ACQp7IYQlAOICAA8ABgquD6k4AFwBAAAA.Kota:BAAANQADCgEIAQAAAA==.',
Ku='Kurnhaspios:BAAANQADCgQIBAAAAA==.Kurquaan:BAAANQAECgMIBAAAAA==.',
Ky='Kydraeth:BAAANQADCgcIEgAAAA==.',
La='Lanstyn:BAABNQAECoEvAAIFAAgK6RkSBACAAgAFAAgK6RkSBACAAgAAAA==.Laufey:BAABNQAECoEcAAIMAAUKnBvE9AB8AQAMAAUKnBvE9AB8AQAAAA==.',
Le='Lemone:BAAANQADCgUIBQAAAA==.Lemonsk:BAAANQADCgUICAAAAA==.Lennox:BAAANQADCgQIBAAAAA==.Lenton:BAAANQAECgEIAQAAAA==.',
Li='Lightfury:BAAANQADCgYIDAAAAA==.Limone:BAAANQAECgEIAQAAAA==.Listradra:BAAANQADCgQIBAAAAA==.',
Lo='Loganwater:BAAANQADCgQIBAAAAA==.Loinari:BAAANQADCgUICwAAAA==.Lokano:BAAANQADCgIIAgAAAA==.',
Lu='Ludmylha:BAAANQAECgIIBAAAAA==.Luisda:BAAANQADCggIFwAAAA==.Lull:BAAANQADCggIEQAAAA==.Lushil:BAAANQAFFAEIAQAAAA==.',
Ly='Lyrea:BAAANQAECggICAAAAA==.',
Ma='Man:BAAANQADCgUIBQAAAA==.Marsangel:BAAANQADCgEIAQAAAA==.Maybell:BAAANQAECgEIAQAAAA==.',
Me='Meepmeepmomp:BAAANQADCgUIBQAAAA==.Megumín:BAAANQADCgUIBQAAAA==.Melt:BAACNQAFFIEOAAQJAAUKUhcRCwClAAAJAAIKoRMRCwClAAAIAAIK4ha4JgCeAAAQAAEKlh/0BgBeAAA1AAQKgTIAAwgACQrjIsQcAPwCAAgACAryIsQcAPwCAAkABAqhIXEeAHMBAAAA.Mepha:BAACNQAFFIEGAAIUAAMKJw/IDwDcAAAUAAMKJw/IDwDcAAA1AAQKgR8AAxQACQozGT44AB8CABQACAp4Gz44AB8CABUACAq0DCo9AJYBAAAA.Meridia:BAAANQADCgMIAwAAAA==.',
Mi='Miike:BAAANQADCgEIAQABNQAFFAUIDgAMAMwTAA==.Mike:BAACNQAFFIEOAAIMAAUKzBMMFACuAQAMAAUKzBMMFACuAQA1AAQKgU0AAwwACQp3I8UaAGMDAAwACQp1I8UaAGMDABYABQrGE4oaAPYAAAAA.Mikevoker:BAAANQADCgEIAQABNQAFFAUIDgAMAMwTAA==.Mipz:BAAANQADCgUIBQAAAA==.Misfitmagi:BAAANQAECgIIAgAAAA==.Mistfox:BAAANQADCgYIDAAAAA==.Mistmommy:BAABNQAECoEZAAINAAgK+w4dGwCjAQANAAgK+w4dGwCjAQAAAA==.',
Mo='Mollieann:BAAANQAECgEIAQAAAA==.Mommon:BAAANQADCgEIAQAAAA==.Morrighan:BAAANQADCgMIAwAAAA==.',
['Mâ']='Mâlus:BAAANQAECgUICAAAAA==.',
['Mä']='Märs:BAAANQADCgYICgAAAA==.',
Na='Nadra:BAAANQADCgYIBgAAAA==.Naminé:BAAANQADCgQIBAABNQAECgUIHAAMAJwbAA==.Naroka:BAAANQAECgEIAQAAAA==.Nattyrav:BAACNQAFFIEHAAIXAAQKRRLMDgBCAQAXAAQKRRLMDgBCAQA1AAQKgSUAAxcACQoWGu4xAI0CABcACQoWGu4xAI0CAAsAAQpQHb7yAFIAAAAA.',
Ne='Neemesis:BAAANQAECgQIBAAAAA==.Nemonk:BAAANQAECgcIDAAAAA==.Nemoz:BAAANQAECgcIBwABNQAECgcIDAAEAAAAAA==.Nerfling:BAAANQADCgYICAAAAA==.',
No='Nocter:BAAANQAECgUIBQAAAA==.Noktor:BAAANQADCgYIBgAAAA==.Noktra:BAAANQAECgQIDwAAAA==.',
Ny='Nylah:BAAANQAECgEIAQABNQAFFAUIDAAJACcNAA==.Nymura:BAAANQAECgUIDQAAAA==.',
Oa='Oakhugger:BAABNQAECoEWAAQHAAcKOAz7ZAAOAQAHAAUKggz7ZAAOAQAYAAMKSgtbJgClAAAZAAIKigXISQBAAAAAAA==.',
Ol='Olyvivia:BAAANQADCgUIBQAAAA==.',
Om='Omgega:BAABNQAECoEcAAIBAAcKtRM2lADGAQABAAcKtRM2lADGAQAAAA==.',
On='Onichan:BAAANQAECgEIAQABNQAFFAcIEwAXAE8YAA==.Onimeek:BAABNQAECoEtAAIaAAkKFxlZHgCBAgAaAAkKFxlZHgCBAgAAAA==.Onionknightt:BAAANQAECgEIAQAAAA==.',
Or='Oryn:BAAANQAECggIDwAAAA==.Oryx:BAAANQADCgEIAQAAAA==.',
Os='Osoloco:BAAANQADCgUIAwAAAA==.',
Pa='Palmpower:BAAANQADCgYICQAAAA==.Palpitations:BAAANQAECgEIAQAAAA==.Paper:BAAANQAFFAQICQAAAQ==.',
Pe='Peacefullev:BAABNQAECoEdAAINAAgKsh6ODgBzAgANAAgKsh6ODgBzAgAAAA==.Pewpewpew:BAAANQAECgUIBQAAAA==.',
Ph='Phantomthief:BAAANQADCgcIDwAAAA==.',
Pi='Pipeleto:BAABNQAECoEoAAIDAAkKeB61LAD2AgADAAkKeB61LAD2AgAAAA==.Pizzaroll:BAABNQAECoEtAAIbAAkK2RYZBQB7AgAbAAkK2RYZBQB7AgAAAA==.',
Po='Podvoddonut:BAAANQADCgYIBgAAAA==.',
Pr='Previdius:BAAANQADCgUIBQAAAA==.Priesstess:BAAANQADCgYICQAAAA==.',
['Pé']='Pépega:BAAANQADCgQIBwAAAA==.',
Ri='Riellus:BAAANQADCgcIBwAAAA==.Riven:BAAANQADCgYIBgAAAA==.Rixin:BAEBNQAECoEmAAIUAAkKXyAyHwCyAgAUAAkKXyAyHwCyAgAAAA==.',
Ro='Rokom:BAACNQAFFIEHAAMGAAMKchkYAgC3AAAGAAIK2h8YAgC3AAADAAEKoQx1NABGAAA1AAQKgSQAAwYACQqJHK0LAOMBAAYABgo4Hq0LAOMBAAMABArKF0PRABkBAAAA.Roonrano:BAAANQADCggJCAAAAA==.',
Ru='Rumpus:BAAANQADCgcIBwAAAA==.Runed:BAAANQAECgEIAQAAAA==.',
Ry='Ryuk:BAAANQADCgYICgAAAA==.',
Sa='Salla:BAAANQADCgYICQAAAA==.Sanlennicus:BAAANQAECgEIAQAAAA==.Saphh:BAAANQAECgEIAQABNQAFFAQICgAVAOcTAA==.Saudencheek:BAAANQAECgQIBAAAAA==.',
Se='Seanster:BAABNQAECoEaAAMcAAkKDhOoHQBoAgAcAAkKDhOoHQBoAgAdAAMKGgKfFgBhAAABNQAFFAUIDAAJACcNAA==.Senecca:BAABNQAECoEdAAIHAAgKdRuHIwCUAgAHAAgKdRuHIwCUAgAAAA==.',
Sh='Shadowms:BAABNQAECoEZAAIeAAcKAxjVGgD8AQAeAAcKAxjVGgD8AQAAAA==.Shadowxd:BAAANQAECgcIEAAAAA==.Shamanpwnz:BAAANQAECgQIBgAAAA==.Shambassador:BAAANQAECgYIDgAAAA==.Shamwowha:BAAANQADCgQIBAAAAA==.Sharkdancer:BAAANQAFFAIIAgABNQAFFAUIDAANAFwhAA==.Shaulana:BAAANQADCggIFwAAAA==.Shenwu:BAABNQAECoEaAAIfAAgKyBjbCwAqAgAfAAgKyBjbCwAqAgAAAA==.Shirokuma:BAACNQAFFIEJAAMHAAUKdxfkDgBGAQAHAAQKPxXkDgBGAQAZAAEKVSDFBgBjAAA1AAQKgRwAAwcACQqPHZAXAPICAAcACQqPHZAXAPICABkAAQrxFylFAFAAAAAA.Shocktopuus:BAAANQADCgQIBAAAAA==.Shwizzle:BAAANQADCggIDgAAAA==.',
Si='Sidvicious:BAAANQADCgUIBAAAAA==.',
Sk='Sköllati:BAAANQAECgQIBAAAAA==.',
Sn='Sneakylev:BAABNQAECoEaAAMgAAkKKxHqGwDiAQAgAAgK3AzqGwDiAQAcAAQKFRFsWQADAQABNQAECggIHQANALIeAA==.',
So='Solari:BAABNQAECoEwAAMhAAkKWSSmAgCwAwAhAAkKWSSmAgCwAwAiAAUKwBaPEwBBAQAAAA==.Soleon:BAAANQAECgUICQAAAA==.Solune:BAAANQAECgYIDAAAAA==.Souprage:BAAANQAECgMIBgAAAA==.',
Sp='Spypal:BAAANQADCgYIDAAAAA==.',
St='Stabwei:BAAANQADCggICAAAAA==.',
Sw='Swagmastrflx:BAAANQADCgQIBAAAAA==.Swëëtdee:BAAANQADCgMICAAAAA==.',
Ta='Taehausx:BAAANQAFFAEIAQABNQAFFAYIFQASANIcAA==.Taraka:BAAANQADCggICAAAAA==.',
Td='Tdolokk:BAAANQADCggIFwAAAA==.',
Te='Teeward:BAAANQADCgYIBgAAAA==.Tenath:BAAANQAECgMIBAAAAA==.',
Th='Thaleon:BAAANQADCggICAAAAA==.Thauriel:BAAANQAECgEIAQAAAA==.Theexecution:BAAANQADCgMIAwAAAA==.Therella:BAAANQADCgUIBQAAAA==.',
To='Totemtotebag:BAAANQAECgQIEwABNQAECgkJGQAZAFgkAA==.',
Tr='Tripodg:BAAANQADCgYICgAAAA==.Trollztoll:BAAANQADCgIIAgAAAA==.',
Tw='Twiddletime:BAAANQAECgQIBAAAAA==.',
['Tï']='Tïggy:BAAANQAECgEIAQAAAA==.',
Un='Una:BAAANQAECgUIBQAAAA==.Unholymisfit:BAAANQAECgIIAgAAAA==.Unholytato:BAAANQADCgQIBAAAAA==.',
Ut='Uthok:BAAANQADCgEJAQAAAA==.',
Uz='Uzol:BAAANQADCgIIAgAAAA==.',
Va='Vacalocà:BAAANQAECgIIAgAAAA==.Valerian:BAAANQAECgYIDAAAAA==.Van:BAAANQADCgQIBAAAAA==.',
Ve='Veinke:BAAANQAECgcIEwAAAA==.Velanthir:BAAANQADCggIFAAAAA==.Verd:BAEANQAFFAEIAQAAAA==.Veronica:BAAANQABCgYIBgAAAA==.Versaacee:BAAANQADCgYIBgAAAA==.Vessarind:BAAANQADCgUIBQAAAA==.',
Vi='Vivrian:BAAANQADCgUIBQAAAA==.',
['Vä']='Vänillaicë:BAAANQADCgcIBwAAAA==.',
Wa='Waally:BAAANQAECgQIBQAAAA==.Wahwoo:BAAANQADCgYIBgAAAA==.',
We='Weebsora:BAAANQAECgQIBQAAAA==.',
Wo='Worldtree:BAAANQADCgEIAQAAAA==.',
Xa='Xaelthira:BAAANQADCgcIBwAAAA==.',
Ya='Yadhi:BAAANQAECgUIEAABNQAECggILwAFAOkZAA==.',
Yi='Yimomo:BAABNQAECoEkAAITAAgKmR4QKgCiAgATAAgKmR4QKgCiAgAAAA==.',
Za='Zalconn:BAABNQAECoEdAAMgAAkKgCMtCwCzAgAgAAcK6yMtCwCzAgAcAAQKVyGlQgB6AQAAAA==.Zarrona:BAAANQAECgIIAwABNQAECgUIHAAMAJwbAA==.Zayah:BAAANQAFFAEIAQAAAA==.',
Zi='Zikony:BAAANQAECgIIAQAAAA==.',
Zu='Zuber:BAABNQAECoEmAAIcAAgKLiJ9DwDmAgAcAAgKLiJ9DwDmAgAAAA==.',
['År']='Årtimus:BAAANQADCgYIDAAAAA==.',
['Üw']='Üwü:BAAANQAECgQIBgAAAA==.',
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
