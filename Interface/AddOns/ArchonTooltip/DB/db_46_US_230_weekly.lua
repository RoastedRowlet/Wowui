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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Unknown-Unknown','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Elemental','Monk-Brewmaster','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Restoration','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Mage-Frost','Warlock-Destruction','Warrior-Fury','Hunter-Survival','Priest-Shadow','Priest-Holy','DeathKnight-Blood','Monk-Windwalker','Druid-Balance','Druid-Guardian','Druid-Feral','Monk-Mistweaver','Warlock-Affliction','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=46,date='2026-05-31',data={Ab='Abaddon:BAABLgAECn8rAAMBAAgJWh4SBgAjAgABAAgJqR0SBgAjAgACAAcJbRvIYwCOAQAAAA==.Abessedge:BAAALgAECgUJBQAAAA==.',
Ac='Acidtears:BAAALgAECgEJAQAAAA==.Ackris:BAABLgAECn8uAAIDAAkJ/BwHCgAuAwADAAkJ/BwHCgAuAwAAAA==.Ackrisa:BAAALgAECgUJCAAAAA==.Acris:BAAALgAECgYJCwABLgAECgkJLgADAPwcAA==.',
Ae='Aedimus:BAAALgADCgcJCQAAAA==.',
Al='Aleathris:BAEALgADCgcJBwABLgAECgQJBAAEAAAAAA==.Alistan:BAAALgAECgEJAQAAAA==.Alka:BAAALgADCgEJAQAAAA==.Alor:BAAALgAECgIJAwABLgAECggJLAAFAK8QAA==.Alpyne:BAAALgAECgcJEgAAAA==.',
Am='Amaimon:BAABLgAECn8aAAMGAAgJDhV8TgCEAQAGAAgJDhV8TgCEAQAHAAEJawzwYQAxAAABLgAFFAcJGQAIAD0TAA==.Amalthaea:BAAALgAECgYJDQABLgAECgkJLgAJAGMWAA==.Amnoon:BAABLgAECn8xAAIKAAkJkhetEgBoAgAKAAkJkhetEgBoAgAAAA==.Amri:BAACLgAFFH8XAAMLAAUJWA80KgAAAQALAAUJWA80KgAAAQAMAAEJYAJSKgAxAAAuAAQKfx8AAwsACAlxFqAVAC0CAAsACAlxFqAVAC0CAAwABglADZkgANsAAAAA.',
An='Andarnáurram:BAAALgAECgIJAgAAAA==.Angelfox:BAAALgAECgIJAQAAAA==.',
Aq='Aquas:BAAALgAECgQJBwAAAA==.',
Ar='Ardrhys:BAAALgAECgYJDQAAAA==.Arthurcarrot:BAAALgAECgQJBwAAAA==.Artikin:BAAALgAECgkJCwABLgAFFAUJEAAHAOUVAA==.',
As='Assasinateu:BAAALgADCgMJAwAAAA==.Asûná:BAAALgAECgcJDwAAAA==.',
At='Atreus:BAABLgAECn8lAAIHAAkJ7BwPDABKAgAHAAkJ7BwPDABKAgAAAA==.Atzalan:BAABLgAECn8UAAINAAYJpwnpcwD7AAANAAYJpwnpcwD7AAAAAA==.',
Au='Automagic:BAAALgAECgEJAgAAAA==.',
Av='Avondwella:BAABLgAECn8rAAMOAAkJZw9cGgBSAQAOAAkJZw9cGgBSAQAPAAEJ+wnERAAvAAAAAA==.',
Az='Azrikam:BAAALgAECgYJCAAAAA==.',
Ba='Baku:BAAALgAECgYJBgABLgAFFAUJEAAHAOUVAA==.Baldyguy:BAAALgADCgcJCgAAAA==.Balm:BAABLgAECn8vAAINAAkJdhhdJwAEAgANAAkJdhhdJwAEAgAAAA==.Balton:BAAALgAECgIJAwAAAA==.Barbsimpsonn:BAAALgAECgEJAQAAAA==.Bashalot:BAAALgAECgUJBgAAAA==.',
Be='Beastcloud:BAAALgAECgIJAgABLgAECgkJJQAHAOwcAA==.Bermin:BAAALgADCgUJAwAAAA==.',
Bi='Biblepimp:BAAALgAFFAEJAQAAAA==.Bigwilliam:BAAALgADCgEJAQAAAA==.',
Bl='Blackmarker:BAABLgAECn8cAAICAAgJ/BRHVQCzAQACAAgJ/BRHVQCzAQAAAA==.',
Bm='Bmo:BAABLgAECn8VAAIQAAcJZSB1SAAJAgAQAAcJZSB1SAAJAgAAAA==.',
Bo='Bodyguardwyn:BAAALgAECgEJAQAAAA==.Bogle:BAACLgAFFH8FAAMQAAIJOQxNjAB0AAAQAAIJUAVNjAB0AAARAAIJOQwOCAA2AAAuAAQKfy8AAxEACQnYIyICAAcDABEACQnYIyICAAcDABAAAwnyFmHLANwAAAAA.Bonedmuch:BAAALgAECgMJAwABLgAECgkJLgAJAGMWAA==.Bow:BAAALgAECgIJAwAAAA==.',
Br='Brasi:BAAALgAECgIJAgAAAA==.Bratton:BAABLgAECn8aAAISAAcJ6wbxEQDSAAASAAcJ6wbxEQDSAAAAAA==.Breadria:BAAALgADCgMJAwABLgAFFAMJBwATAH0FAA==.Bremitin:BAAALgADCggJCAABLgAECgkJMQARAJ8PAA==.Bremitus:BAAALgADCgkJCQABLgAECgkJMQARAJ8PAA==.Brewcrew:BAAALgAECgkJBwAAAA==.Brewey:BAAALgAFFAEJAQAAAA==.Brewmongster:BAAALgAECgQJBQAAAA==.Brimscythe:BAABLgAECn8aAAIGAAgJ5B+wNwAXAgAGAAgJ5B+wNwAXAgAAAA==.Brud:BAAALgAECgMJCwAAAA==.Brunstan:BAACLgAFFH8TAAIUAAUJfh8JDQBgAQAUAAUJfh8JDQBgAQAuAAQKfxcAAhQACQnSHuEDAHECABQACQnSHuEDAHECAAAA.',
Bu='Bubbastump:BAAALgAECgQJBAAAAA==.',
By='Byakugan:BAACLgAFFH8ZAAMIAAcJPRN1BQCDAQAIAAUJaxN1BQCDAQAFAAMJEgkSQADLAAAuAAQKfyAABAgACQktH5oPAK8CAAgACQktH5oPAK8CABUAAQm+F78pAEEAAAUAAQkHAQWpACUAAAAA.',
['Bø']='Bønitalèè:BAABLgAECn8jAAIWAAgJiQmajgBBAQAWAAgJiQmajgBBAQAAAA==.',
Ca='Cain:BAAALgADCgkJDwAAAA==.Calvisi:BAAALgAECgcJDgAAAA==.Calvisichaos:BAABLgAECn8xAAIXAAkJchScBQD7AQAXAAkJchScBQD7AQAAAA==.Cantero:BAAALgADCgUJBQAAAA==.Canthen:BAAALgAECggJDwAAAA==.Carcarnisa:BAAALgAECgQJBgAAAA==.Carm:BAAALgAECgQJBAAAAA==.',
Ce='Cenobia:BAAALgADCgUJCQAAAA==.',
Ch='Chaire:BAAALgADCgcJBgAAAA==.Chrysophylax:BAAALgAECgYJBgAAAA==.',
Co='Conky:BAAALgAECgMJBgAAAA==.Corndog:BAAALgADCgEJAQAAAA==.Cornix:BAAALgADCgEJAQAAAA==.Cosmicspark:BAAALgAECgYJEQAAAA==.',
Cr='Crentist:BAAALgAECgEJAQAAAA==.Critoliz:BAAALgAFFAIJAQAAAA==.Cropala:BAABLgAECn8nAAIQAAkJCBVcNgAQAgAQAAkJCBVcNgAQAgAAAA==.Cruelcodex:BAAALgAECgEJAQAAAA==.',
['Cà']='Càtfish:BAAALgADCgEJAQAAAA==.',
Da='Daca:BAAALgADCgMJAwAAAA==.Darkrequiem:BAAALgADCgkJCwAAAA==.Darkwingduck:BAAALgAECgQJBAAAAA==.Dave:BAAALgADCgQJBAAAAA==.Davros:BAAALgAECgMJBwAAAA==.',
De='Decapitator:BAAALgAECgMJAwAAAA==.Dednburied:BAAALgAECgIJAgAAAA==.Deleto:BAABLgAECn8qAAMBAAgJDRVDDACHAQABAAgJTBFDDACHAQACAAYJYBiniABAAQAAAA==.Dellandre:BAAALgAECgcJEgABLgAECgkJMQARAK8KAA==.Delta:BAABLgAECn8SAAIGAAgJHQdNvgCNAAAGAAgJHQdNvgCNAAAAAA==.Delti:BAAALgAECgUJBgABLgAECggJHgAGACAXAA==.Demondozer:BAAALgAECgMJAwABLgAECgUJCQAEAAAAAA==.Demony:BAAALgAECgEJAQABLgAFFAEJAQAEAAAAAA==.Denard:BAAALgAECgUJBgAAAA==.',
Di='Diabolist:BAABLgAECn8YAAIDAAkJYAggYAB2AQADAAkJYAggYAB2AQAAAA==.Digichowder:BAACLgAFFH8LAAIYAAMJPSSwFwA/AQAYAAMJPSSwFwA/AQAuAAQKfyUAAw8ACQmxI2cDAOUCAA8ACAkOIWcDAOUCABgABQmNHk00AGUBAAAA.Dirtygiri:BAAALgADCgEJAgAAAA==.',
Do='Doktaga:BAAALgAECgYJDgAAAA==.',
Dr='Draex:BAAALgADCgEJAQAAAA==.Dragonzord:BAAALgADCgEJAQAAAA==.Drbubbles:BAAALgADCgYJCAABLgAECgQJCQAEAAAAAA==.Drredd:BAAALgAECgQJBAAAAA==.',
['Dä']='Därkrävèn:BAAALgAECgYJDAAAAA==.',
Ea='Eama:BAAALgADCgIJAwAAAA==.',
Eg='Eggfield:BAAALgAECgUJBgAAAA==.',
El='Eladora:BAAALgADCgEJAQAAAA==.Eldarr:BAABLgAECn81AAMXAAkJ6yArAQDbAgAXAAkJ6yArAQDbAgADAAUJ+hEkhAAoAQAAAA==.Eldhe:BAAALgAECgYJCgAAAA==.Eleos:BAAALgADCgMJBgAAAA==.Elistrae:BAABLgAECn8eAAMZAAgJKRc7HwCVAQAUAAgJKRc0MwCgAQAZAAgJkww7HwCVAQAAAA==.',
Em='Emorri:BAAALgAECgYJBgAAAA==.',
En='Enazen:BAABLgAECn8dAAIMAAgJ+BooBwB4AgAMAAgJ+BooBwB4AgAAAA==.Endlol:BAABLgAECn8vAAMaAAkJFyE6BwDGAgAaAAkJFyE6BwDGAgAbAAEJUh+3WwBUAAABLgAFFAIJAwAEAAAAAA==.',
Er='Eredaria:BAAALgAECgUJCQAAAA==.Ereshkigal:BAAALgADCgYJCwAAAA==.Ergo:BAACLgAFFH8VAAIWAAcJxhFNDwCeAQAWAAcJxhFNDwCeAQAuAAQKfyYAAhYACQmuIhsjAOYCABYACQmuIhsjAOYCAAAA.Eronel:BAABLgAECn8eAAICAAcJ7RqDXwCZAQACAAcJ7RqDXwCZAQAAAA==.',
Es='Esv:BAABLgAFFH8FAAIOAAMJIwWnHQCQAAAOAAMJIwWnHQCQAAABLgAFFAQJFQAWAI4RAA==.',
Ex='Excido:BAAALgAECgEJAgAAAA==.Exodiagold:BAAALgAECgEJAQAAAA==.',
Fa='Fadedharanir:BAAALgAECgIJAwAAAA==.Fadedheart:BAAALgAECgQJBwABLgAECgkJMgACAPIfAA==.Fadedmystic:BAAALgAECgQJBAAAAA==.Fadednight:BAABLgAECn8yAAMCAAkJ8h/XFAC5AgACAAkJ8h/XFAC5AgAcAAEJ1QEIYwARAAAAAA==.Faeyir:BAACLgAFFH8PAAIWAAQJKQyYWQAfAQAWAAQJKQyYWQAfAQAuAAQKfyIAAhYACQnDHT9QAEYCABYACQnDHT9QAEYCAAAA.Fallingmoon:BAABLgAECn8nAAMTAAkJqCAgDADgAgATAAkJqCAgDADgAgAUAAEJKRDmigAwAAAAAA==.Fangrage:BAAALgAECgYJBAAAAA==.Fatherlode:BAACLgAFFH8KAAIWAAMJwBi6cADgAAAWAAMJwBi6cADgAAAuAAQKfysAAhYACQmUIRoZAK4CABYACQmUIRoZAK4CAAAA.',
Fe='Feltpen:BAAALgAECgUJBQAAAA==.Femcelibate:BAAALgADCgcJCAAAAA==.Fentenjoyer:BAAALgAECgcJDwAAAA==.Fernfondler:BAAALgAFFAIJAwAAAA==.',
Fl='Flashylights:BAAALgADCgYJBgAAAA==.',
Fo='Fontane:BAAALgADCgYJBwAAAA==.Forcebolt:BAAALgADCgMJAwAAAA==.',
Fr='Fredgoffin:BAAALgAECgIJAgAAAA==.Freecookies:BAAALgAECgYJCQAAAA==.Frostybop:BAAALgAECgMJBAAAAA==.Frostybrews:BAAALgAECgEJAQABLgAECgMJBAAEAAAAAA==.Frostydh:BAAALgAECgMJAwABLgAECgMJBAAEAAAAAA==.Frostytotems:BAAALgAECgQJBgAAAA==.Fróstblight:BAAALgAECgkJCAAAAA==.',
Fu='Furryiosa:BAAALgADCgYJBgAAAA==.',
Ga='Gauntodimm:BAAALgAECgYJCgAAAA==.',
Gi='Gilberticus:BAAALgAECgYJEgABLgAECgkJRQAdAIIiAA==.Gishmou:BAABLgAECn8eAAIFAAgJKhtgKAAEAgAFAAgJKhtgKAAEAgAAAA==.',
Go='Goldblade:BAABLgAECn8gAAIQAAgJWhf5SQDRAQAQAAgJWhf5SQDRAQAAAA==.',
Gr='Grayhair:BAAALgAECgQJBwAAAA==.Greyoll:BAAALgAECgYJCAAAAA==.Grimling:BAAALgAECgQJCAABLgAFFAUJEAAHAOUVAA==.Grindlewald:BAAALgAECgIJAgAAAA==.',
Gu='Gutted:BAACLgAFFH8cAAMcAAcJtSTbAAAmAgAcAAcJtSTbAAAmAgACAAEJxQzA7ABBAAAuAAQKfx0AAhwACQkZJr0BAGcDABwACQkZJr0BAGcDAAAA.',
['Gä']='Gärin:BAAALgADCggJFAAAAA==.',
Ha='Hanna:BAAALgAFFAEJAQABLgAFFAcJHAAcALUkAA==.Harleyswar:BAAALgADCgEJAQAAAA==.',
He='Hellmaw:BAAALgAECgYJCwAAAA==.',
Hi='Highly:BAAALgADCgcJCwAAAA==.',
Ho='Holianna:BAAALgAECgIJAgAAAA==.Hollowheart:BAABLgAECn8vAAIFAAkJjhg0HwA9AgAFAAkJjhg0HwA9AgAAAA==.Holycourtney:BAAALgADCgkJEQAAAA==.Holyknight:BAAALgADCgEJAQAAAA==.Hotsausage:BAAALgAECgMJAwAAAA==.Hoved:BAAALgADCgEJAQAAAA==.',
Hy='Hylanna:BAAALgAECgYJCgAAAA==.Hyorinmaru:BAAALgAFFAEJAQAAAA==.',
['Hó']='Hónor:BAAALgADCgMJAwABLgAECgkJMQARAJ8PAA==.',
Ic='Ici:BAABLgAECn8yAAMQAAkJ0AfigABTAQAQAAkJ0AfigABTAQAKAAQJuA4SVwDEAAAAAA==.',
If='Iffybacon:BAAALgAECgIJAgABLgAECgQJCwAEAAAAAA==.',
Ik='Ikilledkeny:BAAALgAFFAIJAQAAAA==.',
Im='Imlerith:BAAALgADCgQJBgAAAA==.',
In='Intensifies:BAAALgAECgcJEgAAAA==.',
Ip='Ippo:BAAALgADCgEJAQAAAA==.',
Is='Isabellà:BAAALgAECggJDAABLgAECgkJIwAeAKELAA==.Iskothar:BAABLgAECn8qAAIRAAgJVh8rBgByAgARAAgJVh8rBgByAgAAAA==.',
Iv='Ivarboneless:BAAALgAECgYJEwAAAA==.',
Ja='Jackz:BAAALgAECgkJCQAAAA==.Jackzlock:BAAALgAECgkJAQAAAA==.Jakethemage:BAAALgADCgUJCAAAAA==.Jankball:BAAALgAFFAIJAQAAAA==.',
Je='Jefftrep:BAAALgAECgQJAwAAAA==.Jerihatrix:BAAALgAECgEJAQAAAA==.',
Ji='Jimmylahey:BAAALgAECgMJAwAAAA==.',
Jo='Jonah:BAAALgADCgEJAQAAAA==.',
Ka='Kaina:BAAALgADCgYJCQAAAA==.Kakidruid:BAAALgAECgIJAwAAAA==.Kalfu:BAAALgAECgkJEwAAAA==.',
Ke='Ketesh:BAABLgAECn88AAIfAAkJzSDPAgDyAgAfAAkJzSDPAgDyAgABLgAFFAUJFwALAFgPAA==.',
Ki='Kilorean:BAAALgAECgcJCAAAAA==.Kirae:BAAALgADCgkJGQABLgAECggJKgARAFYfAA==.',
Kl='Kleanse:BAAALgAFFAIJAQAAAA==.',
Kn='Knastey:BAABLgAECn8VAAQeAAYJ4BdLMQA+AQAeAAYJ4BdLMQA+AQANAAYJZAqbcQABAQAgAAEJWxKCMgA3AAAAAA==.Knasty:BAAALgADCgEJAQAAAA==.',
Ko='Kodera:BAABLgAECn8aAAILAAYJIAXHYgCMAAALAAYJIAXHYgCMAAAAAA==.',
Kr='Krej:BAABLgAECn8VAAIcAAkJRxr2DwDxAQAcAAkJRxr2DwDxAQABLgAFFAUJEAAHAOUVAA==.Krisskringle:BAAALgAECgMJBgAAAA==.',
Ku='Kuromori:BAAALgADCgYJBgAAAA==.',
Ky='Kyronix:BAAALgAECgMJBwAAAA==.',
['Kê']='Kênpachi:BAAALgAECgYJDgAAAA==.',
La='Landrey:BAAALgADCgcJBwAAAA==.Langarde:BAABLgAECn8dAAIOAAgJBQ/UGgBNAQAOAAgJBQ/UGgBNAQAAAA==.Laoghaire:BAABLgAECn8YAAIHAAcJ+ANBOgCwAAAHAAcJ+ANBOgCwAAAAAA==.',
Le='Leonz:BAACLgAFFH8XAAIYAAcJRR5kBADxAQAYAAcJRR5kBADxAQAuAAQKfy4AAhgACQmaJOMDABsDABgACQmaJOMDABsDAAAA.Leonzs:BAAALgAECggJEAAAAA==.Letharanos:BAEBLgAECn8nAAMCAAkJdBmHPAD+AQACAAkJdBmHPAD+AQAcAAEJew5QVwApAAAAAA==.',
Li='Liraffemynn:BAACLgAFFH8OAAIhAAQJVhdDIAAcAQAhAAQJVhdDIAAcAQAuAAQKfzwAAiEACQk2I1IDAHIDACEACQk2I1IDAHIDAAAA.Liralynn:BAAALgADCgUJBQAAAA==.',
Lk='Lkynyx:BAAALgADCgYJAQAAAA==.',
Lo='Lonranir:BAAALgAECgMJAwAAAA==.Lostinlight:BAAALgAECgYJBgAAAA==.',
Lu='Lucii:BAAALgADCgEJAQABLgAFFAcJHAAcALUkAA==.Luckylucy:BAABLgAECn8XAAIbAAYJhhaiKgBgAQAbAAYJhhaiKgBgAQAAAA==.',
Ma='Madarauchiha:BAABLgAECn8WAAICAAYJxxVwggB+AQACAAYJxxVwggB+AQAAAA==.Magus:BAAALgADCgkJEQABLgAECgMJBwAEAAAAAA==.Maldran:BAABLgAECn8aAAIFAAcJjh0DJgASAgAFAAcJjh0DJgASAgAAAA==.Maling:BAAALgAECgEJAQAAAA==.Manderpants:BAABLgAECn8bAAITAAcJMAm+ewAxAQATAAcJMAm+ewAxAQAAAA==.Marien:BAABLgAECn8dAAIcAAgJ8BmbDwD2AQAcAAgJ8BmbDwD2AQAAAA==.Marty:BAAALgAECgIJAwAAAA==.Maxus:BAAALgADCgUJBQAAAA==.',
Mb='Mbbin:BAACLgAFFH8JAAIWAAIJvCQHdQDYAAAWAAIJvCQHdQDYAAAuAAQKfycAAhYACQmmIVwbAKICABYACQmmIVwbAKICAAAA.',
Me='Mehuman:BAABLgAECn8UAAIQAAUJNQ+bzQDZAAAQAAUJNQ+bzQDZAAAAAA==.Mehumanhuntr:BAAALgAECgQJBAAAAA==.Mehumanlock:BAABLgAECn8jAAIXAAkJ+xFRCACvAQAXAAkJ+xFRCACvAQAAAA==.Merlinn:BAAALgADCgkJCwAAAA==.Merran:BAAALgADCgEJAQAAAA==.Metal:BAAALgADCgQJBAAAAA==.Meworgendk:BAAALgAECgYJDgAAAA==.',
Mh='Mhoo:BAAALgADCgcJBwAAAA==.',
Mi='Miriym:BAAALgADCgEJAQAAAA==.Miräj:BAAALgAECgYJCgAAAA==.Mistyblue:BAAALgADCgEJAQAAAA==.Miya:BAAALgADCgcJDQAAAA==.',
Mo='Moonscale:BAAALgAECgMJAwAAAA==.Mordaci:BAAALgADCgQJBQABLgAECggJDAAEAAAAAA==.Mordekrieg:BAAALgAFFAMJAwAAAA==.Mortstan:BAAALgAECgcJDQAAAA==.',
My='Myash:BAAALgADCgYJBwAAAA==.',
['Må']='Månni:BAAALgADCgEJAQAAAA==.',
['Mé']='Mélusine:BAAALgADCgEJAQAAAA==.',
Na='Nailia:BAAALgAECgUJCQAAAA==.Nailz:BAABLgAECn8eAAIGAAgJIBdLTQDAAQAGAAgJIBdLTQDAAQAAAA==.Nakama:BAAALgADCgYJBgABLgAECggJLAAFAK8QAA==.Nardog:BAAALgAECgEJAQAAAA==.Narie:BAAALgAECggJCQAAAA==.Nasaug:BAAALgAECgUJCwABLgAECgkJMQARAJ8PAA==.',
Ne='Ned:BAAALgAECgEJAQAAAA==.Neuse:BAAALgAECggJEwAAAA==.',
Ni='Nightlion:BAABLgAECn8XAAIfAAYJAA6CLQDUAAAfAAYJAA6CLQDUAAAAAA==.Nillius:BAAALgADCgIJAgAAAA==.Nisu:BAAALgAECgEJAQAAAA==.',
No='Noahdh:BAAALgAECgMJAwABLgAFFAcJGQADADkZAA==.Noahpriest:BAAALgAECgMJAwABLgAFFAcJGQADADkZAA==.Noahvoker:BAAALgAECggJEQABLgAFFAcJGQADADkZAA==.Noahwarlock:BAACLgAFFH8ZAAQDAAcJORlVDwBkAQADAAUJuR9VDwBkAQAXAAMJXxG6CADoAAAiAAEJkSMwGQBSAAAuAAQKfzEABAMACQmFJN8DAEsDAAMACAlsJN8DAEsDABcABAl0IkEaAHsBACIAAwmsI4IWAM0AAAAA.Nonsensical:BAAALgADCgUJBQABLgAECgUJHAAhAKoiAA==.Nook:BAAALgADCgUJBgAAAA==.Nowere:BAAALgADCgcJBwAAAA==.Noxander:BAAALgAECgEJAQAAAA==.',
Ny='Nym:BAAALgAECgkJEQAAAA==.',
['Nâ']='Nârenth:BAAALgADCgMJAwAAAA==.',
Oa='Oaths:BAAALgAECgcJDwAAAA==.',
Oh='Ohmylantä:BAABLgAECn8dAAIWAAgJPg1ahABVAQAWAAgJPg1ahABVAQAAAA==.Ohmylantå:BAAALgADCgUJCAAAAA==.',
On='Ondeane:BAAALgADCgEJAQAAAA==.Onumae:BAABLgAECn8XAAIQAAkJcRpPKwA9AgAQAAkJcRpPKwA9AgAAAA==.',
Op='Oprime:BAAALgADCgMJAwAAAA==.',
Or='Orator:BAAALgAFFAIJAQAAAA==.Orbeck:BAAALgAECggJCAABLgAFFAcJHAAJAFMeAA==.Ormond:BAAALgAECgcJEwAAAA==.Orochinchin:BAAALgAECgMJAwABLgAFFAcJHAAcALUkAA==.',
Os='Oscarmike:BAAALgADCgcJDQAAAA==.',
Oz='Ozlon:BAAALgAECgcJEwAAAA==.',
['Oâ']='Oâth:BAABLgAECn8iAAMjAAkJCwufDwA5AQAjAAkJCwufDwA5AQAHAAMJRgZUVwBGAAAAAA==.',
Pa='Pachane:BAAALgAECgQJCwAAAA==.Paldozer:BAAALgAECgUJCQABLgAECgUJCQAEAAAAAA==.Pallywacker:BAABLgAECn8uAAIRAAgJ2hI6EgCLAQARAAgJ2hI6EgCLAQAAAA==.Pankins:BAAALgAECgMJAwAAAA==.Panzerkan:BAAALgAECgEJAQAAAA==.Panzerkìn:BAAALgAECgcJCAAAAA==.',
Pe='Percymorris:BAAALgADCgYJBwAAAA==.Peythilly:BAAALgAECgIJAgAAAA==.',
Pi='Pigishdog:BAABLgAECn9KAAIDAAkJtRxcFgCUAgADAAkJtRxcFgCUAgAAAA==.Pikon:BAAALgADCgkJDQAAAA==.',
Po='Pokeabear:BAAALgAECgYJEAABLgAECgcJEAAEAAAAAA==.Pokethedruid:BAAALgAECgEJAQABLgAECgEJBwAEAAAAAA==.Pokethemonk:BAAALgAECgEJBwAAAA==.Poshingtang:BAABLgAECn8pAAQFAAkJqQw5PgCbAQAFAAkJqQw5PgCbAQAIAAgJHhG8NgB4AQAVAAMJSwP+JQB3AAAAAA==.',
Pu='Pulsar:BAAALgADCggJDQAAAA==.Punchies:BAAALgADCggJDQAAAA==.',
Qu='Quatrain:BAABLgAECn8sAAMFAAgJrxA9VABHAQAFAAgJrxA9VABHAQAIAAEJnxBvlQAwAAAAAA==.Quintessence:BAAALgAECgMJAwAAAA==.',
Ra='Rabidbutt:BAAALgAFFAIJAwABLgAFFAYJEgAMAA0jAA==.Ragerunner:BAAALgADCgkJEwAAAA==.Rakarg:BAABLgAECn8ZAAICAAUJDBilvADuAAACAAUJDBilvADuAAAAAA==.Ravenus:BAAALgAECgEJAQAAAA==.',
Re='React:BAAALgAECggJCAABLgAFFAIJAwAEAAAAAA==.Refund:BAAALgAECgEJAQAAAA==.Regalbacon:BAAALgAECgMJAwAAAA==.Reygina:BAABLgAECn8ZAAIKAAYJygLEWQC4AAAKAAYJygLEWQC4AAAAAA==.',
Ri='Rickÿ:BAAALgAECgEJAQAAAA==.Rikku:BAAALgAECggJCAABLgAFFAcJGQAIAD0TAA==.Ripndip:BAAALgAFFAIJAQAAAA==.Riprock:BAAALgAECgIJAQABLgAFFAIJAQAEAAAAAA==.Rixas:BAAALgAECgEJAQABLgAECgkJLgADAPwcAA==.',
Rn='Rn:BAACLgAFFH8FAAIPAAQJShjZEgAgAQAPAAQJShjZEgAgAQAuAAQKfx4AAw8ACQklIkEBAEYDAA8ACQkIIkEBAEYDABgABwkvIyQpABcCAAEuAAUUCAkiAA8AgyQA.',
Ro='Rodeo:BAAALgAECgMJAwAAAA==.Roguehiro:BAABLgAECn8nAAIRAAgJuyERBQCPAgARAAgJuyERBQCPAgAAAA==.Rooter:BAACLgAFFH8SAAIMAAYJDSOsBABUAgAMAAYJDSOsBABUAgAuAAQKfzsAAwwACAmPJYkDAP4CAAwACAmPJYkDAP4CAAsABwnsGTYiALABAAAA.Rosalynñ:BAABLgAECn8pAAIXAAgJMgqmEQAVAQAXAAgJMgqmEQAVAQAAAA==.',
Ru='Ruikhai:BAAALgADCgMJBQABLgADCgkJBwAEAAAAAA==.Ruto:BAAALgAECgEJAQABLgAFFAIJAQAEAAAAAA==.',
Sa='Saelis:BAACLgAFFH8VAAINAAUJnhaRGgBpAQANAAUJnhaRGgBpAQAuAAQKfx0AAw0ACQnAHhwWAIUCAA0ACQnAHhwWAIUCACAABgnwGXIRAIEBAAAA.Salen:BAAALgADCgMJAgAAAA==.Samshara:BAAALgADCgcJDAABLgAECgkJOgAZAGEdAA==.Saptapper:BAAALgAECgIJAgAAAA==.Saracenio:BAAALgADCgEJAQAAAA==.',
Sc='Schnem:BAAALgAECggJCgAAAA==.Scrawni:BAAALgAECgcJCAABLgAFFAUJEAAHAOUVAA==.Scrounge:BAAALgAECgQJBQABLgAECgkJGAADAGAIAA==.',
Se='Securìty:BAAALgAECgQJBQAAAA==.Selyane:BAAALgADCgkJCQAAAA==.Senia:BAAALgAECgkJEQAAAA==.Seong:BAACLgAFFH8cAAIJAAcJUx5pBgD1AQAJAAcJUx5pBgD1AQAuAAQKfyEAAgkACQmAIgUFADkDAAkACQmAIgUFADkDAAAA.Seongdh:BAAALgAECggJDQABLgAFFAcJHAAJAFMeAA==.Seongwar:BAAALgAECgMJAwAAAA==.Seraphinà:BAAALgAECgYJDAABLgAECgkJIwAeAKELAA==.',
Sh='Shadowdooms:BAABLgAECn8WAAMCAAgJFBkfYQDQAQACAAgJFBkfYQDQAQABAAEJSxf2FABFAAAAAA==.Shadowfur:BAAALgADCgkJCQABLgAECgkJOwAKAN8eAA==.Shamynna:BAAALgAECgIJAwAAAA==.Sharreth:BAAALgAECgIJAgAAAA==.Shii:BAAALgADCgUJBQAAAA==.Shimera:BAABLgAECn8uAAITAAkJAxPlNQDxAQATAAkJAxPlNQDxAQAAAA==.Shish:BAAALgAECggJCwAAAA==.Shockawar:BAACLgAFFH8WAAIYAAUJeRwxAwDEAQAYAAUJeRwxAwDEAQAuAAQKfxkAAhgACQmrHmYYAIgCABgACQmrHmYYAIgCAAAA.Shooter:BAAALgADCgIJAgAAAA==.Shootrmcgavn:BAACLgAFFH8eAAQTAAYJ8yIkFQCFAQATAAUJrx8kFQCFAQAZAAQJRSEWCQBwAQAUAAQJNiDGEAAqAQAuAAQKfxsABBMACAk8IdMVAIkCABMABwnxIdMVAIkCABQABwlKIcoaAFMCABkAAwm3IVQuACUBAAAA.Shu:BAAALgAFFAIJAgAAAA==.Shuletaa:BAAALgAECgIJBAAAAA==.Shïsh:BAAALgADCgcJBwABLgAECggJCwAEAAAAAA==.',
Si='Silverwolf:BAAALgADCgEJAQAAAA==.Sinestra:BAAALgAECgEJAQAAAA==.',
Sk='Skibidi:BAAALgAECgEJAQABLgAFFAMJDgAWAB0YAA==.',
Sl='Slagscar:BAAALgAFFAIJAQAAAA==.Slaughterhse:BAABLgAECn8XAAIWAAYJ5gOX7wCjAAAWAAYJ5gOX7wCjAAAAAA==.Slootar:BAABLgAECn8UAAQNAAcJ5xuIJAAoAgANAAcJ5xuIJAAoAgAeAAIJuxBfbABuAAAgAAIJMAZZSQAsAAAAAA==.Slugs:BAAALgAECgUJCAAAAA==.',
Sn='Snqwflake:BAABLgAECn8VAAIhAAgJ7xb8FQAUAgAhAAgJ7xb8FQAUAgAAAA==.',
So='Solareth:BAAALgAECgEJAgAAAA==.Somebeotch:BAAALgADCgYJBgAAAA==.Somerled:BAABLgAECn86AAIZAAkJYR0jBwCiAgAZAAkJYR0jBwCiAgAAAA==.',
Sp='Spyroid:BAAALgAECgUJAQAAAA==.',
St='Static:BAAALgADCgcJBwABLgAECgYJCgAEAAAAAA==.',
Su='Sunstrike:BAAALgAECgEJAgAAAA==.',
Sy='Sylvanna:BAAALgADCgQJBAAAAA==.',
Ta='Tabul:BAAALgADCgUJBAAAAA==.Takka:BAABLgAECn8aAAIFAAgJHR3VFACMAgAFAAgJHR3VFACMAgAAAA==.Talden:BAABLgAECn9EAAMQAAkJMhybGgCOAgAQAAkJMhybGgCOAgARAAMJzRCzPwBMAAAAAA==.Talkamar:BAABLgAECn8iAAIdAAkJ6RA4HQCuAQAdAAkJ6RA4HQCuAQAAAA==.Taylorswift:BAABLgAECn8uAAIWAAkJ3hfVLgBIAgAWAAkJ3hfVLgBIAgAAAA==.Tazzaar:BAAALgAECgMJAwAAAA==.',
Th='Thaelios:BAAALgADCgEJAQAAAA==.Thekourge:BAABLgAECn8xAAIRAAkJrwp9GABAAQARAAkJrwp9GABAAQAAAA==.Thenard:BAABLgAECn8iAAITAAgJPBMrSwCqAQATAAgJPBMrSwCqAQAAAA==.Thukunaenhan:BAAALgAECgQJBAABLgAFFAMJDgAWAB0YAA==.Thukunamage:BAACLgAFFH8OAAIWAAMJHRhuaAD1AAAWAAMJHRhuaAD1AAAuAAQKfyoAAhYACQmyIAQdAJkCABYACQmyIAQdAJkCAAAA.',
Ti='Tibarius:BAAALgADCgkJEgAAAA==.Tili:BAAALgADCgcJCwAAAA==.Tinaraeda:BAAALgAECgMJAwAAAA==.',
To='Tomislav:BAABLgAECn8eAAQDAAkJrxLNSwCtAQADAAcJzRLNSwCtAQAXAAMJRBVMTwCAAAAiAAEJlA6ZNQA4AAAAAA==.Touritos:BAABLgAECn8eAAIIAAkJdRGNJgCfAQAIAAkJdRGNJgCfAQAAAA==.',
Tr='Trimblestein:BAAALgAECgEJAQAAAA==.Troyka:BAAALgAECgEJAQAAAA==.Truefitt:BAAALgAECgYJEwAAAA==.',
Tu='Tulikettwo:BAAALgAECgEJAQAAAA==.Tulirenpo:BAAALgAECgUJBQAAAA==.Tunk:BAAALgAFFAIJAQAAAA==.Tuskal:BAAALgAECgIJAwAAAA==.',
Tw='Twogora:BAAALgAECgYJCQAAAA==.Twohoofy:BAAALgADCgcJBgAAAA==.',
Ty='Tydes:BAABLgAECn8bAAMkAAgJ6RbMEwB4AgAkAAgJ6RbMEwB4AgAlAAEJtgtBHQBBAAAAAA==.Tydru:BAAALgAFFAIJAQAAAA==.Tyler:BAACLgAFFH8LAAIGAAQJfhXYDwBPAQAGAAQJfhXYDwBPAQAuAAQKfxsAAgYACAkOHTgcAKkCAAYACAkOHTgcAKkCAAAA.Tystin:BAAALgADCgQJBQABLgADCgkJBwAEAAAAAA==.',
Ud='Uddermilk:BAABLgAECn8UAAIeAAQJrQrWUgCpAAAeAAQJrQrWUgCpAAAAAA==.',
Um='Umariel:BAAALgAFFAIJAQAAAA==.',
Va='Valina:BAAALgADCgIJAgAAAA==.Valissar:BAAALgAECgMJBQAAAA==.Valr:BAABLgAECn8xAAIRAAkJnw/FFABrAQARAAkJnw/FFABrAQAAAA==.Vancliffe:BAAALgAECgQJBAABLgAFFAUJEAAHAOUVAA==.Vandreu:BAAALgADCgUJBQAAAA==.',
Ve='Verpally:BAAALgADCgMJAwAAAA==.',
Vi='Viparia:BAAALgAECgkJAgAAAA==.Virulent:BAAALgAECgMJAwAAAA==.',
Vo='Voloaura:BAAALgADCgMJAwAAAA==.',
Vs='Vse:BAACLgAFFH8VAAIWAAQJjhEJTwAyAQAWAAQJjhEJTwAyAQAuAAQKfy4AAhYACAl8G0ZBAAICABYACAl8G0ZBAAICAAAA.Vsesosorry:BAABLgAFFH8PAAIFAAQJIA8TNADzAAAFAAQJIA8TNADzAAABLgAFFAQJFQAWAI4RAA==.Vsè:BAAALgADCgUJBQABLgAFFAQJFQAWAI4RAA==.',
Vy='Vyke:BAAALgAECggJDgABLgAFFAcJHAAJAFMeAA==.',
['Ví']='Ví:BAAALgAECgYJBgAAAA==.',
Wa='Wammo:BAAALgAECgYJCgAAAA==.Waq:BAAALgADCgMJAwAAAA==.Wardozer:BAAALgAECgUJCQAAAA==.Warlockedin:BAAALgAECgYJDQAAAA==.',
We='Weierstrass:BAAALgAFFAEJAQABLgAFFAcJHAAcALUkAA==.',
Wo='Worgenkrantz:BAABLgAECn8jAAMeAAkJoQv9KABwAQAeAAkJoQv9KABwAQANAAcJeAJQkgCrAAAAAA==.',
Wr='Wrathlor:BAAALgADCgcJBQAAAA==.Wrenlyn:BAACLgAFFH8QAAIHAAUJ5RVLDQAcAQAHAAUJ5RVLDQAcAQAuAAQKfzAAAwcACAlsI3UMAEICAAcACAntH3UMAEICACMAAglCE6shAHQAAAAA.',
Xa='Xanatas:BAAALgADCggJCAABLgAECggJKgARAFYfAA==.',
Xo='Xolòtl:BAABLgAECn8gAAIOAAgJUBcZFADLAQAOAAgJUBcZFADLAQABLgAFFAUJEAAHAOUVAA==.Xoss:BAAALgAFFAIJAQAAAA==.',
Yg='Yggdrasali:BAAALgAECgQJBgABLgAFFAIJBQAWAJIaAA==.',
Yi='Yin:BAAALgAECgcJCAAAAA==.',
Ys='Yserra:BAAALgAECgcJDAAAAA==.',
Za='Zakuso:BAAALgAECgQJCQAAAA==.Zalatha:BAAALgADCgEJAQAAAA==.Zalyia:BAABLgAECn8uAAIaAAkJlA21IgCVAQAaAAkJlA21IgCVAQAAAA==.',
Ze='Zephinar:BAABLgAECn8ZAAIWAAgJcBVpaQADAgAWAAgJcBVpaQADAgAAAA==.Zexpert:BAABLgAECn8cAAQmAAgJSReiDQAAAgAmAAcJIhiiDQAAAgALAAcJnhUvKAB8AQAMAAQJfgwFNADNAAAAAA==.',
Zq='Zquestion:BAAALgAECgIJBAABLgAECggJHAAmAEkXAA==.',
Zu='Zulblade:BAABLgAECn8SAAIGAAgJORqFMAA5AgAGAAgJORqFMAA5AgAAAA==.Zulpally:BAABLgAECn8aAAQQAAUJQBYKtgD7AAAQAAQJxhgKtgD7AAAKAAMJyRCQcgCxAAARAAQJ+QiuMQCIAAAAAA==.',
['Zô']='Zôrt:BAAALgAECgUJCAAAAA==.',
['Àn']='Àngron:BAAALgADCgYJDAAAAA==.',
['Âr']='Ârtemis:BAAALgAECgYJCwAAAA==.',
['Èo']='Èomer:BAAALgAECgEJAQAAAA==.',
['Öh']='Öhmylanta:BAAALgADCgMJAwAAAA==.',
['Öâ']='Öâth:BAAALgAECgIJAgAAAA==.',
['ßa']='ßaroness:BAAALgADCgUJCQAAAA==.',
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
