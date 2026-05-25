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
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abeblinken:BAAALgAECggJDQAAAA==.Abraaham:BAAALgAECgEJAgAAAA==.',
Ad='Adonas:BAAALgADCgUJBQAAAA==.Adym:BAABLgAECn8ZAAIBAAkJOBnwHABYAgABAAkJOBnwHABYAgAAAA==.',
Ae='Aeralyn:BAAALgADCgcJBwAAAA==.Aermo:BAAALgADCgYJBwAAAA==.Aethoos:BAAALgAECgcJBwABLgAECgkJSwACALobAA==.Aethos:BAABLgAECn9LAAQCAAkJuhunEwCaAgACAAkJuhunEwCaAgADAAEJ+xcSKwBJAAAEAAIJoBnYLwBEAAAAAA==.Aeyther:BAABLgAECn8WAAMFAAkJghiKGgAKAgAFAAkJghiKGgAKAgAGAAIJgBJVawB+AAAAAA==.',
Ag='Agave:BAABLgAECn83AAIHAAgJuBYLIwAPAgAHAAgJuBYLIwAPAgAAAA==.Agony:BAAALgAECgQJCQAAAA==.',
Ah='Ahluethedrud:BAAALgADCgUJBQAAAA==.',
Ai='Airbnb:BAAALgADCgQJBAAAAA==.',
Al='Aleynah:BAAALgADCggJIQABLgAECggJQQAEAG8MAA==.Alukarrd:BAAALgAECgMJBQAAAA==.',
Am='Aminadab:BAAALgADCgYJBgAAAA==.Amnere:BAAALgAECgcJBwABLgAECggJKwAFALYOAA==.Amoraniel:BAABLgAECn8jAAIIAAkJqiAKJwDWAgAIAAkJqiAKJwDWAgAAAA==.Amortin:BAAALgADCgEJAQAAAA==.',
An='Anavar:BAABLgAECn8kAAIJAAkJqhvVDgBpAgAJAAkJqhvVDgBpAgAAAA==.Ancestral:BAAALgADCgEJAQABLgAECgkJFAAKAAAAAA==.Andrar:BAAALgADCgMJBAAAAA==.Andresra:BAABLgAECn8UAAIIAAcJ3RcZZwAJAgAIAAcJ3RcZZwAJAgAAAA==.Angelle:BAABLgAECn8tAAILAAgJOyTSCgDKAgALAAgJOyTSCgDKAgAAAA==.Annakin:BAABLgAECn8mAAIMAAkJexkOHQA5AgAMAAkJexkOHQA5AgAAAA==.Annaluna:BAAALgAECgYJBwAAAA==.Anomally:BAAALgAECgEJAQAAAA==.Anzhelika:BAAALgADCgMJAwAAAA==.',
Ar='Arararagi:BAAALgAECgYJCwAAAA==.Arawn:BAAALgADCgYJBgAAAA==.Arctica:BAABLgAECn8uAAINAAkJHR7LAwCPAgANAAkJHR7LAwCPAgAAAA==.Arelà:BAAALgAFFAEJAwAAAA==.Aria:BAABLgAECn8xAAIJAAkJeyMqAgCQAwAJAAkJeyMqAgCQAwAAAA==.Aristoteles:BAAALgAECgEJAQAAAA==.Arron:BAAALgAECgMJAwAAAA==.Arrowsnag:BAABLgAECn8bAAIOAAkJyAdMGgCuAQAOAAkJyAdMGgCuAQAAAA==.Articdemon:BAAALgADCgkJFAAAAA==.Artics:BAAALgAECgEJAQAAAA==.Arya:BAABLgAFFH8FAAIFAAMJSwxvHADdAAAFAAMJSwxvHADdAAABLgAECggJIQAPAAIfAA==.Arylynn:BAAALgADCgYJBgABLgAECgkJKAAQANQjAA==.',
As='Ashley:BAAALgAECgQJCwAAAA==.Asrael:BAAALgAECgcJDQABLgAECggJKwARAEUVAA==.Astradaeus:BAAALgADCgMJAwAAAA==.Astridaya:BAAALgAECgEJBAAAAA==.',
Au='Aunumator:BAAALgAECgYJEQAAAA==.',
Av='Avert:BAAALgAECgEJAQAAAA==.Avâtre:BAABLgAECn8gAAIPAAkJlxMHKQB6AQAPAAkJlxMHKQB6AQAAAA==.',
Ba='Baba:BAAALgADCgcJAQAAAA==.Baccaj:BAAALgAFFAEJAQAAAA==.Baeblue:BAAALgAECgYJDQABLgAECggJIgASAEQcAA==.Baguette:BAAALgAECgEJAgAAAA==.Bajingobomb:BAABLgAECn8mAAMTAAkJwR8MLwB8AgATAAkJwR8MLwB8AgAUAAEJpREwRgAvAAAAAA==.Baked:BAAALgAECgUJCQAAAA==.Ballmelazer:BAAALgAECgEJAQAAAA==.Barasuishou:BAAALgAECgEJAQABLgAFFAMJDAAFAMcdAA==.Barkruffalo:BAACLgAFFH8MAAIMAAQJ+QmvKgDsAAAMAAQJ+QmvKgDsAAAuAAQKf0IAAwwACQkYIBEHACsDAAwACQkYIBEHACsDABUABglXFaEwACsBAAAA.Barktotem:BAAALgADCgQJBAAAAA==.Barkwoven:BAAALgAECgMJAwAAAA==.Battleborne:BAAALgAECgEJAQAAAA==.Bayln:BAAALgADCgcJBgABLgABCgUJBQAKAAAAAA==.',
Be='Beckyoncé:BAABLgAECn85AAIWAAgJ7CNFEAClAgAWAAgJ7CNFEAClAgAAAA==.Bedris:BAABLgAECn8iAAMSAAkJvg4iUQC2AQASAAkJ3g0iUQC2AQARAAUJUAtkKwCyAAAAAA==.Beerticus:BAABLgAECn8gAAIXAAgJLR74DABPAgAXAAgJLR74DABPAgAAAA==.Bekkar:BAAALgAECgYJDgAAAA==.Belcebu:BAAALgAECgIJBQAAAA==.Berim:BAAALgAECgQJBQAAAA==.',
Bi='Bigdingus:BAABLgAECn8ZAAIYAAkJQB2sBQB8AgAYAAkJQB2sBQB8AgAAAA==.Binggles:BAACLgAFFH8bAAMIAAgJCBqdCABSAgAIAAgJCBqdCABSAgAZAAEJXQHLAQBDAAAuAAQKfyUAAggACAl+JXwSADgDAAgACAl+JXwSADgDAAAA.Bingglestwo:BAAALgAECgMJAwABLgAFFAgJGwAIAAgaAA==.',
Bl='Blackastraza:BAAALgAECgMJAwAAAA==.Blacksheep:BAAALgAECgQJCAAAAA==.Blanketparty:BAABLgAECn8ZAAMPAAgJxhojHADUAQAPAAgJxhojHADUAQAHAAEJXw8EswAuAAAAAA==.Blazze:BAAALgAFFAEJAQAAAA==.Blinkyshadow:BAAALgADCgMJAwAAAA==.Bloodraven:BAACLgAFFH8PAAIMAAQJhhlNGgBPAQAMAAQJhhlNGgBPAQAuAAQKf0AAAwwACQl2H4INANACAAwACQl2H4INANACABoAAwmNFfsgAMQAAAAA.Bluballs:BAAALgAECgkJCQAAAA==.Bluebabyfox:BAAALgADCgIJAgAAAA==.Blëwm:BAAALgAECgEJAQABLgAECgkJHAAQABIWAA==.',
Bo='Boaj:BAACLgAFFH8MAAIbAAMJfxOCKQDUAAAbAAMJfxOCKQDUAAAuAAQKfyMAAhsACQk0GfUfAMsBABsACQk0GfUfAMsBAAAA.Bobette:BAABLgAECn8UAAIcAAgJEAg1FQBpAQAcAAgJEAg1FQBpAQAAAA==.Bodyspray:BAABLgAECn8iAAISAAkJBh+2GgCGAgASAAkJBh+2GgCGAgAAAA==.Boolay:BAABLgAECn8fAAIRAAkJliAjBQB6AgARAAkJliAjBQB6AgAAAA==.Boomchickeni:BAAALgAECgEJAQAAAA==.Bootyfire:BAABLgAECn8ZAAIIAAgJ9RF9aAAFAgAIAAgJ9RF9aAAFAgAAAA==.Boozing:BAABLgAECn8ZAAIaAAgJWx/CBACGAgAaAAgJWx/CBACGAgAAAA==.Bopstds:BAAALgAECgEJAQAAAA==.Bosmina:BAACLgAFFH8PAAIGAAQJ6xAQEAAeAQAGAAQJ6xAQEAAeAQAuAAQKfz0AAgYACQnIFCwWAPkBAAYACQnIFCwWAPkBAAAA.Botanicaljoe:BAAALgAECgQJCAAAAA==.',
Br='Braeibo:BAABLgAECn8mAAIBAAkJew8MNgDaAQABAAkJew8MNgDaAQAAAA==.Breelynn:BAAALgADCgcJBwAAAA==.Breida:BAAALgAECgUJCAAAAA==.Brendalee:BAAALgADCgEJAQAAAA==.Brenmonk:BAAALgAECggJEQAAAA==.Brenpriest:BAAALgADCgEJAQAAAA==.Brielle:BAAALgADCgEJAQAAAA==.Brolerion:BAAALgADCgQJBAAAAA==.',
Bu='Bubblebaddie:BAABLgAECn8UAAISAAgJ5wxAcgBpAQASAAgJ5wxAcgBpAQAAAA==.Bugenhagen:BAAALgAECgUJDwABLgAECgYJDwAKAAAAAA==.Butchers:BAAALgAECgIJAgAAAA==.Buttpaladin:BAABLgAECn8gAAISAAgJLSS+EADHAgASAAgJLSS+EADHAgAAAA==.',
['Bë']='Bëldin:BAAALgADCggJCwAAAA==.',
Ca='Canelo:BAAALgADCgUJBQAAAA==.Cantheal:BAAALgADCgYJBgAAAA==.Carademuerta:BAAALgAECgcJEAAAAA==.Cardib:BAABLgAFFH8OAAITAAYJLh2GGACvAQATAAYJLh2GGACvAQAAAA==.Cavos:BAABLgAECn8wAAIWAAkJDxmDIgApAgAWAAkJDxmDIgApAgAAAA==.',
Ce='Cernsarn:BAABLgAECn84AAIUAAgJQBX1EgCxAQAUAAgJQBX1EgCxAQAAAA==.',
Ch='Chandlef:BAAALgAECgQJBAAAAA==.Chantorc:BAAALgADCgYJCgAAAA==.Chickendad:BAAALgAECgUJBQAAAA==.Chigang:BAAALgADCgMJAwAAAA==.Chiri:BAEBLgAECn8gAAQdAAkJZBH0BwCVAQAdAAgJZxD0BwCVAQAeAAYJdQuPNQAkAQAfAAUJYxC9KAB4AAAAAA==.Chocc:BAAALgADCgMJAwAAAA==.Chvngus:BAABLgAECn8mAAISAAkJ0h97EwCyAgASAAkJ0h97EwCyAgAAAA==.',
Ci='Cindersam:BAAALgAECgYJCQABLgAECgcJFAATALYUAA==.',
Cl='Clawsoh:BAAALgAECgEJAQAAAA==.Climene:BAAALgAECgEJAQABLgAECggJIgASAEQcAA==.',
Co='Cocheeze:BAAALgAECgUJCQAAAA==.Coffeebeen:BAAALgAECgcJBwAAAA==.Condor:BAECLgAFFH8HAAIVAAQJQxqJEwBEAQAVAAQJQxqJEwBEAQAuAAQKfx0AAhUACQlBJf8CACMDABUACQlBJf8CACMDAAAA.Conmammoth:BAAALgAECgQJCgAAAA==.Coohwhip:BAAALgAECgcJEAAAAA==.Cowwithhorns:BAABLgAECn8fAAMbAAkJIRVlKgAPAgAbAAgJIhJlKgAPAgAgAAUJVhPKHwA0AQAAAA==.',
Cr='Cristobal:BAAALgAECgkJEAAAAA==.Cronùs:BAAALgAECggJDAAAAA==.Crunkshot:BAABLgAECn8bAAMSAAcJLwONugARAQASAAcJLwONugARAQALAAcJEQRnWAClAAAAAA==.',
Cu='Curaga:BAAALgAECgUJBQAAAA==.Curnsarn:BAAALgAECgcJCgABLgAECggJOAAUAEAVAA==.Curtis:BAABLgAECn8UAAQGAAcJ9Q14PwA8AQAGAAcJ9Q14PwA8AQAFAAMJsxWDRwDEAAAhAAEJEAMkbQAkAAAAAA==.',
Cy='Cyalaterz:BAAALgAECgEJAQAAAA==.Cyrail:BAABLgAECn8uAAILAAkJviOHBQATAwALAAkJviOHBQATAwAAAA==.',
['Cø']='Cøven:BAACLgAFFH8MAAMVAAQJXhHQJgDFAAAVAAMJ7AzQJgDFAAAMAAIJ0BLRQACNAAAuAAQKfzgAAxUACQnWHhcIALECABUACQnWHhcIALECAAwABAmQEGWdAJAAAAAA.',
Da='Daenérys:BAAALgAECgIJAgAAAA==.Dan:BAAALgAECgEJAQAAAA==.Dapöpe:BAAALgADCgQJBQABLgAECgcJHAASAKIXAA==.Darkmonks:BAAALgAECgYJCwAAAA==.Darksoulstwo:BAAALgAECgYJDAAAAA==.Darktoxi:BAABLgAECn8hAAIJAAgJ0BpYFAA+AgAJAAgJ0BpYFAA+AgABLgAECgkJLgAWAAYaAA==.Darkwarden:BAAALgADCgEJAQAAAA==.Darthpooper:BAAALgAECgYJBgABLgAFFAMJCwASAGoXAA==.Dashel:BAAALgAECgIJAgABLgAECggJKwAFALYOAA==.Dastaan:BAAALgAECgEJAgAAAA==.Dauntus:BAACLgAFFH8WAAIIAAcJ7hK3EgD1AQAIAAcJ7hK3EgD1AQAuAAQKfzYAAggACQlXIlYMAAADAAgACQlXIlYMAAADAAAA.Dawnclaw:BAAALgADCgUJBQAAAA==.Daydream:BAAALgAECgEJAQAAAA==.',
De='Deathclock:BAABLgAECn8tAAITAAkJWSAVDQAyAwATAAkJWSAVDQAyAwAAAA==.Deegey:BAAALgAECgIJAgAAAA==.Deep:BAAALgADCgEJAQAAAA==.Degey:BAAALgAECgYJEAAAAA==.Deign:BAACLgAFFH8MAAIiAAQJawESFAC0AAAiAAQJawESFAC0AAAuAAQKfzUAAiIACQnyDT4XAJYBACIACQnyDT4XAJYBAAAA.Delayne:BAAALgAECggJCQAAAA==.Demoncrat:BAAALgAFFAEJAQAAAA==.Demonicramen:BAAALgAECgIJAgAAAA==.Demonstroza:BAAALgAECgUJBQABLgAECgkJEQAKAAAAAA==.Demontotems:BAAALgAECgMJCQAAAA==.Demotoxi:BAABLgAECn8uAAIWAAkJBhpXGQBgAgAWAAkJBhpXGQBgAgAAAA==.Deriso:BAABLgAECn8WAAMBAAkJMiO6FACEAgABAAgJkCK6FACEAgAjAAYJ9R43KwDTAQAAAA==.Derpthyr:BAAALgADCgMJAwAAAA==.Destrozinth:BAAALgAECgkJEQAAAA==.Dethorok:BAABLgAECn8tAAQOAAkJBCR4AQA1AwAOAAkJsCN4AQA1AwAjAAYJjSTzIgAPAgABAAUJlCCIbgA1AQAAAA==.Deuce:BAAALgAECgQJBQAAAA==.Deåth:BAAALgAFFAEJAQAAAA==.',
Dh='Dhamon:BAAALgADCgYJBgAAAA==.',
Di='Dib:BAAALgAECgUJBQABLgAFFAMJBwACAMUYAA==.Diccem:BAAALgAECgcJBwABLgAECgkJJAABADYgAA==.Dieworc:BAAALgADCgkJFgAAAA==.Digey:BAABLgAECn8WAAIkAAkJtiJaBgDLAgAkAAkJtiJaBgDLAgAAAA==.Digitz:BAABLgAECn8cAAMIAAgJTBYEVwAzAgAIAAgJTBYEVwAzAgAlAAEJAABAHgA1AAAAAA==.Direwolf:BAAALgAECgUJBgAAAA==.Dirtnapp:BAAALgAECgMJCAAAAA==.Divah:BAABLgAECn9BAAIEAAgJbwy+DQA2AQAEAAgJbwy+DQA2AQAAAA==.Divinelight:BAAALgAECgEJAgAAAA==.',
Do='Dogehh:BAAALgADCgIJAgAAAA==.Dogèhh:BAAALgAECgEJAQAAAA==.Donald:BAABLgAECn8hAAIBAAkJEhI2MADxAQABAAkJEhI2MADxAQAAAA==.Donbolo:BAAALgAFFAEJAgAAAA==.Dontlookatme:BAAALgAECgEJAQAAAA==.Dopeaf:BAABLgAECn8XAAMkAAgJtRAlFQB6AQAkAAgJtRAlFQB6AQAbAAEJiAI0sQApAAAAAA==.Dotpotato:BAAALgADCgIJAgAAAA==.Dotterparty:BAAALgAECgYJCgAAAA==.Dowkia:BAAALgAECgEJBAAAAA==.Downwarddog:BAAALgADCgYJBwAAAA==.',
Dr='Dragonmaas:BAAALgADCgYJBgAAAA==.Dragonwings:BAECLgAFFH8PAAIIAAQJtgULWgAKAQAIAAQJtgULWgAKAQAuAAQKfxsAAggABwk7Ft19ANUBAAgABwk7Ft19ANUBAAAA.Drakah:BAAALgAECgIJAgAAAA==.Drakbek:BAABLgAECn8UAAIYAAcJqRWpFABzAQAYAAcJqRWpFABzAQAAAA==.Dreaknite:BAAALgADCgQJBgAAAA==.Dreamshift:BAABLgAECn8eAAMMAAgJZBsjJAAHAgAMAAgJZBsjJAAHAgAVAAIJbQelagBKAAAAAA==.Dreco:BAABLgAECn8dAAIWAAcJrh6vJQBxAgAWAAcJrh6vJQBxAgAAAA==.Drekken:BAAALgAECgMJBQAAAA==.Drelik:BAAALgADCgIJAgAAAA==.Dronebot:BAABLgAECn8yAAMFAAgJhSNMCACrAgAFAAgJhSNMCACrAgAGAAMJngpuZwCPAAAAAA==.Drucifer:BAABLgAECn8aAAIcAAcJBRPMEABpAQAcAAcJBRPMEABpAQAAAA==.Druelf:BAAALgAECgMJBAAAAA==.Druiwny:BAAALgAECgMJAwAAAA==.Drék:BAAALgAECgYJEgAAAA==.Drúcifer:BAAALgAECgEJAQAAAA==.',
Du='Dud:BAABLgAECn8jAAICAAgJoR1aJQAvAgACAAgJoR1aJQAvAgAAAA==.Duelme:BAAALgAECgMJBAABLgAECggJFwAkALUQAA==.Dugaa:BAAALgAECgQJBAAAAA==.Dumbdwagon:BAABLgAECn8mAAIfAAgJaA0AEgCFAQAfAAgJaA0AEgCFAQAAAA==.Dumblecrumb:BAAALgADCgQJBAABLgAECgEJAQAKAAAAAA==.Dumbrouge:BAAALgAECgIJAwABLgAECggJKwARAEUVAA==.Durumi:BAAALgAECgEJAQAAAA==.Dustyshotz:BAAALgAECgUJDQAAAA==.',
Dw='Dwall:BAAALgAECgMJAwAAAA==.Dwarfgasm:BAAALgAECgkJAQAAAA==.Dwarfladin:BAAALgAECgEJAQAAAA==.Dwarriorarf:BAAALgAECgQJBgAAAA==.',
Dz='Dzieux:BAAALgADCgYJBwAAAA==.',
['Dë']='Dëadisbetter:BAAALgADCgEJAQAAAA==.',
['Dö']='Dögehh:BAABLgAECn8VAAMBAAcJyRUrcQAwAQAOAAYJCRCVJwBAAQABAAYJaxYrcQAwAQAAAA==.',
['Dø']='Døgehh:BAAALgAECgEJAQAAAA==.',
Ee='Eeseo:BAAALgAECgEJAgAAAA==.',
Eg='Eggblack:BAAALgAECgQJCQAAAA==.',
El='Ellegryn:BAAALgADCgEJAgAAAA==.Elvebring:BAABLgAECn8cAAIiAAcJsBsrGQD8AQAiAAcJsBsrGQD8AQABLgAFFAMJBgALAFYaAA==.',
Em='Embody:BAABLgAECn8cAAIVAAgJfRHRJAB2AQAVAAgJfRHRJAB2AQAAAA==.Emilio:BAAALgAECgEJAgAAAA==.',
En='Endlyss:BAAALgAECgUJBQAAAA==.',
Er='Erikira:BAABLgAECn8YAAMbAAgJDBAeLQB4AQAbAAgJaw4eLQB4AQAgAAUJZQ2JRAB9AAAAAA==.Erikk:BAABLgAECn8dAAITAAgJSQoWcQBcAQATAAgJSQoWcQBcAQAAAA==.Eryngium:BAABLgAECn8iAAIMAAgJfBtRGwBIAgAMAAgJfBtRGwBIAgAAAA==.',
Es='Essentia:BAAALgAECgEJAQAAAA==.',
Et='Ethantherat:BAAALgAECgEJAQAAAA==.',
Eu='Euphoricx:BAACLgAFFH8MAAIHAAQJ5hd9GwBIAQAHAAQJ5hd9GwBIAQAuAAQKfzUAAgcACQlIJvcCAE4DAAcACQlIJvcCAE4DAAAA.',
Ev='Evildeader:BAABLgAECn8UAAITAAcJehPGdgCYAQATAAcJehPGdgCYAQAAAA==.Eviltotems:BAAALgAECgQJBQABLgAECgcJFAATAHoTAA==.',
Ex='Exalt:BAAALgAECgcJEgAAAA==.Exes:BAAALgADCggJCAABLgAECggJIQAPAAIfAA==.Expand:BAABLgAECn8WAAIXAAkJSBrcFQA7AgAXAAkJSBrcFQA7AgAAAA==.',
Ey='Eyeseyesbaby:BAABLgAECn8ZAAIWAAkJKhyMKQAFAgAWAAkJKhyMKQAFAgAAAA==.',
Ez='Ezbakeovens:BAAALgAFFAIJAwAAAA==.',
Fa='Facelift:BAAALgAECgEJAgAAAA==.Faithles:BAACLgAFFH8MAAIFAAQJJQ58FQAeAQAFAAQJJQ58FQAeAQAuAAQKfzMAAgUACQk+HocHALoCAAUACQk+HocHALoCAAAA.Falgur:BAACLgAFFH8PAAMHAAQJqwPRNwDNAAAHAAQJqwPRNwDNAAAPAAIJORAJFwCaAAAuAAQKfz4AAw8ACQkZIosEAAADAA8ACQkZIosEAAADAAcABAlGEDZnAO0AAAAA.Fallenlord:BAAALgADCgcJBwAAAA==.Fantasma:BAABLgAECn8XAAITAAcJVgz2gAA7AQATAAcJVgz2gAA7AQAAAA==.Fasty:BAABLgAECn8mAAIJAAkJRRToHgC9AQAJAAkJRRToHgC9AQAAAA==.Faygochugger:BAAALgAECgkJCwAAAA==.',
Fe='Fear:BAAALgAECgYJCQAAAA==.Felmajik:BAAALgADCgMJBQAAAA==.',
Fi='Fifths:BAAALgAECgUJBQAAAA==.Findal:BAAALgAECgEJAQABLgABCgUJBAAKAAAAAA==.Finley:BAAALgADCgMJAwAAAA==.Fivemagics:BAABLgAECn8eAAMCAAkJ0RmSMQD6AQACAAgJ0RmSMQD6AQAEAAIJmBTSTgCBAAAAAA==.',
Fl='Flayvour:BAAALgAECgcJCgABLgAECgkJHAAQABIWAA==.Fleaboy:BAABLgAECn8YAAMmAAYJahWmCgBIAQAmAAYJahWmCgBIAQAnAAQJMgYITwCzAAAAAA==.Fleshwound:BAAALgADCgYJBgAAAA==.Flist:BAABLgAECn8jAAIXAAgJPCT5BwCkAgAXAAgJPCT5BwCkAgAAAA==.',
Fo='Fongsaiyok:BAAALgAECgEJAwAAAA==.Foregord:BAAALgADCgUJBQABLgABCgUJBQAKAAAAAA==.Fortlock:BAAALgAECgQJBwAAAA==.Fotation:BAAALgAECgQJBAAAAA==.',
Fr='Frankensteyn:BAAALgADCgkJCQAAAA==.Frankyice:BAABLgAECn8eAAIFAAkJ5A8HHQC2AQAFAAkJ5A8HHQC2AQAAAA==.Freesia:BAABLgAECn8aAAISAAYJWRAbkABcAQASAAYJWRAbkABcAQAAAA==.French:BAAALgAECggJDQAAAA==.Froggyfresh:BAAALgADCgYJCAAAAA==.Fruitjuice:BAABLgAECn8UAAIEAAYJrBrhCQB5AQAEAAYJrBrhCQB5AQAAAA==.',
Fu='Funbobby:BAAALgAECgUJBgAAAA==.',
Fx='Fxce:BAAALgAECgYJCAAAAA==.',
['Fâ']='Fâmine:BAABLgAECn8hAAICAAkJLRV+LAAPAgACAAkJLRV+LAAPAgAAAA==.',
Ga='Galautee:BAAALgAECgEJAQAAAA==.Gamakichi:BAAALgAECgEJAQAAAA==.Gambitt:BAAALgADCgUJBQAAAA==.Gamer:BAAALgADCgcJDAABLgAECgYJDgAKAAAAAA==.Gamergirl:BAAALgAECgYJDgAAAA==.Ganjj:BAAALgAECgEJAQAAAA==.Gawdric:BAACLgAFFH8YAAMTAAYJJh47HACfAQATAAUJJh47HACfAQAUAAMJigP7JwBiAAAuAAQKfx8AAxMACAlWIZwsAIYCABMACAlWIZwsAIYCACgAAQnOC00YAC4AAAAA.',
Gb='Gboozing:BAAALgAECgkJCQABLgAECgkJGQAaAFsfAA==.',
Ge='Geekminator:BAAALgAECgQJBAAAAA==.Georgesoros:BAABLgAECn8WAAQeAAkJNR1gGgD4AQAeAAgJNR1gGgD4AQAdAAEJAACCOQBOAAAfAAIJuAE7MwA5AAAAAA==.',
Gh='Ghibludgeon:BAAALgADCgIJAgAAAA==.Ghiboom:BAAALgAECgEJAgAAAA==.Ghulz:BAABLgAECn8gAAMCAAgJGRSkYwBhAQACAAgJ7QukYwBhAQADAAUJOBfNEgABAQAAAA==.Ghuntarr:BAAALgADCgcJDAAAAA==.',
Gi='Gibsmedats:BAABLgAECn8fAAMWAAkJ1BJ3QgDqAQAWAAgJkRJ3QgDqAQAiAAMJFhGXNACzAAAAAA==.Giin:BAAALgAECgYJCAAAAA==.Gildark:BAAALgADCgEJAQAAAA==.',
Gl='Glaiven:BAABLgAECn8TAAIWAAcJMiDFHgCZAgAWAAcJMiDFHgCZAgAAAA==.Glasscleaner:BAAALgAECgcJEQABLgAFFAQJEAAJAHEmAA==.Glenfarclas:BAAALgAECgYJCgAAAA==.Glenfiddich:BAABLgAECn8hAAITAAkJkiEwGACUAgATAAkJkiEwGACUAgAAAA==.Glenmorangie:BAAALgAECgQJBAAAAA==.',
Gn='Gnartusk:BAABLgAECn8wAAIUAAkJLCVSAQA/AwAUAAkJLCVSAQA/AwAAAA==.Gnomett:BAAALgADCgEJAQAAAA==.',
Go='Goblinsham:BAAALgAECgEJAQAAAA==.Gordrack:BAAALgAFFAIJAgAAAA==.',
Gr='Grandmapunch:BAAALgADCgIJAgABLgAECgcJFAAGAPUNAA==.Grasswizard:BAAALgAECggJEQAAAA==.Greela:BAAALgAECgEJAQAAAA==.Greens:BAACLgAFFH8GAAIVAAMJpxD+JADQAAAVAAMJpxD+JADQAAAuAAQKfyIAAhUABgmbGpclAHABABUABgmbGpclAHABAAAA.Gremory:BAAALgADCgYJBwAAAA==.Gru:BAAALgAECggJDgAAAA==.Grïma:BAAALgADCgcJDQABLgAFFAQJDAAVAF4RAA==.',
Gu='Gueritestje:BAABLgAECn84AAIRAAkJLCNsAQAbAwARAAkJLCNsAQAbAwAAAA==.Guzzlord:BAAALgAECgkJEwAAAA==.',
Ha='Hairinear:BAAALgAECgEJAQAAAA==.Hambo:BAAALgAECgkJBQAAAA==.Handsomejack:BAAALgAECgEJAQABLgAECgkJJgATAMEfAA==.Hanekawa:BAAALgAECgUJBwABLgAFFAMJDAAFAMcdAA==.Harddwarf:BAAALgAECgEJAQAAAA==.Haugcraneka:BAAALgADCgYJBgAAAA==.Hawts:BAAALgAECgEJAQAAAA==.',
He='Heleous:BAABLgAECn8iAAMSAAgJRByXNgAGAgASAAgJRByXNgAGAgARAAEJHg47RAAuAAAAAA==.Hexxedk:BAAALgAECgcJDgAAAA==.',
Hi='Hibernus:BAAALgADCgUJBgABLgAECgcJHAASAKIXAA==.Highly:BAAALgADCgIJAgAAAA==.Hikari:BAABLgAECn8+AAIiAAgJ7hSwFQClAQAiAAgJ7hSwFQClAQAAAA==.Himalayanman:BAAALgAECgkJDgAAAA==.Hipdrop:BAAALgAECgEJAQAAAA==.Hitemup:BAAALgAECgEJBgAAAA==.Hitoshura:BAACLgAFFH8GAAMoAAIJFSV/DQDZAAAoAAIJFSV/DQDZAAATAAEJNBXLzQBJAAAuAAQKfygAAygACAmiJEwCALACACgACAk2JEwCALACABMABglmJA0/AOQBAAAA.',
Ho='Hobbeswerth:BAABLgAECn8UAAIJAAYJEhCMNQAZAQAJAAYJEhCMNQAZAQAAAA==.Holycowbun:BAAALgAECgUJEwABLgAECggJOAAWAIciAA==.Holyginger:BAAALgAECggJCwAAAA==.Holyglizzy:BAABLgAECn8vAAISAAgJGBtCLAAuAgASAAgJGBtCLAAuAgAAAA==.Holysoup:BAAALgAECgEJAQAAAA==.Hornlet:BAAALgAECgEJAQABLgAECgIJBAAKAAAAAA==.Howitzerx:BAAALgAECgQJCQAAAA==.',
Hu='Hubbabubba:BAAALgAECgQJBAAAAA==.Huggies:BAABLgAECn8VAAIRAAYJWSEFDQDHAQARAAYJWSEFDQDHAQAAAA==.Humdinger:BAAALgADCgYJCAAAAA==.Hush:BAAALgAECgMJAgAAAA==.',
Hy='Hypérîon:BAAALgAFFAIJAgAAAA==.',
Ia='Iagging:BAACLgAFFH8QAAIJAAQJcSbsDADCAQAJAAQJcSbsDADCAQAuAAQKfzsAAgkACQkbJuQBAJ0DAAkACQkbJuQBAJ0DAAAA.',
Ib='Ibodan:BAAALgAECgUJCAAAAA==.',
Ic='Iceflinger:BAABLgAECn8wAAIIAAkJQxuhGgCgAgAIAAkJQxuhGgCgAgAAAA==.',
Id='Idjit:BAAALgADCgcJDQABLgAECgYJDwAKAAAAAA==.Idlehand:BAAALgAECgYJDAAAAA==.',
Ie='Ieatcats:BAACLgAFFH8PAAInAAQJHhIbFABCAQAnAAQJHhIbFABCAQAuAAQKfzYAAicACQmoHjUKAF0CACcACQmoHjUKAF0CAAAA.',
Ih='Ihuntdads:BAAALgAECgMJAwAAAA==.',
Il='Ilidia:BAAALgAECgEJAQAAAA==.',
Im='Imarri:BAAALgADCgYJCAAAAA==.Imjustakid:BAAALgADCgMJAwAAAA==.Immahuntyou:BAAALgAECgEJBwAAAA==.Imobelle:BAABLgAECn8hAAIIAAcJPhXTggDMAQAIAAcJPhXTggDMAQAAAA==.Imprepared:BAAALgAECgYJDgAAAA==.',
In='Indrani:BAABLgAECn8gAAIJAAgJZhxQDwB4AgAJAAgJZhxQDwB4AgAAAA==.Infidel:BAAALgAECgMJAwABLgAFFAUJDgAIAGQQAA==.Innogen:BAAALgAECgcJBwAAAA==.',
Ip='Ippiekiyaymf:BAABLgAECn8cAAIFAAcJLxTzJgBtAQAFAAcJLxTzJgBtAQAAAA==.',
Ir='Irayne:BAAALgAECggJEQAAAA==.Irisharcher:BAAALgAECgQJBgAAAA==.Irishfury:BAAALgAECgEJAQAAAA==.Irishman:BAAALgAECgYJCAAAAA==.',
Is='Ishooturface:BAABLgAECn8ZAAMBAAkJhhlNJwAYAgABAAkJhhlNJwAYAgAjAAYJ3g1aRQBAAQAAAA==.István:BAAALgADCgcJDQAAAA==.',
It='Itazki:BAABLgAECn8fAAMaAAkJwCL9AgDKAgAaAAkJwCL9AgDKAgAVAAEJMw1rfAAqAAAAAA==.',
Ja='Jardabeans:BAAALgAECgQJCAAAAA==.Jarjárßlinks:BAABLgAECn8VAAIIAAYJDQ4QpAAaAQAIAAYJDQ4QpAAaAQAAAA==.Jawz:BAAALgAECgMJBQAAAA==.',
Jc='Jconcepts:BAAALgAECgYJBgABLgAECgkJJgAJAEUUAA==.',
Je='Jeff:BAAALgADCgMJAgAAAA==.Jelial:BAAALgAECgcJBwAAAA==.Jenga:BAAALgAECggJDgAAAA==.Jerriblank:BAAALgADCgcJCAAAAA==.',
Jf='Jf:BAACLgAFFH8GAAISAAQJJwUMRwD0AAASAAQJJwUMRwD0AAAuAAQKfxsABBIACQmaFCw0AA8CABIACQmaFCw0AA8CAAsABAnCCEFaAJwAABEAAQnqFftAADcAAAAA.',
Ji='Ji:BAABLgAECn8rAAIXAAgJOxiOFgA0AgAXAAgJOxiOFgA0AgAAAA==.Jibbage:BAACLgAFFH8OAAIIAAUJZBBCDwCeAQAIAAUJZBBCDwCeAQAuAAQKfzMAAggACQlOIjsKAHIDAAgACQlOIjsKAHIDAAAA.Jinkala:BAAALgAECgEJAQAAAA==.Jitzakkal:BAACLgAFFH8eAAMCAAYJoyXMCAAJAgACAAYJoyXMCAAJAgAEAAEJwCZpDwB1AAAuAAQKfyQAAwQACQmKJSYFAIgCAAIACQmNIyEVANYCAAQABgmTJSYFAIgCAAAA.',
Jo='Johnpaladin:BAABLgAECn8hAAIRAAgJgh8nBADIAgARAAgJgh8nBADIAgAAAA==.Joshswims:BAABLgAECn8fAAMTAAkJCRUyQADgAQATAAkJ7hQyQADgAQAoAAQJARCxDQDRAAAAAA==.',
Js='Js:BAAALgAECgYJBgAAAA==.',
Ju='Judgemênt:BAAALgAECgUJBwAAAA==.Jussie:BAAALgAECgEJAgAAAA==.',
Ka='Kadriel:BAAALgADCgEJAQAAAA==.Kaiserblade:BAAALgAECgQJBAABLgAECgkJMAAUACwlAA==.Kalgard:BAAALgAECgIJAgABLgAECgkJJgAJAEUUAA==.Kambo:BAAALgAECgEJBAAAAA==.Kaptainkushh:BAAALgAECgQJEAAAAA==.Kaptkush:BAAALgAECgQJCQAAAA==.Kardinal:BAACLgAFFH8KAAMCAAMJaB6fUAD8AAACAAMJaB6fUAD8AAADAAEJoBgIFABTAAAuAAQKfzAABAIACQkPIjYSAOoCAAIACQkPIjYSAOoCAAQAAwmhH8gsAAsBAAMAAQmDHpQmAFgAAAAA.Kargan:BAAALgADCgYJBgABLgAECgcJHAASAKIXAA==.Karig:BAAALgADCgQJBQAAAA==.Karpathous:BAABLgAECn8UAAIBAAYJ6gktjQDyAAABAAYJ6gktjQDyAAAAAA==.Karrag:BAAALgAECgEJAQAAAA==.Karzo:BAAALgAECggJCQAAAA==.Kasawraa:BAAALgAECgUJBQAAAA==.Katena:BAAALgAECgYJDwAAAA==.Kaymir:BAABLgAECn8vAAQhAAkJkhohEABDAgAhAAkJ3RchEABDAgAGAAMJyhxoVQDhAAAFAAMJ0AsBXABnAAAAAA==.Kazdruid:BAAALgAECgYJCgAAAA==.Kaznathi:BAABLgAECn8oAAIQAAkJ1COEAgAgAwAQAAkJ1COEAgAgAwAAAA==.',
Ke='Keladorn:BAABLgAECn8qAAISAAgJTR7mJwBBAgASAAgJTR7mJwBBAgAAAA==.Keloril:BAAALgAECgQJCgAAAA==.',
Kh='Khanyiso:BAABLgAECn8rAAIRAAgJRRUXDQDFAQARAAgJRRUXDQDFAQAAAA==.Kharak:BAABLgAECn8eAAIIAAgJwRHGZwCQAQAIAAgJwRHGZwCQAQABLgABCgUJBAAKAAAAAA==.',
Ki='Kieran:BAABLgAECn8rAAMFAAgJtg70JAB6AQAFAAgJtg70JAB6AQAGAAgJGwkjMwAWAQAAAA==.Kikimora:BAABLgAECn8rAAQDAAgJEyA+BAAoAgADAAgJEyA+BAAoAgACAAYJshq5TQCbAQAEAAIJmxdvSACVAAAAAA==.Killsaurus:BAACLgAFFH8YAAIFAAUJ+xxHDABmAQAFAAUJ+xxHDABmAQAuAAQKfy4AAgUACAmsIJUPAD0CAAUACAmsIJUPAD0CAAAA.Kilsaurus:BAAALgAECgMJAwAAAA==.Kismete:BAAALgAECgcJCAAAAA==.Kismetx:BAABLgAECn8nAAMVAAgJpg6VKQBVAQAVAAgJpg6VKQBVAQAMAAMJSgJa1AAhAAAAAA==.Kittysmasher:BAAALgAECgQJBAAAAA==.Kiue:BAAALgADCgEJAQAAAA==.',
Kn='Knomtseb:BAAALgADCgcJDgAAAA==.',
Ko='Koa:BAAALgAECgUJBwAAAA==.Koey:BAAALgAECgQJDAAAAA==.Korsho:BAAALgAECgEJAQAAAA==.Kosuke:BAAALgADCgUJBQAAAA==.',
Kr='Kriep:BAAALgAECgEJAgAAAA==.Kristian:BAAALgADCgcJBwAAAA==.Krittykitkat:BAAALgAECgkJDQABLgAECgkJJAAJAKobAA==.Krixos:BAAALgAECgYJCAABLgAFFAcJFgAIAO4SAA==.Kroshka:BAAALgADCgEJAQAAAA==.',
Kw='Kwarrior:BAAALgAECgEJAQABLgAECggJFwACABIVAA==.Kwazlock:BAABLgAECn8XAAMCAAgJEhVOfAArAQACAAcJcxJOfAArAQAEAAMJ2A5NQgCsAAAAAA==.',
Ky='Kybalion:BAAALgAECgQJBwABLgAECgUJCAAKAAAAAA==.Kyoju:BAABLgAECn8YAAIIAAcJwQvQmAAtAQAIAAcJwQvQmAAtAQABLgAFFAEJAQAKAAAAAA==.',
La='Laprimera:BAABLgAECn8mAAIiAAcJgwq+JgAJAQAiAAcJgwq+JgAJAQAAAA==.Lazyjade:BAABLgAECn8lAAIFAAgJxQ8GIgCPAQAFAAgJxQ8GIgCPAQAAAA==.',
Le='Leyskrodan:BAABLgAECn8yAAMFAAgJfBEAIQCXAQAFAAgJfBEAIQCXAQAGAAEJKQMkiQAlAAAAAA==.',
Li='Lichborne:BAAALgAECgUJDwAAAA==.Lift:BAAALgADCggJCAABLgAECgkJFAAKAAAAAA==.Lightmilk:BAAALgADCgkJDwAAAA==.Lilgash:BAAALgADCgcJBwABLgAECgYJEgAKAAAAAA==.Listel:BAAALgADCgUJBQAAAA==.Livalil:BAAALgADCgcJBwAAAA==.Lizardos:BAAALgAECgkJCgAAAA==.',
Lm='Lmnpeprstepr:BAAALgAECgEJAgAAAA==.',
Lo='Lockrocksftw:BAAALgADCgMJAwAAAA==.Lorynn:BAAALgAECgYJCgAAAA==.',
Lu='Lucyna:BAABLgAECn8sAAQCAAkJCB+rFwB+AgACAAgJnR2rFwB+AgAEAAUJBh03EwCxAQADAAEJAABVIABxAAAAAA==.Lueshen:BAABLgAECn8bAAIXAAcJDx6zFABHAgAXAAcJDx6zFABHAgAAAA==.Luniea:BAAALgAECgEJAgAAAA==.',
Ly='Lysergicburn:BAAALgAECgQJBAABLgAECgYJDAAKAAAAAA==.Lyshin:BAAALgAECgEJAQAAAA==.',
['Lá']='Lárz:BAAALgAECgIJAwAAAA==.',
['Lí']='Líon:BAAALgADCgYJBgABLgAECgcJHAASAKIXAA==.',
['Lü']='Lüktar:BAAALgADCgYJBgAAAA==.',
Ma='Madmarsh:BAAALgAECgQJBwABLgAECgkJEwAKAAAAAA==.Madwe:BAABLgAECn8aAAITAAgJ7hr5WQCVAQATAAgJ7hr5WQCVAQAAAA==.Magdalari:BAAALgAECgQJBQAAAA==.Maggams:BAAALgAECgEJAgAAAA==.Magnaur:BAAALgADCgcJDgAAAA==.Magturri:BAABLgAECn8mAAMBAAkJ4SKuCQD8AgABAAkJ4SKuCQD8AgAjAAIJihBMdgBmAAAAAA==.Mahilo:BAAALgAECgEJAQAAAA==.Maineck:BAACLgAFFH8LAAIPAAQJeBW8FgAsAQAPAAQJeBW8FgAsAQAuAAQKfzMAAg8ACQnTHbMPAFECAA8ACQnTHbMPAFECAAAA.Maketaori:BAAALgADCgYJDAAAAA==.Malüm:BAAALgADCgMJAwABLgAECgcJHAASAKIXAA==.Mambosauce:BAAALgADCgUJBQAAAA==.Mangosmash:BAAALgAECgMJBQAAAA==.Maraline:BAAALgADCgYJBQAAAA==.Marcusdapimp:BAACLgAFFH8ZAAIGAAYJjheBBQC+AQAGAAYJjheBBQC+AQAuAAQKfysAAgYACAmIIckFAPMCAAYACAmIIckFAPMCAAAA.Marymoocow:BAABLgAECn8ZAAIYAAYJKQ5uKgDDAAAYAAYJKQ5uKgDDAAAAAA==.Matild:BAABLgAECn8fAAILAAYJTSI6HAD7AQALAAYJTSI6HAD7AQAAAA==.Maxdiabolic:BAAALgADCgQJBAAAAA==.Maxfirepower:BAAALgAECgEJAgAAAA==.Maxfrogpower:BAAALgADCgkJFQAAAA==.Maxsteel:BAAALgADCgkJCQAAAA==.Maxsunward:BAAALgAECgUJDAAAAA==.Maérline:BAAALgADCgcJDQABLgAECggJMgAFAIUjAA==.',
Me='Meatslug:BAAALgAECgUJBgAAAA==.Meepasaurus:BAABLgAECn8kAAIkAAgJmhoWDAAEAgAkAAgJmhoWDAAEAgAAAA==.Megaforce:BAAALgAECgQJBAAAAA==.Meliiodas:BAABLgAECn9BAAIiAAgJaRRQFAC2AQAiAAgJaRRQFAC2AQAAAA==.Melisandre:BAAALgAECgcJCwAAAA==.Mellky:BAACLgAFFH8MAAIJAAQJ+xWHGwAbAQAJAAQJ+xWHGwAbAQAuAAQKfzcAAgkACQm3Iz4GABMDAAkACQm3Iz4GABMDAAAA.Merkin:BAAALgADCgcJBwAAAA==.Merrinx:BAABLgAECn8UAAMDAAYJXiYxAwBxAgADAAYJySUxAwBxAgAEAAIJWyNMGADAAAAAAA==.Metanoia:BAABLgAECn8ZAAMpAAcJ2yGpAwBMAgApAAcJoSGpAwBMAgAnAAUJ6RwkIgBWAQAAAA==.',
Mg='Mgamer:BAABLgAECn8eAAISAAkJKB/sFQCiAgASAAkJKB/sFQCiAgAAAA==.Mgämër:BAAALgAECgEJAQABLgAECgkJHgASACgfAA==.',
Mi='Mi:BAAALgAECgMJAwABLgAECggJIgASAEQcAA==.Midgetmanxl:BAAALgAECgEJAgAAAA==.Midnitetrvlr:BAAALgAECggJDwAAAA==.Miima:BAAALgAECgEJAgAAAA==.Minjeong:BAAALgAECgMJBAAAAA==.Minji:BAAALgAECgUJBQAAAA==.Mirren:BAABLgAECn8YAAIIAAgJ5RbhigC8AQAIAAgJ5RbhigC8AQAAAA==.Missed:BAAALgADCgUJBQABLgAECggJIQAPAAIfAA==.Misthios:BAABLgAECn8XAAInAAgJ3BSlGgAsAgAnAAgJ3BSlGgAsAgAAAA==.Mistkeg:BAAALgAECgYJEAAAAA==.Miteux:BAABLgAECn8UAAIZAAcJeRotBACtAQAZAAcJeRotBACtAQAAAA==.Mixxlepit:BAABLgAECn8aAAMnAAgJCQecJABBAQAnAAgJCQecJABBAQApAAEJpgMyIQAsAAAAAA==.',
Ml='Mlkchocolate:BAAALgADCgkJDwAAAA==.',
Mm='Mmhunt:BAAALgAECgMJAwAAAA==.',
Mo='Mogli:BAAALgADCgYJBgAAAA==.Mokokofosho:BAAALgADCgMJAwAAAA==.Molyporph:BAAALgAECgYJCQAAAA==.Momojojo:BAACLgAFFH8IAAMEAAMJIRJMBwDmAAAEAAMJIRJMBwDmAAACAAMJrQEDewCaAAAuAAQKfzQAAwQACQl0If0AANsCAAQACQl0If0AANsCAAIABQnOEoCcAO4AAAAA.Monre:BAABLgAECn8WAAIWAAgJqxNXSQDPAQAWAAgJqxNXSQDPAQAAAA==.Moobss:BAAALgADCgEJAQAAAA==.Moohlawn:BAAALgAECgQJBwABLgAECggJGQAWAB4aAA==.Moolock:BAAALgAECgUJBQAAAA==.Moonflame:BAABLgAECn8nAAMGAAgJ6xgDKACvAQAGAAYJwhcDKACvAQAFAAgJmw7UKABgAQAAAA==.Moonmajik:BAAALgADCgQJBgAAAA==.Moonmoonmoon:BAAALgAECgMJBAAAAA==.Mooriah:BAABLgAECn8eAAIVAAgJ+gKpTwCeAAAVAAgJ+gKpTwCeAAAAAA==.Moosty:BAAALgAECgIJAgAAAA==.Mordrakhuul:BAAALgAECgcJDgAAAA==.Morphtek:BAAALgAECgYJCgAAAA==.Morphyne:BAABLgAECn8uAAISAAkJzho6PgAsAgASAAkJzho6PgAsAgAAAA==.Moselii:BAAALgADCgEJAQABLgAECgMJBwAKAAAAAA==.Moserr:BAAALgAECgMJBwAAAA==.Motowa:BAAALgAECgEJAQAAAA==.',
Mu='Muffin:BAAALgAECgYJEQAAAA==.',
My='Mycilya:BAAALgAECggJEgAAAA==.Mynchus:BAABLgAECn8UAAMPAAgJZAjEOwAWAQAPAAgJZAjEOwAWAQAcAAEJjAYPMgAqAAAAAA==.Mysaria:BAAALgADCgUJBQAAAA==.Mysterymonk:BAABLgAECn86AAIJAAgJUSX9BAAxAwAJAAgJUSX9BAAxAwAAAA==.Mysterypala:BAABLgAECn9JAAILAAgJIiZ4AgBqAwALAAgJIiZ4AgBqAwAAAA==.Mysto:BAABLgAECn8iAAMiAAgJfRXVHADaAQAiAAgJfRXVHADaAQAWAAMJHQNjzABdAAAAAA==.Mystodin:BAABLgAECn8sAAISAAkJ8Rt1FQClAgASAAkJ8Rt1FQClAgAAAA==.Mystospin:BAAALgAECgUJBQAAAA==.',
['Mä']='Mälförmïtÿ:BAABLgAECn8dAAMGAAkJhRpwFgApAgAGAAgJgxpwFgApAgAFAAgJWhUVGQDYAQAAAA==.',
Na='Nacon:BAABLgAECn8UAAITAAQJ+hhXnAAKAQATAAQJ+hhXnAAKAQAAAA==.Naneko:BAABLgAECn8fAAIIAAkJNAxobACFAQAIAAkJNAxobACFAQAAAA==.Narrator:BAAALgAECgkJEgAAAA==.Nawwl:BAAALgADCgcJDgAAAA==.',
Ne='Neamheaglach:BAAALgADCgQJBAABLgAFFAEJAQAKAAAAAA==.Neelix:BAAALgADCgEJAQAAAA==.Neotahr:BAACLgAFFH8PAAIjAAQJWxGWDgArAQAjAAQJWxGWDgArAQAuAAQKfzwAAyMACQnXIMgBANoCACMACQnXIMgBANoCAAEAAwnOFxybAJwAAAAA.Neroiki:BAABLgAECn8YAAIMAAcJ2A3QSQBEAQAMAAcJ2A3QSQBEAQAAAA==.Neurôn:BAEALgAECgUJCAAAAA==.Nezra:BAABLgAECn8ZAAIhAAkJSRRzGgDEAQAhAAkJSRRzGgDEAQAAAA==.',
Ni='Nicckkcc:BAAALgADCgYJCwAAAA==.Nicotene:BAAALgAECgMJBAAAAA==.Nightquil:BAAALgADCgIJAgAAAA==.Nim:BAACLgAFFH8LAAIkAAMJXwmpGACoAAAkAAMJXwmpGACoAAAuAAQKfyYAAiQACQlwEQUPAM8BACQACQlwEQUPAM8BAAAA.Nitehunter:BAABLgAECn8pAAIBAAgJTg9kSwCTAQABAAgJTg9kSwCTAQAAAA==.',
No='Nomad:BAAALgAECgQJBQAAAA==.',
Nu='Nubshock:BAAALgAECgIJAgAAAA==.Nursis:BAAALgADCgUJBQAAAA==.',
Ny='Nyatsua:BAAALgADCgEJAQAAAA==.',
['Nô']='Nôva:BAAALgADCgkJEAAAAA==.',
['Nö']='Növacaïn:BAAALgAECgIJAgAAAA==.',
Of='Offseason:BAAALgAECgIJAgAAAA==.',
Oi='Oistos:BAAALgADCgcJCwAAAA==.',
Om='Omid:BAAALgADCgYJCgAAAA==.',
On='Ondarklena:BAAALgADCgEJAQAAAA==.Onlydans:BAABLgAECn8ZAAIRAAkJOhnWCwAMAgARAAkJOhnWCwAMAgAAAA==.',
Oo='Oomfie:BAAALgADCgkJDAAAAA==.',
Ou='Ouch:BAABLgAFFH8HAAIBAAQJMRjAGgBXAQABAAQJMRjAGgBXAQAAAA==.',
Oy='Oyakev:BAAALgADCggJCgAAAA==.Oyea:BAAALgAECgUJBQABLgAECggJJQAFAMUPAA==.',
Pa='Pabiloneta:BAAALgAFFAIJAgAAAA==.Pacho:BAAALgADCgkJCQAAAA==.Painzir:BAABLgAECn8uAAITAAkJNR/XEgC4AgATAAkJNR/XEgC4AgAAAA==.Palamyne:BAAALgAECgEJAQAAAA==.Pallyana:BAABLgAECn8cAAISAAkJ+RwaHgBzAgASAAkJ+RwaHgBzAgAAAA==.Palosdin:BAAALgAECgUJBgAAAA==.Pandangerous:BAAALgAECgMJBgAAAA==.Parch:BAAALgADCgcJBwABLgAECggJIwAXADwkAA==.Parrandas:BAAALgAECgUJBQAAAA==.Parsleyposh:BAAALgAECgQJBAAAAA==.',
Pe='Peace:BAACLgAFFH8HAAIFAAMJ8QqNHADcAAAFAAMJ8QqNHADcAAAuAAQKfzMAAgUACQleGzwNAFwCAAUACQleGzwNAFwCAAAA.Pepsweat:BAAALgADCgUJBQAAAA==.Perilc:BAAALgADCgQJBAAAAA==.Perimones:BAAALgAECgQJCAAAAA==.',
Ph='Phalandrel:BAABLgAECn8YAAIBAAkJiByoIwApAgABAAkJiByoIwApAgAAAA==.Phteve:BAAALgADCgUJBwAAAA==.',
Pi='Pigfeet:BAAALgADCgcJCwAAAA==.Pillows:BAAALgADCgYJCgAAAA==.Pinkponyclub:BAAALgAECgcJBwAAAA==.',
Pl='Plapper:BAAALgADCgMJAwABLgAECgYJDgAKAAAAAA==.',
Po='Pog:BAAALgAECgEJAQAAAA==.Ponytale:BAAALgADCgYJBgAAAA==.Popaheal:BAABLgAECn8nAAMGAAYJZR2tIQDWAQAGAAUJ7SGtIQDWAQAFAAUJlwsxTwChAAAAAA==.Portali:BAAALgADCgkJFAAAAA==.Poundtown:BAAALgAECgYJBgAAAA==.',
Pr='Praystatiøn:BAAALgADCgcJBwAAAA==.Profitlord:BAAALgAFFAIJAwAAAA==.Proticus:BAAALgAECgMJAwAAAA==.',
Ps='Psychodad:BAAALgAECgEJAgAAAA==.Psyop:BAAALgAECgEJAgABLgAECggJEwAKAAAAAA==.',
Pu='Puppetpoker:BAAALgAECgEJAQAAAA==.Purplepain:BAAALgAFFAMJAwABLgAFFAUJFAAXAFUmAA==.Purplod:BAABLgAECn8YAAITAAkJtw9PhAB6AQATAAkJtw9PhAB6AQAAAA==.',
Py='Pyatpree:BAAALgAECgcJEAAAAA==.',
['Pä']='Päntera:BAABLgAECn9RAAIOAAgJYB9NCAB+AgAOAAgJYB9NCAB+AgAAAA==.',
Qi='Qing:BAABLgAECn8cAAIQAAkJEhZ7FgDWAQAQAAkJEhZ7FgDWAQAAAA==.',
Qt='Qtrpounder:BAACLgAFFH8LAAIkAAQJqSJhBgCSAQAkAAQJqSJhBgCSAQAuAAQKfxoAAyQACQmmI6YCAAADACQACQmmI6YCAAADACAAAQl+Ad9tABQAAAAA.',
Qy='Qybxboogied:BAAALgAECgIJBAAAAA==.Qybxboogyy:BAAALgAECgEJAQAAAA==.',
Ra='Raensong:BAAALgAECgEJAQAAAA==.Rafterman:BAAALgAECgEJAwAAAA==.Ragedriven:BAAALgADCgMJAwAAAA==.Rahdric:BAAALgAECgYJDQAAAA==.Raisa:BAACLgAFFH8HAAICAAIJLA/hgQCSAAACAAIJLA/hgQCSAAAuAAQKfx4AAwIACQlqITYvAAMCAAIABglNITYvAAMCAAQABAnUHygcAGwBAAAA.Rakarum:BAABLgAECn8nAAIkAAgJaxTfEACyAQAkAAgJaxTfEACyAQAAAA==.Rasar:BAABLgAECn8dAAIIAAkJwh0dIwDmAgAIAAkJwh0dIwDmAgAAAA==.Ravën:BAAALgAECgkJBgAAAA==.Rayleena:BAAALgAECgEJAQAAAA==.Rayo:BAAALgAECgQJBAAAAA==.',
Re='Reginald:BAAALgADCgcJDgAAAA==.Reigh:BAAALgADCgQJBAAAAA==.Rektington:BAABLgAECn8cAAITAAkJxx63HgBuAgATAAkJxx63HgBuAgAAAA==.Remiko:BAABLgAECn8UAAILAAgJXxz2DwB2AgALAAgJXxz2DwB2AgAAAA==.Remmag:BAABLgAECn9AAAIIAAgJpSQ0HgD8AgAIAAgJpSQ0HgD8AgAAAA==.Rempri:BAAALgAECgkJCgAAAA==.Rett:BAAALgAECgEJAQABLgAFFAIJBQAgADAZAA==.Revenger:BAAALgADCgQJBAAAAA==.Rexxy:BAAALgAECgYJDgAAAA==.',
Ri='Ribeye:BAAALgAECgUJBgAAAA==.Riott:BAAALgADCggJDwAAAA==.Rippednstiff:BAAALgADCgYJBgAAAA==.',
Ro='Roflmeister:BAABLgAECn8cAAIOAAYJkRUXEQCyAQAOAAYJkRUXEQCyAQAAAA==.Romoko:BAACLgAFFH8KAAIPAAQJTAdKIgDoAAAPAAQJTAdKIgDoAAAuAAQKfyUAAg8ACAmkFu8gAAgCAA8ACAmkFu8gAAgCAAAA.Rorshk:BAABLgAECn8cAAIaAAcJ0B7VBwAkAgAaAAcJ0B7VBwAkAgAAAA==.Royal:BAAALgAECgEJAQAAAA==.Roysham:BAABLgAECn8YAAIHAAYJjBavPACOAQAHAAYJjBavPACOAQAAAA==.Roywar:BAAALgAECgEJAwAAAA==.',
Ru='Rubianne:BAABLgAECn80AAIMAAgJlQz9RgBQAQAMAAgJlQz9RgBQAQAAAA==.Rumrunner:BAABLgAECn8UAAInAAkJQxscDAA+AgAnAAkJQxscDAA+AgAAAA==.',
Ry='Rycicle:BAAALgADCgYJBQABLgAFFAMJCQAoAOgYAA==.Rynhardt:BAAALgAECgUJBgABLgAFFAMJCQAoAOgYAA==.Ryolith:BAAALgADCgMJAwAAAA==.',
['Rø']='Rønea:BAAALgAECgIJAgAAAA==.',
['Rý']='Rýfle:BAAALgADCgEJAQABLgAFFAMJCQAoAOgYAA==.',
Sa='Sacrus:BAABLgAECn8cAAISAAcJoheEYACQAQASAAcJoheEYACQAQAAAA==.Santoss:BAAALgAECgEJAQAAAA==.Sarah:BAACLgAFFH8HAAIOAAIJoyNyGwC+AAAOAAIJoyNyGwC+AAAuAAQKfzUAAw4ACQkdIvoFAKwCAA4ACQngIfoFAKwCACMAAQm4Ii93AGMAAAEuAAUUBAkMAAUAvRsA.',
Sc='Scoobear:BAAALgAECgEJAQABLgAECggJLwASABgbAA==.Scottscrx:BAAALgADCgUJBQAAAA==.Scrotes:BAAALgAECgYJDQAAAA==.',
Se='Seer:BAABLgAECn8fAAIWAAkJ7R2BFwBsAgAWAAkJ7R2BFwBsAgAAAA==.Seilah:BAAALgAECgYJCwAAAA==.Selbi:BAABLgAECn8fAAIEAAkJjRRqBQDqAQAEAAkJjRRqBQDqAQAAAA==.Senjougahara:BAACLgAFFH8aAAIoAAcJkxvbAAABAgAoAAcJkxvbAAABAgAuAAQKfzcAAygABwnCJUYBAPcCACgABwnCJUYBAPcCABMAAQnCB/oqASsAAAAA.Seola:BAAALgAECgEJBAAAAA==.Serav:BAAALgADCgIJAgAAAA==.Seravonas:BAAALgADCgcJBwAAAA==.Seravonta:BAAALgAECgEJAgAAAA==.Serial:BAABLgAECn8uAAIPAAkJJCPyAwANAwAPAAkJJCPyAwANAwAAAA==.Seriyah:BAACLgAFFH8RAAIaAAQJCxTqBABCAQAaAAQJCxTqBABCAQAuAAQKfxwAAhoABwlsHQQMAMQBABoABwlsHQQMAMQBAAAA.Serph:BAABLgAECn8XAAMSAAkJFRFnlQAoAQASAAkJFRFnlQAoAQALAAIJNwgadABEAAAAAA==.',
Sh='Shabane:BAABLgAECn8xAAIQAAkJEhfQDwAiAgAQAAkJEhfQDwAiAgAAAA==.Shaggyspaggy:BAAALgAECgUJBQAAAA==.Shambulañcé:BAABLgAECn8WAAIHAAYJ8wkeaADqAAAHAAYJ8wkeaADqAAAAAA==.Shanbubu:BAAALgAECgIJCQAAAA==.Shasta:BAAALgAECgkJBwAAAA==.Shekari:BAAALgAECgEJAQAAAA==.Shenanigins:BAAALgADCgUJBQAAAA==.Shiftey:BAABLgAECn8eAAIYAAgJuRJ4FAB1AQAYAAgJuRJ4FAB1AQABLgAECgkJLgATADUfAA==.Shilera:BAAALgADCgYJDwAAAA==.Shiminy:BAAALgAECgkJDwAAAA==.Shinobi:BAABLgAECn8hAAIXAAkJihmvDwAoAgAXAAkJihmvDwAoAgAAAA==.Shiol:BAACLgAFFH8HAAMCAAMJxRgSMACzAAACAAIJ4xcSMACzAAAEAAEJihpJEgBaAAAuAAQKfxcAAwIACAlRHlYkAIICAAIABwkVHlYkAIICAAQABAlvHr0hAEcBAAAA.Shirls:BAABLgAECn8ZAAMSAAkJZBpvRwANAgASAAkJZBpvRwANAgALAAYJChRZWAAaAQAAAA==.Shivak:BAACLgAFFH8OAAIeAAQJEwd8LgDaAAAeAAQJEwd8LgDaAAAuAAQKfzoAAh4ACQnjGl0MAHgCAB4ACQnjGl0MAHgCAAAA.Shivanie:BAABLgAECn8WAAILAAYJjBGPNQBQAQALAAYJjBGPNQBQAQAAAA==.Shock:BAABLgAECn8hAAMPAAgJAh/mDgC4AgAPAAgJAh/mDgC4AgAHAAEJ2RBjlwBBAAAAAA==.Shocklesnar:BAAALgAECgYJDgAAAA==.Shocknorris:BAAALgAECgUJBQAAAA==.Shîftycent:BAABLgAECn8qAAQVAAgJvxUqHAC5AQAVAAgJvxUqHAC5AQAMAAcJbgkpYgArAQAaAAEJ0wDlOwAKAAAAAA==.',
Si='Siccem:BAABLgAECn8kAAIBAAkJNiByCQDrAgABAAkJNiByCQDrAgAAAA==.Sicwiddit:BAAALgAECgcJCwAAAA==.Sienfonson:BAAALgADCgMJAwAAAA==.Silk:BAAALgAECgQJBAABLgAECgkJHAAQABIWAA==.',
Sk='Skaffos:BAAALgADCgUJBQABLgADCgYJBgAKAAAAAA==.Skaffoz:BAAALgADCgEJAQABLgADCgYJBgAKAAAAAA==.Skafz:BAAALgADCgYJBgAAAA==.Skeeda:BAAALgAECgUJBwAAAA==.Skik:BAABLgAECn88AAIkAAgJdx+UCABNAgAkAAgJdx+UCABNAgAAAA==.Skylines:BAAALgAECgcJDgAAAA==.Skylinex:BAAALgAECgQJBQAAAA==.Skylinez:BAACLgAFFH8TAAIPAAUJUBIjGgAaAQAPAAUJUBIjGgAaAQAuAAQKfxoAAg8ACQnRHWUWAGcCAA8ACQnRHWUWAGcCAAAA.Skïttles:BAABLgAECn8kAAMMAAgJgxdVKwDbAQAMAAgJgxdVKwDbAQAVAAQJ6gytUQCWAAAAAA==.',
Sl='Sleezball:BAAALgAECgYJBgAAAA==.Sloppyhog:BAAALgAECgkJEwAAAA==.Sloppyslice:BAAALgAECgEJAQABLgAECgMJBAAKAAAAAA==.Sloshman:BAAALgAECgEJAQAAAA==.',
Sm='Smobo:BAAALgAECgEJAQAAAA==.Smolder:BAAALgAECgUJCQABLgAECgkJFAAKAAAAAA==.',
Sn='Snoz:BAAALgAECgEJAQAAAA==.',
So='Sobek:BAAALgAECgcJCQAAAA==.Soeuphoric:BAAALgAECgcJBwAAAA==.Sohelem:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.Sohhet:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.Sonicfear:BAAALgAFFAEJAgAAAA==.Sonictide:BAACLgAFFH8HAAIHAAQJJg60KwD8AAAHAAQJJg60KwD8AAAuAAQKfxkAAwcACQmAGl8aAEoCAAcACAkYGl8aAEoCAA8AAgkLEypjAIgAAAAA.Souahang:BAAALgAECgEJBQAAAA==.Souldrain:BAAALgAECgQJBAAAAA==.Soviette:BAAALgADCgkJDgAAAA==.',
Sp='Spaghetto:BAABLgAECn8xAAIVAAkJ2hlbDgBNAgAVAAkJ2hlbDgBNAgAAAA==.Sparx:BAAALgAECgEJAgAAAA==.Spicytacoo:BAAALgAECgUJBQAAAA==.Spookyscary:BAAALgAECgEJAQAAAA==.',
St='Stacy:BAAALgADCgMJAwAAAA==.Stankystank:BAABLgAECn8/AAMCAAYJNA5FjwAHAQACAAYJNA5FjwAHAQAEAAIJ1wjvNgAtAAAAAA==.Stepdag:BAACLgAFFH8PAAIQAAQJcwPdLADVAAAQAAQJcwPdLADVAAAuAAQKfzMAAhAACQmNEL8ZALkBABAACQmNEL8ZALkBAAAA.Sthompson:BAAALgAECgUJCAAAAA==.Stinkydagger:BAAALgADCgIJAgAAAA==.Stormbolt:BAAALgAECgIJBQAAAA==.Stoutshrike:BAABLgAECn8UAAIJAAkJHxbVGQDsAQAJAAkJHxbVGQDsAQAAAA==.Strayvoker:BAAALgAFFAIJAgABLgAFFAMJCAAQAEYWAA==.Strive:BAABLgAECn8tAAQhAAkJOxEhFwDvAQAhAAkJpA8hFwDvAQAFAAYJAQ5aNABHAQAGAAQJTxVlUwDpAAAAAA==.Stumpchuggns:BAAALgAECgEJAQAAAA==.',
Su='Suzel:BAAALgAECgEJAwAAAA==.',
Sw='Sweetfeed:BAAALgADCgcJCgAAAA==.',
Sy='Synder:BAABLgAECn8sAAIeAAgJBgUSQgD6AAAeAAgJBgUSQgD6AAAAAA==.',
Sz='Szmata:BAABLgAECn8vAAIcAAkJZSPtAAAtAwAcAAkJZSPtAAAtAwAAAA==.',
['Só']='Sóth:BAAALgADCgEJAQAAAA==.',
Ta='Tabata:BAABLgAECn8uAAIkAAkJsRkHCQBDAgAkAAkJsRkHCQBDAgAAAA==.Tahharruk:BAAALgAECgQJCwAAAA==.Tailwind:BAAALgADCgUJBAAAAA==.Talivandril:BAAALgAECgYJDgAAAA==.Talogos:BAAALgAECgMJBQAAAA==.Talvan:BAAALgADCgcJBwAAAA==.Tankowner:BAAALgADCgUJBQAAAA==.Tarkdoxicity:BAAALgAECgcJBwAAAA==.Tarynna:BAABLgAECn8zAAICAAkJ7xMxLQAMAgACAAkJ7xMxLQAMAgAAAA==.Taubhauhlau:BAAALgAECgEJAQAAAA==.Tawxx:BAAALgAECgUJBgAAAA==.',
Te='Teagen:BAABLgAECn8aAAIPAAcJ5RYHMgBGAQAPAAcJ5RYHMgBGAQAAAA==.Teleprompter:BAABLgAECn8cAAIMAAcJRxYtQABuAQAMAAcJRxYtQABuAQAAAA==.Teleros:BAAALgADCgcJDQAAAA==.Telrissan:BAABLgAECn8WAAMIAAgJwA6qYwCaAQAIAAgJwA6qYwCaAQAlAAYJCwFQDgBaAAAAAA==.Tenyroldemon:BAABLgAECn8bAAINAAkJtBSNCADAAQANAAkJtBSNCADAAQAAAA==.Tenzingyatso:BAAALgAECgcJBgAAAA==.',
Th='Thald:BAABLgAECn8lAAIQAAkJQh94EACWAgAQAAkJQh94EACWAgAAAA==.Thepooper:BAACLgAFFH8LAAISAAMJahd6RwDzAAASAAMJahd6RwDzAAAuAAQKfyYAAhIACQkpIIgYAJICABIACQkpIIgYAJICAAAA.Thiccnasty:BAAALgAECgEJAQAAAA==.Thordun:BAAALgAECgEJAQABLgAECggJFwAkALUQAA==.Thorin:BAAALgAECgMJBgAAAA==.Thunderball:BAABLgAECn8cAAIIAAgJ4xcOUQBEAgAIAAgJ4xcOUQBEAgAAAA==.',
Ti='Tinyaminals:BAAALgADCgYJBgAAAA==.Tisagosa:BAAALgADCgYJCAABLgAFFAQJDwAIADIjAA==.Tisakna:BAACLgAFFH8PAAIIAAQJMiPwIQCbAQAIAAQJMiPwIQCbAQAuAAQKfz4AAwgACQk0JnUCAHMDAAgACQkkJnUCAHMDACUAAQnCJi0XAGEAAAAA.Tiskano:BAAALgADCgYJCwABLgAFFAQJDwAIADIjAA==.Tissaia:BAAALgADCgcJDAABLgAFFAQJDwAIADIjAA==.Tiszy:BAAALgADCgYJBgAAAA==.Titanx:BAAALgAECgkJDgAAAA==.',
To='To:BAAALgAECgYJBgAAAA==.Tomatoes:BAAALgAECgcJEgAAAA==.Toothy:BAAALgAECgUJCQAAAA==.Torahdanyse:BAAALgAECgMJAwAAAA==.Toughputa:BAAALgAECgEJAgAAAA==.',
Tr='Trask:BAABLgAECn8aAAIIAAkJ0huTXgAfAgAIAAkJ0huTXgAfAgAAAA==.Treefort:BAAALgADCgkJEAAAAA==.Trogdoor:BAAALgAECgEJAQAAAA==.Troko:BAAALgAECggJEAABLgAFFAUJFwAIAC8mAA==.Trokom:BAACLgAFFH8XAAIIAAUJLyZWGwC4AQAIAAUJLyZWGwC4AQAuAAQKfy0AAggACQkeJboFAEUDAAgACQkeJboFAEUDAAEuAAUUBQkXAAgALyYA.Trolladin:BAAALgAECgEJAQAAAA==.Trulyunruly:BAAALgAECgQJCAAAAA==.',
Tu='Tuakia:BAAALgADCgEJAQAAAA==.Tuggmytotem:BAABLgAECn8XAAIPAAkJmhywEwAiAgAPAAkJmhywEwAiAgAAAA==.Turgho:BAAALgADCgMJAwAAAA==.',
Tw='Twi:BAAALgAECgcJCwAAAA==.',
Ty='Tygerfist:BAAALgAECgMJBwAAAA==.Tyrannar:BAAALgAECgcJBgAAAA==.Tytanion:BAAALgAECgMJBgAAAA==.Tython:BAAALgADCgcJBwAAAA==.',
Tz='Tzao:BAAALgAECgIJAgAAAA==.',
Uc='Uch:BAAALgADCgQJBQAAAA==.',
Ul='Ultrarion:BAAALgAECgYJCgAAAA==.',
Un='Uncletrump:BAAALgAECgEJAgAAAA==.Undan:BAAALgAECgEJAQAAAA==.Undercovrcow:BAAALgAECgIJAwAAAA==.Unity:BAAALgADCgYJBgAAAA==.Unmade:BAACLgAFFH8PAAIFAAQJcBc1EABGAQAFAAQJcBc1EABGAQAuAAQKfy8AAgUACQllHx8NAF4CAAUACQllHx8NAF4CAAAA.Unstablë:BAAALgAECgUJCAAAAA==.',
Ur='Urbanmech:BAABLgAECn8UAAIXAAkJERzgEQBoAgAXAAkJERzgEQBoAgAAAA==.',
Us='Usedgoods:BAAALgAECgcJAQAAAA==.',
Va='Vanderbos:BAAALgADCgMJAwAAAA==.Vanderune:BAACLgAFFH8PAAIUAAQJLQ8BGADqAAAUAAQJLQ8BGADqAAAuAAQKfzwAAhQACQlaHmIGAJgCABQACQlaHmIGAJgCAAAA.Varastanna:BAAALgADCgYJCgAAAA==.',
Ve='Vecky:BAAALgADCgcJBwAAAA==.Vessel:BAAALgAECgUJBQAAAA==.',
Vi='Victus:BAAALgAECgEJAQAAAA==.Vidrus:BAAALgAECgYJEAAAAA==.Vilkas:BAACLgAFFH8NAAIFAAUJ7RcsBwBUAQAFAAUJ7RcsBwBUAQAuAAQKfx8AAgUACAkKISQIAAIDAAUACAkKISQIAAIDAAAA.Viserion:BAABLgAECn8YAAIfAAYJphSMFwAyAQAfAAYJphSMFwAyAQAAAA==.Visionhorn:BAAALgADCgYJCQAAAA==.',
Vo='Voidlit:BAAALgAECgEJAQAAAA==.Voodoowhodo:BAABLgAECn8dAAIEAAgJcAvHDgAmAQAEAAgJcAvHDgAmAQAAAA==.Votrigan:BAAALgADCgEJAQABLgAECggJKwAFALYOAA==.',
Vu='Vuradra:BAAALgAECgMJAwAAAA==.Vuudrood:BAAALgADCgkJEQAAAA==.',
['Vø']='Vøid:BAAALgAFFAIJAwABLgAFFAcJFgAIAO4SAA==.',
Wa='Waddledoo:BAAALgAECgMJBQAAAA==.Walruskíng:BAABLgAECn8hAAIFAAcJfR0IGQDZAQAFAAcJfR0IGQDZAQAAAA==.Wardaddy:BAAALgAECgYJEgAAAA==.Warkind:BAAALgAECgMJAwAAAA==.Warmage:BAAALgAECgIJAgAAAA==.Warmaku:BAABLgAECn8cAAMMAAgJSBzVFgBuAgAMAAgJSBzVFgBuAgAaAAEJ9QLcOQAhAAAAAA==.Warmohg:BAAALgAECgYJCwAAAA==.Wasred:BAAALgADCgkJCQAAAA==.',
We='Weezybaby:BAABLgAECn8jAAMcAAkJgA95DgCPAQAcAAkJgA95DgCPAQAHAAEJVQR2pQAqAAAAAA==.Wenjiesmom:BAAALgAECgEJAQAAAA==.',
Wh='Whitecosmos:BAAALgAECgMJBgABLgAFFAUJFAAXAFUmAA==.Whohe:BAAALgAECgEJAQAAAA==.',
Wi='Wigwog:BAABLgAECn8WAAIFAAcJWhvHHQCwAQAFAAcJWhvHHQCwAQAAAA==.Windfury:BAACLgAFFH8XAAIcAAYJQiINAQDLAQAcAAYJQiINAQDLAQAuAAQKfy4AAhwACQmtJLABAEwDABwACQmtJLABAEwDAAAA.Windycrits:BAAALgADCgUJAQABLgADCgcJBwAKAAAAAA==.Winterfella:BAAALgAECgEJAQAAAA==.Wirantimer:BAAALgAECgYJDwAAAA==.Wishofwar:BAAALgADCgUJBQABLgAECggJIgASAEQcAA==.Witfuk:BAAALgADCgUJBQAAAA==.',
Wo='Wogasaurus:BAAALgAECggJDgAAAA==.Woobee:BAAALgAECgEJAQAAAA==.',
Wu='Wulrok:BAAALgAECgMJAwAAAA==.Wuzo:BAAALgAECgMJAwAAAA==.',
Wy='Wykka:BAABLgAECn8VAAIDAAkJghCXDQBLAQADAAkJghCXDQBLAQAAAA==.Wyverynn:BAABLgAECn8UAAITAAcJthROewCNAQATAAcJthROewCNAQAAAA==.',
['Wí']='Wínter:BAAALgADCgMJAwAAAA==.',
Xa='Xami:BAAALgADCgkJCQAAAA==.Xany:BAAALgAECgUJCwAAAA==.',
Xc='Xcomunicated:BAAALgADCgUJBQAAAA==.',
Xe='Xenomortis:BAAALgAECgcJDwAAAA==.Xephanie:BAAALgAECgEJBAAAAA==.',
Xi='Xinlucia:BAAALgAECgkJDwAAAA==.',
Xo='Xofu:BAAALgAECgEJBAAAAA==.Xoro:BAAALgAECgMJBAAAAA==.',
Xr='Xrxyz:BAACLgAFFH8PAAISAAUJhBm7KAA+AQASAAUJhBm7KAA+AQAuAAQKfyIAAhIACAnVHOcoAIECABIACAnVHOcoAIECAAAA.',
Xy='Xylus:BAAALgAECgIJAgAAAA==.',
Ya='Yabe:BAAALgAECgMJAwAAAA==.',
Ye='Yen:BAAALgADCgIJAgAAAA==.Yetibear:BAAALgAECgIJAgAAAA==.Yewna:BAAALgAECgYJDwAAAA==.',
Yy='Yyrella:BAAALgADCgIJAgABLgAECgcJFAATAHoTAA==.',
Za='Zachdem:BAAALgAECgQJBAAAAA==.Zachdrac:BAAALgADCgQJBAAAAA==.Zaemor:BAAALgAECgMJBAAAAA==.Zau:BAAALgADCgkJCQAAAA==.',
Ze='Zebrabutt:BAABLgAECn8vAAMPAAkJchOAHADRAQAPAAkJehKAHADRAQAcAAgJWw4wEQCkAQAAAA==.Zed:BAAALgAECgYJBgABLgAECggJIwAXADwkAA==.Zenstation:BAAALgADCgEJAQAAAA==.Zero:BAAALgAECgcJEgAAAA==.',
Zi='Ziccem:BAABLgAECn8zAAIVAAgJwx67DwA8AgAVAAgJwx67DwA8AgABLgAECgkJJAABADYgAA==.Ziggawâ:BAAALgAECgYJDAABLgAECggJKwARAEUVAA==.Zildjìan:BAAALgAECgEJAQAAAA==.Zionsmender:BAAALgAECgYJDwAAAA==.',
Zo='Zolja:BAAALgAECgMJAwAAAA==.Zoney:BAAALgADCgIJAwAAAA==.Zordlon:BAAALgAECgMJBgAAAA==.',
Zu='Zukem:BAAALgAECgUJBQAAAA==.Zuli:BAAALgAECgYJBwABLgAFFAMJBwACAMUYAA==.Zuretull:BAAALgAFFAIJAgAAAA==.',
Zy='Zynlord:BAAALgADCgEJAQAAAA==.Zyvea:BAAALgAECgYJEQAAAA==.',
['Çh']='Çharacter:BAAALgADCgYJBgAAAA==.',
['Çr']='Çrossblesser:BAAALgAECgQJEQAAAA==.',
['ßa']='ßamboo:BAAALgADCgYJDAABLgAECgcJHAASAKIXAA==.',
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
