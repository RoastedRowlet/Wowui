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

local lookup = {'Priest-Discipline','Monk-Brewmaster','Mage-Frost','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Warlock-Demonology','Shaman-Restoration','DeathKnight-Blood','Hunter-Marksmanship','Priest-Holy','Druid-Restoration','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Shaman-Elemental','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Fire','Rogue-Subtlety','Hunter-Survival','Warrior-Protection','Warrior-Arms','Shaman-Enhancement','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Warrior-Fury','Hunter-BeastMastery','Evoker-Augmentation','Mage-Arcane','Priest-Shadow','DeathKnight-Frost','Evoker-Preservation','Rogue-Assassination','DemonHunter-Havoc','Rogue-Outlaw','Evoker-Devastation',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aahzbear:BAAALgAFFAEJAQAAAA==.',
Ab='Abreale:BAAALgADCgMJAwAAAA==.',
Ae='Aeero:BAABLgAECn8UAAIBAAYJNhfEHwCWAQABAAYJNhfEHwCWAQAAAA==.Aerendyl:BAAALgAECgcJCwAAAA==.',
Ai='Aiden:BAACLgAFFH8HAAICAAMJbRADNADCAAACAAMJbRADNADCAAAuAAQKfxQAAgIABgkfHF8qALcBAAIABgkfHF8qALcBAAAA.',
Al='Algros:BAAALgADCgEJAQAAAA==.Alyiriia:BAAALgAECgkJCQAAAA==.',
Am='Amathal:BAABLgAECn8ZAAIDAAgJ+hMCjwC1AQADAAgJ+hMCjwC1AQAAAA==.Amilea:BAAALgAFFAEJAQABLgABCgkJEgAEAAAAAA==.',
An='Anastasia:BAAALgADCggJCAAAAA==.Angelsevoker:BAAALgAECggJCAAAAA==.Angermoonria:BAAALgADCgcJBwAAAA==.Ankheloios:BAAALgADCggJDgAAAA==.Antihiiro:BAAALgAECgMJAwAAAA==.Antipro:BAAALgAFFAEJAQAAAA==.Anubbus:BAAALgAFFAEJAQAAAA==.Anzulok:BAAALgADCgYJAQAAAA==.',
Ar='Arbalest:BAAALgADCgcJBgAAAA==.Aredhela:BAABLgAECn8bAAMFAAgJEhbUGwAOAgAFAAgJEhbUGwAOAgAGAAQJDxcYrgAGAQAAAA==.Arinth:BAAALgADCggJEQAAAA==.Arkadios:BAAALgAECgIJAgAAAA==.Armpit:BAAALgAECgMJAwAAAA==.',
As='Ascanius:BAAALgADCgQJBAAAAA==.Ashiiro:BAAALgAECgcJEAAAAA==.Ashveil:BAAALgAECgUJBQABLgAECgkJJgAHAEEZAA==.Asia:BAABLgAECn8/AAIIAAkJSSVuBABAAwAIAAkJSSVuBABAAwAAAA==.Asmodeius:BAAALgAFFAEJAgAAAA==.Astroprof:BAAALgAECgEJAQABLgAECgYJFAAJAFsaAA==.',
At='Athrea:BAABLgAECn8bAAMHAAkJfBw8HQCFAgAHAAkJHhs8HQCFAgAKAAUJUBuaIQAsAQAAAA==.',
Au='Auntjemima:BAAALgAECgEJAgAAAA==.Aureleus:BAAALgADCgEJAQAAAA==.',
Aw='Away:BAAALgADCgIJAgAAAA==.',
Az='Azaii:BAAALgADCggJCgAAAA==.Azlear:BAAALgAECgkJBgAAAA==.Azrael:BAAALgAECgEJAQAAAA==.',
Ba='Babilouchoux:BAAALgAECgMJBQAAAA==.Ballz:BAAALgADCgYJBgAAAA==.Bano:BAAALgAECgMJAwAAAA==.Barnre:BAAALgAECgYJCQABLgAECgYJDAAEAAAAAA==.Bash:BAAALgAECgcJCwABLgAECggJKAAKAAgbAA==.Baythos:BAAALgAFFAEJAgAAAA==.',
Bb='Bb:BAAALgAECgIJAQAAAA==.',
Bd='Bdssm:BAAALgAECgcJDwAAAA==.',
Be='Beefstick:BAAALgAECgUJBwAAAA==.Berzercarl:BAAALgAECgEJAQAAAA==.Beserkfury:BAABLgAECn8jAAILAAkJOQ2FDACEAQALAAkJOQ2FDACEAQAAAA==.',
Bh='Bhemtu:BAAALgADCgkJEwAAAA==.',
Bi='Biercan:BAAALgAECggJEAAAAA==.Bigcarl:BAAALgADCgMJAwAAAA==.Binke:BAAALgAECgcJEgAAAA==.Bittywhite:BAAALgAECgMJAwAAAA==.Bittywyvern:BAAALgADCgUJCwABLgAECgMJAwAEAAAAAA==.',
Bk='Bkarakh:BAAALgADCgYJDgAAAA==.',
Bl='Blayze:BAABLgAECn8aAAIMAAgJaxTDGwDRAQAMAAgJaxTDGwDRAQAAAA==.Blessidbee:BAAALgAECgEJAQAAAA==.Blightmarx:BAAALgADCgUJCQAAAA==.Blitzwow:BAAALgADCgYJBQAAAA==.Bluemoonflay:BAAALgAECgkJEwAAAA==.Blúnt:BAAALgADCgQJBAAAAA==.',
Bo='Bobheals:BAABLgAECn8kAAMNAAYJAxPmTABIAQANAAUJchbmTABIAQAOAAEJAACqegAAAAAAAA==.Boibye:BAAALgAECgYJDgAAAA==.Bolblock:BAAALgAECgkJDwAAAA==.Bonewolf:BAAALgADCgYJBAAAAA==.Boostedww:BAAALgAECgMJBwAAAA==.',
Br='Brambleclaw:BAABLgAECn8/AAIKAAkJRSOpAwDyAgAKAAkJRSOpAwDyAgAAAA==.Brayker:BAACLgAFFH8FAAIGAAIJLB+KaAC3AAAGAAIJLB+KaAC3AAAuAAQKf0cAAgYACQmjJWoEAEcDAAYACQmjJWoEAEcDAAAA.Breadoneal:BAABLgAECn8pAAMFAAkJ4hmxGwAQAgAFAAgJ9hixGwAQAgAGAAEJ7QVykQEmAAAAAA==.Breeze:BAAALgAECgYJBgAAAA==.Brewed:BAABLgAECn8sAAMPAAgJjxSJIACUAQAPAAgJjxSJIACUAQAQAAEJLwFnuQALAAAAAA==.Brisketbane:BAAALgAECgcJEAAAAA==.Brokenmask:BAACLgAFFH8NAAINAAUJ0RXbFwB8AQANAAUJ0RXbFwB8AQAuAAQKfxUAAw0ACAkOIEobAGECAA0ACAkOIEobAGECABEAAgkLEY1/ADIAAAAA.Broxxar:BAAALgAECgIJAgAAAA==.Bruxxe:BAAALgAECgcJAQAAAA==.Brüenor:BAAALgAECgIJAgAAAA==.',
Bu='Burntroot:BAABLgAECn8gAAISAAcJBQSuWQC7AAASAAcJBQSuWQC7AAAAAA==.',
Ca='Caedwyn:BAABLgAECn8yAAIOAAgJqh+2BgBzAgAOAAgJqh+2BgBzAgAAAA==.Caitrakk:BAABLgAECn8UAAMJAAYJWxqgMgC7AQAJAAYJWxqgMgC7AQASAAUJYhC9TAAVAQAAAA==.Calignus:BAABLgAECn8dAAMGAAgJyRGTnwAdAQAGAAgJyRGTnwAdAQATAAUJVQ8jJwDQAAAAAA==.Captjack:BAABLgAECn8dAAIUAAkJrAt0XQBXAQAUAAkJrAt0XQBXAQAAAA==.Cartilage:BAABLgAECn8lAAIHAAkJXRQoPAD9AQAHAAkJXRQoPAD9AQAAAA==.Catalei:BAAALgAECgYJDwAAAA==.Caution:BAAALgADCgYJCwAAAA==.',
Ce='Celira:BAAALgAECgEJAQAAAA==.Celys:BAAALgAECgIJAgAAAA==.',
Ch='Chickenman:BAAALgAECgEJAQAAAA==.Chillidan:BAAALgAECgQJBgABLgAFFAEJAQAEAAAAAA==.Chiselia:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Choconilla:BAAALgAECgcJEwAAAA==.Chonkmonk:BAAALgADCgQJBAAAAA==.Choppa:BAAALgADCggJCgAAAA==.Chorizo:BAAALgAECgEJAQABLgAECgkJHQAQAIIgAA==.Chupacabrass:BAAALgADCgYJBgAAAA==.Chëbbles:BAAALgADCgMJAwABLgAECgkJHQARAGIWAA==.',
Ci='Cinnomun:BAAALgADCgEJAQAAAA==.',
Co='Combustinme:BAAALgAECgQJBAABLgAECggJLwAUAAcYAA==.Consuming:BAABLgAECn8mAAINAAgJYBSCNgCrAQANAAgJYBSCNgCrAQAAAA==.Coorsbanquet:BAABLgAECn8YAAMVAAgJUBnsBwDlAQAVAAgJUBnsBwDlAQAUAAIJuAkP/wAvAAAAAA==.Coorsbite:BAAALgADCgcJCAAAAA==.Corgh:BAABLgAECn8kAAIWAAYJtw4XBgBIAQAWAAYJtw4XBgBIAQAAAA==.Corrahthecow:BAAALgADCgEJAQAAAA==.Cowardice:BAAALgADCgYJCwAAAA==.',
Cr='Craccjar:BAAALgAECgIJAgAAAA==.Crackjar:BAAALgADCgcJDAAAAA==.Crash:BAECLgAFFH8PAAIUAAYJMBiUIAB/AQAUAAYJMBiUIAB/AQAuAAQKfzcAAxQACAn2JMELANgCABQACAn2JMELANgCABUAAQkwGRMrAEEAAAAA.Croarik:BAAALgAECgEJAQAAAA==.Crushix:BAABLgAECn81AAIFAAkJKhhHHwAfAgAFAAkJKhhHHwAfAgAAAA==.',
Cs='Csyasha:BAAALgAECgYJCAAAAA==.',
Cy='Cybear:BAAALgAECgUJBwAAAA==.Cykun:BAABLgAECn8uAAIXAAkJcSAfBwCjAgAXAAkJcSAfBwCjAgAAAA==.',
['Cã']='Cãs:BAAALgADCgkJCgABLgAECgkJGgANALQNAA==.',
Da='Darch:BAABLgAECn8/AAMYAAkJMCQhAwAAAwAYAAkJMCQhAwAAAwALAAEJPwm2kAAqAAAAAA==.Davidx:BAAALgAECgQJAgAAAA==.',
De='Deadgripz:BAAALgADCgMJBgAAAA==.Deadjaden:BAAALgADCgEJAQAAAA==.Deadlos:BAAALgAECgUJBQAAAA==.Deathscreams:BAAALgAECgQJBgAAAA==.Deathxreaper:BAAALgAECgQJCwAAAA==.Decessus:BAAALgAECgUJBgAAAA==.Dekig:BAABLgAECn8jAAIHAAgJDRTXWQClAQAHAAgJDRTXWQClAQAAAA==.Demine:BAABLgAECn81AAIDAAgJgB9WKABjAgADAAgJgB9WKABjAgAAAA==.Demonvibe:BAAALgAECgQJBgAAAA==.',
Di='Dico:BAAALgAECgIJAgABLgAFFAcJIgAZAHkdAA==.Dinobots:BAAALgAECgYJDAAAAA==.Dipper:BAABLgAECn8cAAIGAAkJExpVNAAXAgAGAAkJExpVNAAXAgAAAA==.Divinator:BAAALgAECgYJCwAAAA==.',
Do='Donbarriga:BAAALgAECgYJCAAAAA==.Dosmojitos:BAAALgADCgcJBwAAAA==.Doublejumps:BAAALgAECgYJCwAAAA==.Doublelung:BAAALgAECgYJEgAAAA==.',
Dr='Draagone:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Drdiddles:BAAALgAECgMJAwAAAA==.',
Du='Duney:BAABLgAECn8/AAIaAAkJoB1+BAC7AgAaAAkJoB1+BAC7AgAAAA==.Dußad:BAAALgAECgMJBwAAAA==.',
['Dé']='Déäth:BAAALgADCgQJBAAAAA==.',
Ec='Eckoe:BAABLgAECn8gAAINAAcJKwbybQDZAAANAAcJKwbybQDZAAAAAA==.',
Ee='Eekeros:BAAALgADCgUJBQAAAA==.Eeveeko:BAACLgAFFH8OAAIbAAQJ7g9RBwAsAQAbAAQJ7g9RBwAsAQAuAAQKfzgAAhsACQmvHtAFAGsCABsACQmvHtAFAGsCAAAA.',
Ej='Ejavuday:BAABLgAECn8sAAIDAAkJPSL6EwDNAgADAAkJPSL6EwDNAgAAAA==.',
El='Elvudu:BAAALgAECgQJBwAAAA==.',
Em='Emberstrife:BAAALgAECgEJAgAAAA==.',
En='Enerchi:BAAALgAFFAEJAQAAAA==.',
Er='Erazath:BAAALgAECgQJCAAAAA==.Erianar:BAAALgAECgIJAgAAAA==.Ericdruid:BAABLgAECn8aAAMRAAcJSiD3EgB+AgARAAcJSiD3EgB+AgANAAEJ6QqZ1gAqAAAAAA==.Ericlock:BAAALgADCgMJAwAAAA==.',
Es='Essia:BAAALgAECgEJAQAAAA==.',
Ev='Eveko:BAAALgADCgIJAQAAAA==.Evera:BAABLgAECn8uAAIHAAkJ6gQhlQAoAQAHAAkJ6gQhlQAoAQAAAA==.Everlst:BAAALgADCgEJAQAAAA==.Evokinpants:BAAALgAECgcJDwAAAA==.Evos:BAAALgAECgQJBgAAAA==.',
Ex='Excels:BAACLgAFFH8KAAINAAMJoBm9LwDjAAANAAMJoBm9LwDjAAAuAAQKfx8AAg0ACQmrIcEEAGEDAA0ACQmrIcEEAGEDAAAA.Explicatory:BAAALgAECgYJBwABLgAFFAMJCgANAKAZAA==.',
Ey='Eyllion:BAAALgAECgQJBQAAAA==.',
Fa='Falorin:BAAALgADCgMJAwAAAA==.Fastoris:BAAALgADCgEJAQAAAA==.Fauci:BAACLgAFFH8JAAIHAAUJOw2hlwC+AAAHAAUJOw2hlwC+AAAuAAQKfx4AAgcACAk4IZEbAI4CAAcACAk4IZEbAI4CAAAA.',
Fb='Fblthelost:BAAALgAECgMJAwAAAA==.',
Fe='Feihao:BAAALgADCggJFQAAAA==.Feile:BAABLgAECn82AAQIAAkJxhcaLgAUAgAIAAkJxhcaLgAUAgAcAAIJfgu/VwBnAAAdAAEJAAD1LwA+AAAAAA==.Fenty:BAAALgAECgUJBQABLgAECggJLwAUAAcYAA==.Feshh:BAAALgADCgEJAQAAAA==.',
Fi='Fifezilla:BAAALgAECgIJAgAAAA==.Firble:BAAALgADCgYJBgAAAA==.Fireg:BAEALgADCgEJAQABLgAFFAQJBQADADULAA==.Fistbeaver:BAAALgADCgUJBQAAAA==.',
Fl='Flinzza:BAAALgAECgUJBQAAAA==.',
Fo='Foolezz:BAAALgAECgMJBAAAAA==.',
Fr='Fredthedh:BAABLgAECn8cAAIUAAkJZSFUFADeAgAUAAkJZSFUFADeAgAAAA==.Fromtheback:BAAALgAECgUJCgAAAA==.',
Fu='Furble:BAAALgADCgYJBgAAAA==.',
Ga='Gaashw:BAAALgAECgIJBgAAAA==.Gadziila:BAAALgADCgEJAQAAAA==.Galcyon:BAAALgADCgEJAQAAAA==.Galiant:BAABLgAECn8mAAIHAAkJ/SMwEwDDAgAHAAkJ/SMwEwDDAgAAAA==.Gashdk:BAAALgAECgEJAQABLgAECgIJBgAEAAAAAA==.Gator:BAAALgAECgEJAQAAAA==.Gaulish:BAAALgADCgkJCQAAAA==.',
Ge='Geraldo:BAAALgAECgIJAgAAAA==.Gethalyn:BAABLgAECn8WAAIGAAcJARGViwA/AQAGAAcJARGViwA/AQAAAA==.Gexz:BAAALgADCgYJDAAAAA==.',
Gh='Ghee:BAAALgAECgEJAgAAAA==.',
Gi='Gianthippo:BAAALgAECgcJDQAAAA==.',
Gl='Glaivedaddy:BAAALgAECgEJAQAAAA==.Glenlives:BAAALgADCgkJCgABLgAECggJKAASAK4NAA==.',
Go='Gore:BAAALgAECgUJBQAAAA==.Gottverdammt:BAAALgAECgEJAQABLgAECgkJEAAEAAAAAA==.',
Gr='Graveknight:BAAALgAECgMJAwAAAA==.Graveshot:BAAALgADCgQJBAAAAA==.Greennrry:BAAALgAFFAEJAQABLgAFFAMJCAAeANsYAA==.Greennrryy:BAAALgAFFAEJAgABLgAFFAMJCAAeANsYAA==.Greenryy:BAAALgAECgIJAwABLgAFFAMJCAAeANsYAA==.Greyskin:BAAALgADCgEJAQAAAA==.Grizzabella:BAABLgAECn80AAINAAkJ9RtVDgDUAgANAAkJ9RtVDgDUAgAAAA==.Grreenry:BAABLgAFFH8IAAIeAAMJ2xj6CAD+AAAeAAMJ2xj6CAD+AAABLgAFFAMJCAAeANsYAA==.Grriz:BAAALgADCgEJAQAAAA==.Grtmustachio:BAAALgAECgkJEAAAAA==.Grundle:BAAALgAECgMJAwAAAA==.',
Gu='Gularak:BAAALgAECgQJBgAAAA==.Gunghø:BAAALgADCggJDwAAAA==.',
Gy='Gyutaro:BAAALgADCgEJAQAAAA==.',
Ha='Haelellionys:BAAALgADCgQJBAAAAA==.Hanamae:BAAALgADCgEJAQAAAA==.Hangnail:BAAALgAECgIJBAAAAA==.Hanswoloqued:BAACLgAFFH8HAAIIAAMJcQbwcwDCAAAIAAMJcQbwcwDCAAAuAAQKfxsAAwgACQmoC4hiAG8BAAgACQmoC4hiAG8BAB0AAgmmAQ0qAEsAAAAA.Harmfuljoker:BAAALgADCgQJBAAAAA==.Haxzen:BAAALgADCgMJBAAAAA==.',
He='Healufast:BAABLgAECn8zAAIMAAkJaxvnDACAAgAMAAkJaxvnDACAAgAAAA==.Hellsong:BAAALgAECgMJAwABLgAECgYJBgAEAAAAAA==.Helstrom:BAAALgADCgEJAQAAAA==.Hendo:BAAALgADCgYJBgAAAA==.Hendoh:BAAALgAECgIJAgAAAA==.Heysisters:BAAALgAECgIJAgAAAA==.',
Hi='Hispeas:BAAALgADCgQJBwAAAA==.Hitchkawk:BAAALgAECgEJAQAAAA==.Hitchlock:BAAALgAECgEJAwAAAA==.',
Ho='Holysabeline:BAACLgAFFH8FAAIFAAIJiBIjMwCFAAAFAAIJiBIjMwCFAAAuAAQKf0gAAgUACQlpGj8RAHcCAAUACQlpGj8RAHcCAAAA.Honestleon:BAAALgADCgMJAwABLgAECgcJFgAGAHgTAA==.Hordechief:BAAALgAFFAIJAgAAAA==.',
Hu='Huchar:BAABLgAECn8/AAMZAAkJICHDAwDhAgAZAAkJICHDAwDhAgAfAAEJmgxXlgAxAAAAAA==.Huevos:BAAALgAECgIJAwAAAA==.Huntersteve:BAABLgAECn8hAAMgAAgJQCOoCAAIAwAgAAgJQCOoCAAIAwALAAYJ7CAfIwANAgAAAA==.',
Hy='Hydraxix:BAAALgAECgYJCwAAAA==.',
['Hô']='Hônk:BAAALgADCgEJAQABLgAECggJKAASAK4NAA==.',
Ia='Iamanopcow:BAAALgADCgQJBAAAAA==.Iamspeed:BAAALgADCgQJBAAAAA==.',
Ic='Iceblade:BAABLgAECn8oAAIFAAkJxxf2HwAaAgAFAAkJxxf2HwAaAgAAAA==.',
If='If:BAAALgAECgMJAwAAAA==.',
Ih='Ihideuseek:BAAALgAECgYJCQABLgAECgkJLAADAD0iAA==.',
Ii='Iityouup:BAAALgADCgYJCAAAAA==.',
Il='Illidaniella:BAABLgAECn8TAAIUAAYJ2wa4pwC1AAAUAAYJ2wa4pwC1AAAAAA==.Illsmurfuup:BAABLgAECn8ZAAIYAAkJ9SZoAACnAwAYAAkJ9SZoAACnAwAAAA==.',
In='Infection:BAAALgADCgYJCAAAAA==.Inverse:BAAALgADCgYJBgAAAA==.',
Ir='Ironßest:BAABLgAECn8UAAIgAAcJzg0+ZwBdAQAgAAcJzg0+ZwBdAQAAAA==.Irôh:BAAALgAECgEJAQABLgAECgUJDgAEAAAAAA==.',
Is='Ishmael:BAAALgADCgEJAQAAAA==.',
Iv='Ivannas:BAAALgAECgIJBAAAAA==.',
Ja='Jaabroni:BAAALgADCgIJAgAAAA==.Jackymoon:BAABLgAECn8aAAIGAAgJXCN5GQCTAgAGAAgJXCN5GQCTAgAAAA==.Jaxxion:BAAALgADCgMJBQAAAA==.',
Jd='Jdawg:BAABLgAECn8/AAIbAAkJQiW+AABHAwAbAAkJQiW+AABHAwAAAA==.',
Je='Jer:BAAALgADCgYJBgAAAA==.Jessaiyan:BAABLgAECn8sAAIUAAkJKyKBBwAFAwAUAAkJKyKBBwAFAwAAAA==.',
Ji='Jindo:BAAALgADCgcJBwAAAA==.Jiuni:BAAALgADCgUJBQAAAA==.',
Jj='Jjcjr:BAAALgAFFAIJAgABLgAFFAYJGgAhAB4hAA==.',
Ju='Julaudette:BAABLgAECn8YAAIdAAYJ/wd/FgDsAAAdAAYJ/wd/FgDsAAAAAA==.Julzaria:BAABLgAECn8cAAIgAAgJWA2QVQCKAQAgAAgJWA2QVQCKAQAAAA==.Julzoblin:BAAALgAECgYJDAAAAA==.Jurny:BAABLgAECn8ZAAMcAAgJiwx3FADtAAAdAAcJigqREQApAQAcAAcJuQp3FADtAAAAAA==.Jusdeen:BAABLgAECn8YAAMOAAkJtiJWBQCZAgAOAAgJGSJWBQCZAgANAAMJvA+nkQB9AAAAAA==.',
Ka='Kadookieii:BAAALgAFFAEJAQAAAA==.Kahlandra:BAABLgAECn83AAMiAAkJChsqAgAzAgAiAAkJChsqAgAzAgADAAgJ9QyOhQBRAQAAAA==.Kairoz:BAAALgAECgYJEQABLgAFFAEJAQAEAAAAAA==.Kaizer:BAACLgAFFH8OAAISAAQJ9BAYIAADAQASAAQJ9BAYIAADAQAuAAQKfyYAAhIACAmrHN4YAE0CABIACAmrHN4YAE0CAAAA.Kalo:BAAALgAECgMJAwAAAA==.Kanrethad:BAAALgAECgQJBAABLgAECggJKAAKAAgbAA==.Karina:BAABLgAECn9HAAMUAAkJoCEnDQDJAgAUAAkJbCAnDQDJAgAVAAkJzxZQBgAYAgAAAA==.Kastravia:BAAALgAFFAIJBAABLgAFFAQJFQAQAG4GAA==.Kawolski:BAAALgAFFAMJBAABLgAFFAQJFQAQAG4GAA==.',
Ke='Kelitarra:BAAALgADCgQJCAAAAA==.Kellibar:BAAALgAECgcJBwAAAA==.Kevin:BAAALgAECgcJCgAAAA==.',
Kh='Khanjuror:BAABLgAECn8tAAIcAAgJ1xRhCQCVAQAcAAgJ1xRhCQCVAQAAAA==.Kholonoe:BAABLgAECn8cAAIjAAkJmRSnHQC5AQAjAAkJmRSnHQC5AQAAAA==.Khornedog:BAABLgAECn8mAAIIAAcJihY4VgCOAQAIAAcJihY4VgCOAQAAAA==.Khrama:BAAALgAECgkJEgAAAA==.',
Ki='Kietemourt:BAAALgADCgUJBQAAAA==.Kiimachamara:BAAALgADCgIJAwAAAA==.Killik:BAAALgAECgQJBAAAAA==.Kinz:BAAALgAECgMJAwABLgABCgkJEgAEAAAAAA==.Kippili:BAAALgADCgQJBAABLgAECgYJCgAEAAAAAA==.Kiritokun:BAAALgADCgYJBAAAAA==.',
Kl='Klapz:BAAALgADCgcJDQABLgAECggJEAAEAAAAAA==.Kleenonean:BAACLgAFFH8QAAIjAAUJ6ySUCACqAQAjAAUJ6ySUCACqAQAuAAQKf1AAAyMACQkBJkMBAF4DACMACQkBJkMBAF4DAAwAAgnGBlV0AFcAAAAA.',
Ko='Kobe:BAAALgAFFAEJAgAAAA==.',
Kp='Kpyassan:BAAALgAECgYJBQAAAA==.',
Kr='Kravenn:BAAALgAECgMJAwAAAA==.Kreuzritter:BAABLgAECn8zAAIYAAkJORDDCABcAgAYAAkJORDDCABcAgAAAA==.Kritterbug:BAAALgAECggJCAAAAA==.',
Ku='Kungcarefu:BAABLgAECn8bAAICAAYJQxImQADoAAACAAYJQxImQADoAAAAAA==.Kungfushnaz:BAAALgAECgEJAQAAAA==.Kurzaan:BAAALgAECgcJAgAAAA==.Kurzak:BAAALgAECgQJBwAAAA==.',
Ky='Kyle:BAAALgAECgEJAQABLgAFFAIJAgAEAAAAAA==.',
La='Laciel:BAAALgAECgMJBAABLgAECgkJGwAHAHwcAA==.Lacio:BAABLgAECn9HAAIjAAkJLwp0KABsAQAjAAkJLwp0KABsAQAAAA==.Larune:BAAALgADCgQJBwAAAA==.Lavendàh:BAABLgAECn8oAAIFAAkJuCBzBABBAwAFAAkJuCBzBABBAwAAAA==.',
Le='Lemonite:BAACLgAFFH8JAAINAAQJnAtMLQDvAAANAAQJnAtMLQDvAAAuAAQKfxYAAg0ACQlwG+QUAI4CAA0ACQlwG+QUAI4CAAAA.Lennykoggins:BAABLgAECn8YAAIgAAgJLBfVQQDFAQAgAAgJLBfVQQDFAQAAAA==.Leyru:BAABLgAECn8sAAIFAAgJISToBAAzAwAFAAgJISToBAAzAwAAAA==.',
Li='Liberos:BAABLgAECn8XAAIJAAgJ0RR7MADYAQAJAAgJ0RR7MADYAQAAAA==.Lifenight:BAABLgAECn8kAAMkAAkJ6BxHBABgAgAkAAkJ6BxHBABgAgAHAAEJvwAGPwEJAAAAAA==.Lilnim:BAAALgAECgYJBgAAAA==.Lithvia:BAAALgAECgYJDQAAAA==.',
Ln='Lninedkhack:BAABLgAECn8mAAMHAAkJQRnoLQA0AgAHAAkJQRnoLQA0AgAKAAgJMQdeLADeAAAAAA==.',
Lo='Lockdor:BAAALgAECgQJBAAAAA==.Logaar:BAABLgAECn80AAMFAAkJSxawEwBdAgAFAAkJSxawEwBdAgAGAAEJ7gFVnwEcAAAAAA==.Loretharan:BAAALgAECgEJAQAAAA==.Louvuitton:BAAALgADCgcJDgAAAA==.',
Lu='Lunartsy:BAAALgADCggJDgAAAA==.Lustiel:BAAALgAECgYJDAAAAA==.Luticris:BAAALgAECgMJBAAAAA==.',
Ly='Lyoric:BAAALgAECgEJAQAAAA==.',
Ma='Madmax:BAAALgADCggJCAAAAA==.Maegot:BAAALgADCgYJBgAAAA==.Magicpants:BAAALgAECgcJCgAAAA==.Magnetto:BAAALgADCggJCgAAAA==.Maiden:BAAALgADCgUJCAABLgAECggJKAAKAAgbAA==.Malexannius:BAAALgADCgUJCQAAAA==.Mannirot:BAAALgAECgEJAQAAAA==.Mariangel:BAAALgAECgUJBwAAAA==.Marrygold:BAAALgAECgEJAgABLgAECgkJIAAHAHYfAA==.Mateus:BAAALgAECgEJBAAAAA==.Maxdeath:BAABLgAECn8lAAIHAAgJ9iO/DQAtAwAHAAgJ9iO/DQAtAwAAAA==.Mazre:BAAALgAECgQJBwAAAA==.',
Me='Megtallica:BAAALgAECgUJBgAAAA==.Mensrea:BAABLgAECn8eAAMJAAYJFhNJUwBIAQAJAAYJFhNJUwBIAQASAAQJsAxVagCaAAAAAA==.Merlinn:BAAALgADCgMJBgAAAA==.Merrycold:BAABLgAECn8gAAMHAAkJdh9FPABGAgAHAAcJpSFFPABGAgAKAAUJ3ROtMgC4AAAAAA==.Merrygold:BAAALgADCgMJAwABLgAECgkJIAAHAHYfAA==.Merrygored:BAAALgAECgIJAgABLgAECgkJIAAHAHYfAA==.Mess:BAABLgAECn8tAAQZAAcJjh53DQD7AQAZAAcJjh53DQD7AQAfAAIJ3gfTlABsAAAaAAMJPQgXRwApAAABLgAECggJKAAKAAgbAA==.Methodical:BAAALgADCgUJBQAAAA==.Metophis:BAAALgAECgYJCgAAAA==.',
Mf='Mfboomstick:BAABLgAECn8/AAMYAAkJNCbIAABlAwAYAAkJNCbIAABlAwALAAEJlSX6KABiAAAAAA==.',
Mi='Mikklelee:BAAALgADCgIJAgAAAA==.Missdebby:BAAALgADCgYJCwAAAA==.Mistweaver:BAABLgAECn8dAAIQAAkJgiDGBABJAwAQAAkJgiDGBABJAwAAAA==.Mistweaving:BAAALgAECgcJAwAAAA==.Mizirath:BAAALgAECgQJBAABLgAECggJMgAOAKofAA==.Miztakswrmde:BAAALgADCgUJBgAAAA==.',
Mo='Moghorva:BAABLgAECn8eAAIlAAkJzBhmCABYAgAlAAkJzBhmCABYAgAAAA==.Mojoe:BAAALgAECgQJDAAAAA==.Mommyswaggin:BAABLgAECn8VAAIMAAkJChRhGwDVAQAMAAkJChRhGwDVAQAAAA==.Moonra:BAAALgAECgEJAQAAAA==.Moopocalypse:BAAALgADCgcJDAABLgAFFAQJBwAMAPAeAA==.Moopsta:BAAALgADCggJDgABLgAFFAQJBwAMAPAeAA==.Moopster:BAACLgAFFH8HAAIMAAQJ8B6mCwBoAQAMAAQJ8B6mCwBoAQAuAAQKfzYAAwwACQmdJT4BAKgDAAwACQmdJT4BAKgDAAEABgnfGc8dALwBAAAA.Mordekaiserz:BAAALgAECgUJCwAAAA==.Morrgoth:BAAALgADCgEJAQAAAA==.',
Mu='Mucouslurp:BAAALgADCgEJAQAAAA==.',
Na='Nalahni:BAACLgAFFH8OAAIhAAQJRQ1lLAD2AAAhAAQJRQ1lLAD2AAAuAAQKfyIAAiEACQmHGMsTACYCACEACQmHGMsTACYCAAAA.Nanashi:BAAALgAECgMJAwAAAA==.Nastage:BAAALgADCgMJAQAAAA==.Nastus:BAAALgAECgMJAwAAAA==.Nayela:BAAALgAECgYJEAAAAA==.Nazgru:BAAALgADCgcJBgAAAA==.',
Ne='Neptuneakis:BAABLgAECn8dAAIRAAkJYhabEgAsAgARAAkJYhabEgAsAgAAAA==.Nerfblaster:BAAALgADCgEJAQAAAA==.Newcarsmell:BAAALgAECgcJCgAAAA==.',
Ni='Nicktee:BAAALgAECgUJCQAAAA==.Nightmares:BAAALgAECgcJCgAAAA==.Nightrvn:BAAALgAECgQJBAAAAA==.Nimrose:BAABLgAECn8WAAIDAAkJogOjmQArAQADAAkJogOjmQArAQAAAA==.Niquid:BAABLgAECn8nAAINAAgJtxUALQDhAQANAAgJtxUALQDhAQAAAA==.',
No='Nolmac:BAABLgAECn8jAAIJAAgJVSMsCwDwAgAJAAgJVSMsCwDwAgAAAA==.Notahealer:BAAALgAFFAEJAQAAAA==.Noxloxes:BAAALgADCgcJDAAAAA==.',
Np='Npv:BAABLgAFFH8HAAIHAAIJgQ3cvgCJAAAHAAIJgQ3cvgCJAAAAAA==.',
Ny='Nyssavia:BAAALgADCgcJDgAAAA==.',
Oa='Oakshre:BAABLgAECn80AAIPAAkJnSDtBQDeAgAPAAkJnSDtBQDeAgAAAA==.',
Ob='Obliteration:BAAALgAECgYJBgABLgAFFAEJAQAEAAAAAA==.',
Ol='Olivertwist:BAAALgAECgQJDgABLgAFFAEJAQAEAAAAAA==.',
Om='Omnimpotent:BAAALgAECgEJAQABLgAECgIJBQAEAAAAAA==.',
On='Ontwarr:BAAALgADCgkJEAAAAA==.Ontwou:BAABLgAECn8VAAIgAAgJ4xiiMwD3AQAgAAgJ4xiiMwD3AQAAAA==.',
Op='Ophi:BAAALgAECgYJEQAAAA==.',
Os='Oshaku:BAAALgAECgcJDAAAAQ==.',
Ou='Ouchpotato:BAAALgAECggJEAABLgAFFAMJCwAXAAkaAA==.',
Pa='Paarthurnax:BAAALgAECgUJBQAAAA==.Palathal:BAAALgAECgUJBgABLgAECggJGQADAPoTAA==.Pallynim:BAAALgADCgQJBwAAAA==.Palms:BAACLgAFFH8JAAIPAAQJNBp7DQA+AQAPAAQJNBp7DQA+AQAuAAQKfxgAAg8ACQlDIpgHAAIDAA8ACQlDIpgHAAIDAAAA.Pancakezebra:BAABLgAECn8yAAIYAAkJ6Rp2DgA1AgAYAAkJ6Rp2DgA1AgAAAA==.Pantsftw:BAABLgAECn8fAAMMAAgJQwzkLgA/AQAMAAgJ1QvkLgA/AQABAAEJQQUfbAAxAAAAAA==.Papabear:BAAALgADCgUJBQAAAA==.Parkbreezy:BAABLgAECn8bAAIOAAcJBwpgNwChAAAOAAcJBwpgNwChAAAAAA==.Passera:BAAALgAECgcJCAAAAA==.Pawg:BAAALgADCgcJBgAAAA==.',
Pe='Pebbles:BAAALgAECgcJBwAAAA==.Peltier:BAABLgAECn8sAAIDAAkJdCCkIACHAgADAAkJdCCkIACHAgAAAA==.Pendle:BAABLgAECn8sAAMIAAgJFA5NWwCBAQAIAAgJfg1NWwCBAQAcAAYJHQvDKQAbAQAAAA==.',
Ph='Phoenix:BAABLgAECn8lAAIGAAkJjB4MIwBhAgAGAAkJjB4MIwBhAgAAAA==.',
Pl='Plox:BAAALgAECgYJEwAAAA==.Plurnizz:BAABLgAECn8dAAMIAAkJHQgdfQA0AQAIAAkJHQgdfQA0AQAcAAQJEwHKXwBPAAAAAA==.',
Po='Pocketchange:BAACLgAFFH8QAAIJAAQJwBjFJAAvAQAJAAQJwBjFJAAvAQAuAAQKfxUAAxIACQniGnEqAMIBABIABgnWHHEqAMIBAAkABgm/FzJLAFYBAAAA.',
Pu='Puffadin:BAAALgADCgEJAQAAAA==.Puppymoke:BAAALgAECgMJAwAAAA==.Puptart:BAAALgAECgUJBQAAAA==.',
Ra='Raest:BAABLgAECn8oAAICAAgJyCQiBQDiAgACAAgJyCQiBQDiAgABLgAECgkJEgAEAAAAAA==.Raiker:BAAALgAECgMJBAAAAA==.Ranch:BAAALgAECgEJAQAAAA==.Razzlock:BAAALgAECgEJAQAAAA==.',
Re='Regret:BAAALgAECggJEAAAAA==.Relovan:BAABLgAECn8vAAMaAAkJ6RBKEwCvAQAaAAkJ6RBKEwCvAQAfAAUJSwOYhgClAAAAAA==.Renothidan:BAACLgAFFH8HAAIGAAMJrxQuUwDmAAAGAAMJrxQuUwDmAAAuAAQKfyEAAgYACQlpG2U3AAsCAAYACQlpG2U3AAsCAAAA.Reuben:BAAALgAECgUJBQAAAA==.Revin:BAAALgADCgYJBgAAAA==.Revrynth:BAAALgAECggJEAABLgAECggJKQAZAPUiAA==.Rexorcist:BAAALgAECgYJBgAAAA==.',
Ri='Rickyboby:BAAALgAECggJDAAAAA==.Righteøus:BAAALgAECgUJDwAAAA==.Rillan:BAABLgAECn8aAAIGAAYJ8xarigBAAQAGAAYJ8xarigBAAQAAAA==.Rin:BAAALgAECgkJCQABLgAECgkJPwAIAEklAA==.Ripper:BAAALgAECgUJCQAAAA==.Rithcice:BAABLgAECn84AAMfAAkJtCaIAACFAwAfAAkJqSaIAACFAwAZAAcJ/yOXBwBzAgAAAA==.Rizzdolphler:BAACLgAFFH8PAAIGAAQJqRTtMAAyAQAGAAQJqRTtMAAyAQAuAAQKfygAAwYACAmyHfEtADACAAYACAmyHfEtADACAAUABgktEYg9ADgBAAAA.',
Ro='Roadnurse:BAAALgADCgIJAgAAAA==.Rockntroll:BAAALgADCgIJAgAAAA==.Rodah:BAAALgADCgkJEAAAAA==.Roscoee:BAAALgADCgEJAQAAAA==.',
Rs='Rsk:BAAALgADCgYJCQABLgAECggJKAAKAAgbAA==.',
Ru='Ruins:BAAALgAECgEJAQAAAA==.',
['Rà']='Ràrity:BAAALgADCggJCAAAAA==.',
['Rö']='Rönburgundy:BAACLgAFFH8GAAIIAAMJ8AxoagDWAAAIAAMJ8AxoagDWAAAuAAQKfy4AAggACQmNHh4aAHoCAAgACQmNHh4aAHoCAAAA.',
Sa='Sanako:BAABLgAECn8oAAIRAAkJxxFnGwDVAQARAAkJxxFnGwDVAQAAAA==.Sanastusa:BAAALgADCgYJCAAAAA==.Saneros:BAAALgAECggJCQABLgAECggJLwAUAAcYAA==.Santoniche:BAAALgAECgUJBAAAAA==.Sap:BAABLgAECn8cAAMXAAcJ0BWjHgCGAQAXAAcJ0BWjHgCGAQAmAAQJQgtUFADPAAABLgAECggJKAAKAAgbAA==.Sausiege:BAAALgAECgMJAwAAAA==.Saveserenade:BAAALgAECgUJBQAAAA==.',
Sc='Scarylarry:BAABLgAECn8vAAIUAAgJBxjRRwCXAQAUAAgJBxjRRwCXAQAAAA==.Scyther:BAACLgAFFH8JAAMnAAMJlg1hFQDGAAAnAAMJQg1hFQDGAAAUAAIJRwPxeQBrAAAuAAQKfxgAAxQACQlBD8txAE8BABQACAk9DMtxAE8BACcABglZEZdBAIoAAAAA.',
Sd='Sdh:BAAALgADCgQJBgAAAA==.',
Se='Seishinokami:BAABLgAECn8oAAISAAgJrg1CMgBZAQASAAgJrg1CMgBZAQAAAA==.Senala:BAAALgAECgEJAQAAAA==.Serenade:BAACLgAFFH8KAAIDAAQJqBHLWQAfAQADAAQJqBHLWQAfAQAuAAQKfyQAAgMACAmuHxYzAKYCAAMACAmuHxYzAKYCAAAA.Setheron:BAABLgAECn8oAAIfAAgJiSHcCgClAgAfAAgJiSHcCgClAgAAAA==.Sethron:BAAALgAECgIJAgAAAA==.Señsei:BAAALgAECggJCwAAAA==.',
Sh='Shamminit:BAAALgAECgIJAgAAAA==.Shamtul:BAAALgAECgEJAwAAAA==.Shamwow:BAAALgADCgcJDgAAAA==.Shlea:BAACLgAFFH8JAAIhAAMJmgeBPgCsAAAhAAMJmgeBPgCsAAAuAAQKfx0AAiEACQn7EKslAJYBACEACQn7EKslAJYBAAAA.Shyva:BAABLgAECn8pAAMZAAgJ9SIxBwC4AgAZAAgJ9SIxBwC4AgAfAAUJ9xegSgAEAQAAAA==.',
Si='Siinestro:BAAALgAECgQJBAAAAA==.Sinlee:BAAALgAECgcJDgABLgAECgkJOgAIAEMiAA==.',
Sl='Slayla:BAAALgAECgUJDAAAAA==.Slimboyjoe:BAAALgADCgcJDgAAAA==.Slimmjim:BAAALgADCgEJAQAAAA==.Slinkstir:BAAALgADCgQJAwAAAA==.',
Sn='Snailtrails:BAAALgAECgcJBwAAAA==.Sneak:BAAALgADCgMJAwABLgAECgYJCwAEAAAAAA==.Sneakcookies:BAAALgAECgMJBwABLgAFFAEJAQAEAAAAAA==.',
So='Soggyundies:BAAALgAECgQJBAAAAA==.Solendros:BAAALgAECgYJDwAAAA==.Sonthar:BAAALgAECgYJBgAAAA==.Soulborn:BAAALgADCgMJAwAAAA==.Soulelf:BAAALgADCgYJBgAAAA==.',
Sp='Spacehog:BAAALgAECgYJDAAAAA==.Sparticus:BAAALgAECgEJAQAAAA==.Spiro:BAAALgAECgEJAQABLgAECgkJLgAPAOYfAA==.Splouge:BAAALgAECgYJBgAAAA==.',
St='Standarshh:BAABLgAECn88AAIgAAkJdSK4BwANAwAgAAkJdSK4BwANAwAAAA==.Stemmz:BAAALgADCgEJAQAAAA==.Stronghand:BAAALgADCgYJBwAAAA==.',
Su='Subtle:BAACLgAFFH8LAAIXAAMJCRriHgAAAQAXAAMJCRriHgAAAQAuAAQKfycAAxcACQnwHiwNAMcCABcACQnwHiwNAMcCACgABQmpBh0XAIgAAAAA.Sugarbabi:BAABLgAECn8hAAMNAAkJDR8uIQA7AgANAAcJ3x4uIQA7AgARAAYJRRjqIgCYAQAAAA==.Sugarrush:BAAALgADCgUJBQAAAA==.Sugarshot:BAAALgAECggJCAAAAA==.Sugarthorn:BAAALgADCgkJCQAAAA==.Sulcer:BAAALgADCgMJBAAAAA==.',
Sw='Swiftwing:BAAALgADCgEJAQAAAA==.',
Sy='Sylria:BAAALgAECgIJAgAAAA==.Sylrianah:BAABLgAECn9IAAQMAAkJ0CD+BQAFAwAMAAkJ0CD+BQAFAwAjAAkJ4QhHKgBgAQABAAQJrgiaTwCSAAAAAA==.Sylveste:BAACLgAFFH8SAAIFAAUJLiOWCgDoAQAFAAUJLiOWCgDoAQAuAAQKfyMAAgUABwkUGkUtAJQBAAUABwkUGkUtAJQBAAAA.Sylvfelster:BAAALgAECgYJBwAAAA==.Sylánnia:BAAALgADCgcJBwAAAA==.',
Ta='Ta:BAABLgAECn8aAAIBAAcJpAgJMgAtAQABAAcJpAgJMgAtAQAAAA==.Talis:BAAALgAECgEJAQAAAA==.Tankhiskhan:BAABLgAECn8VAAIKAAgJQA1nKQDyAAAKAAgJQA1nKQDyAAAAAA==.Tarlis:BAABLgAECn8YAAIdAAgJ9xq8BAAqAgAdAAgJ9xq8BAAqAgAAAA==.',
Te='Tedrickeyjr:BAAALgAECgEJBgAAAA==.Terithresh:BAAALgADCgMJBAAAAA==.',
Th='Thanil:BAABLgAECn8qAAIGAAkJsBeNLgAtAgAGAAkJsBeNLgAtAgAAAA==.Thenet:BAAALgAECgEJAwAAAA==.',
Ti='Tie:BAAALgAECgQJBAAAAA==.Tikamancer:BAAALgADCgEJAQAAAA==.Tilvalhalla:BAABLgAECn8cAAIlAAcJPAogKgAhAQAlAAcJPAogKgAhAQAAAA==.',
To='Todorokii:BAAALgAECgUJDQAAAA==.Tom:BAAALgAECgEJAgABLgAFFAIJAgAEAAAAAA==.Torrin:BAAALgADCgYJBwAAAA==.Tortricid:BAAALgAECgMJBgAAAA==.Totaldchtree:BAAALgAECgEJAQAAAA==.Totempants:BAAALgAECgYJBgAAAA==.Totinospizza:BAAALgADCgYJBgAAAA==.',
Tr='Trashkan:BAAALgADCgIJAgAAAA==.Trauck:BAAALgADCgEJAQAAAA==.Traumzi:BAAALgAECgEJAQAAAA==.Travvy:BAACLgAFFH8oAAMXAAgJKCJOAQD+AQAXAAcJZyFOAQD+AQAmAAIJoR7YCgBtAAAuAAQKfyIAAhcACQkWJgEBAMMDABcACQkWJgEBAMMDAAAA.Treezus:BAAALgADCgYJCAAAAA==.Trevmo:BAABLgAECn82AAIZAAkJGyA3BQC1AgAZAAkJGyA3BQC1AgAAAA==.',
Tu='Turaylon:BAAALgAFFAEJAQAAAA==.Turtlebox:BAAALgAECgQJBgAAAA==.',
Ty='Tym:BAAALgAFFAIJAgAAAA==.',
Ug='Ugargro:BAAALgAECgQJCwAAAA==.',
Un='Unapologetic:BAAALgAECggJDAAAAA==.Unbreakabull:BAABLgAFFH8HAAIRAAQJ4SXpCQC1AQARAAQJ4SXpCQC1AQAAAA==.Unceejin:BAAALgADCggJEQAAAA==.Unholydk:BAABLgAECn8oAAMKAAgJCBuHDQAXAgAKAAgJCBuHDQAXAgAHAAUJsw/KzwDQAAAAAA==.',
Va='Valcuna:BAAALgAECgEJAgAAAA==.Valka:BAABLgAECn8XAAIeAAgJ3QgzGgAVAQAeAAgJ3QgzGgAVAQAAAA==.Vamptouch:BAAALgAECgIJAwABLgAECgYJCwAEAAAAAA==.Vanaan:BAAALgAECgIJAgABLgAECgYJBwAEAAAAAA==.Varidrus:BAAALgAECgMJAwAAAA==.Vaste:BAAALgADCgcJCQAAAA==.',
Ve='Ventrue:BAABLgAECn8jAAIDAAkJ6xWxVADGAQADAAkJ6xWxVADGAQAAAA==.Veyle:BAABLgAECn8/AAMXAAkJ1yQvBADpAgAXAAkJ1yQvBADpAgAmAAEJKh7AGwBJAAAAAA==.',
Vi='Vivian:BAABLgAECn8sAAInAAkJqRkPCgBrAgAnAAkJqRkPCgBrAgABLgAECgkJLgAPAOYfAA==.',
Vo='Voidsurge:BAABLgAECn8pAAQnAAcJTRdjIgBAAQAnAAUJMxtjIgBAAQAVAAUJGRHMFgDSAAAUAAUJyQ/zogC+AAABLgAECggJKAAKAAgbAA==.',
Vy='Vyndria:BAAALgAECgQJDAAAAA==.',
Wa='Wardell:BAAALgADCgEJAgAAAA==.',
We='Weaspore:BAABLgAECn8hAAIHAAgJlR62OgACAgAHAAgJlR62OgACAgAAAA==.Weasy:BAAALgAECgkJDgAAAA==.',
Wo='Woogidaboogi:BAAALgAECgIJBQAAAA==.Woogieboogie:BAAALgAECgEJAQABLgAECgIJBQAEAAAAAA==.',
Xi='Xiamiel:BAAALgADCgYJCQAAAA==.',
Xl='Xl:BAABLgAECn9WAAMnAAgJ/RxVCwCrAgAnAAgJhxxVCwCrAgAUAAgJJxaQPgC3AQAAAA==.',
Ya='Yaitoopmfp:BAAALgAECgEJAQABLgAECgkJIAAHAHYfAA==.',
Yh='Yharnem:BAABLgAECn8XAAICAAcJ8hCaKgBPAQACAAcJ8hCaKgBPAQAAAA==.',
Yo='Yogurtpants:BAAALgAECgYJEgAAAA==.Yonny:BAAALgADCgEJAQAAAA==.',
Yu='Yukionna:BAAALgADCgcJCwAAAA==.',
Za='Zabara:BAABLgAECn8bAAIJAAgJgSEVDgDNAgAJAAgJgSEVDgDNAgAAAA==.Zabbystabby:BAAALgADCgkJDgAAAA==.Zakaraki:BAABLgAECn8+AAQpAAkJhCWFAABFAwApAAkJhCWFAABFAwAhAAcJNyHMFgAJAgAlAAcJTAd5JgBBAQAAAA==.Zaki:BAABLgAECn8aAAIUAAkJThpnHwBEAgAUAAkJThpnHwBEAgAAAA==.Zanked:BAAALgADCgQJBAAAAA==.Zarkingu:BAAALgADCgMJAwAAAA==.',
Ze='Zealot:BAAALgAFFAEJAQAAAA==.Zeleria:BAAALgAECgUJBgAAAA==.Zeno:BAAALgAFFAIJAgAAAA==.Zephyr:BAAALgAECgQJBAAAAA==.Zerathis:BAABLgAECn86AAIIAAkJQyI4DADfAgAIAAkJQyI4DADfAgAAAA==.Zerathül:BAAALgAECgcJEgAAAA==.Zerötwo:BAAALgADCgkJCgAAAA==.Zestul:BAAALgADCgkJFgAAAA==.',
Zi='Zimbobayaga:BAAALgAECgMJAwAAAA==.',
Zo='Zodivine:BAAALgADCgMJAwAAAA==.Zohar:BAAALgADCgEJAgAAAA==.Zooty:BAAALgADCgUJAwAAAA==.Zoshow:BAAALgAECgYJBwAAAA==.',
Zu='Zuggo:BAAALgADCgYJBgAAAA==.',
Zy='Zyrig:BAAALgADCgUJBgAAAA==.',
['Zõ']='Zõshow:BAABLgAECn8XAAMIAAcJmxW3ZwBjAQAIAAcJeBW3ZwBjAQAcAAEJEh0zYABOAAAAAA==.',
['Ça']='Çaptainçhaos:BAAALgAECgYJCgAAAA==.',
['Ða']='Ðaredevil:BAABLgAECn8uAAIPAAkJ5h/yBQDdAgAPAAkJ5h/yBQDdAgAAAA==.',
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
