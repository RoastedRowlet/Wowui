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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Rogue-Subtlety','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Arms','DemonHunter-Devourer','Priest-Shadow','Rogue-Assassination','Paladin-Holy','Priest-Holy','Shaman-Elemental','Druid-Balance','Druid-Restoration','Warrior-Protection','Shaman-Restoration','Warlock-Demonology','Mage-Arcane',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaronfreeze:BAAANQAECgcIEgAAAA==.',
Ab='Abnar:BAAANQAECgEIAQAAAA==.',
Ad='Adversaryq:BAAANQADCgYIBwAAAA==.',
Ai='Aid:BAAANQADCgMIBQAAAA==.',
Al='Alanii:BAAANQAECgUIBQAAAA==.Alaula:BAAANQAECgQIBAAAAA==.Albedô:BAAANQADCgIIBAABNQAECgcIEgABAAAAAA==.Allformarc:BAAANQAECgEIAQAAAA==.Allmaick:BAAANQADCgQIBAAAAA==.Alucard:BAAANQAECgYICAAAAA==.Alystrasza:BAAANQAECgYIDwAAAA==.',
Am='Ambivalent:BAAANQADCgQIBAABNQAECgQICgABAAAAAA==.',
An='Animan:BAAANQABCgIIAgAAAA==.Antimovsky:BAAANQAECgQICQAAAA==.',
Ap='Aphroditê:BAAANQADCgQIBAABNQAECgQICQABAAAAAA==.',
Av='Aviaria:BAAANQAECgEIAQAAAA==.',
Ax='Axsenaea:BAAANQADCgEIAQAAAA==.',
['Aì']='Aìnzooalgown:BAAANQAECgMIBAABNQAECgcIEgABAAAAAA==.',
['Aü']='Aütöpsy:BAAANQAECgUIBgAAAA==.',
Ba='Babylonfive:BAABNQAECoEaAAICAAkJTRz7EgAIAwACAAkJTRz7EgAIAwAAAA==.Backstabbath:BAAANQADCgQIBQAAAA==.Banger:BAAANQAECgEIAQAAAA==.',
Be='Belleta:BAAANQAECgEIAgAAAA==.Belligerente:BAAANQAECgQICgAAAA==.Berserk:BAEANQAECgUIBgABNQAECgkJHgADAJMTAA==.',
Bi='Bigwilli:BAAANQADCgYICwAAAA==.Birds:BAAANQAECgcIDQAAAA==.Biscuit:BAABNQAECoEYAAMEAAgJ4yIiFQDPAgAEAAcJZCYiFQDPAgAFAAYJFxm9GwDYAQAAAA==.Bisha:BAABNQAECoEjAAIGAAgJpxccNABrAgAGAAgJpxccNABrAgAAAA==.Bizcocho:BAAANQADCgYIDgAAAA==.',
Bo='Bonesofdoom:BAAANQADCgEIAQAAAA==.Boomkingobrr:BAAANQAECgYICQAAAA==.Boops:BAAANQAECgEIAQAAAA==.Bootysweatt:BAAANQADCggICAAAAA==.',
Bu='Buckayou:BAAANQADCgUIBwAAAA==.Burnsx:BAAANQADCgYIDAABNQAFFAUICAAHAEUbAA==.',
Bw='Bwoar:BAAANQADCggICAAAAA==.',
Ca='Caiandol:BAAANQADCgQIAwAAAA==.Candydreams:BAAANQABCgQIBAAAAA==.Captnmurloc:BAAANQAECgUIBgAAAA==.Catara:BAAANQADCgcICwAAAA==.',
Ce='Cedar:BAAANQADCgYICwAAAA==.',
Ch='Cheetos:BAAANQADCggICAAAAA==.Cherga:BAAANQAECgIIAgAAAA==.Chrinn:BAAANQABCgUIBQAAAA==.Church:BAAANQAECgQIBgAAAA==.',
Ci='Cirxe:BAAANQAECgQIBwAAAA==.',
Cl='Clarkent:BAAANQAECgEIAQAAAA==.',
Co='Coms:BAAANQAECgUIBQAAAA==.',
['Cø']='Cønstance:BAAANQAECgMIBQAAAA==.',
Da='Dabai:BAAANQAECgYIEQAAAA==.Daipailaotie:BAAANQAECgYICgAAAA==.Dalight:BAAANQAECgIIAwAAAA==.Dankins:BAAANQAFFAIIAgAAAA==.Darealfarmer:BAAANQADCgYIBgAAAA==.Darkzoomies:BAAANQAECgMIAwAAAA==.',
De='Dethsent:BAAANQAECgIIAgAAAA==.Dette:BAAANQAECgEIAQAAAA==.Devourer:BAABNQAECoEeAAIHAAkJWheVDADPAgAHAAkJWheVDADPAgAAAA==.',
Dk='Dkboss:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.',
Do='Doctrdoom:BAAANQADCggICAABNQAECgYIEAABAAAAAA==.',
Dr='Drafted:BAAANQAECgUIBwAAAA==.Dragondank:BAAANQAFFAEIAgABNQAFFAIIAgABAAAAAA==.Drukah:BAAANQADCgcIDAAAAA==.',
Dt='Dtrike:BAAANQAECgIIBAAAAA==.',
Ed='Edstark:BAAANQAECgIIBAAAAA==.',
El='Elabernathy:BAAANQAECgEIAQAAAA==.Elenay:BAAANQAECgUIDgAAAA==.Elliemental:BAAANQADCgQIBAAAAA==.Elpatron:BAAANQAECgcIEgAAAA==.Elylanea:BAAANQADCggICAAAAA==.',
Em='Emulsdeath:BAAANQAECgIIBAABNQAECggIIwACAJYlAA==.Emulsifier:BAABNQAECoEjAAICAAgJliVpCAB0AwACAAgJliVpCAB0AwAAAA==.Emulslash:BAAANQADCgYIDAABNQAECggIIwACAJYlAA==.',
Ex='Expiredbeef:BAAANQADCgYIBgAAAA==.',
Fa='Farcha:BAAANQABCgUIBgABNQADCggIDQABAAAAAA==.',
Fi='Finester:BAAANQAECgUIBQAAAA==.',
Fu='Funslinger:BAAANQADCggICgAAAA==.',
Go='Gorska:BAAANQAECgQICAAAAA==.',
Gr='Grawm:BAAANQAECgYIDgAAAA==.Gritshaman:BAAANQADCgcICQABNQAECgYIEAABAAAAAA==.',
['Gä']='Gämbit:BAAANQADCgcIDAAAAA==.',
Ha='Hangman:BAAANQAECgYIDQAAAA==.Hanni:BAAANQADCggIIQAAAA==.Hawktoetem:BAAANQADCgQIBAAAAA==.Hawktoouh:BAAANQAECgQIBAAAAA==.',
He='Hellshand:BAAANQADCgcIDgAAAA==.Helmhammer:BAAANQAECgEIAQAAAA==.',
Ho='Holychaser:BAAANQAECgMIBwAAAA==.Holycrack:BAAANQADCgYIBgABNQAECgQICwABAAAAAA==.Holycøw:BAAANQAECgEIAQAAAA==.Holypawk:BAAANQAECgEIAQAAAA==.Holyrock:BAAANQAECgEIAgAAAA==.',
['Hó']='Hóly:BAAANQADCgEIAQABNQAECgYICQABAAAAAA==.',
Ih='Ihureciv:BAAANQAECgQIBwABNQAECggIJQAIAPQhAA==.',
Ik='Ikur:BAAANQAECgYIDQAAAA==.',
Ip='Ipopkidneys:BAABNQAECoEcAAMDAAkJ3yS3BQD8AgADAAcJCCa3BQD8AgAJAAMJ1iGBKQAYAQAAAA==.',
Is='Iskur:BAAANQAECgEIAQABNQAECgYIDQABAAAAAA==.Isurr:BAAANQADCggIDQABNQAECgYIDQABAAAAAA==.',
Iv='Ivanapump:BAAANQAECgQIBAAAAA==.',
Ja='Jametrok:BAAANQAECgYICwAAAA==.',
Ji='Jiraîya:BAAANQADCgYIEgAAAA==.',
Jo='Jordak:BAAANQAECgQICAAAAA==.Joshua:BAAANQADCgQIBAAAAA==.',
Ju='Jumbok:BAAANQAECgYIDQAAAA==.Just:BAAANQAECgYICwAAAA==.',
Ka='Kaddiya:BAAANQABCgcIDQAAAA==.Kallistos:BAAANQAECgYIDAAAAA==.Kangaroo:BAAANQADCgQIBAAAAA==.Kaste:BAAANQADCgQIBAAAAA==.',
Ke='Kevdogg:BAAANQAECgIIAgAAAA==.Key:BAABNQAECoEbAAMCAAkJtSB3DQA8AwACAAkJtSB3DQA8AwAKAAcJ/xTSNwDaAQAAAA==.',
Kh='Khione:BAAANQADCgYICwAAAA==.',
Ko='Koluvan:BAAANQADCgQIBAAAAA==.Koopa:BAAANQAECgUICAAAAA==.',
Kr='Krieg:BAAANQADCgUIBAAAAA==.Kromdar:BAAANQADCgMIAwAAAA==.',
Ky='Kyuketsuki:BAAANQADCgEIAQAAAA==.',
Le='Leahan:BAAANQABCgMIAwAAAA==.',
Lh='Lhureciv:BAABNQAECoElAAMIAAgJ9CGgDACuAgAIAAcJhCGgDACuAgALAAEJ3BkbhABLAAAAAA==.',
Li='Lillianna:BAAANQAECgEIAQAAAA==.',
Lo='Loenhart:BAAANQADCgIIAgAAAA==.Logically:BAAANQADCgUIBQAAAA==.',
Lu='Luceus:BAAANQAECgIIAgAAAA==.Lucário:BAAANQAECgQIBAAAAA==.Lugia:BAAANQADCgYIBgAAAA==.Lunastorm:BAAANQAECgYIEAAAAA==.Luponero:BAABNQAECoEcAAMFAAkJ3RyJCwDTAgAFAAkJihyJCwDTAgAEAAEJAiTstwBdAAAAAA==.',
Ma='Macmn:BAABNQAECoEXAAIMAAkJ8iDMBgB9AwAMAAkJ8iDMBgB9AwAAAA==.Mamaheals:BAAANQAECgUICgAAAA==.Mandos:BAAANQAECgQIBgAAAA==.Mantistabogn:BAAANQADCggICgAAAA==.Maor:BAAANQAECgEIAQAAAA==.',
Me='Merlini:BAAANQAECgQIBwAAAA==.Metrohexual:BAAANQAECgYICwAAAA==.Mets:BAAANQAECgMIAwAAAA==.',
Mi='Mikasa:BAAANQADCggICAABNQAECgYICQABAAAAAA==.Mitzis:BAAANQAECgUICAAAAA==.',
Mo='Moltten:BAAANQADCgcIFAAAAA==.Moondo:BAECNQAFFIEKAAINAAUJ6hzpAgC/AQANAAUJ6hzpAgC/AQA1AAQKgRsAAw0ACQnRJBMGAHgDAA0ACQnRJBMGAHgDAA4ABAlaBVAsAMAAAAE1AAQKAwgCAAEAAAAA.',
['Mè']='Mètis:BAAANQAECgQICQAAAA==.',
Na='Naahx:BAAANQAECgEIAQABNQAECgYICAABAAAAAA==.',
Ne='Nefarius:BAABNQAECoEWAAIIAAgJ7hpBDgCMAgAIAAgJ7hpBDgCMAgAAAA==.Neurotics:BAAANQAECgUICAAAAA==.',
Ni='Nineoneone:BAAANQAECgUICAAAAA==.',
Nu='Nurmally:BAAANQAECgYICgABNQAFFAUIBgAEAIYSAA==.',
Oc='Ocra:BAAANQAECgQIBgABNQAECgcIEwABAAAAAA==.',
Of='Offspeck:BAAANQAECgEIAQABNQAECgYIEAABAAAAAA==.',
Or='Origen:BAAANQADCgcIBwABNQAECgkJGgACAE0cAA==.',
Ou='Outbreak:BAAANQADCggICAAAAA==.',
Pa='Paladio:BAAANQAECgIIAgAAAA==.Pandemul:BAAANQADCggICAABNQAECggIIwACAJYlAA==.Patrio:BAAANQADCgYIBgABNQAECgcIEgABAAAAAA==.Pawkler:BAAANQAECgQIBAABNQAECgEIAQABAAAAAA==.',
Pe='Peachie:BAAANQADCgcIBwAAAA==.Peetree:BAAANQAECgYICgAAAA==.',
Ph='Phosphorus:BAABNQAECoErAAMPAAgJxxhLBgBLAgAPAAgJdhdLBgBLAgAGAAgJGxX7PwA1AgAAAA==.',
Pl='Plagüë:BAAANQAECgcIEwAAAA==.',
Po='Polor:BAAANQADCgQIBAAAAA==.',
Pr='Precious:BAAANQADCggIDwAAAA==.Primalistic:BAAANQADCggIGgAAAA==.Prowar:BAAANQAECgQIBQAAAA==.',
Pu='Pullnprey:BAAANQADCgMIAwAAAA==.Purgedoctor:BAABNQAFFIEFAAIQAAIJKSKbBwDPAAAQAAIJKSKbBwDPAAAAAA==.',
['Pà']='Pàladin:BAAANQADCgYIBgAAAA==.',
Qt='Qtptt:BAABNQAECoEkAAIRAAkJQCU9AQC9AwARAAkJQCU9AQC9AwAAAA==.',
Ra='Ravenoflight:BAAANQAECgIIAgAAAA==.Ravenshatred:BAAANQADCgYIBgAAAA==.Rawrsaur:BAAANQAECgQIBAAAAA==.',
Re='Recon:BAAANQADCgMIAwABNQAECggIEgABAAAAAA==.Rein:BAAANQAECgEIAQAAAA==.Remin:BAAANQABCgYICwAAAA==.Retaliator:BAAANQADCgcIFwAAAA==.',
Ri='Risquae:BAAANQAECgEIAQAAAA==.',
Ru='Ruka:BAAANQAECgQIBQAAAA==.',
Ry='Ryguyro:BAAANQADCgIIAgAAAA==.Ryhia:BAAANQAECgIIAgABNQAECgQIBgABAAAAAA==.Ryzee:BAABNQAECoEbAAISAAkJWxP6SgBsAgASAAkJWxP6SgBsAgAAAA==.',
['Rí']='Ríco:BAAANQADCgQICAAAAA==.',
Sa='Salena:BAAANQADCggICAAAAA==.Sartha:BAAANQAECgQICAAAAA==.Sasuka:BAAANQADCggIGgAAAA==.',
Sc='Schy:BAAANQAECgIIAgAAAA==.Scrumpheals:BAAANQADCgcIDQAAAA==.',
Se='Sedda:BAABNQAECoEgAAICAAkJJiUXBAC1AwACAAkJJiUXBAC1AwAAAA==.Sensual:BAAANQAECgcIEQAAAA==.Sesshomaru:BAAANQAECgcIEgAAAA==.',
Sh='Shampain:BAAANQAECgIIAgABNQAECggIIgAKAE4dAA==.Shang:BAABNQAECoEZAAINAAgJXyWKCABTAwANAAgJXyWKCABTAwAAAA==.Shirona:BAAANQAECgYICAAAAA==.Shloomish:BAAANQADCgEIAQAAAA==.Shãde:BAAANQADCgIIAgAAAA==.Shïnwolford:BAAANQAECgEIAQABNQAECgcIEgABAAAAAA==.',
Sk='Skeeter:BAAANQAECgQICwAAAA==.Skroncer:BAAANQADCgYIDgAAAA==.',
Sm='Smokinjawn:BAAANQADCgMIAwAAAA==.Smòtts:BAAANQAECgUICAAAAA==.Smótts:BAAANQADCggIEwAAAA==.',
Sn='Sneekee:BAAANQAECgIIBAABNQAECgQIBAABAAAAAA==.Snizard:BAAANQAECgIIAgAAAA==.Snuggiepoo:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
So='Soawesome:BAAANQADCgYICwABNQAECgQICgABAAAAAA==.',
Sp='Spicymustard:BAAANQADCgYICgAAAA==.Spàdes:BAAANQAECgEIAQAAAA==.',
Sq='Squírtlé:BAAANQADCgEIAQAAAA==.',
St='Stellanoova:BAAANQAECgMIAwABNQAECgMIBwABAAAAAA==.Stuwu:BAAANQABCgQIBAAAAA==.',
Su='Sugarhigh:BAAANQABCgQIBAAAAA==.Sushirollz:BAAANQAECgEIAQAAAA==.',
Ta='Taazdingo:BAAANQADCgYIBgAAAA==.Takin:BAAANQADCggICAAAAA==.Taxxwomann:BAAANQAECggIEgAAAA==.',
Th='Thisishard:BAAANQAECgYIDAAAAA==.Thryen:BAAANQAECgQIBAAAAA==.Thundergrasp:BAAANQADCgcICAABNQAECgkJGwASAFsTAA==.',
To='Toobestake:BAAANQABCgUIBQABNQAECgkJHAAFAN0cAA==.Topenga:BAAANQAECgcIEwAAAA==.',
Tr='Trunnks:BAAANQAECgEIAQAAAA==.',
Ts='Tsargock:BAAANQADCgUIBAAAAA==.',
Tu='Tuoldforthis:BAAANQADCgIIAgAAAA==.',
Tw='Twicelife:BAAANQAECgUIBwABNQAECggIKwAPAMcYAA==.',
Ur='Urbek:BAAANQAECgYIDQAAAA==.Urthstripe:BAAANQAECgQIBwAAAA==.',
Uw='Uwu:BAAANQADCgIIAgABNQAECgYIBgABAAAAAA==.',
Va='Valle:BAAANQADCgEIAQABNQAECgYIBgABAAAAAA==.Valoria:BAAANQADCgEIAQABNQAECgYIBgABAAAAAA==.',
Vi='Viserion:BAAANQAECgMIBwAAAA==.',
Vu='Vue:BAABNQAECoEiAAIKAAgJTh2oEgDMAgAKAAgJTh2oEgDMAgAAAA==.',
Wa='Wakasham:BAAANQAFFAEIAQAAAA==.Warwick:BAAANQABCgIIAgAAAA==.',
We='Wehonoryou:BAAANQAECgQIBQAAAA==.',
Wo='Wolfpacked:BAAANQAECgQICwAAAA==.',
Wu='Wunderlust:BAABNQAECoEjAAISAAgJlRvrPACeAgASAAgJlRvrPACeAgAAAA==.',
Ye='Yellowshaman:BAAANQAECggIEwAAAA==.',
Za='Zandelussy:BAAANQAECgEIAQAAAA==.',
Zu='Zugg:BAAANQAECgYIBgAAAA==.Zuriznikov:BAAANQADCggIDwABNQAECgMIBwABAAAAAA==.',
['Øf']='Øffspeck:BAAANQAECgYIEAAAAA==.',
['ßo']='ßoss:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.',
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
