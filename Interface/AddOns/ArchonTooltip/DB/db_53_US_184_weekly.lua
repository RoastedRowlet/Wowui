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

local lookup = {'Monk-Windwalker','Priest-Holy','Priest-Shadow','Unknown-Unknown','Mage-Arcane','Warrior-Arms','Warrior-Protection','Druid-Feral','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Mage-Frost','Mage-Fire','Paladin-Retribution','Warrior-Fury','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','DeathKnight-Blood','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver','Monk-Brewmaster',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Acefu:BAABNQAECn8ZAAIBAAcK3R8SGACEAgABAAcK3R8SGACEAgAAAA==.Acornella:BAABNQAECn8ZAAMCAAkKoRIbTwAzAgACAAkKoRIbTwAzAgADAAIKABC6aQBXAAABNQAFFAEIAQAEAAAAAA==.Acornkei:BAAANQAFFAEIAQAAAA==.',
Ad='Adonsia:BAAANQADCgQIBAAAAA==.Adreva:BAAANQAECgUIEAAAAA==.',
Ae='Aelana:BAAANQADCgQIBAAAAA==.Aendor:BAAANQADCgcIBwABNQAFFAUICQAFACkRAA==.Aerea:BAAANQAECgEIAwABNQAECgcIGQAGAG0RAA==.Aevastraa:BAAANQADCgEIAQABNQAECggIIgAHALsOAA==.',
Ai='Ailanthus:BAABNQAECn8WAAQIAAgKcgpXIAAQAQAIAAUKMg1XIAAQAQAJAAUKZgMPiACuAAAKAAIKKAVrbQBJAAAAAA==.',
Al='Albinophil:BAAANQADCgIIAgABNQAECgYIEAAEAAAAAA==.Aleyah:BAAANQAECggIBAAAAA==.Alloisaber:BAAANQABCgEIAQAAAA==.Alunne:BAAANQADCgQIBAAAAA==.',
Am='Amna:BAAANQAECgUIDQAAAA==.',
An='Andrelsia:BAAANQAECgEIAQAAAA==.Andrilla:BAAANQADCgYJDAAAAA==.Ankeseth:BAAANQADCggJDQAAAA==.',
Ar='Aracelis:BAAANQADCggICAAAAA==.Araxiel:BAAANQAECgEIBAAAAA==.Archangël:BAAANQAECgEIAQAAAA==.Arkenos:BAAANQAECgEIAQAAAA==.Arén:BAABNQAECn8gAAMLAAgKUCAmKwBEAgALAAYKfCEmKwBEAgAMAAUKcBzHNwCBAQAAAA==.',
As='Ashenshugär:BAAANQADCgcIEQAAAA==.Aszian:BAAANQABCgcICgAAAA==.Aszun:BAABNQAECn8eAAINAAcKyxAkngDGAQANAAcKyxAkngDGAQAAAA==.',
At='Atractiva:BAABNQAECn8jAAMOAAgKJQn0EgB1AQAOAAgKsgj0EgB1AQAPAAgKzQRaBABoAQAAAA==.',
Au='Augment:BAAANQADCggICAABNQAECggIGwAQAGEHAA==.Aura:BAAANQABCgQIBAAAAA==.',
Az='Azmar:BAAANQADCgIIAgAAAA==.Azuri:BAAANQAECgEIAQABNQAECgEIAgAEAAAAAA==.',
Ba='Balain:BAABNQAECn8ZAAMGAAcKbREHowDAAQAGAAcKbREHowDAAQAHAAQKNQVAMwCXAAAAAA==.',
Be='Bear:BAAANQAECgEIAgAAAA==.Beardchi:BAAANQADCgEIAQAAAA==.Bearzerk:BAABNQAECn8WAAIRAAgKzg1FDgDJAQARAAgKzg1FDgDJAQAAAA==.Benathar:BAAANQAECgUICwAAAA==.Bethela:BAAANQABCgYIBgABNQAECgcIHgANAMsQAA==.',
Bi='Birgir:BAAANQAECgQIBAABNQAECgYIGgASADkeAA==.',
Bl='Blackmagék:BAAANQAECgEIAQAAAA==.Blaston:BAAANQAECgUIEgAAAA==.Blightbeard:BAAANQADCggIDgAAAA==.Bloodthorn:BAABNQAECn8WAAQTAAcKtAQGMAA6AQATAAcKtAQGMAA6AQAUAAEKyAVJowAuAAAVAAIKPAHCHAArAAAAAA==.',
Bo='Boogiepop:BAAANQAECgEIAQAAAA==.Boomnescient:BAAANQADCgYICwAAAA==.Bottomdps:BAABNQAECn8qAAIWAAkKSBzAIwD1AgAWAAkKSBzAIwD1AgAAAA==.',
Br='Bramis:BAAANQADCggIDQAAAA==.Branor:BAAANQAECgEIAgAAAA==.Bransonian:BAAANQADCgQJBgAAAA==.Brantu:BAABNQAECn8eAAMXAAcK1wPqTQCUAAAYAAcK1wOL3gAHAQAXAAUKrQHqTQCUAAAAAA==.Braultus:BAABNQAECn8fAAIZAAgKhxkfNgAwAgAZAAgKhxkfNgAwAgAAAA==.Bravehearth:BAAANQADCgEIAQAAAA==.Breuddwydwr:BAAANQADCgEIAQAAAA==.Brewtality:BAAANQAECgQIBQAAAA==.Breyastrasza:BAAANQADCgYIDwAAAA==.',
Ca='Caanu:BAACNQAFFH8JAAIFAAUKKREkIQB3AQAFAAUKKREkIQB3AQA1AAQKfyIAAgUACQpiGutYAM4CAAUACQpiGutYAM4CAAAA.Calydonia:BAAANQAECgIIBAAAAA==.',
Ce='Celdiseth:BAAANQADCggICwAAAA==.Cerdwin:BAAANQAECgUIDgABNQAECggIIgAKAN0VAA==.',
Ch='Charferad:BAAANQAECgEIAQAAAA==.Chatter:BAAANQADCgcICAAAAA==.Cheeseydeath:BAEANQAECgMIAwAAAA==.Chibeard:BAAANQAECgUICwAAAA==.',
Cl='Clevercrane:BAAANQAECgMIAwABNQAECggIFQAUAB0hAA==.',
Co='Coolbro:BAAANQADCgcICAAAAA==.Corialis:BAABNQAECn8dAAMaAAgKzRSfmgBAAQAaAAYKkg+fmgBAAQAWAAYKKgtiqgA7AQAAAA==.',
Cr='Crom:BAABNQAECn8pAAIbAAgKbRFeFAAfAgAbAAgKbRFeFAAfAgAAAA==.Crying:BAAANQAECgQICQAAAA==.',
Cy='Cyn:BAAANQADCgQIBgAAAA==.',
Da='Dandarred:BAABNQAECn8dAAMcAAcKygmskwBhAQAcAAcKygmskwBhAQAQAAQK9QXdSAGkAAAAAA==.Dantey:BAAANQADCggICgABNQAECggIGwAQAGEHAA==.Darkwyn:BAAANQADCgUIBQAAAA==.Dawne:BAABNQAECn8UAAIcAAkK3xc4MQCeAgAcAAkK3xc4MQCeAgAAAA==.Dazanna:BAABNQAECn8jAAMcAAgKqBbZTQAwAgAcAAgKqBbZTQAwAgAQAAEKAABunwE0AAAAAA==.Dazjaxx:BAAANQABCgYICQAAAA==.Dazre:BAAANQAECgIIAgAAAA==.',
De='Deeminor:BAAANQADCgIJAgAAAA==.Demeisen:BAABNQAECn8jAAILAAgKUBC0OADoAQALAAgKUBC0OADoAQAAAA==.Demonizerr:BAAANQAECgEIAQABNQAECggIGwAQAGEHAA==.',
Di='Diksensei:BAAANQAECgEIBAAAAA==.Diod:BAAANQAECgUICQAAAA==.',
Dr='Dracomage:BAAANQADCgMIBgAAAA==.Dracotincan:BAAANQADCgIIAgAAAA==.Draegis:BAAANQAECgEIAQAAAA==.Dragyns:BAABNQAECn8hAAIUAAkKJiCYFQDMAgAUAAkKJiCYFQDMAgAAAA==.Dragynslance:BAAANQAECgEIAQABNQAECgkJIQAUACYgAA==.Drayper:BAAANQAECgcIEQAAAA==.',
Du='Dunbarke:BAABNQAECn8aAAQSAAYKOR6sBwAcAgASAAYKzhysBwAcAgAYAAQKiRek0QAhAQAXAAIKXQvZSwCbAAAAAA==.',
['Dê']='Dêadlights:BAAANQAECgUIDQAAAA==.',
El='Elbrimar:BAAANQAECgEIAQAAAA==.Elendrisa:BAAANQAECgUIDwAAAA==.Elisoria:BAAANQAECgEIAQAAAA==.Ellayssa:BAAANQAECgEIAQAAAA==.Elliwynd:BAABNQAECn8hAAIKAAgK5xVrIQAYAgAKAAgK5xVrIQAYAgAAAA==.Elway:BAAANQADCgIIAgAAAA==.',
Em='Embermourne:BAAANQADCggICAAAAA==.',
Er='Eraela:BAAANQADCggICAAAAA==.Erinnys:BAABNQAECn8fAAILAAgK3wmLRACbAQALAAgK3wmLRACbAQAAAA==.',
Es='Esoteria:BAABNQAECn8nAAIFAAgKwhoTfwCAAgAFAAgKwhoTfwCAAgAAAA==.',
Eu='Eufemia:BAAANQADCgQJBwAAAA==.',
Ev='Evonnya:BAAANQADCggIDgAAAA==.',
Fe='Felfar:BAAANQADCggICwABNQAECgQIBAAEAAAAAA==.',
Fi='Finalomega:BAAANQAECgYICwAAAA==.Finnshot:BAAANQAECgQIBwAAAA==.Finrod:BAAANQADCgQIBwAAAA==.',
Fl='Flaminfalcon:BAAANQAECgEIBAABNQAECggIFQAUAB0hAA==.',
Fo='Foulmilk:BAAANQADCgEIAQAAAA==.Foxflame:BAABNQAECn8iAAMKAAgK3RXqIQATAgAKAAgK3RXqIQATAgAJAAIKFweHngBeAAAAAA==.',
Fr='Franzen:BAAANQAECgEIAQAAAA==.Frawd:BAAANQADCgcIBwABNQAFFAIIBQAFAPAcAA==.Freyalys:BAAANQADCgYIEwAAAA==.Frôstblade:BAAANQABCgYIBgAAAA==.',
Fu='Fulanita:BAAANQADCgcIEwAAAA==.Fullmoonpo:BAAANQADCgMIAwAAAA==.Furyaid:BAABNQAECn8bAAIGAAgKxSLXHQA/AwAGAAgKxSLXHQA/AwAAAA==.',
Ga='Galadrael:BAAANQAECgQJBAAAAA==.Gaz:BAAANQAECgEIAQAAAA==.',
Ge='Genkithered:BAAANQAECgUICwAAAA==.',
Gl='Gloomy:BAAANQADCgEIAQAAAA==.',
Go='Gourak:BAAANQAECgUIDAAAAA==.',
Gr='Gravemarks:BAAANQADCgYIBAAAAA==.Grimhorn:BAAANQAECgUIDQAAAA==.Grimlie:BAAANQADCgYIDgABNQAECgcIHgAXANcDAA==.',
Gu='Guaritrice:BAAANQAECgEIAQAAAA==.',
Gw='Gwindor:BAAANQADCgQJBwAAAA==.',
['Gö']='Gödwyn:BAAANQAECgEIAQABNQAECgQICAAEAAAAAA==.',
Ha='Hairyrage:BAAANQAECgEIAQAAAA==.Hale:BAAANQADCgEIAgAAAA==.Hatterus:BAAANQAECgcIDAAAAA==.',
He='Healzey:BAAANQAECgEIAQAAAA==.Hetairoi:BAAANQAECgYIEAAAAA==.',
Hi='Hillbroken:BAABNQAECn8rAAIdAAgK6hqgKABOAgAdAAgK6hqgKABOAgAAAA==.',
Ho='Holynez:BAAANQADCgcIDQAAAA==.',
Hu='Huan:BAAANQAECgMIAwAAAA==.Huntrix:BAAANQADCgYICgAAAA==.',
['Hà']='Hànks:BAAANQAECgQIBgAAAA==.',
Ib='Ibíng:BAAANQAECgEIAgAAAA==.',
In='Invariance:BAEANQADCgUIBQABNQAECgUIBgAEAAAAAA==.Inèvitable:BAABNQAECn8qAAIeAAgKeB88IADIAgAeAAgKeB88IADIAgAAAA==.',
Ir='Ironphant:BAABNQAECn8VAAIQAAcKIwtf1wBmAQAQAAcKIwtf1wBmAQAAAA==.',
Is='Ishmethit:BAAANQADCgYIBgAAAA==.Istara:BAAANQADCgYIFAAAAA==.',
Je='Jebib:BAAANQAECgYICAABNQAFFAgIHwAKAGEjAA==.Jeod:BAAANQAECgEIAQAAAA==.Jettonk:BAAANQABCgIIAgABNQAECgcIHgAXANcDAA==.',
Ji='Jirachi:BAAANQADCgEIAQAAAA==.',
Jo='Jolty:BAABNQAECn8lAAMeAAkKiiJBFAAVAwAeAAkKiiJBFAAVAwAZAAQKGhl3gwDrAAAAAA==.',
Ju='Junghoulson:BAAANQAECgUIBgAAAA==.',
['Jð']='Jð:BAAANQAECgcICwAAAA==.',
Ka='Kaiou:BAAANQADCgMICQAAAA==.Kantor:BAABNQAECn8sAAICAAgKiAjPggCKAQACAAgKiAjPggCKAQAAAA==.Karboomkin:BAAANQAECgIIBAABNQAFFAQIDAANAOUVAA==.Kasenko:BAAANQADCggICAABNQAECgUICQAEAAAAAA==.Kasryna:BAAANQAECgUICQAAAA==.',
Ke='Kelmair:BAAANQADCgYIBgAAAA==.Keta:BAAANQAECgEIAgAAAA==.Ketameanie:BAABNQAECn8dAAIMAAcKNRy0HgBYAgAMAAcKNRy0HgBYAgAAAA==.',
Kh='Khadguy:BAABNQAECn8bAAIbAAcKKB0HEABmAgAbAAcKKB0HEABmAgAAAA==.',
Km='Kmazing:BAAANQADCggJFAABNQAECggIJwAFAMIaAA==.',
Kn='Knikku:BAAANQADCggICAAAAA==.',
Ko='Konoha:BAABNQAECn8jAAMDAAgKkyBLEQDkAgADAAgKkyBLEQDkAgACAAEKoiLI7QBRAAAAAA==.Koven:BAAANQADCggIJAAAAA==.',
Ku='Kultag:BAABNQAECn8YAAIQAAgKiAvXtACvAQAQAAgKiAvXtACvAQAAAA==.Kuun:BAAANQAECgYIEgAAAA==.',
Ky='Kyaw:BAAANQAECgUIDwAAAA==.Kynzo:BAAANQAECgQICgAAAA==.',
La='Laelah:BAAANQABCgQIBQAAAA==.Lasmína:BAAANQADCgQIBwAAAA==.Laykeezenith:BAACNQAFFH8OAAMNAAcKxiO/AgBAAgANAAYKXiO/AgBAAgAfAAQKKx2WCwCBAQA1AAQKfyQAAx8ACQr6IhIZAIwCAB8ACQq6HBIZAIwCAA0ABwrfIIt2AB8CAAAA.Lazuli:BAABNQAECn8yAAIWAAkKrBrlMAC0AgAWAAkKrBrlMAC0AgAAAA==.',
Le='Lehann:BAABNQAECn8ZAAINAAcKkAkerwCiAQANAAcKkAkerwCiAQAAAA==.',
Li='Littlebitty:BAAANQAECgEIAQAAAA==.',
Lo='Lockatron:BAAANQADCgcIBwABNQAECggIGwAQAGEHAA==.Lothryn:BAABNQAECn8cAAMQAAgKEwvHvACdAQAQAAgKEwvHvACdAQAcAAQKLA6tzQDcAAAAAA==.',
Lp='Lp:BAAANQAECgUIDAABNQAECgYIDAAEAAAAAA==.',
Lu='Lunariah:BAAANQADCgIJAgAAAA==.',
Ly='Lyllien:BAAANQAECgIIAgAAAA==.',
Ma='Marenus:BAABNQAECn8sAAINAAgKuApGjQDrAQANAAgKuApGjQDrAQAAAA==.Marten:BAAANQABCgIIAgAAAA==.Masume:BAAANQAECgQICgAAAA==.Maély:BAAANQADCgUIBQAAAA==.',
Me='Mechadead:BAAANQAECgUICQABNQAECggIGwAQAGEHAA==.Megaopto:BAABNQAECn8UAAIZAAUKsRY2YwBiAQAZAAUKsRY2YwBiAQAAAA==.Meowmix:BAAANQADCgMICAAAAA==.Methanny:BAAANQADCgQIBAAAAA==.',
Mi='Mizmonk:BAAANQADCggICAAAAA==.',
Mj='Mjölnir:BAABNQAECn8hAAIQAAkKCRQeZQBnAgAQAAkKCRQeZQBnAgAAAA==.',
Mo='Momentum:BAAANQAECgEIBQAAAA==.',
Ms='Msdiiva:BAAANQAECgEIAwAAAA==.',
Mu='Mushuu:BAAANQADCgYIDAAAAA==.',
My='Mythel:BAAANQAECgEIAQABNQAECgkJLAATAL0fAA==.',
['Mô']='Môjô:BAAANQABCgUIBQAAAA==.',
Na='Nahion:BAAANQADCgQJBwAAAA==.Nashira:BAABNQAECn8cAAINAAgKcxEEdwAeAgANAAgKcxEEdwAeAgAAAA==.',
Ne='Nemasus:BAAANQAECgUIEgAAAA==.Nepolian:BAAANQABCgYICAAAAA==.Neraine:BAAANQAECgEIAwAAAA==.',
Ni='Ninjahh:BAABNQAECn8cAAITAAcK2xDsIADCAQATAAcK2xDsIADCAQAAAA==.Nioshei:BAABNQAECn8iAAMaAAgKUBreQABaAgAaAAgKUBreQABaAgAWAAMKUwk+9wCeAAAAAA==.',
No='Nochmuerta:BAAANQADCgUIBQABNQADCgcIBwAEAAAAAA==.Nogrid:BAABNQAECn8sAAIgAAgKaR5yDgCyAgAgAAgKaR5yDgCyAgAAAA==.Noxstantine:BAAANQADCgQIBgAAAA==.',
Nu='Nuthar:BAABNQAECn8dAAIQAAcKYRzkcABJAgAQAAcKYRzkcABJAgAAAA==.',
Ny='Nyrrhi:BAAANQAECggIEQAAAA==.',
Ol='Oldeis:BAAANQAECgEIAQAAAA==.',
Or='Orneryosprey:BAAANQAECgQICwABNQAECgYIEAAEAAAAAA==.',
Ou='Ouroborös:BAABNQAECn8YAAINAAgKTxHRegAVAgANAAgKTxHRegAVAgAAAA==.',
Oy='Oyashiro:BAAANQAECgcICQAAAA==.',
Pa='Pamburu:BAABNQAECn8aAAINAAgKYBBDewAUAgANAAgKYBBDewAUAgAAAA==.Papagrape:BAABNQAECn8iAAMhAAgKOhwdEAClAgAhAAgKOhwdEAClAgAiAAMKOhd5KQDcAAAAAA==.Paradiselost:BAAANQADCgQIBwAAAA==.Parzivàl:BAAANQAECgEIAgAAAA==.Paxa:BAABNQAECn8UAAMCAAcK9hazdwCwAQACAAcK9hazdwCwAQADAAIK4AqraABaAAAAAA==.',
Pe='Pennelo:BAAANQADCgQJBAAAAA==.Persayis:BAAANQAECgEIAQAAAA==.',
Ph='Phoebel:BAAANQADCgIJAgABNQAECgcIHgANAMsQAA==.',
Pi='Pineappledk:BAEANQADCggIEgABNQAECgQIBQAEAAAAAA==.Pineapplepn:BAEANQAECgQIBQAAAA==.Pineapplle:BAEANQAECgMICQABNQAECgQIBQAEAAAAAA==.',
Pl='Plazelly:BAAANQADCgcIDAAAAA==.',
Po='Podnov:BAABNQAECn8sAAIfAAkK0xzZFgChAgAfAAkK0xzZFgChAgAAAA==.Pollyanna:BAAANQABCgYICAAAAA==.',
Py='Pyrista:BAAANQAECggICwAAAA==.',
Qa='Qahili:BAAANQAECgEIAQAAAA==.Qang:BAAANQAECgEIAQAAAA==.',
Ra='Radiante:BAACNQAFFH8IAAIcAAUKmgNNEQBHAQAcAAUKmgNNEQBHAQA1AAQKfyAAAxwACQrwHLIcAP8CABwACQrwHLIcAP8CABAAAQodA+3FASEAAAAA.Rageadin:BAAANQABCgcIBQAAAA==.Raion:BAABNQAECn8jAAIgAAgKUB/WDQC7AgAgAAgKUB/WDQC7AgAAAA==.Raithis:BAACNQAFFH8MAAINAAUKqhgEDACLAQANAAUKqhgEDACLAQA1AAQKfycAAg0ACQqfJIsPAGYDAA0ACQqfJIsPAGYDAAAA.Ralzin:BAAANQADCgEIAQAAAA==.Ramhadin:BAEANQADCgcIFgABNQAECgcIHwADAGkdAA==.Randel:BAAANQAECggIBwAAAA==.Raucousrhea:BAAANQAECgEIAQAAAA==.Rav:BAAANQAECgYIDAAAAA==.',
Re='Redvelvet:BAABNQAECn8cAAIjAAgKUBE/HAC8AQAjAAgKUBE/HAC8AQAAAA==.Resisting:BAAANQAECgYIDAAAAA==.Reznal:BAABNQAECn8cAAMWAAkKmx26NgCZAgAWAAgKGx66NgCZAgAaAAUKuB4ldwCiAQABNQAFFAEIAQAEAAAAAA==.',
Ro='Romam:BAAANQAECgEIAQAAAA==.',
Ry='Rydran:BAAANQADCgIIAgAAAA==.Rykria:BAAANQADCgYIFAAAAA==.',
Sa='Sableanne:BAABNQAECn84AAIaAAkK/gV+jQBjAQAaAAkK/gV+jQBjAQAAAA==.Saedirine:BAAANQADCgYIDAAAAA==.Saggi:BAAANQAECgEIBAAAAA==.',
Se='Secksiecutie:BAABNQAECn8jAAIdAAgKLBMTPgDNAQAdAAgKLBMTPgDNAQAAAA==.Secondwall:BAAANQADCgYIBgAAAA==.Selma:BAAANQABCgMIAwAAAA==.Serinar:BAABNQAECn8ZAAIQAAgK5hPvpQDPAQAQAAgK5hPvpQDPAQAAAA==.',
Sh='Shadowbolt:BAAANQABCgQIBgAAAA==.Shoorah:BAAANQADCgEIAQAAAA==.',
Si='Siako:BAABNQAECn8UAAMPAAgKXQeGBABcAQAFAAgKEQTFEwFnAQAPAAcKFwiGBABcAQAAAA==.Silversaiyan:BAABNQAECn8lAAIRAAcKKh8TBwCKAgARAAcKKh8TBwCKAgAAAA==.Sirlink:BAAANQAECgEIAQAAAA==.',
Sl='Slade:BAABNQAECn8sAAMTAAkKvR8vBABUAwATAAkKvR8vBABUAwAUAAQKyRbXYQAlAQAAAA==.Sliyce:BAAANQAECgEIAQAAAA==.',
Sm='Smorc:BAAANQAECgQIBwAAAA==.',
Sn='Sneakyclubs:BAAANQADCgUICAAAAA==.Snowfawn:BAAANQADCgcJDwABNQAECggIFQAYAFcIAA==.',
So='Sofedan:BAABNQAECn8rAAIfAAgK4QUaPwBUAQAfAAgK4QUaPwBUAQAAAA==.Sorgath:BAAANQAECgEIAwAAAA==.Soriel:BAABNQAECn8iAAIkAAgK0RQRDwD9AQAkAAgK0RQRDwD9AQAAAA==.Sorokwa:BAABNQAECn8aAAIeAAkKcwQdhgAEAQAeAAkKcwQdhgAEAQAAAA==.',
Sq='Squeeze:BAAANQAECgUJDQAAAA==.',
St='Stillwater:BAABNQAECn8jAAMbAAgKqQsKFwD0AQAbAAgKqQsKFwD0AQAWAAMKygPwBAF7AAAAAA==.',
Su='Suriden:BAAANQADCggICQAAAA==.',
Sw='Swagidan:BAABNQAECn8zAAILAAkKOBlMHwCcAgALAAkKOBlMHwCcAgAAAA==.Sweaterpally:BAAANQADCgUICQAAAA==.Swiftera:BAAANQAECgIIAgAAAA==.Swiftlier:BAAANQAECgIIBQABNQAECggIJAAZAAoOAA==.',
Sy='Sylphrène:BAABNQAECn8UAAMMAAcKmQH4TwDZAAAMAAcKmQH4TwDZAAALAAMKUQHJiwBAAAAAAA==.',
Ta='Taghman:BAAANQAECgIIAgABNQAECgkJLAATAL0fAA==.Taleth:BAAANQAECgEIAgAAAA==.Tandrana:BAAANQAECgEIAQAAAA==.Targanisha:BAAANQADCggICAABNQAECgkJKgAWAEgcAA==.Targdh:BAABNQAECn8nAAIMAAkKjhy0EQDcAgAMAAkKjhy0EQDcAgABNQAECgkJKgAWAEgcAA==.Targforeva:BAAANQAECgQIBwABNQAECgkJKgAWAEgcAA==.',
Te='Terminus:BAAANQADCgMIAwAAAA==.',
Ti='Ticebane:BAABNQAECn8XAAIeAAgKkQsNZAB8AQAeAAgKkQsNZAB8AQAAAA==.Tichus:BAAANQADCgYIDgAAAA==.Tiduspullo:BAAANQADCgIIAgABNQAECgQICQAEAAAAAA==.Titanbeard:BAAANQADCggIGAAAAA==.Titor:BAABNQAECn8cAAMhAAcKWgkpKwBPAQAhAAcKWgkpKwBPAQAiAAIKKAJENwBQAAAAAA==.Tituspullo:BAAANQAECgQICQAAAA==.',
To='Tock:BAAANQAECgEIAwAAAA==.Tolduan:BAAANQAECgYIEAAAAA==.Totemik:BAAANQADCgUIBQAAAA==.Toughturkey:BAAANQADCgEIAQABNQAECgYIEAAEAAAAAA==.',
Tr='Tricarnetry:BAABNQAECn8bAAIQAAgKYQd4ygCAAQAQAAgKYQd4ygCAAQAAAA==.Tricarnity:BAAANQAECgQICQABNQAECggIGwAQAGEHAA==.Trucknôrris:BAAANQAECgEIAQAAAA==.Trîela:BAAANQAECgUIDAAAAA==.',
Ul='Ulfer:BAAANQADCgYIBgABNQAECggIGwAeAGAfAA==.',
Ve='Veganwolf:BAAANQADCgMIAwAAAA==.Verakis:BAABNQAECn8iAAIHAAgKuw4hGACpAQAHAAgKuw4hGACpAQAAAA==.Verndarí:BAABNQAECn8kAAIZAAgKCg4BUgCqAQAZAAgKCg4BUgCqAQAAAA==.Verudora:BAAANQAECgEIAwAAAA==.',
Vi='Vishas:BAAANQAECgQIBgAAAA==.',
Vo='Vortheus:BAAANQAECgEIAQAAAA==.Votollis:BAAANQAECgEIAwAAAA==.',
Vr='Vrack:BAAANQADCgQIBAAAAA==.',
Wa='Warhowl:BAAANQABCggIDgAAAA==.Warlanen:BAAANQADCgQJBwAAAA==.',
Wi='Willbur:BAABNQAECn8jAAIFAAgKBRDpvgAEAgAFAAgKBRDpvgAEAgAAAA==.',
Wu='Wurthwhile:BAAANQADCgcIEQAAAA==.',
Wy='Wyndywalker:BAAANQAECgUICwAAAA==.',
Xi='Xinnuo:BAAANQADCggIEAAAAA==.',
Za='Zamønk:BAAANQAECgUICwAAAA==.Zarinnara:BAAANQAECgEIAQAAAA==.',
Ze='Zeigfeld:BAAANQAECgEIAQAAAA==.',
Zi='Ziarra:BAAANQADCgUIBQABNQAECgMIBAAEAAAAAA==.',
Zo='Zok:BAAANQAECgUICAAAAA==.',
Zy='Zyzz:BAAANQADCgQJBAAAAA==.',
['Zä']='Zädä:BAAANQADCgQIBQAAAA==.',
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
