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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Rogue-Subtlety','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Paladin-Protection','Mage-Arcane','Mage-Frost','Shaman-Enhancement','Shaman-Restoration',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=53,date='2026-09-22',data={Ai='Ailira:BAAANQAECgYICAABNQAECgUJCQABAAAAAA==.',
Al='Alexzandrite:BAAANQADCggICAABNQADCggIDQABAAAAAA==.Alliethra:BAAANQADCgUIBQAAAA==.',
Am='Amaryllis:BAAANQADCgMJAwAAAA==.Aminall:BAAANQADCgIIAgAAAA==.',
An='Anaboloholic:BAAANQABCgYIDAAAAA==.Anauthaho:BAAANQADCgUIBQAAAA==.Andore:BAAANQAECgEJAQAAAA==.Angrybutch:BAAANQAECgYIDQAAAA==.Angrymurloc:BAAANQADCgUIBQAAAA==.Antoer:BAAANQAECgYJBgAAAA==.',
Ar='Arbor:BAAANQABCgUIBQAAAA==.Arthaz:BAAANQADCgEIAQAAAA==.',
As='Asonnari:BAAANQADCgUJCgAAAA==.',
At='Atreana:BAAANQAECgYIEAAAAA==.Attykus:BAAANQAECgEJAQAAAA==.',
Av='Avalerion:BAAANQAECgUICAAAAA==.Avij:BAAANQADCgYIBgAAAA==.',
Ay='Ayrlyn:BAAANQADCgcIEAAAAA==.',
['Añ']='Añathema:BAAANQAECgEJAQAAAA==.',
Ba='Baldd:BAAANQAECgYICQAAAA==.Balthor:BAAANQAECgUIBgAAAA==.',
Be='Bearlyhealz:BAAANQAECgUICQAAAA==.Beechni:BAAANQAECgYJBgAAAA==.Belgarde:BAAANQADCgUIBQAAAA==.',
Bi='Bigpoppapump:BAAANQADCggICAAAAA==.Biological:BAAANQAECgEJAQAAAA==.',
Bl='Blind:BAAANQAECgQIBQAAAA==.Bluwhale:BAAANQAECgUICAAAAA==.',
Bo='Bormor:BAAANQADCgMIAwAAAA==.Bosambosia:BAAANQADCgQJBwABNQADCgYIBgABAAAAAA==.Bowdacious:BAAANQADCgUJBgAAAA==.',
Br='Brainpath:BAAANQABCgcICAAAAA==.Brickingkeys:BAAANQAECgYJCwAAAA==.Brumak:BAAANQADCgYJCwAAAA==.Bruno:BAAANQAECgcIEgAAAA==.',
Bu='Budthespud:BAAANQADCgYICwAAAA==.Bunnynoodle:BAAANQADCgIIAgAAAA==.Burland:BAAANQAECgcJEAAAAA==.',
Bw='Bwonshogdi:BAAANQAECgYICQAAAA==.',
['Bá']='Báthory:BAAANQAECgEIAQAAAA==.',
Ca='Caladin:BAAANQAECgYJDAAAAA==.Calemental:BAAANQADCgIJAQABNQAECgYJDAABAAAAAA==.Callistos:BAAANQADCgUJBgABNQAECgYJDAABAAAAAA==.Caris:BAAANQADCgMIAwAAAA==.Carnar:BAEANQAECgQIBQABNQAECgUIBQABAAAAAA==.Castianna:BAAANQADCgYJDQAAAA==.',
Ce='Century:BAAANQAECgQJCgAAAA==.',
Ch='Chewbaulk:BAAANQADCgEIAQAAAA==.Chubbysnackz:BAAANQADCggIEwAAAA==.Chug:BAAANQAECgYJDQAAAA==.',
Ci='Circa:BAAANQAECgQJBwAAAA==.Cithrel:BAAANQAECgUJCQAAAA==.Cizin:BAAANQADCgcIBwAAAA==.',
Cl='Claylemian:BAAANQADCgQIBAAAAA==.Cloak:BAAANQAECgQIBAAAAA==.Cloudninelol:BAAANQADCgUIBQAAAA==.',
Co='Coriko:BAAANQAECgcJEwAAAA==.',
Cr='Crocklock:BAAANQAECgIJBAAAAA==.',
Cu='Cured:BAAANQADCgMJAwAAAA==.',
Da='Dallia:BAAANQADCgYJEwAAAA==.Dalyrimple:BAAANQADCgYJEAAAAA==.Damnatio:BAABNQAECoEVAAICAAcKAx/qMgCLAgACAAcKAx/qMgCLAgAAAA==.Darkclement:BAAANQAECgUICgAAAA==.Darksworn:BAAANQADCgMIAQAAAA==.',
De='Deadchaos:BAAANQADCggICAAAAA==.Deathbybob:BAAANQADCggJGQAAAA==.Deckard:BAAANQAECgQIBAAAAA==.Deeper:BAAANQAECgEJAQAAAA==.Demonofwar:BAAANQADCgUIBgABNQAECgYIDwABAAAAAA==.Derese:BAAANQADCggICAAAAA==.Detroll:BAAANQADCgMJAwAAAA==.Dezzii:BAAANQADCgYIDgAAAA==.',
Di='Divineblood:BAAANQAECgIJAgAAAA==.',
Dm='Dmaan:BAAANQAECgcJDgAAAA==.',
Do='Doomflower:BAAANQADCgYIDgAAAA==.',
Dr='Drekzin:BAAANQABCgMIAwAAAA==.Drhealalot:BAAANQAECgEIAQAAAA==.Drugar:BAAANQAECgYICQABNQAECggIFwADANMhAA==.',
Du='Dumparooski:BAAANQADCgQJCQABNQAECgEIAQABAAAAAA==.Durabull:BAAANQADCggJGwAAAA==.',
Ea='Earthvoodoo:BAAANQAECgIIAgAAAA==.',
Ed='Edrin:BAAANQABCgIIAgAAAA==.',
Ei='Eithelis:BAAANQADCgUIBQAAAA==.',
El='Eladar:BAAANQADCggICAAAAA==.',
En='Ender:BAAANQAECgUIBwAAAA==.',
Ep='Ephrael:BAAANQAECggICAAAAA==.',
Er='Erniethemonk:BAAANQAECgQIAwAAAA==.Ernietheorc:BAAANQAECgUICAAAAA==.',
Eu='Eurytos:BAAANQAECgQJBgAAAA==.Euthanize:BAAANQAECgEJAQAAAA==.',
Ev='Evianda:BAAANQADCgUIBQAAAA==.Evilissereni:BAAANQABCgQJBAAAAA==.',
Ez='Ezéé:BAAANQAECgEIAgAAAA==.',
Fa='Falsetto:BAAANQADCgEIAQAAAA==.Faramír:BAAANQADCgYJDgAAAA==.Farrago:BAAANQADCgYIDQAAAA==.',
Fe='Fennek:BAAANQADCgUJAQAAAA==.Feorio:BAAANQAECgQJBAABNQAECgQJBQABAAAAAA==.',
Fi='Fists:BAAANQABCgYICQAAAA==.',
Fm='Fmzmage:BAAANQABCggIEAAAAA==.',
Ga='Garaylo:BAACNQAFFIEJAAICAAUKXhxlAgDZAQACAAUKXhxlAgDZAQA1AAQKgSEAAgIACAohJjQLAHwDAAIACAohJjQLAHwDAAAA.',
Gh='Ghorianha:BAAANQADCgQJBAAAAA==.Ghosst:BAABNQAECoEcAAMEAAgKhyLhDwAkAwAEAAgKhyLhDwAkAwAFAAQK8Qr/PADDAAAAAA==.',
Gn='Gnobull:BAAANQADCggICAAAAA==.Gnudgnimish:BAAANQADCgYIDAABNQAECgcJDwABAAAAAA==.',
Go='Goldenknight:BAAANQADCggIDgAAAA==.',
Gr='Grimmel:BAAANQAECgMIAwAAAA==.Grimmrot:BAAANQADCgQIBAAAAA==.',
Gu='Guildan:BAAANQABCgcIEAAAAA==.Guttris:BAAANQAECgUICQAAAA==.',
Gw='Gwaineelock:BAAANQADCgUJCAAAAA==.Gwyndolyn:BAAANQAECgEJAQAAAA==.',
Ha='Haikusen:BAAANQADCgMJBAABNQAECgYIDwABAAAAAA==.Hassan:BAAANQADCgMIBQAAAA==.',
He='Heisenberger:BAAANQABCgEIAQAAAA==.Heliòs:BAAANQADCgMIBAAAAA==.Hesseth:BAAANQADCggIDwAAAA==.',
Ho='Hoake:BAAANQADCgYICAAAAA==.Hogshock:BAAANQAECgcIDQAAAA==.Holyzel:BAAANQAECgYJCAAAAA==.',
Hs='Hsimingeung:BAAANQADCgUIBQABNQAECgcJDwABAAAAAA==.Hsimingjung:BAAANQAECgcJDwAAAA==.Hsimingkung:BAAANQAECgIIAgABNQAECgcJDwABAAAAAA==.',
Hu='Huaka:BAAANQADCggICAAAAA==.Huh:BAAANQADCgYIBgAAAA==.Humanic:BAAANQADCggIDAAAAA==.Huntari:BAAANQADCgEIAQAAAA==.',
Hy='Hylie:BAABNQAECoEZAAIGAAgKoRPXQQAWAgAGAAgKoRPXQQAWAgAAAA==.',
['Hè']='Hèlla:BAAANQABCgQIBAAAAA==.',
Ic='Icolann:BAAANQAECgcJEgABNQAECgIIAgABAAAAAA==.',
Il='Illidarie:BAAANQADCgEIAQAAAA==.',
Im='Imadragon:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
In='Invisibull:BAAANQADCgEIAQAAAA==.Inzi:BAAANQADCgQIBQAAAA==.',
Is='Isparian:BAAANQADCgYIDgAAAA==.Istabthings:BAABNQAECoEXAAIDAAgK0yGBBQATAwADAAgK0yGBBQATAwAAAA==.',
Iv='Ivanyr:BAABNQAECoEhAAIHAAkKkxw7BwDdAgAHAAkKkxw7BwDdAgAAAA==.Ivy:BAAANQABCgIJAgAAAA==.',
Ja='Jadebug:BAAANQADCgUJBwAAAA==.Jaime:BAAANQADCgUIBwABNQAECgYIDwABAAAAAA==.',
Je='Jenzö:BAAANQAECgUJBQAAAA==.Jesta:BAAANQADCgYJDgAAAA==.',
Ji='Jikiniinki:BAAANQAECgEIAgAAAA==.',
Jo='Joeviben:BAAANQADCggIGQAAAA==.Johnnyretwar:BAAANQAECgIJBAAAAA==.Jovian:BAAANQADCgUJCQAAAA==.',
Ju='Jugsy:BAABNQAECoEbAAIIAAgKIB2lOwDZAgAIAAgKIB2lOwDZAgAAAA==.',
Ka='Kaikai:BAAANQAECgcIEAAAAA==.Kaldread:BAAANQAECgEJAQAAAA==.Kaligo:BAAANQAECgcJEQAAAA==.Kastiron:BAAANQAECgUJBgAAAA==.Kazrime:BAAANQAECgIIAgAAAA==.',
Ke='Kebsy:BAAANQAECgUIDgAAAA==.Kelaia:BAAANQADCgYJBgAAAA==.Kelements:BAAANQADCgIIAgAAAA==.Kelyessada:BAAANQADCgYIBgAAAA==.Kenergy:BAAANQAECgcJEAAAAA==.Kerit:BAAANQABCgIIAgAAAA==.Kevonjuravis:BAAANQAECgMICAAAAA==.',
Kh='Khalyl:BAAANQAECgEJAQAAAA==.',
Ki='Kiandra:BAAANQADCgUIDQAAAA==.Killpain:BAAANQAECgUICAAAAA==.Kirå:BAAANQADCgYIDgAAAA==.',
Kr='Krytus:BAAANQADCgIJAgAAAA==.',
Ku='Kungpaochik:BAAANQADCggIGgABNQAECgEIAQABAAAAAA==.',
Ky='Kyarax:BAAANQADCggICQAAAA==.',
Kz='Kzmo:BAAANQAECgEIAgAAAA==.',
Lo='Lousanis:BAAANQAECgQJCQAAAA==.',
Lu='Lucinick:BAAANQAECgIIAwAAAA==.Lupercal:BAAANQAECggJBwAAAA==.',
Ma='Madmartegan:BAAANQABCgMIAwAAAA==.Mariskama:BAAANQADCgYJFgAAAA==.Maybecolin:BAAANQADCgEJAQAAAA==.Mazza:BAAANQADCggJDQABNQAECgcICQABAAAAAA==.',
Mh='Mhelora:BAAANQAECgQIBgAAAA==.',
Mi='Mikenolan:BAAANQADCgcIBwAAAA==.Mimacho:BAAANQAECgMJAwAAAA==.Mindmuncher:BAAANQAECgQIBwAAAA==.Minimini:BAAANQAECgQJEgAAAA==.Minnow:BAAANQADCgYIBgAAAA==.',
Mo='Moolin:BAAANQAECgMIAwAAAA==.',
Mu='Munder:BAAANQAECgEJAQAAAA==.Murph:BAAANQADCgcJBwAAAA==.',
My='Mythuneran:BAAANQAECgUIDQAAAA==.',
Na='Naheka:BAAANQADCggICAAAAA==.',
Ne='Nemini:BAAANQADCggJGwAAAA==.Nena:BAAANQAECgEIAgAAAA==.Nenacurses:BAAANQADCgYJBgABNQAECgEIAgABAAAAAA==.Newfy:BAAANQAECgYICQAAAA==.',
Ni='Nightmoves:BAAANQADCgYIBgAAAA==.Nithendroz:BAAANQAECgIJAgAAAA==.Nity:BAAANQAECgEJAQAAAA==.',
No='Noctaurus:BAAANQADCgQJBAAAAA==.Nogini:BAAANQADCgcJBwAAAA==.Nomadhew:BAAANQAECggJCAAAAA==.Noraice:BAAANQABCgQIBwAAAA==.Notagain:BAACNQAFFIEMAAICAAUKyA1PBACIAQACAAUKyA1PBACIAQA1AAQKgR4AAgIACQp5IrkfAO0CAAIACQp5IrkfAO0CAAAA.',
Ny='Nyuxx:BAAANQAECgEIAQAAAA==.',
Ob='Obake:BAAANQAECgQIBgAAAA==.',
Od='Odphijor:BAAANQAECggJCAAAAA==.',
Og='Ogsmallz:BAAANQADCgcICwAAAA==.',
Ol='Olenza:BAAANQADCgUJCAAAAA==.',
Or='Orangewhale:BAAANQAFFAEIAQAAAA==.',
Ox='Oxidation:BAAANQADCgQIBQAAAA==.',
Oz='Ozsome:BAAANQAECgUJCAAAAA==.',
Pa='Pavo:BAAANQAECgYIDAAAAA==.',
Pe='Pebbleshifts:BAAANQADCgcICAAAAA==.Peejean:BAAANQAECgEIAQAAAA==.Pey:BAAANQADCggJEAABNQAECgcIEgABAAAAAA==.Peycicle:BAAANQAECgcIEgAAAA==.Peystruction:BAAANQADCgYJBgABNQAECgcIEgABAAAAAA==.',
Ph='Phantasm:BAAANQABCgIIAgAAAA==.Phlox:BAAANQAECgQJBwAAAA==.',
Pi='Pippa:BAAANQAECgQJBwAAAA==.',
Pl='Planett:BAAANQAECgUJCwAAAA==.',
Po='Poetuck:BAAANQAECgYICgAAAA==.Pokeyruler:BAAANQADCgEIAQAAAA==.',
Pr='Proko:BAAANQAECgQJBwAAAA==.',
Qa='Qatka:BAAANQADCgUJCAAAAA==.',
Qu='Quiver:BAAANQAECgEIAQAAAA==.Quizmagic:BAAANQADCgMJAwAAAA==.',
Ra='Raein:BAAANQAECgQJBgAAAA==.Rainn:BAAANQAECgQICgAAAA==.Rainnsoul:BAAANQADCgEIAQAAAA==.Ralofurius:BAAANQADCgUJDAABNQADCgYIBgABAAAAAA==.Rasril:BAAANQADCgIIAgAAAA==.',
Re='Redrighthand:BAAANQADCgMIAwAAAA==.Relwind:BAAANQADCgQIBAAAAA==.Reshtargorr:BAAANQABCgEIAQAAAA==.',
Ro='Roskolnikov:BAAANQAECgEJAQAAAA==.Rossa:BAAANQADCgIIAgAAAA==.',
Ru='Ruele:BAAANQAECgIIAgAAAA==.Ruenan:BAAANQAECgYIEQAAAA==.',
Sa='Sanbas:BAAANQADCgYIEgAAAA==.Sapthat:BAAANQADCggJDgAAAA==.Sarthrity:BAAANQADCggIDgAAAA==.Satyrs:BAAANQADCgIIAgAAAA==.',
Sc='Scootsy:BAAANQAECgUIBwAAAA==.',
Se='Seirin:BAAANQAECgQJBgAAAA==.Seldiane:BAAANQADCggJDAAAAA==.Selendaa:BAAANQAECgQIBgAAAA==.Senadarra:BAAANQADCgYIBgAAAA==.Senastera:BAAANQADCgUIDAAAAA==.Sephandtotem:BAAANQAECgEJAQAAAA==.Sephron:BAAANQAECgEIAQAAAA==.Sethen:BAAANQAECgUIBwAAAA==.',
Sh='Shamalamadd:BAAANQAECgQJCQAAAA==.Shammology:BAAANQAECgYICQAAAA==.Shaollyn:BAAANQADCgYICQAAAA==.Shendralar:BAAANQAECggJEwAAAA==.Sheri:BAAANQAECgQJCwAAAA==.Shizam:BAAANQADCgYIBgAAAA==.Shlexie:BAAANQAECgYJDgAAAA==.Shockless:BAAANQAECgYJCwAAAA==.Shotowkhann:BAAANQAECgQJCwAAAA==.',
Si='Sigmaboss:BAAANQADCgQIBAAAAA==.Silentpebble:BAAANQAECgYJEgAAAA==.Sillygoose:BAABNQAECoEeAAMIAAkKpRlPVACPAgAIAAkK3BhPVACPAgAJAAIKuBftHACWAAAAAA==.',
Sk='Skalar:BAAANQADCgcIHQAAAA==.Skodah:BAAANQADCgYICAABNQAECgQJBQABAAAAAA==.',
So='Somnambula:BAAANQADCgUICgAAAA==.',
Sp='Sprocket:BAAANQADCgIJAgABNQADCgUJAQABAAAAAA==.',
Sq='Squarey:BAAANQADCgUJBwAAAA==.',
St='Stell:BAAANQADCggJJAAAAA==.Stinch:BAAANQADCgcIDAABNQAECgEIAQABAAAAAA==.Stovik:BAABNQAECoEfAAMKAAkK9x5FBAAfAwAKAAkK9x5FBAAfAwALAAIKBBTOuwBkAAAAAA==.',
Sv='Sventhebrave:BAAANQAECgEJAQAAAA==.',
Sw='Sweeneytod:BAAANQABCgMIAwAAAA==.',
Sy='Sykill:BAAANQADCgIIAgAAAA==.',
Ta='Tahuruk:BAAANQABCgQIBAAAAA==.Takamura:BAAANQADCgUIBQAAAA==.Talena:BAAANQAECgIIAgAAAA==.Talleral:BAAANQAECgQJCAAAAA==.Taurgrim:BAAANQADCgQIAwAAAA==.Tavin:BAAANQAECgYJEAAAAA==.',
Te='Temaman:BAAANQADCggIEgAAAA==.Temamañ:BAAANQADCgQIBAABNQADCggIEgABAAAAAA==.Terasha:BAAANQAECgYIBgAAAA==.',
Th='Thealtman:BAAANQADCgUIBQAAAA==.Thegreatmoo:BAAANQABCgIJAgAAAA==.',
Ti='Timaeus:BAAANQAECgYJDgAAAA==.',
Tm='Tmbeesknees:BAAANQABCgQIBAAAAA==.',
To='Tokën:BAAANQADCgEIAQAAAA==.',
Tr='Trishi:BAAANQAECgEJAQAAAA==.',
Tw='Twirlwind:BAAANQAECgYIDQAAAA==.',
Ty='Tydrinor:BAAANQAECgEIAQAAAA==.',
Un='Unoblasto:BAAANQAECgUIDAAAAA==.',
Va='Valorash:BAAANQAECgcIEwAAAA==.Valorious:BAAANQADCgIJAgAAAA==.Valshadow:BAAANQADCgcIBwABNQAECgcIEwABAAAAAA==.Vatahlia:BAAANQADCgUIBgAAAA==.',
Ve='Veleyna:BAAANQADCgUIDQAAAA==.Velintha:BAAANQAECgQJBgAAAA==.Ventise:BAAANQADCggIDQAAAA==.',
Vi='Violee:BAAANQADCgYJCgAAAA==.Vision:BAAANQADCgcIBwAAAA==.',
Vo='Vonderick:BAAANQABCgQJBAAAAA==.Voodoodog:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.',
Wa='Wargasm:BAAANQADCgIIAgAAAA==.Warrstomp:BAAANQADCgUIBQAAAA==.',
Wh='Whitewhale:BAAANQAECgYICAAAAA==.',
Xa='Xandaer:BAAANQADCgMJBAAAAA==.Xandaera:BAAANQABCgcJCQAAAA==.Xandarion:BAAANQADCgUJBQAAAA==.',
Xc='Xcïte:BAAANQAECgEIAwAAAA==.',
Xd='Xd:BAAANQADCgQJBAAAAA==.',
Yo='Yogeta:BAAANQADCgQIBAAAAA==.Yosh:BAAANQADCgIIAgAAAA==.',
Yu='Yuji:BAAANQAECgQJCgAAAA==.',
Za='Zalectra:BAAANQAECgcJDAAAAA==.Zamasû:BAAANQADCgUJAwAAAA==.Zarnie:BAAANQABCgEIAQAAAA==.',
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
