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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','DemonHunter-Havoc','Paladin-Holy','Druid-Restoration','Druid-Balance','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Paladin-Retribution','Rogue-Assassination','Druid-Guardian','Druid-Feral','Hunter-Marksmanship','Warrior-Arms','Shaman-Restoration','Warrior-Protection','DemonHunter-Devourer','Mage-Arcane','Paladin-Protection','Shaman-Elemental','Priest-Holy','Priest-Shadow','Evoker-Augmentation','DeathKnight-Frost','Warrior-Fury','Evoker-Preservation','Priest-Discipline','Warlock-Affliction','Warlock-Destruction','Shaman-Enhancement',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaron:BAAANQAECgIIAgABNQAECgkJKgABAH8gAA==.Aaronfreeze:BAABNQAECoEmAAICAAkKDiFVGQAcAwACAAkKDiFVGQAcAwAAAA==.',
Ab='Abnar:BAAANQAECgQIDAAAAA==.',
Ad='Adversaryq:BAAANQADCgYIBwAAAA==.',
Ai='Aid:BAAANQADCgMIBQAAAA==.',
Al='Alanii:BAAANQAECgUIBQAAAA==.Alaula:BAAANQAECgQIBAAAAA==.Albedô:BAAANQADCgIIBAABNQAECgkJLwADANoiAA==.Allformarc:BAAANQAECgUJBgAAAA==.Allmaick:BAAANQADCggJDAAAAA==.Alucard:BAABNQAECoEhAAIEAAgKAxUASgAgAgAEAAgKAxUASgAgAgAAAA==.Alystrasza:BAABNQAECoElAAMFAAgK3R7bDgDJAgAFAAgK3R7bDgDJAgAGAAcKJQ2UTwB1AQAAAA==.',
Am='Ambivalent:BAAANQAECgQIBwABNQAECgQIDQAHAAAAAA==.',
An='Animan:BAAANQABCgIIAgAAAA==.Antimovsky:BAAANQAECgQICgAAAA==.',
Ap='Aphroditê:BAAANQADCgQIBAABNQAECgcIGwACADYcAA==.',
Ar='Arrowsmïth:BAAANQADCgQIBAAAAA==.',
Av='Aviaria:BAAANQAECgEIAQAAAA==.',
Ax='Axsenaea:BAAANQADCgEIAQAAAA==.',
['Aì']='Aìnzooalgown:BAABNQAECoEYAAMIAAkKmhshJgCEAgAIAAkKmhshJgCEAgAJAAEK1QXZvgAuAAABNQAECgkJLwADANoiAA==.',
['Aü']='Aütöpsy:BAABNQAECoEeAAIKAAgKWRbZEABfAgAKAAgKWRbZEABfAgAAAA==.',
Ba='Babylonfive:BAABNQAECoEzAAILAAkK4yOqBwC0AwALAAkK4yOqBwC0AwAAAA==.Backstabbath:BAAANQADCgQIBQAAAA==.Banger:BAAANQAECgMIBgAAAA==.',
Be='Belleta:BAAANQAECgEIAgAAAA==.Belligerente:BAAANQAECgQIDQAAAA==.Berserk:BAEANQAECgcIEgABNQAFFAQIBgAMAGQCAA==.Bertringer:BAAANQAECgMIAwABNQAECgQIBQAHAAAAAA==.',
Bi='Bigwave:BAAANQADCgQIBAAAAA==.Bigwilli:BAAANQADCgYIDQAAAA==.Bilefiend:BAAANQADCgMIAwAAAA==.Birds:BAACNQAFFIEIAAINAAMKAQ0EBADDAAANAAMKAQ0EBADDAAA1AAQKgSUABA0ACQofIPwEACoDAA0ACQplH/wEACoDAA4ABwp9F9YOAOoBAAYAAQo0DgAAAAAAAAAA.Biscuit:BAACNQAFFIEQAAMCAAUKeBQ2CACeAQACAAUKeBQ2CACeAQAPAAMK9gTrFQCmAAA1AAQKgSMAAwIACAorJcsoANUCAAIACAoiJcsoANUCAA8ABwrsHDwhACUCAAAA.Bisha:BAABNQAECoE4AAIQAAkKSR0zJwANAwAQAAkKSR0zJwANAwAAAA==.Bizcocho:BAAANQAECgUIBwAAAA==.',
Bo='Bonesofdoom:BAAANQADCgEIAQAAAA==.Boomkingobrr:BAAANQAECgYJCQAAAA==.Boops:BAABNQAFFIEIAAIRAAMKkQr7EwDgAAARAAMKkQr7EwDgAAAAAA==.Bootysweatt:BAAANQADCggICAAAAA==.Boss:BAABNQAECoEbAAISAAcKMiElCQCQAgASAAcKMiElCQCQAgAAAA==.',
Bu='Buckayou:BAAANQADCgUIBwAAAA==.Burnsx:BAAANQADCggIGAABNQAFFAcIFgATAEgfAA==.',
Bw='Bwoar:BAAANQAECgcICAAAAA==.',
Ca='Caiandol:BAAANQADCgQIAwAAAA==.Candydreams:BAAANQABCgQIBAAAAA==.Captinfeo:BAAANQADCggICAAAAA==.Captnmurloc:BAAANQAECgcIEgAAAA==.Catara:BAAANQADCgcICwAAAA==.',
Ce='Cedar:BAAANQAECgMIAwAAAA==.',
Ch='Cheetos:BAAANQADCggICAAAAA==.Cherga:BAAANQAECgYIDwAAAA==.Chrinn:BAAANQABCgUIBQAAAA==.Church:BAAANQAECgcIDQAAAA==.',
Ci='Cirxe:BAABNQAECoEcAAIUAAcKMATtEwFEAQAUAAcKMATtEwFEAQAAAA==.',
Cl='Clarkent:BAAANQAECgUICAAAAA==.',
Co='Coms:BAAANQAECgcIEQAAAA==.',
Cr='Crayze:BAAANQAECgIIBAAAAA==.',
['Cø']='Cønstance:BAAANQAECgYIDwAAAA==.',
Da='Dabai:BAABNQAECoEhAAILAAgK1xOFegAGAgALAAgK1xOFegAGAgAAAA==.Daipailaotie:BAABNQAECoEZAAMLAAgKMwb92QAtAQALAAcKMwb92QAtAQAVAAQK0wPQTwB3AAAAAA==.Dalight:BAAANQAECgUICAAAAA==.Dankins:BAABNQAFFIEPAAIRAAUK4B16BgDYAQARAAUK4B16BgDYAQAAAA==.Darealfarmer:BAAANQADCgcIBwAAAA==.Darkzoomies:BAAANQAECgMJAwAAAA==.',
De='Depar:BAAANQAECgMIAwAAAA==.Dethsent:BAAANQAECgIIAgAAAA==.Dette:BAAANQAECgQIDAAAAA==.Devourer:BAABNQAECoE7AAITAAkKSiKuAwCWAwATAAkKSiKuAwCWAwAAAA==.',
Dk='Dkboss:BAAANQADCgYIEQABNQAECgcIGwASADIhAA==.',
Do='Doctrdoom:BAAANQADCggIEAABNQAECgkJKgABAH8gAA==.',
Dr='Drafted:BAAANQAECgYIDQAAAA==.Dragondank:BAAANQAFFAEIAgABNQAFFAUIDwARAOAdAA==.Drukah:BAAANQADCgcIEwAAAA==.',
Dt='Dtrike:BAAANQAECgIIBAAAAA==.',
Ed='Edstark:BAABNQAECoEaAAIDAAcKLAKUYQDCAAADAAcKLAKUYQDCAAAAAA==.',
El='Elabernathy:BAAANQAECgQICAAAAA==.Elenay:BAABNQAECoEbAAIGAAgKxCJZEQApAwAGAAgKxCJZEQApAwAAAA==.Eliarssande:BAAANQAECgYIBgAAAA==.Elliemental:BAAANQADCgQIBAAAAA==.Elpatron:BAABNQAECoEqAAIFAAkKEyJABAByAwAFAAkKEyJABAByAwAAAA==.Elylanea:BAAANQADCggICAAAAA==.',
Em='Emulsdeath:BAABNQAECoEiAAIIAAcKSiJOJgCDAgAIAAcKSiJOJgCDAgABNQAECgkJPAALAFcmAA==.Emulsifier:BAABNQAECoE8AAILAAkKVyaiAwDYAwALAAkKVyaiAwDYAwAAAA==.Emulslash:BAAANQADCgYIDAABNQAECgkJPAALAFcmAA==.',
Ev='Evideia:BAAANQADCgQJBAABNQAECgcIGwACADYcAA==.',
Ex='Expiredbeef:BAAANQADCgYIBgAAAA==.',
Fa='Farcha:BAAANQADCgIIAgABNQADCggICwAHAAAAAA==.',
Fi='Fidge:BAAANQADCgYIBgAAAA==.Finester:BAAANQAECgcIDwAAAA==.',
Fl='Flatline:BAAANQAECgYICwAAAA==.',
Fu='Funslinger:BAAANQADCggICgAAAA==.',
Ga='Gagners:BAAANQAECgYIDwABNQAECgkJPAALAFcmAA==.',
Go='Gorska:BAABNQAECoEfAAIWAAgK4BxiKwCuAgAWAAgK4BxiKwCuAgAAAA==.',
Gr='Grawm:BAAANQAECgYIDgAAAA==.Gritshaman:BAAANQAECgQIBAABNQAECgkJKgABAH8gAA==.',
['Gä']='Gämbit:BAAANQAECgQIBAAAAA==.',
Ha='Hangman:BAAANQAECgYJDQAAAA==.Hanni:BAAANQAECgUIBQAAAA==.Harakutoo:BAAANQADCgcIBwAAAA==.Hawktoetem:BAAANQADCgQIBAAAAA==.Hawktoouh:BAABNQAECoEbAAMXAAcKhBt1PABUAgAXAAcKhBt1PABUAgAYAAEKRQ7LcQAsAAAAAA==.',
He='Hellshand:BAAANQAECgUICQAAAA==.Helmhammer:BAAANQAECgEIAQAAAA==.',
Hi='Hinxx:BAAANQABCgQIAgAAAA==.',
Ho='Holychaser:BAAANQAECgMJBwAAAA==.Holycrack:BAAANQAECgUICwABNQAECgkJIAABAC4hAA==.Holycøw:BAAANQAECgEIAQAAAA==.Holydefender:BAAANQADCgMIAwAAAA==.Holyfyree:BAAANQADCgMIAwABNQAECggIGQAZALIPAA==.Holypawk:BAAANQAECgYIEgAAAA==.Holyrock:BAAANQAECgQICQAAAA==.Honorheart:BAAANQADCgMIBgAAAA==.',
['Hó']='Hóly:BAAANQADCgEJAQABNQAECgYJCQAHAAAAAA==.',
Ih='Ihureciv:BAABNQAECoEbAAIPAAcK+Bt0HQBJAgAPAAcK+Bt0HQBJAgABNQAECgkJRgAYAFIjAA==.',
Ik='Ikur:BAABNQAECoEoAAIEAAkKyxp4HwDcAgAEAAkKyxp4HwDcAgAAAA==.',
Ip='Ipopkidneys:BAACNQAFFIERAAMKAAYK0CKUAwD0AQAKAAUKYiKUAwD0AQAMAAEK8iQ6FQBfAAA1AAQKgSIAAwoACQp3JakKALwCAAoABwoIJqkKALwCAAwABAoeJKxCAHoBAAAA.',
Ir='Iroi:BAAANQAECgIJAgAAAA==.',
Is='Iskur:BAAANQAECgYIEQABNQAECgkJKAAEAMsaAA==.Isurr:BAAANQAECgUIDQABNQAECgkJKAAEAMsaAA==.',
Iv='Ivanapump:BAAANQAECgQIBAAAAA==.',
Ja='Jadhar:BAAANQAECgIIBAAAAA==.Jametrok:BAABNQAECoEaAAILAAgKHRjldgAQAgALAAgKHRjldgAQAgAAAA==.Jastra:BAAANQADCgcIDQAAAA==.',
Je='Jennyanydots:BAAANQADCggICgABNQAFFAYIFQAYAJUVAA==.',
Ji='Jiraîya:BAAANQAECggIEgAAAA==.',
Jo='Jordak:BAABNQAECoEeAAIFAAgKXRxIEQCqAgAFAAgKXRxIEQCqAgAAAA==.Joshua:BAAANQADCgQIBAAAAA==.',
Ju='Jumbok:BAABNQAECoEcAAIUAAcKEhQ+yQDOAQAUAAcKEhQ+yQDOAQAAAA==.Just:BAABNQAECoEYAAMIAAgKPhAxTgCyAQAIAAgKAhAxTgCyAQAaAAQKaAyzYgDMAAAAAA==.',
Ka='Kaddiya:BAAANQABCgcIEQAAAA==.Kaine:BAAANQADCgUIBQAAAA==.Kallistos:BAABNQAECoEbAAIRAAcKlBhAVgDhAQARAAcKlBhAVgDhAQAAAA==.Kangaroo:BAAANQADCgQIBAAAAA==.Kaste:BAAANQAECgQIBgAAAA==.Katalaana:BAAANQAECgEIAQAAAA==.',
Ke='Kevdogg:BAAANQAECgYIEQAAAA==.Key:BAACNQAFFIEHAAMLAAQKohwVDwAcAQALAAMKNCAVDwAcAQAEAAEKbwvwIQBOAAA1AAQKgSMAAwsACQrpIn8jAB0DAAsACQrpIn8jAB0DAAQABwr/FEhmAL8BAAAA.',
Kh='Khione:BAAANQADCgcIFQAAAA==.',
Ki='Kindsöul:BAAANQAECgQICAABNQAFFAMICAANAAENAA==.',
Ko='Koluvan:BAAANQADCggIEwAAAA==.Koopa:BAABNQAECoEaAAIbAAgKVCAOBADhAgAbAAgKVCAOBADhAgAAAA==.',
Kr='Krieg:BAAANQAECgYIBgABNQAECgkJJwAGAFclAA==.Kromdar:BAAANQADCgMIAwAAAA==.',
Ky='Kyuketsuki:BAAANQADCgEIAQAAAA==.',
Le='Leahan:BAAANQABCgMIAwAAAA==.',
Lh='Lhureciv:BAABNQAECoFGAAMYAAkKUiNtAwCZAwAYAAkKUiNtAwCZAwAXAAQKWhZukwAgAQAAAA==.',
Li='Lillianna:BAAANQAECgUIDAAAAA==.Lilsensual:BAABNQAECoEdAAIRAAgKahPQXADKAQARAAgKahPQXADKAQABNQAECgkJKgAVAF4ZAA==.',
Lo='Loenhart:BAAANQADCgIIAgAAAA==.Logically:BAAANQADCgUIBQAAAA==.Lolkurtone:BAAANQAECgQIBAAAAA==.',
Lu='Luceus:BAAANQAECgYIEQAAAA==.Lucário:BAABNQAECoEVAAIQAAgKiyDRMgDgAgAQAAgKiyDRMgDgAgAAAA==.Lugia:BAAANQADCgYJCwAAAA==.Lunadawn:BAAANQAECgYICwAAAA==.Lunastorm:BAABNQAECoE1AAIcAAkK3BpGDQDAAgAcAAkK3BpGDQDAAgAAAA==.Luponero:BAACNQAFFIEVAAMPAAYKehjnCACPAQAPAAUK8RjnCACPAQACAAEKKRYsJwBhAAA1AAQKgSIAAw8ACQrLHyMUAKkCAA8ACQp4HyMUAKkCAAIAAQoCJIomAVIAAAAA.',
Ma='Macmn:BAACNQAFFIEIAAIWAAUKwxWZCAC1AQAWAAUKwxWZCAC1AQA1AAQKgSUAAhYACQqzJeADAMcDABYACQqzJeADAMcDAAAA.Magej:BAAANQADCgQIBAAAAA==.Mageyouacake:BAAANQADCgQIBAAAAA==.Mamaheals:BAABNQAECoEdAAIXAAcKASMwJgC1AgAXAAcKASMwJgC1AgAAAA==.Mandos:BAABNQAECoEfAAIJAAgKxiQxCgBWAwAJAAgKxiQxCgBWAwAAAA==.Mantistabogn:BAAANQAECgYIBgAAAA==.Manzoholy:BAAANQADCgMIAwAAAA==.Maor:BAAANQAECgEIAQAAAA==.',
Me='Merlerk:BAAANQAECgIIAgABNQAFFAQIEgAWAHwZAA==.Merlini:BAABNQAECoEbAAMYAAgKcA9mJgDSAQAYAAgKcA9mJgDSAQAdAAQKEBTQEAAEAQAAAA==.Metrohexual:BAABNQAECoEcAAIRAAcKkBMyZQCuAQARAAcKkBMyZQCuAQAAAA==.Mets:BAAANQAECgUIBQABNQAECgYICwAHAAAAAA==.',
Mi='Mikasa:BAAANQAECgQIBAABNQAECgYJCQAHAAAAAA==.Mitzis:BAABNQAECoEaAAICAAgKVCD7KADUAgACAAgKVCD7KADUAgAAAA==.',
Mo='Moltten:BAAANQADCgcIJAAAAA==.Moondo:BAECNQAFFIEaAAIGAAcKWR8BAgCjAgAGAAcKWR8BAgCjAgA1AAQKgSoAAwYACQrjJBUMAFsDAAYACQrjJBUMAFsDAAUABApaBa1MAKoAAAE1AAQKBwgSAAcAAAAA.',
['Mè']='Mètis:BAABNQAECoEbAAICAAcKNhy6VABKAgACAAcKNhy6VABKAgAAAA==.',
Na='Naahx:BAAANQAECgcJCAABNQAECggIHAAMAM8iAA==.',
Ne='Nefarius:BAABNQAECoEjAAIYAAkKkSA2CQA5AwAYAAkKkSA2CQA5AwAAAA==.Neuropolis:BAAANQADCgYIBgAAAA==.Neurotics:BAABNQAECoEdAAQBAAcKICVRLAC7AgABAAcKzyNRLAC7AgAeAAQK5h6nCwCEAQAfAAMKTiLqKQAgAQAAAA==.',
Ni='Nineoneone:BAABNQAECoEfAAIXAAcKAxnGSgAdAgAXAAcKAxnGSgAdAgAAAA==.',
No='Noperr:BAAANQAECggICAAAAA==.',
Nu='Nurmally:BAAANQAECgYICgABNQAFFAUIBgACAIYSAA==.',
Oc='Ocra:BAABNQAECoEZAAIgAAcKPxLYFADyAQAgAAcKPxLYFADyAQABNQAECgkJMAACAJEdAA==.',
Of='Offspeck:BAAANQAECgQIBQABNQAECgkJKgABAH8gAA==.',
Ol='Oldirtycasta:BAAANQAECgEIAgABNQAECgQIDQAHAAAAAA==.',
On='Onayhawe:BAAANQAECgMIAwAAAA==.',
Or='Origen:BAAANQADCgcIBwABNQAECgkJMwALAOMjAA==.',
Ou='Outbreak:BAAANQADCggICAAAAA==.',
Pa='Paladio:BAABNQAECoEYAAILAAcKAQcK1AA5AQALAAcKAQcK1AA5AQAAAA==.Pallysmack:BAAANQADCgEIAQAAAA==.Pandapwr:BAAANQADCgcIDwABNQAECgcICAAHAAAAAA==.Pandemul:BAAANQADCggICAABNQAECgkJPAALAFcmAA==.Patrio:BAAANQADCgYICwABNQAECgkJKgAFABMiAA==.Pawkler:BAAANQAECgQIBAABNQAECgYIEgAHAAAAAA==.Pawshira:BAAANQADCgUIBQABNQAECgYIEgAHAAAAAA==.',
Pe='Peachie:BAAANQADCgcIBwAAAA==.Peetree:BAABNQAECoEhAAIRAAgKLCPEEQAiAwARAAgKLCPEEQAiAwAAAA==.Perfectcell:BAAANQADCgYICwAAAA==.Petures:BAAANQAECgMIAwAAAA==.',
Ph='Phosphorus:BAABNQAECoFdAAMSAAkK8RvJDAA7AgAQAAkKLhprPgC3AgASAAgK6xrJDAA7AgAAAA==.',
Pl='Plagüë:BAABNQAECoE2AAMJAAkKWR4rEgAHAwAJAAkKux0rEgAHAwAIAAkKtxQ6OQAaAgAAAA==.',
Po='Polor:BAAANQADCgQIBAAAAA==.',
Pr='Precious:BAAANQAECgQIBQAAAA==.Primalistic:BAAANQAECgQIBQAAAA==.',
Pu='Pullnprey:BAAANQADCgMIBAAAAA==.Purgedoctor:BAABNQAFFIEIAAIRAAMK8h3NEAAOAQARAAMK8h3NEAAOAQAAAA==.',
['Pà']='Pàladin:BAAANQADCgYIBgAAAA==.',
Qt='Qtptt:BAACNQAFFIESAAIBAAYKxSE8AgBLAgABAAYKxSE8AgBLAgA1AAQKgSoAAgEACQqOJZ8GAIoDAAEACQqOJZ8GAIoDAAAA.',
Ra='Ravenoflight:BAAANQAECgIIAwAAAA==.Ravenshatred:BAAANQADCggIEgAAAA==.Ravenswrath:BAAANQADCgYIBgAAAA==.Rawrsaur:BAAANQAECgYIDgAAAA==.',
Re='Reallyhpal:BAAANQAECgMIAgAAAA==.Recon:BAAANQADCgMIAwABNQAECggJEgAHAAAAAA==.Rein:BAAANQAECgQIDgAAAA==.Remin:BAAANQADCggIFAAAAA==.Retaliator:BAAANQAECgEIAQAAAA==.Reuuín:BAAANQADCgQIBAABNQAECgYIEAAHAAAAAA==.Revan:BAAANQADCggIDgAAAA==.',
Ri='Risquae:BAAANQAECgEIAQAAAA==.',
Ro='Rosè:BAAANQAECgcIDQABNQAECggIHwAJAMYkAA==.',
Ru='Ruka:BAAANQAECgQIBQAAAA==.',
Ry='Ryguyro:BAAANQADCgIJAgAAAA==.Ryhia:BAAANQAECgIIAgABNQAECggIHwAJAMYkAA==.Ryzee:BAABNQAECoEcAAIUAAkKWxOhlgA2AgAUAAkKWxOhlgA2AgABNQAECgkJGAAWAIEbAA==.',
['Rí']='Ríco:BAAANQADCgYIDgAAAA==.',
Sa='Sajaboy:BAAANQADCgIIAgAAAA==.Salena:BAAANQAECgQIBwAAAA==.Sartha:BAABNQAECoEZAAILAAgKSBKXfwD5AQALAAgKSBKXfwD5AQAAAA==.Sasuka:BAAANQAECgQICAABNQAECgYIBgAHAAAAAA==.Savagesoso:BAAANQADCgQJBAAAAA==.',
Sc='Schy:BAAANQAECgIIAgAAAA==.Scrumpheals:BAAANQADCgcIDQAAAA==.',
Se='Sedda:BAACNQAFFIEIAAILAAUKxR6fBgC/AQALAAUKxR6fBgC/AQA1AAQKgSUAAgsACQpWJTARAHQDAAsACQpWJTARAHQDAAAA.Sensual:BAABNQAECoEqAAIVAAkKXhlGDgCTAgAVAAkKXhlGDgCTAgAAAA==.Sesshomaru:BAABNQAECoEvAAIDAAkK2iLiBwBsAwADAAkK2iLiBwBsAwAAAA==.',
Sh='Shampain:BAAANQAECgYIEQABNQAECgkJQAAEAOAbAA==.Shang:BAABNQAECoEnAAIGAAkKVyUQBQCnAwAGAAkKVyUQBQCnAwAAAA==.Shanzo:BAAANQAECggIAwAAAA==.Shirona:BAABNQAECoEZAAMDAAgKNBpnIQBpAgADAAgKNBpnIQBpAgATAAcKIwvKMwB+AQAAAA==.Shloomish:BAAANQADCgEIAQAAAA==.Shãde:BAAANQADCgIIAgAAAA==.Shïnwolford:BAABNQAECoEhAAIUAAkKoBphRgDoAgAUAAkKoBphRgDoAgABNQAECgkJLwADANoiAA==.',
Si='Siare:BAAANQAECgYICwAAAA==.',
Sk='Skeeter:BAABNQAECoEdAAQfAAcKsB7XEwDJAQAfAAYKCBrXEwDJAQABAAQKyx6XoABlAQAeAAEKCRJzKQA7AAAAAA==.Skroncer:BAAANQADCgYIDwAAAA==.',
Sm='Smokinjawn:BAAANQADCgMIAwAAAA==.Smòtts:BAABNQAECoEfAAINAAcKaR44DQBTAgANAAcKaR44DQBTAgAAAA==.Smótts:BAAANQADCggJEwAAAA==.',
Sn='Sneekee:BAAANQAECgIIBAABNQAECgQIBAAHAAAAAA==.Snizard:BAAANQAECgUIEAAAAA==.Snuggiepoo:BAAANQADCgIIAgABNQAECgYICwAHAAAAAA==.',
So='Soawesome:BAAANQAECgQIBAABNQAECgQIDQAHAAAAAA==.Solenoid:BAAANQAECgQIBAAAAA==.',
Sp='Spicymustard:BAAANQADCgYICgAAAA==.Spàdes:BAAANQAECgIJAgAAAA==.',
Sq='Squírtlé:BAAANQADCgEIAQAAAA==.',
St='Stellanoova:BAAANQAECgUICQABNQAECggIGQAZALIPAA==.Stormbeards:BAAANQADCgcIBwAAAA==.Stuwu:BAAANQABCgQIBAAAAA==.',
Su='Sugarcube:BAAANQAECgUIBQABNQAFFAMICAANAAENAA==.Sugarhigh:BAAANQABCgQIBAAAAA==.Sunlight:BAAANQADCggICQAAAA==.Sushirollz:BAAANQAECgIIAgAAAA==.',
Ta='Taazdingo:BAAANQADCgYJCwAAAA==.Takin:BAAANQADCggICAAAAA==.Taxxwomann:BAABNQAECoEnAAMBAAkK+yIeMgCmAgABAAcKvSIeMgCmAgAfAAMKyR3CLgAEAQAAAA==.',
Th='Thisishard:BAABNQAECoEjAAIUAAkKvBKXjwBFAgAUAAkKvBKXjwBFAgAAAA==.Thryen:BAAANQAECgQICQAAAA==.Thundergrasp:BAABNQAECoEYAAIWAAkKgRuaJQDOAgAWAAkKgRuaJQDOAgAAAA==.',
To='Toe:BAAANQAECgQIBAAAAA==.Toobestake:BAAANQABCgUIBQABNQAFFAYIFQAPAHoYAA==.Topenga:BAABNQAECoEwAAICAAkKkR1EHAANAwACAAkKkR1EHAANAwAAAA==.',
Tr='Trunnks:BAAANQAECgEIAQAAAA==.',
Ts='Tsargock:BAAANQADCgUIBAAAAA==.',
Tu='Tuoldforthis:BAAANQADCgIJAgAAAA==.',
Tw='Twicelife:BAAANQAECgUICQABNQAECgkJXQASAPEbAA==.',
Ty='Typhoid:BAAANQAECgQIBAAAAA==.',
['Tñ']='Tñt:BAAANQAECgQIBAABNQAECgkJKgABAH8gAA==.',
Ur='Urbek:BAAANQAECgYIEwAAAA==.Urthstripe:BAABNQAECoEXAAIFAAgKnhRtHgARAgAFAAgKnhRtHgARAgAAAA==.',
Uw='Uwu:BAAANQADCgYIDgABNQAFFAYIFQAYAJUVAA==.',
Va='Valle:BAAANQADCgcICwABNQAFFAYIFQAYAJUVAA==.Valoria:BAAANQADCgYIBwABNQAFFAYIFQAYAJUVAA==.',
Ve='Velgabrine:BAAANQAECgQICAABNQAECgkJPAALAFcmAA==.Veraani:BAAANQADCggICAAAAA==.Verlaria:BAAANQADCgEIAQAAAA==.',
Vi='Viserion:BAABNQAECoEZAAMZAAgKsg8dCwCJAQAZAAcKBxEdCwCJAQAcAAUKkAqNLwD8AAAAAA==.',
Vu='Vue:BAABNQAECoFAAAIEAAkK4BtZGwDzAgAEAAkK4BtZGwDzAgAAAA==.Vulkun:BAAANQADCgYIBgAAAA==.',
Wa='Wakasham:BAABNQAECoEjAAIgAAkKpCY4AAD8AwAgAAkKpCY4AAD8AwAAAA==.Warwick:BAAANQABCgIIAgAAAA==.',
We='Wehonoryou:BAABNQAECoEWAAMDAAgKHCHyEAD/AgADAAgKHCHyEAD/AgATAAIKUgjrVwBdAAABNQAFFAcIFgATAEgfAA==.',
Wo='Wolfpacked:BAABNQAECoEbAAIRAAYKFhkeZgCrAQARAAYKFhkeZgCrAQABNQAECgkJIAABAC4hAA==.',
Wr='Wrbringer:BAAANQADCgEIAQAAAA==.',
Wu='Wunderlust:BAABNQAECoErAAIUAAkKnRv4TwDRAgAUAAkKnRv4TwDRAgAAAA==.',
Ye='Yellowshaman:BAACNQAFFIEJAAIWAAMKVA4TFgDmAAAWAAMKVA4TFgDmAAA1AAQKgSUAAhYACQqeHYgeAPgCABYACQqeHYgeAPgCAAAA.',
Za='Zandelussy:BAAANQAECgYICwAAAA==.',
Zu='Zugg:BAAANQAECgYIBgABNQAFFAYIFQAYAJUVAA==.Zuriznikov:BAAANQAECgQIDgABNQAECggIGQAZALIPAA==.',
['Øf']='Øffspeck:BAABNQAECoEqAAQBAAkKfyCXIwDdAgABAAgKCCCXIwDdAgAeAAcK+BscBgAwAgAfAAMKoCCmKgAcAQAAAA==.',
['ßo']='ßoss:BAAANQADCgQIBAABNQAECgcIGwASADIhAA==.',
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
