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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Unknown-Unknown','Paladin-Protection','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Brewmaster','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Feral','Druid-Restoration','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Shaman-Enhancement','Mage-Frost','Warlock-Destruction','DeathKnight-Blood','Warrior-Fury','Hunter-Survival','Priest-Shadow','Priest-Holy','Monk-Windwalker','Druid-Balance','Priest-Discipline','Druid-Guardian','Monk-Mistweaver','Rogue-Subtlety','Warlock-Affliction','DemonHunter-Vengeance','Rogue-Assassination','Evoker-Devastation',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abaddon:BAABLgAECn8tAAMBAAkJTB8qBwAoAgABAAgJ6R0qBwAoAgACAAgJrBzyRQDwAQAAAA==.Abessedge:BAAALgAECggJDQAAAA==.',
Ac='Acidtears:BAAALgAECgEJAQAAAA==.Ackris:BAABLgAECn8zAAIDAAkJKR0HCgAuAwADAAkJKR0HCgAuAwAAAA==.Ackrisa:BAAALgAECgUJCAAAAA==.Acris:BAAALgAECgYJCwABLgAECgkJMwADACkdAA==.',
Ae='Aedimus:BAAALgADCgcJCQAAAA==.',
Al='Aleathris:BAEALgADCgcJBwABLgAECgQJBAAEAAAAAA==.Alistan:BAAALgAECgEJAQAAAA==.Alka:BAAALgADCgEJAQAAAA==.Alkaios:BAAALgAECgcJDQABLgAFFAMJBQAFAGMLAA==.Alor:BAAALgAECgIJBAABLgAECgkJNgAGAHsOAA==.Alpyne:BAAALgAECgcJEgAAAA==.',
Am='Amaimon:BAABLgAECn8aAAMHAAgJDhWRVgCDAQAHAAgJDhWRVgCDAQAIAAEJawx8cAAvAAABLgAFFAgJHAAGACoTAA==.Amalthaea:BAAALgAECgcJEwABLgAECgkJLwAJAOoWAA==.Amnoon:BAABLgAECn82AAIKAAkJ+BfnEwBwAgAKAAkJ+BfnEwBwAgAAAA==.Amri:BAACLgAFFH8hAAMLAAYJPRWsMAD/AAALAAUJSxOsMAD/AAAMAAIJ1QtcJQBvAAAuAAQKfy0AAwsACAlOGZwDADIBAAsACAlOGZwDADIBAAwABglADVUiAN0AAAAA.',
An='Andarnáurram:BAAALgAECgIJAgAAAA==.Angelfox:BAAALgAECgQJAgAAAA==.',
Aq='Aquas:BAAALgAECgUJCwAAAA==.',
Ar='Ardrhys:BAAALgAFFAQJBAAAAA==.Arthurcarrot:BAAALgAECgQJBwAAAA==.Artikin:BAAALgAFFAEJAQABLgAFFAYJEgAIAJcVAA==.',
As='Assasin:BAAALgAECgYJBgAAAA==.Assasinateu:BAAALgADCgMJAwAAAA==.Asûná:BAABLgAECn8YAAINAAkJ8xY2DgDSAQANAAkJ8xY2DgDSAQAAAA==.',
At='Atreus:BAABLgAECn8nAAMIAAkJ7BxcDgA/AgAIAAkJ7BxcDgA/AgAHAAEJVAswIAEqAAABLgAFFAEJAQAEAAAAAA==.Atzalan:BAABLgAECn8UAAIOAAYJpwnpcwD7AAAOAAYJpwnpcwD7AAAAAA==.',
Au='Automagic:BAAALgAECgEJAgAAAA==.',
Av='Avondwella:BAABLgAECn8vAAMPAAkJfhBxGgBmAQAPAAkJfhBxGgBmAQAQAAEJ+wnERAAvAAAAAA==.',
Az='Azorah:BAAALgAECgUJBQAAAA==.Azrikam:BAAALgAECgYJCAAAAA==.',
Ba='Badhabit:BAAALgADCgYJBgAAAA==.Baku:BAAALgAECgYJBgABLgAFFAYJEgAIAJcVAA==.Baldyguy:BAAALgADCgcJDQAAAA==.Balm:BAACLgAFFH8GAAIOAAMJggYuTwCEAAAOAAMJggYuTwCEAAAuAAQKfzEAAg4ACQkIGr4hADoCAA4ACQkIGr4hADoCAAAA.Balton:BAAALgAECgIJAwAAAA==.Barbsimpsonn:BAAALgAECgEJAQAAAA==.Bashalot:BAAALgAECgUJBgAAAA==.',
Be='Beastcloud:BAAALgAECgMJAwABLgAFFAEJAQAEAAAAAA==.Beautzibub:BAAALgADCgMJAwAAAA==.Behindyou:BAAALgAECggJBAABLgAECgkJKQARAAgVAA==.Bermin:BAAALgAECgEJAQAAAA==.',
Bi='Biblepimp:BAAALgAFFAEJAQAAAA==.Bigwilliam:BAAALgADCgEJAQAAAA==.',
Bl='Blackmarker:BAABLgAECn8cAAICAAgJ/BTEXQCvAQACAAgJ/BTEXQCvAQAAAA==.Blackmouser:BAAALgAECgQJBAAAAA==.Blemish:BAAALgAECgEJAQABLgAFFAMJBgAOAIIGAA==.Bloodpac:BAAALgAECgQJCAAAAA==.',
Bm='Bmo:BAABLgAECn8VAAIRAAcJZSB1SAAJAgARAAcJZSB1SAAJAgAAAA==.',
Bo='Bodyguardwyn:BAAALgAECgEJAQAAAA==.Bogle:BAACLgAFFH8FAAMRAAIJOQwQqgBtAAARAAIJUAUQqgBtAAAFAAIJOQwOCAA2AAAuAAQKfy8AAwUACQnYI7MCAP8CAAUACQnYI7MCAP8CABEAAwnyFuDiANoAAAAA.Bonedmuch:BAAALgAECggJDgABLgAECgkJLwAJAOoWAA==.Bow:BAAALgAECgIJAwAAAA==.',
Br='Brasi:BAAALgAECgIJAgAAAA==.Bratton:BAABLgAECn8aAAISAAcJ6wa1EwDRAAASAAcJ6wa1EwDRAAAAAA==.Breadria:BAAALgAECgEJAwABLgAFFAMJCQATAFkGAA==.Bremitin:BAAALgAFFAIJAgABLgAFFAMJBQAFAGMLAA==.Bremitus:BAAALgAECgEJAQABLgAFFAMJBQAFAGMLAA==.Brewcrew:BAAALgAECgkJBwAAAA==.Brewey:BAAALgAFFAEJAQAAAA==.Brewmongster:BAAALgAECgQJBQAAAA==.Brimscythe:BAABLgAECn8bAAIHAAgJ5B+wNwAXAgAHAAgJ5B+wNwAXAgAAAA==.Brud:BAABLgAFFH8FAAIQAAMJPwf4DACzAAAQAAMJPwf4DACzAAAAAA==.Brunstan:BAACLgAFFH8TAAIUAAUJfh8SEgBDAQAUAAUJfh8SEgBDAQAuAAQKfxkAAhQACQnjIL4CALwCABQACQnjIL4CALwCAAAA.',
Bu='Bubbastump:BAAALgAECgQJBAAAAA==.',
By='Byakugan:BAACLgAFFH8cAAMGAAgJKhN1BQCDAQAGAAYJRxN1BQCDAQAVAAMJEgl+TADBAAAuAAQKfyAABAYACQktH5oPAK8CAAYACQktH5oPAK8CABYAAQm+F78pAEEAABUAAQkHAQWpACUAAAAA.',
['Bø']='Bønitalèè:BAABLgAECn8kAAIXAAkJGQkzeACJAQAXAAkJGQkzeACJAQAAAA==.',
Ca='Cain:BAAALgAECgEJAQAAAA==.Calvisi:BAAALgAECgcJDwAAAA==.Calvisichaos:BAABLgAECn9HAAIYAAkJ1xu9BAAuAgAYAAkJ1xu9BAAuAgAAAA==.Cantero:BAAALgADCgUJBQAAAA==.Canthen:BAAALgAECggJDwAAAA==.Carcarnisa:BAAALgAECgQJBgAAAA==.Carm:BAAALgAECgYJCgAAAA==.',
Ce='Cenobia:BAAALgADCgUJCQAAAA==.',
Ch='Chaire:BAAALgADCgcJBgAAAA==.Chrysophylax:BAAALgAECgYJBgAAAA==.',
Ci='Cindershade:BAEALgADCgMJAwAAAA==.Cissoid:BAAALgAECgEJAQABLgAFFAgJIAAZAAsjAA==.',
Co='Conky:BAAALgAECgMJBgAAAA==.Corndog:BAAALgADCgEJAQAAAA==.Cornix:BAAALgADCgEJAQAAAA==.Cosmicspark:BAABLgAECn8kAAIRAAkJBg50EgDdAAARAAkJBg50EgDdAAAAAA==.',
Cr='Crentist:BAAALgAECgEJAQAAAA==.Critoliz:BAAALgAFFAMJAQAAAA==.Cropala:BAABLgAECn8pAAIRAAkJCBV5PgAMAgARAAkJCBV5PgAMAgAAAA==.Cruelcodex:BAAALgAECgEJAwAAAA==.',
Cy='Cyrridven:BAAALgADCgQJAgAAAA==.',
['Cà']='Càtfish:BAAALgADCgEJAQAAAA==.',
Da='Daca:BAAALgADCgMJAwAAAA==.Darkrequiem:BAAALgADCgkJCwAAAA==.Darkwingduck:BAAALgAECgYJCwAAAA==.Dave:BAAALgADCgQJBAAAAA==.Davros:BAAALgAECgUJDQAAAA==.',
De='Decapitator:BAAALgAECgMJAwAAAA==.Dednburied:BAAALgAECgIJAgAAAA==.Deleto:BAABLgAECn87AAMCAAkJYRjdAgBBAgACAAkJYRjdAgBBAgABAAgJ2BFNDgCQAQAAAA==.Dellandre:BAABLgAECn8lAAIZAAkJ7Q1RBAADAQAZAAkJ7Q1RBAADAQABLgAECgkJNgAFANgKAA==.Delta:BAABLgAECn8eAAIHAAgJwwjcgQAcAQAHAAgJwwjcgQAcAQAAAA==.Delti:BAAALgAECgUJBgABLgAECgkJHwAHAFcWAA==.Demondozer:BAAALgAECgQJBQABLgAECgcJCwAEAAAAAA==.Demony:BAAALgAECgEJAgABLgAFFAEJAQAEAAAAAA==.Denard:BAAALgAECgUJBgAAAA==.',
Di='Diabolist:BAACLgAFFH8IAAIDAAMJeAi4iQCyAAADAAMJeAi4iQCyAAAuAAQKfxgAAgMACQlgCIdqAGcBAAMACQlgCIdqAGcBAAAA.Digichowder:BAACLgAFFH8SAAMaAAQJTyCAIAAwAQAaAAMJPSSAIAAwAQAQAAEJhhSNQABIAAAuAAQKfyYAAxAACQmxIz8EANoCABAACAkOIT8EANoCABoABQmNHng5AGABAAAA.Dirtmerchant:BAAALgADCgMJAwAAAA==.Dirtygiri:BAAALgADCgEJAgAAAA==.',
Dk='Dkwitch:BAAALgAECgEJAQAAAA==.',
Do='Doktaga:BAAALgAECgYJDgAAAA==.',
Dr='Draex:BAAALgADCgEJAQAAAA==.Dragonzord:BAAALgADCgEJAQAAAA==.Drbubbles:BAAALgADCgYJCAABLgAECgQJCQAEAAAAAA==.Drredd:BAAALgAECgQJBAAAAA==.',
['Dä']='Därkrävèn:BAAALgAECgYJDAAAAA==.',
['Dé']='Déspair:BAAALgAECgEJAQABLgAFFAMJBQAFAGMLAA==.',
Ea='Eama:BAAALgADCgUJBwAAAA==.',
Ed='Edin:BAAALgAECgcJBwABLgAFFAYJIQALAD0VAA==.',
Eg='Eggfield:BAAALgAECgUJBgAAAA==.',
El='Eladora:BAAALgADCgEJAQAAAA==.Eldarr:BAACLgAFFH8HAAIYAAMJlRWYCgDxAAAYAAMJlRWYCgDxAAAuAAQKf0YAAxgACQllIiYBAO8CABgACQllIiYBAO8CAAMABQn6EfSMACABAAAA.Eldhe:BAAALgAECgYJDwAAAA==.Eleos:BAAALgADCgMJBgAAAA==.Elistrae:BAACLgAFFH8MAAIbAAQJXQ+oBQAQAQAbAAQJXQ+oBQAQAQAuAAQKfx8AAxsACQnZFeUZANABABsACQmVDOUZANABABQACAkpFzQzAKABAAAA.',
Em='Emorri:BAAALgAECgYJBgAAAA==.',
En='Enazen:BAABLgAECn8fAAIMAAkJWRp3BQC9AgAMAAkJWRp3BQC9AgAAAA==.Endlol:BAACLgAFFH8IAAIcAAMJWxibCgDuAAAcAAMJWhibCgDuAAAuAAQKfy8AAxwACQkXIY0IAMYCABwACQkXIY0IAMYCAB0AAQlSHwRjAFMAAAAA.',
Er='Eredaria:BAAALgAFFAEJAQAAAA==.Ereshkigal:BAAALgADCgYJCwAAAA==.Ergo:BAACLgAFFH8aAAIXAAgJ7RBGHwAGAgAXAAgJ7RBGHwAGAgAuAAQKfyYAAhcACQmuIhsjAOYCABcACQmuIhsjAOYCAAAA.Eronel:BAABLgAECn8eAAICAAcJ7RoIagCSAQACAAcJ7RoIagCSAQAAAA==.',
Es='Esv:BAABLgAFFH8OAAIPAAQJbAo1DACgAAAPAAQJbAo1DACgAAABLgAFFAUJIgAXAHUYAA==.',
Ex='Excido:BAAALgAECgEJAgAAAA==.Exodiagold:BAAALgAECgEJAQAAAA==.',
Fa='Fadedharanir:BAAALgAECgMJBAAAAA==.Fadedheart:BAAALgAECgYJDAABLgAFFAMJBwACAB4VAA==.Fadedmystic:BAAALgAECgQJBAAAAA==.Fadednight:BAACLgAFFH8HAAICAAMJHhWAQACsAAACAAMJHhWAQACsAAAuAAQKfzYAAwIACQnyH14YALQCAAIACQnyH14YALQCABkAAQnVAW1uAA8AAAAA.Faeyir:BAACLgAFFH8TAAIXAAQJIg8qZAAaAQAXAAQJIg8qZAAaAQAuAAQKfyIAAhcACQnDHT9QAEYCABcACQnDHT9QAEYCAAAA.Fallingmoon:BAABLgAECn8nAAMTAAkJqCDqDwDRAgATAAkJqCDqDwDRAgAUAAEJKRDmigAwAAAAAA==.Fangrage:BAAALgAECgYJBAAAAA==.Fatherlode:BAACLgAFFH8KAAIXAAMJwBg6ggDTAAAXAAMJwBg6ggDTAAAuAAQKfysAAhcACQmUIXsdAKsCABcACQmUIXsdAKsCAAAA.Fathertouchi:BAAALgAECgMJAwAAAA==.',
Fe='Feltpen:BAAALgAECgUJBQAAAA==.Femcelibate:BAAALgADCgcJCAAAAA==.Fentenjoyer:BAAALgAECgcJDwAAAA==.Fernfondler:BAAALgAFFAIJAwABLgAFFAMJCAAcAFsYAA==.Ferrilata:BAAALgADCgcJBgAAAA==.',
Fi='Fivebones:BAAALgAECgQJBAAAAA==.',
Fl='Flashylights:BAAALgADCgYJBgAAAA==.',
Fo='Fontane:BAAALgADCgYJBwAAAA==.Forcebolt:BAAALgADCgMJAwAAAA==.',
Fr='Fredgoofin:BAAALgAECgIJAgAAAA==.Freecookies:BAAALgAECgYJCQAAAA==.Frostybop:BAAALgAECgMJBAABLgAECgIJAgAEAAAAAA==.Frostybreath:BAAALgAECgIJAgAAAA==.Frostybrews:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.Frostydh:BAAALgAECgMJAwABLgAECgIJAgAEAAAAAA==.Frostytotems:BAAALgAECgQJBgAAAA==.Frozenshade:BAAALgAECgUJCQABLgAECgkJRQAbAH4dAA==.Fróstblight:BAAALgAECgkJCAAAAA==.',
Fu='Furryiosa:BAAALgADCgYJBgAAAA==.',
Ga='Gauntodimm:BAAALgAECgYJCgAAAA==.',
Gh='Ghosted:BAAALgAECgUJDQAAAA==.',
Gi='Gilberticus:BAABLgAECn8lAAMbAAgJWBoHAQAaAgAbAAgJWBoHAQAaAgATAAUJRBY1rQDpAAABLgAECgkJUwAeAMUiAA==.Gishmou:BAABLgAECn8fAAIVAAkJwRh/JgAoAgAVAAkJwRh/JgAoAgAAAA==.',
Go='Goldblade:BAABLgAECn8gAAIRAAgJWhfuUwDOAQARAAgJWhfuUwDOAQAAAA==.',
Gr='Grayhair:BAAALgAECgQJCAAAAA==.Greyoll:BAAALgAECgYJCAAAAA==.Grimling:BAAALgAFFAMJAwABLgAFFAYJEgAIAJcVAA==.Grindlewald:BAAALgAECgIJAgAAAA==.',
Gu='Gutted:BAACLgAFFH8gAAMZAAgJCyPbAAAmAgAZAAgJCyPbAAAmAgACAAEJxQwLGQE8AAAuAAQKfx0AAhkACQkZJr0BAGcDABkACQkZJr0BAGcDAAAA.',
['Gä']='Gärin:BAAALgADCggJFAAAAA==.',
Ha='Hanna:BAAALgAFFAEJAQABLgAFFAgJIAAZAAsjAA==.Harleyswar:BAAALgADCgEJAQAAAA==.',
He='Hellmaw:BAAALgAECgYJCwAAAA==.',
Hi='Highly:BAAALgADCgcJCwAAAA==.',
Ho='Holianna:BAAALgAECgMJAwAAAA==.Hollowheart:BAABLgAECn9BAAMVAAkJax3/DwDRAgAVAAkJax3/DwDRAgAWAAEJkyFJMwBjAAAAAA==.Holycourtney:BAAALgADCgkJEQAAAA==.Holyfur:BAAALgAECgYJBgABLgAECgkJPAAKAN8eAA==.Holyknight:BAAALgADCgEJAQAAAA==.Hotsausage:BAAALgAECgMJAwAAAA==.Hoved:BAAALgADCgEJAQAAAA==.',
Hu='Huang:BAAALgAECgMJAwAAAA==.',
Hy='Hylanna:BAAALgAECgcJDAAAAA==.Hyorinmaru:BAAALgAFFAEJAgAAAA==.',
['Hó']='Hónor:BAAALgADCgMJAwABLgAFFAMJBQAFAGMLAA==.',
Ic='Ici:BAABLgAECn80AAMRAAkJ3QmDigBbAQARAAkJ3QmDigBbAQAKAAQJuA6AXQDAAAAAAA==.Icritdaily:BAAALgADCgYJCwAAAA==.',
If='Iffybacon:BAAALgAECgIJAgABLgAECgQJCwAEAAAAAA==.',
Ik='Ikilledkeny:BAAALgAFFAMJAQAAAA==.',
Im='Imlerith:BAAALgADCgQJBgAAAA==.',
In='Intensifies:BAAALgAECgcJEgAAAA==.',
Ip='Ippo:BAAALgADCgEJAQAAAA==.',
Is='Isabellà:BAABLgAECn8eAAIFAAkJKxDjEgCbAQAFAAkJKxDjEgCbAQABLgAECgkJKQAfADMNAA==.Iskothar:BAABLgAECn82AAIFAAkJcCGyAgD/AgAFAAkJcCGyAgD/AgAAAA==.',
It='Itsbob:BAAALgAECgQJAQAAAA==.',
Iv='Ivarboneless:BAABLgAECn8eAAIKAAgJFB9JEwB2AgAKAAgJFB9JEwB2AgAAAA==.',
Ja='Jackz:BAAALgAECgkJCQAAAA==.Jackzdk:BAAALgAECgkJCQAAAA==.Jackzlock:BAAALgAECgkJAQAAAA==.Jakethemage:BAAALgADCgUJCAAAAA==.Jankball:BAAALgAFFAMJAQAAAA==.Jatkal:BAAALgAFFAEJAgAAAA==.Jayreezy:BAAALgAECgQJBAAAAA==.',
Je='Jefftrep:BAAALgAECgQJAwAAAA==.Jerihatrix:BAAALgAECgEJAQAAAA==.',
Ji='Jimmylahey:BAAALgAECgMJAwAAAA==.',
Jo='Jonah:BAAALgADCgEJAQAAAA==.',
Ka='Kaina:BAAALgADCgYJCQAAAA==.Kakidruid:BAAALgAECgIJAwAAAA==.Kalfu:BAABLgAECn8UAAMcAAkJygzYKwB2AQAcAAkJygzYKwB2AQAgAAgJFwnqMQBTAQAAAA==.',
Ke='Ketesh:BAACLgAFFH8LAAIhAAMJQRtLBwDoAAAhAAMJQRtLBwDoAAAuAAQKfzwAAiEACQnNIH8DAO0CACEACQnNIH8DAO0CAAEuAAUUBgkhAAsAPRUA.',
Ki='Kilorean:BAAALgAECgcJCAAAAA==.Kirae:BAAALgAECgYJEAABLgAECgkJNgAFAHAhAA==.',
Kl='Kleanse:BAAALgAFFAMJAQAAAA==.',
Kn='Knastey:BAABLgAECn8VAAQfAAYJ4Bc9NgA9AQAfAAYJ4Bc9NgA9AQAOAAYJZAqbcQABAQANAAEJWxKCMgA3AAAAAA==.Knasty:BAAALgADCgEJAQAAAA==.',
Ko='Kodera:BAABLgAECn8iAAILAAYJQQVPZwClAAALAAYJQQVPZwClAAAAAA==.',
Kr='Krej:BAABLgAECn8XAAIZAAkJMBwzDwAYAgAZAAkJMBwzDwAYAgABLgAFFAYJEgAIAJcVAA==.Krisskringle:BAAALgAECgMJBgAAAA==.',
Ku='Kuromori:BAAALgADCgYJBgAAAA==.',
Ky='Kyronix:BAAALgAECgMJBwAAAA==.',
['Kê']='Kênpachi:BAAALgAECgYJDgAAAA==.',
La='Landrey:BAAALgADCgkJCwAAAA==.Langarde:BAABLgAECn8fAAIPAAkJCxDHFgCNAQAPAAkJCxDHFgCNAQAAAA==.Laoghaire:BAABLgAECn8YAAIIAAcJ+APYQgCrAAAIAAcJ+APYQgCrAAAAAA==.',
Le='Leonz:BAACLgAFFH8bAAIaAAgJDhuEAwBMAgAaAAgJDhuEAwBMAgAuAAQKfy4AAhoACQmaJCcFABADABoACQmaJCcFABADAAAA.Leonzs:BAAALgAECggJEAAAAA==.Letharanos:BAECLgAFFH8KAAMCAAQJQBLTPgCxAAACAAQJQBLTPgCxAAAZAAEJfQdjQwAoAAAuAAQKfycAAwIACQl0GQ9FAPMBAAIACQl0GQ9FAPMBABkAAQl7DuRgACgAAAAA.',
Li='Liraffemynn:BAACLgAFFH8bAAIiAAUJhxv+HQCAAQAiAAUJhxv+HQCAAQAuAAQKfz4AAiIACQmOI8UDAHsDACIACQmOI8UDAHsDAAAA.Liralynn:BAAALgADCgUJBQAAAA==.',
Lk='Lkynyx:BAAALgADCgYJAQAAAA==.',
Lo='Lonranir:BAAALgAECgYJEwAAAA==.Lostinlight:BAAALgAECgYJBgAAAA==.',
Lu='Lucii:BAAALgADCgEJAQABLgAFFAgJIAAZAAsjAA==.Luckylucy:BAABLgAECn8XAAIdAAYJhhanLgBZAQAdAAYJhhanLgBZAQAAAA==.',
Ma='Madarauchiha:BAABLgAECn8aAAICAAYJ6BpwggB+AQACAAYJ6BpwggB+AQAAAA==.Magus:BAAALgADCgkJFgABLgAECgUJDQAEAAAAAA==.Maldran:BAABLgAECn8lAAIVAAcJjh3bKgAPAgAVAAcJjh3bKgAPAgAAAA==.Maling:BAAALgAECgEJAQAAAA==.Manderpants:BAABLgAECn8gAAITAAcJVwqqgwA3AQATAAcJVwqqgwA3AQAAAA==.Marien:BAABLgAECn8fAAIZAAkJHBl/DQAyAgAZAAkJHBl/DQAyAgAAAA==.Marty:BAAALgAECgIJAwAAAA==.Maxus:BAAALgADCgUJBQAAAA==.',
Mb='Mbbin:BAACLgAFFH8RAAIXAAMJFyXeIgAEAQAXAAMJFyXeIgAEAQAuAAQKfyoAAhcACQntIQcdAK4CABcACQntIQcdAK4CAAAA.',
Me='Medraneiprst:BAAALgAECgIJAgAAAA==.Mehuman:BAABLgAECn8cAAIRAAgJYhJ8jABYAQARAAgJYhJ8jABYAQAAAA==.Mehumanhuntr:BAAALgAECgUJBwAAAA==.Mehumanlock:BAABLgAECn8jAAIYAAkJ+xEWCgCkAQAYAAkJ+xEWCgCkAQAAAA==.Menedemnhntr:BAAALgAECgYJBgAAAA==.Merlinn:BAAALgADCgkJDAAAAA==.Merran:BAAALgADCgEJAQAAAA==.Metal:BAAALgADCgQJBAAAAA==.Meworgendk:BAABLgAECn8UAAIZAAYJNhULBAAUAQAZAAYJNhULBAAUAQAAAA==.',
Mh='Mhoo:BAAALgADCgcJBwAAAA==.',
Mi='Miriym:BAAALgADCgEJAQAAAA==.Miräj:BAAALgAECgcJDAAAAA==.Mistyblue:BAAALgAECgEJAQAAAA==.Miya:BAAALgADCgcJDQAAAA==.',
Mo='Moonscale:BAAALgAECgUJCQAAAA==.Mordaci:BAAALgADCgQJBQABLgAECggJGwARAIMZAA==.Mordekrieg:BAABLgAFFH8GAAICAAMJUAt2rgDFAAACAAMJUAt2rgDFAAAAAA==.Mortstan:BAABLgAFFH8FAAIZAAUJYxhTCAAiAQAZAAUJYxhTCAAiAQAAAA==.',
Mu='Mutegen:BAAALgADCgUJBQABLgAFFAUJBQAjAHICAA==.',
My='Myash:BAAALgAECgcJDQAAAA==.',
['Må']='Månni:BAAALgADCgYJBwAAAA==.',
['Mé']='Mélusine:BAAALgADCgEJAQAAAA==.',
Na='Nailia:BAAALgAECgcJCwAAAA==.Nailz:BAABLgAECn8fAAIHAAkJVxZCTwCYAQAHAAkJVxZCTwCYAQAAAA==.Nakama:BAAALgADCgYJBgABLgAECgkJNgAGAHsOAA==.Nardog:BAAALgAECgEJAQAAAA==.Narie:BAAALgAECggJCQAAAA==.Nasaug:BAAALgAECgUJCwABLgAFFAMJBQAFAGMLAA==.',
Ne='Ned:BAAALgAECgEJAQAAAA==.Neuse:BAAALgAECggJEwAAAA==.',
Ni='Nightlion:BAABLgAECn8mAAIhAAkJRhGeBQDuAAAhAAkJRhGeBQDuAAAAAA==.Nillius:BAAALgADCgIJAgAAAA==.Nisu:BAAALgAECgEJAQAAAA==.',
No='Noahdh:BAAALgAECgMJAwABLgAFFAgJHwADABAYAA==.Noahpriest:BAAALgAECgMJAwABLgAFFAgJHwADABAYAA==.Noahvoker:BAAALgAECggJEQABLgAFFAgJHwADABAYAA==.Noahwarlock:BAACLgAFFH8fAAQDAAgJEBjLIQDHAQADAAYJTh3LIQDHAQAYAAMJXxFuCwDkAAAkAAEJkSOAIABQAAAuAAQKfzIABAMACQmFJAEFAD8DAAMACAlsJAEFAD8DABgABAl0IkEaAHsBACQAAwmsI4IWAM0AAAAA.Nonsensical:BAAALgADCgUJBQABLgAECgYJJQAiAHkjAA==.Nook:BAAALgADCgUJBgAAAA==.Nowere:BAAALgADCgcJBwAAAA==.Noxander:BAAALgAECgEJAQAAAA==.',
Ny='Nym:BAAALgAECgkJEQAAAA==.',
['Nâ']='Nârenth:BAAALgADCgMJAwAAAA==.',
Oa='Oaths:BAABLgAECn8YAAMRAAgJmQicEgDcAAARAAgJKwacEgDcAAAFAAQJhQgLOAB/AAAAAA==.',
Oh='Ohmylanta:BAAALgAFFAIJBAAAAA==.Ohmylantä:BAABLgAECn8dAAIXAAgJPg0FjABfAQAXAAgJPg0FjABfAQAAAA==.Ohmylantå:BAAALgADCgUJCAAAAA==.',
On='Ondeane:BAAALgADCgEJAQAAAA==.Onumae:BAABLgAECn8XAAIRAAkJcRr+MQA4AgARAAkJcRr+MQA4AgAAAA==.',
Op='Oprime:BAAALgADCgMJAwAAAA==.',
Or='Orbeck:BAAALgAECggJCAABLgAFFAgJHQAJAIocAA==.Ormond:BAABLgAECn8fAAMKAAcJJhirKgC6AQAKAAcJJhirKgC6AQARAAUJPAWIHAGXAAAAAA==.Orochinchin:BAAALgAECgUJBQABLgAFFAgJIAAZAAsjAA==.',
Os='Oscarmike:BAAALgADCgcJDQAAAA==.',
Oz='Ozlon:BAAALgAECgcJEwAAAA==.',
['Oâ']='Oâth:BAABLgAECn8xAAQlAAkJpg2kDQB4AQAlAAkJpg2kDQB4AQAHAAQJqAr9FQB9AAAIAAMJRgawZQBCAAAAAA==.',
Pa='Pachane:BAAALgAECgQJCwAAAA==.Paldozer:BAAALgAECgUJDQABLgAECgcJCwAEAAAAAA==.Pallywacker:BAACLgAFFH8FAAIFAAIJtgkWEwBhAAAFAAIJtgkWEwBhAAAuAAQKfzIAAgUACAlSE5wUAIYBAAUACAlSE5wUAIYBAAAA.Pankins:BAAALgAECgMJAwAAAA==.Panzerkan:BAAALgAECgEJAQAAAA==.Panzerkìn:BAAALgAECgcJCAAAAA==.',
Pe='Percymorris:BAAALgADCgYJBwAAAA==.Peythilly:BAAALgAECgQJBAAAAA==.',
Pi='Pigishdog:BAACLgAFFH8LAAIDAAMJ8goNLQCnAAADAAMJ8goNLQCnAAAuAAQKf1kAAwMACQnJHecTAK4CAAMACQnJHecTAK4CABgAAQnVEbM9ADYAAAAA.Pikon:BAAALgADCgkJDQAAAA==.',
Po='Pokeabear:BAAALgAECgYJEAABLgAECgcJEAAEAAAAAA==.Pokethedruid:BAAALgAECgEJAQABLgAECgEJBwAEAAAAAA==.Pokethemonk:BAAALgAECgEJBwAAAA==.Poshingtang:BAABLgAECn8pAAQVAAkJqQzYRACbAQAVAAkJqQzYRACbAQAGAAgJHhG8NgB4AQAWAAMJSwP+JQB3AAAAAA==.',
Pu='Pulsar:BAAALgAECgQJBwAAAA==.Punchies:BAAALgADCggJDQAAAA==.',
Qu='Quatrain:BAABLgAECn82AAMGAAkJew4ZOQBSAQAGAAgJ/g8ZOQBSAQAVAAgJrxDTXABGAQAAAA==.Quelana:BAAALgADCgMJAwAAAA==.Quintessence:BAAALgAECgMJAwAAAA==.',
Ra='Rabidbutt:BAAALgAFFAMJBAABLgAFFAcJGgAMAF0gAA==.Ragerunner:BAAALgADCgkJEwAAAA==.Rakarg:BAABLgAECn8ZAAICAAUJDBj40ADnAAACAAUJDBj40ADnAAAAAA==.Ravenus:BAAALgAECgEJAQAAAA==.',
Re='React:BAAALgAECggJCAABLgAFFAMJCAAcAFsYAA==.Redemptor:BAAALgAECgUJBQAAAA==.Refund:BAAALgAECgEJAQAAAA==.Regalbacon:BAAALgAECgMJAwAAAA==.Reygina:BAABLgAECn8ZAAIKAAYJygIuYAC1AAAKAAYJygIuYAC1AAAAAA==.',
Ri='Rickÿ:BAAALgAECgEJAQAAAA==.Rikku:BAAALgAECggJCAABLgAFFAgJHAAGACoTAA==.Ripndip:BAAALgAFFAMJAQAAAA==.Riprock:BAAALgAFFAEJAQABLgAFFAMJAQAEAAAAAA==.Rixas:BAAALgAECgEJAQABLgAECgkJMwADACkdAA==.',
Rn='Rn:BAACLgAFFH8FAAIQAAQJShiPGgATAQAQAAQJShiPGgATAQAuAAQKfx4AAxAACQklIkEBAEYDABAACQkIIkEBAEYDABoABwkvIyQpABcCAAEuAAUUCAkiABAAgyQA.',
Ro='Rodeo:BAAALgAECgMJBgAAAA==.Roguehiro:BAABLgAECn8pAAIFAAgJxSEKBgCKAgAFAAgJxSEKBgCKAgAAAA==.Rooter:BAACLgAFFH8aAAMMAAcJXSCCBACVAgAMAAcJXSCCBACVAgALAAEJTBO9KABFAAAuAAQKfz0AAwwACQkRJB8BAJ8DAAwACQkRJB8BAJ8DAAsABwnsGeklALABAAAA.Roronoaxd:BAAALgADCgMJAwAAAA==.Rosalynñ:BAABLgAECn8pAAIYAAgJMgpXFAAMAQAYAAgJMgpXFAAMAQAAAA==.',
Ru='Ruikhai:BAAALgADCgMJBQABLgADCgkJBwAEAAAAAA==.Ruto:BAAALgAFFAEJAQABLgAFFAMJAQAEAAAAAA==.',
Sa='Sacea:BAAALgADCgUJBQAAAA==.Saelis:BAACLgAFFH8aAAIOAAUJjBeMCgAjAQAOAAUJjBeMCgAjAQAuAAQKfyAAAw4ACQkaIQEMAAADAA4ACQkaIQEMAAADAA0ABgnwGRYUAH8BAAAA.Salen:BAAALgAECgEJAQAAAA==.Samshara:BAAALgAECggJCAABLgAECgkJRQAbAH4dAA==.Saptapper:BAAALgAECgIJAgAAAA==.Saracenio:BAAALgADCgEJAQAAAA==.',
Sc='Schnem:BAAALgAECggJCgAAAA==.Scrawni:BAAALgAECgcJDAABLgAFFAYJEgAIAJcVAA==.Scrounge:BAAALgAFFAEJAQABLgAFFAMJCAADAHgIAA==.',
Se='Securìty:BAAALgAECgQJBQAAAA==.Selyane:BAAALgADCgkJCQAAAA==.Seong:BAACLgAFFH8dAAIJAAgJihz5BQA2AgAJAAgJihz5BQA2AgAuAAQKfyIAAgkACQmAIgUFADkDAAkACQmAIgUFADkDAAAA.Seongdh:BAAALgAECggJDQABLgAFFAgJHQAJAIocAA==.Seongwar:BAAALgAECgMJAwAAAA==.Seraphinà:BAABLgAECn8VAAIXAAcJxgtMFADQAAAXAAcJxgtMFADQAAABLgAECgkJKQAfADMNAA==.',
Sh='Shadowdooms:BAABLgAECn8WAAMCAAgJFBkfYQDQAQACAAgJFBkfYQDQAQABAAEJSxf2FABFAAAAAA==.Shadowfur:BAABLgAECn8VAAISAAgJ8Ar7AAAcAQASAAgJ8Ar7AAAcAQABLgAECgkJPAAKAN8eAA==.Shamynna:BAAALgAECgUJCAAAAA==.Sharpshotjak:BAAALgAFFAgJBAAAAA==.Sharreth:BAAALgAECgIJAgAAAA==.Shii:BAAALgADCgUJBQAAAA==.Shimera:BAABLgAECn8zAAITAAkJNhMjPgDpAQATAAkJNhMjPgDpAQAAAA==.Shish:BAAALgAECggJCwAAAA==.Shizukura:BAAALgADCgEJAQAAAA==.Shockawar:BAACLgAFFH8WAAIaAAUJeRwxAwDEAQAaAAUJeRwxAwDEAQAuAAQKfxkAAhoACQmrHmYYAIgCABoACQmrHmYYAIgCAAAA.Shooter:BAAALgADCgIJAgAAAA==.Shootrmcgavn:BAACLgAFFH8hAAQTAAcJACHEJAByAQATAAYJAB7EJAByAQAbAAQJRSHkDABdAQAUAAUJcB1KCQCsAAAuAAQKfxsABBMACAk8IdMVAIkCABMABwnxIdMVAIkCABQABwlKIcoaAFMCABsAAwm3IXcxACABAAAA.Shu:BAAALgAFFAIJAgAAAA==.Shuletaa:BAAALgAECgIJBAAAAA==.Shïsh:BAAALgADCgcJBwABLgAECggJCwAEAAAAAA==.',
Si='Silverwolf:BAAALgADCgEJAQAAAA==.Sinestra:BAAALgAECgEJAQAAAA==.',
Sk='Skibidi:BAAALgAECgcJDgABLgAFFAQJFgAXAMQaAA==.Skofung:BAAALgAECgEJAQAAAA==.',
Sl='Slagscar:BAAALgAFFAIJAQAAAA==.Slaughterhse:BAABLgAECn8XAAIXAAYJ5gOr+gC0AAAXAAYJ5gOr+gC0AAAAAA==.Slootar:BAABLgAECn8UAAQOAAcJ5xuIJAAoAgAOAAcJ5xuIJAAoAgAfAAIJuxBfbABuAAANAAIJMAZVVwAsAAAAAA==.Slugs:BAAALgAECgUJCAAAAA==.',
Sn='Snizzy:BAAALgAECgYJBgAAAA==.Snqwflake:BAABLgAECn8VAAIiAAgJ7xb8FQAUAgAiAAgJ7xb8FQAUAgAAAA==.',
So='Solareth:BAAALgAECgEJAwAAAA==.Solthin:BAAALgAFFAMJAQAAAA==.Somebeotch:BAAALgADCgYJBgAAAA==.Somerled:BAABLgAECn9FAAIbAAkJfh1tCACXAgAbAAkJfh1tCACXAgAAAA==.',
Sp='Spyroid:BAAALgAECgUJAQAAAA==.',
St='Static:BAAALgADCgcJBwABLgAECgYJCgAEAAAAAA==.',
Su='Sunstrike:BAAALgAECgEJAgAAAA==.',
Sy='Sylvanna:BAAALgADCgQJBAAAAA==.',
Ta='Tabul:BAAALgADCgcJCAAAAA==.Takka:BAACLgAFFH8KAAIVAAYJcwZVDQAtAQAVAAYJcwZVDQAtAQAuAAQKfxsAAhUACAkdHR0YAIgCABUACAkdHR0YAIgCAAAA.Talden:BAACLgAFFH8MAAMRAAMJzxF4IgDMAAARAAMJUhB4IgDMAAAFAAEJRRhpFgBHAAAuAAQKf0UAAxEACQkyHMkfAIkCABEACQkyHMkfAIkCAAUAAwnNEFFGAEwAAAAA.Talkamar:BAACLgAFFH8HAAIeAAMJiRPJIgDKAAAeAAMJiRPJIgDKAAAuAAQKfyMAAh4ACQn7EeoeALYBAB4ACQn7EeoeALYBAAAA.Taylorswift:BAABLgAECn83AAIXAAkJ8xivLABmAgAXAAkJ8xivLABmAgAAAA==.Tazzaar:BAAALgAECgMJAwAAAA==.',
Th='Thaelios:BAAALgADCgEJAQAAAA==.Thekourge:BAABLgAECn82AAIFAAkJ2ApYGwA9AQAFAAkJ2ApYGwA9AQAAAA==.Thenard:BAABLgAECn8jAAITAAgJPBPrVgCfAQATAAgJPBPrVgCfAQAAAA==.Therealcafna:BAAALgADCgcJBwAAAA==.Thukunaenhan:BAAALgAECgQJBAABLgAFFAQJFgAXAMQaAA==.Thukunamage:BAACLgAFFH8WAAIXAAQJxBrqJwDlAAAXAAQJxBrqJwDlAAAuAAQKfyoAAhcACQmyIIchAJcCABcACQmyIIchAJcCAAAA.',
Ti='Tibarius:BAAALgADCgkJEgAAAA==.Tili:BAAALgADCgkJEAAAAA==.Tinaraeda:BAAALgAECgMJAwAAAA==.',
To='Tomislav:BAABLgAECn8lAAQDAAkJcBvfKwAqAgADAAcJrBnfKwAqAgAYAAQJ2xqmIACoAAAkAAEJlA7sPAA4AAAAAA==.Tomuchmakeup:BAAALgAECgMJAwAAAA==.Touritos:BAABLgAECn8eAAIGAAkJdRGbKgCdAQAGAAkJdRGbKgCdAQAAAA==.',
Tr='Trimblestein:BAAALgAECgcJDQAAAA==.Troyka:BAAALgAECgEJAQAAAA==.Truefitt:BAAALgAECgYJEwAAAA==.',
Tu='Tulikettwo:BAAALgAECgEJAQAAAA==.Tulirenpo:BAAALgAECgUJBQAAAA==.Tunk:BAAALgAFFAMJAQAAAA==.Tuskal:BAAALgAECgIJAwAAAA==.',
Tw='Twogora:BAAALgAECgYJCQAAAA==.Twohoofy:BAAALgADCgcJBgAAAA==.',
Ty='Tydes:BAABLgAECn8bAAMjAAgJ6RbMEwB4AgAjAAgJ6RbMEwB4AgAmAAEJtgtBHQBBAAAAAA==.Tydru:BAAALgAFFAMJAQAAAA==.Tyler:BAACLgAFFH8LAAIHAAQJfhXYDwBPAQAHAAQJfhXYDwBPAQAuAAQKfxsAAgcACAkOHTgcAKkCAAcACAkOHTgcAKkCAAAA.Tystin:BAAALgADCgQJBQABLgADCgkJBwAEAAAAAA==.',
Ud='Uddermilk:BAABLgAECn8cAAIfAAcJ/AmzCAC3AAAfAAcJ/AmzCAC3AAAAAA==.',
Um='Umariel:BAAALgAFFAMJAQAAAA==.',
Va='Valina:BAAALgADCgIJAgAAAA==.Valissar:BAAALgAECgMJBwAAAA==.Valkyrja:BAAALgAECgEJAQAAAA==.Valr:BAACLgAFFH8FAAIFAAMJYws2DgCaAAAFAAMJYws2DgCaAAAuAAQKfzQAAgUACQm3DxYXAGgBAAUACQm3DxYXAGgBAAAA.Vancliffe:BAAALgAECgQJBAABLgAFFAYJEgAIAJcVAA==.Vandreu:BAAALgADCgUJBQAAAA==.',
Ve='Verpally:BAAALgADCgMJAwAAAA==.',
Vi='Viparia:BAAALgAECgkJAgAAAA==.Virulent:BAAALgAECgMJAwAAAA==.',
Vo='Voloaura:BAAALgADCgMJAwAAAA==.',
Vs='Vse:BAACLgAFFH8iAAIXAAUJdRg8IwACAQAXAAUJdRg8IwACAQAuAAQKfy4AAhcACAl8GzlIAAICABcACAl8GzlIAAICAAAA.Vsesosorry:BAABLgAFFH8VAAIVAAQJZxS2NgAHAQAVAAQJZxS2NgAHAQABLgAFFAUJIgAXAHUYAA==.Vsè:BAAALgAFFAIJAgABLgAFFAUJIgAXAHUYAA==.',
Vy='Vyke:BAAALgAECgkJEgABLgAFFAgJHQAJAIocAA==.',
['Ví']='Ví:BAAALgAECgYJBgAAAA==.',
Wa='Wammo:BAAALgAECgYJCgAAAA==.Waq:BAAALgADCgMJBgAAAA==.Wardozer:BAAALgAECgcJCwAAAA==.Warlockedin:BAAALgAECgYJDQAAAA==.',
We='Weierstrass:BAAALgAFFAEJAQABLgAFFAgJIAAZAAsjAA==.',
Wo='Worgenkrantz:BAABLgAECn8pAAMfAAkJMw3RKQCFAQAfAAkJMw3RKQCFAQAOAAcJeAJQkgCrAAAAAA==.',
Wr='Wrathlor:BAAALgADCgcJBQAAAA==.Wrenlyn:BAACLgAFFH8SAAMIAAYJlxV7EgAQAQAIAAUJ5RV7EgAQAQAHAAIJKQx9ewCHAAAuAAQKfzAAAwgACAlsI9kOADgCAAgACAntH9kOADgCACUAAglCE7clAHIAAAAA.',
Wu='Wukain:BAAALgADCgEJAQAAAA==.',
Xa='Xanatas:BAABLgAECn8jAAIZAAcJhBvmAQDLAQAZAAcJhBvmAQDLAQABLgAECgkJNgAFAHAhAA==.',
Xo='Xolòtl:BAABLgAECn8rAAIPAAkJqxnYAABLAgAPAAkJqxnYAABLAgABLgAFFAYJEgAIAJcVAA==.Xoss:BAAALgAFFAMJAQAAAA==.',
Yg='Yggdrasali:BAAALgAECgQJBgABLgAFFAUJBwAiAPEFAA==.',
Yi='Yin:BAAALgAECgcJCAAAAA==.',
Yo='Yourhero:BAAALgAECgEJAgAAAA==.Yourportsir:BAAALgADCgIJAgAAAA==.',
Ys='Yserra:BAAALgAECgcJDAAAAA==.',
Za='Zaerine:BAAALgAECgYJBgAAAA==.Zakuso:BAAALgAECgQJCQAAAA==.Zalatha:BAAALgADCgEJAQAAAA==.Zalyia:BAABLgAECn8uAAIcAAkJlA2BJwCSAQAcAAkJlA2BJwCSAQAAAA==.Zapix:BAAALgAECgEJAQABLgAECgMJBwAEAAAAAA==.',
Ze='Zephinar:BAABLgAECn8ZAAIXAAgJcBVpaQADAgAXAAgJcBVpaQADAgAAAA==.Zexpert:BAABLgAECn8dAAQnAAgJkheiDQAAAgAnAAcJdxiiDQAAAgALAAcJnhUvKAB8AQAMAAQJfgwFNADNAAAAAA==.',
Zq='Zquestion:BAAALgAECgIJBAABLgAECggJHQAnAJIXAA==.',
Zu='Zulblade:BAABLgAECn8SAAIHAAgJORqFMAA5AgAHAAgJORqFMAA5AgAAAA==.Zulpally:BAABLgAECn8aAAQRAAUJQBa4ygD6AAARAAQJxhi4ygD6AAAKAAMJyRCQcgCxAAAFAAQJ+QiuMQCIAAAAAA==.',
['Zô']='Zôrt:BAAALgAECggJEAAAAA==.',
['Àn']='Àngron:BAAALgADCgYJDAAAAA==.',
['Âr']='Ârtemis:BAAALgAECgcJEAAAAA==.',
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
