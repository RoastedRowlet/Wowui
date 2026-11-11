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

local lookup = {'Monk-Windwalker','Paladin-Retribution','Priest-Holy','Priest-Shadow','Unknown-Unknown','Paladin-Holy','Paladin-Protection','Mage-Arcane','Warrior-Arms','Warrior-Protection','Druid-Balance','Druid-Feral','Druid-Restoration','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Mage-Frost','Mage-Fire','Warrior-Fury','Warlock-Affliction','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','DeathKnight-Blood','Monk-Brewmaster','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Unholy','Druid-Guardian','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Acefu:BAABNQAECn8iAAIBAAcKLSB7GACDAgABAAcKLSB7GACDAgAAAA==.Aceo:BAAANQADCgYIDwABNQAECgoKOwACAO0OAA==.Acornella:BAABNQAECn8ZAAMDAAkKoRJCUAAzAgADAAkKoRJCUAAzAgAEAAIKABACawBXAAABNQAFFAEIAQAFAAAAAA==.Acornkei:BAAANQAFFAEIAQAAAA==.',
Ad='Adonsia:BAAANQADCgQIBAAAAA==.Adreva:BAABNQAECn8iAAQGAAoK4B6xDwA0AwAGAAoK4B6xDwA0AwAHAAQKKAIFWwBwAAACAAIK0RDGcwFpAAAAAA==.',
Ae='Aelana:BAAANQADCgQIBAAAAA==.Aendor:BAAANQAECgEIAQABNQAFFAcIDwAIAAYQAA==.Aerea:BAAANQAECgEIAgABNQAECgkJJwAJACoVAA==.Aevastraa:BAAANQADCgEIAQABNQAECgoKRQAKADYRAA==.',
Ai='Ailanthus:BAABNQAECn8lAAQLAAoK/wrsMQBiAQALAAoKQAnsMQBiAQAMAAUKMQ76IAANAQANAAIKKAU2bwBJAAAAAA==.',
Al='Albinophil:BAAANQADCgIIAgABNQAECgYIDwAFAAAAAA==.Aleyah:BAAANQAECggIEAAAAA==.Alloisaber:BAAANQAECgQIBQAAAA==.Alunne:BAAANQAECgIIAgAAAA==.',
Am='Amna:BAAANQAECgUIDQAAAA==.',
An='Andrelsia:BAAANQAECgIIAwAAAA==.Andrilla:BAAANQADCgYJDAAAAA==.Ankeseth:BAAANQADCggJDQAAAA==.',
Ar='Aracelis:BAAANQAECgEIAQAAAA==.Araxiel:BAAANQAECgUIBgAAAA==.Archangël:BAAANQAECgEIAQAAAA==.Arkenos:BAAANQAECgIIAgAAAA==.Arén:BAABNQAECn85AAMOAAkKPiGWEwB0AgAOAAkKPiGWEwB0AgAPAAYKshmDOACAAQAAAA==.',
As='Ashenshugär:BAAANQAECgMIBAAAAA==.Aszian:BAAANQABCgcICgAAAA==.Aszun:BAABNQAECn8lAAIQAAcKyxBxoADFAQAQAAcKyxBxoADFAQAAAA==.',
At='Atractiva:BAABNQAECn8rAAMRAAoKMwgoEwB1AQARAAoK3AcoEwB1AQASAAgKzQRiBABoAQAAAA==.',
Au='Augment:BAAANQADCggIDAABNQAECgoKOwACAO0OAA==.Aura:BAAANQABCgUIBwAAAA==.',
Az='Azmar:BAAANQADCgIIAgAAAA==.Azuri:BAAANQAECgYIEQAAAA==.',
Ba='Balain:BAABNQAECn8nAAMJAAkKKhXzpADAAQAJAAkKKhXzpADAAQAKAAUKOwf4KQCaAAAAAA==.Barbiejoe:BAAANQADCgYIBgAAAA==.',
Be='Bear:BAAANQAECgUICAAAAA==.Beardchi:BAAANQADCgEIAQAAAA==.Bearzerk:BAABNQAECn82AAITAAoKmRDQCgDKAQATAAoKmRDQCgDKAQAAAA==.Benathar:BAABNQAECn8VAAIIAAYKhQa/AAGjAAAIAAYKhQa/AAGjAAAAAA==.Bethela:BAAANQAECgQIBAABNQAECgcIJQAQAMsQAA==.',
Bi='Birgir:BAAANQAECgQIBAABNQAECggIIwAUABYaAA==.',
Bl='Blackgrim:BAAANQADCgYIBgAAAA==.Blackmagék:BAAANQABCgIIAgAAAA==.Bladestormer:BAAANQADCgEIAQABNQAECgoKOwACAO0OAA==.Blaston:BAABNQAECn8hAAMDAAgKvBYhUADjAQADAAcKURghUADjAQAVAAYKUQmVEgD+AAAAAA==.Blightbeard:BAAANQADCggIDgAAAA==.Bloodthorn:BAABNQAECn8rAAQWAAkK1QcgZgBZAQAWAAkK1QcgZgBZAQAXAAMKFQQGRgBxAAAYAAIKPAEGHQArAAAAAA==.',
Bo='Boomnescient:BAAANQADCgYICwAAAA==.Bottomdps:BAABNQAECn8xAAIZAAoKnBskJAD1AgAZAAoKnBskJAD1AgAAAA==.',
Br='Bramis:BAAANQAECgEIAQAAAA==.Branor:BAAANQAECgMIBAAAAA==.Bransonian:BAAANQADCgQIBgAAAA==.Brantu:BAABNQAECn8lAAMaAAcKjARTTgCUAAAbAAcKjAQ54QAHAQAaAAUKrQFTTgCUAAAAAA==.Braultus:BAABNQAECn8fAAIcAAgKhxnRNgAvAgAcAAgKhxnRNgAvAgAAAA==.Bravehearth:BAAANQADCgEIAQAAAA==.Breuddwydwr:BAAANQADCgEIAQAAAA==.Brewtality:BAAANQAECgYIDQAAAA==.Breyastrasza:BAAANQADCggIGAAAAA==.Briarthornz:BAAANQAECggIEgAAAA==.',
Ca='Caanu:BAACNQAFFH8PAAIIAAcKBhCUDQB7AQAIAAcKBhCUDQB7AQA1AAQKf0UAAggACgqwIqMQAAYDAAgACgqwIqMQAAYDAAAA.Calydonia:BAAANQAECgIIAwAAAA==.',
Ce='Celdiseth:BAAANQADCggICwAAAA==.Cerdwin:BAABNQAECn8XAAMGAAkKQxIUcgBLAQAGAAkKQxIUcgBLAQACAAIKnQfUmwEmAAABNQAECgoKQQANAFYVAA==.',
Ch='Charferad:BAAANQAECgIIAgAAAA==.Chatter:BAAANQADCgcICAAAAA==.Cheeseydeath:BAEANQAECgMIAwAAAA==.Chibeard:BAABNQAECn8VAAIdAAYK7xxiDwAcAQAdAAYK7xxiDwAcAQAAAA==.Chihîro:BAAANQAECgQIBAAAAA==.',
Cl='Clevercrane:BAAANQAECgMIAgABNQAECgkJIwAXAKkhAA==.',
Co='Coolbro:BAAANQADCgcICAAAAA==.Corialis:BAABNQAECn8uAAMeAAoKZROwOwASAgAeAAoKZROwOwASAgAZAAYKKguBrAA6AQAAAA==.',
Cr='Crom:BAABNQAECn86AAIfAAoKgRAjEAD/AQAfAAoKgRAjEAD/AQAAAA==.Crosis:BAAANQADCgYIBgAAAA==.Crying:BAAANQAECgUIEgAAAA==.',
Cy='Cyn:BAAANQADCgQIBgAAAA==.',
Da='Dandarred:BAABNQAECn82AAMCAAoKEQyquQBIAQACAAkKUwmquQBIAQAGAAgKtQnleAA3AQAAAA==.Danden:BAAANQAECgEIAQAAAA==.Dantey:BAAANQADCggIGwABNQAECgoKOwACAO0OAA==.Darkwyn:BAAANQADCgUIBQAAAA==.Dawne:BAABNQAECn8YAAIGAAoKLRr3MQCdAgAGAAoKLRr3MQCdAgAAAA==.Dazanna:BAABNQAECn8sAAMGAAoKDhSFTgAwAgAGAAoKDhSFTgAwAgACAAEKAACNpQE0AAAAAA==.Dazjaxx:BAAANQABCgYICQAAAA==.Dazre:BAAANQAECgIIAgAAAA==.',
De='Deeminor:BAAANQADCgIJAgAAAA==.Demeisen:BAABNQAECn8zAAIOAAkKABTLKgCiAQAOAAkKABTLKgCiAQAAAA==.Demonizerr:BAAANQAECgEIAQABNQAECgoKOwACAO0OAA==.',
Di='Digor:BAAANQAECgIIAgABNQAFFAEIAQAFAAAAAA==.Diksensei:BAAANQAECgIIBgAAAA==.Diod:BAAANQAECgUIEwAAAA==.',
Dr='Dracomage:BAAANQADCgQIBwAAAA==.Dracotincan:BAAANQADCgIIAgAAAA==.Draegis:BAAANQABCgIIAgAAAA==.Dragyns:BAABNQAECn8hAAIXAAkKJiDoFQDNAgAXAAkKJiDoFQDNAgAAAA==.Dragynslance:BAAANQADCggIDAABNQAECgkJIQAXACYgAA==.Drayper:BAABNQAECn8jAAMDAAkKKBbeSABLAgADAAkKKBbeSABLAgAVAAEKug88KQAyAAAAAA==.',
Du='Dunbarke:BAABNQAECn8jAAQUAAgKFhrFBwAcAgAUAAgKFhrFBwAcAgAbAAQKiRdy1AAhAQAaAAIKXQtETACaAAAAAA==.',
['Dê']='Dêadlights:BAAANQAECgUIEgAAAA==.',
El='Elash:BAAANQAECgMIBwAAAA==.Elbrimar:BAAANQAECgEIAQAAAA==.Elendrisa:BAAANQAECgUIDgAAAA==.Elisoria:BAAANQAECgYICwAAAA==.Ellayssa:BAAANQAECgEIAwAAAA==.Elliwynd:BAABNQAECn80AAINAAoKtBjDFABnAgANAAoKtBjDFABnAgAAAA==.Elway:BAAANQADCgIIAgAAAA==.',
Em='Embermourne:BAAANQADCggICAAAAA==.',
Er='Eraela:BAAANQADCggICAAAAA==.Erinnys:BAABNQAECn8wAAIOAAoKvwnSMwBnAQAOAAoKvwnSMwBnAQAAAA==.',
Es='Esoteria:BAABNQAECn85AAIIAAoKDhoaRgAtAgAIAAoKDhoaRgAtAgAAAA==.',
Eu='Eufemia:BAAANQAECgYIBwAAAA==.',
Ev='Evonnya:BAAANQADCggIDgAAAA==.',
Fe='Felfar:BAAANQADCggICwABNQAECgUICwAFAAAAAA==.',
Fi='Finalomega:BAABNQAECn8WAAIcAAcKBgw9UADtAAAcAAcKBgw9UADtAAAAAA==.Finnshot:BAABNQAECn8WAAIQAAYKGxGY1gBTAQAQAAYKGxGY1gBTAQAAAA==.Finrod:BAAANQAECgUIBQAAAA==.',
Fl='Flaminfalcon:BAAANQAECgEIAgABNQAECgkJIwAXAKkhAA==.',
Fo='Foulmilk:BAAANQADCgEIAQAAAA==.Foxflame:BAABNQAECn9BAAMNAAoKVhVjGAA2AgANAAoKVhVjGAA2AgALAAQKTgpmZACDAAAAAA==.',
Fr='Franzen:BAAANQAECgEIAQAAAA==.Frawd:BAAANQADCgcIBwABNQAFFAUICQAIAEcdAA==.Freyalys:BAAANQADCggIHAAAAA==.Frôstblade:BAAANQABCgYIBgAAAA==.',
Fu='Fulanita:BAAANQADCgcIEwAAAA==.Fullmoonpo:BAAANQADCgMIAwAAAA==.Furyaid:BAABNQAECn8+AAIJAAoK8yEJEAASAwAJAAoK8yEJEAASAwAAAA==.',
Ga='Galadrael:BAAANQAECgQJBAAAAA==.Gaz:BAAANQADCgQIBAAAAA==.',
Ge='Genkithered:BAABNQAECn8ZAAIeAAkKjhauQgDyAQAeAAkKjhauQgDyAQAAAA==.',
Gl='Gloomy:BAAANQADCgEIAQAAAA==.',
Go='Gourak:BAAANQAECgUIEgAAAA==.',
Gr='Graleywrld:BAAANQAECgEIAQAAAA==.Grapejuice:BAABNQAECn8UAAMGAAoKphjuGQDZAgAGAAoKphjuGQDZAgACAAIK2gY+iwEzAAAAAA==.Gravemarks:BAAANQADCgYIBAAAAA==.Grimhorn:BAABNQAECn8eAAILAAcKuAXEUgDBAAALAAcKuAXEUgDBAAAAAA==.Grimlie:BAAANQADCgYIDgABNQAECgcIJQAaAIwEAA==.',
Gu='Guaritrice:BAAANQAECgEIAQAAAA==.',
Gw='Gwindor:BAAANQAECgIIAwAAAA==.',
['Gö']='Gödwyn:BAAANQAECgIIBAABNQAECgQICgAFAAAAAA==.',
Ha='Hairyrage:BAAANQABCgQICAAAAA==.Hale:BAAANQADCgEIAgAAAA==.Hatterus:BAABNQAECn8xAAICAAkKgwmesQBXAQACAAkKgwmesQBXAQAAAA==.',
He='Healzey:BAAANQADCgUIBAAAAA==.Heavygator:BAAANQADCgEIAQAAAA==.Hetairoi:BAAANQAECgYIDwAAAA==.',
Hi='Hillbroken:BAABNQAECn9RAAIgAAoKQhquIAA2AgAgAAoKQhquIAA2AgAAAA==.',
Ho='Holynez:BAAANQAECgYIAgAAAA==.',
Hu='Huan:BAAANQAECgMIBAAAAA==.Huntertidus:BAAANQAECgMIAwABNQAECgQIDAAFAAAAAA==.Huntrix:BAAANQAECgIIAgAAAA==.',
Hy='Hyrlis:BAAANQAECgEIAQAAAA==.',
['Hà']='Hànks:BAAANQAECgUIDAAAAA==.',
Ib='Ibíng:BAAANQAECggIEQAAAA==.',
Ic='Iceatron:BAAANQADCgQICAABNQAECgoKOwACAO0OAA==.',
In='Invariance:BAEANQADCgUIBQABNQAECgUIBQAFAAAAAA==.Inèvitable:BAABNQAECn9QAAIhAAoK6h0ZDgCNAgAhAAoK6h0ZDgCNAgAAAA==.',
Ir='Ironphant:BAABNQAECn8eAAICAAkKVQqw2gBmAQACAAkKVQqw2gBmAQAAAA==.',
Is='Ishmethit:BAAANQADCgYIBgAAAA==.Istara:BAAANQADCgcIFQAAAA==.',
Je='Jebib:BAAANQAECgYIBgABNQAFFAkJJAANAPYjAA==.Jeod:BAAANQAECgIIAwAAAA==.Jettonk:BAAANQABCgIIAgABNQAECgcIJQAaAIwEAA==.',
Ji='Jirachi:BAAANQADCgEIAQAAAA==.',
Jo='Jolty:BAABNQAECn8lAAMhAAkKiiJ4FAAVAwAhAAkKiiJ4FAAVAwAcAAQKGhmshADqAAAAAA==.',
Ju='Junghoulson:BAAANQAECgUIBQAAAA==.',
['Jð']='Jð:BAAANQAECggICQAAAA==.',
Ka='Kaiou:BAAANQADCgUICwAAAA==.Kantor:BAABNQAECn9SAAIDAAoKow38SAD+AQADAAoKow38SAD+AQAAAA==.Karboomkin:BAAANQAECgIIBAABNQAFFAUIDQAQAOUVAA==.Kasenko:BAAANQADCggICAABNQAECgcIGQAiAIoZAA==.Kasryna:BAABNQAECn8ZAAIiAAcKihmyHwBuAQAiAAcKihmyHwBuAQAAAA==.',
Ke='Kelmair:BAAANQADCgYIBgAAAA==.Keta:BAAANQAECgIIAQAAAA==.Ketameanie:BAABNQAECn8+AAIPAAoKTRy6DQBtAgAPAAoKTRy6DQBtAgAAAA==.',
Kh='Khadguy:BAABNQAECn8kAAIfAAkKjRlGEABkAgAfAAkKjRlGEABkAgAAAA==.',
Km='Kmazing:BAAANQADCggJFAABNQAECgoKOQAIAA4aAA==.',
Kn='Knikku:BAAANQADCggICAAAAA==.',
Ko='Konoha:BAABNQAECn81AAMEAAoKwh6ZDQBuAgAEAAoKwh6ZDQBuAgADAAIKtRst8QBRAAAAAA==.Koven:BAAANQADCggIJAAAAA==.',
Ku='Kultag:BAABNQAECn8rAAICAAoKVBKEbADkAQACAAoKVBKEbADkAQAAAA==.Kuun:BAABNQAECn8bAAIZAAkK5QlMmgBjAQAZAAkK5QlMmgBjAQAAAA==.',
Ky='Kyaw:BAAANQAECgUIDQAAAA==.Kynzo:BAAANQAECgQICAAAAA==.',
La='Laelah:BAAANQABCgQIBQAAAA==.Lasmína:BAAANQADCgQIBwAAAA==.Laykeezenith:BAACNQAFFH8OAAMQAAcKxiPrAgA/AgAQAAYKXiPrAgA/AgAjAAQKKx3jCwCAAQA1AAQKfygAAyMACgrJImIZAIwCACMACgpQHWIZAIwCABAABwrfIER4AB8CAAAA.Lazuli:BAABNQAECn9MAAMZAAoKIx7dHQByAgAZAAoKIx7dHQByAgAeAAgKiQlqawBbAQAAAA==.',
Le='Lehann:BAABNQAECn8sAAIQAAoKiA36VwADAgAQAAoKiA36VwADAgAAAA==.',
Li='Littlebitty:BAABNQAECn8bAAIWAAoKbwXmdQAmAQAWAAoKbwXmdQAmAQAAAA==.',
Lo='Lockatron:BAAANQADCggIEQABNQAECgoKOwACAO0OAA==.Lothryn:BAABNQAECn81AAMGAAoKOQ0ORQDsAQAGAAoKOQ0ORQDsAQACAAkKPQsjrwBbAQAAAA==.',
Lp='Lp:BAABNQAECn8bAAIPAAoKGxzXEgAhAgAPAAoKGxzXEgAhAgAAAA==.',
Lu='Lunariah:BAAANQADCgIIAgAAAA==.',
Ly='Lyllien:BAAANQAECgIIAgAAAA==.',
Ma='Marenus:BAABNQAECn9BAAIQAAkKrQsvfwChAQAQAAkKrQsvfwChAQAAAA==.Marten:BAAANQABCgIIAgAAAA==.Masume:BAAANQAECgUICgAAAA==.Maély:BAAANQADCgUIBQAAAA==.',
Me='Mechadead:BAABNQAECn8ZAAIgAAcKXgOEhACMAAAgAAcKXgOEhACMAAABNQAECgoKOwACAO0OAA==.Megaopto:BAABNQAECn8pAAIcAAcKIBbLLgCHAQAcAAcKIBbLLgCHAQAAAA==.Meowmix:BAAANQADCgMICAAAAA==.Methanny:BAAANQADCgQIBAAAAA==.',
Mi='Mizmonk:BAAANQADCggICAAAAA==.',
Mj='Mjölnir:BAABNQAECn8/AAICAAoKqBoRQQBYAgACAAoKqBoRQQBYAgAAAA==.',
Mo='Momentum:BAAANQAECgMIBgAAAA==.',
Ms='Msdiiva:BAAANQAECgMICQAAAA==.',
Mu='Mushuu:BAAANQADCgYIDAAAAA==.',
My='Myrwynn:BAAANQAECgEIAgABNQAECgoKOAAQAEcXAA==.',
['Mô']='Môjô:BAAANQABCgUIBQAAAA==.',
Na='Nahion:BAAANQAECgIIAwAAAA==.Nashira:BAABNQAECn8rAAIQAAoKexL4eAAdAgAQAAoKexL4eAAdAgAAAA==.',
Ne='Nemasus:BAABNQAECn8cAAQNAAYKPxjiQwANAQANAAQKCxjiQwANAQALAAYKCxRLUwC/AAAiAAUKMAOaRQCdAAAAAA==.Nepolian:BAAANQABCgYICAAAAA==.Neraine:BAAANQAECgUIEAAAAA==.',
Ni='Ninjahh:BAABNQAECn82AAIWAAoK1hMuNwAJAgAWAAoK1hMuNwAJAgAAAA==.Nioshei:BAABNQAECn9FAAMeAAoKiRnIHwCqAgAeAAoKiRnIHwCqAgAZAAYKBAgQhQDuAAAAAA==.',
No='Nochmuerta:BAAANQADCgUIBQABNQADCgcIBwAFAAAAAA==.Noctyrna:BAAANQABCgQIAgAAAA==.Nogrid:BAABNQAECn9SAAIHAAoKayGXBQD6AgAHAAoKayGXBQD6AgAAAA==.Noxstantine:BAAANQADCgQIBgAAAA==.',
Nu='Nuthar:BAABNQAECn82AAICAAoKGB0HMwCJAgACAAoKGB0HMwCJAgAAAA==.',
Ny='Nyrrhi:BAAANQAECggIDwAAAA==.',
Ol='Oldeis:BAAANQADCgYJBgAAAA==.',
Or='Orneryosprey:BAAANQAECgQIBwABNQAECgYIDwAFAAAAAA==.',
Ou='Ouroborös:BAABNQAECn8qAAIQAAoKbhFDWgD9AQAQAAoKbhFDWgD9AQAAAA==.',
Oy='Oyashiro:BAAANQAECggIDQAAAA==.',
Pa='Pamburu:BAABNQAECn9AAAIQAAoKDhVHQABCAgAQAAoKDhVHQABCAgAAAA==.Papagrape:BAABNQAECn8yAAMkAAkKtRttCwBdAgAkAAkKtRttCwBdAgAlAAUKKBJHFwC0AAAAAA==.Paradiselost:BAAANQADCgQIBwAAAA==.Parzivàl:BAAANQAECgIIAQAAAA==.Paxa:BAABNQAECn8qAAMDAAkK+RgqOABHAgADAAkK+RgqOABHAgAEAAIK4ArtaQBaAAAAAA==.',
Pe='Peekabu:BAAANQADCgcICAABNQAECgoKOwACAO0OAA==.Pennelo:BAAANQAECgEIAgAAAA==.Persayis:BAAANQAECgIIAgAAAA==.',
Ph='Phoebel:BAAANQADCgIJAgABNQAECgcIJQAQAMsQAA==.',
Pi='Pineappledk:BAEANQADCggIEgABNQAECgQIBwAFAAAAAA==.Pineapplepn:BAEANQAECgQIBwAAAA==.Pineapplle:BAEANQAECgQIBgABNQAECgQIBwAFAAAAAA==.',
Pl='Plazelly:BAAANQADCgcIDAAAAA==.',
Po='Podnov:BAABNQAECn8yAAIjAAoKPRw9FwCgAgAjAAoKPRw9FwCgAgAAAA==.Pollyanna:BAAANQABCgYICAAAAA==.',
Py='Pyrista:BAAANQAECggICwAAAA==.',
Qa='Qahili:BAAANQADCgUIBQAAAA==.Qang:BAAANQAECgIIAwAAAA==.',
Ra='Radiante:BAACNQAFFH8IAAIGAAUKmgO1EQBHAQAGAAUKmgO1EQBHAQA1AAQKfyAAAwYACQrwHD0dAP4CAAYACQrwHD0dAP4CAAIAAQodA27MASEAAAAA.Rageadin:BAAANQAECgEIAQAAAA==.Raion:BAABNQAECn81AAIHAAoKxx/rCgB1AgAHAAoKxx/rCgB1AgAAAA==.Raithis:BAACNQAFFH8UAAIQAAcKQR27AwCzAQAQAAcKQR27AwCzAQA1AAQKf0sAAhAACgrkJVIEAGsDABAACgrkJVIEAGsDAAAA.Raito:BAAANQADCgYIBgAAAA==.Ralzin:BAAANQADCgEIAQAAAA==.Ramhadin:BAEANQADCgcIHAABNQAECgkJNgAEACscAA==.Randel:BAAANQAECggIBwAAAA==.Raucousrhea:BAAANQABCgIIAgAAAA==.Rav:BAAANQAECgYICwAAAA==.',
Re='Redvelvet:BAABNQAECn8rAAImAAoKNhCGHAC8AQAmAAoKNhCGHAC8AQAAAA==.Resisting:BAAANQAECgYIDAABNQAECgoKGwAPABscAA==.Reznal:BAABNQAECn8dAAMZAAkKCB2ENwCYAgAZAAkKCB2ENwCYAgAeAAUKuB6AeACiAQABNQAFFAIIBQAIADwTAA==.',
Ro='Romam:BAAANQAECgIIAwAAAA==.',
Ry='Rydran:BAAANQADCgIIAgAAAA==.Rykria:BAAANQADCggIHQAAAA==.',
Sa='Sableanne:BAABNQAECn9BAAIeAAoKbAjojgBjAQAeAAoKbAjojgBjAQAAAA==.Saedirine:BAAANQADCgYIDAAAAA==.Saggi:BAAANQAECgIIBQAAAA==.Savash:BAAANQAECgIIAgAAAA==.',
Se='Secksiecutie:BAABNQAECn80AAIgAAoKzBEDMwDEAQAgAAoKzBEDMwDEAQAAAA==.Secondwall:BAAANQADCgYIBgAAAA==.Selma:BAAANQABCgMIAwAAAA==.Serinar:BAABNQAECn8ZAAICAAgK5hNNqADPAQACAAgK5hNNqADPAQAAAA==.',
Sh='Shadowbolt:BAAANQABCgQIBgAAAA==.Shayd:BAAANQAECgEIAQAAAA==.Shillelagh:BAAANQAECgEIAQAAAA==.Shoorah:BAAANQADCgEIAQAAAA==.',
Si='Siako:BAABNQAECn8WAAMSAAoKlgaOBABcAQAIAAoKHQRxFgFnAQASAAcKFwiOBABcAQAAAA==.Silversaiyan:BAABNQAECn9DAAITAAkKkCENBACsAgATAAkKkCENBACsAgAAAA==.Sirlink:BAAANQABCgIIAgAAAA==.',
Sl='Slade:BAABNQAECn9eAAMWAAoKkCLoCgAaAwAWAAoKkCLoCgAaAwAXAAYKhRcaHwAoAQAAAA==.Sliyce:BAAANQADCgEIAQAAAA==.',
Sm='Smorc:BAAANQAECgQIBwAAAA==.',
Sn='Sneakyclubs:BAAANQADCgUICAAAAA==.Snowfawn:BAAANQAECgUIDQABNQAECggIFgAbAFcIAA==.',
So='Sofedan:BAABNQAECn9KAAIjAAoKlQZbHgBsAQAjAAoKlQZbHgBsAQAAAA==.Sorgath:BAAANQAECgIIBQAAAA==.Soriel:BAABNQAECn9FAAIdAAoKdRQLCADHAQAdAAoKdRQLCADHAQAAAA==.Sorokwa:BAABNQAECn8uAAIhAAoKcAQ/hwAEAQAhAAoKcAQ/hwAEAQAAAA==.',
Sq='Squeeze:BAAANQAECgUJCwAAAA==.',
St='Stillwater:BAABNQAECn80AAQfAAoKJQxgFAC2AQAfAAoKJQxgFAC2AQAZAAMKygONCAF7AAAeAAIK6wOX4gBGAAAAAA==.Strathius:BAAANQAECgIIAwAAAA==.',
Su='Suriden:BAAANQADCggICQAAAA==.',
Sw='Swagidan:BAABNQAECn9FAAIOAAoK4xlpGQA1AgAOAAoK4xlpGQA1AgAAAA==.Sweaterpally:BAAANQADCgUICQAAAA==.Swiftera:BAAANQAECgIIAgAAAA==.Swiftlier:BAAANQAECgcICQABNQAECgoKQAAcAIkPAA==.',
Sy='Sylphrène:BAABNQAECn8jAAMPAAkKiQJNNwDOAAAPAAkKiQJNNwDOAAAOAAMKUQHcjQBAAAAAAA==.',
Ta='Taghman:BAAANQAECgMICwABNQAECgoKXgAWAJAiAA==.Taleth:BAAANQAECgIIAwABNQAECgYIEQAFAAAAAA==.Tandrana:BAAANQAECgEIAQAAAA==.Targanisha:BAAANQADCggICAABNQAECgoKMQAZAJwbAA==.Targdh:BAABNQAECn9dAAIPAAoKqSCNCQCyAgAPAAoKqSCNCQCyAgABNQAECgoKMQAZAJwbAA==.Targforeva:BAAANQAECgQIBgABNQAECgoKMQAZAJwbAA==.Targthesting:BAAANQAECgYIBgABNQAECgoKMQAZAJwbAA==.',
Te='Telin:BAAANQAECgEIAQAAAA==.Terminus:BAAANQADCgMIAwAAAA==.',
Ti='Ticebane:BAABNQAECn8XAAIhAAgKkQsWZQB8AQAhAAgKkQsWZQB8AQAAAA==.Tichus:BAAANQAECgEIAQAAAA==.Tidusdruo:BAAANQAECgIIAgABNQAECgQIDAAFAAAAAA==.Tidusmonk:BAAANQADCgYIDAABNQAECgQIDAAFAAAAAA==.Tiduspullo:BAAANQAECgQIBwABNQAECgQIDAAFAAAAAA==.Tinafay:BAAANQAECgEIAwAAAA==.Titanbeard:BAAANQADCggIGAAAAA==.Titor:BAABNQAECn82AAMkAAgK5hBsEwCqAQAkAAgK5hBsEwCqAQAlAAIKKALINwBQAAAAAA==.Tituspullo:BAAANQAECgQIDAAAAA==.',
To='Tock:BAAANQAECgEIAQAAAA==.Tolduan:BAABNQAECn8hAAMZAAgK+wodeQALAQAZAAgK+wodeQALAQAfAAUKAARuLQCRAAAAAA==.Totemik:BAAANQADCgUIBQAAAA==.Toughturkey:BAAANQADCgEIAQABNQAECgYIDwAFAAAAAA==.',
Tr='Tricarnetry:BAABNQAECn87AAICAAoK7Q7idQDPAQACAAoK7Q7idQDPAQAAAA==.Tricarnity:BAAANQAECgUIEgABNQAECgoKOwACAO0OAA==.Trucknôrris:BAAANQADCgUIBwAAAA==.Trîela:BAABNQAECn8jAAILAAoKsAlmLgB6AQALAAoKsAlmLgB6AQAAAA==.',
Ul='Ulfer:BAAANQADCgYIBgABNQAECggIGwAhAGAfAA==.',
Um='Um:BAAANQAFFAEIAgAAAA==.',
Va='Valac:BAAANQAECgEIAQAAAA==.',
Ve='Veganwolf:BAAANQADCgMIAwAAAA==.Verakis:BAABNQAECn9FAAIKAAoKNhGODgC2AQAKAAoKNhGODgC2AQAAAA==.Verndarí:BAABNQAECn9AAAIcAAoKiQ+VKQCmAQAcAAoKiQ+VKQCmAQAAAA==.Verudora:BAAANQAECgcIEgAAAA==.',
Vi='Vishas:BAAANQAECgQICgAAAA==.',
Vo='Vortheus:BAAANQAECgcIEgAAAA==.Votollis:BAAANQAECgEIAQAAAA==.',
Vr='Vrack:BAAANQADCgQIBAAAAA==.',
Wa='Warhowl:BAAANQABCggIDgAAAA==.Warlanen:BAAANQAECgIIAwAAAA==.',
Wi='Willbur:BAABNQAECn9JAAIIAAoK4BH+VAAEAgAIAAoK4BH+VAAEAgAAAA==.',
Wu='Wurthwhile:BAAANQADCgcIEQAAAA==.',
Wy='Wyndywalker:BAAANQAECgYIEQAAAA==.',
Xa='Xayvior:BAABNQAECn8YAAIDAAoKnQ9+PwAmAgADAAoKnQ9+PwAmAgAAAA==.',
Xi='Xinnuo:BAAANQADCggIEAAAAA==.',
Za='Zamønk:BAAANQAECgUICQAAAA==.',
Ze='Zeigfeld:BAAANQAECgIIAgAAAA==.',
Zi='Ziarra:BAAANQAECgEIAQABNQAECgQIBwAFAAAAAA==.Zimzy:BAAANQAECgEIAQAAAA==.',
Zo='Zok:BAABNQAECn8kAAIJAAkKRg4hWADjAQAJAAkKRg4hWADjAQAAAA==.',
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
