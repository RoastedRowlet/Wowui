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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Affliction','Rogue-Subtlety','Monk-Windwalker','Hunter-Marksmanship','Evoker-Devastation','Mage-Arcane',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Account:BAAANQABCgQIBAAAAA==.',
Ag='Agnithor:BAAANQAECgUICQAAAA==.',
Al='Aliadra:BAAANQAECgUICQAAAA==.Alistus:BAAANQAECgcIEwAAAA==.Alphá:BAAANQADCgcICAABNQAECgQIDQABAAAAAA==.',
An='Angua:BAAANQAECgQIBQAAAA==.Anotheralt:BAAANQAECggIAQAAAA==.',
Au='Aurius:BAAANQADCggIHQAAAA==.',
Av='Aveliandis:BAAANQAECgUIBgAAAA==.',
Az='Azerphage:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Azhorra:BAAANQADCgQIBwAAAA==.Azzog:BAAANQADCgcICAABNQADCgcIDgABAAAAAA==.Azül:BAAANQAECgIIAgAAAA==.',
Ba='Bacchanalian:BAAANQADCgMIAwABNQAECgQICgABAAAAAA==.Baelrin:BAAANQAECgEIAQAAAA==.Baindyn:BAAANQADCgYIEAAAAA==.Barator:BAAANQADCgYIFAAAAA==.',
Be='Beaum:BAAANQAECgcIEQAAAA==.',
Bl='Blackröse:BAAANQAECgYIEAAAAA==.Bladebane:BAAANQADCgcIBwAAAA==.Blksunshine:BAAANQADCgYIDgAAAA==.',
Bo='Bolash:BAAANQAECgUICwAAAA==.Bovinelover:BAAANQAECgQIAgAAAA==.',
Br='Bradthomas:BAAANQAECgEIAQAAAA==.Bruscha:BAAANQADCggIBQAAAA==.',
Bu='Bulvhine:BAAANQAECgMIAwAAAA==.',
Ca='Cactusteeth:BAAANQAECgIIBAAAAA==.Cafeconpan:BAAANQAECgMIBAAAAA==.Camford:BAAANQADCggIDgAAAA==.Cantatrix:BAAANQADCgYIBgAAAA==.Capslok:BAAANQADCgUIBQAAAA==.Captinmeat:BAAANQADCgYICgAAAA==.Castus:BAAANQADCgcIDgAAAA==.',
Ce='Cecilx:BAAANQAECgEIAQAAAA==.Censøred:BAAANQAECgIIAgAAAA==.',
Ch='Chimerax:BAABNQAECoEZAAMCAAkJ2x30IQBlAgACAAcJuRv0IQBlAgADAAUJXSCVBQCYAQAAAA==.Chronic:BAAANQADCgYICgAAAA==.Chully:BAAANQAECgcIEQAAAA==.',
Cl='Clairíty:BAAANQADCggICwAAAA==.Click:BAAANQAECgQIBgAAAA==.',
Co='Comadore:BAAANQAECgcIDQAAAA==.',
Cr='Crankycad:BAAANQADCgcIBwAAAA==.',
Da='Daphe:BAAANQAECgQIBQAAAA==.Darknesheart:BAAANQABCgQIBgAAAA==.',
De='Deathslead:BAAANQAECgQIBAAAAA==.Decrepe:BAAANQAECgcIEAAAAA==.Delph:BAAANQAECgYIDQAAAA==.Deshal:BAAANQADCgUIDgAAAA==.',
Di='Discostar:BAAANQAECgQIBwAAAA==.Distill:BAAANQADCgQIBAABNQAFFAYIDgAEALYdAA==.',
Dr='Drajhar:BAAANQADCgYIBgAAAA==.Draq:BAAANQADCgYIFAAAAA==.Druidcam:BAAANQADCgcICwAAAA==.',
Eb='Ebonhorn:BAAANQADCgYIDAAAAA==.',
Ei='Einari:BAAANQAECgQIBQAAAA==.',
Ek='Ekiim:BAAANQADCggIDgAAAA==.',
El='Eldamari:BAAANQADCgUIBQAAAA==.',
Em='Emdralaeth:BAAANQADCgMIAwAAAA==.Emeraldfury:BAAANQADCgUIBQAAAA==.',
Er='Eridor:BAAANQAECgMIAwAAAA==.',
Es='Esbernia:BAAANQAECgUICQAAAA==.',
Et='Ettne:BAAANQADCgYIBQAAAA==.',
Ex='Exek:BAAANQAECgMIAwAAAA==.',
Fa='Fabaztard:BAAANQAECgEIAQAAAA==.Faline:BAAANQAECgQIBAAAAA==.',
Fe='Felgetabouit:BAAANQAECgcIEgAAAA==.Feort:BAAANQABCgIIAgAAAA==.Ferlane:BAAANQABCgYICQAAAA==.',
Fi='Fidelity:BAAANQABCgIIAgAAAA==.Fights:BAAANQAECgQIBAAAAA==.Filintos:BAAANQADCgMIAwAAAA==.',
Fl='Fleshworker:BAAANQADCgYIBgAAAA==.',
Fo='Fontaine:BAAANQADCgMIAwAAAA==.Foradin:BAAANQAECgIIBAAAAA==.Forky:BAAANQAECgEIAgAAAA==.Foxknight:BAAANQADCgYIEAAAAA==.',
Fr='Franksnbeans:BAAANQAECgIIAgAAAA==.Fryeren:BAAANQADCgcIBwAAAA==.',
Ga='Gaern:BAAANQAECgYIEQAAAA==.Gaidin:BAAANQAECggIEAAAAA==.Gameslayer:BAAANQAECgEIAQAAAA==.Gankzilla:BAAANQAECgcIEgAAAA==.',
Gi='Gila:BAAANQADCgcICAAAAA==.Gizzle:BAAANQAECgcIEgAAAA==.',
Gr='Greel:BAAANQABCgEIAQAAAA==.Grimanack:BAAANQADCgYICQAAAA==.Grÿm:BAAANQADCgYIBwAAAA==.',
Ha='Hanjha:BAAANQAECgQIBQAAAA==.',
He='Helldozer:BAAANQAECgQIBgAAAA==.Hexinu:BAAANQAECgQIBgAAAA==.',
Hi='Hiyue:BAAANQAECgcIAQAAAA==.',
Ho='Holeinheart:BAAANQADCgMIAwAAAA==.',
Hu='Hugzy:BAAANQADCgMIAwAAAA==.',
Hy='Hypnocide:BAEANQAECgQIBQAAAA==.',
Ib='Ibuki:BAAANQADCgIIAgABNQAECgcIEgABAAAAAA==.',
Ig='Iguanajon:BAAANQAECgMIAwAAAA==.',
Il='Illuvatar:BAAANQAECgQIBwAAAA==.',
Im='Impsane:BAAANQADCgQIBAAAAA==.',
Ir='Irv:BAAANQADCgYICAAAAA==.',
Is='Isellrocks:BAAANQAECgUIBgAAAA==.',
Ja='Jaxxa:BAAANQADCggIDgAAAA==.',
Je='Jeddiah:BAAANQADCgYIEAAAAA==.Jetstorm:BAAANQAECgYIBgAAAA==.',
Ji='Jinkès:BAAANQADCggIDgAAAA==.',
Ju='Juanting:BAAANQADCgEIAgAAAA==.Jubei:BAAANQAECgYIDQAAAA==.Judis:BAAANQAECgQIBwAAAA==.Justokevoker:BAAANQAECgcIEQAAAA==.',
Ka='Kairì:BAAANQAECgMIAwAAAA==.Kalifist:BAABNQAECoEWAAIFAAkJ3RWyDwA+AgAFAAkJ3RWyDwA+AgAAAA==.Kalku:BAAANQADCgcIEQAAAA==.Kanajotoma:BAAANQADCgYICwAAAA==.Karlai:BAAANQADCggIFAABNQAECggIEAABAAAAAA==.',
Ke='Keleena:BAEANQAECgQIBQAAAA==.Keze:BAAANQAECgcIEQAAAA==.',
Kh='Khorahlia:BAAANQADCgQIBAABNQAECgYIEQABAAAAAA==.',
Ki='Killzshot:BAAANQADCgQIBAAAAA==.Kinst:BAAANQAECgQIBQAAAA==.Kitanyia:BAAANQAECgYICwAAAA==.Kittiy:BAAANQAECgEIAQAAAA==.Kizahnevo:BAAANQADCggIFgAAAA==.',
Ko='Kordelia:BAAANQAECgQIBAABNQAECgYIEQABAAAAAA==.',
Kr='Krench:BAAANQADCgQIBAAAAA==.Krusty:BAAANQADCgYIBgAAAA==.',
Ky='Kyakuna:BAAANQADCgQIBAAAAA==.Kyloon:BAAANQAECgIIAwAAAA==.Kyrah:BAAANQAECgQIBQAAAA==.',
La='Lakatryna:BAAANQAECgUIBQABNQAECgkJIQAGAKIeAA==.Lamanira:BAAANQADCgYIDgAAAA==.',
Le='Lejend:BAAANQAECgQIBAAAAA==.',
Ll='Llanedh:BAAANQAECgIIAgAAAA==.',
Lo='Loaganic:BAAANQADCggICAAAAA==.Lonelyhearts:BAAANQAECgEIAgAAAA==.Lorimuni:BAAANQADCggIFAAAAA==.',
Ly='Lytol:BAAANQAECgQIBQAAAA==.',
Ma='Maenad:BAAANQAECgQICgAAAA==.Maeple:BAAANQADCgcIDQAAAA==.Manamontana:BAAANQAECgMIAwAAAA==.Mazikeene:BAAANQADCgYIBgAAAA==.',
Me='Meladyn:BAAANQAECgYIDgAAAA==.',
Mi='Miami:BAACNQAFFIEJAAIHAAUJDxvBAADYAQAHAAUJDxvBAADYAQA1AAQKgRYAAgcACQmPI28BAJMDAAcACQmPI28BAJMDAAAA.Michelle:BAAANQADCgEIAQAAAA==.Missmaam:BAAANQADCgcIDAAAAA==.Mistroot:BAAANQADCgcICgAAAA==.Mizu:BAAANQADCgUIBQAAAA==.',
Mo='Monkfox:BAAANQAECgcIEwABNQAECgcIEQABAAAAAA==.Moon:BAAANQADCgUIBQAAAA==.Moonfirespam:BAAANQADCggICAAAAA==.',
Mu='Mushuwoonter:BAAANQAECgQIBAABNQAECgcIDwABAAAAAA==.Muztang:BAAANQAECgQIBQAAAA==.',
My='Mythhunter:BAAANQAECgEIAQAAAA==.',
['Mô']='Mônkii:BAAANQAECgcIEQAAAA==.',
Na='Nace:BAAANQABCgIIAgAAAA==.Naenia:BAAANQADCgcIDAAAAA==.Nariar:BAAANQADCggICQABNQAECgcIEgABAAAAAA==.Nateldin:BAAANQAECgUIBwAAAA==.',
Ni='Nightcat:BAAANQADCgUICQAAAA==.Niisha:BAAANQAECgQIBQABNQAECgYICgABAAAAAA==.',
No='Nocainus:BAAANQAECgQIBgAAAA==.',
['Nø']='Nøtsure:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Ob='Obsidia:BAAANQAECgQIBgAAAA==.',
Od='Oddlife:BAAANQAECgQICAAAAA==.',
On='Onik:BAAANQADCgIIAwABNQADCgUICQABAAAAAA==.',
Op='Ophj:BAABNQAECoEeAAIIAAkJARyLLQDbAgAIAAkJARyLLQDbAgAAAA==.',
Or='Orangejulius:BAAANQADCgYICwABNQADCggIDgABAAAAAA==.Orangutan:BAAANQAECgMIBQAAAA==.Orinoheal:BAAANQADCgYICAAAAA==.',
Os='Oskar:BAAANQAECgcIEQAAAA==.',
Pe='Pebda:BAAANQADCgYIEgAAAA==.Perilous:BAAANQADCgUIDAAAAA==.',
Ph='Phoelar:BAAANQAECgMIAwAAAA==.Phuumyn:BAAANQAECgQIBgAAAA==.',
Pi='Piccoblast:BAABNQAECoEeAAIIAAkJDSSVCgCLAwAIAAkJDSSVCgCLAwAAAA==.Pichus:BAAANQADCgMIAwABNQAECgQIDQABAAAAAA==.Picklesoup:BAAANQAECgIIAgAAAA==.Piickles:BAAANQAFFAIIAgAAAA==.Pity:BAAANQAECgEIAgAAAA==.',
Pl='Plutø:BAAANQAECgUICAAAAA==.',
Po='Polylocks:BAAANQADCgYICwABNQADCgcIBwABAAAAAA==.Potatogg:BAAANQAECgEIAQAAAA==.',
Pr='Praeastra:BAEANQAECgUIBQAAAA==.Prókill:BAAANQAECgQIBQAAAA==.',
Ps='Psychokitty:BAAANQAECgQICgAAAA==.',
Qu='Quilian:BAAANQAECgcIEgAAAA==.',
Ra='Raelynn:BAAANQAECgQIBgAAAA==.Rancier:BAAANQADCgYIFAAAAA==.Rashalisk:BAAANQADCgMIAwAAAA==.',
Re='Rednecker:BAAANQABCgIIAgAAAA==.Redvex:BAAANQAECgcIEQAAAA==.Reinhard:BAAANQAECgEIAQAAAA==.Rencraw:BAAANQADCgYIDQAAAA==.Renras:BAAANQADCggIEAAAAA==.',
Rh='Rhain:BAAANQAECgMIBAAAAA==.Rhuxy:BAAANQAECgEIAQAAAA==.',
Ri='Rinah:BAAANQAECgcIEwAAAA==.',
Ro='Ronwen:BAAANQADCgUIBQABNQAECgcIEgABAAAAAA==.Rootbeard:BAAANQAECgUIBgAAAA==.Rosanna:BAAANQADCgUIDQAAAA==.Rotyr:BAAANQADCggIFQAAAA==.',
Ru='Ruana:BAEANQADCgYIDwAAAA==.',
Ry='Rye:BAAANQAECgEIAQAAAA==.',
Sc='Scoobey:BAAANQAECgEIAQAAAA==.Scubbs:BAAANQAECgcIEgAAAA==.Scubbsboo:BAAANQADCggICQABNQAECgcIEgABAAAAAA==.',
Se='Selenei:BAAANQADCgEIAQAAAA==.Servantes:BAAANQAECgQIBQAAAA==.',
Sh='Shamancam:BAAANQADCgIIAgAAAA==.Shamp:BAAANQADCggIFgAAAA==.Shiggy:BAAANQAECgIIAgAAAA==.Shotya:BAAANQAECgQIBgAAAA==.',
Si='Sixthknight:BAAANQADCggIGgAAAA==.',
Sl='Slappi:BAAANQADCgcIDQAAAA==.',
Sn='Snarkypony:BAAANQADCgYIEAAAAA==.',
So='Sonofathorck:BAAANQADCgEIAQAAAA==.Sorsere:BAAANQADCgcIBwAAAA==.',
Sp='Spcecialk:BAAANQADCgEIAQAAAA==.Specialk:BAAANQAECgYIDgAAAA==.Spellthat:BAAANQADCggICAAAAA==.',
St='Stirredihime:BAAANQAECgUICAAAAA==.',
Su='Sugarmomma:BAAANQADCgcIBwAAAA==.Sulph:BAAANQAECgQIBgAAAA==.Sundorei:BAAANQADCgIIAgAAAA==.',
Sv='Svalir:BAAANQADCgUICQAAAA==.',
Ta='Talshekar:BAAANQAECgIIAgAAAA==.Tarsis:BAAANQAECgIIAwAAAA==.',
Te='Teiana:BAAANQAECgcIEwAAAA==.',
Th='Thaevin:BAAANQAECgQIBAAAAA==.Thews:BAAANQABCgEIAQAAAA==.Thilendrel:BAAANQAECgcIEwAAAA==.Thingwan:BAAANQAECgcIEgAAAA==.',
Ti='Tinystink:BAAANQAECgMIBgAAAA==.',
To='Toddstephens:BAAANQADCgYICgAAAA==.Tors:BAAANQAECgUIDQAAAA==.Toterbonem:BAAANQADCgMIAwAAAA==.Toyotathon:BAAANQADCgYIBgABNQADCggIDgABAAAAAA==.',
Tr='Trasky:BAAANQAECgMIBQAAAA==.Trollololo:BAAANQAECgQIBgAAAA==.Troy:BAAANQAECgQIBAAAAA==.Trylly:BAAANQADCgcIBwAAAA==.Trëze:BAAANQAECggIDgAAAA==.',
Tt='Ttaartt:BAAANQAFFAIIAgAAAA==.',
Ty='Typh:BAAANQAECgcIEQAAAA==.',
Un='Undeaddemon:BAAANQAECgcIEQAAAA==.Undeaddh:BAAANQADCggICAABNQAECgcIEQABAAAAAA==.Undignified:BAAANQAECgQIBQAAAA==.Unholysixth:BAAANQADCgUIDgAAAA==.',
Va='Vanidarr:BAAANQADCgQIBAAAAA==.',
Ve='Verasia:BAAANQADCgUIBgAAAA==.',
Vi='Vidikan:BAAANQADCgIIAwAAAA==.Violett:BAAANQAECgQICQAAAA==.',
Vo='Voidwarranty:BAAANQAECgQIDQAAAA==.Vortre:BAAANQABCgcIBwAAAA==.',
Vv='Vvumpscut:BAAANQAECgYIDQAAAA==.',
Wa='Waldón:BAAANQAECgIIAgAAAA==.',
Wi='Wildsoul:BAAANQAECgEIAQAAAA==.Wistywind:BAAANQABCgYICQAAAA==.',
Xc='Xclaw:BAAANQAECgQIBAAAAA==.',
Xe='Xeroxgravity:BAAANQAECgEIAgAAAA==.',
Xi='Xilphira:BAAANQADCgUIDwAAAA==.Xirian:BAAANQADCggIDQABNQAECgEIAgABAAAAAA==.',
Xl='Xlithz:BAAANQAECgQIBAAAAA==.',
Ya='Yah:BAAANQADCgQIBwAAAA==.Yautjah:BAAANQADCgUIBQAAAA==.',
Yl='Ylene:BAAANQADCgUICgAAAA==.',
Yo='Yoink:BAAANQAECgcIEQAAAA==.Yondu:BAAANQADCgYIBgABNQAECgQICQABAAAAAA==.',
Za='Zalzuke:BAAANQAECgEIAQAAAA==.Zarinchaos:BAAANQAECgQIBgAAAA==.',
Ze='Zein:BAAANQADCgYIFAAAAA==.Zente:BAAANQAECgYIEQAAAA==.Zequill:BAAANQAECgQIBAAAAA==.Zevsticles:BAAANQAECgcIEwAAAA==.',
Zh='Zhom:BAABNQAECoEhAAIGAAkJoh76BwARAwAGAAkJoh76BwARAwAAAA==.',
Zo='Zooj:BAAANQAECgQIBQAAAA==.Zorlak:BAAANQADCgUIBQAAAA==.',
Zu='Zulall:BAAANQADCgQIBAAAAA==.',
Zy='Zylofeather:BAAANQADCgUIBQAAAA==.',
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
