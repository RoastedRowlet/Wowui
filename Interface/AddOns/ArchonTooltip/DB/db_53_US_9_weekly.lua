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

local lookup = {'Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Mage-Arcane','Unknown-Unknown','Monk-Windwalker','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Druid-Guardian','Warrior-Protection','Warrior-Arms','Warrior-Fury','Warlock-Demonology','Druid-Restoration','Shaman-Enhancement','Shaman-Elemental','Evoker-Preservation','DeathKnight-Blood','Mage-Frost','Mage-Fire','Druid-Feral','DeathKnight-Unholy','Hunter-BeastMastery','Warlock-Destruction','Monk-Mistweaver','Rogue-Assassination','Priest-Shadow','Warlock-Affliction','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Monk-Brewmaster','Rogue-Subtlety','Druid-Balance','Evoker-Devastation','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Acupuncher:BAAANQAECgIIAgAAAA==.',
Ad='Adamsandler:BAAANQADCggICAAAAA==.Adiwolf:BAAANQAECgIIBAAAAA==.',
Al='Alcha:BAAANQAECgcIEAAAAA==.Alenndar:BAAANQADCgEIAQAAAA==.Alexdaddario:BAAANQAECgYIDwAAAA==.Algaefungi:BAAANQAECgIICAAAAA==.Althena:BAAANQAECgEIAQABNQAECgoKOgABACsiAA==.Alystana:BAAANQADCgUIBwAAAA==.',
Am='Amberelle:BAAANQADCgQIBAAAAA==.',
An='Anastera:BAAANQADCgYIBwAAAA==.Animeniac:BAABNQAECn8eAAICAAcKdyK9AQDiAQACAAcKdyK9AQDiAQAAAA==.Anticlimax:BAABNQAECn8fAAQCAAkK4g24GQAZAQADAAcK3w0aQABLAQACAAYK1Ay4GQAZAQAEAAMKWgsKdwCeAAAAAA==.Antilaw:BAAANQAECgEIAgAAAA==.Antisocial:BAAANQAECgQIDQAAAA==.Antistab:BAAANQAECgQIBgAAAA==.',
Ao='Aoibhneas:BAAANQADCgcIBwAAAA==.',
Ap='Apprentice:BAACNQAFFH8HAAIFAAMKkho5MAAOAQAFAAMKkho5MAAOAQA1AAQKfx4AAgUACQoXJNAzACMDAAUACQoXJNAzACMDAAAA.',
Ar='Ariha:BAAANQAECgQIBQAAAA==.Artrael:BAAANQADCggJCAAAAA==.',
At='Atorim:BAAANQADCgIIAgABNQAECgQIBgAGAAAAAA==.',
Av='Avienndha:BAABNQAECn8eAAICAAcKLRn2BQAmAQACAAcKLRn2BQAmAQAAAA==.Avriel:BAAANQAECgQICQABNQAECgoKOgABACsiAA==.',
Ba='Barbatos:BAAANQAECgIIAgAAAA==.',
Be='Beardeddrunk:BAAANQADCgUJBQAAAA==.Beornwildlaw:BAAANQABCgcIDgAAAA==.',
Bi='Bigsheet:BAAANQAECgUIBwABNQAFFAcIIQAHAHIWAA==.',
Bl='Bloodyflame:BAAANQADCgIIAQAAAA==.',
Bo='Bobbytofva:BAAANQAECgMIBAAAAA==.Bobthedurgon:BAAANQADCgUIBQAAAA==.Bobthegrinch:BAAANQADCgQIBAAAAA==.Boneloss:BAAANQADCgQIBAAAAA==.Bonkini:BAAANQAECggICQAAAA==.Boochaka:BAABNQAECn8aAAIIAAkKVhntVAAUAgAIAAkKVhntVAAUAgAAAA==.Bouman:BAAANQADCgYIBgAAAA==.Bouquet:BAABNQAECn8WAAIFAAcKnwQOhwC2AAAFAAcKnwQOhwC2AAAAAA==.',
Br='Brewdog:BAAANQAECgQICgAAAA==.Brickfists:BAAANQADCgQIBAAAAA==.Brotherfuzz:BAAANQAECgIIAwAAAA==.',
Bu='Buckangel:BAAANQAECggIBAABNQAFFAgIBwAJAO4iAA==.Busterposer:BAAANQAECgQICQAAAA==.',
Ca='Caelvaris:BAAANQADCgEIAQAAAA==.Calabooca:BAAANQADCgUICAAAAA==.Canadaclown:BAAANQADCgIIAgAAAA==.Candor:BAAANQADCgUIBQAAAA==.',
Ch='Cheesefries:BAAANQAECgUIEQAAAA==.Chereth:BAAANQAECgcIBwAAAA==.Chratos:BAAANQADCgYIBgAAAA==.',
Cl='Clapton:BAAANQAECgQICQAAAA==.Claptone:BAAANQAECgYIEwAAAA==.',
Co='Corpuscle:BAABNQAECn8ZAAMKAAkK2BYaBgCdAQAKAAkK2BYaBgCdAQAJAAIKogoPDwFZAAAAAA==.',
Cr='Critcomander:BAABNQAECn8pAAIBAAkKFA0yrADHAQABAAkKFA0yrADHAQAAAA==.Critties:BAAANQADCgMIAwAAAA==.Crowfive:BAAANQAECgYIBQAAAA==.Crueldin:BAABNQAECn8WAAMJAAYK2hC1lwBaAQAJAAYK2hC1lwBaAQABAAEKkws4nAE5AAAAAA==.',
Da='Dalsen:BAABNQAECn8tAAILAAkKbg5yIQCOAQALAAkKbg5yIQCOAQAAAA==.Dalvulpe:BAAANQADCgEIAQABNQAECgkJLQALAG4OAA==.Dankchop:BAABNQAECn8VAAMMAAYK5xiLGwCCAQAMAAYKHxWLGwCCAQANAAYKHRc7wAB8AQAAAA==.Darim:BAAANQADCgIIAgAAAA==.Darkbishop:BAAANQABCgYICgAAAA==.Darklink:BAAANQAECgQICQAAAA==.Dawnlighted:BAAANQADCgMIAwAAAA==.',
De='Deadlyshiet:BAAANQAECgMIBQABNQAFFAcIIQAHAHIWAA==.Defibrilater:BAAANQAECgQICAAAAA==.Demonfed:BAAANQABCgIIAgABNQADCgQICAAGAAAAAA==.Demonkrim:BAAANQADCgQIBAAAAA==.Demonlink:BAAANQADCgUIBQAAAA==.Denrin:BAAANQAECgUIEgAAAA==.Deskpop:BAAANQADCgQIBAAAAA==.',
Di='Diabolikal:BAAANQADCgYIDAAAAA==.Dill:BAABNQAECn85AAIOAAoK8CKIAADVAwAOAAoK8CKIAADVAwAAAA==.Divinesmite:BAAANQABCgcICAAAAA==.',
Dm='Dmachine:BAABNQAECn8YAAMNAAcKYhK6rwClAQANAAcK7g+6rwClAQAMAAIKhhRZFgB9AAABNQAFFAcIGgAPAPkeAA==.',
Do='Dondeezy:BAAANQADCgYIBgAAAA==.',
Dr='Drdru:BAABNQAECn8lAAIQAAgKKxv7IAAhAgAQAAgKKxv7IAAhAgABNQADCgUIBQAGAAAAAA==.Dreadshade:BAAANQAECgIIAgAAAA==.Drlittle:BAAANQADCgQIBAAAAA==.Dropfort:BAAANQAECggIDgAAAA==.Drscruffles:BAAANQADCgcIBwAAAA==.Drstress:BAAANQADCgIIAQAAAA==.',
Du='Duifean:BAAANQADCgYICgABNQAECgYICwAGAAAAAA==.Durkidurk:BAAANQADCgMIAwAAAA==.',
Dy='Dyabolykal:BAAANQADCgQIBAABNQADCgYIDAAGAAAAAA==.',
Ea='Easily:BAAANQAECgYIDgAAAA==.',
El='Ellyanthia:BAAANQAECgYICQAAAA==.',
Em='Emachine:BAAANQADCgcIBwABNQAFFAcIGgAPAPkeAA==.',
Ex='Exio:BAAANQAECgQJCgAAAA==.Extenze:BAAANQAECgEIAQAAAA==.',
Fa='Fastasheet:BAACNQAFFH8hAAIHAAcKchY8AwA4AgAHAAcKchY8AwA4AgA1AAQKfzAAAgcACgpOJHwFAHoDAAcACgpOJHwFAHoDAAAA.',
Fe='Feralfed:BAAANQADCgUIBQABNQADCgQICAAGAAAAAA==.',
Fi='Fill:BAABNQAECn8rAAIRAAoK8iO5AQCdAwARAAoK8iO5AQCdAwABNQAFFAQICQAHAGghAA==.',
Fl='Flehtwo:BAACNQAFFH8WAAMSAAYK4grEAwAmAQASAAUK4grEAwAmAQAIAAIKrQzLIQCGAAA1AAQKfy0AAxIACgqUGwk2AJ8CABIACQo7HQk2AJ8CAAgACQqtCROEAIABAAAA.Flehunter:BAAANQAECgcICQAAAA==.Flyinbanana:BAAANQADCgQIBAABNQAECgoKLwATAGwaAA==.',
Fo='Fortypi:BAAANQAECgYIBgABNQAFFAQICQAHAGghAA==.',
Fr='Fraglen:BAAANQADCgUIBQABNQAECgcICgAGAAAAAA==.Frags:BAAANQAECgcICgAAAA==.Fránknárf:BAAANQAECgEIAQAAAA==.',
Ge='Genjyosanzo:BAAANQAECgYIEAAAAA==.',
Gh='Ghostkrim:BAAANQADCgUIBQAAAA==.',
Gi='Gilljoww:BAABNQAECn8bAAIUAAgKSx9XKgByAgAUAAgKSx9XKgByAgAAAA==.Gireigtulb:BAAANQADCgYIBgAAAA==.',
Gn='Gnz:BAAANQAECgEIAQAAAA==.Gnzz:BAABNQAECn8kAAQFAAoKrhXrLwBhAQAFAAoK4RPrLwBhAQAVAAQKLxQkGQAtAQAWAAEKAAAfDgAxAAAAAA==.',
Go='Gocirr:BAAANQAECgUIDgAAAA==.',
Gr='Grito:BAAANQADCgYICgAAAA==.',
Ha='Haehn:BAAANQADCgMIAwAAAA==.Halstorm:BAAANQAECgYIDwAAAA==.Harrysax:BAAANQABCgYIBgAAAA==.',
He='Hedrake:BAAANQAECgQIBQAAAA==.Hexxytime:BAAANQADCgQIBAAAAA==.',
Hi='Hilazy:BAAANQAECgIIAwAAAA==.',
Hm='Hm:BAAANQAECgEIAQAAAA==.',
Ho='Holyfed:BAAANQADCgQICAAAAA==.Holyphok:BAAANQAECgMIAwAAAA==.Hotdog:BAAANQAECgcIBQAAAA==.',
Ic='Icestormy:BAAANQAECgMIAwAAAA==.',
Ih='Ihavenofutur:BAAANQAECgYIDQAAAA==.',
Il='Iliil:BAABNQAECn8yAAIUAAoKMiGYAQDPAgAUAAoKMiGYAQDPAgAAAA==.Illbiteyou:BAAANQADCgQIBAAAAA==.Illidantwo:BAACNQAFFH8YAAIEAAcKIheIBAAjAgAEAAcKIheIBAAjAgA1AAQKfzQAAgQACgqZI6IFAJoDAAQACgqZI6IFAJoDAAAA.',
Im='Imprints:BAAANQAECgYIEgAAAA==.',
In='Inuk:BAAANQAECgYIEwAAAA==.',
Ir='Ironshaman:BAAANQAECgYIEQAAAA==.',
It='Italianapee:BAAANQAECgQIBAABNQAECgYIEwAGAAAAAA==.',
Ja='Jabu:BAAANQADCgQIAwABNQAECgIIBgAGAAAAAA==.Jada:BAAANQAECgQICwAAAA==.Jaghatai:BAAANQADCgIIAgAAAA==.',
Je='Jenstonedart:BAABNQAECn8ZAAIXAAYKmQ/pCwDgAAAXAAYKmQ/pCwDgAAAAAA==.Jeryeth:BAABNQAECn8cAAINAAkKwR7EPwDLAgANAAkKwR7EPwDLAgAAAA==.Jerymander:BAAANQAFFAEIAQAAAA==.Jeryzard:BAAANQADCgYIDAAAAA==.',
Ji='Jiannybon:BAAANQADCgQICwAAAA==.',
Ju='Judgmental:BAAANQADCgYIBgAAAA==.Judidench:BAABNQAECn8XAAIYAAgKqCNIDgBGAwAYAAgKqCNIDgBGAwAAAA==.Juicewillis:BAAANQADCgIIAgAAAA==.',
Ka='Kain:BAECNQAFFH8XAAIKAAcKgyXKAACpAgAKAAcKgyXKAACpAgA1AAQKfy4AAwoACgr0JE4DAI4DAAoACQpiJk4DAI4DAAEABQrUGc8iAJgBAAAA.Kanda:BAAANQAECggIAQAAAA==.Kane:BAABNQAECn8hAAIUAAcK9hMcIAD8AAAUAAcK9hMcIAD8AAAAAA==.Karmasuture:BAAANQADCgYJBgABNQAECgMIAwAGAAAAAA==.Kaïn:BAAANQAECgMIBAABNQAECgoKOgABACsiAA==.',
Ke='Kelsí:BAAANQAECgMICQAAAA==.',
Ki='Kiwí:BAABNQAECn8oAAIFAAkKNR06CABGAgAFAAkKNR06CABGAgAAAA==.',
Kr='Krasavice:BAABNQAECn8xAAIZAAkKmhqzEwDUAQAZAAkKmhqzEwDUAQAAAA==.Krenik:BAAANQADCggIHwAAAA==.Krimdin:BAAANQADCgEIAQAAAA==.Krimdrood:BAAANQADCgMIAwAAAA==.Krimshadow:BAAANQADCgQIBAAAAA==.Krimsonblade:BAAANQADCgQIBAAAAA==.Krimsondeath:BAAANQADCgQIBAAAAA==.Krimtohell:BAAANQAECgQICQAAAA==.Krisp:BAAANQAECgUIEQABNQADCgQICAAGAAAAAA==.',
Ku='Kurquaan:BAAANQADCggICAAAAA==.',
La='Lauranthalas:BAAANQAECgYIDgAAAA==.Lavenderhaze:BAAANQAECgQIBAAAAA==.',
Le='Leathal:BAABNQAECn8eAAIJAAYKTyCNUAApAgAJAAYKTyCNUAApAgAAAA==.Lemurshoes:BAAANQAECgIIAwAAAA==.Lemursneaker:BAABNQAECn8aAAIFAAgKKgW2EwFrAQAFAAgKKgW2EwFrAQAAAA==.Letsgomen:BAAANQADCgEIAQAAAA==.',
Li='Lightshock:BAAANQAECgMIBAAAAA==.Linkblade:BAAANQADCggIDgAAAA==.Linkdin:BAAANQAECgQIBAAAAA==.Linkdrood:BAAANQADCggIGAAAAA==.Linkoflife:BAAANQADCgIIBAAAAA==.',
Ll='Llaagg:BAAANQAECgIIAgAAAA==.',
Lo='Lokust:BAABNQAECn8eAAIIAAYKqSGFJgBJAQAIAAYKqSGFJgBJAQAAAA==.',
Lu='Lucentdawn:BAABNQAECn8fAAIJAAcKfRVmHgBxAQAJAAcKfRVmHgBxAQAAAA==.Luckyshrine:BAAANQABCggICwAAAA==.Ludachris:BAAANQAECgEIAQAAAA==.',
Ly='Lycanius:BAABNQAECn8wAAMXAAkKrht/BgAFAwAXAAkKrht/BgAFAwALAAEKswLEcgAZAAAAAA==.Lynqii:BAACNQAFFH8NAAMPAAcKYRHHCQDNAQAPAAYK+RPHCQDNAQAaAAEKAQdkIQBHAAA1AAQKfxUAAw8ABgrkHx6TALYBAA8ABgrkHx6TALYBABoAAQoVG5hrAEkAAAAA.',
Ma='Macaco:BAAANQADCgYIBgAAAA==.Malirra:BAABNQAECn8dAAIFAAoKmgQIgwC8AAAFAAoKmgQIgwC8AAAAAA==.Malëk:BAABNQAECn86AAIBAAoKKyKPHQBNAwABAAoKKyKPHQBNAwAAAA==.Maximus:BAAANQADCgUIBQAAAA==.',
Me='Mechatholic:BAAANQAECgYIEAAAAA==.Medallis:BAAANQABCgcIDwAAAA==.Mellowlizard:BAACNQAFFH8aAAMPAAcK+R6pBQAUAgAPAAYKYh2pBQAUAgAaAAEKViV6FABnAAA1AAQKfycAAw8ACgqTIDUkAPMCAA8ACQqMIDUkAPMCABoAAwr2HtU7ANIAAAAA.Metuss:BAABNQAECn8VAAMHAAYKJR8dJAAFAgAHAAYKJR8dJAAFAgAbAAUKkxmKIgBvAQAAAA==.',
Mi='Miguel:BAAANQAECgUIDgAAAA==.Mira:BAABNQAECn8YAAIZAAgKkA2tpAC8AQAZAAgKkA2tpAC8AQAAAA==.',
Mk='Mkicon:BAABNQAECn8eAAIVAAYKvx/TCQAxAgAVAAYKvx/TCQAxAgAAAA==.Mkultra:BAABNQAECn8WAAMYAAkK2h14JgCjAgAYAAkKfBx4JgCjAgAUAAUKTh3DVgCYAQAAAA==.',
Mo='Mogmoog:BAABNQAECn8aAAIYAAYKHhTNIADnAAAYAAYKHhTNIADnAAAAAA==.Mooganfreman:BAAANQAECgEIAQAAAA==.Moonangel:BAABNQAECn8dAAIcAAcKehfSCgB3AQAcAAcKehfSCgB3AQAAAA==.Morbodan:BAABNQAECn8uAAIcAAoKTCHrAADnAgAcAAoKTCHrAADnAgAAAA==.Mornangus:BAAANQABCgMIAwAAAA==.Moshpit:BAAANQAFFAEIAQAAAA==.Motone:BAAANQAECgQIBAAAAA==.',
Mu='Multanni:BAABNQAECn8fAAISAAkKaRRiEQCLAQASAAkKaRRiEQCLAQAAAA==.',
My='Mykanoid:BAAANQAECggICQABNQAECgoKLwATAGwaAA==.Myonecrosis:BAABNQAECn8eAAIPAAcKjiDEEgCvAQAPAAcKjiDEEgCvAQAAAA==.',
Na='Nakrog:BAABNQAECn8iAAMMAAgKghoNEAAoAgAMAAgKghoNEAAoAgANAAEKkBplRgFEAAAAAA==.Napster:BAAANQAECgMIAwAAAA==.Nasa:BAACNQAFFH8XAAIHAAcKRA2OBQDGAQAHAAcKRA2OBQDGAQA1AAQKfyQAAgcACQrIHk8WAJ0CAAcACQrIHk8WAJ0CAAAA.',
Ne='Nellarixi:BAABNQAECn8aAAIdAAgKQhz2HQBQAgAdAAgKQhz2HQBQAgAAAA==.Nethus:BAAANQADCgcJCQAAAA==.',
Ni='Niivalyr:BAAANQABCgIJAQAAAA==.Nimbus:BAAANQAECgEIAQABNQAFFAcIGgASADwXAA==.',
No='Nodens:BAAANQADCgcIEwAAAA==.Nomaa:BAABNQAECn8dAAIeAAcKkAJZCQCPAAAeAAcKkAJZCQCPAAAAAA==.Nomäd:BAAANQAECgYIDgAAAA==.Nosneb:BAAANQADCgMIBAABNQADCggIEAAGAAAAAA==.',
Ny='Nytedevil:BAAANQAECgYIEAAAAA==.',
['Nì']='Nìtsua:BAAANQADCggIEAAAAA==.',
Ob='Obilivion:BAAANQADCgYICgAAAA==.',
Og='Ogmount:BAAANQAECgMIAwAAAA==.',
Or='Orflame:BAABNQAECn8bAAMTAAgKeQeuKABvAQATAAgKeQeuKABvAQAfAAEKKgXpJAAxAAAAAA==.',
Ph='Phantomhealz:BAAANQABCgIIAgAAAA==.Phrash:BAACNQAFFH8JAAIHAAQKaCFdCgAeAQAHAAQKaCFdCgAeAQA1AAQKfxkAAgcACQrgI2UJADsDAAcACQrgI2UJADsDAAAA.',
Pi='Pigbearmans:BAAANQADCgYIBgAAAA==.',
Pl='Plex:BAAANQADCgQIBAABNQAECgkJIAAgAGEgAA==.',
Po='Pooldan:BAAANQAECgMJAgAAAA==.',
Pr='Praystatioñ:BAABNQAECn8kAAIhAAkKWhkPBQBmAgAhAAkKWhkPBQBmAgAAAA==.Premiumgank:BAAANQAECgIIAgAAAA==.Prtanks:BAAANQAECgMIBgAAAA==.',
Pu='Purerform:BAAANQADCgcIBwAAAA==.',
Qu='Quelidra:BAAANQADCgUIBQAAAA==.Quepaspete:BAAANQADCgYIBwAAAA==.',
Ra='Raa:BAABNQAECn80AAIZAAkKhhoeJAAGAwAZAAkKhhoeJAAGAwAAAA==.Racker:BAAANQAECgUIDAAAAA==.Ragou:BAAANQADCgQIBAAAAA==.Rainfallen:BAAANQAECggIDwAAAA==.',
Re='Rengots:BAAANQAECgEIAQAAAA==.Rephtide:BAAANQAECgYIDwAAAA==.Responsible:BAABNQAECn8oAAINAAoK6h/QEwC8AQANAAoK6h/QEwC8AQAAAA==.',
Rh='Rhaez:BAAANQAECgEIAQAAAA==.Rhall:BAAANQADCgYIBgAAAA==.Rhetoricdork:BAAANQAECggICAABNQAFFAcIGQAFAOMfAA==.',
Ro='Rocktober:BAAANQAECgEIAQAAAA==.Rogmash:BAAANQAECgUJCwAAAA==.Rokkoz:BAABNQAECn8hAAIQAAkKfhuXBQABAgAQAAkKfhuXBQABAgAAAA==.Romer:BAACNQAFFH8FAAIiAAIKOQGpCgBPAAAiAAIKOQGpCgBPAAA1AAQKfyMAAiIACQqFCCQWAIEBACIACQqFCCQWAIEBAAAA.Rompintom:BAAANQAECgIIAgAAAA==.Rookiestar:BAABNQAECn8VAAIjAAgKvAvuHwDpAAAjAAgKvAvuHwDpAAAAAA==.',
Ru='Rumí:BAAANQAECgQIBwABNQAECgYICQAGAAAAAA==.',
Sa='Sabb:BAAANQADCgYIEAAAAA==.Samstephens:BAAANQADCgQIBAABNQAECgYICwAGAAAAAA==.Saphroniå:BAAANQADCgcIGQAAAA==.Sass:BAABNQAECn82AAMkAAoKBRtcMABeAgAkAAgKvhpcMABeAgAQAAQKCBAcJwClAAAAAA==.Sazed:BAAANQADCgEIAQAAAA==.',
Sc='Schend:BAAANQADCgYICwAAAA==.',
Se='Sed:BAAANQAECgIIBQAAAA==.Serrana:BAAANQADCgUIBQAAAA==.',
Sf='Sfinktor:BAAANQADCgUIBAAAAA==.',
Sh='Shadowmortis:BAAANQAECgQIBQAAAA==.Shadowwilder:BAAANQAECgUICgAAAA==.Shirokhan:BAABNQAECn8lAAIFAAkKixS0iABtAgAFAAkKixS0iABtAgAAAA==.Shootum:BAAANQADCgUIBgAAAA==.Shïfthappens:BAAANQADCgUIBQAAAA==.',
Si='Sidewinderx:BAAANQAECgQIBgAAAA==.Sinlock:BAABNQAECn8dAAMPAAgK3B5NZAAtAgAPAAcKTR9NZAAtAgAaAAQKMxH7NADvAAAAAA==.',
Sk='Skadí:BAAANQAECgQIBQAAAA==.Skrot:BAAANQADCgYIBgABNQAECgoKJQAHAPoVAA==.',
Sm='Smef:BAAANQADCgEIAQAAAA==.',
Sn='Snagglespark:BAABNQAECn8nAAMSAAoKex1ZHgAVAwASAAoKex1ZHgAVAwAIAAYKQQvFtQACAQAAAA==.Sneakykrim:BAAANQABCgEIAQAAAA==.Sneakylink:BAAANQADCgYIEQAAAA==.Snowbunni:BAAANQAECgQIAwAAAA==.',
So='Soladrian:BAAANQAECgcIDAAAAA==.Solanthion:BAEANQADCgcIBwABNQAECggIEAAGAAAAAA==.',
Sp='Spankyee:BAAANQADCgQIBAAAAA==.',
Sr='Srtaco:BAAANQAECgUICAAAAA==.',
St='Starz:BAAANQADCgYIBAAAAA==.Stelmaria:BAAANQAECgMIAwABNQAECgoKJQAZAOYZAA==.',
Su='Sunchipzz:BAAANQADCgQIBAAAAA==.Sundayschool:BAAANQAECgcIEgAAAA==.Sunwing:BAAANQAECgIIAgAAAA==.',
Sy='Syyia:BAAANQADCgIIAgAAAA==.',
['Sé']='Séraph:BAAANQAECgUIBwAAAA==.',
['Só']='Sóozabimaru:BAAANQAECgQICQAAAA==.',
Ta='Tahano:BAAANQABCgIIAgAAAA==.Talljeff:BAAANQAECggIDgAAAA==.Tankarmor:BAABNQAECn8eAAIMAAYK1g0dHwBZAQAMAAYK1g0dHwBZAQAAAA==.Taylorswif:BAACNQAFFH8HAAMFAAQKrQynLQAjAQAFAAQKrQynLQAjAQAVAAEKSAfzFQA+AAA1AAQKfyAAAgUACQowGlpoAK0CAAUACQowGlpoAK0CAAAA.',
Tc='Tcharta:BAABNQAECn8vAAMTAAoKbBp/AQB/AgATAAoKbBp/AQB/AgAlAAEKAAA6QAArAAAAAA==.',
Th='Thefamousone:BAAANQADCgYICAAAAA==.Theiá:BAAANQAECgEIAQAAAA==.Thermotide:BAAANQAECgcIEAAAAA==.Thornpaw:BAAANQADCgQIBAAAAA==.Thoror:BAAANQAECgUICgAAAA==.Thunderbolt:BAAANQADCgcIBwABNQAECgQIBAAGAAAAAA==.Thundernütz:BAAANQADCgIIAwAAAA==.Thymós:BAAANQAECgUIDAAAAA==.',
Ti='Tiffina:BAAANQADCgYICQAAAA==.Tiffzen:BAABNQAECn8WAAIZAAcKOAdX3ABIAQAZAAcKOAdX3ABIAQAAAA==.Timeskip:BAAANQADCggIBgAAAA==.Tinyfaith:BAAANQAECgQICAAAAA==.Titum:BAABNQAECn8UAAIPAAkKQBf6OgCjAgAPAAkKQBf6OgCjAgABNQAFFAYIDAAFAOYIAA==.',
To='Tongpooh:BAABNQAECn8lAAIHAAoK+hU9GACHAgAHAAoK+hU9GACHAgAAAA==.',
Tr='Treeberk:BAAANQAECgIIAgAAAA==.Truelink:BAAANQADCggIEgAAAA==.',
Tu='Tuba:BAAANQAECggIAwAAAA==.Tuckerherout:BAAANQAECgYIEAAAAA==.Tundro:BAAANQADCgcIDQAAAA==.',
Tw='Twix:BAAANQAECgIIAgABNQAECgQJCgAGAAAAAA==.',
['Tî']='Tîtån:BAABNQAECn8ZAAMaAAYKfwvRIgBbAQAaAAYKfwvRIgBbAQAeAAEKAACDNgAbAAAAAA==.',
Uh='Uh:BAABNQAECn8aAAImAAgK8R2VIgB6AgAmAAgK8R2VIgB6AgABNQAFFAQICQAHAGghAA==.',
Un='Undeadlock:BAAANQAECgUIEAAAAA==.',
Va='Vale:BAAANQADCgEIAQAAAA==.',
Vg='Vgmking:BAABNQAECn8pAAIUAAkKBBeSQAD8AQAUAAkKBBeSQAD8AQAAAA==.',
Vi='Vigdis:BAAANQADCgcIBwAAAA==.Vindorei:BAAANQADCgUIDgAAAA==.',
Vo='Voidfed:BAAANQADCgQIBAABNQADCgQICAAGAAAAAA==.Voidfu:BAAANQADCgIIAgAAAA==.Vokzhen:BAABNQAECn8tAAIdAAgKshxEAwDoAQAdAAgKshxEAwDoAQAAAA==.Volescu:BAAANQAECgUIDwAAAA==.',
Wa='Walkerboah:BAAANQAECgYIEgAAAA==.Warmachinne:BAAANQAECgEIAQAAAA==.',
We='Weel:BAABNQAECn8tAAIJAAoKwRPRLgAnAQAJAAoKwRPRLgAnAQAAAA==.',
Wo='Wolfspider:BAAANQAECgIIAwAAAA==.',
Wy='Wyland:BAAANQAECgMIBQAAAA==.Wylander:BAABNQAECn8YAAIJAAcKJCIlDAADAgAJAAcKJCIlDAADAgAAAA==.Wylandvoker:BAAANQADCgIIAgAAAA==.',
Xa='Xanun:BAAANQADCgMIAwAAAA==.',
Xe='Xeri:BAABNQAECn8YAAIRAAkKORvUCwCzAgARAAkKORvUCwCzAgABNQAFFAcIGAAnALgiAA==.Xeromus:BAABNQAECn8bAAMkAAcKQA/yGQATAQAkAAcKQA/yGQATAQAQAAEKxQO5fgAiAAAAAA==.Xetsus:BAAANQADCgUJBQAAAA==.',
Ya='Yang:BAAANQABCgEIAQAAAA==.',
Yo='Yoink:BAAANQADCgUIBQAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Yv='Yvelmaya:BAABNQAECn8dAAMIAAcKJBzSEQDIAQAIAAcKJBzSEQDIAQASAAEKAAAJUAEmAAAAAA==.',
Za='Zabawaba:BAAANQAECgMIAgABNQAECggIDgAGAAAAAA==.Zaboomaprune:BAABNQAECn8XAAMLAAcKAAkYNgD1AAALAAYKAAkYNgD1AAAXAAQKwwFdOABcAAAAAA==.Zarika:BAACNQAFFH8YAAInAAcKuCI+AACBAgAnAAcKuCI+AACBAgA1AAQKfywAAicACgpzJVYAANkDACcACgpzJVYAANkDAAAA.Zarì:BAAANQAECgUIBwABNQAFFAcIGAAnALgiAA==.',
Ze='Zeknull:BAABNQAECn8dAAMJAAgKTRwJOQCAAgAJAAgKTRwJOQCAAgABAAUKYg8xAgEcAQAAAA==.Zekthal:BAAANQAECggICgABNQAECggIHQAJAE0cAA==.Zenio:BAAANQADCgIIAgAAAA==.Zennah:BAAANQADCggIFgAAAA==.Zephy:BAAANQADCgcJCQAAAA==.',
Zr='Zrgl:BAAANQADCggICAAAAA==.',
['Zä']='Zäo:BAACNQAFFH8FAAIPAAIK6xcdLwCbAAAPAAIK6xcdLwCbAAA1AAQKfyQABB4ACQphItgBACcDAB4ACQo7H9gBACcDAA8ABQq7HTqiAJEBABoAAwo8I2g5ANsAAAAA.',
['Ïk']='Ïkea:BAAANQAECgQIBwAAAA==.',
['ßl']='ßloodhunter:BAAANQAECgIIAQAAAA==.',
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
