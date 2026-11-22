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

local lookup = {'Paladin-Retribution','Paladin-Protection','Monk-Brewmaster','Druid-Balance','Hunter-BeastMastery','Warrior-Arms','Warrior-Protection','Unknown-Unknown','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Mage-Frost','Mage-Arcane','Monk-Mistweaver','Hunter-Marksmanship','DemonHunter-Havoc','Warlock-Affliction','DemonHunter-Devourer','Priest-Shadow','Priest-Holy','DeathKnight-Blood','Monk-Windwalker','Hunter-Survival','Priest-Discipline','Druid-Guardian','Druid-Feral','Druid-Restoration','Evoker-Augmentation','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','DemonHunter-Vengeance',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=53,date='2026-11-17',data={Ae='Aegrias:BAABNQAECn8lAAIBAAoK9BsyRQDFAgABAAoK9BsyRQDFAgAAAA==.Aerodria:BAABNQAECn9OAAICAAoKdhn1EQCBAgACAAoKdhn1EQCBAgAAAA==.',
Ak='Akarii:BAAANQAECgYIDAABNQAECgoKNQADAM0hAA==.Akeno:BAAANQAECgYIDAABNQAFFAcIEwAEAAsTAA==.',
Al='Alanril:BAAANQADCgMIAwAAAA==.Alarthevel:BAAANQAECgMIBAAAAA==.Albince:BAAANQADCgQIBAAAAA==.Aligh:BAAANQAECgEIAQAAAA==.Allastolan:BAAANQADCgIIAgABNQAECgoKIAAFAHUcAA==.',
Am='Amant:BAAANQADCggICQAAAA==.Amellis:BAAANQADCgIIAgAAAA==.',
An='Andeduty:BAAANQADCggIDQAAAA==.Andreasham:BAAANQAECgUICQAAAA==.Andreaswar:BAAANQAECgMIAwAAAA==.Anniferal:BAAANQAECgMIBAABNQAFFAcIEQAGANMWAA==.Annisseda:BAACNQAFFH8RAAIGAAcK0xabDwC9AQAGAAcK0xabDwC9AQA1AAQKfygAAwYACQopI8NOAJ0CAAYACQqHIsNOAJ0CAAcAAgoFIRIqAK4AAAAA.Anzak:BAAANQAECgQIBQAAAA==.',
Ar='Araelion:BAAANQADCgIIAgAAAA==.Ardrayshock:BAAANQABCgcJCgAAAA==.Ardrek:BAAANQADCggICAAAAA==.Arrhythmia:BAAANQAECggIEgABNQAFFAcIEAAIAAAAAQ==.',
As='Astrayn:BAAANQADCgIIAgAAAA==.',
Az='Azala:BAAANQAECgIIAgAAAA==.Azryx:BAAANQADCgcICQABNQAECgoKNQADAM0hAA==.Azzy:BAACNQAFFH8YAAIGAAcKvg+uEAA+AQAGAAcKvg+uEAA+AQA1AAQKf1gAAwYACgo/JU8JAEUDAAYACgomJU8JAEUDAAkACQpAILYDABMDAAAA.',
Ba='Bananski:BAAANQADCgcIBwAAAA==.',
Be='Beeflocks:BAAANQAECgUIBwABNQAECgoKMAAGAMYcAA==.Beefychunks:BAABNQAECn8wAAIGAAoKxhybKwCRAgAGAAoKxhybKwCRAgAAAA==.',
Bi='Bigbleu:BAAANQAECgQIBwABNQAFFAUICgAEAFMGAA==.Bigdraco:BAAANQADCgQIBQAAAA==.Biggums:BAAANQADCgQIBAAAAA==.Bigpapapump:BAAANQAECgMIAwAAAA==.Billyspikepd:BAABNQAECn8YAAMBAAYKWBLp2ABpAQABAAYKWBLp2ABpAQACAAEK/glWewAhAAABNQAECggIEgAIAAAAAA==.Billyspikepr:BAAANQADCggIDQABNQAECggIEgAIAAAAAA==.Billyspikerg:BAAANQAECggIEgAAAA==.',
Bl='Black:BAAANQADCgMIAwAAAA==.Blobcat:BAABNQAECn87AAIEAAoKMhbfHQATAgAEAAoKMhbfHQATAgAAAA==.Blobknight:BAABNQAECn8UAAIKAAYKURDQVwBMAQAKAAYKURDQVwBMAQAAAA==.Bloodhase:BAABNQAECn8dAAMKAAoKOhrhIwByAgAKAAoKOhrhIwByAgALAAQK3A7RogC1AAAAAA==.Bloodreign:BAAANQAECgMIAwABNQAECgoKNQADAM0hAA==.Bluecard:BAACNQAFFH8OAAMMAAYK9BcVDgBIAQAMAAUKGBkVDgBIAQANAAEKYhPWGgBQAAA1AAQKfyYAAwwACgpIIMxPAGUCAAwACAomIMxPAGUCAA0AAwo7IS1GAK4AAAAA.',
Bo='Bothenheim:BAACNQAFFH8RAAIBAAcKkBwnBwCKAQABAAcKkBwnBwCKAQA1AAQKfx0AAgEACQqNHE55ADkCAAEACQqNHE55ADkCAAAA.Bowdaddy:BAABNQAECn85AAIFAAoKLBmdMwB4AgAFAAoKLBmdMwB4AgABNQAECgoKOQAFACwZAA==.',
Br='Breakdown:BAABNQAECn8hAAIJAAgK3gkdGAACAQAJAAgK3gkdGAACAQAAAA==.Brewsimmons:BAAANQADCggIEAABNQAFFAcIFAAOAJQKAA==.',
Bu='Bublz:BAAANQADCgIIAgAAAA==.Bumpinuglies:BAAANQAECgUICAAAAA==.Burdris:BAAANQABCgQIBAAAAA==.',
['Bü']='Büttshiv:BAAANQAECggIEQAAAA==.',
Ca='Cailey:BAAANQAECggICgABNQAECggICgAIAAAAAA==.Calcshortfor:BAAANQADCgQIBAAAAA==.Callamdrake:BAAANQADCgQJBQAAAA==.Callamsvoid:BAAANQAECgEIAQAAAA==.Calyrex:BAAANQADCgEIAQAAAA==.Camazotz:BAAANQAECggICwAAAA==.Capulse:BAACNQAFFH8SAAIPAAcKjBYpCwCaAQAPAAcKjBYpCwCaAQA1AAQKfx0ABA8ACAoTIPxgAOsBAA8ABwqRIfxgAOsBABAABQrQFq/KAP0AABEAAQoMAmY4ADIAAAAA.Caredragon:BAAANQADCgIIAgAAAA==.Careglobo:BAABNQAECn8UAAIQAAcKCgwFdwAnAQAQAAcKCgwFdwAnAQAAAA==.Caylen:BAAANQAECggIAgABNQAFFAcIEgAPAIwWAA==.',
Ce='Centri:BAABNQAECn8iAAMSAAkKNiGGBQC4AgASAAcKWCKGBQC4AgATAAkKTxsNfgCCAgAAAA==.',
Ch='Chowa:BAAANQAECgEIAQAAAA==.Chrisnotwise:BAAANQAECgUICQAAAA==.',
Cl='Clapdatazz:BAABNQAECn8UAAIGAAcK7Qd56wAMAQAGAAcK7Qd56wAMAQAAAA==.Cleverlev:BAAANQAECgYICwABNQAFFAMIBQAUAHILAA==.',
Co='Colapse:BAAANQADCgMIAwAAAA==.',
Cr='Crunchrr:BAAANQADCgEIAQAAAA==.',
Cu='Cubensis:BAAANQADCgcIHAAAAA==.',
Cy='Cyiera:BAAANQAECggICgAAAA==.',
Da='Daeland:BAABNQAECn8fAAIJAAkKXgsUEAB6AQAJAAkKXgsUEAB6AQAAAA==.Daisyshot:BAABNQAECn8/AAMFAAoKviJeGgAvAwAFAAkKpSNeGgAvAwAVAAcKKRkQPABwAQAAAA==.Dalsham:BAAANQADCggIBgAAAA==.Dandakian:BAAANQAECggIAwAAAA==.',
De='Deathsgrace:BAAANQADCggICgAAAA==.Deathtank:BAAANQADCgQIBAAAAA==.Decima:BAABNQAECn8kAAIEAAoK5wcRWQBwAQAEAAoK5wcRWQBwAQAAAA==.Dejustinfox:BAAANQADCgQIBwAAAA==.Demeter:BAACNQAFFH8PAAMVAAcK+RnKCwAlAQAVAAYKQBnKCwAlAQAFAAMK+hmCKQCSAAA1AAQKfyYAAxUACgq5IboQADICABUACQoeIboQADICAAUABAp9FlkBAQIBAAAA.Demonpunter:BAABNQAECn8bAAIWAAcKaB5WJgBrAgAWAAcKaB5WJgBrAgABNQAFFAcIEgAXAMAkAA==.',
Di='Diablita:BAABNQAECn8WAAIYAAoKqg35GwDIAQAYAAoKqg35GwDIAQAAAA==.Diabloa:BAAANQADCgQICAAAAA==.Diamba:BAAANQAECgUIBwABNQAECgYICwAIAAAAAA==.Dinoscarr:BAAANQAECgQIBAAAAA==.',
Do='Doohickey:BAAANQAECgUICgABNQAECgYICwAIAAAAAA==.Doohicky:BAAANQAECgYICwAAAA==.Dorgrim:BAAANQADCgMIAwAAAA==.Dotsndash:BAABNQAECn81AAIZAAoKtxpKGACRAgAZAAoKtxpKGACRAgAAAA==.',
Du='Dungpoo:BAAANQADCgEIAQAAAA==.',
Ea='Eargox:BAAANQAECgMIBAAAAA==.',
Ee='Eesa:BAABNQAECn8VAAIaAAcKZxiSWQDXAQAaAAcKZxiSWQDXAQAAAA==.',
El='Elinia:BAAANQADCgMIBAAAAA==.Elleteliara:BAAANQAECgEIAQAAAA==.Elmdor:BAAANQAECgMIAwAAAA==.Elyndra:BAAANQAECgUIDQAAAA==.',
En='Eniacoc:BAAANQAECgEIAQAAAA==.',
Ev='Everas:BAAANQAECgYIBwAAAA==.',
Ex='Excentric:BAAANQAECgIIAgABNQAECgkJIgASADYhAA==.Excentrics:BAAANQADCgUIBQABNQAECgkJIgASADYhAA==.',
Fa='Faithlyn:BAAANQADCgEIAQABNQAECgMIAwAIAAAAAA==.Falarth:BAABNQAECn83AAIbAAoKkxTcKQCzAQAbAAoKkxTcKQCzAQAAAA==.Falloutman:BAABNQAECn8yAAICAAoKpxwaDABwAgACAAoKpxwaDABwAgAAAA==.Farther:BAAANQADCgUICQABNQAFFAgIGwATAAYXAA==.Fayne:BAAANQAECgUIDQAAAA==.',
Fe='Felfart:BAAANQADCgUIBQAAAA==.',
Fi='Firefox:BAACNQAFFH8FAAIbAAIKXhEnIwByAAAbAAIKXhEnIwByAAA1AAQKfyIAAxsACgofGHs3ACsCABsACgofGHs3ACsCAAsAAgoFB9tzAFcAAAAA.',
Fl='Flechillas:BAAANQADCgcIDQAAAA==.Flán:BAABNQAECn8fAAIcAAkKJBHJKgDGAQAcAAkKJBHJKgDGAQAAAA==.',
Fr='Fraternite:BAABNQAECn8VAAQOAAkKAw4mfQA+AQAOAAcK7gsmfQA+AQACAAUKVgZ6SgB7AAABAAIKDwHitwEbAAAAAA==.',
Fu='Furrymoon:BAAANQADCgcIBwAAAA==.',
Ga='Gabriellad:BAABNQAECn8kAAIBAAkKqgd+zQA8AQABAAkKqgd+zQA8AQAAAA==.',
Ge='Gerrakha:BAAANQADCgYIBgABNQAECgoKIAAFAHUcAA==.',
Gi='Giterdonee:BAACNQAFFH8SAAMGAAcKfhJlDwBSAQAGAAUKfhJlDwBSAQAJAAIKAADcAgCpAAA1AAQKfysAAwkACgoiH5oFAMYCAAkACgp8HZoFAMYCAAYABwpyGoGxAKEBAAAA.',
Go='Goldielocks:BAAANQAECggIDQAAAA==.Goodintent:BAAANQADCgEIAQAAAA==.Gorr:BAAANQADCgMIBgABNQAECgIIAgAIAAAAAA==.Gotchoo:BAABNQAECn8hAAIKAAgKuxFxTQCBAQAKAAgKuxFxTQCBAQABNQAECgIIAgAIAAAAAA==.Gothmommy:BAABNQAECn84AAMaAAoKCBvPQgBhAgAaAAoKCBvPQgBhAgAZAAYKPAcfNQDqAAAAAA==.',
Gr='Grilledchis:BAAANQADCgIIAgAAAA==.Griphöök:BAAANQAECgIIBAAAAA==.Groldin:BAAANQAECggICQAAAA==.Grumble:BAAANQAECgQIBAAAAA==.',
['Gõ']='Gõtchoo:BAAANQAECgIIAgAAAA==.',
Ha='Hairball:BAABNQAECn8WAAIdAAkK9xDRBwDqAQAdAAkK9xDRBwDqAQAAAA==.Hammerthumb:BAAANQAECgUIBwABNQAECgoKLgAEANgLAA==.Hardawn:BAAANQABCgEIAQABNQAFFAgIGwATAAYXAA==.',
Ho='Hornswoggle:BAAANQADCgQIBAAAAA==.Hotsoup:BAAANQADCgQJBAAAAA==.Hozzluzzak:BAAANQADCggICAAAAA==.',
Hy='Hyara:BAABNQAECn9YAAIFAAoKrCXzBgBVAwAFAAoKrCXzBgBVAwAAAA==.',
['Hù']='Hùñtarð:BAAANQAECgEIAgAAAA==.',
Im='Imnaked:BAAANQADCgYIBgABNQAECggIGwAIAAAAAA==.',
In='Invisimitch:BAAANQADCgEIAQAAAA==.',
Ip='Ips:BAAANQADCgIIAgABNQADCgUIBQAIAAAAAA==.',
Iv='Iv:BAAANQADCgYIBgAAAA==.',
Ja='Jabzulsor:BAAANQAECggICAAAAA==.',
Je='Jeffster:BAAANQAECgQIAwAAAA==.',
Ji='Jifman:BAAANQADCgYIBgAAAA==.',
Jo='Joffrey:BAAANQADCgcIEQAAAA==.Jordi:BAABNQAECn87AAIFAAkKRR8EMACEAgAFAAkKRR8EMACEAgAAAA==.Jotarcyon:BAAANQABCgIJAgAAAA==.',
Ju='Jukkes:BAAANQADCggIEwAAAA==.Justinfox:BAAANQADCgEIAQAAAA==.Juukess:BAAANQAECgIIAgAAAA==.',
Ka='Kannarri:BAAANQAECgUIEQAAAA==.Kanree:BAACNQAFFH8XAAIUAAcKkQT+BQA9AQAUAAcKkQT+BQA9AQA1AAQKf00AAhQACgpxFLQXAAICABQACgpxFLQXAAICAAAA.Kapriestsun:BAAANQAECgEIAQABNQAECgEIAQAIAAAAAA==.Kastre:BAAANQAECgIIAgAAAA==.Katherine:BAAANQADCgIIAgAAAA==.Kayaa:BAAANQADCggICAAAAA==.',
Ke='Kea:BAACNQAFFH8SAAMeAAUKnx6gAABcAQAaAAUKQB2/DwCrAQAeAAQKkR6gAABcAQA1AAQKf2UABB4ACgpqJlQAAMEDABoACgpbJgACACcEAB4ACQoKJVQAAMEDABkABAonGSc+ADsBAAAA.Kek:BAABNQAECn8pAAIKAAkKywyAQgCQAQAKAAkKywyAQgCQAQAAAA==.Kenny:BAAANQAECggICAABNQAFFAUIEAAFACsgAA==.',
Kh='Khaalid:BAAANQAECgEIAQABNQAECgoKNQADAM0hAA==.Kharok:BAABNQAECn8yAAQJAAoKKx1PBwBBAgAHAAgK9iDNCADDAgAJAAoKqBpPBwBBAgAGAAYKVRjxpgC8AQABNQAECgoKNQADAM0hAA==.',
Ki='Killajccxx:BAAANQAECgEIAQAAAA==.Killhordex:BAAANQAECgEIAgAAAA==.Killhordx:BAAANQABCgcICgAAAA==.Kincane:BAAANQADCgcICQAAAA==.Kittygirl:BAAANQABCgQIBAAAAA==.',
Ko='Korxin:BAACNQAFFH8PAAMFAAcKMRT+GgDiAAAFAAQKDBT+GgDiAAAVAAUKvQw7EQDXAAA1AAQKf04AAwUACgqNIgYzANMCAAUACgqNIgYzANMCABUABwrgF84bAKABAAAA.Kota:BAAANQADCgEIAQAAAA==.',
Ku='Kurnhaspios:BAAANQADCgQIBAAAAA==.Kurquaan:BAAANQAECgMIBAAAAA==.',
Ky='Kydraeth:BAAANQAECgIIAQAAAA==.',
La='Lanstyn:BAABNQAECn8vAAIeAAgK6RnTBAByAgAeAAgK6RnTBAByAgABNQAECgoKNQADAM0hAA==.Laufey:BAABNQAECn8xAAITAAgK/ReYtgAWAgATAAgK/ReYtgAWAgAAAA==.',
Le='Lemone:BAAANQADCgUIBQAAAA==.Lemonsk:BAAANQADCgUICAAAAA==.Lennox:BAAANQADCgQIBAAAAA==.Lenton:BAAANQAECgEIAQAAAA==.',
Li='Lightfury:BAAANQADCgYIDAAAAA==.Limone:BAAANQAECgEIAQAAAA==.Listradra:BAAANQADCgQIBAAAAA==.',
Lo='Loganwater:BAAANQADCgQIBAAAAA==.Loinari:BAAANQADCgUIDQAAAA==.Lokano:BAAANQADCgIIAgAAAA==.',
Lu='Ludmylha:BAABNQAECn8XAAIQAAkKkgqMZwBQAQAQAAkKkgqMZwBQAQAAAA==.Luisda:BAAANQADCggIFwAAAA==.Lull:BAAANQAECggICgAAAA==.Lushil:BAAANQAFFAEIAQAAAA==.',
Ly='Lyrea:BAAANQAECggICAAAAA==.',
Ma='Magidragon:BAAANQAECgMIAwAAAA==.Magnusthered:BAAANQADCgcICAAAAA==.Man:BAAANQADCgUIBQAAAA==.Marsangel:BAAANQADCgEIAQAAAA==.Marydavis:BAAANQABCgIIAgAAAA==.Maxerella:BAAANQADCgUIBQAAAA==.Maybell:BAABNQAECn8mAAIRAAkKegQsHwAxAQARAAkKegQsHwAxAQAAAA==.',
Md='Mdavis:BAAANQADCgMIAwAAAA==.',
Me='Meepmeepmomp:BAAANQADCgUIBQAAAA==.Megumín:BAAANQAECgEIAQAAAA==.Melt:BAACNQAFFH8bAAQNAAcKfxhxCACvAAAMAAQKORhDFwDtAAANAAIK5xhxCACvAAAXAAEKAAA6CQBcAAA1AAQKf1UAAwwACgpAJPYLAAsDAAwACgrGI/YLAAsDAA0ABAoAIlAgAG4BAAAA.Mepha:BAACNQAFFH8QAAILAAcKMw0gAwBnAQALAAcKMw0gAwBnAQA1AAQKfzEAAwsACgr3HmkQAH0CAAsACgr3HmkQAH0CAAoACArhDJ9LAIsBAAAA.Meridia:BAAANQADCgMIAwAAAA==.Metons:BAAANQAECgEIAQABNQAECgkJHwAcACQRAA==.',
Mi='Miike:BAAANQADCgEIAQABNQAFFAgIGwATAAYXAA==.Mike:BAACNQAFFH8bAAMTAAgKBhe7EAB7AQATAAcKpxa7EAB7AQASAAEK4BhODwBUAAA1AAQKf3gAAxMACgoxJUUIAEMDABMACgoxJUUIAEMDABIABQqUD0cfAPAAAAAA.Mikevoker:BAAANQADCgEIAQABNQAFFAgIGwATAAYXAA==.Mipz:BAAANQADCgUIBQAAAA==.Misfitdh:BAAANQAECgMIAwAAAA==.Misfitdk:BAAANQAECggIBAAAAA==.Misfitmagi:BAAANQAECgIIAgAAAA==.Misfittotem:BAAANQAECgIIAgAAAA==.Mistfox:BAAANQADCgYIDAAAAA==.Mistmommy:BAABNQAECn83AAIUAAoKQxNmEQD3AQAUAAoKQxNmEQD3AQAAAA==.',
Mo='Mollieann:BAAANQAECgMIAwAAAA==.Mommon:BAAANQADCgEIAQAAAA==.Monreu:BAAANQAECgIIAgAAAA==.Morrighan:BAAANQADCgMIAwAAAA==.',
['Mâ']='Mâlus:BAAANQAECgUICAAAAA==.',
['Mä']='Märs:BAAANQADCgYICgAAAA==.',
Na='Nadra:BAAANQAECgYIDgAAAA==.Naminé:BAAANQADCgQIBAABNQAECggIMQATAP0XAA==.Naroka:BAABNQAECn8gAAIFAAoKdRzbJQCnAgAFAAoKdRzbJQCnAgAAAA==.Nattyrav:BAACNQAFFH8IAAIQAAQKGRUpEwA/AQAQAAQKGRUpEwA/AQA1AAQKfyUAAxAACQp/Ghg9AIECABAACQp/Ghg9AIECAA8AAQpQHW0LAVEAAAAA.',
Ne='Neemesis:BAAANQAECgQIBAAAAA==.Nemonk:BAAANQAECggIDAABNQAECgkJGwATAMsKAA==.Nemoz:BAABNQAECn8bAAITAAkKywq9fgCtAQATAAkKywq9fgCtAQAAAA==.Nerfling:BAAANQADCgYICAAAAA==.',
No='Nocter:BAAANQAECgUIBQAAAA==.Noktor:BAAANQADCgYIBgAAAA==.Noktra:BAAANQAECgUIDwAAAA==.Nosey:BAAANQADCgUIBQAAAA==.',
Ny='Nylah:BAAANQAECgYIBgABNQAFFAUIEAANAIUSAA==.Nymura:BAABNQAECn8lAAIBAAgKaA3F3wAeAQABAAgKaA3F3wAeAQAAAA==.',
Oa='Oakhugger:BAABNQAECn8uAAUEAAoK2AugUQDYAAAEAAYK7gmgUQDYAAAfAAYKaQfeTQCHAAAgAAUK+gtnNQB4AAAhAAEKygFTiAAUAAAAAA==.',
Ol='Olyvivia:BAAANQAECgcIBwAAAA==.',
Om='Omgega:BAABNQAECn9JAAIBAAoKFxR7dADmAQABAAoKFxR7dADmAQAAAA==.',
On='Onichan:BAAANQAECgEIAQABNQAFFAkJGQAQAOYXAA==.Onimeek:BAABNQAECn9IAAIWAAoKDRl+IwDuAQAWAAoKDRl+IwDuAQAAAA==.Onionknightt:BAAANQAECgIIAQAAAA==.',
Or='Oryn:BAABNQAECn8XAAMSAAoKtRxsIwDRAAATAAcKmh6N0ADlAQASAAMKjBlsIwDRAAABNQAECggIFAATAA4cAA==.Oryx:BAAANQADCgEIAQAAAA==.',
Os='Osoloco:BAAANQADCgUIAwAAAA==.',
Pa='Palmpower:BAAANQADCgYICQAAAA==.Palpitations:BAAANQAECgEIAQAAAA==.Paper:BAAANQAFFAcIEAAAAQ==.',
Pe='Peacefullev:BAACNQAFFH8FAAIUAAMKcgtuCACwAAAUAAMKcgtuCACwAAA1AAQKf04AAxQACgr5HgsGADIDABQACgr5HgsGADIDABwABAoND1Y+ALwAAAAA.Pepegá:BAAANQAECgEIAQAAAA==.Pewpewpew:BAAANQAECgUICQAAAA==.',
Ph='Phantomthief:BAAANQAECggICwAAAA==.',
Pi='Pipeleto:BAABNQAECn9DAAIGAAoK9h7gJQAhAwAGAAoK9h7gJQAhAwAAAA==.Pizzaroll:BAABNQAECn9AAAIiAAoKJRUIBQCiAgAiAAoKJRUIBQCiAgAAAA==.',
Po='Podvoddonut:BAAANQADCgYIBgAAAA==.',
Pr='Previdius:BAAANQADCgUIBQAAAA==.Priesstess:BAAANQADCgYICQAAAA==.',
Pu='Puppyheals:BAAANQABCgQIBAAAAA==.',
['Pé']='Pépega:BAAANQADCgQIBwAAAA==.',
Re='Rei:BAAANQAECgYIDgAAAA==.',
Ri='Riellus:BAAANQAECgIIBAAAAA==.Riiu:BAAANQAECgYICAABNQAECgkJRQABAC8lAA==.Riven:BAAANQADCgYIBgAAAA==.Rixin:BAECNQAFFH8OAAMLAAUKFB5fCwCiAAALAAQKFB5fCwCiAAAbAAEKAACbOwAcAAA1AAQKf0AAAgsACgq/JCcDAE4DAAsACgq/JCcDAE4DAAAA.',
Ro='Rokom:BAACNQAFFH8LAAMJAAUKPRWyAgCyAAAJAAMK5xqyAgCyAAAGAAIKlA+XMwBPAAA1AAQKfzAAAwkACgo2HuMNANUBAAkABwpAIuMNANUBAAYABAptGDHqABABAAAA.Roonrano:BAAANQADCggICAAAAA==.',
Ru='Rumpus:BAAANQADCgcIBwAAAA==.Runed:BAAANQAECgEIAQAAAA==.',
Ry='Ryuk:BAAANQAECgQIBAAAAA==.',
Sa='Salla:BAAANQADCgYICQAAAA==.Saphh:BAAANQAECgEIAQABNQAFFAQIDwAKAHIYAA==.Saudencheek:BAAANQAECgQIBAAAAA==.',
Se='Seanster:BAABNQAECn8eAAMjAAkK+xKkIgBxAgAjAAkK+xKkIgBxAgAkAAMKQQJhGABeAAABNQAFFAUIEAANAIUSAA==.Senecca:BAABNQAECn86AAIEAAoKsxzTFgBcAgAEAAoKsxzTFgBcAgAAAA==.',
Sh='Shadowlily:BAAANQADCgMIAwABNQAECggIDAAIAAAAAA==.Shadowms:BAABNQAECn9EAAMlAAoK2R+EAwByAwAlAAoK2R+EAwByAwAmAAEKAABjLAAAAAAAAA==.Shadowxd:BAABNQAECn9GAAQhAAoKbiG+BACmAwAhAAoKbiG+BACmAwAEAAMKtA3ZYACgAAAfAAEKAACJYAAzAAAAAA==.Shamanpwnz:BAAANQAECgQIBgAAAA==.Shambassador:BAAANQAECggIEQAAAA==.Shamwowha:BAAANQADCgQIBAAAAA==.Sharkdancer:BAABNQAECn8UAAIYAAkKaB6OFQC4AgAYAAkKaB6OFQC4AgABNQAFFAcIDwAUAFQeAA==.Shaulana:BAAANQAECggIDAAAAA==.Shenwu:BAABNQAECn8mAAIDAAoKxxjRDQAcAgADAAoKxxjRDQAcAgAAAA==.Shirokuma:BAACNQAFFH8TAAMEAAcKCxNmCgB3AQAEAAYKCxNmCgB3AQAfAAEKAADwCABfAAA1AAQKfycAAwQACgo3HbsaAPMCAAQACgo3HbsaAPMCAB8AAQrxFz5VAFAAAAAA.Shocktopuus:BAAANQADCgQIBAAAAA==.Shwizzle:BAAANQADCggIDgAAAA==.',
Si='Sidvicious:BAAANQADCgUIBAAAAA==.',
Sk='Sköllati:BAAANQAECgUIBAAAAA==.',
Sl='Slingshotz:BAAANQAECgcIEQAAAA==.Sloppypoppy:BAAANQABCgUIBwAAAA==.',
Sm='Smarty:BAAANQAECgUIBAAAAA==.',
Sn='Sneakylev:BAABNQAECn9LAAMnAAkKTxhZHgDfAQAnAAgKIxJZHgDfAQAjAAQKRRasLQDXAAABNQAFFAMIBQAUAHILAA==.',
So='Solari:BAABNQAECn9BAAMYAAoK1iT0AgCrAwAYAAoK1iT0AgCrAwAoAAUKIBhkFwA4AQAAAA==.Soleon:BAAANQAECgcIDgAAAA==.Solune:BAAANQAECgYIDAAAAA==.Souprage:BAAANQAECgMIBgAAAA==.',
Sp='Spypal:BAAANQADCgYIDAAAAA==.',
St='Stabwei:BAAANQADCggICAAAAA==.',
Su='Sugirokimami:BAAANQAECgYICwAAAA==.Sureshotz:BAAANQAECggICAAAAA==.',
Sw='Swagmastrflx:BAAANQADCgQIBAAAAA==.Swëëtdee:BAAANQADCgMICAAAAA==.',
Ta='Taehausx:BAAANQAFFAEIAQABNQAFFAcIHgAbABciAA==.Taraka:BAAANQAECgQIBAAAAA==.',
Td='Tdolokk:BAAANQADCggIFwAAAA==.',
Te='Teal:BAAANQAECgcIBwAAAA==.Teeward:BAAANQADCgYIBgAAAA==.Tenath:BAAANQAECgUICQAAAA==.Terribleturd:BAAANQAECgEIAQAAAA==.',
Th='Thaleon:BAAANQADCggICAAAAA==.Thauriel:BAAANQAECgEIAQAAAA==.Theexecution:BAAANQAECgQIAwAAAA==.Therella:BAAANQADCgUIBQAAAA==.',
Ti='Timert:BAAANQAECggIBgAAAA==.Tinkerspell:BAAANQAECggIAgAAAA==.',
To='Totemtotebag:BAABNQAECn8XAAIPAAQK7BdpsAAOAQAPAAQK7BdpsAAOAQABNQAECgoKOQAfAMolAA==.',
Tr='Treponeme:BAAANQAECgYICwABNQAECgoKLgAEANgLAA==.Treshaleth:BAAANQADCgQIBAAAAA==.Tripodg:BAABNQAECn8wAAISAAkKwgfIFgAxAQASAAkKwgfIFgAxAQAAAA==.Trollztoll:BAAANQADCgIIAgAAAA==.',
Tw='Twiddletime:BAAANQAECgQIBgAAAA==.',
['Tï']='Tïggy:BAAANQAECgcIBwAAAA==.',
Un='Una:BAABNQAECn8gAAIYAAoKEA0XHgC0AQAYAAoKEA0XHgC0AQAAAA==.Unholymisfit:BAAANQAECgMIBQAAAA==.Unholytato:BAAANQADCgQIBAAAAA==.',
Ur='Ursok:BAAANQAECgEIAQABNQAECgoKNQADAM0hAA==.',
Ut='Uthok:BAAANQADCgUIBgAAAA==.',
Uz='Uzol:BAAANQADCgcICAAAAA==.',
Va='Vacalocà:BAAANQAECggICgAAAA==.Valerian:BAABNQAECn8gAAIEAAoK/wypLACeAQAEAAoK/wypLACeAQAAAA==.Van:BAAANQADCgQIBAAAAA==.',
Ve='Veinke:BAABNQAECn8YAAIoAAgKJRk0CwAfAgAoAAgKJRk0CwAfAgAAAA==.Velanthir:BAAANQADCggIFAAAAA==.Verd:BAEANQAFFAEIAQAAAA==.Verevulf:BAAANQABCgMIAgAAAA==.Veronica:BAAANQABCgYIBgAAAA==.Versaacee:BAAANQADCgYIBgAAAA==.Vessarind:BAAANQADCgUIBQAAAA==.',
Vi='Vivrian:BAAANQADCgUIBQAAAA==.',
['Vä']='Vänillaicë:BAAANQADCggIDAABNQAECggIDAAIAAAAAA==.',
Wa='Waally:BAAANQAECgQIBQAAAA==.Wahwoo:BAAANQAECgQIBAABNQAECggIDAAIAAAAAA==.Walterlight:BAAANQAECgYIBgABNQAECgoKPwAFAL4iAA==.',
We='Weebsora:BAAANQAECgQIBQAAAA==.',
Wo='Worldtree:BAAANQADCgEIAQAAAA==.',
Xa='Xaelthira:BAAANQADCgcIBwAAAA==.',
Ya='Yadhi:BAABNQAECn81AAIDAAoKzSH/AgBrAwADAAoKzSH/AgBrAwAAAA==.',
Yi='Yimomo:BAABNQAECn81AAMaAAkKnx6iNACVAgAaAAkKnx6iNACVAgAZAAUKrAoqOADYAAAAAA==.',
Za='Zalconn:BAABNQAECn8sAAMnAAoKSiPUDwD4AgAnAAoKGiPUDwD4AgAjAAQKVyHeUgBxAQAAAA==.Zarrona:BAAANQAECgIIAwABNQAECggIMQATAP0XAA==.Zayah:BAAANQAFFAIIAwAAAA==.',
Zi='Zikony:BAAANQAECgYICAAAAA==.',
Zu='Zuber:BAABNQAECn8/AAIjAAoKNCELCABVAwAjAAoKNCELCABVAwAAAA==.',
['År']='Årtimus:BAAANQADCgcIEQAAAA==.',
['Öw']='Öwö:BAAANQAECgQIBAAAAA==.',
['Üw']='Üwü:BAABNQAECn8fAAMOAAgKphipXACmAQAOAAgKphipXACmAQABAAQKmRBrHAHvAAAAAA==.',
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
