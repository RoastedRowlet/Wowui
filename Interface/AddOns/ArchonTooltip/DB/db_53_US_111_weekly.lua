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

local lookup = {'Shaman-Elemental','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Warrior-Protection','Mage-Arcane','Unknown-Unknown','Hunter-BeastMastery','Warlock-Affliction','Shaman-Restoration','Druid-Restoration','Druid-Guardian','Paladin-Holy','Warlock-Demonology','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','Mage-Frost','DeathKnight-Frost','Rogue-Subtlety','Hunter-Marksmanship','Priest-Shadow','DeathKnight-Blood','Rogue-Assassination','Priest-Holy','DemonHunter-Devourer','Priest-Discipline','Druid-Balance','Evoker-Augmentation','Evoker-Devastation','Paladin-Protection',}
local provider = {region='US',realm='Gorgonnash',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aakira:BAABNQAECn9KAAIBAAoKZhP/NwDfAQABAAoKZhP/NwDfAQAAAA==.Aathea:BAAANQADCgEIAQAAAA==.',
Ab='Abrastal:BAABNQAECn8XAAICAAgK1hfxnQB8AQACAAgK1hfxnQB8AQAAAA==.',
Ai='Ailmare:BAAANQADCgUIBgAAAA==.',
Al='Alline:BAAANQADCgMIAwAAAA==.Alswaron:BAAANQAECgUICgAAAA==.',
Am='Amador:BAABNQAECn8xAAQDAAoKbR6DAwAdAwADAAgKMCODAwAdAwAEAAgKTB1nWgB9AgAFAAUKJBTmIABGAQAAAA==.Amyra:BAAANQABCggIEQAAAA==.',
An='Ancient:BAAANQAECggICAAAAA==.',
Ap='Aparition:BAAANQADCgcIBQAAAA==.Apsallar:BAABNQAECn8bAAIGAAkKSBvifACeAQAGAAkKSBvifACeAQAAAA==.',
Ar='Arcanedream:BAAANQADCgIIAgABNQAECgYICwAHAAAAAA==.Arcanism:BAABNQAECn85AAIGAAoKGBZgSQAkAgAGAAoKGBZgSQAkAgAAAA==.Arlas:BAAANQADCgcICwAAAA==.',
As='Asstalor:BAAANQADCgYIBgAAAA==.',
At='Athune:BAAANQAECggICAAAAA==.',
Au='Auryon:BAABNQAECn89AAIIAAkKmB6PGADXAgAIAAkKmB6PGADXAgAAAA==.',
Av='Avadacadabra:BAAANQAECggIEgAAAA==.',
Ba='Baraka:BAAANQAECgEJAQAAAA==.Baulder:BAAANQADCgEIAQAAAA==.',
Be='Beercules:BAAANQADCgYIBgAAAA==.',
Bi='Bigb:BAAANQAECgUIBQABNQAFFAkKHwAGAEIfAA==.',
Bl='Bleedwoundz:BAAANQAECgIIBAAAAA==.Bluè:BAABNQAECn8eAAIBAAkKSR1lOQCRAgABAAkKSR1lOQCRAgAAAA==.',
Bo='Boltz:BAAANQAECgIIAgABNQAECgoKLAAJAOQZAA==.Bonesplitter:BAAANQADCgQIBAAAAA==.Boozetotems:BAABNQAECn8nAAMKAAoKVh3lFwDjAgAKAAoKVh3lFwDjAgABAAEKAABMHgEAAAAAAA==.',
Br='Brekke:BAABNQAECn9CAAICAAoK1xONdwDLAQACAAoK1xONdwDLAQAAAA==.',
Bu='Buffalotrace:BAAANQADCgMIAwAAAA==.Bushmethsin:BAABNQAECn8hAAMLAAoKWiIICwAZAwALAAoKWiIICwAZAwAMAAUKWSGFGADqAQAAAA==.Buttery:BAABNQAECn8rAAICAAoKiRz5TQAxAgACAAoKiRz5TQAxAgAAAA==.',
Ca='Cabb:BAABNQAECn8VAAMFAAkKhQ38GQAfAQAFAAcKHg78GQAfAQAEAAMKtQrb3gCiAAAAAA==.Capytaan:BAAANQADCgYIBgAAAA==.',
Ch='Cheesey:BAAANQAECgYIBAABNQAECgoKNgANAHsVAA==.Chimkinnugge:BAAANQAECgIIAgAAAA==.',
Cr='Critable:BAAANQAECgcICAAAAA==.',
Da='Daegan:BAAANQAECgEIAQAAAA==.Darkhelmet:BAAANQAECggICAAAAA==.Darwen:BAAANQADCgEIAQAAAA==.Dayna:BAAANQAECgMIAwAAAA==.',
De='Dergon:BAABNQAECn8rAAIOAAoKaBgfWQBLAgAOAAoKaBgfWQBLAgAAAA==.',
Dm='Dmonicbanshe:BAAANQADCgcIBwAAAA==.',
Do='Dogwalker:BAAANQADCgYJBgABNQAECgoKLAAJAOQZAA==.Doomedturtle:BAAANQABCgYICAAAAA==.',
Du='Duergan:BAACNQAFFH8IAAIPAAMK9QSJBwBjAAAPAAMK9QSJBwBjAAA1AAQKfzwAAw8ACgoYExYTALIBABAACAo2FMQqAMYBAA8ACgppDBYTALIBAAAA.',
['Dà']='Dàrkblade:BAAANQADCggIGwAAAA==.',
Ea='Eatz:BAAANQAECggIEgAAAA==.',
Em='Emo:BAACNQAFFH8IAAIRAAQKWAk9CADNAAARAAQKWAk9CADNAAA1AAQKfxYAAhEACgrfDj0fANQBABEACgrfDj0fANQBAAAA.',
En='Enigmaatic:BAABNQAECn8+AAMGAAoKlxf2PwBAAgAGAAoKlxf2PwBAAgASAAMK2A3pIgCwAAAAAA==.',
Fa='Fansy:BAAANQAECgQIBwAAAA==.',
Fe='Felwind:BAAANQAECgQICAAAAA==.Ferinsmash:BAAANQAECgEIAQAAAA==.',
Fl='Fleurelle:BAAANQADCgYIDQAAAA==.',
Fo='Fooli:BAAANQABCgQIBgAAAA==.',
Fr='Frostfree:BAABNQAECn8mAAITAAYKQQkrYwAXAQATAAYKQQkrYwAXAQAAAA==.Frydãy:BAAANQAECgQIBgABNQAECgoKHwAUAAYMAA==.',
Fu='Furfiend:BAABNQAECn8hAAIRAAoKdh0aKgCPAgARAAoKdh0aKgCPAgAAAA==.',
Gb='Gb:BAABNQAECn8YAAIVAAkKkxLMHgBaAgAVAAkKkxLMHgBaAgABNQAECgcIFAAWAB4dAA==.',
Gi='Gilraen:BAABNQAECn8oAAMEAAkKTRDtiwD+AQAEAAkK4g7tiwD+AQADAAMKyxH5HwC9AAAAAA==.Gilthy:BAAANQABCgEIAQAAAA==.Gingja:BAAANQADCgEIAQABNQAECgcIIgAFABYVAA==.',
Go='Goldenaege:BAAANQAECgYIBQAAAA==.Gorgrand:BAAANQAECggICAAAAA==.',
Gr='Greaseduppig:BAAANQADCgIIAgAAAA==.Greggy:BAAANQADCggICAAAAA==.',
Ha='Hairypotter:BAAANQADCgYICQABNQAECgIIBAAHAAAAAA==.Happydaze:BAABNQAECn8tAAMXAAoK/xAUKACwAQAXAAoK/xAUKACwAQARAAEKQAgK8QAlAAAAAA==.Hardison:BAAANQAECgIIAgAAAA==.Haxthedk:BAAANQABCgEIAQAAAA==.Haxtheshaman:BAAANQABCgIIAgAAAA==.',
Ho='Hojx:BAAANQAECggIDgAAAA==.Honeydew:BAABNQAECn8kAAIBAAoK8hM5SgBNAgABAAoK8hM5SgBNAgAAAA==.',
Hr='Hrolf:BAABNQAECn8tAAIMAAoKehCeHACIAQAMAAoKehCeHACIAQABNQAFFAMICAAPAPUEAA==.',
Il='Illidont:BAAANQAECgUIDQAAAA==.Illijr:BAAANQAECgQIBgAAAA==.',
In='Interfector:BAAANQAECgYIBwAAAA==.',
Ja='Jadehorn:BAAANQAECgIIAgAAAA==.',
Jk='Jkass:BAAANQAECgEIAgAAAA==.',
Ju='Judgementdày:BAAANQAECgYIDAAAAA==.',
Ke='Kemmy:BAAANQAECgQIBwAAAA==.',
Ki='Kiandara:BAACNQAFFH8fAAMEAAgKIxWxCQAYAgAEAAcKIxWxCQAYAgADAAMKqgndAQD5AAA1AAQKfz4AAwQACgraI8IOABoDAAQACgrBI8IOABoDAAMABgp0Ha8OAMMBAAAA.Kikkoman:BAABNQAECn8oAAMUAAoKcB5/IwBpAgAYAAkKLx2qHQCSAgAUAAkKRR1/IwBpAgAAAA==.Kirant:BAAANQAECgMIAwAAAA==.Kittlynia:BAAANQABCgIIAgAAAA==.Kittrina:BAAANQAECgIIAQAAAA==.',
Kp='Kpot:BAAANQADCggIFQAAAA==.',
Ky='Kynrath:BAAANQAECgEIAQAAAA==.',
Le='Lelanie:BAAANQADCggIDAAAAA==.',
Li='Lightfrost:BAABNQAECn82AAMNAAoKexVDNwArAgANAAoKexVDNwArAgACAAkKMhGSwQA6AQAAAA==.Lilithdawn:BAABNQAECn8xAAIZAAoKABYOPAA2AgAZAAoKABYOPAA2AgAAAA==.',
Lo='Lockkitt:BAAANQAECgQIBQAAAA==.Lockwar:BAABNQAECn8sAAIJAAoK5BnUAwBdAgAJAAoK5BnUAwBdAgAAAA==.Louvre:BAABNQAECn8hAAIYAAoKoxPVDQDfAQAYAAoKoxPVDQDfAQAAAA==.Lowehigh:BAAANQADCgUIBgAAAA==.',
Lu='Lukarian:BAAANQADCggIFAAAAA==.Luminaughty:BAAANQADCgcIDAAAAA==.',
Ma='Madmarrtigan:BAAANQADCgUICAAAAA==.Madmarttigan:BAAANQADCgUICQAAAA==.Maheehoo:BAAANQAECgQICgAAAA==.Maheewhat:BAAANQADCgYIBgABNQAECgQICgAHAAAAAA==.Mahok:BAAANQADCgMIAwAAAA==.Mashka:BAAANQAECgcIEQAAAA==.',
Me='Melbuki:BAAANQAECgIIAwAAAA==.Meric:BAAANQADCggIGgAAAA==.Mesotusky:BAAANQADCgYICgABNQAECgQICgAHAAAAAA==.',
Mi='Microbrew:BAAANQAECgIIBAABNQAECgkJKgAMABIaAA==.Millerlight:BAAANQADCgYJCgAAAA==.',
Mo='Moardotz:BAAANQADCgYIDgABNQAECgYICwAHAAAAAA==.Molasses:BAABNQAECn9MAAISAAoK5R3zAwD4AgASAAoK5R3zAwD4AgAAAA==.',
['Mê']='Mêphisto:BAAANQABCgUIBwAAAA==.',
['Mï']='Mïkasa:BAAANQAECgIIAgABNQAECgkJKgAEAIESAA==.',
['Mú']='Músic:BAAANQADCggICAABNQAECgoKHwAUAAYMAA==.',
Na='Nacho:BAAANQAECgIIAgAAAA==.Naptime:BAAANQADCgYIBwAAAA==.',
Ni='Nifkin:BAAANQADCgMIAwAAAA==.Nilse:BAAANQAECggIDAAAAA==.',
Nu='Nubkselk:BAABNQAECn8gAAIaAAoKlRouHgBfAgAaAAoKlRouHgBfAgAAAA==.Nurishment:BAACNQAFFH8VAAILAAcKag7BBwB8AQALAAcKag7BBwB8AQA1AAQKfygAAgsACQrmILkMAAIDAAsACQrmILkMAAIDAAAA.',
On='Onitvchi:BAAANQAECgMIAwAAAA==.',
Op='Opartos:BAAANQADCggICAAAAA==.Optistriker:BAABNQAECn9KAAILAAoKOhavGAAzAgALAAoKOhavGAAzAgAAAA==.',
Pa='Painfree:BAAANQADCggIAgAAAA==.Papabear:BAAANQADCgEIAQAAAA==.',
Pe='Peregrine:BAAANQADCgYIBgAAAA==.',
Ph='Philjaa:BAAANQAECgEIAQAAAA==.',
Po='Potatoe:BAABNQAECn8dAAQWAAoKxwuJKwARAQAWAAgKmgiJKwARAQAZAAkKZAaAowDcAAAbAAUK/gPYGACpAAABNQAECgoKNgANAHsVAA==.',
Pr='Prettyfun:BAAANQADCgUIBQAAAA==.Prometeo:BAAANQADCgMIAwAAAA==.',
Qi='Qira:BAAANQAECgYIDQAAAA==.',
Ra='Radicalism:BAAANQAECgMIAwAAAA==.Raechan:BAAANQAECgQICQAAAA==.Rantioc:BAAANQAECgEIAQAAAA==.Rastasparkly:BAAANQADCggICAAAAA==.',
Re='Remag:BAAANQABCgQIBgAAAA==.Reparations:BAAANQAECggICAAAAA==.Rexbriefs:BAAANQADCgMIAwAAAA==.',
Ro='Rockypalboa:BAABNQAECn8fAAMNAAoKtx2zGwAGAwANAAoKtx2zGwAGAwACAAUKgRKMDAEKAQAAAA==.',
Ru='Rulfnor:BAABNQAECn8nAAMCAAoKSQ4htwCwAQACAAoKSQ4htwCwAQANAAUK7gSm4gC7AAAAAA==.',
Sa='Sacrifice:BAAANQADCggICgAAAA==.Sapodillà:BAAANQAECgcIDgAAAA==.Saurax:BAAANQAECgEIAQAAAA==.',
Sc='Scorench:BAAANQAECgIIAgAAAA==.',
Se='Seldaa:BAAANQADCgYIBgAAAA==.Seraxx:BAAANQADCgIIAgAAAA==.Sevrin:BAACNQAFFH8mAAMYAAkKeBggAQANAgAUAAYKOR5jAgAkAgAYAAgKbRggAQANAgA1AAQKfzQAAxgACgrjJP0DAO0CABQACQpsJBcFADkDABgACQocIv0DAO0CAAAA.Sevro:BAAANQABCgEIAQAAAA==.',
Sh='Shammazing:BAAANQADCgcIBwABNQAECgoKMAAIAOsJAA==.Shìft:BAAANQADCggICAABNQAECgoKNQAUACkjAA==.Shîft:BAABNQAECn81AAMUAAoKKSN5AwBqAwAUAAoKKSN5AwBqAwAYAAMKQBEDfQC/AAAAAA==.',
Sl='Slice:BAAANQAECgEIAQAAAA==.',
So='Sok:BAAANQAECgYICwAAAA==.Soktear:BAAANQAECgYICgAAAA==.Soladaris:BAAANQABCggICwAAAA==.Solicide:BAABNQAECn8qAAMMAAkKEhobDwByAgAMAAkKEBobDwByAgAcAAUKuhfIZAA6AQAAAA==.',
Sp='Sparkle:BAACNQAFFH8UAAIdAAYKsg7yBABSAQAdAAYKsg7yBABSAQA1AAQKfz0AAx0ACgqfH5ADAPcCAB0ACgqfH5ADAPcCAB4AAQpdEkk7ADkAAAAA.',
Sv='Svets:BAABNQAECn8XAAIZAAgKjx/JJQDUAgAZAAgKjx/JJQDUAgAAAA==.',
Sw='Swenzy:BAAANQABCgMIAwAAAA==.',
Sy='Sylphrenna:BAAANQADCggICwAAAA==.',
Te='Teeanna:BAAANQADCgYICQABNQADCgcICwAHAAAAAA==.Tempers:BAABNQAECn8bAAIGAAgKTw/l2gDSAQAGAAgKTw/l2gDSAQAAAA==.',
Th='Thornum:BAAANQADCgQIBAAAAA==.Thottyshotty:BAAANQABCgUIAwAAAA==.',
Ti='Tinnman:BAABNQAECn8eAAIOAAkKphFsfABVAQAOAAkKphFsfABVAQAAAA==.',
To='Toteschaos:BAAANQADCggIDAAAAA==.',
Tw='Twiz:BAABNQAECn8cAAICAAoKzwlXuwCmAQACAAoKzwlXuwCmAQAAAA==.Twizzly:BAAANQAECgQICgAAAA==.Twizzy:BAABNQAECn8wAAIIAAoK6wmKowC/AQAIAAoK6wmKowC/AQAAAA==.',
Tz='Tzechan:BAABNQAECn9TAAMNAAoK8SOWDgBWAwANAAoK8SOWDgBWAwACAAEKAACNoAE3AAAAAA==.',
Ur='Urlshekk:BAABNQAECn8ZAAQfAAoK4BkwHgD3AQAfAAkK4BkwHgD3AQANAAQKPwqczQBpAAACAAIK6wmhjQFHAAAAAA==.Urrdad:BAAANQADCggIEQAAAA==.',
Va='Valtirya:BAAANQADCgIIAgAAAA==.Varumn:BAACNQAFFH8IAAIfAAIKqwRHDABaAAAfAAIKqwRHDABaAAA1AAQKfzEABB8ACQpEE1cUAM8BAB8ACQpEE1cUAM8BAA0AAgrcAc/mADsAAAIAAQrdAizCAScAAAE1AAUUAwgKABkADxQA.',
Ve='Veex:BAAANQADCgUIBgAAAA==.Velithari:BAAANQADCgQIBAAAAA==.',
Vi='Viaugra:BAAANQADCgEIAQAAAA==.',
We='Wearegroot:BAAANQADCgcICAAAAA==.',
Wi='Wihtè:BAAANQADCgcIBwABNQAECgkJHgABAEkdAA==.Wind:BAAANQADCggIDgAAAA==.',
Xa='Xandera:BAAANQADCgcJDgABNQAECgoKPAARAHwaAA==.',
Xp='Xpally:BAABNQAECn8oAAINAAkKFRPhXQD/AQANAAkKFRPhXQD/AQAAAA==.',
Yt='Ytoshi:BAAANQADCgYIBgAAAA==.',
['Yè']='Yèlloow:BAAANQADCgMIAwABNQAECgkJHgABAEkdAA==.',
Za='Zaquel:BAAANQAECgUIBwABNQAECgoKPAARAHwaAA==.Zarcissa:BAAANQAECgUIDgAAAA==.',
Zo='Zosebalie:BAAANQAECgQIBQAAAA==.',
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
