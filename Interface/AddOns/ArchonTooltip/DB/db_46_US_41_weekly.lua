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

local lookup = {'Priest-Discipline','Monk-Brewmaster','Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','Warlock-Demonology','Shaman-Restoration','DeathKnight-Blood','Hunter-Marksmanship','Priest-Holy','Druid-Restoration','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Shaman-Elemental','Druid-Guardian','Paladin-Protection','DemonHunter-Devourer','Mage-Fire','DemonHunter-Vengeance','Rogue-Subtlety','Hunter-Survival','Warrior-Protection','Warrior-Arms','Shaman-Enhancement','Warlock-Destruction','Warlock-Affliction','Warrior-Fury','Hunter-BeastMastery','Evoker-Augmentation','Mage-Arcane','Priest-Shadow','DeathKnight-Frost','Evoker-Preservation','Rogue-Assassination','DemonHunter-Havoc','Rogue-Outlaw','Evoker-Devastation',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aahzbear:BAAALgAECgUJDAAAAA==.',
Ab='Abreale:BAAALgADCgMJAwAAAA==.',
Ae='Aeero:BAABLgAECn8UAAIBAAYJNhfEHwCWAQABAAYJNhfEHwCWAQAAAA==.Aerendyl:BAAALgAECgcJCAAAAA==.',
Ai='Aiden:BAACLgAFFH8HAAICAAMJbRA/KQDOAAACAAMJbRA/KQDOAAAuAAQKfxQAAgIABgkfHF8qALcBAAIABgkfHF8qALcBAAAA.',
Al='Algros:BAAALgADCgEJAQAAAA==.Alyiriia:BAAALgADCgMJAwAAAA==.',
Am='Amathal:BAABLgAECn8WAAIDAAgJ9hOEagBnAQADAAgJ9hOEagBnAQAAAA==.Amilea:BAAALgAFFAEJAQABLgABCgkJEgAEAAAAAA==.',
An='Anastasia:BAAALgADCggJCAAAAA==.Angelsevoker:BAAALgAECggJCAAAAA==.Angermoonria:BAAALgADCgcJBwAAAA==.Ankheloios:BAAALgADCggJDgAAAA==.Antihiiro:BAAALgAECgMJAwAAAA==.Antipro:BAAALgAFFAEJAQAAAA==.Anubbus:BAAALgAECggJDQAAAA==.Anzulok:BAAALgADCgYJAQAAAA==.',
Ar='Arbalest:BAAALgADCgcJBgAAAA==.Aredhela:BAAALgAECggJEQAAAA==.Arinth:BAAALgADCggJEQAAAA==.Armpit:BAAALgAECgMJAwAAAA==.',
As='Ascanius:BAAALgADCgQJBAAAAA==.Ashiiro:BAAALgAECgcJEAAAAA==.Ashveil:BAAALgAECgQJBAABLgAECggJJAAFAGUaAA==.Asia:BAABLgAECn8/AAIGAAkJSSV7AgBPAwAGAAkJSSV7AgBPAwAAAA==.Asmodeius:BAAALgAFFAEJAgAAAA==.Astroprof:BAAALgAECgEJAQABLgAECgYJFAAHAFsaAA==.',
At='Athrea:BAABLgAECn8UAAMIAAkJkRucGQA6AQAFAAgJcBifcgCiAQAIAAUJUBucGQA6AQAAAA==.',
Au='Auntjemima:BAAALgAECgEJAgAAAA==.Aureleus:BAAALgADCgEJAQAAAA==.',
Aw='Away:BAAALgADCgIJAgAAAA==.',
Az='Azaii:BAAALgADCggJCgAAAA==.Azlear:BAAALgAECgkJBgAAAA==.',
Ba='Babilouchoux:BAAALgAECgEJAQAAAA==.Ballz:BAAALgADCgYJBgAAAA==.Bano:BAAALgAECgMJAwAAAA==.Barnre:BAAALgAECgYJCQABLgAECgYJDAAEAAAAAA==.Baythos:BAAALgAFFAEJAgAAAA==.',
Bd='Bdssm:BAAALgAECgYJDgAAAA==.',
Be='Beefstick:BAAALgAECgQJBgAAAA==.Berzercarl:BAAALgAECgEJAQAAAA==.Beserkfury:BAABLgAECn8hAAIJAAgJoA1bDABQAQAJAAgJoA1bDABQAQAAAA==.',
Bh='Bhemtu:BAAALgADCggJDAAAAA==.',
Bi='Biercan:BAAALgAECggJDQAAAA==.Bigcarl:BAAALgADCgMJAwAAAA==.Binke:BAAALgAECgcJDAAAAA==.Bittywhite:BAAALgAECgIJAgAAAA==.Bittywyvern:BAAALgADCgUJCgABLgAECgIJAgAEAAAAAA==.',
Bl='Blayze:BAABLgAECn8UAAIKAAcJUhFaMQB7AQAKAAcJUhFaMQB7AQAAAA==.Blessidbee:BAAALgAECgEJAQAAAA==.Blightmarx:BAAALgADCgUJCAAAAA==.Blitzwow:BAAALgADCgYJBQAAAA==.Bluemoonflay:BAAALgAECgkJEwAAAA==.Blúnt:BAAALgADCgQJBAAAAA==.',
Bo='Bobheals:BAABLgAECn8YAAILAAQJtRDDZADBAAALAAQJtRDDZADBAAAAAA==.Boibye:BAAALgAECgYJDgAAAA==.Bolblock:BAAALgAECgkJDwAAAA==.Boostedww:BAAALgAECgMJBwAAAA==.',
Br='Brambleclaw:BAABLgAECn8/AAIIAAkJRSP4AQASAwAIAAkJRSP4AQASAwAAAA==.Brayker:BAABLgAECn8+AAIMAAkJoyWZAgBRAwAMAAkJoyWZAgBRAwAAAA==.Breadoneal:BAABLgAECn8hAAMNAAkJPBcKFgAPAgANAAgJQBgKFgAPAgAMAAEJyATUSwEpAAAAAA==.Breeze:BAAALgAECgYJBgAAAA==.Brewed:BAABLgAECn8iAAMOAAgJjhShGwCBAQAOAAgJjhShGwCBAQAPAAEJLwFSgwALAAAAAA==.Brisketbane:BAAALgAECgcJEAAAAA==.Brokenmask:BAACLgAFFH8KAAILAAQJCBnPFwA+AQALAAQJCBnPFwA+AQAuAAQKfxUAAwsACAkOIEobAGECAAsACAkOIEobAGECABAAAgkLEd5nADIAAAAA.Broxxar:BAAALgAECgIJAgAAAA==.Bruxxe:BAAALgAECgcJAQAAAA==.Brüenor:BAAALgAECgIJAgAAAA==.',
Bu='Burntroot:BAABLgAECn8ZAAIRAAcJzQOTSAC5AAARAAcJzQOTSAC5AAAAAA==.',
Ca='Caedwyn:BAABLgAECn8pAAISAAgJOh/5BABqAgASAAgJOh/5BABqAgAAAA==.Caitrakk:BAABLgAECn8UAAMHAAYJWxqgMgC7AQAHAAYJWxqgMgC7AQARAAUJYhC9TAAVAQAAAA==.Calignus:BAABLgAECn8cAAMMAAgJ9xCCcwA7AQAMAAgJ9xCCcwA7AQATAAUJVQ8jJwDQAAAAAA==.Captjack:BAABLgAECn8dAAIUAAkJqQvlSgBWAQAUAAkJqQvlSgBWAQAAAA==.Cartilage:BAABLgAECn8dAAIFAAgJFRMsUACLAQAFAAgJFRMsUACLAQAAAA==.Catalei:BAAALgAECgYJDwAAAA==.Caution:BAAALgADCgYJCwAAAA==.',
Ce='Celira:BAAALgAECgEJAQAAAA==.Celys:BAAALgAECgIJAgAAAA==.',
Ch='Chickenman:BAAALgAECgEJAQAAAA==.Chiselia:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Choconilla:BAAALgAECgcJDAAAAA==.Chonkmonk:BAAALgADCgQJBAAAAA==.Choppa:BAAALgADCggJCgAAAA==.Chorizo:BAAALgAECgEJAQABLgAECgYJEgAEAAAAAA==.Chupacabrass:BAAALgADCgYJBgAAAA==.',
Ci='Cinnomun:BAAALgADCgEJAQAAAA==.',
Co='Combustinme:BAAALgAECgQJBAABLgAECggJLwAUAAcYAA==.Consuming:BAABLgAECn8eAAILAAYJ4BaTUABjAQALAAYJ4BaTUABjAQAAAA==.Coorsbanquet:BAAALgAECggJDgAAAA==.Coorsbite:BAAALgADCgYJBgAAAA==.Corgh:BAABLgAECn8kAAIVAAYJtw4XBgBIAQAVAAYJtw4XBgBIAQAAAA==.Corrahthecow:BAAALgADCgEJAQAAAA==.Cowardice:BAAALgADCgYJCwAAAA==.',
Cr='Craccjar:BAAALgADCgMJAwAAAA==.Crash:BAECLgAFFH8MAAIUAAUJnxkSIgBAAQAUAAUJnxkSIgBAAQAuAAQKfzIAAxQACAm5JE0KAMECABQACAm5JE0KAMECABYAAQkwGcEhAEQAAAAA.Croarik:BAAALgAECgEJAQAAAA==.Crushix:BAABLgAECn81AAINAAkJKhhHHwAfAgANAAkJKhhHHwAfAgAAAA==.',
Cs='Csyasha:BAAALgAECgEJAQAAAA==.',
Cy='Cybear:BAAALgAECgQJBgAAAA==.Cykun:BAABLgAECn8oAAIXAAgJlh/MDAAKAgAXAAgJlh/MDAAKAgAAAA==.',
['Cã']='Cãs:BAAALgADCgkJCgABLgAECgkJGgALALQNAA==.',
Da='Darch:BAABLgAECn8/AAMYAAkJLyRkAQAfAwAYAAkJLyRkAQAfAwAJAAEJPwm2kAAqAAAAAA==.',
De='Deadgripz:BAAALgADCgMJBgAAAA==.Deadjaden:BAAALgADCgEJAQAAAA==.Deathscreams:BAAALgAECgQJBgAAAA==.Deathxreaper:BAAALgAECgQJCgAAAA==.Decessus:BAAALgAECgUJBgAAAA==.Dekig:BAABLgAECn8jAAIFAAgJDRSMRACuAQAFAAgJDRSMRACuAQAAAA==.Demine:BAABLgAECn8lAAIDAAgJLR5BKQAzAgADAAgJLR5BKQAzAgAAAA==.Demonvibe:BAAALgAECgQJBgAAAA==.',
Di='Dico:BAAALgAECgIJAgABLgAFFAYJIAAZAL4dAA==.Dinobots:BAAALgAECgYJDAAAAA==.Dipper:BAABLgAECn8aAAIMAAkJKxifKQASAgAMAAkJKxifKQASAgAAAA==.',
Do='Donbarriga:BAAALgAECgYJCAAAAA==.Dosmojitos:BAAALgADCgcJBwAAAA==.Doublejumps:BAAALgAECgYJCwAAAA==.Doublelung:BAAALgAECgYJEgAAAA==.',
Dr='Draagone:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Drdiddles:BAAALgAECgMJAwAAAA==.',
Du='Duney:BAABLgAECn8sAAIaAAkJfBjNBgA+AgAaAAkJfBjNBgA+AgAAAA==.Dußad:BAAALgAECgMJBwAAAA==.',
['Dé']='Déäth:BAAALgADCgQJBAAAAA==.',
Ec='Eckoe:BAABLgAECn8dAAILAAYJjAY4ZQDAAAALAAYJjAY4ZQDAAAAAAA==.',
Ee='Eekeros:BAAALgADCgUJBQAAAA==.Eeveeko:BAACLgAFFH8HAAIbAAMJ1hGABgDtAAAbAAMJ1hGABgDtAAAuAAQKfzQAAhsACQlfHW8DAIMCABsACQlfHW8DAIMCAAAA.',
Ej='Ejavuday:BAABLgAECn8jAAIDAAkJ0iHBFgCYAgADAAkJ0iHBFgCYAgAAAA==.',
El='Elvudu:BAAALgAECgQJBwAAAA==.',
Em='Emberstrife:BAAALgAECgEJAgAAAA==.',
En='Enerchi:BAAALgAECgIJAgABLgAECgQJDgAEAAAAAA==.',
Er='Erazath:BAAALgAECgQJCAAAAA==.Erianar:BAAALgADCgYJDAAAAA==.Ericdruid:BAABLgAECn8aAAMQAAcJSiD3EgB+AgAQAAcJSiD3EgB+AgALAAEJ6QqZ1gAqAAAAAA==.Ericlock:BAAALgADCgMJAwAAAA==.',
Es='Essia:BAAALgAECgEJAQAAAA==.',
Ev='Eveko:BAAALgADCgIJAQAAAA==.Evera:BAABLgAECn8uAAIFAAkJ6gSPdgAtAQAFAAkJ6gSPdgAtAQAAAA==.Evokinpants:BAAALgAECgcJDwAAAA==.Evos:BAAALgAECgQJBgAAAA==.',
Ex='Excels:BAACLgAFFH8GAAILAAMJoBnkJADqAAALAAMJoBnkJADqAAAuAAQKfxgAAgsACQkBINAEAD4DAAsACQkBINAEAD4DAAAA.Explicatory:BAAALgAECgYJBgABLgAFFAMJBgALAKAZAA==.',
Ey='Eyllion:BAAALgAECgQJBQAAAA==.',
Fa='Falorin:BAAALgADCgMJAwAAAA==.Fastoris:BAAALgADCgEJAQAAAA==.Fauci:BAACLgAFFH8IAAIFAAUJOw1BbgDXAAAFAAUJOw1BbgDXAAAuAAQKfx4AAgUACAk4IRQSAJ0CAAUACAk4IRQSAJ0CAAAA.',
Fb='Fblthelost:BAAALgAECgMJAwAAAA==.',
Fe='Feihao:BAAALgADCggJFQAAAA==.Feile:BAABLgAECn82AAQGAAkJxRezIAAjAgAGAAkJxRezIAAjAgAcAAIJfgu/VwBnAAAdAAEJAAD1LwA+AAAAAA==.Feshh:BAAALgADCgEJAQAAAA==.',
Fi='Fifezilla:BAAALgAECgEJAQAAAA==.Firble:BAAALgADCgYJBgAAAA==.Fireg:BAEALgADCgEJAQABLgAFFAQJBQADADULAA==.Fistbeaver:BAAALgADCgUJBQAAAA==.',
Fl='Flinzza:BAAALgAECgUJBQAAAA==.',
Fo='Foolezz:BAAALgADCgMJAwAAAA==.',
Fr='Fredthedh:BAABLgAECn8cAAIUAAkJZSFUFADeAgAUAAkJZSFUFADeAgAAAA==.',
Fu='Furble:BAAALgADCgYJBgAAAA==.',
Ga='Gaashw:BAAALgAECgIJBgAAAA==.Gadziila:BAAALgADCgEJAQAAAA==.Galcyon:BAAALgADCgEJAQAAAA==.Galiant:BAABLgAECn8kAAIFAAkJRCMoDgC/AgAFAAkJRCMoDgC/AgAAAA==.Gashdk:BAAALgAECgEJAQABLgAECgIJBgAEAAAAAA==.Gator:BAAALgAECgEJAQAAAA==.Gaulish:BAAALgADCgkJCQAAAA==.',
Ge='Geraldo:BAAALgADCgcJBwAAAA==.Gethalyn:BAABLgAECn8UAAIMAAcJKxDHaABSAQAMAAcJKxDHaABSAQAAAA==.Gexz:BAAALgADCgYJDAAAAA==.',
Gh='Ghee:BAAALgAECgEJAgAAAA==.',
Gl='Glaivedaddy:BAAALgAECgEJAQAAAA==.Glenlives:BAAALgADCgkJCQABLgAECgcJGAARAGALAA==.',
Go='Gore:BAAALgAECgUJBQAAAA==.Gottverdammt:BAAALgAECgEJAQABLgAECgYJBwAEAAAAAA==.',
Gr='Graveknight:BAAALgAECgMJAwAAAA==.Graveshot:BAAALgADCgQJBAAAAA==.Greennrry:BAAALgAECgQJBgABLgAFFAIJAgAEAAAAAA==.Greyskin:BAAALgADCgEJAQAAAA==.Grizzabella:BAABLgAECn8qAAILAAkJ9BstCgDaAgALAAkJ9BstCgDaAgAAAA==.Grreenry:BAAALgAFFAIJAgAAAA==.Grriz:BAAALgADCgEJAQAAAA==.Grtmustachio:BAAALgAECgYJBwAAAA==.Grundle:BAAALgAECgMJAwAAAA==.',
Gu='Gularak:BAAALgAECgQJBgAAAA==.Gunghø:BAAALgADCggJDwAAAA==.',
Gy='Gyutaro:BAAALgADCgEJAQAAAA==.',
Ha='Haelellionys:BAAALgADCgQJBAAAAA==.Hanamae:BAAALgADCgEJAQAAAA==.Hangnail:BAAALgAECgIJBAAAAA==.Hanswoloqued:BAABLgAECn8aAAMGAAgJUgtsagAqAQAGAAgJUgtsagAqAQAdAAIJpgENKgBLAAAAAA==.Harmfuljoker:BAAALgADCgQJBAAAAA==.Haxzen:BAAALgADCgMJBAAAAA==.',
He='Healufast:BAABLgAECn8oAAIKAAkJLRsoDABZAgAKAAkJLRsoDABZAgAAAA==.Hellsong:BAAALgAECgMJAwABLgAECgYJBgAEAAAAAA==.Hendo:BAAALgADCgYJBgAAAA==.Heysisters:BAAALgADCgYJBwAAAA==.',
Hi='Hispeas:BAAALgADCgQJBwAAAA==.Hitchkawk:BAAALgAECgEJAQAAAA==.Hitchlock:BAAALgAECgEJAwAAAA==.',
Ho='Holysabeline:BAABLgAECn8/AAINAAkJWBq+DQBuAgANAAkJWBq+DQBuAgAAAA==.Honestleon:BAAALgADCgMJAwABLgAFFAEJAQAEAAAAAA==.Hordechief:BAAALgAFFAIJAgAAAA==.',
Hu='Huchar:BAABLgAECn8wAAMZAAkJAR8MBQCIAgAZAAkJAR8MBQCIAgAeAAEJmgxWewAxAAAAAA==.Huevos:BAAALgAECgEJAQAAAA==.Huntersteve:BAABLgAECn8hAAMfAAgJQCOoCAAIAwAfAAgJQCOoCAAIAwAJAAYJ7CAfIwANAgAAAA==.',
Hy='Hydraxix:BAAALgAECgYJCwAAAA==.',
['Hô']='Hônk:BAAALgADCgEJAQABLgAECgcJGAARAGALAA==.',
Ia='Iamanopcow:BAAALgADCgQJBAAAAA==.Iamspeed:BAAALgADCgQJBAAAAA==.',
Ic='Iceblade:BAABLgAECn8fAAINAAkJKBb2HwAaAgANAAkJKBb2HwAaAgAAAA==.',
If='If:BAAALgAECgMJAwAAAA==.',
Ii='Iityouup:BAAALgADCgYJCAAAAA==.',
Il='Illidaniella:BAAALgAECgYJDwAAAA==.Illsmurfuup:BAABLgAECn8ZAAIYAAkJ9SZoAACnAwAYAAkJ9SZoAACnAwAAAA==.',
In='Infection:BAAALgADCgYJCAAAAA==.Inverse:BAAALgADCgYJBgAAAA==.',
Ir='Ironßest:BAAALgAECgcJCAAAAA==.Irôh:BAAALgAECgEJAQABLgAECgQJCgAEAAAAAA==.',
Is='Ishmael:BAAALgADCgEJAQAAAA==.',
Iv='Ivannas:BAAALgAECgEJAQAAAA==.',
Ja='Jaabroni:BAAALgADCgIJAgAAAA==.Jackymoon:BAABLgAECn8ZAAIMAAcJpSM/HwBIAgAMAAcJpSM/HwBIAgAAAA==.Jaxxion:BAAALgADCgMJBQAAAA==.',
Jd='Jdawg:BAABLgAECn82AAIbAAkJLCVTAABVAwAbAAkJLCVTAABVAwAAAA==.',
Je='Jessaiyan:BAABLgAECn8jAAIUAAkJYx++DACkAgAUAAkJYx++DACkAgAAAA==.',
Ji='Jindo:BAAALgADCgcJBwAAAA==.Jiuni:BAAALgADCgUJBQAAAA==.',
Jj='Jjcjr:BAAALgAECgQJBAABLgAFFAYJGQAgAB4hAA==.',
Ju='Julaudette:BAAALgAECgYJDAAAAA==.Julzaria:BAABLgAECn8VAAIfAAYJBgy7awAOAQAfAAYJBgy7awAOAQAAAA==.Julzoblin:BAAALgAECgQJBQAAAA==.Jurny:BAAALgAECgYJDwAAAA==.Jusdeen:BAABLgAECn8YAAMSAAkJtiKPAwCcAgASAAgJGiKPAwCcAgALAAMJvA/kewCAAAAAAA==.',
Ka='Kadookieii:BAAALgAFFAEJAQAAAA==.Kahlandra:BAABLgAECn83AAMhAAkJCxtjAQBWAgAhAAkJCxtjAQBWAgADAAgJ9gxnbABjAQAAAA==.Kaizer:BAACLgAFFH8GAAIRAAMJhxH4HgDcAAARAAMJhxH4HgDcAAAuAAQKfyQAAhEACAmwGt4YAE0CABEACAmwGt4YAE0CAAAA.Kalo:BAAALgAECgMJAwAAAA==.Kanrethad:BAAALgADCgQJCQABLgAECgcJIwAZABoXAA==.Karina:BAABLgAECn8+AAMUAAkJbCAOCQDQAgAUAAkJbCAOCQDQAgAWAAgJFRLDCACQAQAAAA==.Kastravia:BAAALgAFFAEJAQABLgAFFAQJEgAPAG4GAA==.Kawolski:BAAALgAECgIJBAABLgAFFAQJEgAPAG4GAA==.',
Ke='Kelitarra:BAAALgADCgQJCAAAAA==.Kellibar:BAAALgAECgcJBwAAAA==.Kevin:BAAALgAECgcJCgAAAA==.',
Kh='Khanjuror:BAABLgAECn8tAAIcAAgJ1RQABwCZAQAcAAgJ1RQABwCZAQAAAA==.Kholonoe:BAABLgAECn8bAAIiAAgJbBU5HACOAQAiAAgJbBU5HACOAQAAAA==.Khornedog:BAABLgAECn8iAAIGAAcJKBZUSACDAQAGAAcJKBZUSACDAQAAAA==.Khrama:BAAALgAECgkJEAAAAA==.',
Ki='Kiimachamara:BAAALgADCgIJAwAAAA==.Killik:BAAALgAECgQJBAAAAA==.Kippili:BAAALgADCgQJBAABLgAECgYJCgAEAAAAAA==.Kiritokun:BAAALgADCgYJBAAAAA==.',
Kl='Klapz:BAAALgADCgcJDQABLgAECggJDQAEAAAAAA==.Kleenonean:BAACLgAFFH8KAAIiAAMJtiVYDABVAQAiAAMJtiVYDABVAQAuAAQKf0UAAyIACQl3JRUBAF0DACIACQl3JRUBAF0DAAoAAgnGBlV0AFcAAAAA.',
Kp='Kpyassan:BAAALgAECgYJBQAAAA==.',
Kr='Kravenn:BAAALgAECgMJAwAAAA==.Kreuzritter:BAABLgAECn8zAAIYAAkJORDDCABcAgAYAAkJORDDCABcAgAAAA==.Kritterbug:BAAALgAECggJCAAAAA==.',
Ku='Kungcarefu:BAABLgAECn8VAAICAAYJQxK2PQBPAQACAAYJQxK2PQBPAQAAAA==.Kungfushnaz:BAAALgAECgEJAQAAAA==.Kurzaan:BAAALgAECgIJAgAAAA==.Kurzak:BAAALgAECgQJBwAAAA==.',
Ky='Kyle:BAAALgAECgEJAQAAAA==.',
La='Laciel:BAAALgAECgMJBAABLgAECgkJFAAIAJEbAA==.Lacio:BAABLgAECn8+AAIiAAkJLgoRHgB/AQAiAAkJLgoRHgB/AQAAAA==.Larune:BAAALgADCgQJBwAAAA==.Lavendàh:BAABLgAECn8gAAINAAkJAxzOCwCIAgANAAkJAxzOCwCIAgAAAA==.',
Le='Lemonite:BAABLgAECn8WAAILAAkJcBvkFACOAgALAAkJcBvkFACOAgAAAA==.Lennykoggins:BAAALgAECggJEwAAAA==.Leyru:BAABLgAECn8jAAINAAgJ2iPIAwArAwANAAgJ2iPIAwArAwAAAA==.',
Li='Liberos:BAAALgAECggJEAAAAA==.Lifenight:BAABLgAECn8kAAMjAAkJ5xxiAgCAAgAjAAkJ5xxiAgCAAgAFAAEJvwAGPwEJAAAAAA==.Lilnim:BAAALgADCgQJAgAAAA==.Lithvia:BAAALgAECgYJDQAAAA==.',
Ln='Lninedkhack:BAABLgAECn8kAAMFAAgJZRr1MAD0AQAFAAgJZRr1MAD0AQAIAAgJMAe2IQDvAAAAAA==.',
Lo='Lockdor:BAAALgAECgQJBAAAAA==.Logaar:BAABLgAECn8pAAMNAAkJnhRFEABNAgANAAkJnhRFEABNAgAMAAEJ7gGnVAEgAAAAAA==.Loretharan:BAAALgAECgEJAQAAAA==.Louvuitton:BAAALgADCgcJDgAAAA==.',
Lu='Lunartsy:BAAALgADCggJDgAAAA==.Lustiel:BAAALgAECgYJDAAAAA==.Luticris:BAAALgADCggJFwAAAA==.',
Ly='Lyoric:BAAALgAECgEJAQAAAA==.',
Ma='Madmax:BAAALgADCggJCAAAAA==.Maegot:BAAALgADCgYJBgAAAA==.Magicpants:BAAALgAECgcJCgAAAA==.Magnetto:BAAALgADCgQJBAAAAA==.Maiden:BAAALgADCgUJCAABLgAECgcJIwAZABoXAA==.Malexannius:BAAALgADCgUJCQAAAA==.Mannirot:BAAALgAECgEJAQAAAA==.Mariangel:BAAALgAECgQJBAAAAA==.Marrygold:BAAALgAECgEJAQABLgAECggJHwAFAIMgAA==.Mateus:BAAALgAECgEJAwAAAA==.Maxdeath:BAABLgAECn8lAAIFAAgJ9iO/DQAtAwAFAAgJ9iO/DQAtAwAAAA==.Mazre:BAAALgAECgQJBwAAAA==.',
Me='Megtallica:BAAALgAECgMJBAAAAA==.Mensrea:BAABLgAECn8YAAMHAAYJiBRPUgABAQAHAAUJjhFPUgABAQARAAQJsAxVagCaAAAAAA==.Merlinn:BAAALgADCgMJBgAAAA==.Merrycold:BAABLgAECn8fAAMFAAgJgyBFPABGAgAFAAcJpSFFPABGAgAIAAQJzhJKMwB6AAAAAA==.Merrygold:BAAALgADCgMJAwABLgAECggJHwAFAIMgAA==.Merrygored:BAAALgAECgIJAgABLgAECggJHwAFAIMgAA==.Mess:BAABLgAECn8jAAQZAAcJGhdyEQCBAQAZAAcJGhdyEQCBAQAeAAIJ3gfTlABsAAAaAAMJPQgXRwApAAAAAA==.Methodical:BAAALgADCgUJBQAAAA==.Metophis:BAAALgAECgYJCgAAAA==.',
Mf='Mfboomstick:BAABLgAECn82AAMYAAgJIyZWAgD1AgAYAAgJIyZWAgD1AgAJAAEJlSXeIQBmAAAAAA==.',
Mi='Mikklelee:BAAALgADCgIJAgAAAA==.Missdebby:BAAALgADCgYJCwAAAA==.Mistweaver:BAAALgAECgYJEgAAAA==.Mistweaving:BAAALgAECgMJAwAAAA==.Mizirath:BAAALgAECgQJBAABLgAECggJKQASADofAA==.Miztakswrmde:BAAALgADCgUJBgAAAA==.',
Mo='Moghorva:BAABLgAECn8aAAIkAAkJIBVkCwDYAQAkAAkJIBVkCwDYAQAAAA==.Mojoe:BAAALgAECgQJDAAAAA==.Mommyswaggin:BAAALgAECgkJEwAAAA==.Moonra:BAAALgAECgEJAQAAAA==.Moopocalypse:BAAALgADCgUJBQABLgAECgkJLgAKAOkkAA==.Moopsta:BAAALgADCggJDgABLgAECgkJLgAKAOkkAA==.Moopster:BAABLgAECn8uAAMKAAkJ6STTAACmAwAKAAkJ6STTAACmAwABAAIJnh6xPACrAAAAAA==.Mordekaiserz:BAAALgAECgUJCwAAAA==.Morrgoth:BAAALgADCgEJAQAAAA==.',
Mu='Mucouslurp:BAAALgADCgEJAQAAAA==.',
Na='Nalahni:BAACLgAFFH8HAAIgAAMJ/w6yKQDZAAAgAAMJ/w6yKQDZAAAuAAQKfyIAAiAACQmGGFMPACgCACAACQmGGFMPACgCAAAA.Nanashi:BAAALgAECgMJAwAAAA==.Nastage:BAAALgADCgMJAQAAAA==.Nastus:BAAALgAECgMJAwAAAA==.Nayela:BAAALgAECgYJEAAAAA==.Nazgru:BAAALgADCgcJBgAAAA==.',
Ne='Neptuneakis:BAAALgAECgYJDQAAAA==.Nerfblaster:BAAALgADCgEJAQAAAA==.Newcarsmell:BAAALgAECgEJAwAAAA==.',
Ni='Nicktee:BAAALgAECgUJCQAAAA==.Nightmares:BAAALgAECgcJCgAAAA==.Nightrvn:BAAALgAECgQJBAAAAA==.Nimrose:BAAALgAECgcJDAAAAA==.Niquid:BAABLgAECn8gAAILAAgJPBTEPgBPAQALAAgJPBTEPgBPAQAAAA==.',
No='Nolmac:BAAALgAECgcJEwAAAA==.Notahealer:BAAALgAECgYJBwAAAA==.Noxloxes:BAAALgADCgcJDAAAAA==.',
Np='Npv:BAABLgAFFH8FAAIFAAIJzAb6mgCQAAAFAAIJzAb6mgCQAAAAAA==.',
Ny='Nyssavia:BAAALgADCgcJDgAAAA==.',
Oa='Oakshre:BAABLgAECn8rAAIOAAkJYCCHBQC6AgAOAAkJYCCHBQC6AgAAAA==.',
Ol='Olivertwist:BAAALgAECgQJDgAAAA==.',
Om='Omnimpotent:BAAALgAECgEJAQABLgAECgIJAwAEAAAAAA==.',
On='Ontwarr:BAAALgADCgkJDgAAAA==.Ontwou:BAAALgAECgcJCwAAAA==.',
Op='Ophi:BAAALgAECgYJEQAAAA==.',
Os='Oshaku:BAAALgAECgcJCQAAAQ==.',
Ou='Ouchpotato:BAAALgAECgQJBgABLgAFFAIJBQAXAEMTAA==.',
Pa='Paarthurnax:BAAALgAECgUJBQAAAA==.Palathal:BAAALgAECgUJBQABLgAECggJFgADAPYTAA==.Pallynim:BAAALgADCgQJBwAAAA==.Palms:BAABLgAECn8YAAIOAAkJQyKYBwACAwAOAAkJQyKYBwACAwAAAA==.Pancakezebra:BAABLgAECn8yAAIYAAkJ6BqHCQBHAgAYAAkJ6BqHCQBHAgAAAA==.Pantsftw:BAABLgAECn8fAAMKAAgJQgxXJQBRAQAKAAgJ1QtXJQBRAQABAAEJOwXgVgAxAAAAAA==.Papabear:BAAALgADCgUJBQAAAA==.Parkbreezy:BAABLgAECn8YAAISAAcJBwoIJgCeAAASAAcJBwoIJgCeAAAAAA==.Pawg:BAAALgADCgcJBgAAAA==.',
Pe='Pebbles:BAAALgAECgcJBwAAAA==.Peltier:BAABLgAECn8sAAIDAAkJdCCsFACmAgADAAkJdCCsFACmAgAAAA==.Pendle:BAABLgAECn8eAAMcAAcJ2g3DKQAbAQAGAAcJYww8awAoAQAcAAYJHQvDKQAbAQAAAA==.',
Ph='Phoenix:BAABLgAECn8cAAIMAAcJ4CC+PgAqAgAMAAcJ4CC+PgAqAgAAAA==.',
Pl='Plox:BAAALgAECgYJEwAAAA==.Plurnizz:BAABLgAECn8dAAMGAAkJHQhBZgAzAQAGAAkJHQhBZgAzAQAcAAQJEwHKXwBPAAAAAA==.',
Po='Pocketchange:BAABLgAFFH8IAAIHAAQJfBjyFgA+AQAHAAQJfBjyFgA+AQAAAA==.',
Pu='Puffadin:BAAALgADCgEJAQAAAA==.Puppymoke:BAAALgAECgMJAwAAAA==.Puptart:BAAALgAECgUJBQAAAA==.',
Ra='Raest:BAABLgAECn8bAAICAAgJ4CKSEACVAgACAAgJ4CKSEACVAgABLgAECgkJEAAEAAAAAA==.Raiker:BAAALgAECgMJBAAAAA==.Razzlock:BAAALgAECgEJAQAAAA==.',
Re='Regret:BAAALgAECgcJDQAAAA==.Relovan:BAABLgAECn8nAAMaAAgJ0xENEwByAQAaAAgJ0xENEwByAQAeAAUJSwOYhgClAAAAAA==.Renothidan:BAABLgAECn8gAAIMAAgJyRykNgDeAQAMAAgJyRykNgDeAQAAAA==.Reuben:BAAALgADCggJDQAAAA==.Revin:BAAALgADCgYJBgAAAA==.Revrynth:BAAALgAECgMJAwABLgAECggJKAAZAPQiAA==.Rexorcist:BAAALgADCgYJCwAAAA==.',
Ri='Rickyboby:BAAALgAECgYJBgAAAA==.Righteøus:BAAALgAECgQJCgAAAA==.Rillan:BAABLgAECn8WAAIMAAUJvBZuawBMAQAMAAUJvBZuawBMAQAAAA==.Ripper:BAAALgAECgUJCQAAAA==.Rithcice:BAABLgAECn8vAAIeAAkJViZKAACGAwAeAAkJViZKAACGAwAAAA==.Rizzdolphler:BAACLgAFFH8HAAIMAAMJsQdJRgDYAAAMAAMJsQdJRgDYAAAuAAQKfyUAAwwACAmzHZ4eAEwCAAwACAmzHZ4eAEwCAA0ABgktEWIxAEABAAAA.',
Ro='Roadnurse:BAAALgADCgIJAgAAAA==.Rockntroll:BAAALgADCgIJAgAAAA==.Rodah:BAAALgADCgkJEAAAAA==.Roscoee:BAAALgADCgEJAQAAAA==.',
Rs='Rsk:BAAALgADCgYJCQABLgAECgcJIwAZABoXAA==.',
Ru='Ruins:BAAALgAECgEJAQAAAA==.',
['Rà']='Ràrity:BAAALgADCggJCAAAAA==.',
['Rö']='Rönburgundy:BAABLgAECn8uAAIGAAkJhB6oEACRAgAGAAkJhB6oEACRAgAAAA==.',
Sa='Sanako:BAABLgAECn8oAAIQAAkJxxETFQDTAQAQAAkJxxETFQDTAQAAAA==.Sanastusa:BAAALgADCgYJCAAAAA==.Saneros:BAAALgAECgEJAQABLgAECggJLwAUAAcYAA==.Santoniche:BAAALgAECgUJBQAAAA==.Sap:BAABLgAECn8bAAMXAAcJ0BWrFQCbAQAXAAcJ0BWrFQCbAQAlAAQJQguJEADYAAABLgAECgcJIwAZABoXAA==.Sausiege:BAAALgAECgMJAwAAAA==.Saveserenade:BAAALgAECgUJBQAAAA==.',
Sc='Scarylarry:BAABLgAECn8vAAIUAAgJBxjjNgCfAQAUAAgJBxjjNgCfAQAAAA==.Scyther:BAABLgAECn8WAAMUAAgJNw3LcQBPAQAUAAgJPAzLcQBPAQAmAAUJTQ6aSgDGAAAAAA==.',
Sd='Sdh:BAAALgADCgQJBgAAAA==.',
Se='Seishinokami:BAABLgAECn8YAAIRAAcJYAtiNAAPAQARAAcJYAtiNAAPAQAAAA==.Serenade:BAACLgAFFH8KAAIDAAQJqBEpQQA4AQADAAQJqBEpQQA4AQAuAAQKfyQAAgMACAmuHxYzAKYCAAMACAmuHxYzAKYCAAAA.Setheron:BAABLgAECn8YAAIeAAcJrR1wFwDlAQAeAAcJrR1wFwDlAQAAAA==.Sethron:BAAALgAECgIJAgAAAA==.Señsei:BAAALgAECggJCwAAAA==.',
Sh='Shamminit:BAAALgAECgIJAgAAAA==.Shamtul:BAAALgAECgEJAwAAAA==.Shamwow:BAAALgADCgcJDgAAAA==.Shlea:BAABLgAECn8bAAIgAAgJJQ+6KQBBAQAgAAgJJQ+6KQBBAQAAAA==.Shyva:BAABLgAECn8oAAMZAAgJ9CJcBgBjAgAZAAgJ9CJcBgBjAgAeAAUJfBSXPQD9AAAAAA==.',
Si='Siinestro:BAAALgAECgQJBAAAAA==.Sinlee:BAAALgAECgcJDQABLgAECgkJNAAGAEMiAA==.',
Sl='Slayla:BAAALgAECgMJAwAAAA==.Slimboyjoe:BAAALgADCgcJDgAAAA==.Slimmjim:BAAALgADCgEJAQAAAA==.Slinkstir:BAAALgADCgQJAwAAAA==.',
Sn='Snailtrails:BAAALgAECgcJBwAAAA==.Sneak:BAAALgADCgMJAwABLgAECgYJCwAEAAAAAA==.Sneakcookies:BAAALgAECgIJBAABLgAECgQJDgAEAAAAAA==.',
So='Solendros:BAAALgAECgYJDwAAAA==.Sonthar:BAAALgAECgYJBgAAAA==.Soulborn:BAAALgADCgMJAwAAAA==.',
Sp='Spacehog:BAAALgAECgYJDAAAAA==.Sparticus:BAAALgAECgEJAQAAAA==.Spiro:BAAALgAECgEJAQABLgAECgkJIgAmABYXAA==.Splouge:BAAALgAECgYJBgAAAA==.',
St='Standarshh:BAABLgAECn8yAAIfAAkJAiCbCQDMAgAfAAkJAiCbCQDMAgAAAA==.Stemmz:BAAALgADCgEJAQAAAA==.Stronghand:BAAALgADCgYJBwAAAA==.',
Su='Subtle:BAACLgAFFH8FAAIXAAIJQxPeIACeAAAXAAIJQxPeIACeAAAuAAQKfyYAAxcACAmLHywNAMcCABcACAmLHywNAMcCACcABQmpBosRAIkAAAAA.Sugarbabi:BAABLgAECn8fAAMLAAgJVx8uIQA7AgALAAcJ3x4uIQA7AgAQAAUJhRgGIwBVAQAAAA==.Sugarrush:BAAALgADCgUJBQAAAA==.Sugarshot:BAAALgAECggJCAAAAA==.Sugarthorn:BAAALgADCgkJCQAAAA==.Sulcer:BAAALgADCgMJBAAAAA==.',
Sy='Sylria:BAAALgAECgIJAgAAAA==.Sylrianah:BAABLgAECn8/AAMKAAkJ0CCiAwAbAwAKAAkJ0CCiAwAbAwABAAQJrghJOwCzAAAAAA==.Sylveste:BAACLgAFFH8IAAINAAQJQRjEFQAoAQANAAQJQRjEFQAoAQAuAAQKfyMAAg0ABwkUGiwjAKABAA0ABwkUGiwjAKABAAAA.Sylvfelster:BAAALgAECgYJBwAAAA==.Sylánnia:BAAALgADCgcJBwAAAA==.',
Ta='Ta:BAABLgAECn8ZAAIBAAcJowivJQBCAQABAAcJowivJQBCAQAAAA==.Talis:BAAALgADCgYJBgAAAA==.Tankhiskhan:BAABLgAECn8VAAIIAAgJQA1lHwADAQAIAAgJQA1lHwADAQAAAA==.Tarlis:BAABLgAECn8WAAIdAAgJoBq8BAAqAgAdAAgJoBq8BAAqAgAAAA==.',
Te='Tedrickeyjr:BAAALgAECgEJBgAAAA==.Terithresh:BAAALgADCgMJBAAAAA==.',
Th='Thanil:BAABLgAECn8fAAIMAAcJIBdRUgCIAQAMAAcJIBdRUgCIAQAAAA==.Thenet:BAAALgAECgEJAQAAAA==.',
Ti='Tikamancer:BAAALgADCgEJAQAAAA==.Tilvalhalla:BAABLgAECn8cAAIkAAcJPAogKgAhAQAkAAcJPAogKgAhAQAAAA==.',
To='Todorokii:BAAALgAECgUJCwAAAA==.Tom:BAAALgAECgEJAgABLgAFFAIJAgAEAAAAAA==.Torrin:BAAALgADCgYJBwAAAA==.Tortricid:BAAALgAECgMJBgAAAA==.Totempants:BAAALgAECgYJBgAAAA==.Totinospizza:BAAALgADCgYJBgAAAA==.',
Tr='Trashkan:BAAALgADCgIJAgAAAA==.Trauck:BAAALgADCgEJAQAAAA==.Traumzi:BAAALgAECgEJAQAAAA==.Travvy:BAACLgAFFH8kAAMXAAgJOiImAQBaAgAXAAcJfSEmAQBaAgAlAAIJoR5ECAByAAAuAAQKfyAAAhcACQmtJQEBAMMDABcACQmtJQEBAMMDAAAA.Treezus:BAAALgADCgYJCAAAAA==.Trevmo:BAABLgAECn82AAIZAAkJGiD8AgDVAgAZAAkJGiD8AgDVAgAAAA==.',
Tu='Turaylon:BAAALgAFFAEJAQAAAA==.Turtlebox:BAAALgAECgQJBgAAAA==.',
Ty='Tym:BAAALgAFFAIJAgAAAA==.',
Ug='Ugargro:BAAALgAECgMJBAAAAA==.',
Un='Unapologetic:BAAALgAECggJDAAAAA==.Unbreakabull:BAAALgADCgYJBgAAAA==.Unceejin:BAAALgADCggJEQAAAA==.Unholydk:BAABLgAECn8eAAMIAAYJIRUgIwApAQAIAAYJQhMgIwApAQAFAAUJsw+hogDbAAABLgAECgcJIwAZABoXAA==.',
Va='Valcuna:BAAALgAECgEJAgAAAA==.Valka:BAAALgAECggJEAAAAA==.Vamptouch:BAAALgAECgIJAwABLgAECgYJCwAEAAAAAA==.Vanaan:BAAALgADCgYJBgABLgAECgIJAgAEAAAAAA==.Varidrus:BAAALgAECgMJAwAAAA==.Vaste:BAAALgADCgcJCQAAAA==.',
Ve='Ventrue:BAABLgAECn8jAAIDAAkJ6xWgQgDSAQADAAkJ6xWgQgDSAQAAAA==.Veyle:BAABLgAECn8/AAMXAAkJ0STnAQARAwAXAAkJ0STnAQARAwAlAAEJKh7AGwBJAAAAAA==.',
Vi='Vivian:BAABLgAECn8iAAImAAkJFhdQCwAQAgAmAAkJFhdQCwAQAgAAAA==.',
Vo='Voidsurge:BAABLgAECn8aAAQUAAUJAROGhADCAAAUAAUJyQ+GhADCAAAWAAMJsRLlGwBqAAAmAAEJMhNlSAA4AAABLgAECgcJIwAZABoXAA==.',
Vy='Vyndria:BAAALgAECgQJDAAAAA==.',
We='Weaspore:BAABLgAECn8gAAIFAAgJkR7HKgAOAgAFAAgJkR7HKgAOAgAAAA==.Weasy:BAAALgAECgYJBgAAAA==.',
Wo='Woogidaboogi:BAAALgAECgIJAwAAAA==.Woogieboogie:BAAALgAECgEJAQABLgAECgIJAwAEAAAAAA==.',
Xi='Xiamiel:BAAALgADCgYJCQAAAA==.',
Xl='Xl:BAABLgAECn9WAAMmAAgJ/RxVCwCrAgAmAAgJhxxVCwCrAgAUAAgJJhbJMAC5AQAAAA==.',
Yh='Yharnem:BAAALgAECgcJEgAAAA==.',
Yo='Yogurtpants:BAAALgAECgYJEgAAAA==.Yonny:BAAALgADCgEJAQAAAA==.',
Yu='Yukionna:BAAALgADCgcJCwAAAA==.',
Za='Zabara:BAAALgAECggJEQAAAA==.Zabbystabby:BAAALgADCgcJDAAAAA==.Zakaraki:BAABLgAECn8+AAQoAAkJhCVFAABZAwAoAAkJhCVFAABZAwAgAAcJNyFQEAAbAgAkAAcJTQd5JgBBAQAAAA==.Zaki:BAABLgAECn8aAAIUAAkJTBo4FwBKAgAUAAkJTBo4FwBKAgAAAA==.Zanked:BAAALgADCgQJBAAAAA==.Zarkingu:BAAALgADCgMJAwAAAA==.',
Ze='Zealot:BAAALgADCgYJDQAAAA==.Zeleria:BAAALgAECgUJBgAAAA==.Zeno:BAAALgAFFAIJAgAAAA==.Zerathis:BAABLgAECn80AAIGAAkJQyJbBwDxAgAGAAkJQyJbBwDxAgAAAA==.Zerathül:BAAALgAECgcJEgAAAA==.Zerötwo:BAAALgADCgkJCgAAAA==.Zestul:BAAALgADCgkJFgAAAA==.',
Zi='Zimbobayaga:BAAALgAECgMJAwAAAA==.',
Zo='Zodivine:BAAALgADCgMJAwAAAA==.Zohar:BAAALgADCgEJAgAAAA==.Zooty:BAAALgADCgUJAwAAAA==.Zoshow:BAAALgAECgIJAgAAAA==.',
Zu='Zuggo:BAAALgADCgYJBgAAAA==.',
Zy='Zyrig:BAAALgADCgUJBgAAAA==.',
['Zõ']='Zõshow:BAABLgAECn8UAAMGAAcJmxV0TwBuAQAGAAcJeBV0TwBuAQAcAAEJEh0zYABOAAAAAA==.',
['Ça']='Çaptainçhaos:BAAALgAECgYJBgAAAA==.',
['Ða']='Ðaredevil:BAABLgAECn8iAAIOAAgJNh2xCgBNAgAOAAgJNh2xCgBNAgABLgAECgkJIgAmABYXAA==.',
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
