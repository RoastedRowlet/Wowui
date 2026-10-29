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

local lookup = {'Unknown-Unknown','Rogue-Outlaw','Mage-Arcane','Druid-Guardian','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Holy','Druid-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','Priest-Holy','Priest-Discipline','Priest-Shadow','Druid-Balance','Paladin-Retribution','Warrior-Arms','Paladin-Protection','Shaman-Restoration','Warrior-Protection','Mage-Fire','DeathKnight-Blood','DeathKnight-Unholy','Evoker-Devastation','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Druid-Feral','Evoker-Preservation','DemonHunter-Devourer','Monk-Windwalker','Monk-Mistweaver','Mage-Frost','Shaman-Enhancement','Monk-Brewmaster','DeathKnight-Frost','Warlock-Affliction','Warrior-Fury','Evoker-Augmentation',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abris:BAAANQAECgEIAgABNQAECgQIDAABAAAAAA==.',
Ac='Acekith:BAAANQABCgMIAwABNQAECgQJBgABAAAAAA==.Acense:BAAANQAECgQJBgAAAA==.Acidhunter:BAAANQADCgcIBwAAAA==.Acidlock:BAAANQAECggIEwAAAA==.Acidpriest:BAAANQAECgYIDgAAAA==.',
Ad='Adacey:BAABNQAECn8YAAICAAgKGQ4xBAAdAQACAAgKGQ4xBAAdAQAAAA==.Adragon:BAAANQADCgQIBAABNQAECgUIDgABAAAAAA==.Adrenalized:BAAANQADCgMIBAAAAA==.',
Ae='Aesuga:BAAANQADCgYIBgAAAA==.',
Af='Afteraction:BAAANQADCgMIAwAAAA==.',
Ak='Aktras:BAABNQAECn8ZAAIDAAYK9hH6qgDxAAADAAYK9hH6qgDxAAAAAA==.',
Al='Alaunu:BAABNQAECn8xAAIEAAoKaBEZGADvAQAEAAoKaBEZGADvAQAAAA==.Aleas:BAAANQADCgQIBAAAAA==.Alexx:BAAANQAECgQICgAAAA==.Alkaid:BAAANQAECgYIDgAAAA==.Alric:BAAANQAECgMIAwAAAA==.',
An='Anari:BAAANQAECgQIBwABNQAECggIDQABAAAAAA==.Anarky:BAAANQAECggIEgAAAA==.Angelcorp:BAAANQAECgMIAwAAAA==.Annebonny:BAAANQAECgUIDAAAAA==.',
Ap='Apsalar:BAAANQADCgcJBwAAAA==.',
Ar='Archdemon:BAABNQAECn9bAAMFAAoKASV+AwC6AwAFAAoKsCR+AwC6AwAGAAkKVx/eAgB8AgAAAA==.Arienys:BAAANQADCgYICwAAAA==.Ariis:BAAANQADCgUICQAAAA==.Arkh:BAAANQADCgMIAwAAAA==.Arkhanx:BAAANQADCgUJBQAAAA==.Arkhfu:BAAANQAECgIIAgAAAA==.Arleen:BAAANQAECgIIAgAAAA==.Arquen:BAABNQAECn8qAAIHAAoKaCKKBgBjAwAHAAoKaCKKBgBjAwAAAA==.',
As='Asevenx:BAAANQADCggIEQAAAA==.Ashamane:BAAANQAECgEIAQAAAA==.Asian:BAAANQADCgIIAgAAAA==.Asra:BAAANQAECgYICgAAAA==.Astrov:BAABNQAECn8gAAIFAAoKNhIDJAB1AQAFAAoKNhIDJAB1AQAAAA==.',
At='Atulmags:BAAANQAECgYICQAAAA==.',
Au='Auani:BAABNQAECn81AAIIAAkK2CBEBwBOAwAIAAkK2CBEBwBOAwAAAA==.Aurelily:BAAANQADCgYJDAAAAA==.Ausia:BAAANQAECgUIBwAAAA==.',
Av='Avann:BAAANQADCgIIAgAAAA==.',
Az='Azazyl:BAAANQADCgcIFgAAAA==.Azzeus:BAAANQAECgUICwABNQAECgoKKQAJAO8YAA==.Azzfists:BAAANQADCgQIBAABNQAECgoKKQAJAO8YAA==.Azzshot:BAABNQAECn8pAAMJAAoK7xjfIAD1AAAKAAgKWRmGgAAMAgAJAAoKkgnfIAD1AAAAAA==.',
Ba='Babyrinsjr:BAABNQAECn8bAAIKAAYK0A/bwQB+AQAKAAYK0A/bwQB+AQAAAA==.Badista:BAAANQADCgIIAgAAAA==.Baile:BAAANQAECgIIAQABNQAECgQIBwABAAAAAA==.Balleont:BAABNQAECn8fAAIKAAkKCRSIWABqAgAKAAkKCRSIWABqAgAAAA==.Barrada:BAABNQAECn8gAAIKAAcKuQXOxwByAQAKAAcKuQXOxwByAQAAAA==.',
Be='Beefcakeßody:BAAANQADCgYIBgAAAA==.Berea:BAABNQAECn9VAAMLAAoKYxBNEQB3AQAMAAoKwwxPLADMAQALAAgK1AxNEQB3AQAAAA==.',
Bi='Birgi:BAAANQADCgEIAQAAAA==.',
Bl='Blankdemonic:BAAANQABCgYICAAAAA==.Blankwar:BAAANQADCgUIBQAAAA==.Bleedblue:BAABNQAECn8dAAIMAAcKdwz0JQCXAQAMAAcKdwz0JQCXAQAAAA==.Blitzed:BAAANQADCgIIAgAAAA==.Bloodhaven:BAAANQADCgEIAQAAAA==.',
Bo='Bo:BAABNQAECn81AAIKAAkKrx0RJQACAwAKAAkKrx0RJQACAwAAAA==.Bobbinrobin:BAAANQAECgQIBQABNQAECgkJHgANAF8UAA==.Borahae:BAAANQAFFAEIAQAAAA==.Borden:BAAANQADCgQJBAAAAA==.',
Br='Bradent:BAAANQAECgcIDQAAAA==.Breach:BAAANQAECgIIAwABNQAECgQIBwABAAAAAA==.Brunnhild:BAAANQAECgIIAgAAAA==.Bryxi:BAAANQAECgcIDwAAAA==.Brünhilde:BAABNQAECn8vAAQOAAoKXRTmPQC9AQAOAAoKOxPmPQC9AQAPAAQKAxCeFQDRAAAQAAEKAABJhwAiAAAAAA==.',
Bs='Bstbll:BAACNQAFFH8XAAIIAAcKNhjIAwABAgAIAAcKNhjIAwABAgA1AAQKfzUAAwgACgptHo0MAGoCAAgACgptHo0MAGoCABEAAQp/FeFpADoAAAAA.',
Bu='Bubbleheals:BAABNQAECn82AAMHAAoKBhGrKwD8AQAHAAoKBhGrKwD8AQASAAUK5gMyFQFlAAABNQAFFAUICQANAIoLAA==.Bundtcake:BAAANQAECggIBwAAAA==.Burningfist:BAAANQAECgQIDAAAAA==.Buttsnacks:BAABNQAECn8mAAITAAoKUxWIWACCAgATAAoKUxWIWACCAgAAAA==.',
Ca='Caciocavallo:BAAANQAECggIAQABNQAECggIDQABAAAAAA==.Callistrah:BAAANQAECgUIBwAAAA==.Caltaa:BAABNQAECn81AAIUAAkKsCHNBQBRAwAUAAkKsCHNBQBRAwAAAA==.Canarah:BAAANQADCgQIBAABNQAECgkJGgAVAJIZAA==.Canverian:BAABNQAECn8bAAIEAAYKAxbjJQBnAQAEAAYKAxbjJQBnAQAAAA==.Captsmash:BAABNQAECn8uAAMWAAoKGxzfBgACAgAWAAoKGxzfBgACAgATAAUK9QbOowDEAAAAAA==.Carmedic:BAAANQADCgIIAgAAAA==.Caudel:BAAANQABCgIIAgAAAA==.',
Cd='Cdub:BAAANQAECgYIDQAAAA==.',
Ch='Charcuterie:BAAANQAECgQIDQAAAA==.Chasseurfool:BAABNQAECn8bAAIKAAkKOQnnXACHAQAKAAkKOQnnXACHAQAAAA==.Chat:BAACNQAFFH8OAAINAAQKGRIRCwDeAAANAAQKGRIRCwDeAAA1AAQKfzcAAg0ACgqYHOAXAEECAA0ACgqYHOAXAEECAAAA.Chevre:BAABNQAECn8VAAIKAAUKphDS8gAcAQAKAAUKphDS8gAcAQAAAA==.Chezaro:BAABNQAECn8gAAISAAgKTgzNegBcAQASAAgKTgzNegBcAQAAAA==.Chickenwing:BAABNQAECn8nAAIXAAoKSx8sAQDcAgAXAAoKSx8sAQDcAgAAAA==.Christano:BAABNQAECn8nAAMSAAoKPx5aIACLAgASAAoK0x1aIACLAgAUAAMKRyAlLACtAAAAAA==.Christhecold:BAABNQAECn8gAAITAAgKHxrMbgBGAgATAAgKHxrMbgBGAgAAAA==.Chrollo:BAAANQAECgUIEQAAAA==.Chuchu:BAAANQADCgMIAwAAAA==.Chumba:BAAANQAECgYIDgAAAA==.',
Ci='Cinnamilk:BAAANQAECggIBwABNQAECgkJQgAYADAcAA==.',
Cl='Clamslamm:BAEANQADCgUIBQABNQAECgcIHwAZAJIhAA==.Cloudcrack:BAECNQAFFH8PAAMVAAUKpw39EgAiAQAVAAUKpw39EgAiAQANAAMKdAqDHADcAAA1AAQKfzEAAxUACgp+I24DALMDABUACQrDI24DALMDAA0ACQo2HPksAMkCAAAA.',
Co='Cocotaso:BAAANQABCgIIAgAAAA==.Codemon:BAABNQAECn8iAAIaAAcKEBm4FQDwAQAaAAcKEBm4FQDwAQAAAA==.Cole:BAAANQADCgUIBQAAAA==.Cosmoline:BAABNQAECn8jAAIbAAoKmhy3AgAyAgAbAAoKmhy3AgAyAgABNQAECgcIFAAFAGIRAA==.Cotw:BAAANQAECgIIAgABNQAECgUIDgABAAAAAA==.Coverttops:BAABNQAECn8VAAMcAAcKPQlcKQAwAQAcAAcKPQlcKQAwAQAdAAIKgQQQNQFPAAAAAA==.',
Cp='Cptcharis:BAAANQADCgEIAQAAAA==.',
Cr='Critmyshorts:BAAANQAECgYICgAAAA==.Critnespears:BAAANQADCgYIBgAAAA==.Crottin:BAAANQAECgQIAwAAAA==.',
Cu='Cubann:BAAANQAECgIIAgAAAA==.',
Cy='Cylrhea:BAAANQAECgUIDwAAAA==.Cynri:BAAANQADCgQIBQABNQAECgIIAgABAAAAAA==.Cyntrill:BAAANQAECgUICQAAAA==.',
Da='Daboulder:BAAANQAECgEIAQAAAA==.Dadderz:BAAANQADCgYIGQAAAA==.Daedean:BAAANQAECgIIAgABNQAECgQIBwABAAAAAA==.Dagnome:BAAANQADCggICAAAAA==.Dahunter:BAAANQAECgIIAgAAAA==.Dajoel:BAAANQAECgIIAgAAAA==.Dalacia:BAABNQAECn8cAAIVAAoKkRVFXgD0AQAVAAoKkRVFXgD0AQAAAA==.Daphera:BAAANQADCgcIDAAAAA==.Darkhollow:BAAANQADCggIHwAAAA==.Darkhunta:BAAANQADCgQIBAAAAA==.Darknature:BAABNQAECn8hAAIIAAgKhRjiIQAYAgAIAAgKhRjiIQAYAgAAAA==.Darkodin:BAABNQAECn8cAAIZAAcKXgn5cgBLAQAZAAcKXgn5cgBLAQAAAA==.Darkshamy:BAAANQAECgMIBQAAAA==.Darksknightt:BAAANQADCgEIAQAAAA==.Darrad:BAAANQAECgUIBwAAAA==.Datnagadrake:BAACNQAFFH8QAAITAAUKuRMWCQAxAQATAAUKuRMWCQAxAQA1AAQKf0wAAxMACgqrIqcUAMACABMACgp2IqcUAMACABYABgrdIAgQACgCAAAA.Dawinchy:BAABNQAECn8uAAMIAAoKaxnLGAB3AgAIAAoKaxnLGAB3AgAeAAYKxg5oGwBMAQAAAA==.',
De='Deadlypsycho:BAAANQAECgEIAQAAAA==.Deathavoider:BAAANQADCggIEAAAAA==.Deathawakens:BAAANQADCgEIAQAAAA==.Deathlyill:BAAANQAECgIJAgAAAA==.Decemberr:BAAANQAECgQICQAAAA==.Dekudin:BAABNQAECn8dAAIUAAgKtBSmGAA6AQAUAAgKtBSmGAA6AQAAAA==.Dellistia:BAAANQADCgYICwAAAA==.Dennywenny:BAAANQAECgUIDAAAAA==.Deric:BAAANQAECgEIAQAAAA==.Desdamona:BAABNQAECn8bAAIKAAYK2ANkxQCnAAAKAAYK2ANkxQCnAAAAAA==.Destrodemon:BAAANQADCggICAAAAA==.Destropally:BAABNQAECn8hAAISAAkK0w4XqwDJAQASAAkK0w4XqwDJAQAAAA==.Devorick:BAABNQAECn82AAMdAAkKER0LKwDYAgAdAAkKER0LKwDYAgAcAAIKIhBQVwB5AAAAAA==.',
Di='Diaval:BAAANQAECgQICAAAAA==.Dih:BAAANQADCgYIBgABNQAECgkJJQAcAHQWAA==.Dijarl:BAABNQAECn8nAAIKAAkK+h4ZEADOAgAKAAkK+h4ZEADOAgAAAA==.Dipndots:BAAANQAECgUICAAAAA==.Dirtyboy:BAAANQADCgIIAgAAAA==.Discórdia:BAAANQAECgMIAwAAAA==.Diyiya:BAABNQAECn8aAAIKAAcK+wmciQAeAQAKAAcK+wmciQAeAQAAAA==.',
Do='Doggiestylin:BAAANQAECgMIAwAAAA==.Doorki:BAAANQAECggICQAAAA==.Dottey:BAABNQAECn8YAAIcAAkKvA99FwCxAQAcAAkKvA99FwCxAQAAAA==.Doubleott:BAAANQAECgEIAQAAAA==.',
Dr='Drael:BAAANQAECgUIBwAAAA==.Draickin:BAABNQAECn8fAAIHAAgKQBauZADqAQAHAAgKQBauZADqAQAAAA==.Drekle:BAABNQAECn8dAAMaAAgKgxkqCgBNAQAaAAcKOhcqCgBNAQAfAAUKqQvmOADOAAABNQAECgkJMAARADUUAA==.Drelian:BAAANQAECgUICQAAAA==.Drevy:BAABNQAECn8VAAICAAgK8BZLBgBwAgACAAgK8BZLBgBwAgAAAA==.Drewdox:BAAANQADCgUIDAAAAA==.Drexchan:BAAANQAECgEIAQAAAA==.Drizzlenuts:BAAANQAFFAEIAQAAAA==.Drrabbít:BAAANQADCgQIBAAAAA==.Drumira:BAAANQADCgMIAwABNQAECgkJHgAQAPEPAA==.Drumk:BAAANQADCgIIAgABNQAECgkJHgAQAPEPAA==.Drumma:BAAANQADCggIDwAAAA==.Drummer:BAABNQAECn8eAAQQAAkK8Q/BNAB9AQAQAAcKnQzBNAB9AQAPAAUKrhSnDwAwAQAOAAUKkgUuvADlAAAAAA==.Drumroleplz:BAAANQAECgQIBAABNQAECgkJHgAQAPEPAA==.',
Dw='Dw:BAACNQAFFH8FAAIgAAIKqw6wEACNAAAgAAIKqw6wEACNAAA1AAQKfycAAyAACgr1GqIXAKACACAACgr1GqIXAKACAAUAAwqrD4t2AKAAAAE1AAUUBQgNAAoA9hUA.',
['Dà']='Dàddybear:BAABNQAECn8ZAAIKAAcKYwtyjQAXAQAKAAcKYwtyjQAXAQAAAA==.',
Ea='Earthsangel:BAAANQAECgQIBgAAAA==.',
Ec='Eclair:BAAANQAECgQICQAAAA==.',
Ed='Edralyia:BAAANQADCgYICwAAAA==.',
Eg='Egwene:BAAANQADCgQIBAAAAA==.',
Ei='Eilaurosa:BAABNQAECn8WAAILAAgKlgk7RQCyAQALAAgKlgk7RQCyAQAAAA==.Einnarr:BAAANQAECggIBQAAAA==.',
El='Eldrinne:BAABNQAECn8iAAIXAAgKEATwBQANAQAXAAgKEATwBQANAQAAAA==.Eleblast:BAAANQAECgIIAgAAAA==.Elizavoid:BAABNQAECn8hAAQOAAkKKxswQwBfAgAOAAkKKxswQwBfAgAQAAUKUhALLACuAAAPAAEKLhf7JABEAAAAAA==.Elizawrath:BAAANQADCgIIAgAAAA==.Elkuco:BAAANQAECgEIAQAAAA==.Elmindreyda:BAABNQAECn8fAAIMAAkKUA7wOgB5AQAMAAkKUA7wOgB5AQAAAA==.Elthiss:BAABNQAECn83AAIEAAkKsBmxEABVAgAEAAkKsBmxEABVAgAAAA==.',
En='Enfer:BAAANQAECgcIEgABNQAFFAQIDgANABkSAA==.Enyfing:BAAANQAECgQIBAAAAA==.',
Er='Erequois:BAAANQADCgEIAQABNQAECgcIDwABAAAAAA==.Erianthe:BAABNQAECn8kAAIZAAgKdgascwBIAQAZAAgKdgascwBIAQAAAA==.Eriok:BAAANQABCggIDwAAAA==.Erophien:BAAANQADCgMIBAAAAA==.Erovynael:BAAANQAECgQIDAAAAA==.Erovynthalin:BAAANQADCgYIEAAAAA==.Errorwing:BAAANQAECgQIBwAAAA==.',
Es='Eshera:BAAANQADCgIIAgAAAA==.Esherä:BAAANQAECgEIAQAAAA==.',
Ev='Eversong:BAAANQADCgYIDAAAAA==.',
Ex='Exmar:BAAANQAECggIDAAAAA==.',
Ey='Eyesopen:BAAANQAECgYIBwAAAA==.',
Fa='Faewhisker:BAABNQAECn8YAAMhAAkKyw25KQDQAQAhAAkKyw25KQDQAQAiAAQKBQYgOwCZAAAAAA==.Faithfool:BAABNQAECn8fAAINAAkK3gmSkAB7AQANAAkK3gmSkAB7AQAAAA==.Falshallnot:BAAANQAECgUIBAABNQAECgkJMAARADUUAA==.Fancyfeet:BAAANQAECgUIBQABNQAECgkJGgAMADEUAA==.Fanduelfiend:BAAANQADCgMIAwAAAA==.Fangmonarch:BAAANQADCgUIBQAAAA==.Fashaladd:BAABNQAECn8wAAQRAAkKNRQPPwACAgARAAkKNRQPPwACAgAEAAEKAAA1WABIAAAIAAEKlRMAAAAAAAAAAA==.',
Fe='Fearios:BAABNQAECn9CAAIYAAkKMByfGADoAgAYAAkKMByfGADoAgAAAA==.Felbeast:BAAANQAECgMIBQAAAA==.Felbound:BAAANQADCgUICQAAAA==.Femboy:BAAANQADCggICAAAAA==.Feorar:BAAANQADCgYJBgAAAA==.Feta:BAAANQAECgcICgABNQAECggIDQABAAAAAA==.',
Fi='Fieldtrip:BAAANQAECgYIDwAAAA==.Fiendfyre:BAAANQADCgUIBQAAAA==.Fizzlenuts:BAABNQAECn8ZAAIiAAgK6hUiFgAaAgAiAAgK6hUiFgAaAgABNQAFFAEIAQABAAAAAA==.',
Fl='Flightless:BAAANQADCggICgAAAA==.',
Fo='Foxi:BAAANQAECgQJBAAAAA==.',
Fr='Frosttbyte:BAABNQAECn85AAMDAAoKFxlRagCpAgADAAoKmhhRagCpAgAjAAEKjB4AOQBaAAAAAA==.Frostytute:BAAANQADCgIIAgAAAA==.',
Fu='Fullmetalass:BAABNQAECn8WAAIKAAkKZxYbjQDwAQAKAAkKZxYbjQDwAQAAAA==.',
Fy='Fyyre:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëiróx:BAAANQADCgIIAgAAAA==.',
Ga='Galistar:BAABNQAECn8aAAINAAYKrA1grwA0AQANAAYKrA1grwA0AQAAAA==.Gallum:BAAANQABCgEIAQAAAA==.Garglelots:BAAANQAECgUIBgABNQAECgkJHgANAF8UAA==.Garrotxa:BAAANQAECggICwABNQAECggIDQABAAAAAA==.',
Ge='Gevallen:BAAANQAECgcICgAAAA==.',
Gh='Ghavinental:BAABNQAECn8kAAMNAAcKFBFqgQChAQANAAcKAQ9qgQChAQAkAAcK7wwMHwBvAQAAAA==.',
Gi='Gil:BAABNQAECn8eAAIgAAoK4x2bFADCAgAgAAoK4x2bFADCAgAAAA==.Gilgamesh:BAAANQAECgUICgABNQAECgoKHgAgAOMdAA==.',
Gl='Glizzard:BAAANQAECgUIDAABNQAECggIGAASAP8eAA==.Glocket:BAAANQAECgMIBwAAAA==.Gloom:BAAANQAECgYIBgAAAA==.',
Gn='Gnolan:BAABNQAECn8iAAMMAAgKph0EEgBiAgAMAAgKph0EEgBiAgALAAUKHROXXgA8AQAAAA==.',
Go='Goatspace:BAABNQAECn8lAAQbAAoK3gp8BgA7AQAKAAkK2wfRxQB2AQAbAAYK4Ap8BgA7AQAJAAUKDQPLXwCnAAAAAA==.Gomu:BAAANQADCgQIBAAAAA==.Gongagà:BAABNQAECn8kAAIgAAkK/g6jLQDUAQAgAAkK/g6jLQDUAQAAAA==.Goodnoodle:BAAANQAECgEIAgAAAA==.Goodwithabow:BAAANQAECgQICAAAAA==.Goremaster:BAAANQAECgQICgAAAA==.Gothbaddie:BAAANQAECgQIBAABNQAECggIDQABAAAAAA==.Goyum:BAAANQADCgEIAQAAAA==.',
Gr='Grankino:BAABNQAECn8tAAQeAAgK5QsAHwAiAQAeAAUK2xAAHwAiAQARAAgKqwfAOQDhAAAEAAEKiAQDbwAeAAAAAA==.Greedisgood:BAAANQADCgMIAwAAAA==.Greenthumbs:BAAANQADCgYIBgAAAA==.',
Gw='Gwaelphypha:BAABNQAECn8gAAIYAAcKghhaQwDuAQAYAAcKghhaQwDuAQABNQAECgcIDwABAAAAAA==.',
Ha='Hakarii:BAAANQADCgEIAQAAAA==.Halder:BAAANQAECgEIAQAAAA==.Hapkido:BAABNQAECn87AAMlAAoKiSKIAQCvAwAlAAkKGCSIAQCvAwAhAAIK3RLZNQCFAAAAAA==.Hawk:BAAANQAECgMIAwAAAA==.Hazrek:BAABNQAECn8VAAIkAAcKpgviGwClAQAkAAcKpgviGwClAQAAAA==.',
He='Heartattack:BAAANQAECggIAgAAAA==.Hecate:BAABNQAECn8UAAISAAYKbwQIHgHtAAASAAYKbwQIHgHtAAAAAA==.Heidnik:BAAANQAECgUIBQAAAA==.Heihei:BAAANQAECgYIDAAAAA==.Heneedsumilk:BAAANQADCgYICgAAAA==.Heretic:BAAANQAECgIIAgAAAA==.Hermanater:BAAANQADCggICAABNQAECgcIIgAUAKIaAA==.',
Hi='Hillboy:BAAANQADCggIDgAAAA==.',
Ho='Holydes:BAAANQAECgQIBAABNQAECgYIGwAKANgDAA==.Holyground:BAAANQAECgEIAQABNQAECgoKHgAIAGslAA==.Holytrinityy:BAAANQADCgYIBgAAAA==.Holyzack:BAAANQAECgUIBQAAAA==.Hooch:BAAANQAECgUIDAABNQAECgYIDQABAAAAAA==.',
Hu='Humboldt:BAAANQAECggIBgABNQAECggIDQABAAAAAA==.Huunaron:BAABNQAECn8VAAMSAAgK7QyIpwAHAQASAAgK7QyIpwAHAQAHAAMKxhKQAAF6AAAAAA==.',
['Hé']='Héx:BAACNQAFFH8lAAMDAAcKBBbuDAARAgADAAYKPBnuDAARAgAjAAEKIgmgDgBTAAA1AAQKfyQAAyMACgo3Hn8EACcCAAMACgrQFhqaAEwCACMABwoBIH8EACcCAAAA.',
Id='Idylwilde:BAABNQAECn8bAAIRAAcK/wnIQwC1AAARAAcK/wnIQwC1AAAAAA==.',
Ie='Ienzo:BAAANQADCgQIBwAAAA==.',
Ih='Iheartoreos:BAABNQAECn8fAAIYAAcKsBKJUQCuAQAYAAcKsBKJUQCuAQAAAA==.',
Il='Ilovefuta:BAAANQAECgUICQAAAA==.Iloveoreos:BAAANQADCgYIBgAAAA==.',
In='Instakill:BAAANQADCgQIBAAAAA==.Intent:BAAANQADCgMIAwAAAA==.Invictae:BAAANQAECggIDwAAAA==.',
Io='Iobo:BAACNQAFFH8QAAIgAAcKBByYAwAdAgAgAAcKBByYAwAdAgA1AAQKfyYAAyAACgoCJMcGAGUDACAACgoCJMcGAGUDAAUAAgpDG/hIAKMAAAAA.',
Ir='Irk:BAABNQAECn8UAAIMAAgKkBWCMACyAQAMAAgKkBWCMACyAQAAAA==.Ironic:BAAANQADCgYIBgABNQAECgoKOQAMAKshAA==.',
Ja='Jagaerr:BAAANQABCgUICgAAAA==.Jarco:BAEANQAECgEIAQABNQAFFAYIDQACABwaAA==.Jargan:BAAANQADCggICAABNQAECgoKJQAbAN4KAA==.Jasseca:BAAANQAECgMIBAABNQAECgcIDwABAAAAAA==.',
Je='Jeandarc:BAAANQADCggICAAAAA==.Jezäbelle:BAAANQAECgQIBAAAAA==.',
Jo='Joesh:BAAANQABCgcIFgAAAA==.',
Ka='Kaadra:BAAANQAECgUIBQAAAA==.Kaelkin:BAABNQAECn8fAAMOAAkKhBMJUAA0AgAOAAkKhBMJUAA0AgAPAAIK6gbDIgBRAAAAAA==.Kaelun:BAAANQADCgcICwABNQAECgkJHwAOAIQTAA==.Kaelundrus:BAAANQAECgYIDAABNQAECgkJHwAOAIQTAA==.Kainis:BAAANQAECgUIDQAAAA==.Kamonorin:BAAANQABCgIIAgAAAA==.Kaotika:BAAANQAECgUIBgAAAA==.Karmus:BAAANQADCgUJCAAAAA==.',
Ke='Keadin:BAAANQADCgYICwAAAA==.Keilas:BAABNQAECn8cAAIeAAYKrBwHEgDfAQAeAAYKrBwHEgDfAQAAAA==.Kerron:BAAANQAECggIAQAAAA==.Keylala:BAABNQAECn8WAAIcAAYKxQnVDgCoAAAcAAYKxQnVDgCoAAAAAA==.',
Ki='Kickenmage:BAAANQADCgQIBAABNQAECgYIFQAKAKYGAA==.Kickentail:BAABNQAECn8VAAIKAAYKpgY13wBCAQAKAAYKpgY13wBCAQAAAA==.Kiegh:BAAANQADCgcIBwAAAA==.Kior:BAAANQADCgYIBwAAAA==.Kirisham:BAAANQADCgMIAwAAAA==.Kiriwar:BAACNQAFFH8FAAITAAIKmxTALQCSAAATAAIKmxTALQCSAAA1AAQKfzcAAhMACgp2IikiADADABMACgp2IikiADADAAAA.Kirlia:BAABNQAECn8oAAIcAAcKxg6dFQDAAQAcAAcKxg6dFQDAAQAAAA==.',
Kl='Klymax:BAAANQAECgcIDAAAAA==.',
Ko='Koretha:BAAANQAECgQIBAABNQAFFAcIFwAIADYYAA==.Kowkowkachoo:BAAANQAECgUICgAAAA==.',
Kr='Krellis:BAAANQAECgEIAQAAAA==.Krisp:BAABNQAECn8vAAMDAAkKtCK7GAByAwADAAkKtCK7GAByAwAjAAEKrSPWNABnAAAAAA==.Krobelus:BAABNQAECn8kAAISAAgKZQZt3gBeAQASAAgKZQZt3gBeAQAAAA==.Kruggs:BAAANQADCgYIBgAAAA==.',
Ks='Ksharp:BAAANQADCgYIBgABNQAECgYICQABAAAAAA==.',
Kv='Kvedadormu:BAAANQADCgYIEQAAAA==.Kvedeitrormr:BAAANQAECgEIAQAAAA==.Kvedfróðleik:BAAANQABCgEIAQAAAA==.Kvedærilaz:BAAANQADCgEIAQAAAA==.',
Ky='Kylearean:BAAANQAECgQIAwAAAA==.Kyran:BAAANQAECgIIAgAAAA==.',
['Kè']='Kèrónos:BAAANQAECgUIBwAAAA==.',
['Kì']='Kìllstheweak:BAABNQAECn8jAAMmAAgKawonTACIAQAmAAgKawonTACIAQAYAAEKeQqCfAA6AAAAAA==.',
La='Laeythe:BAAANQAECgQIBAABNQAFFAIIBgAOAI0mAA==.Lannah:BAAANQADCgYIDgAAAA==.Lash:BAAANQAECgUIBwAAAA==.',
Lc='Lclc:BAAANQAECgUICQAAAA==.',
Le='Leafeon:BAACNQAFFH8IAAIIAAYK7wkBCAB1AQAIAAYK7wkBCAB1AQA1AAQKfx0AAggACgpOIlcEAIADAAgACgpOIlcEAIADAAE1AAUUBwgQABUAORoA.Lebrin:BAABNQAECn8WAAIVAAUKZhqirQAVAQAVAAUKZhqirQAVAQAAAA==.Legaia:BAABNQAECn8xAAITAAkKox80HgA/AwATAAkKox80HgA/AwAAAA==.Legendknewl:BAAANQAECgQIBAAAAA==.Legendoflink:BAAANQAECgQIBAAAAA==.Lelana:BAAANQADCgcIBwAAAA==.Leliel:BAAANQADCggICAABNQAECgoKLQAHAJcaAA==.Lennyzamwam:BAAANQAECgQIBwAAAA==.Lesindre:BAAANQAECgcICAABNQAECggIAgABAAAAAA==.Letaria:BAAANQADCgYIBgAAAA==.Lexapro:BAAANQAECgcIDQABNQABCgcIBwABAAAAAA==.',
Li='Lianissa:BAAANQADCggIGwAAAA==.Lillinna:BAAANQAECgUIDAAAAA==.Lipidot:BAAANQAECgIIBAAAAA==.Lisea:BAAANQAECgIIAgAAAA==.Lithlina:BAAANQADCgYIBgAAAA==.',
Lo='Loamein:BAAANQAECgcIDQAAAA==.Lockrocks:BAABNQAECn8YAAIdAAgKCRNtVABlAQAdAAgKCRNtVABlAQAAAA==.Lockycharmz:BAAANQAECgIIAgABNQAECgkJQgAYADAcAA==.Lorcán:BAAANQADCgYICwAAAA==.Lorithan:BAAANQADCgIIAgAAAA==.Lormazlezrax:BAABNQAECn8aAAIVAAkKkhmhRQBLAgAVAAkKkhmhRQBLAgAAAA==.',
Lu='Lucernyx:BAAANQAECgIIAgABNQAECgEIAQABAAAAAA==.Luckystars:BAAANQADCgQIBAAAAA==.Luis:BAAANQADCgQIBAAAAA==.Luminara:BAAANQADCgYIBgAAAA==.Lunaera:BAAANQAECgcIEAAAAA==.Lune:BAAANQADCgcIBwABNQAECggIDAABAAAAAA==.Lunella:BAAANQAECgIIAgABNQAECggIDAABAAAAAA==.Lunellia:BAAANQAECggIDAAAAA==.Lunethira:BAAANQADCgMIAwABNQAECggIDAABAAAAAA==.Lunevra:BAAANQABCgcIBwABNQAECggIDAABAAAAAA==.Lupi:BAAANQADCggIDwAAAA==.Lurkaburger:BAABNQAECn8ZAAITAAkKthawZwBZAgATAAkKthawZwBZAgAAAA==.',
Ly='Lythindra:BAAANQADCgQIBAAAAA==.',
Ma='Madhatter:BAAANQAECgQIEAAAAA==.Mageistmage:BAACNQAFFH8QAAIDAAUKzhccHgCRAQADAAUKzhccHgCRAQA1AAQKfykAAwMACgrHIwQUAL8CAAMACgrHIwQUAL8CACMAAQpbHJQkAFcAAAAA.Magori:BAAANQADCgYIBgAAAA==.Majarl:BAAANQAECgYIEgAAAA==.Maki:BAAANQADCgEIAQABNQAECggIIwAHAMwdAA==.Malegar:BAAANQADCggIFgAAAA==.Malificent:BAAANQAECgQICAAAAA==.Mammajamma:BAABNQAECn8oAAIRAAkKYRZENgA5AgARAAkKYRZENgA5AgAAAA==.Marsvolta:BAAANQAECgQICAAAAA==.Maruxus:BAABNQAECn8+AAILAAoKZRauBwAdAgALAAoKZRauBwAdAgAAAA==.Maulsin:BAAANQADCgUIBQAAAA==.Mavanthia:BAABNQAECn8qAAMTAAkK3BKfSgCmAQATAAkK3BKfSgCmAQAWAAEK0hIWQgA3AAAAAA==.Mayyonnaise:BAAANQAECgIIAQAAAA==.',
Mc='Mcdeathy:BAAANQAECgUIDgAAAA==.Mclardragos:BAABNQAECn8nAAMfAAoK1yE4BQBYAwAfAAoK1yE4BQBYAwAaAAEKAAB2PgAvAAAAAA==.',
Me='Meadõw:BAAANQADCgUIBQAAAA==.Meatshield:BAAANQADCgcIDAAAAA==.Mecharoni:BAABNQAECn85AAMMAAoKqyGlDACqAgAMAAkK+h+lDACqAgALAAcKwSA2IgB0AgAAAA==.Medreaux:BAAANQAECggIAgAAAA==.Meganaturexl:BAAANQABCgQIBAAAAA==.Mendication:BAAANQAECgcIEQAAAA==.Meretrixee:BAAANQADCgIIAgABNQAECgoKPAAOAHUYAA==.Meteion:BAABNQAECn8WAAMdAAYKdB5nVABlAQAdAAYKdB5nVABlAQAcAAEKAACYeAA1AAABNQAECggIAgABAAAAAA==.',
Mi='Miacyn:BAAANQAECgIIBQAAAA==.Midnitte:BAAANQAECgEIAQAAAA==.Miladybast:BAABNQAECn8UAAIjAAYKWgcSHAAPAQAjAAYKWgcSHAAPAQAAAA==.Miniwheet:BAAANQAECgcICAABNQAECgkJQgAYADAcAA==.Minke:BAAANQADCggIHwAAAA==.Mirra:BAABNQAECn8eAAIKAAgK3xJAZwBsAQAKAAgK3xJAZwBsAQAAAA==.Missdorei:BAAANQADCgUIBQAAAA==.',
Mo='Molai:BAAANQAECggICAAAAA==.Mommades:BAAANQADCgYIBgABNQAECgYIGwAKANgDAA==.Momsrymommy:BAABNQAECn8XAAISAAYKtxJrwgCXAQASAAYKtxJrwgCXAQAAAA==.Moodrian:BAAANQADCggICQABNQAECgkJMAARADUUAA==.Moonaurora:BAAANQABCgMIAwAAAA==.Moontater:BAAANQADCgYIBgAAAA==.Mordekaiser:BAAANQADCggICAAAAA==.Morgul:BAAANQAECgQIBAAAAA==.Morionso:BAABNQAECn8iAAIUAAcKoholIQDbAQAUAAcKoholIQDbAQAAAA==.Morphyrinsjr:BAAANQADCgcIBwABNQAECgYIGwAKANAPAA==.Mortarion:BAABNQAECn8zAAQZAAkKOxlvQgASAgAZAAcK5RtvQgASAgAmAAgK4xHWQwC0AQAYAAIKPAnZaQBgAAAAAA==.Morwenspring:BAAANQADCgMIAwAAAA==.',
Ms='Mssrbubbles:BAAANQABCggIFwAAAA==.',
Mu='Murdiûs:BAABNQAECn82AAMhAAoK7B0+EgDLAgAhAAoK7B0+EgDLAgAiAAkKCxhZBwBxAgAAAA==.',
My='Mythbruh:BAEBNQAECn8fAAMZAAcKkiGUSwDmAQAZAAcKhiCUSwDmAQAmAAcKfho2PADdAQAAAA==.',
Na='Nachokru:BAAANQABCgEIAgAAAA==.Nahla:BAAANQAECgIIAgAAAA==.Namrevlis:BAAANQADCgIIAgABNQAECgkJHgAQAPEPAA==.Narl:BAAANQAECgUICAAAAA==.Nayrditation:BAAANQAECgcIDQAAAA==.Nayrlock:BAAANQAECgcICwABNQAECgcIDQABAAAAAA==.',
Nc='Nctee:BAAANQAECgUICgAAAA==.',
Ne='Necropally:BAAANQADCgcIDQAAAA==.Nevermore:BAAANQAECgYIBgAAAA==.',
Ni='Nightsmoke:BAAANQAECgMJBQAAAA==.',
No='Nolabull:BAAANQADCgQIBAAAAA==.Nonattarius:BAABNQAECn8aAAIKAAYKZAgP3wBDAQAKAAYKZAgP3wBDAQAAAA==.Noraelara:BAAANQAECggIAQABNQAECggIAgABAAAAAA==.Norezfou:BAABNQAECn81AAMOAAkKyRa1PwBsAgAOAAkKyRa1PwBsAgAQAAcKkhhvJAANAgAAAA==.Norran:BAAANQADCgMIAwAAAA==.Notalice:BAAANQADCgYIBgABNQAECgQIDAABAAAAAA==.Nottartar:BAAANQAECgIJAgAAAA==.',
Nu='Nuker:BAAANQADCgYIEgAAAA==.Nurobi:BAABNQAECn8wAAIRAAoKSRD2OAAoAgARAAoKSRD2OAAoAgAAAA==.',
Od='Odanobunaga:BAACNQAFFH8GAAITAAIKLQjJHQB7AAATAAIKLQjJHQB7AAA1AAQKfy4AAhMACgq/F3hVAIoCABMACgq/F3hVAIoCAAAA.Odyn:BAABNQAECn8UAAISAAYKahDc7wA9AQASAAYKahDc7wA9AQAAAA==.',
Oe='Oerrael:BAAANQADCgcIEAAAAA==.',
Or='Oridk:BAABNQAECn82AAIZAAoKWBv7DABNAgAZAAoKWBv7DABNAgABNQAFFAQICwAKAN0ZAA==.Oripal:BAAANQAECgIIAgABNQAFFAQICwAKAN0ZAA==.Oríon:BAACNQAFFH8LAAMKAAQK3RlsCgD/AAAKAAQK3RlsCgD/AAAbAAEK7wudAgBOAAA1AAQKfzIABBsACgpUIskCAP0CABsACQpsHskCAP0CAAoABgpeIWlhAHsBAAkABgrwFSs7AHgBAAAA.',
Ou='Outofrange:BAAANQAECggIBgAAAA==.',
Pa='Pangjang:BAAANQAECgUICQAAAA==.Pankratease:BAAANQAECgcICQAAAA==.Pankratoes:BAAANQAECgIIAgABNQAECgcICQABAAAAAA==.Pankratos:BAAANQADCgUIBQABNQAECgcICQABAAAAAA==.Papahess:BAABNQAECn8hAAMRAAgKfBVCRQDbAQARAAgKfBVCRQDbAQAEAAMKyQzSSQCFAAAAAA==.Paradias:BAABNQAECn8aAAIMAAkKMRSnEwBNAgAMAAkKMRSnEwBNAgAAAA==.Pastaladan:BAAANQADCgQIBAAAAA==.Pastor:BAAANQAECgMIAwAAAA==.Paxxul:BAAANQADCggICwAAAA==.',
Pe='Peppersham:BAAANQAECgUIEAAAAA==.Petespally:BAABNQAECn8iAAMHAAgKIiMnCwAUAwAHAAgKIiMnCwAUAwAUAAEKAACTbgA0AAAAAA==.',
Pf='Pfftpfft:BAAANQAECgIIBAAAAA==.',
Ph='Pha:BAABNQAECn8gAAIDAAoKrRgibwCfAgADAAoKrRgibwCfAgAAAA==.Phatdanny:BAAANQAECggIDAAAAA==.Phonycheese:BAABNQAECn8vAAMSAAoK5BRpeQA5AgASAAkKfRZpeQA5AgAHAAQK0ggelgCSAAAAAA==.Phur:BAAANQAECgMIAwAAAA==.',
Pi='Pixen:BAABNQAECn9ZAAMdAAoKSRtjEwCOAgAdAAoKSRtjEwCOAgAnAAEKAAADMQAzAAAAAA==.',
Po='Pocalypse:BAAANQAECgQIBQAAAA==.Ponkeyfists:BAACNQAFFH8IAAIhAAQK5BpcBgDZAAAhAAQK5BpcBgDZAAA1AAQKfygAAiEACgoHI/0IAEEDACEACgoHI/0IAEEDAAAA.Portstar:BAABNQAECn8qAAIDAAoKjgh01gDaAQADAAoKjgh01gDaAQAAAA==.Powderhorn:BAAANQADCgUIBQAAAA==.',
Pr='Pravium:BAAANQADCgYIBgABNQAECggIDwABAAAAAA==.Primed:BAABNQAECn80AAIeAAkKtRKADQBDAgAeAAkKtRKADQBDAgAAAA==.Prozac:BAAANQAECgEIAQABNQABCgcIBwABAAAAAA==.',
Pu='Pungla:BAABNQAECn8UAAIhAAoKlRXOGgBoAgAhAAoKlRXOGgBoAgAAAA==.',
['Pî']='Pîper:BAAANQABCgEIAQAAAA==.',
Qu='Quelthanos:BAABNQAECn8yAAMSAAkKQxSAVAC4AQASAAkKQxSAVAC4AQAHAAEKfBDGGwE8AAAAAA==.Quesoblanco:BAAANQABCgQIBAAAAA==.',
Ra='Radical:BAAANQAECgMIBQAAAA==.Ralvick:BAAANQADCgEJAQAAAA==.Ramuun:BAAANQADCgIIAgAAAA==.Randomclown:BAAANQAECgEIAQAAAA==.Rascalfats:BAAANQAECgQIBwABNQAECgYIDQABAAAAAA==.Rashii:BAABNQAECn8nAAIOAAkKrxScMwDuAQAOAAkKrxScMwDuAQAAAA==.Rawor:BAAANQAECgQIBAAAAA==.Raworrior:BAABNQAECn8aAAMTAAcKFg3/wAB7AQATAAcKFg3/wAB7AQAoAAEKOAhgNQAwAAAAAA==.',
Re='Reax:BAAANQADCgYIBgAAAA==.Rebaderchi:BAABNQAECn8hAAIgAAkKYhkAGwCAAgAgAAkKYhkAGwCAAgABNQADCgMIAwABAAAAAA==.Reignofpower:BAAANQADCgUIBQAAAA==.Reisswolf:BAAANQAECgMIAwAAAA==.Remoria:BAAANQAECgUIEAAAAA==.Renildan:BAAANQAECgYICgAAAA==.Renmazuo:BAAANQADCgMIAwAAAA==.Rezputan:BAAANQAECgQIBAAAAA==.',
Rh='Rhavin:BAAANQAECgYIBwAAAA==.Rhodon:BAAANQAECggIDQAAAA==.Rhohorn:BAAANQAECggIBwAAAA==.Rholand:BAABNQAECn8vAAITAAoKbBtKVACOAgATAAoKbBtKVACOAgAAAA==.',
Ri='Rivalt:BAAANQABCgQIBwAAAA==.Riverra:BAAANQADCgcICgAAAA==.Rizzoy:BAABNQAECn8gAAMoAAcKXRarFABVAQAoAAUKaRmrFABVAQATAAYKzBKA4QAmAQAAAA==.',
Ro='Rollo:BAAANQADCgIIBQAAAA==.Roottender:BAAANQADCgcICwAAAA==.Rovyr:BAABNQAECn8sAAMfAAkK/h4MFABtAgAfAAkK/h4MFABtAgApAAEKAAC4JwAlAAAAAA==.Rowinna:BAAANQADCgUIBQAAAA==.',
Ru='Ruckabis:BAABNQAECn8cAAIVAAkKeBXCRQBKAgAVAAkKeBXCRQBKAgAAAA==.',
Ry='Rybearkin:BAAANQADCgMIAwAAAA==.Rylos:BAABNQAECn8aAAIZAAgKPAkSJQBOAQAZAAgKPAkSJQBOAQAAAA==.Ryshadow:BAAANQADCgYICwAAAA==.Ryumi:BAABNQAECn8ZAAIDAAcKexA1/QCTAQADAAcKexA1/QCTAQAAAA==.',
Sa='Saansula:BAAANQADCgEIAQAAAA==.Sacmaster:BAAANQADCggIDAABNQAECgkJJQAcAHQWAA==.Saitamå:BAABNQAECn8kAAIiAAkKxheBFgAUAgAiAAkKxheBFgAUAgAAAA==.Samanaras:BAABNQAECn8lAAMWAAkKxxAqFAD/AAATAAgKrg6EowDEAQAWAAcKOBIqFAD/AAAAAA==.Sangwyn:BAAANQAECgYICQABNQAECggIIwAHAMwdAA==.Santiago:BAAANQADCgMIAwAAAA==.Saratoga:BAAANQAECgQICwAAAA==.Sarkana:BAABNQAECn8tAAIHAAoKlxoMIwDgAgAHAAoKlxoMIwDgAgAAAA==.Saxonn:BAAANQAECgIIAgAAAA==.Saydis:BAABNQAECn8YAAIKAAYKowXd7gAkAQAKAAYKowXd7gAkAQAAAA==.',
Sc='Scatterbrain:BAAANQADCgcIDAAAAA==.',
Se='Sebattan:BAAANQADCgYIBwAAAA==.Seleinai:BAAANQADCgMIAwABNQAECgkJNQAPAH8dAA==.Seleine:BAABNQAECn81AAIPAAkKfx0lAgAJAwAPAAkKfx0lAgAJAwAAAA==.Seloric:BAABNQAECn8kAAIYAAgKbB/mKwBpAgAYAAgKbB/mKwBpAgAAAA==.Serendrin:BAABNQAECn86AAILAAoK0CBdBQBoAgALAAoK0CBdBQBoAgAAAA==.Sevalandre:BAAANQAECgIIAgABNQAECgcIDwABAAAAAA==.',
Sh='Shaaman:BAAANQADCgYIBgAAAA==.Shadowskyz:BAAANQAECgQIDgABNQAFFAUICQANAIoLAA==.Shaggimaggi:BAABNQAECn8UAAMYAAgKVRGDWACQAQAYAAgKVRGDWACQAQAZAAEKZgEceAAeAAAAAA==.Shamanis:BAAANQADCgQIBAAAAA==.Shamcheese:BAAANQAECgQIBAABNQAECgoKLwASAOQUAA==.Shamina:BAACNQAFFH8JAAINAAUKiguqBgAbAQANAAUKiguqBgAbAQA1AAQKf0UAAg0ACgqZHP0lAOwCAA0ACgqZHP0lAOwCAAAA.Shammlet:BAAANQABCggIFAAAAA==.Shamorex:BAABNQAECn8hAAINAAgK+xmaTQBAAgANAAgK+xmaTQBAAgAAAA==.Shatter:BAABNQAECn8YAAISAAgK/x5BXQCBAgASAAgK/x5BXQCBAgAAAA==.Shax:BAAANQADCggICAABNQAECgkJLwADALQiAA==.Shiftit:BAAANQAECgIIAgABNQAECgoKOQADABcZAA==.Shlevin:BAAANQADCgcIDAAAAA==.Shockyoface:BAAANQABCgUIBgAAAA==.',
Si='Sideshift:BAAANQAECgQIBAABNQAFFAUICQANAIoLAA==.Sinara:BAAANQAECgUICQAAAA==.',
Sk='Skaarr:BAAANQADCgQIBQAAAA==.Skibidiheals:BAAANQAECgEIAQAAAA==.Skybear:BAAANQABCgYICAAAAA==.',
Sl='Slash:BAAANQADCgYIBgAAAA==.Slayn:BAABNQAECn81AAIjAAoKFBevBAAeAgAjAAoKFBevBAAeAgAAAA==.Sleebo:BAAANQAECgQIBQAAAA==.Sleinx:BAAANQADCggIDQABNQAFFAQIDgANABkSAA==.Slyrak:BAABNQAECn8VAAMaAAoKLhPXBgC7AQAaAAkKLhXXBgC7AQAfAAEKbQl+TgAzAAAAAA==.',
Sm='Smitus:BAAANQABCgIIAgAAAA==.',
Sn='Snackie:BAABNQAECn8hAAIVAAgKLxvOLwDkAQAVAAgKLxvOLwDkAQAAAA==.Snooty:BAAANQAECggJAgAAAA==.Snotpig:BAAANQAECggIBwAAAA==.',
So='Sokar:BAAANQAECggICQAAAA==.Sokolovva:BAAANQADCgcIDAAAAA==.Souled:BAAANQADCgUIBQABNQAECgkJMgADAO4SAA==.Sourpunchkid:BAAANQAECgYIBwAAAA==.',
Sp='Spacedemon:BAABNQAECn8ZAAIgAAcKzRDuNQCUAQAgAAcKzRDuNQCUAQAAAA==.Sparroh:BAAANQADCgYIBgAAAA==.Spikedriver:BAABNQAECn8nAAIKAAoKHQ56agA+AgAKAAoKHQ56agA+AgAAAA==.Spiky:BAAANQADCgMIAwAAAA==.',
St='Stariane:BAABNQAECn8qAAIFAAoK9hpjGQDQAgAFAAoK9hpjGQDQAgAAAA==.Startaker:BAAANQADCggIDwAAAA==.Startaster:BAAANQADCgcIBwAAAA==.Starvoid:BAAANQAECgUIBwAAAA==.Stateofgrace:BAAANQAECggICAABNQAECgoKHgAIAGslAA==.Steeldk:BAAANQAECgIJAgAAAA==.Stella:BAAANQAECgQICAAAAA==.Stonyfist:BAAANQADCgEIAQAAAA==.Stonyy:BAAANQAECgIIAgAAAA==.Stubhorn:BAAANQADCgUICAAAAA==.',
Su='Summers:BAAANQADCgYICwAAAA==.Sumonmyface:BAABNQAECn8lAAMcAAkKdBbPIgBbAQAcAAQKEh7PIgBbAQAdAAYKvhBZxQBAAQAAAA==.Superillbomb:BAAANQADCgYJCQAAAA==.Superold:BAAANQAECgYIDAAAAA==.',
Sw='Swamprot:BAABNQAECn8dAAIZAAcKah+lMwBcAgAZAAcKah+lMwBcAgAAAA==.',
Sy='Sydoom:BAAANQABCgEIAQAAAA==.Syletage:BAAANQADCgYICwAAAA==.Syral:BAAANQADCgYICwAAAA==.Syrel:BAAANQAECgEIBAAAAA==.',
Ta='Tailfordays:BAAANQADCgIIAgAAAA==.Tanky:BAAANQADCgIIAgAAAA==.Tantor:BAAANQADCgEIAQAAAA==.Taurnator:BAAANQABCgEIAQAAAA==.Taylorswift:BAABNQAECn8eAAMIAAoKayV2IgASAgAIAAcKFyV2IgASAgAeAAQKZB3hGgBTAQAAAA==.',
Tc='Tchiratha:BAAANQAECgYIDwABNQAECgkJMgASAEMUAA==.',
Te='Tednougat:BAAANQADCgYIBgAAAA==.Telain:BAABNQAECn8nAAQHAAoKQQocngBKAQAHAAkKxwccngBKAQASAAcKZwpd+gAqAQAUAAIKSQz9XQBjAAAAAA==.Tensuki:BAAANQADCgQIBAAAAA==.Tesh:BAAANQADCgQIBgAAAA==.',
Th='Thaelynn:BAAANQADCggIGAAAAA==.Thakilla:BAABNQAECn89AAIRAAoK0RA3HQChAQARAAoK0RA3HQChAQAAAA==.Theolodin:BAAANQAECgIIAgAAAA==.Thordrik:BAAANQAECgIIAQAAAA==.Thorix:BAAANQAECgUICQAAAA==.Thornhub:BAAANQAECggICwABNQAFFAoKOQAcABYiAA==.Thrust:BAAANQAECgUIBQABNQABCgcIBwABAAAAAA==.Thrustwood:BAAANQADCgMIAwAAAA==.',
Ti='Tiammanth:BAAANQAECgYICQAAAA==.Tigerbrew:BAAANQADCgUIBQAAAA==.Tigerburn:BAAANQADCgQIBAAAAA==.Tigerdawn:BAAANQADCgYIBgAAAA==.Tikya:BAAANQADCgYIBwAAAA==.Tilsit:BAAANQAECggIDQAAAA==.Timberreaper:BAAANQADCgcICAAAAA==.Tinyz:BAAANQAECgQICQAAAA==.Tisisme:BAAANQADCgUIBQAAAA==.',
To='Tonythetiger:BAAANQAECgYICgABNQAECgkJQgAYADAcAA==.',
Tr='Train:BAAANQADCgcIBwAAAA==.Trampadin:BAAANQABCgQIBAAAAA==.Trei:BAAANQADCgIIAgABNQAECgcIDQABAAAAAA==.Trexlot:BAAANQADCgIIAgAAAA==.Trinjal:BAAANQAECgEIAgAAAA==.',
Tu='Tubbylumpkin:BAAANQADCggIDAAAAA==.Tummi:BAAANQADCgcIEAAAAA==.Tumnus:BAAANQAECgEIAQAAAA==.',
Ty='Tyjan:BAAANQAECgIIAwAAAA==.',
['Tâ']='Tâfa:BAAANQADCggICAAAAA==.',
Uh='Uhtred:BAAANQADCgYIBwAAAA==.',
Ul='Ulti:BAABNQAECn8jAAIHAAgKzB0BNACUAgAHAAgKzB0BNACUAgAAAA==.',
Un='Unholydevil:BAAANQAECgIIAgAAAA==.Unholyheart:BAAANQAECgIIAgAAAA==.',
Va='Varthios:BAAANQABCgQIBgAAAA==.Varyusha:BAAANQAECgEIAQAAAA==.',
Ve='Velantra:BAAANQAECggICwAAAA==.Venari:BAABNQAECn8XAAIbAAkK3xOvAwDeAQAbAAkK3xOvAwDeAQAAAA==.',
Vi='Vilelyn:BAAANQAECgUIDwABNQADCgEIAQABAAAAAA==.Viloria:BAABNQAECn8eAAIEAAcKgRaoHgCqAQAEAAcKgRaoHgCqAQAAAA==.Vincent:BAAANQADCgQIBAAAAA==.Virrard:BAABNQAECn8kAAIKAAoK7BdOVAB0AgAKAAoK7BdOVAB0AgAAAA==.',
Vl='Vladimor:BAAANQAECgQIDAAAAA==.Vladimyrr:BAAANQADCgUJCAAAAA==.',
Vo='Voslaarum:BAAANQADCgEIAQABNQAECgUIDgABAAAAAA==.Vozrezz:BAAANQAECgUIDwAAAA==.',
Vu='Vualake:BAAANQADCgMIAwAAAA==.',
['Vë']='Vëda:BAABNQAECn8yAAIOAAoKPiDWGwADAwAOAAoKPiDWGwADAwAAAA==.',
Wa='Waffle:BAAANQAECgIIAwABNQAFFAUIBQAkAPUSAA==.Warage:BAAANQAECgEIAQAAAA==.Warske:BAAANQAECgUIBAAAAA==.',
Wh='Wheaties:BAAANQAECgYICgABNQAECgkJQgAYADAcAA==.Whizzie:BAABNQAECn8yAAIDAAkK7hJ4nwBCAgADAAkK7hJ4nwBCAgAAAA==.Whizzlecrank:BAABNQAECn81AAIDAAkKTBR8pQA2AgADAAkKTBR8pQA2AgAAAA==.',
Wi='Wicker:BAABNQAECn8pAAMRAAkKtRW9QwDlAQARAAcK9xO9QwDlAQAIAAUKHxJhRgD+AAAAAA==.Willpharaoh:BAAANQADCgUICgAAAA==.Wiçker:BAAANQADCgIIAgABNQAECgkJKQARALUVAA==.',
Wo='Wolford:BAAANQADCgYIBgAAAA==.',
Wr='Wras:BAABNQAECn8aAAIYAAYKPRb8VACgAQAYAAYKPRb8VACgAQAAAA==.Wrectt:BAAANQAECgUIDgABNQAECgYICQABAAAAAA==.',
['Wò']='Wòbbles:BAAANQAECgYIDQAAAA==.',
Xa='Xandrah:BAAANQADCgUJBQAAAA==.Xandrel:BAABNQAECn8pAAISAAkK0Q42ggBNAQASAAkK0Q42ggBNAQAAAA==.',
Xe='Xed:BAABNQAECn80AAINAAcKshgdSwBKAgANAAcKshgdSwBKAgAAAA==.Xenogears:BAABNQAECn8mAAIJAAkK2hluEgCaAQAJAAkK2hluEgCaAQAAAA==.',
Xi='Xiansai:BAABNQAECn8rAAIQAAoKWxHbIAAxAgAQAAoKWxHbIAAxAgAAAA==.',
Ya='Yappey:BAAANQAECgcIBwAAAA==.',
Yi='Yippee:BAABNQAECn8bAAINAAkKgB0zGAA+AgANAAkKgB0zGAA+AgAAAA==.',
Yo='Youthinasia:BAAANQAECgUIEAAAAA==.',
Ze='Zerega:BAAANQADCgcIHAABNQAECgoKVQALAGMQAA==.',
Zh='Zhi:BAAANQAECgMIBQAAAA==.Zhukov:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.',
Zo='Zombiehippo:BAABNQAECn8vAAIDAAoKsBe0VwDRAgADAAoKsBe0VwDRAgAAAA==.',
['Áu']='Áutarch:BAAANQAECgYIEAAAAA==.',
['Ðe']='Ðemøn:BAAANQADCggIGQAAAA==.',
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
