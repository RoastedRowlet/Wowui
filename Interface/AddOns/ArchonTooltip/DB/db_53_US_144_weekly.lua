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

local lookup = {'Shaman-Restoration','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Balance','Unknown-Unknown','Hunter-Survival','Hunter-Marksmanship','Warrior-Fury','Druid-Restoration','Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','Hunter-BeastMastery','Rogue-Subtlety','Priest-Discipline','Priest-Holy','DeathKnight-Unholy','Rogue-Assassination','Paladin-Holy','Evoker-Augmentation','Monk-Windwalker','Evoker-Devastation','Monk-Brewmaster','DeathKnight-Frost','Priest-Shadow','Warlock-Destruction','Shaman-Elemental','DeathKnight-Blood','Evoker-Preservation',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Account:BAAANQABCgQIBAAAAA==.',
Ag='Agnithor:BAABNQAECoEhAAIBAAgKgBnDNgBdAgABAAgKgBnDNgBdAgAAAA==.',
Al='Aliadra:BAABNQAECoEZAAICAAgKMCE7RgDoAgACAAgKMCE7RgDoAgAAAA==.Alistor:BAAANQADCggICAAAAA==.Alistus:BAABNQAECoEuAAMDAAkKNiNeDgAbAwADAAgK3SJeDgAbAwAEAAcKryBEHgBCAgAAAA==.Alphá:BAAANQADCgcICAABNQAECgcIIAABAHoWAA==.',
Am='Amyliz:BAAANQABCgcJBwAAAA==.',
An='Angua:BAABNQAECoEZAAIFAAcK3xEYRQCwAQAFAAcK3xEYRQCwAQAAAA==.Anotheralt:BAAANQAFFAEIAQAAAA==.',
Au='Aurius:BAAANQAECgIIAwAAAA==.',
Av='Aveliandis:BAAANQAECgUIBgAAAA==.',
Az='Azerphage:BAAANQAECgQICAABNQAECgQICwAGAAAAAA==.Azhorra:BAAANQADCgQIBwAAAA==.Azzog:BAAANQADCgcICAABNQAECgQIBgAGAAAAAA==.Azül:BAAANQAECgQICwAAAA==.',
Ba='Bacchanalian:BAAANQAECgEIAQABNQAECgUIDwAGAAAAAA==.Baelrin:BAAANQAECgYIDwAAAA==.Baindyn:BAAANQADCgYIHAAAAA==.Barator:BAAANQADCggIHAAAAA==.',
Be='Beaum:BAABNQAECoEqAAICAAkK/iU8BADUAwACAAkK/iU8BADUAwAAAA==.',
Bl='Blackröse:BAABNQAECoEdAAMHAAkKjQy7BgD3AQAHAAkKhQy7BgD3AQAIAAcKawXtPQAzAQAAAA==.Bladebane:BAAANQAECgUIDAAAAA==.Blksunshine:BAAANQADCggIFgAAAA==.',
Bo='Bolash:BAABNQAECoEgAAIJAAcKIBx1BwBWAgAJAAcKIBx1BwBWAgAAAA==.Bovinelover:BAABNQAECoEdAAIKAAkK1SKAAgCaAwAKAAkK1SKAAgCaAwAAAA==.',
Br='Bradthomas:BAAANQAECgUIBgAAAA==.Braindead:BAAANQAECgQIBAABNQAECgQICwAGAAAAAA==.Bruscha:BAAANQADCggIDAAAAA==.',
Bu='Bulvhine:BAAANQAECgMIBgAAAA==.',
Ca='Cactusteeth:BAAANQAECgIIBAAAAA==.Cafeconpan:BAAANQAECgQICQAAAA==.Camford:BAAANQAECgEIAQAAAA==.Cantatrix:BAAANQADCggIGAAAAA==.Capslok:BAAANQAECgQIBAAAAA==.Captinmeat:BAAANQAECgMIAwAAAA==.Castus:BAAANQAECgQIBgAAAA==.',
Ce='Cecilx:BAAANQAECgYIEQAAAA==.Censøred:BAAANQAECgUIBgAAAA==.',
Ch='Chimerax:BAABNQAECoEtAAMLAAkKHx8/BQBPAgALAAcK7h8/BQBPAgAMAAcKexxeVgAyAgAAAA==.Chronic:BAAANQADCgYICgAAAA==.Chully:BAABNQAECoEoAAIEAAgK2xxVFACuAgAEAAgK2xxVFACuAgAAAA==.',
Cl='Clairíty:BAAANQAECgUICgAAAA==.Clegg:BAAANQADCgcIBwABNQAECgQICwAGAAAAAA==.Click:BAAANQAECgYIDAAAAA==.',
Co='Comadore:BAABNQAECoEcAAINAAkK2hPndQASAgANAAkK2hPndQASAgAAAA==.',
Cr='Crankycad:BAAANQADCgcIDgAAAA==.Credan:BAEANQAECggICAAAAA==.',
Da='Daphe:BAAANQAECgUIDQAAAA==.Dardria:BAAANQABCgIIAgAAAA==.Darknesheart:BAAANQADCgUIDQAAAA==.',
De='Deathslead:BAABNQAECoEYAAIOAAgKkhDEZgAcAgAOAAgKkhDEZgAcAgAAAA==.Decrepe:BAABNQAECoEnAAIKAAgKAB2EEQCoAgAKAAgKAB2EEQCoAgAAAA==.Delph:BAABNQAECoEdAAIJAAgKxxvPBQCRAgAJAAgKxxvPBQCRAgAAAA==.Deshal:BAAANQADCgYIHwAAAA==.Dethklock:BAAANQADCgEIAQAAAA==.',
Di='Discostar:BAABNQAECoEdAAMKAAgKNg4LKQClAQAKAAgKNg4LKQClAQAFAAIKbQZFjgBnAAAAAA==.Distill:BAAANQADCgQIBAABNQAFFAcIHwAPAJAkAA==.',
Do='Dominicm:BAAANQAECggICQAAAA==.',
Dr='Drajhar:BAAANQADCgYIBgAAAA==.Draq:BAAANQADCggIHAAAAA==.Druidcam:BAAANQAECgMIBwAAAA==.',
Eb='Ebonhorn:BAAANQADCggIGAAAAA==.',
Ei='Einari:BAABNQAECoEZAAMQAAcKbiQTBACAAgARAAcKeyAULACZAgAQAAYKxSQTBACAAgAAAA==.Einark:BAAANQADCgQIBAAAAA==.',
Ek='Ekiim:BAAANQADCggIFgAAAA==.',
El='Eldamari:BAAANQAECgMIAwAAAA==.',
Em='Emdralaeth:BAAANQADCgMIAwAAAA==.Emeraldfury:BAAANQADCgUIBQAAAA==.',
Er='Eridor:BAAANQAECgUIBgAAAA==.',
Es='Esbernia:BAAANQAECgUICQAAAA==.Eshul:BAAANQADCgUIBQABNQAECgYIDAAGAAAAAA==.',
Et='Ettne:BAAANQADCgYIBQAAAA==.',
Ex='Exek:BAAANQAECgYIEQAAAA==.',
Fa='Fabaztard:BAAANQAECgYIDAAAAA==.Faline:BAAANQAECgYIDwAAAA==.',
Fe='Felgetabouit:BAABNQAECoEiAAIEAAkKiByrFQCeAgAEAAkKiByrFQCeAgAAAA==.Feort:BAAANQABCgIIAgAAAA==.Ferlane:BAAANQADCgQIBAAAAA==.Feywynn:BAAANQADCgYIBgAAAA==.',
Fi='Fidelity:BAAANQABCgIIAgAAAA==.Fights:BAAANQAECgUIDQAAAA==.Filintos:BAAANQADCgMIAwAAAA==.',
Fl='Fleshworker:BAAANQADCgYIBgABNQAECggIKwAEALYkAA==.',
Fo='Fontaine:BAAANQADCgUICAAAAA==.Foradin:BAAANQAECgUIDgAAAA==.Forky:BAAANQAECgEIBQAAAA==.Forloss:BAAANQADCgYIBgAAAA==.Foxknight:BAAANQADCgYIFwABNQADCgcIBwAGAAAAAA==.',
Fr='Franksnbeans:BAAANQAECgIIAgAAAA==.Fryeren:BAAANQADCggIBwAAAA==.',
Ft='Ftx:BAAANQAECgQICwAAAA==.',
['Fí']='Fírefox:BAAANQADCgcIBwAAAA==.',
Ga='Gaern:BAABNQAECoEfAAISAAkKABrGLQBYAgASAAkKABrGLQBYAgAAAA==.Gaidan:BAAANQAECgYICgABNQAFFAQIBwAEAJUGAA==.Gaidin:BAACNQAFFIEHAAIEAAQKlQYWCgD7AAAEAAQKlQYWCgD7AAA1AAQKgR0AAgQACQqZGbQVAJ4CAAQACQqZGbQVAJ4CAAAA.Gameslayer:BAAANQAECgUIBgAAAA==.Gankzilla:BAABNQAECoEjAAITAAkKHBg3GACTAgATAAkKHBg3GACTAgAAAA==.',
Gi='Gila:BAAANQADCgcICAAAAA==.Gizzle:BAABNQAECoEhAAINAAkK4xQTbAArAgANAAkK4xQTbAArAgAAAA==.',
Gn='Gnarleywine:BAAANQABCgIIAgAAAA==.',
Gr='Greel:BAAANQABCgEIAQAAAA==.Grimanack:BAAANQADCggIEQAAAA==.Grændal:BAAANQAECgMIBAABNQAFFAQIBwAEAJUGAA==.Grÿm:BAAANQADCgYIBwAAAA==.',
Ha='Hanjha:BAAANQAECgYICwAAAA==.',
He='Helldozer:BAAANQAECgYIDAAAAA==.Hexinu:BAAANQAECgYIDAAAAA==.',
Hi='Hiyue:BAAANQAECggIBQAAAA==.',
Ho='Holeinheart:BAAANQADCgMIAwAAAA==.',
Hu='Hugzy:BAAANQADCgcIEQAAAA==.',
Hy='Hypnocide:BAEANQAECgYIEgAAAA==.',
Ib='Ibuki:BAAANQAECgIIAgABNQAECgkJIgAUAHoFAA==.',
Ig='Iguanajon:BAAANQAECgYIEwAAAA==.',
Il='Illandren:BAAANQAFFAEIAQAAAA==.',
Im='Impsane:BAAANQADCgcIDwAAAA==.',
Ir='Irv:BAAANQAECgYIDQAAAA==.',
Is='Isellrocks:BAAANQAECgYICAAAAA==.',
Ja='Jaxxa:BAAANQAECgYICQAAAA==.',
Je='Jeddiah:BAAANQAECgQICAAAAA==.Jetstorm:BAAANQAECgYIBgAAAA==.',
Ji='Jinkès:BAAANQAECgIIBAAAAA==.',
Ju='Juanting:BAAANQADCgEIAgAAAA==.Jubei:BAABNQAECoEZAAINAAcKvx4FdQAUAgANAAcKvx4FdQAUAgAAAA==.Judis:BAABNQAECoEYAAITAAcKIxc+KwAJAgATAAcKIxc+KwAJAgAAAA==.Justokevoker:BAABNQAECoEoAAIVAAgKuhyDBACfAgAVAAgKuhyDBACfAgAAAA==.',
Ka='Kainda:BAAANQADCgIIAgAAAA==.Kairì:BAAANQAECgYICgAAAA==.Kalifist:BAABNQAECoEkAAIWAAkKhx1NDgDfAgAWAAkKhx1NDgDfAgAAAA==.Kalku:BAAANQAECgQIBAAAAA==.Kanajotoma:BAAANQADCggIGQAAAA==.Karlai:BAAANQAECgUIDAABNQAFFAQIBwAEAJUGAA==.Kayle:BAAANQAECgQIBAABNQAECgkJIgAUAHoFAA==.',
Ke='Keldrune:BAAANQADCggICAAAAA==.Keleena:BAEBNQAECoEZAAIUAAcKnhhHTwAOAgAUAAcKnhhHTwAOAgAAAA==.Keze:BAABNQAECoEoAAIOAAgKqB5TNQCpAgAOAAgKqB5TNQCpAgAAAA==.',
Kh='Khorahlia:BAAANQADCgQIBAABNQAECgkJHwASAAAaAA==.',
Ki='Kielir:BAAANQABCgcIDQAAAA==.Killzshot:BAAANQADCgQIBAAAAA==.Kinst:BAAANQAECgYIEwAAAA==.Kitanyia:BAABNQAECoEZAAIJAAgKQhCJCwDmAQAJAAgKQhCJCwDmAQAAAA==.Kittiy:BAAANQAECgEIAQAAAA==.Kizahnevo:BAAANQAECgIIBAAAAA==.',
Ko='Kordelia:BAAANQAECgYIDgABNQAECgkJHwASAAAaAA==.',
Kr='Krench:BAAANQADCgQIBAAAAA==.Krusty:BAAANQADCgYIBgAAAA==.',
Ku='Kuiper:BAAANQABCgEIAQAAAA==.',
Ky='Kyakuna:BAAANQADCgQIBAAAAA==.Kyloon:BAABNQAECoEVAAMQAAgKZgTRGgB0AAARAAcKhwP2kAAoAQAQAAMKtwTRGgB0AAAAAA==.Kyrah:BAAANQAECgYIEwAAAA==.',
La='Lakatryna:BAAANQAECgUJBQABNQAFFAYIEAAIAPoYAA==.Lamanira:BAAANQADCggIFgAAAA==.',
Le='Lejend:BAAANQAECgUIEgAAAA==.',
Li='Lithis:BAAANQAECgEIAQAAAA==.',
Ll='Llamakiller:BAAANQADCgMIAwABNQADCgUICwAGAAAAAA==.Llanedh:BAAANQAECgIIAgAAAA==.',
Lo='Loaganic:BAAANQADCggICAAAAA==.Lonelyhearts:BAAANQAECgQIBgAAAA==.Lorimuni:BAAANQADCggIFAAAAA==.',
Ly='Lytol:BAAANQAECgYIBwAAAA==.',
Ma='Maenad:BAAANQAECgUIDwAAAA==.Maeple:BAAANQAECgUICgAAAA==.Manamontana:BAAANQAECgQIBQAAAA==.Mazikeene:BAAANQADCgYIBgAAAA==.',
Me='Meladyn:BAACNQAFFIEJAAIFAAUKEBsFCgCjAQAFAAUKEBsFCgCjAQA1AAQKgScAAgUACQqNJF4DAL8DAAUACQqNJF4DAL8DAAAA.Mentock:BAAANQABCgUICAAAAA==.',
Mi='Miami:BAACNQAFFIEWAAIXAAcKdxnvAABaAgAXAAcKdxnvAABaAgA1AAQKgSAAAhcACQrRJEICAIkDABcACQrRJEICAIkDAAAA.Michelle:BAAANQADCgEIAQAAAA==.Missmaam:BAAANQAECgQIBgAAAA==.Mistroot:BAAANQADCgcICgAAAA==.Mizu:BAAANQADCgUIBQAAAA==.',
Mo='Monkfox:BAACNQAFFIEIAAIYAAUKHRr5AQC7AQAYAAUKHRr5AQC7AQA1AAQKgSAAAhgACQp4Ij0EACADABgACQp4Ij0EACADAAE1AAQKCAgoABgAySMA.Moon:BAAANQADCgUIBQAAAA==.Moonfirespam:BAAANQADCggICAAAAA==.',
Mu='Mushuwoonter:BAAANQAECgQIBAABNQAECgkJIQAVAM8VAA==.Muvok:BAAANQAECgEIAQAAAA==.Muztang:BAAANQAECgUICgAAAA==.',
My='Mythhunter:BAAANQAECgEIAQAAAA==.',
['Mô']='Mônkii:BAABNQAECoEoAAIYAAgKySM5BAAgAwAYAAgKySM5BAAgAwAAAA==.',
Na='Nace:BAAANQABCgIIAgAAAA==.Naenia:BAAANQAECgQIBgAAAA==.Nariar:BAAANQADCggICQABNQAECgkJIgAUAHoFAA==.Nateldin:BAAANQAECgYIDQAAAA==.',
Ne='Nepe:BAAANQAECgEIAQAAAA==.',
Ni='Nightcat:BAAANQADCgUICQAAAA==.Niisha:BAAANQAECgYIDQABNQAECggIIQARAL8QAA==.',
No='Nocainus:BAAANQAECgYIDAAAAA==.',
['Nø']='Nøtsure:BAAANQAECgIIBAABNQAECgUIBgAGAAAAAA==.',
Ob='Obsidia:BAAANQAECgYIDAAAAA==.',
Od='Oddlife:BAABNQAECoEYAAMSAAYKVSBYOQAZAgASAAYK9R9YOQAZAgAZAAIKzAxvhABZAAAAAA==.',
Oh='Ohsnapkatt:BAAANQADCgUJBQAAAA==.',
Ol='Oled:BAAANQADCgUIBQAAAA==.',
Om='Omari:BAAANQADCggICAAAAA==.',
On='Onceathief:BAAANQADCgQJBAAAAA==.Onik:BAAANQADCgIIAwABNQADCgUICwAGAAAAAA==.',
Op='Ophj:BAABNQAECoEnAAICAAkKgR2dWgC4AgACAAkKgR2dWgC4AgAAAA==.',
Or='Orangejulius:BAAANQADCgYICwABNQADCggIFgAGAAAAAA==.Orangutan:BAAANQAECgMIBQAAAA==.Orinoheal:BAAANQADCgYICAAAAA==.',
Os='Oskar:BAABNQAECoEgAAIBAAkKIBWXRgAcAgABAAkKIBWXRgAcAgAAAA==.',
Pa='Pallycam:BAAANQAECgIIAgAAAA==.',
Pe='Pebda:BAAANQADCgYIFwAAAA==.Pebde:BAAANQAECgMIAwAAAA==.Pendor:BAAANQABCgQIBgAAAA==.Perilous:BAAANQADCggIGgAAAA==.',
Ph='Phoelar:BAAANQAECgUICwAAAA==.Phuumyn:BAAANQAECgYIDAAAAA==.',
Pi='Piccoblast:BAACNQAFFIETAAICAAYKRRN7CwD+AQACAAYKRRN7CwD+AQA1AAQKgSUAAgIACQr8JN4fAFEDAAIACQr8JN4fAFEDAAAA.Pichus:BAAANQAECgQIBAABNQAECgcIIAABAHoWAA==.Picklesoup:BAAANQAECgIIAgAAAA==.Piickles:BAACNQAFFIEGAAMRAAIKcA5sIgCcAAARAAIKcA5sIgCcAAAaAAIKIgSDEQCBAAA1AAQKgRoAAxEACQq1E+5YAOgBABEABwrEGO5YAOgBABoACArHC9QtAI4BAAAA.Pippopper:BAAANQAECgIIAgABNQAECgkJLgADADYjAA==.Pity:BAAANQAECgUIBwAAAA==.',
Pl='Plutø:BAAANQAECgUICAAAAA==.',
Po='Polylocks:BAAANQAECgIIAgAAAA==.Potatogg:BAAANQAECgEIBAAAAA==.',
Pr='Praeastra:BAEBNQAECoEbAAICAAkKYAnpwQDcAQACAAkKYAnpwQDcAQAAAA==.Prókill:BAAANQAECgUICgAAAA==.',
Ps='Psychokitty:BAABNQAECoEbAAIKAAYK5RX2LAB+AQAKAAYK5RX2LAB+AQAAAA==.',
Qu='Quilian:BAABNQAECoEhAAIRAAkK+CHyCgBZAwARAAkK+CHyCgBZAwAAAA==.',
Ra='Raelynn:BAAANQAECgYIDAAAAA==.Rancier:BAAANQADCggIHAAAAA==.Rashalisk:BAAANQADCgUIBQAAAA==.',
Re='Rednecker:BAAANQABCgIIAgAAAA==.Redvex:BAABNQAECoEoAAMMAAgKjiOSEgAwAwAMAAgKjiOSEgAwAwAbAAEKRyNhYgBUAAAAAA==.Reinhard:BAAANQAECgUICwAAAA==.Relani:BAAANQAECggICAAAAA==.Rencraw:BAAANQADCggIGAAAAA==.Renras:BAAANQADCggJEwAAAA==.',
Rh='Rhain:BAAANQAECgYICgAAAA==.Rhexy:BAAANQAECgYIBgAAAA==.Rhuxy:BAAANQAECgEIAQAAAA==.',
Ri='Rinah:BAABNQAECoElAAMPAAkKDRqOCgC+AgAPAAkKDRqOCgC+AgATAAIK9Q34dwB3AAAAAA==.',
Ro='Ronwen:BAAANQADCgUIBQABNQAECgkJIgAUAHoFAA==.Rootbeard:BAAANQAECgUJBgAAAA==.Rosanna:BAAANQADCgcIGQAAAA==.Rotyr:BAAANQAECgUICQAAAA==.',
Ru='Ruana:BAEANQADCggIHQAAAA==.Rubberlip:BAAANQAECgQJBAAAAA==.',
Ry='Rye:BAABNQAECoEkAAMQAAcKyh4wBAB5AgAQAAcKyh4wBAB5AgARAAYK/xGregBxAQAAAA==.',
Sa='Santhela:BAAANQADCgIIAgAAAA==.Sarahbera:BAAANQABCgIIAgAAAA==.',
Sc='Scoobey:BAAANQAECgIIBAAAAA==.Scots:BAAANQADCggIEAAAAA==.Scubbs:BAABNQAECoEgAAIBAAgKkBtANwBbAgABAAgKkBtANwBbAgAAAA==.Scubbsboo:BAAANQADCggICQABNQAECggIIAABAJAbAA==.',
Se='Selenei:BAAANQADCgEIAQAAAA==.Servantes:BAAANQAECgYICwAAAA==.',
Sh='Shamancam:BAAANQAECgMIBAAAAA==.Shammyhagar:BAAANQADCgQIBAAAAA==.Shamp:BAAANQAECgIIAgAAAA==.Shiggy:BAAANQAECgYIEAABNQAECggIIgANAPsYAA==.Shotya:BAAANQAECgUIBwAAAA==.',
Si='Sixthdemon:BAAANQADCgUIBQAAAA==.Sixthknight:BAAANQAECgQIBwAAAA==.',
Sl='Slappi:BAAANQAECgUICAAAAA==.',
Sn='Snarkypony:BAAANQADCggIGwAAAA==.',
So='Sonofathorck:BAAANQADCgEIAQAAAA==.Sorsere:BAAANQAECgEIAQAAAA==.',
Sp='Spcecialk:BAAANQADCggICQAAAA==.Specialk:BAABNQAECoEiAAIcAAgK8RR6SQAkAgAcAAgK8RR6SQAkAgAAAA==.Spellthat:BAAANQAFFAEIAQAAAA==.',
St='Stirredihime:BAAANQAECgUICAAAAA==.Stormmage:BAAANQAECgMIAwABNQAECgkJJQAdACgiAA==.',
Su='Sugarmomma:BAAANQADCgcIBwAAAA==.Sulph:BAAANQAECgYIDAAAAA==.Sundorei:BAAANQADCgcIDwAAAA==.',
Sv='Svalir:BAAANQADCgUICwAAAA==.',
Ta='Talshekar:BAAANQAECgUIBwAAAA==.Tarsis:BAAANQAECgUICAAAAA==.',
Te='Teiana:BAABNQAECoEkAAINAAkKfCBOIwAeAwANAAkKfCBOIwAeAwAAAA==.',
Th='Thaevin:BAAANQAECgYIDgAAAA==.Thews:BAAANQABCgEIAQAAAA==.Thilendrel:BAABNQAECoEdAAMaAAkKxxyJEwCtAgAaAAkKxxyJEwCtAgARAAMKNg4OwwCYAAAAAA==.Thingwan:BAABNQAECoErAAIKAAkKUCBhBgBKAwAKAAkKUCBhBgBKAwAAAA==.Thunderman:BAAANQAECgQIEgAAAA==.',
Ti='Tinyakromajr:BAAANQAECgIIAgABNQAECgUIDQAGAAAAAA==.Tinystink:BAAANQAECgUIDQAAAA==.',
To='Toddstephens:BAAANQADCgcICwAAAA==.Tors:BAABNQAECoEoAAMFAAgK/BJCOAADAgAFAAgK/BJCOAADAgAKAAIK3ASTXABdAAAAAA==.Totemdweller:BAAANQABCgUICwAAAA==.Toterbonem:BAAANQADCgMIAwAAAA==.Toyotathon:BAAANQADCgYIBgABNQADCggIFgAGAAAAAA==.',
Tr='Trasky:BAAANQAECgYIEQAAAA==.Trollololo:BAAANQAECgYIDAAAAA==.Troy:BAABNQAECoEXAAICAAcKJAuK4wCbAQACAAcKJAuK4wCbAQAAAA==.Trylly:BAAANQADCgcIBwABNQAECgIIAgAGAAAAAA==.Trëze:BAABNQAECoEgAAMOAAkKfRvJJwDaAgAOAAkKfRvJJwDaAgAIAAUKWwffUAC8AAAAAA==.',
Tt='Ttaartt:BAACNQAFFIEGAAIeAAIKDRNQEQCWAAAeAAIKDRNQEQCWAAA1AAQKgRwAAh4ACQqBD30XACoCAB4ACQqBD30XACoCAAAA.',
Ty='Typh:BAABNQAECoEqAAITAAkKZCNfBAB9AwATAAkKZCNfBAB9AwAAAA==.',
Un='Undeaddemon:BAABNQAECoEVAAMMAAgKgBeCXwAXAgAMAAgKdheCXwAXAgAbAAIK4RgtUQCAAAAAAA==.Undeaddh:BAAANQADCggICAABNQAECggIFQAMAIAXAA==.Undeadscaly:BAAANQAECgYICAABNQAECggIFQAMAIAXAA==.Undignified:BAAANQAECgYIEQAAAA==.Unholysixth:BAAANQADCgcIGgAAAA==.',
Va='Vanidarr:BAAANQADCgQIBAAAAA==.',
Ve='Verasia:BAAANQADCggIEQAAAA==.',
Vi='Vidikan:BAAANQADCgIIAwAAAA==.Violett:BAABNQAECoEcAAIWAAkKsBsSEADIAgAWAAkKsBsSEADIAgAAAA==.',
Vo='Voidwarranty:BAABNQAECoEgAAMBAAcKehYsXgDFAQABAAcKehYsXgDFAQAcAAUKSBfClABAAQAAAA==.Vortre:BAAANQABCgcIBwAAAA==.',
Vv='Vvumpscut:BAABNQAECoEcAAIBAAcK3hfwVwDbAQABAAcK3hfwVwDbAQAAAA==.',
Wa='Waldón:BAAANQAECgUIDAAAAA==.',
Wi='Wildsoul:BAAANQAECgEIAQAAAA==.Wistywind:BAAANQABCggJCwAAAA==.',
Xc='Xclaw:BAAANQAECgQJBAAAAA==.',
Xe='Xeroxgravity:BAAANQAECgMIAwAAAA==.Xeroxshaman:BAAANQADCgQJAgAAAA==.',
Xi='Xilphira:BAAANQADCgYIFAAAAA==.Xirian:BAAANQAECgQIBwAAAA==.',
Xl='Xlithz:BAAANQAECgYIDwAAAA==.',
Ya='Yah:BAAANQADCgQIBwAAAA==.Yautjah:BAAANQADCgUIBQAAAA==.',
Yl='Ylene:BAAANQADCgUICgAAAA==.',
Yo='Yoink:BAABNQAECoEjAAISAAkK1CESCwBPAwASAAkK1CESCwBPAwAAAA==.Yondu:BAAANQADCgcICQABNQAECgUICgAGAAAAAA==.',
Za='Zalzuke:BAAANQAECgEJAQAAAA==.Zarinchaos:BAAANQAECgYIEgAAAA==.Zavis:BAAANQADCggICwAAAA==.',
Ze='Zein:BAAANQADCggIHAAAAA==.Zente:BAABNQAECoEfAAIOAAgKlhBJZwAaAgAOAAgKlhBJZwAaAgAAAA==.Zequill:BAAANQAECgUIEgAAAA==.Zevfury:BAAANQAECgEIAQABNQAECgkJIgAOABwgAA==.Zevsticles:BAABNQAECoEiAAIOAAkKHCCKGAAfAwAOAAkKHCCKGAAfAwAAAA==.',
Zh='Zhom:BAACNQAFFIEQAAIIAAYK+hgLBQDsAQAIAAYK+hgLBQDsAQA1AAQKgSoAAggACQqtItwKABkDAAgACQqtItwKABkDAAAA.',
Zo='Zooj:BAAANQAECgYIBwAAAA==.Zorlak:BAAANQAECgEIAgAAAA==.',
Zu='Zulall:BAAANQADCggIDgAAAA==.',
Zy='Zylofeather:BAAANQADCgUIBQAAAA==.',
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
