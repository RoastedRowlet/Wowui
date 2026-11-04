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

local lookup = {'Paladin-Protection','Monk-Windwalker','Warrior-Arms','Paladin-Retribution','Monk-Brewmaster','Priest-Holy','Unknown-Unknown','DemonHunter-Devourer','Druid-Restoration','Shaman-Restoration','Hunter-Survival','Druid-Balance','Shaman-Elemental','Mage-Arcane','Warrior-Protection','Warrior-Fury','Rogue-Assassination','Paladin-Holy','DemonHunter-Vengeance','Druid-Feral','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Priest-Discipline','DemonHunter-Havoc','Evoker-Augmentation','Monk-Mistweaver','Hunter-Marksmanship','Shaman-Enhancement','Rogue-Subtlety','DeathKnight-Frost','DeathKnight-Blood','Rogue-Outlaw','Priest-Shadow','Druid-Guardian','Evoker-Devastation','Warlock-Affliction','Mage-Fire','Evoker-Preservation',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abysslicker:BAAANQADCggIFAAAAA==.',
Ac='Achooe:BAABNQAECn8kAAIBAAcK5wO1SADKAAABAAcK5wO1SADKAAAAAA==.',
Ad='Ado:BAABNQAECn8WAAICAAoK3A8UHQCDAQACAAoK3A8UHQCDAQAAAA==.Adrel:BAAANQADCgUIBQAAAA==.Adversity:BAACNQAFFH8JAAIDAAUKNhxhHQCiAAADAAUKNhxhHQCiAAA1AAQKfx4AAgMACgoZIisdALYCAAMACgoZIisdALYCAAAA.',
Ae='Aegeus:BAAANQADCggICQAAAA==.Aenil:BAAANQADCgMIAwAAAA==.Aevintz:BAAANQAECgcICgAAAA==.',
Ai='Aio:BAAANQADCgEIAQAAAA==.Aiolii:BAABNQAECn8YAAIEAAcKjRPjxwAHAQAEAAcKjRPjxwAHAQAAAA==.Aisling:BAAANQADCgQIBAAAAA==.',
Ak='Akiras:BAAANQADCgEIAgAAAA==.',
Al='Alanala:BAAANQABCgQIBAAAAA==.Alarielle:BAAANQAECgIIAgABNQAECgcIKAAFAM4gAA==.Alcestis:BAAANQADCgIIAgAAAA==.Aldea:BAAANQAECgUIEAABNQAECgkJJgAGAIobAA==.Alexeika:BAAANQAECgYIBgAAAA==.Aliseadyn:BAAANQAECgEIAQABNQAECgYIEQAHAAAAAA==.Alyndrya:BAABNQAECn9NAAIIAAoK9BEvFgDWAQAIAAoK9BEvFgDWAQAAAA==.',
Am='Amithralia:BAABNQAECn8tAAIJAAkKBCL9CQD1AgAJAAkKBCL9CQD1AgAAAA==.',
An='Anejo:BAAANQAECgQIBAAAAA==.Ankari:BAAANQADCgEIAQAAAA==.Ansdusk:BAAANQAECgQIBgABNQAECgcIDQAHAAAAAA==.Anzarna:BAAANQAECgIIAgABNQAECgUICgAHAAAAAA==.',
Ao='Aohikari:BAAANQAECgQICAABNQAFFAcIGgAKAIkYAA==.',
Ap='Apples:BAAANQADCgMIAwAAAA==.Aprigity:BAAANQAECggIEwAAAA==.',
Aq='Aquaten:BAABNQAECn8fAAILAAcKdRJoBwBeAQALAAcKdRJoBwBeAQAAAA==.',
Ar='Arashinigon:BAABNQAECn8jAAMMAAcKhAwWNAA1AQAMAAcKhAwWNAA1AQAJAAUKqBE6QQAdAQAAAA==.Arcafrost:BAAANQAECggIAQAAAA==.Arceus:BAAANQAECgUIEAAAAA==.Arick:BAABNQAECn8UAAIEAAcKkxS7zgB+AQAEAAcKkxS7zgB+AQAAAA==.Ark:BAABNQAECn9dAAMKAAoK+iYSAAAFBAAKAAoK+iYSAAAFBAANAAIKQiHgvQBhAAAAAA==.',
As='Astrofax:BAAANQAECgEIAQAAAA==.',
At='Atanker:BAAANQADCgMIBAAAAA==.',
Au='Aunn:BAAANQAECgYICgAAAA==.Aureia:BAABNQAECn8UAAMNAAkKOB24SQBQAgANAAkKOB24SQBQAgAKAAEKHA3pHAEzAAAAAA==.Auriea:BAAANQAECgQIBQABNQAECgkJFAANADgdAA==.',
Ax='Axon:BAABNQAECn8tAAIOAAkK4gnqhwBpAQAOAAkK4gnqhwBpAQAAAA==.',
Ba='Baaku:BAAANQAECgQIBgAAAA==.Baelhay:BAABNQAECn8gAAMPAAcK2AIUJgCYAAAPAAcK2AIUJgCYAAAQAAEKAABjOwAcAAAAAA==.Ballard:BAAANQADCgMIBQAAAA==.Barrelroll:BAAANQADCggIEAAAAA==.Bashon:BAABNQAECn9DAAMKAAoKJR12FADoAgAKAAoKJR12FADoAgANAAEKAAABWQEgAAAAAA==.Battlebot:BAAANQAECgUIDAAAAA==.',
Be='Beet:BAABNQAECn81AAICAAkKOyHZCgCMAgACAAkKOyHZCgCMAgAAAA==.Belgaron:BAAANQAECgcICwABNQAECgkJOQACALoXAA==.Belitha:BAABNQAECn8vAAIIAAoKOSH3DAAUAwAIAAoKOSH3DAAUAwAAAA==.Belmaris:BAABNQAECn8nAAIRAAcKexrdGQBAAQARAAcKexrdGQBAAQAAAA==.Benevolence:BAAANQAECgIIAgAAAA==.Beriana:BAAANQAECgQIBAABNQAECgoKHgASABARAA==.Betëlgeuse:BAAANQADCgUICQAAAA==.',
Bi='Bigcupcakes:BAAANQAECgUICgAAAA==.Bigdruid:BAAANQAECgIIAwABNQAECggIDgAHAAAAAA==.Bimbosuzi:BAAANQAECgUIDAAAAA==.Bingbing:BAAANQADCgUIBQAAAA==.Binghealing:BAAANQADCgEIAQAAAA==.',
Bl='Blasteyes:BAABNQAECn8pAAITAAkKXxuKCQBOAgATAAkKXxuKCQBOAgAAAA==.Bloomharvest:BAAANQADCgEIAQAAAA==.Bluegrass:BAABNQAECn9DAAIUAAoKzyHWAgD8AgAUAAoKzyHWAgD8AgAAAA==.',
Bo='Borc:BAAANQADCgcIHQAAAA==.Borik:BAABNQAECn8oAAIFAAcKziC+BQAAAgAFAAcKziC+BQAAAgAAAA==.Borknagar:BAAANQADCgcIFAAAAA==.',
Br='Brat:BAAANQADCgcIBwABNQAFFAcIIQAGAOAeAA==.Brighteye:BAAANQAECgQIBAAAAA==.Brindis:BAAANQAECgUICQAAAA==.Brisket:BAAANQADCggIHwABNQAECgEIAQAHAAAAAA==.Brutalicious:BAAANQADCgIIAgAAAA==.',
Bu='Bubblebut:BAABNQAECn8tAAISAAoKqB8HDgAuAwASAAoKqB8HDgAuAwAAAA==.Bubbs:BAAANQADCgQIBAABNQAECgoKPQACAAslAA==.Buckme:BAABNQAECn8pAAIVAAoK4RiyMwDRAgAVAAoK4RiyMwDRAgAAAA==.Bulova:BAAANQAECgUIBQAAAA==.Bunnygirl:BAAANQAECgIIAgABNQAFFAcIFAAWAKIiAA==.Busen:BAAANQADCggIHgAAAA==.',
By='Byungsoon:BAAANQADCgQIBAAAAA==.',
['Bà']='Bàal:BAABNQAECn8hAAMXAAoKqxJjUwBcAgAXAAoKqxJjUwBcAgAWAAEKNxFMcwA7AAAAAA==.',
Ca='Caiphage:BAAANQADCgcIBwAAAA==.Caladelm:BAABNQAECn8VAAIEAAYK9hOvogBHAQAEAAYK9hOvogBHAQAAAA==.Caralhan:BAABNQAECn8ZAAIYAAcKWgqnOgABAQAYAAcKWgqnOgABAQAAAA==.Castelo:BAAANQAECgUICQAAAA==.',
Ce='Cedra:BAABNQAECn9RAAMOAAoKDSSQGAByAwAOAAoK9iOQGAByAwAZAAIKnh9fHwCrAAAAAA==.Cegeo:BAABNQAECn8uAAIWAAoKZRACBACrAQAWAAoKZRACBACrAQAAAA==.Celari:BAAANQAECgEIAQAAAA==.Celinari:BAAANQADCgEIAQAAAA==.Centric:BAAANQADCgcIBwAAAA==.',
Ch='Cheepdeeps:BAABNQAECn9BAAIDAAoKgBsJKQB5AgADAAoKgBsJKQB5AgAAAA==.Chelea:BAAANQADCggIEQAAAA==.Chidora:BAAANQADCgcIBwAAAA==.Chocoworm:BAAANQADCgMIAgAAAA==.Chìpotle:BAAANQADCgYIDAAAAA==.',
Ci='Ciennajewel:BAABNQAECn8cAAIGAAcKJhvxQgD1AQAGAAcKJhvxQgD1AQAAAA==.Cirdle:BAABNQAECn8uAAIVAAcKLhPidgCHAQAVAAcKLhPidgCHAQAAAA==.',
Co='Cobalt:BAACNQAFFH8LAAIXAAQKLA7GFQDMAAAXAAQKLA7GFQDMAAA1AAQKfywAAhcACgqxHrwgAAEDABcACgqxHrwgAAEDAAE1AAUUBggKABcAexEA.Coolkid:BAAANQAECgMJBAAAAA==.Corntard:BAAANQADCggIHAAAAA==.',
Cr='Crazynlazy:BAABNQAECn8bAAINAAcKcgOy0QDwAAANAAcKcgOy0QDwAAAAAA==.Creamtastic:BAAANQAECgIIAgABNQAECgoKJwAKAGAbAA==.Crucifixea:BAABNQAECn8jAAMSAAkKEBRNSABGAgASAAgKoBVNSABGAgABAAkKfhOOLwBiAQABNQAFFAMIDAAGAF4YAA==.Cruxsader:BAAANQADCggIEAAAAA==.Crystyl:BAABNQAECn8cAAIZAAcK9A1hFAAPAQAZAAcK9A1hFAAPAQAAAA==.',
Ct='Ctesias:BAAANQADCgYIBwAAAA==.',
Cu='Cuddly:BAAANQAECgcIBwABNQAFFAgICgAaAKMRAA==.Curtle:BAAANQADCgEIAQAAAA==.Cute:BAAANQAECgYIBgABNQAFFAcIIQAGAOAeAA==.',
Cy='Cymoril:BAABNQAECn9CAAIDAAoK9RrJNABDAgADAAoK9RrJNABDAgAAAA==.Cythrawll:BAAANQADCgEIAQAAAA==.',
Da='Daamass:BAAANQAECgIIAgAAAA==.Dagyrr:BAAANQADCgEIAQAAAA==.Dalman:BAAANQAECgQIBgAAAA==.Dalmin:BAAANQADCggICAAAAA==.Dalov:BAABNQAECn8hAAIVAAoK1BoyMQBQAgAVAAoK1BoyMQBQAgAAAA==.Darkcarnival:BAABNQAECn8gAAIXAAcKqBawhgDVAQAXAAcKqBawhgDVAQAAAA==.Darkkill:BAAANQADCgMIAwABNQAECgoKKQAKAFQjAA==.Darthraider:BAABNQAECn8aAAIYAAYKlwUBTQCsAAAYAAYKlwUBTQCsAAAAAA==.Dasnotgood:BAAANQADCggIIgAAAA==.',
De='Deemon:BAABNQAECn8lAAMIAAoKQBb4MgCqAQAIAAcKtxj4MgCqAQAbAAUKJhKsUACtAAAAAA==.Delathatha:BAAANQADCgcICwAAAA==.Demiish:BAAANQADCgEIAgAAAA==.Demorjan:BAAANQADCggIFgAAAA==.Denard:BAAANQADCggIGAABNQAECgEIAQAHAAAAAA==.Denarias:BAAANQADCgUJBQABNQAECgUICgAHAAAAAA==.Denevien:BAAANQAECgcIEgAAAA==.Desdemona:BAABNQAECn8cAAIBAAcKERD0KgDqAAABAAcKERD0KgDqAAAAAA==.Dethiaris:BAAANQAECgQIEQAAAA==.',
Di='Diablojr:BAAANQAECgUIDAAAAA==.Dianimal:BAAANQAECgMIAwAAAA==.Distroya:BAAANQAECgQIBAAAAA==.',
Dk='Dkaiseremp:BAABNQAECn8kAAIcAAoK3AftCwCcAQAcAAoK3AftCwCcAQAAAA==.',
Do='Dobutsu:BAABNQAECn8fAAIMAAoKyhxkDQCuAgAMAAoKyhxkDQCuAgAAAA==.Dog:BAACNQAFFH8aAAIdAAUKyCaHAQApAgAdAAUKyCaHAQApAgA1AAQKf+gAAh0ACgoNJwEAAKUEAB0ACgoNJwEAAKUEAAAA.Doomace:BAABNQAECn9CAAMEAAoKnBTpZwDEAQAEAAoKnBTpZwDEAQABAAEKwgHpZQAaAAAAAA==.',
Dr='Draaka:BAAANQADCgYIDwAAAA==.Dragee:BAAANQAECgYIBwABNQAECgoKJQAIAEAWAA==.Dragon:BAABNQAECn8UAAMLAAoKrhf+AwAjAgALAAgK6hf+AwAjAgAVAAMKKRUO8ACRAAAAAA==.Driftyshaman:BAAANQAECgUIBgAAAA==.Droopy:BAAANQAECgcIDAAAAA==.Dræghoule:BAABNQAECn8aAAIYAAcKVwdHQQDdAAAYAAcKVwdHQQDdAAAAAA==.',
Du='Durnik:BAABNQAECn8oAAMVAAoKTB+XIACWAgAVAAoKTB+XIACWAgAeAAEKAADLkQAuAAABNQAECgkJOQACALoXAA==.',
Dw='Dworflundgrn:BAABNQAECn8mAAIfAAkKZgddFwBYAQAfAAkKZgddFwBYAQAAAA==.',
Dy='Dyamí:BAABNQAECn8oAAIOAAgKYxXEfgB+AQAOAAgKYxXEfgB+AQAAAA==.',
['Dá']='Dánte:BAAANQAECgYICQAAAA==.',
Eg='Eglosira:BAAANQADCgMIBgAAAA==.',
El='Elbuhero:BAABNQAECn8qAAMJAAgKJwezNgBmAQAJAAgKJwezNgBmAQAMAAUK+xX/XQBZAQAAAA==.Eldiablo:BAAANQAECgMIBwAAAA==.Electric:BAABNQAECn8UAAINAAUKxQjx1QDoAAANAAUKxQjx1QDoAAAAAA==.Elementstone:BAAANQAECgIIAgAAAA==.Elendish:BAAANQADCgIIAgAAAA==.Eleven:BAABNQAECn8yAAIOAAoKvwe4jwBYAQAOAAoKvwe4jwBYAQAAAA==.Eliasevo:BAAANQADCgcICQABNQAECgoKKQAKAFQjAA==.Elrythe:BAABNQAECn9RAAIVAAoKECH/FgDKAgAVAAoKECH/FgDKAgAAAA==.',
Er='Eraleth:BAAANQAECgUICwABNQAECgoKLwAIADkhAA==.',
Et='Etarnus:BAAANQAECgEIBQAAAA==.',
Fa='Faben:BAAANQADCgUIBQAAAA==.Faced:BAAANQAECgUICwAAAA==.Fatalii:BAABNQAECn8WAAMgAAgKmxQzSACTAQAgAAcKxRAzSACTAQARAAYKahRbLwDAAAAAAA==.',
Fe='Felebash:BAAANQAECgYIEwAAAA==.Felfireflux:BAAANQADCgYIDAAAAA==.Fellirane:BAAANQADCgUIBQAAAA==.',
Fi='Fistdaddy:BAAANQADCgYJDwAAAA==.',
Fl='Floofies:BAABNQAECn87AAIfAAoK+yRXAQCtAwAfAAoK+yRXAQCtAwAAAA==.Floofthulu:BAAANQAECgEIAQABNQAECgoKOwAfAPskAA==.Fluffalo:BAABNQAECn84AAINAAoKRSKBEQBiAwANAAoKRSKBEQBiAwABNQAECgoKOwAfAPskAA==.',
Fo='Foxypocket:BAABNQAECn8cAAIRAAcKNAnMJAD2AAARAAcKNAnMJAD2AAAAAA==.',
Fr='Fredrickk:BAAANQAECgYIEQAAAA==.',
Fu='Furcas:BAAANQAECgIIAgAAAA==.Furrglur:BAAANQAECgIIAgABNQAECgoKOwAfAPskAA==.Furrylight:BAAANQAECgIIAQABNQAECgoKMQAKABojAA==.Furryphase:BAABNQAECn8xAAMKAAoKGiN1CAB0AwAKAAoKGiN1CAB0AwANAAMKlQXQxgBTAAAAAA==.Fuzzington:BAAANQAECgcIDAABNQAECgoKOwAfAPskAA==.Fuzzydunlop:BAAANQAECgIIAgAAAA==.',
Fz='Fzoul:BAAANQAECgMIAwAAAA==.',
Ga='Gaith:BAAANQAECgYIBgAAAA==.Galnier:BAABNQAECn8aAAIEAAoKpBDrZgDGAQAEAAoKpBDrZgDGAQAAAA==.Gandoomi:BAAANQABCgIIAgAAAA==.Gauldangit:BAAANQAECgEIAgAAAA==.',
Ge='Gex:BAAANQADCgEIAQAAAA==.',
Gh='Ghosted:BAAANQAECgMIBQAAAA==.',
Gl='Glaecia:BAAANQADCgEIAQAAAA==.Glaur:BAABNQAECn8xAAIKAAkKqhnuKABWAgAKAAkKqhnuKABWAgAAAA==.',
Go='Goatjira:BAAANQAECgMIBAAAAA==.',
Gr='Greathammer:BAAANQAECgEIAQAAAA==.Grimgor:BAAANQAECgQIBAABNQAECgcIHQAhAKkdAA==.Gripisrdy:BAABNQAECn8gAAQYAAcKoh4yOgA6AgAYAAYKjyAyOgA6AgAhAAcK2hjWSgCPAQAiAAIK2w+lqACAAAAAAA==.Grippindeez:BAABNQAECn8tAAMhAAkKmg9wOgB3AQAhAAkK1wxwOgB3AQAiAAIKNBxKtgBbAAAAAA==.',
Gu='Gunslingr:BAABNQAECn82AAMjAAoKXSEuAwAIAwAjAAoKECAuAwAIAwAgAAcKaxdaOQDUAQAAAA==.',
Gw='Gweetow:BAAANQAECgEIAQAAAA==.',
Gy='Gymsharklyfe:BAAANQAECggIBgAAAA==.',
Ha='Hairyjolene:BAAANQADCggIFQAAAA==.Handsome:BAABNQAECn8xAAMeAAoKkB3XCgBrAgAeAAoKYxzXCgBrAgAVAAcKFBfMxwByAQABNQAFFAMIDAAGAF4YAA==.',
He='Headpats:BAACNQAFFH8KAAISAAUKgxSlCQB/AQASAAUKgxSlCQB/AQA1AAQKfx8AAhIACgpsH/YQAAwDABIACgpsH/YQAAwDAAE1AAUUCAgKABoAoxEA.Hearthisrdy:BAAANQAECgYIBgAAAA==.Hel:BAAANQADCgUIBQAAAA==.Helgrim:BAAANQADCgUIBQAAAA==.Helmshammer:BAAANQAECgYIBgAAAA==.Hexwhisper:BAAANQAECgQIBAAAAA==.Heycarlos:BAABNQAECn9AAAMhAAkKkCKTBgB5AwAhAAkKkCKTBgB5AwAYAAIKrwfJzQBRAAAAAA==.',
Hi='Hikaripala:BAAANQADCgYIBgABNQAFFAcIGgAKAIkYAA==.Hikarishaman:BAACNQAFFH8aAAMKAAcKiRiZCgClAQAKAAUKDhaZCgClAQANAAQKmhuMEgBGAQA1AAQKfzkAAw0ACgrPHDsdAFoCAA0ACgrPHDsdAFoCAAoACgpNHChPACgCAAAA.Hime:BAABNQAECn8jAAIEAAcKVAil9wAuAQAEAAcKVAil9wAuAQAAAA==.',
Ho='Holyblimblam:BAAANQAECgMIBwAAAA==.Honeypieheal:BAAANQAECgMIBAAAAA==.Horabad:BAAANQAECgYIDAAAAA==.Hosemachine:BAABNQAECn8ZAAIYAAgKWhkLOgA7AgAYAAgKWhkLOgA7AgAAAA==.',
Hu='Hulque:BAAANQADCgYIBgAAAA==.Humper:BAAANQADCgEIAQAAAA==.',
['Hè']='Hèri:BAAANQAECgMIAwAAAA==.Hèrifire:BAAANQAECgYIEwAAAA==.',
Ic='Icyshadow:BAABNQAECn8eAAMkAAcKZwzHKAACAQAkAAcKZwzHKAACAQAGAAEKqxA94AA0AAAAAA==.',
Id='Idouna:BAAANQADCgEIAQAAAA==.',
Ih='Ihalo:BAAANQAECgYIEAAAAA==.',
Il='Illinesh:BAAANQADCgYICwAAAA==.',
Ir='Ironpaw:BAAANQAECgUJDAAAAA==.',
It='Ithildur:BAAANQADCgQIBAAAAA==.',
Ja='Jadde:BAAANQADCgYIBwAAAA==.Jadienne:BAAANQAECgQIDAAAAA==.Jameson:BAAANQAECgUIDAAAAA==.Jamiel:BAAANQADCgEIAQAAAA==.Jangewinde:BAAANQAECgUIEQAAAA==.Jasmind:BAABNQAECn8dAAMJAAkKxQtAJwBrAQAJAAkKxQtAJwBrAQAMAAEKAABjxQAdAAAAAA==.Jaywu:BAAANQADCggICAAAAA==.',
Je='Jemi:BAAANQAECgEIAgAAAA==.',
Ji='Jiwà:BAABNQAECn83AAMKAAkKARQuVgAPAgAKAAkKARQuVgAPAgANAAcKnwKexgAFAQAAAA==.',
Jo='Joecool:BAAANQAECgcIBwAAAA==.Johnnyboy:BAAANQADCgEIAQAAAA==.Joshjb:BAAANQAECgIIAgAAAA==.Joss:BAAANQADCgIIAgAAAA==.',
Ka='Kaguro:BAABNQAECn80AAMRAAoK5BLoDwCnAQAjAAkK8w5WCgDWAQARAAkKKRLoDwCnAQAAAA==.Kaibab:BAAANQADCgEIAQAAAA==.Kakwaa:BAAANQAECgIJAwAAAA==.Kalix:BAAANQABCgUICAAAAA==.Kaliyah:BAAANQAECgYIEAAAAA==.Kattrin:BAAANQAECgEIAQAAAA==.Kayleebear:BAAANQADCgQIBQAAAA==.',
Ke='Kerplaa:BAAANQADCgMIAwAAAA==.Keyadistor:BAABNQAECn8dAAQhAAcKqR3dPgDPAQAhAAcK2hzdPgDPAQAiAAMKCx4iXwCiAAAYAAEKAACz5gAuAAAAAA==.',
Kh='Khazabrew:BAABNQAECn8vAAIFAAkKoB7ZBgDXAgAFAAkKoB7ZBgDXAgAAAA==.',
Ki='Kiamara:BAABNQAECn8cAAIXAAcKuATQqADOAAAXAAcKuATQqADOAAAAAA==.Kinderlin:BAABNQAECn8+AAIEAAoKkxiBRQAmAgAEAAoKkxiBRQAmAgAAAA==.Kirbun:BAABNQAECn8xAAIOAAkK/xyJZwCvAgAOAAkK/xyJZwCvAgAAAA==.Kizchaos:BAAANQAECgMIBAAAAA==.',
Ko='Komurash:BAABNQAECn8tAAMDAAoKfxfnPAAiAgADAAoKfxfnPAAiAgAPAAIKRgM8PABVAAAAAA==.Korstruck:BAAANQAECgUIBQAAAA==.Kotys:BAAANQADCgUIBQAAAA==.',
Kr='Kravvelocity:BAAANQAECggIDwAAAA==.',
Ku='Kulika:BAAANQADCgEIAQAAAA==.Kungbrew:BAAANQAECgEIAQABNQAECgcIHgAkAGcMAA==.',
La='Lancaban:BAAANQADCggIHgAAAQ==.Larry:BAAANQADCgEIAQAAAA==.Lastiri:BAAANQABCgIIAgAAAA==.',
Le='Lethalarrow:BAABNQAECn8eAAIVAAgKJA2TjgDsAQAVAAgKJA2TjgDsAQAAAA==.Lethalpally:BAAANQADCggIDAAAAA==.Lewismr:BAAANQADCgUIDQABNQAECgkKMwAEAIUVAA==.Lewisr:BAABNQAECn8zAAIEAAkKhRXObwCwAQAEAAkKhRXObwCwAQAAAA==.',
Li='Ligahoo:BAAANQADCggJEgAAAA==.Lilysweets:BAAANQADCgcICgAAAA==.',
Lo='Loralynn:BAAANQAECgQIBQABNQAFFAIIBQAEALkDAA==.Lorianne:BAABNQAECn8aAAMNAAoK0wlrUgBWAQANAAkKpAprUgBWAQAKAAQKoguvrgCTAAABNQAFFAIIBQAEALkDAA==.Lorryanne:BAACNQAFFH8FAAIEAAIKuQM7IgBuAAAEAAIKuQM7IgBuAAA1AAQKf00AAxIACgqgGFE7AHcCABIACgqgGFE7AHcCAAQACgqDDvBqALwBAAAA.',
Lu='Lucianas:BAAANQAECgYIDAAAAA==.Lunacat:BAAANQAECgQICQABNQADCgYJDwAHAAAAAA==.Luxdaddy:BAABNQAECn8VAAIGAAgKsRfUSgDTAQAGAAgKsRfUSgDTAQABNQADCgYJDwAHAAAAAA==.',
Ly='Lysi:BAABNQAECn8YAAIVAAcKzBJkhwBhAQAVAAcKzBJkhwBhAQAAAA==.',
Ma='Madaea:BAABNQAECn8oAAIdAAoKoRqGEgBUAgAdAAoKoRqGEgBUAgAAAA==.Madameuyen:BAAANQAECgQIBwAAAA==.Madlyn:BAAANQAECgQIDwAAAA==.Magepuppy:BAABNQAECn8cAAMOAAgK+hQ/ygDxAQAOAAcKTxU/ygDxAQAZAAEKTxM9QABEAAABNQAECgoKQgABALsdAA==.Makavali:BAABNQAECn8xAAMJAAoKiBfbDwCDAgAJAAkKVBnbDwCDAgAMAAkKTBEyNQAuAQAAAA==.Makavalii:BAABNQAECn9TAAMEAAkK9xUzeAA8AgAEAAkK9xUzeAA8AgASAAkKCxM/UAArAgABNQAECgoKMQAJAIgXAA==.Malanimus:BAAANQAECgUICgAAAA==.Malevola:BAAANQAECgEIAQAAAA==.Malholis:BAAANQAECgUICwAAAA==.Mandorallen:BAAANQAECgQIBAABNQAECgkJOQACALoXAA==.Matagi:BAABNQAECn84AAIVAAkKNRbvVwBrAgAVAAkKNRbvVwBrAgAAAA==.Mate:BAAANQADCgUICQABNQAECgEIAQAHAAAAAA==.',
Me='Meatloaf:BAAANQADCgQIBQAAAA==.Meeseks:BAABNQAECn83AAIYAAoKQxsJFgASAgAYAAoKQxsJFgASAgAAAA==.Megabyte:BAAANQAECgQJBAAAAA==.Melbeast:BAAANQAECgcIEQAAAA==.Melorea:BAAANQAECgIIAwAAAA==.Merdin:BAABNQAECn8hAAIOAAcKGg79hgBrAQAOAAcKGg79hgBrAQAAAA==.Methmartion:BAABNQAECn8gAAIWAAcKdwkCEgCuAAAWAAcKdwkCEgCuAAAAAA==.',
Mi='Mignon:BAAANQAECgEIAQAAAA==.Milougheh:BAAANQAECggIAgAAAA==.Minós:BAAANQADCgUIBgAAAA==.Mish:BAAANQAECgQIBAAAAA==.Missiah:BAABNQAECn8uAAIBAAkKXAcWJQATAQABAAkKXAcWJQATAQAAAA==.',
Mo='Molfise:BAAANQADCgYIBgAAAA==.Monna:BAAANQADCgEIAQAAAA==.Moonfell:BAABNQAECn8tAAIGAAkKIRLzZQBxAQAGAAkKIRLzZQBxAQAAAA==.Moonlilly:BAABNQAECn8cAAIPAAcK7AOXIgCxAAAPAAcK7AOXIgCxAAAAAA==.Mopp:BAAANQAECgQIEgAAAA==.Morganthe:BAAANQADCggIEgAAAA==.Mornîngstar:BAAANQAECggIEwAAAA==.',
Mu='Mugatoo:BAAANQAECggIBAAAAA==.',
Mx='Mxtemlen:BAAANQAECgQIBAABNQAECggIHAASAHcSAA==.',
My='Mylilhunter:BAABNQAECn8bAAIVAAcK5wZivAD1AAAVAAcK5wZivAD1AAAAAA==.Myrtheli:BAAANQADCggICQABNQAECgkJJgAGAIobAA==.Mysticx:BAAANQAECggICAAAAA==.',
Na='Nachtelf:BAABNQAECn9GAAIVAAoKER0UKQBvAgAVAAoKER0UKQBvAgAAAA==.Nagan:BAAANQAECgYIDAAAAA==.Natadawn:BAAANQADCgYIBgAAAA==.Natalone:BAABNQAECn9DAAIZAAoKLST1AQBhAwAZAAoKLST1AQBhAwAAAA==.Nathel:BAABNQAECn8eAAMOAAcKZgMX6QCzAAAOAAcKcgIX6QCzAAAZAAYKRANbLABZAAAAAA==.',
Ne='Nerisa:BAAANQADCgUIBQAAAA==.',
Ni='Nirra:BAAANQAECgMIBQAAAA==.',
No='Noctis:BAAANQAECgYICwAAAA==.Notoriginal:BAABNQAECn8vAAIYAAoK+g/UGQDoAQAYAAoK+g/UGQDoAQAAAA==.Novatron:BAABNQAECn8gAAQfAAcKqAUJIQDXAAAfAAcKvQMJIQDXAAANAAQKbwaIqwB9AAAKAAMK7wCRFwE8AAAAAA==.',
Nu='Nuance:BAAANQAECgIIAgAAAA==.Nuked:BAABNQAECn8UAAIOAAYKuxddAAGNAQAOAAYKuxddAAGNAQAAAA==.',
['Né']='Néith:BAAANQADCgQIBQAAAA==.',
Od='Odor:BAAANQAECgQIBwAAAA==.',
Og='Ograskygazer:BAABNQAECn8bAAIJAAcKBAUSPgDUAAAJAAcKBAUSPgDUAAAAAA==.',
Oi='Oieg:BAAANQADCgEIAQAAAA==.',
Om='Omee:BAABNQAECn8cAAMIAAgKVw6gKgAKAQAIAAcKfg2gKgAKAQAbAAUKYA7mTwCwAAAAAA==.Omegaone:BAAANQADCgcIBwAAAA==.',
On='Oneil:BAAANQADCgMJAwAAAA==.Onlyshrimps:BAAANQAECgYIBgAAAA==.',
Or='Oralena:BAABNQAECn8cAAIVAAcK3AOWzQDSAAAVAAcK3AOWzQDSAAAAAA==.Orioncheats:BAABNQAECn9BAAMYAAkKnhZCOABEAgAYAAkKahZCOABEAgAiAAgKlhOBLAB5AQAAAA==.',
Ow='Owo:BAAANQAECgEIAQAAAA==.',
Ox='Oxygën:BAABNQAECn8mAAIOAAgK/hM4fwB9AQAOAAgK/hM4fwB9AQAAAA==.',
Pa='Palomita:BAAANQADCgIIAwAAAA==.',
Pe='Ped:BAAANQAECgEIAQABNQAECgkJJgAGAIobAA==.Pedaramun:BAAANQAECgcICAABNQAECgkJJgAGAIobAA==.Pedarias:BAABNQAECn8mAAMGAAkKiht5MQBHAgAGAAkKiht5MQBHAgAkAAEKAABTlgANAAAAAA==.Peon:BAAANQAECgYIDwAAAA==.Perstephanie:BAAANQADCgQIBgAAAA==.',
Ph='Pharune:BAABNQAECn8mAAIlAAcK2Q0MKABWAQAlAAcK2Q0MKABWAQAAAA==.Phredrick:BAAANQAECgYICwAAAA==.',
Pi='Piemanninty:BAAANQAECgIJBQAAAA==.',
Pl='Plandemic:BAAANQAECgEIAQAAAA==.',
Po='Pockithealz:BAAANQADCgQIBQABNQAECggIFgAgAJsUAA==.Pointnshoot:BAAANQADCgQIBQABNQAECgcIJwAHAAAAAA==.Pokerface:BAAANQAECgYIDAAAAA==.Ponky:BAAANQAECgIIAgABNQAECgoKNAASAHgbAA==.Poongwoon:BAAANQADCgMIAwAAAA==.Pounces:BAACNQAFFH8GAAIJAAQKBxKhCgApAQAJAAQKBxKhCgApAQA1AAQKfxYAAgkACQplHZoXAA0CAAkACQplHZoXAA0CAAE1AAUUCAgKABoAoxEA.',
Pr='Precious:BAAANQAECgYIEAABNQAFFAcIIQAGAOAeAA==.',
Pu='Puppet:BAAANQAECgcIEAABNQAFFAcIIQAGAOAeAA==.',
Py='Pymura:BAAANQADCgQIBAAAAA==.',
['Pí']='Píongá:BAAANQADCgEIAgAAAA==.',
Qe='Qee:BAAANQAECgEIAQABNQAECgoKJQAIAEAWAA==.',
Qu='Quattro:BAABNQAECn8lAAImAAkKkg62CgCDAQAmAAkKkg62CgCDAQAAAA==.',
Ra='Racecar:BAAANQAECgUIDQAAAA==.Raezil:BAAANQAECgQICQABNQAECgoKIQAXAKsSAA==.Raivyn:BAABNQAECn85AAICAAkKuhdMEgAKAgACAAkKuhdMEgAKAgAAAA==.Rathmora:BAAANQADCggIJQAAAA==.Raylaira:BAAANQAECgUICgABNQAECgUICgAHAAAAAA==.Raziel:BAAANQADCgYIBwAAAA==.',
Re='Redbeard:BAAANQAECgUIBgAAAA==.Remnants:BAAANQADCggIEwAAAA==.Renard:BAABNQAECn9GAAIJAAoKAiRjAwCSAwAJAAoKAiRjAwCSAwAAAA==.Reposado:BAABNQAECn8WAAIhAAcKtBf5MQCjAQAhAAcKtBf5MQCjAQAAAA==.Revelare:BAABNQAECn8gAAIKAAcKYBd8ZwDWAQAKAAcKYBd8ZwDWAQAAAA==.Rexbie:BAAANQAECgcICwAAAA==.',
Rh='Rhylee:BAAANQAECgUIDgAAAA==.',
Ri='Rianne:BAAANQADCgUIBQAAAA==.Riptidepod:BAABNQAECn8nAAMKAAoKYBvbJgDJAgAKAAoKYBvbJgDJAgANAAEKAACrRgErAAAAAA==.',
Rm='Rmplstiltskn:BAAANQADCgUICQAAAA==.',
Ro='Robberttrest:BAABNQAECn8cAAIVAAUKWwl87QAmAQAVAAUKWwl87QAmAQAAAA==.Rockyhunter:BAAANQAECggIDgABNQAECgoKOwAiAP4dAA==.Rockyhunterr:BAABNQAECn87AAIiAAoK/h3zEQAdAwAiAAoK/h3zEQAdAwAAAA==.Rockymage:BAAANQADCgYIBgAAAA==.Rockyrogue:BAAANQADCggICAABNQAECgoKOwAiAP4dAA==.Rockywarlock:BAAANQAECgEIAQABNQAECgoKOwAiAP4dAA==.Rockywarrior:BAAANQADCgYICgABNQAECgoKOwAiAP4dAA==.Rodney:BAAANQADCgEIAQAAAA==.Ronaeminnda:BAAANQADCgEIAQAAAA==.Rooth:BAABNQAECn8UAAImAAYKEAz9DwAKAQAmAAYKEAz9DwAKAQAAAA==.Roryn:BAABNQAECn9PAAIEAAoK3iWjBgBVAwAEAAoK3iWjBgBVAwAAAA==.Rottencheeze:BAAANQADCgEIAQABNQAECgoKKgAVAE0PAA==.',
Ru='Rubï:BAABNQAECn8kAAIQAAoKsiKeAQASAwAQAAoKsiKeAQASAwAAAA==.Ruggburn:BAAANQAECgEIAQABNQAECgoKKwAZAE0bAA==.Rugiaas:BAACNQAFFH8pAAISAAcKXSHlAQCnAgASAAcKXSHlAQCnAgA1AAQKf0AAAxIACgofJc4EAKoDABIACgofJc4EAKoDAAQABArUGM35ACsBAAAA.Rugian:BAAANQAECgQIBQABNQAFFAcIKQASAF0hAA==.Rugis:BAAANQAECgMIBQABNQAFFAcIKQASAF0hAA==.',
Ry='Ryuka:BAAANQAECgcIEQAAAA==.',
['Râ']='Râezil:BAAANQADCgIIAwABNQAECgoKIQAXAKsSAA==.',
Sa='Sabriiel:BAAANQADCgIIBAABNQAECgQIBgAHAAAAAA==.Samyria:BAAANQAECgQICgAAAA==.Sapphiriana:BAAANQADCgIIAgABNQAECgYIFAAmABAMAA==.Saprates:BAAANQADCgMIAwAAAA==.Satyaru:BAABNQAECn8uAAQFAAkKhBHsEQDHAQAFAAgKag/sEQDHAQAdAAgK/QzdFwBGAQACAAEKAAAIcwAmAAAAAA==.Saucy:BAABNQAECn8dAAINAAcKlxXQYgAjAQANAAcKlxXQYgAjAQAAAA==.',
Sc='Scratchum:BAAANQADCgEIAQAAAA==.',
Se='Sedona:BAABNQAECn8VAAInAAcKJgPKFACoAAAnAAcKJgPKFACoAAAAAA==.Selarra:BAABNQAECn8jAAIGAAkKzw5cfACkAQAGAAkKzw5cfACkAQAAAA==.Seric:BAABNQAECn8uAAMPAAkKtg4pGwCHAQAPAAkKtg4pGwCHAQADAAgKcAaylAAgAQAAAA==.Sethuriel:BAAANQAECggIDgAAAA==.',
Sh='Shaatixaa:BAAANQADCgEIAQAAAA==.Shadowdancèr:BAAANQADCgEJAQAAAA==.Shadowlocke:BAAANQADCgMIAwAAAA==.Shalzith:BAAANQAECgEIAQAAAA==.Shenandoah:BAAANQADCgYIBwAAAA==.Shockadelica:BAAANQADCgYIBgAAAA==.',
Si='Siath:BAAANQADCgEIAQABNQAECgkJJgAGAIobAA==.Silentwrath:BAAANQAECgEIAQABNQAECgoKNgAlAH4TAA==.Sitheretta:BAAANQAECgUICgAAAA==.',
Sk='Skoto:BAAANQAECggIDgAAAA==.Skyböx:BAAANQADCgEIAQAAAA==.',
Sm='Smartfood:BAABNQAECn8aAAIDAAkK0wx7iQA6AQADAAkK0wx7iQA6AQAAAA==.Smoochybooty:BAAANQAECgMIBAAAAA==.',
Sn='Snuggy:BAAANQAECgIIAgAAAA==.',
So='Solnar:BAABNQAECn8cAAMSAAgKdxJZYAD3AQASAAgKdxJZYAD3AQAEAAQK8QyVRwGuAAAAAA==.Soupspoon:BAAANQADCgEIAwAAAA==.',
Sp='Specter:BAAANQAECggICAAAAA==.Splashdaddy:BAACNQAFFH8NAAIKAAcKjQ/ICQCzAQAKAAcKjQ/ICQCzAQA1AAQKf0QAAgoACgrxIqYaAAUDAAoACgrxIqYaAAUDAAE1AAMKBgkPAAcAAAAA.Spoiled:BAAANQADCggICQABNQAFFAcIIQAGAOAeAA==.',
Sr='Srìracha:BAAANQAECggIDAAAAA==.',
St='Staks:BAAANQADCgcIFAAAAA==.Starii:BAABNQAECn8cAAIKAAcKXwUThwDuAAAKAAcKXwUThwDuAAAAAA==.Stormieskye:BAABNQAECn88AAINAAkKKRWYNgDCAQANAAkKKRWYNgDCAQAAAA==.Striga:BAAANQADCgcICAAAAA==.',
Su='Summonme:BAAANQAECgIIAgAAAA==.Suzume:BAAANQAECgQIBAABNQAFFAcIGgAKAIkYAA==.',
Sw='Sweetshot:BAAANQADCgEIAQAAAA==.',
Sy='Sylvancura:BAAANQADCgQIBAAAAA==.Synestra:BAABNQAECn8WAAIlAAYKihpmIgCEAQAlAAYKihpmIgCEAQAAAA==.',
Ta='Taea:BAABNQAECn8VAAIKAAYKNh7aRwDBAQAKAAYKNh7aRwDBAQAAAA==.Taeus:BAABNQAECn85AAQZAAoKxiDiBgCLAgAZAAoKNiDiBgCLAgAOAAkKlhvf0wDfAQAoAAEKPw9zDAA/AAAAAA==.Taintedkoma:BAAANQAECgMIBAABNQAECgcIIAAWAHcJAA==.Talagark:BAAANQADCgYIBwAAAA==.Talanat:BAAANQADCgIIAwAAAA==.Taurenator:BAABNQAECn8eAAIPAAoKQyCkBgD5AgAPAAoKQyCkBgD5AgAAAA==.',
Te='Tearinass:BAAANQAECgUIBQAAAA==.Teheez:BAAANQADCgIIAgAAAA==.Tenthrol:BAAANQAECgEIAQAAAA==.Teranidas:BAAANQAECgUICgAAAA==.Teratrendera:BAABNQAECn8eAAIpAAcKOiEMCACdAgApAAcKOiEMCACdAgAAAA==.Teron:BAAANQAECgMJBAAAAA==.Tesx:BAAANQAECgIIAwAAAA==.',
Th='Thavis:BAABNQAECn8vAAMWAAgKSBXIDQDNAAAXAAgKthGJXACFAQAWAAQK7xPIDQDNAAAAAA==.Thdoris:BAAANQADCgQIBAAAAA==.Thetimelord:BAAANQAECgMIBQAAAA==.Thewarrior:BAABNQAECn8XAAMQAAcK8hu3DgBPAQAQAAYK2Bu3DgBPAQADAAcK3hW6lwAZAQAAAA==.Thrask:BAAANQADCgQIBAAAAA==.',
Ti='Ticktac:BAAANQAECgcIBgAAAA==.Tik:BAAANQADCggIEAAAAA==.Tilted:BAABNQAECn8fAAIEAAoKbRc4kwD9AQAEAAoKbRc4kwD9AQAAAA==.Tiltêd:BAAANQAECgUICQAAAA==.Tinkr:BAABNQAECn80AAIiAAoK2hiGFwAiAgAiAAoK2hiGFwAiAgAAAA==.',
To='Tobi:BAAANQADCgYIBwAAAA==.Toewzix:BAAANQAECgQIBQAAAA==.Tom:BAAANQAECgUICAABNQAECgoKIQAXAKsSAA==.Torrey:BAABNQAECn8pAAMTAAkKSAt0DwAaAQAIAAkKngmuNACdAQATAAkKmwl0DwAaAQAAAA==.Totemsareus:BAABNQAECn8pAAMKAAoKVCMgCACAAwAKAAoKVCMgCACAAwANAAIKigdZFQFjAAAAAA==.Toxx:BAAANQAECgcIBgABNQAECggIHAAIAFcOAA==.',
Tr='Tradd:BAACNQAFFH8MAAIGAAMKXhgUHQDFAAAGAAMKXhgUHQDFAAA1AAQKfz8ABAYACgojISMOAFMDAAYACgojISMOAFMDABoABwrDDr4MAGwBACQACQp5DO8jACkBAAAA.Trallor:BAABNQAECn8nAAMDAAkKQgwVvgCBAQADAAgKWg0VvgCBAQAPAAMKJgmtLwBeAAAAAA==.Tress:BAAANQAECgEIAQAAAA==.Trhall:BAAANQAECgQIBwAAAA==.Tristyana:BAABNQAECn9BAAIVAAoKqBKCSAADAgAVAAoKqBKCSAADAgAAAA==.',
Ts='Tsiddahn:BAABNQAECn8sAAIGAAkK9RqmKADHAgAGAAkK9RqmKADHAgAAAA==.Tsunâde:BAABNQAECn89AAMCAAoKCyWrAgBGAwACAAoKCyWrAgBGAwAdAAcKjhFnHgDzAAAAAA==.',
Tw='Twanu:BAAANQAECgQIBAAAAA==.',
Ty='Tylurien:BAABNQAECn8mAAISAAcKSSbNGQAQAwASAAcKSSbNGQAQAwAAAA==.Tyrael:BAABNQAECn8oAAMBAAkK7RJjJAAYAQABAAgKsg9jJAAYAQASAAEKYwIE+AATAAABNQADCgMIBgAHAAAAAA==.',
Uk='Ukon:BAAANQADCgYIBgAAAA==.',
Ul='Ulangi:BAAANQAECgEIAQAAAA==.',
Un='Un:BAAANQADCgcIAgAAAA==.',
Ur='Urbanprey:BAABNQAECn8mAAIWAAkKFQv5BwAkAQAWAAkKFQv5BwAkAQAAAA==.',
Va='Valenhi:BAAANQAECgIIAgAAAA==.Valkoinen:BAAANQADCgMIBgAAAA==.Valora:BAABNQAECn9AAAIGAAoKjh4XFwDyAgAGAAoKjh4XFwDyAgAAAA==.Valoria:BAAANQAECgIIAwAAAA==.Vanille:BAABNQAECn8bAAIJAAcKRwT0RQCuAAAJAAcKRwT0RQCuAAAAAA==.Vargen:BAAANQAECgUICAAAAA==.Varonika:BAAANQAECgUIBwAAAA==.Vayla:BAABNQAECn87AAIPAAkKfB0ZBgBuAgAPAAkKfB0ZBgBuAgAAAA==.',
Vb='Vbv:BAAANQAECgcICwAAAA==.',
Ve='Veal:BAAANQADCgYIBgABNQAECgkJIwAGAM8OAA==.Vedik:BAAANQAECgYIEAAAAA==.Vegasduc:BAAANQADCgQIBAAAAA==.Vegasducks:BAABNQAECn8yAAIOAAoKgwg1bACqAQAOAAoKgwg1bACqAQAAAA==.Velara:BAAANQADCgYIDQAAAA==.Veld:BAABNQAECn8VAAIIAAgKYg+rMwClAQAIAAgKYg+rMwClAQAAAA==.Velithara:BAAANQADCgYJBgAAAA==.Veralyn:BAAANQADCgUICgAAAA==.',
Vi='Violet:BAABNQAECn8eAAIEAAYKpwVUDAEKAQAEAAYKpwVUDAEKAQAAAA==.',
Vy='Vyla:BAAANQADCgEIAQAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUIBQAAAA==.',
Wa='Wardancer:BAAANQAECgUIBgAAAA==.Warfise:BAAANQAECgYIEwAAAA==.Warspriest:BAABNQAECn8gAAIkAAcKcRzCHgBIAgAkAAcKcRzCHgBIAgAAAA==.Warwizard:BAABNQAECn9WAAISAAoKlyVfAQAeBAASAAoKlyVfAQAeBAAAAA==.',
Wd='Wdemperor:BAABNQAECn8eAAQPAAoKoASTMACxAAAPAAkKXAOTMACxAAADAAMKzgNrCQE8AAAQAAMKvQYhNwAAAAABNQAECgoKJAAcANwHAA==.',
We='Webin:BAAANQAECgEIAQAAAA==.',
Wh='Whispaknight:BAAANQAECgEIAQABNQAECgEIAQAHAAAAAA==.Whisperwiind:BAAANQADCgcICAABNQAECgEIAQAHAAAAAA==.Whisperz:BAAANQADCgYIBgABNQAECgEIAQAHAAAAAA==.',
Wi='Wickedywaque:BAAANQADCgUIBgAAAA==.Wickerchickn:BAAANQAECgQJBwAAAA==.Wiisper:BAAANQAECgEIAQAAAA==.Wilshammy:BAAANQAECgEIAQAAAA==.Winterhunter:BAAANQADCgEIAgAAAA==.',
Wo='Wonkyponky:BAABNQAECn80AAISAAoKeBvdJwDJAgASAAoKeBvdJwDJAgAAAA==.',
Wr='Wrathbarrage:BAAANQAECgYIEQABNQAECgoKNgAlAH4TAA==.Wrathchoi:BAAANQAECgYIBwAAAA==.Wrathstorm:BAABNQAECn82AAMlAAoKfhM/GgB7AQAlAAoKWRM/GgB7AQAUAAEKKQpZPgAvAAAAAA==.',
Ya='Yazahk:BAAANQAECgIIAgABNQAECgYICgAHAAAAAA==.Yazjani:BAAANQADCgIIAwAAAA==.Yazoth:BAAANQADCgEIAQAAAA==.Yazoura:BAAANQADCggIEAAAAA==.Yazwynn:BAAANQADCgcIDwAAAA==.',
Ye='Yezgraine:BAACNQAFFH8aAAIiAAcK+iDKAQCdAgAiAAcK+iDKAQCdAgA1AAQKfzYAAyIACgqHJb8BAGoDACIACgqHJb8BAGoDACEAAQrdHM6dAFYAAAAA.',
Yo='Yookock:BAAANQADCggIDgAAAA==.',
Yz='Yzaak:BAAANQAECgYICgAAAA==.',
Za='Zagyg:BAAANQADCgQIBAAAAA==.',
Ze='Zeddiccus:BAABNQAECn8jAAMZAAoK9ByPEgAmAQAOAAcKpRwLeQCKAQAZAAQKohqPEgAmAQAAAA==.Zeva:BAAANQAECgYIEwAAAA==.',
Zo='Zonzmik:BAAANQADCggIDAAAAA==.Zorrokiller:BAAANQADCgQIBAAAAA==.Zorvoth:BAAANQADCgQIBAABNQAECgUICgAHAAAAAA==.',
Zu='Zurazaee:BAABNQAECn8gAAIGAAcKKyLPHwCuAgAGAAcKKyLPHwCuAgAAAA==.',
['Él']='Élle:BAAANQADCgcICAAAAA==.',
['Ér']='Éric:BAABNQAECn9BAAIlAAoKwgqRIABFAQAlAAoKwgqRIABFAQAAAA==.',
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
