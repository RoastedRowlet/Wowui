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

local lookup = {'Druid-Balance','Hunter-Marksmanship','Unknown-Unknown','Paladin-Holy','Mage-Arcane','DemonHunter-Devourer','Hunter-BeastMastery','Shaman-Enhancement','Paladin-Retribution','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Paladin-Protection','Hunter-Survival','DemonHunter-Havoc','Druid-Restoration','Shaman-Elemental','DeathKnight-Frost','Rogue-Subtlety','Monk-Windwalker','Warrior-Arms','Warlock-Affliction','Warlock-Demonology','Shaman-Restoration','Warlock-Destruction',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=53,date='2026-09-29',data={Ad='Addisyn:BAAANQADCgcIEwAAAA==.',
Ae='Aemetris:BAAANQAECggICAAAAA==.Aendrel:BAAANQAECgUICAAAAA==.',
Ai='Airaquafira:BAAANQAECgUIDQAAAA==.',
Aj='Ajheria:BAAANQADCgQIBAAAAA==.',
Al='Alégria:BAAANQAECgYIDAAAAA==.',
Am='Amiragosa:BAAANQABCgYICAAAAA==.',
An='Anaire:BAAANQAECgEIAQAAAA==.Anaiya:BAAANQADCgEIAQAAAA==.Anaru:BAABNQAECoEYAAIBAAcKBgPrXwD7AAABAAcKBgPrXwD7AAAAAA==.Andalaine:BAAANQADCgYIDAAAAA==.Anraleth:BAABNQAECoEjAAICAAkKsCMTBACBAwACAAkKsCMTBACBAwAAAA==.',
Ar='Arckillion:BAAANQAECgYIBgAAAA==.Arcángel:BAAANQAECgIIAgAAAA==.Ariana:BAAANQADCgYIDAAAAA==.Armâgeddon:BAAANQADCgYIBgAAAA==.',
As='Asparagus:BAAANQAECgQICgAAAA==.Asturoth:BAAANQADCggIDgAAAA==.',
Au='Aust:BAAANQADCgcIBwAAAA==.',
Av='Averlis:BAAANQAECgQIBAAAAA==.Avoiddance:BAAANQADCgYIBgAAAA==.',
Ay='Ayci:BAAANQAECgQIBgAAAA==.',
Az='Azmithrilim:BAAANQAECgIIAwAAAA==.Azurargentyr:BAAANQABCgEIAQAAAA==.',
Ba='Baconbo:BAAANQAECgUIDwAAAA==.Batistabomba:BAAANQADCgUIBQAAAA==.',
Be='Bended:BAAANQAECgYIEQAAAA==.',
Bl='Blikey:BAAANQAECgcIBwAAAA==.Bloodyrott:BAAANQADCgIIAgAAAA==.Bluedrake:BAAANQAECgQIBAABNQAECgkJHQABAFUfAA==.Blueparrot:BAAANQAECgUIDAAAAA==.',
Bo='Bocantwo:BAAANQAECgEJAQAAAA==.Boggyboomer:BAAANQADCgMIAwAAAA==.',
Br='Brewteaful:BAAANQADCgEIAQAAAA==.Bringinlight:BAAANQADCgcIHAABNQADCggIHgADAAAAAA==.',
Bu='Bulletz:BAAANQADCggIDQAAAA==.',
Ca='Cassandria:BAAANQAECgUIDAAAAA==.',
Ce='Cervixticklr:BAAANQADCggIEgAAAA==.',
Ch='Chathlia:BAAANQABCgIIAgAAAA==.Choglana:BAAANQADCgQIBAAAAA==.Chogric:BAABNQAECoEaAAIEAAgKQiMREAAoAwAEAAgKQiMREAAoAwABNQADCgQIBAADAAAAAA==.Châos:BAAANQAECggIEQAAAA==.',
Ci='Cif:BAAANQAECgQICQAAAA==.Civetta:BAAANQAECgUIDQAAAA==.',
Cr='Crazzywazzy:BAAANQAECgYICAAAAA==.Crona:BAAANQAECgcIEQAAAA==.Crzyblnkrton:BAACNQAFFIENAAIFAAUKPQu8FQBrAQAFAAUKPQu8FQBrAQA1AAQKgR4AAgUACQpcHWtMAMMCAAUACQpcHWtMAMMCAAAA.Crzzy:BAAANQAECgQIBAAAAA==.',
Cu='Cultera:BAABNQAECoEYAAIGAAgK6xgOFwB2AgAGAAgK6xgOFwB2AgAAAA==.Cuzon:BAAANQAECgcIEAAAAA==.',
Cy='Cyhyraethia:BAAANQAECgUIDAABNQAECgkJIwAGADEbAA==.',
Da='Dagden:BAAANQADCgUIBQAAAA==.Daish:BAAANQADCgEIAQAAAA==.Danda:BAAANQADCggIFgAAAA==.Daricepicker:BAABNQAECoEfAAIHAAgK2B+JKAC6AgAHAAgK2B+JKAC6AgAAAA==.Darkyn:BAAANQAECgcIEQAAAA==.',
Dd='Ddeonù:BAABNQAECoEeAAIGAAgK6BJdHwAYAgAGAAgK6BJdHwAYAgAAAA==.',
De='Deadlysins:BAAANQADCggICAAAAA==.Deadscar:BAEBNQAECoEXAAIIAAgKBiUwBAA6AwAIAAgKBiUwBAA6AwAAAA==.Deathmasterj:BAAANQADCgUIBgAAAA==.Dentheaded:BAACNQAFFIESAAIJAAYKtx3MAQA4AgAJAAYKtx3MAQA4AgA1AAQKgSIAAgkACQrRJaUFAL0DAAkACQrRJaUFAL0DAAAA.',
Di='Dithariaa:BAAANQADCgEIAQAAAA==.',
Do='Docryktor:BAAANQAECgYIEgAAAA==.Doomgears:BAAANQADCgEIAQAAAA==.',
Dr='Draculä:BAAANQAECgEIAQABNQAECgcJBwADAAAAAA==.Drashta:BAAANQAECgYIDgAAAA==.Drhurtouch:BAAANQAECgIIAgAAAA==.Drogas:BAABNQAECoEbAAQKAAcK9wzBIQB4AQAKAAcK9wzBIQB4AQALAAYKrAeRHgAnAQAMAAUKJw2FDwDmAAAAAA==.Drtybear:BAAANQADCggIIAAAAA==.Druithz:BAAANQAECgQIBAABNQAECgkJJgAEAD0dAA==.',
['Dâ']='Dârrius:BAAANQADCggICQAAAA==.',
Eb='Ebonwings:BAAANQAECgYIBwAAAA==.',
Ed='Ediana:BAABNQAECoEbAAMFAAgKjQWX1gCIAQAFAAgKjAWX1gCIAQANAAIKcgOhLwBNAAAAAA==.Edisian:BAAANQABCgIIAgAAAA==.',
Ee='Eebz:BAAANQADCgQIBAAAAA==.Eebzy:BAAANQAECgUICgAAAA==.',
El='Elandrah:BAAANQAECgUICQAAAA==.Elithsong:BAAANQABCgIIAgAAAA==.Elmô:BAAANQAECgUIEgAAAA==.',
Es='Essence:BAAANQADCgYIBgAAAA==.Estameling:BAAANQAECgUIDAAAAA==.',
Et='Etherah:BAAANQABCgEIAQAAAA==.',
Ex='Excizion:BAAANQAECgUIEAAAAA==.',
Fa='Fantabulouus:BAAANQAECgcIBwAAAA==.Fantym:BAAANQABCgYJBgAAAA==.Farorê:BAAANQABCgEIAQAAAA==.Fathertim:BAAANQADCgEIAQAAAA==.',
Fe='Feldrena:BAAANQADCgYIBgAAAA==.',
Fl='Flangus:BAAANQADCgYICQAAAA==.',
Fo='Forgiven:BAABNQAECoEXAAIBAAgK8yKiIACSAgABAAgK8yKiIACSAgAAAA==.Foxyhound:BAAANQAECgYIBgAAAA==.',
Fr='Franksredhot:BAAANQAECgEIAQAAAA==.Frostii:BAAANQAECgYICgAAAA==.',
Fu='Fudestamp:BAAANQAECgMIAwAAAA==.Fugryktor:BAAANQAECgIIBQABNQAECgYIEgADAAAAAA==.Fuu:BAAANQABCgMJAwAAAA==.',
Fy='Fyre:BAAANQADCgEJAQAAAA==.',
Ga='Galandor:BAAANQADCggIIgAAAA==.Gandaalf:BAAANQAECgYIBgAAAA==.Gandelfzz:BAAANQADCgEIAQAAAA==.',
Ge='Geedorah:BAAANQADCgIIAgAAAA==.Gemhide:BAAANQAECgYIDAAAAA==.Gerbo:BAAANQABCgIIAwAAAA==.',
Gi='Gityadruid:BAAANQADCgYIGQABNQADCggIHgADAAAAAA==.Gityahunter:BAAANQADCggIHgAAAA==.',
Go='Gobanks:BAABNQAECoEbAAIOAAgKhx7vCQDAAgAOAAgKhx7vCQDAAgAAAA==.',
Gr='Grayarms:BAAANQAECgQIBgAAAA==.Graygoat:BAAANQADCgYIBgABNQAFFAcIGQAPAH8jAA==.Grayson:BAAANQADCggIIAAAAA==.Graysurv:BAACNQAFFIEZAAIPAAcKfyMDAAAHAwAPAAcKfyMDAAAHAwA1AAQKgSIAAg8ACQoEJyMAAOsDAA8ACQoEJyMAAOsDAAAA.Grimik:BAAANQAECgcIEQAAAA==.Grimwali:BAAANQAECgMIAwAAAA==.',
Ha='Hamelot:BAAANQAECgEIAQAAAA==.Hamremmi:BAAANQADCgIIAgABNQAECgEIAQADAAAAAA==.Hardrock:BAEANQADCgcICwABNQAECgMIBgADAAAAAA==.',
He='Healsforu:BAAANQAECgEIAQAAAA==.',
Ho='Hobiscuits:BAEANQABCgcIEQABNQAECgMIBAADAAAAAA==.',
Hy='Hydrobubble:BAAANQADCgYIBgAAAA==.',
Il='Illyy:BAAANQAECgQJBgAAAA==.',
Im='Imagine:BAAANQAECgcIBwAAAA==.',
In='Indagussy:BAAANQAECgcIEQABNQAFFAUICgAQAFQgAA==.Indawhole:BAACNQAFFIEKAAIQAAUKVCDmAwDcAQAQAAUKVCDmAwDcAQA1AAQKgSAAAxAACQqKJGcMABsDABAACAqRJGcMABsDAAYACAqwIBEWAIMCAAAA.',
Is='Isamna:BAAANQABCgIJAgAAAA==.',
Iz='Izumiwitabow:BAAANQADCggIHQAAAA==.',
Ja='Jasmean:BAAANQABCgYIBwAAAA==.Jassabella:BAAANQAECgEIAgAAAA==.Javaluminous:BAAANQAECgUIDAAAAA==.Jaytsukitori:BAAANQAECgUICAABNQAECgcIEAADAAAAAA==.',
Jd='Jdots:BAAANQADCgcIDAAAAA==.',
Jh='Jhantherox:BAAANQABCgQIBAAAAA==.Jheranton:BAAANQADCgYICgAAAA==.',
Ji='Jif:BAAANQAECgUIBQAAAA==.',
Jo='Joesepi:BAAANQAECgIIAgAAAA==.Jonah:BAAANQAECgQIBgABNQAECgcIDAADAAAAAA==.Joodee:BAAANQAECgUIBgAAAA==.Jordi:BAAANQADCgcIBwAAAA==.Joseon:BAAANQAECgQIBAABNQAECgkJGQARANcjAA==.',
Ka='Kackarot:BAABNQAECoEhAAISAAgKaBIDRwAMAgASAAgKaBIDRwAMAgAAAA==.Katrine:BAABNQAECoEZAAITAAgKXROhJgADAgATAAgKXROhJgADAgAAAA==.',
Ki='Kij:BAECNQAFFIEHAAMNAAMKGhM4BACkAAANAAIKCRM4BACkAAAFAAEKOxNdQgBQAAA1AAQKgR4AAwUACQrPH2IwABADAAUACQrPH2IwABADAA0AAQqbI/AoAGkAAAAA.Kilrah:BAAANQAECgUIDgAAAA==.Kissmycrits:BAAANQAECgQIEQAAAA==.Kissmywrath:BAAANQAECgEIAQAAAA==.Kiyana:BAAANQAECgIIAgAAAA==.Kiyoine:BAAANQAECgUIDAAAAA==.',
Kn='Knocksteady:BAAANQAECgcIEAAAAA==.Knoxreaps:BAAANQADCgUIBQAAAA==.',
Ko='Kookie:BAAANQAECgUIBQAAAA==.',
Ky='Kynbrookera:BAAANQAECgUIDgAAAA==.',
Kz='Kzmyng:BAAANQADCgcIBwAAAA==.',
['Kì']='Kìnky:BAAANQADCgcJBwAAAA==.',
La='Lacquerhead:BAAANQADCgQIBAABNQADCgYIBgADAAAAAA==.Laetha:BAAANQADCggIDgABNQAECgQICQADAAAAAA==.',
Li='Lightweaver:BAAANQAECggIAQAAAA==.Linai:BAABNQAECoEhAAIUAAcK8ghqIgCPAQAUAAcK8ghqIgCPAQAAAA==.Linthe:BAAANQAECgcIEgAAAA==.Lit:BAAANQAECgIIBQAAAA==.Lites:BAAANQAECgYICwAAAA==.Littledog:BAAANQAECgcIDgAAAA==.',
Lo='Longshenks:BAAANQADCgIIAgAAAA==.Lotten:BAABNQAECoEdAAIJAAgKthb0XwAiAgAJAAgKthb0XwAiAgAAAA==.',
Lu='Luckevin:BAAANQAECgIIAgAAAA==.Lurashtai:BAAANQAECgIIAgAAAA==.Luvido:BAAANQABCgcICQAAAA==.',
Ma='Malafang:BAAANQAECgEIAQAAAA==.Malanah:BAAANQADCggIIAAAAA==.Malgaren:BAAANQABCggIEwAAAA==.Mangoo:BAAANQADCgYIBgAAAA==.Marandra:BAAANQADCgcIEAAAAA==.Mattu:BAAANQADCgQIBAAAAA==.Maverick:BAACNQAFFIEFAAIUAAMKygwwCQD0AAAUAAMKygwwCQD0AAA1AAQKgSQAAhQACQr+IJEEADgDABQACQr+IJEEADgDAAAA.',
Me='Meregryn:BAAANQADCgUIBQAAAA==.Merunyaa:BAAANQAECgcICAAAAA==.',
Mi='Michaella:BAAANQADCgYIEAAAAA==.Mil:BAAANQADCgQJBQAAAA==.Minipwn:BAAANQAECgQIBwAAAA==.',
Mk='Mk:BAEANQADCggIDgABNQAECgcIGQAVAIwbAA==.',
Mo='Mogar:BAABNQAECoEVAAIWAAgK1Al4rwA6AQAWAAgK1Al4rwA6AQAAAA==.Moonzhine:BAAANQADCggJEQAAAA==.Moosejaw:BAAANQADCgcIGwAAAA==.Mordread:BAAANQADCgYIEwAAAA==.Morgalruk:BAAANQADCgcIFgAAAA==.',
My='Mythx:BAABNQAECoEYAAMHAAkKTiHsGQAAAwAHAAkKTiHsGQAAAwACAAgKFBDBKgCkAQAAAA==.',
['Mý']='Mýthh:BAAANQADCggIAQAAAA==.',
Ne='Netherward:BAACNQAFFIERAAMXAAYKXRoiAAA7AgAXAAYKXRoiAAA7AgAYAAMKmhi7EQAAAQA1AAQKgSoAAxcACQreI20AAJUDABcACQreI20AAJUDABgAAgoBHNfdAKIAAAE1AAQKAQgBAAMAAAAA.',
Ni='Nivmizzet:BAAANQAECgUIEAAAAA==.',
No='Nolakai:BAAANQADCgcIGQAAAA==.Novagosa:BAAANQAECgUICwABNQAECgkJGwAZAIMjAA==.Novalea:BAABNQAECoEbAAIZAAkKgyM5BACTAwAZAAkKgyM5BACTAwAAAA==.Nozom:BAAANQADCgYIBgAAAA==.',
Np='Np:BAAANQAECgMJBQAAAA==.',
Nu='Nutcutter:BAAANQADCgcIIwABNQADCggIKgADAAAAAA==.',
Ny='Nyvera:BAAANQADCgIIAgAAAA==.Nyxon:BAAANQADCgYIEQAAAA==.',
Os='Osirus:BAAANQAECgIIAgAAAA==.',
Ox='Oxxo:BAAANQADCgEIAQAAAA==.',
Pa='Palomar:BAAANQADCggIIQAAAA==.Paraggonn:BAAANQAECgIIAwAAAA==.',
Ph='Pherkle:BAAANQADCgUICAABNQAECgYIEgADAAAAAA==.Phuriosa:BAAANQAECgEIAQABNQAFFAEIAQADAAAAAA==.Phury:BAAANQAFFAEIAQAAAA==.Physinyx:BAAANQAECggIEgAAAA==.',
Pi='Pizza:BAAANQADCgEIAQAAAA==.',
Po='Pomomies:BAAANQABCgIIAgAAAA==.Pooseunpoose:BAAANQAECgcICgAAAA==.',
Pu='Pumbaa:BAAANQAECgEJAQABNQAECgcJBwADAAAAAA==.',
Ra='Raenyx:BAAANQAECggIEAABNQAECggIEgADAAAAAA==.Ragnarrok:BAAANQADCgYIBgAAAA==.Raif:BAAANQAECgUICQAAAA==.Raveneyes:BAEANQAECgYIDAAAAA==.',
Re='Reightous:BAAANQAECgIIAwAAAA==.Reylilyn:BAAANQAECgYIDQAAAA==.',
Rh='Rhaenfyre:BAABNQAECoEgAAMGAAgKBB3vGgBKAgAGAAcKrx3vGgBKAgAQAAEKWRicbABIAAAAAA==.',
Ri='Ripley:BAAANQAECgcIBwABNQAFFAMIBQAUAMoMAA==.Rivenel:BAACNQAFFIEFAAMYAAIKoQ4GLABSAAAYAAEKiREGLABSAAAaAAEKuAuJGQBMAAA1AAQKgSAAAxoACQo1HOoFAKMCABoACArwG+oFAKMCABgABgrpFypsAMIBAAAA.',
Ro='Robinvoid:BAAANQAECgcIDAAAAA==.Rondrey:BAAANQADCgYIBgAAAA==.Roquan:BAAANQAECgUICwAAAA==.Rosè:BAAANQAECgYIBgABNQAFFAMIBQAUAMoMAA==.',
Ru='Rubmyrott:BAAANQAECgEIAQAAAA==.Runawäy:BAAANQAECgUIBgAAAA==.Rundas:BAAANQAECgQICgAAAA==.',
['Ré']='Rébél:BAAANQADCgYICAAAAA==.',
['Rê']='Rêdd:BAAANQAECgQIBgAAAA==.',
['Rì']='Rìven:BAAANQADCgYICAAAAA==.',
Sa='Sabeion:BAAANQAECggIBwAAAA==.Saddie:BAAANQADCgUIBQAAAA==.Saharaa:BAAANQAECgEIAwAAAA==.Salswarriah:BAAANQADCggIGAAAAA==.Sanasath:BAAANQAECgQICAABNQAECgYIDgADAAAAAA==.',
Se='Segador:BAAANQAECgMJBgAAAA==.Seonwoo:BAAANQAECgEIAQAAAA==.Seraphim:BAAANQADCggICAAAAA==.',
Sg='Sgtbonesnap:BAAANQADCgUIBQABNQAECgEIAQADAAAAAA==.',
Sh='Shamanizim:BAABNQAECoEjAAISAAkKwh+AEgA6AwASAAkKwh+AEgA6AwAAAA==.Shamanka:BAAANQADCgIIAgAAAA==.Shenzii:BAAANQAECgQICAAAAA==.Shinoikari:BAAANQADCgUIDAABNQAECggIHwAWADERAA==.Shinotenshi:BAAANQAECgIIAwABNQAECggIHwAWADERAA==.Shugarae:BAAANQAECgQJAwAAAA==.',
Si='Silvafist:BAAANQAECgEJAwAAAA==.',
Sk='Skreezy:BAAANQAECgYIBgAAAA==.Skuls:BAAANQADCgIIAgAAAA==.',
Sl='Slashemup:BAAANQAECgcIEgAAAA==.Slayter:BAABNQAECoEZAAIRAAkK1yO7BABbAwARAAkK1yO7BABbAwAAAA==.',
Sm='Smaugor:BAAANQAECgYJEQABNQAECgcJBwADAAAAAA==.',
So='Soju:BAAANQAECgEIAQABNQAECggIHwAHANgfAA==.Soliloquy:BAAANQAECgUIDQAAAA==.Solosith:BAAANQADCggIDwAAAA==.',
Sq='Squishyman:BAAANQAECggIEgAAAA==.Squishypal:BAAANQAECgQIBQABNQAECggIEgADAAAAAA==.',
St='Stare:BAEANQADCgQIBAABNQAECggIFwAIAAYlAA==.Stõrm:BAAANQADCgYIBgABNQAECgcJBwADAAAAAA==.',
Su='Suzsette:BAAANQADCggIIQAAAA==.',
Sw='Swïper:BAAANQABCgQIBAAAAA==.',
Sy='Sylris:BAAANQADCgIIAgAAAA==.Syrelyia:BAAANQAECgEIAQAAAA==.',
Ta='Tardovski:BAAANQAECgQICgAAAA==.',
Te='Telda:BAAANQADCgYICwAAAA==.Teneturadvos:BAAANQAECgEIAQABNQAECgYIBwADAAAAAA==.Terrorwynd:BAAANQAECgEIAQAAAA==.',
Th='Thellaria:BAAANQADCgcICAAAAA==.Thiccterror:BAAANQAECgQIBAAAAA==.Thumpér:BAAANQADCgQIBAAAAA==.',
Ti='Tirgo:BAAANQABCgQJBQAAAA==.',
Tr='Traevel:BAAANQADCgYIBgAAAA==.Treme:BAAANQAECgUICgAAAA==.Troche:BAAANQAECgYIDgAAAA==.Truthfully:BAAANQAECgUICgAAAA==.',
Tt='Ttjpll:BAAANQADCgcIEwAAAA==.',
Tu='Tuckncloak:BAAANQAECgcIBwAAAA==.',
Un='Undeadtoast:BAAANQAECgUIDQABNQAFFAQICAAOAOIaAA==.Unhappytoast:BAACNQAFFIEIAAIOAAQK4hppAwBSAQAOAAQK4hppAwBSAQA1AAQKgR8AAg4ACQpYIx0FADUDAA4ACQpYIx0FADUDAAAA.',
Ur='Uriania:BAAANQADCgIIAgAAAA==.',
Us='Ushioni:BAABNQAECoEfAAIWAAgKPxXCawACAgAWAAgKPxXCawACAgAAAA==.',
Va='Valklemor:BAAANQAECgEIAwAAAA==.Vallorien:BAAANQADCggIIgAAAA==.',
Ve='Velaryn:BAAANQAECgcJBwAAAA==.Vengeânce:BAAANQADCgYICwAAAA==.Verenoth:BAAANQAECgIIBAAAAA==.',
Vi='Viveca:BAAANQAECgUIDAAAAA==.Viztrix:BAAANQABCgIIAgAAAA==.',
['Và']='Vàli:BAAANQADCgYIDAAAAA==.',
Wh='Whiteparrot:BAAANQADCgQIBAAAAA==.Wholy:BAABNQAECoEXAAIEAAkKBRg/IwCtAgAEAAkKBRg/IwCtAgAAAA==.',
Wo='Woden:BAAANQADCgMIBQABNQAECgEIAQADAAAAAA==.',
Xa='Xaanii:BAAANQADCgcIIAAAAA==.Xarferrin:BAAANQADCgEIAQAAAA==.',
Xe='Xeeria:BAABNQAECoEaAAMZAAkKexsIGwDRAgAZAAkKexsIGwDRAgASAAMKgxjkrwDcAAAAAA==.Xenzull:BAAANQADCgEIAQAAAA==.',
Xu='Xuecat:BAAANQADCggIEQAAAA==.Xuefeiyan:BAAANQAECgUIBwAAAA==.',
Za='Zaralina:BAAANQAECgUIDgAAAA==.Zarithra:BAAANQAECgEIAQAAAA==.Zarynth:BAAANQADCgQIBwAAAA==.Zaryssa:BAAANQAECgQIBwAAAA==.',
Ze='Zenzug:BAAANQADCgUIBQAAAA==.',
Zh='Zharazi:BAAANQABCgQIBAABNQADCggJEQADAAAAAA==.Zharfrost:BAAANQADCgUICQAAAA==.Zhieri:BAAANQADCgUICAAAAA==.',
Zm='Zmaj:BAAANQABCgIIAgAAAA==.',
Zo='Zombiehunter:BAAANQAECgYIEAAAAA==.Zomboy:BAAANQADCgMIAwAAAA==.Zornqueff:BAAANQADCggICAAAAA==.Zortax:BAAANQAECgQICQAAAA==.',
Zu='Zu:BAAANQAECgEIAQAAAA==.Zug:BAAANQAECgYIEAAAAA==.',
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
