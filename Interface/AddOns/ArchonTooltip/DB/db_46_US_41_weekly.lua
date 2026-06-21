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
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aahzbear:BAAALgAFFAEJAQAAAA==.',
Ab='Abreale:BAAALgADCgMJAwAAAA==.Abruum:BAAALgADCgcJBwAAAA==.',
Ae='Aeero:BAABLgAECn8UAAIBAAYJNhfEHwCWAQABAAYJNhfEHwCWAQAAAA==.Aerendyl:BAAALgAECgcJCwAAAA==.',
Ai='Aiden:BAACLgAFFH8HAAICAAMJbRArOwC6AAACAAMJbRArOwC6AAAuAAQKfxQAAgIABgkfHF8qALcBAAIABgkfHF8qALcBAAAA.',
Al='Algros:BAAALgADCgEJAQAAAA==.Alternative:BAAALgAECgUJBwAAAA==.Alyiriia:BAAALgAECgkJCQAAAA==.',
Am='Amathal:BAABLgAECn8ZAAIDAAgJ+hMSjABfAQADAAgJ+hMSjABfAQAAAA==.Amazon:BAAALgAECgIJAwAAAA==.Amilea:BAAALgAFFAEJAQABLgABCgkJEwAEAAAAAA==.',
An='Anastasia:BAAALgADCggJCAAAAA==.Angelsevoker:BAAALgAECggJCAAAAA==.Angermoonria:BAAALgADCgcJBwAAAA==.Ankheloios:BAAALgAECgQJBAAAAA==.Antihiiro:BAAALgAECgMJAwAAAA==.Antipro:BAAALgAFFAEJAQAAAA==.Anubbus:BAABLgAFFH8FAAIDAAMJWwMQlQCoAAADAAMJWwMQlQCoAAAAAA==.Anzulok:BAAALgADCgYJAQAAAA==.',
Ar='Arbalest:BAAALgADCgcJBgAAAA==.Aredhela:BAABLgAECn8hAAMFAAkJlxQXGQA+AgAFAAkJlxQXGQA+AgAGAAQJMRd0uwAPAQAAAA==.Arinth:BAAALgADCggJEQAAAA==.Arkadios:BAAALgAECgIJAgAAAA==.Armpit:BAAALgAECgMJAwAAAA==.',
As='Ascanius:BAAALgAECgEJAQABLgAECgQJBAAEAAAAAA==.Ashiiro:BAAALgAECgcJEAAAAA==.Ashveil:BAAALgAECgUJBQABLgAECgkJJgAHAEEZAA==.Asia:BAABLgAECn8/AAIIAAkJSSW7BQA1AwAIAAkJSSW7BQA1AwAAAA==.Asmodeius:BAAALgAFFAEJAgAAAA==.Astroprof:BAAALgAECgEJAQABLgAECgYJFAAJAFsaAA==.',
At='Athrea:BAABLgAECn8gAAMHAAkJfR5TFQDHAgAHAAkJ3B1TFQDHAgAKAAUJUBu+JQAlAQAAAA==.',
Au='Auntjemima:BAAALgAECgEJAgAAAA==.Aureleus:BAAALgADCgEJAQAAAA==.',
Aw='Away:BAAALgADCgIJAgAAAA==.',
Az='Azaii:BAAALgADCggJCgAAAA==.Azlear:BAAALgAECgkJBgAAAA==.Azrael:BAAALgAECgkJBwAAAA==.',
Ba='Babilouchoux:BAAALgAECgMJBQAAAA==.Ballz:BAAALgADCgYJBgAAAA==.Bano:BAAALgAECgMJAwAAAA==.Barnre:BAAALgAECgYJCQABLgAECgYJDAAEAAAAAA==.Bash:BAABLgAECn8VAAILAAcJ6hMwHQBkAQALAAcJ6hMwHQBkAQABLgAECggJKgAKAAgbAA==.Baythos:BAAALgAFFAEJAgAAAA==.',
Bb='Bb:BAAALgAECgIJAQAAAA==.',
Bd='Bdssm:BAAALgAFFAIJAgAAAA==.',
Be='Beefstick:BAAALgAECgUJBwAAAA==.Berzercarl:BAAALgAECgEJAQAAAA==.Beserkfury:BAABLgAECn8lAAIMAAkJjRCqDgBzAQAMAAkJjRCqDgBzAQAAAA==.',
Bh='Bhemtu:BAAALgAECgEJAQAAAA==.',
Bi='Biercan:BAAALgAECggJEAAAAA==.Bigcarl:BAAALgADCgMJAwAAAA==.Binke:BAABLgAECn8iAAINAAkJrgz5MQB1AQANAAkJrgz5MQB1AQAAAA==.Bittywhite:BAAALgAECgcJCQAAAA==.Bittywyvern:BAAALgADCgUJCwABLgAECgcJCQAEAAAAAA==.',
Bk='Bkarakh:BAAALgADCgYJFgAAAA==.',
Bl='Blayze:BAABLgAECn8eAAIOAAkJ5hPOGQD8AQAOAAkJ5hPOGQD8AQAAAA==.Blessidbee:BAAALgAECgEJAQAAAA==.Blightmarx:BAAALgADCgUJCQAAAA==.Blitzwow:BAAALgADCgYJBQAAAA==.Bluemoonflay:BAAALgAECgkJEwAAAA==.Blúnt:BAAALgADCgQJBAAAAA==.',
Bo='Bobheals:BAABLgAECn8tAAMPAAYJWBdUAQApAQAPAAUJphtUAQApAQALAAEJAAB6lQAAAAAAAA==.Boibye:BAAALgAECgYJDgAAAA==.Bolblock:BAAALgAECgkJDwAAAA==.Bonewolf:BAAALgADCgYJCwAAAA==.Boostedww:BAAALgAFFAEJAQAAAA==.Boostie:BAAALgAECgEJAgAAAA==.',
Br='Brambleclaw:BAABLgAECn8/AAIKAAkJRSPHBADjAgAKAAkJRSPHBADjAgAAAA==.Brayker:BAACLgAFFH8GAAIGAAIJLB+ZgwCtAAAGAAIJLB+ZgwCtAAAuAAQKf0cAAgYACQmjJR8GAEEDAAYACQmjJR8GAEEDAAAA.Breadoneal:BAABLgAECn8pAAMFAAkJ4hkCHwAKAgAFAAgJ9hgCHwAKAgAGAAEJ7QUOvwEkAAAAAA==.Breeze:BAAALgAECgYJBgAAAA==.Brewed:BAABLgAECn80AAMQAAkJORRqHADLAQAQAAkJORRqHADLAQARAAEJLwEF4QALAAAAAA==.Brisketbane:BAAALgAECgcJEAAAAA==.Brokenmask:BAACLgAFFH8VAAIPAAcJ7Q8HAgA5AQAPAAcJ7Q8HAgA5AQAuAAQKfxUAAw8ACAkOIEobAGECAA8ACAkOIEobAGECABIAAgkLESWOADIAAAAA.Broxxar:BAAALgAECgIJAgAAAA==.Bruxxe:BAAALgAECgcJAQAAAA==.Brüenor:BAAALgAECgIJAgAAAA==.',
Bu='Burntroot:BAABLgAECn8vAAINAAkJ+Ac+RAAiAQANAAkJ+Ac+RAAiAQAAAA==.',
Ca='Caedwyn:BAABLgAECn8yAAILAAgJqh8UCABuAgALAAgJqh8UCABuAgAAAA==.Caitrakk:BAABLgAECn8UAAMJAAYJWxqgMgC7AQAJAAYJWxqgMgC7AQANAAUJYhC9TAAVAQAAAA==.Calignus:BAABLgAECn8dAAMGAAgJyRG+rwAfAQAGAAgJyRG+rwAfAQATAAUJVQ8jJwDQAAAAAA==.Captjack:BAABLgAECn8dAAIUAAkJrAs2aQBTAQAUAAkJrAs2aQBTAQAAAA==.Cartilage:BAABLgAECn8lAAIHAAkJXRQPRAD2AQAHAAkJXRQPRAD2AQAAAA==.Catalei:BAAALgAECgYJDwAAAA==.Caution:BAAALgADCgYJCwAAAA==.',
Ce='Cela:BAAALgAECgEJAQAAAA==.Celira:BAAALgAECgEJAQAAAA==.Celys:BAAALgAECgIJAgAAAA==.',
Ch='Chickenman:BAAALgAECgEJAQAAAA==.Chillidan:BAAALgAECgQJBwABLgAECgYJFAARAOMWAA==.Chiselia:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Choconilla:BAAALgAECgcJEwAAAA==.Chonkmonk:BAAALgADCgQJBAAAAA==.Choppa:BAAALgADCggJCgAAAA==.Chorizo:BAAALgAECgEJAQABLgAECgkJHQARAIIgAA==.Chupacabrass:BAAALgADCgYJBgAAAA==.Chëbbles:BAAALgADCgMJAwABLgAECgkJJgASABUXAA==.',
Ci='Cinnomun:BAAALgADCgEJAQAAAA==.',
Co='Combustinme:BAAALgAECgQJBAABLgAECggJNgAUACEZAA==.Consuming:BAABLgAECn8tAAIPAAkJpRPMMADeAQAPAAkJpRPMMADeAQAAAA==.Coorsbanquet:BAABLgAECn8bAAMVAAkJvhcMBwAYAgAVAAkJvhcMBwAYAgAUAAIJuAm2DAAuAAAAAA==.Coorsbite:BAAALgAECgQJBAAAAA==.Corgh:BAABLgAECn8kAAIWAAYJtw4XBgBIAQAWAAYJtw4XBgBIAQAAAA==.Corrahthecow:BAAALgADCgEJAQAAAA==.Cowardice:BAAALgADCgYJCwAAAA==.',
Cr='Craccjar:BAAALgAECgUJCwAAAA==.Crackjar:BAAALgADCgcJDAAAAA==.Crash:BAECLgAFFH8RAAIUAAcJ3xepHwC6AQAUAAcJ3xepHwC6AQAuAAQKfzgAAxQACAn2JLYNANgCABQACAn2JLYNANgCABUAAQkwGbMwAEAAAAAA.Croarik:BAAALgAECgEJAQAAAA==.Crushix:BAABLgAECn81AAIFAAkJKhhHHwAfAgAFAAkJKhhHHwAfAgAAAA==.',
Cs='Csyasha:BAAALgAECgYJCQAAAA==.',
Cy='Cybear:BAAALgAECgYJCAAAAA==.Cykun:BAABLgAECn8uAAIXAAkJcSDfCACXAgAXAAkJcSDfCACXAgAAAA==.',
['Cã']='Cãs:BAAALgADCgkJCgABLgAECgkJGgAPALQNAA==.',
Da='Darch:BAABLgAECn8/AAMYAAkJMCT7AwDyAgAYAAkJMCT7AwDyAgAMAAEJPwm2kAAqAAAAAA==.Davidx:BAAALgAECgYJCAAAAA==.',
De='Deadgripz:BAAALgADCgMJBgAAAA==.Deadjaden:BAAALgADCgEJAQAAAA==.Deadlos:BAAALgAECgUJCAAAAA==.Deathscreams:BAAALgAECgQJBgAAAA==.Deathxreaper:BAAALgAECgQJCwAAAA==.Decessus:BAAALgAECgUJBgAAAA==.Dekig:BAACLgAFFH8IAAIHAAMJNxDloADTAAAHAAMJNxDloADTAAAuAAQKfyQAAgcACAmLFc5YALsBAAcACAmLFc5YALsBAAAA.Delbert:BAAALgADCgYJBgAAAA==.Demine:BAABLgAECn89AAIDAAkJrB/lHACvAgADAAkJrB/lHACvAgAAAA==.Demonvibe:BAAALgAFFAEJAQAAAA==.',
Di='Dico:BAAALgAECgIJAgABLgAFFAgJIwAZAIccAA==.Dinobots:BAAALgAECgYJDAAAAA==.Dipper:BAABLgAECn8cAAIGAAkJExrUPAARAgAGAAkJExrUPAARAgAAAA==.Divinator:BAAALgAECgYJDQAAAA==.',
Do='Donbarriga:BAAALgAECgYJCAAAAA==.Dosmojitos:BAAALgADCgcJBwAAAA==.Doublejumps:BAAALgAECgYJCwAAAA==.Doublelung:BAAALgAECgYJEgAAAA==.',
Dr='Draagone:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Drdiddles:BAAALgAECgMJAwAAAA==.',
Du='Duney:BAACLgAFFH8LAAMaAAQJjhPlIgAoAQAaAAQJuhDlIgAoAQAbAAMJVhTkJQDWAAAuAAQKf1cAAxsACQliH+cEAMQCABsACQlIHucEAMQCABoACAnvH5wNAJUCAAAA.Dußad:BAAALgAECgMJBwAAAA==.',
['Dé']='Déäth:BAAALgADCgQJBAAAAA==.',
Ec='Eckoe:BAABLgAECn8gAAIPAAcJKwaHdQDVAAAPAAcJKwaHdQDVAAAAAA==.',
Ee='Eekeros:BAAALgADCgUJBQAAAA==.Eeveeko:BAACLgAFFH8SAAIcAAQJZRLqCQAeAQAcAAQJZRLqCQAeAQAuAAQKfzsAAhwACQkcH6MGAG4CABwACQkcH6MGAG4CAAAA.',
Ej='Ejavuday:BAABLgAECn8wAAIDAAkJPSIDGADJAgADAAkJPSIDGADJAgAAAA==.',
El='Elvudu:BAAALgAECgQJBwAAAA==.',
Em='Emberstrife:BAAALgAECgEJAgAAAA==.',
En='Enerchi:BAABLgAECn8UAAMRAAYJ4xbpTwAvAQARAAUJZRTpTwAvAQAQAAMJ1SLFNQArAQAAAA==.',
Er='Erazath:BAAALgAECgQJCAAAAA==.Erianar:BAAALgAECgIJAgAAAA==.Ericdruid:BAABLgAECn8aAAMSAAcJSiD3EgB+AgASAAcJSiD3EgB+AgAPAAEJ6QqZ1gAqAAAAAA==.Ericlock:BAAALgADCgMJAwAAAA==.',
Es='Essia:BAAALgAECgEJAQAAAA==.',
Ev='Eveko:BAAALgADCgIJAQAAAA==.Evera:BAABLgAECn8uAAIHAAkJ6gQhpwAhAQAHAAkJ6gQhpwAhAQAAAA==.Everlst:BAAALgADCgEJAQAAAA==.Evokinpants:BAAALgAECgcJDwAAAA==.Evos:BAAALgAECgQJBgAAAA==.',
Ex='Excels:BAACLgAFFH8OAAIPAAMJoBlTNADcAAAPAAMJoBlTNADcAAAuAAQKfyYAAg8ACQmpIhIEAH4DAA8ACQmpIhIEAH4DAAAA.Explicatory:BAAALgAECgYJBwABLgAFFAMJDgAPAKAZAA==.',
Ey='Eyllion:BAAALgAECgUJCgAAAA==.',
Fa='Falorin:BAAALgADCgMJAwAAAA==.Fastoris:BAAALgADCgEJAQAAAA==.Fauci:BAACLgAFFH8NAAIHAAUJVBSqhAD/AAAHAAUJVBSqhAD/AAAuAAQKfx4AAgcACAk4IXwgAIcCAAcACAk4IXwgAIcCAAAA.',
Fb='Fblthelost:BAAALgAECgMJAwAAAA==.',
Fe='Feihao:BAAALgADCggJFQAAAA==.Feile:BAABLgAECn82AAQIAAkJxhfqMwAJAgAIAAkJxhfqMwAJAgAdAAIJfgu/VwBnAAAeAAEJAAD1LwA+AAAAAA==.Fenty:BAAALgAECgUJBQABLgAECggJNgAUACEZAA==.Feshh:BAAALgADCgEJAQAAAA==.',
Fi='Fifezilla:BAAALgAECgIJAgAAAA==.Firble:BAAALgADCgYJBgAAAA==.Fireg:BAAALgADCgEJAQABLgAFFAQJBQADADULAA==.Fistbeaver:BAAALgADCgUJBQAAAA==.',
Fl='Flinzza:BAAALgAECgYJCwAAAA==.Flökki:BAAALgAECgEJAQAAAA==.',
Fo='Foolezz:BAAALgAECgMJBAAAAA==.',
Fr='Fredthedh:BAABLgAECn8cAAIUAAkJZSFUFADeAgAUAAkJZSFUFADeAgAAAA==.Freshjordans:BAAALgAECgEJAQABLgAECgYJCwAEAAAAAA==.Fromtheback:BAAALgAECgYJDgABLgAECgkJGwAHAPAaAA==.',
Fu='Furble:BAAALgADCgYJBgAAAA==.',
Ga='Gaashw:BAAALgAECgIJBgAAAA==.Gadziila:BAAALgADCgEJAQAAAA==.Galcyon:BAAALgADCgEJAQAAAA==.Galiant:BAABLgAECn8mAAIHAAkJ/SNiFwC6AgAHAAkJ/SNiFwC6AgAAAA==.Gashdk:BAAALgAECgEJAQABLgAECgIJBgAEAAAAAA==.Gator:BAAALgAECgEJAQAAAA==.Gaulish:BAAALgADCgkJCQAAAA==.',
Ge='Geraldo:BAAALgAECgIJAgAAAA==.Getagrip:BAAALgAFFAIJAgABLgAFFAQJDgAXAIkWAA==.Gethalyn:BAABLgAECn8XAAIGAAcJCRGrmQBCAQAGAAcJCRGrmQBCAQAAAA==.Gexz:BAAALgADCgYJDAAAAA==.',
Gh='Ghee:BAAALgAECgEJAgAAAA==.',
Gi='Gianthippo:BAAALgAECgcJEgAAAA==.',
Gl='Glaivedaddy:BAAALgAECgEJAQAAAA==.Glenlives:BAAALgADCgkJCgABLgAECgkJLQANAEINAA==.',
Go='Gore:BAAALgAECgUJBQAAAA==.Gottverdammt:BAAALgAECgEJAQABLgAECgkJEAAEAAAAAA==.',
Gr='Graveknight:BAAALgAECgMJAwAAAA==.Graveshot:BAAALgADCgQJBAAAAA==.Greennrry:BAAALgAFFAEJAQABLgAFFAMJCAAfANsYAA==.Greennrryy:BAAALgAFFAEJAwABLgAFFAMJCAAfANsYAA==.Greenryy:BAAALgAECgIJAwABLgAFFAMJCAAfANsYAA==.Greyskin:BAAALgADCgEJAQAAAA==.Grizzabella:BAABLgAECn85AAIPAAkJ9Rs7EADQAgAPAAkJ9Rs7EADQAgAAAA==.Grreenry:BAABLgAFFH8IAAIfAAMJ2xhpDADvAAAfAAMJ2xhpDADvAAABLgAFFAMJCAAfANsYAA==.Grriz:BAAALgADCgEJAQAAAA==.Grtmustachio:BAAALgAECgkJEAAAAA==.Grumly:BAAALgAECgQJBAAAAA==.Grundle:BAAALgAECgMJAwAAAA==.',
Gu='Gularak:BAAALgAECgQJBgAAAA==.Gunghø:BAAALgADCggJDwAAAA==.',
Gy='Gyutaro:BAAALgADCgEJAQAAAA==.',
Ha='Haelellionys:BAAALgADCgQJBAAAAA==.Hanamae:BAAALgADCgEJAQAAAA==.Hangnail:BAAALgAECgIJBAAAAA==.Hanswoloqued:BAACLgAFFH8RAAMIAAQJ/AaKDAB0AAAIAAQJ/AaKDAB0AAAeAAEJ2wZ9AwBQAAAuAAQKfxsAAwgACQmoC9ttAGABAAgACQmoC9ttAGABAB4AAgmmAQ0qAEsAAAAA.Harmfuljoker:BAAALgADCgQJBAAAAA==.Haxzen:BAAALgADCgMJBAAAAA==.',
He='Healufast:BAABLgAECn9EAAIOAAkJMR4PBwAAAwAOAAkJMR4PBwAAAwAAAA==.Hellsong:BAAALgAECgMJAwABLgAECgYJBgAEAAAAAA==.Helstrom:BAAALgAECgcJCQAAAA==.Hendo:BAAALgADCgYJBgAAAA==.Hendoh:BAAALgAECgIJAgAAAA==.Heysisters:BAAALgAECgIJAwAAAA==.',
Hi='Hispeas:BAAALgADCgQJBwAAAA==.Hitchkawk:BAAALgAECgEJAQAAAA==.Hitchlock:BAAALgAECgEJAwAAAA==.',
Ho='Holysabeline:BAACLgAFFH8GAAIFAAIJiBLiOgB6AAAFAAIJiBLiOgB6AAAuAAQKf0gAAgUACQlpGt0TAHACAAUACQlpGt0TAHACAAAA.Honestleon:BAAALgADCgMJAwABLgAECgcJFgAGAHgTAA==.Hordechief:BAAALgAFFAIJAgAAAA==.',
Hu='Huchar:BAABLgAECn9EAAMZAAkJ3SJ0AwD9AgAZAAkJ3SJ0AwD9AgAaAAEJmgzCqAAtAAAAAA==.Huevos:BAAALgAECgIJAwAAAA==.Huntersteve:BAABLgAECn8hAAMgAAgJQCOoCAAIAwAgAAgJQCOoCAAIAwAMAAYJ7CAfIwANAgAAAA==.',
Hy='Hydraxix:BAAALgAECgYJCwAAAA==.',
['Hô']='Hônk:BAAALgADCgEJAQABLgAECgkJLQANAEINAA==.',
Ia='Iamanopcow:BAAALgADCgQJBAAAAA==.Iamspeed:BAAALgADCgQJBAAAAA==.',
Ib='Ibuprofen:BAAALgAECgEJAgAAAA==.',
Ic='Iceblade:BAABLgAECn8oAAIFAAkJxxf2HwAaAgAFAAkJxxf2HwAaAgAAAA==.',
Ie='Ieatbabys:BAAALgADCgQJBAAAAA==.',
If='If:BAAALgAECgMJAwAAAA==.',
Ih='Ihideuseek:BAAALgAECgYJDwABLgAECgkJMAADAD0iAA==.',
Ii='Iityouup:BAAALgADCgYJCAAAAA==.',
Il='Illidaniella:BAABLgAECn8ZAAIUAAgJmQgWggAcAQAUAAgJmQgWggAcAQAAAA==.Illsmurfuup:BAABLgAECn8ZAAIYAAkJ9SZoAACnAwAYAAkJ9SZoAACnAwAAAA==.Iluminatus:BAAALgAECgQJBAAAAA==.',
In='Infection:BAAALgADCgYJCAAAAA==.Inverse:BAAALgADCgYJBgAAAA==.',
Ir='Ironßest:BAABLgAECn8hAAIgAAcJdxC4bABoAQAgAAcJdxC4bABoAQAAAA==.Irôh:BAAALgAECgEJAQABLgAECgUJGgAhAK4fAA==.',
Is='Ishmael:BAAALgADCgEJAQAAAA==.',
Iv='Ivannas:BAAALgAECgMJBgAAAA==.',
Ja='Jaabroni:BAAALgADCgIJAgAAAA==.Jackymoon:BAABLgAECn8aAAIGAAgJXCP8HgCNAgAGAAgJXCP8HgCNAgAAAA==.Jaxxion:BAAALgAECgEJAgAAAA==.',
Jd='Jdawg:BAABLgAECn8/AAIcAAkJQiUNAQA9AwAcAAkJQiUNAQA9AwAAAA==.',
Je='Jer:BAAALgADCgYJBgAAAA==.Jessaiyan:BAABLgAECn8sAAIUAAkJKyIxCQADAwAUAAkJKyIxCQADAwAAAA==.',
Ji='Jindo:BAAALgADCgcJBwAAAA==.Jiuni:BAAALgADCgUJBQAAAA==.',
Jj='Jjcjr:BAAALgAFFAIJAwABLgAFFAYJHQAiAJMhAA==.',
Ju='Julaidan:BAAALgAECgQJBAAAAA==.Julaudette:BAABLgAECn8eAAIeAAYJ3wizGQDzAAAeAAYJ3wizGQDzAAAAAA==.Juliania:BAAALgAECgIJAwAAAA==.Julzaria:BAABLgAECn8uAAIgAAgJchJWSQDGAQAgAAgJchJWSQDGAQAAAA==.Julzoblin:BAAALgAECgYJEQAAAA==.Jurny:BAABLgAECn8eAAMdAAkJngtgFwDoAAAeAAgJ/QmmFAAoAQAdAAcJuQpgFwDoAAAAAA==.Jusdeen:BAABLgAECn8YAAMLAAkJtiKGBgCVAgALAAgJGSKGBgCVAgAPAAMJvA8bmgB9AAAAAA==.',
Ka='Kadookieii:BAAALgAFFAEJAQAAAA==.Kahlandra:BAABLgAECn83AAMjAAkJChuGAgAoAgAjAAkJChuGAgAoAgADAAgJ9Qz2kQBUAQAAAA==.Kairoz:BAAALgAECgYJEwABLgAECgYJFAARAOMWAA==.Kaizer:BAACLgAFFH8VAAINAAUJNRM8JgD9AAANAAUJNRM8JgD9AAAuAAQKfyYAAg0ACAmrHN4YAE0CAA0ACAmrHN4YAE0CAAAA.Kalo:BAAALgAECgMJAwAAAA==.Kanrethad:BAAALgAECgQJBAABLgAECggJKgAKAAgbAA==.Karina:BAABLgAECn9HAAMUAAkJoCFADwDKAgAUAAkJbCBADwDKAgAVAAkJzxY5BwASAgAAAA==.Kastravia:BAABLgAFFH8GAAMUAAIJ1wI+lQBPAAAUAAIJfQE+lQBPAAAVAAEJ4APRFAAoAAABLgAFFAQJFgARAB4HAA==.Kawolski:BAABLgAFFH8JAAMPAAMJiQe6TQCIAAAPAAMJiQe6TQCIAAALAAEJ3hQuOwA9AAABLgAFFAQJFgARAB4HAA==.',
Ke='Kelitarra:BAAALgADCgQJCAAAAA==.Kellibar:BAAALgAECgcJBwAAAA==.Kevin:BAAALgAECgcJCgAAAA==.Keyzer:BAAALgAECgEJAQAAAA==.',
Kh='Khanjuror:BAABLgAECn8tAAIdAAgJ1xQcCwCQAQAdAAgJ1xQcCwCQAQAAAA==.Kholonoe:BAABLgAECn8cAAIkAAkJmRSzIQC5AQAkAAkJmRSzIQC5AQAAAA==.Khornedog:BAABLgAECn8oAAIIAAgJmBeZPwDeAQAIAAgJmBeZPwDeAQAAAA==.Khrama:BAABLgAECn8WAAIKAAkJiSH9BQDFAgAKAAkJiSH9BQDFAgAAAA==.',
Ki='Kietemourt:BAAALgADCgUJBQAAAA==.Kiimachamara:BAAALgADCgIJAwAAAA==.Killik:BAAALgAECgQJBAAAAA==.Kinz:BAAALgAECgMJAwABLgABCgkJEwAEAAAAAA==.Kippili:BAAALgADCgQJBAABLgAECgYJCgAEAAAAAA==.Kiritokun:BAAALgADCgYJBAAAAA==.',
Kl='Klapz:BAAALgADCgcJDQABLgAECggJEAAEAAAAAA==.Kleenonean:BAACLgAFFH8XAAIkAAUJ6ySqCwCkAQAkAAUJ6ySqCwCkAQAuAAQKf2MAAyQACQkTJsgAAH0DACQACQkTJsgAAH0DAA4AAgnGBlV0AFcAAAAA.',
Ko='Kobe:BAAALgAFFAEJAgAAAA==.',
Kp='Kpyaccah:BAAALgAECgEJAQAAAA==.Kpyassan:BAAALgAECgYJBQAAAA==.',
Kr='Kravenn:BAAALgAECgMJAwAAAA==.Kreuzritter:BAABLgAECn8zAAIYAAkJORDDCABcAgAYAAkJORDDCABcAgAAAA==.Kritterbug:BAAALgAECggJCAAAAA==.',
Ku='Kungcarefu:BAABLgAECn8bAAICAAYJQxLHRADnAAACAAYJQxLHRADnAAAAAA==.Kungfushnaz:BAAALgAECgEJAQAAAA==.Kurzaan:BAAALgAECgcJAgAAAA==.Kurzak:BAAALgAECgQJBwAAAA==.',
Ky='Kyle:BAAALgAECgEJAQABLgAFFAIJAgAEAAAAAA==.',
La='Laciel:BAAALgAECgMJBAABLgAECgkJIAAHAH0eAA==.Lacio:BAABLgAECn9HAAIkAAkJLwrdLQBqAQAkAAkJLwrdLQBqAQAAAA==.Larune:BAAALgADCgQJBwAAAA==.Lasten:BAAALgAECgEJAwAAAA==.Lavendàh:BAABLgAECn8oAAIFAAkJuCCIBQA6AwAFAAkJuCCIBQA6AwAAAA==.',
Le='Lemonite:BAACLgAFFH8TAAIPAAUJ3xE5JgAqAQAPAAUJ3xE5JgAqAQAuAAQKfxYAAg8ACQlwG+QUAI4CAA8ACQlwG+QUAI4CAAAA.Lennykoggins:BAABLgAECn8YAAIgAAgJLBeOTQC5AQAgAAgJLBeOTQC5AQAAAA==.Lexxix:BAAALgAECgUJBQAAAA==.Leyru:BAABLgAECn8sAAIFAAgJIST8BQAuAwAFAAgJIST8BQAuAwAAAA==.',
Li='Liberos:BAABLgAECn8YAAIJAAkJOBO2LQAAAgAJAAkJOBO2LQAAAgAAAA==.Lifenight:BAABLgAECn8kAAMlAAkJ6ByFBQBbAgAlAAkJ6ByFBQBbAgAHAAEJvwAGPwEJAAAAAA==.Lilnim:BAAALgAECgYJBgAAAA==.Lithvia:BAAALgAECgYJDQAAAA==.',
Ln='Lninedkhack:BAABLgAECn8mAAMHAAkJQRlcNAAtAgAHAAkJQRlcNAAtAgAKAAgJMQdZMgDTAAAAAA==.',
Lo='Lockdor:BAAALgAECgQJBAAAAA==.Logaar:BAABLgAECn80AAMFAAkJSxaQFgBXAgAFAAkJSxaQFgBXAgAGAAEJ7gH5zQEbAAAAAA==.Loretharan:BAAALgAECgEJAQAAAA==.Louvuitton:BAAALgADCgcJDgAAAA==.',
Lu='Luckymagi:BAAALgAECgEJAQAAAA==.Luckywizkid:BAAALgAECgYJBgAAAA==.Lunartsy:BAAALgADCggJDgAAAA==.Lustiel:BAAALgAECgYJDAAAAA==.Luticris:BAAALgAECgMJBAAAAA==.',
Ly='Lyoric:BAAALgAECgEJAQAAAA==.',
Ma='Madmax:BAAALgADCggJCAAAAA==.Maegot:BAAALgADCgYJBgAAAA==.Magicpants:BAAALgAECgcJCgAAAA==.Magnetto:BAAALgADCggJDQAAAA==.Maiden:BAAALgADCgUJCAABLgAECggJKgAKAAgbAA==.Malexannius:BAAALgADCgUJCQAAAA==.Mannirot:BAAALgAECgEJAQAAAA==.Mariangel:BAAALgAECgUJCQAAAA==.Marrygold:BAAALgAECgEJAgABLgAECgkJIAAHAHYfAA==.Mateus:BAAALgAECgkJDQAAAA==.Maxdeath:BAABLgAECn8lAAIHAAgJ9iO/DQAtAwAHAAgJ9iO/DQAtAwAAAA==.Mazre:BAAALgAECgQJBwAAAA==.',
Me='Megtallica:BAAALgAECgUJCwAAAA==.Mendrelina:BAAALgAECgYJCgAAAA==.Mensrea:BAABLgAECn8lAAMJAAgJyxL0UwBkAQAJAAcJDhH0UwBkAQANAAcJyA5XXgDJAAAAAA==.Merlinn:BAAALgADCgMJBgAAAA==.Merrycold:BAABLgAECn8gAAMHAAkJdh9FPABGAgAHAAcJpSFFPABGAgAKAAUJ3ROmOACxAAAAAA==.Merrygold:BAAALgADCgMJAwABLgAECgkJIAAHAHYfAA==.Merrygored:BAAALgAECgIJAgABLgAECgkJIAAHAHYfAA==.Mess:BAABLgAECn8uAAQZAAcJlB5gDwDzAQAZAAcJlB5gDwDzAQAaAAIJ3gfTlABsAAAbAAMJPQgXRwApAAABLgAECggJKgAKAAgbAA==.Methodical:BAAALgADCgUJBQAAAA==.Metophis:BAAALgAECgYJCgAAAA==.',
Mf='Mfboomstick:BAABLgAECn8/AAMYAAkJNCY3AQBZAwAYAAkJNCY3AQBZAwAMAAEJlSVXLQBhAAAAAA==.',
Mi='Mikklelee:BAAALgADCgIJAgAAAA==.Minerva:BAAALgADCgMJAwAAAA==.Missdebby:BAAALgADCgYJCwAAAA==.Mistweaver:BAABLgAECn8dAAIRAAkJgiDlBQBJAwARAAkJgiDlBQBJAwAAAA==.Mistweaving:BAAALgAECgcJBAAAAA==.Mizirath:BAAALgAECgQJBAABLgAECggJMgALAKofAA==.',
Mo='Moghorva:BAABLgAECn8fAAMmAAkJzBgdCQBYAgAmAAkJzBgdCQBYAgAnAAEJ4w0MkQA5AAAAAA==.Mojoe:BAAALgAECgQJEAAAAA==.Mommyswaggin:BAABLgAECn8VAAIOAAkJChRtHwDJAQAOAAkJChRtHwDJAQAAAA==.Moonra:BAAALgAECgEJAQAAAA==.Moopocalypse:BAAALgADCgcJDAABLgAFFAUJDQAOAFQfAA==.Moopsta:BAAALgADCggJDgABLgAFFAUJDQAOAFQfAA==.Moopster:BAACLgAFFH8NAAIOAAUJVB82DQB3AQAOAAUJVB82DQB3AQAuAAQKfzYAAw4ACQmdJbQBAJwDAA4ACQmdJbQBAJwDAAEABgnfGRciAL0BAAAA.Moopy:BAAALgAECgMJAwABLgAFFAUJDQAOAFQfAA==.Mordekaiserz:BAAALgAECgUJCwAAAA==.Morrgoth:BAAALgADCgEJAQAAAA==.',
Mu='Mucouslurp:BAAALgADCgEJAQAAAA==.',
Na='Nalahni:BAACLgAFFH8OAAInAAQJRQ1gOADkAAAnAAQJRQ1gOADkAAAuAAQKfyIAAicACQmHGHoWACQCACcACQmHGHoWACQCAAAA.Nanashi:BAAALgAECgMJAwAAAA==.Nastage:BAAALgADCgMJAQAAAA==.Nastus:BAAALgAECgMJAwAAAA==.Nayela:BAAALgAECgYJEAAAAA==.Nazgru:BAAALgAECgEJAQAAAA==.',
Ne='Neptuneakis:BAABLgAECn8mAAISAAkJFRdPFAAxAgASAAkJFRdPFAAxAgAAAA==.Neptuno:BAAALgADCgEJAQABLgAECgkJJgASABUXAA==.Nerfblaster:BAAALgADCgEJAQAAAA==.Newcarsmell:BAABLgAECn8UAAQFAAkJ9Q8jJADkAQAFAAgJtxEjJADkAQATAAUJMwsHMACnAAAGAAEJmAGV1AEQAAAAAA==.',
Ni='Nicktee:BAAALgAFFAEJAQAAAA==.Nightmares:BAAALgAECgcJCgAAAA==.Nightrvn:BAAALgAECgQJBAAAAA==.Nimrose:BAABLgAECn8YAAIDAAkJogPzowA0AQADAAkJogPzowA0AQAAAA==.Niquid:BAABLgAECn8qAAIPAAkJ2ha6MADfAQAPAAkJ2ha6MADfAQAAAA==.',
No='Nolmac:BAABLgAECn8oAAIJAAkJ/SKKBgBIAwAJAAkJ/SKKBgBIAwAAAA==.Notahealer:BAAALgAFFAIJAwABLgAFFAMJBAAEAAAAAA==.Noxloxes:BAAALgADCgcJDAAAAA==.',
Np='Npv:BAABLgAFFH8HAAIHAAIJgQ2R6ACAAAAHAAIJgQ2R6ACAAAAAAA==.',
Ny='Nyssavia:BAAALgADCgcJDgAAAA==.',
Oa='Oakshre:BAABLgAECn80AAIQAAkJnSBYBwDUAgAQAAkJnSBYBwDUAgAAAA==.',
Ob='Obliteration:BAAALgAECgYJBwABLgAECgYJFAARAOMWAA==.',
Ol='Olivertwist:BAAALgAECgQJDgABLgAECgYJFAARAOMWAA==.',
Om='Omnimpotent:BAAALgAECgEJAQABLgAECgIJBQAEAAAAAA==.',
On='Ontwarr:BAAALgAECgQJBAAAAA==.Ontwou:BAABLgAECn8YAAIgAAkJRBuJIgBaAgAgAAkJRBuJIgBaAgAAAA==.',
Op='Ophi:BAAALgAECgYJEQAAAA==.',
Os='Oshaku:BAAALgAECgcJDAAAAQ==.',
Ou='Ouchpotato:BAACLgAFFH8HAAIGAAQJLBN2QwAkAQAGAAQJLBN2QwAkAQAuAAQKfxUAAgYACQlMHYEbAJ8CAAYACQlMHYEbAJ8CAAEuAAUUBAkOABcAiRYA.',
Pa='Paarthurnax:BAABLgAFFH8HAAMnAAMJMwm5CABlAAAnAAMJlgi5CABlAAAiAAEJFAerDwA+AAAAAA==.Palathal:BAAALgAECgUJBgABLgAECggJGQADAPoTAA==.Pallynim:BAAALgADCgQJBwAAAA==.Palms:BAACLgAFFH8RAAIQAAUJLxznDgBHAQAQAAUJLxznDgBHAQAuAAQKfxgAAhAACQlDIpgHAAIDABAACQlDIpgHAAIDAAAA.Pancakezebra:BAABLgAECn8yAAIYAAkJ6RruEAAlAgAYAAkJ6RruEAAlAgAAAA==.Pantsftw:BAABLgAECn8fAAMOAAgJQwyiNAAyAQAOAAgJ1QuiNAAyAQABAAEJQQXIfQAuAAAAAA==.Papabear:BAAALgADCgUJBQAAAA==.Parkbreezy:BAABLgAECn8bAAILAAcJBwqXQgCcAAALAAcJBwqXQgCcAAAAAA==.Passera:BAABLgAECn8WAAIDAAgJvxKBAwAWAQADAAgJvxKBAwAWAQAAAA==.Pawg:BAAALgADCgcJBgAAAA==.',
Pe='Pebbles:BAAALgAECgcJBwAAAA==.Peltier:BAABLgAECn8sAAIDAAkJdCDOJQCFAgADAAkJdCDOJQCFAgAAAA==.Pendle:BAABLgAECn8sAAMIAAgJFA5GZAB2AQAIAAgJfg1GZAB2AQAdAAYJHQvDKQAbAQAAAA==.Perilous:BAAALgAECgIJAgABLgAFFAQJDgAXAIkWAA==.',
Ph='Phoenix:BAABLgAECn8tAAIGAAkJbB/eGgCjAgAGAAkJbB/eGgCjAgAAAA==.Phorine:BAAALgAECgEJAQAAAA==.',
Pl='Plox:BAAALgAECgYJEwAAAA==.Plugtobacca:BAAALgAFFAMJAwABLgAFFAUJDQAHAFQUAA==.Plurnizz:BAABLgAECn8dAAMIAAkJHQhciAApAQAIAAkJHQhciAApAQAdAAQJEwHKXwBPAAAAAA==.',
Po='Pocketchange:BAACLgAFFH8VAAMJAAUJahafIgBlAQAJAAUJahafIgBlAQANAAIJZxSJBQCXAAAuAAQKfxUAAw0ACQniGnEqAMIBAA0ABgnWHHEqAMIBAAkABgm/FzJLAFYBAAAA.',
Pu='Puffadin:BAAALgADCgEJAQAAAA==.Puppymoke:BAAALgAECgMJAwAAAA==.Puptart:BAAALgAECgUJBQAAAA==.',
Ra='Raest:BAABLgAECn8pAAICAAgJyCT8BQDdAgACAAgJyCT8BQDdAgABLgAECgkJFgAKAIkhAA==.Raiker:BAAALgAECgMJBAAAAA==.Ranch:BAAALgAECgEJAQAAAA==.Razzlock:BAAALgAECgEJAQAAAA==.',
Re='Regret:BAAALgAECgkJEgAAAA==.Relovan:BAABLgAECn8vAAMbAAkJ6RCDFgCnAQAbAAkJ6RCDFgCnAQAaAAUJSwOYhgClAAAAAA==.Renothidan:BAACLgAFFH8NAAIGAAQJqxntMwBHAQAGAAQJqxntMwBHAQAuAAQKfyMAAgYACQnZG+04AB4CAAYACQnZG+04AB4CAAAA.Reuben:BAAALgAECgUJBQAAAA==.Revin:BAAALgADCgYJBgAAAA==.Revrynth:BAAALgAECggJEAABLgAECggJKQAZAPUiAA==.Rexorcist:BAAALgAFFAEJAQAAAA==.',
Ri='Rickyboby:BAAALgAECggJDAAAAA==.Righteøus:BAAALgAECgUJDwAAAA==.Rillan:BAABLgAECn8aAAIGAAYJ8xbtmwA+AQAGAAYJ8xbtmwA+AQAAAA==.Rin:BAAALgAECgkJCQABLgAECgkJPwAIAEklAA==.Ripper:BAAALgAECgUJCQAAAA==.Rippèd:BAAALgAECgYJCwAAAA==.Rithcice:BAABLgAECn84AAMaAAkJtCbyAAB8AwAaAAkJqSbyAAB8AwAZAAcJ/yPUCABrAgAAAA==.Rizzdolphler:BAACLgAFFH8QAAIGAAQJqRSERAAiAQAGAAQJqRSERAAiAQAuAAQKfygAAwYACAmyHZo1ACoCAAYACAmyHZo1ACoCAAUABgktEctCADYBAAAA.',
Ro='Roadnurse:BAAALgADCgIJAgAAAA==.Rockntroll:BAAALgADCgIJAgAAAA==.Rodah:BAAALgADCgkJEAAAAA==.Roscoee:BAAALgADCgEJAQAAAA==.Roselynt:BAAALgAECgMJAwAAAA==.',
Rs='Rsk:BAAALgADCgYJCQABLgAECggJKgAKAAgbAA==.',
Ru='Ruins:BAAALgAECgEJAQAAAA==.',
['Rà']='Ràrity:BAAALgADCggJCAAAAA==.',
['Rö']='Rönburgundy:BAACLgAFFH8NAAIIAAMJ1BEqdgDVAAAIAAMJ1BEqdgDVAAAuAAQKfy4AAggACQmNHvAdAHECAAgACQmNHvAdAHECAAAA.',
Sa='Sanako:BAABLgAECn8oAAISAAkJxxGEHwDMAQASAAkJxxGEHwDMAQAAAA==.Sanastusa:BAAALgADCgYJCAAAAA==.Saneros:BAAALgAECggJCQABLgAECggJNgAUACEZAA==.Santoniche:BAAALgAECgUJBAAAAA==.Sap:BAABLgAECn8gAAMXAAcJFxc8HwCcAQAXAAcJFxc8HwCcAQAoAAQJQguGFgDIAAABLgAECggJKgAKAAgbAA==.Sausiege:BAAALgAECgMJAwAAAA==.Saveserenade:BAAALgAECgUJBQAAAA==.',
Sc='Scarylarry:BAABLgAECn82AAIUAAgJIRmgPADVAQAUAAgJIRmgPADVAQAAAA==.Scyther:BAACLgAFFH8MAAMhAAQJbwwaFQD7AAAhAAQJMAwaFQD7AAAUAAIJRwMzjwBkAAAuAAQKfxgAAxQACQlBD8txAE8BABQACAk9DMtxAE8BACEABglZEetLAIcAAAAA.',
Sd='Sdh:BAAALgADCgQJBgAAAA==.',
Se='Seaze:BAAALgADCgYJCwAAAA==.Seishinokami:BAABLgAECn8tAAINAAkJQg1YLwCDAQANAAkJQg1YLwCDAQAAAA==.Senala:BAAALgAECgEJAQAAAA==.Serenade:BAACLgAFFH8KAAIDAAQJqBFFawANAQADAAQJqBFFawANAQAuAAQKfyQAAgMACAmuHxYzAKYCAAMACAmuHxYzAKYCAAAA.Setheron:BAABLgAECn8sAAIaAAkJdSG1BQAFAwAaAAkJdSG1BQAFAwAAAA==.Sethron:BAAALgAECgIJAgAAAA==.Señsei:BAAALgAECggJCwAAAA==.',
Sh='Shamminit:BAAALgAECgIJAgAAAA==.Shamtul:BAAALgAECgEJAwAAAA==.Shamwow:BAAALgADCgcJDgAAAA==.Shlea:BAACLgAFFH8TAAInAAQJFQiIBgCsAAAnAAQJFQiIBgCsAAAuAAQKfx0AAicACQn7EIEpAJsBACcACQn7EIEpAJsBAAAA.Shyva:BAABLgAECn8pAAMZAAgJ9SIxBwC4AgAZAAgJ9SIxBwC4AgAaAAUJ9xf9UgD/AAAAAA==.',
Si='Siinestro:BAAALgAECgQJBAAAAA==.Sinlee:BAAALgAECgcJDgABLgAECgkJOgAIAEMiAA==.',
Sl='Slayla:BAAALgAECgUJDAAAAA==.Slimboyjoe:BAAALgADCgcJDgAAAA==.Slimmjim:BAAALgADCgEJAQAAAA==.Slinkstir:BAAALgADCgQJAwAAAA==.',
Sn='Snailtrails:BAAALgAECgcJBwAAAA==.Sneak:BAAALgADCgMJAwABLgAECgYJCwAEAAAAAA==.Sneakcookies:BAAALgAECgMJBwABLgAECgYJFAARAOMWAA==.',
So='Soggyundies:BAAALgAECgQJBAAAAA==.Solendros:BAAALgAECgYJDwAAAA==.Sonthar:BAAALgAECgYJBgAAAA==.Soulborn:BAAALgADCgMJAwAAAA==.Soulelf:BAAALgADCgcJBwAAAA==.',
Sp='Spacehog:BAAALgAECgYJDAAAAA==.Sparticus:BAAALgAECgEJAQAAAA==.Spiro:BAAALgAECgEJAQABLgAFFAMJCwAQAMIfAA==.Splouge:BAAALgAECgYJBgAAAA==.',
St='Standarshh:BAACLgAFFH8IAAIgAAMJ5xklCgClAAAgAAMJ5xklCgClAAAuAAQKf0AAAiAACQl1Is0KAP8CACAACQl1Is0KAP8CAAAA.Stemmz:BAAALgADCgEJAQAAAA==.Stronghand:BAAALgADCgYJBwAAAA==.',
Su='Subtle:BAACLgAFFH8OAAIXAAQJiRaPGgBCAQAXAAQJiRaPGgBCAQAuAAQKfygAAxcACQnXHywNAMcCABcACQnXHywNAMcCACkABQmpBvMZAIUAAAAA.Sugarbabi:BAABLgAECn8hAAMPAAkJDR8uIQA7AgAPAAcJ3x4uIQA7AgASAAYJRRjiJwCRAQAAAA==.Sugarcube:BAAALgAECgEJAQAAAA==.Sugarqween:BAAALgAECgYJCwAAAA==.Sugarrush:BAAALgADCgUJBQAAAA==.Sugarshot:BAAALgAECggJCAAAAA==.Sugarthorn:BAAALgAECgEJAQAAAA==.Sulcer:BAAALgADCgMJBAAAAA==.',
Sw='Swiftwing:BAAALgADCgYJBgAAAA==.',
Sy='Sylria:BAAALgAECgIJAgAAAA==.Sylrianah:BAABLgAECn9IAAQOAAkJ0CBcBwD5AgAOAAkJ0CBcBwD5AgAkAAkJ4QimLgBmAQABAAQJrghvWACeAAAAAA==.Sylveste:BAACLgAFFH8XAAIFAAYJbSEnCQApAgAFAAYJbSEnCQApAgAuAAQKfyMAAgUABwkUGgkyAI4BAAUABwkUGgkyAI4BAAAA.Sylvfelster:BAAALgAECgYJBwABLgAFFAYJFwAFAG0hAA==.Sylánnia:BAAALgADCgcJBwAAAA==.',
Ta='Ta:BAABLgAECn8aAAIBAAcJpAgXOgAoAQABAAcJpAgXOgAoAQAAAA==.Talis:BAAALgAECgEJAQAAAA==.Tankhiskhan:BAABLgAECn8VAAIKAAgJQA3ULgDpAAAKAAgJQA3ULgDpAAAAAA==.Tarlis:BAABLgAECn8YAAIeAAgJ9xq8BAAqAgAeAAgJ9xq8BAAqAgAAAA==.',
Te='Tedrickeyjr:BAAALgAECgEJBgAAAA==.Terithresh:BAAALgADCgMJBAAAAA==.',
Th='Thanil:BAABLgAECn8wAAIGAAkJmBkuNgAoAgAGAAkJmBkuNgAoAgAAAA==.Thelliane:BAAALgAECgIJAgABLgAFFAYJIwAJAFcTAA==.Thenet:BAAALgAECgEJAwAAAA==.',
Ti='Tie:BAAALgAECggJDwAAAA==.Tikamancer:BAAALgADCgEJAQAAAA==.Tilvalhalla:BAABLgAECn8cAAImAAcJPAogKgAhAQAmAAcJPAogKgAhAQAAAA==.',
To='Todorokii:BAAALgAECgUJDQAAAA==.Tom:BAAALgAECgEJAgABLgAFFAIJAgAEAAAAAA==.Torrin:BAAALgADCgYJBwAAAA==.Tortricid:BAAALgAECgcJDgAAAA==.Totaldchtree:BAAALgAECgEJAQAAAA==.Totempants:BAAALgAECgYJBgAAAA==.Totinospizza:BAAALgADCgYJBgAAAA==.',
Tr='Trashkan:BAAALgADCgIJAgAAAA==.Trauck:BAAALgADCgEJAQAAAA==.Traumzi:BAAALgAECgEJAQAAAA==.Travvy:BAACLgAFFH83AAMXAAgJmCJOAQD+AQAXAAgJUx5OAQD+AQAoAAIJoR6xDABqAAAuAAQKfyIAAhcACQkWJgEBAMMDABcACQkWJgEBAMMDAAAA.Treezus:BAAALgADCgYJCAAAAA==.Trevmo:BAABLgAECn82AAIZAAkJGyCGBgCjAgAZAAkJGyCGBgCjAgAAAA==.Trexin:BAAALgAECgUJCAAAAA==.',
Tu='Turaylon:BAAALgAFFAEJAQAAAA==.Turtlebox:BAAALgAECgQJBgAAAA==.',
Ty='Tym:BAAALgAFFAIJAgAAAA==.',
Ug='Ugargro:BAABLgAECn8VAAMZAAUJOwdZOQCPAAAZAAUJOwdZOQCPAAAaAAEJGwWHsgAkAAAAAA==.',
Un='Unapologetic:BAAALgAECggJDAAAAA==.Unbreakabull:BAABLgAFFH8RAAISAAUJ/yUxDwCwAQASAAUJ/yUxDwCwAQAAAA==.Unceejin:BAAALgADCggJEQAAAA==.Unholydk:BAABLgAECn8qAAMKAAgJCBv7DwAMAgAKAAgJCBv7DwAMAgAHAAUJsw+A5wDLAAAAAA==.',
Va='Valcuna:BAAALgAECgQJBQAAAA==.Valka:BAABLgAECn8YAAIfAAkJUgkmGgA8AQAfAAkJUgkmGgA8AQAAAA==.Vamptouch:BAAALgAECgIJAwABLgAECgYJCwAEAAAAAA==.Vanaan:BAAALgAECgIJAgABLgAECgYJBwAEAAAAAA==.Varidrus:BAAALgAECgQJBQAAAA==.Vaste:BAAALgADCgcJCQAAAA==.',
Ve='Ventrue:BAABLgAECn8jAAIDAAkJ6xWWXgDEAQADAAkJ6xWWXgDEAQAAAA==.Veyle:BAABLgAECn8/AAMXAAkJ1yRhBQDdAgAXAAkJ1yRhBQDdAgAoAAEJKh7AGwBJAAAAAA==.',
Vi='Vivian:BAABLgAECn8xAAIhAAkJfRrhCgB6AgAhAAkJfRrhCgB6AgABLgAFFAMJCwAQAMIfAA==.',
Vo='Voidsurge:BAABLgAECn8xAAQVAAcJ+hh1DACPAQAVAAcJUxZ1DACPAQAhAAUJMxscKAA7AQAUAAUJyQ+vsQDFAAABLgAECggJKgAKAAgbAA==.',
Vy='Vyndria:BAAALgAECgQJDwAAAA==.',
Wa='Wardell:BAAALgAECgQJBQAAAA==.',
We='Weaspore:BAABLgAECn8hAAIHAAgJlR7EQgD6AQAHAAgJlR7EQgD6AQAAAA==.Weasy:BAAALgAECgkJDgAAAA==.',
Wo='Woogidaboogi:BAAALgAECgIJBQAAAA==.Woogieboogie:BAAALgAECgEJAQABLgAECgIJBQAEAAAAAA==.',
Xi='Xiamiel:BAAALgADCgYJCQAAAA==.',
Xl='Xl:BAABLgAECn9WAAMhAAgJ/RxVCwCrAgAhAAgJhxxVCwCrAgAUAAgJJxZURQC3AQAAAA==.',
Ya='Yaitoopmfp:BAAALgAECgIJAgABLgAECgkJIAAHAHYfAA==.',
Yh='Yharnem:BAABLgAECn8XAAICAAcJ8hBTLgBMAQACAAcJ8hBTLgBMAQAAAA==.',
Yo='Yogurtpants:BAAALgAECgYJEgAAAA==.Yonny:BAAALgADCgEJAQAAAA==.',
Yu='Yukionna:BAAALgADCgcJCwAAAA==.',
Za='Zabara:BAABLgAECn8dAAIJAAkJrh+uCwD/AgAJAAkJrh+uCwD/AgAAAA==.Zabbylight:BAAALgAECgQJBQAAAA==.Zabbystabby:BAAALgADCgkJDgAAAA==.Zakaraki:BAABLgAECn8+AAQiAAkJhCWoAAA8AwAiAAkJhCWoAAA8AwAnAAcJNyEQGQAOAgAmAAcJTAd5JgBBAQAAAA==.Zaki:BAABLgAECn8aAAIUAAkJThqKIwBCAgAUAAkJThqKIwBCAgAAAA==.Zanked:BAAALgADCgQJBAAAAA==.Zarkingu:BAAALgADCgMJAwAAAA==.',
Ze='Zealot:BAAALgAFFAEJAQAAAA==.Zeleria:BAAALgAECgUJBgAAAA==.Zeno:BAAALgAFFAIJAgAAAA==.Zephyr:BAAALgAECgQJBAAAAA==.Zerathis:BAABLgAECn86AAIIAAkJQyLSDgDWAgAIAAkJQyLSDgDWAgAAAA==.Zerathül:BAAALgAECgcJEgAAAA==.Zerötwo:BAAALgADCgkJCgAAAA==.Zestul:BAAALgADCgkJFgAAAA==.',
Zi='Zimbobayaga:BAAALgAECgMJAwAAAA==.',
Zo='Zodivine:BAAALgADCgMJAwAAAA==.Zohar:BAAALgADCgEJAgAAAA==.Zooty:BAAALgADCgUJAwAAAA==.Zoshow:BAAALgAFFAIJAgAAAA==.',
Zu='Zuggo:BAAALgADCgYJBgAAAA==.',
Zy='Zyrig:BAAALgADCgUJBgAAAA==.',
['Zõ']='Zõshow:BAABLgAECn8XAAMIAAcJmxVtcQBXAQAIAAcJeBVtcQBXAQAdAAEJEh0zYABOAAAAAA==.',
['Ça']='Çaptainçhaos:BAAALgAECgYJCgAAAA==.',
['Ða']='Ðaredevil:BAACLgAFFH8LAAIQAAMJwh9tFQATAQAQAAMJwh9tFQATAQAuAAQKfy4AAhAACQnmH0gHANUCABAACQnmH0gHANUCAAAA.',
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
