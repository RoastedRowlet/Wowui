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

local lookup = {'Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Mage-Frost','Hunter-Survival','DeathKnight-Frost','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','Priest-Shadow','Paladin-Retribution','Hunter-Marksmanship','Paladin-Protection','DemonHunter-Devourer','DeathKnight-Blood','Priest-Holy','Paladin-Holy','Druid-Balance','Shaman-Restoration','Rogue-Subtlety','DemonHunter-Havoc','Rogue-Outlaw','Rogue-Assassination','Warlock-Demonology','Warrior-Arms','Priest-Discipline','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warrior-Fury','Druid-Feral','Shaman-Elemental','Druid-Restoration','Warlock-Affliction','Druid-Guardian','Shaman-Enhancement',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aaravos:BAABLgAECn8UAAIBAAgJLxM2CgCRAQABAAgJLxM2CgCRAQAAAA==.',
Ab='Abysseon:BAAALgAECgUJDgAAAA==.',
Ac='Accretion:BAAALgAECgYJBgAAAA==.',
Ad='Adaria:BAABLgAECn8WAAICAAcJWAWSZQA3AQACAAcJWAWSZQA3AQAAAA==.Adrillbear:BAAALgAECgIJAgABLgAECgYJEAADAAAAAA==.Adura:BAAALgADCgkJHAAAAA==.',
Ae='Aeirith:BAACLgAFFH8HAAIEAAMJSxfjAQDgAAAEAAMJSxfjAQDgAAAuAAQKfyQAAwQACQmwHbgBAGwCAAQACQmwHbgBAGwCAAUAAQlFCk1VATEAAAAA.Aelion:BAAALgAECgEJAQAAAA==.',
Ah='Ahheevoker:BAAALgAECgYJEgAAAA==.',
Ai='Ailsà:BAAALgADCgEJAQAAAA==.',
Al='Aladaria:BAAALgAECgMJAwAAAA==.Aldyah:BAAALgAECgcJCgAAAA==.Alias:BAAALgAECgYJBQAAAA==.Allanonn:BAAALgAECgQJBAAAAA==.Alohomora:BAAALgAECgUJEAAAAA==.Alvist:BAAALgAECgQJEAAAAA==.',
Am='Amarasu:BAABLgAECn8bAAIGAAkJig/LGQDMAQAGAAkJig/LGQDMAQAAAA==.Amarlly:BAABLgAECn8vAAIHAAgJkRjgBwAEAgAHAAgJkRjgBwAEAgAAAA==.Amenedil:BAAALgAECgUJDAAAAA==.',
An='Anbrew:BAABLgAECn8UAAQIAAcJdxKGRQA8AQAIAAYJDBKGRQA8AQAJAAUJjA5sPgD5AAAKAAEJMwfQpAAlAAABLgAFFAYJDwALAN0dAA==.Ancelina:BAABLgAECn8lAAIMAAgJSiQhBwDZAgAMAAgJSiQhBwDZAgAAAA==.Anderton:BAABLgAECn8xAAINAAgJShkMRwDmAQANAAgJShkMRwDmAQAAAA==.Andilocks:BAAALgADCgMJAwAAAA==.Aneira:BAAALgAECgUJEQAAAA==.Annovera:BAAALgAECgMJBgAAAA==.Anuubis:BAAALgADCgYJBgAAAA==.Anyi:BAAALgAECgEJAQAAAA==.',
Ap='Apexxd:BAAALgAECgEJAQAAAA==.Applefritter:BAAALgAECgUJCAABLgAECgkJKAAMAJYbAA==.',
Ar='Archérhiro:BAACLgAFFH8jAAMCAAgJkBU/BQA4AgACAAcJUhg/BQA4AgAOAAMJRwTfIQCHAAAuAAQKfygAAwIACQnrHnYYAIgCAAIACQnfHnYYAIgCAA4ACAkrGdobAEoCAAAA.Arilias:BAAALgAECgEJAQABLgAECgkJKwACAE0XAA==.Arillann:BAABLgAECn89AAIPAAkJUR9LBACwAgAPAAkJUR9LBACwAgAAAA==.Arrook:BAAALgADCgMJAwAAAA==.Arrtonomis:BAAALgAECgUJCAABLgAECgkJEQADAAAAAA==.Arte:BAABLgAECn89AAICAAkJaxOnLAABAgACAAkJaxOnLAABAgAAAA==.Arthundermis:BAAALgAECgkJEQAAAA==.Artlunarmis:BAAALgADCgEJAQABLgAECgkJEQADAAAAAA==.Arvena:BAABLgAECn8nAAIQAAkJVgrWbgA5AQAQAAkJVgrWbgA5AQAAAA==.',
As='Asclëpius:BAAALgADCgcJBgABLgAECgEJAQADAAAAAA==.Asheron:BAAALgAECgYJCAAAAA==.Ashylock:BAAALgAECgEJAQABLgAFFAUJDgAFAGAWAA==.Ashymage:BAACLgAFFH8OAAIFAAUJYBbFVQAyAQAFAAUJYBbFVQAyAQAuAAQKfzcAAgUACQlYHLYpAMwCAAUACQlYHLYpAMwCAAAA.Askevar:BAABLgAECn8gAAMLAAkJjQpTagCJAQALAAkJuQhTagCJAQARAAYJ5wlHJwAEAQAAAA==.Aspect:BAAALgADCgEJAQABLgAFFAIJAwADAAAAAA==.Asriél:BAAALgAECgQJBAAAAA==.Astor:BAAALgADCgEJAQAAAA==.Astrona:BAAALgADCgkJFwAAAA==.',
At='Atreus:BAABLgAECn8YAAINAAkJbAVUtgAKAQANAAkJbAVUtgAKAQAAAA==.Attalaguy:BAAALgAECgYJDgAAAA==.',
Au='Audra:BAAALgADCgUJBwAAAA==.',
Av='Avabeatrix:BAAALgADCgEJAQAAAA==.Avinthoro:BAAALgADCgIJAgAAAA==.',
Ay='Ayyayyron:BAAALgAECgUJCQAAAA==.',
Az='Azaleah:BAABLgAECn8/AAINAAkJtRpjIQB3AgANAAkJtRpjIQB3AgAAAA==.Azanoth:BAAALgADCgIJAgAAAA==.Azraesha:BAABLgAECn8rAAIQAAkJ/BXXJwAgAgAQAAkJ/BXXJwAgAgAAAA==.Azureflamez:BAAALgAECgEJAQAAAA==.Azzul:BAAALgADCgcJBwAAAA==.',
Ba='Baiken:BAAALgAECgIJAgABLgAECgQJCAADAAAAAA==.Banjoman:BAABLgAECn8kAAISAAcJXST1CQC7AgASAAcJXST1CQC7AgAAAA==.Baza:BAAALgADCgYJBgAAAA==.Baýlei:BAABLgAECn8WAAIIAAYJ5A2SUwAFAQAIAAYJ5A2SUwAFAQAAAA==.',
Be='Beary:BAAALgAECgQJCAAAAA==.Beenaughty:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Belaanna:BAAALgADCgYJCQAAAA==.Beliria:BAAALgADCgUJBgAAAA==.Benimaru:BAAALgAECgQJCgAAAA==.Beriko:BAAALgAECgMJAwAAAA==.Bernat:BAAALgAECgEJAQAAAA==.Beàrdfáce:BAAALgADCgQJBAAAAA==.',
Bi='Bigblunt:BAAALgADCgUJBQAAAA==.Bigjuicy:BAAALgAECggJCgAAAA==.Billie:BAAALgADCgcJBwAAAA==.Bimboficate:BAAALgADCgYJBwAAAA==.',
Bl='Black:BAAALgAECgQJBAAAAA==.Blackadder:BAABLgAECn8UAAIPAAUJPAscMACZAAAPAAUJPAscMACZAAAAAA==.Blessthefall:BAAALgAECgYJCgAAAA==.Blondie:BAAALgADCgQJBAABLgAECgYJEgADAAAAAA==.Bloodie:BAAALgAECgMJAwAAAA==.Blue:BAABLgAECn88AAIKAAkJxRvtDQBeAgAKAAkJxRvtDQBeAgAAAA==.Bluestreak:BAAALgAECgEJAwABLgAECgcJCQADAAAAAA==.',
Bo='Bode:BAAALgAECgYJEwAAAA==.Bogern:BAAALgADCgcJBwAAAA==.Bolau:BAAALgADCgYJBwAAAA==.Boltz:BAAALgADCgYJBgAAAA==.Boogy:BAAALgAECgYJBgAAAA==.Bopdiz:BAAALgAECgEJAQABLgAECgQJEAADAAAAAA==.Borledish:BAAALgAECgMJBAABLgAECgQJEAADAAAAAA==.Bottosai:BAAALgAECgEJAgAAAA==.',
Br='Branwynn:BAAALgAECgEJBgAAAA==.Breezyfight:BAAALgAECgYJCwAAAA==.Breezysha:BAAALgADCgcJCAAAAA==.Brenz:BAABLgAFFH8FAAMNAAMJOQLLpgBEAAANAAIJ9gDLpgBEAAAPAAEJvQQ2GQApAAAAAA==.Brewdaddy:BAAALgAECgUJEwABLgAECggJMgATAKwQAA==.Brewdude:BAAALgAECgEJAQAAAA==.Brigor:BAAALgAECgQJBAAAAA==.Brokenblade:BAAALgADCgYJBgAAAA==.Brotherblood:BAAALgAECgMJBgAAAA==.',
Bu='Bulldoza:BAAALgAECgQJBQAAAA==.Bullwinkles:BAAALgAECgEJAQAAAA==.Butterknifeo:BAABLgAFFH8FAAIUAAMJxxQWLQC8AAAUAAMJxxQWLQC8AAAAAA==.',
By='Byryja:BAABLgAECn8UAAIFAAUJJQVM+wCpAAAFAAUJJQVM+wCpAAAAAA==.',
Ca='Cahrazie:BAABLgAECn8WAAINAAkJxBLURgDnAQANAAkJxBLURgDnAQAAAA==.Caidinn:BAAALgAECgkJEQAAAA==.Caitrîn:BAAALgADCgkJCQABLgAECgUJEQADAAAAAA==.Calissancia:BAABLgAECn82AAIIAAgJNBekHAAfAgAIAAgJNBekHAAfAgAAAA==.Calkey:BAABLgAECn8WAAIBAAYJUQi3HAC3AAABAAYJUQi3HAC3AAAAAA==.Cathandris:BAAALgADCgEJAQAAAA==.',
Ce='Ceri:BAAALgAECgkJBwAAAA==.',
Ch='Chadarack:BAAALgAECgYJBwAAAA==.Chadaracks:BAAALgAECgEJAQAAAA==.Channingtotm:BAACLgAFFH8dAAIVAAUJLiWdCAAaAgAVAAUJLiWdCAAaAgAuAAQKfzUAAhUACQlhIfkDAHADABUACQlhIfkDAHADAAAA.Chantix:BAAALgADCgUJBQAAAA==.Charlemoo:BAAALgADCgUJBQABLgAECgMJAwADAAAAAA==.Cheekymonkey:BAABLgAECn8kAAIEAAkJIAsJBQCHAQAEAAkJIAsJBQCHAQAAAA==.Chrispbacon:BAAALgAECgUJCQAAAA==.Chueyé:BAAALgAECgMJAwABLgAFFAMJCQAWAO8dAA==.Chunkyy:BAAALgADCgYJBgAAAA==.Churros:BAABLgAECn8oAAMMAAkJlhtREABRAgAMAAkJlhtREABRAgASAAcJThVEJQCMAQAAAA==.',
Ci='Cincog:BAAALgAECgQJBAABLgAECgYJCQADAAAAAA==.',
Cl='Closetcookie:BAAALgAECgQJBAAAAA==.',
Co='Coberren:BAAALgAECgEJAQAAAA==.Cordialkylie:BAAALgAECgIJAgAAAA==.Cowcrusader:BAAALgADCgcJBwAAAA==.',
Cr='Crazyugly:BAAALgAECgMJAwAAAA==.Crogrer:BAAALgAECgMJAwAAAA==.Crosslock:BAAALgAECgQJCQAAAA==.',
Cu='Cuppycakes:BAAALgADCgcJFAAAAA==.',
Cy='Cynnari:BAAALgAECgUJBQAAAA==.',
Da='Dalan:BAAALgAECgIJAgABLgAFFAMJBwAEAEsXAA==.Dalaris:BAABLgAECn8hAAIXAAkJfhY+EQAGAgAXAAkJfhY+EQAGAgAAAA==.Dano:BAAALgADCgYJDQAAAA==.Darci:BAAALgAECgYJCwAAAA==.Darkeon:BAAALgAECgcJCwAAAA==.Darlenedark:BAAALgAECgEJAQAAAA==.Darling:BAAALgAECgIJAgAAAA==.Darron:BAAALgAECgEJAwABLgAECgcJCwADAAAAAA==.Darrosh:BAABLgAECn8bAAQYAAgJuxOzEQDiAAAYAAYJDhCzEQDiAAAWAAcJjQ2BOwDLAAAZAAMJ9hBGGgCEAAAAAA==.Dartian:BAAALgADCgYJBgABLgAECgkJKwACAE0XAA==.Dazdot:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.Dazsham:BAAALgAECgEJAQAAAA==.',
De='Deathdevil:BAAALgAECgUJBQAAAA==.Deathlurker:BAAALgADCgQJBAAAAA==.Deathmare:BAAALgAECgUJBQAAAA==.Deathmommy:BAAALgAECgcJCAAAAA==.Deathty:BAAALgAECgMJCgABLgAFFAEJAgADAAAAAA==.Dementia:BAAALgADCgMJAwAAAA==.Design:BAABLgAECn8lAAIaAAkJ4Rd1LQAdAgAaAAkJ4Rd1LQAdAgAAAA==.Desmeridian:BAAALgAECgUJBQAAAA==.Devotee:BAAALgADCgIJAgAAAA==.',
Dh='Dhish:BAAALgAECgUJCgAAAA==.',
Di='Diltlish:BAAALgAECgMJBQAAAA==.Diocles:BAAALgAECgEJAQAAAA==.Disconcern:BAAALgAECgEJAQAAAA==.Discontent:BAABLgAFFH8GAAIbAAIJUR3ULACQAAAbAAIJUR3ULACQAAAAAA==.Discordiä:BAABLgAECn8XAAIcAAgJHRdtGwDlAQAcAAgJHRdtGwDlAQAAAA==.Discspal:BAAALgAECgYJBwAAAA==.Diåblo:BAAALgADCgUJBQAAAA==.',
Dm='Dmginc:BAAALgADCgIJAgAAAA==.',
Do='Doeblin:BAAALgAECgQJDAAAAA==.Domidouse:BAAALgADCgYJBgAAAA==.Donkedixon:BAAALgADCgYJBgAAAA==.Doubtz:BAAALgAECgQJBQABLgAECgQJEAADAAAAAA==.',
Dp='Dpalx:BAAALgAECgQJBAAAAA==.Dpxs:BAABLgAFFH8HAAIVAAQJkhYPOADrAAAVAAQJkhYPOADrAAAAAA==.',
Dr='Dracaria:BAAALgAECgEJAQAAAA==.Dracones:BAAALgAECgYJDgAAAA==.Dragondz:BAAALgAECgUJBQAAAA==.Dragonflai:BAABLgAECn8mAAIFAAkJnBdpTADwAQAFAAkJnBdpTADwAQAAAA==.Dragonkin:BAAALgAECgQJCAAAAA==.Drakkari:BAAALgAECgYJDQAAAA==.Drakkei:BAABLgAECn87AAMCAAkJKRiYJgA6AgACAAkJKRiYJgA6AgAGAAMJIgZaRgCYAAAAAA==.Drerane:BAAALgADCgYJBgAAAA==.Drexxsster:BAAALgADCgQJBAAAAA==.Drshortbus:BAAALgAECgQJCAAAAA==.Drumitus:BAAALgADCgYJCAAAAA==.Drunkngrundl:BAABLgAECn89AAIJAAkJHiPGAwAJAwAJAAkJHiPGAwAJAwAAAA==.Drylo:BAECLgAFFH8JAAIdAAQJ6R4qGwBpAQAdAAQJ6R4qGwBpAQAuAAQKfy0AAx0ACQkmIP8IAMICAB0ACQmLHv8IAMICAB4ACAnFHykEADECAAAA.',
Du='Dunstir:BAABLgAECn8ZAAINAAgJ6QWxtAAMAQANAAgJ6QWxtAAMAQAAAA==.Dusktrekker:BAAALgAECgkJBwAAAA==.',
Dy='Dypshyt:BAABLgAECn8aAAQdAAkJhxcJSwD0AAAeAAUJUBJRIgAYAQAdAAYJqxAJSwD0AAAfAAUJTgchLAB8AAAAAA==.',
Ed='Edelweíss:BAAALgAECgQJCQAAAA==.',
Ek='Ekoh:BAAALgAECgIJAgAAAA==.',
El='Elarol:BAAALgAECgEJAgAAAA==.Eldons:BAAALgADCgIJAgAAAA==.',
Em='Embers:BAABLgAECn8WAAIgAAYJGxO5VADvAAAgAAYJGxO5VADvAAAAAA==.Emeralde:BAAALgAECgYJCgAAAA==.Emilia:BAAALgADCgIJAwAAAA==.Emptyhands:BAAALgAECgYJBgAAAA==.Emptyheals:BAABLgAECn8xAAIcAAkJ3yBWBABIAwAcAAkJ3yBWBABIAwAAAA==.',
Er='Ereada:BAAALgADCgUJCgAAAA==.Erfinden:BAAALgADCgEJAQAAAA==.',
Es='Espers:BAABLgAECn8fAAIUAAkJ6Q+0OgAYAQAUAAkJ6Q+0OgAYAQAAAA==.',
Et='Ethellin:BAABLgAECn8xAAINAAkJgAWEngAuAQANAAkJgAWEngAuAQAAAA==.',
Fa='Fahrenheit:BAAALgAECgEJAgAAAA==.Farkuat:BAAALgADCgQJBAAAAA==.Fatcastle:BAAALgADCgcJDgAAAA==.',
Fe='Feedmepizzas:BAAALgAECgMJCAAAAA==.Feildmedic:BAAALgAECgEJAQAAAA==.Feleria:BAAALgAECgUJCAAAAA==.Fellslasher:BAAALgAECgIJAgAAAA==.Felmage:BAAALgADCgYJBgAAAA==.Felraiser:BAAALgADCgIJAgABLgADCgUJBgADAAAAAA==.Felwinter:BAABLgAECn81AAIaAAkJthrGHwBgAgAaAAkJthrGHwBgAgAAAA==.Femcelgoon:BAAALgADCgEJAQAAAA==.Fenna:BAAALgADCgYJDAAAAA==.Fetor:BAAALgAECgcJEAAAAA==.',
Fi='Finwé:BAAALgAECgQJCQAAAA==.Fistsalot:BAAALgAECgQJCAAAAA==.',
Fl='Flafferthorn:BAAALgADCgcJCgAAAA==.Fluxarata:BAABLgAECn8pAAIQAAkJfQyXVAB9AQAQAAkJfQyXVAB9AQAAAA==.',
Fo='Forthememes:BAAALgAECgcJCQAAAA==.',
Fr='Fred:BAABLgAECn8rAAIgAAgJhQqNOQBYAQAgAAgJhQqNOQBYAQAAAA==.Freddrick:BAAALgADCgQJBAAAAA==.Friendly:BAAALgAECgEJAQAAAA==.Frostbuddy:BAAALgAECgcJDQAAAA==.Frëya:BAAALgADCgYJDQAAAA==.Frío:BAAALgAECgEJAQAAAA==.Frøstitute:BAABLgAECn8gAAIFAAkJiBGqSwDyAQAFAAkJiBGqSwDyAQAAAA==.',
Fu='Fullmage:BAAALgADCgQJBAAAAA==.',
['Fè']='Fènrïr:BAAALgADCgQJBAAAAA==.',
Ga='Gabel:BAABLgAECn8mAAIhAAkJQh04BgB2AgAhAAkJQh04BgB2AgAAAA==.Gadnabit:BAAALgADCgkJCQAAAA==.Gailardia:BAABLgAECn8eAAICAAcJShv8NAD9AQACAAcJShv8NAD9AQABLgAFFAMJDwASAEkZAA==.Galand:BAABLgAECn8iAAMLAAYJ+h5HawCGAQALAAYJdB5HawCGAQARAAIJoiFOTABUAAAAAA==.Galladin:BAAALgADCggJDgAAAA==.Gardyson:BAAALgAFFAEJAQAAAA==.Gazton:BAAALgAECgUJBQAAAA==.',
Gl='Glaaki:BAAALgAECgQJBwAAAA==.',
Gn='Gnob:BAAALgAECgMJBAAAAA==.',
Go='Gooblet:BAAALgADCgQJBQAAAA==.Goodfellow:BAAALgAECgEJAQABLgAECgYJFQAhAMUcAA==.Goopy:BAAALgADCgYJAwAAAA==.',
Gr='Graendal:BAAALgADCgQJBAAAAA==.Granite:BAAALgAECgMJBAAAAA==.Granted:BAAALgADCgUJBQAAAA==.Greevil:BAAALgAECgEJAwAAAA==.Gremilien:BAABLgAECn8mAAIOAAkJSBKACQDRAQAOAAkJSBKACQDRAQAAAA==.Grimgorr:BAAALgADCgMJAwAAAA==.Grimmly:BAAALgAECgEJAQAAAA==.Grymdevours:BAAALgADCgYJBgAAAA==.',
Ha='Halcyonic:BAAALgAECgUJCQAAAA==.Halleyscomet:BAABLgAECn8WAAINAAcJPBptRAAXAgANAAcJPBptRAAXAgAAAA==.Happyhammer:BAAALgADCgcJCAAAAA==.Harrod:BAAALgAECggJCwAAAA==.Hawkwave:BAAALgAECgcJEgABLgAECgkJEQADAAAAAA==.Hazardzone:BAAALgAECgMJCgAAAA==.',
He='Heavyweather:BAAALgADCgcJBwAAAA==.Hefty:BAABLgAECn8WAAMGAAkJ3Qs8JwBgAQAGAAcJKQs8JwBgAQACAAUJ8glxmQD/AAAAAA==.Heftyer:BAAALgAECgMJAwAAAA==.Helioween:BAAALgADCgMJAwAAAA==.Helixon:BAAALgADCgYJBgAAAA==.Hellbad:BAACLgAFFH8MAAIJAAQJ7hNcJQAJAQAJAAQJ7hNcJQAJAQAuAAQKfxUAAwkACAleGCsmAHUBAAoABgmOG30jALoBAAkACAkXEismAHUBAAAA.Hellbine:BAAALgADCgMJAgAAAA==.Hellsspawn:BAAALgAECgYJCAAAAA==.Hexaverse:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.',
Ho='Hoardwither:BAAALgAECgEJAgAAAA==.Hoenheim:BAAALgAECgEJAQAAAA==.Hogrog:BAAALgADCgMJAwAAAA==.Hokàge:BAACLgAFFH8JAAIWAAMJ7x0WIQAEAQAWAAMJ7x0WIQAEAQAuAAQKfzkABBYACQkpIg0IAJsCABYACQkpIg0IAJsCABkAAgkCGsMZAIwAABgAAQkZAvQoAAkAAAAA.Holyballs:BAAALgAECgIJAgAAAA==.Homealone:BAABLgAECn8WAAMVAAYJvQk/hwC8AAAVAAUJ6AY/hwC8AAAiAAUJ8gNAdgB4AAAAAA==.',
Hu='Huffles:BAAALgAECgQJBwAAAA==.Hugmachine:BAAALgAFFAIJAgAAAA==.Huntinfuzzy:BAAALgAECgkJDwAAAA==.Huntn:BAAALgADCggJCAAAAA==.',
Hy='Hypahypa:BAAALgAECggJCAAAAA==.',
Ia='Iamknot:BAAALgAECgQJBgAAAA==.',
Ic='Icemommy:BAAALgADCgQJCAAAAA==.',
Ig='Igothots:BAACLgAFFH8FAAIjAAIJZBDpTgB5AAAjAAIJZBDpTgB5AAAuAAQKfx4AAyMACQl/HgIQALgCACMACQl/HgIQALgCACEAAQltCVJQACkAAAAA.',
Il='Illariana:BAABLgAECn8aAAQMAAgJNRIYKgB5AQAMAAgJNRIYKgB5AQASAAEJwQIddAAgAAAcAAEJvgFogAAeAAAAAA==.Illirotica:BAAALgAECgcJCQAAAA==.',
In='Incredibro:BAAALgADCgEJAQAAAA==.Insanitty:BAAALgAECgcJDwAAAA==.Invincible:BAAALgAECgEJAQABLgAECgYJFgAIAMkiAA==.',
Ir='Ironlobo:BAAALgAECgYJEgAAAA==.Ironsolari:BAAALgADCgYJBgAAAA==.Irritable:BAABLgAECn8fAAIkAAYJEiD3CADGAQAkAAYJEiD3CADGAQAAAA==.',
It='Itherious:BAAALgAECgQJCQAAAA==.',
Ja='Jacham:BAABLgAECn8WAAIgAAkJ2hSzHQD6AQAgAAkJ2hSzHQD6AQAAAA==.Jackyll:BAAALgAECgQJCAAAAA==.Jagerboy:BAAALgAECgYJBgAAAA==.Jango:BAAALgAECgIJAgABLgAFFAEJAQADAAAAAA==.Jatix:BAACLgAFFH8NAAINAAQJjx4KIwBnAQANAAQJjx4KIwBnAQAuAAQKfyoAAg0ACQkcI5UNAPACAA0ACQkcI5UNAPACAAAA.',
Je='Jeetkundo:BAAALgADCgEJAQABLgAECgYJFgAIAMkiAA==.Jellymagus:BAAALgAECgIJAgAAAA==.Jellyms:BAAALgAECgYJDAAAAA==.Jellyspinoff:BAAALgAECgMJBwAAAA==.Jellytown:BAABLgAECn89AAIFAAkJaxTCQQAQAgAFAAkJaxTCQQAQAgAAAA==.Jelorinea:BAAALgAECgMJAwAAAA==.Jessiana:BAAALgAECgQJCAAAAA==.Jezelda:BAAALgAECgQJBgAAAA==.',
Jp='Jpeppers:BAAALgAECgUJDQAAAA==.',
Ju='Jumano:BAAALgAECgUJCgAAAA==.Jundra:BAAALgAECgUJCgAAAA==.Jurih:BAAALgADCgIJAgAAAA==.',
Ka='Kaineh:BAABLgAECn8oAAIOAAgJah1eBQBDAgAOAAgJah1eBQBDAgAAAA==.Kainë:BAAALgADCgIJAgAAAA==.Kait:BAABLgAECn8+AAICAAkJ6R8pDwDOAgACAAkJ6R8pDwDOAgAAAA==.Kaladil:BAAALgAECgcJDgAAAA==.Kamis:BAAALgAECgMJAwAAAA==.Kanaga:BAAALgAECgQJBQAAAA==.Kannan:BAABLgAECn8YAAMQAAgJzxv/LwA8AgAQAAgJzxv/LwA8AgAXAAEJAQdWeQAqAAAAAA==.Kashmihhr:BAAALgADCgIJAgAAAA==.Kashmir:BAAALgAECgQJBAAAAA==.Kasmes:BAAALgADCggJGQAAAA==.Kasmius:BAAALgAECgMJAwAAAA==.Kasmus:BAAALgAECgQJCAAAAA==.Kawdor:BAABLgAECn8yAAQTAAgJrBDvOwBMAQATAAcJNw/vOwBMAQAPAAcJSA9rHwAMAQANAAMJ8wqCLwFtAAAAAA==.',
Ke='Keetsz:BAAALgAECgYJDAAAAA==.Kelaino:BAAALgADCgQJBQAAAA==.Keledish:BAAALgADCgEJAQAAAA==.',
Kh='Khansmebduke:BAACLgAFFH8FAAMXAAQJNxbVFQDZAAAXAAMJkRnVFQDZAAAQAAEJKgzUkQA9AAAuAAQKfxYAAxcACAmlHJcUANsBABAACAk1F1w+APsBABcABwlXHZcUANsBAAEuAAUUBQkJACEAjh4A.',
Ki='Kiaf:BAAALgADCgcJDQAAAA==.Kiba:BAAALgADCgEJAQAAAA==.Killanick:BAAALgAECgEJAQAAAA==.Killdar:BAAALgAECgQJBAAAAA==.Kimia:BAAALgADCgYJCQAAAA==.Kirtthedirt:BAAALgAECgUJBgAAAA==.Kirtthehurt:BAABLgAECn8pAAIFAAkJShh1LQBdAgAFAAkJShh1LQBdAgAAAA==.',
Ko='Koldfront:BAAALgAECgQJBwAAAA==.Kollinator:BAAALgAECgYJCgAAAA==.Korso:BAAALgADCgUJCwABLgAECgUJEQADAAAAAA==.Kotal:BAAALgAECgEJAQAAAA==.',
Ky='Kylair:BAABLgAECn80AAIMAAkJ/B5gCQC0AgAMAAkJ/B5gCQC0AgAAAA==.Kynreessa:BAAALgADCgYJCAAAAA==.Kyønshi:BAAALgADCgUJBgAAAA==.',
['Kì']='Kìrito:BAAALgAECgYJDQAAAA==.',
La='Labeya:BAAALgADCgMJAwAAAA==.Lafty:BAAALgAFFAEJAgAAAA==.Laftydh:BAAALgAECgYJEgABLgAFFAEJAgADAAAAAA==.Lailah:BAAALgADCgIJAgABLgAECgkJPwANALUaAA==.Laine:BAAALgADCgMJAwAAAA==.Landrra:BAAALgAECgQJBAAAAA==.Larac:BAAALgAECggJEgAAAA==.Lathsong:BAAALgADCgYJDwAAAA==.Lavi:BAAALgADCgQJAwAAAA==.',
Le='Leadge:BAAALgADCgYJBwAAAA==.Lenik:BAABLgAECn8aAAIWAAYJ+gn1NADyAAAWAAYJ+gn1NADyAAAAAA==.Leskya:BAAALgADCgQJAwAAAA==.',
Li='Libras:BAAALgADCgMJAwAAAA==.Licorice:BAAALgAECgUJDgABLgAECgkJKAAMAJYbAA==.Lieree:BAABLgAECn8XAAIFAAgJUg0xewB7AQAFAAgJUg0xewB7AQAAAA==.Lifeguàrd:BAAALgAECgkJBwAAAA==.Lillana:BAAALgADCgcJDQAAAA==.Lilyfaye:BAAALgADCgkJDAAAAA==.Limosfire:BAABLgAECn8VAAIOAAYJkAOZIgCQAAAOAAYJkAOZIgCQAAAAAA==.Linsatha:BAAALgAECggJEAAAAA==.',
Lo='Lockty:BAAALgAECgIJBgABLgAFFAEJAgADAAAAAA==.Logi:BAAALgADCgYJCwAAAA==.Lorezever:BAAALgADCgcJDQAAAA==.Lotion:BAAALgADCgIJAgAAAA==.',
Lu='Luar:BAAALgAECgYJDQAAAA==.Lulubean:BAAALgADCgMJBAAAAA==.Lunaris:BAAALgADCgQJBAAAAA==.Lungorthin:BAAALgAECgMJAwAAAA==.Lunà:BAABLgAECn8aAAIBAAcJwwMFIQCaAAABAAcJwwMFIQCaAAAAAA==.',
Ly='Lythalle:BAAALgAECgEJAQAAAA==.Lythwynn:BAABLgAECn8rAAINAAkJhQ8HbACLAQANAAkJhQ8HbACLAQAAAA==.',
['Lá']='Lásh:BAAALgAECgUJCAABLgAECgUJEQADAAAAAA==.',
Ma='Mace:BAAALgAECgEJAQAAAA==.Madison:BAAALgAECgEJAQAAAA==.Magdolyn:BAAALgADCgMJAwAAAA==.Mageyboi:BAAALgAECgQJBgABLgAFFAMJCQAWAO8dAA==.Magickul:BAAALgAECgYJDAAAAA==.Magleon:BAAALgADCgIJAgAAAA==.Magonk:BAAALgADCgEJAQAAAA==.Mahano:BAAALgAECgYJDgABLgAFFAEJAQADAAAAAA==.Makis:BAAALgAECgMJBQAAAA==.Malachi:BAAALgADCgkJCQAAAA==.Manavoid:BAABLgAECn8cAAIQAAYJkAoAoADVAAAQAAYJkAoAoADVAAAAAA==.Mandragore:BAAALgAECgIJBAAAAA==.Massili:BAAALgADCgkJGgAAAA==.Mastor:BAAALgADCgQJBwAAAA==.Maynard:BAABLgAECn8hAAIIAAkJ9xE0KwC+AQAIAAkJ9xE0KwC+AQAAAA==.',
Mc='Mcdouble:BAAALgADCgMJAwAAAA==.',
Me='Meri:BAABLgAECn8cAAIjAAgJlxwrJgAfAgAjAAgJlxwrJgAfAgAAAA==.',
Mi='Miande:BAABLgAECn8VAAIkAAcJ0xe+CQC1AQAkAAcJ0xe+CQC1AQAAAA==.Microburst:BAAALgADCgcJCwAAAA==.Minecraft:BAAALgAECgIJAgAAAA==.Minilock:BAABLgAECn8sAAMaAAkJeQ7TSwCyAQAaAAkJUA3TSwCyAQABAAUJTg6zHAC3AAAAAA==.Misogynixy:BAAALgADCgQJBAAAAA==.Missdeeds:BAAALgADCgYJEAAAAA==.Missleading:BAAALgAECgYJCQAAAA==.Missused:BAAALgAECgYJEQAAAA==.Mithos:BAAALgAECgUJBwAAAA==.Mithraxa:BAAALgAECgQJBAAAAA==.Miyagifu:BAAALgADCgQJBAAAAA==.',
Mo='Moash:BAAALgADCgkJCQAAAA==.Modsagoodtnk:BAAALgAECgYJCwABLgAECggJKQACAIMZAA==.Mongermook:BAABLgAECn8eAAMlAAkJ+Qn1KgDzAAAlAAkJ+Qn1KgDzAAAUAAEJxgFpkQAVAAAAAA==.Monnkysham:BAAALgAECgQJBgABLgAECgYJCQADAAAAAA==.Moogledragon:BAAALgADCgMJAwAAAA==.Mooglefur:BAAALgAECgQJBQAAAA==.Moonbloom:BAABLgAECn8cAAIjAAgJQhwPHgBMAgAjAAgJQhwPHgBMAgAAAA==.Morlosh:BAAALgAECgMJAwAAAA==.Moryna:BAABLgAECn8rAAIbAAgJsAbJMAD6AAAbAAgJsAbJMAD6AAAAAA==.',
Mt='Mthrandir:BAAALgADCgUJBQAAAA==.',
Mu='Muford:BAAALgAECgQJBQABLgAFFAcJFAAJAFMfAA==.Mull:BAAALgAECgYJEgAAAA==.Muloc:BAAALgADCgEJAQAAAA==.',
My='Myaka:BAAALgAECgYJBgAAAA==.Mythicc:BAAALgADCgQJBAAAAA==.',
Na='Naatixa:BAAALgAECggJDAAAAA==.Nacronor:BAAALgAECgQJCQAAAA==.Naiika:BAAALgAECgYJBwAAAA==.Nascha:BAAALgADCgEJAQAAAA==.Nasoj:BAAALgAECgUJCAABLgAECgYJEwADAAAAAA==.',
Ne='Necrotic:BAAALgAECgQJBAAAAA==.Nedalla:BAAALgAECgYJCwAAAA==.Neeve:BAAALgAECgEJAQAAAA==.Nekrotik:BAAALgADCgcJBgAAAA==.Neobahamut:BAAALgADCgEJAQABLgAECgYJDQADAAAAAA==.Netharel:BAAALgADCgIJAgAAAA==.Newports:BAAALgAECgEJAQAAAA==.',
Ni='Nichôlasmage:BAAALgAECgYJCwAAAA==.Nickatnite:BAAALgAFFAEJAQAAAA==.Nickelodeon:BAAALgAFFAEJAQAAAA==.Nicksaban:BAABLgAECn8mAAINAAkJOBsdKwBKAgANAAkJOBsdKwBKAgAAAA==.Nightgear:BAACLgAFFH8wAAMCAAgJaBeNCQD7AQACAAcJehmNCQD7AQAOAAIJ/ArRLwBJAAAuAAQKf1kAAwIACQm1IgUIABADAAIACQm1IgUIABADAA4ABAnfEj0hAJoAAAAA.Nightshades:BAAALgADCgQJBAAAAA==.Nilux:BAAALgAECgYJDgAAAA==.Ninetails:BAAALgAECgUJCgAAAA==.Niteshadeth:BAAALgAECgQJBAAAAA==.Niteyknight:BAAALgAECgQJBAAAAA==.Nixeava:BAABLgAECn8ZAAIiAAYJCQWzYwCqAAAiAAYJCQWzYwCqAAAAAA==.',
No='Nogooddruid:BAAALgAECgQJBwAAAA==.Nopetsneeded:BAABLgAECn89AAIOAAkJzBSgBwD/AQAOAAkJzBSgBwD/AQAAAA==.Nostariel:BAAALgAECgMJBgAAAA==.Notadoctor:BAAALgAECgYJCAAAAA==.Noteworthy:BAAALgAECgYJEgABLgAFFAYJDwALAN0dAA==.',
Ny='Nysong:BAABLgAECn8vAAMBAAgJDgkLFAACAQABAAgJDgkLFAACAQAaAAMJYwLICgFTAAAAAA==.',
['Nó']='Nórin:BAAALgAECgUJBQAAAA==.',
Od='Oddangel:BAAALgAECgYJEwAAAA==.Ode:BAAALgAECgcJCgAAAA==.Odex:BAABLgAECn8mAAMeAAkJNQ0ZCACnAQAeAAkJNQ0ZCACnAQAdAAEJpggsiAA6AAAAAA==.',
Oh='Ohblergen:BAAALgAECgIJAgAAAA==.',
Ok='Okragren:BAABLgAECn81AAIiAAkJhwxxMABvAQAiAAkJhwxxMABvAQAAAA==.',
Ol='Olehi:BAAALgADCgcJBwAAAA==.Olynder:BAAALgAECgIJBAAAAA==.',
On='Onos:BAABLgAECn8bAAICAAcJIyQ4IABEAgACAAcJIyQ4IABEAgAAAA==.Onto:BAAALgADCgEJAQAAAA==.Ontoquas:BAAALgADCgkJCgAAAA==.',
Or='Orinin:BAAALgADCgkJCQABLgAECgQJCAADAAAAAA==.',
Pa='Paleclaw:BAAALgADCgQJBAAAAA==.Pally:BAAALgAECgUJBQAAAA==.Papasmurfz:BAAALgAECgEJAwAAAA==.Paramedic:BAAALgAECgQJBwAAAA==.Pathogen:BAABLgAECn8hAAILAAkJDR/nNgAbAgALAAkJDR/nNgAbAgAAAA==.',
Pe='Penryn:BAAALgAECgQJBAAAAA==.Pepster:BAABLgAECn8XAAImAAkJpQErKwCBAAAmAAkJpQErKwCBAAAAAA==.Persephoknee:BAAALgADCgEJAQAAAA==.',
Pf='Pfchen:BAAALgAECgEJAQAAAA==.',
Pl='Plinkerbell:BAAALgADCgcJBgAAAA==.Plumprnickel:BAAALgAECgEJAQAAAA==.Plxkingg:BAAALgADCgUJBQAAAA==.',
Po='Porimma:BAAALgAECgYJDgAAAA==.Pormas:BAAALgAECgYJDwAAAA==.Poseydon:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.',
Pr='Prayerz:BAAALgADCgMJAwAAAA==.Proctology:BAAALgAECgQJBAAAAA==.Prom:BAAALgAECgMJAwAAAA==.Promethèus:BAAALgAECgQJBAAAAA==.Prosby:BAAALgADCgIJAgAAAA==.Prowlnfool:BAAALgADCgUJBQAAAA==.Pryto:BAAALgADCgkJDgABLgAFFAIJAwADAAAAAA==.',
Qu='Queedle:BAABLgAECn8cAAIYAAkJWAmSCgBsAQAYAAkJWAmSCgBsAQAAAA==.',
Ra='Raennis:BAAALgAECgIJAgAAAA==.Ragalstan:BAAALgAECgEJAQAAAA==.Rahanumn:BAABLgAECn8YAAINAAgJ6wmsmQA2AQANAAgJ6wmsmQA2AQAAAA==.Rainlette:BAAALgAECgYJBgAAAA==.Rainsvoker:BAACLgAFFH8jAAIfAAYJXQ2lEAByAQAfAAYJXQ2lEAByAQAuAAQKf1IAAx8ACQkOHHYGAJYCAB8ACQkOHHYGAJYCAB0ABgk7CLpYAMQAAAAA.Ramike:BAAALgAECggJCQAAAA==.Raqtar:BAAALgAECgIJAgABLgAECgkJEQADAAAAAA==.Ratrazarke:BAAALgADCgIJAgAAAA==.Razihel:BAAALgADCgYJCQAAAA==.',
Re='Reaver:BAAALgAECgQJBAAAAA==.Reddan:BAABLgAECn8qAAINAAgJlgzpkQBDAQANAAgJlgzpkQBDAQAAAA==.Renata:BAAALgAFFAIJAgAAAA==.Replicant:BAAALgAECgEJAQAAAA==.Retman:BAAALgAECgMJAQAAAA==.Reverìe:BAAALgAECgcJBwAAAA==.Reylinn:BAAALgAECgQJBAAAAA==.Reyra:BAAALgAECgEJAQAAAA==.Reï:BAABLgAECn8dAAIjAAkJUBQqIwAnAgAjAAkJUBQqIwAnAgAAAA==.',
Ri='Ridlei:BAAALgAECgMJBAAAAA==.Rimchester:BAAALgAECgIJAQAAAA==.Ritzon:BAABLgAECn89AAMgAAkJJSSLBQAAAwAgAAkJJSSLBQAAAwAbAAEJmBdNaQA+AAAAAA==.',
Ro='Rosadita:BAAALgAECgQJAwAAAA==.Roxydan:BAABLgAECn8dAAMBAAgJiQ03KQAdAQAaAAgJiQ1KZwCWAQABAAYJ8Ag3KQAdAQAAAA==.',
Ry='Ryko:BAABLgAECn8eAAImAAcJDRPFDwC8AQAmAAcJDRPFDwC8AQAAAA==.',
Sa='Sanandume:BAAALgADCgEJAQAAAA==.Sanctess:BAAALgAECggJDQAAAA==.Sankai:BAAALgAECgEJAQABLgAECgYJDgADAAAAAA==.Sarlas:BAAALgADCgQJBAAAAA==.Sarumanpally:BAAALgAECgYJBwAAAA==.Sayomi:BAAALgADCgcJEwAAAA==.',
Se='Secretjuice:BAAALgAECgYJCQAAAA==.Senseijundra:BAAALgAECgQJCAAAAA==.',
Sh='Shabadu:BAAALgADCgQJBAAAAA==.Shadyandi:BAAALgADCgcJCAAAAA==.Shamanhack:BAAALgAFFAIJAwAAAA==.Shan:BAAALgADCgYJBgAAAA==.Sharazad:BAAALgAECgEJAgAAAA==.Sheda:BAAALgAECgQJBAAAAA==.Shedia:BAAALgADCgYJCQAAAA==.Shmoove:BAEALgAECgUJBgAAAA==.Shmooves:BAEALgAECgQJBAABLgAECgUJBgADAAAAAA==.Shoukei:BAAALgADCgIJAwAAAA==.',
Si='Sianna:BAAALgADCgYJBgAAAA==.Siinful:BAAALgAECgEJAQAAAA==.Simbruh:BAAALgADCgMJAwAAAA==.Sinarria:BAAALgAECgEJAQAAAA==.Sithra:BAAALgADCgEJAQAAAA==.',
Sk='Skeemer:BAAALgAECgQJBAAAAA==.Skeetro:BAAALgAECgEJAQAAAA==.Skips:BAAALgAECgQJCQAAAA==.Skullace:BAABLgAECn8pAAIBAAkJDg+xCQCcAQABAAkJDg+xCQCcAQAAAA==.Skullhead:BAAALgADCgEJAQAAAA==.Skybreaker:BAAALgAECgUJCAAAAA==.',
Sm='Smashurfacen:BAAALgADCgcJFAAAAA==.',
Sn='Snitbit:BAAALgADCgkJGgAAAA==.Sno:BAAALgADCgEJAQABLgAECgUJBwADAAAAAA==.Snoopingas:BAAALgADCgIJAgAAAA==.Snpcrklpopu:BAAALgADCgYJCAAAAA==.',
So='Solarana:BAAALgAECgkJCQAAAA==.Sortiebatoru:BAAALgAECgIJAgAAAA==.Sotzi:BAAALgADCggJEQAAAA==.Souldune:BAAALgAECgYJBgAAAA==.',
Sp='Sparkplugg:BAAALgAECgEJAQAAAA==.',
Sr='Srfreaky:BAAALgAECgQJCQAAAA==.',
St='Stormcunning:BAABLgAECn8WAAIiAAYJCAxiTAAWAQAiAAYJCAxiTAAWAQAAAA==.Stormfire:BAAALgADCgcJBwAAAA==.Stormßringer:BAABLgAECn8UAAIiAAgJERDXMwCJAQAiAAgJERDXMwCJAQAAAA==.Stownr:BAAALgAECgYJBgAAAA==.Strip:BAAALgADCgUJCAAAAA==.Strongclaw:BAAALgADCgUJBQAAAA==.Stumpyborg:BAABLgAECn8VAAQBAAcJaAYrLwBXAAAaAAYJNgST1QCiAAABAAIJMwsrLwBXAAAkAAEJhAeqPQArAAABLgAECgkJFgAGAN0LAA==.Stónéhëárt:BAAALgADCgYJBwABLgAECgkJEQADAAAAAA==.',
Su='Subdue:BAAALgADCgQJBAAAAA==.Subverse:BAAALgAECgQJBAAAAA==.Sundance:BAAALgAECgcJDgAAAA==.Sune:BAABLgAECn8gAAMMAAYJxgsIRAD2AAAMAAYJxgsIRAD2AAAcAAEJNwkMeQAqAAAAAA==.Supplicant:BAAALgADCgQJBwAAAA==.',
Sv='Svellulfr:BAAALgAECgEJAQAAAA==.Svuca:BAAALgADCgcJBwAAAA==.',
Sy='Sydneyweenie:BAAALgADCgcJCAAAAA==.Syldi:BAAALgAECgEJAQABLgAECgYJHAASAPYbAA==.Sythis:BAAALgAECgIJAwAAAA==.',
['Sä']='Sästa:BAAALgADCgkJCQAAAA==.',
['Sö']='Sörren:BAABLgAECn8UAAIkAAUJCgRCIgCaAAAkAAUJCgRCIgCaAAAAAA==.',
Ta='Tacosdeasada:BAAALgAECgEJAQAAAA==.Taitertot:BAAALgADCgQJBQAAAA==.Tanelórn:BAAALgAECgIJAwAAAA==.Tanlon:BAAALgAECgcJCwAAAA==.Taykorra:BAAALgADCggJDQAAAA==.',
Te='Telandril:BAABLgAECn8vAAIjAAkJvxFVMgDMAQAjAAkJvxFVMgDMAQAAAA==.Telphin:BAAALgAECgYJCQAAAA==.Tempestira:BAAALgAECgEJAQAAAA==.Tensuken:BAABLgAECn8ZAAINAAYJpBgkpgAiAQANAAYJpBgkpgAiAQAAAA==.Teylonna:BAAALgAECgEJAQAAAA==.',
Th='Thadgun:BAAALgADCgkJFQAAAA==.Thadium:BAAALgADCgYJCQAAAA==.Thalgan:BAAALgAECgEJAQAAAA==.Thalyn:BAAALgAECgEJAQAAAA==.Thecword:BAAALgADCgYJBgAAAA==.Themedic:BAABLgAECn8XAAMVAAcJxRDKTQBrAQAVAAcJxRDKTQBrAQAiAAEJ6gF0twAXAAAAAA==.Theremar:BAAALgAECgMJAwAAAA==.Thergothon:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.Thisisdrexx:BAAALgAECgIJAwAAAA==.Thorwrath:BAAALgADCgEJAgAAAA==.Thrazoro:BAAALgAECgQJBAAAAA==.Thrazzoro:BAAALgAECgYJEwAAAA==.',
Ti='Tiarl:BAABLgAECn8wAAISAAkJAhcWEwA0AgASAAkJAhcWEwA0AgAAAA==.Tiia:BAAALgADCgIJAgAAAA==.Timex:BAABLgAECn8XAAMeAAYJRCD5DgDrAQAeAAYJRCD5DgDrAQAdAAEJUheKhgA+AAAAAA==.Tinysitril:BAAALgAECgYJCQABLgAECgkJIQAXAH4WAA==.Tinysohei:BAAALgAECgMJAwAAAA==.Titañick:BAAALgAECgEJAwAAAA==.',
To='Tom:BAABLgAECn8WAAMdAAYJLgtuUgDZAAAdAAYJLgtuUgDZAAAeAAEJZQjoJQAvAAAAAA==.Toosxyfohair:BAAALgAECgcJEQAAAA==.',
Tr='Trainwrekk:BAAALgADCgYJBgAAAA==.Tranqar:BAAALgAECgQJBgAAAA==.Tresg:BAAALgAECgYJCQAAAA==.Trissandra:BAAALgAECgEJAQAAAA==.Trolltoll:BAAALgADCgEJAwAAAA==.Trüth:BAAALgADCggJEAAAAA==.',
Tw='Twylidan:BAEALgAECgkJBQABLgAFFAQJCQAdAOkeAA==.',
Ty='Tyrannus:BAAALgADCgYJBgAAAA==.Tyregar:BAAALgAECgEJAQAAAA==.Tyrànda:BAAALgADCgMJAwAAAA==.Tyzy:BAAALgAECgEJAgAAAA==.',
['Tö']='Tötém:BAAALgAECgEJAQAAAA==.',
Ul='Ulanhi:BAABLgAECn8VAAIhAAUJzh31EACdAQAhAAUJzh31EACdAQAAAA==.',
Un='Undeadjelly:BAAALgAECgYJDAAAAA==.Unholy:BAAALgAECgYJDwAAAA==.',
Ur='Urkzul:BAAALgADCgMJAwAAAA==.Ursoth:BAAALgADCgUJCgAAAA==.',
Ut='Uthèrsmight:BAAALgAECgYJBgAAAA==.Uti:BAAALgADCgUJBQAAAA==.',
Uu='Uubs:BAAALgADCgEJAQABLgAFFAMJCgANAJoSAA==.',
Va='Valakk:BAAALgAECgIJBQAAAA==.Vallak:BAAALgADCgIJBAAAAA==.Valsitril:BAAALgAECgYJEAABLgAECgkJIQAXAH4WAA==.Valthaczar:BAAALgAECgMJBgAAAA==.Vanara:BAAALgAECgEJAgAAAA==.Varadun:BAAALgAFFAIJAwAAAA==.Varrosh:BAAALgADCgYJBgAAAA==.Vathan:BAAALgAECgQJBQAAAA==.',
Ve='Velmora:BAAALgAECgkJCQAAAA==.Velsetin:BAABLgAECn8dAAIFAAcJTBsyTABSAgAFAAcJTBsyTABSAgABLgAFFAMJBQAUAMcUAA==.Verathina:BAAALgADCgEJAQAAAA==.Versed:BAAALgADCgUJBQABLgAECgQJBAADAAAAAA==.Veryspooky:BAABLgAECn8aAAIaAAgJNhn5NAD/AQAaAAgJNhn5NAD/AQAAAA==.Vexian:BAABLgAECn8UAAMiAAkJVBvdDQCBAgAiAAkJVBvdDQCBAgAVAAEJ3B9VrQBcAAAAAA==.',
Vf='Vfl:BAAALgADCgcJBwAAAA==.',
Vi='Vicas:BAAALgAECgYJEAAAAA==.',
Vl='Vladdok:BAAALgAECgUJBQAAAA==.Vladok:BAAALgAECgEJAQAAAA==.Vladokk:BAAALgAECgMJAwAAAA==.',
Vo='Voidofdeath:BAAALgADCgQJBAAAAA==.Voidshiekah:BAAALgADCgEJAQAAAA==.Vorteia:BAAALgADCgYJBgAAAA==.',
['Vé']='Véngéánçé:BAAALgAECgMJBAAAAA==.',
Wa='Wald:BAAALgAECgYJEAAAAA==.Warmongerr:BAAALgADCgIJAgAAAA==.Waruh:BAAALgADCgcJCQAAAA==.',
We='Webgar:BAAALgAECgEJAQAAAA==.',
Wh='Whisperlia:BAAALgAECgQJBQAAAA==.White:BAAALgAECgEJAQAAAA==.Whitetoothe:BAABLgAECn8kAAICAAYJ4hJfewA7AQACAAYJ4hJfewA7AQAAAA==.',
Wi='Wistmeaver:BAABLgAECn8WAAMIAAYJySKHFgBSAgAIAAYJySKHFgBSAgAJAAMJ5SD3NgAZAQAAAA==.Witherbear:BAAALgADCgcJBwAAAA==.Witherhoard:BAAALgADCgEJAQAAAA==.Wizzy:BAAALgADCgEJAQAAAA==.',
['Wå']='Wånheda:BAAALgAECggJEwAAAA==.',
Xa='Xaniana:BAAALgAECgkJDQAAAA==.Xaosin:BAAALgADCgUJBQAAAA==.',
Xe='Xenzak:BAAALgAECgEJAQAAAA==.Xephir:BAAALgADCgMJAwAAAA==.Xerxës:BAAALgAECgEJAQAAAA==.',
Xl='Xl:BAAALgAECgQJCwAAAA==.',
Xo='Xoito:BAAALgAECgEJAQABLgAECgcJBAADAAAAAA==.Xotiko:BAAALgAECgYJDAAAAA==.',
Xu='Xubris:BAAALgADCgYJCQAAAA==.',
['Xâ']='Xâxâs:BAAALgAECgMJAwABLgAECggJGQAdAFsEAA==.',
Ya='Yaerin:BAACLgAFFH8VAAIcAAQJPiOqFwCMAQAcAAQJPiOqFwCMAQAuAAQKfyQAAhwACQkAIqMDAF4DABwACQkAIqMDAF4DAAAA.',
Yu='Yunarä:BAAALgAECgYJBwAAAA==.Yuukon:BAABLgAECn8ZAAQRAAgJkRXxGgB5AQARAAgJkRXxGgB5AQALAAQJ5gPBJgFoAAAHAAEJDwgrGAAvAAAAAA==.',
Za='Zakuul:BAAALgADCgQJBAAAAA==.Zalezaar:BAAALgAECgIJAgAAAA==.Zangetsu:BAAALgAECgcJBwAAAA==.Zaxie:BAABLgAECn8oAAIQAAgJXByNIwA3AgAQAAgJXByNIwA3AgAAAA==.',
Ze='Zenwu:BAAALgADCgkJGwAAAA==.Zephrylia:BAAALgAECgQJBQAAAA==.Zerama:BAAALgAECgUJBQAAAA==.',
Zh='Zheratul:BAAALgAECgEJAQAAAA==.Zhirl:BAAALgAECgkJCQAAAA==.Zhivet:BAAALgAECgYJBgAAAA==.',
Zi='Zilphia:BAAALgAECggJEgAAAA==.',
Zu='Zuriel:BAAALgAECgIJAgAAAA==.',
Zy='Zyku:BAAALgAECgEJAQAAAA==.Zylphie:BAAALgADCgcJBwAAAA==.',
['Àm']='Àmagezing:BAAALgAFFAIJAgABLgAFFAQJEQANAIIgAA==.',
['Åj']='Åj:BAAALgADCgcJBwAAAA==.',
['Åp']='Åpexx:BAAALgAECgYJDAAAAA==.',
['Çw']='Çwÿbàbý:BAAALgAECgIJAwAAAA==.',
['Ór']='Órión:BAABLgAECn8VAAICAAYJ1BKrlwACAQACAAYJ1BKrlwACAQAAAA==.',
['Ös']='Östara:BAABLgAECn8bAAIjAAcJgBjEKwDxAQAjAAcJgBjEKwDxAQAAAA==.',
['ßj']='ßjörn:BAAALgADCgQJBAAAAA==.',
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
