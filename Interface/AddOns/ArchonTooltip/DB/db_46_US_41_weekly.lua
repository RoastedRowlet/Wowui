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

local lookup = {'Priest-Discipline','Monk-Brewmaster','Mage-Frost','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Warlock-Demonology','Shaman-Restoration','DeathKnight-Blood','Hunter-Marksmanship','Shaman-Elemental','Priest-Holy','Druid-Restoration','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Fire','Rogue-Subtlety','Hunter-Survival','Warrior-Protection','Warrior-Arms','Warrior-Fury','Shaman-Enhancement','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Hunter-BeastMastery','DemonHunter-Havoc','Evoker-Augmentation','Mage-Arcane','Priest-Shadow','DeathKnight-Frost','Evoker-Preservation','Rogue-Assassination','Rogue-Outlaw','Evoker-Devastation',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aahzbear:BAAALgAFFAEJAQAAAA==.',
Ab='Abreale:BAAALgADCgMJAwAAAA==.Abruum:BAAALgADCgcJBwAAAA==.',
Ae='Aeero:BAABLgAECn8UAAIBAAYJNhfEHwCWAQABAAYJNhfEHwCWAQAAAA==.Aerendyl:BAAALgAECgcJCwAAAA==.',
Ai='Aiden:BAACLgAFFH8HAAICAAMJbRBwNwC9AAACAAMJbRBwNwC9AAAuAAQKfxQAAgIABgkfHF8qALcBAAIABgkfHF8qALcBAAAA.',
Al='Algros:BAAALgADCgEJAQAAAA==.Alyiriia:BAAALgAECgkJCQAAAA==.',
Am='Amathal:BAABLgAECn8ZAAIDAAgJ+hPGhgBjAQADAAgJ+hPGhgBjAQAAAA==.Amilea:BAAALgAFFAEJAQABLgABCgkJEgAEAAAAAA==.',
An='Anastasia:BAAALgADCggJCAAAAA==.Angelsevoker:BAAALgAECggJCAAAAA==.Angermoonria:BAAALgADCgcJBwAAAA==.Ankheloios:BAAALgADCggJDgAAAA==.Antihiiro:BAAALgAECgMJAwAAAA==.Antipro:BAAALgAFFAEJAQAAAA==.Anubbus:BAAALgAFFAIJAwAAAA==.Anzulok:BAAALgADCgYJAQAAAA==.',
Ar='Arbalest:BAAALgADCgcJBgAAAA==.Aredhela:BAABLgAECn8cAAMFAAgJEhZgHQANAgAFAAgJEhZgHQANAgAGAAQJDxdcuQAFAQAAAA==.Arinth:BAAALgADCggJEQAAAA==.Arkadios:BAAALgAECgIJAgAAAA==.Armpit:BAAALgAECgMJAwAAAA==.',
As='Ascanius:BAAALgADCgQJBAAAAA==.Ashiiro:BAAALgAECgcJEAAAAA==.Ashveil:BAAALgAECgUJBQABLgAECgkJJgAHAEEZAA==.Asia:BAABLgAECn8/AAIIAAkJSSUEBQA7AwAIAAkJSSUEBQA7AwAAAA==.Asmodeius:BAAALgAFFAEJAgAAAA==.Astroprof:BAAALgAECgEJAQABLgAECgYJFAAJAFsaAA==.',
At='Athrea:BAABLgAECn8gAAMHAAkJfR5HEwDNAgAHAAkJ3B1HEwDNAgAKAAUJUBvMIwAqAQAAAA==.',
Au='Auntjemima:BAAALgAECgEJAgAAAA==.Aureleus:BAAALgADCgEJAQAAAA==.',
Aw='Away:BAAALgADCgIJAgAAAA==.',
Az='Azaii:BAAALgADCggJCgAAAA==.Azlear:BAAALgAECgkJBgAAAA==.Azrael:BAAALgAECgIJAwAAAA==.',
Ba='Babilouchoux:BAAALgAECgMJBQAAAA==.Ballz:BAAALgADCgYJBgAAAA==.Bano:BAAALgAECgMJAwAAAA==.Barnre:BAAALgAECgYJCQABLgAECgYJDAAEAAAAAA==.Bash:BAAALgAECgcJDgABLgAECggJKgAKAAgbAA==.Baythos:BAAALgAFFAEJAgAAAA==.',
Bb='Bb:BAAALgAECgIJAQAAAA==.',
Bd='Bdssm:BAAALgAECgcJDwAAAA==.',
Be='Beefstick:BAAALgAECgUJBwAAAA==.Berzercarl:BAAALgAECgEJAQAAAA==.Beserkfury:BAABLgAECn8jAAILAAkJOQ2RDQB6AQALAAkJOQ2RDQB6AQAAAA==.',
Bh='Bhemtu:BAAALgAECgEJAQAAAA==.',
Bi='Biercan:BAAALgAECggJEAAAAA==.Bigcarl:BAAALgADCgMJAwAAAA==.Binke:BAABLgAECn8ZAAIMAAgJlQpxPgAqAQAMAAgJlQpxPgAqAQAAAA==.Bittywhite:BAAALgAECgUJBwAAAA==.Bittywyvern:BAAALgADCgUJCwABLgAECgUJBwAEAAAAAA==.',
Bk='Bkarakh:BAAALgADCgYJDgAAAA==.',
Bl='Blayze:BAABLgAECn8eAAINAAkJ5hMvGAD+AQANAAkJ5hMvGAD+AQAAAA==.Blessidbee:BAAALgAECgEJAQAAAA==.Blightmarx:BAAALgADCgUJCQAAAA==.Blitzwow:BAAALgADCgYJBQAAAA==.Bluemoonflay:BAAALgAECgkJEwAAAA==.Blúnt:BAAALgADCgQJBAAAAA==.',
Bo='Bobheals:BAABLgAECn8pAAMOAAYJ7xRKRwBoAQAOAAUJwRhKRwBoAQAPAAEJAADEhgAAAAAAAA==.Boibye:BAAALgAECgYJDgAAAA==.Bolblock:BAAALgAECgkJDwAAAA==.Bonewolf:BAAALgADCgYJCwAAAA==.Boostedww:BAAALgAECgMJCAAAAA==.Boostie:BAAALgAECgEJAgAAAA==.',
Br='Brambleclaw:BAABLgAECn8/AAIKAAkJRSM1BADsAgAKAAkJRSM1BADsAgAAAA==.Brayker:BAACLgAFFH8GAAIGAAIJLB8BdQCxAAAGAAIJLB8BdQCxAAAuAAQKf0cAAgYACQmjJTQFAEYDAAYACQmjJTQFAEYDAAAA.Breadoneal:BAABLgAECn8pAAMFAAkJ4hl8HQAMAgAFAAgJ9hh8HQAMAgAGAAEJ7QVepAEmAAAAAA==.Breeze:BAAALgAECgYJBgAAAA==.Brewed:BAABLgAECn8xAAMQAAkJmxNpGgDQAQAQAAkJmxNpGgDQAQARAAEJLwHCygALAAAAAA==.Brisketbane:BAAALgAECgcJEAAAAA==.Brokenmask:BAACLgAFFH8PAAIOAAUJ0RUrGwBxAQAOAAUJ0RUrGwBxAQAuAAQKfxUAAw4ACAkOIEobAGECAA4ACAkOIEobAGECABIAAgkLEXyGADIAAAAA.Broxxar:BAAALgAECgIJAgAAAA==.Bruxxe:BAAALgAECgcJAQAAAA==.Brüenor:BAAALgAECgIJAgAAAA==.',
Bu='Burntroot:BAABLgAECn8jAAIMAAgJigXeTwDnAAAMAAgJigXeTwDnAAAAAA==.',
Ca='Caedwyn:BAABLgAECn8yAAIPAAgJqh9hBwBwAgAPAAgJqh9hBwBwAgAAAA==.Caitrakk:BAABLgAECn8UAAMJAAYJWxqgMgC7AQAJAAYJWxqgMgC7AQAMAAUJYhC9TAAVAQAAAA==.Calignus:BAABLgAECn8dAAMGAAgJyRGGpAAkAQAGAAgJyRGGpAAkAQATAAUJVQ8jJwDQAAAAAA==.Captjack:BAABLgAECn8dAAIUAAkJrAshZABTAQAUAAkJrAshZABTAQAAAA==.Cartilage:BAABLgAECn8lAAIHAAkJXRTMPwD8AQAHAAkJXRTMPwD8AQAAAA==.Catalei:BAAALgAECgYJDwAAAA==.Caution:BAAALgADCgYJCwAAAA==.',
Ce='Celira:BAAALgAECgEJAQAAAA==.Celys:BAAALgAECgIJAgAAAA==.',
Ch='Chickenman:BAAALgAECgEJAQAAAA==.Chillidan:BAAALgAECgQJBwABLgAFFAEJAQAEAAAAAA==.Chiselia:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Choconilla:BAAALgAECgcJEwAAAA==.Chonkmonk:BAAALgADCgQJBAAAAA==.Choppa:BAAALgADCggJCgAAAA==.Chorizo:BAAALgAECgEJAQABLgAECgkJHQARAIIgAA==.Chupacabrass:BAAALgADCgYJBgAAAA==.Chëbbles:BAAALgADCgMJAwABLgAECgkJJgASABUXAA==.',
Ci='Cinnomun:BAAALgADCgEJAQAAAA==.',
Co='Combustinme:BAAALgAECgQJBAABLgAECggJNgAUACEZAA==.Consuming:BAABLgAECn8tAAIOAAkJpROKLgDhAQAOAAkJpROKLgDhAQAAAA==.Coorsbanquet:BAABLgAECn8ZAAMVAAgJUBlTCADiAQAVAAgJUBlTCADiAQAUAAIJuAkdCwEvAAAAAA==.Coorsbite:BAAALgADCgcJCAAAAA==.Corgh:BAABLgAECn8kAAIWAAYJtw4XBgBIAQAWAAYJtw4XBgBIAQAAAA==.Corrahthecow:BAAALgADCgEJAQAAAA==.Cowardice:BAAALgADCgYJCwAAAA==.',
Cr='Craccjar:BAAALgAECgQJBwAAAA==.Crackjar:BAAALgADCgcJDAAAAA==.Crash:BAECLgAFFH8QAAIUAAYJMBjYJwBwAQAUAAYJMBjYJwBwAQAuAAQKfzcAAxQACAn2JK0MANkCABQACAn2JK0MANkCABUAAQkwGaAtAEAAAAAA.Croarik:BAAALgAECgEJAQAAAA==.Crushix:BAABLgAECn81AAIFAAkJKhhHHwAfAgAFAAkJKhhHHwAfAgAAAA==.',
Cs='Csyasha:BAAALgAECgYJCQAAAA==.',
Cy='Cybear:BAAALgAECgYJCAAAAA==.Cykun:BAABLgAECn8uAAIXAAkJcSD6BwCcAgAXAAkJcSD6BwCcAgAAAA==.',
['Cã']='Cãs:BAAALgADCgkJCgABLgAECgkJGgAOALQNAA==.',
Da='Darch:BAABLgAECn8/AAMYAAkJMCSDAwD6AgAYAAkJMCSDAwD6AgALAAEJPwm2kAAqAAAAAA==.Davidx:BAAALgAECgQJBQAAAA==.',
De='Deadgripz:BAAALgADCgMJBgAAAA==.Deadjaden:BAAALgADCgEJAQAAAA==.Deadlos:BAAALgAECgUJCAAAAA==.Deathscreams:BAAALgAECgQJBgAAAA==.Deathxreaper:BAAALgAECgQJCwAAAA==.Decessus:BAAALgAECgUJBgAAAA==.Dekig:BAACLgAFFH8FAAIHAAIJOQ3dvgCTAAAHAAIJOQ3dvgCTAAAuAAQKfyMAAgcACAkNFIteAKQBAAcACAkNFIteAKQBAAAA.Demine:BAABLgAECn86AAIDAAkJ5R13GgC1AgADAAkJ5R13GgC1AgAAAA==.Demonvibe:BAAALgAFFAEJAQAAAA==.',
Di='Dico:BAAALgAECgIJAgABLgAFFAgJIwAZAIccAA==.Dinobots:BAAALgAECgYJDAAAAA==.Dipper:BAABLgAECn8cAAIGAAkJExr4NwAXAgAGAAkJExr4NwAXAgAAAA==.Divinator:BAAALgAECgYJDQAAAA==.',
Do='Donbarriga:BAAALgAECgYJCAAAAA==.Dosmojitos:BAAALgADCgcJBwAAAA==.Doublejumps:BAAALgAECgYJCwAAAA==.Doublelung:BAAALgAECgYJEgAAAA==.',
Dr='Draagone:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Drdiddles:BAAALgAECgMJAwAAAA==.',
Du='Duney:BAACLgAFFH8GAAMaAAQJMRCuIADZAAAaAAMJVhSuIADZAAAbAAMJnAr5MwDNAAAuAAQKf0wAAxoACQnYHm0EAMcCABoACQlIHm0EAMcCABsABglvG60sAJgBAAAA.Dußad:BAAALgAECgMJBwAAAA==.',
['Dé']='Déäth:BAAALgADCgQJBAAAAA==.',
Ec='Eckoe:BAABLgAECn8gAAIOAAcJKwbfcQDVAAAOAAcJKwbfcQDVAAAAAA==.',
Ee='Eekeros:BAAALgADCgUJBQAAAA==.Eeveeko:BAACLgAFFH8OAAIcAAQJ7g/HCAAhAQAcAAQJ7g/HCAAhAQAuAAQKfzkAAhwACQmvHmwGAGYCABwACQmvHmwGAGYCAAAA.',
Ej='Ejavuday:BAABLgAECn8wAAIDAAkJPSL3FQDPAgADAAkJPSL3FQDPAgAAAA==.',
El='Elvudu:BAAALgAECgQJBwAAAA==.',
Em='Emberstrife:BAAALgAECgEJAgAAAA==.',
En='Enerchi:BAAALgAFFAEJAQAAAA==.',
Er='Erazath:BAAALgAECgQJCAAAAA==.Erianar:BAAALgAECgIJAgAAAA==.Ericdruid:BAABLgAECn8aAAMSAAcJSiD3EgB+AgASAAcJSiD3EgB+AgAOAAEJ6QqZ1gAqAAAAAA==.Ericlock:BAAALgADCgMJAwAAAA==.',
Es='Essia:BAAALgAECgEJAQAAAA==.',
Ev='Eveko:BAAALgADCgIJAQAAAA==.Evera:BAABLgAECn8uAAIHAAkJ6gR5nAAoAQAHAAkJ6gR5nAAoAQAAAA==.Everlst:BAAALgADCgEJAQAAAA==.Evokinpants:BAAALgAECgcJDwAAAA==.Evos:BAAALgAECgQJBgAAAA==.',
Ex='Excels:BAACLgAFFH8NAAIOAAMJoBlkMgDgAAAOAAMJoBlkMgDgAAAuAAQKfyYAAg4ACQmpIqYDAH8DAA4ACQmpIqYDAH8DAAAA.Explicatory:BAAALgAECgYJBwABLgAFFAMJDQAOAKAZAA==.',
Ey='Eyllion:BAAALgAECgUJCAAAAA==.',
Fa='Falorin:BAAALgADCgMJAwAAAA==.Fastoris:BAAALgADCgEJAQAAAA==.Fauci:BAACLgAFFH8JAAIHAAUJOw1wpgC9AAAHAAUJOw1wpgC9AAAuAAQKfx4AAgcACAk4IfUdAIwCAAcACAk4IfUdAIwCAAAA.',
Fb='Fblthelost:BAAALgAECgMJAwAAAA==.',
Fe='Feihao:BAAALgADCggJFQAAAA==.Feile:BAABLgAECn82AAQIAAkJxhfwMAAPAgAIAAkJxhfwMAAPAgAdAAIJfgu/VwBnAAAeAAEJAAD1LwA+AAAAAA==.Fenty:BAAALgAECgUJBQABLgAECggJNgAUACEZAA==.Feshh:BAAALgADCgEJAQAAAA==.',
Fi='Fifezilla:BAAALgAECgIJAgAAAA==.Firble:BAAALgADCgYJBgAAAA==.Fireg:BAEALgADCgEJAQABLgAFFAQJBQADADULAA==.Fistbeaver:BAAALgADCgUJBQAAAA==.',
Fl='Flinzza:BAAALgAECgYJCwAAAA==.',
Fo='Foolezz:BAAALgAECgMJBAAAAA==.',
Fr='Fredthedh:BAABLgAECn8cAAIUAAkJZSFUFADeAgAUAAkJZSFUFADeAgAAAA==.Fromtheback:BAAALgAECgYJDgABLgAECgkJGwAHAPAaAA==.',
Fu='Furble:BAAALgADCgYJBgAAAA==.',
Ga='Gaashw:BAAALgAECgIJBgAAAA==.Gadziila:BAAALgADCgEJAQAAAA==.Galcyon:BAAALgADCgEJAQAAAA==.Galiant:BAABLgAECn8mAAIHAAkJ/SNIFQC/AgAHAAkJ/SNIFQC/AgAAAA==.Gashdk:BAAALgAECgEJAQABLgAECgIJBgAEAAAAAA==.Gator:BAAALgAECgEJAQAAAA==.Gaulish:BAAALgADCgkJCQAAAA==.',
Ge='Geraldo:BAAALgAECgIJAgAAAA==.Gethalyn:BAABLgAECn8WAAIGAAcJAREDkABGAQAGAAcJAREDkABGAQAAAA==.Gexz:BAAALgADCgYJDAAAAA==.',
Gh='Ghee:BAAALgAECgEJAgAAAA==.',
Gi='Gianthippo:BAAALgAECgcJEgAAAA==.',
Gl='Glaivedaddy:BAAALgAECgEJAQAAAA==.Glenlives:BAAALgADCgkJCgABLgAECggJLAAMABgOAA==.',
Go='Gore:BAAALgAECgUJBQAAAA==.Gottverdammt:BAAALgAECgEJAQABLgAECgkJEAAEAAAAAA==.',
Gr='Graveknight:BAAALgAECgMJAwAAAA==.Graveshot:BAAALgADCgQJBAAAAA==.Greennrry:BAAALgAFFAEJAQABLgAFFAMJCAAfANsYAA==.Greennrryy:BAAALgAFFAEJAgABLgAFFAMJCAAfANsYAA==.Greenryy:BAAALgAECgIJAwABLgAFFAMJCAAfANsYAA==.Greyskin:BAAALgADCgEJAQAAAA==.Grizzabella:BAABLgAECn85AAIOAAkJ9Rs4DwDSAgAOAAkJ9Rs4DwDSAgAAAA==.Grreenry:BAABLgAFFH8IAAIfAAMJ2xh+CgD4AAAfAAMJ2xh+CgD4AAABLgAFFAMJCAAfANsYAA==.Grriz:BAAALgADCgEJAQAAAA==.Grtmustachio:BAAALgAECgkJEAAAAA==.Grundle:BAAALgAECgMJAwAAAA==.',
Gu='Gularak:BAAALgAECgQJBgAAAA==.Gunghø:BAAALgADCggJDwAAAA==.',
Gy='Gyutaro:BAAALgADCgEJAQAAAA==.',
Ha='Haelellionys:BAAALgADCgQJBAAAAA==.Hanamae:BAAALgADCgEJAQAAAA==.Hangnail:BAAALgAECgIJBAAAAA==.Hanswoloqued:BAACLgAFFH8KAAIIAAMJ0QbefAC7AAAIAAMJ0QbefAC7AAAuAAQKfxsAAwgACQmoC55nAGkBAAgACQmoC55nAGkBAB4AAgmmAQ0qAEsAAAAA.Harmfuljoker:BAAALgADCgQJBAAAAA==.Haxzen:BAAALgADCgMJBAAAAA==.',
He='Healufast:BAABLgAECn87AAINAAkJmxziCADQAgANAAkJmxziCADQAgAAAA==.Hellsong:BAAALgAECgMJAwABLgAECgYJBgAEAAAAAA==.Helstrom:BAAALgADCgYJBQAAAA==.Hendo:BAAALgADCgYJBgAAAA==.Hendoh:BAAALgAECgIJAgAAAA==.Heysisters:BAAALgAECgIJAwAAAA==.',
Hi='Hispeas:BAAALgADCgQJBwAAAA==.Hitchkawk:BAAALgAECgEJAQAAAA==.Hitchlock:BAAALgAECgEJAwAAAA==.',
Ho='Holysabeline:BAACLgAFFH8GAAIFAAIJiBIPNwB9AAAFAAIJiBIPNwB9AAAuAAQKf0gAAgUACQlpGqcSAHICAAUACQlpGqcSAHICAAAA.Honestleon:BAAALgADCgMJAwABLgAECgcJFgAGAHgTAA==.Hordechief:BAAALgAFFAIJAgAAAA==.',
Hu='Huchar:BAABLgAECn9EAAMZAAkJ3SIAAwAEAwAZAAkJ3SIAAwAEAwAbAAEJmgxungAxAAAAAA==.Huevos:BAAALgAECgIJAwAAAA==.Huntersteve:BAABLgAECn8hAAMgAAgJQCOoCAAIAwAgAAgJQCOoCAAIAwALAAYJ7CAfIwANAgAAAA==.',
Hy='Hydraxix:BAAALgAECgYJCwAAAA==.',
['Hô']='Hônk:BAAALgADCgEJAQABLgAECggJLAAMABgOAA==.',
Ia='Iamanopcow:BAAALgADCgQJBAAAAA==.Iamspeed:BAAALgADCgQJBAAAAA==.',
Ic='Iceblade:BAABLgAECn8oAAIFAAkJxxf2HwAaAgAFAAkJxxf2HwAaAgAAAA==.',
If='If:BAAALgAECgMJAwAAAA==.',
Ih='Ihideuseek:BAAALgAECgYJCgABLgAECgkJMAADAD0iAA==.',
Ii='Iityouup:BAAALgADCgYJCAAAAA==.',
Il='Illidaniella:BAABLgAECn8ZAAIUAAgJmQjIewAcAQAUAAgJmQjIewAcAQAAAA==.Illsmurfuup:BAABLgAECn8ZAAIYAAkJ9SZoAACnAwAYAAkJ9SZoAACnAwAAAA==.',
In='Infection:BAAALgADCgYJCAAAAA==.Inverse:BAAALgADCgYJBgAAAA==.',
Ir='Ironßest:BAABLgAECn8XAAIgAAcJgA6kawBeAQAgAAcJgA6kawBeAQAAAA==.Irôh:BAAALgAECgEJAQABLgAECgUJFgAhAKAfAA==.',
Is='Ishmael:BAAALgADCgEJAQAAAA==.',
Iv='Ivannas:BAAALgAECgMJBgAAAA==.',
Ja='Jaabroni:BAAALgADCgIJAgAAAA==.Jackymoon:BAABLgAECn8aAAIGAAgJXCMvHACRAgAGAAgJXCMvHACRAgAAAA==.Jaxxion:BAAALgADCgMJBQAAAA==.',
Jd='Jdawg:BAABLgAECn8/AAIcAAkJQiXkAABDAwAcAAkJQiXkAABDAwAAAA==.',
Je='Jer:BAAALgADCgYJBgAAAA==.Jessaiyan:BAABLgAECn8sAAIUAAkJKyJWCAAEAwAUAAkJKyJWCAAEAwAAAA==.',
Ji='Jindo:BAAALgADCgcJBwAAAA==.Jiuni:BAAALgADCgUJBQAAAA==.',
Jj='Jjcjr:BAAALgAFFAIJAgABLgAFFAYJGwAiAJMhAA==.',
Ju='Julaidan:BAAALgAECgQJBAAAAA==.Julaudette:BAABLgAECn8eAAIeAAYJ3whsFwD1AAAeAAYJ3whsFwD1AAAAAA==.Juliania:BAAALgAECgIJAgAAAA==.Julzaria:BAABLgAECn8lAAIgAAgJZhI1QwDMAQAgAAgJZhI1QwDMAQAAAA==.Julzoblin:BAAALgAECgYJEAAAAA==.Jurny:BAABLgAECn8cAAMdAAgJiwzCFQDrAAAeAAcJzArPEgAqAQAdAAcJuQrCFQDrAAAAAA==.Jusdeen:BAABLgAECn8YAAMPAAkJtiLtBQCXAgAPAAgJGSLtBQCXAgAOAAMJvA9plQB9AAAAAA==.',
Ka='Kadookieii:BAAALgAFFAEJAQAAAA==.Kahlandra:BAABLgAECn83AAMjAAkJChtVAgArAgAjAAkJChtVAgArAgADAAgJ9QyQiQBeAQAAAA==.Kairoz:BAAALgAECgYJEgABLgAFFAEJAQAEAAAAAA==.Kaizer:BAACLgAFFH8QAAIMAAUJ9BBFJAD+AAAMAAUJ9BBFJAD+AAAuAAQKfyYAAgwACAmrHN4YAE0CAAwACAmrHN4YAE0CAAAA.Kalo:BAAALgAECgMJAwAAAA==.Kanrethad:BAAALgAECgQJBAABLgAECggJKgAKAAgbAA==.Karina:BAABLgAECn9HAAMUAAkJoCE1DgDKAgAUAAkJbCA1DgDKAgAVAAkJzxbBBgASAgAAAA==.Kastravia:BAAALgAFFAIJBAABLgAFFAQJFQARAG4GAA==.Kawolski:BAABLgAFFH8FAAIOAAMJ8AaFRgCWAAAOAAMJ8AaFRgCWAAABLgAFFAQJFQARAG4GAA==.',
Ke='Kelitarra:BAAALgADCgQJCAAAAA==.Kellibar:BAAALgAECgcJBwAAAA==.Kevin:BAAALgAECgcJCgAAAA==.Keyzer:BAAALgAECgEJAQAAAA==.',
Kh='Khanjuror:BAABLgAECn8tAAIdAAgJ1xQaCgCUAQAdAAgJ1xQaCgCUAQAAAA==.Kholonoe:BAABLgAECn8cAAIkAAkJmRRSHgDKAQAkAAkJmRRSHgDKAQAAAA==.Khornedog:BAABLgAECn8mAAIIAAcJihZTWgCKAQAIAAcJihZTWgCKAQAAAA==.Khrama:BAABLgAECn8WAAIKAAkJiSFTBQDNAgAKAAkJiSFTBQDNAgAAAA==.',
Ki='Kietemourt:BAAALgADCgUJBQAAAA==.Kiimachamara:BAAALgADCgIJAwAAAA==.Killik:BAAALgAECgQJBAAAAA==.Kinz:BAAALgAECgMJAwABLgABCgkJEgAEAAAAAA==.Kippili:BAAALgADCgQJBAABLgAECgYJCgAEAAAAAA==.Kiritokun:BAAALgADCgYJBAAAAA==.',
Kl='Klapz:BAAALgADCgcJDQABLgAECggJEAAEAAAAAA==.Kleenonean:BAACLgAFFH8QAAIkAAUJ6yRDCgCgAQAkAAUJ6yRDCgCgAQAuAAQKf1sAAyQACQkBJt4AAHsDACQACQkBJt4AAHsDAA0AAgnGBlV0AFcAAAAA.',
Ko='Kobe:BAAALgAFFAEJAgAAAA==.',
Kp='Kpyassan:BAAALgAECgYJBQAAAA==.',
Kr='Kravenn:BAAALgAECgMJAwAAAA==.Kreuzritter:BAABLgAECn8zAAIYAAkJORDDCABcAgAYAAkJORDDCABcAgAAAA==.Kritterbug:BAAALgAECggJCAAAAA==.',
Ku='Kungcarefu:BAABLgAECn8bAAICAAYJQxKGQgDoAAACAAYJQxKGQgDoAAAAAA==.Kungfushnaz:BAAALgAECgEJAQAAAA==.Kurzaan:BAAALgAECgcJAgAAAA==.Kurzak:BAAALgAECgQJBwAAAA==.',
Ky='Kyle:BAAALgAECgEJAQABLgAFFAIJAgAEAAAAAA==.',
La='Laciel:BAAALgAECgMJBAABLgAECgkJIAAHAH0eAA==.Lacio:BAABLgAECn9HAAIkAAkJLwp6KQB9AQAkAAkJLwp6KQB9AQAAAA==.Larune:BAAALgADCgQJBwAAAA==.Lasten:BAAALgAECgEJAgAAAA==.Lavendàh:BAABLgAECn8oAAIFAAkJuCDsBAA9AwAFAAkJuCDsBAA9AwAAAA==.',
Le='Lemonite:BAACLgAFFH8NAAIOAAQJRw+sLgDxAAAOAAQJRw+sLgDxAAAuAAQKfxYAAg4ACQlwG+QUAI4CAA4ACQlwG+QUAI4CAAAA.Lennykoggins:BAABLgAECn8YAAIgAAgJLBdxRwC/AQAgAAgJLBdxRwC/AQAAAA==.Lexxix:BAAALgAECgUJBQAAAA==.Leyru:BAABLgAECn8sAAIFAAgJISRqBQAxAwAFAAgJISRqBQAxAwAAAA==.',
Li='Liberos:BAABLgAECn8YAAIJAAkJOBMIKwAAAgAJAAkJOBMIKwAAAgAAAA==.Lifenight:BAABLgAECn8kAAMlAAkJ6BzWBABkAgAlAAkJ6BzWBABkAgAHAAEJvwAGPwEJAAAAAA==.Lilnim:BAAALgAECgYJBgAAAA==.Lithvia:BAAALgAECgYJDQAAAA==.',
Ln='Lninedkhack:BAABLgAECn8mAAMHAAkJQRkkMQAyAgAHAAkJQRkkMQAyAgAKAAgJMQfbLgDcAAAAAA==.',
Lo='Lockdor:BAAALgAECgQJBAAAAA==.Logaar:BAABLgAECn80AAMFAAkJSxYrFQBZAgAFAAkJSxYrFQBZAgAGAAEJ7gFptAEcAAAAAA==.Loretharan:BAAALgAECgEJAQAAAA==.Louvuitton:BAAALgADCgcJDgAAAA==.',
Lu='Lunartsy:BAAALgADCggJDgAAAA==.Lustiel:BAAALgAECgYJDAAAAA==.Luticris:BAAALgAECgMJBAAAAA==.',
Ly='Lyoric:BAAALgAECgEJAQAAAA==.',
Ma='Madmax:BAAALgADCggJCAAAAA==.Maegot:BAAALgADCgYJBgAAAA==.Magicpants:BAAALgAECgcJCgAAAA==.Magnetto:BAAALgADCggJDQAAAA==.Maiden:BAAALgADCgUJCAABLgAECggJKgAKAAgbAA==.Malexannius:BAAALgADCgUJCQAAAA==.Mannirot:BAAALgAECgEJAQAAAA==.Mariangel:BAAALgAECgUJCAAAAA==.Marrygold:BAAALgAECgEJAgABLgAECgkJIAAHAHYfAA==.Mateus:BAAALgAECgkJDQAAAA==.Maxdeath:BAABLgAECn8lAAIHAAgJ9iO/DQAtAwAHAAgJ9iO/DQAtAwAAAA==.Mazre:BAAALgAECgQJBwAAAA==.',
Me='Megtallica:BAAALgAECgUJBwAAAA==.Mensrea:BAABLgAECn8fAAMJAAcJrBKyVwBHAQAJAAYJFhOyVwBHAQAMAAUJagxVagCaAAAAAA==.Merlinn:BAAALgADCgMJBgAAAA==.Merrycold:BAABLgAECn8gAAMHAAkJdh9FPABGAgAHAAcJpSFFPABGAgAKAAUJ3RPFNQC1AAAAAA==.Merrygold:BAAALgADCgMJAwABLgAECgkJIAAHAHYfAA==.Merrygored:BAAALgAECgIJAgABLgAECgkJIAAHAHYfAA==.Mess:BAABLgAECn8tAAQZAAcJjh50DgD1AQAZAAcJjh50DgD1AQAbAAIJ3gfTlABsAAAaAAMJPQgXRwApAAABLgAECggJKgAKAAgbAA==.Methodical:BAAALgADCgUJBQAAAA==.Metophis:BAAALgAECgYJCgAAAA==.',
Mf='Mfboomstick:BAABLgAECn8/AAMYAAkJNCb3AABgAwAYAAkJNCb3AABgAwALAAEJlSXoKgBiAAAAAA==.',
Mi='Mikklelee:BAAALgADCgIJAgAAAA==.Minerva:BAAALgADCgMJAwAAAA==.Missdebby:BAAALgADCgYJCwAAAA==.Mistweaver:BAABLgAECn8dAAIRAAkJgiBSBQBJAwARAAkJgiBSBQBJAwAAAA==.Mistweaving:BAAALgAECgcJAwAAAA==.Mizirath:BAAALgAECgQJBAABLgAECggJMgAPAKofAA==.Miztakswrmde:BAAALgADCgUJBgAAAA==.',
Mo='Moghorva:BAABLgAECn8eAAImAAkJzBjFCABZAgAmAAkJzBjFCABZAgAAAA==.Mojoe:BAAALgAECgQJDAAAAA==.Mommyswaggin:BAABLgAECn8VAAINAAkJChRuHQDMAQANAAkJChRuHQDMAQAAAA==.Moonra:BAAALgAECgEJAQAAAA==.Moopocalypse:BAAALgADCgcJDAABLgAFFAQJCwANAP4eAA==.Moopsta:BAAALgADCggJDgABLgAFFAQJCwANAP4eAA==.Moopster:BAACLgAFFH8LAAINAAQJ/h4YDQBiAQANAAQJ/h4YDQBiAQAuAAQKfzYAAw0ACQmdJXgBAKADAA0ACQmdJXgBAKADAAEABgnfGdEfAMABAAAA.Mordekaiserz:BAAALgAECgUJCwAAAA==.Morrgoth:BAAALgADCgEJAQAAAA==.',
Mu='Mucouslurp:BAAALgADCgEJAQAAAA==.',
Na='Nalahni:BAACLgAFFH8OAAIiAAQJRQ2zMQDxAAAiAAQJRQ2zMQDxAAAuAAQKfyIAAiIACQmHGCoVACkCACIACQmHGCoVACkCAAAA.Nanashi:BAAALgAECgMJAwAAAA==.Nastage:BAAALgADCgMJAQAAAA==.Nastus:BAAALgAECgMJAwAAAA==.Nayela:BAAALgAECgYJEAAAAA==.Nazgru:BAAALgAECgEJAQAAAA==.',
Ne='Neptuneakis:BAABLgAECn8mAAISAAkJFRerEgA2AgASAAkJFRerEgA2AgAAAA==.Neptuno:BAAALgADCgEJAQABLgAECgkJJgASABUXAA==.Nerfblaster:BAAALgADCgEJAQAAAA==.Newcarsmell:BAAALgAECgkJEwAAAA==.',
Ni='Nicktee:BAAALgAECgUJCQAAAA==.Nightmares:BAAALgAECgcJCgAAAA==.Nightrvn:BAAALgAECgQJBAAAAA==.Nimrose:BAABLgAECn8WAAIDAAkJogPlmwA9AQADAAkJogPlmwA9AQAAAA==.Niquid:BAABLgAECn8nAAIOAAgJtxXILgDgAQAOAAgJtxXILgDgAQAAAA==.',
No='Nolmac:BAABLgAECn8nAAIJAAgJVSNgDADsAgAJAAgJVSNgDADsAgAAAA==.Notahealer:BAAALgAFFAIJAwAAAA==.Noxloxes:BAAALgADCgcJDAAAAA==.',
Np='Npv:BAABLgAFFH8HAAIHAAIJgQ0B0QCIAAAHAAIJgQ0B0QCIAAAAAA==.',
Ny='Nyssavia:BAAALgADCgcJDgAAAA==.',
Oa='Oakshre:BAABLgAECn80AAIQAAkJnSCmBgDYAgAQAAkJnSCmBgDYAgAAAA==.',
Ob='Obliteration:BAAALgAECgYJBwABLgAFFAEJAQAEAAAAAA==.',
Ol='Olivertwist:BAAALgAECgQJDgABLgAFFAEJAQAEAAAAAA==.',
Om='Omnimpotent:BAAALgAECgEJAQABLgAECgIJBQAEAAAAAA==.',
On='Ontwarr:BAAALgADCgkJEAAAAA==.Ontwou:BAABLgAECn8WAAIgAAgJ4xj0NwDzAQAgAAgJ4xj0NwDzAQAAAA==.',
Op='Ophi:BAAALgAECgYJEQAAAA==.',
Os='Oshaku:BAAALgAECgcJDAAAAQ==.',
Ou='Ouchpotato:BAAALgAFFAEJAQABLgAFFAQJDgAXAIkWAA==.',
Pa='Paarthurnax:BAAALgAFFAMJAwAAAA==.Palathal:BAAALgAECgUJBgABLgAECggJGQADAPoTAA==.Pallynim:BAAALgADCgQJBwAAAA==.Palms:BAACLgAFFH8NAAIQAAQJ1htoDQBKAQAQAAQJ1htoDQBKAQAuAAQKfxgAAhAACQlDIpgHAAIDABAACQlDIpgHAAIDAAAA.Pancakezebra:BAABLgAECn8yAAIYAAkJ6RqKDwAxAgAYAAkJ6RqKDwAxAgAAAA==.Pantsftw:BAABLgAECn8fAAMNAAgJQwz6MQA0AQANAAgJ1Qv6MQA0AQABAAEJQQUTdQAuAAAAAA==.Papabear:BAAALgADCgUJBQAAAA==.Parkbreezy:BAABLgAECn8bAAIPAAcJBwrvPACdAAAPAAcJBwrvPACdAAAAAA==.Passera:BAAALgAECggJDgAAAA==.Pawg:BAAALgADCgcJBgAAAA==.',
Pe='Pebbles:BAAALgAECgcJBwAAAA==.Peltier:BAABLgAECn8sAAIDAAkJdCBrIwCJAgADAAkJdCBrIwCJAgAAAA==.Pendle:BAABLgAECn8sAAMIAAgJFA6HYAB7AQAIAAgJfg2HYAB7AQAdAAYJHQvDKQAbAQAAAA==.',
Ph='Phoenix:BAABLgAECn8tAAIGAAkJbB9OGACoAgAGAAkJbB9OGACoAgAAAA==.',
Pl='Plox:BAAALgAECgYJEwAAAA==.Plurnizz:BAABLgAECn8dAAMIAAkJHQjkgQAwAQAIAAkJHQjkgQAwAQAdAAQJEwHKXwBPAAAAAA==.',
Po='Pocketchange:BAACLgAFFH8QAAIJAAQJwBh+KgAhAQAJAAQJwBh+KgAhAQAuAAQKfxUAAwwACQniGnEqAMIBAAwABgnWHHEqAMIBAAkABgm/FzJLAFYBAAAA.',
Pu='Puffadin:BAAALgADCgEJAQAAAA==.Puppymoke:BAAALgAECgMJAwAAAA==.Puptart:BAAALgAECgUJBQAAAA==.',
Ra='Raest:BAABLgAECn8pAAICAAgJyCSKBQDgAgACAAgJyCSKBQDgAgABLgAECgkJFgAKAIkhAA==.Raiker:BAAALgAECgMJBAAAAA==.Ranch:BAAALgAECgEJAQAAAA==.Razzlock:BAAALgAECgEJAQAAAA==.',
Re='Regret:BAAALgAECgkJEgAAAA==.Relovan:BAABLgAECn8vAAMaAAkJ6RAeFQCrAQAaAAkJ6RAeFQCrAQAbAAUJSwOYhgClAAAAAA==.Renothidan:BAACLgAFFH8JAAIGAAMJQx+5SgAJAQAGAAMJQx+5SgAJAQAuAAQKfyMAAgYACQnaGyI1ACECAAYACQnaGyI1ACECAAAA.Reuben:BAAALgAECgUJBQAAAA==.Revin:BAAALgADCgYJBgAAAA==.Revrynth:BAAALgAECggJEAABLgAECggJKQAZAPUiAA==.Rexorcist:BAAALgAECgcJDQAAAA==.',
Ri='Rickyboby:BAAALgAECggJDAAAAA==.Righteøus:BAAALgAECgUJDwAAAA==.Rillan:BAABLgAECn8aAAIGAAYJ8xbQkwBAAQAGAAYJ8xbQkwBAAQAAAA==.Rin:BAAALgAECgkJCQABLgAECgkJPwAIAEklAA==.Ripper:BAAALgAECgUJCQAAAA==.Rippèd:BAAALgAECgYJCgAAAA==.Rithcice:BAABLgAECn84AAMbAAkJtCa4AACDAwAbAAkJqSa4AACDAwAZAAcJ/yMnCABuAgAAAA==.Rizzdolphler:BAACLgAFFH8PAAIGAAQJqRShOgAnAQAGAAQJqRShOgAnAQAuAAQKfygAAwYACAmyHaQxAC8CAAYACAmyHaQxAC8CAAUABgktESlAADcBAAAA.',
Ro='Roadnurse:BAAALgADCgIJAgAAAA==.Rockntroll:BAAALgADCgIJAgAAAA==.Rodah:BAAALgADCgkJEAAAAA==.Roscoee:BAAALgADCgEJAQAAAA==.',
Rs='Rsk:BAAALgADCgYJCQABLgAECggJKgAKAAgbAA==.',
Ru='Ruins:BAAALgAECgEJAQAAAA==.',
['Rà']='Ràrity:BAAALgADCggJCAAAAA==.',
['Rö']='Rönburgundy:BAACLgAFFH8JAAIIAAMJIQ66cQDQAAAIAAMJIQ66cQDQAAAuAAQKfy4AAggACQmNHi8cAHUCAAgACQmNHi8cAHUCAAAA.',
Sa='Sanako:BAABLgAECn8oAAISAAkJxxFuHQDQAQASAAkJxxFuHQDQAQAAAA==.Sanastusa:BAAALgADCgYJCAAAAA==.Saneros:BAAALgAECggJCQABLgAECggJNgAUACEZAA==.Santoniche:BAAALgAECgUJBAAAAA==.Sap:BAABLgAECn8gAAMXAAcJFxdjHQCdAQAXAAcJFxdjHQCdAQAnAAQJQgtwFQDJAAABLgAECggJKgAKAAgbAA==.Sausiege:BAAALgAECgMJAwAAAA==.Saveserenade:BAAALgAECgUJBQAAAA==.',
Sc='Scarylarry:BAABLgAECn82AAIUAAgJIRmUOQDUAQAUAAgJIRmUOQDUAQAAAA==.Scyther:BAACLgAFFH8JAAMhAAMJlg2tGAC/AAAhAAMJQg2tGAC/AAAUAAIJRwOUhABkAAAuAAQKfxgAAxQACQlBD8txAE8BABQACAk9DMtxAE8BACEABglZEVFGAIgAAAAA.',
Sd='Sdh:BAAALgADCgQJBgAAAA==.',
Se='Seishinokami:BAABLgAECn8sAAIMAAgJGA7eNABYAQAMAAgJGA7eNABYAQAAAA==.Senala:BAAALgAECgEJAQAAAA==.Serenade:BAACLgAFFH8KAAIDAAQJqBEkYgAbAQADAAQJqBEkYgAbAQAuAAQKfyQAAgMACAmuHxYzAKYCAAMACAmuHxYzAKYCAAAA.Setheron:BAABLgAECn8rAAIbAAgJACK0CgCyAgAbAAgJACK0CgCyAgAAAA==.Sethron:BAAALgAECgIJAgAAAA==.Señsei:BAAALgAECggJCwAAAA==.',
Sh='Shamminit:BAAALgAECgIJAgAAAA==.Shamtul:BAAALgAECgEJAwAAAA==.Shamwow:BAAALgADCgcJDgAAAA==.Shlea:BAACLgAFFH8MAAIiAAMJBgpWQgCwAAAiAAMJBgpWQgCwAAAuAAQKfx0AAiIACQn7ENImAKIBACIACQn7ENImAKIBAAAA.Shyva:BAABLgAECn8pAAMZAAgJ9SIxBwC4AgAZAAgJ9SIxBwC4AgAbAAUJ9xcDTwACAQAAAA==.',
Si='Siinestro:BAAALgAECgQJBAAAAA==.Sinlee:BAAALgAECgcJDgABLgAECgkJOgAIAEMiAA==.',
Sl='Slayla:BAAALgAECgUJDAAAAA==.Slimboyjoe:BAAALgADCgcJDgAAAA==.Slimmjim:BAAALgADCgEJAQAAAA==.Slinkstir:BAAALgADCgQJAwAAAA==.',
Sn='Snailtrails:BAAALgAECgcJBwAAAA==.Sneak:BAAALgADCgMJAwABLgAECgYJCwAEAAAAAA==.Sneakcookies:BAAALgAECgMJBwABLgAFFAEJAQAEAAAAAA==.',
So='Soggyundies:BAAALgAECgQJBAAAAA==.Solendros:BAAALgAECgYJDwAAAA==.Sonthar:BAAALgAECgYJBgAAAA==.Soulborn:BAAALgADCgMJAwAAAA==.Soulelf:BAAALgADCgcJBwAAAA==.',
Sp='Spacehog:BAAALgAECgYJDAAAAA==.Sparticus:BAAALgAECgEJAQAAAA==.Spiro:BAAALgAECgEJAQABLgAFFAMJCQAQAHoeAA==.Splouge:BAAALgAECgYJBgAAAA==.',
St='Standarshh:BAABLgAECn9AAAIgAAkJdSIkCQAHAwAgAAkJdSIkCQAHAwAAAA==.Stemmz:BAAALgADCgEJAQAAAA==.Stronghand:BAAALgADCgYJBwAAAA==.',
Su='Subtle:BAACLgAFFH8OAAIXAAQJiRYKFwBJAQAXAAQJiRYKFwBJAQAuAAQKfycAAxcACQnwHiwNAMcCABcACQnwHiwNAMcCACgABQmpBm0YAIgAAAAA.Sugarbabi:BAABLgAECn8hAAMOAAkJDR8uIQA7AgAOAAcJ3x4uIQA7AgASAAYJRRhdJQCTAQAAAA==.Sugarrush:BAAALgADCgUJBQAAAA==.Sugarshot:BAAALgAECggJCAAAAA==.Sugarthorn:BAAALgADCgkJCQAAAA==.Sulcer:BAAALgADCgMJBAAAAA==.',
Sw='Swiftwing:BAAALgADCgEJAQAAAA==.',
Sy='Sylria:BAAALgAECgIJAgAAAA==.Sylrianah:BAABLgAECn9IAAQNAAkJ0CChBgD9AgANAAkJ0CChBgD9AgAkAAkJ4QhiKgB3AQABAAQJrgi5UQCmAAAAAA==.Sylveste:BAACLgAFFH8SAAIFAAUJLiN/DADdAQAFAAUJLiN/DADdAQAuAAQKfyMAAgUABwkUGngvAJIBAAUABwkUGngvAJIBAAAA.Sylvfelster:BAAALgAECgYJBwAAAA==.Sylánnia:BAAALgADCgcJBwAAAA==.',
Ta='Ta:BAABLgAECn8aAAIBAAcJpAinNQAxAQABAAcJpAinNQAxAQAAAA==.Talis:BAAALgAECgEJAQAAAA==.Tankhiskhan:BAABLgAECn8VAAIKAAgJQA3QKwDxAAAKAAgJQA3QKwDxAAAAAA==.Tarlis:BAABLgAECn8YAAIeAAgJ9xq8BAAqAgAeAAgJ9xq8BAAqAgAAAA==.',
Te='Tedrickeyjr:BAAALgAECgEJBgAAAA==.Terithresh:BAAALgADCgMJBAAAAA==.',
Th='Thanil:BAABLgAECn8uAAIGAAkJsBd7MgArAgAGAAkJsBd7MgArAgAAAA==.Thenet:BAAALgAECgEJAwAAAA==.',
Ti='Tie:BAAALgAECgQJBQAAAA==.Tikamancer:BAAALgADCgEJAQAAAA==.Tilvalhalla:BAABLgAECn8cAAImAAcJPAogKgAhAQAmAAcJPAogKgAhAQAAAA==.',
To='Todorokii:BAAALgAECgUJDQAAAA==.Tom:BAAALgAECgEJAgABLgAFFAIJAgAEAAAAAA==.Torrin:BAAALgADCgYJBwAAAA==.Tortricid:BAAALgAECgcJDgAAAA==.Totaldchtree:BAAALgAECgEJAQAAAA==.Totempants:BAAALgAECgYJBgAAAA==.Totinospizza:BAAALgADCgYJBgAAAA==.',
Tr='Trashkan:BAAALgADCgIJAgAAAA==.Trauck:BAAALgADCgEJAQAAAA==.Traumzi:BAAALgAECgEJAQAAAA==.Travvy:BAACLgAFFH8wAAMXAAgJgyJOAQD+AQAXAAcJ0iFOAQD+AQAnAAIJoR6iCwBtAAAuAAQKfyIAAhcACQkWJgEBAMMDABcACQkWJgEBAMMDAAAA.Treezus:BAAALgADCgYJCAAAAA==.Trevmo:BAABLgAECn82AAIZAAkJGyDVBQCrAgAZAAkJGyDVBQCrAgAAAA==.Trexin:BAAALgAECgQJBQAAAA==.',
Tu='Turaylon:BAAALgAFFAEJAQAAAA==.Turtlebox:BAAALgAECgQJBgAAAA==.',
Ty='Tym:BAAALgAFFAIJAgAAAA==.',
Ug='Ugargro:BAAALgAECgQJEAAAAA==.',
Un='Unapologetic:BAAALgAECggJDAAAAA==.Unbreakabull:BAABLgAFFH8LAAISAAQJ/yUJDAC3AQASAAQJ/yUJDAC3AQAAAA==.Unceejin:BAAALgADCggJEQAAAA==.Unholydk:BAABLgAECn8qAAMKAAgJCBu8DgATAgAKAAgJCBu8DgATAgAHAAUJsw9q2gDQAAAAAA==.',
Va='Valcuna:BAAALgAECgQJBQAAAA==.Valka:BAABLgAECn8YAAIfAAkJUgmOFwBDAQAfAAkJUgmOFwBDAQAAAA==.Vamptouch:BAAALgAECgIJAwABLgAECgYJCwAEAAAAAA==.Vanaan:BAAALgAECgIJAgABLgAECgYJBwAEAAAAAA==.Varidrus:BAAALgAECgQJBQAAAA==.Vaste:BAAALgADCgcJCQAAAA==.',
Ve='Ventrue:BAABLgAECn8jAAIDAAkJ6xXfWQDJAQADAAkJ6xXfWQDJAQAAAA==.Veyle:BAABLgAECn8/AAMXAAkJ1yTCBADjAgAXAAkJ1yTCBADjAgAnAAEJKh7AGwBJAAAAAA==.',
Vi='Vivian:BAABLgAECn8sAAIhAAkJqRkUCwBmAgAhAAkJqRkUCwBmAgABLgAFFAMJCQAQAHoeAA==.',
Vo='Voidsurge:BAABLgAECn8pAAQhAAcJTRcOJQA+AQAhAAUJMxsOJQA+AQAVAAUJGREHGADRAAAUAAUJyQ/FqQDEAAABLgAECggJKgAKAAgbAA==.',
Vy='Vyndria:BAAALgAECgQJDAAAAA==.',
Wa='Wardell:BAAALgADCgEJAgAAAA==.',
We='Weaspore:BAABLgAECn8hAAIHAAgJlR5+PgAAAgAHAAgJlR5+PgAAAgAAAA==.Weasy:BAAALgAECgkJDgAAAA==.',
Wo='Woogidaboogi:BAAALgAECgIJBQAAAA==.Woogieboogie:BAAALgAECgEJAQABLgAECgIJBQAEAAAAAA==.',
Xi='Xiamiel:BAAALgADCgYJCQAAAA==.',
Xl='Xl:BAABLgAECn9WAAMhAAgJ/RxVCwCrAgAhAAgJhxxVCwCrAgAUAAgJJxYIQgC2AQAAAA==.',
Ya='Yaitoopmfp:BAAALgAECgEJAQABLgAECgkJIAAHAHYfAA==.',
Yh='Yharnem:BAABLgAECn8XAAICAAcJ8hCPLABNAQACAAcJ8hCPLABNAQAAAA==.',
Yo='Yogurtpants:BAAALgAECgYJEgAAAA==.Yonny:BAAALgADCgEJAQAAAA==.',
Yu='Yukionna:BAAALgADCgcJCwAAAA==.',
Za='Zabara:BAABLgAECn8cAAIJAAgJgSGCDwDLAgAJAAgJgSGCDwDLAgAAAA==.Zabbystabby:BAAALgADCgkJDgAAAA==.Zakaraki:BAABLgAECn8+AAQpAAkJhCWXAABAAwApAAkJhCWXAABAAwAiAAcJNyECGAAPAgAmAAcJTAd5JgBBAQAAAA==.Zaki:BAABLgAECn8aAAIUAAkJThqYIQBBAgAUAAkJThqYIQBBAgAAAA==.Zanked:BAAALgADCgQJBAAAAA==.Zarkingu:BAAALgADCgMJAwAAAA==.',
Ze='Zealot:BAAALgAFFAEJAQAAAA==.Zeleria:BAAALgAECgUJBgAAAA==.Zeno:BAAALgAFFAIJAgAAAA==.Zephyr:BAAALgAECgQJBAAAAA==.Zerathis:BAABLgAECn86AAIIAAkJQyKCDQDbAgAIAAkJQyKCDQDbAgAAAA==.Zerathül:BAAALgAECgcJEgAAAA==.Zerötwo:BAAALgADCgkJCgAAAA==.Zestul:BAAALgADCgkJFgAAAA==.',
Zi='Zimbobayaga:BAAALgAECgMJAwAAAA==.',
Zo='Zodivine:BAAALgADCgMJAwAAAA==.Zohar:BAAALgADCgEJAgAAAA==.Zooty:BAAALgADCgUJAwAAAA==.Zoshow:BAAALgAECgYJBwAAAA==.',
Zu='Zuggo:BAAALgADCgYJBgAAAA==.',
Zy='Zyrig:BAAALgADCgUJBgAAAA==.',
['Zõ']='Zõshow:BAABLgAECn8XAAMIAAcJmxUmbABeAQAIAAcJeBUmbABeAQAdAAEJEh0zYABOAAAAAA==.',
['Ça']='Çaptainçhaos:BAAALgAECgYJCgAAAA==.',
['Ða']='Ðaredevil:BAACLgAFFH8JAAIQAAMJeh44FQAPAQAQAAMJeh44FQAPAQAuAAQKfy4AAhAACQnmH6UGANgCABAACQnmH6UGANgCAAAA.',
['Ðy']='Ðynamo:BAAALgADCgMJAwAAAA==.',
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
