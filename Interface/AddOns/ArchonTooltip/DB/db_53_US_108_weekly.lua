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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Mage-Arcane','Mage-Frost','Shaman-Enhancement','Shaman-Restoration',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=53,date='2026-09-15',data={Ai='Ailira:BAAANQAECgYICAABNQAECgUICQABAAAAAA==.',
Al='Alexzandrite:BAAANQADCggICAABNQADCggIDQABAAAAAA==.Alliethra:BAAANQADCgUIBQAAAA==.',
Am='Aminall:BAAANQADCgIIAgAAAA==.',
An='Anaboloholic:BAAANQABCgYIDAAAAA==.Anauthaho:BAAANQADCgUIBQAAAA==.Andore:BAAANQADCggIFwAAAA==.Angrybutch:BAAANQAECgYIDQAAAA==.Antoer:BAAANQADCggIFgAAAA==.',
Ar='Arbor:BAAANQABCgUIBQAAAA==.Arthaz:BAAANQADCgEIAQAAAA==.',
As='Asonnari:BAAANQADCgUICgAAAA==.',
At='Atreana:BAAANQAECgUICgAAAA==.Attykus:BAAANQADCggIDwAAAA==.',
Av='Avalerion:BAAANQAECgUIBwAAAA==.Avij:BAAANQADCgYIBgAAAA==.',
Ay='Ayrlyn:BAAANQADCgcIEAAAAA==.',
['Añ']='Añathema:BAAANQADCgYIDAAAAA==.',
Ba='Baldd:BAAANQAECgEIAgAAAA==.Balthor:BAAANQAECgEIAQAAAA==.',
Be='Bearlyhealz:BAAANQAECgQIBAAAAA==.Beechni:BAAANQADCgUIBQAAAA==.Belgarde:BAAANQADCgUIBQAAAA==.',
Bi='Bigpoppapump:BAAANQADCggICAAAAA==.',
Bl='Blind:BAAANQAECgQIBQAAAA==.Bluwhale:BAAANQAECgIIAwAAAA==.',
Bo='Bormor:BAAANQADCgMIAwAAAA==.Bowdacious:BAAANQADCgUIBQAAAA==.',
Br='Brainpath:BAAANQABCgcICAAAAA==.Brickingkeys:BAAANQAECgYIBgAAAA==.Brumak:BAAANQADCgYICwAAAA==.Bruno:BAAANQAECgUICwAAAA==.',
Bu='Budthespud:BAAANQADCgYICwAAAA==.Bunnynoodle:BAAANQADCgIIAgAAAA==.Burland:BAAANQAECgUICQAAAA==.',
Bw='Bwonshogdi:BAAANQAECgYICQAAAA==.',
['Bá']='Báthory:BAAANQAECgEIAQAAAA==.',
Ca='Caladin:BAAANQAECgQIBgAAAA==.Callistos:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.Caris:BAAANQADCgMIAwAAAA==.Carnar:BAEANQAECgQIBQAAAA==.Castianna:BAAANQADCgYIDQAAAA==.',
Ce='Century:BAAANQAECgQIBgAAAA==.',
Ch='Chewbaulk:BAAANQADCgEIAQAAAA==.Chubbysnackz:BAAANQADCggIEwAAAA==.Chug:BAAANQAECgUIBwAAAA==.',
Ci='Circa:BAAANQAECgMIAwAAAA==.Cithrel:BAAANQAECgUIBwAAAA==.Cizin:BAAANQADCgcIBwAAAA==.',
Cl='Claylemian:BAAANQADCgQIBAAAAA==.Cloak:BAAANQAECgQIBAAAAA==.Cloudninelol:BAAANQADCgUIBQAAAA==.',
Co='Coriko:BAAANQAECgYIDAAAAA==.',
Cr='Crocklock:BAAANQAECgIIAgAAAA==.',
Cu='Cured:BAAANQADCgMIAwAAAA==.',
Da='Dallia:BAAANQADCgYIDQAAAA==.Dalyrimple:BAAANQADCgYICgAAAA==.Damnatio:BAAANQAECgcIDgAAAA==.Darkclement:BAAANQAECgQIBQAAAA==.Darksworn:BAAANQADCgMIAQAAAA==.',
De='Deadchaos:BAAANQADCggICAAAAA==.Deathbybob:BAAANQADCgYIEQAAAA==.Deckard:BAAANQADCggIFgAAAA==.Deeper:BAAANQAECgEIAQAAAA==.Demonofwar:BAAANQADCgUIBgABNQAECgQICQABAAAAAA==.Derese:BAAANQADCggICAAAAA==.Dethbringer:BAAANQABCgQIBAAAAA==.Dezzii:BAAANQADCgYIDgAAAA==.',
Di='Divineblood:BAAANQADCgEIAQAAAA==.',
Dm='Dmaan:BAAANQAECgYIBwAAAA==.',
Do='Doomflower:BAAANQADCgYIDgAAAA==.',
Dr='Drekzin:BAAANQABCgMIAwAAAA==.Drhealalot:BAAANQAECgEIAQAAAA==.Drugar:BAAANQAECgYICQABNQAFFAEIAQABAAAAAA==.',
Du='Dumparooski:BAAANQADCgQICQABNQADCggIGgABAAAAAA==.Durabull:BAAANQADCggIFQAAAA==.',
Ea='Earthvoodoo:BAAANQAECgIIAgAAAA==.',
Ed='Edrin:BAAANQABCgIIAgAAAA==.',
Ei='Eithelis:BAAANQADCgUIBQAAAA==.',
En='Ender:BAAANQAECgIIAgAAAA==.',
Ep='Ephrael:BAAANQAECggICAAAAA==.',
Er='Erniethemonk:BAAANQADCggICAAAAA==.Ernietheorc:BAAANQAECgUICAAAAA==.',
Eu='Eurytos:BAAANQAECgIIAgAAAA==.Euthanize:BAAANQADCggICAAAAA==.',
Ev='Evianda:BAAANQABCgQIBQAAAA==.Evilissereni:BAAANQABCgQIBAAAAA==.',
Ez='Ezéé:BAAANQAECgEIAgAAAA==.',
Fa='Falsetto:BAAANQADCgEIAQAAAA==.Faramír:BAAANQADCgYIDgAAAA==.Farrago:BAAANQADCgYIDAAAAA==.',
Fe='Fennek:BAAANQADCgUIAQAAAA==.Feorio:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Fi='Fists:BAAANQABCgYICQAAAA==.',
Fr='Freetorylanz:BAAANQABCgYICAAAAA==.',
Ga='Garaylo:BAABNQAECoEeAAICAAgJ/iWCBwCBAwACAAgJ/iWCBwCBAwAAAA==.',
Gh='Ghosst:BAAANQAECgcIEgAAAA==.',
Gn='Gnobull:BAAANQADCggICAAAAA==.Gnudgnimish:BAAANQADCgYIDAABNQAECgUICAABAAAAAA==.',
Go='Goldenknight:BAAANQADCggIDgAAAA==.',
Gr='Grimmel:BAAANQAECgMIAwAAAA==.Grimmrot:BAAANQADCgQIBAAAAA==.',
Gu='Guildan:BAAANQABCgcIEAAAAA==.Guttris:BAAANQAECgUICQAAAA==.',
Gw='Gwaineelock:BAAANQADCgQICAAAAA==.Gwyndolyn:BAAANQADCggICAAAAA==.',
Ha='Haikusen:BAAANQADCgMIAQABNQAECgQICQABAAAAAA==.Hassan:BAAANQADCgMIBQAAAA==.',
He='Heisenberger:BAAANQABCgEIAQAAAA==.Heliòs:BAAANQADCgMIBAAAAA==.Hesseth:BAAANQADCggIDwAAAA==.',
Ho='Hoake:BAAANQADCgYICAAAAA==.Hogshock:BAAANQAECgUIBgAAAA==.Holyzel:BAAANQAECgIIAgAAAA==.',
Hs='Hsimingeung:BAAANQADCgUIBQABNQAECgUICAABAAAAAA==.Hsimingjung:BAAANQAECgUICAAAAA==.Hsimingkung:BAAANQAECgIIAgABNQAECgUICAABAAAAAA==.',
Hu='Huh:BAAANQADCgYIBgAAAA==.Humanic:BAAANQADCggIDAAAAA==.Huntari:BAAANQADCgEIAQAAAA==.',
Hy='Hylie:BAAANQAECgcIDwAAAA==.',
['Hè']='Hèlla:BAAANQABCgQIBAAAAA==.',
Ic='Icolann:BAAANQAECgYICwABNQAECgIIAgABAAAAAA==.',
Il='Illidarie:BAAANQADCgEIAQAAAA==.',
Im='Imadragon:BAAANQADCgMIAwABNQADCggIGgABAAAAAA==.',
In='Invisibull:BAAANQADCgEIAQAAAA==.Inzi:BAAANQADCgQIBQAAAA==.',
Is='Isparian:BAAANQADCgYIDgAAAA==.Istabthings:BAAANQAFFAEIAQAAAA==.',
Iv='Ivanyr:BAABNQAECoEdAAIDAAkJKRtyBQDcAgADAAkJKRtyBQDcAgAAAA==.',
Ja='Jaime:BAAANQADCgUIBwABNQAECgQICQABAAAAAA==.',
Je='Jenzö:BAAANQAECgUIBQAAAA==.Jesta:BAAANQADCgYICgAAAA==.',
Ji='Jikiniinki:BAAANQAECgEIAgAAAA==.',
Jo='Joeviben:BAAANQADCggIEgAAAA==.Johnnyretwar:BAAANQAECgIIAwAAAA==.Jovian:BAAANQADCgQIBAAAAA==.',
Ju='Jugsy:BAAANQAECgcIEgAAAA==.',
Ka='Kaikai:BAAANQAECgcIDwAAAA==.Kaldread:BAAANQADCggIEgAAAA==.Kaligo:BAAANQAECgUIDQAAAA==.Kastiron:BAAANQAECgMIAwAAAA==.Kazrime:BAAANQAECgIIAgAAAA==.',
Ke='Kebsy:BAAANQAECgUICQAAAA==.Kelements:BAAANQADCgIIAgAAAA==.Kelyessada:BAAANQADCgYIBgAAAA==.Kenergy:BAAANQAECgYICQAAAA==.Kerit:BAAANQABCgIIAgAAAA==.Kevonjuravis:BAAANQAECgEIBQAAAA==.',
Kh='Khalyl:BAAANQADCgYIEgAAAA==.',
Ki='Kiandra:BAAANQADCgUICAAAAA==.Killpain:BAAANQADCgcIDQAAAA==.Kirå:BAAANQADCgYIDgAAAA==.',
Kr='Krytus:BAAANQADCgEIAQAAAA==.',
Ku='Kungpaochik:BAAANQADCggIGgAAAA==.',
Kz='Kzmo:BAAANQAECgEIAgAAAA==.',
Lo='Lousanis:BAAANQAECgIIBQAAAA==.',
Lu='Lucinick:BAAANQAECgEIAQAAAA==.Lupercal:BAAANQAECggIBwAAAA==.',
Ma='Madmartegan:BAAANQABCgMIAwAAAA==.Mariskama:BAAANQADCgYIEAAAAA==.Mazza:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Mh='Mhelora:BAAANQAECgEIAgAAAA==.',
Mi='Mikenolan:BAAANQADCgcIBwAAAA==.Mimacho:BAAANQAECgMIAwAAAA==.Mindmuncher:BAAANQAECgIIAwAAAA==.Minimini:BAAANQAECgQIDgAAAA==.Minnow:BAAANQADCgYIBgAAAA==.',
Mo='Moolin:BAAANQAECgMIAwAAAA==.',
Mu='Muggni:BAAANQADCggICQAAAA==.',
My='Mythuneran:BAAANQAECgQICAAAAA==.',
Ne='Nemini:BAAANQADCgYIEwAAAA==.Nena:BAAANQADCggIIgAAAA==.Newfy:BAAANQAECgYICQAAAA==.',
Ni='Nightmoves:BAAANQADCgYIBgAAAA==.Nithendroz:BAAANQADCggIFgAAAA==.Nity:BAAANQADCgYICQAAAA==.',
No='Noctaurus:BAAANQADCgQIBAAAAA==.Nogini:BAAANQADCgcIBwAAAA==.Noraice:BAAANQABCgQIBwAAAA==.Notagain:BAACNQAFFIEIAAICAAUJWws1AgCOAQACAAUJWws1AgCOAQA1AAQKgRwAAgIACQmUIMoWAOoCAAIACQmUIMoWAOoCAAAA.',
Ny='Nyuxx:BAAANQAECgEIAQAAAA==.',
Ob='Obake:BAAANQAECgQIBgAAAA==.',
Od='Odphijor:BAAANQAECggICAAAAA==.',
Og='Ogsmallz:BAAANQADCgcICwAAAA==.',
Ol='Olenza:BAAANQADCgQICAAAAA==.',
Or='Orangewhale:BAAANQAECgcIDAAAAA==.',
Ox='Oxidation:BAAANQADCgQIBQAAAA==.',
Oz='Ozsome:BAAANQAECgMIAwAAAA==.',
Pa='Pavo:BAAANQAECgQIBgAAAA==.',
Pe='Pebbleshifts:BAAANQADCgcICAAAAA==.Peejean:BAAANQAECgEIAQAAAA==.Pey:BAAANQADCggICAABNQAECgYICwABAAAAAA==.Peycicle:BAAANQAECgYICwAAAA==.',
Ph='Phantasm:BAAANQABCgIIAgAAAA==.Phlox:BAAANQAECgMIAwAAAA==.',
Pi='Pippa:BAAANQAECgMIAwAAAA==.',
Pl='Planett:BAAANQAECgQIBgAAAA==.',
Po='Poetuck:BAAANQAECgUICQAAAA==.Pokeyruler:BAAANQADCgEIAQAAAA==.',
Pr='Proko:BAAANQAECgMIAwAAAA==.',
Qa='Qatka:BAAANQADCgQICAAAAA==.',
Qu='Quiver:BAAANQAECgEIAQAAAA==.Quizmagic:BAAANQADCgMIAwAAAA==.',
Ra='Raein:BAAANQAECgIIAgAAAA==.Rainn:BAAANQAECgQICgAAAA==.Rainnsoul:BAAANQADCgEIAQAAAA==.Ralofurius:BAAANQADCgUIDAABNQADCgYIBgABAAAAAA==.Rasril:BAAANQADCgIIAgAAAA==.',
Re='Redrighthand:BAAANQADCgMIAwAAAA==.Relwind:BAAANQADCgQIBAAAAA==.Reshtargorr:BAAANQABCgEIAQAAAA==.',
Ro='Roskolnikov:BAAANQADCggIFAAAAA==.Rossa:BAAANQADCgIIAgAAAA==.',
Ru='Ruele:BAAANQAECgIIAgAAAA==.Ruenan:BAAANQAECgUICwAAAA==.',
Sa='Sanbas:BAAANQADCgYIDAAAAA==.Sapthat:BAAANQADCggICAAAAA==.Sarthrity:BAAANQADCggIDAAAAA==.Satyrs:BAAANQADCgIIAgAAAA==.',
Sc='Scootsy:BAAANQAECgUIBwAAAA==.',
Se='Seirin:BAAANQAECgIIAgAAAA==.Seldiane:BAAANQADCgQIBAAAAA==.Selendaa:BAAANQAECgMIBAAAAA==.Senadarra:BAAANQADCgYIBgAAAA==.Senastera:BAAANQADCgUIDAAAAA==.Sephandtotem:BAAANQADCggIDwAAAA==.Sephron:BAAANQADCggIFwAAAA==.Sethen:BAAANQAECgUIBwAAAA==.',
Sh='Shamalamadd:BAAANQAECgQIBQAAAA==.Shammology:BAAANQAECgYIBgAAAA==.Shaollyn:BAAANQADCgYICQAAAA==.Shendralar:BAAANQAECgYICwAAAA==.Sheri:BAAANQAECgQIBwAAAA==.Shizam:BAAANQADCgYIBgAAAA==.Shlexie:BAAANQAECgUICAAAAA==.Shockless:BAAANQAECgUIBQAAAA==.Shotowkhann:BAAANQAECgQIBQAAAA==.',
Si='Sigmaboss:BAAANQADCgQIBAAAAA==.Silentpebble:BAAANQAECgYIDAAAAA==.Sillygoose:BAABNQAECoEdAAMEAAkJpRlzOgCnAgAEAAkJ3BhzOgCnAgAFAAIJuBeTFgCaAAAAAA==.',
Sk='Skalar:BAAANQADCgcIHQAAAA==.Skodah:BAAANQADCgUIBwABNQAECgEIAQABAAAAAA==.',
So='Somnambula:BAAANQADCgUIBQAAAA==.',
Sp='Sprocket:BAAANQADCgIIAgABNQADCgUIAQABAAAAAA==.',
Sq='Squarey:BAAANQADCgIIAgAAAA==.',
St='Stell:BAAANQADCggIHQAAAA==.Stinch:BAAANQADCgcIDAABNQADCggIGgABAAAAAA==.Stovik:BAABNQAECoEXAAMGAAkJnx2xAwAPAwAGAAkJnx2xAwAPAwAHAAIJBBSemwBxAAAAAA==.',
Sv='Sventhebrave:BAAANQADCggIEwAAAA==.',
Sw='Sweeneytod:BAAANQABCgMIAwAAAA==.',
Sy='Sykill:BAAANQADCgIIAgAAAA==.',
Ta='Tahuruk:BAAANQABCgQIBAAAAA==.Takamura:BAAANQADCgUIBQAAAA==.Talena:BAAANQAECgIIAgAAAA==.Talleral:BAAANQAECgQIBQAAAA==.Taurgrim:BAAANQADCgQIAwAAAA==.Tavin:BAAANQAECgUICgAAAA==.',
Te='Temaman:BAAANQADCggIEgAAAA==.Temamañ:BAAANQADCgQIBAABNQADCggIEgABAAAAAA==.Terasha:BAAANQAECgYIBgAAAA==.',
Th='Thealtman:BAAANQADCgUIBQAAAA==.',
Ti='Timaeus:BAAANQAECgQICAAAAA==.',
Tm='Tmbeesknees:BAAANQABCgQIBAAAAA==.',
To='Tokën:BAAANQADCgEIAQAAAA==.',
Tr='Trishi:BAAANQADCggILQAAAA==.',
Tw='Twirlwind:BAAANQAECgUIBwAAAA==.',
Ty='Tydrinor:BAAANQADCggIFAAAAA==.',
Un='Unoblasto:BAAANQAECgQIBwAAAA==.',
Va='Valorash:BAAANQAECgUICwAAAA==.Valorious:BAAANQADCgEIAQAAAA==.Valshadow:BAAANQADCgcIBwABNQAECgUICwABAAAAAA==.Vatahlia:BAAANQADCgUIBgAAAA==.',
Ve='Veleyna:BAAANQADCgUIDQAAAA==.Velintha:BAAANQAECgMIAgAAAA==.Ventise:BAAANQADCggIDQAAAA==.',
Vi='Violee:BAAANQADCgQIBAAAAA==.Vision:BAAANQADCgcIBwAAAA==.',
Vo='Voodoodog:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.',
Wa='Wargasm:BAAANQADCgIIAgAAAA==.Warrstomp:BAAANQADCgQIBAAAAA==.',
Wh='Whitewhale:BAAANQAECgYICAAAAA==.',
Xa='Xandaer:BAAANQADCgMIBAAAAA==.Xandaera:BAAANQABCgcICQAAAA==.',
Xc='Xcïte:BAAANQAECgEIAwAAAA==.',
Yo='Yogeta:BAAANQADCgQIBAAAAA==.Yosh:BAAANQADCgIIAgAAAA==.',
Yu='Yuji:BAAANQAECgQIBgAAAA==.',
Za='Zalectra:BAAANQAECgUIBQAAAA==.Zamasû:BAAANQADCgMIAwAAAA==.Zarnie:BAAANQABCgEIAQAAAA==.',
Ze='Zelila:BAAANQADCgcIDAAAAA==.',
Zo='Zoras:BAAANQADCggICAAAAA==.',
['Ål']='Ålloria:BAAANQADCgcICQAAAA==.',
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
