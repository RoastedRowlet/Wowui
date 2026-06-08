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
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abogato:BAAALgAECgQJBAAAAA==.',
Ae='Aedra:BAAALgADCgcJEgAAAA==.Aeowyyn:BAAALgAECggJEwAAAA==.',
Af='Af:BAAALgADCgUJBQAAAA==.',
Ah='Ahnir:BAABLgAECn8aAAIBAAkJaw87ZgCYAQABAAkJaw87ZgCYAQAAAA==.Ahnkhano:BAABLgAECn8dAAICAAgJ8RFiEgCjAQACAAgJ8RFiEgCjAQAAAA==.',
Ai='Aidenarren:BAAALgADCgkJEAAAAA==.Ainge:BAAALgADCgUJBQAAAA==.Aiom:BAAALgADCgMJAwAAAA==.',
Ak='Akashaa:BAAALgADCgEJAQAAAA==.Akbartheiiv:BAACLgAFFH8YAAIDAAcJ7xi4AQACAgADAAcJ7xi4AQACAgAuAAQKfzMAAgMACQl7IwQEABgDAAMACQl7IwQEABgDAAAA.',
Al='Alexanderson:BAAALgADCgEJAQAAAA==.Alhamdulilah:BAAALgADCgEJAQAAAA==.Alivour:BAAALgADCgkJCQAAAA==.Allero:BAAALgAECgMJAwAAAA==.Allistrana:BAABLgAECn8iAAIEAAkJBRwzEwBGAgAEAAkJBRwzEwBGAgAAAA==.Aluvia:BAAALgAECgIJBAAAAA==.',
Am='Amairis:BAABLgAECn8XAAMFAAYJlxMNLgBcAQAFAAYJlxMNLgBcAQADAAMJaAkzYwB8AAAAAA==.Ambiorix:BAAALgADCgEJAgAAAA==.',
An='Anari:BAAALgADCgUJBQAAAA==.Angelsin:BAAALgADCgkJGwAAAA==.Animorph:BAAALgADCgcJJQAAAA==.Annestasia:BAAALgAECgcJCAAAAA==.Anrion:BAABLgAECn8uAAMGAAkJHyMTBgDMAgAGAAkJHyMTBgDMAgAHAAcJNxweCQDNAQAAAA==.Anteater:BAAALgADCgEJAQABLgAECgUJDgAIAAAAAA==.',
Ap='Aph:BAAALgAECgcJDgAAAA==.Apolló:BAAALgAECgkJDwAAAA==.',
Ar='Araiana:BAAALgAECgEJAQAAAA==.Arayia:BAABLgAECn8cAAMJAAgJsxr1CAAoAgAJAAgJsxr1CAAoAgAKAAUJkA1wcgDUAAAAAA==.Arelian:BAABLgAECn8ZAAMHAAkJ2BJ/EAA1AQAHAAYJmhZ/EAA1AQALAAkJbwt7iwD7AAAAAA==.Aristia:BAABLgAECn8vAAMKAAgJ1iNYDQDoAgAKAAgJ1iNYDQDoAgAMAAEJzwwbigAtAAABLgAECgIJAgAIAAAAAA==.Artaic:BAAALgAECgUJDgAAAA==.Artemysia:BAAALgADCgEJAQAAAA==.',
At='Ataboom:BAAALgADCgEJAQAAAA==.Ataliya:BAAALgAECgQJCgAAAA==.',
Au='Auranar:BAABLgAECn8lAAINAAgJEAcmFQAGAQANAAgJEAcmFQAGAQAAAA==.Aurilia:BAABLgAECn8gAAIEAAYJZB+xFgANAgAEAAYJZB+xFgANAgAAAA==.',
Av='Avanicus:BAABLgAECn8oAAQOAAkJhQquFQDtAAAPAAcJUAkRFAAdAQAOAAcJbwmuFQDtAAAQAAQJqANPDQFQAAAAAA==.Aven:BAABLgAECn8kAAMRAAgJkRK4WAC0AQARAAgJchK4WAC0AQASAAUJrQe4PwCGAAAAAA==.',
Ax='Axiomronin:BAABLgAECn8qAAMTAAkJYCRMBQDmAgATAAgJ9yRMBQDmAgAUAAgJJyK3DgCSAgAAAA==.',
Ay='Ayroon:BAAALgAECgQJBQAAAA==.',
Az='Azulien:BAABLgAECn8nAAMFAAgJiAMLPQALAQAFAAgJiAMLPQALAQAEAAEJSwAVegAMAAAAAA==.Azuriel:BAAALgAECgIJAgAAAA==.',
Ba='Baltuk:BAABLgAECn8aAAIRAAgJ0x3YJgCgAgARAAgJ0x3YJgCgAgAAAA==.Bananafarts:BAAALgADCgMJAwAAAA==.Banderblitz:BAACLgAFFH8HAAIVAAIJrhM+PACYAAAVAAIJrhM+PACYAAAuAAQKfzUAAhUACQlIIcEKALICABUACQlIIcEKALICAAAA.Baobei:BAAALgADCgcJBwAAAA==.Bar:BAACLgAFFH8HAAMDAAQJigbuEQCOAAADAAQJigbuEQCOAAAEAAMJlRETEgBUAAAuAAQKfxsAAgMACAlxGicVAEMCAAMACAlxGicVAEMCAAAA.Barunnar:BAAALgADCgEJAQAAAA==.',
Be='Bearlyshady:BAAALgADCgcJCwABLgAECgkJJgALAIkUAA==.Bellatrixie:BAAALgAECgcJDQAAAA==.Benafflock:BAABLgAECn8eAAQPAAgJYwpXEABJAQAPAAgJRApXEABJAQAQAAQJYwSY4QCXAAAOAAEJDw3/PQAsAAABLgAECgcJEgAIAAAAAA==.Beriadhwen:BAAALgAECgYJBwAAAA==.Bermy:BAABLgAECn8aAAIOAAkJGxEcEwANAQAOAAkJGxEcEwANAQAAAA==.Bewildert:BAAALgADCgIJAgAAAA==.',
Bh='Bhawkwco:BAAALgADCgEJAQAAAA==.',
Bl='Blackhawkdk:BAABLgAECn8uAAIRAAkJshuiJQBlAgARAAkJshuiJQBlAgAAAA==.Blende:BAABLgAECn8qAAIBAAkJKSHPDgDmAgABAAkJKSHPDgDmAgAAAA==.Bloodshadow:BAABLgAECn80AAIWAAkJxRPfNgD3AQAWAAkJxRPfNgD3AQAAAA==.Blueberrae:BAAALgADCgEJAQAAAA==.Bluemaster:BAAALgADCgYJBgAAAA==.Bluish:BAAALgAECgEJAQAAAA==.',
Bo='Boidohanta:BAAALgADCgUJBQAAAA==.',
Br='Braveharth:BAABLgAECn8XAAIBAAgJPQRoygDuAAABAAgJPQRoygDuAAAAAA==.Braxus:BAAALgAECgMJBAAAAA==.Breakcooloz:BAACLgAFFH8TAAIXAAYJ/R+CAQC4AQAXAAYJ/R+CAQC4AQAuAAQKfyIAAhcACAmoIyIBADQDABcACAmoIyIBADQDAAEuAAUUCAkgABEAiCEA.Brooce:BAABLgAECn8yAAIBAAkJyB+MFQC4AgABAAkJyB+MFQC4AgAAAA==.Broom:BAAALgADCgkJHQABLgAECgkJSAANAD8hAA==.Brylise:BAAALgADCgIJAgAAAA==.',
Bu='Burstinurass:BAACLgAFFH8gAAIRAAgJiCHQBAC1AgARAAgJiCHQBAC1AgAuAAQKfxgAAhEACAm+JYMXALECABEACAm+JYMXALECAAAA.',
Ca='Caladorion:BAAALgAECgIJAgAAAA==.Candyjar:BAAALgADCgcJDAAAAA==.Cantmissyou:BAAALgAECgEJBgAAAA==.Capidk:BAAALgAFFAEJAQAAAA==.Carafe:BAAALgADCgEJAQABLgAECgkJJAAYAIYeAA==.Carbonight:BAAALgADCgEJAQAAAA==.Carlos:BAAALgAECgUJDwABLgAECggJJQABAHgiAA==.Caspianne:BAAALgAECgQJBgAAAA==.',
Cb='Cbrown:BAAALgAECgEJAQAAAA==.',
Ce='Celani:BAACLgAFFH8JAAIEAAMJ9RJeHgCyAAAEAAMJ9RJeHgCyAAAuAAQKfyYAAwQACAnaGdsVABUCAAQACAnaGdsVABUCAAUAAQm6AWpeACQAAAAA.Celintha:BAAALgADCgcJBwAAAA==.Cellyne:BAABLgAECn8nAAMBAAgJ6AcpqAAfAQABAAgJ6AcpqAAfAQAZAAIJJAIchQA2AAAAAA==.Centy:BAAALgAECgYJEgAAAA==.Ceredisam:BAAALgADCgcJBwAAAA==.',
Ch='Chainheal:BAAALgAECgMJAwAAAA==.Chaz:BAAALgAECgcJEQAAAA==.Chedrood:BAAALgADCgMJBwAAAA==.Chelives:BAEBLgAECn8sAAIaAAcJEgNrMgCmAAAaAAcJEgNrMgCmAAAAAA==.Choalmakyahn:BAAALgADCgUJBQAAAA==.Chubrub:BAABLgAECn8aAAMbAAYJHwWcZACoAAAbAAYJHwWcZACoAAAcAAMJLAP/tQBPAAAAAA==.Chìef:BAAALgADCgEJAQAAAA==.',
Ci='Cires:BAAALgAECgEJAgAAAA==.',
Cl='Claud:BAAALgAECgYJBgAAAA==.Cleric:BAAALgADCgMJAwAAAA==.',
Co='Cobaltwolf:BAAALgAECgQJCAAAAA==.Colanasou:BAAALgAECgYJEwAAAA==.Coldbattler:BAABLgAECn8UAAIWAAgJSg9EaQBkAQAWAAgJSg9EaQBkAQAAAA==.Copelongcut:BAAALgADCgMJAQAAAA==.Corrick:BAAALgADCgcJEAAAAA==.',
Cr='Crastosmomma:BAAALgADCgkJCQAAAA==.Crow:BAAALgAECgkJHQAAAQ==.',
Cu='Curavis:BAAALgADCgMJAwAAAA==.',
Cy='Cydric:BAACLgAFFH8FAAIBAAMJaxaAHAC8AAABAAMJaxaAHAC8AAAuAAQKfyIAAgEACAmHI8UMACgDAAEACAmHI8UMACgDAAAA.',
Da='Daarrkstar:BAABLgAECn8mAAMcAAcJ/yT1DQDaAgAcAAcJ/yT1DQDaAgAdAAMJrxB5IQC6AAABLgAECgkJKgABACkhAA==.Daenyra:BAAALgADCgUJBQAAAA==.Dakarai:BAAALgADCggJDgAAAA==.Danek:BAAALgADCggJGQAAAA==.Darkane:BAABLgAFFH8KAAMNAAYJaQ4eHwCaAAAWAAQJ3gmQZAC+AAANAAIJOhUeHwCaAAAAAA==.Darknives:BAAALgAECgEJAwAAAA==.Darocate:BAAALgADCgYJBgAAAA==.Dathanarr:BAAALgAECggJCAAAAA==.',
De='Deadskvll:BAAALgADCgYJBgAAAA==.Deathbot:BAACLgAFFH8bAAISAAUJthirFQAnAQASAAUJthirFQAnAQAuAAQKf0UAAhIACQnXIq4EAOACABIACQnXIq4EAOACAAAA.Demira:BAAALgADCgMJAwAAAA==.Demoray:BAACLgAFFH8KAAINAAUJvBiZCACSAQANAAUJvBiZCACSAQAuAAQKfxQAAg0ABwl0JB0VAIoCAA0ABwl0JB0VAIoCAAAA.Dendrin:BAAALgAECgEJAQAAAA==.Deneese:BAAALgAECgIJAgAAAA==.Derrpy:BAAALgADCgEJAQAAAA==.Desniee:BAABLgAECn8gAAQeAAkJMx91QwBuAgAeAAkJMx91QwBuAgAfAAIJHA3jFAB3AAAgAAEJuxW+DgA/AAAAAA==.Dethrone:BAABLgAECn8aAAQQAAgJhx3JLAAgAgAQAAcJoR/JLAAgAgAOAAYJ5xniIABNAQAPAAEJXBYtLgBCAAAAAA==.',
Di='Digitpro:BAABLgAECn87AAIhAAgJcxB/HgCkAQAhAAgJcxB/HgCkAQAAAA==.Dirtydragon:BAABLgAECn8mAAMiAAgJ0h2WBgCSAgAiAAgJ0h2WBgCSAgAjAAEJhwdmZQArAAAAAA==.Disturbo:BAAALgADCgkJDwAAAA==.Divinedecay:BAABLgAECn8aAAISAAcJsg0+KgD7AAASAAcJsg0+KgD7AAABLgAECgkJRAAWAHQaAA==.',
Do='Dok:BAAALgADCgcJBwAAAA==.Donoraginn:BAAALgADCgkJIgABLgADCgkJQgAIAAAAAA==.Donos:BAAALgADCgkJQgAAAA==.Dontkare:BAAALgADCgcJEQABLgAECgkJKgAaAJ0lAA==.Doomjuele:BAAALgADCgYJBgAAAA==.Dorsai:BAAALgADCgUJBQAAAA==.Dott:BAAALgADCgIJAgABLgAECgkJGgABAGsPAA==.',
Dr='Draaxx:BAAALgADCgIJAgAAAA==.Draazzy:BAAALgADCgkJEgAAAA==.Dracbanti:BAAALgADCgkJEQAAAA==.Dracobelle:BAABLgAECn8jAAMiAAYJ2RviDgDVAQAiAAYJ2RviDgDVAQAjAAMJ+wh1bQCDAAAAAA==.Dragundeez:BAAALgAECggJCQAAAA==.Drark:BAAALgAECgEJAgAAAA==.Drathiel:BAAALgAECgMJAwAAAA==.Draxxien:BAAALgADCgcJBwAAAA==.Drazlowe:BAAALgADCgQJBwAAAA==.Draäx:BAAALgADCgkJEgAAAA==.Dreezee:BAAALgAECgcJEQAAAA==.Drizztknight:BAAALgADCgEJAQAAAA==.Droobear:BAAALgAECgIJAgAAAA==.Drwho:BAABLgAECn8nAAIeAAgJihi/RgABAgAeAAgJihi/RgABAgAAAA==.Dràco:BAAALgADCggJDwAAAA==.Drääx:BAAALgADCggJCAAAAA==.Dräëxx:BAAALgADCgcJDQAAAA==.',
Du='Durimli:BAAALgADCgYJBwAAAA==.',
Dw='Dwayneb:BAAALgAECgkJBwAAAA==.',
['Dî']='Dîxon:BAAALgAFFAMJAwABLgAFFAgJIAARAIghAA==.',
['Dô']='Dôz:BAAALgADCgQJBAAAAA==.',
Ea='Earthernbot:BAABLgAFFH8OAAIeAAQJRwl4ZAAWAQAeAAQJRwl4ZAAWAQAAAA==.Earthspeaker:BAAALgADCgEJAQAAAA==.',
Ei='Eidolon:BAAALgADCgkJEgAAAA==.',
El='Eleram:BAAALgADCgYJBgABLgAECgkJGgABAGsPAA==.Elfadwagon:BAACLgAFFH8ZAAIkAAYJoRg1AQCWAQAkAAYJoRg1AQCWAQAuAAQKfyQAAiQACAlcIa8CAAIDACQACAlcIa8CAAIDAAAA.Eliptical:BAAALgAECgYJEwABLgAECggJGwABAO4eAA==.Elkesey:BAAALgADCgEJAQAAAA==.Elonura:BAAALgADCgYJBgAAAA==.Elunea:BAAALgADCggJCwAAAA==.',
Em='Emishanot:BAAALgAECgEJAQABLgAECgYJEQAIAAAAAA==.',
Ep='Epoch:BAAALgADCgEJAQAAAA==.',
Er='Erangar:BAABLgAECn8eAAIbAAYJiQujVADWAAAbAAYJiQujVADWAAAAAA==.Erdor:BAAALgADCgcJDgAAAA==.Erini:BAAALgADCgkJCQAAAA==.Erred:BAAALgADCgcJBwAAAA==.',
Es='Esmer:BAABLgAECn8tAAIBAAkJJwq8dAB5AQABAAkJJwq8dAB5AQAAAA==.',
Et='Etheman:BAAALgAECgcJDQAAAA==.',
Eu='Euphrasie:BAAALgAECgEJAQABLgAECgkJHgAcAG4hAA==.',
Ev='Eversteal:BAAALgADCgQJBAABLgAECggJKAACAFAbAA==.Evholker:BAABLgAECn8cAAMkAAkJXBC4DAA5AQAkAAgJ6RC4DAA5AQAjAAYJFw6FRwABAQAAAA==.',
Ex='Excuses:BAAALgAECgYJDAABLgAFFAcJJQAVAJ8ZAA==.Executey:BAAALgADCgQJBAAAAA==.Exhumina:BAAALgAECgcJCQAAAA==.',
Fa='Facestealerr:BAAALgAECgYJEwAAAA==.Fallenhullkk:BAAALgADCgYJBgAAAA==.Fangyi:BAAALgADCgYJBgAAAA==.',
Fe='Feetsmell:BAAALgADCgkJEgABLgAECgkJSAANAD8hAA==.Felmufín:BAABLgAECn8cAAIQAAgJQwy7cwBNAQAQAAgJQwy7cwBNAQAAAA==.Felspury:BAAALgAECgEJAQABLgAFFAQJEQAeACEOAA==.Feyrea:BAAALgAECgQJBgAAAA==.',
Fi='Fibula:BAAALgADCgcJBwAAAA==.Fitzfarseer:BAAALgADCgkJCQAAAA==.',
Fl='Flairrick:BAABLgAECn8sAAIVAAgJDCSuBgDsAgAVAAgJDCSuBgDsAgAAAA==.Flars:BAABLgAECn8gAAIYAAgJdxtJBgAzAgAYAAgJdxtJBgAzAgAAAA==.Flatliner:BAACLgAFFH8QAAIZAAYJgwUwGABUAQAZAAYJgwUwGABUAQAuAAQKfzkAAxkACAk1DiM0AK0BABkACAk1DiM0AK0BAAEAAQmlCV9TASoAAAAA.Floracide:BAAALgAECgYJCwABLgAECggJCgAIAAAAAA==.Florence:BAAALgAECggJCgAAAA==.Flyingbot:BAAALgAECgUJBQAAAA==.',
Fo='Foid:BAAALgAECgYJBwAAAA==.Forq:BAAALgADCgcJBwAAAA==.',
Fr='Fran:BAAALgADCgYJBgABLgAECgkJSAANAD8hAA==.Frankzappn:BAAALgAECgQJBAAAAA==.Fray:BAABLgAECn8iAAILAAkJahpdIQBDAgALAAkJahpdIQBDAgAAAA==.Freeguy:BAABLgAECn8mAAILAAkJCxrPHQBXAgALAAkJCxrPHQBXAgAAAA==.Fruitsnacks:BAAALgAECgEJAQABLgAFFAYJDgALAH8YAA==.',
Fu='Fuddicus:BAABLgAECn9IAAMcAAkJjyS3CAAbAwAcAAkJjyS3CAAbAwAbAAEJGRI9gwA9AAAAAA==.Fuddmore:BAAALgAECgYJBwABLgAECgcJDQAIAAAAAA==.Fuddster:BAAALgAECgcJDQAAAA==.',
Ga='Gaddess:BAABLgAECn8lAAIDAAcJ4weKQAAFAQADAAcJ4weKQAAFAQAAAA==.Ganath:BAAALgAECgMJAwAAAA==.Ganymede:BAAALgAECgYJEwAAAA==.Garan:BAAALgADCgQJBAAAAA==.Garnar:BAAALgADCgIJAgAAAA==.',
Ge='Geilamaine:BAABLgAECn8gAAIZAAkJFRxYCAD7AgAZAAkJFRxYCAD7AgAAAA==.',
Gi='Gimpy:BAAALgAECgQJBQAAAA==.',
Gl='Glimagi:BAAALgADCgcJDwAAAA==.Glimdaemon:BAAALgAECgIJAgAAAA==.',
Go='Gonefishing:BAABLgAECn8+AAIBAAkJ7iPzDAD1AgABAAkJ7iPzDAD1AgAAAA==.Gorddownie:BAABLgAECn8fAAIMAAYJuANFXgCOAAAMAAYJuANFXgCOAAAAAA==.',
Gr='Graied:BAAALgAECgYJBgAAAA==.Granuaille:BAAALgAECgIJAgAAAA==.Grellior:BAAALgAECgEJAQAAAA==.Grimjawz:BAAALgAECggJCgAAAA==.Grippysocks:BAACLgAFFH8SAAIZAAUJcRkIGABVAQAZAAUJcRkIGABVAQAuAAQKfzMAAhkACAnKGBIcADQCABkACAnKGBIcADQCAAAA.',
Gu='Gummibear:BAABLgAECn8fAAMlAAcJHRPMHQBjAQAlAAcJHRPMHQBjAQAaAAQJ2ANZNwCNAAAAAA==.',
Ha='Hakar:BAAALgAECgYJCAAAAA==.Hanoa:BAAALgADCgIJAgAAAA==.Harthoon:BAACLgAFFH8gAAIeAAYJwg+RNQCBAQAeAAYJwg+RNQCBAQAuAAQKfzkAAh4ACAnIHkY+ABwCAB4ACAnIHkY+ABwCAAAA.Haruharu:BAAALgAECgMJCwAAAA==.Hawkhogan:BAAALgADCgYJCQAAAA==.Hazdanzul:BAAALgADCgQJBQABLgAECgYJEQAIAAAAAA==.',
He='Hehexxd:BAAALgAECgIJAgAAAA==.Helias:BAAALgADCgkJBgAAAA==.Hemp:BAAALgAECgMJAwAAAA==.Herrondale:BAAALgADCgcJBwAAAA==.Hey:BAAALgADCgkJIwABLgAECgkJQwAmAKAfAA==.',
Hj='Hjukonlikjuj:BAAALgAECgEJAQAAAA==.',
Ho='Holiebelle:BAAALgAECggJCAABLgAECggJIwAiANkbAA==.Hollanov:BAAALgADCgYJBgAAAA==.Honeynoats:BAABLgAECn8qAAIEAAgJfRDgIQCmAQAEAAgJfRDgIQCmAQAAAA==.Honks:BAAALgAECgQJBQAAAA==.Hotdwarf:BAAALgAECggJEgAAAA==.',
Hu='Hubbabubbles:BAAALgAECgEJAQAAAA==.Hullkk:BAACLgAFFH8bAAMlAAYJ8SIrDABvAQAlAAUJxCArDABvAQAVAAQJ8hs8GQA/AQAuAAQKfzcAAxUACAmJJokFAE4DABUACAnOJYkFAE4DACUABwkPJNgFAJsCAAAA.Hundale:BAAALgAECgQJBAAAAA==.Hutchkins:BAABLgAECn8qAAMQAAgJ7hxPLQBYAgAQAAgJ7hxPLQBYAgAPAAEJAAB3RAAAAAAAAA==.Hutchknight:BAAALgAECgUJDAABLgAECggJKgAQAO4cAA==.Hutchyo:BAAALgADCgQJBAABLgAECggJKgAQAO4cAA==.',
Hy='Hydro:BAACLgAFFH8JAAIBAAQJRw0LSQAMAQABAAQJRw0LSQAMAQAuAAQKfzQAAwEACQlGIf4VALUCAAEACQlGIf4VALUCAAIABAk1D1gtAKkAAAAA.Hypovolaemia:BAAALgADCgYJCwAAAA==.',
['Hä']='Häwtz:BAAALgADCgIJAgAAAA==.',
Ia='Iamhealer:BAAALgADCgMJAgAAAA==.',
Il='Illaandra:BAAALgADCgEJAQABLgAECgMJAwAIAAAAAA==.',
Im='Imsanity:BAAALgADCgEJAQAAAA==.',
In='Inari:BAAALgAECgQJBwABLgAECgkJLAAhAE4YAA==.Inseng:BAABLgAECn8pAAMSAAgJjyAAEQDwAQASAAYJyiIAEQDwAQAYAAgJNxcVEABiAQAAAA==.Invasion:BAAALgAECgYJDAAAAA==.',
Ix='Ixy:BAABLgAECn8nAAILAAkJLRqKHwBNAgALAAkJLRqKHwBNAgAAAA==.',
Ja='Jaghas:BAAALgADCgMJBgAAAA==.Jahde:BAABLgAECn86AAIKAAgJSA3SRwBmAQAKAAgJSA3SRwBmAQAAAA==.Jahoda:BAAALgADCgYJBgAAAA==.Jaina:BAAALgAECgQJBQAAAA==.Jamer:BAABLgAECn8lAAIaAAgJzyJgBQC3AgAaAAgJzyJgBQC3AgAAAA==.Jassykins:BAABLgAECn8oAAIWAAgJQxIDRwDAAQAWAAgJQxIDRwDAAQAAAA==.',
Je='Jeewop:BAAALgADCgEJAQAAAA==.Jeongaegdeom:BAAALgADCgcJDgAAAA==.Jessecuster:BAAALgAECgUJBgAAAA==.',
Ji='Jindouyun:BAABLgAFFH8FAAInAAMJ6CCsCwAgAQAnAAMJ6CCsCwAgAQAAAA==.Jinjerr:BAAALgAECgcJEQAAAA==.',
Jo='Joloc:BAABLgAECn8oAAIOAAkJsxQLBgD3AQAOAAkJsxQLBgD3AQAAAA==.Jozay:BAAALgAECgYJDAAAAA==.',
Ju='Juancarlos:BAAALgADCgEJAQAAAA==.',
Ka='Kaidaa:BAAALgAECgQJBAAAAA==.Kaladan:BAAALgAECgUJCwAAAA==.Kalasparkle:BAAALgAECgYJEwAAAA==.Kalrosa:BAABLgAECn8cAAIVAAgJUyNkDQCQAgAVAAgJUyNkDQCQAgABLgAFFAIJBwAVAK4TAA==.Kare:BAABLgAECn8qAAIaAAkJnSXpAgAIAwAaAAkJnSXpAgAIAwAAAA==.Karee:BAABLgAECn8iAAICAAkJ6yThAABRAwACAAkJ6yThAABRAwABLgAECgkJKgAaAJ0lAA==.Kathilnas:BAAALgADCgUJBQABLgAECgYJEQAIAAAAAA==.',
Kc='Kcosfomas:BAAALgADCgIJAgAAAA==.',
Ke='Kebob:BAAALgADCgcJCAAAAA==.Kermodh:BAAALgADCgMJAQAAAA==.Kermodk:BAAALgAECgYJCgAAAA==.Kermodrood:BAABLgAECn8qAAMMAAkJCSMzBQAAAwAMAAkJCCMzBQAAAwAnAAQJRyIlIwAjAQAAAA==.',
Kh='Khanthurs:BAAALgAECgQJBAAAAA==.Kholdbrew:BAAALgAECgYJCwAAAA==.',
Ki='Kicklife:BAAALgAECgEJAQAAAA==.Kiizo:BAABLgAECn8nAAIoAAgJhRZIFwDVAQAoAAgJhRZIFwDVAQAAAA==.Kilnot:BAABLgAECn8UAAIcAAcJ4xZQMgC8AQAcAAcJ4xZQMgC8AQAAAA==.Kinstine:BAABLgAECn8VAAISAAYJ/wFMMgCtAAASAAYJ/wFMMgCtAAAAAA==.',
Kn='Knarwxlves:BAAALgAFFAEJAQAAAA==.',
Ko='Koltara:BAABLgAFFH8OAAILAAYJfxg4IgCMAQALAAYJfxg4IgCMAQAAAA==.Koltaris:BAACLgAFFH8PAAITAAQJTh88GgBCAQATAAQJTh88GgBCAQAuAAQKfyIAAhMACAl2JI4IAKICABMACAl2JI4IAKICAAEuAAUUBgkOAAsAfxgA.Komori:BAAALgAECgQJBAAAAA==.Konshis:BAACLgAFFH8KAAMmAAMJSwwMOwCXAAAmAAMJSwwMOwCXAAAUAAEJqQUhPwA4AAAuAAQKfyQAAiYACQkqFfcnANEBACYACQkqFfcnANEBAAAA.Kookymonster:BAABLgAECn9AAAMQAAkJlSNeBABGAwAQAAgJlSNeBABGAwAOAAcJlh2CBwBPAgAAAA==.Korbyn:BAAALgADCgkJCQAAAA==.Kos:BAACLgAFFH8ZAAMRAAYJGxO9MwCBAQARAAUJGxO9MwCBAQASAAEJAAB2VwAAAAAuAAQKfxcAAxEACAl6H+s0ACMCABEACAl6H+s0ACMCABgAAgmaGXEnAH0AAAAA.',
Ku='Kuragaru:BAACLgAFFH8YAAMoAAYJTh0bDACsAQAoAAYJTh0bDACsAQAXAAIJbwxWBACsAAAuAAQKfzgAAygACAm1JL0IAI8CACgACAm1JL0IAI8CABcACAlqGicFAEMCAAAA.',
Ky='Kyoubouna:BAAALgAECgQJBAAAAA==.Kyoxi:BAAALgADCgEJAQAAAA==.',
La='Laedrea:BAAALgADCgEJAQAAAA==.Larianne:BAAALgAECgcJEgAAAA==.',
Le='Leese:BAABLgAECn8jAAIMAAgJ6wfjPQAJAQAMAAgJ6wfjPQAJAQAAAA==.Leretic:BAAALgAECgYJBgABLgAECggJGwABAO4eAA==.Lerion:BAABLgAECn8bAAIBAAgJ7h4fEgABAwABAAgJ7h4fEgABAwAAAA==.Lester:BAABLgAECn8zAAIDAAkJnBs4DACHAgADAAkJnBs4DACHAgAAAA==.Lethana:BAAALgADCgcJDAAAAA==.Lexysady:BAAALgAECgIJAgAAAA==.',
Li='Liamsun:BAABLgAECn9AAAQmAAkJJhUwHgAUAgAmAAkJJhUwHgAUAgATAAgJShb2GwC9AQAUAAYJuxT4PwAZAQAAAA==.Lidd:BAAALgAECgQJAwAAAA==.Lidrael:BAABLgAECn8+AAQHAAkJDh7ZAwCGAgAHAAkJDh7ZAwCGAgAGAAYJNAX+QgDsAAALAAYJewpXmwDiAAAAAA==.Lidrahl:BAAALgADCgcJDQAAAA==.Liekos:BAAALgAECgMJCAAAAA==.Lightbloom:BAAALgAECgIJBQAAAA==.Lightwing:BAAALgAECgEJAgAAAA==.Liliria:BAABLgAECn88AAIEAAkJdRhfFQAbAgAEAAkJdRhfFQAbAgAAAA==.Lillidân:BAAALgAECgYJEQABLgAFFAIJBQAeABsVAA==.Lingwong:BAAALgAECgcJCQAAAA==.Litebite:BAAALgAECgUJBQAAAA==.Litharelw:BAAALgAECgIJAwAAAA==.Littlefish:BAAALgADCgcJDwAAAA==.',
Lj='Ljaeì:BAABLgAECn8eAAIDAAgJRxmeGgDpAQADAAgJRxmeGgDpAQAAAA==.',
Ll='Lloreth:BAABLgAECn8mAAIKAAkJGQt8QQCCAQAKAAkJGQt8QQCCAQAAAA==.',
Ln='Lnpoop:BAAALgAECggJEwAAAA==.',
Lo='Locknload:BAAALgADCgQJBAAAAA==.Lockwood:BAABLgAECn8jAAIoAAkJvg8AGADOAQAoAAkJvg8AGADOAQAAAA==.Lominar:BAAALgADCgcJBwAAAA==.Lorelei:BAABLgAECn8sAAIWAAcJdQ47bgBYAQAWAAcJdQ47bgBYAQAAAA==.Lorrellia:BAABLgAECn8aAAIeAAkJzgRhlABKAQAeAAkJzgRhlABKAQAAAA==.Loway:BAAALgADCgkJGwABLgAECgkJSAANAD8hAA==.',
Lu='Luc:BAAALgADCgkJEgABLgAECgkJQwAmAKAfAA==.Lucariõ:BAACLgAFFH8YAAIEAAcJ7RQlBQDzAQAEAAcJ7RQlBQDzAQAuAAQKfxYAAgQACAkXHpMNAH8CAAQACAkXHpMNAH8CAAAA.Lumina:BAABLgAECn8jAAICAAcJCR5sCwACAgACAAcJCR5sCwACAgAAAA==.Lunaría:BAAALgADCgUJBgAAAA==.Lustydragon:BAAALgADCgEJAQAAAA==.',
Ly='Lyllies:BAAALgAECgIJAgAAAA==.Lysergia:BAABLgAECn8eAAIcAAkJbiHYCgD9AgAcAAkJbiHYCgD9AgAAAA==.',
['Lì']='Lìght:BAACLgAFFH8YAAIZAAUJ4xbCGABOAQAZAAUJ4xbCGABOAQAuAAQKfyEAAhkABwkWI+8YADMCABkABwkWI+8YADMCAAAA.',
Ma='Madrona:BAABLgAECn8WAAIeAAgJkQ++bQCZAQAeAAgJkQ++bQCZAQAAAA==.Magnumrex:BAAALgADCgcJDAAAAA==.Mahoney:BAAALgAECgUJBQAAAA==.Majestynihil:BAAALgADCggJCAAAAA==.Makkazul:BAABLgAECn8gAAMRAAgJnBdxWAC0AQARAAgJfRdxWAC0AQAYAAUJ3hUNGgDvAAAAAA==.Maladia:BAAALgADCgkJCQAAAA==.Management:BAAALgADCgQJBAAAAA==.Mangler:BAABLgAECn8cAAIbAAgJYAU6UADmAAAbAAgJYAU6UADmAAAAAA==.Maris:BAAALgADCgkJEgAAAA==.Marrad:BAAALgAECgQJBAAAAA==.Marrok:BAAALgAECgcJBwAAAA==.Marunji:BAAALgAECgYJEQAAAA==.Matcauthon:BAAALgAECgYJCgAAAA==.Matrim:BAAALgAECgQJBwAAAA==.Mattdæmon:BAABLgAECn8rAAQGAAkJxQ7PGgCXAQAGAAkJxQ7PGgCXAQAHAAQJEwkbIwB1AAALAAIJpwLF2AA+AAAAAA==.Mattmattmatt:BAAALgADCgEJAQAAAA==.Mazzak:BAAALgADCgUJDgAAAA==.',
Me='Meanit:BAAALgAECgQJBgAAAA==.Meekogaia:BAABLgAECn89AAIcAAkJRiF1BwAuAwAcAAkJRiF1BwAuAwAAAA==.Meekosan:BAAALgAECgQJBgAAAA==.Melestaris:BAAALgADCgYJBgAAAA==.',
Mi='Mihlenna:BAAALgADCgcJBwAAAA==.Millerowntoo:BAAALgAFFAIJBAABLgAFFAMJCwAWAP8mAA==.Mimzy:BAAALgAECgEJAgAAAA==.Minarmo:BAAALgADCgEJAQAAAA==.Mingzi:BAAALgAECggJDwAAAA==.Missanabie:BAAALgADCgcJBwAAAA==.Missymeow:BAAALgADCgYJDAAAAA==.Mital:BAAALgADCgEJAQAAAA==.Mizu:BAEALgAECgEJAgABLgAFFAUJBQAjAIoFAA==.',
Mm='Mmbear:BAAALgAECgEJAQABLgAFFAYJJAABAAgYAA==.',
Mo='Mojeen:BAAALgADCgIJAgAAAA==.Monkoko:BAAALgADCgEJAgAAAA==.Montkriege:BAABLgAECn8UAAUKAAYJdQs+aADyAAAKAAYJdQs+aADyAAAMAAUJpwLTZACOAAAJAAIJoxJgKgB1AAAnAAEJJxpjLABGAAAAAA==.Moonsocks:BAAALgAECgUJBQABLgAFFAUJEgAZAHEZAA==.Morpheus:BAAALgADCggJCAAAAA==.Mourium:BAAALgAECgMJAwAAAA==.Moxxie:BAABLgAECn8WAAMMAAcJMxZ0NgAtAQAMAAYJsBV0NgAtAQAJAAEJwBhYQQBKAAAAAA==.',
Mu='Mufín:BAAALgAECgYJCQAAAA==.Murfie:BAABLgAECn8aAAMDAAkJVRYzIwC+AQADAAkJVRYzIwC+AQAEAAQJWgyDWQDOAAAAAA==.Murica:BAAALgADCgEJAQABLgAECgkJSAANAD8hAA==.',
My='Mythiccbops:BAAALgAECgMJAwABLgAECgkJNwAEAK4ZAA==.Mythosrex:BAAALgAECgcJBgAAAA==.',
['Mâ']='Mâjôr:BAAALgADCgUJBQAAAA==.',
['Mì']='Mìr:BAACLgAFFH8SAAILAAUJEBR1QQATAQALAAUJEBR1QQATAQAuAAQKfzIAAwsACAldISIdAFsCAAsACAldISIdAFsCAAYABgn7EB02AC8BAAAA.',
['Mó']='Mónkass:BAAALgAECgEJAQAAAA==.',
Na='Naitho:BAAALgAECgYJBgAAAA==.Nakedfeet:BAAALgADCgEJAQABLgAFFAUJEgAZAHEZAA==.Narena:BAAALgADCgYJBgAAAA==.Nashira:BAABLgAECn8mAAIcAAkJRgvPSgB2AQAcAAkJRgvPSgB2AQAAAA==.Nashness:BAACLgAFFH8OAAMRAAQJGR6nQQBfAQARAAQJGR6nQQBfAQAYAAIJOQdBHAB9AAAuAAQKfzIAAxEACQkOIwcQAB0DABEACQkOIwcQAB0DABgAAQnhI6crAGAAAAAA.Natharion:BAABLgAECn82AAMPAAkJlBiVAgCTAgAPAAkJhRiVAgCTAgAQAAgJWAjfhQApAQAAAA==.Nazrogul:BAABLgAECn8VAAIRAAYJXwg+sgAeAQARAAYJXwg+sgAeAQAAAA==.',
Ne='Nerfme:BAAALgAECgYJBwAAAA==.Nezar:BAAALgAECggJEgAAAA==.',
Ni='Ninjaxe:BAACLgAFFH8MAAIUAAQJkhAxCAD0AAAUAAQJkhAxCAD0AAAuAAQKfyIAAxQACAnLH94JANoCABQACAnLH94JANoCABMAAQkmCD+VACAAAAEuAAUUBgkKAA0AaQ4A.Ninkharak:BAAALgADCgEJAQAAAA==.Nishal:BAAALgAECgMJBAABLgAECgkJOQAcALcdAA==.Nitazuresh:BAAALgADCgEJAQABLgAECgYJIAAEAGQfAA==.Niterage:BAAALgADCgYJDQAAAA==.',
Nn='Nn:BAABLgAECn8sAAInAAgJWRBPIAA4AQAnAAgJWRBPIAA4AQAAAA==.',
No='Noasmago:BAAALgAECgMJAwABLgAFFAUJFQADADgUAA==.Novachrono:BAAALgADCgEJAQAAAA==.',
Nu='Nu:BAAALgAECgYJDAAAAA==.Nuckinphutz:BAAALgADCgYJCwAAAA==.Nullthor:BAABLgAECn8UAAIdAAYJ7xM5FAB3AQAdAAYJ7xM5FAB3AQAAAA==.Nurfd:BAABLgAECn8UAAIaAAYJcAGLPQBtAAAaAAYJcAGLPQBtAAAAAA==.',
['Nè']='Nègan:BAABLgAECn8+AAMWAAkJORiKMgAHAgAWAAkJORiKMgAHAgANAAgJbwhKEwAdAQAAAA==.',
['Nì']='Nìr:BAABLgAFFH8JAAIGAAUJ2hGoDwATAQAGAAUJ2hGoDwATAQAAAA==.',
['Nó']='Nóva:BAAALgADCgQJBAAAAA==.',
['Nô']='Nôyar:BAAALgAECgQJBQAAAA==.',
Ob='Obamakare:BAAALgAECgYJDQABLgAECgkJKgAaAJ0lAA==.',
Od='Odinrex:BAABLgAECn8zAAIWAAgJfBfvMwACAgAWAAgJfBfvMwACAgAAAA==.',
Og='Ogmattbone:BAAALgADCgMJAQAAAA==.',
Ol='Oldjuel:BAAALgADCgkJCQAAAA==.',
Op='Opuntia:BAABLgAECn8UAAMUAAYJlROgMgAtAQAUAAYJlROgMgAtAQAmAAYJQwwoZADMAAAAAA==.',
Ou='Ouch:BAAALgADCgMJAwAAAA==.Outofarrows:BAABLgAECn9IAAMNAAkJPyGBAQD/AgANAAkJPyGBAQD/AgAhAAEJXwmRLgA4AAAAAA==.',
Ow='Ow:BAAALgADCgEJAQABLgADCgMJAwAIAAAAAA==.Ownown:BAAALgAECgIJAgABLgAFFAMJCwAWAP8mAA==.',
Pa='Palinuttz:BAAALgAECgMJAwAAAA==.Pallypaladin:BAACLgAFFH8kAAIBAAYJCBhIGwCEAQABAAYJCBhIGwCEAQAuAAQKfyEAAgEACQnTH9clAGICAAEACQnTH9clAGICAAAA.Partywolf:BAAALgAECgYJBgAAAA==.Pasteeater:BAAALgAECgQJBAAAAA==.',
Pe='Pernelope:BAABLgAECn8iAAILAAcJ7RvRRADgAQALAAcJ7RvRRADgAQAAAA==.Pernicus:BAAALgAECgEJAgAAAA==.',
Ph='Phatzero:BAABLgAECn9EAAMWAAkJdBqvGwB0AgAWAAkJdBqvGwB0AgANAAIJMgRzNgA6AAAAAA==.Phöenix:BAAALgAECgEJAQAAAA==.',
Pi='Piedra:BAAALgADCgYJDAABLgAECgkJNwAEAK4ZAA==.Pierogi:BAAALgADCgUJBQAAAA==.Piety:BAAALgAECgYJCQAAAA==.Pinjo:BAAALgAECgUJDQAAAA==.',
Po='Polarnomad:BAAALgADCgYJCwABLgAECggJFwAeABkTAA==.Polarr:BAABLgAECn8XAAIeAAgJGRNkzwBNAQAeAAgJGRNkzwBNAQAAAA==.Polydrake:BAAALgAFFAEJAQAAAA==.Pook:BAAALgAECgcJBwABLgAFFAQJDQAmAPwdAA==.Popsicles:BAAALgAECgUJCAAAAA==.',
Pr='Pride:BAAALgADCgIJAgABLgAECggJGAAaAIUgAA==.Prismatic:BAAALgAECgMJBAAAAA==.Probablyblue:BAAALgAECgYJCQAAAA==.Proofy:BAAALgAECgcJDwAAAA==.Prowl:BAAALgADCgYJBgABLgAECgYJCwAIAAAAAA==.',
Ps='Psyop:BAAALgAECgEJAQABLgAECggJGgAEAAUcAA==.',
Pu='Punchkick:BAAALgAECgEJAgAAAA==.Punchup:BAABLgAECn8YAAIUAAcJAgoNQADxAAAUAAcJAgoNQADxAAAAAA==.',
Py='Pythie:BAAALgAECgEJAQAAAA==.',
Ra='Rabit:BAAALgAECgQJCwAAAA==.Ramsey:BAAALgADCgEJAQAAAA==.Rastputin:BAAALgAECgkJDgAAAA==.',
Re='Rebrex:BAAALgADCgcJFQAAAA==.Redpyro:BAAALgADCgcJDwAAAA==.Ren:BAAALgAECgEJAQAAAA==.Retrïbutor:BAAALgAECgYJCgAAAA==.',
Rf='Rf:BAAALgAECgEJAQAAAA==.',
Rh='Rhodraco:BAABLgAECn8pAAMkAAgJjAsbEQDrAAAjAAcJGwspQAAeAQAkAAYJUQsbEQDrAAAAAA==.',
Ri='Rikku:BAAALgAECgYJCQAAAA==.Rinela:BAABLgAECn8fAAIMAAgJDhz7GQA2AgAMAAgJDhz7GQA2AgAAAA==.Riotdrill:BAAALgADCgYJBwAAAA==.',
Rj='Rj:BAABLgAECn8tAAIKAAkJHiOCAwCDAwAKAAkJHiOCAwCDAwAAAA==.',
Ro='Robari:BAAALgAECgYJDAAAAA==.Robi:BAAALgADCgEJAQABLgAECgkJKgABACkhAA==.Rolandrex:BAAALgAECgEJAQAAAA==.Romulusinc:BAAALgADCgMJBgAAAA==.Rosabee:BAABLgAECn8tAAIEAAkJBxGFHADUAQAEAAkJBxGFHADUAQAAAA==.Rouen:BAAALgAECgcJBwABLgAECgkJMwADAJwbAA==.',
Rp='Rp:BAAALgAECgMJAwAAAA==.',
Rq='Rq:BAAALgADCgYJBgAAAA==.',
Rt='Rtfreshness:BAAALgAECgYJBgAAAA==.',
Ru='Runswithheal:BAAALgAECgQJBQAAAA==.',
Ry='Ryyukken:BAAALgAECgYJCQAAAA==.',
['Rà']='Ràndòm:BAAALgADCgIJAgABLgAFFAgJHgAeAIEdAA==.Ràwrshåk:BAAALgADCgYJCgAAAA==.',
['Rá']='Rándom:BAABLgAFFH8GAAIKAAMJ8AqtPwCsAAAKAAMJ8AqtPwCsAAABLgAFFAgJHgAeAIEdAA==.',
['Ró']='Rónin:BAAALgAFFAEJAwAAAA==.',
Sa='Sago:BAAALgAECgMJBAAAAA==.Salyveir:BAAALgAECgIJAgAAAA==.Sanzen:BAABLgAECn8ZAAMUAAYJsRvIIgDAAQAUAAYJsRvIIgDAAQAmAAMJsgcVWQBqAAAAAA==.Sarentu:BAAALgAECgQJBAABLgAECggJHwAMAA4cAA==.Sauce:BAABLgAECn9DAAImAAkJoB+CBgAtAwAmAAkJoB+CBgAtAwAAAA==.',
Sc='Scrubz:BAABLgAECn8aAAInAAkJixrVBwA2AgAnAAkJixrVBwA2AgAAAA==.',
Se='Sekcypants:BAAALgADCgcJBwAAAA==.Senile:BAABLgAECn8sAAIgAAgJghz6AQBMAgAgAAgJghz6AQBMAgAAAA==.Seydori:BAAALgADCgUJDAAAAA==.',
Sh='Shadydice:BAAALgADCgYJBgABLgAECgkJJgALAIkUAA==.Shadylid:BAABLgAECn8mAAMLAAkJiRTDOADYAQALAAkJiRTDOADYAQAHAAMJVQmbJABqAAAAAA==.Shadówglider:BAABLgAECn8WAAILAAYJwgrXmwDcAAALAAYJwgrXmwDcAAAAAA==.Shaelia:BAAALgAECgYJBwAAAA==.Shale:BAABLgAECn8YAAILAAkJziDMPADIAQALAAkJziDMPADIAQAAAA==.Shamallaman:BAAALgAECgEJAQABLgAECgkJKwABAJwkAA==.Shameless:BAAALgAFFAIJAgAAAA==.Sharkina:BAAALgADCgUJBQAAAA==.Sharkweek:BAAALgAECgQJBQAAAA==.Sheyoni:BAAALgAECgUJDAAAAA==.Shortbusava:BAAALgADCgcJBwAAAA==.Shreck:BAAALgAECgQJBgAAAA==.',
Si='Sinfulness:BAAALgAECgUJBwAAAA==.',
Sk='Skean:BAAALgAECggJCgAAAA==.Skikette:BAAALgAECgYJDAAAAA==.Skinrot:BAACLgAFFH8HAAIKAAMJKwd0RgCXAAAKAAMJKwd0RgCXAAAuAAQKfzkAAgoACQkSEDMwANgBAAoACQkSEDMwANgBAAAA.',
Sm='Smig:BAAALgAECgEJBAAAAA==.',
So='Soeki:BAABLgAECn8sAAIOAAgJpxWHBwDNAQAOAAgJpxWHBwDNAQAAAA==.Solux:BAABLgAFFH8OAAMCAAUJbRy4BAA2AQACAAQJNxq4BAA2AQAZAAEJwgHOQgBBAAABLgAFFAUJEAAOADYWAA==.Soullove:BAABLgAECn9YAAIOAAkJ7RqgAgCAAgAOAAkJ7RqgAgCAAgAAAA==.Soullovez:BAABLgAECn8nAAMMAAgJRQ47NAA5AQAMAAcJcRA7NAA5AQAKAAcJhQrGXgAQAQABLgAECgkJWAAOAO0aAA==.Soulshocks:BAABLgAECn87AAIbAAgJrBKbKgCPAQAbAAgJrBKbKgCPAQABLgAECgkJWAAOAO0aAA==.Soulviver:BAABLgAECn9DAAIEAAkJRBUnEQBNAgAEAAkJRBUnEQBNAgAAAA==.',
Sp='Sparkelly:BAAALgADCgEJAQAAAA==.Spicytuna:BAAALgAECgYJCQAAAA==.Spliffy:BAAALgADCgYJBgAAAA==.Spurey:BAACLgAFFH8RAAIeAAQJIQ4XXQAmAQAeAAQJIQ4XXQAmAQAuAAQKfy8AAx8ACQn6HjoDAEUCAB8ACAk1GjoDAEUCAB4ACQnIGdZiALIBAAAA.Spurylock:BAAALgADCggJDQABLgAFFAQJEQAeACEOAA==.',
St='Starstreak:BAAALgAECgYJBgABLgAECgkJNQAeABUSAA==.Stimer:BAACLgAFFH8JAAIVAAMJnyGWIAAiAQAVAAMJnyGWIAAiAQAuAAQKfz4AAxUACQmPIb8GADwDABUACQmKIb8GADwDACUACAkLHZ4PAOoBAAAA.Stuipd:BAAALgADCgYJCQAAAA==.',
Su='Sublimedeath:BAABLgAECn8UAAIaAAUJ9RRwJAAbAQAaAAUJ9RRwJAAbAQAAAA==.Sublimelife:BAAALgAECgEJAQAAAA==.Sukboytony:BAAALgADCgYJBgAAAA==.Sultanofswat:BAAALgADCgcJBwAAAA==.Sunnysideup:BAAALgAECgUJBQAAAA==.',
Sv='Svetlana:BAAALgAECgYJEQAAAA==.',
Sw='Swan:BAACLgAFFH8IAAIeAAMJ+QevhwC8AAAeAAMJ+QevhwC8AAAuAAQKfxYAAx4ABwk5EIGhAJQBAB4ABwk5EIGhAJQBACAAAwkHBE0MAGkAAAEuAAUUBAkQACEADg8A.Swordboardal:BAACLgAFFH8VAAIaAAQJFxFUFADtAAAaAAQJFxFUFADtAAAuAAQKfxsAAxoACQm8F/sMABACABoACQm8F/sMABACACUABQk4A3suAIIAAAAA.',
Sy='Sybius:BAAALgAECgEJAgAAAA==.Symptom:BAAALgAECgEJAQAAAA==.Syncophat:BAAALgADCgcJDQAAAA==.',
['Sé']='Séphórâ:BAAALgADCgMJBAAAAA==.',
Ta='Tachia:BAAALgAECgYJBgAAAA==.Tad:BAAALgAECgMJBwAAAA==.Taint:BAAALgADCgQJBgAAAA==.Takara:BAAALgADCgEJAQABLgAECggJHAAJALMaAA==.Takia:BAABLgAECn8gAAMWAAYJBQRVsADSAAAWAAYJBQRVsADSAAANAAMJwAALQQAhAAAAAA==.Talanzen:BAACLgAFFH8HAAIeAAMJTxkobQD8AAAeAAMJTxkobQD8AAAuAAQKfygAAh4ACQnOHwMiAJACAB4ACQnOHwMiAJACAAAA.Talonia:BAAALgADCgEJAQABLgAECgMJBAAIAAAAAA==.Tanakiko:BAAALgADCgUJCQAAAA==.Tarrzok:BAAALgADCgcJBwABLgAECgkJJgALAIkUAA==.',
Te='Teacup:BAAALgAECgUJBgABLgAECgkJJAAYAIYeAA==.Tellanji:BAAALgAECgQJBgAAAA==.',
Th='Theowyn:BAAALgADCgEJAQAAAA==.Thormarian:BAAALgADCgUJBwAAAA==.Thrakara:BAACLgAFFH8gAAImAAYJIRQIFwCVAQAmAAYJIRQIFwCVAQAuAAQKfzkAAiYACAmNHw4OAHUCACYACAmNHw4OAHUCAAAA.Thunderhorns:BAABLgAECn8nAAINAAgJYAl5EwAbAQANAAgJYAl5EwAbAQAAAA==.Thundrall:BAABLgAECn8YAAIWAAYJpgE74AB1AAAWAAYJpgE74AB1AAAAAA==.',
Ti='Tinionron:BAAALgADCgUJCAAAAA==.',
To='Toaster:BAAALgADCgQJBAABLgAFFAUJEgAZAHEZAA==.Toothléss:BAAALgADCgIJAgAAAA==.Toria:BAAALgAECgUJBgAAAA==.Torlania:BAAALgADCgYJBgAAAA==.',
Tr='Trayleen:BAAALgAECgMJBAAAAA==.Treeåj:BAABLgAECn8kAAMMAAgJ9gzENAA2AQAMAAgJ9gzENAA2AQAKAAYJiwVDkwCpAAAAAA==.Trilina:BAAALgADCgkJCAAAAA==.Truths:BAACLgAFFH8lAAMVAAcJnxloBQD0AQAVAAcJnxloBQD0AQAlAAEJcwApQQAuAAAuAAQKfyQAAhUACAkJJYIIACMDABUACAkJJYIIACMDAAAA.Trystrom:BAAALgAECgIJAgAAAA==.',
Ts='Tsuo:BAACLgAFFH8VAAInAAYJ4SGtAgDxAQAnAAYJ4SGtAgDxAQAuAAQKfzgAAicACAkgJsACAPwCACcACAkgJsACAPwCAAAA.',
Tu='Tuhãn:BAAALgAECgEJAQAAAA==.',
Tw='Twixxed:BAAALgADCgYJCAABLgAECggJGgARANMdAA==.',
Tx='Txjustice:BAAALgADCgUJDwAAAA==.',
Ty='Tymptriss:BAABLgAECn8gAAIOAAYJ/Qo7GQDPAAAOAAYJ/Qo7GQDPAAAAAA==.Tyrick:BAAALgAECgkJEAAAAA==.Tywen:BAAALgADCgEJAQAAAA==.',
Uh='Uhogpaladin:BAAALgADCgEJAQAAAA==.',
Um='Umbrage:BAACLgAFFH8QAAMOAAUJNhbFEQCeAAAQAAQJdBL0bgDUAAAOAAIJrRrFEQCeAAAuAAQKfykABA4ACAmAIfoIADECAA4ABwnpHfoIADECABAACAkXHkEwABICAA8AAQmWHSooAFEAAAAA.',
Un='Unholyblade:BAAALgADCgYJCgAAAA==.',
Ur='Urethrafrkln:BAAALgAECgIJAgAAAA==.',
Va='Vache:BAAALgADCgkJFgAAAA==.Valartha:BAABLgAECn8ZAAIMAAYJGherLwBSAQAMAAYJGherLwBSAQAAAA==.Variol:BAABLgAECn8bAAIEAAgJgA1PLABbAQAEAAgJgA1PLABbAQAAAA==.Vaztek:BAAALgADCgMJAwAAAA==.',
Ve='Vecna:BAAALgAECgYJEAAAAA==.Vellarya:BAAALgADCgYJBgABLgAECgkJHgAcAG4hAA==.Vellmora:BAAALgAECgEJAQAAAA==.Velsea:BAAALgAECgMJBwAAAA==.Velstadt:BAABLgAECn83AAIUAAkJCyHdBAD9AgAUAAkJCyHdBAD9AgAAAA==.Venhance:BAABLgAECn8gAAMbAAgJNxfbJgCmAQAbAAgJNxfbJgCmAQAcAAEJTBBmzAAvAAAAAA==.Venotu:BAABLgAECn8xAAICAAkJPR7MBQCEAgACAAkJPR7MBQCEAgAAAA==.Vermilion:BAABLgAECn8aAAILAAYJHAiyqwDAAAALAAYJHAiyqwDAAAAAAA==.Veronor:BAAALgAECgQJBAABLgAECgkJNwAUAAshAA==.Verso:BAAALgADCgcJEwAAAA==.',
Vh='Vholatile:BAAALgAECgYJCwAAAA==.',
Vi='Vinculum:BAAALgADCgIJAgAAAA==.Viviel:BAAALgAECgkJNAAAAQ==.',
Vo='Voidherron:BAAALgAECgYJCwAAAA==.Voidobscur:BAAALgADCgUJBQAAAA==.Voidwapa:BAAALgAECgQJCAAAAA==.Vonzilla:BAABLgAECn8pAAIDAAYJ9hv/JQCUAQADAAYJ9hv/JQCUAQAAAA==.Vorthael:BAABLgAECn8rAAIRAAcJYgdpuwD7AAARAAcJYgdpuwD7AAAAAA==.Voxen:BAAALgADCgQJBAAAAA==.',
Vy='Vynirel:BAAALgAECgEJAQAAAA==.',
['Vö']='Vöid:BAAALgADCgcJBwAAAA==.',
Wa='Waarlow:BAAALgADCgEJAQAAAA==.Warlockbot:BAAALgAFFAEJAwAAAA==.Warmongral:BAABLgAECn86AAIBAAgJ2xlsOAAVAgABAAgJ2xlsOAAVAgAAAA==.Waterboot:BAAALgAECgYJDwAAAA==.Wattheyneed:BAAALgADCgUJBQAAAA==.',
We='Wendi:BAABLgAECn8mAAIOAAcJeQ1WEwAKAQAOAAcJeQ1WEwAKAQAAAA==.',
Wh='Wheelchair:BAAALgADCgUJBQABLgAECgkJSAANAD8hAA==.Whipx:BAAALgADCgIJAgAAAA==.',
Wi='Wingsaber:BAABLgAECn89AAIBAAkJAxXwSgDbAQABAAkJAxXwSgDbAQAAAA==.Wisename:BAAALgAECgMJBgAAAA==.Withher:BAAALgADCgkJEAAAAA==.',
Wo='Wombo:BAABLgAECn8yAAIXAAkJKSR/AABTAwAXAAkJKSR/AABTAwAAAA==.Woolala:BAAALgAECgcJCAABLgAECgkJPgABAO4jAA==.',
Wr='Wrathran:BAABLgAECn8WAAIWAAgJuBIKTACxAQAWAAgJuBIKTACxAQAAAA==.',
Wu='Wut:BAAALgADCgkJCQABLgAECgkJQwAmAKAfAA==.',
Xa='Xahiri:BAAALgAECgEJAQAAAA==.',
Xl='Xlia:BAAALgAECgIJAgAAAA==.',
Ya='Yaeyo:BAAALgAECgcJDQAAAA==.Yazmat:BAACLgAFFH8HAAIZAAMJNBAWMACoAAAZAAMJNBAWMACoAAAuAAQKfykAAhkACQklHK0MALsCABkACQklHK0MALsCAAAA.Yazmyn:BAAALgAECggJDgAAAA==.',
Ye='Yeah:BAAALgADCgkJCQABLgAECgkJQwAmAKAfAA==.Yerehmi:BAAALgAECgMJBQAAAA==.',
Ym='Ymma:BAAALgADCgcJBwAAAA==.',
Yu='Yuny:BAABLgAECn8aAAImAAgJuAeJOQACAQAmAAgJuAeJOQACAQAAAA==.',
Yv='Yvendria:BAABLgAECn82AAQPAAkJkB7fAQDCAgAPAAkJkB7fAQDCAgAQAAUJpQ/DngD8AAAOAAEJAAAnagA+AAAAAA==.',
Za='Zacnafeen:BAAALgAECgMJAwAAAA==.Zaelessa:BAAALgAECgMJCQABLgAECgkJNAAIAAAAAQ==.Zaier:BAABLgAECn9SAAQZAAkJwCQBAwBFAwAZAAkJwCQBAwBFAwABAAQJKBJw0ADlAAACAAEJxgMlWQAUAAAAAA==.Zaraelila:BAAALgADCgMJAwAAAA==.Zartart:BAAALgAECgkJBgAAAA==.',
Ze='Zeltan:BAABLgAECn8qAAMZAAgJ9hz2LwDCAQAZAAYJGxz2LwDCAQABAAgJsxETZwCWAQAAAA==.Zeropriest:BAAALgADCgUJBQAAAA==.',
Zh='Zhundrenga:BAABLgAECn8gAAISAAYJsQdpOACnAAASAAYJsQdpOACnAAAAAA==.',
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
