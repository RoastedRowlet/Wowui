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

local lookup = {'Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Restoration','Druid-Balance','Evoker-Augmentation','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Warrior-Protection','Monk-Windwalker','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Unknown-Unknown','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','Mage-Frost','DemonHunter-Havoc','Shaman-Restoration','Rogue-Outlaw','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','DeathKnight-Blood','Druid-Guardian','Shaman-Enhancement','Priest-Discipline','Mage-Fire','Paladin-Retribution','Mage-Arcane','Druid-Feral','DeathKnight-Frost','Evoker-Preservation','Rogue-Assassination','Evoker-Devastation','Monk-Brewmaster',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aamon:BAAALgAECgQJCgAAAA==.',
Ab='Abacus:BAABLgAECn8hAAIBAAgJGiO4CQA9AgABAAgJGiO4CQA9AgAAAA==.',
Ad='Adam:BAACLgAFFH8NAAMCAAcJUxTgKQA9AQACAAUJ5RXgKQA9AQADAAMJlBFcDQCiAAAuAAQKfy4ABAIACQk2JF4WAM4CAAIACQmcI14WAM4CAAMABQljJKcNAOsBAAQAAQkaI5UbAGYAAAAA.Adedruid:BAABLgAECn8gAAMFAAYJ3xoBSgB6AQAFAAYJ3xoBSgB6AQAGAAYJdR/1JABHAQAAAA==.Adevoker:BAAALgAECgQJBAAAAA==.Adragon:BAABLgAECn8eAAIHAAkJLhnMDQA8AgAHAAkJLhnMDQA8AgAAAA==.',
Ae='Aengyl:BAAALgAECgQJBAAAAA==.Aeonne:BAAALgAECggJEwAAAA==.',
Ak='Akshul:BAABLgAECn8UAAIIAAYJ5Q1HRgAvAQAIAAYJ5Q1HRgAvAQAAAA==.Akurama:BAAALgAECgcJCQAAAA==.',
Al='Aldrea:BAAALgAECgYJCgAAAA==.Allsmiles:BAABLgAECn8UAAQJAAkJwB3tCAAhAgAJAAgJhRrtCAAhAgAKAAUJChm2TQBwAQALAAMJ7R0oKgDvAAAAAA==.Allura:BAAALgAECgIJAwAAAA==.Alorian:BAAALgAECgIJAgAAAA==.Alttharius:BAAALgAECgMJAwABLgAECgkJGQAMALQgAA==.Alyysha:BAABLgAECn8bAAINAAcJlwkCRgBgAQANAAcJlwkCRgBgAQAAAA==.',
Am='Amoon:BAABLgAECn8sAAMOAAkJoRhgHQAgAgAOAAkJ8xZgHQAgAgAPAAYJBRX9DAAuAQAAAA==.',
An='Andoriel:BAAALgADCgcJBwABLgAFFAIJAwAQAAAAAA==.Angelrain:BAABLgAECn8sAAMRAAgJWByRDgCaAgARAAgJWByRDgCaAgASAAcJ8QeFLAAdAQAAAA==.',
Ar='Archymedes:BAABLgAECn8mAAIKAAcJ9BB2KgBdAQAKAAcJ9BB2KgBdAQAAAA==.Arckady:BAAALgAECgQJBwAAAA==.Areko:BAAALgAECgEJAQAAAA==.Artharius:BAABLgAECn8ZAAIMAAkJtCDNDgANAgAMAAkJtCDNDgANAgAAAA==.',
Au='Auburnbeard:BAAALgADCgYJBgAAAA==.Aumed:BAAALgADCgEJAQAAAA==.',
Av='Averle:BAABLgAECn9HAAIDAAYJCQfnFQC8AAADAAYJCQfnFQC8AAAAAA==.',
Az='Azrran:BAAALgADCgEJAQAAAA==.Aztharot:BAAALgAECgIJAgAAAA==.',
Ba='Badchoices:BAAALgAECgMJAwAAAA==.Badkittie:BAAALgAECgIJAgAAAA==.',
Be='Belinda:BAAALgAECgEJAQABLgAFFAYJGAATAMgjAA==.Bewater:BAAALgADCgcJBwAAAA==.',
Bl='Bladesmcgee:BAAALgAECgcJBwABLgAECgQJCAAQAAAAAA==.',
Bo='Bobadelphia:BAAALgADCgYJBgABLgAECgYJEQAQAAAAAA==.Bofahdeez:BAABLgAECn8aAAMSAAgJeg6+PABHAQASAAcJVg6+PABHAQARAAcJLQwAKQAyAQAAAA==.Bogs:BAACLgAFFH8NAAIUAAQJ1hltMABVAQAUAAQJ1hltMABVAQAuAAQKfyMAAhQACAnrIb4jAOQCABQACAnrIb4jAOQCAAAA.Bonedaddy:BAAALgAECgYJBgAAAA==.',
Br='Brewswayne:BAAALgADCgQJBAABLgAFFAIJAwAQAAAAAA==.Brolic:BAABLgAECn8rAAMVAAgJ8x0cCQA+AgAVAAgJ8x0cCQA+AgAOAAEJJgmW4wAkAAAAAA==.',
Ca='Cail:BAEBLgAECn8UAAIWAAgJvxdhGwAZAgAWAAgJvxdhGwAZAgAAAA==.Calamìty:BAAALgADCgcJDgABLgAECgkJIgAFALUNAA==.Calisa:BAABLgAECn8yAAIXAAkJmR1CAQC4AgAXAAkJmR1CAQC4AgAAAA==.Cardio:BAAALgADCgYJCAAAAA==.Carnifexx:BAAALgAFFAIJAgABLgAFFAUJFQAOAHUeAA==.Cassey:BAAALgAECgEJAQAAAA==.',
Ce='Celesteus:BAAALgADCgkJFAAAAA==.',
Ch='Charis:BAAALgAECgYJCwAAAA==.Chigutotems:BAAALgAECgYJCgABLgAECgkJFQAOAFsVAA==.Choi:BAAALgAECgUJDwAAAA==.Chooq:BAAALgADCgIJAgAAAA==.Chozen:BAAALgAECgUJEAAAAA==.Chumlee:BAAALgAECgUJBQAAAA==.',
Ci='Cienna:BAAALgAECgYJDgAAAA==.Cigz:BAAALgADCgEJAQAAAA==.Cinch:BAAALgAECgIJAgAAAA==.',
Co='Colinferral:BAAALgAECgYJCAAAAA==.Coulee:BAAALgAECgIJBAABLgAECggJIQAVAL0eAA==.Cowladin:BAAALgADCgUJBQAAAA==.',
Cr='Crakzkull:BAAALgAECgUJCwAAAA==.Croar:BAAALgAECgMJBAAAAA==.Cronicpain:BAAALgADCgkJCQAAAA==.',
['Cä']='Cäntstandya:BAACLgAFFH8NAAMYAAQJVRgdEQAHAQAYAAMJFBcdEQAHAQAZAAMJmRjSMwDxAAAuAAQKfyMAAxkACAkvG1cSAKUCABkACAliGVcSAKUCABgABwkaHuULACMCAAAA.',
Da='Daiko:BAAALgAECgYJCQAAAA==.Daks:BAAALgAFFAIJAwAAAA==.Dargo:BAAALgAECgYJEwAAAA==.Darklucrezia:BAACLgAFFH8MAAMZAAQJ0BdLGQBKAQAZAAQJ0BdLGQBKAQAaAAIJNgISHwBSAAAuAAQKfywAAxkACAn2HxkPAJECABkACAltHxkPAJECABoACAkOEeQlAPoBAAAA.Dazzlefraz:BAAALgAECgQJBAAAAA==.',
De='Demonklunter:BAAALgADCgYJEAAAAA==.Destructoid:BAAALgAECgEJAQAAAA==.',
Di='Dicey:BAAALgADCgMJAwABLgAECgQJBgAQAAAAAA==.',
Do='Dochunter:BAAALgAECgUJBQAAAA==.',
Dr='Dracarius:BAAALgAECgQJBwAAAA==.Drega:BAAALgAECgYJBwAAAA==.Droods:BAAALgAECgQJBQAAAA==.Drtypinkcake:BAABLgAECn8WAAIVAAYJXwYGKwDBAAAVAAYJXwYGKwDBAAAAAA==.Druskgar:BAABLgAECn8fAAITAAgJyyE/LAAIAgATAAgJyyE/LAAIAgAAAA==.Dryad:BAAALgAECgQJBwAAAA==.',
Du='Duckster:BAAALgADCgYJBwAAAA==.Dunce:BAABLgAECn8gAAIbAAgJ9h/XCQCaAgAbAAgJ9h/XCQCaAgAAAA==.Durkk:BAABLgAECn8yAAIcAAkJGCF0AwDRAgAcAAkJGCF0AwDRAgAAAA==.Durza:BAAALgAECgcJEAAAAA==.',
['Dä']='Dännydevito:BAAALgADCgQJBAAAAA==.',
Ed='Eduard:BAAALgAECgYJCQAAAA==.',
El='Elanthae:BAAALgAECgQJCwAAAA==.Elysia:BAAALgAECgEJAgAAAA==.',
Er='Erzulie:BAAALgAECgUJBAAAAA==.',
Es='Estara:BAABLgAECn8sAAIdAAkJqwtVFQAwAQAdAAkJqwtVFQAwAQAAAA==.',
Et='Etali:BAABLgAECn8pAAIKAAkJjBrdDABXAgAKAAkJjBrdDABXAgAAAA==.',
Ez='Ezazel:BAAALgADCgUJBwAAAA==.',
Fa='Faite:BAAALgADCgUJBQAAAA==.Falorin:BAABLgAECn8dAAIUAAYJRxe4dABRAQAUAAYJRxe4dABRAQAAAA==.Fanis:BAABLgAECn8mAAIaAAkJzxXGBQD9AQAaAAkJzxXGBQD9AQAAAA==.Fatherwhig:BAAALgAECgIJAwAAAA==.',
Fi='Fidis:BAAALgADCgkJCwAAAA==.Fistsofdeath:BAAALgADCggJCgAAAA==.Fistychub:BAAALgADCgEJAQAAAA==.',
Fl='Flashbang:BAAALgADCgEJAQAAAA==.Flashis:BAAALgAECggJEwAAAA==.Florago:BAAALgAECgQJBwAAAA==.',
Fo='Foxtrap:BAAALgAECgYJBgAAAA==.',
Fr='Frakir:BAABLgAECn8yAAQWAAkJoBngDgCMAgAWAAkJoBngDgCMAgAeAAMJRwrfHACMAAAIAAEJkAYjkwAjAAAAAA==.Fritzz:BAAALgAECgcJEgAAAA==.Frog:BAAALgAECgIJBAAAAA==.',
Fu='Furrypaw:BAABLgAECn8lAAIbAAkJOCXSAAC/AwAbAAkJOCXSAAC/AwAAAA==.',
Fw='Fwapp:BAACLgAFFH8YAAINAAYJ6B59BgDoAQANAAYJ6B59BgDoAQAuAAQKfxcAAg0ACAlrIcgLAL8CAA0ACAlrIcgLAL8CAAAA.',
Ga='Galvanize:BAAALgAECgEJAwAAAA==.Galynisse:BAABLgAECn8mAAMfAAYJChoeFgDOAQAfAAYJChoeFgDOAQASAAMJ7A4eZQCZAAAAAA==.',
Ge='Gedorah:BAABLgAECn8fAAIgAAcJOBz0AQD/AQAgAAcJOBz0AQD/AQABLgAFFAMJCgAIAHAeAA==.',
Gh='Ghaspy:BAAALgAECgUJCgAAAA==.Ghoste:BAAALgADCgMJAwAAAA==.Ghrex:BAAALgAECgEJAQAAAA==.',
Gi='Gijaick:BAABLgAECn8rAAMCAAgJIRhlMwDLAQACAAgJIRhlMwDLAQADAAEJHg4AdAAxAAAAAA==.',
Gl='Glaivethrow:BAABLgAECn8VAAIOAAkJWxUOQAD0AQAOAAkJWxUOQAD0AQAAAA==.Glizzo:BAAALgAECgYJDAAAAA==.Gloam:BAAALgADCgUJBQAAAA==.',
Go='Gochujjang:BAAALgAECgYJDQAAAA==.Goldhawk:BAAALgAECgMJAwAAAA==.Gotchá:BAAALgAECgEJBAAAAA==.Gotwiped:BAAALgAECgcJEAAAAA==.',
Gr='Grimgor:BAAALgAECgcJAQAAAA==.',
Ha='Hahaheals:BAAALgAECgMJBAAAAA==.Hakhar:BAAALgADCgMJAwAAAA==.Hatter:BAABLgAECn8ZAAQOAAgJ1hKfYAB/AQAOAAgJ1hKfYAB/AQAVAAMJXwcRWACGAAAPAAEJNRMmKwA0AAAAAA==.',
He='Healsus:BAAALgAECgMJAwAAAA==.Heimlish:BAAALgAECgEJAQAAAA==.Hellraiser:BAABLgAECn8bAAMTAAYJUxm6awBEAQATAAYJGhi6awBEAQAcAAQJCw+VMACKAAAAAA==.Hermione:BAAALgAECgYJDQAAAA==.Hexecution:BAAALgADCgIJAgAAAA==.',
Hi='Hiddendragon:BAAALgAECgEJAQAAAA==.',
Ho='Holydarkness:BAAALgADCggJCwAAAA==.Holykilla:BAAALgAECgEJAwAAAA==.Holykiller:BAAALgAECgEJAgAAAA==.Hoofjob:BAAALgADCggJDgABLgAFFAQJBwAfALMdAA==.Hoplite:BAAALgADCgYJCAABLgAECggJEgAQAAAAAA==.Hotot:BAAALgADCgMJAwAAAA==.',
Hu='Huffpuffle:BAAALgAECgUJCgAAAA==.',
['Hô']='Hôwl:BAABLgAECn8YAAIFAAcJwhBKOABtAQAFAAcJwhBKOABtAQAAAA==.',
Ic='Icdeathg:BAACLgAFFH8JAAIOAAMJ/Qv5QwDQAAAOAAMJ/Qv5QwDQAAAuAAQKfygAAg4ACAmFGpImAOoBAA4ACAmFGpImAOoBAAAA.',
Ik='Iktaar:BAAALgAECgQJBAAAAA==.',
Il='Illidami:BAAALgADCgkJCwAAAA==.Illidamngirl:BAAALgADCgYJBgABLgAECggJHgALANcbAA==.',
Im='Imperius:BAACLgAFFH8VAAIhAAUJHBbqHwBHAQAhAAUJHBbqHwBHAQAuAAQKfyQAAiEACQmMJB0OAB0DACEACQmMJB0OAB0DAAAA.',
In='Ines:BAACLgAFFH8HAAITAAMJ9RvxUAAQAQATAAMJ9RvxUAAQAQAuAAQKfzoAAhMACQlrJCUFACsDABMACQlrJCUFACsDAAAA.Insomiax:BAAALgAECggJDwAAAA==.Insta:BAABLgAECn8nAAIKAAcJzx3cIwA3AgAKAAcJzx3cIwA3AgAAAA==.Inter:BAABLgAECn8vAAIcAAkJ9yE6BAALAwAcAAkJ9yE6BAALAwAAAA==.',
Ir='Iridi:BAAALgADCgEJAQAAAA==.Iritall:BAAALgADCgcJCwAAAA==.',
It='Ithamburglar:BAAALgAECgQJBgAAAA==.',
Iz='Izureka:BAAALgADCgYJBgAAAA==.',
Ja='Jackidaytona:BAAALgAECgcJBwAAAA==.Jakaru:BAAALgAECgYJEgAAAA==.Jankadish:BAAALgAECgcJEwAAAA==.Jarre:BAACLgAFFH8GAAIFAAQJrggsDgAFAQAFAAQJrggsDgAFAQAuAAQKfygAAgUACAmzICIKAPMCAAUACAmzICIKAPMCAAAA.Jaspirian:BAAALgADCggJFAAAAA==.Jazzil:BAAALgADCgcJCgAAAA==.',
Jb='Jbaconcheese:BAAALgAECgEJAQAAAA==.',
Je='Jehmothy:BAAALgAECgUJBQAAAA==.Jerome:BAAALgAECgEJAQAAAA==.',
Jo='Jotabop:BAAALgAECgQJBgAAAA==.',
Ju='Judgequota:BAAALgAECgYJBgABLgAFFAQJDgAIAHUXAA==.Juicy:BAABLgAECn8YAAIYAAcJ+hY9FwCdAQAYAAcJ+hY9FwCdAQAAAA==.Juupiter:BAAALgAECgEJAQAAAA==.',
Ka='Kabu:BAAALgAECgcJBwAAAA==.Kalia:BAABLgAECn8vAAMUAAkJ/xj9KQAwAgAUAAkJ/xj9KQAwAgAiAAMJUg+5CQCmAAABLgADCgEJAQAQAAAAAA==.Kalitra:BAAALgADCgMJAwABLgADCgEJAQAQAAAAAA==.Katoumae:BAACLgAFFH8SAAIjAAUJNB0fAgCCAQAjAAUJNB0fAgCCAQAuAAQKfxwAAiMACAm0GvUFAKMCACMACAm0GvUFAKMCAAAA.Katoumey:BAAALgAECgYJCgABLgAFFAUJEgAjADQdAA==.',
Ke='Keratin:BAABLgAECn8nAAIkAAgJiiMEAgC2AgAkAAgJiiMEAgC2AgAAAA==.',
Kh='Khumi:BAABLgAECn8XAAIaAAgJYSCmEgCiAgAaAAgJYSCmEgCiAgABLgAFFAgJHQAhACsmAA==.',
Ki='Kinan:BAABLgAECn8tAAMZAAkJ8iXEAAB6AwAZAAkJ8iXEAAB6AwAaAAcJOx6kFwBxAgAAAA==.Kita:BAAALgAECggJEgABLgAECgkJAgAQAAAAAA==.',
Kk='Kkaarrkk:BAAALgAECgUJBQAAAA==.',
Kr='Krindon:BAABLgAECn8VAAIVAAcJ0QxjHgAeAQAVAAcJ0QxjHgAeAQAAAA==.',
Ku='Kureiji:BAAALgADCgEJAQAAAA==.',
Ky='Kythin:BAAALgADCgEJAQAAAA==.',
La='Lacutis:BAAALgAECgEJAQAAAA==.Laww:BAAALgADCgcJCgAAAA==.',
Le='Lecroix:BAAALgADCgUJBQAAAA==.Leonus:BAAALgAECgMJAwABLgAECgIJAgAQAAAAAA==.Lessana:BAAALgAECgIJBAAAAA==.Lethalforce:BAAALgADCgMJAwAAAA==.',
Li='Liandri:BAAALgADCgEJAgAAAA==.Lightchild:BAAALgADCggJCAAAAA==.Lightprivlge:BAAALgAECgIJAgAAAA==.Lillith:BAAALgAECgMJAwAAAA==.Livewire:BAAALgAECgQJBwAAAA==.',
Lo='Lokohmojo:BAAALgAECgMJBAAAAA==.Lomponic:BAEBLgAECn8qAAIRAAgJaRuODwASAgARAAgJaRuODwASAgAAAA==.Loomadin:BAAALgADCgYJCQAAAA==.',
Lu='Lunethra:BAABLgAECn8rAAIZAAkJwhGAKwAGAgAZAAkJwhGAKwAGAgAAAA==.',
Ma='Mageaux:BAAALgAECgEJAQAAAA==.Magerag:BAACLgAFFH8HAAIUAAMJQBjPUgD/AAAUAAMJQBjPUgD/AAAuAAQKfyoAAxQACAnWIbMvALMCABQACAnWIbMvALMCACIAAglAGkQVAHMAAAAA.Manamontana:BAACLgAFFH8YAAMTAAYJLBKtGwCGAQATAAUJLBKtGwCGAQAcAAEJAADzLwAAAAAuAAQKfxoAAhMACAn4H4AoAJgCABMACAn4H4AoAJgCAAAA.Marumo:BAAALgAECgMJBgAAAA==.',
Mc='Mcribz:BAACLgAFFH8YAAITAAYJyCPTCAD+AQATAAYJyCPTCAD+AQAuAAQKfyIAAhMACAl8IzIZAOUCABMACAl8IzIZAOUCAAAA.',
Me='Meelonusk:BAAALgAECgQJCAAAAA==.Mess:BAAALgAECgUJBgAAAA==.Messah:BAAALgAECgMJBwAAAA==.Messic:BAAALgADCgEJAQAAAA==.',
Mi='Michaelcoyle:BAABLgAECn8qAAIZAAgJNR0lHgAiAgAZAAgJNR0lHgAiAgAAAA==.Midnightcrow:BAAALgADCgkJDwAAAA==.Milo:BAACLgAFFH8FAAIKAAMJLyQvEwAyAQAKAAMJLyQvEwAyAQAuAAQKfzUAAwoACQlFI48CABkDAAoACQlFI48CABkDAAkACAluHBQEALQCAAAA.Mishra:BAAALgAECgUJBQAAAA==.Mitra:BAABLgAECn8mAAIXAAgJ6h1tAgBaAgAXAAgJ6h1tAgBaAgAAAA==.',
Mo='Moesko:BAAALgAECggJEQAAAA==.Mof:BAAALgADCgEJAQAAAA==.Mohawkk:BAAALgAECgQJBQAAAA==.Monktup:BAAALgAECgYJCwAAAA==.Monnehbaggs:BAABLgAECn8iAAMSAAkJEhz/DQB7AgASAAgJpR3/DQB7AgAfAAUJ4xAwMQD0AAAAAA==.Mortalidad:BAAALgADCgQJBAAAAA==.',
Mu='Muin:BAAALgAECgEJAQAAAA==.Murdersamich:BAAALgAECgQJCwAAAA==.',
My='Mybigcrits:BAAALgAECgYJDAAAAA==.',
['Mà']='Màevë:BAAALgAECgEJAgAAAA==.',
Na='Nairdax:BAAALgADCgEJAQAAAA==.Nalmec:BAABLgAECn8bAAIKAAYJ4QcwRQDdAAAKAAYJ4QcwRQDdAAAAAA==.Nama:BAAALgADCgYJBgAAAA==.Naysayre:BAABLgAECn8dAAIOAAYJigc2iwC0AAAOAAYJigc2iwC0AAAAAA==.',
Ne='Nebody:BAAALgAECgUJBQAAAA==.Necriss:BAABLgAECn8jAAIhAAkJgA18TACYAQAhAAkJgA18TACYAQAAAA==.',
Ni='Nightkilla:BAAALgAECgEJAwAAAA==.Nike:BAAALgAECggJDgAAAA==.Nilowin:BAABLgAECn8pAAIBAAgJvw+zFwCFAQABAAgJvw+zFwCFAQAAAA==.',
No='Nokaj:BAAALgAECgEJAgAAAA==.Noshards:BAAALgAECgcJDQAAAA==.Notericdh:BAAALgAECgYJEwAAAA==.',
Og='Oghom:BAAALgADCgcJCgAAAA==.',
Oh='Ohnoitzgumby:BAABLgAECn8VAAMTAAcJhBUkcAA6AQATAAUJghckcAA6AQAkAAMJoBJPFABOAAAAAA==.',
Om='Omiko:BAAALgAECgIJAgAAAA==.',
Op='Opeep:BAAALgADCgcJGQAAAA==.',
Or='Orah:BAAALgADCgEJAQAAAA==.',
Os='Osos:BAAALgAECgYJEAAAAA==.',
Pa='Paladimdab:BAAALgAECgQJBQAAAA==.Papachance:BAAALgAECgUJCAAAAA==.Papafrank:BAAALgADCgkJFwAAAA==.Paradis:BAAALgADCgcJBwAAAA==.Pazuzu:BAAALgADCgYJBgAAAA==.',
Pe='Peepo:BAAALgAECgEJAQAAAA==.',
Pi='Pinga:BAAALgAECgYJEAABLgAECgkJMAAlAD0iAA==.Pinkberry:BAAALgAECgQJBAAAAA==.Pintcube:BAAALgADCgYJCAAAAA==.',
Pl='Pljeskavica:BAAALgAECgYJBwAAAA==.Plox:BAAALgAECgMJAwAAAA==.',
Po='Port:BAABLgAECn8nAAIFAAkJ4B5EDAC9AgAFAAkJ4B5EDAC9AgAAAA==.Potroastjr:BAAALgADCgEJAgABLgAECgEJAQAQAAAAAA==.',
Pr='Primordus:BAAALgADCgUJBQAAAA==.Profiler:BAAALgAECgcJCAAAAA==.Protocol:BAAALgAECgMJAwAAAA==.Prïestess:BAAALgAECgYJBQAAAA==.',
Ps='Pseriph:BAABLgAECn8ZAAIDAAcJ3BZrCwAKAgADAAcJ3BZrCwAKAgAAAA==.',
Ra='Radamantis:BAAALgAECgMJAwAAAA==.Raenon:BAAALgADCgkJEAAAAA==.Raggnar:BAACLgAFFH8KAAIIAAMJcB6FGAAOAQAIAAMJcB6FGAAOAQAuAAQKfywAAggACAkcIoUIAJACAAgACAkcIoUIAJACAAAA.Ragingwaters:BAAALgADCgYJCAAAAA==.Ranvir:BAAALgAECgEJAQAAAA==.Raun:BAABLgAECn8yAAMhAAkJACG9CQDmAgAhAAkJACG9CQDmAgANAAMJJBEvcgCzAAAAAA==.',
Re='Regnarr:BAAALgADCgEJAQAAAA==.Rehgar:BAAALgAFFAEJAQAAAA==.Relaire:BAABLgAECn8eAAIZAAgJSw/IOwCbAQAZAAgJSw/IOwCbAQAAAA==.Resonate:BAAALgAFFAIJAwAAAA==.',
Ri='Rikane:BAAALgADCgcJDAABLgADCgcJEgAQAAAAAA==.Rikenji:BAAALgADCgMJAwAAAA==.Riku:BAABLgAECn8tAAIjAAkJ1x+dAQDvAgAjAAkJ1x+dAQDvAgAAAA==.',
Ro='Rock:BAAALgAECgcJDQAAAA==.Rockyrag:BAAALgADCgEJAQAAAA==.Roguey:BAABLgAECn8lAAMmAAkJ8w1TCAB+AQAmAAcJlBFTCAB+AQABAAYJDwoPJgAGAQAAAA==.Roots:BAAALgAECgEJBgAAAA==.',
Ru='Rulethrefour:BAAALgAECgMJBAAAAA==.',
Ry='Ryveri:BAABLgAECn8lAAIKAAkJDxndEAAmAgAKAAkJDxndEAAmAgAAAA==.',
Sa='Sablehide:BAABLgAECn8lAAIHAAgJnRScHgCSAQAHAAgJnRScHgCSAQAAAA==.Sanaron:BAAALgADCgIJAgAAAA==.Sanaty:BAAALgAFFAEJAQAAAA==.Saryn:BAAALgAECgYJDwAAAA==.Satanz:BAAALgADCgIJAgAAAA==.Sathanus:BAAALgAECgQJBwAAAA==.',
Se='Searate:BAAALgADCgcJEgAAAA==.Seaside:BAACLgAFFH8PAAITAAMJ/iUGMABSAQATAAMJ/iUGMABSAQAuAAQKfxYAAxMABwk9JYUtAAICABMABwk9JYUtAAICABwAAgmEC+8/AE4AAAAA.Secrett:BAABLgAECn8YAAMBAAcJ9xMLHQBQAQABAAcJ9xMLHQBQAQAmAAEJew4yHwA0AAAAAA==.Sephyxia:BAABLgAECn8vAAIcAAkJcxqpBwBVAgAcAAkJcxqpBwBVAgAAAA==.Serryon:BAAALgADCgIJAgAAAA==.',
Sf='Sfora:BAAALgADCgkJEQAAAA==.',
Sh='Shadowwzz:BAAALgADCgEJAQAAAA==.Shoçknezz:BAAALgAECgMJBQAAAA==.',
Si='Silverwolf:BAABLgAECn8zAAIeAAkJjx8wAwCPAgAeAAkJjx8wAwCPAgAAAA==.Simplyunlock:BAACLgAFFH8HAAICAAMJqAhYVwDOAAACAAMJqAhYVwDOAAAuAAQKfyYAAwIACAl1FWEvANwBAAIACAl1FWEvANwBAAMAAgnnBZVmAEMAAAAA.Simplyvoided:BAAALgAECgQJBgAAAA==.Sinverguenza:BAAALgAECgMJBQAAAA==.Sizzlechop:BAABLgAECn8hAAITAAgJmQm/ZwBNAQATAAgJmQm/ZwBNAQAAAA==.',
Sk='Skizzak:BAAALgADCgQJBAABLgAFFAYJGAATAMgjAA==.Skweeks:BAAALgAECgMJBAAAAA==.',
Sm='Smelvin:BAABLgAECn8bAAIIAAkJ8xlsFgBmAgAIAAkJ8xlsFgBmAgABLgAECgQJCAAQAAAAAA==.Smoko:BAAALgAECgIJAgABLgAECgUJBQAQAAAAAA==.',
Sn='Snailslolol:BAAALgAECgEJAgAAAA==.Snakey:BAECLgAFFH8QAAMHAAQJggZtJAD2AAAHAAQJggZtJAD2AAAnAAEJ1wLRCgBDAAAuAAQKfyYAAwcACAmLGD4aAPkBAAcACAmLGD4aAPkBACcABgl5BHkmAO8AAAAA.',
So='Solara:BAABLgAECn8gAAQRAAgJSRlsFADaAQARAAgJSRlsFADaAQASAAEJQAIShwApAAAfAAEJXgKYXgAkAAAAAA==.Soleill:BAAALgAECgcJBwAAAA==.Sondan:BAAALgADCgMJAwAAAA==.Songs:BAAALgAECgEJAQABLgAECgYJGAAMAP8gAA==.',
Sp='Spellpowa:BAAALgAECgYJDgAAAA==.',
Ss='Ssminion:BAAALgAECgEJAwAAAA==.',
St='Stormwing:BAABLgAECn8dAAIIAAgJMRlYGQDDAQAIAAgJMRlYGQDDAQAAAA==.Strecagosa:BAAALgAECgYJDQAAAA==.',
Sv='Svenn:BAAALgAECgYJBgAAAA==.',
Sy='Sybelissa:BAAALgAECgMJAwABLgAECgcJCgAQAAAAAA==.Synni:BAAALgADCgEJAQAAAA==.',
['Sÿ']='Sÿnÿster:BAAALgADCgMJAwABLgAFFAQJDAAZANAXAA==.',
Ta='Talron:BAAALgAECgQJBwAAAA==.Tastytay:BAAALgADCgMJAwAAAA==.Tatertots:BAABLgAECn8pAAMkAAkJsx6wAQCzAgAkAAkJsx6wAQCzAgATAAMJ8hON7ACmAAAAAA==.',
Te='Tea:BAABLgAECn8oAAIZAAkJkCJEBgD5AgAZAAkJkCJEBgD5AgAAAA==.Teal:BAAALgAECgMJAwAAAA==.Templyn:BAAALgAECgcJDAAAAA==.Templÿn:BAAALgADCgIJAgABLgAECgcJDAAQAAAAAA==.Tenebrarum:BAABLgAECn8bAAIZAAgJGQ2cWwA2AQAZAAgJGQ2cWwA2AQAAAA==.Testorooni:BAABLgAECn8ZAAIZAAcJkBgpMwDjAQAZAAcJkBgpMwDjAQAAAA==.',
Th='Thakodi:BAAALgAECgQJBAAAAA==.Thannos:BAAALgADCgEJAQAAAA==.Tharvan:BAAALgADCgcJDAAAAA==.Thedeadman:BAABLgAECn8kAAITAAkJEiJqEgCbAgATAAkJEiJqEgCbAgAAAA==.Thepriestg:BAAALgAECgEJAQAAAA==.Thiccksilver:BAAALgADCgcJBwAAAA==.Thompson:BAABLgAECn8VAAITAAcJuxTYawBEAQATAAcJuxTYawBEAQAAAA==.Thunderflaps:BAAALgAECgUJCQAAAA==.Thyrus:BAABLgAECn8wAAMlAAkJPSJpAwDRAgAlAAkJPSJpAwDRAgAnAAEJqgL7RAAjAAAAAA==.',
Ti='Tirna:BAABLgAECn8vAAIgAAkJVAwJAwCeAQAgAAkJVAwJAwCeAQAAAA==.',
To='Tobi:BAAALgAECgkJCQABLgAFFAIJAwAQAAAAAA==.Toebot:BAAALgAECgEJAQAAAA==.Tomsellock:BAABLgAECn8WAAMEAAcJjhBuBwDcAQAEAAcJjhBuBwDcAQACAAEJugM+LAEmAAAAAA==.Tonari:BAAALgAECgEJAQABLgAECgYJEAAQAAAAAA==.Torvi:BAAALgADCgMJAwAAAA==.',
Tr='Transmørtuus:BAAALgAECgQJCQAAAA==.Treehug:BAAALgAECggJEwAAAA==.Triple:BAAALgAECgQJBwABLgAECgYJEAAQAAAAAA==.Trolleonne:BAAALgAECgIJAgAAAA==.',
Tu='Tullen:BAEBLgAECn8sAAISAAkJQxGeGQC0AQASAAkJQxGeGQC0AQAAAA==.Turanos:BAAALgAECgQJBwAAAA==.',
Tw='Tweyen:BAAALgAECgEJAQAAAA==.',
Ty='Tyindaris:BAAALgAECgQJCgAAAA==.Tyloregeth:BAABLgAECn8mAAIRAAgJpxT+GwCQAQARAAgJpxT+GwCQAQAAAA==.',
['Tè']='Tèmplyn:BAAALgADCgEJAQABLgAECgcJDAAQAAAAAA==.',
['Té']='Témplýn:BAAALgADCgEJAQABLgAECgcJDAAQAAAAAA==.',
['Të']='Tëmplýn:BAAALgAECgEJAQABLgAECgcJDAAQAAAAAA==.',
Ul='Ulfrunn:BAAALgADCgYJBgAAAA==.Ultrachad:BAACLgAFFH8UAAITAAUJxxx4KABhAQATAAUJxxx4KABhAQAuAAQKfx4AAhMACAlIIwUUAAMDABMACAlIIwUUAAMDAAAA.',
Um='Umami:BAABLgAECn8gAAIKAAYJ+RgpNwAaAQAKAAYJ+RgpNwAaAQAAAA==.',
Un='Unggoy:BAACLgAFFH8XAAMaAAgJGR38AgAkAgAaAAgJ8Rv8AgAkAgAZAAIJsRlcQQC5AAAuAAQKfygAAxoACQkhJrsBAKYDABoACQkhJrsBAKYDABkAAQnFJeCtAG8AAAAA.Unholywaters:BAAALgAECgIJBQAAAA==.',
Ur='Urianna:BAAALgAECgIJBgAAAA==.',
Va='Vaelthirion:BAABLgAECn8hAAIUAAgJRBS7SAC+AQAUAAgJRBS7SAC+AQAAAA==.Vahidamus:BAAALgAECgYJBwAAAA==.Valkaryon:BAAALgAECgcJCgABLgAFFAIJAwAQAAAAAA==.Valmirax:BAAALgADCggJEgAAAA==.Valton:BAABLgAECn86AAIhAAYJ5hAOgQAhAQAhAAYJ5hAOgQAhAQAAAA==.',
Ve='Vegetation:BAAALgAECgQJBgAAAA==.Velenestus:BAAALgAECgMJBgAAAA==.Verses:BAAALgADCgEJAQAAAA==.',
Vi='Vizsla:BAAALgAECgEJAQAAAA==.',
Wa='Wackaman:BAABLgAECn8eAAILAAgJ1xtFCQAZAgALAAgJ1xtFCQAZAgAAAA==.Warpig:BAAALgAECgYJEQAAAA==.Wasps:BAAALgAECgYJEQAAAA==.',
We='Wegmaniac:BAAALgADCgYJCAAAAA==.Welastrexa:BAAALgADCgUJBQABLgADCgYJCAAQAAAAAA==.',
Wi='Wickedclöwn:BAAALgADCgMJAwAAAA==.Winchester:BAAALgADCgIJAgAAAA==.Windhorn:BAAALgADCggJEQAAAA==.Winds:BAABLgAECn8YAAIMAAYJ/yBoFwAqAgAMAAYJ/yBoFwAqAgAAAA==.',
Wn='Wntrizcoming:BAAALgADCgMJBQAAAA==.',
Wo='Wolfquota:BAACLgAFFH8OAAIIAAQJdRfwEQAzAQAIAAQJdRfwEQAzAQAuAAQKfx8AAwgACAlGIkkJAP4CAAgACAlGIkkJAP4CAB4ABAntE08eAOkAAAAA.Wolftime:BAAALgADCgUJBQAAAA==.Wombaa:BAACLgAFFH8OAAITAAQJ9CKsFAChAQATAAQJ9CKsFAChAQAuAAQKfxwAAhMACAleJGEKAEgDABMACAleJGEKAEgDAAAA.',
Wr='Wrathbolt:BAAALgAECgEJAQABLgAECggJJQAMAGQcAA==.Wrathmo:BAABLgAECn8lAAMMAAgJZByEDAAvAgAMAAcJaR6EDAAvAgAoAAcJHQopMgD8AAAAAA==.Wrolie:BAAALgADCgMJAwAAAA==.',
['Wê']='Wêêdyys:BAAALgADCgMJBAAAAA==.',
Xy='Xyr:BAAALgAECgEJAQABLgAECggJJQARAKsPAA==.',
Yo='Yougotsniped:BAAALgADCgEJAQAAAA==.',
Za='Zandalia:BAAALgAECgMJAwAAAA==.Zark:BAEALgADCgcJBwABLgAECggJFAAWAL8XAA==.',
Ze='Zemphoths:BAAALgAECgUJCAAAAA==.',
Zo='Zoa:BAAALgADCgYJBgAAAA==.Zolton:BAAALgADCgMJAwAAAA==.Zornak:BAAALgAECgUJBQAAAA==.',
['Åe']='Åequitas:BAAALgAECgYJCQAAAA==.',
['ßa']='ßahamut:BAAALgAECgQJBQAAAA==.',
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
