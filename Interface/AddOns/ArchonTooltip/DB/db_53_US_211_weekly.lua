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

local lookup = {'Paladin-Protection','Monk-Windwalker','Warrior-Arms','Paladin-Retribution','Monk-Brewmaster','Priest-Holy','Shaman-Restoration','DemonHunter-Devourer','Druid-Restoration','Unknown-Unknown','Hunter-Survival','Druid-Balance','Shaman-Elemental','Mage-Arcane','Warrior-Protection','Warrior-Fury','Rogue-Assassination','Paladin-Holy','DemonHunter-Vengeance','Druid-Feral','Hunter-BeastMastery','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Mage-Frost','Priest-Discipline','DemonHunter-Havoc','Priest-Shadow','Evoker-Augmentation','Monk-Mistweaver','Hunter-Marksmanship','Shaman-Enhancement','Rogue-Subtlety','DeathKnight-Frost','DeathKnight-Blood','Rogue-Outlaw','Druid-Guardian','Evoker-Devastation','Warlock-Affliction','Mage-Fire','Evoker-Preservation',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abysslicker:BAAANQADCggIFAAAAA==.',
Ac='Achooe:BAABNQAECn8rAAIBAAgKFwQROQC3AAABAAgKFwQROQC3AAAAAA==.Acrylic:BAAANQAECgIIAQAAAA==.',
Ad='Ado:BAABNQAECn8WAAICAAoK3A+4IACAAQACAAoK3A+4IACAAQAAAA==.Adrel:BAAANQAECgYIBQAAAA==.Adversity:BAACNQAFFH8JAAIDAAUKNhyzJQDTAAADAAUKNhyzJQDTAAA1AAQKfx4AAgMACgoZIiIjAKoCAAMACgoZIiIjAKoCAAAA.',
Ae='Aegeus:BAAANQADCggICQAAAA==.Aenil:BAAANQADCgMIAwAAAA==.Aevintz:BAAANQAECgcICgAAAA==.',
Ai='Aiolii:BAABNQAECn8YAAIEAAcKjROH4QAFAQAEAAcKjROH4QAFAQAAAA==.Aisling:BAAANQADCgQIBAAAAA==.',
Ak='Akiras:BAAANQABCgYIDAAAAA==.',
Al='Alanala:BAAANQABCgQIBAAAAA==.Alarielle:BAAANQAECgIIAgABNQAECggIKQAFAKYgAA==.Alcestis:BAAANQADCgIIAgAAAA==.Aldea:BAAANQAECgUIEAABNQAECgoKJwAGANMZAA==.Alexeika:BAAANQAECgYIBgAAAA==.Aliseadyn:BAAANQAECgEIAQABNQAECggIFgAHAJocAA==.Alyndrya:BAABNQAECn9VAAIIAAoKmhOYFwDnAQAIAAoKmhOYFwDnAQAAAA==.',
Am='Amithralia:BAABNQAECn8vAAIJAAoKZCElCABFAwAJAAoKZCElCABFAwAAAA==.',
An='Anejo:BAAANQAECgQIBAAAAA==.Ankari:BAAANQADCgEIAQAAAA==.Ansdusk:BAAANQAECgQICgABNQAECgcIDQAKAAAAAA==.Anzarna:BAAANQAECgUIBwABNQAECgUIDwAKAAAAAA==.',
Ao='Aohikari:BAAANQAECgQICAABNQAFFAgIGwAHANEXAA==.',
Ap='Apples:BAAANQADCgMIAwAAAA==.Aprigity:BAAANQAECggIEwAAAA==.',
Aq='Aquaten:BAABNQAECn8fAAILAAcKdRKSCABTAQALAAcKdRKSCABTAQAAAA==.',
Ar='Arashinigon:BAABNQAECn8kAAMMAAgKfw0aOgAzAQAMAAcKhAwaOgAzAQAJAAYKoxE6QQAdAQAAAA==.Arcafrost:BAAANQAECggIAQAAAA==.Arceus:BAAANQAECgQIEAAAAA==.Arick:BAABNQAECn8VAAIEAAgK3hS7zgB+AQAEAAgK3hS7zgB+AQAAAA==.Ark:BAABNQAECn9nAAMHAAoK+iYSAAAFBAAHAAoK+iYSAAAFBAANAAIKQiHZzwBfAAAAAA==.',
At='Atanker:BAAANQADCgMIAwAAAA==.',
Au='Aunn:BAAANQAECgYICgAAAA==.Aureia:BAABNQAECn8UAAMNAAkKOB24SQBQAgANAAkKOB24SQBQAgAHAAEKHA3pHAEzAAAAAA==.Auriea:BAAANQAECgQIAgABNQAECgkJFAANADgdAA==.',
Ax='Axon:BAABNQAECn8zAAIOAAkKvAsghQCLAQAOAAkKvAsghQCLAQAAAA==.',
Ay='Aybarak:BAAANQADCgMIAwAAAA==.',
Ba='Baaku:BAAANQAECgQIBgAAAA==.Baelhay:BAABNQAECn8kAAMPAAcKIQPEKQCbAAAPAAcKIQPEKQCbAAAQAAEKAABjOwAcAAAAAA==.Ballard:BAAANQADCgMIAwAAAA==.Barrelroll:BAAANQADCggIEwAAAA==.Bashon:BAABNQAECn9MAAMHAAoKwB1ZFgDwAgAHAAoKwB1ZFgDwAgANAAEKAAABWQEgAAAAAA==.Battlebot:BAAANQAECgUIDAAAAA==.',
Be='Beet:BAABNQAECn85AAICAAkKOyGFCgCsAgACAAkKOyGFCgCsAgAAAA==.Belgaron:BAAANQAECgcICwABNQAECgkJQAACAC0YAA==.Belitha:BAABNQAECn8yAAIIAAoKOSH3DAAUAwAIAAoKOSH3DAAUAwAAAA==.Belmaris:BAABNQAECn8uAAIRAAgKaxrADgDOAQARAAgKaxrADgDOAQAAAA==.Beriana:BAAANQAECgQIBAABNQAECgoKHgASABARAA==.Betëlgeuse:BAAANQADCgUICQAAAA==.',
Bi='Bigcupcakes:BAAANQAECgUICgAAAA==.Bigdruid:BAAANQAECgIIAwABNQAECggICwAKAAAAAA==.Biloughah:BAAANQAECgIIAgAAAA==.Bimbosuzi:BAAANQAECgUIDAAAAA==.Bingbing:BAAANQADCgUIBAAAAA==.Binghealing:BAAANQADCgEIAQAAAA==.',
Bl='Blasteyes:BAABNQAECn8sAAITAAkKAxyKCQBOAgATAAkKAxyKCQBOAgAAAA==.Bloomharvest:BAAANQADCgEIAQAAAA==.Bluegrass:BAABNQAECn9IAAIUAAoKfiL4AgAOAwAUAAoKfiL4AgAOAwAAAA==.',
Bo='Borc:BAAANQADCgcIGwAAAA==.Borik:BAABNQAECn8pAAIFAAgKpiCkBABaAgAFAAgKpiCkBABaAgAAAA==.Borknagar:BAAANQADCgcIFAAAAA==.',
Br='Brat:BAAANQADCgcIBwABNQAFFAgIKQAGACUeAA==.Brighteye:BAAANQAECgQIBAAAAA==.Brindis:BAAANQAECgUICAAAAA==.Brisket:BAAANQADCggIIQABNQAECgEIAQAKAAAAAA==.Brutalicious:BAAANQADCgIIAgAAAA==.',
Bu='Bubblebut:BAABNQAECn83AAISAAoKqh+VEAArAwASAAoKqh+VEAArAwAAAA==.Bubbs:BAAANQADCgQIBAABNQAECgoKQgACAAslAA==.Buckme:BAABNQAECn8pAAIVAAoK4RiyMwDRAgAVAAoK4RiyMwDRAgAAAA==.Bulova:BAAANQAECgQIBAAAAA==.Bunnygirl:BAAANQAECgIIAgABNQAFFAkJHAAWACsfAA==.Busen:BAAANQADCggIHQAAAA==.',
By='Byungsoon:BAAANQADCgQIBAAAAA==.',
['Bà']='Bàal:BAABNQAECn8hAAMWAAoKqxJjUwBcAgAWAAoKqxJjUwBcAgAXAAEKNxFMcwA7AAAAAA==.',
Ca='Caiphage:BAAANQAECgIIAgAAAA==.Caladelm:BAABNQAECn8aAAIEAAYKKhS0uQBIAQAEAAYKKhS0uQBIAQAAAA==.Caralhan:BAABNQAECn8aAAIYAAgK8gqKNQA3AQAYAAgK8gqKNQA3AQAAAA==.Castelo:BAAANQAECggIDwAAAA==.',
Ce='Cedra:BAABNQAECn9RAAMOAAoKDSSQGAByAwAOAAoK9iOQGAByAwAZAAIKnh/wIwCpAAAAAA==.Cegeo:BAABNQAECn80AAIXAAoKWhMGBADMAQAXAAoKWhMGBADMAQAAAA==.Celari:BAAANQAECgEIAQAAAA==.Celinari:BAAANQADCgEIAQAAAA==.Centric:BAAANQADCgcIBwAAAA==.',
Ch='Cheepdeeps:BAABNQAECn9GAAIDAAoKvRyvKACRAgADAAoKvRyvKACRAgAAAA==.Chelea:BAAANQADCggIFAAAAA==.Chidora:BAAANQADCgcIBwAAAA==.Chocoworm:BAAANQADCgMIAgAAAA==.Chìpotle:BAAANQADCgYICgAAAA==.',
Ci='Ciennajewel:BAABNQAECn8kAAIGAAoKPBWALACBAgAGAAoKPBWALACBAgAAAA==.Cirdle:BAABNQAECn8xAAIVAAgKiBKtbADOAQAVAAgKiBKtbADOAQAAAA==.',
Co='Cobalt:BAACNQAFFH8LAAIWAAQKLA4mGgDHAAAWAAQKLA4mGgDHAAA1AAQKfywAAhYACgqxHrwgAAEDABYACgqxHrwgAAEDAAE1AAUUBggKABYAexEA.Coolkid:BAAANQAECgMJBAAAAA==.Corntard:BAAANQADCggIGAAAAA==.',
Cr='Crazynlazy:BAABNQAECn8bAAINAAcKcgOy0QDwAAANAAcKcgOy0QDwAAAAAA==.Creamtastic:BAAANQAECgIIAgABNQAECgoKMQAHANAdAA==.Crucifixea:BAABNQAECn8oAAMSAAkKEBRNSABGAgASAAgKoBVNSABGAgABAAkK/xO/HgBjAQABNQAFFAUIDgAGAAARAA==.Cruxsader:BAAANQADCggIEAAAAA==.Crystyl:BAABNQAECn8gAAIZAAgKyw3lEQBRAQAZAAgKyw3lEQBRAQAAAA==.',
Ct='Ctesias:BAAANQADCgYIBgAAAA==.',
Cu='Cuddly:BAAANQAECgcIBwABNQAFFAkJEgAaACUTAA==.Cute:BAAANQAECgYIBgABNQAFFAgIKQAGACUeAA==.',
Cy='Cymoril:BAABNQAECn9EAAIDAAoKZhv/OABOAgADAAoKZhv/OABOAgAAAA==.',
Da='Daamass:BAAANQAECgIIAgAAAA==.Dagyrr:BAAANQADCgEIAQAAAA==.Dalman:BAAANQAECgQIBgAAAA==.Dalmin:BAAANQADCggICAAAAA==.Dalov:BAABNQAECn8lAAIVAAoKLRvlPABMAgAVAAoKLRvlPABMAgAAAA==.Darkcarnival:BAABNQAECn8nAAIWAAgK0xTpawCAAQAWAAgK0xTpawCAAQAAAA==.Darkkill:BAAANQADCgMIAwABNQAECgoKKQAHAFQjAA==.Darthraider:BAABNQAECn8aAAIYAAYKlwUzUwCrAAAYAAYKlwUzUwCrAAAAAA==.Dasnotgood:BAAANQADCggIHwAAAA==.',
De='Deemon:BAABNQAECn8lAAMIAAoKQBb4MgCqAQAIAAcKtxj4MgCqAQAbAAUKJhJjWACtAAAAAA==.Delathatha:BAAANQADCgcICwAAAA==.Demiish:BAAANQADCgEIAQAAAA==.Demorjan:BAAANQADCggIFgAAAA==.Denard:BAAANQADCggIFQABNQAECgEIAQAKAAAAAA==.Denarias:BAAANQADCgUJBQABNQAECgUIDwAKAAAAAA==.Denevien:BAABNQAECn8eAAMGAAkKoRUeUADjAQAGAAgKMRUeUADjAQAcAAIKeAYtdwA4AAAAAA==.Desdemona:BAABNQAECn8kAAIBAAgKXhCMJwAgAQABAAgKXhCMJwAgAQAAAA==.Dethiaris:BAAANQAECgYIEQAAAA==.',
Di='Diablojr:BAAANQAECgUIDAAAAA==.Dianimal:BAAANQAECgMIAwAAAA==.Distroya:BAAANQAECgQIBAAAAA==.',
Dk='Dkaiseremp:BAABNQAECn8kAAIdAAoK3AftCwCcAQAdAAoK3AftCwCcAQAAAA==.',
Do='Dobutsu:BAABNQAECn8fAAIMAAoKyhywDwCmAgAMAAoKyhywDwCmAgAAAA==.Dog:BAACNQAFFH8aAAIeAAUKyCYNAgAlAgAeAAUKyCYNAgAlAgA1AAQKf/QAAh4ACgoOJwEAAKkEAB4ACgoOJwEAAKkEAAAA.Doomace:BAABNQAECn9DAAMEAAoKnBS8fwAqAgAEAAoKnBS8fwAqAgABAAEKwgGAbgAaAAAAAA==.',
Dr='Draaka:BAAANQADCgYIDgAAAA==.Dragee:BAAANQAECgYIBgABNQAECgoKJQAIAEAWAA==.Dragon:BAABNQAECn8UAAMLAAoKrhe3BAAXAgALAAgK6he3BAAXAgAVAAMKKRXwBAGOAAAAAA==.Driftyshaman:BAAANQAECgUICwAAAA==.Droopy:BAAANQAECgYIDwAAAA==.Dræghoule:BAABNQAECn8eAAIYAAgK6gdjPAASAQAYAAgK6gdjPAASAQAAAA==.',
Du='Durnik:BAABNQAECn8uAAMVAAoKCSFlGwDJAgAVAAoKCSFlGwDJAgAfAAMKPghdSwBmAAABNQAECgkJQAACAC0YAA==.',
Dw='Dworflundgrn:BAABNQAECn8oAAIgAAoKkAe3FgCNAQAgAAoKkAe3FgCNAQAAAA==.',
Dy='Dyamí:BAABNQAECn8vAAIOAAgKxxZ2egCkAQAOAAgKxxZ2egCkAQAAAA==.',
['Dá']='Dánte:BAAANQAECgYICQAAAA==.',
Eg='Eglosira:BAAANQADCgMIBQAAAA==.',
El='Elbuhero:BAABNQAECn8qAAMJAAgKJwezNgBmAQAJAAgKJwezNgBmAQAMAAUK+xX/XQBZAQAAAA==.Eldiablo:BAAANQAECgMIBwAAAA==.Electric:BAABNQAECn8UAAINAAUKxQjx1QDoAAANAAUKxQjx1QDoAAAAAA==.Elementstone:BAAANQAECgIIAgAAAA==.Elendish:BAAANQADCgIIAgAAAA==.Eleven:BAABNQAECn80AAIOAAoKeQlxjgB2AQAOAAoKeQlxjgB2AQAAAA==.Eliasevo:BAAANQADCgcICQABNQAECgoKKQAHAFQjAA==.Elrythe:BAABNQAECn9RAAIVAAoKECElHgC8AgAVAAoKECElHgC8AgAAAA==.',
Er='Eraleth:BAAANQAECgUICwABNQAECgoKMgAIADkhAA==.',
Et='Etarnus:BAAANQADCggIFQAAAA==.',
Fa='Faben:BAAANQADCgUIBQAAAA==.Faced:BAAANQAECgUICwAAAA==.Fatalii:BAABNQAECn8WAAMhAAgKmxQLVQCTAQAhAAcKxRALVQCTAQARAAYKahQCTQCNAQAAAA==.',
Fe='Felebash:BAABNQAECn8YAAIDAAYKHwnougDsAAADAAYKHwnougDsAAAAAA==.Felfireflux:BAAANQADCgYIDAAAAA==.Fellirane:BAAANQADCgUIBQAAAA==.',
Fi='Fistdaddy:BAAANQADCgYJDwAAAA==.',
Fl='Floofies:BAABNQAECn9BAAIgAAoK+yRXAQCtAwAgAAoK+yRXAQCtAwAAAA==.Floofndoom:BAAANQAECgUIBQABNQAECgoKQQAgAPskAA==.Floofthulu:BAAANQAECgEIAQABNQAECgoKQQAgAPskAA==.Fluffalo:BAABNQAECn8+AAINAAoKPyPFCwALAwANAAoKPyPFCwALAwABNQAECgoKQQAgAPskAA==.',
Fo='Foxypocket:BAABNQAECn8cAAIRAAcKNAlAJwD0AAARAAcKNAlAJwD0AAAAAA==.',
Fr='Fredrickk:BAABNQAECn8WAAIHAAgKmhyWVACpAQAHAAgKmhyWVACpAQAAAA==.',
Fu='Furcas:BAAANQAECgIIAgAAAA==.Furrglur:BAAANQAECgIIAgABNQAECgoKQQAgAPskAA==.Furrylight:BAAANQAECgIIAQABNQAECgoKMwAHABojAA==.Furryphase:BAABNQAECn8zAAMHAAoKGiOaCgBmAwAHAAoKGiOaCgBmAwANAAMKlQXH1wBTAAAAAA==.Fuzzington:BAAANQAECgcICwABNQAECgoKQQAgAPskAA==.Fuzzydunlop:BAAANQAECgIIAgAAAA==.',
Fz='Fzoul:BAAANQAECgMIAwAAAA==.',
Ga='Gaith:BAAANQAECgYIBgAAAA==.Galnier:BAABNQAECn8aAAIEAAoKpBAMdADTAQAEAAoKpBAMdADTAQAAAA==.Gandoomi:BAAANQABCgIIAgAAAA==.',
Gh='Ghosted:BAAANQAECgMIBQAAAA==.',
Gl='Glaecia:BAAANQADCgEIAQAAAA==.Glaur:BAABNQAECn8yAAIHAAoKbBdvKgBoAgAHAAoKbBdvKgBoAgAAAA==.',
Go='Goatjira:BAAANQAECgMIBgAAAA==.',
Gr='Greygorypack:BAEANQADCgUIBQAAAA==.Grimgor:BAAANQAECgQIBAABNQAECggIHgAiAFUbAA==.Gripisrdy:BAABNQAECn8nAAQYAAgKPRwyOgA6AgAYAAcKTB0yOgA6AgAiAAcK2hjWSgCPAQAjAAIK2w+lqACAAAAAAA==.Grippindeez:BAABNQAECn8yAAMjAAkKUxY2LACWAQAjAAUKnhw2LACWAQAiAAkK1wwuQwB3AQAAAA==.',
Gu='Gunslingr:BAABNQAECn88AAMkAAoKXSEuAwAIAwAkAAoKECAuAwAIAwAhAAkKhhijHgCHAgAAAA==.',
Gw='Gweetow:BAAANQAECgEIAQAAAA==.',
Gy='Gymsharklyfe:BAAANQAECggIBgAAAA==.',
Ha='Habanero:BAAANQAECggICAAAAA==.Hairyjolene:BAAANQADCggIEgAAAA==.Handsome:BAABNQAECn80AAMfAAoKqx1CCgCOAgAfAAoK/BxCCgCOAgAVAAcKFBfMxwByAQABNQAFFAUIDgAGAAARAA==.',
He='Headpats:BAACNQAFFH8KAAISAAUKgxSgCwB5AQASAAUKgxSgCwB5AQA1AAQKfx8AAhIACgpsH0AVAP4CABIACgpsH0AVAP4CAAE1AAUUCQkSABoAJRMA.Hearthisrdy:BAAANQAECgYIBgAAAA==.Hel:BAAANQADCgUIBQAAAA==.Helgrim:BAAANQADCgUIBQAAAA==.Helmshammer:BAAANQAECgYIBgAAAA==.Hexwhisper:BAAANQAECgQIBAAAAA==.Heycarlos:BAABNQAECn9AAAMiAAkKkCKTBgB5AwAiAAkKkCKTBgB5AwAYAAIKrwfJzQBRAAAAAA==.',
Hi='Hikaripala:BAAANQADCgYIBgABNQAFFAgIGwAHANEXAA==.Hikarishaman:BAACNQAFFH8bAAMHAAgK0ReZCgClAQAHAAYKghWZCgClAQANAAQKmhuMEgBGAQA1AAQKfzkAAw0ACgrPHPshAFUCAA0ACgrPHPshAFUCAAcACgpNHChPACgCAAAA.Hime:BAABNQAECn8qAAIEAAgKgwjX2wAOAQAEAAgKgwjX2wAOAQAAAA==.',
Ho='Holyblimblam:BAAANQAECgMIBwAAAA==.Honeypieheal:BAAANQAECgMIAwAAAA==.Horabad:BAAANQAECgUIEAAAAA==.Hosemachine:BAABNQAECn8ZAAIYAAgKWhkLOgA7AgAYAAgKWhkLOgA7AgAAAA==.',
Hu='Hulque:BAAANQADCgYIBgAAAA==.Humper:BAAANQADCgEIAQAAAA==.',
['Hè']='Hèri:BAAANQAECgMIAwAAAA==.Hèrifire:BAABNQAECn8YAAMOAAYKyRPh2ADoAAAOAAUKchXh2ADoAAAZAAIK2A2MKgB4AAAAAA==.',
Ic='Icyshadow:BAABNQAECn8iAAMcAAcKZwyyLQACAQAcAAcKZwyyLQACAQAGAAEKqxCM7QAzAAAAAA==.',
Id='Idouna:BAAANQADCgEIAQAAAA==.',
Ih='Ihalo:BAAANQAECgYIEAAAAA==.',
Il='Illinesh:BAAANQADCgYICgAAAA==.',
Ir='Ironpaw:BAAANQAECgUJDAAAAA==.',
It='Ithildur:BAAANQADCgQIBAAAAA==.',
Ja='Jadde:BAAANQADCgYIBgAAAA==.Jadienne:BAAANQAECgQIDAAAAA==.Jameson:BAAANQAECgUIDAAAAA==.Jamiel:BAAANQABCgMIAwAAAA==.Jangewinde:BAAANQAECgUIDwAAAA==.Jasmind:BAABNQAECn8nAAMJAAoKHw81HgDyAQAJAAoKHw81HgDyAQAMAAEKAABjxQAdAAAAAA==.Jaywu:BAAANQADCggICAAAAA==.',
Ji='Jiwà:BAABNQAECn84AAMHAAkKARQuVgAPAgAHAAkKARQuVgAPAgANAAcKnwKexgAFAQAAAA==.',
Jo='Joecool:BAAANQAECgcIBwAAAA==.Joshjb:BAAANQAECgIIAgAAAA==.Joss:BAAANQADCgIIAgAAAA==.',
Ka='Kaguro:BAABNQAECn85AAMRAAoKlhVBCwAPAgARAAoK5xRBCwAPAgAkAAkK8w5WCgDWAQAAAA==.Kaibab:BAAANQADCgEIAQAAAA==.Kakwaa:BAAANQAECgIJAwAAAA==.Kalix:BAAANQABCgUICAAAAA==.Kaliyah:BAAANQAECgYIDwAAAA==.Kattrin:BAAANQAECgEIAQAAAA==.Kayleebear:BAAANQADCgQIBAAAAA==.',
Ke='Kerplaa:BAAANQADCgMIAwAAAA==.Keyadistor:BAABNQAECn8eAAQiAAgKVRu+OwCZAQAiAAgKpBq+OwCZAQAjAAMKCx6JZwCgAAAYAAEKAACz5gAuAAAAAA==.',
Kh='Khazabrew:BAABNQAECn8wAAIFAAoKAh3ZBgDXAgAFAAoKAh3ZBgDXAgAAAA==.',
Ki='Kiamara:BAABNQAECn8gAAIWAAgKGQV+pgD1AAAWAAgKGQV+pgD1AAAAAA==.Kinderlin:BAABNQAECn9PAAIEAAoKtxhLTQAzAgAEAAoKtxhLTQAzAgAAAA==.Kirboom:BAAANQAECgUIBQAAAA==.Kirbun:BAABNQAECn8xAAIOAAkK/xyJZwCvAgAOAAkK/xyJZwCvAgAAAA==.Kizchaos:BAAANQAECgMIBAAAAA==.',
Ko='Komurash:BAABNQAECn8zAAMDAAoKMBjoQAAxAgADAAoKMBjoQAAxAgAPAAIKRgM8PABVAAAAAA==.Korstruck:BAAANQAECgUIBQAAAA==.Kotys:BAAANQADCgUIBQAAAA==.',
Kr='Kravvelocity:BAAANQAECggIDAAAAA==.',
Ku='Kungbrew:BAAANQAECgEIAQABNQAECgcIIgAcAGcMAA==.',
La='Lancaban:BAAANQADCggIHQAAAQ==.Lastiri:BAAANQABCgIIAgAAAA==.',
Le='Lethalarrow:BAABNQAECn8nAAIVAAoKoAstcADFAQAVAAoKoAstcADFAQAAAA==.Lethalpally:BAAANQADCggIEQAAAA==.Lewismr:BAAANQADCgUIDQABNQAECgoKPQAEAKMUAA==.Lewisr:BAABNQAECn89AAIEAAoKoxSiZgDyAQAEAAoKoxSiZgDyAQAAAA==.',
Li='Ligahoo:BAAANQADCggIDwAAAA==.Lilysweets:BAAANQADCgcICgAAAA==.',
Lo='Loralynn:BAAANQAECgQIBQABNQAFFAIIBQAEALkDAA==.Lorianne:BAABNQAECn8iAAMNAAoKTgt5VQBwAQANAAkKVAx5VQBwAQAHAAUKiQntswCgAAABNQAFFAIIBQAEALkDAA==.Lorryanne:BAACNQAFFH8FAAIEAAIKuQMiJwBsAAAEAAIKuQMiJwBsAAA1AAQKf1IAAxIACgqgGFE7AHcCABIACgqgGFE7AHcCAAQACgrxD8RyANYBAAAA.',
Lu='Lucianas:BAAANQAECgcIEQAAAA==.Lunacat:BAAANQAECgQICQABNQADCgYJDwAKAAAAAA==.Luxdaddy:BAABNQAECn8bAAIGAAgKPhsaNQBVAgAGAAgKPhsaNQBVAgABNQADCgYJDwAKAAAAAA==.',
Ly='Lysi:BAABNQAECn8cAAIVAAcKtBM7lABwAQAVAAcKtBM7lABwAQAAAA==.',
Ma='Madaea:BAABNQAECn8oAAIeAAoKoRqGEgBUAgAeAAoKoRqGEgBUAgAAAA==.Madameuyen:BAAANQAECgQICwAAAA==.Madlyn:BAAANQAECgQIDwAAAA==.Magepuppy:BAABNQAECn8cAAMOAAgK+hQ/ygDxAQAOAAcKTxU/ygDxAQAZAAEKTxM9QABEAAABNQAECgoKQgABALsdAA==.Makavali:BAABNQAECn85AAMJAAoKDhivEQCUAgAJAAkK6RmvEQCUAgAMAAkKTBGYOwArAQAAAA==.Makavalii:BAABNQAECn9TAAMEAAkK9xUzeAA8AgAEAAkK9xUzeAA8AgASAAkKCxM/UAArAgABNQAECgoKOQAJAA4YAA==.Malanimus:BAAANQAECgYICgAAAA==.Malevola:BAAANQAECgEIAQAAAA==.Malholis:BAAANQAECgUIEAAAAA==.Mandorallen:BAAANQAECgQIBAABNQAECgkJQAACAC0YAA==.Matagi:BAABNQAECn84AAIVAAkKNRbvVwBrAgAVAAkKNRbvVwBrAgAAAA==.Mate:BAAANQADCgUICAABNQAECgEIAQAKAAAAAA==.',
Me='Meatloaf:BAAANQADCgQIBAAAAA==.Meeseks:BAABNQAECn83AAIYAAoKQxtUGQALAgAYAAoKQxtUGQALAgAAAA==.Megabyte:BAAANQAECgQJBAAAAA==.Melbeast:BAABNQAECn8WAAIVAAgK3BTPdQC3AQAVAAgK3BTPdQC3AQAAAA==.Melorea:BAAANQAECgIIAgAAAA==.Merdin:BAABNQAECn8iAAIOAAgKow0kfgCbAQAOAAgKow0kfgCbAQAAAA==.Methmartion:BAABNQAECn8hAAIXAAcKdwm+FACqAAAXAAcKdwm+FACqAAAAAA==.',
Mi='Mignon:BAAANQAECgEIAQAAAA==.Milougheh:BAAANQAECggIAgAAAA==.Minós:BAAANQADCgUIBQAAAA==.Mish:BAAANQAECgQIBAAAAA==.Missiah:BAABNQAECn8wAAIBAAoKiAevJAA0AQABAAoKiAevJAA0AQAAAA==.',
Mo='Moirane:BAAANQADCgQIBAAAAA==.Molfise:BAAANQADCgYIBQAAAA==.Monna:BAAANQABCgIIAgAAAA==.Moonfell:BAABNQAECn8uAAIGAAoKaBIQXwCtAQAGAAoKaBIQXwCtAQAAAA==.Moonlilly:BAABNQAECn8fAAIPAAgKPwVeIQDZAAAPAAgKPwVeIQDZAAAAAA==.Mopp:BAABNQAECn8UAAMDAAQKYwes8AB+AAADAAQKwwWs8AB+AAAPAAEKKAqTRwAmAAAAAA==.Morganthe:BAAANQADCggIEAAAAA==.Mornîngstar:BAAANQAECggIEQAAAA==.',
Mu='Mugatoo:BAAANQAECggIBAAAAA==.',
Mx='Mxtemlen:BAAANQAECgQIBAABNQAECggIHAASAHcSAA==.',
My='Mylilhunter:BAABNQAECn8iAAIVAAgKDQgvoABXAQAVAAgKDQgvoABXAQAAAA==.Myrtheli:BAAANQADCggICAABNQAECgoKJwAGANMZAA==.Mysticx:BAAANQAECggICAAAAA==.',
Na='Nachtelf:BAABNQAECn9LAAIVAAoKER2rMQBvAgAVAAoKER2rMQBvAgAAAA==.Nagan:BAAANQAECgYIDAAAAA==.Natadawn:BAAANQADCgYIBgAAAA==.Natalone:BAABNQAECn9IAAIZAAoKLST1AQBhAwAZAAoKLST1AQBhAwAAAA==.Nathel:BAABNQAECn8iAAMZAAcKogPALABsAAAOAAcKcgLP+QCuAAAZAAYK/gPALABsAAAAAA==.',
Ne='Nerisa:BAAANQADCgUIBQAAAA==.',
Ni='Nirra:BAAANQAECgMIBQAAAA==.',
No='Noctis:BAAANQAECgYICwAAAA==.Notoriginal:BAABNQAECn80AAIYAAoKaRH1GgD7AQAYAAoKaRH1GgD7AQAAAA==.Novatron:BAABNQAECn8gAAQgAAcKqAVmJQAGAQAgAAcKvQNmJQAGAQANAAQKbwY2vAB9AAAHAAMK7wCRFwE8AAAAAA==.',
Nu='Nuance:BAAANQAECgIIAgAAAA==.Nuked:BAABNQAECn8UAAIOAAYKuxddAAGNAQAOAAYKuxddAAGNAQAAAA==.',
['Né']='Néith:BAAANQADCgQIBAAAAA==.',
Od='Odor:BAAANQAECgQIBwAAAA==.',
Og='Ograskygazer:BAABNQAECn8fAAIJAAcKBAVlRQDUAAAJAAcKBAVlRQDUAAAAAA==.',
Oi='Oieg:BAAANQABCgUIBAAAAA==.',
Om='Omee:BAABNQAECn8kAAMbAAoKHRDALQCOAQAbAAkKEw/ALQCOAQAIAAcKfg1VLwAHAQAAAA==.Omegaone:BAAANQADCgcIBwAAAA==.',
On='Oneil:BAAANQADCgMJAwAAAA==.Onlyshrimps:BAAANQAECgYIBgAAAA==.',
Op='Ophela:BAAANQAECgEIAQAAAA==.',
Or='Oralena:BAABNQAECn8gAAIVAAcK3AN94gDQAAAVAAcK3AN94gDQAAAAAA==.Orioncheats:BAABNQAECn9CAAMYAAoKkBb2HgDWAQAYAAoKYhb2HgDWAQAjAAgKlhNFMgBzAQAAAA==.',
Ow='Owo:BAAANQAECgEIAQAAAA==.',
Ox='Oxygën:BAABNQAECn8uAAIOAAoKpBSiUAAQAgAOAAoKpBSiUAAQAgAAAA==.',
Pa='Palomita:BAAANQADCgIIAgAAAA==.',
Pe='Ped:BAAANQAECgEIAQABNQAECgoKJwAGANMZAA==.Pedaramun:BAAANQAECgcIBwABNQAECgoKJwAGANMZAA==.Pedarias:BAABNQAECn8nAAMGAAoK0xkxLgB4AgAGAAoK0xkxLgB4AgAcAAEKAABTlgANAAAAAA==.Peon:BAAANQAECgYIDwAAAA==.Perstephanie:BAAANQADCgQIBAAAAA==.',
Ph='Pharune:BAABNQAECn8tAAIlAAgK1Q6bKgAgAQAlAAgK1Q6bKgAgAQAAAA==.Phredrick:BAAANQAECgUIEAAAAA==.',
Pi='Piemanninty:BAAANQAECgIJBQAAAA==.',
Pl='Plandemic:BAAANQAECgEIAQAAAA==.',
Po='Pockithealz:BAAANQADCgQIBAABNQAECggIFgAhAJsUAA==.Pointnshoot:BAAANQADCgQIBwABNQAECgcIJwAKAAAAAA==.Pokerface:BAAANQAECgYIDAAAAA==.Ponky:BAAANQAECgIIAgABNQAECgoKNAASAHgbAA==.Poongwoon:BAAANQADCgMIAwAAAA==.Pounces:BAACNQAFFH8GAAIJAAQKBxKhCgApAQAJAAQKBxKhCgApAQA1AAQKfxYAAgkACQplHRwcAAkCAAkACQplHRwcAAkCAAE1AAUUCQkSABoAJRMA.',
Pr='Precious:BAABNQAECn8mAAIGAAoKpiXJAABFBAAGAAoKpiXJAABFBAABNQAFFAgIKQAGACUeAA==.',
Pu='Puppet:BAAANQAECgcIEAABNQAFFAgIKQAGACUeAA==.',
Py='Pymura:BAAANQADCgQIBAAAAA==.',
['Pí']='Píongá:BAAANQADCgEIAQAAAA==.',
Qe='Qee:BAAANQAECgEIAQABNQAECgoKJQAIAEAWAA==.',
Qu='Quattro:BAABNQAECn8lAAImAAkKkg4qDACAAQAmAAkKkg4qDACAAQAAAA==.',
Ra='Racecar:BAAANQAECgUIDQAAAA==.Raezil:BAAANQAECgQICQABNQAECgoKIQAWAKsSAA==.Raivyn:BAABNQAECn9AAAICAAkKLRgfFAAQAgACAAkKLRgfFAAQAgAAAA==.Rathmora:BAAANQADCggIJAAAAA==.Raylaira:BAAANQAECgUIDwAAAA==.Raziel:BAAANQADCgYIBgAAAA==.',
Re='Redbeard:BAAANQAECgUIBgAAAA==.Remnants:BAAANQADCggIEwAAAA==.Renard:BAABNQAECn9GAAIJAAoKAiRjAwCSAwAJAAoKAiRjAwCSAwAAAA==.Reposado:BAABNQAECn8eAAIiAAgK0Bo3JwAKAgAiAAgK0Bo3JwAKAgAAAA==.Revelare:BAABNQAECn8nAAIHAAgKrBZ8ZwDWAQAHAAgKrBZ8ZwDWAQAAAA==.Rexbie:BAAANQAECgcICwAAAA==.',
Rh='Rhylee:BAAANQAECgUIDgAAAA==.',
Ri='Rianne:BAAANQADCgUIBQAAAA==.Riptidepod:BAABNQAECn8xAAMHAAoK0B3bJgDJAgAHAAoK0B3bJgDJAgANAAEKAACrRgErAAAAAA==.',
Rm='Rmplstiltskn:BAAANQADCgUICQAAAA==.',
Ro='Robberttrest:BAABNQAECn8cAAIVAAUKWwl87QAmAQAVAAUKWwl87QAmAQAAAA==.Rockyhunter:BAAANQAECggIDAABNQAECgoKQwAjAKoeAA==.Rockyhunterr:BAABNQAECn9DAAIjAAoKqh7zEQAdAwAjAAoKqh7zEQAdAwAAAA==.Rockymage:BAAANQADCgYIBgAAAA==.Rockyrogue:BAAANQADCggICAABNQAECgoKQwAjAKoeAA==.Rockywarlock:BAAANQAECgEIAQABNQAECgoKQwAjAKoeAA==.Rockywarrior:BAAANQADCgYICgABNQAECgoKQwAjAKoeAA==.Ronaeminnda:BAAANQABCgQIBAAAAA==.Rooth:BAABNQAECn8WAAImAAYK+Aw0EQASAQAmAAYK+Aw0EQASAQAAAA==.Roryn:BAABNQAECn9TAAIEAAoK3iXaBwBYAwAEAAoK3iXaBwBYAwAAAA==.',
Ru='Rubï:BAABNQAECn8qAAIQAAoKKCRgAQA3AwAQAAoKKCRgAQA3AwAAAA==.Ruggburn:BAAANQAECgYIBgABNQAECgoKMQAZAE0bAA==.Rugiaas:BAACNQAFFH8pAAISAAcKXSGqAgB+AgASAAcKXSGqAgB+AgA1AAQKf0EAAxIACgofJc4EAKoDABIACgofJc4EAKoDAAQABArUGM35ACsBAAAA.Rugian:BAAANQAECgQIBQABNQAFFAcIKQASAF0hAA==.Rugis:BAAANQAECgMIBQABNQAFFAcIKQASAF0hAA==.',
Ry='Ryuka:BAAANQAECgcIEQAAAA==.',
['Râ']='Râezil:BAAANQADCgIIAgABNQAECgoKIQAWAKsSAA==.',
Sa='Sabriiel:BAAANQADCgIIAwABNQAECgQIBgAKAAAAAA==.Samyria:BAAANQAECgQICQAAAA==.Sapphiriana:BAAANQADCgIIAgABNQAECgYIFgAmAPgMAA==.Saprates:BAAANQADCgMIAwAAAA==.Satyaru:BAABNQAECn8xAAQFAAoKoBDsEQDHAQAFAAgKag/sEQDHAQAeAAkKKQ3HFgB8AQACAAEKAAAIcwAmAAAAAA==.Saucy:BAABNQAECn8eAAINAAcKlxWYbwAjAQANAAcKlxWYbwAjAQAAAA==.',
Se='Sedona:BAABNQAECn8XAAInAAcKJgNtGQC8AAAnAAcKJgNtGQC8AAAAAA==.Selarra:BAABNQAECn8mAAIGAAoKEw9cfACkAQAGAAoKEw9cfACkAQAAAA==.Seric:BAABNQAECn8wAAMPAAoKtw0pGwCHAQAPAAkKtg4pGwCHAQADAAkKjQaPlgA9AQAAAA==.Sethuriel:BAAANQAECggIDgAAAA==.',
Sh='Shadowdancèr:BAAANQADCgEJAQAAAA==.Shadowlocke:BAAANQADCgMIAwAAAA==.Shalzith:BAAANQAECgEIAQAAAA==.Shenandoah:BAAANQADCgYIBgAAAA==.Shockadelica:BAAANQADCgYIBgAAAA==.',
Si='Sitheretta:BAAANQAECgUICQAAAA==.',
Sk='Skoto:BAAANQAECggICwAAAA==.',
Sm='Smartfood:BAABNQAECn8eAAIDAAkK0wxXlgA+AQADAAkK0wxXlgA+AQAAAA==.Smoochybooty:BAAANQAECgMIBAAAAA==.',
Sn='Snuggy:BAAANQAECgIIAgAAAA==.',
So='Solnar:BAABNQAECn8cAAMSAAgKdxJZYAD3AQASAAgKdxJZYAD3AQAEAAQK8QyVRwGuAAAAAA==.Soupspoon:BAAANQAECggIBAAAAA==.',
Sp='Specter:BAAANQAECggICAAAAA==.Splashdaddy:BAACNQAFFH8PAAIHAAgKFw/ICQCzAQAHAAgKFw/ICQCzAQA1AAQKf0UAAgcACgrxIqkWAO0CAAcACgrxIqkWAO0CAAE1AAMKBgkPAAoAAAAA.Spoiled:BAAANQADCggICAABNQAFFAgIKQAGACUeAA==.',
Sr='Srìracha:BAAANQAECggIDgAAAA==.',
St='Staks:BAAANQADCgcIFAAAAA==.Starii:BAABNQAECn8gAAIHAAgKUwWaiQADAQAHAAgKUwWaiQADAQAAAA==.Stormieskye:BAABNQAECn89AAINAAoKWRWUMAABAgANAAoKWRWUMAABAgAAAA==.Striga:BAAANQADCgcIBwAAAA==.',
Su='Summonme:BAAANQAECgIIAgAAAA==.Suzume:BAAANQAECgQIBAABNQAFFAgIGwAHANEXAA==.',
Sw='Sweetshot:BAAANQADCgEIAQAAAA==.',
Sy='Sylvancura:BAAANQADCgQIBAAAAA==.Synestra:BAABNQAECn8bAAIlAAYKihpmIgCEAQAlAAYKihpmIgCEAQAAAA==.',
Ta='Taea:BAABNQAECn8ZAAIHAAYK4B/dRADpAQAHAAYK4B/dRADpAQAAAA==.Taeus:BAACNQAFFH8FAAMOAAIKIxFiRgBJAAAOAAIKIxFiRgBJAAAZAAEKAAA4FwAAAAA1AAQKfzoABBkACgrGIOIGAIsCABkACgo2IOIGAIsCAA4ACQqWG9/TAN8BACgAAQo/D3MMAD8AAAAA.Taintedkoma:BAAANQAECgUIBwABNQAECgcIIQAXAHcJAA==.Talagark:BAAANQADCgYIBgAAAA==.Talanat:BAAANQADCgIIAgAAAA==.Taurenator:BAABNQAECn8eAAIPAAoKQyCkBgD5AgAPAAoKQyCkBgD5AgAAAA==.',
Te='Tearinass:BAAANQAECgUIBQAAAA==.Teheez:BAAANQADCgIIAgAAAA==.Tenthrol:BAAANQABCgMIBQAAAA==.Teranidas:BAAANQAECgUICgABNQAECgUIDwAKAAAAAA==.Teratrendera:BAABNQAECn8iAAIpAAcKOiE8CQCZAgApAAcKOiE8CQCZAgAAAA==.Teron:BAAANQAECgMJBAAAAA==.Tesx:BAAANQAECgIIAQAAAA==.',
Th='Thavis:BAABNQAECn82AAMXAAoKLRQJDQDhAAAWAAoK4RDYUgDIAQAXAAQKqRYJDQDhAAAAAA==.Thdoris:BAAANQADCgQIBAAAAA==.Therele:BAAANQAECgQIBAAAAA==.Thetimelord:BAAANQAECgMIBQAAAA==.Thewarrior:BAABNQAECn8bAAMDAAoKQRgOWADjAQADAAoKdRQOWADjAQAQAAYK2BtCEQBLAQAAAA==.Thrask:BAAANQADCgQIBAAAAA==.',
Ti='Ticktac:BAAANQAECgcIBgAAAA==.Tik:BAAANQADCggIDgAAAA==.Tilted:BAABNQAECn8hAAMEAAoKbRc4kwD9AQAEAAoKbRc4kwD9AQABAAEKAAC4dwAAAAAAAA==.Tiltêd:BAAANQAECgYIDAAAAA==.Tinkr:BAABNQAECn89AAIjAAoK4xqQFABcAgAjAAoK4xqQFABcAgAAAA==.',
To='Tobi:BAAANQADCgYIBgAAAA==.Toewzix:BAAANQAECgQIBAAAAA==.Tom:BAAANQAECgUICAABNQAECgoKIQAWAKsSAA==.Torrey:BAABNQAECn8qAAMTAAoKIwumDwA2AQAIAAkKngmuNACdAQATAAoKrAmmDwA2AQAAAA==.Totemsareus:BAABNQAECn8pAAMHAAoKVCMgCACAAwAHAAoKVCMgCACAAwANAAIKigdZFQFjAAAAAA==.Toxx:BAAANQAECgcIBgABNQAECgoKJAAbAB0QAA==.',
Tr='Tradd:BAACNQAFFH8OAAIGAAUKABE3FQBDAQAGAAUKABE3FQBDAQA1AAQKf0cABAYACgojISMOAFMDAAYACgojISMOAFMDABwACgoRFO0RACYCABoABwrDDr4MAGwBAAAA.Trallor:BAABNQAECn8nAAMDAAkKQgwVvgCBAQADAAgKWg0VvgCBAQAPAAMKJglSNQBbAAAAAA==.Trhall:BAAANQAECgQICwAAAA==.Tristyana:BAABNQAECn9GAAIVAAoKqBI/VAANAgAVAAoKqBI/VAANAgAAAA==.',
Ts='Tsiddahn:BAABNQAECn8sAAIGAAkK9RqmKADHAgAGAAkK9RqmKADHAgAAAA==.Tsunâde:BAABNQAECn9CAAMCAAoKCyVRAwBAAwACAAoKCyVRAwBAAwAeAAcKExIqIQD0AAAAAA==.',
Tw='Twanu:BAAANQAECgUICQAAAA==.',
Ty='Tylurien:BAABNQAECn8tAAISAAgKHCbNGQAQAwASAAgKHCbNGQAQAwAAAA==.Tyrael:BAABNQAECn80AAMBAAoKCQ95GwB/AQABAAoKCQ95GwB/AQASAAEKYwL9BgEVAAABNQADCgMIBgAKAAAAAA==.',
Uk='Ukon:BAAANQADCgYIBgAAAA==.',
Ul='Ulangi:BAAANQAECgEIAQAAAA==.',
Un='Un:BAAANQADCgcIAQAAAA==.',
Ur='Urbanprey:BAABNQAECn8pAAIXAAkKrgsNCQAlAQAXAAkKrgsNCQAlAQAAAA==.',
Va='Valenhi:BAAANQAECgIIAQAAAA==.Valkoinen:BAAANQADCgMIBgAAAA==.Valora:BAABNQAECn9FAAIGAAoKjh6CGwDrAgAGAAoKjh6CGwDrAgAAAA==.Valoria:BAAANQAECgIIAwAAAA==.Vanille:BAABNQAECn8fAAIJAAcKRwTqTQCuAAAJAAcKRwTqTQCuAAAAAA==.Vargen:BAAANQAECgcIDAAAAA==.Varonika:BAAANQAECgUIBwAAAA==.Vayla:BAABNQAECn8/AAIPAAkKpB34BgB0AgAPAAkKpB34BgB0AgAAAA==.',
Vb='Vbv:BAAANQAECgcICgAAAA==.',
Ve='Veal:BAAANQADCgYIBgABNQAECgoKJgAGABMPAA==.Vedik:BAAANQAECgYIEwAAAA==.Vegasduc:BAAANQADCgQIBAAAAA==.Vegasducks:BAABNQAECn80AAIOAAoKgwhteACpAQAOAAoKgwhteACpAQAAAA==.Velara:BAAANQADCgYIDAAAAA==.Veld:BAABNQAECn8VAAIIAAgKYg+rMwClAQAIAAgKYg+rMwClAQAAAA==.Velithara:BAAANQADCgYJBgAAAA==.Velura:BAAANQAECggICAAAAA==.Veralyn:BAAANQADCgUICgAAAA==.',
Vi='Violet:BAABNQAECn8iAAIEAAYK1AVUDAEKAQAEAAYK1AVUDAEKAQAAAA==.',
Vy='Vyla:BAAANQABCgcIDAAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUIBQAAAA==.',
Wa='Wardancer:BAAANQAECgUIBQAAAA==.Warfise:BAABNQAECn8YAAIPAAYKHBgXFABkAQAPAAYKHBgXFABkAQAAAA==.Warspriest:BAABNQAECn8nAAIcAAgK3BrCHgBIAgAcAAgK3BrCHgBIAgAAAA==.Warwizard:BAABNQAECn9bAAISAAoKlyW9AQAbBAASAAoKlyW9AQAbBAAAAA==.',
Wd='Wdemperor:BAABNQAECn8kAAQQAAoKZwZBHgCjAAAQAAYKZQdBHgCjAAAPAAkKnQN1KwCQAAADAAMKzgPiRgFDAAABNQAECgoKJAAdANwHAA==.',
We='Webin:BAAANQAECgEIAQAAAA==.',
Wh='Whispaknight:BAAANQAECgEIAQABNQAECgEIAQAKAAAAAA==.Whisperwiind:BAAANQADCgcIBwABNQAECgEIAQAKAAAAAA==.Whisperz:BAAANQADCgYIBgABNQAECgEIAQAKAAAAAA==.',
Wi='Wickedywaque:BAAANQADCgUIBQAAAA==.Wickerchickn:BAAANQAECgQJBwAAAA==.Wiisper:BAAANQAECgEIAQAAAA==.Wilshammy:BAAANQAECgEIAQAAAA==.Winterhunter:BAAANQADCgEIAQAAAA==.',
Wo='Wonkyponky:BAABNQAECn80AAISAAoKeBvdJwDJAgASAAoKeBvdJwDJAgAAAA==.',
Wr='Wrathbarrage:BAABNQAECn8XAAIVAAgKvBLAjADxAQAVAAgKvBLAjADxAQABNQAECgoKPwAlAOgUAA==.Wrathchoi:BAAANQAECgYIBgAAAA==.Wrathstorm:BAABNQAECn8/AAMlAAoK6BQiGACyAQAlAAoK6BQiGACyAQAUAAEKKQoaRwAvAAAAAA==.',
Ya='Yazahk:BAAANQADCggIFgABNQAECgYIBgAKAAAAAA==.Yazjani:BAAANQADCgIIAgAAAA==.Yazoth:BAAANQADCgEIAQAAAA==.Yazoura:BAAANQADCggIDwAAAA==.Yazwynn:BAAANQADCgcIDgAAAA==.',
Ye='Yezgraine:BAACNQAFFH8cAAIjAAgK+SHKAQCdAgAjAAgK+SHKAQCdAgA1AAQKfzkAAyMACgqHJScCAGUDACMACgqHJScCAGUDACIABAr3Gvd9AJ8AAAAA.',
Yo='Yookock:BAAANQADCggIDgAAAA==.',
Yz='Yzaak:BAAANQAECgYIBgAAAA==.',
Za='Zagyg:BAAANQADCgQIBAAAAA==.',
Ze='Zeddiccus:BAABNQAECn8jAAMZAAoK9BzjFQAgAQAOAAcKpRzJiACDAQAZAAQKohrjFQAgAQAAAA==.Zeva:BAABNQAECn8YAAIcAAYKCAdgMgDkAAAcAAYKCAdgMgDkAAAAAA==.',
Zo='Zonzmik:BAAANQADCggICgAAAA==.Zorrokiller:BAAANQADCgQIBAAAAA==.Zorvoth:BAAANQADCgQIBAABNQAECgUIDwAKAAAAAA==.',
Zu='Zurazaee:BAABNQAECn8kAAIGAAcKKyKWJgCiAgAGAAcKKyKWJgCiAgAAAA==.',
['Él']='Élle:BAAANQADCgcICAAAAA==.',
['Ér']='Éric:BAABNQAECn9GAAIlAAoKwgpuJQBDAQAlAAoKwgpuJQBDAQAAAA==.',
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
