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

local lookup = {'Warlock-Demonology','Druid-Balance','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Mage-Arcane','Rogue-Assassination','Monk-Windwalker','Unknown-Unknown','Shaman-Restoration','Paladin-Holy','Monk-Mistweaver','Druid-Restoration','Paladin-Protection','Druid-Guardian','Warrior-Protection','Warrior-Arms','Hunter-BeastMastery','Warrior-Fury','Shaman-Elemental','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Preservation','Priest-Shadow','DeathKnight-Blood','Mage-Frost','Mage-Fire','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Monk-Brewmaster','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Acupuncher:BAAANQAECgIIAgAAAA==.',
Ad='Adamsandler:BAAANQADCggICAAAAA==.Adiwolf:BAAANQAECgIIBAAAAA==.',
Al='Alcha:BAABNQAECn8cAAIBAAgKXBtQYAA3AgABAAgKXBtQYAA3AgAAAA==.Alenndar:BAAANQADCgEIAQAAAA==.Alexdaddario:BAABNQAECn8UAAICAAcKWx3hRwDMAQACAAcKWx3hRwDMAQAAAA==.Algaefungi:BAAANQAECgIICAAAAA==.Althena:BAAANQAECgEIAQABNQAECgoKSAADAMoiAA==.Alystana:BAAANQADCgUIBwAAAA==.',
Am='Amberelle:BAAANQADCgQIBAAAAA==.',
An='Anastera:BAAANQADCgYIBwAAAA==.Animeniac:BAABNQAECn8xAAIEAAgKkyKrBQBIAgAEAAgKkyKrBQBIAgAAAA==.Anticlimax:BAABNQAECn8uAAQFAAoKGBDJJQBWAQAFAAgKsg/JJQBWAQAEAAYK1Ay4GQAZAQAGAAYKtAm4VAC8AAAAAA==.Antilaw:BAAANQAECgYICgAAAA==.Antisocial:BAAANQAECgQIDQAAAA==.Antistab:BAAANQAECgQICgAAAA==.',
Ao='Aoibhneas:BAAANQADCgcIBwAAAA==.',
Ap='Apprentice:BAACNQAFFH8HAAIHAAMKkho5MAAOAQAHAAMKkho5MAAOAQA1AAQKfx4AAgcACQoXJNAzACMDAAcACQoXJNAzACMDAAAA.',
Ar='Ariha:BAAANQAECgQIBQAAAA==.Arnokk:BAAANQADCgYIDAAAAA==.Artrael:BAAANQADCggJCAAAAA==.',
At='Atorim:BAAANQADCgIIAgABNQAECggIFwAIAOsMAA==.',
Av='Avienndha:BAABNQAECn8xAAIEAAgKShloCwCHAQAEAAgKShloCwCHAQAAAA==.Avriel:BAAANQAECgQICQABNQAECgoKSAADAMoiAA==.',
Ba='Barbatos:BAAANQAECgIIAgAAAA==.',
Be='Beardeddrunk:BAAANQADCgUJBQAAAA==.Beornwildlaw:BAAANQABCgcIDgAAAA==.',
Bi='Bigsheet:BAAANQAECgUIBwABNQAFFAgIJAAJAFMXAA==.',
Bl='Bloodyflame:BAAANQADCgEIAQAAAA==.',
Bo='Bobbytofva:BAAANQAECgMIBAAAAA==.Bobthedurgon:BAAANQADCgUIBQAAAA==.Bobthegrinch:BAAANQADCgQIBAAAAA==.Boneloss:BAAANQADCgQIBAAAAA==.Bonkini:BAAANQAECggIEAAAAA==.Bonkí:BAAANQAECggICQABNQAECggIEAAKAAAAAA==.Boochaka:BAABNQAECn8qAAILAAoKyhy2JgB+AgALAAoKyhy2JgB+AgAAAA==.Bouman:BAAANQADCgYIBgAAAA==.Bouquet:BAABNQAECn8pAAIHAAoKJQaxhwCFAQAHAAoKJQaxhwCFAQAAAA==.',
Br='Brewdog:BAAANQAECgQICgAAAA==.Brickdeath:BAAANQAECgEIAQAAAA==.Brickfists:BAAANQAECgEIAQAAAA==.Brotherfuzz:BAAANQAECgIIAwAAAA==.',
Bu='Buckangel:BAAANQAECggIDAABNQAFFAgIEwAMACkmAA==.Busterposer:BAABNQAECn8iAAIGAAoKSSDFCgDlAgAGAAoKSSDFCgDlAgAAAA==.',
['Bë']='Bëan:BAAANQAECgYIBgAAAA==.',
Ca='Caelvaris:BAAANQADCgEIAQAAAA==.Calabooca:BAAANQADCgUICAAAAA==.Canadaclown:BAAANQADCgIIAgAAAA==.Candor:BAAANQADCgUIBQAAAA==.',
Ch='Cheesefries:BAABNQAECn8iAAINAAcKUhokFgCGAQANAAcKUhokFgCGAQAAAA==.Chereth:BAABNQAECn8jAAIOAAoKRh+TBQCCAwAOAAoKRh+TBQCCAwAAAA==.Chratos:BAAANQADCgYIBgAAAA==.',
Cl='Clapt:BAAANQAECgQIBgAAAA==.Clapton:BAAANQAECgQICgAAAA==.Claptone:BAABNQAECn8VAAILAAcKwRS3hwB3AQALAAcKwRS3hwB3AQAAAA==.',
Co='Corpuscle:BAABNQAECn8sAAMPAAoKJxjnEAAGAgAPAAoKJxjnEAAGAgAMAAIKogoPDwFZAAAAAA==.',
Cr='Critcomander:BAABNQAECn8rAAIDAAkKcQ0yrADHAQADAAkKcQ0yrADHAQAAAA==.Critties:BAAANQADCgMIAwAAAA==.Crowfive:BAAANQAECgUIBQAAAA==.Crueldin:BAABNQAECn8aAAMMAAgKIhC1lwBaAQAMAAgKIhC1lwBaAQADAAEKkws4nAE5AAAAAA==.',
Da='Dalsen:BAABNQAECn80AAIQAAoKPw5yIQCOAQAQAAoKPw5yIQCOAQAAAA==.Dalvulpe:BAAANQAECgIIAgABNQAECgoKNAAQAD8OAA==.Dankchop:BAABNQAECn8ZAAMRAAgK+haLGwCCAQARAAYKHxWLGwCCAQASAAgKshU7wAB8AQAAAA==.Darim:BAAANQADCgIIAgAAAA==.Darkbishop:BAAANQABCgYICgAAAA==.Darklink:BAABNQAECn8UAAITAAgK2BEuggCaAQATAAgK2BEuggCaAQAAAA==.Dawnlighted:BAAANQADCgMIAwAAAA==.',
De='Deadlyshiet:BAAANQAECgMIBQABNQAFFAgIJAAJAFMXAA==.Defibrilater:BAAANQAECgQICAAAAA==.Demonfed:BAAANQABCgIIAgABNQAECgcIEgAKAAAAAA==.Demonkrim:BAAANQADCgQIBAAAAA==.Demonlink:BAAANQADCgUIBQAAAA==.Denrin:BAAANQAECgYIEgAAAA==.Deskpop:BAAANQADCgQIBAAAAA==.',
Di='Diabolikal:BAAANQADCgYIDAAAAA==.Dill:BAABNQAECn9XAAIUAAoK6CSIAADVAwAUAAoK6CSIAADVAwAAAA==.Divinesmite:BAAANQADCgcICAAAAA==.',
Dm='Dmachine:BAABNQAECn8mAAMSAAoK8BYHOwBGAgASAAoK6BYHOwBGAgARAAIKhhR8MABwAAABNQAFFAgIHAABAJgdAA==.',
Do='Dondeezy:BAAANQADCgYIBgAAAA==.',
Dr='Drdru:BAABNQAECn82AAIOAAoKIhuDDQDZAgAOAAoKIhuDDQDZAgABNQADCgUIBQAKAAAAAA==.Dreadshade:BAAANQAECgYICAAAAA==.Drheals:BAAANQADCgIIAgAAAA==.Drlittle:BAAANQADCgQIBAAAAA==.Dropfort:BAAANQAECggIDwAAAA==.Drscruffles:BAAANQADCgcIBwAAAA==.Drstress:BAAANQADCgEIAQAAAA==.',
Du='Duifean:BAAANQADCgYIFAABNQAECggIJAAVACIGAA==.Durkidurk:BAAANQADCgMIAwAAAA==.',
Dy='Dyabolykal:BAAANQADCgQIBAABNQADCgYIDAAKAAAAAA==.',
Ea='Easily:BAAANQAECgYIDgAAAA==.',
El='Ellyanthia:BAAANQAECgYICQABNQAECgUICAAKAAAAAA==.',
Em='Emachine:BAAANQADCgcIBwABNQAFFAgIHAABAJgdAA==.',
Ex='Exio:BAAANQAECgQJCgAAAA==.Extenze:BAAANQAECgUICwAAAA==.',
Fa='Fastasheet:BAACNQAFFH8kAAIJAAgKUxc8AwA4AgAJAAgKUxc8AwA4AgA1AAQKfzwAAgkACgqhJUoEACkDAAkACgqhJUoEACkDAAAA.',
Fe='Feralfed:BAAANQAECgcICgABNQAECgcIEgAKAAAAAA==.',
Fi='Fill:BAABNQAECn8rAAIWAAoK9yO5AQCdAwAWAAoK9yO5AQCdAwABNQAFFAcIDAAJAEEfAA==.',
Fl='Flehtwo:BAACNQAFFH8YAAMVAAcKgwlVBwBZAQAVAAYKgwlVBwBZAQALAAIKzgzLIQCGAAA1AAQKfzcAAxUACgpGHgk2AJ8CABUACgpGHgk2AJ8CAAsACQrRDBOEAIABAAAA.Flehunter:BAABNQAECn8fAAMXAAkKqxGPFwC/AQAXAAgKghCPFwC/AQATAAYKZwysxwAIAQAAAA==.Flyinbanana:BAAANQADCgQIBAABNQAECgoKTAAYAJ8fAA==.',
Fo='Fortypi:BAAANQAECgYIBgABNQAFFAcIDAAJAEEfAA==.',
Fr='Fragilelimbs:BAAANQAECggICAAAAA==.Fraglen:BAAANQADCgUIBQABNQAECgcICgAKAAAAAA==.Frags:BAAANQAECgcICgAAAA==.Fránknárf:BAAANQAECgEIAQAAAA==.',
Fu='Fuzzywuzzy:BAAANQAECgMIAwAAAA==.',
Ge='Genjyosanzo:BAABNQAECn8oAAIZAAgK7giOJwAwAQAZAAgK7giOJwAwAQAAAA==.',
Gh='Ghmaven:BAAANQAECgUIBQAAAA==.Ghostkrim:BAAANQADCgUIBQAAAA==.',
Gi='Gilljoww:BAABNQAECn8bAAIaAAgKSx9XKgByAgAaAAgKSx9XKgByAgAAAA==.Gireigtulb:BAAANQADCgYIBgAAAA==.',
Gn='Gnz:BAAANQAECgEIAQAAAA==.Gnzz:BAABNQAECn8tAAQbAAoK/hwkGQAtAQAHAAoKDRoBbQDGAQAbAAYKPhUkGQAtAQAcAAIKvhZ7CgBJAAAAAA==.',
Go='Gocirr:BAABNQAECn8cAAQQAAcK0AV8RQCWAAAQAAcKngV8RQCWAAACAAIKaATfeABLAAAOAAEKPAomdwAnAAAAAA==.',
Gr='Grito:BAAANQADCgYICgAAAA==.Gryphon:BAAANQAECgQIBAAAAA==.',
Ha='Haehn:BAAANQADCgMIAwAAAA==.Halstorm:BAABNQAECn8hAAMLAAoKBBt1FgDuAgALAAoKBBt1FgDuAgAVAAIK1QHxJgFEAAAAAA==.Hamburgler:BAAANQAECgIIAwABNQAECgUICAAKAAAAAA==.Harrysax:BAAANQABCgYIBgAAAA==.',
He='Hedrake:BAAANQAECggICwAAAA==.Hexxytime:BAAANQADCgQIBAAAAA==.',
Hi='Hilazy:BAAANQAECgIIAwAAAA==.Hitzel:BAAANQAECgcICQAAAA==.',
Hm='Hm:BAAANQAECgEIAQAAAA==.',
Ho='Holyphok:BAAANQAECgMIAwAAAA==.Hoobastank:BAAANQAECgQIBAAAAA==.Hotdog:BAABNQAECn8VAAQdAAoKUhYiGAAXAgAdAAkKLhQiGAAXAgAaAAMKdRuokQC/AAAeAAIKMwdAlgBfAAAAAA==.',
Ic='Icestormy:BAAANQAECgMIAwAAAA==.',
Ih='Ihavenofutur:BAABNQAECn8ZAAMbAAkKigjOHwDFAAAHAAcK2AQMUQEJAQAbAAUKvwrOHwDFAAAAAA==.',
Il='Iliil:BAABNQAECn9JAAMaAAoKGCMXDQBIAwAaAAoKGCMXDQBIAwAdAAEKAACyogAAAAAAAA==.Illbiteyou:BAAANQADCgQIBAAAAA==.Illidantwo:BAACNQAFFH8aAAIGAAgKrROIBAAjAgAGAAgKrROIBAAjAgA1AAQKf0cAAgYACgoSJWEEAEMDAAYACgoSJWEEAEMDAAAA.',
Im='Imprints:BAABNQAECn8bAAISAAkKMgZD1gBDAQASAAkKMgZD1gBDAQAAAA==.',
In='Inuk:BAABNQAECn8WAAIOAAgKZxZaKwDDAQAOAAgKZxZaKwDDAQAAAA==.',
Ir='Ironshaman:BAAANQAECgYIEQABNQAECgoKPQAIAG0jAA==.',
It='Italianapee:BAAANQAECgQIBAABNQAECggIFgAOAGcWAA==.',
Ja='Jabu:BAAANQADCgQIAwABNQAECgIIBgAKAAAAAA==.Jada:BAAANQAECgUIDQAAAA==.Jaghatai:BAAANQADCgIIAgAAAA==.',
Je='Jenstonedart:BAABNQAECn8rAAIfAAoKAg0iFABpAQAfAAoKAg0iFABpAQAAAA==.Jeryeth:BAABNQAECn8pAAISAAoK/B7EPwDLAgASAAoK/B7EPwDLAgAAAA==.Jerymander:BAAANQAFFAEIAQAAAA==.Jeryzard:BAAANQADCgYIDAAAAA==.',
Ji='Jiannybon:BAAANQADCgQICwAAAA==.',
Ju='Judgmental:BAAANQADCgYIBgAAAA==.Judidench:BAABNQAECn8XAAIdAAgKqCNIDgBGAwAdAAgKqCNIDgBGAwAAAA==.Juicewillis:BAAANQADCgIIAgAAAA==.',
Ka='Kain:BAECNQAFFH8XAAIPAAcKgyXKAACpAgAPAAcKgyXKAACpAgA1AAQKfzUAAw8ACgr0JE4DAI4DAA8ACQpiJk4DAI4DAAMABQrUGUeuAF0BAAAA.Kanda:BAAANQAECggIAQAAAA==.Kane:BAABNQAECn8jAAIaAAgK6BOkWACQAQAaAAgK6BOkWACQAQAAAA==.Karmasuture:BAAANQADCgYJBgABNQAECgMIAwAKAAAAAA==.Kata:BAAANQAECgcIDgABNQAFFAUICwAFANUgAA==.Kaïn:BAAANQAECgMIBAABNQAECgoKSAADAMoiAA==.',
Ke='Kelsí:BAAANQAECgYIDwAAAA==.',
Ki='Kiwí:BAABNQAECn86AAIHAAoKGyCsJQCdAgAHAAoKGyCsJQCdAgAAAA==.',
Kr='Krasavice:BAABNQAECn9LAAITAAoK/h9LFwDeAgATAAoK/h9LFwDeAgAAAA==.Krenik:BAAANQADCggIHwAAAA==.Krimdin:BAAANQAECgMIAwAAAA==.Krimdrood:BAAANQADCgMIAwAAAA==.Krimshadow:BAAANQADCgcIBwAAAA==.Krimsonblade:BAAANQADCgQIBAAAAA==.Krimsondeath:BAAANQAECggICAAAAA==.Krimtohell:BAABNQAECn8YAAQBAAkKXxMQcQByAQABAAgKFRIQcQByAQAgAAEKHBvTKQBPAAAhAAEK8A8jKgA6AAAAAA==.Krisp:BAAANQAECgcIEgAAAA==.',
Ku='Kurquaan:BAAANQADCggICAAAAA==.',
La='Lauranthalas:BAABNQAECn8ZAAITAAcKMAtFwQAVAQATAAcKMAtFwQAVAQAAAA==.Lavenderhaze:BAAANQAECgQIBAAAAA==.',
Le='Leathal:BAABNQAECn8pAAIMAAkKTR2uLABiAgAMAAkKTR2uLABiAgAAAA==.Legenddairy:BAAANQAECgcIDAAAAA==.Lemurshoes:BAAANQAECgIIAwAAAA==.Lemursneaker:BAABNQAECn8aAAIHAAgKKgW2EwFrAQAHAAgKKgW2EwFrAQAAAA==.Letsgomen:BAAANQADCgEIAQAAAA==.',
Li='Lightsfire:BAAANQADCgMIAwABNQAECgUICQAKAAAAAA==.Lightshock:BAAANQAECgUICQAAAA==.Linkblade:BAAANQADCggIDgAAAA==.Linkborne:BAAANQABCgMIAwAAAA==.Linkdin:BAAANQAECgQIBAAAAA==.Linkdrood:BAAANQAECggIDgAAAA==.Linky:BAAANQADCgIIBAAAAA==.',
Ll='Llaagg:BAAANQAECgIIAgAAAA==.',
Lo='Lokust:BAABNQAECn8nAAILAAYKsSG/UwAYAgALAAYKsSG/UwAYAgAAAA==.',
Lu='Lucentdawn:BAABNQAECn8lAAIMAAkKtBIGUQC9AQAMAAkKtBIGUQC9AQAAAA==.Luckyshrine:BAAANQABCggICwAAAA==.Ludachris:BAAANQAECgEIAQAAAA==.',
Ly='Lycanius:BAABNQAECn9FAAMfAAoKXht/BgAFAwAfAAoKXht/BgAFAwAQAAQKjBEtQQCnAAAAAA==.Lynqii:BAACNQAFFH8NAAMBAAcKYRHHCQDNAQABAAYK+RPHCQDNAQAgAAEKAQdkIQBHAAA1AAQKfxUAAwEABgrkHx6TALYBAAEABgrkHx6TALYBACAAAQoVG5hrAEkAAAAA.',
Ma='Macaco:BAAANQADCgYIBgAAAA==.Malirra:BAABNQAECn8nAAIHAAoKZAbpCgF7AQAHAAoKZAbpCgF7AQAAAA==.Malëk:BAABNQAECn9IAAIDAAoKyiKPHQBNAwADAAoKyiKPHQBNAwAAAA==.Maximus:BAAANQADCgUIBQAAAA==.',
Me='Mechatholic:BAAANQAECgcIEQAAAA==.Medallis:BAAANQABCgcIDwAAAA==.Mellowlizard:BAACNQAFFH8cAAQBAAgKmB2pBQAUAgABAAYKYh2pBQAUAgAgAAEKViV6FABnAAAhAAEKtBatDABaAAA1AAQKfzkABCEACgo+JOkDAFgCAAEACgo+JDUkAPMCACEABwooIukDAFgCACAAAwr2HtU7ANIAAAAA.Metuss:BAABNQAECn8bAAMJAAgKEhsdJAAFAgAJAAcKAR0dJAAFAgANAAYKaxqKIgBvAQAAAA==.',
Mi='Miguel:BAAANQAECgUIDgAAAA==.Mira:BAABNQAECn8mAAITAAoKUQ72cQDAAQATAAoKUQ72cQDAAQAAAA==.',
Mk='Mkicon:BAABNQAECn8qAAIbAAcKBiDTCQAxAgAbAAcKBiDTCQAxAgAAAA==.Mkultra:BAABNQAECn8fAAMdAAoKKSB4JgCjAgAdAAoK9x54JgCjAgAaAAYKTh3DVgCYAQAAAA==.',
Mo='Mogmoog:BAABNQAECn8pAAIdAAgKNRHLMQBNAQAdAAgKNRHLMQBNAQAAAA==.Mooganfreman:BAAANQAECgEIAQAAAA==.Moonangel:BAABNQAECn8wAAIIAAgKSRlmDwDEAQAIAAgKSRlmDwDEAQAAAA==.Morbodan:BAABNQAECn89AAIIAAoKbSOxAgAhAwAIAAoKbSOxAgAhAwAAAA==.Mornangus:BAAANQABCgMIAwAAAA==.Moshpit:BAAANQAFFAEIAQAAAA==.Motone:BAAANQAECgQIBAAAAA==.',
Mu='Multanni:BAABNQAECn8zAAIVAAoK4RkTIQBcAgAVAAoK4RkTIQBcAgAAAA==.',
My='Mykanoid:BAABNQAECn8XAAIiAAkKexHICwCLAQAiAAkKexHICwCLAQABNQAECgoKTAAYAJ8fAA==.Myonecrosis:BAABNQAECn8xAAIBAAgKGyFrRAD2AQABAAgKGyFrRAD2AQAAAA==.',
Na='Nakrog:BAABNQAECn8iAAMRAAgKghoNEAAoAgARAAgKghoNEAAoAgASAAEKkBplRgFEAAAAAA==.Napster:BAAANQAECgMIAwAAAA==.Nasa:BAACNQAFFH8ZAAIJAAgK9guOBQDGAQAJAAgK9guOBQDGAQA1AAQKfyQAAgkACQrIHk8WAJ0CAAkACQrIHk8WAJ0CAAAA.',
Ne='Nellarixi:BAABNQAECn8aAAIZAAgKQhz2HQBQAgAZAAgKQhz2HQBQAgAAAA==.Nethus:BAAANQADCgcICQAAAA==.',
Ni='Niivalyr:BAAANQABCgIIAQAAAA==.Nimbus:BAAANQAECgEIAQABNQAFFAUICQAVADIWAA==.',
No='Nodens:BAAANQADCgcIEwAAAA==.Nomaa:BAABNQAECn8wAAIhAAgKpgISGADMAAAhAAgKpgISGADMAAAAAA==.Nomäd:BAABNQAECn8kAAIUAAgKixBYEABcAQAUAAgKixBYEABcAQAAAA==.Nosneb:BAAANQADCgMIBAABNQADCggIEAAKAAAAAA==.',
Ny='Nytedevil:BAABNQAECn8XAAIBAAoKMBWBcQBxAQABAAoKMBWBcQBxAQAAAA==.',
['Nì']='Nìtsua:BAAANQADCggIEAAAAA==.',
Ob='Obilivion:BAAANQAECgYIBwAAAA==.',
Og='Ogmount:BAAANQAECgMIAwAAAA==.',
Or='Orflame:BAABNQAECn8bAAMYAAgKeQeuKABvAQAYAAgKeQeuKABvAQAjAAEKKgXpJAAxAAAAAA==.',
Ph='Phantomhealz:BAAANQABCgIIAgAAAA==.Phrash:BAACNQAFFH8MAAIJAAcKQR9dCgAeAQAJAAcKQR9dCgAeAQA1AAQKfx0AAgkACQr9JGUJADsDAAkACQr9JGUJADsDAAAA.',
Pi='Pigbearmans:BAAANQADCgYIBgAAAA==.',
Pl='Plex:BAAANQAECgcICgABNQAECgkJIAAkAGEgAA==.',
Po='Pooldan:BAAANQAECgMJAgAAAA==.',
Pr='Praystatioñ:BAABNQAECn8sAAIlAAoKhBkPBQBmAgAlAAoKhBkPBQBmAgAAAA==.Premiumgank:BAAANQAECgIIAgAAAA==.Priestlink:BAAANQADCgcIGAAAAA==.Prtanks:BAAANQAECgUIBgAAAA==.',
Pu='Purerform:BAAANQADCgcIBwAAAA==.',
Qu='Quelidra:BAAANQADCgUIBQAAAA==.Quepaspete:BAAANQADCgYIBwAAAA==.',
Ra='Raa:BAABNQAECn9EAAITAAkKnSWjBQBcAwATAAkKnSWjBQBcAwAAAA==.Racker:BAABNQAECn8ZAAIUAAcK2BLzEQCFAQAUAAcK2BLzEQCFAQAAAA==.Ragou:BAAANQADCgQIBAAAAA==.Rainfallen:BAABNQAECn8UAAMhAAoKRwlYDACdAQAhAAoKRwlYDACdAQAgAAEKWgZqOgAkAAAAAA==.',
Re='Rengots:BAAANQAECgYICgAAAA==.Rephtide:BAAANQAECgUIEAAAAA==.Responsible:BAABNQAECn8yAAISAAoKgyCwJwAbAwASAAoKgyCwJwAbAwAAAA==.',
Rh='Rhaez:BAAANQAECgEIAQAAAA==.Rhall:BAAANQADCgYIBgAAAA==.Rhetoricdork:BAAANQAECggICQABNQAFFAgIGwAHANUcAA==.',
Ri='Ritter:BAAANQADCgQIBAAAAA==.',
Ro='Rocksham:BAAANQAECggICAAAAA==.Rocktober:BAAANQAECgUIBQAAAA==.Rogmash:BAAANQAECgUJCwAAAA==.Rokkoz:BAABNQAECn8zAAIOAAoK2x+/BgBmAwAOAAoK2x+/BgBmAwAAAA==.Romer:BAACNQAFFH8FAAImAAIKOQGpCgBPAAAmAAIKOQGpCgBPAAA1AAQKfyMAAiYACQqFCCQWAIEBACYACQqFCCQWAIEBAAAA.Rompintom:BAAANQAECgIIAgAAAA==.Rookiestar:BAABNQAECn8rAAInAAkKaA7bRQDOAQAnAAkKaA7bRQDOAQAAAA==.',
Ru='Rumí:BAAANQAECgUICAAAAA==.',
Sa='Sabb:BAAANQADCgYIEAAAAA==.Samstephens:BAAANQADCgYICgABNQAECggIJAAVACIGAA==.Saphroniå:BAAANQADCgcIGQAAAA==.Sass:BAABNQAECn9DAAMCAAoKfxxcMABeAgACAAgKWhtcMABeAgAOAAQKKButNAA1AQAAAA==.Sazed:BAAANQADCgEIAQAAAA==.',
Sc='Schend:BAAANQADCgYICwAAAA==.Scibiol:BAAANQADCgIIAgAAAA==.',
Se='Sed:BAAANQAECgIIBQAAAA==.Serrana:BAAANQADCgUIBQAAAA==.',
Sf='Sfinktor:BAAANQADCgYIBgAAAA==.',
Sh='Shadax:BAAANQAECgYIBgAAAA==.Shadowmortis:BAAANQAECgQIBQAAAA==.Shadowwilder:BAABNQAECn8ZAAIGAAgKuQO3VQC4AAAGAAgKuQO3VQC4AAAAAA==.Shirokhan:BAABNQAECn81AAIHAAkKaRuCSAAmAgAHAAkKaRuCSAAmAgAAAA==.Shootum:BAAANQADCgYIDAAAAA==.Shïfthappens:BAAANQADCgUIBQAAAA==.',
Si='Sidewinderx:BAABNQAECn8UAAIeAAcKEwXcdgDHAAAeAAcKEwXcdgDHAAAAAA==.Sinlock:BAABNQAECn8dAAMBAAgK3B5NZAAtAgABAAcKTR9NZAAtAgAgAAQKMxH7NADvAAAAAA==.',
Sk='Skadí:BAAANQAECgYIBQAAAA==.Skrot:BAAANQADCgYIBgABNQAECgoKMQAJAJIYAA==.',
Sm='Smallarms:BAAANQADCgIIAgAAAA==.Smef:BAAANQADCgEIAQAAAA==.',
Sn='Snagglespark:BAACNQAFFH8GAAIVAAUKRgz7EwC/AAAVAAUKRgz7EwC/AAA1AAQKfywAAxUACgojHlkeABUDABUACgojHlkeABUDAAsABgpBC8W1AAIBAAAA.Sneakykrim:BAAANQABCgEIAQAAAA==.Sneakylink:BAAANQADCgYIEQAAAA==.Snowbunni:BAAANQAECgUIDAAAAA==.',
So='Soladrian:BAAANQAECgcIDAAAAA==.Solanthion:BAEANQADCgcIBwABNQAECgkJGwAaAKYXAA==.',
Sp='Spankyee:BAAANQADCgQIBAAAAA==.',
Sr='Srtaco:BAAANQAECgcIDgAAAA==.',
St='Starz:BAAANQADCgYIBAAAAA==.Stelmaria:BAAANQAECgMIAwABNQAECgoKNAATAMAbAA==.',
Su='Sunchipzz:BAAANQADCgQIBAAAAA==.Sundayschool:BAAANQAECgcIEgAAAA==.Sunwing:BAAANQAECgQIBgAAAA==.',
Sy='Syyia:BAAANQADCgIIAgAAAA==.',
['Sé']='Séraph:BAAANQAECgYICAAAAA==.',
['Só']='Sóozabimaru:BAAANQAECgQICQAAAA==.',
Ta='Tahano:BAAANQABCgIIAgAAAA==.Talljeff:BAAANQAECggIDgAAAA==.Tankarmor:BAABNQAECn8nAAIRAAYKqw8dHwBZAQARAAYKqw8dHwBZAQAAAA==.Taylorswif:BAACNQAFFH8HAAMHAAQKrQynLQAjAQAHAAQKrQynLQAjAQAbAAEKSAfzFQA+AAA1AAQKfyEAAwcACgqAGlpoAK0CAAcACQowGlpoAK0CABsAAQq1HMgyAFQAAAAA.',
Tc='Tcharta:BAABNQAECn9MAAMYAAoKnx+gAgCQAwAYAAoKnx+gAgCQAwAiAAEKAAA6QAArAAAAAA==.',
Te='Teostradin:BAAANQAECgQIBAAAAA==.',
Th='Thefamousone:BAAANQADCgYICAAAAA==.Theiá:BAAANQAECgEIAQAAAA==.Thermotide:BAAANQAECgcIEAAAAA==.Thornpaw:BAAANQADCgQIBAAAAA==.Thoror:BAAANQAECgUICgAAAA==.Thunderbolt:BAAANQADCgcIBwABNQAECgQIBAAKAAAAAA==.Thundernütz:BAAANQADCgIIAwAAAA==.Thymós:BAAANQAECgUIDAAAAA==.',
Ti='Tiffina:BAAANQADCgYICQAAAA==.Tiffzen:BAABNQAECn8eAAITAAgKGQhdxAAOAQATAAgKGQhdxAAOAQAAAA==.Timeskip:BAAANQADCggIBgAAAA==.Tinyfaith:BAAANQAECgQICAAAAA==.Titum:BAACNQAFFH8MAAIBAAUKZBSQFADtAAABAAUKZBSQFADtAAA1AAQKfyQAAgEACgp3IVILAAcDAAEACgp3IVILAAcDAAAA.',
To='Tongpooh:BAABNQAECn8xAAIJAAoKkhg9GACHAgAJAAoKkhg9GACHAgAAAA==.',
Tr='Treeberk:BAAANQAECgIIAgAAAA==.Truelink:BAAANQADCggIEgAAAA==.',
Tu='Tuba:BAAANQAECggIBQAAAA==.Tuckerherout:BAAANQAECgYIEAAAAA==.Tundro:BAAANQAECgEIAQAAAA==.',
Tw='Twix:BAAANQAECgIIAgABNQAECgQJCgAKAAAAAA==.',
['Tî']='Tîtån:BAABNQAECn8eAAMgAAYKJw3RIgBbAQAgAAYKJw3RIgBbAQAhAAEKAACDNgAbAAAAAA==.',
Uh='Uh:BAABNQAECn8aAAIeAAgK9x2VIgB6AgAeAAgK9x2VIgB6AgABNQAFFAcIDAAJAEEfAA==.',
Un='Undeadlock:BAAANQAECgQIEAAAAA==.',
Va='Vale:BAAANQADCgEIAQAAAA==.Valynda:BAAANQADCgEIAQAAAA==.',
Vg='Vgmking:BAABNQAECn8rAAIaAAkKCReSQAD8AQAaAAkKCReSQAD8AQAAAA==.',
Vi='Vigdis:BAAANQADCgcIBwAAAA==.Vindorei:BAAANQADCgUIDgAAAA==.',
Vo='Voidfed:BAAANQADCgQIBAABNQAECgcIEgAKAAAAAA==.Voidfu:BAAANQADCgIIAgAAAA==.Voidmydrama:BAAANQADCgYIBgAAAA==.Voidrefund:BAAANQADCgYIBgAAAA==.Vokzhen:BAABNQAECn84AAIZAAoKdhpjEABAAgAZAAoKdhpjEABAAgAAAA==.Volescu:BAABNQAECn8fAAMgAAoKLR1+AwDqAQAgAAgKeRx+AwDqAQABAAQKbBkBkwAgAQAAAA==.',
Wa='Walkerboah:BAABNQAECn8jAAIBAAoKvA8+UgDKAQABAAoKvA8+UgDKAQAAAA==.Warmachinne:BAAANQAECgIIAQAAAA==.',
We='Weel:BAABNQAECn89AAIMAAoK4Rk2HgC6AgAMAAoK4Rk2HgC6AgAAAA==.',
Wo='Wolfspider:BAAANQAECgIIAwAAAA==.',
Wy='Wyland:BAAANQAECgQIBQAAAA==.Wylander:BAABNQAECn8iAAIMAAoKdh9CEQAkAwAMAAoKdh9CEQAkAwAAAA==.Wylandvoker:BAAANQADCgIIAgAAAA==.',
Xa='Xanun:BAAANQADCgMIAwAAAA==.',
Xe='Xeri:BAABNQAECn8bAAIWAAoKXhnUCwCzAgAWAAoKXhnUCwCzAgABNQAFFAgIGgAoAJghAA==.Xeromus:BAABNQAECn8oAAMCAAgK6w4oOgAzAQACAAgK6w4oOgAzAQAOAAEKxQO5fgAiAAAAAA==.Xetsus:BAAANQADCgUJBQAAAA==.',
Ya='Yang:BAAANQABCgEIAQAAAA==.',
Yo='Yoink:BAAANQADCgUIBQAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Yv='Yvelmaya:BAABNQAECn8qAAMLAAgKexx6MQBDAgALAAgKexx6MQBDAgAVAAEKAAAJUAEmAAAAAA==.',
Za='Zabawaba:BAAANQAECggIDgABNQAECggIDwAKAAAAAA==.Zaboomaprune:BAABNQAECn8jAAMQAAkKqgw2LQAQAQAQAAkKqgw2LQAQAQAfAAQKwwFdOABcAAAAAA==.Zarika:BAACNQAFFH8aAAMoAAgKmCE+AACBAgAoAAcKuCI+AACBAgAnAAIK9RsdHwBhAAA1AAQKfz4AAygACgpkJlYAANkDACgACgpzJVYAANkDACcACQorJZoMAAsDAAAA.Zarì:BAAANQAECgUIBwABNQAFFAgIGgAoAJghAA==.',
Ze='Zeknull:BAABNQAECn8dAAMMAAgKTRwJOQCAAgAMAAgKTRwJOQCAAgADAAUKYg8xAgEcAQABNQAECgoKMAAFABoeAA==.Zekthal:BAABNQAECn8wAAMFAAoKGh70CQCqAgAFAAoKGh70CQCqAgAGAAEK4QWjiQAcAAAAAA==.Zenio:BAAANQADCgIIAgAAAA==.Zennah:BAAANQADCggIFgAAAA==.Zephy:BAAANQADCgcICQAAAA==.',
Zr='Zrgl:BAAANQADCggICAAAAA==.',
['Zä']='Zäo:BAACNQAFFH8FAAIBAAIK6xcdLwCbAAABAAIK6xcdLwCbAAA1AAQKfyQABCEACQphItgBACcDACEACQo7H9gBACcDAAEABQq7HTqiAJEBACAAAwo8I2g5ANsAAAAA.',
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
