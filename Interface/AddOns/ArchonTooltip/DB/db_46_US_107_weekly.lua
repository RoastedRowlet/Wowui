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

local lookup = {'Paladin-Retribution','Paladin-Protection','Priest-Shadow','Priest-Holy','Priest-Discipline','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Druid-Feral','Druid-Restoration','DemonHunter-Devourer','Druid-Balance','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Warrior-Fury','Hunter-BeastMastery','Rogue-Assassination','DeathKnight-Frost','Paladin-Holy','Warrior-Protection','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Mage-Frost','Mage-Arcane','Mage-Fire','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warrior-Arms','Monk-Mistweaver','Druid-Guardian','Rogue-Subtlety',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abogato:BAAALgAECgQJBAAAAA==.',
Ae='Aedra:BAAALgADCgcJEgAAAA==.Aeowyyn:BAABLgAECn8UAAIBAAgJwAZVtgATAQABAAgJwAZVtgATAQAAAA==.',
Af='Af:BAAALgADCgUJBQAAAA==.Afib:BAAALgADCgEJAgAAAA==.',
Ah='Ahnir:BAABLgAECn8iAAIBAAkJrg9jagCXAQABAAkJrg9jagCXAQAAAA==.Ahnkhano:BAABLgAECn8dAAICAAgJ8RFiEgCjAQACAAgJ8RFiEgCjAQAAAA==.',
Ai='Aidenarren:BAAALgADCgkJEAAAAA==.Ainge:BAAALgADCgUJBQAAAA==.Aiom:BAAALgADCgMJAwAAAA==.',
Ak='Akashaa:BAAALgADCgEJAQAAAA==.Akbartheiiv:BAACLgAFFH8YAAIDAAcJ7xi4AQACAgADAAcJ7xi4AQACAgAuAAQKfzMAAgMACQl7I1wEABQDAAMACQl7I1wEABQDAAAA.',
Al='Alexanderson:BAAALgADCgEJAQAAAA==.Alhamdulilah:BAAALgADCgEJAQAAAA==.Alivour:BAAALgAECgUJBQAAAA==.Allero:BAAALgAECgMJAwAAAA==.Allistrana:BAABLgAECn8iAAIEAAkJBRwzEwBGAgAEAAkJBRwzEwBGAgAAAA==.Aluvia:BAAALgAECgIJBAAAAA==.',
Am='Amairis:BAABLgAECn8dAAMFAAYJWRgOJACsAQAFAAYJWRgOJACsAQADAAMJaAlOaAB2AAAAAA==.Ambiorix:BAAALgADCgEJAgAAAA==.',
An='Anari:BAAALgADCgUJBQAAAA==.Angelsin:BAAALgADCgkJGwAAAA==.Animorph:BAAALgADCgcJJQAAAA==.Annestasia:BAAALgAECgcJCAAAAA==.Anrion:BAABLgAECn8uAAMGAAkJHyOyBgDJAgAGAAkJHyOyBgDJAgAHAAcJNxyVCQDNAQAAAA==.Anteater:BAAALgADCgEJAQABLgAECgUJDgAIAAAAAA==.',
Ap='Aph:BAAALgAECgcJDgAAAA==.Apolló:BAAALgAECgkJDwAAAA==.',
Ar='Araiana:BAAALgAECgEJAQAAAA==.Arayia:BAABLgAECn8cAAMJAAgJsxqoCQAjAgAJAAgJsxqoCQAjAgAKAAUJkA2tdADVAAAAAA==.Arelian:BAABLgAECn8ZAAMHAAkJ2BI3EQA1AQAHAAYJmhY3EQA1AQALAAkJbwsakAD8AAAAAA==.Aristia:BAABLgAECn8xAAMKAAgJciQNBwBEAwAKAAgJciQNBwBEAwAMAAEJzwxGjwAtAAABLgAECgIJAgAIAAAAAA==.Artaic:BAAALgAECgUJDgAAAA==.Artemysia:BAAALgADCgEJAQAAAA==.',
At='Ataboom:BAAALgADCgEJAQAAAA==.Ataliya:BAAALgAECgQJCgAAAA==.',
Au='Auranar:BAABLgAECn8uAAINAAkJigpMDwBjAQANAAkJigpMDwBjAQAAAA==.Aurilia:BAABLgAECn8mAAIEAAYJZB/6FwAKAgAEAAYJZB/6FwAKAgAAAA==.',
Av='Avanicus:BAABLgAECn8oAAQOAAkJhQonIgBFAQAOAAcJbwknIgBFAQAPAAcJUAlFFQAdAQAQAAQJqAPLFwFNAAAAAA==.Aven:BAABLgAECn8kAAMRAAgJkRLmXQCsAQARAAgJchLmXQCsAQASAAUJrQduQgCCAAAAAA==.',
Ax='Axiomronin:BAABLgAECn8qAAMTAAkJYCSUBQDkAgATAAgJ9ySUBQDkAgAUAAgJJyK3DgCSAgAAAA==.',
Ay='Ayroon:BAAALgAECgQJBQAAAA==.',
Az='Azulien:BAABLgAECn8pAAMFAAkJqQMnOAAxAQAFAAkJqQMnOAAxAQAEAAEJSwAgfgAMAAAAAA==.Azuriel:BAAALgAECgIJAgAAAA==.',
Ba='Baltuk:BAABLgAECn8aAAIRAAgJ0x3YJgCgAgARAAgJ0x3YJgCgAgAAAA==.Bananafarts:BAAALgADCgMJAwAAAA==.Banderblitz:BAACLgAFFH8JAAIVAAIJRBuaPACwAAAVAAIJRBuaPACwAAAuAAQKfzUAAhUACQlIIZ4LAKwCABUACQlIIZ4LAKwCAAAA.Baobei:BAAALgADCgcJBwAAAA==.Bar:BAACLgAFFH8HAAMDAAQJigbuEQCOAAADAAQJigbuEQCOAAAEAAMJlRETEgBUAAAuAAQKfxsAAgMACAlxGicVAEMCAAMACAlxGicVAEMCAAAA.Barunnar:BAAALgADCgEJAQAAAA==.',
Be='Bearlyshady:BAAALgADCgcJCwABLgAECgkJJgALAIkUAA==.Bellatrixie:BAAALgAECgcJEAAAAA==.Benafflock:BAABLgAECn8eAAQPAAgJYwp0EQBIAQAPAAgJRAp0EQBIAQAQAAQJYwSY4QCXAAAOAAEJDw2WQAAqAAABLgAECgcJEgAIAAAAAA==.Beriadhwen:BAAALgAECgYJBwAAAA==.Bermy:BAABLgAECn8aAAIOAAkJGxH2EwAMAQAOAAkJGxH2EwAMAQAAAA==.Bewildert:BAAALgADCgIJAgAAAA==.',
Bh='Bhawkwco:BAAALgADCgEJAQAAAA==.',
Bi='Bigjaina:BAAALgAFFAIJAgAAAA==.',
Bl='Blackhawkdk:BAACLgAFFH8FAAIRAAMJxw41oQDRAAARAAMJxw41oQDRAAAuAAQKfy4AAhEACQmyG/snAGACABEACQmyG/snAGACAAAA.Blende:BAABLgAECn8qAAIBAAkJKSE+EADiAgABAAkJKSE+EADiAgAAAA==.Bloodshadow:BAABLgAECn81AAIWAAkJxRMGOwDvAQAWAAkJxRMGOwDvAQAAAA==.Blueberrae:BAAALgADCgEJAQAAAA==.Bluemaster:BAAALgADCgYJBgAAAA==.Bluish:BAAALgAECgMJAwAAAA==.',
Bo='Boidohanta:BAAALgADCgUJBQAAAA==.',
Br='Braveharth:BAABLgAECn8XAAIBAAgJPQTz0gDsAAABAAgJPQTz0gDsAAAAAA==.Braxus:BAAALgAECgMJBAAAAA==.Breakcooloz:BAACLgAFFH8UAAIXAAcJvR7/AAAIAgAXAAcJvR7/AAAIAgAuAAQKfyIAAhcACAmoIyIBADQDABcACAmoIyIBADQDAAEuAAUUCAkhABEAiCEA.Brooce:BAABLgAECn8zAAIBAAkJyB9ZFwC1AgABAAkJyB9ZFwC1AgAAAA==.Broom:BAAALgADCgkJHQABLgAFFAIJAgAIAAAAAA==.Brylise:BAAALgADCgIJAgAAAA==.',
Bu='Burstinurass:BAACLgAFFH8hAAIRAAgJiCGPBwCjAgARAAgJiCGPBwCjAgAuAAQKfxgAAhEACAm+JQEZAK4CABEACAm+JQEZAK4CAAAA.',
Ca='Caladorion:BAAALgAECgIJAgAAAA==.Candyjar:BAAALgADCgcJDAAAAA==.Cantmissyou:BAAALgAFFAEJAgAAAA==.Capidk:BAAALgAFFAEJAQAAAA==.Carafe:BAAALgADCgEJAQABLgAECgkJJAAYAIYeAA==.Carbonight:BAAALgADCgEJAQAAAA==.Carlos:BAAALgAECgUJDwABLgAECggJJQABAHgiAA==.Caspianne:BAAALgAECgQJBgAAAA==.',
Cb='Cbrown:BAAALgAECgEJAQAAAA==.',
Ce='Celani:BAACLgAFFH8JAAIEAAMJ9RLyIACsAAAEAAMJ9RLyIACsAAAuAAQKfyYAAwQACAnaGSUXABICAAQACAnaGSUXABICAAUAAQm6AWpeACQAAAAA.Celintha:BAAALgADCgcJCwAAAA==.Cellyne:BAABLgAECn8tAAMBAAgJvwlOmwA8AQABAAgJvwlOmwA8AQAZAAIJJALqiAA2AAAAAA==.Centy:BAAALgAECgYJEgAAAA==.Ceredisam:BAAALgADCgcJBwAAAA==.',
Ch='Chainheal:BAAALgAECgMJAwAAAA==.Chaz:BAAALgAECgcJEQAAAA==.Chedrood:BAAALgADCgMJBwAAAA==.Chelives:BAEBLgAECn8xAAIaAAcJNQOkMwCoAAAaAAcJNQOkMwCoAAAAAA==.Choalmakyahn:BAAALgADCgUJBQAAAA==.Chubrub:BAABLgAECn8aAAMbAAYJHwX6aACoAAAbAAYJHwX6aACoAAAcAAMJLAM1vwBNAAAAAA==.Chìef:BAAALgADCgEJAQAAAA==.',
Ci='Cires:BAAALgAECgEJAgAAAA==.',
Cl='Claud:BAAALgAECgYJBgAAAA==.Cleric:BAAALgADCgMJAwAAAA==.',
Co='Cobaltwolf:BAAALgAECgQJCAAAAA==.Colanasou:BAABLgAECn8YAAIbAAYJdQ92TQD7AAAbAAYJdQ92TQD7AAAAAA==.Coldbattler:BAABLgAECn8WAAIWAAkJfBFtTAC4AQAWAAkJfBFtTAC4AQAAAA==.Colostomia:BAAALgADCgMJAwAAAA==.Copelongcut:BAAALgADCgMJAQAAAA==.Corrick:BAAALgADCgcJEAAAAA==.',
Cr='Crastosmomma:BAAALgADCgkJCQAAAA==.Crow:BAAALgAECgkJHQAAAQ==.',
Cu='Curavis:BAAALgADCgMJAwAAAA==.',
Cy='Cydric:BAACLgAFFH8FAAIBAAMJaxaAHAC8AAABAAMJaxaAHAC8AAAuAAQKfyIAAgEACAmHI8UMACgDAAEACAmHI8UMACgDAAAA.',
Da='Daarrkstar:BAABLgAECn8pAAMcAAcJ/yTyDgDYAgAcAAcJ/yTyDgDYAgAdAAMJrxB5IQC6AAABLgAECgkJKgABACkhAA==.Daenyra:BAAALgADCgUJBQAAAA==.Dakarai:BAAALgADCggJDgAAAA==.Danek:BAAALgADCggJGQAAAA==.Darkane:BAABLgAFFH8KAAMNAAYJaQ6PIQCaAAAWAAQJ3gmzbQC6AAANAAIJOhWPIQCaAAAAAA==.Darknives:BAAALgAECgEJAwAAAA==.Darocate:BAAALgADCgYJBgAAAA==.Dathanarr:BAAALgAECggJCAAAAA==.',
De='Deadskvll:BAAALgADCgYJBgAAAA==.Deathbot:BAACLgAFFH8bAAISAAUJthh4GAAeAQASAAUJthh4GAAeAQAuAAQKf0UAAhIACQnXIiEFANoCABIACQnXIiEFANoCAAAA.Demira:BAAALgADCgMJAwAAAA==.Demoray:BAACLgAFFH8KAAINAAUJvBiZCACSAQANAAUJvBiZCACSAQAuAAQKfxQAAg0ABwl0JB0VAIoCAA0ABwl0JB0VAIoCAAAA.Dendrin:BAAALgAECgEJAQAAAA==.Deneese:BAAALgAECgIJAgAAAA==.Derrpy:BAAALgADCgEJAQAAAA==.Desc:BAAALgAECgEJAQAAAA==.Desniee:BAABLgAECn8gAAQeAAkJMx91QwBuAgAeAAkJMx91QwBuAgAfAAIJHA3jFAB3AAAgAAEJuxW+DgA/AAAAAA==.Dethrone:BAABLgAECn8aAAQQAAgJhx2ALgAdAgAQAAcJoR+ALgAdAgAOAAYJ5xniIABNAQAPAAEJXBYtLgBCAAAAAA==.',
Di='Digitpro:BAABLgAECn89AAIhAAgJcxDuHwCdAQAhAAgJcxDuHwCdAQAAAA==.Dirtydragon:BAABLgAECn8oAAMiAAgJ4x2SBgCWAgAiAAgJ4x2SBgCWAgAjAAEJhwdmZQArAAAAAA==.Disturbo:BAAALgADCgkJDwAAAA==.Divinedecay:BAABLgAECn8dAAISAAcJaA8yKAAQAQASAAcJaA8yKAAQAQABLgAECgkJRAAWAHQaAA==.',
Do='Dok:BAAALgADCgcJCQAAAA==.Donoraginn:BAAALgADCgkJIgABLgADCgkJRQAIAAAAAA==.Donos:BAAALgADCgkJRQAAAA==.Dontkare:BAAALgADCgcJEQABLgAECgkJKgAaAJ0lAA==.Doomjuele:BAAALgADCgYJBgAAAA==.Dorsai:BAAALgADCgUJBQAAAA==.Dott:BAAALgADCgIJAgABLgAECgkJIgABAK4PAA==.',
Dr='Draaxx:BAAALgADCgIJAgAAAA==.Draazzy:BAAALgADCgkJEgAAAA==.Dracbanti:BAAALgADCgkJEQAAAA==.Dracobelle:BAABLgAECn8jAAMiAAYJ2RssDwDVAQAiAAYJ2RssDwDVAQAjAAMJ+wjucQCBAAAAAA==.Dragundeez:BAAALgAECggJCgAAAA==.Drark:BAAALgAECgEJAgAAAA==.Drathiel:BAAALgAECgMJAwAAAA==.Draxxien:BAAALgADCgcJBwAAAA==.Drazlowe:BAAALgADCgQJBwAAAA==.Draäx:BAAALgADCgkJGwAAAA==.Dreezee:BAAALgAECgcJEQAAAA==.Drizztknight:BAAALgADCgEJAQAAAA==.Droobear:BAAALgAECgIJAgAAAA==.Drwho:BAABLgAECn8pAAIeAAkJ1xihMgBMAgAeAAkJ1xihMgBMAgAAAA==.Dràco:BAAALgADCggJDwAAAA==.Drääx:BAAALgADCggJCAAAAA==.Dräëxx:BAAALgADCgcJDQAAAA==.',
Du='Durimli:BAAALgAECgUJBAAAAA==.',
Dw='Dwayneb:BAAALgAECgkJBwAAAA==.',
Dy='Dyric:BAAALgAECgMJBQAAAA==.',
['Dî']='Dîxon:BAAALgAFFAMJBAABLgAFFAgJIQARAIghAA==.',
['Dô']='Dôz:BAAALgADCgQJBAAAAA==.',
Ea='Earthernbot:BAABLgAFFH8OAAIeAAQJRwnSagAVAQAeAAQJRwnSagAVAQAAAA==.Earthspeaker:BAAALgADCgEJAQAAAA==.',
Ei='Eidolon:BAAALgADCgkJEgAAAA==.',
El='Eleram:BAAALgADCgYJBgABLgAECgkJIgABAK4PAA==.Elfadwagon:BAACLgAFFH8ZAAIkAAYJoRibAQCKAQAkAAYJoRibAQCKAQAuAAQKfyQAAiQACAlcIa8CAAIDACQACAlcIa8CAAIDAAAA.Eliptical:BAAALgAECgYJEwABLgAECggJGwABAO4eAA==.Elkesey:BAAALgADCgEJAQAAAA==.Elonura:BAAALgADCgYJBgAAAA==.Elunea:BAAALgADCggJCwAAAA==.',
Em='Emishanot:BAAALgAECgEJAQABLgAECgYJEQAIAAAAAA==.',
Ep='Epoch:BAAALgADCgEJAQAAAA==.',
Er='Erangar:BAABLgAECn8kAAIbAAYJMQz5VgDbAAAbAAYJMQz5VgDbAAAAAA==.Erdor:BAAALgADCgcJDgAAAA==.Erini:BAAALgADCgkJCQAAAA==.Erred:BAAALgADCgcJBwAAAA==.',
Es='Esmer:BAABLgAECn8vAAIBAAkJJwomegB3AQABAAkJJwomegB3AQAAAA==.',
Et='Etheman:BAAALgAECgcJDQAAAA==.',
Eu='Euphrasie:BAAALgAECgIJAgABLgAECgkJHgAcAG4hAA==.',
Ev='Eversteal:BAAALgADCgQJBAABLgAECggJLAACAM0bAA==.Evholker:BAABLgAECn8fAAMkAAkJaxFrDABFAQAkAAgJHhJrDABFAQAjAAYJFw5SSgD/AAAAAA==.',
Ew='Ewinkus:BAAALgADCgYJBgAAAA==.',
Ex='Excuses:BAAALgAECgYJDAABLgAFFAcJJQAVAJ8ZAA==.Executey:BAAALgADCgQJBAAAAA==.Exhumina:BAAALgAECgcJCQAAAA==.',
Fa='Facestealerr:BAABLgAECn8ZAAIQAAYJMRZtcQBWAQAQAAYJMRZtcQBWAQAAAA==.Fallenhullkk:BAAALgADCgYJBgAAAA==.Fangyi:BAAALgADCgYJBgAAAA==.',
Fe='Feetsmell:BAAALgADCgkJEgABLgAFFAIJAgAIAAAAAA==.Felmufín:BAABLgAECn8cAAIQAAgJQwwDeQBGAQAQAAgJQwwDeQBGAQAAAA==.Felspury:BAAALgAECgEJAQABLgAFFAUJEgAeACEOAA==.Feyrea:BAAALgAECgQJBgAAAA==.',
Fi='Fibula:BAAALgADCgcJBwAAAA==.Fitzfarseer:BAAALgADCgkJCQAAAA==.',
Fl='Flairrick:BAABLgAECn8yAAMVAAgJNSQhBwDrAgAVAAgJNSQhBwDrAgAaAAEJ0iO7QABpAAAAAA==.Flars:BAABLgAECn8hAAIYAAgJdxvXBgAwAgAYAAgJdxvXBgAwAgAAAA==.Flatliner:BAACLgAFFH8QAAIZAAYJgwVaGwA+AQAZAAYJgwVaGwA+AQAuAAQKfzsAAxkACQkADSM0AK0BABkACQkADSM0AK0BAAEAAQmlCV9TASoAAAAA.Floracide:BAAALgAECgYJCwABLgAECggJCgAIAAAAAA==.Florence:BAAALgAECggJCgAAAA==.Floret:BAAALgAECgEJAQAAAA==.Flyingbot:BAAALgAECgUJBQAAAA==.',
Fo='Foid:BAAALgAECgYJBwAAAA==.Forq:BAAALgADCgcJBwAAAA==.',
Fr='Fran:BAAALgADCgYJBgABLgAFFAIJAgAIAAAAAA==.Frankzappn:BAAALgAECgUJBQAAAA==.Fray:BAABLgAECn8iAAILAAkJahqIIgBEAgALAAkJahqIIgBEAgAAAA==.Freeguy:BAABLgAECn8tAAILAAkJjxuHFgCNAgALAAkJjxuHFgCNAgAAAA==.Fruitsnacks:BAAALgAECgEJAQABLgAFFAcJDwALAGgWAA==.',
Fu='Fuddicus:BAABLgAECn9IAAMcAAkJjyRgCQAZAwAcAAkJjyRgCQAZAwAbAAEJGRI9gwA9AAAAAA==.Fuddmore:BAAALgAECgYJBwABLgAECgcJDQAIAAAAAA==.Fuddster:BAAALgAECgcJDQAAAA==.',
Ga='Gaddess:BAABLgAECn8qAAIDAAcJMAiQQgACAQADAAcJMAiQQgACAQAAAA==.Ganath:BAAALgAECgMJAwAAAA==.Ganymede:BAAALgAECgYJEwAAAA==.Garan:BAAALgADCgQJBAAAAA==.Garnar:BAAALgADCgIJAgAAAA==.',
Ge='Geilamaine:BAACLgAFFH8FAAIZAAMJzhI8LgC6AAAZAAMJzhI8LgC6AAAuAAQKfyIAAhkACQkVHOsIAPoCABkACQkVHOsIAPoCAAAA.',
Gi='Gimpy:BAAALgAECgQJBQAAAA==.',
Gl='Glimagi:BAAALgADCgcJDwAAAA==.Glimdaemon:BAAALgAECgIJAgAAAA==.',
Go='Gonefishing:BAABLgAECn8+AAIBAAkJ7iNHDgDxAgABAAkJ7iNHDgDxAgAAAA==.Gorddownie:BAABLgAECn8fAAIMAAYJuAPLYQCNAAAMAAYJuAPLYQCNAAAAAA==.',
Gr='Graied:BAAALgAECgYJBgAAAA==.Granuaille:BAAALgAECgIJAgAAAA==.Grellior:BAAALgAECgEJAQAAAA==.Grimjawz:BAAALgAECgkJEAAAAA==.Grippysocks:BAACLgAFFH8TAAIZAAYJ/RUlEwCOAQAZAAYJ/RUlEwCOAQAuAAQKfzUAAhkACQl0FhIcADQCABkACQl0FhIcADQCAAAA.',
Gu='Gummibear:BAABLgAECn8mAAMlAAcJOhS1HABzAQAlAAcJOhS1HABzAQAaAAQJ2ANZNwCNAAAAAA==.',
Ha='Hakar:BAAALgAECgYJCAAAAA==.Hanoa:BAAALgADCgIJAgAAAA==.Harthoon:BAACLgAFFH8hAAIeAAcJvw1YKQDNAQAeAAcJvw1YKQDNAQAuAAQKfzsAAh4ACQm8Hs0oAHUCAB4ACQm8Hs0oAHUCAAAA.Haruharu:BAAALgAECgMJCwAAAA==.Hawkhogan:BAAALgADCgYJCQAAAA==.Hazdanzul:BAAALgADCgQJBQABLgAECgYJEQAIAAAAAA==.',
He='Hehexxd:BAAALgAECgIJAgAAAA==.Helias:BAAALgADCgkJBgAAAA==.Hemp:BAAALgAECgMJAwAAAA==.Herrondale:BAAALgADCgcJBwAAAA==.Hey:BAAALgADCgkJIwABLgAECgkJQwAmAKAfAA==.',
Hj='Hjukonlikjuj:BAAALgAECgEJAQAAAA==.',
Ho='Holiebelle:BAAALgAECggJCAABLgAECggJIwAiANkbAA==.Hollanov:BAAALgADCgYJBgAAAA==.Honeynoats:BAABLgAECn8sAAIEAAgJYBHtIQCvAQAEAAgJYBHtIQCvAQAAAA==.Honks:BAAALgAECgQJBQAAAA==.Hotdwarf:BAAALgAECggJEgAAAA==.',
Hu='Hubbabubbles:BAAALgAECgEJAQAAAA==.Hullkk:BAACLgAFFH8cAAMlAAcJ/SCQCAC7AQAlAAYJ3B6QCAC7AQAVAAQJ8hvYGwA9AQAuAAQKfzkAAyUACQl8I2UDAPgCABUACAnOJYkFAE4DACUACAkKImUDAPgCAAAA.Hundale:BAAALgAECgQJBAAAAA==.Hutchkins:BAABLgAECn8wAAMQAAgJwiC6MAAUAgAQAAgJwiC6MAAUAgAPAAEJAAB7SAAAAAAAAA==.Hutchknight:BAAALgAECgUJDAABLgAECggJMAAQAMIgAA==.Hutchyo:BAAALgADCgQJBAABLgAECggJMAAQAMIgAA==.',
Hy='Hydro:BAACLgAFFH8JAAIBAAQJRw0QUAAJAQABAAQJRw0QUAAJAQAuAAQKfzQAAwEACQlGIcUXALICAAEACQlGIcUXALICAAIABAk1DxUvAKgAAAAA.Hypovolaemia:BAAALgAECgYJDQAAAA==.',
['Hä']='Häwtz:BAAALgADCgIJAgAAAA==.',
Ia='Iamhealer:BAAALgADCgMJAgAAAA==.',
Il='Illaandra:BAAALgADCgEJAQABLgAECgMJAwAIAAAAAA==.',
Im='Imsanity:BAAALgAECgcJBwAAAA==.',
In='Inari:BAAALgAECgQJBwABLgAECgkJLAAhAE4YAA==.Innervate:BAAALgADCgEJAQABLgAECgMJBAAIAAAAAA==.Inseng:BAABLgAECn8wAAMYAAgJ5CDmBQBNAgAYAAgJOR3mBQBNAgASAAYJQiM2EQD2AQAAAA==.Invasion:BAAALgAECgYJDAAAAA==.',
Ix='Ixy:BAABLgAECn8qAAILAAkJkBrLHgBZAgALAAkJkBrLHgBZAgAAAA==.',
Ja='Jaghas:BAAALgADCgYJEQAAAA==.Jahde:BAABLgAECn9DAAIKAAkJWA1FPgCXAQAKAAkJWA1FPgCXAQAAAA==.Jahoda:BAAALgADCgYJBgAAAA==.Jaina:BAAALgAECgYJCwAAAA==.Jamer:BAABLgAECn8lAAIaAAgJzyLPBQCzAgAaAAgJzyLPBQCzAgAAAA==.Jassykins:BAABLgAECn8uAAIWAAgJQxIaTAC5AQAWAAgJQxIaTAC5AQAAAA==.',
Je='Jeewop:BAAALgADCgEJAQAAAA==.Jeongaegdeom:BAAALgADCgcJDgAAAA==.Jessecuster:BAAALgAECgUJBgAAAA==.',
Ji='Jindouyun:BAABLgAFFH8HAAInAAMJ6CBYDQAdAQAnAAMJ6CBYDQAdAQAAAA==.Jinjerr:BAAALgAECgcJEQAAAA==.',
Jo='Joloc:BAABLgAECn8vAAIOAAkJ8hbWBAAoAgAOAAkJ8hbWBAAoAgAAAA==.Jozay:BAAALgAECgYJDAAAAA==.',
Ju='Juancarlos:BAAALgADCgEJAQAAAA==.',
Ka='Kaidaa:BAAALgAECgQJBAAAAA==.Kaladan:BAAALgAECgUJCwAAAA==.Kalasparkle:BAAALgAECgYJEwAAAA==.Kalrosa:BAABLgAECn8cAAIVAAgJUyMqDgCMAgAVAAgJUyMqDgCMAgABLgAFFAIJCQAVAEQbAA==.Kare:BAABLgAECn8qAAIaAAkJnSVEAwACAwAaAAkJnSVEAwACAwAAAA==.Karee:BAABLgAECn8iAAICAAkJ6yQAAQBOAwACAAkJ6yQAAQBOAwABLgAECgkJKgAaAJ0lAA==.Kathilnas:BAAALgADCgUJBQABLgAECgYJEQAIAAAAAA==.',
Kc='Kcosfomas:BAAALgADCgIJAgAAAA==.',
Ke='Kebob:BAAALgADCgcJCAABLgAECgUJBQAIAAAAAA==.Kermodh:BAAALgAECgcJBwAAAA==.Kermodk:BAAALgAECgYJCgAAAA==.Kermodrood:BAABLgAECn8qAAMMAAkJCSOZBQD+AgAMAAkJCCOZBQD+AgAnAAQJRyI8JQAjAQAAAA==.Kermowar:BAAALgAECgEJAQAAAA==.',
Kh='Khanthurs:BAAALgAECgQJBAAAAA==.Kholdbrew:BAAALgAECgYJCwAAAA==.',
Ki='Kicklife:BAAALgAECgIJAwAAAA==.Kiizo:BAABLgAECn8nAAIoAAgJhRZyGADUAQAoAAgJhRZyGADUAQAAAA==.Kilnot:BAABLgAECn8UAAIcAAcJ4xZQMgC8AQAcAAcJ4xZQMgC8AQAAAA==.Kinstine:BAABLgAECn8VAAISAAYJ/wFMMgCtAAASAAYJ/wFMMgCtAAAAAA==.',
Kn='Knarwxlves:BAABLgAFFH8FAAIhAAMJaxhUGwDxAAAhAAMJaxhUGwDxAAAAAA==.',
Ko='Koltara:BAABLgAFFH8PAAILAAcJaBbnGgDPAQALAAcJaBbnGgDPAQAAAA==.Koltaris:BAACLgAFFH8PAAITAAQJTh+7HAA9AQATAAQJTh+7HAA9AQAuAAQKfyIAAhMACAl2JAwJAJ8CABMACAl2JAwJAJ8CAAEuAAUUBwkPAAsAaBYA.Koltaros:BAAALgADCgYJBgABLgAFFAcJDwALAGgWAA==.Komori:BAAALgAECgYJBgAAAA==.Konshis:BAACLgAFFH8KAAMmAAMJSwxCQgCPAAAmAAMJSwxCQgCPAAAUAAEJqQUHRQAyAAAuAAQKfyQAAiYACQkqFUQqANMBACYACQkqFUQqANMBAAAA.Kookymonster:BAABLgAECn9IAAMQAAkJpiOmBABEAwAQAAgJpiOmBABEAwAOAAcJlh2CBwBPAgAAAA==.Korbyn:BAAALgADCgkJCQAAAA==.Kos:BAACLgAFFH8aAAMRAAcJ2BJPJQDKAQARAAYJ2BJPJQDKAQASAAEJAADsXQAAAAAuAAQKfxkAAxEACQmpIGAbAKECABEACQmpIGAbAKECABgAAgmaGQIqAH0AAAAA.',
Ku='Kuragaru:BAACLgAFFH8ZAAMoAAcJYhq1CQD3AQAoAAcJYhq1CQD3AQAXAAIJbwxWBACsAAAuAAQKfzoAAygACQn4JIcDAA4DACgACQn4JIcDAA4DABcACAlqGicFAEMCAAAA.',
Ky='Kyoubouna:BAAALgAECgQJBAAAAA==.Kyoxi:BAAALgADCgEJAQAAAA==.',
La='Laedrea:BAAALgADCgEJAQAAAA==.Larc:BAAALgAECgcJBwABLgAECgkJMwADAJwbAA==.Larianne:BAAALgAECgcJEgAAAA==.',
Le='Leese:BAABLgAECn8jAAIMAAgJ6wdXQAAJAQAMAAgJ6wdXQAAJAQAAAA==.Leretic:BAAALgAECgYJBgABLgAECggJGwABAO4eAA==.Lerion:BAABLgAECn8bAAIBAAgJ7h4fEgABAwABAAgJ7h4fEgABAwAAAA==.Lester:BAABLgAECn8zAAIDAAkJnBv/DACCAgADAAkJnBv/DACCAgAAAA==.Lethana:BAAALgADCgcJDAAAAA==.Lexysady:BAAALgAECgIJAgAAAA==.',
Li='Liamsun:BAABLgAECn9AAAQmAAkJJhW1HwAXAgAmAAkJJhW1HwAXAgATAAgJShbeHAC8AQAUAAYJuxT4PwAZAQAAAA==.Lidd:BAAALgAECgQJAwAAAA==.Liddrahl:BAAALgAECgEJAQAAAA==.Lidrael:BAABLgAECn8+AAQHAAkJDh4jBACFAgAHAAkJDh4jBACFAgAGAAYJNAX+QgDsAAALAAYJewpXmwDiAAAAAA==.Lidrahl:BAAALgADCgcJDQAAAA==.Liekos:BAAALgAECgMJCAAAAA==.Lightbloom:BAAALgAECgIJBQAAAA==.Lightwing:BAAALgAECgEJAgAAAA==.Liliria:BAABLgAECn88AAIEAAkJdRipFgAXAgAEAAkJdRipFgAXAgAAAA==.Lillidân:BAAALgAECgYJEQABLgAFFAIJBQAeABsVAA==.Lingwong:BAAALgAECgcJCwAAAA==.Litebite:BAAALgAECgUJBQAAAA==.Litharelw:BAAALgAECgIJAwAAAA==.Littlefish:BAAALgADCgcJDwAAAA==.',
Lj='Ljaeì:BAABLgAECn8jAAIDAAgJRxkXGwDrAQADAAgJRxkXGwDrAQAAAA==.',
Ll='Lloreth:BAABLgAECn8sAAIKAAkJGQtaQwCBAQAKAAkJGQtaQwCBAQAAAA==.',
Ln='Lnpoop:BAAALgAECggJEwAAAA==.',
Lo='Locknload:BAAALgADCgQJBAAAAA==.Lockwood:BAABLgAECn8jAAIoAAkJvg8gGQDOAQAoAAkJvg8gGQDOAQAAAA==.Lominar:BAAALgADCgcJBwAAAA==.Lorelei:BAABLgAECn8xAAIWAAcJlBBUbgBfAQAWAAcJlBBUbgBfAQAAAA==.Lorrellia:BAABLgAECn8gAAIeAAkJdgX0jwBUAQAeAAkJdgX0jwBUAQAAAA==.Loway:BAAALgAECgMJAwABLgAFFAIJAgAIAAAAAA==.',
Lu='Luc:BAAALgADCgkJEgABLgAECgkJQwAmAKAfAA==.Lucariõ:BAACLgAFFH8YAAIEAAcJ7RSLAgCDAQAEAAcJ7RSLAgCDAQAuAAQKfxYAAgQACAkXHpMNAH8CAAQACAkXHpMNAH8CAAAA.Lumina:BAABLgAECn8pAAICAAgJXRurCQAwAgACAAgJXRurCQAwAgAAAA==.Lunaría:BAAALgADCgUJBgAAAA==.Lustydragon:BAAALgADCgEJAQAAAA==.',
Ly='Lyllies:BAAALgAECgIJAgAAAA==.Lysergia:BAABLgAECn8eAAIcAAkJbiGqCwD8AgAcAAkJbiGqCwD8AgAAAA==.',
['Lì']='Lìght:BAACLgAFFH8ZAAIZAAUJ4xZ0GwA9AQAZAAUJ4xZ0GwA9AQAuAAQKfyEAAhkABwkWIyQaADECABkABwkWIyQaADECAAAA.',
Ma='Madrona:BAABLgAECn8WAAIeAAgJkQ/zcQCTAQAeAAgJkQ/zcQCTAQAAAA==.Magnumrex:BAAALgADCgcJDAAAAA==.Mahoney:BAAALgAECgUJBQAAAA==.Majestynihil:BAAALgADCggJCAAAAA==.Makkazul:BAABLgAECn8iAAMRAAgJQBnMUwDGAQARAAgJIRnMUwDGAQAYAAUJ3hWdGwDuAAAAAA==.Maladia:BAAALgADCgkJCQAAAA==.Management:BAAALgADCgQJBAAAAA==.Mangler:BAABLgAECn8iAAIbAAgJjgWYUgDqAAAbAAgJjgWYUgDqAAAAAA==.Maris:BAAALgADCgkJGwAAAA==.Marrad:BAAALgAECgQJBAAAAA==.Marrok:BAAALgAECgcJBwAAAA==.Marunji:BAAALgAECgYJEQAAAA==.Matcauthon:BAAALgAECgYJEAAAAA==.Matrim:BAAALgAECgQJBwAAAA==.Mattdæmon:BAABLgAECn8rAAQGAAkJxQ5FHACWAQAGAAkJxQ5FHACWAQAHAAQJEwm8JAB1AAALAAIJpwLF2AA+AAAAAA==.Mattmattmatt:BAAALgADCgEJAQAAAA==.Mazzak:BAAALgADCgUJDgAAAA==.',
Me='Meanit:BAAALgAECgQJBgAAAA==.Meekogaia:BAABLgAECn89AAIcAAkJRiH6BwAtAwAcAAkJRiH6BwAtAwAAAA==.Meekosan:BAAALgAECgQJBgAAAA==.Melestaris:BAAALgAECggJCAAAAA==.',
Mi='Mihlenna:BAAALgADCgcJBwAAAA==.Millerowntoo:BAAALgAFFAIJBAABLgAFFAMJCwAWAP8mAA==.Mimzy:BAAALgAECgEJAgAAAA==.Minarmo:BAAALgADCgEJAQAAAA==.Mingzi:BAAALgAECggJDwAAAA==.Missanabie:BAAALgADCgcJBwAAAA==.Missymeow:BAAALgADCgYJDAAAAA==.Mital:BAAALgADCgEJAQAAAA==.Mizu:BAEALgAECgEJAgABLgAFFAUJCgAjAGkMAA==.',
Mm='Mmbear:BAAALgAECgEJAQABLgAFFAYJJAABAAgYAA==.',
Mo='Mojeen:BAAALgADCgIJAgAAAA==.Monkoko:BAAALgADCgEJAgAAAA==.Montkriege:BAABLgAECn8XAAUKAAcJNRCwRwBuAQAKAAcJNRCwRwBuAQAMAAUJpwLTZACOAAAJAAIJoxJgKgB1AAAnAAIJKxgQZwBBAAAAAA==.Moonsocks:BAAALgAECgUJBQABLgAFFAYJEwAZAP0VAA==.Morpheus:BAAALgADCggJCAAAAA==.Mourium:BAAALgAECgMJAwAAAA==.Moxxie:BAABLgAECn8WAAMMAAcJMxaqOAAtAQAMAAYJsBWqOAAtAQAJAAEJwBjBRQBLAAAAAA==.',
Mu='Mufín:BAAALgAECgYJCQAAAA==.Murfie:BAABLgAECn8aAAMDAAkJVRYzIwC+AQADAAkJVRYzIwC+AQAEAAQJWgyDWQDOAAAAAA==.Murica:BAAALgADCgEJAQABLgAFFAIJAgAIAAAAAA==.',
My='Mythiccbops:BAAALgAECgMJAwABLgAECgkJNwAEAK4ZAA==.Mythosrex:BAAALgAECgcJBgAAAA==.',
['Mâ']='Mâjôr:BAAALgADCgUJBQAAAA==.',
['Mì']='Mìr:BAACLgAFFH8SAAILAAUJEBT0RwALAQALAAUJEBT0RwALAQAuAAQKfzIAAwsACAldIWMeAFsCAAsACAldIWMeAFsCAAYABgn7EB02AC8BAAAA.',
['Mó']='Mónkass:BAAALgAECgEJAQAAAA==.',
Na='Naitho:BAAALgAECgYJBgAAAA==.Nakedfeet:BAAALgADCgEJAQABLgAFFAYJEwAZAP0VAA==.Narena:BAAALgADCgYJBgAAAA==.Nashira:BAABLgAECn8mAAIcAAkJRgssTgB0AQAcAAkJRgssTgB0AQAAAA==.Nashness:BAACLgAFFH8SAAMRAAUJGR6aSABcAQARAAUJGR6aSABcAQAYAAIJOQcDIAB9AAAuAAQKfzIAAxEACQkOIwcQAB0DABEACQkOIwcQAB0DABgAAQnhI6suAF8AAAAA.Natharion:BAABLgAECn82AAMPAAkJlBiVAgCTAgAPAAkJhRiVAgCTAgAQAAgJWAjhigAjAQAAAA==.Nazrogul:BAABLgAECn8VAAIRAAYJXwg+sgAeAQARAAYJXwg+sgAeAQAAAA==.',
Ne='Nerfme:BAAALgAECgYJBwAAAA==.Nezar:BAABLgAECn8YAAMKAAgJPhP4QACLAQAKAAcJChP4QACLAQAMAAUJUBk2OQAqAQAAAA==.',
Ni='Ninjaxe:BAACLgAFFH8MAAIUAAQJkhAxCAD0AAAUAAQJkhAxCAD0AAAuAAQKfyIAAxQACAnLH94JANoCABQACAnLH94JANoCABMAAQkmCD+VACAAAAEuAAUUBgkKAA0AaQ4A.Ninkharak:BAAALgADCgEJAQAAAA==.Nishal:BAAALgAECgMJBAABLgAECgkJOQAcALcdAA==.Nitazuresh:BAAALgADCgEJAQABLgAECgYJJgAEAGQfAA==.Niterage:BAAALgADCgYJDQAAAA==.',
Nn='Nn:BAABLgAECn8yAAInAAgJTBHYHwBKAQAnAAgJTBHYHwBKAQAAAA==.',
No='Noasmago:BAAALgAECgMJAwABLgAFFAUJFQADADgUAA==.Novachrono:BAAALgADCgIJAgAAAA==.',
Nu='Nu:BAAALgAECgYJDAAAAA==.Nuckinphutz:BAAALgADCgYJCwAAAA==.Nullthor:BAABLgAECn8UAAIdAAYJ7xM5FAB3AQAdAAYJ7xM5FAB3AQAAAA==.Nurfd:BAABLgAECn8UAAIaAAYJcAEKQABrAAAaAAYJcAEKQABrAAAAAA==.',
['Nè']='Nègan:BAABLgAECn8+AAMWAAkJORiiNgD/AQAWAAkJORiiNgD/AQANAAgJbwghFAAaAQAAAA==.',
['Nì']='Nìr:BAABLgAFFH8JAAIGAAUJ2hGhEQATAQAGAAUJ2hGhEQATAQAAAA==.',
['Nó']='Nóva:BAAALgADCgQJBAAAAA==.',
['Nô']='Nôyar:BAAALgAECgQJBQAAAA==.',
Ob='Obamakare:BAAALgAECgYJDQABLgAECgkJKgAaAJ0lAA==.Obfuscen:BAAALgADCgYJBgAAAA==.',
Od='Odinrex:BAABLgAECn87AAIWAAkJJRh+HwBmAgAWAAkJJRh+HwBmAgAAAA==.',
Og='Ogmattbone:BAAALgADCgMJAQAAAA==.',
Ol='Oldjuel:BAAALgADCgkJCQAAAA==.',
Op='Opuntia:BAABLgAECn8aAAMUAAYJpBlwJgB/AQAUAAYJpBlwJgB/AQAmAAYJYw2LZQDdAAAAAA==.',
Ou='Ouch:BAAALgADCgMJAwAAAA==.Outofarrows:BAABLgAECn9OAAMNAAkJcSF8AQAEAwANAAkJcSF8AQAEAwAhAAEJXwmRLgA4AAABLgAFFAIJAgAIAAAAAA==.',
Ow='Ow:BAAALgADCgEJAQABLgADCgMJAwAIAAAAAA==.Ownown:BAAALgAECgIJAgABLgAFFAMJCwAWAP8mAA==.',
Pa='Palinuttz:BAAALgAECgMJAwAAAA==.Pallypaladin:BAACLgAFFH8kAAIBAAYJCBhWIAB+AQABAAYJCBhWIAB+AQAuAAQKfyEAAgEACQnTH1MoAF8CAAEACQnTH1MoAF8CAAAA.Partywolf:BAAALgAECgYJBgAAAA==.Pasteeater:BAAALgAECgQJBAAAAA==.',
Pe='Pernelope:BAABLgAECn8iAAILAAcJ7RvRRADgAQALAAcJ7RvRRADgAQAAAA==.Pernicus:BAAALgAECgEJAwAAAA==.',
Ph='Phatzero:BAABLgAECn9EAAMWAAkJdBohHgBtAgAWAAkJdBohHgBtAgANAAIJMgSZOAA6AAAAAA==.Phöenix:BAAALgAECgEJAQAAAA==.',
Pi='Piedra:BAAALgADCgYJDAABLgAECgkJNwAEAK4ZAA==.Pierogi:BAAALgADCgUJBQAAAA==.Piety:BAAALgAECgYJCQAAAA==.Pinjo:BAAALgAECgcJDwAAAA==.',
Po='Polarnomad:BAAALgADCgYJCwABLgAECggJFwAeABkTAA==.Polarr:BAABLgAECn8XAAIeAAgJGRNkzwBNAQAeAAgJGRNkzwBNAQAAAA==.Polydrake:BAAALgAFFAEJAQAAAA==.Pook:BAAALgAECgcJDgABLgAFFAQJEQAmADkeAA==.Popsicles:BAAALgAECgUJCAAAAA==.',
Pr='Pride:BAAALgADCgIJAgABLgAECggJGAAaAIUgAA==.Prismatic:BAAALgAECgMJBAAAAA==.Probablyblue:BAAALgAECgYJCQAAAA==.Proofy:BAAALgAECgcJDwAAAA==.Prowl:BAAALgADCgYJBgABLgAECgYJCwAIAAAAAA==.',
Ps='Psyop:BAAALgAECgEJAQABLgAECggJIQAEABkfAA==.',
Pu='Punchkick:BAAALgAECgEJAgAAAA==.Punchup:BAABLgAECn8YAAIUAAcJAgqrQgDxAAAUAAcJAgqrQgDxAAAAAA==.',
Py='Pythie:BAAALgAECgEJAQAAAA==.',
Qi='Qing:BAAALgAECgIJAgAAAA==.',
Ra='Rabit:BAAALgAECgUJDgAAAA==.Ramsey:BAAALgADCgEJAQAAAA==.Rastputin:BAAALgAECgkJDgAAAA==.',
Re='Rebrex:BAAALgADCgcJFQAAAA==.Redpyro:BAAALgADCgcJDwAAAA==.Retrïbutor:BAAALgAECgYJCgAAAA==.',
Rf='Rf:BAAALgAECgEJAQAAAA==.',
Rh='Rhodraco:BAABLgAECn8tAAMkAAgJjAvxEQDmAAAjAAcJGwtAQwAZAQAkAAYJUQvxEQDmAAAAAA==.',
Ri='Rikku:BAAALgAECgYJCQAAAA==.Rinela:BAABLgAECn8fAAIMAAgJDhz7GQA2AgAMAAgJDhz7GQA2AgAAAA==.Riotdrill:BAAALgADCgYJBwAAAA==.',
Rj='Rj:BAABLgAECn8uAAIKAAkJHiPMAwCCAwAKAAkJHiPMAwCCAwAAAA==.',
Ro='Robari:BAAALgAECggJEAAAAA==.Robi:BAAALgADCgEJAQABLgAECgkJKgABACkhAA==.Rolandrex:BAAALgAECgEJAQAAAA==.Romulusinc:BAAALgADCgMJBgAAAA==.Rosabee:BAABLgAECn8tAAIEAAkJBxHDHQDTAQAEAAkJBxHDHQDTAQAAAA==.Rouen:BAAALgAECgcJBwABLgAECgkJMwADAJwbAA==.',
Rp='Rp:BAAALgAECgMJAwAAAA==.',
Rq='Rq:BAAALgADCgYJBgAAAA==.',
Rt='Rtfreshness:BAAALgAECgYJBgAAAA==.',
Ru='Runswithheal:BAAALgAECgQJBQAAAA==.',
Ry='Ryyukken:BAAALgAECgYJCQAAAA==.',
['Rà']='Ràndòm:BAAALgADCgIJAgABLgAFFAgJHgAeAIEdAA==.Ràwrshåk:BAAALgAECgEJAQAAAA==.',
['Rá']='Rándom:BAABLgAFFH8GAAIKAAMJ8ApfRgCYAAAKAAMJ8ApfRgCYAAABLgAFFAgJHgAeAIEdAA==.',
['Ró']='Rónin:BAABLgAFFH8GAAIHAAMJVwoeCwCVAAAHAAMJVwoeCwCVAAAAAA==.',
Sa='Sago:BAAALgAECgMJBAAAAA==.Salyveir:BAAALgAECgIJAgAAAA==.Sanzen:BAABLgAECn8ZAAMUAAYJsRvIIgDAAQAUAAYJsRvIIgDAAQAmAAMJsgcVWQBqAAAAAA==.Sarentu:BAAALgAECgQJBAABLgAECggJHwAMAA4cAA==.Sauce:BAABLgAECn9DAAImAAkJoB8CBwAsAwAmAAkJoB8CBwAsAwAAAA==.',
Sc='Scrubz:BAABLgAECn8aAAInAAkJixrVBwA2AgAnAAkJixrVBwA2AgAAAA==.',
Se='Sekcypants:BAAALgADCgcJBwAAAA==.Senile:BAABLgAECn8yAAIgAAgJRB7TAQBqAgAgAAgJRB7TAQBqAgAAAA==.Seydori:BAAALgADCgUJDAAAAA==.',
Sh='Shadydice:BAAALgADCgYJBgABLgAECgkJJgALAIkUAA==.Shadylid:BAABLgAECn8mAAMLAAkJiRTDOgDYAQALAAkJiRTDOgDYAQAHAAMJVQlQJgBqAAAAAA==.Shadówglider:BAABLgAECn8cAAILAAYJwgpvoADeAAALAAYJwgpvoADeAAAAAA==.Shaelia:BAAALgAECgYJDQAAAA==.Shale:BAABLgAECn8YAAILAAkJziA0PwDIAQALAAkJziA0PwDIAQAAAA==.Shallen:BAAALgAECgEJAQAAAA==.Shamallaman:BAAALgAECgEJAQABLgAFFAEJAQAIAAAAAA==.Shameless:BAAALgAFFAIJAgAAAA==.Sharkina:BAAALgADCgUJBQAAAA==.Sharkweek:BAAALgAECgQJBQAAAA==.Sheetar:BAAALgAECgUJBQABLgAECgkJNQAWAMUTAA==.Sheyoni:BAAALgAECgUJDAAAAA==.Shortbusava:BAAALgADCgcJBwAAAA==.Shreck:BAAALgAECgQJBgAAAA==.',
Si='Silentbob:BAAALgAECgEJAQAAAA==.Sinfulness:BAAALgAECgUJBwAAAA==.',
Sk='Skean:BAAALgAECggJDAAAAA==.Skikette:BAAALgAECgYJDwAAAA==.Skinrot:BAACLgAFFH8JAAIKAAMJKwebSwCJAAAKAAMJKwebSwCJAAAuAAQKfzkAAgoACQkSELUxANcBAAoACQkSELUxANcBAAAA.',
Sl='Slysniper:BAAALgADCgQJBgAAAA==.',
Sm='Smig:BAAALgAECgEJBAAAAA==.',
So='Soeki:BAABLgAECn8yAAIOAAgJvhUDCADLAQAOAAgJvhUDCADLAQAAAA==.Solux:BAABLgAFFH8OAAMCAAUJbRwxBQAyAQACAAQJNxoxBQAyAQAZAAEJwgE5RgA/AAABLgAFFAYJEQAQACgSAA==.Soullove:BAABLgAECn9aAAIOAAkJ7RrTAgB7AgAOAAkJ7RrTAgB7AgAAAA==.Soullovez:BAABLgAECn8qAAMMAAgJVw6xNQA8AQAMAAcJhhCxNQA8AQAKAAcJhQoFYQAQAQABLgAECgkJWgAOAO0aAA==.Soulshocks:BAABLgAECn87AAIbAAgJrBKiLACOAQAbAAgJrBKiLACOAQABLgAECgkJWgAOAO0aAA==.Soulviver:BAABLgAECn9LAAIEAAkJ7BVWEABiAgAEAAkJ7BVWEABiAgAAAA==.',
Sp='Sparkelly:BAAALgADCgEJAQAAAA==.Spicytuna:BAAALgAECgYJCQAAAA==.Spliffy:BAAALgADCgYJBgAAAA==.Spurey:BAACLgAFFH8SAAIeAAUJIQ6UYwAlAQAeAAUJIQ6UYwAlAQAuAAQKfy8AAx8ACQn6HjoDAEUCAB8ACAk1GjoDAEUCAB4ACQnIGUBlALABAAAA.Spurylock:BAAALgADCggJDQABLgAFFAUJEgAeACEOAA==.',
St='Starstreak:BAAALgAECgYJBgABLgAECgkJOwAeACEVAA==.Stimer:BAACLgAFFH8NAAIVAAUJ1iASEAB/AQAVAAUJ1iASEAB/AQAuAAQKf0EAAxUACQmqJfAAAHsDABUACQmlJfAAAHsDACUACAkLHXoQAOcBAAAA.Stuipd:BAAALgADCgYJCQAAAA==.',
Su='Sublimedeath:BAABLgAECn8UAAIaAAUJ9RRwJAAbAQAaAAUJ9RRwJAAbAQAAAA==.Sublimelife:BAAALgAECgEJAQAAAA==.Sukboytony:BAAALgADCgYJBgAAAA==.Sultanofswat:BAAALgADCgcJBwAAAA==.Sunnysideup:BAAALgAECgUJBQAAAA==.',
Sv='Svetlana:BAAALgAECgYJEQAAAA==.',
Sw='Swan:BAACLgAFFH8IAAIeAAMJ+QcLjwC8AAAeAAMJ+QcLjwC8AAAuAAQKfxYAAx4ABwk5EIGhAJQBAB4ABwk5EIGhAJQBACAAAwkHBE0MAGkAAAEuAAUUBAkQACEADg8A.Swolegoose:BAAALgADCgEJAQAAAA==.Swordboardal:BAACLgAFFH8ZAAIaAAQJHxMTFQDxAAAaAAQJHxMTFQDxAAAuAAQKfxsAAxoACQm8F9wNAAoCABoACQm8F9wNAAoCACUABQk4A3suAIIAAAAA.',
Sy='Sybius:BAAALgAECgEJAgAAAA==.Symptom:BAAALgAECgEJAQAAAA==.Syncophat:BAAALgAECgQJBAAAAA==.',
['Sé']='Séphórâ:BAAALgADCgMJBAAAAA==.',
Ta='Tachia:BAAALgAECgYJBgAAAA==.Tad:BAAALgAECgMJBwAAAA==.Taint:BAAALgADCgQJBgAAAA==.Takara:BAAALgADCgEJAQABLgAECggJHAAJALMaAA==.Takia:BAABLgAECn8mAAMWAAYJrgTbswDXAAAWAAYJrgTbswDXAAANAAMJwACKQwAhAAAAAA==.Talanzen:BAACLgAFFH8LAAIeAAQJBBonTQBMAQAeAAQJBBonTQBMAQAuAAQKfygAAh4ACQnOH78kAIcCAB4ACQnOH78kAIcCAAAA.Talonia:BAAALgADCgEJAQABLgAECgMJBAAIAAAAAA==.Tanakiko:BAAALgADCgUJCQAAAA==.Tarrzok:BAAALgADCgcJBwABLgAECgkJJgALAIkUAA==.',
Te='Teacup:BAAALgAECgUJBgABLgAECgkJJAAYAIYeAA==.Tellanji:BAAALgAECgQJBgAAAA==.',
Th='Theowyn:BAAALgADCgEJAQAAAA==.Thormarian:BAAALgADCgUJBwAAAA==.Thrakara:BAACLgAFFH8hAAImAAcJOhJCFADUAQAmAAcJOhJCFADUAQAuAAQKfzsAAiYACQljHTEYAFECACYACQljHTEYAFECAAAA.Thunderhorns:BAABLgAECn8tAAINAAgJpwnTEwAfAQANAAgJpwnTEwAfAQAAAA==.Thundrall:BAABLgAECn8dAAIWAAYJ4gGC4QCCAAAWAAYJ4gGC4QCCAAAAAA==.',
Ti='Tinionron:BAAALgAECgMJAwAAAA==.',
To='Toaster:BAAALgADCgQJBAABLgAFFAYJEwAZAP0VAA==.Toothléss:BAAALgADCgIJAgAAAA==.Toria:BAAALgAECgUJBgAAAA==.Torlania:BAAALgADCgYJBgAAAA==.',
Tr='Trayleen:BAAALgAECgMJBAAAAA==.Treeåj:BAABLgAECn8tAAMMAAgJnw+fLwBcAQAMAAgJnw+fLwBcAQAKAAYJiwVDkwCpAAAAAA==.Trilina:BAAALgADCgkJCAAAAA==.Truths:BAACLgAFFH8lAAMVAAcJnxnFBgDyAQAVAAcJnxnFBgDyAQAlAAEJcwA7RwAtAAAuAAQKfyQAAhUACAkJJYIIACMDABUACAkJJYIIACMDAAAA.Trystrom:BAAALgAECgIJAgAAAA==.',
Ts='Tsuo:BAACLgAFFH8WAAInAAcJqR1aAgAbAgAnAAcJqR1aAgAbAgAuAAQKfzoAAicACQmWJeYAAF4DACcACQmWJeYAAF4DAAAA.',
Tu='Tuhãn:BAAALgAECgEJAQAAAA==.',
Tw='Twixxed:BAAALgADCgYJCAABLgAECggJGgARANMdAA==.',
Tx='Txjustice:BAAALgADCgUJDwAAAA==.',
Ty='Tymptriss:BAABLgAECn8mAAIOAAYJwwsqGgDPAAAOAAYJwwsqGgDPAAAAAA==.Tyrick:BAAALgAECgkJEAAAAA==.Tywen:BAAALgADCgEJAQAAAA==.',
Uh='Uhogpaladin:BAAALgADCgEJAQAAAA==.',
Um='Umbrage:BAACLgAFFH8RAAMQAAYJKBIDWwANAQAQAAUJUw4DWwANAQAOAAIJrRpmEwCcAAAuAAQKfysABA4ACQkTH/oIADECABAACQkXHKgjAE8CAA4ABwnpHfoIADECAA8AAQmWHSooAFEAAAAA.',
Un='Unholyblade:BAAALgADCgYJCgAAAA==.',
Ur='Urethrafrkln:BAAALgAECgYJCQAAAA==.',
Va='Vache:BAAALgADCgkJFgAAAA==.Valartha:BAABLgAECn8fAAIMAAYJ+BjNLABuAQAMAAYJ+BjNLABuAQAAAA==.Var:BAAALgAECgEJAQAAAA==.Variol:BAABLgAECn8bAAIEAAgJgA3LLQBaAQAEAAgJgA3LLQBaAQAAAA==.Vaztek:BAAALgADCgMJAwAAAA==.',
Ve='Vecna:BAAALgAECgYJEAAAAA==.Vellarya:BAAALgADCgYJBgABLgAECgkJHgAcAG4hAA==.Vellmora:BAAALgAECgEJAQAAAA==.Velsea:BAAALgAECgMJBwAAAA==.Velstadt:BAABLgAECn89AAIUAAkJVyK9AwAgAwAUAAkJVyK9AwAgAwAAAA==.Venhance:BAABLgAECn8gAAMbAAgJNxetKACmAQAbAAgJNxetKACmAQAcAAEJTBB11QAvAAAAAA==.Venotu:BAABLgAECn8xAAICAAkJPR41BgCBAgACAAkJPR41BgCBAgAAAA==.Vermilion:BAABLgAECn8bAAILAAYJwwhmrwDEAAALAAYJwwhmrwDEAAAAAA==.Veronor:BAAALgAECgQJBQABLgAECgkJPQAUAFciAA==.Verso:BAAALgADCgcJEwAAAA==.',
Vh='Vholatile:BAAALgAECgYJEAAAAA==.',
Vi='Vinculum:BAAALgADCgIJAgAAAA==.Viviel:BAAALgAECgkJNgAAAQ==.',
Vo='Voidherron:BAAALgAECgYJCwAAAA==.Voidobscur:BAAALgADCgUJBQAAAA==.Voidwapa:BAAALgAECgQJCAAAAA==.Vonzilla:BAACLgAFFH8GAAIDAAQJUwdgJADNAAADAAQJUwdgJADNAAAuAAQKfzIAAgMACQmtG34MAIkCAAMACQmtG34MAIkCAAAA.Voodoomama:BAAALgAECgEJAQAAAA==.Vorthael:BAABLgAECn8wAAIRAAcJmAchwgD4AAARAAcJmAchwgD4AAAAAA==.Voxen:BAAALgADCgQJBAAAAA==.',
Vy='Vynirel:BAAALgAECgEJAQAAAA==.',
['Vö']='Vöid:BAAALgADCgcJBwAAAA==.',
Wa='Waarlow:BAAALgADCgEJAQAAAA==.Warlockbot:BAAALgAFFAEJAwAAAA==.Warmongral:BAABLgAECn9DAAIBAAkJyBqvIQB+AgABAAkJyBqvIQB+AgAAAA==.Waterboot:BAAALgAECgYJDwAAAA==.Wattheyneed:BAAALgADCgUJBQAAAA==.',
We='Wendi:BAABLgAECn8mAAIOAAcJeQ1mFAAGAQAOAAcJeQ1mFAAGAQAAAA==.',
Wh='Wheelchair:BAAALgADCgUJBQABLgAFFAIJAgAIAAAAAA==.Whipx:BAAALgADCgIJAgAAAA==.',
Wi='Wingsaber:BAABLgAECn89AAIBAAkJAxWLTgDaAQABAAkJAxWLTgDaAQAAAA==.Wisename:BAAALgAECgMJBgAAAA==.Withher:BAAALgADCgkJEAAAAA==.',
Wo='Wolph:BAAALgAECgUJBQAAAA==.Wombo:BAABLgAECn85AAIXAAkJ8yRnAABlAwAXAAkJ8yRnAABlAwAAAA==.Woolala:BAAALgAECgcJCAABLgAECgkJPgABAO4jAA==.',
Wr='Wrathran:BAABLgAECn8YAAIWAAkJyxFaOwDuAQAWAAkJyxFaOwDuAQAAAA==.',
Wu='Wut:BAAALgAECgIJAgABLgAECgkJQwAmAKAfAA==.',
Xa='Xahiri:BAAALgAECgEJAQAAAA==.',
Xl='Xlia:BAAALgAECgMJAwAAAA==.',
Ya='Yaeyo:BAAALgAECgcJDQAAAA==.Yazmat:BAACLgAFFH8HAAIZAAMJNBC8MwCbAAAZAAMJNBC8MwCbAAAuAAQKfykAAhkACQklHHcNALkCABkACQklHHcNALkCAAAA.Yazmyn:BAAALgAECggJDgAAAA==.',
Ye='Yeah:BAAALgADCgkJCQABLgAECgkJQwAmAKAfAA==.Yerehmi:BAAALgAECgMJBQAAAA==.',
Ym='Ymma:BAAALgADCgcJBwAAAA==.',
Yu='Yuny:BAABLgAECn8aAAImAAgJuAeJOQACAQAmAAgJuAeJOQACAQAAAA==.',
Yv='Yvendria:BAABLgAECn82AAQPAAkJkB4MAgC/AgAPAAkJkB4MAgC/AgAQAAUJpQ+oogD6AAAOAAEJAAAnagA+AAAAAA==.',
Za='Zacnafeen:BAAALgAECgMJAwAAAA==.Zaelessa:BAAALgAECgMJCQABLgAECgkJNgAIAAAAAQ==.Zaier:BAABLgAECn9SAAQZAAkJwCQBAwBFAwAZAAkJwCQBAwBFAwABAAQJKBLL2QDjAAACAAEJxgOuXAAUAAAAAA==.Zaraelila:BAAALgADCgMJAwAAAA==.Zartart:BAAALgAECgkJBgAAAA==.',
Ze='Zeltan:BAABLgAECn8qAAMZAAgJ9hz2LwDCAQAZAAYJGxz2LwDCAQABAAgJsxGuawCUAQAAAA==.Zeropriest:BAAALgADCgUJBQAAAA==.',
Zh='Zhundrenga:BAABLgAECn8mAAISAAYJUAjjOQCpAAASAAYJUAjjOQCpAAAAAA==.',
Zi='Zinik:BAAALgADCgEJAQAAAA==.',
Zo='Zolt:BAAALgAECgcJDQAAAA==.Zoma:BAAALgADCgEJAQAAAA==.',
Zu='Zugzeal:BAAALgADCgYJBAAAAA==.Zuldraaxx:BAAALgADCgkJCQAAAA==.Zurge:BAAALgAECgEJAQAAAA==.',
['Zï']='Zïggy:BAAALgAECgYJBwAAAA==.',
['År']='Åres:BAAALgADCgIJAwAAAA==.',
['Ün']='Ünc:BAAALgAECgMJAwAAAA==.',
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
