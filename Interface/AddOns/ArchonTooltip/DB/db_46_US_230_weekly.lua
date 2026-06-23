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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Unknown-Unknown','Paladin-Protection','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Brewmaster','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Restoration','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Shaman-Enhancement','Mage-Frost','Warlock-Destruction','DeathKnight-Blood','Warrior-Fury','Hunter-Survival','Priest-Shadow','Priest-Holy','Monk-Windwalker','Druid-Balance','Priest-Discipline','Druid-Guardian','Druid-Feral','Monk-Mistweaver','Warlock-Affliction','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=46,date='2026-06-21',data={Ab='Abaddon:BAABLgAECn8tAAMBAAkJTB8pBwAoAgABAAgJ6R0pBwAoAgACAAgJrBzuRQDwAQAAAA==.Abessedge:BAAALgAECgcJCwAAAA==.',
Ac='Acidtears:BAAALgAECgEJAQAAAA==.Ackris:BAABLgAECn8zAAIDAAkJKR0HCgAuAwADAAkJKR0HCgAuAwAAAA==.Ackrisa:BAAALgAECgUJCAAAAA==.Acris:BAAALgAECgYJCwABLgAECgkJMwADACkdAA==.',
Ae='Aedimus:BAAALgADCgcJCQAAAA==.',
Al='Aleathris:BAEALgADCgcJBwABLgAECgQJBAAEAAAAAA==.Alistan:BAAALgAECgEJAQAAAA==.Alka:BAAALgADCgEJAQAAAA==.Alkaios:BAAALgAECgYJBgABLgAFFAMJBQAFAGMLAA==.Alor:BAAALgAECgIJBAABLgAECgkJNAAGAJgMAA==.Alpyne:BAAALgAECgcJEgAAAA==.',
Am='Amaimon:BAABLgAECn8aAAMHAAgJDhWSVgCDAQAHAAgJDhWSVgCDAQAIAAEJawx7cAAvAAABLgAFFAgJHAAGACoTAA==.Amalthaea:BAAALgAECgcJEwABLgAECgkJLgAJAGMWAA==.Amnoon:BAABLgAECn80AAIKAAkJ+BfoEwBwAgAKAAkJ+BfoEwBwAgAAAA==.Amri:BAACLgAFFH8eAAMLAAYJPRWoMAD/AAALAAUJSxOoMAD/AAAMAAIJ5QVbJQBvAAAuAAQKfykAAwsACAlOGTcBACYBAAsACAlOGTcBACYBAAwABglADVQiAN0AAAAA.',
An='Andarnáurram:BAAALgAECgIJAgAAAA==.Angelfox:BAAALgAECgQJAgAAAA==.',
Aq='Aquas:BAAALgAECgUJCwAAAA==.',
Ar='Ardrhys:BAAALgAFFAQJBAAAAA==.Arthurcarrot:BAAALgAECgQJBwAAAA==.Artikin:BAAALgAECgkJCwABLgAFFAYJEgAIAJcVAA==.',
As='Assasinateu:BAAALgADCgMJAwAAAA==.Asûná:BAAALgAECggJEAAAAA==.',
At='Atreus:BAABLgAECn8mAAMIAAkJ7BxeDgA/AgAIAAkJ7BxeDgA/AgAHAAEJVAsrIAEqAAAAAA==.Atzalan:BAABLgAECn8UAAINAAYJpwnpcwD7AAANAAYJpwnpcwD7AAAAAA==.',
Au='Automagic:BAAALgAECgEJAgAAAA==.',
Av='Avondwella:BAABLgAECn8vAAMOAAkJfhByGgBmAQAOAAkJfhByGgBmAQAPAAEJ+wnERAAvAAAAAA==.',
Az='Azrikam:BAAALgAECgYJCAAAAA==.',
Ba='Baku:BAAALgAECgYJBgABLgAFFAYJEgAIAJcVAA==.Baldyguy:BAAALgADCgcJCgAAAA==.Balm:BAABLgAECn8xAAINAAkJCBrAIQA6AgANAAkJCBrAIQA6AgAAAA==.Balton:BAAALgAECgIJAwAAAA==.Barbsimpsonn:BAAALgAECgEJAQAAAA==.Bashalot:BAAALgAECgUJBgAAAA==.',
Be='Beastcloud:BAAALgAECgMJAwABLgAECgkJJgAIAOwcAA==.Behindyou:BAAALgAECggJBAABLgAECgkJKQAQAAgVAA==.Bermin:BAAALgADCgUJAwAAAA==.',
Bi='Biblepimp:BAAALgAFFAEJAQAAAA==.Bigwilliam:BAAALgADCgEJAQAAAA==.',
Bl='Blackmarker:BAABLgAECn8cAAICAAgJ/BTBXQCvAQACAAgJ/BTBXQCvAQAAAA==.Blackmouser:BAAALgADCgQJBAAAAA==.Bloodpac:BAAALgAECgEJAQAAAA==.',
Bm='Bmo:BAABLgAECn8VAAIQAAcJZSB1SAAJAgAQAAcJZSB1SAAJAgAAAA==.',
Bo='Bodyguardwyn:BAAALgAECgEJAQAAAA==.Bogle:BAACLgAFFH8FAAMQAAIJOQwOqgBtAAAQAAIJUAUOqgBtAAAFAAIJOQwOCAA2AAAuAAQKfy8AAwUACQnYI7MCAP8CAAUACQnYI7MCAP8CABAAAwnyFt3iANoAAAAA.Bonedmuch:BAAALgAECgcJDQABLgAECgkJLgAJAGMWAA==.Bow:BAAALgAECgIJAwAAAA==.',
Br='Brasi:BAAALgAECgIJAgAAAA==.Bratton:BAABLgAECn8aAAIRAAcJ6wa1EwDRAAARAAcJ6wa1EwDRAAAAAA==.Breadria:BAAALgAECgEJAwABLgAFFAMJCQASAFkGAA==.Bremitin:BAAALgADCggJCAABLgAFFAMJBQAFAGMLAA==.Bremitus:BAAALgADCgkJCQABLgAFFAMJBQAFAGMLAA==.Brewcrew:BAAALgAECgkJBwAAAA==.Brewey:BAAALgAFFAEJAQAAAA==.Brewmongster:BAAALgAECgQJBQAAAA==.Brimscythe:BAABLgAECn8bAAIHAAgJ5B+wNwAXAgAHAAgJ5B+wNwAXAgAAAA==.Brud:BAAALgAFFAMJAwAAAA==.Brunstan:BAACLgAFFH8TAAITAAUJfh8VEgBDAQATAAUJfh8VEgBDAQAuAAQKfxkAAhMACQnjIL4CALwCABMACQnjIL4CALwCAAAA.',
Bu='Bubbastump:BAAALgAECgQJBAAAAA==.',
By='Byakugan:BAACLgAFFH8cAAMGAAgJKhN1BQCDAQAGAAYJRxN1BQCDAQAUAAMJEgl7TADBAAAuAAQKfyAABAYACQktH5oPAK8CAAYACQktH5oPAK8CABUAAQm+F78pAEEAABQAAQkHAQWpACUAAAAA.',
['Bø']='Bønitalèè:BAABLgAECn8kAAIWAAkJGQkyeACJAQAWAAkJGQkyeACJAQAAAA==.',
Ca='Cain:BAAALgADCgkJDwAAAA==.Calvisi:BAAALgAECgcJDwAAAA==.Calvisichaos:BAABLgAECn9BAAIXAAkJ6Bm9BAAuAgAXAAkJ6Bm9BAAuAgAAAA==.Cantero:BAAALgADCgUJBQAAAA==.Canthen:BAAALgAECggJDwAAAA==.Carcarnisa:BAAALgAECgQJBgAAAA==.Carm:BAAALgAECgYJCgAAAA==.',
Ce='Cenobia:BAAALgADCgUJCQAAAA==.',
Ch='Chaire:BAAALgADCgcJBgAAAA==.Chrysophylax:BAAALgAECgYJBgAAAA==.',
Ci='Cissoid:BAAALgAECgEJAQABLgAFFAgJIAAYAAsjAA==.',
Co='Conky:BAAALgAECgMJBgAAAA==.Corndog:BAAALgADCgEJAQAAAA==.Cornix:BAAALgADCgEJAQAAAA==.Cosmicspark:BAABLgAECn8eAAIQAAcJuQy6rgAhAQAQAAcJuQy6rgAhAQAAAA==.',
Cr='Crentist:BAAALgAECgEJAQAAAA==.Critoliz:BAAALgAFFAMJAQAAAA==.Cropala:BAABLgAECn8pAAIQAAkJCBV4PgAMAgAQAAkJCBV4PgAMAgAAAA==.Cruelcodex:BAAALgAECgEJAQAAAA==.',
Cy='Cyrridven:BAAALgADCgIJAgAAAA==.',
['Cà']='Càtfish:BAAALgADCgEJAQAAAA==.',
Da='Daca:BAAALgADCgMJAwAAAA==.Darkrequiem:BAAALgADCgkJCwAAAA==.Darkwingduck:BAAALgAECgYJCwAAAA==.Dave:BAAALgADCgQJBAAAAA==.Davros:BAAALgAECgMJCAAAAA==.',
De='Decapitator:BAAALgAECgMJAwAAAA==.Dednburied:BAAALgAECgIJAgAAAA==.Deleto:BAABLgAECn8yAAMCAAgJyhiYAwAgAQABAAgJ2BFODgCQAQACAAgJyhiYAwAgAQAAAA==.Dellandre:BAABLgAECn8iAAIYAAgJ/A0SAgDJAAAYAAgJ/A0SAgDJAAABLgAECgkJNAAFANgKAA==.Delta:BAABLgAECn8eAAIHAAgJwwjbgQAcAQAHAAgJwwjbgQAcAQAAAA==.Delti:BAAALgAECgUJBgABLgAECgkJHwAHAFcWAA==.Demondozer:BAAALgAECgMJBAABLgAECgcJCwAEAAAAAA==.Demony:BAAALgAECgEJAgABLgAFFAEJAQAEAAAAAA==.Denard:BAAALgAECgUJBgAAAA==.',
Di='Diabolist:BAACLgAFFH8IAAIDAAMJeAi2iQCyAAADAAMJeAi2iQCyAAAuAAQKfxgAAgMACQlgCIdqAGcBAAMACQlgCIdqAGcBAAAA.Digichowder:BAACLgAFFH8SAAMZAAQJTyB+IAAwAQAZAAMJPSR+IAAwAQAPAAEJhhSQQABIAAAuAAQKfyYAAw8ACQmxIz8EANoCAA8ACAkOIT8EANoCABkABQmNHng5AGABAAAA.Dirtygiri:BAAALgADCgEJAgAAAA==.',
Do='Doktaga:BAAALgAECgYJDgAAAA==.',
Dr='Draex:BAAALgADCgEJAQAAAA==.Dragonzord:BAAALgADCgEJAQAAAA==.Drbubbles:BAAALgADCgYJCAABLgAECgQJCQAEAAAAAA==.Drredd:BAAALgAECgQJBAAAAA==.',
['Dä']='Därkrävèn:BAAALgAECgYJDAAAAA==.',
['Dé']='Déspair:BAAALgAECgEJAQABLgAFFAMJBQAFAGMLAA==.',
Ea='Eama:BAAALgADCgIJAwAAAA==.',
Ed='Edin:BAAALgAECgcJBwABLgAFFAYJHgALAD0VAA==.',
Eg='Eggfield:BAAALgAECgUJBgAAAA==.',
El='Eladora:BAAALgADCgEJAQAAAA==.Eldarr:BAACLgAFFH8FAAIXAAMJlRWYCgDxAAAXAAMJlRWYCgDxAAAuAAQKfz4AAxcACQlBIiYBAO8CABcACQlBIiYBAO8CAAMABQn6EfGMACABAAAA.Eldhe:BAAALgAECgYJDwAAAA==.Eleos:BAAALgADCgMJBgAAAA==.Elistrae:BAACLgAFFH8GAAIaAAMJzQ4NIADXAAAaAAMJzQ4NIADXAAAuAAQKfx8AAxoACQnZFegZANABABoACQmVDOgZANABABMACAkpFzQzAKABAAAA.',
Em='Emorri:BAAALgAECgYJBgAAAA==.',
En='Enazen:BAABLgAECn8fAAIMAAkJWRp3BQC9AgAMAAkJWRp3BQC9AgAAAA==.Endlol:BAACLgAFFH8FAAIbAAMJ7A5HJwDCAAAbAAMJ7A5HJwDCAAAuAAQKfy8AAxsACQkXIY0IAMYCABsACQkXIY0IAMYCABwAAQlSH/5iAFMAAAAA.',
Er='Eredaria:BAAALgAFFAEJAQAAAA==.Ereshkigal:BAAALgADCgYJCwAAAA==.Ergo:BAACLgAFFH8aAAIWAAgJ7RBIHwAGAgAWAAgJ7RBIHwAGAgAuAAQKfyYAAhYACQmuIhsjAOYCABYACQmuIhsjAOYCAAAA.Eronel:BAABLgAECn8eAAICAAcJ7RoFagCSAQACAAcJ7RoFagCSAQAAAA==.',
Es='Esv:BAABLgAFFH8OAAIOAAQJbAqaAwCwAAAOAAQJbAqaAwCwAAABLgAFFAUJHgAWAEIVAA==.',
Ex='Excido:BAAALgAECgEJAgAAAA==.Exodiagold:BAAALgAECgEJAQAAAA==.',
Fa='Fadedharanir:BAAALgAECgIJAwAAAA==.Fadedheart:BAAALgAECgYJDAABLgAFFAMJBQACAKgOAA==.Fadedmystic:BAAALgAECgQJBAAAAA==.Fadednight:BAACLgAFFH8FAAICAAMJqA49mADeAAACAAMJqA49mADeAAAuAAQKfzQAAwIACQnyH14YALQCAAIACQnyH14YALQCABgAAQnVAWpuAA8AAAAA.Faeyir:BAACLgAFFH8TAAIWAAQJIg8pZAAaAQAWAAQJIg8pZAAaAQAuAAQKfyIAAhYACQnDHT9QAEYCABYACQnDHT9QAEYCAAAA.Fallingmoon:BAABLgAECn8nAAMSAAkJqCDsDwDRAgASAAkJqCDsDwDRAgATAAEJKRDmigAwAAAAAA==.Fangrage:BAAALgAECgYJBAAAAA==.Fatherlode:BAACLgAFFH8KAAIWAAMJwBg7ggDTAAAWAAMJwBg7ggDTAAAuAAQKfysAAhYACQmUIXwdAKsCABYACQmUIXwdAKsCAAAA.Fathertouchi:BAAALgAECgMJAwAAAA==.',
Fe='Feltpen:BAAALgAECgUJBQAAAA==.Femcelibate:BAAALgADCgcJCAAAAA==.Fentenjoyer:BAAALgAECgcJDwAAAA==.Fernfondler:BAAALgAFFAIJAwABLgAFFAMJBQAbAOwOAA==.',
Fi='Fivebones:BAAALgAECgQJBAAAAA==.',
Fl='Flashylights:BAAALgADCgYJBgAAAA==.',
Fo='Fontane:BAAALgADCgYJBwAAAA==.Forcebolt:BAAALgADCgMJAwAAAA==.',
Fr='Fredgoofin:BAAALgAECgIJAgAAAA==.Freecookies:BAAALgAECgYJCQAAAA==.Frostybop:BAAALgAECgMJBAABLgAECgIJAgAEAAAAAA==.Frostybreath:BAAALgAECgIJAgAAAA==.Frostybrews:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.Frostydh:BAAALgAECgMJAwABLgAECgIJAgAEAAAAAA==.Frostytotems:BAAALgAECgQJBgAAAA==.Fróstblight:BAAALgAECgkJCAAAAA==.',
Fu='Furryiosa:BAAALgADCgYJBgAAAA==.',
Ga='Gauntodimm:BAAALgAECgYJCgAAAA==.',
Gi='Gilberticus:BAABLgAECn8gAAMaAAYJHx7HAABkAQAaAAYJHx7HAABkAQASAAQJXBYwrQDpAAABLgAECgkJUAAdAMUiAA==.Gishmou:BAABLgAECn8fAAIUAAkJwRh+JgAoAgAUAAkJwRh+JgAoAgAAAA==.',
Go='Goldblade:BAABLgAECn8gAAIQAAgJWhfuUwDOAQAQAAgJWhfuUwDOAQAAAA==.',
Gr='Grayhair:BAAALgAECgQJCAAAAA==.Greyoll:BAAALgAECgYJCAAAAA==.Grimling:BAAALgAFFAEJAQABLgAFFAYJEgAIAJcVAA==.Grindlewald:BAAALgAECgIJAgAAAA==.',
Gu='Gutted:BAACLgAFFH8gAAMYAAgJCyPbAAAmAgAYAAgJCyPbAAAmAgACAAEJxQwNGQE8AAAuAAQKfx0AAhgACQkZJr0BAGcDABgACQkZJr0BAGcDAAAA.',
['Gä']='Gärin:BAAALgADCggJFAAAAA==.',
Ha='Hanna:BAAALgAFFAEJAQABLgAFFAgJIAAYAAsjAA==.Harleyswar:BAAALgADCgEJAQAAAA==.',
He='Hellmaw:BAAALgAECgYJCwAAAA==.',
Hi='Highly:BAAALgADCgcJCwAAAA==.',
Ho='Holianna:BAAALgAECgIJAgAAAA==.Hollowheart:BAABLgAECn87AAMUAAkJ7hz/DwDRAgAUAAkJ7hz/DwDRAgAVAAEJkyFKMwBjAAAAAA==.Holycourtney:BAAALgADCgkJEQAAAA==.Holyknight:BAAALgADCgEJAQAAAA==.Hotsausage:BAAALgAECgMJAwAAAA==.Hoved:BAAALgADCgEJAQAAAA==.',
Hu='Huang:BAAALgAECgMJAwAAAA==.',
Hy='Hylanna:BAAALgAECgcJDAAAAA==.Hyorinmaru:BAAALgAFFAEJAgAAAA==.',
['Hó']='Hónor:BAAALgADCgMJAwABLgAFFAMJBQAFAGMLAA==.',
Ic='Ici:BAABLgAECn8zAAMQAAkJAAiGigBbAQAQAAkJAAiGigBbAQAKAAQJuA6BXQDAAAAAAA==.Icritdaily:BAAALgADCgUJCgAAAA==.',
If='Iffybacon:BAAALgAECgIJAgABLgAECgQJCwAEAAAAAA==.',
Ik='Ikilledkeny:BAAALgAFFAMJAQAAAA==.',
Im='Imlerith:BAAALgADCgQJBgAAAA==.',
In='Intensifies:BAAALgAECgcJEgAAAA==.',
Ip='Ippo:BAAALgADCgEJAQAAAA==.',
Is='Isabellà:BAABLgAECn8YAAIFAAkJ1Q/iEgCbAQAFAAkJ1Q/iEgCbAQABLgAECgkJKQAeADMNAA==.Iskothar:BAABLgAECn80AAIFAAkJgCGyAgD/AgAFAAkJgCGyAgD/AgAAAA==.',
Iv='Ivarboneless:BAABLgAECn8cAAIKAAcJaiBKEwB2AgAKAAcJaiBKEwB2AgAAAA==.',
Ja='Jackz:BAAALgAECgkJCQAAAA==.Jackzlock:BAAALgAECgkJAQAAAA==.Jakethemage:BAAALgADCgUJCAAAAA==.Jankball:BAAALgAFFAMJAQAAAA==.Jatkal:BAAALgAFFAEJAgAAAA==.Jayreezy:BAAALgAECgMJBAAAAA==.',
Je='Jefftrep:BAAALgAECgQJAwAAAA==.Jerihatrix:BAAALgAECgEJAQAAAA==.',
Ji='Jimmylahey:BAAALgAECgMJAwAAAA==.',
Jo='Jonah:BAAALgADCgEJAQAAAA==.',
Ka='Kaina:BAAALgADCgYJCQAAAA==.Kakidruid:BAAALgAECgIJAwAAAA==.Kalfu:BAABLgAECn8UAAMbAAkJygzWKwB2AQAbAAkJygzWKwB2AQAfAAgJFwnpMQBTAQAAAA==.',
Ke='Ketesh:BAACLgAFFH8FAAIgAAMJDxfuFgDMAAAgAAMJDxfuFgDMAAAuAAQKfzwAAiAACQnNIH8DAO0CACAACQnNIH8DAO0CAAEuAAUUBgkeAAsAPRUA.',
Ki='Kilorean:BAAALgAECgcJCAAAAA==.Kirae:BAAALgAECgUJBQABLgAECgkJNAAFAIAhAA==.',
Kl='Kleanse:BAAALgAFFAMJAQAAAA==.',
Kn='Knastey:BAABLgAECn8VAAQeAAYJ4Bc7NgA9AQAeAAYJ4Bc7NgA9AQANAAYJZAqbcQABAQAhAAEJWxKCMgA3AAAAAA==.Knasty:BAAALgADCgEJAQAAAA==.',
Ko='Kodera:BAABLgAECn8iAAILAAYJQQVPZwClAAALAAYJQQVPZwClAAAAAA==.',
Kr='Krej:BAABLgAECn8XAAIYAAkJMBw0DwAYAgAYAAkJMBw0DwAYAgABLgAFFAYJEgAIAJcVAA==.Krisskringle:BAAALgAECgMJBgAAAA==.',
Ku='Kuromori:BAAALgADCgYJBgAAAA==.',
Ky='Kyronix:BAAALgAECgMJBwAAAA==.',
['Kê']='Kênpachi:BAAALgAECgYJDgAAAA==.',
La='Landrey:BAAALgADCgkJCwAAAA==.Langarde:BAABLgAECn8fAAIOAAkJCxDIFgCNAQAOAAkJCxDIFgCNAQAAAA==.Laoghaire:BAABLgAECn8YAAIIAAcJ+APYQgCrAAAIAAcJ+APYQgCrAAAAAA==.',
Le='Leonz:BAACLgAFFH8bAAIZAAgJDhuEAwBMAgAZAAgJDhuEAwBMAgAuAAQKfy4AAhkACQmaJCcFABADABkACQmaJCcFABADAAAA.Leonzs:BAAALgAECggJEAAAAA==.Letharanos:BAECLgAFFH8HAAMCAAMJkhfJjgDtAAACAAMJkhfJjgDtAAAYAAEJfQdiQwAoAAAuAAQKfycAAwIACQl0GQpFAPMBAAIACQl0GQpFAPMBABgAAQl7DuJgACgAAAAA.',
Li='Liraffemynn:BAACLgAFFH8bAAIiAAUJhxv5HQCAAQAiAAUJhxv5HQCAAQAuAAQKfz4AAiIACQmOI8YDAHsDACIACQmOI8YDAHsDAAAA.Liralynn:BAAALgADCgUJBQAAAA==.',
Lk='Lkynyx:BAAALgADCgYJAQAAAA==.',
Lo='Lonranir:BAAALgAECgYJEAAAAA==.Lostinlight:BAAALgAECgYJBgAAAA==.',
Lu='Lucii:BAAALgADCgEJAQABLgAFFAgJIAAYAAsjAA==.Luckylucy:BAABLgAECn8XAAIcAAYJhhamLgBZAQAcAAYJhhamLgBZAQAAAA==.',
Ma='Madarauchiha:BAABLgAECn8aAAICAAYJ6BpwggB+AQACAAYJ6BpwggB+AQAAAA==.Magus:BAAALgADCgkJFgABLgAECgMJCAAEAAAAAA==.Maldran:BAABLgAECn8jAAIUAAcJjh3YKgAPAgAUAAcJjh3YKgAPAgAAAA==.Maling:BAAALgAECgEJAQAAAA==.Manderpants:BAABLgAECn8gAAISAAcJVwqpgwA3AQASAAcJVwqpgwA3AQAAAA==.Marien:BAABLgAECn8fAAIYAAkJHBmBDQAyAgAYAAkJHBmBDQAyAgAAAA==.Marty:BAAALgAECgIJAwAAAA==.Maxus:BAAALgADCgUJBQAAAA==.',
Mb='Mbbin:BAACLgAFFH8MAAIWAAMJFyWpUQA6AQAWAAMJFyWpUQA6AQAuAAQKfyoAAhYACQntIQgdAK4CABYACQntIQgdAK4CAAAA.',
Me='Mehuman:BAABLgAECn8aAAIQAAcJzxF7jABYAQAQAAcJzxF7jABYAQAAAA==.Mehumanhuntr:BAAALgAECgUJBwAAAA==.Mehumanlock:BAABLgAECn8jAAIXAAkJ+xEWCgCkAQAXAAkJ+xEWCgCkAQAAAA==.Menedemnhntr:BAAALgAECgYJBgAAAA==.Merlinn:BAAALgADCgkJCwAAAA==.Merran:BAAALgADCgEJAQAAAA==.Metal:BAAALgADCgQJBAAAAA==.Meworgendk:BAAALgAECgYJDgAAAA==.',
Mh='Mhoo:BAAALgADCgcJBwAAAA==.',
Mi='Miriym:BAAALgADCgEJAQAAAA==.Miräj:BAAALgAECgcJDAAAAA==.Mistyblue:BAAALgADCgEJAQAAAA==.Miya:BAAALgADCgcJDQAAAA==.',
Mo='Moonscale:BAAALgAECgMJBAAAAA==.Mordaci:BAAALgADCgQJBQABLgAFFAEJAQAEAAAAAA==.Mordekrieg:BAABLgAFFH8GAAICAAMJUAt2rgDFAAACAAMJUAt2rgDFAAAAAA==.Mortstan:BAAALgAECgcJDQAAAA==.',
My='Myash:BAAALgAECgcJDQAAAA==.',
['Må']='Månni:BAAALgADCgYJBwAAAA==.',
['Mé']='Mélusine:BAAALgADCgEJAQAAAA==.',
Na='Nailia:BAAALgAECgcJCwAAAA==.Nailz:BAABLgAECn8fAAIHAAkJVxZGTwCYAQAHAAkJVxZGTwCYAQAAAA==.Nakama:BAAALgADCgYJBgABLgAECgkJNAAGAJgMAA==.Nardog:BAAALgAECgEJAQAAAA==.Narie:BAAALgAECggJCQAAAA==.Nasaug:BAAALgAECgUJCwABLgAFFAMJBQAFAGMLAA==.',
Ne='Ned:BAAALgAECgEJAQAAAA==.Neuse:BAAALgAECggJEwAAAA==.',
Ni='Nightlion:BAABLgAECn8hAAIgAAcJRxB5JgAgAQAgAAcJRxB5JgAgAQAAAA==.Nillius:BAAALgADCgIJAgAAAA==.Nisu:BAAALgAECgEJAQAAAA==.',
No='Noahdh:BAAALgAECgMJAwABLgAFFAgJHwADABAYAA==.Noahpriest:BAAALgAECgMJAwABLgAFFAgJHwADABAYAA==.Noahvoker:BAAALgAECggJEQABLgAFFAgJHwADABAYAA==.Noahwarlock:BAACLgAFFH8fAAQDAAgJEBjOIQDHAQADAAYJTh3OIQDHAQAXAAMJXxFuCwDkAAAjAAEJkSN/IABQAAAuAAQKfzEABAMACQmFJAEFAD8DAAMACAlsJAEFAD8DABcABAl0IkEaAHsBACMAAwmsI4IWAM0AAAAA.Nonsensical:BAAALgADCgUJBQABLgAECgYJIgAiAEYiAA==.Nook:BAAALgADCgUJBgAAAA==.Nowere:BAAALgADCgcJBwAAAA==.Noxander:BAAALgAECgEJAQAAAA==.',
Ny='Nym:BAAALgAECgkJEQAAAA==.',
['Nâ']='Nârenth:BAAALgADCgMJAwAAAA==.',
Oa='Oaths:BAAALgAECgcJEQAAAA==.',
Oh='Ohmylanta:BAAALgAFFAIJAgAAAA==.Ohmylantä:BAABLgAECn8dAAIWAAgJPg0GjABfAQAWAAgJPg0GjABfAQAAAA==.Ohmylantå:BAAALgADCgUJCAAAAA==.',
On='Ondeane:BAAALgADCgEJAQAAAA==.Onumae:BAABLgAECn8XAAIQAAkJcRr+MQA4AgAQAAkJcRr+MQA4AgAAAA==.',
Op='Oprime:BAAALgADCgMJAwAAAA==.',
Or='Orbeck:BAAALgAECggJCAABLgAFFAgJHQAJAIocAA==.Ormond:BAABLgAECn8eAAMKAAcJeBSqKgC6AQAKAAcJeBSqKgC6AQAQAAUJPAWFHAGXAAAAAA==.Orochinchin:BAAALgAECgUJBQABLgAFFAgJIAAYAAsjAA==.',
Os='Oscarmike:BAAALgADCgcJDQAAAA==.',
Oz='Ozlon:BAAALgAECgcJEwAAAA==.',
['Oâ']='Oâth:BAABLgAECn8tAAMkAAkJpg2kDQB4AQAkAAkJpg2kDQB4AQAIAAMJRgatZQBCAAAAAA==.',
Pa='Pachane:BAAALgAECgQJCwAAAA==.Paldozer:BAAALgAECgUJCQABLgAECgcJCwAEAAAAAA==.Pallywacker:BAACLgAFFH8FAAIFAAIJtgkWEwBhAAAFAAIJtgkWEwBhAAAuAAQKfzIAAgUACAlSE5wUAIYBAAUACAlSE5wUAIYBAAAA.Pankins:BAAALgAECgMJAwAAAA==.Panzerkan:BAAALgAECgEJAQAAAA==.Panzerkìn:BAAALgAECgcJCAAAAA==.',
Pe='Percymorris:BAAALgADCgYJBwAAAA==.Peythilly:BAAALgAECgQJBAAAAA==.',
Pi='Pigishdog:BAACLgAFFH8FAAIDAAMJ8grLgADDAAADAAMJ8grLgADDAAAuAAQKf1cAAwMACQnJHecTAK4CAAMACQnJHecTAK4CABcAAQnVEbE9ADYAAAAA.Pikon:BAAALgADCgkJDQAAAA==.',
Po='Pokeabear:BAAALgAECgYJEAABLgAECgcJEAAEAAAAAA==.Pokethedruid:BAAALgAECgEJAQABLgAECgEJBwAEAAAAAA==.Pokethemonk:BAAALgAECgEJBwAAAA==.Poshingtang:BAABLgAECn8pAAQUAAkJqQzVRACbAQAUAAkJqQzVRACbAQAGAAgJHhG8NgB4AQAVAAMJSwP+JQB3AAAAAA==.',
Pu='Pulsar:BAAALgAECgQJBwAAAA==.Punchies:BAAALgADCggJDQAAAA==.',
Qu='Quatrain:BAABLgAECn80AAMGAAkJmAwWOQBSAQAGAAgJ1g0WOQBSAQAUAAgJrxDRXABGAQAAAA==.Quintessence:BAAALgAECgMJAwAAAA==.',
Ra='Rabidbutt:BAAALgAFFAMJBAABLgAFFAcJGQAMAF0gAA==.Ragerunner:BAAALgADCgkJEwAAAA==.Rakarg:BAABLgAECn8ZAAICAAUJDBjx0ADnAAACAAUJDBjx0ADnAAAAAA==.Ravenus:BAAALgAECgEJAQAAAA==.',
Re='React:BAAALgAECggJCAABLgAFFAMJBQAbAOwOAA==.Redemptor:BAAALgAECgUJBQAAAA==.Refund:BAAALgAECgEJAQAAAA==.Regalbacon:BAAALgAECgMJAwAAAA==.Reygina:BAABLgAECn8ZAAIKAAYJygIvYAC1AAAKAAYJygIvYAC1AAAAAA==.',
Ri='Rickÿ:BAAALgAECgEJAQAAAA==.Rikku:BAAALgAECggJCAABLgAFFAgJHAAGACoTAA==.Ripndip:BAAALgAFFAMJAQAAAA==.Riprock:BAAALgAECgIJAQABLgAFFAMJAQAEAAAAAA==.Rixas:BAAALgAECgEJAQABLgAECgkJMwADACkdAA==.',
Rn='Rn:BAACLgAFFH8FAAIPAAQJShiTGgATAQAPAAQJShiTGgATAQAuAAQKfx4AAw8ACQklIkEBAEYDAA8ACQkIIkEBAEYDABkABwkvIyQpABcCAAEuAAUUCAkiAA8AgyQA.',
Ro='Rodeo:BAAALgAECgMJBQAAAA==.Roguehiro:BAABLgAECn8pAAIFAAgJxSEKBgCKAgAFAAgJxSEKBgCKAgAAAA==.Rooter:BAACLgAFFH8ZAAIMAAcJXSCCBACVAgAMAAcJXSCCBACVAgAuAAQKfz0AAwwACQkRJB8BAJ8DAAwACQkRJB8BAJ8DAAsABwnsGeklALABAAAA.Roronoaxd:BAAALgADCgMJAwAAAA==.Rosalynñ:BAABLgAECn8pAAIXAAgJMgpXFAAMAQAXAAgJMgpXFAAMAQAAAA==.',
Ru='Ruikhai:BAAALgADCgMJBQABLgADCgkJBwAEAAAAAA==.Ruto:BAAALgAECgEJAQABLgAFFAMJAQAEAAAAAA==.',
Sa='Saelis:BAACLgAFFH8VAAINAAUJnhZ5IQBMAQANAAUJnhZ5IQBMAQAuAAQKfx8AAw0ACQnfIAIMAAADAA0ACQnfIAIMAAADACEABgnwGRUUAH8BAAAA.Salen:BAAALgAECgEJAQAAAA==.Samshara:BAAALgAECgQJBAABLgAECgkJRAAaAH4dAA==.Saptapper:BAAALgAECgIJAgAAAA==.Saracenio:BAAALgADCgEJAQAAAA==.',
Sc='Schnem:BAAALgAECggJCgAAAA==.Scrawni:BAAALgAECgcJCAABLgAFFAYJEgAIAJcVAA==.Scrounge:BAAALgAFFAEJAQABLgAFFAMJCAADAHgIAA==.',
Se='Securìty:BAAALgAECgQJBQAAAA==.Selyane:BAAALgADCgkJCQAAAA==.Seong:BAACLgAFFH8dAAIJAAgJihz8BQA2AgAJAAgJihz8BQA2AgAuAAQKfyEAAgkACQmAIgUFADkDAAkACQmAIgUFADkDAAAA.Seongdh:BAAALgAECggJDQABLgAFFAgJHQAJAIocAA==.Seongwar:BAAALgAECgMJAwAAAA==.Seraphinà:BAAALgAECgYJEAABLgAECgkJKQAeADMNAA==.',
Sh='Shadowdooms:BAABLgAECn8WAAMCAAgJFBkfYQDQAQACAAgJFBkfYQDQAQABAAEJSxf2FABFAAAAAA==.Shadowfur:BAAALgAECggJDQABLgAECgkJPAAKAN8eAA==.Shamynna:BAAALgAECgMJBAAAAA==.Sharreth:BAAALgAECgIJAgAAAA==.Shii:BAAALgADCgUJBQAAAA==.Shimera:BAABLgAECn8yAAISAAkJNhMlPgDpAQASAAkJNhMlPgDpAQAAAA==.Shish:BAAALgAECggJCwAAAA==.Shizukura:BAAALgADCgEJAQAAAA==.Shockawar:BAACLgAFFH8WAAIZAAUJeRwxAwDEAQAZAAUJeRwxAwDEAQAuAAQKfxkAAhkACQmrHmYYAIgCABkACQmrHmYYAIgCAAAA.Shooter:BAAALgADCgIJAgAAAA==.Shootrmcgavn:BAACLgAFFH8eAAQSAAYJ8yLEJAByAQASAAUJrx/EJAByAQAaAAQJRSHkDABdAQATAAQJNiDGEAAqAQAuAAQKfxsABBIACAk8IdMVAIkCABIABwnxIdMVAIkCABMABwlKIcoaAFMCABoAAwm3IXUxACABAAAA.Shu:BAAALgAFFAIJAgAAAA==.Shuletaa:BAAALgAECgIJBAAAAA==.Shïsh:BAAALgADCgcJBwABLgAECggJCwAEAAAAAA==.',
Si='Silverwolf:BAAALgADCgEJAQAAAA==.Sinestra:BAAALgAECgEJAQAAAA==.',
Sk='Skibidi:BAAALgAECgcJDgABLgAFFAMJEwAWABcfAA==.',
Sl='Slagscar:BAAALgAFFAIJAQAAAA==.Slaughterhse:BAABLgAECn8XAAIWAAYJ5gOm+gC0AAAWAAYJ5gOm+gC0AAAAAA==.Slootar:BAABLgAECn8UAAQNAAcJ5xuIJAAoAgANAAcJ5xuIJAAoAgAeAAIJuxBfbABuAAAhAAIJMAZUVwAsAAAAAA==.Slugs:BAAALgAECgUJCAAAAA==.',
Sn='Snqwflake:BAABLgAECn8VAAIiAAgJ7xb8FQAUAgAiAAgJ7xb8FQAUAgAAAA==.',
So='Solareth:BAAALgAECgEJAgAAAA==.Solthin:BAAALgAFFAMJAQAAAA==.Somebeotch:BAAALgADCgYJBgAAAA==.Somerled:BAABLgAECn9EAAIaAAkJfh1vCACXAgAaAAkJfh1vCACXAgAAAA==.',
Sp='Spyroid:BAAALgAECgUJAQAAAA==.',
St='Static:BAAALgADCgcJBwABLgAECgYJCgAEAAAAAA==.',
Su='Sunstrike:BAAALgAECgEJAgAAAA==.',
Sy='Sylvanna:BAAALgADCgQJBAAAAA==.',
Ta='Tabul:BAAALgADCgUJBAAAAA==.Takka:BAABLgAECn8aAAIUAAgJHR0cGACIAgAUAAgJHR0cGACIAgAAAA==.Talden:BAACLgAFFH8GAAMQAAMJzxFEdADLAAAQAAMJ3A5EdADLAAAFAAEJRRhoFgBHAAAuAAQKf0UAAxAACQkyHMcfAIkCABAACQkyHMcfAIkCAAUAAwnNEFJGAEwAAAAA.Talkamar:BAACLgAFFH8FAAIdAAMJwhLIIgDKAAAdAAMJwhLIIgDKAAAuAAQKfyMAAh0ACQn7EeoeALYBAB0ACQn7EeoeALYBAAAA.Taylorswift:BAABLgAECn83AAIWAAkJ8xiyLABmAgAWAAkJ8xiyLABmAgAAAA==.Tazzaar:BAAALgAECgMJAwAAAA==.',
Th='Thaelios:BAAALgADCgEJAQAAAA==.Thekourge:BAABLgAECn80AAIFAAkJ2ApYGwA9AQAFAAkJ2ApYGwA9AQAAAA==.Thenard:BAABLgAECn8jAAISAAgJPBPrVgCfAQASAAgJPBPrVgCfAQAAAA==.Therealcafna:BAAALgADCgcJBwAAAA==.Thukunaenhan:BAAALgAECgQJBAABLgAFFAMJEwAWABcfAA==.Thukunamage:BAACLgAFFH8TAAIWAAMJFx99bwADAQAWAAMJFx99bwADAQAuAAQKfyoAAhYACQmyIIkhAJcCABYACQmyIIkhAJcCAAAA.',
Ti='Tibarius:BAAALgADCgkJEgAAAA==.Tili:BAAALgADCgkJDwAAAA==.Tinaraeda:BAAALgAECgMJAwAAAA==.',
To='Tomislav:BAABLgAECn8lAAQDAAkJcBvfKwAqAgADAAcJrBnfKwAqAgAXAAQJ2xqlIACoAAAjAAEJlA7rPAA4AAAAAA==.Tomuchmakeup:BAAALgAECgMJAwAAAA==.Touritos:BAABLgAECn8eAAIGAAkJdRGaKgCdAQAGAAkJdRGaKgCdAQAAAA==.',
Tr='Trimblestein:BAAALgAECgUJCgAAAA==.Troyka:BAAALgAECgEJAQAAAA==.Truefitt:BAAALgAECgYJEwAAAA==.',
Tu='Tulikettwo:BAAALgAECgEJAQAAAA==.Tulirenpo:BAAALgAECgUJBQAAAA==.Tunk:BAAALgAFFAMJAQAAAA==.Tuskal:BAAALgAECgIJAwAAAA==.',
Tw='Twogora:BAAALgAECgYJCQAAAA==.Twohoofy:BAAALgADCgcJBgAAAA==.',
Ty='Tydes:BAABLgAECn8bAAMlAAgJ6RbMEwB4AgAlAAgJ6RbMEwB4AgAmAAEJtgtBHQBBAAAAAA==.Tydru:BAAALgAFFAMJAQAAAA==.Tyler:BAACLgAFFH8LAAIHAAQJfhXYDwBPAQAHAAQJfhXYDwBPAQAuAAQKfxsAAgcACAkOHTgcAKkCAAcACAkOHTgcAKkCAAAA.Tystin:BAAALgADCgQJBQABLgADCgkJBwAEAAAAAA==.',
Ud='Uddermilk:BAABLgAECn8cAAIeAAcJ/AnaAgDAAAAeAAcJ/AnaAgDAAAAAAA==.',
Um='Umariel:BAAALgAFFAMJAQAAAA==.',
Va='Valina:BAAALgADCgIJAgAAAA==.Valissar:BAAALgAECgMJBwAAAA==.Valkyrja:BAAALgAECgEJAQAAAA==.Valr:BAACLgAFFH8FAAIFAAMJYws2DgCaAAAFAAMJYws2DgCaAAAuAAQKfzQAAgUACQm3DxYXAGgBAAUACQm3DxYXAGgBAAAA.Vancliffe:BAAALgAECgQJBAABLgAFFAYJEgAIAJcVAA==.Vandreu:BAAALgADCgUJBQAAAA==.',
Ve='Verpally:BAAALgADCgMJAwAAAA==.',
Vi='Viparia:BAAALgAECgkJAgAAAA==.Virulent:BAAALgAECgMJAwAAAA==.',
Vo='Voloaura:BAAALgADCgMJAwAAAA==.',
Vs='Vse:BAACLgAFFH8eAAIWAAUJQhVDVwAuAQAWAAUJQhVDVwAuAQAuAAQKfy4AAhYACAl8GztIAAICABYACAl8GztIAAICAAAA.Vsesosorry:BAABLgAFFH8VAAIUAAQJZxSwNgAHAQAUAAQJZxSwNgAHAQABLgAFFAUJHgAWAEIVAA==.Vsè:BAAALgADCgUJBQABLgAFFAUJHgAWAEIVAA==.',
Vy='Vyke:BAAALgAECgkJEQABLgAFFAgJHQAJAIocAA==.',
['Ví']='Ví:BAAALgAECgYJBgAAAA==.',
Wa='Wammo:BAAALgAECgYJCgAAAA==.Waq:BAAALgADCgMJAwAAAA==.Wardozer:BAAALgAECgcJCwAAAA==.Warlockedin:BAAALgAECgYJDQAAAA==.',
We='Weierstrass:BAAALgAFFAEJAQABLgAFFAgJIAAYAAsjAA==.',
Wo='Worgenkrantz:BAABLgAECn8pAAMeAAkJMw3OKQCFAQAeAAkJMw3OKQCFAQANAAcJeAJQkgCrAAAAAA==.',
Wr='Wrathlor:BAAALgADCgcJBQAAAA==.Wrenlyn:BAACLgAFFH8SAAMIAAYJlxV3EgAQAQAIAAUJ5RV3EgAQAQAHAAIJKQx8ewCHAAAuAAQKfzAAAwgACAlsI9sOADgCAAgACAntH9sOADgCACQAAglCE7UlAHIAAAAA.',
Wu='Wukain:BAAALgADCgEJAQAAAA==.',
Xa='Xanatas:BAAALgAECgYJDwABLgAECgkJNAAFAIAhAA==.',
Xo='Xolòtl:BAABLgAECn8hAAIOAAkJQBUZFADLAQAOAAkJQBUZFADLAQABLgAFFAYJEgAIAJcVAA==.Xoss:BAAALgAFFAMJAQAAAA==.',
Yg='Yggdrasali:BAAALgAECgQJBgABLgAFFAIJBQAWAJIaAA==.',
Yi='Yin:BAAALgAECgcJCAAAAA==.',
Yo='Yourhero:BAAALgAECgEJAgAAAA==.',
Ys='Yserra:BAAALgAECgcJDAAAAA==.',
Za='Zaerine:BAAALgAECgYJBgAAAA==.Zakuso:BAAALgAECgQJCQAAAA==.Zalatha:BAAALgADCgEJAQAAAA==.Zalyia:BAABLgAECn8uAAIbAAkJlA2BJwCSAQAbAAkJlA2BJwCSAQAAAA==.Zapix:BAAALgAECgEJAQABLgAECgMJBwAEAAAAAA==.',
Ze='Zephinar:BAABLgAECn8ZAAIWAAgJcBVpaQADAgAWAAgJcBVpaQADAgAAAA==.Zexpert:BAABLgAECn8dAAQnAAgJkheiDQAAAgAnAAcJdxiiDQAAAgALAAcJnhUvKAB8AQAMAAQJfgwFNADNAAAAAA==.',
Zq='Zquestion:BAAALgAECgIJBAABLgAECggJHQAnAJIXAA==.',
Zu='Zulblade:BAABLgAECn8SAAIHAAgJORqFMAA5AgAHAAgJORqFMAA5AgAAAA==.Zulpally:BAABLgAECn8aAAQQAAUJQBa2ygD6AAAQAAQJxhi2ygD6AAAKAAMJyRCQcgCxAAAFAAQJ+QiuMQCIAAAAAA==.',
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
