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

local lookup = {'Druid-Restoration','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Priest-Shadow','Shaman-Restoration','Warlock-Destruction','Warlock-Demonology','Shaman-Elemental','Hunter-BeastMastery','Paladin-Protection','Paladin-Holy','DeathKnight-Blood','Warlock-Affliction','Priest-Holy','Evoker-Devastation','Hunter-Marksmanship','Warrior-Arms','Mage-Arcane','Monk-Mistweaver','DemonHunter-Havoc','Monk-Brewmaster','Warrior-Fury','Paladin-Retribution','Hunter-Survival','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','Shaman-Enhancement','Monk-Windwalker',}
local provider = {region='US',realm="Mug'thol",name='US',type='weekly',zone=53,date='2026-09-22',data={Ad='Adjust:BAAANQAECgIIBAABNQAFFAUICwABAAsaAA==.',
Ae='Aedrenis:BAAANQADCgUIDgAAAA==.Aegrisomnia:BAAANQABCgMIAwABNQAECgcIEgACAAAAAA==.Aenstus:BAAANQADCgMJAwAAAA==.Aeropunk:BAAANQADCgIJAgAAAA==.Aerys:BAAANQAECgcJEAAAAA==.Aerøs:BAAANQAECgQIBwAAAA==.',
Ag='Aggiz:BAAANQADCgYICgABNQAECgcIEQACAAAAAA==.',
Aj='Ajaxprime:BAABNQAECoEcAAMDAAgK7yWQBgB5AwADAAgK7yWQBgB5AwAEAAEK6whEbQA1AAAAAA==.',
Ak='Akiojonës:BAAANQADCgYIBgAAAA==.',
Al='Alfabika:BAAANQAECgQJBAAAAA==.Alzim:BAAANQAECgcIEgAAAA==.',
Am='Amoriara:BAAANQADCgQIBAAAAA==.',
An='Angry:BAAANQAECgEIAgAAAA==.Ankelbiter:BAAANQAECggIDQAAAA==.Anûbis:BAAANQAECgUJBQAAAA==.',
Ar='Aragos:BAAANQAECgUJCQAAAA==.Arcelon:BAAANQAECgEIAQAAAA==.Arwenatak:BAAANQAECgcJEgAAAA==.',
As='Asmoon:BAABNQAFFIEHAAIFAAUKLRZeBQCrAQAFAAUKLRZeBQCrAQAAAA==.',
At='Athren:BAAANQAECgUIBQAAAA==.Athrogate:BAAANQAECgUIDAAAAA==.',
Au='Auraloxious:BAAANQAECgEIAQAAAA==.',
Av='Avanorina:BAAANQAFFAEJAQAAAA==.',
Az='Azmun:BAAANQAECgQJBAABNQAFFAUJBwAFAC0WAA==.Azmunn:BAAANQAECgMIAwABNQAFFAUJBwAFAC0WAA==.',
Ba='Baelzadru:BAAANQAECgIIAgAAAA==.Baelzheron:BAAANQAECgIIAgAAAA==.Baksylyk:BAAANQADCgYICwABNQAECgQICQACAAAAAA==.Ballador:BAAANQAECgYJCQAAAA==.Barakas:BAAANQADCgUIBQAAAA==.Barakoshamma:BAAANQAECgcIEwAAAA==.Barazudar:BAAANQAECgUJEAAAAA==.Baroke:BAAANQADCgYIBgAAAA==.Barragadin:BAAANQADCgUIBQABNQAECgYJDwACAAAAAA==.Barreta:BAAANQAECgYJDgAAAA==.',
Be='Beck:BAAANQAECgUJEAAAAA==.Beefykin:BAAANQAECgMJAwAAAA==.Bellamuerté:BAAANQAECgQIBAABNQAECgcJDwACAAAAAA==.Bellámuerté:BAAANQAECgcJDwAAAA==.Bemmy:BAAANQAECgQIBAABNQAECgcIEgACAAAAAA==.',
Bi='Bigdrandyy:BAAANQAECgYIEQAAAA==.Biggspal:BAAANQADCgYIBgAAAA==.',
Bl='Blackbird:BAAANQAECgcIEAAAAA==.Blackmage:BAAANQADCgYIBgAAAA==.Bloodlordzz:BAAANQAECgQIBwAAAA==.Bloodreina:BAAANQAECgYJEAABNQAECgcJCgACAAAAAA==.',
Bo='Bob:BAAANQAECgQJBgAAAA==.Bobtheknob:BAAANQADCgYIBgAAAA==.Bockandcalls:BAAANQAECgYICgAAAA==.Bolbi:BAAANQAECgIIAwAAAA==.',
Br='Brahm:BAAANQAECgEJAQABNQAECgYIDgACAAAAAA==.Brdua:BAAANQADCgYJBgAAAA==.Breadnbudda:BAAANQADCgYJFQAAAA==.Brogar:BAAANQADCgcJGAAAAA==.',
Bu='Bubblekush:BAAANQAECgYIBgABNQAFFAYIDgAGAAsaAA==.Buffknight:BAAANQADCggJCgABNQAECgYIDgACAAAAAA==.Bulkam:BAAANQAECgYJEAAAAA==.Bulkazarr:BAABNQAECoEVAAIHAAcKxRvSLABLAgAHAAcKxRvSLABLAgAAAA==.Burbuja:BAAANQADCggJCAABNQAECgYIDwACAAAAAA==.',
Ca='Callabash:BAAANQAECggIEwAAAA==.',
Ce='Celarena:BAAANQAECgQICgAAAA==.Cermit:BAAANQADCgUIBQAAAA==.',
Ch='Chewie:BAAANQADCgUIBQAAAA==.Chilla:BAAANQADCgQIBAAAAA==.Chomrogg:BAAANQAECgYJBwAAAA==.Chopzzpala:BAAANQADCgYICAAAAA==.Choubelle:BAAANQADCgQIBAAAAA==.Chyp:BAAANQAECgUICwAAAA==.Chzpriest:BAAANQAECgcIDgAAAA==.',
Ci='Cichorì:BAACNQAFFIELAAMIAAQKfRaeCACrAAAJAAIKyBt0EwCwAAAIAAIKMhGeCACrAAA1AAQKgRsAAwgACQoWInoFAKQCAAgACQpgG3oFAKQCAAkABgqaIlJBABgCAAAA.Cipa:BAAANQADCgcIBwAAAA==.Circee:BAAANQADCgcIFgAAAA==.',
Co='Colmer:BAAANQADCgMIAwAAAA==.',
Cr='Creckko:BAAANQADCgEIAQAAAA==.Crockito:BAACNQAFFIESAAIKAAUKHCVlAQA2AgAKAAUKHCVlAQA2AgA1AAQKgSEAAwoACQrlJicAABEEAAoACQrlJicAABEEAAcAAQpXDhTcACkAAAAA.',
Cy='Cyrusdavirus:BAAANQADCgUIBQAAAA==.',
Da='Dabu:BAAANQAECgQJBAAAAA==.Danto:BAAANQAECgIJAwABNQAECgYIDgACAAAAAA==.Darc:BAAANQADCggJDAAAAA==.Darktroll:BAABNQAECoEWAAILAAgKyBDHQQAxAgALAAgKyBDHQQAxAgAAAA==.',
De='Depoprovera:BAABNQAECoEbAAIMAAcKSBGdGwB/AQAMAAcKSBGdGwB/AQAAAA==.Deqz:BAAANQAECgcJDgAAAA==.',
Di='Diezel:BAAANQAECgIIAgABNQAECgMIAwACAAAAAA==.Dilox:BAAANQADCggIGgAAAA==.Dinosaur:BAAANQAECgcIEgABNQAECgkJFwANABgcAA==.Dirtydee:BAAANQAECgcJEgAAAA==.Disaaya:BAAANQAECgcIEgAAAA==.Divinecheeks:BAAANQAECgIIBAAAAA==.',
Dj='Djangó:BAAANQAECgEIAQAAAA==.',
Do='Donto:BAAANQAECgEIAQABNQAECgYIDgACAAAAAA==.Dontos:BAAANQAECgMIBAABNQAECgYIDgACAAAAAA==.Doodlebug:BAABNQAECoEkAAIOAAkKjBteEQDcAgAOAAkKjBteEQDcAgAAAA==.Dooshrocket:BAAANQAECgEIAQAAAA==.Dotsntaxes:BAACNQAFFIEHAAQIAAUKpgZzCwB6AAAJAAIKSA3PGgCQAAAIAAIK3gJzCwB6AAAPAAEK8wBsCgAtAAA1AAQKgR4ABAkACQryGPc6ADICAAkACArPFfc6ADICAAgABQrHEnweAFoBAA8AAQpCC9AcAEcAAAAA.',
Dr='Dracom:BAAANQAECgIJAgAAAA==.Dracuujin:BAAANQADCggJCAABNQAFFAUJCgAQABEbAA==.Dralioli:BAAANQAECgUJCAAAAA==.Dreanil:BAAANQAECgcIDAAAAA==.Droho:BAABNQAECoEWAAIRAAcKNiMpBwDbAgARAAcKNiMpBwDbAgABNQAFFAYIEAAKACUcAA==.Drroog:BAAANQADCgQIBQABNQAECgEIAQACAAAAAA==.',
Du='Dumper:BAAANQAECgIIAgAAAA==.',
Dw='Dwarfsize:BAAANQADCggICAABNQAFFAUICwABAAsaAA==.',
['Dâ']='Dârn:BAABNQAECoEaAAMJAAgKtCCFFADvAgAJAAgKtCCFFADvAgAIAAEKASDIVwBSAAAAAA==.',
El='Eleweaver:BAAANQADCgcIDAAAAA==.Elissra:BAAANQADCgEIAQABNQAECgYJCgACAAAAAA==.Elvispræstly:BAAANQADCgYIBgAAAA==.',
En='Enoughtalk:BAAANQAECgMJBgAAAA==.',
Eo='Eostre:BAAANQAECgYIDwAAAA==.',
Eu='Eupherine:BAAANQAECgUJEAAAAA==.',
Ev='Evillarry:BAAANQADCgYIDAAAAA==.Evilpaladin:BAABNQAECoEYAAIMAAgK9RERFwCxAQAMAAgK9RERFwCxAQAAAA==.',
Ez='Ezluz:BAAANQAECgYIEwAAAA==.',
Fa='Facsimile:BAAANQAECgcIDwAAAA==.',
Fe='Festers:BAAANQAECgYJCwAAAA==.',
Fi='Fingerwalk:BAAANQAECgYIDwAAAA==.',
Fl='Flappi:BAAANQAECgcJEQAAAA==.Flappii:BAAANQADCgEIAQAAAA==.Flaster:BAAANQADCgYIBgAAAA==.Fluffykat:BAAANQAECgQIDwAAAA==.',
Fo='Fosho:BAACNQAFFIEQAAIKAAYKJRx6AQAuAgAKAAYKJRx6AQAuAgA1AAQKgRwAAgoACQowJFQIAIEDAAoACQowJFQIAIEDAAAA.',
Fr='Franch:BAAANQAECgYJCwAAAA==.Frank:BAAANQADCgYJCwABNQAECgQIBwACAAAAAA==.Fraud:BAAANQAECgcJCgAAAA==.Freelvlsvnty:BAAANQADCgYIBgAAAA==.Froddy:BAAANQAECgUICAAAAA==.Frylockk:BAABNQAECoEcAAQPAAkKgB5fAQABAwAPAAgKlR9fAQABAwAJAAYKiBwwVADRAQAIAAEKQB3yVwBSAAAAAA==.',
Fu='Furrykane:BAEANQAECggJEwAAAA==.Future:BAAANQAECgcIEgAAAA==.',
Ga='Gaara:BAAANQAECgUICAAAAA==.Gamepunisher:BAAANQAECgYJDwAAAA==.Gares:BAAANQAECgcJDAAAAA==.',
Gi='Giorbs:BAAANQADCgYIBgAAAA==.',
Go='Goatgeek:BAAANQABCgMIAwABNQAECgMIAwACAAAAAA==.Goham:BAAANQAECgcIEgAAAA==.Goobe:BAAANQADCgQJBgABNQAECgcIEQACAAAAAA==.Goontotem:BAAANQAECgEIAQABNQAECgUIBgACAAAAAA==.Gorro:BAAANQADCgYIBgAAAA==.',
Gr='Grimkai:BAAANQABCgMIAwAAAA==.Grogon:BAAANQAECgEJAQAAAA==.Gromlo:BAAANQAECgcIEAAAAA==.Grulog:BAAANQAECgMIBQAAAA==.',
Gu='Guldav:BAAANQADCgMIAwAAAA==.Gunny:BAABNQAECoEaAAMLAAgKdiG6EQAVAwALAAgKdiG6EQAVAwASAAIKKRJXSQB+AAAAAA==.',
['Gã']='Gã:BAAANQADCgUIBQAAAA==.',
['Gö']='Göld:BAAANQADCgcIBwAAAA==.',
Ha='Haeliman:BAAANQADCggICAAAAA==.Haileigh:BAAANQADCggIGgAAAA==.Harleigh:BAAANQABCgMIAgAAAA==.Havöc:BAABNQAECoEXAAITAAgKmhsmOwB6AgATAAgKmhsmOwB6AgAAAA==.',
He='Herpenderper:BAAANQAECgEIAQAAAA==.',
Hi='Hikawa:BAABNQAECoEeAAIUAAcKfSUJLwACAwAUAAcKfSUJLwACAwAAAA==.Hippocratic:BAAANQAECgcICgAAAA==.',
Ho='Honortheox:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.',
Hu='Huntemall:BAAANQAECgMIBAAAAA==.',
Hy='Hysteriix:BAEBNQAECoEnAAIVAAkKQiQdAQCtAwAVAAkKQiQdAQCtAwAAAA==.',
Ic='Iceborn:BAAANQAECggIAQAAAA==.Iceshards:BAAANQAECgYJDwAAAA==.Icraptotems:BAAANQAECgEIAQAAAA==.',
Id='Idtrapthat:BAAANQAECgEIAQAAAA==.',
Il='Illidankior:BAAANQAFFAEIAQAAAA==.Illirothas:BAAANQAECgUIBQABNQAECgcJEgACAAAAAA==.',
Im='Imen:BAAANQAECgYJDgAAAA==.Imsassy:BAAANQAECgQJBAAAAA==.',
In='Infectedbøb:BAAANQAECgQICgAAAA==.Inmortuae:BAAANQADCggIFgABNQAECgcJEgACAAAAAA==.',
Io='Iornbane:BAAANQAECgQJBQAAAA==.',
Ir='Irissela:BAAANQAECgIJAgAAAA==.',
Is='Ispitmagic:BAAANQAECgEJAQAAAA==.',
Iv='Ivalice:BAAANQAECgcJEAAAAA==.',
Iz='Izüal:BAAANQADCgYICQABNQAECgQICQACAAAAAA==.',
Ja='Jafbe:BAAANQAECgUJBgAAAA==.Jaghatai:BAAANQAECgUIBwAAAA==.Jammer:BAAANQADCgYIBgAAAA==.',
Ji='Jimcarrey:BAAANQAECgIIAgABNQAECgQJBQACAAAAAA==.Jimmyc:BAAANQAECgQJBQAAAA==.Jimmysi:BAAANQAECgcIDQAAAA==.',
Jo='Joemauma:BAAANQAECgUIDwAAAA==.',
Jp='Jpam:BAABNQAECoEZAAIUAAkK1hlySwCpAgAUAAkK1hlySwCpAgAAAA==.',
Ju='Jumbosize:BAACNQAFFIELAAIBAAUKCxrjAQC7AQABAAUKCxrjAQC7AQA1AAQKgSUAAgEACQqPJeQAAL4DAAEACQqPJeQAAL4DAAAA.Jupîter:BAAANQAECgEIAQAAAA==.Justamuslim:BAAANQADCggICAABNQAECgYICgACAAAAAA==.',
Ka='Kaerlif:BAAANQAECgYIBgABNQAECgkJGgAWAG0dAA==.Kaiyley:BAAANQAECgUIBQAAAA==.Kalastrian:BAAANQAECgUJCgAAAA==.Karateshock:BAAANQAECgcIDQAAAA==.Karlmarks:BAAANQABCggJCgAAAA==.Kazuren:BAAANQAECgYJDgAAAA==.',
Ke='Keano:BAAANQAECgQIBwAAAA==.Keeldemall:BAAANQADCgIJAgAAAA==.Kelia:BAAANQADCgMIAwABNQAECgcJEgACAAAAAA==.Kelinna:BAAANQAECgUICAAAAA==.',
Kh='Khmelnitsky:BAAANQADCggICAAAAA==.',
Ki='Kirin:BAAANQAECgQJCAAAAA==.',
Kl='Klaye:BAAANQAECgMJAwABNQAECgYIDgACAAAAAA==.',
Kn='Knatknom:BAAANQAECgIIAgAAAA==.',
Ko='Kodabonk:BAABNQAECoEaAAIXAAgKEh3QBQCYAgAXAAgKEh3QBQCYAgAAAA==.Kodanorth:BAAANQAECgEJAQABNQAECggIGgAXABIdAA==.Korthos:BAAANQAECgYJCwAAAA==.Kotara:BAAANQADCggJDwAAAA==.',
Kr='Kraur:BAAANQAECgcJEgAAAA==.',
['Kì']='Kìngpin:BAAANQAECgUJDgAAAA==.',
La='Laarry:BAAANQADCgUIBQABNQAECgcJEgACAAAAAA==.Lammp:BAABNQAECoEaAAMHAAkK+BdoJwBoAgAHAAcKUBtoJwBoAgAKAAgK5RIYPQAFAgAAAA==.Lamppally:BAAANQADCgQIBAABNQAECgkJGgAHAPgXAA==.Lampshade:BAAANQADCggICAABNQAECgkJGgAHAPgXAA==.Laws:BAABNQAECoEXAAIEAAkKzgrSKwCVAQAEAAkKzgrSKwCVAQAAAA==.Lazydragon:BAAANQAECgYJEwAAAA==.',
Li='Liaeda:BAAANQAECgYIEAAAAA==.Lianshi:BAAANQADCgUIBQAAAA==.Linainverse:BAAANQAECgEJAgAAAA==.Lixie:BAAANQADCggICAAAAA==.',
Lo='Lolo:BAAANQADCggICAABNQAFFAYIEAAKACUcAA==.Loosie:BAAANQADCgEIAQAAAA==.Lost:BAAANQADCgUIBQABNQAECgkJFwAEAM4KAA==.Lovely:BAAANQAECgEIAgAAAA==.',
Lu='Luduhcris:BAAANQADCgYIEAAAAA==.Lugnuts:BAAANQAECgUIDAAAAA==.Lumiltiand:BAABNQAECoEbAAIDAAgKUyE7EwDYAgADAAgKUyE7EwDYAgABNQAFFAIIAwACAAAAAA==.',
Lw='Lwaxana:BAAANQADCgMIAwAAAA==.',
Ma='Makloy:BAAANQABCgYICAAAAA==.Malgoros:BAAANQAECgQIBAABNQAECgcIDwACAAAAAA==.Malgrendin:BAABNQAECoEXAAILAAcKFiN2HgDFAgALAAcKFiN2HgDFAgAAAA==.Malty:BAABNQAECoEaAAITAAgK2Rw/NwCKAgATAAgK2Rw/NwCKAgAAAA==.Malédictias:BAAANQAECgQJBAAAAA==.Manataurus:BAAANQADCgYIBgAAAA==.Manuall:BAAANQAECgQJBgAAAA==.Marbas:BAAANQAECgYJCwAAAA==.Maxidk:BAAANQAECgcIEwAAAA==.Maximage:BAAANQAECgQIBAABNQAECgcIEwACAAAAAA==.Maximonk:BAAANQADCgQIBgABNQAECgcIEwACAAAAAA==.Mazëkeen:BAAANQADCggICAAAAA==.',
Me='Medîvh:BAAANQAECgQIBAAAAA==.',
Mi='Midgemaisel:BAAANQAECgIJAgAAAA==.Mik:BAAANQABCgMIAgABNQADCgYJBgACAAAAAA==.Mikhael:BAAANQADCgEIAQABNQADCgYJBgACAAAAAA==.Mirado:BAABNQAECoEaAAIYAAgKxx6hAgDTAgAYAAgKxx6hAgDTAgAAAA==.Mirix:BAAANQADCgUIBQAAAA==.Mithridates:BAAANQAECgYJCwAAAA==.',
Mo='Molonlabe:BAAANQADCgUIBQAAAA==.Monix:BAAANQAECggIEQAAAA==.Monkragga:BAAANQAECgYJDwAAAA==.Mooseleroy:BAAANQAECgQJBgAAAA==.Mortarien:BAAANQAECggJCwAAAA==.Mozai:BAAANQADCgIIAgABNQAECggIGAAZAMMfAA==.',
Mu='Mugged:BAAANQAECgUIDQAAAA==.',
My='Myrtle:BAAANQAECgYJDgAAAA==.',
['Má']='Másóchist:BAAANQAECggIEAAAAA==.',
Ne='Necrophobic:BAAANQADCgQIBAAAAA==.',
Ni='Nice:BAAANQADCgYIDAAAAA==.Nikna:BAAANQADCgIIAgAAAA==.Niwatori:BAAANQAECgQIDwAAAA==.',
No='Noah:BAACNQAFFIEPAAMaAAYKoA8rAADfAQAaAAUKvhArAADfAQASAAMKzQ3ADADYAAA1AAQKgR4AAxoACQpSJZsAAIMDABoACQpSJZsAAIMDABIAAgrJFI9IAIIAAAAA.Nol:BAAANQAECggICgABNQAFFAYIEQAbACQfAA==.Nolarz:BAACNQAFFIERAAIbAAYKJB+KAABNAgAbAAYKJB+KAABNAgA1AAQKgSQAAhsACQpNJuYAAM0DABsACQpNJuYAAM0DAAAA.',
Nu='Nukthom:BAAANQADCgcICQAAAA==.',
Ny='Nyneaves:BAAANQAECgcIEwAAAA==.Nyst:BAAANQAECgYIEwAAAA==.',
Ob='Objekt:BAAANQAECgUIBwAAAA==.',
Oh='Ohmenwah:BAAANQADCgUICQAAAA==.',
Oj='Ojplosion:BAAANQAECgcJEgABNQABCggJCAACAAAAAA==.',
Ol='Olga:BAAANQAECgEIAwAAAA==.Olma:BAAANQAECgYIBAABNQAFFAUJCgAQABEbAA==.',
Om='Omghunter:BAAANQADCgYIBgAAAA==.',
On='Onisprite:BAAANQAECgEJAQAAAA==.',
Or='Orchaos:BAAANQADCgUIBgAAAA==.Ordhah:BAAANQAECgQICQAAAA==.',
Os='Osanna:BAAANQADCggJFQAAAA==.',
Pa='Paladout:BAABNQAECoEaAAIZAAgKNR/EKgCyAgAZAAgKNR/EKgCyAgAAAA==.Palletjack:BAABNQAECoEYAAIOAAgKBCbtBQB0AwAOAAgKBCbtBQB0AwAAAA==.Palli:BAAANQADCgUIDQAAAA==.Paona:BAAANQAECgYJEAAAAA==.Papafloppa:BAAANQADCgIIAgAAAA==.Paulioo:BAAANQABCgIIAgAAAA==.',
Pe='Peraroll:BAAANQADCggICAAAAA==.',
Ph='Phenphen:BAABNQAECoEdAAMbAAkK/x2BGAArAgAbAAgKTB+BGAArAgAcAAUK2BKMJQBKAQAAAA==.Physicyan:BAAANQAECgYICgAAAA==.',
Pi='Pipez:BAAANQAECgMIAwAAAA==.',
Pl='Planetdru:BAABNQAECoEYAAIFAAgKQh5jGQCsAgAFAAgKQh5jGQCsAgAAAA==.',
Po='Pogster:BAAANQADCgcIBwAAAA==.Pollyy:BAAANQAECgYICwAAAA==.Popshampain:BAAANQAECgQJCQAAAA==.',
Ps='Psychonight:BAABNQAECoEdAAIdAAkKTxk8AgC7AgAdAAkKTxk8AgC7AgAAAA==.',
Pu='Punchydabear:BAAANQAECgUIAQAAAA==.',
['Pì']='Pìp:BAAANQADCgYJBgAAAA==.',
Ra='Raenlling:BAAANQAFFAIIAwAAAA==.Ratscum:BAEANQADCggIGAAAAA==.Rayssa:BAAANQAECgcIEgAAAA==.',
Re='Redeker:BAAANQAECgYJDgAAAA==.Redlossa:BAAANQADCgIIAgAAAA==.Renneth:BAAANQADCgUJBQAAAA==.Rentahunter:BAAANQAECgEIAQABNQAECgQICAACAAAAAA==.Revax:BAAANQABCgUJBAABNQAECgcJEgACAAAAAA==.Reyna:BAAANQADCgQIBAABNQADCggICAACAAAAAA==.',
Rh='Rholand:BAAANQAECgEJAQAAAA==.',
Ri='Ricopsu:BAAANQAECgcJEAAAAA==.',
Rn='Rngnar:BAAANQAECggJCAAAAA==.',
Ro='Roakar:BAAANQADCgYIBgAAAA==.Rocklii:BAAANQADCggIDQAAAA==.Roguewolf:BAABNQAECoEYAAIFAAgKxAuGNgC5AQAFAAgKxAuGNgC5AQAAAA==.Rokdomaa:BAAANQAECgcJCwAAAA==.Roki:BAAANQAECgcJEAAAAA==.Rolow:BAAANQAECgcIEgAAAA==.Roony:BAACNQAFFIEPAAIBAAYK4x+ZAAAyAgABAAYK4x+ZAAAyAgA1AAQKgR8AAgEACQrZIkEFADQDAAEACQrZIkEFADQDAAAA.Roper:BAAANQAECgIJAgAAAA==.Roritai:BAAANQABCgQIBAABNQAECgMIBQACAAAAAA==.Rot:BAABNQAECoEcAAMDAAgKgSWjFwCtAgADAAcKQiGjFwCtAgAEAAYK7iX2EgCKAgAAAA==.Royle:BAAANQAECgQIBAAAAA==.',
Ru='Runes:BAABNQAECoEXAAIDAAgKdhV+JgAwAgADAAgKdhV+JgAwAgAAAA==.Runnerjay:BAAANQADCggIDwABNQAECgcIGwAMAEgRAA==.Rush:BAAANQADCgIJAgABNQAECgUIDQACAAAAAA==.Ruuf:BAAANQAECgcJDwAAAA==.',
Ry='Rysxn:BAAANQAECgcJDQAAAA==.Ryuujins:BAACNQAFFIEKAAIQAAUKERvkBADMAQAQAAUKERvkBADMAQA1AAQKgRsAAxAACQrpJJwLACcDABAACQqeJJwLACcDAB0ABQq/JBQGANcBAAAA.',
Sa='Sago:BAAANQAECgcJEgAAAA==.Sandman:BAAANQAECgQIBwAAAA==.',
Sc='Scumball:BAEANQADCgcIEgABNQADCggIGAACAAAAAA==.Scyon:BAABNQAECoEoAAIUAAkKJx2HNgDpAgAUAAkKJx2HNgDpAgAAAA==.',
Se='Selinie:BAAANQABCggIDQAAAA==.Senari:BAAANQAECgUIDQAAAA==.Senbane:BAAANQADCggICQAAAA==.Sencia:BAAANQAECgQIBQAAAA==.',
Sh='Shadowblazer:BAABNQAECoEXAAIJAAgKthuiJQCPAgAJAAgKthuiJQCPAgAAAA==.Shalizar:BAAANQADCgUICAAAAA==.Shanda:BAABNQAECoEaAAMHAAkKrxtqEwDqAgAHAAkKrxtqEwDqAgAKAAIKEhu7rgCYAAAAAA==.Shanto:BAAANQAECgYIDgAAAA==.Sheesh:BAAANQADCgcIDgAAAA==.Shesheshenn:BAABNQAECoEXAAMHAAkKFRdYQgDkAQAHAAYKeB1YQgDkAQAeAAgKnwGwGwDwAAAAAA==.Shoumei:BAABNQAECoEYAAMfAAgK7xV/FQAiAgAfAAgK7xV/FQAiAgAVAAUK8QqHIQDyAAAAAA==.Shugz:BAAANQADCgMIAwABNQAECggIEgACAAAAAA==.Shuken:BAAANQAECggIAQAAAA==.',
Si='Silfra:BAAANQAECgQIDAAAAA==.Sinfull:BAAANQADCggICAAAAA==.Sintharia:BAAANQADCgUJBQAAAA==.',
Sk='Skolaid:BAABNQAECoEaAAMNAAkKJCAzCwA6AwANAAkKJCAzCwA6AwAZAAEKeh9OAQFXAAAAAA==.Skornel:BAAANQADCgIIAgAAAA==.',
Sl='Slapparazzi:BAAANQADCgYIBQAAAA==.',
Sm='Smilingdev:BAAANQADCggIEAABNQAECgMIAwACAAAAAA==.Smoopoodoop:BAAANQAECgUIBQAAAA==.',
Sn='Snagglepuss:BAAANQADCggICAAAAA==.Sneakysin:BAAANQADCgQIBAAAAA==.',
So='Soulmend:BAAANQAECgYJCwAAAA==.Soulsproxy:BAAANQABCgQIBQAAAA==.',
Sp='Spaceman:BAAANQAECgUIDAAAAA==.',
Sq='Sqûïsh:BAAANQADCggICAAAAA==.',
St='Stabbz:BAAANQADCgUIBQAAAA==.Stevetson:BAAANQAECgIJAgAAAA==.Stoops:BAAANQADCggIFgAAAA==.Stormdemon:BAAANQAECgUJCAAAAA==.Stormspellz:BAAANQAECgcJEwAAAA==.',
Su='Supay:BAAANQAECgIJAgAAAA==.',
Sw='Swinginsista:BAAANQAECgYIDwAAAA==.',
Ta='Taldath:BAAANQADCggJDwAAAA==.Talicso:BAABNQAECoEaAAIUAAkKIhm4SwCoAgAUAAkKIhm4SwCoAgAAAA==.Talos:BAAANQAECgQIBQABNQAECgcJCgACAAAAAA==.Talzinn:BAAANQADCgYIBgABNQAECgcJCgACAAAAAA==.Tardalian:BAAANQADCgYICAAAAA==.Tarkinal:BAAANQAECgYIEwAAAA==.Taurito:BAAANQAECgQJBAAAAA==.',
Te='Teezee:BAAANQAECgcJEQAAAA==.Teitterdrud:BAAANQAECgYJDgAAAA==.Telira:BAAANQAECgYJCgAAAA==.Tenderhoof:BAABNQAECoEgAAMFAAkKDx8CDAA/AwAFAAkKDx8CDAA/AwABAAEKmASmUgAnAAAAAA==.',
Th='Thanatus:BAAANQADCgQJBAAAAA==.Thath:BAAANQADCggIHwAAAA==.Thavus:BAAANQADCgYIBgAAAA==.Thearatwo:BAAANQAECggIDAAAAA==.Thunderclapz:BAAANQAECgcJCAAAAA==.Thunsibution:BAAANQADCggICQABNQAFFAEIAQACAAAAAA==.',
Ti='Tickz:BAAANQAECgcIEgAAAA==.Tinilia:BAAANQADCgQIBQAAAA==.Tirah:BAAANQAECgcIEgAAAA==.',
To='Toat:BAAANQADCgYIBgAAAA==.Toeran:BAAANQAECgcJEgAAAA==.Tokémon:BAAANQAECgYICQAAAA==.Toxren:BAAANQAECgcJEgAAAA==.',
Tr='Traelin:BAABNQAECoEbAAINAAkKBiQTAwClAwANAAkKBiQTAwClAwAAAA==.Trickee:BAAANQAECgQIBQABNQAECgYJCwACAAAAAA==.',
Ts='Tskaha:BAAANQAECgIJAwAAAA==.',
Ty='Tyria:BAAANQAECgEIAgAAAA==.Tyruunas:BAAANQADCgMIAwAAAA==.',
Ug='Uggthok:BAAANQAECgIIBAAAAA==.',
Ur='Urizarah:BAAANQADCgYIDAAAAA==.',
Ut='Uthrid:BAAANQADCgYIBgAAAA==.',
Va='Vanadis:BAAANQADCgcICwAAAA==.Vardamir:BAABNQAECoEXAAINAAkKGByQEwDvAgANAAkKGByQEwDvAgAAAA==.Vargath:BAAANQADCgMIAwAAAA==.Vashstampede:BAAANQADCgYJCwAAAA==.',
Ve='Vei:BAAANQADCgUIDwABNQADCgIIAgACAAAAAA==.Velrik:BAAANQAECgQIBgAAAA==.Venema:BAAANQADCgIIAgAAAA==.Venüs:BAAANQAECgEIAQAAAA==.Vercy:BAAANQADCgUJBQAAAA==.Vezkin:BAABNQAECoEaAAIFAAkKryQfBgCIAwAFAAkKryQfBgCIAwAAAA==.',
Vi='Vintagejeans:BAAANQAECgUIBQAAAA==.Virtus:BAAANQAECgYJDgAAAA==.Vitrixz:BAAANQADCgQJBAAAAA==.Vizaimor:BAAANQAECgYICQAAAA==.',
Vo='Voi:BAAANQABCgIJAwABNQAECgEIAQACAAAAAA==.Vostok:BAABNQAECoEYAAITAAkKCRUHQwBbAgATAAkKCRUHQwBbAgAAAA==.',
Vu='Vulcãnus:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.',
Wa='Warcry:BAAANQAECgEJAQAAAA==.',
We='Wealthyscaly:BAAANQAECgMIBAAAAA==.Weedzzar:BAAANQADCgQIBAAAAA==.Werse:BAABNQAECoEaAAIQAAgKqx71GAC9AgAQAAgKqx71GAC9AgAAAA==.Wetloginyou:BAAANQAECgUJCAAAAA==.',
Wh='Whodi:BAAANQAECgUIDQAAAA==.',
Wi='Witt:BAAANQAECgQJCQAAAA==.',
Wo='Woementality:BAAANQADCgMIAwAAAA==.Wolful:BAAANQAECgUIDQAAAA==.',
Wr='Wrathoftitan:BAAANQADCgIIAgAAAA==.',
Wu='Wushoolay:BAAANQAECgQJCgAAAA==.',
Xn='Xnatem:BAAANQAECgUJDQAAAA==.',
Xo='Xoliver:BAAANQADCgYICQAAAA==.',
Ya='Yashiro:BAAANQAECgYJDgAAAA==.',
Ye='Yeraleth:BAABNQAECoEYAAIBAAgKWxxxDQCRAgABAAgKWxxxDQCRAgAAAA==.',
Yi='Yisiwang:BAAANQADCgcIBwAAAA==.',
Yo='Yorick:BAAANQADCggIFQAAAA==.Yorkj:BAAANQAECgYICgAAAA==.',
Za='Zalthorax:BAAANQADCgEJAQABNQAECgcJEgACAAAAAA==.Zatilion:BAAANQAECgcJEQAAAA==.Zavage:BAAANQADCgYICgABNQAECgUJDAACAAAAAA==.Zayn:BAAANQAECgMIAwAAAA==.',
Ze='Zenki:BAAANQADCgQJAgAAAA==.Zenkî:BAAANQADCgEIAQAAAA==.Zenrune:BAAANQAECgcICgAAAA==.Zephiday:BAAANQAECgMIAwAAAA==.',
Zi='Ziggashot:BAAANQAECgcIEQAAAA==.Zinsus:BAAANQADCggJEwABNQAECgcJEgACAAAAAA==.',
Zo='Zongchi:BAAANQAECgEIAQAAAA==.',
Zu='Zurahahsha:BAAANQAECgYJDwAAAA==.',
['Ðr']='Ðrow:BAABNQAECoEXAAISAAgKCQ8+HwDtAQASAAgKCQ8+HwDtAQAAAA==.',
['Óx']='Óxy:BAAANQAECgUIDQAAAA==.',
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
