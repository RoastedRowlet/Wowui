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
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aadeon:BAAANQADCgEIAQAAAA==.',
Ac='Acefu:BAABNQAECn8oAAIBAAcKLSB7GACDAgABAAcKLSB7GACDAgAAAA==.Aceo:BAAANQADCgYIDwABNQAECgoKRAACAHoPAA==.Acornella:BAABNQAECn8ZAAMDAAkKoRJCUAAzAgADAAkKoRJCUAAzAgAEAAIKABACawBXAAABNQAFFAEIAQAFAAAAAA==.Acornkei:BAAANQAFFAEIAQAAAA==.',
Ad='Adonsia:BAAANQADCgQIBAAAAA==.Adreva:BAABNQAECn8iAAQGAAoK4B5WEgApAwAGAAoK4B5WEgApAwAHAAQKKAIFWwBwAAACAAIK0RDGcwFpAAAAAA==.',
Ae='Aelana:BAAANQADCgQIBAAAAA==.Aendor:BAAANQAECgEIAQABNQAFFAgIEAAIAM8OAA==.Aerea:BAAANQAECgEIAgABNQAECgkJJwAJACoVAA==.Aevastraa:BAAANQADCgEIAQABNQAECgoKSwAKADsRAA==.',
Ai='Ailanthus:BAABNQAECn8rAAQLAAoKLQxeMgB4AQALAAoK1ApeMgB4AQAMAAUKMQ76IAANAQANAAIKKAU2bwBJAAAAAA==.',
Al='Albinophil:BAAANQADCgIIAgABNQAECgYIDAAFAAAAAA==.Aleyah:BAAANQAECggIEQAAAA==.Alloisaber:BAAANQAECgQIBQAAAA==.Alunne:BAAANQAECgIIAgAAAA==.',
Am='Amna:BAAANQAECgUIDAAAAA==.',
An='Andrelsia:BAAANQAECgIIAgAAAA==.Andrilla:BAAANQADCgYJDAAAAA==.Ankeseth:BAAANQADCggJDQAAAA==.',
Ar='Aracelis:BAAANQAECgEIAQAAAA==.Araxiel:BAAANQAECgcICAAAAA==.Archangël:BAAANQAECgEIAQAAAA==.Arkenos:BAAANQAECgIIAgAAAA==.Arén:BAABNQAECn85AAMOAAkKPiFuFQBxAgAOAAkKPiFuFQBxAgAPAAYKshmDOACAAQAAAA==.',
As='Ashenshugär:BAAANQAECgMIBAAAAA==.Aszian:BAAANQABCgcICgAAAA==.Aszun:BAABNQAECn8lAAIQAAcKyxBxoADFAQAQAAcKyxBxoADFAQAAAA==.',
At='Atractiva:BAABNQAECn8rAAMRAAoKMwgoEwB1AQARAAoK3AcoEwB1AQASAAgKzQRiBABoAQAAAA==.',
Au='Augment:BAAANQADCggIFQABNQAECgoKRAACAHoPAA==.Aura:BAAANQABCgUIBwAAAA==.',
Az='Azmar:BAAANQADCgIIAgAAAA==.Azuri:BAABNQAECn8VAAIKAAYKnAYnLQCbAAAKAAYKnAYnLQCbAAAAAA==.',
Ba='Balain:BAABNQAECn8nAAMJAAkKKhXzpADAAQAJAAkKKhXzpADAAQAKAAUKOwc/LQCaAAAAAA==.Barbiejoe:BAAANQADCgYIBgAAAA==.',
Be='Bear:BAAANQAECgYICwAAAA==.Beardchi:BAAANQADCgEIAQAAAA==.Bearzerk:BAABNQAECn87AAITAAoK3hCrCwDPAQATAAoK3hCrCwDPAQAAAA==.Benathar:BAABNQAECn8VAAIIAAYKhQaUCgGjAAAIAAYKhQaUCgGjAAAAAA==.Bethela:BAAANQAECgQIBAABNQAECgcIJQAQAMsQAA==.',
Bi='Birgir:BAAANQAECgQIBAABNQAECgkJJAAUALwZAA==.',
Bl='Blackgrim:BAAANQADCgYIDgAAAA==.Blackmagék:BAAANQABCgIIAgAAAA==.Bladestormer:BAAANQADCgEIAQABNQAECgoKRAACAHoPAA==.Blaston:BAABNQAECn8hAAMDAAgKvBbTVgDhAQADAAcKURjTVgDhAQAVAAYKUQmVEgD+AAAAAA==.Blightbeard:BAAANQADCggIDgAAAA==.Bloodthorn:BAABNQAECn8vAAQWAAkKyAhKagBsAQAWAAkKyAhKagBsAQAXAAMKFQRmSABvAAAYAAIKPAEGHQArAAAAAA==.',
Bo='Boomnescient:BAAANQADCgYICwAAAA==.Bottomdps:BAABNQAECn8xAAIZAAoKnBskJAD1AgAZAAoKnBskJAD1AgAAAA==.',
Br='Bramis:BAAANQADCggIDQAAAA==.Branor:BAAANQAECgMIAwAAAA==.Bransonian:BAAANQADCgQIBgAAAA==.Brantu:BAABNQAECn8lAAMaAAcKjARTTgCUAAAbAAcKjAQ54QAHAQAaAAUKrQFTTgCUAAAAAA==.Braultus:BAABNQAECn8fAAIcAAgKhxnRNgAvAgAcAAgKhxnRNgAvAgAAAA==.Bravehearth:BAAANQADCgEIAQAAAA==.Breuddwydwr:BAAANQADCgEIAQAAAA==.Brewtality:BAABNQAECn8VAAIBAAgKPQlMNAD9AAABAAgKPQlMNAD9AAAAAA==.Breyastrasza:BAAANQADCggIIAAAAA==.Briarthornz:BAABNQAECn8UAAIQAAoKihSRTAA2AgAQAAoKihSRTAA2AgAAAA==.',
Ca='Caanu:BAACNQAFFH8QAAIIAAgKzw4aDADAAQAIAAgKzw4aDADAAQA1AAQKf0YAAggACgqwIhkTAP8CAAgACgqwIhkTAP8CAAAA.Calydonia:BAAANQAECgIIAwAAAA==.',
Ce='Celdiseth:BAAANQADCggICwAAAA==.Cerdwin:BAAANQAECggIEwABNQAECgoKSgANAGsVAA==.',
Ch='Charferad:BAAANQAECgIIAgAAAA==.Chatter:BAAANQADCgcICAAAAA==.Cheeseydeath:BAEANQAECgMIAwAAAA==.Chibeard:BAABNQAECn8VAAIdAAYK7xyiEAAbAQAdAAYK7xyiEAAbAQAAAA==.Chihîro:BAAANQAECgQIBAAAAA==.Chungfoo:BAAANQAECggICAAAAA==.',
Cl='Clevercrane:BAAANQAECgMIAgABNQAECgkJIwAXAKkhAA==.',
Co='Coolbro:BAAANQADCgcICAABNQAECggIBgAFAAAAAA==.Corialis:BAABNQAECn8zAAMeAAoKhBOpPgAaAgAeAAoKhBOpPgAaAgAZAAYKKguBrAA6AQAAAA==.',
Cr='Crom:BAABNQAECn9DAAIfAAoKQBGnEAALAgAfAAoKQBGnEAALAgAAAA==.Crosis:BAAANQADCgYIBwAAAA==.Crying:BAAANQAECgUIEgAAAA==.',
Cy='Cyn:BAAANQADCgQIBgAAAA==.',
Da='Dandarred:BAABNQAECn82AAMGAAoKAwwTlQBhAQAGAAgKtQkTlQBhAQACAAkKUwmCyABEAQAAAA==.Dantey:BAAANQADCggIGwABNQAECgoKRAACAHoPAA==.Darkwyn:BAAANQADCgUIBQAAAA==.Dawne:BAABNQAECn8YAAIGAAoKLRr3MQCdAgAGAAoKLRr3MQCdAgAAAA==.Dazanna:BAABNQAECn8sAAMGAAoKDhSFTgAwAgAGAAoKDhSFTgAwAgACAAEKAACNpQE0AAAAAA==.Dazjaxx:BAAANQABCgYICQAAAA==.Dazre:BAAANQAECgIIAgAAAA==.',
De='Deeminor:BAAANQADCgIJAgAAAA==.Demeisen:BAABNQAECn84AAIOAAkKJxSmLQCnAQAOAAkKJxSmLQCnAQAAAA==.Demonizerr:BAAANQAECgEIAQABNQAECgoKRAACAHoPAA==.',
Di='Digor:BAAANQAECgIIAgABNQAFFAEIAQAFAAAAAA==.Diksensei:BAAANQAECgIIAwAAAA==.Diod:BAAANQAECgUIEgAAAA==.',
Dr='Dracomage:BAAANQADCgQIBwAAAA==.Dracotincan:BAAANQADCgIIAgAAAA==.Draegis:BAAANQABCgIIAgAAAA==.Dragyns:BAABNQAECn8hAAIXAAkKJiDoFQDNAgAXAAkKJiDoFQDNAgAAAA==.Dragynslance:BAAANQADCggIDAABNQAECgkJIQAXACYgAA==.Drayper:BAABNQAECn8jAAMDAAkKKBbeSABLAgADAAkKKBbeSABLAgAVAAEKug88KQAyAAAAAA==.',
Du='Dunbarke:BAABNQAECn8kAAQUAAkKvBnFBwAcAgAUAAgKFhrFBwAcAgAbAAUKkBdy1AAhAQAaAAIKXQtETACaAAAAAA==.',
['Dê']='Dêadlights:BAAANQAECgUIEgAAAA==.',
El='Elash:BAAANQAECgMIBAAAAA==.Elbrimar:BAAANQABCgQIBQAAAA==.Elendrisa:BAAANQAECgYIDgAAAA==.Elisoria:BAAANQAECgYICgAAAA==.Ellayssa:BAAANQAECgEIAQAAAA==.Elliwynd:BAABNQAECn80AAINAAoKtBgLFwBkAgANAAoKtBgLFwBkAgAAAA==.Elway:BAAANQADCgIIAgAAAA==.',
Em='Embermourne:BAAANQADCggICAAAAA==.',
Er='Eraela:BAAANQADCggICAAAAA==.Erinnys:BAABNQAECn82AAIOAAoKCgouNwBrAQAOAAoKCgouNwBrAQAAAA==.',
Es='Esoteria:BAABNQAECn85AAIIAAoKDhp0SwAsAgAIAAoKDhp0SwAsAgAAAA==.',
Eu='Eufemia:BAAANQAECgYIBgAAAA==.',
Ev='Evonnya:BAAANQADCggIDgAAAA==.',
Fe='Felfar:BAAANQADCggIDAABNQAECgUICQAFAAAAAA==.',
Fi='Finalomega:BAABNQAECn8WAAIcAAcKBgyjVQDnAAAcAAcKBgyjVQDnAAAAAA==.Finnshot:BAABNQAECn8aAAIQAAYKGxGY1gBTAQAQAAYKGxGY1gBTAQAAAA==.Finrod:BAAANQAECgUIBQAAAA==.',
Fl='Flaminfalcon:BAAANQAECgEIAgABNQAECgkJIwAXAKkhAA==.',
Fo='Foulmilk:BAAANQADCgEIAQAAAA==.Foxflame:BAABNQAECn9KAAMNAAoKaxUWGwAzAgANAAoKaxUWGwAzAgALAAQKTgrGaQCCAAAAAA==.',
Fr='Franzen:BAAANQADCggIIwAAAA==.Frawd:BAAANQADCgcIBwABNQAFFAUICQAIAEcdAA==.Freyalys:BAAANQADCggIJAAAAA==.Frôstblade:BAAANQABCgYIBgAAAA==.',
Fu='Fulanita:BAAANQADCgcIEwAAAA==.Fullmoonpo:BAAANQADCgMIAwAAAA==.Furyaid:BAABNQAECn9EAAIJAAoKRCKGDwAbAwAJAAoKRCKGDwAbAwAAAA==.',
Ga='Galadrael:BAAANQAECgQJBAAAAA==.Gaz:BAAANQADCgQIBAAAAA==.',
Ge='Genkithered:BAABNQAECn8ZAAIeAAkKjhbtSADvAQAeAAkKjhbtSADvAQAAAA==.',
Gl='Gloomy:BAAANQADCgEIAQAAAA==.',
Go='Gourak:BAAANQAECgUIEQAAAA==.',
Gr='Graleywrld:BAAANQAECgMIAwAAAA==.Grapejuice:BAABNQAECn8aAAMGAAoKNRr4FwD3AgAGAAoKNRr4FwD3AgACAAIK2gaomwEzAAAAAA==.Gravemarks:BAAANQADCgYIBAAAAA==.Grimhorn:BAABNQAECn8kAAILAAcKGAY4VgDGAAALAAcKGAY4VgDGAAAAAA==.Grimlie:BAAANQADCgYIDgABNQAECgcIJQAaAIwEAA==.',
Gu='Guaritrice:BAAANQAECgEIAQAAAA==.',
Gw='Gwindor:BAAANQAECgIIAgAAAA==.',
['Gö']='Gödwyn:BAAANQAECgIIAQABNQAECgQICgAFAAAAAA==.',
Ha='Hairyrage:BAAANQABCgQICAAAAA==.Hale:BAAANQADCgEIAgAAAA==.Hatterus:BAABNQAECn9AAAICAAoKlAlXrAB3AQACAAoKlAlXrAB3AQAAAA==.',
He='Healzey:BAAANQADCgUIBAAAAA==.Heavygator:BAAANQAECgIIAgAAAA==.Hetairoi:BAAANQAECgYIDAAAAA==.',
Hi='Hillbroken:BAABNQAECn9aAAIgAAoKnhuTGQB9AgAgAAoKnhuTGQB9AgAAAA==.',
Ho='Holynez:BAAANQAECgYIAQAAAA==.Hosmer:BAAANQADCgQIBAAAAA==.',
Hu='Huan:BAAANQAECgMIBAAAAA==.Huntertidus:BAAANQAECgYICgABNQAECgYIEAAFAAAAAA==.Huntrix:BAAANQAECgIIAgAAAA==.',
Hy='Hyrlis:BAAANQAECgEIAQAAAA==.',
['Hà']='Hànks:BAAANQAECgUICwAAAA==.',
Ib='Ibíng:BAAANQAECggIDwAAAA==.',
Ic='Iceatron:BAAANQADCgQICAABNQAECgoKRAACAHoPAA==.',
In='Invariance:BAEANQADCgUIBQABNQAECgUIBQAFAAAAAA==.Inèvitable:BAABNQAECn9ZAAIhAAoKKR8gDAC1AgAhAAoKKR8gDAC1AgAAAA==.',
Ir='Ironphant:BAABNQAECn8jAAICAAoKhQqw2gBmAQACAAoKhQqw2gBmAQAAAA==.',
Is='Ishmethit:BAAANQADCgYIBgAAAA==.Istara:BAAANQADCgcIFQAAAA==.',
Je='Jebib:BAAANQAECgYIBgABNQAFFAkJJgANAPYjAA==.Jeod:BAAANQAECgIIAgAAAA==.Jettonk:BAAANQABCgIIAgABNQAECgcIJQAaAIwEAA==.',
Ji='Jirachi:BAAANQADCgEIAQAAAA==.',
Jo='Jolty:BAABNQAECn8lAAMhAAkKiiJ4FAAVAwAhAAkKiiJ4FAAVAwAcAAQKGhmshADqAAAAAA==.',
Ju='Junghoulson:BAAANQAECgUIBQAAAA==.',
['Jð']='Jð:BAAANQAECggICQAAAA==.',
Ka='Kaiou:BAAANQADCgUICwAAAA==.Kantor:BAABNQAECn9bAAIDAAoKKQ7wTQABAgADAAoKKQ7wTQABAgAAAA==.Karboomkin:BAAANQAECgIIBAABNQAFFAYIDQAQAOUVAA==.Kasenko:BAAANQADCggICAABNQAECgcIGgAiAMsZAA==.Kasryna:BAABNQAECn8aAAIiAAcKyxkWIgBxAQAiAAcKyxkWIgBxAQAAAA==.',
Ke='Kelmair:BAAANQADCgYIBgAAAA==.Keta:BAAANQAECgIIAQAAAA==.Ketameanie:BAABNQAECn9BAAIPAAoKjhysDgBqAgAPAAoKjhysDgBqAgAAAA==.',
Kh='Khadguy:BAABNQAECn8kAAIfAAkKjRlGEABkAgAfAAkKjRlGEABkAgAAAA==.',
Km='Kmazing:BAAANQADCggJFAABNQAECgoKOQAIAA4aAA==.',
Kn='Knikku:BAAANQADCggICAAAAA==.',
Ko='Konoha:BAABNQAECn81AAMEAAoKwh6rDgBuAgAEAAoKwh6rDgBuAgADAAIKtRst8QBRAAAAAA==.Koven:BAAANQADCggIJAAAAA==.',
Ku='Kultag:BAABNQAECn8rAAICAAoKVBJ/eADdAQACAAoKVBJ/eADdAQAAAA==.Kuun:BAABNQAECn8bAAIZAAkK5QlMmgBjAQAZAAkK5QlMmgBjAQAAAA==.',
Ky='Kyaw:BAAANQAECgUIDQAAAA==.Kynzo:BAAANQAECgQICAAAAA==.',
La='Laelah:BAAANQABCgQIBQAAAA==.Lasmína:BAAANQADCgQIBwAAAA==.Laykeezenith:BAACNQAFFH8OAAMQAAcKxiPrAgA/AgAQAAYKXiPrAgA/AgAjAAQKKx3jCwCAAQA1AAQKfygAAyMACgrJImIZAIwCACMACgpQHWIZAIwCABAABwrfIER4AB8CAAAA.Lazuli:BAACNQAFFH8FAAMeAAQKRg/hJQB3AAAeAAIKnwbhJQB3AAAZAAMKSARDLAAuAAA1AAQKf00AAxkACgojHt8gAG4CABkACgojHt8gAG4CAB4ACAqJCUZzAFkBAAAA.',
Le='Lehann:BAABNQAECn8sAAIQAAoKiA2IYgABAgAQAAoKiA2IYgABAgAAAA==.',
Li='Littlebitty:BAABNQAECn8hAAIWAAoKbwWmgAAmAQAWAAoKbwWmgAAmAQAAAA==.',
Lo='Lockatron:BAAANQAECgEIAQABNQAECgoKRAACAHoPAA==.Lostsonofpo:BAAANQAECgEIAQAAAA==.Lothryn:BAABNQAECn81AAMGAAoKOQ1UTQDeAQAGAAoKOQ1UTQDeAQACAAkKPQu5vwCdAQAAAA==.',
Lp='Lp:BAABNQAECn8bAAIPAAoKGxzgFAAZAgAPAAoKGxzgFAAZAgAAAA==.',
Lu='Lunariah:BAAANQADCgIIAgAAAA==.',
Ly='Lyllien:BAAANQAECgIIAgAAAA==.',
Ma='Marenus:BAABNQAECn9KAAIQAAoKWBAKUwAmAgAQAAoKWBAKUwAmAgAAAA==.Marten:BAAANQABCgIIAgAAAA==.Masume:BAAANQAECgUICQAAAA==.Maély:BAAANQADCgUIBQAAAA==.',
Me='Mechadead:BAABNQAECn8bAAIgAAgKPwNdhACiAAAgAAgKPwNdhACiAAABNQAECgoKRAACAHoPAA==.Megaopto:BAABNQAECn8wAAIcAAcKnRbRMACJAQAcAAcKnRbRMACJAQAAAA==.Meowmix:BAAANQADCgMICAAAAA==.Methanny:BAAANQADCgQIBAAAAA==.',
Mi='Mizmonk:BAAANQADCggICAAAAA==.',
Mj='Mjölnir:BAABNQAECn9GAAICAAoKxBqBRgBWAgACAAoKxBqBRgBWAgAAAA==.',
Mo='Momentum:BAAANQAECgIIAgAAAA==.',
Ms='Msdiiva:BAAANQAECgMIBAAAAA==.',
Mu='Mushuu:BAAANQADCgYIDAAAAA==.',
My='Myrwynn:BAAANQAECggICQABNQAECgoKOgAQAEcXAA==.',
['Mô']='Môjô:BAAANQABCgUIBQAAAA==.',
Na='Nahion:BAAANQAECgIIAgAAAA==.Nashira:BAABNQAECn8wAAIQAAoKWxP4eAAdAgAQAAoKWxP4eAAdAgAAAA==.',
Ne='Nemasus:BAABNQAECn8cAAQNAAYKPxjiQwANAQANAAQKCxjiQwANAQALAAYKCxRVWAC+AAAiAAUKMAOaRQCdAAAAAA==.Nepolian:BAAANQABCgYICAAAAA==.Neraine:BAAANQAECgUIDgAAAA==.',
Ni='Ninjahh:BAABNQAECn83AAIWAAoK2hOkPAAJAgAWAAoK2hOkPAAJAgAAAA==.Nioshei:BAABNQAECn9LAAMeAAoKiRnqIwCkAgAeAAoKiRnqIwCkAgAZAAYKBAisjgDuAAAAAA==.Nisara:BAAANQAECgQIBAABNQAECgoKVwAeAO0hAA==.',
No='Nochmuerta:BAAANQADCgUIBQABNQADCgcIBwAFAAAAAA==.Noctyrna:BAAANQADCgEIAQAAAA==.Nogrid:BAABNQAECn9bAAIHAAoKwSHcBQD9AgAHAAoKwSHcBQD9AgAAAA==.Noxstantine:BAAANQADCgQIBgAAAA==.',
Nu='Nuthar:BAABNQAECn85AAICAAoK7R3aNACQAgACAAoK7R3aNACQAgAAAA==.',
Ny='Nyrrhi:BAAANQAECggIDgAAAA==.',
Ol='Oldeis:BAAANQADCgYJBgAAAA==.',
Or='Orneryosprey:BAAANQAECgQIBwABNQAECgYIDAAFAAAAAA==.',
Ou='Ouroborös:BAABNQAECn8qAAIQAAoKbhEGZQD7AQAQAAoKbhEGZQD7AQAAAA==.',
Oy='Oyashiro:BAAANQAECggIDAAAAA==.',
Pa='Pamburu:BAABNQAECn9JAAIQAAoK1RV2QQBSAgAQAAoK1RV2QQBSAgAAAA==.Papagrape:BAABNQAECn8yAAMkAAkKtRtRDABdAgAkAAkKtRtRDABdAgAlAAUKKBKFGACzAAAAAA==.Paradiselost:BAAANQADCgQIBwAAAA==.Parzivàl:BAAANQAECgIIAQAAAA==.Paxa:BAABNQAECn8tAAMDAAoKQRdRMwBzAgADAAoKQRdRMwBzAgAEAAIK4ArtaQBaAAAAAA==.',
Pe='Peekabu:BAAANQADCgcIDAABNQAECgoKRAACAHoPAA==.Pennelo:BAAANQADCgQIBQAAAA==.Persayis:BAAANQAECgIIAgAAAA==.',
Ph='Phoebel:BAAANQADCgIJAgABNQAECgcIJQAQAMsQAA==.',
Pi='Pineappledk:BAEANQADCggIEgABNQAECgQIBgAFAAAAAA==.Pineapplepn:BAEANQAECgQIBgAAAA==.Pineapplle:BAEANQAECgQIBgABNQAECgQIBgAFAAAAAA==.',
Pl='Plazelly:BAAANQADCgcIDAAAAA==.',
Po='Podnov:BAABNQAECn8yAAIjAAoKPRw9FwCgAgAjAAoKPRw9FwCgAgAAAA==.Pollyanna:BAAANQABCgYICAAAAA==.',
Pr='Prztrump:BAAANQAECggIBgAAAA==.',
Py='Pyrista:BAAANQAECggICwAAAA==.',
Qa='Qahili:BAAANQADCgUIBgAAAA==.Qang:BAAANQAECgIIAgAAAA==.',
Ra='Radiante:BAACNQAFFH8IAAIGAAUKmgO1EQBHAQAGAAUKmgO1EQBHAQA1AAQKfyAAAwYACQrwHD0dAP4CAAYACQrwHD0dAP4CAAIAAQodA27MASEAAAAA.Rageadin:BAAANQABCgcIBQAAAA==.Raion:BAABNQAECn81AAIHAAoKxx8XDABxAgAHAAoKxx8XDABxAgAAAA==.Raithis:BAACNQAFFH8UAAIQAAcKQR3zBACwAQAQAAcKQR3zBACwAQA1AAQKf1EAAhAACgrkJdYDAHMDABAACgrkJdYDAHMDAAAA.Raito:BAAANQADCgYIBgAAAA==.Ralzin:BAAANQADCgEIAQAAAA==.Ramhadin:BAEANQADCgcIHAABNQAECgoKPgAEAHIaAA==.Randel:BAAANQAECggIBgAAAA==.Raucousrhea:BAAANQABCgIIAgAAAA==.Rav:BAAANQAECgYICwAAAA==.',
Re='Redvelvet:BAABNQAECn8wAAImAAoKZhGGHAC8AQAmAAoKZhGGHAC8AQAAAA==.Resisting:BAAANQAECgYIDAABNQAECgoKGwAPABscAA==.Reznal:BAABNQAECn8hAAMZAAoKhxyENwCYAgAZAAoKhxyENwCYAgAeAAUKuB6AeACiAQABNQAFFAIIBQAIADwTAA==.',
Ro='Romam:BAAANQAECgIIAgAAAA==.',
Ry='Rydran:BAAANQADCgIIAgAAAA==.Rykria:BAAANQADCggIJQAAAA==.',
Sa='Sableanne:BAABNQAECn9HAAMeAAoKbAjojgBjAQAeAAoKbAjojgBjAQAZAAYKjgTAtACfAAAAAA==.Saedirine:BAAANQADCgYIDAAAAA==.Saggi:BAAANQAECggIDAAAAA==.',
Se='Secksiecutie:BAABNQAECn80AAIgAAoKzBFbOAC/AQAgAAoKzBFbOAC/AQAAAA==.Secondwall:BAAANQADCgYIBgAAAA==.Selma:BAAANQABCgMIAwAAAA==.Serinar:BAABNQAECn8ZAAICAAgK5hNNqADPAQACAAgK5hNNqADPAQAAAA==.',
Sh='Shadowbolt:BAAANQABCgQIBgAAAA==.Shoorah:BAAANQADCgEIAQAAAA==.',
Si='Siako:BAABNQAECn8WAAMSAAoKlgaOBABcAQAIAAoKHQRxFgFnAQASAAcKFwiOBABcAQAAAA==.Silversaiyan:BAABNQAECn9JAAITAAoKoyC+AgD3AgATAAoKoyC+AgD3AgAAAA==.Sirlink:BAAANQABCgIIAgAAAA==.',
Sl='Slade:BAABNQAECn9lAAMWAAoKkCIvCwAdAwAWAAoKkCIvCwAdAwAXAAYKhRdhIAAnAQAAAA==.Sliyce:BAAANQADCgEIAQAAAA==.',
Sm='Smorc:BAAANQAECgQIBwAAAA==.',
Sn='Sneakyclubs:BAAANQADCgUICAAAAA==.Snowfawn:BAAANQAECgUICwABNQAECggIGQAQAE0MAA==.',
So='Sofedan:BAABNQAECn9TAAIjAAoKugfcHQCIAQAjAAoKugfcHQCIAQAAAA==.Sorgath:BAAANQAECgIIAgAAAA==.Soriel:BAABNQAECn9LAAIdAAoKdRRsCADQAQAdAAoKdRRsCADQAQAAAA==.Sorokwa:BAABNQAECn8uAAIhAAoKcAQ/hwAEAQAhAAoKcAQ/hwAEAQAAAA==.',
Sq='Squeeze:BAAANQAECgUJCwAAAA==.',
St='Stillwater:BAABNQAECn80AAQfAAoKJQwOFgC0AQAfAAoKJQwOFgC0AQAZAAMKygONCAF7AAAeAAIK6wOk6wBGAAAAAA==.Strathius:BAAANQAECgIIAgAAAA==.',
Su='Suriden:BAAANQADCggICQAAAA==.',
Sw='Swagidan:BAABNQAECn9LAAIOAAoK/BlvGgBAAgAOAAoK/BlvGgBAAgAAAA==.Sweaterpally:BAAANQADCgUICQAAAA==.Swiftera:BAAANQAECgIIAgAAAA==.Swiftlier:BAAANQAECgcICAABNQAECgoKSQAcAKkRAA==.',
Sy='Sylphrène:BAABNQAECn8sAAMPAAoKrQP8MwD6AAAPAAoKrQP8MwD6AAAOAAMKUQHcjQBAAAAAAA==.',
Ta='Taghman:BAAANQAECgMICAABNQAECgoKZQAWAJAiAA==.Taleth:BAAANQAECgMIBAABNQAECgYIFQAKAJwGAA==.Tandrana:BAAANQAECgEIAQAAAA==.Targanisha:BAAANQADCggICAABNQAECgoKMQAZAJwbAA==.Targdh:BAABNQAECn9fAAIPAAoKqSBlCgCtAgAPAAoKqSBlCgCtAgABNQAECgoKMQAZAJwbAA==.Targforeva:BAAANQAECgQIBgABNQAECgoKMQAZAJwbAA==.Targthesting:BAAANQAECggIDQABNQAECgoKMQAZAJwbAA==.',
Te='Terminus:BAAANQADCgMIAwAAAA==.',
Ti='Ticebane:BAABNQAECn8XAAIhAAgKkQsWZQB8AQAhAAgKkQsWZQB8AQAAAA==.Tichus:BAAANQAECgUIBQAAAA==.Tidusdruo:BAAANQAECgIIAgABNQAECgYIEAAFAAAAAA==.Tidusmonk:BAAANQAECgMIAwABNQAECgYIEAAFAAAAAA==.Tiduspullo:BAAANQAECgYIEAAAAA==.Tinafay:BAAANQAECgEIAQAAAA==.Titanbeard:BAAANQADCggIGAAAAA==.Titor:BAABNQAECn88AAMkAAgK5hDhFACpAQAkAAgK5hDhFACpAQAlAAIKKALINwBQAAAAAA==.Tituspullo:BAAANQAECgUIDQABNQAECgYIEAAFAAAAAA==.',
To='Tock:BAAANQAECgEIAQAAAA==.Tolduan:BAABNQAECn8iAAMZAAgK+wrkgQAMAQAZAAgK+wrkgQAMAQAfAAUKAARuLQCRAAAAAA==.Totemik:BAAANQADCgUIBgAAAA==.Toughturkey:BAAANQADCgEIAQABNQAECgYIDAAFAAAAAA==.',
Tr='Tricarnetry:BAABNQAECn9EAAICAAoKeg+8ewDWAQACAAoKeg+8ewDWAQAAAA==.Tricarnity:BAABNQAECn8UAAIBAAYKKQPrSwB0AAABAAYKKQPrSwB0AAABNQAECgoKRAACAHoPAA==.Trucknôrris:BAAANQADCgUIBwAAAA==.Trîela:BAABNQAECn8jAAILAAoKsAkoMgB5AQALAAoKsAkoMgB5AQAAAA==.',
Ul='Ulfer:BAAANQADCgYIBgABNQAECggIGwAhAGAfAA==.',
Um='Um:BAAANQAFFAEIAgAAAA==.',
Va='Valac:BAAANQADCgUIBQAAAA==.',
Ve='Veganwolf:BAAANQADCgMIAwAAAA==.Verakis:BAABNQAECn9LAAIKAAoKOxGbDwC9AQAKAAoKOxGbDwC9AQAAAA==.Verndarí:BAABNQAECn9JAAIcAAoKqREbJgDLAQAcAAoKqREbJgDLAQAAAA==.Verudora:BAABNQAECn8cAAMkAAoKchZUCQCrAgAkAAoKchZUCQCrAgAlAAEKAAC/QAAqAAAAAA==.',
Vi='Vishas:BAAANQAECgQIBwAAAA==.',
Vo='Vortheus:BAABNQAECn8WAAIfAAoKfgxZEwDhAQAfAAoKfgxZEwDhAQAAAA==.Votollis:BAAANQAECgEIAQAAAA==.',
Vr='Vrack:BAAANQADCgQIBAAAAA==.',
Wa='Warhowl:BAAANQABCggIDgAAAA==.Warlanen:BAAANQAECgIIAgAAAA==.',
Wi='Willbur:BAABNQAECn9SAAIIAAoKkBPpTwAgAgAIAAoKkBPpTwAgAgAAAA==.',
Wu='Wurthwhile:BAAANQADCgcIEQAAAA==.',
Wy='Wyndywalker:BAAANQAECgYIEAAAAA==.',
Xa='Xayvior:BAABNQAECn8gAAIDAAoKBROyOgBQAgADAAoKBROyOgBQAgAAAA==.',
Xi='Xinnou:BAAANQADCgIIAQAAAA==.Xinnuo:BAAANQADCggIEQAAAA==.',
Za='Zamønk:BAAANQAECgUICQAAAA==.',
Ze='Zeigfeld:BAAANQAECgIIAgAAAA==.',
Zi='Ziarra:BAAANQADCgYIBQABNQAECgQIBwAFAAAAAA==.Zimzy:BAAANQAECgEIAQAAAA==.',
Zo='Zok:BAABNQAECn8kAAIJAAkKRg6XXwDgAQAJAAkKRg6XXwDgAQAAAA==.',
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
