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

local lookup = {'Unknown-Unknown','Paladin-Retribution',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=53,date='2026-09-08',data={Ai='Ailira:BAAANQAECgYIBgAAAA==.',
Al='Alexzandrite:BAAANQADCggICAABNQADCggIDQABAAAAAA==.Alliethra:BAAANQADCgMIAwAAAA==.',
Am='Aminall:BAAANQADCgIIAgAAAA==.',
An='Anaboloholic:BAAANQABCgYICQAAAA==.Anauthaho:BAAANQADCgUIBQAAAA==.Andore:BAAANQADCgcIDwAAAA==.Angrybutch:BAAANQAECgYIDQAAAA==.Antoer:BAAANQADCggIFgAAAA==.',
Ap='Apocalÿpse:BAAANQABCgMIAwAAAA==.',
Ar='Arbor:BAAANQABCgUIBQAAAA==.',
As='Asonnari:BAAANQADCgUIBQAAAA==.',
At='Atreana:BAAANQAECgQIBQAAAA==.Attykus:BAAANQADCgYIDQAAAA==.',
Av='Avalerion:BAAANQAECgEIAgAAAA==.Avij:BAAANQADCgYIBgAAAA==.',
Ay='Ayrlyn:BAAANQADCgcIEAAAAA==.',
['Añ']='Añathema:BAAANQADCgQICgAAAA==.',
Ba='Baldd:BAAANQAECgEIAQAAAA==.Balthor:BAAANQAECgEIAQAAAA==.',
Be='Beechni:BAAANQADCgUIBQAAAA==.Belgarde:BAAANQADCgUIBQAAAA==.',
Bl='Blind:BAAANQAECgQIBQAAAA==.Bluwhale:BAAANQAECgIIAgAAAA==.',
Bo='Bormor:BAAANQADCgMIAwAAAA==.',
Br='Brainpath:BAAANQABCgEIAQAAAA==.Brasidias:BAAANQABCgMIAwAAAA==.Brumak:BAAANQADCgYICwAAAA==.Bruno:BAAANQAECgQIBgAAAA==.',
Bu='Budthespud:BAAANQADCgYICwAAAA==.Bunnynoodle:BAAANQADCgIIAgAAAA==.Burland:BAAANQAECgUIBQAAAA==.',
Bw='Bwonshogdi:BAAANQAECgYICQAAAA==.',
['Bá']='Báthory:BAAANQAECgEIAQAAAA==.',
Ca='Caladin:BAAANQAECgMIAwAAAA==.Callistos:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.Caris:BAAANQADCgMIAwAAAA==.Carnar:BAEANQAECgEIAQAAAA==.Castianna:BAAANQADCgYICQAAAA==.',
Ce='Century:BAAANQAECgIIAgAAAA==.',
Ch='Chewbaulk:BAAANQADCgEIAQAAAA==.Chubbysnackz:BAAANQADCggIEwAAAA==.Chug:BAAANQAECgIIAgAAAA==.',
Ci='Circa:BAAANQADCggIEwAAAA==.Cithrel:BAAANQAECgIIAgAAAA==.Cizin:BAAANQADCgcIBwAAAA==.',
Cl='Claylemian:BAAANQADCgQIBAAAAA==.Cloak:BAAANQAECgQIBAAAAA==.Cloudninelol:BAAANQADCgUIBQAAAA==.',
Co='Coriko:BAAANQAECgMIBgAAAA==.',
Cr='Crocklock:BAAANQADCgYICwAAAA==.',
Da='Dallia:BAAANQADCgYIDQAAAA==.Dalyrimple:BAAANQADCgQIBAAAAA==.Damnatio:BAAANQAECgMIBgAAAA==.Darkclement:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Darksworn:BAAANQADCgMIAQAAAA==.',
De='Deadchaos:BAAANQADCggICAAAAA==.Deathbybob:BAAANQADCgYIDQAAAA==.Deckard:BAAANQADCggIDgAAAA==.Deeper:BAAANQADCgYIBgAAAA==.Demonofwar:BAAANQADCgUIBgABNQAECgQIBQABAAAAAA==.Derese:BAAANQADCggICAAAAA==.Dezzii:BAAANQADCgYIDgAAAA==.',
Di='Divineblood:BAAANQADCgEIAQAAAA==.',
Dm='Dmaan:BAAANQAECgMIAwAAAA==.',
Do='Doomflower:BAAANQADCgYIDgAAAA==.',
Dr='Drekzin:BAAANQABCgMIAwAAAA==.Drhealalot:BAAANQADCgYICwAAAA==.Drugar:BAAANQAECgYICQABNQAECgcIBwABAAAAAA==.',
Du='Dumparooski:BAAANQADCgMIBQABNQADCggIFAABAAAAAA==.Durabull:BAAANQADCggIDwAAAA==.',
Ea='Earthvoodoo:BAAANQAECgIIAgAAAA==.',
Ed='Edrin:BAAANQABCgIIAgAAAA==.',
En='Ender:BAAANQADCggIFQAAAA==.',
Ep='Ephrael:BAAANQAECggICAAAAA==.',
Er='Ernietheorc:BAAANQAECgIIAwAAAA==.',
Eu='Eurytos:BAAANQADCgIIAgAAAA==.',
Ev='Evilissereni:BAAANQABCgIIAgAAAA==.',
Ez='Ezéé:BAAANQAECgEIAQAAAA==.',
Fa='Falsetto:BAAANQADCgEIAQAAAA==.Faramír:BAAANQADCgYIDgAAAA==.Farrago:BAAANQADCgYICwAAAA==.',
Fe='Fennek:BAAANQADCgUIAQAAAA==.',
Fi='Fists:BAAANQABCgYIBgAAAA==.',
Fr='Freetorylanz:BAAANQABCgUIBQAAAA==.',
Ga='Garaylo:BAABNQAECoEWAAICAAgJUiVxBgBbAwACAAgJUiVxBgBbAwAAAA==.',
Gh='Ghosst:BAAANQAECgYICwAAAA==.',
Gn='Gnobull:BAAANQADCggICAAAAA==.Gnudgnimish:BAAANQADCgYIDAABNQAECgQIBAABAAAAAA==.',
Go='Goldenknight:BAAANQADCgYICwAAAA==.',
Gr='Grimmel:BAAANQAECgEIAQAAAA==.Grimmrot:BAAANQADCgQIBAAAAA==.',
Gu='Guildan:BAAANQABCgYICQAAAA==.Guttris:BAAANQAECgQIBwAAAA==.',
Gw='Gwaineelock:BAAANQADCgMIBAAAAA==.',
Ha='Haikusen:BAAANQADCgMIAQABNQAECgQIBQABAAAAAA==.Hassan:BAAANQADCgMIBQAAAA==.',
He='Heisenberger:BAAANQABCgEIAQAAAA==.Heliòs:BAAANQADCgMIBAAAAA==.Hesseth:BAAANQADCggIDgAAAA==.',
Ho='Hoake:BAAANQADCgYICAAAAA==.Hogshock:BAAANQAECgEIAQAAAA==.Holyzel:BAAANQAECgEIAQAAAA==.',
Hs='Hsimingeung:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Hsimingjung:BAAANQAECgQIBAAAAA==.Hsimingkung:BAAANQADCgcICgABNQAECgQIBAABAAAAAA==.',
Hu='Huh:BAAANQADCgYIBgAAAA==.Humanic:BAAANQADCggIBgAAAA==.Huntari:BAAANQADCgEIAQAAAA==.',
Hy='Hylie:BAAANQAECgYICgAAAA==.',
['Hè']='Hèlla:BAAANQABCgQIBAAAAA==.',
Ic='Icolann:BAAANQAECgUIBQABNQAECgIIAgABAAAAAA==.',
Il='Illidarie:BAAANQADCgEIAQAAAA==.',
In='Invisibull:BAAANQADCgEIAQAAAA==.Inzi:BAAANQADCgQIBQAAAA==.',
Is='Isparian:BAAANQADCgYIDgAAAA==.Istabthings:BAAANQAECgcIBwAAAA==.',
Iv='Ivanyr:BAAANQAECgcIEQAAAA==.',
Ja='Jaime:BAAANQADCgUIBwABNQAECgQIBQABAAAAAA==.',
Je='Jenzö:BAAANQAECgUIBQAAAA==.Jesta:BAAANQADCgUICQAAAA==.',
Ji='Jikiniinki:BAAANQAECgEIAgAAAA==.',
Jo='Joeviben:BAAANQADCggIEQAAAA==.Johnnyretwar:BAAANQAECgIIAgAAAA==.',
Ju='Jugsy:BAAANQAECgcIDAAAAA==.',
Ka='Kaikai:BAAANQAECgcIDQAAAA==.Kaldread:BAAANQADCgUICgAAAA==.Kaligo:BAAANQAECgUICAAAAA==.Kastiron:BAAANQAECgEIAQAAAA==.Kazrime:BAAANQAECgIIAgAAAA==.',
Ke='Kebsy:BAAANQAECgQIBAAAAA==.Kelements:BAAANQADCgIIAgAAAA==.Kelyessada:BAAANQADCgYIBgAAAA==.Kenergy:BAAANQAECgQIBwAAAA==.Kerit:BAAANQABCgIIAgAAAA==.Kevonjuravis:BAAANQAECgEIBAAAAA==.',
Kh='Khalyl:BAAANQADCgQIDAAAAA==.',
Ki='Kiandra:BAAANQADCgMIAwAAAA==.Killpain:BAAANQADCgUIBgAAAA==.Kirå:BAAANQADCgUICAAAAA==.',
Ku='Kungpaochik:BAAANQADCggIFAAAAA==.',
Kz='Kzmo:BAAANQAECgEIAQAAAA==.',
Lo='Lousanis:BAAANQAECgIIBQAAAA==.',
Lu='Lucinick:BAAANQADCgcICgAAAA==.',
Ma='Mariskama:BAAANQADCgYICgAAAA==.Mazza:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Mh='Mhelora:BAAANQAECgEIAQAAAA==.',
Mi='Mikenolan:BAAANQADCgcIBwAAAA==.Mimacho:BAAANQAECgMIAwAAAA==.Mindmuncher:BAAANQAECgEIAQAAAA==.Minimini:BAAANQAECgQICQAAAA==.Minnow:BAAANQADCgYIBgAAAA==.',
Mo='Moolin:BAAANQADCggIFQAAAA==.',
Mu='Muggni:BAAANQADCggICQAAAA==.',
My='Mythuneran:BAAANQAECgMIBAAAAA==.',
Ne='Nemini:BAAANQADCgYIDQAAAA==.Nena:BAAANQADCgYIGQAAAA==.Newfy:BAAANQAECgQIBQAAAA==.',
Ni='Nightmoves:BAAANQADCgYIBgAAAA==.Nithendroz:BAAANQADCgYIDgAAAA==.Nity:BAAANQADCgYICQAAAA==.',
No='Noctaurus:BAAANQADCgQIBAAAAA==.Noraice:BAAANQABCgQIBwAAAA==.Notagain:BAABNQAECoEaAAICAAkJLiBoCgAYAwACAAkJLiBoCgAYAwAAAA==.',
Ny='Nyuxx:BAAANQADCgcICgAAAA==.',
Ob='Obake:BAAANQAECgQIBgAAAA==.',
Og='Ogsmallz:BAAANQADCgcICwAAAA==.',
Ol='Olenza:BAAANQADCgMIBAAAAA==.',
Or='Orangewhale:BAAANQAECgYIBgAAAA==.',
Ox='Oxidation:BAAANQADCgQIBAAAAA==.',
Oz='Ozsome:BAAANQADCggICAAAAA==.',
Pa='Pavo:BAAANQAECgMIAwAAAA==.',
Pe='Pebbleshifts:BAAANQADCgEIAQAAAA==.Peejean:BAAANQAECgEIAQAAAA==.Peycicle:BAAANQAECgMIBQAAAA==.',
Ph='Phantasm:BAAANQABCgIIAgAAAA==.Phlox:BAAANQADCggIEwAAAA==.',
Pi='Pippa:BAAANQADCggIEwAAAA==.',
Pl='Planett:BAAANQAECgIIAgAAAA==.',
Po='Poetuck:BAAANQAECgQIBAAAAA==.Pokeyruler:BAAANQADCgEIAQAAAA==.',
Pr='Proko:BAAANQADCggIEwAAAA==.',
Qa='Qatka:BAAANQADCgMIBAAAAA==.',
Qu='Quiver:BAAANQADCgQIBAAAAA==.',
Ra='Raein:BAAANQADCggIEgAAAA==.Rainn:BAAANQAECgQIBgAAAA==.Rainnsoul:BAAANQADCgEIAQAAAA==.Ralofurius:BAAANQADCgUICAABNQADCgYIBgABAAAAAA==.Rasril:BAAANQADCgIIAgAAAA==.',
Re='Redrighthand:BAAANQADCgMIAwAAAA==.Reshtargorr:BAAANQABCgEIAQAAAA==.',
Ro='Roskolnikov:BAAANQADCgQIDAAAAA==.Rossa:BAAANQADCgIIAgAAAA==.',
Ru='Ruele:BAAANQAECgIIAgAAAA==.Ruenan:BAAANQAECgUIBgAAAA==.',
Sa='Sanbas:BAAANQADCgYIDAAAAA==.Sarthrity:BAAANQADCgQIBAAAAA==.',
Sc='Scootsy:BAAANQAECgUIBwAAAA==.',
Se='Seirin:BAAANQADCggIEAAAAA==.Selendaa:BAAANQAECgMIAwAAAA==.Senadarra:BAAANQADCgYIBgAAAA==.Senastera:BAAANQADCgQIBwAAAA==.Sephandtotem:BAAANQADCgYIDQAAAA==.Sephron:BAAANQADCgYIDwAAAA==.Sethen:BAAANQAECgIIAgAAAA==.',
Sh='Shamalamadd:BAAANQAECgEIAQAAAA==.Shaollyn:BAAANQADCgYICQAAAA==.Shendralar:BAAANQAECgYICwAAAA==.Sheri:BAAANQAECgQIBAAAAA==.Shizam:BAAANQADCgYIBgAAAA==.Shlexie:BAAANQAECgMIAwAAAA==.Shockless:BAAANQADCgUIBQAAAA==.Shotowkhann:BAAANQADCggIEAAAAA==.',
Si='Sigmaboss:BAAANQADCgQIBAAAAA==.Silentpebble:BAAANQAECgUIBgAAAA==.Sillygoose:BAAANQAECgcIEwAAAA==.',
Sk='Skalar:BAAANQADCgcIFgAAAA==.Skodah:BAAANQADCgUIBwABNQAECgEIAQABAAAAAA==.',
Sp='Sprocket:BAAANQADCgIIAgABNQADCgUIAQABAAAAAA==.',
St='Stell:BAAANQADCggIFQAAAA==.Stinch:BAAANQADCgcIDAABNQADCggIFAABAAAAAA==.Stovik:BAAANQAECggIDwAAAA==.',
Sv='Sventhebrave:BAAANQADCgQICwAAAA==.',
Sw='Sweeneytod:BAAANQABCgMIAwAAAA==.',
Sy='Sykill:BAAANQADCgIIAgAAAA==.',
Ta='Tahuruk:BAAANQABCgQIBAAAAA==.Takamura:BAAANQADCgUIBQAAAA==.Talleral:BAAANQADCgUIBAAAAA==.Taurgrim:BAAANQADCgQIAwAAAA==.Tavin:BAAANQAECgQIBQAAAA==.',
Te='Temaman:BAAANQADCggIEgAAAA==.Temamañ:BAAANQADCgQIBAABNQADCggIEgABAAAAAA==.',
Ti='Timaeus:BAAANQAECgQIBAAAAA==.',
Tm='Tmbeesknees:BAAANQABCgQIBAAAAA==.',
To='Tokën:BAAANQADCgEIAQAAAA==.',
Tr='Trishi:BAAANQADCggIHgAAAA==.',
Tw='Twirlwind:BAAANQAECgIIAgAAAA==.',
Ty='Tydrinor:BAAANQADCgYIDQAAAA==.',
Un='Unoblasto:BAAANQAECgIIAQAAAA==.',
Va='Valorash:BAAANQAECgQIBgAAAA==.Valorious:BAAANQABCgUIBAAAAA==.Valshadow:BAAANQADCgcIBwABNQAECgQIBgABAAAAAA==.Vatahlia:BAAANQADCgUIBgAAAA==.',
Ve='Veleyna:BAAANQADCgUIDQAAAA==.Velintha:BAAANQADCggICAAAAA==.Ventise:BAAANQADCggIDQAAAA==.',
Vi='Vision:BAAANQADCgcIBwAAAA==.',
Vo='Voodoodog:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.',
Wa='Wargasm:BAAANQADCgIIAgAAAA==.Warrstomp:BAAANQADCgQIBAAAAA==.',
Wh='Whitewhale:BAAANQAECgYICAAAAA==.',
Xa='Xandaer:BAAANQADCgMIBAAAAA==.Xandaera:BAAANQABCgQIBAAAAA==.',
Xc='Xcïte:BAAANQAECgEIAwAAAA==.',
Yo='Yogeta:BAAANQADCgQIBAAAAA==.Yosh:BAAANQADCgIIAgAAAA==.',
Yu='Yuji:BAAANQAECgIIAgAAAA==.',
Za='Zamasû:BAAANQADCgMIAwAAAA==.',
Ze='Zelila:BAAANQADCgcIBwAAAA==.',
Zo='Zoras:BAAANQADCggICAAAAA==.',
['Ål']='Ålloria:BAAANQADCgMIAwAAAA==.',
['Ón']='Ónix:BAAANQADCgYICQAAAA==.',
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
