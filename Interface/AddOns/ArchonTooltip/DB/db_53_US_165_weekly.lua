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

local lookup = {'Hunter-BeastMastery','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','Unknown-Unknown','DeathKnight-Frost','Mage-Arcane','Druid-Balance','Warrior-Arms','DemonHunter-Devourer','Paladin-Holy','Evoker-Preservation','Monk-Windwalker','Paladin-Retribution','Rogue-Assassination','Rogue-Outlaw','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Rogue-Subtlety','Druid-Guardian','Priest-Discipline','Priest-Holy','Priest-Shadow','Mage-Frost','Warrior-Protection','Paladin-Protection','Druid-Feral','DeathKnight-Blood','DeathKnight-Unholy','DemonHunter-Vengeance','Monk-Brewmaster','Warrior-Fury','Monk-Mistweaver','Mage-Fire','Hunter-Survival','Hunter-Marksmanship',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Accoli:BAAANQAECgUIBQAAAA==.Acslater:BAAANQADCgQIBAAAAA==.',
Ag='Agoobagoo:BAAANQAFFAEIAQAAAA==.',
Al='Aliasx:BAAANQADCgUICQAAAA==.Allarus:BAAANQADCgcICQAAAA==.Alotofsin:BAAANQAECgEIAQAAAA==.Alphadog:BAABNQAECoEgAAIBAAgKex1/JwC/AgABAAgKex1/JwC/AgAAAA==.Alwaysunny:BAAANQADCgYIDAAAAA==.',
Am='Amahlfarouk:BAAANQAECgQIBgAAAA==.Aminatou:BAAANQAECgYIEQAAAA==.',
Ar='Ariaddne:BAABNQAECoEYAAQCAAcK2RZCEgDzAQACAAcK5xRCEgDzAQADAAUKqRKeiwAvAQAEAAEKwRhp4wBDAAAAAA==.Artemîs:BAAANQAECgEIAQAAAA==.',
As='Ashaelra:BAAANQAECgUIBQAAAA==.Asolitha:BAAANQADCgUIBQAAAA==.',
Au='Augonly:BAAANQAFFAMIBAAAAA==.Augy:BAABNQAECoEbAAMFAAcKXB5XBwDgAQAGAAcKJRukEAAPAgAFAAYKkRpXBwDgAQAAAA==.',
Az='Azalea:BAAANQAECgYICAAAAA==.',
Ba='Barhead:BAAANQADCggIDgAAAA==.',
Bb='Bbldrizzy:BAACNQAFFIEHAAIDAAQKvhzACQBfAQADAAQKvhzACQBfAQA1AAQKgSYAAgMACQrgJEcJAIoDAAMACQrgJEcJAIoDAAAA.',
Be='Beastlieduke:BAAANQADCgYIDAABNQAECggIHQAHAGUdAA==.Beastlièduke:BAAANQADCgIIAgABNQAECggIHQAHAGUdAA==.Belephon:BAAANQADCgIIAgAAAA==.Belinda:BAAANQADCggIEAAAAA==.',
Bi='Bighunt:BAAANQAECgMIAwAAAA==.Bijju:BAAANQAECggIDAAAAA==.Binggus:BAAANQAECgcJEQAAAA==.',
Bl='Blabbybootze:BAAANQAECgYICgAAAA==.Bladelight:BAAANQADCgcJDAAAAA==.Blightfangs:BAAANQAECgQIBAAAAA==.Bluzey:BAAANQADCgYIBgAAAA==.',
Bo='Bodakye:BAAANQAECgQIBwAAAA==.Boneplague:BAAANQADCgQIBAAAAA==.Boow:BAAANQAECgUIBQAAAA==.',
Br='Bracalina:BAAANQAECgEIAQAAAA==.Broggy:BAAANQADCgEIAQABNQAECgEIAQAIAAAAAA==.Brorgy:BAAANQAECgUIEgAAAA==.Brovahkin:BAAANQABCggIEAAAAA==.',
Bu='Bubbapal:BAAANQADCgUIBwAAAA==.Buzzbuzz:BAAANQAECgMIBAAAAA==.',
By='Bywar:BAAANQADCgcICAAAAA==.',
['Bé']='Bébop:BAAANQAECggICAAAAA==.',
Ca='Caeruleus:BAAANQADCgQJBAAAAA==.Captyn:BAAANQABCgQIAwAAAA==.Catbum:BAAANQADCgIIAwAAAA==.Caylea:BAAANQADCggICAAAAA==.',
Ch='Chaosraven:BAABNQAECoEaAAIJAAgKcwzFMgCpAQAJAAgKcwzFMgCpAQAAAA==.Chapelgnome:BAAANQADCgUJBQABNQAECgUIEgAIAAAAAA==.Charlyne:BAAANQABCgMIAwAAAA==.Chewthymight:BAAANQAECgYIEgAAAA==.Chickenslop:BAAANQADCggIFgAAAA==.Chiptime:BAAANQAECgQICwAAAA==.Chri:BAAANQAECgQIBAAAAA==.Chungotron:BAAANQAFFAIIAgAAAA==.Chzburger:BAAANQABCgIIBAAAAA==.',
Cl='Cladon:BAAANQAECggICAAAAA==.Clairity:BAAANQADCgcIBwAAAA==.',
Co='Cocoon:BAAANQAECgQIBAABNQAFFAMIBQAKAKcTAA==.Cormogh:BAAANQADCggJCwAAAA==.Cowhealer:BAABNQAECoEjAAMLAAkKnB15FgDpAgALAAkKnB15FgDpAgAHAAMKGAppRACmAAAAAA==.',
Cr='Craeftig:BAAANQAECgQICAABNQAECgYICwAIAAAAAA==.Craeftigdk:BAAANQAECgYICwAAAA==.Craeftigtwo:BAAANQADCggJDQABNQAECgYICwAIAAAAAA==.Craeftigwl:BAAANQADCggICAABNQAECgYICwAIAAAAAA==.Crepitus:BAAANQAECgUIEQAAAA==.Crusabull:BAAANQADCgUIBQAAAA==.Cræftig:BAAANQAECgYIBgABNQAECgYICwAIAAAAAA==.',
Cu='Cuddlseraph:BAAANQAECgQIDQAAAA==.',
Cy='Cynnithice:BAAANQADCgIIAgABNQAECgEIAQAIAAAAAA==.',
Da='Daamdam:BAAANQAECggICAAAAA==.Dafirenze:BAAANQADCggIDwAAAA==.Daftxshade:BAAANQADCgcICAAAAA==.Dariian:BAAANQAECggIBgAAAA==.Darkbeef:BAAANQAECgYIDwAAAA==.Darkjusticeh:BAAANQAECgIIAgAAAA==.Darthbjóurn:BAAANQAECgUIBQAAAA==.Darthsyde:BAAANQAECgQIAwAAAA==.',
De='Deadergriff:BAAANQAECgUIDgAAAA==.Deadicated:BAAANQAECgUICgAAAA==.Deadinsíde:BAAANQAECggICAABNQAECggIEAAIAAAAAA==.Deathmark:BAAANQABCgYIBgAAAA==.Deeznutzs:BAAANQADCgQIBgAAAA==.Delan:BAAANQAECgYIBwAAAA==.Demolishonn:BAAANQAECgIIAgAAAA==.Desunaito:BAABNQAECoEpAAIJAAkKOCNIBwBKAwAJAAkKOCNIBwBKAwAAAA==.Dexter:BAAANQAECgQIBQAAAA==.',
Dh='Dhzilong:BAAANQAECggICAABNQAFFAUICgAMAB0aAA==.',
Di='Diddlefiddle:BAAANQADCgIIAgAAAA==.Dioji:BAAANQAECggIBgAAAA==.',
Dm='Dmeo:BAAANQADCgMIAwAAAA==.',
Do='Docadoodle:BAAANQADCgcIBwABNQAECggIIAANAMoYAA==.Docarcanis:BAAANQADCgcIBwABNQAECggIIAANAMoYAA==.Docwyle:BAABNQAECoEgAAINAAgKyhjcGgBLAgANAAgKyhjcGgBLAgAAAA==.Doozey:BAAANQABCgcJBwAAAA==.',
Dr='Dracmary:BAAANQADCgUIBQAAAA==.Dracnogard:BAAANQADCgYIFgAAAA==.Dracowulf:BAAANQAECgUIDAAAAA==.Dragonx:BAAANQAECgQIDwAAAA==.Drakowolf:BAAANQAECgUIBgAAAA==.Drama:BAAANQAECgEIAQAAAA==.Dreadful:BAABNQAECoEjAAIOAAgKYxn8MgBdAgAOAAgKYxn8MgBdAgAAAA==.Dreorge:BAAANQAFFAEIAQAAAA==.Drewceratops:BAAANQAECgcIEgAAAA==.Drimchi:BAAANQAECgEIAQAAAA==.Drimveil:BAAANQAECggIDgAAAA==.Drogô:BAAANQAECgQIBAAAAA==.Dromgar:BAAANQAECggIBgAAAA==.Dromkyr:BAABNQAECoEbAAIPAAgKuAzGHAC7AQAPAAgKuAzGHAC7AQAAAA==.Drossiechan:BAABNQAECoEYAAIQAAkKwRi9EgB+AgAQAAkKwRi9EgB+AgAAAA==.',
Du='Duellipa:BAAANQAECgQICQABNQAECgUIEgAIAAAAAA==.',
Dy='Dysian:BAAANQADCgQIBQAAAA==.Dywanw:BAAANQABCgYIBgAAAA==.',
Ed='Edward:BAAANQAECggJBwAAAA==.',
Ef='Effloria:BAABNQAECoEZAAIHAAgKTyMUBwAqAwAHAAgKTyMUBwAqAwAAAA==.',
Ek='Ekim:BAAANQADCgQIAwAAAA==.',
El='Elauvia:BAAANQAECgMIAwAAAA==.Elegia:BAAANQAECggIDgAAAA==.',
Em='Emleah:BAAANQAECgEIAQAAAA==.',
En='Enash:BAAANQADCgQIBAAAAA==.Encoredh:BAAANQAECgQJBAABNQAECgUIDQAIAAAAAA==.Encoredk:BAAANQADCgIIAgAAAA==.Encoree:BAAANQADCgcIBwABNQAECgUIDQAIAAAAAA==.Encorep:BAAANQAECgUIDQAAAA==.Enris:BAAANQADCgUICAAAAA==.',
Ev='Eviscerated:BAAANQAECgQIBQAAAA==.',
Fa='Fail:BAAANQADCgYICwAAAA==.Falker:BAAANQADCgYIBgAAAA==.Fallen:BAAANQAECgUIBwAAAA==.Fallingvoid:BAAANQAFFAIIAgAAAA==.Fancyfeet:BAAANQADCgIIAwABNQAECgYIBgAIAAAAAA==.Fatchungus:BAAANQAECgQIBQABNQAECgYIBgAIAAAAAA==.Fateesia:BAAANQAECgEIAQAAAA==.',
Fe='Fextardo:BAAANQADCgYIBgAAAA==.',
Fi='Finaliter:BAABNQAECoElAAIRAAkK3Rq1NgCvAgARAAkK3Rq1NgCvAgAAAA==.',
Fl='Flamingdrago:BAAANQAECgQIBQAAAA==.Flirtyflurry:BAAANQAECgQIBgAAAA==.',
Fo='Fox:BAACNQAFFIEGAAMSAAMKNhJ7BwAAAQASAAMKPhF7BwAAAQATAAIK8hIFAgCbAAA1AAQKgSsAAxMACQoPI5IBAFQDABMACQp0IpIBAFQDABIABwqcGxQeADYCAAAA.',
Fr='Fremder:BAAANQAECgUJBgAAAA==.Froggy:BAABNQAECoERAAINAAkKzAXDLwCBAQANAAkKzAXDLwCBAQAAAA==.Frogleap:BAAANQADCgUIBQABNQAECgkJEQANAMwFAA==.Frogred:BAAANQADCgQIBAABNQAECgkJEQANAMwFAA==.',
Fu='Funeral:BAACNQAFFIEYAAMUAAcKqR10AAB3AQAUAAQKcxt0AAB3AQAVAAQKqxvZCQBnAQA1AAQKgSQABBQACQrnJfYAAI0DABQACQrpJPYAAI0DABUABgrmJFZAAFECABYAAQrPDA8pADEAAAAA.Furiousmoon:BAAANQADCggICAAAAA==.Futuresailor:BAAANQADCgEIAQAAAA==.',
Fy='Fyjhrt:BAABNQAECoEUAAITAAcKxh7yBAB7AgATAAcKxh7yBAB7AgAAAA==.',
Ga='Galladin:BAAANQAECgIIAgABNQADCgYIDgAIAAAAAA==.Gallory:BAAANQAECggIBgAAAA==.Gayanall:BAAANQADCgMIAwAAAA==.',
Gd='Gdk:BAAANQAECgEIAQABNQAECggIHAADAGEZAA==.Gdkdrake:BAAANQADCgUIBQABNQAECggIHAADAGEZAA==.Gdkmage:BAAANQAECgUICQABNQAECggIHAADAGEZAA==.Gdkman:BAABNQAECoEcAAMDAAgKYRn3TAD0AQADAAcKqhf3TAD0AQAEAAEK6QQ87wAvAAAAAA==.Gdknotlock:BAAANQADCgQIBgABNQAECggIHAADAGEZAA==.',
Ge='Geoprince:BAAANQADCgcIEAAAAA==.Gerbon:BAAANQADCgMICAAAAA==.',
Gh='Ghaldrin:BAAANQABCggIFAAAAA==.Ghoulfriend:BAAANQADCgUICgAAAA==.',
Gi='Gigitty:BAAANQADCgYIBgAAAA==.Gimmedatneck:BAABNQAECoEVAAMSAAkKaR68BwAsAwASAAkKaR68BwAsAwAXAAQKnAVPNwC7AAABNQAFFAQIBwADAL4cAA==.Githrogathan:BAAANQAECgUIDgAAAA==.',
Go='Gokudin:BAAANQADCgIIAgABNQADCgIIAgAIAAAAAA==.Goldenrager:BAAANQADCgQIBAAAAA==.Gooseandmav:BAAANQADCgEIAQAAAA==.',
Gr='Grabetta:BAAANQADCgEIAQAAAA==.Gragasfat:BAAANQAECgIIAgAAAA==.Groundnpound:BAAANQADCgUJBQAAAA==.',
['Gâ']='Gârrosh:BAAANQADCgYIBgABNQAECggIJAABAL0MAA==.',
['Gö']='Gödhand:BAAANQADCgcIDgAAAA==.',
Ha='Haeha:BAAANQADCgQIBAAAAA==.Haraldsson:BAAANQADCggICAAAAA==.Hargrumn:BAAANQABCgMIAgAAAA==.Harrypooc:BAAANQADCgQJBAAAAA==.Hasaro:BAABNQAECoEmAAIYAAkKDgwPFQCOAQAYAAkKDgwPFQCOAQAAAA==.Hatcho:BAAANQADCgUICAAAAA==.Havokvacano:BAAANQAECgIIBgAAAA==.Havøckblaze:BAAANQADCgIIAgAAAA==.',
He='Healmachine:BAAANQAECgIIAgAAAA==.Hellbrringer:BAAANQAECgEIAQAAAA==.Helzer:BAAANQADCggIDwABNQAECggIGAACAE8SAA==.',
Ho='Holybaphomet:BAAANQADCgUICQAAAA==.Holyfarts:BAABNQAECoElAAQZAAkK0SD2AABIAwAZAAkKrh72AABIAwAaAAcKwhveNwBEAgAbAAgKSxUHHAAcAgAAAA==.Hornedraven:BAAANQADCgEIAQAAAA==.',
Hu='Humanform:BAAANQADCgUIBQAAAA==.Hunbroll:BAAANQADCgYIBgABNQAFFAQICgAcAIILAA==.Hungshaman:BAAANQABCgIIAgAAAA==.Hunterkiller:BAAANQADCggIGgAAAA==.',
Hx='Hx:BAAANQADCgYJDwAAAA==.',
Hy='Hypnoticpal:BAAANQAECggIDAAAAA==.',
['Hõ']='Hõnor:BAABNQAECoElAAMMAAkKfCGcIQAOAwAMAAkKTiCcIQAOAwAdAAUKRiCEEADBAQABNQAECgkJGgARAKAjAA==.',
Ia='Iammoo:BAAANQAECgIIAgAAAA==.',
Ig='Igriss:BAAANQAECgYIDgAAAA==.',
Il='Illidanx:BAAANQADCgQIBAAAAA==.Illuminaughd:BAAANQAECgMIBQAAAA==.Ilumii:BAAANQAECgMIAwAAAA==.Ilydris:BAAANQADCgEIAgAAAA==.',
Im='Imonthegcd:BAAANQAECgYIBgABNQAECgkJGgARAKAjAA==.',
In='Infinitepain:BAABNQAECoEjAAIaAAkKNSDHDQAuAwAaAAkKNSDHDQAuAwAAAA==.Innodk:BAAANQAECgYIBwAAAA==.',
Ir='Iridellis:BAAANQADCgcIBwABNQAECggIIwAOAGMZAA==.',
Is='Ispankutank:BAAANQADCgEIAQAAAA==.',
Ja='Jahjahblinks:BAAANQADCgYIFAABNQAECggIJAABAL0MAA==.Jave:BAAANQABCgQIBQAAAA==.Jaycers:BAABNQAECoEcAAIeAAgKrB92CgC1AgAeAAgKrB92CgC1AgAAAA==.Jayclark:BAAANQADCgEIAQAAAA==.',
Ji='Jimmypal:BAAANQAECgMIBQAAAA==.',
Jo='Joedingle:BAAANQAECgUIDQAAAA==.Joemomma:BAAANQADCgUJBQAAAA==.Johnnyboi:BAAANQADCgEIAQAAAA==.Jokestarfist:BAAANQAECgYIEgAAAA==.',
Jr='Jr:BAAANQADCggICAAAAA==.',
Ka='Kaelar:BAAANQADCgMIAwABNQAECgkJJQAfANkjAA==.Kaitokit:BAABNQAECoEwAAMgAAkKKhuSFQDTAgAgAAkKKhuSFQDTAgAhAAgKpA+LQwClAQAAAA==.Kalia:BAAANQADCgIIAgAAAA==.Kalyth:BAAANQAECgYICwAAAA==.Kamera:BAABNQAECoEZAAQRAAkK2RuGSQBrAgARAAgKKR2GSQBrAgAOAAMK9gWQzgCFAAAeAAEKVBEvWAAwAAAAAA==.Kandessa:BAAANQADCgIJAwAAAA==.Kaylah:BAABNQAECoEZAAMTAAgKQR88AwDVAgATAAgK9B48AwDVAgASAAYKSx5AJwDtAQAAAA==.Kayllina:BAAANQAECgUIDAAAAA==.Kayotic:BAAANQAECgIIAwAAAA==.',
Ke='Kelmorphic:BAABNQAECoEZAAIiAAgKLB+mAwDVAgAiAAgKLB+mAwDVAgAAAA==.',
Ki='Killcommand:BAAANQADCggICAABNQAFFAMIBQAKAKcTAA==.',
Ko='Kosmas:BAAANQAECgEJAQAAAA==.',
Kr='Krombear:BAAANQADCgIIAgAAAA==.',
Ku='Kudai:BAAANQAECgQIBgAAAA==.Kungpowchikn:BAAANQADCgIIAgAAAA==.Kurisuw:BAAANQAECgEIAQAAAA==.Kurookami:BAAANQADCgEIAQAAAA==.Kuukwa:BAAANQAECgUICAAAAA==.',
Ky='Kyarina:BAAANQABCggIDwAAAA==.',
['Kí']='Kíller:BAAANQAECgQIBQAAAA==.',
La='Lamadda:BAAANQADCgUIBQAAAA==.',
Ld='Ldg:BAAANQADCgQIBAAAAA==.',
Le='Leafdaddy:BAAANQAECgUICQABNQAECgkJHQAjANsbAA==.Letusgiveita:BAAANQADCgQJBAAAAA==.',
Li='Lightingbolt:BAAANQADCgUICwAAAA==.Lightshields:BAAANQADCgIIAgAAAA==.Lilymei:BAAANQADCggIEAAAAA==.Linesondra:BAAANQADCgUIBQAAAA==.Linissa:BAAANQAECgQIBgAAAA==.Littledude:BAAANQADCgYIBgAAAA==.Littlemorsel:BAABNQAECoEaAAIBAAgKdQyTYgD7AQABAAgKdQyTYgD7AQAAAA==.Livalifa:BAAANQAECgEIAQAAAA==.',
Lo='Lockenload:BAAANQAECgUIDAAAAA==.Lohhar:BAAANQADCggIDgAAAA==.Loser:BAAANQABCgQIBQAAAA==.',
Ls='Lselec:BAAANQAECgMJBQAAAA==.',
Lu='Lucens:BAAANQAECgYIEAAAAA==.Lucerna:BAAANQADCgIIAgAAAA==.Lurchdh:BAEANQADCgQJBAABNQAECgkJSwAcAO4ZAA==.Lurchdruid:BAEANQAECgIIAQABNQAECgkJSwAcAO4ZAA==.Lurchmage:BAEANQAECggIEQABNQAECgkJSwAcAO4ZAA==.Lurchn:BAEBNQAECoFLAAMcAAkK7hkXAwDkAgAcAAkK7hkXAwDkAgAKAAgKGAdN3gB5AQAAAA==.',
Ly='Lyricai:BAAANQAECgUICwAAAA==.',
Ma='Madjake:BAAANQADCggICAAAAA==.Maemae:BAAANQADCgYJCwAAAA==.Magallanes:BAAANQAECgQIBAAAAA==.Mapleleaf:BAAANQADCgcIBwAAAA==.Markyy:BAABNQAECoEaAAQRAAkKoCPuCQCWAwARAAkKoCPuCQCWAwAOAAQKLRC3oADwAAAeAAEKYSC0SgBdAAAAAA==.Matas:BAAANQAECgMJBAAAAA==.Maylinfenora:BAAANQAECgYIEAAAAA==.Mazzikane:BAAANQADCgYIBgAAAA==.',
Me='Meowizenith:BAAANQADCgUIBQAAAA==.Merdazin:BAAANQAECgQIDAAAAA==.Metalhedface:BAABNQAECoEbAAIMAAgKRREbdADqAQAMAAgKRREbdADqAQAAAA==.',
Mi='Mikecoxwall:BAAANQADCgEIAQAAAA==.Minisan:BAAANQADCgEIAQAAAA==.Misary:BAAANQAECgIIAgAAAA==.Mistake:BAAANQAECgUJCAAAAA==.',
Mo='Mogyar:BAABNQAECoEbAAIRAAcKLRezdQDiAQARAAcKLRezdQDiAQAAAA==.Moistybush:BAAANQAECgEIAQAAAA==.Moltalgol:BAAANQAECgEIAgAAAA==.Monkeli:BAABNQAECoEWAAIkAAcKcRTTCQDmAQAkAAcKcRTTCQDmAQAAAA==.Moocifer:BAAANQADCgIIAgAAAA==.Moogrim:BAAANQADCggICAAAAA==.Moonsiand:BAABNQAECoEaAAIBAAgKXB2tJQDHAgABAAgKXB2tJQDHAgABNQAECggIIAABAHsdAA==.Moreldwiddle:BAAANQAECgIIBgAAAA==.Morgaia:BAAANQAECgUIBQAAAA==.Morrigån:BAAANQADCgMIAwAAAA==.Motgus:BAAANQAECgUICgAAAA==.Mozzsticks:BAAANQADCgYICwAAAA==.',
Ms='Mshottie:BAAANQAECgEIAQAAAA==.',
Mx='Mx:BAAANQADCgYICgAAAA==.',
My='Mystrialia:BAAANQABCgYIBgAAAA==.Mythlock:BAAANQADCgcIEwAAAA==.',
['Mó']='Mócha:BAAANQAECgQICQAAAA==.',
Na='Nardrian:BAAANQAECgQIBQAAAA==.',
Ne='Nekiron:BAAANQADCgQIBAAAAA==.Nellaa:BAAANQAECgEIAQAAAA==.Nestaria:BAAANQADCggICAAAAA==.Netalanot:BAAANQADCgYIBgAAAA==.Nettik:BAAANQADCgUIBwAAAA==.Neverborn:BAAANQAECgYIEwAAAA==.',
Ni='Nightrage:BAAANQAECgMIAwAAAA==.Nilex:BAAANQADCgcIBwAAAA==.',
No='Nomadic:BAAANQADCgIIAgAAAA==.Notmypally:BAAANQAECgUIBQABNQAECggIIgAKANAgAA==.',
Nu='Numera:BAAANQADCgIIAwABNQAECgQICQAIAAAAAA==.Nutellaqq:BAAANQAECgYIEwAAAA==.',
Ob='Obeseotter:BAABNQAECoEuAAIKAAgK7xddcgBkAgAKAAgK7xddcgBkAgAAAA==.Oborax:BAAANQAECgMIBAABNQAECggIIAABAHsdAA==.',
Od='Od:BAAANQADCgYIFQAAAA==.',
Ol='Oliviabenson:BAAANQAECgUIDwAAAA==.',
Ox='Oxsidius:BAAANQAECgIIAwAAAA==.',
Pa='Paldi:BAAANQAECgQIBAABNQAECgYIBgAIAAAAAA==.Paliboos:BAAANQADCgYIBgAAAA==.Palulu:BAEANQAECggIDwAAAA==.Pariss:BAAANQADCgUIBQABNQAECggIDwAIAAAAAA==.Paws:BAAANQAECgUICwAAAA==.',
Pe='Peaky:BAABNQAECoEaAAQlAAcKtw22KgDFAAAlAAUK4wW2KgDFAAAjAAUKfQNVHgCmAAAQAAIKgAHZVAAvAAAAAA==.Perelia:BAAANQAECgYIDAAAAA==.',
Pl='Plondor:BAAANQABCgEIAQAAAA==.',
Po='Polarity:BAAANQAECgQIBgAAAA==.Pooche:BAAANQAECgIIAwAAAA==.Popcola:BAAANQAECgQICAAAAA==.',
Pp='Ppc:BAAANQAECgEIAQABNQAFFAMIBQAKAKcTAA==.',
Pr='Prezu:BAEBNQAECoEVAAIPAAcKnA7SIgBqAQAPAAcKnA7SIgBqAQABNQAECggIDwAIAAAAAA==.Procyonx:BAAANQAECgEIAQAAAA==.Prophofdoom:BAAANQAECgYIDgAAAA==.Prõc:BAAANQADCggICAAAAA==.',
Pv='Pvc:BAACNQAFFIEFAAIKAAMKpxMcIQAAAQAKAAMKpxMcIQAAAQA1AAQKgR8AAwoACQoPIY8pACUDAAoACQoPIY8pACUDACYAAQqaAHoLACkAAAAA.',
Ra='Raisedead:BAAANQADCgIIAgABNQADCggIDAAIAAAAAA==.Rancord:BAAANQADCggICAAAAA==.Rastaqwon:BAAANQADCgQIBAAAAA==.Ratsmasher:BAAANQAECgIIAgAAAA==.Razed:BAAANQADCgYICwAAAA==.',
Re='Renoitukax:BAAANQADCgEIAQAAAA==.Retrobution:BAAANQAECgcIDwAAAA==.Rezz:BAAANQAECgcIDAAAAA==.',
Rh='Rhohir:BAAANQABCgIIAgAAAA==.',
Ri='Riru:BAAANQAECgQIBwAAAA==.',
Ro='Rockstéady:BAAANQAECggICAAAAA==.Roopall:BAABNQAECoEXAAIOAAgKOyDyFwDwAgAOAAgKOyDyFwDwAgAAAA==.',
Ry='Rynzu:BAAANQAECgMIBAAAAA==.Ryzen:BAAANQAECgYICgAAAA==.',
Sa='Sabelwin:BAAANQADCgEIAQAAAA==.Sanasrindis:BAAANQADCgQIAgAAAA==.Saninar:BAAANQAECgUIDwAAAA==.Sanshift:BAAANQADCgYIBwAAAA==.Satansimp:BAAANQADCggINQAAAA==.',
Sc='Schadnfreude:BAABNQAECoEmAAMJAAkKtBpeEQDIAgAJAAkKtBpeEQDIAgAhAAEK1geBuQApAAAAAA==.Schezmu:BAAANQAECgUIBwAAAA==.',
Se='Sean:BAAANQADCgUICgAAAA==.Senorfiesta:BAAANQAECgUIDQAAAA==.Setazen:BAAANQADCgYIBgAAAA==.',
Sh='Shadowjoker:BAAANQAECgEIAQAAAA==.Shaee:BAAANQAECgUIDQAAAA==.Shamans:BAAANQAECgEIAQAAAA==.Shambalaya:BAAANQADCgQIAQAAAA==.Shaokhan:BAAANQAECgQIBAAAAA==.Shasta:BAABNQAECoEeAAIYAAkKfyX6AADJAwAYAAkKfyX6AADJAwAAAA==.Shihthead:BAAANQADCgUIBQAAAA==.Shisuiuchiha:BAAANQADCgIIAgAAAA==.Shmorg:BAAANQADCgEIAQAAAA==.Shootumup:BAABNQAECoEkAAMnAAkKYSI0AQBQAwAnAAkKYSI0AQBQAwABAAEKZRf7CAFOAAAAAA==.Shyx:BAAANQAECgYIDAAAAA==.',
Si='Simplèjack:BAAANQAECgcIEgAAAA==.Sinamon:BAAANQADCgYIDAAAAA==.Sinani:BAAANQADCgUJBQAAAA==.Sinnamon:BAAANQABCgQJBAABNQADCgYIDAAIAAAAAA==.',
Sj='Sjdh:BAAANQADCgYIBgABNQAECggIHgAMANAZAA==.',
Sk='Skar:BAAANQADCgUIBgAAAA==.Skram:BAAANQAECgQIBAABNQAECggIIwARAMkNAA==.Skronker:BAAANQADCggIDQAAAA==.',
Sl='Slammydooker:BAAANQAECgcIDgAAAA==.',
Sm='Smallkat:BAAANQAECgUIBQAAAA==.Smirksfotm:BAAANQAECgUICAABNQAECggIEAAIAAAAAA==.Smoketail:BAAANQAECgIJAgAAAA==.',
Sn='Snail:BAAANQAECgYIBgAAAA==.Sneakmanman:BAAANQADCgYJCQAAAA==.',
So='Somberdh:BAAANQADCggICwAAAA==.Sorni:BAAANQAECgUIEAAAAA==.Soulglo:BAAANQADCgcIDQAAAA==.',
Sp='Sprayandpray:BAAANQAECgMIBQAAAA==.Spritey:BAAANQABCgIIAgAAAA==.',
St='Stareless:BAAANQADCgYIBgAAAA==.Statik:BAAANQAECgMIAwAAAA==.Steveedudu:BAAANQADCggICAAAAA==.',
Su='Summondemons:BAAANQAECgIIBQAAAA==.Sunpali:BAAANQAECgUICQAAAA==.Susanno:BAAANQADCgUJCwAAAA==.',
Sy='Sylauda:BAAANQADCgYICgAAAA==.Sylvians:BAAANQAECgEIAQAAAA==.',
Ta='Tacutacudark:BAAANQADCgYIFAAAAA==.Taintedbeef:BAAANQADCgEIAQABNQAECgYIDAAIAAAAAA==.Talonflame:BAABNQAECoEZAAMoAAcKlRRLKAC8AQAoAAcKYhFLKAC8AQABAAMKOhfH2ADiAAAAAA==.Talonted:BAAANQAECgIIAgAAAA==.Tansu:BAAANQADCgcIDQAAAA==.Taterpuff:BAAANQABCgUIBQAAAA==.Taupo:BAAANQAECgEIAQAAAA==.Taxidermy:BAAANQADCgYIDAAAAA==.',
Te='Telarinda:BAAANQAECgIIAgAAAA==.',
Th='Thicclich:BAAANQAECgMIAwAAAA==.Thicktotem:BAAANQAECgEIAQAAAA==.Thickumz:BAAANQADCgQIBAAAAA==.Thisismeta:BAAANQAECgUICQAAAA==.Thorynwar:BAACNQAFFIEIAAIMAAUKZBTzCgCbAQAMAAUKZBTzCgCbAQA1AAQKgR0AAgwACQrkIGkWAEYDAAwACQrkIGkWAEYDAAE1AAQKCQklACEAZSYA.Thorýn:BAABNQAECoElAAMhAAkKZSbeBQCAAwAhAAkKZSbeBQCAAwAgAAcKKxoBNAD8AQAAAA==.Thórin:BAAANQAECgYIDAAAAA==.',
Ti='Tierax:BAABNQAECoEgAAMXAAkKoR+mBgABAwAXAAgK8CCmBgABAwASAAIK8RlrXgCdAAAAAA==.Tipsy:BAAANQAECgYJDwAAAA==.',
To='Tojì:BAAANQAECggIEAAAAA==.Tomfoolary:BAAANQADCgQIBAAAAA==.Tonathul:BAAANQADCggIEAAAAA==.Torrk:BAAANQADCgUICwAAAA==.Torultrear:BAAANQAECgIJAgAAAA==.Tot:BAABNQAECoEZAAIEAAgKxgfEcgBcAQAEAAgKxgfEcgBcAQAAAA==.',
Tr='Tralleth:BAAANQAECgQICwAAAA==.Trallock:BAAANQADCggJCAAAAA==.Traumatized:BAAANQADCgUIBwAAAA==.Truska:BAAANQABCgEIAQAAAA==.',
Tu='Tuskyrex:BAAANQABCgIIAgAAAA==.',
Tw='Twinklord:BAAANQAECgUICQAAAA==.Twostroke:BAAANQAECggIDwAAAA==.Twretwtwrewr:BAAANQADCgIJAgAAAA==.Twunkie:BAAANQADCgcIBwAAAA==.',
Ty='Tylopally:BAAANQAECgYIDQAAAA==.Tyloremixdd:BAAANQADCgYIBwAAAA==.Tylototem:BAAANQAECgQIBAAAAA==.',
['Tö']='Tötem:BAAANQADCgMIAwABNQAECgkJGgARAKAjAA==.',
Uj='Ujcpet:BAAANQADCgYIBgAAAA==.',
Un='Uncookedham:BAAANQADCgYIEAAAAA==.Underhorn:BAAANQADCgYIBgAAAA==.',
Va='Vaas:BAAANQADCggICAABNQAECggIHAAeAKwfAA==.Vaeelrundor:BAAANQAECgQIEAAAAA==.Valyr:BAAANQADCgQIBAAAAA==.Vampslayer:BAAANQADCgYIBgAAAA==.Vanillaface:BAAANQADCgYIBwAAAA==.Vañillaface:BAAANQABCgQIBgAAAA==.',
Ve='Vedebone:BAAANQAECgUIDAAAAA==.Vedexd:BAABNQAECoEdAAIBAAcKbg61gQCoAQABAAcKbg61gQCoAQAAAA==.Velarael:BAAANQAECgQICQAAAA==.Velexi:BAAANQADCgQIBwAAAA==.',
Vl='Vlidya:BAAANQADCgEIAQAAAA==.',
Vo='Voidberg:BAAANQADCggJDgAAAA==.',
Vs='Vs:BAAANQAECggIDgAAAA==.',
Wa='Wachonaso:BAABNQAECoEfAAIVAAkKcRzoKACqAgAVAAkKcRzoKACqAgAAAA==.Wastedsage:BAAANQAECgUICAAAAA==.Waterlou:BAAANQADCgIJAgAAAA==.',
Wh='Whatuphuz:BAAANQADCggIEAAAAA==.Wheresmyjaw:BAABNQAECoEgAAMVAAgKpRlhTwAeAgAVAAcKjhphTwAeAgAUAAMKzw7tPwCuAAAAAA==.',
Wi='Wildthree:BAAANQAECgYIDQAAAA==.Wilkieswar:BAAANQADCggIEgABNQAECgcIGQAKAKwdAA==.Willenda:BAAANQAECgEIAQAAAA==.Winterfall:BAAANQADCgUIBQAAAA==.',
Wu='Wuinn:BAACNQAFFIELAAIPAAUKiAkXCABvAQAPAAUKiAkXCABvAQA1AAQKgRoAAg8ACQp0FLkQAHECAA8ACQp0FLkQAHECAAAA.',
Xa='Xakutioner:BAABNQAECoEbAAILAAgKKxxlHgClAgALAAgKKxxlHgClAgAAAA==.Xaldiir:BAAANQAECgcIDQAAAA==.',
Xe='Xerexia:BAABNQAECoEpAAIMAAgKFQ2ZfwDIAQAMAAgKFQ2ZfwDIAQAAAA==.',
Xw='Xwoo:BAAANQAECgIIAgAAAA==.',
Ya='Yahro:BAAANQAECgcIEQAAAA==.',
Ye='Yellowranger:BAABNQAECoEaAAIOAAgKvhK3RwAFAgAOAAgKvhK3RwAFAgAAAA==.',
Yj='Yjn:BAAANQAECgYIBQAAAA==.',
Yo='Yongyong:BAAANQAECgMJBQAAAA==.Yotoymuerto:BAAANQAECgEIAQAAAA==.',
Yu='Yunara:BAAANQAECgYIBgAAAA==.Yustayoke:BAAANQAECgcIEwAAAA==.',
Za='Zalvianna:BAAANQAECgUIBQAAAA==.Zarathoz:BAAANQABCgYJBgAAAA==.Zarshx:BAAANQADCgQICAABNQAECgYIBgAIAAAAAA==.',
Ze='Zennith:BAAANQAECggIBwAAAA==.Zennithz:BAAANQAECggIEAAAAA==.Zeonz:BAAANQAECgEIAQAAAA==.',
Zi='Zilongmage:BAAANQAECgUJBQABNQAFFAUICgAMAB0aAA==.Zilongwar:BAACNQAFFIEKAAIMAAUKHRotCgCoAQAMAAUKHRotCgCoAQA1AAQKgRsAAgwACQqqIvYaAC4DAAwACQqqIvYaAC4DAAAA.',
Zo='Zonecw:BAAANQAECgYICwAAAA==.Zonedk:BAAANQAECgQIBgABNQAECgYICwAIAAAAAA==.',
['Ør']='Ørsted:BAAANQADCgIIAgABNQAECgEIAQAIAAAAAA==.',
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
