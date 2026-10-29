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
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Acefu:BAABNQAECn8iAAIBAAcKLSB7GACDAgABAAcKLSB7GACDAgAAAA==.Aceo:BAAANQADCgYIBgABNQAECgoKKwACABcLAA==.Acornella:BAABNQAECn8ZAAMDAAkKoRJCUAAzAgADAAkKoRJCUAAzAgAEAAIKABACawBXAAABNQAFFAEIAQAFAAAAAA==.Acornkei:BAAANQAFFAEIAQAAAA==.',
Ad='Adonsia:BAAANQADCgQIBAAAAA==.Adreva:BAABNQAECn8aAAQGAAcKaiAGHABjAgAGAAcKaiAGHABjAgAHAAQKKAIFWwBwAAACAAIK0RDGcwFpAAAAAA==.',
Ae='Aelana:BAAANQADCgQIBAAAAA==.Aendor:BAAANQADCgcIBwABNQAFFAcIDwAIAAYQAA==.Aerea:BAAANQAECgEIAgABNQAECgkJIwAJALoSAA==.Aevastraa:BAAANQADCgEIAQABNQAECgkJMgAKAIUPAA==.',
Ai='Ailanthus:BAABNQAECn8bAAQLAAgKagv6IAANAQALAAUKMQ76IAANAQAMAAUK5QRuiQCuAAANAAIKKAU2bwBJAAAAAA==.',
Al='Albinophil:BAAANQADCgIIAgABNQAECgYIDAAFAAAAAA==.Aleyah:BAAANQAECggICgAAAA==.Alloisaber:BAAANQAECgMIAwAAAA==.Alunne:BAAANQADCgQIBAAAAA==.',
Am='Amna:BAAANQAECgUIDAAAAA==.',
An='Andrelsia:BAAANQAECgEIAQAAAA==.Andrilla:BAAANQADCgYJDAAAAA==.Ankeseth:BAAANQADCggJDQAAAA==.',
Ar='Aracelis:BAAANQAECgEIAQAAAA==.Araxiel:BAAANQADCggICwAAAA==.Archangël:BAAANQAECgEIAQAAAA==.Arkenos:BAAANQADCgYICwAAAA==.Arén:BAABNQAECn8yAAMOAAkKPiGVCwCVAgAOAAkKPiGVCwCVAgAPAAYKshmDOACAAQAAAA==.',
As='Ashenshugär:BAAANQAECgMIAwAAAA==.Aszian:BAAANQABCgcICgAAAA==.Aszun:BAABNQAECn8kAAIQAAcKyxBxoADFAQAQAAcKyxBxoADFAQAAAA==.',
At='Atractiva:BAABNQAECn8qAAMRAAoKMwgoEwB1AQARAAoK3AcoEwB1AQASAAgKzQRiBABoAQAAAA==.',
Au='Augment:BAAANQADCggICAABNQAECgoKKwACABcLAA==.Aura:BAAANQABCgUIBwAAAA==.',
Az='Azmar:BAAANQADCgIIAgAAAA==.Azuri:BAAANQAECgMIBAAAAA==.',
Ba='Balain:BAABNQAECn8jAAMJAAkKuhLzpADAAQAJAAkKuhLzpADAAQAKAAUKOwezHQCiAAAAAA==.Barbiejoe:BAAANQADCgYIBgAAAA==.',
Be='Bear:BAAANQAECgEIAQAAAA==.Beardchi:BAAANQADCgEIAQAAAA==.Bearzerk:BAABNQAECn8nAAITAAkKtQ4jCgBmAQATAAkKtQ4jCgBmAQAAAA==.Benathar:BAAANQAECgYIEAAAAA==.Bethela:BAAANQABCgYIBgABNQAECgcIJAAQAMsQAA==.',
Bi='Birgir:BAAANQAECgQIBAABNQAECggIIQAUAMcZAA==.',
Bl='Blackmagék:BAAANQABCgIIAgAAAA==.Blaston:BAABNQAECn8bAAMVAAYK8ReVEgD+AAADAAUKZRqvTwBzAQAVAAYKUQmVEgD+AAAAAA==.Blightbeard:BAAANQADCggIDgAAAA==.Bloodthorn:BAABNQAECn8gAAQWAAgKBAaZMAA6AQAWAAgKBAaZMAA6AQAXAAMKFQRUPQB3AAAYAAIKPAEGHQArAAAAAA==.',
Bo='Boomnescient:BAAANQADCgYICwAAAA==.Bottomdps:BAABNQAECn8xAAIZAAoKnBskJAD1AgAZAAoKnBskJAD1AgAAAA==.',
Br='Bramis:BAAANQADCggIDQAAAA==.Branor:BAAANQAECgIIAgAAAA==.Bransonian:BAAANQADCgQJBgAAAA==.Brantu:BAABNQAECn8kAAMaAAcKjARTTgCUAAAbAAcKjAQ54QAHAQAaAAUKrQFTTgCUAAAAAA==.Braultus:BAABNQAECn8fAAIcAAgKhxnRNgAvAgAcAAgKhxnRNgAvAgAAAA==.Bravehearth:BAAANQADCgEIAQAAAA==.Breuddwydwr:BAAANQADCgEIAQAAAA==.Brewtality:BAAANQAECgUIBwAAAA==.Breyastrasza:BAAANQADCgYIDwAAAA==.Briarthornz:BAAANQAECgYIBgAAAA==.',
Ca='Caanu:BAACNQAFFH8PAAIIAAcKBhD4BQCPAQAIAAcKBhD4BQCPAQA1AAQKfzcAAggACgrSINIMAPECAAgACgrSINIMAPECAAAA.Calydonia:BAAANQAECgIIAwAAAA==.',
Ce='Celdiseth:BAAANQADCggICwAAAA==.Cerdwin:BAAANQAECgcIDgABNQAECgkJMwANAAsVAA==.',
Ch='Charferad:BAAANQADCgYIDAAAAA==.Chatter:BAAANQADCgcICAAAAA==.Cheeseydeath:BAEANQAECgMIAwAAAA==.Chibeard:BAAANQAECgYIEAAAAA==.Chihîro:BAAANQAECgQIBAAAAA==.',
Cl='Clevercrane:BAAANQAECgMIAgABNQAECgkJHQAXAPgdAA==.',
Co='Coolbro:BAAANQADCgcICAAAAA==.Corialis:BAABNQAECn8oAAMdAAkKMRXnOAC4AQAdAAgKfxPnOAC4AQAZAAYKKguBrAA6AQAAAA==.',
Cr='Crom:BAABNQAECn8zAAIeAAgK5xF+DwCRAQAeAAgK5xF+DwCRAQAAAA==.Crying:BAAANQAECgUIDgAAAA==.',
Cy='Cyn:BAAANQADCgQIBgAAAA==.',
Da='Dandarred:BAABNQAECn8sAAMGAAgKjQkTlQBhAQAGAAgKjQkTlQBhAQACAAcK+ggMswDzAAAAAA==.Dantey:BAAANQADCggIFwABNQAECgoKKwACABcLAA==.Darkwyn:BAAANQADCgUIBQAAAA==.Dawne:BAABNQAECn8YAAIGAAoKLRr3MQCdAgAGAAoKLRr3MQCdAgAAAA==.Dazanna:BAABNQAECn8qAAMGAAgKqBaFTgAwAgAGAAgKqBaFTgAwAgACAAEKAACNpQE0AAAAAA==.Dazjaxx:BAAANQABCgYICQAAAA==.Dazre:BAAANQAECgIIAgAAAA==.',
De='Deeminor:BAAANQADCgIJAgAAAA==.Demeisen:BAABNQAECn8sAAIOAAgKFxQ6IwB7AQAOAAgKFxQ6IwB7AQAAAA==.Demonizerr:BAAANQAECgEIAQABNQAECgoKKwACABcLAA==.',
Di='Digor:BAAANQAECgIIAgABNQAFFAEIAQAFAAAAAA==.Diksensei:BAAANQAECgIIAwAAAA==.Diod:BAAANQAECgYIDgAAAA==.',
Dr='Dracomage:BAAANQADCgQIBwAAAA==.Dracotincan:BAAANQADCgIIAgAAAA==.Draegis:BAAANQABCgIIAgAAAA==.Dragyns:BAABNQAECn8hAAIXAAkKJiDoFQDNAgAXAAkKJiDoFQDNAgAAAA==.Dragynslance:BAAANQADCggIDAABNQAECgkJIQAXACYgAA==.Drayper:BAABNQAECn8aAAMDAAkKmBXeSABLAgADAAkKmBXeSABLAgAVAAEKug88KQAyAAAAAA==.',
Du='Dunbarke:BAABNQAECn8hAAQUAAgKxxnFBwAcAgAUAAgKxxnFBwAcAgAbAAQKiRdy1AAhAQAaAAIKXQtETACaAAAAAA==.',
['Dê']='Dêadlights:BAAANQAECgUIEgAAAA==.',
El='Elendrisa:BAAANQAECgUIDgAAAA==.Elisoria:BAAANQAECgMIAwAAAA==.Ellayssa:BAAANQAECgEIAQAAAA==.Elliwynd:BAABNQAECn8tAAINAAoKnxaVDQBWAgANAAoKnxaVDQBWAgAAAA==.Elway:BAAANQADCgIIAgAAAA==.',
Em='Embermourne:BAAANQADCggICAAAAA==.',
Er='Eraela:BAAANQADCggICAAAAA==.Erinnys:BAABNQAECn8mAAIOAAgKMQruMQAZAQAOAAgKMQruMQAZAQAAAA==.',
Es='Esoteria:BAABNQAECn8zAAIIAAoK+BdlNQAcAgAIAAoK+BdlNQAcAgAAAA==.',
Eu='Eufemia:BAAANQAECgEIAQAAAA==.',
Ev='Evonnya:BAAANQADCggIDgAAAA==.',
Fe='Felfar:BAAANQADCggICwABNQAECgUICQAFAAAAAA==.',
Fi='Finalomega:BAAANQAECgYIEwAAAA==.Finnshot:BAAANQAECgQICwAAAA==.Finrod:BAAANQAECgUIBQAAAA==.',
Fl='Flaminfalcon:BAAANQAECgEIAgABNQAECgkJHQAXAPgdAA==.',
Fo='Foulmilk:BAAANQADCgEIAQAAAA==.Foxflame:BAABNQAECn8zAAMNAAkKCxVMIgAUAgANAAkKCxVMIgAUAgAMAAQKTgrUTgCKAAAAAA==.',
Fr='Franzen:BAAANQADCgYIFAAAAA==.Frawd:BAAANQADCgcIBwABNQAFFAUICQAIAEcdAA==.Freyalys:BAAANQADCgYIEwAAAA==.Frôstblade:BAAANQABCgYIBgAAAA==.',
Fu='Fulanita:BAAANQADCgcIEwAAAA==.Fullmoonpo:BAAANQADCgMIAwAAAA==.Furyaid:BAABNQAECn8rAAIJAAkKHiNiHgA+AwAJAAkKHiNiHgA+AwAAAA==.',
Ga='Galadrael:BAAANQAECgQJBAAAAA==.Gaz:BAAANQADCgQIBAAAAA==.',
Ge='Genkithered:BAAANQAECgYIEAAAAA==.',
Gl='Gloomy:BAAANQADCgEIAQAAAA==.',
Go='Gourak:BAAANQAECgUIEQAAAA==.',
Gr='Grapejuice:BAAANQAECgUIBQAAAA==.Gravemarks:BAAANQADCgYIBAAAAA==.Grimhorn:BAAANQAECgUIEAAAAA==.Grimlie:BAAANQADCgYIDgABNQAECgcIJAAaAIwEAA==.',
Gu='Guaritrice:BAAANQAECgEIAQAAAA==.',
Gw='Gwindor:BAAANQAECgEIAQAAAA==.',
['Gö']='Gödwyn:BAAANQAECgIIAQABNQAECgQICgAFAAAAAA==.',
Ha='Hairyrage:BAAANQABCgQICAAAAA==.Hale:BAAANQADCgEIAgAAAA==.Hatterus:BAABNQAECn8fAAICAAcKrAQ7ywDKAAACAAcKrAQ7ywDKAAAAAA==.',
He='Healzey:BAAANQADCgUIBAAAAA==.Hetairoi:BAAANQAECgYIDAAAAA==.',
Hi='Hillbroken:BAABNQAECn89AAIfAAkKFBomHwDSAQAfAAkKFBomHwDSAQAAAA==.',
Hu='Huan:BAAANQAECgMIBAAAAA==.Huntrix:BAAANQADCgYICgAAAA==.',
Hy='Hyrlis:BAAANQAECgEIAQAAAA==.',
['Hà']='Hànks:BAAANQAECgUIBwAAAA==.',
Ib='Ibíng:BAAANQAECgEIAgAAAA==.',
In='Invariance:BAEANQADCgUIBQABNQAECgUIBQAFAAAAAA==.Inèvitable:BAABNQAECn88AAIgAAkKgR2gIADIAgAgAAkKgR2gIADIAgAAAA==.',
Ir='Ironphant:BAABNQAECn8aAAICAAkKZQmw2gBmAQACAAkKZQmw2gBmAQAAAA==.',
Is='Ishmethit:BAAANQADCgYIBgAAAA==.Istara:BAAANQADCgYIFAAAAA==.',
Je='Jebib:BAAANQAECgYIBgABNQAFFAUICQACAGIiAA==.Jeod:BAAANQAECgEIAQAAAA==.Jettonk:BAAANQABCgIIAgABNQAECgcIJAAaAIwEAA==.',
Ji='Jirachi:BAAANQADCgEIAQAAAA==.',
Jo='Jolty:BAABNQAECn8lAAMgAAkKiiJ4FAAVAwAgAAkKiiJ4FAAVAwAcAAQKGhmshADqAAAAAA==.',
Ju='Junghoulson:BAAANQAECgUIBQAAAA==.',
['Jð']='Jð:BAAANQAECggICQAAAA==.',
Ka='Kaiou:BAAANQADCgUICwAAAA==.Kantor:BAABNQAECn8+AAIDAAkKFw0dQQCvAQADAAkKFw0dQQCvAQAAAA==.Karboomkin:BAAANQAECgIIBAABNQAFFAUIDQAQAOUVAA==.Kasenko:BAAANQADCggICAABNQAECgYIEwAFAAAAAA==.Kasryna:BAAANQAECgYIEwAAAA==.',
Ke='Kelmair:BAAANQADCgYIBgAAAA==.Keta:BAAANQAECgIIAQAAAA==.Ketameanie:BAABNQAECn8wAAIPAAoK3BheDAApAgAPAAoK3BheDAApAgAAAA==.',
Kh='Khadguy:BAABNQAECn8gAAIeAAkKjRlGEABkAgAeAAkKjRlGEABkAgAAAA==.',
Km='Kmazing:BAAANQADCggJFAABNQAECgoKMwAIAPgXAA==.',
Kn='Knikku:BAAANQADCggICAAAAA==.',
Ko='Konoha:BAABNQAECn8vAAMEAAoK9R2HEQDjAgAEAAkKyx6HEQDjAgADAAIKtRu+vABFAAAAAA==.Koven:BAAANQADCggIJAAAAA==.',
Ku='Kultag:BAABNQAECn8lAAICAAoKsRCwSADdAQACAAoKsRCwSADdAQAAAA==.Kuun:BAABNQAECn8ZAAIZAAkK5QmBXQD1AAAZAAkK5QmBXQD1AAAAAA==.',
Ky='Kyaw:BAAANQAECgUIDQAAAA==.Kynzo:BAAANQAECgQICAAAAA==.',
La='Laelah:BAAANQABCgQIBQAAAA==.Lasmína:BAAANQADCgQIBwAAAA==.Laykeezenith:BAACNQAFFH8OAAMQAAcKxiPrAgA/AgAQAAYKXiPrAgA/AgAhAAQKKx3jCwCAAQA1AAQKfygAAyEACgrJImIZAIwCACEACgpQHWIZAIwCABAABwrfIER4AB8CAAAA.Lazuli:BAABNQAECn9EAAMZAAoKABtgGQAyAgAZAAoKABtgGQAyAgAdAAgKiQmFRwB3AQAAAA==.',
Le='Lehann:BAABNQAECn8iAAIQAAkKcwqdWgCOAQAQAAkKcwqdWgCOAQAAAA==.',
Li='Littlebitty:BAAANQAECgcIDgAAAA==.',
Lo='Lockatron:BAAANQADCggIDAABNQAECgoKKwACABcLAA==.Lothryn:BAABNQAECn8oAAMCAAgKzws6jwAzAQACAAgKzws6jwAzAQAGAAQKLA7QzwDcAAAAAA==.',
Lp='Lp:BAABNQAECn8YAAIPAAoKGxx5CgBPAgAPAAoKGxx5CgBPAgAAAA==.',
Lu='Lunariah:BAAANQADCgIJAgAAAA==.',
Ly='Lyllien:BAAANQAECgIIAgAAAA==.',
Ma='Marenus:BAABNQAECn8+AAIQAAkKcgufVgCZAQAQAAkKcgufVgCZAQAAAA==.Marten:BAAANQABCgIIAgAAAA==.Masume:BAAANQAECgUICQAAAA==.Maély:BAAANQADCgUIBQAAAA==.',
Me='Mechadead:BAAANQAECgYIEwABNQAECgoKKwACABcLAA==.Megaopto:BAABNQAECn8bAAIcAAcKThTOJABvAQAcAAcKThTOJABvAQAAAA==.Meowmix:BAAANQADCgMICAAAAA==.Methanny:BAAANQADCgQIBAAAAA==.',
Mi='Mizmonk:BAAANQADCggICAAAAA==.',
Mj='Mjölnir:BAABNQAECn8vAAICAAoK/RZHNAAnAgACAAoK/RZHNAAnAgAAAA==.',
Mo='Momentum:BAAANQAECgEIAQAAAA==.',
Ms='Msdiiva:BAAANQAECgEIAQAAAA==.',
Mu='Mushuu:BAAANQADCgYIDAAAAA==.',
['Mô']='Môjô:BAAANQABCgUIBQAAAA==.',
Na='Nahion:BAAANQAECgEIAQAAAA==.Nashira:BAABNQAECn8lAAIQAAkKaRH4eAAdAgAQAAkKaRH4eAAdAgAAAA==.',
Ne='Nemasus:BAABNQAECn8YAAQNAAYKPxjiQwANAQANAAQKCxjiQwANAQAMAAYKCxRhQQDAAAAiAAUKMAOaRQCdAAAAAA==.Nepolian:BAAANQABCgYICAAAAA==.Neraine:BAAANQAECgUICgAAAA==.',
Ni='Ninjahh:BAABNQAECn8oAAIWAAgKzhR5NwCLAQAWAAgKzhR5NwCLAQAAAA==.Nioshei:BAABNQAECn8yAAMdAAkKqhi3LAD0AQAdAAkKqhi3LAD0AQAZAAMKUwlq+gCeAAAAAA==.',
No='Nochmuerta:BAAANQADCgUIBQABNQADCgcIBwAFAAAAAA==.Nogrid:BAABNQAECn8+AAIHAAkKdh0rCgAWAgAHAAkKdh0rCgAWAgAAAA==.Noxstantine:BAAANQADCgQIBgAAAA==.',
Nu='Nuthar:BAABNQAECn8sAAICAAkKQRzOMQAzAgACAAkKQRzOMQAzAgAAAA==.',
Ny='Nyrrhi:BAAANQAECggIDQAAAA==.',
Ol='Oldeis:BAAANQADCgYJBgAAAA==.',
Or='Orneryosprey:BAAANQAECgQIBwABNQAECgYIDAAFAAAAAA==.',
Ou='Ouroborös:BAABNQAECn8kAAIQAAoKXhGkNQAJAgAQAAoKXhGkNQAJAgAAAA==.',
Oy='Oyashiro:BAAANQAECgcIBwAAAA==.',
Pa='Pamburu:BAABNQAECn8sAAIQAAkKuxRzQQDeAQAQAAkKuxRzQQDeAQAAAA==.Papagrape:BAABNQAECn8tAAMjAAkKtRtABwBnAgAjAAkKtRtABwBnAgAkAAMKOhfOKQDcAAAAAA==.Paradiselost:BAAANQADCgQIBwAAAA==.Parzivàl:BAAANQAECgIIAQAAAA==.Paxa:BAABNQAECn8jAAMDAAkKVBdLNgDgAQADAAkKVBdLNgDgAQAEAAIK4ArtaQBaAAAAAA==.',
Pe='Peekabu:BAAANQADCgcICAABNQAECgoKKwACABcLAA==.Pennelo:BAAANQADCgQIBAAAAA==.Persayis:BAAANQADCgYIDAAAAA==.',
Ph='Phoebel:BAAANQADCgIJAgABNQAECgcIJAAQAMsQAA==.',
Pi='Pineappledk:BAEANQADCggIEgABNQAECgQIBgAFAAAAAA==.Pineapplepn:BAEANQAECgQIBgAAAA==.Pineapplle:BAEANQAECgQIBgABNQAECgQIBgAFAAAAAA==.',
Pl='Plazelly:BAAANQADCgcIDAAAAA==.',
Po='Podnov:BAABNQAECn8xAAIhAAoKPRw9FwCgAgAhAAoKPRw9FwCgAgAAAA==.Pollyanna:BAAANQABCgYICAAAAA==.',
Py='Pyrista:BAAANQAECggICwAAAA==.',
Qa='Qahili:BAAANQADCgUIBQAAAA==.Qang:BAAANQADCgYIDAAAAA==.',
Ra='Radiante:BAACNQAFFH8IAAIGAAUKmgO1EQBHAQAGAAUKmgO1EQBHAQA1AAQKfyAAAwYACQrwHD0dAP4CAAYACQrwHD0dAP4CAAIAAQodA27MASEAAAAA.Rageadin:BAAANQABCgcIBQAAAA==.Raion:BAABNQAECn8vAAIHAAoKXB+CBgCDAgAHAAoKXB+CBgCDAgAAAA==.Raithis:BAACNQAFFH8NAAIQAAYKnRtnDACLAQAQAAYKnRtnDACLAQA1AAQKfzYAAhAACgo3JSwFADwDABAACgo3JSwFADwDAAAA.Raito:BAAANQADCgYIBgAAAA==.Ralzin:BAAANQADCgEIAQAAAA==.Ramhadin:BAEANQADCgcIHAABNQAECggILQAEAEYcAA==.Randel:BAAANQAECggIBgAAAA==.Raucousrhea:BAAANQABCgIIAgAAAA==.Rav:BAAANQAECgYICwAAAA==.',
Re='Redvelvet:BAABNQAECn8lAAIlAAkK8hCGHAC8AQAlAAkK8hCGHAC8AQAAAA==.Resisting:BAAANQAECgYIDAABNQAECgoKGAAPABscAA==.Reznal:BAABNQAECn8cAAMZAAkKmx2ENwCYAgAZAAgKGx6ENwCYAgAdAAUKuB6AeACiAQAAAA==.',
Ro='Romam:BAAANQAECgEIAQAAAA==.',
Ry='Rydran:BAAANQADCgIIAgAAAA==.Rykria:BAAANQADCgYIFAAAAA==.',
Sa='Sableanne:BAABNQAECn89AAIdAAoKJQjojgBjAQAdAAoKJQjojgBjAQAAAA==.Saedirine:BAAANQADCgYIDAAAAA==.Saggi:BAAANQAECgIIBAAAAA==.',
Se='Secksiecutie:BAABNQAECn8vAAIfAAoKQhFKIADKAQAfAAoKQhFKIADKAQAAAA==.Secondwall:BAAANQADCgYIBgAAAA==.Selma:BAAANQABCgMIAwAAAA==.Serinar:BAABNQAECn8ZAAICAAgK5hNNqADPAQACAAgK5hNNqADPAQAAAA==.',
Sh='Shadowbolt:BAAANQABCgQIBgAAAA==.Shoorah:BAAANQADCgEIAQAAAA==.',
Si='Siako:BAABNQAECn8UAAMSAAgKXQeOBABcAQAIAAgKEQRxFgFnAQASAAcKFwiOBABcAQAAAA==.Silversaiyan:BAABNQAECn8xAAITAAkKjRouBwCJAgATAAkKjRouBwCJAgAAAA==.Sirlink:BAAANQABCgIIAgAAAA==.',
Sl='Slade:BAABNQAECn9FAAMWAAoKrCE2BABTAwAWAAoKrCE2BABTAwAXAAYKhRfHFwA9AQAAAA==.Sliyce:BAAANQADCgEIAQAAAA==.',
Sm='Smorc:BAAANQAECgQIBwAAAA==.',
Sn='Sneakyclubs:BAAANQADCgUICAAAAA==.Snowfawn:BAAANQAECgQIBgABNQAECggIFgAbAFcIAA==.',
So='Sofedan:BAABNQAECn89AAIhAAkKEgYqHAAfAQAhAAkKEgYqHAAfAQAAAA==.Sorgath:BAAANQAECgEIAgAAAA==.Soriel:BAABNQAECn8yAAImAAkK2xILCABqAQAmAAkK2xILCABqAQAAAA==.Sorokwa:BAABNQAECn8uAAIgAAoKcAQ/hwAEAQAgAAoKcAQ/hwAEAQAAAA==.',
Sq='Squeeze:BAAANQAECgUJCwAAAA==.',
St='Stillwater:BAABNQAECn8uAAQeAAoKpwuSDQC3AQAeAAoKpwuSDQC3AQAZAAMKygONCAF7AAAdAAEKMQRB2wAeAAAAAA==.Strathius:BAAANQAECgEIAQAAAA==.',
Su='Suriden:BAAANQADCggICQAAAA==.',
Sw='Swagidan:BAABNQAECn8/AAIOAAoKiRmTEABDAgAOAAoKiRmTEABDAgAAAA==.Sweaterpally:BAAANQADCgUICQAAAA==.Swiftera:BAAANQAECgIIAgAAAA==.Swiftlier:BAAANQAECgcICAABNQAECgoKNAAcAN8OAA==.',
Sy='Sylphrène:BAABNQAECn8cAAMPAAgKYQKRLgC0AAAPAAgKYQKRLgC0AAAOAAMKUQHcjQBAAAAAAA==.',
Ta='Taghman:BAAANQAECgMIBwABNQAECgoKRQAWAKwhAA==.Taleth:BAAANQAECgIIAwABNQAECgMIBAAFAAAAAA==.Tandrana:BAAANQAECgEIAQAAAA==.Targanisha:BAAANQADCggICAABNQAECgoKMQAZAJwbAA==.Targdh:BAABNQAECn9JAAIPAAoKsR38EQDcAgAPAAoKsR38EQDcAgABNQAECgoKMQAZAJwbAA==.Targforeva:BAAANQAECgQIBgABNQAECgoKMQAZAJwbAA==.',
Te='Terminus:BAAANQADCgMIAwAAAA==.',
Ti='Ticebane:BAABNQAECn8XAAIgAAgKkQsWZQB8AQAgAAgKkQsWZQB8AQAAAA==.Tichus:BAAANQADCgYIDgAAAA==.Tiduspullo:BAAANQAECgQIBQABNQAECgUIBwAFAAAAAA==.Titanbeard:BAAANQADCggIGAAAAA==.Titor:BAABNQAECn8pAAMjAAcKdRB2EgBDAQAjAAcKdRB2EgBDAQAkAAIKKALINwBQAAAAAA==.Tituspullo:BAAANQAECgUIBwAAAA==.',
To='Tock:BAAANQAECgEIAQAAAA==.Tolduan:BAABNQAECn8dAAMZAAgKvwpJVQANAQAZAAgKvwpJVQANAQAeAAUKAARuLQCRAAAAAA==.Totemik:BAAANQADCgUIBQAAAA==.Toughturkey:BAAANQADCgEIAQABNQAECgYIDAAFAAAAAA==.',
Tr='Tricarnetry:BAABNQAECn8rAAICAAoKFwsOagCCAQACAAoKFwsOagCCAQAAAA==.Tricarnity:BAAANQAECgUIDgABNQAECgoKKwACABcLAA==.Trucknôrris:BAAANQADCgUIBwAAAA==.Trîela:BAAANQAECgcIEgAAAA==.',
Ul='Ulfer:BAAANQADCgYIBgABNQAECggIGwAgAGAfAA==.',
Um='Um:BAAANQAECgQIBQAAAA==.',
Ve='Veganwolf:BAAANQADCgMIAwAAAA==.Verakis:BAABNQAECn8yAAIKAAkKhQ/vCwB9AQAKAAkKhQ/vCwB9AQAAAA==.Verndarí:BAABNQAECn80AAIcAAoK3w57HwCWAQAcAAoK3w57HwCWAQAAAA==.Verudora:BAAANQAECgEIAQAAAA==.',
Vi='Vishas:BAAANQAECgQIBgAAAA==.',
Vo='Vortheus:BAAANQAECgcIDgAAAA==.Votollis:BAAANQAECgEIAQAAAA==.',
Vr='Vrack:BAAANQADCgQIBAAAAA==.',
Wa='Warhowl:BAAANQABCggIDgAAAA==.Warlanen:BAAANQAECgEIAQAAAA==.',
Wi='Willbur:BAABNQAECn81AAIIAAkKHBDhUwCxAQAIAAkKHBDhUwCxAQAAAA==.',
Wu='Wurthwhile:BAAANQADCgcIEQAAAA==.',
Wy='Wyndywalker:BAAANQAECgYIEAAAAA==.',
Xa='Xayvior:BAAANQAECgYIBgAAAA==.',
Xi='Xinnuo:BAAANQADCggIEAAAAA==.',
Za='Zamønk:BAAANQAECgUICQAAAA==.',
Ze='Zeigfeld:BAAANQADCgYIDAAAAA==.',
Zi='Ziarra:BAAANQADCgYIBQABNQAECgQIBwAFAAAAAA==.',
Zo='Zok:BAAANQAECggIEwAAAA==.',
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
