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

local lookup = {'Paladin-Retribution','Paladin-Protection','Druid-Balance','Unknown-Unknown','Warrior-Arms','Warrior-Protection','Monk-Brewmaster','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Mage-Frost','Mage-Arcane','Monk-Mistweaver','Hunter-Marksmanship','DemonHunter-Havoc','Warlock-Affliction','Priest-Shadow','Priest-Holy','DeathKnight-Blood','DemonHunter-Devourer','Monk-Windwalker','Hunter-Survival','Priest-Discipline','Druid-Feral','Druid-Guardian','Druid-Restoration','Evoker-Augmentation','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','DemonHunter-Vengeance',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=53,date='2026-11-03',data={Ae='Aegrias:BAABNQAECn8lAAIBAAoK9BsyRQDFAgABAAoK9BsyRQDFAgAAAA==.Aerodria:BAABNQAECn9KAAICAAoKdhn1EQCBAgACAAoKdhn1EQCBAgAAAA==.',
Ak='Akeno:BAAANQAECgQIBwABNQAFFAcIEwADAAsTAA==.',
Al='Alanril:BAAANQADCgMIAwAAAA==.Alarthevel:BAAANQAECgMIBAAAAA==.Albince:BAAANQADCgQIBAAAAA==.Aligh:BAAANQAECgEIAQAAAA==.Allastolan:BAAANQADCgIIAgABNQAECggIDgAEAAAAAA==.',
Am='Amant:BAAANQADCggICQAAAA==.Amellis:BAAANQADCgIIAgAAAA==.',
An='Andeduty:BAAANQADCggIDQAAAA==.Andreasham:BAAANQAECgUICQAAAA==.Andreaswar:BAAANQAECgMIAwAAAA==.Anniferal:BAAANQAECgMIBAABNQAFFAcIEQAFANMWAA==.Annisseda:BAACNQAFFH8RAAIFAAcK0xa4CgBNAQAFAAcK0xa4CgBNAQA1AAQKfycAAwUACQopI/8/ABUCAAUACQqHIv8/ABUCAAYAAgoFIXgiALIAAAAA.Anzak:BAAANQAECgQIBQAAAA==.',
Ar='Araelina:BAAANQADCgIIAgAAAA==.Ardrayshock:BAAANQABCgcJCgAAAA==.Ardrek:BAAANQADCggICAAAAA==.Arrhythmia:BAAANQAECggIEgABNQAFFAYIEAAEAAAAAQ==.',
As='Astrayn:BAAANQADCgIIAgAAAA==.',
Az='Azala:BAAANQAECgIIAgAAAA==.Azryx:BAAANQADCgcICQABNQAECgoKNQAHAM0hAA==.Azzy:BAACNQAFFH8YAAIFAAcKvg+9CgBNAQAFAAcKvg+9CgBNAQA1AAQKf04AAwUACgrUJIULACgDAAUACgq7JIULACgDAAgACQpAILYDABMDAAAA.',
Ba='Bananski:BAAANQADCgcIBwAAAA==.',
Be='Beeflocks:BAAANQAECgUIBwABNQAECgoKMAAFAMccAA==.Beefychunks:BAABNQAECn8wAAIFAAoKxxw4HwCrAgAFAAoKxxw4HwCrAgAAAA==.',
Bi='Bigbleu:BAAANQAECgQIBwABNQAFFAQIBQADAOICAA==.Bigdraco:BAAANQADCgQIBQAAAA==.Biggums:BAAANQADCgQIBAAAAA==.Bigpapapump:BAAANQAECgMIAwAAAA==.Billyspikepd:BAABNQAECn8YAAMBAAYKWBLp2ABpAQABAAYKWBLp2ABpAQACAAEK/glWewAhAAAAAA==.Billyspikepr:BAAANQADCggIDQABNQAECgYIGAABAFgSAA==.Billyspikerg:BAAANQAECgYIDgABNQAECgYIGAABAFgSAA==.',
Bl='Black:BAAANQADCgMIAwAAAA==.Blobcat:BAABNQAECn8sAAIDAAkKjBWUJQCZAQADAAkKjBWUJQCZAQAAAA==.Blobknight:BAAANQAECgYIEAAAAA==.Bloodhase:BAABNQAECn8dAAMJAAoKOhrhIwByAgAJAAoKOhrhIwByAgAKAAQK3A7RogC1AAAAAA==.Bluecard:BAACNQAFFH8OAAMLAAYK9BfICABSAQALAAUKGBnICABSAQAMAAEKYhPWGgBQAAA1AAQKfyQAAwsACgpIIMxPAGUCAAsACAomIMxPAGUCAAwAAwo7IS1GAK4AAAAA.',
Bo='Bothenheim:BAACNQAFFH8RAAIBAAcKkBzAAwCeAQABAAcKkBzAAwCeAQA1AAQKfxwAAgEACQoQHE55ADkCAAEACQoQHE55ADkCAAAA.Bowdaddy:BAABNQAECn8qAAINAAgKQhaJeACCAQANAAgKQhaJeACCAQABNQAECggIKgANAEIWAA==.',
Br='Breakdown:BAABNQAECn8cAAIIAAcKVglaGQANAQAIAAcKVglaGQANAQAAAA==.Brewsimmons:BAAANQADCggIEAABNQAFFAcIFAAOAJQKAA==.',
Bu='Bublz:BAAANQADCgIIAgAAAA==.Bumpinuglies:BAAANQAECgMIBAAAAA==.Burdris:BAAANQABCgQIBAAAAA==.',
['Bü']='Büttshiv:BAAANQAECgYICAAAAA==.',
Ca='Cailey:BAAANQAECggICgABNQAECggICgAEAAAAAA==.Calcshortfor:BAAANQADCgQIBAAAAA==.Callamdrake:BAAANQADCgQJBQAAAA==.Callamsvoid:BAAANQAECgEIAQAAAA==.Calyrex:BAAANQADCgEIAQAAAA==.Camazotz:BAAANQAECggICAAAAA==.Capulse:BAACNQAFFH8SAAIPAAcKjBY6CQCMAQAPAAcKjBY6CQCMAQA1AAQKfxwABA8ACAp2HfxgAOsBAA8ABwqVHvxgAOsBABAABQrQFmiRALAAABEAAQoMAj8xADIAAAAA.Caredragon:BAAANQADCgIIAgAAAA==.Careglobo:BAAANQAECgMIBAAAAA==.Caylen:BAAANQAECggIAgABNQAFFAcIEgAPAIwWAA==.',
Ce='Centri:BAABNQAECn8iAAMSAAkKNiGGBQC4AgASAAcKWCKGBQC4AgATAAkKTxsNfgCCAgAAAA==.',
Ch='Chowa:BAAANQAECgEIAQAAAA==.Chrisnotwise:BAAANQAECgIIBAAAAA==.',
Cl='Clapdatazz:BAABNQAECn8UAAIFAAcK7Qd56wAMAQAFAAcK7Qd56wAMAQAAAA==.Cleverlev:BAAANQADCggIEQABNQAFFAMIBQAUAHILAA==.',
Co='Colapse:BAAANQADCgMIAwAAAA==.',
Cr='Crunchrr:BAAANQADCgEIAQAAAA==.',
Cu='Cubensis:BAAANQADCgcIHAAAAA==.',
Cy='Cyiera:BAAANQAECggICgAAAA==.',
Da='Daeland:BAABNQAECn8aAAIIAAgKXQorDwBGAQAIAAgKXQorDwBGAQAAAA==.Daisyshot:BAABNQAECn87AAMNAAoK+yBeGgAvAwANAAkKbiFeGgAvAwAVAAcKkRgQPABwAQAAAA==.Dalsham:BAAANQADCggIBgAAAA==.Dandakian:BAAANQAECggIAgAAAA==.',
De='Deathsgrace:BAAANQADCggICgAAAA==.Deathtank:BAAANQADCgMIAwAAAA==.Decima:BAABNQAECn8gAAIDAAoKgAcRWQBwAQADAAoKgAcRWQBwAQAAAA==.Dejustinfox:BAAANQADCgQIBwAAAA==.Demeter:BAACNQAFFH8PAAMVAAcK+RkaBwAxAQAVAAYKQBkaBwAxAQANAAMK+hmCKQCSAAA1AAQKfyMAAxUACgo4IZsTANABABUACQqKIJsTANABAA0ABAp9FlkBAQIBAAAA.Demonpunter:BAABNQAECn8bAAIWAAcKaB5WJgBrAgAWAAcKaB5WJgBrAgABNQAFFAcIEgAXAMAkAA==.',
Di='Diablita:BAAANQAECgYIBQAAAA==.Diabloa:BAAANQADCgQICAAAAA==.Diamba:BAAANQAECgUIBwABNQAECgYICwAEAAAAAA==.Dinoscarr:BAAANQAECgQIBAAAAA==.',
Do='Doohickey:BAAANQAECgYICgABNQAECgYICwAEAAAAAA==.Doohicky:BAAANQAECgYICwAAAA==.Dorgrim:BAAANQADCgMIAwAAAA==.Dotsndash:BAABNQAECn80AAIYAAoKtxpKGACRAgAYAAoKtxpKGACRAgAAAA==.',
Du='Dungpoo:BAAANQADCgEIAQAAAA==.',
Ea='Eargox:BAAANQAECgMIBAAAAA==.',
Ee='Eesa:BAABNQAECn8VAAIZAAcKZxhNRQDrAQAZAAcKZxhNRQDrAQAAAA==.',
El='Elinia:BAAANQADCgMIBAAAAA==.Elleteliara:BAAANQAECgEIAQAAAA==.Elmdor:BAAANQAECgMIAwAAAA==.Elyndra:BAAANQAECgUIDAAAAA==.',
En='Eniacoc:BAAANQAECgEIAQAAAA==.',
Ev='Everas:BAAANQAECgcIBwAAAA==.',
Ex='Excentric:BAAANQAECgIIAgABNQAECgkJIgASADYhAA==.Excentrics:BAAANQADCgUIBQABNQAECgkJIgASADYhAA==.',
Fa='Faithlyn:BAAANQADCgEIAQABNQAECgIIAgAEAAAAAA==.Falarth:BAABNQAECn8tAAIaAAoKuxMnJACvAQAaAAoKuxMnJACvAQAAAA==.Falloutman:BAABNQAECn8pAAICAAoKpxxhCQB5AgACAAoKpxxhCQB5AgAAAA==.Farther:BAAANQADCgUICQABNQAFFAcIGAATAD0bAA==.Fayne:BAAANQAECgMIBAAAAA==.',
Fe='Felfart:BAAANQADCgUIBQAAAA==.',
Fi='Firefox:BAACNQAFFH8FAAIaAAIKXhEnIwByAAAaAAIKXhEnIwByAAA1AAQKfyAAAxoACgofGHs3ACsCABoACgofGHs3ACsCAAoAAgriBl9nAFkAAAE1AAUUBggLABsAuhcA.',
Fl='Flechillas:BAAANQADCgcIDQAAAA==.Flán:BAABNQAECn8fAAIcAAkKJBHJKgDGAQAcAAkKJBHJKgDGAQAAAA==.',
Fr='Fraternite:BAAANQAECgYIBwAAAA==.',
Fu='Furrymoon:BAAANQADCgcIBwAAAA==.',
Ga='Gabriellad:BAAANQAECgYIDgAAAA==.',
Ge='Gerrakha:BAAANQADCgYIBgABNQAECggIDgAEAAAAAA==.',
Gi='Giterdonee:BAACNQAFFH8SAAMFAAcKfhLICQBiAQAFAAUKfhLICQBiAQAIAAIKAADcAgCpAAA1AAQKfycAAwgACgoiH5oFAMYCAAgACgp8HZoFAMYCAAUABwqzFIGxAKEBAAAA.',
Go='Goldielocks:BAAANQAECgQIBAAAAA==.Gorr:BAAANQADCgMIBgABNQAECgIIAgAEAAAAAA==.Gotchoo:BAABNQAECn8hAAIJAAgKuxFxTQCBAQAJAAgKuxFxTQCBAQABNQAECgIIAgAEAAAAAA==.Gothmommy:BAABNQAECn8yAAMZAAoKCBvPQgBhAgAZAAoKCBvPQgBhAgAYAAYKPAdALADqAAAAAA==.',
Gr='Grilledchis:BAAANQADCgIIAgAAAA==.Groldin:BAAANQAECggICQAAAA==.Grumble:BAAANQAECgQIBAAAAA==.',
['Gõ']='Gõtchoo:BAAANQAECgIIAgAAAA==.',
Ha='Hairball:BAABNQAECn8VAAIdAAgKyhHRBwDqAQAdAAgKyhHRBwDqAQAAAA==.Hammerthumb:BAAANQAECgMIAwABNQAECgkJJgADACgMAA==.Hardawn:BAAANQABCgEIAQABNQAFFAcIGAATAD0bAA==.',
Ho='Hotsoup:BAAANQADCgQJBAAAAA==.Hozzluzzak:BAAANQADCggICAAAAA==.',
Hy='Hyara:BAABNQAECn9PAAINAAoKwiSqBgBFAwANAAoKwiSqBgBFAwAAAA==.',
['Hù']='Hùñtarð:BAAANQAECgEIAgAAAA==.',
Im='Imnaked:BAAANQADCgYIBgABNQAECggIGwAEAAAAAA==.',
In='Invisimitch:BAAANQADCgEIAQAAAA==.',
Ip='Ips:BAAANQADCgIIAgABNQADCgUIBQAEAAAAAA==.',
Iv='Iv:BAAANQADCgYIBgAAAA==.',
Je='Jeffster:BAAANQAECgMIAwAAAA==.',
Ji='Jifman:BAAANQADCgYIBgAAAA==.',
Jo='Joffrey:BAAANQADCgcIEQAAAA==.Jordi:BAABNQAECn81AAINAAkKRR//KABwAgANAAkKRR//KABwAgAAAA==.Jotarcyon:BAAANQABCgIJAgAAAA==.',
Ju='Jukkes:BAAANQADCggIEwAAAA==.Justinfox:BAAANQADCgEIAQAAAA==.Juukess:BAAANQAECgIIAgAAAA==.',
Ka='Kannarri:BAAANQAECgMICgAAAA==.Kanree:BAACNQAFFH8XAAIUAAcKkQRVBAA2AQAUAAcKkQRVBAA2AQA1AAQKf0sAAhQACgpBE7QXAAICABQACgpBE7QXAAICAAAA.Kapriestsun:BAAANQAECgEIAQABNQAECgEIAQAEAAAAAA==.Kayaa:BAAANQADCggICAAAAA==.',
Ke='Kea:BAACNQAFFH8SAAMeAAUKnx54AABiAQAZAAUKQB2aCgC7AQAeAAQKkR54AABiAQA1AAQKf2IABBkACgpqJk0BAC0EABkACgpbJk0BAC0EAB4ACQoGJVQAAMEDABgABAonGSc+ADsBAAAA.Kek:BAABNQAECn8dAAIJAAkK2QiXQQBUAQAJAAkK2QiXQQBUAQAAAA==.',
Kh='Khaalid:BAAANQAECgEIAQABNQAECgoKNQAHAM0hAA==.Kharok:BAABNQAECn8yAAQIAAoKKx1KBQBSAgAGAAgK9iDNCADDAgAIAAoKqBpKBQBSAgAFAAYKVRjxpgC8AQABNQAECgoKNQAHAM0hAA==.',
Ki='Killhordex:BAAANQAECgEIAQAAAA==.Kincane:BAAANQADCgcICQAAAA==.Kittygirl:BAAANQABCgQIBAAAAA==.',
Ko='Korxin:BAACNQAFFH8PAAMVAAcKMRSKCwDeAAANAAQKDBT+GgDiAAAVAAUKvQyKCwDeAAA1AAQKf0UAAw0ACgoBIgYzANMCAA0ACgoBIgYzANMCABUABwrgF74WAKABAAAA.Kota:BAAANQADCgEIAQAAAA==.',
Ku='Kurnhaspios:BAAANQADCgQIBAAAAA==.Kurquaan:BAAANQAECgMIBAAAAA==.',
Ky='Kydraeth:BAAANQAECgIIAQAAAA==.',
La='Lanstyn:BAABNQAECn8vAAIeAAgK6RnTBAByAgAeAAgK6RnTBAByAgABNQAECgoKNQAHAM0hAA==.Laufey:BAABNQAECn8xAAITAAgK/ReYtgAWAgATAAgK/ReYtgAWAgAAAA==.',
Le='Lemone:BAAANQADCgUIBQAAAA==.Lemonsk:BAAANQADCgUICAAAAA==.Lennox:BAAANQADCgQIBAAAAA==.Lenton:BAAANQAECgEIAQAAAA==.',
Li='Lightfury:BAAANQADCgYIDAAAAA==.Limone:BAAANQAECgEIAQAAAA==.Listradra:BAAANQADCgQIBAAAAA==.',
Lo='Loganwater:BAAANQADCgQIBAAAAA==.Lokano:BAAANQADCgIIAgAAAA==.',
Lu='Ludmylha:BAAANQAECgcIDQAAAA==.Luisda:BAAANQADCggIFwAAAA==.Lull:BAAANQAECgIIAgAAAA==.Lushil:BAAANQAFFAEIAQAAAA==.',
Ly='Lyrea:BAAANQAECggICAAAAA==.',
Ma='Magidragon:BAAANQAECgIIAQAAAA==.Man:BAAANQADCgUIBQAAAA==.Marsangel:BAAANQADCgEIAQAAAA==.Marydavis:BAAANQABCgIIAgAAAA==.Maxerella:BAAANQADCgUIBQAAAA==.Maybell:BAAANQAECgUIEAAAAA==.',
Md='Mdavis:BAAANQADCgMIAwAAAA==.',
Me='Meepmeepmomp:BAAANQADCgUIBQAAAA==.Megumín:BAAANQAECgEIAQAAAA==.Melt:BAACNQAFFH8bAAQMAAcKfxhxCACvAAALAAQKORiSEADzAAAMAAIK5xhxCACvAAAXAAEKAAA6CQBcAAA1AAQKf0sAAwsACgpAJHUHABoDAAsACgrGI3UHABoDAAwABAoAIlAgAG4BAAAA.Mepha:BAACNQAFFH8PAAIKAAYKxQ6SAwAoAQAKAAYKxQ6SAwAoAQA1AAQKfzAAAwoACgrMHmwNAH0CAAoACgrMHmwNAH0CAAkACArhDJ9LAIsBAAAA.Meridia:BAAANQADCgMIAwAAAA==.Metons:BAAANQAECgEIAQABNQAECgkJHwAcACQRAA==.',
Mi='Miike:BAAANQADCgEIAQABNQAFFAcIGAATAD0bAA==.Mike:BAACNQAFFH8YAAMTAAcKPRvuDgBEAQATAAYK1BvuDgBEAQASAAEK4BgQCwBdAAA1AAQKf2sAAxMACgpgJAITAIcDABMACgpgJAITAIcDABIABQqUD0cfAPAAAAAA.Mikevoker:BAAANQADCgEIAQABNQAFFAcIGAATAD0bAA==.Mipz:BAAANQADCgUIBQAAAA==.Misfitdh:BAAANQAECgQIAwAAAA==.Misfitdk:BAAANQAECggIBAAAAA==.Misfitmagi:BAAANQAECgIIAgAAAA==.Misfittotem:BAAANQAECgMIAgAAAA==.Mistfox:BAAANQADCgYIDAAAAA==.Mistmommy:BAABNQAECn8vAAIUAAoKLxFhDwDdAQAUAAoKLxFhDwDdAQAAAA==.',
Mo='Mollieann:BAAANQAECgIIAgAAAA==.Mommon:BAAANQADCgEIAQAAAA==.Monreu:BAAANQAECgIIAgAAAA==.Morrighan:BAAANQADCgMIAwAAAA==.',
['Mâ']='Mâlus:BAAANQAECgUICAAAAA==.',
['Mä']='Märs:BAAANQADCgYICgAAAA==.',
Na='Nadra:BAAANQAECgQIBgAAAA==.Naminé:BAAANQADCgQIBAABNQAECggIMQATAP0XAA==.Naroka:BAAANQAECggIDgAAAA==.Nattyrav:BAACNQAFFH8IAAIQAAQKGRUpEwA/AQAQAAQKGRUpEwA/AQA1AAQKfyUAAxAACQp/Ghg9AIECABAACQp/Ghg9AIECAA8AAQpQHW0LAVEAAAAA.',
Ne='Neemesis:BAAANQAECgQIBAAAAA==.Nemonk:BAAANQAECggIDAABNQAECgkJGwATAMsKAA==.Nemoz:BAABNQAECn8bAAITAAkKywp/agCvAQATAAkKywp/agCvAQAAAA==.Nerfling:BAAANQADCgYICAAAAA==.',
No='Nocter:BAAANQAECgUIBQAAAA==.Noktor:BAAANQADCgYIBgAAAA==.Noktra:BAAANQAECgUIDwAAAA==.Nosey:BAAANQADCgUIBQAAAA==.',
Ny='Nylah:BAAANQAECgYIBgABNQAFFAUIEAAMAIUSAA==.Nymura:BAABNQAECn8kAAIBAAcKVg6i5gBOAQABAAcKVg6i5gBOAQAAAA==.',
Oa='Oakhugger:BAABNQAECn8mAAUDAAkKKAzZRQDaAAADAAYK7gnZRQDaAAAfAAUK+gvAKQB6AAAgAAIKqwPFWwA+AAAhAAEKygEQdwAUAAAAAA==.',
Ol='Olyvivia:BAAANQAECgcIBwAAAA==.',
Om='Omgega:BAABNQAECn82AAIBAAoK9RI7ZQDKAQABAAoK9RI7ZQDKAQAAAA==.',
On='Onichan:BAAANQAECgEIAQABNQAFFAgIFwAQAG0YAA==.Onimeek:BAABNQAECn9EAAIWAAoKDRkKHAD2AQAWAAoKDRkKHAD2AQAAAA==.Onionknightt:BAAANQAECgIIAQAAAA==.',
Or='Oryn:BAABNQAECn8XAAMSAAoKtRxsIwDRAAATAAcKmh6N0ADlAQASAAMKjBlsIwDRAAAAAA==.Oryx:BAAANQADCgEIAQAAAA==.',
Os='Osoloco:BAAANQADCgUIAwAAAA==.',
Pa='Palmpower:BAAANQADCgYICQAAAA==.Palpitations:BAAANQAECgEIAQAAAA==.Paper:BAAANQAFFAYIEAAAAQ==.',
Pe='Peacefullev:BAACNQAFFH8FAAIUAAMKcgtyBgC2AAAUAAMKcgtyBgC2AAA1AAQKfzsAAxQACgr5HooJAPICABQACgr5HooJAPICABwAAQoAAEdhAAAAAAAA.Pepegá:BAAANQAECgEIAQAAAA==.Pewpewpew:BAAANQAECgUICQAAAA==.',
Ph='Phantomthief:BAAANQAECggICwAAAA==.',
Pi='Pipeleto:BAABNQAECn9DAAIFAAoK9h7gJQAhAwAFAAoK9h7gJQAhAwAAAA==.Pizzaroll:BAABNQAECn9AAAIiAAoKJRUIBQCiAgAiAAoKJRUIBQCiAgAAAA==.',
Po='Podvoddonut:BAAANQADCgYIBgAAAA==.',
Pr='Previdius:BAAANQADCgUIBQAAAA==.Priesstess:BAAANQADCgYICQAAAA==.',
Pu='Puppyheals:BAAANQABCgQIBAAAAA==.',
['Pé']='Pépega:BAAANQADCgQIBwAAAA==.',
Re='Rei:BAAANQADCggICwAAAA==.',
Ri='Riellus:BAAANQAECgIIBAAAAA==.Riiu:BAAANQAECgYICAABNQAECgkJRAABAC8lAA==.Riven:BAAANQADCgYIBgAAAA==.Rixin:BAECNQAFFH8OAAMKAAUKFB4BCQCmAAAKAAQKFB4BCQCmAAAaAAEKAACbOwAcAAA1AAQKfzYAAgoACgrBI+EEABkDAAoACgrBI+EEABkDAAAA.',
Ro='Rokom:BAACNQAFFH8KAAMIAAQK1ReyAgCyAAAIAAMK5xqyAgCyAAAFAAEKsBGWPABHAAA1AAQKfy4AAwgACgoTHuMNANUBAAgABwoJIuMNANUBAAUABAptGDHqABABAAAA.Roonrano:BAAANQADCggICAAAAA==.',
Ru='Rumpus:BAAANQADCgcIBwAAAA==.Runed:BAAANQAECgEIAQAAAA==.',
Ry='Ryuk:BAAANQAECgQIBAAAAA==.',
Sa='Salla:BAAANQADCgYICQAAAA==.Saphh:BAAANQAECgEIAQABNQAFFAQIDwAJAHIYAA==.Saudencheek:BAAANQAECgQIBAAAAA==.',
Se='Seanster:BAABNQAECn8eAAMjAAkK+xKkIgBxAgAjAAkK+xKkIgBxAgAkAAMKQQJhGABeAAABNQAFFAUIEAAMAIUSAA==.Senecca:BAABNQAECn82AAIDAAoKdxySEwBWAgADAAoKdxySEwBWAgAAAA==.',
Sh='Shadowlily:BAAANQADCgMIAwABNQAECgkJNQAPALINAA==.Shadowms:BAABNQAECn86AAMlAAoKMh+cAwBFAwAlAAoKMh+cAwBFAwAmAAEKAABGJwAAAAAAAA==.Shadowxd:BAABNQAECn87AAQhAAoKaCFbAwCrAwAhAAoKaCFbAwCrAwADAAIKHQ5wZABtAAAgAAEKAACJYAAzAAAAAA==.Shamanpwnz:BAAANQAECgQIBgAAAA==.Shambassador:BAAANQAECggIEQAAAA==.Shamwowha:BAAANQADCgQIBAAAAA==.Sharkdancer:BAABNQAECn8UAAIbAAkKaB6OFQC4AgAbAAkKaB6OFQC4AgABNQAFFAcIDwAUAFQeAA==.Shaulana:BAAANQAECgEIAQABNQAECgkJNQAPALINAA==.Shenwu:BAABNQAECn8iAAIHAAoKxxjRDQAcAgAHAAoKxxjRDQAcAgAAAA==.Shirokuma:BAACNQAFFH8TAAMDAAcKCxN/BgCCAQADAAYKCxN/BgCCAQAgAAEKAADwCABfAAA1AAQKfyUAAwMACgo3HbsaAPMCAAMACgo3HbsaAPMCACAAAQrxFz5VAFAAAAAA.Shocktopuus:BAAANQADCgQIBAAAAA==.Shwizzle:BAAANQADCggIDgAAAA==.',
Si='Sidvicious:BAAANQADCgUIBAAAAA==.',
Sk='Sköllati:BAAANQAECgUIBAAAAA==.',
Sl='Slingshotz:BAAANQAECggIDwAAAA==.Sloppypoppy:BAAANQABCgUIBwAAAA==.',
Sm='Smarty:BAAANQAECgUIBAAAAA==.',
Sn='Sneakylev:BAABNQAECn85AAMnAAkK6RVZHgDfAQAnAAgKDxBZHgDfAQAjAAQKMRURLgDFAAABNQAFFAMIBQAUAHILAA==.',
So='Solari:BAABNQAECn8/AAMbAAoK1iT0AgCrAwAbAAoK1iT0AgCrAwAoAAUKIBhkFwA4AQAAAA==.Soleon:BAAANQAECgcIDgAAAA==.Solune:BAAANQAECgYIDAAAAA==.Souprage:BAAANQAECgMIBgAAAA==.',
Sp='Spypal:BAAANQADCgYIDAAAAA==.',
St='Stabwei:BAAANQADCggICAAAAA==.',
Su='Sugirokimami:BAAANQAECgYICwAAAA==.Sureshotz:BAAANQAECggICAAAAA==.',
Sw='Swagmastrflx:BAAANQADCgQIBAAAAA==.Swëëtdee:BAAANQADCgMICAAAAA==.',
Ta='Taehausx:BAAANQAFFAEIAQABNQAFFAcIFwAaAE4bAA==.Taraka:BAAANQAECgQIBAAAAA==.',
Td='Tdolokk:BAAANQADCggIFwAAAA==.',
Te='Teeward:BAAANQADCgYIBgAAAA==.Tenath:BAAANQAECgUICQAAAA==.Terribleturd:BAAANQAECgEIAQAAAA==.',
Th='Thaleon:BAAANQADCggICAAAAA==.Thauriel:BAAANQAECgEIAQAAAA==.Theexecution:BAAANQAECgQIAwAAAA==.Therella:BAAANQADCgUIBQAAAA==.',
Ti='Tinkerspell:BAAANQAECggIAgAAAA==.',
To='Totemtotebag:BAABNQAECn8XAAIPAAQK7BdpsAAOAQAPAAQK7BdpsAAOAQABNQAECgoKMAAgAH4lAA==.',
Tr='Treshaleth:BAAANQADCgQIBAAAAA==.Tripodg:BAABNQAECn8eAAISAAkKgQVnFQADAQASAAkKgQVnFQADAQAAAA==.Trollztoll:BAAANQADCgIIAgAAAA==.',
Tw='Twiddletime:BAAANQAECgQIBgAAAA==.',
['Tï']='Tïggy:BAAANQAECgcIBwAAAA==.',
Un='Una:BAABNQAECn8YAAIbAAgK6gxXIwBKAQAbAAgK6gxXIwBKAQAAAA==.Unholymisfit:BAAANQAECgIIBQAAAA==.Unholytato:BAAANQADCgQIBAAAAA==.',
Ur='Ursok:BAAANQAECgEIAQABNQAECgoKNQAHAM0hAA==.',
Ut='Uthok:BAAANQADCgUIBgAAAA==.',
Uz='Uzol:BAAANQADCgcICAAAAA==.',
Va='Vacalocà:BAAANQAECggICgAAAA==.Valerian:BAABNQAECn8bAAIDAAgK0wtINQAtAQADAAgK0wtINQAtAQAAAA==.Van:BAAANQADCgQIBAAAAA==.',
Ve='Veinke:BAABNQAECn8YAAIoAAgKJRk0CwAfAgAoAAgKJRk0CwAfAgAAAA==.Velanthir:BAAANQADCggIFAAAAA==.Verd:BAEANQAFFAEIAQAAAA==.Verevulf:BAAANQABCgIIAgAAAA==.Veronica:BAAANQABCgYIBgAAAA==.Versaacee:BAAANQADCgYIBgAAAA==.Vessarind:BAAANQADCgUIBQAAAA==.',
Vi='Vivrian:BAAANQADCgUIBQAAAA==.',
['Vä']='Vänillaicë:BAAANQADCgcIBwABNQAECgkJNQAPALINAA==.',
Wa='Waally:BAAANQAECgQIBQAAAA==.Wahwoo:BAAANQADCggIDgABNQAECgkJNQAPALINAA==.Walterlight:BAAANQAECgYIBgABNQAECgoKOwANAPsgAA==.',
We='Weebsora:BAAANQAECgQIBQAAAA==.',
Wo='Worldtree:BAAANQADCgEIAQAAAA==.',
Xa='Xaelthira:BAAANQADCgcIBwAAAA==.',
Ya='Yadhi:BAABNQAECn81AAIHAAoKzSH/AgBrAwAHAAoKzSH/AgBrAwAAAA==.',
Yi='Yimomo:BAABNQAECn81AAMZAAkKnx6iNACVAgAZAAkKnx6iNACVAgAYAAUKrAriLgDYAAAAAA==.',
Za='Zalconn:BAABNQAECn8sAAMnAAoKSiMXDQD1AgAnAAoKGiMXDQD1AgAjAAQKVyHeUgBxAQAAAA==.Zarrona:BAAANQAECgIIAwABNQAECggIMQATAP0XAA==.Zayah:BAAANQAFFAIIAwAAAA==.',
Zi='Zikony:BAAANQAECgYICAAAAA==.',
Zu='Zuber:BAABNQAECn8/AAIjAAoKNCELCABVAwAjAAoKNCELCABVAwAAAA==.',
['År']='Årtimus:BAAANQADCgcIEQAAAA==.',
['Öw']='Öwö:BAAANQAECgQIBAAAAA==.',
['Üw']='Üwü:BAABNQAECn8fAAMOAAgKphgLTQCsAQAOAAgKphgLTQCsAQABAAQKmRBrHAHvAAAAAA==.',
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
