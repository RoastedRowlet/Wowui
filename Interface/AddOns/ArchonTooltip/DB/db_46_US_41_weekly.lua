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

local lookup = {'Priest-Discipline','Monk-Brewmaster','Mage-Frost','Unknown-Unknown','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','Warlock-Demonology','Shaman-Restoration','DeathKnight-Blood','Hunter-Marksmanship','Priest-Holy','Druid-Restoration','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Shaman-Elemental','Paladin-Protection','DemonHunter-Devourer','Mage-Fire','DemonHunter-Vengeance','Rogue-Subtlety','Hunter-Survival','Warrior-Protection','Warrior-Arms','Shaman-Enhancement','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Warrior-Fury','Hunter-BeastMastery','Evoker-Augmentation','Mage-Arcane','Priest-Shadow','DeathKnight-Frost','Evoker-Preservation','Rogue-Assassination','DemonHunter-Havoc','Rogue-Outlaw','Evoker-Devastation',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aahzbear:BAAALgAECgUJDAAAAA==.',
Ab='Abreale:BAAALgADCgMJAwAAAA==.',
Ae='Aeero:BAABLgAECn8UAAIBAAYJNhfEHwCWAQABAAYJNhfEHwCWAQAAAA==.Aerendyl:BAAALgAECgcJCwAAAA==.',
Ai='Aiden:BAACLgAFFH8HAAICAAMJbRBgLwDLAAACAAMJbRBgLwDLAAAuAAQKfxQAAgIABgkfHF8qALcBAAIABgkfHF8qALcBAAAA.',
Al='Algros:BAAALgADCgEJAQAAAA==.Alyiriia:BAAALgAECgkJCQAAAA==.',
Am='Amathal:BAABLgAECn8ZAAIDAAgJ+hPUdgBuAQADAAgJ+hPUdgBuAQAAAA==.Amilea:BAAALgAFFAEJAQABLgABCgkJEgAEAAAAAA==.',
An='Anastasia:BAAALgADCggJCAAAAA==.Angelsevoker:BAAALgAECggJCAAAAA==.Angermoonria:BAAALgADCgcJBwAAAA==.Ankheloios:BAAALgADCggJDgAAAA==.Antihiiro:BAAALgAECgMJAwAAAA==.Antipro:BAAALgAFFAEJAQAAAA==.Anubbus:BAAALgAFFAEJAQAAAA==.Anzulok:BAAALgADCgYJAQAAAA==.',
Ar='Arbalest:BAAALgADCgcJBgAAAA==.Aredhela:BAABLgAECn8VAAMFAAgJqhZrpAAPAQAFAAQJDxdrpAAPAQAGAAQJMBDnVwCnAAAAAA==.Arinth:BAAALgADCggJEQAAAA==.Armpit:BAAALgAECgMJAwAAAA==.',
As='Ascanius:BAAALgADCgQJBAAAAA==.Ashiiro:BAAALgAECgcJEAAAAA==.Ashveil:BAAALgAECgUJBQABLgAECggJJQAHAGYaAA==.Asia:BAABLgAECn8/AAIIAAkJSSW3AwBGAwAIAAkJSSW3AwBGAwAAAA==.Asmodeius:BAAALgAFFAEJAgAAAA==.Astroprof:BAAALgAECgEJAQABLgAECgYJFAAJAFsaAA==.',
At='Athrea:BAABLgAECn8UAAMKAAkJkRu5HgAvAQAHAAgJcBifcgCiAQAKAAUJUBu5HgAvAQAAAA==.',
Au='Auntjemima:BAAALgAECgEJAgAAAA==.Aureleus:BAAALgADCgEJAQAAAA==.',
Aw='Away:BAAALgADCgIJAgAAAA==.',
Az='Azaii:BAAALgADCggJCgAAAA==.Azlear:BAAALgAECgkJBgAAAA==.',
Ba='Babilouchoux:BAAALgAECgMJBQAAAA==.Ballz:BAAALgADCgYJBgAAAA==.Bano:BAAALgAECgMJAwAAAA==.Barnre:BAAALgAECgYJCQABLgAECgYJDAAEAAAAAA==.Bash:BAAALgAECgcJBwABLgAECggJKAAKAAgbAA==.Baythos:BAAALgAFFAEJAgAAAA==.',
Bb='Bb:BAAALgAECgIJAQAAAA==.',
Bd='Bdssm:BAAALgAECgcJDwAAAA==.',
Be='Beefstick:BAAALgAECgUJBwAAAA==.Berzercarl:BAAALgAECgEJAQAAAA==.Beserkfury:BAABLgAECn8jAAILAAkJOQ1sCwCLAQALAAkJOQ1sCwCLAQAAAA==.',
Bh='Bhemtu:BAAALgADCggJEgAAAA==.',
Bi='Biercan:BAAALgAECggJDQAAAA==.Bigcarl:BAAALgADCgMJAwAAAA==.Binke:BAAALgAECgcJEgAAAA==.Bittywhite:BAAALgAECgMJAwAAAA==.Bittywyvern:BAAALgADCgUJCwABLgAECgMJAwAEAAAAAA==.',
Bk='Bkarakh:BAAALgADCgMJAwAAAA==.',
Bl='Blayze:BAABLgAECn8ZAAIMAAcJfxWkHwCjAQAMAAcJfxWkHwCjAQAAAA==.Blessidbee:BAAALgAECgEJAQAAAA==.Blightmarx:BAAALgADCgUJCAAAAA==.Blitzwow:BAAALgADCgYJBQAAAA==.Bluemoonflay:BAAALgAECgkJEwAAAA==.Blúnt:BAAALgADCgQJBAAAAA==.',
Bo='Bobheals:BAABLgAECn8eAAMNAAYJbA/NWAANAQANAAUJJBLNWAANAQAOAAEJAAAdagAAAAAAAA==.Boibye:BAAALgAECgYJDgAAAA==.Bolblock:BAAALgAECgkJDwAAAA==.Bonewolf:BAAALgADCgMJAwAAAA==.Boostedww:BAAALgAECgMJBwAAAA==.',
Br='Brambleclaw:BAABLgAECn8/AAIKAAkJRSMGAwD6AgAKAAkJRSMGAwD6AgAAAA==.Brayker:BAABLgAECn9HAAIFAAkJoyV+AwBUAwAFAAkJoyV+AwBUAwAAAA==.Breadoneal:BAABLgAECn8mAAMGAAkJzxcHGwAFAgAGAAgJ5hgHGwAFAgAFAAEJyAT7dgEoAAAAAA==.Breeze:BAAALgAECgYJBgAAAA==.Brewed:BAABLgAECn8qAAMPAAgJjxTMHQCWAQAPAAgJjxTMHQCWAQAQAAEJLwFZoQALAAAAAA==.Brisketbane:BAAALgAECgcJEAAAAA==.Brokenmask:BAACLgAFFH8KAAINAAQJCBkGHQA7AQANAAQJCBkGHQA7AQAuAAQKfxUAAw0ACAkOIEobAGECAA0ACAkOIEobAGECABEAAgkLEVh2ADIAAAAA.Broxxar:BAAALgAECgIJAgAAAA==.Bruxxe:BAAALgAECgcJAQAAAA==.Brüenor:BAAALgAECgIJAgAAAA==.',
Bu='Burntroot:BAABLgAECn8gAAISAAcJBQQFUwC8AAASAAcJBQQFUwC8AAAAAA==.',
Ca='Caedwyn:BAABLgAECn8yAAIOAAgJqh/OBQB2AgAOAAgJqh/OBQB2AgAAAA==.Caitrakk:BAABLgAECn8UAAMJAAYJWxqgMgC7AQAJAAYJWxqgMgC7AQASAAUJYhC9TAAVAQAAAA==.Calignus:BAABLgAECn8dAAMFAAgJyRFEigA7AQAFAAgJyRFEigA7AQATAAUJVQ8jJwDQAAAAAA==.Captjack:BAABLgAECn8dAAIUAAkJrAu8VQBiAQAUAAkJrAu8VQBiAQAAAA==.Cartilage:BAABLgAECn8lAAIHAAkJXRTcNgABAgAHAAkJXRTcNgABAgAAAA==.Catalei:BAAALgAECgYJDwAAAA==.Caution:BAAALgADCgYJCwAAAA==.',
Ce='Celira:BAAALgAECgEJAQAAAA==.Celys:BAAALgAECgIJAgAAAA==.',
Ch='Chickenman:BAAALgAECgEJAQAAAA==.Chiselia:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Choconilla:BAAALgAECgcJEgAAAA==.Chonkmonk:BAAALgADCgQJBAAAAA==.Choppa:BAAALgADCggJCgAAAA==.Chorizo:BAAALgAECgEJAQABLgAECgkJGwAQAKwfAA==.Chupacabrass:BAAALgADCgYJBgAAAA==.Chëbbles:BAAALgADCgMJAwABLgAECggJFAARANIQAA==.',
Ci='Cinnomun:BAAALgADCgEJAQAAAA==.',
Co='Combustinme:BAAALgAECgQJBAABLgAECggJLwAUAAcYAA==.Consuming:BAABLgAECn8kAAINAAgJYBR0MwCsAQANAAgJYBR0MwCsAQAAAA==.Coorsbanquet:BAAALgAECggJEgAAAA==.Coorsbite:BAAALgADCgcJCAAAAA==.Corgh:BAABLgAECn8kAAIVAAYJtw4XBgBIAQAVAAYJtw4XBgBIAQAAAA==.Corrahthecow:BAAALgADCgEJAQAAAA==.Cowardice:BAAALgADCgYJCwAAAA==.',
Cr='Craccjar:BAAALgAECgIJAgAAAA==.Crackjar:BAAALgADCgcJDAAAAA==.Crash:BAECLgAFFH8NAAIUAAUJEhoyLAA3AQAUAAUJEhoyLAA3AQAuAAQKfzMAAxQACAn2JI4MAMcCABQACAn2JI4MAMcCABYAAQkwGZwnAEIAAAAA.Croarik:BAAALgAECgEJAQAAAA==.Crushix:BAABLgAECn81AAIGAAkJKhhHHwAfAgAGAAkJKhhHHwAfAgAAAA==.',
Cs='Csyasha:BAAALgAECgIJAgAAAA==.',
Cy='Cybear:BAAALgAECgUJBwAAAA==.Cykun:BAABLgAECn8uAAIXAAkJcSDRBQCyAgAXAAkJcSDRBQCyAgAAAA==.',
['Cã']='Cãs:BAAALgADCgkJCgABLgAECgkJGgANALQNAA==.',
Da='Darch:BAABLgAECn8/AAMYAAkJMCRwAgAKAwAYAAkJMCRwAgAKAwALAAEJPwm2kAAqAAAAAA==.Davidx:BAAALgADCgcJCgAAAA==.',
De='Deadgripz:BAAALgADCgMJBgAAAA==.Deadjaden:BAAALgADCgEJAQAAAA==.Deadlos:BAAALgADCgYJCAAAAA==.Deathscreams:BAAALgAECgQJBgAAAA==.Deathxreaper:BAAALgAECgQJCwAAAA==.Decessus:BAAALgAECgUJBgAAAA==.Dekig:BAABLgAECn8jAAIHAAgJDRRxUgCoAQAHAAgJDRRxUgCoAQAAAA==.Demine:BAABLgAECn8zAAIDAAgJgB8VJABwAgADAAgJgB8VJABwAgAAAA==.Demonvibe:BAAALgAECgQJBgAAAA==.',
Di='Dico:BAAALgAECgIJAgABLgAFFAcJIgAZAHkdAA==.Dinobots:BAAALgAECgYJDAAAAA==.Dipper:BAABLgAECn8bAAIFAAkJSxjINgAFAgAFAAkJSxjINgAFAgAAAA==.Divinator:BAAALgAECgYJCwAAAA==.',
Do='Donbarriga:BAAALgAECgYJCAAAAA==.Dosmojitos:BAAALgADCgcJBwAAAA==.Doublejumps:BAAALgAECgYJCwAAAA==.Doublelung:BAAALgAECgYJEgAAAA==.',
Dr='Draagone:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Drdiddles:BAAALgAECgMJAwAAAA==.',
Du='Duney:BAABLgAECn86AAIaAAkJdx3yAwC+AgAaAAkJdx3yAwC+AgAAAA==.Dußad:BAAALgAECgMJBwAAAA==.',
['Dé']='Déäth:BAAALgADCgQJBAAAAA==.',
Ec='Eckoe:BAABLgAECn8gAAINAAcJKwbRaADZAAANAAcJKwbRaADZAAAAAA==.',
Ee='Eekeros:BAAALgADCgUJBQAAAA==.Eeveeko:BAACLgAFFH8LAAIbAAQJzA/aBQAuAQAbAAQJzA/aBQAuAQAuAAQKfzYAAhsACQlYHv8EAG8CABsACQlYHv8EAG8CAAAA.',
Ej='Ejavuday:BAABLgAECn8jAAIDAAkJ1CEpHwCIAgADAAkJ1CEpHwCIAgAAAA==.',
El='Elvudu:BAAALgAECgQJBwAAAA==.',
Em='Emberstrife:BAAALgAECgEJAgAAAA==.',
En='Enerchi:BAAALgAFFAEJAQAAAA==.',
Er='Erazath:BAAALgAECgQJCAAAAA==.Erianar:BAAALgAECgIJAgAAAA==.Ericdruid:BAABLgAECn8aAAMRAAcJSiD3EgB+AgARAAcJSiD3EgB+AgANAAEJ6QqZ1gAqAAAAAA==.Ericlock:BAAALgADCgMJAwAAAA==.',
Es='Essia:BAAALgAECgEJAQAAAA==.',
Ev='Eveko:BAAALgADCgIJAQAAAA==.Evera:BAABLgAECn8uAAIHAAkJ6gRwigAqAQAHAAkJ6gRwigAqAQAAAA==.Everlst:BAAALgADCgEJAQAAAA==.Evokinpants:BAAALgAECgcJDwAAAA==.Evos:BAAALgAECgQJBgAAAA==.',
Ex='Excels:BAACLgAFFH8IAAINAAMJoBlGKwDpAAANAAMJoBlGKwDpAAAuAAQKfxkAAg0ACQkBIDYGADwDAA0ACQkBIDYGADwDAAAA.Explicatory:BAAALgAECgYJBgABLgAFFAMJCAANAKAZAA==.',
Ey='Eyllion:BAAALgAECgQJBQAAAA==.',
Fa='Falorin:BAAALgADCgMJAwAAAA==.Fastoris:BAAALgADCgEJAQAAAA==.Fauci:BAACLgAFFH8IAAIHAAUJOw2nhQDIAAAHAAUJOw2nhQDIAAAuAAQKfx4AAgcACAk4IW8YAJICAAcACAk4IW8YAJICAAAA.',
Fb='Fblthelost:BAAALgAECgMJAwAAAA==.',
Fe='Feihao:BAAALgADCggJFQAAAA==.Feile:BAABLgAECn82AAQIAAkJxhe3KQAbAgAIAAkJxhe3KQAbAgAcAAIJfgu/VwBnAAAdAAEJAAD1LwA+AAAAAA==.Fenty:BAAALgAECgUJBQABLgAECggJLwAUAAcYAA==.Feshh:BAAALgADCgEJAQAAAA==.',
Fi='Fifezilla:BAAALgAECgIJAgAAAA==.Firble:BAAALgADCgYJBgAAAA==.Fireg:BAEALgADCgEJAQABLgAFFAQJBQADADULAA==.Fistbeaver:BAAALgADCgUJBQAAAA==.',
Fl='Flinzza:BAAALgAECgUJBQAAAA==.',
Fo='Foolezz:BAAALgAECgMJBAAAAA==.',
Fr='Fredthedh:BAABLgAECn8cAAIUAAkJZSFUFADeAgAUAAkJZSFUFADeAgAAAA==.Fromtheback:BAAALgAECgUJCgAAAA==.',
Fu='Furble:BAAALgADCgYJBgAAAA==.',
Ga='Gaashw:BAAALgAECgIJBgAAAA==.Gadziila:BAAALgADCgEJAQAAAA==.Galcyon:BAAALgADCgEJAQAAAA==.Galiant:BAABLgAECn8mAAIHAAkJ/SObEADIAgAHAAkJ/SObEADIAgAAAA==.Gashdk:BAAALgAECgEJAQABLgAECgIJBgAEAAAAAA==.Gator:BAAALgAECgEJAQAAAA==.Gaulish:BAAALgADCgkJCQAAAA==.',
Ge='Geraldo:BAAALgADCgcJBwAAAA==.Gethalyn:BAABLgAECn8WAAIFAAcJAREJegBaAQAFAAcJAREJegBaAQAAAA==.Gexz:BAAALgADCgYJDAAAAA==.',
Gh='Ghee:BAAALgAECgEJAgAAAA==.',
Gi='Gianthippo:BAAALgAECgYJBgAAAA==.',
Gl='Glaivedaddy:BAAALgAECgEJAQAAAA==.Glenlives:BAAALgADCgkJCQABLgAECggJIAASABYMAA==.',
Go='Gore:BAAALgAECgUJBQAAAA==.Gottverdammt:BAAALgAECgEJAQABLgAECgkJEAAEAAAAAA==.',
Gr='Graveknight:BAAALgAECgMJAwAAAA==.Graveshot:BAAALgADCgQJBAAAAA==.Greennrry:BAAALgAFFAEJAQABLgAFFAMJBwAeADwYAA==.Greenryy:BAAALgAECgIJAwABLgAFFAMJBwAeADwYAA==.Greyskin:BAAALgADCgEJAQAAAA==.Grizzabella:BAABLgAECn8rAAINAAkJ9RvfDADXAgANAAkJ9RvfDADXAgAAAA==.Grreenry:BAABLgAFFH8HAAIeAAMJPBjbBwADAQAeAAMJPBjbBwADAQABLgAFFAMJBwAeADwYAA==.Grriz:BAAALgADCgEJAQAAAA==.Grtmustachio:BAAALgAECgkJEAAAAA==.Grundle:BAAALgAECgMJAwAAAA==.',
Gu='Gularak:BAAALgAECgQJBgAAAA==.Gunghø:BAAALgADCggJDwAAAA==.',
Gy='Gyutaro:BAAALgADCgEJAQAAAA==.',
Ha='Haelellionys:BAAALgADCgQJBAAAAA==.Hanamae:BAAALgADCgEJAQAAAA==.Hangnail:BAAALgAECgIJBAAAAA==.Hanswoloqued:BAABLgAECn8bAAMIAAkJqAu2WwB1AQAIAAkJqAu2WwB1AQAdAAIJpgENKgBLAAAAAA==.Harmfuljoker:BAAALgADCgQJBAAAAA==.Haxzen:BAAALgADCgMJBAAAAA==.',
He='Healufast:BAABLgAECn8qAAIMAAkJORtNDwBMAgAMAAkJORtNDwBMAgAAAA==.Hellsong:BAAALgAECgMJAwABLgAECgYJBgAEAAAAAA==.Hendo:BAAALgADCgYJBgAAAA==.Heysisters:BAAALgADCgYJBwAAAA==.',
Hi='Hispeas:BAAALgADCgQJBwAAAA==.Hitchkawk:BAAALgAECgEJAQAAAA==.Hitchlock:BAAALgAECgEJAwAAAA==.',
Ho='Holysabeline:BAABLgAECn9IAAIGAAkJaRpiDwB8AgAGAAkJaRpiDwB8AgAAAA==.Honestleon:BAAALgADCgMJAwABLgAECgcJFgAFAHgTAA==.Hordechief:BAAALgAFFAIJAgAAAA==.',
Hu='Huchar:BAABLgAECn82AAMZAAkJBR8HBQCuAgAZAAkJBR8HBQCuAgAfAAEJmgy2iwAxAAAAAA==.Huevos:BAAALgAECgIJAgAAAA==.Huntersteve:BAABLgAECn8hAAMgAAgJQCOoCAAIAwAgAAgJQCOoCAAIAwALAAYJ7CAfIwANAgAAAA==.',
Hy='Hydraxix:BAAALgAECgYJCwAAAA==.',
['Hô']='Hônk:BAAALgADCgEJAQABLgAECggJIAASABYMAA==.',
Ia='Iamanopcow:BAAALgADCgQJBAAAAA==.Iamspeed:BAAALgADCgQJBAAAAA==.',
Ic='Iceblade:BAABLgAECn8oAAIGAAkJxxf2HwAaAgAGAAkJxxf2HwAaAgAAAA==.',
If='If:BAAALgAECgMJAwAAAA==.',
Ih='Ihideuseek:BAAALgAECgYJBgABLgAECgkJIwADANQhAA==.',
Ii='Iityouup:BAAALgADCgYJCAAAAA==.',
Il='Illidaniella:BAABLgAECn8TAAIUAAYJ2wbbmwC/AAAUAAYJ2wbbmwC/AAAAAA==.Illsmurfuup:BAABLgAECn8ZAAIYAAkJ9SZoAACnAwAYAAkJ9SZoAACnAwAAAA==.',
In='Infection:BAAALgADCgYJCAAAAA==.Inverse:BAAALgADCgYJBgAAAA==.',
Ir='Ironßest:BAAALgAECgcJCQAAAA==.Irôh:BAAALgAECgEJAQABLgAECgUJDgAEAAAAAA==.',
Is='Ishmael:BAAALgADCgEJAQAAAA==.',
Iv='Ivannas:BAAALgAECgEJAgAAAA==.',
Ja='Jaabroni:BAAALgADCgIJAgAAAA==.Jackymoon:BAABLgAECn8aAAIFAAgJXCM2FgCgAgAFAAgJXCM2FgCgAgAAAA==.Jaxxion:BAAALgADCgMJBQAAAA==.',
Jd='Jdawg:BAABLgAECn8/AAIbAAkJQiWUAABMAwAbAAkJQiWUAABMAwAAAA==.',
Je='Jessaiyan:BAABLgAECn8sAAIUAAkJKyJrBgAPAwAUAAkJKyJrBgAPAwAAAA==.',
Ji='Jindo:BAAALgADCgcJBwAAAA==.Jiuni:BAAALgADCgUJBQAAAA==.',
Jj='Jjcjr:BAAALgAFFAIJAgABLgAFFAYJGQAhAB4hAA==.',
Ju='Julaudette:BAAALgAECgYJEgAAAA==.Julzaria:BAABLgAECn8bAAIgAAcJVw2BZABOAQAgAAcJVw2BZABOAQAAAA==.Julzoblin:BAAALgAECgYJDAAAAA==.Jurny:BAABLgAECn8UAAMcAAgJtgpqFgDOAAAcAAUJkApqFgDOAAAdAAUJ2gqTFwDLAAAAAA==.Jusdeen:BAABLgAECn8YAAMOAAkJtiKnBACcAgAOAAgJGSKnBACcAgANAAMJvA8YigCAAAAAAA==.',
Ka='Kadookieii:BAAALgAFFAEJAQAAAA==.Kahlandra:BAABLgAECn83AAMiAAkJChvgAQBAAgAiAAkJChvgAQBAAgADAAgJ9QxmegBmAQAAAA==.Kairoz:BAAALgAECgYJCwABLgAFFAEJAQAEAAAAAA==.Kaizer:BAACLgAFFH8KAAISAAQJVw8qHQAMAQASAAQJVw8qHQAMAQAuAAQKfyUAAhIACAmwGt4YAE0CABIACAmwGt4YAE0CAAAA.Kalo:BAAALgAECgMJAwAAAA==.Kanrethad:BAAALgAECgQJBAABLgAECggJKAAKAAgbAA==.Karina:BAABLgAECn9HAAMUAAkJoCGDCwDSAgAUAAkJbCCDCwDSAgAWAAkJzxaxBQAdAgAAAA==.Kastravia:BAAALgAFFAEJAgABLgAFFAQJEgAQAG4GAA==.Kawolski:BAAALgAFFAMJAwABLgAFFAQJEgAQAG4GAA==.',
Ke='Kelitarra:BAAALgADCgQJCAAAAA==.Kellibar:BAAALgAECgcJBwAAAA==.Kevin:BAAALgAECgcJCgAAAA==.',
Kh='Khanjuror:BAABLgAECn8tAAIcAAgJ1xRXCACaAQAcAAgJ1xRXCACaAQAAAA==.Kholonoe:BAABLgAECn8cAAIjAAkJmRS6GQDTAQAjAAkJmRS6GQDTAQAAAA==.Khornedog:BAABLgAECn8mAAIIAAcJihaOUACSAQAIAAcJihaOUACSAQAAAA==.Khrama:BAAALgAECgkJEAAAAA==.',
Ki='Kiimachamara:BAAALgADCgIJAwAAAA==.Killik:BAAALgAECgQJBAAAAA==.Kinz:BAAALgAECgMJAwABLgABCgkJEgAEAAAAAA==.Kippili:BAAALgADCgQJBAABLgAECgYJCgAEAAAAAA==.Kiritokun:BAAALgADCgYJBAAAAA==.',
Kl='Klapz:BAAALgADCgcJDQABLgAECggJDQAEAAAAAA==.Kleenonean:BAACLgAFFH8OAAIjAAQJ6ySkBgC0AQAjAAQJ6ySkBgC0AQAuAAQKf0oAAyMACQkBJhMBAGsDACMACQkBJhMBAGsDAAwAAgnGBlV0AFcAAAAA.',
Kp='Kpyassan:BAAALgAECgYJBQAAAA==.',
Kr='Kravenn:BAAALgAECgMJAwAAAA==.Kreuzritter:BAABLgAECn8zAAIYAAkJORDDCABcAgAYAAkJORDDCABcAgAAAA==.Kritterbug:BAAALgAECggJCAAAAA==.',
Ku='Kungcarefu:BAABLgAECn8bAAICAAYJQxJqPADrAAACAAYJQxJqPADrAAAAAA==.Kungfushnaz:BAAALgAECgEJAQAAAA==.Kurzaan:BAAALgAECgcJAgAAAA==.Kurzak:BAAALgAECgQJBwAAAA==.',
Ky='Kyle:BAAALgAECgEJAQABLgAFFAIJAgAEAAAAAA==.',
La='Laciel:BAAALgAECgMJBAABLgAECgkJFAAKAJEbAA==.Lacio:BAABLgAECn9HAAIjAAkJLwpsIwCFAQAjAAkJLwpsIwCFAQAAAA==.Larune:BAAALgADCgQJBwAAAA==.Lavendàh:BAABLgAECn8oAAIGAAkJuCC7AwBGAwAGAAkJuCC7AwBGAwAAAA==.',
Le='Lemonite:BAACLgAFFH8FAAINAAMJsAxHNQC9AAANAAMJsAxHNQC9AAAuAAQKfxYAAg0ACQlwG+QUAI4CAA0ACQlwG+QUAI4CAAAA.Lennykoggins:BAABLgAECn8YAAIgAAgJLBfzOQDMAQAgAAgJLBfzOQDMAQAAAA==.Leyru:BAABLgAECn8sAAIGAAgJISQ6BAA2AwAGAAgJISQ6BAA2AwAAAA==.',
Li='Liberos:BAABLgAECn8XAAIJAAgJ0RQfLADaAQAJAAgJ0RQfLADaAQAAAA==.Lifenight:BAABLgAECn8kAAMkAAkJ6ByVAwBqAgAkAAkJ6ByVAwBqAgAHAAEJvwAGPwEJAAAAAA==.Lilnim:BAAALgAECgUJBQAAAA==.Lithvia:BAAALgAECgYJDQAAAA==.',
Ln='Lninedkhack:BAABLgAECn8lAAMHAAgJZhoPPQDrAQAHAAgJZhoPPQDrAQAKAAgJMQcCKQDeAAAAAA==.',
Lo='Lockdor:BAAALgAECgQJBAAAAA==.Logaar:BAABLgAECn8qAAMGAAkJwBVaEgBbAgAGAAkJwBVaEgBbAgAFAAEJ7gF/gQEgAAAAAA==.Loretharan:BAAALgAECgEJAQAAAA==.Louvuitton:BAAALgADCgcJDgAAAA==.',
Lu='Lunartsy:BAAALgADCggJDgAAAA==.Lustiel:BAAALgAECgYJDAAAAA==.Luticris:BAAALgAECgMJBAAAAA==.',
Ly='Lyoric:BAAALgAECgEJAQAAAA==.',
Ma='Madmax:BAAALgADCggJCAAAAA==.Maegot:BAAALgADCgYJBgAAAA==.Magicpants:BAAALgAECgcJCgAAAA==.Magnetto:BAAALgADCgQJBAAAAA==.Maiden:BAAALgADCgUJCAABLgAECggJKAAKAAgbAA==.Malexannius:BAAALgADCgUJCQAAAA==.Mannirot:BAAALgAECgEJAQAAAA==.Mariangel:BAAALgAECgUJBgAAAA==.Marrygold:BAAALgAECgEJAgABLgAECgkJIAAHAHYfAA==.Mateus:BAAALgAECgEJBAAAAA==.Maxdeath:BAABLgAECn8lAAIHAAgJ9iO/DQAtAwAHAAgJ9iO/DQAtAwAAAA==.Mazre:BAAALgAECgQJBwAAAA==.',
Me='Megtallica:BAAALgAECgUJBgAAAA==.Mensrea:BAABLgAECn8eAAMJAAYJFhNoTABKAQAJAAYJFhNoTABKAQASAAQJsAxVagCaAAAAAA==.Merlinn:BAAALgADCgMJBgAAAA==.Merrycold:BAABLgAECn8gAAMHAAkJdh9FPABGAgAHAAcJpSFFPABGAgAKAAUJ3RNCLgC8AAAAAA==.Merrygold:BAAALgADCgMJAwABLgAECgkJIAAHAHYfAA==.Merrygored:BAAALgAECgIJAgABLgAECgkJIAAHAHYfAA==.Mess:BAABLgAECn8nAAQZAAcJ2BhnEgCbAQAZAAcJ2BhnEgCbAQAfAAIJ3gfTlABsAAAaAAMJPQgXRwApAAABLgAECggJKAAKAAgbAA==.Methodical:BAAALgADCgUJBQAAAA==.Metophis:BAAALgAECgYJCgAAAA==.',
Mf='Mfboomstick:BAABLgAECn8/AAMYAAkJNCaWAABrAwAYAAkJNCaWAABrAwALAAEJlSU2JgBkAAAAAA==.',
Mi='Mikklelee:BAAALgADCgIJAgAAAA==.Missdebby:BAAALgADCgYJCwAAAA==.Mistweaver:BAABLgAECn8bAAIQAAkJrB/WBAA1AwAQAAkJrB/WBAA1AwAAAA==.Mistweaving:BAAALgAECgcJAwAAAA==.Mizirath:BAAALgAECgQJBAABLgAECggJMgAOAKofAA==.Miztakswrmde:BAAALgADCgUJBgAAAA==.',
Mo='Moghorva:BAABLgAECn8cAAIlAAkJzBiABwBfAgAlAAkJzBiABwBfAgAAAA==.Mojoe:BAAALgAECgQJDAAAAA==.Mommyswaggin:BAAALgAECgkJEwAAAA==.Moonra:BAAALgAECgEJAQAAAA==.Moopocalypse:BAAALgADCgcJDAABLgAECgkJNQAMAOkkAA==.Moopsta:BAAALgADCggJDgABLgAECgkJNQAMAOkkAA==.Moopster:BAABLgAECn81AAMMAAkJ6SQ+AQCcAwAMAAkJ6SQ+AQCcAwABAAYJ3xl9GwDFAQAAAA==.Mordekaiserz:BAAALgAECgUJCwAAAA==.Morrgoth:BAAALgADCgEJAQAAAA==.',
Mu='Mucouslurp:BAAALgADCgEJAQAAAA==.',
Na='Nalahni:BAACLgAFFH8LAAIhAAQJXAxsJwAAAQAhAAQJXAxsJwAAAQAuAAQKfyIAAiEACQmHGDsSAC8CACEACQmHGDsSAC8CAAAA.Nanashi:BAAALgAECgMJAwAAAA==.Nastage:BAAALgADCgMJAQAAAA==.Nastus:BAAALgAECgMJAwAAAA==.Nayela:BAAALgAECgYJEAAAAA==.Nazgru:BAAALgADCgcJBgAAAA==.',
Ne='Neptuneakis:BAABLgAECn8UAAIRAAgJ0hAGIgCMAQARAAgJ0hAGIgCMAQAAAA==.Nerfblaster:BAAALgADCgEJAQAAAA==.Newcarsmell:BAAALgAECgYJCQAAAA==.',
Ni='Nicktee:BAAALgAECgUJCQAAAA==.Nightmares:BAAALgAECgcJCgAAAA==.Nightrvn:BAAALgAECgQJBAAAAA==.Nimrose:BAAALgAECggJDwAAAA==.Niquid:BAABLgAECn8nAAINAAgJtxVaKgDhAQANAAgJtxVaKgDhAQAAAA==.',
No='Nolmac:BAABLgAECn8bAAIJAAgJaiIbCwDeAgAJAAgJaiIbCwDeAgAAAA==.Notahealer:BAAALgAFFAEJAQAAAA==.Noxloxes:BAAALgADCgcJDAAAAA==.',
Np='Npv:BAABLgAFFH8HAAIHAAIJgQ3rpwCSAAAHAAIJgQ3rpwCSAAAAAA==.',
Ny='Nyssavia:BAAALgADCgcJDgAAAA==.',
Oa='Oakshre:BAABLgAECn80AAIPAAkJnSD0BADkAgAPAAkJnSD0BADkAgAAAA==.',
Ob='Obliteration:BAAALgAECgYJBgABLgAFFAEJAQAEAAAAAA==.',
Ol='Olivertwist:BAAALgAECgQJDgABLgAFFAEJAQAEAAAAAA==.',
Om='Omnimpotent:BAAALgAECgEJAQABLgAECgIJBQAEAAAAAA==.',
On='Ontwarr:BAAALgADCgkJEAAAAA==.Ontwou:BAAALgAECggJDwAAAA==.',
Op='Ophi:BAAALgAECgYJEQAAAA==.',
Os='Oshaku:BAAALgAECgcJCwAAAQ==.',
Ou='Ouchpotato:BAAALgAECggJDgABLgAFFAMJCAAXAG8VAA==.',
Pa='Paarthurnax:BAAALgAECgUJBQAAAA==.Palathal:BAAALgAECgUJBgABLgAECggJGQADAPoTAA==.Pallynim:BAAALgADCgQJBwAAAA==.Palms:BAACLgAFFH8FAAIPAAMJKxulFAD3AAAPAAMJKxulFAD3AAAuAAQKfxgAAg8ACQlDIpgHAAIDAA8ACQlDIpgHAAIDAAAA.Pancakezebra:BAABLgAECn8yAAIYAAkJ6RoIDQA6AgAYAAkJ6RoIDQA6AgAAAA==.Pantsftw:BAABLgAECn8fAAMMAAgJQwxHKwBKAQAMAAgJ1QtHKwBKAQABAAEJQQUkZAAxAAAAAA==.Papabear:BAAALgADCgUJBQAAAA==.Parkbreezy:BAABLgAECn8bAAIOAAcJBwotMACjAAAOAAcJBwotMACjAAAAAA==.Pawg:BAAALgADCgcJBgAAAA==.',
Pe='Pebbles:BAAALgAECgcJBwAAAA==.Peltier:BAABLgAECn8sAAIDAAkJdCD2HACUAgADAAkJdCD2HACUAgAAAA==.Pendle:BAABLgAECn8lAAMcAAcJBA7DKQAbAQAIAAcJVQ0KcwA+AQAcAAYJHQvDKQAbAQAAAA==.',
Ph='Phoenix:BAABLgAECn8lAAIFAAkJjB4SHgBzAgAFAAkJjB4SHgBzAgAAAA==.',
Pl='Plox:BAAALgAECgYJEwAAAA==.Plurnizz:BAABLgAECn8dAAMIAAkJHQgzdQA5AQAIAAkJHQgzdQA5AQAcAAQJEwHKXwBPAAAAAA==.',
Po='Pocketchange:BAACLgAFFH8MAAIJAAQJwBjVHgA2AQAJAAQJwBjVHgA2AQAuAAQKfxQAAxIACAmWHXEqAMIBABIABgnWHHEqAMIBAAkABQl6GTJLAFYBAAAA.',
Pu='Puffadin:BAAALgADCgEJAQAAAA==.Puppymoke:BAAALgAECgMJAwAAAA==.Puptart:BAAALgAECgUJBQAAAA==.',
Ra='Raest:BAABLgAECn8hAAICAAgJDyOqBgCxAgACAAgJDyOqBgCxAgABLgAECgkJEAAEAAAAAA==.Raiker:BAAALgAECgMJBAAAAA==.Razzlock:BAAALgAECgEJAQAAAA==.',
Re='Regret:BAAALgAECggJDwAAAA==.Relovan:BAABLgAECn8sAAMaAAkJmBDrEQCuAQAaAAkJmBDrEQCuAQAfAAUJSwOYhgClAAAAAA==.Renothidan:BAACLgAFFH8FAAIFAAMJrxTPRwDyAAAFAAMJrxTPRwDyAAAuAAQKfyEAAgUACQlpG3AwAB0CAAUACQlpG3AwAB0CAAAA.Reuben:BAAALgADCggJEQAAAA==.Revin:BAAALgADCgYJBgAAAA==.Revrynth:BAAALgAECggJEAABLgAECggJKQAZAPUiAA==.Rexorcist:BAAALgADCgYJCwAAAA==.',
Ri='Rickyboby:BAAALgAECggJDAAAAA==.Righteøus:BAAALgAECgUJDwAAAA==.Rillan:BAABLgAECn8aAAIFAAYJ8xYMgQBMAQAFAAYJ8xYMgQBMAQAAAA==.Rin:BAAALgAECgkJCQABLgAECgkJPwAIAEklAA==.Ripper:BAAALgAECgUJCQAAAA==.Rithcice:BAABLgAECn84AAMfAAkJtCZcAACLAwAfAAkJqSZcAACLAwAZAAcJ/yPIBgB5AgAAAA==.Rizzdolphler:BAACLgAFFH8LAAIFAAMJswzQUADhAAAFAAMJswzQUADhAAAuAAQKfycAAwUACAmyHSIoAEACAAUACAmyHSIoAEACAAYABgktEZI5ADsBAAAA.',
Ro='Roadnurse:BAAALgADCgIJAgAAAA==.Rockntroll:BAAALgADCgIJAgAAAA==.Rodah:BAAALgADCgkJEAAAAA==.Roscoee:BAAALgADCgEJAQAAAA==.',
Rs='Rsk:BAAALgADCgYJCQABLgAECggJKAAKAAgbAA==.',
Ru='Ruins:BAAALgAECgEJAQAAAA==.',
['Rà']='Ràrity:BAAALgADCggJCAAAAA==.',
['Rö']='Rönburgundy:BAABLgAECn8uAAIIAAkJjR4wFwCBAgAIAAkJjR4wFwCBAgAAAA==.',
Sa='Sanako:BAABLgAECn8oAAIRAAkJxxHiGADYAQARAAkJxxHiGADYAQAAAA==.Sanastusa:BAAALgADCgYJCAAAAA==.Saneros:BAAALgAECggJCQABLgAECggJLwAUAAcYAA==.Santoniche:BAAALgAECgUJBAAAAA==.Sap:BAABLgAECn8cAAMXAAcJ0BXpGwCOAQAXAAcJ0BXpGwCOAQAmAAQJQgsSEwDRAAABLgAECggJKAAKAAgbAA==.Sausiege:BAAALgAECgMJAwAAAA==.Saveserenade:BAAALgAECgUJBQAAAA==.',
Sc='Scarylarry:BAABLgAECn8vAAIUAAgJBxiLQgCeAQAUAAgJBxiLQgCeAQAAAA==.Scyther:BAACLgAFFH8GAAMnAAMJrwpcFwCPAAAnAAIJuQ1cFwCPAAAUAAIJRwPVbgBxAAAuAAQKfxcAAxQACQlfDstxAE8BABQACAk9DMtxAE8BACcABgnuD5pKAMYAAAAA.',
Sd='Sdh:BAAALgADCgQJBgAAAA==.',
Se='Seishinokami:BAABLgAECn8gAAISAAgJFgzKMQBIAQASAAgJFgzKMQBIAQAAAA==.Senala:BAAALgAECgEJAQAAAA==.Serenade:BAACLgAFFH8KAAIDAAQJqBFNTwAqAQADAAQJqBFNTwAqAQAuAAQKfyQAAgMACAmuHxYzAKYCAAMACAmuHxYzAKYCAAAA.Setheron:BAABLgAECn8gAAIfAAgJvBxgEgA+AgAfAAgJvBxgEgA+AgAAAA==.Sethron:BAAALgAECgIJAgAAAA==.Señsei:BAAALgAECggJCwAAAA==.',
Sh='Shamminit:BAAALgAECgIJAgAAAA==.Shamtul:BAAALgAECgEJAwAAAA==.Shamwow:BAAALgADCgcJDgAAAA==.Shlea:BAACLgAFFH8GAAIhAAMJmgctNwC2AAAhAAMJmgctNwC2AAAuAAQKfxwAAiEACQnGD+8jAJoBACEACQnGD+8jAJoBAAAA.Shyva:BAABLgAECn8pAAMZAAgJ9SIxBwC4AgAZAAgJ9SIxBwC4AgAfAAUJ9xf7RAAIAQAAAA==.',
Si='Siinestro:BAAALgAECgQJBAAAAA==.Sinlee:BAAALgAECgcJDgABLgAECgkJOgAIAEMiAA==.',
Sl='Slayla:BAAALgAECgQJBwAAAA==.Slimboyjoe:BAAALgADCgcJDgAAAA==.Slimmjim:BAAALgADCgEJAQAAAA==.Slinkstir:BAAALgADCgQJAwAAAA==.',
Sn='Snailtrails:BAAALgAECgcJBwAAAA==.Sneak:BAAALgADCgMJAwABLgAECgYJCwAEAAAAAA==.Sneakcookies:BAAALgAECgMJBwABLgAFFAEJAQAEAAAAAA==.',
So='Soggyundies:BAAALgAECgQJBAAAAA==.Solendros:BAAALgAECgYJDwAAAA==.Sonthar:BAAALgAECgYJBgAAAA==.Soulborn:BAAALgADCgMJAwAAAA==.Soulelf:BAAALgADCgYJBgAAAA==.',
Sp='Spacehog:BAAALgAECgYJDAAAAA==.Sparticus:BAAALgAECgEJAQAAAA==.Spiro:BAAALgAECgEJAQABLgAECgkJJwAnAD0ZAA==.Splouge:BAAALgAECgYJBgAAAA==.',
St='Standarshh:BAABLgAECn83AAIgAAkJ9SBfCQDsAgAgAAkJ9SBfCQDsAgAAAA==.Stemmz:BAAALgADCgEJAQAAAA==.Stronghand:BAAALgADCgYJBwAAAA==.',
Su='Subtle:BAACLgAFFH8IAAIXAAMJbxV6HQD1AAAXAAMJbxV6HQD1AAAuAAQKfyYAAxcACAmLHywNAMcCABcACAmLHywNAMcCACgABQmpBjMVAIgAAAAA.Sugarbabi:BAABLgAECn8hAAMNAAkJDR8uIQA7AgANAAcJ3x4uIQA7AgARAAYJRRj2HwCbAQAAAA==.Sugarrush:BAAALgADCgUJBQAAAA==.Sugarshot:BAAALgAECggJCAAAAA==.Sugarthorn:BAAALgADCgkJCQAAAA==.Sulcer:BAAALgADCgMJBAAAAA==.',
Sy='Sylria:BAAALgAECgIJAgAAAA==.Sylrianah:BAABLgAECn9IAAQMAAkJ0CASBQAOAwAMAAkJ0CASBQAOAwAjAAkJ4QgrJACAAQABAAQJrgjnRQCvAAAAAA==.Sylveste:BAACLgAFFH8NAAIGAAUJ8SI6CADsAQAGAAUJ8SI6CADsAQAuAAQKfyMAAgYABwkUGv8pAJgBAAYABwkUGv8pAJgBAAAA.Sylvfelster:BAAALgAECgYJBwAAAA==.Sylánnia:BAAALgADCgcJBwAAAA==.',
Ta='Ta:BAABLgAECn8aAAIBAAcJpAhNLQA/AQABAAcJpAhNLQA/AQAAAA==.Talis:BAAALgADCgYJCgAAAA==.Tankhiskhan:BAABLgAECn8VAAIKAAgJQA1DJgDzAAAKAAgJQA1DJgDzAAAAAA==.Tarlis:BAABLgAECn8YAAIdAAgJ9xq8BAAqAgAdAAgJ9xq8BAAqAgAAAA==.',
Te='Tedrickeyjr:BAAALgAECgEJBgAAAA==.Terithresh:BAAALgADCgMJBAAAAA==.',
Th='Thanil:BAABLgAECn8iAAIFAAcJIBf6ZgCBAQAFAAcJIBf6ZgCBAQAAAA==.Thenet:BAAALgAECgEJAQAAAA==.',
Ti='Tie:BAAALgADCgcJBwAAAA==.Tikamancer:BAAALgADCgEJAQAAAA==.Tilvalhalla:BAABLgAECn8cAAIlAAcJPAogKgAhAQAlAAcJPAogKgAhAQAAAA==.',
To='Todorokii:BAAALgAECgUJDQAAAA==.Tom:BAAALgAECgEJAgABLgAFFAIJAgAEAAAAAA==.Torrin:BAAALgADCgYJBwAAAA==.Tortricid:BAAALgAECgMJBgAAAA==.Totempants:BAAALgAECgYJBgAAAA==.Totinospizza:BAAALgADCgYJBgAAAA==.',
Tr='Trashkan:BAAALgADCgIJAgAAAA==.Trauck:BAAALgADCgEJAQAAAA==.Traumzi:BAAALgAECgEJAQAAAA==.Travvy:BAACLgAFFH8kAAMXAAgJKCJOAQD+AQAXAAcJZyFOAQD+AQAmAAIJoR6ZCQBwAAAuAAQKfyIAAhcACQkWJgEBAMMDABcACQkWJgEBAMMDAAAA.Treezus:BAAALgADCgYJCAAAAA==.Trevmo:BAABLgAECn82AAIZAAkJGyBWBADDAgAZAAkJGyBWBADDAgAAAA==.',
Tu='Turaylon:BAAALgAFFAEJAQAAAA==.Turtlebox:BAAALgAECgQJBgAAAA==.',
Ty='Tym:BAAALgAFFAIJAgAAAA==.',
Ug='Ugargro:BAAALgAECgQJBgAAAA==.',
Un='Unapologetic:BAAALgAECggJDAAAAA==.Unbreakabull:BAAALgAFFAMJAwAAAA==.Unceejin:BAAALgADCggJEQAAAA==.Unholydk:BAABLgAECn8oAAMKAAgJCBsADAAfAgAKAAgJCBsADAAfAgAHAAUJsw9twQDQAAAAAA==.',
Va='Valcuna:BAAALgAECgEJAgAAAA==.Valka:BAABLgAECn8XAAIeAAgJ3QjdFgAlAQAeAAgJ3QjdFgAlAQAAAA==.Vamptouch:BAAALgAECgIJAwABLgAECgYJCwAEAAAAAA==.Vanaan:BAAALgAECgIJAgABLgAECgYJBwAEAAAAAA==.Varidrus:BAAALgAECgMJAwAAAA==.Vaste:BAAALgADCgcJCQAAAA==.',
Ve='Ventrue:BAABLgAECn8jAAIDAAkJ6xWZTgDTAQADAAkJ6xWZTgDTAQAAAA==.Veyle:BAABLgAECn8/AAMXAAkJ1yRwAwD1AgAXAAkJ1yRwAwD1AgAmAAEJKh7AGwBJAAAAAA==.',
Vi='Vivian:BAABLgAECn8nAAInAAkJPRldCQBmAgAnAAkJPRldCQBmAgAAAA==.',
Vo='Voidsurge:BAABLgAECn8aAAQUAAUJAROdmADFAAAUAAUJyQ+dmADFAAAWAAMJsRLLIABmAAAnAAEJMhMSVAA3AAABLgAECggJKAAKAAgbAA==.',
Vy='Vyndria:BAAALgAECgQJDAAAAA==.',
We='Weaspore:BAABLgAECn8gAAIHAAgJlR7+NAAHAgAHAAgJlR7+NAAHAgAAAA==.Weasy:BAAALgAECgkJDgAAAA==.',
Wo='Woogidaboogi:BAAALgAECgIJBQAAAA==.Woogieboogie:BAAALgAECgEJAQABLgAECgIJBQAEAAAAAA==.',
Xi='Xiamiel:BAAALgADCgYJCQAAAA==.',
Xl='Xl:BAABLgAECn9WAAMnAAgJ/RxVCwCrAgAnAAgJhxxVCwCrAgAUAAgJJxZCOQDAAQAAAA==.',
Ya='Yaitoopmfp:BAAALgAECgEJAQABLgAECgkJIAAHAHYfAA==.',
Yh='Yharnem:BAABLgAECn8XAAICAAcJ8hAYKABRAQACAAcJ8hAYKABRAQAAAA==.',
Yo='Yogurtpants:BAAALgAECgYJEgAAAA==.Yonny:BAAALgADCgEJAQAAAA==.',
Yu='Yukionna:BAAALgADCgcJCwAAAA==.',
Za='Zabara:BAABLgAECn8VAAIJAAgJgSHTFgBmAgAJAAgJgSHTFgBmAgAAAA==.Zabbystabby:BAAALgADCgkJDgAAAA==.Zakaraki:BAABLgAECn8+AAQpAAkJhCVsAABMAwApAAkJhCVsAABMAwAhAAcJNyHRFAAUAgAlAAcJTAd5JgBBAQAAAA==.Zaki:BAABLgAECn8aAAIUAAkJThr+GwBPAgAUAAkJThr+GwBPAgAAAA==.Zanked:BAAALgADCgQJBAAAAA==.Zarkingu:BAAALgADCgMJAwAAAA==.',
Ze='Zealot:BAAALgAFFAEJAQAAAA==.Zeleria:BAAALgAECgUJBgAAAA==.Zeno:BAAALgAFFAIJAgAAAA==.Zephyr:BAAALgAECgQJBAAAAA==.Zerathis:BAABLgAECn86AAIIAAkJQyKcCgDlAgAIAAkJQyKcCgDlAgAAAA==.Zerathül:BAAALgAECgcJEgAAAA==.Zerötwo:BAAALgADCgkJCgAAAA==.Zestul:BAAALgADCgkJFgAAAA==.',
Zi='Zimbobayaga:BAAALgAECgMJAwAAAA==.',
Zo='Zodivine:BAAALgADCgMJAwAAAA==.Zohar:BAAALgADCgEJAgAAAA==.Zooty:BAAALgADCgUJAwAAAA==.Zoshow:BAAALgAECgMJBAAAAA==.',
Zu='Zuggo:BAAALgADCgYJBgAAAA==.',
Zy='Zyrig:BAAALgADCgUJBgAAAA==.',
['Zõ']='Zõshow:BAABLgAECn8XAAMIAAcJmxV5YABpAQAIAAcJeBV5YABpAQAcAAEJEh0zYABOAAAAAA==.',
['Ça']='Çaptainçhaos:BAAALgAECgYJCgAAAA==.',
['Ða']='Ðaredevil:BAABLgAECn8sAAIPAAgJHSCOCQCHAgAPAAgJHSCOCQCHAgABLgAECgkJJwAnAD0ZAA==.',
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
