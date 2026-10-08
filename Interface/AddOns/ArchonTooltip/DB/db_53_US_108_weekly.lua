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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Paladin-Retribution','Mage-Arcane','Mage-Frost','Paladin-Protection','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Druid-Balance','Druid-Guardian','Druid-Restoration','Monk-Windwalker','Shaman-Enhancement','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Brewmaster','Shaman-Restoration','Shaman-Elemental','Warlock-Destruction','Warlock-Affliction','Monk-Mistweaver','Priest-Holy','Warrior-Protection',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=53,date='2026-10-06',data={Ae='Aecch:BAAANQADCgQIBAAAAA==.',
Ai='Ailira:BAAANQAECgYICAABNQAECgUJCQABAAAAAA==.',
Ak='Akasha:BAAANQADCgQIBQAAAA==.',
Al='Alexzandrite:BAAANQADCggICAABNQADCggIDQABAAAAAA==.Alliethra:BAAANQADCgYICwAAAA==.',
Am='Amaryllis:BAAANQADCgMJAwAAAA==.Aminall:BAAANQADCgIIAgAAAA==.',
An='Anaboloholic:BAAANQABCgYIDAAAAA==.Anauthaho:BAAANQADCgUIBQAAAA==.Andore:BAAANQAECgIIAwAAAA==.Angrybutch:BAAANQAECgYIDQAAAA==.Angrymurloc:BAAANQAECgEIAQAAAA==.Antoer:BAAANQAECgYIDAAAAA==.',
Aq='Aquanox:BAAANQADCgYIBgAAAA==.',
Ar='Arbor:BAAANQABCgUIBQAAAA==.Arthaz:BAAANQADCgEIAQAAAA==.',
As='Ashamael:BAAANQADCggICAAAAA==.Asonnari:BAAANQADCgUJCgAAAA==.',
At='Atreana:BAABNQAECoEjAAICAAgK2hODZAAIAgACAAgK2hODZAAIAgAAAA==.Attykus:BAAANQAECgQIBAAAAA==.',
Av='Avalerion:BAABNQAECoEaAAIDAAgKbRsaWQBiAgADAAgKbRsaWQBiAgAAAA==.Avij:BAAANQADCgYIBgABNQADCgYIDAABAAAAAA==.',
Ay='Ayrlyn:BAAANQAECgUIBAAAAA==.',
['Añ']='Añathema:BAAANQAECgEJAQAAAA==.',
Ba='Baldd:BAAANQAECggIEgAAAA==.Balthor:BAAANQAECgUIBgAAAA==.',
Be='Bearlyhealz:BAAANQAECgUIEQABNQAECgYIEQABAAAAAA==.Beechni:BAAANQAECgYJBgAAAA==.Belgarde:BAAANQADCgUIBQAAAA==.',
Bi='Bigpoppapump:BAAANQADCggICAAAAA==.Biological:BAAANQAECgEIAQAAAA==.Bismo:BAAANQAECgIIAQAAAA==.',
Bl='Blind:BAAANQAECgQIBQAAAA==.Bluwhale:BAAANQAECgYICQAAAA==.',
Bo='Bormor:BAAANQAECgMIAwAAAA==.Bowdacious:BAAANQADCgUICQAAAA==.',
Br='Brainpath:BAAANQABCgcICAAAAA==.Brasidias:BAAANQABCgMIAwAAAA==.Brickingkeys:BAABNQAECoEYAAMEAAkKLR+/dwB4AgAEAAcKkh6/dwB4AgAFAAIKSSFSIwCxAAAAAA==.Brumak:BAAANQADCgYJCwAAAA==.Bruno:BAABNQAECoElAAMGAAgKxBHRHwC7AQAGAAgKxBHRHwC7AQADAAEKhQlNgAEuAAAAAA==.',
Bu='Budthespud:BAAANQADCgYICwAAAA==.Bunnynoodle:BAAANQADCgIIAgAAAA==.Burland:BAABNQAECoEZAAQHAAkKeA2xFgAaAgAHAAkKdwyxFgAaAgAIAAEKRxdhGABBAAAJAAEKWwtHhwA6AAAAAA==.',
Bw='Bwonshogdi:BAAANQAECgYICQAAAA==.',
['Bá']='Báthory:BAAANQAECgEIAQAAAA==.',
Ca='Caedus:BAAANQABCgUIBQAAAA==.Caladin:BAABNQAECoEaAAIGAAcKWh7UFAA2AgAGAAcKWh7UFAA2AgAAAA==.Calemental:BAAANQADCgIJAQABNQAECgcIGgAGAFoeAA==.Callistos:BAAANQADCgUICwABNQAECgcIGgAGAFoeAA==.Caris:BAAANQADCgUICAAAAA==.Carnar:BAEANQAECgQIBQABNQAECgYIEQABAAAAAA==.Castianna:BAAANQADCgYIEgAAAA==.',
Ce='Century:BAABNQAECoEaAAQKAAcK1xKIQgC/AQAKAAcK1xKIQgC/AQALAAUK8gnDMgDAAAAMAAMKgAxLUQCVAAAAAA==.',
Ch='Chewbaulk:BAAANQADCgEIAQAAAA==.Chubbysnackz:BAAANQADCggIFQAAAA==.Chug:BAABNQAECoEbAAINAAgKCR/AEQCxAgANAAgKCR/AEQCxAgAAAA==.',
Ci='Circa:BAAANQAECgYIEgAAAA==.Cithrel:BAAANQAECgcIEgAAAA==.Cizin:BAAANQADCgcIBwAAAA==.',
Cl='Claylemian:BAAANQADCgQIBAAAAA==.Cloak:BAAANQAECgQIBAAAAA==.Cloudninelol:BAAANQADCgUIBQAAAA==.',
Co='Coriko:BAABNQAECoEcAAIOAAgKdgfaFgDNAQAOAAgKdgfaFgDNAQAAAA==.',
Cr='Crocklock:BAAANQAECgIJBAAAAA==.',
Cu='Cured:BAAANQADCgMIAwAAAA==.',
Da='Dakkenz:BAAANQADCgUIBQAAAA==.Dallia:BAAANQAECgEIAgAAAA==.Dalyrimple:BAAANQADCggIHAAAAA==.Damnatio:BAABNQAECoEcAAIDAAgKLyOyIwAdAwADAAgKLyOyIwAdAwAAAA==.Darkclement:BAAANQAECgUIEwAAAA==.Darksworn:BAAANQADCgMIAQAAAA==.Daskapital:BAAANQAECgIIAgAAAA==.Davrimbasher:BAAANQADCgMIAwAAAA==.',
De='Deadchaos:BAAANQADCggICAAAAA==.Deathbybob:BAAANQADCggIHwAAAA==.Deckard:BAAANQAECgYIDwAAAA==.Deeper:BAAANQAECgQIBgAAAA==.Demonofwar:BAAANQADCgUICwABNQAECggIGwAPABYkAA==.Derese:BAAANQADCggICAAAAA==.Detroll:BAAANQADCgMJAwAAAA==.Dezzii:BAAANQAECgIIAgAAAA==.',
Di='Divineblood:BAAANQAECgIJAgAAAA==.',
Dm='Dmaan:BAABNQAECoEZAAIQAAkK1yJaBQB6AwAQAAkK1yJaBQB6AwAAAA==.',
Do='Doomflower:BAAANQAECgIIAgAAAA==.',
Dr='Drekzin:BAAANQABCgMIAwAAAA==.Drhealalot:BAAANQAECgMIBAAAAA==.Drugar:BAABNQAECoEZAAMQAAgK4h+8HQB1AgAQAAgKFB68HQB1AgARAAcKQh0JNQAxAgABNQAFFAQICQAHAEgUAA==.',
Du='Dumparooski:BAAANQAECgQIBAABNQAECgcIEQABAAAAAA==.Durabull:BAAANQADCggJGwAAAA==.',
Ea='Earthvoodoo:BAAANQAECgIIAgAAAA==.',
Ed='Edrin:BAAANQABCgIIAgAAAA==.',
Ei='Eithelis:BAAANQADCgUIBQAAAA==.',
El='Eladar:BAAANQADCggICAAAAA==.Elezel:BAAANQADCgIIAwAAAA==.',
En='Ender:BAAANQAECgUIBwAAAA==.',
Ep='Ephrael:BAAANQAECggICAAAAA==.',
Er='Erniethemonk:BAAANQAECgUICQAAAA==.Ernietheorc:BAAANQAECgUICAAAAA==.',
Eu='Eurytos:BAAANQAECgYIEQAAAA==.Euthanize:BAAANQAECgMIBQAAAA==.',
Ev='Evianda:BAAANQADCgYIDAAAAA==.Evilissereni:BAAANQABCgUIBgAAAA==.',
Ez='Ezéé:BAAANQAECgEIAgAAAA==.',
Fa='Falsetto:BAAANQADCgEIAQAAAA==.Faramír:BAAANQAECgIIAgAAAA==.Farrago:BAAANQADCgYIDQAAAA==.',
Fe='Fennek:BAAANQAECgYICQAAAA==.Feorio:BAAANQAECgUIDQABNQAECgUIDAABAAAAAA==.',
Fi='Fists:BAAANQABCgYICQAAAA==.',
Fm='Fmzmage:BAAANQABCggIEgAAAA==.',
Ga='Garaylo:BAACNQAFFIEUAAIDAAYKLCB2AgBBAgADAAYKLCB2AgBBAgA1AAQKgScAAgMACApBJggTAGoDAAMACApBJggTAGoDAAAA.',
Ge='Geoffreys:BAAANQAECgQIBQAAAA==.Geroendor:BAAANQAECgEIAQAAAA==.',
Gh='Ghorianha:BAAANQADCgQICAAAAA==.Ghosst:BAABNQAECoEmAAMSAAkKpSK0CgB2AwASAAkKpSK0CgB2AwATAAQK8Qr8UgCyAAAAAA==.',
Gn='Gnobull:BAAANQADCggICAAAAA==.Gnudgnimish:BAAANQADCgYIDAABNQAECggIIQAUAEUlAA==.',
Go='Goldenknight:BAAANQADCggIDgAAAA==.Gorilon:BAAANQAECggIBAAAAA==.',
Gr='Grimmel:BAAANQAECgYICQAAAA==.Grimmrot:BAAANQADCgQIBAAAAA==.',
Gu='Guildan:BAAANQABCgcIEAAAAA==.Guttris:BAAANQAECgUICQAAAA==.',
Gw='Gwyndolyn:BAAANQAECgEJAQAAAA==.',
Ha='Hahalu:BAAANQADCgYICgAAAA==.Haikusen:BAAANQADCggIDAABNQAECggIGwAPABYkAA==.Hassan:BAAANQADCgMIBQAAAA==.Haupaa:BAAANQADCgcIDAAAAA==.',
He='Heisenberger:BAAANQABCgEIAQAAAA==.Heliòs:BAAANQADCgMIBAAAAA==.Hemolele:BAAANQADCgcICAAAAA==.Hesseth:BAAANQAECgQIBAAAAA==.',
Ho='Hoake:BAAANQADCgYICAAAAA==.Hogshock:BAABNQAECoEXAAQOAAkK5BCBDgBpAgAOAAkK5BCBDgBpAgAVAAMKFwhm3ACFAAAWAAIKKgWx/ABZAAAAAA==.Holyzel:BAAANQAECgcICgAAAA==.',
Hs='Hsimingeung:BAAANQADCgUIBQABNQAECggIIQAUAEUlAA==.Hsimingjung:BAABNQAECoEhAAIUAAgKRSXoAgBeAwAUAAgKRSXoAgBeAwAAAA==.Hsimingkung:BAAANQAECgIIAgABNQAECggIIQAUAEUlAA==.',
Hu='Huaka:BAAANQADCggIEgAAAA==.Huh:BAAANQADCgYIBgAAAA==.Humanic:BAAANQADCggIDAAAAA==.Huntari:BAAANQADCgEIAQAAAA==.',
Hy='Hylie:BAABNQAECoEZAAICAAgKoRM2awD1AQACAAgKoRM2awD1AQAAAA==.',
['Hè']='Hèlla:BAAANQABCgQIBAAAAA==.',
Ic='Icolann:BAABNQAECoEkAAIVAAgKgR6sJwClAgAVAAgKgR6sJwClAgABNQAECgIIAgABAAAAAA==.',
Il='Illidarie:BAAANQADCgEIAQAAAA==.',
Im='Imadragon:BAAANQADCgMIAwABNQAECgcIEQABAAAAAA==.',
In='Invisibull:BAAANQADCgEIAQAAAA==.Inzi:BAAANQADCgUICQAAAA==.',
Is='Isparian:BAAANQADCgYIDgAAAA==.Istabthings:BAACNQAFFIEJAAIHAAQKSBTBBwBjAQAHAAQKSBTBBwBjAQA1AAQKgRkAAwcACArTIZAIAOQCAAcACArTIZAIAOQCAAkAAQr8FC2EAEEAAAAA.',
Iv='Ivanyr:BAACNQAFFIEMAAIGAAUKyhBSBABTAQAGAAUKyhBSBABTAQA1AAQKgScAAgYACQo6H1YLAMUCAAYACQo6H1YLAMUCAAAA.Ivy:BAAANQABCgIIAgAAAA==.',
Ja='Jackleecher:BAAANQAECgQIBAABNQAECgkJGAAEAC0fAA==.Jadebug:BAAANQAECgMIAgAAAA==.Jaime:BAAANQADCgUIBwABNQAECggIGwAPABYkAA==.',
Je='Jenzö:BAAANQAECggIEAAAAA==.Jesta:BAAANQADCgYJDgAAAA==.',
Ji='Jikiniinki:BAAANQAECgQIBgAAAA==.',
Jo='Joeviben:BAAANQAECgUICAAAAA==.Johnnyretwar:BAAANQAECgYIDAAAAA==.Jovian:BAAANQADCgUIDQAAAA==.',
Ju='Jugsy:BAABNQAECoEpAAIEAAkKmh/pKQAyAwAEAAkKmh/pKQAyAwAAAA==.',
['Jë']='Jënzo:BAAANQADCgQIBAABNQAECggIEAABAAAAAA==.',
Ka='Kaikai:BAABNQAECoEbAAQCAAkKmhLNSgBUAgACAAkKmhLNSgBUAgAXAAMK5AhfSwCSAAAYAAEKxQl/LgAtAAAAAA==.Kaldread:BAAANQAECgIIBQAAAA==.Kaligo:BAABNQAECoEkAAMWAAgK8RfhPgBQAgAWAAgK8RfhPgBQAgAVAAMKHA1a1gCSAAAAAA==.Karshtonson:BAAANQAECggICAAAAA==.Kastiron:BAAANQAECgUJBgAAAA==.Kazrime:BAAANQAECgIIAgAAAA==.',
Ke='Kebsy:BAABNQAECoEWAAQNAAYK6xmbJgC7AQANAAYKcxibJgC7AQAUAAEKGQvtLAAxAAAZAAEKMQpWSQAnAAAAAA==.Kelaia:BAAANQADCgYJBgAAAA==.Kelements:BAAANQADCgIIAgAAAA==.Kelyessada:BAAANQADCgYIBgAAAA==.Kenergy:BAABNQAECoEaAAIJAAkKmQqbLQD6AQAJAAkKmQqbLQD6AQAAAA==.Kerit:BAAANQABCgIIAgAAAA==.Kevonjuravis:BAAANQAECgQIDgAAAA==.',
Kh='Khalyl:BAAANQAECgMIBQAAAA==.',
Ki='Kiandra:BAAANQADCgYIFgAAAA==.Killpain:BAAANQAECgUIDAAAAA==.Kirå:BAAANQADCgYIDgAAAA==.',
Kr='Krytus:BAAANQADCgIJAgAAAA==.',
Ku='Kungpaochik:BAAANQAECgcIEQAAAA==.',
Ky='Kyarax:BAAANQADCggICQAAAA==.',
Kz='Kzmo:BAAANQAECgEIAgAAAA==.',
Le='Lena:BAAANQADCgYIBgAAAA==.',
Li='Lizzybordan:BAAANQADCgYICQAAAA==.',
Lo='Lousanis:BAAANQAECgUIEwAAAA==.',
Lu='Lucinick:BAAANQAECgMIBgAAAA==.Lupercal:BAAANQAECggJBwAAAA==.',
Ma='Madmartegan:BAAANQABCgMIAwAAAA==.Mariskama:BAAANQADCggIHgAAAA==.Markusthered:BAAANQAECgQIBAAAAA==.Maybecolin:BAAANQADCgEJAQAAAA==.Mazza:BAAANQAECgIIAgABNQAECggIDwABAAAAAA==.',
Mh='Mhelora:BAAANQAECgQIDQAAAA==.',
Mi='Mikenolan:BAAANQADCgcIBwAAAA==.Mimacho:BAAANQAECgMIAwAAAA==.Mindmuncher:BAAANQAECgUIDAAAAA==.Minimini:BAAANQAECgQJEgAAAA==.Minnow:BAAANQADCgYIBgAAAA==.',
Mo='Moolin:BAAANQAECgYICQAAAA==.',
Mu='Munder:BAAANQAECgEJAQAAAA==.Murph:BAAANQADCgcJBwAAAA==.',
My='Mythuneran:BAAANQAECgYIDgAAAA==.',
Na='Naheka:BAAANQADCggIEAAAAA==.Naron:BAAANQADCgIIAgAAAA==.',
Ne='Nemini:BAAANQADCggIKgAAAA==.Nena:BAABNQAECoEZAAMKAAUKEA21ZQALAQAKAAUKEA21ZQALAQAMAAIKIQaZYwBAAAAAAA==.Nenacurses:BAAANQADCgYJBgABNQAECgUIGQAKABANAA==.Newfy:BAAANQAECgYICQAAAA==.',
Ni='Nightmoves:BAAANQADCgYIBgAAAA==.Ninjamage:BAAANQADCggIDgAAAA==.Nithendroz:BAAANQAECgQIBgAAAA==.Nity:BAAANQAECgEIAQAAAA==.',
No='Noctaurus:BAAANQADCgQJBAAAAA==.Nogini:BAAANQADCgcJBwAAAA==.Nomadhew:BAAANQAECggJCAAAAA==.Noraice:BAAANQABCgQIBwAAAA==.Notagain:BAACNQAFFIEOAAIDAAYKoBCzBQDWAQADAAYKoBCzBQDWAQA1AAQKgSYAAgMACQpaI4okABkDAAMACQpaI4okABkDAAAA.',
Ny='Nyuxx:BAAANQAECgEIAgAAAA==.',
Ob='Obake:BAAANQAECgQIBgAAAA==.',
Od='Odphijor:BAAANQAECggICAAAAA==.',
Og='Ogsmallz:BAAANQADCgcICwAAAA==.',
Or='Orangewhale:BAAANQAFFAIIAwAAAA==.Orondrus:BAAANQADCgMIAwAAAA==.',
Ox='Oxidation:BAAANQADCgQIBQAAAA==.',
Oz='Ozsome:BAAANQAECgUIDQAAAA==.',
Pa='Pallybob:BAAANQADCgUICQABNQADCggIHwABAAAAAA==.Pavo:BAABNQAECoEZAAMMAAcKbQ6bLgBwAQAMAAcKbQ6bLgBwAQAKAAMKFAZ0hwCDAAAAAA==.',
Pe='Pebbleshifts:BAAANQADCgcICAAAAA==.Peejean:BAAANQAECgEIAQAAAA==.Pey:BAAANQAECgQIBAABNQAECgkJIgAEAKcjAA==.Peycicle:BAABNQAECoEiAAIEAAkKpyOrEACLAwAEAAkKpyOrEACLAwAAAA==.Peystruction:BAAANQADCgYJBgABNQAECgkJIgAEAKcjAA==.',
Ph='Phantasm:BAAANQABCgIIAgAAAA==.Phlox:BAAANQAECgYIEgAAAA==.',
Pi='Pippa:BAAANQAECgYIEgAAAA==.',
Pl='Planett:BAABNQAECoEbAAMVAAcKVRlbUwDsAQAVAAcKVRlbUwDsAQAWAAYK6wsFkwBEAQAAAA==.',
Po='Poetuck:BAABNQAECoEcAAIFAAgKzhAPCwDfAQAFAAgKzhAPCwDfAQAAAA==.Pokeyruler:BAAANQADCgEIAQAAAA==.',
Pr='Proko:BAAANQAECgYIDwAAAA==.',
Qa='Qatka:BAAANQADCgUJCAAAAA==.',
Qu='Quiver:BAAANQAECgEIAQAAAA==.Quizmagic:BAAANQADCgMJAwAAAA==.',
Ra='Raein:BAAANQAECgUIEAAAAA==.Rainn:BAAANQAECgQICgAAAA==.Rainnsoul:BAAANQADCgEIAQAAAA==.Ralofurius:BAAANQADCgYIDAAAAA==.Rasril:BAAANQADCgIIAgAAAA==.',
Re='Redrighthand:BAAANQADCgMIAwAAAA==.Relwind:BAAANQADCgQIBAAAAA==.Rename:BAAANQAECgQIBAABNQAECgkJGAAEAC0fAA==.Reshtargorr:BAAANQABCgEIAQAAAA==.',
Ro='Roskolnikov:BAAANQAECgMIBQAAAA==.Rossa:BAAANQAECgMIAwAAAA==.',
Ru='Ruele:BAAANQAECgIIAgAAAA==.Ruenan:BAABNQAECoEpAAMSAAkK5CVFAgDaAwASAAkK5CVFAgDaAwATAAMK0RzyRAD+AAAAAA==.',
Sa='Sanbas:BAAANQAECgQIBQAAAA==.Sapthat:BAAANQAECgQIBAAAAA==.Sarthrity:BAAANQAFFAEIAQAAAA==.Satyrs:BAAANQADCgIIAgAAAA==.Savepebble:BAAANQAECgIIAgAAAA==.',
Sc='Scootsy:BAAANQAECgcIEwAAAA==.',
Se='Seirin:BAAANQAECgUIEAAAAA==.Seldiane:BAAANQADCggIFgAAAA==.Selendaa:BAAANQAECgUIDgAAAA==.Senadarra:BAAANQADCgYIBgAAAA==.Senastera:BAAANQADCgUIDAAAAA==.Sephandtotem:BAAANQAECgEJAQAAAA==.Sephron:BAAANQAECgIIBQAAAA==.Sethen:BAAANQAECgUIBwAAAA==.',
Sh='Shadowyhog:BAAANQADCggICAAAAA==.Shamalamadd:BAAANQAECgYIEAAAAA==.Shammology:BAAANQAECgcICgAAAA==.Shaollyn:BAAANQADCgYICQAAAA==.Shendralar:BAABNQAECoEiAAMJAAkKSBaJMADmAQAJAAkKnQ6JMADmAQAHAAcK+xXyGwDiAQAAAA==.Sheri:BAAANQAECgUIEAAAAA==.Shizam:BAAANQADCgYIBgAAAA==.Shlexie:BAABNQAECoEXAAMFAAgKkxbSCQACAgAFAAcKsxjSCQACAgAEAAYKiQ+5/wBoAQAAAA==.Shockless:BAABNQAECoEZAAMWAAgKFAz3gQBvAQAWAAcKxgr3gQBvAQAVAAEKnQGvGgEbAAAAAA==.Shotowkhann:BAABNQAECoEVAAIaAAcKmBBobQCeAQAaAAcKmBBobQCeAQAAAA==.',
Si='Sigmaboss:BAAANQADCgQIBAAAAA==.Silentpebble:BAAANQAECgcIEwAAAA==.Sillygoose:BAACNQAFFIEJAAMEAAQKgQyDKwDvAAAEAAMKSg6DKwDvAAAFAAEKJQeGEQBAAAA1AAQKgSIAAwQACQqCHa1kAKECAAQACQrcHK1kAKECAAUAAgq4F+ooAIgAAAAA.Sinderella:BAAANQABCgcIBwAAAA==.',
Sk='Skalar:BAAANQAECgIIAgAAAA==.Skodah:BAAANQAECgEIAQABNQAECgUIDAABAAAAAA==.',
So='Somnambula:BAAANQADCgUICgAAAA==.',
Sp='Sprocket:BAAANQADCgIJAgABNQAECgYICQABAAAAAA==.',
Sq='Squarey:BAAANQADCgYICgAAAA==.',
St='Stell:BAAANQADCggJJAAAAA==.Stinch:BAAANQADCgcIDAABNQAECgcIEQABAAAAAA==.Stovik:BAACNQAFFIEHAAIOAAMKcxheAwAGAQAOAAMKcxheAwAGAQA1AAQKgS4AAw4ACQrEIlkCAIYDAA4ACQrEIlkCAIYDABUAAgoEFG7tAF4AAAAA.',
Sv='Sventhebrave:BAAANQAECgMIBQAAAA==.',
Sw='Sweeneytod:BAAANQABCgMIAwAAAA==.',
Sy='Sykill:BAAANQADCgIIAgAAAA==.Sylus:BAAANQADCgEIAQAAAA==.',
Ta='Tahuruk:BAAANQABCgQIBAAAAA==.Takamura:BAAANQADCgUIBQAAAA==.Talena:BAAANQAECgIIAgAAAA==.Talleral:BAAANQAECgQIDgAAAA==.Tamanan:BAAANQADCggICAABNQADCggIEgABAAAAAA==.Taurgrim:BAAANQADCgQIAwAAAA==.Tavin:BAABNQAECoEbAAIYAAgKAhBoBwADAgAYAAgKAhBoBwADAgAAAA==.',
Te='Temaman:BAAANQADCggIEgAAAA==.Temamañ:BAAANQADCggIDAABNQADCggIEgABAAAAAA==.Terasha:BAAANQAECgYIBgAAAA==.',
Th='Thealtman:BAAANQADCgUIBQAAAA==.Thegreatmoo:BAAANQADCgQIBAAAAA==.',
Ti='Timaeus:BAABNQAECoEaAAIFAAgK2BWrCQAFAgAFAAgK2BWrCQAFAgAAAA==.Tinder:BAAANQADCgYIBQABNQAECggIGwAPABYkAA==.',
Tm='Tmbeesknees:BAAANQABCgQIBAAAAA==.',
To='Tokën:BAAANQADCgEIAQAAAA==.',
Tr='Trishi:BAAANQAECgQIBwAAAA==.',
Tw='Twirlwind:BAABNQAECoEcAAIbAAgKFyX4AgBgAwAbAAgKFyX4AgBgAwAAAA==.',
Ty='Tydrinor:BAAANQAECgEIAQAAAA==.',
Un='Unoblasto:BAABNQAECoEWAAIEAAgKZhOuowAaAgAEAAgKZhOuowAaAgAAAA==.',
Va='Valorash:BAABNQAECoEmAAMDAAcKFRuAcgAbAgADAAcKFRuAcgAbAgAGAAYKng/5LQBDAQAAAA==.Valorious:BAAANQADCgQIBQAAAA==.Valshadow:BAAANQADCgcIBwABNQAECgcIJgADABUbAA==.Vampirilla:BAAANQADCgEIAQAAAA==.Vatahlia:BAAANQADCggIEQAAAA==.',
Ve='Veleyna:BAAANQAECgIIBAAAAA==.Velinnari:BAAANQAECgUIBQAAAA==.Velintha:BAAANQAECgQJBgAAAA==.Ventise:BAAANQADCggIDQAAAA==.',
Vi='Violee:BAAANQAECgMIAwAAAA==.Vision:BAAANQADCgcIBwAAAA==.',
Vo='Vonderick:BAAANQABCgUIBQAAAA==.Voodoodog:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.',
Wa='Wargasm:BAAANQADCgMIAwABNQADCgYICQABAAAAAA==.Warrstomp:BAAANQADCgYIBwAAAA==.',
Wh='Whitewhale:BAAANQAECgYICAAAAA==.',
Xa='Xandaer:BAAANQADCgMIBAAAAA==.Xandaera:BAAANQABCgcICQAAAA==.Xandarion:BAAANQADCggIFAAAAA==.',
Xc='Xcïte:BAAANQAECgEIAwAAAA==.',
Xd='Xd:BAAANQADCgQJBAAAAA==.',
Yo='Yogeta:BAAANQADCgQIBAAAAA==.Yosh:BAAANQADCgIIAgAAAA==.',
Yu='Yuji:BAAANQAECgUICwAAAA==.',
Za='Zalectra:BAABNQAECoEYAAMSAAgKvCBcKQDTAgASAAgKvCBcKQDTAgATAAUKfQojRwDwAAAAAA==.Zamasû:BAAANQADCgUIBwAAAA==.Zarnie:BAAANQABCgEIAQAAAA==.',
Ze='Zelila:BAAANQAECgQIBgAAAA==.',
Zo='Zoioz:BAAANQADCgQIBwAAAA==.Zoras:BAAANQADCggICAAAAA==.',
['Ål']='Ålloria:BAAANQAECgIIAgABNQAECggIEgABAAAAAA==.',
['Ón']='Ónix:BAAANQAECgIIAgAAAA==.',
['Öd']='Ödínn:BAAANQADCgUIDAABNQADCgYICQABAAAAAA==.',
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
