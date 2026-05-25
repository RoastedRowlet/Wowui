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

local lookup = {'Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Druid-Restoration','Evoker-Augmentation','Mage-Frost','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Warrior-Protection','Monk-Windwalker','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Unknown-Unknown','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','Paladin-Retribution','DemonHunter-Havoc','Shaman-Restoration','Rogue-Outlaw','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','DeathKnight-Blood','Druid-Guardian','Shaman-Enhancement','Priest-Discipline','Mage-Fire','Mage-Arcane','Druid-Feral','DeathKnight-Frost','Evoker-Preservation','Rogue-Assassination','Evoker-Devastation','Monk-Brewmaster',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aamon:BAAALgAECgQJCgAAAA==.',
Ab='Abacus:BAABLgAECn8jAAIBAAkJjyJeCAB+AgABAAkJjyJeCAB+AgAAAA==.',
Ad='Adam:BAACLgAFFH8VAAQCAAcJ4Rm8JQBpAQACAAUJLhy8JQBpAQADAAMJlBFcDQCiAAAEAAEJNR2uEABYAAAuAAQKfy4ABAIACQk2JF4WAM4CAAIACQmcI14WAM4CAAMABQljJKcNAOsBAAQAAQkaI+cjAGMAAAAA.Adedruid:BAABLgAECn8gAAMFAAYJdR9cKwCnAQAFAAYJdR9cKwCnAQAGAAYJ3xoBSgB6AQAAAA==.Adevoker:BAAALgAECgQJBAAAAA==.Adragon:BAABLgAECn8nAAIHAAkJ5RqjDAB1AgAHAAkJ5RqjDAB1AgAAAA==.',
Ae='Aengyl:BAAALgAECgQJBAAAAA==.Aeonne:BAABLgAECn8VAAIIAAgJyxLBfgBdAQAIAAgJyxLBfgBdAQAAAA==.',
Ak='Akshul:BAABLgAECn8UAAIJAAYJ5Q1HRgAvAQAJAAYJ5Q1HRgAvAQAAAA==.Akurama:BAAALgAECgcJCgAAAA==.',
Al='Aldrea:BAAALgAECgYJCwAAAA==.Allsmiles:BAABLgAECn8UAAQKAAkJwB3tCAAhAgAKAAgJhRrtCAAhAgALAAUJChm2TQBwAQAMAAMJ7R0oKgDvAAAAAA==.Allura:BAAALgAECgQJBwAAAA==.Alorian:BAAALgAECgIJAgAAAA==.Alttharius:BAAALgAECgMJAwABLgAECgkJGQANALQgAA==.Alyysha:BAABLgAECn8bAAIOAAcJlwkCRgBgAQAOAAcJlwkCRgBgAQAAAA==.',
Am='Amoon:BAABLgAECn81AAMPAAkJgBkHIQAxAgAPAAkJ0RcHIQAxAgAQAAYJBRWnDwAnAQAAAA==.',
An='Andoriel:BAAALgADCgcJBwABLgAFFAIJAwARAAAAAA==.Angelrain:BAABLgAECn8sAAMSAAgJWByRDgCaAgASAAgJWByRDgCaAgATAAcJ8QfEMgAYAQAAAA==.Aniata:BAAALgAECgEJAQAAAA==.',
Ar='Archymedes:BAABLgAECn8sAAILAAcJJxHWMgBZAQALAAcJJxHWMgBZAQAAAA==.Arckady:BAAALgAECgQJCgAAAA==.Areko:BAAALgAECgIJBAAAAA==.Artharius:BAABLgAECn8ZAAINAAkJtCApEwD+AQANAAkJtCApEwD+AQAAAA==.',
Au='Auburnbeard:BAAALgADCgYJBgAAAA==.Aumed:BAAALgADCgEJAQAAAA==.',
Av='Averle:BAABLgAECn9NAAIDAAcJYweSFADdAAADAAcJYweSFADdAAAAAA==.',
Az='Azrran:BAAALgADCgEJAQAAAA==.Aztharot:BAAALgAECgIJAgAAAA==.',
Ba='Badchoices:BAAALgAECgMJAwAAAA==.Badkittie:BAAALgAECgIJAgAAAA==.Balding:BAAALgAECgEJAQAAAA==.Baphico:BAAALgADCgUJBQAAAA==.',
Be='Behemoth:BAAALgAECgEJAQAAAA==.Belinda:BAAALgAECgEJAQABLgAFFAYJGAAUAMgjAA==.Bettyßaraxus:BAAALgAECgMJAwABLgAECggJJAAVAEIdAA==.Bewater:BAAALgADCgcJBwAAAA==.',
Bl='Bladesmcgee:BAAALgAECgcJBwABLgAECgQJCAARAAAAAA==.Blasphem:BAAALgADCgQJBAAAAA==.',
Bo='Bobadelphia:BAAALgADCgYJBgABLgAECgYJEQARAAAAAA==.Bofahdeez:BAABLgAECn8aAAMTAAgJfA6+PABHAQATAAcJWA6+PABHAQASAAcJLQz5MAAvAQAAAA==.Bogs:BAACLgAFFH8RAAIIAAQJmx2nNwBTAQAIAAQJmx2nNwBTAQAuAAQKfyMAAggACAnrIb4jAOQCAAgACAnrIb4jAOQCAAAA.Bonedaddy:BAAALgAECgYJBgAAAA==.',
Br='Brewswayne:BAAALgADCgQJBAABLgAFFAIJAwARAAAAAA==.Brolic:BAABLgAECn8rAAMWAAgJ8x30CwAwAgAWAAgJ8x30CwAwAgAPAAEJJgmh/QAkAAAAAA==.',
['Bä']='Bämboo:BAAALgAFFAEJAQABLgAFFAQJCQAXAOoQAA==.',
Ca='Cail:BAEBLgAECn8ZAAIXAAkJexYPGQBVAgAXAAkJexYPGQBVAgAAAA==.Calamìty:BAAALgADCgcJDgABLgAECgkJJwAGAAsPAA==.Calisa:BAABLgAECn87AAIYAAkJ6h/7AADxAgAYAAkJ6h/7AADxAgAAAA==.Cardio:BAAALgAECgIJAQAAAA==.Carnifexx:BAAALgAFFAIJAgABLgAFFAYJGwAPADcZAA==.Cassey:BAAALgAECgEJAQAAAA==.',
Ce='Celesteus:BAAALgADCgkJFAAAAA==.',
Ch='Charis:BAAALgAECgYJCwAAAA==.Chigutotems:BAAALgAECgYJCgABLgAECgkJGwAPAGwWAA==.Choi:BAAALgAECgUJDwAAAA==.Chooq:BAAALgADCgIJAgAAAA==.Chozen:BAAALgAECgUJEAAAAA==.Chumlee:BAAALgAECgUJBQAAAA==.',
Ci='Cienna:BAAALgAECgYJDgAAAA==.Cigz:BAAALgADCgEJAQAAAA==.Cinch:BAAALgAECgIJAgAAAA==.',
Co='Colinferral:BAAALgAECgYJCAAAAA==.Coulee:BAAALgAECgQJBwABLgAECggJJgAWABofAA==.Cowladin:BAAALgADCgUJBQAAAA==.',
Cr='Crakzkull:BAAALgAECgUJCwAAAA==.Croar:BAAALgAECgMJBAAAAA==.Cronicpain:BAAALgADCgkJCQAAAA==.',
['Cä']='Cäntstandya:BAACLgAFFH8RAAMZAAQJVRgnFQD8AAAZAAMJnxcnFQD8AAAaAAMJmRgrQwDkAAAuAAQKfyMAAxoACAkvG1cSAKUCABoACAliGVcSAKUCABkABwkaHngPABwCAAAA.',
Da='Daiko:BAAALgAECgYJCQAAAA==.Daks:BAAALgAFFAIJAwAAAA==.Dargo:BAAALgAECgYJEwAAAA==.Darklucrezia:BAACLgAFFH8QAAMaAAQJjhxHFwBjAQAaAAQJjhxHFwBjAQAbAAIJNgKIJQBRAAAuAAQKfywAAxoACAn3HyoVAIACABoACAltHyoVAIACABsACAkOEeQlAPoBAAAA.Dazzlefraz:BAAALgAECgQJBAAAAA==.',
De='Demonklunter:BAAALgADCgYJEAAAAA==.Destructoid:BAAALgAECgEJAQAAAA==.',
Di='Dicey:BAAALgADCgMJAwABLgAECgQJBwARAAAAAA==.',
Do='Dochunter:BAAALgAECgUJBQAAAA==.',
Dr='Dracarius:BAAALgAECgQJCwAAAA==.Drega:BAAALgAECgYJBwAAAA==.Droods:BAAALgAECgQJBQAAAA==.Drtypinkcake:BAABLgAECn8aAAIWAAYJSAiZMADIAAAWAAYJSAiZMADIAAAAAA==.Druskgar:BAABLgAECn8fAAIUAAgJzyHnNgABAgAUAAgJzyHnNgABAgAAAA==.Dryad:BAAALgAECgQJCwAAAA==.',
Du='Duckster:BAAALgADCgYJBwAAAA==.Dunce:BAABLgAECn8gAAIcAAgJ9h/SDACZAgAcAAgJ9h/SDACZAgAAAA==.Durkk:BAABLgAECn87AAIdAAkJ9yGJAwDpAgAdAAkJ9yGJAwDpAgAAAA==.Durza:BAAALgAECgcJEAAAAA==.',
['Dä']='Dännydevito:BAAALgADCgQJBAAAAA==.',
Ed='Eduard:BAAALgAECgYJCQAAAA==.',
Ek='Eklipse:BAAALgAECgMJAwAAAA==.',
El='Elanthae:BAAALgAECgQJEAAAAA==.Elysia:BAAALgAECgEJAgAAAA==.',
Er='Erzulie:BAAALgAECgUJBAAAAA==.',
Es='Estara:BAABLgAECn81AAIeAAkJqwsIHAAqAQAeAAkJqwsIHAAqAQAAAA==.',
Et='Etali:BAABLgAECn8yAAILAAkJQBwvDACEAgALAAkJQBwvDACEAgAAAA==.',
Ez='Ezazel:BAAALgADCgUJBwAAAA==.',
Fa='Faite:BAAALgADCgUJBQAAAA==.Falorin:BAABLgAECn8eAAIIAAcJEhbzbgB/AQAIAAcJEhbzbgB/AQAAAA==.Fanis:BAABLgAECn8mAAIbAAkJzRVcBwDuAQAbAAkJzRVcBwDuAQAAAA==.Fatherwhig:BAAALgAECgIJAwAAAA==.',
Fi='Fidis:BAAALgADCgkJCwAAAA==.Fistsofdeath:BAAALgADCggJCgAAAA==.Fistychub:BAAALgADCgEJAQAAAA==.',
Fl='Flashbang:BAAALgADCgEJAQAAAA==.Flashis:BAAALgAECggJEwAAAA==.Florago:BAAALgAECgQJCwAAAA==.',
Fr='Frakir:BAABLgAECn87AAQXAAkJ5xk1EwCHAgAXAAkJ5xk1EwCHAgAfAAMJRwrVIgCMAAAJAAEJkAYjkwAjAAAAAA==.Fritzz:BAAALgAECgcJEgAAAA==.Frog:BAAALgAECgIJBQAAAA==.',
Fu='Furrypaw:BAABLgAECn8uAAIcAAkJZiUbAQDCAwAcAAkJZiUbAQDCAwAAAA==.',
Fw='Fwapp:BAACLgAFFH8YAAIOAAYJ6B6ACgDHAQAOAAYJ6B6ACgDHAQAuAAQKfxcAAg4ACAlrIcgLAL8CAA4ACAlrIcgLAL8CAAAA.',
Ga='Galvanize:BAAALgAECgEJAwAAAA==.Galynisse:BAABLgAECn8tAAMgAAgJKhf/EQApAgAgAAgJKhf/EQApAgATAAMJ7A4eZQCZAAAAAA==.',
Ge='Gedorah:BAABLgAECn8fAAIhAAcJOByDAgD1AQAhAAcJOByDAgD1AQABLgAFFAMJDQAJAFkiAA==.',
Gh='Ghaspy:BAAALgAECgUJCgAAAA==.Ghoste:BAAALgADCgMJAwAAAA==.Ghrex:BAAALgAECgEJAQAAAA==.',
Gi='Gijaick:BAABLgAECn8rAAMCAAgJLBiKPwDGAQACAAgJLBiKPwDGAQADAAEJHg4AdAAxAAAAAA==.',
Gl='Glaivethrow:BAABLgAECn8bAAIPAAkJbBYBNADWAQAPAAkJbBYBNADWAQAAAA==.Glizzo:BAAALgAECgYJDAAAAA==.Gloam:BAAALgADCgUJBQAAAA==.',
Go='Gochujjang:BAAALgAECgYJDQAAAA==.Goldhawk:BAAALgAECgMJAwAAAA==.Gotchá:BAAALgAECgEJBAAAAA==.Gotwiped:BAABLgAECn8WAAIUAAgJfRqxLwAdAgAUAAgJfRqxLwAdAgAAAA==.',
Gr='Grimgor:BAAALgAECgcJAQAAAA==.',
Ha='Hahaheals:BAAALgAECgMJBAAAAA==.Hakhar:BAAALgADCgMJAwAAAA==.Hanth:BAAALgADCgUJBAABLgAECgMJAwARAAAAAA==.Hatter:BAABLgAECn8jAAQPAAgJ2hNMXgBKAQAPAAgJaRNMXgBKAQAWAAMJ+AsRWACGAAAQAAEJNRMmKwA0AAAAAA==.',
He='Healsus:BAAALgAECgMJAwAAAA==.Heimlish:BAAALgAECgEJAQAAAA==.Hellraiser:BAABLgAECn8gAAMUAAYJnBrOcQBbAQAUAAYJYxnOcQBbAQAdAAUJrg9/LwC0AAAAAA==.Hermione:BAAALgAECgYJDQAAAA==.Hexecution:BAAALgADCgIJAgAAAA==.',
Hi='Hiddendragon:BAAALgAECgEJAQAAAA==.',
Ho='Holydarkness:BAAALgAECgQJBAAAAA==.Holykilla:BAAALgAECgEJBAAAAA==.Holykiller:BAAALgAECgEJAgAAAA==.Hoofjob:BAAALgADCggJDgABLgAFFAQJDAAgAPEeAA==.Hoplite:BAAALgADCgYJCAABLgAECggJEgARAAAAAA==.Hotot:BAAALgADCgMJAwAAAA==.',
Hu='Huffpuffle:BAAALgAECgUJCgAAAA==.',
['Hô']='Hôwl:BAABLgAECn8YAAIGAAcJwhAfQABuAQAGAAcJwhAfQABuAQAAAA==.',
Ic='Icdeathg:BAACLgAFFH8JAAIPAAMJ/QsGUADJAAAPAAMJ/QsGUADJAAAuAAQKfysAAg8ACAmGGgAuAPABAA8ACAmGGgAuAPABAAAA.',
Ik='Iktaar:BAAALgAECgQJBQAAAA==.',
Il='Illidami:BAAALgADCgkJCwAAAA==.Illidamngirl:BAAALgADCgYJBgABLgAECgkJJwAMALwcAA==.',
Im='Imperius:BAACLgAFFH8VAAIVAAUJHBb7LQAzAQAVAAUJHBb7LQAzAQAuAAQKfyQAAhUACQmMJB0OAB0DABUACQmMJB0OAB0DAAAA.',
In='Ines:BAACLgAFFH8KAAIUAAMJWSHVWAAdAQAUAAMJWSHVWAAdAQAuAAQKfzoAAhQACQlrJHgHAB4DABQACQlrJHgHAB4DAAAA.Insomiax:BAAALgAECggJDwAAAA==.Insta:BAABLgAECn8pAAILAAcJzx3cIwA3AgALAAcJzx3cIwA3AgAAAA==.Inter:BAABLgAECn8vAAIdAAkJ9yE6BAALAwAdAAkJ9yE6BAALAwAAAA==.',
Ir='Iridi:BAAALgADCgEJAQAAAA==.Iritall:BAAALgADCgcJCwAAAA==.',
It='Ithamburglar:BAAALgAECgQJBwAAAA==.',
Iz='Izureka:BAAALgADCgYJBgAAAA==.',
Ja='Jackidaytona:BAAALgAECgcJBwAAAA==.Jakaru:BAAALgAFFAEJAQAAAA==.Jankadish:BAAALgAECgcJEwAAAA==.Jarre:BAACLgAFFH8GAAIGAAQJrggsDgAFAQAGAAQJrggsDgAFAQAuAAQKfygAAgYACAmzICIKAPMCAAYACAmzICIKAPMCAAAA.Jaspirian:BAAALgADCggJFAAAAA==.Jazzil:BAAALgADCgcJCgAAAA==.',
Jb='Jbaconcheese:BAAALgAECgEJAQAAAA==.',
Je='Jehmothy:BAAALgAECgUJBQAAAA==.Jerome:BAAALgAECgEJAQAAAA==.',
Jo='Jotabop:BAAALgAECgQJBgAAAA==.',
Ju='Judgequota:BAAALgAFFAIJAgABLgAFFAQJEAAJACceAA==.Juicy:BAABLgAECn8eAAIZAAkJmRb6CwBJAgAZAAkJmRb6CwBJAgAAAA==.Juupiter:BAAALgAECgEJAQAAAA==.',
Ka='Kabu:BAAALgAECgcJBwAAAA==.Kalia:BAABLgAECn8vAAMIAAkJ/xh3NAApAgAIAAkJ/xh3NAApAgAiAAMJUg/rCgCgAAAAAA==.Kalitra:BAAALgADCgMJAwABLgAECgkJLwAIAP8YAA==.Katoumae:BAACLgAFFH8SAAIjAAUJNB1VAwBmAQAjAAUJNB1VAwBmAQAuAAQKfx0AAiMACAklG/UFAKMCACMACAklG/UFAKMCAAAA.Katoumey:BAAALgAECgYJCgABLgAFFAUJEgAjADQdAA==.',
Ke='Keratin:BAABLgAECn8sAAIkAAkJvSJ7AgCkAgAkAAkJvSJ7AgCkAgAAAA==.',
Kh='Khumi:BAABLgAECn8XAAIbAAgJYSCmEgCiAgAbAAgJYSCmEgCiAgABLgAFFAkJIwAVAOkkAA==.',
Ki='Kinan:BAABLgAECn82AAMaAAkJHSbeAACBAwAaAAkJHSbeAACBAwAbAAcJOx6kFwBxAgAAAA==.Kita:BAAALgAECggJEgABLgAECgkJAgARAAAAAA==.',
Kk='Kkaarrkk:BAAALgAECgUJBQAAAA==.',
Kr='Krindon:BAABLgAECn8aAAIWAAcJKw8IIwAlAQAWAAcJKw8IIwAlAQAAAA==.',
Ku='Kureiji:BAAALgADCgEJAQAAAA==.',
Ky='Kythin:BAAALgAECgEJAQABLgAECgkJLwAIAP8YAA==.',
La='Lacutis:BAAALgAECgEJAQAAAA==.Lanssolo:BAAALgADCgUJBQAAAA==.Laww:BAAALgADCgcJCgAAAA==.',
Le='Lecroix:BAAALgADCgUJBQAAAA==.Leonus:BAAALgAECgMJAwABLgAECgIJAgARAAAAAA==.Lessana:BAAALgAECgQJCwAAAA==.Lethalforce:BAAALgADCgMJAwAAAA==.',
Li='Liandri:BAAALgADCgEJAgAAAA==.Lightchild:BAAALgADCggJCAAAAA==.Lightprivlge:BAAALgAECgcJDQAAAA==.Lillith:BAAALgAECgMJAwAAAA==.Livewire:BAAALgAECgQJCwAAAA==.',
Lo='Lokohmojo:BAAALgAECgMJBAAAAA==.Lomponic:BAEBLgAECn8zAAISAAkJ4RvVCwBwAgASAAkJ4RvVCwBwAgAAAA==.Loomadin:BAAALgADCgYJCQAAAA==.',
Lu='Lunethra:BAABLgAECn8rAAIaAAkJwhGAKwAGAgAaAAkJwhGAKwAGAgAAAA==.',
Ma='Mageaux:BAAALgAECgEJAQAAAA==.Magerag:BAACLgAFFH8JAAIIAAMJGBt4XQD+AAAIAAMJGBt4XQD+AAAuAAQKfy0AAwgACAnWIbMvALMCAAgACAnWIbMvALMCACIAAglAGkQVAHMAAAAA.Manamontana:BAACLgAFFH8YAAMUAAYJLBI0LABvAQAUAAUJLBI0LABvAQAdAAEJAAClOQAAAAAuAAQKfxoAAhQACAn4H4AoAJgCABQACAn4H4AoAJgCAAAA.Marumo:BAAALgAECgMJBgAAAA==.',
Mc='Mcribz:BAACLgAFFH8YAAIUAAYJyCONDwDqAQAUAAYJyCONDwDqAQAuAAQKfyIAAhQACAl8IzIZAOUCABQACAl8IzIZAOUCAAAA.',
Me='Meelonusk:BAAALgAECgQJCAAAAA==.Mess:BAAALgAECgYJCwAAAA==.Messah:BAAALgAECgQJCgAAAA==.Messic:BAAALgADCgEJAQAAAA==.',
Mi='Michaelcoyle:BAABLgAECn8yAAIaAAgJiB59GwBXAgAaAAgJiB59GwBXAgAAAA==.Midnightcrow:BAAALgADCgkJDwAAAA==.Milo:BAACLgAFFH8HAAILAAMJLyRhGwAgAQALAAMJLyRhGwAgAQAuAAQKfzcAAwsACQlFI/oDAA4DAAsACQlFI/oDAA4DAAoACAluHBQEALQCAAAA.Mishra:BAAALgAECgUJBQAAAA==.Mitra:BAABLgAECn8uAAIYAAgJlR6QAgBvAgAYAAgJlR6QAgBvAgAAAA==.',
Mo='Moesko:BAAALgAECggJEgAAAA==.Mof:BAAALgADCgEJAQAAAA==.Mohawkk:BAAALgAECgQJBQAAAA==.Monktup:BAAALgAECgYJCwAAAA==.Monnehbaggs:BAABLgAECn8oAAMTAAkJExz/DQB7AgATAAgJpR3/DQB7AgAgAAgJhxj3DQBiAgAAAA==.Mortalidad:BAAALgADCgQJBAAAAA==.',
Mu='Muin:BAAALgAECgEJAQAAAA==.Murdersamich:BAAALgAECgQJCwAAAA==.',
My='Mybigcrits:BAAALgAECgYJDAAAAA==.',
['Mà']='Màevë:BAAALgAECgEJAgAAAA==.',
Na='Nairdax:BAAALgADCgEJAQAAAA==.Nalmec:BAABLgAECn8hAAILAAYJPQjOTgDjAAALAAYJPQjOTgDjAAAAAA==.Nama:BAAALgADCgYJCwAAAA==.Naysayre:BAABLgAECn8hAAIPAAYJigfRngC5AAAPAAYJigfRngC5AAAAAA==.',
Ne='Nebody:BAAALgAECgUJBgAAAA==.Necriss:BAABLgAECn8sAAIVAAkJUxA+SwDGAQAVAAkJUxA+SwDGAQAAAA==.',
Ni='Nightkilla:BAAALgAECgEJAwAAAA==.Nike:BAAALgAECggJDwAAAA==.Nilowin:BAABLgAECn8vAAIBAAgJ9w8kGwCVAQABAAgJ9w8kGwCVAQAAAA==.',
No='Nokaj:BAAALgAECgEJAgAAAA==.Noshards:BAAALgAECgcJDQAAAA==.Notericdh:BAAALgAECgYJEwAAAA==.',
Og='Oghom:BAAALgADCgcJCgAAAA==.',
Oh='Ohnoitzgumby:BAABLgAECn8cAAMUAAcJuhaCWQCWAQAUAAcJrBaCWQCWAQAkAAMJoBJPFABOAAAAAA==.',
Om='Omiko:BAAALgAECgIJAgAAAA==.',
Op='Opeep:BAAALgADCgcJGQAAAA==.',
Or='Orah:BAAALgADCgEJAQAAAA==.',
Os='Osos:BAAALgAECgYJEAAAAA==.',
Pa='Paladimdab:BAAALgAECgQJBQAAAA==.Papachance:BAAALgAECgYJDgAAAA==.Papafrank:BAAALgAECgQJBQAAAA==.Paradis:BAAALgADCgcJBwAAAA==.Pazuzu:BAAALgADCgYJBgAAAA==.',
Pe='Peepo:BAAALgAECgEJAQAAAA==.',
Pi='Pinga:BAABLgAECn8cAAQgAAkJnx95BAArAwAgAAkJMx95BAArAwATAAIJ+hxwUwBfAAASAAEJmQ4lbgA0AAABLgAECgkJNQAlAD0iAA==.Pinkberry:BAAALgAECgQJBAAAAA==.Pintcube:BAAALgADCgYJCAAAAA==.',
Pl='Pljeskavica:BAAALgAECgYJBwAAAA==.Plox:BAAALgAECgMJAwAAAA==.',
Po='Port:BAABLgAECn8wAAIGAAkJ8R4BCgD9AgAGAAkJ8R4BCgD9AgAAAA==.Potroastjr:BAAALgADCgEJAgABLgAECgEJAQARAAAAAA==.',
Pr='Primordus:BAAALgADCgUJBQAAAA==.Profiler:BAAALgAECgcJCAAAAA==.Protocol:BAAALgAECgMJAwAAAA==.Prïestess:BAAALgAECgcJCQAAAA==.',
Ps='Pseriph:BAABLgAECn8ZAAIDAAcJ3BZrCwAKAgADAAcJ3BZrCwAKAgAAAA==.',
Ra='Radamantis:BAAALgAECgMJAwAAAA==.Raenon:BAAALgADCgkJEAAAAA==.Raggnar:BAACLgAFFH8NAAIJAAMJWSJ/FwAoAQAJAAMJWSJ/FwAoAQAuAAQKfzEAAgkACQmVIWIFAO0CAAkACQmVIWIFAO0CAAAA.Ragingwaters:BAAALgADCgYJCAABLgAECgIJBgARAAAAAA==.Ranvir:BAAALgAECgEJAQAAAA==.Raun:BAABLgAECn87AAMVAAkJBiPRBQAuAwAVAAkJBiPRBQAuAwAOAAMJJBEvcgCzAAAAAA==.',
Re='Regnarr:BAAALgADCgEJAQAAAA==.Rehgar:BAAALgAFFAEJAQAAAA==.Relaire:BAABLgAECn8vAAIaAAkJ8RI9KAATAgAaAAkJ8RI9KAATAgAAAA==.Remenissions:BAAALgAECgEJAQAAAA==.Resonate:BAAALgAFFAIJAwAAAA==.',
Ri='Rikane:BAAALgADCgcJDAABLgADCgcJEgARAAAAAA==.Rikenji:BAAALgAECgEJAQAAAA==.Riku:BAABLgAECn82AAIjAAkJvSC0AQAEAwAjAAkJvSC0AQAEAwAAAA==.',
Ro='Rock:BAAALgAECgcJDgAAAA==.Rocks:BAAALgAECgEJAQAAAA==.Rockyrag:BAAALgADCgEJAQAAAA==.Roguey:BAABLgAECn8sAAMmAAkJuQ8mCgB0AQAmAAcJlBEmCgB0AQABAAcJ/wxyIQBcAQAAAA==.Roots:BAAALgAECgEJBwAAAA==.',
Ru='Rulethrefour:BAAALgAECgQJBwAAAA==.',
Ry='Ryveri:BAABLgAECn8lAAILAAkJDxmFFgAWAgALAAkJDxmFFgAWAgAAAA==.',
Sa='Sablehide:BAABLgAECn8tAAIHAAgJdhcXHADVAQAHAAgJdhcXHADVAQAAAA==.Sanaron:BAAALgADCgIJAgAAAA==.Sanaty:BAAALgAFFAEJAgAAAA==.Saryn:BAAALgAECgYJDwAAAA==.Satanz:BAAALgADCgIJAgAAAA==.Sathanus:BAAALgAECgQJCwAAAA==.',
Se='Searate:BAAALgADCgcJEgAAAA==.Seaside:BAACLgAFFH8PAAIUAAMJ/iWdPgBHAQAUAAMJ/iWdPgBHAQAuAAQKfxgAAxQABwk9JeE3AP0BABQABwk9JeE3AP0BAB0AAgmEC+8/AE4AAAAA.Secrett:BAABLgAECn8YAAMBAAcJ9xN0JABDAQABAAcJ9xN0JABDAQAmAAEJew4dIwAwAAAAAA==.Sephyxia:BAABLgAECn8vAAIdAAkJdBp9CgA7AgAdAAkJdBp9CgA7AgAAAA==.Serryon:BAAALgADCgIJAgAAAA==.',
Sf='Sfora:BAAALgAECgMJAwAAAA==.',
Sh='Shadowwzz:BAAALgADCgEJAQAAAA==.Shoçknezz:BAAALgAECgMJBQAAAA==.',
Si='Silverwolf:BAABLgAECn88AAIfAAkJUyCWAgDNAgAfAAkJUyCWAgDNAgAAAA==.Simplyunlock:BAACLgAFFH8MAAICAAQJawq8SAASAQACAAQJawq8SAASAQAuAAQKfyYAAwIACAl1FWw5ANsBAAIACAl1FWw5ANsBAAMAAgnnBZVmAEMAAAAA.Simplyvoided:BAAALgAECgQJBgAAAA==.Sinverguenza:BAAALgAECgMJBQAAAA==.Sizzlechop:BAABLgAECn8oAAIUAAgJ7QrVbwBfAQAUAAgJ7QrVbwBfAQAAAA==.',
Sk='Skizzak:BAAALgADCgQJBAABLgAFFAYJGAAUAMgjAA==.Skweeks:BAAALgAECgMJBAAAAA==.',
Sm='Smelvin:BAABLgAECn8bAAIJAAkJ8xlsFgBmAgAJAAkJ8xlsFgBmAgABLgAECgQJCAARAAAAAA==.Smoko:BAAALgAECgIJAgABLgAECgUJBQARAAAAAA==.',
Sn='Snailslolol:BAAALgAECgEJAwAAAA==.Snakey:BAECLgAFFH8UAAMHAAQJGglBKgDyAAAHAAQJGglBKgDyAAAnAAEJ1wJfDABCAAAuAAQKfywAAwcACAmLGD4aAPkBAAcACAmLGD4aAPkBACcABgl5BHkmAO8AAAAA.',
So='Solara:BAABLgAECn8hAAQSAAkJMRjsEQAgAgASAAkJMRjsEQAgAgATAAEJQAIShwApAAAgAAEJXgKYXgAkAAAAAA==.Soleill:BAAALgAECgcJBwAAAA==.Sondan:BAAALgADCgMJAwAAAA==.Songs:BAAALgAECgEJAQABLgAECgYJGAANAP8gAA==.',
Sp='Spellpowa:BAAALgAECgYJDgAAAA==.',
Sq='Squirtin:BAAALgAECgIJAgAAAA==.',
Ss='Ssminion:BAAALgAECgMJBgAAAA==.',
St='Stalath:BAAALgADCgcJBwAAAA==.Stormwing:BAABLgAECn8eAAIJAAgJiBlVHgDDAQAJAAgJiBlVHgDDAQAAAA==.Strecagosa:BAAALgAECgYJDQAAAA==.',
Sv='Svenn:BAAALgAECgYJBgAAAA==.',
Sy='Sybelissa:BAAALgAECgMJAwABLgAECgcJCgARAAAAAA==.Synni:BAAALgADCgEJAQAAAA==.',
['Sÿ']='Sÿnÿster:BAAALgAECgEJAQABLgAFFAQJEAAaAI4cAA==.',
Ta='Talron:BAAALgAECgQJBwAAAA==.Tastytay:BAAALgADCgMJAwAAAA==.Tatertots:BAABLgAECn8yAAMkAAkJFCCGAQDoAgAkAAkJFCCGAQDoAgAUAAMJ8hON7ACmAAAAAA==.',
Te='Tea:BAABLgAECn8xAAIaAAkJgCXbAQBlAwAaAAkJgCXbAQBlAwAAAA==.Teal:BAAALgAECgMJAwAAAA==.Templyn:BAAALgAECggJEwAAAA==.Templÿn:BAAALgADCgIJAgABLgAECggJEwARAAAAAA==.Tenebrarum:BAABLgAECn8bAAIaAAgJGQ0xVwBjAQAaAAgJGQ0xVwBjAQAAAA==.Testorooni:BAABLgAECn8ZAAIaAAcJkBgpMwDjAQAaAAcJkBgpMwDjAQAAAA==.',
Th='Thakodi:BAAALgAECgQJBAAAAA==.Thannos:BAAALgADCgEJAQAAAA==.Tharvan:BAAALgADCgcJDAAAAA==.Thavok:BAAALgAECgEJAQAAAA==.Thedeadman:BAABLgAECn8kAAIUAAkJEyJcGgCGAgAUAAkJEyJcGgCGAgAAAA==.Thepriestg:BAAALgAECgEJAQAAAA==.Thiccksilver:BAAALgADCgcJBwABLgAECgkJKAACAC8eAA==.Thompson:BAABLgAECn8VAAIUAAcJuxT7fABDAQAUAAcJuxT7fABDAQAAAA==.Thunderflaps:BAAALgAECgUJCQAAAA==.Thyrus:BAABLgAECn81AAMlAAkJPSLSAgAQAwAlAAkJPSLSAgAQAwAnAAEJqgL7RAAjAAAAAA==.',
Ti='Tirna:BAABLgAECn84AAIhAAkJng7sAgDWAQAhAAkJng7sAgDWAQAAAA==.',
To='Toebot:BAAALgAECgEJAQAAAA==.Toggle:BAAALgAECgEJAQAAAA==.Tomsellock:BAABLgAECn8WAAMEAAcJjhBuBwDcAQAEAAcJjhBuBwDcAQACAAEJugM+LAEmAAAAAA==.Tonari:BAAALgAECgEJAQABLgAECgYJEAARAAAAAA==.Torvi:BAAALgADCgMJAwAAAA==.',
Tr='Transmørtuus:BAAALgAECgQJCQAAAA==.Treehug:BAAALgAECggJEwAAAA==.Triple:BAAALgAECgQJBwABLgAECgYJEAARAAAAAA==.Trolleonne:BAAALgAECgIJAgAAAA==.',
Tu='Tullen:BAEBLgAECn81AAITAAkJjRGfGwDEAQATAAkJjRGfGwDEAQAAAA==.Turanos:BAAALgAECgQJCwAAAA==.',
Tw='Tweyen:BAAALgAECgEJAQAAAA==.Twistedbael:BAAALgAECgUJBQAAAA==.',
Ty='Tyindaris:BAAALgAECgQJCgAAAA==.Tyloregeth:BAABLgAECn8mAAISAAgJphSOIQCSAQASAAgJphSOIQCSAQAAAA==.',
['Tè']='Tèmplyn:BAAALgADCgEJAQABLgAECggJEwARAAAAAA==.',
['Té']='Témplýn:BAAALgADCgEJAQABLgAECggJEwARAAAAAA==.',
['Të']='Tëmplýn:BAAALgAECgEJAQABLgAECggJEwARAAAAAA==.',
Ul='Ulfrunn:BAAALgADCgYJBgAAAA==.Ultrachad:BAACLgAFFH8aAAIUAAYJXxf8IgCIAQAUAAYJXxf8IgCIAQAuAAQKfx4AAhQACAlNIwUUAAMDABQACAlNIwUUAAMDAAAA.',
Um='Umami:BAABLgAECn8gAAILAAYJ+RhzSgB7AQALAAYJ+RhzSgB7AQAAAA==.',
Un='Unggoy:BAACLgAFFH8fAAMbAAgJHR38AgAkAgAbAAgJ9Bv8AgAkAgAaAAIJsRkjUgCwAAAuAAQKfygAAxsACQkhJrsBAKYDABsACQkhJrsBAKYDABoAAQnFJbfJAG4AAAAA.Unholywaters:BAAALgAECgIJBgAAAA==.',
Ur='Urianna:BAAALgAECgIJBgAAAA==.',
Va='Vaelthirion:BAABLgAECn8nAAIIAAgJYxY2QgD5AQAIAAgJYxY2QgD5AQAAAA==.Vahidamus:BAAALgAECgcJCgAAAA==.Valkaryon:BAAALgAECgcJCgABLgAFFAIJAwARAAAAAA==.Valmirax:BAAALgADCggJEgAAAA==.Valton:BAABLgAECn9BAAIVAAcJuA9OgQBLAQAVAAcJuA9OgQBLAQAAAA==.',
Ve='Vegetation:BAAALgAECgQJBwAAAA==.Velenestus:BAAALgAECgMJBgAAAA==.Verses:BAAALgADCgEJAQAAAA==.',
Vi='Vizsla:BAAALgAECgEJAQAAAA==.',
Wa='Wackaman:BAABLgAECn8nAAIMAAkJvByQBgB/AgAMAAkJvByQBgB/AgAAAA==.Warpig:BAAALgAECgYJEQAAAA==.Wasps:BAAALgAECgYJEQAAAA==.',
We='Wegmaniac:BAAALgADCgYJCAAAAA==.Welastrexa:BAAALgADCgUJBQABLgAECgIJBgARAAAAAA==.',
Wi='Wickedclöwn:BAAALgADCgMJAwAAAA==.Winchester:BAAALgADCgIJAgAAAA==.Windhorn:BAAALgAECgMJBAAAAA==.Winds:BAABLgAECn8YAAINAAYJ/yBoFwAqAgANAAYJ/yBoFwAqAgAAAA==.',
Wn='Wntrizcoming:BAAALgADCgMJBQAAAA==.',
Wo='Wolfquota:BAACLgAFFH8QAAIJAAQJJx69EgBIAQAJAAQJJx69EgBIAQAuAAQKfx8AAwkACAlGIkkJAP4CAAkACAlGIkkJAP4CAB8ABAntE08eAOkAAAAA.Wolftime:BAAALgADCgUJBQAAAA==.Wombaa:BAACLgAFFH8SAAIUAAQJoiVGFwC1AQAUAAQJoiVGFwC1AQAuAAQKfxwAAhQACAleJGEKAEgDABQACAleJGEKAEgDAAAA.',
Wr='Wrathbolt:BAAALgAECgEJAQABLgAFFAQJBQANAHoZAA==.Wrathmo:BAACLgAFFH8FAAINAAQJehmWCwBAAQANAAQJehmWCwBAAQAuAAQKfyUAAw0ACAljHDAQACICAA0ABwlpHjAQACICACgABwkdCng4AP0AAAAA.Wrathp:BAAALgAECgcJCQABLgAFFAQJBQANAHoZAA==.Wrolie:BAAALgADCgMJAwAAAA==.',
['Wê']='Wêêdyys:BAAALgADCgMJBAAAAA==.',
Xy='Xyr:BAAALgAECgEJAQABLgAECggJJwASANsQAA==.',
Ya='Yamiamigo:BAAALgAECgEJAQAAAA==.',
Yo='Yougotsniped:BAAALgADCgEJAQAAAA==.',
Za='Zandalia:BAAALgAECgMJAwAAAA==.Zark:BAEALgAECgEJAQABLgAECgkJGQAXAHsWAA==.',
Ze='Zemphoths:BAAALgAECgcJCgAAAA==.',
Zo='Zoa:BAAALgADCgYJBgAAAA==.Zolton:BAAALgADCgMJAwAAAA==.Zornak:BAAALgAECgUJDgAAAA==.',
['Åe']='Åequitas:BAAALgAECgYJCQAAAA==.',
['ßa']='ßahamut:BAAALgAECgYJCQAAAA==.',
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
