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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','DemonHunter-Devourer','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Balance','Druid-Restoration','Warrior-Arms','Warlock-Demonology','Paladin-Retribution',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaronfreeze:BAAANQAECgYIDAAAAA==.',
Ab='Abnar:BAAANQAECgEIAQAAAA==.',
Ad='Adversaryq:BAAANQADCgEIAQAAAA==.',
Ai='Aid:BAAANQADCgMIBQAAAA==.',
Al='Alanii:BAAANQAECgUIBQAAAA==.Alaula:BAAANQAECgQIBAAAAA==.Albedô:BAAANQADCgIIBAABNQAECgcIEgABAAAAAA==.Allformarc:BAAANQADCgUIBQAAAA==.Allmaick:BAAANQADCgQIBAAAAA==.Alucard:BAAANQAECgIIAgAAAA==.Alystrasza:BAAANQAECgUICQAAAA==.',
Am='Ambivalent:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.',
An='Animan:BAAANQABCgIIAgAAAA==.Antimovsky:BAAANQAECgMIBQAAAA==.',
Ap='Aphroditê:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.',
Av='Aviaria:BAAANQADCggIDgAAAA==.',
Ax='Axsenaea:BAAANQADCgEIAQAAAA==.',
['Aì']='Aìnzooalgown:BAAANQAECgMIBAABNQAECgcIEgABAAAAAA==.',
['Aü']='Aütöpsy:BAAANQAECgEIAQAAAA==.',
Ba='Babylonfive:BAAANQAECgcIDwAAAA==.Backstabbath:BAAANQADCgIIAgAAAA==.Banger:BAAANQAECgEIAQAAAA==.',
Be='Belleta:BAAANQAECgEIAgAAAA==.Belligerente:BAAANQAECgQIBQAAAA==.Berserk:BAEANQAECgQIBAABNQAECggIEwACADYUAA==.',
Bi='Bigwilli:BAAANQADCgUIBQAAAA==.Biscuit:BAAANQAECggIEAAAAA==.Bisha:BAAANQAECgcIEQAAAA==.Bizcocho:BAAANQADCgYIDgAAAA==.',
Bo='Bonesofdoom:BAAANQADCgEIAQAAAA==.Boomkingobrr:BAAANQAECgYICQAAAA==.Bootysweatt:BAAANQADCggICAAAAA==.',
Bu='Buckayou:BAAANQADCgUIBwAAAA==.Burnsx:BAAANQADCgYIDAABNQAECgkJGgADACclAA==.',
Ca='Caiandol:BAAANQADCgQIAwAAAA==.Candydreams:BAAANQABCgQIBAAAAA==.Captnmurloc:BAAANQAECgUIBQAAAA==.Catara:BAAANQADCgcICwAAAA==.',
Ce='Cedar:BAAANQADCgYICwAAAA==.',
Ch='Cheetos:BAAANQADCggICAAAAA==.Cherga:BAAANQADCgUICAAAAA==.Chrinn:BAAANQABCgUIBQAAAA==.Church:BAAANQAECgEIAgAAAA==.',
Ci='Cirxe:BAAANQAECgMIAwAAAA==.',
Co='Coms:BAAANQADCggICAAAAA==.',
['Cø']='Cønstance:BAAANQAECgIIAgAAAA==.',
Da='Dabai:BAAANQAECgQICwAAAA==.Daddý:BAAANQAECgYIBgAAAA==.Daipailaotie:BAAANQAECgQIBAAAAA==.Dalight:BAAANQAECgEIAQAAAA==.Dankins:BAAANQAECggICAABNQAFFAEIAQABAAAAAA==.Darealfarmer:BAAANQADCgYIBgAAAA==.Darkzoomies:BAAANQAECgIIAgAAAA==.',
De='Dette:BAAANQAECgEIAQAAAA==.Devourer:BAAANQAECgcIEAAAAA==.',
Dk='Dkboss:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Do='Doctrdoom:BAAANQADCggICAABNQAECgQICgABAAAAAA==.',
Dr='Drafted:BAAANQAECgQIBgAAAA==.Dragondank:BAAANQAFFAEIAQAAAA==.Drukah:BAAANQADCgYIBgAAAA==.',
Dt='Dtrike:BAAANQAECgIIAgAAAA==.',
Ed='Edstark:BAAANQAECgEIAQAAAA==.',
El='Elabernathy:BAAANQAECgEIAQAAAA==.Elenay:BAAANQAECgMICQAAAA==.Elliemental:BAAANQADCgQIBAAAAA==.Elpatron:BAAANQAECgYICwAAAA==.Elylanea:BAAANQADCggICAAAAA==.',
Em='Emulsdeath:BAAANQAECgEIAgABNQAECgcIEQABAAAAAA==.Emulsifier:BAAANQAECgcIEQAAAA==.Emulslash:BAAANQADCgYIDAABNQAECgcIEQABAAAAAA==.',
Ex='Expiredbeef:BAAANQADCgYIBgAAAA==.',
Fa='Farcha:BAAANQABCgUIBgABNQADCgYIBgABAAAAAA==.',
Fi='Finester:BAAANQAECgUIBQAAAA==.',
Fu='Funslinger:BAAANQADCggICgAAAA==.',
Go='Gorska:BAAANQAECgQIBAAAAA==.',
Gr='Grawm:BAAANQAECgUICAAAAA==.Gritshaman:BAAANQADCgIIAgABNQAECgQICgABAAAAAA==.',
['Gä']='Gämbit:BAAANQADCgEIAgAAAA==.',
Ha='Hangman:BAAANQAECgQICgAAAA==.Hanni:BAAANQADCgcIHgAAAA==.Hawktoetem:BAAANQADCgQIBAAAAA==.Hawktoouh:BAAANQADCgQIBAAAAA==.',
He='Hellshand:BAAANQADCgcIDgAAAA==.Helmhammer:BAAANQADCgQIBAAAAA==.',
Ho='Holychaser:BAAANQAECgMIBQAAAA==.Holycrack:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Holycøw:BAAANQADCgUICAAAAA==.Holypawk:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Holyrock:BAAANQAECgEIAQAAAA==.',
Ih='Ihureciv:BAAANQAECgMIBAABNQAECgcIEgABAAAAAA==.',
Ik='Ikur:BAAANQAECgQIBwAAAA==.',
Ip='Ipopkidneys:BAAANQAFFAEIAQAAAA==.',
Is='Iskur:BAAANQADCgUIBQABNQAECgQIBwABAAAAAA==.Isurr:BAAANQADCgcIBwABNQAECgQIBwABAAAAAA==.',
Ja='Jametrok:BAAANQAECgQIBQAAAA==.',
Ji='Jiraîya:BAAANQADCgYIEgAAAA==.',
Jo='Jordak:BAAANQAECgQIBAAAAA==.Joshua:BAAANQADCgQIBAAAAA==.',
Ju='Jumbok:BAAANQAECgQIBwAAAA==.Just:BAAANQAECgQIBQAAAA==.',
Ka='Kallistos:BAAANQAECgQIBgAAAA==.Kangaroo:BAAANQADCgQIBAAAAA==.Kaste:BAAANQADCgQIBAAAAA==.',
Ke='Kevdogg:BAAANQADCggIDgAAAA==.Key:BAAANQAECgcIEQAAAA==.',
Kh='Khione:BAAANQADCgYICwAAAA==.',
Ko='Koopa:BAAANQAECgUICAAAAA==.',
Kr='Kromdar:BAAANQADCgMIAwAAAA==.',
Ky='Kyuketsuki:BAAANQADCgEIAQAAAA==.',
Le='Leahan:BAAANQABCgMIAwAAAA==.',
Lh='Lhureciv:BAAANQAECgcIEgAAAA==.',
Li='Lillianna:BAAANQADCggIDgAAAA==.',
Lo='Loenhart:BAAANQADCgIIAgAAAA==.Logically:BAAANQADCgUIBQAAAA==.',
Lu='Luceus:BAAANQADCgYIBgAAAA==.Lucário:BAAANQAECgQIBAAAAA==.Lunastorm:BAAANQAECgYIEAAAAA==.Luponero:BAABNQAECoEXAAMEAAkJhxvNCADdAgAEAAkJNBvNCADdAgAFAAEJAiTnhQBgAAAAAA==.',
Ma='Macmn:BAAANQAECggIDgAAAA==.Mamaheals:BAAANQAECgQIBQAAAA==.Mandos:BAAANQAECgQIBgAAAA==.Mantistabogn:BAAANQADCggICgAAAA==.Maor:BAAANQADCggICgAAAA==.',
Me='Merlini:BAAANQAECgQIBQAAAA==.Metrohexual:BAAANQAECgUIBQAAAA==.Mets:BAAANQAECgEIAQAAAA==.',
Mi='Mitzis:BAAANQAECgQIBgAAAA==.',
Mo='Moltten:BAAANQADCgYIDQAAAA==.Moondo:BAECNQAFFIEGAAIGAAUJmxSjAQCuAQAGAAUJmxSjAQCuAQA1AAQKgRoAAwYACQnRJH0CAJ8DAAYACQnRJH0CAJ8DAAcABAlaBYMgAMwAAAE1AAMKCAgBAAEAAAAA.',
['Mè']='Mètis:BAAANQAECgQIBQAAAA==.',
Ne='Nefarius:BAAANQAECgcIDQAAAA==.Neurotics:BAAANQAECgMIAwAAAA==.',
Ni='Nineoneone:BAAANQAECgMIAwAAAA==.',
Nu='Nurmally:BAAANQAECgQIBAABNQAFFAIIAgABAAAAAA==.',
Oc='Ocra:BAAANQADCggIFgABNQAECgQIBQABAAAAAA==.',
Of='Offspeck:BAAANQAECgEIAQABNQAECgQICgABAAAAAA==.',
Or='Origen:BAAANQADCgcIBwABNQAECgcIDwABAAAAAA==.',
Ou='Outbreak:BAAANQADCggICAAAAA==.',
Pa='Paladio:BAAANQADCggIFgAAAA==.Pandemul:BAAANQADCggICAABNQAECgcIEQABAAAAAA==.Patrio:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Pawkler:BAAANQAECgQIBAAAAA==.',
Pe='Peachie:BAAANQADCgcIBwAAAA==.Peatri:BAAANQADCgcIBwAAAA==.Peetree:BAAANQAECgYIBAAAAA==.',
Ph='Phosphorus:BAABNQAECoEYAAIIAAgJGxVqKQBJAgAIAAgJGxVqKQBJAgAAAA==.',
Pl='Plagüë:BAAANQAECgcIEwAAAA==.',
Po='Polor:BAAANQADCgQIBAAAAA==.',
Pr='Precious:BAAANQADCgcIBwAAAA==.Primalistic:BAAANQADCggIFAAAAA==.Prowar:BAAANQAECgEIAQAAAA==.',
Pu='Purgedoctor:BAAANQAFFAIIAwAAAA==.',
['Pà']='Pàladin:BAAANQADCgYIBgAAAA==.',
Qt='Qtptt:BAABNQAECoEbAAIJAAkJByWFAADAAwAJAAkJByWFAADAAwAAAA==.',
Ra='Ravenoflight:BAAANQADCgYICgAAAA==.Ravenshatred:BAAANQADCgYIBgAAAA==.',
Re='Recon:BAAANQADCgMIAwABNQAECggIDgABAAAAAA==.Remin:BAAANQABCgQIBwAAAA==.Retaliator:BAAANQADCgcIEgAAAA==.',
Ri='Risquae:BAAANQAECgEIAQAAAA==.',
Ru='Ruka:BAAANQAECgQIBQAAAA==.',
Ry='Ryguyro:BAAANQADCgIIAgAAAA==.Ryhia:BAAANQAECgIIAgABNQAECgQIBgABAAAAAA==.Ryzee:BAAANQAECgcIDwAAAA==.',
['Rí']='Ríco:BAAANQADCgMIBAAAAA==.',
Sa='Sartha:BAAANQAECgIIAwAAAA==.Sasuka:BAAANQADCggIEgAAAA==.',
Sc='Schy:BAAANQADCgcIDgAAAA==.Scrumpheals:BAAANQADCgYIBwAAAA==.',
Se='Sedda:BAABNQAECoEXAAIKAAkJhiQcAwClAwAKAAkJhiQcAwClAwAAAA==.Sensual:BAAANQAECgcIEQAAAA==.Sesshomaru:BAAANQAECgcIEgAAAA==.',
Sh='Shampain:BAAANQADCggIIgABNQAECgYIEAABAAAAAA==.Shang:BAAANQAECgcIDwAAAA==.Shirona:BAAANQAECgIIAgAAAA==.Shãde:BAAANQADCgIIAgAAAA==.Shïnwolford:BAAANQAECgEIAQABNQAECgcIEgABAAAAAA==.',
Sk='Skeeter:BAAANQAECgQIBwAAAA==.Skroncer:BAAANQADCgYICQAAAA==.',
Sm='Smòtts:BAAANQAECgMIAwAAAA==.Smótts:BAAANQADCgcICwAAAA==.',
Sn='Sneekee:BAAANQAECgIIBAAAAA==.Snizard:BAAANQADCggIFAAAAA==.Snuggiepoo:BAAANQADCgIIAgABNQADCgYICwABAAAAAA==.',
So='Soawesome:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Sp='Spicymustard:BAAANQADCgQIBAAAAA==.Spàdes:BAAANQAECgEIAQAAAA==.',
St='Stellanoova:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Stuwu:BAAANQABCgQIBAAAAA==.',
Su='Sugarhigh:BAAANQABCgQIBAAAAA==.Sushirollz:BAAANQADCgMIBQAAAA==.',
Ta='Taazdingo:BAAANQABCgEIAQAAAA==.Takin:BAAANQADCggICAAAAA==.Taxxwomann:BAAANQAECgYICgAAAA==.',
Th='Thisishard:BAAANQAECgQIBgAAAA==.Thryen:BAAANQADCgYIDQAAAA==.',
To='Topenga:BAAANQAECgQIBQAAAA==.',
Tr='Trunnks:BAAANQAECgEIAQAAAA==.',
Tu='Tuoldforthis:BAAANQADCgIIAgAAAA==.',
Tw='Twicelife:BAAANQAECgUIBQABNQAECggIGAAIABsVAA==.',
Ur='Urbek:BAAANQAECgQIBwAAAA==.Urthstripe:BAAANQAECgIIAwAAAA==.',
Uw='Uwu:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
Va='Valle:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Valoria:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.',
Vi='Viserion:BAAANQAECgIIAwAAAA==.',
Vu='Vue:BAAANQAECgYIEAAAAA==.',
Wa='Wakasham:BAAANQAECgcIDAAAAA==.Warwick:BAAANQABCgIIAgAAAA==.',
We='Wehonoryou:BAAANQAECgIIAgAAAA==.',
Wo='Wolfpacked:BAAANQAECgQICAAAAA==.',
Wu='Wunderlust:BAAANQAECgcIEQAAAA==.',
Ye='Yellowshaman:BAAANQAECgYICwAAAA==.',
Za='Zandelussy:BAAANQADCgYICwAAAA==.',
Zu='Zugg:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Zuriznikov:BAAANQADCggIDQABNQAECgIIAwABAAAAAA==.',
['Øf']='Øffspeck:BAAANQAECgQICgAAAA==.',
['ßo']='ßoss:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
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
