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

local lookup = {'Paladin-Protection','Priest-Shadow','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Druid-Feral','Druid-Restoration','DemonHunter-Devourer','Druid-Balance','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Priest-Discipline','Warrior-Fury','Paladin-Retribution','Hunter-BeastMastery','Rogue-Assassination','DeathKnight-Frost','Paladin-Holy','Warrior-Protection','Shaman-Restoration','Shaman-Enhancement','Mage-Frost','Mage-Arcane','Mage-Fire','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Shaman-Elemental','Monk-Mistweaver','Warrior-Arms','Druid-Guardian','Rogue-Subtlety',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abogato:BAAALgAECgQJBAAAAA==.',
Ae='Aedra:BAAALgADCgcJEgAAAA==.Aeowyyn:BAAALgAECggJEwAAAA==.',
Af='Af:BAAALgADCgUJBQAAAA==.',
Ah='Ahnir:BAAALgAECggJEgAAAA==.Ahnkhano:BAABLgAECn8dAAIBAAgJ8RFiEgCjAQABAAgJ8RFiEgCjAQAAAA==.',
Ai='Aidenarren:BAAALgADCgkJEAAAAA==.Ainge:BAAALgADCgUJBQAAAA==.Aiom:BAAALgADCgMJAwAAAA==.',
Ak='Akashaa:BAAALgADCgEJAQAAAA==.Akbartheiiv:BAACLgAFFH8YAAICAAcJ6hi4AQACAgACAAcJ6hi4AQACAgAuAAQKfy4AAgIACQllI3oDAPsCAAIACQllI3oDAPsCAAAA.',
Al='Allero:BAAALgAECgMJAwAAAA==.Allistrana:BAABLgAECn8iAAIDAAkJBRwzEwBGAgADAAkJBRwzEwBGAgAAAA==.Aluvia:BAAALgAECgIJBAAAAA==.',
Am='Amairis:BAAALgAECgQJCAAAAA==.Ambiorix:BAAALgADCgEJAQAAAA==.',
An='Anari:BAAALgADCgUJBQAAAA==.Angelsin:BAAALgADCgkJGwAAAA==.Animorph:BAAALgADCgcJJQAAAA==.Annestasia:BAAALgAECgcJCAAAAA==.Anrion:BAABLgAECn8nAAMEAAkJHyNGBAC+AgAEAAkJHyNGBAC+AgAFAAcJZxvVBgDKAQAAAA==.Anteater:BAAALgADCgEJAQABLgAECgUJDgAGAAAAAA==.',
Ap='Aph:BAAALgAECgcJDAAAAA==.Apolló:BAAALgAECgkJDgAAAA==.',
Ar='Araiana:BAAALgAECgEJAQAAAA==.Arayia:BAABLgAECn8UAAMHAAYJ9gsmFwD1AAAHAAYJ9gsmFwD1AAAIAAUJkA0iXgDWAAAAAA==.Arelian:BAABLgAECn8YAAMFAAgJqRPhCwBDAQAFAAYJmhbhCwBDAQAJAAgJMQsChwC9AAAAAA==.Aristia:BAABLgAECn8cAAMIAAgJSCPzCwDCAgAIAAgJSCPzCwDCAgAKAAEJzwytagAuAAABLgADCgYJCgAGAAAAAA==.Artaic:BAAALgAECgUJDgAAAA==.Artemysia:BAAALgADCgEJAQAAAA==.',
At='Ataboom:BAAALgADCgEJAQAAAA==.Ataliya:BAAALgAECgQJCgAAAA==.',
Au='Auranar:BAABLgAECn8VAAILAAcJqwbVEwDfAAALAAcJqwbVEwDfAAAAAA==.Aurilia:BAAALgAECgYJDgAAAA==.',
Av='Avanicus:BAABLgAECn8kAAQMAAkJhQr4DwD0AAAMAAcJbwn4DwD0AAANAAUJKApJEgDNAAAOAAQJqANj2gBUAAAAAA==.Aven:BAABLgAECn8XAAMPAAcJugxdfQAfAQAPAAcJTQxdfQAfAQAQAAUJ8QSgMwB4AAAAAA==.',
Ax='Axiomronin:BAABLgAECn8lAAMRAAkJTSTYAwDdAgARAAgJRyTYAwDdAgASAAgJJyK3DgCSAgAAAA==.',
Ay='Ayroon:BAAALgAECgQJBAAAAA==.',
Az='Azulien:BAABLgAECn8gAAITAAYJnwP7NQDVAAATAAYJnwP7NQDVAAAAAA==.Azuriel:BAAALgAECgIJAgAAAA==.',
Ba='Baltuk:BAABLgAECn8aAAIPAAgJ0x3YJgCgAgAPAAgJ0x3YJgCgAgAAAA==.Banderblitz:BAABLgAECn81AAIUAAkJSCGzBADgAgAUAAkJSCGzBADgAgAAAA==.Baobei:BAAALgADCgcJBwAAAA==.Bar:BAACLgAFFH8GAAMCAAMJBAbuEQCOAAACAAMJBAbuEQCOAAADAAMJlREtHQB7AAAuAAQKfxsAAgIACAlxGicVAEMCAAIACAlxGicVAEMCAAAA.Barunnar:BAAALgADCgEJAQAAAA==.',
Be='Bearlyshady:BAAALgADCgcJCwABLgAECgkJJgAJAIkUAA==.Bellatrixie:BAAALgADCggJGwAAAA==.Benafflock:BAABLgAECn8VAAQNAAgJZwjPCwAxAQANAAgJSAjPCwAxAQAOAAQJYwSY4QCXAAAMAAEJDw01MQAtAAABLgAECgcJEgAGAAAAAA==.Beriadhwen:BAAALgAECgUJBgAAAA==.Bermy:BAABLgAECn8WAAIMAAgJgQ8aJQAzAQAMAAgJgQ8aJQAzAQAAAA==.Bewildert:BAAALgADCgIJAgAAAA==.',
Bh='Bhawkwco:BAAALgADCgEJAQAAAA==.',
Bl='Blackhawkdk:BAABLgAECn8oAAIPAAkJHBoXIABEAgAPAAkJHBoXIABEAgAAAA==.Blende:BAABLgAECn8YAAIVAAcJ+SD6JwAZAgAVAAcJ+SD6JwAZAgAAAA==.Bloodshadow:BAABLgAECn8mAAIWAAgJHxTgOgCeAQAWAAgJHxTgOgCeAQAAAA==.Blueberrae:BAAALgADCgEJAQAAAA==.Bluemaster:BAAALgADCgYJBgAAAA==.',
Bo='Boidohanta:BAAALgADCgUJBQAAAA==.Bondarrex:BAAALgADCgYJBgAAAA==.',
Br='Braveharth:BAAALgAECgcJEgAAAA==.Braxus:BAAALgAECgMJBAAAAA==.Breakcooloz:BAACLgAFFH8QAAIXAAUJJSGrAQCAAQAXAAUJJSGrAQCAAQAuAAQKfyIAAhcACAmoIyIBADQDABcACAmoIyIBADQDAAEuAAUUBQkRAA8AsSMA.Brooce:BAABLgAECn8oAAIVAAgJpB7BHQBRAgAVAAgJpB7BHQBRAgAAAA==.Broom:BAAALgADCgkJHQABLgAECgkJLQALABAfAA==.',
Bu='Burstinurass:BAACLgAFFH8RAAIPAAUJsSN8GACSAQAPAAUJsSN8GACSAQAuAAQKfxcAAg8ACAmpJdoOALkCAA8ACAmpJdoOALkCAAAA.',
Ca='Caladorion:BAAALgAECgEJAQAAAA==.Candyjar:BAAALgADCgcJDAAAAA==.Cantmissyou:BAAALgAECgEJBgAAAA==.Capidk:BAAALgAFFAEJAQAAAA==.Carafe:BAAALgADCgEJAQABLgAECgYJGQAYALAhAA==.Carbonight:BAAALgADCgEJAQAAAA==.Carlos:BAAALgAECgUJDAABLgAECggJIAAVAKcgAA==.Caspianne:BAAALgAECgQJBgAAAA==.',
Cb='Cbrown:BAAALgAECgEJAQAAAA==.',
Ce='Celani:BAABLgAECn8fAAMDAAgJOBjPEQAIAgADAAgJOBjPEQAIAgATAAEJugFqXgAkAAAAAA==.Cellyne:BAABLgAECn8aAAMVAAcJIwb/pQDhAAAVAAcJIwb/pQDhAAAZAAIJJAIebgA2AAAAAA==.Centy:BAAALgAECgYJEgAAAA==.Ceredisam:BAAALgADCgcJBwAAAA==.',
Ch='Chaz:BAAALgAECgYJDQAAAA==.Chedrood:BAAALgADCgMJBwAAAA==.Chelives:BAEBLgAECn8YAAIaAAYJfQHfLwB3AAAaAAYJfQHfLwB3AAAAAA==.Chubrub:BAAALgAECgUJDgAAAA==.Chìef:BAAALgADCgEJAQAAAA==.',
Ci='Cires:BAAALgAECgEJAgAAAA==.',
Cl='Claud:BAAALgADCgcJCwAAAA==.Cleric:BAAALgADCgMJAwAAAA==.',
Co='Cobaltwolf:BAAALgAECgQJCAAAAA==.Colanasou:BAAALgAECgQJBwAAAA==.Coldbattler:BAAALgAECgYJEAAAAA==.Copelongcut:BAAALgADCgMJAQAAAA==.Corrick:BAAALgADCgcJEAAAAA==.',
Cr='Crow:BAAALgAECgkJHQAAAQ==.',
Cu='Curavis:BAAALgADCgMJAwAAAA==.',
Cy='Cydric:BAABLgAECn8iAAIVAAgJhyPFDAAoAwAVAAgJhyPFDAAoAwAAAA==.',
Da='Daarrkstar:BAABLgAECn8YAAMbAAYJ4yVTDwCHAgAbAAYJ4yVTDwCHAgAcAAMJrxB5IQC6AAABLgAECgcJGAAVAPkgAA==.Daenyra:BAAALgADCgUJBQAAAA==.Dakarai:BAAALgADCggJDgAAAA==.Danek:BAAALgADCggJGQAAAA==.Darkane:BAABLgAFFH8FAAMWAAUJGwK6QgCzAAAWAAQJrQK6QgCzAAALAAEJZgBtJQAsAAAAAA==.Darocate:BAAALgADCgYJBgAAAA==.Dathanarr:BAAALgAECggJCAAAAA==.',
De='Deadskvll:BAAALgADCgYJBgAAAA==.Deathbot:BAACLgAFFH8NAAIQAAQJBBK6EQD+AAAQAAQJBBK6EQD+AAAuAAQKf0EAAhAACQniICoDANsCABAACQniICoDANsCAAAA.Demira:BAAALgADCgMJAwAAAA==.Demoray:BAACLgAFFH8KAAILAAUJvBiZCACSAQALAAUJvBiZCACSAQAuAAQKfxQAAgsABwl0JB0VAIoCAAsABwl0JB0VAIoCAAAA.Dendrin:BAAALgADCgEJAQAAAA==.Deneese:BAAALgAECgIJAgAAAA==.Desniee:BAABLgAECn8gAAQdAAkJMh91QwBuAgAdAAkJMh91QwBuAgAeAAIJHA3jFAB3AAAfAAEJuxW+DgA/AAAAAA==.Dethrone:BAABLgAECn8UAAQMAAgJihjiIABNAQAMAAYJ5xniIABNAQAOAAYJDhUroQAWAQANAAEJXBYtLgBCAAAAAA==.',
Di='Digitpro:BAABLgAECn8tAAIgAAgJVQ61GACQAQAgAAgJVQ61GACQAQAAAA==.Dirtydragon:BAABLgAECn8gAAMhAAgJTRs9BgBiAgAhAAgJTRs9BgBiAgAiAAEJhwdmZQArAAAAAA==.Disturbo:BAAALgADCgYJBgAAAA==.Divinedecay:BAAALgAECgYJEgABLgAECgkJMAAWAGwVAA==.',
Do='Dok:BAAALgADCgcJBwAAAA==.Donoraginn:BAAALgADCgkJHwABLgADCgkJMAAGAAAAAA==.Donos:BAAALgADCgkJMAAAAA==.Dontkare:BAAALgADCgcJEQABLgAECgkJKgAaAJwlAA==.Doomjuele:BAAALgADCgYJBgAAAA==.Dorsai:BAAALgADCgUJBQAAAA==.Dott:BAAALgADCgIJAgABLgAECggJEgAGAAAAAA==.',
Dr='Draazzy:BAAALgADCgkJEgAAAA==.Dracbanti:BAAALgADCgkJEQAAAA==.Dracobelle:BAABLgAECn8ZAAIhAAYJ2RtOCwDaAQAhAAYJ2RtOCwDaAQAAAA==.Drark:BAAALgADCgQJBAAAAA==.Drathiel:BAAALgAECgMJAwAAAA==.Drazlowe:BAAALgADCgQJBwAAAA==.Dreezee:BAAALgAECgIJBQAAAA==.Drizztknight:BAAALgADCgEJAQAAAA==.Droobear:BAAALgAECgIJAgAAAA==.Drwho:BAABLgAECn8gAAIdAAYJ5BjYZQBxAQAdAAYJ5BjYZQBxAQAAAA==.Dràco:BAAALgADCggJDwAAAA==.Drääx:BAAALgADCggJCAAAAA==.Dräëxx:BAAALgADCgcJDQAAAA==.',
Du='Durimli:BAAALgADCgYJBwAAAA==.',
Dw='Dwayneb:BAAALgAECgkJBwAAAA==.',
['Dô']='Dôz:BAAALgADCgQJBAAAAA==.',
Ea='Earthernbot:BAAALgAECgYJCAAAAA==.Earthspeaker:BAAALgADCgEJAQAAAA==.',
El='Elfadwagon:BAACLgAFFH8RAAIjAAQJMhvfAQBYAQAjAAQJMhvfAQBYAQAuAAQKfyQAAiMACAlcIa8CAAIDACMACAlcIa8CAAIDAAAA.Eliptical:BAAALgAECgYJEwABLgAECggJGwAVAO4eAA==.Elkesey:BAAALgADCgEJAQAAAA==.Elonura:BAAALgADCgYJBgAAAA==.Elunea:BAAALgADCggJCgAAAA==.',
Em='Emishanot:BAAALgAECgEJAQABLgAECgYJEQAGAAAAAA==.',
Ep='Epoch:BAAALgADCgEJAQAAAA==.',
Er='Erangar:BAAALgAECgYJDgAAAA==.Erdor:BAAALgADCgcJDgAAAA==.Erred:BAAALgADCgcJBwAAAA==.',
Es='Esmer:BAABLgAECn8tAAIVAAkJJwqCUACNAQAVAAkJJwqCUACNAQAAAA==.',
Et='Etheman:BAAALgAECgcJDQAAAA==.',
Eu='Euphrasie:BAAALgADCgUJBQABLgAECggJHAAbAH0jAA==.',
Ev='Eversteal:BAAALgADCgQJBAABLgAECgYJHwABAJkgAA==.Evholker:BAABLgAECn8bAAMjAAgJ+xBpCQBHAQAjAAgJ6RBpCQBHAQAiAAUJnA6URADCAAAAAA==.',
Ex='Excuses:BAAALgAECgYJDAABLgAFFAcJIQAUAN8YAA==.Executey:BAAALgADCgQJBAAAAA==.Exhumina:BAAALgAECgYJBgAAAA==.',
Fa='Facestealerr:BAAALgAECgYJDgAAAA==.Fallenhullkk:BAAALgADCgYJBgAAAA==.Fangyi:BAAALgADCgYJBgAAAA==.',
Fe='Feetsmell:BAAALgADCgkJEgABLgAECgkJLQALABAfAA==.Felmufín:BAABLgAECn8cAAIOAAgJQQy4WQBSAQAOAAgJQQy4WQBSAQAAAA==.Felspury:BAAALgAECgEJAQABLgAFFAMJBQAdAFALAA==.',
Fi='Fibula:BAAALgADCgcJBwAAAA==.',
Fl='Flairrick:BAABLgAECn8aAAIUAAcJux7bEgASAgAUAAcJux7bEgASAgAAAA==.Flars:BAAALgAECgcJDQAAAA==.Flatliner:BAACLgAFFH8FAAIZAAMJiAWGJACvAAAZAAMJiAWGJACvAAAuAAQKfzkAAxkACAk1DiM0AK0BABkACAk1DiM0AK0BABUAAQmlCV9TASoAAAAA.Floracide:BAAALgAECgQJBAAAAA==.',
Fo='Foid:BAAALgAECgYJBwAAAA==.',
Fr='Fran:BAAALgADCgYJBgABLgAECgkJLQALABAfAA==.Frankzappn:BAAALgAECgQJBAAAAA==.Fray:BAABLgAECn8dAAIJAAgJshoiIgADAgAJAAgJshoiIgADAgAAAA==.Freeguy:BAABLgAECn8eAAIJAAgJ5RrmJADzAQAJAAgJ5RrmJADzAQAAAA==.',
Fu='Fuddicus:BAABLgAECn85AAMbAAgJ3yT7CgDNAgAbAAgJ3yT7CgDNAgAkAAEJGRI9gwA9AAAAAA==.Fuddmore:BAAALgAECgEJAQABLgAECgQJBwAGAAAAAA==.Fuddster:BAAALgAECgQJBwAAAA==.',
Ga='Gaddess:BAABLgAECn8YAAICAAYJEAf3OQDWAAACAAYJEAf3OQDWAAAAAA==.Ganath:BAAALgAECgMJAwAAAA==.Ganymede:BAAALgAECgYJDQAAAA==.Garan:BAAALgADCgQJBAAAAA==.Garnar:BAAALgADCgIJAgAAAA==.',
Ge='Geilamaine:BAABLgAECn8eAAIZAAgJTx6XBwDRAgAZAAgJTx6XBwDRAgAAAA==.',
Gi='Gimpy:BAAALgAECgQJBQAAAA==.',
Gl='Glimagi:BAAALgADCgcJDwAAAA==.Glimdaemon:BAAALgAECgIJAgAAAA==.',
Go='Gonefishing:BAABLgAECn87AAIVAAkJ7iPaBQAVAwAVAAkJ7iPaBQAVAwAAAA==.Gorddownie:BAABLgAECn8UAAIKAAYJ+wIXTQCAAAAKAAYJ+wIXTQCAAAAAAA==.',
Gr='Graied:BAAALgAECgYJBgAAAA==.Grellior:BAAALgAECgEJAQAAAA==.Grippysocks:BAACLgAFFH8QAAIZAAUJcRkCDQCDAQAZAAUJcRkCDQCDAQAuAAQKfzMAAhkACAnKGBIcADQCABkACAnKGBIcADQCAAAA.',
Gu='Gummibear:BAAALgAECgcJEwAAAA==.',
Ha='Hakar:BAAALgAECgYJCAAAAA==.Hanoa:BAAALgADCgIJAgAAAA==.Harthoon:BAACLgAFFH8UAAIdAAUJwA1HQQA4AQAdAAUJwA1HQQA4AQAuAAQKfzkAAh0ACAnIHvAoADQCAB0ACAnIHvAoADQCAAAA.Haruharu:BAAALgAECgMJCwAAAA==.Hawkhogan:BAAALgADCgYJCQAAAA==.Hazdanzul:BAAALgADCgQJBQABLgAECgYJEQAGAAAAAA==.',
He='Hehexxd:BAAALgAECgIJAgAAAA==.Helias:BAAALgADCgkJBgAAAA==.Hemp:BAAALgADCgEJAQAAAA==.Herrondale:BAAALgADCgcJBwAAAA==.Hey:BAAALgADCgkJIwABLgAECgkJLgAlAPgdAA==.',
Hj='Hjukonlikjuj:BAAALgAECgEJAQAAAA==.',
Ho='Hollanov:BAAALgADCgYJBgAAAA==.Honeynoats:BAABLgAECn8eAAIDAAcJ5AhrLAAeAQADAAcJ5AhrLAAeAQAAAA==.Honks:BAAALgAECgEJAgAAAA==.Hotdwarf:BAAALgAECgcJCwAAAA==.',
Hu='Hubbabubbles:BAAALgADCggJCAAAAA==.Hullkk:BAACLgAFFH8UAAMUAAUJ9iLtCwBZAQAUAAQJ8hvtCwBZAQAmAAQJEiB7DAAYAQAuAAQKfzcAAxQACAmKJokFAE4DABQACAnOJYkFAE4DACYABwkQJEIDALACAAAA.Hundale:BAAALgAECgQJBAAAAA==.Hutchkins:BAABLgAECn8pAAMOAAgJ7hxPLQBYAgAOAAgJ7hxPLQBYAgANAAEJAAAPLQAAAAAAAA==.Hutchknight:BAAALgAECgUJDAABLgAECggJKQAOAO4cAA==.Hutchyo:BAAALgADCgQJBAABLgAECggJKQAOAO4cAA==.',
Hy='Hydro:BAABLgAECn8mAAMVAAgJAx1OOwDNAQAVAAgJAx1OOwDNAQABAAQJNQ/RIQCwAAAAAA==.',
['Hä']='Häwtz:BAAALgADCgIJAgAAAA==.',
Ia='Iamhealer:BAAALgADCgMJAgAAAA==.',
In='Inari:BAAALgAECgQJBwABLgAECggJIwAWAGUWAA==.Inseng:BAABLgAECn8XAAMQAAgJJB7+EAClAQAQAAYJHx7+EAClAQAYAAgJNxdCCQB0AQAAAA==.Invasion:BAAALgAECgYJDAAAAA==.',
Ix='Ixy:BAABLgAECn8bAAIJAAgJEhovJAD3AQAJAAgJEhovJAD3AQAAAA==.',
Ja='Jahde:BAABLgAECn8iAAIIAAcJwQrpSgAbAQAIAAcJwQrpSgAbAQAAAA==.Jahoda:BAAALgADCgYJBgAAAA==.Jaina:BAAALgAECgQJBAAAAA==.Jamer:BAABLgAECn8VAAIaAAUJZCFyEgBzAQAaAAUJZCFyEgBzAQAAAA==.Jassykins:BAABLgAECn8WAAIWAAcJYQtAYwAiAQAWAAcJYQtAYwAiAQAAAA==.',
Je='Jeewop:BAAALgADCgEJAQAAAA==.Jeongaegdeom:BAAALgADCgcJDgAAAA==.Jessecuster:BAAALgAECgUJBgAAAA==.',
Ji='Jinjerr:BAAALgAECgYJCgAAAA==.',
Jo='Joloc:BAABLgAECn8UAAIMAAYJyAhsFwCwAAAMAAYJyAhsFwCwAAAAAA==.Jozay:BAAALgAECgYJDAAAAA==.',
Ju='Juancarlos:BAAALgADCgEJAQAAAA==.',
Ka='Kaidaa:BAAALgAECgQJBAAAAA==.Kalasparkle:BAAALgAECgQJAwAAAA==.Kalrosa:BAABLgAECn8ZAAIUAAYJ4iJYGQDUAQAUAAYJ4iJYGQDUAQABLgAECgkJNQAUAEghAA==.Kare:BAABLgAECn8qAAIaAAkJnCVVAQAsAwAaAAkJnCVVAQAsAwAAAA==.Karee:BAABLgAECn8XAAIBAAcJEiGUCgDKAQABAAcJEiGUCgDKAQABLgAECgkJKgAaAJwlAA==.Kathilnas:BAAALgADCgUJBQABLgAECgYJEQAGAAAAAA==.',
Kc='Kcosfomas:BAAALgADCgIJAgAAAA==.',
Ke='Kebob:BAAALgADCgcJCAAAAA==.Kermodrood:BAABLgAECn8mAAMKAAgJlyKMBwCWAgAKAAgJliKMBwCWAgAnAAQJRyJbFgAlAQAAAA==.',
Kh='Khanthurs:BAAALgAECgQJBAAAAA==.Kholdbrew:BAAALgAECgUJBQAAAA==.',
Ki='Kiizo:BAABLgAECn8fAAIoAAgJ7hR8EwCzAQAoAAgJ7hR8EwCzAQAAAA==.Kilnot:BAAALgAECgcJEwAAAA==.Kinstine:BAABLgAECn8VAAIQAAYJ/wFMMgCtAAAQAAYJ/wFMMgCtAAAAAA==.',
Ko='Koltara:BAAALgAFFAEJAgABLgAFFAQJDwARAE4fAA==.Koltaris:BAACLgAFFH8PAAIRAAQJTh9jDgBZAQARAAQJTh9jDgBZAQAuAAQKfyIAAhEACAl2JKAFAK8CABEACAl2JKAFAK8CAAAA.Konshis:BAACLgAFFH8FAAMlAAMJXQikIQCsAAAlAAMJXQikIQCsAAASAAEJqQWQKgA8AAAuAAQKfyIAAiUACAn7FEUjAIABACUACAn7FEUjAIABAAAA.Kookymonster:BAABLgAECn81AAMOAAkJoyEYCgDSAgAOAAgJ0iAYCgDSAgAMAAcJlh2CBwBPAgAAAA==.Korbyn:BAAALgADCgkJCQAAAA==.Kos:BAACLgAFFH8QAAMPAAUJng3VRAAvAQAPAAQJng3VRAAvAQAQAAEJAABoPAAAAAAuAAQKfxcAAw8ACAl6H+4hADoCAA8ACAl6H+4hADoCABgAAgmaGR8YAIMAAAAA.',
Ku='Kuragaru:BAACLgAFFH8SAAMoAAUJDiCvCQBuAQAoAAUJDiCvCQBuAQAXAAIJbwxWBACsAAAuAAQKfzgAAygACAm0JHYEALICACgACAm0JHYEALICABcACAlqGicFAEMCAAAA.',
Ky='Kyoubouna:BAAALgAECgQJBAAAAA==.Kyoxi:BAAALgADCgEJAQAAAA==.',
La='Larianne:BAAALgAECgcJEgAAAA==.',
Le='Leese:BAABLgAECn8bAAIKAAYJcgiOOwDKAAAKAAYJcgiOOwDKAAAAAA==.Leretic:BAAALgAECgYJBgABLgAECggJGwAVAO4eAA==.Lerion:BAABLgAECn8bAAIVAAgJ7h4fEgABAwAVAAgJ7h4fEgABAwAAAA==.Lester:BAABLgAECn8iAAICAAgJwBmzEAAEAgACAAgJwBmzEAAEAgAAAA==.Lethana:BAAALgADCgcJDAAAAA==.',
Li='Liamsun:BAABLgAECn9AAAQlAAkJJhWpEwAQAgAlAAkJJhWpEwAQAgARAAgJShY5FADPAQASAAYJuxT4PwAZAQAAAA==.Lidd:BAAALgAECgQJAwAAAA==.Lidrael:BAABLgAECn8zAAQFAAkJxh17AgCOAgAFAAkJxh17AgCOAgAEAAYJNAX+QgDsAAAJAAYJewpXmwDiAAAAAA==.Lidrahl:BAAALgADCgcJDQAAAA==.Liekos:BAAALgAECgMJCAAAAA==.Lightbloom:BAAALgAECgIJBQAAAA==.Liliria:BAABLgAECn8xAAIDAAkJWhjmDwAhAgADAAkJWhjmDwAhAgAAAA==.Lillidân:BAAALgAECgYJEQABLgAFFAIJBQAdABsVAA==.Lingwong:BAAALgAECgEJAgAAAA==.Litebite:BAAALgAECgUJBQAAAA==.Littlefish:BAAALgADCgcJDwAAAA==.',
Lj='Ljaeì:BAABLgAECn8cAAICAAgJ5BfTFADWAQACAAgJ5BfTFADWAQAAAA==.',
Ll='Lloreth:BAABLgAECn8ZAAIIAAgJeQlaSAAlAQAIAAgJeQlaSAAlAQAAAA==.',
Ln='Lnpoop:BAAALgAECgcJDgAAAA==.',
Lo='Locknload:BAAALgADCgMJAwAAAA==.Lockwood:BAABLgAECn8aAAIoAAgJTAvqGwBbAQAoAAgJTAvqGwBbAQAAAA==.Lominar:BAAALgADCgcJBwAAAA==.Lorelei:BAABLgAECn8YAAIWAAYJKA0FcAADAQAWAAYJKA0FcAADAQAAAA==.Lorrellia:BAAALgAECggJEQAAAA==.',
Lu='Lucariõ:BAACLgAFFH8TAAIDAAYJXxV2AwDLAQADAAYJXxV2AwDLAQAuAAQKfxYAAgMACAkXHpMNAH8CAAMACAkXHpMNAH8CAAAA.Lumina:BAABLgAECn8UAAIBAAYJ7hoeDwB5AQABAAYJ7hoeDwB5AQAAAA==.Lunaría:BAAALgADCgUJBgAAAA==.Lustydragon:BAAALgADCgEJAQAAAA==.',
Ly='Lyllies:BAAALgAECgIJAgAAAA==.Lysergia:BAABLgAECn8cAAIbAAgJfSN5CQDRAgAbAAgJfSN5CQDRAgAAAA==.',
['Lì']='Lìght:BAACLgAFFH8OAAIZAAQJQBwkFQAtAQAZAAQJQBwkFQAtAQAuAAQKfyAAAhkABwnBH1EWAAwCABkABwnBH1EWAAwCAAAA.',
Ma='Madrona:BAAALgAECgQJBQAAAA==.Magnumrex:BAAALgADCgUJBQAAAA==.Mahoney:BAAALgAECgUJBQAAAA==.Majestynihil:BAAALgADCggJCAAAAA==.Makkazul:BAABLgAECn8gAAMPAAgJnBciPwDAAQAPAAgJfRciPwDAAQAYAAUJ3hVdDwD9AAAAAA==.Maladia:BAAALgADCgkJCQAAAA==.Management:BAAALgADCgQJBAAAAA==.Mangler:BAABLgAECn8UAAIkAAYJcAQuTACtAAAkAAYJcAQuTACtAAAAAA==.Marrad:BAAALgAECgQJBAAAAA==.Marrok:BAAALgAECgcJBwAAAA==.Marunji:BAAALgAECgYJEQAAAA==.Matcauthon:BAAALgAECgQJCAAAAA==.Matrim:BAAALgAECgQJBQAAAA==.Mattdæmon:BAABLgAECn8fAAMEAAgJMwtuGgBDAQAEAAgJMwtuGgBDAQAJAAIJpwLF2AA+AAAAAA==.Mattmattmatt:BAAALgADCgEJAQAAAA==.Mazzak:BAAALgADCgMJBgAAAA==.',
Me='Meanit:BAAALgAECgQJBgAAAA==.Meekogaia:BAABLgAECn8zAAIbAAgJYCKYCQDPAgAbAAgJYCKYCQDPAgAAAA==.Meekosan:BAAALgAECgQJBgAAAA==.Melestaris:BAAALgADCgYJBgAAAA==.',
Mi='Mihlenna:BAAALgADCgcJBwAAAA==.Millerowntoo:BAAALgAFFAIJAwABLgAFFAMJCwAWAP8mAA==.Mimzy:BAAALgAECgEJAgAAAA==.Minarmo:BAAALgADCgEJAQAAAA==.Mingzi:BAAALgAECgYJDwAAAA==.Missanabie:BAAALgADCgcJBwAAAA==.Missymeow:BAAALgADCgYJDAAAAA==.Mital:BAAALgADCgEJAQAAAA==.Mizu:BAEALgAECgEJAgABLgAECgkJIAAjAGQRAA==.',
Mm='Mmbear:BAAALgAECgEJAQABLgAFFAUJGAAVAK4VAA==.',
Mo='Mojeen:BAAALgADCgIJAgAAAA==.Monkoko:BAAALgADCgEJAgAAAA==.Montkriege:BAABLgAECn8UAAUIAAYJdQtoVQD1AAAIAAYJdQtoVQD1AAAKAAUJpwLTZACOAAAHAAIJoxJgKgB1AAAnAAEJJxpjLABGAAAAAA==.Moonsocks:BAAALgAECgUJBQABLgAFFAUJEAAZAHEZAA==.Moxxie:BAABLgAECn8WAAMKAAcJMhaIJwA2AQAKAAYJsBWIJwA2AQAHAAEJvRivLABKAAAAAA==.',
Mu='Mufín:BAAALgAECgYJCQAAAA==.Murfie:BAABLgAECn8WAAMCAAgJ5xYzIwC+AQACAAgJ5xYzIwC+AQADAAQJWgyDWQDOAAAAAA==.Murica:BAAALgADCgEJAQABLgAECgkJLQALABAfAA==.',
My='Mythosrex:BAAALgAECgcJBgAAAA==.',
['Mâ']='Mâjôr:BAAALgADCgUJBQAAAA==.',
['Mì']='Mìr:BAACLgAFFH8SAAIJAAUJEBQ4JwAvAQAJAAUJEBQ4JwAvAQAuAAQKfzIAAwkACAlcIXUTAGYCAAkACAlcIXUTAGYCAAQABgn7EB02AC8BAAAA.',
['Mó']='Mónkass:BAAALgAECgEJAQAAAA==.',
Na='Naitho:BAAALgAECgYJBgAAAA==.Nakedfeet:BAAALgADCgEJAQABLgAFFAUJEAAZAHEZAA==.Narena:BAAALgADCgYJBgAAAA==.Nashira:BAABLgAECn8dAAIbAAgJTgm4RQAzAQAbAAgJTgm4RQAzAQAAAA==.Nashness:BAACLgAFFH8GAAMPAAMJwxj9VgABAQAPAAMJwxj9VgABAQAYAAIJOQf+DACPAAAuAAQKfzIAAw8ACQkOIwcQAB0DAA8ACQkOIwcQAB0DABgAAQnUI/QaAGMAAAAA.Natharion:BAABLgAECn82AAMNAAkJkxiVAgCTAgANAAkJhRiVAgCTAgAOAAgJWAimaQArAQAAAA==.Nazrogul:BAABLgAECn8VAAIPAAYJXwg+sgAeAQAPAAYJXwg+sgAeAQAAAA==.',
Ne='Nerfme:BAAALgAECgYJBwAAAA==.Nezar:BAAALgADCgcJEQAAAA==.',
Ni='Ninjaxe:BAACLgAFFH8MAAISAAQJkhBaEQD1AAASAAQJkhBaEQD1AAAuAAQKfyIAAxIACAnLH94JANoCABIACAnLH94JANoCABEAAQkmCD+VACAAAAEuAAUUBQkFABYAGwIA.Ninkharak:BAAALgADCgEJAQAAAA==.Nishal:BAAALgAECgMJBAABLgAECgkJOQAbALcdAA==.Niterage:BAAALgADCgYJDQAAAA==.',
Nn='Nn:BAABLgAECn8aAAInAAcJ2wyqHwDMAAAnAAcJ2wyqHwDMAAAAAA==.',
No='Novachrono:BAAALgADCgEJAQAAAA==.',
Nu='Nu:BAAALgAECgQJBAAAAA==.Nuckinphutz:BAAALgADCgYJCwAAAA==.Nullthor:BAABLgAECn8UAAIcAAYJ7xM5FAB3AQAcAAYJ7xM5FAB3AQAAAA==.Nurfd:BAABLgAECn8UAAIaAAYJcAF/LwB5AAAaAAYJcAF/LwB5AAAAAA==.',
['Nè']='Nègan:BAABLgAECn8vAAIWAAgJ1hT9NADbAQAWAAgJ1hT9NADbAQAAAA==.',
['Nô']='Nôyar:BAAALgAECgQJBQAAAA==.',
Ob='Obamakare:BAAALgAECgYJDQABLgAECgkJKgAaAJwlAA==.',
Od='Odinrex:BAABLgAECn8cAAIWAAcJgxbgQACJAQAWAAcJgxbgQACJAQAAAA==.',
Og='Ogmattbone:BAAALgADCgMJAQAAAA==.',
Op='Opuntia:BAAALgAECgYJCwAAAA==.',
Ou='Ouch:BAAALgADCgMJAwAAAA==.Outofarrows:BAABLgAECn8tAAMLAAkJEB8MAgCuAgALAAkJEB8MAgCuAgAgAAEJXwmRLgA4AAAAAA==.',
Ow='Ow:BAAALgADCgEJAQABLgADCgMJAwAGAAAAAA==.Ownown:BAAALgAECgIJAgABLgAFFAMJCwAWAP8mAA==.',
Pa='Palinuttz:BAAALgAECgMJAwAAAA==.Pallypaladin:BAACLgAFFH8YAAIVAAUJrhUVIQBEAQAVAAUJrhUVIQBEAQAuAAQKfyEAAhUACQnUH+4UAIgCABUACQnUH+4UAIgCAAAA.Pasteeater:BAAALgAECgQJBAAAAA==.',
Pe='Pernelope:BAABLgAECn8iAAIJAAcJ7RvRRADgAQAJAAcJ7RvRRADgAQAAAA==.',
Ph='Phatzero:BAABLgAECn8wAAMWAAkJbBUqJwDzAQAWAAkJbBUqJwDzAQALAAIJMgSoKwA7AAAAAA==.Phöenix:BAAALgAECgEJAQAAAA==.',
Pi='Piedra:BAAALgADCgYJDAAAAA==.Pierogi:BAAALgADCgUJBQAAAA==.Piety:BAAALgAECgIJAgAAAA==.Pinjo:BAAALgAECgEJBAAAAA==.',
Po='Polarnomad:BAAALgADCgYJCwABLgAECggJFwAdABkTAA==.Polarr:BAABLgAECn8XAAIdAAgJGRNkzwBNAQAdAAgJGRNkzwBNAQAAAA==.Polydrake:BAAALgAECgYJBwAAAA==.Popsicles:BAAALgAECgUJBQAAAA==.',
Pr='Prismatic:BAAALgAECgMJBAAAAA==.Probablyblue:BAAALgAECgYJCQAAAA==.Proofy:BAAALgAECgcJDwAAAA==.Prowl:BAAALgADCgYJBgABLgAECgYJCwAGAAAAAA==.',
Ps='Psyop:BAAALgADCgkJEQABLgAECggJDQAGAAAAAA==.',
Pu='Punchkick:BAAALgADCgcJBwAAAA==.Punchup:BAABLgAECn8YAAISAAcJAgqMLAAKAQASAAcJAgqMLAAKAQAAAA==.',
Py='Pythie:BAAALgAECgEJAQAAAA==.',
Ra='Rabit:BAAALgAECgQJCAAAAA==.Ramsey:BAAALgADCgEJAQAAAA==.Rastputin:BAAALgAECgkJDgAAAA==.',
Re='Rebrex:BAAALgADCgcJBwAAAA==.Redpyro:BAAALgADCgcJDwAAAA==.Ren:BAAALgAECgEJAQAAAA==.Retrïbutor:BAAALgAECgYJCgAAAA==.',
Rf='Rf:BAAALgAECgEJAQAAAA==.',
Rh='Rhodraco:BAABLgAECn8ZAAMiAAYJQQnzQwDFAAAiAAYJQAjzQwDFAAAjAAQJIgp2EwCIAAAAAA==.',
Ri='Rinela:BAABLgAECn8fAAIKAAgJDhz7GQA2AgAKAAgJDhz7GQA2AgAAAA==.Riotdrill:BAAALgADCgYJBwAAAA==.',
Rj='Rj:BAABLgAECn8dAAIIAAcJoiGCDwCVAgAIAAcJoiGCDwCVAgAAAA==.',
Ro='Robi:BAAALgADCgEJAQABLgAECgcJGAAVAPkgAA==.Rolandrex:BAAALgAECgEJAQAAAA==.Romulusinc:BAAALgADCgMJBgAAAA==.Rosabee:BAABLgAECn8iAAIDAAgJbRHmGAC7AQADAAgJbRHmGAC7AQAAAA==.',
Rp='Rp:BAAALgAECgMJAwAAAA==.',
Rq='Rq:BAAALgADCgYJBgAAAA==.',
Rt='Rtfreshness:BAAALgAECgYJBgAAAA==.',
Ru='Runswithheal:BAAALgAECgQJBQAAAA==.',
Ry='Ryyukken:BAAALgAECgYJCQAAAA==.',
['Rà']='Ràndòm:BAAALgADCgIJAgABLgAFFAgJHQAdAH8dAA==.Ràwrshåk:BAAALgADCgYJBgAAAA==.',
['Rá']='Rándom:BAAALgAFFAMJAwABLgAFFAgJHQAdAH8dAA==.',
['Ró']='Rónin:BAAALgAFFAEJAgAAAA==.',
Sa='Sago:BAAALgAECgMJBAAAAA==.Sanzen:BAABLgAECn8ZAAMSAAYJsRvIIgDAAQASAAYJsRvIIgDAAQAlAAMJsgcVWQBqAAAAAA==.Sauce:BAABLgAECn8uAAIlAAkJ+B1HBQAAAwAlAAkJ+B1HBQAAAwAAAA==.',
Sc='Scrubz:BAABLgAECn8aAAInAAkJixrVBwA2AgAnAAkJixrVBwA2AgAAAA==.',
Se='Senile:BAABLgAECn8aAAIfAAcJlhKrAwB2AQAfAAcJlhKrAwB2AQAAAA==.Seydori:BAAALgADCgUJDAAAAA==.',
Sh='Shadydice:BAAALgADCgYJBgABLgAECgkJJgAJAIkUAA==.Shadylid:BAABLgAECn8mAAMJAAkJiRSsJwDkAQAJAAkJiRSsJwDkAQAFAAMJVQk4GwBvAAAAAA==.Shadówglider:BAAALgAECgYJDgAAAA==.Shale:BAABLgAECn8WAAIJAAgJdiH2OgAIAgAJAAgJdiH2OgAIAgAAAA==.Shamallaman:BAAALgAECgEJAQABLgAECgkJJAAVACEkAA==.Shameless:BAAALgAFFAIJAgAAAA==.Sharkina:BAAALgADCgUJBQAAAA==.Sharkweek:BAAALgAECgQJBQAAAA==.Sheyoni:BAAALgAECgMJAwAAAA==.Shreck:BAAALgAECgQJBgAAAA==.',
Sk='Skikette:BAAALgADCggJJwAAAA==.Skinrot:BAABLgAECn8wAAIIAAkJag5lKwC1AQAIAAkJag5lKwC1AQAAAA==.',
Sm='Smig:BAAALgAECgEJBAAAAA==.',
So='Soeki:BAABLgAECn8aAAIMAAcJiwu/DgAHAQAMAAcJiwu/DgAHAQAAAA==.Solux:BAAALgAFFAMJBAABLgAFFAUJDgAMADYWAA==.Soullove:BAABLgAECn8+AAIMAAgJshX4BgCZAQAMAAgJshX4BgCZAQAAAA==.Soullovez:BAABLgAECn8YAAMKAAcJOwpgNADsAAAKAAcJOwpgNADsAAAIAAIJGgq7lQBOAAABLgAECggJPgAMALIVAA==.Soulshocks:BAABLgAECn8sAAIkAAgJpQ/NJQBkAQAkAAgJpQ/NJQBkAQABLgAECggJPgAMALIVAA==.Soulviver:BAABLgAECn8tAAIDAAgJ8RF2GQC2AQADAAgJ8RF2GQC2AQAAAA==.',
Sp='Sparkelly:BAAALgADCgEJAQAAAA==.Spicytuna:BAAALgADCgYJBgAAAA==.Spliffy:BAAALgADCgYJBgAAAA==.Spurey:BAACLgAFFH8FAAIdAAMJUAt9YADgAAAdAAMJUAt9YADgAAAuAAQKfy8AAx4ACQn6HjoDAEUCAB4ACAk1GjoDAEUCAB0ACQnHGWFHAMIBAAAA.Spurylock:BAAALgADCggJDQABLgAFFAMJBQAdAFALAA==.',
St='Starstreak:BAAALgADCgUJBQABLgAECggJMAAdALQSAA==.Stimer:BAABLgAECn8wAAMUAAkJ6x+/BgA8AwAUAAkJ1B+/BgA8AwAmAAgJCx0UCgD2AQAAAA==.Stuipd:BAAALgADCgYJCQAAAA==.',
Su='Sublimedeath:BAABLgAECn8UAAIaAAUJ9RRwJAAbAQAaAAUJ9RRwJAAbAQAAAA==.Sublimelife:BAAALgAECgEJAQAAAA==.Sukboytony:BAAALgADCgYJBgAAAA==.Sultanofswat:BAAALgADCgcJBwAAAA==.Sunnysideup:BAAALgAECgUJBQAAAA==.',
Sv='Svetlana:BAAALgAECgYJCQAAAA==.',
Sw='Swan:BAACLgAFFH8IAAIdAAMJ+QdgYwDTAAAdAAMJ+QdgYwDTAAAuAAQKfxYAAx0ABwk5EIGhAJQBAB0ABwk5EIGhAJQBAB8AAwkHBE0MAGkAAAAA.Swordboardal:BAACLgAFFH8MAAIaAAMJww6JEwC4AAAaAAMJww6JEwC4AAAuAAQKfxkAAxoACQkbF0oIAC8CABoACQkbF0oIAC8CACYABQk4A3suAIIAAAAA.',
Sy='Symptom:BAAALgAECgEJAQAAAA==.Syncophat:BAAALgADCgcJDQAAAA==.',
['Sé']='Séphórâ:BAAALgADCgMJBAAAAA==.',
Ta='Tachia:BAAALgAECgYJBgAAAA==.Tad:BAAALgAECgMJBgAAAA==.Taint:BAAALgADCgQJBgAAAA==.Takia:BAAALgAECgYJDgAAAA==.Talanzen:BAABLgAECn8mAAIdAAkJ1RyYHQBvAgAdAAkJ1RyYHQBvAgAAAA==.Tarrzok:BAAALgADCgcJBwABLgAECgkJJgAJAIkUAA==.',
Te='Teacup:BAAALgAECgUJBgABLgAECgYJGQAYALAhAA==.',
Th='Theowyn:BAAALgADCgEJAQAAAA==.Thormarian:BAAALgADCgUJBwAAAA==.Thrakara:BAACLgAFFH8UAAIlAAUJcBJnEABaAQAlAAUJcBJnEABaAQAuAAQKfzkAAiUACAmNHw4OAHUCACUACAmNHw4OAHUCAAAA.Thunderhorns:BAABLgAECn8VAAILAAYJsgbPGACsAAALAAYJsgbPGACsAAAAAA==.Thundrall:BAAALgAECgYJCAAAAA==.',
To='Toaster:BAAALgADCgQJBAABLgAFFAUJEAAZAHEZAA==.Toothléss:BAAALgADCgIJAgAAAA==.Toria:BAAALgAECgUJBgAAAA==.Torlania:BAAALgADCgYJBgAAAA==.',
Tr='Trayleen:BAAALgAECgMJBAAAAA==.Treeåj:BAAALgAECgYJDgAAAA==.Trilina:BAAALgADCgkJCAAAAA==.Truths:BAACLgAFFH8hAAMUAAcJ3xhMAQAGAgAUAAcJ3xhMAQAGAgAmAAEJcwBrJwAyAAAuAAQKfyQAAhQACAkHJYIIACMDABQACAkHJYIIACMDAAAA.Trystrom:BAAALgADCgcJCwAAAA==.',
Ts='Tsuo:BAACLgAFFH8UAAInAAUJsCFEAgCXAQAnAAUJsCFEAgCXAQAuAAQKfzgAAicACAkhJoABAAIDACcACAkhJoABAAIDAAAA.',
Tu='Tuhãn:BAAALgAECgEJAQAAAA==.',
Tw='Twixxed:BAAALgADCgYJCAABLgAECggJGgAPANMdAA==.',
Tx='Txjustice:BAAALgADCgUJDwAAAA==.',
Ty='Tymptriss:BAAALgAECgYJDgAAAA==.Tyrick:BAAALgAECgkJEAAAAA==.Tywen:BAAALgADCgEJAQAAAA==.',
Uh='Uhogpaladin:BAAALgADCgEJAQAAAA==.',
Um='Umbrage:BAACLgAFFH8OAAMMAAUJNhacCQCsAAAOAAQJdBLOTADlAAAMAAIJrRqcCQCsAAAuAAQKfykABAwACAl3IfoIADECAAwABwnpHfoIADECAA4ACAkOHoUfACoCAA0AAQmWHSooAFEAAAAA.',
Un='Unholyblade:BAAALgADCgYJCgAAAA==.',
Ur='Urethrafrkln:BAAALgADCgcJDwAAAA==.',
Va='Vache:BAAALgADCgkJDQAAAA==.Valartha:BAAALgAECgYJDgAAAA==.Variol:BAAALgAECgYJBgAAAA==.Vaztek:BAAALgADCgMJAwAAAA==.',
Ve='Vecna:BAAALgAECgYJEAAAAA==.Vellarya:BAAALgADCgYJBgABLgAECggJHAAbAH0jAA==.Vellmora:BAAALgAECgEJAQAAAA==.Velsea:BAAALgAECgMJBgAAAA==.Velstadt:BAABLgAECn8jAAISAAkJ9hvnBwCDAgASAAkJ9hvnBwCDAgAAAA==.Venhance:BAABLgAECn8aAAMkAAcJnRZOJwBbAQAkAAcJnRZOJwBbAQAbAAEJTBDUmQAxAAAAAA==.Venotu:BAABLgAECn8nAAIBAAkJ4hx8BABtAgABAAkJ4hx8BABtAgAAAA==.Vermilion:BAAALgAECgYJEwAAAA==.Verso:BAAALgADCgcJEwAAAA==.',
Vi='Vinculum:BAAALgADCgIJAgAAAA==.Viviel:BAAALgAECggJJQAAAQ==.',
Vo='Voidherron:BAAALgAECgYJCwAAAA==.Voidobscur:BAAALgADCgUJBQAAAA==.Voidwapa:BAAALgAECgQJCAAAAA==.Vonzilla:BAABLgAECn8bAAICAAYJChWlJQBHAQACAAYJChWlJQBHAQAAAA==.Vorthael:BAABLgAECn8XAAIPAAYJlQaXrQDIAAAPAAYJlQaXrQDIAAAAAA==.Voxen:BAAALgADCgQJBAAAAA==.',
Vy='Vynirel:BAAALgAECgEJAQAAAA==.',
['Vö']='Vöid:BAAALgADCgcJBwAAAA==.',
Wa='Waarlow:BAAALgADCgEJAQAAAA==.Warlockbot:BAAALgAFFAEJAwAAAA==.Warmongral:BAABLgAECn8iAAIVAAcJMxQsXQBtAQAVAAcJMxQsXQBtAQAAAA==.Waterboot:BAAALgAECgYJDwAAAA==.Wattheyneed:BAAALgADCgUJBQAAAA==.',
We='Wendi:BAABLgAECn8fAAIMAAcJPg2JDgAKAQAMAAcJPg2JDgAKAQAAAA==.',
Wh='Wheelchair:BAAALgADCgUJBQABLgAECgkJLQALABAfAA==.Whipx:BAAALgADCgIJAgAAAA==.',
Wi='Wingsaber:BAABLgAECn89AAIVAAkJBBXiLgD8AQAVAAkJBBXiLgD8AQAAAA==.Wisename:BAAALgADCgcJCAAAAA==.Withher:BAAALgADCgcJBwAAAA==.',
Wo='Wombo:BAABLgAECn8eAAIXAAkJMB9zAQC5AgAXAAkJMB9zAQC5AgAAAA==.Woolala:BAAALgAECgEJAQABLgAECgkJOwAVAO4jAA==.',
Wr='Wrathran:BAAALgAECgYJEQAAAA==.',
Wu='Wut:BAAALgADCgkJCQABLgAECgkJLgAlAPgdAA==.',
Xa='Xahiri:BAAALgAECgEJAQAAAA==.',
Xl='Xlia:BAAALgAECgIJAgAAAA==.',
Ya='Yaeyo:BAAALgAECgcJDQAAAA==.Yazmat:BAACLgAFFH8HAAIZAAMJNBBEIQDIAAAZAAMJNBBEIQDIAAAuAAQKfykAAhkACQkkHEAHANcCABkACQkkHEAHANcCAAAA.Yazmyn:BAAALgAECggJDgAAAA==.',
Ye='Yerehmi:BAAALgAECgMJBQAAAA==.',
Ym='Ymma:BAAALgADCgcJBwAAAA==.',
Yu='Yuny:BAAALgAECgcJEwAAAA==.',
Yv='Yvendria:BAABLgAECn8eAAQNAAkJBRh1AwAYAgANAAkJBRh1AwAYAgAOAAUJpQ/0egAGAQAMAAEJAAAnagA+AAAAAA==.',
Za='Zacnafeen:BAAALgAECgMJAwAAAA==.Zaelessa:BAAALgAECgMJBgABLgAECggJJQAGAAAAAQ==.Zaier:BAABLgAECn9FAAMZAAkJwCQBAwBFAwAZAAkJwCQBAwBFAwAVAAMJuRHuxACwAAAAAA==.Zaraelila:BAAALgADCgMJAwAAAA==.',
Ze='Zeltan:BAABLgAECn8hAAMZAAgJsxr2LwDCAQAZAAYJGxz2LwDCAQAVAAgJPQ3KYQBiAQAAAA==.Zeropriest:BAAALgADCgUJBQAAAA==.',
Zh='Zhundrenga:BAAALgAECgYJDgAAAA==.',
Zi='Zinik:BAAALgADCgEJAQAAAA==.',
Zo='Zolt:BAAALgAECgcJDQAAAA==.Zoma:BAAALgADCgEJAQAAAA==.',
Zu='Zugzeal:BAAALgADCgYJBAAAAA==.',
['Zï']='Zïggy:BAAALgAECgYJBwAAAA==.',
['År']='Åres:BAAALgADCgIJAwAAAA==.',
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
