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

local lookup = {'Priest-Discipline','Monk-Brewmaster','Mage-Frost','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Warlock-Demonology','Shaman-Restoration','DeathKnight-Blood','Druid-Guardian','Hunter-Marksmanship','Shaman-Elemental','Priest-Holy','Druid-Restoration','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Fire','Rogue-Subtlety','Hunter-Survival','Warrior-Protection','Shaman-Enhancement','Warrior-Fury','Warrior-Arms','Warlock-Destruction','Warlock-Affliction','Druid-Feral','DeathKnight-Frost','Hunter-BeastMastery','DemonHunter-Havoc','Evoker-Augmentation','Priest-Shadow','Mage-Arcane','Evoker-Preservation','Rogue-Assassination','Evoker-Devastation','Rogue-Outlaw',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aahzbear:BAAALgAFFAEJAQAAAA==.',
Ab='Abreale:BAAALgADCgMJAwAAAA==.Abruum:BAAALgADCgcJBwAAAA==.',
Ae='Aeero:BAABLgAECn8UAAIBAAYJNhfEHwCWAQABAAYJNhfEHwCWAQAAAA==.Aerendyl:BAAALgAECgcJCwAAAA==.',
Ai='Aiden:BAACLgAFFH8HAAICAAMJbRAgOwC6AAACAAMJbRAgOwC6AAAuAAQKfxQAAgIABgkfHF8qALcBAAIABgkfHF8qALcBAAAA.',
Al='Algros:BAAALgADCgEJAQAAAA==.Alilitha:BAAALgADCgYJBgAAAA==.Alternative:BAAALgAECgUJBwAAAA==.Alyiriia:BAAALgAECgkJCQAAAA==.',
Am='Amathal:BAABLgAECn8ZAAIDAAgJ+hMTjABfAQADAAgJ+hMTjABfAQAAAA==.Amazon:BAAALgAECgIJBQAAAA==.Amilea:BAAALgAFFAEJAQABLgABCgkJEwAEAAAAAA==.',
An='Anastasia:BAAALgADCggJCAAAAA==.Angelsevoker:BAAALgAECggJCAAAAA==.Angermoonria:BAAALgADCgcJBwAAAA==.Ankheloios:BAAALgAECgUJBQAAAA==.Antihiiro:BAAALgAECgMJAwAAAA==.Antipro:BAAALgAFFAEJAQAAAA==.Anubbus:BAABLgAFFH8GAAIDAAMJWwP6lACoAAADAAMJWwP6lACoAAAAAA==.Anzulok:BAAALgADCgYJAQAAAA==.',
Ar='Arbalest:BAAALgADCgcJBgAAAA==.Aredhela:BAABLgAECn8hAAMFAAkJlxQVGQA+AgAFAAkJlxQVGQA+AgAGAAQJMRdxuwAPAQAAAA==.Arinth:BAAALgADCggJEQAAAA==.Arkadios:BAAALgAECgIJAgAAAA==.Armpit:BAAALgAECgMJAwAAAA==.Armsdealer:BAAALgADCgEJAQAAAA==.',
As='Ascanius:BAAALgAECgEJAQABLgAECgQJBAAEAAAAAA==.Ashiiro:BAAALgAECgcJEAAAAA==.Ashveil:BAAALgAECgUJBQABLgAECgkJJgAHAEEZAA==.Asia:BAABLgAECn8/AAIIAAkJSSW8BQA1AwAIAAkJSSW8BQA1AwAAAA==.Asmodeius:BAAALgAFFAEJAgAAAA==.Astroprof:BAAALgAECgEJAQABLgAECgYJFQAJAFsaAA==.',
At='Athrea:BAABLgAECn8gAAMHAAkJfR5VFQDHAgAHAAkJ3B1VFQDHAgAKAAUJUBu/JQAlAQAAAA==.',
Au='Auntjemima:BAAALgAECgEJAgAAAA==.Aureleus:BAAALgADCgEJAQAAAA==.',
Aw='Away:BAAALgADCgIJAgAAAA==.',
Az='Azaii:BAAALgADCggJCgAAAA==.Azlear:BAAALgAECgkJBgAAAA==.Azrael:BAAALgAECgkJBwAAAA==.',
Ba='Babilouchoux:BAAALgAECgMJBQAAAA==.Badomen:BAAALgAECgEJAQAAAA==.Ballz:BAAALgADCgYJBgAAAA==.Bano:BAAALgAECgMJAwAAAA==.Barnre:BAAALgAECgYJCQABLgAECgYJDAAEAAAAAA==.Bash:BAABLgAECn8VAAILAAcJ6hMwHQBkAQALAAcJ6hMwHQBkAQABLgAECggJKgAKAAgbAA==.Batzab:BAAALgAECgEJAQABLgAECgkJHQAJAK4fAA==.Baythos:BAAALgAFFAEJAgAAAA==.',
Bb='Bb:BAAALgAECgIJAQAAAA==.',
Bd='Bdssm:BAAALgAFFAIJAgAAAA==.',
Be='Bearito:BAAALgAFFAMJAwAAAA==.Bearockobama:BAAALgAFFAEJAQABLgAFFAYJGwAJALwbAA==.Beefstick:BAAALgAFFAMJAwAAAA==.Berzercarl:BAAALgAECgEJAQAAAA==.Beserkfury:BAABLgAECn8nAAIMAAkJjRCrDgBzAQAMAAkJjRCrDgBzAQAAAA==.',
Bh='Bhemtu:BAAALgAECgEJAQAAAA==.',
Bi='Biercan:BAAALgAECggJEAAAAA==.Bigcarl:BAAALgADCgMJAwAAAA==.Binke:BAABLgAECn8wAAINAAkJZA7jCQANAQANAAkJZA7jCQANAQAAAA==.Bittywhite:BAAALgAECgcJDwAAAA==.Bittywyvern:BAAALgADCgUJCwABLgAECgcJDwAEAAAAAA==.',
Bl='Blayze:BAABLgAECn8eAAIOAAkJ5hPQGQD8AQAOAAkJ5hPQGQD8AQAAAA==.Blessidbee:BAAALgAECgEJAQAAAA==.Blightmarx:BAAALgADCgUJCQAAAA==.Blitzwow:BAAALgADCgYJBQAAAA==.Bluemoonflay:BAAALgAECgkJEwAAAA==.Blúnt:BAAALgADCgQJBAAAAA==.',
Bo='Bobakat:BAAALgAECgEJAQAAAA==.Bobheals:BAABLgAECn82AAMPAAkJkhvfAQCPAgAPAAkJkhvfAQCPAgALAAEJAAB5lQAAAAAAAA==.Boibye:BAAALgAECgYJDgAAAA==.Bolblock:BAAALgAECgkJDwAAAA==.Bonewolf:BAAALgAECgQJBAAAAA==.Boostedww:BAAALgAFFAEJAgAAAA==.Boostie:BAAALgAECgEJAgAAAA==.',
Br='Brambleclaw:BAABLgAECn8/AAIKAAkJRSPFBADjAgAKAAkJRSPFBADjAgAAAA==.Brayker:BAACLgAFFH8IAAIGAAIJqx+8UQBqAAAGAAIJqx+8UQBqAAAuAAQKf0cAAgYACQmjJSAGAEEDAAYACQmjJSAGAEEDAAAA.Breadoneal:BAABLgAECn8pAAMFAAkJ4hkEHwAKAgAFAAgJ9hgEHwAKAgAGAAEJ7QURvwEkAAAAAA==.Breeze:BAAALgAECgYJBgAAAA==.Brewed:BAABLgAECn80AAMQAAkJPRRrHADLAQAQAAkJPRRrHADLAQARAAEJLwEG4QALAAAAAA==.Brisketbane:BAAALgAECgcJEAAAAA==.Brokenmask:BAACLgAFFH8kAAIPAAgJVBvTBAA/AgAPAAgJVBvTBAA/AgAuAAQKfxUAAw8ACAkOIEobAGECAA8ACAkOIEobAGECABIAAgkLESeOADIAAAAA.Broxxar:BAAALgAECgIJAgAAAA==.Bruxxe:BAAALgAECgcJAQAAAA==.Brüenor:BAAALgAECgIJAgAAAA==.',
Bu='Bubblesx:BAAALgAECgEJAQABLgAFFAEJAgAEAAAAAA==.Burntroot:BAABLgAECn8yAAINAAkJ/QdARAAiAQANAAkJ/QdARAAiAQAAAA==.',
['Bá']='Bálor:BAAALgAECgEJAQABLgAECgYJDAAEAAAAAA==.',
Ca='Caedwyn:BAABLgAECn8yAAILAAgJqh8UCABuAgALAAgJqh8UCABuAgAAAA==.Caitrakk:BAABLgAECn8VAAMJAAYJWxqgMgC7AQAJAAYJWxqgMgC7AQANAAUJYhC9TAAVAQAAAA==.Calignus:BAABLgAECn8dAAMGAAgJyRG+rwAfAQAGAAgJyRG+rwAfAQATAAUJVQ8jJwDQAAAAAA==.Captjack:BAABLgAECn8dAAIUAAkJrAs3aQBTAQAUAAkJrAs3aQBTAQAAAA==.Cartilage:BAABLgAECn8lAAIHAAkJXRQRRAD2AQAHAAkJXRQRRAD2AQAAAA==.Catalei:BAAALgAECgYJDwAAAA==.Caution:BAAALgADCgYJCwAAAA==.',
Ce='Cela:BAAALgAECgEJAQAAAA==.Celira:BAAALgAECgEJAQAAAA==.Celys:BAAALgAECgIJAgAAAA==.',
Ch='Chebbles:BAAALgAECgEJAQABLgAFFAMJEgASACQOAA==.Chickenman:BAAALgAECgEJAQAAAA==.Chillidan:BAAALgAECgQJBwABLgAFFAEJAgAEAAAAAA==.Chiselia:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Choconilla:BAAALgAECgcJEwAAAA==.Chonkmonk:BAAALgADCgQJBAAAAA==.Choppa:BAAALgADCggJCgAAAA==.Chorizo:BAAALgAECgEJAQABLgAECgkJHwARAIIgAA==.Chupacabrass:BAAALgADCgYJBgAAAA==.Chëbbles:BAAALgAECgEJAwABLgAFFAMJEgASACQOAA==.',
Ci='Cinnomun:BAAALgADCgEJAQAAAA==.',
Co='Combustinme:BAAALgAECgQJBAABLgAECggJNgAUACEZAA==.Consuming:BAABLgAECn8tAAIPAAkJpRPIMADeAQAPAAkJpRPIMADeAQAAAA==.Coorsbanquet:BAABLgAECn8bAAMVAAkJvhcNBwAYAgAVAAkJvhcNBwAYAgAUAAIJuAmDNgArAAAAAA==.Coorsbite:BAAALgAECgQJBQAAAA==.Corgh:BAABLgAECn8kAAIWAAYJtw4XBgBIAQAWAAYJtw4XBgBIAQAAAA==.Corrahthecow:BAAALgADCgEJAQAAAA==.Cowardice:BAAALgADCgYJCwAAAA==.',
Cr='Craccjar:BAAALgAECgUJEgAAAA==.Crackjar:BAAALgADCgcJDAAAAA==.Crash:BAACLgAFFH8UAAIUAAgJUBeVHwC6AQAUAAgJUBeVHwC6AQAuAAQKfzwAAxQACAmBJbUNANgCABQACAmBJbUNANgCABUAAQkwGbYwAEAAAAAA.Croarik:BAAALgAECgEJAQAAAA==.Crushix:BAABLgAECn81AAIFAAkJKhhHHwAfAgAFAAkJKhhHHwAfAgAAAA==.',
Cs='Csyasha:BAAALgAECgYJCQAAAA==.',
Cu='Cubcadet:BAAALgAFFAEJAQAAAA==.',
Cy='Cybear:BAAALgAFFAIJAgAAAA==.Cykun:BAABLgAECn8uAAIXAAkJcSDiCACXAgAXAAkJcSDiCACXAgAAAA==.',
['Cã']='Cãs:BAAALgADCgkJCgABLgAECgkJGgAPALQNAA==.',
Da='Dammned:BAAALgAECgUJBQAAAA==.Darch:BAABLgAECn8/AAMYAAkJMCT6AwDyAgAYAAkJMCT6AwDyAgAMAAEJPwm2kAAqAAAAAA==.Davidx:BAAALgAFFAEJAQAAAA==.',
De='Deadgripz:BAAALgADCgMJBgAAAA==.Deadjaden:BAAALgADCgEJAQAAAA==.Deadlos:BAAALgAECgUJCAAAAA==.Deathscreams:BAAALgAECgQJBgAAAA==.Deathxreaper:BAAALgAECgQJCwAAAA==.Decessus:BAAALgAECgUJBgAAAA==.Dekig:BAACLgAFFH8NAAIHAAQJHA/+LwAJAQAHAAQJHA/+LwAJAQAuAAQKfyUAAgcACAmLFdFYALsBAAcACAmLFdFYALsBAAAA.Delbert:BAAALgADCgYJBgAAAA==.Demine:BAABLgAECn89AAIDAAkJpx/jHACvAgADAAkJpx/jHACvAgAAAA==.Demonvibe:BAAALgAFFAEJAQAAAA==.',
Di='Dico:BAAALgAECgIJAgABLgAFFAgJIwAZAIccAA==.Dinobots:BAAALgAECgYJDAAAAA==.Dipper:BAABLgAECn8cAAIGAAkJExrSPAARAgAGAAkJExrSPAARAgAAAA==.Divinator:BAAALgAECgYJDQAAAA==.',
Do='Donbarriga:BAAALgAECgYJCAAAAA==.Dosmojitos:BAAALgADCgcJBwAAAA==.Doublejumps:BAAALgAFFAEJAQABLgAFFAMJBgAaAFIZAA==.Doublelung:BAAALgAECgYJEgAAAA==.',
Dr='Draagone:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Draekeneyez:BAAALgAECgEJAQAAAA==.Drdiddles:BAAALgAECgMJAwAAAA==.',
Du='Duney:BAACLgAFFH8OAAMbAAQJjhPhIgAoAQAbAAQJuhDhIgAoAQAcAAMJVhTcJQDWAAAuAAQKf1oAAxwACQnRIOcEAMQCABwACQm3H+cEAMQCABsACAnvH50NAJUCAAAA.Dußad:BAAALgAECgMJBwAAAA==.',
['Dé']='Déäth:BAAALgADCgQJBAAAAA==.',
Ec='Eckoe:BAABLgAECn8gAAIPAAcJKwaHdQDVAAAPAAcJKwaHdQDVAAAAAA==.',
Ee='Eekeros:BAAALgADCgUJBQAAAA==.Eeveeko:BAACLgAFFH8ZAAIaAAUJZRLkBgDpAAAaAAUJZRLkBgDpAAAuAAQKfzsAAhoACQkcH6MGAG4CABoACQkcH6MGAG4CAAAA.',
Ej='Ejavuday:BAABLgAECn8wAAIDAAkJPSIBGADJAgADAAkJPSIBGADJAgAAAA==.',
El='Elvudu:BAAALgAECgQJBwAAAA==.',
Em='Emberstrife:BAAALgAECgEJAgAAAA==.',
En='Enerchi:BAABLgAECn8UAAMRAAYJ4xbqTwAvAQARAAUJZRTqTwAvAQAQAAMJ1SLFNQArAQABLgAFFAEJAgAEAAAAAA==.',
Er='Erazath:BAAALgAECgQJCAAAAA==.Erianar:BAAALgAECgMJAwAAAA==.Ericdruid:BAABLgAECn8aAAMSAAcJSiD3EgB+AgASAAcJSiD3EgB+AgAPAAEJ6QqZ1gAqAAAAAA==.Ericlock:BAAALgADCgMJAwAAAA==.',
Es='Essia:BAAALgAECgEJAQAAAA==.',
Ev='Eveko:BAAALgADCgIJAQAAAA==.Evera:BAABLgAECn8xAAIHAAkJ6gQnpwAhAQAHAAkJ6gQnpwAhAQAAAA==.Everlst:BAAALgADCgEJAQAAAA==.Eviljerk:BAAALgAECgIJAgAAAA==.Evokinpants:BAAALgAECgcJDwAAAA==.Evos:BAAALgAECgQJBgAAAA==.',
Ex='Excels:BAACLgAFFH8QAAIPAAMJShtMNADcAAAPAAMJShtMNADcAAAuAAQKfysAAg8ACQnSIhEEAH4DAA8ACQnSIhEEAH4DAAAA.Explicatory:BAAALgAECgYJBwABLgAFFAMJEAAPAEobAA==.',
Ey='Eyllion:BAAALgAECgUJCwAAAA==.',
Fa='Falorin:BAAALgADCgMJAwAAAA==.Fastoris:BAAALgADCgEJAQAAAA==.Fauci:BAACLgAFFH8NAAIHAAUJVBSihAD/AAAHAAUJVBSihAD/AAAuAAQKfyAAAgcACQmsIHsgAIcCAAcACQmsIHsgAIcCAAAA.Faunaa:BAAALgAECgMJAwAAAA==.',
Fb='Fblthelost:BAAALgAECgMJAwAAAA==.',
Fe='Feihao:BAAALgADCggJFQAAAA==.Feile:BAABLgAECn82AAQIAAkJxhfrMwAJAgAIAAkJxhfrMwAJAgAdAAIJfgu/VwBnAAAeAAEJAAD1LwA+AAAAAA==.Fenty:BAAALgAECgUJBQABLgAECggJNgAUACEZAA==.Feshh:BAAALgADCgEJAQAAAA==.',
Fi='Fifezilla:BAAALgAECgIJAgAAAA==.Firble:BAAALgADCgYJBgAAAA==.Fireg:BAAALgADCgEJAQABLgAFFAQJBQADADULAA==.Fistbeaver:BAAALgADCgUJBQAAAA==.',
Fl='Flinzza:BAAALgAECgYJCwAAAA==.Flökki:BAAALgAECgEJAQAAAA==.',
Fo='Foolezz:BAAALgAECgMJBAAAAA==.',
Fr='Fredthedh:BAABLgAECn8cAAIUAAkJZSFUFADeAgAUAAkJZSFUFADeAgAAAA==.Freshjordans:BAAALgAECgEJAQABLgAFFAMJBgAaAFIZAA==.Fromtheback:BAAALgAECgYJDgABLgAFFAIJBQAHAK4VAA==.',
Fu='Furble:BAAALgADCgYJBgAAAA==.',
Ga='Gaashw:BAAALgAECgIJBgAAAA==.Gadziila:BAAALgADCgEJAQAAAA==.Galcyon:BAAALgADCgEJAQAAAA==.Galiant:BAABLgAECn8mAAIHAAkJ/SNiFwC6AgAHAAkJ/SNiFwC6AgAAAA==.Gammilite:BAAALgAECgMJAwAAAA==.Gashdk:BAAALgAECgEJAQABLgAECgIJBgAEAAAAAA==.Gator:BAAALgAECgEJAQAAAA==.Gaulish:BAAALgADCgkJCQAAAA==.',
Ge='Geraldo:BAAALgAECgIJAgAAAA==.Getagrip:BAABLgAFFH8KAAIHAAYJUweAJQA2AQAHAAYJUweAJQA2AQAAAA==.Gethalyn:BAABLgAECn8XAAIGAAcJCRGpmQBCAQAGAAcJCRGpmQBCAQAAAA==.Gexz:BAAALgADCgYJDAAAAA==.',
Gh='Ghee:BAAALgAECgEJAgAAAA==.',
Gi='Gianthippo:BAAALgAECgcJEgAAAA==.',
Gl='Glaivedaddy:BAAALgAECgEJAQAAAA==.Glenlives:BAAALgADCgkJCgABLgAECgkJLQANAEINAA==.',
Go='Gore:BAAALgAECgUJBQAAAA==.Gottverdammt:BAAALgAECgEJAQABLgAECgkJEAAEAAAAAA==.',
Gr='Graveknight:BAAALgAECgMJAwAAAA==.Graveshot:BAAALgADCgQJBAAAAA==.Greennrry:BAAALgAFFAEJAQABLgAFFAMJCAAfANsYAA==.Greennrryy:BAAALgAFFAEJBAABLgAFFAMJCAAfANsYAA==.Greenryy:BAAALgAECgIJAwABLgAFFAMJCAAfANsYAA==.Greyskin:BAAALgADCgEJAQAAAA==.Grizzabella:BAABLgAECn86AAIPAAkJQBw7EADQAgAPAAkJQBw7EADQAgAAAA==.Grreenry:BAABLgAFFH8IAAIfAAMJ2xhpDADvAAAfAAMJ2xhpDADvAAABLgAFFAMJCAAfANsYAA==.Grriz:BAAALgADCgEJAQAAAA==.Grtmustachio:BAAALgAECgkJEAAAAA==.Grumly:BAAALgAECgcJCwAAAA==.Grundle:BAAALgAECgMJAwAAAA==.',
Gu='Gularak:BAAALgAECgQJBgAAAA==.Gunghø:BAAALgADCggJDwAAAA==.Gurbosc:BAAALgADCgYJBgABLgAECgkJMgANAP0HAA==.',
Gy='Gyutaro:BAAALgADCgEJAQAAAA==.',
Ha='Haelellionys:BAAALgADCgQJBAAAAA==.Hamms:BAAALgAECgYJBwAAAA==.Hanamae:BAAALgADCgEJAQAAAA==.Hangnail:BAAALgAECgIJBAAAAA==.Hanswoloqued:BAACLgAFFH8VAAMeAAQJzAeNCQCAAAAIAAQJswfYLADQAAAeAAIJRgaNCQCAAAAuAAQKfxsAAwgACQmoC9ttAGABAAgACQmoC9ttAGABAB4AAgmmAQ0qAEsAAAAA.Harmfuljoker:BAAALgADCgQJBAAAAA==.Haussmann:BAAALgAECgEJAQABLgAFFAgJGQAFAMkgAA==.Haxzen:BAAALgADCgMJBAAAAA==.',
He='Healufast:BAABLgAECn9EAAIOAAkJMR4PBwAAAwAOAAkJMR4PBwAAAwAAAA==.Helediriel:BAABLgAFFH8KAAIgAAQJCAz3CAABAQAgAAQJCAz3CAABAQAAAA==.Hellsong:BAAALgAECgMJAwABLgAECgYJBgAEAAAAAA==.Helstrom:BAABLgAECn8XAAIGAAcJdQzpFwAAAQAGAAcJdQzpFwAAAQAAAA==.Hendo:BAAALgADCgYJBgAAAA==.Hendoh:BAAALgAECggJDgAAAA==.Hendosan:BAAALgAECgIJAwAAAA==.Hendou:BAAALgAECgEJAwAAAA==.Heysisters:BAAALgAECgIJAwAAAA==.',
Hi='Hispeas:BAAALgADCgQJBwAAAA==.Hitchkawk:BAAALgAECgEJAQAAAA==.Hitchlock:BAAALgAECgEJAwAAAA==.',
Hj='Hjalmar:BAAALgAECgYJEAABLgAECgkJHQAJAK4fAA==.',
Ho='Holysabeline:BAACLgAFFH8IAAIFAAIJBxd+HABiAAAFAAIJBxd+HABiAAAuAAQKf0gAAgUACQlpGtsTAHACAAUACQlpGtsTAHACAAAA.Honestleon:BAAALgADCgMJAwABLgAECgcJFgAGAHgTAA==.Hordechief:BAAALgAFFAIJAgAAAA==.',
Hu='Huchar:BAABLgAECn9EAAMZAAkJ3SJ0AwD9AgAZAAkJ3SJ0AwD9AgAbAAEJmgzFqAAtAAAAAA==.Huevos:BAAALgAECgIJAwABLgAFFAgJIwAHAE0dAA==.Huntersteve:BAABLgAECn8hAAMhAAgJQCOoCAAIAwAhAAgJQCOoCAAIAwAMAAYJ7CAfIwANAgAAAA==.',
Hy='Hydraxix:BAAALgAECgYJDgAAAA==.',
['Hô']='Hônk:BAAALgADCgEJAQABLgAECgkJLQANAEINAA==.',
Ia='Iamanopcow:BAAALgADCgQJBAAAAA==.Iamspeed:BAAALgADCgQJBAAAAA==.',
Ib='Ibuprofen:BAAALgAECgIJBgAAAA==.',
Ic='Iceblade:BAABLgAECn8oAAIFAAkJxxf2HwAaAgAFAAkJxxf2HwAaAgAAAA==.',
Ie='Ieatbabys:BAAALgADCgUJBQAAAA==.',
If='If:BAAALgAECgMJAwAAAA==.',
Ih='Ihideuseek:BAAALgAECgYJDwABLgAECgkJMAADAD0iAA==.',
Ii='Iityouup:BAAALgADCgYJCAAAAA==.',
Il='Illidaniella:BAABLgAECn8aAAMUAAkJZAkWggAcAQAUAAgJmQgWggAcAQAiAAEJ7Q4KHgA2AAAAAA==.Illsmurfuup:BAABLgAECn8ZAAIYAAkJ9SZoAACnAwAYAAkJ9SZoAACnAwAAAA==.Iluminatus:BAAALgAECgQJBAAAAA==.',
In='Infection:BAAALgADCgYJCAAAAA==.Inverse:BAAALgADCgYJBgAAAA==.',
Ir='Ironßest:BAABLgAECn8hAAIhAAcJdxC1bABoAQAhAAcJdxC1bABoAQAAAA==.Irôh:BAAALgAECgEJAQABLgAECgUJHAAiAK4fAA==.',
Is='Ishmael:BAAALgADCgEJAQAAAA==.',
It='Itswaymil:BAAALgAECgEJAQAAAA==.',
Iv='Ivannas:BAAALgAECgMJBgAAAA==.',
Ja='Jaabroni:BAAALgADCgIJAgAAAA==.Jackymoon:BAABLgAECn8aAAIGAAgJXCP9HgCNAgAGAAgJXCP9HgCNAgAAAA==.Jaxxion:BAAALgAECgEJAwAAAA==.',
Jd='Jdawg:BAABLgAECn8/AAIaAAkJQiUNAQA9AwAaAAkJQiUNAQA9AwAAAA==.',
Je='Jer:BAAALgADCgYJBgAAAA==.Jessaiyan:BAABLgAECn8sAAIUAAkJKyIvCQADAwAUAAkJKyIvCQADAwAAAA==.',
Ji='Jindo:BAAALgADCgcJBwAAAA==.Jiuni:BAAALgADCgUJBQAAAA==.',
Jj='Jjcjr:BAAALgAFFAIJBAABLgAFFAgJLAAjAJ0dAA==.',
Ju='Julaidan:BAAALgAECgQJBgAAAA==.Julaudette:BAABLgAECn8jAAIeAAYJDQmyGQDzAAAeAAYJDQmyGQDzAAAAAA==.Juliania:BAAALgAECgYJCAAAAA==.Julzaria:BAABLgAECn89AAIhAAkJ4xM7DACMAQAhAAkJ4xM7DACMAQAAAA==.Julzoblin:BAABLgAECn8YAAIkAAYJPwdQEQCgAAAkAAYJPwdQEQCgAAAAAA==.Jurny:BAABLgAECn80AAMdAAkJchFaAgCDAQAdAAgJcRJaAgCDAQAeAAgJMQ1lBQDjAAAAAA==.Jusdeen:BAABLgAECn8YAAMLAAkJtiKGBgCVAgALAAgJGSKGBgCVAgAPAAMJvA8bmgB9AAAAAA==.',
Ka='Kadookieii:BAAALgAFFAEJAQAAAA==.Kahlandra:BAABLgAECn83AAMlAAkJChuGAgAoAgAlAAkJChuGAgAoAgADAAgJ9Qz4kQBUAQAAAA==.Kairoz:BAABLgAECn8UAAMBAAYJFxeHJgCcAQABAAYJFxeHJgCcAQAkAAIJ9A4qbgBoAAABLgAFFAEJAgAEAAAAAA==.Kaizer:BAACLgAFFH8WAAINAAUJNRM7JgD9AAANAAUJNRM7JgD9AAAuAAQKfykAAg0ACAlBHd4YAE0CAA0ACAlBHd4YAE0CAAAA.Kalo:BAAALgAECgMJAwAAAA==.Kanrethad:BAAALgAECgQJBAABLgAECggJKgAKAAgbAA==.Karina:BAABLgAECn9HAAMUAAkJoCE+DwDKAgAUAAkJbCA+DwDKAgAVAAkJzxY6BwASAgABLgAFFAEJAgAEAAAAAA==.Kastravia:BAABLgAFFH8GAAMUAAIJ1wI8lQBPAAAUAAIJfQE8lQBPAAAVAAEJ4APSFAAoAAABLgAFFAQJFgARAB4HAA==.Kawolski:BAABLgAFFH8MAAMPAAMJgQe0TQCIAAAPAAMJgQe0TQCIAAALAAMJDBWkFQB2AAABLgAFFAQJFgARAB4HAA==.Kawwne:BAAALgAECgEJAQABLgAECgYJCgAEAAAAAA==.',
Ke='Keepz:BAAALgAECgEJAQABLgAECgYJDAAEAAAAAA==.Kelitarra:BAAALgADCgQJCAAAAA==.Kellibar:BAAALgAECgcJBwAAAA==.Keunen:BAAALgADCgYJBgAAAA==.Kevin:BAAALgAECgcJCgAAAA==.Keyzer:BAAALgAECgEJAQAAAA==.',
Kh='Khanjuror:BAABLgAECn8uAAIdAAgJ1xQcCwCQAQAdAAgJ1xQcCwCQAQAAAA==.Kholonoe:BAABLgAECn8cAAIkAAkJmRS1IQC5AQAkAAkJmRS1IQC5AQAAAA==.Khornedog:BAABLgAECn8oAAIIAAgJmBecPwDeAQAIAAgJmBecPwDeAQAAAA==.Khrama:BAABLgAECn8WAAIKAAkJiSH6BQDFAgAKAAkJiSH6BQDFAgABLgAECggJKQACAMgkAA==.',
Ki='Kietemourt:BAAALgADCgUJBQAAAA==.Kiimachamara:BAAALgADCgIJAwAAAA==.Killik:BAAALgAECgQJBAAAAA==.Kinz:BAAALgAECgMJAwABLgABCgkJEwAEAAAAAA==.Kippili:BAAALgADCgQJBAABLgAECgYJCgAEAAAAAA==.Kiritokun:BAAALgADCgYJBAAAAA==.',
Kl='Klapz:BAAALgADCgcJDQABLgAECggJEAAEAAAAAA==.Kleenonean:BAACLgAFFH8cAAIkAAUJ6ySqCwCkAQAkAAUJ6ySqCwCkAQAuAAQKf2YAAyQACQknJscAAH0DACQACQknJscAAH0DAA4AAgnGBlV0AFcAAAAA.',
Ko='Kobe:BAAALgAFFAEJAgAAAA==.',
Kp='Kpyaccah:BAAALgAECgEJAQAAAA==.Kpyassan:BAAALgAECgYJBQAAAA==.',
Kr='Kravenn:BAAALgAECgMJAwAAAA==.Kredor:BAAALgAECgEJAQAAAA==.Kreuzritter:BAABLgAECn8zAAIYAAkJORDDCABcAgAYAAkJORDDCABcAgAAAA==.Kritterbug:BAAALgAECggJCAAAAA==.',
Ku='Kungcarefu:BAABLgAECn8bAAICAAYJQxLJRADnAAACAAYJQxLJRADnAAAAAA==.Kungfushnaz:BAAALgAECgEJAQAAAA==.Kurzaan:BAAALgAECgcJAgAAAA==.Kurzak:BAAALgAECgQJBwAAAA==.',
Ky='Kyle:BAAALgAECgEJAQABLgAFFAIJAgAEAAAAAA==.',
La='Laciel:BAAALgAECgMJBAABLgAECgkJIAAHAH0eAA==.Lacio:BAABLgAECn9HAAIkAAkJLwrhLQBqAQAkAAkJLwrhLQBqAQAAAA==.Larune:BAAALgADCgQJBwAAAA==.Lasten:BAAALgAECgEJAwAAAA==.Lavendàh:BAABLgAECn8oAAIFAAkJuCCHBQA6AwAFAAkJuCCHBQA6AwAAAA==.',
Le='Lemonite:BAACLgAFFH8UAAIPAAYJdxAyJgAqAQAPAAYJdxAyJgAqAQAuAAQKfxYAAg8ACQlwG+QUAI4CAA8ACQlwG+QUAI4CAAAA.Lennykoggins:BAABLgAECn8YAAIhAAgJLBePTQC5AQAhAAgJLBePTQC5AQAAAA==.Lexxix:BAAALgAECgUJBQAAAA==.Leyru:BAABLgAECn8sAAIFAAgJIST7BQAuAwAFAAgJIST7BQAuAwAAAA==.',
Li='Liberos:BAABLgAECn8YAAIJAAkJOBO5LQAAAgAJAAkJOBO5LQAAAgAAAA==.Lifenight:BAABLgAECn8kAAMgAAkJ6ByGBQBbAgAgAAkJ6ByGBQBbAgAHAAEJvwAGPwEJAAAAAA==.Lilnim:BAAALgAECgYJBgAAAA==.Lithvia:BAAALgAECgYJDQAAAA==.',
Ln='Lninedkhack:BAABLgAECn8mAAMHAAkJQRldNAAtAgAHAAkJQRldNAAtAgAKAAgJMQdbMgDTAAAAAA==.',
Lo='Lockdor:BAAALgAECgQJBAAAAA==.Logaar:BAABLgAECn80AAMFAAkJSxaOFgBXAgAFAAkJSxaOFgBXAgAGAAEJ7gH8zQEbAAAAAA==.Loretharan:BAAALgAECgEJAQAAAA==.Louvuitton:BAAALgADCgcJDgAAAA==.',
Lu='Luckymagi:BAAALgAECgEJAQAAAA==.Luckywizkid:BAAALgAECgYJBgAAAA==.Lunarstorm:BAAALgAECgMJAwAAAA==.Lunartsy:BAAALgADCggJDgAAAA==.Lustiel:BAAALgAECgYJDAAAAA==.Luticris:BAAALgAECgMJBAAAAA==.',
Ly='Lyoric:BAAALgAECgEJAQAAAA==.',
Ma='Madmax:BAAALgADCggJCAAAAA==.Maegot:BAAALgADCgYJBgAAAA==.Magicpants:BAAALgAECgcJCgAAAA==.Magnetto:BAAALgADCggJDQAAAA==.Maiden:BAAALgADCgUJCAABLgAECggJKgAKAAgbAA==.Malexannius:BAAALgADCgUJCQAAAA==.Mannirot:BAAALgAECgEJAQAAAA==.Mariangel:BAAALgAECgUJCQAAAA==.Marrygold:BAAALgAECgEJAgABLgAECgkJIwAHAHYfAA==.Mateus:BAAALgAECgkJDQAAAA==.Maxdeath:BAABLgAECn8lAAIHAAgJ9iO/DQAtAwAHAAgJ9iO/DQAtAwAAAA==.Mazre:BAAALgAECgQJBwAAAA==.',
Me='Megtallica:BAAALgAECggJEwAAAA==.Mendrelina:BAAALgAECgYJDAAAAA==.Mensrea:BAABLgAECn8nAAMJAAkJdxP7UwBkAQAJAAcJDhH7UwBkAQANAAgJow5dXgDJAAAAAA==.Meow:BAAALgADCgIJAgAAAA==.Merlinn:BAAALgADCgMJBgAAAA==.Merrycold:BAABLgAECn8jAAMHAAkJdh9FPABGAgAHAAcJpSFFPABGAgAKAAUJ3ROoOACxAAAAAA==.Merrygold:BAAALgADCgMJAwABLgAECgkJIwAHAHYfAA==.Merrygored:BAAALgAECgIJAgABLgAECgkJIwAHAHYfAA==.Mess:BAABLgAECn8uAAQZAAcJlB5eDwDzAQAZAAcJlB5eDwDzAQAbAAIJ3gfTlABsAAAcAAMJPQgXRwApAAABLgAECggJKgAKAAgbAA==.Methodical:BAAALgADCgUJBQAAAA==.Metophis:BAAALgAECgYJCgAAAA==.',
Mf='Mfboomstick:BAABLgAECn8/AAMYAAkJNCY3AQBZAwAYAAkJNCY3AQBZAwAMAAEJlSVVLQBhAAAAAA==.Mfgirthquake:BAABLgAFFH8GAAIaAAMJUhmLBgDwAAAaAAMJUhmLBgDwAAAAAA==.',
Mi='Miisty:BAAALgAECggJCAAAAA==.Mikklelee:BAAALgADCgIJAgAAAA==.Minerva:BAAALgADCgMJAwAAAA==.Missdebby:BAAALgADCgYJCwAAAA==.Mistweaver:BAABLgAECn8fAAIRAAkJgiDjBQBJAwARAAkJgiDjBQBJAwAAAA==.Mistweaving:BAAALgAECgcJBAAAAA==.Mistyjoe:BAAALgAECgEJAQAAAA==.Mizirath:BAAALgAECgQJBAABLgAECggJMgALAKofAA==.',
Mo='Mochi:BAAALgAECgUJBgABLgAECgkJKAASAKIaAA==.Moghorva:BAABLgAECn8fAAMmAAkJzBgdCQBYAgAmAAkJzBgdCQBYAgAjAAEJ4w0OkQA5AAAAAA==.Mojoe:BAABLgAECn8aAAIJAAcJuhRQCwBbAQAJAAcJuhRQCwBbAQAAAA==.Mommyswaggin:BAABLgAECn8VAAIOAAkJChRvHwDJAQAOAAkJChRvHwDJAQAAAA==.Moonra:BAAALgAECgEJAQAAAA==.Moopocalypse:BAAALgADCgcJDAABLgAFFAUJDQAOAFQfAA==.Moopsta:BAAALgADCggJDgABLgAFFAUJDQAOAFQfAA==.Moopster:BAACLgAFFH8NAAIOAAUJVB82DQB3AQAOAAUJVB82DQB3AQAuAAQKfzYAAw4ACQmdJbMBAJwDAA4ACQmdJbMBAJwDAAEABgnfGRsiAL0BAAAA.Moopy:BAAALgAECgQJAwABLgAFFAUJDQAOAFQfAA==.Mordekaiserz:BAAALgAECgUJCwAAAA==.Morrgoth:BAAALgADCgEJAQAAAA==.',
Mu='Mucouslurp:BAAALgADCgEJAQAAAA==.',
Na='Nalahni:BAACLgAFFH8OAAIjAAQJRQ1kOADkAAAjAAQJRQ1kOADkAAAuAAQKfyIAAiMACQmHGHoWACQCACMACQmHGHoWACQCAAAA.Nalthexon:BAAALgAECgEJAQAAAA==.Nanashi:BAAALgAECgMJAwAAAA==.Nastage:BAAALgADCgMJAQAAAA==.Nastus:BAAALgAECgMJAwAAAA==.Native:BAAALgAECgQJBAAAAA==.Nayela:BAAALgAECgYJEAAAAA==.Nazgru:BAAALgAECgEJAQAAAA==.',
Ne='Neptuneakis:BAACLgAFFH8SAAISAAMJJA5OGACqAAASAAMJJA5OGACqAAAuAAQKfy0AAxIACQk/GFEUADECABIACQk/GFEUADECAA8AAQkgFBkdADwAAAAA.Neptuno:BAAALgAECgQJDAABLgAFFAMJEgASACQOAA==.Nerfblaster:BAAALgADCgEJAQAAAA==.Newcarsmell:BAABLgAECn8UAAQFAAkJ9Q8iJADkAQAFAAgJtxEiJADkAQATAAUJMwsIMACnAAAGAAEJmAGY1AEQAAAAAA==.Newp:BAAALgAECgQJBQAAAA==.',
Ni='Nicktee:BAAALgAFFAEJAQAAAA==.Nightmares:BAAALgAECgcJCgAAAA==.Nightrvn:BAAALgAECgQJBAAAAA==.Nimfierce:BAAALgADCgkJCQAAAA==.Nimrose:BAABLgAECn8cAAIDAAkJlQb2owA0AQADAAkJlQb2owA0AQAAAA==.Niquid:BAABLgAECn8yAAIPAAkJzBe4MADfAQAPAAkJzBe4MADfAQAAAA==.',
No='Nobu:BAABLgAFFH8HAAInAAUJ6g+tAQArAQAnAAUJ6g+tAQArAQABLgAFFAUJDQAHAFQUAA==.Nolmac:BAABLgAECn8oAAIJAAkJ/SKIBgBIAwAJAAkJ/SKIBgBIAwAAAA==.Notahealer:BAABLgAFFH8LAAMOAAQJvRNpDQDLAAAOAAMJmxdpDQDLAAABAAIJ/gWgQwBtAAAAAA==.Noxloxes:BAAALgADCgcJDAAAAA==.',
Np='Npv:BAABLgAFFH8HAAIHAAIJgQ2O6ACAAAAHAAIJgQ2O6ACAAAAAAA==.',
Ny='Nyssavia:BAAALgADCgcJDgAAAA==.',
Oa='Oakshre:BAABLgAECn80AAIQAAkJnSBYBwDUAgAQAAkJnSBYBwDUAgAAAA==.',
Ob='Obliteration:BAAALgAFFAEJAgAAAA==.',
Ol='Olivertwist:BAAALgAECgQJDgABLgAFFAEJAgAEAAAAAA==.',
Om='Omnimpotent:BAAALgAECgEJAQABLgAECgIJBQAEAAAAAA==.',
On='Ontwarr:BAAALgAECgYJDQAAAA==.Ontwou:BAABLgAECn8ZAAIhAAkJRBuIIgBaAgAhAAkJRBuIIgBaAgAAAA==.',
Op='Ophi:BAAALgAECgYJEQAAAA==.',
Os='Oshaku:BAAALgAECgcJDAAAAQ==.',
Ou='Ouchpotato:BAACLgAFFH8IAAIGAAQJLBNpQwAkAQAGAAQJLBNpQwAkAQAuAAQKfxUAAgYACQlMHYIbAJ8CAAYACQlMHYIbAJ8CAAEuAAUUBgkKAAcAUwcA.',
Pa='Paarthurnax:BAABLgAFFH8MAAMjAAQJXAkUHQC8AAAjAAQJXAkUHQC8AAAoAAEJFAepDwA+AAAAAA==.Palathal:BAAALgAECgUJBgABLgAECggJGQADAPoTAA==.Pallynim:BAAALgADCgQJBwAAAA==.Palms:BAACLgAFFH8SAAIQAAYJRBjnDgBHAQAQAAYJRBjnDgBHAQAuAAQKfxgAAhAACQlDIpgHAAIDABAACQlDIpgHAAIDAAAA.Pancakezebra:BAABLgAECn8yAAIYAAkJ6RrsEAAlAgAYAAkJ6RrsEAAlAgAAAA==.Pantsftw:BAABLgAECn8fAAMOAAgJQwymNAAyAQAOAAgJ1QumNAAyAQABAAEJQQXJfQAuAAAAAA==.Papabear:BAAALgADCgUJBQAAAA==.Parkbreezy:BAABLgAECn8bAAILAAcJBwqYQgCcAAALAAcJBwqYQgCcAAAAAA==.Passera:BAABLgAECn8WAAIDAAgJvxL/FwADAQADAAgJvxL/FwADAQAAAA==.Pawg:BAAALgADCgcJBgAAAA==.',
Pe='Pebbles:BAAALgAECgcJBwAAAA==.Peltier:BAABLgAECn8sAAIDAAkJdCDLJQCFAgADAAkJdCDLJQCFAgAAAA==.Pendle:BAABLgAECn8sAAMIAAgJFA5GZAB2AQAIAAgJfg1GZAB2AQAdAAYJHQvDKQAbAQAAAA==.Perilous:BAAALgAECgIJAgABLgAFFAYJCgAHAFMHAA==.',
Ph='Phoenix:BAABLgAECn8xAAIGAAkJbB/fGgCjAgAGAAkJbB/fGgCjAgAAAA==.Phorine:BAAALgAECgEJAQAAAA==.',
Pl='Plox:BAAALgAECgYJEwAAAA==.Plugtobacca:BAABLgAFFH8FAAMQAAQJjwVFEgCQAAAQAAMJagdFEgCQAAACAAIJAACtYwAAAAABLgAFFAUJDQAHAFQUAA==.Plurnizz:BAABLgAECn8dAAMIAAkJHQhgiAApAQAIAAkJHQhgiAApAQAdAAQJEwHKXwBPAAAAAA==.',
Po='Pocketchange:BAACLgAFFH8bAAMJAAYJvBvHEQA5AQAJAAYJvBvHEQA5AQANAAIJPxzWHgChAAAuAAQKfxUAAw0ACQniGnEqAMIBAA0ABgnWHHEqAMIBAAkABgm/FzJLAFYBAAAA.',
Pr='Prowl:BAAALgAECgEJAQABLgAFFAMJBgAaAFIZAA==.',
Pu='Puffadin:BAAALgADCgEJAQAAAA==.Punybanner:BAAALgAECgEJAQAAAA==.Puppymoke:BAAALgAECgMJAwAAAA==.Puptart:BAAALgAECgUJBQAAAA==.',
Ra='Raest:BAABLgAECn8pAAICAAgJyCT8BQDdAgACAAgJyCT8BQDdAgAAAA==.Raiker:BAAALgAECgMJBAAAAA==.Ranch:BAAALgAECgEJAQAAAA==.Razzlock:BAAALgAECgEJAQAAAA==.',
Re='Regret:BAAALgAECgkJEgAAAA==.Relovan:BAABLgAECn8vAAMcAAkJ6RCEFgCnAQAcAAkJ6RCEFgCnAQAbAAUJSwOYhgClAAAAAA==.Renothidan:BAACLgAFFH8PAAIGAAQJfxrcMwBHAQAGAAQJfxrcMwBHAQAuAAQKfyMAAgYACQnZG+s4AB4CAAYACQnZG+s4AB4CAAAA.Reuben:BAAALgAECgUJBQAAAA==.Revin:BAAALgAECgcJBgAAAA==.Revrynth:BAAALgAFFAIJAgAAAA==.Rexorcist:BAACLgAFFH8JAAIGAAMJShMWLgDPAAAGAAMJShMWLgDPAAAuAAQKfxYAAgYABwkZEAwUACEBAAYABwkZEAwUACEBAAAA.',
Ri='Rickyboby:BAAALgAECggJDAAAAA==.Righteøus:BAAALgAECgUJEQAAAA==.Rillan:BAABLgAECn8aAAIGAAYJ8xbqmwA+AQAGAAYJ8xbqmwA+AQAAAA==.Rimed:BAAALgAFFAQJBAAAAA==.Rin:BAAALgAECgkJCQABLgAECgkJPwAIAEklAA==.Ripper:BAAALgAECgUJCQAAAA==.Rippèd:BAABLgAECn8iAAMdAAYJjhBOBQDqAAAdAAYJBA9OBQDqAAAIAAMJExFHGACeAAAAAA==.Rithcice:BAABLgAECn84AAMbAAkJtCbyAAB8AwAbAAkJqSbyAAB8AwAZAAcJ/yPTCABrAgAAAA==.Rizzdolphler:BAACLgAFFH8QAAIGAAQJqRR4RAAiAQAGAAQJqRR4RAAiAQAuAAQKfygAAwYACAmyHZc1ACoCAAYACAmyHZc1ACoCAAUABgktEc1CADYBAAAA.',
Ro='Roadnurse:BAAALgADCgIJAgAAAA==.Rockntroll:BAAALgADCgIJAgAAAA==.Rodah:BAAALgADCgkJEAAAAA==.Roscoee:BAAALgADCgEJAQAAAA==.Roselynt:BAAALgAECgMJAwAAAA==.',
Rs='Rsk:BAAALgADCgYJCQABLgAECggJKgAKAAgbAA==.',
Ru='Ruins:BAAALgAECgEJAQAAAA==.',
['Rà']='Ràrity:BAAALgADCggJCAAAAA==.',
['Rö']='Rönburgundy:BAACLgAFFH8NAAIIAAMJ1BEVdgDVAAAIAAMJ1BEVdgDVAAAuAAQKfy4AAggACQmNHvAdAHECAAgACQmNHvAdAHECAAAA.',
Sa='Sanako:BAABLgAECn8oAAISAAkJxxGHHwDMAQASAAkJxxGHHwDMAQAAAA==.Sanastusa:BAAALgADCgYJCAAAAA==.Saneros:BAAALgAECggJCQABLgAECggJNgAUACEZAA==.Santoniche:BAAALgAECgUJBAAAAA==.Sap:BAABLgAECn8gAAMXAAcJFxc9HwCcAQAXAAcJFxc9HwCcAQAnAAQJQguHFgDIAAABLgAECggJKgAKAAgbAA==.Sausiege:BAAALgAECgMJAwAAAA==.Saveserenade:BAAALgAECgUJBQAAAA==.',
Sc='Scarylarry:BAABLgAECn82AAIUAAgJIRmiPADVAQAUAAgJIRmiPADVAQAAAA==.Scyther:BAACLgAFFH8MAAMiAAQJbwwcFQD7AAAiAAQJMAwcFQD7AAAUAAIJRwMrjwBkAAAuAAQKfxgAAxQACQlBD8txAE8BABQACAk9DMtxAE8BACIABglZEexLAIcAAAAA.',
Sd='Sdh:BAAALgADCgQJBgAAAA==.',
Se='Seaze:BAAALgAECgUJBQAAAA==.Seishinokami:BAABLgAECn8tAAINAAkJQg1aLwCDAQANAAkJQg1aLwCDAQAAAA==.Senala:BAAALgAECgEJAQAAAA==.Serenade:BAACLgAFFH8KAAIDAAQJqBErawANAQADAAQJqBErawANAQAuAAQKfyQAAgMACAmuHxYzAKYCAAMACAmuHxYzAKYCAAAA.Setheron:BAABLgAECn8sAAIbAAkJdSG2BQAFAwAbAAkJdSG2BQAFAwAAAA==.Sethron:BAAALgAECgIJAgAAAA==.Señsei:BAAALgAECggJCwAAAA==.',
Sh='Shamminit:BAAALgAECgIJAgAAAA==.Shamtul:BAAALgAECgEJAwAAAA==.Shamwow:BAAALgADCgcJDgAAAA==.Shlea:BAACLgAFFH8XAAIjAAQJVAiuHgCxAAAjAAQJVAiuHgCxAAAuAAQKfx0AAiMACQn7EIMpAJsBACMACQn7EIMpAJsBAAAA.Shyva:BAABLgAECn8pAAMZAAgJ9SIxBwC4AgAZAAgJ9SIxBwC4AgAbAAUJ9xcFUwD/AAABLgAFFAIJAgAEAAAAAA==.',
Si='Siinestro:BAAALgAECgQJBAAAAA==.Sinlee:BAAALgAECgcJDgABLgAECgkJOgAIAEMiAA==.',
Sl='Slayla:BAAALgAECgUJDAAAAA==.Slimboyjoe:BAAALgADCgcJDgAAAA==.Slimmjim:BAAALgADCgEJAQAAAA==.Slinkstir:BAAALgADCgQJAwAAAA==.',
Sn='Snailtrails:BAAALgAECgcJBwAAAA==.Sneak:BAAALgADCgMJAwABLgAFFAMJBgAaAFIZAA==.Sneakcookies:BAAALgAECgMJBwABLgAFFAEJAgAEAAAAAA==.',
So='Soggyundies:BAAALgAECgQJBAAAAA==.Solendros:BAAALgAECgYJDwAAAA==.Sonthar:BAAALgAECgYJBgAAAA==.Soulborn:BAAALgADCgMJAwAAAA==.Soulelf:BAAALgADCgkJEQAAAA==.',
Sp='Spacehog:BAAALgAECgYJDAAAAA==.Sparticus:BAAALgAECgEJAQAAAA==.Spiro:BAAALgAECgEJAQABLgAFFAMJCwAQAMIfAA==.Splouge:BAAALgAECgYJBgAAAA==.',
St='Standarshh:BAACLgAFFH8KAAIhAAMJ5xnRLwDbAAAhAAMJ5xnRLwDbAAAuAAQKf0AAAiEACQl1IsoKAP8CACEACQl1IsoKAP8CAAAA.Stemmz:BAAALgADCgEJAQAAAA==.Stronghand:BAAALgADCgYJBwAAAA==.',
Su='Subtle:BAACLgAFFH8PAAIXAAUJiRaLGgBCAQAXAAUJiRaLGgBCAQAuAAQKfygAAxcACQnXHywNAMcCABcACQnXHywNAMcCACkABQmpBvMZAIUAAAEuAAUUBgkKAAcAUwcA.Sugarbabi:BAABLgAECn8jAAMPAAkJUh8uIQA7AgAPAAcJ3x4uIQA7AgASAAcJ1hflJwCRAQAAAA==.Sugarcube:BAAALgAECgYJBgAAAA==.Sugarqween:BAAALgAFFAEJAQAAAA==.Sugarrush:BAAALgADCgUJBQAAAA==.Sugarshot:BAAALgAECgkJCwAAAA==.Sugarthorn:BAAALgAECgIJBAAAAA==.Sugartotem:BAAALgAECgEJAQAAAA==.Sulcer:BAAALgADCgMJBAAAAA==.',
Sw='Swiftwing:BAAALgADCgYJBgAAAA==.',
Sy='Sylria:BAAALgAECgIJAgAAAA==.Sylrianah:BAABLgAECn9IAAQOAAkJ0CBcBwD5AgAOAAkJ0CBcBwD5AgAkAAkJ4QipLgBmAQABAAQJrghvWACeAAAAAA==.Sylveste:BAACLgAFFH8ZAAIFAAgJySAkCQApAgAFAAgJySAkCQApAgAuAAQKfyUAAgUACQnfGAkyAI4BAAUACQnfGAkyAI4BAAAA.Sylvfelster:BAAALgAECgYJBwABLgAFFAgJGQAFAMkgAA==.Sylánnia:BAAALgADCgcJBwAAAA==.',
Ta='Ta:BAABLgAECn8aAAIBAAcJpAgWOgAoAQABAAcJpAgWOgAoAQAAAA==.Talis:BAAALgAECgEJAQAAAA==.Tankhiskhan:BAABLgAECn8VAAIKAAgJQA3XLgDpAAAKAAgJQA3XLgDpAAAAAA==.Tarlis:BAABLgAECn8YAAIeAAgJ9xq8BAAqAgAeAAgJ9xq8BAAqAgAAAA==.',
Te='Tedrickeyjr:BAAALgAECgEJBgAAAA==.Terithresh:BAAALgADCgMJBAAAAA==.',
Th='Thanil:BAABLgAECn8wAAIGAAkJmhkrNgAoAgAGAAkJmhkrNgAoAgAAAA==.Thelliane:BAAALgAECgIJAgABLgAFFAYJIwAJAFcTAA==.Thenet:BAAALgAECgEJAwAAAA==.',
Ti='Tie:BAABLgAECn8bAAITAAgJ5hWTAgC7AQATAAgJ5hWTAgC7AQAAAA==.Tikamancer:BAAALgADCgEJAQAAAA==.Tilvalhalla:BAABLgAECn8cAAImAAcJPAogKgAhAQAmAAcJPAogKgAhAQAAAA==.Tin:BAAALgAECgEJAQAAAA==.',
To='Todorokii:BAAALgAECgUJDQAAAA==.Tom:BAAALgAECgEJAgABLgAFFAIJAgAEAAAAAA==.Torrin:BAAALgADCgYJBwAAAA==.Tortaa:BAAALgAECgUJBQAAAA==.Tortricid:BAAALgAECgcJDgAAAA==.Totaldchtree:BAAALgAECgEJAQAAAA==.Totempants:BAAALgAECgYJBgAAAA==.Totinospizza:BAAALgADCgYJBgAAAA==.',
Tr='Trashkan:BAAALgADCgIJAgAAAA==.Trauck:BAAALgADCgEJAQAAAA==.Traumzi:BAAALgAECgEJAQAAAA==.Travvy:BAACLgAFFH9gAAMXAAkJMCUoAAB4AwAXAAkJbSQoAAB4AwAnAAIJoR6xDABqAAAuAAQKfyIAAhcACQkWJgEBAMMDABcACQkWJgEBAMMDAAAA.Treezus:BAAALgADCgYJCAAAAA==.Trevmo:BAABLgAECn82AAIZAAkJGyCEBgCjAgAZAAkJGyCEBgCjAgAAAA==.Trexin:BAAALgAECggJEAAAAA==.',
Tu='Turaylon:BAAALgAFFAEJAQAAAA==.Turtlebox:BAAALgAECgQJBgAAAA==.',
Ty='Tym:BAAALgAFFAIJAgAAAA==.',
Tz='Tzuyu:BAAALgAFFAEJAgAAAA==.',
Ug='Ugargro:BAABLgAECn8XAAQZAAUJIQhaOQCPAAAZAAUJOwdaOQCPAAAbAAIJJwSJsgAkAAAcAAEJcggzGQAiAAAAAA==.',
Un='Unapologetic:BAAALgAECggJDAAAAA==.Unbreakabull:BAABLgAFFH8SAAISAAYJ2yIkDwCwAQASAAYJ2yIkDwCwAQAAAA==.Unceejin:BAAALgADCggJEQAAAA==.Unholydk:BAABLgAECn8qAAMKAAgJCBv6DwAMAgAKAAgJCBv6DwAMAgAHAAUJsw+I5wDLAAAAAA==.',
Va='Valcuna:BAAALgAECgQJBQAAAA==.Valka:BAABLgAECn8YAAIfAAkJUgkoGgA8AQAfAAkJUgkoGgA8AQAAAA==.Vamptouch:BAAALgAECgIJAwABLgAFFAMJBgAaAFIZAA==.Vanaan:BAAALgAECgIJAgABLgAECgYJBwAEAAAAAA==.Varidrus:BAAALgAECgQJBQAAAA==.Vaste:BAAALgADCgcJCQAAAA==.',
Ve='Venomlight:BAAALgAECgcJBwAAAA==.Ventrue:BAABLgAECn8jAAIDAAkJ6xWVXgDEAQADAAkJ6xWVXgDEAQAAAA==.Veyle:BAABLgAECn8/AAMXAAkJ1yRiBQDdAgAXAAkJ1yRiBQDdAgAnAAEJKh7AGwBJAAAAAA==.',
Vi='Vivian:BAABLgAECn8xAAIiAAkJfRrgCgB6AgAiAAkJfRrgCgB6AgABLgAFFAMJCwAQAMIfAA==.Vixèn:BAAALgAECgEJAQAAAA==.',
Vo='Voidsurge:BAABLgAECn8yAAQVAAcJmBl1DACPAQAVAAcJUxZ1DACPAQAiAAUJMxsfKAA7AQAUAAUJ+hGwsQDFAAABLgAECggJKgAKAAgbAA==.',
Vy='Vyel:BAAALgAECgQJBAAAAA==.Vyndria:BAAALgAECgYJEQAAAA==.',
Wa='Wardell:BAAALgAECgQJCAAAAA==.',
We='Weashock:BAAALgAFFAIJAgAAAA==.Weaspore:BAABLgAECn8hAAIHAAgJlR7IQgD6AQAHAAgJlR7IQgD6AQAAAA==.Weasy:BAAALgAECgkJDgAAAA==.',
Wi='Windfury:BAAALgAFFAMJAwAAAA==.',
Wo='Woogidaboogi:BAAALgAECgIJBQAAAA==.Woogieboogie:BAAALgAECgEJAQABLgAECgIJBQAEAAAAAA==.',
Xi='Xiamiel:BAAALgADCgYJCQAAAA==.',
Xl='Xl:BAABLgAECn9WAAMiAAgJ/RxVCwCrAgAiAAgJhxxVCwCrAgAUAAgJJxZWRQC3AQAAAA==.',
Ya='Yaitoopmfp:BAAALgAECgIJBAABLgAECgkJIwAHAHYfAA==.Yao:BAAALgAECgIJAgABLgAFFAMJCgAZAPUZAA==.',
Yh='Yharnem:BAABLgAECn8XAAICAAcJ8hBWLgBMAQACAAcJ8hBWLgBMAQAAAA==.',
Yo='Yogurtpants:BAAALgAECgYJEgAAAA==.Yonny:BAAALgADCgEJAQAAAA==.',
Yu='Yukionna:BAAALgADCgcJCwAAAA==.',
Za='Zabara:BAABLgAECn8dAAIJAAkJrh+tCwD/AgAJAAkJrh+tCwD/AgAAAA==.Zabbystabby:BAAALgADCgkJDgAAAA==.Zakaraki:BAABLgAECn8+AAQoAAkJhCWoAAA8AwAoAAkJhCWoAAA8AwAjAAcJNyEPGQAOAgAmAAcJTAd5JgBBAQAAAA==.Zaki:BAABLgAECn8aAAIUAAkJThqHIwBCAgAUAAkJThqHIwBCAgAAAA==.Zanked:BAAALgADCgQJBAAAAA==.Zarkingu:BAAALgADCgMJAwAAAA==.',
Ze='Zealot:BAAALgAFFAEJAQAAAA==.Zeleria:BAAALgAECgUJBgAAAA==.Zeno:BAAALgAFFAIJAgAAAA==.Zephyr:BAAALgAECgQJBAAAAA==.Zerathis:BAABLgAECn86AAIIAAkJQyLSDgDWAgAIAAkJQyLSDgDWAgAAAA==.Zerathül:BAAALgAECgcJEgAAAA==.Zerötwo:BAAALgADCgkJCgAAAA==.Zestul:BAAALgADCgkJFgAAAA==.',
Zi='Zimbobayaga:BAAALgAECgMJAwAAAA==.Zip:BAAALgAECgQJBAAAAA==.',
Zo='Zodivine:BAAALgADCgMJAwAAAA==.Zohar:BAAALgADCgEJAgAAAA==.Zooty:BAAALgADCgUJAwAAAA==.Zoshow:BAAALgAFFAIJAgAAAA==.',
Zu='Zuggo:BAAALgADCgYJBgAAAA==.',
Zy='Zyrig:BAAALgAECgcJDAAAAA==.',
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
