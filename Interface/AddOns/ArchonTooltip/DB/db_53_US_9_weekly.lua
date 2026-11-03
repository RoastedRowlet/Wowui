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

local lookup = {'Warlock-Demonology','Druid-Balance','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Mage-Arcane','Unknown-Unknown','Monk-Windwalker','Shaman-Restoration','Paladin-Holy','Monk-Mistweaver','Druid-Restoration','Paladin-Protection','Druid-Guardian','Warrior-Protection','Warrior-Arms','Hunter-BeastMastery','Warrior-Fury','Shaman-Elemental','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Preservation','Priest-Shadow','DeathKnight-Blood','Mage-Frost','Mage-Fire','Rogue-Assassination','Druid-Feral','DeathKnight-Unholy','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Monk-Brewmaster','Rogue-Subtlety','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Acupuncher:BAAANQAECgIIAgAAAA==.',
Ad='Adamsandler:BAAANQADCggICAAAAA==.Adiwolf:BAAANQAECgIIBAAAAA==.',
Al='Alcha:BAABNQAECn8XAAIBAAcKXBtQYAA3AgABAAcKXBtQYAA3AgAAAA==.Alenndar:BAAANQADCgEIAQAAAA==.Alexdaddario:BAABNQAECn8UAAICAAcKWx3hRwDMAQACAAcKWx3hRwDMAQAAAA==.Algaefungi:BAAANQAECgIICAAAAA==.Althena:BAAANQAECgEIAQABNQAECgoKQgADAMoiAA==.Alystana:BAAANQADCgUIBwAAAA==.',
Am='Amberelle:BAAANQADCgQIBAAAAA==.',
An='Anastera:BAAANQADCgYIBwAAAA==.Animeniac:BAABNQAECn8qAAIEAAcKZSPjBgDtAQAEAAcKZSPjBgDtAQAAAA==.Anticlimax:BAABNQAECn8qAAQEAAkKgA64GQAZAQAEAAYK1Ay4GQAZAQAFAAcKEw95KQAUAQAGAAUKHAiCWACNAAAAAA==.Antilaw:BAAANQAECggICAAAAA==.Antisocial:BAAANQAECgQIDQAAAA==.Antistab:BAAANQAECgQICgAAAA==.',
Ao='Aoibhneas:BAAANQADCgcIBwAAAA==.',
Ap='Apprentice:BAACNQAFFH8HAAIHAAMKkho5MAAOAQAHAAMKkho5MAAOAQA1AAQKfx4AAgcACQoXJNAzACMDAAcACQoXJNAzACMDAAAA.',
Ar='Ariha:BAAANQAECgQIBQAAAA==.Arnokk:BAAANQADCgYIDAAAAA==.Artrael:BAAANQADCggJCAAAAA==.',
At='Atorim:BAAANQADCgIIAgABNQAECgcICwAIAAAAAA==.',
Av='Avienndha:BAABNQAECn8qAAIEAAcKlBr6DABGAQAEAAcKlBr6DABGAQAAAA==.Avriel:BAAANQAECgQICQABNQAECgoKQgADAMoiAA==.',
Ba='Barbatos:BAAANQAECgIIAgAAAA==.',
Be='Beardeddrunk:BAAANQADCgUJBQAAAA==.Beornwildlaw:BAAANQABCgcIDgAAAA==.',
Bi='Bigsheet:BAAANQAECgUIBwABNQAFFAgIJAAJAFMXAA==.',
Bl='Bloodyflame:BAAANQADCgEIAQAAAA==.',
Bo='Bobbytofva:BAAANQAECgMIBAAAAA==.Bobthedurgon:BAAANQADCgUIBQAAAA==.Bobthegrinch:BAAANQADCgQIBAAAAA==.Boneloss:BAAANQADCgQIBAAAAA==.Bonkini:BAAANQAECggIDwAAAA==.Bonkí:BAAANQAECggICAABNQAECggIDwAIAAAAAA==.Boochaka:BAABNQAECn8mAAIKAAoKLxmwLABBAgAKAAoKLxmwLABBAgAAAA==.Bouman:BAAANQADCgYIBgAAAA==.Bouquet:BAABNQAECn8hAAIHAAgKJQWCtQAQAQAHAAgKJQWCtQAQAQAAAA==.',
Br='Brewdog:BAAANQAECgQICgAAAA==.Brickdeath:BAAANQAECgEIAQAAAA==.Brickfists:BAAANQAECgEIAQAAAA==.Brotherfuzz:BAAANQAECgIIAwAAAA==.',
Bu='Buckangel:BAAANQAECggIDAABNQAFFAcIBwALAO4iAA==.Busterposer:BAABNQAECn8cAAIGAAoKTx/1CwC/AgAGAAoKTx/1CwC/AgAAAA==.',
['Bë']='Bëan:BAAANQAECgYIBgAAAA==.',
Ca='Caelvaris:BAAANQADCgEIAQAAAA==.Calabooca:BAAANQADCgUICAAAAA==.Canadaclown:BAAANQADCgIIAgAAAA==.Candor:BAAANQADCgUIBQAAAA==.',
Ch='Cheesefries:BAABNQAECn8iAAIMAAcKUhqGEwCMAQAMAAcKUhqGEwCMAQAAAA==.Chereth:BAABNQAECn8aAAINAAoKyRsFCAAiAwANAAoKyRsFCAAiAwAAAA==.Chratos:BAAANQADCgYIBgAAAA==.',
Cl='Clapt:BAAANQAECgMIAwAAAA==.Clapton:BAAANQAECgQICgAAAA==.Claptone:BAABNQAECn8UAAIKAAYKYxW3hwB3AQAKAAYKYxW3hwB3AQAAAA==.',
Co='Corpuscle:BAABNQAECn8pAAMOAAkKURltEQDWAQAOAAkKURltEQDWAQALAAIKogoPDwFZAAAAAA==.',
Cr='Critcomander:BAABNQAECn8rAAIDAAkKcQ0yrADHAQADAAkKcQ0yrADHAQAAAA==.Critties:BAAANQADCgMIAwAAAA==.Crowfive:BAAANQAECgUIBQAAAA==.Crueldin:BAABNQAECn8XAAMLAAYK2hC1lwBaAQALAAYK2hC1lwBaAQADAAEKkws4nAE5AAAAAA==.',
Da='Dalsen:BAABNQAECn80AAIPAAoKPw5UIQA/AQAPAAoKPw5UIQA/AQAAAA==.Dalvulpe:BAAANQAECgIIAgABNQAECgoKNAAPAD8OAA==.Dankchop:BAABNQAECn8XAAMQAAcKDheLGwCCAQAQAAYKHxWLGwCCAQARAAcKkBU7wAB8AQAAAA==.Darim:BAAANQADCgIIAgAAAA==.Darkbishop:BAAANQABCgYICgAAAA==.Darklink:BAABNQAECn8UAAISAAgK2BEDcgCTAQASAAgK2BEDcgCTAQAAAA==.Dawnlighted:BAAANQADCgMIAwAAAA==.',
De='Deadlyshiet:BAAANQAECgMIBQABNQAFFAgIJAAJAFMXAA==.Defibrilater:BAAANQAECgQICAAAAA==.Demonfed:BAAANQABCgIIAgABNQAECgcIEgAIAAAAAA==.Demonkrim:BAAANQADCgQIBAAAAA==.Demonlink:BAAANQADCgUIBQAAAA==.Denrin:BAAANQAECgYIEgAAAA==.Deskpop:BAAANQADCgQIBAAAAA==.',
Di='Diabolikal:BAAANQADCgYIDAAAAA==.Dill:BAABNQAECn9NAAITAAoKtiSIAADVAwATAAoKtiSIAADVAwAAAA==.Divinesmite:BAAANQADCgcICAAAAA==.',
Dm='Dmachine:BAABNQAECn8mAAMRAAoK8BY8MgBOAgARAAoK6BY8MgBOAgAQAAIKhhRWKwBzAAABNQAFFAcIGgABAPkeAA==.',
Do='Dondeezy:BAAANQADCgYIBgAAAA==.',
Dr='Drdru:BAABNQAECn82AAINAAoKIhtACwDaAgANAAoKIhtACwDaAgABNQADCgUIBQAIAAAAAA==.Dreadshade:BAAANQAECgcICAAAAA==.Drlittle:BAAANQADCgQIBAAAAA==.Dropfort:BAAANQAECggIDwAAAA==.Drscruffles:BAAANQADCgcIBwAAAA==.Drstress:BAAANQADCgEIAQAAAA==.',
Du='Duifean:BAAANQADCgYIDgABNQAECggIHQAUAJwFAA==.Durkidurk:BAAANQADCgMIAwAAAA==.',
Dy='Dyabolykal:BAAANQADCgQIBAABNQADCgYIDAAIAAAAAA==.',
Ea='Easily:BAAANQAECgYIDgAAAA==.',
El='Ellyanthia:BAAANQAECgYICQABNQAECgUICAAIAAAAAA==.',
Em='Emachine:BAAANQADCgcIBwABNQAFFAcIGgABAPkeAA==.',
Ex='Exio:BAAANQAECgQJCgAAAA==.Extenze:BAAANQAECgUICwAAAA==.',
Fa='Fastasheet:BAACNQAFFH8kAAIJAAgKUxc8AwA4AgAJAAgKUxc8AwA4AgA1AAQKfzwAAgkACgqhJYUDAC8DAAkACgqhJYUDAC8DAAAA.',
Fe='Feralfed:BAAANQAECgcICgABNQAECgcIEgAIAAAAAA==.',
Fi='Fill:BAABNQAECn8rAAIVAAoK9yO5AQCdAwAVAAoK9yO5AQCdAwABNQAFFAYICwAJAOMhAA==.',
Fl='Flehtwo:BAACNQAFFH8XAAMUAAcKgwnVBQBgAQAUAAYKgwnVBQBgAQAKAAIKrQzLIQCGAAA1AAQKfzYAAxQACgpGHgk2AJ8CABQACgpGHgk2AJ8CAAoACQrRDBOEAIABAAAA.Flehunter:BAABNQAECn8cAAMWAAkKQhCTFgCjAQAWAAgK4g6TFgCjAQASAAYKZwz2tgAAAQAAAA==.Flyinbanana:BAAANQADCgQIBAABNQAECgoKQAAXAIUeAA==.',
Fo='Fortypi:BAAANQAECgYIBgABNQAFFAYICwAJAOMhAA==.',
Fr='Fragilelimbs:BAAANQAECgYIBgAAAA==.Fraglen:BAAANQADCgUIBQABNQAECgcICgAIAAAAAA==.Frags:BAAANQAECgcICgAAAA==.Fránknárf:BAAANQAECgEIAQAAAA==.',
Fu='Fuzzywuzzy:BAAANQAECgEIAQAAAA==.',
Ge='Genjyosanzo:BAABNQAECn8hAAIYAAcKzggrKwDxAAAYAAcKzggrKwDxAAAAAA==.',
Gh='Ghmaven:BAAANQAECgYIBQAAAA==.Ghostkrim:BAAANQADCgUIBQAAAA==.',
Gi='Gilljoww:BAABNQAECn8bAAIZAAgKSx9XKgByAgAZAAgKSx9XKgByAgAAAA==.Gireigtulb:BAAANQADCgYIBgAAAA==.',
Gn='Gnz:BAAANQAECgEIAQAAAA==.Gnzz:BAABNQAECn8qAAQaAAoKJxokGQAtAQAHAAoKRBVefQCBAQAaAAYKPhUkGQAtAQAbAAIKvhahCABJAAAAAA==.',
Go='Gocirr:BAABNQAECn8ZAAQPAAcKaQWcPgCUAAAPAAcKNgWcPgCUAAACAAIKaATtcABLAAANAAEKPAp0bQAnAAAAAA==.',
Gr='Grito:BAAANQADCgYICgAAAA==.',
Ha='Haehn:BAAANQADCgMIAwAAAA==.Halstorm:BAABNQAECn8bAAMKAAoK9hqHEgD6AgAKAAoK9hqHEgD6AgAUAAIK1QHxJgFEAAAAAA==.Hamburgler:BAAANQAECgEIAQABNQAECgUICAAIAAAAAA==.Harrysax:BAAANQABCgYIBgAAAA==.',
He='Hedrake:BAAANQAECgcICgAAAA==.Hexxytime:BAAANQADCgQIBAAAAA==.',
Hi='Hilazy:BAAANQAECgIIAwAAAA==.Hitzel:BAAANQAECgcIBwAAAA==.',
Hm='Hm:BAAANQAECgEIAQAAAA==.',
Ho='Holyphok:BAAANQAECgMIAwAAAA==.Hoobastank:BAAANQAECgQIBAAAAA==.Hotdog:BAAANQAECggIDwAAAA==.',
Ic='Icestormy:BAAANQAECgMIAwAAAA==.',
Ih='Ihavenofutur:BAABNQAECn8XAAMaAAkK8gdDHQC7AAAaAAUKtAlDHQC7AAAHAAcK2AR47gCrAAAAAA==.',
Il='Iliil:BAABNQAECn9BAAIZAAoKmyIXDQBIAwAZAAoKmyIXDQBIAwAAAA==.Illbiteyou:BAAANQADCgQIBAAAAA==.Illidantwo:BAACNQAFFH8YAAIGAAcKIheIBAAjAgAGAAcKIheIBAAjAgA1AAQKf0cAAgYACgoSJZYDAEcDAAYACgoSJZYDAEcDAAAA.',
Im='Imprints:BAABNQAECn8bAAIRAAkKLwZD1gBDAQARAAkKLwZD1gBDAQAAAA==.',
In='Inuk:BAABNQAECn8WAAINAAgKZxZaKwDDAQANAAgKZxZaKwDDAQAAAA==.',
Ir='Ironshaman:BAAANQAECgYIEQABNQAECgoKPQAcAG0jAA==.',
It='Italianapee:BAAANQAECgQIBAABNQAECggIFgANAGcWAA==.',
Ja='Jabu:BAAANQADCgQIAwABNQAECgIIBgAIAAAAAA==.Jada:BAAANQAECgYIDQAAAA==.Jaghatai:BAAANQADCgIIAgAAAA==.',
Je='Jenstonedart:BAABNQAECn8mAAIdAAoKoQx8EQBhAQAdAAoKoQx8EQBhAQAAAA==.Jeryeth:BAABNQAECn8hAAIRAAoK9xvEPwDLAgARAAoK9xvEPwDLAgAAAA==.Jerymander:BAAANQAFFAEIAQAAAA==.Jeryzard:BAAANQADCgYIDAAAAA==.',
Ji='Jiannybon:BAAANQADCgQICwAAAA==.',
Ju='Judgmental:BAAANQADCgYIBgAAAA==.Judidench:BAABNQAECn8XAAIeAAgKqCNIDgBGAwAeAAgKqCNIDgBGAwAAAA==.Juicewillis:BAAANQADCgIIAgAAAA==.',
Ka='Kain:BAECNQAFFH8XAAIOAAcKgyXKAACpAgAOAAcKgyXKAACpAgA1AAQKfzUAAw4ACgr0JE4DAI4DAA4ACQpiJk4DAI4DAAMABQrUGUWaAFcBAAAA.Kanda:BAAANQAECggIAQAAAA==.Kane:BAABNQAECn8jAAIZAAgK6BMOQQARAQAZAAgK6BMOQQARAQAAAA==.Karmasuture:BAAANQADCgYJBgABNQAECgMIAwAIAAAAAA==.Kata:BAAANQAECgcICAABNQAFFAUICQAFANUgAA==.Kaïn:BAAANQAECgMIBAABNQAECgoKQgADAMoiAA==.',
Ke='Kelsí:BAAANQAECgMICQAAAA==.',
Ki='Kiwí:BAABNQAECn8zAAIHAAoKVR+uLwBjAgAHAAoKVR+uLwBjAgAAAA==.',
Kr='Krasavice:BAABNQAECn9GAAISAAoKEx4rGwCzAgASAAoKEx4rGwCzAgAAAA==.Krenik:BAAANQADCggIHwAAAA==.Krimdin:BAAANQAECgMIAwAAAA==.Krimdrood:BAAANQADCgMIAwAAAA==.Krimshadow:BAAANQADCgcIBwAAAA==.Krimsonblade:BAAANQADCgQIBAAAAA==.Krimsondeath:BAAANQAECggICAAAAA==.Krimtohell:BAABNQAECn8YAAQBAAkKXxOsZABuAQABAAgKFRKsZABuAQAfAAEKHBveJQBRAAAgAAEK8A/eJAA6AAAAAA==.Krisp:BAAANQAECgcIEgAAAA==.',
Ku='Kurquaan:BAAANQADCggICAAAAA==.',
La='Lauranthalas:BAABNQAECn8ZAAISAAcKMAuWqwAXAQASAAcKMAuWqwAXAQAAAA==.Lavenderhaze:BAAANQAECgQIBAAAAA==.',
Le='Leathal:BAABNQAECn8iAAILAAkKKx2NUAApAgALAAkKKx2NUAApAgAAAA==.Legenddairy:BAAANQAECgYIBQAAAA==.Lemurshoes:BAAANQAECgIIAwAAAA==.Lemursneaker:BAABNQAECn8aAAIHAAgKKgW2EwFrAQAHAAgKKgW2EwFrAQAAAA==.Letsgomen:BAAANQADCgEIAQAAAA==.',
Li='Lightsfire:BAAANQADCgMIAwABNQAECgUICQAIAAAAAA==.Lightshock:BAAANQAECgUICQAAAA==.Linkblade:BAAANQADCggIDgAAAA==.Linkdin:BAAANQAECgQIBAAAAA==.Linkdrood:BAAANQAECggIDgAAAA==.Linky:BAAANQADCgIIBAAAAA==.',
Ll='Llaagg:BAAANQAECgIIAgAAAA==.',
Lo='Lokust:BAABNQAECn8jAAIKAAYKsSG/UwAYAgAKAAYKsSG/UwAYAgAAAA==.',
Lu='Lucentdawn:BAABNQAECn8jAAILAAcKfRWIegCpAQALAAcKfRWIegCpAQAAAA==.Luckyshrine:BAAANQABCggICwAAAA==.Ludachris:BAAANQAECgEIAQAAAA==.',
Ly='Lycanius:BAABNQAECn9FAAMdAAoKXht/BgAFAwAdAAoKXht/BgAFAwAPAAQKjRG2OQCqAAAAAA==.Lynqii:BAACNQAFFH8NAAMBAAcKYRHHCQDNAQABAAYK+RPHCQDNAQAfAAEKAQdkIQBHAAA1AAQKfxUAAwEABgrkHx6TALYBAAEABgrkHx6TALYBAB8AAQoVG5hrAEkAAAAA.',
Ma='Macaco:BAAANQADCgYIBgAAAA==.Malirra:BAABNQAECn8lAAIHAAoK5gTpCgF7AQAHAAoK5gTpCgF7AQAAAA==.Malëk:BAABNQAECn9CAAIDAAoKyiKPHQBNAwADAAoKyiKPHQBNAwAAAA==.Maximus:BAAANQADCgUIBQAAAA==.',
Me='Mechatholic:BAAANQAECgcIEQAAAA==.Medallis:BAAANQABCgcIDwAAAA==.Mellowlizard:BAACNQAFFH8aAAMBAAcK+R6pBQAUAgABAAYKYh2pBQAUAgAfAAEKViV6FABnAAA1AAQKfzcABCAACgo+JNsCAGcCAAEACgo+JEgaAI4CACAABwooItsCAGcCAB8AAwr2HtU7ANIAAAAA.Metuss:BAABNQAECn8WAAMJAAYKJR8dJAAFAgAJAAYKJR8dJAAFAgAMAAUKkxmKIgBvAQAAAA==.',
Mi='Miguel:BAAANQAECgUIDgAAAA==.Mira:BAABNQAECn8kAAISAAkKyA4seQCBAQASAAkKyA4seQCBAQAAAA==.',
Mk='Mkicon:BAABNQAECn8lAAIaAAcKBiDTCQAxAgAaAAcKBiDTCQAxAgAAAA==.Mkultra:BAABNQAECn8cAAMeAAoKvx54JgCjAgAeAAoKjR14JgCjAgAZAAYKTh3DVgCYAQAAAA==.',
Mo='Mogmoog:BAABNQAECn8iAAIeAAcKuhG3NgAWAQAeAAcKuhG3NgAWAQAAAA==.Mooganfreman:BAAANQAECgEIAQAAAA==.Moonangel:BAABNQAECn8pAAIcAAcK3hmHEwB7AQAcAAcK3hmHEwB7AQAAAA==.Morbodan:BAABNQAECn89AAIcAAoKbSMoAgAsAwAcAAoKbSMoAgAsAwAAAA==.Mornangus:BAAANQABCgMIAwAAAA==.Moshpit:BAAANQAFFAEIAQAAAA==.Motone:BAAANQAECgQIBAAAAA==.',
Mu='Multanni:BAABNQAECn8vAAIUAAkKrhhQKwD7AQAUAAkKrhhQKwD7AQAAAA==.',
My='Mykanoid:BAABNQAECn8XAAIhAAkKexFeCgCNAQAhAAkKexFeCgCNAQABNQAECgoKQAAXAIUeAA==.Myonecrosis:BAABNQAECn8qAAIBAAcKHSKuWgBHAgABAAcKHSKuWgBHAgAAAA==.',
Na='Nakrog:BAABNQAECn8iAAMQAAgKghoNEAAoAgAQAAgKghoNEAAoAgARAAEKkBplRgFEAAAAAA==.Napster:BAAANQAECgMIAwAAAA==.Nasa:BAACNQAFFH8XAAIJAAcKRA2OBQDGAQAJAAcKRA2OBQDGAQA1AAQKfyQAAgkACQrIHk8WAJ0CAAkACQrIHk8WAJ0CAAAA.',
Ne='Nellarixi:BAABNQAECn8aAAIYAAgKQhz2HQBQAgAYAAgKQhz2HQBQAgAAAA==.Nethus:BAAANQADCgcJCQAAAA==.',
Ni='Niivalyr:BAAANQABCgIIAQAAAA==.Nimbus:BAAANQAECgEIAQABNQAFFAcIGwAUADwXAA==.',
No='Nodens:BAAANQADCgcIEwAAAA==.Nomaa:BAABNQAECn8pAAIgAAcKkAISGADMAAAgAAcKkAISGADMAAAAAA==.Nomäd:BAABNQAECn8dAAITAAcKPxHHEAAqAQATAAcKPxHHEAAqAQAAAA==.Nosneb:BAAANQADCgMIBAABNQADCggIEAAIAAAAAA==.',
Ny='Nytedevil:BAABNQAECn8VAAIBAAkKQRUVkgC5AQABAAkKQRUVkgC5AQAAAA==.',
['Nì']='Nìtsua:BAAANQADCggIEAAAAA==.',
Ob='Obilivion:BAAANQAECgYIBwAAAA==.',
Og='Ogmount:BAAANQAECgMIAwAAAA==.',
Or='Orflame:BAABNQAECn8bAAMXAAgKeQeuKABvAQAXAAgKeQeuKABvAQAiAAEKKgXpJAAxAAAAAA==.',
Ph='Phantomhealz:BAAANQABCgIIAgAAAA==.Phrash:BAACNQAFFH8LAAIJAAYK4yFdCgAeAQAJAAYK4yFdCgAeAQA1AAQKfx0AAgkACQr9JGUJADsDAAkACQr9JGUJADsDAAAA.',
Pi='Pigbearmans:BAAANQADCgYIBgAAAA==.',
Pl='Plex:BAAANQAECgcICgABNQAECgkJIAAjAGEgAA==.',
Po='Pooldan:BAAANQAECgMJAgAAAA==.',
Pr='Praystatioñ:BAABNQAECn8sAAIkAAoKhBkPBQBmAgAkAAoKhBkPBQBmAgAAAA==.Premiumgank:BAAANQAECgIIAgAAAA==.Priestlink:BAAANQADCgcIGAAAAA==.Prtanks:BAAANQAECgUIBgAAAA==.',
Pu='Purerform:BAAANQADCgcIBwAAAA==.',
Qu='Quelidra:BAAANQADCgUIBQAAAA==.Quepaspete:BAAANQADCgYIBwAAAA==.',
Ra='Raa:BAABNQAECn9DAAISAAkKnSUHBABiAwASAAkKnSUHBABiAwAAAA==.Racker:BAABNQAECn8UAAITAAcK2BLzEQCFAQATAAcK2BLzEQCFAQAAAA==.Ragou:BAAANQADCgQIBAAAAA==.Rainfallen:BAABNQAECn8UAAMgAAoKRwlYDACdAQAgAAoKRwlYDACdAQAfAAEKWgYUNgAkAAAAAA==.',
Re='Rengots:BAAANQAECgYICgAAAA==.Rephtide:BAAANQAECgUIEAAAAA==.Responsible:BAABNQAECn8yAAIRAAoKgyCwJwAbAwARAAoKgyCwJwAbAwAAAA==.',
Rh='Rhaez:BAAANQAECgEIAQAAAA==.Rhall:BAAANQADCgYIBgAAAA==.Rhetoricdork:BAAANQAECggICQABNQAFFAgIGwAHANUcAA==.',
Ri='Ritter:BAAANQADCgQIBAAAAA==.',
Ro='Rocksham:BAAANQAECggICAAAAA==.Rocktober:BAAANQAECgQIBQAAAA==.Rogmash:BAAANQAECgUJCwAAAA==.Rokkoz:BAABNQAECn8wAAINAAkKKh7pCgDhAgANAAkKKh7pCgDhAgAAAA==.Romer:BAACNQAFFH8FAAIlAAIKOQGpCgBPAAAlAAIKOQGpCgBPAAA1AAQKfyMAAiUACQqFCCQWAIEBACUACQqFCCQWAIEBAAAA.Rompintom:BAAANQAECgIIAgAAAA==.Rookiestar:BAABNQAECn8mAAImAAkKaA5rPgC+AQAmAAkKaA5rPgC+AQAAAA==.',
Ru='Rumí:BAAANQAECgUICAAAAA==.',
Sa='Sabb:BAAANQADCgYIEAAAAA==.Samstephens:BAAANQADCgQIBAABNQAECggIHQAUAJwFAA==.Saphroniå:BAAANQADCgcIGQAAAA==.Sass:BAABNQAECn8/AAMCAAoKFRxcMABeAgACAAgKWhtcMABeAgANAAQKvxgkMgAbAQAAAA==.Sazed:BAAANQADCgEIAQAAAA==.',
Sc='Schend:BAAANQADCgYICwAAAA==.Scibiol:BAAANQADCgIIAgAAAA==.',
Se='Sed:BAAANQAECgIIBQAAAA==.Serrana:BAAANQADCgUIBQAAAA==.',
Sh='Shadax:BAAANQAECgYIBgAAAA==.Shadowmortis:BAAANQAECgQIBQAAAA==.Shadowwilder:BAAANQAECgcIEAAAAA==.Shirokhan:BAABNQAECn8wAAIHAAkKsxm0iABtAgAHAAkKsxm0iABtAgAAAA==.Shootum:BAAANQADCgYIDAAAAA==.Shïfthappens:BAAANQADCgUIBQAAAA==.',
Si='Sidewinderx:BAABNQAECn8UAAInAAcKEwXcdgDHAAAnAAcKEwXcdgDHAAAAAA==.Sinlock:BAABNQAECn8dAAMBAAgK3B5NZAAtAgABAAcKTR9NZAAtAgAfAAQKMxH7NADvAAAAAA==.',
Sk='Skadí:BAAANQAECgYIBQAAAA==.Skrot:BAAANQADCgYIBgABNQAECgoKLwAJALYXAA==.',
Sm='Smallarms:BAAANQADCgIIAgAAAA==.Smef:BAAANQADCgEIAQAAAA==.',
Sn='Snagglespark:BAABNQAECn8rAAMUAAoKCR5ZHgAVAwAUAAoKCR5ZHgAVAwAKAAYKQQvFtQACAQAAAA==.Sneakykrim:BAAANQABCgEIAQAAAA==.Sneakylink:BAAANQADCgYIEQAAAA==.Snowbunni:BAAANQAECgUIDAAAAA==.',
So='Soladrian:BAAANQAECgcIDAAAAA==.Solanthion:BAEANQADCgcIBwABNQAECgoKIgADAOEIAA==.',
Sp='Spankyee:BAAANQADCgQIBAAAAA==.',
Sr='Srtaco:BAAANQAECgUICAAAAA==.',
St='Starz:BAAANQADCgYIBAAAAA==.Stelmaria:BAAANQAECgMIAwABNQAECgoKMQASAIQbAA==.',
Su='Sunchipzz:BAAANQADCgQIBAAAAA==.Sundayschool:BAAANQAECgcIEgAAAA==.Sunwing:BAAANQAECgUIBgAAAA==.',
Sy='Syyia:BAAANQADCgIIAgAAAA==.',
['Sé']='Séraph:BAAANQAECgUIBwAAAA==.',
['Só']='Sóozabimaru:BAAANQAECgQICQAAAA==.',
Ta='Tahano:BAAANQABCgIIAgAAAA==.Talljeff:BAAANQAECggIDgAAAA==.Tankarmor:BAABNQAECn8jAAIQAAYKaQ8dHwBZAQAQAAYKaQ8dHwBZAQAAAA==.Taylorswif:BAACNQAFFH8HAAMHAAQKrQynLQAjAQAHAAQKrQynLQAjAQAaAAEKSAfzFQA+AAA1AAQKfyEAAwcACgqAGlpoAK0CAAcACQowGlpoAK0CABoAAQq1HC0tAFYAAAAA.',
Tc='Tcharta:BAABNQAECn9AAAMXAAoKhR4PBAAvAwAXAAoKhR4PBAAvAwAhAAEKAAA6QAArAAAAAA==.',
Te='Teostradin:BAAANQAECgQIBAAAAA==.',
Th='Thefamousone:BAAANQADCgYICAAAAA==.Theiá:BAAANQAECgEIAQAAAA==.Thermotide:BAAANQAECgcIEAAAAA==.Thornpaw:BAAANQADCgQIBAAAAA==.Thoror:BAAANQAECgUICgAAAA==.Thunderbolt:BAAANQADCgcIBwABNQAECgQIBAAIAAAAAA==.Thundernütz:BAAANQADCgIIAwAAAA==.Thymós:BAAANQAECgUIDAAAAA==.',
Ti='Tiffina:BAAANQADCgYICQAAAA==.Tiffzen:BAABNQAECn8cAAISAAcK7QdX3ABIAQASAAcK7QdX3ABIAQAAAA==.Timeskip:BAAANQADCggIBgAAAA==.Tinyfaith:BAAANQAECgQICAAAAA==.Titum:BAACNQAFFH8IAAIBAAQKvg2hHgCaAAABAAQKvg2hHgCaAAA1AAQKfyIAAgEACgqxINcKAPsCAAEACgqxINcKAPsCAAE1AAUUBggMAAcA5ggA.',
To='Tongpooh:BAABNQAECn8vAAIJAAoKthc9GACHAgAJAAoKthc9GACHAgAAAA==.',
Tr='Treeberk:BAAANQAECgIIAgAAAA==.Truelink:BAAANQADCggIEgAAAA==.',
Tu='Tuba:BAAANQAECggIBQAAAA==.Tuckerherout:BAAANQAECgYIEAAAAA==.Tundro:BAAANQAECgEIAQAAAA==.',
Tw='Twix:BAAANQAECgIIAgABNQAECgQJCgAIAAAAAA==.',
['Tî']='Tîtån:BAABNQAECn8eAAMfAAYKJw3RIgBbAQAfAAYKJw3RIgBbAQAgAAEKAACDNgAbAAAAAA==.',
Uh='Uh:BAABNQAECn8aAAInAAgK9x2VIgB6AgAnAAgK9x2VIgB6AgABNQAFFAYICwAJAOMhAA==.',
Un='Undeadlock:BAAANQAECgQIEAAAAA==.',
Va='Vale:BAAANQADCgEIAQAAAA==.Valynda:BAAANQADCgEIAQAAAA==.',
Vg='Vgmking:BAABNQAECn8qAAIZAAkKCReSQAD8AQAZAAkKCReSQAD8AQAAAA==.',
Vi='Vigdis:BAAANQADCgcIBwAAAA==.Vindorei:BAAANQADCgUIDgAAAA==.',
Vo='Voidfed:BAAANQADCgQIBAABNQAECgcIEgAIAAAAAA==.Voidfu:BAAANQADCgIIAgAAAA==.Voidmydrama:BAAANQADCgYIBgAAAA==.Voidrefund:BAAANQADCgYIBgAAAA==.Vokzhen:BAABNQAECn81AAIYAAoKdhoeFQC4AgAYAAoKdhoeFQC4AgAAAA==.Volescu:BAABNQAECn8dAAMfAAoK8xwTAwDlAQAfAAgKKxwTAwDlAQABAAQKbBm+gQAlAQAAAA==.',
Wa='Walkerboah:BAABNQAECn8gAAIBAAkKaw9vWwCIAQABAAkKaw9vWwCIAQAAAA==.Warmachinne:BAAANQAECgEIAQAAAA==.',
We='Weel:BAABNQAECn85AAILAAoKmhl1GQC+AgALAAoKmhl1GQC+AgAAAA==.',
Wo='Wolfspider:BAAANQAECgIIAwAAAA==.',
Wy='Wyland:BAAANQAECgQIBQAAAA==.Wylander:BAABNQAECn8hAAILAAkKuSBVEwDzAgALAAkKuSBVEwDzAgAAAA==.Wylandvoker:BAAANQADCgIIAgAAAA==.',
Xa='Xanun:BAAANQADCgMIAwAAAA==.',
Xe='Xeri:BAABNQAECn8bAAIVAAoKXhnUCwCzAgAVAAoKXhnUCwCzAgABNQAFFAcIGAAoALgiAA==.Xeromus:BAABNQAECn8hAAMCAAcK+A8xPgD/AAACAAcK+A8xPgD/AAANAAEKxQO5fgAiAAAAAA==.Xetsus:BAAANQADCgUJBQAAAA==.',
Ya='Yang:BAAANQABCgEIAQAAAA==.',
Yo='Yoink:BAAANQADCgUIBQAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Yv='Yvelmaya:BAABNQAECn8pAAMKAAcKsxxaOQACAgAKAAcKsxxaOQACAgAUAAEKAAAJUAEmAAAAAA==.',
Za='Zabawaba:BAAANQAECgcICQABNQAECggIDwAIAAAAAA==.Zaboomaprune:BAABNQAECn8bAAMPAAkKZgkYNgD1AAAPAAkKZgkYNgD1AAAdAAQKwwFdOABcAAAAAA==.Zarika:BAACNQAFFH8YAAIoAAcKuCI+AACBAgAoAAcKuCI+AACBAgA1AAQKfz0AAygACgpkJlYAANkDACgACgpzJVYAANkDACYACQorJdQKAAkDAAAA.Zarì:BAAANQAECgUIBwABNQAFFAcIGAAoALgiAA==.',
Ze='Zeknull:BAABNQAECn8dAAMLAAgKTRwJOQCAAgALAAgKTRwJOQCAAgADAAUKYg8xAgEcAQABNQAECgoKJwAFAFAdAA==.Zekthal:BAABNQAECn8nAAMFAAoKUB0lCgCRAgAFAAoKUB0lCgCRAgAGAAEK4QXjfwAcAAAAAA==.Zenio:BAAANQADCgIIAgAAAA==.Zennah:BAAANQADCggIFgAAAA==.Zephy:BAAANQADCgcICQAAAA==.',
Zr='Zrgl:BAAANQADCggICAAAAA==.',
['Zä']='Zäo:BAACNQAFFH8FAAIBAAIK6xcdLwCbAAABAAIK6xcdLwCbAAA1AAQKfyQABCAACQphItgBACcDACAACQo7H9gBACcDAAEABQq7HTqiAJEBAB8AAwo8I2g5ANsAAAAA.',
['Ïk']='Ïkea:BAAANQAECgQIBwAAAA==.',
['ßl']='ßloodhunter:BAAANQAECgUIAgAAAA==.',
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
