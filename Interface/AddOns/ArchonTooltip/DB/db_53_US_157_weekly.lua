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

local lookup = {'Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Warlock-Destruction','Monk-Windwalker','Shaman-Elemental','Monk-Mistweaver','Priest-Shadow','DeathKnight-Blood','Druid-Balance','Warrior-Fury','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Frost','Warrior-Arms','Warlock-Affliction','Shaman-Enhancement','Hunter-BeastMastery','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Paladin-Retribution','Shaman-Restoration','Priest-Holy','DemonHunter-Havoc','Paladin-Holy','Hunter-Survival','DemonHunter-Devourer','Paladin-Protection','Priest-Discipline','Druid-Restoration','Evoker-Augmentation','Mage-Fire','Druid-Guardian','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aaralia:BAAANQAECgYIDAAAAA==.',
Ab='Abyssdark:BAABNQAECn9DAAIBAAoKVBtlKADjAgABAAoKVBtlKADjAgAAAA==.',
Ac='Accusation:BAACNQAFFH8PAAICAAUK4xaDBQDyAAACAAUK4xaDBQDyAAA1AAQKfxcAAgIACgo4FZ1IAPQBAAIACgo4FZ1IAPQBAAAA.',
Ak='Akadeus:BAAANQAECgIIAgAAAA==.',
Al='Alarielle:BAAANQAECgMICAABNQAECgkJOQADAOQXAA==.Altx:BAAANQABCgUIAwAAAA==.Alwaysdrunk:BAAANQAECgEIAQAAAA==.',
Am='Amirah:BAAANQADCgEIAgAAAA==.Ammathael:BAAANQAECgEJAQAAAA==.',
An='Anagela:BAAANQABCgUIBQABNQAECgQICAAEAAAAAA==.Anamarie:BAAANQAECgQIBQABNQAECgkJGQAFAEATAA==.Antipasta:BAAANQAECggICAAAAA==.',
Ar='Aramist:BAAANQADCggIJQAAAA==.',
As='Ashergreyson:BAAANQADCgYIBgAAAA==.Ashikahammer:BAAANQAECgYIDQABNQAECgkJIgADAJQgAA==.Ashtaroth:BAABNQAECn8fAAIBAAgKUwkjfgAuAQABAAgKUwkjfgAuAQABNQAECgkJOQADAOQXAA==.',
Az='Azraeth:BAAANQAECgYIEgABNQAECggIEQAEAAAAAA==.',
Ba='Bacon:BAAANQABCgMIAwABNQAECgcIEQAEAAAAAA==.Baehyun:BAAANQAECggIDQABNQAFFAoKMAAGAEIkAA==.Basou:BAAANQADCggICAAAAA==.Baspar:BAAANQADCgIIAgAAAA==.',
Be='Belanova:BAAANQADCgQIBAAAAA==.Belnathas:BAAANQADCggIHAAAAA==.',
Bl='Blamethemage:BAAANQAECgcICQABNQAECgoKQgAHAFcZAA==.Bloodbeard:BAAANQAECgYICAAAAA==.Bloodedge:BAAANQADCgIIBAAAAA==.',
Bo='Bohmbear:BAAANQADCgYICgAAAA==.Bomboy:BAAANQAECgEIAQABNQAECgQIBQAEAAAAAA==.',
Br='Brasha:BAAANQAECgcIBwAAAA==.Brentobox:BAABNQAECn8jAAIIAAcKbx/3DgDmAQAIAAcKbx/3DgDmAQAAAA==.Brugara:BAAANQADCggIFwAAAA==.',
Bu='Bungeholio:BAABNQAECn8YAAIJAAgKNAl1JgATAQAJAAgKNAl1JgATAQABNQAECgoKQgAHAFcZAA==.',
Ca='Camael:BAAANQAECgYIDwAAAA==.Cannelle:BAABNQAECn8ZAAIDAAkKLxHqCADbAQADAAkKLxHqCADbAQAAAA==.Carden:BAABNQAECn8jAAIKAAcKjCAoJwCaAQAKAAcKjCAoJwCaAQAAAA==.',
Ce='Cervantes:BAAANQAECgYIEQAAAA==.',
Ch='Charcyna:BAAANQAECgMICAABNQAFFAcIEwALAC0aAA==.Chardr:BAACNQAFFH8TAAILAAcKLRpEBQBRAgALAAcKLRpEBQBRAgA1AAQKfyYAAgsACQqzJfIZAPgCAAsACQqzJfIZAPgCAAAA.Chillywillie:BAABNQAECn8ZAAIMAAYKEQqxGwDtAAAMAAYKEQqxGwDtAAAAAA==.Chrodne:BAAANQAECgEIAgAAAA==.Chucknorrîs:BAAANQAECgYIDwAAAA==.',
Ci='Cigam:BAAANQAECgUIDQAAAA==.',
Cl='Clintbarton:BAABNQAECn9QAAINAAoKdQ7SGQB2AQANAAoKdQ7SGQB2AQAAAA==.',
Cr='Crûtch:BAAANQADCggIDgAAAA==.',
Ct='Cthullu:BAAANQADCggICAAAAA==.',
Cu='Culebra:BAABNQAECn8uAAMOAAoKuxYmJQBhAgAOAAkKzxYmJQBhAgAPAAUKdhMcggDHAAAAAA==.',
['Cø']='Cøldshoulder:BAABNQAECn8mAAIQAAkKOBclMwATAgAQAAkKOBclMwATAgAAAA==.',
Da='Dabi:BAAANQADCgcIIAAAAA==.Daehyun:BAAANQAECggIDQABNQAFFAoKMAAGAEIkAA==.Danceofdeath:BAAANQAECgYIBwABNQAFFAUICQARADgZAA==.Dane:BAABNQAECn8fAAIRAAkKOgy5dgBnAQARAAkKOgy5dgBnAQAAAA==.Darcmatter:BAABNQAECn8eAAQBAAoKpBwAaQAhAgABAAgKdxwAaQAhAgAFAAMKahyZNQDsAAASAAIKqx/jHQBXAAAAAA==.Darthmo:BAAANQADCgMIAwAAAA==.',
De='Deadtrap:BAAANQABCggIDwAAAA==.Deathsend:BAAANQADCgYICAAAAA==.Deepsicks:BAABNQAECn8pAAITAAoKBxo3DgCIAgATAAoKBxo3DgCIAgAAAA==.Deepstate:BAAANQAECgUICAAAAA==.Deimos:BAAANQADCgYIBgABNQAECgYICAAEAAAAAA==.Demonaholio:BAAANQAECgQIBAABNQAECgoKQgAHAFcZAA==.Demonäde:BAAANQADCgUIAgAAAA==.',
Di='Dima:BAABNQAECn82AAIUAAkKzxfGWABpAgAUAAkKzxfGWABpAgAAAA==.Dithy:BAAANQAECgUIEwAAAA==.',
Dk='Dkrmk:BAAANQADCgMIAgAAAA==.Dktelli:BAABNQAECn8UAAMQAAgKPhGnSgCQAQAQAAgKPhGnSgCQAQAKAAQKgAcWoACYAAABNQAECgoKUgATAIcjAA==.',
Dn='Dne:BAAANQADCggIDgABNQAECgkJHwARADoMAA==.',
Do='Donavon:BAAANQAECgcIDwAAAA==.Donutjelly:BAABNQAECn8hAAILAAgKrRhUKACDAQALAAgKrRhUKACDAQAAAA==.Dorivandor:BAAANQAECgUICgAAAA==.Dornnbryda:BAAANQADCggIDgABNQAECgkJIwANAB4SAA==.',
Dr='Drackothyr:BAABNQAECn8jAAMVAAkK0xoECQC6AQAVAAkK0xoECQC6AQAWAAMKKwXvRAB7AAAAAA==.Dreamweavver:BAAANQADCgQIBAAAAA==.Drumark:BAAANQADCgMIAwAAAA==.',
Du='Dugmaren:BAAANQABCggICAABNQAFFAQICAAPAFIWAA==.Dumpsterfire:BAAANQAECgcIBwAAAA==.',
Dw='Dwastring:BAABNQAECn8nAAIUAAkKBxfcYgBQAgAUAAkKBxfcYgBQAgAAAA==.',
Dy='Dyrale:BAAANQADCgYIGwAAAA==.',
Ek='Eknivar:BAAANQAECgcIDQABNQAECgoKPgAXAMUcAA==.',
Er='Erebus:BAAANQAECgQIBAAAAA==.Erragorn:BAABNQAECn8iAAMMAAYKlxWBFgA0AQAMAAUKvhSBFgA0AQARAAYKEhS2pAD8AAAAAA==.',
Ev='Evisa:BAABNQAECn8gAAIXAAgKrwdvqQAmAQAXAAgKrwdvqQAmAQAAAA==.Evokholio:BAAANQAECgIIAwAAAA==.',
['Eö']='Eöath:BAAANQAECgEIAQAAAA==.',
Fa='Falaurenta:BAAANQADCgMIBgAAAA==.',
Fe='Fearzlol:BAAANQAECgIIAgABNQAFFAQICAAPAFIWAA==.Fedahyin:BAAANQADCgUIBQABNQADCggIDgAEAAAAAA==.Feidao:BAAANQAECgQIDgAAAA==.Feralith:BAAANQADCgMIAQAAAA==.',
Fo='Foshizzle:BAAANQABCgIIAgAAAA==.',
Fu='Funkenfox:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëânòr:BAAANQADCgUIBQAAAA==.',
Ga='Gailinn:BAABNQAECn8eAAIYAAcKrgW8FwH4AAAYAAcKrgW8FwH4AAAAAA==.',
Gh='Ghlen:BAAANQADCgEIAQAAAA==.',
Go='Gooraah:BAAANQADCgUIBQABNQADCgYICQAEAAAAAA==.Gorash:BAAANQAECggIEQAAAA==.',
Gr='Greggd:BAAANQADCgIIAgABNQAECgoKNAAZAEQdAA==.Greggdshami:BAABNQAECn80AAIZAAoKRB1BEgD8AgAZAAoKRB1BEgD8AgAAAA==.Gretagobbo:BAAANQAECgQIBAABNQAECgYICAAEAAAAAA==.',
Gu='Gundamus:BAAANQADCgYIBgAAAA==.Gurney:BAAANQADCgYIDAABNQADCggIDgAEAAAAAA==.Guthrum:BAAANQADCgQIBwAAAA==.',
Gw='Gwenaelle:BAAANQAECgYIBgAAAA==.',
Ha='Halorah:BAAANQADCgYICQAAAA==.',
He='Healmonger:BAACNQAFFH8IAAIaAAQKbR1hEABjAQAaAAQKbR1hEABjAQA1AAQKf18AAxoACgpdJNkQAEADABoACgpdJNkQAEADAAkABwouCR8vANYAAAAA.Hekili:BAAANQAECgUIDQAAAA==.Helgrin:BAAANQADCgYIBgAAAA==.Heruin:BAAANQAECggIEgAAAA==.',
Hi='Hictor:BAAANQADCgMIAwAAAA==.',
Ho='Holly:BAAANQAECgQIBQAAAA==.Holyomega:BAAANQADCgUIBQAAAA==.Holypackin:BAAANQAECgEIAgABNQAECgQIBQAEAAAAAA==.Hongdou:BAAANQAECgQIAwAAAA==.Horse:BAACNQAFFH8pAAIaAAcKRQFwDgB8AQAaAAcKRQFwDgB8AQA1AAQKf0YAAhoACgpHDVBqAN8BABoACgpHDVBqAN8BAAAA.Hourzero:BAAANQAECgEIAQAAAA==.',
Ia='Iammyscars:BAACNQAFFH8OAAIbAAUKDRJRBwAyAQAbAAUKDRJRBwAyAQA1AAQKfz0AAhsACgr8IOgLAMACABsACgr8IOgLAMACAAAA.',
Ic='Icu:BAAANQAECgcIDwAAAA==.',
Ik='Ikillu:BAABNQAECn8rAAITAAgKFx2XCgBAAgATAAgKFx2XCgBAAgAAAA==.',
Il='Ilis:BAAANQAECgQICgAAAA==.',
Ja='Jadawin:BAAANQABCgIIAgAAAA==.Jaiminvi:BAAANQADCgEIAQAAAA==.Jasnahh:BAAANQAECgQICQABNQAECgYICgAEAAAAAA==.Jaylas:BAAANQADCgEIAQABNQAECggILgAcAAMgAA==.',
Jo='Joeexotíc:BAACNQAFFH8OAAQdAAUK4yQkAACuAQAdAAUK4yQkAACuAQAUAAEKMSGgJABfAAANAAEKixBRIwBHAAA1AAQKfzIABB0ACgqGJg8AAJ4DAB0ACgqGJg8AAJ4DAA0ABQrFExtBAEwBABQAAwoUHKIEAfwAAAAA.',
Ju='Jun:BAACNQAFFH8cAAIbAAcK2SJsAwBPAgAbAAcK2SJsAwBPAgA1AAQKf0YAAxsACgqeJq0AAPwDABsACgqeJq0AAPwDAB4ACAqAIgMdAGwCAAAA.Junfan:BAAANQAECggIEAAAAA==.',
Ka='Kandros:BAAANQABCgUIBwAAAA==.Kasumaus:BAABNQAECn8dAAQQAAkKtgYIYQAhAQAQAAkK4AUIYQAhAQACAAQK5AYipwCqAAAKAAIKvwQYuABYAAAAAA==.',
Ke='Kelly:BAAANQADCggICAAAAA==.Kennifer:BAAANQADCggICQAAAA==.Kenshindune:BAAANQADCgQIBAAAAA==.Keragan:BAAANQADCgEJAQAAAA==.',
Kh='Khalyeesi:BAAANQADCgIIAwAAAA==.Khandris:BAAANQABCggIEwAAAA==.Khazjek:BAAANQADCgYICAAAAA==.Khephris:BAABNQAECn85AAIDAAkK5BefCwAGAgADAAkK5BefCwAGAgAAAA==.',
Ki='Kiralni:BAAANQAECgQIAwAAAA==.',
Kn='Knivex:BAABNQAECn8+AAMXAAoKxRzwnABHAgAXAAkKEBzwnABHAgADAAMK4h1eHQADAQAAAA==.',
Ko='Koryann:BAABNQAECn82AAIfAAoKwRYtDgASAgAfAAoKwRYtDgASAgAAAA==.Kosel:BAAANQAECgcIEAAAAA==.Kova:BAABNQAECn8mAAIHAAkKzBByQgCQAQAHAAkKzBByQgCQAQAAAA==.',
Kr='Kramm:BAAANQAECgQIAgAAAA==.Krazyplaya:BAAANQAECgEIAQAAAA==.',
Ky='Kyrise:BAABNQAECn8iAAIZAAoKIheRIwB2AgAZAAoKIheRIwB2AgAAAA==.',
La='Lambo:BAAANQAECgQJBAAAAA==.Landam:BAABNQAECn8dAAIYAAgKVAm/tgAkAQAYAAgKVAm/tgAkAQAAAA==.',
Le='Leap:BAAANQADCgMIAwABNQAECgoKMwAeAHAWAA==.Leviticus:BAAANQADCgQIBAAAAA==.',
Li='Lifeaura:BAACNQAFFH8VAAIgAAYKsBC1AADhAQAgAAYKsBC1AADhAQA1AAQKfzUAAiAACQr3ICABAFcDACAACQr3ICABAFcDAAAA.Lifesmage:BAAANQAECggIBgAAAA==.Lifesshaman:BAAANQAECggICAAAAA==.Lightbläster:BAAANQAECgIIBAAAAA==.Lightrider:BAAANQADCgYICwAAAA==.Linesta:BAAANQADCgEIAQAAAA==.Lionroar:BAACNQAFFH8TAAIhAAcKTRxmAwASAgAhAAcKTRxmAwASAgA1AAQKfzkAAyEACgouI+AHAEYDACEACgouI+AHAEYDAAsAAgp0DYhnAGUAAAAA.Littleguy:BAABNQAECn8jAAIHAAcKuwOUfwDYAAAHAAcKuwOUfwDYAAAAAA==.',
Ll='Llaothtaed:BAAANQAECggIBgAAAA==.',
Lo='Lochannis:BAABNQAECn8YAAIMAAoKag98CgCnAQAMAAoKag98CgCnAQAAAA==.Logi:BAABNQAECn8aAAMfAAoKNwecKAD5AAAfAAoKLgecKAD5AAAYAAMKoAVbRQFXAAAAAA==.Lokalock:BAAANQAECgUIDwABNQAECgoKUgATAIcjAA==.Lonee:BAAANQADCgIIAgAAAA==.Lorellei:BAABNQAECn8iAAIaAAYK/A1QqAAcAQAaAAYK/A1QqAAcAQAAAA==.Lothgow:BAAANQAECgEIAgAAAA==.',
Lu='Luxus:BAAANQAECgMIBAAAAA==.',
['Lâ']='Lân:BAACNQAFFH8IAAMPAAQKUhY5DQD8AAAPAAQKUhY5DQD8AAAOAAIKHRElCQCHAAA1AAQKfxsAAw8ACQpgHrMPAN4CAA8ACQrFHbMPAN4CAA4ACAq4GPAlAF0CAAAA.',
Ma='Maelynn:BAAANQADCgUIBQAAAA==.Magchro:BAAANQADCgQIBAABNQAECgEIAgAEAAAAAA==.Manticor:BAAANQADCgcIBgAAAA==.Martyglaive:BAABNQAECn8oAAIbAAgK2RZ1IADMAQAbAAgK2RZ1IADMAQAAAA==.Matteas:BAABNQAECn8UAAIYAAcKgxxTkgAAAgAYAAcKgxxTkgAAAgAAAA==.',
Me='Menionblue:BAAANQADCgUIBQAAAA==.Mew:BAAANQAECgUIDwAAAA==.',
Mf='Mfdoom:BAABNQAECn9DAAQBAAoKzyCnKwA1AgABAAkKySCnKwA1AgASAAQKxxq1FwDQAAAFAAMKfBV8PgDIAAABNQADCgIIBAAEAAAAAA==.',
Mi='Mizrey:BAACNQAFFH8FAAIQAAMK2w5uHABOAAAQAAMK2w5uHABOAAA1AAQKfy4AAhAACgqNH9cSAPcCABAACgqNH9cSAPcCAAAA.Mizukisakura:BAAANQAECgQIBAAAAA==.',
Mo='Mograins:BAABNQAECn9CAAMFAAoK/B9HDQAkAgABAAkKFx9mJQBTAgAFAAYKXSFHDQAkAgAAAA==.Monzcarro:BAAANQADCggICwAAAA==.Mordar:BAAANQADCgUIBwAAAA==.Morgainne:BAAANQAECgUIEwAAAA==.Mortmor:BAAANQAECgYICwAAAA==.',
Ms='Mstrsinister:BAAANQADCgcIBwAAAA==.',
Mu='Muffinn:BAABNQAECn8qAAIUAAgKOw2JmQDUAQAUAAgKOw2JmQDUAQAAAA==.Mursê:BAAANQAECggICAAAAA==.',
My='Mymdos:BAABNQAECn9MAAIRAAoKgSLFFwDXAgARAAoKgSLFFwDXAgABNQABCgIIAgAEAAAAAA==.Myrmidonn:BAAANQADCgYICgAAAA==.',
['Mä']='Mästérdòn:BAAANQAECgcIDAAAAA==.',
['Må']='Måsterdon:BAABNQAECn8aAAIfAAYKEQzOOQCZAAAfAAYKEQzOOQCZAAAAAA==.',
['Mô']='Môiraine:BAACNQAFFH8IAAIcAAQKcRQcDQA5AQAcAAQKcRQcDQA5AQA1AAQKfxwAAhwACQo0GzQdAKICABwACQo0GzQdAKICAAAA.',
Ne='Nercos:BAAANQAECgEIAQABNQAFFAIIAgAEAAAAAA==.Nercqt:BAAANQAFFAIIAgAAAA==.Neverborn:BAAANQAECgcIEgAAAA==.',
Ni='Niame:BAAANQAECgUIDAAAAA==.Nice:BAAANQAECgQIBAAAAA==.Nitraina:BAABNQAECn8WAAMDAAgKHgInMwBuAAAXAAcKGwF8jgGpAAADAAYKeAInMwBuAAAAAA==.Niyabelle:BAABNQAECn80AAMPAAoKmB3IJQA6AgAPAAoKmB3IJQA6AgAOAAcKUhIbRAC4AQAAAA==.',
No='Noggenfloggr:BAAANQAECgUICAAAAA==.Nomesis:BAAANQAECgEIAQAAAA==.Norita:BAAANQADCgMIAwAAAA==.',
Ny='Nyxth:BAAANQADCgYIBgAAAA==.',
Oa='Oakmane:BAAANQABCgEIAQABNQAECggIEQAEAAAAAA==.',
Od='Odïn:BAAANQADCgYIDAAAAA==.',
Ol='Oleevia:BAABNQAECn9DAAIJAAoKXBrGCwB1AgAJAAoKXBrGCwB1AgAAAA==.',
Om='Omgdingers:BAAANQAECgYICAABNQAECgoKGQAQAK8bAA==.',
On='Oneshót:BAAANQADCgYICAABNQAECgcIFQAaABkVAA==.Oneth:BAAANQAECgIIAgABNQAECgUIEQAEAAAAAA==.',
Or='Oraxia:BAAANQAECgEIAQABNQAECgYICAAEAAAAAA==.Ords:BAAANQABCgYICAABNQAECgQIBQAEAAAAAA==.Orgdynamite:BAAANQAECgcICgABNQAFFAcIKQAHANccAA==.Orgsham:BAACNQAFFH8pAAMHAAcK1xzBAwCmAQAHAAcK1xzBAwCmAQATAAEKSBfiBwBTAAA1AAQKfz8AAwcACgq9JNMNAHoDAAcACgq9JNMNAHoDABMABAozFwsjACoBAAAA.',
Pa='Paedragon:BAAANQAECgUIEQAAAA==.Paimon:BAAANQADCgYIBgAAAA==.Paladareian:BAABNQAECn8uAAIcAAgKAyC+MgCaAgAcAAgKAyC+MgCaAgAAAA==.',
Pe='Pej:BAACNQAFFH8pAAQVAAcK4xfCBwAKAQAiAAUKdhJoBgAgAQAVAAQKXxDCBwAKAQAWAAQKPgoNDADiAAA1AAQKf0kABBUACgrBHScPAGgCABUACQoJHicPAGgCABYABwpPFwgdAPsBACIABgrIGnwLAKcBAAAA.Pejbolt:BAAANQADCgcICgABNQAFFAcIHAAbANkiAA==.',
Ph='Phenomenon:BAAANQAECgUIBQABNQAECgkJGQAFAEATAA==.Phoenixa:BAAANQAECgEIAQAAAA==.',
Pl='Plus:BAAANQAECgcICwAAAA==.',
Po='Powerslavé:BAACNQAFFH8JAAIRAAUKOBmvEgDqAAARAAUKOBmvEgDqAAA1AAQKfzkAAhEACgoQI7MOABIDABEACgoQI7MOABIDAAAA.',
Pr='Priestitoot:BAAANQAECgMIBAAAAA==.Proust:BAAANQADCggIDgAAAA==.',
Pu='Pumkinhead:BAABNQAECn8pAAIHAAoK2g2mYwD2AQAHAAoK2g2mYwD2AQAAAA==.',
Py='Pyromania:BAABNQAECn8ZAAIFAAkKQBMBBACrAQAFAAkKQBMBBACrAQAAAA==.',
['Pä']='Pä:BAAANQADCgMIAQAAAA==.',
Ra='Raiden:BAABNQAECn8sAAIYAAkKUg/KiQB4AQAYAAkKUg/KiQB4AQAAAA==.Rat:BAAANQABCgIIAgAAAA==.Rauck:BAAANQAECgIIAwABNQAECgYICAAEAAAAAA==.',
Re='Rentacat:BAAANQAECgUICAAAAA==.Retropâlly:BAAANQADCgMIAwAAAA==.Revoker:BAAANQADCgUICAABNQAECgoKKAAUAN4YAA==.',
Ro='Rogi:BAAANQAECgUICAABNQABCgIIAgAEAAAAAA==.',
['Rö']='Römana:BAABNQAECn8hAAIUAAkKAw4inADPAQAUAAkKAw4inADPAQAAAA==.',
Sa='Sanguinaris:BAAANQAECgEIAQABNQAECggIEQAEAAAAAA==.Sappinbubs:BAAANQAECgEIAQABNQAECgQIBQAEAAAAAA==.Sareya:BAAANQABCggIDwAAAA==.Sataanic:BAAANQAECgUIBwAAAA==.Satyrical:BAABNQAECn8tAAQQAAoKyRTlKgDLAQACAAgKzhXwSgDpAQAQAAoKzg7lKgDLAQAKAAIKbAvXtwBYAAAAAA==.',
Sc='Scfy:BAAANQAECgUIBQABNQAFFAUICAAKADINAA==.Scorch:BAABNQAECn8UAAIXAAcKuRXZ0QDjAQAXAAcKuRXZ0QDjAQAAAA==.',
Se='Sedrayn:BAAANQAECgYIBwAAAA==.Selatha:BAAANQABCgIIAgABNQAFFAYIEAAXAAEaAA==.Selystine:BAAANQADCgUICAAAAA==.Semaj:BAAANQADCgcIBwAAAA==.Sergantis:BAAANQADCggIDgAAAA==.',
Sh='Shagee:BAAANQAECgEIAQAAAA==.Shamwowolio:BAABNQAECn9CAAIHAAoKVxnmHwBFAgAHAAoKVxnmHwBFAgAAAA==.Shayd:BAABNQAECn8oAAQUAAoK3hgwVwBtAgAdAAgKGBccBQB6AgAUAAkKvhgwVwBtAgANAAMKJRixUwDYAAAAAA==.Shigz:BAAANQADCggICQAAAA==.Shirokyu:BAAANQADCggICAAAAA==.Shirra:BAAANQADCggIDwAAAA==.Shirraz:BAABNQAECn8pAAIeAAgKrgngJgAqAQAeAAgKrgngJgAqAQAAAA==.Sho:BAAANQAECgcIEQAAAA==.Shroomicide:BAAANQAECggIBgAAAA==.',
Si='Sicaris:BAAANQADCgYICgABNQAECggIEQAEAAAAAA==.Sicksdeep:BAACNQAFFH8PAAMRAAUKrg9MFgDSAAARAAQKrg9MFgDSAAAMAAEKAABsBgBEAAA1AAQKfz8AAxEACgrrH+0cALgCABEACgrrH+0cALgCAAwAAQoZHq0jAFgAAAAA.Sigürd:BAAANQADCgEIAQAAAA==.Silverblade:BAAANQADCgEIAQAAAA==.Silverstorm:BAABNQAECn8cAAIUAAYKkQek3ABHAQAUAAYKkQek3ABHAQAAAA==.',
Sk='Skÿe:BAABNQAECn82AAINAAoKhxonDgAvAgANAAoKhxonDgAvAgAAAA==.',
Sl='Slamma:BAACNQAFFH8nAAIRAAcKNSQtBADwAQARAAcKNSQtBADwAQA1AAQKf1YAAhEACgqdJo0EANIDABEACgqdJo0EANIDAAAA.Slappin:BAAANQAECgIIBAABNQAECgQIBQAEAAAAAA==.Slappinbubs:BAAANQAECgQIBQAAAA==.Slicedbreád:BAACNQAFFH8rAAMZAAcKhhHKCwCQAQAZAAYKBg7KCwCQAQAHAAUKDRizCgACAQA1AAQKf0IAAwcACgopI4AJABcDAAcACgopI4AJABcDABkACgohGPFOACkCAAE1AAQKAQgBAAQAAAAA.',
Sm='Smokadaganga:BAABNQAECn8WAAMjAAkKqwmmBABXAQAjAAYK1gumBABXAQAXAAcKWwU/KgFFAQAAAA==.',
So='Sols:BAAANQAECgYIDQABNQAFFAUICQARADgZAA==.Sondirion:BAABNQAECn8jAAINAAkKHhLjFgCeAQANAAkKHhLjFgCeAQAAAA==.Soulancer:BAAANQAECgQIBAABNQAECggIEQAEAAAAAA==.Sowet:BAAANQAECgIIAgAAAA==.',
Sp='Speoghii:BAABNQAECn8mAAIBAAoKnhrFRwB7AgABAAoKnhrFRwB7AgAAAA==.Spifftreebug:BAABNQAECn9BAAMLAAoKpBEWKwBvAQALAAkKTg8WKwBvAQAhAAkKOQnzKQBVAQAAAA==.Sprinklez:BAABNQAECn8bAAITAAcK0hv1FAB/AQATAAcK0hv1FAB/AQAAAA==.',
St='Steelerschic:BAABNQAECn8aAAIHAAYK7AMwogCQAAAHAAYK7AMwogCQAAAAAA==.Stormleader:BAACNQAFFH8IAAIhAAUKewZuCAAaAQAhAAUKewZuCAAaAQA1AAQKfz8AAyEACgpSGTsWAJICACEACgpSGTsWAJICACQAAQoAADN2ABMAAAAA.',
Su='Surge:BAAANQAECgUIDAAAAA==.',
Ta='Tai:BAABNQAECn82AAIlAAoKTRoXCQANAgAlAAoKTRoXCQANAgAAAA==.Tainema:BAAANQAECgIIBAAAAA==.Tankguywowie:BAAANQAECgUIBQABNQAFFAYIDgALAGQLAA==.Taurriel:BAAANQAECgYIEAAAAA==.Tazzm:BAABNQAECn8kAAINAAgK2gRGQABSAQANAAgK2gRGQABSAQAAAA==.',
Te='Teranok:BAABNQAECn8ZAAQmAAkKGhezEQDLAQAmAAgKIRmzEQDLAQAGAAYKZBFZPAAzAQAIAAEK1gFHVQAfAAAAAA==.Terzal:BAAANQADCgYIBgAAAA==.',
Th='Thalel:BAAANQAECgQIDgAAAA==.Theacused:BAABNQAECn8ZAAIXAAoK0xmCTAADAgAXAAoK0xmCTAADAgABNQAFFAUIDwACAOMWAA==.Them:BAAANQADCgIIAgABNQAECgEIAQAEAAAAAA==.Thoir:BAACNQAFFH8pAAIZAAcKSyRWAQDGAgAZAAcKSyRWAQDGAgA1AAQKf0YAAhkACgrmJfwGAIsDABkACgrmJfwGAIsDAAE1AAUUBwgpABoARQEA.Thorodinson:BAAANQAECgUICQAAAA==.',
Ti='Tipsylorcet:BAABNQAECn8hAAImAAkKDhsaBwDHAQAmAAkKDhsaBwDHAQAAAA==.',
Tk='Tkrain:BAAANQADCggIIAAAAA==.',
Tr='Traen:BAAANQADCggICAAAAA==.Trashbull:BAAANQAECggIAgAAAA==.Tricktickler:BAAANQAECgUIEwAAAA==.Troy:BAAANQADCgUIBQAAAA==.',
Tu='Tuskani:BAAANQABCggIGgAAAA==.',
Ty='Tybird:BAABNQAECn8/AAIQAAoKxR0vGQDBAgAQAAoKxR0vGQDBAgAAAA==.Tyranisv:BAAANQADCgMIAwAAAA==.',
Ul='Ulsull:BAAANQADCgcIEAABNQADCggIDgAEAAAAAA==.Ulybonez:BAEBNQAECn8VAAMPAAkKchNsYQA1AQAOAAgKag/xVQBjAQAPAAgKdQ1sYQA1AQABNQAFFAcIKQAJAP8gAA==.Ulyssi:BAECNQAFFH8pAAIJAAcK/yAaAgDkAQAJAAcK/yAaAgDkAQA1AAQKf0MAAgkACgoGJiMDAKkDAAkACgoGJiMDAKkDAAAA.',
Um='Ummpatas:BAAANQAECgEIAQAAAA==.',
Us='Usseel:BAAANQADCgMIAwAAAA==.',
['Uñ']='Uñàble:BAAANQADCgIIAgAAAA==.',
Va='Valymus:BAAANQADCgIIAgABNQAECgoKKAAUAN4YAA==.Vandagylon:BAAANQADCgYIDAAAAA==.Vandals:BAAANQAECgcIEAAAAA==.',
Ve='Ven:BAABNQAECn8jAAIJAAkKQgelIwArAQAJAAkKQgelIwArAQAAAA==.Ver:BAAANQADCgMIAQAAAA==.',
Vo='Voltaire:BAAANQADCgIIAgAAAA==.',
Wa='Walle:BAAANQADCgEIAQAAAA==.Wankstar:BAAANQAECgEIAQABNQAECgQIBQAEAAAAAA==.Wargas:BAAANQABCgIIAgAAAA==.Warvein:BAABNQAECn8gAAMRAAkK/A8CjwD2AQARAAkK/A8CjwD2AQAlAAQKMAdwNACTAAAAAA==.',
We='Weehunt:BAABNQAECn8mAAIUAAoKcg4JYwC4AQAUAAoKcg4JYwC4AQAAAA==.Weeshami:BAAANQADCgMIAwAAAA==.',
Wh='Whillia:BAAANQADCgMIAwAAAA==.',
Wi='Wicah:BAABNQAECn8eAAIaAAcKdxo+PgAJAgAaAAcKdxo+PgAJAgAAAA==.Wicka:BAABNQAECn87AAIZAAkKeSLkFADkAgAZAAkKeSLkFADkAgAAAA==.Widowblade:BAAANQAECgYICwAAAA==.Wildriver:BAABNQAECn8XAAIhAAgKfBiaKQDSAQAhAAgKfBiaKQDSAQAAAA==.Willferàl:BAAANQADCgMIAwAAAA==.',
Xa='Xaehyun:BAACNQAFFH8wAAIGAAoKQiQiAABbAwAGAAoKQiQiAABbAwA1AAQKfyoAAgYACgoJJwcAAKYDAAYACgoJJwcAAKYDAAAA.Xandrelar:BAAANQAECgQIBAABNQAECgoKKAAUAN4YAA==.',
Xm='Xmrpdk:BAACNQAFFH8pAAIKAAcKKiTrAgBtAgAKAAcKKiTrAgBtAgA1AAQKf0YAAgoACgp0Jv8BANQDAAoACgp0Jv8BANQDAAAA.Xmrppally:BAAANQAECgcICAABNQAFFAcIKQAKACokAA==.',
Xy='Xy:BAAANQADCggICAAAAA==.',
Ya='Yarina:BAAANQADCgUIBQAAAA==.',
Yo='Yoyiek:BAACNQAFFH8OAAILAAYKZAu0FAAhAQALAAYKZAu0FAAhAQA1AAQKfzEAAwsACgpXHtcMALYCAAsACgpXHtcMALYCACQAAwq6AjBSAFoAAAAA.',
Za='Zalynn:BAAANQAECgEIAQAAAA==.Zanne:BAACNQAFFH8IAAINAAQKVRR3DgC1AAANAAQKVRR3DgC1AAA1AAQKfy0AAg0ACgo1H98XAJkCAA0ACgo1H98XAJkCAAAA.Zaraele:BAAANQAECgEIAQAAAA==.Zarthul:BAAANQAECgQICAAAAA==.',
Ze='Zehara:BAAANQADCgMIBAAAAA==.Zenori:BAAANQADCggIDgAAAA==.',
Zh='Zhenyu:BAAANQADCgQIBAABNQAECggIEQAEAAAAAA==.',
Zi='Ziely:BAAANQADCgMIAwAAAA==.',
Zl='Zlot:BAECNQAFFH8pAAMUAAcKah7EDACGAQAUAAUKBB7EDACGAQANAAQKFCC3CgDpAAA1AAQKf0YAAxQACgrYJW8iAA0DABQACAoAJm8iAA0DAA0ACQroIDQZAI0CAAAA.',
Zu='Zulani:BAAANQAECgUIBQAAAA==.',
['Õn']='Õneshot:BAABNQAECn8VAAIaAAcKGRVJbwDQAQAaAAcKGRVJbwDQAQAAAA==.',
['Øñ']='Øñêshot:BAAANQADCggIEwABNQAECgcIFQAaABkVAA==.',
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
