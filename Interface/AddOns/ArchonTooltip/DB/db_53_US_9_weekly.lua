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

local lookup = {'Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Mage-Arcane','Unknown-Unknown','Shaman-Restoration','Paladin-Holy','Druid-Guardian','Monk-Windwalker','Warrior-Fury','Warrior-Arms','Warlock-Demonology','Druid-Restoration','Shaman-Enhancement','Shaman-Elemental','Evoker-Preservation','DeathKnight-Blood','Mage-Frost','Mage-Fire','DeathKnight-Unholy','Paladin-Protection','Hunter-BeastMastery','Druid-Feral','Warlock-Destruction','Rogue-Assassination','Warrior-Protection','Priest-Shadow','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Monk-Brewmaster','Druid-Balance','Evoker-Devastation','DeathKnight-Frost','Rogue-Outlaw','Warlock-Affliction',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Acupuncher:BAAANQAECgIIAgAAAA==.',
Ad='Adamsandler:BAAANQADCggICAAAAA==.Adiwolf:BAAANQAECgIIBAAAAA==.',
Al='Alcha:BAAANQAECgcIEAAAAA==.Alenndar:BAAANQADCgEIAQAAAA==.Alexdaddario:BAAANQAECgYIDgAAAA==.Algaefungi:BAAANQAECgIICAAAAA==.Althena:BAAANQAECgEIAQABNQAECgkJMwABAOQhAA==.Alystana:BAAANQADCgUIBwAAAA==.',
Am='Amberelle:BAAANQADCgQIBAAAAA==.',
An='Anastera:BAAANQADCgYIBwAAAA==.Animeniac:BAAANQAECgUIEgAAAA==.Anticlimax:BAABNQAECn8YAAQCAAcKrg9uGQAZAQADAAYKLg5VPwBLAQACAAUKiA5uGQAZAQAEAAMKsAdZdQCeAAAAAA==.Antilaw:BAAANQAECgEIAgAAAA==.Antisocial:BAAANQAECgQICwAAAA==.Antistab:BAAANQAECgIIAgAAAA==.',
Ao='Aoibhneas:BAAANQADCgcIBwAAAA==.',
Ap='Apprentice:BAACNQAFFH8HAAIFAAMKkhoMLwAOAQAFAAMKkhoMLwAOAQA1AAQKfx4AAgUACQoXJHUyACYDAAUACQoXJHUyACYDAAAA.',
Ar='Ariha:BAAANQAECgQIBQAAAA==.Artrael:BAAANQADCggJCAAAAA==.',
At='Atorim:BAAANQADCgIIAgABNQAECgMIAwAGAAAAAA==.',
Av='Avienndha:BAAANQAECgUIEgAAAA==.Avriel:BAAANQAECgQICQABNQAECgkJMwABAOQhAA==.',
Ba='Barbatos:BAAANQAECgIIAgAAAA==.',
Be='Beardeddrunk:BAAANQADCgUJBQAAAA==.Beornwildlaw:BAAANQABCgcIDgAAAA==.',
Bl='Bloodyflame:BAAANQABCggICwAAAA==.',
Bo='Bobbytofva:BAAANQAECgMIBAAAAA==.Bobthedurgon:BAAANQADCgUIBQAAAA==.Bobthegrinch:BAAANQADCgQIBAAAAA==.Boneloss:BAAANQADCgQIBAAAAA==.Boochaka:BAABNQAECn8WAAIHAAcK3BrTUwAUAgAHAAcK3BrTUwAUAgAAAA==.Bouman:BAAANQADCgYIBgAAAA==.Bouquet:BAAANQAECgUIEAAAAA==.',
Br='Brewdog:BAAANQAECgQICgAAAA==.Brickfists:BAAANQADCgQIBAAAAA==.Brotherfuzz:BAAANQAECgIIAwAAAA==.',
Bu='Buckangel:BAAANQAECggIAgABNQAFFAcIBwAIAO4iAA==.Busterposer:BAAANQAECgQIBgAAAA==.',
Ca='Caelvaris:BAAANQADCgEIAQAAAA==.Calabooca:BAAANQADCgUICAAAAA==.Canadaclown:BAAANQADCgIJAgAAAA==.Candor:BAAANQADCgUIBQAAAA==.',
Ch='Cheesefries:BAAANQAECgUIEQAAAA==.Chereth:BAAANQADCgMIAwAAAA==.Chratos:BAAANQADCgYIBgAAAA==.',
Cl='Clapton:BAAANQAECgQICQAAAA==.Claptone:BAAANQAECgYIEAAAAA==.',
Co='Corpuscle:BAAANQAECgYIEAAAAA==.',
Cr='Critcomander:BAABNQAECn8nAAIBAAgKDg6vqQDHAQABAAgKDg6vqQDHAQAAAA==.Critties:BAAANQADCgMIAwAAAA==.Crowfive:BAAANQAECgUIBQAAAA==.Crueldin:BAAANQAECgYIEwAAAA==.',
Da='Dalsen:BAABNQAECn8mAAIJAAgKzg7wIACNAQAJAAgKzg7wIACNAQAAAA==.Dalvulpe:BAAANQADCgEIAQABNQAECggIJgAJAM4OAA==.Dankchop:BAAANQAECgYIEgAAAA==.Darim:BAAANQADCgIIAgAAAA==.Darkbishop:BAAANQABCgYICgAAAA==.Darklink:BAAANQAECgQICQAAAA==.Dawnlighted:BAAANQADCgMIAwAAAA==.',
De='Deadlyshiet:BAAANQAECgMIBQABNQAFFAcIIAAKAHIWAA==.Defibrilater:BAAANQAECgQIBwAAAA==.Demonfed:BAAANQABCgIIAgABNQADCgQICAAGAAAAAA==.Denrin:BAAANQAECgUIDgAAAA==.Deskpop:BAAANQADCgQIBAAAAA==.',
Di='Diabolikal:BAAANQADCgYIDAAAAA==.Dill:BAABNQAECn81AAILAAkKgCWGAADVAwALAAkKgCWGAADVAwAAAA==.Divinesmite:BAAANQABCgcICAAAAA==.',
Dm='Dmachine:BAABNQAECn8WAAIMAAcK7g+orQClAQAMAAcK7g+orQClAQABNQAFFAYIGQANAKMdAA==.',
Do='Dondeezy:BAAANQADCgYIBgAAAA==.',
Dr='Drdru:BAABNQAECn8jAAIOAAcKJxucIAAhAgAOAAcKJxucIAAhAgABNQADCgUIBQAGAAAAAA==.Dreadshade:BAAANQADCgcIDgAAAA==.Dropfort:BAAANQAECggIDgAAAA==.Drscruffles:BAAANQADCgcIBwAAAA==.',
Du='Duifean:BAAANQADCgUIBQABNQAECgQIBgAGAAAAAA==.Durkidurk:BAAANQADCgMIAwAAAA==.',
Dy='Dyabolykal:BAAANQADCgQIBAABNQADCgYIDAAGAAAAAA==.',
Ea='Easily:BAAANQAECgYIDgAAAA==.',
El='Ellyanthia:BAAANQAECgYICQAAAA==.',
Em='Emachine:BAAANQADCgcIBwABNQAFFAYIGQANAKMdAA==.',
Ex='Exio:BAAANQAECgQJCgAAAA==.',
Fa='Fastasheet:BAACNQAFFH8gAAIKAAcKchYaAwA4AgAKAAcKchYaAwA4AgA1AAQKfywAAgoACQpUJVgFAHoDAAoACQpUJVgFAHoDAAAA.',
Fe='Feralfed:BAAANQADCgUIBQABNQADCgQICAAGAAAAAA==.',
Fi='Fill:BAABNQAECn8oAAIPAAkKgyWrAQCeAwAPAAkKgyWrAQCeAwABNQAFFAMICAAKAGghAA==.',
Fl='Flehtwo:BAACNQAFFH8RAAMQAAYKngmJDwBwAQAQAAUKngmJDwBwAQAHAAIKrQwPIQCGAAA1AAQKfyoAAxAACQo5HWc1AJ8CABAACQo5HWc1AJ8CAAcACApDCrSCAIABAAAA.Flehunter:BAAANQAECgcIBwAAAA==.Flyinbanana:BAAANQADCgQIBAABNQAECgkJJgARAFEaAA==.',
Fo='Fortypi:BAAANQAECgUIBQABNQAFFAMICAAKAGghAA==.',
Fr='Fraglen:BAAANQADCgUIBQABNQAECgcICgAGAAAAAA==.Frags:BAAANQAECgcICgAAAA==.Fránknárf:BAAANQAECgEIAQAAAA==.',
Ge='Genjyosanzo:BAAANQAECgUIDAAAAA==.',
Gh='Ghostkrim:BAAANQADCgUIBQAAAA==.',
Gi='Gilljoww:BAABNQAECn8bAAISAAgKSx/EKQBzAgASAAgKSx/EKQBzAgAAAA==.Gireigtulb:BAAANQADCgYIBgAAAA==.',
Gn='Gnzz:BAABNQAECn8eAAQTAAgKdBndGAAuAQAFAAcKCxhAxwD0AQATAAQKLxTdGAAuAQAUAAEKAADwDQAxAAAAAA==.',
Go='Gocirr:BAAANQAECgUICgAAAA==.',
Gr='Grito:BAAANQADCgYICgAAAA==.',
Ha='Haehn:BAAANQADCgMIAwAAAA==.Halstorm:BAAANQAECgYICwAAAA==.Harrysax:BAAANQABCgYIBgAAAA==.',
He='Hedrake:BAAANQAECgQIBQAAAA==.Hexxytime:BAAANQADCgQIBAAAAA==.',
Hi='Hilazy:BAAANQAECgIIAwAAAA==.',
Hm='Hm:BAAANQAECgEIAQAAAA==.',
Ho='Holyfed:BAAANQADCgQICAAAAA==.Holyphok:BAAANQAECgMIAwAAAA==.Hotdog:BAAANQAECgUIAgAAAA==.',
Ic='Icestormy:BAAANQAECgMIAwAAAA==.',
Ih='Ihavenofutur:BAAANQAECgUICQAAAA==.',
Il='Iliil:BAABNQAECn8pAAISAAkK+iDmDABJAwASAAkK+iDmDABJAwAAAA==.Illbiteyou:BAAANQADCgQIBAAAAA==.Illidantwo:BAACNQAFFH8XAAIEAAYKThxYBAAjAgAEAAYKThxYBAAjAgA1AAQKfzIAAgQACQphJJAFAJoDAAQACQphJJAFAJoDAAAA.',
Im='Imprints:BAAANQAECgYIEAAAAA==.',
In='Inuk:BAAANQAECgYIEwAAAA==.',
Ir='Ironshaman:BAAANQAECgYIEQAAAA==.',
It='Italianapee:BAAANQAECgQIBAABNQAECgYIEwAGAAAAAA==.',
Ja='Jabu:BAAANQADCgQIAwABNQAECgIIBgAGAAAAAA==.Jada:BAAANQAECgQIBwAAAA==.Jaghatai:BAAANQADCgIIAgAAAA==.',
Je='Jenstonedart:BAAANQAECgUIEwAAAA==.Jeryeth:BAABNQAECn8cAAIMAAkKwR7MPgDLAgAMAAkKwR7MPgDLAgAAAA==.Jerymander:BAAANQADCgMIAwAAAA==.Jeryzard:BAAANQADCgYIDAAAAA==.',
Ji='Jiannybon:BAAANQADCgQICwAAAA==.',
Ju='Judgmental:BAAANQADCgYIBgAAAA==.Judidench:BAABNQAECn8XAAIVAAgKqCMzDgBFAwAVAAgKqCMzDgBFAwAAAA==.Juicewillis:BAAANQADCgIIAgAAAA==.',
Ka='Kain:BAECNQAFFH8XAAIWAAcKgyXFAACpAgAWAAcKgyXFAACpAgA1AAQKfycAAxYACQo3JjsDAI8DABYACQo3JjsDAI8DAAEAAQo4CiyzASsAAAAA.Kanda:BAAANQAECggIAQAAAA==.Kane:BAABNQAECn8dAAISAAcKXBLdVwCQAQASAAcKXBLdVwCQAQAAAA==.Karmasuture:BAAANQADCgYJBgABNQAECgMIAwAGAAAAAA==.Kaïn:BAAANQAECgMIBAABNQAECgkJMwABAOQhAA==.',
Ke='Kelsí:BAAANQAECgMICQAAAA==.',
Ki='Kiwí:BAABNQAECn8gAAIFAAgKICG2UQDdAgAFAAgKICG2UQDdAgAAAA==.',
Kr='Krasavice:BAABNQAECn8qAAIXAAgKMxsMPACzAgAXAAgKMxsMPACzAgAAAA==.Krenik:BAAANQADCggIHwAAAA==.Krimdin:BAAANQADCgEIAQAAAA==.Krimdrood:BAAANQADCgMIAwAAAA==.Krimsondeath:BAAANQADCgQIBAAAAA==.Krimtohell:BAAANQAECgMIBQAAAA==.Krisp:BAAANQAECgQIDAABNQADCgQICAAGAAAAAA==.',
Ku='Kurquaan:BAAANQADCggICAAAAA==.',
La='Lauranthalas:BAAANQAECgUICgAAAA==.Lavenderhaze:BAAANQADCgEIAQAAAA==.',
Le='Leathal:BAABNQAECn8bAAIIAAYKTyCwTwAqAgAIAAYKTyCwTwAqAgAAAA==.Lemurshoes:BAAANQAECgIIAwAAAA==.Lemursneaker:BAABNQAECn8aAAIFAAgKKgUUEQFsAQAFAAgKKgUUEQFsAQAAAA==.Letsgomen:BAAANQADCgEIAQAAAA==.',
Li='Lightshock:BAAANQAECgEIAgAAAA==.Linkblade:BAAANQADCggIDgAAAA==.Linkdin:BAAANQADCgcIDAAAAA==.Linkdrood:BAAANQADCggIFAAAAA==.Linkoflife:BAAANQADCgIIBAAAAA==.',
Ll='Llaagg:BAAANQAECgIIAgAAAA==.',
Lo='Lokust:BAAANQAECgUIEwAAAA==.',
Lu='Lucentdawn:BAAANQAECgYIEwAAAA==.Luckyshrine:BAAANQABCggICwAAAA==.Ludachris:BAAANQAECgEIAQAAAA==.',
Ly='Lycanius:BAABNQAECn8wAAMYAAkKrhtiBgAEAwAYAAkKrhtiBgAEAwAJAAEKswLgbwAZAAAAAA==.Lynqii:BAACNQAFFH8NAAMNAAcKYRGHCQDTAQANAAYK+ROHCQDTAQAZAAEKAQeFIQBHAAA1AAQKfxUAAw0ABgrkH/mQALcBAA0ABgrkH/mQALcBABkAAQoVGwBrAEkAAAAA.',
Ma='Macaco:BAAANQADCgYIBgAAAA==.Malirra:BAABNQAECn8ZAAIFAAkKowQ1BwF9AQAFAAkKowQ1BwF9AQAAAA==.Malëk:BAABNQAECn8zAAIBAAkK5CHfHABOAwABAAkK5CHfHABOAwAAAA==.Maximus:BAAANQADCgUIBQAAAA==.',
Me='Mechatholic:BAAANQAECgYICgAAAA==.Medallis:BAAANQABCgcIDwAAAA==.Mellowlizard:BAACNQAFFH8ZAAMNAAYKox2jBQAWAgANAAUKEhujBQAWAgAZAAEKViUrFABnAAA1AAQKfyQAAw0ACQqhI1UjAPQCAA0ACAoaJFUjAPQCABkAAwr2HoY7ANIAAAAA.Metuss:BAAANQAECgYIEwAAAA==.',
Mi='Miguel:BAAANQAECgUJDgAAAA==.Mira:BAAANQAECgYIEwAAAA==.',
Mk='Mkicon:BAAANQAECgUIEwAAAA==.Mkultra:BAAANQAECgcIEgAAAA==.',
Mo='Mogmoog:BAAANQAECgUIEQAAAA==.Mooganfreman:BAAANQADCggIDgAAAA==.Moonangel:BAAANQAECgUIEgAAAA==.Morbodan:BAABNQAECn8lAAIaAAkK4iDzBgBhAwAaAAkK4iDzBgBhAwAAAA==.Mornangus:BAAANQABCgMIAwAAAA==.Moshpit:BAAANQAFFAEIAQAAAA==.Motone:BAAANQAECgMJBAAAAA==.',
Mu='Multanni:BAABNQAECn8YAAIQAAcKdxVQbQDUAQAQAAcKdxVQbQDUAQAAAA==.',
My='Mykanoid:BAAANQAECgIIAgABNQAECgkJJgARAFEaAA==.Myonecrosis:BAAANQAECgUIEgAAAA==.',
Na='Nakrog:BAABNQAECn8iAAMbAAgKghoWCwCJAgAbAAgKghoWCwCJAgAMAAEKkBo5QgFEAAAAAA==.Napster:BAAANQAECgMIAwAAAA==.Nasa:BAACNQAFFH8WAAIKAAYK1A9nBQDGAQAKAAYK1A9nBQDGAQA1AAQKfyQAAgoACQrIHhAWAJwCAAoACQrIHhAWAJwCAAAA.',
Ne='Nellarixi:BAABNQAECn8aAAIcAAgKQhyrHQBQAgAcAAgKQhyrHQBQAgAAAA==.Nethus:BAAANQADCgcJCQAAAA==.',
Ni='Niivalyr:BAAANQABCgIJAQAAAA==.Nimbus:BAAANQADCggIDgABNQAFFAcIFAAQADQXAA==.',
No='Nodens:BAAANQADCgcIEwAAAA==.Nomaa:BAAANQAECgUIEQAAAA==.Nomäd:BAAANQAECgUICAAAAA==.Nosneb:BAAANQADCgMIBAABNQADCggIEAAGAAAAAA==.',
Ny='Nytedevil:BAAANQAECgYIDgAAAA==.',
['Nì']='Nìtsua:BAAANQADCggIEAAAAA==.',
Ob='Obilivion:BAAANQADCgYICgAAAA==.',
Og='Ogmount:BAAANQAECgMIAwAAAA==.',
Or='Orflame:BAABNQAECn8bAAMRAAgKeQdeKABvAQARAAgKeQdeKABvAQAdAAEKKgVyJAAxAAAAAA==.',
Ph='Phantomhealz:BAAANQABCgIIAgAAAA==.Phrash:BAABNQAFFH8IAAIKAAMKaCEfCgAfAQAKAAMKaCEfCgAfAQAAAA==.',
Pi='Pigbearmans:BAAANQADCgYIBgAAAA==.',
Pl='Plex:BAAANQADCgQIBAABNQAECgkJIAAeAGEgAA==.',
Po='Pooldan:BAAANQAECgMJAgAAAA==.',
Pr='Praystatioñ:BAABNQAECn8gAAIfAAgKIxoCBQBmAgAfAAgKIxoCBQBmAgAAAA==.Premiumgank:BAAANQAECgIIAgAAAA==.Priestlink:BAAANQADCgcIDQAAAA==.Prtanks:BAAANQAECgMIBgAAAA==.',
Pu='Purerform:BAAANQADCgcIBwAAAA==.',
Qu='Quelidra:BAAANQADCgUIBQAAAA==.Quepaspete:BAAANQADCgYIBwAAAA==.',
Ra='Raa:BAABNQAECn8vAAIXAAgK7h11IwAHAwAXAAgK7h11IwAHAwAAAA==.Racker:BAAANQAECgUICgAAAA==.Ragou:BAAANQADCgQIBAAAAA==.Rainfallen:BAAANQAECggIDAAAAA==.',
Re='Rengots:BAAANQAECgEIAQAAAA==.Rephtide:BAAANQAECgUIDgAAAA==.Responsible:BAABNQAECn8gAAIMAAkKth//JgAbAwAMAAkKth//JgAbAwAAAA==.',
Rh='Rhaez:BAAANQAECgEIAQAAAA==.Rhall:BAAANQADCgYIBgAAAA==.Rhetoricdork:BAAANQAECggICAABNQAFFAcIGQAFAOMfAA==.',
Ro='Rocktober:BAAANQAECgEIAQAAAA==.Rogmash:BAAANQAECgUJCwAAAA==.Rokkoz:BAABNQAECn8aAAIOAAcK/R50GgBiAgAOAAcK/R50GgBiAgAAAA==.Romer:BAACNQAFFH8FAAIgAAIKOQF5CgBPAAAgAAIKOQF5CgBPAAA1AAQKfyMAAiAACQqFCOEVAIIBACAACQqFCOEVAIIBAAAA.Rookiestar:BAAANQAECgcIEQAAAA==.',
Ru='Rumí:BAAANQAECgQIBAABNQAECgYICQAGAAAAAA==.',
Sa='Sabb:BAAANQADCgYIEAAAAA==.Samstephens:BAAANQADCgQIBAABNQAECgQIBgAGAAAAAA==.Saphroniå:BAAANQADCgcIGQAAAA==.Sass:BAABNQAECn8vAAMhAAkKnBrjLwBeAgAhAAgKvhrjLwBeAgAOAAIK3RCWYAB+AAAAAA==.Sazed:BAAANQADCgEIAQAAAA==.',
Sc='Schend:BAAANQADCgYICwAAAA==.',
Se='Sed:BAAANQAECgIIBQAAAA==.Serrana:BAAANQADCgUIBQAAAA==.',
Sf='Sfinktor:BAAANQADCgMIAgAAAA==.',
Sh='Shadowmortis:BAAANQAECgQJBQAAAA==.Shadowwilder:BAAANQAECgUICgAAAA==.Shirokhan:BAABNQAECn8jAAIFAAgK6xYfhgByAgAFAAgK6xYfhgByAgAAAA==.Shootum:BAAANQADCgUIBQAAAA==.Shïfthappens:BAAANQADCgUIBQAAAA==.',
Si='Sidewinderx:BAAANQAECgQIBAAAAA==.Sinlock:BAABNQAECn8dAAMNAAgK3B6EYgAuAgANAAcKTR+EYgAuAgAZAAQKMxG+NADvAAAAAA==.',
Sk='Skadí:BAAANQAECgQIBQAAAA==.Skrot:BAAANQADCgYIBgABNQAECgkJIwAKAPwXAA==.',
Sm='Smef:BAAANQADCgEIAQAAAA==.',
Sn='Snagglespark:BAABNQAECn8jAAMQAAkKyRz1HQAVAwAQAAkKyRz1HQAVAwAHAAYKQQvkswACAQAAAA==.Sneakylink:BAAANQADCgYIEQAAAA==.Snowbunni:BAAANQAECgIIAgAAAA==.',
So='Soladrian:BAAANQAECgcIDAAAAA==.Solanthion:BAEANQADCgcIBwABNQAECgYIEgAGAAAAAA==.',
Sp='Spankyee:BAAANQADCgQIBAAAAA==.',
Sr='Srtaco:BAAANQAECgQIBAAAAA==.',
St='Starz:BAAANQADCgYJBAAAAA==.Stelmaria:BAAANQAECgMIAwABNQAECgkJIgAXAAEcAA==.',
Su='Sunchipzz:BAAANQADCgQIBAAAAA==.Sundayschool:BAAANQAECgcJEgAAAA==.Sunwing:BAAANQAECgIIAgAAAA==.',
Sy='Syyia:BAAANQADCgIIAgAAAA==.',
['Sé']='Séraph:BAAANQAECgQIBQAAAA==.',
['Só']='Sóozabimaru:BAAANQAECgQICQAAAA==.',
Ta='Tahano:BAAANQABCgIIAgAAAA==.Talljeff:BAAANQAECggIDQAAAA==.Tankarmor:BAAANQAECgUIEwAAAA==.Taylorswif:BAACNQAFFH8HAAMFAAQKrQyeLAAjAQAFAAQKrQyeLAAjAQATAAEKSAeIFQA+AAA1AAQKfyAAAgUACQowGnZmALECAAUACQowGnZmALECAAAA.',
Tc='Tcharta:BAABNQAECn8mAAMRAAkKURoCDgDGAgARAAkKURoCDgDGAgAiAAEKAACxPwArAAAAAA==.',
Th='Thefamousone:BAAANQADCgYICAAAAA==.Theiá:BAAANQAECgEIAQAAAA==.Thermotide:BAAANQAECgYIDgAAAA==.Thornpaw:BAAANQADCgQIBAAAAA==.Thoror:BAAANQAECgUICgAAAA==.Thunderbolt:BAAANQADCgcIBwABNQAECgQIBAAGAAAAAA==.Thundernütz:BAAANQADCgIIAwAAAA==.Thymós:BAAANQAECgUIDAAAAA==.',
Ti='Tiffina:BAAANQADCgYICQAAAA==.Tiffzen:BAABNQAECn8WAAIXAAcKOAep2QBIAQAXAAcKOAep2QBIAQAAAA==.Timeskip:BAAANQADCggIBgAAAA==.Tinyfaith:BAAANQAECgQICAAAAA==.Titum:BAAANQAFFAIIBAABNQAFFAYIDAAFAOYIAA==.',
To='Tongpooh:BAABNQAECn8jAAIKAAkK/BfsFwCGAgAKAAkK/BfsFwCGAgAAAA==.',
Tr='Treeberk:BAAANQAECgIIAgAAAA==.Truelink:BAAANQADCggICgAAAA==.',
Tu='Tuba:BAAANQAECggIAwAAAA==.Tuckerherout:BAAANQAECgYIEAAAAA==.Tundro:BAAANQADCgUIBgAAAA==.',
Tw='Twix:BAAANQAECgIIAgABNQAECgQJCgAGAAAAAA==.',
['Tî']='Tîtån:BAAANQAECgUIEwAAAA==.',
Uh='Uh:BAABNQAECn8WAAIjAAgKTx3UIQB7AgAjAAgKTx3UIQB7AgABNQAFFAMICAAKAGghAA==.',
Un='Undeadlock:BAAANQAECgQIDAAAAA==.',
Va='Vale:BAAANQADCgEIAQAAAA==.',
Vg='Vgmking:BAABNQAECn8lAAISAAgKHxfePwD9AQASAAgKHxfePwD9AQAAAA==.',
Vi='Vigdis:BAAANQADCgcIBwAAAA==.Vindorei:BAAANQADCgUIDgAAAA==.',
Vo='Voidfed:BAAANQADCgQIBAABNQADCgQICAAGAAAAAA==.Voidfu:BAAANQADCgIIAgAAAA==.Voidrefund:BAAANQADCgYIBgAAAA==.Vokzhen:BAABNQAECn8lAAIcAAgKfhziFAC5AgAcAAgKfhziFAC5AgAAAA==.Volescu:BAAANQAECgQICgAAAA==.',
Wa='Walkerboah:BAAANQAECgYIEAAAAA==.Warmachinne:BAAANQAECgEIAQAAAA==.',
We='Weel:BAABNQAECn8pAAIIAAkKzRDAVgASAgAIAAkKzRDAVgASAgAAAA==.',
Wo='Wolfspider:BAAANQAECgIIAwAAAA==.',
Wy='Wyland:BAAANQAECgMIBQAAAA==.Wylander:BAAANQAECgYIDwAAAA==.Wylandvoker:BAAANQADCgIIAgAAAA==.',
Xa='Xanun:BAAANQADCgMIAwAAAA==.',
Xe='Xeri:BAABNQAECn8WAAIPAAkKORuSCwC1AgAPAAkKORuSCwC1AgABNQAFFAYIFwAkAGMlAA==.Xeromus:BAAANQAECgUIEAAAAA==.Xetsus:BAAANQADCgUJBQAAAA==.',
Ya='Yang:BAAANQABCgEIAQAAAA==.',
Yo='Yoink:BAAANQADCgUIBQAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Yv='Yvelmaya:BAAANQAECgUIEgAAAA==.',
Za='Zabawaba:BAAANQAECgIIAQABNQAECggIDgAGAAAAAA==.Zaboomaprune:BAAANQAECgYIEwAAAA==.Zarika:BAACNQAFFH8XAAIkAAYKYyU+AACBAgAkAAYKYyU+AACBAgA1AAQKfyoAAiQACQqRJlQAANoDACQACQqRJlQAANoDAAAA.Zarì:BAAANQAECgUIBwABNQAFFAYIFwAkAGMlAA==.',
Ze='Zeknull:BAABNQAECn8dAAMIAAgKTRxpOACAAgAIAAgKTRxpOACAAgABAAUKYg+H/gAcAQAAAA==.Zekthal:BAAANQAECgcIBwABNQAECggIHQAIAE0cAA==.Zenio:BAAANQADCgIIAgAAAA==.Zennah:BAAANQADCggIFgAAAA==.Zephy:BAAANQADCgcJCQAAAA==.',
Zr='Zrgl:BAAANQADCggICAAAAA==.',
['Zä']='Zäo:BAACNQAFFH8FAAINAAIK6xd7LQChAAANAAIK6xd7LQChAAA1AAQKfyQABCUACQphItMBACgDACUACQo7H9MBACgDAA0ABQq7Hf2fAJEBABkAAwo8IxU5ANsAAAAA.',
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
