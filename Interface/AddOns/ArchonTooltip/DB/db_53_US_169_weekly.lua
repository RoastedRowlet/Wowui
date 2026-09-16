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

local lookup = {'Mage-Arcane','Mage-Frost','Unknown-Unknown','Paladin-Holy','Druid-Balance','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Priest-Shadow','Druid-Restoration','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','Druid-Guardian','Warrior-Protection','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Blood',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aairidari:BAAANQAECgQICQAAAA==.',
Ab='Abruna:BAAANQAECgMIAwABNQAECgkJHwABADohAA==.Abruno:BAABNQAECoEfAAMBAAkJOiFaFQBJAwABAAkJZCBaFQBJAwACAAEJXB3SIABNAAAAAA==.Abruto:BAAANQADCgIIAQABNQAECgkJHwABADohAA==.',
Ae='Aeown:BAAANQADCgcIEwABNQAECgYIDQADAAAAAA==.Aerdis:BAAANQADCgcIFAABNQAECgMIAwADAAAAAA==.',
Ah='Aharuka:BAAANQADCgEIAQAAAA==.',
Al='Alandrìas:BAAANQAECgUICwAAAA==.Altera:BAAANQAECgMIBAAAAA==.',
An='Andelarenn:BAAANQABCgIIAgAAAA==.Andere:BAAANQAECgQIBAAAAA==.Androonatorz:BAABNQAECoEeAAIEAAkJUyC4BgBQAwAEAAkJUyC4BgBQAwAAAA==.Anfernay:BAAANQAECgYICgAAAA==.Antiaxxis:BAAANQADCgEIAQAAAA==.',
Ap='Apawthetic:BAAANQAECgMIAwABNQAECgkJHQAFAOwbAA==.',
Ar='Arcanodare:BAAANQADCggICAAAAA==.Artemisled:BAAANQAECgUIDQAAAA==.Arveiturace:BAAANQADCgcIFgAAAA==.',
As='Ashborrn:BAAANQADCgUIBQAAAA==.Ashtar:BAAANQAECgUICwAAAA==.',
At='Attack:BAAANQAECgEIAwAAAA==.',
Ax='Axhure:BAAANQABCgMIAgAAAA==.',
Ba='Babydoll:BAAANQAECgQICAAAAA==.Bajablast:BAAANQADCgcIDQAAAA==.Barma:BAAANQAECgMIAwAAAA==.',
Be='Beltirra:BAAANQADCgYIEQAAAA==.',
Bh='Bhangbros:BAAANQADCgcIBwAAAA==.',
Bi='Bigmobility:BAAANQAECgYICwAAAA==.Bigwill:BAAANQAECgYIDwAAAA==.',
Bl='Blargy:BAAANQAECgYIDwAAAA==.Bleach:BAAANQADCgcICAAAAA==.',
Bo='Borealslam:BAAANQADCgQIBAAAAA==.Bouzol:BAAANQAECgYIBgAAAA==.',
Br='Brimara:BAAANQAECgQIBwAAAA==.',
Bu='Bucketojoy:BAAANQAECgIIBAAAAA==.',
['Bà']='Bàtman:BAAANQADCgUIBQAAAA==.',
Ca='Caliburne:BAAANQAECgYIDQAAAA==.Capz:BAACNQAFFIENAAIGAAYJIh2FAQBGAgAGAAYJIh2FAQBGAgA1AAQKgRcAAgYACQkcJSQNAF8DAAYACQkcJSQNAF8DAAAA.',
Ce='Cedrin:BAAANQADCgUICAAAAA==.Ceez:BAAANQADCgcIDQAAAA==.',
Ch='Chickenstwip:BAAANQADCgEIAgABNQAECgYIDwADAAAAAA==.Chosenöne:BAAANQADCgEIAQAAAA==.Chèn:BAAANQAECgMIBQAAAA==.',
Ci='Cindrella:BAAANQAECgYIDwAAAA==.',
Cl='Clayre:BAABNQAECoEaAAIHAAgJJRwvBADEAgAHAAgJJRwvBADEAgAAAA==.Clow:BAAANQAECgIIBAAAAA==.',
Co='Colossus:BAAANQADCgQIBAAAAA==.Coolcrush:BAAANQADCgMIBgABNQAECgUICgADAAAAAA==.Corven:BAABNQAECoEfAAMIAAkJsiD8AwBtAwAIAAkJsiD8AwBtAwAHAAEJRQVDZAApAAAAAA==.',
Cr='Critzwar:BAABNQAECoEbAAIGAAkJPyDLDgBRAwAGAAkJPyDLDgBRAwAAAA==.Crönus:BAAANQADCggIDwAAAA==.',
Ct='Cthuluwu:BAAANQADCggICAAAAA==.',
Da='Daedyxes:BAAANQAECgQIBQAAAA==.Daní:BAAANQADCgUIBgABNQADCgUICAADAAAAAA==.Darkensi:BAAANQABCgYICQAAAA==.Dasherdeez:BAAANQADCgQIBQAAAA==.Daygath:BAAANQAECgEIAQAAAA==.',
De='Deadlyiris:BAAANQAECgYIDwAAAA==.Deadshot:BAAANQADCgMIAwAAAA==.Deatharin:BAAANQADCgUIBgAAAA==.Deathjak:BAAANQADCggIDQABNQAECgUIDQADAAAAAA==.Demonbulio:BAAANQAECgEIAQAAAA==.Demonisthicc:BAAANQAECgYIDwAAAA==.Demonslayeer:BAAANQADCgUIBQAAAA==.Devi:BAAANQAECgQIBQAAAA==.',
Di='Diaravynn:BAAANQADCgIIAgAAAA==.Dithehealer:BAAANQAECgQIBgAAAA==.Divain:BAAANQADCgQIBgAAAA==.',
Dk='Dkdi:BAAANQADCggIEAAAAA==.',
Do='Dozekar:BAAANQAECgEIAQAAAA==.',
Dr='Drenamai:BAAANQAECgEIAQAAAA==.',
Du='Duhmptruhk:BAAANQAECgcICQAAAA==.Dunbroch:BAACNQAFFIEFAAIJAAMJrwuOCADaAAAJAAMJrwuOCADaAAA1AAQKgSAAAgkACQmfGWcOAKICAAkACQmfGWcOAKICAAAA.Duskforge:BAAANQABCgIIAgAAAA==.',
['Dé']='Démonicblood:BAAANQAECgcIEQAAAA==.',
Eg='Eggplantgodx:BAAANQAECgYICwAAAA==.',
Ek='Ekhart:BAAANQADCggIEgAAAA==.',
El='Elfajah:BAAANQADCgYICQAAAA==.Eliicia:BAABNQAECoEeAAMKAAkJrhqkBQAJAwAKAAkJrhqkBQAJAwALAAgJ+w0oEQAdAgAAAA==.',
Em='Emmy:BAAANQAECgQIDQAAAA==.Emofineshyt:BAAANQADCgcICgAAAA==.Emogothbabe:BAAANQAECgYIDwAAAA==.Emowrecky:BAAANQAECgQIBgAAAA==.',
En='Endo:BAABNQAECoEfAAMMAAkJLiS0DAAFAwAMAAgJAiO0DAAFAwANAAcJnyBeDACNAgAAAA==.Endorush:BAAANQAECgMIAwABNQAECgkJHwAMAC4kAA==.Eneldenes:BAAANQAECgEIAgAAAA==.Enjoyer:BAAANQAECgMIAwAAAA==.',
Er='Ereitherla:BAAANQAECgMIAwAAAA==.',
Es='Esmenet:BAAANQAECgUIBQAAAA==.Espressð:BAAANQAECgEIAQABNQAECgYIDwADAAAAAA==.',
Ex='Excalibear:BAAANQAECgMIBAABNQAECgkJGQAOALIbAA==.',
Ey='Eydis:BAAANQADCgIIAgAAAA==.',
Fe='Feironor:BAAANQADCgQIBgAAAA==.Fenrys:BAAANQADCgcICwAAAA==.',
Fi='Fikareous:BAAANQADCgUIBQABNQAECgUIBQADAAAAAA==.',
Fl='Flayre:BAAANQAECgQICQAAAA==.Fleredil:BAAANQAECgUICwAAAA==.Flingernle:BAAANQAECgUIDAAAAA==.',
Fo='Forepray:BAABNQAECoEdAAIPAAkJ/BlvCAAIAwAPAAkJ/BlvCAAIAwAAAA==.Forger:BAAANQAECgQICAAAAA==.Forsakey:BAAANQADCgYICwABNQAECgkJGwAQAHsfAA==.',
Fr='Fraun:BAAANQADCggIEQAAAA==.',
Fu='Fullyprotpal:BAAANQADCgcICAAAAA==.Furioustotem:BAAANQAECgMIAwAAAA==.Future:BAAANQADCgUIBgABNQAECgkJHgABANwiAA==.',
Ga='Galten:BAAANQABCgUIBQAAAA==.',
Ge='Geekbarr:BAAANQADCgUIBQABNQAECgYIDwADAAAAAA==.',
Gh='Ghettox:BAAANQADCgIIAgAAAA==.Ghostw:BAAANQAECgIIAwAAAA==.',
Go='Golgotterath:BAABNQAECoEZAAIOAAkJshv+GgB/AgAOAAkJshv+GgB/AgAAAA==.Gorm:BAAANQAECgYIBgABNQAECgMIAwADAAAAAA==.',
Gr='Grippyshocks:BAAANQAECgIIAgABNQAECgcIDAADAAAAAA==.',
Ha='Halbruck:BAAANQAECgYIDwAAAA==.Haldane:BAAANQAECgUIDgABNQAECgYIDwADAAAAAA==.Havochunter:BAAANQADCgcIDAAAAA==.',
He='Heidegger:BAAANQADCgYICgAAAA==.Helinndealin:BAABNQAECoEdAAMRAAkJfSSaAABVAwARAAgJNiSaAABVAwASAAgJLSJVFwCKAgAAAA==.Hellin:BAAANQADCgMIAQAAAA==.Heolstor:BAAANQAECgQIBQAAAA==.Hephsdh:BAAANQAECgIIAwAAAA==.Heraois:BAAANQAECgIIAgAAAA==.Heriod:BAAANQABCgEIAQAAAA==.',
Hg='Hgshake:BAAANQADCgYIBgAAAA==.',
Ho='Holytës:BAAANQADCggICAAAAA==.Holywráth:BAAANQADCgQIBgAAAA==.',
Hu='Hunterdh:BAAANQADCggIDwAAAA==.',
Il='Illidope:BAAANQAECgcIDAAAAA==.',
In='Infinitevoid:BAAANQADCgYIBwAAAA==.Innervatez:BAAANQAECgQIBAAAAA==.Inteaus:BAAANQADCggIFgAAAA==.',
Io='Ionúin:BAAANQADCgQIBAAAAA==.',
Iv='Ivÿ:BAAANQADCgIIAgAAAA==.',
Ja='Jaekir:BAAANQAECgMIBAAAAA==.Jakfrost:BAAANQAECgUIDQAAAA==.Jakie:BAAANQADCgYICgABNQAECgUIBwADAAAAAA==.Jarten:BAABNQAECoEbAAINAAgJbhtXDgBqAgANAAgJbhtXDgBqAgAAAA==.Jayaah:BAAANQADCgYIEQAAAA==.Jaylebate:BAAANQADCggIHAAAAA==.',
Je='Jesseatamer:BAABNQAECoEZAAITAAgJuCM+CwAoAwATAAgJuCM+CwAoAwAAAA==.',
Ji='Jitsuru:BAAANQADCgUIBQAAAA==.',
Jo='Jox:BAAANQABCgUIBQAAAA==.Joxor:BAAANQABCgUIBQAAAA==.',
Js='Jstdeath:BAAANQADCgEIAQABNQAECgYIEAADAAAAAA==.Jstrawr:BAAANQAECgYIEAAAAA==.',
Ka='Karen:BAAANQAECgQIBAAAAA==.Kasalu:BAAANQABCgQIBAAAAA==.Kastia:BAAANQADCgUIDgAAAA==.Katrynwel:BAAANQAECgQIBAAAAA==.Katsumi:BAAANQADCgcIEQAAAA==.',
Ke='Keliki:BAAANQAECgYICwAAAA==.Kellenah:BAAANQABCgIIAgAAAA==.Kettama:BAAANQADCggIEAABNQAECgYIDwADAAAAAA==.',
Kh='Khold:BAAANQAECgYICAAAAA==.Khrogann:BAAANQAECgMIBAAAAA==.',
Ki='Killalltoday:BAAANQAECgQIBQAAAA==.Kirkk:BAAANQADCgYIEQAAAA==.',
Kl='Klaminus:BAAANQADCgQIBAAAAA==.',
Kn='Knixx:BAABNQAECoEeAAMSAAkJVCTvAQCbAwASAAkJVCTvAQCbAwARAAYJ8xFLCABhAQAAAA==.Knuppelus:BAAANQADCgYICQAAAA==.',
Ko='Kobyashimaru:BAAANQADCgUIBQAAAA==.Koshi:BAAANQADCgMIAwAAAA==.Kotastrophe:BAAANQAECgMIAwABNQAECgcICQADAAAAAA==.Koveras:BAAANQADCgYIBwAAAA==.Koyaanis:BAAANQADCggIDgAAAA==.Koyya:BAAANQAECgQIBwAAAA==.',
Kr='Krenmonk:BAAANQAECgEIAQAAAA==.Krunchee:BAAANQADCgUICAAAAA==.',
Ku='Kufoo:BAAANQAECgQIBQAAAA==.Kurao:BAAANQAECgEIAQAAAA==.Kurukai:BAAANQADCgIIAgAAAA==.',
Ky='Kyrian:BAABNQAECoEdAAILAAkJlCHFAgBeAwALAAkJlCHFAgBeAwAAAA==.',
La='Lagøless:BAAANQAECggIEAAAAA==.',
Le='Leo:BAAANQADCgYIBgAAAA==.',
Li='Likestoflash:BAEANQADCgYIBgABNQAECgcIDwADAAAAAA==.Lissaris:BAAANQADCgEIAgAAAA==.',
Lo='Lohal:BAAANQAECgYIDgAAAA==.Lohmi:BAAANQAECgQIBgAAAA==.Lormn:BAAANQADCgEIAQAAAA==.',
Lu='Luania:BAAANQADCgUIDgAAAA==.',
Ly='Lyna:BAAANQADCggICAAAAA==.Lyravega:BAAANQADCggICAAAAA==.Lyshkä:BAAANQAECgYIDQAAAA==.Lyzzardkng:BAAANQAECgUICAAAAA==.',
['Lý']='Lýra:BAAANQADCgYIBwAAAA==.',
Ma='Maango:BAAANQAECggICAAAAA==.Maemu:BAAANQABCgUIBQAAAA==.Magerthat:BAAANQADCgQIBgAAAA==.Magicaltickl:BAAANQAECgQIBwAAAA==.Magiki:BAAANQADCgcICwAAAA==.Malkala:BAAANQADCgMIAwAAAA==.Malonormu:BAAANQABCgYIBAAAAA==.Mamadeezy:BAAANQADCgYICgAAAA==.Mando:BAAANQADCgcIDwABNQAECgMIAwADAAAAAA==.Manical:BAAANQADCggIFQAAAA==.Marcel:BAAANQADCgYIEQAAAA==.Mashiach:BAABNQAECoEbAAMSAAkJvx7KDwDNAgASAAkJvx7KDwDNAgAPAAEJXRMRRQA6AAAAAA==.Matthyjsz:BAAANQADCgIIAgAAAA==.',
Me='Megumin:BAAANQADCgYIDQABNQAECgYIDQADAAAAAA==.Melikefire:BAABNQAECoEXAAIBAAcJhxwUYAAnAgABAAcJhxwUYAAnAgAAAA==.Memecompdall:BAAANQADCgUICAAAAA==.Merek:BAAANQAECgQIBQAAAA==.Mettix:BAAANQADCgIIAgAAAA==.',
Mi='Mirigosa:BAAANQADCgQIAwABNQAECgYIDwADAAAAAA==.Mistybdk:BAAANQADCggICAABNQAECgkJHwAUAAIhAA==.Mistyd:BAABNQAECoEfAAIUAAkJAiFTAQBwAwAUAAkJAiFTAQBwAwAAAA==.',
Mo='Mogfooyen:BAAANQABCgQIBgAAAA==.Moonbeam:BAAANQAECgEIAQAAAA==.Morgause:BAAANQAECgEIAQAAAA==.Morllan:BAAANQAECgYICQAAAA==.',
Mu='Muirdin:BAAANQADCgEIAQAAAA==.',
My='Mykinlive:BAAANQADCgIIAgAAAA==.',
['Må']='Mångix:BAAANQADCgcIBwAAAA==.',
Na='Naanomage:BAAANQADCgcIEAAAAA==.Naija:BAAANQADCgIIAgAAAA==.Narcotx:BAAANQADCgIIAgAAAA==.',
Ne='Necrotoxin:BAAANQADCgYIBgAAAA==.',
Ni='Nightmaratic:BAAANQADCgYIBgAAAA==.Nightsdeath:BAAANQAECgEIAQAAAA==.Nightsever:BAAANQAECgYIDQAAAA==.Nirath:BAAANQAECgQIBQAAAA==.',
No='Noiire:BAAANQAECgMIAwABNQAECgkJHgAKAK4aAA==.',
Od='Odysse:BAAANQADCgYICQAAAA==.Odyssé:BAAANQAECgIIAgAAAA==.',
Ok='Okami:BAAANQAECgEIAQAAAA==.',
Oo='Ooyagoddess:BAAANQADCgEIAQAAAA==.',
Or='Orryck:BAAANQADCgQIBQAAAA==.',
Pa='Pacamonk:BAAANQAECgYIDAAAAA==.Papatiny:BAAANQADCgIIAgAAAA==.Pawsa:BAAANQAECgMIAwABNQAECgYIDwADAAAAAA==.Pawthetic:BAABNQAECoEdAAMFAAkJ7BuvDwDxAgAFAAkJ7BuvDwDxAgAQAAMJrRBYLQC3AAAAAA==.',
Pe='Peelforheals:BAABNQAECoEdAAIPAAkJ+htrCQDyAgAPAAkJ+htrCQDyAgAAAA==.Penguindemic:BAAANQAECgQICgAAAA==.Pep:BAAANQAECgMIAwAAAA==.Pepperoni:BAAANQADCggIDQAAAA==.Petruccius:BAABNQAECoEYAAIFAAkJrxeoEgDLAgAFAAkJrxeoEgDLAgAAAA==.Pewpewlepew:BAAANQAECgQIBwAAAA==.',
Ph='Phaeku:BAAANQADCgMIAwAAAA==.',
Pi='Picklebreath:BAAANQADCgUICgAAAA==.Pinksparklez:BAAANQADCgUICAAAAA==.',
Pl='Plague:BAAANQADCgMIAwAAAA==.',
Po='Poptartsz:BAAANQAECgMIBQAAAA==.Potatolockx:BAAANQAECgQIAwAAAA==.',
Pr='Precht:BAAANQADCgYIDgAAAA==.Prikarea:BAAANQAECgUIBQAAAA==.Prumper:BAAANQAECgcICwAAAA==.',
Pu='Purah:BAAANQADCgEIAgAAAA==.',
Qu='Quesoblanco:BAAANQAECgQIBgAAAA==.',
Ra='Rabid:BAAANQADCgMIAwAAAA==.Raghallov:BAAANQAECgIIBAAAAA==.Rampa:BAAANQADCgYIEQABNQAECgYIDwADAAAAAA==.',
Re='Regena:BAAANQAECgYIDQAAAA==.Remorse:BAABNQAECoEfAAIVAAkJQh8OAgA2AwAVAAkJQh8OAgA2AwAAAA==.Rendwick:BAAANQADCgYICQAAAA==.',
Ri='Rim:BAAANQAECgUICAAAAA==.',
Ro='Ronard:BAAANQAECgcIDwAAAA==.Ronfar:BAABNQAECoEeAAIWAAkJUyDkAQBoAwAWAAkJUyDkAQBoAwAAAA==.',
Ru='Rustyglass:BAAANQABCgYIBAAAAA==.Ruttisðir:BAAANQAECgIIAwAAAA==.',
Ry='Ryhorn:BAAANQADCggIDgAAAA==.Ryno:BAAANQADCgUIBwAAAA==.Ryujin:BAAANQAECgQIBgAAAA==.Ryù:BAAANQADCggIFwAAAA==.',
Sa='Saladman:BAAANQADCgQIBAAAAA==.Salo:BAAANQADCgMIBgAAAA==.Sanazenet:BAAANQADCggIDAAAAA==.Saviorself:BAAANQADCgMIAwABNQAECgkJHQAFAOwbAA==.',
Sc='Scarlypop:BAAANQAECgUIDAAAAA==.Scarscar:BAAANQABCgEIAQAAAA==.Schwinn:BAAANQADCgQIBAAAAA==.',
Se='Segarth:BAAANQAECgEIAQAAAA==.Seswatha:BAAANQAECgUIBQABNQAECgkJGQAOALIbAA==.',
Sh='Shamandroo:BAAANQAECgMIAwABNQAECgkJHgAEAFMgAA==.Shanghaied:BAAANQADCgcIDAAAAA==.Shmongus:BAAANQADCgIIAgABNQAECgMIAwADAAAAAA==.Shortandold:BAAANQAECgMIBQAAAA==.Shådowfire:BAAANQAECgEIAQAAAA==.Shìft:BAAANQAECgQICgAAAA==.',
Si='Sintram:BAAANQABCgIIAgAAAA==.',
Sl='Slighted:BAAANQADCgcIFgABNQAECgMIAwADAAAAAA==.Slimydruid:BAAANQADCgYIBgAAAA==.Slow:BAABNQAECoEeAAIBAAkJ3CIGGAA8AwABAAkJ3CIGGAA8AwAAAA==.',
Sm='Smokinontech:BAAANQADCgQIBAABNQAECgYIDwADAAAAAA==.Smokze:BAAANQADCggICAAAAA==.',
So='Sockoh:BAAANQAECgQICAAAAA==.Solera:BAEANQADCggICAAAAA==.Sonicberger:BAAANQADCgYIDQABNQAECgEIAQADAAAAAA==.Soniko:BAAANQAECgMIAwAAAA==.Sonícberger:BAAANQAECgEIAQAAAA==.Soulcaliber:BAAANQADCgQIBAAAAA==.',
St='Stain:BAAANQAECgQIBAAAAA==.Stealth:BAAANQAECgQIBAABNQAECgQIBQADAAAAAA==.Stonehenge:BAAANQAECgQICAABNQAECgYIDwADAAAAAA==.Stonepalm:BAAANQADCgQIBAAAAA==.Stratan:BAAANQADCgIIAgABNQADCgQIBAADAAAAAA==.Strawk:BAAANQAECgMIAwAAAA==.',
Su='Suffer:BAAANQADCggICQABNQAECgkJHgABANwiAA==.Supercat:BAAANQADCgYIBwAAAA==.Surf:BAAANQAECgIIBAAAAA==.',
Sw='Swankydranky:BAABNQAECoEeAAMXAAkJ3RK/DgBRAgAXAAkJoxK/DgBRAgAYAAEJiBT2GwBGAAAAAA==.Swankypally:BAAANQAECgMIAwABNQAECgkJHgAXAN0SAA==.',
Sy='Syesc:BAAANQABCgQIBAAAAA==.Sylandris:BAAANQADCgIIAgAAAA==.',
Ta='Tabbz:BAAANQAECgUICgAAAA==.Tallael:BAAANQAECgUICwAAAA==.Tallyhochick:BAAANQAECgUICwAAAA==.Taman:BAABNQAECoEVAAIOAAgJ0hutGwB6AgAOAAgJ0hutGwB6AgAAAA==.Taylerswift:BAAANQADCgYIBwAAAA==.',
Th='Thebestname:BAAANQAECgQIBgAAAA==.Thebigonion:BAAANQADCgYIEQAAAA==.Theexile:BAAANQAECgYIDQAAAA==.',
Ti='Tinydeath:BAAANQAECgYIDQAAAA==.Tinyfu:BAAANQADCgQIBAAAAA==.Tinytamer:BAAANQAECgYIDAABNQAECgYIDQADAAAAAA==.',
Tm='Tmakrist:BAAANQADCgEIAQAAAA==.',
To='Toko:BAAANQAFFAEIAQAAAA==.',
Tr='Trailblazah:BAAANQAECgIIAgAAAA==.Treeheals:BAAANQADCggICAAAAA==.Truthes:BAAANQADCgYIBwABNQAECgQIBQADAAAAAA==.Truths:BAAANQADCgIIAgABNQAECgQIBQADAAAAAA==.Truthsx:BAAANQAECgQIBQAAAA==.Truthy:BAAANQADCgYICAABNQAECgQIBQADAAAAAA==.',
Ts='Tsukúne:BAAANQADCgQIBAAAAA==.',
Ty='Tyg:BAAANQADCgcIBwAAAA==.Tylaatape:BAAANQAECgQIBgAAAA==.Tyraell:BAAANQAECgMIBgAAAA==.',
['Tõ']='Tõkó:BAAANQADCgUIBQABNQAFFAEIAQADAAAAAA==.',
Um='Umbrae:BAAANQADCgMIAQAAAA==.Umfray:BAAANQAECgEIAQABNQAECgIIBAADAAAAAA==.',
Us='Usgasdanelv:BAAANQAECgQIBQAAAA==.',
Uz='Uzala:BAAANQADCgYIEQAAAA==.',
Va='Vanleiden:BAAANQADCgEIAQAAAA==.Vazro:BAAANQAECgUICgAAAA==.',
Ve='Venthyl:BAABNQAECoEWAAIFAAkJ0SQgBACbAwAFAAkJ0SQgBACbAwAAAA==.',
Vi='Vizan:BAAANQABCgcIBwABNQAECgQIBQADAAAAAA==.',
We='Wellby:BAAANQADCgYIDwAAAA==.Westerin:BAAANQAECgQIBAAAAA==.',
Wi='Wildnature:BAAANQADCgYIBgAAAA==.Wimateeka:BAAANQAECgQIBwAAAA==.Windfury:BAAANQAECgYICAABNQAECgkJHgABANwiAA==.Windigo:BAAANQAECgIIAgAAAA==.',
Wo='Wooqles:BAAANQADCgUIBQABNQADCgYICAADAAAAAA==.',
Wr='Wrastelas:BAAANQABCgEIAQAAAA==.',
Wu='Wuilhem:BAAANQADCgEIAQAAAA==.',
Xa='Xaala:BAAANQAECgQIBQAAAA==.',
Xo='Xosderdk:BAAANQADCgIIAgAAAA==.',
Ya='Yarjuul:BAAANQAECgIIAgABNQAECgIIBAADAAAAAA==.',
Ye='Yespaladin:BAABNQAECoEYAAIZAAgJeRmyGQBXAgAZAAgJeRmyGQBXAgAAAA==.',
Yi='Yimity:BAAANQADCgYIBgAAAA==.',
Yo='Yogí:BAABNQAECoEdAAIOAAkJHR4lDAAFAwAOAAkJHR4lDAAFAwAAAA==.Yozomoto:BAABNQAECoEYAAMTAAkJcR4iCgA1AwATAAkJcR4iCgA1AwAJAAEJ5gjSTwAxAAAAAA==.',
Za='Zalandria:BAAANQADCggIGgAAAA==.',
Ze='Zeltemis:BAAANQAECgMIAwAAAA==.',
Zi='Zipsion:BAAANQAECgYIDAAAAA==.Zithen:BAAANQADCgEIAQAAAA==.Zivver:BAAANQAECgUICgAAAA==.Zizka:BAAANQAECgQIBgAAAA==.',
Zo='Zolandir:BAAANQADCgcICgAAAA==.',
['Üt']='Üther:BAAANQAECgYIDQAAAA==.',
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
