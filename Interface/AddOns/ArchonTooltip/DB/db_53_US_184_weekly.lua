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

local lookup = {'Monk-Windwalker','Paladin-Retribution','Priest-Holy','Priest-Shadow','Unknown-Unknown','Paladin-Holy','Paladin-Protection','Mage-Arcane','Warrior-Arms','Warrior-Protection','Druid-Feral','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Mage-Frost','Mage-Fire','Warrior-Fury','Warlock-Affliction','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','DeathKnight-Blood','Monk-Brewmaster','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Unholy','Druid-Guardian','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Acefu:BAABNQAECn8iAAIBAAcKLSB7GACDAgABAAcKLSB7GACDAgAAAA==.Aceo:BAAANQADCgYICwABNQAECgoKNAACAIkMAA==.Acornella:BAABNQAECn8ZAAMDAAkKoRJCUAAzAgADAAkKoRJCUAAzAgAEAAIKABACawBXAAABNQAFFAEIAQAFAAAAAA==.Acornkei:BAAANQAFFAEIAQAAAA==.',
Ad='Adonsia:BAAANQADCgQIBAAAAA==.Adreva:BAABNQAECn8iAAQGAAoK4B5MDABCAwAGAAoK4B5MDABCAwAHAAQKKAIFWwBwAAACAAIK0RDGcwFpAAAAAA==.',
Ae='Aelana:BAAANQADCgQIBAAAAA==.Aendor:BAAANQAECgEIAQABNQAFFAcIDwAIAAYQAA==.Aerea:BAAANQAECgEIAgABNQAECgkJJQAJAEEUAA==.Aevastraa:BAAANQADCgEIAQABNQAECgkJOwAKAPQPAA==.',
Ai='Ailanthus:BAABNQAECn8bAAQLAAgKagv6IAANAQALAAUKMQ76IAANAQAMAAUK5QRuiQCuAAANAAIKKAU2bwBJAAAAAA==.',
Al='Albinophil:BAAANQADCgIIAgABNQAECgYIDAAFAAAAAA==.Aleyah:BAAANQAECggIDQAAAA==.Alloisaber:BAAANQAECgQIBQAAAA==.Alunne:BAAANQAECgIIAgAAAA==.',
Am='Amna:BAAANQAECgUIDAAAAA==.',
An='Andrelsia:BAAANQAECgEIAQAAAA==.Andrilla:BAAANQADCgYJDAAAAA==.Ankeseth:BAAANQADCggJDQAAAA==.',
Ar='Aracelis:BAAANQAECgEIAQAAAA==.Araxiel:BAAANQAECgUIBQAAAA==.Archangël:BAAANQAECgEIAQAAAA==.Arkenos:BAAANQAECgIIAgAAAA==.Arén:BAABNQAECn85AAMOAAkKPiGWEAB8AgAOAAkKPiGWEAB8AgAPAAYKshmDOACAAQAAAA==.',
As='Ashenshugär:BAAANQAECgMIBAAAAA==.Aszian:BAAANQABCgcICgAAAA==.Aszun:BAABNQAECn8kAAIQAAcKyxBxoADFAQAQAAcKyxBxoADFAQAAAA==.',
At='Atractiva:BAABNQAECn8rAAMRAAoKMwgoEwB1AQARAAoK3AcoEwB1AQASAAgKzQRiBABoAQAAAA==.',
Au='Augment:BAAANQADCggIDAABNQAECgoKNAACAIkMAA==.Aura:BAAANQABCgUIBwAAAA==.',
Az='Azmar:BAAANQADCgIIAgAAAA==.Azuri:BAAANQAECgQICAAAAA==.',
Ba='Balain:BAABNQAECn8lAAMJAAkKQRTzpADAAQAJAAkKQRTzpADAAQAKAAUKOwf7JACfAAAAAA==.Barbiejoe:BAAANQADCgYIBgAAAA==.',
Be='Bear:BAAANQAECgUIBgAAAA==.Beardchi:BAAANQADCgEIAQAAAA==.Bearzerk:BAABNQAECn8tAAITAAkKwA+ADAB7AQATAAkKwA+ADAB7AQAAAA==.Benathar:BAABNQAECn8VAAIIAAYKhQaf7gCrAAAIAAYKhQaf7gCrAAAAAA==.Bethela:BAAANQABCgYIBgABNQAECgcIJAAQAMsQAA==.',
Bi='Birgir:BAAANQAECgQIBAABNQAECggIIQAUAMcZAA==.',
Bl='Blackmagék:BAAANQABCgIIAgAAAA==.Blaston:BAABNQAECn8gAAMDAAgKvBZHQwDzAQADAAcKURhHQwDzAQAVAAYKUQmVEgD+AAAAAA==.Blightbeard:BAAANQADCggIDgAAAA==.Bloodthorn:BAABNQAECn8oAAQWAAkKZQdaWwBKAQAWAAkKZQdaWwBKAQAXAAMKFQRLQwBxAAAYAAIKPAEGHQArAAAAAA==.',
Bo='Boomnescient:BAAANQADCgYICwAAAA==.Bottomdps:BAABNQAECn8xAAIZAAoKnBskJAD1AgAZAAoKnBskJAD1AgAAAA==.',
Br='Bramis:BAAANQADCggIDQAAAA==.Branor:BAAANQAECgIIAgAAAA==.Bransonian:BAAANQADCgQIBgAAAA==.Brantu:BAABNQAECn8kAAMaAAcKjARTTgCUAAAbAAcKjAQ54QAHAQAaAAUKrQFTTgCUAAAAAA==.Braultus:BAABNQAECn8fAAIcAAgKhxnRNgAvAgAcAAgKhxnRNgAvAgAAAA==.Bravehearth:BAAANQADCgEIAQAAAA==.Breuddwydwr:BAAANQADCgEIAQAAAA==.Brewtality:BAAANQAECgYIDAAAAA==.Breyastrasza:BAAANQADCgcIEAAAAA==.Briarthornz:BAAANQAECgcIDQAAAA==.',
Ca='Caanu:BAACNQAFFH8PAAIIAAcKBhDzCQCBAQAIAAcKBhDzCQCBAQA1AAQKf0AAAggACgpUIvYOAAMDAAgACgpUIvYOAAMDAAAA.Calydonia:BAAANQAECgIIAwAAAA==.',
Ce='Celdiseth:BAAANQADCggICwAAAA==.Cerdwin:BAAANQAECggIEwABNQAECgoKNwANAJ0TAA==.',
Ch='Charferad:BAAANQAECgIIAgAAAA==.Chatter:BAAANQADCgcICAAAAA==.Cheeseydeath:BAEANQAECgMIAwAAAA==.Chibeard:BAABNQAECn8VAAIdAAYK7xy6DQAeAQAdAAYK7xy6DQAeAQAAAA==.Chihîro:BAAANQAECgQIBAAAAA==.',
Cl='Clevercrane:BAAANQAECgMIAgAAAA==.',
Co='Coolbro:BAAANQADCgcICAAAAA==.Corialis:BAABNQAECn8uAAMeAAoKZRMrMgAkAgAeAAoKZRMrMgAkAgAZAAYKKguBrAA6AQAAAA==.',
Cr='Crom:BAABNQAECn81AAIfAAkK5xBsEQC+AQAfAAkK5xBsEQC+AQAAAA==.Crying:BAAANQAECgUIEgAAAA==.',
Cy='Cyn:BAAANQADCgQIBgAAAA==.',
Da='Dandarred:BAABNQAECn8zAAMGAAgKtQn2aQBGAQAGAAgKtQn2aQBGAQACAAcK+ggz2ADsAAAAAA==.Dantey:BAAANQADCggIFwABNQAECgoKNAACAIkMAA==.Darkwyn:BAAANQADCgUIBQAAAA==.Dawne:BAABNQAECn8YAAIGAAoKLRr3MQCdAgAGAAoKLRr3MQCdAgAAAA==.Dazanna:BAABNQAECn8qAAMGAAgKqBaFTgAwAgAGAAgKqBaFTgAwAgACAAEKAACNpQE0AAAAAA==.Dazjaxx:BAAANQABCgYICQAAAA==.Dazre:BAAANQAECgIIAgAAAA==.',
De='Deeminor:BAAANQADCgIJAgAAAA==.Demeisen:BAABNQAECn8tAAIOAAgKXBRFLQBqAQAOAAgKXBRFLQBqAQAAAA==.Demonizerr:BAAANQAECgEIAQABNQAECgoKNAACAIkMAA==.',
Di='Digor:BAAANQAECgIIAgABNQAFFAEIAQAFAAAAAA==.Diksensei:BAAANQAECgIIAwAAAA==.Diod:BAAANQAECgUIEgAAAA==.',
Dr='Dracomage:BAAANQADCgQIBwAAAA==.Dracotincan:BAAANQADCgIIAgAAAA==.Draegis:BAAANQABCgIIAgAAAA==.Dragyns:BAABNQAECn8hAAIXAAkKJiDoFQDNAgAXAAkKJiDoFQDNAgAAAA==.Dragynslance:BAAANQADCggIDAABNQAECgkJIQAXACYgAA==.Drayper:BAABNQAECn8jAAMDAAkKKBbeSABLAgADAAkKKBbeSABLAgAVAAEKug88KQAyAAAAAA==.',
Du='Dunbarke:BAABNQAECn8hAAQUAAgKxxnFBwAcAgAUAAgKxxnFBwAcAgAbAAQKiRdy1AAhAQAaAAIKXQtETACaAAAAAA==.',
['Dê']='Dêadlights:BAAANQAECgUIEgAAAA==.',
El='Elbrimar:BAAANQABCgQIBQAAAA==.Elendrisa:BAAANQAECgUIDgAAAA==.Elisoria:BAAANQAECgUICAAAAA==.Ellayssa:BAAANQAECgEIAQAAAA==.Elliwynd:BAABNQAECn8yAAINAAoKtBhlEQBqAgANAAoKtBhlEQBqAgAAAA==.Elway:BAAANQADCgIIAgAAAA==.',
Em='Embermourne:BAAANQADCggICAAAAA==.',
Er='Eraela:BAAANQADCggICAAAAA==.Erinnys:BAABNQAECn8mAAIOAAgKMQpkRQCbAQAOAAgKMQpkRQCbAQAAAA==.',
Es='Esoteria:BAABNQAECn83AAIIAAoKDhrEPQAwAgAIAAoKDhrEPQAwAgAAAA==.',
Eu='Eufemia:BAAANQAECgUIBQAAAA==.',
Ev='Evonnya:BAAANQADCggIDgAAAA==.',
Fe='Felfar:BAAANQADCggICwABNQAECgUICQAFAAAAAA==.',
Fi='Finalomega:BAABNQAECn8WAAIcAAcKBgw1SQDuAAAcAAcKBgw1SQDuAAAAAA==.Finnshot:BAAANQAECgQIDgAAAA==.Finrod:BAAANQAECgUIBQAAAA==.',
Fl='Flaminfalcon:BAAANQAECgEIAgABNQAECgMIAgAFAAAAAA==.',
Fo='Foulmilk:BAAANQADCgEIAQAAAA==.Foxflame:BAABNQAECn83AAMNAAoKnRNMIgAUAgANAAoKnRNMIgAUAgAMAAQKTgrYXACFAAAAAA==.',
Fr='Franzen:BAAANQADCgcIFQAAAA==.Frawd:BAAANQADCgcIBwABNQAFFAUICQAIAEcdAA==.Freyalys:BAAANQADCgcIFAAAAA==.Frôstblade:BAAANQABCgYIBgAAAA==.',
Fu='Fulanita:BAAANQADCgcIEwAAAA==.Fullmoonpo:BAAANQADCgMIAwAAAA==.Furyaid:BAABNQAECn80AAIJAAkKbiNiHgA+AwAJAAkKbiNiHgA+AwAAAA==.',
Ga='Galadrael:BAAANQAECgQJBAAAAA==.Gaz:BAAANQADCgQIBAAAAA==.',
Ge='Genkithered:BAABNQAECn8VAAIeAAYK5RuFcwCxAQAeAAYK5RuFcwCxAQAAAA==.',
Gl='Gloomy:BAAANQADCgEIAQAAAA==.',
Go='Gourak:BAAANQAECgUIEQAAAA==.',
Gr='Graleywrld:BAAANQADCgcIBwAAAA==.Grapejuice:BAAANQAECgcIDAAAAA==.Gravemarks:BAAANQADCgYIBAAAAA==.Grimhorn:BAAANQAECgUIEQAAAA==.Grimlie:BAAANQADCgYIDgABNQAECgcIJAAaAIwEAA==.',
Gu='Guaritrice:BAAANQAECgEIAQAAAA==.',
Gw='Gwindor:BAAANQAECgEIAQAAAA==.',
['Gö']='Gödwyn:BAAANQAECgIIAQABNQAECgQICgAFAAAAAA==.',
Ha='Hairyrage:BAAANQABCgQICAAAAA==.Hale:BAAANQADCgEIAgAAAA==.Hatterus:BAABNQAECn8jAAICAAgK8wQO4gDcAAACAAgK8wQO4gDcAAAAAA==.',
He='Healzey:BAAANQADCgUIBAAAAA==.Heavygator:BAAANQADCgEIAQAAAA==.Hetairoi:BAAANQAECgYIDAAAAA==.',
Hi='Hillbroken:BAABNQAECn9HAAIgAAoKDBrbHgAgAgAgAAoKDBrbHgAgAgAAAA==.',
Ho='Holynez:BAAANQAECgYIAQAAAA==.',
Hu='Huan:BAAANQAECgMIBAAAAA==.Huntertidus:BAAANQAECgMIAwABNQAECgQIDAAFAAAAAA==.Huntrix:BAAANQAECgIIAgAAAA==.',
Hy='Hyrlis:BAAANQAECgEIAQAAAA==.',
['Hà']='Hànks:BAAANQAECgUICwAAAA==.',
Ib='Ibíng:BAAANQAECggICgAAAA==.',
Ic='Iceatron:BAAANQADCgQIBAABNQAECgoKNAACAIkMAA==.',
In='Invariance:BAEANQADCgUIBQABNQAECgUIBQAFAAAAAA==.Inèvitable:BAABNQAECn9GAAIhAAoK5x0VEABYAgAhAAoK5x0VEABYAgAAAA==.',
Ir='Ironphant:BAABNQAECn8eAAICAAkKVQqw2gBmAQACAAkKVQqw2gBmAQAAAA==.',
Is='Ishmethit:BAAANQADCgYIBgAAAA==.Istara:BAAANQADCgcIFQAAAA==.',
Je='Jebib:BAAANQAECgYIBgABNQAFFAkJIwANALUjAA==.Jeod:BAAANQAECgEIAQAAAA==.Jettonk:BAAANQABCgIIAgABNQAECgcIJAAaAIwEAA==.',
Ji='Jirachi:BAAANQADCgEIAQAAAA==.',
Jo='Jolty:BAABNQAECn8lAAMhAAkKiiJ4FAAVAwAhAAkKiiJ4FAAVAwAcAAQKGhmshADqAAAAAA==.',
Ju='Junghoulson:BAAANQAECgUIBQAAAA==.',
['Jð']='Jð:BAAANQAECggICQAAAA==.',
Ka='Kaiou:BAAANQADCgUICwAAAA==.Kantor:BAABNQAECn9IAAIDAAoKKAyfSQDZAQADAAoKKAyfSQDZAQAAAA==.Karboomkin:BAAANQAECgIIBAABNQAFFAUIDQAQAOUVAA==.Kasenko:BAAANQADCggICAABNQAECgcIFgAiAHwZAA==.Kasryna:BAABNQAECn8WAAIiAAcKfBkhGwByAQAiAAcKfBkhGwByAQAAAA==.',
Ke='Kelmair:BAAANQADCgYIBgAAAA==.Keta:BAAANQAECgIIAQAAAA==.Ketameanie:BAABNQAECn82AAIPAAoKFRzDDgBCAgAPAAoKFRzDDgBCAgAAAA==.',
Kh='Khadguy:BAABNQAECn8kAAIfAAkKjRlGEABkAgAfAAkKjRlGEABkAgAAAA==.',
Km='Kmazing:BAAANQADCggJFAABNQAECgoKNwAIAA4aAA==.',
Kn='Knikku:BAAANQADCggICAAAAA==.',
Ko='Konoha:BAABNQAECn8zAAMEAAoKwh7xCwByAgAEAAoKwh7xCwByAgADAAIKtRst8QBRAAAAAA==.Koven:BAAANQADCggIJAAAAA==.',
Ku='Kultag:BAABNQAECn8pAAICAAoKVBLlWgDnAQACAAoKVBLlWgDnAQAAAA==.Kuun:BAABNQAECn8bAAIZAAkK5QlMmgBjAQAZAAkK5QlMmgBjAQAAAA==.',
Ky='Kyaw:BAAANQAECgUIDQAAAA==.Kynzo:BAAANQAECgQICAAAAA==.',
La='Laelah:BAAANQABCgQIBQAAAA==.Lasmína:BAAANQADCgQIBwAAAA==.Laykeezenith:BAACNQAFFH8OAAMQAAcKxiPrAgA/AgAQAAYKXiPrAgA/AgAjAAQKKx3jCwCAAQA1AAQKfygAAyMACgrJImIZAIwCACMACgpQHWIZAIwCABAABwrfIER4AB8CAAAA.Lazuli:BAABNQAECn9IAAMZAAoKhRyHHwBIAgAZAAoKhRyHHwBIAgAeAAgKiQmSXABxAQAAAA==.',
Le='Lehann:BAABNQAECn8iAAIQAAkKcwqrewB7AQAQAAkKcwqrewB7AQAAAA==.',
Li='Littlebitty:BAAANQAECgcIDgAAAA==.',
Lo='Lockatron:BAAANQADCggIEAABNQAECgoKNAACAIkMAA==.Lothryn:BAABNQAECn8yAAMGAAoKIA0BPwDmAQAGAAoKIA0BPwDmAQACAAgKzwu5vwCdAQAAAA==.',
Lp='Lp:BAABNQAECn8ZAAIPAAoKGxzYDwAwAgAPAAoKGxzYDwAwAgAAAA==.',
Lu='Lunariah:BAAANQADCgIIAgAAAA==.',
Ly='Lyllien:BAAANQAECgIIAgAAAA==.',
Ma='Marenus:BAABNQAECn9BAAIQAAkKrQv9bwCYAQAQAAkKrQv9bwCYAQAAAA==.Marten:BAAANQABCgIIAgAAAA==.Masume:BAAANQAECgUICQAAAA==.Maély:BAAANQADCgUIBQAAAA==.',
Me='Mechadead:BAABNQAECn8XAAIgAAcKXgPAeACMAAAgAAcKXgPAeACMAAABNQAECgoKNAACAIkMAA==.Megaopto:BAABNQAECn8iAAIcAAcKSBWzKwB+AQAcAAcKSBWzKwB+AQAAAA==.Meowmix:BAAANQADCgMICAAAAA==.Methanny:BAAANQADCgQIBAAAAA==.',
Mi='Mizmonk:BAAANQADCggICAAAAA==.',
Mj='Mjölnir:BAABNQAECn85AAICAAoKpBo4NgBdAgACAAoKpBo4NgBdAgAAAA==.',
Mo='Momentum:BAAANQAECgEIAQAAAA==.',
Ms='Msdiiva:BAAANQAECgMIAwAAAA==.',
Mu='Mushuu:BAAANQADCgYIDAAAAA==.',
My='Mythel:BAAANQAECgMIAwABNQAECgoKVAAWAI8iAA==.',
['Mô']='Môjô:BAAANQABCgUIBQAAAA==.',
Na='Nahion:BAAANQAECgEIAQAAAA==.Nashira:BAABNQAECn8rAAIQAAoKexL4eAAdAgAQAAoKexL4eAAdAgAAAA==.',
Ne='Nemasus:BAABNQAECn8cAAQNAAYKPxjiQwANAQANAAQKCxjiQwANAQAMAAYKCxQiTADBAAAiAAUKMAOaRQCdAAAAAA==.Nepolian:BAAANQABCgYICAAAAA==.Neraine:BAAANQAECgUIDgAAAA==.',
Ni='Ninjahh:BAABNQAECn8wAAIWAAoKkhOcMQD5AQAWAAoKkhOcMQD5AQAAAA==.Nioshei:BAABNQAECn87AAMeAAkKqhisQQBaAgAeAAkKqhisQQBaAgAZAAYKBAitdgDuAAAAAA==.',
No='Nochmuerta:BAAANQADCgUIBQABNQADCgcIBwAFAAAAAA==.Noctyrna:BAAANQABCgQIAgAAAA==.Nogrid:BAABNQAECn9IAAIHAAoKKh/FBgDBAgAHAAoKKh/FBgDBAgAAAA==.Noxstantine:BAAANQADCgQIBgAAAA==.',
Nu='Nuthar:BAABNQAECn8yAAICAAkKEB0TPwA8AgACAAkKEB0TPwA8AgAAAA==.',
Ny='Nyrrhi:BAAANQAECggIDgAAAA==.',
Ol='Oldeis:BAAANQADCgYJBgAAAA==.',
Or='Orneryosprey:BAAANQAECgQIBwABNQAECgYIDAAFAAAAAA==.',
Ou='Ouroborös:BAABNQAECn8oAAIQAAoKbhHZTQD0AQAQAAoKbhHZTQD0AQAAAA==.',
Oy='Oyashiro:BAAANQAECgcIBwAAAA==.',
Pa='Pamburu:BAABNQAECn82AAIQAAoKfxPTRAAOAgAQAAoKfxPTRAAOAgAAAA==.Papagrape:BAABNQAECn8uAAMkAAkKtRsLCgBfAgAkAAkKtRsLCgBfAgAlAAMKOhfOKQDcAAAAAA==.Paradiselost:BAAANQADCgQIBwAAAA==.Parzivàl:BAAANQAECgIIAQAAAA==.Paxa:BAABNQAECn8nAAMDAAkKlhilLwBQAgADAAkKlhilLwBQAgAEAAIK4ArtaQBaAAAAAA==.',
Pe='Peekabu:BAAANQADCgcICAABNQAECgoKNAACAIkMAA==.Pennelo:BAAANQADCgQIBAAAAA==.Persayis:BAAANQAECgIIAgAAAA==.',
Ph='Phoebel:BAAANQADCgIJAgABNQAECgcIJAAQAMsQAA==.',
Pi='Pineappledk:BAEANQADCggIEgABNQAECgQIBgAFAAAAAA==.Pineapplepn:BAEANQAECgQIBgAAAA==.Pineapplle:BAEANQAECgQIBgABNQAECgQIBgAFAAAAAA==.',
Pl='Plazelly:BAAANQADCgcIDAAAAA==.',
Po='Podnov:BAABNQAECn8yAAIjAAoKPRw9FwCgAgAjAAoKPRw9FwCgAgAAAA==.Pollyanna:BAAANQABCgYICAAAAA==.',
Py='Pyrista:BAAANQAECggICwAAAA==.',
Qa='Qahili:BAAANQADCgUIBQAAAA==.Qang:BAAANQAECgIIAgAAAA==.',
Ra='Radiante:BAACNQAFFH8IAAIGAAUKmgO1EQBHAQAGAAUKmgO1EQBHAQA1AAQKfyAAAwYACQrwHD0dAP4CAAYACQrwHD0dAP4CAAIAAQodA27MASEAAAAA.Rageadin:BAAANQABCgcIBQAAAA==.Raion:BAABNQAECn8zAAIHAAoKxx8/CQB9AgAHAAoKxx8/CQB9AgAAAA==.Raithis:BAACNQAFFH8TAAIQAAYKrB8FBgBeAQAQAAYKrB8FBgBeAQA1AAQKf0IAAhAACgpNJa4IADIDABAACgpNJa4IADIDAAAA.Raito:BAAANQADCgYIBgAAAA==.Ralzin:BAAANQADCgEIAQAAAA==.Ramhadin:BAEANQADCgcIHAABNQAECggINQAEAHYcAA==.Randel:BAAANQAECggIBgAAAA==.Raucousrhea:BAAANQABCgIIAgAAAA==.Rav:BAAANQAECgYICwAAAA==.',
Re='Redvelvet:BAABNQAECn8rAAImAAoKNhCGHAC8AQAmAAoKNhCGHAC8AQAAAA==.Resisting:BAAANQAECgYIDAABNQAECgoKGQAPABscAA==.Reznal:BAABNQAECn8cAAMZAAkKmx2ENwCYAgAZAAgKGx6ENwCYAgAeAAUKuB6AeACiAQABNQAFFAIIBQAIADwTAA==.',
Ro='Romam:BAAANQAECgEIAQAAAA==.',
Ry='Rydran:BAAANQADCgIIAgAAAA==.Rykria:BAAANQADCgcIFQAAAA==.',
Sa='Sableanne:BAABNQAECn9AAAIeAAoKJQjojgBjAQAeAAoKJQjojgBjAQAAAA==.Saedirine:BAAANQADCgYIDAAAAA==.Saggi:BAAANQAECgIIBAAAAA==.',
Se='Secksiecutie:BAABNQAECn8zAAIgAAoKzBHfKwDFAQAgAAoKzBHfKwDFAQAAAA==.Secondwall:BAAANQADCgYIBgAAAA==.Selma:BAAANQABCgMIAwAAAA==.Serinar:BAABNQAECn8ZAAICAAgK5hNNqADPAQACAAgK5hNNqADPAQAAAA==.',
Sh='Shadowbolt:BAAANQABCgQIBgAAAA==.Shoorah:BAAANQADCgEIAQAAAA==.',
Si='Siako:BAABNQAECn8UAAMSAAgKXQeOBABcAQAIAAgKEQRxFgFnAQASAAcKFwiOBABcAQAAAA==.Silversaiyan:BAABNQAECn89AAITAAkKtR3YBABlAgATAAkKtR3YBABlAgAAAA==.Sirlink:BAAANQABCgIIAgAAAA==.',
Sl='Slade:BAABNQAECn9UAAMWAAoKjyI2BABTAwAWAAoKjyI2BABTAwAXAAYKhRevHAAsAQAAAA==.Sliyce:BAAANQADCgEIAQAAAA==.',
Sm='Smorc:BAAANQAECgQIBwAAAA==.',
Sn='Sneakyclubs:BAAANQADCgUICAAAAA==.Snowfawn:BAAANQAECgUICwABNQAECggIDgAFAAAAAA==.',
So='Sofedan:BAABNQAECn9AAAIjAAkKEgZgIwAVAQAjAAkKEgZgIwAVAQAAAA==.Sorgath:BAAANQAECgEIAgAAAA==.Soriel:BAABNQAECn87AAIdAAkKFxPXCgBaAQAdAAkKFxPXCgBaAQAAAA==.Sorokwa:BAABNQAECn8uAAIhAAoKcAQ/hwAEAQAhAAoKcAQ/hwAEAQAAAA==.',
Sq='Squeeze:BAAANQAECgUJCwAAAA==.',
St='Stillwater:BAABNQAECn8yAAQfAAoKJQzeEQC2AQAfAAoKJQzeEQC2AQAZAAMKygONCAF7AAAeAAEKMQRc9wAeAAAAAA==.Strathius:BAAANQAECgEIAQAAAA==.',
Su='Suriden:BAAANQADCggICQAAAA==.',
Sw='Swagidan:BAABNQAECn9DAAIOAAoKiRlOFwAoAgAOAAoKiRlOFwAoAgAAAA==.Sweaterpally:BAAANQADCgUICQAAAA==.Swiftera:BAAANQAECgIIAgAAAA==.Swiftlier:BAAANQAECgcICAABNQAECgoKPgAcAIkPAA==.',
Sy='Sylphrène:BAABNQAECn8cAAMPAAgKYQKCNwCuAAAPAAgKYQKCNwCuAAAOAAMKUQHcjQBAAAAAAA==.',
Ta='Taghman:BAAANQAECgMICAABNQAECgoKVAAWAI8iAA==.Taleth:BAAANQAECgIIAwABNQAECgQICAAFAAAAAA==.Tandrana:BAAANQAECgEIAQAAAA==.Targanisha:BAAANQADCggICAABNQAECgoKMQAZAJwbAA==.Targdh:BAABNQAECn9YAAIPAAoKHx78EQDcAgAPAAoKHx78EQDcAgABNQAECgoKMQAZAJwbAA==.Targforeva:BAAANQAECgQIBgABNQAECgoKMQAZAJwbAA==.',
Te='Terminus:BAAANQADCgMIAwAAAA==.',
Ti='Ticebane:BAABNQAECn8XAAIhAAgKkQsWZQB8AQAhAAgKkQsWZQB8AQAAAA==.Tichus:BAAANQADCgYIDgAAAA==.Tidusdruo:BAAANQAECgIIAgABNQAECgQIDAAFAAAAAA==.Tiduspullo:BAAANQAECgQIBQABNQAECgQIDAAFAAAAAA==.Tinafay:BAAANQAECgEIAQAAAA==.Titanbeard:BAAANQADCggIGAAAAA==.Titor:BAABNQAECn8vAAMkAAcK8hDXFgBGAQAkAAcK8hDXFgBGAQAlAAIKKALINwBQAAAAAA==.Tituspullo:BAAANQAECgQIDAAAAA==.',
To='Tock:BAAANQAECgEIAQAAAA==.Tolduan:BAABNQAECn8fAAMZAAgK1QpbawALAQAZAAgK1QpbawALAQAfAAUKAARuLQCRAAAAAA==.Totemik:BAAANQADCgUIBQAAAA==.Toughturkey:BAAANQADCgEIAQABNQAECgYIDAAFAAAAAA==.',
Tr='Tricarnetry:BAABNQAECn80AAICAAoKiQyaewCWAQACAAoKiQyaewCWAQAAAA==.Tricarnity:BAAANQAECgUIEAABNQAECgoKNAACAIkMAA==.Trucknôrris:BAAANQADCgUIBwAAAA==.Trîela:BAABNQAECn8fAAIMAAkKHwlZMQBFAQAMAAkKHwlZMQBFAQAAAA==.',
Ul='Ulfer:BAAANQADCgYIBgABNQAECggIGwAhAGAfAA==.',
Um='Um:BAAANQAFFAEIAQAAAA==.',
Ve='Veganwolf:BAAANQADCgMIAwAAAA==.Verakis:BAABNQAECn87AAIKAAkK9A8OEAB8AQAKAAkK9A8OEAB8AQAAAA==.Verndarí:BAABNQAECn8+AAIcAAoKiQ+YJACrAQAcAAoKiQ+YJACrAQAAAA==.Verudora:BAAANQAECgUIBgAAAA==.',
Vi='Vishas:BAAANQAECgQIBwAAAA==.',
Vo='Vortheus:BAAANQAECgcIDgAAAA==.Votollis:BAAANQAECgEIAQAAAA==.',
Vr='Vrack:BAAANQADCgQIBAAAAA==.',
Wa='Warhowl:BAAANQABCggIDgAAAA==.Warlanen:BAAANQAECgEIAQAAAA==.',
Wi='Willbur:BAABNQAECn8/AAIIAAoK8BBtUQD0AQAIAAoK8BBtUQD0AQAAAA==.',
Wu='Wurthwhile:BAAANQADCgcIEQAAAA==.',
Wy='Wyndywalker:BAAANQAECgYIEAAAAA==.',
Xa='Xayvior:BAAANQAECggIEAAAAA==.',
Xi='Xinnuo:BAAANQADCggIEAAAAA==.',
Za='Zamønk:BAAANQAECgUICQAAAA==.',
Ze='Zeigfeld:BAAANQAECgIIAgAAAA==.',
Zi='Ziarra:BAAANQADCgYIBQABNQAECgQIBwAFAAAAAA==.Zimzy:BAAANQAECgEIAQAAAA==.',
Zo='Zok:BAABNQAECn8bAAIJAAkKLwqmYgCeAQAJAAkKLwqmYgCeAQAAAA==.',
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
