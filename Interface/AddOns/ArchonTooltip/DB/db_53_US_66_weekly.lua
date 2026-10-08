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

local lookup = {'Paladin-Holy','Paladin-Protection','Paladin-Retribution','Warrior-Protection','DeathKnight-Blood','Hunter-BeastMastery','Shaman-Elemental','Rogue-Assassination','Warrior-Arms','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DemonHunter-Devourer','Monk-Mistweaver','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Mage-Frost','DemonHunter-Vengeance','Monk-Windwalker','Druid-Restoration','Hunter-Marksmanship','Hunter-Survival','Rogue-Subtlety','DemonHunter-Havoc','Shaman-Restoration','Unknown-Unknown','Druid-Guardian','Evoker-Augmentation','DeathKnight-Frost','Warrior-Fury',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abaddôn:BAAANQADCgYIBgAAAA==.',
Ad='Adirolf:BAAANQAECgQIBgAAAA==.',
Ae='Aenlori:BAAANQADCgYIBgABNQAFFAYIDAABAFYSAA==.Aenlorie:BAACNQAFFIEMAAMBAAYKVhJgCwCDAQABAAUKkQ5gCwCDAQACAAEKfAMqDgBAAAA1AAQKgS8ABAEACQrbC2NWAPUBAAEACQrbC2NWAPUBAAMABQozFvHJAE4BAAIABAqUE0dAAM0AAAAA.',
Ag='Ag:BAAANQADCgMIAgAAAA==.Agesilaus:BAAANQADCgEIAQAAAA==.Aggathon:BAEBNQAECoEWAAIEAAcK9Q5gGgBjAQAEAAcK9Q5gGgBjAQAAAA==.',
Ak='Akebono:BAAANQADCgUJBQAAAA==.',
Al='Aldebaran:BAAANQAECgQICAAAAA==.Alphatanker:BAACNQAFFIEJAAIFAAMK5iVTDQBOAQAFAAMK5iVTDQBOAQA1AAQKgS4AAgUACQp0JrsAAPADAAUACQp0JrsAAPADAAAA.',
Ar='Argentino:BAAANQAECgEJAQAAAA==.',
As='Ashke:BAABNQAECoEcAAIGAAgKvBVsWgA7AgAGAAgKvBVsWgA7AgAAAA==.',
Au='Aurica:BAAANQAECgEIAgAAAA==.',
Ax='Axes:BAAANQAECgMIBgAAAA==.',
Ba='Badlucklouie:BAABNQAECoEaAAIHAAcK3xgiUgADAgAHAAcK3xgiUgADAgAAAA==.Badpenny:BAAANQADCgYIFwAAAA==.Bajenkas:BAAANQADCgYIBgAAAA==.Balfas:BAAANQAECgUIDAAAAA==.',
Be='Beaupeep:BAAANQADCgYIMwAAAA==.',
Bi='Bighorner:BAAANQADCgQIBAAAAA==.Bindicrippa:BAAANQADCgcIFAAAAA==.',
Bl='Blackwater:BAABNQAECoEdAAIIAAcKjxnmKgALAgAIAAcKjxnmKgALAgAAAA==.Bloodstyx:BAAANQADCggIFgABNQAECgcIFwAFAEofAA==.',
Bo='Bobi:BAAANQAECgEIAgAAAA==.Boyacky:BAAANQADCgEIAQAAAA==.',
Br='Braiglock:BAAANQAECgQIBgAAAA==.Bratty:BAAANQADCgMIBgAAAA==.',
Bu='Bucko:BAABNQAECoEVAAIGAAcKexcObgAJAgAGAAcKexcObgAJAgAAAA==.',
By='Bygz:BAAANQAECgUIDAABNQAFFAYIFAAJAG4kAA==.',
Ca='Caarjack:BAABNQAECoEkAAMKAAkKOxgEDwCmAgAKAAkKOxgEDwCmAgALAAQKFBg3IwAMAQAAAA==.Callmefury:BAAANQAECgQIBgAAAA==.Callmeheal:BAAANQAECgMIBQAAAA==.Callmemommy:BAAANQADCgUIBQAAAA==.Casserole:BAABNQAECoEbAAIMAAcK3RMlvADoAQAMAAcK3RMlvADoAQAAAA==.Catadelic:BAABNQAECoEcAAIGAAcKdAe0oACTAQAGAAcKdAe0oACTAQAAAA==.',
Ce='Celestial:BAABNQAECoEZAAMNAAcKRhIaFADGAQANAAcKRhIaFADGAQAOAAIKuwiFHwBjAAAAAA==.',
Ch='Chewwbacca:BAABNQAECoEVAAQNAAgKDx+PBADRAgANAAgKDx+PBADRAgAOAAEKXhTOJABHAAAPAAEKNAl9JQEzAAAAAA==.Chewwy:BAAANQADCgUIBQABNQAECggIFQANAA8fAA==.Chewwyy:BAAANQADCgIIAgABNQAECggIFQANAA8fAA==.Chud:BAAANQAECgEIAgAAAA==.Chuwy:BAAANQADCgMIAwABNQAECggIFQANAA8fAA==.',
Cl='Clap:BAAANQADCgYIBgAAAA==.',
Cu='Cudi:BAAANQAECgIICAAAAA==.Cuzigothigh:BAAANQABCgEIAQAAAA==.',
Da='Darkdemon:BAABNQAECoE3AAIQAAkKBSQBAgDAAwAQAAkKBSQBAgDAAwAAAA==.Darkladyann:BAAANQAFFAEIAQAAAA==.',
De='Deadlee:BAABNQAECoEWAAIRAAcK/hmLEwAXAgARAAcK/hmLEwAXAgAAAA==.Deathphish:BAABNQAECoEVAAMSAAcK+A9tXAB3AQASAAcKKw9tXAB3AQAFAAQKdQ9uhgC/AAAAAA==.Dentfry:BAAANQAECggIEAAAAA==.Derfla:BAAANQAECgUIBwAAAA==.Deshler:BAAANQAECggIBwAAAA==.Dezign:BAABNQAECoEUAAMTAAkKqSDtDABJAwATAAkKqSDtDABJAwAUAAEK+gX4cQArAAABNQAFFAYIEwAVADwhAA==.',
Di='Dildro:BAAANQAECgMIBwAAAA==.Dimhammer:BAAANQAECgEIAQAAAA==.Ditlutz:BAAANQAECgcIEwAAAA==.',
Do='Dom:BAACNQAFFIEIAAIJAAUKkA9tEACCAQAJAAUKkA9tEACCAQA1AAQKgR8AAgkACQoWHfBNAIUCAAkACQoWHfBNAIUCAAAA.Doronjo:BAAANQADCgYICQAAAA==.Dorz:BAAANQADCgYICwAAAA==.Dotrammy:BAAANQADCgcICQAAAA==.',
Du='Dupeslicate:BAAANQAECgUIDgAAAA==.',
Dw='Dwanco:BAAANQADCgEIAQAAAA==.Dwarfussy:BAAANQADCgMIAwAAAA==.',
Dy='Dybby:BAAANQAECgUIDAAAAA==.Dylexek:BAAANQADCgEIAQAAAA==.Dynamite:BAAANQADCgQIBAAAAA==.',
['Dé']='Détth:BAAANQAECgMIAwAAAA==.',
El='Elderoth:BAABNQAECoEVAAIMAAgKvRkaZQCgAgAMAAgKvRkaZQCgAgAAAA==.Elfsky:BAAANQADCgUJBQAAAA==.',
En='Endlessnight:BAABNQAECoEXAAIFAAcKSh+9KQBaAgAFAAcKSh+9KQBaAgAAAA==.',
Er='Erica:BAAANQAECgQIBAAAAA==.',
['Eä']='Eärendil:BAAANQAECgMIAwAAAA==.',
Fa='Faebryn:BAAANQADCggIFAAAAA==.Faevor:BAAANQAECgUIEgAAAA==.',
Fe='Fenirean:BAAANQAECgQIBgAAAA==.',
Fl='Flirts:BAAANQADCgYICgAAAA==.',
Fo='Forcas:BAABNQAECoEVAAIWAAcKtyHpBQCcAgAWAAcKtyHpBQCcAgAAAA==.',
Ga='Gamarrick:BAAANQAECgcIEQAAAA==.',
Ge='Germain:BAAANQADCgIIAgAAAA==.',
Gn='Gnometzu:BAAANQADCggIDgAAAA==.',
Go='Golddicmove:BAAANQADCgQIBAAAAA==.',
Gr='Gremmel:BAAANQADCgcICQAAAA==.Griever:BAABNQAECoE2AAQNAAkKpxpuLAARAQAPAAYKDRghgwCxAQANAAMKpR9uLAARAQAOAAEKGBZ1JABIAAAAAA==.',
Gu='Guillak:BAAANQAECgYIEgAAAA==.',
Ha='Hadroldel:BAAANQAECgcICgAAAA==.Hammond:BAAANQADCgMICAAAAA==.Hanraktah:BAAANQADCgUIBQAAAA==.Harlem:BAAANQABCgQIBAAAAA==.Harxx:BAAANQADCgUICgAAAA==.Hatka:BAAANQAECgQIBQAAAA==.Hattori:BAAANQAECgEIAQAAAA==.',
Hi='Higurashi:BAAANQABCgQIBwAAAA==.',
Ho='Holymanson:BAAANQAECgMJBQAAAA==.Hoofington:BAAANQAECgYIDQAAAA==.Howlingdoom:BAAANQADCgYIBgAAAA==.',
Hy='Hylexerr:BAAANQAECgEIAgAAAA==.',
Ib='Ibull:BAAANQADCggICQAAAA==.',
If='Iffy:BAABNQAECoEeAAIGAAgK8BpdOQCbAgAGAAgK8BpdOQCbAgAAAA==.',
Il='Ilian:BAABNQAECoEbAAIXAAkKbxj/FgBrAgAXAAkKbxj/FgBrAgAAAA==.',
In='Iniquity:BAAANQADCggJFAAAAA==.',
Ja='Jabiso:BAABNQAECoEWAAIHAAcKWxbDUwD9AQAHAAcKWxbDUwD9AQAAAA==.Jackthebeast:BAAANQAECgEIAQABNQAECgkJGgAHAOQfAA==.Jackthefel:BAAANQAECgQJBwABNQAECgkJGgAHAOQfAA==.Jackthetotem:BAABNQAECoEaAAIHAAkK5B/OFwAkAwAHAAkK5B/OFwAkAwAAAA==.Jain:BAAANQAECgEIAgAAAA==.',
Jd='Jdmagisdruid:BAAANQAECgcIEwAAAA==.',
Je='Jeanne:BAAANQAECgcIEQAAAA==.Jezabel:BAAANQADCgIIAgAAAA==.',
Jo='Jorcingmyshi:BAAANQAECgcIEgAAAA==.Jorhmont:BAAANQADCgUIBQAAAA==.',
Ju='Juan:BAABNQAECoEVAAIYAAYK3RhJJwC1AQAYAAYK3RhJJwC1AQAAAA==.Jumpeor:BAACNQAFFIEPAAIDAAYK3xz4AgAtAgADAAYK3xz4AgAtAgA1AAQKgTAAAgMACQqxJpcCAOUDAAMACQqxJpcCAOUDAAAA.',
Ka='Kanig:BAAANQADCggJEgAAAA==.Kassey:BAAANQADCgYIGAAAAA==.Katacola:BAACNQAFFIEXAAIYAAYK4xv3AQAtAgAYAAYK4xv3AQAtAgA1AAQKgScAAhgACQolJJkFAFcDABgACQolJJkFAFcDAAAA.',
Ke='Kenaf:BAAANQADCgQIBAAAAA==.Kendrys:BAAANQAECgcIEwAAAA==.Kevenal:BAABNQAECoEVAAIZAAkKpxqDEQDGAgAZAAkKpxqDEQDGAgAAAA==.',
Ki='Kikiliki:BAAANQAECgQIDgAAAA==.Killmartin:BAAANQAECggICAAAAA==.Kinneas:BAABNQAECoEVAAIDAAgKJBhzWQBhAgADAAgKJBhzWQBhAgAAAA==.Kizmit:BAAANQAECgEIAQAAAA==.',
Kl='Klënz:BAAANQAECgEIAQAAAA==.',
Ko='Koa:BAAANQAECgQICgAAAA==.',
Ku='Kurau:BAABNQAECoEUAAIaAAcKqARYCgA2AQAaAAcKqARYCgA2AQAAAA==.Kurzal:BAAANQAECgQICQAAAA==.',
Ky='Kyraz:BAABNQAFFIEPAAMIAAYK/BnpAQA+AgAIAAYK/BnpAQA+AgAbAAMKIAUbCwDhAAABNQAFFAYIFAAJAG4kAA==.',
La='Lacie:BAAANQAECgUIDwAAAA==.Lavos:BAAANQAECgEIAQABNQAECggIHwADAJgeAA==.',
Le='Lexy:BAAANQAECgEIAQABNQAECgcIGwAQAA4iAA==.',
Lo='Lokiel:BAAANQAECgQICgAAAA==.Lokifurion:BAAANQAECgYIEgAAAA==.Lokisson:BAAANQAECgEIAQAAAA==.',
Lu='Lunitari:BAAANQAECgIIAgAAAA==.',
Ly='Lyaenna:BAAANQAECgYIDgAAAA==.',
Ma='Mageshir:BAAANQAECgEIAQAAAA==.Magrat:BAAANQADCgIIAgAAAA==.Mahu:BAAANQAECgQIBAAAAA==.Maletherion:BAAANQAECgcIEwAAAA==.Maltherion:BAABNQAECoEVAAMcAAgK/RtsIABxAgAcAAgK/RtsIABxAgAQAAEKZwMGZgAnAAAAAA==.Margareetah:BAAANQAECgEIAQAAAA==.',
Me='Meglamonk:BAAANQAECgUIBgAAAA==.',
Mi='Milarca:BAAANQABCgYJCwAAAA==.Minireaper:BAAANQADCgMIAwAAAA==.Misbehavin:BAAANQADCgQIBAAAAA==.',
Mj='Mjolnir:BAAANQAECgcIEwAAAA==.',
Mo='Mochizuko:BAAANQABCgIIAgAAAA==.Mongke:BAAANQABCggICAAAAA==.Moonre:BAAANQADCgYIEgAAAA==.',
Mu='Mubvan:BAAANQAECgEIAQAAAA==.Mushroommans:BAAANQAECgQICgABNQAECggIKwAQALgkAA==.',
My='Mystaris:BAAANQADCgYICgAAAA==.',
Na='Namôr:BAAANQADCgYIEgAAAA==.Narzel:BAAANQAECgIIBQAAAA==.Nashîr:BAAANQAECgYIEgAAAA==.Navybum:BAAANQAECgUICAAAAA==.',
Ne='Nehemiah:BAABNQAECoEZAAMEAAcKBh8ZCwBhAgAEAAcKBh8ZCwBhAgAJAAEKPxpqJgFLAAAAAA==.Nequin:BAABNQAECoEaAAIBAAgKFhjiOwBXAgABAAgKFhjiOwBXAgABNQAECgcIGAAdAHwhAA==.Nequins:BAAANQAECgMIBAABNQAECgcIGAAdAHwhAA==.Nequinss:BAABNQAECoEYAAIdAAcKfCGOLACMAgAdAAcKfCGOLACMAgAAAA==.Nevermore:BAAANQAECgEIAQAAAA==.',
Ni='Nicabar:BAABNQAECoEbAAIPAAgKFgZ4ngBqAQAPAAgKFgZ4ngBqAQAAAA==.Nilfheim:BAAANQAECgUICQAAAA==.Nivla:BAAANQAECgEIAQAAAA==.',
No='Noehtyar:BAAANQAECgQIBgAAAA==.Noie:BAAANQAECgUIDwAAAA==.Novadd:BAAANQADCgUIBQAAAA==.Novä:BAAANQAECgQIBAAAAA==.Noztalgia:BAAANQAECgQICAAAAA==.',
['Në']='Nëklaüs:BAAANQAECgQIEAAAAA==.',
Od='Odanarratite:BAAANQAECgEIAQAAAA==.Odanarrayne:BAAANQAECgEIAQAAAA==.Oditte:BAAANQADCggICAAAAA==.',
Oi='Oilliphéist:BAAANQAECgUIBwAAAA==.',
On='Onewithyou:BAAANQADCgEIAQAAAA==.',
Op='Opioid:BAAANQAECgEIAQABNQAECgIICAAeAAAAAA==.',
Or='Ornot:BAABNQAECoEnAAIdAAgKZRLTWwDNAQAdAAgKZRLTWwDNAQAAAA==.',
Os='Oshdruid:BAAANQADCgYICwAAAA==.',
Pa='Paislìe:BAAANQADCggIAgAAAA==.Palacola:BAAANQAECgEIAQAAAA==.Pandurbear:BAAANQADCgYIGAAAAA==.Paperplate:BAAANQAECgUIDAABNQAECgcIGAAMAJgNAA==.Paws:BAAANQADCgMJBgAAAA==.',
Pe='Peposhammy:BAAANQADCgUIBQAAAA==.',
Ph='Phuulith:BAAANQADCgYIEQAAAA==.',
Pi='Picantechode:BAAANQAECgEIAgAAAA==.',
Pr='Provost:BAABNQAECoEfAAIDAAgKmB5pOgDEAgADAAgKmB5pOgDEAgAAAA==.',
Ps='Psychonoia:BAAANQAECgUIEwAAAA==.',
Pu='Pumperdogx:BAAANQAECgEIAQABNQAFFAMICQAFAOYlAA==.Pumpkinpîe:BAAANQADCgYIBgAAAA==.',
Qu='Quadritrix:BAAANQADCgQIBAAAAA==.Quanx:BAAANQAECgcICQAAAA==.Quark:BAAANQAECgIIAgAAAA==.',
Ra='Ratacola:BAAANQAECgQICAAAAA==.',
Re='Remulüs:BAABNQAECoEbAAMQAAcKDiLTEwCzAgAQAAcKDiLTEwCzAgAcAAUK7hTNTgAlAQAAAA==.Reoãn:BAAANQABCgQIBgABNQADCgUIBQAeAAAAAA==.',
Ri='Riah:BAAANQAECgEIAgAAAA==.Riilyn:BAABNQAECoEaAAIIAAcKUBvmJgAmAgAIAAcKUBvmJgAmAgAAAA==.',
['Rø']='Røean:BAAANQADCgUIBQAAAA==.',
Sa='Sanktis:BAAANQADCggIFgAAAA==.',
Sb='Sbcarpenter:BAAANQAECgMIAgAAAA==.',
Sc='Scawmfhealz:BAAANQABCgMIAwAAAA==.Scecretzs:BAAANQADCgYIEQAAAA==.',
Se='Sebone:BAAANQADCggIDQAAAA==.Secretz:BAAANQAECgQICwAAAA==.Sedrelari:BAABNQAECoEjAAMGAAgK1CGqMQC1AgAGAAcKDSKqMQC1AgAaAAcKFR3zBQAhAgAAAA==.Sengseng:BAAANQADCgUIBgAAAA==.Sepsis:BAAANQAECgIICAAAAA==.Serjaime:BAAANQAECgEIAQAAAA==.Sesamo:BAABNQAECoEgAAIDAAkKHR5FNwDQAgADAAkKHR5FNwDQAgAAAA==.',
Sh='Shadedstørmz:BAAANQAECgIIAgAAAA==.Shocks:BAAANQAECgMIBgAAAA==.Shé:BAAANQAECgcIEwAAAA==.',
Si='Sixoneseven:BAAANQADCgYICgAAAA==.Sixseven:BAABNQAECoEWAAMQAAgKhhAmJQD+AQAQAAgKFhAmJQD+AQAWAAYKRQpRGAD6AAAAAA==.',
Sk='Skaarlett:BAAANQAECgEIAgAAAA==.Skone:BAABNQAECoEVAAMBAAcKdQfoigBSAQABAAcKdQfoigBSAQADAAEKEQMYlwEiAAAAAA==.',
Sm='Smarthen:BAAANQAECgEIAwABNQAECggIFwAfACsiAA==.',
Sn='Snickers:BAABNQAECoEZAAIgAAcK8RFgCgCfAQAgAAcK8RFgCgCfAQAAAA==.',
So='Solarian:BAABNQAECoEVAAIQAAcKRxB/LQCzAQAQAAcKRxB/LQCzAQAAAA==.',
St='Starosa:BAAANQADCgEIAQAAAA==.Startle:BAAANQADCgYIFwAAAA==.Steelbreeze:BAAANQADCggIGQAAAA==.Storms:BAABNQAECoEqAAMMAAkKuSD+SwDaAgAMAAkKPx3+SwDaAgAVAAMKVyPuFQAsAQAAAA==.Stoutbringer:BAAANQAECgEIAgAAAA==.Stride:BAAANQAECgEIAQABNQAECggIFQALAHoYAA==.',
Sy='Sylvaedir:BAAANQADCggICQAAAA==.',
['Sö']='Sören:BAAANQAECgUIDgAAAA==.',
Ta='Taomi:BAAANQAECgcIBwAAAA==.',
Te='Teaka:BAAANQADCgYIEAAAAA==.Tenspeed:BAAANQAECgcIDwAAAA==.Terellesguy:BAAANQADCgQIBAABNQAECgcIGgAHAN8YAA==.Tetsuro:BAAANQADCgUIBwAAAA==.',
Th='Thire:BAAANQADCgcICwABNQAECgcIFQABAHUHAA==.Throwglaive:BAAANQAECgcIDwABNQAFFAYIFAAJAG4kAA==.',
Ti='Tidereign:BAAANQAECgQICwAAAA==.Tinytotems:BAABNQAECoEZAAIdAAcKWBmnTwD5AQAdAAcKWBmnTwD5AQAAAA==.Tiriell:BAABNQAECoEiAAIDAAgK7BSSdwAOAgADAAgK7BSSdwAOAgAAAA==.',
To='Toe:BAAANQAFFAMIAwAAAA==.Touchmee:BAAANQADCgcIAQAAAA==.',
Tr='Trausti:BAAANQAECgUJCgAAAA==.Treehen:BAABNQAECoEXAAIfAAgKKyKmBQAUAwAfAAgKKyKmBQAUAwAAAA==.Trinanah:BAABNQAECoEhAAIUAAkKtRCbIgD4AQAUAAkKtRCbIgD4AQAAAA==.Troltsky:BAAANQADCgQIBAAAAA==.',
Va='Valariann:BAAANQADCggICAABNQAECgkJJgAbAPYXAA==.Valeriux:BAAANQADCgUJAwAAAA==.Valgal:BAAANQAECgUIBgAAAA==.Valiraste:BAABNQAECoEeAAIPAAkKkRYxRQBmAgAPAAkKkRYxRQBmAgABNQAFFAEIAQAeAAAAAA==.Valor:BAAANQAECgEIAgABNQAECggIHwADAJgeAA==.Vapor:BAAANQADCgQIBAAAAA==.Varalina:BAAANQAECgQJBwAAAA==.',
Vi='Viital:BAAANQADCgYIBgAAAA==.Vischar:BAAANQADCgUIBwAAAA==.',
Vo='Voidmommy:BAAANQABCgEIAQAAAA==.',
Wa='Washbeans:BAABNQAECoEkAAMhAAkKix5CHgBxAgAhAAkKix5CHgBxAgASAAIKFhp/oACUAAAAAA==.Wayne:BAAANQABCgQIAgAAAA==.',
We='Wef:BAABNQAECoEUAAIGAAgKQgqlgQDaAQAGAAgKQgqlgQDaAQAAAA==.',
Wh='Whyse:BAABNQAECoEYAAIMAAcKmA0K2gCtAQAMAAcKmA0K2gCtAQAAAA==.',
Wi='Wings:BAABNQAECoEVAAILAAgKehg/DwBJAgALAAgKehg/DwBJAgAAAA==.Wintel:BAAANQADCgYIBwAAAA==.Wizaes:BAAANQAECgEIAQAAAA==.',
Xa='Xanza:BAAANQADCgYIDgAAAA==.',
Ya='Yamzaio:BAAANQADCgUJBwAAAA==.',
Yo='Yo:BAAANQADCgcIDAAAAA==.',
Za='Zancrafter:BAAANQADCgIIAgABNQAECgkJJgAQAM8ZAA==.Zandk:BAAANQAECgEIAQABNQAECgkJJgAQAM8ZAA==.Zanduwuin:BAABNQAECoEmAAMQAAkKzxnlEQDJAgAQAAkKzxnlEQDJAgAWAAMKRgmjIgB1AAAAAA==.Zanvoker:BAABNQAECoEnAAQgAAkKUBizBgAsAgAgAAkKBRizBgAsAgALAAYKLBN1HABpAQAKAAcKJQnKJgBfAQABNQAECgkJJgAQAM8ZAA==.Zargar:BAAANQAECgQIDQAAAA==.',
Zo='Zorttok:BAAANQAECgEIAQAAAA==.',
Zu='Zukkario:BAACNQAFFIEUAAMJAAYKbiTNBABcAgAJAAYKwCPNBABcAgAiAAQK+h60AACKAQA1AAQKgSMAAwkACQp5Jv4PAHgDAAkACQpcJv4PAHgDACIAAQr3JpoiAHYAAAAA.',
Zy='Zyp:BAAANQAECgEIAgAAAA==.',
['Âx']='Âxel:BAABNQAECoEfAAIdAAgKZSQMDgA8AwAdAAgKZSQMDgA8AwAAAA==.',
['År']='Årgon:BAABNQAECoEjAAISAAkKzRkoJQCKAgASAAkKzRkoJQCKAgAAAA==.',
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
