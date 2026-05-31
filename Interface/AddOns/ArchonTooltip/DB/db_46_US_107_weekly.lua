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

local lookup = {'Paladin-Retribution','Paladin-Protection','Priest-Shadow','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Druid-Feral','Druid-Restoration','DemonHunter-Devourer','Druid-Balance','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Priest-Discipline','Warrior-Fury','Hunter-BeastMastery','Rogue-Assassination','DeathKnight-Frost','Paladin-Holy','Warrior-Protection','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Mage-Frost','Mage-Arcane','Mage-Fire','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warrior-Arms','Monk-Mistweaver','Druid-Guardian','Rogue-Subtlety',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abogato:BAAALgAECgQJBAAAAA==.',
Ae='Aedra:BAAALgADCgcJEgAAAA==.Aeowyyn:BAAALgAECggJEwAAAA==.',
Af='Af:BAAALgADCgUJBQAAAA==.',
Ah='Ahnir:BAABLgAECn8aAAIBAAkJaw8/XwCZAQABAAkJaw8/XwCZAQAAAA==.Ahnkhano:BAABLgAECn8dAAICAAgJ8RFiEgCjAQACAAgJ8RFiEgCjAQAAAA==.',
Ai='Aidenarren:BAAALgADCgkJEAAAAA==.Ainge:BAAALgADCgUJBQAAAA==.Aiom:BAAALgADCgMJAwAAAA==.',
Ak='Akashaa:BAAALgADCgEJAQAAAA==.Akbartheiiv:BAACLgAFFH8YAAIDAAcJ7xi4AQACAgADAAcJ7xi4AQACAgAuAAQKfzMAAgMACQl7I5QDABEDAAMACQl7I5QDABEDAAAA.',
Al='Alexanderson:BAAALgADCgEJAQAAAA==.Alhamdulilah:BAAALgADCgEJAQAAAA==.Allero:BAAALgAECgMJAwAAAA==.Allistrana:BAABLgAECn8iAAIEAAkJBRwzEwBGAgAEAAkJBRwzEwBGAgAAAA==.Aluvia:BAAALgAECgIJBAAAAA==.',
Am='Amairis:BAAALgAECgYJEQAAAA==.Ambiorix:BAAALgADCgEJAgAAAA==.',
An='Anari:BAAALgADCgUJBQAAAA==.Angelsin:BAAALgADCgkJGwAAAA==.Animorph:BAAALgADCgcJJQAAAA==.Annestasia:BAAALgAECgcJCAAAAA==.Anrion:BAABLgAECn8sAAMFAAkJHyNABQDTAgAFAAkJHyNABQDTAgAGAAcJNxygCADQAQAAAA==.Anteater:BAAALgADCgEJAQABLgAECgUJDgAHAAAAAA==.',
Ap='Aph:BAAALgAECgcJDQAAAA==.Apolló:BAAALgAECgkJDwAAAA==.',
Ar='Araiana:BAAALgAECgEJAQAAAA==.Arayia:BAABLgAECn8aAAMIAAYJEh2gDgCpAQAIAAYJEh2gDgCpAQAJAAUJkA05bgDYAAAAAA==.Arelian:BAABLgAECn8ZAAMGAAkJ2BKvDwA2AQAGAAYJmhavDwA2AQAKAAkJbwvhhQD3AAAAAA==.Aristia:BAABLgAECn8oAAMJAAgJSyPGDQDaAgAJAAgJSyPGDQDaAgALAAEJzwzhggAuAAABLgADCgYJCgAHAAAAAA==.Artaic:BAAALgAECgUJDgAAAA==.Artemysia:BAAALgADCgEJAQAAAA==.',
At='Ataboom:BAAALgADCgEJAQAAAA==.Ataliya:BAAALgAECgQJCgAAAA==.',
Au='Auranar:BAABLgAECn8lAAIMAAgJEAelEwAOAQAMAAgJEAelEwAOAQAAAA==.Aurilia:BAABLgAECn8aAAIEAAYJZB9hFQASAgAEAAYJZB9hFQASAgAAAA==.',
Av='Avanicus:BAABLgAECn8oAAQNAAkJhQpWFADvAAAOAAcJUAkhEgAjAQANAAcJbwlWFADvAAAPAAQJqAOHAwFRAAAAAA==.Aven:BAABLgAECn8jAAMQAAgJkRL5UwC1AQAQAAgJchL5UwC1AQARAAUJNgfEPACFAAAAAA==.',
Ax='Axiomronin:BAABLgAECn8qAAMSAAkJYCTpBADoAgASAAgJ9yTpBADoAgATAAgJJyK3DgCSAgAAAA==.',
Ay='Ayroon:BAAALgAECgQJBQAAAA==.',
Az='Azulien:BAABLgAECn8mAAMUAAgJiAPDOgD8AAAUAAgJiAPDOgD8AAAEAAEJSwDCdAAOAAAAAA==.Azuriel:BAAALgAECgIJAgAAAA==.',
Ba='Baltuk:BAABLgAECn8aAAIQAAgJ0x3YJgCgAgAQAAgJ0x3YJgCgAgAAAA==.Bananafarts:BAAALgADCgMJAwAAAA==.Banderblitz:BAACLgAFFH8GAAIVAAIJ0hF2OACWAAAVAAIJ0hF2OACWAAAuAAQKfzUAAhUACQlIIX4JALcCABUACQlIIX4JALcCAAAA.Baobei:BAAALgADCgcJBwAAAA==.Bar:BAACLgAFFH8HAAMDAAQJigYJKgCCAAADAAQJigYJKgCCAAAEAAMJlRF0JgBnAAAuAAQKfxsAAgMACAlxGicVAEMCAAMACAlxGicVAEMCAAAA.Barunnar:BAAALgADCgEJAQAAAA==.',
Be='Bearlyshady:BAAALgADCgcJCwABLgAECgkJJgAKAIkUAA==.Bellatrixie:BAAALgAECgcJDQAAAA==.Benafflock:BAABLgAECn8eAAQOAAgJYwoADwBLAQAOAAgJRAoADwBLAQAPAAQJYwSY4QCXAAANAAEJDw36OgAsAAABLgAECgcJEgAHAAAAAA==.Beriadhwen:BAAALgAECgYJBwAAAA==.Bermy:BAABLgAECn8aAAINAAkJGxHsEQAOAQANAAkJGxHsEQAOAQAAAA==.Bewildert:BAAALgADCgIJAgAAAA==.',
Bh='Bhawkwco:BAAALgADCgEJAQAAAA==.',
Bl='Blackhawkdk:BAABLgAECn8uAAIQAAkJshsBIwBmAgAQAAkJshsBIwBmAgAAAA==.Blende:BAABLgAECn8pAAIBAAgJxCCFHQB9AgABAAgJxCCFHQB9AgAAAA==.Bloodshadow:BAABLgAECn8yAAIWAAkJWBOrNQDvAQAWAAkJWBOrNQDvAQAAAA==.Blueberrae:BAAALgADCgEJAQAAAA==.Bluemaster:BAAALgADCgYJBgAAAA==.',
Bo='Boidohanta:BAAALgADCgUJBQAAAA==.',
Br='Braveharth:BAABLgAECn8WAAIBAAgJLgTCwQDoAAABAAgJLgTCwQDoAAAAAA==.Braxus:BAAALgAECgMJBAAAAA==.Breakcooloz:BAACLgAFFH8TAAIXAAYJ/R83AQC+AQAXAAYJ/R83AQC+AQAuAAQKfyIAAhcACAmoIyIBADQDABcACAmoIyIBADQDAAEuAAUUBgkeABAAGyIA.Brooce:BAABLgAECn8wAAIBAAkJxh+QFQCsAgABAAkJxh+QFQCsAgAAAA==.Broom:BAAALgADCgkJHQABLgAECgkJPwAMALQgAA==.',
Bu='Burstinurass:BAACLgAFFH8eAAIQAAYJGyKZEgD6AQAQAAYJGyKZEgD6AQAuAAQKfxgAAhAACAm+JWcVALQCABAACAm+JWcVALQCAAAA.',
Ca='Caladorion:BAAALgAECgIJAgAAAA==.Candyjar:BAAALgADCgcJDAAAAA==.Cantmissyou:BAAALgAECgEJBgAAAA==.Capidk:BAAALgAFFAEJAQAAAA==.Carafe:BAAALgADCgEJAQABLgAECgkJJAAYAIYeAA==.Carbonight:BAAALgADCgEJAQAAAA==.Carlos:BAAALgAECgUJDgABLgAECggJJQABAHgiAA==.Caspianne:BAAALgAECgQJBgAAAA==.',
Cb='Cbrown:BAAALgAECgEJAQAAAA==.',
Ce='Celani:BAACLgAFFH8HAAIEAAMJ9RLvGwC2AAAEAAMJ9RLvGwC2AAAuAAQKfyYAAwQACAnaGUMUAB4CAAQACAnaGUMUAB4CABQAAQm6AWpeACQAAAAA.Cellyne:BAABLgAECn8fAAMBAAcJOAbm0gDQAAABAAcJOAbm0gDQAAAZAAIJJAJ2gAA2AAAAAA==.Centy:BAAALgAECgYJEgAAAA==.Ceredisam:BAAALgADCgcJBwAAAA==.',
Ch='Chainheal:BAAALgAECgMJAwAAAA==.Chaz:BAAALgAECgYJEAAAAA==.Chedrood:BAAALgADCgMJBwAAAA==.Chelives:BAEBLgAECn8lAAIaAAcJ5AETMwCYAAAaAAcJ5AETMwCYAAAAAA==.Choalmakyahn:BAAALgADCgUJBQAAAA==.Chubrub:BAABLgAECn8VAAMbAAUJegQhbgB+AAAbAAUJegQhbgB+AAAcAAMJLAPVrABPAAAAAA==.Chìef:BAAALgADCgEJAQAAAA==.',
Ci='Cires:BAAALgAECgEJAgAAAA==.',
Cl='Claud:BAAALgAECgYJBgAAAA==.Cleric:BAAALgADCgMJAwAAAA==.',
Co='Cobaltwolf:BAAALgAECgQJCAAAAA==.Colanasou:BAAALgAECgYJDQAAAA==.Coldbattler:BAABLgAECn8UAAIWAAgJSg9jYgBoAQAWAAgJSg9jYgBoAQAAAA==.Copelongcut:BAAALgADCgMJAQAAAA==.Corrick:BAAALgADCgcJEAAAAA==.',
Cr='Crow:BAAALgAECgkJHQAAAQ==.',
Cu='Curavis:BAAALgADCgMJAwAAAA==.',
Cy='Cydric:BAABLgAECn8iAAIBAAgJhyPFDAAoAwABAAgJhyPFDAAoAwAAAA==.',
Da='Daarrkstar:BAABLgAECn8fAAMcAAcJ7yThDADZAgAcAAcJ7yThDADZAgAdAAMJrxB5IQC6AAABLgAECggJKQABAMQgAA==.Daenyra:BAAALgADCgUJBQAAAA==.Dakarai:BAAALgADCggJDgAAAA==.Danek:BAAALgADCggJGQAAAA==.Darkane:BAABLgAFFH8GAAMMAAYJaAYPHwB+AAAWAAQJrQKHYQCnAAAMAAIJAAwPHwB+AAAAAA==.Darknives:BAAALgAECgEJAwAAAA==.Darocate:BAAALgADCgYJBgAAAA==.Dathanarr:BAAALgAECggJCAAAAA==.',
De='Deadskvll:BAAALgADCgYJBgAAAA==.Deathbot:BAACLgAFFH8WAAIRAAUJ8xb6FAAWAQARAAUJ8xb6FAAWAQAuAAQKf0UAAhEACQnXIhgEAOUCABEACQnXIhgEAOUCAAAA.Demira:BAAALgADCgMJAwAAAA==.Demoray:BAACLgAFFH8KAAIMAAUJvBiZCACSAQAMAAUJvBiZCACSAQAuAAQKfxQAAgwABwl0JB0VAIoCAAwABwl0JB0VAIoCAAAA.Dendrin:BAAALgADCgEJAQAAAA==.Deneese:BAAALgAECgIJAgAAAA==.Derrpy:BAAALgADCgEJAQAAAA==.Desniee:BAABLgAECn8gAAQeAAkJMx91QwBuAgAeAAkJMx91QwBuAgAfAAIJHA3jFAB3AAAgAAEJuxW+DgA/AAAAAA==.Dethrone:BAABLgAECn8aAAQPAAgJhx06KgAjAgAPAAcJoR86KgAjAgANAAYJ5xniIABNAQAOAAEJXBYtLgBCAAAAAA==.',
Di='Digitpro:BAABLgAECn85AAIhAAgJcxAaHQClAQAhAAgJcxAaHQClAQAAAA==.Dirtydragon:BAABLgAECn8mAAMiAAgJ0h09BgCSAgAiAAgJ0h09BgCSAgAjAAEJhwdmZQArAAAAAA==.Disturbo:BAAALgADCgkJDwAAAA==.Divinedecay:BAAALgAECgcJEwABLgAECgkJPwAWAHQaAA==.',
Do='Dok:BAAALgADCgcJBwAAAA==.Donoraginn:BAAALgADCgkJIgABLgADCgkJPQAHAAAAAA==.Donos:BAAALgADCgkJPQAAAA==.Dontkare:BAAALgADCgcJEQABLgAECgkJKgAaAJ0lAA==.Doomjuele:BAAALgADCgYJBgAAAA==.Dorsai:BAAALgADCgUJBQAAAA==.Dott:BAAALgADCgIJAgABLgAECgkJGgABAGsPAA==.',
Dr='Draaxx:BAAALgADCgIJAgAAAA==.Draazzy:BAAALgADCgkJEgAAAA==.Dracbanti:BAAALgADCgkJEQAAAA==.Dracobelle:BAABLgAECn8jAAMiAAYJ2RtdDgDVAQAiAAYJ2RtdDgDVAQAjAAMJ+whmagBwAAAAAA==.Dragundeez:BAAALgAECgcJBwAAAA==.Drark:BAAALgAECgEJAQAAAA==.Drathiel:BAAALgAECgMJAwAAAA==.Draxxien:BAAALgADCgcJBwAAAA==.Drazlowe:BAAALgADCgQJBwAAAA==.Draäx:BAAALgADCgkJCQAAAA==.Dreezee:BAAALgAECgYJCwAAAA==.Drizztknight:BAAALgADCgEJAQAAAA==.Droobear:BAAALgAECgIJAgAAAA==.Drwho:BAABLgAECn8mAAIeAAgJihiEQgD9AQAeAAgJihiEQgD9AQAAAA==.Dràco:BAAALgADCggJDwAAAA==.Drääx:BAAALgADCggJCAAAAA==.Dräëxx:BAAALgADCgcJDQAAAA==.',
Du='Durimli:BAAALgADCgYJBwAAAA==.',
Dw='Dwayneb:BAAALgAECgkJBwAAAA==.',
['Dî']='Dîxon:BAAALgADCgcJBwABLgAFFAYJHgAQABsiAA==.',
['Dô']='Dôz:BAAALgADCgQJBAAAAA==.',
Ea='Earthernbot:BAABLgAFFH8OAAIeAAQJRwk2XAAaAQAeAAQJRwk2XAAaAQAAAA==.Earthspeaker:BAAALgADCgEJAQAAAA==.',
Ei='Eidolon:BAAALgADCgkJCQAAAA==.',
El='Eleram:BAAALgADCgYJBgABLgAECgkJGgABAGsPAA==.Elfadwagon:BAACLgAFFH8XAAIkAAUJMhvcAgBPAQAkAAUJMhvcAgBPAQAuAAQKfyQAAiQACAlcIa8CAAIDACQACAlcIa8CAAIDAAAA.Eliptical:BAAALgAECgYJEwABLgAECggJGwABAO4eAA==.Elkesey:BAAALgADCgEJAQAAAA==.Elonura:BAAALgADCgYJBgAAAA==.Elunea:BAAALgADCggJCwAAAA==.',
Em='Emishanot:BAAALgAECgEJAQABLgAECgYJEQAHAAAAAA==.',
Ep='Epoch:BAAALgADCgEJAQAAAA==.',
Er='Erangar:BAABLgAECn8aAAIbAAYJKAtIUADZAAAbAAYJKAtIUADZAAAAAA==.Erdor:BAAALgADCgcJDgAAAA==.Erini:BAAALgADCgkJCQAAAA==.Erred:BAAALgADCgcJBwAAAA==.',
Es='Esmer:BAABLgAECn8tAAIBAAkJJwoVcQByAQABAAkJJwoVcQByAQAAAA==.',
Et='Etheman:BAAALgAECgcJDQAAAA==.',
Eu='Euphrasie:BAAALgADCgUJBQABLgAECgkJHgAcAG4hAA==.',
Ev='Eversteal:BAAALgADCgQJBAABLgAECggJKAACAFAbAA==.Evholker:BAABLgAECn8cAAMkAAkJXBDWCwBEAQAkAAgJ6RDWCwBEAQAjAAYJFw7/RQDvAAAAAA==.',
Ex='Excuses:BAAALgAECgYJDAABLgAFFAcJIwAVAN8YAA==.Executey:BAAALgADCgQJBAAAAA==.Exhumina:BAAALgAECgcJBgAAAA==.',
Fa='Facestealerr:BAAALgAECgYJEwAAAA==.Fallenhullkk:BAAALgADCgYJBgAAAA==.Fangyi:BAAALgADCgYJBgAAAA==.',
Fe='Feetsmell:BAAALgADCgkJEgABLgAECgkJPwAMALQgAA==.Felmufín:BAABLgAECn8cAAIPAAgJQwxJbgBTAQAPAAgJQwxJbgBTAQAAAA==.Felspury:BAAALgAECgEJAQABLgAFFAQJDQAeAIIKAA==.Feyrea:BAAALgAECgMJAwAAAA==.',
Fi='Fibula:BAAALgADCgcJBwAAAA==.',
Fl='Flairrick:BAABLgAECn8kAAIVAAcJvB4WGgAJAgAVAAcJvB4WGgAJAgAAAA==.Flars:BAABLgAECn8eAAIYAAgJdxvQBQAnAgAYAAgJdxvQBQAnAgAAAA==.Flatliner:BAACLgAFFH8OAAIZAAUJCAbWHAAgAQAZAAUJCAbWHAAgAQAuAAQKfzkAAxkACAk1DiM0AK0BABkACAk1DiM0AK0BAAEAAQmlCV9TASoAAAAA.Floracide:BAAALgAECgYJCwAAAA==.Florence:BAAALgAECgYJBgABLgAECgYJCwAHAAAAAA==.Flyingbot:BAAALgAECgUJBQAAAA==.',
Fo='Foid:BAAALgAECgYJBwAAAA==.Forq:BAAALgADCgcJBwAAAA==.',
Fr='Fran:BAAALgADCgYJBgABLgAECgkJPwAMALQgAA==.Frankzappn:BAAALgAECgQJBAAAAA==.Fray:BAABLgAECn8hAAIKAAkJahpmHwBEAgAKAAkJahpmHwBEAgAAAA==.Freeguy:BAABLgAECn8mAAIKAAkJCxrNGwBZAgAKAAkJCxrNGwBZAgAAAA==.',
Fu='Fuddicus:BAABLgAECn9FAAMcAAkJjyTPBwAfAwAcAAkJjyTPBwAfAwAbAAEJGRI9gwA9AAAAAA==.Fuddmore:BAAALgAECgYJBwABLgAECgcJDQAHAAAAAA==.Fuddster:BAAALgAECgcJDQAAAA==.',
Ga='Gaddess:BAABLgAECn8eAAIDAAYJGwcdTAC3AAADAAYJGwcdTAC3AAAAAA==.Ganath:BAAALgAECgMJAwAAAA==.Ganymede:BAAALgAECgYJDQAAAA==.Garan:BAAALgADCgQJBAAAAA==.Garnar:BAAALgADCgIJAgAAAA==.',
Ge='Geilamaine:BAABLgAECn8gAAIZAAkJFRyTBwD/AgAZAAkJFRyTBwD/AgAAAA==.',
Gi='Gimpy:BAAALgAECgQJBQAAAA==.',
Gl='Glimagi:BAAALgADCgcJDwAAAA==.Glimdaemon:BAAALgAECgIJAgAAAA==.',
Go='Gonefishing:BAABLgAECn8+AAIBAAkJ7iM+CwD4AgABAAkJ7iM+CwD4AgAAAA==.Gorddownie:BAABLgAECn8fAAILAAYJuAP0WQCOAAALAAYJuAP0WQCOAAAAAA==.',
Gr='Graied:BAAALgAECgYJBgAAAA==.Grellior:BAAALgAECgEJAQAAAA==.Grimjawz:BAAALgAECgIJAgAAAA==.Grippysocks:BAACLgAFFH8SAAIZAAUJcRmNFABoAQAZAAUJcRmNFABoAQAuAAQKfzMAAhkACAnKGBIcADQCABkACAnKGBIcADQCAAAA.',
Gu='Gummibear:BAABLgAECn8WAAMlAAcJcw7ZIwAtAQAlAAcJcw7ZIwAtAQAaAAQJ2ANZNwCNAAAAAA==.',
Ha='Hakar:BAAALgAECgYJCAAAAA==.Hanoa:BAAALgADCgIJAgAAAA==.Harthoon:BAACLgAFFH8eAAIeAAUJLxDTUQAuAQAeAAUJLxDTUQAuAQAuAAQKfzkAAh4ACAnIHn06ABgCAB4ACAnIHn06ABgCAAAA.Haruharu:BAAALgAECgMJCwAAAA==.Hawkhogan:BAAALgADCgYJCQAAAA==.Hazdanzul:BAAALgADCgQJBQABLgAECgYJEQAHAAAAAA==.',
He='Hehexxd:BAAALgAECgIJAgAAAA==.Helias:BAAALgADCgkJBgAAAA==.Hemp:BAAALgAECgMJAwAAAA==.Herrondale:BAAALgADCgcJBwAAAA==.Hey:BAAALgADCgkJIwABLgAECgkJOgAmAPcdAA==.',
Hj='Hjukonlikjuj:BAAALgAECgEJAQAAAA==.',
Ho='Hollanov:BAAALgADCgYJBgAAAA==.Honeynoats:BAABLgAECn8jAAIEAAgJ5Ai8MQAsAQAEAAgJ5Ai8MQAsAQAAAA==.Honks:BAAALgAECgQJBQAAAA==.Hotdwarf:BAAALgAECggJEQAAAA==.',
Hu='Hubbabubbles:BAAALgAECgEJAQAAAA==.Hullkk:BAACLgAFFH8ZAAMVAAUJcyNcFQBHAQAVAAQJ8htcFQBHAQAlAAQJuSBjFAATAQAuAAQKfzcAAxUACAmJJokFAE4DABUACAnOJYkFAE4DACUABwkPJFUFAJ4CAAAA.Hundale:BAAALgAECgQJBAAAAA==.Hutchkins:BAABLgAECn8qAAMPAAgJ7hxPLQBYAgAPAAgJ7hxPLQBYAgAOAAEJAACePwAAAAAAAA==.Hutchknight:BAAALgAECgUJDAABLgAECggJKgAPAO4cAA==.Hutchyo:BAAALgADCgQJBAABLgAECggJKgAPAO4cAA==.',
Hy='Hydro:BAACLgAFFH8JAAIBAAQJRw2cPwAVAQABAAQJRw2cPwAVAQAuAAQKfzQAAwEACQlGIa0TALgCAAEACQlGIa0TALgCAAIABAk1D/YqAKoAAAAA.Hypovolaemia:BAAALgADCgYJCAAAAA==.',
['Hä']='Häwtz:BAAALgADCgIJAgAAAA==.',
Ia='Iamhealer:BAAALgADCgMJAgAAAA==.',
Il='Illaandra:BAAALgADCgEJAQABLgAECgMJAwAHAAAAAA==.',
In='Inari:BAAALgAECgQJBwABLgAECgkJLAAhAE4YAA==.Inseng:BAABLgAECn8jAAMRAAgJdyADEADvAQARAAYJqSIDEADvAQAYAAgJNxevDgBYAQAAAA==.Invasion:BAAALgAECgYJDAAAAA==.',
Ix='Ixy:BAABLgAECn8nAAIKAAkJLRqkHQBOAgAKAAkJLRqkHQBOAgAAAA==.',
Ja='Jahde:BAABLgAECn8yAAIJAAgJKg0MRQBoAQAJAAgJKg0MRQBoAQAAAA==.Jahoda:BAAALgADCgYJBgAAAA==.Jaina:BAAALgAECgQJBQAAAA==.Jamer:BAABLgAECn8hAAIaAAYJ0CIBDgDyAQAaAAYJ0CIBDgDyAQAAAA==.Jassykins:BAABLgAECn8gAAIWAAcJSw5fbQBPAQAWAAcJSw5fbQBPAQAAAA==.',
Je='Jeewop:BAAALgADCgEJAQAAAA==.Jeongaegdeom:BAAALgADCgcJDgAAAA==.Jessecuster:BAAALgAECgUJBgAAAA==.',
Ji='Jindouyun:BAAALgAFFAIJAgAAAA==.Jinjerr:BAAALgAECgcJDAAAAA==.',
Jo='Joloc:BAABLgAECn8gAAINAAgJFRESCwByAQANAAgJFRESCwByAQAAAA==.Jozay:BAAALgAECgYJDAAAAA==.',
Ju='Juancarlos:BAAALgADCgEJAQAAAA==.',
Ka='Kaidaa:BAAALgAECgQJBAAAAA==.Kaladan:BAAALgAECgMJBAAAAA==.Kalasparkle:BAAALgAECgYJDQAAAA==.Kalrosa:BAABLgAECn8aAAIVAAYJ4iJ7JAC9AQAVAAYJ4iJ7JAC9AQABLgAFFAIJBgAVANIRAA==.Kare:BAABLgAECn8qAAIaAAkJnSV3AgARAwAaAAkJnSV3AgARAwAAAA==.Karee:BAABLgAECn8iAAICAAkJ6yTFAABUAwACAAkJ6yTFAABUAwABLgAECgkJKgAaAJ0lAA==.Kathilnas:BAAALgADCgUJBQABLgAECgYJEQAHAAAAAA==.',
Kc='Kcosfomas:BAAALgADCgIJAgAAAA==.',
Ke='Kebob:BAAALgADCgcJCAAAAA==.Kermodk:BAAALgAECgYJCgAAAA==.Kermodrood:BAABLgAECn8qAAMLAAkJCSO9BAADAwALAAkJCCO9BAADAwAnAAQJRyJgIAAkAQAAAA==.',
Kh='Khanthurs:BAAALgAECgQJBAAAAA==.Kholdbrew:BAAALgAECgYJCwAAAA==.',
Ki='Kiizo:BAABLgAECn8nAAIoAAgJhRZ5FQDbAQAoAAgJhRZ5FQDbAQAAAA==.Kilnot:BAABLgAECn8UAAIcAAcJ4xZQMgC8AQAcAAcJ4xZQMgC8AQAAAA==.Kinstine:BAABLgAECn8VAAIRAAYJ/wFMMgCtAAARAAYJ/wFMMgCtAAAAAA==.',
Kn='Knarwxlves:BAAALgAECgMJAwAAAA==.',
Ko='Koltara:BAABLgAFFH8MAAIKAAUJvRjyLgA/AQAKAAUJvRjyLgA/AQAAAA==.Koltaris:BAACLgAFFH8PAAISAAQJTh83FwBHAQASAAQJTh83FwBHAQAuAAQKfyIAAhIACAl2JPEHAKQCABIACAl2JPEHAKQCAAEuAAUUBQkMAAoAvRgA.Konshis:BAACLgAFFH8HAAMmAAMJawmsNACVAAAmAAMJawmsNACVAAATAAEJqQWBOgA4AAAuAAQKfyQAAiYACQkqFe0kAM8BACYACQkqFe0kAM8BAAAA.Kookymonster:BAABLgAECn84AAMPAAkJ5yG7DQDTAgAPAAgJFyG7DQDTAgANAAcJlh2CBwBPAgAAAA==.Korbyn:BAAALgADCgkJCQAAAA==.Kos:BAACLgAFFH8YAAMQAAUJIBRqVQAsAQAQAAQJIBRqVQAsAQARAAEJAAB3TwAAAAAuAAQKfxcAAxAACAl6H5AxACQCABAACAl6H5AxACQCABgAAgmaGfciAH0AAAAA.',
Ku='Kuragaru:BAACLgAFFH8WAAMoAAUJDiBwEwBQAQAoAAUJDiBwEwBQAQAXAAIJbwxWBACsAAAuAAQKfzgAAygACAm1JN4HAJQCACgACAm1JN4HAJQCABcACAlqGicFAEMCAAAA.',
Ky='Kyoubouna:BAAALgAECgQJBAAAAA==.Kyoxi:BAAALgADCgEJAQAAAA==.',
La='Laedrea:BAAALgADCgEJAQAAAA==.Larianne:BAAALgAECgcJEgAAAA==.',
Le='Leese:BAABLgAECn8jAAILAAgJ6wfROgAKAQALAAgJ6wfROgAKAQAAAA==.Leretic:BAAALgAECgYJBgABLgAECggJGwABAO4eAA==.Lerion:BAABLgAECn8bAAIBAAgJ7h4fEgABAwABAAgJ7h4fEgABAwAAAA==.Lester:BAABLgAECn8yAAIDAAkJrBrVCwB4AgADAAkJrBrVCwB4AgAAAA==.Lethana:BAAALgADCgcJDAAAAA==.Lexysady:BAAALgAECgIJAgAAAA==.',
Li='Liamsun:BAABLgAECn9AAAQmAAkJJhXXGwASAgAmAAkJJhXXGwASAgASAAgJShajGgC/AQATAAYJuxT4PwAZAQAAAA==.Lidd:BAAALgAECgQJAwAAAA==.Lidrael:BAABLgAECn8+AAQGAAkJDh5cAwCSAgAGAAkJDh5cAwCSAgAFAAYJNAX+QgDsAAAKAAYJewpXmwDiAAAAAA==.Lidrahl:BAAALgADCgcJDQAAAA==.Liekos:BAAALgAECgMJCAAAAA==.Lightbloom:BAAALgAECgIJBQAAAA==.Lightwing:BAAALgAECgEJAgAAAA==.Liliria:BAABLgAECn88AAIEAAkJdRiYEwAlAgAEAAkJdRiYEwAlAgAAAA==.Lillidân:BAAALgAECgYJEQAAAA==.Lingwong:BAAALgAECgcJCQAAAA==.Litebite:BAAALgAECgUJBQAAAA==.Litharelw:BAAALgAECgIJAgAAAA==.Littlefish:BAAALgADCgcJDwAAAA==.',
Lj='Ljaeì:BAABLgAECn8eAAIDAAgJRxnSGADkAQADAAgJRxnSGADkAQAAAA==.',
Ll='Lloreth:BAABLgAECn8gAAIJAAkJkgp/QQB5AQAJAAkJkgp/QQB5AQAAAA==.',
Ln='Lnpoop:BAAALgAECggJEQAAAA==.',
Lo='Locknload:BAAALgADCgMJAwAAAA==.Lockwood:BAABLgAECn8jAAIoAAkJvg9WFgDTAQAoAAkJvg9WFgDTAQAAAA==.Lominar:BAAALgADCgcJBwAAAA==.Lorelei:BAABLgAECn8lAAIWAAcJAg0YcABIAQAWAAcJAg0YcABIAQAAAA==.Lorrellia:BAABLgAECn8aAAIeAAkJzgQolQAzAQAeAAkJzgQolQAzAQAAAA==.Loway:BAAALgADCgkJEgABLgAECgkJPwAMALQgAA==.',
Lu='Luc:BAAALgADCgkJCQABLgAECgkJOgAmAPcdAA==.Lucariõ:BAACLgAFFH8YAAIEAAcJ7RTLAwAEAgAEAAcJ7RTLAwAEAgAuAAQKfxYAAgQACAkXHpMNAH8CAAQACAkXHpMNAH8CAAAA.Lumina:BAABLgAECn8eAAICAAYJJhtNEwB7AQACAAYJJhtNEwB7AQAAAA==.Lunaría:BAAALgADCgUJBgAAAA==.Lustydragon:BAAALgADCgEJAQAAAA==.',
Ly='Lyllies:BAAALgAECgIJAgAAAA==.Lysergia:BAABLgAECn8eAAIcAAkJbiHlCQD/AgAcAAkJbiHlCQD/AgAAAA==.',
['Lì']='Lìght:BAACLgAFFH8XAAIZAAUJ4xZYFQBgAQAZAAUJ4xZYFQBgAQAuAAQKfyEAAhkABwkWI4oXADUCABkABwkWI4oXADUCAAAA.',
Ma='Madrona:BAAALgAECgYJEgAAAA==.Magnumrex:BAAALgADCgcJDAAAAA==.Mahoney:BAAALgAECgUJBQAAAA==.Majestynihil:BAAALgADCggJCAAAAA==.Makkazul:BAABLgAECn8gAAMQAAgJnBelUwC1AQAQAAgJfRelUwC1AQAYAAUJ3hXLFwDlAAAAAA==.Maladia:BAAALgADCgkJCQAAAA==.Management:BAAALgADCgQJBAAAAA==.Mangler:BAABLgAECn8UAAIbAAYJcAQVYACoAAAbAAYJcAQVYACoAAAAAA==.Maris:BAAALgADCgkJEgAAAA==.Marrad:BAAALgAECgQJBAAAAA==.Marrok:BAAALgAECgcJBwAAAA==.Marunji:BAAALgAECgYJEQAAAA==.Matcauthon:BAAALgAECgQJCAAAAA==.Matrim:BAAALgAECgQJBwAAAA==.Mattdæmon:BAABLgAECn8mAAQFAAgJkg4IHwBdAQAFAAgJkg4IHwBdAQAKAAIJpwLF2AA+AAAGAAEJMgcGNgAaAAAAAA==.Mattmattmatt:BAAALgADCgEJAQAAAA==.Mazzak:BAAALgADCgUJDgAAAA==.',
Me='Meanit:BAAALgAECgQJBgAAAA==.Meekogaia:BAABLgAECn89AAIcAAkJRiG3BgAxAwAcAAkJRiG3BgAxAwAAAA==.Meekosan:BAAALgAECgQJBgAAAA==.Melestaris:BAAALgADCgYJBgAAAA==.',
Mi='Mihlenna:BAAALgADCgcJBwAAAA==.Millerowntoo:BAAALgAFFAIJBAABLgAFFAMJCwAWAP8mAA==.Mimzy:BAAALgAECgEJAgAAAA==.Minarmo:BAAALgADCgEJAQAAAA==.Mingzi:BAAALgAECggJDwAAAA==.Missanabie:BAAALgADCgcJBwAAAA==.Missymeow:BAAALgADCgYJDAAAAA==.Mital:BAAALgADCgEJAQAAAA==.Mizu:BAEALgAECgEJAgAAAA==.',
Mm='Mmbear:BAAALgAECgEJAQABLgAFFAYJIwABAAgYAA==.',
Mo='Mojeen:BAAALgADCgIJAgAAAA==.Monkoko:BAAALgADCgEJAgAAAA==.Montkriege:BAABLgAECn8UAAUJAAYJdQthZAD2AAAJAAYJdQthZAD2AAALAAUJpwLTZACOAAAIAAIJoxJgKgB1AAAnAAEJJxpjLABGAAAAAA==.Moonsocks:BAAALgAECgUJBQABLgAFFAUJEgAZAHEZAA==.Morpheus:BAAALgADCggJCAAAAA==.Mourium:BAAALgAECgMJAwAAAA==.Moxxie:BAABLgAECn8WAAMLAAcJMxbzMwAuAQALAAYJsBXzMwAuAQAIAAEJwBgBPABKAAAAAA==.',
Mu='Mufín:BAAALgAECgYJCQAAAA==.Murfie:BAABLgAECn8aAAMDAAkJVRYzIwC+AQADAAkJVRYzIwC+AQAEAAQJWgyDWQDOAAAAAA==.Murica:BAAALgADCgEJAQABLgAECgkJPwAMALQgAA==.',
My='Mythiccbops:BAAALgAECgMJAwABLgAECgkJNwAEAK4ZAA==.Mythosrex:BAAALgAECgcJBgAAAA==.',
['Mâ']='Mâjôr:BAAALgADCgUJBQAAAA==.',
['Mì']='Mìr:BAACLgAFFH8SAAIKAAUJEBTgOQAcAQAKAAUJEBTgOQAcAQAuAAQKfzIAAwoACAldIawbAFoCAAoACAldIawbAFoCAAUABgn7EB02AC8BAAAA.',
['Mó']='Mónkass:BAAALgAECgEJAQAAAA==.',
Na='Naitho:BAAALgAECgYJBgAAAA==.Nakedfeet:BAAALgADCgEJAQABLgAFFAUJEgAZAHEZAA==.Narena:BAAALgADCgYJBgAAAA==.Nashira:BAABLgAECn8mAAIcAAkJRguqRgB3AQAcAAkJRguqRgB3AQAAAA==.Nashness:BAACLgAFFH8KAAMQAAQJcBZhTAA6AQAQAAQJcBZhTAA6AQAYAAIJOQdKGACCAAAuAAQKfzIAAxAACQkOIwcQAB0DABAACQkOIwcQAB0DABgAAQnhI9UmAGEAAAAA.Natharion:BAABLgAECn82AAMOAAkJlBiVAgCTAgAOAAkJhRiVAgCTAgAPAAgJWAgtgAAuAQAAAA==.Nazrogul:BAABLgAECn8VAAIQAAYJXwg+sgAeAQAQAAYJXwg+sgAeAQAAAA==.',
Ne='Nerfme:BAAALgAECgYJBwAAAA==.Nezar:BAAALgAECggJCgAAAA==.',
Ni='Ninjaxe:BAACLgAFFH8MAAITAAQJkhAxCAD0AAATAAQJkhAxCAD0AAAuAAQKfyIAAxMACAnLH94JANoCABMACAnLH94JANoCABIAAQkmCD+VACAAAAEuAAUUBgkGAAwAaAYA.Ninkharak:BAAALgADCgEJAQAAAA==.Nishal:BAAALgAECgMJBAABLgAECgkJOQAcALcdAA==.Niterage:BAAALgADCgYJDQAAAA==.',
Nn='Nn:BAABLgAECn8kAAInAAcJ2wzmLwDFAAAnAAcJ2wzmLwDFAAAAAA==.',
No='Noasmago:BAAALgAECgMJAwABLgAFFAUJFAADADgUAA==.Novachrono:BAAALgADCgEJAQAAAA==.',
Nu='Nu:BAAALgAECgYJDAAAAA==.Nuckinphutz:BAAALgADCgYJCwAAAA==.Nullthor:BAABLgAECn8UAAIdAAYJ7xM5FAB3AQAdAAYJ7xM5FAB3AQAAAA==.Nurfd:BAABLgAECn8UAAIaAAYJcAG6OgBvAAAaAAYJcAG6OgBvAAAAAA==.',
['Nè']='Nègan:BAABLgAECn87AAMWAAkJnRdRMgD8AQAWAAkJnRdRMgD8AQAMAAgJbwgLEgAlAQAAAA==.',
['Nì']='Nìr:BAABLgAFFH8JAAIFAAUJ2hEXDQAcAQAFAAUJ2hEXDQAcAQAAAA==.',
['Nó']='Nóva:BAAALgADCgQJBAAAAA==.',
['Nô']='Nôyar:BAAALgAECgQJBQAAAA==.',
Ob='Obamakare:BAAALgAECgYJDQABLgAECgkJKgAaAJ0lAA==.',
Od='Odinrex:BAABLgAECn8rAAIWAAgJahY/OADmAQAWAAgJahY/OADmAQAAAA==.',
Og='Ogmattbone:BAAALgADCgMJAQAAAA==.',
Ol='Oldjuel:BAAALgADCgkJCQAAAA==.',
Op='Opuntia:BAABLgAECn8UAAMTAAYJlRN7LwAzAQATAAYJlRN7LwAzAQAmAAYJQwy+WwDLAAAAAA==.',
Ou='Ouch:BAAALgADCgMJAwAAAA==.Outofarrows:BAABLgAECn8/AAMMAAkJtCB9AQD4AgAMAAkJtCB9AQD4AgAhAAEJXwmRLgA4AAAAAA==.',
Ow='Ow:BAAALgADCgEJAQABLgADCgMJAwAHAAAAAA==.Ownown:BAAALgAECgIJAgABLgAFFAMJCwAWAP8mAA==.',
Pa='Palinuttz:BAAALgAECgMJAwAAAA==.Pallypaladin:BAACLgAFFH8jAAIBAAYJCBjyFACPAQABAAYJCBjyFACPAQAuAAQKfyEAAgEACQnTH8MiAGMCAAEACQnTH8MiAGMCAAAA.Partywolf:BAAALgAECgYJBgAAAA==.Pasteeater:BAAALgAECgQJBAAAAA==.',
Pe='Pernelope:BAABLgAECn8iAAIKAAcJ7RvRRADgAQAKAAcJ7RvRRADgAQAAAA==.Pernicus:BAAALgAECgEJAgAAAA==.',
Ph='Phatzero:BAABLgAECn8/AAMWAAkJdBrtGAB6AgAWAAkJdBrtGAB6AgAMAAIJMgTqMwA6AAAAAA==.Phöenix:BAAALgAECgEJAQAAAA==.',
Pi='Piedra:BAAALgADCgYJDAABLgAECgkJNwAEAK4ZAA==.Pierogi:BAAALgADCgUJBQAAAA==.Piety:BAAALgAECgYJCAAAAA==.Pinjo:BAAALgAECgQJCQAAAA==.',
Po='Polarnomad:BAAALgADCgYJCwABLgAECggJFwAeABkTAA==.Polarr:BAABLgAECn8XAAIeAAgJGRNkzwBNAQAeAAgJGRNkzwBNAQAAAA==.Polydrake:BAAALgAFFAEJAQAAAA==.Popsicles:BAAALgAECgUJBwAAAA==.',
Pr='Prismatic:BAAALgAECgMJBAAAAA==.Probablyblue:BAAALgAECgYJCQAAAA==.Proofy:BAAALgAECgcJDwAAAA==.Prowl:BAAALgADCgYJBgABLgAECgYJCwAHAAAAAA==.',
Ps='Psyop:BAAALgADCgkJEQABLgAECggJFwAEAAUcAA==.',
Pu='Punchkick:BAAALgAECgEJAgAAAA==.Punchup:BAABLgAECn8YAAITAAcJAgqLOwD5AAATAAcJAgqLOwD5AAAAAA==.',
Py='Pythie:BAAALgAECgEJAQAAAA==.',
Ra='Rabit:BAAALgAECgQJCwAAAA==.Ramsey:BAAALgADCgEJAQAAAA==.Rastputin:BAAALgAECgkJDgAAAA==.',
Re='Rebrex:BAAALgADCgcJDgAAAA==.Redpyro:BAAALgADCgcJDwAAAA==.Ren:BAAALgAECgEJAQAAAA==.Retrïbutor:BAAALgAECgYJCgAAAA==.',
Rf='Rf:BAAALgAECgEJAQAAAA==.',
Rh='Rhodraco:BAABLgAECn8hAAMjAAYJPAocTADXAAAjAAYJPAocTADXAAAkAAQJIgo1GAB+AAAAAA==.',
Ri='Rikku:BAAALgAECgYJCQAAAA==.Rinela:BAABLgAECn8fAAILAAgJDhz7GQA2AgALAAgJDhz7GQA2AgAAAA==.Riotdrill:BAAALgADCgYJBwAAAA==.',
Rj='Rj:BAABLgAECn8oAAIJAAgJgCLXCQAMAwAJAAgJgCLXCQAMAwAAAA==.',
Ro='Robari:BAAALgAECgYJBgAAAA==.Robi:BAAALgADCgEJAQABLgAECggJKQABAMQgAA==.Rolandrex:BAAALgAECgEJAQAAAA==.Romulusinc:BAAALgADCgMJBgAAAA==.Rosabee:BAABLgAECn8tAAIEAAkJBxGxGgDcAQAEAAkJBxGxGgDcAQAAAA==.',
Rp='Rp:BAAALgAECgMJAwAAAA==.',
Rq='Rq:BAAALgADCgYJBgAAAA==.',
Rt='Rtfreshness:BAAALgAECgYJBgAAAA==.',
Ru='Runswithheal:BAAALgAECgQJBQAAAA==.',
Ry='Ryyukken:BAAALgAECgYJCQAAAA==.',
['Rà']='Ràndòm:BAAALgADCgIJAgABLgAFFAgJHgAeAIEdAA==.Ràwrshåk:BAAALgADCgYJBgAAAA==.',
['Rá']='Rándom:BAABLgAFFH8GAAIJAAMJ8AoCOgC3AAAJAAMJ8AoCOgC3AAABLgAFFAgJHgAeAIEdAA==.',
['Ró']='Rónin:BAAALgAFFAEJAwAAAA==.',
Sa='Sago:BAAALgAECgMJBAAAAA==.Salyveir:BAAALgAECgIJAgAAAA==.Sanzen:BAABLgAECn8ZAAMTAAYJsRvIIgDAAQATAAYJsRvIIgDAAQAmAAMJsgcVWQBqAAAAAA==.Sauce:BAABLgAECn86AAImAAkJ9x0YCAD8AgAmAAkJ9x0YCAD8AgAAAA==.',
Sc='Scrubz:BAABLgAECn8aAAInAAkJixrVBwA2AgAnAAkJixrVBwA2AgAAAA==.',
Se='Sekcypants:BAAALgADCgcJBwAAAA==.Senile:BAABLgAECn8kAAIgAAcJgxUjBACdAQAgAAcJgxUjBACdAQAAAA==.Seydori:BAAALgADCgUJDAAAAA==.',
Sh='Shadydice:BAAALgADCgYJBgABLgAECgkJJgAKAIkUAA==.Shadylid:BAABLgAECn8mAAMKAAkJiRTANADdAQAKAAkJiRTANADdAQAGAAMJVQmVIgBrAAAAAA==.Shadówglider:BAAALgAECgYJEgAAAA==.Shaelia:BAAALgAECgYJBwAAAA==.Shale:BAABLgAECn8YAAIKAAkJziDwOADMAQAKAAkJziDwOADMAQAAAA==.Shamallaman:BAAALgAECgEJAQABLgAECgkJKwABAJwkAA==.Shameless:BAAALgAFFAIJAgAAAA==.Sharkina:BAAALgADCgUJBQAAAA==.Sharkweek:BAAALgAECgQJBQAAAA==.Sheyoni:BAAALgAECgQJBwAAAA==.Shortbusava:BAAALgADCgcJBwAAAA==.Shreck:BAAALgAECgQJBgAAAA==.',
Si='Sinfulness:BAAALgAECgUJBgAAAA==.',
Sk='Skean:BAAALgAECggJCAAAAA==.Skikette:BAAALgAECgYJBgAAAA==.Skinrot:BAABLgAECn84AAIJAAkJEhD7LQDbAQAJAAkJEhD7LQDbAQAAAA==.',
Sm='Smig:BAAALgAECgEJBAAAAA==.',
So='Soeki:BAABLgAECn8kAAINAAcJPw+DDgA7AQANAAcJPw+DDgA7AQAAAA==.Solux:BAABLgAFFH8MAAICAAQJNxriAwBDAQACAAQJNxriAwBDAQABLgAFFAUJEAANADYWAA==.Soullove:BAABLgAECn9NAAINAAkJ2BdHBAAmAgANAAkJ2BdHBAAmAgAAAA==.Soullovez:BAABLgAECn8nAAMLAAgJRQ7BMQA6AQALAAcJcRDBMQA6AQAJAAcJhQohWwAUAQABLgAECgkJTQANANgXAA==.Soulshocks:BAABLgAECn85AAIbAAgJrBLWJwCVAQAbAAgJrBLWJwCVAQABLgAECgkJTQANANgXAA==.Soulviver:BAABLgAECn88AAIEAAkJhxRZEQBAAgAEAAkJhxRZEQBAAgAAAA==.',
Sp='Sparkelly:BAAALgADCgEJAQAAAA==.Spicytuna:BAAALgAECgYJCQAAAA==.Spliffy:BAAALgADCgYJBgAAAA==.Spurey:BAACLgAFFH8NAAIeAAQJggrTXAAYAQAeAAQJggrTXAAYAQAuAAQKfy8AAx8ACQn6HjoDAEUCAB8ACAk1GjoDAEUCAB4ACQnIGRZbALQBAAAA.Spurylock:BAAALgADCggJDQABLgAFFAQJDQAeAIIKAA==.',
St='Starstreak:BAAALgAECgYJBgABLgAECgkJNQAeABUSAA==.Stimer:BAACLgAFFH8GAAIVAAMJ2x/dIgAPAQAVAAMJ2x/dIgAPAQAuAAQKfzIAAxUACQntH78GADwDABUACQnVH78GADwDACUACAkLHYMOAOwBAAAA.Stuipd:BAAALgADCgYJCQAAAA==.',
Su='Sublimedeath:BAABLgAECn8UAAIaAAUJ9RRwJAAbAQAaAAUJ9RRwJAAbAQAAAA==.Sublimelife:BAAALgAECgEJAQAAAA==.Sukboytony:BAAALgADCgYJBgAAAA==.Sultanofswat:BAAALgADCgcJBwAAAA==.Sunnysideup:BAAALgAECgUJBQAAAA==.',
Sv='Svetlana:BAAALgAECgYJEQAAAA==.',
Sw='Swan:BAACLgAFFH8IAAIeAAMJ+QewfgC/AAAeAAMJ+QewfgC/AAAuAAQKfxYAAx4ABwk5EIGhAJQBAB4ABwk5EIGhAJQBACAAAwkHBE0MAGkAAAEuAAUUBAkQACEADg8A.Swordboardal:BAACLgAFFH8RAAIaAAMJHhaxFgDPAAAaAAMJHhaxFgDPAAAuAAQKfxsAAxoACQm8F8ULABsCABoACQm8F8ULABsCACUABQk4A3suAIIAAAAA.',
Sy='Sybius:BAAALgAECgEJAgAAAA==.Symptom:BAAALgAECgEJAQAAAA==.Syncophat:BAAALgADCgcJDQAAAA==.',
['Sé']='Séphórâ:BAAALgADCgMJBAAAAA==.',
Ta='Tachia:BAAALgAECgYJBgAAAA==.Tad:BAAALgAECgMJBgAAAA==.Taint:BAAALgADCgQJBgAAAA==.Takara:BAAALgADCgEJAQABLgAECgYJGgAIABIdAA==.Takia:BAABLgAECn8aAAMWAAYJowPBrADJAAAWAAYJowPBrADJAAAMAAMJwACYPQAjAAAAAA==.Talanzen:BAACLgAFFH8FAAIeAAMJLRm7ZQD8AAAeAAMJLRm7ZQD8AAAuAAQKfygAAh4ACQnOH0AfAI0CAB4ACQnOH0AfAI0CAAAA.Tanakiko:BAAALgADCgUJCQAAAA==.Tarrzok:BAAALgADCgcJBwABLgAECgkJJgAKAIkUAA==.',
Te='Teacup:BAAALgAECgUJBgABLgAECgkJJAAYAIYeAA==.Tellanji:BAAALgAECgQJBgAAAA==.',
Th='Theowyn:BAAALgADCgEJAQAAAA==.Thormarian:BAAALgADCgUJBwAAAA==.Thrakara:BAACLgAFFH8eAAImAAUJVxWoGQBUAQAmAAUJVxWoGQBUAQAuAAQKfzkAAiYACAmNHw4OAHUCACYACAmNHw4OAHUCAAAA.Thunderhorns:BAABLgAECn8fAAIMAAYJkQcJHAC5AAAMAAYJkQcJHAC5AAAAAA==.Thundrall:BAAALgAECgYJEgAAAA==.',
Ti='Tinionron:BAAALgADCgUJCAAAAA==.',
To='Toaster:BAAALgADCgQJBAABLgAFFAUJEgAZAHEZAA==.Toothléss:BAAALgADCgIJAgAAAA==.Toria:BAAALgAECgUJBgAAAA==.Torlania:BAAALgADCgYJBgAAAA==.',
Tr='Trayleen:BAAALgAECgMJBAAAAA==.Treeåj:BAABLgAECn8iAAMLAAgJ9gwKMgA4AQALAAgJ9gwKMgA4AQAJAAUJxARDkwCpAAAAAA==.Trilina:BAAALgADCgkJCAAAAA==.Truths:BAACLgAFFH8jAAMVAAcJ3xjJBADkAQAVAAcJ3xjJBADkAQAlAAEJcwCKOgAvAAAuAAQKfyQAAhUACAkJJYIIACMDABUACAkJJYIIACMDAAAA.Trystrom:BAAALgAECgIJAgAAAA==.',
Ts='Tsuo:BAACLgAFFH8UAAInAAUJsCGCBACRAQAnAAUJsCGCBACRAQAuAAQKfzgAAicACAkgJnQCAP4CACcACAkgJnQCAP4CAAAA.',
Tu='Tuhãn:BAAALgAECgEJAQAAAA==.',
Tw='Twixxed:BAAALgADCgYJCAABLgAECggJGgAQANMdAA==.',
Tx='Txjustice:BAAALgADCgUJDwAAAA==.',
Ty='Tymptriss:BAABLgAECn8aAAINAAYJ2QeYGwC1AAANAAYJ2QeYGwC1AAAAAA==.Tyrick:BAAALgAECgkJEAAAAA==.Tywen:BAAALgADCgEJAQAAAA==.',
Uh='Uhogpaladin:BAAALgADCgEJAQAAAA==.',
Um='Umbrage:BAACLgAFFH8QAAMNAAUJNhaSDwChAAAPAAQJdBLjZQDeAAANAAIJrRqSDwChAAAuAAQKfykABA0ACAmAIfoIADECAA0ABwnpHfoIADECAA8ACAkXHm8tABYCAA4AAQmWHSooAFEAAAAA.',
Un='Unholyblade:BAAALgADCgYJCgAAAA==.',
Ur='Urethrafrkln:BAAALgAECgIJAgAAAA==.',
Va='Vache:BAAALgADCgkJDQAAAA==.Valartha:BAABLgAECn8TAAILAAYJ3hZ2LgBMAQALAAYJ3hZ2LgBMAQAAAA==.Variol:BAABLgAECn8VAAIEAAcJ3QzsLwA4AQAEAAcJ3QzsLwA4AQAAAA==.Vaztek:BAAALgADCgMJAwAAAA==.',
Ve='Vecna:BAAALgAECgYJEAAAAA==.Vellarya:BAAALgADCgYJBgABLgAECgkJHgAcAG4hAA==.Vellmora:BAAALgAECgEJAQAAAA==.Velsea:BAAALgAECgMJBgAAAA==.Velstadt:BAABLgAECn8zAAITAAkJ7B8EBQDyAgATAAkJ7B8EBQDyAgAAAA==.Venhance:BAABLgAECn8gAAMbAAgJNxfAJACpAQAbAAgJNxfAJACpAQAcAAEJTBCKwQAvAAAAAA==.Venotu:BAABLgAECn8uAAICAAkJ+BxsBgBpAgACAAkJ+BxsBgBpAgAAAA==.Vermilion:BAABLgAECn8XAAIKAAYJHAjMogC+AAAKAAYJHAjMogC+AAAAAA==.Verso:BAAALgADCgcJEwAAAA==.',
Vh='Vholatile:BAAALgAECgYJCwAAAA==.',
Vi='Vinculum:BAAALgADCgIJAgAAAA==.Viviel:BAAALgAECgkJNAAAAQ==.',
Vo='Voidherron:BAAALgAECgYJCwAAAA==.Voidobscur:BAAALgADCgUJBQAAAA==.Voidwapa:BAAALgAECgQJCAAAAA==.Vonzilla:BAABLgAECn8kAAIDAAYJrRqJJQB+AQADAAYJrRqJJQB+AQAAAA==.Vorthael:BAABLgAECn8kAAIQAAcJcQY/twDzAAAQAAcJcQY/twDzAAAAAA==.Voxen:BAAALgADCgQJBAAAAA==.',
Vy='Vynirel:BAAALgAECgEJAQAAAA==.',
['Vö']='Vöid:BAAALgADCgcJBwAAAA==.',
Wa='Waarlow:BAAALgADCgEJAQAAAA==.Warlockbot:BAAALgAFFAEJAwAAAA==.Warmongral:BAABLgAECn8yAAIBAAgJShZySgDPAQABAAgJShZySgDPAQAAAA==.Waterboot:BAAALgAECgYJDwAAAA==.Wattheyneed:BAAALgADCgUJBQAAAA==.',
We='Wendi:BAABLgAECn8mAAINAAcJeQ0SEgAMAQANAAcJeQ0SEgAMAQAAAA==.',
Wh='Wheelchair:BAAALgADCgUJBQABLgAECgkJPwAMALQgAA==.Whipx:BAAALgADCgIJAgAAAA==.',
Wi='Wingsaber:BAABLgAECn89AAIBAAkJAxU+RgDbAQABAAkJAxU+RgDbAQAAAA==.Wisename:BAAALgAECgMJBgAAAA==.Withher:BAAALgADCgkJEAAAAA==.',
Wo='Wombo:BAABLgAECn8qAAIXAAkJxiOGAABKAwAXAAkJxiOGAABKAwAAAA==.Woolala:BAAALgAECgcJCAABLgAECgkJPgABAO4jAA==.',
Wr='Wrathran:BAABLgAECn8WAAIWAAgJuBIKRgC3AQAWAAgJuBIKRgC3AQAAAA==.',
Wu='Wut:BAAALgADCgkJCQABLgAECgkJOgAmAPcdAA==.',
Xa='Xahiri:BAAALgAECgEJAQAAAA==.',
Xl='Xlia:BAAALgAECgIJAgAAAA==.',
Ya='Yaeyo:BAAALgAECgcJDQAAAA==.Yazmat:BAACLgAFFH8HAAIZAAMJNBCgLACxAAAZAAMJNBCgLACxAAAuAAQKfykAAhkACQklHJ8LAMACABkACQklHJ8LAMACAAAA.Yazmyn:BAAALgAECggJDgAAAA==.',
Ye='Yeah:BAAALgADCgkJCQABLgAECgkJOgAmAPcdAA==.Yerehmi:BAAALgAECgMJBQAAAA==.',
Ym='Ymma:BAAALgADCgcJBwAAAA==.',
Yu='Yuny:BAABLgAECn8aAAImAAgJuAeJOQACAQAmAAgJuAeJOQACAQAAAA==.',
Yv='Yvendria:BAABLgAECn8uAAQOAAkJMRwzAgCdAgAOAAkJMRwzAgCdAgAPAAUJpQ+lmAACAQANAAEJAAAnagA+AAAAAA==.',
Za='Zacnafeen:BAAALgAECgMJAwAAAA==.Zaelessa:BAAALgAECgMJCQABLgAECgkJNAAHAAAAAQ==.Zaier:BAABLgAECn9QAAQZAAkJwCQBAwBFAwAZAAkJwCQBAwBFAwABAAQJ/hBm1wDKAAACAAEJxgOaVAAUAAAAAA==.Zaraelila:BAAALgADCgMJAwAAAA==.Zartart:BAAALgAECgkJBgAAAA==.',
Ze='Zeltan:BAABLgAECn8qAAMZAAgJ9hz2LwDCAQAZAAYJGxz2LwDCAQABAAgJsxHKXwCYAQAAAA==.Zeropriest:BAAALgADCgUJBQAAAA==.',
Zh='Zhundrenga:BAABLgAECn8aAAIRAAYJjgeXNQCoAAARAAYJjgeXNQCoAAAAAA==.',
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
