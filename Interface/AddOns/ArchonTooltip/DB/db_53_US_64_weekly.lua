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

local lookup = {'Monk-Windwalker','Unknown-Unknown','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','Druid-Balance','Druid-Restoration','Warlock-Affliction','DemonHunter-Devourer','Shaman-Restoration','Hunter-BeastMastery',}
local provider = {region='US',realm='Deathwing',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aamix:BAAANQAECgcIEQAAAA==.Aarom:BAABNQAECoEZAAIBAAkJdyMpAgByAwABAAkJdyMpAgByAwAAAA==.Aaronk:BAAANQADCggIDwAAAA==.',
Ab='Abdltdoc:BAAANQAECgIIAgAAAA==.',
Ae='Aelyn:BAAANQADCgQIBAAAAA==.Aerius:BAAANQADCgcIEAAAAA==.',
Af='Affliclock:BAAANQAECggIEgAAAA==.',
Ai='Aingerfal:BAAANQADCggIEgAAAA==.',
Ak='Akasori:BAAANQAECgYIDgAAAA==.Akosori:BAAANQADCgYIBgABNQAECgYIDgACAAAAAA==.',
Al='Alterboyy:BAAANQAECgEIAQAAAA==.Alîsonshammy:BAAANQAFFAIIAgAAAA==.',
Am='Ambersulfr:BAAANQAECgEIAQAAAA==.Amrazz:BAAANQAECgQIBAAAAA==.Amzey:BAEANQAECgcIDQAAAA==.',
An='Anahata:BAAANQADCgEIAgABNQADCgQIBAACAAAAAA==.Andromeda:BAAANQAECgQIBgAAAA==.Anneaux:BAAANQADCgcICwAAAA==.Antimortem:BAAANQADCgQIBAAAAA==.',
Ar='Aridillo:BAAANQAECgEIAQAAAA==.',
As='Ashaea:BAAANQAECgEIAQAAAA==.Ashaka:BAAANQAECgIIAgAAAA==.Astralus:BAAANQAECgMIBAAAAA==.Astramis:BAAANQADCggIEwAAAA==.',
At='Atomicbarbie:BAAANQAECgQIBAABNQAFFAIIAgACAAAAAA==.Atriøx:BAAANQADCggICAAAAA==.Atziri:BAAANQAECgUICAAAAA==.',
Az='Azamia:BAAANQAECgMIAwABNQABCgIIAwACAAAAAA==.',
Ba='Backlash:BAAANQAECgEIAgAAAA==.Balzhac:BAAANQADCgcIBwAAAA==.Bam:BAAANQADCggICAABNQAECgkJFwADAKojAA==.Bamplify:BAAANQAECgUIBQABNQAECgkJFwADAKojAA==.Barrierbobo:BAAANQADCggIEwAAAA==.Barthold:BAAANQADCgcIBwAAAA==.',
Be='Bellmonte:BAAANQADCgYIBgABNQAECgQICAACAAAAAA==.Belmonk:BAAANQAECgEIAQAAAA==.Berdron:BAAANQAECgYIDQAAAA==.',
Bl='Bladeliger:BAAANQAECgQIBgAAAA==.Blazin:BAAANQAECgEIAQAAAA==.Bledsmasher:BAAANQADCgUIBQAAAA==.Blouses:BAAANQAFFAEIAQAAAA==.',
Bo='Boltsgobrr:BAAANQADCgIIAgAAAA==.Boned:BAAANQADCggIFAAAAA==.Bonemair:BAABNQAECoEZAAIEAAkJ9hllDACvAgAEAAkJ9hllDACvAgAAAA==.Boredasf:BAAANQADCgYIBgAAAA==.',
Br='Bradocks:BAAANQADCggIDAAAAA==.Breezeblocks:BAAANQADCgEIAQAAAA==.Bryteblade:BAAANQADCgMIAwABNQADCgYIFgACAAAAAA==.',
Bu='Bubblehooker:BAAANQAECgIIAgAAAA==.Buffnbeers:BAAANQADCgYICwABNQAFFAIIAgACAAAAAA==.Bullteesta:BAAANQADCgQIBAAAAA==.',
Bw='Bwonurjor:BAAANQADCgQIBAAAAA==.',
['Bó']='Bónes:BAAANQADCggICwAAAA==.',
Ca='Caldec:BAABNQAECoEaAAIFAAkJrCQGAQChAwAFAAkJrCQGAQChAwAAAA==.',
Ch='Chainizard:BAAANQAECgcICAAAAA==.Cheeno:BAAANQAECgUICwAAAA==.Chihiro:BAAANQADCggIFAAAAA==.Chillyfists:BAAANQADCgUIBQAAAA==.Chuffed:BAAANQABCgIIAgABNQADCgYIBgACAAAAAA==.',
Cl='Clisholder:BAAANQADCgQIBAAAAA==.',
Co='Coaltaine:BAAANQADCgMIAwABNQADCgYIFgACAAAAAA==.Computer:BAABNQAECoEWAAMGAAgJ/yIcAgAXAwAGAAgJ/yIcAgAXAwAHAAcJAhpQGgArAgAAAA==.Cootin:BAAANQAECggIBgAAAA==.',
Cp='Cpteddie:BAAANQAECgYIEgABNQAFFAQICAAEAHwaAA==.',
Cr='Craigg:BAAANQADCgYIBgAAAA==.Crate:BAAANQADCgQIBAABNQAECgEIAQACAAAAAA==.Crelam:BAABNQAECoEZAAIIAAkJExGWBACcAgAIAAkJExGWBACcAgAAAA==.Critherine:BAAANQADCgcIBgAAAA==.Cronatherus:BAAANQADCgUIBQAAAA==.Cruentis:BAAANQAECgMIBAAAAA==.Crysuh:BAAANQAECgMIAwABNQAECgUIBwACAAAAAA==.Crysus:BAAANQAECgUIBwAAAA==.',
Da='Dabo:BAAANQAECgUIBwAAAA==.Damarisalynn:BAAANQADCgUIBQAAAA==.Darkurgekris:BAAANQADCggICAABNQAFFAEIAQACAAAAAA==.Darwin:BAAANQADCgcIEgAAAA==.Dasmoodhayn:BAAANQADCgcIDwAAAA==.Davalanch:BAAANQAECggIEwAAAA==.Dazizejr:BAAANQAECgcIDQAAAA==.',
De='Deathxrage:BAAANQADCgcIDwAAAA==.Decor:BAAANQADCgYICQAAAA==.Denïed:BAAANQADCgQIBAAAAA==.Deramooke:BAAANQADCgcIBwAAAA==.Dethkløk:BAAANQADCgYICQAAAA==.',
Di='Dibstrum:BAAANQADCgcIEAAAAA==.Digduug:BAAANQAECgQIBAAAAA==.Dixqt:BAAANQAECgQICAAAAA==.',
Do='Dogfight:BAABNQAECoEYAAMJAAkJ8BhKDgC+AgAJAAkJ8BhKDgC+AgAFAAIJQAMYLgBHAAAAAA==.Doilookfatou:BAAANQAECgUIBgAAAA==.',
Dr='Draxus:BAAANQADCgcIEAAAAA==.Dresel:BAAANQAECgYIBgAAAA==.Drewpeebahlz:BAAANQADCgYIBgABNQABCgIIAgACAAAAAA==.Drshakaloo:BAAANQADCggIFQAAAA==.',
Du='Dunnome:BAAANQADCgYIBgAAAA==.Durto:BAAANQADCgYIBgAAAA==.',
Dy='Dyami:BAAANQAECgMIAwAAAA==.Dynas:BAAANQADCgcIBwAAAA==.',
Ea='Earthcake:BAAANQAECgYIDAAAAA==.',
Ed='Eddielich:BAACNQAFFIEIAAIEAAQJfBpfAgBOAQAEAAQJfBpfAgBOAQA1AAQKgRkAAgQACQmkJMMBAK8DAAQACQmkJMMBAK8DAAAA.',
Eg='Eggfumonk:BAAANQADCgYIFgAAAA==.',
El='Elasmon:BAAANQAECgQIBQAAAA==.Elbodeep:BAAANQADCgQIBAAAAA==.Elfpen:BAAANQADCgMIAwAAAA==.',
Er='Erragal:BAAANQADCgMIAwAAAA==.',
Ez='Ezindrozar:BAAANQADCgUIAwAAAA==.',
Fa='Falek:BAAANQAECgEIAQAAAA==.',
Fe='Felurián:BAAANQADCgcICQABNQADCgUIBwACAAAAAA==.Fexli:BAAANQADCgMIAwAAAA==.',
Fi='Fireteeth:BAAANQADCgYICAAAAA==.',
Fl='Flurtty:BAAANQADCgQICAAAAA==.',
Fo='Folklore:BAAANQADCgcIEgAAAA==.',
Fr='Frighrish:BAAANQADCggICAAAAA==.Frigomortis:BAAANQADCgYIEAABNQADCgcIEQACAAAAAA==.Frozown:BAAANQAECgYICgAAAA==.Fruits:BAAANQAECgEIAQAAAA==.',
Ft='Ftfw:BAAANQAECgMIAwAAAA==.',
Fu='Funfanfare:BAAANQADCgQIBAAAAA==.Furrylife:BAAANQADCggICwAAAA==.Fusebawx:BAAANQADCgUIBgABNQAECgEIAQACAAAAAA==.Fuzzychin:BAAANQAECgEIAgAAAA==.',
['Fò']='Fòrlorn:BAAANQABCgEIAQAAAA==.',
Ga='Galram:BAAANQAECgYIBgABNQAECgkJGQAIABMRAA==.Gardettos:BAAANQAECgQIBgAAAA==.Gargingoyles:BAAANQADCgIIAgAAAA==.',
Gh='Gharghael:BAAANQADCggICQAAAA==.',
Gi='Gip:BAAANQABCgIIBAAAAA==.',
Gl='Glimmair:BAAANQAECgUIBQABNQAECgkJGQAEAPYZAA==.Glimmer:BAAANQADCgUIBQAAAQ==.',
Gn='Gnxrr:BAAANQAECgYICgAAAA==.',
Go='Gooncaine:BAAANQAECgYICgAAAA==.Gorbstrasz:BAAANQAECgEIAQAAAA==.Gorpse:BAAANQAECgIIAgAAAA==.',
Gr='Gregorz:BAAANQADCgMIAwAAAA==.Greyanna:BAAANQADCgcIEgAAAA==.Gridon:BAAANQABCgUIBQAAAA==.Gromthrall:BAAANQADCgcIEgAAAA==.',
Gw='Gwynhwyfar:BAAANQADCgMIAwABNQAECgQIBQACAAAAAA==.',
Hb='Hbhealthen:BAABNQAECoEcAAMKAAkJpx8LAwAvAwAKAAkJpx8LAwAvAwALAAEJLBr8HgBSAAAAAA==.',
He='Hellhore:BAAANQADCggIGAAAAA==.Hetamala:BAAANQADCgMIAwAAAA==.',
Hi='Highego:BAAANQAECgEIAQAAAA==.',
Ho='Holdenc:BAAANQAECgIIAgABNQAECgQIBgACAAAAAA==.Hoodz:BAAANQAECgQIBgAAAA==.Houseplant:BAAANQADCggIDAAAAA==.Howard:BAAANQADCgcIEAAAAA==.',
Hu='Huzzarr:BAAANQABCgIIAgAAAA==.',
Hy='Hypnos:BAAANQADCgEIAQAAAA==.',
Ib='Ibearprofen:BAAANQAECgQIBgAAAA==.',
Id='Idtrapdat:BAAANQAECgcIEQAAAA==.',
Il='Ilse:BAAANQAECgQIBwAAAA==.',
Im='Imagined:BAABNQAECoEZAAIMAAkJMBp5IADUAgAMAAkJMBp5IADUAgAAAA==.',
In='Indihunter:BAAANQADCgEIAQAAAA==.',
Ir='Ironchords:BAAANQADCgEIAQAAAA==.',
Iv='Ivank:BAAANQAECgEIAQAAAA==.Ivannalot:BAAANQADCgUIBwAAAA==.Ivracha:BAAANQAECgEIAQAAAA==.',
Ja='Jage:BAAANQADCggIEQAAAA==.Jarsham:BAAANQADCgcIEQAAAA==.Jaràdan:BAAANQADCgQIBAABNQAECgYIDAACAAAAAA==.',
Je='Jeff:BAAANQAECggICgAAAA==.Jemma:BAAANQABCgYICgAAAA==.',
Jo='Joran:BAAANQADCgcIDgAAAA==.Jordie:BAAANQADCgIIAgAAAA==.',
Jw='Jwrs:BAAANQAECgEIAQAAAA==.',
['Jï']='Jïbril:BAAANQAECgYICAAAAA==.',
Ka='Kabbala:BAAANQAECgQICAABNQAECgkJGQAMADAaAA==.Kahlani:BAAANQAECgQIBQAAAA==.Kahlua:BAAANQAECgIIAgAAAA==.Kailan:BAAANQADCgYIBgABNQAECgQIBwACAAAAAA==.Kalathios:BAAANQABCgIIAgABNQAECgIIAgACAAAAAA==.Kaldro:BAAANQAECgEIAQAAAA==.Kaliae:BAAANQADCgYIBAAAAA==.Kaly:BAAANQAECgMIAwAAAA==.Kano:BAAANQAECgMIAwAAAA==.Kariana:BAAANQAECgUIBwAAAA==.Kathry:BAAANQADCgUIBwAAAA==.',
Ke='Keepdreaming:BAAANQAECgMIAwAAAA==.Kefkka:BAAANQADCgEIAQAAAA==.Keybricker:BAAANQADCgUIBQABNQAFFAIIAgACAAAAAA==.Keymebrah:BAAANQAECggIEQAAAA==.',
Ko='Korda:BAAANQADCggICAAAAA==.Korinä:BAAANQAECgYIBgAAAA==.Kosh:BAAANQADCgMIAwAAAA==.Koyra:BAABNQAECoEXAAILAAkJDCWbAADDAwALAAkJDCWbAADDAwAAAA==.',
Kr='Krump:BAAANQADCgcIBwAAAA==.',
Ku='Kubwa:BAAANQABCgUIBwAAAA==.Kungfugimp:BAAANQADCggIDwAAAA==.Kurral:BAABNQAECoEZAAMNAAkJ8xpiCwDqAgANAAkJ8xpiCwDqAgAOAAEJVgG8NgAeAAAAAA==.Kurstina:BAAANQADCgYICQAAAA==.',
Ky='Kyramus:BAAANQADCggIEwAAAA==.',
La='Laconia:BAAANQAECgQICAAAAA==.Lashstorm:BAAANQADCgcICwAAAA==.Lattsatnar:BAAANQAECgEIAQAAAA==.',
Le='Lebron:BAAANQADCgYIDAABNQADCggIDQACAAAAAA==.Lennel:BAAANQADCgYIBgABNQADCgYICwACAAAAAA==.',
Li='Lilsnick:BAAANQADCgcIDgABNQADCgcIEAACAAAAAA==.Litterbawx:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.',
Ll='Llanthyl:BAAANQADCggIEwAAAA==.',
Lo='Lockbawx:BAAANQAECgEIAQAAAA==.Lockntroll:BAAANQAECgEIAQAAAA==.Loktardogard:BAAANQADCgUIBQAAAA==.',
Lu='Lunafalia:BAAANQAECgQIBgAAAA==.Lurosa:BAAANQAECgcIEQAAAA==.Luxray:BAAANQABCgYIBwAAAA==.',
Ly='Lyrae:BAAANQADCgYIBwAAAA==.',
['Lï']='Lïchkinged:BAAANQADCgUIBQAAAA==.',
Ma='Macready:BAAANQAECgcIDwAAAA==.Magenin:BAAANQADCgcIEAAAAA==.Maggotgut:BAAANQADCgQIBQAAAA==.Magoren:BAAANQADCgEIAQAAAA==.Mairiachi:BAAANQAECgEIAQABNQAECgkJGQAEAPYZAA==.Maltessa:BAAANQADCgUICgABNQAECgQIBwACAAAAAA==.Marload:BAAANQAECgcIDwAAAA==.',
Me='Melath:BAAANQADCggIDQAAAA==.',
Mi='Midletons:BAAANQADCggIDgAAAA==.Minikub:BAAANQAECgIIAgAAAA==.',
Mn='Mnzn:BAAANQADCggIEAAAAA==.',
Mo='Moodroo:BAAANQADCggIEAAAAA==.Moonanoke:BAAANQADCggIEAAAAA==.Moovoker:BAAANQAECgQIBwAAAA==.Morseques:BAAANQAECgQIBgAAAA==.Mortimer:BAAANQAECgMIBAAAAA==.Moz:BAAANQADCgMIAwAAAA==.',
Mu='Muggy:BAABNQAECoEYAAMJAAkJwSH1CAAVAwAJAAgJ0yP1CAAVAwAFAAMJeRfKGwDpAAAAAA==.',
Mx='Mxkebfistin:BAABNQAECoEXAAIBAAkJcxrbBgDAAgABAAkJcxrbBgDAAgAAAA==.Mxkebspinnin:BAAANQADCggICAABNQAECgkJFwABAHMaAA==.',
Na='Narama:BAABNQAECoEXAAQGAAkJehBaFwB5AQAGAAYJjgxaFwB5AQAHAAUJdhPrQQBGAQAPAAEJAA0QGQAsAAAAAA==.',
Ne='Nekka:BAAANQADCgQICAAAAA==.Nethanos:BAAANQADCgQIBAAAAA==.Neverrmore:BAAANQADCgUIBQAAAA==.',
Ni='Ninæ:BAAANQAECggIDwAAAA==.Nitewïng:BAAANQADCggIEAABNQADCgUIBQACAAAAAQ==.',
No='Nofeet:BAAANQADCgYICwAAAA==.Nohomoh:BAAANQADCgUIBgAAAA==.Nootau:BAAANQAECgQIDQAAAA==.',
Ny='Nyoz:BAAANQADCgYIDgAAAA==.Nyxxadra:BAAANQAECgMIBQAAAA==.',
Om='Omegadeed:BAAANQAECgQIBgAAAA==.',
On='Onne:BAAANQADCgMIBgAAAA==.',
Or='Orcinus:BAAANQAECgYIDAAAAA==.Orcishfist:BAAANQADCggICAAAAA==.Orvar:BAAANQADCggIEQABNQABCgIIAgACAAAAAA==.',
Pa='Pakaru:BAAANQAECgUIBQAAAA==.Pam:BAABNQAECoEXAAIDAAkJqiOvAgBnAwADAAkJqiOvAgBnAwAAAA==.',
Pe='Peorä:BAAANQAECgYIBgAAAA==.Perfectdark:BAABNQAECoEZAAIQAAkJUSP/AQCdAwAQAAkJUSP/AQCdAwAAAA==.Perse:BAAANQADCgcIDAAAAA==.',
Ph='Phathottie:BAAANQABCgEIAQABNQADCgcIEQACAAAAAA==.Pheadas:BAAANQADCgUIBQAAAA==.',
Pi='Pieper:BAAANQAECgQIBQAAAA==.Pipa:BAAANQAECgUICwAAAA==.Pippit:BAAANQAECgQIBgABNQAECgUICwACAAAAAA==.',
Pl='Plokane:BAAANQAECgUIBgAAAA==.',
Po='Poacher:BAAANQADCgMIAwAAAA==.Poppapally:BAAANQADCgYICQAAAA==.Porque:BAAANQADCggIDQAAAA==.Powar:BAAANQADCgUIAwAAAA==.',
Pr='Provence:BAAANQADCgYICAAAAA==.',
Py='Pyreynna:BAAANQAECgEIAQAAAA==.',
['Pè']='Pèppèr:BAAANQAECgQIBQABNQAECgQIBgACAAAAAA==.',
Qs='Qsteve:BAAANQADCgYIBgAAAA==.',
Ra='Rainier:BAAANQADCgIIAgAAAA==.Ralnorin:BAAANQADCggIEgAAAA==.Raschild:BAAANQAECgEIAQAAAA==.',
Re='Realfrojd:BAAANQAECgQIBQAAAA==.Regginunchuk:BAAANQAECgQIBwAAAA==.Releronastus:BAAANQADCgcICwAAAA==.Rextallion:BAAANQAECgYIDgAAAA==.Reyson:BAAANQAECgQIBgAAAA==.',
Rh='Rhunon:BAAANQAFFAEIAQAAAA==.Rhythma:BAAANQADCgYIBAAAAA==.',
Ri='Rinthia:BAAANQAECgQIBwAAAA==.Ripyeet:BAAANQAECgUICAAAAA==.',
Ro='Rol:BAAANQADCgQIBAAAAA==.Rolden:BAAANQADCgcIEAAAAA==.',
Ru='Rukaji:BAAANQAECgEIAwAAAA==.',
['Rå']='Rågeadin:BAAANQADCgYIDQABNQADCgQIBQACAAAAAA==.Rågè:BAAANQADCgQIBQAAAA==.',
Sa='Saetheline:BAAANQAECgMIAwAAAA==.Sarkang:BAAANQAECgEIAQAAAA==.Satdurrday:BAAANQADCgQIBAABNQAECgQIBgACAAAAAA==.',
Sc='Schutze:BAAANQAECgcIDQAAAA==.',
Sd='Sdadfeg:BAAANQAECgQIBgAAAA==.',
Se='Senco:BAAANQADCgcIDQAAAA==.',
Sh='Shabobado:BAAANQAECgYIBgAAAA==.Shadowleaf:BAAANQADCgQIBAAAAA==.Shampyre:BAAANQADCgUIBQAAAA==.Shiipo:BAAANQADCggIDAAAAA==.Shøck:BAAANQAECgIIAgAAAA==.',
Si='Sibble:BAAANQADCgYIBgAAAA==.Siegfried:BAAANQADCggIDAAAAA==.Silbanuz:BAAANQAECgQIBQAAAA==.Simplejakk:BAAANQAECgcIBwAAAA==.Sinterklaas:BAAANQAECgMIAwAAAA==.',
Sk='Skylee:BAAANQAECgQIBQAAAA==.',
Sl='Slark:BAAANQAECgQIBAAAAA==.Slawth:BAAANQAECgQIBQAAAA==.Sleepel:BAAANQADCgYIBgAAAA==.',
Sm='Smexytimes:BAAANQAECgUIBQAAAA==.Smeyplus:BAAANQAFFAMIAgAAAA==.',
Sn='Snickeris:BAAANQADCgcIEAAAAA==.Snofawl:BAAANQAECgYIBwAAAA==.Snoranir:BAAANQAECgEIAQAAAA==.Snurchbasher:BAAANQADCggIDwAAAA==.',
Sp='Speedpuss:BAAANQADCgUIBQAAAA==.Spiko:BAAANQAECgQIBgAAAA==.Spratticus:BAAANQADCgYIBgAAAA==.',
Sq='Squidd:BAAANQADCgMIAwAAAA==.',
St='Stars:BAAANQAECgEIAQABNQAECgcIEQACAAAAAA==.',
Su='Sureno:BAAANQAECgQICAAAAA==.',
Sx='Sxyhealz:BAAANQADCggICAAAAA==.Sxyheålz:BAAANQAECgYIDwAAAA==.',
Ta='Tanndari:BAAANQADCgUICwAAAA==.Tartare:BAAANQAECgQIBAAAAA==.Tashaman:BAABNQAECoEbAAIRAAkJxwzOHQAbAgARAAkJxwzOHQAbAgAAAA==.',
Te='Teriheals:BAAANQADCgcIEAAAAA==.',
Th='Thejorlane:BAAANQADCgUIBwAAAA==.Thiccholy:BAAANQAECgcIEgAAAA==.Thiccshields:BAAANQADCgQIBAABNQAECgcIEgACAAAAAA==.Thicctotemz:BAAANQADCgYIDAABNQAECgcIEgACAAAAAA==.Thogo:BAAANQAECgQIBgAAAA==.',
Ti='Tikaa:BAAANQADCgYIDgAAAA==.Tipnontotems:BAAANQADCgUIBQAAAA==.',
To='Tokiya:BAAANQAECgcIEgAAAA==.Tomerto:BAAANQAECgQIBgAAAA==.Toobeastly:BAAANQAECgQICAAAAA==.Toonerdin:BAAANQADCggIEwAAAA==.',
Tr='Tril:BAAANQADCgcIEgAAAA==.Trox:BAAANQADCgcIEAAAAA==.Tryingmybest:BAAANQAFFAIIAgAAAA==.',
Ts='Tsugi:BAAANQAECgIIAgAAAA==.',
Tw='Twozero:BAAANQADCgIIAgAAAA==.',
Ty='Tyralen:BAAANQAECgUIBwAAAA==.Tyrandras:BAAANQAECgMIAwABNQAECgUIBwACAAAAAA==.Tyrïon:BAAANQAECgcIEAAAAA==.',
Un='Unlyfe:BAAANQAECgIIAgAAAA==.',
Va='Vaero:BAAANQADCggIDwAAAA==.Vandenar:BAAANQADCgUICAAAAA==.',
Vd='Vdarkadin:BAAANQADCgEIAQAAAA==.',
Ve='Vee:BAAANQADCgEIAQABNQAECgcIEAACAAAAAA==.Velyssa:BAAANQADCggIEwAAAA==.',
Vi='Vibin:BAAANQAECgUIBwAAAA==.Vineeshewah:BAAANQADCggIEwAAAA==.',
Vo='Voidguy:BAAANQADCggIEgAAAA==.',
Vu='Vulsted:BAAANQADCggIEQAAAA==.',
Vy='Vykx:BAAANQADCgMIBQAAAA==.',
Wa='Wantedd:BAAANQADCgMIBAABNQAECgQIBgACAAAAAA==.',
Wh='Whatapal:BAAANQADCgcIDQAAAA==.',
Wi='Wilbo:BAAANQAECgUICwABNQAECgkJGAAJAPAYAA==.Wily:BAAANQAECgEIAQAAAA==.Wisperwing:BAAANQADCggIFAAAAA==.',
Wo='Wolfdrudu:BAAANQADCgQIBgAAAA==.Worldfire:BAAANQAECgQIBQAAAA==.Wormadina:BAAANQADCgcIFQAAAA==.Wormszer:BAAANQADCgcIEQAAAA==.',
Wy='Wynds:BAABNQAECoEZAAIKAAkJyiYOAAAEBAAKAAkJyiYOAAAEBAAAAA==.Wyngs:BAAANQAECgYIBgABNQAECgkJGQAKAMomAA==.',
Xe='Xeres:BAAANQABCgIIBAAAAA==.',
Xi='Xi:BAAANQAECgMIAwAAAA==.Xiaozhi:BAEANQADCggIEwAAAA==.',
Xt='Xtend:BAAANQAECgEIAQAAAA==.',
Xz='Xzariana:BAAANQAECgEIAQAAAA==.',
Yo='Yoirr:BAAANQAECgIIAgAAAA==.',
Yu='Yuff:BAAANQADCggICAABNQAECgIIAwACAAAAAA==.',
['Yë']='Yëëter:BAAANQADCgQIBAAAAA==.',
Za='Zach:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.Zanori:BAAANQAECgQICQAAAA==.Zansijo:BAAANQADCgUIBQABNQAECgQICQACAAAAAA==.',
Zo='Zolajin:BAAANQADCgYICQAAAA==.Zorriya:BAABNQAECoEfAAISAAkJtiPEAQCeAwASAAkJtiPEAQCeAwAAAA==.Zoyn:BAAANQADCgYIBgAAAA==.',
Zy='Zygo:BAAANQADCggIDwAAAA==.',
['Ár']='Áries:BAAANQAECgMIBwAAAA==.',
['Êv']='Êvelyn:BAAANQADCgMIAwAAAA==.',
['Ít']='Ítsaßünny:BAAANQADCgQIBQAAAA==.',
['Ðe']='Ðemonic:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.Ðemonicßlaze:BAAANQADCggIEAABNQAECgEIAQACAAAAAA==.',
['Ýu']='Ýuno:BAAANQADCgYICAAAAA==.',
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
