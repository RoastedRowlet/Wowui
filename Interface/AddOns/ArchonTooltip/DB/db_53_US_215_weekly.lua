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

local lookup = {'Unknown-Unknown','Paladin-Protection','Paladin-Holy','Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Priest-Holy','DeathKnight-Blood','Evoker-Preservation','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Druid-Balance','Priest-Shadow','Priest-Discipline','DemonHunter-Devourer','Hunter-BeastMastery','Evoker-Augmentation','Warrior-Arms','DemonHunter-Havoc','Rogue-Subtlety','Rogue-Assassination',}
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=53,date='2026-10-06',data={Ae='Aeonmoksha:BAAANQAECgEJAQAAAA==.',
Ai='Airo:BAAANQADCgIIAgAAAA==.',
Ak='Akaris:BAAANQAECgUIDwAAAA==.',
Al='Alainea:BAAANQAECgUIBwAAAA==.Alorgynn:BAAANQABCgIIAwABNQAECgEIAgABAAAAAA==.Alôra:BAAANQADCgcIBwABNQAECgEIAgABAAAAAA==.',
Am='Amaterasu:BAACNQAFFIEZAAICAAcKayENAQBgAgACAAcKayENAQBgAgA1AAQKgScAAgIACQprJhYCAKgDAAIACQprJhYCAKgDAAE1AAUUBwoZAAIAayEA.Ambre:BAAANQAECgYICgAAAA==.',
An='Angwy:BAAANQAECgIJAgAAAA==.',
Ar='Ara:BAAANQAECgQICAAAAA==.Archhùnter:BAAANQABCgQIBAAAAA==.Ariannae:BAAANQAECgYIBgAAAA==.',
As='Ashamed:BAAANQAECggIEgABNQAFFAcKGQACAGshAA==.',
At='Atropa:BAAANQADCgYIBgAAAA==.',
Au='Aura:BAABNQAECoEsAAMDAAgKzR+QHgDhAgADAAgKzR+QHgDhAgAEAAEKLQzodQEzAAAAAA==.',
Ax='Axl:BAAANQAECgEIAgAAAA==.',
Ay='Aylíth:BAAANQAECgMIAwABNQAFFAcKGQACAGshAA==.',
Ba='Bah:BAAANQADCgcIIwAAAA==.Banjoo:BAAANQAECgIIAgAAAA==.Baruk:BAABNQAECoEkAAMFAAkKAxTURAAjAgAFAAkKAxTURAAjAgAGAAMKuAIX9gBlAAAAAA==.',
Be='Benny:BAAANQADCgcIEwABNQAECgcIHgAHAKEhAA==.',
Bi='Bigçhungi:BAAANQAECgYICQABNQAFFAYIGQAIAAwkAA==.',
Bl='Blitzen:BAABNQAECoEnAAIJAAkKexgtEACTAgAJAAkKexgtEACTAgAAAA==.',
Bo='Boozamabeard:BAAANQAECggIDQAAAA==.Borealiss:BAAANQAECgUIDgABNQAECgkJJwAJAHsYAA==.',
Br='Break:BAAANQAECgYICQABNQAFFAcKFQAEABggAA==.',
Bw='Bwonsamdi:BAAANQADCgcIBwAAAA==.',
['Bâ']='Bârks:BAAANQAECgMIBwAAAA==.',
Ca='Caarij:BAABNQAECoEeAAMKAAcKSxg2QQDxAQAKAAcKJBg2QQDxAQALAAEKjwz5kQA2AAAAAA==.Cadence:BAAANQAECgIIAgAAAA==.Callia:BAAANQADCgIIAgAAAA==.',
Ce='Celorana:BAAANQADCgYIBgAAAA==.',
Ch='Chijirô:BAAANQAECgEIAQAAAA==.Choleena:BAAANQAECgMIBwAAAA==.',
Co='Coppola:BAAANQABCgUJAwAAAA==.',
['Cí']='Círce:BAAANQAECggICAABNQAFFAcKGQACAGshAA==.',
Da='Dangerwithin:BAAANQAECgMIAwABNQAFFAcKGQACAGshAA==.Danklazercat:BAAANQADCgEJAQABNQAFFAYIGQAIAAwkAA==.Darius:BAAANQAFFAEIAQAAAA==.Dastraz:BAAANQAECgQICQAAAA==.',
De='Deaconblues:BAAANQABCgMIBQABNQAECggIDQABAAAAAA==.Devkra:BAAANQAECgUIEAAAAA==.',
Dh='Dharma:BAAANQAECgUIDwAAAA==.',
Do='Doge:BAAANQAECgcIEQAAAA==.',
Dr='Drakona:BAAANQADCgUIBQAAAA==.Drapenthim:BAAANQADCgQIAwAAAA==.',
Du='Dudemachine:BAAANQADCgMIAwABNQAECgkJGQAMADAcAA==.',
['Dø']='Døødemage:BAAANQAECgIIAQAAAA==.',
Ed='Eddison:BAAANQAECgIIAgAAAA==.',
El='Eloralove:BAAANQADCggICAAAAA==.',
En='Enchanted:BAABNQAECoEfAAIKAAgK3h8pMQBGAgAKAAgK3h8pMQBGAgAAAA==.Ender:BAAANQAECgYIDwAAAA==.',
Es='Eskanor:BAAANQADCgQJBAAAAA==.',
Et='Eternalwrath:BAAANQAECgMIBwAAAA==.',
Fe='Felmary:BAAANQAECgUIDQAAAA==.',
Fi='Firnen:BAAANQADCgMIAwAAAA==.',
Fr='Freyja:BAAANQAECgMIBgAAAA==.',
Fu='Furbees:BAAANQAECgQICQAAAA==.',
Ga='Gaziban:BAAANQADCgEJAQAAAA==.',
Ge='Geenon:BAAANQAECgQIBAAAAA==.',
Gr='Graubard:BAAANQAECgMICAAAAA==.Grimswhisper:BAAANQAECgUICAAAAA==.Grynsel:BAAANQAECgMICAAAAA==.',
Ha='Harlynne:BAAANQADCgYJBgAAAA==.Harukav:BAABNQAECoEdAAIGAAgKxhrWOABsAgAGAAgKxhrWOABsAgAAAA==.',
He='Hela:BAAANQAECgEIAQAAAA==.',
Ho='Homrun:BAAANQADCggIFQAAAA==.',
Ia='Iamtheman:BAAANQADCgYIDgAAAA==.',
Im='Imtoschmexy:BAAANQADCgcIDgAAAA==.',
In='Inwe:BAAANQADCggIEwAAAA==.',
Je='Jesmarie:BAAANQAECgUIDwAAAA==.',
Jo='Johnnydodge:BAAANQAECgYIEgAAAA==.Jordon:BAAANQAECgIIAgAAAA==.Joyride:BAAANQAECgMIBwAAAA==.',
Ju='Juiceboxx:BAAANQAECgcIDgAAAA==.Jujuwing:BAAANQAECgUIDwAAAA==.',
['Jù']='Jùde:BAAANQAECgIIAwAAAA==.',
Ka='Kanrethad:BAABNQAECoEkAAMNAAgKDyKXGAAQAwANAAgKDyKXGAAQAwAOAAIKdR4FQQC1AAAAAA==.',
Ke='Kerrygan:BAAANQAECgYIDQAAAA==.',
Ki='Killà:BAAANQADCgMIAwAAAA==.Kilmister:BAAANQAECgMIAwABNQAECgMICAABAAAAAA==.',
Ko='Koaì:BAAANQAECgEIAgAAAA==.Korthank:BAABNQAECoEeAAIFAAgKUBQPVwDeAQAFAAgKUBQPVwDeAQAAAA==.Koyanskaya:BAAANQADCgMIAwABNQAECgIIAwABAAAAAA==.',
Kw='Kwissy:BAAANQAECgEIAQAAAA==.',
['Ká']='Kátiá:BAAANQAECgQIDQAAAA==.',
La='Labellanotte:BAAANQAECgMIBwAAAA==.Landair:BAAANQABCgIIAgAAAA==.Landao:BAAANQABCgQIAwAAAA==.Laoftarf:BAAANQADCgIIAgAAAA==.Layssa:BAABNQAECoEeAAIPAAgKVx1vIACrAgAPAAgKVx1vIACrAgAAAA==.',
Li='Lighter:BAAANQADCgUICgAAAA==.Likal:BAAANQADCgcIDAAAAA==.Likall:BAAANQADCgUICgAAAA==.Liliania:BAAANQADCgQIBAAAAA==.Linda:BAAANQABCgYICgAAAA==.Lindona:BAAANQABCgIIAgAAAA==.',
Lu='Lucyford:BAABNQAECoEVAAQCAAgKjg/RLwA1AQACAAcKLg3RLwA1AQADAAUKaAfWuADhAAAEAAQK9g+6EwHHAAAAAA==.Lunafox:BAAANQADCgYJBgABNQAECgMIBwABAAAAAA==.Lunatic:BAAANQAECgMIBwAAAA==.',
Ly='Lyraali:BAAANQAECgIIBAAAAA==.',
['Lã']='Lãtha:BAAANQADCgUICQAAAA==.',
Ma='Magemode:BAAANQAECgYIDwAAAA==.Makingfiends:BAAANQAECgQIBwABNQAECgkJGQAMADAcAA==.Mar:BAAANQAECgQIBAAAAA==.Marshtonjus:BAAANQADCgQIBAAAAA==.Martyrion:BAAANQADCgcIFwAAAA==.Matterhorne:BAAANQADCgYIEAAAAA==.',
Mh='Mhercy:BAAANQAECgQIBAAAAA==.',
Mi='Mikeberetta:BAAANQAECgEIAQAAAA==.Minchin:BAAANQAECgUIBgAAAA==.Miniz:BAAANQAECgIIBAAAAA==.Mislahd:BAAANQADCgYIBgAAAA==.Mistesla:BAAANQADCgcIEAAAAA==.',
Mo='Moktezuma:BAAANQAECgMIBgAAAA==.',
Mu='Mutekii:BAAANQAECgcIEAAAAA==.',
Na='Natrel:BAAANQAECgQIBAAAAA==.Nausium:BAAANQAECgUIBgAAAA==.',
Ni='Niasi:BAAANQADCgYIBgAAAA==.Nier:BAAANQADCggIDgAAAA==.Niuven:BAAANQAECggIEAAAAA==.',
Oc='Octane:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Octozm:BAAANQAECgUICQAAAA==.',
Ol='Oldetimer:BAAANQADCggICAAAAA==.Olympi:BAAANQABCggIDQAAAA==.',
Oo='Oolga:BAABNQAECoEkAAIDAAgKGCLSFQAVAwADAAgKGCLSFQAVAwAAAA==.Oopsie:BAAANQADCgQICAAAAA==.',
Or='Oreofrosting:BAABNQAECoEZAAIMAAkKMBxXEQC2AgAMAAkKMBxXEQC2AgAAAA==.',
Os='Oshiokiyo:BAAANQADCgEIAQAAAA==.',
Pa='Pally:BAAANQAECggIAgAAAA==.',
Pe='Penderrin:BAAANQAECgUIEAAAAA==.Perseffonee:BAAANQAECgUIEAAAAA==.',
Ph='Phrenologist:BAAANQADCggIFgAAAA==.Physics:BAACNQAFFIEIAAMHAAUK7w/kDQCMAQAHAAUK7w/kDQCMAQAQAAMKCg4ZDQDUAAA1AAQKgRoABAcACQoIGps+AEsCAAcABworHZs+AEsCABAACQpkEsohAAECABEAAgqnAEQuABQAAAAA.',
Pu='Pub:BAABNQAECoEYAAISAAkKuxsEFgCaAgASAAkKuxsEFgCaAgAAAA==.',
Py='Pyzemphx:BAAANQAECgMICAAAAA==.',
Ra='Raelos:BAAANQAECgEIAgAAAA==.Ragebait:BAAANQAECgMIBwAAAA==.Ranikina:BAAANQAECgQICwAAAA==.',
Re='Regal:BAAANQAECgEIAQAAAA==.Regansi:BAAANQADCgIIBAAAAA==.Regasus:BAAANQAECgMIBQAAAA==.Revolt:BAAANQADCggIFwAAAA==.',
Rh='Rheía:BAAANQAECgIIAgABNQAFFAcKGQACAGshAA==.Rhysi:BAAANQADCggIDgAAAA==.',
Ri='Riteofdeath:BAAANQADCgIIAgAAAA==.',
Ro='Rock:BAAANQADCggICAAAAA==.Rowenne:BAAANQADCggIHQABNQAECgUIBwABAAAAAA==.',
Sa='Sahariel:BAABNQAECoEeAAIHAAcKoSEmKwCdAgAHAAcKoSEmKwCdAgAAAA==.Sarg:BAAANQAECgIIAgABNQAFFAMIBQATAOALAA==.Sauce:BAAANQADCgIJAwABNQAECgEIAQABAAAAAA==.',
Sc='Schwartpheil:BAABNQAECoEaAAITAAgKCQxffADmAQATAAgKCQxffADmAQAAAA==.Scrsaint:BAAANQAFFAEIAQAAAA==.',
Se='Seff:BAAANQAECgUICwABNQAECgUIEAABAAAAAA==.Seumadruga:BAAANQADCgUIBQAAAA==.',
Sh='Shardemma:BAAANQADCgUICAAAAA==.Shimmerly:BAAANQADCggIDgABNQAECgEIAQABAAAAAA==.Shytningbolt:BAAANQADCggICAABNQAECggIIgAIAAMjAA==.',
Si='Sintara:BAABNQAECoEfAAIUAAgK9Qu5CwB5AQAUAAgK9Qu5CwB5AQAAAA==.',
So='Sore:BAAANQAECgYICAAAAA==.',
Sq='Squigyçus:BAABNQAECoEwAAITAAkKPiS+BwCSAwATAAkKPiS+BwCSAwABNQAFFAYIGQAIAAwkAA==.',
St='Strawkun:BAAANQADCgYJBgAAAA==.',
['Sç']='Sçruffy:BAACNQAFFIEZAAIIAAYKDCTJAQB5AgAIAAYKDCTJAQB5AgA1AAQKgSQAAwgACQp7JZMGAIQDAAgACQp7JZMGAIQDAAoABwqBF9FcAHYBAAAA.',
Ta='Talren:BAAANQADCgIIAgAAAA==.',
Te='Teldryn:BAABNQAECoEnAAIVAAkK8x8AJgARAwAVAAkK8x8AJgARAwAAAA==.',
Th='Thorendire:BAABNQAECoEdAAIWAAcKMg7BPgCPAQAWAAcKMg7BPgCPAQAAAA==.Thundoor:BAAANQAECgQIBQAAAA==.',
Ti='Tirnz:BAABNQAECoEaAAILAAgKFAfyRQBhAQALAAgKFAfyRQBhAQAAAA==.',
Tr='Treeoflife:BAAANQAECgUIEwAAAA==.Trilldt:BAAANQAECggIBQAAAA==.',
Tu='Tuskanir:BAAANQABCgIJAgAAAA==.',
Va='Vaelestrix:BAACNQAFFIEKAAMXAAUKeRrxAwDlAQAXAAUKSRrxAwDlAQAYAAIKHxX+DQC4AAA1AAQKgTIAAxcACQqXJnAAAPEDABcACQqIJnAAAPEDABgACQq2It4IADMDAAAA.Vaelora:BAAANQADCgcIDQAAAA==.Vaynn:BAAANQADCggIDgAAAA==.',
Vo='Voiddøøde:BAAANQADCgQIBAAAAA==.Voidsocket:BAAANQADCggJCAABNQAECgMIBQABAAAAAA==.',
Vu='Vulpvs:BAAANQADCgcIDwAAAA==.',
Vv='Vvlpvs:BAAANQADCgYIEAAAAA==.',
Wa='Warherald:BAAANQAECgYIEQAAAA==.',
We='Wednesday:BAACNQAFFIEWAAIIAAgK+RPVAQB3AgAIAAgK+RPVAQB3AgA1AAQKgSMAAggACQrKInwKAFMDAAgACQrKInwKAFMDAAAA.',
Xa='Xandril:BAAANQAECgMIAwABNQAECgQICQABAAAAAA==.',
Xi='Xirek:BAAANQAECgMIBwAAAA==.',
['Xì']='Xìlin:BAAANQABCgEIAQABNQAECgEIAgABAAAAAA==.',
Yr='Yreasak:BAAANQAECgQICQAAAA==.Yrisan:BAAANQADCgcIEgABNQAECgQICQABAAAAAA==.',
Ys='Yseulde:BAAANQADCgYIDAABNQAECgQICQABAAAAAA==.',
Za='Zapfren:BAAANQADCgEIAgABNQAECgkJGQAMADAcAA==.Zarnok:BAAANQADCggIDwAAAA==.',
Ze='Zeratüle:BAAANQADCgcIBwAAAA==.',
Zo='Zosimos:BAAANQADCgcIBwAAAA==.',
Zu='Zurâ:BAABNQAECoEaAAIIAAgKGgSQbgAVAQAIAAgKGgSQbgAVAQAAAA==.',
['Çh']='Çhief:BAAANQADCgMIAwABNQAECgkJHwAIAF0TAA==.',
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
