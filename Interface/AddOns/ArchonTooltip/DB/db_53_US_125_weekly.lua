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

local lookup = {'Priest-Discipline','Priest-Holy','Priest-Shadow','Unknown-Unknown','Evoker-Devastation','Warrior-Protection','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Hunter-Marksmanship','Monk-Windwalker','Paladin-Retribution','DeathKnight-Unholy','DemonHunter-Devourer','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Rogue-Subtlety','Warlock-Demonology','Rogue-Assassination','Rogue-Outlaw','Monk-Brewmaster','Mage-Arcane','Druid-Balance','DemonHunter-Havoc','Hunter-BeastMastery','Paladin-Protection','Evoker-Preservation','Druid-Restoration',}
local provider = {region='US',realm="Jubei'Thos",name='US',type='weekly',zone=53,date='2026-09-15',data={Ad='Addelana:BAAANQADCgQIBAAAAA==.Adelanaa:BAABNQAECoEUAAQBAAYJDxInDAD1AAACAAYJpRFjQwB6AQABAAUJFQgnDAD1AAADAAEJJgHkUwAYAAABNQADCgQIBAAEAAAAAA==.Adrasta:BAAANQADCggIEQAAAA==.Adriell:BAAANQAECgUICwAAAA==.Adura:BAAANQADCgEIAQAAAA==.',
Ae='Aelathe:BAAANQAECgIIAgAAAA==.Aeneas:BAAANQAECggICQAAAA==.Aenimma:BAAANQAECggIDgAAAA==.Aerys:BAAANQADCggIDQAAAA==.',
Ak='Akey:BAAANQAECgQIBQAAAA==.',
Al='Alamwah:BAAANQADCgEIAQABNQAECgYICgAEAAAAAA==.Alaroo:BAAANQADCggICAAAAA==.Alatao:BAAANQABCgQIBAAAAA==.Aleinaas:BAAANQADCgYIBgAAAA==.Aleine:BAAANQAECgEIAQAAAA==.Alektra:BAAANQAECgYIDAAAAA==.Alexella:BAAANQADCgcICQAAAA==.Allerfala:BAAANQADCgQIBAABNQAECgkJGQAFAAUcAA==.Alliete:BAAANQADCgIIAgAAAA==.Allya:BAAANQAECgMIBQAAAA==.Aloine:BAAANQAECgYIDwAAAA==.Alteredbeast:BAAANQAECgQIBAAAAA==.',
Am='Amogus:BAAANQADCgUIBQAAAA==.Amoresh:BAAANQAECgQIBAAAAA==.Ampuzzible:BAAANQADCgcIBwABNQAECgEIAQAEAAAAAA==.',
An='Anchor:BAAANQABCgEIAgAAAA==.Anqu:BAAANQADCgMIAwAAAA==.',
Ar='Arbitera:BAAANQAECgYIDAAAAA==.Arkona:BAAANQADCgYICgABNQADCgcIDQAEAAAAAA==.Arvon:BAAANQAECgQIBQAAAA==.Arzir:BAABNQAECoEYAAIGAAkJAA8GCAARAgAGAAkJAA8GCAARAgAAAA==.',
As='Ashbringer:BAAANQAECgUIBQAAAA==.Asmonjoel:BAAANQADCgcICAAAAA==.Assumi:BAAANQADCggIEgAAAA==.',
At='Athenis:BAAANQAECgIIAgAAAA==.',
Au='Audree:BAAANQADCgYIBAAAAA==.Aurellia:BAAANQAECggICQAAAA==.',
Av='Avoide:BAAANQADCgYICgAAAA==.',
Ay='Aydy:BAAANQADCgYIBgAAAA==.',
Az='Azamat:BAAANQAECgIIAwAAAA==.Azuredemonx:BAAANQAECgYIDQAAAA==.',
Ba='Backup:BAAANQAECgQIDAAAAA==.Banan:BAAANQADCgYIBgAAAA==.',
Bb='Bbajer:BAAANQAECgEIAQAAAA==.Bbqporkbuns:BAABNQAECoEYAAIHAAkJnCD+AQBjAwAHAAkJnCD+AQBjAwAAAA==.',
Be='Bearzy:BAAANQAECgEIAgAAAA==.Bearzz:BAAANQAECgUICQAAAA==.Belledormi:BAAANQAECgQIBgAAAA==.Bellest:BAAANQAECgUICQAAAA==.Benji:BAABNQAECoEZAAMIAAgJmCNPDAAzAwAIAAgJmCNPDAAzAwAJAAYJvAq9YgAlAQAAAA==.',
Bf='Bfev:BAAANQAECgYICQAAAA==.',
Bg='Bggestthighs:BAAANQAECgQIBQABNQAECgcIIQAKAK8TAA==.',
Bi='Bid:BAAANQAECgQIBwAAAA==.Bigado:BAAANQADCggICgAAAA==.Bigalo:BAAANQAECgQIBAAAAA==.Bigarms:BAAANQADCgQIDAABNQAECgQIAwAEAAAAAA==.Bigfel:BAAANQABCgQIBAAAAA==.Biggesthighz:BAABNQAECoEhAAIKAAcJrxOaHADMAQAKAAcJrxOaHADMAQAAAA==.',
Bl='Blindanddeaf:BAAANQAECgQIBAAAAA==.Bluee:BAAANQAECgIIAgABNQAECgMIAwAEAAAAAA==.',
Bo='Boohbooh:BAAANQADCggIDQAAAA==.Boomakus:BAAANQAECgcIEgAAAA==.',
Br='Brannie:BAAANQAECgEIAgAAAA==.Brenine:BAAANQAECgEIAgAAAA==.Brewskie:BAAANQADCgEIAgAAAA==.Brodess:BAABNQAECoEaAAMIAAkJjiNFAwC2AwAIAAkJjiNFAwC2AwAJAAEJTwvbuQAvAAAAAA==.Brody:BAAANQAECgcIDwAAAA==.Bromorc:BAAANQADCgYIEQAAAA==.Broner:BAABNQAECoEYAAILAAcJdAw5GgCMAQALAAcJdAw5GgCMAQAAAA==.Bronlite:BAAANQADCgQICwAAAA==.Brotherlee:BAABNQAECoEVAAIMAAkJTRJ4NQAsAgAMAAkJTRJ4NQAsAgAAAA==.',
Bu='Bubski:BAAANQAECgEIAQAAAA==.Bulimio:BAAANQADCgIIAgAAAA==.Bunz:BAAANQADCgcIGAAAAA==.Buratt:BAAANQADCgYIEQAAAA==.',
['Bé']='Béllâ:BAAANQADCggIAgAAAA==.',
['Bõ']='Bõggie:BAAANQAECgYICgABNQAFFAYICwANAEUSAA==.',
Ca='Calabor:BAAANQADCgUIBQAAAA==.Capacitør:BAAANQAECgQIBwAAAA==.Cardib:BAAANQAECgcIEwAAAA==.Carlîn:BAAANQADCgYIBgAAAA==.Cattamend:BAAANQAECgcIDwAAAA==.Cattawrath:BAAANQAECgQIBAAAAA==.Cattazap:BAAANQAECgQICAAAAA==.Cauliflawer:BAAANQAECgQICQAAAA==.Cavoda:BAAANQADCgMIAwAAAA==.',
Ch='Chakrakhan:BAAANQAECgEIAwAAAA==.Char:BAAANQADCgYIBwAAAA==.Chase:BAAANQAECgMIBQAAAA==.Chinadh:BAACNQAFFIEGAAIOAAQJjw6dAwBPAQAOAAQJjw6dAwBPAQA1AAQKgRsAAg4ACQmIIB0GAEoDAA4ACQmIIB0GAEoDAAAA.Chinahunter:BAAANQABCgYICQABNQAFFAQIBgAOAI8OAA==.Chinamage:BAAANQAECgUIBwABNQAFFAQIBgAOAI8OAA==.Chopzuey:BAAANQADCgQICAAAAA==.Chugtiki:BAAANQAECgcIEgAAAA==.Chuunky:BAAANQABCgIIAgAAAA==.',
Ci='Cinderaz:BAAANQADCgYIEQAAAA==.',
Cl='Clikboomboom:BAAANQADCgUIBwAAAA==.',
Co='Cones:BAAANQADCgYICgABNQAECgQIAwAEAAAAAA==.Conesworth:BAAANQAECgYIDAAAAA==.Conesy:BAAANQADCgYIBAAAAA==.Coquina:BAAANQADCgYIBgAAAA==.Cordeilia:BAABNQAECoEeAAICAAkJQxNZKAAVAgACAAkJQxNZKAAVAgAAAA==.Cordi:BAAANQABCgEIAQAAAA==.Corruptax:BAAANQADCgcIDgAAAA==.Costiigan:BAAANQADCgYIBgAAAA==.',
Cr='Critsaquino:BAAANQAECgYICgAAAA==.Critsngigs:BAAANQAECgYIBgAAAA==.Crotchsniffa:BAAANQAECgEIAQAAAA==.Crowlêy:BAAANQABCgQICAABNQAECgYIDwAEAAAAAA==.',
Cy='Cyberlust:BAAANQADCggICAAAAA==.Cyklar:BAAANQADCgYIEQAAAA==.',
Da='Daddydevito:BAAANQAECgUIDAAAAA==.Daddythyme:BAAANQAECgYICgAAAA==.Dames:BAAANQADCgYIBgAAAA==.Danky:BAAANQADCggIHwAAAA==.Daqueta:BAAANQAECgQIBAAAAA==.Daquetawar:BAAANQAECgQIBAAAAA==.Darkniggura:BAAANQAECgMIAwAAAA==.Darknstormy:BAAANQADCgcIDQAAAA==.Darkpal:BAAANQAECggICQAAAA==.Dazzi:BAAANQADCgYIEgAAAA==.',
De='Deathdaddy:BAAANQADCgYIEwAAAA==.Decapitation:BAAANQAECgYIDgAAAA==.Deepkingz:BAAANQADCgUIBgAAAA==.Defacedd:BAAANQADCgYICgAAAA==.Deify:BAAANQAECgQIBgAAAA==.Deifyh:BAAANQADCgQIBQAAAA==.Deliaz:BAAANQADCgYIEQAAAA==.',
Di='Dismarryx:BAAANQAECgEIAgAAAA==.',
Dj='Djapana:BAAANQADCgYICAABNQADCgcIDQAEAAAAAA==.',
Dn='Dnomm:BAAANQADCgYIEQAAAA==.',
Do='Dogmuffin:BAAANQADCgMIAwAAAA==.',
Dr='Drakyon:BAAANQAECgEIAQAAAA==.Dreaddlord:BAAANQADCgQIBQABNQAECgQIBgAEAAAAAA==.Dreadiedude:BAAANQAECgQIBgAAAA==.Drowlie:BAAANQADCgYIBgABNQAECgMIAwAEAAAAAA==.',
Du='Durrin:BAAANQAECgMIAwAAAA==.Dutchman:BAAANQAECgEIAQAAAA==.',
Ef='Effectus:BAAANQAECgYIEAAAAA==.',
Ei='Eith:BAAANQAECgMIBAAAAA==.',
El='Elele:BAAANQABCgUIBQAAAA==.Eljay:BAAANQAECgUICQAAAA==.Ellell:BAABNQAECoEdAAIIAAYJagnmYAArAQAIAAYJagnmYAArAQAAAA==.Elliemental:BAAANQABCgYICgAAAA==.',
Em='Emberly:BAAANQADCgEIAQAAAA==.',
En='Endersfault:BAAANQAECgcIEgAAAA==.',
Ep='Epicdemoness:BAAANQAECgcIEAAAAA==.',
Er='Eroni:BAAANQAECgUIBgAAAA==.',
Eu='Euphea:BAAANQADCgYIBwAAAA==.',
Ev='Evaelfie:BAAANQAECgYIEgAAAA==.',
Fa='Farrand:BAAANQADCgQIBAAAAA==.',
Fe='Fearology:BAAANQADCgMIAwAAAA==.Felcollins:BAAANQADCgIIAQAAAA==.Felicia:BAAANQAECgYIDAAAAA==.Fellordkiki:BAAANQAECgcIEQAAAA==.',
Fi='Filthydh:BAAANQADCgYIBgABNQAECgkJGQAMAAwjAA==.Filthypally:BAABNQAECoEZAAIMAAkJDCMRBwCHAwAMAAkJDCMRBwCHAwAAAA==.Fivëam:BAAANQABCgIIAgAAAA==.',
Fl='Flashheart:BAAANQAECgEIAgAAAA==.Fleabag:BAAANQADCgYIDQAAAA==.',
Fo='Fossgate:BAAANQAECggICAABNQAECggIDgAEAAAAAA==.Foxe:BAEANQADCgMIAwABNQAECgEIAgAEAAAAAA==.',
Fr='Freezefauker:BAAANQAECgQIBgAAAA==.Fridge:BAAANQAECgQIBwAAAA==.Frostxfury:BAAANQAECgEIAgAAAA==.Frøstynips:BAACNQAFFIEOAAMPAAUJeBdxAQBXAQAPAAQJBBVxAQBXAQAQAAEJSSEMDwBiAAA1AAQKgTUAAw8ACQmeJakBAKgDAA8ACQkHJakBAKgDAA0ACQlQJCAIAEgDAAAA.',
Fu='Furysgrip:BAAANQAECgcIEgAAAA==.',
['Fì']='Fìsty:BAAANQADCgYIBgAAAA==.',
Ga='Gabagool:BAAANQAECgQICQAAAA==.Gaidal:BAAANQAECgIIAwAAAA==.Galafrey:BAAANQAECgEIAQABNQAECgcIEwAEAAAAAA==.Garaktou:BAAANQADCgQICAAAAA==.Gashweaver:BAAANQADCgMIAwAAAA==.',
Ge='Gekyum:BAABNQAECoEfAAIKAAkJriKbAgCQAwAKAAkJriKbAgCQAwAAAA==.Getinmyspit:BAAANQAECgQIBQAAAA==.',
Gh='Ghazgkhull:BAAANQADCgYIBgAAAA==.',
Gi='Gidyana:BAAANQAECgMIAwAAAA==.Girlsdayoni:BAAANQAECgQICAAAAA==.Girlsnight:BAAANQADCgQIBwAAAA==.',
Gl='Glancelot:BAAANQAECgMIBgAAAA==.Glipglorp:BAAANQADCgQIBAAAAA==.',
Gn='Gnurse:BAAANQADCgcICAAAAA==.',
Go='Gommo:BAAANQAECgUICQAAAA==.Gorbad:BAAANQAECgEIAQAAAA==.',
Gr='Greggoryy:BAAANQABCgQICQAAAA==.Groundizzle:BAAANQAECgcICwAAAA==.',
Gt='Gtoromu:BAAANQADCgcIDQAAAA==.',
Gu='Guanyu:BAAANQAECgEIAQAAAA==.Guccisosa:BAAANQADCgYIBgAAAA==.Guineamon:BAAANQADCgEIAQAAAA==.',
Ha='Haruk:BAAANQAECgcIEQAAAA==.',
He='Heatfist:BAAANQAECgUICQAAAA==.Helldridge:BAAANQAECgEIAQAAAA==.Heåls:BAAANQAECgQIBgAAAA==.',
Ho='Hoelishock:BAAANQAECgEIAQAAAA==.Hollynova:BAAANQAECgEIAQAAAA==.Holychad:BAAANQAECgcIEgAAAA==.Honeydew:BAACNQAFFIEIAAILAAQJ8As4AwAZAQALAAQJ8As4AwAZAQA1AAQKgSgAAgsACQnzINkEADkDAAsACQnzINkEADkDAAAA.Honganteresa:BAAANQAECgYIBgAAAA==.Hoofmax:BAAANQADCgYICAAAAA==.Hotteemie:BAAANQADCgYIBgAAAA==.',
['Hø']='Høtdøts:BAAANQAECgEIAQAAAA==.',
If='Ifrit:BAAANQAECgIIAwABNQAECgkJHgARAPwiAA==.',
Il='Illidank:BAAANQAECgQICAAAAA==.',
Im='Imanoob:BAAANQADCgUIBQAAAA==.Imperiex:BAAANQADCgEIAQAAAA==.',
In='Infectedlock:BAAANQAECgYIBgABNQAFFAQIBgAOAI8OAA==.Inurdreams:BAAANQABCgcICAAAAA==.',
Io='Ionsw:BAAANQAFFAEIAQAAAA==.',
Ip='Ipsifu:BAAANQAECgEIAQABNQAECgkJHAASAHwjAA==.',
Ir='Ironski:BAAANQADCgcICAAAAA==.',
Ja='Jackillz:BAAANQADCgUIBQABNQAECgYIDAAEAAAAAA==.Jatzsy:BAAANQAECgMIBQAAAA==.Jayar:BAAANQAECgIIAwAAAA==.Jazzy:BAAANQADCgUIBQAAAA==.',
Je='Jee:BAAANQAECgQIBQAAAA==.Jescon:BAAANQAECgIIAgAAAA==.Jeé:BAAANQADCgUIBQAAAA==.',
Ji='Jiamil:BAAANQAECgUIDwAAAA==.Jigolow:BAAANQADCgUIBQAAAA==.',
Jo='Johlissa:BAAANQAECgIIAgAAAA==.',
Ju='Jubber:BAAANQAECgQIBwAAAA==.',
Ka='Kadashy:BAAANQAECgYICQAAAA==.Kadashyy:BAAANQAECgIIAgABNQAECgYICQAEAAAAAA==.Kaherd:BAAANQAECgEIAgAAAA==.Kamikasi:BAAANQADCggICwAAAA==.Kaneshiro:BAAANQAECgQICAAAAA==.Karytheca:BAAANQADCgYIBAAAAA==.Katae:BAAANQAECgYIEAAAAA==.Kayrali:BAAANQADCgIIAgAAAA==.',
Kb='Kboomz:BAAANQADCgYIBgABNQADCgcIDQAEAAAAAA==.',
Ke='Kegaz:BAAANQAECgMIAwAAAA==.Kegward:BAAANQADCgUIBQAAAA==.Kelynada:BAABNQAECoEWAAITAAYJdBARUQCHAQATAAYJdBARUQCHAQAAAA==.Kendd:BAACNQAFFIEKAAMSAAUJWxEEAgDJAQASAAUJWxEEAgDJAQAUAAEJNgmMCQBXAAA1AAQKgSEABBIACQlfHy8DAE4DABIACQk8HS8DAE4DABUABwlCEMcHAK0BABQAAgmXFgE5AJsAAAAA.Kerrigân:BAAANQAECgIIAgAAAA==.',
Ki='Kindra:BAAANQADCgYIBgAAAA==.Kithari:BAAANQAECgQIBgAAAA==.',
Kn='Knickerbits:BAAANQABCgEIAQAAAA==.Knotting:BAAANQADCggIFgAAAA==.',
Ko='Kochez:BAAANQADCgQIBAAAAA==.Kollateral:BAAANQADCgYICwAAAA==.',
Kr='Krankiekunt:BAABNQAECoEaAAIWAAkJeCA/AgA0AwAWAAkJeCA/AgA0AwAAAA==.Krellhim:BAAANQAECgIIAQAAAA==.',
Ku='Kuanija:BAAANQAECgcIDwAAAA==.Kuuga:BAAANQAECgIIBAAAAA==.',
La='Landwalker:BAAANQAFFAEIAQAAAA==.Langas:BAAANQAECgIIAQABNQAECggIBgAEAAAAAA==.Langasbrew:BAAANQAECggIBgAAAA==.Latorius:BAAANQAECgUICgAAAA==.Lavaloadz:BAAANQADCggIDQAAAA==.Lazziel:BAAANQADCgcIDQAAAA==.',
Le='Lexavis:BAABNQAECoEfAAMMAAkJWiHiFQDyAgAMAAkJWiHiFQDyAgARAAYJuSGFIwBOAgABNQAECgYIEQAEAAAAAA==.Leyiast:BAAANQAECgQIBgAAAA==.Leyissa:BAAANQADCgIIAgABNQAECgQIBgAEAAAAAA==.',
Lh='Lheo:BAAANQADCgYICAAAAA==.',
Li='Liggma:BAAANQAECgQICAAAAA==.Lightborn:BAAANQADCggICAAAAA==.Lilwhite:BAAANQAECgYICgAAAA==.',
Lo='Lockaboom:BAAANQAECgMIAwAAAA==.Loldruid:BAAANQAECgQIBgAAAA==.Lom:BAAANQAECgcIDQAAAA==.Lomzz:BAAANQADCgIIAgAAAA==.',
Lu='Lukie:BAEANQAECgIIAgAAAA==.',
Ly='Lycan:BAAANQADCgEIAQAAAA==.Lym:BAAANQADCgQIBAAAAA==.Lynarium:BAAANQAECgEIAQAAAA==.Lyradaeris:BAAANQABCgIIAgAAAA==.',
['Lÿ']='Lÿrath:BAAANQADCggIDgAAAA==.',
Ma='Magepill:BAAANQADCgQIBAAAAA==.Magharitta:BAAANQAECgUICwAAAA==.Mahwae:BAAANQADCgIIAwAAAA==.Makavelli:BAAANQADCgIIAgAAAA==.Manoliso:BAAANQAECgEIAQAAAA==.',
Me='Medesin:BAAANQADCgYIEQAAAA==.Mekhanite:BAAANQAECgQIBgAAAA==.',
Mi='Milspec:BAAANQAECgYIDAAAAA==.Minami:BAAANQAECgQIBgAAAA==.Minhiriath:BAAANQADCgQIBAAAAA==.Mintbadger:BAAANQADCgUIBwAAAA==.Mistea:BAAANQADCgMIAwAAAA==.',
Mo='Mochimask:BAAANQADCgIIAgAAAA==.Moetown:BAAANQADCggICAABNQAECgkJLgAXAHEgAA==.Moistmaker:BAAANQAECgYIEwAAAA==.Mold:BAAANQAECgEIAQAAAA==.Momotaku:BAAANQAECgYICQAAAA==.Monalisa:BAAANQAECgMIAwAAAA==.Monkmon:BAAANQADCgIIAgABNQAECgQIBwAEAAAAAA==.Moonoo:BAAANQADCgUIBQAAAA==.Mordok:BAAANQAECgEIAQAAAA==.Morena:BAAANQADCgcIDQAAAA==.Morgaina:BAAANQADCgcIDQAAAA==.',
Mu='Muscleclub:BAAANQAECgcIDQAAAA==.',
My='Mysticalzz:BAAANQADCgQIBAAAAA==.',
['Më']='Mëmëmë:BAAANQAECgEIAQAAAA==.',
['Mü']='Müddrätt:BAAANQADCgIIAgAAAA==.',
Na='Naeff:BAAANQAECgQIAQAAAA==.Natria:BAAANQAECgUIBwAAAA==.Naya:BAAANQAECgYIEAAAAA==.',
Ne='Nerfdehoof:BAAANQADCggICQAAAA==.Nerfdelag:BAAANQAECgQIBwAAAA==.Nerfgün:BAAANQAECgcIEwAAAA==.',
Ni='Nicodautroc:BAAANQADCgQIBgABNQAECgMIBQAEAAAAAA==.Nintone:BAAANQAECgQIBgAAAA==.',
No='Nonippies:BAAANQAECgMIBAAAAA==.Noolie:BAAANQADCgIIAgABNQAECgMIAwAEAAAAAA==.',
Ns='Nsi:BAAANQADCgUICAAAAA==.',
Nu='Nubishe:BAAANQAECgMIAwAAAA==.Nutsdormu:BAAANQAECgQIDgAAAA==.',
Ny='Nythe:BAAANQADCgEIAQABNQADCgIIAgAEAAAAAA==.Nyxmoona:BAAANQADCgYIEQAAAA==.',
['Nà']='Nàishà:BAAANQADCggIEAAAAA==.',
Ob='Obskurer:BAAANQAECggICwAAAA==.',
Od='Odinwolf:BAAANQAECgMIBQABNQAECgkJHgARAPwiAA==.',
Oj='Ojisancage:BAABNQAECoEZAAITAAYJVRm6PQDXAQATAAYJVRm6PQDXAQAAAA==.',
Om='Omnitract:BAAANQADCgUIBQAAAA==.',
Or='Orinys:BAAANQAECgEIAgAAAA==.Orkky:BAAANQAECgYIDAAAAA==.',
Pa='Page:BAAANQAECgYIDwAAAA==.Pakurruun:BAAANQAECgEIAgAAAA==.Palala:BAAANQADCgcIBwABNQAECgQIBgAEAAAAAA==.Pallatress:BAAANQADCgYIEQAAAA==.Pandor:BAAANQAECgEIAQAAAA==.Panginoon:BAAANQAECgcIEQAAAA==.Paparìch:BAABNQAECoEVAAIYAAgJiyCxEwC/AgAYAAgJiyCxEwC/AgAAAA==.Paphio:BAAANQADCggIDAAAAA==.',
Pe='Perden:BAAANQADCgYIBgAAAA==.Pesh:BAAANQADCgYIDQAAAA==.',
Pg='Pgundry:BAAANQADCggIFwAAAA==.',
Ph='Phakin:BAAANQADCgMIAwAAAA==.Phexides:BAAANQAECgMIAwAAAA==.',
Pi='Piddlesworth:BAAANQADCggIFwAAAA==.Pinkyblue:BAAANQAECggIEwAAAA==.Pipssqeek:BAAANQADCgcIDwAAAA==.',
Pj='Pjw:BAABNQAECoEeAAIRAAkJmBU+FwClAgARAAkJmBU+FwClAgAAAA==.',
Pl='Plarrior:BAAANQADCgMIAwAAAA==.Plip:BAABNQAECoEkAAMIAAcJtRudJABQAgAIAAcJtRudJABQAgAJAAEJjgPJwgAkAAAAAA==.',
Po='Pokerrface:BAAANQADCggICAAAAA==.Polloloco:BAAANQADCgEIAQAAAA==.Poobumhead:BAAANQAECgEIAgAAAA==.Porkroll:BAAANQABCgIIAgAAAA==.Poweredman:BAAANQADCgIIAgAAAA==.Powerheal:BAAANQAECgEIAQAAAA==.',
Pr='Prftlybalncd:BAAANQAECgYIEAABNQAECgkJHgARAJgVAA==.Probabele:BAAANQAECgEIAQAAAA==.Probably:BAACNQAFFIEOAAMPAAUJvBgGBAC5AAAPAAQJeRsGBAC5AAAQAAEJyA0AAAAAAAA1AAQKgToABA8ACQnyI8gBAKMDAA8ACQnyI8gBAKMDABAAAQn/HEN2AFUAAA0AAQnnE3x3AEwAAAAA.Protato:BAAANQADCggICAAAAA==.',
Ps='Psyche:BAAANQADCgYIBgAAAA==.',
Pt='Ptrie:BAAANQAECgQIBgAAAA==.',
Pu='Pudgeyp:BAAANQAECggIEgAAAA==.Pudgeyr:BAAANQAECgIIAQAAAA==.Punj:BAAANQAECgIIAwAAAA==.Puntarr:BAAANQADCgYIEwAAAA==.Puppybonks:BAAANQAECgIIAgAAAA==.Purdxpriest:BAAANQABCggICAAAAA==.Purdxwarrior:BAAANQABCgQIBQABNQABCggICAAEAAAAAA==.',
Pw='Pwrbottom:BAAANQAECgQIAwAAAA==.',
Qi='Qibla:BAAANQAECgYICwAAAA==.',
Qu='Quarizma:BAACNQAFFIEGAAIKAAQJFx7RAwCCAQAKAAQJFx7RAwCCAQA1AAQKgSYAAgoACQnsI6YBALEDAAoACQnsI6YBALEDAAAA.',
Ra='Radiantbunz:BAAANQADCggIEgAAAA==.Rankone:BAAANQAECgMIAwABNQAECgQIBgAEAAAAAA==.Raxe:BAEANQAECgEIAgAAAA==.',
Re='Reaperoffire:BAAANQADCggIFwAAAA==.Repliod:BAAANQAECgQICAAAAA==.Reploid:BAAANQADCgcIBwABNQAECgQICAAEAAAAAA==.Restho:BAAANQAECgUIDwAAAA==.Revarix:BAAANQAECgYICQAAAA==.',
Rh='Rhaella:BAAANQAECgQIBgAAAA==.Rhuiser:BAAANQAECgYIEwAAAA==.Rhuno:BAAANQAECgQICAAAAA==.',
Ri='Rigormortits:BAAANQADCgcIBwABNQAECgQICAAEAAAAAA==.Ritsuki:BAAANQAECgQIBAAAAA==.Ritéboys:BAAANQAECgIIAwABNQAECgcIEgAEAAAAAA==.Ritëboys:BAAANQAECgcIEgAAAA==.',
Ro='Rocketjuice:BAAANQAECgYIDgAAAA==.Roflpwnnt:BAAANQAECgEIAQAAAA==.',
Ru='Rutee:BAAANQAECgYIDgAAAA==.',
Sa='Saethene:BAAANQAECgEIAQABNQAECgcIEwAEAAAAAA==.Safh:BAAANQADCggICQAAAA==.Safk:BAAANQAECgYIDgAAAA==.Saleina:BAAANQADCgIIAwAAAA==.Sandiwang:BAAANQADCgIIAgAAAA==.Sanosanz:BAAANQAECgEIAQAAAA==.Saptko:BAAANQADCgUIBQAAAA==.Sartoc:BAAANQAECgMIBAABNQAECgcIEwAEAAAAAA==.',
Sc='Scabbo:BAAANQAECgMIBAAAAA==.Scalesoul:BAAANQAECgcIEQAAAQ==.',
Sd='Sdfgoose:BAAANQAECgEIAgAAAA==.',
Se='Seiferoth:BAABNQAECoEeAAIRAAkJ/CJIAwCPAwARAAkJ/CJIAwCPAwAAAA==.Selitha:BAAANQABCgIIAgAAAA==.Senddori:BAAANQADCgUIBQAAAA==.Sergantcolen:BAAANQAECgUIBgAAAA==.Señornanna:BAAANQADCgQIBAAAAA==.',
Sh='Shaddai:BAAANQAECgQIBgAAAA==.Shadowofevil:BAAANQAECgQIBQAAAA==.Shakywing:BAAANQADCgIIAgAAAA==.Shalavoo:BAAANQAECgIIAgAAAA==.Shamankiller:BAAANQAECgMICAAAAA==.Shamazzle:BAAANQAECgMIBAAAAA==.Shamlen:BAAANQAECgYIDgAAAA==.Shichokeme:BAAANQADCgMIAwAAAA==.Shiicho:BAAANQADCgYICQAAAA==.Shinieedruid:BAAANQAECgcICwAAAA==.Shions:BAAANQADCgYIBgAAAA==.Shockostoob:BAAANQAECgQIBgAAAA==.',
Si='Sidatas:BAAANQADCggICwAAAA==.Silverspulse:BAAANQAECgYIDQAAAA==.Sinequanon:BAABNQAECoEYAAMDAAgJIBMRGgDJAQADAAYJvhgRGgDJAQACAAQJthPsXgD2AAAAAA==.Sinfulbeast:BAAANQAECgYIDwAAAA==.Sippycup:BAAANQAECgEIAQABNQAECgcIEQAEAAAAAA==.',
Sk='Skrogan:BAAANQABCgQICAAAAA==.Skulv:BAABNQAECoEgAAMOAAkJgCEyBwAyAwAOAAgJ+CIyBwAyAwAZAAIJchVHPwCYAAAAAA==.',
Sl='Slakzor:BAAANQADCgQIAwAAAA==.Slammed:BAAANQAECgQIBwAAAA==.Sleepyshark:BAAANQAECgYICQAAAA==.Slopain:BAAANQAECgQIBwAAAA==.Slåppery:BAABNQAECoEYAAIKAAkJAh0vBgA1AwAKAAkJAh0vBgA1AwAAAA==.',
Sm='Smashy:BAAANQADCggIEQAAAA==.Smìtty:BAAANQADCgMIBAAAAA==.',
Sn='Snorlax:BAAANQAECgYIDAAAAA==.Snort:BAAANQAECgQIBwAAAA==.',
So='Sona:BAAANQAECgYIBgAAAA==.Sonotafurry:BAAANQADCgYIBgAAAA==.Soresu:BAAANQADCggICgAAAA==.Soundwit:BAAANQAECgQICQAAAA==.',
Sp='Sparrowstalk:BAAANQADCgEIAQAAAA==.Spindrift:BAAANQAECgMIBgAAAA==.Spoonyy:BAABNQAECoEaAAIXAAkJfB9FMADQAgAXAAkJfB9FMADQAgAAAA==.',
Sq='Squanchie:BAAANQAECgEIAQABNQAECgQIBgAEAAAAAA==.',
St='Steinlarger:BAAANQAECgQIBAAAAA==.Stephen:BAAANQAECgQIBAAAAA==.Storrmbender:BAAANQAECgYIDgAAAA==.Stoutbrew:BAAANQADCggICQAAAA==.Strípe:BAAANQAECgQIBAAAAA==.Stuy:BAABNQAECoEWAAIKAAgJ3xApFwAbAgAKAAgJ3xApFwAbAgAAAA==.Stãria:BAAANQAECgQIBAAAAA==.Störme:BAAANQADCgQICAAAAA==.',
Su='Sugarburst:BAAANQAECgIIAgAAAA==.Sukmahdisc:BAAANQADCggICAAAAA==.',
Sw='Swak:BAABNQAECoEbAAIaAAcJrRYaNwAcAgAaAAcJrRYaNwAcAgAAAA==.Sweet:BAAANQAECgMIAQAAAA==.Switchmage:BAAANQADCggICAAAAA==.Switchskin:BAABNQAECoEYAAIYAAkJshroFACwAgAYAAkJshroFACwAgAAAA==.',
Sy='Syvrogue:BAAANQAECgcIDQABNQAECgEIAQAEAAAAAA==.',
Ta='Tallinor:BAAANQAECgEIAgAAAA==.Tanags:BAAANQAECgQIBgAAAA==.Tankakus:BAAANQADCgMIAwAAAA==.Taumast:BAAANQADCgMIAwABNQAECgcICwAEAAAAAA==.Tauter:BAAANQADCgYIDgAAAA==.Tazzee:BAAANQADCgYIDAAAAA==.',
Te='Temperature:BAAANQAECgEIAQABNQAECgEIAwAEAAAAAA==.Testaxltesta:BAAANQAECgYIBgABNQADCggIDgAEAAAAAA==.',
Th='Thael:BAAANQADCgQIBAAAAA==.Thalia:BAAANQAECgYIEQAAAA==.Thoriatit:BAAANQAECgMIAwAAAA==.Thottydot:BAAANQAECgEIAQAAAA==.Thox:BAAANQADCgIIAgAAAA==.Thyranux:BAAANQADCgMIBAAAAA==.',
Ti='Tienchi:BAAANQAECgYIDAAAAA==.Tierk:BAAANQADCggICAABNQAECgYIDwAEAAAAAA==.Tim:BAAANQAECgYIEAAAAA==.',
Tl='Tlo:BAAANQADCgcIBwABNQAECgkJIgAaABYjAA==.',
To='Tollmemaybe:BAABNQAECoEeAAMbAAgJ3yDsBADwAgAbAAgJ3yDsBADwAgAMAAEJ9AgN7wAxAAAAAA==.Tormént:BAAANQAECgcIEQAAAA==.',
Tr='Transport:BAAANQAECgEIAwAAAA==.Traumatizer:BAAANQADCggIDQAAAA==.Trenbolone:BAAANQADCgIIAwAAAA==.Tronix:BAAANQAECgUICAAAAA==.Trucidario:BAAANQADCgYIBgAAAA==.Truwar:BAAANQAECgcICgAAAA==.',
Tu='Tubbquake:BAAANQAECgcIDwAAAA==.',
Tw='Twatasaurus:BAAANQADCgcIFAAAAA==.',
['Tî']='Tîmmeh:BAAANQAECgYIDAAAAA==.',
Ub='Ubica:BAAANQAECgcIEAAAAA==.',
Un='Unholykníght:BAAANQADCgEIAQAAAA==.Unvoid:BAAANQAECgIICAAAAA==.',
Ur='Urzog:BAAANQADCgUIBQAAAA==.',
Us='Useacooldown:BAAANQAECgQIAwAAAA==.',
Va='Valentine:BAAANQAECgcIDgAAAA==.Valithor:BAAANQAECgIIAwAAAA==.Valkyrion:BAABNQAECoEeAAIcAAkJdiFrAgBnAwAcAAkJdiFrAgBnAwAAAA==.Valysan:BAAANQADCgEIAQAAAA==.Vann:BAAANQADCgMIAwAAAA==.',
Ve='Velathri:BAAANQAECgEIAQAAAA==.Velenlerolan:BAABNQAECoEfAAINAAkJniR+AgC6AwANAAkJniR+AgC6AwAAAA==.Velrayne:BAAANQAECgUICwAAAA==.Veng:BAAANQABCgQIBAAAAA==.Verailde:BAAANQADCgUICQAAAA==.Verathriel:BAAANQABCgQIBgAAAA==.Verilence:BAAANQAECgYIDwAAAA==.Veventhius:BAAANQADCgIIAgAAAA==.Vext:BAAANQADCgMIAwAAAA==.',
Vi='Vindicor:BAAANQADCgQICAAAAA==.',
Vo='Voidberg:BAAANQAECgQIBAABNQAECggIGwAdAPsbAA==.Vorndryad:BAAANQADCgcIFAAAAA==.',
Vy='Vynburn:BAAANQAECgcIEQAAAA==.',
Wa='Warmon:BAAANQADCggIEQAAAA==.Watson:BAAANQAECgMIBQAAAA==.Waveryy:BAAANQADCgMIBgAAAA==.',
We='Wemblitz:BAAANQADCgUICwAAAA==.Wesh:BAABNQAECoEYAAINAAgJsRpuGACAAgANAAgJsRpuGACAAgAAAA==.',
Wh='Whio:BAAANQAECgQIBwAAAA==.Whitetabby:BAAANQADCggICAAAAA==.Whtclass:BAAANQAECgMIAwAAAA==.',
Wi='Wintersfence:BAAANQADCgYICAAAAA==.',
Wk='Wkwk:BAAANQAECgQIBwAAAA==.',
Wp='Wpd:BAABNQAECoEYAAIYAAkJzBvmDQAJAwAYAAkJzBvmDQAJAwAAAA==.',
['Wî']='Wîngman:BAAANQAECgUIDAAAAA==.',
Xe='Xenarn:BAEANQAECgEIAgAAAA==.Xenoruin:BAAANQAECgQIBgAAAA==.',
Xi='Xiphios:BAAANQADCgYIBgAAAA==.',
Ya='Yarpidk:BAAANQADCgcICQAAAA==.',
Yo='Yorkie:BAABNQAECoEdAAIXAAkJMR1DJAABAwAXAAkJMR1DJAABAwAAAA==.Yoyogi:BAAANQADCgYIBwAAAA==.',
Yu='Yui:BAAANQADCggICAAAAA==.Yurarzir:BAAANQAECgcIEAAAAA==.',
Za='Zanisha:BAAANQAECgEIAgAAAA==.Zaz:BAAANQADCgYIBgAAAA==.',
Ze='Zelendorm:BAAANQAECgYIDAAAAA==.',
Zu='Zula:BAAANQADCgcIBwABNQAECgMIAwAEAAAAAA==.',
['ßa']='ßaccycønes:BAAANQADCggIEwAAAA==.',
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
