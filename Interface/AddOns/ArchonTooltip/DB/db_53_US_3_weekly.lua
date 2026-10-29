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

local lookup = {'Paladin-Retribution','Paladin-Protection','Druid-Balance','Unknown-Unknown','Warrior-Arms','Warrior-Protection','Monk-Brewmaster','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Mage-Frost','Mage-Arcane','Monk-Mistweaver','Hunter-Marksmanship','DemonHunter-Havoc','Warlock-Affliction','Priest-Shadow','DeathKnight-Blood','DemonHunter-Devourer','Monk-Windwalker','Priest-Holy','Hunter-Survival','Priest-Discipline','Druid-Feral','Druid-Guardian','Evoker-Augmentation','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation','Druid-Restoration','Rogue-Subtlety','DemonHunter-Vengeance',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=53,date='2026-10-27',data={Ae='Aegrias:BAABNQAECn8lAAIBAAoK9BsyRQDFAgABAAoK9BsyRQDFAgAAAA==.Aerodria:BAABNQAECn8/AAICAAoKdhn1EQCBAgACAAoKdhn1EQCBAgAAAA==.',
Ak='Akeno:BAAANQAECgMIAgABNQAFFAYIEgADALkUAA==.',
Al='Alanril:BAAANQADCgMIAwAAAA==.Alarthevel:BAAANQAECgMIBAAAAA==.Albince:BAAANQADCgQIBAAAAA==.Allastolan:BAAANQADCgIIAgABNQAECgEIDQAEAAAAAA==.',
Am='Amant:BAAANQADCggICQAAAA==.Amellis:BAAANQADCgIIAgAAAA==.',
An='Andeduty:BAAANQADCggIDAAAAA==.Andreasham:BAAANQAECgUICQAAAA==.Andreaswar:BAAANQAECgMIAwAAAA==.Anniferal:BAAANQAECgMIBAABNQAFFAYIEAAFAI4ZAA==.Annisseda:BAACNQAFFH8QAAIFAAYKjhmbDwC9AQAFAAYKjhmbDwC9AQA1AAQKfyYAAwUACQrpIlYvABwCAAUACQpHIlYvABwCAAYAAgoFISIbALkAAAAA.Anzak:BAAANQAECgQIBQAAAA==.',
Ar='Araelina:BAAANQADCgIIAgAAAA==.Ardrayshock:BAAANQABCgcJCgAAAA==.Ardrek:BAAANQADCggICAAAAA==.Arrhythmia:BAAANQAECgQICwABNQAFFAcIEAAEAAAAAQ==.',
As='Astrayn:BAAANQADCgIIAgAAAA==.',
Az='Azala:BAAANQAECgIIAgAAAA==.Azryx:BAAANQADCgcICQABNQAECgoKLwAHAMYfAA==.Azzy:BAACNQAFFH8XAAIFAAcKvg9OBwBYAQAFAAcKvg9OBwBYAQA1AAQKf0UAAwUACgryI2ILAAwDAAgACQpAILYDABMDAAUACgrRI2ILAAwDAAAA.',
Ba='Bananski:BAAANQADCgcIBwAAAA==.',
Be='Beeflocks:BAAANQAECgMIBgABNQAECgoKJQAFAPUaAA==.Beefychunks:BAABNQAECn8lAAIFAAoK9RozXwBvAgAFAAoK9RozXwBvAgAAAA==.',
Bi='Bigbleu:BAAANQAECgQIBAABNQAFFAQIBQADAOICAA==.Bigdraco:BAAANQADCgQIBQAAAA==.Biggums:BAAANQADCgQIBAAAAA==.Bigpapapump:BAAANQAECgMIAwAAAA==.Billyspikepd:BAABNQAECn8YAAMBAAYKWBLp2ABpAQABAAYKWBLp2ABpAQACAAEK/glWewAhAAAAAA==.Billyspikepr:BAAANQADCggIDQABNQAECgYIGAABAFgSAA==.Billyspikerg:BAAANQAECgYIDgABNQAECgYIGAABAFgSAA==.',
Bl='Black:BAAANQADCgMIAwAAAA==.Blobcat:BAABNQAECn8qAAIDAAkKjBUMHQCjAQADAAkKjBUMHQCjAQAAAA==.Blobknight:BAAANQAECgUIDwAAAA==.Bloodhase:BAABNQAECn8dAAMJAAoKOhrhIwByAgAJAAoKOhrhIwByAgAKAAQK3A7RogC1AAAAAA==.Bluecard:BAACNQAFFH8NAAMLAAUKKxmACgADAQALAAQKGRuACgADAQAMAAEKYhPWGgBQAAA1AAQKfyMAAwsACgoBIMxPAGUCAAsACArVH8xPAGUCAAwAAwo7IS1GAK4AAAAA.',
Bo='Bothenheim:BAACNQAFFH8QAAIBAAYKLh2KBABNAQABAAYKLh2KBABNAQA1AAQKfxsAAgEACQoQHE55ADkCAAEACQoQHE55ADkCAAAA.Bowdaddy:BAABNQAECn8kAAINAAgKZRXYYQB6AQANAAgKZRXYYQB6AQABNQAECggIJAANAGUVAA==.',
Br='Breakdown:BAABNQAECn8cAAIIAAcKVgn6EADbAAAIAAcKVgn6EADbAAAAAA==.Brewsimmons:BAAANQADCggIEAABNQAFFAcIFAAOAJQKAA==.',
Bu='Bublz:BAAANQADCgIIAgAAAA==.Bumpinuglies:BAAANQAECgEIAQAAAA==.',
Ca='Cailey:BAAANQAECggICgABNQAECggICgAEAAAAAA==.Calcshortfor:BAAANQADCgQIBAAAAA==.Callamdrake:BAAANQADCgQJBQAAAA==.Callamsvoid:BAAANQAECgEIAQAAAA==.Calyrex:BAAANQADCgEIAQAAAA==.Camazotz:BAAANQAECgcICAAAAA==.Capulse:BAACNQAFFH8RAAIPAAYKPBcpCwCaAQAPAAYKPBcpCwCaAQA1AAQKfxsABA8ACAqqIPxgAOsBAA8ABgqeIvxgAOsBABAABQrQFmxzALoAABEAAQoMAqgqADMAAAAA.Caredragon:BAAANQADCgIIAgAAAA==.Careglobo:BAAANQAECgMIBAAAAA==.Caylen:BAAANQAECggIAgABNQAFFAYIEQAPADwXAA==.',
Ce='Centri:BAABNQAECn8iAAMSAAkKNiGGBQC4AgASAAcKWCKGBQC4AgATAAkKTxsNfgCCAgAAAA==.',
Ch='Chowa:BAAANQAECgEIAQAAAA==.',
Cl='Clapdatazz:BAAANQAECggIEgAAAA==.Cleverlev:BAAANQADCggIDQABNQAFFAMIBQAUAHILAA==.',
Co='Colapse:BAAANQADCgMIAwAAAA==.',
Cr='Crunchrr:BAAANQADCgEIAQAAAA==.',
Cu='Cubensis:BAAANQADCgcJFgAAAA==.',
Cy='Cyiera:BAAANQAECggICgAAAA==.',
Da='Daeland:BAABNQAECn8XAAIIAAgKXQrvCgBQAQAIAAgKXQrvCgBQAQAAAA==.Daisyshot:BAABNQAECn87AAMNAAoK+yBeGgAvAwANAAkKbiFeGgAvAwAVAAcKkRgQPABwAQAAAA==.Dalsham:BAAANQADCggIBgAAAA==.',
De='Deathsgrace:BAAANQADCggICgAAAA==.Deathtank:BAAANQADCgMIAwAAAA==.Decima:BAABNQAECn8dAAIDAAkKSAcRWQBwAQADAAkKSAcRWQBwAQAAAA==.Dejustinfox:BAAANQADCgQIBwAAAA==.Demeter:BAACNQAFFH8OAAMVAAYKohdaCQDVAAAVAAUK4xVaCQDVAAANAAMK+hmyHQBjAAA1AAQKfyIAAxUACgo4IS4OAOsBABUACQqKIC4OAOsBAA0ABAp9FlkBAQIBAAAA.Demonpunter:BAABNQAECn8bAAIWAAcKaB5WJgBrAgAWAAcKaB5WJgBrAgABNQAFFAYIEQAXAD4lAA==.',
Di='Diablita:BAAANQADCgEIAQAAAA==.Diabloa:BAAANQADCgQICAAAAA==.Diamba:BAAANQAECgUIBwABNQAECgYICwAEAAAAAA==.Dinoscarr:BAAANQAECgQIBAAAAA==.',
Do='Doohickey:BAAANQAECgYICgABNQAECggIIgAGAFENAA==.Doohicky:BAAANQAECgYICwABNQAECggIIgAGAFENAA==.Dorgrim:BAAANQADCgMIAwAAAA==.Dotsndash:BAABNQAECn8yAAIYAAoKZxlKGACRAgAYAAoKZxlKGACRAgAAAA==.',
Du='Dungpoo:BAAANQADCgEIAQAAAA==.',
Ea='Eargox:BAAANQAECgMIBAAAAA==.',
Ee='Eesa:BAAANQAECggIDgAAAA==.',
El='Elinia:BAAANQADCgMIBAAAAA==.Elleteliara:BAAANQAECgEIAQAAAA==.Elmdor:BAAANQAECgQIAwAAAA==.Elyndra:BAAANQAECgUICQAAAA==.',
En='Eniacoc:BAAANQAECgEIAQAAAA==.',
Ev='Everas:BAAANQAECgYIBwAAAA==.',
Ex='Excentric:BAAANQAECgIIAgABNQAECgkJIgASADYhAA==.Excentrics:BAAANQADCgUIBQABNQAECgkJIgASADYhAA==.',
Fa='Faithlyn:BAAANQADCgEIAQABNQAECgIIAgAEAAAAAA==.Falarth:BAABNQAECn8jAAIZAAoK/BFrJgBlAQAZAAoK/BFrJgBlAQAAAA==.Falloutman:BAABNQAECn8hAAICAAoKLBuiCAA9AgACAAoKLBuiCAA9AgAAAA==.Farther:BAAANQADCgUICQABNQAFFAcIGAATAD0bAA==.Fayne:BAAANQAECgMIAwAAAA==.',
Fe='Felfart:BAAANQADCgUIBQAAAA==.',
Fi='Firefox:BAACNQAFFH8FAAIZAAIKXhEnIwByAAAZAAIKXhEnIwByAAA1AAQKfx0AAhkACgofGHs3ACsCABkACgofGHs3ACsCAAE1AAUUBggLABoAuhcA.',
Fl='Flechillas:BAAANQADCgcIDQAAAA==.Flán:BAABNQAECn8cAAIbAAkKSBDJKgDGAQAbAAkKSBDJKgDGAQAAAA==.',
Fr='Fraternite:BAAANQAECgYIBwAAAA==.',
Fu='Furrymoon:BAAANQADCgcIBwAAAA==.',
Ga='Gabriellad:BAAANQAECgUIDQAAAA==.',
Ge='Gerrakha:BAAANQADCgYIBgABNQAECgEIDQAEAAAAAA==.',
Gi='Giterdonee:BAACNQAFFH8RAAMFAAYKZRPnCgAVAQAFAAQKZRPnCgAVAQAIAAIKAADcAgCpAAA1AAQKfycAAwgACgoiH5oFAMYCAAgACgp8HZoFAMYCAAUABwqzFIGxAKEBAAAA.',
Go='Gorr:BAAANQADCgMIBgABNQAECgIIAgAEAAAAAA==.Gotchoo:BAABNQAECn8hAAIJAAgKuxGWOQA0AQAJAAgKuxGWOQA0AQABNQAECgIIAgAEAAAAAA==.Gothmommy:BAABNQAECn8sAAIcAAoKCBvPQgBhAgAcAAoKCBvPQgBhAgAAAA==.',
Gr='Grilledchis:BAAANQADCgIIAgAAAA==.Groldin:BAAANQAECggICQAAAA==.Grumble:BAAANQAECgQIBAAAAA==.',
['Gõ']='Gõtchoo:BAAANQAECgIIAgAAAA==.',
Ha='Hairball:BAABNQAECn8VAAIdAAgKyhHRBwDqAQAdAAgKyhHRBwDqAQAAAA==.Hammerthumb:BAAANQAECgMIAwABNQAECggIJAADAGcLAA==.Hardawn:BAAANQABCgEIAQABNQAFFAcIGAATAD0bAA==.',
Ho='Hotsoup:BAAANQADCgQJBAAAAA==.Hozzluzzak:BAAANQADCggICAAAAA==.',
Hy='Hyara:BAABNQAECn9FAAINAAoKgCOGCACZAwANAAoKgCOGCACZAwAAAA==.',
['Hù']='Hùñtarð:BAAANQAECgEIAgAAAA==.',
Im='Imnaked:BAAANQADCgYIBgAAAA==.',
In='Invisimitch:BAAANQADCgEIAQAAAA==.',
Ip='Ips:BAAANQADCgIIAgABNQADCgUIBQAEAAAAAA==.',
Iv='Iv:BAAANQADCgYIBgAAAA==.',
Je='Jeffster:BAAANQAECgEIAQAAAA==.',
Ji='Jifman:BAAANQADCgYIBgAAAA==.',
Jo='Joffrey:BAAANQADCgcIDgAAAA==.Jordi:BAABNQAECn8uAAINAAgKxx5nPwCsAgANAAgKxx5nPwCsAgAAAA==.Jotarcyon:BAAANQABCgIJAgAAAA==.',
Ju='Jukkes:BAAANQADCggIEwAAAA==.Justinfox:BAAANQADCgEIAQAAAA==.Juukess:BAAANQAECgIIAgAAAA==.',
Ka='Kannarri:BAAANQAECgMICAAAAA==.Kanree:BAACNQAFFH8WAAIUAAcKkQRJAwBBAQAUAAcKkQRJAwBBAQA1AAQKf0UAAhQACgobE7QXAAICABQACgobE7QXAAICAAAA.Kapriestsun:BAAANQAECgEIAQABNQAECgEIAQAEAAAAAA==.Kayaa:BAAANQADCggICAAAAA==.',
Ke='Kea:BAACNQAFFH8OAAMcAAUKhh4lBwDEAQAcAAUKQB0lBwDEAQAeAAQK2xo7AQBvAQA1AAQKf10ABB4ACgpqJlQAAMEDABwACgpbJhECAO8DAB4ACQoGJVQAAMEDABgABAonGSc+ADsBAAAA.Kek:BAABNQAECn8cAAIJAAgKAQndOgAvAQAJAAgKAQndOgAvAQAAAA==.',
Kh='Khaalid:BAAANQAECgEIAQABNQAECgoKLwAHAMYfAA==.Kharok:BAABNQAECn8sAAQIAAkKDiEYBAA/AgAGAAgK9iDNCADDAgAIAAkKkh0YBAA/AgAFAAYKVRjxpgC8AQABNQAECgoKLwAHAMYfAA==.',
Ki='Killhordex:BAAANQADCgIIAgAAAA==.Kincane:BAAANQADCgcICQAAAA==.',
Ko='Korxin:BAACNQAFFH8OAAMNAAYKxRH+GgDiAAANAAQKDBT+GgDiAAAVAAQKBgfKDQCMAAA1AAQKfzwAAw0ACgoBIgYzANMCAA0ACgoBIgYzANMCABUABwqUFCATAI8BAAAA.Kota:BAAANQADCgEIAQAAAA==.',
Ku='Kurnhaspios:BAAANQADCgQIBAAAAA==.Kurquaan:BAAANQAECgMIBAAAAA==.',
Ky='Kydraeth:BAAANQAECgEIAQAAAA==.',
La='Lanstyn:BAABNQAECn8vAAIeAAgK6RnTBAByAgAeAAgK6RnTBAByAgABNQAECgoKLwAHAMYfAA==.Laufey:BAABNQAECn8wAAITAAgKuBekaQB1AQATAAgKuBekaQB1AQAAAA==.',
Le='Lemone:BAAANQADCgUIBQAAAA==.Lemonsk:BAAANQADCgUICAAAAA==.Lennox:BAAANQADCgQIBAAAAA==.Lenton:BAAANQAECgEIAQAAAA==.',
Li='Lightfury:BAAANQADCgYIDAAAAA==.Limone:BAAANQAECgEIAQAAAA==.Listradra:BAAANQADCgQIBAAAAA==.',
Lo='Loganwater:BAAANQADCgQIBAAAAA==.Loinari:BAAANQADCgUIDQAAAA==.Lokano:BAAANQADCgIIAgAAAA==.',
Lu='Ludmylha:BAAANQAECgUICAAAAA==.Luisda:BAAANQADCggIFwAAAA==.Lull:BAAANQADCggIEQAAAA==.Lushil:BAAANQAFFAEIAQAAAA==.',
Ly='Lyrea:BAAANQAECggICAAAAA==.',
Ma='Man:BAAANQADCgUIBQAAAA==.Marsangel:BAAANQADCgEIAQAAAA==.Marydavis:BAAANQABCgEIAQAAAA==.Maxerella:BAAANQADCgUIBQAAAA==.Maybell:BAAANQAECgYIDgAAAA==.',
Md='Mdavis:BAAANQADCgMIAwAAAA==.',
Me='Meepmeepmomp:BAAANQADCgUIBQAAAA==.Megumín:BAAANQAECgEIAQAAAA==.Melt:BAACNQAFFH8aAAQMAAcKfxi5AwCfAAALAAQKORgtDADzAAAMAAIK5xi5AwCfAAAXAAEKAAA6CQBcAAA1AAQKf0IAAwsACgpyIt0UAIQCAAsACQr9Id0UAIQCAAwABAoAIlAgAG4BAAAA.Mepha:BAACNQAFFH8PAAIKAAYKxQ5ZAgA9AQAKAAYKxQ5ZAgA9AQA1AAQKfyYAAwoACgqpHJk/AB8CAAoACQqpHJk/AB8CAAkACArhDJ9LAIsBAAAA.Meridia:BAAANQADCgMIAwAAAA==.',
Mi='Miike:BAAANQADCgEIAQABNQAFFAcIGAATAD0bAA==.Mike:BAACNQAFFH8YAAMTAAcKPRseCgBQAQATAAYK1BseCgBQAQASAAEK4Bg4CABdAAA1AAQKf2IAAxMACgpbJAITAIcDABMACgpbJAITAIcDABIABQqUD0cfAPAAAAAA.Mikevoker:BAAANQADCgEIAQABNQAFFAcIGAATAD0bAA==.Mipz:BAAANQADCgUIBQAAAA==.Misfitdh:BAAANQAECgIIAgAAAA==.Misfitdk:BAAANQAECggIAgAAAA==.Misfitmagi:BAAANQAECgIIAgAAAA==.Misfittotem:BAAANQAECgIIAQAAAA==.Mistfox:BAAANQADCgYIDAAAAA==.Mistmommy:BAABNQAECn8sAAIUAAkK+RHVDADDAQAUAAkK+RHVDADDAQAAAA==.',
Mo='Mollieann:BAAANQAECgIIAgAAAA==.Mommon:BAAANQADCgEIAQAAAA==.Morrighan:BAAANQADCgMIAwAAAA==.',
['Mâ']='Mâlus:BAAANQAECgUICAAAAA==.',
['Mä']='Märs:BAAANQADCgYICgAAAA==.',
Na='Nadra:BAAANQAECgIIAQAAAA==.Naminé:BAAANQADCgQIBAABNQAECggIMAATALgXAA==.Naroka:BAAANQAECggIDQAAAA==.Nattyrav:BAACNQAFFH8IAAIQAAQKGRUpEwA/AQAQAAQKGRUpEwA/AQA1AAQKfyUAAxAACQp/Ghg9AIECABAACQp/Ghg9AIECAA8AAQpQHW0LAVEAAAAA.',
Ne='Neemesis:BAAANQAECgQIBAAAAA==.Nemonk:BAAANQAECggIDAABNQAECgkJFAATACQGAA==.Nemoz:BAABNQAECn8UAAITAAkKJAaWtgDaAAATAAkKJAaWtgDaAAAAAA==.Nerfling:BAAANQADCgYICAAAAA==.',
No='Nocter:BAAANQAECgUIBQAAAA==.Noktor:BAAANQADCgYIBgAAAA==.Noktra:BAAANQAECgUIDwAAAA==.Nosey:BAAANQADCgUIBQAAAA==.',
Ny='Nylah:BAAANQAECgYIBgABNQAFFAUIEAAMAIUSAA==.Nymura:BAABNQAECn8kAAIBAAcKVg5eqgACAQABAAcKVg5eqgACAQAAAA==.',
Oa='Oakhugger:BAABNQAECn8kAAQDAAgKZwuaOADmAAADAAYK7gmaOADmAAAfAAQKzgrmLgCbAAAgAAIKqwPFWwA+AAAAAA==.',
Ol='Olyvivia:BAAANQAECgcIBwAAAA==.',
Om='Omgega:BAABNQAECn8sAAIBAAoKoBKCZwCIAQABAAoKoBKCZwCIAQAAAA==.',
On='Onichan:BAAANQAECgEIAQAAAA==.Onimeek:BAABNQAECn87AAIWAAoKDRntEwAWAgAWAAoKDRntEwAWAgAAAA==.Onionknightt:BAAANQAECgEIAQAAAA==.',
Or='Oryn:BAABNQAECn8VAAMSAAoKGBxsIwDRAAATAAcKnh2N0ADlAQASAAMKjBlsIwDRAAABNQAFFAEIAQAEAAAAAA==.Oryx:BAAANQADCgEIAQAAAA==.',
Os='Osoloco:BAAANQADCgUIAwAAAA==.',
Pa='Palmpower:BAAANQADCgYICQAAAA==.Palpitations:BAAANQAECgEIAQAAAA==.Paper:BAAANQAFFAcIEAAAAQ==.',
Pe='Peacefullev:BAACNQAFFH8FAAIUAAMKcgsjBQC3AAAUAAMKcgsjBQC3AAA1AAQKfzIAAhQACgr5HnsFAMQCABQACgr5HnsFAMQCAAAA.Pepegá:BAAANQAECgEIAQAAAA==.Pewpewpew:BAAANQAECgUICQAAAA==.',
Ph='Phantomthief:BAAANQAECggICAAAAA==.',
Pi='Pipeleto:BAABNQAECn9DAAIFAAoK9h7gJQAhAwAFAAoK9h7gJQAhAwAAAA==.Pizzaroll:BAABNQAECn9AAAIhAAoKJRUIBQCiAgAhAAoKJRUIBQCiAgAAAA==.',
Po='Podvoddonut:BAAANQADCgYIBgAAAA==.',
Pr='Previdius:BAAANQADCgUIBQAAAA==.Priesstess:BAAANQADCgYICQAAAA==.',
['Pé']='Pépega:BAAANQADCgQIBwAAAA==.',
Ri='Riellus:BAAANQAECgIIAgAAAA==.Riiu:BAAANQAECgYICAABNQAECgkJPgABAC8lAA==.Riven:BAAANQADCgYIBgAAAA==.Rixin:BAECNQAFFH8NAAMKAAUKFB7eBgCzAAAKAAQKFB7eBgCzAAAZAAEKAACbOwAcAAA1AAQKfy0AAgoACgqAHW8bAOcCAAoACgqAHW8bAOcCAAAA.',
Ro='Rokom:BAACNQAFFH8KAAMIAAQK1ReyAgCyAAAIAAMK5xqyAgCyAAAFAAEKsBGWPABHAAA1AAQKfywAAwgACgosHeMNANUBAAgABwqXIOMNANUBAAUABAptGDHqABABAAAA.Roonrano:BAAANQADCggICAAAAA==.',
Ru='Rumpus:BAAANQADCgcIBwAAAA==.Runed:BAAANQAECgEIAQAAAA==.',
Ry='Ryuk:BAAANQAECgQIBAAAAA==.',
Sa='Salla:BAAANQADCgYICQAAAA==.Sanlennicus:BAAANQAECgIIBAAAAA==.Saphh:BAAANQAECgEIAQABNQAFFAQIDwAJAHIYAA==.Saudencheek:BAAANQAECgQIBAAAAA==.',
Se='Seanster:BAABNQAECn8eAAMiAAkK+xKkIgBxAgAiAAkK+xKkIgBxAgAjAAMKQQJhGABeAAABNQAFFAUIEAAMAIUSAA==.Senecca:BAABNQAECn8sAAIDAAoKiRv6IADFAgADAAoKiRv6IADFAgAAAA==.',
Sh='Shadowlily:BAAANQADCgMIAwABNQAECgkJJwAPADAJAA==.Shadowms:BAABNQAECn8xAAIkAAoKEx8YAwAiAwAkAAoKEx8YAwAiAwAAAA==.Shadowxd:BAABNQAECn8xAAQlAAoKFh6uBQAaAwAlAAoKFh6uBQAaAwAgAAEKAACJYAAzAAADAAEKHAYOugAmAAAAAA==.Shamanpwnz:BAAANQAECgQIBgAAAA==.Shambassador:BAAANQAECggIEQAAAA==.Shamwowha:BAAANQADCgQIBAAAAA==.Sharkdancer:BAABNQAECn8UAAIaAAkKaB6OFQC4AgAaAAkKaB6OFQC4AgABNQAFFAYIDgAUAJMhAA==.Shaulana:BAAANQAECgEIAQABNQAECgkJJwAPADAJAA==.Shenwu:BAABNQAECn8fAAIHAAkKLxfRDQAcAgAHAAkKLxfRDQAcAgAAAA==.Shirokuma:BAACNQAFFH8SAAMDAAYKuRSOBgA6AQADAAUKuRSOBgA6AQAgAAEKAADwCABfAAA1AAQKfyQAAwMACgo3HbsaAPMCAAMACgo3HbsaAPMCACAAAQrxFz5VAFAAAAAA.Shocktopuus:BAAANQADCgQIBAAAAA==.Shwizzle:BAAANQADCggIDgAAAA==.',
Si='Sidvicious:BAAANQADCgUIBAAAAA==.',
Sk='Sköllati:BAAANQAECgUIBAAAAA==.',
Sl='Slingshotz:BAAANQAECgcICAAAAA==.',
Sm='Smarty:BAAANQAECgUIBAAAAA==.',
Sn='Sneakylev:BAABNQAECn8xAAMmAAkKvRRZHgDfAQAmAAgKHg9ZHgDfAQAiAAQKcRSEKQDLAAABNQAFFAMIBQAUAHILAA==.',
So='Solari:BAABNQAECn85AAMaAAoKtST0AgCrAwAaAAoKtST0AgCrAwAnAAUKIBhkFwA4AQAAAA==.Soleon:BAAANQAECgcIDgAAAA==.Solune:BAAANQAECgYIDAAAAA==.Souprage:BAAANQAECgMIBgAAAA==.',
Sp='Spypal:BAAANQADCgYIDAAAAA==.',
St='Stabwei:BAAANQADCggICAAAAA==.',
Su='Sugirokimami:BAAANQAECgYICwAAAA==.',
Sw='Swagmastrflx:BAAANQADCgQIBAAAAA==.Swëëtdee:BAAANQADCgMICAAAAA==.',
Ta='Taehausx:BAAANQAFFAEIAQABNQAFFAYICgACAO4UAA==.Taraka:BAAANQAECgQIBAAAAA==.',
Td='Tdolokk:BAAANQADCggIFwAAAA==.',
Te='Teeward:BAAANQADCgYIBgAAAA==.Tenath:BAAANQAECgUICQAAAA==.Terribleturd:BAAANQAECgEIAQAAAA==.',
Th='Thaleon:BAAANQADCggICAAAAA==.Thauriel:BAAANQAECgEIAQAAAA==.Theexecution:BAAANQAECgQIAwAAAA==.Therella:BAAANQADCgUIBQAAAA==.',
Ti='Tinkerspell:BAAANQAECggIAgAAAA==.',
To='Totemtotebag:BAABNQAECn8XAAIPAAQK7BdpsAAOAQAPAAQK7BdpsAAOAQABNQAECgoKLwAgAH4lAA==.',
Tr='Treshaleth:BAAANQADCgQIBAAAAA==.Tripodg:BAABNQAECn8UAAISAAcKegXJFADQAAASAAcKegXJFADQAAAAAA==.Trollztoll:BAAANQADCgIIAgAAAA==.',
Tw='Twiddletime:BAAANQAECgQIBgAAAA==.',
['Tï']='Tïggy:BAAANQAECgYIBgAAAA==.',
Un='Una:BAAANQAECgYIEwAAAA==.Unholymisfit:BAAANQAECgMIBQAAAA==.Unholytato:BAAANQADCgQIBAAAAA==.',
Ur='Ursok:BAAANQAECgEIAQABNQAECgoKLwAHAMYfAA==.',
Ut='Uthok:BAAANQADCgEJAQAAAA==.',
Uz='Uzol:BAAANQADCgcICAAAAA==.',
Va='Vacalocà:BAAANQAECggICgAAAA==.Valerian:BAABNQAECn8ZAAIDAAgKVAvDKgA0AQADAAgKVAvDKgA0AQAAAA==.Van:BAAANQADCgQIBAAAAA==.',
Ve='Veinke:BAABNQAECn8YAAInAAgKJRk0CwAfAgAnAAgKJRk0CwAfAgAAAA==.Velanthir:BAAANQADCggIFAAAAA==.Verd:BAEANQAFFAEIAQAAAA==.Verevulf:BAAANQABCgIIAgAAAA==.Veronica:BAAANQABCgYIBgAAAA==.Versaacee:BAAANQADCgYIBgAAAA==.Vessarind:BAAANQADCgUIBQAAAA==.',
Vi='Vivrian:BAAANQADCgUIBQAAAA==.',
['Vä']='Vänillaicë:BAAANQADCgcIBwABNQAECgkJJwAPADAJAA==.',
Wa='Waally:BAAANQAECgQIBQAAAA==.Wahwoo:BAAANQADCggIDgABNQAECgkJJwAPADAJAA==.Walterlight:BAAANQAECgYIBgABNQAECgoKOwANAPsgAA==.',
We='Weebsora:BAAANQAECgQIBQAAAA==.',
Wo='Worldtree:BAAANQADCgEIAQAAAA==.',
Xa='Xaelthira:BAAANQADCgcIBwAAAA==.',
Ya='Yadhi:BAABNQAECn8vAAIHAAoKxh//AgBrAwAHAAoKxh//AgBrAwAAAA==.',
Yi='Yimomo:BAABNQAECn8tAAIcAAkKnx6iNACVAgAcAAkKnx6iNACVAgAAAA==.',
Za='Zalconn:BAABNQAECn8rAAMmAAoKSiMHCgDvAgAmAAoKGiMHCgDvAgAiAAQKVyHeUgBxAQAAAA==.Zarrona:BAAANQAECgIIAwABNQAECggIMAATALgXAA==.Zayah:BAAANQAFFAIIAwAAAA==.',
Zi='Zikony:BAAANQAECgcIBwAAAA==.',
Zu='Zuber:BAABNQAECn8/AAIiAAoKNCF5AwC6AgAiAAoKNCF5AwC6AgAAAA==.',
['År']='Årtimus:BAAANQADCgYIDAAAAA==.',
['Öw']='Öwö:BAAANQAECgQIBAAAAA==.',
['Üw']='Üwü:BAABNQAECn8eAAMOAAgKphjONwC+AQAOAAgKphjONwC+AQABAAQKmRBrHAHvAAAAAA==.',
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
