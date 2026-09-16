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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Paladin-Protection','Unknown-Unknown','DeathKnight-Frost','Paladin-Holy','DemonHunter-Devourer','Warrior-Arms','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Hunter-Marksmanship','DeathKnight-Blood','Mage-Arcane','Mage-Frost',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Absofsteels:BAAANQAECgQIBgAAAA==.',
Ac='Acaric:BAAANQAECgEIAQAAAA==.',
Ad='Adøra:BAABNQAECoEYAAIBAAkJUxdBGgCqAgABAAkJUxdBGgCqAgAAAA==.',
Ag='Agumon:BAAANQADCggIFwAAAA==.',
Al='Alistair:BAAANQADCgUIBQAAAA==.Alluriel:BAAANQADCggIEgAAAA==.Altharoth:BAABNQAECoEXAAMCAAkJmhgKHwCtAgACAAkJmhgKHwCtAgADAAEJzAzYOwA2AAAAAA==.',
Am='Amira:BAAANQADCgYIDwABNQAECgcIEAAEAAAAAA==.Amormage:BAAANQADCgcIEQAAAA==.Amphitrite:BAAANQADCgUIBQAAAA==.',
An='Anteiku:BAAANQAECgIIBAAAAA==.Anteikudeath:BAAANQADCgEIAQAAAA==.',
Ap='Applemoose:BAAANQAECgQIBQAAAA==.',
Ar='Arauial:BAAANQAECgMIAwAAAA==.Arcanis:BAAANQAECgQICwAAAA==.Aribella:BAAANQAECgYICgAAAA==.Arizae:BAAANQADCgcIBwAAAA==.Arizann:BAAANQAECgEIAQAAAA==.Arobotev:BAAANQAECgUICgAAAA==.',
As='Astaren:BAAANQADCgcIEAAAAA==.',
At='Atiya:BAAANQAECgYIEAAAAA==.',
Az='Azaris:BAAANQAECgMIAwAAAA==.',
Ba='Babykraze:BAAANQAECgQIBgAAAA==.Baelrog:BAAANQADCggIFwAAAA==.Baiene:BAAANQAECgIIAgAAAA==.Baiken:BAAANQADCgYIBgAAAA==.Baldheadelf:BAAANQADCgQIBAAAAA==.Bandalar:BAAANQAECgYIDQAAAA==.Banerino:BAAANQADCgIIAgAAAA==.Barnabust:BAAANQADCgYIBwAAAA==.Bashems:BAAANQAECgEIAQAAAA==.Baston:BAAANQADCgIIAgAAAA==.',
Be='Beastums:BAAANQAECgUICgAAAA==.',
Bi='Bigchungus:BAAANQADCggICQAAAA==.Bingbong:BAAANQADCgEIAQAAAA==.',
Bl='Blacken:BAAANQADCgIIAgAAAA==.Bleak:BAAANQADCgQIBAAAAA==.Blindmonk:BAAANQAECgMIAwAAAA==.Bloodmary:BAAANQAECgEIAQAAAA==.Bloodor:BAAANQADCgEIAQAAAA==.Bloöm:BAAANQAECgcIEgAAAA==.',
Bm='Bmaazi:BAAANQAECgMIBAAAAA==.',
Bo='Bonerina:BAAANQAECgQICQAAAA==.Boomadk:BAABNQAECoEbAAIFAAgJ0x9OCQDLAgAFAAgJ0x9OCQDLAgAAAA==.',
Br='Bradburn:BAAANQADCgYIDAAAAA==.Brasserz:BAAANQAECgMIAwAAAA==.Breezybone:BAAANQAECgYIBgAAAA==.Briaela:BAAANQADCgIIAgAAAA==.Brice:BAAANQADCgYICgAAAA==.Briochebun:BAAANQAECgUIBwAAAA==.',
Bw='Bwangifer:BAAANQAECgUICQAAAA==.',
['Bë']='Bëcky:BAABNQAECoEcAAMCAAkJBCQoBQCkAwACAAkJBCQoBQCkAwAGAAYJYxLiSgCCAQAAAA==.',
Ca='Caso:BAAANQADCgMIBAABNQAECgEIAgAEAAAAAA==.',
Ce='Cellysia:BAAANQAECgQIBwAAAA==.Ceramyth:BAAANQADCgYICwAAAA==.Ceres:BAAANQAECgUICgAAAA==.Cesara:BAAANQAECgYIEAAAAA==.',
Ch='Chal:BAAANQADCgcIBwAAAA==.Chaplin:BAAANQADCgUIBQABNQAECgMIAwAEAAAAAA==.Chasterra:BAAANQABCgIIAgABNQAECgMIAwAEAAAAAA==.Chbribs:BAAANQADCggIFwAAAA==.Chiptewth:BAAANQABCgYIBwAAAA==.Chiron:BAAANQADCgEIAQAAAA==.',
Co='Coldsteel:BAAANQADCggIGgAAAA==.Columbina:BAABNQAECoEWAAIHAAgJihW7FQBJAgAHAAgJihW7FQBJAgAAAA==.Corn:BAAANQADCgIIAgAAAA==.',
Cp='Cptredbeardd:BAAANQADCgYIDgAAAA==.',
Cr='Crackmonger:BAABNQAECoEdAAIIAAkJ0xqkIQDMAgAIAAkJ0xqkIQDMAgAAAA==.Crackundead:BAAANQAECgcIEgAAAA==.Crapdragon:BAAANQADCgEIAQAAAA==.',
Cy='Cyphr:BAAANQAECgUICgAAAA==.Cyrinx:BAAANQAECgMIAwAAAA==.',
Da='Daen:BAAANQADCggICAAAAA==.Dagravytrain:BAAANQAECgUIBQAAAA==.Dalend:BAAANQAECgYIDQAAAA==.Damerot:BAAANQAECgUIBgAAAA==.Dangerous:BAAANQADCgYIFAAAAA==.Danpal:BAAANQADCgEIAQAAAA==.Dansharo:BAAANQADCgMIAwAAAA==.Darnnix:BAAANQAECgEIAgAAAA==.Darthrevin:BAAANQAECgUICAAAAA==.Dawnsingers:BAAANQADCgQIBAAAAA==.',
De='Deadbeard:BAAANQAECgQIDQAAAA==.Deathbash:BAAANQADCgEIAQAAAA==.Deathdream:BAAANQADCgMIAwAAAA==.Deathrar:BAAANQADCgcICwAAAA==.Deathviix:BAAANQADCgYICwAAAA==.Debased:BAAANQAECgQIBAAAAA==.Demini:BAAANQADCgYIDQAAAA==.Demisê:BAAANQAECgYIEAAAAA==.Demonn:BAAANQADCgEIAQAAAA==.Derbygirl:BAAANQADCgYIDAAAAA==.Desso:BAAANQADCgYIEQAAAA==.Detraz:BAAANQABCgEIAQAAAA==.Devilskin:BAAANQADCgMIAwAAAA==.',
Di='Dillinger:BAAANQADCggIGQAAAA==.Dingodgaf:BAAANQAECgMIBgAAAA==.',
Dj='Djinnjuicy:BAAANQAECgQICQAAAA==.',
Do='Dodo:BAAANQADCgYIBgAAAA==.Dorianmyth:BAAANQAECgQIBQAAAA==.',
Dr='Dragonshammy:BAAANQADCgMIAwAAAA==.Dreamclaw:BAAANQADCgYIEAAAAA==.Drippindots:BAAANQAECgcIEgAAAA==.Driztette:BAAANQAECgIIAgAAAA==.Drnewport:BAAANQADCggIEwAAAA==.Drystine:BAAANQAECgEIAQAAAA==.',
Dy='Dyronebiggum:BAAANQABCgMIAQAAAA==.',
['Dí']='Dín:BAAANQAECgQIBQAAAA==.',
Ec='Ectharienne:BAAANQABCgMIAwAAAA==.',
Eg='Eggs:BAAANQADCgEIAQAAAA==.',
Ei='Eillaura:BAAANQAECgYIEAAAAA==.',
El='Eleredra:BAAANQADCgYIBgABNQAECgQIBwAEAAAAAA==.Elipsis:BAABNQAECoEYAAIJAAkJIyE+BABjAwAJAAkJIyE+BABjAwAAAA==.Elm:BAAANQAECgEIAgAAAA==.Elycia:BAAANQAECgIIAgABNQAECgYIDAAEAAAAAA==.Elyenora:BAAANQAECgYIDAAAAA==.',
En='Enquea:BAAANQADCgEIAQABNQAECgEIAQAEAAAAAA==.Enricco:BAAANQADCggIFAAAAA==.',
Er='Ereko:BAAANQAECgIIBAAAAA==.Eriss:BAAANQAECgEIAwAAAA==.Erythorbic:BAAANQAECgIIBAAAAA==.',
Es='Estralage:BAAANQADCgUICwAAAA==.',
Ev='Evictor:BAAANQADCgIIAgABNQAECgMIAwAEAAAAAA==.',
Fa='Fanaticism:BAAANQADCgMIAwAAAA==.Fangs:BAAANQADCgEIAQABNQAECgYICgAEAAAAAA==.Faranth:BAAANQADCgYICQAAAA==.',
Fe='Feer:BAAANQADCgQICAAAAA==.Feldron:BAAANQAECgcIDgAAAA==.',
Ff='Ffugme:BAAANQAECgQIBwAAAA==.Ffugnutz:BAAANQADCgQIBAAAAA==.Ffugoff:BAAANQADCgYICgAAAA==.Ffugtard:BAAANQAECgMIBAAAAA==.Ffugyou:BAAANQADCgMIAwAAAA==.',
Fi='Finnian:BAAANQAECgUICgAAAA==.Fio:BAAANQAECgYICQAAAA==.',
Fl='Flowers:BAAANQAECgQIBQAAAA==.Fläva:BAAANQADCgMIAwAAAA==.',
Fo='Foot:BAAANQADCgQIBAAAAA==.Foxhound:BAAANQAECgQIBQAAAA==.',
Fr='Frostypie:BAAANQADCggIEAAAAA==.',
Fu='Furysbubble:BAAANQADCgQIBAAAAA==.',
['Fö']='Föx:BAAANQADCgYIBgAAAA==.',
Ga='Gaius:BAAANQADCgcIFgAAAA==.Gawdcomplex:BAAANQAECgUICwAAAA==.',
Ge='Gernaj:BAAANQADCgcICwAAAA==.',
Gh='Ghostfrudge:BAAANQADCggICAAAAA==.Ghostfudge:BAAANQAECgMIBQAAAA==.',
Gi='Ginny:BAAANQAECgEIAQAAAA==.Ginsan:BAAANQADCgEIAQAAAA==.Ginthalos:BAAANQADCgQIBAAAAA==.',
Go='Golaru:BAAANQABCgIIAgAAAA==.',
Gr='Greygor:BAAANQAECgIIBAAAAA==.Grotok:BAAANQADCggIDgABNQAECgMIAwAEAAAAAA==.',
Gu='Gumer:BAAANQAECgEIAQAAAA==.Guulen:BAAANQADCgIIAgAAAA==.',
Ha='Halontier:BAAANQADCgUIBwAAAA==.Hasklaufien:BAAANQADCgYICQAAAA==.',
Hi='Hinderberg:BAAANQAECgEIAQAAAA==.',
Ho='Horde:BAAANQADCgIIAgAAAA==.',
Hu='Huntsum:BAAANQAECgMIAwAAAA==.',
Ia='Iahsotgievhu:BAAANQADCgUIBQAAAA==.',
Ic='Icedsoul:BAAANQADCgIIAgAAAA==.',
Ig='Iggey:BAAANQAECgIIAgAAAA==.',
Il='Ilandras:BAAANQAECgQIBwAAAA==.Illadus:BAAANQAECgEIAQAAAA==.Illiviix:BAAANQADCgYIEgAAAA==.',
In='Indra:BAAANQAECgcIDQAAAA==.Intoxicated:BAAANQADCgcIGQAAAA==.',
Ir='Iranna:BAABNQAECoEYAAMKAAkJUyLGAgBkAwAKAAkJUyLGAgBkAwALAAEJoQrbOQA5AAAAAA==.',
It='Itsredbelow:BAAANQADCggIDAAAAA==.',
Iz='Izlaz:BAAANQADCggICAAAAA==.',
Ja='Jacrispy:BAAANQADCgYIBgAAAA==.Jaggedace:BAAANQAECgMIAwAAAA==.Janaki:BAAANQAECgMIAwAAAA==.',
Je='Jellyfish:BAAANQADCggIEAAAAA==.',
Ji='Jibbtotem:BAAANQADCgYIDQABNQAECgMIBAAEAAAAAA==.',
Jo='Joexotick:BAAANQABCgMIBQAAAA==.Jonnyquestt:BAAANQAECgYIDgAAAA==.',
Ju='Junrush:BAAANQAFFAIIAgAAAA==.Junshot:BAAANQAECgEIAQABNQAFFAIIAgAEAAAAAA==.',
Ka='Karaizula:BAAANQAECgQIBgAAAA==.Katsuko:BAAANQAECgMIAwAAAA==.Kattnirra:BAAANQAECgQIBAAAAA==.Katze:BAAANQAECgQIBwAAAA==.Kaylé:BAAANQADCgQIBQAAAA==.',
Ke='Keepper:BAAANQAECgEIAQAAAA==.Kenj:BAAANQAECgcIDQABNQAECgUICAAEAAAAAA==.Kenjurr:BAAANQAECgcIBwABNQAECgUICAAEAAAAAA==.Kenslynn:BAAANQAECgQIBgAAAA==.',
Ki='Kiannor:BAAANQAECgUICgAAAA==.Killahaseo:BAAANQAECgQICQAAAA==.Killmoedee:BAAANQAECgQIBwAAAA==.Kishibe:BAAANQAECgIIAgAAAA==.Kiss:BAAANQAECgYICgABNQAFFAYIDwAMAE8dAA==.',
Kl='Klexios:BAAANQADCgcIFwAAAA==.',
Ko='Koopa:BAAANQAECgUIBQAAAA==.',
Kr='Kraulhoof:BAAANQAECgEIAQAAAA==.Kronohs:BAAANQAECgEIAQAAAA==.',
Ku='Kui:BAAANQAECgQIBQAAAA==.Kuyna:BAAANQADCgYIDgAAAA==.',
['Kö']='Köz:BAAANQADCgQIBAAAAA==.',
La='Laetri:BAAANQAECgQIBAAAAA==.Lailiia:BAAANQAECgIIAgAAAA==.Lavendarlace:BAAANQADCgYIDAAAAA==.Lazloo:BAAANQAECgUIBgAAAA==.Lazymidget:BAAANQAECggIDwAAAA==.',
Le='Leftÿ:BAAANQAECgcIEgAAAA==.Lexibelle:BAAANQAECgIIAwAAAA==.',
Li='Lightace:BAAANQAECgQIBQAAAA==.Lightbunny:BAAANQAECggIDAAAAA==.Lincia:BAAANQAECgIIAgAAAA==.Linkkil:BAAANQADCgEIAQAAAA==.Liv:BAAANQADCgMIAwABNQAECgYIDQAEAAAAAA==.',
Lo='Loastotem:BAAANQADCgIIAgAAAA==.Lobos:BAAANQAECgQICQAAAA==.Lorvinion:BAAANQADCgYIBgAAAA==.Lostdraco:BAAANQAECgQICAAAAA==.Lostdream:BAAANQAECgUIBAAAAA==.Loun:BAAANQAECgEIAQAAAA==.',
Lu='Luiss:BAAANQAECgEIAgAAAA==.Luminism:BAAANQAECgIIBQABNQAECgEIAQAEAAAAAA==.Luvlycruelty:BAAANQAECgEIAQAAAA==.',
Ly='Lyn:BAEANQAECgYIDQAAAA==.',
['Lê']='Lêônà:BAAANQABCggICAAAAA==.',
Ma='Maazi:BAAANQADCgYIBgAAAA==.Mackenziiee:BAAANQAECgYICgAAAA==.Madglowup:BAAANQAECgMIAwAAAA==.Magicwater:BAAANQADCggICAABNQAECgIIBAAEAAAAAA==.Magtaki:BAAANQADCgEIAQAAAA==.Mainline:BAAANQAECgMIAwAAAA==.Maizepriest:BAAANQAECgQICQAAAA==.Maliaa:BAAANQADCgQIBQAAAA==.Malloryrose:BAAANQADCgcIBwAAAA==.Mandrison:BAAANQADCgQIBAAAAA==.Maxz:BAAANQADCgYIDAAAAA==.',
Me='Meerkat:BAAANQAECgQIBAAAAA==.Mellowblink:BAAANQAECgQIBgAAAA==.',
Mi='Migglet:BAAANQADCgUICAAAAA==.Mimi:BAACNQAFFIETAAMNAAcJ+yOsAABcAgANAAYJxyKsAABcAgABAAIJLyauBQDUAAA1AAQKgSMAAw0ACQltJoABALcDAA0ACQklJoABALcDAAEABgl7JroYALUCAAAA.Miramage:BAAANQADCgcIBwABNQAECgEIAQAEAAAAAA==.Miravus:BAAANQAECgEIAQAAAA==.Mitcheoff:BAAANQAECgIIAgAAAA==.',
Mo='Monkerick:BAAANQADCgQIBwAAAA==.',
Mu='Murkoobi:BAAANQADCgYIDAAAAA==.',
My='Mystáke:BAAANQAECgYIDQAAAA==.',
Na='Narbus:BAAANQAECgQIBwAAAA==.Naromancer:BAAANQAECgUIDAAAAA==.Nathadon:BAAANQAECgMIAwAAAA==.Nautrium:BAAANQADCgIIAgAAAA==.',
Ne='Nekhraros:BAAANQAECgYICgAAAA==.Nergál:BAAANQADCgYIBQABNQADCggICAAEAAAAAA==.Neyti:BAAANQADCgIIAgAAAA==.Neytvengy:BAAANQADCggIDQAAAA==.Nezukô:BAAANQADCgUICQAAAA==.',
Ni='Nikkisan:BAAANQADCgYIDgAAAA==.Nixk:BAAANQADCgMIAwAAAA==.',
No='Noixi:BAAANQADCgYIDwAAAA==.Noras:BAAANQAECgMIAwAAAA==.Nordicslayer:BAAANQADCgUICQAAAA==.Notagnoblin:BAEBNQAECoEcAAIOAAkJXSWgAQDKAwAOAAkJXSWgAQDKAwAAAA==.Notrick:BAAANQADCggIEAAAAA==.',
Nu='Nuffsaid:BAAANQADCgUIBgAAAA==.',
Ny='Nyko:BAAANQADCgMIAwAAAA==.',
Og='Ogrelurd:BAAANQAECgMIAwAAAA==.',
Op='Ophelia:BAAANQAECgQICQAAAA==.',
Or='Orakwa:BAAANQAECgIIAgAAAA==.',
Pa='Pachez:BAAANQAECgIIAgAAAA==.Paladont:BAAANQAECgEIAgAAAA==.Pallinda:BAAANQAECgUICAAAAA==.Palmogant:BAAANQAECgQIBgAAAA==.Pappyoblues:BAAANQAECgEIAgAAAA==.Patt:BAAANQADCgUIBQAAAA==.',
Pe='Pendulumlaw:BAABNQAECoEeAAIIAAkJRBgcKACoAgAIAAkJRBgcKACoAgAAAA==.Pepe:BAAANQADCgEIAQAAAA==.',
Ph='Phinn:BAAANQAECgIIBAAAAA==.Phoopanchu:BAAANQAECgEIAQAAAA==.',
Pi='Pimikoh:BAAANQADCgYICAAAAA==.Pinkbuns:BAAANQAECgEIAQAAAA==.',
Pn='Pneuma:BAAANQADCgcIEwAAAA==.',
Po='Pollonius:BAAANQADCgQIBAAAAA==.Popsy:BAAANQAECgQIBAAAAA==.',
Pr='Prenton:BAAANQAECgIIBAAAAA==.Prepotente:BAAANQAECgMIAwABNQAECgQIBgAEAAAAAA==.Prideflag:BAAANQADCggICAAAAA==.Priestin:BAAANQABCgQIAwAAAA==.',
Ps='Psyduck:BAAANQAECgIIAgABNQAFFAcIEwACAFYiAA==.',
Pu='Punie:BAAANQAECgIIAwAAAA==.Puzzykat:BAAANQADCgYIBgAAAA==.',
Qe='Qeini:BAAANQAECgQIBgAAAA==.',
Ra='Rafoff:BAAANQADCggIFgAAAA==.Ragnarax:BAAANQAECgMIAwAAAA==.Rancoramble:BAAANQAECgQICgAAAA==.Randis:BAAANQAECgIIBAAAAA==.Raysonna:BAAANQADCggIDQAAAA==.',
Re='Reticent:BAAANQADCgcIEwAAAA==.Reversewally:BAAANQAECgcIDwAAAA==.Rexiis:BAAANQAECgQIBwAAAA==.Reyth:BAAANQADCggIFQAAAA==.',
Rh='Rhuby:BAAANQAECgIIAgAAAA==.',
Ri='Rimos:BAAANQAECgEIAQAAAA==.Rivening:BAAANQADCggIFwAAAA==.',
Rk='Rk:BAAANQADCgYICAAAAA==.',
Ro='Rochelle:BAAANQADCggIFQAAAA==.Roeyth:BAAANQADCggICAAAAA==.Rokki:BAAANQAECgMIAwAAAA==.Roostor:BAAANQADCgYICwAAAA==.Roundhouse:BAAANQAECgQICQAAAA==.',
Ru='Rubbmytotems:BAAANQAECgQIBgAAAA==.Rubicôn:BAAANQABCgYICAABNQAECgkJHQAPANIgAA==.Rubmyoysters:BAAANQADCgEIAQAAAA==.Ruleti:BAAANQAECgQICwAAAA==.Rumí:BAAANQADCggIGgAAAA==.',
Sa='Sabado:BAAANQADCggIEwAAAA==.Safewerd:BAEANQAECgIIAgAAAA==.Saitama:BAAANQADCgYIEAABNQAECgcIDgAEAAAAAA==.Sangriel:BAAANQAECgMIAwAAAA==.Saraceleste:BAAANQADCgcIDAAAAA==.Saralanna:BAAANQAECgIIAwAAAA==.Sarefina:BAAANQAECgEIAQAAAA==.Sathenazarke:BAAANQAECgYIBgABNQAECgkJGAAKAFMiAA==.',
Sc='Schism:BAAANQADCgUICQAAAA==.',
Se='Seraphnite:BAAANQADCgIIAgAAAA==.Seriousjakk:BAAANQADCgEIAQABNQADCgQIBwAEAAAAAA==.',
Sh='Shadowtax:BAAANQABCgIIAgAAAA==.Shan:BAAANQAECgcIEwAAAA==.Shaohlin:BAAANQADCgUIBQAAAA==.Shavemybush:BAAANQADCgcIBwAAAA==.Shayy:BAAANQAECgUICwAAAA==.Shigure:BAAANQAECgQIBQAAAA==.Sholin:BAAANQADCggIFgAAAA==.Shomea:BAAANQADCgcIFwAAAA==.',
Si='Sikotick:BAAANQAECgEIAQAAAA==.Sikxrapture:BAAANQADCgYIBgAAAA==.Siliconista:BAABNQAECoEZAAMQAAkJzCLyAgB8AgAPAAkJsR0PHgAeAwAQAAcJEiXyAgB8AgAAAA==.',
Sk='Skitrit:BAAANQADCgQIBQABNQAECgQICwAEAAAAAA==.Skyjin:BAAANQADCgYICQAAAA==.',
Sl='Slammurai:BAAANQADCgUIBQAAAA==.Slippie:BAAANQABCgMIAQAAAA==.Slippinwater:BAAANQAECgIIBAAAAA==.Sllew:BAAANQAECgcIDwAAAA==.Slyyce:BAAANQADCggICAAAAA==.',
Sm='Smoulder:BAAANQADCgIIBAAAAA==.',
Sn='Snigles:BAAANQAECgMIAwAAAA==.Snowlily:BAAANQADCgUICgABNQAECgQIBwAEAAAAAA==.Snurp:BAAANQAECgQIBwABNQAECgYIBgAEAAAAAA==.',
So='Softnsquishy:BAAANQAECgEIAgAAAA==.Solmarrow:BAAANQAECgUICgAAAA==.',
Sp='Spartos:BAAANQAECgQIBgAAAA==.Speedy:BAAANQAECgIIAwAAAA==.Speedyspeed:BAAANQADCgQIBQAAAA==.Spokes:BAAANQADCgUIBQABNQAECgMIAwAEAAAAAA==.Sposi:BAEANQAECgQICQAAAA==.',
Sr='Srimrithyu:BAAANQADCgYIEwAAAA==.',
Ss='Sselionn:BAAANQAECgEIAQAAAA==.',
St='Stomps:BAAANQAECgEIAQAAAA==.Stonezef:BAAANQAECgMIAwAAAA==.',
Su='Suffocation:BAAANQADCgYIBwAAAA==.Sungdihhwoo:BAAANQADCgQIBwAAAA==.Susann:BAAANQAECgYIEQAAAA==.',
Sy='Syravia:BAAANQAECgQIBQAAAA==.',
['Sò']='Sòlushan:BAAANQAECgEIAQABNQAECggIDQAEAAAAAA==.',
Ta='Tahoa:BAAANQABCgQIBAAAAA==.Tameka:BAAANQAECgYICwAAAA==.Tardis:BAAANQAECgcIBgAAAA==.Tatersdh:BAEANQAECgQIBgABNQAECgkJHAAOAF0lAA==.Tavinrayn:BAAANQADCgQIBgAAAA==.',
Te='Tekesh:BAAANQADCggICgAAAA==.Teksham:BAAANQADCgYIEgAAAA==.Telarin:BAAANQAECgIIAgAAAA==.Tezrian:BAAANQADCgYICgABNQAECgQIBgAEAAAAAA==.',
Th='Thebigdawg:BAAANQADCgEIAQAAAA==.Theladyboy:BAAANQAECgQIBAAAAA==.Thomss:BAAANQAECgUICgAAAA==.Throhk:BAAANQADCgQIBAAAAA==.Thrumgar:BAAANQAECgEIAgAAAA==.',
Ti='Tigerliley:BAAANQAECgQIBAABNQAECgQIBwAEAAAAAA==.Tinneas:BAAANQADCgYICAAAAA==.',
To='Tomás:BAAANQAECgMIAwAAAA==.Torstai:BAAANQADCggIFwAAAA==.Totemic:BAAANQADCggIEgAAAA==.Toyun:BAAANQADCgMIAwAAAA==.',
Tr='Trap:BAAANQADCgQIBAAAAA==.Trueshöt:BAAANQAECgQIBAAAAA==.',
Ts='Tserendolgor:BAAANQADCgYICQABNQAECgQIBgAEAAAAAA==.',
Ty='Tyresious:BAAANQADCggICgAAAA==.',
['Tà']='Tàric:BAAANQADCgMIAwAAAA==.',
Ut='Utherrex:BAAANQADCgIIAgABNQAECgQIBwAEAAAAAA==.',
Va='Vahaghn:BAAANQAECgYIDAAAAA==.Valcerus:BAAANQADCgcIFwAAAA==.Valedus:BAAANQAECgUICwAAAA==.',
Ve='Veelete:BAAANQADCgQIBAABNQAECgcIEQAEAAAAAA==.Vengeancedh:BAAANQADCgYIFQAAAA==.Vespra:BAAANQADCgYIBgAAAA==.Veylara:BAAANQADCgIIAgAAAA==.',
Vi='Viix:BAAANQADCgIIAgAAAA==.Vinno:BAAANQADCgYIBwAAAA==.Virr:BAAANQAECgEIAQAAAA==.',
Vo='Volcker:BAAANQAECgIIBAAAAA==.Voltuk:BAAANQAECgQICQAAAA==.',
Wa='Wariius:BAAANQAECgIIAgAAAA==.Warwarb:BAAANQAECgEIAQABNQAECgYIDQAEAAAAAA==.Wasabijack:BAAANQADCgMIAwAAAA==.Waterliliy:BAAANQAECgQIBwAAAA==.Wayhn:BAAANQABCgYIBgAAAA==.',
Wi='Windfurypie:BAAANQADCggICQAAAA==.',
Wo='Wolfbish:BAAANQAECgIIAwAAAA==.',
['Wý']='Wýler:BAAANQADCgIIAgABNQADCggICAAEAAAAAA==.',
Xa='Xacious:BAAANQADCggIFwAAAA==.',
Xh='Xhuri:BAAANQADCgYIBgAAAA==.',
['Xë']='Xëna:BAAANQAECgQIBQAAAA==.',
Yo='Yorllik:BAAANQADCggIHQAAAA==.',
Yu='Yuzuha:BAAANQABCgIIAgAAAA==.',
Za='Zarulyn:BAAANQADCgYIBgAAAA==.',
Ze='Zendragon:BAAANQAECgQIBAABNQAECgQICQAEAAAAAA==.',
Zh='Zhorvan:BAAANQADCggIGQABNQAECgQIBQAEAAAAAA==.',
Zi='Zilstar:BAAANQADCggIDAAAAA==.',
['Âr']='Ârtëmïs:BAAANQAECgIIAwAAAA==.',
['Åp']='Åpollo:BAAANQAECgcIEAAAAA==.',
['Òm']='Òmgitsbwòng:BAAANQAECgMIBQAAAA==.',
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
