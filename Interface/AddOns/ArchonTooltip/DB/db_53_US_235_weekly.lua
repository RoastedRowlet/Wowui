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

local lookup = {'Hunter-Marksmanship','Unknown-Unknown','Paladin-Holy','Mage-Arcane','DemonHunter-Devourer','Hunter-BeastMastery','Paladin-Retribution','Druid-Balance','Hunter-Survival','DemonHunter-Havoc','Shaman-Elemental','Rogue-Subtlety','Warrior-Arms','Warlock-Affliction','Shaman-Restoration','Warlock-Destruction','Warlock-Demonology','Druid-Restoration','Paladin-Protection',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=53,date='2026-09-22',data={Ad='Addisyn:BAAANQADCgUIEQAAAA==.',
Ae='Aemetris:BAAANQAECggICAAAAA==.Aendrel:BAAANQAECgMJAwAAAA==.',
Ai='Airaquafira:BAAANQAECgUICAAAAA==.',
Aj='Ajheria:BAAANQADCgQIBAAAAA==.',
Al='Alégria:BAAANQAECgYIBgAAAA==.',
Am='Amiragosa:BAAANQABCgYICAAAAA==.',
An='Anaire:BAAANQADCggJDQAAAA==.Anaiya:BAAANQADCgEIAQAAAA==.Anaru:BAAANQAECgYJDwAAAA==.Andalaine:BAAANQADCgYIDAAAAA==.Anraleth:BAABNQAECoEfAAIBAAkKdCMKAwCSAwABAAkKdCMKAwCSAwAAAA==.',
Ar='Arckillion:BAAANQAECgEJAQAAAA==.Arcángel:BAAANQADCgQIBAAAAA==.Ariana:BAAANQADCgYIDAAAAA==.Armâgeddon:BAAANQADCgYIBgAAAA==.',
As='Asparagus:BAAANQAECgMJBgAAAA==.Asturoth:BAAANQADCggIDgAAAA==.',
Au='Aust:BAAANQADCgcIBwAAAA==.',
Av='Averlis:BAAANQAECgQIBAAAAA==.Avoiddance:BAAANQADCgYIBgAAAA==.',
Ay='Ayci:BAAANQAECgQJBQAAAA==.',
Az='Azmithrilim:BAAANQAECgIIAwAAAA==.Azurargentyr:BAAANQABCgEIAQAAAA==.',
Ba='Baconbo:BAAANQAECgUICgAAAA==.Batistabomba:BAAANQADCgUIBQAAAA==.',
Be='Bended:BAAANQAECgUICwAAAA==.',
Bl='Blikey:BAAANQAECgcIBwAAAA==.Bloodyrott:BAAANQADCgIIAgAAAA==.Bluedrake:BAAANQAECgEIAQABNQAECgcIEAACAAAAAA==.Blueparrot:BAAANQAECgQJBgAAAA==.',
Bo='Bocantwo:BAAANQAECgEJAQAAAA==.Boggyboomer:BAAANQADCgMIAwAAAA==.',
Br='Brewteaful:BAAANQADCgEIAQAAAA==.Bringinlight:BAAANQADCgYJGAABNQADCgcJFgACAAAAAA==.',
Bu='Bulletz:BAAANQADCggIDQAAAA==.',
Ca='Cassandria:BAAANQAECgUIBwAAAA==.',
Ce='Cervixticklr:BAAANQADCgcJCwAAAA==.',
Ch='Chathlia:BAAANQABCgIIAgAAAA==.Choglana:BAAANQADCgQIBAAAAA==.Chogric:BAABNQAECoEZAAIDAAgK8yL0DAAnAwADAAgK8yL0DAAnAwABNQADCgQIBAACAAAAAA==.Châos:BAAANQAECgcJCwAAAA==.',
Ci='Cif:BAAANQAECgQICQAAAA==.Civetta:BAAANQAECgUICAAAAA==.',
Cr='Crazzywazzy:BAAANQAECgYIBgAAAA==.Crona:BAAANQAECgYJDgAAAA==.Crzyblnkrton:BAACNQAFFIEJAAIEAAUKPQs3DgB4AQAEAAUKPQs3DgB4AQA1AAQKgRsAAgQACQoBHJFIALECAAQACQoBHJFIALECAAAA.Crzzy:BAAANQAECgQIBAAAAA==.',
Cu='Cultera:BAABNQAECoEWAAIFAAgKEhhiFQBxAgAFAAgKEhhiFQBxAgAAAA==.Cuzon:BAAANQAECgcJDgAAAA==.',
Cy='Cyhyraethia:BAAANQAECgQJBwABNQAECgkJGwAFAPoYAA==.',
Da='Daish:BAAANQADCgEIAQAAAA==.Danda:BAAANQADCggIFgAAAA==.Daricepicker:BAABNQAECoEYAAIGAAgK2B/AIQCzAgAGAAgK2B/AIQCzAgAAAA==.Darkyn:BAAANQAECgYICgAAAA==.',
Dd='Ddeonù:BAABNQAECoEaAAIFAAgK6BJDGgA1AgAFAAgK6BJDGgA1AgAAAA==.',
De='Deadlysins:BAAANQADCggICAAAAA==.Deadscar:BAEANQAECgcIEgAAAA==.Deathmasterj:BAAANQADCgUIBgAAAA==.Dentheaded:BAACNQAFFIENAAIHAAYKARgDAQAzAgAHAAYKARgDAQAzAgA1AAQKgR8AAgcACQrMJWoDANADAAcACQrMJWoDANADAAAA.',
Di='Dithariaa:BAAANQADCgEIAQAAAA==.',
Do='Docryktor:BAAANQAECgUJDAAAAA==.Doomgears:BAAANQADCgEIAQAAAA==.',
Dr='Draculä:BAAANQAECgEIAQABNQAECgcJBwACAAAAAA==.Drashta:BAAANQAECgYIDgAAAA==.Drhurtouch:BAAANQAECgIJAgAAAA==.Drogas:BAAANQAECgYIEQAAAA==.Drtybear:BAAANQADCggJGgAAAA==.Druithz:BAAANQAECgQIBAABNQAECgkJIAADAAYcAA==.',
Du='Dundonn:BAAANQAECgIIAgAAAA==.',
['Dâ']='Dârrius:BAAANQADCggICQAAAA==.',
Eb='Ebonwings:BAAANQAECgQIBAAAAA==.',
Ed='Ediana:BAAANQAECgcJEwAAAA==.Edisian:BAAANQABCgIIAgAAAA==.',
Ee='Eebz:BAAANQADCgQIBAAAAA==.Eebzy:BAAANQAECgMIBQAAAA==.',
El='Elandrah:BAAANQAECgUIBAAAAA==.Elithsong:BAAANQABCgIIAgAAAA==.Elmô:BAAANQAECgUIDQAAAA==.',
Es='Essence:BAAANQADCgYIBgAAAA==.Estameling:BAAANQAECgUIBwAAAA==.',
Et='Etherah:BAAANQABCgEIAQAAAA==.',
Ex='Excizion:BAAANQAECgUJCwAAAA==.',
Fa='Fantabulouus:BAAANQADCggIDwAAAA==.Fantym:BAAANQABCgYJBgAAAA==.Farorê:BAAANQABCgEIAQAAAA==.Fathertim:BAAANQADCgEIAQAAAA==.',
Fe='Feldrena:BAAANQADCgYIBgAAAA==.',
Fl='Flangus:BAAANQADCgMIAwAAAA==.',
Fo='Forgiven:BAABNQAECoEXAAIIAAgK8yI5GQCtAgAIAAgK8yI5GQCtAgAAAA==.Foxyhound:BAAANQAECgYIBgAAAA==.',
Fr='Franksredhot:BAAANQAECgEIAQAAAA==.Frostii:BAAANQAECgUICQAAAA==.',
Fu='Fudestamp:BAAANQADCgcIDAAAAA==.Fugryktor:BAAANQAECgIIAwABNQAECgUJDAACAAAAAA==.Fuu:BAAANQABCgMJAwAAAA==.',
Fy='Fyre:BAAANQADCgEJAQAAAA==.',
Ga='Galandor:BAAANQADCgcIGgAAAA==.Gandaalf:BAAANQADCgUJBQAAAA==.Gandelfzz:BAAANQADCgEIAQAAAA==.',
Ge='Geedorah:BAAANQADCgIIAgAAAA==.Gemhide:BAAANQAECgUICwAAAA==.',
Gi='Gityadruid:BAAANQADCgYIEwABNQADCgcJFgACAAAAAA==.Gityahunter:BAAANQADCgcJFgAAAA==.',
Go='Gobanks:BAAANQAECgcIEAAAAA==.',
Gr='Graygoat:BAAANQADCgYIBgABNQAFFAcIGAAJAH8jAA==.Grayson:BAAANQADCgcJGAAAAA==.Graysurv:BAACNQAFFIEYAAIJAAcKfyMCAAAhAwAJAAcKfyMCAAAhAwA1AAQKgR8AAgkACQoEJxcAAPgDAAkACQoEJxcAAPgDAAAA.Grimik:BAAANQAECgYIEAAAAA==.Grimwali:BAAANQADCggIDwAAAA==.',
Ha='Hamelot:BAAANQAECgEIAQAAAA==.Hamremmi:BAAANQADCgIIAgABNQADCggICAACAAAAAA==.Hardrock:BAEANQADCgYIBwABNQADCgkJGAACAAAAAA==.',
He='Healsforu:BAAANQAECgEIAQAAAA==.',
Ho='Hobiscuits:BAEANQABCgcIEQABNQAECgEIAQACAAAAAA==.',
Hy='Hydrobubble:BAAANQADCgYIBgAAAA==.',
Il='Illyy:BAAANQAECgQJBgAAAA==.',
Im='Imagine:BAAANQAECgUIBQAAAA==.',
In='Indagussy:BAAANQAECgUICgABNQAFFAMIBQAKAB0fAA==.Indawhole:BAACNQAFFIEFAAIKAAMKHR9qBgAkAQAKAAMKHR9qBgAkAQA1AAQKgR4AAwoACQpEJEEJAC8DAAoACApCJEEJAC8DAAUACAqwIIYRAKICAAAA.',
Is='Isamna:BAAANQABCgIJAgAAAA==.',
Iz='Izumiwitabow:BAAANQADCgcJFQAAAA==.',
Ja='Jasmean:BAAANQABCgQIBQAAAA==.Jassabella:BAAANQAECgEIAgAAAA==.Javaluminous:BAAANQAECgUIBwAAAA==.Jaytsukitori:BAAANQAECgUICAABNQAECgcJDgACAAAAAA==.',
Jh='Jhantherox:BAAANQABCgQIBAAAAA==.Jheranton:BAAANQADCgYICgAAAA==.',
Ji='Jif:BAAANQAECgQIBAAAAA==.',
Jo='Joesepi:BAAANQAECgEIAQAAAA==.Jonah:BAAANQAECgQIBAABNQAECgQIBQACAAAAAA==.Joodee:BAAANQAECgEJAQAAAA==.',
Ka='Kackarot:BAABNQAECoEZAAILAAgKJBKHOQAWAgALAAgKJBKHOQAWAgAAAA==.Katrine:BAAANQAECgYIDQAAAA==.',
Ki='Kij:BAEBNQAECoEbAAIEAAkKzx//IAAzAwAEAAkKzx//IAAzAwAAAA==.Kilrah:BAAANQAECgUIDgAAAA==.Kissmycrits:BAAANQAECgQIDQAAAA==.Kissmywrath:BAAANQAECgEIAQAAAA==.Kiyana:BAAANQADCggJEgAAAA==.Kiyoine:BAAANQAECgUIBwAAAA==.',
Kn='Knocksteady:BAAANQAECgcIDwAAAA==.Knoxreaps:BAAANQADCgUIBQAAAA==.',
Ko='Kookie:BAAANQAECgUIBQAAAA==.',
Ky='Kynbrookera:BAAANQAECgUIBwAAAA==.',
['Kì']='Kìnky:BAAANQADCgcJBwAAAA==.',
La='Laetha:BAAANQADCgYIBgABNQAECgMJBQACAAAAAA==.',
Li='Lightweaver:BAAANQAECggIAQAAAA==.Linai:BAABNQAECoEbAAIMAAcKsgWMIQB5AQAMAAcKsgWMIQB5AQAAAA==.Linthe:BAAANQAECgYJEQAAAA==.Lit:BAAANQAECgIIAwAAAA==.Lites:BAAANQAECgUICgAAAA==.Littledog:BAAANQAECgYJCwAAAA==.',
Lo='Longshenks:BAAANQADCgIIAgAAAA==.Lotten:BAABNQAECoEaAAIHAAgKnBVVTgAbAgAHAAgKnBVVTgAbAgAAAA==.',
Lu='Luckevin:BAAANQADCgEIAQAAAA==.Lurashtai:BAAANQADCggJDgAAAA==.Luvido:BAAANQABCgcICQAAAA==.',
Ma='Malafang:BAAANQADCgcIDQAAAA==.Malanah:BAAANQADCgcIGAAAAA==.Malgaren:BAAANQABCggIEAAAAA==.Mangoo:BAAANQADCgYIBgAAAA==.Marandra:BAAANQADCgcIEAAAAA==.Mattu:BAAANQADCgQIBAAAAA==.Maverick:BAABNQAECoEgAAIMAAkKXCAmBAA9AwAMAAkKXCAmBAA9AwAAAA==.',
Me='Meregryn:BAAANQADCgUIBQAAAA==.Merunyaa:BAAANQAECgUIBQAAAA==.',
Mi='Michaella:BAAANQADCgYIEAAAAA==.Mil:BAAANQADCgQJBQAAAA==.Minipwn:BAAANQAECgIIAwAAAA==.',
Mk='Mk:BAEANQADCggIDgABNQAECgYIEgACAAAAAA==.',
Mo='Mogar:BAABNQAECoEVAAINAAgK1AkzlABGAQANAAgK1AkzlABGAQAAAA==.Moonzhine:BAAANQADCggJEQAAAA==.Moosejaw:BAAANQADCgcJFQAAAA==.Mordread:BAAANQADCgYIDQAAAA==.Morgalruk:BAAANQADCgcIDwAAAA==.',
My='Mythx:BAABNQAECoEYAAMGAAkKTiH0DwAjAwAGAAkKTiH0DwAjAwABAAgKFBChIwC5AQAAAA==.',
['Mý']='Mýthh:BAAANQADCggJAQAAAA==.',
Ne='Netherward:BAACNQAFFIEMAAIOAAYKXRoUAABKAgAOAAYKXRoUAABKAgA1AAQKgScAAg4ACQrNI0UAAKYDAA4ACQrNI0UAAKYDAAE1AAMKCAgIAAIAAAAA.',
Ni='Nivmizzet:BAAANQAECgUICwAAAA==.',
No='Nolakai:BAAANQADCgcJEgAAAA==.Novagosa:BAAANQAECgUICgABNQAECggJGgAPAFslAA==.Novalea:BAABNQAECoEaAAIPAAgKWyWzBwBaAwAPAAgKWyWzBwBaAwAAAA==.Nozom:BAAANQADCgYIBgAAAA==.',
Np='Np:BAAANQAECgMJBQAAAA==.',
Nu='Nutcutter:BAAANQADCgcIHAAAAA==.',
Ny='Nyvera:BAAANQADCgIIAgAAAA==.Nyxon:BAAANQADCgYIEQAAAA==.',
Os='Osirus:BAAANQAECgIIAgAAAA==.',
Ox='Oxxo:BAAANQADCgEIAQAAAA==.',
Pa='Palomar:BAAANQADCgcIGQAAAA==.Paraggonn:BAAANQAECgIIAwAAAA==.',
Ph='Pherkle:BAAANQADCgQJBgABNQAECgUJDAACAAAAAA==.Phuriosa:BAAANQADCgYIBgABNQAFFAEJAQACAAAAAA==.Phury:BAAANQAFFAEJAQAAAA==.Physinyx:BAAANQAECggJDwAAAA==.',
Pi='Pizza:BAAANQADCgEIAQAAAA==.',
Po='Pomomies:BAAANQABCgIIAgAAAA==.Pooseunpoose:BAAANQAECgUICAAAAA==.',
Pu='Pumbaa:BAAANQAECgEJAQABNQAECgcJBwACAAAAAA==.',
Ra='Raenyx:BAAANQAECggICAABNQAECggJDwACAAAAAA==.Ragnarrok:BAAANQADCgYIBgAAAA==.Raif:BAAANQAECgQJBAAAAA==.Raveneyes:BAEANQAECgYIDAAAAA==.',
Re='Reightous:BAAANQAECgIJAgAAAA==.Reylilyn:BAAANQAECgUJBwAAAA==.',
Rh='Rhaenfyre:BAABNQAECoEZAAMFAAcKABw7IQDsAQAFAAYKnBw7IQDsAQAKAAEKWRgJWwBMAAAAAA==.',
Ri='Ripley:BAAANQADCgcIBwABNQAECgkJIAAMAFwgAA==.Rivenel:BAABNQAECoEeAAMQAAkK9xsMBQCxAgAQAAgK8BsMBQCxAgARAAYKjBepVADPAQAAAA==.',
Ro='Robinvoid:BAAANQAECgcIBwAAAA==.Rondrey:BAAANQADCgYIBgAAAA==.Roquan:BAAANQAECgUIBgAAAA==.Rosè:BAAANQAECgYIBgABNQAECgkJIAAMAFwgAA==.',
Ru='Rubmyrott:BAAANQAECgEIAQAAAA==.Runawäy:BAAANQAECgUJBgAAAA==.Rundas:BAAANQAECgMJBgAAAA==.',
['Ré']='Rébél:BAAANQADCgYICAAAAA==.',
['Rê']='Rêdd:BAAANQAECgEIAgAAAA==.',
['Rì']='Rìven:BAAANQADCgYICAAAAA==.',
Sa='Sabeion:BAAANQAECggIBwAAAA==.Saharaa:BAAANQAECgEIAwAAAA==.Salswarriah:BAAANQADCgcIEAAAAA==.Sanasath:BAAANQAECgQICAABNQAECgUICgACAAAAAA==.',
Se='Segador:BAAANQAECgMJBgAAAA==.Seonwoo:BAAANQAECgEIAQAAAA==.Seraphim:BAAANQADCggICAAAAA==.',
Sg='Sgtbonesnap:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.',
Sh='Shamanizim:BAABNQAECoEbAAILAAkKuh6cEAAuAwALAAkKuh6cEAAuAwAAAA==.Shamanka:BAAANQADCgIIAgAAAA==.Shenzii:BAAANQAECgQJBwAAAA==.Shinoikari:BAAANQADCgQIBwABNQAECggIFwANAAwPAA==.Shinotenshi:BAAANQAECgEIAQABNQAECggIFwANAAwPAA==.Shugarae:BAAANQAECgQJAwAAAA==.',
Si='Silvafist:BAAANQAECgEJAwAAAA==.',
Sk='Skreezy:BAAANQADCgYIBgAAAA==.Skuls:BAAANQADCgEJAQAAAA==.',
Sl='Slashemup:BAAANQAECgcIEgAAAA==.Slayter:BAABNQAECoEXAAISAAkKUSOoAwBfAwASAAkKUSOoAwBfAwAAAA==.',
Sm='Smaugor:BAAANQAECgYJEQABNQAECgcJBwACAAAAAA==.',
So='Soju:BAAANQABCgIIAgABNQAECggIGAAGANgfAA==.Soliloquy:BAAANQAECgQIBgAAAA==.Solosith:BAAANQADCggIDwAAAA==.',
Sq='Squishyman:BAAANQAECgYICwAAAA==.Squishypal:BAAANQAECgQIBQABNQAECgYICwACAAAAAA==.',
St='Stõrm:BAAANQADCgYIBgABNQAECgcJBwACAAAAAA==.',
Su='Suzsette:BAAANQADCgcJGQAAAA==.',
Sw='Swïper:BAAANQABCgQJBAAAAA==.',
Sy='Sylris:BAAANQADCgIIAgAAAA==.Syrelyia:BAAANQAECgEIAQAAAA==.',
Ta='Tardovski:BAAANQAECgMJBgAAAA==.',
Te='Telda:BAAANQADCgQIBQAAAA==.Terrorwynd:BAAANQADCgUJBQAAAA==.',
Th='Thellaria:BAAANQABCggJDgAAAA==.Thiccterror:BAAANQAECgQIBAAAAA==.Thumpér:BAAANQADCgQIBAAAAA==.',
Ti='Tirgo:BAAANQABCgQJBQAAAA==.',
Tr='Treme:BAAANQAECgUICQAAAA==.Troche:BAAANQAECgUICgAAAA==.Truthfully:BAAANQAECgUJBgAAAA==.',
Tt='Ttjpll:BAAANQADCgYIDAAAAA==.',
Tu='Tuckncloak:BAAANQADCgQIBwAAAA==.',
Un='Undeadtoast:BAAANQAECgUICAABNQAECgkJGwATAAUiAA==.Unhappytoast:BAABNQAECoEbAAITAAkKBSKRBAAzAwATAAkKBSKRBAAzAwAAAA==.',
Ur='Uriania:BAAANQADCgIIAgAAAA==.',
Us='Ushioni:BAABNQAECoEcAAINAAgKGRNQXAD+AQANAAgKGRNQXAD+AQAAAA==.',
Va='Valklemor:BAAANQAECgEIAwAAAA==.Vallorien:BAAANQADCgcIGgAAAA==.',
Ve='Velaryn:BAAANQAECgcJBwAAAA==.Vengeânce:BAAANQADCgYICwAAAA==.',
Vi='Viveca:BAAANQAECgUIBwAAAA==.Viztrix:BAAANQABCgIIAgAAAA==.',
['Và']='Vàli:BAAANQADCgYIDAAAAA==.',
Wh='Wholy:BAAANQAFFAEIAQAAAA==.',
Wo='Woden:BAAANQADCgIJAwABNQADCggICAACAAAAAA==.',
Xa='Xaanii:BAAANQADCgcJGgAAAA==.Xarferrin:BAAANQADCgEIAQAAAA==.',
Xe='Xeeria:BAAANQAECgcJEwAAAA==.Xenzull:BAAANQADCgEIAQAAAA==.',
Xu='Xuecat:BAAANQADCggJCwAAAA==.Xuefeiyan:BAAANQAECgUIBwAAAA==.',
Za='Zaralina:BAAANQAECgQIDQAAAA==.Zarithra:BAAANQADCgQIDgAAAA==.Zarynth:BAAANQADCgQIBwAAAA==.Zaryssa:BAAANQAECgIIAwAAAA==.',
Ze='Zenzug:BAAANQADCgUIBQAAAA==.',
Zh='Zharazi:BAAANQABCgQIBAABNQADCggJEQACAAAAAA==.Zharfrost:BAAANQADCgUICQAAAA==.Zhieri:BAAANQADCgUICAAAAA==.',
Zm='Zmaj:BAAANQABCgIIAgAAAA==.',
Zo='Zombiehunter:BAAANQAECgQJCgAAAA==.Zomboy:BAAANQADCgMIAwAAAA==.Zortax:BAAANQAECgMJBQAAAA==.',
Zu='Zug:BAAANQAECgUICgAAAA==.',
['Âr']='Ârc:BAAANQAECgIIAwAAAA==.',
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
