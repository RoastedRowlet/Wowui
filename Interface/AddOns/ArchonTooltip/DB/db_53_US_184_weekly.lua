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

local lookup = {'Monk-Windwalker','Paladin-Retribution','Priest-Holy','Priest-Shadow','Unknown-Unknown','Paladin-Holy','Paladin-Protection','Mage-Arcane','Warrior-Arms','Warrior-Protection','Druid-Feral','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Mage-Frost','Mage-Fire','Warrior-Fury','Warlock-Affliction','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','DeathKnight-Blood','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Druid-Guardian','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver','Monk-Brewmaster',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Acefu:BAABNQAECn8eAAIBAAcKLSB7GACDAgABAAcKLSB7GACDAgAAAA==.Aceo:BAAANQADCgYIBgABNQAECggIIgACAMgIAA==.Acornella:BAABNQAECn8ZAAMDAAkKoRJCUAAzAgADAAkKoRJCUAAzAgAEAAIKABACawBXAAABNQAFFAEIAQAFAAAAAA==.Acornkei:BAAANQAFFAEIAQAAAA==.',
Ad='Adonsia:BAAANQADCgQIBAAAAA==.Adreva:BAABNQAECn8XAAQGAAcKaiB0BQB/AgAGAAcKaiB0BQB/AgAHAAQKKAIFWwBwAAACAAIK0RDGcwFpAAAAAA==.',
Ae='Aelana:BAAANQADCgQIBAAAAA==.Aendor:BAAANQADCgcIBwABNQAFFAcIDwAIAAYQAA==.Aerea:BAAANQAECgEIAwABNQAECggIGwAJANcPAA==.Aevastraa:BAAANQADCgEIAQABNQAECggIKQAKADwQAA==.',
Ai='Ailanthus:BAABNQAECn8bAAQLAAgKagtnDwCzAAALAAUKMQ5nDwCzAAAMAAUK5QRuiQCuAAANAAIKKAU2bwBJAAAAAA==.',
Al='Albinophil:BAAANQADCgIIAgABNQAECgcIEQAFAAAAAA==.Aleyah:BAAANQAECggIBQAAAA==.Alloisaber:BAAANQABCgEIAQAAAA==.Alunne:BAAANQADCgQIBAAAAA==.',
Am='Amna:BAAANQAECgUIDQAAAA==.',
An='Andrelsia:BAAANQAECgEIAQAAAA==.Andrilla:BAAANQADCgYJDAAAAA==.Ankeseth:BAAANQADCggJDQAAAA==.',
Ar='Aracelis:BAAANQADCggICAAAAA==.Araxiel:BAAANQAECgEIBAAAAA==.Archangël:BAAANQAECgEIAQAAAA==.Arkenos:BAAANQAECgEIAQAAAA==.Arén:BAABNQAECn8qAAMOAAkKqR/4BQD1AQAOAAgKqR/4BQD1AQAPAAYKshmDOACAAQAAAA==.',
As='Ashenshugär:BAAANQAECgMIAwAAAA==.Aszian:BAAANQABCgcICgAAAA==.Aszun:BAABNQAECn8kAAIQAAcKyxCYWgD4AAAQAAcKyxCYWgD4AAAAAA==.',
At='Atractiva:BAABNQAECn8nAAMRAAoKMwgoEwB1AQARAAoK3AcoEwB1AQASAAgKzQRiBABoAQAAAA==.',
Au='Augment:BAAANQADCggICAABNQAECggIIgACAMgIAA==.Aura:BAAANQABCgUIBwAAAA==.',
Az='Azmar:BAAANQADCgIIAgAAAA==.Azuri:BAAANQAECgEIAQABNQAECgIIBAAFAAAAAA==.',
Ba='Balain:BAABNQAECn8bAAMJAAgK1w/zpADAAQAJAAcKbRHzpADAAQAKAAUKfAXyMwCXAAAAAA==.Barbiejoe:BAAANQADCgYIBgAAAA==.',
Be='Bear:BAAANQAECgEIAgAAAA==.Beardchi:BAAANQADCgEIAQAAAA==.Bearzerk:BAABNQAECn8eAAITAAkK9g1TBQBTAQATAAkK9g1TBQBTAQAAAA==.Benathar:BAAANQAECgYIEAAAAA==.Bethela:BAAANQABCgYIBgABNQAECgcIJAAQAMsQAA==.',
Bi='Birgir:BAAANQAECgQIBAABNQAECgcIIAAUAI0aAA==.',
Bl='Blackmagék:BAAANQAECgEIAQAAAA==.Blaston:BAABNQAECn8WAAMVAAYKZA+VEgD+AAAVAAYKUQmVEgD+AAADAAQKTQ93UADYAAAAAA==.Blightbeard:BAAANQADCggIDgAAAA==.Bloodthorn:BAABNQAECn8ZAAQWAAgKNgSZMAA6AQAWAAcKtASZMAA6AQAXAAMKFQQ/MwB8AAAYAAIKPAEGHQArAAAAAA==.',
Bo='Boogiepop:BAAANQAECgEIAQAAAA==.Boomnescient:BAAANQADCgYICwAAAA==.Bottomdps:BAABNQAECn8xAAIZAAoKnBv1DgCcAQAZAAoKnBv1DgCcAQAAAA==.',
Br='Bramis:BAAANQADCggIDQAAAA==.Branor:BAAANQAECgEIAgAAAA==.Bransonian:BAAANQADCgQJBgAAAA==.Brantu:BAABNQAECn8kAAMaAAcKjARTTgCUAAAbAAcKjAQ54QAHAQAaAAUKrQFTTgCUAAAAAA==.Braultus:BAABNQAECn8fAAIcAAgKhxnRNgAvAgAcAAgKhxnRNgAvAgAAAA==.Bravehearth:BAAANQADCgEIAQAAAA==.Breuddwydwr:BAAANQADCgEIAQAAAA==.Brewtality:BAAANQAECgUICAAAAA==.Breyastrasza:BAAANQADCgYIDwAAAA==.',
Ca='Caanu:BAACNQAFFH8PAAIIAAcKBhDMAgCcAQAIAAcKBhDMAgCcAQA1AAQKfy0AAggACgr7HdQEAJACAAgACgr7HdQEAJACAAAA.Calydonia:BAAANQAECgIIBAAAAA==.',
Ce='Celdiseth:BAAANQADCggICwAAAA==.Cerdwin:BAAANQAECgYIDgABNQAECgkJKwANAJoUAA==.',
Ch='Charferad:BAAANQAECgEIAQAAAA==.Chatter:BAAANQADCgcICAAAAA==.Cheeseydeath:BAEANQAECgMIAwAAAA==.Chibeard:BAAANQAECgYIEAAAAA==.Chihîro:BAAANQAECgQIBAAAAA==.',
Cl='Clevercrane:BAAANQAECgMIAwABNQAECgkJFwAXAO0dAA==.',
Co='Coolbro:BAAANQADCgcICAAAAA==.Corialis:BAABNQAECn8jAAMZAAgKWAyBrAA6AQAZAAYKKguBrAA6AQAdAAcK8w/sKwAyAQAAAA==.',
Cr='Crom:BAABNQAECn8rAAIeAAgKfhGXFAAfAgAeAAgKfhGXFAAfAgAAAA==.Crying:BAAANQAECgUIDgAAAA==.',
Cy='Cyn:BAAANQADCgQIBgAAAA==.',
Da='Dandarred:BAABNQAECn8kAAMGAAgK8QgTlQBhAQAGAAgK8QgTlQBhAQACAAcKuQeFawDuAAAAAA==.Dantey:BAAANQADCggIEQABNQAECggIIgACAMgIAA==.Darkwyn:BAAANQADCgUIBQAAAA==.Dawne:BAABNQAECn8YAAIGAAoKLRr3MQCdAgAGAAoKLRr3MQCdAgAAAA==.Dazanna:BAABNQAECn8qAAMGAAgKqBb2FgCeAQAGAAgKqBb2FgCeAQACAAEKAACNpQE0AAAAAA==.Dazjaxx:BAAANQABCgYICQAAAA==.Dazre:BAAANQAECgIIAgAAAA==.',
De='Deeminor:BAAANQADCgIJAgAAAA==.Demeisen:BAABNQAECn8rAAIOAAgKfhNvCwCZAQAOAAgKfhNvCwCZAQAAAA==.Demonizerr:BAAANQAECgEIAQABNQAECggIIgACAMgIAA==.',
Di='Diksensei:BAAANQAECgIIBQAAAA==.Diod:BAAANQAECgYIDgAAAA==.',
Dr='Dracomage:BAAANQADCgMIBgAAAA==.Dracotincan:BAAANQADCgIIAgAAAA==.Draegis:BAAANQAECgEIAQAAAA==.Dragyns:BAABNQAECn8hAAIXAAkKJiDoFQDNAgAXAAkKJiDoFQDNAgAAAA==.Dragynslance:BAAANQAECgEIAQABNQAECgkJIQAXACYgAA==.Drayper:BAAANQAECgcIEQAAAA==.',
Du='Dunbarke:BAABNQAECn8gAAQUAAcKjRoZAgB5AQAUAAcKjRoZAgB5AQAbAAQKiRdy1AAhAQAaAAIKXQtETACaAAAAAA==.',
['Dê']='Dêadlights:BAAANQAECgUIEgAAAA==.',
El='Elbrimar:BAAANQAECgEIAQAAAA==.Elendrisa:BAAANQAECgUIDwAAAA==.Elisoria:BAAANQAECgMIAwAAAA==.Ellayssa:BAAANQAECgEIAQAAAA==.Elliwynd:BAABNQAECn8oAAINAAgK5xWmCQCdAQANAAgK5xWmCQCdAQAAAA==.Elway:BAAANQADCgIIAgAAAA==.',
Em='Embermourne:BAAANQADCggICAAAAA==.',
Er='Eraela:BAAANQADCggICAAAAA==.Erinnys:BAABNQAECn8mAAIOAAgKMQrcGAArAQAOAAgKMQrcGAArAQAAAA==.',
Es='Esoteria:BAABNQAECn8uAAIIAAgKxRsXEgDWAQAIAAgKxRsXEgDWAQAAAA==.',
Eu='Eufemia:BAAANQADCgQJBwAAAA==.',
Ev='Evonnya:BAAANQADCggIDgAAAA==.',
Fe='Felfar:BAAANQADCggICwAAAA==.',
Fi='Finalomega:BAAANQAECgYIEAAAAA==.Finnshot:BAAANQAECgUICQAAAA==.Finrod:BAAANQAECgUIBQAAAA==.',
Fl='Flaminfalcon:BAAANQAECgEIBAABNQAECgkJFwAXAO0dAA==.',
Fo='Foulmilk:BAAANQADCgEIAQAAAA==.Foxflame:BAABNQAECn8rAAMNAAkKmhRMIgAUAgANAAkKmhRMIgAUAgAMAAQKTgoVMQCaAAAAAA==.',
Fr='Franzen:BAAANQAECgEIAQAAAA==.Frawd:BAAANQADCgcIBwABNQAFFAMIBwAIAEcdAA==.Freyalys:BAAANQADCgYIEwAAAA==.Frôstblade:BAAANQABCgYIBgAAAA==.',
Fu='Fulanita:BAAANQADCgcIEwAAAA==.Fullmoonpo:BAAANQADCgMIAwAAAA==.Furyaid:BAABNQAECn8iAAIJAAgK7iLNBwBCAgAJAAgK7iLNBwBCAgAAAA==.',
Ga='Galadrael:BAAANQAECgQJBAAAAA==.Gaz:BAAANQAECgEIAQAAAA==.',
Ge='Genkithered:BAAANQAECgYIEAAAAA==.',
Gl='Gloomy:BAAANQADCgEIAQAAAA==.',
Go='Gourak:BAAANQAECgYIDgAAAA==.',
Gr='Grapejuice:BAAANQAECgUIBQAAAA==.Gravemarks:BAAANQADCgYIBAAAAA==.Grimhorn:BAAANQAECgUIEAAAAA==.Grimlie:BAAANQADCgYIDgABNQAECgcIJAAaAIwEAA==.',
Gu='Guaritrice:BAAANQAECgEIAQAAAA==.',
Gw='Gwindor:BAAANQADCgQJBwAAAA==.',
['Gö']='Gödwyn:BAAANQAECgEIAQABNQAECgQICgAFAAAAAA==.',
Ha='Hairyrage:BAAANQAECgEIAQAAAA==.Hale:BAAANQADCgEIAgAAAA==.Hatterus:BAAANQAECgcIEwAAAA==.',
He='Healzey:BAAANQAECgEIAQAAAA==.Hetairoi:BAAANQAECgcIEQAAAA==.',
Hi='Hillbroken:BAABNQAECn80AAIfAAkKGBl7CgC2AQAfAAkKGBl7CgC2AQAAAA==.',
Ho='Holynez:BAAANQADCgcIDQAAAA==.',
Hu='Huan:BAAANQAECgMIBAAAAA==.Huntrix:BAAANQADCgYICgAAAA==.',
Hy='Hyrlis:BAAANQAECgEIAQAAAA==.',
['Hà']='Hànks:BAAANQAECgUIBwAAAA==.',
Ib='Ibíng:BAAANQAECgEIAgAAAA==.',
In='Invariance:BAEANQADCgUIBQABNQAECgUIBgAFAAAAAA==.Inèvitable:BAABNQAECn8zAAIgAAkKYx2GBQDfAQAgAAkKYx2GBQDfAQAAAA==.',
Ir='Ironphant:BAABNQAECn8aAAICAAkKZQmw2gBmAQACAAkKZQmw2gBmAQAAAA==.',
Is='Ishmethit:BAAANQADCgYIBgAAAA==.Istara:BAAANQADCgYIFAAAAA==.',
Je='Jebib:BAAANQAECgYICAABNQAFFAgIHwANAGEjAA==.Jeod:BAAANQAECgEIAQAAAA==.Jettonk:BAAANQABCgIIAgABNQAECgcIJAAaAIwEAA==.',
Ji='Jirachi:BAAANQADCgEIAQAAAA==.',
Jo='Jolty:BAABNQAECn8lAAMgAAkKiiJ4FAAVAwAgAAkKiiJ4FAAVAwAcAAQKGhmshADqAAAAAA==.',
Ju='Junghoulson:BAAANQAECgUIBgAAAA==.',
['Jð']='Jð:BAAANQAECggICwAAAA==.',
Ka='Kaiou:BAAANQADCgUICwAAAA==.Kantor:BAABNQAECn81AAIDAAkK5AsdFQDIAQADAAkK5AsdFQDIAQAAAA==.Karboomkin:BAAANQAECgIIBAABNQAECggICwAFAAAAAA==.Kasenko:BAAANQADCggICAABNQAECgYIDgAFAAAAAA==.Kasryna:BAAANQAECgYIDgAAAA==.',
Ke='Kelmair:BAAANQADCgYIBgAAAA==.Keta:BAAANQAECgIIAgAAAA==.Ketameanie:BAABNQAECn8nAAIPAAoKmBjtAQBhAgAPAAoKmBjtAQBhAgAAAA==.',
Kh='Khadguy:BAABNQAECn8eAAIeAAkKjRlGEABkAgAeAAkKjRlGEABkAgAAAA==.',
Km='Kmazing:BAAANQADCggJFAABNQAECggILgAIAMUbAA==.',
Kn='Knikku:BAAANQADCggICAAAAA==.',
Ko='Konoha:BAABNQAECn8qAAMEAAgK6SB1AgAYAgAEAAgK6SB1AgAYAgADAAEKoiIt8QBRAAAAAA==.Koven:BAAANQADCggIJAAAAA==.',
Ku='Kultag:BAABNQAECn8fAAICAAgKLA1UOwBRAQACAAgKLA1UOwBRAQAAAA==.Kuun:BAABNQAECn8WAAIZAAgKTQkGPADWAAAZAAgKTQkGPADWAAAAAA==.',
Ky='Kyaw:BAAANQAECgUIDwAAAA==.Kynzo:BAAANQAECgQICgAAAA==.',
La='Laelah:BAAANQABCgQIBQAAAA==.Lasmína:BAAANQADCgQIBwAAAA==.Laykeezenith:BAACNQAFFH8OAAMQAAcKxiPrAgA/AgAQAAYKXiPrAgA/AgAhAAQKKx3jCwCAAQA1AAQKfyUAAyEACgpkImIZAIwCACEACgrrHGIZAIwCABAABwrfIER4AB8CAAAA.Lazuli:BAABNQAECn87AAMZAAoKnxmUMQC0AgAZAAoKnxmUMQC0AgAdAAgKiQk+GgCKAQAAAA==.',
Le='Lehann:BAABNQAECn8ZAAIQAAcKkAm1sQChAQAQAAcKkAm1sQChAQAAAA==.',
Li='Littlebitty:BAAANQAECgcICAAAAA==.',
Lo='Lockatron:BAAANQADCgcICQABNQAECggIIgACAMgIAA==.Lothryn:BAABNQAECn8jAAMCAAgKqguRQABFAQACAAgKqguRQABFAQAGAAQKLA7QzwDcAAAAAA==.',
Lp='Lp:BAABNQAECn8UAAIPAAkKUBu/AgAdAgAPAAkKUBu/AgAdAgAAAA==.',
Lu='Lunariah:BAAANQADCgIJAgAAAA==.',
Ly='Lyllien:BAAANQAECgIIAgAAAA==.',
Ma='Marenus:BAABNQAECn81AAIQAAkKuArlHwCYAQAQAAkKuArlHwCYAQAAAA==.Marten:BAAANQABCgIIAgAAAA==.Masume:BAAANQAECgUIDAAAAA==.Maély:BAAANQADCgUIBQAAAA==.',
Me='Mechadead:BAAANQAECgUIDgABNQAECggIIgACAMgIAA==.Megaopto:BAABNQAECn8UAAIcAAUKsRYbZABiAQAcAAUKsRYbZABiAQAAAA==.Meowmix:BAAANQADCgMICAAAAA==.Methanny:BAAANQADCgQIBAAAAA==.',
Mi='Mizmonk:BAAANQADCggICAAAAA==.',
Mj='Mjölnir:BAABNQAECn8nAAICAAoKKRUXZwBmAgACAAoKKRUXZwBmAgAAAA==.',
Mo='Momentum:BAAANQAECgIIBQAAAA==.',
Ms='Msdiiva:BAAANQAECgEIAwAAAA==.',
Mu='Mushuu:BAAANQADCgYIDAAAAA==.',
My='Mythel:BAAANQAECgIIAQABNQAECgoKNwAWALIeAA==.',
['Mô']='Môjô:BAAANQABCgUIBQAAAA==.',
Na='Nahion:BAAANQADCgQJBwAAAA==.Nashira:BAABNQAECn8hAAIQAAkKTBD4eAAdAgAQAAkKTBD4eAAdAgAAAA==.',
Ne='Nemasus:BAABNQAECn8YAAQNAAYKPxjiQwANAQANAAQKCxjiQwANAQAMAAYKCxQGJQDSAAAiAAUKMAOaRQCdAAAAAA==.Nepolian:BAAANQABCgYICAAAAA==.Neraine:BAAANQAECgYICAAAAA==.',
Ni='Ninjahh:BAABNQAECn8iAAIWAAcK2hTcFgAlAQAWAAcK2hTcFgAlAQAAAA==.Nioshei:BAABNQAECn8pAAMdAAgKrhqCFACwAQAdAAgKrhqCFACwAQAZAAMKUwlq+gCeAAAAAA==.',
No='Nochmuerta:BAAANQADCgUIBQABNQADCgcIBwAFAAAAAA==.Nogrid:BAABNQAECn81AAIHAAkKIx0fAgA8AgAHAAkKIx0fAgA8AgAAAA==.Noxstantine:BAAANQADCgQIBgAAAA==.',
Nu='Nuthar:BAABNQAECn8kAAICAAgKLR3tDgAFAgACAAgKLR3tDgAFAgAAAA==.',
Ny='Nyrrhi:BAAANQAECggIEQAAAA==.',
Ol='Oldeis:BAAANQAECgEIAQAAAA==.',
Or='Orneryosprey:BAAANQAECgQICwABNQAECgcIEQAFAAAAAA==.',
Ou='Ouroborös:BAABNQAECn8fAAIQAAgKjRG6IQCRAQAQAAgKjRG6IQCRAQAAAA==.',
Oy='Oyashiro:BAAANQAECgcICQAAAA==.',
Pa='Pamburu:BAABNQAECn8jAAIQAAkKwxNTFADQAQAQAAkKwxNTFADQAQAAAA==.Papagrape:BAABNQAECn8kAAMjAAgKDR4+EAClAgAjAAgKDR4+EAClAgAkAAMKOhfOKQDcAAAAAA==.Paradiselost:BAAANQADCgQIBwAAAA==.Parzivàl:BAAANQAECgIIAgAAAA==.Paxa:BAABNQAECn8bAAMDAAgKmBfIFgC7AQADAAgKmBfIFgC7AQAEAAIK4ArtaQBaAAAAAA==.',
Pe='Peekabu:BAAANQADCgcICAABNQAECggIIgACAMgIAA==.Pennelo:BAAANQADCgQIBAAAAA==.Persayis:BAAANQAECgEIAQAAAA==.',
Ph='Phoebel:BAAANQADCgIJAgABNQAECgcIJAAQAMsQAA==.',
Pi='Pineappledk:BAEANQADCggIEgABNQAECgUIBwAFAAAAAA==.Pineapplepn:BAEANQAECgUIBwAAAA==.Pineapplle:BAEANQAECgQICQABNQAECgUIBwAFAAAAAA==.',
Pl='Plazelly:BAAANQADCgcIDAAAAA==.',
Po='Podnov:BAABNQAECn8uAAIhAAoK2Bs9FwCgAgAhAAoK2Bs9FwCgAgAAAA==.Pollyanna:BAAANQABCgYICAAAAA==.',
Py='Pyrista:BAAANQAECggICwAAAA==.',
Qa='Qahili:BAAANQAECgEIAQAAAA==.Qang:BAAANQAECgEIAQAAAA==.',
Ra='Radiante:BAACNQAFFH8IAAIGAAUKmgO1EQBHAQAGAAUKmgO1EQBHAQA1AAQKfyAAAwYACQrwHD0dAP4CAAYACQrwHD0dAP4CAAIAAQodA27MASEAAAAA.Rageadin:BAAANQABCgcIBQAAAA==.Raion:BAABNQAECn8qAAIHAAgKfh89AwD2AQAHAAgKfh89AwD2AQAAAA==.Raithis:BAACNQAFFH8MAAIQAAUKqhhnDACLAQAQAAUKqhhnDACLAQA1AAQKfy4AAhAACgqSI8IGAF0CABAACgqSI8IGAF0CAAAA.Ralzin:BAAANQADCgEIAQAAAA==.Ramhadin:BAEANQADCgcIFgABNQAECggIJgAEAEYcAA==.Randel:BAAANQAECggIBwAAAA==.Raucousrhea:BAAANQAECgEIAQAAAA==.Rav:BAAANQAECgYIDAAAAA==.',
Re='Redvelvet:BAABNQAECn8hAAIlAAkKFRDpDAAHAQAlAAkKFRDpDAAHAQAAAA==.Resisting:BAAANQAECgYIDAABNQAECgkJFAAPAFAbAA==.Reznal:BAABNQAECn8cAAMZAAkKmx2ENwCYAgAZAAgKGx6ENwCYAgAdAAUKuB6AeACiAQABNQAFFAEIAQAFAAAAAA==.',
Ro='Romam:BAAANQAECgEIAQAAAA==.',
Ry='Rydran:BAAANQADCgIIAgAAAA==.Rykria:BAAANQADCgYIFAAAAA==.',
Sa='Sableanne:BAABNQAECn86AAIdAAoKtgbojgBjAQAdAAoKtgbojgBjAQAAAA==.Saedirine:BAAANQADCgYIDAAAAA==.Saggi:BAAANQAECgEIBAAAAA==.',
Se='Secksiecutie:BAABNQAECn8qAAIfAAgKLBNlEgBzAQAfAAgKLBNlEgBzAQAAAA==.Secondwall:BAAANQADCgYIBgAAAA==.Selma:BAAANQABCgMIAwAAAA==.Serinar:BAABNQAECn8ZAAICAAgK5hNNqADPAQACAAgK5hNNqADPAQAAAA==.',
Sh='Shadowbolt:BAAANQABCgQIBgAAAA==.Shoorah:BAAANQADCgEIAQAAAA==.',
Si='Siako:BAABNQAECn8UAAMSAAgKXQeOBABcAQAIAAgKEQRxFgFnAQASAAcKFwiOBABcAQAAAA==.Silversaiyan:BAABNQAECn8pAAITAAcKUR8uBwCJAgATAAcKUR8uBwCJAgAAAA==.Sirlink:BAAANQAECgEIAQAAAA==.',
Sl='Slade:BAABNQAECn83AAMWAAoKsh42BABTAwAWAAoKsh42BABTAwAXAAYKhRdUDgBSAQAAAA==.Sliyce:BAAANQAECgEIAQAAAA==.',
Sm='Smorc:BAAANQAECgQIBwAAAA==.',
Sn='Sneakyclubs:BAAANQADCgUICAAAAA==.Snowfawn:BAAANQAECgMIAgABNQAECggIFgAbAFcIAA==.',
So='Sofedan:BAABNQAECn80AAIhAAkK8wUHDQAmAQAhAAkK8wUHDQAmAQAAAA==.Sorgath:BAAANQAECgIIAwAAAA==.Soriel:BAABNQAECn8pAAImAAgK0RRlBABMAQAmAAgK0RRlBABMAQAAAA==.Sorokwa:BAABNQAECn8kAAIgAAoKawQ/hwAEAQAgAAoKawQ/hwAEAQAAAA==.',
Sq='Squeeze:BAAANQAECgUJDQAAAA==.',
St='Stillwater:BAABNQAECn8qAAMeAAgKLwzSCABnAQAeAAgKLwzSCABnAQAZAAMKygONCAF7AAAAAA==.',
Su='Suriden:BAAANQADCggICQAAAA==.',
Sw='Swagidan:BAABNQAECn83AAIOAAoKWhjXHwCbAgAOAAoKWhjXHwCbAgAAAA==.Sweaterpally:BAAANQADCgUICQAAAA==.Swiftera:BAAANQAECgIIAgAAAA==.Swiftlier:BAAANQAECgcICwABNQAECgoKJwAcALUNAA==.',
Sy='Sylphrène:BAABNQAECn8cAAMPAAgKYQLBHADIAAAPAAgKYQLBHADIAAAOAAMKUQHcjQBAAAAAAA==.',
Ta='Taghman:BAAANQAECgIIBAABNQAECgoKNwAWALIeAA==.Taleth:BAAANQAECgIIBAAAAA==.Tandrana:BAAANQAECgEIAQAAAA==.Targanisha:BAAANQADCggICAABNQAECgoKMQAZAJwbAA==.Targdh:BAABNQAECn80AAIPAAoKDR2GBQC7AQAPAAoKDR2GBQC7AQABNQAECgoKMQAZAJwbAA==.Targforeva:BAAANQAECgQIBwABNQAECgoKMQAZAJwbAA==.',
Te='Terminus:BAAANQADCgMIAwAAAA==.',
Ti='Ticebane:BAABNQAECn8XAAIgAAgKkQsWZQB8AQAgAAgKkQsWZQB8AQAAAA==.Tichus:BAAANQADCgYIDgAAAA==.Tiduspullo:BAAANQAECgIIAgABNQAECgUICQAFAAAAAA==.Titanbeard:BAAANQADCggIGAAAAA==.Titor:BAABNQAECn8jAAMjAAcKmgo5CwAPAQAjAAcKmgo5CwAPAQAkAAIKKALINwBQAAAAAA==.Tituspullo:BAAANQAECgUICQAAAA==.',
To='Tock:BAAANQAECgEIAwAAAA==.Tolduan:BAABNQAECn8XAAMZAAcKYwueMQD5AAAZAAcKYwueMQD5AAAeAAMKAgNuLQCRAAAAAA==.Totemik:BAAANQADCgUIBQAAAA==.Toughturkey:BAAANQADCgEIAQABNQAECgcIEQAFAAAAAA==.',
Tr='Tricarnetry:BAABNQAECn8iAAICAAgKyAjDbwDmAAACAAgKyAjDbwDmAAAAAA==.Tricarnity:BAAANQAECgUICwABNQAECggIIgACAMgIAA==.Trucknôrris:BAAANQAECgEIAQAAAA==.Trîela:BAAANQAECgcIDwAAAA==.',
Ul='Ulfer:BAAANQADCgYIBgABNQAECggIGwAgAGAfAA==.',
Um='Um:BAAANQAECgQIBAAAAA==.',
Ve='Veganwolf:BAAANQADCgMIAwAAAA==.Verakis:BAABNQAECn8pAAIKAAgKPBCcBwA+AQAKAAgKPBCcBwA+AQAAAA==.Verndarí:BAABNQAECn8nAAIcAAoKtQ24UgCqAQAcAAoKtQ24UgCqAQAAAA==.Verudora:BAAANQAECgEIAwAAAA==.',
Vi='Vishas:BAAANQAECgQIBgAAAA==.',
Vo='Vortheus:BAAANQAECgcICAAAAA==.Votollis:BAAANQAECgEIAwAAAA==.',
Vr='Vrack:BAAANQADCgQIBAAAAA==.',
Wa='Warhowl:BAAANQABCggIDgAAAA==.Warlanen:BAAANQADCgQJBwAAAA==.',
Wi='Willbur:BAABNQAECn8sAAIIAAkK7w43HACfAQAIAAkK7w43HACfAQAAAA==.',
Wu='Wurthwhile:BAAANQADCgcIEQAAAA==.',
Wy='Wyndywalker:BAAANQAECgYIEAAAAA==.',
Xi='Xinnuo:BAAANQADCggIEAAAAA==.',
Za='Zamønk:BAAANQAECgUICwAAAA==.Zarinnara:BAAANQAECgEIAQAAAA==.',
Ze='Zeigfeld:BAAANQAECgEIAQAAAA==.',
Zi='Ziarra:BAAANQADCgUIBQABNQAECgQICAAFAAAAAA==.',
Zo='Zok:BAAANQAECgcICwAAAA==.',
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
