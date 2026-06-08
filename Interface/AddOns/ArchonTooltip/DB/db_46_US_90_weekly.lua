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

local lookup = {'Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Druid-Restoration','Evoker-Augmentation','Mage-Frost','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Warrior-Protection','Monk-Windwalker','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Unknown-Unknown','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','DemonHunter-Havoc','Shaman-Restoration','Rogue-Outlaw','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Monk-Mistweaver','Druid-Guardian','Shaman-Enhancement','Priest-Discipline','Mage-Fire','Paladin-Retribution','Mage-Arcane','Druid-Feral','DeathKnight-Frost','Evoker-Preservation','Rogue-Assassination','Evoker-Devastation','Monk-Brewmaster',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aamon:BAAALgAECgQJCgAAAA==.',
Ab='Abacus:BAABLgAECn8jAAIBAAkJjyLNCgBrAgABAAkJjyLNCgBrAgAAAA==.',
Ac='Acin:BAAALgADCgQJBAAAAA==.',
Ad='Adam:BAACLgAFFH8ZAAQCAAcJWxuRNQBaAQACAAUJLhyRNQBaAQADAAMJlBFcDQCiAAAEAAEJECbVEABxAAAuAAQKfy4ABAIACQk2JF4WAM4CAAIACQmcI14WAM4CAAMABQljJKcNAOsBAAQAAQkaI7grAGAAAAAA.Adedruid:BAABLgAECn8gAAMFAAYJdR9cKwCnAQAFAAYJdR9cKwCnAQAGAAYJ3xoBSgB6AQAAAA==.Adevoker:BAAALgAECgQJBAAAAA==.Adragon:BAABLgAECn8rAAIHAAkJ5RqSDgBzAgAHAAkJ5RqSDgBzAgAAAA==.',
Ae='Aengyl:BAAALgAECgQJBAAAAA==.Aeonne:BAABLgAECn8WAAIIAAgJyxJIjABZAQAIAAgJyxJIjABZAQAAAA==.',
Ak='Akshul:BAABLgAECn8UAAIJAAYJ5Q1HRgAvAQAJAAYJ5Q1HRgAvAQAAAA==.Akurama:BAAALgAECgcJCgAAAA==.',
Al='Aldrea:BAAALgAECggJEQAAAA==.Allsmiles:BAABLgAECn8VAAQKAAkJZh7tCAAhAgAKAAgJhRrtCAAhAgALAAUJChm2TQBwAQAMAAQJkh4oKgDvAAAAAA==.Allura:BAAALgAECgQJCQAAAA==.Alorian:BAAALgAECgIJAgAAAA==.Alttharius:BAAALgAECgMJAwABLgAECgkJGQANALQgAA==.Alyysha:BAABLgAECn8bAAIOAAcJlwkCRgBgAQAOAAcJlwkCRgBgAQAAAA==.',
Am='Amoon:BAABLgAECn81AAMPAAkJgBlmJgAoAgAPAAkJ0RdmJgAoAgAQAAYJBRXMEQAjAQAAAA==.',
An='Andoriel:BAAALgADCgcJBwABLgAFFAIJAwARAAAAAA==.Angelrain:BAABLgAECn8sAAMSAAgJWByRDgCaAgASAAgJWByRDgCaAgATAAcJ8QcaOQAHAQAAAA==.Aniata:BAAALgAECgEJAQAAAA==.',
Ar='Archymedes:BAABLgAECn8sAAILAAcJJxGAOgBUAQALAAcJJxGAOgBUAQAAAA==.Arckady:BAAALgAECgQJDwAAAA==.Areko:BAAALgAECgIJBQAAAA==.Aresh:BAAALgAECgEJAgAAAA==.Array:BAAALgAECgYJBwABLgAECgkJMAAGAPEeAA==.Artharius:BAABLgAECn8ZAAINAAkJtCA/EQBvAgANAAkJtCA/EQBvAgAAAA==.',
As='Asanad:BAAALgADCgUJBQABLgAECgUJCAARAAAAAA==.',
Au='Auburnbeard:BAAALgADCgYJBgAAAA==.Aumed:BAAALgADCgEJAQAAAA==.Aurelionburn:BAAALgAECgEJAQAAAA==.',
Av='Averle:BAABLgAECn9eAAIDAAcJZwpLFQDxAAADAAcJZwpLFQDxAAAAAA==.',
Az='Azrran:BAAALgADCgEJAQAAAA==.Aztharot:BAAALgAECgIJAgAAAA==.',
Ba='Badchoices:BAAALgAECgQJBAAAAA==.Badkittie:BAAALgAECgQJBwAAAA==.Balding:BAAALgAECgQJBgAAAA==.Baphico:BAAALgADCgUJCQAAAA==.',
Be='Bearhug:BAAALgAECgEJAQAAAA==.Behemoth:BAAALgAECgQJBAAAAA==.Belinda:BAAALgAECgEJAQABLgAFFAYJGAAUAMgjAA==.Bettyßaraxus:BAAALgAECgMJAwAAAA==.Bewater:BAAALgADCgcJBwAAAA==.',
Bi='Bigcarol:BAAALgAECgEJAQAAAA==.Bigunsforu:BAAALgAECgUJBAAAAA==.',
Bl='Bladesmcgee:BAAALgAECggJCQABLgAECgQJCAARAAAAAA==.Blasphem:BAAALgADCgQJBAAAAA==.',
Bo='Bobadelphia:BAAALgADCgYJBgABLgAECgYJEQARAAAAAA==.Bofahdeez:BAABLgAECn8aAAMTAAgJfA6+PABHAQATAAcJWA6+PABHAQASAAcJLQzvOAAnAQAAAA==.Bogs:BAACLgAFFH8WAAIIAAUJmx1iQQBbAQAIAAUJmx1iQQBbAQAuAAQKfyMAAggACAnrIb4jAOQCAAgACAnrIb4jAOQCAAAA.Bonedaddy:BAAALgAECgYJBgAAAA==.',
Br='Brewswayne:BAAALgADCgQJBAABLgAFFAIJAwARAAAAAA==.Brolic:BAABLgAECn8xAAMVAAgJkCA/CQCJAgAVAAgJkCA/CQCJAgAPAAEJJgnVGQEkAAAAAA==.',
['Bä']='Bämboo:BAAALgAFFAEJAgABLgAFFAQJCwAWAOoQAA==.',
Ca='Cail:BAEBLgAECn8ZAAIWAAkJexYZHgBQAgAWAAkJexYZHgBQAgAAAA==.Calamìty:BAAALgADCgcJDgABLgAFFAMJBwAGABwKAA==.Calisa:BAABLgAECn87AAIXAAkJ6h9QAQDmAgAXAAkJ6h9QAQDmAgAAAA==.Cardio:BAAALgAECgUJBgAAAA==.Carnifexx:BAAALgAFFAIJAgABLgAFFAgJHgAPAGEVAA==.Cassey:BAAALgAECgEJAQAAAA==.',
Ce='Celesteus:BAAALgADCgkJFAAAAA==.',
Ch='Charis:BAAALgAECgYJCwAAAA==.Chigutotems:BAAALgAECgYJCwABLgAECgkJGwAPAGwWAA==.Chimmoku:BAAALgAFFAQJBAABLgAFFAcJHQABAD4ZAA==.Choi:BAAALgAECgUJDwAAAA==.Chooq:BAAALgADCgIJAgAAAA==.Chozen:BAAALgAECgUJEAAAAA==.Chumlee:BAAALgAECgYJCwAAAA==.',
Ci='Cienna:BAAALgAECgYJDgAAAA==.Cigz:BAAALgADCgEJAQAAAA==.Cinch:BAAALgAECgIJAgAAAA==.',
Co='Colinferral:BAAALgAECgYJCAAAAA==.Coulee:BAAALgAECgQJCAABLgAECggJKQAVABshAA==.Cowladin:BAAALgADCgUJBQAAAA==.',
Cr='Crakzkull:BAAALgAECgUJCwAAAA==.Croar:BAAALgAECgMJBAAAAA==.Cronicpain:BAAALgADCgkJCQAAAA==.',
Cu='Cuernuda:BAAALgAECgEJAQAAAA==.',
['Cä']='Cäntstandya:BAACLgAFFH8RAAMYAAQJVRhMGQDzAAAYAAMJnxdMGQDzAAAZAAMJmRguWQDfAAAuAAQKfyMAAxkACAkvG1cSAKUCABkACAliGVcSAKUCABgABwkaHh0SABUCAAAA.',
Da='Daiko:BAAALgAECgYJCQAAAA==.Daks:BAAALgAFFAIJAwAAAA==.Dargo:BAAALgAECgYJEwAAAA==.Darklucrezia:BAACLgAFFH8SAAMZAAUJjhy0JwBWAQAZAAUJjhy0JwBWAQAaAAIJNgJQLgBMAAAuAAQKfy4AAxkACAn3H+UaAHgCABkACAltH+UaAHgCABoACAkOEeQlAPoBAAAA.Dazzlefraz:BAAALgAECgQJBAAAAA==.',
De='Demonklunter:BAAALgADCgYJEAAAAA==.Destructoid:BAAALgAECgEJAQAAAA==.',
Di='Dicey:BAAALgADCgMJAwABLgAECgQJBwARAAAAAA==.',
Do='Dochunter:BAAALgAECgUJBQAAAA==.',
Dr='Dracarius:BAAALgAECgQJEAAAAA==.Drega:BAAALgAECgYJBwAAAA==.Droods:BAAALgAECgQJBQAAAA==.Drtypinkcake:BAABLgAECn8gAAIVAAcJ1wqFLQADAQAVAAcJ1wqFLQADAQAAAA==.Druskgar:BAABLgAECn8mAAMUAAkJlh4QQAD7AQAUAAgJzyEQQAD7AQAbAAcJ4A8JIQBBAQAAAA==.Dryad:BAAALgAECgQJDwAAAA==.',
Du='Duckster:BAAALgADCgYJBwAAAA==.Dunce:BAACLgAFFH8GAAIcAAIJdR83NQCyAAAcAAIJdR83NQCyAAAuAAQKfycAAhwACAnyIHMMAMICABwACAnyIHMMAMICAAAA.Durkk:BAABLgAECn87AAIbAAkJ9yHgBADbAgAbAAkJ9yHgBADbAgAAAA==.Durza:BAAALgAECgcJEAAAAA==.',
['Dä']='Dännydevito:BAAALgADCgQJBAAAAA==.',
Ed='Eduard:BAAALgAECgYJCQAAAA==.',
Ek='Eklipse:BAAALgAECgMJAwAAAA==.',
El='Elanthae:BAAALgAECgQJEQAAAA==.Elysia:BAAALgAECgEJAgAAAA==.',
Er='Erzulie:BAAALgAECgUJBAAAAA==.',
Es='Estara:BAABLgAECn81AAIdAAkJqwtiIwAhAQAdAAkJqwtiIwAhAQAAAA==.',
Et='Etali:BAABLgAECn8yAAILAAkJQByxDwB1AgALAAkJQByxDwB1AgAAAA==.',
Ex='Expired:BAAALgAECgEJAQAAAA==.',
Fa='Faite:BAAALgADCgUJBQAAAA==.Falorin:BAABLgAECn8gAAIIAAgJChYFXwC8AQAIAAgJChYFXwC8AQAAAA==.Fanis:BAABLgAECn8mAAIaAAkJzRXxCADeAQAaAAkJzRXxCADeAQAAAA==.Fatherwhig:BAAALgAECgIJAwAAAA==.',
Fe='Fenrin:BAAALgAECgQJBAAAAA==.',
Fi='Fidis:BAAALgADCgkJCwAAAA==.Fistsofdeath:BAAALgADCggJCgAAAA==.Fistychub:BAAALgADCgEJAQAAAA==.',
Fl='Flashbang:BAAALgADCgEJAQAAAA==.Flashis:BAAALgAECggJEwAAAA==.Florago:BAAALgAECgQJEAAAAA==.',
Fr='Frakir:BAABLgAECn87AAQWAAkJ5xmaFwCBAgAWAAkJ5xmaFwCBAgAeAAMJRwojKgCMAAAJAAEJkAYjkwAjAAAAAA==.Fritzz:BAAALgAECgcJEgABLgAECgkJEwARAAAAAA==.Frog:BAAALgAECgIJBQAAAA==.',
Fu='Furrypaw:BAABLgAECn8uAAIcAAkJZiWOAQC9AwAcAAkJZiWOAQC9AwAAAA==.Fuzzyy:BAAALgAECgEJAQAAAA==.',
Fw='Fwapp:BAACLgAFFH8ZAAIOAAcJXh3sCQADAgAOAAcJXh3sCQADAgAuAAQKfxcAAg4ACAlrIcgLAL8CAA4ACAlrIcgLAL8CAAAA.',
Ga='Galvanize:BAAALgAECgEJBAAAAA==.Galynisse:BAABLgAECn8xAAMfAAgJAhhZEwA5AgAfAAgJAhhZEwA5AgATAAMJ7A4eZQCZAAAAAA==.',
Ge='Gedorah:BAABLgAECn8fAAIgAAcJOBxDAwDeAQAgAAcJOBxDAwDeAQABLgAFFAQJEwAJAEAhAA==.',
Gh='Ghaspy:BAAALgAECgUJCgAAAA==.Ghoste:BAAALgADCgMJAwAAAA==.Ghrex:BAAALgAECgEJAQAAAA==.',
Gi='Gijaick:BAABLgAECn8vAAMCAAgJWBiGQgDOAQACAAgJWBiGQgDOAQADAAEJHg4AdAAxAAAAAA==.',
Gl='Glaivethrow:BAABLgAECn8bAAIPAAkJbBZbPADKAQAPAAkJbBZbPADKAQAAAA==.Glizzo:BAAALgAECgYJDAAAAA==.Gloam:BAAALgADCgUJBQAAAA==.Glueballs:BAAALgAECgEJAQABLgAECgcJCwARAAAAAA==.',
Go='Gochujjang:BAAALgAECgYJDQAAAA==.Goldhawk:BAAALgAECgMJAwAAAA==.Gotchá:BAAALgAECgEJBAAAAA==.Gotwiped:BAABLgAECn8WAAIUAAgJfRrlNwAYAgAUAAgJfRrlNwAYAgAAAA==.',
Gr='Grimgor:BAAALgAECgcJAQAAAA==.',
Ha='Hahaheals:BAAALgAECgMJBAAAAA==.Hakhar:BAAALgADCgMJAwAAAA==.Hanth:BAAALgADCgkJDAABLgAECgMJBAARAAAAAA==.Hatter:BAABLgAECn8pAAQPAAgJ4xW0PwC+AQAPAAgJ4xW0PwC+AQAVAAMJ+AsRWACGAAAQAAEJNRMmKwA0AAAAAA==.',
He='Healsus:BAAALgAECgMJAwAAAA==.Heimlish:BAAALgAECgEJAQAAAA==.Hellraiser:BAABLgAECn8nAAMUAAcJfhmAYgCbAQAUAAcJVBiAYgCbAQAbAAcJaRNYHgBYAQAAAA==.Hermione:BAAALgAECgYJDQAAAA==.Hexecution:BAAALgADCgIJAgAAAA==.',
Hi='Hiddendragon:BAAALgAECgEJAQAAAA==.',
Ho='Holydarkness:BAAALgAECgYJCgAAAA==.Holyhello:BAAALgAECgEJAQAAAA==.Holykilla:BAAALgAECgEJBQAAAA==.Holykiller:BAAALgAECgcJCgAAAA==.Hoofjob:BAAALgADCggJDgABLgAFFAQJDgAfAOIgAA==.Hoplite:BAAALgADCgcJDgABLgAECggJEgARAAAAAA==.Hotot:BAAALgADCgMJAwAAAA==.Howlly:BAAALgAECggJEAAAAA==.',
Hu='Huffpuffle:BAAALgAECgUJCgAAAA==.',
['Hô']='Hôwl:BAABLgAECn8YAAIGAAcJwhCSRQBvAQAGAAcJwhCSRQBvAQAAAA==.',
Ic='Icdeathg:BAACLgAFFH8JAAIPAAMJ/QtfYgC4AAAPAAMJ/QtfYgC4AAAuAAQKfzEAAg8ACAksH8wYAHcCAA8ACAksH8wYAHcCAAAA.',
Ik='Iktaar:BAAALgAECgYJEQAAAA==.',
Il='Illidami:BAAALgADCgkJCwAAAA==.Illidamngirl:BAAALgADCgYJBgABLgAECgkJJwAMALwcAA==.',
Im='Imperius:BAACLgAFFH8VAAIhAAUJHBY0QgAZAQAhAAUJHBY0QgAZAQAuAAQKfyQAAiEACQmMJB0OAB0DACEACQmMJB0OAB0DAAAA.',
In='Ines:BAACLgAFFH8KAAIUAAMJWSEWdwAGAQAUAAMJWSEWdwAGAQAuAAQKfzoAAhQACQlrJB0KABcDABQACQlrJB0KABcDAAAA.Insomiax:BAAALgAECggJDwAAAA==.Insta:BAABLgAECn8rAAILAAcJzx3cIwA3AgALAAcJzx3cIwA3AgAAAA==.Inter:BAABLgAECn8vAAIbAAkJ9yE6BAALAwAbAAkJ9yE6BAALAwAAAA==.',
Ir='Iridi:BAAALgADCgEJAQAAAA==.Iritall:BAAALgADCgcJCwABLgAECgEJAgARAAAAAA==.',
It='Ithamburglar:BAAALgAECgQJBwAAAA==.',
Iz='Izureka:BAAALgADCgYJBgAAAA==.',
Ja='Jackidaytona:BAAALgAECgcJBwAAAA==.Jakaru:BAABLgAECn8bAAIcAAkJWRoJEQCHAgAcAAkJWRoJEQCHAgAAAA==.Jankadish:BAAALgAECgcJEwAAAA==.Jarre:BAACLgAFFH8GAAIGAAQJrggsDgAFAQAGAAQJrggsDgAFAQAuAAQKfygAAgYACAmzICIKAPMCAAYACAmzICIKAPMCAAAA.Jaspirian:BAAALgADCggJFAAAAA==.Jazzil:BAAALgADCgcJCgAAAA==.',
Jb='Jbaconcheese:BAAALgAECgEJAQAAAA==.',
Je='Jehm:BAAALgAECgEJAQABLgAECgMJAwARAAAAAA==.Jehmothy:BAAALgAECgUJBQAAAA==.Jerome:BAAALgAECgEJAQAAAA==.',
Jo='Jotabop:BAAALgAECgQJBgAAAA==.',
Ju='Judgequota:BAAALgAFFAMJAwABLgAFFAQJEAAJACceAA==.Juicy:BAABLgAECn8kAAIYAAkJQRflDABTAgAYAAkJQRflDABTAgAAAA==.Juupiter:BAAALgAECgEJAQABLgAECggJIAAIAAoWAA==.',
Ka='Kabu:BAAALgAECgcJBwAAAA==.Kalia:BAABLgAECn8vAAMIAAkJ/xgVPgB/AgAIAAkJ/xgVPgB/AgAiAAMJUg/nDACYAAAAAA==.Kalitra:BAAALgADCgMJAwABLgAECgkJLwAIAP8YAA==.Katoumae:BAACLgAFFH8SAAIjAAUJNB2WBQBIAQAjAAUJNB2WBQBIAQAuAAQKfycAAiMACQkdIkgCAP0CACMACQkdIkgCAP0CAAAA.Katoumey:BAAALgAECgYJCgABLgAFFAUJEgAjADQdAA==.',
Ke='Keratin:BAABLgAECn8uAAIkAAkJvSKRAwCaAgAkAAkJvSKRAwCaAgAAAA==.',
Kh='Khumi:BAABLgAECn8XAAIaAAgJYSCmEgCiAgAaAAgJYSCmEgCiAgABLgAFFAkJKwAhAD4mAA==.',
Ki='Kinan:BAABLgAECn82AAMZAAkJHSaWAQB5AwAZAAkJHSaWAQB5AwAaAAcJOx6kFwBxAgAAAA==.Kita:BAAALgAECggJEgABLgAECgkJAgARAAAAAA==.',
Kk='Kkaarrkk:BAAALgAECgUJCAAAAA==.',
Kr='Krindon:BAABLgAECn8nAAIVAAgJdBEvHACLAQAVAAgJdBEvHACLAQAAAA==.',
Ku='Kureiji:BAAALgADCgEJAQAAAA==.',
Ky='Kythin:BAAALgAECgEJAQABLgAECgkJLwAIAP8YAA==.',
La='Lacutis:BAAALgAECgEJAwAAAA==.Lanssolo:BAAALgAECgMJAwAAAA==.Laww:BAAALgADCgcJCgAAAA==.',
Le='Lecroix:BAAALgADCgUJBQAAAA==.Leonus:BAAALgAECgMJAwABLgAECgIJAgARAAAAAA==.Lessana:BAAALgAECgQJDgAAAA==.Lethalforce:BAAALgADCgMJAwAAAA==.',
Li='Liandri:BAAALgADCgEJAgAAAA==.Lightchild:BAAALgADCggJCAAAAA==.Lightprivlge:BAAALgAECgcJDQAAAA==.Lillith:BAAALgAECgMJAwAAAA==.Livewire:BAAALgAECgQJEAAAAA==.',
Lo='Lokohmojo:BAAALgAECgMJBAAAAA==.Lomponic:BAEBLgAECn8zAAISAAkJ4RuJDgBoAgASAAkJ4RuJDgBoAgAAAA==.Loomadin:BAAALgADCgYJCQAAAA==.Loranis:BAAALgAECgQJBQAAAA==.',
Lu='Lunethra:BAABLgAECn8rAAIZAAkJwhGAKwAGAgAZAAkJwhGAKwAGAgAAAA==.',
Ma='Mageaux:BAAALgAECgEJAQAAAA==.Magerag:BAACLgAFFH8JAAIIAAMJGBtxcADxAAAIAAMJGBtxcADxAAAuAAQKfy8AAwgACQlNIg0fAJ0CAAgACQlNIg0fAJ0CACIAAglAGkQVAHMAAAAA.Manamontana:BAACLgAFFH8ZAAMUAAcJtw8JKACnAQAUAAYJtw8JKACnAQAbAAEJAABASAAAAAAuAAQKfxoAAhQACAn4H4AoAJgCABQACAn4H4AoAJgCAAAA.Marumo:BAAALgAECgMJBgAAAA==.',
Mc='Mcribz:BAACLgAFFH8YAAIUAAYJyCMwHwDSAQAUAAYJyCMwHwDSAQAuAAQKfyIAAhQACAl8IzIZAOUCABQACAl8IzIZAOUCAAAA.',
Me='Meelonusk:BAAALgAECgQJCAAAAA==.Mess:BAAALgAECgYJDAAAAA==.Messah:BAAALgAECgQJCgAAAA==.Messic:BAAALgADCgEJAQAAAA==.',
Mi='Michaelcoyle:BAACLgAFFH8HAAIZAAQJZQ3oOwAqAQAZAAQJZQ3oOwAqAQAuAAQKfzQAAhkACAnuHsUdAGgCABkACAnuHsUdAGgCAAAA.Midnightcrow:BAAALgADCgkJDwAAAA==.Milo:BAACLgAFFH8QAAILAAQJFiGCDACOAQALAAQJFiGCDACOAQAuAAQKfzcAAwsACQlFI6gFAP4CAAsACQlFI6gFAP4CAAoACAluHBQEALQCAAAA.Miorine:BAAALgAECgEJAgAAAA==.Mishra:BAAALgAECgUJBQAAAA==.Mitra:BAABLgAECn86AAIXAAkJuSKoAAApAwAXAAkJuSKoAAApAwAAAA==.',
Mo='Moesko:BAABLgAECn8VAAIGAAkJcBJIPACZAQAGAAkJcBJIPACZAQAAAA==.Mof:BAAALgADCgEJAQAAAA==.Mohawkk:BAAALgAECgQJBQAAAA==.Monktup:BAAALgAECgYJCwAAAA==.Monnehbaggs:BAABLgAECn8vAAMTAAkJPxz/DQB7AgAfAAgJBRtfDQCLAgATAAgJpR3/DQB7AgAAAA==.Mortalidad:BAAALgADCgQJBAAAAA==.',
Mu='Muin:BAAALgAECgEJAQAAAA==.Murdersamich:BAAALgAECgQJCwAAAA==.',
My='Mybigcrits:BAAALgAECgYJDAAAAA==.Myraghor:BAAALgADCgYJBgAAAA==.',
['Mà']='Màevë:BAAALgAECgEJAgAAAA==.',
Na='Nairdax:BAAALgADCgEJAQAAAA==.Nalmec:BAABLgAECn8hAAILAAYJPQgDWQDgAAALAAYJPQgDWQDgAAAAAA==.Nama:BAAALgADCgcJFAAAAA==.Naysayre:BAABLgAECn8wAAIPAAgJ4AfAggAOAQAPAAgJ4AfAggAOAQAAAA==.',
Ne='Nebody:BAAALgAECgYJDQAAAA==.Necriss:BAABLgAECn8sAAIhAAkJUxD0XQCrAQAhAAkJUxD0XQCrAQAAAA==.Nevereven:BAAALgAECgEJAQAAAA==.',
Ni='Nightkilla:BAAALgAECgEJAwAAAA==.Nike:BAAALgAECggJDwAAAA==.Nilowin:BAABLgAECn8zAAIBAAgJNRFDHgCWAQABAAgJNRFDHgCWAQAAAA==.',
No='Nokaj:BAAALgAECgEJAgAAAA==.Noshards:BAAALgAECgcJDQAAAA==.Notericdh:BAAALgAECgYJEwAAAA==.',
Og='Oghom:BAAALgADCgcJCgAAAA==.',
Oh='Ohnoitzgumby:BAABLgAECn8cAAMUAAcJuhZjZwCQAQAUAAcJrBZjZwCQAQAkAAMJoBJPFABOAAAAAA==.',
Om='Omiko:BAAALgAECgIJAgAAAA==.',
Op='Opeep:BAAALgADCgcJGQAAAA==.',
Or='Orah:BAAALgADCgEJAQAAAA==.',
Os='Osos:BAAALgAECgYJEAAAAA==.',
Pa='Paladimdab:BAAALgAECgQJBQAAAA==.Papachance:BAABLgAECn8VAAIIAAcJswYyvAAKAQAIAAcJswYyvAAKAQAAAA==.Papafrank:BAAALgAECgYJCgAAAA==.Paradis:BAAALgADCgcJBwAAAA==.Pazuzu:BAAALgADCgYJBgAAAA==.',
Pe='Peepo:BAAALgAECgEJAQAAAA==.',
Pi='Pinga:BAABLgAECn8cAAQfAAkJnx/BBQAgAwAfAAkJMx/BBQAgAwATAAIJ+hx7WwBdAAASAAEJmQ5pfQA0AAABLgAFFAQJCAAlAHgWAA==.Pinkberry:BAAALgAECgQJBAAAAA==.Pintcube:BAAALgADCgYJCAAAAA==.',
Pl='Pljeskavica:BAAALgAECgYJBwAAAA==.Plox:BAAALgAECgMJAwAAAA==.',
Po='Port:BAABLgAECn8wAAIGAAkJ8R7FCwD7AgAGAAkJ8R7FCwD7AgAAAA==.Potroastjr:BAAALgADCgEJAgABLgAECgEJAQARAAAAAA==.',
Pr='Preposition:BAAALgAECgcJBwAAAA==.Primordus:BAAALgADCgUJBQAAAA==.Profiler:BAAALgAECgcJCgAAAA==.Protocol:BAAALgAECgMJAwAAAA==.Prïestess:BAAALgAECgcJDAAAAA==.',
Ps='Pseriph:BAABLgAECn8ZAAIDAAcJ3BZrCwAKAgADAAcJ3BZrCwAKAgAAAA==.',
Ra='Radamantis:BAAALgAECgQJBwAAAA==.Raenon:BAAALgADCgkJEAAAAA==.Raggnar:BAACLgAFFH8TAAIJAAQJQCFAEgB2AQAJAAQJQCFAEgB2AQAuAAQKfzEAAgkACQmVIdcGAOUCAAkACQmVIdcGAOUCAAAA.Ragingwaters:BAAALgADCgYJCAABLgAECgIJBgARAAAAAA==.Ranvir:BAAALgAECgEJAQAAAA==.Raun:BAABLgAECn87AAMhAAkJBiOJCAAeAwAhAAkJBiOJCAAeAwAOAAMJJBEvcgCzAAAAAA==.',
Re='Regnarr:BAAALgADCgEJAQAAAA==.Rehgar:BAAALgAFFAEJAQAAAA==.Relaire:BAABLgAECn8/AAIZAAkJrBMYMAARAgAZAAkJrBMYMAARAgAAAA==.Remenissions:BAAALgAECgEJAQAAAA==.Resonate:BAAALgAFFAIJAwAAAA==.',
Ri='Rikane:BAAALgADCgcJDAABLgADCgcJEgARAAAAAA==.Rikenji:BAAALgAECgEJAQABLgAECggJIAAIAAoWAA==.Riku:BAABLgAECn82AAIjAAkJvSB4AgD1AgAjAAkJvSB4AgD1AgAAAA==.',
Ro='Rock:BAAALgAECgcJEgAAAA==.Rocks:BAAALgAECgEJAQAAAA==.Rockyrag:BAAALgAECgUJBQAAAA==.Roguey:BAABLgAECn8sAAMmAAkJuQ/OCwBoAQAmAAcJlBHOCwBoAQABAAcJ/wwBJwBOAQAAAA==.Roots:BAAALgAECgEJCAAAAA==.',
Ru='Rulethrefour:BAAALgAECgQJCAAAAA==.',
Ry='Ryveri:BAABLgAECn8lAAILAAkJDxmqGwAKAgALAAkJDxmqGwAKAgAAAA==.',
Sa='Sablehide:BAABLgAECn8zAAIHAAkJXBmCEQBRAgAHAAkJXBmCEQBRAgAAAA==.Sanaron:BAAALgADCgIJAgAAAA==.Sanaty:BAAALgAFFAIJBAAAAA==.Sarnak:BAAALgADCgMJAwAAAA==.Saryn:BAAALgAECgYJDwAAAA==.Satanz:BAAALgADCgIJAgAAAA==.Sathanus:BAAALgAECgQJEAAAAA==.',
Se='Searate:BAAALgADCgcJEgAAAA==.Seaside:BAACLgAFFH8PAAIUAAMJ/iX3HAAvAQAUAAMJ/iX3HAAvAQAuAAQKfxgAAxQABwk9JU5BAPgBABQABwk9JU5BAPgBABsAAgmEC+8/AE4AAAAA.Secrett:BAABLgAECn8YAAMBAAcJ9xPaKQA5AQABAAcJ9xPaKQA5AQAmAAEJew5NJwAwAAAAAA==.Sephyxia:BAABLgAECn8vAAIbAAkJdBo+DQArAgAbAAkJdBo+DQArAgAAAA==.Serryon:BAAALgADCgIJAgAAAA==.',
Sf='Sfora:BAAALgAECgQJBAAAAA==.',
Sh='Shadowwzz:BAAALgADCgEJAQAAAA==.Shocknezz:BAAALgADCgIJAQAAAA==.Shockwaves:BAAALgAECgEJAQAAAA==.Shoçknezz:BAAALgAECgMJBQAAAA==.',
Si='Silverwolf:BAABLgAECn9GAAIeAAkJ/SBeAgDwAgAeAAkJ/SBeAgDwAgAAAA==.Simplyunlock:BAACLgAFFH8TAAICAAQJTgu8VwAKAQACAAQJTgu8VwAKAQAuAAQKfyYAAwIACAl1FV1BANMBAAIACAl1FV1BANMBAAMAAgnnBZVmAEMAAAAA.Simplyvoided:BAAALgAECgQJBgAAAA==.Sinfulcynic:BAAALgADCgQJBQAAAA==.Sinverguenza:BAAALgAECgMJBQAAAA==.Sizzlechop:BAABLgAECn8uAAMUAAkJ/g/wfgBdAQAUAAgJ7QrwfgBdAQAbAAMJrBZaMgDHAAAAAA==.',
Sk='Skizzak:BAAALgADCgQJBAABLgAFFAYJGAAUAMgjAA==.Skweeks:BAAALgAECgMJBAAAAA==.',
Sm='Smelvin:BAABLgAECn8cAAIJAAkJ8xmGGwD4AQAJAAkJ8xmGGwD4AQABLgAECgQJCAARAAAAAA==.Smoko:BAAALgAECgIJAgABLgAECgUJBQARAAAAAA==.',
Sn='Snailslolol:BAAALgAECgcJCgAAAA==.Snakey:BAECLgAFFH8ZAAMHAAUJGgnbNQDhAAAHAAQJGgnbNQDhAAAnAAIJ1wK1DgA9AAAuAAQKfywAAwcACAmLGD4aAPkBAAcACAmLGD4aAPkBACcABgl5BHkmAO8AAAAA.',
So='Solara:BAABLgAECn8hAAQSAAkJMRiHFQAYAgASAAkJMRiHFQAYAgATAAEJQAIShwApAAAfAAEJXgKYXgAkAAAAAA==.Soleill:BAAALgAECgcJBwAAAA==.Sondan:BAAALgADCgMJAwAAAA==.Songs:BAAALgAECgEJAQABLgAECgYJGAANAP8gAA==.',
Sp='Spellpowa:BAAALgAECgYJDgAAAA==.',
Sq='Squirtin:BAAALgAECgIJAgAAAA==.',
Ss='Ssminion:BAAALgAECgMJBgAAAA==.',
St='Stalath:BAAALgAECgQJBAAAAA==.Stormwing:BAABLgAECn8eAAIJAAgJiBkkJAC4AQAJAAgJiBkkJAC4AQAAAA==.Strecagosa:BAAALgAECgYJDQAAAA==.',
Su='Sumarr:BAAALgAECgYJBgAAAA==.',
Sv='Svenn:BAAALgAECgYJBgAAAA==.',
Sy='Sybelissa:BAAALgAECgMJAwABLgAECgcJCgARAAAAAA==.Synni:BAAALgADCgEJAQAAAA==.',
['Sÿ']='Sÿnÿster:BAAALgAECgQJBQABLgAFFAUJEgAZAI4cAA==.',
Ta='Talron:BAAALgAECgUJCAAAAA==.Tastytay:BAAALgADCgMJAwAAAA==.Tatertots:BAABLgAECn8yAAMkAAkJFCBBAgDgAgAkAAkJFCBBAgDgAgAUAAMJ8hON7ACmAAAAAA==.',
Te='Tea:BAABLgAECn8xAAIZAAkJgCUTAwBZAwAZAAkJgCUTAwBZAwAAAA==.Teal:BAAALgAECgMJAwAAAA==.Templyn:BAABLgAECn8hAAMbAAkJJBSMGACRAQAbAAgJCRaMGACRAQAUAAkJmQg8gABaAQAAAA==.Templÿn:BAAALgADCgIJAgABLgAECgkJIQAbACQUAA==.Tenebrarum:BAABLgAECn8bAAIZAAgJGQ0xVwBjAQAZAAgJGQ0xVwBjAQAAAA==.Testorooni:BAABLgAECn8ZAAIZAAcJkBgpMwDjAQAZAAcJkBgpMwDjAQAAAA==.',
Th='Thakodi:BAAALgAECgQJBAAAAA==.Thannos:BAAALgADCgEJAQAAAA==.Tharvan:BAAALgADCgcJDAAAAA==.Thavok:BAAALgAECgEJAQAAAA==.Thedeadman:BAABLgAECn8kAAIUAAkJEyKxIAB+AgAUAAkJEyKxIAB+AgAAAA==.Thepriestg:BAAALgAECgEJAQAAAA==.Thiccksilver:BAAALgADCgcJBwABLgAFFAQJCwACAAUWAA==.Thompson:BAABLgAECn8VAAIUAAcJuxQOjQBCAQAUAAcJuxQOjQBCAQAAAA==.Thunderflaps:BAAALgAECgUJCQAAAA==.Thyrus:BAACLgAFFH8IAAIlAAQJeBZgFQAoAQAlAAQJeBZgFQAoAQAuAAQKfzUAAyUACQk9IlIDAA4DACUACQk9IlIDAA4DACcAAQmqAvtEACMAAAAA.',
Ti='Tirna:BAABLgAECn84AAIgAAkJng4MBACuAQAgAAkJng4MBACuAQAAAA==.',
To='Toebot:BAAALgAECgEJAQAAAA==.Toggle:BAAALgAECgEJAQAAAA==.Tomsellock:BAABLgAECn8WAAMEAAcJjhBuBwDcAQAEAAcJjhBuBwDcAQACAAEJugM+LAEmAAAAAA==.Tonari:BAAALgAECgEJAQABLgAECgYJEAARAAAAAA==.Torvi:BAAALgADCgMJAwAAAA==.',
Tr='Transmørtuus:BAAALgAECgQJCQAAAA==.Treehug:BAAALgAECggJEwAAAA==.Triple:BAAALgAECgQJBwABLgAECgYJEAARAAAAAA==.Trolleonne:BAAALgAECgIJAgAAAA==.',
Tu='Tullen:BAEBLgAECn81AAITAAkJjRGxIACvAQATAAkJjRGxIACvAQAAAA==.Turanos:BAAALgAECgQJEAAAAA==.',
Tw='Tweyen:BAAALgAECgEJAQAAAA==.Twistedbael:BAAALgAECgUJBQAAAA==.',
Ty='Tyindaris:BAAALgAECgQJCgAAAA==.Tyloregeth:BAABLgAECn8sAAISAAgJphRVJgCRAQASAAgJphRVJgCRAQAAAA==.',
['Tè']='Tèmplyn:BAAALgADCgEJAQABLgAECgkJIQAbACQUAA==.',
['Té']='Témplýn:BAAALgADCgEJAQABLgAECgkJIQAbACQUAA==.',
['Të']='Tëmplýn:BAAALgAECgIJAgABLgAECgkJIQAbACQUAA==.',
Ul='Ulfrunn:BAAALgADCgYJBgAAAA==.Ultrachad:BAACLgAFFH8dAAIUAAcJ9hjcGgDqAQAUAAcJ9hjcGgDqAQAuAAQKfx4AAhQACAlNIwUUAAMDABQACAlNIwUUAAMDAAAA.',
Um='Umami:BAABLgAECn8gAAILAAYJ+RhzSgB7AQALAAYJ+RhzSgB7AQAAAA==.',
Un='Unggoy:BAACLgAFFH8kAAQaAAgJHR38AgAkAgAaAAgJ9Bv8AgAkAgAYAAQJyRR1DwA8AQAZAAIJsRmwagCrAAAuAAQKfygAAxoACQkhJrsBAKYDABoACQkhJrsBAKYDABkAAQnFJXzmAGwAAAAA.Unhollowed:BAAALgAECgIJAgAAAA==.Unholywaters:BAAALgAECgIJBgAAAA==.',
Ur='Urianna:BAAALgAECgYJCwAAAA==.',
Va='Vaelthirion:BAABLgAECn8nAAIIAAgJYxY+TADwAQAIAAgJYxY+TADwAQAAAA==.Vahidamus:BAAALgAECggJCwAAAA==.Valkaryon:BAAALgAECgcJCgABLgAFFAIJAwARAAAAAA==.Valmirax:BAAALgADCggJEgAAAA==.Valton:BAABLgAECn9VAAIhAAgJHBJLZgCYAQAhAAgJHBJLZgCYAQAAAA==.',
Ve='Vegetation:BAAALgAECgQJBwAAAA==.Velenestus:BAAALgAECgMJBgAAAA==.Verses:BAAALgADCgEJAQAAAA==.',
Vi='Vizsla:BAAALgAECgEJAQAAAA==.',
Wa='Wackaman:BAABLgAECn8nAAIMAAkJvBx6CABnAgAMAAkJvBx6CABnAgAAAA==.Warpig:BAAALgAECgYJEQAAAA==.Wasps:BAAALgAECgYJEQAAAA==.',
We='Wegmaniac:BAAALgADCgYJCAAAAA==.Welastrexa:BAAALgADCgUJBQABLgAECgIJBgARAAAAAA==.',
Wi='Wickedclöwn:BAAALgADCgMJAwAAAA==.Winchester:BAAALgADCgIJAgAAAA==.Windhorn:BAAALgAECgYJEAAAAA==.Winds:BAABLgAECn8YAAINAAYJ/yBoFwAqAgANAAYJ/yBoFwAqAgAAAA==.',
Wn='Wntrizcoming:BAAALgADCgMJBQAAAA==.',
Wo='Wolfquota:BAACLgAFFH8QAAIJAAQJJx59GgAxAQAJAAQJJx59GgAxAQAuAAQKfyQAAwkACAmCIkkJAP4CAAkACAmCIkkJAP4CAB4ABAntE08eAOkAAAAA.Wolftime:BAAALgADCgUJBQAAAA==.Wombaa:BAACLgAFFH8XAAMUAAUJoiU0KQCiAQAUAAUJoiU0KQCiAQAkAAIJPR5AFgC0AAAuAAQKfxwAAhQACAleJGEKAEgDABQACAleJGEKAEgDAAAA.Woolybully:BAAALgAECgEJAQABLgAECgYJBwARAAAAAA==.',
Wr='Wrathbolt:BAAALgAECgEJAgABLgAFFAQJBwATAOMLAA==.Wrathmo:BAACLgAFFH8FAAINAAQJehn3DwAzAQANAAQJehn3DwAzAQAuAAQKfyUAAw0ACAljHD0TABkCAA0ABwlpHj0TABkCACgABwkdCho+APoAAAEuAAUUBAkHABMA4wsA.Wrathp:BAABLgAFFH8HAAITAAQJ4wtTFwDuAAATAAQJ4wtTFwDuAAAAAA==.Wrolie:BAAALgADCgMJAwAAAA==.',
['Wê']='Wêêdyys:BAAALgADCgMJBAAAAA==.',
Xy='Xyr:BAAALgAECgEJAQABLgAECgkJOQASAFUXAA==.',
Ya='Yamiamigo:BAAALgAECgEJAgAAAA==.',
Yo='Yonah:BAAALgAECgEJAQAAAA==.Yougotsniped:BAAALgADCgEJAQAAAA==.',
Za='Zandalia:BAAALgAECgMJAwAAAA==.Zark:BAEALgAECgEJAQABLgAECgkJGQAWAHsWAA==.',
Ze='Zemphoths:BAAALgAECgcJCgAAAA==.',
Zo='Zoa:BAAALgADCgYJBgAAAA==.Zolton:BAAALgADCgMJAwAAAA==.Zornak:BAABLgAECn8ZAAICAAUJlA1ctQDXAAACAAUJlA1ctQDXAAAAAA==.',
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
