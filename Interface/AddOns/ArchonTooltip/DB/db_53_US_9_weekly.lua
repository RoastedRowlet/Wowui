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

local lookup = {'Warlock-Demonology','Druid-Balance','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Mage-Arcane','Rogue-Assassination','Monk-Windwalker','Unknown-Unknown','Shaman-Restoration','Paladin-Holy','Monk-Mistweaver','Druid-Restoration','Paladin-Protection','Druid-Guardian','Warrior-Protection','Warrior-Arms','Hunter-BeastMastery','Warrior-Fury','Shaman-Elemental','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Preservation','Priest-Shadow','DeathKnight-Blood','Mage-Frost','Mage-Fire','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Monk-Brewmaster','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Acupuncher:BAAANQAECgIIAgAAAA==.',
Ad='Adamsandler:BAAANQADCggICAAAAA==.Adiwolf:BAAANQAECgIIBAAAAA==.',
Al='Alcha:BAABNQAECn8cAAIBAAgKXBtQYAA3AgABAAgKXBtQYAA3AgAAAA==.Alenndar:BAAANQADCgEIAQAAAA==.Alexdaddario:BAABNQAECn8UAAICAAcKWx3hRwDMAQACAAcKWx3hRwDMAQAAAA==.Algaefungi:BAAANQAECgIICAAAAA==.Althena:BAAANQAECgEIAQABNQAECgoKSAADAMoiAA==.Alystana:BAAANQADCgUIBwAAAA==.',
Am='Amberelle:BAAANQADCgQIBAAAAA==.',
An='Anastera:BAAANQADCgYIBwAAAA==.Animeniac:BAABNQAECn85AAIEAAkKMCQcAwDYAgAEAAkKMCQcAwDYAgAAAA==.Anticlimax:BAABNQAECn8yAAQFAAoKMRAUKABZAQAFAAgKRhAUKABZAQAEAAYK1Ay4GQAZAQAGAAYKtAnaWQC8AAAAAA==.Antilaw:BAAANQAECgcIDAAAAA==.Antisocial:BAAANQAECgQIDQAAAA==.Antistab:BAAANQAECgQICgAAAA==.',
Ao='Aoibhneas:BAAANQADCgcIBwAAAA==.',
Ap='Apprentice:BAACNQAFFH8HAAIHAAMKkho5MAAOAQAHAAMKkho5MAAOAQA1AAQKfx4AAgcACQoXJNAzACMDAAcACQoXJNAzACMDAAAA.',
Ar='Ariha:BAAANQAECgQIBQAAAA==.Arnokk:BAAANQADCgYIDAAAAA==.Artrael:BAAANQADCggJCAAAAA==.',
At='Atorim:BAAANQADCgIIAgABNQAECggIGAAIAAANAA==.',
Av='Avienndha:BAABNQAECn85AAIEAAkKmhgjCgDBAQAEAAkKmhgjCgDBAQAAAA==.Avriel:BAAANQAECgQICQABNQAECgoKSAADAMoiAA==.',
Ba='Barbatos:BAAANQAECgIIAgAAAA==.',
Be='Beardeddrunk:BAAANQADCgUJBQAAAA==.Beornwildlaw:BAAANQABCgcIDgAAAA==.Beryoni:BAAANQAECggICAAAAA==.',
Bi='Bigsheet:BAAANQAECgUIBwABNQAFFAkJJQAJAMcUAA==.',
Bl='Bloodyflame:BAAANQADCgEIAQAAAA==.',
Bo='Bobbytofva:BAAANQAECgMIBAAAAA==.Bobthedurgon:BAAANQADCgUIBQAAAA==.Bobthegrinch:BAAANQADCgQIBAAAAA==.Boneloss:BAAANQADCgQIBAAAAA==.Bonkini:BAAANQAECggIEAAAAA==.Bonkí:BAAANQAECggICQABNQAECggIEAAKAAAAAA==.Boochaka:BAABNQAECn8qAAILAAoKyhzfKgB7AgALAAoKyhzfKgB7AgAAAA==.Bouman:BAAANQADCgYIBgAAAA==.Bouquet:BAABNQAECn8pAAIHAAoKJQackACFAQAHAAoKJQackACFAQAAAA==.',
Br='Brewdog:BAAANQAECgQICgAAAA==.Brickdeath:BAAANQAECgEIAQAAAA==.Brickfists:BAAANQAECgEIAQAAAA==.Brotherfuzz:BAAANQAECgIIAwAAAA==.',
Bu='Buckangel:BAAANQAECggIDAABNQAFFAgIEwAMACkmAA==.Busterposer:BAABNQAECn8iAAIGAAoKSSDkCwDhAgAGAAoKSSDkCwDhAgAAAA==.',
['Bë']='Bëan:BAAANQAECggICQAAAA==.',
Ca='Caelvaris:BAAANQADCgEIAQAAAA==.Calabooca:BAAANQADCgUICAAAAA==.Canadaclown:BAAANQADCgIIAgAAAA==.Candor:BAAANQADCgUIBQAAAA==.',
Ch='Cheesefries:BAABNQAECn8qAAINAAkKEx12CgChAgANAAkKEx12CgChAgAAAA==.Chereth:BAABNQAECn8jAAIOAAoKRh9gBgB+AwAOAAoKRh9gBgB+AwAAAA==.Chratos:BAAANQADCgYIBgAAAA==.',
Cl='Clapt:BAAANQAECgQIBgAAAA==.Clapton:BAAANQAECgQICgAAAA==.Claptone:BAABNQAECn8WAAILAAcKwRS3hwB3AQALAAcKwRS3hwB3AQAAAA==.',
Co='Corpuscle:BAABNQAECn8wAAMPAAoK8xntDwAqAgAPAAoK8xntDwAqAgAMAAIKogoPDwFZAAAAAA==.',
Cr='Critcomander:BAABNQAECn8rAAIDAAkKcQ0yrADHAQADAAkKcQ0yrADHAQAAAA==.Critties:BAAANQADCgMIAwAAAA==.Crowfive:BAAANQAECgUIBQAAAA==.Crueldin:BAABNQAECn8dAAMMAAgKIhC1lwBaAQAMAAgKIhC1lwBaAQADAAEKkws4nAE5AAAAAA==.',
Da='Dalsen:BAABNQAECn80AAIQAAoKPw5yIQCOAQAQAAoKPw5yIQCOAQAAAA==.Dalvulpe:BAAANQAECgIIAgABNQAECgoKNAAQAD8OAA==.Dankchop:BAABNQAECn8cAAMRAAgK+haLGwCCAQARAAgKRxOLGwCCAQASAAgKshU7wAB8AQAAAA==.Darim:BAAANQADCgIIAgAAAA==.Darkbishop:BAAANQABCgYICgAAAA==.Darklink:BAABNQAECn8UAAITAAgK2BEojwCYAQATAAgK2BEojwCYAQAAAA==.Dawnlighted:BAAANQADCgMIAwAAAA==.',
De='Deadlyshiet:BAAANQAECgMIBQABNQAFFAkJJQAJAMcUAA==.Defibrilater:BAAANQAECgQICAAAAA==.Demonfed:BAAANQABCgIIAgABNQAECgcIEgAKAAAAAA==.Demonkrim:BAAANQADCgQIBAAAAA==.Demonlink:BAAANQADCgUIBQAAAA==.Denrin:BAAANQAECgYIEgAAAA==.Deskpop:BAAANQADCgQIBAAAAA==.',
Di='Diabolikal:BAAANQADCgYIDAAAAA==.Dill:BAABNQAECn9XAAIUAAoK6CSIAADVAwAUAAoK6CSIAADVAwAAAA==.Divinesmite:BAAANQADCgcICAAAAA==.',
Dm='Dmachine:BAABNQAECn8mAAMSAAoK8BaFQABBAgASAAoK6BaFQABBAgARAAIKhhQcNABwAAABNQAFFAgIHAABAJgdAA==.',
Do='Dondeezy:BAAANQADCgYIBgAAAA==.',
Dr='Drdru:BAABNQAECn82AAIOAAoKIhs6DwDUAgAOAAoKIhs6DwDUAgABNQADCgUIBQAKAAAAAA==.Dreadshade:BAAANQAECgYICAAAAA==.Drheals:BAAANQADCgIIAgAAAA==.Drlittle:BAAANQADCgQIBAAAAA==.Dropfort:BAAANQAECggIDwABNQAECgkJGQAPAFUSAA==.Drscruffles:BAAANQADCgcIBwAAAA==.Drstress:BAAANQADCgEIAQAAAA==.',
Du='Duifean:BAAANQADCggIFgABNQAECgkJJQAVAJwGAA==.Durkidurk:BAAANQADCgMIAwAAAA==.',
Dy='Dyabolykal:BAAANQADCgQIBAABNQADCgYIDAAKAAAAAA==.',
Ea='Easily:BAAANQAECgYIDgAAAA==.',
El='Ellyanthia:BAAANQAECgYICQABNQAECgUICAAKAAAAAA==.',
Em='Emachine:BAAANQADCgcIBwABNQAFFAgIHAABAJgdAA==.',
Ex='Exio:BAAANQAECgQICgAAAA==.Extenze:BAAANQAECgUICwAAAA==.',
Fa='Fastasheet:BAACNQAFFH8lAAIJAAkKxxQ8AwA4AgAJAAkKxxQ8AwA4AgA1AAQKfzwAAgkACgqhJccEACcDAAkACgqhJccEACcDAAAA.',
Fe='Feralfed:BAAANQAECgcIDQABNQAECgcIEgAKAAAAAA==.',
Fi='Fill:BAABNQAECn8rAAIWAAoK9yO5AQCdAwAWAAoK9yO5AQCdAwABNQAFFAcIDAAJAEEfAA==.',
Fl='Flehtwo:BAACNQAFFH8YAAMVAAcKgwntCABVAQAVAAYKgwntCABVAQALAAIKzgzLIQCGAAA1AAQKfzcAAxUACgpGHgk2AJ8CABUACgpGHgk2AJ8CAAsACQrRDBOEAIABAAAA.Flehunter:BAABNQAECn8fAAMXAAkKqxFrGQC7AQAXAAgKghBrGQC7AQATAAYKZwwn1QAIAQAAAA==.Flyinbanana:BAAANQADCgQIBAABNQAECgoKWwAYAAsjAA==.',
Fo='Fortypi:BAAANQAECgYIBgABNQAFFAcIDAAJAEEfAA==.',
Fr='Fragilelimbs:BAAANQAECggICgAAAA==.Fraglen:BAAANQADCgUIBQABNQAECgcICgAKAAAAAA==.Frags:BAAANQAECgcICgAAAA==.Fránknárf:BAAANQAECgEIAQAAAA==.',
Fu='Fuzzywuzzy:BAAANQAECgMIAwAAAA==.',
Ge='Genjyosanzo:BAABNQAECn8vAAIZAAkKsQi8JQBWAQAZAAkKsQi8JQBWAQAAAA==.',
Gh='Ghmaven:BAAANQAECgUIBQAAAA==.Ghostkrim:BAAANQADCgUIBQAAAA==.',
Gi='Gilljoww:BAABNQAECn8bAAIaAAgKSx9XKgByAgAaAAgKSx9XKgByAgAAAA==.Gireigtulb:BAAANQADCgYIBgAAAA==.',
Gn='Gnz:BAAANQAECgEIAQAAAA==.Gnzz:BAABNQAECn8tAAQbAAoK/hwkGQAtAQAHAAoKDRpydQDEAQAbAAYKPhUkGQAtAQAcAAIKvhakCwBJAAAAAA==.',
Go='Gocirr:BAABNQAECn8cAAQQAAcK0QXuSACaAAAQAAcKnwXuSACaAAACAAIKaASBfgBLAAAOAAEKPAp5fQAnAAAAAA==.',
Gr='Grito:BAAANQADCgYICgAAAA==.Gryphon:BAAANQAECgYICgAAAA==.',
Ha='Haehn:BAAANQADCgMIAwAAAA==.Halstorm:BAABNQAECn8hAAMLAAoKBBt/GQDqAgALAAoKBBt/GQDqAgAVAAIK1QHxJgFEAAAAAA==.Hamburgler:BAAANQAECgMIBgABNQAECgUICAAKAAAAAA==.Harrysax:BAAANQABCgYIBgAAAA==.',
He='Hedrake:BAAANQAECggIEQAAAA==.Hexxytime:BAAANQADCgQIBAAAAA==.',
Hi='Hilazy:BAAANQAECgIIAwAAAA==.Hitzel:BAAANQAECggICwAAAA==.',
Hm='Hm:BAAANQAECgEIAQAAAA==.',
Ho='Holyphok:BAAANQAECgMIAwAAAA==.Hoobastank:BAAANQAECgQIBAAAAA==.Hotdog:BAABNQAECn8VAAQdAAoKUhY+GgAVAgAdAAkKLhQ+GgAVAgAaAAMKdRuokQC/AAAeAAIKMweUnwBdAAAAAA==.',
Ic='Icestormy:BAAANQAECgMIAwAAAA==.',
Ih='Ihavenofutur:BAABNQAECn8aAAMbAAkKjAh6IgDFAAAHAAcK2AQMUQEJAQAbAAUKwgp6IgDFAAAAAA==.',
Il='Iliil:BAABNQAECn9JAAMaAAoKGCMXDQBIAwAaAAoKGCMXDQBIAwAdAAEKAACgqQAAAAAAAA==.Illbiteyou:BAAANQADCgQIBAAAAA==.Illidantwo:BAACNQAFFH8aAAIGAAgKrROIBAAjAgAGAAgKrROIBAAjAgA1AAQKf0cAAgYACgoSJeEEAEADAAYACgoSJeEEAEADAAAA.',
Im='Imprints:BAABNQAECn8bAAISAAkKMgZD1gBDAQASAAkKMgZD1gBDAQAAAA==.',
In='Inuk:BAABNQAECn8WAAIOAAgKZxZaKwDDAQAOAAgKZxZaKwDDAQAAAA==.',
Ir='Ironshaman:BAAANQAECgYIEQABNQAECgoKPQAIAG0jAA==.',
It='Italianapee:BAAANQAECgQIBAABNQAECggIFgAOAGcWAA==.',
Ja='Jabu:BAAANQADCgQIAwABNQAECgIIBgAKAAAAAA==.Jada:BAAANQAECgUIDQAAAA==.Jaghatai:BAAANQADCgIIAgAAAA==.',
Je='Jenstonedart:BAABNQAECn8rAAIfAAoKAg3pFgBmAQAfAAoKAg3pFgBmAQAAAA==.Jeryeth:BAABNQAECn8pAAISAAoK/B7EPwDLAgASAAoK/B7EPwDLAgAAAA==.Jerymander:BAAANQAFFAEIAQAAAA==.Jeryzard:BAAANQADCgYIDAAAAA==.',
Ji='Jiannybon:BAAANQADCgQICwAAAA==.',
Ju='Judgmental:BAAANQADCgYIBgAAAA==.Judidench:BAABNQAECn8XAAIdAAgKqCNIDgBGAwAdAAgKqCNIDgBGAwAAAA==.Juicewillis:BAAANQADCgIIAgAAAA==.',
Ka='Kain:BAECNQAFFH8ZAAIPAAgKEyPKAACpAgAPAAgKEyPKAACpAgA1AAQKfzUAAw8ACgr0JE4DAI4DAA8ACQpiJk4DAI4DAAMABQrUGS6+AFYBAAAA.Kanda:BAAANQAECggIAQAAAA==.Kane:BAABNQAECn8qAAIaAAkKBBPvNQBuAQAaAAkKBBPvNQBuAQAAAA==.Karmasuture:BAAANQADCgYJBgABNQAECgMIAwAKAAAAAA==.Kata:BAAANQAECgcIDgABNQAFFAUICwAFANUgAA==.Kaïn:BAAANQAECgMIBAABNQAECgoKSAADAMoiAA==.',
Ke='Kelsí:BAABNQAECn8VAAMMAAcKvguBqgDJAAAMAAcKvguBqgDJAAADAAEKfQEotwEcAAAAAA==.Kemdygos:BAAANQAECgIIAQAAAA==.',
Ki='Killnuall:BAAANQADCgYICgABNQAECgoKFgAgAHQHAA==.Kiwí:BAABNQAECn8+AAIHAAoKxiEwGQDgAgAHAAoKxiEwGQDgAgAAAA==.',
Kr='Krasavice:BAABNQAECn9QAAITAAoK3yGZEgADAwATAAoK3yGZEgADAwAAAA==.Krenik:BAAANQADCggIHwAAAA==.Krimdin:BAAANQAECgMIAwAAAA==.Krimdrood:BAAANQADCgMIAwAAAA==.Krimshadow:BAAANQADCgcIBwAAAA==.Krimsonblade:BAAANQADCgQIBAAAAA==.Krimsondeath:BAAANQAECggICAAAAA==.Krimtohell:BAABNQAECn8YAAQBAAkKXxNmegBvAQABAAgKFRJmegBvAQAhAAEKHBtVLABPAAAgAAEK8A8GLQA6AAAAAA==.Krisp:BAAANQAECgcIEgAAAA==.',
Ku='Kurquaan:BAAANQADCggICAAAAA==.',
La='Lauranthalas:BAABNQAECn8ZAAITAAcKMAsszwAUAQATAAcKMAsszwAUAQAAAA==.Lavenderhaze:BAAANQAECgQIBAAAAA==.',
Le='Leathal:BAABNQAECn8qAAIMAAkKTR1uMQBaAgAMAAkKTR1uMQBaAgAAAA==.Legenddairy:BAAANQAECgcIDAAAAA==.Lemurshoes:BAAANQAECgIIAwAAAA==.Lemursneaker:BAABNQAECn8aAAIHAAgKKgW2EwFrAQAHAAgKKgW2EwFrAQAAAA==.Letsgomen:BAAANQADCgEIAQAAAA==.',
Li='Lightsfire:BAAANQADCgMIAwABNQAECgoKFQAVANgRAA==.Lightshock:BAABNQAECn8VAAIVAAoK2BG5PADhAQAVAAoK2BG5PADhAQAAAA==.Linkblade:BAAANQADCggIDgAAAA==.Linkborne:BAAANQABCgMIAwAAAA==.Linkdin:BAAANQAECgQIBAAAAA==.Linkdrood:BAAANQAECggIDgAAAA==.Linky:BAAANQADCgIIBAAAAA==.',
Ll='Llaagg:BAAANQAECgIIAgAAAA==.',
Lo='Lokust:BAABNQAECn8tAAILAAcKCSG/UwAYAgALAAcKCSG/UwAYAgAAAA==.',
Lu='Lucentdawn:BAABNQAECn8vAAIMAAoK7BNxPwAXAgAMAAoK7BNxPwAXAgAAAA==.Luckyshrine:BAAANQABCggICwAAAA==.Ludachris:BAAANQAECgEIAQAAAA==.',
Ly='Lycanius:BAABNQAECn9FAAMfAAoKXht/BgAFAwAfAAoKXht/BgAFAwAQAAQKjBFGRgClAAAAAA==.Lynqii:BAACNQAFFH8NAAMBAAcKYRHHCQDNAQABAAYK+RPHCQDNAQAhAAEKAQdkIQBHAAA1AAQKfxUAAwEABgrkHx6TALYBAAEABgrkHx6TALYBACEAAQoVG5hrAEkAAAAA.',
Ma='Macaco:BAAANQADCgYIBgAAAA==.Malirra:BAABNQAECn8nAAIHAAoKZAbpCgF7AQAHAAoKZAbpCgF7AQAAAA==.Malëk:BAABNQAECn9IAAIDAAoKyiKPHQBNAwADAAoKyiKPHQBNAwAAAA==.Maximus:BAAANQADCgUIBQAAAA==.',
Me='Mechatholic:BAAANQAECgcIEQAAAA==.Medallis:BAAANQABCgcIDwAAAA==.Mellowlizard:BAACNQAFFH8cAAQBAAgKmB2pBQAUAgABAAYKYh2pBQAUAgAhAAEKViV6FABnAAAgAAEKtBYhEABXAAA1AAQKfzsABAEACgo+JDUPAPQCAAEACgo+JDUPAPQCACAABwooImkEAFACACEAAwr2HtU7ANIAAAAA.Metuss:BAABNQAECn8fAAMJAAkKgxgdJAAFAgAJAAcKAR0dJAAFAgANAAgKcBmKIgBvAQAAAA==.',
Mi='Miguel:BAAANQAECgUIDgAAAA==.Mira:BAABNQAECn8qAAITAAoKmg7wYgAAAgATAAoKmg7wYgAAAgAAAA==.Missmutilate:BAAANQADCggICAAAAA==.',
Mk='Mkicon:BAABNQAECn8xAAIbAAgKkh3TCQAxAgAbAAgKkh3TCQAxAgAAAA==.Mkultra:BAABNQAECn8iAAMdAAoKSiB4JgCjAgAdAAoKGB94JgCjAgAaAAYKTh3DVgCYAQAAAA==.',
Mo='Mogmoog:BAABNQAECn8qAAIdAAkKChEmLQB/AQAdAAkKChEmLQB/AQAAAA==.Mooganfreman:BAAANQAECgEIAQAAAA==.Moonangel:BAABNQAECn83AAIIAAkK3Bm8CwAVAgAIAAkK3Bm8CwAVAgAAAA==.Morbodan:BAABNQAECn89AAIIAAoKbSMBAwAbAwAIAAoKbSMBAwAbAwAAAA==.Mornangus:BAAANQABCgMIAwAAAA==.Moshpit:BAAANQAFFAEIAQAAAA==.Motone:BAAANQAECgQIBAAAAA==.',
Mu='Multanni:BAABNQAECn83AAIVAAoKHhqwIwBcAgAVAAoKHhqwIwBcAgAAAA==.',
My='Mykanoid:BAABNQAECn8gAAIiAAoKbRMNCQDsAQAiAAoKbRMNCQDsAQABNQAECgoKWwAYAAsjAA==.Myonecrosis:BAABNQAECn85AAIBAAkKNSDJLgBUAgABAAkKNSDJLgBUAgAAAA==.',
Na='Nakrog:BAABNQAECn8iAAMRAAgKghoNEAAoAgARAAgKghoNEAAoAgASAAEKkBplRgFEAAAAAA==.Napster:BAAANQAECgMIAwAAAA==.Nasa:BAACNQAFFH8ZAAIJAAgK9guOBQDGAQAJAAgK9guOBQDGAQA1AAQKfyQAAgkACQrIHk8WAJ0CAAkACQrIHk8WAJ0CAAAA.',
Ne='Nellarixi:BAABNQAECn8aAAIZAAgKQhz2HQBQAgAZAAgKQhz2HQBQAgAAAA==.Nethus:BAAANQADCgcICQAAAA==.',
Ni='Niivalyr:BAAANQABCgIIAQAAAA==.Nimbus:BAAANQAECgEIAQABNQAFFAcIGwAVADwXAA==.',
No='Nodens:BAAANQADCgcIEwAAAA==.Nomaa:BAABNQAECn84AAIgAAkK2wIGFwDOAAAgAAkK2wIGFwDOAAAAAA==.Nomäd:BAABNQAECn8sAAIUAAkKbBEVDgCgAQAUAAkKbBEVDgCgAQAAAA==.Nosneb:BAAANQADCgMIBAABNQADCggIEAAKAAAAAA==.',
Ny='Nytedevil:BAABNQAECn8aAAIBAAoK5xWdeAB0AQABAAoK5xWdeAB0AQAAAA==.',
['Nì']='Nìtsua:BAAANQADCggIEAAAAA==.',
Ob='Obilivion:BAAANQAECgYIBwAAAA==.',
Og='Ogmount:BAAANQAECgMIAwAAAA==.',
Or='Orflame:BAABNQAECn8bAAMYAAgKeQeuKABvAQAYAAgKeQeuKABvAQAjAAEKKgXpJAAxAAAAAA==.',
Ph='Phantomhealz:BAAANQABCgIIAgAAAA==.Phrash:BAACNQAFFH8MAAIJAAcKQR9dCgAeAQAJAAcKQR9dCgAeAQA1AAQKfx0AAgkACQr9JGUJADsDAAkACQr9JGUJADsDAAAA.',
Pi='Pigbearmans:BAAANQADCgYIBgAAAA==.',
Pl='Plex:BAAANQAECgcICgABNQAECgkJIAAkAGEgAA==.',
Po='Pooldan:BAAANQAECgMJAgAAAA==.',
Pr='Praystatioñ:BAABNQAECn8sAAIlAAoKhBkPBQBmAgAlAAoKhBkPBQBmAgAAAA==.Premiumgank:BAAANQAECgUIBQAAAA==.Priestlink:BAAANQADCgcIGAAAAA==.Prtanks:BAAANQAECgQIBgAAAA==.',
Pu='Purerform:BAAANQADCgcIBwAAAA==.',
Qu='Quelidra:BAAANQADCgUIBQAAAA==.Quepaspete:BAAANQADCgYIBwAAAA==.',
Ra='Raa:BAABNQAECn9GAAITAAkK8iU9BQBlAwATAAkK8iU9BQBlAwAAAA==.Racker:BAABNQAECn8fAAIUAAgKQRNnEQBiAQAUAAgKQRNnEQBiAQAAAA==.Ragou:BAAANQADCgQIBAAAAA==.Rainfallen:BAABNQAECn8UAAMgAAoKRwlYDACdAQAgAAoKRwlYDACdAQAhAAEKWgadPQAjAAAAAA==.',
Re='Rengots:BAAANQAECgYICgAAAA==.Rephtide:BAAANQAECgUIEAAAAA==.Responsible:BAABNQAECn8yAAISAAoKgyCwJwAbAwASAAoKgyCwJwAbAwAAAA==.',
Rh='Rhaez:BAAANQAECgEIAQAAAA==.Rhall:BAAANQADCgYIBgAAAA==.Rhetoricdork:BAAANQAECggICQABNQAECgoKHgAXAEQbAA==.',
Ri='Ritter:BAAANQADCgQIBAAAAA==.',
Ro='Rocksham:BAAANQAECggICAAAAA==.Rocktober:BAAANQAECgUIBgAAAA==.Rogmash:BAAANQAECgUJCwAAAA==.Rokkoz:BAABNQAECn83AAIOAAoK9B+ABwBmAwAOAAoK9B+ABwBmAwAAAA==.Romer:BAACNQAFFH8FAAImAAIKOQGpCgBPAAAmAAIKOQGpCgBPAAA1AAQKfyMAAiYACQqFCCQWAIEBACYACQqFCCQWAIEBAAAA.Rompintom:BAAANQAECgIIAgAAAA==.Rookiestar:BAABNQAECn8rAAInAAkKaA7QTADOAQAnAAkKaA7QTADOAQAAAA==.',
Ru='Rumí:BAAANQAECgUICAAAAA==.',
Sa='Sabb:BAAANQADCgYIEAAAAA==.Samstephens:BAAANQADCgYIDQABNQAECgkJJQAVAJwGAA==.Saphroniå:BAAANQADCgcIGQAAAA==.Sass:BAABNQAECn9DAAMCAAoKfxxcMABeAgACAAgKWhtcMABeAgAOAAQKKBsJOQA0AQAAAA==.Sazed:BAAANQADCgEIAQAAAA==.',
Sc='Schend:BAAANQADCgYICwAAAA==.Scibiol:BAAANQADCgIIAgAAAA==.',
Se='Sed:BAAANQAECgIIBQAAAA==.Serrana:BAAANQADCgUIBQAAAA==.',
Sf='Sfinktor:BAAANQADCgYIBgAAAA==.',
Sh='Shadax:BAAANQAECgcICAAAAA==.Shadowmortis:BAAANQAECgQIBQAAAA==.Shadowwilder:BAABNQAECn8gAAIGAAgKUwT6VgDHAAAGAAgKUwT6VgDHAAAAAA==.Shirokhan:BAABNQAECn81AAIHAAkKaRsRUAAgAgAHAAkKaRsRUAAgAgAAAA==.Shootum:BAAANQADCgYIDAAAAA==.Shïfthappens:BAAANQADCgUIBQAAAA==.',
Si='Sidewinderx:BAABNQAECn8UAAIeAAcKEwXcdgDHAAAeAAcKEwXcdgDHAAAAAA==.Sinlock:BAABNQAECn8dAAMBAAgK3B5NZAAtAgABAAcKTR9NZAAtAgAhAAQKMxH7NADvAAAAAA==.',
Sk='Skadí:BAAANQAECgYIBQAAAA==.Skrot:BAAANQADCgYIBgABNQAECgoKMQAJAJIYAA==.',
Sm='Smallarms:BAAANQADCgIIAgAAAA==.Smef:BAAANQADCgEIAQAAAA==.',
Sn='Snagglespark:BAACNQAFFH8GAAIVAAUKRgz6FQC/AAAVAAUKRgz6FQC/AAA1AAQKfy4AAxUACgr2HlkeABUDABUACgr2HlkeABUDAAsABgpBC8W1AAIBAAAA.Sneakykrim:BAAANQABCgEIAQAAAA==.Sneakylink:BAAANQADCgYIEQAAAA==.Snowbunni:BAAANQAECgUIDAAAAA==.',
So='Soladrian:BAAANQAECgcIDAAAAA==.Solanthion:BAEANQADCgcIBwABNQAECgkJGwAaAKYXAA==.',
Sp='Spankyee:BAAANQADCgQIBAAAAA==.',
Sr='Srtaco:BAAANQAECgcIDgAAAA==.',
St='Starz:BAAANQADCgYIBAAAAA==.Stelmaria:BAAANQAECgMIAwABNQAFFAQIBQATADsDAA==.',
Su='Sunchipzz:BAAANQADCgQIBAAAAA==.Sundayschool:BAAANQAECgcIEgAAAA==.Sunwing:BAAANQAECgQIBgAAAA==.',
Sy='Syyia:BAAANQADCgIIAgAAAA==.',
['Sé']='Séraph:BAAANQAECgcIDgAAAA==.',
['Só']='Sóozabimaru:BAAANQAECgQICQAAAA==.',
Ta='Tahano:BAAANQABCgIIAgAAAA==.Talljeff:BAAANQAECggIDgAAAA==.Tankarmor:BAABNQAECn8tAAIRAAcKChDIHwAAAQARAAcKChDIHwAAAQAAAA==.Taylorswif:BAACNQAFFH8HAAMHAAQKrQynLQAjAQAHAAQKrQynLQAjAQAbAAEKSAfzFQA+AAA1AAQKfyEAAwcACgqAGlpoAK0CAAcACQowGlpoAK0CABsAAQq1HAY2AFQAAAAA.',
Tc='Tcharta:BAABNQAECn9bAAMYAAoKCyMnAQD3AwAYAAoKCyMnAQD3AwAiAAEKAAA6QAArAAAAAA==.',
Te='Teostradin:BAAANQAECggICwAAAA==.',
Th='Thefamousone:BAAANQADCgYICAAAAA==.Theiá:BAAANQAECgEIAQAAAA==.Thermotide:BAAANQAECgcIEAAAAA==.Thiccpickles:BAAANQAECgUIBQABNQAECgoKRwALAC4gAA==.Thornpaw:BAAANQADCgUIBgAAAA==.Thoror:BAAANQAECgUICgAAAA==.Thunderbolt:BAAANQADCgcIBwABNQAECgQIBAAKAAAAAA==.Thundernütz:BAAANQADCgIIAwAAAA==.Thymós:BAAANQAECgUIDAAAAA==.',
Ti='Tiffina:BAAANQADCgYICQAAAA==.Tiffzen:BAABNQAECn8eAAITAAgKGQib0gANAQATAAgKGQib0gANAQAAAA==.Timeskip:BAAANQADCggIBgAAAA==.Tinyfaith:BAAANQAECgQICAAAAA==.Titum:BAACNQAFFH8MAAIBAAUKZBTsFwDpAAABAAUKZBTsFwDpAAA1AAQKfyYAAgEACgp3IYENAP8CAAEACgp3IYENAP8CAAAA.',
To='Tongpooh:BAABNQAECn8xAAIJAAoKkhg9GACHAgAJAAoKkhg9GACHAgAAAA==.',
Tr='Treeberk:BAAANQAECgIIAgAAAA==.Truelink:BAAANQADCggIEgAAAA==.',
Tu='Tuba:BAAANQAECggIBQAAAA==.Tuckerherout:BAAANQAECgYIEAAAAA==.Tundro:BAAANQAECgEIAQAAAA==.',
Tw='Twix:BAAANQAECgIIAgABNQAECgQICgAKAAAAAA==.',
['Tî']='Tîtån:BAABNQAECn8kAAMhAAcKUBDdCgAVAQAhAAcKUBDdCgAVAQAgAAEKAACDNgAbAAAAAA==.',
Uh='Uh:BAABNQAECn8aAAIeAAgK9x2VIgB6AgAeAAgK9x2VIgB6AgABNQAFFAcIDAAJAEEfAA==.',
Un='Undeadlock:BAAANQAECgQIEAAAAA==.',
Va='Vale:BAAANQADCgEIAQAAAA==.Valynda:BAAANQADCgEIAQAAAA==.',
Vg='Vgmking:BAABNQAECn8rAAIaAAkKCReSQAD8AQAaAAkKCReSQAD8AQAAAA==.',
Vi='Vigdis:BAAANQADCgcIBwAAAA==.Vindorei:BAAANQADCgUIDgAAAA==.',
Vo='Voidfed:BAAANQADCgQIBAABNQAECgcIEgAKAAAAAA==.Voidfu:BAAANQADCgIIAgAAAA==.Voidmydrama:BAAANQADCgYIBgAAAA==.Voidrefund:BAAANQADCgYIBgAAAA==.Vokzhen:BAABNQAECn8/AAIZAAoKdho9EQBGAgAZAAoKdho9EQBGAgAAAA==.Volescu:BAABNQAECn8hAAMhAAoK4h2VAwAAAgAhAAgKah2VAwAAAgABAAQKbBm7nAAeAQAAAA==.',
Wa='Walkerboah:BAABNQAECn8jAAIBAAoKvA+XWQDHAQABAAoKvA+XWQDHAQAAAA==.Warmachinne:BAAANQAECgIIAQAAAA==.',
We='Weel:BAABNQAECn9BAAIMAAoK4RlFIwCpAgAMAAoK4RlFIwCpAgAAAA==.',
Wo='Wolfspider:BAAANQAECgIIAwAAAA==.',
Wy='Wyland:BAAANQAECgQIBQAAAA==.Wylander:BAABNQAECn8iAAIMAAoKdh8hFAAZAwAMAAoKdh8hFAAZAwAAAA==.Wylandvoker:BAAANQADCgIIAgAAAA==.',
Xa='Xanun:BAAANQADCgMIAwAAAA==.',
Xe='Xeri:BAABNQAECn8bAAIWAAoKXhnUCwCzAgAWAAoKXhnUCwCzAgABNQAFFAgIGgAoAJghAA==.Xeromus:BAABNQAECn8wAAMCAAkKNRDDLwCJAQACAAkKNRDDLwCJAQAOAAEKxQO5fgAiAAAAAA==.Xetsus:BAAANQADCgUJBQAAAA==.',
Ya='Yang:BAAANQABCgEIAQAAAA==.',
Yo='Yoink:BAAANQADCgUIBQAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Yv='Yvelmaya:BAABNQAECn8tAAMLAAkKSB13IwCnAgALAAkKSB13IwCnAgAVAAEKAAAJUAEmAAAAAA==.',
Za='Zabawaba:BAABNQAECn8ZAAQPAAkKVRLLFQDTAQAPAAkKVRLLFQDTAQAMAAEKxwglJgEvAAADAAEK6gf8rgElAAAAAA==.Zaboomaprune:BAABNQAECn8qAAMQAAoKPw2FKQA9AQAQAAoKPw2FKQA9AQAfAAQKwwFdOABcAAAAAA==.Zarika:BAACNQAFFH8aAAMoAAgKmCE+AACBAgAoAAcKuCI+AACBAgAnAAIK9RsXIgBhAAA1AAQKfz4AAygACgpkJlYAANkDACgACgpzJVYAANkDACcACQorJVYNAAsDAAAA.Zarì:BAAANQAECgUIBwABNQAFFAgIGgAoAJghAA==.',
Ze='Zeknull:BAABNQAECn8dAAMMAAgKTRwJOQCAAgAMAAgKTRwJOQCAAgADAAUKYg8xAgEcAQABNQAECgoKOQAFAGsfAA==.Zekthal:BAABNQAECn85AAMFAAoKax+SCADQAgAFAAoKax+SCADQAgAGAAEK4QWJkAAcAAAAAA==.Zenio:BAAANQADCgIIAgAAAA==.Zennah:BAAANQADCggIFgAAAA==.Zephy:BAAANQADCgcICQAAAA==.',
Zr='Zrgl:BAAANQADCggICAAAAA==.',
['Zä']='Zäo:BAACNQAFFH8FAAIBAAIK6xcdLwCbAAABAAIK6xcdLwCbAAA1AAQKfyQABCAACQphItgBACcDACAACQo7H9gBACcDAAEABQq7HTqiAJEBACEAAwo8I2g5ANsAAAAA.',
['Ïk']='Ïkea:BAAANQAECgQIBwAAAA==.',
['ßl']='ßloodhunter:BAAANQAECgUIBQAAAA==.',
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
