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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','DemonHunter-Havoc','Paladin-Holy','Druid-Restoration','Druid-Balance','Unknown-Unknown','Rogue-Subtlety','Paladin-Retribution','Rogue-Assassination','Druid-Guardian','Druid-Feral','Hunter-Marksmanship','Warrior-Arms','Shaman-Restoration','DemonHunter-Devourer','DeathKnight-Unholy','Shaman-Elemental','Priest-Shadow','Mage-Arcane','Warrior-Fury','Priest-Holy','Paladin-Protection','Evoker-Preservation','Priest-Discipline','Warlock-Affliction','Warlock-Destruction','Warrior-Protection','DeathKnight-Blood','Shaman-Enhancement',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaron:BAAANQAECgIIAgABNQAECgcIHgABAPAfAA==.Aaronfreeze:BAABNQAECoEjAAICAAkKDiFqEQA1AwACAAkKDiFqEQA1AwAAAA==.',
Ab='Abnar:BAAANQAECgQICAAAAA==.',
Ad='Adversaryq:BAAANQADCgYIBwAAAA==.',
Ai='Aid:BAAANQADCgMIBQAAAA==.',
Al='Alanii:BAAANQAECgUIBQAAAA==.Alaula:BAAANQAECgQIBAAAAA==.Albedô:BAAANQADCgIIBAABNQAECgkJJwADAHkiAA==.Allformarc:BAAANQAECgUJBgAAAA==.Allmaick:BAAANQADCggJDAAAAA==.Alucard:BAABNQAECoEZAAIEAAgK9QuXXAC3AQAEAAgK9QuXXAC3AQAAAA==.Alystrasza:BAABNQAECoEfAAMFAAgKKB7tDADIAgAFAAgKKB7tDADIAgAGAAcKJQ2YRgCCAQAAAA==.',
Am='Ambivalent:BAAANQAECgQIBAABNQAECgQIDQAHAAAAAA==.',
An='Animan:BAAANQABCgIIAgAAAA==.Antimovsky:BAAANQAECgQICgAAAA==.',
Ap='Aphroditê:BAAANQADCgQIBAABNQAECgYIEwAHAAAAAA==.',
Av='Aviaria:BAAANQAECgEIAQAAAA==.',
Ax='Axsenaea:BAAANQADCgEIAQAAAA==.',
['Aì']='Aìnzooalgown:BAAANQAECgcIDwABNQAECgkJJwADAHkiAA==.',
['Aü']='Aütöpsy:BAABNQAECoEWAAIIAAgKCRAVFQAZAgAIAAgKCRAVFQAZAgAAAA==.',
Ba='Babylonfive:BAABNQAECoEqAAIJAAkKfSH5DwBtAwAJAAkKfSH5DwBtAwAAAA==.Backstabbath:BAAANQADCgQIBQAAAA==.Banger:BAAANQAECgIIAwAAAA==.',
Be='Belleta:BAAANQAECgEIAgAAAA==.Belligerente:BAAANQAECgQIDQAAAA==.Berserk:BAEANQAECgYIDAABNQAECgkJKQAKAJAUAA==.',
Bi='Bigwave:BAAANQADCgQIBAAAAA==.Bigwilli:BAAANQADCgYIDQAAAA==.Birds:BAACNQAFFIEFAAILAAIKuQxBBAB/AAALAAIKuQxBBAB/AAA1AAQKgSEAAwsACQoQIKMDADYDAAsACQpWH6MDADYDAAwABwp9FzkMAPIBAAAA.Biscuit:BAACNQAFFIEKAAMCAAQKtxbfCABTAQACAAQKtxbfCABTAQANAAEKugNmHABBAAA1AAQKgR0AAwIACAorJegxAJUCAAIABwpkJugxAJUCAA0ABgogHMknAMABAAAA.Bisha:BAABNQAECoEwAAIOAAkKRBraNwCvAgAOAAkKRBraNwCvAgAAAA==.Bizcocho:BAAANQAECgUIBgAAAA==.',
Bo='Bonesofdoom:BAAANQADCgEIAQAAAA==.Boomkingobrr:BAAANQAECgYJCQAAAA==.Boops:BAABNQAFFIEFAAIPAAIKGg7cFgCZAAAPAAIKGg7cFgCZAAAAAA==.Bootysweatt:BAAANQADCggICAAAAA==.Boss:BAAANQAECgYIEAAAAA==.',
Bu='Buckayou:BAAANQADCgUIBwAAAA==.Burnsx:BAAANQADCgcIFgABNQAFFAYIFAAQAIsgAA==.',
Bw='Bwoar:BAAANQAECgEIAQAAAA==.',
Ca='Caiandol:BAAANQADCgQIAwAAAA==.Candydreams:BAAANQABCgQIBAAAAA==.Captinfeo:BAAANQADCggICAAAAA==.Captnmurloc:BAAANQAECgYIEQAAAA==.Catara:BAAANQADCgcICwAAAA==.',
Ce='Cedar:BAAANQADCgYICwAAAA==.',
Ch='Cheetos:BAAANQADCggICAAAAA==.Cherga:BAAANQAECgYIDwAAAA==.Chrinn:BAAANQABCgUIBQAAAA==.Church:BAAANQAECgQIBgAAAA==.',
Ci='Cirxe:BAAANQAECgUIEQAAAA==.',
Cl='Clarkent:BAAANQAECgUICAAAAA==.',
Co='Coms:BAAANQAECgYIDAAAAA==.',
Cr='Crayze:BAAANQAECgIIAgAAAA==.',
['Cø']='Cønstance:BAAANQAECgYIDAAAAA==.',
Da='Dabai:BAABNQAECoEcAAIJAAcK8hKRhwCwAQAJAAcK8hKRhwCwAQAAAA==.Daipailaotie:BAAANQAECggIEgAAAA==.Dalight:BAAANQAECgUICAAAAA==.Dankins:BAABNQAFFIELAAIPAAUKjBxlBQDIAQAPAAUKjBxlBQDIAQAAAA==.Darealfarmer:BAAANQADCgcIBwAAAA==.Darkzoomies:BAAANQAECgMJAwAAAA==.',
De='Depar:BAAANQAECgMIAwAAAA==.Dethsent:BAAANQAECgIJAgAAAA==.Dette:BAAANQAECgQICAAAAA==.Devourer:BAABNQAECoExAAIQAAkKACJ9AwCTAwAQAAkKACJ9AwCTAwAAAA==.',
Dk='Dkboss:BAAANQADCgYIEQABNQAECgQIEAAHAAAAAA==.',
Do='Doctrdoom:BAAANQADCggIEAABNQAECgcIHgABAPAfAA==.',
Dr='Drafted:BAAANQAECgYIDQAAAA==.Dragondank:BAAANQAFFAEIAgABNQAFFAUICwAPAIwcAA==.Drukah:BAAANQADCgcIDAAAAA==.',
Dt='Dtrike:BAAANQAECgIIBAAAAA==.',
Ed='Edstark:BAAANQAECgUIEwAAAA==.',
El='Elabernathy:BAAANQAECgQIBQAAAA==.Elenay:BAAANQAECgUIEAAAAA==.Elliemental:BAAANQADCgQIBAAAAA==.Elpatron:BAABNQAECoEmAAIFAAkKYiHXAwBvAwAFAAkKYiHXAwBvAwAAAA==.Elylanea:BAAANQADCggICAAAAA==.',
Em='Emulsdeath:BAABNQAECoEbAAIRAAcKKyExHwCIAgARAAcKKyExHwCIAgABNQAECgkJPAAJAFcmAA==.Emulsifier:BAABNQAECoE8AAIJAAkKVybfAQDsAwAJAAkKVybfAQDsAwAAAA==.Emulslash:BAAANQADCgYJDAABNQAECgkJPAAJAFcmAA==.',
Ev='Evideia:BAAANQADCgQJBAABNQAECgYIEwAHAAAAAA==.',
Ex='Expiredbeef:BAAANQADCgYIBgAAAA==.',
Fa='Farcha:BAAANQADCgIIAgABNQADCggICwAHAAAAAA==.',
Fi='Fidge:BAAANQADCgYIBgAAAA==.Finester:BAAANQAECgcIDQAAAA==.',
Fl='Flatline:BAAANQAECgUIBQAAAA==.',
Fu='Funslinger:BAAANQADCggICgAAAA==.',
Ga='Gagners:BAAANQAECgUICQABNQAECgkJPAAJAFcmAA==.',
Go='Gorska:BAABNQAECoEYAAISAAcK7Rx8OABNAgASAAcK7Rx8OABNAgAAAA==.',
Gr='Grawm:BAAANQAECgYIDgAAAA==.Gritshaman:BAAANQAECgQJBAABNQAECgcIHgABAPAfAA==.',
['Gä']='Gämbit:BAAANQAECgMIAwAAAA==.',
Ha='Hangman:BAAANQAECgYJDQAAAA==.Hanni:BAAANQADCggJIQAAAA==.Hawktoetem:BAAANQADCgQIBAAAAA==.Hawktoouh:BAAANQAECgYIEQAAAA==.',
He='Hellshand:BAAANQAECgUICQAAAA==.Helmhammer:BAAANQAECgEIAQAAAA==.',
Ho='Holychaser:BAAANQAECgMJBwAAAA==.Holycrack:BAAANQAECgUICQABNQAECggIGQABADwfAA==.Holycøw:BAAANQAECgEIAQAAAA==.Holydefender:BAAANQADCgMIAwAAAA==.Holyfyree:BAAANQADCgIIAgABNQAECgcIEQAHAAAAAA==.Holypawk:BAAANQAECgYIDQAAAA==.Holyrock:BAAANQAECgQIBgAAAA==.Honorheart:BAAANQADCgMIBgAAAA==.',
['Hó']='Hóly:BAAANQADCgEJAQABNQAECgYJCQAHAAAAAA==.',
Ih='Ihureciv:BAAANQAECgYIEQABNQAECgkJPgATAG0jAA==.',
Ik='Ikur:BAABNQAECoEgAAIEAAgKDR3QIwCqAgAEAAgKDR3QIwCqAgAAAA==.',
Ip='Ipopkidneys:BAACNQAFFIEMAAMIAAUKUCJxBQCJAQAIAAQKpyFxBQCJAQAKAAEK8iTSDwBlAAA1AAQKgSAAAwgACQp3JSEJAM4CAAgABwoIJiEJAM4CAAoABAoeJGI2AIABAAAA.',
Ir='Iroi:BAAANQAECgIJAgAAAA==.',
Is='Iskur:BAAANQAECgUICwABNQAECggIIAAEAA0dAA==.Isurr:BAAANQAECgUICQABNQAECggIIAAEAA0dAA==.',
Iv='Ivanapump:BAAANQAECgQIBAAAAA==.',
Ja='Jadhar:BAAANQAECgIIBAAAAA==.Jametrok:BAABNQAECoEaAAIJAAgKHRhRXgAnAgAJAAgKHRhRXgAnAgAAAA==.Jastra:BAAANQADCgcIDQAAAA==.',
Je='Jennyanydots:BAAANQADCggICQABNQAFFAYIEAATAM8RAA==.',
Ji='Jiraîya:BAAANQAECgcIEAAAAA==.',
Jo='Jordak:BAABNQAECoEYAAIFAAcKxRyFFgBDAgAFAAcKxRyFFgBDAgAAAA==.Joshua:BAAANQADCgQIBAAAAA==.',
Ju='Jumbok:BAABNQAECoEcAAIUAAcKEhRJsADWAQAUAAcKEhRJsADWAQAAAA==.Just:BAAANQAECggIEgAAAA==.',
Ka='Kaddiya:BAAANQABCgcJEQAAAA==.Kaine:BAAANQADCgUIBQAAAA==.Kallistos:BAABNQAECoEZAAIPAAcK1BV8UgDKAQAPAAcK1BV8UgDKAQAAAA==.Kangaroo:BAAANQADCgQIBAAAAA==.Kaste:BAAANQAECgQIBgAAAA==.',
Ke='Kevdogg:BAAANQAECgYIDAAAAA==.Key:BAABNQAECoEgAAMJAAkKQCLgHQAfAwAJAAkKQCLgHQAfAwAEAAcK/xTDVwDIAQAAAA==.',
Kh='Khione:BAAANQADCgcIFQAAAA==.',
Ki='Kindsöul:BAAANQAECgQIBAABNQAFFAIIBQALALkMAA==.',
Ko='Koluvan:BAAANQADCggIDAAAAA==.Koopa:BAABNQAECoEUAAIVAAcKJR+QBQBzAgAVAAcKJR+QBQBzAgAAAA==.',
Kr='Krieg:BAAANQAECgYIBgABNQAECgkJJAAGALkkAA==.Kromdar:BAAANQADCgMIAwAAAA==.',
Ky='Kyuketsuki:BAAANQADCgEIAQAAAA==.',
Le='Leahan:BAAANQABCgMIAwAAAA==.',
Lh='Lhureciv:BAABNQAECoE+AAMTAAkKbSNECQAoAwATAAgKiiNECQAoAwAWAAQKWhYCgQAkAQAAAA==.',
Li='Lillianna:BAAANQAECgQIBwAAAA==.Lilsensual:BAAANQAECgcIEgABNQAECgkJIgAXAGAXAA==.',
Lo='Loenhart:BAAANQADCgIIAgAAAA==.Logically:BAAANQADCgUIBQAAAA==.Lolkurtone:BAAANQAECgQIBAAAAA==.',
Lu='Luceus:BAAANQAECgUICwAAAA==.Lucário:BAAANQAECggIEgAAAA==.Lugia:BAAANQADCgYJCwAAAA==.Lunadawn:BAAANQAECgUIBQAAAA==.Lunastorm:BAABNQAECoEuAAIYAAkKuRpQCwDLAgAYAAkKuRpQCwDLAgAAAA==.Luponero:BAACNQAFFIEPAAINAAUKGBQmBwCRAQANAAUKGBQmBwCRAQA1AAQKgSAAAw0ACQpiH8MRAK8CAA0ACQoPH8MRAK8CAAIAAQoCJNAGAVMAAAAA.',
Ma='Macmn:BAABNQAECoEiAAISAAkKniU7AwDLAwASAAkKniU7AwDLAwAAAA==.Mamaheals:BAABNQAECoEYAAIWAAcKASNgHwC8AgAWAAcKASNgHwC8AgAAAA==.Mandos:BAAANQAECgcIEwAAAA==.Mantistabogn:BAAANQAECgYIBgAAAA==.Manzoholy:BAAANQADCgMIAwAAAA==.Maor:BAAANQAECgEIAQAAAA==.',
Me='Merlerk:BAAANQAECgIIAgABNQAFFAMICgASAOAZAA==.Merlini:BAABNQAECoEXAAMTAAgKNg5vIgDSAQATAAgKNg5vIgDSAQAZAAQKEBSVDgAQAQAAAA==.Metrohexual:BAABNQAECoEXAAIPAAcKhBDoZQCEAQAPAAcKhBDoZQCEAQAAAA==.Mets:BAAANQAECgUIBQABNQAECgQIBQAHAAAAAA==.',
Mi='Mikasa:BAAANQAECgQIBAABNQAECgYJCQAHAAAAAA==.Mitzis:BAABNQAECoEXAAICAAgKBCDjHwDgAgACAAgKBCDjHwDgAgAAAA==.',
Mo='Moltten:BAAANQADCgcIHgAAAA==.Moondo:BAECNQAFFIEVAAIGAAcKsRw5AgB0AgAGAAcKsRw5AgB0AgA1AAQKgSoAAwYACQrjJE8JAG4DAAYACQrjJE8JAG4DAAUABApaBUNCALIAAAE1AAQKBwgQAAcAAAAA.',
['Mè']='Mètis:BAAANQAECgYIEwAAAA==.',
Na='Naahx:BAAANQAECgcJCAABNQAECggIFwAKANUhAA==.',
Ne='Nefarius:BAABNQAECoEeAAITAAkKtx9ACAA4AwATAAkKtx9ACAA4AwAAAA==.Neuropolis:BAAANQADCgYIBgAAAA==.Neurotics:BAABNQAECoEWAAQaAAcKNiMACgCHAQABAAYKwCEERQBCAgAaAAQKnB4ACgCHAQAbAAMKTiIeKAAhAQAAAA==.',
Ni='Nineoneone:BAABNQAECoEYAAIWAAcK3A3oZwB/AQAWAAcK3A3oZwB/AQAAAA==.',
No='Noperr:BAAANQAECggICAAAAA==.',
Nu='Nurmally:BAAANQAECgYICgABNQAFFAUIBgACAIYSAA==.',
Oc='Ocra:BAAANQAECgUIDwABNQAECgkJKAACAOYZAA==.',
Of='Offspeck:BAAANQAECgQIBQABNQAECgcIHgABAPAfAA==.',
Ol='Oldirtycasta:BAAANQAECgEIAQABNQAECgQIDQAHAAAAAA==.',
Or='Origen:BAAANQADCgcIBwABNQAECgkJKgAJAH0hAA==.',
Ou='Outbreak:BAAANQADCggICAAAAA==.',
Pa='Paladio:BAAANQAECgUIDwAAAA==.Pandapwr:BAAANQADCgcIBwABNQAECgEIAQAHAAAAAA==.Pandemul:BAAANQADCggJCAABNQAECgkJPAAJAFcmAA==.Patrio:BAAANQADCgYICwABNQAECgkJJgAFAGIhAA==.Pawkler:BAAANQAECgQIBAABNQAECgYIDQAHAAAAAA==.Pawshira:BAAANQADCgUIBQABNQAECgYIDQAHAAAAAA==.',
Pe='Peachie:BAAANQADCgcIBwAAAA==.Peetree:BAABNQAECoEaAAIPAAgKdiE7FAD9AgAPAAgKdiE7FAD9AgAAAA==.Perfectcell:BAAANQADCgUIBQAAAA==.Petures:BAAANQADCgUIBQAAAA==.',
Ph='Phosphorus:BAABNQAECoFPAAMcAAkKlBseCgBQAgAOAAkKyRYjSQBxAgAcAAgK6xoeCgBQAgAAAA==.',
Pl='Plagüë:BAABNQAECoEuAAMdAAkKVRsTJwBOAgAdAAgK1xoTJwBOAgARAAkKtxTaKgA1AgAAAA==.',
Po='Polor:BAAANQADCgQIBAAAAA==.',
Pr='Precious:BAAANQAECgEIAQAAAA==.Primalistic:BAAANQAECgQIBQAAAA==.',
Pu='Pullnprey:BAAANQADCgMJBAAAAA==.Purgedoctor:BAABNQAFFIEIAAIPAAMK8h3YDAATAQAPAAMK8h3YDAATAQAAAA==.',
['Pà']='Pàladin:BAAANQADCgYIBgAAAA==.',
Qt='Qtptt:BAACNQAFFIEOAAIBAAUKWyIkBADeAQABAAUKWyIkBADeAQA1AAQKgSoAAgEACQqOJcQDAKEDAAEACQqOJcQDAKEDAAAA.',
Ra='Ravenoflight:BAAANQAECgIIAwAAAA==.Ravenshatred:BAAANQADCggJDAAAAA==.Ravenswrath:BAAANQADCgYJBgAAAA==.Rawrsaur:BAAANQAECgYIDgAAAA==.',
Re='Recon:BAAANQADCgMIAwABNQAECggJEgAHAAAAAA==.Rein:BAAANQAECgQIBwAAAA==.Remin:BAAANQADCgcIDAAAAA==.Retaliator:BAAANQAECgEIAQAAAA==.Reuuín:BAAANQADCgQIBAABNQAECgUIDwAHAAAAAA==.Revan:BAAANQADCggICAAAAA==.',
Ri='Risquae:BAAANQAECgEIAQAAAA==.',
Ro='Rosè:BAAANQAECgcIDQABNQAECgcIEwAHAAAAAA==.',
Ru='Ruka:BAAANQAECgQIBQAAAA==.',
Ry='Ryguyro:BAAANQADCgIJAgAAAA==.Ryhia:BAAANQAECgIIAgABNQAECgcIEwAHAAAAAA==.Ryzee:BAABNQAECoEbAAIUAAkKWxMZgQBBAgAUAAkKWxMZgQBBAgABNQAFFAEIAQAHAAAAAA==.',
['Rí']='Ríco:BAAANQADCgUIDQAAAA==.',
Sa='Sajaboy:BAAANQADCgIIAgAAAA==.Salena:BAAANQAECgIIAwAAAA==.Sartha:BAAANQAECgYIDwAAAA==.Sasuka:BAAANQAECgMIBAAAAA==.Savagesoso:BAAANQADCgQJBAAAAA==.',
Sc='Schy:BAAANQAECgIIAgAAAA==.Scrumpheals:BAAANQADCgcIDQAAAA==.',
Se='Sedda:BAABNQAECoEiAAIJAAkKPyW2DQB7AwAJAAkKPyW2DQB7AwAAAA==.Sensual:BAABNQAECoEiAAIXAAkKYBdVDwBaAgAXAAkKYBdVDwBaAgAAAA==.Sesshomaru:BAABNQAECoEnAAIDAAkKeSJVBwBhAwADAAkKeSJVBwBhAwAAAA==.',
Sh='Shampain:BAAANQAECgUICwABNQAECgkJOAAEANkbAA==.Shang:BAABNQAECoEkAAIGAAkKuSQtBQCgAwAGAAkKuSQtBQCgAwAAAA==.Shirona:BAABNQAECoEXAAMDAAgKZxjeHABsAgADAAgKZxjeHABsAgAQAAcKIwsjLwCHAQAAAA==.Shloomish:BAAANQADCgEIAQAAAA==.Shãde:BAAANQADCgIIAgAAAA==.Shïnwolford:BAABNQAECoEZAAIUAAgKwBQLiQAuAgAUAAgKwBQLiQAuAgABNQAECgkJJwADAHkiAA==.',
Si='Siare:BAAANQAECgQIBQAAAA==.',
Sk='Skeeter:BAABNQAECoEbAAQbAAcKOx7AEgDOAQAbAAYKgBnAEgDOAQABAAQKyx5+iABuAQAaAAEKCRJTJQA7AAAAAA==.Skroncer:BAAANQADCgYIDwAAAA==.',
Sm='Smokinjawn:BAAANQADCgMIAwAAAA==.Smòtts:BAABNQAECoEYAAILAAcKcR1zCwA+AgALAAcKcR1zCwA+AgAAAA==.Smótts:BAAANQADCggJEwAAAA==.',
Sn='Sneekee:BAAANQAECgIIBAABNQAECgQIBAAHAAAAAA==.Snizard:BAAANQAECgUICwAAAA==.Snuggiepoo:BAAANQADCgIIAgABNQAECgMIBQAHAAAAAA==.',
So='Soawesome:BAAANQAECgQIBAABNQAECgQIDQAHAAAAAA==.Solenoid:BAAANQADCggIEAAAAA==.',
Sp='Spicymustard:BAAANQADCgYICgAAAA==.Spàdes:BAAANQAECgIJAgAAAA==.',
Sq='Squírtlé:BAAANQADCgEIAQAAAA==.',
St='Stellanoova:BAAANQAECgQICAABNQAECgcIEQAHAAAAAA==.Stuwu:BAAANQABCgQIBAAAAA==.',
Su='Sugarhigh:BAAANQABCgQIBAAAAA==.Sunlight:BAAANQADCggICQAAAA==.Sushirollz:BAAANQAECgEIAQAAAA==.',
Ta='Taazdingo:BAAANQADCgYJCwAAAA==.Takin:BAAANQADCggICAAAAA==.Taxxwomann:BAABNQAECoEkAAMBAAkKJiJkKQCoAgABAAcKrCFkKQCoAgAbAAMKyR3ZKwALAQAAAA==.',
Th='Thisishard:BAABNQAECoEfAAIUAAgK/RKElgAPAgAUAAgK/RKElgAPAgAAAA==.Thryen:BAAANQAECgQICQAAAA==.Thundergrasp:BAAANQAFFAEIAQAAAA==.',
To='Toe:BAAANQAECgEIAQAAAA==.Toobestake:BAAANQABCgUIBQABNQAFFAUIDwANABgUAA==.Topenga:BAABNQAECoEoAAICAAkK5hk3IwDSAgACAAkK5hk3IwDSAgAAAA==.',
Tr='Trunnks:BAAANQAECgEIAQAAAA==.',
Ts='Tsargock:BAAANQADCgUIBAAAAA==.',
Tu='Tuoldforthis:BAAANQADCgIJAgAAAA==.',
Tw='Twicelife:BAAANQAECgUICQABNQAECgkJTwAcAJQbAA==.',
['Tñ']='Tñt:BAAANQADCggICwABNQAECgcIHgABAPAfAA==.',
Ur='Urbek:BAAANQAECgYIEwAAAA==.Urthstripe:BAAANQAECgYIDgAAAA==.',
Uw='Uwu:BAAANQADCgQIBgABNQAFFAYIEAATAM8RAA==.',
Va='Valle:BAAANQADCgcICAABNQAFFAYIEAATAM8RAA==.Valoria:BAAANQADCgYIBwABNQAFFAYIEAATAM8RAA==.',
Ve='Velgabrine:BAAANQAECgQICAABNQAECgkJPAAJAFcmAA==.Veraani:BAAANQADCggICAAAAA==.Verlaria:BAAANQADCgEIAQAAAA==.',
Vi='Viserion:BAAANQAECgcIEQAAAA==.',
Vu='Vue:BAABNQAECoE4AAIEAAkK2RvKFQD/AgAEAAkK2RvKFQD/AgAAAA==.',
Wa='Wakasham:BAABNQAECoEfAAIeAAkKSyZEAADxAwAeAAkKSyZEAADxAwAAAA==.Warwick:BAAANQABCgIIAgAAAA==.',
We='Wehonoryou:BAAANQAECgcIEAABNQAFFAYIFAAQAIsgAA==.',
Wo='Wolfpacked:BAABNQAECoEVAAIPAAYKyhjVVgC5AQAPAAYKyhjVVgC5AQABNQAECggIGQABADwfAA==.',
Wr='Wrbringer:BAAANQADCgEIAQAAAA==.',
Wu='Wunderlust:BAABNQAECoEjAAIUAAgKlRvjbwBqAgAUAAgKlRvjbwBqAgAAAA==.',
Ye='Yellowshaman:BAABNQAECoEiAAISAAkKXxs/HQDqAgASAAkKXxs/HQDqAgAAAA==.',
Za='Zandelussy:BAAANQAECgMIBQAAAA==.',
Zu='Zugg:BAAANQAECgYIBgABNQAFFAYIEAATAM8RAA==.Zuriznikov:BAAANQAECgQICQABNQAECgcIEQAHAAAAAA==.',
['Øf']='Øffspeck:BAABNQAECoEeAAQBAAcK8B/RNAB8AgABAAcKCh7RNAB8AgAaAAUKXhonCgCDAQAbAAMKTB5GLgD9AAAAAA==.',
['ßo']='ßoss:BAAANQADCgQIBAABNQAECgQIEAAHAAAAAA==.',
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
