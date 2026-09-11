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

local lookup = {'Warlock-Demonology','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Mage-Arcane','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Druid-Feral',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaril:BAAANQADCgMIBQAAAQ==.',
Ab='Abrams:BAAANQAECgYICwAAAA==.Absínthè:BAAANQABCgQIBAAAAA==.',
Ag='Agnass:BAAANQADCgEIAQAAAA==.',
Al='Aldea:BAAANQADCgYIBgAAAA==.Alirrayiia:BAAANQAECgYICgAAAA==.Allystar:BAAANQADCgMIBAAAAA==.Alvidor:BAAANQAECgEIAQAAAA==.',
Am='Amachine:BAAANQADCggIDgABNQAECgkJFgABAI0iAA==.Amybabe:BAAANQADCgQIBAAAAA==.',
An='Anorivia:BAAANQAECgMIAwAAAA==.',
Ap='Apollossham:BAAANQAECgMIBAAAAA==.',
Ar='Arragora:BAAANQAECgQIBQAAAA==.Arrowdynamix:BAAANQADCgYIDQAAAA==.',
As='Ashyani:BAAANQADCgUIBQAAAA==.',
At='Atlan:BAAANQADCgUIBQABNQAECgMIBAACAAAAAA==.',
Ba='Babbayagga:BAAANQAECgUIBQAAAA==.Baji:BAAANQAECgUICAAAAA==.Barefaall:BAABNQAECoEaAAMDAAkJpCNIBQA/AwADAAgJCiZIBQA/AwAEAAIJOxisKwCoAAAAAA==.Barefalls:BAAANQAECgEIAgABNQAECgkJGgADAKQjAA==.Baénoth:BAAANQABCgQIBgAAAA==.',
Be='Bergonator:BAAANQADCggICAAAAA==.Berrodiah:BAAANQADCgUIBQABNQAECgQIBQACAAAAAA==.Bestlays:BAAANQADCgUIBQAAAA==.Bettiepage:BAAANQADCgEIAQAAAA==.',
Bh='Bheiroth:BAAANQAECgMIBAAAAA==.',
Bl='Blackchapell:BAAANQABCgYICQAAAA==.Bluett:BAAANQADCgEIAQAAAA==.',
Bo='Bogertus:BAAANQAECgQICQAAAA==.',
Br='Brein:BAAANQAECgEIAQAAAA==.',
Bu='Bucketeer:BAAANQADCggIEQAAAA==.',
Ca='Cameltoetoe:BAAANQAECgEIAQAAAA==.Canaprey:BAAANQADCgcIEwABNQADCggIEAACAAAAAA==.Catshunter:BAAANQADCgYIBgAAAA==.',
Ce='Celaa:BAAANQADCgQIBAABNQADCggIFAACAAAAAA==.Celebrían:BAAANQADCgUIBQAAAA==.',
Ch='Chanka:BAAANQADCgYICQAAAA==.Chantillary:BAAANQADCgEIAQAAAA==.Charise:BAAANQADCggIEQAAAA==.Cheesy:BAAANQADCgYIDAAAAA==.Chopzullee:BAAANQADCgYIBgAAAA==.',
Ci='Cinnaz:BAAANQAECgUICgABNQAECgYIDwACAAAAAA==.',
Cl='Clortho:BAAANQADCgYIEAAAAA==.',
Co='Colljack:BAAANQAFFAIIAgAAAA==.Corvath:BAAANQAECgEIAQAAAA==.',
Cr='Cryptoe:BAAANQAECgcIDQAAAA==.',
Da='Daedelus:BAAANQAECgEIAQAAAA==.Daglon:BAAANQADCgcIBwAAAA==.Daraedra:BAAANQADCgcICgAAAA==.Dardolur:BAAANQADCgIIAgAAAA==.Darkslayer:BAAANQADCgMIAwAAAA==.Darkthyr:BAAANQADCggIFgAAAA==.',
De='Deeznutticus:BAAANQAFFAEIAQAAAA==.Demonspud:BAAANQAECgQIBgAAAA==.Dersan:BAAANQADCgIIAgAAAA==.Destriant:BAAANQAECgUIBgAAAA==.Devourer:BAAANQABCgMIAwAAAA==.Deylia:BAAANQADCgYIBgABNQAECgYIDgACAAAAAA==.',
Dh='Dhori:BAAANQADCgEIAQAAAA==.',
Di='Dillion:BAAANQAECgEIAQAAAA==.Dionin:BAAANQADCgUICgAAAA==.Dizzyhealz:BAAANQADCgMIBQAAAA==.Dizzyhuntres:BAAANQABCgMIAwAAAA==.',
Do='Dooberto:BAAANQAECgIIAgAAAA==.Dooburt:BAAANQADCgcIBwAAAA==.',
Dr='Dracaric:BAAANQADCgYIBgAAAA==.Dragondznut:BAAANQADCgQIBAAAAA==.Drfrostie:BAAANQAECgQIBAAAAA==.Driatin:BAAANQAECgEIAQAAAA==.',
Du='Durø:BAAANQAECgUICAAAAA==.',
['Dè']='Dègenerate:BAAANQAECgUICAAAAA==.',
Ed='Eddy:BAAANQAECgQIAwAAAA==.',
El='Eldumpling:BAAANQAECgMIBAAAAA==.',
Ep='Epicnym:BAAANQADCggIDgAAAA==.',
Es='Esdeath:BAAANQAECgEIAgAAAA==.',
Ex='Extenze:BAAANQAECgEIAQAAAA==.',
Fe='Feda:BAAANQADCgQIBAAAAA==.Ferryman:BAAANQADCgcIEgAAAA==.',
Fi='Findria:BAAANQADCgYIBgABNQAECgYIDQACAAAAAA==.',
Fo='Forphium:BAABNQAECoEWAAMFAAkJTRtZBwCuAgAFAAgJ+htZBwCuAgAGAAEJ5xVRLQBNAAAAAA==.',
Fr='Freespirit:BAAANQAECgYICgABNQAFFAQIBgAHAHgiAA==.Friarkuck:BAAANQADCgEIAQAAAA==.',
Ga='Gahlina:BAAANQADCgYIDwAAAA==.Gambaaddict:BAAANQAECgQIBAAAAA==.Garshan:BAAANQADCgYIDAAAAA==.',
Gh='Ghexn:BAAANQADCgIIAgAAAA==.',
Gi='Gilleyy:BAAANQADCggIDgAAAA==.Gird:BAAANQAECgEIAQAAAA==.',
Gn='Gnymesis:BAAANQADCgUIBQAAAA==.',
Go='Goatmonger:BAAANQADCggIFgAAAA==.Goinpostal:BAAANQADCgYICwAAAA==.Gordek:BAAANQAECgMIAgAAAA==.',
Gr='Grantaron:BAAANQAECgUIBQAAAA==.Grimskul:BAAANQAECgUICQAAAA==.Grntitan:BAAANQADCgMIBgAAAA==.',
Gw='Gwoohoori:BAAANQADCgQIBAAAAA==.',
Ha='Halukari:BAAANQADCgMIBQABNQAECgYIDgACAAAAAA==.Haléon:BAAANQAECgEIAQAAAA==.',
He='Headshotty:BAAANQADCgYIDAAAAA==.Hellfire:BAAANQADCgYIBgAAAA==.Hezrel:BAAANQADCgYIBgAAAA==.',
Hi='Hinal:BAAANQADCgcIEQAAAA==.',
Ho='Holyenabler:BAAANQAECgUIBQAAAA==.',
Hu='Hungor:BAAANQABCgQIBAAAAA==.',
Ih='Iheartbailey:BAAANQADCgQIBAAAAA==.',
Im='Imcruel:BAABNQAECoEXAAIIAAkJZhvrGQD7AgAIAAkJZhvrGQD7AgAAAA==.',
Io='Iorese:BAAANQADCggIDwAAAA==.',
Ir='Iriana:BAEANQADCgQICQAAAA==.',
Ja='Jagershamer:BAAANQAECgQIBAAAAA==.Jasperine:BAAANQAECgEIAQABNQAFFAQIBgAHAHgiAA==.',
Je='Jenneldots:BAAANQAECgQIBgABNQAECgYIBwACAAAAAA==.Jerce:BAAANQADCgUICQAAAA==.',
Jo='Johnnyhuntz:BAAANQADCgYICAAAAA==.',
Ju='Juacqer:BAAANQADCgEIAQAAAA==.',
Ka='Kaant:BAAANQAECgEIAQAAAA==.Kaidevyn:BAAANQAECgIIAgAAAA==.',
Ke='Keiran:BAAANQAECgUIBQAAAA==.Kenix:BAAANQADCgUIBQABNQADCgYICgACAAAAAA==.',
Kh='Khalnerys:BAAANQADCggIDAAAAA==.Khaotick:BAEANQAECgYIDAABNQAECgUIBQACAAAAAA==.Khoulock:BAABNQAECoEQAAQJAAkJihp2DgDdAQAJAAYJ7hp2DgDdAQABAAYJZBjtJgDUAQAKAAEJJhngEgBHAAAAAA==.',
Ki='Kimmi:BAAANQAECgEIAQAAAA==.Kiro:BAAANQADCgYIBgAAAA==.',
Ko='Kotawar:BAAANQADCgMIAwAAAA==.',
Kt='Kthxbye:BAAANQADCgUIBQABNQAECgQIBAACAAAAAA==.',
Ku='Kuraishin:BAAANQAECgUICwAAAA==.Kuterr:BAAANQADCgUIBQAAAA==.',
Ky='Kyrae:BAAANQADCgYIEAAAAA==.',
La='Lagspike:BAAANQAECgYIDwAAAA==.',
Le='Lengex:BAAANQADCgEIAQAAAA==.Lero:BAAANQAECgIIAgAAAA==.Lexoh:BAAANQAECgQIAgAAAA==.',
Li='Lilieth:BAAANQADCgEIAQAAAA==.Liltankarmor:BAAANQAECgYIBwAAAA==.Lindir:BAAANQAECgYIDQAAAA==.Liquid:BAAANQAECgIIBQAAAA==.Litasfk:BAAANQAECgQIBAAAAA==.Liuni:BAAANQAECgMIBAAAAA==.',
Lo='Lobopeste:BAAANQAECgEIAQAAAA==.Lorelynn:BAAANQAECgQIBAAAAA==.Loðbrók:BAAANQADCgYICwAAAA==.',
Lu='Luckycritz:BAAANQADCggICAABNQAECgcIDQACAAAAAA==.Lucìan:BAAANQAECgMIBAAAAA==.Luna:BAAANQAECgQIBAAAAA==.Lunaclair:BAAANQAECgEIAQABNQAECgUICwACAAAAAA==.Lunarielle:BAAANQAECgQIBgAAAA==.',
Ma='Mabrito:BAAANQAECgcIDgABNQAFFAMIBAACAAAAAA==.Macfly:BAAANQAECgQIBgAAAA==.Macneel:BAAANQADCgEIAQAAAA==.Magicmissile:BAAANQADCgEIAQABNQAECggIEwACAAAAAA==.Malevalous:BAAANQADCgQICQABNQAECgEIAQACAAAAAA==.Mancath:BAAANQAECgEIAQAAAA==.Marlei:BAAANQADCggIFAAAAA==.Maru:BAAANQADCgcIBwABNQAECgUICAACAAAAAA==.',
Me='Medenà:BAAANQADCgMIAwAAAA==.Meeko:BAAANQAECgcIBwABNQAECgkJGgALABkhAA==.Melfie:BAAANQADCgQIBAAAAA==.',
Mi='Midoriya:BAAANQADCgcICQAAAA==.Mistjack:BAAANQADCggICAAAAA==.',
Mo='Moldyjack:BAAANQAECgEIAQAAAA==.Mortiis:BAAANQADCgMIAwAAAA==.',
My='Myzyry:BAAANQAECgIIAgAAAA==.',
['Må']='Måze:BAAANQADCgIIAgAAAA==.',
Na='Nazdormu:BAAANQADCgcIEgAAAA==.',
Ne='Neisen:BAAANQADCgYIBgAAAA==.Nevare:BAAANQADCgYIBgAAAA==.',
Nu='Nubi:BAAANQADCgIIAgAAAA==.Nugent:BAAANQAECgQIBAAAAA==.',
Oa='Oakgrove:BAAANQADCgIIAgAAAA==.',
On='Oneforall:BAAANQAECgYIDAAAAA==.',
Pa='Pailly:BAAANQABCgQIBAAAAA==.Papalion:BAAANQAECgEIAQAAAA==.',
Pi='Pinklilydrd:BAAANQADCgUIBQAAAA==.',
Pl='Plaindonut:BAAANQAECgUIBQAAAA==.',
Pr='Prissygalore:BAAANQADCgEIAQAAAA==.',
Pu='Putras:BAAANQABCgIIAgAAAA==.',
Ra='Ravenbrook:BAAANQAECgYICwAAAA==.Rawrr:BAAANQADCgcIBwAAAA==.Raxie:BAAANQAECgYIDgAAAA==.',
Re='Reddfoxx:BAAANQADCgUIBwAAAA==.Resepuff:BAAANQADCggIEAAAAA==.',
Rh='Rhymunky:BAAANQADCgMIAwAAAA==.',
Ri='Rifthor:BAAANQADCgYIBgAAAA==.Ripmxi:BAAANQAECgMIAwAAAA==.',
Ru='Runelight:BAAANQADCgMIAwABNQAECgYICgACAAAAAA==.Runeshock:BAAANQAECgYICgAAAA==.Rupertgiless:BAABNQAECoEWAAIBAAkJbRoqBwD1AgABAAkJbRoqBwD1AgAAAA==.',
Sa='Saluran:BAAANQABCgYIBgAAAA==.Sannea:BAAANQADCgUICgABNQADCggIFAACAAAAAA==.Sarcastyx:BAAANQAECgMIAgAAAA==.Saxines:BAAANQADCgYIDQAAAA==.',
Sc='Schwarznacht:BAAANQADCgUIBQAAAA==.',
Se='Seekndestroy:BAAANQAECgEIAQAAAA==.',
Sh='Shankkerz:BAAANQADCgYICAAAAA==.',
Si='Sindusk:BAAANQAECgYIDAAAAA==.Sitzho:BAAANQADCgIIAwAAAA==.',
Sk='Skeleton:BAAANQABCgIIAgAAAA==.Skullblade:BAAANQADCgcICwAAAA==.Skybringer:BAAANQADCggIGwAAAA==.Skydras:BAAANQAECgUICQAAAA==.',
Sm='Smoothscales:BAAANQABCgQIBgAAAA==.',
So='Sonofgrumpy:BAAANQADCggIEAAAAA==.Sorphium:BAAANQAECgIIBAABNQAECgkJFgAFAE0bAA==.Soxxy:BAAANQADCgEIAQABNQAECgYIBwACAAAAAA==.',
Sp='Sparhawk:BAAANQADCgYIEQAAAA==.',
St='Stormyprissi:BAAANQABCgMIAwAAAA==.Strombjorn:BAAANQAECgEIAQAAAA==.',
Ta='Talie:BAAANQABCgQIBAAAAA==.Tasireth:BAAANQADCgMIAwAAAA==.',
Te='Tessi:BAAANQAECgUICwAAAA==.Testamental:BAAANQADCgIIAgAAAA==.',
Th='Thalrian:BAAANQADCggIDgAAAA==.Theylive:BAAANQADCgcIBwAAAA==.Thighs:BAAANQAECgMIAwAAAA==.',
Ti='Tiahina:BAAANQADCgUIBQAAAA==.Tipsypala:BAAANQAECgIIAgAAAA==.',
To='Toya:BAAANQAECgUIBQAAAA==.',
Tr='Trivia:BAAANQADCgcIEAAAAA==.Truthordare:BAAANQADCgYIDQAAAA==.',
Tu='Turtei:BAAANQADCggICAABNQAFFAIIAgACAAAAAA==.Turtl:BAAANQAFFAIIAgAAAA==.',
Ul='Ulgrym:BAAANQADCgEIAQAAAA==.',
Un='Unbalancéd:BAAANQADCgUIBgAAAA==.Unbroken:BAAANQABCgMIAgAAAA==.',
Va='Vaeadin:BAAANQADCgYIDwAAAA==.Vahra:BAAANQADCgEIAQAAAA==.Valantis:BAAANQAECgQIBAAAAA==.Valgaskav:BAAANQAECgMIAwAAAA==.Valkor:BAAANQADCgIIAgAAAA==.Valric:BAAANQADCgYIBgAAAA==.',
Ve='Vegasnight:BAAANQADCgMIBQAAAA==.Venithan:BAAANQADCgYICgABNQADCgYIEAACAAAAAA==.',
Vo='Volos:BAAANQADCggIDAAAAA==.Vordaman:BAAANQAECgUICAAAAA==.',
Vy='Vynír:BAAANQAECggIDwAAAA==.',
Wa='Waghoba:BAABNQAECoEYAAIMAAkJ4yKzAAB8AwAMAAkJ4yKzAAB8AwAAAA==.Wandä:BAAANQAECgQIBQAAAA==.Warborn:BAAANQADCgQIBAAAAA==.Warrionomous:BAAANQAECggIEwAAAA==.Washu:BAAANQAECgEIAgAAAA==.',
We='Wetkittyy:BAAANQABCgUICAAAAA==.',
Wh='Whobetter:BAAANQADCgYICQAAAA==.',
Wi='Winterous:BAAANQAECgIIAgAAAA==.',
Wo='Wonderbread:BAAANQAECgYICAAAAA==.',
Xe='Xenan:BAAANQADCggIEAAAAA==.',
Xt='Xtrolldinary:BAAANQADCgMIAwAAAA==.',
Ye='Yeastmode:BAAANQADCgQIBAAAAA==.',
Yo='Yonahh:BAAANQAECgEIAQAAAA==.',
Yv='Yvelthilios:BAAANQADCgcICgAAAA==.',
Ze='Zeebra:BAAANQAECgEIAQAAAA==.Zeg:BAAANQAECgMIBQAAAA==.Zega:BAAANQADCgcIBwAAAA==.Zegafur:BAAANQADCgQIBAAAAA==.',
Zi='Zillionbucks:BAAANQAECggICAAAAA==.Zillionbúcks:BAAANQAECgIIBAABNQAECggICAACAAAAAA==.',
Zu='Zulgore:BAAANQAECgYIBgAAAA==.',
['Zê']='Zêddicus:BAAANQAECgMIBAAAAA==.',
['Áq']='Áquafina:BAAANQAECgMIAwAAAA==.',
['Ðö']='Ðö:BAAANQAECgEIAQAAAA==.',
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
