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

local lookup = {'Hunter-BeastMastery','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Priest-Holy','Shaman-Restoration','Mage-Frost','Monk-Mistweaver','Unknown-Unknown','Paladin-Holy','Druid-Restoration','DemonHunter-Vengeance','Hunter-Survival','Shaman-Elemental','Monk-Brewmaster','Paladin-Protection','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Blood','Druid-Balance','DemonHunter-Devourer','Monk-Windwalker','Druid-Guardian','Mage-Fire','Druid-Feral','Warrior-Fury','Shaman-Enhancement','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','Priest-Discipline','DemonHunter-Havoc','Hunter-Marksmanship','Warrior-Protection','Mage-Arcane','Rogue-Outlaw','Rogue-Subtlety','DeathKnight-Frost','Rogue-Assassination',}
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abeblinken:BAAALgAECgkJDwAAAA==.Abraaham:BAAALgAECgEJAgAAAA==.',
Ad='Adonas:BAAALgADCgUJBQAAAA==.Adym:BAABLgAECn8ZAAIBAAkJOBnwHABYAgABAAkJOBnwHABYAgAAAA==.',
Ae='Aeralyn:BAAALgAECgQJBAAAAA==.Aermo:BAAALgADCgYJBwAAAA==.Aethoos:BAAALgAECgcJCwABLgAECgkJTwACAC4cAA==.Aethos:BAABLgAECn9PAAQCAAkJLhy+EwCjAgACAAkJLhy+EwCjAgADAAEJ+xcSKwBJAAAEAAIJoBkoMwBDAAAAAA==.Aeyther:BAABLgAECn8WAAMFAAkJghiKGgAKAgAFAAkJghiKGgAKAgAGAAIJgBJVawB+AAAAAA==.',
Ag='Agave:BAACLgAFFH8GAAIHAAIJsgfvXQBrAAAHAAIJsgfvXQBrAAAuAAQKfzoAAgcACQmLFZ0eAD8CAAcACQmLFZ0eAD8CAAAA.Agony:BAAALgAECgQJCQAAAA==.',
Ah='Ahluethedrud:BAAALgADCgUJBQAAAA==.',
Ai='Airbnb:BAAALgADCgQJBAAAAA==.',
Al='Aleynah:BAAALgADCggJIQABLgAECgkJQwAEAC4MAA==.Alukarrd:BAAALgAECgMJBQAAAA==.',
Am='Aminadab:BAAALgADCgYJBgAAAA==.Amnere:BAAALgAECgcJBwABLgAFFAIJBgAGAI8DAA==.Amoraniel:BAABLgAECn8oAAIIAAkJJSPgFQDAAgAIAAkJJSPgFQDAAgAAAA==.Amortin:BAAALgADCgEJAQAAAA==.',
An='Anavar:BAACLgAFFH8JAAIJAAMJgh7qIQAKAQAJAAMJgh7qIQAKAQAuAAQKfyUAAgkACQmqG9UOAGkCAAkACQmqG9UOAGkCAAAA.Ancestral:BAAALgADCgEJAQABLgAECgkJFAAKAAAAAA==.Andrar:BAAALgADCgMJBAAAAA==.Andresra:BAABLgAECn8UAAIIAAcJ3RcZZwAJAgAIAAcJ3RcZZwAJAgAAAA==.Angelle:BAABLgAECn8tAAILAAgJOyTSCgDKAgALAAgJOyTSCgDKAgAAAA==.Annakin:BAABLgAECn8mAAIMAAkJexlEHwA4AgAMAAkJexlEHwA4AgAAAA==.Annaluna:BAAALgAECgYJBwAAAA==.Anomally:BAAALgAECgEJAQAAAA==.Anzhelika:BAAALgADCgMJAwAAAA==.',
Ar='Arararagi:BAAALgAECgYJCwAAAA==.Arawn:BAAALgADCgYJBgAAAA==.Arctica:BAABLgAECn8uAAINAAkJHR7LAwCPAgANAAkJHR7LAwCPAgAAAA==.Arelà:BAAALgAFFAEJAwAAAA==.Aria:BAABLgAECn80AAIJAAkJ6SNGAgCYAwAJAAkJ6SNGAgCYAwAAAA==.Aristoteles:BAAALgAECgIJAwAAAA==.Arron:BAAALgAECgMJBAAAAA==.Arrowsnag:BAABLgAECn8eAAIOAAkJgwh2GgC7AQAOAAkJgwh2GgC7AQAAAA==.Articdemon:BAAALgADCgkJFAAAAA==.Artics:BAAALgAECgEJAQAAAA==.Arya:BAABLgAFFH8FAAIFAAMJSwxlIADLAAAFAAMJSwxlIADLAAABLgAFFAQJCAAPAEMMAA==.Arylynn:BAAALgADCgYJBgABLgAECgkJKAAQANQjAA==.',
As='Asrael:BAAALgAECggJDwABLgAFFAIJBgARAAAZAA==.Astradaeus:BAAALgADCgMJAwAAAA==.Astridaya:BAAALgAECgEJBAAAAA==.',
At='Atish:BAAALgADCgMJAwAAAA==.',
Au='Aunumator:BAAALgAECgYJEQAAAA==.',
Av='Avert:BAAALgAECgEJAQAAAA==.Avâtre:BAABLgAECn8gAAIPAAkJlxN/LAB5AQAPAAkJlxN/LAB5AQAAAA==.',
Az='Azlea:BAAALgAECgMJAwAAAA==.',
Ba='Baba:BAAALgADCgcJAQAAAA==.Baccaj:BAAALgAFFAEJAQAAAA==.Baeblue:BAAALgAECgYJDQABLgAECggJJAASAEQcAA==.Baguette:BAAALgAECgEJAgAAAA==.Bajemobomb:BAAALgAECgEJAQABLgAECgkJJgATAMEfAA==.Bajingobomb:BAABLgAECn8mAAMTAAkJwR8MLwB8AgATAAkJwR8MLwB8AgAUAAEJpREwRgAvAAAAAA==.Baked:BAAALgAECgUJDQAAAA==.Ballmelazer:BAAALgAECgEJAQAAAA==.Barasuishou:BAAALgAECgEJAQABLgAFFAQJEAAFACEeAA==.Barina:BAAALgADCgQJBAAAAA==.Barkruffalo:BAACLgAFFH8MAAIMAAQJ+QkvMADhAAAMAAQJ+QkvMADhAAAuAAQKf0gAAwwACQkYIEcHADUDAAwACQkYIEcHADUDABUABglXFdM0ACoBAAAA.Barktotem:BAAALgADCgQJBAAAAA==.Barkwoven:BAAALgAECgMJBQAAAA==.Barndoogle:BAAALgAECgEJAQAAAA==.Battleborne:BAAALgAECgEJAQAAAA==.Bayln:BAAALgADCgcJBgABLgABCgUJBQAKAAAAAA==.',
Be='Beckyoncé:BAACLgAFFH8GAAIWAAIJWSVUTwDcAAAWAAIJWSVUTwDcAAAuAAQKfzwAAhYACQlfJAYGABkDABYACQlfJAYGABkDAAAA.Bedris:BAABLgAECn8iAAMSAAkJvg6TXwCYAQASAAkJ3g2TXwCYAQARAAUJUAtkKwCyAAAAAA==.Beerticus:BAABLgAECn8gAAIXAAgJLR6CDgBKAgAXAAgJLR6CDgBKAgAAAA==.Bekkar:BAAALgAECgYJDwAAAA==.Belcebu:BAAALgAECgIJBgAAAA==.Berim:BAAALgAECgQJBQAAAA==.',
Bi='Bigdingus:BAABLgAECn8ZAAIYAAkJQB2sBQB8AgAYAAkJQB2sBQB8AgAAAA==.Binggles:BAACLgAFFH8bAAMIAAgJCBodBwDvAQAIAAgJCBodBwDvAQAZAAEJXQHLAQBDAAAuAAQKfyUAAggACAl+JXwSADgDAAgACAl+JXwSADgDAAAA.Bingglestwo:BAAALgAECgMJAwABLgAFFAgJGwAIAAgaAA==.',
Bl='Blackastraza:BAAALgAECgUJBQAAAA==.Blacksheep:BAAALgAECgcJDgAAAA==.Blanketparty:BAABLgAECn8ZAAMPAAgJxhoNHwDRAQAPAAgJxhoNHwDRAQAHAAEJXw9FwgAuAAAAAA==.Blazze:BAAALgAFFAEJAQAAAA==.Blinkyshadow:BAAALgADCgMJAwAAAA==.Bloodraven:BAACLgAFFH8SAAIMAAQJhhmrHgBEAQAMAAQJhhmrHgBEAQAuAAQKf0AAAwwACQl2H68OANACAAwACQl2H68OANACABoAAwmNFcckAL4AAAAA.Bluballs:BAAALgAECgkJDwAAAA==.Bluebabyfox:BAAALgADCgIJAgAAAA==.Blëwm:BAAALgAECgEJAQABLgAECgkJHgAQAG4XAA==.',
Bo='Boaj:BAACLgAFFH8MAAIbAAMJfxNaLwDRAAAbAAMJfxNaLwDRAAAuAAQKfyMAAhsACQk0GZsjAMMBABsACQk0GZsjAMMBAAAA.Bobette:BAABLgAECn8UAAIcAAgJEAg1FQBpAQAcAAgJEAg1FQBpAQAAAA==.Bodyspray:BAABLgAECn8iAAISAAkJBh9EHwB0AgASAAkJBh9EHwB0AgAAAA==.Boolay:BAABLgAECn8fAAIRAAkJliDcBQB3AgARAAkJliDcBQB3AgAAAA==.Boomchickeni:BAAALgAECgYJBwAAAA==.Bootyfire:BAABLgAECn8ZAAIIAAgJ9RF9aAAFAgAIAAgJ9RF9aAAFAgAAAA==.Boozing:BAABLgAECn8fAAIaAAkJ8x7XAgDbAgAaAAkJ8x7XAgDbAgAAAA==.Bopstds:BAAALgAECgEJAQAAAA==.Bosmina:BAACLgAFFH8SAAIGAAQJ6xDOEgAOAQAGAAQJ6xDOEgAOAQAuAAQKfz0AAgYACQnIFMkYAO8BAAYACQnIFMkYAO8BAAAA.Botanicaljoe:BAAALgAECgQJCAAAAA==.',
Br='Braeibo:BAABLgAECn8nAAIBAAkJew+COwDaAQABAAkJew+COwDaAQAAAA==.Breelynn:BAAALgADCgcJBwAAAA==.Breida:BAAALgAECgUJCAAAAA==.Brendalee:BAAALgADCgEJAQAAAA==.Brenmonk:BAABLgAECn8ZAAIXAAgJugsmLgA5AQAXAAgJugsmLgA5AQAAAA==.Brenpriest:BAAALgADCgEJAQAAAA==.Brielle:BAAALgADCgEJAQAAAA==.Broghugin:BAAALgADCgEJAQAAAA==.Brolerion:BAAALgADCgQJBAAAAA==.Bruenor:BAAALgADCgIJAgAAAA==.',
Bu='Bubblebaddie:BAABLgAECn8aAAISAAgJXhMEVQCyAQASAAgJXhMEVQCyAQAAAA==.Bugenhagen:BAAALgAECgUJDwABLgAECgYJDwAKAAAAAA==.Butchers:BAAALgAECgIJAgAAAA==.Buttpaladin:BAABLgAECn8gAAISAAgJLSRYEwC6AgASAAgJLSRYEwC6AgAAAA==.',
['Bë']='Bëldin:BAAALgADCggJCwAAAA==.',
Ca='Canelo:BAAALgADCgUJBQAAAA==.Cantheal:BAAALgADCgYJBgAAAA==.Carademuerta:BAAALgAECgcJEAAAAA==.Cavos:BAABLgAECn8wAAIWAAkJDxmCJQAiAgAWAAkJDxmCJQAiAgAAAA==.',
Ce='Cernsarn:BAACLgAFFH8GAAIUAAIJixZlJwCFAAAUAAIJixZlJwCFAAAuAAQKfzsAAhQACQnmF8EMACUCABQACQnmF8EMACUCAAAA.',
Ch='Chandlef:BAAALgAECgQJBAAAAA==.Chantorc:BAAALgADCgYJCgAAAA==.Chickendad:BAAALgAECgUJBQAAAA==.Chigang:BAAALgADCgMJAwAAAA==.Chiri:BAEBLgAECn8iAAQdAAkJZBH+CACIAQAdAAgJZxD+CACIAQAeAAYJdQuPNQAkAQAfAAcJtg4bIQDUAAAAAA==.Chocc:BAAALgADCgMJAwAAAA==.Chvngus:BAABLgAECn8mAAISAAkJ0h95FwCgAgASAAkJ0h95FwCgAgAAAA==.',
Ci='Cindersam:BAAALgAECgYJCQABLgAECgcJFAATALYUAA==.',
Cl='Clawsoh:BAAALgAECgEJAQAAAA==.Climene:BAAALgAECgEJAQABLgAECggJJAASAEQcAA==.',
Co='Cocheeze:BAAALgAECgUJCQAAAA==.Coffeebeen:BAAALgAECgcJBwAAAA==.Condor:BAECLgAFFH8KAAIVAAQJSx16FABJAQAVAAQJSx16FABJAQAuAAQKfx0AAhUACQlBJYcDACADABUACQlBJYcDACADAAAA.Conmammoth:BAAALgAECgQJCgAAAA==.Coohwhip:BAAALgAECgcJEAAAAA==.Cowwithhorns:BAABLgAECn8fAAMbAAkJIRVlKgAPAgAbAAgJIhJlKgAPAgAgAAUJVhNcJAArAQAAAA==.',
Cr='Crakidos:BAAALgAECgQJBQAAAA==.Crinaa:BAAALgAECgEJAQAAAA==.Cristobal:BAAALgAECgkJEAAAAA==.Cronùs:BAAALgAECggJDAAAAA==.Crunkshot:BAABLgAECn8bAAMSAAcJLwONugARAQASAAcJLwONugARAQALAAcJEQQ2XQClAAAAAA==.',
Cu='Curaga:BAAALgAECgYJBgAAAA==.Curnsarn:BAAALgAECgcJDgABLgAFFAIJBgAUAIsWAA==.Curtis:BAABLgAECn8UAAQGAAcJ9Q14PwA8AQAGAAcJ9Q14PwA8AQAFAAMJsxWDRwDEAAAhAAEJEAP1dQAkAAAAAA==.',
Cy='Cyalaterz:BAAALgAECgEJAQAAAA==.Cyrail:BAABLgAECn8uAAILAAkJviOHBQATAwALAAkJviOHBQATAwAAAA==.',
['Cø']='Cøven:BAACLgAFFH8QAAMMAAQJgRdGNADNAAAMAAMJERNGNADNAAAVAAMJSw7dKAC+AAAuAAQKfzgAAxUACQnWHi0JAK0CABUACQnWHi0JAK0CAAwABAmQEGWdAJAAAAAA.',
Da='Daenérys:BAAALgAECgIJAgAAAA==.Dahfool:BAAALgAECgYJBgAAAA==.Dan:BAAALgAECgEJAQAAAA==.Dapöpe:BAAALgADCgcJDQABLgAECggJHgASANkWAA==.Darkmonks:BAAALgAECgYJCwAAAA==.Darksoulstwo:BAAALgAECgYJDAAAAA==.Darktoxi:BAABLgAECn8hAAIJAAgJ0BrIFgA/AgAJAAgJ0BrIFgA/AgABLgAECgkJLgAWAAYaAA==.Darkwarden:BAAALgADCgEJAQAAAA==.Darthpooper:BAAALgAECgYJBgABLgAFFAMJCwASAGoXAA==.Dashawmon:BAAALgADCgcJBwABLgADCgcJFAAKAAAAAA==.Dashel:BAAALgAECgIJAgABLgAFFAIJBgAGAI8DAA==.Dastaan:BAAALgAECgEJAgAAAA==.Dauntus:BAACLgAFFH8aAAIIAAcJohUJEwASAgAIAAcJohUJEwASAgAuAAQKfzcAAggACQntI5oJABoDAAgACQntI5oJABoDAAAA.Dawnclaw:BAAALgADCgUJBQAAAA==.Daydream:BAAALgAECgEJAQAAAA==.',
De='Deathclock:BAACLgAFFH8FAAITAAIJPRQvsQCSAAATAAIJPRQvsQCSAAAuAAQKfy0AAhMACQlZIBUNADIDABMACQlZIBUNADIDAAAA.Deegey:BAAALgAECgIJAwAAAA==.Deep:BAAALgADCgEJAQAAAA==.Degey:BAAALgAECgYJEAAAAA==.Deign:BAACLgAFFH8PAAIiAAQJawHgFwCnAAAiAAQJawHgFwCnAAAuAAQKfzUAAiIACQnyDRkaAI4BACIACQnyDRkaAI4BAAAA.Delayne:BAAALgAECggJCQAAAA==.Demoncrat:BAAALgAFFAEJAQAAAA==.Demonicramen:BAAALgAECgIJAgAAAA==.Demonstroza:BAAALgAECgUJBQABLgAECgkJEQAKAAAAAA==.Demontotems:BAAALgAECgQJCgAAAA==.Demotoxi:BAABLgAECn8uAAIWAAkJBhoJHABYAgAWAAkJBhoJHABYAgAAAA==.Deriso:BAABLgAECn8WAAMBAAkJMiPeGAB6AgABAAgJkCLeGAB6AgAjAAYJ9R43KwDTAQAAAA==.Derpthyr:BAAALgADCgMJAwAAAA==.Destrozar:BAAALgAECgMJAwABLgAECgkJEQAKAAAAAA==.Destrozinth:BAAALgAECgkJEQAAAA==.Dethorok:BAABLgAECn8tAAQOAAkJBCTOAQAuAwAOAAkJsCPOAQAuAwAjAAYJjSTzIgAPAgABAAUJlCBqegAxAQAAAA==.Deuce:BAAALgAECgQJBQAAAA==.Deåth:BAABLgAFFH8HAAITAAMJaQnglADEAAATAAMJaQnglADEAAAAAA==.',
Dh='Dhamon:BAAALgADCgYJBgAAAA==.',
Di='Diagonpally:BAAALgAECgMJAwABLgAECgYJDwAKAAAAAA==.Dib:BAAALgAECgUJBQABLgAFFAMJBwACAMUYAA==.Diccem:BAAALgAECgcJDAABLgAECgkJKAABAJ8gAA==.Dieworc:BAAALgADCgkJFgAAAA==.Digey:BAABLgAECn8WAAIkAAkJtiJaBgDLAgAkAAkJtiJaBgDLAgAAAA==.Digitz:BAABLgAECn8cAAMIAAgJTBYEVwAzAgAIAAgJTBYEVwAzAgAlAAEJAABAHgA1AAAAAA==.Direwolf:BAAALgAECgUJBgAAAA==.Dirtnapp:BAAALgAECgMJCAAAAA==.Divah:BAABLgAECn9DAAIEAAkJLgzzCwBiAQAEAAkJLgzzCwBiAQAAAA==.Divinelight:BAAALgAECgEJAgAAAA==.',
Do='Dogehh:BAAALgADCgIJAgAAAA==.Dogèhh:BAAALgAECgUJBQAAAA==.Donald:BAABLgAECn8hAAIBAAkJEhL1NQDuAQABAAkJEhL1NQDuAQAAAA==.Donbolo:BAAALgAFFAEJAgAAAA==.Dontlookatme:BAAALgAECgEJAQAAAA==.Dopeaf:BAABLgAECn8dAAMkAAgJFhYfEADOAQAkAAgJFhYfEADOAQAbAAEJiAI0sQApAAAAAA==.Dotpotato:BAAALgADCgIJAgAAAA==.Dotterparty:BAAALgAFFAEJAQAAAA==.Dottër:BAAALgAECgIJAgABLgAFFAMJBwATAGkJAA==.Dowkia:BAAALgAECgEJBAAAAA==.Downwarddog:BAAALgADCgYJBwAAAA==.',
Dr='Dragonmaas:BAAALgADCgYJBgAAAA==.Dragonwings:BAECLgAFFH8SAAIIAAQJUAr/XgASAQAIAAQJUAr/XgASAQAuAAQKfxsAAggABwk7Ft19ANUBAAgABwk7Ft19ANUBAAAA.Drakah:BAAALgAECgIJAgAAAA==.Drakbek:BAABLgAECn8WAAIYAAcJUhaEFgB7AQAYAAcJUhaEFgB7AQAAAA==.Dreaknite:BAAALgADCgQJBgAAAA==.Dreamshift:BAABLgAECn8eAAMMAAgJZBuvJgAGAgAMAAgJZBuvJgAGAgAVAAIJbQevcgBKAAAAAA==.Dreco:BAABLgAECn8dAAIWAAcJrh6vJQBxAgAWAAcJrh6vJQBxAgAAAA==.Drekken:BAAALgAECgMJBQAAAA==.Drelik:BAAALgADCgIJAgAAAA==.Dronebot:BAABLgAECn80AAMFAAkJqiPyAwAJAwAFAAkJqiPyAwAJAwAGAAMJngpuZwCPAAAAAA==.Drucifer:BAABLgAECn8aAAIcAAcJBRPoEgBnAQAcAAcJBRPoEgBnAQAAAA==.Druelf:BAAALgAECgMJBAAAAA==.Druiwny:BAAALgAECgMJAwAAAA==.Drék:BAABLgAECn8bAAIEAAYJxRQ5DwAyAQAEAAYJxRQ5DwAyAQAAAA==.Drúcifer:BAAALgAECgEJAQAAAA==.',
Du='Dud:BAABLgAECn8jAAICAAgJoR1jKQAnAgACAAgJoR1jKQAnAgAAAA==.Duelme:BAAALgAECgMJBQABLgAECggJHQAkABYWAA==.Dugaa:BAAALgAECgQJBAAAAA==.Dumbdwagon:BAACLgAFFH8GAAIfAAIJiAiVIgBtAAAfAAIJiAiVIgBtAAAuAAQKfygAAh8ACQnVDY4PAMABAB8ACQnVDY4PAMABAAAA.Dumblecrumb:BAAALgADCgQJBAABLgAECgEJAQAKAAAAAA==.Dumbrouge:BAAALgAECgIJAwABLgAFFAIJBgARAAAZAA==.Durumi:BAAALgAECgEJAQAAAA==.Dustyshotz:BAAALgAECgYJDgAAAA==.',
Dw='Dwall:BAAALgAECgMJAwAAAA==.Dwarfgasm:BAAALgAECgkJAQAAAA==.Dwarfladin:BAAALgAECgEJAQAAAA==.Dwarriorarf:BAAALgAECgQJBgAAAA==.',
Dz='Dzieux:BAAALgADCgYJBwAAAA==.',
['Dë']='Dëadisbetter:BAAALgADCgEJAQAAAA==.',
['Dò']='Dògehh:BAAALgAECgIJAgAAAA==.',
['Dö']='Dögehh:BAABLgAECn8VAAMBAAcJyRUxewAwAQAOAAYJCRCtKgA8AQABAAYJaxYxewAwAQAAAA==.',
['Dø']='Døgehh:BAAALgAECgEJAQAAAA==.',
Ee='Eeseo:BAAALgAECgEJAgAAAA==.',
Eg='Eggblack:BAAALgAECgQJCgAAAA==.',
Ei='Eillei:BAAALgAECgEJAgAAAA==.',
El='Ellegryn:BAAALgADCgEJAgAAAA==.Elvebring:BAABLgAECn8cAAIiAAcJsBsrGQD8AQAiAAcJsBsrGQD8AQABLgAFFAMJCAALAFYaAA==.',
Em='Embody:BAABLgAECn8cAAIVAAgJfREVKAB1AQAVAAgJfREVKAB1AQAAAA==.Emilio:BAAALgAECgEJAgAAAA==.',
En='Endlyss:BAAALgAECgUJBQAAAA==.',
Er='Erikira:BAABLgAECn8gAAQbAAgJ5xP2JgCtAQAbAAgJRhL2JgCtAQAgAAUJZQ3HSwB9AAAkAAEJ3hOrSQA4AAAAAA==.Erikk:BAABLgAECn8dAAITAAgJSQo3egBZAQATAAgJSQo3egBZAQAAAA==.Eryngium:BAABLgAECn8iAAIMAAgJfBtlHQBHAgAMAAgJfBtlHQBHAgAAAA==.',
Es='Essentia:BAAALgAECgEJAQAAAA==.',
Et='Ethantherat:BAAALgAECgEJAQAAAA==.',
Eu='Euphoricx:BAACLgAFFH8QAAIHAAQJIhndIABCAQAHAAQJIhndIABCAQAuAAQKfzUAAgcACQlIJvcCAE4DAAcACQlIJvcCAE4DAAAA.',
Ev='Evildeader:BAABLgAECn8UAAITAAcJehPGdgCYAQATAAcJehPGdgCYAQAAAA==.Eviltotems:BAAALgAECgQJBQABLgAECgcJFAATAHoTAA==.',
Ex='Exalt:BAAALgAECgcJEwAAAA==.Exes:BAAALgADCggJCAABLgAFFAQJCAAPAEMMAA==.Expand:BAABLgAECn8WAAIXAAkJSBrcFQA7AgAXAAkJSBrcFQA7AgAAAA==.Explouzi:BAAALgADCgEJAQAAAA==.',
Ey='Eyeseyesbaby:BAABLgAECn8aAAIWAAkJKhzjKAARAgAWAAkJKhzjKAARAgAAAA==.',
Ez='Ezbakeovens:BAAALgAFFAIJBAAAAA==.',
Fa='Facelift:BAAALgAECgEJAgAAAA==.Faithles:BAACLgAFFH8PAAIFAAQJLQ/NFwAVAQAFAAQJLQ/NFwAVAQAuAAQKfzMAAgUACQk+HqYIAKwCAAUACQk+HqYIAKwCAAAA.Falgur:BAACLgAFFH8SAAMPAAQJ6BVGKgDKAAAPAAMJ1hFGKgDKAAAHAAQJqwPmQADGAAAuAAQKfz4AAw8ACQkZIjkFAPwCAA8ACQkZIjkFAPwCAAcABAlGELFvAO0AAAAA.Fallenlord:BAAALgADCgcJBwAAAA==.Fantasma:BAABLgAECn8XAAITAAcJVgwgigA7AQATAAcJVgwgigA7AQAAAA==.Fasty:BAABLgAECn8mAAIJAAkJRRToHgC9AQAJAAkJRRToHgC9AQAAAA==.Faygochugger:BAAALgAFFAEJAQAAAA==.',
Fe='Fear:BAAALgAECgYJCgAAAA==.Felmajik:BAAALgADCgMJBQAAAA==.Ferous:BAAALgAECgYJBgAAAA==.',
Fi='Fifths:BAAALgAECgUJBwAAAA==.Findal:BAAALgAECgEJAQABLgABCgUJBAAKAAAAAA==.Finley:BAAALgADCgMJAwAAAA==.Fivemagics:BAABLgAECn8eAAMCAAkJ0RmFNgDyAQACAAgJ0RmFNgDyAQAEAAIJmBTSTgCBAAAAAA==.',
Fl='Flayvour:BAAALgAECgcJEAABLgAECgkJHgAQAG4XAA==.Fleaboy:BAABLgAECn8YAAMmAAYJahWmCwBHAQAmAAYJahWmCwBHAQAnAAQJMgYITwCzAAAAAA==.Fleshwound:BAAALgADCgYJBgAAAA==.Flist:BAACLgAFFH8GAAIXAAIJ/yXbGgDfAAAXAAIJ/yXbGgDfAAAuAAQKfyQAAhcACQl4JNUDABEDABcACQl4JNUDABEDAAAA.',
Fo='Fongsaiyok:BAAALgAECgEJAwAAAA==.Foregord:BAAALgADCgUJBQABLgABCgUJBQAKAAAAAA==.Fortlock:BAAALgAECgQJCwAAAA==.Fotation:BAAALgAECgQJBAAAAA==.',
Fr='Frankensteyn:BAAALgADCgkJCQAAAA==.Frankyice:BAABLgAECn8eAAIFAAkJ5A9dIACkAQAFAAkJ5A9dIACkAQAAAA==.Freesia:BAABLgAECn8aAAISAAYJWRAbkABcAQASAAYJWRAbkABcAQAAAA==.French:BAAALgAECggJDQAAAA==.Froggyfresh:BAAALgADCgYJCAAAAA==.Fruitjuice:BAABLgAECn8ZAAIEAAYJTRwpCgCEAQAEAAYJTRwpCgCEAQAAAA==.',
Fu='Funbobby:BAAALgAECgUJBgAAAA==.',
Fx='Fxce:BAAALgAECgcJDwAAAA==.',
['Fâ']='Fâmine:BAACLgAFFH8GAAICAAMJ4gg2cADKAAACAAMJ4gg2cADKAAAuAAQKfyIAAgIACQktFSYxAAgCAAIACQktFSYxAAgCAAAA.',
Ga='Galautee:BAAALgAECgEJAQAAAA==.Gamakichi:BAAALgAECgEJAQAAAA==.Gambitt:BAAALgADCgUJBQAAAA==.Gamer:BAAALgADCgcJDAABLgAECgYJDgAKAAAAAA==.Gamergirl:BAAALgAECgYJDgAAAA==.Ganjj:BAAALgAECgEJAQAAAA==.Gawdric:BAACLgAFFH8YAAMTAAYJJh5MJwCQAQATAAUJJh5MJwCQAQAUAAMJigPgLABdAAAuAAQKfx8AAxMACAlWIZwsAIYCABMACAlWIZwsAIYCACgAAQnOC00YAC4AAAAA.',
Gb='Gboozing:BAAALgAECgkJCQABLgAECgkJHwAaAPMeAA==.',
Ge='Geekminator:BAAALgAECgQJBAAAAA==.Georgesoros:BAABLgAECn8WAAQeAAkJNR1gGgD4AQAeAAgJNR1gGgD4AQAdAAEJAACCOQBOAAAfAAIJuAH8NQA5AAAAAA==.',
Gh='Ghibludgeon:BAAALgADCgIJAgAAAA==.Ghiboom:BAAALgAECgEJAgAAAA==.Ghulz:BAABLgAECn8nAAMDAAgJSRlGBwDdAQADAAcJxRpGBwDdAQACAAgJ7QtHawBaAQAAAA==.Ghuntarr:BAAALgADCgcJDAAAAA==.',
Gi='Gibsmedats:BAABLgAECn8fAAMWAAkJ1BJ3QgDqAQAWAAgJkRJ3QgDqAQAiAAMJFhEzOQCxAAAAAA==.Giin:BAAALgAECgYJCAAAAA==.Gildark:BAAALgADCgEJAQAAAA==.',
Gl='Glaiven:BAABLgAECn8TAAIWAAcJMiDFHgCZAgAWAAcJMiDFHgCZAgAAAA==.Glasscleaner:BAAALgAECgcJEQABLgAFFAQJEwAJAHEmAA==.Glenfarclas:BAAALgAECgYJCgAAAA==.Glenfiddich:BAABLgAECn8hAAITAAkJkiGEGwCOAgATAAkJkiGEGwCOAgAAAA==.Glenmorangie:BAAALgAECgQJBAAAAA==.Glupek:BAAALgAECgEJAQAAAA==.',
Gn='Gnartusk:BAABLgAECn8zAAIUAAkJWCV8AQBDAwAUAAkJWCV8AQBDAwAAAA==.Gnomett:BAAALgADCgEJAQAAAA==.',
Go='Goblinsham:BAAALgAECgEJAQAAAA==.Gordrack:BAAALgAFFAIJAgAAAA==.',
Gr='Grandmapunch:BAAALgADCgIJAgABLgAECgcJFAAGAPUNAA==.Grasswizard:BAAALgAECggJEQAAAA==.Greela:BAAALgAECgEJAQAAAA==.Greens:BAACLgAFFH8LAAIVAAMJfBOEKADBAAAVAAMJfBOEKADBAAAuAAQKfyYAAhUABwmfGwYcANABABUABwmfGwYcANABAAAA.Gremory:BAAALgADCgYJBwAAAA==.Gru:BAAALgAECggJDgAAAA==.Grïma:BAAALgADCggJFAABLgAFFAQJEAAMAIEXAA==.',
Gu='Gueritestje:BAABLgAECn85AAIRAAkJ8yNsAQApAwARAAkJ8yNsAQApAwAAAA==.Guzzlord:BAAALgAECgkJEwAAAA==.',
Ha='Hairinear:BAAALgAECgEJAQAAAA==.Hambo:BAAALgAECgkJBQAAAA==.Handsomejack:BAAALgAECgEJAQABLgAECgkJJgATAMEfAA==.Hanekawa:BAAALgAECgUJBwABLgAFFAQJEAAFACEeAA==.Harddwarf:BAAALgAECgEJAQAAAA==.Haugcraneka:BAAALgADCgYJBgAAAA==.Hawts:BAAALgAECgEJAQAAAA==.',
He='Heleous:BAABLgAECn8kAAMSAAgJRBxFPAD7AQASAAgJRBxFPAD7AQARAAEJHg47RAAuAAAAAA==.Hexxedk:BAAALgAECgcJDgAAAA==.',
Hi='Hibernus:BAAALgADCgUJCQABLgAECggJHgASANkWAA==.Highly:BAAALgADCgIJAgAAAA==.Hikari:BAABLgAECn9GAAIiAAkJWBX6EAD6AQAiAAkJWBX6EAD6AQAAAA==.Himalayanman:BAAALgAECgkJDgABLgAFFAcJDQAJAHAWAA==.Hipdrop:BAAALgAECgEJAQAAAA==.Hitemup:BAAALgAECgEJBwAAAA==.Hitoshura:BAACLgAFFH8GAAMoAAIJFSX8EADSAAAoAAIJFSX8EADSAAATAAEJNBXH4ABJAAAuAAQKfygAAygACAmiJNYCAKQCACgACAk2JNYCAKQCABMABglmJHpEAOIBAAAA.',
Ho='Hobbeswerth:BAABLgAECn8UAAIJAAYJEhCMNQAZAQAJAAYJEhCMNQAZAQAAAA==.Holycowbun:BAAALgAECgUJEwABLgAFFAIJBgAWAIQdAA==.Holyginger:BAAALgAECggJCwAAAA==.Holyglizzy:BAABLgAECn80AAISAAgJvhzpKABGAgASAAgJvhzpKABGAgAAAA==.Holysoup:BAAALgAECgEJAQAAAA==.Hornlet:BAAALgAECgEJAQABLgAECgIJBAAKAAAAAA==.Howitzerx:BAAALgAECgQJCQAAAA==.',
Hu='Hubbabubba:BAAALgAFFAEJAQAAAA==.Huggies:BAABLgAECn8YAAMRAAgJsiE8CQAiAgARAAcJGSE8CQAiAgASAAIJWCG23gDBAAAAAA==.Humdinger:BAAALgADCgYJCAAAAA==.Hush:BAAALgAECgMJAgAAAA==.Hushed:BAAALgAECgYJBgAAAA==.',
Hy='Hypérîon:BAAALgAFFAIJBAAAAA==.',
Ia='Iagging:BAACLgAFFH8TAAIJAAQJcSYxEAC8AQAJAAQJcSYxEAC8AQAuAAQKfzsAAgkACQkbJjgCAJoDAAkACQkbJjgCAJoDAAAA.',
Ib='Ibodan:BAAALgAECgUJCQAAAA==.',
Ic='Iceflinger:BAABLgAECn8xAAIIAAkJdBzPGQCpAgAIAAkJdBzPGQCpAgAAAA==.',
Id='Idjit:BAAALgAECgMJAwABLgAECgYJDwAKAAAAAA==.Idlehand:BAAALgAECgYJDAAAAA==.',
Ie='Ieatcats:BAACLgAFFH8SAAInAAQJXxJiFwA7AQAnAAQJXxJiFwA7AQAuAAQKfzYAAicACQmoHo0LAFQCACcACQmoHo0LAFQCAAAA.',
Ih='Ihuntdads:BAAALgAECgMJAwAAAA==.',
Il='Ilidia:BAAALgAECgEJAQAAAA==.',
Im='Imarri:BAAALgADCgYJCAAAAA==.Imjustakid:BAAALgADCgMJAwAAAA==.Immahuntyou:BAAALgAECgEJBwAAAA==.Imobelle:BAABLgAECn8hAAIIAAcJPhXTggDMAQAIAAcJPhXTggDMAQAAAA==.Imprepared:BAAALgAECgYJDgAAAA==.',
In='Indrani:BAABLgAECn8gAAIJAAgJZhw0EQB3AgAJAAgJZhw0EQB3AgAAAA==.Infidel:BAAALgAECgMJAwABLgAFFAYJEQAIALcOAA==.Innogen:BAAALgAECgcJBwAAAA==.',
Ip='Ippiekiyaymf:BAABLgAECn8cAAIFAAcJLxQhKgBhAQAFAAcJLxQhKgBhAQAAAA==.',
Ir='Irayne:BAABLgAECn8YAAMRAAkJRxumCwDzAQARAAYJPx2mCwDzAQASAAgJsBHHXgCaAQAAAA==.Irisharcher:BAAALgAECgQJCQAAAA==.Irishfury:BAAALgAECgEJAwAAAA==.Irishman:BAAALgAECgYJCgAAAA==.',
Is='Ishooturface:BAABLgAECn8ZAAMBAAkJhhmaLAAUAgABAAkJhhmaLAAUAgAjAAYJ3g1aRQBAAQAAAA==.István:BAAALgADCgcJDQAAAA==.',
It='Itazki:BAACLgAFFH8GAAMaAAMJ7xipCQDyAAAaAAMJ7xipCQDyAAAMAAEJGQJGbAAtAAAuAAQKfyAABBoACQnAIn4DAMACABoACQnAIn4DAMACABUAAQkzDTOGACoAAAwAAQltCOvYACQAAAAA.',
Ja='Jardabeans:BAAALgAECgQJCAAAAA==.Jarjárßlinks:BAABLgAECn8bAAIIAAYJgBGXmgApAQAIAAYJgBGXmgApAQAAAA==.Jawz:BAAALgAECgMJBQAAAA==.',
Jc='Jconcepts:BAAALgAECgYJCQABLgAECgkJJgAJAEUUAA==.',
Je='Jediknight:BAAALgAECgEJAQAAAA==.Jeff:BAAALgADCgMJAgAAAA==.Jelial:BAAALgAECgcJBwAAAA==.Jenga:BAAALgAECggJDgAAAA==.Jergal:BAAALgADCgkJCQAAAA==.Jerriblank:BAAALgADCgcJCAAAAA==.',
Jf='Jf:BAACLgAFFH8KAAISAAQJgwZgSgD8AAASAAQJgwZgSgD8AAAuAAQKfxsABBIACQmaFNo/AO8BABIACQmaFNo/AO8BAAsABAnCCDFfAJwAABEAAQnqFXBGADYAAAAA.',
Ji='Ji:BAABLgAECn8wAAIXAAgJOxiOFgA0AgAXAAgJOxiOFgA0AgAAAA==.Jibbage:BAACLgAFFH8RAAIIAAYJtw5CDwCeAQAIAAYJtw5CDwCeAQAuAAQKfzMAAggACQlOIjsKAHIDAAgACQlOIjsKAHIDAAAA.Jinkala:BAAALgAECgEJAQAAAA==.Jitzakkal:BAACLgAFFH8gAAMCAAcJEyW+DQAAAgACAAYJoyW+DQAAAgAEAAIJgCTQCwC8AAAuAAQKfyQAAwQACQmKJSYFAIgCAAIACQmNIyEVANYCAAQABgmTJSYFAIgCAAAA.',
Jo='Johnpaladin:BAABLgAECn8hAAIRAAgJgh8nBADIAgARAAgJgh8nBADIAgAAAA==.Joshswims:BAABLgAECn8hAAMTAAkJAhbaPAD7AQATAAkJAhbaPAD7AQAoAAQJARCxDQDRAAAAAA==.',
Js='Js:BAAALgAECgYJBgAAAA==.',
Ju='Judgemênt:BAAALgAECgUJCQAAAA==.Jussie:BAAALgAECgEJAgAAAA==.',
Ka='Kadriel:BAAALgADCgEJAQAAAA==.Kaiserblade:BAAALgAECgQJBAABLgAECgkJMwAUAFglAA==.Kalgard:BAAALgAECgIJAwABLgAECgkJJgAJAEUUAA==.Kambo:BAAALgAECgEJBAAAAA==.Kaptainkushh:BAAALgAECgQJEAAAAA==.Kaptkush:BAAALgAECgQJCQAAAA==.Kardinal:BAACLgAFFH8LAAMCAAMJfB79WQD6AAACAAMJfB79WQD6AAADAAEJoBh4GQBTAAAuAAQKfzAABAIACQkPIjYSAOoCAAIACQkPIjYSAOoCAAQAAwmhH8gsAAsBAAMAAQmDHqwrAFYAAAAA.Kargan:BAAALgADCgkJDgABLgAECggJHgASANkWAA==.Karig:BAAALgADCgQJBQAAAA==.Karpathous:BAABLgAECn8UAAIBAAYJ6gn0mADyAAABAAYJ6gn0mADyAAAAAA==.Karrag:BAAALgAECgEJAQAAAA==.Karzo:BAAALgAECggJCQAAAA==.Kasawraa:BAAALgAECgUJBQAAAA==.Katena:BAAALgAECgYJDwAAAA==.Kaymir:BAABLgAECn8yAAQhAAkJkhotEgA1AgAhAAkJ3RctEgA1AgAGAAMJyhxoVQDhAAAFAAQJ3Q/aUACkAAAAAA==.Kazdruid:BAAALgAECgYJCgAAAA==.Kaznathi:BAABLgAECn8oAAIQAAkJ1CP4AgAbAwAQAAkJ1CP4AgAbAwAAAA==.',
Ke='Keladorn:BAABLgAECn8sAAISAAgJfh9zJwBNAgASAAgJfh9zJwBNAgAAAA==.Keloril:BAAALgAECgQJCgAAAA==.',
Kh='Khanyiso:BAACLgAFFH8GAAIRAAIJABkQDACbAAARAAIJABkQDACbAAAuAAQKfywAAhEACQnuFBoLAP0BABEACQnuFBoLAP0BAAAA.Kharak:BAABLgAECn8eAAIIAAgJwRFMdQB0AQAIAAgJwRFMdQB0AQABLgABCgUJBAAKAAAAAA==.',
Ki='Kieran:BAACLgAFFH8GAAMGAAIJjwNDKQBbAAAGAAIJjwNDKQBbAAAFAAEJcwMKNQA7AAAuAAQKfzEAAwUACQnfDkojAI4BAAUACAmGEEojAI4BAAYACQlwCAkuAEUBAAAA.Kikimora:BAACLgAFFH8GAAIDAAIJKCKsCADEAAADAAIJKCKsCADEAAAuAAQKfywABAMACQkRIM4CAH8CAAMACQkRIM4CAH8CAAIABgmyGq5TAJUBAAQAAgmbF29IAJUAAAAA.Killsaurus:BAACLgAFFH8cAAIFAAUJ+xwTDwBYAQAFAAUJ+xwTDwBYAQAuAAQKfy4AAgUACAmsIGgRAC4CAAUACAmsIGgRAC4CAAAA.Kilsaurus:BAAALgAECgQJBAAAAA==.Kirkyperky:BAAALgAECgMJAwAAAA==.Kismete:BAABLgAECn8gAAIeAAgJswbPRwDoAAAeAAgJswbPRwDoAAAAAA==.Kismetx:BAABLgAECn8nAAMVAAgJpg4mLQBUAQAVAAgJpg4mLQBUAQAMAAMJSgKS3gAhAAAAAA==.Kittysmasher:BAAALgAECgQJBAAAAA==.Kiue:BAAALgADCgEJAQAAAA==.',
Kn='Knomtseb:BAAALgADCgcJDgAAAA==.',
Ko='Koa:BAAALgAECgUJBwAAAA==.Koey:BAAALgAECgQJDAAAAA==.Korsho:BAAALgAECgEJAQAAAA==.Kosuke:BAAALgADCgUJBQAAAA==.',
Kr='Kriep:BAAALgAECgEJAgAAAA==.Kristian:BAAALgADCgcJBwAAAA==.Krittykitkat:BAAALgAECgkJDQABLgAFFAMJCQAJAIIeAA==.Krixos:BAAALgAECgYJCAABLgAFFAcJGgAIAKIVAA==.Kroshka:BAAALgADCgEJAQAAAA==.Krìt:BAAALgAECgUJBQABLgAECgkJMgATADUfAA==.',
Kw='Kwarrior:BAAALgAECgEJAQABLgAECggJFwACABIVAA==.Kwazlock:BAABLgAECn8XAAMCAAgJEhX+hAAlAQACAAcJcxL+hAAlAQAEAAMJ2A5NQgCsAAAAAA==.',
Ky='Kybalion:BAAALgAECgQJBwABLgAECgUJDAAKAAAAAA==.Kyoju:BAABLgAECn8YAAIIAAcJwQsNqgAQAQAIAAcJwQsNqgAQAQABLgAFFAEJAQAKAAAAAA==.',
La='Laprimera:BAABLgAECn8sAAIiAAcJmQzAJwAXAQAiAAcJmQzAJwAXAQAAAA==.Lara:BAAALgAECgQJCwAAAA==.Lazyjade:BAABLgAECn8mAAIFAAgJGxCfJgB3AQAFAAgJGxCfJgB3AQAAAA==.',
Le='Leyskrodan:BAABLgAECn81AAMFAAkJthDWGwDJAQAFAAkJthDWGwDJAQAGAAEJKQMkiQAlAAAAAA==.',
Li='Lichborne:BAAALgAECgUJDwAAAA==.Lift:BAAALgADCggJCAABLgAECgkJFAAKAAAAAA==.Lightmilk:BAAALgADCgkJDwAAAA==.Lilgash:BAAALgADCgcJBwABLgAECgYJEgAKAAAAAA==.Listel:BAAALgADCgUJBQAAAA==.Livalil:BAAALgADCgcJBwAAAA==.Lizardos:BAAALgAECgkJCgAAAA==.',
Lm='Lmnpeprstepr:BAAALgAECgEJAgAAAA==.',
Lo='Lockofdirish:BAAALgAECgUJBQAAAA==.Lockrocksftw:BAAALgADCgMJAwAAAA==.Lorynn:BAAALgAECgYJCgAAAA==.',
Lu='Lucyna:BAABLgAECn8uAAQCAAkJCB9nGACFAgACAAgJ0R1nGACFAgAEAAUJBh03EwCxAQADAAEJAABVIABxAAAAAA==.Lueshen:BAABLgAECn8bAAIXAAcJDx6zFABHAgAXAAcJDx6zFABHAgAAAA==.Luniea:BAAALgAECgEJAgAAAA==.',
Ly='Lysergicburn:BAAALgAECgQJBAABLgAECgYJDAAKAAAAAA==.Lyshin:BAAALgAECgQJBQAAAA==.',
['Lá']='Lárz:BAAALgAECgIJAwAAAA==.',
['Lí']='Líon:BAAALgADCggJDgABLgAECggJHgASANkWAA==.',
['Lü']='Lüktar:BAAALgADCgYJBgAAAA==.',
Ma='Madmarsh:BAAALgAECgQJBwABLgAECgkJEwAKAAAAAA==.Madwe:BAABLgAECn8cAAITAAkJChnDRwDYAQATAAkJChnDRwDYAQAAAA==.Magdalari:BAAALgAECgQJBQAAAA==.Maggams:BAAALgAECgEJAgAAAA==.Magnaur:BAAALgADCgcJDgAAAA==.Magturri:BAABLgAECn8mAAMBAAkJ4SKuCQD8AgABAAkJ4SKuCQD8AgAjAAIJihBMdgBmAAAAAA==.Mahilo:BAAALgAECgEJAQAAAA==.Maineck:BAACLgAFFH8QAAIPAAQJeBWAGwAaAQAPAAQJeBWAGwAaAQAuAAQKfzUAAg8ACQnTHnsPAGUCAA8ACQnTHnsPAGUCAAAA.Maketaori:BAAALgADCgYJDAAAAA==.Malüm:BAAALgADCgcJCgABLgAECggJHgASANkWAA==.Mambosauce:BAAALgADCgUJBQAAAA==.Mangosmash:BAAALgAECgMJBQAAAA==.Maraline:BAAALgADCgYJBQAAAA==.Marcusdapimp:BAACLgAFFH8ZAAIGAAYJjheQBwCnAQAGAAYJjheQBwCnAQAuAAQKfysAAgYACAmIIckFAPMCAAYACAmIIckFAPMCAAAA.Marymoocow:BAABLgAECn8dAAIYAAcJygy5KwDaAAAYAAcJygy5KwDaAAAAAA==.Matild:BAABLgAECn8fAAILAAYJTSIBIQAUAgALAAYJTSIBIQAUAgAAAA==.Maxdiabolic:BAAALgADCgQJBAAAAA==.Maxfirepower:BAAALgAECgEJAgAAAA==.Maxfrogpower:BAAALgADCgkJFQAAAA==.Maximumgourd:BAAALgAECgEJAQAAAA==.Maxsteel:BAAALgADCgkJCQAAAA==.Maxsunward:BAAALgAECgYJEQAAAA==.Maérline:BAAALgADCgcJDQABLgAECgkJNAAFAKojAA==.',
Me='Meatslug:BAAALgAECgUJBgAAAA==.Meepasaurus:BAABLgAECn8kAAIkAAgJmhqyDQD3AQAkAAgJmhqyDQD3AQAAAA==.Megaforce:BAAALgAECgQJBAAAAA==.Meliiodas:BAABLgAECn9JAAIiAAkJ7RXODgAZAgAiAAkJ7RXODgAZAgAAAA==.Melisandre:BAAALgAECgcJCwAAAA==.Mellky:BAACLgAFFH8QAAIJAAQJ8R3fGABcAQAJAAQJ8R3fGABcAQAuAAQKfzcAAgkACQm3IyIHABEDAAkACQm3IyIHABEDAAAA.Merkin:BAAALgADCgcJBwAAAA==.Merrinx:BAABLgAECn8UAAMDAAYJXiYxAwBxAgADAAYJySUxAwBxAgAEAAIJWyMlGgC/AAAAAA==.Metanoia:BAACLgAFFH8GAAInAAMJYRLCIADyAAAnAAMJYRLCIADyAAAuAAQKfx8AAykACQkvIXgCAJwCACkACAn0IHgCAJwCACcABwnhHusOACQCAAAA.',
Mg='Mgamer:BAABLgAECn8fAAISAAkJKB90GQCTAgASAAkJKB90GQCTAgAAAA==.Mgämër:BAAALgAECgEJAQABLgAECgkJHwASACgfAA==.',
Mi='Mi:BAAALgAECgUJCgABLgAECggJJAASAEQcAA==.Midgetmanxl:BAAALgAECgEJAgAAAA==.Midnitetrvlr:BAABLgAECn8XAAITAAgJYxMEVgCvAQATAAgJYxMEVgCvAQAAAA==.Miima:BAAALgAECgEJAgAAAA==.Minchy:BAAALgADCgEJAQABLgAECggJFAAPAGQIAA==.Minjeong:BAAALgAFFAEJAgAAAA==.Minji:BAAALgAECgUJBQAAAA==.Mirren:BAABLgAECn8YAAIIAAgJ5RbhigC8AQAIAAgJ5RbhigC8AQAAAA==.Missed:BAAALgADCgUJBQABLgAFFAQJCAAPAEMMAA==.Misthios:BAABLgAECn8XAAInAAgJ3BSlGgAsAgAnAAgJ3BSlGgAsAgAAAA==.Mistkeg:BAAALgAECgYJEAAAAA==.Miteux:BAABLgAECn8UAAIZAAcJeRotBACtAQAZAAcJeRotBACtAQAAAA==.Mixxlepit:BAABLgAECn8aAAMnAAgJCQcfKAA6AQAnAAgJCQcfKAA6AQApAAEJpgMyIQAsAAAAAA==.',
Ml='Mlkchocolate:BAAALgADCgkJDwAAAA==.',
Mm='Mmhunt:BAAALgAECgMJAwAAAA==.',
Mo='Mogli:BAAALgADCgYJBgAAAA==.Mokokofosho:BAAALgADCgMJAwAAAA==.Molyporph:BAAALgAECgYJCQAAAA==.Momojojo:BAACLgAFFH8MAAMEAAQJ5A9NBQAqAQAEAAQJ5A9NBQAqAQACAAMJrQELhwCZAAAuAAQKfzQAAwQACQl0ITkBANMCAAQACQl0ITkBANMCAAIABQnOEjamAOkAAAAA.Monre:BAABLgAECn8WAAIWAAgJqxNXSQDPAQAWAAgJqxNXSQDPAQAAAA==.Moobss:BAAALgADCgEJAQAAAA==.Moohlawn:BAAALgAECgQJBwABLgAFFAIJAgAKAAAAAA==.Moolock:BAAALgAECgUJBQAAAA==.Moonflame:BAACLgAFFH8GAAIGAAMJFQkzIACYAAAGAAMJFQkzIACYAAAuAAQKfygAAwYACQkbGAMoAK8BAAYABwnhFgMoAK8BAAUACAmbDpIuAEUBAAAA.Moonmajik:BAAALgAECgEJAQAAAA==.Moonmoonmoon:BAAALgAECgQJBQAAAA==.Mooriah:BAABLgAECn8eAAIVAAgJ+gJ9VQCeAAAVAAgJ+gJ9VQCeAAAAAA==.Moosty:BAAALgAECgIJAgAAAA==.Mordrakhuul:BAAALgAECgcJDgAAAA==.Morphtek:BAAALgAECgYJEAAAAA==.Morphyne:BAACLgAFFH8IAAISAAQJlAz+QgAOAQASAAQJlAz+QgAOAQAuAAQKfy4AAhIACQnOGjo+ACwCABIACQnOGjo+ACwCAAAA.Moselii:BAAALgAECgEJAQABLgAECgMJCAAKAAAAAA==.Moserr:BAAALgAECgMJCAAAAA==.Motowa:BAAALgAECgMJAwAAAA==.',
Mu='Muffin:BAAALgAECgYJEQAAAA==.',
My='Mycilya:BAAALgAECggJEgAAAA==.Mynchus:BAABLgAECn8UAAMPAAgJZAjeQAAUAQAPAAgJZAjeQAAUAQAcAAEJjAY0OQAqAAAAAA==.Mysaria:BAAALgADCgUJBQAAAA==.Mysterymonk:BAABLgAECn9AAAIJAAkJvSUZAQDJAwAJAAkJvSUZAQDJAwAAAA==.Mysterypala:BAABLgAECn9KAAILAAgJIibnAgBoAwALAAgJIibnAgBoAwAAAA==.Mysto:BAABLgAECn8iAAMiAAgJfRXVHADaAQAiAAgJfRXVHADaAQAWAAMJHQNjzABdAAAAAA==.Mystodin:BAABLgAECn80AAISAAkJ8RtBGQCVAgASAAkJ8RtBGQCVAgAAAA==.Mystospin:BAAALgAECgUJBQAAAA==.',
['Mà']='Màyhem:BAAALgADCgYJBgAAAA==.',
['Mä']='Mälförmïtÿ:BAABLgAECn8dAAMGAAkJhRpwFgApAgAGAAgJgxpwFgApAgAFAAgJWhVhGwDNAQAAAA==.',
Na='Nacon:BAABLgAECn8aAAITAAYJFxtnSQDTAQATAAYJFxtnSQDTAQAAAA==.Nagayoshi:BAAALgAECgQJBAAAAA==.Naneko:BAABLgAECn8fAAIIAAkJNAwGdAB3AQAIAAkJNAwGdAB3AQAAAA==.Narrator:BAAALgAECgkJEgAAAA==.Nawwl:BAAALgADCgcJDgAAAA==.',
Ne='Neamheaglach:BAAALgADCgQJBAABLgAFFAEJAQAKAAAAAA==.Necroz:BAAALgAECgEJAQAAAA==.Neelix:BAAALgADCgEJAQAAAA==.Neotahr:BAACLgAFFH8PAAIjAAQJWxG/EQAVAQAjAAQJWxG/EQAVAQAuAAQKfzwAAyMACQnXIBoCANACACMACQnXIBoCANACAAEAAwnOFxybAJwAAAAA.Neroiki:BAABLgAECn8aAAIMAAcJ2Q0aTQBHAQAMAAcJ2Q0aTQBHAQAAAA==.Neurôn:BAEALgAECgUJCAAAAA==.Nezra:BAABLgAECn8ZAAIhAAkJSRRzGgDEAQAhAAkJSRRzGgDEAQAAAA==.',
Ni='Nicckkcc:BAAALgADCgYJCwAAAA==.Nicotene:BAAALgAECgQJBwAAAA==.Nightquil:BAAALgADCgIJAgAAAA==.Nim:BAACLgAFFH8OAAIkAAMJWw9SGQCzAAAkAAMJWw9SGQCzAAAuAAQKfyYAAiQACQlwEcwQAMQBACQACQlwEcwQAMQBAAAA.Nitehunter:BAABLgAECn8uAAIBAAgJ0A/qTwCaAQABAAgJ0A/qTwCaAQAAAA==.',
No='Nomad:BAAALgAECgQJBQAAAA==.Nongshim:BAAALgAECgIJAgABLgAECgkJLQAOAAQkAA==.',
Nu='Nubshock:BAAALgAECgIJAgAAAA==.Nursis:BAAALgADCgUJBQAAAA==.',
Ny='Nyatsua:BAAALgADCgEJAQAAAA==.',
['Nô']='Nôva:BAAALgADCgkJEAAAAA==.',
['Nö']='Növacaïn:BAAALgAECgIJAgAAAA==.',
Of='Offseason:BAAALgAECgIJAgAAAA==.',
Oi='Oistos:BAAALgADCgcJCwAAAA==.',
Om='Omid:BAAALgADCgYJCgAAAA==.',
On='Ondarklena:BAAALgADCgEJAQAAAA==.Onlydans:BAABLgAECn8ZAAIRAAkJOhnWCwAMAgARAAkJOhnWCwAMAgAAAA==.',
Oo='Oomfie:BAAALgADCgkJDAAAAA==.',
Ou='Ouch:BAABLgAFFH8JAAIBAAUJMRi2IwBSAQABAAUJMRi2IwBSAQAAAA==.',
Ox='Oxxo:BAAALgADCgEJAQAAAA==.',
Oy='Oyakev:BAAALgADCggJCgAAAA==.Oyea:BAAALgAECgUJCAABLgAECggJJgAFABsQAA==.',
Pa='Pabiloneta:BAAALgAFFAIJAgAAAA==.Pacho:BAAALgADCgkJCQAAAA==.Painzir:BAABLgAECn8yAAITAAkJNR99FQCzAgATAAkJNR99FQCzAgAAAA==.Palamyne:BAAALgAECgEJAQAAAA==.Pallerina:BAAALgAECgEJAQABLgAECgUJAwAKAAAAAA==.Pallyana:BAABLgAECn8cAAISAAkJ+RwaIwBhAgASAAkJ+RwaIwBhAgAAAA==.Palosdin:BAAALgAECgUJBgAAAA==.Pandangerous:BAAALgAECgMJBgAAAA==.Paradocx:BAAALgAECgYJBgAAAA==.Parch:BAAALgADCgcJBwABLgAFFAIJBgAXAP8lAA==.Parrandas:BAAALgAECgUJBQAAAA==.Parsleyposh:BAAALgAECgQJBAAAAA==.',
Pe='Peace:BAACLgAFFH8HAAIFAAMJ8QqAIADKAAAFAAMJ8QqAIADKAAAuAAQKfzMAAgUACQleG+8OAE4CAAUACQleG+8OAE4CAAAA.Pepsweat:BAAALgADCgUJBQAAAA==.Perilc:BAAALgADCgQJBAAAAA==.Perimones:BAAALgAECgQJCAAAAA==.',
Ph='Phalandrel:BAABLgAECn8YAAIBAAkJiBwhKQAjAgABAAkJiBwhKQAjAgAAAA==.Phteve:BAAALgADCgUJBwAAAA==.',
Pi='Pigfeet:BAAALgAECgEJAQAAAA==.Pillows:BAAALgADCgYJCgAAAA==.Pinkponyclub:BAAALgAECgcJBwAAAA==.',
Pl='Plapper:BAAALgADCgMJAwABLgAECgYJDgAKAAAAAA==.',
Po='Pog:BAAALgAECgQJBwAAAA==.Ponytale:BAAALgADCgYJBgAAAA==.Popaheal:BAABLgAECn8nAAMGAAYJZR2tIQDWAQAGAAUJ7SGtIQDWAQAFAAUJlwvHWACEAAAAAA==.Portali:BAAALgADCgkJFAAAAA==.Poundtown:BAAALgAECgYJBgAAAA==.',
Pr='Praystatiøn:BAAALgADCgcJBwAAAA==.Profitlord:BAABLgAFFH8FAAISAAIJ4R0HagCyAAASAAIJ4R0HagCyAAAAAA==.Proticus:BAAALgAECgMJAwAAAA==.',
Ps='Psychodad:BAAALgAECgEJAgAAAA==.Psyop:BAAALgAECgcJCQAAAA==.',
Pu='Puppetpoker:BAAALgAECgEJAQAAAA==.Purplepain:BAAALgAFFAMJAwABLgAFFAUJGAAXAFUmAA==.Purplod:BAABLgAECn8YAAITAAkJtw9PhAB6AQATAAkJtw9PhAB6AQAAAA==.',
Py='Pyatpree:BAAALgAECgcJEAAAAA==.',
['Pä']='Päntera:BAABLgAECn9RAAIOAAgJYB+QCQB4AgAOAAgJYB+QCQB4AgAAAA==.',
Qi='Qing:BAABLgAECn8eAAIQAAkJbhcoFgDpAQAQAAkJbhcoFgDpAQAAAA==.',
Qt='Qtrpounder:BAACLgAFFH8PAAIkAAQJESQrBwCaAQAkAAQJESQrBwCaAQAuAAQKfxoAAyQACQmmI0sDAPICACQACQmmI0sDAPICACAAAQl+Aax5ABQAAAAA.',
Qy='Qybxboogied:BAAALgAECgMJBgAAAA==.Qybxboogyy:BAAALgAECgEJAQAAAA==.',
Ra='Raensong:BAAALgAECgEJAQAAAA==.Rafterman:BAAALgAECgEJAwAAAA==.Ragedriven:BAAALgADCggJCQAAAA==.Rahdric:BAAALgAECgYJDQAAAA==.Raisa:BAACLgAFFH8HAAICAAIJLA+VjgCRAAACAAIJLA+VjgCRAAAuAAQKfx4AAwIACQlqIX4zAP4BAAIABglNIX4zAP4BAAQABAnUHygcAGwBAAAA.Rakarum:BAABLgAECn8tAAIkAAgJaxRbEgCuAQAkAAgJaxRbEgCuAQAAAA==.Rasar:BAABLgAECn8dAAIIAAkJwh0dIwDmAgAIAAkJwh0dIwDmAgAAAA==.Ravën:BAAALgAECgkJBgAAAA==.Rayleena:BAAALgAECgEJAQAAAA==.Rayo:BAAALgAECgQJBAAAAA==.',
Re='Reginald:BAAALgADCgcJDgAAAA==.Reigh:BAAALgADCgQJBAAAAA==.Rektington:BAACLgAFFH8HAAMoAAQJLxcVCABBAQAoAAQJLxcVCABBAQATAAEJOxIg4ABLAAAuAAQKfxwAAhMACQnHHjgiAGoCABMACQnHHjgiAGoCAAAA.Remiko:BAABLgAECn8UAAILAAgJXxzVEQBwAgALAAgJXxzVEQBwAgAAAA==.Remmag:BAABLgAECn9AAAIIAAgJpSQ0HgD8AgAIAAgJpSQ0HgD8AgAAAA==.Rempri:BAAALgAECgkJEgAAAA==.Rett:BAAALgAECgEJAQABLgAFFAIJBQAgADAZAA==.Revenger:BAAALgAECgEJAQAAAA==.Rexxy:BAAALgAECgYJDgAAAA==.',
Ri='Ribeye:BAAALgAECgUJBwAAAA==.Riott:BAAALgADCggJDwAAAA==.Rippednstiff:BAAALgADCgYJBgAAAA==.',
Ro='Roflmeister:BAABLgAECn8cAAIOAAYJkRUXEQCyAQAOAAYJkRUXEQCyAQAAAA==.Romoko:BAACLgAFFH8KAAIPAAQJTAe+JwDZAAAPAAQJTAe+JwDZAAAuAAQKfyUAAg8ACAmkFu8gAAgCAA8ACAmkFu8gAAgCAAAA.Rorshk:BAABLgAECn8eAAIaAAgJMiAoBQCHAgAaAAgJMiAoBQCHAgAAAA==.Royal:BAAALgAECgEJAQAAAA==.Roysham:BAABLgAECn8YAAIHAAYJjBavPACOAQAHAAYJjBavPACOAQAAAA==.Roywar:BAAALgAECgEJAwAAAA==.',
Ru='Rubianne:BAABLgAECn89AAIMAAkJfwzaPQCJAQAMAAkJfwzaPQCJAQAAAA==.Rumrunner:BAABLgAECn8UAAInAAkJQxvcDQAyAgAnAAkJQxvcDQAyAgAAAA==.',
Ry='Rycicle:BAAALgADCgYJBQABLgAECgUJBgAKAAAAAA==.Rynhardt:BAAALgAECgUJBgAAAA==.Ryolith:BAAALgADCgMJAwAAAA==.',
['Rø']='Rønea:BAAALgAECgIJAgAAAA==.',
['Rý']='Rýfle:BAAALgADCgEJAQABLgAECgUJBgAKAAAAAA==.',
Sa='Sacrus:BAABLgAECn8eAAISAAgJ2RY2UgC6AQASAAgJ2RY2UgC6AQAAAA==.Santoss:BAAALgAECgEJAQAAAA==.Sarah:BAACLgAFFH8HAAIOAAIJoyMOHwC4AAAOAAIJoyMOHwC4AAAuAAQKfzUAAw4ACQkdIiIHAKICAA4ACQngISIHAKICACMAAQm4Ii93AGMAAAEuAAUUBQkOAAUAvRsA.',
Sc='Scoobear:BAAALgAECgEJAgABLgAECggJNAASAL4cAA==.Scottscrx:BAAALgADCgUJBQAAAA==.Scrotes:BAABLgAFFH8FAAIFAAUJOQrGGAANAQAFAAUJOQrGGAANAQAAAA==.',
Se='Seer:BAABLgAECn8fAAIWAAkJ7R0eGgBkAgAWAAkJ7R0eGgBkAgAAAA==.Seilah:BAAALgAECgYJEAAAAA==.Selbi:BAABLgAECn8fAAIEAAkJjRRQBgDhAQAEAAkJjRRQBgDhAQAAAA==.Senjougahara:BAACLgAFFH8aAAIoAAcJkxtpAQD1AQAoAAcJkxtpAQD1AQAuAAQKfzcAAygABwnCJUYBAPcCACgABwnCJUYBAPcCABMAAQnCB/oqASsAAAAA.Seola:BAAALgAECgEJBAAAAA==.Serav:BAAALgADCgIJAgAAAA==.Seravonas:BAAALgADCgcJBwAAAA==.Seravonta:BAAALgAECgEJAgAAAA==.Serial:BAABLgAECn8uAAIPAAkJJCOjBAAJAwAPAAkJJCOjBAAJAwAAAA==.Seriyah:BAACLgAFFH8RAAIaAAQJCxQtBgAsAQAaAAQJCxQtBgAsAQAuAAQKfxwAAhoABwlsHVENAL4BABoABwlsHVENAL4BAAAA.Serph:BAABLgAECn8XAAMSAAkJFRG1ZQCKAQASAAkJFRG1ZQCKAQALAAIJNwiYegBDAAAAAA==.',
Sh='Shabane:BAABLgAECn80AAIQAAkJVxdxEAAnAgAQAAkJVxdxEAAnAgAAAA==.Shaggyspaggy:BAAALgAECgUJBQAAAA==.Shambulañcé:BAABLgAECn8WAAIHAAYJ8wmRcADqAAAHAAYJ8wmRcADqAAAAAA==.Shanbubu:BAAALgAECgIJCwAAAA==.Shasta:BAAALgAECgkJCAAAAA==.Shekari:BAAALgAECgEJAQAAAA==.Shenanigins:BAAALgADCgUJBQAAAA==.Shiftey:BAABLgAECn8iAAIYAAgJfRN3FQCFAQAYAAgJfRN3FQCFAQABLgAECgkJMgATADUfAA==.Shilera:BAAALgADCgYJDwAAAA==.Shiminy:BAAALgAECgkJDwAAAA==.Shinobi:BAABLgAECn8hAAIXAAkJihmhEQAhAgAXAAkJihmhEQAhAgAAAA==.Shiol:BAACLgAFFH8HAAMCAAMJxRgSMACzAAACAAIJ4xcSMACzAAAEAAEJihpJEgBaAAAuAAQKfxcAAwIACAlRHlYkAIICAAIABwkVHlYkAIICAAQABAlvHr0hAEcBAAAA.Shirls:BAACLgAFFH8HAAISAAQJYhOQNgAnAQASAAQJYhOQNgAnAQAuAAQKfxkAAxIACQlkGm9HAA0CABIACQlkGm9HAA0CAAsABgkKFFlYABoBAAAA.Shivak:BAACLgAFFH8RAAIeAAQJ3Qn0LQDwAAAeAAQJ3Qn0LQDwAAAuAAQKfzoAAh4ACQnjGqINAG0CAB4ACQnjGqINAG0CAAAA.Shivanie:BAABLgAECn8WAAILAAYJjBFpOQBOAQALAAYJjBFpOQBOAQAAAA==.Shock:BAACLgAFFH8IAAIPAAQJQwxUIgD6AAAPAAQJQwxUIgD6AAAuAAQKfyEAAw8ACAkCH+YOALgCAA8ACAkCH+YOALgCAAcAAQnZEGOXAEEAAAAA.Shocklesnar:BAAALgAECgYJDgAAAA==.Shocknorris:BAAALgAECgUJBQAAAA==.Shîftycent:BAABLgAECn8qAAQVAAgJvxW8HgC4AQAVAAgJvxW8HgC4AQAMAAcJbgkpYgArAQAaAAEJ0wDlOwAKAAAAAA==.',
Si='Siccem:BAABLgAECn8oAAIBAAkJnyBUCgDxAgABAAkJnyBUCgDxAgAAAA==.Sicwiddit:BAAALgAECggJDAAAAA==.Sienfonson:BAAALgADCgMJAwAAAA==.Silk:BAAALgAECgQJBAABLgAECgkJHgAQAG4XAA==.',
Sk='Skaffos:BAAALgADCgUJBQABLgADCgYJBgAKAAAAAA==.Skaffoz:BAAALgADCgEJAQABLgADCgYJBgAKAAAAAA==.Skafz:BAAALgADCgYJBgAAAA==.Skeeda:BAAALgAECgUJEAAAAA==.Skik:BAABLgAECn9EAAIkAAkJhCFIAwDzAgAkAAkJhCFIAwDzAgAAAA==.Skylines:BAAALgAFFAEJAgAAAA==.Skylinex:BAAALgAECgQJBQAAAA==.Skylinez:BAACLgAFFH8VAAIPAAUJUBIaHwAIAQAPAAUJUBIaHwAIAQAuAAQKfxwAAg8ACQnRHWUWAGcCAA8ACQnRHWUWAGcCAAAA.Skïttles:BAABLgAECn8lAAMMAAgJqBiGKwDpAQAMAAgJqBiGKwDpAQAVAAQJ6gyoVwCWAAAAAA==.',
Sl='Sleezball:BAAALgAECgYJDAAAAA==.Sloppyhog:BAAALgAECgkJEwAAAA==.Sloppyslice:BAAALgAECgEJAQABLgAECgMJBAAKAAAAAA==.Sloshman:BAAALgAECgEJAQAAAA==.',
Sm='Smobo:BAAALgAECgEJAQAAAA==.Smolder:BAAALgAECgUJCQABLgAECgkJFAAKAAAAAA==.',
Sn='Snoz:BAAALgAECgEJAQAAAA==.',
So='Sobek:BAAALgAECgcJCQAAAA==.Soeuphoric:BAAALgAECgcJBwAAAA==.Sohelem:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.Sohhet:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.Sonicfear:BAAALgAFFAEJAgAAAA==.Sonictide:BAACLgAFFH8LAAIHAAQJuhDLLAAMAQAHAAQJuhDLLAAMAQAuAAQKfxkAAwcACQmAGnEdAEcCAAcACAkYGnEdAEcCAA8AAgkLE/dqAIcAAAAA.Souahang:BAAALgAECgEJBgAAAA==.Souldrain:BAAALgAECgQJBgAAAA==.Soviette:BAAALgADCgkJDgAAAA==.',
Sp='Spaghetto:BAABLgAECn8xAAIVAAkJ2hnnDwBKAgAVAAkJ2hnnDwBKAgAAAA==.Sparx:BAAALgAECgEJAgAAAA==.Spicytacoo:BAAALgAECgUJBQAAAA==.Spookyscary:BAAALgAECgEJAQAAAA==.',
St='Stacy:BAAALgADCgMJAwAAAA==.Stankystank:BAABLgAECn8/AAMCAAYJNA4cmAADAQACAAYJNA4cmAADAQAEAAIJ1wiKOgAtAAAAAA==.Stepdag:BAACLgAFFH8SAAIQAAQJfgOkMADPAAAQAAQJfgOkMADPAAAuAAQKfzMAAhAACQmNEO4bALQBABAACQmNEO4bALQBAAAA.Sthompson:BAAALgAECgUJCAAAAA==.Stinkydagger:BAAALgADCgIJAgAAAA==.Stormbolt:BAAALgAECgIJBQAAAA==.Stoutshrike:BAABLgAECn8UAAIJAAkJHxbVGQDsAQAJAAkJHxbVGQDsAQAAAA==.Strayvoker:BAACLgAFFH8HAAIeAAMJQgQpQQCgAAAeAAMJQgQpQQCgAAAuAAQKfyEAAh4ACQnnFRMRAEMCAB4ACQnnFRMRAEMCAAAA.Strive:BAABLgAECn8tAAQhAAkJOxGwGgDZAQAhAAkJpA+wGgDZAQAFAAYJAQ5aNABHAQAGAAQJTxVlUwDpAAAAAA==.Strup:BAAALgAECgkJAQAAAA==.Stumpchuggns:BAAALgAECgEJAQAAAA==.',
Su='Suzel:BAAALgAECgMJBgAAAA==.',
Sw='Sweetfeed:BAAALgADCgcJCgAAAA==.',
Sy='Synder:BAACLgAFFH8FAAIeAAIJ3gAVUwBTAAAeAAIJ3gAVUwBTAAAuAAQKfy8AAh4ACQlrBZg9ABIBAB4ACQlrBZg9ABIBAAAA.',
Sz='Szmata:BAABLgAECn8wAAIcAAkJZSMnAQApAwAcAAkJZSMnAQApAwAAAA==.',
['Sï']='Sïñ:BAAALgAECgYJBgAAAA==.',
['Só']='Sóth:BAAALgADCgEJAQAAAA==.',
Ta='Tabata:BAABLgAECn8uAAIkAAkJsRmACgA0AgAkAAkJsRmACgA0AgAAAA==.Tahharruk:BAAALgAECgQJCwAAAA==.Tailwind:BAAALgADCgUJBAAAAA==.Talivandril:BAAALgAECgYJDgAAAA==.Talogos:BAAALgAECgMJBQAAAA==.Talvan:BAAALgADCgcJBwAAAA==.Tankowner:BAAALgADCgUJBQAAAA==.Tarkdoxicity:BAAALgAECgcJBwAAAA==.Tarynna:BAABLgAECn82AAICAAkJsBQoMAAMAgACAAkJsBQoMAAMAgAAAA==.Taubhauhlau:BAAALgAECgEJAQAAAA==.Tawxx:BAAALgAECgUJBgAAAA==.',
Te='Teagen:BAABLgAECn8aAAIPAAcJ5RYnNgBFAQAPAAcJ5RYnNgBFAQAAAA==.Tekin:BAAALgAECgEJAQABLgAECgkJJgAJAEUUAA==.Teleprompter:BAABLgAECn8dAAIMAAgJZxfiMADKAQAMAAgJZxfiMADKAQAAAA==.Teleros:BAAALgADCgcJDQAAAA==.Telrissan:BAABLgAECn8YAAMIAAgJlBDWZACbAQAIAAgJlBDWZACbAQAlAAYJCwGcDwBYAAAAAA==.Tenyroldemon:BAABLgAECn8bAAINAAkJtBRdCQC7AQANAAkJtBRdCQC7AQAAAA==.Tenzingyatso:BAAALgAECgcJBgAAAA==.',
Th='Thald:BAABLgAECn8lAAIQAAkJQh94EACWAgAQAAkJQh94EACWAgAAAA==.Thepooper:BAACLgAFFH8LAAISAAMJahfNVADjAAASAAMJahfNVADjAAAuAAQKfyYAAhIACQkpIJccAIICABIACQkpIJccAIICAAAA.Thiccnasty:BAAALgAECgYJBgAAAA==.Thordun:BAAALgAECgEJAQABLgAECggJHQAkABYWAA==.Thorin:BAAALgAECgMJBgAAAA==.Thunderball:BAABLgAECn8cAAIIAAgJ4xcOUQBEAgAIAAgJ4xcOUQBEAgAAAA==.',
Ti='Tinyaminals:BAAALgADCgYJBgAAAA==.Tisagosa:BAAALgADCgYJCAABLgAFFAQJEgAIADIjAA==.Tisakna:BAACLgAFFH8SAAIIAAQJMiM8LACLAQAIAAQJMiM8LACLAQAuAAQKfz4AAwgACQk0JiADAGUDAAgACQkkJiADAGUDACUAAQnCJi0XAGEAAAAA.Tiskano:BAAALgADCgYJCwABLgAFFAQJEgAIADIjAA==.Tissaia:BAAALgADCgcJDAABLgAFFAQJEgAIADIjAA==.Tiszy:BAAALgADCgYJBgAAAA==.Titanx:BAAALgAECgkJDgAAAA==.',
To='To:BAAALgAECgYJBgAAAA==.Tomatoes:BAAALgAECgcJEwAAAA==.Toothy:BAAALgAECgUJCgAAAA==.Torahdanyse:BAAALgAECgMJAwAAAA==.Toughputa:BAAALgAECgEJAgAAAA==.',
Tr='Trask:BAABLgAECn8aAAIIAAkJ0huTXgAfAgAIAAkJ0huTXgAfAgAAAA==.Treefort:BAAALgADCgkJEAAAAA==.Trogdoor:BAAALgAECgEJAQAAAA==.Troko:BAAALgAECggJEAABLgAFFAUJFwAIAC8mAA==.Trokom:BAACLgAFFH8XAAIIAAUJLyb8IwCrAQAIAAUJLyb8IwCrAQAuAAQKfy0AAggACQkeJdoGADcDAAgACQkeJdoGADcDAAEuAAUUBQkXAAgALyYA.Trolladin:BAAALgAECgEJAQAAAA==.Trulyunruly:BAAALgAECgQJCAAAAA==.',
Tu='Tuakia:BAAALgADCgEJAQAAAA==.Tuggmytotem:BAABLgAECn8XAAIPAAkJmhzUFQAfAgAPAAkJmhzUFQAfAgAAAA==.Turgho:BAAALgADCgMJAwAAAA==.',
Tw='Twi:BAAALgAECgcJCwAAAA==.',
Ty='Tygerfist:BAAALgAECgMJBwAAAA==.Tyrannar:BAAALgAECgcJBgAAAA==.Tytanion:BAAALgAECgMJBgAAAA==.Tython:BAAALgADCgcJBwAAAA==.',
Tz='Tzao:BAAALgAECgIJBAAAAA==.',
Uc='Uch:BAAALgADCgQJBQAAAA==.',
Ug='Ugrak:BAAALgAECgYJBgABLgAECgcJBwAKAAAAAA==.',
Ul='Ultrarion:BAAALgAECgYJCgAAAA==.',
Un='Uncletrump:BAAALgAECgEJAgAAAA==.Undan:BAAALgAECgEJAQAAAA==.Undercovrcow:BAAALgAECgIJAwAAAA==.Unity:BAAALgADCgYJBgAAAA==.Unmade:BAACLgAFFH8SAAIFAAQJQBiwEQA/AQAFAAQJQBiwEQA/AQAuAAQKfy8AAgUACQllHzIOAFgCAAUACQllHzIOAFgCAAAA.Unstablë:BAAALgAECgUJDAAAAA==.',
Ur='Urbanmech:BAABLgAECn8UAAIXAAkJERzgEQBoAgAXAAkJERzgEQBoAgAAAA==.',
Us='Usedgoods:BAAALgAECgcJAQAAAA==.',
Va='Vanderbos:BAAALgADCgMJAwAAAA==.Vanderune:BAACLgAFFH8SAAIUAAQJLQ9fHADbAAAUAAQJLQ9fHADbAAAuAAQKfzwAAhQACQlaHmMHAJECABQACQlaHmMHAJECAAAA.Varastanna:BAAALgADCgYJCgAAAA==.',
Ve='Vecky:BAAALgADCgcJBwAAAA==.Vessel:BAAALgAECgUJBQAAAA==.',
Vi='Victus:BAAALgAECgEJAQAAAA==.Vidrus:BAAALgAECgYJEAAAAA==.Vilkas:BAACLgAFFH8NAAIFAAUJ7RcsBwBUAQAFAAUJ7RcsBwBUAQAuAAQKfx8AAgUACAkKISQIAAIDAAUACAkKISQIAAIDAAAA.Viserion:BAABLgAECn8YAAIfAAYJphTWGAAzAQAfAAYJphTWGAAzAQAAAA==.Visionhorn:BAAALgADCgYJCQAAAA==.',
Vo='Voidlit:BAAALgAECgEJAQAAAA==.Voodoowhodo:BAABLgAECn8dAAIEAAgJcAuXEAAfAQAEAAgJcAuXEAAfAQAAAA==.Votrigan:BAAALgADCgEJAQABLgAFFAIJBgAGAI8DAA==.',
Vu='Vuradra:BAAALgAECgMJAwAAAA==.Vuudrood:BAAALgAECgMJAwAAAA==.',
['Vø']='Vøid:BAAALgAFFAIJBAABLgAFFAcJGgAIAKIVAA==.',
Wa='Waddledoo:BAAALgAECgMJBQAAAA==.Walruskíng:BAABLgAECn8hAAIFAAcJfR1xGwDNAQAFAAcJfR1xGwDNAQAAAA==.Wardaddy:BAAALgAECgYJEgAAAA==.Warkind:BAAALgAECgMJAwAAAA==.Warmage:BAAALgAECgIJAgAAAA==.Warmaku:BAABLgAECn8dAAMMAAkJ5RpkEgCoAgAMAAkJ5RpkEgCoAgAaAAEJ9QLcOQAhAAAAAA==.Warmohg:BAAALgAECgYJDAAAAA==.Wasred:BAAALgADCgkJCQAAAA==.',
We='Weezybaby:BAABLgAECn8jAAMcAAkJgA8qEACPAQAcAAkJgA8qEACPAQAHAAEJVQR2pQAqAAAAAA==.Wenjiesmom:BAAALgAECgEJAQAAAA==.',
Wh='Whitecosmos:BAAALgAECgQJBwABLgAFFAUJGAAXAFUmAA==.Whohe:BAAALgAECgEJAQAAAA==.',
Wi='Wigwog:BAABLgAECn8WAAIFAAcJWhtZIACkAQAFAAcJWhtZIACkAQAAAA==.Windfury:BAACLgAFFH8YAAIcAAcJCSOWAAA6AgAcAAcJCSOWAAA6AgAuAAQKfy4AAhwACQmtJLABAEwDABwACQmtJLABAEwDAAAA.Windycrits:BAAALgADCgUJAQABLgADCgcJBwAKAAAAAA==.Winterfella:BAAALgAECgEJAQAAAA==.Wirantimer:BAAALgAECgYJDwAAAA==.Wishofwar:BAAALgADCgUJBQABLgAECggJJAASAEQcAA==.Witfuk:BAAALgADCgUJBQAAAA==.',
Wo='Wogasaurus:BAAALgAECggJDgAAAA==.Woobee:BAAALgAECgEJAQAAAA==.',
Wu='Wulrok:BAAALgAECgMJAwAAAA==.Wuzo:BAAALgAECgMJAwAAAA==.',
Wy='Wykka:BAABLgAECn8VAAIDAAkJghDRDwBBAQADAAkJghDRDwBBAQAAAA==.Wyverynn:BAABLgAECn8UAAITAAcJthROewCNAQATAAcJthROewCNAQAAAA==.',
['Wí']='Wínter:BAAALgADCgMJAwAAAA==.',
Xa='Xami:BAAALgADCgkJCQAAAA==.Xany:BAAALgAECgUJCwAAAA==.',
Xc='Xcomunicated:BAAALgADCgUJBQAAAA==.',
Xe='Xenomortis:BAAALgAECgcJDwAAAA==.Xephanie:BAAALgAECgEJBAAAAA==.',
Xi='Xinlucia:BAAALgAECgkJDwAAAA==.',
Xo='Xofu:BAAALgAECgEJBAAAAA==.Xoro:BAAALgAECgQJBgAAAA==.',
Xr='Xrxyz:BAACLgAFFH8PAAISAAUJhBlJMgAvAQASAAUJhBlJMgAvAQAuAAQKfyQAAhIACAkYHecoAIECABIACAkYHecoAIECAAAA.',
Xy='Xylus:BAAALgAECgIJAgAAAA==.',
Ya='Yabe:BAAALgAECgMJAwAAAA==.',
Ye='Yen:BAAALgADCgIJAgAAAA==.Yetibear:BAAALgAECgIJAgAAAA==.Yewna:BAAALgAECgYJDwAAAA==.',
Yy='Yyrella:BAAALgADCgIJAgABLgAECgcJFAATAHoTAA==.',
Za='Zachdem:BAAALgAECgQJBAAAAA==.Zachdrac:BAAALgADCgQJBAAAAA==.Zachmonk:BAAALgAECgEJAQAAAA==.Zaemor:BAAALgAECgMJBAAAAA==.Zau:BAAALgADCgkJCQAAAA==.',
Ze='Zebrabutt:BAABLgAECn8vAAMPAAkJchN1HwDNAQAPAAkJehJ1HwDNAQAcAAgJWw4wEQCkAQAAAA==.Zed:BAAALgAECgcJCAABLgAFFAIJBgAXAP8lAA==.Zenstation:BAAALgADCgEJAQABLgADCgcJBwAKAAAAAA==.Zero:BAAALgAECgcJEgAAAA==.',
Zi='Ziccem:BAABLgAECn8zAAIVAAgJwx5jEQA6AgAVAAgJwx5jEQA6AgABLgAECgkJKAABAJ8gAA==.Ziggawâ:BAAALgAECgYJEAABLgAFFAIJBgARAAAZAA==.Zildjìan:BAAALgAECgEJAQAAAA==.Zionsmender:BAAALgAECgYJDwAAAA==.',
Zo='Zolja:BAAALgAECgMJAwAAAA==.Zoney:BAAALgADCgIJAwAAAA==.Zordlon:BAAALgAECgMJBgAAAA==.',
Zu='Zugdug:BAAALgAECgEJAQAAAA==.Zukem:BAAALgAECgUJBQAAAA==.Zuli:BAAALgAECgYJBwABLgAFFAMJBwACAMUYAA==.Zuretull:BAABLgAFFH8GAAITAAMJzgeikwDGAAATAAMJzgeikwDGAAAAAA==.',
Zy='Zynlord:BAAALgADCgEJAQAAAA==.Zyvea:BAAALgAECgYJEgAAAA==.',
['Çh']='Çharacter:BAAALgAECgYJBgAAAA==.',
['Çr']='Çrossblesser:BAABLgAECn8UAAIFAAUJxBM/QADqAAAFAAUJxBM/QADqAAAAAA==.',
['ßa']='ßamboo:BAAALgADCgYJDQABLgAECggJHgASANkWAA==.',
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
