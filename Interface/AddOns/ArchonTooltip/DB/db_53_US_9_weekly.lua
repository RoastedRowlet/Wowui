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

local lookup = {'Paladin-Retribution','Mage-Arcane','Unknown-Unknown','Monk-Windwalker','Warrior-Fury','Warrior-Arms','Warlock-Demonology','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','DemonHunter-Havoc','Paladin-Protection','Hunter-BeastMastery','Druid-Feral','Warlock-Destruction','Rogue-Assassination','Warrior-Protection','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Monk-Brewmaster','Druid-Balance','Mage-Frost','Paladin-Holy','Rogue-Outlaw','Warlock-Affliction',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acupuncher:BAAANQAECgIIAgAAAA==.',
Ad='Adamsandler:BAAANQADCggICAAAAA==.Adiwolf:BAAANQAECgIIBAAAAA==.',
Al='Alcha:BAAANQAECgMICAAAAA==.Alenndar:BAAANQADCgEIAQAAAA==.Alexdaddario:BAAANQAECgUICgAAAA==.Algaefungi:BAAANQAECgEIBQAAAA==.Althena:BAAANQAECgEIAQABNQAECggIIgABAMAeAA==.Alystana:BAAANQADCgUIBwAAAA==.',
Am='Amberelle:BAAANQADCgQIBAAAAA==.',
An='Anastera:BAAANQADCgYIBwAAAA==.Animeniac:BAAANQAECgMICAAAAA==.Anticlimax:BAAANQAECgYIEAAAAA==.Antilaw:BAAANQAECgEJAQAAAA==.Antisocial:BAAANQAECgQIBQAAAA==.',
Ao='Aoibhneas:BAAANQADCgcIBwAAAA==.',
Ap='Apprentice:BAABNQAECoEcAAICAAkKKSSLGwBVAwACAAkKKSSLGwBVAwAAAA==.',
Ar='Ariha:BAAANQAECgQIBAAAAA==.Artrael:BAAANQADCggJCAAAAA==.',
At='Atorim:BAAANQADCgIIAgABNQADCggIGAADAAAAAA==.',
Av='Avienndha:BAAANQAECgMICAAAAA==.Avriel:BAAANQAECgQICQABNQAECggIIgABAMAeAA==.',
Ba='Barbatos:BAAANQAECgEIAQAAAA==.',
Be='Beardeddrunk:BAAANQADCgUJBQAAAA==.Beornwildlaw:BAAANQABCgcIDgAAAA==.',
Bo='Bobbytofva:BAAANQAECgMIBAAAAA==.Boochaka:BAAANQAECgYIDwAAAA==.Bouman:BAAANQADCgYIBgAAAA==.Bouquet:BAAANQAECgUIBwAAAA==.',
Br='Brewdog:BAAANQAECgQJCgAAAA==.Brickfists:BAAANQADCgQIBAAAAA==.Brotherfuzz:BAAANQAECgIIAwAAAA==.',
Bu='Busterposer:BAAANQAECgIIAgAAAA==.',
Ca='Caelvaris:BAAANQADCgEIAQAAAA==.Calabooca:BAAANQADCgUICAAAAA==.Canadaclown:BAAANQADCgIJAgAAAA==.Candor:BAAANQADCgUIBQAAAA==.',
Ch='Cheesefries:BAAANQAECgMICAAAAA==.Chratos:BAAANQADCgYIBgAAAA==.',
Cl='Clapton:BAAANQAECgQICAAAAA==.Claptone:BAAANQAECgUIBAAAAA==.',
Co='Corpuscle:BAAANQAECgYIEAAAAA==.',
Cr='Critcomander:BAABNQAECoEYAAIBAAgKZQw0igCpAQABAAgKZQw0igCpAQAAAA==.Critties:BAAANQADCgMIAwAAAA==.Crueldin:BAAANQAECgUIDQAAAA==.',
Da='Dalsen:BAAANQAECgYIEwAAAA==.Dalvulpe:BAAANQADCgEIAQABNQAECgYIEwADAAAAAA==.Dankchop:BAAANQAECgUIBgAAAA==.Darkbishop:BAAANQABCgYICgAAAA==.Darklink:BAAANQAECgQIBAAAAA==.Dawnlighted:BAAANQADCgMIAwAAAA==.',
De='Deadlyshiet:BAAANQAECgMIBQABNQAFFAYIGQAEAM4WAA==.Demonfed:BAAANQABCgIIAgABNQADCgQIBAADAAAAAA==.Denrin:BAAANQAECgQIBAAAAA==.Deskpop:BAAANQADCgQIBAAAAA==.',
Di='Diabolikal:BAAANQADCgYIBgAAAA==.Dill:BAABNQAECoElAAIFAAkKtiR9AADAAwAFAAkKtiR9AADAAwAAAA==.Divinesmite:BAAANQABCgcICAAAAA==.',
Dm='Dmachine:BAABNQAECoEWAAIGAAcKcxCYhAC5AQAGAAcKcxCYhAC5AQABNQAFFAUIDgAHACUmAA==.',
Do='Dondeezy:BAAANQABCgIIAgAAAA==.',
Dr='Drdru:BAAANQAECgUIEQABNQADCgUIBQADAAAAAA==.Dreadshade:BAAANQADCgcIDgAAAA==.Dropfort:BAAANQAECgcICAAAAA==.Drscruffles:BAAANQADCgcIBwAAAA==.',
Du='Durkidurk:BAAANQADCgMIAwAAAA==.',
Dy='Dyabolykal:BAAANQABCgUIBwABNQADCgYIBgADAAAAAA==.',
Ea='Easily:BAAANQAECgYIDgAAAA==.',
El='Ellyanthia:BAAANQAECgMJAwAAAA==.',
Em='Emachine:BAAANQADCgcIBwABNQAFFAUIDgAHACUmAA==.',
Ex='Exio:BAAANQAECgQJCgAAAA==.',
Fa='Fastasheet:BAACNQAFFIEZAAIEAAYKzhaGAgAEAgAEAAYKzhaGAgAEAgA1AAQKgSgAAgQACQpqJbECAJ4DAAQACQpqJbECAJ4DAAAA.',
Fi='Fill:BAABNQAECoEiAAIIAAkKDiWzAADOAwAIAAkKDiWzAADOAwABNQAFFAIIAgADAAAAAA==.',
Fl='Flehtwo:BAACNQAFFIEHAAMJAAUK2wf3DAAiAQAJAAQKxgf3DAAiAQAKAAEKKRa7HABUAAA1AAQKgSQAAwkACQqiHEElALYCAAkACQqiHEElALYCAAoACApDCvJiAI0BAAAA.Flyinbanana:BAAANQADCgQIBAABNQAECgcIEAADAAAAAA==.',
Fr='Fraglen:BAAANQADCgUIBQABNQAECgcICgADAAAAAA==.Frags:BAAANQAECgcICgAAAA==.Fránknárf:BAAANQAECgEIAQAAAA==.',
Ge='Genjyosanzo:BAAANQAECgMIBwAAAA==.',
Gh='Ghorn:BAAANQADCgcICgAAAA==.Ghostkrim:BAAANQADCgUIBQAAAA==.',
Gi='Gilljoww:BAABNQAECoEbAAILAAgKix8VHACbAgALAAgKix8VHACbAgAAAA==.Gireigtulb:BAAANQADCgYIBgAAAA==.',
Gn='Gnzz:BAAANQAECgYIEgAAAA==.',
Go='Gocirr:BAAANQAECgQIBQAAAA==.',
Gr='Grito:BAAANQADCgYICgAAAA==.',
Ha='Haehn:BAAANQADCgMIAwAAAA==.Halstorm:BAAANQAECgQJBQAAAA==.Harrysax:BAAANQABCgYIBgAAAA==.',
He='Hedrake:BAAANQAECgQIBAAAAA==.Hexxytime:BAAANQADCgQIBAAAAA==.',
Hi='Hilazy:BAAANQAECgIIAwAAAA==.',
Hm='Hm:BAAANQADCggICwAAAA==.',
Ho='Holyfed:BAAANQADCgQIBAAAAA==.Holyphok:BAAANQAECgEJAQAAAA==.Hotdog:BAAANQAECgUIAgAAAA==.',
Ic='Icestormy:BAAANQADCgcIDQAAAA==.',
Ih='Ihavenofutur:BAAANQAECgEIAQAAAA==.',
Il='Iliil:BAABNQAECoEZAAILAAcKCSMbGAC8AgALAAcKCSMbGAC8AgAAAA==.Illbiteyou:BAAANQADCgQIBAAAAA==.Illidantwo:BAACNQAFFIEMAAIMAAUKRRM/BgCJAQAMAAUKRRM/BgCJAQA1AAQKgSoAAgwACQocJM0FAHwDAAwACQocJM0FAHwDAAAA.',
Im='Imprints:BAAANQAECgUIBgAAAA==.',
In='Inuk:BAAANQAECgYIEwAAAA==.',
Ir='Ironshaman:BAAANQAECgYIEQAAAA==.',
It='Italianapee:BAAANQAECgQIBAABNQAECgYIEwADAAAAAA==.',
Ja='Jabu:BAAANQADCgQIAwABNQAECgIIBgADAAAAAA==.Jada:BAAANQAECgQJBAAAAA==.Jaghatai:BAAANQADCgIIAgAAAA==.',
Je='Jenstonedart:BAAANQAECgQIDQAAAA==.Jeryeth:BAABNQAECoEaAAIGAAgK0h+PPACdAgAGAAgK0h+PPACdAgAAAA==.Jeryzard:BAAANQADCgYIDAAAAA==.',
Ji='Jiannybon:BAAANQADCgQICwAAAA==.',
Ju='Judgmental:BAAANQADCgYIBgAAAA==.Judidench:BAAANQAECggIDwAAAA==.Juicewillis:BAAANQADCgIIAgAAAA==.',
Ka='Kain:BAECNQAFFIEQAAINAAYKAyD/AAA0AgANAAYKAyD/AAA0AgA1AAQKgSAAAw0ACQoZJgQCAJ8DAA0ACQoZJgQCAJ8DAAEAAQo4CjpSATAAAAAA.Kanda:BAAANQADCgIIAgAAAA==.Kane:BAAANQAECgUIDwAAAA==.Karmasuture:BAAANQADCgYJBgABNQAECgMIAwADAAAAAA==.Kaïn:BAAANQAECgMIBAABNQAECggIIgABAMAeAA==.',
Ke='Kelsí:BAAANQAECgMIBwAAAA==.',
Ki='Kiwí:BAAANQAECgYIDwAAAA==.',
Kr='Krasavice:BAABNQAECoEdAAIOAAcKHxx/QABhAgAOAAcKHxx/QABhAgAAAA==.Krenik:BAAANQADCggIHwAAAA==.Krimsondeath:BAAANQADCgQIBAAAAA==.Krimtohell:BAAANQAECgIIAgAAAA==.Krisp:BAAANQAECgMIBAABNQADCgQIBAADAAAAAA==.',
Ku='Kurquaan:BAAANQADCggICAAAAA==.',
La='Lauranthalas:BAAANQAECgIIBQAAAA==.Lavenderhaze:BAAANQADCgEIAQAAAA==.',
Le='Leathal:BAAANQAECgYIEAAAAA==.Lemurshoes:BAAANQAECgIIAwAAAA==.Lemursneaker:BAAANQAECgYIDwAAAA==.Letsgomen:BAAANQADCgEJAQAAAA==.',
Li='Lightshock:BAAANQADCggIIgAAAA==.Linkblade:BAAANQADCgQIBAAAAA==.Linkdrood:BAAANQADCgcIBwAAAA==.',
Ll='Llaagg:BAAANQAECgIIAgAAAA==.',
Lo='Lokust:BAAANQAECgQICQAAAA==.',
Lu='Lucentdawn:BAAANQAECgYICwAAAA==.Luckyshrine:BAAANQABCggICwAAAA==.Ludachris:BAAANQAECgEIAQAAAA==.',
Ly='Lycanius:BAABNQAECoEaAAIPAAcK/hMhDQDbAQAPAAcK/hMhDQDbAQAAAA==.Lynqii:BAABNQAFFIEJAAMHAAUKvhOeDAA/AQAHAAQK7haeDAA/AQAQAAEKAQdTFwBRAAAAAA==.',
Ma='Malirra:BAAANQAECgUICwAAAA==.Malëk:BAABNQAECoEiAAIBAAgKwB76NwCqAgABAAgKwB76NwCqAgAAAA==.Maximus:BAAANQADCgUIBQAAAA==.',
Me='Mechatholic:BAAANQAECgQIBAAAAA==.Medallis:BAAANQABCgUICgAAAA==.Mellowlizard:BAACNQAFFIEOAAMHAAUKJSbnBADJAQAHAAQKWSbnBADJAQAQAAEKViUPDwBuAAA1AAQKgSMAAwcACQoiJAcSAB4DAAcACAqNJAcSAB4DABAAAwr2Hlo0AN0AAAAA.Metuss:BAAANQAECgUICAAAAA==.',
Mi='Miguel:BAAANQAECgUJDgAAAA==.Mira:BAAANQAECgYIDgAAAA==.',
Mk='Mkicon:BAAANQAECgQICQAAAA==.Mkultra:BAAANQAECgYICQAAAA==.',
Mo='Mogmoog:BAAANQAECgMIBwAAAA==.Mooganfreman:BAAANQADCgYIBgAAAA==.Moonangel:BAAANQAECgMICAAAAA==.Morbodan:BAABNQAECoEbAAIRAAkKAx2NCgAEAwARAAkKAx2NCgAEAwAAAA==.Mornangus:BAAANQABCgMIAwAAAA==.Motone:BAAANQAECgMJBAAAAA==.',
Mu='Multanni:BAAANQAECgYIDwAAAA==.',
My='Myonecrosis:BAAANQAECgMICAAAAA==.',
['Mö']='Mörs:BAAANQADCgEIAQAAAA==.',
Na='Nakrog:BAABNQAECoEZAAMSAAgKVBkFCwA8AgASAAgKVBkFCwA8AgAGAAEKkBr+CwFLAAAAAA==.Napster:BAAANQADCggIDwAAAA==.Nasa:BAACNQAFFIELAAIEAAQKsQzHBgAgAQAEAAQKsQzHBgAgAQA1AAQKgSQAAgQACQqcHm0NANACAAQACQqcHm0NANACAAAA.',
Ne='Nellarixi:BAABNQAECoEaAAITAAgKkxwCFQB3AgATAAgKkxwCFQB3AgAAAA==.Nethus:BAAANQADCgcJCQAAAA==.',
Ni='Niivalyr:BAAANQABCgIJAQAAAA==.Nimbus:BAAANQADCggIDgABNQAFFAQIBgAJAGkPAA==.',
No='Nodens:BAAANQADCgcIEwAAAA==.Nomaa:BAAANQAECgMICAAAAA==.Nomäd:BAAANQADCggIDAAAAA==.Nosneb:BAAANQADCgMIBAABNQADCggIEAADAAAAAA==.',
Ny='Nytedevil:BAAANQAECgUIBwAAAA==.',
['Nì']='Nìtsua:BAAANQADCggIEAAAAA==.',
Ob='Obilivion:BAAANQADCgYICgAAAA==.',
Og='Ogmount:BAAANQAECgMIAwAAAA==.',
Or='Orflame:BAABNQAECoEbAAMUAAgKeQcsIQCAAQAUAAgKeQcsIQCAAQAVAAEKKgW4HAAxAAAAAA==.',
Ph='Phantomhealz:BAAANQABCgIIAgAAAA==.Phrash:BAAANQAFFAIIAgAAAA==.',
Pi='Pigbearmans:BAAANQADCgYIBgAAAA==.',
Pl='Plex:BAAANQADCgQIBAABNQAECgkJIAAWAGEgAA==.',
Po='Pooldan:BAAANQAECgMJAgAAAA==.',
Pr='Praystatioñ:BAABNQAECoEZAAIXAAcKdhueBAA/AgAXAAcKdhueBAA/AgAAAA==.Premiumgank:BAAANQAECgIJAgAAAA==.Priestlink:BAAANQADCgYIBgAAAA==.Prtanks:BAAANQAECgMIBAAAAA==.',
Pu='Purerform:BAAANQADCgcIBwAAAA==.',
Qu='Quelidra:BAAANQADCgUIBQAAAA==.Quepaspete:BAAANQADCgYIBwAAAA==.',
Ra='Raa:BAABNQAECoEhAAIOAAgKbx54GgD8AgAOAAgKbx54GgD8AgAAAA==.Racker:BAAANQAECgIIBAAAAA==.Ragou:BAAANQADCgQIBAAAAA==.',
Re='Rengots:BAAANQADCgYIDAAAAA==.Rephtide:BAAANQAECgQICAAAAA==.Responsible:BAAANQAECgYIEgAAAA==.',
Rh='Rhaez:BAAANQAECgEIAQAAAA==.Rhall:BAAANQADCgYIBgAAAA==.Rhetoricdork:BAAANQAECgYIBgABNQAFFAYIEQACANgfAA==.',
Ro='Rogmash:BAAANQAECgUJCwAAAA==.Rokkoz:BAAANQAECgYIEQAAAA==.Romer:BAACNQAFFIEFAAIYAAIKOQGEBwBTAAAYAAIKOQGEBwBTAAA1AAQKgSMAAhgACQrfCCURAJABABgACQrfCCURAJABAAAA.Rookiestar:BAAANQAECgUIBQAAAA==.',
Sa='Sabb:BAAANQADCgYIEAAAAA==.Saphroniå:BAAANQADCgcIGQAAAA==.Sass:BAABNQAECoEhAAIZAAgKqxowJgBlAgAZAAgKqxowJgBlAgAAAA==.Sazed:BAAANQADCgEIAQAAAA==.',
Sc='Schend:BAAANQADCgYICwAAAA==.',
Se='Sed:BAAANQAECgIIBQAAAA==.Serrana:BAAANQADCgUIBQAAAA==.',
Sf='Sfinktor:BAAANQADCgMIAgAAAA==.',
Sh='Shadowmortis:BAAANQAECgQJBQAAAA==.Shirokhan:BAAANQAECggIDgAAAA==.',
Si='Sidewinderx:BAAANQADCgEIAQAAAA==.Sinlock:BAABNQAECoEdAAMHAAgKQx8EPQBdAgAHAAcKoh8EPQBdAgAQAAQKMxFSLgD9AAAAAA==.',
Sk='Skadí:BAAANQAECgEIAQAAAA==.Skrot:BAAANQADCgYIBgAAAA==.',
Sn='Snagglespark:BAAANQAECgcIEwAAAA==.Sneakylink:BAAANQADCgYIBgAAAA==.Snowbunni:BAAANQAECgIIAgAAAA==.',
So='Soladrian:BAAANQAECgYICgAAAA==.Solanthion:BAEANQADCgcIBwABNQAECgUIBwADAAAAAA==.',
Sp='Spankyee:BAAANQADCgQIBAAAAA==.',
St='Starz:BAAANQADCgYJBAAAAA==.Stelmaria:BAAANQADCgUIBQABNQAECggIHAAOAKwbAA==.',
Su='Sunchipzz:BAAANQADCgQIBAAAAA==.Sundayschool:BAAANQAECgcJEgAAAA==.',
Sy='Syyia:BAAANQADCgIIAgAAAA==.',
['Sé']='Séraph:BAAANQAECgIIAwAAAA==.',
['Só']='Sóozabimaru:BAAANQAECgQICQAAAA==.',
Ta='Tahano:BAAANQABCgIIAgAAAA==.Talljeff:BAAANQAECggICgAAAA==.Tankarmor:BAAANQAECgQICQAAAA==.Taylorswif:BAACNQAFFIEHAAMCAAQKEwsCGwA6AQACAAQKEwsCGwA6AQAaAAEKSAeZDQBHAAA1AAQKgSAAAgIACQodHF5AAOMCAAIACQodHF5AAOMCAAAA.',
Tc='Tcharta:BAAANQAECgcIEAAAAA==.',
Th='Thefamousone:BAAANQADCgYICAAAAA==.Thermotide:BAAANQAECgYIDgAAAA==.Thoror:BAAANQAECgUIBQAAAA==.Thunderbolt:BAAANQADCgcIBwABNQAECgQIBAADAAAAAA==.Thundernütz:BAAANQADCgIIAgAAAA==.Thymós:BAAANQAECgUICwAAAA==.',
Ti='Tiffina:BAAANQADCgYICQAAAA==.Tiffzen:BAAANQAECgYIEAAAAA==.Timeskip:BAAANQADCggIBgAAAA==.Tinyfaith:BAAANQADCggIDQAAAA==.Titum:BAAANQAFFAIIAwABNQAECgkJIQACACcYAA==.',
To='Tongpooh:BAABNQAECoEfAAIEAAkKmRi5DwCtAgAEAAkKmRi5DwCtAgABNQADCgYIBgADAAAAAA==.',
Tr='Treeberk:BAAANQAECgIIAgAAAA==.Truelink:BAAANQADCgUIBQAAAA==.',
Tu='Tuba:BAAANQAECggIAQAAAA==.Tuckerherout:BAAANQAECgYIEAAAAA==.Tundro:BAAANQADCgUIBgAAAA==.',
Tw='Twix:BAAANQAECgIIAgABNQAECgQJCgADAAAAAA==.',
['Tî']='Tîtån:BAAANQAECgQICQAAAA==.',
Uh='Uh:BAAANQAECgcIEQABNQAFFAIIAgADAAAAAA==.',
Un='Undeadlock:BAAANQAECgMIBAAAAA==.',
Va='Vale:BAAANQADCgEIAQAAAA==.',
Vg='Vgmking:BAABNQAECoEeAAILAAgKHBBTRACnAQALAAgKHBBTRACnAQAAAA==.',
Vi='Vindorei:BAAANQADCgUIDgAAAA==.',
Vo='Vokzhen:BAAANQAECgUIEAAAAA==.Volescu:BAAANQAECgQIBwAAAA==.',
Wa='Walkerboah:BAAANQAECgYIDAAAAA==.Warmachinne:BAAANQADCgYIBgAAAA==.',
We='Weel:BAABNQAECoEaAAIbAAgKbBGwTADyAQAbAAgKbBGwTADyAQAAAA==.',
Wo='Wolfspider:BAAANQAECgIIAwAAAA==.',
Wy='Wyland:BAAANQAECgMIBQAAAA==.Wylander:BAAANQAECgUICQAAAA==.Wylandvoker:BAAANQADCgIIAgAAAA==.',
Xa='Xanun:BAAANQADCgMIAwAAAA==.',
Xe='Xeri:BAAANQAECgcICwABNQAFFAUIDAAcAF4aAA==.Xeromus:BAAANQAECgMIBgAAAA==.Xetsus:BAAANQADCgUJBQAAAA==.',
Ya='Yang:BAAANQABCgEIAQAAAA==.',
Yo='Yoink:BAAANQADCgUIBQAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Yv='Yvelmaya:BAAANQAECgMICAAAAA==.',
Za='Zaboomaprune:BAAANQAECgUIBwAAAA==.Zarika:BAACNQAFFIEMAAIcAAUKXhpwAADSAQAcAAUKXhpwAADSAQA1AAQKgScAAhwACQp/JioAAOwDABwACQp/JioAAOwDAAAA.Zarì:BAAANQAECgUIBwABNQAFFAUIDAAcAF4aAA==.',
Ze='Zeknull:BAABNQAECoEcAAMbAAgKTRxHJwCXAgAbAAgKTRxHJwCXAgABAAQKZw5j3ADuAAAAAA==.Zenio:BAAANQADCgIIAgAAAA==.Zennah:BAAANQADCggICAAAAA==.Zephy:BAAANQADCgcJCQAAAA==.',
Zr='Zrgl:BAAANQADCggICAAAAA==.',
['Zä']='Zäo:BAACNQAFFIEFAAIHAAIK6xe/HACpAAAHAAIK6xe/HACpAAA1AAQKgSQABB0ACQrWIucAAFADAB0ACQpjIOcAAFADAAcABQoiH/NxALEBABAAAwopG84yAOQAAAAA.',
['Ïk']='Ïkea:BAAANQAECgQIBwAAAA==.',
['ßl']='ßloodhunter:BAAANQADCgIIAgAAAA==.',
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
