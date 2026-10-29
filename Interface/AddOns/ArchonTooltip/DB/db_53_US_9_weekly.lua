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

local lookup = {'Warlock-Demonology','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Mage-Arcane','Unknown-Unknown','Monk-Windwalker','Shaman-Restoration','Paladin-Holy','Monk-Mistweaver','Paladin-Protection','Druid-Guardian','Warrior-Protection','Warrior-Arms','Warrior-Fury','Druid-Restoration','Shaman-Elemental','Shaman-Enhancement','Evoker-Preservation','Priest-Shadow','DeathKnight-Blood','Mage-Frost','Mage-Fire','Rogue-Assassination','Druid-Feral','DeathKnight-Unholy','Hunter-BeastMastery','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Monk-Brewmaster','Rogue-Subtlety','Druid-Balance','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Acupuncher:BAAANQAECgIIAgAAAA==.',
Ad='Adamsandler:BAAANQADCggICAAAAA==.Adiwolf:BAAANQAECgIIBAAAAA==.',
Al='Alcha:BAABNQAECn8XAAIBAAcKXBvsQACmAQABAAcKXBvsQACmAQAAAA==.Alenndar:BAAANQADCgEIAQAAAA==.Alexdaddario:BAAANQAECgcIEQAAAA==.Algaefungi:BAAANQAECgIICAAAAA==.Althena:BAAANQAECgEIAQABNQAECgoKPgACACsiAA==.Alystana:BAAANQADCgUIBwAAAA==.',
Am='Amberelle:BAAANQADCgQIBAAAAA==.',
An='Anastera:BAAANQADCgYIBwAAAA==.Animeniac:BAABNQAECn8kAAIDAAcKRCMuBQDkAQADAAcKRCMuBQDkAQAAAA==.Anticlimax:BAABNQAECn8mAAQEAAkKgA4MIQAgAQAEAAcKEw8MIQAgAQADAAYK1Ay4GQAZAQAFAAQKPAoKdwCeAAAAAA==.Antilaw:BAAANQAECgEIAgAAAA==.Antisocial:BAAANQAECgQIDQAAAA==.Antistab:BAAANQAECgQICgAAAA==.',
Ao='Aoibhneas:BAAANQADCgcIBwAAAA==.',
Ap='Apprentice:BAACNQAFFH8HAAIGAAMKkho5MAAOAQAGAAMKkho5MAAOAQA1AAQKfx4AAgYACQoXJNAzACMDAAYACQoXJNAzACMDAAAA.',
Ar='Ariha:BAAANQAECgQIBQAAAA==.Arnokk:BAAANQADCgYIBgAAAA==.Artrael:BAAANQADCggJCAAAAA==.',
At='Atorim:BAAANQADCgIIAgABNQAECgQIBgAHAAAAAA==.',
Av='Avienndha:BAABNQAECn8kAAIDAAcKfhrPCgAyAQADAAcKfhrPCgAyAQAAAA==.Avriel:BAAANQAECgQICQABNQAECgoKPgACACsiAA==.',
Ba='Barbatos:BAAANQAECgIIAgAAAA==.',
Be='Beardeddrunk:BAAANQADCgUJBQAAAA==.Beornwildlaw:BAAANQABCgcIDgAAAA==.',
Bi='Bigsheet:BAAANQAECgUIBwABNQAFFAgIIwAIAFMXAA==.',
Bl='Bloodyflame:BAAANQADCgEIAQAAAA==.',
Bo='Bobbytofva:BAAANQAECgMIBAAAAA==.Bobthedurgon:BAAANQADCgUIBQAAAA==.Bobthegrinch:BAAANQADCgQIBAAAAA==.Boneloss:BAAANQADCgQIBAAAAA==.Bonkini:BAAANQAECggIDgAAAA==.Boochaka:BAABNQAECn8jAAIJAAkKNhttJQAhAgAJAAkKNhttJQAhAgAAAA==.Bouman:BAAANQADCgYIBgAAAA==.Bouquet:BAABNQAECn8cAAIGAAgK1QSXmAATAQAGAAgK1QSXmAATAQAAAA==.',
Br='Brewdog:BAAANQAECgQICgAAAA==.Brickfists:BAAANQADCgQIBwAAAA==.Brotherfuzz:BAAANQAECgMIAwAAAA==.',
Bu='Buckangel:BAAANQAECggIDAABNQAFFAcIBwAKAO4iAA==.Busterposer:BAABNQAECn8UAAIFAAoKEh8/CQC/AgAFAAoKEh8/CQC/AgAAAA==.',
Ca='Caelvaris:BAAANQADCgEIAQAAAA==.Calabooca:BAAANQADCgUICAAAAA==.Canadaclown:BAAANQADCgIIAgAAAA==.Candor:BAAANQADCgUIBQAAAA==.',
Ch='Cheesefries:BAABNQAECn8cAAILAAcK1RnqDwB+AQALAAcK1RnqDwB+AQAAAA==.Chereth:BAAANQAECggIDQAAAA==.Chratos:BAAANQADCgYIBgAAAA==.',
Cl='Clapt:BAAANQAECgEIAQAAAA==.Clapton:BAAANQAECgQICQAAAA==.Claptone:BAABNQAECn8UAAIJAAYKYxW3hwB3AQAJAAYKYxW3hwB3AQAAAA==.',
Co='Corpuscle:BAABNQAECn8iAAMMAAkKbhi+DADaAQAMAAkKbhi+DADaAQAKAAIKogoPDwFZAAAAAA==.',
Cr='Critcomander:BAABNQAECn8rAAICAAkKcQ0yrADHAQACAAkKcQ0yrADHAQAAAA==.Critties:BAAANQADCgMIAwAAAA==.Crowfive:BAAANQAECgYIBQAAAA==.Crueldin:BAABNQAECn8XAAMKAAYK2hC1lwBaAQAKAAYK2hC1lwBaAQACAAEKkws4nAE5AAAAAA==.',
Da='Dalsen:BAABNQAECn8xAAINAAkKBw9yIQCOAQANAAkKBw9yIQCOAQAAAA==.Dalvulpe:BAAANQADCgEIAQABNQAECgkJMQANAAcPAA==.Dankchop:BAABNQAECn8WAAMOAAYK5xiLGwCCAQAOAAYKHxWLGwCCAQAPAAYKHRc7wAB8AQAAAA==.Darim:BAAANQADCgIIAgAAAA==.Darkbishop:BAAANQABCgYICgAAAA==.Darklink:BAAANQAECgQIDAAAAA==.Dawnlighted:BAAANQADCgMIAwAAAA==.',
De='Deadlyshiet:BAAANQAECgMIBQABNQAFFAgIIwAIAFMXAA==.Defibrilater:BAAANQAECgQICAAAAA==.Demonfed:BAAANQABCgIIAgABNQADCgQICAAHAAAAAA==.Demonkrim:BAAANQADCgQIBAAAAA==.Demonlink:BAAANQADCgUIBQAAAA==.Denrin:BAAANQAECgYIEgAAAA==.Depressed:BAAANQABCgEIAQAAAA==.Deskpop:BAAANQADCgQIBAAAAA==.',
Di='Diabolikal:BAAANQADCgYIDAAAAA==.Dill:BAABNQAECn9DAAIQAAoKdSOIAADVAwAQAAoKdSOIAADVAwAAAA==.Divinesmite:BAAANQADCgEIAQAAAA==.',
Dm='Dmachine:BAABNQAECn8iAAMPAAoKFBJFOADxAQAPAAoKwRBFOADxAQAOAAIKhhTxIgB4AAABNQAFFAcIGgABAPkeAA==.',
Do='Dondeezy:BAAANQADCgYIBgAAAA==.',
Dr='Drdru:BAABNQAECn8tAAIRAAkKvRvCCQCoAgARAAkKvRvCCQCoAgABNQADCgUIBQAHAAAAAA==.Dreadshade:BAAANQAECgYIBwAAAA==.Drlittle:BAAANQADCgQIBAAAAA==.Dropfort:BAAANQAECggIDwAAAA==.Drscruffles:BAAANQADCgcIBwAAAA==.Drstress:BAAANQADCgEIAQAAAA==.',
Du='Duifean:BAAANQADCgYICgABNQAECgcIFQASAAUFAA==.Durkidurk:BAAANQADCgMIAwAAAA==.',
Dy='Dyabolykal:BAAANQADCgQIBAABNQADCgYIDAAHAAAAAA==.',
Ea='Easily:BAAANQAECgYIDgAAAA==.',
El='Ellyanthia:BAAANQAECgYICQAAAA==.',
Em='Emachine:BAAANQADCgcIBwABNQAFFAcIGgABAPkeAA==.',
Ex='Exio:BAAANQAECgQJCgAAAA==.Extenze:BAAANQAECgQIBAAAAA==.',
Fa='Fastasheet:BAACNQAFFH8jAAIIAAgKUxc8AwA4AgAIAAgKUxc8AwA4AgA1AAQKfzoAAggACgqXJTECADwDAAgACgqXJTECADwDAAAA.',
Fe='Feralfed:BAAANQAECgEIAQABNQADCgQICAAHAAAAAA==.',
Fi='Fill:BAABNQAECn8rAAITAAoK9yO5AQCdAwATAAoK9yO5AQCdAwABNQAFFAQICQAIAGghAA==.',
Fl='Flehtwo:BAACNQAFFH8XAAMSAAcKgwn7AwBjAQASAAYKgwn7AwBjAQAJAAIKrQzLIQCGAAA1AAQKfzMAAxIACgrfGwk2AJ8CABIACgrfGwk2AJ8CAAkACQrRDBOEAIABAAAA.Flehunter:BAAANQAECgcIEAAAAA==.Flyinbanana:BAAANQADCgQIBAABNQAECgoKNgAUAFscAA==.',
Fo='Fortypi:BAAANQAECgYIBgABNQAFFAQICQAIAGghAA==.',
Fr='Fragilelimbs:BAAANQAECgYIBgAAAA==.Fraglen:BAAANQADCgUIBQABNQAECgcICgAHAAAAAA==.Frags:BAAANQAECgcICgAAAA==.Fránknárf:BAAANQAECgEIAQAAAA==.',
Ge='Genjyosanzo:BAABNQAECn8bAAIVAAcKzgjnIwDnAAAVAAcKzgjnIwDnAAAAAA==.',
Gh='Ghostkrim:BAAANQADCgUIBQAAAA==.',
Gi='Gilljoww:BAABNQAECn8bAAIWAAgKSx9XKgByAgAWAAgKSx9XKgByAgAAAA==.Gireigtulb:BAAANQADCgYIBgAAAA==.',
Gn='Gnz:BAAANQAECgEIAQAAAA==.Gnzz:BAABNQAECn8mAAQXAAoKChckGQAtAQAGAAoK4RPRfwBDAQAXAAUKEhUkGQAtAQAYAAEKAAAfDgAxAAAAAA==.',
Go='Gocirr:BAAANQAECgUIEwAAAA==.',
Gr='Grito:BAAANQADCgYICgAAAA==.',
Ha='Haehn:BAAANQADCgMIAwAAAA==.Halstorm:BAAANQAECgcIEQAAAA==.Harrysax:BAAANQABCgYIBgAAAA==.',
He='Hedrake:BAAANQAECgcICQAAAA==.Hexxytime:BAAANQADCgQIBAAAAA==.',
Hi='Hilazy:BAAANQAECgIIAwAAAA==.Hitzel:BAAANQAECgIIAgAAAA==.',
Hm='Hm:BAAANQAECgEIAQAAAA==.',
Ho='Holyfed:BAAANQADCgQICAAAAA==.Holyphok:BAAANQAECgMIAwAAAA==.Hotdog:BAAANQAECggIDgAAAA==.',
Ic='Icestormy:BAAANQAECgMIAwAAAA==.',
Ih='Ihavenofutur:BAAANQAECgcIEwAAAA==.',
Il='Iliil:BAABNQAECn86AAIWAAoKmyIXDQBIAwAWAAoKmyIXDQBIAwAAAA==.Illbiteyou:BAAANQADCgQIBAAAAA==.Illidantwo:BAACNQAFFH8YAAIFAAcKIheIBAAjAgAFAAcKIheIBAAjAgA1AAQKfz4AAgUACgr3I6IFAJoDAAUACgr3I6IFAJoDAAAA.',
Im='Imprints:BAABNQAECn8XAAIPAAgKBAZD1gBDAQAPAAgKBAZD1gBDAQAAAA==.',
In='Inuk:BAAANQAECgYIEwAAAA==.',
Ir='Ironshaman:BAAANQAECgYIEQABNQAECgoKOAAZAHQiAA==.',
It='Italianapee:BAAANQAECgQIBAABNQAECgYIEwAHAAAAAA==.',
Ja='Jabu:BAAANQADCgQIAwABNQAECgIIBgAHAAAAAA==.Jada:BAAANQAECgUIDAAAAA==.Jaghatai:BAAANQADCgIIAgAAAA==.',
Je='Jenstonedart:BAABNQAECn8fAAIaAAkKxg31DABhAQAaAAkKxg31DABhAQAAAA==.Jeryeth:BAABNQAECn8eAAIPAAkK1h7EPwDLAgAPAAkK1h7EPwDLAgAAAA==.Jerymander:BAAANQAFFAEIAQAAAA==.Jeryzard:BAAANQADCgYIDAAAAA==.',
Ji='Jiannybon:BAAANQADCgQICwAAAA==.',
Ju='Judgmental:BAAANQADCgYIBgAAAA==.Judidench:BAABNQAECn8XAAIbAAgKqCNIDgBGAwAbAAgKqCNIDgBGAwAAAA==.Juicewillis:BAAANQADCgIIAgAAAA==.',
Ka='Kain:BAECNQAFFH8XAAIMAAcKgyXKAACpAgAMAAcKgyXKAACpAgA1AAQKfzUAAwwACgr0JE4DAI4DAAwACQpiJk4DAI4DAAIABQrUGUpwAHMBAAAA.Kanda:BAAANQAECggIAQAAAA==.Kane:BAABNQAECn8jAAIWAAgK6BNjMwAcAQAWAAgK6BNjMwAcAQAAAA==.Karmasuture:BAAANQADCgYJBgABNQAECgMIAwAHAAAAAA==.Kaïn:BAAANQAECgMIBAABNQAECgoKPgACACsiAA==.',
Ke='Kelsí:BAAANQAECgMICQAAAA==.',
Ki='Kiwí:BAABNQAECn8sAAIGAAoKVR9oIgBuAgAGAAoKVR9oIgBuAgAAAA==.',
Kr='Krasavice:BAABNQAECn88AAIcAAoK5h24EQDBAgAcAAoK5h24EQDBAgAAAA==.Krenik:BAAANQADCggIHwAAAA==.Krimdin:BAAANQAECgMIAwAAAA==.Krimdrood:BAAANQADCgMIAwAAAA==.Krimshadow:BAAANQADCgcIBwAAAA==.Krimsonblade:BAAANQADCgQIBAAAAA==.Krimsondeath:BAAANQADCgQIBAAAAA==.Krimtohell:BAAANQAECgcIDwAAAA==.Krisp:BAAANQAECgYIEgABNQADCgQICAAHAAAAAA==.',
Ku='Kurquaan:BAAANQADCggICAAAAA==.',
La='Lauranthalas:BAABNQAECn8ZAAIcAAcKMAsSigAdAQAcAAcKMAsSigAdAQAAAA==.Lavenderhaze:BAAANQAECgQIBAAAAA==.',
Le='Leathal:BAABNQAECn8eAAIKAAYKTyCNUAApAgAKAAYKTyCNUAApAgAAAA==.Lemurshoes:BAAANQAECgIIAwAAAA==.Lemursneaker:BAABNQAECn8aAAIGAAgKKgW2EwFrAQAGAAgKKgW2EwFrAQAAAA==.Letsgomen:BAAANQADCgEIAQAAAA==.',
Li='Lightsfire:BAAANQABCgQIBAABNQAECgQICAAHAAAAAA==.Lightshock:BAAANQAECgQICAAAAA==.Linkblade:BAAANQADCggIDgAAAA==.Linkdin:BAAANQAECgQIBAAAAA==.Linkdrood:BAAANQAECgYIBgAAAA==.Linkoflife:BAAANQADCgIIBAAAAA==.',
Ll='Llaagg:BAAANQAECgIIAgAAAA==.',
Lo='Lokust:BAABNQAECn8jAAIJAAYKsSG/UwAYAgAJAAYKsSG/UwAYAgAAAA==.',
Lu='Lucentdawn:BAABNQAECn8jAAIKAAcKfRVHSQBxAQAKAAcKfRVHSQBxAQAAAA==.Luckyshrine:BAAANQABCggICwAAAA==.Ludachris:BAAANQAECgEIAQAAAA==.',
Ly='Lycanius:BAABNQAECn9AAAMaAAoKXht/BgAFAwAaAAoKXht/BgAFAwANAAEKswLEcgAZAAAAAA==.Lynqii:BAACNQAFFH8NAAMBAAcKYRHHCQDNAQABAAYK+RPHCQDNAQAdAAEKAQdkIQBHAAA1AAQKfxUAAwEABgrkHx6TALYBAAEABgrkHx6TALYBAB0AAQoVG5hrAEkAAAAA.',
Ma='Macaco:BAAANQADCgYIBgAAAA==.Malirra:BAABNQAECn8hAAIGAAoKswTpCgF7AQAGAAoKswTpCgF7AQAAAA==.Malëk:BAABNQAECn8+AAICAAoKKyKPHQBNAwACAAoKKyKPHQBNAwAAAA==.Maximus:BAAANQADCgUIBQAAAA==.',
Me='Mechatholic:BAAANQAECgcIEQAAAA==.Medallis:BAAANQABCgcIDwAAAA==.Mellowlizard:BAACNQAFFH8aAAMBAAcK+R6pBQAUAgABAAYKYh2pBQAUAgAdAAEKViV6FABnAAA1AAQKfy8ABAEACgo+JKsQAKMCAAEACgo+JKsQAKMCAB0AAwr2HtU7ANIAAB4AAQrBIT0UAGEAAAAA.Metuss:BAABNQAECn8WAAMIAAYKJR8dJAAFAgAIAAYKJR8dJAAFAgALAAUKkxmKIgBvAQAAAA==.',
Mi='Miguel:BAAANQAECgUIDgAAAA==.Mira:BAABNQAECn8eAAIcAAkKyA6ZXQCFAQAcAAkKyA6ZXQCFAQAAAA==.',
Mk='Mkicon:BAABNQAECn8kAAIXAAcKeB7TCQAxAgAXAAcKeB7TCQAxAgAAAA==.Mkultra:BAABNQAECn8aAAMbAAoKLx54JgCjAgAbAAoK/Rx4JgCjAgAWAAYKTh3DVgCYAQAAAA==.',
Mo='Mogmoog:BAABNQAECn8cAAIbAAYKHhQWaQBtAQAbAAYKHhQWaQBtAQAAAA==.Mooganfreman:BAAANQAECgEIAQAAAA==.Moonangel:BAABNQAECn8jAAIZAAcKZxkfEQB6AQAZAAcKZxkfEQB6AQAAAA==.Morbodan:BAABNQAECn84AAIZAAoKdCLVAQAhAwAZAAoKdCLVAQAhAwAAAA==.Mornangus:BAAANQABCgMIAwAAAA==.Moshpit:BAAANQAFFAEIAQAAAA==.Motone:BAAANQAECgQIBAAAAA==.',
Mu='Multanni:BAABNQAECn8oAAISAAkKZReAJADdAQASAAkKZReAJADdAQAAAA==.',
My='Mykanoid:BAABNQAECn8XAAIfAAkKexGwBwCaAQAfAAkKexGwBwCaAQABNQAECgoKNgAUAFscAA==.Myonecrosis:BAABNQAECn8kAAIBAAcKHSIAQgCiAQABAAcKHSIAQgCiAQAAAA==.',
Na='Nakrog:BAABNQAECn8iAAMOAAgKghoNEAAoAgAOAAgKghoNEAAoAgAPAAEKkBplRgFEAAAAAA==.Napster:BAAANQAECgMIAwAAAA==.Nasa:BAACNQAFFH8XAAIIAAcKRA2OBQDGAQAIAAcKRA2OBQDGAQA1AAQKfyQAAggACQrIHk8WAJ0CAAgACQrIHk8WAJ0CAAAA.',
Ne='Nellarixi:BAABNQAECn8aAAIVAAgKQhz2HQBQAgAVAAgKQhz2HQBQAgAAAA==.Nethus:BAAANQADCgcJCQAAAA==.',
Ni='Niivalyr:BAAANQABCgIIAQAAAA==.Nimbus:BAAANQAECgEIAQABNQAFFAcIGwASADwXAA==.',
No='Nodens:BAAANQADCgcIEwAAAA==.Nomaa:BAABNQAECn8jAAIeAAcKkAISGADMAAAeAAcKkAISGADMAAAAAA==.Nomäd:BAABNQAECn8XAAIQAAcK6xBLDQAiAQAQAAcK6xBLDQAiAQAAAA==.Nosneb:BAAANQADCgMIBAABNQADCggIEAAHAAAAAA==.',
Ny='Nytedevil:BAAANQAECgYIEQAAAA==.',
['Nì']='Nìtsua:BAAANQADCggIEAAAAA==.',
Ob='Obilivion:BAAANQAECgYIBgAAAA==.',
Og='Ogmount:BAAANQAECgMIAwAAAA==.',
Or='Orflame:BAABNQAECn8bAAMUAAgKeQeuKABvAQAUAAgKeQeuKABvAQAgAAEKKgXpJAAxAAAAAA==.',
Ph='Phantomhealz:BAAANQABCgIIAgAAAA==.Phrash:BAACNQAFFH8JAAIIAAQKaCFdCgAeAQAIAAQKaCFdCgAeAQA1AAQKfx0AAggACQr9JGUJADsDAAgACQr9JGUJADsDAAAA.',
Pi='Pigbearmans:BAAANQADCgYIBgAAAA==.',
Pl='Plex:BAAANQAECgYIBgABNQAECgkJIAAhAGEgAA==.',
Po='Pooldan:BAAANQAECgMJAgAAAA==.',
Pr='Praystatioñ:BAABNQAECn8qAAIiAAoKhBkPBQBmAgAiAAoKhBkPBQBmAgAAAA==.Premiumgank:BAAANQAECgIIAgAAAA==.Priestlink:BAAANQADCgcIGAAAAA==.Prtanks:BAAANQAECgMIBgAAAA==.',
Pu='Purerform:BAAANQADCgcIBwAAAA==.',
Qu='Quelidra:BAAANQADCgUIBQAAAA==.Quepaspete:BAAANQADCgYIBwAAAA==.',
Ra='Raa:BAABNQAECn86AAIcAAkK8RoeJAAGAwAcAAkK8RoeJAAGAwAAAA==.Racker:BAAANQAECgcIDgAAAA==.Ragou:BAAANQADCgQIBAAAAA==.Rainfallen:BAABNQAECn8UAAMeAAoKRwlYDACdAQAeAAoKRwlYDACdAQAdAAEKWgYNLQAmAAAAAA==.',
Re='Rengots:BAAANQAECgYIBQAAAA==.Rephtide:BAAANQAECgUIEAAAAA==.Responsible:BAABNQAECn8wAAIPAAoKQSCwJwAbAwAPAAoKQSCwJwAbAwAAAA==.',
Rh='Rhaez:BAAANQAECgEIAQAAAA==.Rhall:BAAANQADCgYIBgAAAA==.Rhetoricdork:BAAANQAECggICQABNQAFFAcIGQAGAOMfAA==.',
Ro='Rocktober:BAAANQAECgQIBQAAAA==.Rogmash:BAAANQAECgUJCwAAAA==.Rokkoz:BAABNQAECn8qAAIRAAkK1h0cBwDuAgARAAkK1h0cBwDuAgAAAA==.Romer:BAACNQAFFH8FAAIjAAIKOQGpCgBPAAAjAAIKOQGpCgBPAAA1AAQKfyMAAiMACQqFCCQWAIEBACMACQqFCCQWAIEBAAAA.Rompintom:BAAANQAECgIIAgAAAA==.Rookiestar:BAABNQAECn8dAAIkAAkKhg1CLwC5AQAkAAkKhg1CLwC5AQAAAA==.',
Ru='Rumí:BAAANQAECgQICAABNQAECgYICQAHAAAAAA==.',
Sa='Sabb:BAAANQADCgYIEAAAAA==.Samstephens:BAAANQADCgQIBAABNQAECgcIFQASAAUFAA==.Saphroniå:BAAANQADCgcIGQAAAA==.Sass:BAABNQAECn86AAMlAAoKFRxcMABeAgAlAAgKWhtcMABeAgARAAQKSBcWNADQAAAAAA==.Sazed:BAAANQADCgEIAQAAAA==.',
Sc='Schend:BAAANQADCgYICwAAAA==.Scibiol:BAAANQADCgIIAgAAAA==.',
Se='Sed:BAAANQAECgIIBQAAAA==.Serrana:BAAANQADCgUIBQAAAA==.',
Sf='Sfinktor:BAAANQADCgUIBAAAAA==.',
Sh='Shadowmortis:BAAANQAECgQIBQAAAA==.Shadowwilder:BAAANQAECgUICgAAAA==.Shirokhan:BAABNQAECn8pAAIGAAkKaRW0iABtAgAGAAkKaRW0iABtAgAAAA==.Shootum:BAAANQADCgUIBgAAAA==.Shïfthappens:BAAANQADCgUIBQAAAA==.',
Si='Sidewinderx:BAAANQAECgYIBgAAAA==.Sinlock:BAABNQAECn8dAAMBAAgK3B5NZAAtAgABAAcKTR9NZAAtAgAdAAQKMxH7NADvAAAAAA==.',
Sk='Skadí:BAAANQAECgQIBQAAAA==.Skrot:BAAANQADCgYIBgABNQAECgoKKQAIAPoVAA==.',
Sm='Smef:BAAANQADCgEIAQAAAA==.',
Sn='Snagglespark:BAABNQAECn8rAAMSAAoKCR5ZHgAVAwASAAoKCR5ZHgAVAwAJAAYKQQvFtQACAQAAAA==.Sneakykrim:BAAANQABCgEIAQAAAA==.Sneakylink:BAAANQADCgYIEQAAAA==.Snowbunni:BAAANQAECgQIBwAAAA==.',
So='Soladrian:BAAANQAECgcIDAAAAA==.Solanthion:BAEANQADCgcIBwABNQAECgoKGgACAOEIAA==.',
Sp='Spankyee:BAAANQADCgQIBAAAAA==.',
Sr='Srtaco:BAAANQAECgUICAAAAA==.',
St='Starz:BAAANQADCgYIBAAAAA==.Stelmaria:BAAANQAECgMIAwABNQAECgoKKAAcAJUaAA==.',
Su='Sunchipzz:BAAANQADCgQIBAAAAA==.Sundayschool:BAAANQAECgcIEgAAAA==.Sunwing:BAAANQAECgIIAgAAAA==.',
Sy='Syyia:BAAANQADCgIIAgAAAA==.',
['Sé']='Séraph:BAAANQAECgUIBwAAAA==.',
['Só']='Sóozabimaru:BAAANQAECgQICQAAAA==.',
Ta='Tahano:BAAANQABCgIIAgAAAA==.Talljeff:BAAANQAECggIDgAAAA==.Tankarmor:BAABNQAECn8jAAIOAAYKaQ8dHwBZAQAOAAYKaQ8dHwBZAQAAAA==.Taylorswif:BAACNQAFFH8HAAMGAAQKrQynLQAjAQAGAAQKrQynLQAjAQAXAAEKSAfzFQA+AAA1AAQKfyAAAgYACQowGlpoAK0CAAYACQowGlpoAK0CAAAA.',
Tc='Tcharta:BAABNQAECn82AAMUAAoKWxz8BADBAgAUAAoKWxz8BADBAgAfAAEKAAA6QAArAAAAAA==.',
Te='Teostradin:BAAANQAECgQIBAAAAA==.',
Th='Thefamousone:BAAANQADCgYICAAAAA==.Theiá:BAAANQAECgEIAQAAAA==.Thermotide:BAAANQAECgcIEAAAAA==.Thornpaw:BAAANQADCgQIBAAAAA==.Thoror:BAAANQAECgUICgAAAA==.Thunderbolt:BAAANQADCgcIBwABNQAECgQIBAAHAAAAAA==.Thundernütz:BAAANQADCgIIAwAAAA==.Thymós:BAAANQAECgUIDAAAAA==.',
Ti='Tiffina:BAAANQADCgYICQAAAA==.Tiffzen:BAABNQAECn8WAAIcAAcKOAdX3ABIAQAcAAcKOAdX3ABIAQAAAA==.Timeskip:BAAANQADCggIBgAAAA==.Tinyfaith:BAAANQAECgQICAAAAA==.Titum:BAACNQAFFH8GAAIBAAMK9w5AJQBQAAABAAMK9w5AJQBQAAA1AAQKfxkAAgEACgrmGfo6AKMCAAEACgrmGfo6AKMCAAE1AAUUBggMAAYA5ggA.',
To='Tongpooh:BAABNQAECn8pAAIIAAoK+hU9GACHAgAIAAoK+hU9GACHAgAAAA==.',
Tr='Treeberk:BAAANQAECgIIAgAAAA==.Truelink:BAAANQADCggIEgAAAA==.',
Tu='Tuba:BAAANQAECggIBQAAAA==.Tuckerherout:BAAANQAECgYIEAAAAA==.Tundro:BAAANQAECgEIAQAAAA==.',
Tw='Twix:BAAANQAECgIIAgABNQAECgQJCgAHAAAAAA==.',
['Tî']='Tîtån:BAABNQAECn8eAAMdAAYKJw3RIgBbAQAdAAYKJw3RIgBbAQAeAAEKAACDNgAbAAAAAA==.',
Uh='Uh:BAABNQAECn8aAAImAAgK9x2VIgB6AgAmAAgK9x2VIgB6AgABNQAFFAQICQAIAGghAA==.',
Un='Undeadlock:BAAANQAECgUIEAAAAA==.',
Va='Vale:BAAANQADCgEIAQAAAA==.',
Vg='Vgmking:BAABNQAECn8qAAIWAAkKCReSQAD8AQAWAAkKCReSQAD8AQAAAA==.',
Vi='Vigdis:BAAANQADCgcIBwAAAA==.Vindorei:BAAANQADCgUIDgAAAA==.',
Vo='Voidfed:BAAANQADCgQIBAABNQADCgQICAAHAAAAAA==.Voidfu:BAAANQADCgIIAgAAAA==.Voidmydrama:BAAANQADCgYIBgAAAA==.Voidrefund:BAAANQADCgYIBgAAAA==.Vokzhen:BAABNQAECn8tAAIVAAgKshweFQC4AgAVAAgKshweFQC4AgAAAA==.Volescu:BAABNQAECn8ZAAMdAAkK8RxDAwCXAQAdAAcKABxDAwCXAQABAAMKuxpvhwDjAAAAAA==.',
Wa='Walkerboah:BAABNQAECn8fAAIBAAkKGQ/7RACXAQABAAkKGQ/7RACXAQAAAA==.Warmachinne:BAAANQAECgEIAQAAAA==.',
We='Weel:BAABNQAECn8wAAIKAAoKwRPZVwARAgAKAAoKwRPZVwARAgAAAA==.',
Wo='Wolfspider:BAAANQAECgIIAwAAAA==.',
Wy='Wyland:BAAANQAECgMIBQAAAA==.Wylander:BAABNQAECn8gAAIKAAgKGiL6EADIAgAKAAgKGiL6EADIAgAAAA==.Wylandvoker:BAAANQADCgIIAgAAAA==.',
Xa='Xanun:BAAANQADCgMIAwAAAA==.',
Xe='Xeri:BAABNQAECn8aAAITAAoKXhnUCwCzAgATAAoKXhnUCwCzAgABNQAFFAcIGAAnALgiAA==.Xeromus:BAABNQAECn8hAAMlAAcK+A9fMQANAQAlAAcK+A9fMQANAQARAAEKxQO5fgAiAAAAAA==.Xetsus:BAAANQADCgUJBQAAAA==.',
Ya='Yang:BAAANQABCgEIAQAAAA==.',
Yo='Yoink:BAAANQADCgUIBQAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Yv='Yvelmaya:BAABNQAECn8jAAMJAAcKsxxKKQAJAgAJAAcKsxxKKQAJAgASAAEKAAAJUAEmAAAAAA==.',
Za='Zabawaba:BAAANQAECgUIBwABNQAECggIDwAHAAAAAA==.Zaboomaprune:BAABNQAECn8aAAMNAAgK/QgYNgD1AAANAAgK/QgYNgD1AAAaAAQKwwFdOABcAAAAAA==.Zarika:BAACNQAFFH8YAAInAAcKuCI+AACBAgAnAAcKuCI+AACBAgA1AAQKfzUAAycACgrVJVYAANkDACcACgpzJVYAANkDACQACQqII28KAOkCAAAA.Zarì:BAAANQAECgUIBwABNQAFFAcIGAAnALgiAA==.',
Ze='Zeknull:BAABNQAECn8dAAMKAAgKTRwJOQCAAgAKAAgKTRwJOQCAAgACAAUKYg8xAgEcAQABNQAECgoKGAAEABQcAA==.Zekthal:BAABNQAECn8YAAMEAAoKFBxWCAB+AgAEAAoKFBxWCAB+AgAFAAEK4QWbcAAfAAAAAA==.Zenio:BAAANQADCgIIAgAAAA==.Zennah:BAAANQADCggIFgAAAA==.Zephy:BAAANQADCgcICQAAAA==.',
Zr='Zrgl:BAAANQADCggICAAAAA==.',
['Zä']='Zäo:BAACNQAFFH8FAAIBAAIK6xcdLwCbAAABAAIK6xcdLwCbAAA1AAQKfyQABB4ACQphItgBACcDAB4ACQo7H9gBACcDAAEABQq7HTqiAJEBAB0AAwo8I2g5ANsAAAAA.',
['Ïk']='Ïkea:BAAANQAECgQIBwAAAA==.',
['ßl']='ßloodhunter:BAAANQAECgMIAgAAAA==.',
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
