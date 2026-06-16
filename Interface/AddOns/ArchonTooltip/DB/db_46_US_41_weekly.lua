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

local lookup = {'Priest-Discipline','Monk-Brewmaster','Mage-Frost','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Warlock-Demonology','Shaman-Restoration','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Shaman-Elemental','Priest-Holy','Druid-Restoration','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Fire','Rogue-Subtlety','Hunter-Survival','Warrior-Protection','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Hunter-BeastMastery','DemonHunter-Havoc','Evoker-Devastation','Mage-Arcane','Priest-Shadow','DeathKnight-Frost','Evoker-Preservation','Evoker-Augmentation','Rogue-Assassination','Rogue-Outlaw',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aahzbear:BAAALgAFFAEJAQAAAA==.',
Ab='Abreale:BAAALgADCgMJAwAAAA==.Abruum:BAAALgADCgcJBwAAAA==.',
Ae='Aeero:BAABLgAECn8UAAIBAAYJNhfEHwCWAQABAAYJNhfEHwCWAQAAAA==.Aerendyl:BAAALgAECgcJCwAAAA==.',
Ai='Aiden:BAACLgAFFH8HAAICAAMJbRAEOgC6AAACAAMJbRAEOgC6AAAuAAQKfxQAAgIABgkfHF8qALcBAAIABgkfHF8qALcBAAAA.',
Al='Algros:BAAALgADCgEJAQAAAA==.Alternative:BAAALgAECgEJAgAAAA==.Alyiriia:BAAALgAECgkJCQAAAA==.',
Am='Amathal:BAABLgAECn8ZAAIDAAgJ+hP6iQBgAQADAAgJ+hP6iQBgAQAAAA==.Amazon:BAAALgAECgIJAwAAAA==.Amilea:BAAALgAFFAEJAQABLgABCgkJEgAEAAAAAA==.',
An='Anastasia:BAAALgADCggJCAAAAA==.Angelsevoker:BAAALgAECggJCAAAAA==.Angermoonria:BAAALgADCgcJBwAAAA==.Ankheloios:BAAALgAECgQJBAAAAA==.Antihiiro:BAAALgAECgMJAwAAAA==.Antipro:BAAALgAFFAEJAQAAAA==.Anubbus:BAAALgAFFAMJBAAAAA==.Anzulok:BAAALgADCgYJAQAAAA==.',
Ar='Arbalest:BAAALgADCgcJBgAAAA==.Aredhela:BAABLgAECn8cAAMFAAgJEhaUHgAMAgAFAAgJEhaUHgAMAgAGAAQJDxcJwQAEAQAAAA==.Arinth:BAAALgADCggJEQAAAA==.Arkadios:BAAALgAECgIJAgAAAA==.Armpit:BAAALgAECgMJAwAAAA==.',
As='Ascanius:BAAALgAECgEJAQABLgAECgQJBAAEAAAAAA==.Ashiiro:BAAALgAECgcJEAAAAA==.Ashveil:BAAALgAECgUJBQABLgAECgkJJgAHAEEZAA==.Asia:BAABLgAECn8/AAIIAAkJSSWABQA3AwAIAAkJSSWABQA3AwAAAA==.Asmodeius:BAAALgAFFAEJAgAAAA==.Astroprof:BAAALgAECgEJAQABLgAECgYJFAAJAFsaAA==.',
At='Athrea:BAABLgAECn8gAAMHAAkJfR7IFADJAgAHAAkJ3B3IFADJAgAKAAUJUBs1JQAnAQAAAA==.',
Au='Auntjemima:BAAALgAECgEJAgAAAA==.Aureleus:BAAALgADCgEJAQAAAA==.',
Aw='Away:BAAALgADCgIJAgAAAA==.',
Az='Azaii:BAAALgADCggJCgAAAA==.Azlear:BAAALgAECgkJBgAAAA==.Azrael:BAAALgAECgkJBwAAAA==.',
Ba='Babilouchoux:BAAALgAECgMJBQAAAA==.Ballz:BAAALgADCgYJBgAAAA==.Bano:BAAALgAECgMJAwAAAA==.Barnre:BAAALgAECgYJCQABLgAECgYJDAAEAAAAAA==.Bash:BAABLgAECn8UAAILAAcJShEvIgA4AQALAAcJShEvIgA4AQABLgAECggJKgAKAAgbAA==.Baythos:BAAALgAFFAEJAgAAAA==.',
Bb='Bb:BAAALgAECgIJAQAAAA==.',
Bd='Bdssm:BAAALgAFFAIJAgAAAA==.',
Be='Beefstick:BAAALgAECgUJBwAAAA==.Berzercarl:BAAALgAECgEJAQAAAA==.Beserkfury:BAABLgAECn8jAAIMAAkJOQ1sDgBzAQAMAAkJOQ1sDgBzAQAAAA==.',
Bh='Bhemtu:BAAALgAECgEJAQAAAA==.',
Bi='Biercan:BAAALgAECggJEAAAAA==.Bigcarl:BAAALgADCgMJAwAAAA==.Binke:BAABLgAECn8hAAINAAkJrgwfMQB2AQANAAkJrgwfMQB2AQAAAA==.Bittywhite:BAAALgAECgUJBwAAAA==.Bittywyvern:BAAALgADCgUJCwABLgAECgUJBwAEAAAAAA==.',
Bk='Bkarakh:BAAALgADCgYJEwAAAA==.',
Bl='Blayze:BAABLgAECn8eAAIOAAkJ5hNkGQD8AQAOAAkJ5hNkGQD8AQAAAA==.Blessidbee:BAAALgAECgEJAQAAAA==.Blightmarx:BAAALgADCgUJCQAAAA==.Blitzwow:BAAALgADCgYJBQAAAA==.Bluemoonflay:BAAALgAECgkJEwAAAA==.Blúnt:BAAALgADCgQJBAAAAA==.',
Bo='Bobheals:BAABLgAECn8pAAMPAAYJvhVdRgB0AQAPAAUJuhldRgB0AQALAAEJAADzkAAAAAAAAA==.Boibye:BAAALgAECgYJDgAAAA==.Bolblock:BAAALgAECgkJDwAAAA==.Bonewolf:BAAALgADCgYJCwAAAA==.Boostedww:BAAALgAECgMJCAAAAA==.Boostie:BAAALgAECgEJAgAAAA==.',
Br='Brambleclaw:BAABLgAECn8/AAIKAAkJRSOhBADmAgAKAAkJRSOhBADmAgAAAA==.Brayker:BAACLgAFFH8GAAIGAAIJLB8KfwCuAAAGAAIJLB8KfwCuAAAuAAQKf0cAAgYACQmjJdYFAEMDAAYACQmjJdYFAEMDAAAA.Breadoneal:BAABLgAECn8pAAMFAAkJ4hmiHgALAgAFAAgJ9hiiHgALAgAGAAEJ7QWntwEkAAAAAA==.Breeze:BAAALgAECgYJBgAAAA==.Brewed:BAABLgAECn8xAAMQAAkJmxPmGwDMAQAQAAkJmxPmGwDMAQARAAEJLwG+2QALAAAAAA==.Brisketbane:BAAALgAECgcJEAAAAA==.Brokenmask:BAACLgAFFH8PAAIPAAUJ0RXCHQBjAQAPAAUJ0RXCHQBjAQAuAAQKfxUAAw8ACAkOIEobAGECAA8ACAkOIEobAGECABIAAgkLEZWLADIAAAAA.Broxxar:BAAALgAECgIJAgAAAA==.Bruxxe:BAAALgAECgcJAQAAAA==.Brüenor:BAAALgAECgIJAgAAAA==.',
Bu='Burntroot:BAABLgAECn8nAAINAAgJSgfyTAD9AAANAAgJSgfyTAD9AAAAAA==.',
Ca='Caedwyn:BAABLgAECn8yAAILAAgJqh/eBwBvAgALAAgJqh/eBwBvAgAAAA==.Caitrakk:BAABLgAECn8UAAMJAAYJWxqgMgC7AQAJAAYJWxqgMgC7AQANAAUJYhC9TAAVAQAAAA==.Calignus:BAABLgAECn8dAAMGAAgJyRH7qwAiAQAGAAgJyRH7qwAiAQATAAUJVQ8jJwDQAAAAAA==.Captjack:BAABLgAECn8dAAIUAAkJrAuVZwBTAQAUAAkJrAuVZwBTAQAAAA==.Cartilage:BAABLgAECn8lAAIHAAkJXRTiQgD3AQAHAAkJXRTiQgD3AQAAAA==.Catalei:BAAALgAECgYJDwAAAA==.Caution:BAAALgADCgYJCwAAAA==.',
Ce='Cela:BAAALgAECgEJAQAAAA==.Celira:BAAALgAECgEJAQAAAA==.Celys:BAAALgAECgIJAgAAAA==.',
Ch='Chickenman:BAAALgAECgEJAQAAAA==.Chillidan:BAAALgAECgQJBwABLgAFFAEJAQAEAAAAAA==.Chiselia:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Choconilla:BAAALgAECgcJEwAAAA==.Chonkmonk:BAAALgADCgQJBAAAAA==.Choppa:BAAALgADCggJCgAAAA==.Chorizo:BAAALgAECgEJAQABLgAECgkJHQARAIIgAA==.Chupacabrass:BAAALgADCgYJBgAAAA==.Chëbbles:BAAALgADCgMJAwABLgAECgkJJgASABUXAA==.',
Ci='Cinnomun:BAAALgADCgEJAQAAAA==.',
Co='Combustinme:BAAALgAECgQJBAABLgAECggJNgAUACEZAA==.Consuming:BAABLgAECn8tAAIPAAkJpRMoMADfAQAPAAkJpRMoMADfAQAAAA==.Coorsbanquet:BAABLgAECn8ZAAMVAAgJUBnECADiAQAVAAgJUBnECADiAQAUAAIJuAlaFQEvAAAAAA==.Coorsbite:BAAALgADCgcJCAAAAA==.Corgh:BAABLgAECn8kAAIWAAYJtw4XBgBIAQAWAAYJtw4XBgBIAQAAAA==.Corrahthecow:BAAALgADCgEJAQAAAA==.Cowardice:BAAALgADCgYJCwAAAA==.',
Cr='Craccjar:BAAALgAECgUJCwAAAA==.Crackjar:BAAALgADCgcJDAAAAA==.Crash:BAECLgAFFH8QAAIUAAYJMBgILQBpAQAUAAYJMBgILQBpAQAuAAQKfzgAAxQACAn2JGgNANgCABQACAn2JGgNANgCABUAAQkwGc0vAEAAAAAA.Croarik:BAAALgAECgEJAQAAAA==.Crushix:BAABLgAECn81AAIFAAkJKhhHHwAfAgAFAAkJKhhHHwAfAgAAAA==.',
Cs='Csyasha:BAAALgAECgYJCQAAAA==.',
Cy='Cybear:BAAALgAECgYJCAAAAA==.Cykun:BAABLgAECn8uAAIXAAkJcSChCACaAgAXAAkJcSChCACaAgAAAA==.',
['Cã']='Cãs:BAAALgADCgkJCgABLgAECgkJGgAPALQNAA==.',
Da='Darch:BAABLgAECn8/AAMYAAkJMCTgAwD0AgAYAAkJMCTgAwD0AgAMAAEJPwm2kAAqAAAAAA==.Davidx:BAAALgAECgUJBwAAAA==.',
De='Deadgripz:BAAALgADCgMJBgAAAA==.Deadjaden:BAAALgADCgEJAQAAAA==.Deadlos:BAAALgAECgUJCAAAAA==.Deathscreams:BAAALgAECgQJBgAAAA==.Deathxreaper:BAAALgAECgQJCwAAAA==.Decessus:BAAALgAECgUJBgAAAA==.Dekig:BAACLgAFFH8IAAIHAAMJNxALnADXAAAHAAMJNxALnADXAAAuAAQKfyMAAgcACAkNFEFkAJwBAAcACAkNFEFkAJwBAAAA.Delbert:BAAALgADCgYJBgAAAA==.Demine:BAABLgAECn86AAIDAAkJ5R07HACwAgADAAkJ5R07HACwAgAAAA==.Demonvibe:BAAALgAFFAEJAQAAAA==.',
Di='Dico:BAAALgAECgIJAgABLgAFFAgJIwAZAIccAA==.Dinobots:BAAALgAECgYJDAAAAA==.Dipper:BAABLgAECn8cAAIGAAkJExo1OwAUAgAGAAkJExo1OwAUAgAAAA==.Divinator:BAAALgAECgYJDQAAAA==.',
Do='Donbarriga:BAAALgAECgYJCAAAAA==.Dosmojitos:BAAALgADCgcJBwAAAA==.Doublejumps:BAAALgAECgYJCwAAAA==.Doublelung:BAAALgAECgYJEgAAAA==.',
Dr='Draagone:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Drdiddles:BAAALgAECgMJAwAAAA==.',
Du='Duney:BAACLgAFFH8IAAMaAAQJZxIZJgAYAQAaAAQJ6Q0ZJgAYAQAbAAMJVhQyJADYAAAuAAQKf1EAAxsACQnYHscEAMQCABsACQlIHscEAMQCABoACAlSG34WADkCAAAA.Dußad:BAAALgAECgMJBwAAAA==.',
['Dé']='Déäth:BAAALgADCgQJBAAAAA==.',
Ec='Eckoe:BAABLgAECn8gAAIPAAcJKwaZdADVAAAPAAcJKwaZdADVAAAAAA==.',
Ee='Eekeros:BAAALgADCgUJBQAAAA==.Eeveeko:BAACLgAFFH8SAAIcAAQJZRJaCQAlAQAcAAQJZRJaCQAlAQAuAAQKfzsAAhwACQkcH3QGAG4CABwACQkcH3QGAG4CAAAA.',
Ej='Ejavuday:BAABLgAECn8wAAIDAAkJPSJlFwDKAgADAAkJPSJlFwDKAgAAAA==.',
El='Elvudu:BAAALgAECgQJBwAAAA==.',
Em='Emberstrife:BAAALgAECgEJAgAAAA==.',
En='Enerchi:BAAALgAFFAEJAQAAAA==.',
Er='Erazath:BAAALgAECgQJCAAAAA==.Erianar:BAAALgAECgIJAgAAAA==.Ericdruid:BAABLgAECn8aAAMSAAcJSiD3EgB+AgASAAcJSiD3EgB+AgAPAAEJ6QqZ1gAqAAAAAA==.Ericlock:BAAALgADCgMJAwAAAA==.',
Es='Essia:BAAALgAECgEJAQAAAA==.',
Ev='Eveko:BAAALgADCgIJAQAAAA==.Evera:BAABLgAECn8uAAIHAAkJ6gTHowAjAQAHAAkJ6gTHowAjAQAAAA==.Everlst:BAAALgADCgEJAQAAAA==.Evokinpants:BAAALgAECgcJDwAAAA==.Evos:BAAALgAECgQJBgAAAA==.',
Ex='Excels:BAACLgAFFH8OAAIPAAMJoBncMgDcAAAPAAMJoBncMgDcAAAuAAQKfyYAAg8ACQmpIu4DAH4DAA8ACQmpIu4DAH4DAAAA.Explicatory:BAAALgAECgYJBwABLgAFFAMJDgAPAKAZAA==.',
Ey='Eyllion:BAAALgAECgUJCgAAAA==.',
Fa='Falorin:BAAALgADCgMJAwAAAA==.Fastoris:BAAALgADCgEJAQAAAA==.Fauci:BAACLgAFFH8NAAIHAAUJVBQ+gQABAQAHAAUJVBQ+gQABAQAuAAQKfx4AAgcACAk4IeMfAIgCAAcACAk4IeMfAIgCAAAA.',
Fb='Fblthelost:BAAALgAECgMJAwAAAA==.',
Fe='Feihao:BAAALgADCggJFQAAAA==.Feile:BAABLgAECn82AAQIAAkJxhenMgAMAgAIAAkJxhenMgAMAgAdAAIJfgu/VwBnAAAeAAEJAAD1LwA+AAAAAA==.Fenty:BAAALgAECgUJBQABLgAECggJNgAUACEZAA==.Feshh:BAAALgADCgEJAQAAAA==.',
Fi='Fifezilla:BAAALgAECgIJAgAAAA==.Firble:BAAALgADCgYJBgAAAA==.Fireg:BAEALgADCgEJAQABLgAFFAQJBQADADULAA==.Fistbeaver:BAAALgADCgUJBQAAAA==.',
Fl='Flinzza:BAAALgAECgYJCwAAAA==.',
Fo='Foolezz:BAAALgAECgMJBAAAAA==.',
Fr='Fredthedh:BAABLgAECn8cAAIUAAkJZSFUFADeAgAUAAkJZSFUFADeAgAAAA==.Freshjordans:BAAALgAECgEJAQABLgAECgYJCwAEAAAAAA==.Fromtheback:BAAALgAECgYJDgABLgAECgkJGwAHAPAaAA==.',
Fu='Furble:BAAALgADCgYJBgAAAA==.',
Ga='Gaashw:BAAALgAECgIJBgAAAA==.Gadziila:BAAALgADCgEJAQAAAA==.Galcyon:BAAALgADCgEJAQAAAA==.Galiant:BAABLgAECn8mAAIHAAkJ/SPYFgC7AgAHAAkJ/SPYFgC7AgAAAA==.Gashdk:BAAALgAECgEJAQABLgAECgIJBgAEAAAAAA==.Gator:BAAALgAECgEJAQAAAA==.Gaulish:BAAALgADCgkJCQAAAA==.',
Ge='Geraldo:BAAALgAECgIJAgAAAA==.Gethalyn:BAABLgAECn8XAAIGAAcJCREilgBFAQAGAAcJCREilgBFAQAAAA==.Gexz:BAAALgADCgYJDAAAAA==.',
Gh='Ghee:BAAALgAECgEJAgAAAA==.',
Gi='Gianthippo:BAAALgAECgcJEgAAAA==.',
Gl='Glaivedaddy:BAAALgAECgEJAQAAAA==.Glenlives:BAAALgADCgkJCgABLgAECgkJLQANAEINAA==.',
Go='Gore:BAAALgAECgUJBQAAAA==.Gottverdammt:BAAALgAECgEJAQABLgAECgkJEAAEAAAAAA==.',
Gr='Graveknight:BAAALgAECgMJAwAAAA==.Graveshot:BAAALgADCgQJBAAAAA==.Greennrry:BAAALgAFFAEJAQABLgAFFAMJCAAfANsYAA==.Greennrryy:BAAALgAFFAEJAwABLgAFFAMJCAAfANsYAA==.Greenryy:BAAALgAECgIJAwABLgAFFAMJCAAfANsYAA==.Greyskin:BAAALgADCgEJAQAAAA==.Grizzabella:BAABLgAECn85AAIPAAkJ9RsCEADQAgAPAAkJ9RsCEADQAgAAAA==.Grreenry:BAABLgAFFH8IAAIfAAMJ2xjmCwDvAAAfAAMJ2xjmCwDvAAABLgAFFAMJCAAfANsYAA==.Grriz:BAAALgADCgEJAQAAAA==.Grtmustachio:BAAALgAECgkJEAAAAA==.Grundle:BAAALgAECgMJAwAAAA==.',
Gu='Gularak:BAAALgAECgQJBgAAAA==.Gunghø:BAAALgADCggJDwAAAA==.',
Gy='Gyutaro:BAAALgADCgEJAQAAAA==.',
Ha='Haelellionys:BAAALgADCgQJBAAAAA==.Hanamae:BAAALgADCgEJAQAAAA==.Hangnail:BAAALgAECgIJBAAAAA==.Hanswoloqued:BAACLgAFFH8OAAIIAAQJ2AXiaQDrAAAIAAQJ2AXiaQDrAAAuAAQKfxsAAwgACQmoC/ZrAGMBAAgACQmoC/ZrAGMBAB4AAgmmAQ0qAEsAAAAA.Harmfuljoker:BAAALgADCgQJBAAAAA==.Haxzen:BAAALgADCgMJBAAAAA==.',
He='Healufast:BAABLgAECn9EAAIOAAkJMR7hBgABAwAOAAkJMR7hBgABAwAAAA==.Hellsong:BAAALgAECgMJAwABLgAECgYJBgAEAAAAAA==.Helstrom:BAAALgAECgMJAwAAAA==.Hendo:BAAALgADCgYJBgAAAA==.Hendoh:BAAALgAECgIJAgAAAA==.Heysisters:BAAALgAECgIJAwAAAA==.',
Hi='Hispeas:BAAALgADCgQJBwAAAA==.Hitchkawk:BAAALgAECgEJAQAAAA==.Hitchlock:BAAALgAECgEJAwAAAA==.',
Ho='Holysabeline:BAACLgAFFH8GAAIFAAIJiBKDOQB6AAAFAAIJiBKDOQB6AAAuAAQKf0gAAgUACQlpGosTAHECAAUACQlpGosTAHECAAAA.Honestleon:BAAALgADCgMJAwABLgAECgcJFgAGAHgTAA==.Hordechief:BAAALgAFFAIJAgAAAA==.',
Hu='Huchar:BAABLgAECn9EAAMZAAkJ3SJeAwD/AgAZAAkJ3SJeAwD/AgAaAAEJmgy1pAAxAAAAAA==.Huevos:BAAALgAECgIJAwAAAA==.Huntersteve:BAABLgAECn8hAAMgAAgJQCOoCAAIAwAgAAgJQCOoCAAIAwAMAAYJ7CAfIwANAgAAAA==.',
Hy='Hydraxix:BAAALgAECgYJCwAAAA==.',
['Hô']='Hônk:BAAALgADCgEJAQABLgAECgkJLQANAEINAA==.',
Ia='Iamanopcow:BAAALgADCgQJBAAAAA==.Iamspeed:BAAALgADCgQJBAAAAA==.',
Ic='Iceblade:BAABLgAECn8oAAIFAAkJxxf2HwAaAgAFAAkJxxf2HwAaAgAAAA==.',
Ie='Ieatbabys:BAAALgADCgQJBAAAAA==.',
If='If:BAAALgAECgMJAwAAAA==.',
Ih='Ihideuseek:BAAALgAECgYJDwABLgAECgkJMAADAD0iAA==.',
Ii='Iityouup:BAAALgADCgYJCAAAAA==.',
Il='Illidaniella:BAABLgAECn8ZAAIUAAgJmQgwgAAcAQAUAAgJmQgwgAAcAQAAAA==.Illsmurfuup:BAABLgAECn8ZAAIYAAkJ9SZoAACnAwAYAAkJ9SZoAACnAwAAAA==.Iluminatus:BAAALgAECgQJBAAAAA==.',
In='Infection:BAAALgADCgYJCAAAAA==.Inverse:BAAALgADCgYJBgAAAA==.',
Ir='Ironßest:BAABLgAECn8hAAIgAAcJdxBxagBoAQAgAAcJdxBxagBoAQAAAA==.Irôh:BAAALgAECgEJAQABLgAECgUJGgAhAK4fAA==.',
Is='Ishmael:BAAALgADCgEJAQAAAA==.',
Iv='Ivannas:BAAALgAECgMJBgAAAA==.',
Ja='Jaabroni:BAAALgADCgIJAgAAAA==.Jackymoon:BAABLgAECn8aAAIGAAgJXCNWHgCOAgAGAAgJXCNWHgCOAgAAAA==.Jaxxion:BAAALgAECgEJAQAAAA==.',
Jd='Jdawg:BAABLgAECn8/AAIcAAkJQiUFAQA+AwAcAAkJQiUFAQA+AwAAAA==.',
Je='Jer:BAAALgADCgYJBgAAAA==.Jessaiyan:BAABLgAECn8sAAIUAAkJKyL2CAADAwAUAAkJKyL2CAADAwAAAA==.',
Ji='Jindo:BAAALgADCgcJBwAAAA==.Jiuni:BAAALgADCgUJBQAAAA==.',
Jj='Jjcjr:BAAALgAFFAIJAgABLgAFFAYJHQAiAJMhAA==.',
Ju='Julaidan:BAAALgAECgQJBAAAAA==.Julaudette:BAABLgAECn8eAAIeAAYJ3wgLGQD0AAAeAAYJ3wgLGQD0AAAAAA==.Juliania:BAAALgAECgIJAgAAAA==.Julzaria:BAABLgAECn8qAAIgAAgJchKvRwDGAQAgAAgJchKvRwDGAQAAAA==.Julzoblin:BAAALgAECgYJEQAAAA==.Jurny:BAABLgAECn8dAAMdAAgJiwzjFgDoAAAeAAcJzAoUFAApAQAdAAcJuQrjFgDoAAAAAA==.Jusdeen:BAABLgAECn8YAAMLAAkJtiJcBgCVAgALAAgJGSJcBgCVAgAPAAMJvA+4mAB9AAAAAA==.',
Ka='Kadookieii:BAAALgAFFAEJAQAAAA==.Kahlandra:BAABLgAECn83AAMjAAkJChtzAgApAgAjAAkJChtzAgApAgADAAgJ9QzNjwBVAQAAAA==.Kairoz:BAAALgAECgYJEwABLgAFFAEJAQAEAAAAAA==.Kaizer:BAACLgAFFH8UAAINAAUJLROuJAD/AAANAAUJLROuJAD/AAAuAAQKfyYAAg0ACAmrHN4YAE0CAA0ACAmrHN4YAE0CAAAA.Kalo:BAAALgAECgMJAwAAAA==.Kanrethad:BAAALgAECgQJBAABLgAECggJKgAKAAgbAA==.Karina:BAABLgAECn9HAAMUAAkJoCH1DgDJAgAUAAkJbCD1DgDJAgAVAAkJzxYcBwASAgAAAA==.Kastravia:BAABLgAFFH8GAAMUAAIJ1gJokQBPAAAUAAIJfAFokQBPAAAVAAEJ4AMOFAAoAAABLgAFFAQJFgARAB4HAA==.Kawolski:BAABLgAFFH8FAAIPAAMJ8Ab0SwCIAAAPAAMJ8Ab0SwCIAAABLgAFFAQJFgARAB4HAA==.',
Ke='Kelitarra:BAAALgADCgQJCAAAAA==.Kellibar:BAAALgAECgcJBwAAAA==.Kevin:BAAALgAECgcJCgAAAA==.Keyzer:BAAALgAECgEJAQAAAA==.',
Kh='Khanjuror:BAABLgAECn8tAAIdAAgJ1xTdCgCQAQAdAAgJ1xTdCgCQAQAAAA==.Kholonoe:BAABLgAECn8cAAIkAAkJmRR6IADAAQAkAAkJmRR6IADAAQAAAA==.Khornedog:BAABLgAECn8mAAIIAAcJihYNXACJAQAIAAcJihYNXACJAQAAAA==.Khrama:BAABLgAECn8WAAIKAAkJiSHQBQDIAgAKAAkJiSHQBQDIAgAAAA==.',
Ki='Kietemourt:BAAALgADCgUJBQAAAA==.Kiimachamara:BAAALgADCgIJAwAAAA==.Killik:BAAALgAECgQJBAAAAA==.Kinz:BAAALgAECgMJAwABLgABCgkJEgAEAAAAAA==.Kippili:BAAALgADCgQJBAABLgAECgYJCgAEAAAAAA==.Kiritokun:BAAALgADCgYJBAAAAA==.',
Kl='Klapz:BAAALgADCgcJDQABLgAECggJEAAEAAAAAA==.Kleenonean:BAACLgAFFH8UAAIkAAUJ6yQZCwCmAQAkAAUJ6yQZCwCmAQAuAAQKf14AAyQACQkBJuIAAHoDACQACQkBJuIAAHoDAA4AAgnGBlV0AFcAAAAA.',
Ko='Kobe:BAAALgAFFAEJAgAAAA==.',
Kp='Kpyassan:BAAALgAECgYJBQAAAA==.',
Kr='Kravenn:BAAALgAECgMJAwAAAA==.Kreuzritter:BAABLgAECn8zAAIYAAkJORDDCABcAgAYAAkJORDDCABcAgAAAA==.Kritterbug:BAAALgAECggJCAAAAA==.',
Ku='Kungcarefu:BAABLgAECn8bAAICAAYJQxIWRADnAAACAAYJQxIWRADnAAAAAA==.Kungfushnaz:BAAALgAECgEJAQAAAA==.Kurzaan:BAAALgAECgcJAgAAAA==.Kurzak:BAAALgAECgQJBwAAAA==.',
Ky='Kyle:BAAALgAECgEJAQABLgAFFAIJAgAEAAAAAA==.',
La='Laciel:BAAALgAECgMJBAABLgAECgkJIAAHAH0eAA==.Lacio:BAABLgAECn9HAAIkAAkJLwpBLAByAQAkAAkJLwpBLAByAQAAAA==.Larune:BAAALgADCgQJBwAAAA==.Lasten:BAAALgAECgEJAwAAAA==.Lavendàh:BAABLgAECn8oAAIFAAkJuCBfBQA7AwAFAAkJuCBfBQA7AwAAAA==.',
Le='Lemonite:BAACLgAFFH8PAAIPAAUJpxE8JQApAQAPAAUJpxE8JQApAQAuAAQKfxYAAg8ACQlwG+QUAI4CAA8ACQlwG+QUAI4CAAAA.Lennykoggins:BAABLgAECn8YAAIgAAgJLBfOSwC6AQAgAAgJLBfOSwC6AQAAAA==.Lexxix:BAAALgAECgUJBQAAAA==.Leyru:BAABLgAECn8sAAIFAAgJISTUBQAwAwAFAAgJISTUBQAwAwAAAA==.',
Li='Liberos:BAABLgAECn8YAAIJAAkJOBPjLAAAAgAJAAkJOBPjLAAAAgAAAA==.Lifenight:BAABLgAECn8kAAMlAAkJ6BxgBQBdAgAlAAkJ6BxgBQBdAgAHAAEJvwAGPwEJAAAAAA==.Lilnim:BAAALgAECgYJBgAAAA==.Lithvia:BAAALgAECgYJDQAAAA==.',
Ln='Lninedkhack:BAABLgAECn8mAAMHAAkJQRlaMwAvAgAHAAkJQRlaMwAvAgAKAAgJMQc0MQDXAAAAAA==.',
Lo='Lockdor:BAAALgAECgQJBAAAAA==.Logaar:BAABLgAECn80AAMFAAkJSxYzFgBYAgAFAAkJSxYzFgBYAgAGAAEJ7gHjxQEbAAAAAA==.Loretharan:BAAALgAECgEJAQAAAA==.Louvuitton:BAAALgADCgcJDgAAAA==.',
Lu='Lunartsy:BAAALgADCggJDgAAAA==.Lustiel:BAAALgAECgYJDAAAAA==.Luticris:BAAALgAECgMJBAAAAA==.',
Ly='Lyoric:BAAALgAECgEJAQAAAA==.',
Ma='Madmax:BAAALgADCggJCAAAAA==.Maegot:BAAALgADCgYJBgAAAA==.Magicpants:BAAALgAECgcJCgAAAA==.Magnetto:BAAALgADCggJDQAAAA==.Maiden:BAAALgADCgUJCAABLgAECggJKgAKAAgbAA==.Malexannius:BAAALgADCgUJCQAAAA==.Mannirot:BAAALgAECgEJAQAAAA==.Mariangel:BAAALgAECgUJCQAAAA==.Marrygold:BAAALgAECgEJAgABLgAECgkJIAAHAHYfAA==.Mateus:BAAALgAECgkJDQAAAA==.Maxdeath:BAABLgAECn8lAAIHAAgJ9iO/DQAtAwAHAAgJ9iO/DQAtAwAAAA==.Mazre:BAAALgAECgQJBwAAAA==.',
Me='Megtallica:BAAALgAECgUJCAAAAA==.Mendrelina:BAAALgAECgIJAgAAAA==.Mensrea:BAABLgAECn8hAAMJAAcJDhGnUgBkAQAJAAcJDhGnUgBkAQANAAUJagxVagCaAAAAAA==.Merlinn:BAAALgADCgMJBgAAAA==.Merrycold:BAABLgAECn8gAAMHAAkJdh9FPABGAgAHAAcJpSFFPABGAgAKAAUJ3RPkNwCyAAAAAA==.Merrygold:BAAALgADCgMJAwABLgAECgkJIAAHAHYfAA==.Merrygored:BAAALgAECgIJAgABLgAECgkJIAAHAHYfAA==.Mess:BAABLgAECn8uAAQZAAcJlB4cDwD0AQAZAAcJlB4cDwD0AQAaAAIJ3gfTlABsAAAbAAMJPQgXRwApAAABLgAECggJKgAKAAgbAA==.Methodical:BAAALgADCgUJBQAAAA==.Metophis:BAAALgAECgYJCgAAAA==.',
Mf='Mfboomstick:BAABLgAECn8/AAMYAAkJNCYdAQBcAwAYAAkJNCYdAQBcAwAMAAEJlSWhLABhAAAAAA==.',
Mi='Mikklelee:BAAALgADCgIJAgAAAA==.Minerva:BAAALgADCgMJAwAAAA==.Missdebby:BAAALgADCgYJCwAAAA==.Mistweaver:BAABLgAECn8dAAIRAAkJgiDFBQBJAwARAAkJgiDFBQBJAwAAAA==.Mistweaving:BAAALgAECgcJAwAAAA==.Mizirath:BAAALgAECgQJBAABLgAECggJMgALAKofAA==.',
Mo='Moghorva:BAABLgAECn8fAAMmAAkJzBj+CABXAgAmAAkJzBj+CABXAgAnAAEJ4w0vjgA5AAAAAA==.Mojoe:BAAALgAECgQJEAAAAA==.Mommyswaggin:BAABLgAECn8VAAIOAAkJChTVHgDJAQAOAAkJChTVHgDJAQAAAA==.Moonra:BAAALgAECgEJAQAAAA==.Moopocalypse:BAAALgADCgcJDAABLgAFFAQJDAAOAE0hAA==.Moopsta:BAAALgADCggJDgABLgAFFAQJDAAOAE0hAA==.Moopster:BAACLgAFFH8MAAIOAAQJTSGZDAB5AQAOAAQJTSGZDAB5AQAuAAQKfzYAAw4ACQmdJaYBAJ0DAA4ACQmdJaYBAJ0DAAEABgnfGYkhAL8BAAAA.Moopy:BAAALgAECgMJAwABLgAFFAQJDAAOAE0hAA==.Mordekaiserz:BAAALgAECgUJCwAAAA==.Morrgoth:BAAALgADCgEJAQAAAA==.',
Mu='Mucouslurp:BAAALgADCgEJAQAAAA==.',
Na='Nalahni:BAACLgAFFH8OAAInAAQJRQ1UNgDpAAAnAAQJRQ1UNgDpAAAuAAQKfyIAAicACQmHGO8VACgCACcACQmHGO8VACgCAAAA.Nanashi:BAAALgAECgMJAwAAAA==.Nastage:BAAALgADCgMJAQAAAA==.Nastus:BAAALgAECgMJAwAAAA==.Nayela:BAAALgAECgYJEAAAAA==.Nazgru:BAAALgAECgEJAQAAAA==.',
Ne='Neptuneakis:BAABLgAECn8mAAISAAkJFRerEwA0AgASAAkJFRerEwA0AgAAAA==.Neptuno:BAAALgADCgEJAQABLgAECgkJJgASABUXAA==.Nerfblaster:BAAALgADCgEJAQAAAA==.Newcarsmell:BAABLgAECn8UAAQFAAkJ9Q9yIwDnAQAFAAgJtxFyIwDnAQATAAUJMwtbLwCnAAAGAAEJmAHXywERAAAAAA==.',
Ni='Nicktee:BAAALgAECgUJCQAAAA==.Nightmares:BAAALgAECgcJCgAAAA==.Nightrvn:BAAALgAECgQJBAAAAA==.Nimrose:BAABLgAECn8YAAIDAAkJogOkoQA1AQADAAkJogOkoQA1AQAAAA==.Niquid:BAABLgAECn8nAAIPAAgJtxVmMADeAQAPAAgJtxVmMADeAQAAAA==.',
No='Nolmac:BAABLgAECn8oAAIJAAkJ/SJWBgBJAwAJAAkJ/SJWBgBJAwAAAA==.Notahealer:BAAALgAFFAIJAwABLgAFFAMJBAAEAAAAAA==.Noxloxes:BAAALgADCgcJDAAAAA==.',
Np='Npv:BAABLgAFFH8HAAIHAAIJgQ1s4QCDAAAHAAIJgQ1s4QCDAAAAAA==.',
Ny='Nyssavia:BAAALgADCgcJDgAAAA==.',
Oa='Oakshre:BAABLgAECn80AAIQAAkJnSAvBwDVAgAQAAkJnSAvBwDVAgAAAA==.',
Ob='Obliteration:BAAALgAECgYJBwABLgAFFAEJAQAEAAAAAA==.',
Ol='Olivertwist:BAAALgAECgQJDgABLgAFFAEJAQAEAAAAAA==.',
Om='Omnimpotent:BAAALgAECgEJAQABLgAECgIJBQAEAAAAAA==.',
On='Ontwarr:BAAALgADCgkJEAAAAA==.Ontwou:BAABLgAECn8WAAIgAAgJ4xg3OwDuAQAgAAgJ4xg3OwDuAQAAAA==.',
Op='Ophi:BAAALgAECgYJEQAAAA==.',
Os='Oshaku:BAAALgAECgcJDAAAAQ==.',
Ou='Ouchpotato:BAACLgAFFH8FAAIGAAQJLhHyRAAcAQAGAAQJLhHyRAAcAQAuAAQKfxUAAgYACQlMHesaAKACAAYACQlMHesaAKACAAEuAAUUBAkOABcAiRYA.',
Pa='Paarthurnax:BAABLgAFFH8FAAMnAAMJMwkWSQCjAAAnAAMJKAgWSQCjAAAiAAEJFAc7DwA+AAAAAA==.Palathal:BAAALgAECgUJBgABLgAECggJGQADAPoTAA==.Pallynim:BAAALgADCgQJBwAAAA==.Palms:BAACLgAFFH8NAAIQAAQJ1hvuDgBBAQAQAAQJ1hvuDgBBAQAuAAQKfxgAAhAACQlDIpgHAAIDABAACQlDIpgHAAIDAAAA.Pancakezebra:BAABLgAECn8yAAIYAAkJ6Rp0EAArAgAYAAkJ6Rp0EAArAgAAAA==.Pantsftw:BAABLgAECn8fAAMOAAgJQwzQMwAyAQAOAAgJ1QvQMwAyAQABAAEJQQUsewAuAAAAAA==.Papabear:BAAALgADCgUJBQAAAA==.Parkbreezy:BAABLgAECn8bAAILAAcJBwrWQACcAAALAAcJBwrWQACcAAAAAA==.Passera:BAAALgAECggJEQAAAA==.Pawg:BAAALgADCgcJBgAAAA==.',
Pe='Pebbles:BAAALgAECgcJBwAAAA==.Peltier:BAABLgAECn8sAAIDAAkJdCAXJQCFAgADAAkJdCAXJQCFAgAAAA==.Pendle:BAABLgAECn8sAAMIAAgJFA6EYgB6AQAIAAgJfg2EYgB6AQAdAAYJHQvDKQAbAQAAAA==.Perilous:BAAALgAECgIJAgABLgAFFAQJDgAXAIkWAA==.',
Ph='Phoenix:BAABLgAECn8tAAIGAAkJbB89GgCkAgAGAAkJbB89GgCkAgAAAA==.',
Pl='Plox:BAAALgAECgYJEwAAAA==.Plurnizz:BAABLgAECn8dAAMIAAkJHQjLhgArAQAIAAkJHQjLhgArAQAdAAQJEwHKXwBPAAAAAA==.',
Po='Pocketchange:BAACLgAFFH8RAAIJAAUJahbMIABmAQAJAAUJahbMIABmAQAuAAQKfxUAAw0ACQniGnEqAMIBAA0ABgnWHHEqAMIBAAkABgm/FzJLAFYBAAAA.',
Pu='Puffadin:BAAALgADCgEJAQAAAA==.Puppymoke:BAAALgAECgMJAwAAAA==.Puptart:BAAALgAECgUJBQAAAA==.',
Ra='Raest:BAABLgAECn8pAAICAAgJyCTSBQDeAgACAAgJyCTSBQDeAgABLgAECgkJFgAKAIkhAA==.Raiker:BAAALgAECgMJBAAAAA==.Ranch:BAAALgAECgEJAQAAAA==.Razzlock:BAAALgAECgEJAQAAAA==.',
Re='Regret:BAAALgAECgkJEgAAAA==.Relovan:BAABLgAECn8vAAMbAAkJ6RAdFgCoAQAbAAkJ6RAdFgCoAQAaAAUJSwOYhgClAAAAAA==.Renothidan:BAACLgAFFH8NAAIGAAQJqxnEMABJAQAGAAQJqxnEMABJAQAuAAQKfyMAAgYACQnZGws4AB8CAAYACQnZGws4AB8CAAAA.Reuben:BAAALgAECgUJBQAAAA==.Revin:BAAALgADCgYJBgAAAA==.Revrynth:BAAALgAECggJEAABLgAECggJKQAZAPUiAA==.Rexorcist:BAAALgAECgcJDQAAAA==.',
Ri='Rickyboby:BAAALgAECggJDAAAAA==.Righteøus:BAAALgAECgUJDwAAAA==.Rillan:BAABLgAECn8aAAIGAAYJ8xa9mQA/AQAGAAYJ8xa9mQA/AQAAAA==.Rin:BAAALgAECgkJCQABLgAECgkJPwAIAEklAA==.Ripper:BAAALgAECgUJCQAAAA==.Rippèd:BAAALgAECgYJCwAAAA==.Rithcice:BAABLgAECn84AAMaAAkJtCbcAAB/AwAaAAkJqSbcAAB/AwAZAAcJ/yOlCABsAgAAAA==.Rizzdolphler:BAACLgAFFH8QAAIGAAQJqRSHQQAjAQAGAAQJqRSHQQAjAQAuAAQKfygAAwYACAmyHaM0ACsCAAYACAmyHaM0ACsCAAUABgktEQpCADYBAAAA.',
Ro='Roadnurse:BAAALgADCgIJAgAAAA==.Rockntroll:BAAALgADCgIJAgAAAA==.Rodah:BAAALgADCgkJEAAAAA==.Roscoee:BAAALgADCgEJAQAAAA==.Roselynt:BAAALgAECgMJAwAAAA==.',
Rs='Rsk:BAAALgADCgYJCQABLgAECggJKgAKAAgbAA==.',
Ru='Ruins:BAAALgAECgEJAQAAAA==.',
['Rà']='Ràrity:BAAALgADCggJCAAAAA==.',
['Rö']='Rönburgundy:BAACLgAFFH8MAAIIAAMJUxF+cwDVAAAIAAMJUxF+cwDVAAAuAAQKfy4AAggACQmNHmgdAHICAAgACQmNHmgdAHICAAAA.',
Sa='Sanako:BAABLgAECn8oAAISAAkJxxG3HgDPAQASAAkJxxG3HgDPAQAAAA==.Sanastusa:BAAALgADCgYJCAAAAA==.Saneros:BAAALgAECggJCQABLgAECggJNgAUACEZAA==.Santoniche:BAAALgAECgUJBAAAAA==.Sap:BAABLgAECn8gAAMXAAcJFxe8HgCcAQAXAAcJFxe8HgCcAQAoAAQJQgs+FgDIAAABLgAECggJKgAKAAgbAA==.Sausiege:BAAALgAECgMJAwAAAA==.Saveserenade:BAAALgAECgUJBQAAAA==.',
Sc='Scarylarry:BAABLgAECn82AAIUAAgJIRnROwDUAQAUAAgJIRnROwDUAQAAAA==.Scyther:BAACLgAFFH8LAAMhAAQJbwwAFAAAAQAhAAQJMAwAFAAAAQAUAAIJRwOZiwBkAAAuAAQKfxgAAxQACQlBD8txAE8BABQACAk9DMtxAE8BACEABglZEYFKAIcAAAAA.',
Sd='Sdh:BAAALgADCgQJBgAAAA==.',
Se='Seaze:BAAALgADCgYJCwAAAA==.Seishinokami:BAABLgAECn8tAAINAAkJQg17LgCEAQANAAkJQg17LgCEAQAAAA==.Senala:BAAALgAECgEJAQAAAA==.Serenade:BAACLgAFFH8KAAIDAAQJqBGMaAAbAQADAAQJqBGMaAAbAQAuAAQKfyQAAgMACAmuHxYzAKYCAAMACAmuHxYzAKYCAAAA.Setheron:BAABLgAECn8sAAIaAAkJdSF+BQAHAwAaAAkJdSF+BQAHAwAAAA==.Sethron:BAAALgAECgIJAgAAAA==.Señsei:BAAALgAECggJCwAAAA==.',
Sh='Shamminit:BAAALgAECgIJAgAAAA==.Shamtul:BAAALgAECgEJAwAAAA==.Shamwow:BAAALgADCgcJDgAAAA==.Shlea:BAACLgAFFH8QAAInAAQJBAi0OwDVAAAnAAQJBAi0OwDVAAAuAAQKfx0AAicACQn7EKMoAJ4BACcACQn7EKMoAJ4BAAAA.Shyva:BAABLgAECn8pAAMZAAgJ9SIxBwC4AgAZAAgJ9SIxBwC4AgAaAAUJ9xdTUgAAAQAAAA==.',
Si='Siinestro:BAAALgAECgQJBAAAAA==.Sinlee:BAAALgAECgcJDgABLgAECgkJOgAIAEMiAA==.',
Sl='Slayla:BAAALgAECgUJDAAAAA==.Slimboyjoe:BAAALgADCgcJDgAAAA==.Slimmjim:BAAALgADCgEJAQAAAA==.Slinkstir:BAAALgADCgQJAwAAAA==.',
Sn='Snailtrails:BAAALgAECgcJBwAAAA==.Sneak:BAAALgADCgMJAwABLgAECgYJCwAEAAAAAA==.Sneakcookies:BAAALgAECgMJBwABLgAFFAEJAQAEAAAAAA==.',
So='Soggyundies:BAAALgAECgQJBAAAAA==.Solendros:BAAALgAECgYJDwAAAA==.Sonthar:BAAALgAECgYJBgAAAA==.Soulborn:BAAALgADCgMJAwAAAA==.Soulelf:BAAALgADCgcJBwAAAA==.',
Sp='Spacehog:BAAALgAECgYJDAAAAA==.Sparticus:BAAALgAECgEJAQAAAA==.Spiro:BAAALgAECgEJAQABLgAFFAMJCQAQAHUeAA==.Splouge:BAAALgAECgYJBgAAAA==.',
St='Standarshh:BAACLgAFFH8FAAIgAAMJ5xnyUwD3AAAgAAMJ5xnyUwD3AAAuAAQKf0AAAiAACQl1IlwKAAEDACAACQl1IlwKAAEDAAAA.Stemmz:BAAALgADCgEJAQAAAA==.Stronghand:BAAALgADCgYJBwAAAA==.',
Su='Subtle:BAACLgAFFH8OAAIXAAQJiRaNGQBDAQAXAAQJiRaNGQBDAQAuAAQKfygAAxcACQnXHywNAMcCABcACQnXHywNAMcCACkABQmpBmYZAIgAAAAA.Sugarbabi:BAABLgAECn8hAAMPAAkJDR8uIQA7AgAPAAcJ3x4uIQA7AgASAAYJRRgZJwCSAQAAAA==.Sugarqween:BAAALgAECgYJBwAAAA==.Sugarrush:BAAALgADCgUJBQAAAA==.Sugarshot:BAAALgAECggJCAAAAA==.Sugarthorn:BAAALgADCgkJCQAAAA==.Sulcer:BAAALgADCgMJBAAAAA==.',
Sw='Swiftwing:BAAALgADCgYJBgAAAA==.',
Sy='Sylria:BAAALgAECgIJAgAAAA==.Sylrianah:BAABLgAECn9IAAQOAAkJ0CAwBwD6AgAOAAkJ0CAwBwD6AgAkAAkJ4QgPLQBuAQABAAQJrgjbVQCkAAAAAA==.Sylveste:BAACLgAFFH8WAAIFAAUJLiOfDQDTAQAFAAUJLiOfDQDTAQAuAAQKfyMAAgUABwkUGhUxAJEBAAUABwkUGhUxAJEBAAAA.Sylvfelster:BAAALgAECgYJBwABLgAFFAUJFgAFAC4jAA==.Sylánnia:BAAALgADCgcJBwAAAA==.',
Ta='Ta:BAABLgAECn8aAAIBAAcJpAiQOAAuAQABAAcJpAiQOAAuAQAAAA==.Talis:BAAALgAECgEJAQAAAA==.Tankhiskhan:BAABLgAECn8VAAIKAAgJQA0SLgDqAAAKAAgJQA0SLgDqAAAAAA==.Tarlis:BAABLgAECn8YAAIeAAgJ9xq8BAAqAgAeAAgJ9xq8BAAqAgAAAA==.',
Te='Tedrickeyjr:BAAALgAECgEJBgAAAA==.Terithresh:BAAALgADCgMJBAAAAA==.',
Th='Thanil:BAABLgAECn8uAAIGAAkJsBc9NQApAgAGAAkJsBc9NQApAgAAAA==.Thelliane:BAAALgAECgIJAgABLgAFFAYJIwAJAFcTAA==.Thenet:BAAALgAECgEJAwAAAA==.',
Ti='Tie:BAAALgAECggJCwAAAA==.Tikamancer:BAAALgADCgEJAQAAAA==.Tilvalhalla:BAABLgAECn8cAAImAAcJPAogKgAhAQAmAAcJPAogKgAhAQAAAA==.',
To='Todorokii:BAAALgAECgUJDQAAAA==.Tom:BAAALgAECgEJAgABLgAFFAIJAgAEAAAAAA==.Torrin:BAAALgADCgYJBwAAAA==.Tortricid:BAAALgAECgcJDgAAAA==.Totaldchtree:BAAALgAECgEJAQAAAA==.Totempants:BAAALgAECgYJBgAAAA==.Totinospizza:BAAALgADCgYJBgAAAA==.',
Tr='Trashkan:BAAALgADCgIJAgAAAA==.Trauck:BAAALgADCgEJAQAAAA==.Traumzi:BAAALgAECgEJAQAAAA==.Travvy:BAACLgAFFH82AAMXAAgJmCJOAQD+AQAXAAgJUx5OAQD+AQAoAAIJoR5uDABqAAAuAAQKfyIAAhcACQkWJgEBAMMDABcACQkWJgEBAMMDAAAA.Treezus:BAAALgADCgYJCAAAAA==.Trevmo:BAABLgAECn82AAIZAAkJGyBdBgCkAgAZAAkJGyBdBgCkAgAAAA==.Trexin:BAAALgAECgUJBwAAAA==.',
Tu='Turaylon:BAAALgAFFAEJAQAAAA==.Turtlebox:BAAALgAECgQJBgAAAA==.',
Ty='Tym:BAAALgAFFAIJAgAAAA==.',
Ug='Ugargro:BAABLgAECn8VAAMZAAUJPgd5OACPAAAZAAUJPgd5OACPAAAaAAEJGwW+sAAkAAAAAA==.',
Un='Unapologetic:BAAALgAECggJDAAAAA==.Unbreakabull:BAABLgAFFH8NAAISAAUJ/yUbDgCyAQASAAUJ/yUbDgCyAQAAAA==.Unceejin:BAAALgADCggJEQAAAA==.Unholydk:BAABLgAECn8qAAMKAAgJCBuqDwAOAgAKAAgJCBuqDwAOAgAHAAUJsw8u4wDNAAAAAA==.',
Va='Valcuna:BAAALgAECgQJBQAAAA==.Valka:BAABLgAECn8YAAIfAAkJUgmXGQA7AQAfAAkJUgmXGQA7AQAAAA==.Vamptouch:BAAALgAECgIJAwABLgAECgYJCwAEAAAAAA==.Vanaan:BAAALgAECgIJAgABLgAECgYJBwAEAAAAAA==.Varidrus:BAAALgAECgQJBQAAAA==.Vaste:BAAALgADCgcJCQAAAA==.',
Ve='Ventrue:BAABLgAECn8jAAIDAAkJ6xUGXQDEAQADAAkJ6xUGXQDEAQAAAA==.Veyle:BAABLgAECn8/AAMXAAkJ1yQ9BQDfAgAXAAkJ1yQ9BQDfAgAoAAEJKh7AGwBJAAAAAA==.',
Vi='Vivian:BAABLgAECn8xAAIhAAkJfRqMCgB8AgAhAAkJfRqMCgB8AgABLgAFFAMJCQAQAHUeAA==.',
Vo='Voidsurge:BAABLgAECn8xAAQVAAcJ+hhCDACPAQAVAAcJUxZCDACPAQAhAAUJMxs5JwA8AQAUAAUJyQ9MrwDEAAABLgAECggJKgAKAAgbAA==.',
Vy='Vyndria:BAAALgAECgQJDwAAAA==.',
Wa='Wardell:BAAALgAECgEJAQAAAA==.',
We='Weaspore:BAABLgAECn8hAAIHAAgJlR6nQQD7AQAHAAgJlR6nQQD7AQAAAA==.Weasy:BAAALgAECgkJDgAAAA==.',
Wo='Woogidaboogi:BAAALgAECgIJBQAAAA==.Woogieboogie:BAAALgAECgEJAQABLgAECgIJBQAEAAAAAA==.',
Xi='Xiamiel:BAAALgADCgYJCQAAAA==.',
Xl='Xl:BAABLgAECn9WAAMhAAgJ/RxVCwCrAgAhAAgJhxxVCwCrAgAUAAgJJxZrRAC2AQAAAA==.',
Ya='Yaitoopmfp:BAAALgAECgEJAQABLgAECgkJIAAHAHYfAA==.',
Yh='Yharnem:BAABLgAECn8XAAICAAcJ8hDELQBMAQACAAcJ8hDELQBMAQAAAA==.',
Yo='Yogurtpants:BAAALgAECgYJEgAAAA==.Yonny:BAAALgADCgEJAQAAAA==.',
Yu='Yukionna:BAAALgADCgcJCwAAAA==.',
Za='Zabara:BAABLgAECn8cAAIJAAgJgSGAEADJAgAJAAgJgSGAEADJAgAAAA==.Zabbystabby:BAAALgADCgkJDgAAAA==.Zakaraki:BAABLgAECn8+AAQiAAkJhCWkAAA9AwAiAAkJhCWkAAA9AwAnAAcJNyHNGAAOAgAmAAcJTAd5JgBBAQAAAA==.Zaki:BAABLgAECn8aAAIUAAkJThoKIwBBAgAUAAkJThoKIwBBAgAAAA==.Zanked:BAAALgADCgQJBAAAAA==.Zarkingu:BAAALgADCgMJAwAAAA==.',
Ze='Zealot:BAAALgAFFAEJAQAAAA==.Zeleria:BAAALgAECgUJBgAAAA==.Zeno:BAAALgAFFAIJAgAAAA==.Zephyr:BAAALgAECgQJBAAAAA==.Zerathis:BAABLgAECn86AAIIAAkJQyJpDgDXAgAIAAkJQyJpDgDXAgAAAA==.Zerathül:BAAALgAECgcJEgAAAA==.Zerötwo:BAAALgADCgkJCgAAAA==.Zestul:BAAALgADCgkJFgAAAA==.',
Zi='Zimbobayaga:BAAALgAECgMJAwAAAA==.',
Zo='Zodivine:BAAALgADCgMJAwAAAA==.Zohar:BAAALgADCgEJAgAAAA==.Zooty:BAAALgADCgUJAwAAAA==.Zoshow:BAAALgAFFAIJAgAAAA==.',
Zu='Zuggo:BAAALgADCgYJBgAAAA==.',
Zy='Zyrig:BAAALgADCgUJBgAAAA==.',
['Zõ']='Zõshow:BAABLgAECn8XAAMIAAcJmxWlcABYAQAIAAcJeBWlcABYAQAdAAEJEh0zYABOAAAAAA==.',
['Ça']='Çaptainçhaos:BAAALgAECgYJCgAAAA==.',
['Ða']='Ðaredevil:BAACLgAFFH8JAAIQAAMJdR5lFgAIAQAQAAMJdR5lFgAIAQAuAAQKfy4AAhAACQnmHyQHANUCABAACQnmHyQHANUCAAAA.',
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
