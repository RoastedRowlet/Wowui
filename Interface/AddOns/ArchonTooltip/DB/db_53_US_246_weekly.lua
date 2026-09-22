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

local lookup = {'Warlock-Affliction','Hunter-BeastMastery','DemonHunter-Havoc','Druid-Restoration','Druid-Balance','Unknown-Unknown','Paladin-Retribution','Rogue-Subtlety','Druid-Guardian','Druid-Feral','Hunter-Marksmanship','Warrior-Arms','DemonHunter-Devourer','Shaman-Restoration','Priest-Shadow','Paladin-Holy','Rogue-Assassination','Priest-Holy','Evoker-Preservation','Shaman-Elemental','Warrior-Protection','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Demonology','Mage-Arcane','Warlock-Destruction','Shaman-Enhancement',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaron:BAAANQAECgIIAgABNQAECgcJFwABAL4dAA==.Aaronfreeze:BAABNQAECoEbAAICAAgKQyJ0EwAJAwACAAgKQyJ0EwAJAwAAAA==.',
Ab='Abnar:BAAANQAECgMIBAAAAA==.',
Ad='Adversaryq:BAAANQADCgYIBwAAAA==.',
Ai='Aid:BAAANQADCgMIBQAAAA==.',
Al='Alanii:BAAANQAECgUIBQAAAA==.Alaula:BAAANQAECgQIBAAAAA==.Albedô:BAAANQADCgIIBAABNQAECggIGwADAEUiAA==.Allformarc:BAAANQAECgUJBgAAAA==.Allmaick:BAAANQADCggJDAAAAA==.Alucard:BAAANQAECgYIDgAAAA==.Alystrasza:BAABNQAECoEYAAMEAAgKzRprFgAJAgAEAAcKDxlrFgAJAgAFAAcKJQ0pPACRAQAAAA==.',
Am='Ambivalent:BAAANQADCgQIBAABNQAECgQJDAAGAAAAAA==.',
An='Animan:BAAANQABCgIIAgAAAA==.Antimovsky:BAAANQAECgQICQAAAA==.',
Ap='Aphroditê:BAAANQADCgQIBAABNQAECgYJDwAGAAAAAA==.',
Av='Aviaria:BAAANQAECgEIAQAAAA==.',
Ax='Axsenaea:BAAANQADCgEIAQAAAA==.',
['Aì']='Aìnzooalgown:BAAANQAECgcIDgABNQAECggIGwADAEUiAA==.',
['Aü']='Aütöpsy:BAAANQAECgcIDQAAAA==.',
Ba='Babylonfive:BAABNQAECoEjAAIHAAkKQiDWDgBdAwAHAAkKQiDWDgBdAwAAAA==.Backstabbath:BAAANQADCgQIBQAAAA==.Banger:BAAANQAECgIIAwAAAA==.',
Be='Belleta:BAAANQAECgEIAgAAAA==.Belligerente:BAAANQAECgQJDAAAAA==.Berserk:BAEANQAECgUJCwABNQAECgkJIAAIAA4UAA==.',
Bi='Bigwilli:BAAANQADCgYIDQAAAA==.Birds:BAABNQAECoEYAAMJAAkKAR/UAwD3AgAJAAkKrhzUAwD3AgAKAAcKfRdVCQAEAgAAAA==.Biscuit:BAABNQAECoEZAAMCAAgKQSNNIwCrAgACAAcKZCZNIwCrAgALAAYKlBmoIgDEAQAAAA==.Bisha:BAABNQAECoEkAAIMAAgKpxcuSwA8AgAMAAgKpxcuSwA8AgAAAA==.Bizcocho:BAAANQAECgMIAwAAAA==.',
Bo='Bonesofdoom:BAAANQADCgEIAQAAAA==.Boomkingobrr:BAAANQAECgYJCQAAAA==.Boops:BAAANQAFFAEIAQAAAA==.Bootysweatt:BAAANQADCggICAAAAA==.Boss:BAAANQAECgUICgAAAA==.',
Bu='Buckayou:BAAANQADCgUIBwAAAA==.Burnsx:BAAANQADCgYIDwABNQAFFAYJDgANAIYdAA==.',
Bw='Bwoar:BAAANQADCggIEAAAAA==.',
Ca='Caiandol:BAAANQADCgQIAwAAAA==.Candydreams:BAAANQABCgQIBAAAAA==.Captinfeo:BAAANQADCggICAAAAA==.Captnmurloc:BAAANQAECgUICwAAAA==.Catara:BAAANQADCgcICwAAAA==.',
Ce='Cedar:BAAANQADCgYICwAAAA==.',
Ch='Cheetos:BAAANQADCggICAAAAA==.Cherga:BAAANQAECgQJCAAAAA==.Chrinn:BAAANQABCgUIBQAAAA==.Church:BAAANQAECgQIBgAAAA==.',
Ci='Cirxe:BAAANQAECgUJDAAAAA==.',
Cl='Clarkent:BAAANQAECgMJAwAAAA==.',
Co='Coms:BAAANQAECgUJCgAAAA==.',
['Cø']='Cønstance:BAAANQAECgQICAAAAA==.',
Da='Dabai:BAABNQAECoEcAAIHAAcK8hK+ZgDJAQAHAAcK8hK+ZgDJAQAAAA==.Daipailaotie:BAAANQAECgYIEAAAAA==.Dalight:BAAANQAECgQJBwAAAA==.Dankins:BAABNQAFFIEHAAIOAAUKjBxOAwDUAQAOAAUKjBxOAwDUAQAAAA==.Darealfarmer:BAAANQADCgYJBgAAAA==.Darkzoomies:BAAANQAECgMJAwAAAA==.',
De='Dethsent:BAAANQAECgIJAgAAAA==.Dette:BAAANQAECgMIBAAAAA==.Devourer:BAABNQAECoEoAAINAAkK7BgFDQDkAgANAAkK7BgFDQDkAgAAAA==.',
Dk='Dkboss:BAAANQADCgYIEQABNQAECgQICgAGAAAAAA==.',
Do='Doctrdoom:BAAANQADCggICAABNQAECgcJFwABAL4dAA==.',
Dr='Drafted:BAAANQAECgYJDQAAAA==.Dragondank:BAAANQAFFAEIAgABNQAFFAUIBwAOAIwcAA==.Drukah:BAAANQADCgcIDAAAAA==.',
Dt='Dtrike:BAAANQAECgIIBAAAAA==.',
Ed='Edstark:BAAANQAECgQIDgAAAA==.',
El='Elabernathy:BAAANQAECgEJAgAAAA==.Elenay:BAAANQAECgUIDwAAAA==.Elliemental:BAAANQADCgQIBAAAAA==.Elpatron:BAABNQAECoEeAAIEAAgKrx4YCwC7AgAEAAgKrx4YCwC7AgAAAA==.Elylanea:BAAANQADCggICAAAAA==.',
Em='Emulsdeath:BAAANQAECgcIEwABNQAECggIMAAHABcmAA==.Emulsifier:BAABNQAECoEwAAIHAAgKFyYICwB+AwAHAAgKFyYICwB+AwAAAA==.Emulslash:BAAANQADCgYJDAABNQAECggIMAAHABcmAA==.',
Ev='Evideia:BAAANQADCgQJBAABNQAECgYJDwAGAAAAAA==.',
Ex='Expiredbeef:BAAANQADCgYIBgAAAA==.',
Fa='Farcha:BAAANQADCgIIAgABNQADCggIDQAGAAAAAA==.',
Fi='Finester:BAAANQAECgYICwAAAA==.',
Fl='Flatline:BAAANQADCgMIBgAAAA==.',
Fu='Funslinger:BAAANQADCggICgAAAA==.',
Ga='Gagners:BAAANQAECgIIBAABNQAECggIMAAHABcmAA==.',
Go='Gorska:BAAANQAECgYIDgAAAA==.',
Gr='Grawm:BAAANQAECgYIDgAAAA==.Gritshaman:BAAANQAECgQJBAABNQAECgcJFwABAL4dAA==.',
['Gä']='Gämbit:BAAANQAECgMIAwAAAA==.',
Ha='Hangman:BAAANQAECgYJDQAAAA==.Hanni:BAAANQADCggJIQAAAA==.Hawktoetem:BAAANQADCgQIBAAAAA==.Hawktoouh:BAAANQAECgYICgAAAA==.',
He='Hellshand:BAAANQAECgIIBAAAAA==.Helmhammer:BAAANQAECgEIAQAAAA==.',
Ho='Holychaser:BAAANQAECgMJBwAAAA==.Holycrack:BAAANQAECgUIBQABNQAECgYJEQAGAAAAAA==.Holycøw:BAAANQAECgEJAQAAAA==.Holyfyree:BAAANQADCgIIAgABNQAECgcIDAAGAAAAAA==.Holypawk:BAAANQAECgYIBwAAAA==.Holyrock:BAAANQAECgEJAwAAAA==.Honorheart:BAAANQADCgMIBgAAAA==.',
['Hó']='Hóly:BAAANQADCgEJAQABNQAECgYJCQAGAAAAAA==.',
Ih='Ihureciv:BAAANQAECgQICwABNQAECggJMgAPAFgiAA==.',
Ik='Ikur:BAABNQAECoEZAAIQAAgK+xvUHACuAgAQAAgK+xvUHACuAgAAAA==.',
Ip='Ipopkidneys:BAACNQAFFIEIAAMIAAUKKyHTAwCUAQAIAAQKOiDTAwCUAQARAAEK8iRsCgBqAAA1AAQKgR4AAwgACQoMJV8HAOMCAAgABwoIJl8HAOMCABEABAotI8kqAIEBAAAA.',
Ir='Iroi:BAAANQAECgIJAgAAAA==.',
Is='Iskur:BAAANQAECgUIBwABNQAECggIGQAQAPsbAA==.Isurr:BAAANQAECgQIBQABNQAECggIGQAQAPsbAA==.',
Iv='Ivanapump:BAAANQAECgQIBAAAAA==.',
Ja='Jadhar:BAAANQAECgIIBAAAAA==.Jametrok:BAAANQAECgYJEQAAAA==.Jastra:BAAANQADCgYIBgAAAA==.',
Ji='Jiraîya:BAAANQAECgcIDgAAAA==.',
Jo='Jordak:BAAANQAECgYJDgAAAA==.Joshua:BAAANQADCgQIBAAAAA==.',
Ju='Jumbok:BAAANQAECgYIEwAAAA==.Just:BAAANQAECgYIEgAAAA==.',
Ka='Kaddiya:BAAANQABCgcJEQAAAA==.Kaine:BAAANQADCgUIBQAAAA==.Kallistos:BAAANQAECgcJEwAAAA==.Kangaroo:BAAANQADCgQIBAAAAA==.Kaste:BAAANQAECgQIBAAAAA==.',
Ke='Kevdogg:BAAANQAECgQJBgAAAA==.Key:BAABNQAECoEdAAMHAAkKQCLQEQBHAwAHAAkKQCLQEQBHAwAQAAcK/xSwSADQAQAAAA==.',
Kh='Khione:BAAANQADCgcJEgAAAA==.',
Ko='Koluvan:BAAANQADCgQIBAAAAA==.Koopa:BAAANQAECgYIDgAAAA==.',
Kr='Krieg:BAAANQADCgUIBAABNQAECgkJIQAFAIckAA==.Kromdar:BAAANQADCgMIAwAAAA==.',
Ky='Kyuketsuki:BAAANQADCgEIAQAAAA==.',
Le='Leahan:BAAANQABCgMIAwAAAA==.',
Lh='Lhureciv:BAABNQAECoEyAAMPAAgKWCLZDwCiAgAPAAcK9yHZDwCiAgASAAMKzhmkfQDjAAAAAA==.',
Li='Lillianna:BAAANQAECgMIBAAAAA==.Lilsensual:BAAANQAECgIIBAAAAA==.',
Lo='Loenhart:BAAANQADCgIIAgAAAA==.Logically:BAAANQADCgUIBQAAAA==.',
Lu='Luceus:BAAANQAECgQJBgAAAA==.Lucário:BAAANQAECgcIDAAAAA==.Lugia:BAAANQADCgYJCwAAAA==.Lunastorm:BAABNQAECoEgAAITAAgKeBxoDQCFAgATAAgKeBxoDQCFAgAAAA==.Luponero:BAACNQAFFIEKAAILAAUK5g7JBQCJAQALAAUK5g7JBQCJAQA1AAQKgR4AAwsACQpiH9sMANgCAAsACQoPH9sMANgCAAIAAQoCJIPhAFcAAAAA.',
Ma='Macmn:BAABNQAECoEaAAIUAAkKfyMyBwCPAwAUAAkKfyMyBwCPAwAAAA==.Mamaheals:BAAANQAECgYIEAAAAA==.Mandos:BAAANQAECgYJDAAAAA==.Mantistabogn:BAAANQAECgUJBQAAAA==.Maor:BAAANQAECgEIAQAAAA==.',
Me='Merlerk:BAAANQAECgIIAgABNQAFFAMJCAAUAOAZAA==.Merlini:BAAANQAECgcJDgAAAA==.Metrohexual:BAAANQAECgYJEAAAAA==.Mets:BAAANQAECgQJBAABNQAECgEJAQAGAAAAAA==.',
Mi='Mikasa:BAAANQAECgQIBAABNQAECgYJCQAGAAAAAA==.Mitzis:BAAANQAFFAEJAQAAAA==.',
Mo='Moltten:BAAANQADCgcIGgAAAA==.Moondo:BAECNQAFFIEPAAIFAAYKUh1aAgArAgAFAAYKUh1aAgArAgA1AAQKgSgAAwUACQrjJAsHAHwDAAUACQrjJAsHAHwDAAQABApaBVA3ALgAAAE1AAQKBgkHAAYAAAAA.',
['Mè']='Mètis:BAAANQAECgYJDwAAAA==.',
Na='Naahx:BAAANQAECgcJCAABNQAECggIEAAGAAAAAA==.',
Ne='Nefarius:BAABNQAECoEXAAIPAAgK7hp/EgB5AgAPAAgK7hp/EgB5AgAAAA==.Neurotics:BAAANQAECgYJDgAAAA==.',
Ni='Nineoneone:BAAANQAECgYIDgAAAA==.',
Nu='Nurmally:BAAANQAECgYICgABNQAFFAUIBgACAIYSAA==.',
Oc='Ocra:BAAANQAECgQICgABNQAECggIIwACADMbAA==.',
Of='Offspeck:BAAANQAECgEIAQABNQAECgcJFwABAL4dAA==.',
Or='Origen:BAAANQADCgcIBwABNQAECgkJIwAHAEIgAA==.',
Ou='Outbreak:BAAANQADCggICAAAAA==.',
Pa='Paladio:BAAANQAECgIIBgAAAA==.Pandemul:BAAANQADCggJCAABNQAECggIMAAHABcmAA==.Patrio:BAAANQADCgYIBgABNQAECggIHgAEAK8eAA==.Pawkler:BAAANQAECgQIBAABNQAECgYIBwAGAAAAAA==.Pawshira:BAAANQADCgUIBQABNQAECgYIBwAGAAAAAA==.',
Pe='Peachie:BAAANQADCgcIBwAAAA==.Peetree:BAAANQAECggJEAAAAA==.',
Ph='Phosphorus:BAABNQAECoE+AAMVAAgKqxsXBwBxAgAVAAgK6xoXBwBxAgAMAAgKihUvVwARAgAAAA==.',
Pl='Plagüë:BAABNQAECoEiAAMWAAgKthvlHQBmAgAWAAgK1xrlHQBmAgAXAAcK5BSNMwDaAQAAAA==.',
Po='Polor:BAAANQADCgQIBAAAAA==.',
Pr='Precious:BAAANQADCggJFAAAAA==.Primalistic:BAAANQAECgEIAQAAAA==.',
Pu='Pullnprey:BAAANQADCgMJBAAAAA==.Purgedoctor:BAABNQAFFIEIAAIOAAMK8h2hCAAYAQAOAAMK8h2hCAAYAQAAAA==.',
['Pà']='Pàladin:BAAANQADCgYIBgAAAA==.',
Qt='Qtptt:BAACNQAFFIEKAAIYAAUK2CENAgDqAQAYAAUK2CENAgDqAQA1AAQKgScAAhgACQpAJa4CAKgDABgACQpAJa4CAKgDAAAA.',
Ra='Ravenoflight:BAAANQAECgIJAgAAAA==.Ravenshatred:BAAANQADCggJDAAAAA==.Ravenswrath:BAAANQADCgYJBgAAAA==.Rawrsaur:BAAANQAECgQICAAAAA==.',
Re='Recon:BAAANQADCgMIAwABNQAECggJEgAGAAAAAA==.Rein:BAAANQAECgIJAgAAAA==.Remin:BAAANQADCgUJBQAAAA==.Retaliator:BAAANQAECgEIAQAAAA==.Reuuín:BAAANQADCgIIAgABNQAECgUJCgAGAAAAAA==.Revan:BAAANQADCggJCAAAAA==.',
Ri='Risquae:BAAANQAECgEJAQAAAA==.',
Ro='Rosè:BAAANQAECgYJBgABNQAECgYJDAAGAAAAAA==.',
Ru='Ruka:BAAANQAECgQIBQAAAA==.',
Ry='Ryguyro:BAAANQADCgIJAgAAAA==.Ryhia:BAAANQAECgIIAgABNQAECgYJDAAGAAAAAA==.Ryzee:BAABNQAECoEbAAIZAAkKWxPtZwBZAgAZAAkKWxPtZwBZAgAAAA==.',
['Rí']='Ríco:BAAANQADCgUIDQAAAA==.',
Sa='Sajaboy:BAAANQADCgIIAgAAAA==.Salena:BAAANQAECgEJAQAAAA==.Sartha:BAAANQAECgUICQAAAA==.Sasuka:BAAANQAECgEJAQAAAA==.Savagesoso:BAAANQADCgQJBAAAAA==.',
Sc='Schy:BAAANQAECgIIAgAAAA==.Scrumpheals:BAAANQADCgcIDQAAAA==.',
Se='Sedda:BAABNQAECoEiAAIHAAkKPyViBwCgAwAHAAkKPyViBwCgAwAAAA==.Sensual:BAAANQAECgcJEwAAAA==.Sesshomaru:BAABNQAECoEbAAIDAAgKRSJXDAD+AgADAAgKRSJXDAD+AgAAAA==.',
Sh='Shampain:BAAANQAECgIIBgABNQAECggILAAQAE4dAA==.Shang:BAABNQAECoEhAAIFAAkKhyRrBAChAwAFAAkKhyRrBAChAwAAAA==.Shirona:BAAANQAECgYJDQAAAA==.Shloomish:BAAANQADCgEIAQAAAA==.Shãde:BAAANQADCgIIAgAAAA==.Shïnwolford:BAAANQAECgcIDwABNQAECggIGwADAEUiAA==.',
Si='Siare:BAAANQAECgEJAQAAAA==.',
Sk='Skeeter:BAAANQAECgYJEQAAAA==.Skroncer:BAAANQADCgYIDwAAAA==.',
Sm='Smokinjawn:BAAANQADCgMIAwAAAA==.Smòtts:BAAANQAECgYJDgAAAA==.Smótts:BAAANQADCggJEwAAAA==.',
Sn='Sneekee:BAAANQAECgIIBAABNQAECgQIBAAGAAAAAA==.Snizard:BAAANQAECgQJBgAAAA==.Snuggiepoo:BAAANQADCgIIAgABNQAECgEJAgAGAAAAAA==.',
So='Soawesome:BAAANQADCgYJCwABNQAECgQJDAAGAAAAAA==.',
Sp='Spicymustard:BAAANQADCgYICgAAAA==.Spàdes:BAAANQAECgIJAgAAAA==.',
Sq='Squírtlé:BAAANQADCgEIAQAAAA==.',
St='Stellanoova:BAAANQAECgQJBgABNQAECgcIDAAGAAAAAA==.Stuwu:BAAANQABCgQIBAAAAA==.',
Su='Sugarhigh:BAAANQABCgQIBAAAAA==.Sunlight:BAAANQADCggJCAAAAA==.Sushirollz:BAAANQAECgEIAQAAAA==.',
Ta='Taazdingo:BAAANQADCgYJCwAAAA==.Takin:BAAANQADCggICAAAAA==.Taxxwomann:BAABNQAECoEdAAMYAAkKxCDOJACSAgAYAAcKGCDOJACSAgAaAAMKUR3XKAANAQAAAA==.',
Th='Thisishard:BAAANQAECgcJEwAAAA==.Thryen:BAAANQAECgQIBQAAAA==.Thundergrasp:BAAANQAECggJCAABNQAECgkJGwAZAFsTAA==.',
To='Toobestake:BAAANQABCgUIBQABNQAFFAUJCgALAOYOAA==.Topenga:BAABNQAECoEjAAICAAgKMxtSJQCiAgACAAgKMxtSJQCiAgAAAA==.',
Tr='Trunnks:BAAANQAECgEIAQAAAA==.',
Ts='Tsargock:BAAANQADCgUIBAAAAA==.',
Tu='Tuoldforthis:BAAANQADCgIJAgAAAA==.',
Tw='Twicelife:BAAANQAECgUJCAABNQAECggIPgAVAKsbAA==.',
['Tñ']='Tñt:BAAANQADCgMIAwABNQAECgcJFwABAL4dAA==.',
Ur='Urbek:BAAANQAECgYIEwAAAA==.Urthstripe:BAAANQAECgUICAAAAA==.',
Uw='Uwu:BAAANQADCgIJAgABNQAFFAUICwAPAHASAA==.',
Va='Valle:BAAANQADCgEIAQABNQAFFAUICwAPAHASAA==.Valoria:BAAANQADCgEJAQABNQAFFAUICwAPAHASAA==.',
Ve='Velgabrine:BAAANQAECgQICAABNQAECggIMAAHABcmAA==.Verlaria:BAAANQADCgEIAQAAAA==.',
Vi='Viserion:BAAANQAECgcIDAAAAA==.',
Vu='Vue:BAABNQAECoEsAAIQAAgKTh16GgC9AgAQAAgKTh16GgC9AgAAAA==.',
Wa='Wakasham:BAABNQAECoEbAAIbAAkKPyYdAAADBAAbAAkKPyYdAAADBAAAAA==.Warwick:BAAANQABCgIIAgAAAA==.',
We='Wehonoryou:BAAANQAECgYICgABNQAFFAYJDgANAIYdAA==.',
Wo='Wolfpacked:BAAANQAECgYJEQAAAA==.',
Wu='Wunderlust:BAABNQAECoEjAAIZAAgKlRsLWACEAgAZAAgKlRsLWACEAgAAAA==.',
Ye='Yellowshaman:BAABNQAECoEfAAIUAAkKrBppFgD6AgAUAAkKrBppFgD6AgAAAA==.',
Za='Zandelussy:BAAANQAECgEJAgAAAA==.',
Zu='Zugg:BAAANQAECgYIBgABNQAFFAUICwAPAHASAA==.Zuriznikov:BAAANQAECgQIBQABNQAECgcIDAAGAAAAAA==.',
['Øf']='Øffspeck:BAABNQAECoEXAAQBAAcKvh3kBwCQAQAYAAYKURrkUgDWAQABAAUKXhrkBwCQAQAaAAMKTB5HKgAEAQAAAA==.',
['ßo']='ßoss:BAAANQADCgQIBAABNQAECgQICgAGAAAAAA==.',
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
