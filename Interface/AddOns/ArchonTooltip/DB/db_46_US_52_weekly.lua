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

local lookup = {'Hunter-BeastMastery','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Priest-Holy','Shaman-Restoration','Mage-Frost','Monk-Mistweaver','Unknown-Unknown','Paladin-Holy','Druid-Restoration','DemonHunter-Vengeance','Hunter-Survival','Monk-Brewmaster','Paladin-Protection','Shaman-Elemental','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Blood','Druid-Balance','DemonHunter-Devourer','Monk-Windwalker','Druid-Guardian','Mage-Fire','Druid-Feral','Warrior-Fury','Shaman-Enhancement','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','Priest-Discipline','DemonHunter-Havoc','Hunter-Marksmanship','Warrior-Protection','Mage-Arcane','Rogue-Outlaw','Rogue-Subtlety','DeathKnight-Frost','Rogue-Assassination',}
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abeblinken:BAAALgAECgQJBgAAAA==.Abraaham:BAAALgAECgEJAgAAAA==.',
Ad='Adym:BAABLgAECn8ZAAIBAAkJOBnwHABYAgABAAkJOBnwHABYAgAAAA==.',
Ae='Aermo:BAAALgADCgYJBgAAAA==.Aethos:BAABLgAECn9CAAQCAAgJ4hxIHAA+AgACAAgJ4hxIHAA+AgADAAEJ+xcSKwBJAAAEAAIJoBn7KQBGAAAAAA==.Aeyther:BAABLgAECn8WAAMFAAkJghiKGgAKAgAFAAkJghiKGgAKAgAGAAIJgBJVawB+AAAAAA==.',
Ag='Agave:BAABLgAECn8xAAIHAAgJuBYTHAAUAgAHAAgJuBYTHAAUAgAAAA==.Agony:BAAALgAECgEJAwAAAA==.',
Ah='Ahluethedrud:BAAALgADCgUJBQAAAA==.',
Ai='Airbnb:BAAALgADCgQJBAAAAA==.',
Al='Aleynah:BAAALgADCggJIQABLgAECggJNwAEAP8KAA==.Alukarrd:BAAALgAECgMJBQAAAA==.',
Am='Aminadab:BAAALgADCgYJBgAAAA==.Amoraniel:BAABLgAECn8jAAIIAAkJpyCqGgCBAgAIAAkJpyCqGgCBAgAAAA==.Amortin:BAAALgADCgEJAQAAAA==.',
An='Anavar:BAABLgAECn8jAAIJAAkJqhvVDgBpAgAJAAkJqhvVDgBpAgAAAA==.Ancestral:BAAALgADCgEJAQABLgAECgkJFAAKAAAAAA==.Andrar:BAAALgADCgMJBAAAAA==.Andresra:BAABLgAECn8UAAIIAAcJ3RcZZwAJAgAIAAcJ3RcZZwAJAgAAAA==.Angelle:BAABLgAECn8tAAILAAgJPCRZBwDVAgALAAgJPCRZBwDVAgAAAA==.Annakin:BAABLgAECn8hAAIMAAkJ0Rh7IgA0AgAMAAkJ0Rh7IgA0AgAAAA==.Annaluna:BAAALgAECgUJBgAAAA==.Anomally:BAAALgAECgEJAQAAAA==.Anzhelika:BAAALgADCgMJAwAAAA==.',
Ar='Arararagi:BAAALgAECgUJBQAAAA==.Arawn:BAAALgADCgYJBgAAAA==.Arctica:BAABLgAECn8pAAINAAkJMx3LAwCPAgANAAkJMx3LAwCPAgAAAA==.Arelà:BAAALgAFFAEJAwAAAA==.Aria:BAABLgAECn8nAAIJAAgJ7iPMAwAwAwAJAAgJ7iPMAwAwAwAAAA==.Aristoteles:BAAALgAECgEJAQAAAA==.Arron:BAAALgAECgIJAgAAAA==.Arrowsnag:BAABLgAECn8WAAIOAAkJwAUsGQCLAQAOAAkJwAUsGQCLAQAAAA==.Articdemon:BAAALgADCgkJFAAAAA==.Artics:BAAALgAECgEJAQAAAA==.Arya:BAABLgAFFH8FAAIFAAMJSwy6FwDmAAAFAAMJSwy6FwDmAAAAAA==.Arylynn:BAAALgADCgYJBgABLgAECgkJKAAPAMsjAA==.',
As='Ashley:BAAALgAECgMJCQAAAA==.Asrael:BAAALgAECgcJBwABLgAECggJKAAQAHsUAA==.Astradaeus:BAAALgADCgMJAwAAAA==.Astridaya:BAAALgAECgEJBAAAAA==.',
Au='Aunumator:BAAALgAECgYJDAAAAA==.',
Av='Avert:BAAALgAECgEJAQAAAA==.Avâtre:BAABLgAECn8gAAIRAAkJlxOKIQCCAQARAAkJlxOKIQCCAQAAAA==.',
Ba='Baba:BAAALgADCgcJAQAAAA==.Baccaj:BAAALgAECgYJCgAAAA==.Baeblue:BAAALgAECgYJDQABLgAECggJIgASAEMcAA==.Baguette:BAAALgAECgEJAQAAAA==.Bajingobomb:BAABLgAECn8mAAMTAAkJwB8MLwB8AgATAAkJwB8MLwB8AgAUAAEJpREwRgAvAAAAAA==.Baked:BAAALgAECgMJBgAAAA==.Ballmelazer:BAAALgAECgEJAQAAAA==.Barasuishou:BAAALgAECgEJAQABLgAECggJJgADACAhAA==.Barkruffalo:BAACLgAFFH8IAAIMAAIJZRBcPACBAAAMAAIJZRBcPACBAAAuAAQKfzoAAwwACQnHHrQHAAEDAAwACQnHHrQHAAEDABUABglXFZInADYBAAAA.Barktotem:BAAALgADCgQJBAAAAA==.Barkwoven:BAAALgADCgcJBwAAAA==.Battleborne:BAAALgAECgEJAQAAAA==.Bayln:BAAALgADCgcJBgABLgABCgUJBQAKAAAAAA==.',
Be='Beckyoncé:BAABLgAECn8zAAIWAAgJ6iNXDQCdAgAWAAgJ6iNXDQCdAgAAAA==.Bedris:BAABLgAECn8iAAMSAAkJxA5TTQCWAQASAAkJ6Q1TTQCWAQAQAAUJUAtkKwCyAAAAAA==.Beerticus:BAABLgAECn8YAAIXAAgJeRxMDAAyAgAXAAgJeRxMDAAyAgAAAA==.Bekkar:BAAALgAECgQJBQAAAA==.Belcebu:BAAALgAECgIJBAAAAA==.Berim:BAAALgAECgQJBQAAAA==.',
Bi='Bigdingus:BAABLgAECn8ZAAIYAAkJQB2sBQB8AgAYAAkJQB2sBQB8AgAAAA==.Binggles:BAACLgAFFH8bAAMIAAgJBxo8BABjAgAIAAgJBxo8BABjAgAZAAEJXQHLAQBDAAAuAAQKfyUAAggACAl+JXwSADgDAAgACAl+JXwSADgDAAAA.Bingglestwo:BAAALgAECgMJAwABLgAFFAgJGwAIAAcaAA==.',
Bl='Blackastraza:BAAALgAECgIJAgAAAA==.Blacksheep:BAAALgAECgQJBwAAAA==.Blanketparty:BAABLgAECn8ZAAMRAAgJxRosFgDiAQARAAgJxRosFgDiAQAHAAEJXw8cmwAuAAAAAA==.Blazze:BAAALgAECgEJAQAAAA==.Blinkyshadow:BAAALgADCgMJAwAAAA==.Bloodraven:BAACLgAFFH8LAAIMAAMJvRvNHwAJAQAMAAMJvRvNHwAJAQAuAAQKfzkAAwwACQl2H1sLAMoCAAwACQl2H1sLAMoCABoAAwmNFZYbAMcAAAAA.Bluballs:BAAALgAECgkJCQAAAA==.Bluebabyfox:BAAALgADCgIJAgAAAA==.Blëwm:BAAALgADCgcJDQABLgAECgkJHAAPABIWAA==.',
Bo='Boaj:BAACLgAFFH8MAAIbAAMJfxPyIQDdAAAbAAMJfxPyIQDdAAAuAAQKfyMAAhsACQk0GbkYANoBABsACQk0GbkYANoBAAAA.Bobette:BAABLgAECn8UAAIcAAgJDwg1FQBpAQAcAAgJDwg1FQBpAQAAAA==.Bodyspray:BAABLgAECn8dAAISAAkJ0BwwHgBOAgASAAkJ0BwwHgBOAgAAAA==.Boolay:BAABLgAECn8fAAIQAAkJliDSAwCBAgAQAAkJliDSAwCBAgAAAA==.Bootyfire:BAABLgAECn8ZAAIIAAgJ9RF9aAAFAgAIAAgJ9RF9aAAFAgAAAA==.Boozing:BAAALgAECgkJCgAAAA==.Bopstds:BAAALgAECgEJAQAAAA==.Bosmina:BAACLgAFFH8LAAIGAAMJIg0gFgC7AAAGAAMJIg0gFgC7AAAuAAQKfzYAAgYACQnHFKISAP4BAAYACQnHFKISAP4BAAAA.Botanicaljoe:BAAALgAECgQJBAAAAA==.',
Br='Braeibo:BAABLgAECn8cAAIBAAgJew6tQwB+AQABAAgJew6tQwB+AQAAAA==.Breelynn:BAAALgADCgcJBwAAAA==.Breida:BAAALgAECgUJCAAAAA==.Brenmonk:BAAALgAECgcJBwAAAA==.Brielle:BAAALgADCgEJAQAAAA==.Brolerion:BAAALgADCgQJBAAAAA==.',
Bu='Bubblebaddie:BAAALgAECggJEgAAAA==.Bugenhagen:BAAALgAECgQJCwABLgAECgYJDgAKAAAAAA==.Buttpaladin:BAABLgAECn8YAAISAAgJRSMCDwC1AgASAAgJRSMCDwC1AgAAAA==.',
['Bë']='Bëldin:BAAALgADCggJCwAAAA==.',
Ca='Canelo:BAAALgADCgUJBQAAAA==.Cantheal:BAAALgADCgYJBgAAAA==.Carademuerta:BAAALgAECgcJEAAAAA==.Cardib:BAABLgAFFH8MAAITAAUJyx3lJgBlAQATAAUJyx3lJgBlAQAAAA==.Cavos:BAABLgAECn8tAAIWAAkJDBkdGwAuAgAWAAkJDBkdGwAuAgAAAA==.',
Ce='Cernsarn:BAABLgAECn8yAAIUAAgJNBTmEACnAQAUAAgJNBTmEACnAQAAAA==.',
Ch='Chandlef:BAAALgAECgQJBAAAAA==.Chantorc:BAAALgADCgYJCgAAAA==.Chickendad:BAAALgAECgUJBQAAAA==.Chigang:BAAALgADCgMJAwAAAA==.Chiri:BAEBLgAECn8gAAQdAAkJZBFmBgCeAQAdAAgJZxBmBgCeAQAeAAYJdQuPNQAkAQAfAAUJYxCHJAB6AAAAAA==.Chocc:BAAALgADCgIJAgAAAA==.Chvngus:BAABLgAECn8jAAISAAgJsyDpGABuAgASAAgJsyDpGABuAgAAAA==.',
Ci='Cindersam:BAAALgAECgYJCQABLgAECgcJFAATALYUAA==.',
Cl='Clawsoh:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.Climene:BAAALgADCgYJCwABLgAECggJIgASAEMcAA==.',
Co='Cocheeze:BAAALgAECgUJBQAAAA==.Coffeebeen:BAAALgADCgcJCAAAAA==.Condor:BAECLgAFFH8GAAIVAAMJ9RxSGQAHAQAVAAMJ9RxSGQAHAQAuAAQKfx0AAhUACQlBJSQCACoDABUACQlBJSQCACoDAAAA.Conmammoth:BAAALgAECgQJCgAAAA==.Coohwhip:BAAALgAECgcJEAAAAA==.Cowwithhorns:BAABLgAECn8fAAMbAAkJIRVlKgAPAgAbAAgJIhJlKgAPAgAgAAUJVhN7GgArAQAAAA==.',
Cr='Cristobal:BAAALgAECgkJEAAAAA==.Cronùs:BAAALgAECggJDAAAAA==.Crunkshot:BAABLgAECn8XAAMSAAcJLwONugARAQASAAcJLwONugARAQALAAYJJQPOawDKAAAAAA==.',
Cu='Curaga:BAAALgAECgUJBQAAAA==.Curnsarn:BAAALgAECgcJCgABLgAECggJMgAUADQUAA==.Curtis:BAABLgAECn8UAAQGAAcJ9Q14PwA8AQAGAAcJ9Q14PwA8AQAFAAMJsxWDRwDEAAAhAAEJEAMOXwAkAAAAAA==.',
Cy='Cyalaterz:BAAALgAECgEJAQAAAA==.Cyrail:BAABLgAECn8pAAILAAkJrCOHBQATAwALAAkJrCOHBQATAwAAAA==.',
['Cø']='Cøven:BAACLgAFFH8IAAMVAAMJaRX9JgCPAAAVAAIJwxD9JgCPAAAMAAIJbBEVOACOAAAuAAQKfzMAAxUACQnCHs4MAMwCABUACQnCHs4MAMwCAAwABAmQEGWdAJAAAAAA.',
Da='Dan:BAAALgAECgEJAQAAAA==.Dapöpe:BAAALgADCgQJBAABLgAECgYJGgASAEkWAA==.Darkmonks:BAAALgAECgUJCgAAAA==.Darksoulstwo:BAAALgAECgYJDAAAAA==.Darktoxi:BAABLgAECn8bAAIJAAgJ0RrvDwA+AgAJAAgJ0RrvDwA+AgABLgAECggJJQAWAHUVAA==.Darkwarden:BAAALgADCgEJAQAAAA==.Darthpooper:BAAALgAECgYJBgABLgAFFAMJCwASAGoXAA==.Dastaan:BAAALgAECgEJAgAAAA==.Dauntus:BAACLgAFFH8UAAIIAAYJDxVdFQCyAQAIAAYJDxVdFQCyAQAuAAQKfzUAAggACQlFIWQLAO4CAAgACQlFIWQLAO4CAAAA.Dawnclaw:BAAALgADCgUJBQAAAA==.Daydream:BAAALgAECgEJAQAAAA==.',
De='Deathclock:BAABLgAECn8tAAITAAkJWCAVDQAyAwATAAkJWCAVDQAyAwAAAA==.Deep:BAAALgADCgEJAQAAAA==.Degey:BAAALgAECgYJEAAAAA==.Deign:BAACLgAFFH8IAAIiAAMJ4QD8FACGAAAiAAMJ4QD8FACGAAAuAAQKfy4AAiIACQlgDLAYAFQBACIACQlgDLAYAFQBAAAA.Delayne:BAAALgAECggJCQAAAA==.Demoncrat:BAAALgAFFAEJAQAAAA==.Demonicramen:BAAALgAECgIJAgAAAA==.Demonstroza:BAAALgAECgUJBQABLgAECgkJEQAKAAAAAA==.Demontotems:BAAALgAECgMJCQAAAA==.Demotoxi:BAABLgAECn8lAAIWAAgJdRWXMAC6AQAWAAgJdRWXMAC6AQAAAA==.Deriso:BAABLgAECn8WAAMBAAkJMiPeDQCcAgABAAgJkCLeDQCcAgAjAAYJ9R43KwDTAQAAAA==.Derpthyr:BAAALgADCgMJAwAAAA==.Destrozinth:BAAALgAECgkJEQAAAA==.Dethorok:BAABLgAECn8lAAQOAAgJyiMnBAC5AgAOAAgJWSMnBAC5AgAjAAYJjSTzIgAPAgABAAUJlCAKVwBDAQAAAA==.Deuce:BAAALgAECgQJBQAAAA==.Deåth:BAAALgAFFAEJAQAAAA==.',
Dh='Dhamon:BAAALgADCgYJBgAAAA==.',
Di='Dieworc:BAAALgADCgkJFgAAAA==.Digey:BAABLgAECn8WAAIkAAkJtSJaBgDLAgAkAAkJtSJaBgDLAgAAAA==.Digitz:BAABLgAECn8cAAMIAAgJTBYEVwAzAgAIAAgJTBYEVwAzAgAlAAEJAABAHgA1AAAAAA==.Direwolf:BAAALgAECgUJBgAAAA==.Dirtnapp:BAAALgAECgMJCAAAAA==.Divah:BAABLgAECn83AAIEAAgJ/woJDQAgAQAEAAgJ/woJDQAgAQAAAA==.Divinelight:BAAALgAECgEJAQAAAA==.',
Do='Dogehh:BAAALgADCgIJAgAAAA==.Dogèhh:BAAALgAECgEJAQAAAA==.Donald:BAABLgAECn8cAAIBAAgJ3w/YQQCFAQABAAgJ3w/YQQCFAQAAAA==.Donbolo:BAAALgAECgUJDgAAAA==.Dopeaf:BAABLgAECn8VAAMkAAgJwA4KEwBrAQAkAAgJwA4KEwBrAQAbAAEJiAI0sQApAAAAAA==.Dotpotato:BAAALgADCgIJAgAAAA==.Dotterparty:BAAALgAECgQJBAAAAA==.Dowkia:BAAALgAECgEJBAAAAA==.Downwarddog:BAAALgADCgYJBwAAAA==.',
Dr='Dragonmaas:BAAALgADCgYJBgAAAA==.Dragonwings:BAECLgAFFH8MAAIIAAQJwwSOTAATAQAIAAQJwwSOTAATAQAuAAQKfxgAAggABwk7Ft19ANUBAAgABwk7Ft19ANUBAAAA.Drakah:BAAALgAECgIJAgAAAA==.Drakbek:BAAALgAECgYJEgAAAA==.Dreaknite:BAAALgADCgQJBgAAAA==.Dreamshift:BAABLgAECn8eAAMMAAgJZBvRHgAIAgAMAAgJZBvRHgAIAgAVAAIJbQenXABNAAAAAA==.Dreco:BAABLgAECn8dAAIWAAcJrh6vJQBxAgAWAAcJrh6vJQBxAgAAAA==.Drekken:BAAALgAECgMJBQAAAA==.Drelik:BAAALgADCgIJAgAAAA==.Dronebot:BAABLgAECn8yAAMFAAgJhCMaBgC1AgAFAAgJhCMaBgC1AgAGAAMJngpuZwCPAAAAAA==.Drucifer:BAABLgAECn8UAAIcAAcJ3A6gFQBjAQAcAAcJ3A6gFQBjAQAAAA==.Druelf:BAAALgAECgMJAwAAAA==.Druiwny:BAAALgAECgMJAwAAAA==.Drék:BAAALgAECgYJDgAAAA==.Drúcifer:BAAALgADCgkJEgAAAA==.',
Du='Dud:BAABLgAECn8hAAICAAgJnx3HHAA6AgACAAgJnx3HHAA6AgAAAA==.Duelme:BAAALgAECgMJBAABLgAECggJFQAkAMAOAA==.Dugaa:BAAALgAECgQJBAAAAA==.Dumbdwagon:BAABLgAECn8lAAIfAAgJLgsOEgBeAQAfAAgJLgsOEgBeAQAAAA==.Dumblecrumb:BAAALgADCgQJBAAAAA==.Dumbrouge:BAAALgAECgIJAwABLgAECggJKAAQAHsUAA==.Dustyshotz:BAAALgAECgUJCQAAAA==.',
Dw='Dwall:BAAALgAECgMJAwAAAA==.Dwarfgasm:BAAALgAECgkJAQAAAA==.Dwarfladin:BAAALgAECgEJAQAAAA==.Dwarriorarf:BAAALgAECgQJBgAAAA==.',
Dz='Dzieux:BAAALgADCgYJBwAAAA==.',
['Dë']='Dëadisbetter:BAAALgADCgEJAQAAAA==.',
['Dö']='Dögehh:BAAALgAECgcJEgAAAA==.',
['Dø']='Døgehh:BAAALgAECgEJAQAAAA==.',
Ee='Eeseo:BAAALgAECgEJAgAAAA==.',
Eg='Eggblack:BAAALgAECgQJCAAAAA==.',
El='Ellegryn:BAAALgADCgEJAgAAAA==.Elvebring:BAABLgAECn8cAAIiAAcJsBsrGQD8AQAiAAcJsBsrGQD8AQABLgAFFAMJBgALAFYaAA==.',
Em='Embody:BAABLgAECn8cAAIVAAgJfRFDHgB7AQAVAAgJfRFDHgB7AQAAAA==.Emilio:BAAALgAECgEJAgAAAA==.',
En='Endlyss:BAAALgAECgUJBQAAAA==.',
Er='Erikira:BAAALgAECgcJEgAAAA==.Erikk:BAABLgAECn8WAAITAAgJSQoJYQBdAQATAAgJSQoJYQBdAQAAAA==.Eryngium:BAABLgAECn8aAAIMAAgJkBk3GgAsAgAMAAgJkBk3GgAsAgAAAA==.',
Es='Essentia:BAAALgAECgEJAQAAAA==.',
Et='Ethantherat:BAAALgAECgEJAQAAAA==.',
Eu='Euphoricx:BAACLgAFFH8IAAIHAAMJvxcAIwAAAQAHAAMJvxcAIwAAAQAuAAQKfzAAAgcACQlIJvcCAE4DAAcACQlIJvcCAE4DAAAA.',
Ev='Evildeader:BAABLgAECn8UAAITAAcJehPGdgCYAQATAAcJehPGdgCYAQAAAA==.Eviltotems:BAAALgAECgQJBQABLgAECgcJFAATAHoTAA==.',
Ex='Exalt:BAAALgAECgcJEgAAAA==.Exes:BAAALgADCggJCAABLgAFFAMJBQAFAEsMAA==.Expand:BAABLgAECn8WAAIXAAkJSBrcFQA7AgAXAAkJSBrcFQA7AgAAAA==.',
Ey='Eyeseyesbaby:BAABLgAECn8ZAAIWAAkJKhxcIAANAgAWAAkJKhxcIAANAgAAAA==.',
Ez='Ezbakeovens:BAAALgAFFAIJAgAAAA==.',
Fa='Facelift:BAAALgAECgEJAgAAAA==.Faithles:BAACLgAFFH8IAAIFAAMJxg/+FwDkAAAFAAMJxg/+FwDkAAAuAAQKfywAAgUACQmKHcMGAKMCAAUACQmKHcMGAKMCAAAA.Falgur:BAACLgAFFH8LAAMHAAMJSATTNwCiAAAHAAMJSATTNwCiAAARAAIJORAJFwCaAAAuAAQKfzcAAxEACQlbIFoGALsCABEACQlbIFoGALsCAAcAAwnBCSV1AIcAAAAA.Fallenlord:BAAALgADCgcJBwAAAA==.Fantasma:BAAALgAECgQJDAAAAA==.Fasty:BAABLgAECn8mAAIJAAkJRhToHgC9AQAJAAkJRhToHgC9AQAAAA==.Faygochugger:BAAALgAECggJCgAAAA==.',
Fe='Fear:BAAALgAECgEJAgAAAA==.Felmajik:BAAALgADCgMJBQAAAA==.',
Fi='Fifths:BAAALgADCgUJBQAAAA==.Finley:BAAALgADCgMJAwAAAA==.Fivemagics:BAABLgAECn8eAAMCAAkJ0RmHJgAFAgACAAgJ0RmHJgAFAgAEAAIJmBTSTgCBAAAAAA==.',
Fl='Flayvour:BAAALgAECgQJBAABLgAECgkJHAAPABIWAA==.Fleaboy:BAABLgAECn8WAAMmAAYJQhUGCQBFAQAmAAYJQhUGCQBFAQAnAAQJMgYITwCzAAAAAA==.Fleshwound:BAAALgADCgYJBgAAAA==.Flist:BAABLgAECn8gAAIXAAgJKCTnCABuAgAXAAgJKCTnCABuAgAAAA==.',
Fo='Fongsaiyok:BAAALgAECgEJAwAAAA==.Foregord:BAAALgADCgUJBQABLgABCgUJBQAKAAAAAA==.Fortlock:BAAALgAECgQJBwAAAA==.Fotation:BAAALgAECgQJBAAAAA==.',
Fr='Frankensteyn:BAAALgADCgkJCQAAAA==.Frankyice:BAABLgAECn8eAAIFAAkJ5g/wFwC0AQAFAAkJ5g/wFwC0AQAAAA==.Freesia:BAABLgAECn8aAAISAAYJWRAbkABcAQASAAYJWRAbkABcAQAAAA==.French:BAAALgAECggJDQAAAA==.Froggyfresh:BAAALgADCgYJCAAAAA==.Fruitjuice:BAABLgAECn8UAAIEAAYJrBraBwCCAQAEAAYJrBraBwCCAQAAAA==.',
Fu='Funbobby:BAAALgAECgUJBgAAAA==.',
Fx='Fxce:BAAALgAECgQJBAAAAA==.',
['Fâ']='Fâmine:BAABLgAECn8gAAICAAkJLBW8JQAKAgACAAkJLBW8JQAKAgAAAA==.',
Ga='Galautee:BAAALgAECgEJAQAAAA==.Gamakichi:BAAALgAECgEJAQAAAA==.Gambitt:BAAALgADCgUJBQAAAA==.Gamer:BAAALgADCgcJDAABLgAECgYJDgAKAAAAAA==.Gamergirl:BAAALgAECgYJDgAAAA==.Ganjj:BAAALgAECgEJAQAAAA==.Gawdric:BAACLgAFFH8TAAMTAAYJJh5gDwC+AQATAAUJJh5gDwC+AQAUAAEJAAB/NgAAAAAuAAQKfx8AAxMACAlWIZwsAIYCABMACAlWIZwsAIYCACgAAQnOC00YAC4AAAAA.',
Gb='Gboozing:BAAALgAECgkJCQAAAA==.',
Ge='Geekminator:BAAALgAECgQJBAAAAA==.Georgesoros:BAABLgAECn8WAAQeAAkJNB3xHQCWAQAeAAgJNB3xHQCWAQAdAAEJAACCOQBOAAAfAAIJuAFCLgA5AAAAAA==.',
Gh='Ghibludgeon:BAAALgADCgIJAgAAAA==.Ghiboom:BAAALgAECgEJAgAAAA==.Ghulz:BAABLgAECn8gAAMCAAgJGRTcVgBZAQACAAgJ7QvcVgBZAQADAAUJORdTDgAEAQAAAA==.Ghuntarr:BAAALgADCgcJDAAAAA==.',
Gi='Gibsmedats:BAABLgAECn8fAAMWAAkJ1BJ3QgDqAQAWAAgJkRJ3QgDqAQAiAAMJFhF5LAC5AAAAAA==.Giin:BAAALgAECgEJAwAAAA==.Gildark:BAAALgADCgEJAQAAAA==.',
Gl='Glaiven:BAABLgAECn8TAAIWAAcJMiDFHgCZAgAWAAcJMiDFHgCZAgAAAA==.Glasscleaner:BAAALgAECgcJEQABLgAFFAMJDAAJAHImAA==.Glenfarclas:BAAALgAECgYJBgAAAA==.Glenfiddich:BAABLgAECn8gAAITAAkJjiHgEACnAgATAAkJjiHgEACnAgAAAA==.',
Gn='Gnartusk:BAABLgAECn8mAAIUAAgJ0iR4AwDRAgAUAAgJ0iR4AwDRAgAAAA==.Gnomett:BAAALgADCgEJAQAAAA==.',
Go='Goblinsham:BAAALgAECgEJAQAAAA==.Gordrack:BAAALgAECggJCwAAAA==.',
Gr='Grandmapunch:BAAALgADCgIJAgABLgAECgcJFAAGAPUNAA==.Grasswizard:BAAALgAECggJEQAAAA==.Greela:BAAALgADCgIJAgAAAA==.Greens:BAABLgAECn8WAAIVAAYJPxbBLQAQAQAVAAYJPxbBLQAQAQAAAA==.Gremory:BAAALgADCgYJBwAAAA==.Gru:BAAALgAECggJDgAAAA==.Grïma:BAAALgADCgcJDQABLgAFFAMJCAAVAGkVAA==.',
Gu='Gueritestje:BAABLgAECn8yAAIQAAkJyyKJAQD3AgAQAAkJyyKJAQD3AgAAAA==.Guzzlord:BAAALgAECgkJEwAAAA==.',
Ha='Hairinear:BAAALgAECgEJAQAAAA==.Hambo:BAAALgAECgkJBQAAAA==.Handsomejack:BAAALgAECgEJAQABLgAECgkJJgATAMAfAA==.Hanekawa:BAAALgAECgUJBwABLgAECggJJgADACAhAA==.Harddwarf:BAAALgAECgEJAQAAAA==.Haugcraneka:BAAALgADCgYJBgAAAA==.Hawts:BAAALgAECgEJAQAAAA==.',
He='Heleous:BAABLgAECn8iAAMSAAgJQxy2KAAWAgASAAgJQxy2KAAWAgAQAAEJHg47RAAuAAAAAA==.',
Hi='Hibernus:BAAALgADCgUJBQABLgAECgYJGgASAEkWAA==.Highly:BAAALgADCgIJAgAAAA==.Hikari:BAABLgAECn80AAIiAAgJPRT8EgCZAQAiAAgJPRT8EgCZAQAAAA==.Himalayanman:BAAALgAECgkJDgAAAA==.Hipdrop:BAAALgAECgEJAQAAAA==.Hitemup:BAAALgAECgEJBgAAAA==.Hitoshura:BAABLgAECn8iAAMoAAgJcSSgAQC5AgAoAAgJAySgAQC5AgATAAYJZSTVMgDtAQAAAA==.',
Ho='Hobbeswerth:BAABLgAECn8UAAIJAAYJEhCMNQAZAQAJAAYJEhCMNQAZAQAAAA==.Holycowbun:BAAALgAECgUJDgABLgAECggJMgAWABoiAA==.Holyginger:BAAALgAECgYJBwAAAA==.Holyglizzy:BAABLgAECn8gAAISAAgJWBIdTgCUAQASAAgJWBIdTgCUAQAAAA==.Holysoup:BAAALgAECgEJAQAAAA==.Hornlet:BAAALgAECgEJAQABLgAECgIJBAAKAAAAAA==.Howitzerx:BAAALgAECgQJCQAAAA==.',
Hu='Hubbabubba:BAAALgAECgQJBAAAAA==.Huggies:BAABLgAECn8VAAIQAAYJWSFbCgDPAQAQAAYJWSFbCgDPAQAAAA==.Humdinger:BAAALgADCgYJCAAAAA==.Hush:BAAALgADCgUJBQAAAA==.',
Hy='Hypérîon:BAAALgAECgQJCwAAAA==.',
Ia='Iagging:BAACLgAFFH8MAAIJAAMJcibQEABVAQAJAAMJcibQEABVAQAuAAQKfzQAAgkACQkVJqEBAJADAAkACQkVJqEBAJADAAAA.',
Ib='Ibodan:BAAALgAECgUJCAAAAA==.',
Ic='Iceflinger:BAABLgAECn8oAAIIAAgJDx3nLgAbAgAIAAgJDx3nLgAbAgAAAA==.',
Id='Idjit:BAAALgADCgcJDQABLgAECgYJDgAKAAAAAA==.Idlehand:BAAALgAECgYJDAAAAA==.',
Ie='Ieatcats:BAACLgAFFH8LAAInAAMJ0g4XGgDrAAAnAAMJ0g4XGgDrAAAuAAQKfzYAAicACQmoHikHAHACACcACQmoHikHAHACAAAA.',
Ih='Ihuntdads:BAAALgAECgEJAQAAAA==.',
Il='Ilidia:BAAALgAECgEJAQAAAA==.',
Im='Imarri:BAAALgADCgYJCAAAAA==.Imjustakid:BAAALgADCgMJAwAAAA==.Immahuntyou:BAAALgAECgEJBgAAAA==.Imobelle:BAABLgAECn8hAAIIAAcJPhXTggDMAQAIAAcJPhXTggDMAQAAAA==.Imprepared:BAAALgAECgYJDgAAAA==.',
In='Indrani:BAABLgAECn8YAAIJAAgJKhzCCwB4AgAJAAgJKhzCCwB4AgAAAA==.Infidel:BAAALgAECgMJAwABLgAFFAUJDgAIAGQQAA==.',
Ip='Ippiekiyaymf:BAABLgAECn8bAAIFAAcJLxSdHwB0AQAFAAcJLxSdHwB0AQAAAA==.',
Ir='Irayne:BAAALgAECgcJDwAAAA==.Irisharcher:BAAALgAECgIJAgAAAA==.Irishman:BAAALgAECgUJBgAAAA==.',
Is='Ishooturface:BAABLgAECn8ZAAMBAAkJhhlSHAAtAgABAAkJhhlSHAAtAgAjAAYJ3g1aRQBAAQAAAA==.István:BAAALgADCgcJDQAAAA==.',
It='Itazki:BAABLgAECn8fAAMaAAkJvyIYAgDRAgAaAAkJvyIYAgDRAgAVAAEJMw1ubQAqAAAAAA==.',
Ja='Jardabeans:BAAALgAECgQJCAAAAA==.Jarjárßlinks:BAAALgAECgYJDwAAAA==.Jawz:BAAALgAECgMJBQAAAA==.',
Je='Jeff:BAAALgADCgMJAgAAAA==.Jelial:BAAALgAECgcJBwAAAA==.Jenga:BAAALgAECggJDgAAAA==.Jerriblank:BAAALgADCgcJCAAAAA==.',
Jf='Jf:BAABLgAECn8bAAQSAAkJmhSuKQASAgASAAkJmhSuKQASAgALAAQJwgg8UACcAAAQAAEJ6hVwOAA5AAAAAA==.',
Ji='Ji:BAABLgAECn8rAAIXAAgJOxiOFgA0AgAXAAgJOxiOFgA0AgAAAA==.Jibbage:BAACLgAFFH8OAAIIAAUJZBBCDwCeAQAIAAUJZBBCDwCeAQAuAAQKfzMAAggACQlMIjsKAHIDAAgACQlMIjsKAHIDAAAA.Jitzakkal:BAACLgAFFH8eAAMCAAYJoyV4BAATAgACAAYJoyV4BAATAgAEAAEJwCZpDwB1AAAuAAQKfyQAAwQACQmKJSYFAIgCAAIACQmNIyEVANYCAAQABgmTJSYFAIgCAAAA.',
Jo='Johnpaladin:BAABLgAECn8hAAIQAAgJgh8nBADIAgAQAAgJgh8nBADIAgAAAA==.Joshswims:BAABLgAECn8fAAMTAAkJChV3NQDiAQATAAkJ7xR3NQDiAQAoAAQJARCxDQDRAAAAAA==.',
Js='Js:BAAALgADCgYJBgAAAA==.',
Ju='Jussie:BAAALgAECgEJAQAAAA==.',
Ka='Kadriel:BAAALgADCgEJAQAAAA==.Kaiserblade:BAAALgAECgQJBAABLgAECggJJgAUANIkAA==.Kambo:BAAALgAECgEJBAAAAA==.Kaptainkushh:BAAALgAECgQJEAAAAA==.Kaptkush:BAAALgAECgQJCQAAAA==.Kardinal:BAACLgAFFH8IAAMCAAMJDR6cQgACAQACAAMJDR6cQgACAQADAAEJGBkAAAAAAAAuAAQKfy0ABAIACQleITYSAOoCAAIACQleITYSAOoCAAQAAwmhH8gsAAsBAAMAAQmDHo4dAFsAAAAA.Karig:BAAALgADCgQJBQAAAA==.Karpathous:BAABLgAECn8UAAIBAAYJ6glzdgD0AAABAAYJ6glzdgD0AAAAAA==.Karrag:BAAALgAECgEJAQAAAA==.Karzo:BAAALgAECggJCQAAAA==.Kasawraa:BAAALgAECgUJBQAAAA==.Katena:BAAALgAECgYJDwAAAA==.Kaymir:BAABLgAECn8qAAQhAAgJjRqiEgD2AQAhAAgJgBeiEgD2AQAGAAMJyhxoVQDhAAAFAAMJ0AvUTwBoAAAAAA==.Kazdruid:BAAALgAECgYJCgAAAA==.Kaznathi:BAABLgAECn8oAAIPAAkJyyPTAQAnAwAPAAkJyyPTAQAnAwAAAA==.',
Ke='Keladorn:BAABLgAECn8iAAISAAcJlh1nNQDjAQASAAcJlh1nNQDjAQAAAA==.Keloril:BAAALgAECgQJCgAAAA==.',
Kh='Khanyiso:BAABLgAECn8oAAIQAAgJexSUCwC2AQAQAAgJexSUCwC2AQAAAA==.Kharak:BAABLgAECn8eAAIIAAgJwRGIWQCPAQAIAAgJwRGIWQCPAQABLgABCgUJBAAKAAAAAA==.',
Ki='Kieran:BAABLgAECn8qAAMFAAgJtg5kHwB2AQAFAAgJtg5kHwB2AQAGAAgJGwknLQAZAQAAAA==.Kikimora:BAABLgAECn8rAAQDAAgJEyCQAgBBAgADAAgJEyCQAgBBAgACAAYJshpjPgCjAQAEAAIJmxdvSACVAAAAAA==.Killsaurus:BAACLgAFFH8TAAIFAAUJ+xzECAB1AQAFAAUJ+xzECAB1AQAuAAQKfy4AAgUACAmeIMgLAEgCAAUACAmeIMgLAEgCAAAA.Kilsaurus:BAAALgAECgMJAwAAAA==.Kismetx:BAABLgAECn8fAAMVAAgJDQnILQAQAQAVAAgJDQnILQAQAQAMAAMJSgJvwQAhAAAAAA==.Kittysmasher:BAAALgAECgQJBAAAAA==.Kiue:BAAALgADCgEJAQAAAA==.',
Kn='Knomtseb:BAAALgADCgcJDgAAAA==.',
Ko='Koa:BAAALgAECgUJBwAAAA==.Koey:BAAALgAECgQJCQAAAA==.Korsho:BAAALgAECgEJAQAAAA==.Kosuke:BAAALgADCgUJBQAAAA==.',
Kr='Kriep:BAAALgAECgEJAgAAAA==.Kristian:BAAALgADCgcJBwAAAA==.Krittykitkat:BAAALgAECgkJCAABLgAECgkJIwAJAKobAA==.Krixos:BAAALgAECgYJCAABLgAFFAYJFAAIAA8VAA==.Kroshka:BAAALgADCgEJAQAAAA==.',
Kw='Kwarrior:BAAALgAECgEJAQABLgAECggJFwACAA4VAA==.Kwazlock:BAABLgAECn8XAAMCAAgJDhUTaQAtAQACAAcJbxITaQAtAQAEAAMJ2A5NQgCsAAAAAA==.',
Ky='Kybalion:BAAALgAECgQJBgABLgAECgUJBwAKAAAAAA==.Kyoju:BAABLgAECn8WAAIIAAcJRguqiAArAQAIAAcJRguqiAArAQABLgAFFAEJAQAKAAAAAA==.',
La='Laprimera:BAABLgAECn8ZAAIiAAYJSQm8JgDcAAAiAAYJSQm8JgDcAAAAAA==.Lazyjade:BAABLgAECn8iAAIFAAgJbg5RHwB2AQAFAAgJbg5RHwB2AQAAAA==.',
Le='Leyskrodan:BAABLgAECn8yAAMFAAgJfBHEGwCSAQAFAAgJfBHEGwCSAQAGAAEJKQMkiQAlAAAAAA==.',
Li='Lichborne:BAAALgAECgUJDgAAAA==.Lift:BAAALgADCggJCAABLgAECgkJFAAKAAAAAA==.Lightmilk:BAAALgADCgkJDwAAAA==.Listel:BAAALgADCgUJBQAAAA==.Lizardos:BAAALgAECgkJCgAAAA==.',
Lm='Lmnpeprstepr:BAAALgAECgEJAgAAAA==.',
Lo='Lockrocksftw:BAAALgADCgMJAwAAAA==.Lorynn:BAAALgAECgYJCgAAAA==.',
Lu='Lucyna:BAABLgAECn8pAAQCAAkJ5R5aJgAGAgACAAgJbx1aJgAGAgAEAAUJBh03EwCxAQADAAEJAABVIABxAAAAAA==.Lueshen:BAABLgAECn8bAAIXAAcJDx6zFABHAgAXAAcJDx6zFABHAgAAAA==.Luniea:BAAALgAECgEJAgAAAA==.',
Ly='Lysergicburn:BAAALgAECgQJBAABLgAECgYJDAAKAAAAAA==.Lyshin:BAAALgADCgQJBAAAAA==.',
['Lá']='Lárz:BAAALgAECgIJAwAAAA==.',
['Lü']='Lüktar:BAAALgADCgYJBgAAAA==.',
Ma='Madmarsh:BAAALgAECgQJBwABLgAECgkJEwAKAAAAAA==.Madwe:BAABLgAECn8aAAITAAgJ7RpbSwCZAQATAAgJ7RpbSwCZAQAAAA==.Magdalari:BAAALgAECgQJBQAAAA==.Maggams:BAAALgAECgEJAgAAAA==.Magnaur:BAAALgADCgcJDgAAAA==.Magturri:BAABLgAECn8mAAMBAAkJ4CKuCQD8AgABAAkJ4CKuCQD8AgAjAAIJihBMdgBmAAAAAA==.Mahilo:BAAALgAECgEJAQAAAA==.Maineck:BAABLgAECn8vAAIRAAkJ0x3rDQA/AgARAAkJ0x3rDQA/AgAAAA==.Maketaori:BAAALgADCgYJDAAAAA==.Malüm:BAAALgADCgIJAgABLgAECgYJGgASAEkWAA==.Mambosauce:BAAALgADCgUJBQAAAA==.Mangosmash:BAAALgAECgMJBQAAAA==.Maraline:BAAALgADCgYJBQAAAA==.Marcusdapimp:BAACLgAFFH8UAAIGAAYJjhdkAwDMAQAGAAYJjhdkAwDMAQAuAAQKfysAAgYACAmIIckFAPMCAAYACAmIIckFAPMCAAAA.Marymoocow:BAABLgAECn8ZAAIYAAYJKQ5aIADHAAAYAAYJKQ5aIADHAAAAAA==.Matild:BAABLgAECn8fAAILAAYJTSLsFgAFAgALAAYJTSLsFgAFAgAAAA==.Maxdiabolic:BAAALgADCgQJBAAAAA==.Maxfirepower:BAAALgAECgEJAgAAAA==.Maxfrogpower:BAAALgADCgYJDAAAAA==.Maxsunward:BAAALgAECgQJCAAAAA==.Maérline:BAAALgADCgcJDQABLgAECggJMgAFAIQjAA==.',
Me='Meatslug:BAAALgAECgUJBgAAAA==.Meepasaurus:BAABLgAECn8eAAIkAAcJyhqoEQB+AQAkAAcJyhqoEQB+AQAAAA==.Megaforce:BAAALgAECgQJBAAAAA==.Meliiodas:BAABLgAECn83AAIiAAgJNxGkFQB3AQAiAAgJNxGkFQB3AQAAAA==.Melisandre:BAAALgADCgIJAgAAAA==.Mellky:BAACLgAFFH8IAAIJAAMJFBX2GwDcAAAJAAMJFBX2GwDcAAAuAAQKfzAAAgkACQm3I30FAAoDAAkACQm3I30FAAoDAAAA.Merkin:BAAALgADCgcJBwAAAA==.Merrinx:BAABLgAECn8UAAMDAAYJXiYxAwBxAgADAAYJySUxAwBxAgAEAAIJWyPiFADEAAAAAA==.Metanoia:BAAALgAECgQJDAAAAA==.',
Mg='Mgamer:BAABLgAECn8dAAISAAgJuh8+GgBmAgASAAgJuh8+GgBmAgAAAA==.Mgämër:BAAALgAECgEJAQAAAA==.',
Mi='Midgetmanxl:BAAALgAECgEJAgAAAA==.Midnitetrvlr:BAAALgAECggJDwAAAA==.Miima:BAAALgAECgEJAgAAAA==.Minjeong:BAAALgAECgEJAQAAAA==.Minji:BAAALgAECgUJBQAAAA==.Mirren:BAABLgAECn8YAAIIAAgJ5RbhigC8AQAIAAgJ5RbhigC8AQAAAA==.Missed:BAAALgADCgUJBQABLgAFFAMJBQAFAEsMAA==.Misthios:BAABLgAECn8XAAInAAgJ3BSlGgAsAgAnAAgJ3BSlGgAsAgAAAA==.Mistkeg:BAAALgAECgYJEAAAAA==.Miteux:BAABLgAECn8UAAIZAAcJeRotBACtAQAZAAcJeRotBACtAQAAAA==.Mixxlepit:BAABLgAECn8aAAMnAAgJCAcJHwA+AQAnAAgJCAcJHwA+AQApAAEJpgMyIQAsAAAAAA==.',
Ml='Mlkchocolate:BAAALgADCgkJDwAAAA==.',
Mm='Mmhunt:BAAALgAECgMJAwAAAA==.',
Mo='Mogli:BAAALgADCgYJBgAAAA==.Molyporph:BAAALgAECgYJCQAAAA==.Momojojo:BAACLgAFFH8FAAMEAAMJfgfrDACNAAACAAMJrQF9agCeAAAEAAIJrwrrDACNAAAuAAQKfzIAAwQACAkUIbgBAHwCAAQACAkUIbgBAHwCAAIABQnOEoyFAPAAAAAA.Monre:BAABLgAECn8WAAIWAAgJqxNXSQDPAQAWAAgJqxNXSQDPAQAAAA==.Moobss:BAAALgADCgEJAQAAAA==.Moohlawn:BAAALgAECgQJBwABLgAECggJEgAKAAAAAA==.Moolock:BAAALgAECgUJBQAAAA==.Moonflame:BAABLgAECn8mAAMGAAgJHhgDKACvAQAGAAYJsBYDKACvAQAFAAgJmw5xIwBXAQAAAA==.Moonmajik:BAAALgADCgQJBgAAAA==.Mooriah:BAABLgAECn8eAAIVAAgJ+gLMRACiAAAVAAgJ+gLMRACiAAAAAA==.Moosty:BAAALgAECgIJAgAAAA==.Mordrakhuul:BAAALgAECgYJCAAAAA==.Morphtek:BAAALgAECgYJCgAAAA==.Morphyne:BAABLgAECn8mAAISAAkJbBo6PgAsAgASAAkJbBo6PgAsAgAAAA==.Moselii:BAAALgADCgEJAQABLgAECgMJBgAKAAAAAA==.Moserr:BAAALgAECgMJBgAAAA==.',
Mu='Muffin:BAAALgAECgYJEQAAAA==.',
My='Mycilya:BAAALgAECggJEgAAAA==.Mynchus:BAAALgAECggJEAAAAA==.Mysaria:BAAALgADCgUJBQAAAA==.Mysterymonk:BAABLgAECn8wAAIJAAgJUiXWAwAvAwAJAAgJUiXWAwAvAwAAAA==.Mysterypala:BAABLgAECn84AAILAAgJEyYdAgBgAwALAAgJEyYdAgBgAwAAAA==.Mysto:BAABLgAECn8iAAMiAAgJfhXVHADaAQAiAAgJfhXVHADaAQAWAAMJHQNjzABdAAAAAA==.Mystodin:BAABLgAECn8aAAISAAgJoRpUJwAdAgASAAgJoRpUJwAdAgAAAA==.',
['Mä']='Mälförmïtÿ:BAABLgAECn8dAAMGAAkJhRpwFgApAgAGAAgJghpwFgApAgAFAAgJWxVtFADaAQAAAA==.',
Na='Nacon:BAAALgAECgQJEwAAAA==.Naneko:BAABLgAECn8fAAIIAAkJNAzKXgCCAQAIAAkJNAzKXgCCAQAAAA==.Narrator:BAAALgAECgkJDQAAAA==.Nawwl:BAAALgADCgcJDgAAAA==.',
Ne='Neamheaglach:BAAALgADCgQJBAABLgAFFAEJAQAKAAAAAA==.Neelix:BAAALgADCgEJAQAAAA==.Neotahr:BAACLgAFFH8LAAIjAAMJVxLvEADcAAAjAAMJVxLvEADcAAAuAAQKfzUAAyMACQnmHyEDAGgCACMACQnmHyEDAGgCAAEAAwnOFxybAJwAAAAA.Neroiki:BAABLgAECn8UAAIMAAcJnA1IQQBDAQAMAAcJnA1IQQBDAQAAAA==.Neurôn:BAEALgAECgUJCAAAAA==.Nezra:BAABLgAECn8ZAAIhAAkJSRRzGgDEAQAhAAkJSRRzGgDEAQAAAA==.',
Ni='Nicckkcc:BAAALgADCgYJCwAAAA==.Nicotene:BAAALgAECgEJAQAAAA==.Nightquil:BAAALgADCgIJAgAAAA==.Nim:BAACLgAFFH8FAAIkAAMJRwekFQCfAAAkAAMJRwekFQCfAAAuAAQKfyUAAiQACQlgEeUMAM4BACQACQlgEeUMAM4BAAAA.Nitehunter:BAABLgAECn8hAAIBAAcJoA4LXgAvAQABAAcJoA4LXgAvAQAAAA==.',
No='Nomad:BAAALgAECgQJBQAAAA==.',
Nu='Nubshock:BAAALgAECgIJAgAAAA==.',
Ny='Nyatsua:BAAALgADCgEJAQAAAA==.',
['Nô']='Nôva:BAAALgADCgkJEAAAAA==.',
['Nö']='Növacaïn:BAAALgAECgIJAgAAAA==.',
Of='Offseason:BAAALgADCgcJDQAAAA==.',
Oi='Oistos:BAAALgADCgcJCwAAAA==.',
Om='Omid:BAAALgADCgYJCgAAAA==.',
On='Ondarklena:BAAALgADCgEJAQAAAA==.Onlydans:BAABLgAECn8ZAAIQAAkJOhnWCwAMAgAQAAkJOhnWCwAMAgAAAA==.',
Oo='Oomfie:BAAALgADCgkJDAAAAA==.',
Ou='Ouch:BAAALgAFFAIJAgAAAA==.',
Oy='Oyakev:BAAALgADCggJCgAAAA==.',
Pa='Pabiloneta:BAAALgAFFAIJAgAAAA==.Pacho:BAAALgADCgkJCQAAAA==.Painzir:BAABLgAECn8lAAITAAgJ5R9qKAAYAgATAAgJ5R9qKAAYAgAAAA==.Palamyne:BAAALgAECgEJAQAAAA==.Pallyana:BAABLgAECn8bAAISAAkJ+RxSFgB/AgASAAkJ+RxSFgB/AgAAAA==.Palosdin:BAAALgAECgMJAwAAAA==.Pandangerous:BAAALgAECgMJAwAAAA==.Parch:BAAALgADCgcJBwABLgAECggJIAAXACgkAA==.Parrandas:BAAALgAECgUJBQAAAA==.Parsleyposh:BAAALgADCgMJAgAAAA==.',
Pe='Peace:BAACLgAFFH8FAAIFAAMJgQiYGADdAAAFAAMJgQiYGADdAAAuAAQKfykAAgUACQlZG/kPAIYCAAUACQlZG/kPAIYCAAAA.Pepsweat:BAAALgADCgUJBQAAAA==.Perilc:BAAALgADCgQJBAAAAA==.Perimones:BAAALgAECgQJCAAAAA==.',
Ph='Phalandrel:BAABLgAECn8YAAIBAAkJiByuGQA/AgABAAkJiByuGQA/AgAAAA==.Phteve:BAAALgADCgUJBwAAAA==.',
Pi='Pigfeet:BAAALgADCgcJCwAAAA==.Pillows:BAAALgADCgYJCgAAAA==.Pinkponyclub:BAAALgAECgcJBwAAAA==.',
Pl='Plapper:BAAALgADCgMJAwABLgAECgYJDgAKAAAAAA==.',
Po='Ponytale:BAAALgADCgYJBgAAAA==.Popaheal:BAABLgAECn8iAAMGAAYJZR2tIQDWAQAGAAUJ7SGtIQDWAQAFAAUJTgp3RgCXAAAAAA==.Portali:BAAALgADCgkJFAAAAA==.Poundtown:BAAALgAECgEJAQAAAA==.',
Pr='Praystatiøn:BAAALgADCgcJBwAAAA==.Profitlord:BAAALgAFFAEJAQAAAA==.Proticus:BAAALgAECgMJAwAAAA==.',
Ps='Psychodad:BAAALgAECgEJAgAAAA==.Psyop:BAAALgAECgEJAgABLgAECggJDQAKAAAAAA==.',
Pu='Puppetpoker:BAAALgAECgEJAQAAAA==.Purplepain:BAAALgAFFAMJAwABLgAFFAQJDwAXAM0lAA==.Purplod:BAABLgAECn8YAAITAAkJtw9PhAB6AQATAAkJtw9PhAB6AQAAAA==.',
Py='Pyatpree:BAAALgAECgYJDwAAAA==.',
['Pä']='Päntera:BAABLgAECn89AAIOAAgJCh7pBwBmAgAOAAgJCh7pBwBmAgAAAA==.',
Qi='Qing:BAABLgAECn8cAAIPAAkJEhaZEgDgAQAPAAkJEhaZEgDgAQAAAA==.',
Qt='Qtrpounder:BAACLgAFFH8HAAIkAAMJ8iPbCQA1AQAkAAMJ8iPbCQA1AQAuAAQKfxUAAyQACQmdIvoKAPEBACQACQmdIvoKAPEBACAAAQl+AQ1cABQAAAAA.',
Qy='Qybxboogied:BAAALgAECgIJAwAAAA==.',
Ra='Raensong:BAAALgAECgEJAQAAAA==.Rafterman:BAAALgAECgEJAwAAAA==.Rahdric:BAAALgAECgYJDQAAAA==.Raisa:BAACLgAFFH8HAAICAAIJLA8WcACXAAACAAIJLA8WcACXAAAuAAQKfx4AAwIACQlqIakkAA8CAAIABglNIakkAA8CAAQABAnUHygcAGwBAAAA.Rakarum:BAABLgAECn8dAAIkAAYJxxXSGAAmAQAkAAYJxxXSGAAmAQAAAA==.Rasar:BAABLgAECn8dAAIIAAkJwh0dIwDmAgAIAAkJwh0dIwDmAgAAAA==.Rayleena:BAAALgAECgEJAQAAAA==.Rayo:BAAALgAECgQJBAAAAA==.',
Re='Reginald:BAAALgADCgcJDgAAAA==.Reigh:BAAALgADCgQJBAAAAA==.Rektington:BAABLgAECn8cAAITAAkJxx6OFwB3AgATAAkJxx6OFwB3AgAAAA==.Remiko:BAAALgAECggJEgAAAA==.Remmag:BAABLgAECn80AAIIAAgJpSRPFQCiAgAIAAgJpSRPFQCiAgAAAA==.Rett:BAAALgAECgEJAQABLgAECggJLQAgAIgiAA==.Revenger:BAAALgADCgQJBAAAAA==.Rexxy:BAAALgAECgYJDgAAAA==.',
Ri='Ribeye:BAAALgAECgUJBQAAAA==.Riott:BAAALgADCggJDwAAAA==.Rippednstiff:BAAALgADCgYJBgAAAA==.',
Ro='Roflmeister:BAABLgAECn8cAAIOAAYJkRUXEQCyAQAOAAYJkRUXEQCyAQAAAA==.Romoko:BAACLgAFFH8KAAIRAAQJTAf2GwDyAAARAAQJTAf2GwDyAAAuAAQKfyUAAhEACAmkFu8gAAgCABEACAmkFu8gAAgCAAAA.Rorshk:BAABLgAECn8cAAIaAAcJ0B4XBgArAgAaAAcJ0B4XBgArAgAAAA==.Royal:BAAALgAECgEJAQAAAA==.Roysham:BAABLgAECn8YAAIHAAYJjBavPACOAQAHAAYJjBavPACOAQAAAA==.Roywar:BAAALgAECgEJAwAAAA==.',
Ru='Rubianne:BAABLgAECn8sAAIMAAcJUAxWTAAWAQAMAAcJUAxWTAAWAQAAAA==.Rumrunner:BAABLgAECn8UAAInAAkJRBuJCABSAgAnAAkJRBuJCABSAgAAAA==.',
Ry='Rycicle:BAAALgADCgYJBQABLgAECgEJAQAKAAAAAA==.Rynhardt:BAAALgAECgEJAQAAAA==.Ryolith:BAAALgADCgMJAwAAAA==.',
['Rø']='Rønea:BAAALgAECgIJAgAAAA==.',
['Rý']='Rýfle:BAAALgADCgEJAQABLgAECgEJAQAKAAAAAA==.',
Sa='Sacrus:BAABLgAECn8aAAISAAYJSRangAAiAQASAAYJSRangAAiAQAAAA==.Santoss:BAAALgADCgYJGQAAAA==.Sarah:BAACLgAFFH8HAAIOAAIJoyPLFgDLAAAOAAIJoyPLFgDLAAAuAAQKfzUAAw4ACQkeIucDAMACAA4ACQnhIecDAMACACMAAQm4Ii93AGMAAAEuAAUUBAkMAAUAvRsA.',
Sc='Scottscrx:BAAALgADCgUJBQAAAA==.Scrotes:BAAALgAECgYJDQAAAA==.',
Se='Seer:BAABLgAECn8fAAIWAAkJ7B1SEgBvAgAWAAkJ7B1SEgBvAgAAAA==.Seilah:BAAALgAECgYJCwAAAA==.Selbi:BAABLgAECn8aAAIEAAgJyxTWBgCcAQAEAAgJyxTWBgCcAQAAAA==.Senjougahara:BAACLgAFFH8YAAIoAAYJkR7mAACzAQAoAAYJkR7mAACzAQAuAAQKfzYAAygABwnCJUYBAPcCACgABwnCJUYBAPcCABMAAQnCB/oqASsAAAAA.Seola:BAAALgAECgEJAwAAAA==.Serav:BAAALgADCgIJAgAAAA==.Seravonas:BAAALgADCgcJBwAAAA==.Seravonta:BAAALgAECgEJAgAAAA==.Serial:BAABLgAECn8pAAIRAAkJ/SGbBADlAgARAAkJ/SGbBADlAgAAAA==.Seriyah:BAACLgAFFH8RAAIaAAQJCxR5AwBeAQAaAAQJCxR5AwBeAQAuAAQKfxwAAhoABwlpHbIJAMgBABoABwlpHbIJAMgBAAAA.Serph:BAAALgAECgcJDgAAAA==.',
Sh='Shabane:BAABLgAECn8nAAIPAAgJwBVMFwCxAQAPAAgJwBVMFwCxAQAAAA==.Shaggyspaggy:BAAALgAECgUJBQAAAA==.Shambulañcé:BAABLgAECn8WAAIHAAYJ8wniVwDtAAAHAAYJ8wniVwDtAAAAAA==.Shanbubu:BAAALgAECgIJCAAAAA==.Shasta:BAAALgAECgkJAwAAAA==.Shekari:BAAALgAECgEJAQAAAA==.Shenanigins:BAAALgADCgUJBQAAAA==.Shiftey:BAAALgAECggJDgABLgAECggJJQATAOUfAA==.Shilera:BAAALgADCgYJDwAAAA==.Shiminy:BAAALgAECgkJDwAAAA==.Shinobi:BAABLgAECn8gAAIXAAkJiBnSCwA5AgAXAAkJiBnSCwA5AgAAAA==.Shiol:BAACLgAFFH8HAAMCAAMJxRgSMACzAAACAAIJ4xcSMACzAAAEAAEJihpJEgBaAAAuAAQKfxcAAwIACAlRHlYkAIICAAIABwkVHlYkAIICAAQABAlvHr0hAEcBAAAA.Shirls:BAABLgAECn8ZAAMSAAkJZBpvRwANAgASAAkJZBpvRwANAgALAAYJChRZWAAaAQAAAA==.Shivak:BAACLgAFFH8KAAIeAAMJZwhyLQDHAAAeAAMJZwhyLQDHAAAuAAQKfzYAAh4ACQnkGsEJAHsCAB4ACQnkGsEJAHsCAAAA.Shivanie:BAABLgAECn8WAAILAAYJjBGqLQBXAQALAAYJjBGqLQBXAQAAAA==.Shock:BAABLgAECn8hAAMRAAgJAh/mDgC4AgARAAgJAh/mDgC4AgAHAAEJ2RBjlwBBAAABLgAFFAMJBQAFAEsMAA==.Shocklesnar:BAAALgAECgUJCwAAAA==.Shocknorris:BAAALgAECgUJBQAAAA==.Shîftycent:BAABLgAECn8qAAQVAAgJvxUJGAC0AQAVAAgJvxUJGAC0AQAMAAcJbgkpYgArAQAaAAEJ0wDlOwAKAAAAAA==.',
Si='Siccem:BAABLgAECn8bAAIBAAgJaB1yFgBWAgABAAgJaB1yFgBWAgABLgAECggJKwAVAK0eAA==.Sicwiddit:BAAALgAECgUJCQAAAA==.Sienfonson:BAAALgADCgMJAwAAAA==.',
Sk='Skaffos:BAAALgADCgUJBQABLgADCgYJBgAKAAAAAA==.Skaffoz:BAAALgADCgEJAQABLgADCgYJBgAKAAAAAA==.Skafz:BAAALgADCgYJBgAAAA==.Skeeda:BAAALgAECgEJAQAAAA==.Skik:BAABLgAECn80AAIkAAgJdx+TBgBdAgAkAAgJdx+TBgBdAgAAAA==.Skylines:BAAALgAECgcJDgAAAA==.Skylinez:BAACLgAFFH8TAAIRAAUJUBKmFAAlAQARAAUJUBKmFAAlAQAuAAQKfxoAAhEACQnRHWUWAGcCABEACQnRHWUWAGcCAAAA.Skïttles:BAABLgAECn8hAAMMAAgJghdqMQDlAQAMAAgJghdqMQDlAQAVAAMJygtNUwBnAAAAAA==.',
Sl='Sleezball:BAAALgADCgEJAwAAAA==.Sloppyhog:BAAALgAECgkJEwAAAA==.Sloppyslice:BAAALgAECgEJAQABLgAECgMJBAAKAAAAAA==.Sloshman:BAAALgAECgEJAQAAAA==.',
Sm='Smobo:BAAALgAECgEJAQAAAA==.Smolder:BAAALgAECgUJCQABLgAECgkJFAAKAAAAAA==.',
Sn='Snoz:BAAALgAECgEJAQAAAA==.',
So='Sobek:BAAALgAECgcJCQAAAA==.Soeuphoric:BAAALgAECgcJBwAAAA==.Sohelem:BAAALgAECgEJAQAAAA==.Sonicfear:BAAALgAFFAEJAgAAAA==.Sonictide:BAABLgAECn8XAAIHAAgJFhqtFABSAgAHAAgJFhqtFABSAgAAAA==.Souahang:BAAALgAECgEJBQAAAA==.Souldrain:BAAALgAECgQJBAAAAA==.Soviette:BAAALgADCgkJDgAAAA==.',
Sp='Spaghetto:BAABLgAECn8uAAIVAAkJ2xkrCwBVAgAVAAkJ2xkrCwBVAgAAAA==.Sparx:BAAALgAECgEJAgAAAA==.Spicytacoo:BAAALgAECgUJBQAAAA==.Spookyscary:BAAALgAECgEJAQAAAA==.',
St='Stacy:BAAALgADCgMJAwAAAA==.Stankystank:BAABLgAECn8/AAMCAAYJMw4+fgAAAQACAAYJMw4+fgAAAQAEAAIJ1wgKMQAtAAAAAA==.Stepdag:BAACLgAFFH8LAAIPAAMJsgMFMACnAAAPAAMJsgMFMACnAAAuAAQKfzIAAg8ACQmNEAEWAL0BAA8ACQmNEAEWAL0BAAAA.Sthompson:BAAALgADCgYJCQAAAA==.Stinkydagger:BAAALgADCgIJAgAAAA==.Stormbolt:BAAALgAECgIJBAAAAA==.Stoutshrike:BAABLgAECn8UAAIJAAkJHxbVGQDsAQAJAAkJHxbVGQDsAQAAAA==.Strive:BAABLgAECn8oAAQhAAkJARETEwDxAQAhAAkJaQ8TEwDxAQAFAAYJDgpaNABHAQAGAAQJTxVlUwDpAAAAAA==.Stumpchuggns:BAAALgAECgEJAQAAAA==.',
Su='Suzel:BAAALgAECgEJAgAAAA==.',
Sw='Sweetfeed:BAAALgADCgcJCgAAAA==.',
Sy='Synder:BAABLgAECn8mAAIeAAgJ0wMQPgDdAAAeAAgJ0wMQPgDdAAAAAA==.',
Sz='Szmata:BAABLgAECn8nAAIcAAgJECNmAgCyAgAcAAgJECNmAgCyAgAAAA==.',
['Só']='Sóth:BAAALgADCgEJAQAAAA==.',
Ta='Tabata:BAABLgAECn8pAAIkAAkJtxUWCwDvAQAkAAkJtxUWCwDvAQAAAA==.Tahharruk:BAAALgAECgQJCwAAAA==.Tailwind:BAAALgADCgUJBAAAAA==.Talivandril:BAAALgAECgYJDgAAAA==.Talogos:BAAALgAECgMJBAAAAA==.Talvan:BAAALgADCgcJBwAAAA==.Tankowner:BAAALgADCgUJBQAAAA==.Tarkdoxicity:BAAALgADCgcJCgAAAA==.Tarynna:BAABLgAECn8pAAICAAgJWxPbOgCvAQACAAgJWxPbOgCvAQAAAA==.Taubhauhlau:BAAALgAECgEJAQAAAA==.Tawxx:BAAALgAECgUJBgAAAA==.',
Te='Teagen:BAABLgAECn8aAAIRAAcJ5RaBKABTAQARAAcJ5RaBKABTAQAAAA==.Teleprompter:BAABLgAECn8bAAIMAAYJlBTCTQAQAQAMAAYJlBTCTQAQAQAAAA==.Teleros:BAAALgADCgcJDQAAAA==.Telrissan:BAABLgAECn8VAAMIAAgJwQv7ZABzAQAIAAgJwQv7ZABzAQAlAAYJCwGODABeAAAAAA==.Tenyroldemon:BAABLgAECn8bAAINAAkJtBTmBgDHAQANAAkJtBTmBgDHAQAAAA==.Tenzingyatso:BAAALgAECgcJBgAAAA==.',
Th='Thald:BAABLgAECn8lAAIPAAkJQh94EACWAgAPAAkJQh94EACWAgAAAA==.Thepooper:BAACLgAFFH8LAAISAAMJahfrNwD/AAASAAMJahfrNwD/AAAuAAQKfyYAAhIACQkpIO4QAKUCABIACQkpIO4QAKUCAAAA.Thordun:BAAALgAECgEJAQABLgAECggJFQAkAMAOAA==.Thorin:BAAALgAECgIJAgAAAA==.Thunderball:BAABLgAECn8cAAIIAAgJ4xcOUQBEAgAIAAgJ4xcOUQBEAgAAAA==.',
Ti='Tinyaminals:BAAALgADCgYJBgAAAA==.Tisagosa:BAAALgADCgYJCAABLgAFFAMJCwAIAOIjAA==.Tisakna:BAACLgAFFH8LAAIIAAMJ4iNsPgA+AQAIAAMJ4iNsPgA+AQAuAAQKfzYAAwgACQkqJsUCAGIDAAgACQkaJsUCAGIDACUAAQnCJi0XAGEAAAAA.Tiskano:BAAALgADCgYJCwABLgAFFAMJCwAIAOIjAA==.Tissaia:BAAALgADCgcJDAABLgAFFAMJCwAIAOIjAA==.Tiszy:BAAALgADCgYJBgAAAA==.Titanx:BAAALgAECgkJDgAAAA==.',
To='To:BAAALgAECgYJBgAAAA==.Tomatoes:BAAALgAECgcJEgAAAA==.Toothy:BAAALgAECgUJCQAAAA==.Torahdanyse:BAAALgAECgMJAwAAAA==.Toughputa:BAAALgAECgEJAgAAAA==.',
Tr='Trask:BAABLgAECn8aAAIIAAkJ0huTXgAfAgAIAAkJ0huTXgAfAgAAAA==.Treefort:BAAALgADCgkJEAAAAA==.Trogdoor:BAAALgAECgEJAQAAAA==.Troko:BAAALgAECggJEAABLgAFFAUJEgAIAN4lAA==.Trokom:BAACLgAFFH8SAAIIAAUJ3iVRGQCfAQAIAAUJ3iVRGQCfAQAuAAQKfygAAggACQkFJUINAFsDAAgACQkFJUINAFsDAAEuAAUUBQkSAAgA3iUA.Trolladin:BAAALgAECgEJAQAAAA==.Trulyunruly:BAAALgAECgQJBAAAAA==.',
Tu='Tuakia:BAAALgADCgEJAQAAAA==.Tuggmytotem:BAABLgAECn8XAAIRAAkJmhzLDgAyAgARAAkJmhzLDgAyAgAAAA==.Turgho:BAAALgADCgMJAwAAAA==.',
Tw='Twi:BAAALgAECgcJCwAAAA==.',
Ty='Tygerfist:BAAALgAECgMJBwAAAA==.Tyrannar:BAAALgAECgcJBgAAAA==.Tytanion:BAAALgAECgMJBgAAAA==.Tython:BAAALgADCgcJBwAAAA==.',
Uc='Uch:BAAALgADCgQJBQAAAA==.',
Ul='Ultrarion:BAAALgAECgYJCgAAAA==.',
Un='Uncletrump:BAAALgAECgEJAQAAAA==.Undan:BAAALgAECgEJAQAAAA==.Undercovrcow:BAAALgAECgEJAgAAAA==.Unity:BAAALgADCgYJBgAAAA==.Unmade:BAACLgAFFH8LAAIFAAMJYhk5FQD9AAAFAAMJYhk5FQD9AAAuAAQKfy4AAgUACQk/HwoKAGUCAAUACQk/HwoKAGUCAAAA.Unstablë:BAAALgAECgUJBwAAAA==.',
Ur='Urbanmech:BAABLgAECn8UAAIXAAkJERzgEQBoAgAXAAkJERzgEQBoAgAAAA==.',
Us='Usedgoods:BAAALgAECgcJAQAAAA==.',
Va='Vanderbos:BAAALgADCgMJAwAAAA==.Vanderune:BAACLgAFFH8LAAIUAAMJ2A6OGQCyAAAUAAMJ2A6OGQCyAAAuAAQKfzUAAhQACQkDHf8GAGgCABQACQkDHf8GAGgCAAAA.Varastanna:BAAALgADCgYJCgAAAA==.',
Ve='Vecky:BAAALgADCgcJBwAAAA==.',
Vi='Victus:BAAALgAECgEJAQAAAA==.Vidrus:BAAALgAECgYJDgAAAA==.Vilkas:BAACLgAFFH8NAAIFAAUJ7RcsBwBUAQAFAAUJ7RcsBwBUAQAuAAQKfx8AAgUACAkKISQIAAIDAAUACAkKISQIAAIDAAAA.Viserion:BAABLgAECn8UAAIfAAYJpBG5IQBtAQAfAAYJpBG5IQBtAQAAAA==.Visionhorn:BAAALgADCgIJAwAAAA==.',
Vo='Voidlit:BAAALgAECgEJAQAAAA==.Voodoowhodo:BAABLgAECn8VAAIEAAgJygi3DgAHAQAEAAgJygi3DgAHAQAAAA==.',
Vu='Vuradra:BAAALgAECgMJAwAAAA==.Vuudrood:BAAALgADCgkJEQAAAA==.',
Wa='Waddledoo:BAAALgAECgMJBQAAAA==.Walruskíng:BAABLgAECn8hAAIFAAcJfB16EwDkAQAFAAcJfB16EwDkAQAAAA==.Wardaddy:BAAALgAECgYJEgAAAA==.Warkind:BAAALgAECgMJAwAAAA==.Warmage:BAAALgAECgIJAgAAAA==.Warmaku:BAABLgAECn8aAAMMAAgJSBwIEwBvAgAMAAgJSBwIEwBvAgAaAAEJ9QLcOQAhAAAAAA==.Warmohg:BAAALgAECgYJCgAAAA==.Wasred:BAAALgADCgkJCQAAAA==.',
We='Weezybaby:BAABLgAECn8jAAMcAAkJfg9hCwCVAQAcAAkJfg9hCwCVAQAHAAEJVQR2pQAqAAAAAA==.Wenjiesmom:BAAALgAECgEJAQAAAA==.',
Wh='Whitecosmos:BAAALgAECgMJBgABLgAFFAQJDwAXAM0lAA==.Whohe:BAAALgAECgEJAQAAAA==.',
Wi='Wigwog:BAABLgAECn8WAAIFAAcJXBt0FwC6AQAFAAcJXBt0FwC6AQAAAA==.Windfury:BAACLgAFFH8UAAIcAAUJACNPAQCPAQAcAAUJACNPAQCPAQAuAAQKfygAAhwACQmVJLABAEwDABwACQmVJLABAEwDAAAA.Windycrits:BAAALgADCgUJAQAAAA==.Winterfella:BAAALgADCgUJCwAAAA==.Wirantimer:BAAALgAECgYJDwAAAA==.Wishofwar:BAAALgADCgUJBQABLgAECggJIgASAEMcAA==.Witfuk:BAAALgADCgUJBQAAAA==.',
Wo='Wogasaurus:BAAALgAECggJDgAAAA==.Woobee:BAAALgAECgEJAQAAAA==.',
Wu='Wulrok:BAAALgADCgYJBgAAAA==.Wuzo:BAAALgAECgMJAwAAAA==.',
Wy='Wykka:BAABLgAECn8VAAIDAAkJghC0CQBYAQADAAkJghC0CQBYAQAAAA==.Wyverynn:BAABLgAECn8UAAITAAcJthROewCNAQATAAcJthROewCNAQAAAA==.',
['Wí']='Wínter:BAAALgADCgMJAwAAAA==.',
Xa='Xami:BAAALgADCgkJCQAAAA==.Xany:BAAALgAECgUJCwAAAA==.',
Xc='Xcomunicated:BAAALgADCgUJBQAAAA==.',
Xe='Xenomortis:BAAALgAECgcJDwAAAA==.Xephanie:BAAALgAECgEJBAAAAA==.',
Xi='Xinlucia:BAAALgAECgkJDwAAAA==.',
Xo='Xofu:BAAALgAECgEJBAAAAA==.Xoro:BAAALgAECgEJAQAAAA==.',
Xr='Xrxyz:BAACLgAFFH8PAAISAAUJhBlOHABQAQASAAUJhBlOHABQAQAuAAQKfyEAAhIACAnVHOcoAIECABIACAnVHOcoAIECAAAA.',
Xy='Xylus:BAAALgAECgIJAgAAAA==.',
Ya='Yabe:BAAALgAECgMJAwAAAA==.',
Ye='Yen:BAAALgADCgIJAgAAAA==.Yetibear:BAAALgAECgIJAgAAAA==.Yewna:BAAALgAECgYJDgAAAA==.',
Yy='Yyrella:BAAALgADCgIJAgABLgAECgcJFAATAHoTAA==.',
Za='Zachdem:BAAALgAECgQJBAAAAA==.Zachdrac:BAAALgADCgQJBAAAAA==.Zaemor:BAAALgAECgEJAQAAAA==.Zau:BAAALgADCgkJCQAAAA==.',
Ze='Zebrabutt:BAABLgAECn8sAAMRAAgJdxJEJQBnAQAcAAgJWQ4wEQCkAQARAAgJIhBEJQBnAQAAAA==.Zenstation:BAAALgADCgEJAQAAAA==.Zero:BAAALgAECgcJEgAAAA==.',
Zi='Ziccem:BAABLgAECn8rAAIVAAgJrR4BDQA4AgAVAAgJrR4BDQA4AgAAAA==.Ziggawâ:BAAALgAECgYJCQABLgAECggJKAAQAHsUAA==.Zildjìan:BAAALgAECgEJAQAAAA==.Zionsmender:BAAALgAECgYJDwAAAA==.',
Zo='Zolja:BAAALgAECgMJAwAAAA==.Zoney:BAAALgADCgIJAwAAAA==.Zordlon:BAAALgAECgMJBgAAAA==.',
Zu='Zukem:BAAALgAECgUJBQAAAA==.Zuli:BAAALgAECgYJBgABLgAFFAMJBwACAMUYAA==.Zuretull:BAAALgAECgYJCQAAAA==.',
Zy='Zynlord:BAAALgADCgEJAQAAAA==.Zyvea:BAAALgAECgYJDQAAAA==.',
['Çh']='Çharacter:BAAALgADCgYJBgAAAA==.',
['Çr']='Çrossblesser:BAAALgAECgQJEQAAAA==.',
['ßa']='ßamboo:BAAALgADCgYJBwABLgAECgYJGgASAEkWAA==.',
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
