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

local lookup = {'Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Druid-Restoration','Evoker-Augmentation','Mage-Frost','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Warrior-Protection','Monk-Windwalker','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Unknown-Unknown','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','Paladin-Retribution','DemonHunter-Havoc','Shaman-Restoration','Rogue-Outlaw','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Monk-Mistweaver','Druid-Guardian','Shaman-Enhancement','Priest-Discipline','Mage-Fire','Mage-Arcane','Druid-Feral','DeathKnight-Frost','Rogue-Assassination','Evoker-Devastation','Evoker-Preservation','Monk-Brewmaster',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aamon:BAAALgAECgQJCgAAAA==.',
Ab='Abacus:BAABLgAECn8jAAIBAAkJjyLXCQBxAgABAAkJjyLXCQBxAgAAAA==.',
Ac='Acin:BAAALgADCgQJBAAAAA==.',
Ad='Adam:BAACLgAFFH8ZAAQCAAcJWxs+LgBiAQACAAUJLhw+LgBiAQADAAMJlBFcDQCiAAAEAAEJECZODgByAAAuAAQKfy4ABAIACQk2JF4WAM4CAAIACQmcI14WAM4CAAMABQljJKcNAOsBAAQAAQkaI5coAGEAAAAA.Adedruid:BAABLgAECn8gAAMFAAYJdR9cKwCnAQAFAAYJdR9cKwCnAQAGAAYJ3xoBSgB6AQAAAA==.Adevoker:BAAALgAECgQJBAAAAA==.Adragon:BAABLgAECn8rAAIHAAkJ5RqpDQBtAgAHAAkJ5RqpDQBtAgAAAA==.',
Ae='Aengyl:BAAALgAECgQJBAAAAA==.Aeonne:BAABLgAECn8WAAIIAAgJyxJQgQBaAQAIAAgJyxJQgQBaAQAAAA==.',
Ak='Akshul:BAABLgAECn8UAAIJAAYJ5Q1HRgAvAQAJAAYJ5Q1HRgAvAQAAAA==.Akurama:BAAALgAECgcJCgAAAA==.',
Al='Aldrea:BAAALgAECgcJEAAAAA==.Allsmiles:BAABLgAECn8VAAQKAAkJZh7tCAAhAgAKAAgJhRrtCAAhAgALAAUJChm2TQBwAQAMAAQJkh4oKgDvAAAAAA==.Allura:BAAALgAECgQJBwAAAA==.Alorian:BAAALgAECgIJAgAAAA==.Alttharius:BAAALgAECgMJAwABLgAECgkJGQANALQgAA==.Alyysha:BAABLgAECn8bAAIOAAcJlwkCRgBgAQAOAAcJlwkCRgBgAQAAAA==.',
Am='Amoon:BAABLgAECn81AAMPAAkJgBn6IwAqAgAPAAkJ0Rf6IwAqAgAQAAYJBRXoEAAkAQAAAA==.',
An='Andoriel:BAAALgADCgcJBwABLgAFFAIJAwARAAAAAA==.Angelrain:BAABLgAECn8sAAMSAAgJWByRDgCaAgASAAgJWByRDgCaAgATAAcJ8QcGNgASAQAAAA==.Aniata:BAAALgAECgEJAQAAAA==.',
Ar='Archymedes:BAABLgAECn8sAAILAAcJJxFrNwBUAQALAAcJJxFrNwBUAQAAAA==.Arckady:BAAALgAECgQJCwAAAA==.Areko:BAAALgAECgIJBQAAAA==.Aresh:BAAALgAECgEJAgAAAA==.Artharius:BAABLgAECn8ZAAINAAkJtCA/EQBvAgANAAkJtCA/EQBvAgAAAA==.',
Au='Auburnbeard:BAAALgADCgYJBgAAAA==.Aumed:BAAALgADCgEJAQAAAA==.',
Av='Averle:BAABLgAECn9YAAIDAAcJNQo1FADwAAADAAcJNQo1FADwAAAAAA==.',
Az='Azrran:BAAALgADCgEJAQAAAA==.Aztharot:BAAALgAECgIJAgAAAA==.',
Ba='Badchoices:BAAALgAECgQJBAAAAA==.Badkittie:BAAALgAECgMJAwAAAA==.Balding:BAAALgAECgEJAgAAAA==.Baphico:BAAALgADCgUJCQAAAA==.',
Be='Bearhug:BAAALgAECgEJAQAAAA==.Behemoth:BAAALgAECgQJBAAAAA==.Belinda:BAAALgAECgEJAQABLgAFFAYJGAAUAMgjAA==.Bettyßaraxus:BAAALgAECgMJAwABLgAECgkJMQAVAMAfAA==.Bewater:BAAALgADCgcJBwAAAA==.',
Bi='Bigcarol:BAAALgAECgEJAQAAAA==.',
Bl='Bladesmcgee:BAAALgAECggJCQABLgAECgQJCAARAAAAAA==.Blasphem:BAAALgADCgQJBAAAAA==.',
Bo='Bobadelphia:BAAALgADCgYJBgABLgAECgYJEQARAAAAAA==.Bofahdeez:BAABLgAECn8aAAMTAAgJfA6+PABHAQATAAcJWA6+PABHAQASAAcJLQzSNgAYAQAAAA==.Bogs:BAACLgAFFH8SAAIIAAUJmx37QgBGAQAIAAUJmx37QgBGAQAuAAQKfyMAAggACAnrIb4jAOQCAAgACAnrIb4jAOQCAAAA.Bonedaddy:BAAALgAECgYJBgAAAA==.',
Br='Brewswayne:BAAALgADCgQJBAABLgAFFAIJAwARAAAAAA==.Brolic:BAABLgAECn8rAAMWAAgJ8x20DQAqAgAWAAgJ8x20DQAqAgAPAAEJJgnADAEkAAAAAA==.',
['Bä']='Bämboo:BAAALgAFFAEJAgABLgAFFAQJCwAXAOoQAA==.',
Ca='Cail:BAEBLgAECn8ZAAIXAAkJexbnGwBSAgAXAAkJexbnGwBSAgAAAA==.Calamìty:BAAALgADCgcJDgABLgAECgkJKAAGADYRAA==.Calisa:BAABLgAECn87AAIYAAkJ6h8vAQDoAgAYAAkJ6h8vAQDoAgAAAA==.Cardio:BAAALgAECgUJBgAAAA==.Carnifexx:BAAALgAFFAIJAgABLgAFFAcJHAAPADMYAA==.Cassey:BAAALgAECgEJAQAAAA==.',
Ce='Celesteus:BAAALgADCgkJFAAAAA==.',
Ch='Charis:BAAALgAECgYJCwAAAA==.Chigutotems:BAAALgAECgYJCwABLgAECgkJGwAPAGwWAA==.Choi:BAAALgAECgUJDwAAAA==.Chooq:BAAALgADCgIJAgAAAA==.Chozen:BAAALgAECgUJEAAAAA==.Chumlee:BAAALgAECgYJCwAAAA==.',
Ci='Cienna:BAAALgAECgYJDgAAAA==.Cigz:BAAALgADCgEJAQAAAA==.Cinch:BAAALgAECgIJAgAAAA==.',
Co='Colinferral:BAAALgAECgYJCAAAAA==.Coulee:BAAALgAECgQJCAABLgAECggJKQAWABohAA==.Cowladin:BAAALgADCgUJBQAAAA==.',
Cr='Crakzkull:BAAALgAECgUJCwAAAA==.Croar:BAAALgAECgMJBAAAAA==.Cronicpain:BAAALgADCgkJCQAAAA==.',
Cu='Cuernuda:BAAALgAECgEJAQAAAA==.',
['Cä']='Cäntstandya:BAACLgAFFH8RAAMZAAQJVRhBGAD2AAAZAAMJnxdBGAD2AAAaAAMJmRj+TgDjAAAuAAQKfyMAAxoACAkvG1cSAKUCABoACAliGVcSAKUCABkABwkaHgsRABgCAAAA.',
Da='Daiko:BAAALgAECgYJCQAAAA==.Daks:BAAALgAFFAIJAwAAAA==.Dargo:BAAALgAECgYJEwAAAA==.Darklucrezia:BAACLgAFFH8RAAMaAAUJjhyfHwBdAQAaAAUJjhyfHwBdAQAbAAIJNgJlKgBNAAAuAAQKfy4AAxoACAn3H2IYAH0CABoACAltH2IYAH0CABsACAkOEeQlAPoBAAAA.Dazzlefraz:BAAALgAECgQJBAAAAA==.',
De='Demonklunter:BAAALgADCgYJEAAAAA==.Destructoid:BAAALgAECgEJAQAAAA==.',
Di='Dicey:BAAALgADCgMJAwABLgAECgQJBwARAAAAAA==.',
Do='Dochunter:BAAALgAECgUJBQAAAA==.',
Dr='Dracarius:BAAALgAECgQJDAAAAA==.Drega:BAAALgAECgYJBwAAAA==.Droods:BAAALgAECgQJBQAAAA==.Drtypinkcake:BAABLgAECn8eAAIWAAYJpQkwMwDPAAAWAAYJpQkwMwDPAAAAAA==.Druskgar:BAABLgAECn8mAAMUAAkJlh4kPAD9AQAUAAgJzyEkPAD9AQAcAAcJ4A8EHwBDAQAAAA==.Dryad:BAAALgAECgQJCwAAAA==.',
Du='Duckster:BAAALgADCgYJBwAAAA==.Dunce:BAACLgAFFH8FAAIdAAIJdR9rLgC1AAAdAAIJdR9rLgC1AAAuAAQKfycAAh0ACAnyIGkLAMMCAB0ACAnyIGkLAMMCAAAA.Durkk:BAABLgAECn87AAIcAAkJ9yFPBADgAgAcAAkJ9yFPBADgAgAAAA==.Durza:BAAALgAECgcJEAAAAA==.',
['Dä']='Dännydevito:BAAALgADCgQJBAAAAA==.',
Ed='Eduard:BAAALgAECgYJCQAAAA==.',
Ek='Eklipse:BAAALgAECgMJAwAAAA==.',
El='Elanthae:BAAALgAECgQJEQAAAA==.Elysia:BAAALgAECgEJAgAAAA==.',
Er='Erzulie:BAAALgAECgUJBAAAAA==.',
Es='Estara:BAABLgAECn81AAIeAAkJqwvmHwAoAQAeAAkJqwvmHwAoAQAAAA==.',
Et='Etali:BAABLgAECn8yAAILAAkJQBw0DgB6AgALAAkJQBw0DgB6AgAAAA==.',
Ex='Expired:BAAALgAECgEJAQAAAA==.',
Ez='Ezazel:BAAALgADCgUJBwAAAA==.',
Fa='Faite:BAAALgADCgUJBQAAAA==.Falorin:BAABLgAECn8gAAIIAAgJChZMWQC5AQAIAAgJChZMWQC5AQAAAA==.Fanis:BAABLgAECn8mAAIbAAkJzRVKCADmAQAbAAkJzRVKCADmAQAAAA==.Fatherwhig:BAAALgAECgIJAwAAAA==.',
Fi='Fidis:BAAALgADCgkJCwAAAA==.Fistsofdeath:BAAALgADCggJCgAAAA==.Fistychub:BAAALgADCgEJAQAAAA==.',
Fl='Flashbang:BAAALgADCgEJAQAAAA==.Flashis:BAAALgAECggJEwAAAA==.Florago:BAAALgAECgQJDAAAAA==.',
Fr='Frakir:BAABLgAECn87AAQXAAkJ5xnFFQCDAgAXAAkJ5xnFFQCDAgAfAAMJRwr3JgCMAAAJAAEJkAYjkwAjAAAAAA==.Fritzz:BAAALgAECgcJEgABLgAECgkJEAARAAAAAA==.Frog:BAAALgAECgIJBQAAAA==.',
Fu='Furrypaw:BAABLgAECn8uAAIdAAkJZiVbAQC/AwAdAAkJZiVbAQC/AwAAAA==.',
Fw='Fwapp:BAACLgAFFH8YAAIOAAYJ6B55DQC7AQAOAAYJ6B55DQC7AQAuAAQKfxcAAg4ACAlrIcgLAL8CAA4ACAlrIcgLAL8CAAAA.',
Ga='Galvanize:BAAALgAECgEJBAAAAA==.Galynisse:BAABLgAECn8wAAMgAAgJAhjkEQA4AgAgAAgJAhjkEQA4AgATAAMJ7A4eZQCZAAAAAA==.',
Ge='Gedorah:BAABLgAECn8fAAIhAAcJOBz1AgDoAQAhAAcJOBz1AgDoAQABLgAFFAMJDwAJAFkiAA==.',
Gh='Ghaspy:BAAALgAECgUJCgAAAA==.Ghoste:BAAALgADCgMJAwAAAA==.Ghrex:BAAALgAECgEJAQAAAA==.',
Gi='Gijaick:BAABLgAECn8vAAMCAAgJWBjyPgDTAQACAAgJWBjyPgDTAQADAAEJHg4AdAAxAAAAAA==.',
Gl='Glaivethrow:BAABLgAECn8bAAIPAAkJbBavOADNAQAPAAkJbBavOADNAQAAAA==.Glizzo:BAAALgAECgYJDAAAAA==.Gloam:BAAALgADCgUJBQAAAA==.',
Go='Gochujjang:BAAALgAECgYJDQAAAA==.Goldhawk:BAAALgAECgMJAwAAAA==.Gotchá:BAAALgAECgEJBAAAAA==.Gotwiped:BAABLgAECn8WAAIUAAgJfRpHNAAaAgAUAAgJfRpHNAAaAgAAAA==.',
Gr='Grimgor:BAAALgAECgcJAQAAAA==.',
Ha='Hahaheals:BAAALgAECgMJBAAAAA==.Hakhar:BAAALgADCgMJAwAAAA==.Hanth:BAAALgADCgkJDAABLgAECgMJBAARAAAAAA==.Hatter:BAABLgAECn8kAAQPAAgJ2hPeYABOAQAPAAgJaRPeYABOAQAWAAMJ+AsRWACGAAAQAAEJNRMmKwA0AAAAAA==.',
He='Healsus:BAAALgAECgMJAwAAAA==.Heimlish:BAAALgAECgEJAQAAAA==.Hellraiser:BAABLgAECn8lAAMUAAcJfhlYXQCcAQAUAAcJVBhYXQCcAQAcAAUJERh+JAAUAQAAAA==.Hermione:BAAALgAECgYJDQAAAA==.Hexecution:BAAALgADCgIJAgAAAA==.',
Hi='Hiddendragon:BAAALgAECgEJAQAAAA==.',
Ho='Holydarkness:BAAALgAECgYJCgAAAA==.Holyhello:BAAALgAECgEJAQAAAA==.Holykilla:BAAALgAECgEJBQAAAA==.Holykiller:BAAALgAECgcJCgAAAA==.Hoofjob:BAAALgADCggJDgABLgAFFAQJDQAgANcgAA==.Hoplite:BAAALgADCgYJCAABLgAECggJEgARAAAAAA==.Hotot:BAAALgADCgMJAwAAAA==.Howlly:BAAALgAECggJCAAAAA==.',
Hu='Huffpuffle:BAAALgAECgUJCgAAAA==.',
['Hô']='Hôwl:BAABLgAECn8YAAIGAAcJwhBuQwBwAQAGAAcJwhBuQwBwAQAAAA==.',
Ic='Icdeathg:BAACLgAFFH8JAAIPAAMJ/QvdWQDAAAAPAAMJ/QvdWQDAAAAuAAQKfzEAAg8ACAksH1cXAHYCAA8ACAksH1cXAHYCAAAA.',
Ik='Iktaar:BAAALgAECgYJDgAAAA==.',
Il='Illidami:BAAALgADCgkJCwAAAA==.Illidamngirl:BAAALgADCgYJBgABLgAECgkJJwAMALwcAA==.',
Im='Imperius:BAACLgAFFH8VAAIVAAUJHBbcOAAiAQAVAAUJHBbcOAAiAQAuAAQKfyQAAhUACQmMJB0OAB0DABUACQmMJB0OAB0DAAAA.',
In='Ines:BAACLgAFFH8KAAIUAAMJWSH9ZwAPAQAUAAMJWSH9ZwAPAQAuAAQKfzoAAhQACQlrJPYIABoDABQACQlrJPYIABoDAAAA.Insomiax:BAAALgAECggJDwAAAA==.Insta:BAABLgAECn8qAAILAAcJzx3cIwA3AgALAAcJzx3cIwA3AgAAAA==.Inter:BAABLgAECn8vAAIcAAkJ9yE6BAALAwAcAAkJ9yE6BAALAwAAAA==.',
Ir='Iridi:BAAALgADCgEJAQAAAA==.Iritall:BAAALgADCgcJCwABLgAECgEJAgARAAAAAA==.',
It='Ithamburglar:BAAALgAECgQJBwAAAA==.',
Iz='Izureka:BAAALgADCgYJBgAAAA==.',
Ja='Jackidaytona:BAAALgAECgcJBwAAAA==.Jakaru:BAAALgAFFAIJAgAAAA==.Jankadish:BAAALgAECgcJEwAAAA==.Jarre:BAACLgAFFH8GAAIGAAQJrggsDgAFAQAGAAQJrggsDgAFAQAuAAQKfygAAgYACAmzICIKAPMCAAYACAmzICIKAPMCAAAA.Jaspirian:BAAALgADCggJFAAAAA==.Jazzil:BAAALgADCgcJCgAAAA==.',
Jb='Jbaconcheese:BAAALgAECgEJAQAAAA==.',
Je='Jehmothy:BAAALgAECgUJBQAAAA==.Jerome:BAAALgAECgEJAQAAAA==.',
Jo='Jotabop:BAAALgAECgQJBgAAAA==.',
Ju='Judgequota:BAAALgAFFAMJAwABLgAFFAQJEAAJACceAA==.Juicy:BAABLgAECn8kAAIZAAkJQRfqCwBYAgAZAAkJQRfqCwBYAgAAAA==.Juupiter:BAAALgAECgEJAQABLgAECggJIAAIAAoWAA==.',
Ka='Kabu:BAAALgAECgcJBwAAAA==.Kalia:BAABLgAECn8vAAMIAAkJ/xgVPgB/AgAIAAkJ/xgVPgB/AgAiAAMJUg8ADACbAAAAAA==.Kalitra:BAAALgADCgMJAwABLgAECgkJLwAIAP8YAA==.Katoumae:BAACLgAFFH8SAAIjAAUJNB2YBABNAQAjAAUJNB2YBABNAQAuAAQKfyMAAiMACAmSIesEAI4CACMACAmSIesEAI4CAAAA.Katoumey:BAAALgAECgYJCgABLgAFFAUJEgAjADQdAA==.',
Ke='Keratin:BAABLgAECn8uAAIkAAkJvSIIAwCZAgAkAAkJvSIIAwCZAgAAAA==.',
Kh='Khumi:BAABLgAECn8XAAIbAAgJYSCmEgCiAgAbAAgJYSCmEgCiAgABLgAFFAkJKAAVAOokAA==.',
Ki='Kinan:BAABLgAECn82AAMaAAkJHSZJAQB9AwAaAAkJHSZJAQB9AwAbAAcJOx6kFwBxAgAAAA==.Kita:BAAALgAECggJEgABLgAECgkJAgARAAAAAA==.',
Kk='Kkaarrkk:BAAALgAECgUJCAAAAA==.',
Kr='Krindon:BAABLgAECn8fAAIWAAcJSQ+OJgAgAQAWAAcJSQ+OJgAgAQAAAA==.',
Ku='Kureiji:BAAALgADCgEJAQAAAA==.',
Ky='Kythin:BAAALgAECgEJAQABLgAECgkJLwAIAP8YAA==.',
La='Lacutis:BAAALgAECgEJAQAAAA==.Lanssolo:BAAALgAECgMJAwAAAA==.Laww:BAAALgADCgcJCgAAAA==.',
Le='Lecroix:BAAALgADCgUJBQAAAA==.Leonus:BAAALgAECgMJAwABLgAECgIJAgARAAAAAA==.Lessana:BAAALgAECgQJDgAAAA==.Lethalforce:BAAALgADCgMJAwAAAA==.',
Li='Liandri:BAAALgADCgEJAgAAAA==.Lightchild:BAAALgADCggJCAAAAA==.Lightprivlge:BAAALgAECgcJDQAAAA==.Lillith:BAAALgAECgMJAwAAAA==.Livewire:BAAALgAECgQJDAAAAA==.',
Lo='Lokohmojo:BAAALgAECgMJBAAAAA==.Lomponic:BAEBLgAECn8zAAISAAkJ4RtwDQBiAgASAAkJ4RtwDQBiAgAAAA==.Loomadin:BAAALgADCgYJCQAAAA==.Loranis:BAAALgADCgMJAwAAAA==.',
Lu='Lunethra:BAABLgAECn8rAAIaAAkJwhGAKwAGAgAaAAkJwhGAKwAGAgAAAA==.',
Ma='Mageaux:BAAALgAECgEJAQAAAA==.Magerag:BAACLgAFFH8JAAIIAAMJGBuxZwD1AAAIAAMJGBuxZwD1AAAuAAQKfy4AAwgACAnWIbMvALMCAAgACAnWIbMvALMCACIAAglAGkQVAHMAAAAA.Manamontana:BAACLgAFFH8YAAMUAAYJLBK1NwBkAQAUAAUJLBK1NwBkAQAcAAEJAACYQQAAAAAuAAQKfxoAAhQACAn4H4AoAJgCABQACAn4H4AoAJgCAAAA.Marumo:BAAALgAECgMJBgAAAA==.',
Mc='Mcribz:BAACLgAFFH8YAAIUAAYJyCN8FwDaAQAUAAYJyCN8FwDaAQAuAAQKfyIAAhQACAl8IzIZAOUCABQACAl8IzIZAOUCAAAA.',
Me='Meelonusk:BAAALgAECgQJCAAAAA==.Mess:BAAALgAECgYJDAAAAA==.Messah:BAAALgAECgQJCgAAAA==.Messic:BAAALgADCgEJAQAAAA==.',
Mi='Michaelcoyle:BAABLgAECn80AAIaAAgJ7h4sGwBtAgAaAAgJ7h4sGwBtAgAAAA==.Midnightcrow:BAAALgADCgkJDwAAAA==.Milo:BAACLgAFFH8LAAILAAMJ4yXQFQBFAQALAAMJ4yXQFQBFAQAuAAQKfzcAAwsACQlFI/YEAAIDAAsACQlFI/YEAAIDAAoACAluHBQEALQCAAAA.Miorine:BAAALgAECgEJAgAAAA==.Mishra:BAAALgAECgUJBQAAAA==.Mitra:BAABLgAECn80AAIYAAkJiyHGAAALAwAYAAkJiyHGAAALAwAAAA==.',
Mo='Moesko:BAAALgAFFAEJAQAAAA==.Mof:BAAALgADCgEJAQAAAA==.Mohawkk:BAAALgAECgQJBQAAAA==.Monktup:BAAALgAECgYJCwAAAA==.Monnehbaggs:BAABLgAECn8vAAMTAAkJPxz/DQB7AgAgAAgJBRtZDACKAgATAAgJpR3/DQB7AgAAAA==.Mortalidad:BAAALgADCgQJBAAAAA==.',
Mu='Muin:BAAALgAECgEJAQAAAA==.Murdersamich:BAAALgAECgQJCwAAAA==.',
My='Mybigcrits:BAAALgAECgYJDAAAAA==.Myraghor:BAAALgADCgYJBgAAAA==.',
['Mà']='Màevë:BAAALgAECgEJAgAAAA==.',
Na='Nairdax:BAAALgADCgEJAQAAAA==.Nalmec:BAABLgAECn8hAAILAAYJPQi6VADgAAALAAYJPQi6VADgAAAAAA==.Nama:BAAALgADCgcJFAAAAA==.Naysayre:BAABLgAECn8oAAIPAAYJmAg4owC9AAAPAAYJmAg4owC9AAAAAA==.',
Ne='Nebody:BAAALgAECgYJDAAAAA==.Necriss:BAABLgAECn8sAAIVAAkJUxCbWgCkAQAVAAkJUxCbWgCkAQAAAA==.Nevereven:BAAALgAECgEJAQAAAA==.',
Ni='Nightkilla:BAAALgAECgEJAwAAAA==.Nike:BAAALgAECggJDwAAAA==.Nilowin:BAABLgAECn8xAAIBAAgJNRHUHACXAQABAAgJNRHUHACXAQAAAA==.',
No='Nokaj:BAAALgAECgEJAgAAAA==.Noshards:BAAALgAECgcJDQAAAA==.Notericdh:BAAALgAECgYJEwAAAA==.',
Og='Oghom:BAAALgADCgcJCgAAAA==.',
Oh='Ohnoitzgumby:BAABLgAECn8cAAMUAAcJuhYBYgCRAQAUAAcJrBYBYgCRAQAkAAMJoBJPFABOAAAAAA==.',
Om='Omiko:BAAALgAECgIJAgAAAA==.',
Op='Opeep:BAAALgADCgcJGQAAAA==.',
Or='Orah:BAAALgADCgEJAQAAAA==.',
Os='Osos:BAAALgAECgYJEAAAAA==.',
Pa='Paladimdab:BAAALgAECgQJBQAAAA==.Papachance:BAAALgAECggJDwAAAA==.Papafrank:BAAALgAECgUJBgAAAA==.Paradis:BAAALgADCgcJBwAAAA==.Pazuzu:BAAALgADCgYJBgAAAA==.',
Pe='Peepo:BAAALgAECgEJAQAAAA==.',
Pi='Pinga:BAABLgAECn8cAAQgAAkJnx8lBQAgAwAgAAkJMx8lBQAgAwATAAIJ+hwPWABeAAASAAEJmQ6JdQA0AAAAAA==.Pinkberry:BAAALgAECgQJBAAAAA==.Pintcube:BAAALgADCgYJCAAAAA==.',
Pl='Pljeskavica:BAAALgAECgYJBwAAAA==.Plox:BAAALgAECgMJAwAAAA==.',
Po='Port:BAABLgAECn8wAAIGAAkJ8R4NCwD8AgAGAAkJ8R4NCwD8AgAAAA==.Potroastjr:BAAALgADCgEJAgABLgAECgEJAQARAAAAAA==.',
Pr='Preposition:BAAALgAECgcJBwAAAA==.Primordus:BAAALgADCgUJBQAAAA==.Profiler:BAAALgAECgcJCgAAAA==.Protocol:BAAALgAECgMJAwAAAA==.Prïestess:BAAALgAECgcJDAAAAA==.',
Ps='Pseriph:BAABLgAECn8ZAAIDAAcJ3BZrCwAKAgADAAcJ3BZrCwAKAgAAAA==.',
Ra='Radamantis:BAAALgAECgQJBwAAAA==.Raenon:BAAALgADCgkJEAAAAA==.Raggnar:BAACLgAFFH8PAAIJAAMJWSILGgAjAQAJAAMJWSILGgAjAQAuAAQKfzEAAgkACQmVITUGAOkCAAkACQmVITUGAOkCAAAA.Ragingwaters:BAAALgADCgYJCAABLgAECgIJBgARAAAAAA==.Ranvir:BAAALgAECgEJAQAAAA==.Raun:BAABLgAECn87AAMVAAkJBiNQBwAgAwAVAAkJBiNQBwAgAwAOAAMJJBEvcgCzAAAAAA==.',
Re='Regnarr:BAAALgADCgEJAQAAAA==.Rehgar:BAAALgAFFAEJAQAAAA==.Relaire:BAABLgAECn83AAIaAAkJ8RIXLgANAgAaAAkJ8RIXLgANAgAAAA==.Remenissions:BAAALgAECgEJAQAAAA==.Resonate:BAAALgAFFAIJAwAAAA==.',
Ri='Rikane:BAAALgADCgcJDAABLgADCgcJEgARAAAAAA==.Rikenji:BAAALgAECgEJAQABLgAECggJIAAIAAoWAA==.Riku:BAABLgAECn82AAIjAAkJvSAZAgD5AgAjAAkJvSAZAgD5AgAAAA==.',
Ro='Rock:BAAALgAECgcJEgAAAA==.Rocks:BAAALgAECgEJAQAAAA==.Rockyrag:BAAALgADCgEJAQAAAA==.Roguey:BAABLgAECn8sAAMlAAkJuQ8TCwBuAQAlAAcJlBETCwBuAQABAAcJ/wzJJABUAQAAAA==.Roots:BAAALgAECgEJCAAAAA==.',
Ru='Rulethrefour:BAAALgAECgQJCAAAAA==.',
Ry='Ryveri:BAABLgAECn8lAAILAAkJDxmqGQAMAgALAAkJDxmqGQAMAgAAAA==.',
Sa='Sablehide:BAABLgAECn8wAAIHAAkJXBluEABKAgAHAAkJXBluEABKAgAAAA==.Sanaron:BAAALgADCgIJAgAAAA==.Sanaty:BAAALgAFFAEJAgAAAA==.Sarnak:BAAALgADCgMJAwAAAA==.Saryn:BAAALgAECgYJDwAAAA==.Satanz:BAAALgADCgIJAgAAAA==.Sathanus:BAAALgAECgQJDAAAAA==.',
Se='Searate:BAAALgADCgcJEgAAAA==.Seaside:BAACLgAFFH8PAAIUAAMJ/iV0SgA9AQAUAAMJ/iV0SgA9AQAuAAQKfxgAAxQABwk9JSI9APoBABQABwk9JSI9APoBABwAAgmEC+8/AE4AAAAA.Secrett:BAABLgAECn8YAAMBAAcJ9xPBJwA9AQABAAcJ9xPBJwA9AQAlAAEJew54JQAwAAAAAA==.Sephyxia:BAABLgAECn8vAAIcAAkJdBoQDAAxAgAcAAkJdBoQDAAxAgAAAA==.Serryon:BAAALgADCgIJAgAAAA==.',
Sf='Sfora:BAAALgAECgMJAwAAAA==.',
Sh='Shadowwzz:BAAALgADCgEJAQAAAA==.Shockwaves:BAAALgAECgEJAQAAAA==.Shoçknezz:BAAALgAECgMJBQAAAA==.',
Si='Silverwolf:BAABLgAECn8/AAIfAAkJsCCtAgDaAgAfAAkJsCCtAgDaAgAAAA==.Simplyunlock:BAACLgAFFH8QAAICAAQJTgugTwAVAQACAAQJTgugTwAVAQAuAAQKfyYAAwIACAl1FVU+ANYBAAIACAl1FVU+ANYBAAMAAgnnBZVmAEMAAAAA.Simplyvoided:BAAALgAECgQJBgAAAA==.Sinfulcynic:BAAALgADCgQJBQAAAA==.Sinverguenza:BAAALgAECgMJBQAAAA==.Sizzlechop:BAABLgAECn8rAAMUAAkJug/NeABdAQAUAAgJ7QrNeABdAQAcAAMJ+BWvMADCAAAAAA==.',
Sk='Skizzak:BAAALgADCgQJBAABLgAFFAYJGAAUAMgjAA==.Skweeks:BAAALgAECgMJBAAAAA==.',
Sm='Smelvin:BAABLgAECn8cAAIJAAkJ8xnYGQD7AQAJAAkJ8xnYGQD7AQABLgAECgQJCAARAAAAAA==.Smoko:BAAALgAECgIJAgABLgAECgUJBQARAAAAAA==.',
Sn='Snailslolol:BAAALgAECgcJCgAAAA==.Snakey:BAECLgAFFH8VAAMHAAUJGgmNMADlAAAHAAQJGgmNMADlAAAmAAIJ1wKwDQBBAAAuAAQKfywAAwcACAmLGD4aAPkBAAcACAmLGD4aAPkBACYABgl5BHkmAO8AAAAA.',
So='Solara:BAABLgAECn8hAAQSAAkJMRj1EwATAgASAAkJMRj1EwATAgATAAEJQAIShwApAAAgAAEJXgKYXgAkAAAAAA==.Soleill:BAAALgAECgcJBwAAAA==.Sondan:BAAALgADCgMJAwAAAA==.Songs:BAAALgAECgEJAQABLgAECgYJGAANAP8gAA==.',
Sp='Spellpowa:BAAALgAECgYJDgAAAA==.',
Sq='Squirtin:BAAALgAECgIJAgAAAA==.',
Ss='Ssminion:BAAALgAECgMJBgAAAA==.',
St='Stalath:BAAALgAECgMJAwAAAA==.Stormwing:BAABLgAECn8eAAIJAAgJiBmjIQC+AQAJAAgJiBmjIQC+AQAAAA==.Strecagosa:BAAALgAECgYJDQAAAA==.',
Su='Sumarr:BAAALgAECgYJBgAAAA==.',
Sv='Svenn:BAAALgAECgYJBgAAAA==.',
Sy='Sybelissa:BAAALgAECgMJAwABLgAECgcJCgARAAAAAA==.Synni:BAAALgADCgEJAQAAAA==.',
['Sÿ']='Sÿnÿster:BAAALgAECgQJBQABLgAFFAUJEQAaAI4cAA==.',
Ta='Talron:BAAALgAECgQJBwAAAA==.Tastytay:BAAALgADCgMJAwAAAA==.Tatertots:BAABLgAECn8yAAMkAAkJFCDhAQDdAgAkAAkJFCDhAQDdAgAUAAMJ8hON7ACmAAAAAA==.',
Te='Tea:BAABLgAECn8xAAIaAAkJgCWKAgBfAwAaAAkJgCWKAgBfAwAAAA==.Teal:BAAALgAECgMJAwAAAA==.Templyn:BAABLgAECn8fAAMcAAgJCRbPFgCWAQAcAAgJCRbPFgCWAQAUAAgJ2AjMlAApAQAAAA==.Templÿn:BAAALgADCgIJAgABLgAECggJHwAcAAkWAA==.Tenebrarum:BAABLgAECn8bAAIaAAgJGQ0xVwBjAQAaAAgJGQ0xVwBjAQAAAA==.Testorooni:BAABLgAECn8ZAAIaAAcJkBgpMwDjAQAaAAcJkBgpMwDjAQAAAA==.',
Th='Thakodi:BAAALgAECgQJBAAAAA==.Thannos:BAAALgADCgEJAQAAAA==.Tharvan:BAAALgADCgcJDAAAAA==.Thavok:BAAALgAECgEJAQAAAA==.Thedeadman:BAABLgAECn8kAAIUAAkJEyL7HQCBAgAUAAkJEyL7HQCBAgAAAA==.Thepriestg:BAAALgAECgEJAQAAAA==.Thiccksilver:BAAALgADCgcJBwABLgAFFAMJBwACAKcWAA==.Thompson:BAABLgAECn8VAAIUAAcJuxQWhgBDAQAUAAcJuxQWhgBDAQAAAA==.Thunderflaps:BAAALgAECgUJCQAAAA==.Thyrus:BAABLgAECn81AAMnAAkJPSInAwAOAwAnAAkJPSInAwAOAwAmAAEJqgL7RAAjAAABLgAECgkJHAAgAJ8fAA==.',
Ti='Tirna:BAABLgAECn84AAIhAAkJng58AwDDAQAhAAkJng58AwDDAQAAAA==.',
To='Toebot:BAAALgAECgEJAQAAAA==.Toggle:BAAALgAECgEJAQAAAA==.Tomsellock:BAABLgAECn8WAAMEAAcJjhBuBwDcAQAEAAcJjhBuBwDcAQACAAEJugM+LAEmAAAAAA==.Tonari:BAAALgAECgEJAQABLgAECgYJEAARAAAAAA==.Torvi:BAAALgADCgMJAwAAAA==.',
Tr='Transmørtuus:BAAALgAECgQJCQAAAA==.Treehug:BAAALgAECggJEwAAAA==.Triple:BAAALgAECgQJBwABLgAECgYJEAARAAAAAA==.Trolleonne:BAAALgAECgIJAgAAAA==.',
Tu='Tullen:BAEBLgAECn81AAITAAkJjREIHgC8AQATAAkJjREIHgC8AQAAAA==.Turanos:BAAALgAECgQJDAAAAA==.',
Tw='Tweyen:BAAALgAECgEJAQAAAA==.Twistedbael:BAAALgAECgUJBQAAAA==.',
Ty='Tyindaris:BAAALgAECgQJCgAAAA==.Tyloregeth:BAABLgAECn8sAAISAAgJphRZJACHAQASAAgJphRZJACHAQAAAA==.',
['Tè']='Tèmplyn:BAAALgADCgEJAQABLgAECggJHwAcAAkWAA==.',
['Té']='Témplýn:BAAALgADCgEJAQABLgAECggJHwAcAAkWAA==.',
['Të']='Tëmplýn:BAAALgAECgEJAQABLgAECggJHwAcAAkWAA==.',
Ul='Ulfrunn:BAAALgADCgYJBgAAAA==.Ultrachad:BAACLgAFFH8bAAIUAAYJNxizJwCPAQAUAAYJNxizJwCPAQAuAAQKfx4AAhQACAlNIwUUAAMDABQACAlNIwUUAAMDAAEuAAUUBwkOAAIAnBcA.',
Um='Umami:BAABLgAECn8gAAILAAYJ+RhzSgB7AQALAAYJ+RhzSgB7AQAAAA==.',
Un='Unggoy:BAACLgAFFH8kAAQbAAgJHR38AgAkAgAbAAgJ9Bv8AgAkAgAZAAQJyRTfDABRAQAaAAIJsRl8XwCtAAAuAAQKfygAAxsACQkhJrsBAKYDABsACQkhJrsBAKYDABoAAQnFJenZAG0AAAAA.Unhollowed:BAAALgAECgEJAQAAAA==.Unholywaters:BAAALgAECgIJBgAAAA==.',
Ur='Urianna:BAAALgAECgYJCwAAAA==.',
Va='Vaelthirion:BAABLgAECn8nAAIIAAgJYxYfSADrAQAIAAgJYxYfSADrAQAAAA==.Vahidamus:BAAALgAECggJCwAAAA==.Valkaryon:BAAALgAECgcJCgABLgAFFAIJAwARAAAAAA==.Valmirax:BAAALgADCggJEgAAAA==.Valton:BAABLgAECn9IAAIVAAcJjRE7gQBRAQAVAAcJjRE7gQBRAQAAAA==.',
Ve='Vegetation:BAAALgAECgQJBwAAAA==.Velenestus:BAAALgAECgMJBgAAAA==.Verses:BAAALgADCgEJAQAAAA==.',
Vi='Vizsla:BAAALgAECgEJAQAAAA==.',
Wa='Wackaman:BAABLgAECn8nAAIMAAkJvBybBwBxAgAMAAkJvBybBwBxAgAAAA==.Warpig:BAAALgAECgYJEQAAAA==.Wasps:BAAALgAECgYJEQAAAA==.',
We='Wegmaniac:BAAALgADCgYJCAAAAA==.Welastrexa:BAAALgADCgUJBQABLgAECgIJBgARAAAAAA==.',
Wi='Wickedclöwn:BAAALgADCgMJAwAAAA==.Winchester:BAAALgADCgIJAgAAAA==.Windhorn:BAAALgAECgYJDAAAAA==.Winds:BAABLgAECn8YAAINAAYJ/yBoFwAqAgANAAYJ/yBoFwAqAgAAAA==.',
Wn='Wntrizcoming:BAAALgADCgMJBQAAAA==.',
Wo='Wolfquota:BAACLgAFFH8QAAIJAAQJJx6fFgA6AQAJAAQJJx6fFgA6AQAuAAQKfx8AAwkACAlGIkkJAP4CAAkACAlGIkkJAP4CAB8ABAntE08eAOkAAAAA.Wolftime:BAAALgADCgUJBQAAAA==.Wombaa:BAACLgAFFH8TAAIUAAUJoiVBIACqAQAUAAUJoiVBIACqAQAuAAQKfxwAAhQACAleJGEKAEgDABQACAleJGEKAEgDAAAA.Woolybully:BAAALgAECgEJAQABLgAECgYJBwARAAAAAA==.',
Wr='Wrathbolt:BAAALgAECgEJAgABLgAFFAQJBQANAHoZAA==.Wrathmo:BAACLgAFFH8FAAINAAQJehnxDQA6AQANAAQJehnxDQA6AQAuAAQKfyUAAw0ACAljHBESABwCAA0ABwlpHhESABwCACgABwkdCtg7APsAAAAA.Wrathp:BAAALgAFFAMJAwABLgAFFAQJBQANAHoZAA==.Wrolie:BAAALgADCgMJAwAAAA==.',
['Wê']='Wêêdyys:BAAALgADCgMJBAAAAA==.',
Xy='Xyr:BAAALgAECgEJAQABLgAECgkJMAASADwUAA==.',
Ya='Yamiamigo:BAAALgAECgEJAQAAAA==.',
Yo='Yonah:BAAALgADCgYJBgAAAA==.Yougotsniped:BAAALgADCgEJAQAAAA==.',
Za='Zandalia:BAAALgAECgMJAwAAAA==.Zark:BAEALgAECgEJAQABLgAECgkJGQAXAHsWAA==.',
Ze='Zemphoths:BAAALgAECgcJCgAAAA==.',
Zo='Zoa:BAAALgADCgYJBgAAAA==.Zolton:BAAALgADCgMJAwAAAA==.Zornak:BAAALgAECgUJEwAAAA==.',
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
