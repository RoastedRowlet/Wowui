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

local lookup = {'Priest-Discipline','Monk-Brewmaster','Mage-Frost','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Warlock-Demonology','Shaman-Restoration','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Shaman-Elemental','Priest-Holy','Druid-Restoration','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Fire','Rogue-Subtlety','Hunter-Survival','Warrior-Protection','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Hunter-BeastMastery','DemonHunter-Havoc','Evoker-Devastation','Priest-Shadow','Mage-Arcane','DeathKnight-Frost','Evoker-Preservation','Evoker-Augmentation','Rogue-Assassination','Rogue-Outlaw',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aahzbear:BAAALgAFFAEJAQAAAA==.',
Ab='Abreale:BAAALgADCgMJAwAAAA==.Abruum:BAAALgADCgcJBwAAAA==.',
Ae='Aeero:BAABLgAECn8UAAIBAAYJNhfEHwCWAQABAAYJNhfEHwCWAQAAAA==.Aerendyl:BAAALgAECgcJCwAAAA==.',
Ai='Aiden:BAACLgAFFH8HAAICAAMJbRAgOwC6AAACAAMJbRAgOwC6AAAuAAQKfxQAAgIABgkfHF8qALcBAAIABgkfHF8qALcBAAAA.',
Al='Algros:BAAALgADCgEJAQAAAA==.Alternative:BAAALgAECgUJBwAAAA==.Alyiriia:BAAALgAECgkJCQAAAA==.',
Am='Amathal:BAABLgAECn8ZAAIDAAgJ+hMTjABfAQADAAgJ+hMTjABfAQAAAA==.Amazon:BAAALgAECgIJBQAAAA==.Amilea:BAAALgAFFAEJAQABLgABCgkJEwAEAAAAAA==.',
An='Anastasia:BAAALgADCggJCAAAAA==.Angelsevoker:BAAALgAECggJCAAAAA==.Angermoonria:BAAALgADCgcJBwAAAA==.Ankheloios:BAAALgAECgUJBQAAAA==.Antihiiro:BAAALgAECgMJAwAAAA==.Antipro:BAAALgAFFAEJAQAAAA==.Anubbus:BAABLgAFFH8FAAIDAAMJWwP6lACoAAADAAMJWwP6lACoAAAAAA==.Anzulok:BAAALgADCgYJAQAAAA==.',
Ar='Arbalest:BAAALgADCgcJBgAAAA==.Aredhela:BAABLgAECn8hAAMFAAkJlxQVGQA+AgAFAAkJlxQVGQA+AgAGAAQJMRdxuwAPAQAAAA==.Arinth:BAAALgADCggJEQAAAA==.Arkadios:BAAALgAECgIJAgAAAA==.Armpit:BAAALgAECgMJAwAAAA==.',
As='Ascanius:BAAALgAECgEJAQABLgAECgQJBAAEAAAAAA==.Ashiiro:BAAALgAECgcJEAAAAA==.Ashveil:BAAALgAECgUJBQABLgAECgkJJgAHAEEZAA==.Asia:BAABLgAECn8/AAIIAAkJSSW8BQA1AwAIAAkJSSW8BQA1AwAAAA==.Asmodeius:BAAALgAFFAEJAgAAAA==.Astroprof:BAAALgAECgEJAQABLgAECgYJFQAJAFsaAA==.',
At='Athrea:BAABLgAECn8gAAMHAAkJfR5VFQDHAgAHAAkJ3B1VFQDHAgAKAAUJUBu/JQAlAQAAAA==.',
Au='Auntjemima:BAAALgAECgEJAgAAAA==.Aureleus:BAAALgADCgEJAQAAAA==.',
Aw='Away:BAAALgADCgIJAgAAAA==.',
Az='Azaii:BAAALgADCggJCgAAAA==.Azlear:BAAALgAECgkJBgAAAA==.Azrael:BAAALgAECgkJBwAAAA==.',
Ba='Babilouchoux:BAAALgAECgMJBQAAAA==.Ballz:BAAALgADCgYJBgAAAA==.Bano:BAAALgAECgMJAwAAAA==.Barnre:BAAALgAECgYJCQABLgAECgYJDAAEAAAAAA==.Bash:BAABLgAECn8VAAILAAcJ6hMwHQBkAQALAAcJ6hMwHQBkAQABLgAECggJKgAKAAgbAA==.Baythos:BAAALgAFFAEJAgAAAA==.',
Bb='Bb:BAAALgAECgIJAQAAAA==.',
Bd='Bdssm:BAAALgAFFAIJAgAAAA==.',
Be='Beefstick:BAAALgAECgUJBwAAAA==.Berzercarl:BAAALgAECgEJAQAAAA==.Beserkfury:BAABLgAECn8lAAIMAAkJjRCrDgBzAQAMAAkJjRCrDgBzAQAAAA==.',
Bh='Bhemtu:BAAALgAECgEJAQAAAA==.',
Bi='Biercan:BAAALgAECggJEAAAAA==.Bigcarl:BAAALgADCgMJAwAAAA==.Binke:BAABLgAECn8pAAINAAkJ/QwjBAAKAQANAAkJ/QwjBAAKAQAAAA==.Bittywhite:BAAALgAECgcJDAAAAA==.Bittywyvern:BAAALgADCgUJCwABLgAECgcJDAAEAAAAAA==.',
Bk='Bkarakh:BAAALgAECgMJAwAAAA==.',
Bl='Blayze:BAABLgAECn8eAAIOAAkJ5hPQGQD8AQAOAAkJ5hPQGQD8AQAAAA==.Blessidbee:BAAALgAECgEJAQAAAA==.Blightmarx:BAAALgADCgUJCQAAAA==.Blitzwow:BAAALgADCgYJBQAAAA==.Bluemoonflay:BAAALgAECgkJEwAAAA==.Blúnt:BAAALgADCgQJBAAAAA==.',
Bo='Bobheals:BAABLgAECn8vAAMPAAcJsxkNAgCvAQAPAAcJsxkNAgCvAQALAAEJAAB5lQAAAAAAAA==.Boibye:BAAALgAECgYJDgAAAA==.Bolblock:BAAALgAECgkJDwAAAA==.Bonewolf:BAAALgADCgYJCwAAAA==.Boostedww:BAAALgAFFAEJAgAAAA==.Boostie:BAAALgAECgEJAgAAAA==.',
Br='Brambleclaw:BAABLgAECn8/AAIKAAkJRSPFBADjAgAKAAkJRSPFBADjAgAAAA==.Brayker:BAACLgAFFH8GAAIGAAIJLB+QgwCtAAAGAAIJLB+QgwCtAAAuAAQKf0cAAgYACQmjJSAGAEEDAAYACQmjJSAGAEEDAAAA.Breadoneal:BAABLgAECn8pAAMFAAkJ4hkEHwAKAgAFAAgJ9hgEHwAKAgAGAAEJ7QURvwEkAAAAAA==.Breeze:BAAALgAECgYJBgAAAA==.Brewed:BAABLgAECn80AAMQAAkJORRrHADLAQAQAAkJORRrHADLAQARAAEJLwEG4QALAAAAAA==.Brisketbane:BAAALgAECgcJEAAAAA==.Brokenmask:BAACLgAFFH8ZAAIPAAcJWhRUBQB1AQAPAAcJWhRUBQB1AQAuAAQKfxUAAw8ACAkOIEobAGECAA8ACAkOIEobAGECABIAAgkLESeOADIAAAAA.Broxxar:BAAALgAECgIJAgAAAA==.Bruxxe:BAAALgAECgcJAQAAAA==.Brüenor:BAAALgAECgIJAgAAAA==.',
Bu='Burntroot:BAABLgAECn8wAAINAAkJ+AdARAAiAQANAAkJ+AdARAAiAQAAAA==.',
['Bá']='Bálor:BAAALgAECgEJAQABLgAECgYJDAAEAAAAAA==.',
Ca='Caedwyn:BAABLgAECn8yAAILAAgJqh8UCABuAgALAAgJqh8UCABuAgAAAA==.Caitrakk:BAABLgAECn8VAAMJAAYJWxqgMgC7AQAJAAYJWxqgMgC7AQANAAUJYhC9TAAVAQAAAA==.Calignus:BAABLgAECn8dAAMGAAgJyRG+rwAfAQAGAAgJyRG+rwAfAQATAAUJVQ8jJwDQAAAAAA==.Captjack:BAABLgAECn8dAAIUAAkJrAs3aQBTAQAUAAkJrAs3aQBTAQAAAA==.Cartilage:BAABLgAECn8lAAIHAAkJXRQRRAD2AQAHAAkJXRQRRAD2AQAAAA==.Catalei:BAAALgAECgYJDwAAAA==.Caution:BAAALgADCgYJCwAAAA==.',
Ce='Cela:BAAALgAECgEJAQAAAA==.Celira:BAAALgAECgEJAQAAAA==.Celys:BAAALgAECgIJAgAAAA==.',
Ch='Chickenman:BAAALgAECgEJAQAAAA==.Chillidan:BAAALgAECgQJBwABLgAECgYJFAARAOMWAA==.Chiselia:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Choconilla:BAAALgAECgcJEwAAAA==.Chonkmonk:BAAALgADCgQJBAAAAA==.Choppa:BAAALgADCggJCgAAAA==.Chorizo:BAAALgAECgEJAQABLgAECgkJHQARAIIgAA==.Chupacabrass:BAAALgADCgYJBgAAAA==.Chëbbles:BAAALgAECgEJAQABLgAFFAMJBgASADQKAA==.',
Ci='Cinnomun:BAAALgADCgEJAQAAAA==.',
Co='Combustinme:BAAALgAECgQJBAABLgAECggJNgAUACEZAA==.Consuming:BAABLgAECn8tAAIPAAkJpRPIMADeAQAPAAkJpRPIMADeAQAAAA==.Coorsbanquet:BAABLgAECn8bAAMVAAkJvhcNBwAYAgAVAAkJvhcNBwAYAgAUAAIJuAlfHQArAAAAAA==.Coorsbite:BAAALgAECgQJBAAAAA==.Corgh:BAABLgAECn8kAAIWAAYJtw4XBgBIAQAWAAYJtw4XBgBIAQAAAA==.Corrahthecow:BAAALgADCgEJAQAAAA==.Cowardice:BAAALgADCgYJCwAAAA==.',
Cr='Craccjar:BAAALgAECgUJDQAAAA==.Crackjar:BAAALgADCgcJDAAAAA==.Crash:BAECLgAFFH8RAAIUAAcJ3xeVHwC6AQAUAAcJ3xeVHwC6AQAuAAQKfzgAAxQACAn2JLUNANgCABQACAn2JLUNANgCABUAAQkwGbYwAEAAAAAA.Croarik:BAAALgAECgEJAQAAAA==.Crushix:BAABLgAECn81AAIFAAkJKhhHHwAfAgAFAAkJKhhHHwAfAgAAAA==.',
Cs='Csyasha:BAAALgAECgYJCQAAAA==.',
Cy='Cybear:BAAALgAECgYJCAAAAA==.Cykun:BAABLgAECn8uAAIXAAkJcSDiCACXAgAXAAkJcSDiCACXAgAAAA==.',
['Cã']='Cãs:BAAALgADCgkJCgABLgAECgkJGgAPALQNAA==.',
Da='Darch:BAABLgAECn8/AAMYAAkJMCT6AwDyAgAYAAkJMCT6AwDyAgAMAAEJPwm2kAAqAAAAAA==.Davidx:BAAALgAFFAEJAQAAAA==.',
De='Deadgripz:BAAALgADCgMJBgAAAA==.Deadjaden:BAAALgADCgEJAQAAAA==.Deadlos:BAAALgAECgUJCAAAAA==.Deathscreams:BAAALgAECgQJBgAAAA==.Deathxreaper:BAAALgAECgQJCwAAAA==.Decessus:BAAALgAECgUJBgAAAA==.Dekig:BAACLgAFFH8JAAIHAAMJwhDhoADTAAAHAAMJwhDhoADTAAAuAAQKfyUAAgcACAmLFdFYALsBAAcACAmLFdFYALsBAAAA.Delbert:BAAALgADCgYJBgAAAA==.Demine:BAABLgAECn89AAIDAAkJrB/jHACvAgADAAkJrB/jHACvAgAAAA==.Demonvibe:BAAALgAFFAEJAQAAAA==.',
Di='Dico:BAAALgAECgIJAgABLgAFFAgJIwAZAIccAA==.Dinobots:BAAALgAECgYJDAAAAA==.Dipper:BAABLgAECn8cAAIGAAkJExrSPAARAgAGAAkJExrSPAARAgAAAA==.Divinator:BAAALgAECgYJDQAAAA==.',
Do='Donbarriga:BAAALgAECgYJCAAAAA==.Dosmojitos:BAAALgADCgcJBwAAAA==.Doublejumps:BAAALgAECgYJCwAAAA==.Doublelung:BAAALgAECgYJEgAAAA==.',
Dr='Draagone:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Draekeneyez:BAAALgAECgEJAQAAAA==.Drdiddles:BAAALgAECgMJAwAAAA==.',
Du='Duney:BAACLgAFFH8OAAMaAAQJjhPhIgAoAQAaAAQJuhDhIgAoAQAbAAMJVhTcJQDWAAAuAAQKf1oAAxsACQnLIOcEAMQCABsACQmyH+cEAMQCABoACAnvH50NAJUCAAAA.Dußad:BAAALgAECgMJBwAAAA==.',
['Dé']='Déäth:BAAALgADCgQJBAAAAA==.',
Ec='Eckoe:BAABLgAECn8gAAIPAAcJKwaHdQDVAAAPAAcJKwaHdQDVAAAAAA==.',
Ee='Eekeros:BAAALgADCgUJBQAAAA==.Eeveeko:BAACLgAFFH8WAAIcAAQJZRJrAgAKAQAcAAQJZRJrAgAKAQAuAAQKfzsAAhwACQkcH6MGAG4CABwACQkcH6MGAG4CAAAA.',
Ej='Ejavuday:BAABLgAECn8wAAIDAAkJPSIBGADJAgADAAkJPSIBGADJAgAAAA==.',
El='Elvudu:BAAALgAECgQJBwAAAA==.',
Em='Emberstrife:BAAALgAECgEJAgAAAA==.',
En='Enerchi:BAABLgAECn8UAAMRAAYJ4xbqTwAvAQARAAUJZRTqTwAvAQAQAAMJ1SLFNQArAQAAAA==.',
Er='Erazath:BAAALgAECgQJCAAAAA==.Erianar:BAAALgAECgMJAwAAAA==.Ericdruid:BAABLgAECn8aAAMSAAcJSiD3EgB+AgASAAcJSiD3EgB+AgAPAAEJ6QqZ1gAqAAAAAA==.Ericlock:BAAALgADCgMJAwAAAA==.',
Es='Essia:BAAALgAECgEJAQAAAA==.',
Ev='Eveko:BAAALgADCgIJAQAAAA==.Evera:BAABLgAECn8vAAIHAAkJ6gQnpwAhAQAHAAkJ6gQnpwAhAQAAAA==.Everlst:BAAALgADCgEJAQAAAA==.Evokinpants:BAAALgAECgcJDwAAAA==.Evos:BAAALgAECgQJBgAAAA==.',
Ex='Excels:BAACLgAFFH8PAAIPAAMJoBlMNADcAAAPAAMJoBlMNADcAAAuAAQKfysAAg8ACQnSIhEEAH4DAA8ACQnSIhEEAH4DAAAA.Explicatory:BAAALgAECgYJBwABLgAFFAMJDwAPAKAZAA==.',
Ey='Eyllion:BAAALgAECgUJCwAAAA==.',
Fa='Falorin:BAAALgADCgMJAwAAAA==.Fastoris:BAAALgADCgEJAQAAAA==.Fauci:BAACLgAFFH8NAAIHAAUJVBSihAD/AAAHAAUJVBSihAD/AAAuAAQKfx4AAgcACAk4IXsgAIcCAAcACAk4IXsgAIcCAAAA.',
Fb='Fblthelost:BAAALgAECgMJAwAAAA==.',
Fe='Feihao:BAAALgADCggJFQAAAA==.Feile:BAABLgAECn82AAQIAAkJxhfrMwAJAgAIAAkJxhfrMwAJAgAdAAIJfgu/VwBnAAAeAAEJAAD1LwA+AAAAAA==.Fenty:BAAALgAECgUJBQABLgAECggJNgAUACEZAA==.Feshh:BAAALgADCgEJAQAAAA==.',
Fi='Fifezilla:BAAALgAECgIJAgAAAA==.Firble:BAAALgADCgYJBgAAAA==.Fireg:BAAALgADCgEJAQABLgAFFAQJBQADADULAA==.Fistbeaver:BAAALgADCgUJBQAAAA==.',
Fl='Flinzza:BAAALgAECgYJCwAAAA==.Flökki:BAAALgAECgEJAQAAAA==.',
Fo='Foolezz:BAAALgAECgMJBAAAAA==.',
Fr='Fredthedh:BAABLgAECn8cAAIUAAkJZSFUFADeAgAUAAkJZSFUFADeAgAAAA==.Freshjordans:BAAALgAECgEJAQABLgAECgYJCwAEAAAAAA==.Fromtheback:BAAALgAECgYJDgABLgAECgkJGwAHAPAaAA==.',
Fu='Furble:BAAALgADCgYJBgAAAA==.',
Ga='Gaashw:BAAALgAECgIJBgAAAA==.Gadziila:BAAALgADCgEJAQAAAA==.Galcyon:BAAALgADCgEJAQAAAA==.Galiant:BAABLgAECn8mAAIHAAkJ/SNiFwC6AgAHAAkJ/SNiFwC6AgAAAA==.Gashdk:BAAALgAECgEJAQABLgAECgIJBgAEAAAAAA==.Gator:BAAALgAECgEJAQAAAA==.Gaulish:BAAALgADCgkJCQAAAA==.',
Ge='Geraldo:BAAALgAECgIJAgAAAA==.Getagrip:BAABLgAFFH8FAAIHAAMJ8AToKwC1AAAHAAMJ8AToKwC1AAABLgAFFAQJDgAXAIkWAA==.Gethalyn:BAABLgAECn8XAAIGAAcJCRGpmQBCAQAGAAcJCRGpmQBCAQAAAA==.Gexz:BAAALgADCgYJDAAAAA==.',
Gh='Ghee:BAAALgAECgEJAgAAAA==.',
Gi='Gianthippo:BAAALgAECgcJEgAAAA==.',
Gl='Glaivedaddy:BAAALgAECgEJAQAAAA==.Glenlives:BAAALgADCgkJCgABLgAECgkJLQANAEINAA==.',
Go='Gore:BAAALgAECgUJBQAAAA==.Gottverdammt:BAAALgAECgEJAQABLgAECgkJEAAEAAAAAA==.',
Gr='Graveknight:BAAALgAECgMJAwAAAA==.Graveshot:BAAALgADCgQJBAAAAA==.Greennrry:BAAALgAFFAEJAQABLgAFFAMJCAAfANsYAA==.Greennrryy:BAAALgAFFAEJAwABLgAFFAMJCAAfANsYAA==.Greenryy:BAAALgAECgIJAwABLgAFFAMJCAAfANsYAA==.Greyskin:BAAALgADCgEJAQAAAA==.Grizzabella:BAABLgAECn85AAIPAAkJ9Rs7EADQAgAPAAkJ9Rs7EADQAgAAAA==.Grreenry:BAABLgAFFH8IAAIfAAMJ2xhpDADvAAAfAAMJ2xhpDADvAAABLgAFFAMJCAAfANsYAA==.Grriz:BAAALgADCgEJAQAAAA==.Grtmustachio:BAAALgAECgkJEAAAAA==.Grumly:BAAALgAECgYJBwAAAA==.Grundle:BAAALgAECgMJAwAAAA==.',
Gu='Gularak:BAAALgAECgQJBgAAAA==.Gunghø:BAAALgADCggJDwAAAA==.',
Gy='Gyutaro:BAAALgADCgEJAQAAAA==.',
Ha='Haelellionys:BAAALgADCgQJBAAAAA==.Hamms:BAAALgAECgYJBwAAAA==.Hanamae:BAAALgADCgEJAQAAAA==.Hangnail:BAAALgAECgIJBAAAAA==.Hanswoloqued:BAACLgAFFH8VAAMeAAQJzAfzAwCQAAAIAAQJsweFFADlAAAeAAIJRgbzAwCQAAAuAAQKfxsAAwgACQmoC9ttAGABAAgACQmoC9ttAGABAB4AAgmmAQ0qAEsAAAAA.Harmfuljoker:BAAALgADCgQJBAAAAA==.Haussmann:BAAALgAECgEJAQABLgAFFAYJFwAFAG0hAA==.Haxzen:BAAALgADCgMJBAAAAA==.',
He='Healufast:BAABLgAECn9EAAIOAAkJMR4PBwAAAwAOAAkJMR4PBwAAAwAAAA==.Helediriel:BAAALgAECgQJCAAAAA==.Hellsong:BAAALgAECgMJAwABLgAECgYJBgAEAAAAAA==.Helstrom:BAAALgAECgcJDgAAAA==.Hendo:BAAALgADCgYJBgAAAA==.Hendoh:BAAALgAECgcJBwAAAA==.Heysisters:BAAALgAECgIJAwAAAA==.',
Hi='Hispeas:BAAALgADCgQJBwAAAA==.Hitchkawk:BAAALgAECgEJAQAAAA==.Hitchlock:BAAALgAECgEJAwAAAA==.',
Hj='Hjalmar:BAAALgAECgYJDgAAAA==.',
Ho='Holysabeline:BAACLgAFFH8GAAIFAAIJiBLgOgB6AAAFAAIJiBLgOgB6AAAuAAQKf0gAAgUACQlpGtsTAHACAAUACQlpGtsTAHACAAAA.Honestleon:BAAALgADCgMJAwABLgAECgcJFgAGAHgTAA==.Hordechief:BAAALgAFFAIJAgAAAA==.',
Hu='Huchar:BAABLgAECn9EAAMZAAkJ3SJ0AwD9AgAZAAkJ3SJ0AwD9AgAaAAEJmgzFqAAtAAAAAA==.Huevos:BAAALgAECgIJAwABLgAFFAcJIAAHAJYfAA==.Huntersteve:BAABLgAECn8hAAMgAAgJQCOoCAAIAwAgAAgJQCOoCAAIAwAMAAYJ7CAfIwANAgAAAA==.',
Hy='Hydraxix:BAAALgAECgYJCwAAAA==.',
['Hô']='Hônk:BAAALgADCgEJAQABLgAECgkJLQANAEINAA==.',
Ia='Iamanopcow:BAAALgADCgQJBAAAAA==.Iamspeed:BAAALgADCgQJBAAAAA==.',
Ib='Ibuprofen:BAAALgAECgIJAwAAAA==.',
Ic='Iceblade:BAABLgAECn8oAAIFAAkJxxf2HwAaAgAFAAkJxxf2HwAaAgAAAA==.',
Ie='Ieatbabys:BAAALgADCgQJBAAAAA==.',
If='If:BAAALgAECgMJAwAAAA==.',
Ih='Ihideuseek:BAAALgAECgYJDwABLgAECgkJMAADAD0iAA==.',
Ii='Iityouup:BAAALgADCgYJCAAAAA==.',
Il='Illidaniella:BAABLgAECn8aAAMUAAkJZAkWggAcAQAUAAgJmQgWggAcAQAhAAEJ8Q66DQA4AAAAAA==.Illsmurfuup:BAABLgAECn8ZAAIYAAkJ9SZoAACnAwAYAAkJ9SZoAACnAwAAAA==.Iluminatus:BAAALgAECgQJBAAAAA==.',
In='Infection:BAAALgADCgYJCAAAAA==.Inverse:BAAALgADCgYJBgAAAA==.',
Ir='Ironßest:BAABLgAECn8hAAIgAAcJdxC1bABoAQAgAAcJdxC1bABoAQAAAA==.Irôh:BAAALgAECgEJAQABLgAECgUJHAAhAK4fAA==.',
Is='Ishmael:BAAALgADCgEJAQAAAA==.',
It='Itswaymil:BAAALgAECgEJAQAAAA==.',
Iv='Ivannas:BAAALgAECgMJBgAAAA==.',
Ja='Jaabroni:BAAALgADCgIJAgAAAA==.Jackymoon:BAABLgAECn8aAAIGAAgJXCP9HgCNAgAGAAgJXCP9HgCNAgAAAA==.Jaxxion:BAAALgAECgEJAwAAAA==.',
Jd='Jdawg:BAABLgAECn8/AAIcAAkJQiUNAQA9AwAcAAkJQiUNAQA9AwAAAA==.',
Je='Jer:BAAALgADCgYJBgAAAA==.Jessaiyan:BAABLgAECn8sAAIUAAkJKyIvCQADAwAUAAkJKyIvCQADAwAAAA==.',
Ji='Jindo:BAAALgADCgcJBwAAAA==.Jiuni:BAAALgADCgUJBQAAAA==.',
Jj='Jjcjr:BAAALgAFFAIJBAABLgAFFAYJHwAiAJMhAA==.',
Ju='Julaidan:BAAALgAECgQJBAAAAA==.Julaudette:BAABLgAECn8eAAIeAAYJ3wiyGQDzAAAeAAYJ3wiyGQDzAAAAAA==.Juliania:BAAALgAECgIJAwAAAA==.Julzaria:BAABLgAECn8vAAIgAAkJFhFYSQDFAQAgAAkJFhFYSQDFAQAAAA==.Julzoblin:BAABLgAECn8XAAIjAAYJ5wZoBgC6AAAjAAYJ5wZoBgC6AAAAAA==.Jurny:BAABLgAECn8gAAMdAAkJngthFwDoAAAeAAgJ/QmlFAAoAQAdAAcJuQphFwDoAAAAAA==.Jusdeen:BAABLgAECn8YAAMLAAkJtiKGBgCVAgALAAgJGSKGBgCVAgAPAAMJvA8bmgB9AAAAAA==.',
Ka='Kadookieii:BAAALgAFFAEJAQAAAA==.Kahlandra:BAABLgAECn83AAMkAAkJChuGAgAoAgAkAAkJChuGAgAoAgADAAgJ9Qz4kQBUAQAAAA==.Kairoz:BAABLgAECn8UAAMBAAYJFxeHJgCcAQABAAYJFxeHJgCcAQAjAAIJ9A4qbgBoAAABLgAECgYJFAARAOMWAA==.Kaizer:BAACLgAFFH8VAAINAAUJNRM7JgD9AAANAAUJNRM7JgD9AAAuAAQKfyYAAg0ACAmrHN4YAE0CAA0ACAmrHN4YAE0CAAAA.Kalo:BAAALgAECgMJAwAAAA==.Kanrethad:BAAALgAECgQJBAABLgAECggJKgAKAAgbAA==.Karina:BAABLgAECn9HAAMUAAkJoCE+DwDKAgAUAAkJbCA+DwDKAgAVAAkJzxY6BwASAgAAAA==.Kastravia:BAABLgAFFH8GAAMUAAIJ1wI8lQBPAAAUAAIJfQE8lQBPAAAVAAEJ4APSFAAoAAABLgAFFAQJFgARAB4HAA==.Kawolski:BAABLgAFFH8JAAMPAAMJgQe0TQCIAAAPAAMJgQe0TQCIAAALAAEJ3hQuOwA9AAABLgAFFAQJFgARAB4HAA==.',
Ke='Kelitarra:BAAALgADCgQJCAAAAA==.Kellibar:BAAALgAECgcJBwAAAA==.Kevin:BAAALgAECgcJCgAAAA==.Keyzer:BAAALgAECgEJAQAAAA==.',
Kh='Khanjuror:BAABLgAECn8tAAIdAAgJ1xQcCwCQAQAdAAgJ1xQcCwCQAQAAAA==.Kholonoe:BAABLgAECn8cAAIjAAkJmRS1IQC5AQAjAAkJmRS1IQC5AQAAAA==.Khornedog:BAABLgAECn8oAAIIAAgJmBecPwDeAQAIAAgJmBecPwDeAQAAAA==.Khrama:BAABLgAECn8WAAIKAAkJiSH6BQDFAgAKAAkJiSH6BQDFAgAAAA==.',
Ki='Kietemourt:BAAALgADCgUJBQAAAA==.Kiimachamara:BAAALgADCgIJAwAAAA==.Killik:BAAALgAECgQJBAAAAA==.Kinz:BAAALgAECgMJAwABLgABCgkJEwAEAAAAAA==.Kippili:BAAALgADCgQJBAABLgAECgYJCgAEAAAAAA==.Kiritokun:BAAALgADCgYJBAAAAA==.',
Kl='Klapz:BAAALgADCgcJDQABLgAECggJEAAEAAAAAA==.Kleenonean:BAACLgAFFH8aAAIjAAUJ6ySqCwCkAQAjAAUJ6ySqCwCkAQAuAAQKf2YAAyMACQknJscAAH0DACMACQknJscAAH0DAA4AAgnGBlV0AFcAAAAA.',
Ko='Kobe:BAAALgAFFAEJAgAAAA==.',
Kp='Kpyaccah:BAAALgAECgEJAQAAAA==.Kpyassan:BAAALgAECgYJBQAAAA==.',
Kr='Kravenn:BAAALgAECgMJAwAAAA==.Kreuzritter:BAABLgAECn8zAAIYAAkJORDDCABcAgAYAAkJORDDCABcAgAAAA==.Kritterbug:BAAALgAECggJCAAAAA==.',
Ku='Kungcarefu:BAABLgAECn8bAAICAAYJQxLJRADnAAACAAYJQxLJRADnAAAAAA==.Kungfushnaz:BAAALgAECgEJAQAAAA==.Kurzaan:BAAALgAECgcJAgAAAA==.Kurzak:BAAALgAECgQJBwAAAA==.',
Ky='Kyle:BAAALgAECgEJAQABLgAFFAIJAgAEAAAAAA==.',
La='Laciel:BAAALgAECgMJBAABLgAECgkJIAAHAH0eAA==.Lacio:BAABLgAECn9HAAIjAAkJLwrhLQBqAQAjAAkJLwrhLQBqAQAAAA==.Larune:BAAALgADCgQJBwAAAA==.Lasten:BAAALgAECgEJAwAAAA==.Lavendàh:BAABLgAECn8oAAIFAAkJuCCHBQA6AwAFAAkJuCCHBQA6AwAAAA==.',
Le='Lemonite:BAACLgAFFH8TAAIPAAUJ3xEyJgAqAQAPAAUJ3xEyJgAqAQAuAAQKfxYAAg8ACQlwG+QUAI4CAA8ACQlwG+QUAI4CAAAA.Lennykoggins:BAABLgAECn8YAAIgAAgJLBePTQC5AQAgAAgJLBePTQC5AQAAAA==.Lexxix:BAAALgAECgUJBQAAAA==.Leyru:BAABLgAECn8sAAIFAAgJIST7BQAuAwAFAAgJIST7BQAuAwAAAA==.',
Li='Liberos:BAABLgAECn8YAAIJAAkJOBO5LQAAAgAJAAkJOBO5LQAAAgAAAA==.Lifenight:BAABLgAECn8kAAMlAAkJ6ByGBQBbAgAlAAkJ6ByGBQBbAgAHAAEJvwAGPwEJAAAAAA==.Lilnim:BAAALgAECgYJBgAAAA==.Lithvia:BAAALgAECgYJDQAAAA==.',
Ln='Lninedkhack:BAABLgAECn8mAAMHAAkJQRldNAAtAgAHAAkJQRldNAAtAgAKAAgJMQdbMgDTAAAAAA==.',
Lo='Lockdor:BAAALgAECgQJBAAAAA==.Logaar:BAABLgAECn80AAMFAAkJSxaOFgBXAgAFAAkJSxaOFgBXAgAGAAEJ7gH8zQEbAAAAAA==.Loretharan:BAAALgAECgEJAQAAAA==.Louvuitton:BAAALgADCgcJDgAAAA==.',
Lu='Luckymagi:BAAALgAECgEJAQAAAA==.Luckywizkid:BAAALgAECgYJBgAAAA==.Lunartsy:BAAALgADCggJDgAAAA==.Lustiel:BAAALgAECgYJDAAAAA==.Luticris:BAAALgAECgMJBAAAAA==.',
Ly='Lyoric:BAAALgAECgEJAQAAAA==.',
Ma='Madmax:BAAALgADCggJCAAAAA==.Maegot:BAAALgADCgYJBgAAAA==.Magicpants:BAAALgAECgcJCgAAAA==.Magnetto:BAAALgADCggJDQAAAA==.Maiden:BAAALgADCgUJCAABLgAECggJKgAKAAgbAA==.Malexannius:BAAALgADCgUJCQAAAA==.Mannirot:BAAALgAECgEJAQAAAA==.Mariangel:BAAALgAECgUJCQAAAA==.Marrygold:BAAALgAECgEJAgABLgAECgkJIAAHAHYfAA==.Mateus:BAAALgAECgkJDQAAAA==.Maxdeath:BAABLgAECn8lAAIHAAgJ9iO/DQAtAwAHAAgJ9iO/DQAtAwAAAA==.Mazre:BAAALgAECgQJBwAAAA==.',
Me='Megtallica:BAAALgAECgUJDAAAAA==.Mendrelina:BAAALgAECgYJCgAAAA==.Mensrea:BAABLgAECn8mAAMJAAgJyxL7UwBkAQAJAAcJDhH7UwBkAQANAAcJyA5dXgDJAAAAAA==.Merlinn:BAAALgADCgMJBgAAAA==.Merrycold:BAABLgAECn8gAAMHAAkJdh9FPABGAgAHAAcJpSFFPABGAgAKAAUJ3ROoOACxAAAAAA==.Merrygold:BAAALgADCgMJAwABLgAECgkJIAAHAHYfAA==.Merrygored:BAAALgAECgIJAgABLgAECgkJIAAHAHYfAA==.Mess:BAABLgAECn8uAAQZAAcJlB5eDwDzAQAZAAcJlB5eDwDzAQAaAAIJ3gfTlABsAAAbAAMJPQgXRwApAAABLgAECggJKgAKAAgbAA==.Methodical:BAAALgADCgUJBQAAAA==.Metophis:BAAALgAECgYJCgAAAA==.',
Mf='Mfboomstick:BAABLgAECn8/AAMYAAkJNCY3AQBZAwAYAAkJNCY3AQBZAwAMAAEJlSVVLQBhAAAAAA==.',
Mi='Mikklelee:BAAALgADCgIJAgAAAA==.Minerva:BAAALgADCgMJAwAAAA==.Missdebby:BAAALgADCgYJCwAAAA==.Mistweaver:BAABLgAECn8dAAIRAAkJgiDjBQBJAwARAAkJgiDjBQBJAwAAAA==.Mistweaving:BAAALgAECgcJBAAAAA==.Mistyjoe:BAAALgAECgEJAQAAAA==.Mizirath:BAAALgAECgQJBAABLgAECggJMgALAKofAA==.',
Mo='Mochi:BAAALgAECgEJAQABLgAECgkJKAASAKIaAA==.Moghorva:BAABLgAECn8fAAMmAAkJzBgdCQBYAgAmAAkJzBgdCQBYAgAnAAEJ4w0OkQA5AAAAAA==.Mojoe:BAAALgAECgQJEAAAAA==.Mommyswaggin:BAABLgAECn8VAAIOAAkJChRvHwDJAQAOAAkJChRvHwDJAQAAAA==.Moonra:BAAALgAECgEJAQAAAA==.Moopocalypse:BAAALgADCgcJDAABLgAFFAUJDQAOAFQfAA==.Moopsta:BAAALgADCggJDgABLgAFFAUJDQAOAFQfAA==.Moopster:BAACLgAFFH8NAAIOAAUJVB82DQB3AQAOAAUJVB82DQB3AQAuAAQKfzYAAw4ACQmdJbMBAJwDAA4ACQmdJbMBAJwDAAEABgnfGRsiAL0BAAAA.Moopy:BAAALgAECgQJAwABLgAFFAUJDQAOAFQfAA==.Mordekaiserz:BAAALgAECgUJCwAAAA==.Morrgoth:BAAALgADCgEJAQAAAA==.',
Mu='Mucouslurp:BAAALgADCgEJAQAAAA==.',
Na='Nalahni:BAACLgAFFH8OAAInAAQJRQ1kOADkAAAnAAQJRQ1kOADkAAAuAAQKfyIAAicACQmHGHoWACQCACcACQmHGHoWACQCAAAA.Nalthexon:BAAALgAECgEJAQAAAA==.Nanashi:BAAALgAECgMJAwAAAA==.Nastage:BAAALgADCgMJAQAAAA==.Nastus:BAAALgAECgMJAwAAAA==.Nayela:BAAALgAECgYJEAAAAA==.Nazgru:BAAALgAECgEJAQAAAA==.',
Ne='Neptuneakis:BAACLgAFFH8GAAISAAMJNAqmDAC0AAASAAMJNAqmDAC0AAAuAAQKfywAAhIACQl/GFEUADECABIACQl/GFEUADECAAAA.Neptuno:BAAALgAECgEJAgABLgAFFAMJBgASADQKAA==.Nerfblaster:BAAALgADCgEJAQAAAA==.Newcarsmell:BAABLgAECn8UAAQFAAkJ9Q8iJADkAQAFAAgJtxEiJADkAQATAAUJMwsIMACnAAAGAAEJmAGY1AEQAAAAAA==.',
Ni='Nicktee:BAAALgAFFAEJAQAAAA==.Nightmares:BAAALgAECgcJCgAAAA==.Nightrvn:BAAALgAECgQJBAAAAA==.Nimfierce:BAAALgADCgkJCQAAAA==.Nimrose:BAABLgAECn8YAAIDAAkJogP2owA0AQADAAkJogP2owA0AQAAAA==.Niquid:BAABLgAECn8tAAIPAAkJ2ha4MADfAQAPAAkJ2ha4MADfAQAAAA==.',
No='Nolmac:BAABLgAECn8oAAIJAAkJ/SKIBgBIAwAJAAkJ/SKIBgBIAwAAAA==.Notahealer:BAABLgAFFH8GAAMOAAMJwxFMCQCMAAAOAAIJkxZMCQCMAAABAAIJ/gWgQwBtAAAAAA==.Noxloxes:BAAALgADCgcJDAAAAA==.',
Np='Npv:BAABLgAFFH8HAAIHAAIJgQ2O6ACAAAAHAAIJgQ2O6ACAAAAAAA==.',
Ny='Nyssavia:BAAALgADCgcJDgAAAA==.',
Oa='Oakshre:BAABLgAECn80AAIQAAkJnSBYBwDUAgAQAAkJnSBYBwDUAgAAAA==.',
Ob='Obliteration:BAAALgAECgYJBwABLgAECgYJFAARAOMWAA==.',
Ol='Olivertwist:BAAALgAECgQJDgABLgAECgYJFAARAOMWAA==.',
Om='Omnimpotent:BAAALgAECgEJAQABLgAECgIJBQAEAAAAAA==.',
On='Ontwarr:BAAALgAECgYJDQAAAA==.Ontwou:BAABLgAECn8YAAIgAAkJRBuIIgBaAgAgAAkJRBuIIgBaAgAAAA==.',
Op='Ophi:BAAALgAECgYJEQAAAA==.',
Os='Oshaku:BAAALgAECgcJDAAAAQ==.',
Ou='Ouchpotato:BAACLgAFFH8IAAIGAAQJLBNpQwAkAQAGAAQJLBNpQwAkAQAuAAQKfxUAAgYACQlMHYIbAJ8CAAYACQlMHYIbAJ8CAAEuAAUUBAkOABcAiRYA.',
Pa='Paarthurnax:BAABLgAFFH8LAAMnAAQJegjPDgDTAAAnAAQJegjPDgDTAAAiAAEJFAepDwA+AAAAAA==.Palathal:BAAALgAECgUJBgABLgAECggJGQADAPoTAA==.Pallynim:BAAALgADCgQJBwAAAA==.Palms:BAACLgAFFH8RAAIQAAUJLxznDgBHAQAQAAUJLxznDgBHAQAuAAQKfxgAAhAACQlDIpgHAAIDABAACQlDIpgHAAIDAAAA.Pancakezebra:BAABLgAECn8yAAIYAAkJ6RrsEAAlAgAYAAkJ6RrsEAAlAgAAAA==.Pantsftw:BAABLgAECn8fAAMOAAgJQwymNAAyAQAOAAgJ1QumNAAyAQABAAEJQQXJfQAuAAAAAA==.Papabear:BAAALgADCgUJBQAAAA==.Parkbreezy:BAABLgAECn8bAAILAAcJBwqYQgCcAAALAAcJBwqYQgCcAAAAAA==.Passera:BAABLgAECn8WAAIDAAgJvxIZCgAPAQADAAgJvxIZCgAPAQAAAA==.Pawg:BAAALgADCgcJBgAAAA==.',
Pe='Pebbles:BAAALgAECgcJBwAAAA==.Peltier:BAABLgAECn8sAAIDAAkJdCDLJQCFAgADAAkJdCDLJQCFAgAAAA==.Pendle:BAABLgAECn8sAAMIAAgJFA5GZAB2AQAIAAgJfg1GZAB2AQAdAAYJHQvDKQAbAQAAAA==.Perilous:BAAALgAECgIJAgABLgAFFAQJDgAXAIkWAA==.',
Ph='Phoenix:BAABLgAECn8vAAIGAAkJbB/fGgCjAgAGAAkJbB/fGgCjAgAAAA==.Phorine:BAAALgAECgEJAQAAAA==.',
Pl='Plox:BAAALgAECgYJEwAAAA==.Plugtobacca:BAABLgAFFH8FAAMQAAQJjwVYCACiAAAQAAMJagdYCACiAAACAAIJAACtYwAAAAABLgAFFAUJDQAHAFQUAA==.Plurnizz:BAABLgAECn8dAAMIAAkJHQhgiAApAQAIAAkJHQhgiAApAQAdAAQJEwHKXwBPAAAAAA==.',
Po='Pocketchange:BAACLgAFFH8ZAAMJAAUJkhoVDQDvAAAJAAUJkhoVDQDvAAANAAIJPxzWDgCzAAAuAAQKfxUAAw0ACQniGnEqAMIBAA0ABgnWHHEqAMIBAAkABgm/FzJLAFYBAAAA.',
Pu='Puffadin:BAAALgADCgEJAQAAAA==.Punybanner:BAAALgAECgEJAQAAAA==.Puppymoke:BAAALgAECgMJAwAAAA==.Puptart:BAAALgAECgUJBQAAAA==.',
Ra='Raest:BAABLgAECn8pAAICAAgJyCT8BQDdAgACAAgJyCT8BQDdAgABLgAECgkJFgAKAIkhAA==.Raiker:BAAALgAECgMJBAAAAA==.Ranch:BAAALgAECgEJAQAAAA==.Razzlock:BAAALgAECgEJAQAAAA==.',
Re='Regret:BAAALgAECgkJEgAAAA==.Relovan:BAABLgAECn8vAAMbAAkJ6RCEFgCnAQAbAAkJ6RCEFgCnAQAaAAUJSwOYhgClAAAAAA==.Renothidan:BAACLgAFFH8PAAIGAAQJfxrcMwBHAQAGAAQJfxrcMwBHAQAuAAQKfyMAAgYACQnZG+s4AB4CAAYACQnZG+s4AB4CAAAA.Reuben:BAAALgAECgUJBQAAAA==.Revin:BAAALgADCgYJBgAAAA==.Revrynth:BAAALgAFFAIJAgAAAA==.Rexorcist:BAAALgAFFAIJAwAAAA==.',
Ri='Rickyboby:BAAALgAECggJDAAAAA==.Righteøus:BAAALgAECgUJEQAAAA==.Rillan:BAABLgAECn8aAAIGAAYJ8xbqmwA+AQAGAAYJ8xbqmwA+AQAAAA==.Rin:BAAALgAECgkJCQABLgAECgkJPwAIAEklAA==.Ripper:BAAALgAECgUJCQAAAA==.Rippèd:BAABLgAECn8YAAIdAAYJswy6AgDPAAAdAAYJswy6AgDPAAAAAA==.Rithcice:BAABLgAECn84AAMaAAkJtCbyAAB8AwAaAAkJqSbyAAB8AwAZAAcJ/yPTCABrAgAAAA==.Rizzdolphler:BAACLgAFFH8QAAIGAAQJqRR4RAAiAQAGAAQJqRR4RAAiAQAuAAQKfygAAwYACAmyHZc1ACoCAAYACAmyHZc1ACoCAAUABgktEc1CADYBAAAA.',
Ro='Roadnurse:BAAALgADCgIJAgAAAA==.Rockntroll:BAAALgADCgIJAgAAAA==.Rodah:BAAALgADCgkJEAAAAA==.Roscoee:BAAALgADCgEJAQAAAA==.Roselynt:BAAALgAECgMJAwAAAA==.',
Rs='Rsk:BAAALgADCgYJCQABLgAECggJKgAKAAgbAA==.',
Ru='Ruins:BAAALgAECgEJAQAAAA==.',
['Rà']='Ràrity:BAAALgADCggJCAAAAA==.',
['Rö']='Rönburgundy:BAACLgAFFH8NAAIIAAMJ1BEVdgDVAAAIAAMJ1BEVdgDVAAAuAAQKfy4AAggACQmNHvAdAHECAAgACQmNHvAdAHECAAAA.',
Sa='Sanako:BAABLgAECn8oAAISAAkJxxGHHwDMAQASAAkJxxGHHwDMAQAAAA==.Sanastusa:BAAALgADCgYJCAAAAA==.Saneros:BAAALgAECggJCQABLgAECggJNgAUACEZAA==.Santoniche:BAAALgAECgUJBAAAAA==.Sap:BAABLgAECn8gAAMXAAcJFxc9HwCcAQAXAAcJFxc9HwCcAQAoAAQJQguHFgDIAAABLgAECggJKgAKAAgbAA==.Sausiege:BAAALgAECgMJAwAAAA==.Saveserenade:BAAALgAECgUJBQAAAA==.',
Sc='Scarylarry:BAABLgAECn82AAIUAAgJIRmiPADVAQAUAAgJIRmiPADVAQAAAA==.Scyther:BAACLgAFFH8MAAMhAAQJbwwcFQD7AAAhAAQJMAwcFQD7AAAUAAIJRwMrjwBkAAAuAAQKfxgAAxQACQlBD8txAE8BABQACAk9DMtxAE8BACEABglZEexLAIcAAAAA.',
Sd='Sdh:BAAALgADCgQJBgAAAA==.',
Se='Seaze:BAAALgAECgIJAgAAAA==.Seishinokami:BAABLgAECn8tAAINAAkJQg1aLwCDAQANAAkJQg1aLwCDAQAAAA==.Senala:BAAALgAECgEJAQAAAA==.Serenade:BAACLgAFFH8KAAIDAAQJqBErawANAQADAAQJqBErawANAQAuAAQKfyQAAgMACAmuHxYzAKYCAAMACAmuHxYzAKYCAAAA.Setheron:BAABLgAECn8sAAIaAAkJdSG2BQAFAwAaAAkJdSG2BQAFAwAAAA==.Sethron:BAAALgAECgIJAgAAAA==.Señsei:BAAALgAECggJCwAAAA==.',
Sh='Shamminit:BAAALgAECgIJAgAAAA==.Shamtul:BAAALgAECgEJAwAAAA==.Shamwow:BAAALgADCgcJDgAAAA==.Shlea:BAACLgAFFH8XAAInAAQJVAheDgDXAAAnAAQJVAheDgDXAAAuAAQKfx0AAicACQn7EIMpAJsBACcACQn7EIMpAJsBAAAA.Shyva:BAABLgAECn8pAAMZAAgJ9SIxBwC4AgAZAAgJ9SIxBwC4AgAaAAUJ9xcFUwD/AAABLgAFFAIJAgAEAAAAAA==.',
Si='Siinestro:BAAALgAECgQJBAAAAA==.Sinlee:BAAALgAECgcJDgABLgAECgkJOgAIAEMiAA==.',
Sl='Slayla:BAAALgAECgUJDAAAAA==.Slimboyjoe:BAAALgADCgcJDgAAAA==.Slimmjim:BAAALgADCgEJAQAAAA==.Slinkstir:BAAALgADCgQJAwAAAA==.',
Sn='Snailtrails:BAAALgAECgcJBwAAAA==.Sneak:BAAALgADCgMJAwABLgAECgYJCwAEAAAAAA==.Sneakcookies:BAAALgAECgMJBwABLgAECgYJFAARAOMWAA==.',
So='Soggyundies:BAAALgAECgQJBAAAAA==.Solendros:BAAALgAECgYJDwAAAA==.Sonthar:BAAALgAECgYJBgAAAA==.Soulborn:BAAALgADCgMJAwAAAA==.Soulelf:BAAALgADCgcJBwAAAA==.',
Sp='Spacehog:BAAALgAECgYJDAAAAA==.Sparticus:BAAALgAECgEJAQAAAA==.Spiro:BAAALgAECgEJAQABLgAFFAMJCwAQAMIfAA==.Splouge:BAAALgAECgYJBgAAAA==.',
St='Standarshh:BAACLgAFFH8JAAIgAAMJ5xnMIACtAAAgAAMJ5xnMIACtAAAuAAQKf0AAAiAACQl1IsoKAP8CACAACQl1IsoKAP8CAAAA.Stemmz:BAAALgADCgEJAQAAAA==.Stronghand:BAAALgADCgYJBwAAAA==.',
Su='Subtle:BAACLgAFFH8OAAIXAAQJiRaLGgBCAQAXAAQJiRaLGgBCAQAuAAQKfygAAxcACQnXHywNAMcCABcACQnXHywNAMcCACkABQmpBvMZAIUAAAAA.Sugarbabi:BAABLgAECn8iAAMPAAkJDR8uIQA7AgAPAAcJ3x4uIQA7AgASAAcJFhflJwCRAQAAAA==.Sugarcube:BAAALgAECgEJAQAAAA==.Sugarqween:BAAALgAECgYJDAAAAA==.Sugarrush:BAAALgADCgUJBQAAAA==.Sugarshot:BAAALgAECggJCAAAAA==.Sugarthorn:BAAALgAECgIJAwAAAA==.Sulcer:BAAALgADCgMJBAAAAA==.',
Sw='Swiftwing:BAAALgADCgYJBgAAAA==.',
Sy='Sylria:BAAALgAECgIJAgAAAA==.Sylrianah:BAABLgAECn9IAAQOAAkJ0CBcBwD5AgAOAAkJ0CBcBwD5AgAjAAkJ4QipLgBmAQABAAQJrghvWACeAAAAAA==.Sylveste:BAACLgAFFH8XAAIFAAYJbSEkCQApAgAFAAYJbSEkCQApAgAuAAQKfyMAAgUABwkUGgkyAI4BAAUABwkUGgkyAI4BAAAA.Sylvfelster:BAAALgAECgYJBwABLgAFFAYJFwAFAG0hAA==.Sylánnia:BAAALgADCgcJBwAAAA==.',
Ta='Ta:BAABLgAECn8aAAIBAAcJpAgWOgAoAQABAAcJpAgWOgAoAQAAAA==.Talis:BAAALgAECgEJAQAAAA==.Tankhiskhan:BAABLgAECn8VAAIKAAgJQA3XLgDpAAAKAAgJQA3XLgDpAAAAAA==.Tarlis:BAABLgAECn8YAAIeAAgJ9xq8BAAqAgAeAAgJ9xq8BAAqAgAAAA==.',
Te='Tedrickeyjr:BAAALgAECgEJBgAAAA==.Terithresh:BAAALgADCgMJBAAAAA==.',
Th='Thanil:BAABLgAECn8wAAIGAAkJmBkrNgAoAgAGAAkJmBkrNgAoAgAAAA==.Thelliane:BAAALgAECgIJAgABLgAFFAYJIwAJAFcTAA==.Thenet:BAAALgAECgEJAwAAAA==.',
Ti='Tie:BAAALgAECggJDwAAAA==.Tikamancer:BAAALgADCgEJAQAAAA==.Tilvalhalla:BAABLgAECn8cAAImAAcJPAogKgAhAQAmAAcJPAogKgAhAQAAAA==.',
To='Todorokii:BAAALgAECgUJDQAAAA==.Tom:BAAALgAECgEJAgABLgAFFAIJAgAEAAAAAA==.Torrin:BAAALgADCgYJBwAAAA==.Tortricid:BAAALgAECgcJDgAAAA==.Totaldchtree:BAAALgAECgEJAQAAAA==.Totempants:BAAALgAECgYJBgAAAA==.Totinospizza:BAAALgADCgYJBgAAAA==.',
Tr='Trashkan:BAAALgADCgIJAgAAAA==.Trauck:BAAALgADCgEJAQAAAA==.Traumzi:BAAALgAECgEJAQAAAA==.Travvy:BAACLgAFFH8+AAMXAAkJhh/qAAC3AgAXAAkJyRvqAAC3AgAoAAIJoR6xDABqAAAuAAQKfyIAAhcACQkWJgEBAMMDABcACQkWJgEBAMMDAAAA.Treezus:BAAALgADCgYJCAAAAA==.Trevmo:BAABLgAECn82AAIZAAkJGyCEBgCjAgAZAAkJGyCEBgCjAgAAAA==.Trexin:BAAALgAECgYJCgAAAA==.',
Tu='Turaylon:BAAALgAFFAEJAQAAAA==.Turtlebox:BAAALgAECgQJBgAAAA==.',
Ty='Tym:BAAALgAFFAIJAgAAAA==.',
Ug='Ugargro:BAABLgAECn8VAAMZAAUJOwdaOQCPAAAZAAUJOwdaOQCPAAAaAAEJGwWJsgAkAAAAAA==.',
Un='Unapologetic:BAAALgAECggJDAAAAA==.Unbreakabull:BAABLgAFFH8RAAISAAUJ/yUkDwCwAQASAAUJ/yUkDwCwAQAAAA==.Unceejin:BAAALgADCggJEQAAAA==.Unholydk:BAABLgAECn8qAAMKAAgJCBv6DwAMAgAKAAgJCBv6DwAMAgAHAAUJsw+I5wDLAAAAAA==.',
Va='Valcuna:BAAALgAECgQJBQAAAA==.Valka:BAABLgAECn8YAAIfAAkJUgkoGgA8AQAfAAkJUgkoGgA8AQAAAA==.Vamptouch:BAAALgAECgIJAwABLgAECgYJCwAEAAAAAA==.Vanaan:BAAALgAECgIJAgABLgAECgYJBwAEAAAAAA==.Varidrus:BAAALgAECgQJBQAAAA==.Vaste:BAAALgADCgcJCQAAAA==.',
Ve='Ventrue:BAABLgAECn8jAAIDAAkJ6xWVXgDEAQADAAkJ6xWVXgDEAQAAAA==.Veyle:BAABLgAECn8/AAMXAAkJ1yRiBQDdAgAXAAkJ1yRiBQDdAgAoAAEJKh7AGwBJAAAAAA==.',
Vi='Vivian:BAABLgAECn8xAAIhAAkJfRrgCgB6AgAhAAkJfRrgCgB6AgABLgAFFAMJCwAQAMIfAA==.Vixèn:BAAALgAECgEJAQAAAA==.',
Vo='Voidsurge:BAABLgAECn8yAAQVAAcJmBl1DACPAQAVAAcJUxZ1DACPAQAhAAUJMxsfKAA7AQAUAAUJ+hGwsQDFAAABLgAECggJKgAKAAgbAA==.',
Vy='Vyndria:BAAALgAECgQJDwAAAA==.',
Wa='Wardell:BAAALgAECgQJBwAAAA==.',
We='Weaspore:BAABLgAECn8hAAIHAAgJlR7IQgD6AQAHAAgJlR7IQgD6AQAAAA==.Weasy:BAAALgAECgkJDgAAAA==.',
Wo='Woogidaboogi:BAAALgAECgIJBQAAAA==.Woogieboogie:BAAALgAECgEJAQABLgAECgIJBQAEAAAAAA==.',
Xi='Xiamiel:BAAALgADCgYJCQAAAA==.',
Xl='Xl:BAABLgAECn9WAAMhAAgJ/RxVCwCrAgAhAAgJhxxVCwCrAgAUAAgJJxZWRQC3AQAAAA==.',
Ya='Yaitoopmfp:BAAALgAECgIJAwABLgAECgkJIAAHAHYfAA==.Yao:BAAALgAECgEJAQABLgAFFAMJCgAZAPUZAA==.',
Yh='Yharnem:BAABLgAECn8XAAICAAcJ8hBWLgBMAQACAAcJ8hBWLgBMAQAAAA==.',
Yo='Yogurtpants:BAAALgAECgYJEgAAAA==.Yonny:BAAALgADCgEJAQAAAA==.',
Yu='Yukionna:BAAALgADCgcJCwAAAA==.',
Za='Zabara:BAABLgAECn8dAAIJAAkJrh+tCwD/AgAJAAkJrh+tCwD/AgAAAA==.Zabbystabby:BAAALgADCgkJDgAAAA==.Zakaraki:BAABLgAECn8+AAQiAAkJhCWoAAA8AwAiAAkJhCWoAAA8AwAnAAcJNyEPGQAOAgAmAAcJTAd5JgBBAQAAAA==.Zaki:BAABLgAECn8aAAIUAAkJThqHIwBCAgAUAAkJThqHIwBCAgAAAA==.Zanked:BAAALgADCgQJBAAAAA==.Zarkingu:BAAALgADCgMJAwAAAA==.',
Ze='Zealot:BAAALgAFFAEJAQAAAA==.Zeleria:BAAALgAECgUJBgAAAA==.Zeno:BAAALgAFFAIJAgAAAA==.Zephyr:BAAALgAECgQJBAAAAA==.Zerathis:BAABLgAECn86AAIIAAkJQyLSDgDWAgAIAAkJQyLSDgDWAgAAAA==.Zerathül:BAAALgAECgcJEgAAAA==.Zerötwo:BAAALgADCgkJCgAAAA==.Zestul:BAAALgADCgkJFgAAAA==.',
Zi='Zimbobayaga:BAAALgAECgMJAwAAAA==.',
Zo='Zodivine:BAAALgADCgMJAwAAAA==.Zohar:BAAALgADCgEJAgAAAA==.Zooty:BAAALgADCgUJAwAAAA==.Zoshow:BAAALgAFFAIJAgAAAA==.',
Zu='Zuggo:BAAALgADCgYJBgAAAA==.',
Zy='Zyrig:BAAALgADCgUJBgAAAA==.',
['Zõ']='Zõshow:BAABLgAECn8XAAMIAAcJmxVucQBXAQAIAAcJeBVucQBXAQAdAAEJEh0zYABOAAAAAA==.',
['Ça']='Çaptainçhaos:BAAALgAECgYJCgAAAA==.',
['Çh']='Çhromi:BAAALgADCgMJAwAAAA==.',
['Ða']='Ðaredevil:BAACLgAFFH8LAAIQAAMJwh9rFQATAQAQAAMJwh9rFQATAQAuAAQKfy4AAhAACQnmH0gHANUCABAACQnmH0gHANUCAAAA.',
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
