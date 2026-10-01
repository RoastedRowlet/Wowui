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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Paladin-Protection','Paladin-Retribution','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Shaman-Enhancement','Warrior-Fury','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Brewmaster','Shaman-Restoration','Mage-Arcane','Warlock-Destruction','Warlock-Affliction','Shaman-Elemental','Mage-Frost',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=53,date='2026-09-29',data={Ai='Ailira:BAAANQAECgYICAABNQAECgUJCQABAAAAAA==.',
Ak='Akasha:BAAANQADCgMIAwAAAA==.',
Al='Alexzandrite:BAAANQADCggICAABNQADCggIDQABAAAAAA==.Alliethra:BAAANQADCgYICwAAAA==.',
Am='Amaryllis:BAAANQADCgMJAwAAAA==.Aminall:BAAANQADCgIIAgAAAA==.',
An='Anaboloholic:BAAANQABCgYIDAAAAA==.Anauthaho:BAAANQADCgUIBQAAAA==.Andore:BAAANQAECgEJAQAAAA==.Angrybutch:BAAANQAECgYIDQAAAA==.Angrymurloc:BAAANQADCgUIBQAAAA==.Antoer:BAAANQAECgYIDAAAAA==.',
Aq='Aquanox:BAAANQADCgYIBgAAAA==.',
Ar='Arbor:BAAANQABCgUIBQAAAA==.Arthaz:BAAANQADCgEIAQAAAA==.',
As='Asonnari:BAAANQADCgUJCgAAAA==.',
At='Atreana:BAABNQAECoEbAAICAAcKQxSDaADNAQACAAcKQxSDaADNAQAAAA==.Attykus:BAAANQAECgEIAQAAAA==.',
Av='Avalerion:BAAANQAECgcIDQAAAA==.Avij:BAAANQADCgYIBgAAAA==.',
Ay='Ayrlyn:BAAANQADCgcIEAAAAA==.',
['Añ']='Añathema:BAAANQAECgEJAQAAAA==.',
Ba='Baldd:BAAANQAECggIDgAAAA==.Balthor:BAAANQAECgUIBgAAAA==.',
Be='Bearlyhealz:BAAANQAECgUIDQABNQAECgYIEQABAAAAAA==.Beechni:BAAANQAECgYJBgAAAA==.Belgarde:BAAANQADCgUIBQAAAA==.',
Bi='Bigpoppapump:BAAANQADCggICAAAAA==.Biological:BAAANQAECgEIAQAAAA==.Bismo:BAAANQADCgcIBwAAAA==.',
Bl='Blind:BAAANQAECgQIBQAAAA==.Bluwhale:BAAANQAECgYICQAAAA==.',
Bo='Bormor:BAAANQAECgMIAwAAAA==.Bosambosia:BAAANQADCgQJBwABNQADCgYIBgABAAAAAA==.Bowdacious:BAAANQADCgUIBwAAAA==.',
Br='Brainpath:BAAANQABCgcICAAAAA==.Brasidias:BAAANQABCgMIAwAAAA==.Brickingkeys:BAAANQAECggIEAAAAA==.Brumak:BAAANQADCgYJCwAAAA==.Bruno:BAABNQAECoEdAAMDAAgKRg1oIgBzAQADAAgKuQxoIgBzAQAEAAEKhQnBVQEuAAAAAA==.',
Bu='Budthespud:BAAANQADCgYICwAAAA==.Bunnynoodle:BAAANQADCgIIAgAAAA==.Burland:BAABNQAECoEXAAQFAAkKgAy/FAAdAgAFAAkKfwu/FAAdAgAGAAEKRxehFgBCAAAHAAEKWws2dAA6AAAAAA==.',
Bw='Bwonshogdi:BAAANQAECgYICQAAAA==.',
['Bá']='Báthory:BAAANQAECgEIAQAAAA==.',
Ca='Caladin:BAAANQAECgYIEgAAAA==.Calemental:BAAANQADCgIJAQABNQAECgYIEgABAAAAAA==.Callistos:BAAANQADCgUICwABNQAECgYIEgABAAAAAA==.Caris:BAAANQADCgUICAAAAA==.Carnar:BAEANQAECgQIBQABNQAECgYICwABAAAAAA==.Castianna:BAAANQADCgYIEgAAAA==.',
Ce='Century:BAAANQAECgUIDwAAAA==.',
Ch='Chewbaulk:BAAANQADCgEIAQAAAA==.Chubbysnackz:BAAANQADCggIEwAAAA==.Chug:BAAANQAECgYIEwAAAA==.',
Ci='Circa:BAAANQAECgUIDAAAAA==.Cithrel:BAAANQAECgYIDAAAAA==.Cizin:BAAANQADCgcIBwAAAA==.',
Cl='Claylemian:BAAANQADCgQIBAAAAA==.Cloak:BAAANQAECgQIBAAAAA==.Cloudninelol:BAAANQADCgUIBQAAAA==.',
Co='Coriko:BAABNQAECoEYAAIIAAgKogQRFgCpAQAIAAgKogQRFgCpAQAAAA==.',
Cr='Crocklock:BAAANQAECgIJBAAAAA==.',
Cu='Cured:BAAANQADCgMIAwAAAA==.',
Da='Dallia:BAAANQADCgYJEwAAAA==.Dalyrimple:BAAANQADCggIFwAAAA==.Damnatio:BAABNQAECoEYAAIEAAcKRSOINQC0AgAEAAcKRSOINQC0AgAAAA==.Darkclement:BAAANQAECgUIDgAAAA==.Darksworn:BAAANQADCgMIAQAAAA==.',
De='Deadchaos:BAAANQADCggICAAAAA==.Deathbybob:BAAANQADCggIHAAAAA==.Deckard:BAAANQAECgUICQAAAA==.Deeper:BAAANQAECgEJAQAAAA==.Demonofwar:BAAANQADCgUIBwABNQAECgcIFQAJAEIkAA==.Derese:BAAANQADCggICAAAAA==.Detroll:BAAANQADCgMJAwAAAA==.Dezzii:BAAANQADCgcIDwAAAA==.',
Di='Divineblood:BAAANQAECgIJAgAAAA==.',
Dm='Dmaan:BAAANQAECggIEAAAAA==.',
Do='Doomflower:BAAANQADCgYIDgAAAA==.',
Dr='Drekzin:BAAANQABCgMIAwAAAA==.Drhealalot:BAAANQAECgIIAwAAAA==.Drugar:BAAANQAECgcIEAABNQAFFAIIBQAFANcSAA==.',
Du='Dumparooski:BAAANQADCgUICgABNQAECgUICQABAAAAAA==.Durabull:BAAANQADCggJGwAAAA==.',
Ea='Earthvoodoo:BAAANQAECgIIAgAAAA==.',
Ed='Edrin:BAAANQABCgIIAgAAAA==.',
Ei='Eithelis:BAAANQADCgUIBQAAAA==.',
El='Eladar:BAAANQADCggICAAAAA==.',
En='Ender:BAAANQAECgUIBwAAAA==.',
Ep='Ephrael:BAAANQAECggICAAAAA==.',
Er='Erniethemonk:BAAANQAECgUICAAAAA==.Ernietheorc:BAAANQAECgUICAAAAA==.',
Eu='Eurytos:BAAANQAECgUICwAAAA==.Euthanize:BAAANQAECgIIAwAAAA==.',
Ev='Evianda:BAAANQADCgYIBwAAAA==.Evilissereni:BAAANQABCgQJBAAAAA==.',
Ez='Ezéé:BAAANQAECgEIAgAAAA==.',
Fa='Falsetto:BAAANQADCgEIAQAAAA==.Faramír:BAAANQADCgcIDwAAAA==.Farrago:BAAANQADCgYIDQAAAA==.',
Fe='Fennek:BAAANQAECgMIAwAAAA==.Feorio:BAAANQAECgUICQABNQAECgQIBgABAAAAAA==.',
Fi='Fists:BAAANQABCgYICQAAAA==.',
Fm='Fmzmage:BAAANQABCggIEgAAAA==.',
Ga='Garaylo:BAACNQAFFIEOAAIEAAUKWSBsAwDvAQAEAAUKWSBsAwDvAQA1AAQKgSQAAgQACApBJgYOAHoDAAQACApBJgYOAHoDAAAA.',
Gh='Ghorianha:BAAANQADCgQICAAAAA==.Ghosst:BAABNQAECoEiAAMKAAkKEiI4CAB+AwAKAAkKEiI4CAB+AwALAAQK8Qq+SAC2AAAAAA==.',
Gn='Gnobull:BAAANQADCggICAAAAA==.Gnudgnimish:BAAANQADCgYIDAABNQAECggIGgAMAEMlAA==.',
Go='Goldenknight:BAAANQADCggIDgAAAA==.Gorilon:BAAANQAECggIBAAAAA==.',
Gr='Grimmel:BAAANQAECgMIAwAAAA==.Grimmrot:BAAANQADCgQIBAAAAA==.',
Gu='Guildan:BAAANQABCgcIEAAAAA==.Guttris:BAAANQAECgUICQAAAA==.',
Gw='Gwaineelock:BAAANQADCgUIDAAAAA==.Gwyndolyn:BAAANQAECgEJAQAAAA==.',
Ha='Hahalu:BAAANQADCgYIBgAAAA==.Haikusen:BAAANQADCgMIBAABNQAECgcIFQAJAEIkAA==.Hassan:BAAANQADCgMIBQAAAA==.Haupaa:BAAANQADCgYIBgAAAA==.',
He='Heisenberger:BAAANQABCgEIAQAAAA==.Heliòs:BAAANQADCgMIBAAAAA==.Hemolele:BAAANQADCgcIBwAAAA==.Hesseth:BAAANQADCggIDwAAAA==.',
Ho='Hoake:BAAANQADCgYICAAAAA==.Hogshock:BAAANQAECgcIEgAAAA==.Holyzel:BAAANQAECgcICQAAAA==.',
Hs='Hsimingeung:BAAANQADCgUIBQABNQAECggIGgAMAEMlAA==.Hsimingjung:BAABNQAECoEaAAIMAAgKQyVaAgBnAwAMAAgKQyVaAgBnAwAAAA==.Hsimingkung:BAAANQAECgIIAgABNQAECggIGgAMAEMlAA==.',
Hu='Huaka:BAAANQADCggIDgAAAA==.Huh:BAAANQADCgYIBgAAAA==.Humanic:BAAANQADCggIDAAAAA==.Huntari:BAAANQADCgEIAQAAAA==.',
Hy='Hylie:BAABNQAECoEZAAICAAgKoRODVwADAgACAAgKoRODVwADAgAAAA==.',
['Hè']='Hèlla:BAAANQABCgQIBAAAAA==.',
Ic='Icolann:BAABNQAECoEdAAINAAgK1B32IgCiAgANAAgK1B32IgCiAgABNQAECgIIAgABAAAAAA==.',
Il='Illidarie:BAAANQADCgEIAQAAAA==.',
Im='Imadragon:BAAANQADCgMIAwABNQAECgUICQABAAAAAA==.',
In='Invisibull:BAAANQADCgEIAQAAAA==.Inzi:BAAANQADCgQIBQAAAA==.',
Is='Isparian:BAAANQADCgYIDgAAAA==.Istabthings:BAACNQAFFIEFAAIFAAIK1xJJCwCkAAAFAAIK1xJJCwCkAAA1AAQKgRgAAgUACArTIQoHAPgCAAUACArTIQoHAPgCAAAA.',
Iv='Ivanyr:BAACNQAFFIEHAAIDAAMKSw/bBQDAAAADAAMKSw/bBQDAAAA1AAQKgSQAAgMACQqPHpoJAMcCAAMACQqPHpoJAMcCAAAA.Ivy:BAAANQABCgIIAgAAAA==.',
Ja='Jadebug:BAAANQADCgUJBwAAAA==.Jaime:BAAANQADCgUIBwABNQAECgcIFQAJAEIkAA==.',
Je='Jenzö:BAAANQAECgUICAAAAA==.Jesta:BAAANQADCgYJDgAAAA==.',
Ji='Jikiniinki:BAAANQAECgEIAgAAAA==.',
Jo='Joeviben:BAAANQAECgMIAwAAAA==.Johnnyretwar:BAAANQAECgMIBQAAAA==.Jovian:BAAANQADCgUIDQAAAA==.',
Ju='Jugsy:BAABNQAECoEiAAIOAAgKSSBWPgDpAgAOAAgKSSBWPgDpAgAAAA==.',
['Jë']='Jënzo:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.',
Ka='Kaikai:BAABNQAECoEZAAQCAAkKNRIQPgBZAgACAAkKNRIQPgBZAgAPAAMK5AiMRgCXAAAQAAEKxQn3KQAtAAAAAA==.Kaldread:BAAANQAECgIIAwAAAA==.Kaligo:BAABNQAECoEcAAMRAAgKsxOtSAAFAgARAAgKsxOtSAAFAgANAAMKHA3HvgCYAAAAAA==.Kastiron:BAAANQAECgUJBgAAAA==.Kazrime:BAAANQAECgIIAgAAAA==.',
Ke='Kebsy:BAAANQAECgYIEAAAAA==.Kelaia:BAAANQADCgYJBgAAAA==.Kelements:BAAANQADCgIIAgAAAA==.Kelyessada:BAAANQADCgYIBgAAAA==.Kenergy:BAABNQAECoEXAAIHAAgKeQp5KgDSAQAHAAgKeQp5KgDSAQAAAA==.Kerit:BAAANQABCgIIAgAAAA==.Kevonjuravis:BAAANQAECgQIDAAAAA==.',
Kh='Khalyl:BAAANQAECgIIAwAAAA==.',
Ki='Kiandra:BAAANQADCgYIEwAAAA==.Killpain:BAAANQAECgUIDAAAAA==.Kirå:BAAANQADCgYIDgAAAA==.',
Kr='Krytus:BAAANQADCgIJAgAAAA==.',
Ku='Kungpaochik:BAAANQAECgUICQAAAA==.',
Ky='Kyarax:BAAANQADCggICQAAAA==.',
Kz='Kzmo:BAAANQAECgEIAgAAAA==.',
Le='Lena:BAAANQADCgYIBgAAAA==.',
Li='Lizzybordan:BAAANQADCgMIAwABNQADCgQIBAABAAAAAA==.',
Lo='Lousanis:BAAANQAECgUIDgAAAA==.',
Lu='Lucinick:BAAANQAECgIIBAAAAA==.Lupercal:BAAANQAECggJBwAAAA==.',
Ma='Madmartegan:BAAANQABCgMIAwAAAA==.Mariskama:BAAANQADCgYIGAAAAA==.Markusthered:BAAANQADCgYIBgAAAA==.Maybecolin:BAAANQADCgEJAQAAAA==.Mazza:BAAANQADCggJDQABNQAECgcICQABAAAAAA==.',
Mh='Mhelora:BAAANQAECgQICgAAAA==.',
Mi='Mikenolan:BAAANQADCgcIBwAAAA==.Mimacho:BAAANQAECgMIAwAAAA==.Mindmuncher:BAAANQAECgUIDAAAAA==.Minimini:BAAANQAECgQJEgAAAA==.Minnow:BAAANQADCgYIBgAAAA==.',
Mo='Moolin:BAAANQAECgYICQAAAA==.',
Mu='Munder:BAAANQAECgEJAQAAAA==.Murph:BAAANQADCgcJBwAAAA==.',
My='Mythuneran:BAAANQAECgYIDgAAAA==.',
Na='Naheka:BAAANQADCggIEAAAAA==.',
Ne='Nemini:BAAANQADCggIIgAAAA==.Nena:BAAANQAECgQICgAAAA==.Nenacurses:BAAANQADCgYJBgABNQAECgQICgABAAAAAA==.Newfy:BAAANQAECgYICQAAAA==.',
Ni='Nightmoves:BAAANQADCgYIBgAAAA==.Ninjamage:BAAANQADCggICAAAAA==.Nithendroz:BAAANQAECgIIAgAAAA==.Nity:BAAANQAECgEIAQAAAA==.',
No='Noctaurus:BAAANQADCgQJBAAAAA==.Nogini:BAAANQADCgcJBwAAAA==.Nomadhew:BAAANQAECggJCAAAAA==.Noraice:BAAANQABCgQIBwAAAA==.Notagain:BAACNQAFFIEOAAIEAAYKoBCnAwDnAQAEAAYKoBCnAwDnAQA1AAQKgSAAAgQACQp5IsMwAMgCAAQACQp5IsMwAMgCAAAA.',
Ny='Nyuxx:BAAANQAECgEIAgAAAA==.',
Ob='Obake:BAAANQAECgQIBgAAAA==.',
Od='Odphijor:BAAANQAECggICAAAAA==.',
Og='Ogsmallz:BAAANQADCgcICwAAAA==.',
Ol='Olenza:BAAANQADCgUIDAAAAA==.',
Or='Orangewhale:BAAANQAFFAIIAwAAAA==.Orondrus:BAAANQADCgMIAwAAAA==.',
Ox='Oxidation:BAAANQADCgQIBQAAAA==.',
Oz='Ozsome:BAAANQAECgUIDQAAAA==.',
Pa='Pallybob:BAAANQADCgQIBAABNQADCggIHAABAAAAAA==.Pavo:BAAANQAECgYIEQAAAA==.',
Pe='Pebbleshifts:BAAANQADCgcICAAAAA==.Peejean:BAAANQAECgEIAQAAAA==.Pey:BAAANQADCggIFQABNQAECgkJGgAOAA8hAA==.Peycicle:BAABNQAECoEaAAIOAAkKDyENJwAtAwAOAAkKDyENJwAtAwAAAA==.Peystruction:BAAANQADCgYJBgABNQAECgkJGgAOAA8hAA==.',
Ph='Phantasm:BAAANQABCgIIAgAAAA==.Phlox:BAAANQAECgUIDAAAAA==.',
Pi='Pippa:BAAANQAECgUIDAAAAA==.',
Pl='Planett:BAAANQAECgUIEAAAAA==.',
Po='Poetuck:BAAANQAECgYIEAAAAA==.Pokeyruler:BAAANQADCgEIAQAAAA==.',
Pr='Proko:BAAANQAECgQICQAAAA==.',
Qa='Qatka:BAAANQADCgUJCAAAAA==.',
Qu='Quiver:BAAANQAECgEIAQAAAA==.Quizmagic:BAAANQADCgMJAwAAAA==.',
Ra='Raein:BAAANQAECgUICwAAAA==.Rainn:BAAANQAECgQICgAAAA==.Rainnsoul:BAAANQADCgEIAQAAAA==.Ralofurius:BAAANQADCgUJDAABNQADCgYIBgABAAAAAA==.Rasril:BAAANQADCgIIAgAAAA==.',
Re='Redrighthand:BAAANQADCgMIAwAAAA==.Relwind:BAAANQADCgQIBAAAAA==.Reshtargorr:BAAANQABCgEIAQAAAA==.',
Ro='Roskolnikov:BAAANQAECgIIAwAAAA==.Rossa:BAAANQADCgIIAgAAAA==.',
Ru='Ruele:BAAANQAECgIIAgAAAA==.Ruenan:BAABNQAECoEkAAMKAAkK5CU3AQDqAwAKAAkK5CU3AQDqAwALAAEKVxghYwBHAAAAAA==.',
Sa='Sanbas:BAAANQAECgQIBAAAAA==.Sapthat:BAAANQADCggJDgAAAA==.Sarthrity:BAAANQAECgEIAQAAAA==.Satyrs:BAAANQADCgIIAgAAAA==.Savepebble:BAAANQADCggICAAAAA==.',
Sc='Scootsy:BAAANQAECgYIDQAAAA==.',
Se='Seirin:BAAANQAECgUICwAAAA==.Seldiane:BAAANQADCggIFgAAAA==.Selendaa:BAAANQAECgQICwAAAA==.Senadarra:BAAANQADCgYIBgAAAA==.Senastera:BAAANQADCgUIDAAAAA==.Sephandtotem:BAAANQAECgEJAQAAAA==.Sephron:BAAANQAECgIIAwAAAA==.Sethen:BAAANQAECgUIBwAAAA==.',
Sh='Shamalamadd:BAAANQAECgYICwAAAA==.Shammology:BAAANQAECgcICgAAAA==.Shaollyn:BAAANQADCgYICQAAAA==.Shendralar:BAABNQAECoEeAAMHAAkKsRQkKADlAQAFAAcK+xU5GQDsAQAHAAgKpg4kKADlAQAAAA==.Sheri:BAAANQAECgUIEAAAAA==.Shizam:BAAANQADCgYIBgAAAA==.Shlexie:BAAANQAECgcIDwAAAA==.Shockless:BAAANQAECgYIEQAAAA==.Shotowkhann:BAAANQAECgQIDwAAAA==.',
Si='Sigmaboss:BAAANQADCgQIBAAAAA==.Silentpebble:BAAANQAECgcIEwAAAA==.Sillygoose:BAACNQAFFIEHAAMOAAQKgQxQIwDzAAAOAAMKSg5QIwDzAAASAAEKJQeBDQBHAAA1AAQKgSAAAw4ACQoQHKVaAJ4CAA4ACQppG6VaAJ4CABIAAgq4Fy8jAJIAAAAA.',
Sk='Skalar:BAAANQADCgcIHQAAAA==.Skodah:BAAANQADCgYIDAABNQAECgQIBgABAAAAAA==.',
So='Somnambula:BAAANQADCgUICgAAAA==.',
Sp='Sprocket:BAAANQADCgIJAgABNQAECgMIAwABAAAAAA==.',
Sq='Squarey:BAAANQADCgUJBwAAAA==.',
St='Stell:BAAANQADCggJJAAAAA==.Stinch:BAAANQADCgcIDAABNQAECgUICQABAAAAAA==.Stovik:BAABNQAECoElAAMIAAkK+SATAwBcAwAIAAkK+SATAwBcAwANAAIKBBSt1gBfAAAAAA==.',
Sv='Sventhebrave:BAAANQAECgIIAwAAAA==.',
Sw='Sweeneytod:BAAANQABCgMIAwAAAA==.',
Sy='Sykill:BAAANQADCgIIAgAAAA==.Sylus:BAAANQADCgEIAQAAAA==.',
Ta='Tahuruk:BAAANQABCgQIBAAAAA==.Takamura:BAAANQADCgUIBQAAAA==.Talena:BAAANQAECgIIAgAAAA==.Talleral:BAAANQAECgQIDAAAAA==.Taurgrim:BAAANQADCgQIAwAAAA==.Tavin:BAAANQAECgcIEwAAAA==.',
Te='Temaman:BAAANQADCggIEgAAAA==.Temamañ:BAAANQADCggIDAABNQADCggIEgABAAAAAA==.Terasha:BAAANQAECgYIBgAAAA==.',
Th='Thealtman:BAAANQADCgUIBQAAAA==.Thegreatmoo:BAAANQADCgQIBAAAAA==.',
Ti='Timaeus:BAAANQAECgcIDwAAAA==.',
Tm='Tmbeesknees:BAAANQABCgQIBAAAAA==.',
To='Tokën:BAAANQADCgEIAQAAAA==.',
Tr='Trishi:BAAANQAECgEIAgAAAA==.',
Tw='Twirlwind:BAAANQAECgYIEwAAAA==.',
Ty='Tydrinor:BAAANQAECgEIAQAAAA==.',
Un='Unoblasto:BAAANQAECgcIEQAAAA==.',
Va='Valorash:BAABNQAECoEbAAIEAAcKfBrlXQApAgAEAAcKfBrlXQApAgAAAA==.Valorious:BAAANQADCgMIAwAAAA==.Valshadow:BAAANQADCgcIBwABNQAECgcIGwAEAHwaAA==.Vatahlia:BAAANQADCggIEQAAAA==.',
Ve='Veleyna:BAAANQAECgIIAgAAAA==.Velintha:BAAANQAECgQJBgAAAA==.Ventise:BAAANQADCggIDQAAAA==.',
Vi='Violee:BAAANQAECgMIAwAAAA==.Vision:BAAANQADCgcIBwAAAA==.',
Vo='Vonderick:BAAANQABCgUIBQAAAA==.Voodoodog:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.',
Wa='Wargasm:BAAANQADCgMIAwABNQADCgQIBAABAAAAAA==.Warrstomp:BAAANQADCgUIBQAAAA==.',
Wh='Whitewhale:BAAANQAECgYICAAAAA==.',
Xa='Xandaer:BAAANQADCgMIBAAAAA==.Xandaera:BAAANQABCgcJCQAAAA==.Xandarion:BAAANQADCggIDQAAAA==.',
Xc='Xcïte:BAAANQAECgEIAwAAAA==.',
Xd='Xd:BAAANQADCgQJBAAAAA==.',
Yo='Yogeta:BAAANQADCgQIBAAAAA==.Yosh:BAAANQADCgIIAgAAAA==.',
Yu='Yuji:BAAANQAECgUICwAAAA==.',
Za='Zalectra:BAAANQAECgcIEwAAAA==.Zamasû:BAAANQADCgUIBwAAAA==.Zarnie:BAAANQABCgEIAQAAAA==.',
Ze='Zelila:BAAANQAECgIIAgAAAA==.',
Zo='Zoioz:BAAANQADCgQIBAAAAA==.Zoras:BAAANQADCggICAAAAA==.',
['Ål']='Ålloria:BAAANQADCgcICQAAAA==.',
['Ón']='Ónix:BAAANQADCgcICgAAAA==.',
['Öd']='Ödínn:BAAANQADCgQIBAAAAA==.',
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
