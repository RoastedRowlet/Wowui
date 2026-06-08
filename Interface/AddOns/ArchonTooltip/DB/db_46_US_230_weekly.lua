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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Unknown-Unknown','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Elemental','Monk-Brewmaster','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Restoration','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Mage-Frost','Warlock-Destruction','DeathKnight-Blood','Warrior-Fury','Hunter-Survival','Priest-Shadow','Priest-Holy','Monk-Windwalker','Druid-Balance','Priest-Discipline','Druid-Guardian','Druid-Feral','Monk-Mistweaver','Warlock-Affliction','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=46,date='2026-06-07',data={Ab='Abaddon:BAABLgAECn8sAAMBAAgJmh6HBgAtAgABAAgJ6R2HBgAtAgACAAcJbRu/aACOAQAAAA==.Abessedge:BAAALgAECgUJBQAAAA==.',
Ac='Acidtears:BAAALgAECgEJAQAAAA==.Ackris:BAABLgAECn8uAAIDAAkJ/BwHCgAuAwADAAkJ/BwHCgAuAwAAAA==.Ackrisa:BAAALgAECgUJCAAAAA==.Acris:BAAALgAECgYJCwABLgAECgkJLgADAPwcAA==.',
Ae='Aedimus:BAAALgADCgcJCQAAAA==.',
Al='Aleathris:BAEALgADCgcJBwABLgAECgQJBAAEAAAAAA==.Alistan:BAAALgAECgEJAQAAAA==.Alka:BAAALgADCgEJAQAAAA==.Alor:BAAALgAECgIJBAABLgAECggJLQAFAK8QAA==.Alpyne:BAAALgAECgcJEgAAAA==.',
Am='Amaimon:BAABLgAECn8aAAMGAAgJDhV3UwCBAQAGAAgJDhV3UwCBAQAHAAEJawy4aAAvAAABLgAFFAgJHAAIACoTAA==.Amalthaea:BAAALgAECgcJEwABLgAECgkJLgAJAGMWAA==.Amnoon:BAABLgAECn80AAIKAAkJ+BfVEgByAgAKAAkJ+BfVEgByAgAAAA==.Amri:BAACLgAFFH8ZAAMLAAUJPhDqLgD8AAALAAUJPhDqLgD8AAAMAAEJYAJ/LQAlAAAuAAQKfx8AAwsACAlxFqAVAC0CAAsACAlxFqAVAC0CAAwABglADYYhANwAAAAA.',
An='Andarnáurram:BAAALgAECgIJAgAAAA==.Angelfox:BAAALgAECgQJAgAAAA==.',
Aq='Aquas:BAAALgAECgQJBwAAAA==.',
Ar='Ardrhys:BAAALgAECgcJDgAAAA==.Arthurcarrot:BAAALgAECgQJBwAAAA==.Artikin:BAAALgAECgkJCwABLgAFFAYJEgAHAJcVAA==.',
As='Assasinateu:BAAALgADCgMJAwAAAA==.Asûná:BAAALgAECgcJDwAAAA==.',
At='Atreus:BAABLgAECn8mAAMHAAkJ7Bw0DQBEAgAHAAkJ7Bw0DQBEAgAGAAEJVAtDEgEqAAAAAA==.Atzalan:BAABLgAECn8UAAINAAYJpwnpcwD7AAANAAYJpwnpcwD7AAAAAA==.',
Au='Automagic:BAAALgAECgEJAgAAAA==.',
Av='Avondwella:BAABLgAECn8rAAMOAAkJZw9ZHABJAQAOAAkJZw9ZHABJAQAPAAEJ+wnERAAvAAAAAA==.',
Az='Azrikam:BAAALgAECgYJCAAAAA==.',
Ba='Baku:BAAALgAECgYJBgABLgAFFAYJEgAHAJcVAA==.Baldyguy:BAAALgADCgcJCgAAAA==.Balm:BAABLgAECn8xAAINAAkJCBqsIAA5AgANAAkJCBqsIAA5AgAAAA==.Balton:BAAALgAECgIJAwAAAA==.Barbsimpsonn:BAAALgAECgEJAQAAAA==.Bashalot:BAAALgAECgUJBgAAAA==.',
Be='Beastcloud:BAAALgAECgIJAgABLgAECgkJJgAHAOwcAA==.Bermin:BAAALgADCgUJAwAAAA==.',
Bi='Biblepimp:BAAALgAFFAEJAQAAAA==.Bigwilliam:BAAALgADCgEJAQAAAA==.',
Bl='Blackmarker:BAABLgAECn8cAAICAAgJ/BSqWQCzAQACAAgJ/BSqWQCzAQAAAA==.',
Bm='Bmo:BAABLgAECn8VAAIQAAcJZSB1SAAJAgAQAAcJZSB1SAAJAgAAAA==.',
Bo='Bodyguardwyn:BAAALgAECgEJAQAAAA==.Bogle:BAACLgAFFH8FAAMQAAIJOQxzmgBwAAAQAAIJUAVzmgBwAAARAAIJOQwOCAA2AAAuAAQKfy8AAxEACQnYI3ACAAMDABEACQnYI3ACAAMDABAAAwnyFk7ZANsAAAAA.Bonedmuch:BAAALgAECgcJDQABLgAECgkJLgAJAGMWAA==.Bow:BAAALgAECgIJAwAAAA==.',
Br='Brasi:BAAALgAECgIJAgAAAA==.Bratton:BAABLgAECn8aAAISAAcJ6wbQEgDTAAASAAcJ6wbQEgDTAAAAAA==.Breadria:BAAALgAECgEJAQABLgAFFAMJBwATAH0FAA==.Bremitin:BAAALgADCggJCAABLgAECgkJMwARALcPAA==.Bremitus:BAAALgADCgkJCQABLgAECgkJMwARALcPAA==.Brewcrew:BAAALgAECgkJBwAAAA==.Brewey:BAAALgAFFAEJAQAAAA==.Brewmongster:BAAALgAECgQJBQAAAA==.Brimscythe:BAABLgAECn8bAAIGAAgJ5B+wNwAXAgAGAAgJ5B+wNwAXAgAAAA==.Brud:BAAALgAECgMJCwAAAA==.Brunstan:BAACLgAFFH8TAAIUAAUJfh+1DwBVAQAUAAUJfh+1DwBVAQAuAAQKfxkAAhQACQnjIH4CAMACABQACQnjIH4CAMACAAAA.',
Bu='Bubbastump:BAAALgAECgQJBAAAAA==.',
By='Byakugan:BAACLgAFFH8cAAMIAAgJKhN1BQCDAQAIAAYJRxN1BQCDAQAFAAMJEglDRQDFAAAuAAQKfyAABAgACQktH5oPAK8CAAgACQktH5oPAK8CABUAAQm+F78pAEEAAAUAAQkHAQWpACUAAAAA.',
['Bø']='Bønitalèè:BAABLgAECn8jAAIWAAgJiQkkjQBYAQAWAAgJiQkkjQBYAQAAAA==.',
Ca='Cain:BAAALgADCgkJDwAAAA==.Calvisi:BAAALgAECgcJDgAAAA==.Calvisichaos:BAABLgAECn88AAIXAAkJhBdFBAAyAgAXAAkJhBdFBAAyAgAAAA==.Cantero:BAAALgADCgUJBQAAAA==.Canthen:BAAALgAECggJDwAAAA==.Carcarnisa:BAAALgAECgQJBgAAAA==.Carm:BAAALgAECgQJBAAAAA==.',
Ce='Cenobia:BAAALgADCgUJCQAAAA==.',
Ch='Chaire:BAAALgADCgcJBgAAAA==.Chrysophylax:BAAALgAECgYJBgAAAA==.',
Co='Conky:BAAALgAECgMJBgAAAA==.Corndog:BAAALgADCgEJAQAAAA==.Cornix:BAAALgADCgEJAQAAAA==.Cosmicspark:BAAALgAECgYJEgAAAA==.',
Cr='Crentist:BAAALgAECgEJAQAAAA==.Critoliz:BAAALgAFFAIJAQAAAA==.Cropala:BAABLgAECn8oAAIQAAkJCBWTOgAPAgAQAAkJCBWTOgAPAgAAAA==.Cruelcodex:BAAALgAECgEJAQAAAA==.',
['Cà']='Càtfish:BAAALgADCgEJAQAAAA==.',
Da='Daca:BAAALgADCgMJAwAAAA==.Darkrequiem:BAAALgADCgkJCwAAAA==.Darkwingduck:BAAALgAECgQJBQAAAA==.Dave:BAAALgADCgQJBAAAAA==.Davros:BAAALgAECgMJCAAAAA==.',
De='Decapitator:BAAALgAECgMJAwAAAA==.Dednburied:BAAALgAECgIJAgAAAA==.Deleto:BAABLgAECn8rAAMBAAgJDRUmDQCWAQABAAgJ2BEmDQCWAQACAAYJYBiQjwA/AQAAAA==.Dellandre:BAABLgAECn8aAAIYAAgJQQsYJwARAQAYAAgJQQsYJwARAQABLgAECgkJNAARANgKAA==.Delta:BAABLgAECn8XAAIGAAgJ+QfNgQARAQAGAAgJ+QfNgQARAQAAAA==.Delti:BAAALgAECgUJBgABLgAECgkJHwAGAFcWAA==.Demondozer:BAAALgAECgMJBAABLgAECgUJCQAEAAAAAA==.Demony:BAAALgAECgEJAQABLgAFFAEJAQAEAAAAAA==.Denard:BAAALgAECgUJBgAAAA==.',
Di='Diabolist:BAACLgAFFH8FAAIDAAIJ+gb0oQCAAAADAAIJ+gb0oQCAAAAuAAQKfxgAAgMACQlgCMVlAG0BAAMACQlgCMVlAG0BAAAA.Digichowder:BAACLgAFFH8MAAIZAAMJPSRdGwA3AQAZAAMJPSRdGwA3AQAuAAQKfyYAAw8ACQmxI9EDAOECAA8ACAkOIdEDAOECABkABQmNHkY3AGQBAAAA.Dirtygiri:BAAALgADCgEJAgAAAA==.',
Do='Doktaga:BAAALgAECgYJDgAAAA==.',
Dr='Draex:BAAALgADCgEJAQAAAA==.Dragonzord:BAAALgADCgEJAQAAAA==.Drbubbles:BAAALgADCgYJCAABLgAECgQJCQAEAAAAAA==.Drredd:BAAALgAECgQJBAAAAA==.',
['Dä']='Därkrävèn:BAAALgAECgYJDAAAAA==.',
Ea='Eama:BAAALgADCgIJAwAAAA==.',
Ed='Edin:BAAALgAECgcJBwABLgAFFAUJGQALAD4QAA==.',
Eg='Eggfield:BAAALgAECgUJBgAAAA==.',
El='Eladora:BAAALgADCgEJAQAAAA==.Eldarr:BAABLgAECn83AAMXAAkJaCErAQDiAgAXAAkJaCErAQDiAgADAAUJ+hFYiAAkAQAAAA==.Eldhe:BAAALgAECgYJDwAAAA==.Eleos:BAAALgADCgMJBgAAAA==.Elistrae:BAABLgAECn8eAAMaAAgJKRemIACUAQAUAAgJKRc0MwCgAQAaAAgJkwymIACUAQAAAA==.',
Em='Emorri:BAAALgAECgYJBgAAAA==.',
En='Enazen:BAABLgAECn8fAAIMAAkJWRo4BQC/AgAMAAkJWRo4BQC/AgAAAA==.Endlol:BAABLgAECn8vAAMbAAkJFyH4BwDLAgAbAAkJFyH4BwDLAgAcAAEJUh/zXgBTAAABLgAFFAIJAwAEAAAAAA==.',
Er='Eredaria:BAAALgAFFAEJAQAAAA==.Ereshkigal:BAAALgADCgYJCwAAAA==.Ergo:BAACLgAFFH8ZAAIWAAgJ7RCiFwAZAgAWAAgJ7RCiFwAZAgAuAAQKfyYAAhYACQmuIhsjAOYCABYACQmuIhsjAOYCAAAA.Eronel:BAABLgAECn8eAAICAAcJ7Rp2ZACYAQACAAcJ7Rp2ZACYAQAAAA==.',
Es='Esv:BAABLgAFFH8HAAIOAAMJ3wfAHwCKAAAOAAMJ3wfAHwCKAAABLgAFFAQJGQAWACgUAA==.',
Ex='Excido:BAAALgAECgEJAgAAAA==.Exodiagold:BAAALgAECgEJAQAAAA==.',
Fa='Fadedharanir:BAAALgAECgIJAwAAAA==.Fadedheart:BAAALgAECgQJBwABLgAECgkJNAACAPIfAA==.Fadedmystic:BAAALgAECgQJBAAAAA==.Fadednight:BAABLgAECn80AAMCAAkJ8h+uFgC4AgACAAkJ8h+uFgC4AgAYAAEJ1QF5aAARAAAAAA==.Faeyir:BAACLgAFFH8PAAIWAAQJKQzPYQAeAQAWAAQJKQzPYQAeAQAuAAQKfyIAAhYACQnDHT9QAEYCABYACQnDHT9QAEYCAAAA.Fallingmoon:BAABLgAECn8nAAMTAAkJqCDYDQDaAgATAAkJqCDYDQDaAgAUAAEJKRDmigAwAAAAAA==.Fangrage:BAAALgAECgYJBAAAAA==.Fatherlode:BAACLgAFFH8KAAIWAAMJwBhZeQDgAAAWAAMJwBhZeQDgAAAuAAQKfysAAhYACQmUIW0bALACABYACQmUIW0bALACAAAA.',
Fe='Feltpen:BAAALgAECgUJBQAAAA==.Femcelibate:BAAALgADCgcJCAAAAA==.Fentenjoyer:BAAALgAECgcJDwAAAA==.Fernfondler:BAAALgAFFAIJAwAAAA==.',
Fl='Flashylights:BAAALgADCgYJBgAAAA==.',
Fo='Fontane:BAAALgADCgYJBwAAAA==.Forcebolt:BAAALgADCgMJAwAAAA==.',
Fr='Fredgoffin:BAAALgAECgIJAgAAAA==.Freecookies:BAAALgAECgYJCQAAAA==.Frostybop:BAAALgAECgMJBAABLgAECgIJAgAEAAAAAA==.Frostybreath:BAAALgAECgIJAgAAAA==.Frostybrews:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.Frostydh:BAAALgAECgMJAwABLgAECgIJAgAEAAAAAA==.Frostytotems:BAAALgAECgQJBgAAAA==.Fróstblight:BAAALgAECgkJCAAAAA==.',
Fu='Furryiosa:BAAALgADCgYJBgAAAA==.',
Ga='Gauntodimm:BAAALgAECgYJCgAAAA==.',
Gi='Gilberticus:BAAALgAECgYJEwABLgAECgkJSgAdAMUiAA==.Gishmou:BAABLgAECn8fAAIFAAkJwRgtJAApAgAFAAkJwRgtJAApAgAAAA==.',
Go='Goldblade:BAABLgAECn8gAAIQAAgJWhc/TwDQAQAQAAgJWhc/TwDQAQAAAA==.',
Gr='Grayhair:BAAALgAECgQJCAAAAA==.Greyoll:BAAALgAECgYJCAAAAA==.Grimling:BAAALgAFFAEJAQABLgAFFAYJEgAHAJcVAA==.Grindlewald:BAAALgAECgIJAgAAAA==.',
Gu='Gutted:BAACLgAFFH8gAAMYAAgJCyNuAgCIAgAYAAgJCyNuAgCIAgACAAEJxQzaAAFAAAAuAAQKfx0AAhgACQkZJr0BAGcDABgACQkZJr0BAGcDAAAA.',
['Gä']='Gärin:BAAALgADCggJFAAAAA==.',
Ha='Hanna:BAAALgAFFAEJAQABLgAFFAgJIAAYAAsjAA==.Harleyswar:BAAALgADCgEJAQAAAA==.',
He='Hellmaw:BAAALgAECgYJCwAAAA==.',
Hi='Highly:BAAALgADCgcJCwAAAA==.',
Ho='Holianna:BAAALgAECgIJAgAAAA==.Hollowheart:BAABLgAECn8vAAIFAAkJjhg9IQA8AgAFAAkJjhg9IQA8AgAAAA==.Holycourtney:BAAALgADCgkJEQAAAA==.Holyknight:BAAALgADCgEJAQAAAA==.Hotsausage:BAAALgAECgMJAwAAAA==.Hoved:BAAALgADCgEJAQAAAA==.',
Hu='Huang:BAAALgAECgMJAwAAAA==.',
Hy='Hylanna:BAAALgAECgYJCgAAAA==.Hyorinmaru:BAAALgAFFAEJAgAAAA==.',
['Hó']='Hónor:BAAALgADCgMJAwABLgAECgkJMwARALcPAA==.',
Ic='Ici:BAABLgAECn8zAAMQAAkJAAgBgwBfAQAQAAkJAAgBgwBfAQAKAAQJuA4tWgDDAAAAAA==.',
If='Iffybacon:BAAALgAECgIJAgABLgAECgQJCwAEAAAAAA==.',
Ik='Ikilledkeny:BAAALgAFFAIJAQAAAA==.',
Im='Imlerith:BAAALgADCgQJBgAAAA==.',
In='Intensifies:BAAALgAECgcJEgAAAA==.',
Ip='Ippo:BAAALgADCgEJAQAAAA==.',
Is='Isabellà:BAAALgAECggJDAABLgAECgkJJwAeAL4MAA==.Iskothar:BAABLgAECn8xAAIRAAkJQSFvAgADAwARAAkJQSFvAgADAwAAAA==.',
Iv='Ivarboneless:BAABLgAECn8UAAIKAAYJgSEDGQA0AgAKAAYJgSEDGQA0AgAAAA==.',
Ja='Jackz:BAAALgAECgkJCQAAAA==.Jackzlock:BAAALgAECgkJAQAAAA==.Jakethemage:BAAALgADCgUJCAAAAA==.Jankball:BAAALgAFFAIJAQAAAA==.Jayreezy:BAAALgAECgMJAwAAAA==.',
Je='Jefftrep:BAAALgAECgQJAwAAAA==.Jerihatrix:BAAALgAECgEJAQAAAA==.',
Ji='Jimmylahey:BAAALgAECgMJAwAAAA==.',
Jo='Jonah:BAAALgADCgEJAQAAAA==.',
Ka='Kaina:BAAALgADCgYJCQAAAA==.Kakidruid:BAAALgAECgIJAwAAAA==.Kalfu:BAABLgAECn8UAAMbAAkJygzvJwCHAQAbAAkJygzvJwCHAQAfAAgJFwk0LgBeAQAAAA==.',
Ke='Ketesh:BAABLgAECn88AAIgAAkJzSAtAwDvAgAgAAkJzSAtAwDvAgABLgAFFAUJGQALAD4QAA==.',
Ki='Kilorean:BAAALgAECgcJCAAAAA==.Kirae:BAAALgADCgkJGQABLgAECgkJMQARAEEhAA==.',
Kl='Kleanse:BAAALgAFFAIJAQAAAA==.',
Kn='Knastey:BAABLgAECn8VAAQeAAYJ4BfMMwA9AQAeAAYJ4BfMMwA9AQANAAYJZAqbcQABAQAhAAEJWxKCMgA3AAAAAA==.Knasty:BAAALgADCgEJAQAAAA==.',
Ko='Kodera:BAABLgAECn8gAAILAAYJQQWlYgClAAALAAYJQQWlYgClAAAAAA==.',
Kr='Krej:BAABLgAECn8XAAIYAAkJMBwSDgAfAgAYAAkJMBwSDgAfAgABLgAFFAYJEgAHAJcVAA==.Krisskringle:BAAALgAECgMJBgAAAA==.',
Ku='Kuromori:BAAALgADCgYJBgAAAA==.',
Ky='Kyronix:BAAALgAECgMJBwAAAA==.',
['Kê']='Kênpachi:BAAALgAECgYJDgAAAA==.',
La='Landrey:BAAALgADCgkJCAAAAA==.Langarde:BAABLgAECn8fAAIOAAkJCxCWFQCQAQAOAAkJCxCWFQCQAQAAAA==.Laoghaire:BAABLgAECn8YAAIHAAcJ+AM8PgCtAAAHAAcJ+AM8PgCtAAAAAA==.',
Le='Leonz:BAACLgAFFH8bAAIZAAgJDhtOAgBTAgAZAAgJDhtOAgBTAgAuAAQKfy4AAhkACQmaJIkEABcDABkACQmaJIkEABcDAAAA.Leonzs:BAAALgAECggJEAAAAA==.Letharanos:BAEBLgAECn8nAAMCAAkJdBkDQAD9AQACAAkJdBkDQAD9AQAYAAEJew4NXAApAAAAAA==.',
Li='Liraffemynn:BAACLgAFFH8TAAIiAAUJiBezGwBtAQAiAAUJiBezGwBtAQAuAAQKfz4AAiIACQmOI1sDAHwDACIACQmOI1sDAHwDAAAA.Liralynn:BAAALgADCgUJBQAAAA==.',
Lk='Lkynyx:BAAALgADCgYJAQAAAA==.',
Lo='Lonranir:BAAALgAECgYJCwAAAA==.Lostinlight:BAAALgAECgYJBgAAAA==.',
Lu='Lucii:BAAALgADCgEJAQABLgAFFAgJIAAYAAsjAA==.Luckylucy:BAABLgAECn8XAAIcAAYJhhaBLABbAQAcAAYJhhaBLABbAQAAAA==.',
Ma='Madarauchiha:BAABLgAECn8ZAAICAAYJpBpwggB+AQACAAYJpBpwggB+AQAAAA==.Magus:BAAALgADCgkJEQABLgAECgMJCAAEAAAAAA==.Maldran:BAABLgAECn8jAAIFAAcJjh1mKAARAgAFAAcJjh1mKAARAgAAAA==.Maling:BAAALgAECgEJAQAAAA==.Manderpants:BAABLgAECn8fAAITAAcJCArWewA8AQATAAcJCArWewA8AQAAAA==.Marien:BAABLgAECn8fAAIYAAkJHBl5DAA7AgAYAAkJHBl5DAA7AgAAAA==.Marty:BAAALgAECgIJAwAAAA==.Maxus:BAAALgADCgUJBQAAAA==.',
Mb='Mbbin:BAACLgAFFH8LAAIWAAMJFyURTABDAQAWAAMJFyURTABDAQAuAAQKfygAAhYACQmmIZgdAKQCABYACQmmIZgdAKQCAAAA.',
Me='Mehuman:BAABLgAECn8VAAIQAAYJ6Q07uwAEAQAQAAYJ6Q07uwAEAQAAAA==.Mehumanhuntr:BAAALgAECgUJBgAAAA==.Mehumanlock:BAABLgAECn8jAAIXAAkJ+xEaCQCpAQAXAAkJ+xEaCQCpAQAAAA==.Merlinn:BAAALgADCgkJCwAAAA==.Merran:BAAALgADCgEJAQAAAA==.Metal:BAAALgADCgQJBAAAAA==.Meworgendk:BAAALgAECgYJDgAAAA==.',
Mh='Mhoo:BAAALgADCgcJBwAAAA==.',
Mi='Miriym:BAAALgADCgEJAQAAAA==.Miräj:BAAALgAECgcJDAAAAA==.Mistyblue:BAAALgADCgEJAQAAAA==.Miya:BAAALgADCgcJDQAAAA==.',
Mo='Moonscale:BAAALgAECgMJBAAAAA==.Mordaci:BAAALgADCgQJBQABLgAFFAEJAQAEAAAAAA==.Mordekrieg:BAAALgAFFAMJBAAAAA==.Mortstan:BAAALgAECgcJDQAAAA==.',
My='Myash:BAAALgAECgcJBgAAAA==.',
['Må']='Månni:BAAALgADCgYJBwAAAA==.',
['Mé']='Mélusine:BAAALgADCgEJAQAAAA==.',
Na='Nailia:BAAALgAECgUJCQAAAA==.Nailz:BAABLgAECn8fAAIGAAkJVxbUSwCXAQAGAAkJVxbUSwCXAQAAAA==.Nakama:BAAALgADCgYJBgABLgAECggJLQAFAK8QAA==.Nardog:BAAALgAECgEJAQAAAA==.Narie:BAAALgAECggJCQAAAA==.Nasaug:BAAALgAECgUJCwABLgAECgkJMwARALcPAA==.',
Ne='Ned:BAAALgAECgEJAQAAAA==.Neuse:BAAALgAECggJEwAAAA==.',
Ni='Nightlion:BAABLgAECn8YAAIgAAYJiw+3LgDgAAAgAAYJiw+3LgDgAAAAAA==.Nillius:BAAALgADCgIJAgAAAA==.Nisu:BAAALgAECgEJAQAAAA==.',
No='Noahdh:BAAALgAECgMJAwABLgAFFAgJHQADAJMXAA==.Noahpriest:BAAALgAECgMJAwABLgAFFAgJHQADAJMXAA==.Noahvoker:BAAALgAECggJEQABLgAFFAgJHQADAJMXAA==.Noahwarlock:BAACLgAFFH8dAAQDAAgJkxdcHADBAQADAAYJnxxcHADBAQAXAAMJXxHLCQDtAAAjAAEJkSNAHQBSAAAuAAQKfzEABAMACQmFJGUEAEUDAAMACAlsJGUEAEUDABcABAl0IkEaAHsBACMAAwmsI4IWAM0AAAAA.Nonsensical:BAAALgADCgUJBQABLgAECgYJIgAiAEYiAA==.Nook:BAAALgADCgUJBgAAAA==.Nowere:BAAALgADCgcJBwAAAA==.Noxander:BAAALgAECgEJAQAAAA==.',
Ny='Nym:BAAALgAECgkJEQAAAA==.',
['Nâ']='Nârenth:BAAALgADCgMJAwAAAA==.',
Oa='Oaths:BAAALgAECgcJEQAAAA==.',
Oh='Ohmylantä:BAABLgAECn8dAAIWAAgJPg0HhABqAQAWAAgJPg0HhABqAQAAAA==.Ohmylantå:BAAALgADCgUJCAAAAA==.',
On='Ondeane:BAAALgADCgEJAQAAAA==.Onumae:BAABLgAECn8XAAIQAAkJcRrOLgA7AgAQAAkJcRrOLgA7AgAAAA==.',
Op='Oprime:BAAALgADCgMJAwAAAA==.',
Or='Orator:BAAALgAFFAIJAQAAAA==.Orbeck:BAAALgAECggJCAABLgAFFAgJHQAJAIocAA==.Ormond:BAABLgAECn8cAAMKAAcJbRQlKQC7AQAKAAcJbRQlKQC7AQAQAAUJPAWzEAGXAAAAAA==.Orochinchin:BAAALgAECgUJBQABLgAFFAgJIAAYAAsjAA==.',
Os='Oscarmike:BAAALgADCgcJDQAAAA==.',
Oz='Ozlon:BAAALgAECgcJEwAAAA==.',
['Oâ']='Oâth:BAABLgAECn8nAAMkAAkJdgyTDwBGAQAkAAkJdgyTDwBGAQAHAAMJRga4XgBCAAAAAA==.',
Pa='Pachane:BAAALgAECgQJCwAAAA==.Paldozer:BAAALgAECgUJCQABLgAECgUJCQAEAAAAAA==.Pallywacker:BAABLgAECn8xAAIRAAgJ2hKXEwCHAQARAAgJ2hKXEwCHAQAAAA==.Pankins:BAAALgAECgMJAwAAAA==.Panzerkan:BAAALgAECgEJAQAAAA==.Panzerkìn:BAAALgAECgcJCAAAAA==.',
Pe='Percymorris:BAAALgADCgYJBwAAAA==.Peythilly:BAAALgAECgQJBAAAAA==.',
Pi='Pigishdog:BAABLgAECn9RAAMDAAkJ/hw+FQCgAgADAAkJ/hw+FQCgAgAXAAEJ1RGAOgA2AAAAAA==.Pikon:BAAALgADCgkJDQAAAA==.',
Po='Pokeabear:BAAALgAECgYJEAABLgAECgcJEAAEAAAAAA==.Pokethedruid:BAAALgAECgEJAQABLgAECgEJBwAEAAAAAA==.Pokethemonk:BAAALgAECgEJBwAAAA==.Poshingtang:BAABLgAECn8pAAQFAAkJqQycQQCbAQAFAAkJqQycQQCbAQAIAAgJHhG8NgB4AQAVAAMJSwP+JQB3AAAAAA==.',
Pu='Pulsar:BAAALgADCgkJDwAAAA==.Punchies:BAAALgADCggJDQAAAA==.',
Qu='Quatrain:BAABLgAECn8tAAMFAAgJrxCJWABHAQAFAAgJrxCJWABHAQAIAAIJTREAfgBmAAAAAA==.Quintessence:BAAALgAECgMJAwAAAA==.',
Ra='Rabidbutt:BAAALgAFFAIJAwABLgAFFAYJFwAMAA0jAA==.Ragerunner:BAAALgADCgkJEwAAAA==.Rakarg:BAABLgAECn8ZAAICAAUJDBj8xQDtAAACAAUJDBj8xQDtAAAAAA==.Ravenus:BAAALgAECgEJAQAAAA==.',
Re='React:BAAALgAECggJCAABLgAFFAIJAwAEAAAAAA==.Redemptor:BAAALgAECgUJBQAAAA==.Refund:BAAALgAECgEJAQAAAA==.Regalbacon:BAAALgAECgMJAwAAAA==.Reygina:BAABLgAECn8ZAAIKAAYJygL6XAC3AAAKAAYJygL6XAC3AAAAAA==.',
Ri='Rickÿ:BAAALgAECgEJAQAAAA==.Rikku:BAAALgAECggJCAABLgAFFAgJHAAIACoTAA==.Ripndip:BAAALgAFFAIJAQAAAA==.Riprock:BAAALgAECgIJAQABLgAFFAIJAQAEAAAAAA==.Rixas:BAAALgAECgEJAQABLgAECgkJLgADAPwcAA==.',
Rn='Rn:BAACLgAFFH8FAAIPAAQJShgGFwAXAQAPAAQJShgGFwAXAQAuAAQKfx4AAw8ACQklIkEBAEYDAA8ACQkIIkEBAEYDABkABwkvIyQpABcCAAEuAAUUCAkiAA8AgyQA.',
Ro='Rodeo:BAAALgAECgMJAwAAAA==.Roguehiro:BAABLgAECn8oAAIRAAgJxSGMBQCMAgARAAgJxSGMBQCMAgAAAA==.Rooter:BAACLgAFFH8XAAIMAAYJDSPbBQBJAgAMAAYJDSPbBQBJAgAuAAQKfzsAAwwACAmPJbsDAP0CAAwACAmPJbsDAP0CAAsABwnsGRgkALMBAAAA.Rosalynñ:BAABLgAECn8pAAIXAAgJMgoLEwAPAQAXAAgJMgoLEwAPAQAAAA==.',
Ru='Ruikhai:BAAALgADCgMJBQABLgADCgkJBwAEAAAAAA==.Ruto:BAAALgAECgEJAQABLgAFFAIJAQAEAAAAAA==.',
Sa='Saelis:BAACLgAFFH8VAAINAAUJnhbRHQBeAQANAAUJnhbRHQBeAQAuAAQKfx8AAw0ACQnfIFILAAEDAA0ACQnfIFILAAEDACEABgnwGdcSAH8BAAAA.Salen:BAAALgADCgQJAwAAAA==.Samshara:BAAALgADCgcJDAABLgAECgkJQgAaAH4dAA==.Saptapper:BAAALgAECgIJAgAAAA==.Saracenio:BAAALgADCgEJAQAAAA==.',
Sc='Schnem:BAAALgAECggJCgAAAA==.Scrawni:BAAALgAECgcJCAABLgAFFAYJEgAHAJcVAA==.Scrounge:BAAALgAFFAEJAQABLgAFFAIJBQADAPoGAA==.',
Se='Securìty:BAAALgAECgQJBQAAAA==.Selyane:BAAALgADCgkJCQAAAA==.Senia:BAAALgAECgkJEQAAAA==.Seong:BAACLgAFFH8dAAIJAAgJihxGBAA9AgAJAAgJihxGBAA9AgAuAAQKfyEAAgkACQmAIgUFADkDAAkACQmAIgUFADkDAAAA.Seongdh:BAAALgAECggJDQABLgAFFAgJHQAJAIocAA==.Seongwar:BAAALgAECgMJAwAAAA==.Seraphinà:BAAALgAECgYJDAABLgAECgkJJwAeAL4MAA==.',
Sh='Shadowdooms:BAABLgAECn8WAAMCAAgJFBkfYQDQAQACAAgJFBkfYQDQAQABAAEJSxf2FABFAAAAAA==.Shadowfur:BAAALgAECggJCAABLgAECgkJPAAKAN8eAA==.Shamynna:BAAALgAECgMJBAAAAA==.Sharreth:BAAALgAECgIJAgAAAA==.Shii:BAAALgADCgUJBQAAAA==.Shimera:BAABLgAECn8yAAITAAkJNhNVOQDwAQATAAkJNhNVOQDwAQAAAA==.Shish:BAAALgAECggJCwAAAA==.Shizukura:BAAALgADCgEJAQAAAA==.Shockawar:BAACLgAFFH8WAAIZAAUJeRwxAwDEAQAZAAUJeRwxAwDEAQAuAAQKfxkAAhkACQmrHmYYAIgCABkACQmrHmYYAIgCAAAA.Shooter:BAAALgADCgIJAgAAAA==.Shootrmcgavn:BAACLgAFFH8eAAQTAAYJ8yJ6HAB8AQATAAUJrx96HAB8AQAaAAQJRSGWCgBkAQAUAAQJNiDGEAAqAQAuAAQKfxsABBMACAk8IdMVAIkCABMABwnxIdMVAIkCABQABwlKIcoaAFMCABoAAwm3ITswACMBAAAA.Shu:BAAALgAFFAIJAgAAAA==.Shuletaa:BAAALgAECgIJBAAAAA==.Shïsh:BAAALgADCgcJBwABLgAECggJCwAEAAAAAA==.',
Si='Silverwolf:BAAALgADCgEJAQAAAA==.Sinestra:BAAALgAECgEJAQAAAA==.',
Sk='Skibidi:BAAALgAECgcJBwABLgAFFAMJEAAWABcfAA==.',
Sl='Slagscar:BAAALgAFFAIJAQAAAA==.Slaughterhse:BAABLgAECn8XAAIWAAYJ5gOM8QC7AAAWAAYJ5gOM8QC7AAAAAA==.Slootar:BAABLgAECn8UAAQNAAcJ5xuIJAAoAgANAAcJ5xuIJAAoAgAeAAIJuxBfbABuAAAhAAIJMAbzTwAsAAAAAA==.Slugs:BAAALgAECgUJCAAAAA==.',
Sn='Snqwflake:BAABLgAECn8VAAIiAAgJ7xb8FQAUAgAiAAgJ7xb8FQAUAgAAAA==.',
So='Solareth:BAAALgAECgEJAgAAAA==.Somebeotch:BAAALgADCgYJBgAAAA==.Somerled:BAABLgAECn9CAAIaAAkJfh3VBwCeAgAaAAkJfh3VBwCeAgAAAA==.',
Sp='Spyroid:BAAALgAECgUJAQAAAA==.',
St='Static:BAAALgADCgcJBwABLgAECgYJCgAEAAAAAA==.',
Su='Sunstrike:BAAALgAECgEJAgAAAA==.',
Sy='Sylvanna:BAAALgADCgQJBAAAAA==.',
Ta='Tabul:BAAALgADCgUJBAAAAA==.Takka:BAABLgAECn8aAAIFAAgJHR2QFgCKAgAFAAgJHR2QFgCKAgAAAA==.Talden:BAABLgAECn9FAAMQAAkJMhxJHQCNAgAQAAkJMhxJHQCNAgARAAMJzRAQQwBMAAAAAA==.Talkamar:BAABLgAECn8iAAIdAAkJ6RAYHwCpAQAdAAkJ6RAYHwCpAQAAAA==.Taylorswift:BAABLgAECn83AAIWAAkJ8xgDKgBsAgAWAAkJ8xgDKgBsAgAAAA==.Tazzaar:BAAALgAECgMJAwAAAA==.',
Th='Thaelios:BAAALgADCgEJAQAAAA==.Thekourge:BAABLgAECn80AAIRAAkJ2AryGQA/AQARAAkJ2AryGQA/AQAAAA==.Thenard:BAABLgAECn8jAAITAAgJPBOQUACmAQATAAgJPBOQUACmAQAAAA==.Thukunaenhan:BAAALgAECgQJBAABLgAFFAMJEAAWABcfAA==.Thukunamage:BAACLgAFFH8QAAIWAAMJFx+0aAAOAQAWAAMJFx+0aAAOAQAuAAQKfyoAAhYACQmyIEcfAJwCABYACQmyIEcfAJwCAAAA.',
Ti='Tibarius:BAAALgADCgkJEgAAAA==.Tili:BAAALgADCgkJDAAAAA==.Tinaraeda:BAAALgAECgMJAwAAAA==.',
To='Tomislav:BAABLgAECn8eAAQDAAkJrxLtTwCmAQADAAcJzRLtTwCmAQAXAAMJRBVMTwCAAAAjAAEJlA6wOAA4AAAAAA==.Tomuchmakeup:BAAALgAECgEJAQAAAA==.Touritos:BAABLgAECn8eAAIIAAkJdRFnKACeAQAIAAkJdRFnKACeAQAAAA==.',
Tr='Trimblestein:BAAALgAECgMJBAAAAA==.Troyka:BAAALgAECgEJAQAAAA==.Truefitt:BAAALgAECgYJEwAAAA==.',
Tu='Tulikettwo:BAAALgAECgEJAQAAAA==.Tulirenpo:BAAALgAECgUJBQAAAA==.Tunk:BAAALgAFFAIJAQAAAA==.Tuskal:BAAALgAECgIJAwAAAA==.',
Tw='Twogora:BAAALgAECgYJCQAAAA==.Twohoofy:BAAALgADCgcJBgAAAA==.',
Ty='Tydes:BAABLgAECn8bAAMlAAgJ6RbMEwB4AgAlAAgJ6RbMEwB4AgAmAAEJtgtBHQBBAAAAAA==.Tydru:BAAALgAFFAIJAQAAAA==.Tyler:BAACLgAFFH8LAAIGAAQJfhXYDwBPAQAGAAQJfhXYDwBPAQAuAAQKfxsAAgYACAkOHTgcAKkCAAYACAkOHTgcAKkCAAAA.Tystin:BAAALgADCgQJBQABLgADCgkJBwAEAAAAAA==.',
Ud='Uddermilk:BAABLgAECn8UAAIeAAQJrQqlVgCpAAAeAAQJrQqlVgCpAAAAAA==.',
Um='Umariel:BAAALgAFFAIJAQAAAA==.',
Va='Valina:BAAALgADCgIJAgAAAA==.Valissar:BAAALgAECgMJBgAAAA==.Valkyrja:BAAALgAECgEJAQAAAA==.Valr:BAABLgAECn8zAAIRAAkJtw/vFQBqAQARAAkJtw/vFQBqAQAAAA==.Vancliffe:BAAALgAECgQJBAABLgAFFAYJEgAHAJcVAA==.Vandreu:BAAALgADCgUJBQAAAA==.',
Ve='Verpally:BAAALgADCgMJAwAAAA==.',
Vi='Viparia:BAAALgAECgkJAgAAAA==.Virulent:BAAALgAECgMJAwAAAA==.',
Vo='Voloaura:BAAALgADCgMJAwAAAA==.',
Vs='Vse:BAACLgAFFH8ZAAIWAAQJKBReUAA8AQAWAAQJKBReUAA8AQAuAAQKfy4AAhYACAl8G/dEAAcCABYACAl8G/dEAAcCAAAA.Vsesosorry:BAABLgAFFH8SAAIFAAQJZxS/MAAKAQAFAAQJZxS/MAAKAQABLgAFFAQJGQAWACgUAA==.Vsè:BAAALgADCgUJBQABLgAFFAQJGQAWACgUAA==.',
Vy='Vyke:BAAALgAECgkJEQABLgAFFAgJHQAJAIocAA==.',
['Ví']='Ví:BAAALgAECgYJBgAAAA==.',
Wa='Wammo:BAAALgAECgYJCgAAAA==.Waq:BAAALgADCgMJAwAAAA==.Wardozer:BAAALgAECgUJCQAAAA==.Warlockedin:BAAALgAECgYJDQAAAA==.',
We='Weierstrass:BAAALgAFFAEJAQABLgAFFAgJIAAYAAsjAA==.',
Wo='Worgenkrantz:BAABLgAECn8nAAMeAAkJvgz4JwCEAQAeAAkJvgz4JwCEAQANAAcJeAJQkgCrAAAAAA==.',
Wr='Wrathlor:BAAALgADCgcJBQAAAA==.Wrenlyn:BAACLgAFFH8SAAMHAAYJlxXBDwAVAQAHAAUJ5RXBDwAVAQAGAAIJKQzhcwCHAAAuAAQKfzAAAwcACAlsI60NADwCAAcACAntH60NADwCACQAAglCE7QjAHIAAAAA.',
Wu='Wukain:BAAALgADCgEJAQAAAA==.',
Xa='Xanatas:BAAALgAECgMJAwABLgAECgkJMQARAEEhAA==.',
Xo='Xolòtl:BAABLgAECn8gAAIOAAgJUBcZFADLAQAOAAgJUBcZFADLAQABLgAFFAYJEgAHAJcVAA==.Xoss:BAAALgAFFAIJAQAAAA==.',
Yg='Yggdrasali:BAAALgAECgQJBgABLgAFFAIJBQAWAJIaAA==.',
Yi='Yin:BAAALgAECgcJCAAAAA==.',
Yo='Yourhero:BAAALgAECgEJAQAAAA==.',
Ys='Yserra:BAAALgAECgcJDAAAAA==.',
Za='Zaerine:BAAALgAECgYJBgAAAA==.Zakuso:BAAALgAECgQJCQAAAA==.Zalatha:BAAALgADCgEJAQAAAA==.Zalyia:BAABLgAECn8uAAIbAAkJlA3qIwCiAQAbAAkJlA3qIwCiAQAAAA==.',
Ze='Zephinar:BAABLgAECn8ZAAIWAAgJcBVpaQADAgAWAAgJcBVpaQADAgAAAA==.Zexpert:BAABLgAECn8cAAQnAAgJSReiDQAAAgAnAAcJIhiiDQAAAgALAAcJnhUvKAB8AQAMAAQJfgwFNADNAAAAAA==.',
Zq='Zquestion:BAAALgAECgIJBAABLgAECggJHAAnAEkXAA==.',
Zu='Zulblade:BAABLgAECn8SAAIGAAgJORqFMAA5AgAGAAgJORqFMAA5AgAAAA==.Zulpally:BAABLgAECn8aAAQQAAUJQBb3wQD7AAAQAAQJxhj3wQD7AAAKAAMJyRCQcgCxAAARAAQJ+QiuMQCIAAAAAA==.',
['Zô']='Zôrt:BAAALgAECgUJCAAAAA==.',
['Àn']='Àngron:BAAALgADCgYJDAAAAA==.',
['Âr']='Ârtemis:BAAALgAECgYJDAAAAA==.',
['Èo']='Èomer:BAAALgAECgEJAQAAAA==.',
['Öh']='Öhmylanta:BAAALgADCgMJAwAAAA==.',
['Öâ']='Öâth:BAAALgAECgIJAgAAAA==.',
['ßa']='ßaroness:BAAALgAECgEJAQAAAA==.',
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
