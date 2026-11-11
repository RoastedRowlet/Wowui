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

local lookup = {'Paladin-Retribution','Paladin-Protection','Monk-Brewmaster','Druid-Balance','Hunter-BeastMastery','Warrior-Arms','Warrior-Protection','Unknown-Unknown','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Mage-Frost','Mage-Arcane','Monk-Mistweaver','Hunter-Marksmanship','DemonHunter-Havoc','Warlock-Affliction','Priest-Shadow','Priest-Holy','DeathKnight-Blood','DemonHunter-Devourer','Monk-Windwalker','Hunter-Survival','Priest-Discipline','Druid-Guardian','Druid-Feral','Druid-Restoration','Evoker-Augmentation','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','DemonHunter-Vengeance',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=53,date='2026-11-10',data={Ae='Aegrias:BAABNQAECn8lAAIBAAoK9BsyRQDFAgABAAoK9BsyRQDFAgAAAA==.Aerodria:BAABNQAECn9OAAICAAoKdhn1EQCBAgACAAoKdhn1EQCBAgAAAA==.',
Ak='Akarii:BAAANQAECgYIBwABNQAECgoKNQADAM0hAA==.Akeno:BAAANQAECgUIDAABNQAFFAcIEwAEAAsTAA==.',
Al='Alanril:BAAANQADCgMIAwAAAA==.Alarthevel:BAAANQAECgMIBAAAAA==.Albince:BAAANQADCgQIBAAAAA==.Aligh:BAAANQAECgEIAQAAAA==.Allastolan:BAAANQADCgIIAgABNQAECgoKGwAFAFQcAA==.',
Am='Amant:BAAANQADCggICQAAAA==.Amellis:BAAANQADCgIIAgAAAA==.',
An='Andeduty:BAAANQADCggIDQAAAA==.Andreasham:BAAANQAECgUICQAAAA==.Andreaswar:BAAANQAECgMIAwAAAA==.Anniferal:BAAANQAECgMIBAABNQAFFAcIEQAGANMWAA==.Annisseda:BAACNQAFFH8RAAIGAAcK0xabDwC9AQAGAAcK0xabDwC9AQA1AAQKfygAAwYACQopI8NOAJ0CAAYACQqHIsNOAJ0CAAcAAgoFIdcmALAAAAAA.Anzak:BAAANQAECgQIBQAAAA==.',
Ar='Araelion:BAAANQADCgIIAgAAAA==.Ardrayshock:BAAANQABCgcJCgAAAA==.Ardrek:BAAANQADCggICAAAAA==.Arrhythmia:BAAANQAECggIEgABNQAFFAYIEgAIAAAAAQ==.',
As='Astrayn:BAAANQADCgIIAgAAAA==.',
Az='Azala:BAAANQAECgIIAgAAAA==.Azryx:BAAANQADCgcICQABNQAECgoKNQADAM0hAA==.Azzy:BAACNQAFFH8YAAIGAAcKvg+mDQBIAQAGAAcKvg+mDQBIAQA1AAQKf1cAAwYACgrUJJAJAD8DAAYACgq7JJAJAD8DAAkACQpAILYDABMDAAAA.',
Ba='Bananski:BAAANQADCgcIBwAAAA==.',
Be='Beeflocks:BAAANQAECgUIBwABNQAECgoKMAAGAMYcAA==.Beefychunks:BAABNQAECn8wAAIGAAoKxhyiJgCbAgAGAAoKxhyiJgCbAgAAAA==.',
Bi='Bigbleu:BAAANQAECgQIBwABNQAFFAQIBQAEAOICAA==.Bigdraco:BAAANQADCgQIBQAAAA==.Biggums:BAAANQADCgQIBAAAAA==.Bigpapapump:BAAANQAECgMIAwAAAA==.Billyspikepd:BAABNQAECn8YAAMBAAYKWBLp2ABpAQABAAYKWBLp2ABpAQACAAEK/glWewAhAAABNQAECggIEQAIAAAAAA==.Billyspikepr:BAAANQADCggIDQABNQAECggIEQAIAAAAAA==.Billyspikerg:BAAANQAECggIEQAAAA==.',
Bl='Black:BAAANQADCgMIAwAAAA==.Blobcat:BAABNQAECn8zAAIEAAkK3hbfIgDRAQAEAAkK3hbfIgDRAQAAAA==.Blobknight:BAABNQAECn8UAAIKAAYKURDQVwBMAQAKAAYKURDQVwBMAQAAAA==.Bloodhase:BAABNQAECn8dAAMKAAoKOhrhIwByAgAKAAoKOhrhIwByAgALAAQK3A7RogC1AAAAAA==.Bluecard:BAACNQAFFH8OAAMMAAYK9BdnCwBQAQAMAAUKGBlnCwBQAQANAAEKYhPWGgBQAAA1AAQKfyYAAwwACgpIIMxPAGUCAAwACAomIMxPAGUCAA0AAwo7IS1GAK4AAAAA.',
Bo='Bothenheim:BAACNQAFFH8RAAIBAAcKkBxjBQCRAQABAAcKkBxjBQCRAQA1AAQKfx0AAgEACQqNHE55ADkCAAEACQqNHE55ADkCAAAA.Bowdaddy:BAABNQAECn8wAAIFAAgKiBmWYwDlAQAFAAgKiBmWYwDlAQABNQAECggIMAAFAIgZAA==.',
Br='Breakdown:BAABNQAECn8gAAIJAAcKVgkXGQDaAAAJAAcKVgkXGQDaAAAAAA==.Brewsimmons:BAAANQADCggIEAABNQAFFAcIFAAOAJQKAA==.',
Bu='Bublz:BAAANQADCgIIAgAAAA==.Bumpinuglies:BAAANQAECgUICAAAAA==.Burdris:BAAANQABCgQIBAAAAA==.',
['Bü']='Büttshiv:BAAANQAECggIEQAAAA==.',
Ca='Cailey:BAAANQAECggICgABNQAECggICgAIAAAAAA==.Calcshortfor:BAAANQADCgQIBAAAAA==.Callamdrake:BAAANQADCgQJBQAAAA==.Callamsvoid:BAAANQAECgEIAQAAAA==.Calyrex:BAAANQADCgEIAQAAAA==.Camazotz:BAAANQAECggICwAAAA==.Capulse:BAACNQAFFH8SAAIPAAcKjBYpCwCaAQAPAAcKjBYpCwCaAQA1AAQKfx0ABA8ACAoTIPxgAOsBAA8ABwqRIfxgAOsBABAABQrQFoGhAK8AABEAAQoMAlI1ADIAAAAA.Caredragon:BAAANQADCgIIAgAAAA==.Careglobo:BAAANQAECgUIDQAAAA==.Caylen:BAAANQAECggIAgABNQAFFAcIEgAPAIwWAA==.',
Ce='Centri:BAABNQAECn8iAAMSAAkKNiGGBQC4AgASAAcKWCKGBQC4AgATAAkKTxsNfgCCAgAAAA==.',
Ch='Chowa:BAAANQAECgEIAQAAAA==.Chrisnotwise:BAAANQAECgIIBAAAAA==.',
Cl='Clapdatazz:BAABNQAECn8UAAIGAAcK7Qd56wAMAQAGAAcK7Qd56wAMAQAAAA==.Cleverlev:BAAANQAECgYIBgABNQAFFAMIBQAUAHILAA==.',
Co='Colapse:BAAANQADCgMIAwAAAA==.',
Cr='Crunchrr:BAAANQADCgEIAQAAAA==.',
Cu='Cubensis:BAAANQADCgcIHAAAAA==.',
Cy='Cyiera:BAAANQAECggICgAAAA==.',
Da='Daeland:BAABNQAECn8eAAIJAAkKMguuDgB6AQAJAAkKMguuDgB6AQAAAA==.Daisyshot:BAABNQAECn8/AAMFAAoKviJeGgAvAwAFAAkKpSNeGgAvAwAVAAcKKRkQPABwAQAAAA==.Dalsham:BAAANQADCggIBgAAAA==.Dandakian:BAAANQAECggIAgAAAA==.',
De='Deathsgrace:BAAANQADCggICgAAAA==.Deathtank:BAAANQADCgQIBAAAAA==.Decima:BAABNQAECn8gAAIEAAoKgAcRWQBwAQAEAAoKgAcRWQBwAQAAAA==.Dejustinfox:BAAANQADCgQIBwAAAA==.Demeter:BAACNQAFFH8PAAMVAAcK+Rm1CQArAQAVAAYKQBm1CQArAQAFAAMK+hmCKQCSAAA1AAQKfyUAAxUACgq6IXwPADcCABUACQofIXwPADcCAAUABAp9FlkBAQIBAAAA.Demonpunter:BAABNQAECn8bAAIWAAcKaB5WJgBrAgAWAAcKaB5WJgBrAgABNQAFFAcIEgAXAMAkAA==.',
Di='Diablita:BAAANQAECggIDQAAAA==.Diabloa:BAAANQADCgQICAAAAA==.Diamba:BAAANQAECgUIBwABNQAECgYICwAIAAAAAA==.Dinoscarr:BAAANQAECgQIBAAAAA==.',
Do='Doohickey:BAAANQAECgUICgABNQAECgYICwAIAAAAAA==.Doohicky:BAAANQAECgYICwAAAA==.Dorgrim:BAAANQADCgMIAwAAAA==.Dotsndash:BAABNQAECn81AAIYAAoKtxpKGACRAgAYAAoKtxpKGACRAgAAAA==.',
Du='Dungpoo:BAAANQADCgEIAQAAAA==.',
Ea='Eargox:BAAANQAECgMIBAAAAA==.',
Ee='Eesa:BAABNQAECn8VAAIZAAcKZxgWUQDfAQAZAAcKZxgWUQDfAQAAAA==.',
El='Elinia:BAAANQADCgMIBAAAAA==.Elleteliara:BAAANQAECgEIAQAAAA==.Elmdor:BAAANQAECgMIAwAAAA==.Elyndra:BAAANQAECgUIDAAAAA==.',
En='Eniacoc:BAAANQAECgEIAQAAAA==.',
Ev='Everas:BAAANQAECgYIBwAAAA==.',
Ex='Excentric:BAAANQAECgIIAgABNQAECgkJIgASADYhAA==.Excentrics:BAAANQADCgUIBQABNQAECgkJIgASADYhAA==.',
Fa='Faithlyn:BAAANQADCgEIAQABNQAECgIIAgAIAAAAAA==.Falarth:BAABNQAECn80AAIaAAoKkxSvJgC5AQAaAAoKkxSvJgC5AQAAAA==.Falloutman:BAABNQAECn8yAAICAAoKpxzhCgB2AgACAAoKpxzhCgB2AgAAAA==.Farther:BAAANQADCgUICQABNQAFFAcIGQATAD0bAA==.Fayne:BAAANQAECgUICQAAAA==.',
Fe='Felfart:BAAANQADCgUIBQAAAA==.',
Fi='Firefox:BAACNQAFFH8FAAIaAAIKXhEnIwByAAAaAAIKXhEnIwByAAA1AAQKfyIAAxoACgofGHs3ACsCABoACgofGHs3ACsCAAsAAgoFB7VuAFgAAAE1AAUUBwgMABsAThkA.',
Fl='Flechillas:BAAANQADCgcIDQAAAA==.Flán:BAABNQAECn8fAAIcAAkKJBHJKgDGAQAcAAkKJBHJKgDGAQAAAA==.',
Fr='Fraternite:BAAANQAECgYIBwAAAA==.',
Fu='Furrymoon:BAAANQADCgcIBwAAAA==.',
Ga='Gabriellad:BAABNQAECn8aAAIBAAcKNwVGCwHDAAABAAcKNwVGCwHDAAAAAA==.',
Ge='Gerrakha:BAAANQADCgYIBgABNQAECgoKGwAFAFQcAA==.',
Gi='Giterdonee:BAACNQAFFH8SAAMGAAcKfhKVDABeAQAGAAUKfhKVDABeAQAJAAIKAADcAgCpAAA1AAQKfyoAAwkACgoiH5oFAMYCAAkACgp8HZoFAMYCAAYABwr1FYGxAKEBAAAA.',
Go='Goldielocks:BAAANQAECgUIBwAAAA==.Goodintent:BAAANQADCgEIAQAAAA==.Gorr:BAAANQADCgMIBgABNQAECgIIAgAIAAAAAA==.Gotchoo:BAABNQAECn8hAAIKAAgKuxFxTQCBAQAKAAgKuxFxTQCBAQABNQAECgIIAgAIAAAAAA==.Gothmommy:BAABNQAECn84AAMZAAoKCBvPQgBhAgAZAAoKCBvPQgBhAgAYAAYKPAdwMQDqAAAAAA==.',
Gr='Grilledchis:BAAANQADCgIIAgAAAA==.Griphöök:BAAANQAECgIIAgAAAA==.Groldin:BAAANQAECggICQAAAA==.Grumble:BAAANQAECgQIBAAAAA==.',
['Gõ']='Gõtchoo:BAAANQAECgIIAgAAAA==.',
Ha='Hairball:BAABNQAECn8VAAIdAAgKyhHRBwDqAQAdAAgKyhHRBwDqAQAAAA==.Hammerthumb:BAAANQAECgUIBwABNQAECgoKKgAEAG0LAA==.Hardawn:BAAANQABCgEIAQABNQAFFAcIGQATAD0bAA==.',
Ho='Hornswoggle:BAAANQADCgQIBAAAAA==.Hotsoup:BAAANQADCgQJBAAAAA==.Hozzluzzak:BAAANQADCggICAAAAA==.',
Hy='Hyara:BAABNQAECn9YAAIFAAoKrCWeBQBcAwAFAAoKrCWeBQBcAwAAAA==.',
['Hù']='Hùñtarð:BAAANQAECgEIAgAAAA==.',
Im='Imnaked:BAAANQADCgYIBgABNQAECggIGwAIAAAAAA==.',
In='Invisimitch:BAAANQADCgEIAQAAAA==.',
Ip='Ips:BAAANQADCgIIAgABNQADCgUIBQAIAAAAAA==.',
Iv='Iv:BAAANQADCgYIBgAAAA==.',
Ja='Jabzulsor:BAAANQAECggICAAAAA==.',
Je='Jeffster:BAAANQAECgMIAwAAAA==.',
Ji='Jifman:BAAANQADCgYIBgAAAA==.',
Jo='Joffrey:BAAANQADCgcIEQAAAA==.Jordi:BAABNQAECn87AAIFAAkKRR+8KQCLAgAFAAkKRR+8KQCLAgAAAA==.Jotarcyon:BAAANQABCgIJAgAAAA==.',
Ju='Jukkes:BAAANQADCggIEwAAAA==.Justinfox:BAAANQADCgEIAQAAAA==.Juukess:BAAANQAECgIIAgAAAA==.',
Ka='Kannarri:BAAANQAECgMIDAAAAA==.Kanree:BAACNQAFFH8XAAIUAAcKkQQgBQAzAQAUAAcKkQQgBQAzAQA1AAQKf0wAAhQACgpxFLQXAAICABQACgpxFLQXAAICAAAA.Kapriestsun:BAAANQAECgEIAQABNQAECgEIAQAIAAAAAA==.Kastre:BAAANQAECgIIAgAAAA==.Katherine:BAAANQADCgIIAgAAAA==.Kayaa:BAAANQADCggICAAAAA==.',
Ke='Kea:BAACNQAFFH8SAAMeAAUKnx6SAABhAQAZAAUKQB2CDQCwAQAeAAQKkR6SAABhAQA1AAQKf2UABB4ACgpqJlQAAMEDABkACgpbJpABACoEAB4ACQoKJVQAAMEDABgABAonGSc+ADsBAAAA.Kek:BAABNQAECn8lAAIKAAkKtQuQPwCHAQAKAAkKtQuQPwCHAQAAAA==.Kenny:BAAANQAECggICAABNQAFFAUIDAAFACsgAA==.',
Kh='Khaalid:BAAANQAECgEIAQABNQAECgoKNQADAM0hAA==.Kharok:BAABNQAECn8yAAQJAAoKKx11BgBHAgAHAAgK9iDNCADDAgAJAAoKqBp1BgBHAgAGAAYKVRjxpgC8AQABNQAECgoKNQADAM0hAA==.',
Ki='Killhordex:BAAANQAECgEIAQAAAA==.Kincane:BAAANQADCgcICQAAAA==.Kittygirl:BAAANQABCgQIBAAAAA==.',
Ko='Korxin:BAACNQAFFH8PAAMVAAcKMRSkDgDZAAAFAAQKDBT+GgDiAAAVAAUKvQykDgDZAAA1AAQKf00AAwUACgqNIgYzANMCAAUACgqNIgYzANMCABUABwrgF7cZAKQBAAAA.Kota:BAAANQADCgEIAQAAAA==.',
Ku='Kurnhaspios:BAAANQADCgQIBAAAAA==.Kurquaan:BAAANQAECgMIBAAAAA==.',
Ky='Kydraeth:BAAANQAECgIIAQAAAA==.',
La='Lanstyn:BAABNQAECn8vAAIeAAgK6RnTBAByAgAeAAgK6RnTBAByAgABNQAECgoKNQADAM0hAA==.Laufey:BAABNQAECn8xAAITAAgK/ReYtgAWAgATAAgK/ReYtgAWAgAAAA==.',
Le='Lemone:BAAANQADCgUIBQAAAA==.Lemonsk:BAAANQADCgUICAAAAA==.Lennox:BAAANQADCgQIBAAAAA==.Lenton:BAAANQAECgEIAQAAAA==.',
Li='Lightfury:BAAANQADCgYIDAAAAA==.Limone:BAAANQAECgEIAQAAAA==.Listradra:BAAANQADCgQIBAAAAA==.',
Lo='Loganwater:BAAANQADCgQIBAAAAA==.Lokano:BAAANQADCgIIAgAAAA==.',
Lu='Ludmylha:BAAANQAECgcIEQAAAA==.Luisda:BAAANQADCggIFwAAAA==.Lull:BAAANQAECggICgAAAA==.Lushil:BAAANQAFFAEIAQAAAA==.',
Ly='Lyrea:BAAANQAECggICAAAAA==.',
Ma='Magidragon:BAAANQAECgEIAQAAAA==.Man:BAAANQADCgUIBQAAAA==.Marsangel:BAAANQADCgEIAQAAAA==.Marydavis:BAAANQABCgIIAgAAAA==.Maxerella:BAAANQADCgUIBQAAAA==.Maybell:BAABNQAECn8cAAIRAAgK5wORIgDtAAARAAgK5wORIgDtAAAAAA==.',
Md='Mdavis:BAAANQADCgMIAwAAAA==.',
Me='Meepmeepmomp:BAAANQADCgUIBQAAAA==.Megumín:BAAANQAECgEIAQAAAA==.Melt:BAACNQAFFH8bAAQNAAcKfxhxCACvAAAMAAQKORi+EwDzAAANAAIK5xhxCACvAAAXAAEKAAA6CQBcAAA1AAQKf1QAAwwACgpAJN0JABMDAAwACgrGI90JABMDAA0ABAoAIlAgAG4BAAAA.Mepha:BAACNQAFFH8PAAILAAYKxQ5iBAAjAQALAAYKxQ5iBAAjAQA1AAQKfzEAAwsACgr3HvsOAIECAAsACgr3HvsOAIECAAoACArhDJ9LAIsBAAAA.Meridia:BAAANQADCgMIAwAAAA==.Metons:BAAANQAECgEIAQABNQAECgkJHwAcACQRAA==.',
Mi='Miike:BAAANQADCgEIAQABNQAFFAcIGQATAD0bAA==.Mike:BAACNQAFFH8ZAAMTAAcKPRudEwA9AQATAAYK1BudEwA9AQASAAEK4Bi0DQBUAAA1AAQKf3MAAxMACgp8JAITAIcDABMACgp8JAITAIcDABIABQqUD0cfAPAAAAAA.Mikevoker:BAAANQADCgEIAQABNQAFFAcIGQATAD0bAA==.Mipz:BAAANQADCgUIBQAAAA==.Misfitdh:BAAANQAECgQIAwAAAA==.Misfitdk:BAAANQAECggIBAAAAA==.Misfitmagi:BAAANQAECgIIAgAAAA==.Misfittotem:BAAANQAECgMIAgAAAA==.Mistfox:BAAANQADCgYIDAAAAA==.Mistmommy:BAABNQAECn8zAAIUAAoKoBJhEADyAQAUAAoKoBJhEADyAQAAAA==.',
Mo='Mollieann:BAAANQAECgIIAgAAAA==.Mommon:BAAANQADCgEIAQAAAA==.Monreu:BAAANQAECgIIAgAAAA==.Morrighan:BAAANQADCgMIAwAAAA==.',
['Mâ']='Mâlus:BAAANQAECgUICAAAAA==.',
['Mä']='Märs:BAAANQADCgYICgAAAA==.',
Na='Naminé:BAAANQADCgQIBAABNQAECggIMQATAP0XAA==.Naroka:BAABNQAECn8bAAIFAAoKVBxhIQCsAgAFAAoKVBxhIQCsAgAAAA==.Nattyrav:BAACNQAFFH8IAAIQAAQKGRUpEwA/AQAQAAQKGRUpEwA/AQA1AAQKfyUAAxAACQp/Ghg9AIECABAACQp/Ghg9AIECAA8AAQpQHW0LAVEAAAAA.',
Ne='Neemesis:BAAANQAECgQIBAAAAA==.Nemonk:BAAANQAECggIDAABNQAECgkJGwATAMsKAA==.Nemoz:BAABNQAECn8bAAITAAkKywpddgCuAQATAAkKywpddgCuAQAAAA==.Nerfling:BAAANQADCgYICAAAAA==.',
No='Nocter:BAAANQAECgUIBQAAAA==.Noktor:BAAANQADCgYIBgAAAA==.Noktra:BAAANQAECgUIDwAAAA==.Nosey:BAAANQADCgUIBQAAAA==.',
Ny='Nylah:BAAANQAECgYIBgABNQAFFAUIEAANAIUSAA==.Nymura:BAABNQAECn8kAAIBAAcKVg6i5gBOAQABAAcKVg6i5gBOAQAAAA==.',
Oa='Oakhugger:BAABNQAECn8qAAUEAAoKbQu6TADZAAAEAAYK7gm6TADZAAAfAAYKvgZ6SwB9AAAgAAUK+gt2MAB5AAAhAAEKygGigQAUAAAAAA==.',
Ol='Olyvivia:BAAANQAECgcIBwAAAA==.',
Om='Omgega:BAABNQAECn9AAAIBAAoKtxNfawDnAQABAAoKtxNfawDnAQAAAA==.',
On='Onichan:BAAANQAECgEIAQABNQAFFAgIFwAQAG0YAA==.Onimeek:BAABNQAECn9IAAIWAAoKDRl+IADyAQAWAAoKDRl+IADyAQAAAA==.Onionknightt:BAAANQAECgIIAQAAAA==.',
Or='Oryn:BAABNQAECn8XAAMSAAoKtRxsIwDRAAATAAcKmh6N0ADlAQASAAMKjBlsIwDRAAABNQAECggIFAATAA4cAA==.Oryx:BAAANQADCgEIAQAAAA==.',
Os='Osoloco:BAAANQADCgUIAwAAAA==.',
Pa='Palmpower:BAAANQADCgYICQAAAA==.Palpitations:BAAANQAECgEIAQAAAA==.Paper:BAAANQAFFAYIEgAAAQ==.',
Pe='Peacefullev:BAACNQAFFH8FAAIUAAMKcgt7BwC2AAAUAAMKcgt7BwC2AAA1AAQKf0IAAxQACgr5HooJAPICABQACgr5HooJAPICABwAAgo7EK1UAEAAAAAA.Pepegá:BAAANQAECgEIAQAAAA==.Pewpewpew:BAAANQAECgUICQAAAA==.',
Ph='Phantomthief:BAAANQAECggICwAAAA==.',
Pi='Pipeleto:BAABNQAECn9DAAIGAAoK9h7gJQAhAwAGAAoK9h7gJQAhAwAAAA==.Pizzaroll:BAABNQAECn9AAAIiAAoKJRUIBQCiAgAiAAoKJRUIBQCiAgAAAA==.',
Po='Podvoddonut:BAAANQADCgYIBgAAAA==.',
Pr='Previdius:BAAANQADCgUIBQAAAA==.Priesstess:BAAANQADCgYICQAAAA==.',
Pu='Puppyheals:BAAANQABCgQIBAAAAA==.',
['Pé']='Pépega:BAAANQADCgQIBwAAAA==.',
Re='Rei:BAAANQAECgYICAAAAA==.',
Ri='Riellus:BAAANQAECgIIBAAAAA==.Riiu:BAAANQAECgYICAABNQAECgkJRQABAC8lAA==.Riven:BAAANQADCgYIBgAAAA==.Rixin:BAECNQAFFH8OAAMLAAUKFB4sCgCmAAALAAQKFB4sCgCmAAAaAAEKAACbOwAcAAA1AAQKfz8AAgsACgq+JMECAFIDAAsACgq+JMECAFIDAAAA.',
Ro='Rokom:BAACNQAFFH8LAAMJAAUKPRWyAgCyAAAJAAMK5xqyAgCyAAAGAAIKlA88LwBUAAA1AAQKfzAAAwkACgo2HuMNANUBAAkABwpAIuMNANUBAAYABAptGDHqABABAAAA.Roonrano:BAAANQADCggICAAAAA==.',
Ru='Rumpus:BAAANQADCgcIBwAAAA==.Runed:BAAANQAECgEIAQAAAA==.',
Ry='Ryuk:BAAANQAECgQIBAAAAA==.',
Sa='Salla:BAAANQADCgYICQAAAA==.Saphh:BAAANQAECgEIAQABNQAFFAQIDwAKAHIYAA==.Saudencheek:BAAANQAECgQIBAAAAA==.',
Se='Seanster:BAABNQAECn8eAAMjAAkK+xKkIgBxAgAjAAkK+xKkIgBxAgAkAAMKQQJhGABeAAABNQAFFAUIEAANAIUSAA==.Senecca:BAABNQAECn86AAIEAAoKsxw0FQBeAgAEAAoKsxw0FQBeAgAAAA==.',
Sh='Shadowlily:BAAANQADCgMIAwABNQAECgkJQQAPAPsPAA==.Shadowms:BAABNQAECn9BAAMlAAoKZR/1AwBOAwAlAAoKZR/1AwBOAwAmAAEKAABDKgAAAAAAAA==.Shadowxd:BAABNQAECn9CAAQhAAoKbiEcBACpAwAhAAoKbiEcBACpAwAEAAIKHQ54bABsAAAfAAEKAACJYAAzAAAAAA==.Shamanpwnz:BAAANQAECgQIBgAAAA==.Shambassador:BAAANQAECggIEQAAAA==.Shamwowha:BAAANQADCgQIBAAAAA==.Sharkdancer:BAABNQAECn8UAAIbAAkKaB6OFQC4AgAbAAkKaB6OFQC4AgABNQAFFAcIDwAUAFQeAA==.Shaulana:BAAANQAECgUIBQABNQAECgkJQQAPAPsPAA==.Shenwu:BAABNQAECn8iAAIDAAoKxxjRDQAcAgADAAoKxxjRDQAcAgAAAA==.Shirokuma:BAACNQAFFH8TAAMEAAcKCxN2CAB5AQAEAAYKCxN2CAB5AQAfAAEKAADwCABfAAA1AAQKfycAAwQACgo3HbsaAPMCAAQACgo3HbsaAPMCAB8AAQrxFz5VAFAAAAAA.Shocktopuus:BAAANQADCgQIBAAAAA==.Shwizzle:BAAANQADCggIDgAAAA==.',
Si='Sidvicious:BAAANQADCgUIBAAAAA==.',
Sk='Sköllati:BAAANQAECgUIBAAAAA==.',
Sl='Slingshotz:BAAANQAECgcIEQAAAA==.Sloppypoppy:BAAANQABCgUIBwAAAA==.',
Sm='Smarty:BAAANQAECgUIBAAAAA==.',
Sn='Sneakylev:BAABNQAECn9BAAMnAAkK+xZZHgDfAQAnAAgKmhBZHgDfAQAjAAQKPxbDLADVAAABNQAFFAMIBQAUAHILAA==.',
So='Solari:BAABNQAECn9BAAMbAAoK1iT0AgCrAwAbAAoK1iT0AgCrAwAoAAUKIBhkFwA4AQAAAA==.Soleon:BAAANQAECgcIDgAAAA==.Solune:BAAANQAECgYIDAAAAA==.Souprage:BAAANQAECgMIBgAAAA==.',
Sp='Spypal:BAAANQADCgYIDAAAAA==.',
St='Stabwei:BAAANQADCggICAAAAA==.',
Su='Sugirokimami:BAAANQAECgYICwAAAA==.Sureshotz:BAAANQAECggICAAAAA==.',
Sw='Swagmastrflx:BAAANQADCgQIBAAAAA==.Swëëtdee:BAAANQADCgMICAAAAA==.',
Ta='Taehausx:BAAANQAFFAEIAQABNQAFFAcIGAAaAE4bAA==.Taraka:BAAANQAECgQIBAAAAA==.',
Td='Tdolokk:BAAANQADCggIFwAAAA==.',
Te='Teeward:BAAANQADCgYIBgAAAA==.Tenath:BAAANQAECgUICQAAAA==.Terribleturd:BAAANQAECgEIAQAAAA==.',
Th='Thaleon:BAAANQADCggICAAAAA==.Thauriel:BAAANQAECgEIAQAAAA==.Theexecution:BAAANQAECgQIAwAAAA==.Therella:BAAANQADCgUIBQAAAA==.',
Ti='Timert:BAAANQAECggIBgAAAA==.Tinkerspell:BAAANQAECggIAgAAAA==.',
To='Totemtotebag:BAABNQAECn8XAAIPAAQK7BdpsAAOAQAPAAQK7BdpsAAOAQABNQAECgoKOQAfAMolAA==.',
Tr='Treponeme:BAAANQAECgUIBQABNQAECgoKKgAEAG0LAA==.Treshaleth:BAAANQADCgQIBAAAAA==.Tripodg:BAABNQAECn8mAAISAAkK8gYGFwAUAQASAAkK8gYGFwAUAQAAAA==.Trollztoll:BAAANQADCgIIAgAAAA==.',
Tw='Twiddletime:BAAANQAECgQIBgAAAA==.',
['Tï']='Tïggy:BAAANQAECgcIBwAAAA==.',
Un='Una:BAABNQAECn8eAAIbAAoKAAxqHgCcAQAbAAoKAAxqHgCcAQAAAA==.Unholymisfit:BAAANQAECgIIBQAAAA==.Unholytato:BAAANQADCgQIBAAAAA==.',
Ur='Ursok:BAAANQAECgEIAQABNQAECgoKNQADAM0hAA==.',
Ut='Uthok:BAAANQADCgUIBgAAAA==.',
Uz='Uzol:BAAANQADCgcICAAAAA==.',
Va='Vacalocà:BAAANQAECggICgAAAA==.Valerian:BAABNQAECn8eAAIEAAkK2QtKMgBgAQAEAAkK2QtKMgBgAQAAAA==.Van:BAAANQADCgQIBAAAAA==.',
Ve='Veinke:BAABNQAECn8YAAIoAAgKJRk0CwAfAgAoAAgKJRk0CwAfAgAAAA==.Velanthir:BAAANQADCggIFAAAAA==.Verd:BAEANQAFFAEIAQAAAA==.Verevulf:BAAANQABCgIIAgAAAA==.Veronica:BAAANQABCgYIBgAAAA==.Versaacee:BAAANQADCgYIBgAAAA==.Vessarind:BAAANQADCgUIBQAAAA==.',
Vi='Vivrian:BAAANQADCgUIBQAAAA==.',
['Vä']='Vänillaicë:BAAANQADCgcIBwABNQAECgkJQQAPAPsPAA==.',
Wa='Waally:BAAANQAECgQIBQAAAA==.Wahwoo:BAAANQADCggIDgABNQAECgkJQQAPAPsPAA==.Walterlight:BAAANQAECgYIBgABNQAECgoKPwAFAL4iAA==.',
We='Weebsora:BAAANQAECgQIBQAAAA==.',
Wo='Worldtree:BAAANQADCgEIAQAAAA==.',
Xa='Xaelthira:BAAANQADCgcIBwAAAA==.',
Ya='Yadhi:BAABNQAECn81AAIDAAoKzSH/AgBrAwADAAoKzSH/AgBrAwAAAA==.',
Yi='Yimomo:BAABNQAECn81AAMZAAkKnx6iNACVAgAZAAkKnx6iNACVAgAYAAUKrApyNADYAAAAAA==.',
Za='Zalconn:BAABNQAECn8sAAMnAAoKSiOvDgD5AgAnAAoKGiOvDgD5AgAjAAQKVyHeUgBxAQAAAA==.Zarrona:BAAANQAECgIIAwABNQAECggIMQATAP0XAA==.Zayah:BAAANQAFFAIIAwAAAA==.',
Zi='Zikony:BAAANQAECgYICAAAAA==.',
Zu='Zuber:BAABNQAECn8/AAIjAAoKNCELCABVAwAjAAoKNCELCABVAwAAAA==.',
['År']='Årtimus:BAAANQADCgcIEQAAAA==.',
['Öw']='Öwö:BAAANQAECgQIBAAAAA==.',
['Üw']='Üwü:BAABNQAECn8fAAMOAAgKphg7VgCqAQAOAAgKphg7VgCqAQABAAQKmRBrHAHvAAAAAA==.',
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
