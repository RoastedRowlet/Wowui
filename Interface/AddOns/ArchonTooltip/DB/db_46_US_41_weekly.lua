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

local lookup = {'Priest-Discipline','Warlock-Demonology','Monk-Brewmaster','Mage-Frost','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Shaman-Restoration','DeathKnight-Blood','Druid-Guardian','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Elemental','Priest-Holy','Druid-Restoration','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Fire','DemonHunter-Havoc','Rogue-Subtlety','Hunter-Survival','Warrior-Protection','Shaman-Enhancement','Warrior-Fury','Warrior-Arms','Warlock-Destruction','Warlock-Affliction','Druid-Feral','DeathKnight-Frost','Evoker-Augmentation','Priest-Shadow','Mage-Arcane','Evoker-Preservation','Rogue-Assassination','Evoker-Devastation','Rogue-Outlaw',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=46,date='2026-08-25',data={Aa='Aahzbear:BAAALgAFFAEJAQAAAA==.',
Ab='Abreale:BAAALgADCgMJAwAAAA==.Abruum:BAAALgADCgcJBwAAAA==.',
Ae='Aeero:BAABLgAECn8UAAIBAAYJNhfEHwCWAQABAAYJNhfEHwCWAQAAAA==.Aerendyl:BAAALgAECgcJCwABLgAECgkJOgACAEMiAA==.',
Ai='Aiden:BAACLgAFFH8HAAIDAAMJbRAgOwC6AAADAAMJbRAgOwC6AAAuAAQKfxQAAgMABgkfHF8qALcBAAMABgkfHF8qALcBAAAA.',
Al='Algros:BAAALgADCgEJAQAAAA==.Alilitha:BAAALgADCgYJDAAAAA==.Alternative:BAAALgAECgUJBwAAAA==.Alyiriia:BAAALgAECgkJCQAAAA==.',
Am='Amathal:BAABLgAECn8ZAAIEAAgJ+hMTjABfAQAEAAgJ+hMTjABfAQAAAA==.Amazon:BAAALgAECgIJBQAAAA==.Amilea:BAAALgAFFAEJAQABLgABCgkJEwAFAAAAAA==.',
An='Anastasia:BAAALgADCggJCAAAAA==.Angelsevoker:BAAALgAECggJCAAAAA==.Angermoonria:BAAALgADCgcJBwAAAA==.Ankheloios:BAAALgAECgUJBQAAAA==.Antihiiro:BAAALgAECgMJAwAAAA==.Antipro:BAAALgAFFAEJAQAAAA==.Anubbus:BAABLgAFFH8GAAIEAAMJWwP6lACoAAAEAAMJWwP6lACoAAAAAA==.Anzulok:BAAALgADCgYJAQAAAA==.',
Ar='Arbalest:BAAALgADCgcJBgAAAA==.Aredhela:BAABLgAECn8nAAMGAAkJyxUVGQA+AgAGAAkJyxUVGQA+AgAHAAYJOBpHFAA9AQAAAA==.Arinth:BAAALgADCggJEQAAAA==.Arkadios:BAAALgAECgIJAgAAAA==.Armpit:BAAALgAECgMJAwAAAA==.Armsdealer:BAAALgADCgEJAQAAAA==.',
As='Ascanius:BAAALgAECgEJAQABLgAECgQJBAAFAAAAAA==.Ashiiro:BAAALgAECgcJEAAAAA==.Ashveil:BAAALgAECgUJBQABLgAECgkJJgAIAEEZAA==.Asia:BAABLgAECn8/AAICAAkJSSW8BQA1AwACAAkJSSW8BQA1AwAAAA==.Asmodeius:BAAALgAFFAEJAgAAAA==.Astroprof:BAAALgAECgEJAQABLgAECgYJFQAJAFsaAA==.',
At='Ataxia:BAAALgAFFAEJAQAAAA==.Athrea:BAABLgAECn8gAAMIAAkJfR5VFQDHAgAIAAkJ3B1VFQDHAgAKAAUJUBu/JQAlAQAAAA==.',
Au='Auntjemima:BAAALgAECgEJAgAAAA==.Aureleus:BAAALgADCgEJAQAAAA==.',
Aw='Away:BAAALgADCgIJAgAAAA==.',
Az='Azaii:BAAALgADCggJCgAAAA==.Azlear:BAAALgAECgkJBgAAAA==.Azrael:BAAALgAECgkJBwAAAA==.',
Ba='Babilouchoux:BAAALgAECgMJBQAAAA==.Badomen:BAAALgAECgEJAQAAAA==.Ballz:BAAALgADCgYJBgAAAA==.Bano:BAAALgAECgMJAwAAAA==.Barnre:BAAALgAECgcJCgAAAA==.Bash:BAABLgAECn8VAAILAAcJ6hMwHQBkAQALAAcJ6hMwHQBkAQABLgAECggJKgAKAAgbAA==.Batzab:BAAALgAECgEJAQABLgAECgkJIwAJAK4fAA==.Baythos:BAAALgAFFAEJAgAAAA==.',
Bb='Bb:BAAALgAECgIJAQAAAA==.',
Bd='Bdssm:BAAALgAFFAIJAgAAAA==.',
Be='Bearito:BAAALgAFFAMJBAAAAA==.Bearockobama:BAAALgAFFAEJAQABLgAFFAYJGwAJALwbAA==.Beefstick:BAABLgAFFH8HAAIMAAMJkBHvLgDoAAAMAAMJkBHvLgDoAAAAAA==.Berzercarl:BAAALgAECgEJAQAAAA==.Beserkfury:BAABLgAECn8nAAINAAkJjRCrDgBzAQANAAkJjRCrDgBzAQAAAA==.',
Bh='Bhemtu:BAAALgAECgEJAQAAAA==.',
Bi='Biercan:BAAALgAECggJEAAAAA==.Bigcarl:BAAALgADCgMJAwAAAA==.Binke:BAABLgAECn8wAAIOAAkJZA4yDAAFAQAOAAkJZA4yDAAFAQAAAA==.Bittywhite:BAAALgAECgcJDwAAAA==.Bittywyvern:BAAALgADCgUJCwABLgAECgcJDwAFAAAAAA==.',
Bl='Blayze:BAABLgAECn8eAAIPAAkJ5hPQGQD8AQAPAAkJ5hPQGQD8AQAAAA==.Blessidbee:BAAALgAECgEJAQAAAA==.Blightmarx:BAAALgADCgUJCQAAAA==.Blitzwow:BAAALgADCgYJBQAAAA==.Blondpistol:BAAALgADCgMJAwAAAA==.Bluemoonflay:BAAALgAECgkJEwAAAA==.Blúnt:BAAALgADCgQJBAAAAA==.',
Bo='Bobakat:BAAALgAECgEJAQAAAA==.Bobheals:BAABLgAECn82AAMQAAkJkhslAgCPAgAQAAkJkhslAgCPAgALAAEJAAB5lQAAAAAAAA==.Boibye:BAAALgAECgYJDgAAAA==.Bolblock:BAAALgAECgkJDwAAAA==.Bonewolf:BAAALgAECgQJBAAAAA==.Boostedww:BAAALgAFFAEJAwAAAA==.Boostie:BAAALgAECgEJAgAAAA==.',
Br='Brambleclaw:BAABLgAECn8/AAIKAAkJRSPFBADjAgAKAAkJRSPFBADjAgAAAA==.Brayker:BAACLgAFFH8KAAIHAAIJ3iGtMgDFAAAHAAIJ3iGtMgDFAAAuAAQKf0cAAgcACQmjJSAGAEEDAAcACQmjJSAGAEEDAAAA.Breadoneal:BAABLgAECn8pAAMGAAkJ4hkEHwAKAgAGAAgJ9hgEHwAKAgAHAAEJ7QURvwEkAAAAAA==.Breeze:BAAALgAECgYJBgAAAA==.Brewed:BAABLgAECn80AAMRAAkJPRRrHADLAQARAAkJPRRrHADLAQASAAEJLwEG4QALAAAAAA==.Brisketbane:BAAALgAECgcJEAAAAA==.Brokenmask:BAACLgAFFH8qAAMQAAgJhB1uBABfAgAQAAgJhB1uBABfAgALAAEJgAnyLwApAAAuAAQKfxUAAxAACAkOIEobAGECABAACAkOIEobAGECABMAAgkLESeOADIAAAAA.Broxxar:BAAALgAECgIJAgAAAA==.Bruxxe:BAAALgAECgcJAQAAAA==.Brynjamin:BAAALgAECgYJBgAAAA==.Brüenor:BAAALgAECgIJAgAAAA==.',
Bu='Burntroot:BAABLgAECn8yAAIOAAkJ/QdARAAiAQAOAAkJ/QdARAAiAQAAAA==.',
['Bá']='Bálor:BAAALgAECgEJAgABLgAECgYJDAAFAAAAAA==.',
Ca='Caedwyn:BAABLgAECn8yAAILAAgJqh8UCABuAgALAAgJqh8UCABuAgAAAA==.Caitrakk:BAABLgAECn8VAAMJAAYJWxqgMgC7AQAJAAYJWxqgMgC7AQAOAAUJYhC9TAAVAQAAAA==.Calignus:BAABLgAECn8dAAMHAAgJyRG+rwAfAQAHAAgJyRG+rwAfAQAUAAUJVQ8jJwDQAAAAAA==.Captjack:BAABLgAECn8dAAIVAAkJrAs3aQBTAQAVAAkJrAs3aQBTAQAAAA==.Cartilage:BAABLgAECn8lAAIIAAkJXRQRRAD2AQAIAAkJXRQRRAD2AQAAAA==.Catalei:BAAALgAECgYJDwAAAA==.Caution:BAAALgADCgYJCwAAAA==.',
Ce='Cela:BAAALgAECgEJAQAAAA==.Celira:BAAALgAECgEJAQAAAA==.Celys:BAAALgAECgIJAgAAAA==.',
Ch='Chebbles:BAAALgAECgEJAQABLgAFFAMJEgATACQOAA==.Chickenman:BAAALgAECgEJAQAAAA==.Chillidan:BAAALgAECgQJBwABLgAFFAEJAgAFAAAAAA==.Chiselia:BAAALgADCgUJBQABLgAECgcJCgAFAAAAAA==.Choconilla:BAAALgAECgcJEwAAAA==.Chonkmonk:BAAALgADCgQJBAAAAA==.Choppa:BAAALgADCggJCgAAAA==.Chorizo:BAAALgAECgEJAQABLgAECgkJHwASAIIgAA==.Chupacabrass:BAAALgADCgYJBgAAAA==.Chëbbles:BAAALgAECgEJAwABLgAFFAMJEgATACQOAA==.',
Ci='Cinnomun:BAAALgADCgEJAQAAAA==.',
Co='Combustinme:BAAALgAECgQJBAABLgAECggJNgAVACEZAA==.Consuming:BAABLgAECn8tAAIQAAkJpRPIMADeAQAQAAkJpRPIMADeAQAAAA==.Coorsbanquet:BAABLgAECn8bAAMWAAkJvhcNBwAYAgAWAAkJvhcNBwAYAgAVAAIJuAmuPAArAAAAAA==.Coorsbite:BAAALgAECgcJCQABLgAECgkJGwAWAL4XAA==.Corgh:BAABLgAECn8kAAIXAAYJtw4XBgBIAQAXAAYJtw4XBgBIAQAAAA==.Corrahthecow:BAAALgADCgEJAQABLgAECgkJGwAWAL4XAA==.Cowardice:BAAALgADCgYJCwAAAA==.',
Cr='Craccjar:BAAALgAECgUJEgAAAA==.Crackjar:BAAALgADCgcJDAAAAA==.Crash:BAACLgAFFH8UAAIVAAgJUBeVHwC6AQAVAAgJUBeVHwC6AQAuAAQKfz8ABBUACQkLJbUNANgCABUACQkLJbUNANgCABgAAQkQG9sbAE4AABYAAQkwGbYwAEAAAAAA.Croarik:BAAALgAECgEJAQAAAA==.Crushix:BAABLgAECn81AAIGAAkJKhhHHwAfAgAGAAkJKhhHHwAfAgAAAA==.',
Cs='Csyasha:BAAALgAECgYJCQAAAA==.',
Cu='Cubcadet:BAAALgAFFAEJAQAAAA==.',
Cy='Cybear:BAAALgAFFAMJAwAAAA==.Cykun:BAABLgAECn8uAAIZAAkJcSDiCACXAgAZAAkJcSDiCACXAgAAAA==.',
['Cã']='Cãs:BAAALgADCgkJCgABLgAECgkJGgAQALQNAA==.',
Da='Dammned:BAAALgAECgUJBQAAAA==.Darch:BAABLgAECn8/AAMaAAkJMCT6AwDyAgAaAAkJMCT6AwDyAgANAAEJPwm2kAAqAAAAAA==.Davidx:BAAALgAFFAEJAQAAAA==.',
De='Deadgripz:BAAALgADCgMJBgAAAA==.Deadjaden:BAAALgADCgEJAQAAAA==.Deadlos:BAAALgAECgUJCAAAAA==.Deathscreams:BAAALgAECgQJBgAAAA==.Deathxreaper:BAAALgAECgQJCwAAAA==.Decessus:BAAALgAECgUJBgAAAA==.Dekig:BAACLgAFFH8NAAIIAAQJHA9NNAADAQAIAAQJHA9NNAADAQAuAAQKfyUAAggACAmLFdFYALsBAAgACAmLFdFYALsBAAAA.Delbert:BAAALgADCgYJBgAAAA==.Demine:BAABLgAECn89AAIEAAkJpx/jHACvAgAEAAkJpx/jHACvAgAAAA==.Demonvibe:BAAALgAFFAEJAQAAAA==.',
Di='Dico:BAAALgAECgIJAgABLgAFFAkJJgAbAP0cAA==.Dinobots:BAAALgAECgYJDAAAAA==.Dipper:BAABLgAECn8cAAIHAAkJExrSPAARAgAHAAkJExrSPAARAgAAAA==.Divinator:BAAALgAECgYJDQAAAA==.',
Do='Donbarriga:BAAALgAECgYJCAAAAA==.Dosmojitos:BAAALgADCgcJBwAAAA==.Doublejumps:BAAALgAFFAEJAQABLgAFFAMJBgAcAFIZAA==.Doublelung:BAAALgAECgYJEgAAAA==.',
Dr='Draagone:BAAALgADCgUJBQABLgAECgcJCgAFAAAAAA==.Draekeneyez:BAAALgAECgEJAQAAAA==.Drdiddles:BAAALgAECgMJAwAAAA==.',
Du='Duney:BAACLgAFFH8OAAMdAAQJjhPhIgAoAQAdAAQJuhDhIgAoAQAeAAMJVhTcJQDWAAAuAAQKf1oAAx4ACQnRIOcEAMQCAB4ACQm3H+cEAMQCAB0ACAnvH50NAJUCAAAA.Dußad:BAAALgAECgMJBwAAAA==.',
['Dé']='Déäth:BAAALgADCgQJBAAAAA==.',
Ec='Eckoe:BAABLgAECn8gAAIQAAcJKwaHdQDVAAAQAAcJKwaHdQDVAAAAAA==.',
Ee='Eekeros:BAAALgADCgUJBQAAAA==.Eeveeko:BAACLgAFFH8ZAAIcAAUJZRKWBwDpAAAcAAUJZRKWBwDpAAAuAAQKfzsAAhwACQkcH6MGAG4CABwACQkcH6MGAG4CAAAA.',
Ej='Ejavuday:BAABLgAECn8wAAIEAAkJPSIBGADJAgAEAAkJPSIBGADJAgAAAA==.',
El='Elvudu:BAAALgAECgQJBwAAAA==.',
Em='Emberstrife:BAAALgAECgEJAgAAAA==.',
En='Enerchi:BAABLgAECn8UAAMSAAYJ4xbqTwAvAQASAAUJZRTqTwAvAQARAAMJ1SLFNQArAQABLgAFFAEJAgAFAAAAAA==.Enterunder:BAAALgADCgMJAwAAAA==.',
Er='Erazath:BAAALgAECgQJCAAAAA==.Erianar:BAAALgAECgMJAwAAAA==.Ericdruid:BAABLgAECn8aAAMTAAcJSiD3EgB+AgATAAcJSiD3EgB+AgAQAAEJ6QqZ1gAqAAAAAA==.Ericlock:BAAALgADCgMJAwAAAA==.',
Es='Essia:BAAALgAECgEJAQAAAA==.',
Ev='Eveko:BAAALgADCgIJAQAAAA==.Evera:BAABLgAECn8xAAIIAAkJ6gQnpwAhAQAIAAkJ6gQnpwAhAQAAAA==.Everlst:BAAALgADCgEJAQAAAA==.Eviljerk:BAAALgAECgIJAgAAAA==.Evokinpants:BAAALgAECgcJDwAAAA==.Evos:BAAALgAECgQJBgAAAA==.',
Ex='Excels:BAACLgAFFH8QAAIQAAMJShtMNADcAAAQAAMJShtMNADcAAAuAAQKfysAAhAACQnSIhEEAH4DABAACQnSIhEEAH4DAAAA.Explicatory:BAAALgAECgYJBwABLgAFFAMJEAAQAEobAA==.',
Ey='Eyllion:BAAALgAECgUJCwAAAA==.',
Fa='Falorin:BAAALgADCgMJAwAAAA==.Fastoris:BAAALgADCgEJAQAAAA==.Fauci:BAACLgAFFH8NAAIIAAUJVBSihAD/AAAIAAUJVBSihAD/AAAuAAQKfyAAAggACQmsIHsgAIcCAAgACQmsIHsgAIcCAAAA.Faunaa:BAAALgAECgMJBQAAAA==.',
Fb='Fblthelost:BAAALgAECgMJAwAAAA==.',
Fe='Feihao:BAAALgADCggJFQAAAA==.Feile:BAABLgAECn82AAQCAAkJxhfrMwAJAgACAAkJxhfrMwAJAgAfAAIJfgu/VwBnAAAgAAEJAAD1LwA+AAAAAA==.Fenty:BAAALgAECgUJBQABLgAECggJNgAVACEZAA==.Feshh:BAAALgADCgEJAQAAAA==.',
Fi='Fifezilla:BAAALgAECgIJAgAAAA==.Firble:BAAALgADCgYJBgAAAA==.Fireg:BAAALgADCgEJAQABLgAFFAQJBQAEADULAA==.Fistbeaver:BAAALgADCgUJBQAAAA==.',
Fl='Flinzza:BAAALgAECgYJCwAAAA==.Flyknit:BAAALgAECgMJAwAAAA==.Flökki:BAAALgAECgEJAQABLgAFFAMJAQAFAAAAAA==.',
Fo='Foolezz:BAAALgAECgMJBAAAAA==.',
Fr='Fredthedh:BAABLgAECn8cAAIVAAkJZSFUFADeAgAVAAkJZSFUFADeAgAAAA==.Freshjordans:BAAALgAECgEJAQABLgAFFAMJBgAcAFIZAA==.Fromtheback:BAAALgAECgYJDgABLgAFFAIJBQAIAK4VAA==.',
Fu='Furble:BAAALgADCgYJBgAAAA==.',
Ga='Gaashw:BAAALgAECgIJBgAAAA==.Gadziila:BAAALgADCgEJAQAAAA==.Galcyon:BAAALgADCgEJAQAAAA==.Galiant:BAABLgAECn8mAAIIAAkJ/SNiFwC6AgAIAAkJ/SNiFwC6AgAAAA==.Gammilite:BAAALgAECgUJCAAAAA==.Gandelf:BAAALgADCgUJBQAAAA==.Gashdk:BAAALgAECgEJAQABLgAECgIJBgAFAAAAAA==.Gator:BAAALgAECgEJAQAAAA==.Gaulish:BAAALgADCgkJCQAAAA==.',
Ge='Geraldo:BAAALgAECgIJAgAAAA==.Getagrip:BAABLgAFFH8KAAIIAAYJUwcAKQAvAQAIAAYJUwcAKQAvAQAAAA==.Gethalyn:BAABLgAECn8XAAIHAAcJCRGpmQBCAQAHAAcJCRGpmQBCAQAAAA==.Gexz:BAAALgADCgYJDAAAAA==.',
Gh='Ghee:BAAALgAECgEJAgAAAA==.Ghume:BAAALgAECgUJBQAAAA==.',
Gi='Gianthippo:BAAALgAECgcJEgAAAA==.',
Gl='Glaivedaddy:BAAALgAECgEJAQAAAA==.Glenlives:BAAALgADCgkJCgABLgAECgkJLQAOAEINAA==.',
Go='Gore:BAAALgAECgUJBQAAAA==.Gottverdammt:BAAALgAECgEJAQABLgAECgkJEAAFAAAAAA==.',
Gr='Graveknight:BAAALgAECgMJAwAAAA==.Graveshot:BAAALgADCgQJBAAAAA==.Greennrry:BAAALgAFFAEJAQABLgAFFAMJCAAhANsYAA==.Greennrryy:BAABLgAFFH8FAAIaAAEJ3yRGGQBKAAAaAAEJ3yRGGQBKAAABLgAFFAMJCAAhANsYAA==.Greenryy:BAAALgAECgIJAwABLgAFFAMJCAAhANsYAA==.Greyskin:BAAALgADCgEJAQAAAA==.Grizzabella:BAABLgAECn86AAIQAAkJQBw7EADQAgAQAAkJQBw7EADQAgAAAA==.Grreenry:BAABLgAFFH8IAAIhAAMJ2xhpDADvAAAhAAMJ2xhpDADvAAABLgAFFAMJCAAhANsYAA==.Grriz:BAAALgADCgEJAQAAAA==.Grtmustachio:BAAALgAECgkJEAAAAA==.Grumly:BAAALgAECgcJCwAAAA==.Grundle:BAAALgAECgMJAwAAAA==.',
Gu='Gularak:BAAALgAECgQJBgAAAA==.Gunghø:BAAALgADCggJDwAAAA==.Gurbosc:BAAALgADCgYJBgABLgAECgkJMgAOAP0HAA==.',
Gy='Gyutaro:BAAALgADCgEJAQAAAA==.',
Ha='Haelellionys:BAAALgADCgQJBAAAAA==.Hamms:BAAALgAECgYJBwABLgAECgkJGwAWAL4XAA==.Hanamae:BAAALgADCgEJAQAAAA==.Hangnail:BAAALgAECgIJBAAAAA==.Hanswoloqued:BAACLgAFFH8VAAMgAAQJzAdICgCAAAACAAQJswfBMQDAAAAgAAIJRgZICgCAAAAuAAQKfxsAAwIACQmoC9ttAGABAAIACQmoC9ttAGABACAAAgmmAQ0qAEsAAAAA.Harmfuljoker:BAAALgADCgQJBAAAAA==.Haussmann:BAAALgAECgEJAQABLgAFFAgJGQAGAMkgAA==.Haxzen:BAAALgADCgMJBAAAAA==.',
He='Healufast:BAABLgAECn9EAAIPAAkJMR4PBwAAAwAPAAkJMR4PBwAAAwAAAA==.Helediriel:BAABLgAFFH8KAAIiAAQJCAzeCQD9AAAiAAQJCAzeCQD9AAAAAA==.Hellsong:BAAALgAECgMJAwABLgAECgYJBgAFAAAAAA==.Helstrom:BAABLgAECn8bAAIHAAcJmwxWHAD9AAAHAAcJmwxWHAD9AAAAAA==.Hendo:BAAALgADCgYJBgAAAA==.Hendoh:BAAALgAECggJDgAAAA==.Hendosan:BAAALgAECgIJAwAAAA==.Hendou:BAAALgAECgEJAwAAAA==.Heysisters:BAAALgAECgIJAwAAAA==.',
Hi='Hispeas:BAAALgADCgQJBwAAAA==.Hitchkawk:BAAALgAECgEJAQAAAA==.Hitchlock:BAAALgAECgEJAwAAAA==.',
Hj='Hjalmar:BAAALgAECgYJEAABLgAECgkJIwAJAK4fAA==.',
Ho='Holysabeline:BAACLgAFFH8KAAIGAAIJYxnNGACUAAAGAAIJYxnNGACUAAAuAAQKf0gAAgYACQlpGtsTAHACAAYACQlpGtsTAHACAAAA.Honestleon:BAAALgADCgMJAwABLgAECgcJFgAHAHgTAA==.Hordechief:BAAALgAFFAIJAgAAAA==.',
Ht='Htpktbhole:BAAALgADCgMJAwAAAA==.',
Hu='Huchar:BAABLgAECn9EAAMbAAkJ3SJ0AwD9AgAbAAkJ3SJ0AwD9AgAdAAEJmgzFqAAtAAAAAA==.Huevos:BAAALgAECgIJAwABLgAFFAgJJQAIAF8eAA==.Huntersteve:BAABLgAECn8hAAMMAAgJQCOoCAAIAwAMAAgJQCOoCAAIAwANAAYJ7CAfIwANAgAAAA==.',
Hy='Hydraxix:BAAALgAECgYJDgAAAA==.',
['Hô']='Hônk:BAAALgADCgEJAQABLgAECgkJLQAOAEINAA==.',
Ia='Iamanopcow:BAAALgADCgQJBAAAAA==.Iamspeed:BAAALgADCgQJBAAAAA==.',
Ib='Ibuprofen:BAAALgAECgIJBgAAAA==.',
Ic='Iceblade:BAABLgAECn8oAAIGAAkJxxf2HwAaAgAGAAkJxxf2HwAaAgAAAA==.',
Ie='Ieatbabys:BAAALgADCgUJBQAAAA==.',
If='If:BAAALgAECgMJAwAAAA==.',
Ih='Ihideuseek:BAAALgAECgYJDwABLgAECgkJMAAEAD0iAA==.',
Ii='Iityouup:BAAALgADCgYJCAAAAA==.',
Il='Illidaniella:BAABLgAECn8aAAMVAAkJZAkWggAcAQAVAAgJmQgWggAcAQAYAAEJ7Q6wIgA2AAAAAA==.Illsmurfuup:BAABLgAECn8ZAAIaAAkJ9SZoAACnAwAaAAkJ9SZoAACnAwAAAA==.Iluminatus:BAAALgAECgQJBAAAAA==.',
In='Indacouch:BAAALgADCgEJAQAAAA==.Infection:BAAALgADCgYJCAAAAA==.Inverse:BAAALgADCgYJBgAAAA==.',
Ir='Ironßest:BAABLgAECn8hAAIMAAcJdxC1bABoAQAMAAcJdxC1bABoAQAAAA==.Irôh:BAAALgAECgEJAQABLgAECgUJHAAYAK4fAA==.',
Is='Ishmael:BAAALgADCgEJAQAAAA==.',
It='Itswaymil:BAAALgAECgEJAQAAAA==.',
Iv='Ivannas:BAAALgAECgMJBgAAAA==.',
Ja='Jaabroni:BAAALgADCgIJAgAAAA==.Jackymoon:BAABLgAECn8aAAIHAAgJXCP9HgCNAgAHAAgJXCP9HgCNAgAAAA==.Jaxxion:BAAALgAECgEJAwAAAA==.',
Jd='Jdawg:BAABLgAECn8/AAIcAAkJQiUNAQA9AwAcAAkJQiUNAQA9AwAAAA==.',
Je='Jer:BAAALgADCgYJBgAAAA==.Jessaiyan:BAABLgAECn8sAAIVAAkJKyIvCQADAwAVAAkJKyIvCQADAwAAAA==.',
Ji='Jindo:BAAALgADCgcJBwAAAA==.Jiuni:BAAALgADCgUJBQAAAA==.',
Jj='Jjcjr:BAAALgAFFAIJBAABLgAFFAkJLQAjAAodAA==.',
Ju='Julaidan:BAAALgAECgQJBgAAAA==.Julaudette:BAABLgAECn8jAAIgAAYJDQmyGQDzAAAgAAYJDQmyGQDzAAAAAA==.Juliania:BAAALgAECgYJCAAAAA==.Julzaria:BAABLgAECn89AAIMAAkJ4xNxDgCLAQAMAAkJ4xNxDgCLAQAAAA==.Julzoblin:BAABLgAECn8YAAIkAAYJPwf+FACVAAAkAAYJPwf+FACVAAAAAA==.Jurny:BAABLgAECn81AAMfAAkJHBM4AgCtAQAfAAgJWBQ4AgCtAQAgAAgJMQ1hBgDiAAAAAA==.Jusdeen:BAABLgAECn8YAAMLAAkJtiKGBgCVAgALAAgJGSKGBgCVAgAQAAMJvA8bmgB9AAAAAA==.',
Ka='Kadookieii:BAAALgAFFAEJAQAAAA==.Kahlandra:BAABLgAECn83AAMlAAkJChuGAgAoAgAlAAkJChuGAgAoAgAEAAgJ9Qz4kQBUAQAAAA==.Kairoz:BAABLgAECn8UAAMBAAYJFxeHJgCcAQABAAYJFxeHJgCcAQAkAAIJ9A4qbgBoAAABLgAFFAEJAgAFAAAAAA==.Kaizer:BAACLgAFFH8WAAIOAAUJNRM7JgD9AAAOAAUJNRM7JgD9AAAuAAQKfykAAg4ACAlBHd4YAE0CAA4ACAlBHd4YAE0CAAAA.Kalo:BAAALgAECgMJAwAAAA==.Kanrethad:BAAALgAECgQJBAABLgAECggJKgAKAAgbAA==.Karina:BAABLgAECn9HAAMVAAkJoCE+DwDKAgAVAAkJbCA+DwDKAgAWAAkJzxY6BwASAgABLgAFFAEJAgAFAAAAAA==.Kastravia:BAABLgAFFH8GAAMVAAIJ1wI8lQBPAAAVAAIJfQE8lQBPAAAWAAEJ4APSFAAoAAABLgAFFAQJFgASAB4HAA==.Kawolski:BAABLgAFFH8MAAMQAAMJgQe0TQCIAAAQAAMJgQe0TQCIAAALAAMJDBWuFgB0AAABLgAFFAQJFgASAB4HAA==.Kawwne:BAAALgAECgEJAQABLgAECgYJCgAFAAAAAA==.',
Ke='Keepz:BAAALgAECgEJAQABLgAECgYJDAAFAAAAAA==.Kelitarra:BAAALgADCgQJCAAAAA==.Kellibar:BAAALgAECgcJBwAAAA==.Keunen:BAAALgAECgIJAgAAAA==.Kevin:BAAALgAECgcJCgAAAA==.Keyzer:BAAALgAECgEJAQAAAA==.',
Kh='Khanjuror:BAABLgAECn8uAAIfAAgJ1xQcCwCQAQAfAAgJ1xQcCwCQAQAAAA==.Kholonoe:BAABLgAECn8cAAIkAAkJmRS1IQC5AQAkAAkJmRS1IQC5AQAAAA==.Khornedog:BAABLgAECn8oAAICAAgJmBecPwDeAQACAAgJmBecPwDeAQAAAA==.Khrama:BAABLgAECn8WAAIKAAkJiSH6BQDFAgAKAAkJiSH6BQDFAgABLgAECggJKQADAMgkAA==.',
Ki='Kietemourt:BAAALgADCgUJBQAAAA==.Kiimachamara:BAAALgADCgIJAwAAAA==.Killik:BAAALgAECgQJBAAAAA==.Kinz:BAAALgAECgMJAwABLgABCgkJEwAFAAAAAA==.Kippili:BAAALgADCgQJBAABLgAECgYJCgAFAAAAAA==.Kiritokun:BAAALgADCgYJBAAAAA==.',
Kl='Klapz:BAAALgADCgcJDQABLgAECggJEAAFAAAAAA==.Kleenonean:BAACLgAFFH8dAAIkAAYJ+SP+BgCkAQAkAAYJ+SP+BgCkAQAuAAQKf2kAAyQACQknJscAAH0DACQACQknJscAAH0DAA8AAgnGBlV0AFcAAAAA.',
Ko='Kobe:BAAALgAFFAEJAgAAAA==.',
Kp='Kpyaccah:BAAALgAECgEJAQAAAA==.Kpyassan:BAAALgAECgYJBQAAAA==.',
Kr='Kravenn:BAAALgAECgMJAwAAAA==.Kredor:BAAALgAECgEJAQAAAA==.Kreuzritter:BAABLgAECn8zAAIaAAkJORDDCABcAgAaAAkJORDDCABcAgAAAA==.Kritterbug:BAAALgAECggJCAAAAA==.',
Ku='Kungcarefu:BAABLgAECn8bAAIDAAYJQxLJRADnAAADAAYJQxLJRADnAAAAAA==.Kungfujules:BAAALgAECgEJAQAAAA==.Kungfushnaz:BAAALgAECgEJAQAAAA==.Kurzaan:BAAALgAECgkJAgAAAA==.Kurzak:BAAALgAECgQJBwAAAA==.',
Ky='Kyle:BAAALgAECgEJAQABLgAFFAIJAgAFAAAAAA==.',
La='Laciel:BAAALgAECgMJBAABLgAECgkJIAAIAH0eAA==.Lacio:BAABLgAECn9HAAIkAAkJLwrhLQBqAQAkAAkJLwrhLQBqAQAAAA==.Larune:BAAALgADCgQJBwAAAA==.Lasten:BAAALgAECgEJAwAAAA==.Lavendàh:BAABLgAECn8oAAIGAAkJuCCHBQA6AwAGAAkJuCCHBQA6AwAAAA==.',
Le='Lemonite:BAACLgAFFH8UAAIQAAYJdxAyJgAqAQAQAAYJdxAyJgAqAQAuAAQKfxYAAhAACQlwG+QUAI4CABAACQlwG+QUAI4CAAAA.Lemonpepper:BAAALgADCgkJCQABLgAFFAYJFAAQAHcQAA==.Lennykoggins:BAABLgAECn8YAAIMAAgJLBePTQC5AQAMAAgJLBePTQC5AQAAAA==.Lexxix:BAAALgAECgUJBQAAAA==.Leyru:BAABLgAECn8sAAIGAAgJIST7BQAuAwAGAAgJIST7BQAuAwAAAA==.',
Li='Liberos:BAABLgAECn8YAAIJAAkJOBO5LQAAAgAJAAkJOBO5LQAAAgAAAA==.Lifenight:BAABLgAECn8kAAMiAAkJ6ByGBQBbAgAiAAkJ6ByGBQBbAgAIAAEJvwAGPwEJAAAAAA==.Lilnim:BAAALgAECgYJBgAAAA==.Lithvia:BAAALgAECgYJDQAAAA==.',
Ln='Lninedkhack:BAABLgAECn8mAAMIAAkJQRldNAAtAgAIAAkJQRldNAAtAgAKAAgJMQdbMgDTAAAAAA==.',
Lo='Lockdor:BAAALgAECgQJBAAAAA==.Logaar:BAABLgAECn80AAMGAAkJSxaOFgBXAgAGAAkJSxaOFgBXAgAHAAEJ7gH8zQEbAAAAAA==.Loretharan:BAAALgAECgEJAQAAAA==.Louvuitton:BAAALgADCgcJDgAAAA==.',
Lu='Luckymagi:BAAALgAECgEJAQAAAA==.Luckywizkid:BAAALgAECgYJBgAAAA==.Lunarstorm:BAAALgAECgMJBQAAAA==.Lunartsy:BAAALgADCggJDgAAAA==.Lustiel:BAAALgAECgYJDAABLgAECgcJCgAFAAAAAA==.Luticris:BAAALgAECgMJBAAAAA==.Luxurix:BAAALgAECgUJBQAAAA==.',
Ly='Lyoric:BAAALgAECgEJAQAAAA==.',
Ma='Madmax:BAAALgADCggJCAAAAA==.Maegot:BAAALgADCgYJBgAAAA==.Magicpants:BAAALgAECgcJCgAAAA==.Magnetto:BAAALgADCggJDQAAAA==.Maiden:BAAALgADCgUJCAABLgAECggJKgAKAAgbAA==.Malexannius:BAAALgADCgUJCQAAAA==.Mannirot:BAAALgAECgEJAQAAAA==.Mariangel:BAAALgAECgUJCQAAAA==.Marrygold:BAAALgAECgEJAgABLgAECgkJIwAIAHYfAA==.Mateus:BAAALgAECgkJDQAAAA==.Maxdeath:BAABLgAECn8lAAIIAAgJ9iO/DQAtAwAIAAgJ9iO/DQAtAwAAAA==.Mazre:BAAALgAECgQJBwAAAA==.',
Me='Megtallica:BAABLgAECn8YAAIHAAgJvww7GAAbAQAHAAgJvww7GAAbAQAAAA==.Mendrelina:BAAALgAECgYJDAAAAA==.Mensrea:BAABLgAECn8rAAMJAAkJKRc7EgAVAQAJAAcJzhU7EgAVAQAOAAgJow5dXgDJAAAAAA==.Meow:BAAALgADCgIJAgAAAA==.Merlinn:BAAALgADCgMJBgAAAA==.Merrycold:BAABLgAECn8jAAMIAAkJdh9FPABGAgAIAAcJpSFFPABGAgAKAAUJ3ROoOACxAAAAAA==.Merrygold:BAAALgADCgMJAwABLgAECgkJIwAIAHYfAA==.Merrygored:BAAALgAECgIJAgABLgAECgkJIwAIAHYfAA==.Mess:BAABLgAECn8uAAQbAAcJlB5eDwDzAQAbAAcJlB5eDwDzAQAdAAIJ3gfTlABsAAAeAAMJPQgXRwApAAABLgAECggJKgAKAAgbAA==.Methodical:BAAALgADCgUJBQAAAA==.Metophis:BAAALgAECgYJCgAAAA==.',
Mf='Mfboomstick:BAABLgAECn8/AAMaAAkJNCY3AQBZAwAaAAkJNCY3AQBZAwANAAEJlSVVLQBhAAAAAA==.Mfgirthquake:BAABLgAFFH8GAAIcAAMJUhlmBwDtAAAcAAMJUhlmBwDtAAAAAA==.',
Mi='Miisty:BAAALgAECggJCAAAAA==.Mikklelee:BAAALgADCgIJAgAAAA==.Minerva:BAAALgADCgMJAwAAAA==.Missdebby:BAAALgADCgYJCwAAAA==.Mistweaver:BAABLgAECn8fAAISAAkJgiDjBQBJAwASAAkJgiDjBQBJAwAAAA==.Mistweaving:BAAALgAECgcJBAAAAA==.Mistyjoe:BAAALgAECgEJAQAAAA==.Mizirath:BAAALgAECgQJBAABLgAECggJMgALAKofAA==.',
Mo='Mochi:BAABLgAECn8XAAMlAAgJYhyeAABKAgAlAAgJYhyeAABKAgAEAAUJVxKRHwDkAAABLgAECgkJKAATAKIaAA==.Moghorva:BAABLgAECn8fAAMmAAkJzBgdCQBYAgAmAAkJzBgdCQBYAgAjAAEJ4w0OkQA5AAAAAA==.Mojoe:BAABLgAECn8aAAIJAAcJuhRDDQBcAQAJAAcJuhRDDQBcAQAAAA==.Mommyswaggin:BAABLgAECn8VAAIPAAkJChRvHwDJAQAPAAkJChRvHwDJAQAAAA==.Moonra:BAAALgAECgEJAQAAAA==.Moopocalypse:BAAALgADCgcJDAABLgAFFAUJDQAPAFQfAA==.Moopsta:BAAALgADCggJDgABLgAFFAUJDQAPAFQfAA==.Moopster:BAACLgAFFH8NAAIPAAUJVB82DQB3AQAPAAUJVB82DQB3AQAuAAQKfzYAAw8ACQmdJbMBAJwDAA8ACQmdJbMBAJwDAAEABgnfGRsiAL0BAAAA.Moopy:BAAALgAECgQJAwABLgAFFAUJDQAPAFQfAA==.Mordekaiserz:BAAALgAECgUJCwAAAA==.Morrgoth:BAAALgADCgEJAQAAAA==.',
Mu='Mucouslurp:BAAALgADCgEJAQAAAA==.',
Na='Nalahni:BAACLgAFFH8OAAIjAAQJRQ1kOADkAAAjAAQJRQ1kOADkAAAuAAQKfyIAAiMACQmHGHoWACQCACMACQmHGHoWACQCAAAA.Nalthexon:BAAALgAECgEJAQAAAA==.Nanashi:BAAALgAECgMJAwAAAA==.Nastage:BAAALgADCgMJAQAAAA==.Nastus:BAAALgAECgMJAwAAAA==.Native:BAAALgAECgQJBAAAAA==.Nayela:BAAALgAECgYJEAAAAA==.Nazgru:BAAALgAECgEJAQAAAA==.',
Ne='Neptuneakis:BAACLgAFFH8SAAITAAMJJA7NGgCqAAATAAMJJA7NGgCqAAAuAAQKfy0AAxMACQk/GFEUADECABMACQk/GFEUADECABAAAQkgFI8gADwAAAAA.Neptuno:BAAALgAECgQJDAABLgAFFAMJEgATACQOAA==.Nerfblaster:BAAALgADCgEJAQAAAA==.Newcarsmell:BAABLgAECn8UAAQGAAkJ9Q8iJADkAQAGAAgJtxEiJADkAQAUAAUJMwsIMACnAAAHAAEJmAGY1AEQAAAAAA==.Newp:BAAALgAECgQJBQAAAA==.',
Ni='Nicktee:BAAALgAFFAEJAQAAAA==.Nightmares:BAAALgAECgcJCgAAAA==.Nightrvn:BAAALgAECgQJBAAAAA==.Nimfierce:BAAALgADCgkJCQAAAA==.Nimrose:BAABLgAECn8cAAIEAAkJlQb2owA0AQAEAAkJlQb2owA0AQAAAA==.Niquid:BAABLgAECn8yAAIQAAkJzBe4MADfAQAQAAkJzBe4MADfAQAAAA==.',
No='Nobu:BAABLgAFFH8HAAInAAUJ6g/2AQAiAQAnAAUJ6g/2AQAiAQABLgAFFAUJDQAIAFQUAA==.Nolmac:BAABLgAECn8oAAIJAAkJ/SKIBgBIAwAJAAkJ/SKIBgBIAwAAAA==.Notahealer:BAABLgAFFH8LAAMPAAQJvROXDgDBAAAPAAMJmxeXDgDBAAABAAIJ/gWgQwBtAAAAAA==.Noxloxes:BAAALgADCgcJDAAAAA==.',
Np='Npv:BAABLgAFFH8HAAIIAAIJgQ2O6ACAAAAIAAIJgQ2O6ACAAAAAAA==.',
Ny='Nyssavia:BAAALgADCgcJDgAAAA==.',
Oa='Oakshre:BAABLgAECn80AAIRAAkJnSBYBwDUAgARAAkJnSBYBwDUAgAAAA==.',
Ob='Obliteration:BAAALgAFFAEJAgAAAA==.',
Ol='Olivertwist:BAAALgAECgQJDgABLgAFFAEJAgAFAAAAAA==.',
Om='Omnimpotent:BAAALgAECgEJAQABLgAECgIJBQAFAAAAAA==.',
On='Ontwarr:BAAALgAECgYJDQAAAA==.Ontwou:BAABLgAECn8ZAAIMAAkJRBuIIgBaAgAMAAkJRBuIIgBaAgAAAA==.',
Op='Ophi:BAAALgAECgYJEQAAAA==.',
Os='Oshaku:BAAALgAECgcJDAAAAQ==.',
Ou='Ouchpotato:BAACLgAFFH8IAAIHAAQJLBNpQwAkAQAHAAQJLBNpQwAkAQAuAAQKfxUAAgcACQlMHYIbAJ8CAAcACQlMHYIbAJ8CAAEuAAUUBgkKAAgAUwcA.',
Pa='Paarthurnax:BAABLgAFFH8MAAMjAAQJXAnaHwCxAAAjAAQJXAnaHwCxAAAoAAEJFAepDwA+AAAAAA==.Palathal:BAAALgAECgUJBgABLgAECggJGQAEAPoTAA==.Pallynim:BAAALgADCgQJBwAAAA==.Palms:BAACLgAFFH8SAAIRAAYJRBjnDgBHAQARAAYJRBjnDgBHAQAuAAQKfxgAAhEACQlDIpgHAAIDABEACQlDIpgHAAIDAAAA.Pancakezebra:BAABLgAECn8yAAIaAAkJ6RrsEAAlAgAaAAkJ6RrsEAAlAgAAAA==.Pantsftw:BAABLgAECn8fAAMPAAgJQwymNAAyAQAPAAgJ1QumNAAyAQABAAEJQQXJfQAuAAAAAA==.Papabear:BAAALgADCgUJBQAAAA==.Parkbreezy:BAABLgAECn8bAAILAAcJBwqYQgCcAAALAAcJBwqYQgCcAAAAAA==.Passera:BAABLgAECn8WAAIEAAgJvxJcGwABAQAEAAgJvxJcGwABAQAAAA==.Pawg:BAAALgADCgcJBgAAAA==.',
Pe='Peltier:BAABLgAECn8sAAIEAAkJdCDLJQCFAgAEAAkJdCDLJQCFAgAAAA==.Pendle:BAABLgAECn8sAAMCAAgJFA5GZAB2AQACAAgJfg1GZAB2AQAfAAYJHQvDKQAbAQAAAA==.Perilous:BAAALgAECgIJAgABLgAFFAYJCgAIAFMHAA==.',
Ph='Phoenix:BAABLgAECn8xAAIHAAkJbB/fGgCjAgAHAAkJbB/fGgCjAgAAAA==.Phorine:BAAALgAECgEJAQAAAA==.Pháe:BAAALgAECgIJAgAAAA==.',
Pi='Pinkskies:BAAALgAECgEJAQAAAA==.',
Pl='Plox:BAAALgAECgYJEwAAAA==.Plugtobacca:BAABLgAFFH8FAAMRAAQJjwXbEwCQAAARAAMJagfbEwCQAAADAAIJAACtYwAAAAABLgAFFAUJDQAIAFQUAA==.Plurnizz:BAABLgAECn8dAAMCAAkJHQhgiAApAQACAAkJHQhgiAApAQAfAAQJEwHKXwBPAAAAAA==.',
Po='Pocketchange:BAACLgAFFH8bAAMJAAYJvBu6EwAxAQAJAAYJvBu6EwAxAQAOAAIJPxz9IACeAAAuAAQKfxcAAw4ACQlMG3EqAMIBAA4ABgnWHHEqAMIBAAkABwmBGDJLAFYBAAAA.',
Pr='Prowl:BAAALgAECgEJAQABLgAFFAMJBgAcAFIZAA==.',
Pu='Puffadin:BAAALgADCgEJAQAAAA==.Punybanner:BAAALgAECgEJAQAAAA==.Puppymoke:BAAALgAECgMJAwAAAA==.Puptart:BAAALgAECgUJBQAAAA==.',
['Pí']='Pínk:BAAALgAECgcJBwAAAA==.',
Ra='Raest:BAABLgAECn8pAAIDAAgJyCT8BQDdAgADAAgJyCT8BQDdAgAAAA==.Raiker:BAAALgAECgMJBAAAAA==.Ranch:BAAALgAECgEJAQAAAA==.Razzlock:BAAALgAECgEJAQAAAA==.',
Re='Rebeccamagic:BAAALgAECgMJAwAAAA==.Regret:BAAALgAECgkJEgAAAA==.Relovan:BAABLgAECn8vAAMeAAkJ6RCEFgCnAQAeAAkJ6RCEFgCnAQAdAAUJSwOYhgClAAAAAA==.Renothidan:BAACLgAFFH8PAAIHAAQJfxrcMwBHAQAHAAQJfxrcMwBHAQAuAAQKfyMAAgcACQnZG+s4AB4CAAcACQnZG+s4AB4CAAAA.Reuben:BAAALgAECgUJBQAAAA==.Revin:BAAALgAFFAIJAgAAAA==.Revrynth:BAAALgAFFAIJAgAAAA==.Rexorcist:BAACLgAFFH8JAAIHAAMJShPDMgDFAAAHAAMJShPDMgDFAAAuAAQKfxgAAgcACAkqFScMAKYBAAcACAkqFScMAKYBAAAA.',
Ri='Rickyboby:BAAALgAECggJDAAAAA==.Righteøus:BAAALgAECgUJEwAAAA==.Rillan:BAABLgAECn8aAAIHAAYJ8xbqmwA+AQAHAAYJ8xbqmwA+AQAAAA==.Rimed:BAAALgAFFAQJBAAAAA==.Rin:BAAALgAECgkJCQABLgAECgkJPwACAEklAA==.Ripper:BAAALgAECgUJDAAAAA==.Rippèd:BAABLgAECn8iAAMfAAYJjhBBBgDrAAAfAAYJBA9BBgDrAAACAAMJExF9GwCdAAAAAA==.Rithcice:BAABLgAECn84AAMdAAkJtCbyAAB8AwAdAAkJqSbyAAB8AwAbAAcJ/yPTCABrAgAAAA==.Rizzdolphler:BAACLgAFFH8QAAIHAAQJqRR4RAAiAQAHAAQJqRR4RAAiAQAuAAQKfygAAwcACAmyHZc1ACoCAAcACAmyHZc1ACoCAAYABgktEc1CADYBAAAA.',
Ro='Roadnurse:BAAALgADCgIJAgAAAA==.Rockntroll:BAAALgADCgIJAgAAAA==.Rodah:BAAALgADCgkJEAAAAA==.Roscoee:BAAALgADCgEJAQAAAA==.Roselynt:BAAALgAECgMJAwAAAA==.',
Rs='Rsk:BAAALgADCgYJCQABLgAECggJKgAKAAgbAA==.',
Ru='Ruins:BAAALgAECgEJAQAAAA==.',
['Rà']='Ràrity:BAAALgADCggJCAAAAA==.',
['Rö']='Rönburgundy:BAACLgAFFH8NAAICAAMJ1BEVdgDVAAACAAMJ1BEVdgDVAAAuAAQKfy4AAgIACQmNHvAdAHECAAIACQmNHvAdAHECAAAA.',
Sa='Sanako:BAABLgAECn8oAAITAAkJxxGHHwDMAQATAAkJxxGHHwDMAQAAAA==.Sanastusa:BAAALgADCgYJCAAAAA==.Saneros:BAAALgAECggJCQABLgAECggJNgAVACEZAA==.Santoniche:BAAALgAECgUJBAAAAA==.Sap:BAABLgAECn8gAAMZAAcJFxc9HwCcAQAZAAcJFxc9HwCcAQAnAAQJQguHFgDIAAABLgAECggJKgAKAAgbAA==.Sausiege:BAAALgAECgMJAwAAAA==.Saveserenade:BAAALgAECgUJBQAAAA==.',
Sc='Scarylarry:BAABLgAECn82AAIVAAgJIRmiPADVAQAVAAgJIRmiPADVAQAAAA==.Scyther:BAACLgAFFH8MAAMYAAQJbwwcFQD7AAAYAAQJMAwcFQD7AAAVAAIJRwMrjwBkAAAuAAQKfxgAAxUACQlBD8txAE8BABUACAk9DMtxAE8BABgABglZEexLAIcAAAAA.',
Sd='Sdh:BAAALgADCgQJBgAAAA==.',
Se='Seaze:BAAALgAECgUJBQAAAA==.Seishinokami:BAABLgAECn8tAAIOAAkJQg1aLwCDAQAOAAkJQg1aLwCDAQAAAA==.Senala:BAAALgAECgEJAQAAAA==.Serenade:BAACLgAFFH8KAAIEAAQJqBErawANAQAEAAQJqBErawANAQAuAAQKfyQAAgQACAmuHxYzAKYCAAQACAmuHxYzAKYCAAAA.Setheron:BAABLgAECn8sAAIdAAkJdSG2BQAFAwAdAAkJdSG2BQAFAwAAAA==.Sethron:BAAALgAECgIJAgAAAA==.Señsei:BAAALgAECggJCwAAAA==.',
Sh='Shamminit:BAAALgAECgIJAgAAAA==.Shamtul:BAAALgAECgEJAwAAAA==.Shamwow:BAAALgADCgcJDgAAAA==.Shlea:BAACLgAFFH8XAAIjAAQJVAhaIQCnAAAjAAQJVAhaIQCnAAAuAAQKfx0AAiMACQn7EIMpAJsBACMACQn7EIMpAJsBAAAA.Shyva:BAABLgAECn8pAAMbAAgJ9SIxBwC4AgAbAAgJ9SIxBwC4AgAdAAUJ9xcFUwD/AAABLgAFFAIJAgAFAAAAAA==.',
Si='Siatren:BAAALgAECgEJAQAAAA==.Siinestro:BAAALgAECgQJBAAAAA==.Sinlee:BAAALgAECgcJDgABLgAECgkJOgACAEMiAA==.',
Sl='Slayla:BAAALgAECgUJDAAAAA==.Slimboyjoe:BAAALgADCgcJDgAAAA==.Slimmjim:BAAALgADCgEJAQAAAA==.Slinkstir:BAAALgADCgQJAwAAAA==.',
Sn='Snailtrails:BAAALgAECgcJBwAAAA==.Sneak:BAAALgADCgMJAwABLgAFFAMJBgAcAFIZAA==.Sneakcookies:BAAALgAFFAEJAQABLgAFFAEJAgAFAAAAAA==.',
So='Soggyundies:BAAALgAECgQJBAAAAA==.Solendros:BAAALgAECgYJDwAAAA==.Sonthar:BAAALgAECgYJBgAAAA==.Soulelf:BAAALgAECggJCAAAAA==.',
Sp='Spacehog:BAAALgAECgYJDAAAAA==.Sparticus:BAAALgAECgEJAQAAAA==.Spiro:BAAALgAECgEJAQABLgAFFAMJCwARAMIfAA==.Splouge:BAAALgAECgYJBgAAAA==.',
St='Standarshh:BAACLgAFFH8KAAIMAAMJ5xkTMwDaAAAMAAMJ5xkTMwDaAAAuAAQKf0AAAgwACQl1IsoKAP8CAAwACQl1IsoKAP8CAAAA.Stemmz:BAAALgADCgEJAQAAAA==.Stronghand:BAAALgADCgYJBwAAAA==.',
Su='Subtle:BAACLgAFFH8PAAIZAAUJiRaLGgBCAQAZAAUJiRaLGgBCAQAuAAQKfygAAxkACQnXHywNAMcCABkACQnXHywNAMcCACkABQmpBvMZAIUAAAEuAAUUBgkKAAgAUwcA.Sugarbabi:BAABLgAECn8jAAMQAAkJUh8uIQA7AgAQAAcJ3x4uIQA7AgATAAcJ1hflJwCRAQAAAA==.Sugarcube:BAAALgAECgYJBgAAAA==.Sugarqween:BAAALgAFFAEJAQAAAA==.Sugarrush:BAAALgADCgUJBQAAAA==.Sugarshot:BAAALgAECgkJCwAAAA==.Sugarthorn:BAAALgAECgIJBAAAAA==.Sugartotem:BAAALgAECgEJAQAAAA==.Sulcer:BAAALgADCgMJBAAAAA==.',
Sw='Swiftwing:BAAALgADCgYJBgAAAA==.',
Sy='Sylria:BAAALgAECgIJAgAAAA==.Sylrianah:BAABLgAECn9IAAQPAAkJ0CBcBwD5AgAPAAkJ0CBcBwD5AgAkAAkJ4QipLgBmAQABAAQJrghvWACeAAAAAA==.Sylveste:BAACLgAFFH8ZAAIGAAgJySAkCQApAgAGAAgJySAkCQApAgAuAAQKfyUAAgYACQnfGAkyAI4BAAYACQnfGAkyAI4BAAAA.Sylvfelster:BAAALgAECgYJBwABLgAFFAgJGQAGAMkgAA==.Sylánnia:BAAALgADCgcJBwAAAA==.',
Ta='Ta:BAABLgAECn8aAAIBAAcJpAgWOgAoAQABAAcJpAgWOgAoAQAAAA==.Talis:BAAALgAECgEJAQAAAA==.Tankhiskhan:BAABLgAECn8VAAIKAAgJQA3XLgDpAAAKAAgJQA3XLgDpAAAAAA==.Tarlis:BAABLgAECn8YAAIgAAgJ9xq8BAAqAgAgAAgJ9xq8BAAqAgAAAA==.',
Te='Tedrickeyjr:BAAALgAECgEJBgAAAA==.Terithresh:BAAALgADCgMJBAAAAA==.',
Th='Thanil:BAABLgAECn8wAAIHAAkJmhkrNgAoAgAHAAkJmhkrNgAoAgAAAA==.Thelliane:BAAALgAECgIJAgABLgAFFAYJIwAJAFcTAA==.Thenet:BAAALgAECgEJAwAAAA==.',
Ti='Tie:BAABLgAECn8iAAIUAAgJOxfMAgDSAQAUAAgJOxfMAgDSAQAAAA==.Tikamancer:BAAALgADCgEJAQAAAA==.Tilvalhalla:BAABLgAECn8cAAImAAcJPAogKgAhAQAmAAcJPAogKgAhAQAAAA==.Tin:BAAALgAECgEJAQAAAA==.',
To='Todorokii:BAAALgAECgUJDQAAAA==.Tom:BAAALgAECgEJAgABLgAFFAIJAgAFAAAAAA==.Torrin:BAAALgADCgYJBwAAAA==.Tortaa:BAAALgAECgUJBQAAAA==.Tortricid:BAAALgAECgcJDgAAAA==.Totaldchtree:BAAALgAECgEJAQAAAA==.Totempants:BAAALgAECgYJBgAAAA==.Totinospizza:BAAALgADCgYJBgAAAA==.',
Tr='Trashkan:BAAALgADCgIJAgAAAA==.Trauck:BAAALgADCgEJAQAAAA==.Traumzi:BAAALgAECgEJAQAAAA==.Travvy:BAACLgAFFH9pAAMZAAkJMCUmAACDAwAZAAkJ/CQmAACDAwAnAAIJoR6xDABqAAAuAAQKfyIAAhkACQkWJgEBAMMDABkACQkWJgEBAMMDAAAA.Treezus:BAAALgADCgYJCAAAAA==.Trevmo:BAABLgAECn82AAIbAAkJGyCEBgCjAgAbAAkJGyCEBgCjAgAAAA==.Trexin:BAAALgAECggJEQAAAA==.',
Tu='Turaylon:BAAALgAFFAEJAQAAAA==.Turtlebox:BAAALgAECgQJBgAAAA==.',
Ty='Tym:BAAALgAFFAIJAgAAAA==.',
Tz='Tzuyu:BAAALgAFFAEJAgAAAA==.',
Ug='Ugargro:BAABLgAECn8XAAQbAAUJIQhaOQCPAAAbAAUJOwdaOQCPAAAdAAIJJwSJsgAkAAAeAAEJcgjFHwAgAAAAAA==.',
Un='Unapologetic:BAAALgAECggJDAAAAA==.Unbreakabull:BAABLgAFFH8SAAITAAYJ2yIkDwCwAQATAAYJ2yIkDwCwAQAAAA==.Unceejin:BAAALgADCggJEQAAAA==.Unholydk:BAABLgAECn8qAAMKAAgJCBv6DwAMAgAKAAgJCBv6DwAMAgAIAAUJsw+I5wDLAAAAAA==.',
Va='Valcuna:BAAALgAECgQJBQAAAA==.Valka:BAABLgAECn8YAAIhAAkJUgkoGgA8AQAhAAkJUgkoGgA8AQAAAA==.Vamptouch:BAAALgAECgIJAwABLgAFFAMJBgAcAFIZAA==.Vanaan:BAAALgAECgIJAgABLgAECgYJBwAFAAAAAA==.Varidrus:BAAALgAECgQJBQAAAA==.Vaste:BAAALgADCgcJCQAAAA==.',
Ve='Velleannissa:BAAALgADCgMJAwAAAA==.Venomlight:BAAALgAECgcJBwAAAA==.Ventrue:BAABLgAECn8jAAIEAAkJ6xWVXgDEAQAEAAkJ6xWVXgDEAQAAAA==.Veyle:BAABLgAECn8/AAMZAAkJ1yRiBQDdAgAZAAkJ1yRiBQDdAgAnAAEJKh7AGwBJAAAAAA==.',
Vi='Vivian:BAABLgAECn8xAAIYAAkJfRrgCgB6AgAYAAkJfRrgCgB6AgABLgAFFAMJCwARAMIfAA==.Vixèn:BAAALgAECgEJAQAAAA==.',
Vo='Voidsurge:BAABLgAECn8yAAQWAAcJmBl1DACPAQAWAAcJUxZ1DACPAQAYAAUJMxsfKAA7AQAVAAUJ+hGwsQDFAAABLgAECggJKgAKAAgbAA==.',
Vy='Vyel:BAAALgAECgQJBAAAAA==.Vyndria:BAAALgAECgYJEQAAAA==.',
Wa='Wardell:BAAALgAECgQJCAAAAA==.',
We='Weashock:BAAALgAFFAIJAgAAAA==.Weaspore:BAABLgAECn8hAAIIAAgJlR7IQgD6AQAIAAgJlR7IQgD6AQAAAA==.Weasy:BAAALgAECgkJDgAAAA==.',
Wi='Windfury:BAABLgAFFH8IAAIcAAMJYSDjBAAoAQAcAAMJYSDjBAAoAQAAAA==.',
Wo='Woogidaboogi:BAAALgAECgIJBQAAAA==.Woogieboogie:BAAALgAECgEJAQABLgAECgIJBQAFAAAAAA==.',
Xi='Xiamiel:BAAALgADCgYJCQAAAA==.',
Xl='Xl:BAABLgAECn9WAAMYAAgJ/RxVCwCrAgAYAAgJhxxVCwCrAgAVAAgJJxZWRQC3AQAAAA==.',
Ya='Yaitoopmfp:BAAALgAECgIJBAABLgAECgkJIwAIAHYfAA==.Yao:BAAALgAECgIJAgABLgAFFAMJCgAbAPUZAA==.',
Yh='Yharnem:BAABLgAECn8XAAIDAAcJ8hBWLgBMAQADAAcJ8hBWLgBMAQAAAA==.',
Yo='Yogurtpants:BAAALgAECgYJEgAAAA==.Yonny:BAAALgADCgEJAQAAAA==.',
Yu='Yukionna:BAAALgADCgcJCwAAAA==.',
Za='Zabara:BAABLgAECn8jAAIJAAkJrh+tCwD/AgAJAAkJrh+tCwD/AgAAAA==.Zabbystabby:BAAALgADCgkJDgAAAA==.Zakaraki:BAABLgAECn8+AAQoAAkJhCWoAAA8AwAoAAkJhCWoAAA8AwAjAAcJNyEPGQAOAgAmAAcJTAd5JgBBAQAAAA==.Zaki:BAABLgAECn8aAAIVAAkJThqHIwBCAgAVAAkJThqHIwBCAgAAAA==.Zanked:BAAALgADCgQJBAAAAA==.Zarkingu:BAAALgADCgMJAwAAAA==.',
Ze='Zealot:BAAALgAFFAEJAQAAAA==.Zeleria:BAAALgAECgUJBgAAAA==.Zeno:BAAALgAFFAIJAgAAAA==.Zephyr:BAAALgAECgQJBAAAAA==.Zerathis:BAABLgAECn86AAICAAkJQyLSDgDWAgACAAkJQyLSDgDWAgAAAA==.Zerathül:BAAALgAECgcJEgAAAA==.Zerötwo:BAAALgADCgkJCgAAAA==.Zestul:BAAALgADCgkJFgAAAA==.',
Zi='Zimbobayaga:BAAALgAECgMJAwAAAA==.Zip:BAAALgAECgQJBAAAAA==.',
Zo='Zodivine:BAAALgADCgMJAwAAAA==.Zohar:BAAALgADCgEJAgAAAA==.Zooty:BAAALgADCgUJAwAAAA==.Zoshow:BAAALgAFFAIJAgAAAA==.',
Zu='Zuggo:BAAALgADCgYJBgAAAA==.',
Zy='Zyrig:BAAALgAECggJDgAAAA==.',
['Zõ']='Zõshow:BAABLgAECn8XAAMCAAcJmxVucQBXAQACAAcJeBVucQBXAQAfAAEJEh0zYABOAAAAAA==.',
['Ça']='Çaptainçhaos:BAAALgAECgYJCgAAAA==.',
['Çh']='Çhromi:BAAALgADCgMJAwAAAA==.',
['Ða']='Ðaredevil:BAACLgAFFH8LAAIRAAMJwh9rFQATAQARAAMJwh9rFQATAQAuAAQKfy4AAhEACQnmH0gHANUCABEACQnmH0gHANUCAAAA.',
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
