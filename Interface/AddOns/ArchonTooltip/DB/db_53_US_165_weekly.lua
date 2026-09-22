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

local lookup = {'Druid-Guardian','Hunter-BeastMastery','Shaman-Elemental','Druid-Restoration','Unknown-Unknown','Mage-Arcane','Druid-Balance','DeathKnight-Frost','Warrior-Arms','DemonHunter-Devourer','Paladin-Holy','Paladin-Retribution','Rogue-Outlaw','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Discipline','Priest-Shadow','Priest-Holy','Warrior-Protection','Paladin-Protection','DeathKnight-Blood','DeathKnight-Unholy','Mage-Frost','Evoker-Preservation','Mage-Fire','Hunter-Survival','Rogue-Subtlety',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Accoli:BAAANQAECgUIBQAAAA==.Acslater:BAAANQADCgQJBAAAAA==.',
Ag='Agoobagoo:BAAANQAECgcIBgABNQAECggIHQABAN8fAA==.',
Al='Aliasx:BAAANQADCgUICQAAAA==.Allarus:BAAANQADCgcICQAAAA==.Alotofsin:BAAANQAECgEIAQAAAA==.Alphadog:BAABNQAECoEaAAICAAgKDBn2PABCAgACAAgKDBn2PABCAgAAAA==.Alwaysunny:BAAANQADCgYIDAAAAA==.',
Am='Amahlfarouk:BAAANQAECgIIAgAAAA==.Aminatou:BAAANQAECgUJCwAAAA==.',
Ar='Ariaddne:BAAANQAECgYJDgAAAA==.Artemîs:BAAANQADCgUICgAAAA==.',
As='Ashaelra:BAAANQAECgUIBQAAAA==.Asolitha:BAAANQADCgUIBQAAAA==.',
Au='Augonly:BAAANQAFFAEIAQAAAA==.Augy:BAAANQAECgYJEgAAAA==.',
Ba='Barhead:BAAANQADCgQIBwAAAA==.',
Bb='Bbldrizzy:BAABNQAECoEiAAIDAAkKbCTFBgCVAwADAAkKbCTFBgCVAwAAAA==.',
Be='Beastlieduke:BAAANQADCgYIDAABNQAECggJGwAEAGUdAA==.Beastlièduke:BAAANQADCgIIAgABNQAECggJGwAEAGUdAA==.Belinda:BAAANQADCggJCgAAAA==.',
Bi='Bighunt:BAAANQAECgMJAwAAAA==.Bijju:BAAANQAECggJDAAAAA==.Binggus:BAAANQAECgcJEQAAAA==.',
Bl='Blabbybootze:BAAANQAECgQJBAAAAA==.Bladelight:BAAANQADCgcJDAAAAA==.Blightfangs:BAAANQAECgEIAQAAAA==.',
Bo='Bodakye:BAAANQAECgQIBwAAAA==.Boneplague:BAAANQADCgQIBAAAAA==.Boow:BAAANQADCgcIGQAAAA==.',
Br='Bracalina:BAAANQADCgcICQAAAA==.Broggy:BAAANQADCgEIAQABNQAECgEIAQAFAAAAAA==.Brorgy:BAAANQAECgUJDgAAAA==.Brovahkin:BAAANQABCgUJCAAAAA==.',
Bu='Bubbapal:BAAANQADCgUIBwAAAA==.Buzzbuzz:BAAANQAECgMIBAAAAA==.',
By='Bywar:BAAANQADCgUJBQAAAA==.',
Ca='Caeruleus:BAAANQADCgQJBAAAAA==.Captyn:BAAANQABCgQIAwAAAA==.Catbum:BAAANQADCgIIAwAAAA==.Caylea:BAAANQADCggICAAAAA==.',
Ch='Chaosraven:BAAANQAECgYJDwAAAA==.Chapelgnome:BAAANQADCgUJBQABNQAECgUJDgAFAAAAAA==.Charlyne:BAAANQABCgMIAwAAAA==.Chewthymight:BAAANQAECgUJCwAAAA==.Chickenslop:BAAANQADCggIFQAAAA==.Chiptime:BAAANQAECgQICwAAAA==.Chri:BAAANQAECgQIBAAAAA==.Chzburger:BAAANQABCgIIBAAAAA==.',
Cl='Cladon:BAAANQAECggJCAAAAA==.Clairity:BAAANQADCgcIBwAAAA==.',
Co='Cocoon:BAAANQAECgQIBAABNQAECgkJGwAGAIYgAA==.Cormogh:BAAANQADCggJCwAAAA==.Cowhealer:BAABNQAECoEhAAMHAAkKUx2OEQD+AgAHAAkKUx2OEQD+AgAEAAMKGAotOQCrAAAAAA==.',
Cr='Craeftig:BAAANQAECgQJBQAAAA==.Craeftigdk:BAAANQAECgMJBQABNQAECgQJBQAFAAAAAA==.Craeftigtwo:BAAANQADCggJDQABNQAECgQJBQAFAAAAAA==.Craeftigwl:BAAANQADCggICAABNQAECgQJBQAFAAAAAA==.Crepitus:BAAANQAECgQJCwAAAA==.Crusabull:BAAANQADCgUIBQAAAA==.Cræftig:BAAANQAECgEIAQABNQAECgQJBQAFAAAAAA==.',
Cu='Cuddlseraph:BAAANQAECgQICQAAAA==.',
Cy='Cynnithice:BAAANQADCgIIAgABNQADCgcICQAFAAAAAA==.',
Da='Dafirenze:BAAANQADCggIDwAAAA==.Daftxshade:BAAANQADCgcICAAAAA==.Darkbeef:BAAANQAECgUICwAAAA==.Darthsyde:BAAANQABCgQIBAAAAA==.',
De='Deadergriff:BAAANQAECgUJCQAAAA==.Deadicated:BAAANQAECgQJBQAAAA==.Deadinsíde:BAAANQAECggICAAAAA==.Deeznutzs:BAAANQADCgQJBQAAAA==.Delan:BAAANQAECgYIBwAAAA==.Demolishonn:BAAANQAECgEIAQAAAA==.Desunaito:BAABNQAECoEnAAIIAAkKOCPwAwB9AwAIAAkKOCPwAwB9AwAAAA==.Dexter:BAAANQAECgQIBQAAAA==.',
Dh='Dhzilong:BAAANQAECggJBwABNQAFFAUJCgAJAB0aAA==.',
Di='Diddlefiddle:BAAANQADCgIIAgAAAA==.Dioji:BAAANQAECggIBgAAAA==.',
Dm='Dmeo:BAAANQADCgMIAwAAAA==.',
Do='Docadoodle:BAAANQADCgcIBwABNQAECggIHwAKAMoYAA==.Docarcanis:BAAANQADCgcJBwABNQAECggIHwAKAMoYAA==.Docwyle:BAABNQAECoEfAAIKAAgKyhjeFQBrAgAKAAgKyhjeFQBrAgAAAA==.Doozey:BAAANQABCgcJBwAAAA==.',
Dr='Dracmary:BAAANQADCgUIBQAAAA==.Dracnogard:BAAANQADCgYIEQAAAA==.Dracowulf:BAAANQAECgUJBwAAAA==.Dragonx:BAAANQAECgQICwAAAA==.Drakowolf:BAAANQAECgEIAQAAAA==.Dreadful:BAABNQAECoEcAAILAAgKjxTWOAAVAgALAAgKjxTWOAAVAgAAAA==.Dreorge:BAAANQAECggIDgAAAA==.Drewceratops:BAAANQAECgYJEQAAAA==.Drimchi:BAAANQAECgEIAQAAAA==.Drimveil:BAAANQAECgcJCwAAAA==.Drogô:BAAANQADCgYJDwAAAA==.Dromgar:BAAANQAECggIBAAAAA==.Dromkyr:BAAANQAECgYJDwAAAA==.Drossiechan:BAAANQAECggJEwAAAA==.',
Du='Duellipa:BAAANQAECgQICQABNQAECgUJDgAFAAAAAA==.',
Dy='Dysian:BAAANQADCgQIBQAAAA==.Dywanw:BAAANQABCgYIBgAAAA==.',
Ed='Edward:BAAANQAECggJBwAAAA==.',
Ef='Effloria:BAAANQAECgYJDgAAAA==.',
Ek='Ekim:BAAANQADCgQIAwAAAA==.',
El='Elauvia:BAAANQAECgMIAwAAAA==.Elegia:BAAANQAECggIDgAAAA==.',
En='Enash:BAAANQADCgQIBAAAAA==.Encoredh:BAAANQAECgQJBAAAAA==.Encoredk:BAAANQADCgIIAgAAAA==.Encoree:BAAANQADCgcIBwAAAA==.Encorep:BAAANQAECgQICAAAAA==.Enris:BAAANQADCgUICAAAAA==.',
Ev='Eviscerated:BAAANQAECgQIBAAAAA==.',
Fa='Fail:BAAANQADCgYICwAAAA==.Falker:BAAANQADCgYIBgAAAA==.Fallen:BAAANQAECgQIBgAAAA==.Fallingvoid:BAAANQAFFAIIAgAAAA==.Fancyfeet:BAAANQADCgIIAwABNQAECgYIBgAFAAAAAA==.Fatchungus:BAAANQAECgQIBQABNQAECgYIBgAFAAAAAA==.Fateesia:BAAANQAECgEIAQAAAA==.',
Fi='Finaliter:BAABNQAECoEcAAIMAAgKSRpSPgBZAgAMAAgKSRpSPgBZAgAAAA==.',
Fl='Flamingdrago:BAAANQADCgYJDQAAAA==.Flirtyflurry:BAAANQAECgQIBgAAAA==.',
Fo='Fox:BAABNQAECoEoAAMNAAkKzCIMAQBvAwANAAkKdCIMAQBvAwAOAAQKiBkKNAA5AQAAAA==.',
Fr='Fremder:BAAANQAECgUJBgAAAA==.Froggy:BAABNQAECoERAAIKAAkKzAUJKgCYAQAKAAkKzAUJKgCYAQAAAA==.Frogred:BAAANQADCgQIBAABNQAECgkJEQAKAMwFAA==.',
Fu='Funeral:BAACNQAFFIERAAMPAAYK8BYjAQAaAQAQAAQKShGsBwBDAQAPAAMKHBsjAQAaAQA1AAQKgSAABA8ACQrnJcwAAJkDAA8ACQrpJMwAAJkDABAABgrmJIouAGYCABEAAQrPDK4jADIAAAAA.Furiousmoon:BAAANQADCggICAAAAA==.Futuresailor:BAAANQADCgEIAQAAAA==.',
Fy='Fyjhrt:BAAANQAECgcJDQAAAA==.',
Ga='Gallory:BAAANQAECggIBgAAAA==.Gayanall:BAAANQADCgMIAwAAAA==.',
Gd='Gdk:BAAANQAECgEJAQABNQAECgYJEQAFAAAAAA==.Gdkmage:BAAANQAECgUJBgABNQAECgYJEQAFAAAAAA==.Gdkman:BAAANQAECgYJEQAAAA==.Gdknotlock:BAAANQADCgQIBgABNQAECgYJEQAFAAAAAA==.',
Ge='Geoprince:BAAANQADCgYIDAAAAA==.Gerbon:BAAANQADCgMICAAAAA==.',
Gh='Ghaldrin:BAAANQABCggIEAAAAA==.Ghoulfriend:BAAANQADCgUIBgAAAA==.',
Gi='Gigitty:BAAANQADCgYIBgAAAA==.Gimmedatneck:BAAANQAECgYIDAABNQAECgkJIgADAGwkAA==.Githrogathan:BAAANQAECgUJCQAAAA==.',
Go='Gokudin:BAAANQADCgIIAgABNQADCgIIAgAFAAAAAA==.Goldenrager:BAAANQADCgQIBAAAAA==.Gooseandmav:BAAANQADCgEIAQAAAA==.',
Gr='Grabetta:BAAANQADCgEIAQAAAA==.Gragasfat:BAAANQAECgEJAQAAAA==.Groundnpound:BAAANQADCgUJBQAAAA==.',
['Gâ']='Gârrosh:BAAANQADCgYIBgABNQAECggJHAACAIwKAA==.',
Ha='Haeha:BAAANQADCgQIBAAAAA==.Haraldsson:BAAANQADCggICAAAAA==.Hargrumn:BAAANQABCgMIAgAAAA==.Harrypooc:BAAANQADCgQJBAAAAA==.Hasaro:BAABNQAECoEdAAIBAAkKcQufDwCSAQABAAkKcQufDwCSAQAAAA==.Hatcho:BAAANQADCgUICAAAAA==.Havokvacano:BAAANQAECgIJBAAAAA==.Havøckblaze:BAAANQADCgIIAgAAAA==.',
He='Healmachine:BAAANQADCggIHAAAAA==.Hellbrringer:BAAANQAECgEIAQAAAA==.Helzer:BAAANQADCgcIBwABNQAECgcJEQAFAAAAAA==.',
Ho='Holybaphomet:BAAANQADCgUICQAAAA==.Holyfarts:BAABNQAECoEeAAQSAAkK4x5gAQACAwASAAkK7BtgAQACAwATAAgKSxWAFQBKAgAUAAYKqBzNOQAFAgAAAA==.Hornedraven:BAAANQADCgEIAQAAAA==.',
Hu='Humanform:BAAANQADCgUJBQAAAA==.Hunbroll:BAAANQADCgYIBgABNQAFFAMJBgAGAGwNAA==.Hungshaman:BAAANQABCgIIAgAAAA==.Hunterkiller:BAAANQADCgYIEgAAAA==.',
Hx='Hx:BAAANQADCgYJDwAAAA==.',
Hy='Hypnoticpal:BAAANQAECggIDAAAAA==.',
['Hõ']='Hõnor:BAABNQAECoEgAAMJAAkKTSEkGAAnAwAJAAkKGSAkGAAnAwAVAAUKRiDXDADSAQABNQAECggIFgAIAA4jAA==.',
Ig='Igriss:BAAANQAECgYIDgAAAA==.',
Il='Illidanx:BAAANQADCgQIBAAAAA==.Ilumii:BAAANQAECgMIAwAAAA==.',
Im='Imonthegcd:BAAANQAECgYIBgABNQAECggIFgAIAA4jAA==.',
In='Infinitepain:BAABNQAECoEbAAIUAAgK/SFhEQD0AgAUAAgK/SFhEQD0AgAAAA==.Innodk:BAAANQAECgEJAQAAAA==.',
Ir='Iridellis:BAAANQADCgcIBwABNQAECggIHAALAI8UAA==.',
Is='Ispankutank:BAAANQADCgEIAQAAAA==.',
Ja='Jahjahblinks:BAAANQADCgYIFAABNQAECggJHAACAIwKAA==.Jave:BAAANQABCgQIBQAAAA==.Jaycers:BAABNQAECoEVAAIWAAgKGB33CQCQAgAWAAgKGB33CQCQAgAAAA==.Jayclark:BAAANQADCgEIAQAAAA==.',
Ji='Jimmypal:BAAANQAECgIJAwAAAA==.',
Jo='Joedingle:BAAANQAECgQJCAAAAA==.Joemomma:BAAANQADCgUJBQAAAA==.Johnnyboi:BAAANQADCgEIAQAAAA==.Jokestarfist:BAAANQAECgYIDgAAAA==.',
Jr='Jr:BAAANQADCggICAAAAA==.',
Ka='Kaelar:BAAANQADCgMIAwABNQAECggIFQAIAPccAA==.Kaitokit:BAABNQAECoEnAAMXAAkKYBjXLgDtAQAXAAYKexvXLgDtAQAYAAcK4g8zOADAAQAAAA==.Kalia:BAAANQADCgIIAgAAAA==.Kalyth:BAAANQAECgYICwAAAA==.Kamera:BAAANQAECgcJEQAAAA==.Kandessa:BAAANQADCgIJAwAAAA==.Kaylah:BAAANQAECgUIDgAAAA==.Kayllina:BAAANQAECgUICAAAAA==.Kayotic:BAAANQAECgIIAgAAAA==.',
Ke='Kelmorphic:BAAANQAECgYJDgAAAA==.',
Ki='Killcommand:BAAANQADCggICAABNQAECgkJGwAGAIYgAA==.',
Ko='Kosmas:BAAANQAECgEJAQAAAA==.',
Kr='Krombear:BAAANQADCgIIAgAAAA==.',
Ku='Kudai:BAAANQAECgQIBgAAAA==.Kungpowchikn:BAAANQADCgIIAgAAAA==.Kurookami:BAAANQADCgEIAQAAAA==.Kuukwa:BAAANQAECgQIBQAAAA==.',
Ky='Kyarina:BAAANQABCggIDwAAAA==.',
['Kí']='Kíller:BAAANQAECgEIAQAAAA==.',
La='Lamadda:BAAANQADCgUIBQAAAA==.',
Ld='Ldg:BAAANQADCgQIBAAAAA==.',
Le='Letusgiveita:BAAANQADCgQJBAAAAA==.',
Li='Lightingbolt:BAAANQADCgUICwAAAA==.Lightshields:BAAANQADCgIIAgAAAA==.Lilymei:BAAANQADCgcICAAAAA==.Linissa:BAAANQAECgQIBgAAAA==.Littledude:BAAANQADCgYIBgAAAA==.Littlemorsel:BAAANQAECgYJDwAAAA==.Livalifa:BAAANQAECgEIAQAAAA==.',
Lo='Lockenload:BAAANQAECgUIDAAAAA==.Lohhar:BAAANQADCggIDgAAAA==.Loser:BAAANQABCgQIBQAAAA==.',
Ls='Lselec:BAAANQAECgMJBQAAAA==.',
Lu='Lucens:BAAANQAECgYJCwAAAA==.Lurchdh:BAEANQADCgQJBAABNQAECgkJMgAZAFUSAA==.Lurchdruid:BAEANQAECgIIAQABNQAECgkJMgAZAFUSAA==.Lurchmage:BAEANQAECggIEQABNQAECgkJMgAZAFUSAA==.Lurchn:BAEBNQAECoEyAAMZAAkKVRLmBABRAgAZAAkKOhLmBABRAgAGAAgKrQWYxQB2AQAAAA==.',
Ly='Lyricai:BAAANQAECgQIBgAAAA==.',
Ma='Madjake:BAAANQADCggICAAAAA==.Maemae:BAAANQADCgYJCwAAAA==.Magallanes:BAAANQABCgIIAgAAAA==.Markyy:BAAANQAECggIEQABNQAECggIFgAIAA4jAA==.Matas:BAAANQAECgMJBAAAAA==.Maylinfenora:BAAANQAECgUJCgAAAA==.Mazzikane:BAAANQADCgYIBgAAAA==.',
Me='Meowizenith:BAAANQADCgUIBQAAAA==.Merdazin:BAAANQAECgQIDAAAAA==.Metalhedface:BAAANQAECgcIEgAAAA==.',
Mi='Mikecoxwall:BAAANQADCgEIAQAAAA==.Misary:BAAANQAECgIIAgAAAA==.Mistake:BAAANQAECgUJCAAAAA==.',
Mo='Mogyar:BAABNQAECoEaAAIMAAcKfxacXgDjAQAMAAcKfxacXgDjAQAAAA==.Moistybush:BAAANQAECgEIAQAAAA==.Moltalgol:BAAANQAECgEIAgAAAA==.Monkeli:BAAANQAECgcIDwAAAA==.Moonsiand:BAAANQAECgYIDwABNQAECggIGgACAAwZAA==.Moreldwiddle:BAAANQAECgIJBAAAAA==.Morgaia:BAAANQADCggJHQAAAA==.Morrigån:BAAANQADCgMIAwAAAA==.Motgus:BAAANQAECgUIBQAAAA==.Mozzsticks:BAAANQADCgYICwAAAA==.',
Ms='Mshottie:BAAANQADCgcIBwAAAA==.',
Mx='Mx:BAAANQADCgYJCAAAAA==.',
My='Mystrialia:BAAANQABCgYIBgAAAA==.Mythlock:BAAANQADCgcIEwAAAA==.',
['Mó']='Mócha:BAAANQAECgQIBgAAAA==.',
Na='Nardrian:BAAANQAECgQIBQAAAA==.',
Ne='Nellaa:BAAANQAECgEIAQAAAA==.Nestaria:BAAANQADCggICAAAAA==.Netalanot:BAAANQADCgYIBgAAAA==.Neverborn:BAAANQAECgYJDQAAAA==.',
Ni='Nightrage:BAAANQADCggIGAAAAA==.',
No='Nomadic:BAAANQADCgIIAgAAAA==.Notmypally:BAAANQADCgQJBAABNQAECggJGwAGADcgAA==.',
Nu='Numera:BAAANQADCgEIAQAAAA==.Nutellaqq:BAAANQAECgYJEgAAAA==.',
Ob='Obeseotter:BAABNQAECoEiAAIGAAcK1ReUggARAgAGAAcK1ReUggARAgAAAA==.Oborax:BAAANQADCgYIBgABNQAECggIGgACAAwZAA==.',
Od='Od:BAAANQADCgUIDwAAAA==.',
Ol='Oliviabenson:BAAANQAECgUICQAAAA==.',
Ox='Oxsidius:BAAANQAECgEJAQAAAA==.',
Pa='Paldi:BAAANQAECgQIBAABNQAECgYIBgAFAAAAAA==.Paliboos:BAAANQADCgYIBgAAAA==.Palulu:BAEANQAECggIDwAAAA==.Pariss:BAAANQADCgUIBQABNQAECggJDgAFAAAAAA==.Paws:BAAANQAECgUJBgAAAA==.',
Pe='Peaky:BAAANQAECgQIDQAAAA==.Perelia:BAAANQAECgQJBgAAAA==.',
Pl='Plondor:BAAANQABCgEIAQAAAA==.',
Po='Polarity:BAAANQAECgMJAwAAAA==.Pooche:BAAANQAECgIIAwAAAA==.Popcola:BAAANQAECgQIBAAAAA==.',
Pp='Ppc:BAAANQAECgEJAQABNQAECgkJGwAGAIYgAA==.',
Pr='Prezu:BAEBNQAECoEVAAIaAAcKnA5VHgBvAQAaAAcKnA5VHgBvAQABNQAECggIDwAFAAAAAA==.Prophofdoom:BAAANQAECgYIDgAAAA==.Prõc:BAAANQADCggICAAAAA==.',
Pv='Pvc:BAABNQAECoEbAAMGAAkKhiBWJQAkAwAGAAkKhiBWJQAkAwAbAAEKmgCYCQApAAAAAA==.',
Ra='Raisedead:BAAANQADCgIIAgABNQADCggIDAAFAAAAAA==.Rancord:BAAANQADCggICAAAAA==.Ratsmasher:BAAANQAECgIIAgAAAA==.Razed:BAAANQADCgYICwAAAA==.',
Re='Retrobution:BAAANQAECgQICAAAAA==.Rezz:BAAANQAECgcIDAAAAA==.',
Rh='Rhohir:BAAANQABCgIIAgAAAA==.',
Ri='Riru:BAAANQAECgQIBwAAAA==.',
Ro='Roopall:BAAANQAECgcIDQAAAA==.',
Ry='Rynzu:BAAANQAECgMIBAAAAA==.Ryzen:BAAANQAECgYIBwAAAA==.',
Sa='Sabelwin:BAAANQADCgEIAQAAAA==.Sanasrindis:BAAANQADCgQIAgAAAA==.Saninar:BAAANQAECgQJCgAAAA==.Sanshift:BAAANQADCgYJBwAAAA==.Satansimp:BAAANQADCggILQAAAA==.',
Sc='Schadnfreude:BAABNQAECoEeAAMIAAkKNRSyFwBRAgAIAAkKNRSyFwBRAgAYAAEK1genlwAwAAAAAA==.Schezmu:BAAANQAECgQIBAAAAA==.',
Se='Sean:BAAANQADCgUICgAAAA==.Senorfiesta:BAAANQAECgUJCAAAAA==.Setazen:BAAANQADCgYIBgAAAA==.',
Sh='Shadowjoker:BAAANQAECgEIAQAAAA==.Shaee:BAAANQAECgQICAAAAA==.Shamans:BAAANQADCgYICwAAAA==.Shambalaya:BAAANQADCgEJAQAAAA==.Shaokhan:BAAANQADCgYIBgAAAA==.Shasta:BAABNQAECoEbAAIBAAkKGiW+AADGAwABAAkKGiW+AADGAwAAAA==.Shihthead:BAAANQADCgUIBQAAAA==.Shisuiuchiha:BAAANQADCgIIAgAAAA==.Shmorg:BAAANQADCgEIAQAAAA==.Shootumup:BAABNQAECoEhAAMcAAkKPyLkAABSAwAcAAkKPyLkAABSAwACAAEKZReU4wBSAAAAAA==.Shyx:BAAANQAECgQIBgAAAA==.',
Si='Simplèjack:BAAANQAECgcJDQAAAA==.Sinamon:BAAANQADCgYIBgAAAA==.Sinani:BAAANQADCgUJBQAAAA==.Sinnamon:BAAANQABCgQJBAABNQADCgYIBgAFAAAAAA==.',
Sj='Sjdh:BAAANQADCgYIBgABNQAECgYIEgAFAAAAAA==.',
Sk='Skar:BAAANQADCgUIBgAAAA==.Skronker:BAAANQADCggIDQAAAA==.',
Sl='Slammydooker:BAAANQAECgUJBwAAAA==.',
Sm='Smirksfotm:BAAANQAECgUICAABNQAECggICAAFAAAAAA==.Smoketail:BAAANQAECgIJAgAAAA==.',
Sn='Snail:BAAANQAECgYIBgAAAA==.Sneakmanman:BAAANQADCgYJCQAAAA==.',
So='Somberdh:BAAANQADCggICwAAAA==.Sorni:BAAANQAECgQICgAAAA==.Soulglo:BAAANQADCgcIDQAAAA==.',
Sp='Sprayandpray:BAAANQAECgMIBQAAAA==.Spritey:BAAANQABCgIIAgAAAA==.',
St='Stareless:BAAANQADCgYIBgAAAA==.Statik:BAAANQADCgIIAgAAAA==.Steveedudu:BAAANQADCggICAAAAA==.',
Su='Summondemons:BAAANQAECgIIBQAAAA==.Sunpali:BAAANQAECgQIBAAAAA==.Susanno:BAAANQADCgUJCwAAAA==.',
Sy='Sylauda:BAAANQADCgYICgAAAA==.Sylvians:BAAANQAECgEIAQAAAA==.',
Ta='Tacutacudark:BAAANQADCgYIFAAAAA==.Taintedbeef:BAAANQADCgEIAQABNQAECgUJBgAFAAAAAA==.Talonflame:BAAANQAECgcJEwAAAA==.Talonted:BAAANQADCggICwAAAA==.Tansu:BAAANQADCgYICAAAAA==.Taupo:BAAANQADCgcIEgAAAA==.Taxidermy:BAAANQADCgYIBgAAAA==.',
Te='Telarinda:BAAANQAECgIIAgAAAA==.',
Th='Thicclich:BAAANQAECgMJAwAAAA==.Thicktotem:BAAANQAECgEIAQAAAA==.Thickumz:BAAANQADCgQIBAAAAA==.Thisismeta:BAAANQAECgUICQAAAA==.Thorynwar:BAABNQAECoEYAAIJAAkKeCC+EwBCAwAJAAkKeCC+EwBCAwABNQAECgkJJAAYAEwmAA==.Thorýn:BAABNQAECoEkAAMYAAkKTCb+AQDSAwAYAAkKTCb+AQDSAwAXAAcKKxqeKQAOAgAAAA==.Thórin:BAAANQAECgYICgAAAA==.',
Ti='Tierax:BAABNQAECoEZAAMdAAgKzSDtBQAHAwAdAAgKzSDtBQAHAwAOAAEKkxOKXQA+AAAAAA==.Tipsy:BAAANQAECgYJDwAAAA==.',
To='Tojì:BAAANQAECggICAABNQAECggICAAFAAAAAA==.Tomfoolary:BAAANQADCgQJBAAAAA==.Tonathul:BAAANQADCggIEAAAAA==.Torrk:BAAANQADCgUICwAAAA==.Torultrear:BAAANQAECgIJAgAAAA==.Tot:BAAANQAECgYJEAAAAA==.',
Tr='Tralleth:BAAANQAECgQIBwAAAA==.Trallock:BAAANQADCggJCAAAAA==.Traumatized:BAAANQADCgIIAgAAAA==.Truska:BAAANQABCgEIAQAAAA==.',
Tw='Twinklord:BAAANQAECgQIBwAAAA==.Twostroke:BAAANQAECgcJCwAAAA==.Twretwtwrewr:BAAANQADCgIJAgAAAA==.',
Ty='Tylopally:BAAANQAECgQICwAAAA==.Tyloremixdd:BAAANQADCgYIBwAAAA==.Tylototem:BAAANQAECgQIBAAAAA==.',
['Tö']='Tötem:BAAANQADCgMIAwABNQAECggIFgAIAA4jAA==.',
Uj='Ujcpet:BAAANQADCgYIBgAAAA==.',
Un='Uncookedham:BAAANQADCgYIEAAAAA==.Underhorn:BAAANQADCgYIBgAAAA==.',
Va='Vaas:BAAANQADCggICAABNQAECggJFQAWABgdAA==.Vaeelrundor:BAAANQAECgQIDQAAAA==.Valyr:BAAANQADCgQJBAAAAA==.Vampslayer:BAAANQADCgYIBgAAAA==.Vanillaface:BAAANQADCgYIBwAAAA==.Vañillaface:BAAANQABCgQIBgAAAA==.',
Ve='Vedebone:BAAANQAECgUIBwAAAA==.Vedexd:BAABNQAECoEdAAICAAcKbg6cZQC9AQACAAcKbg6cZQC9AQAAAA==.Velarael:BAAANQAECgQJBQAAAA==.Velexi:BAAANQADCgQIBwAAAA==.',
Vl='Vlidya:BAAANQADCgEIAQAAAA==.',
Vo='Voidberg:BAAANQADCggJDgAAAA==.',
Vs='Vs:BAAANQAECggIDgAAAA==.',
Wa='Wachonaso:BAABNQAECoEbAAIQAAkKYxyaGwDCAgAQAAkKYxyaGwDCAgAAAA==.Wastedsage:BAAANQAECgIIAwAAAA==.Waterlou:BAAANQADCgIJAgAAAA==.',
Wh='Whatuphuz:BAAANQADCgQICQAAAA==.Wheresmyjaw:BAABNQAECoEZAAMQAAgK2xbHXACzAQAQAAYK4hfHXACzAQAPAAMKzw4TOgC1AAAAAA==.',
Wi='Wildthree:BAAANQAECgUJBwAAAA==.Wilkieswar:BAAANQADCggIEAABNQAECgYIEgAFAAAAAA==.Willenda:BAAANQADCgcIDgAAAA==.',
Wu='Wuinn:BAACNQAFFIEGAAIaAAQKhgmBBwAxAQAaAAQKhgmBBwAxAQA1AAQKgRgAAhoACQpPFOkNAHwCABoACQpPFOkNAHwCAAAA.',
Xa='Xakutioner:BAAANQAECgYJEAAAAA==.Xaldiir:BAAANQAECgUIBgAAAA==.',
Xe='Xerexia:BAABNQAECoEcAAIJAAgK7wvTbQDDAQAJAAgK7wvTbQDDAQAAAA==.',
Xw='Xwoo:BAAANQAECgIIAgAAAA==.',
Ya='Yahro:BAAANQAECgcIEQAAAA==.',
Ye='Yellowranger:BAAANQAECgYJEQAAAA==.',
Yj='Yjn:BAAANQAECgEJAQAAAA==.',
Yo='Yongyong:BAAANQAECgMJBQAAAA==.Yotoymuerto:BAAANQAECgEIAQAAAA==.',
Yu='Yunara:BAAANQAECgYIBgAAAA==.Yustayoke:BAAANQAECgYIDQAAAA==.',
Za='Zalvianna:BAAANQADCggJJAAAAA==.Zarathoz:BAAANQABCgYJBgAAAA==.Zarshx:BAAANQADCgQICAABNQAECgYIBgAFAAAAAA==.',
Ze='Zennithz:BAAANQAECggICAAAAA==.Zeonz:BAAANQAECgEIAQAAAA==.',
Zi='Zilongmage:BAAANQAECgUJBQABNQAFFAUJCgAJAB0aAA==.Zilongwar:BAACNQAFFIEKAAIJAAUKHRoiBgC8AQAJAAUKHRoiBgC8AQA1AAQKgRsAAgkACQqqIj8SAEwDAAkACQqqIj8SAEwDAAAA.',
Zo='Zonecw:BAAANQAECgUJBQAAAA==.Zonedk:BAAANQAECgQIBgABNQAECgUJBQAFAAAAAA==.',
['Ør']='Ørsted:BAAANQADCgIIAgABNQADCgcIEgAFAAAAAA==.',
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
