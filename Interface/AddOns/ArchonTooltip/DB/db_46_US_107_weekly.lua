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

local lookup = {'Paladin-Retribution','Paladin-Protection','Priest-Shadow','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Druid-Feral','Druid-Restoration','DemonHunter-Devourer','Druid-Balance','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Priest-Discipline','Warrior-Fury','Hunter-BeastMastery','Rogue-Assassination','DeathKnight-Frost','Paladin-Holy','Warrior-Protection','Shaman-Restoration','Shaman-Enhancement','Mage-Frost','Mage-Arcane','Mage-Fire','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Shaman-Elemental','Warrior-Arms','Monk-Mistweaver','Druid-Guardian','Rogue-Subtlety',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abogato:BAAALgAECgQJBAAAAA==.',
Ae='Aedra:BAAALgADCgcJEgAAAA==.Aeowyyn:BAAALgAECggJEwAAAA==.',
Af='Af:BAAALgADCgUJBQAAAA==.',
Ah='Ahnir:BAABLgAECn8aAAIBAAkJaw+2UgCyAQABAAkJaw+2UgCyAQAAAA==.Ahnkhano:BAABLgAECn8dAAICAAgJ8RFiEgCjAQACAAgJ8RFiEgCjAQAAAA==.',
Ai='Aidenarren:BAAALgADCgkJEAAAAA==.Ainge:BAAALgADCgUJBQAAAA==.Aiom:BAAALgADCgMJAwAAAA==.',
Ak='Akashaa:BAAALgADCgEJAQAAAA==.Akbartheiiv:BAACLgAFFH8YAAIDAAcJ7xi4AQACAgADAAcJ7xi4AQACAgAuAAQKfzMAAgMACQl7IwcDACEDAAMACQl7IwcDACEDAAAA.',
Al='Alexanderson:BAAALgADCgEJAQAAAA==.Allero:BAAALgAECgMJAwAAAA==.Allistrana:BAABLgAECn8iAAIEAAkJBRwzEwBGAgAEAAkJBRwzEwBGAgAAAA==.Aluvia:BAAALgAECgIJBAAAAA==.',
Am='Amairis:BAAALgAECgUJDAAAAA==.Ambiorix:BAAALgADCgEJAQAAAA==.',
An='Anari:BAAALgADCgUJBQAAAA==.Angelsin:BAAALgADCgkJGwAAAA==.Animorph:BAAALgADCgcJJQAAAA==.Annestasia:BAAALgAECgcJCAAAAA==.Anrion:BAABLgAECn8sAAMFAAkJHyNEBADdAgAFAAkJHyNEBADdAgAGAAcJNxzPBwDVAQAAAA==.Anteater:BAAALgADCgEJAQABLgAECgUJDgAHAAAAAA==.',
Ap='Aph:BAAALgAECgcJDAAAAA==.Apolló:BAAALgAECgkJDwAAAA==.',
Ar='Araiana:BAAALgAECgEJAQAAAA==.Arayia:BAABLgAECn8UAAMIAAYJ9gv+GwDvAAAIAAYJ9gv+GwDvAAAJAAUJkA1taQDXAAAAAA==.Arelian:BAABLgAECn8ZAAMGAAkJ2BJhDgA8AQAGAAYJmhZhDgA8AQAKAAkJbwv4dwAKAQAAAA==.Aristia:BAABLgAECn8iAAMJAAgJSCMzDgDIAgAJAAgJSCMzDgDIAgALAAEJzwxXeQAuAAABLgADCgYJCgAHAAAAAA==.Artaic:BAAALgAECgUJDgAAAA==.Artemysia:BAAALgADCgEJAQAAAA==.',
At='Ataboom:BAAALgADCgEJAQAAAA==.Ataliya:BAAALgAECgQJCgAAAA==.',
Au='Auranar:BAABLgAECn8dAAIMAAgJewY0EwAEAQAMAAgJewY0EwAEAQAAAA==.Aurilia:BAABLgAECn8UAAIEAAYJLxsQGwDJAQAEAAYJLxsQGwDJAQAAAA==.',
Av='Avanicus:BAABLgAECn8oAAQNAAkJhQqWEgDyAAAOAAcJUAkiEAAnAQANAAcJbwmWEgDyAAAPAAQJqAPL9ABTAAAAAA==.Aven:BAABLgAECn8cAAMQAAcJJg+EhwAvAQAQAAcJAg+EhwAvAQARAAUJNgdIOACFAAAAAA==.',
Ax='Axiomronin:BAABLgAECn8mAAMSAAkJTSQJBQDXAgASAAgJRyQJBQDXAgATAAgJJyK3DgCSAgAAAA==.',
Ay='Ayroon:BAAALgAECgQJBAAAAA==.',
Az='Azulien:BAABLgAECn8kAAIUAAcJfgMLOgD1AAAUAAcJfgMLOgD1AAAAAA==.Azuriel:BAAALgAECgIJAgAAAA==.',
Ba='Baltuk:BAABLgAECn8aAAIQAAgJ0x3YJgCgAgAQAAgJ0x3YJgCgAgAAAA==.Banderblitz:BAACLgAFFH8GAAIVAAIJ0hFxMgCWAAAVAAIJ0hFxMgCWAAAuAAQKfzUAAhUACQlIIc4HAMQCABUACQlIIc4HAMQCAAAA.Baobei:BAAALgADCgcJBwAAAA==.Bar:BAACLgAFFH8HAAMDAAQJigZxJQCOAAADAAQJigZxJQCOAAAEAAMJlREIIgB5AAAuAAQKfxsAAgMACAlxGicVAEMCAAMACAlxGicVAEMCAAAA.Barunnar:BAAALgADCgEJAQAAAA==.',
Be='Bearlyshady:BAAALgADCgcJCwABLgAECgkJJgAKAIkUAA==.Bellatrixie:BAAALgAECgYJBgAAAA==.Benafflock:BAABLgAECn8bAAQOAAgJkwhvDgA+AQAOAAgJdAhvDgA+AQAPAAQJYwSY4QCXAAANAAEJDw1mNwAsAAABLgAECgcJEgAHAAAAAA==.Beriadhwen:BAAALgAECgUJBgAAAA==.Bermy:BAABLgAECn8aAAINAAkJGxH4DwAWAQANAAkJGxH4DwAWAQAAAA==.Bewildert:BAAALgADCgIJAgAAAA==.',
Bh='Bhawkwco:BAAALgADCgEJAQAAAA==.',
Bl='Blackhawkdk:BAABLgAECn8qAAIQAAkJkRqdJQBLAgAQAAkJkRqdJQBLAgAAAA==.Blende:BAABLgAECn8gAAIBAAgJbSBSHAB9AgABAAgJbSBSHAB9AgAAAA==.Bloodshadow:BAABLgAECn8rAAIWAAgJZBTeRwCdAQAWAAgJZBTeRwCdAQAAAA==.Blueberrae:BAAALgADCgEJAQAAAA==.Bluemaster:BAAALgADCgYJBgAAAA==.',
Bo='Boidohanta:BAAALgADCgUJBQAAAA==.Bondarrex:BAAALgADCgYJBgAAAA==.',
Br='Braveharth:BAABLgAECn8VAAIBAAgJCgQRsgD6AAABAAgJCgQRsgD6AAAAAA==.Braxus:BAAALgAECgMJBAAAAA==.Breakcooloz:BAACLgAFFH8TAAIXAAYJ/R/gAADWAQAXAAYJ/R/gAADWAQAuAAQKfyIAAhcACAmoIyIBADQDABcACAmoIyIBADQDAAAA.Brooce:BAABLgAECn8uAAIBAAkJ3B5dEwCzAgABAAkJ3B5dEwCzAgAAAA==.Broom:BAAALgADCgkJHQABLgAECgkJNgAMAIcfAA==.',
Bu='Burstinurass:BAACLgAFFH8YAAIQAAUJsSPZIwCGAQAQAAUJsSPZIwCGAQAuAAQKfxgAAhAACAm+JegSALgCABAACAm+JegSALgCAAEuAAUUBgkTABcA/R8A.',
Ca='Caladorion:BAAALgAECgIJAgAAAA==.Candyjar:BAAALgADCgcJDAAAAA==.Cantmissyou:BAAALgAECgEJBgAAAA==.Capidk:BAAALgAFFAEJAQAAAA==.Carafe:BAAALgADCgEJAQABLgAECgkJJAAYAIYeAA==.Carbonight:BAAALgADCgEJAQAAAA==.Carlos:BAAALgAECgUJDAABLgAECggJJQABAHgiAA==.Caspianne:BAAALgAECgQJBgAAAA==.',
Cb='Cbrown:BAAALgAECgEJAQAAAA==.',
Ce='Celani:BAACLgAFFH8HAAIEAAMJ9RItGADJAAAEAAMJ9RItGADJAAAuAAQKfyYAAwQACAnaGRYSACgCAAQACAnaGRYSACgCABQAAQm6AWpeACQAAAAA.Cellyne:BAABLgAECn8fAAMBAAcJOAZEwADkAAABAAcJOAZEwADkAAAZAAIJJALVeQA2AAAAAA==.Centy:BAAALgAECgYJEgAAAA==.Ceredisam:BAAALgADCgcJBwAAAA==.',
Ch='Chaz:BAAALgAECgYJDwAAAA==.Chedrood:BAAALgADCgMJBwAAAA==.Chelives:BAEBLgAECn8eAAIaAAYJkAEnNgB1AAAaAAYJkAEnNgB1AAAAAA==.Chubrub:BAAALgAECgUJEQAAAA==.Chìef:BAAALgADCgEJAQAAAA==.',
Ci='Cires:BAAALgAECgEJAgAAAA==.',
Cl='Claud:BAAALgAECgYJBgAAAA==.Cleric:BAAALgADCgMJAwAAAA==.',
Co='Cobaltwolf:BAAALgAECgQJCAAAAA==.Colanasou:BAAALgAECgYJCgAAAA==.Coldbattler:BAABLgAECn8UAAIWAAgJSg/yVwBuAQAWAAgJSg/yVwBuAQAAAA==.Copelongcut:BAAALgADCgMJAQAAAA==.Corrick:BAAALgADCgcJEAAAAA==.',
Cr='Crow:BAAALgAECgkJHQAAAQ==.',
Cu='Curavis:BAAALgADCgMJAwAAAA==.',
Cy='Cydric:BAABLgAECn8iAAIBAAgJhyPFDAAoAwABAAgJhyPFDAAoAwAAAA==.',
Da='Daarrkstar:BAABLgAECn8YAAMbAAYJ4yWTEwCDAgAbAAYJ4yWTEwCDAgAcAAMJrxB5IQC6AAABLgAECggJIAABAG0gAA==.Daenyra:BAAALgADCgUJBQAAAA==.Dakarai:BAAALgADCggJDgAAAA==.Danek:BAAALgADCggJGQAAAA==.Darkane:BAABLgAFFH8FAAMWAAUJGwKFVACnAAAWAAQJrQKFVACnAAAMAAEJZgA+LAArAAAAAA==.Darocate:BAAALgADCgYJBgAAAA==.Dathanarr:BAAALgAECggJCAAAAA==.',
De='Deadskvll:BAAALgADCgYJBgAAAA==.Deathbot:BAACLgAFFH8RAAIRAAQJ0BXDEwALAQARAAQJ0BXDEwALAQAuAAQKf0UAAhEACQnXImADAO4CABEACQnXImADAO4CAAAA.Demira:BAAALgADCgMJAwAAAA==.Demoray:BAACLgAFFH8KAAIMAAUJvBiZCACSAQAMAAUJvBiZCACSAQAuAAQKfxQAAgwABwl0JB0VAIoCAAwABwl0JB0VAIoCAAAA.Dendrin:BAAALgADCgEJAQAAAA==.Deneese:BAAALgAECgIJAgAAAA==.Desniee:BAABLgAECn8gAAQdAAkJMx91QwBuAgAdAAkJMx91QwBuAgAeAAIJHA3jFAB3AAAfAAEJuxW+DgA/AAAAAA==.Dethrone:BAABLgAECn8aAAQPAAgJhx2HJgApAgAPAAcJoR+HJgApAgANAAYJ5xniIABNAQAOAAEJXBYtLgBCAAAAAA==.',
Di='Digitpro:BAABLgAECn8xAAIgAAgJVA7qHQCOAQAgAAgJVA7qHQCOAQAAAA==.Dirtydragon:BAABLgAECn8kAAMhAAgJoByiBgB2AgAhAAgJoByiBgB2AgAiAAEJhwdmZQArAAAAAA==.Disturbo:BAAALgADCgYJBgAAAA==.Divinedecay:BAAALgAECgYJEgABLgAECgkJNgAWAFgWAA==.',
Do='Dok:BAAALgADCgcJBwAAAA==.Donoraginn:BAAALgADCgkJIgABLgADCgkJNwAHAAAAAA==.Donos:BAAALgADCgkJNwAAAA==.Dontkare:BAAALgADCgcJEQABLgAECgkJKgAaAJ0lAA==.Doomjuele:BAAALgADCgYJBgAAAA==.Dorsai:BAAALgADCgUJBQAAAA==.Dott:BAAALgADCgIJAgABLgAECgkJGgABAGsPAA==.',
Dr='Draaxx:BAAALgADCgIJAgAAAA==.Draazzy:BAAALgADCgkJEgAAAA==.Dracbanti:BAAALgADCgkJEQAAAA==.Dracobelle:BAABLgAECn8eAAMhAAYJ2RtjDQDVAQAhAAYJ2RtjDQDVAQAiAAMJ+wjOYQCDAAAAAA==.Drark:BAAALgAECgEJAQAAAA==.Drathiel:BAAALgAECgMJAwAAAA==.Draxxien:BAAALgADCgcJBwAAAA==.Drazlowe:BAAALgADCgQJBwAAAA==.Dreezee:BAAALgAECgIJBQAAAA==.Drizztknight:BAAALgADCgEJAQAAAA==.Droobear:BAAALgAECgIJAgAAAA==.Drwho:BAABLgAECn8kAAIdAAcJhRjUVQC+AQAdAAcJhRjUVQC+AQAAAA==.Dràco:BAAALgADCggJDwAAAA==.Drääx:BAAALgADCggJCAAAAA==.Dräëxx:BAAALgADCgcJDQAAAA==.',
Du='Durimli:BAAALgADCgYJBwAAAA==.',
Dw='Dwayneb:BAAALgAECgkJBwAAAA==.',
['Dô']='Dôz:BAAALgADCgQJBAAAAA==.',
Ea='Earthernbot:BAABLgAFFH8LAAIdAAQJbwhhUwAgAQAdAAQJbwhhUwAgAQAAAA==.Earthspeaker:BAAALgADCgEJAQAAAA==.',
El='Eleram:BAAALgADCgYJBgABLgAECgkJGgABAGsPAA==.Elfadwagon:BAACLgAFFH8WAAIjAAUJMhtcAgBRAQAjAAUJMhtcAgBRAQAuAAQKfyQAAiMACAlcIa8CAAIDACMACAlcIa8CAAIDAAAA.Eliptical:BAAALgAECgYJEwABLgAECggJGwABAO4eAA==.Elkesey:BAAALgADCgEJAQAAAA==.Elonura:BAAALgADCgYJBgAAAA==.Elunea:BAAALgADCggJCgAAAA==.',
Em='Emishanot:BAAALgAECgEJAQABLgAECgYJEQAHAAAAAA==.',
Ep='Epoch:BAAALgADCgEJAQAAAA==.',
Er='Erangar:BAABLgAECn8UAAIkAAYJXQeXUQDBAAAkAAYJXQeXUQDBAAAAAA==.Erdor:BAAALgADCgcJDgAAAA==.Erred:BAAALgADCgcJBwAAAA==.',
Es='Esmer:BAABLgAECn8tAAIBAAkJJwpkXwCSAQABAAkJJwpkXwCSAQAAAA==.',
Et='Etheman:BAAALgAECgcJDQAAAA==.',
Eu='Euphrasie:BAAALgADCgUJBQABLgAECggJHAAbAH0jAA==.',
Ev='Eversteal:BAAALgADCgQJBAABLgAECgYJJQACAJ0gAA==.Evholker:BAABLgAECn8cAAMjAAkJXBAWCwBGAQAjAAgJ6RAWCwBGAQAiAAYJFw4ZQAACAQAAAA==.',
Ex='Excuses:BAAALgAECgYJDAABLgAFFAcJIwAVAN8YAA==.Executey:BAAALgADCgQJBAAAAA==.Exhumina:BAAALgAECgcJBgAAAA==.',
Fa='Facestealerr:BAAALgAECgYJEAAAAA==.Fallenhullkk:BAAALgADCgYJBgAAAA==.Fangyi:BAAALgADCgYJBgAAAA==.',
Fe='Feetsmell:BAAALgADCgkJEgABLgAECgkJNgAMAIcfAA==.Felmufín:BAABLgAECn8cAAIPAAgJQwx0ZgBaAQAPAAgJQwx0ZgBaAQAAAA==.Felspury:BAAALgAECgEJAQABLgAFFAQJCQAdABMKAA==.Feyrea:BAAALgAECgMJAwAAAA==.',
Fi='Fibula:BAAALgADCgcJBwAAAA==.',
Fl='Flairrick:BAABLgAECn8fAAIVAAcJvB7XGAAEAgAVAAcJvB7XGAAEAgAAAA==.Flars:BAABLgAECn8XAAIYAAcJlR2ABwDbAQAYAAcJlR2ABwDbAQAAAA==.Flatliner:BAACLgAFFH8JAAIZAAQJogSzIgDbAAAZAAQJogSzIgDbAAAuAAQKfzkAAxkACAk1DiM0AK0BABkACAk1DiM0AK0BAAEAAQmlCV9TASoAAAAA.Floracide:BAAALgAECgYJCwAAAA==.',
Fo='Foid:BAAALgAECgYJBwAAAA==.',
Fr='Fran:BAAALgADCgYJBgABLgAECgkJNgAMAIcfAA==.Frankzappn:BAAALgAECgQJBAAAAA==.Fray:BAABLgAECn8hAAIKAAkJahqOHABMAgAKAAkJahqOHABMAgAAAA==.Freeguy:BAABLgAECn8mAAIKAAkJCxqnGABkAgAKAAkJCxqnGABkAgAAAA==.',
Fu='Fuddicus:BAABLgAECn9DAAMbAAgJ3iT7CgDNAgAbAAgJ3iT7CgDNAgAkAAEJGRI9gwA9AAAAAA==.Fuddmore:BAAALgAECgYJBwAAAA==.Fuddster:BAAALgAECgQJBwABLgAECgYJBwAHAAAAAA==.',
Ga='Gaddess:BAABLgAECn8eAAIDAAYJGwdlQwDXAAADAAYJGwdlQwDXAAAAAA==.Ganath:BAAALgAECgMJAwAAAA==.Ganymede:BAAALgAECgYJDQAAAA==.Garan:BAAALgADCgQJBAAAAA==.Garnar:BAAALgADCgIJAgAAAA==.',
Ge='Geilamaine:BAABLgAECn8gAAIZAAkJFRyeBgACAwAZAAkJFRyeBgACAwAAAA==.',
Gi='Gimpy:BAAALgAECgQJBQAAAA==.',
Gl='Glimagi:BAAALgADCgcJDwAAAA==.Glimdaemon:BAAALgAECgIJAgAAAA==.',
Go='Gonefishing:BAABLgAECn89AAIBAAkJ7iMnCQAHAwABAAkJ7iMnCQAHAwAAAA==.Gorddownie:BAABLgAECn8ZAAILAAYJcAMpVQCJAAALAAYJcAMpVQCJAAAAAA==.',
Gr='Graied:BAAALgAECgYJBgAAAA==.Grellior:BAAALgAECgEJAQAAAA==.Grippysocks:BAACLgAFFH8RAAIZAAUJcRleEQBuAQAZAAUJcRleEQBuAQAuAAQKfzMAAhkACAnKGBIcADQCABkACAnKGBIcADQCAAAA.',
Gu='Gummibear:BAABLgAECn8VAAMlAAcJ/A1eIAAwAQAlAAcJ/A1eIAAwAQAaAAQJ2ANZNwCNAAAAAA==.',
Ha='Hakar:BAAALgAECgYJCAAAAA==.Hanoa:BAAALgADCgIJAgAAAA==.Harthoon:BAACLgAFFH8ZAAIdAAUJwA2GTwAqAQAdAAUJwA2GTwAqAQAuAAQKfzkAAh0ACAnIHsk1ACQCAB0ACAnIHsk1ACQCAAAA.Haruharu:BAAALgAECgMJCwAAAA==.Hawkhogan:BAAALgADCgYJCQAAAA==.Hazdanzul:BAAALgADCgQJBQABLgAECgYJEQAHAAAAAA==.',
He='Hehexxd:BAAALgAECgIJAgAAAA==.Helias:BAAALgADCgkJBgAAAA==.Hemp:BAAALgADCgEJAQAAAA==.Herrondale:BAAALgADCgcJBwAAAA==.Hey:BAAALgADCgkJIwABLgAECgkJNwAmAPcdAA==.',
Hj='Hjukonlikjuj:BAAALgAECgEJAQAAAA==.',
Ho='Hollanov:BAAALgADCgYJBgAAAA==.Honeynoats:BAABLgAECn8iAAIEAAgJNwjvLgAxAQAEAAgJNwjvLgAxAQAAAA==.Honks:BAAALgAECgEJAgAAAA==.Hotdwarf:BAAALgAECgcJDgAAAA==.',
Hu='Hubbabubbles:BAAALgAECgEJAQAAAA==.Hullkk:BAACLgAFFH8ZAAMVAAUJcyNOEQBMAQAVAAQJ8htOEQBMAQAlAAQJuSBUEAAZAQAuAAQKfzcAAxUACAmJJokFAE4DABUACAnOJYkFAE4DACUABwkPJKgEAKYCAAAA.Hundale:BAAALgAECgQJBAAAAA==.Hutchkins:BAABLgAECn8qAAMPAAgJ7hxPLQBYAgAPAAgJ7hxPLQBYAgAOAAEJAAC3OAAAAAAAAA==.Hutchknight:BAAALgAECgUJDAABLgAECggJKgAPAO4cAA==.Hutchyo:BAAALgADCgQJBAABLgAECggJKgAPAO4cAA==.',
Hy='Hydro:BAACLgAFFH8FAAIBAAQJOQ0MNQAkAQABAAQJOQ0MNQAkAQAuAAQKfzIAAwEACQlGIdgQAMYCAAEACQlGIdgQAMYCAAIABAk1D6knAKsAAAAA.Hypovolaemia:BAAALgADCgIJAgAAAA==.',
['Hä']='Häwtz:BAAALgADCgIJAgAAAA==.',
Ia='Iamhealer:BAAALgADCgMJAgAAAA==.',
Il='Illaandra:BAAALgADCgEJAQABLgAECgMJAwAHAAAAAA==.',
In='Inari:BAAALgAECgQJBwABLgAECgkJLAAgAE4YAA==.Inseng:BAABLgAECn8dAAMRAAgJ4h44EQDJAQARAAYJcSA4EQDJAQAYAAgJNxfaDABeAQAAAA==.Invasion:BAAALgAECgYJDAAAAA==.',
Ix='Ixy:BAABLgAECn8hAAIKAAkJLRo4GgBaAgAKAAkJLRo4GgBaAgAAAA==.',
Ja='Jahde:BAABLgAECn8qAAIJAAgJLwxhRwBOAQAJAAgJLwxhRwBOAQAAAA==.Jahoda:BAAALgADCgYJBgAAAA==.Jaina:BAAALgAECgQJBQAAAA==.Jamer:BAABLgAECn8bAAIaAAYJ9CE8DgDcAQAaAAYJ9CE8DgDcAQAAAA==.Jassykins:BAABLgAECn8bAAIWAAcJ6Qw1awA9AQAWAAcJ6Qw1awA9AQAAAA==.',
Je='Jeewop:BAAALgADCgEJAQAAAA==.Jeongaegdeom:BAAALgADCgcJDgAAAA==.Jessecuster:BAAALgAECgUJBgAAAA==.',
Ji='Jinjerr:BAAALgAECgcJDAAAAA==.',
Jo='Joloc:BAABLgAECn8YAAINAAYJiQ6XEgDyAAANAAYJiQ6XEgDyAAAAAA==.Jozay:BAAALgAECgYJDAAAAA==.',
Ju='Juancarlos:BAAALgADCgEJAQAAAA==.',
Ka='Kaidaa:BAAALgAECgQJBAAAAA==.Kaladan:BAAALgAECgMJBAAAAA==.Kalasparkle:BAAALgAECgYJCAAAAA==.Kalrosa:BAABLgAECn8ZAAIVAAYJ4iL/IADDAQAVAAYJ4iL/IADDAQABLgAFFAIJBgAVANIRAA==.Kare:BAABLgAECn8qAAIaAAkJnSXyAQAeAwAaAAkJnSXyAQAeAwAAAA==.Karee:BAABLgAECn8hAAICAAkJ6yShAABXAwACAAkJ6yShAABXAwABLgAECgkJKgAaAJ0lAA==.Kathilnas:BAAALgADCgUJBQABLgAECgYJEQAHAAAAAA==.',
Kc='Kcosfomas:BAAALgADCgIJAgAAAA==.',
Ke='Kebob:BAAALgADCgcJCAAAAA==.Kermodk:BAAALgAECgQJBAAAAA==.Kermodrood:BAABLgAECn8qAAMLAAkJCSP6AwAHAwALAAkJCCP6AwAHAwAnAAQJRyKVHAAlAQAAAA==.',
Kh='Khanthurs:BAAALgAECgQJBAAAAA==.Kholdbrew:BAAALgAECgYJCwAAAA==.',
Ki='Kiizo:BAABLgAECn8nAAIoAAgJhRYjEwDmAQAoAAgJhRYjEwDmAQAAAA==.Kilnot:BAABLgAECn8UAAIbAAcJ4xZQMgC8AQAbAAcJ4xZQMgC8AQAAAA==.Kinstine:BAABLgAECn8VAAIRAAYJ/wFMMgCtAAARAAYJ/wFMMgCtAAAAAA==.',
Ko='Koltara:BAABLgAFFH8HAAIKAAUJCAkXRwDkAAAKAAUJCAkXRwDkAAAAAA==.Koltaris:BAACLgAFFH8PAAISAAQJTh9lEwBQAQASAAQJTh9lEwBQAQAuAAQKfyIAAhIACAl2JBYHAKgCABIACAl2JBYHAKgCAAEuAAUUBQkHAAoACAkA.Konshis:BAACLgAFFH8GAAMmAAMJXQjNKwChAAAmAAMJXQjNKwChAAATAAEJqQUWMwA8AAAuAAQKfyIAAiYACAn7FJIrAIQBACYACAn7FJIrAIQBAAAA.Kookymonster:BAABLgAECn81AAMPAAkJpSFTDgDDAgAPAAgJ1SBTDgDDAgANAAcJlh2CBwBPAgAAAA==.Korbyn:BAAALgADCgkJCQAAAA==.Kos:BAACLgAFFH8TAAMQAAUJqBFeUAArAQAQAAQJqBFeUAArAQARAAEJAABiSAAAAAAuAAQKfxcAAxAACAl6H4ksACoCABAACAl6H4ksACoCABgAAgmaGWYfAH0AAAAA.',
Ku='Kuragaru:BAACLgAFFH8UAAMoAAUJDiCyDwBbAQAoAAUJDiCyDwBbAQAXAAIJbwxWBACsAAAuAAQKfzgAAygACAm1JMYGAJ0CACgACAm1JMYGAJ0CABcACAlqGicFAEMCAAAA.',
Ky='Kyoubouna:BAAALgAECgQJBAAAAA==.Kyoxi:BAAALgADCgEJAQAAAA==.',
La='Larianne:BAAALgAECgcJEgAAAA==.',
Le='Leese:BAABLgAECn8jAAILAAgJ6wdiNgALAQALAAgJ6wdiNgALAQAAAA==.Leretic:BAAALgAECgYJBgABLgAECggJGwABAO4eAA==.Lerion:BAABLgAECn8bAAIBAAgJ7h4fEgABAwABAAgJ7h4fEgABAwAAAA==.Lester:BAABLgAECn8mAAIDAAgJzhpcEgAcAgADAAgJzhpcEgAcAgAAAA==.Lethana:BAAALgADCgcJDAAAAA==.Lexysady:BAAALgAECgIJAgAAAA==.',
Li='Liamsun:BAABLgAECn9AAAQmAAkJJhUKGQAQAgAmAAkJJhUKGQAQAgASAAgJShZ/GADDAQATAAYJuxT4PwAZAQAAAA==.Lidd:BAAALgAECgQJAwAAAA==.Lidrael:BAABLgAECn88AAQGAAkJDh7gAgCaAgAGAAkJDh7gAgCaAgAFAAYJNAX+QgDsAAAKAAYJewpXmwDiAAAAAA==.Lidrahl:BAAALgADCgcJDQAAAA==.Liekos:BAAALgAECgMJCAAAAA==.Lightbloom:BAAALgAECgIJBQAAAA==.Lightwing:BAAALgAECgEJAQAAAA==.Liliria:BAABLgAECn86AAIEAAkJYhiLEwAXAgAEAAkJYhiLEwAXAgAAAA==.Lillidân:BAAALgAECgYJEQABLgAFFAIJBQAdABsVAA==.Lingwong:BAAALgAECgEJAwAAAA==.Litebite:BAAALgAECgUJBQAAAA==.Littlefish:BAAALgADCgcJDwAAAA==.',
Lj='Ljaeì:BAABLgAECn8eAAIDAAgJRxluFgDyAQADAAgJRxluFgDyAQAAAA==.',
Ll='Lloreth:BAABLgAECn8aAAIJAAgJegnEUQAlAQAJAAgJegnEUQAlAQAAAA==.',
Ln='Lnpoop:BAAALgAECgcJDwAAAA==.',
Lo='Locknload:BAAALgADCgMJAwAAAA==.Lockwood:BAABLgAECn8gAAIoAAkJDA8IFQDSAQAoAAkJDA8IFQDSAQAAAA==.Lominar:BAAALgADCgcJBwAAAA==.Lorelei:BAABLgAECn8eAAIWAAYJRg2gfwAQAQAWAAYJRg2gfwAQAQAAAA==.Lorrellia:BAABLgAECn8aAAIdAAkJzgRLhABSAQAdAAkJzgRLhABSAQAAAA==.Loway:BAAALgADCgkJCQABLgAECgkJNgAMAIcfAA==.',
Lu='Lucariõ:BAACLgAFFH8XAAIEAAYJsBaLAgCDAQAEAAYJsBaLAgCDAQAuAAQKfxYAAgQACAkXHpMNAH8CAAQACAkXHpMNAH8CAAAA.Lumina:BAABLgAECn8ZAAICAAYJJhubEQB+AQACAAYJJhubEQB+AQAAAA==.Lunaría:BAAALgADCgUJBgAAAA==.Lustydragon:BAAALgADCgEJAQAAAA==.',
Ly='Lyllies:BAAALgAECgIJAgAAAA==.Lysergia:BAABLgAECn8cAAIbAAgJfSOvDADLAgAbAAgJfSOvDADLAgAAAA==.',
['Lì']='Lìght:BAACLgAFFH8SAAIZAAQJQBxUGwATAQAZAAQJQBxUGwATAQAuAAQKfyAAAhkABwnBHx8bAAQCABkABwnBHx8bAAQCAAAA.',
Ma='Madrona:BAAALgAECgYJDAAAAA==.Magnumrex:BAAALgADCgUJBQAAAA==.Mahoney:BAAALgAECgUJBQAAAA==.Majestynihil:BAAALgADCggJCAAAAA==.Makkazul:BAABLgAECn8gAAMQAAgJnBeKTAC6AQAQAAgJfReKTAC6AQAYAAUJ3hUJFQDqAAAAAA==.Maladia:BAAALgADCgkJCQAAAA==.Management:BAAALgADCgQJBAAAAA==.Mangler:BAABLgAECn8UAAIkAAYJcARKWQCoAAAkAAYJcARKWQCoAAAAAA==.Maris:BAAALgADCgkJCQAAAA==.Marrad:BAAALgAECgQJBAAAAA==.Marrok:BAAALgAECgcJBwAAAA==.Marunji:BAAALgAECgYJEQAAAA==.Matcauthon:BAAALgAECgQJCAAAAA==.Matrim:BAAALgAECgQJBQAAAA==.Mattdæmon:BAABLgAECn8jAAMFAAgJVw2rHABaAQAFAAgJVw2rHABaAQAKAAIJpwLF2AA+AAAAAA==.Mattmattmatt:BAAALgADCgEJAQAAAA==.Mazzak:BAAALgADCgMJBgAAAA==.',
Me='Meanit:BAAALgAECgQJBgAAAA==.Meekogaia:BAABLgAECn87AAIbAAgJjSLLCQDvAgAbAAgJjSLLCQDvAgAAAA==.Meekosan:BAAALgAECgQJBgAAAA==.Melestaris:BAAALgADCgYJBgAAAA==.',
Mi='Mihlenna:BAAALgADCgcJBwAAAA==.Millerowntoo:BAAALgAFFAIJAwABLgAFFAMJCwAWAP8mAA==.Mimzy:BAAALgAECgEJAgAAAA==.Minarmo:BAAALgADCgEJAQAAAA==.Mingzi:BAAALgAECgYJDwAAAA==.Missanabie:BAAALgADCgcJBwAAAA==.Missymeow:BAAALgADCgYJDAAAAA==.Mital:BAAALgADCgEJAQAAAA==.Mizu:BAEALgAECgEJAgABLgAECgkJIAAjAGQRAA==.',
Mm='Mmbear:BAAALgAECgEJAQABLgAFFAUJHQABAIwXAA==.',
Mo='Mojeen:BAAALgADCgIJAgAAAA==.Monkoko:BAAALgADCgEJAgAAAA==.Montkriege:BAABLgAECn8UAAUJAAYJdQvzXwD1AAAJAAYJdQvzXwD1AAALAAUJpwLTZACOAAAIAAIJoxJgKgB1AAAnAAEJJxpjLABGAAAAAA==.Moonsocks:BAAALgAECgUJBQABLgAFFAUJEQAZAHEZAA==.Mourium:BAAALgAECgMJAwAAAA==.Moxxie:BAABLgAECn8WAAMLAAcJMxYBMAAvAQALAAYJsBUBMAAvAQAIAAEJwBiGNQBLAAAAAA==.',
Mu='Mufín:BAAALgAECgYJCQAAAA==.Murfie:BAABLgAECn8aAAMDAAkJVRYzIwC+AQADAAkJVRYzIwC+AQAEAAQJWgyDWQDOAAAAAA==.Murica:BAAALgADCgEJAQABLgAECgkJNgAMAIcfAA==.',
My='Mythosrex:BAAALgAECgcJBgAAAA==.',
['Mâ']='Mâjôr:BAAALgADCgUJBQAAAA==.',
['Mì']='Mìr:BAACLgAFFH8SAAIKAAUJEBQyMQAoAQAKAAUJEBQyMQAoAQAuAAQKfzIAAwoACAldIQEZAGICAAoACAldIQEZAGICAAUABgn7EB02AC8BAAAA.',
['Mó']='Mónkass:BAAALgAECgEJAQAAAA==.',
Na='Naitho:BAAALgAECgYJBgAAAA==.Nakedfeet:BAAALgADCgEJAQABLgAFFAUJEQAZAHEZAA==.Narena:BAAALgADCgYJBgAAAA==.Nashira:BAABLgAECn8dAAIbAAgJTglBUwAwAQAbAAgJTglBUwAwAQAAAA==.Nashness:BAACLgAFFH8KAAMQAAQJcBbnQABDAQAQAAQJcBbnQABDAQAYAAIJOQfZEwCEAAAuAAQKfzIAAxAACQkOIwcQAB0DABAACQkOIwcQAB0DABgAAQnhI4EiAGEAAAAA.Natharion:BAABLgAECn82AAMOAAkJlBiVAgCTAgAOAAkJhRiVAgCTAgAPAAgJWAhReAAzAQAAAA==.Nazrogul:BAABLgAECn8VAAIQAAYJXwg+sgAeAQAQAAYJXwg+sgAeAQAAAA==.',
Ne='Nerfme:BAAALgAECgYJBwAAAA==.Nezar:BAAALgAECgYJBQABLgAECgcJFQAbANkiAA==.',
Ni='Ninjaxe:BAACLgAFFH8MAAITAAQJkhDOFQDuAAATAAQJkhDOFQDuAAAuAAQKfyIAAxMACAnLH94JANoCABMACAnLH94JANoCABIAAQkmCD+VACAAAAEuAAUUBQkFABYAGwIA.Ninkharak:BAAALgADCgEJAQAAAA==.Nishal:BAAALgAECgMJBAABLgAECgkJOQAbALcdAA==.Niterage:BAAALgADCgYJDQAAAA==.',
Nn='Nn:BAABLgAECn8fAAInAAcJ2wy1KQDHAAAnAAcJ2wy1KQDHAAAAAA==.',
No='Novachrono:BAAALgADCgEJAQAAAA==.',
Nu='Nu:BAAALgAECgYJCgAAAA==.Nuckinphutz:BAAALgADCgYJCwAAAA==.Nullthor:BAABLgAECn8UAAIcAAYJ7xM5FAB3AQAcAAYJ7xM5FAB3AQAAAA==.Nurfd:BAABLgAECn8UAAIaAAYJcAE1NgB1AAAaAAYJcAE1NgB1AAAAAA==.',
['Nè']='Nègan:BAABLgAECn85AAMWAAgJyxeZQgCuAQAWAAgJyxeZQgCuAQAMAAgJbwjaEAAnAQAAAA==.',
['Nì']='Nìr:BAABLgAFFH8FAAIFAAUJHBHCCgAuAQAFAAUJHBHCCgAuAQAAAA==.',
['Nó']='Nóva:BAAALgADCgQJBAAAAA==.',
['Nô']='Nôyar:BAAALgAECgQJBQAAAA==.',
Ob='Obamakare:BAAALgAECgYJDQABLgAECgkJKgAaAJ0lAA==.',
Od='Odinrex:BAABLgAECn8jAAIWAAcJgxZFTgCKAQAWAAcJgxZFTgCKAQAAAA==.',
Og='Ogmattbone:BAAALgADCgMJAQAAAA==.',
Op='Opuntia:BAAALgAECgYJDgAAAA==.',
Ou='Ouch:BAAALgADCgMJAwAAAA==.Outofarrows:BAABLgAECn82AAMMAAkJhx8xAgC7AgAMAAkJhx8xAgC7AgAgAAEJXwmRLgA4AAAAAA==.',
Ow='Ow:BAAALgADCgEJAQABLgADCgMJAwAHAAAAAA==.Ownown:BAAALgAECgIJAgABLgAFFAMJCwAWAP8mAA==.',
Pa='Palinuttz:BAAALgAECgMJAwAAAA==.Pallypaladin:BAACLgAFFH8dAAIBAAUJjBfCKAA+AQABAAUJjBfCKAA+AQAuAAQKfyEAAgEACQnTHygeAHMCAAEACQnTHygeAHMCAAAA.Pasteeater:BAAALgAECgQJBAAAAA==.',
Pe='Pernelope:BAABLgAECn8iAAIKAAcJ7RvRRADgAQAKAAcJ7RvRRADgAQAAAA==.Pernicus:BAAALgAECgEJAQAAAA==.',
Ph='Phatzero:BAABLgAECn82AAMWAAkJWBa7KQANAgAWAAkJWBa7KQANAgAMAAIJMgTwMAA6AAAAAA==.Phöenix:BAAALgAECgEJAQAAAA==.',
Pi='Piedra:BAAALgADCgYJDAABLgAECgkJNgAEAK4ZAA==.Pierogi:BAAALgADCgUJBQAAAA==.Piety:BAAALgAECgYJCAAAAA==.Pinjo:BAAALgAECgEJBgAAAA==.',
Po='Polarnomad:BAAALgADCgYJCwABLgAECggJFwAdABkTAA==.Polarr:BAABLgAECn8XAAIdAAgJGRNkzwBNAQAdAAgJGRNkzwBNAQAAAA==.Polydrake:BAAALgAFFAEJAQAAAA==.Popsicles:BAAALgAECgUJBgAAAA==.',
Pr='Prismatic:BAAALgAECgMJBAAAAA==.Probablyblue:BAAALgAECgYJCQAAAA==.Proofy:BAAALgAECgcJDwAAAA==.Prowl:BAAALgADCgYJBgABLgAECgYJCwAHAAAAAA==.',
Ps='Psyop:BAAALgADCgkJEQABLgAECggJEwAHAAAAAA==.',
Pu='Punchkick:BAAALgAECgEJAQAAAA==.Punchup:BAABLgAECn8YAAITAAcJAgrfNgD7AAATAAcJAgrfNgD7AAAAAA==.',
Py='Pythie:BAAALgAECgEJAQAAAA==.',
Ra='Rabit:BAAALgAECgQJCAAAAA==.Ramsey:BAAALgADCgEJAQAAAA==.Rastputin:BAAALgAECgkJDgAAAA==.',
Re='Rebrex:BAAALgADCgcJDgAAAA==.Redpyro:BAAALgADCgcJDwAAAA==.Ren:BAAALgAECgEJAQAAAA==.Retrïbutor:BAAALgAECgYJCgAAAA==.',
Rf='Rf:BAAALgAECgEJAQAAAA==.',
Rh='Rhodraco:BAABLgAECn8eAAMiAAYJQgnQTADOAAAiAAYJQAjQTADOAAAjAAQJIgqNFgCBAAAAAA==.',
Ri='Rikku:BAAALgAECgMJAwAAAA==.Rinela:BAABLgAECn8fAAILAAgJDhz7GQA2AgALAAgJDhz7GQA2AgAAAA==.Riotdrill:BAAALgADCgYJBwAAAA==.',
Rj='Rj:BAABLgAECn8hAAIJAAgJ0yFcCgD4AgAJAAgJ0yFcCgD4AgAAAA==.',
Ro='Robi:BAAALgADCgEJAQABLgAECggJIAABAG0gAA==.Rolandrex:BAAALgAECgEJAQAAAA==.Romulusinc:BAAALgADCgMJBgAAAA==.Rosabee:BAABLgAECn8rAAIEAAkJRBABGQDcAQAEAAkJRBABGQDcAQAAAA==.',
Rp='Rp:BAAALgAECgMJAwAAAA==.',
Rq='Rq:BAAALgADCgYJBgAAAA==.',
Rt='Rtfreshness:BAAALgAECgYJBgAAAA==.',
Ru='Runswithheal:BAAALgAECgQJBQAAAA==.',
Ry='Ryyukken:BAAALgAECgYJCQAAAA==.',
['Rà']='Ràndòm:BAAALgADCgIJAgABLgAFFAgJHgAdAIEdAA==.Ràwrshåk:BAAALgADCgYJBgAAAA==.',
['Rá']='Rándom:BAABLgAFFH8GAAIJAAMJ8AoBNgC6AAAJAAMJ8AoBNgC6AAABLgAFFAgJHgAdAIEdAA==.',
['Ró']='Rónin:BAAALgAFFAEJAwAAAA==.',
Sa='Sago:BAAALgAECgMJBAAAAA==.Sanzen:BAABLgAECn8ZAAMTAAYJsRvIIgDAAQATAAYJsRvIIgDAAQAmAAMJsgcVWQBqAAAAAA==.Sauce:BAABLgAECn83AAImAAkJ9x0uBwD9AgAmAAkJ9x0uBwD9AgAAAA==.',
Sc='Scrubz:BAABLgAECn8aAAInAAkJixrVBwA2AgAnAAkJixrVBwA2AgAAAA==.',
Se='Senile:BAABLgAECn8fAAIfAAcJnRMiBACDAQAfAAcJnRMiBACDAQAAAA==.Seydori:BAAALgADCgUJDAAAAA==.',
Sh='Shadydice:BAAALgADCgYJBgABLgAECgkJJgAKAIkUAA==.Shadylid:BAABLgAECn8mAAMKAAkJiRTzMADjAQAKAAkJiRTzMADjAQAGAAMJVQniHwBtAAAAAA==.Shadówglider:BAAALgAECgYJDgAAAA==.Shaelia:BAAALgAECgQJBAAAAA==.Shale:BAABLgAECn8YAAIKAAkJziCHNQDPAQAKAAkJziCHNQDPAQAAAA==.Shamallaman:BAAALgAECgEJAQABLgAECgkJKQABACkkAA==.Shameless:BAAALgAFFAIJAgAAAA==.Sharkina:BAAALgADCgUJBQAAAA==.Sharkweek:BAAALgAECgQJBQAAAA==.Sheyoni:BAAALgAECgQJBwAAAA==.Shortbusava:BAAALgADCgcJBwAAAA==.Shreck:BAAALgAECgQJBgAAAA==.',
Si='Sinfulness:BAAALgADCgkJCQAAAA==.',
Sk='Skikette:BAAALgADCgkJLwAAAA==.Skinrot:BAABLgAECn8yAAIJAAkJlQ+SLADTAQAJAAkJlQ+SLADTAQAAAA==.',
Sm='Smig:BAAALgAECgEJBAAAAA==.',
So='Soeki:BAABLgAECn8fAAINAAcJGQ6rDgAoAQANAAcJGQ6rDgAoAQAAAA==.Solux:BAABLgAFFH8IAAICAAQJpxfkAwAtAQACAAQJpxfkAwAtAQABLgAFFAUJDwANADYWAA==.Soullove:BAABLgAECn9IAAINAAgJhBizBQDhAQANAAgJhBizBQDhAQAAAA==.Soullovez:BAABLgAECn8iAAMLAAgJGA22MAArAQALAAcJEg+2MAArAQAJAAcJLQkhXAACAQABLgAECggJSAANAIQYAA==.Soulshocks:BAABLgAECn80AAIkAAgJHhBeKwBsAQAkAAgJHhBeKwBsAQABLgAECggJSAANAIQYAA==.Soulviver:BAABLgAECn81AAIEAAkJ0xAxGQDaAQAEAAkJ0xAxGQDaAQAAAA==.',
Sp='Sparkelly:BAAALgADCgEJAQAAAA==.Spicytuna:BAAALgAECgYJBgAAAA==.Spliffy:BAAALgADCgYJBgAAAA==.Spurey:BAACLgAFFH8JAAIdAAQJEwr0UwAfAQAdAAQJEwr0UwAfAQAuAAQKfy8AAx4ACQn6HjoDAEUCAB4ACAk1GjoDAEUCAB0ACQnIGZ1XALkBAAAA.Spurylock:BAAALgADCggJDQABLgAFFAQJCQAdABMKAA==.',
St='Starstreak:BAAALgAECgYJBgABLgAECgkJMwAdABUSAA==.Stimer:BAABLgAECn8wAAMVAAkJ7R+/BgA8AwAVAAkJ1R+/BgA8AwAlAAgJCx0ZDQDvAQAAAA==.Stuipd:BAAALgADCgYJCQAAAA==.',
Su='Sublimedeath:BAABLgAECn8UAAIaAAUJ9RRwJAAbAQAaAAUJ9RRwJAAbAQAAAA==.Sublimelife:BAAALgAECgEJAQAAAA==.Sukboytony:BAAALgADCgYJBgAAAA==.Sultanofswat:BAAALgADCgcJBwAAAA==.Sunnysideup:BAAALgAECgUJBQAAAA==.',
Sv='Svetlana:BAAALgAECgYJDQAAAA==.',
Sw='Swan:BAACLgAFFH8IAAIdAAMJ+QcucwDIAAAdAAMJ+QcucwDIAAAuAAQKfxYAAx0ABwk5EIGhAJQBAB0ABwk5EIGhAJQBAB8AAwkHBE0MAGkAAAEuAAUUBAkQACAADg8A.Swordboardal:BAACLgAFFH8PAAIaAAMJww4cFwC3AAAaAAMJww4cFwC3AAAuAAQKfxsAAxoACQm8F0AKACkCABoACQm8F0AKACkCACUABQk4A3suAIIAAAAA.',
Sy='Symptom:BAAALgAECgEJAQAAAA==.Syncophat:BAAALgADCgcJDQAAAA==.',
['Sé']='Séphórâ:BAAALgADCgMJBAAAAA==.',
Ta='Tachia:BAAALgAECgYJBgAAAA==.Tad:BAAALgAECgMJBgAAAA==.Taint:BAAALgADCgQJBgAAAA==.Takia:BAABLgAECn8UAAMWAAYJjANhoQDFAAAWAAYJjANhoQDFAAAMAAMJwAA6OgAjAAAAAA==.Talanzen:BAABLgAECn8mAAIdAAkJ1RzhJgBjAgAdAAkJ1RzhJgBjAgAAAA==.Tanakiko:BAAALgADCgUJCQAAAA==.Tarrzok:BAAALgADCgcJBwABLgAECgkJJgAKAIkUAA==.',
Te='Teacup:BAAALgAECgUJBgABLgAECgkJJAAYAIYeAA==.Tellanji:BAAALgAECgIJAwAAAA==.',
Th='Theowyn:BAAALgADCgEJAQAAAA==.Thormarian:BAAALgADCgUJBwAAAA==.Thrakara:BAACLgAFFH8ZAAImAAUJUxXdFABgAQAmAAUJUxXdFABgAQAuAAQKfzkAAiYACAmNHw4OAHUCACYACAmNHw4OAHUCAAAA.Thunderhorns:BAABLgAECn8aAAIMAAYJkQc5GgC6AAAMAAYJkQc5GgC6AAAAAA==.Thundrall:BAAALgAECgYJDQAAAA==.',
Ti='Tinionron:BAAALgADCgUJCAAAAA==.',
To='Toaster:BAAALgADCgQJBAABLgAFFAUJEQAZAHEZAA==.Toothléss:BAAALgADCgIJAgAAAA==.Toria:BAAALgAECgUJBgAAAA==.Torlania:BAAALgADCgYJBgAAAA==.',
Tr='Trayleen:BAAALgAECgMJBAAAAA==.Treeåj:BAABLgAECn8fAAMLAAgJ/QrlMgAeAQALAAgJ/QrlMgAeAQAJAAUJxARDkwCpAAAAAA==.Trilina:BAAALgADCgkJCAAAAA==.Truths:BAACLgAFFH8jAAMVAAcJ3xjaAgDzAQAVAAcJ3xjaAgDzAQAlAAEJcwACMgAwAAAuAAQKfyQAAhUACAkJJYIIACMDABUACAkJJYIIACMDAAAA.Trystrom:BAAALgADCgcJCwAAAA==.',
Ts='Tsuo:BAACLgAFFH8UAAInAAUJsCFuAwCWAQAnAAUJsCFuAwCWAQAuAAQKfzgAAicACAkgJhUCAAADACcACAkgJhUCAAADAAAA.',
Tu='Tuhãn:BAAALgAECgEJAQAAAA==.',
Tw='Twixxed:BAAALgADCgYJCAABLgAECggJGgAQANMdAA==.',
Tx='Txjustice:BAAALgADCgUJDwAAAA==.',
Ty='Tymptriss:BAABLgAECn8UAAINAAYJQwVPHACjAAANAAYJQwVPHACjAAAAAA==.Tyrick:BAAALgAECgkJEAAAAA==.Tywen:BAAALgADCgEJAQAAAA==.',
Uh='Uhogpaladin:BAAALgADCgEJAQAAAA==.',
Um='Umbrage:BAACLgAFFH8PAAMNAAUJNhaoDAClAAAPAAQJdBLeWwDgAAANAAIJrRqoDAClAAAuAAQKfykABA0ACAmAIfoIADECAA0ABwnpHfoIADECAA8ACAkXHgMpAB4CAA4AAQmWHSooAFEAAAAA.',
Un='Unholyblade:BAAALgADCgYJCgAAAA==.',
Ur='Urethrafrkln:BAAALgAECgEJAQAAAA==.',
Va='Vache:BAAALgADCgkJDQAAAA==.Valartha:BAABLgAECn8NAAILAAYJwxSeLwAxAQALAAYJwxSeLwAxAQAAAA==.Variol:BAAALgAECgcJDwAAAA==.Vaztek:BAAALgADCgMJAwAAAA==.',
Ve='Vecna:BAAALgAECgYJEAAAAA==.Vellarya:BAAALgADCgYJBgABLgAECggJHAAbAH0jAA==.Vellmora:BAAALgAECgEJAQAAAA==.Velsea:BAAALgAECgMJBgAAAA==.Velstadt:BAABLgAECn8nAAITAAkJ/xzYBwCnAgATAAkJ/xzYBwCnAgAAAA==.Venhance:BAABLgAECn8gAAMkAAgJNxeSIQCqAQAkAAgJNxeSIQCqAQAbAAEJTBAOsgAwAAAAAA==.Venotu:BAABLgAECn8uAAICAAkJ+ByYBQBtAgACAAkJ+ByYBQBtAgAAAA==.Vermilion:BAABLgAECn8XAAIKAAYJHAgQmwDBAAAKAAYJHAgQmwDBAAAAAA==.Verso:BAAALgADCgcJEwAAAA==.',
Vh='Vholatile:BAAALgAECgUJBQAAAA==.',
Vi='Vinculum:BAAALgADCgIJAgAAAA==.Viviel:BAAALgAECggJLQAAAQ==.',
Vo='Voidherron:BAAALgAECgYJCwAAAA==.Voidobscur:BAAALgADCgUJBQAAAA==.Voidwapa:BAAALgAECgQJCAAAAA==.Vonzilla:BAABLgAECn8fAAIDAAYJmxbMKwBOAQADAAYJmxbMKwBOAQAAAA==.Vorthael:BAABLgAECn8dAAIQAAYJrgaMyQDEAAAQAAYJrgaMyQDEAAAAAA==.Voxen:BAAALgADCgQJBAAAAA==.',
Vy='Vynirel:BAAALgAECgEJAQAAAA==.',
['Vö']='Vöid:BAAALgADCgcJBwAAAA==.',
Wa='Waarlow:BAAALgADCgEJAQAAAA==.Warlockbot:BAAALgAFFAEJAwAAAA==.Warmongral:BAABLgAECn8qAAIBAAgJ0RQXUQC2AQABAAgJ0RQXUQC2AQAAAA==.Waterboot:BAAALgAECgYJDwAAAA==.Wattheyneed:BAAALgADCgUJBQAAAA==.',
We='Wendi:BAABLgAECn8mAAINAAcJeQ1FEAASAQANAAcJeQ1FEAASAQAAAA==.',
Wh='Wheelchair:BAAALgADCgUJBQABLgAECgkJNgAMAIcfAA==.Whipx:BAAALgADCgIJAgAAAA==.',
Wi='Wingsaber:BAABLgAECn89AAIBAAkJAxWQPgDsAQABAAkJAxWQPgDsAQAAAA==.Wisename:BAAALgAECgMJAwAAAA==.Withher:BAAALgADCgcJBwAAAA==.',
Wo='Wombo:BAABLgAECn8eAAIXAAkJMB/+AQCsAgAXAAkJMB/+AQCsAgAAAA==.Woolala:BAAALgAECgcJCAABLgAECgkJPQABAO4jAA==.',
Wr='Wrathran:BAABLgAECn8WAAIWAAgJuBK7PQC/AQAWAAgJuBK7PQC/AQAAAA==.',
Wu='Wut:BAAALgADCgkJCQABLgAECgkJNwAmAPcdAA==.',
Xa='Xahiri:BAAALgAECgEJAQAAAA==.',
Xl='Xlia:BAAALgAECgIJAgAAAA==.',
Ya='Yaeyo:BAAALgAECgcJDQAAAA==.Yazmat:BAACLgAFFH8HAAIZAAMJNBDZJwC6AAAZAAMJNBDZJwC6AAAuAAQKfykAAhkACQklHDMKAMQCABkACQklHDMKAMQCAAAA.Yazmyn:BAAALgAECggJDgAAAA==.',
Ye='Yeah:BAAALgADCgkJCQABLgAECgkJNwAmAPcdAA==.Yerehmi:BAAALgAECgMJBQAAAA==.',
Ym='Ymma:BAAALgADCgcJBwAAAA==.',
Yu='Yuny:BAAALgAECgcJEwAAAA==.',
Yv='Yvendria:BAABLgAECn8iAAQOAAkJShr1AgBlAgAOAAkJShr1AgBlAgAPAAUJpQ/gjwAGAQANAAEJAAAnagA+AAAAAA==.',
Za='Zacnafeen:BAAALgAECgMJAwAAAA==.Zaelessa:BAAALgAECgMJCAABLgAECggJLQAHAAAAAQ==.Zaier:BAABLgAECn9OAAMZAAkJwCQBAwBFAwAZAAkJwCQBAwBFAwABAAMJuRFC5QCvAAAAAA==.Zaraelila:BAAALgADCgMJAwAAAA==.Zartart:BAAALgAECgkJBgAAAA==.',
Ze='Zeltan:BAABLgAECn8qAAMZAAgJ9hz2LwDCAQAZAAYJGxz2LwDCAQABAAgJsxHbVgCoAQAAAA==.Zeropriest:BAAALgADCgUJBQAAAA==.',
Zh='Zhundrenga:BAABLgAECn8UAAIRAAYJ2wQvNgCQAAARAAYJ2wQvNgCQAAAAAA==.',
Zi='Zinik:BAAALgADCgEJAQAAAA==.',
Zo='Zolt:BAAALgAECgcJDQAAAA==.Zoma:BAAALgADCgEJAQAAAA==.',
Zu='Zugzeal:BAAALgADCgYJBAAAAA==.Zuldraaxx:BAAALgADCgkJCQAAAA==.',
['Zï']='Zïggy:BAAALgAECgYJBwAAAA==.',
['År']='Åres:BAAALgADCgIJAwAAAA==.',
['Ün']='Ünc:BAAALgADCgEJAQAAAA==.',
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
