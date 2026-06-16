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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Unknown-Unknown','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Brewmaster','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Restoration','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Shaman-Enhancement','Mage-Frost','Warlock-Destruction','DeathKnight-Blood','Warrior-Fury','Hunter-Survival','Priest-Shadow','Priest-Holy','Monk-Windwalker','Druid-Balance','Priest-Discipline','Druid-Guardian','Druid-Feral','Monk-Mistweaver','Warlock-Affliction','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=46,date='2026-06-14',data={Ab='Abaddon:BAABLgAECn8tAAMBAAkJTB8LBwApAgABAAgJ6R0LBwApAgACAAgJrByuRADyAQAAAA==.Abessedge:BAAALgAECgUJBQAAAA==.',
Ac='Acidtears:BAAALgAECgEJAQAAAA==.Ackris:BAABLgAECn8uAAIDAAkJ/BwHCgAuAwADAAkJ/BwHCgAuAwAAAA==.Ackrisa:BAAALgAECgUJCAAAAA==.Acris:BAAALgAECgYJCwABLgAECgkJLgADAPwcAA==.',
Ae='Aedimus:BAAALgADCgcJCQAAAA==.',
Al='Aleathris:BAEALgADCgcJBwABLgAECgQJBAAEAAAAAA==.Alistan:BAAALgAECgEJAQAAAA==.Alka:BAAALgADCgEJAQAAAA==.Alor:BAAALgAECgIJBAABLgAECgkJNAAFAJgMAA==.Alpyne:BAAALgAECgcJEgAAAA==.',
Am='Amaimon:BAABLgAECn8aAAMGAAgJDhXwVQCCAQAGAAgJDhXwVQCCAQAHAAEJawxxbgAvAAABLgAFFAgJHAAFACoTAA==.Amalthaea:BAAALgAECgcJEwABLgAECgkJLgAIAGMWAA==.Amnoon:BAABLgAECn80AAIJAAkJ+Be1EwBwAgAJAAkJ+Be1EwBwAgAAAA==.Amri:BAACLgAFFH8dAAMKAAUJSxNHLwABAQAKAAUJSxNHLwABAQALAAEJYAJfLwAlAAAuAAQKfyQAAwoACAlOGaAVAC0CAAoACAlOGaAVAC0CAAsABglADQoiAN0AAAAA.',
An='Andarnáurram:BAAALgAECgIJAgAAAA==.Angelfox:BAAALgAECgQJAgAAAA==.',
Aq='Aquas:BAAALgAECgQJBwAAAA==.',
Ar='Ardrhys:BAAALgAFFAQJBAAAAA==.Arthurcarrot:BAAALgAECgQJBwAAAA==.Artikin:BAAALgAECgkJCwABLgAFFAYJEgAHAJcVAA==.',
As='Assasinateu:BAAALgADCgMJAwAAAA==.Asûná:BAAALgAECggJEAAAAA==.',
At='Atreus:BAABLgAECn8mAAMHAAkJ7BwaDgBAAgAHAAkJ7BwaDgBAAgAGAAEJVAu0HAEqAAAAAA==.Atzalan:BAABLgAECn8UAAIMAAYJpwnpcwD7AAAMAAYJpwnpcwD7AAAAAA==.',
Au='Automagic:BAAALgAECgEJAgAAAA==.',
Av='Avondwella:BAABLgAECn8vAAMNAAkJfhAxGgBmAQANAAkJfhAxGgBmAQAOAAEJ+wnERAAvAAAAAA==.',
Az='Azrikam:BAAALgAECgYJCAAAAA==.',
Ba='Baku:BAAALgAECgYJBgABLgAFFAYJEgAHAJcVAA==.Baldyguy:BAAALgADCgcJCgAAAA==.Balm:BAABLgAECn8xAAIMAAkJCBqCIQA5AgAMAAkJCBqCIQA5AgAAAA==.Balton:BAAALgAECgIJAwAAAA==.Barbsimpsonn:BAAALgAECgEJAQAAAA==.Bashalot:BAAALgAECgUJBgAAAA==.',
Be='Beastcloud:BAAALgAECgIJAgABLgAECgkJJgAHAOwcAA==.Behindyou:BAAALgAECggJBAABLgAECgkJKAAPAAgVAA==.Bermin:BAAALgADCgUJAwAAAA==.',
Bi='Biblepimp:BAAALgAFFAEJAQAAAA==.Bigwilliam:BAAALgADCgEJAQAAAA==.',
Bl='Blackmarker:BAABLgAECn8cAAICAAgJ/BT6XACvAQACAAgJ/BT6XACvAQAAAA==.Blackmouser:BAAALgADCgQJBAAAAA==.Bloodpac:BAAALgAECgEJAQAAAA==.',
Bm='Bmo:BAABLgAECn8VAAIPAAcJZSB1SAAJAgAPAAcJZSB1SAAJAgAAAA==.',
Bo='Bodyguardwyn:BAAALgAECgEJAQAAAA==.Bogle:BAACLgAFFH8FAAMPAAIJOQwrpgBuAAAPAAIJUAUrpgBuAAAQAAIJOQwOCAA2AAAuAAQKfy8AAxAACQnYI6QCAAADABAACQnYI6QCAAADAA8AAwnyFknhANoAAAAA.Bonedmuch:BAAALgAECgcJDQABLgAECgkJLgAIAGMWAA==.Bow:BAAALgAECgIJAwAAAA==.',
Br='Brasi:BAAALgAECgIJAgAAAA==.Bratton:BAABLgAECn8aAAIRAAcJ6wZwEwDUAAARAAcJ6wZwEwDUAAAAAA==.Breadria:BAAALgAECgEJAwABLgAFFAMJBwASAH0FAA==.Bremitin:BAAALgADCggJCAABLgAECgkJNAAQALcPAA==.Bremitus:BAAALgADCgkJCQABLgAECgkJNAAQALcPAA==.Brewcrew:BAAALgAECgkJBwAAAA==.Brewey:BAAALgAFFAEJAQAAAA==.Brewmongster:BAAALgAECgQJBQAAAA==.Brimscythe:BAABLgAECn8bAAIGAAgJ5B+wNwAXAgAGAAgJ5B+wNwAXAgAAAA==.Brud:BAAALgAECgMJCwAAAA==.Brunstan:BAACLgAFFH8TAAITAAUJfh9oEQBJAQATAAUJfh9oEQBJAQAuAAQKfxkAAhMACQnjILICAL0CABMACQnjILICAL0CAAAA.',
Bu='Bubbastump:BAAALgAECgQJBAAAAA==.',
By='Byakugan:BAACLgAFFH8cAAMFAAgJKhN1BQCDAQAFAAYJRxN1BQCDAQAUAAMJEgnlSgDBAAAuAAQKfyAABAUACQktH5oPAK8CAAUACQktH5oPAK8CABUAAQm+F78pAEEAABQAAQkHAQWpACUAAAAA.',
['Bø']='Bønitalèè:BAABLgAECn8kAAIWAAkJGQkHdwCJAQAWAAkJGQkHdwCJAQAAAA==.',
Ca='Cain:BAAALgADCgkJDwAAAA==.Calvisi:BAAALgAECgcJDgAAAA==.Calvisichaos:BAABLgAECn8+AAIXAAkJhBecBAAvAgAXAAkJhBecBAAvAgAAAA==.Cantero:BAAALgADCgUJBQAAAA==.Canthen:BAAALgAECggJDwAAAA==.Carcarnisa:BAAALgAECgQJBgAAAA==.Carm:BAAALgAECgQJBAAAAA==.',
Ce='Cenobia:BAAALgADCgUJCQAAAA==.',
Ch='Chaire:BAAALgADCgcJBgAAAA==.Chrysophylax:BAAALgAECgYJBgAAAA==.',
Co='Conky:BAAALgAECgMJBgAAAA==.Corndog:BAAALgADCgEJAQAAAA==.Cornix:BAAALgADCgEJAQAAAA==.Cosmicspark:BAABLgAECn8aAAIPAAcJ7wukqwAkAQAPAAcJ7wukqwAkAQAAAA==.',
Cr='Crentist:BAAALgAECgEJAQAAAA==.Critoliz:BAAALgAFFAMJAQAAAA==.Cropala:BAABLgAECn8oAAIPAAkJCBXQPQANAgAPAAkJCBXQPQANAgAAAA==.Cruelcodex:BAAALgAECgEJAQAAAA==.',
['Cà']='Càtfish:BAAALgADCgEJAQAAAA==.',
Da='Daca:BAAALgADCgMJAwAAAA==.Darkrequiem:BAAALgADCgkJCwAAAA==.Darkwingduck:BAAALgAECgQJBQAAAA==.Dave:BAAALgADCgQJBAAAAA==.Davros:BAAALgAECgMJCAAAAA==.',
De='Decapitator:BAAALgAECgMJAwAAAA==.Dednburied:BAAALgAECgIJAgAAAA==.Deleto:BAABLgAECn8uAAMBAAgJIxj5DQCUAQACAAcJ+BiBZQCaAQABAAgJ2BH5DQCUAQAAAA==.Dellandre:BAABLgAECn8eAAIYAAgJhAwWJgAgAQAYAAgJhAwWJgAgAQABLgAECgkJNAAQANgKAA==.Delta:BAABLgAECn8eAAIGAAgJwwhpgAAcAQAGAAgJwwhpgAAcAQAAAA==.Delti:BAAALgAECgUJBgABLgAECgkJHwAGAFcWAA==.Demondozer:BAAALgAECgMJBAABLgAECgcJCwAEAAAAAA==.Demony:BAAALgAECgEJAgABLgAFFAEJAQAEAAAAAA==.Denard:BAAALgAECgUJBgAAAA==.',
Di='Diabolist:BAACLgAFFH8IAAIDAAMJeAi3hwCyAAADAAMJeAi3hwCyAAAuAAQKfxgAAgMACQlgCCBpAGoBAAMACQlgCCBpAGoBAAAA.Digichowder:BAACLgAFFH8QAAMZAAQJTyA+HwAxAQAZAAMJPSQ+HwAxAQAOAAEJhhTtPgBIAAAuAAQKfyYAAw4ACQmxIy0EANsCAA4ACAkOIS0EANsCABkABQmNHiY5AGIBAAAA.Dirtygiri:BAAALgADCgEJAgAAAA==.',
Do='Doktaga:BAAALgAECgYJDgAAAA==.',
Dr='Draex:BAAALgADCgEJAQAAAA==.Dragonzord:BAAALgADCgEJAQAAAA==.Drbubbles:BAAALgADCgYJCAABLgAECgQJCQAEAAAAAA==.Drredd:BAAALgAECgQJBAAAAA==.',
['Dä']='Därkrävèn:BAAALgAECgYJDAAAAA==.',
['Dé']='Déspair:BAAALgAECgEJAQABLgAECgkJNAAQALcPAA==.',
Ea='Eama:BAAALgADCgIJAwAAAA==.',
Ed='Edin:BAAALgAECgcJBwABLgAFFAUJHQAKAEsTAA==.',
Eg='Eggfield:BAAALgAECgUJBgAAAA==.',
El='Eladora:BAAALgADCgEJAQAAAA==.Eldarr:BAABLgAECn85AAMXAAkJHSIXAQDxAgAXAAkJHSIXAQDxAgADAAUJ+hGTiwAjAQAAAA==.Eldhe:BAAALgAECgYJDwAAAA==.Eleos:BAAALgADCgMJBgAAAA==.Elistrae:BAABLgAECn8fAAMaAAkJ2RV+GQDUAQAaAAkJlQx+GQDUAQATAAgJKRc0MwCgAQAAAA==.',
Em='Emorri:BAAALgAECgYJBgAAAA==.',
En='Enazen:BAABLgAECn8fAAILAAkJWRppBQC9AgALAAkJWRppBQC9AgAAAA==.Endlol:BAABLgAECn8vAAMbAAkJFyF6CADIAgAbAAkJFyF6CADIAgAcAAEJUh/uYQBTAAABLgAFFAIJAwAEAAAAAA==.',
Er='Eredaria:BAAALgAFFAEJAQAAAA==.Ereshkigal:BAAALgADCgYJCwAAAA==.Ergo:BAACLgAFFH8aAAIWAAgJ7RCkHAATAgAWAAgJ7RCkHAATAgAuAAQKfyYAAhYACQmuIhsjAOYCABYACQmuIhsjAOYCAAAA.Eronel:BAABLgAECn8eAAICAAcJ7RoraQCSAQACAAcJ7RoraQCSAQAAAA==.',
Es='Esv:BAABLgAFFH8KAAINAAQJowYoHQCoAAANAAQJowYoHQCoAAABLgAFFAUJHgAWAEIVAA==.',
Ex='Excido:BAAALgAECgEJAgAAAA==.Exodiagold:BAAALgAECgEJAQAAAA==.',
Fa='Fadedharanir:BAAALgAECgIJAwAAAA==.Fadedheart:BAAALgAECgQJBwABLgAECgkJNAACAPIfAA==.Fadedmystic:BAAALgAECgQJBAAAAA==.Fadednight:BAABLgAECn80AAMCAAkJ8h/4FwC1AgACAAkJ8h/4FwC1AgAYAAEJ1QEVbQAPAAAAAA==.Faeyir:BAACLgAFFH8TAAIWAAQJIg84YgAkAQAWAAQJIg84YgAkAQAuAAQKfyIAAhYACQnDHT9QAEYCABYACQnDHT9QAEYCAAAA.Fallingmoon:BAABLgAECn8nAAMSAAkJqCBzDwDSAgASAAkJqCBzDwDSAgATAAEJKRDmigAwAAAAAA==.Fangrage:BAAALgAECgYJBAAAAA==.Fatherlode:BAACLgAFFH8KAAIWAAMJwBgfgADbAAAWAAMJwBgfgADbAAAuAAQKfysAAhYACQmUIfYcAKwCABYACQmUIfYcAKwCAAAA.Fathertouchi:BAAALgAECgMJAwAAAA==.',
Fe='Feltpen:BAAALgAECgUJBQAAAA==.Femcelibate:BAAALgADCgcJCAAAAA==.Fentenjoyer:BAAALgAECgcJDwAAAA==.Fernfondler:BAAALgAFFAIJAwAAAA==.',
Fl='Flashylights:BAAALgADCgYJBgAAAA==.',
Fo='Fontane:BAAALgADCgYJBwAAAA==.Forcebolt:BAAALgADCgMJAwAAAA==.',
Fr='Fredgoofin:BAAALgAECgIJAgAAAA==.Freecookies:BAAALgAECgYJCQAAAA==.Frostybop:BAAALgAECgMJBAABLgAECgIJAgAEAAAAAA==.Frostybreath:BAAALgAECgIJAgAAAA==.Frostybrews:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.Frostydh:BAAALgAECgMJAwABLgAECgIJAgAEAAAAAA==.Frostytotems:BAAALgAECgQJBgAAAA==.Fróstblight:BAAALgAECgkJCAAAAA==.',
Fu='Furryiosa:BAAALgADCgYJBgAAAA==.',
Ga='Gauntodimm:BAAALgAECgYJCgAAAA==.',
Gi='Gilberticus:BAABLgAECn8bAAMaAAYJPRu+HwCgAQAaAAYJPRu+HwCgAQASAAQJXBYEqwDpAAABLgAECgkJUAAdAMUiAA==.Gishmou:BAABLgAECn8fAAIUAAkJwRj3JQAoAgAUAAkJwRj3JQAoAgAAAA==.',
Go='Goldblade:BAABLgAECn8gAAIPAAgJWhccUwDPAQAPAAgJWhccUwDPAQAAAA==.',
Gr='Grayhair:BAAALgAECgQJCAAAAA==.Greyoll:BAAALgAECgYJCAAAAA==.Grimling:BAAALgAFFAEJAQABLgAFFAYJEgAHAJcVAA==.Grindlewald:BAAALgAECgIJAgAAAA==.',
Gu='Gutted:BAACLgAFFH8gAAMYAAgJCyPbAAAmAgAYAAgJCyPbAAAmAgACAAEJxQxxEgE8AAAuAAQKfx0AAhgACQkZJr0BAGcDABgACQkZJr0BAGcDAAAA.',
['Gä']='Gärin:BAAALgADCggJFAAAAA==.',
Ha='Hanna:BAAALgAFFAEJAQABLgAFFAgJIAAYAAsjAA==.Harleyswar:BAAALgADCgEJAQAAAA==.',
He='Hellmaw:BAAALgAECgYJCwAAAA==.',
Hi='Highly:BAAALgADCgcJCwAAAA==.',
Ho='Holianna:BAAALgAECgIJAgAAAA==.Hollowheart:BAABLgAECn82AAMUAAkJ7hyvDwDRAgAUAAkJ7hyvDwDRAgAVAAEJkyE7MgBkAAAAAA==.Holycourtney:BAAALgADCgkJEQAAAA==.Holyknight:BAAALgADCgEJAQAAAA==.Hotsausage:BAAALgAECgMJAwAAAA==.Hoved:BAAALgADCgEJAQAAAA==.',
Hu='Huang:BAAALgAECgMJAwAAAA==.',
Hy='Hylanna:BAAALgAECgcJDAAAAA==.Hyorinmaru:BAAALgAFFAEJAgAAAA==.',
['Hó']='Hónor:BAAALgADCgMJAwABLgAECgkJNAAQALcPAA==.',
Ic='Ici:BAABLgAECn8zAAMPAAkJAAj2hwBfAQAPAAkJAAj2hwBfAQAJAAQJuA5qXADCAAAAAA==.',
If='Iffybacon:BAAALgAECgIJAgABLgAECgQJCwAEAAAAAA==.',
Ik='Ikilledkeny:BAAALgAFFAMJAQAAAA==.',
Im='Imlerith:BAAALgADCgQJBgAAAA==.',
In='Intensifies:BAAALgAECgcJEgAAAA==.',
Ip='Ippo:BAAALgADCgEJAQAAAA==.',
Is='Isabellà:BAAALgAECgkJEwABLgAECgkJJwAeAL4MAA==.Iskothar:BAABLgAECn8yAAIQAAkJQSGiAgAAAwAQAAkJQSGiAgAAAwAAAA==.',
Iv='Ivarboneless:BAABLgAECn8YAAIJAAcJCyAREwB3AgAJAAcJCyAREwB3AgAAAA==.',
Ja='Jackz:BAAALgAECgkJCQAAAA==.Jackzlock:BAAALgAECgkJAQAAAA==.Jakethemage:BAAALgADCgUJCAAAAA==.Jankball:BAAALgAFFAMJAQAAAA==.Jatkal:BAAALgAFFAEJAQAAAA==.Jayreezy:BAAALgAECgMJAwAAAA==.',
Je='Jefftrep:BAAALgAECgQJAwAAAA==.Jerihatrix:BAAALgAECgEJAQAAAA==.',
Ji='Jimmylahey:BAAALgAECgMJAwAAAA==.',
Jo='Jonah:BAAALgADCgEJAQAAAA==.',
Ka='Kaina:BAAALgADCgYJCQAAAA==.Kakidruid:BAAALgAECgIJAwAAAA==.Kalfu:BAABLgAECn8UAAMbAAkJygxgKgB+AQAbAAkJygxgKgB+AQAfAAgJFwmeMABaAQAAAA==.',
Ke='Ketesh:BAABLgAECn88AAIgAAkJzSBpAwDuAgAgAAkJzSBpAwDuAgABLgAFFAUJHQAKAEsTAA==.',
Ki='Kilorean:BAAALgAECgcJCAAAAA==.Kirae:BAAALgADCgkJGQABLgAECgkJMgAQAEEhAA==.',
Kl='Kleanse:BAAALgAFFAMJAQAAAA==.',
Kn='Knastey:BAABLgAECn8VAAQeAAYJ4Be1NQA9AQAeAAYJ4Be1NQA9AQAMAAYJZAqbcQABAQAhAAEJWxKCMgA3AAAAAA==.Knasty:BAAALgADCgEJAQAAAA==.',
Ko='Kodera:BAABLgAECn8gAAIKAAYJQQUuZgClAAAKAAYJQQUuZgClAAAAAA==.',
Kr='Krej:BAABLgAECn8XAAIYAAkJMBwADwAaAgAYAAkJMBwADwAaAgABLgAFFAYJEgAHAJcVAA==.Krisskringle:BAAALgAECgMJBgAAAA==.',
Ku='Kuromori:BAAALgADCgYJBgAAAA==.',
Ky='Kyronix:BAAALgAECgMJBwAAAA==.',
['Kê']='Kênpachi:BAAALgAECgYJDgAAAA==.',
La='Landrey:BAAALgADCgkJCQAAAA==.Langarde:BAABLgAECn8fAAINAAkJCxCMFgCOAQANAAkJCxCMFgCOAQAAAA==.Laoghaire:BAABLgAECn8YAAIHAAcJ+AO2QQCrAAAHAAcJ+AO2QQCrAAAAAA==.',
Le='Leonz:BAACLgAFFH8bAAIZAAgJDhspAwBNAgAZAAgJDhspAwBNAgAuAAQKfy4AAhkACQmaJAgFABIDABkACQmaJAgFABIDAAAA.Leonzs:BAAALgAECggJEAAAAA==.Letharanos:BAECLgAFFH8HAAMCAAMJkheQiwDuAAACAAMJkheQiwDuAAAYAAEJfQc/QgAoAAAuAAQKfycAAwIACQl0Gd9DAPUBAAIACQl0Gd9DAPUBABgAAQl7DsNfACgAAAAA.',
Li='Liraffemynn:BAACLgAFFH8YAAIiAAUJshmlHACBAQAiAAUJshmlHACBAQAuAAQKfz4AAiIACQmOI7EDAHsDACIACQmOI7EDAHsDAAAA.Liralynn:BAAALgADCgUJBQAAAA==.',
Lk='Lkynyx:BAAALgADCgYJAQAAAA==.',
Lo='Lonranir:BAAALgAECgYJCwAAAA==.Lostinlight:BAAALgAECgYJBgAAAA==.',
Lu='Lucii:BAAALgADCgEJAQABLgAFFAgJIAAYAAsjAA==.Luckylucy:BAABLgAECn8XAAIcAAYJhhYeLgBZAQAcAAYJhhYeLgBZAQAAAA==.',
Ma='Madarauchiha:BAABLgAECn8aAAICAAYJ6BpwggB+AQACAAYJ6BpwggB+AQAAAA==.Magus:BAAALgADCgkJFgABLgAECgMJCAAEAAAAAA==.Maldran:BAABLgAECn8jAAIUAAcJjh1MKgAPAgAUAAcJjh1MKgAPAgAAAA==.Maling:BAAALgAECgEJAQAAAA==.Manderpants:BAABLgAECn8fAAISAAcJCAr9gQA3AQASAAcJCAr9gQA3AQAAAA==.Marien:BAABLgAECn8fAAIYAAkJHBlFDQA1AgAYAAkJHBlFDQA1AgAAAA==.Marty:BAAALgAECgIJAwAAAA==.Maxus:BAAALgADCgUJBQAAAA==.',
Mb='Mbbin:BAACLgAFFH8MAAIWAAMJFyXyUgA9AQAWAAMJFyXyUgA9AQAuAAQKfyoAAhYACQntIYUcAK4CABYACQntIYUcAK4CAAAA.',
Me='Mehuman:BAABLgAECn8aAAIPAAcJzxE6iwBZAQAPAAcJzxE6iwBZAQAAAA==.Mehumanhuntr:BAAALgAECgUJBwAAAA==.Mehumanlock:BAABLgAECn8jAAIXAAkJ+xHaCQClAQAXAAkJ+xHaCQClAQAAAA==.Merlinn:BAAALgADCgkJCwAAAA==.Merran:BAAALgADCgEJAQAAAA==.Metal:BAAALgADCgQJBAAAAA==.Meworgendk:BAAALgAECgYJDgAAAA==.',
Mh='Mhoo:BAAALgADCgcJBwAAAA==.',
Mi='Miriym:BAAALgADCgEJAQAAAA==.Miräj:BAAALgAECgcJDAAAAA==.Mistyblue:BAAALgADCgEJAQAAAA==.Miya:BAAALgADCgcJDQAAAA==.',
Mo='Moonscale:BAAALgAECgMJBAAAAA==.Mordaci:BAAALgADCgQJBQABLgAFFAIJAwAEAAAAAA==.Mordekrieg:BAABLgAFFH8FAAICAAMJSgm4rwC+AAACAAMJSgm4rwC+AAAAAA==.Mortstan:BAAALgAECgcJDQAAAA==.',
My='Myash:BAAALgAECgcJDQAAAA==.',
['Må']='Månni:BAAALgADCgYJBwAAAA==.',
['Mé']='Mélusine:BAAALgADCgEJAQAAAA==.',
Na='Nailia:BAAALgAECgcJCwAAAA==.Nailz:BAABLgAECn8fAAIGAAkJVxaETgCXAQAGAAkJVxaETgCXAQAAAA==.Nakama:BAAALgADCgYJBgABLgAECgkJNAAFAJgMAA==.Nardog:BAAALgAECgEJAQAAAA==.Narie:BAAALgAECggJCQAAAA==.Nasaug:BAAALgAECgUJCwABLgAECgkJNAAQALcPAA==.',
Ne='Ned:BAAALgAECgEJAQAAAA==.Neuse:BAAALgAECggJEwAAAA==.',
Ni='Nightlion:BAABLgAECn8dAAIgAAcJ3g/bJQAhAQAgAAcJ3g/bJQAhAQAAAA==.Nillius:BAAALgADCgIJAgAAAA==.Nisu:BAAALgAECgEJAQAAAA==.',
No='Noahdh:BAAALgAECgMJAwABLgAFFAgJHwADABAYAA==.Noahpriest:BAAALgAECgMJAwABLgAFFAgJHwADABAYAA==.Noahvoker:BAAALgAECggJEQABLgAFFAgJHwADABAYAA==.Noahwarlock:BAACLgAFFH8fAAQDAAgJEBiuHwDIAQADAAYJTh2uHwDIAQAXAAMJXxHTCgDqAAAjAAEJkSO7HwBQAAAuAAQKfzEABAMACQmFJNcEAEEDAAMACAlsJNcEAEEDABcABAl0IkEaAHsBACMAAwmsI4IWAM0AAAAA.Nonsensical:BAAALgADCgUJBQABLgAECgYJIgAiAEYiAA==.Nook:BAAALgADCgUJBgAAAA==.Nowere:BAAALgADCgcJBwAAAA==.Noxander:BAAALgAECgEJAQAAAA==.',
Ny='Nym:BAAALgAECgkJEQAAAA==.',
['Nâ']='Nârenth:BAAALgADCgMJAwAAAA==.',
Oa='Oaths:BAAALgAECgcJEQAAAA==.',
Oh='Ohmylantä:BAABLgAECn8dAAIWAAgJPg20igBfAQAWAAgJPg20igBfAQAAAA==.Ohmylantå:BAAALgADCgUJCAAAAA==.',
On='Ondeane:BAAALgADCgEJAQAAAA==.Onumae:BAABLgAECn8XAAIPAAkJcRpvMQA5AgAPAAkJcRpvMQA5AgAAAA==.',
Op='Oprime:BAAALgADCgMJAwAAAA==.',
Or='Orbeck:BAAALgAECggJCAABLgAFFAgJHQAIAIocAA==.Ormond:BAABLgAECn8cAAMJAAcJbRR+KgC6AQAJAAcJbRR+KgC6AQAPAAUJPAX6GQGXAAAAAA==.Orochinchin:BAAALgAECgUJBQABLgAFFAgJIAAYAAsjAA==.',
Os='Oscarmike:BAAALgADCgcJDQAAAA==.',
Oz='Ozlon:BAAALgAECgcJEwAAAA==.',
['Oâ']='Oâth:BAABLgAECn8tAAMkAAkJpg12DQB4AQAkAAkJpg12DQB4AQAHAAMJRgbAYwBCAAAAAA==.',
Pa='Pachane:BAAALgAECgQJCwAAAA==.Paldozer:BAAALgAECgUJCQABLgAECgcJCwAEAAAAAA==.Pallywacker:BAACLgAFFH8FAAIQAAIJtgmAEgBjAAAQAAIJtgmAEgBjAAAuAAQKfzEAAhAACAnaEmEUAIYBABAACAnaEmEUAIYBAAAA.Pankins:BAAALgAECgMJAwAAAA==.Panzerkan:BAAALgAECgEJAQAAAA==.Panzerkìn:BAAALgAECgcJCAAAAA==.',
Pe='Percymorris:BAAALgADCgYJBwAAAA==.Peythilly:BAAALgAECgQJBAAAAA==.',
Pi='Pigishdog:BAABLgAECn9TAAMDAAkJyR2NEwCwAgADAAkJyR2NEwCwAgAXAAEJ1RHYPAA2AAAAAA==.Pikon:BAAALgADCgkJDQAAAA==.',
Po='Pokeabear:BAAALgAECgYJEAABLgAECgcJEAAEAAAAAA==.Pokethedruid:BAAALgAECgEJAQABLgAECgEJBwAEAAAAAA==.Pokethemonk:BAAALgAECgEJBwAAAA==.Poshingtang:BAABLgAECn8pAAQUAAkJqQwSRACaAQAUAAkJqQwSRACaAQAFAAgJHhG8NgB4AQAVAAMJSwP+JQB3AAAAAA==.',
Pu='Pulsar:BAAALgAECgQJBwAAAA==.Punchies:BAAALgADCggJDQAAAA==.',
Qu='Quatrain:BAABLgAECn80AAMFAAkJmAxnOABTAQAFAAgJ1g1nOABTAQAUAAgJrxDFWwBGAQAAAA==.Quintessence:BAAALgAECgMJAwAAAA==.',
Ra='Rabidbutt:BAAALgAFFAMJBAABLgAFFAcJGAALAF0gAA==.Ragerunner:BAAALgADCgkJEwAAAA==.Rakarg:BAABLgAECn8ZAAICAAUJDBjszQDpAAACAAUJDBjszQDpAAAAAA==.Ravenus:BAAALgAECgEJAQAAAA==.',
Re='React:BAAALgAECggJCAABLgAFFAIJAwAEAAAAAA==.Redemptor:BAAALgAECgUJBQAAAA==.Refund:BAAALgAECgEJAQAAAA==.Regalbacon:BAAALgAECgMJAwAAAA==.Reygina:BAABLgAECn8ZAAIJAAYJygJVXwC3AAAJAAYJygJVXwC3AAAAAA==.',
Ri='Rickÿ:BAAALgAECgEJAQAAAA==.Rikku:BAAALgAECggJCAABLgAFFAgJHAAFACoTAA==.Ripndip:BAAALgAFFAMJAQAAAA==.Riprock:BAAALgAECgIJAQABLgAFFAMJAQAEAAAAAA==.Rixas:BAAALgAECgEJAQABLgAECgkJLgADAPwcAA==.',
Rn='Rn:BAACLgAFFH8FAAIOAAQJShitGQAUAQAOAAQJShitGQAUAQAuAAQKfx4AAw4ACQklIkEBAEYDAA4ACQkIIkEBAEYDABkABwkvIyQpABcCAAEuAAUUCAkiAA4AgyQA.',
Ro='Rodeo:BAAALgAECgMJBQAAAA==.Roguehiro:BAABLgAECn8oAAIQAAgJxSHsBQCKAgAQAAgJxSHsBQCKAgAAAA==.Rooter:BAACLgAFFH8YAAILAAcJXSAzBACWAgALAAcJXSAzBACWAgAuAAQKfz0AAwsACQkRJBoBAJ8DAAsACQkRJBoBAJ8DAAoABwnsGS8lALQBAAAA.Roronoaxd:BAAALgADCgMJAwAAAA==.Rosalynñ:BAABLgAECn8pAAIXAAgJMgoMFAAMAQAXAAgJMgoMFAAMAQAAAA==.',
Ru='Ruikhai:BAAALgADCgMJBQABLgADCgkJBwAEAAAAAA==.Ruto:BAAALgAECgEJAQABLgAFFAMJAQAEAAAAAA==.',
Sa='Saelis:BAACLgAFFH8VAAIMAAUJnhalIABNAQAMAAUJnhalIABNAQAuAAQKfx8AAwwACQnfINYLAAADAAwACQnfINYLAAADACEABgnwGdkTAH4BAAAA.Salen:BAAALgAECgEJAQAAAA==.Samshara:BAAALgADCgcJDAABLgAECgkJQwAaAH4dAA==.Saptapper:BAAALgAECgIJAgAAAA==.Saracenio:BAAALgADCgEJAQAAAA==.',
Sc='Schnem:BAAALgAECggJCgAAAA==.Scrawni:BAAALgAECgcJCAABLgAFFAYJEgAHAJcVAA==.Scrounge:BAAALgAFFAEJAQABLgAFFAMJCAADAHgIAA==.',
Se='Securìty:BAAALgAECgQJBQAAAA==.Selyane:BAAALgADCgkJCQAAAA==.Seong:BAACLgAFFH8dAAIIAAgJihyFBQA2AgAIAAgJihyFBQA2AgAuAAQKfyEAAggACQmAIgUFADkDAAgACQmAIgUFADkDAAAA.Seongdh:BAAALgAECggJDQABLgAFFAgJHQAIAIocAA==.Seongwar:BAAALgAECgMJAwAAAA==.Seraphinà:BAAALgAECgYJEAABLgAECgkJJwAeAL4MAA==.',
Sh='Shadowdooms:BAABLgAECn8WAAMCAAgJFBkfYQDQAQACAAgJFBkfYQDQAQABAAEJSxf2FABFAAAAAA==.Shadowfur:BAAALgAECggJCAABLgAECgkJPAAJAN8eAA==.Shamynna:BAAALgAECgMJBAAAAA==.Sharreth:BAAALgAECgIJAgAAAA==.Shii:BAAALgADCgUJBQAAAA==.Shimera:BAABLgAECn8yAAISAAkJNhM1PQDpAQASAAkJNhM1PQDpAQAAAA==.Shish:BAAALgAECggJCwAAAA==.Shizukura:BAAALgADCgEJAQAAAA==.Shockawar:BAACLgAFFH8WAAIZAAUJeRwxAwDEAQAZAAUJeRwxAwDEAQAuAAQKfxkAAhkACQmrHmYYAIgCABkACQmrHmYYAIgCAAAA.Shooter:BAAALgADCgIJAgAAAA==.Shootrmcgavn:BAACLgAFFH8eAAQSAAYJ8yJWIgB1AQASAAUJrx9WIgB1AQAaAAQJRSFrDABfAQATAAQJNiDGEAAqAQAuAAQKfxsABBIACAk8IdMVAIkCABIABwnxIdMVAIkCABMABwlKIcoaAFMCABoAAwm3IVIxACEBAAAA.Shu:BAAALgAFFAIJAgAAAA==.Shuletaa:BAAALgAECgIJBAAAAA==.Shïsh:BAAALgADCgcJBwABLgAECggJCwAEAAAAAA==.',
Si='Silverwolf:BAAALgADCgEJAQAAAA==.Sinestra:BAAALgAECgEJAQAAAA==.',
Sk='Skibidi:BAAALgAECgcJDAABLgAFFAMJEwAWABcfAA==.',
Sl='Slagscar:BAAALgAFFAIJAQAAAA==.Slaughterhse:BAABLgAECn8XAAIWAAYJ5gOL+AC0AAAWAAYJ5gOL+AC0AAAAAA==.Slootar:BAABLgAECn8UAAQMAAcJ5xuIJAAoAgAMAAcJ5xuIJAAoAgAeAAIJuxBfbABuAAAhAAIJMAZoVQAsAAAAAA==.Slugs:BAAALgAECgUJCAAAAA==.',
Sn='Snqwflake:BAABLgAECn8VAAIiAAgJ7xb8FQAUAgAiAAgJ7xb8FQAUAgAAAA==.',
So='Solareth:BAAALgAECgEJAgAAAA==.Solthin:BAAALgAFFAMJAQAAAA==.Somebeotch:BAAALgADCgYJBgAAAA==.Somerled:BAABLgAECn9DAAIaAAkJfh1cCACZAgAaAAkJfh1cCACZAgAAAA==.',
Sp='Spyroid:BAAALgAECgUJAQAAAA==.',
St='Static:BAAALgADCgcJBwABLgAECgYJCgAEAAAAAA==.',
Su='Sunstrike:BAAALgAECgEJAgAAAA==.',
Sy='Sylvanna:BAAALgADCgQJBAAAAA==.',
Ta='Tabul:BAAALgADCgUJBAAAAA==.Takka:BAABLgAECn8aAAIUAAgJHR29FwCJAgAUAAgJHR29FwCJAgAAAA==.Talden:BAABLgAECn9FAAMPAAkJMhxjHwCKAgAPAAkJMhxjHwCKAgAQAAMJzRCaRQBMAAAAAA==.Talkamar:BAABLgAECn8iAAIdAAkJ6RBmIACoAQAdAAkJ6RBmIACoAQAAAA==.Taylorswift:BAABLgAECn83AAIWAAkJ8xgfLABnAgAWAAkJ8xgfLABnAgAAAA==.Tazzaar:BAAALgAECgMJAwAAAA==.',
Th='Thaelios:BAAALgADCgEJAQAAAA==.Thekourge:BAABLgAECn80AAIQAAkJ2AoSGwA9AQAQAAkJ2AoSGwA9AQAAAA==.Thenard:BAABLgAECn8jAAISAAgJPBO2VQCfAQASAAgJPBO2VQCfAQAAAA==.Thukunaenhan:BAAALgAECgQJBAABLgAFFAMJEwAWABcfAA==.Thukunamage:BAACLgAFFH8TAAIWAAMJFx+RbwAHAQAWAAMJFx+RbwAHAQAuAAQKfyoAAhYACQmyIPggAJgCABYACQmyIPggAJgCAAAA.',
Ti='Tibarius:BAAALgADCgkJEgAAAA==.Tili:BAAALgADCgkJDQAAAA==.Tinaraeda:BAAALgAECgMJAwAAAA==.',
To='Tomislav:BAABLgAECn8lAAQDAAkJcBtfKwAsAgADAAcJrBlfKwAsAgAXAAQJ2xozIACoAAAjAAEJlA7oOwA4AAAAAA==.Tomuchmakeup:BAAALgAECgEJAQAAAA==.Touritos:BAABLgAECn8eAAIFAAkJdREtKgCdAQAFAAkJdREtKgCdAQAAAA==.',
Tr='Trimblestein:BAAALgAECgUJCQAAAA==.Troyka:BAAALgAECgEJAQAAAA==.Truefitt:BAAALgAECgYJEwAAAA==.',
Tu='Tulikettwo:BAAALgAECgEJAQAAAA==.Tulirenpo:BAAALgAECgUJBQAAAA==.Tunk:BAAALgAFFAMJAQAAAA==.Tuskal:BAAALgAECgIJAwAAAA==.',
Tw='Twogora:BAAALgAECgYJCQAAAA==.Twohoofy:BAAALgADCgcJBgAAAA==.',
Ty='Tydes:BAABLgAECn8bAAMlAAgJ6RbMEwB4AgAlAAgJ6RbMEwB4AgAmAAEJtgtBHQBBAAAAAA==.Tydru:BAAALgAFFAMJAQAAAA==.Tyler:BAACLgAFFH8LAAIGAAQJfhXYDwBPAQAGAAQJfhXYDwBPAQAuAAQKfxsAAgYACAkOHTgcAKkCAAYACAkOHTgcAKkCAAAA.Tystin:BAAALgADCgQJBQABLgADCgkJBwAEAAAAAA==.',
Ud='Uddermilk:BAABLgAECn8YAAIeAAcJ5wf+TgDNAAAeAAcJ5wf+TgDNAAAAAA==.',
Um='Umariel:BAAALgAFFAMJAQAAAA==.',
Va='Valina:BAAALgADCgIJAgAAAA==.Valissar:BAAALgAECgMJBwAAAA==.Valkyrja:BAAALgAECgEJAQAAAA==.Valr:BAABLgAECn80AAIQAAkJtw/nFgBoAQAQAAkJtw/nFgBoAQAAAA==.Vancliffe:BAAALgAECgQJBAABLgAFFAYJEgAHAJcVAA==.Vandreu:BAAALgADCgUJBQAAAA==.',
Ve='Verpally:BAAALgADCgMJAwAAAA==.',
Vi='Viparia:BAAALgAECgkJAgAAAA==.Virulent:BAAALgAECgMJAwAAAA==.',
Vo='Voloaura:BAAALgADCgMJAwAAAA==.',
Vs='Vse:BAACLgAFFH8eAAIWAAUJQhUDVQA5AQAWAAUJQhUDVQA5AQAuAAQKfy4AAhYACAl8G4hHAAMCABYACAl8G4hHAAMCAAAA.Vsesosorry:BAABLgAFFH8VAAIUAAQJZxQ1NQAIAQAUAAQJZxQ1NQAIAQABLgAFFAUJHgAWAEIVAA==.Vsè:BAAALgADCgUJBQABLgAFFAUJHgAWAEIVAA==.',
Vy='Vyke:BAAALgAECgkJEQABLgAFFAgJHQAIAIocAA==.',
['Ví']='Ví:BAAALgAECgYJBgAAAA==.',
Wa='Wammo:BAAALgAECgYJCgAAAA==.Waq:BAAALgADCgMJAwAAAA==.Wardozer:BAAALgAECgcJCwAAAA==.Warlockedin:BAAALgAECgYJDQAAAA==.',
We='Weierstrass:BAAALgAFFAEJAQABLgAFFAgJIAAYAAsjAA==.',
Wo='Worgenkrantz:BAABLgAECn8nAAMeAAkJvgwlKgCAAQAeAAkJvgwlKgCAAQAMAAcJeAJQkgCrAAAAAA==.',
Wr='Wrathlor:BAAALgADCgcJBQAAAA==.Wrenlyn:BAACLgAFFH8SAAMHAAYJlxWnEQAVAQAHAAUJ5RWnEQAVAQAGAAIJKQwweQCHAAAuAAQKfzAAAwcACAlsI5kOADkCAAcACAntH5kOADkCACQAAglCE0AlAHIAAAAA.',
Wu='Wukain:BAAALgADCgEJAQAAAA==.',
Xa='Xanatas:BAAALgAECgYJCQABLgAECgkJMgAQAEEhAA==.',
Xo='Xolòtl:BAABLgAECn8gAAINAAgJUBcZFADLAQANAAgJUBcZFADLAQABLgAFFAYJEgAHAJcVAA==.Xoss:BAAALgAFFAMJAQAAAA==.',
Yg='Yggdrasali:BAAALgAECgQJBgABLgAFFAIJBQAWAJIaAA==.',
Yi='Yin:BAAALgAECgcJCAAAAA==.',
Yo='Yourhero:BAAALgAECgEJAQAAAA==.',
Ys='Yserra:BAAALgAECgcJDAAAAA==.',
Za='Zaerine:BAAALgAECgYJBgAAAA==.Zakuso:BAAALgAECgQJCQAAAA==.Zalatha:BAAALgADCgEJAQAAAA==.Zalyia:BAABLgAECn8uAAIbAAkJlA0QJgCaAQAbAAkJlA0QJgCaAQAAAA==.',
Ze='Zephinar:BAABLgAECn8ZAAIWAAgJcBVpaQADAgAWAAgJcBVpaQADAgAAAA==.Zexpert:BAABLgAECn8cAAQnAAgJSReiDQAAAgAnAAcJIhiiDQAAAgAKAAcJnhUvKAB8AQALAAQJfgwFNADNAAAAAA==.',
Zq='Zquestion:BAAALgAECgIJBAABLgAECggJHAAnAEkXAA==.',
Zu='Zulblade:BAABLgAECn8SAAIGAAgJORqFMAA5AgAGAAgJORqFMAA5AgAAAA==.Zulpally:BAABLgAECn8aAAQPAAUJQBaQyQD6AAAPAAQJxhiQyQD6AAAJAAMJyRCQcgCxAAAQAAQJ+QiuMQCIAAAAAA==.',
['Zô']='Zôrt:BAAALgAECggJEAAAAA==.',
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
