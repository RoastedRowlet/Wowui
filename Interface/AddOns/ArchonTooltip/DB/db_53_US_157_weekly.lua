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

local lookup = {'Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Monk-Windwalker','Shaman-Elemental','Monk-Mistweaver','Priest-Shadow','DeathKnight-Blood','Druid-Balance','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Frost','Warrior-Arms','Warlock-Destruction','Warlock-Affliction','Shaman-Enhancement','Hunter-BeastMastery','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Warrior-Fury','Paladin-Retribution','Shaman-Restoration','Priest-Holy','DemonHunter-Havoc','Paladin-Holy','Hunter-Survival','DemonHunter-Devourer','Paladin-Protection','Priest-Discipline','Druid-Restoration','Evoker-Augmentation','Mage-Fire','Druid-Guardian','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aaralia:BAAANQAECgUIDAAAAA==.',
Ab='Abyssdark:BAABNQAECn89AAIBAAoKVBtlKADjAgABAAoKVBtlKADjAgAAAA==.',
Ac='Accusation:BAACNQAFFH8NAAICAAUKIhMqBQDqAAACAAUKIhMqBQDqAAA1AAQKfxYAAgIACgovFfAgAGwBAAIACgovFfAgAGwBAAAA.',
Ak='Akadeus:BAAANQAECgIIAgAAAA==.',
Al='Alarielle:BAAANQAECgMICAABNQAECgcIMQADAB4dAA==.Altx:BAAANQABCgUIAwAAAA==.Alwaysdrunk:BAAANQAECgEIAQAAAA==.',
Am='Amirah:BAAANQADCgEIAgAAAA==.Ammathael:BAAANQAECgEJAQAAAA==.',
An='Anagela:BAAANQABCgUIBQABNQAECgMIBwAEAAAAAA==.Anamarie:BAAANQAECgQIBQABNQAECggIDwAEAAAAAA==.Antipasta:BAAANQAECggICAAAAA==.',
Ar='Aramist:BAAANQADCgYIIwAAAA==.',
As='Ashergreyson:BAAANQADCgYIBgAAAA==.Ashikahammer:BAAANQAECgYIDQABNQAECgkJIgADAJQgAA==.Ashtaroth:BAABNQAECn8ZAAIBAAgKbgjGgQDxAAABAAgKbgjGgQDxAAABNQAECgcIMQADAB4dAA==.',
Az='Azraeth:BAAANQAECgYIEgABNQAECggICgAEAAAAAA==.',
Ba='Bacon:BAAANQABCgMIAwABNQAECgYICwAEAAAAAA==.Baehyun:BAAANQAECggIDQABNQAFFAkJLgAFAIwkAA==.Basou:BAAANQADCggICAAAAA==.',
Be='Belanova:BAAANQADCgQIBAAAAA==.Belnathas:BAAANQADCggIHAAAAA==.',
Bl='Blamethemage:BAAANQAECgUIBgABNQAECgoKOgAGAHIXAA==.Bloodbeard:BAAANQAECgYICAAAAA==.Bloodedge:BAAANQADCgIIBAAAAA==.',
Bo='Bohmbear:BAAANQADCgYIBgAAAA==.Bomboy:BAAANQAECgIIAQAAAA==.',
Br='Brasha:BAAANQAECgcIBwAAAA==.Brentobox:BAABNQAECn8eAAIHAAcKZR/mCwDZAQAHAAcKZR/mCwDZAQAAAA==.Brugara:BAAANQADCggIFwAAAA==.',
Bu='Bungeholio:BAABNQAECn8UAAIIAAgKNAkvHgAXAQAIAAgKNAkvHgAXAQABNQAECgoKOgAGAHIXAA==.',
Ca='Camael:BAAANQAECgYIDwAAAA==.Cannelle:BAABNQAECn8VAAIDAAkKnBDZBwCpAQADAAkKnBDZBwCpAQAAAA==.Carden:BAABNQAECn8eAAIJAAcKSB97IgCAAQAJAAcKSB97IgCAAQAAAA==.',
Ce='Cervantes:BAAANQAECgUIDAAAAA==.',
Ch='Charcyna:BAAANQAECgMICAABNQAFFAcIEwAKAC0aAA==.Chardr:BAACNQAFFH8TAAIKAAcKLRpEBQBRAgAKAAcKLRpEBQBRAgA1AAQKfyMAAgoACQqmJfIZAPgCAAoACQqmJfIZAPgCAAAA.Chillywillie:BAAANQAECgQIDgAAAA==.Chrodne:BAAANQAECgIIAQAAAA==.Chucknorrîs:BAAANQAECgYICQAAAA==.',
Ci='Cigam:BAAANQAECgQIDAAAAA==.',
Cl='Clintbarton:BAABNQAECn9HAAILAAoKGw4yFAB+AQALAAoKGw4yFAB+AQAAAA==.',
Cr='Crûtch:BAAANQADCggIDgAAAA==.',
Ct='Cthullu:BAAANQADCggICAAAAA==.',
Cu='Culebra:BAABNQAECn8tAAMMAAoKUxYmJQBhAgAMAAkKzxYmJQBhAgANAAUKphKfZwDCAAAAAA==.',
['Cø']='Cøldshoulder:BAABNQAECn8kAAIOAAkKOBclMwATAgAOAAkKOBclMwATAgAAAA==.',
Da='Dabi:BAAANQADCgYIGQAAAA==.Daehyun:BAAANQAECggIDQABNQAFFAkJLgAFAIwkAA==.Danceofdeath:BAAANQAECgYIBwABNQAFFAQIBwAPAFUWAA==.Dane:BAABNQAECn8fAAIPAAkKOgxRXQBqAQAPAAkKOgxRXQBqAQAAAA==.Darcmatter:BAABNQAECn8dAAQBAAoKARwAaQAhAgABAAgKdxwAaQAhAgAQAAMKahyZNQDsAAARAAEKAAAQLAA+AAAAAA==.Darthmo:BAAANQADCgMIAwAAAA==.',
De='Deadtrap:BAAANQABCggIDwAAAA==.Deathsend:BAAANQADCgYICAAAAA==.Deepsicks:BAABNQAECn8oAAISAAoKBxo3DgCIAgASAAoKBxo3DgCIAgAAAA==.Deepstate:BAAANQAECgUICAAAAA==.Deimos:BAAANQADCgYIBgABNQAECgYICAAEAAAAAA==.Demonaholio:BAAANQAECgQIBAABNQAECgoKOgAGAHIXAA==.Demonäde:BAAANQADCgUIAgAAAA==.',
Di='Dima:BAABNQAECn8zAAITAAgKSRjGWABpAgATAAgKSRjGWABpAgAAAA==.Dithy:BAAANQAECgUIDgAAAA==.',
Dk='Dkrmk:BAAANQADCgMIAgAAAA==.Dktelli:BAABNQAECn8UAAMOAAgKPhGnSgCQAQAOAAgKPhGnSgCQAQAJAAQKgAcWoACYAAABNQAECgoKRQASAPEiAA==.',
Dn='Dne:BAAANQADCggIDgABNQAECgkJHwAPADoMAA==.',
Do='Donavon:BAAANQAECgYIDQAAAA==.Donutjelly:BAABNQAECn8hAAIKAAgKrRhiHgCWAQAKAAgKrRhiHgCWAQAAAA==.Dorivandor:BAAANQAECgUICgAAAA==.Dornnbryda:BAAANQADCggIDgABNQAECggIHwALALQSAA==.',
Dr='Drackothyr:BAABNQAECn8cAAMUAAgKYRw5EABTAgAUAAgKYRw5EABTAgAVAAMKKwXvRAB7AAAAAA==.Dreamweavver:BAAANQADCgQIBAAAAA==.Drumark:BAAANQADCgMIAwAAAA==.',
Du='Dugmaren:BAAANQABCggICAABNQAFFAMIBwANAFIWAA==.Dumpsterfire:BAAANQAECgcIBwAAAA==.',
Dw='Dwastring:BAABNQAECn8fAAITAAkKRBbcYgBQAgATAAkKRBbcYgBQAgAAAA==.',
Dy='Dyrale:BAAANQADCgYIGwAAAA==.',
Ek='Eknivar:BAAANQAECgcIBwABNQAECgoKNgAWABscAA==.',
Er='Erebus:BAAANQAECgQIBAAAAA==.Erragorn:BAABNQAECn8eAAMXAAYKlxWBFgA0AQAXAAUKvhSBFgA0AQAPAAYKEhQziAABAQAAAA==.',
Ev='Evisa:BAABNQAECn8WAAIWAAYKZAhlzQCzAAAWAAYKZAhlzQCzAAAAAA==.Evokholio:BAAANQAECgIIAwAAAA==.',
['Eö']='Eöath:BAAANQAECgEIAQAAAA==.',
Fa='Falaurenta:BAAANQADCgMIBgAAAA==.',
Fe='Fearzlol:BAAANQAECgIIAgABNQAFFAMIBwANAFIWAA==.Feidao:BAAANQAECgQICgAAAA==.Feralith:BAAANQADCgMIAQAAAA==.',
Fo='Foshizzle:BAAANQABCgIIAgAAAA==.',
Fu='Funkenfox:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëânòr:BAAANQADCgUIBQAAAA==.',
Ga='Gailinn:BAABNQAECn8YAAIYAAYKaQW8FwH4AAAYAAYKaQW8FwH4AAAAAA==.',
Gh='Ghlen:BAAANQADCgEIAQAAAA==.',
Go='Gooraah:BAAANQADCgUIBQABNQADCgYICQAEAAAAAA==.Gorash:BAAANQAECggICgAAAA==.',
Gr='Greggd:BAAANQADCgIIAgABNQAECgoKMQAZADMdAA==.Greggdshami:BAABNQAECn8xAAIZAAoKMx2mCwAKAwAZAAoKMx2mCwAKAwAAAA==.Gretagobbo:BAAANQAECgQIBAABNQAECgYICAAEAAAAAA==.',
Gu='Gundamus:BAAANQADCgYIBgAAAA==.Gurney:BAAANQADCgUICgABNQADCggIDgAEAAAAAA==.Guthrum:BAAANQADCgQIBAAAAA==.',
Ha='Halorah:BAAANQADCgYICQAAAA==.Hammburger:BAAANQABCgIIAgAAAA==.',
He='Healmonger:BAACNQAFFH8IAAIaAAQKbR0qDABoAQAaAAQKbR0qDABoAQA1AAQKf1wAAxoACgpdJEcLAC0DABoACgpdJEcLAC0DAAgABgqnCgYpAMAAAAAA.Hekili:BAAANQAECgUIDAAAAA==.Helgrin:BAAANQADCgYIBgAAAA==.Heruin:BAAANQAECgcIEgAAAA==.',
Hi='Hictor:BAAANQADCgMIAwAAAA==.',
Ho='Holly:BAAANQAECgQIBQAAAA==.Holypackin:BAAANQAECgIIAgAAAA==.Hongdou:BAAANQAECgQIAwAAAA==.Horse:BAACNQAFFH8oAAIaAAcKRQG2CgB/AQAaAAcKRQG2CgB/AQA1AAQKf0EAAhoACgomDVBqAN8BABoACgomDVBqAN8BAAAA.Hourzero:BAAANQAECgEIAQAAAA==.',
Ia='Iammyscars:BAACNQAFFH8NAAIbAAQKHhKbCADfAAAbAAQKHhKbCADfAAA1AAQKfzQAAhsACgrXIIUHAN8CABsACgrXIIUHAN8CAAAA.',
Ic='Icu:BAAANQAECgcIDwAAAA==.',
Ik='Ikillu:BAABNQAECn8lAAISAAgK2xqdCQAXAgASAAgK2xqdCQAXAgAAAA==.',
Il='Ilis:BAAANQAECgQIBwAAAA==.',
Ja='Jadawin:BAAANQABCgIIAgAAAA==.Jaiminvi:BAAANQADCgEIAQAAAA==.Jasnahh:BAAANQAECgQICQABNQAECgYICgAEAAAAAA==.Jaylas:BAAANQADCgEIAQABNQAECggILgAcAAMgAA==.',
Jo='Joeexotíc:BAACNQAFFH8OAAQdAAUK4yQaAAC5AQAdAAUK4yQaAAC5AQATAAEKMSGOHQBkAAALAAEKixBRIwBHAAA1AAQKfyMABB0ACgoNIYkAADEDAB0ACgoNIYkAADEDAAsABQrFExtBAEwBABMAAwoUHKIEAfwAAAAA.',
Ju='Jun:BAACNQAFFH8bAAIbAAcK2SIMAgDcAQAbAAcK2SIMAgDcAQA1AAQKfz0AAxsACgqcJq0AAPwDABsACgqcJq0AAPwDAB4ACAqAIgMdAGwCAAAA.Junfan:BAAANQAECggIEAAAAA==.',
Ka='Kandros:BAAANQABCgUICAAAAA==.Kasumaus:BAABNQAECn8WAAQOAAgKyQYIYQAhAQAOAAgKzwUIYQAhAQACAAQK5AYipwCqAAAJAAIKvwQYuABYAAAAAA==.',
Ke='Kelly:BAAANQADCggICAAAAA==.Kennifer:BAAANQADCggICQAAAA==.Kenshindune:BAAANQADCgQIBAAAAA==.Keragan:BAAANQADCgEJAQAAAA==.',
Kh='Khalyeesi:BAAANQADCgIIAwAAAA==.Khandris:BAAANQABCggIEwAAAA==.Khazjek:BAAANQADCgYICAAAAA==.Khephris:BAABNQAECn8xAAIDAAcKHh2fCwAGAgADAAcKHh2fCwAGAgAAAA==.',
Ki='Kiralni:BAAANQAECgMIAwAAAA==.',
Kn='Knivex:BAABNQAECn82AAMWAAoKGxzwnABHAgAWAAkKTRvwnABHAgADAAMK4h1eHQADAQAAAA==.',
Ko='Koryann:BAABNQAECn8sAAIfAAgKbxUAFABqAQAfAAgKbxUAFABqAQAAAA==.Kosel:BAAANQAECgcIEAAAAA==.Kova:BAABNQAECn8fAAIGAAkKaw/vRgA6AQAGAAkKaw/vRgA6AQAAAA==.',
Kr='Kramm:BAAANQAECgQIAgAAAA==.Krazyplaya:BAAANQAECgEIAQAAAA==.',
Ky='Kyrise:BAABNQAECn8bAAIZAAoKIhNhUgAdAgAZAAoKIhNhUgAdAgAAAA==.',
La='Lambo:BAAANQAECgQJBAAAAA==.Landam:BAABNQAECn8aAAIYAAcKEAn+swDxAAAYAAcKEAn+swDxAAAAAA==.',
Le='Leap:BAAANQADCgMIAwABNQAECgoKLwAeAHAWAA==.Leviticus:BAAANQADCgMIAwAAAA==.',
Li='Lifeaura:BAACNQAFFH8VAAIgAAYKsBC1AADhAQAgAAYKsBC1AADhAQA1AAQKfzUAAiAACQr3ICABAFcDACAACQr3ICABAFcDAAAA.Lifesmage:BAAANQAECggIBgAAAA==.Lifesshaman:BAAANQAECggICAAAAA==.Lightbläster:BAAANQAECgIIBAAAAA==.Lightrider:BAAANQADCgYICwAAAA==.Linesta:BAAANQADCgEIAQAAAA==.Lionroar:BAACNQAFFH8TAAIhAAcKTRxmAwASAgAhAAcKTRxmAwASAgA1AAQKfzgAAyEACgouI+AHAEYDACEACgouI+AHAEYDAAoAAgp0DXFYAGoAAAAA.Littleguy:BAABNQAECn8hAAIGAAcKmgNvaQDSAAAGAAcKmgNvaQDSAAAAAA==.',
Ll='Llaothtaed:BAAANQAECggIBgAAAA==.',
Lo='Lochannis:BAABNQAECn8VAAIXAAgK6Q8PCwBOAQAXAAgK6Q8PCwBOAQAAAA==.Logi:BAAANQAECggIDwAAAA==.Lokalock:BAAANQAECgUIDwABNQAECgoKRQASAPEiAA==.Lonee:BAAANQADCgIIAgAAAA==.Lorellei:BAABNQAECn8dAAIaAAYK8A3BfgDdAAAaAAYK8A3BfgDdAAAAAA==.Lothgow:BAAANQAECgEIAgAAAA==.',
Lu='Luxus:BAAANQAECgMIBAAAAA==.',
['Lâ']='Lân:BAACNQAFFH8HAAMNAAMKUhYrCgD9AAANAAMKUhYrCgD9AAAMAAIKHREUBwCQAAA1AAQKfxUAAw0ACQohHbgPAKsCAA0ACQqlG7gPAKsCAAwACAq4GPAlAF0CAAAA.',
Ma='Maelynn:BAAANQADCgUIBQAAAA==.Magchro:BAAANQADCgQIBAABNQAECgIIAQAEAAAAAA==.Manticor:BAAANQADCgcIBgAAAA==.Martyglaive:BAABNQAECn8fAAIbAAgKGxbIIwB3AQAbAAgKGxbIIwB3AQAAAA==.Matteas:BAABNQAECn8UAAIYAAcKgxxTkgAAAgAYAAcKgxxTkgAAAgAAAA==.',
Me='Menionblue:BAAANQADCgUIBQAAAA==.Mew:BAAANQAECgUIDwAAAA==.',
Mf='Mfdoom:BAABNQAECn9DAAQBAAoKzyCPHgBGAgABAAkKySCPHgBGAgARAAQKxxq1FwDQAAAQAAMKfBV8PgDIAAABNQADCgIIBAAEAAAAAA==.',
Mi='Mizrey:BAABNQAECn8oAAIOAAoKVB/XEgD3AgAOAAoKVB/XEgD3AgAAAA==.Mizukisakura:BAAANQAECgQIBAAAAA==.',
Mo='Mograins:BAABNQAECn9CAAMBAAoK/B/VFwBwAgABAAkKFx/VFwBwAgAQAAYKXSFHDQAkAgAAAA==.Monzcarro:BAAANQADCggICwAAAA==.Mordar:BAAANQADCgUIBwAAAA==.Morgainne:BAAANQAECgUIDgAAAA==.Mortmor:BAAANQAECgYICwAAAA==.',
Mu='Muffinn:BAABNQAECn8mAAITAAgKGwyJmQDUAQATAAgKGwyJmQDUAQAAAA==.Mursê:BAAANQAECgYICAAAAA==.',
My='Mymdos:BAABNQAECn9MAAIPAAoKgSJNDgD0AgAPAAoKgSJNDgD0AgABNQABCgIIAgAEAAAAAA==.Myrmidonn:BAAANQADCgYICgAAAA==.',
['Mä']='Mästérdòn:BAAANQAECgcIDAAAAA==.',
['Må']='Måsterdon:BAABNQAECn8aAAIfAAYKEQxGLwCbAAAfAAYKEQxGLwCbAAAAAA==.',
['Mô']='Môiraine:BAACNQAFFH8HAAIcAAMKOBC9DgDcAAAcAAMKOBC9DgDcAAA1AAQKfxYAAhwACQqaGAgbAGwCABwACQqaGAgbAGwCAAAA.',
Ne='Nercos:BAAANQAECgEIAQABNQAFFAIIAgAEAAAAAA==.Nercqt:BAAANQAFFAIIAgAAAA==.Neverborn:BAAANQAECgcIEgAAAA==.',
Ni='Niame:BAAANQAECgUIDAAAAA==.Nitraina:BAABNQAECn8WAAMDAAgKHgInMwBuAAAWAAcKGwF8jgGpAAADAAYKeAInMwBuAAAAAA==.Niyabelle:BAABNQAECn8uAAMNAAoKuhxcIQAVAgANAAoKuhxcIQAVAgAMAAcKUhIbRAC4AQAAAA==.',
No='Noggenfloggr:BAAANQAECgUICAAAAA==.Nomesis:BAAANQAECgEIAQAAAA==.Norita:BAAANQABCgEIAQAAAA==.',
Ny='Nyxth:BAAANQADCgYIBgAAAA==.',
Oa='Oakmane:BAAANQABCgEIAQABNQAECggICgAEAAAAAA==.',
Od='Odïn:BAAANQADCgYIDAAAAA==.',
Ol='Oleevia:BAABNQAECn85AAIIAAoKuxjTCwApAgAIAAoKuxjTCwApAgAAAA==.',
Om='Omgdingers:BAAANQAECgYICAABNQAECgoKGQAOAK8bAA==.',
On='Oneshót:BAAANQADCgYICAABNQAECgcIFQAaABkVAA==.Oneth:BAAANQAECgIIAgABNQAECgUIDAAEAAAAAA==.',
Or='Oraxia:BAAANQAECgEIAQABNQAECgYICAAEAAAAAA==.Orgdynamite:BAAANQAECgYIBwABNQAFFAcIKAAGANccAA==.Orgsham:BAACNQAFFH8oAAMGAAcK1xx1AgCrAQAGAAcK1xx1AgCrAQASAAEKSBfiBwBTAAA1AAQKfz0AAwYACgq9JNMNAHoDAAYACgq9JNMNAHoDABIABAozFwsjACoBAAAA.',
Pa='Paedragon:BAAANQAECgUIDAAAAA==.Paimon:BAAANQADCgYIBgAAAA==.Paladareian:BAABNQAECn8uAAIcAAgKAyC+MgCaAgAcAAgKAyC+MgCaAgAAAA==.',
Pe='Pej:BAACNQAFFH8oAAQiAAcK4xfgBADHAAAUAAQKXxDCBwAKAQAVAAQKPgqNCQDjAAAiAAUKdhLgBADHAAA1AAQKf0QABBQACgq9HScPAGgCABQACApiICcPAGgCABUABwpPFwgdAPsBACIABgrBGnwLAKcBAAAA.Pejbolt:BAAANQADCgcICgABNQAFFAcIGwAbANkiAA==.',
Ph='Phenomenon:BAAANQAECgUIBQABNQAECggIDwAEAAAAAA==.Phoenixa:BAAANQAECgEIAQAAAA==.',
Pl='Plus:BAAANQAECgcICwAAAA==.',
Po='Powerslavé:BAACNQAFFH8HAAIPAAQKVRYnGACeAAAPAAQKVRYnGACeAAA1AAQKfzIAAg8ACgofIXsZAJ4CAA8ACgofIXsZAJ4CAAAA.',
Pr='Priestitoot:BAAANQAECgMIAwAAAA==.Proust:BAAANQADCggIDgAAAA==.',
Pu='Pumkinhead:BAABNQAECn8hAAIGAAoKnQymYwD2AQAGAAoKnQymYwD2AQAAAA==.',
Py='Pyromania:BAAANQAECggIDwAAAA==.',
['Pä']='Pä:BAAANQADCgMIAQAAAA==.',
Ra='Raiden:BAABNQAECn8pAAIYAAgK9Q1shwBCAQAYAAgK9Q1shwBCAQAAAA==.Rat:BAAANQABCgIIAgAAAA==.Rauck:BAAANQAECgIIAQABNQAECgYICAAEAAAAAA==.',
Re='Rentacat:BAAANQAECgUICAAAAA==.Retropâlly:BAAANQADCgMIAwAAAA==.Revoker:BAAANQADCgUICAABNQAECgoKKAATAN4YAA==.',
Ro='Rogi:BAAANQAECgUICAABNQABCgIIAgAEAAAAAA==.',
['Rö']='Römana:BAABNQAECn8fAAITAAkKdg0inADPAQATAAkKdg0inADPAQAAAA==.',
Sa='Sanguinaris:BAAANQAECgEIAQABNQAECggICgAEAAAAAA==.Sappinbubs:BAAANQAECgEIAQAAAA==.Sareya:BAAANQABCggIEAAAAA==.Sataanic:BAAANQAECgYIBwAAAA==.Satyrical:BAABNQAECn8nAAQOAAkKIxVLKwCBAQACAAgKzhXwSgDpAQAOAAkKegxLKwCBAQAJAAIKbAvXtwBYAAAAAA==.',
Sc='Scorch:BAABNQAECn8UAAIWAAcKuRXZ0QDjAQAWAAcKuRXZ0QDjAQAAAA==.',
Se='Sedrayn:BAAANQAECgYIBwAAAA==.Selatha:BAAANQABCgIIAgABNQAFFAYIEAAWAAEaAA==.Selystine:BAAANQADCgUICAAAAA==.Semaj:BAAANQADCgcIBwAAAA==.Sergantis:BAAANQADCggIDgAAAA==.',
Sh='Shagee:BAAANQAECgEIAQAAAA==.Shamwowolio:BAABNQAECn86AAIGAAoKchcXHgALAgAGAAoKchcXHgALAgAAAA==.Shayd:BAABNQAECn8oAAQTAAoK3hgwVwBtAgAdAAgKGBccBQB6AgATAAkKvhgwVwBtAgALAAMKJRixUwDYAAAAAA==.Shigz:BAAANQADCggICQAAAA==.Shirokyu:BAAANQADCggICAAAAA==.Shirra:BAAANQADCggIDwAAAA==.Shirraz:BAABNQAECn8lAAIeAAgKrglOHwAvAQAeAAgKrglOHwAvAQAAAA==.Sho:BAAANQAECgYICwAAAA==.Shroomicide:BAAANQAECggIBgAAAA==.',
Si='Sicaris:BAAANQADCgYICgABNQAECggIEQAEAAAAAA==.Sicksdeep:BAACNQAFFH8LAAMPAAUKrg8ZEQDYAAAPAAQKrg8ZEQDYAAAXAAEKAABsBgBEAAA1AAQKfzUAAg8ACgqfH/gVALcCAA8ACgqfH/gVALcCAAAA.Sigürd:BAAANQADCgEIAQAAAA==.Silverstorm:BAABNQAECn8YAAITAAYKkQek3ABHAQATAAYKkQek3ABHAQAAAA==.',
Sk='Skÿe:BAABNQAECn8wAAILAAkKUBlwDgDlAQALAAkKUBlwDgDlAQAAAA==.',
Sl='Slamma:BAACNQAFFH8mAAIPAAcKNSRTAgADAgAPAAcKNSRTAgADAgA1AAQKf1EAAg8ACgqdJo0EANIDAA8ACgqdJo0EANIDAAAA.Slappin:BAAANQAECgIIBAAAAA==.Slappinbubs:BAAANQAECgQIBQAAAA==.Slicedbreád:BAACNQAFFH8lAAMZAAcKFw7KCwCQAQAZAAYKBQrKCwCQAQAGAAUKwBYACAADAQA1AAQKfz4AAwYACgrfIYIRAIYCAAYACQoiIYIRAIYCABkACgohGPFOACkCAAE1AAQKAQgBAAQAAAAA.',
Sm='Smokadaganga:BAABNQAECn8WAAMjAAkKqwmmBABXAQAjAAYK1gumBABXAQAWAAcKWwU/KgFFAQAAAA==.',
So='Sols:BAAANQAECgYIDQABNQAFFAQIBwAPAFUWAA==.Sondirion:BAABNQAECn8fAAILAAgKtBIrFQBuAQALAAgKtBIrFQBuAQAAAA==.Soulancer:BAAANQAECgQIBAABNQAECggICgAEAAAAAA==.Sowet:BAAANQAECgIIAgAAAA==.',
Sp='Speoghii:BAABNQAECn8kAAIBAAoKnhrFRwB7AgABAAoKnhrFRwB7AgAAAA==.Spifftreebug:BAABNQAECn82AAMKAAoK1xAsIgBzAQAKAAkKZQ4sIgBzAQAhAAcKbAjULQD1AAAAAA==.Sprinklez:BAABNQAECn8VAAISAAYK6BjGGgC3AQASAAYK6BjGGgC3AQAAAA==.',
St='Steelerschic:BAABNQAECn8UAAIGAAUKBgQCmABvAAAGAAUKBgQCmABvAAAAAA==.Stormleader:BAACNQAFFH8IAAIhAAUKewZ0BgAeAQAhAAUKewZ0BgAeAQA1AAQKfz8AAyEACgpSGe4NAE8CACEACgpSGe4NAE8CACQAAQoAADN2ABMAAAAA.',
Su='Surge:BAAANQAECgUIDAAAAA==.',
Ta='Tai:BAABNQAECn8wAAIlAAkK8BmdCADIAQAlAAkK8BmdCADIAQAAAA==.Tainema:BAAANQAECgIIBAAAAA==.Tankguywowie:BAAANQAECgUIBQABNQAFFAYIDgAKAGQLAA==.Taurriel:BAAANQAECgYIEAAAAA==.Tazzm:BAABNQAECn8kAAILAAgK2gRGQABSAQALAAgK2gRGQABSAQAAAA==.',
Te='Teranok:BAABNQAECn8ZAAQmAAkKGhezEQDLAQAmAAgKIRmzEQDLAQAFAAYKZBFZPAAzAQAHAAEK1gFHVQAfAAAAAA==.Terzal:BAAANQADCgYIBgAAAA==.',
Th='Thalel:BAAANQAECgQIDgAAAA==.Theacused:BAABNQAECn8ZAAIWAAoK0xktNQAdAgAWAAoK0xktNQAdAgABNQAFFAUIDQACACITAA==.Them:BAAANQADCgIIAgABNQAECgEIAQAEAAAAAA==.Thoir:BAACNQAFFH8oAAIZAAcKSyS8AADQAgAZAAcKSyS8AADQAgA1AAQKf0EAAhkACgrmJfwGAIsDABkACgrmJfwGAIsDAAE1AAUUBwgoABoARQEA.Thorodinson:BAAANQAECgQIBQAAAA==.',
Ti='Tipsylorcet:BAABNQAECn8aAAImAAgKcxuXDQAhAgAmAAgKcxuXDQAhAgAAAA==.',
Tk='Tkrain:BAAANQADCgYIHgAAAA==.',
Tr='Traen:BAAANQADCggICAAAAA==.Trashbull:BAAANQAECggIAgAAAA==.Tricktickler:BAAANQAECgUIDgAAAA==.Troy:BAAANQADCgUIBQAAAA==.',
Tu='Tuskani:BAAANQABCggIHAAAAA==.',
Ty='Tybird:BAABNQAECn82AAIOAAoK6RwuEABoAgAOAAoK6RwuEABoAgAAAA==.Tyranisv:BAAANQADCgMIAwAAAA==.',
Ul='Ulsull:BAAANQADCgcIEAABNQADCggIDgAEAAAAAA==.Ulybonez:BAAANQAECggIEAABNQAFFAcIKAAIAP8gAA==.Ulyssi:BAACNQAFFH8oAAIIAAcK/yBdAQD1AQAIAAcK/yBdAQD1AQA1AAQKf0EAAggACgrhJCMDAKkDAAgACgrhJCMDAKkDAAAA.',
Um='Ummpatas:BAAANQAECgEIAQAAAA==.',
Us='Usseel:BAAANQADCgMIAwAAAA==.',
['Uñ']='Uñàble:BAAANQADCgIIAgAAAA==.',
Va='Valymus:BAAANQADCgIIAgABNQAECgoKKAATAN4YAA==.Vandagylon:BAAANQADCgYIDAAAAA==.Vandals:BAAANQAECgcIEAAAAA==.',
Ve='Ven:BAABNQAECn8cAAIIAAgKuAaVPgA4AQAIAAgKuAaVPgA4AQAAAA==.Ver:BAAANQADCgMIAQAAAA==.',
Vo='Voltaire:BAAANQADCgIIAgAAAA==.',
Wa='Walle:BAAANQADCgEIAQAAAA==.Wankstar:BAAANQAECgEIAQAAAA==.Wargas:BAAANQABCgIIAgAAAA==.Warvein:BAABNQAECn8gAAMPAAkK/A8CjwD2AQAPAAkK/A8CjwD2AQAlAAQKMAdwNACTAAAAAA==.',
We='Weehunt:BAABNQAECn8eAAITAAgKKhA4kQDnAQATAAgKKhA4kQDnAQAAAA==.Weeshami:BAAANQADCgMIAwAAAA==.',
Wh='Whillia:BAAANQADCgMIAwAAAA==.',
Wi='Wicah:BAAANQAECgYIEgAAAA==.Wicka:BAABNQAECn80AAIZAAkK4SFmDwDaAgAZAAkK4SFmDwDaAgAAAA==.Widowblade:BAAANQAECgUIBQAAAA==.Wildriver:BAABNQAECn8VAAIhAAYKLxuaKQDSAQAhAAYKLxuaKQDSAQAAAA==.Willferàl:BAAANQADCgMIAwAAAA==.',
Xa='Xaehyun:BAACNQAFFH8uAAIFAAkKjCQ7AAACAwAFAAkKjCQ7AAACAwA1AAQKfygAAgUACgoJJwQAAKsDAAUACgoJJwQAAKsDAAAA.Xandrelar:BAAANQAECgQIBAABNQAECgoKKAATAN4YAA==.',
Xm='Xmrpdk:BAACNQAFFH8oAAIJAAcKKiTMAQDxAQAJAAcKKiTMAQDxAQA1AAQKf0EAAgkACgrhJf8BANQDAAkACgrhJf8BANQDAAAA.Xmrppally:BAAANQAECgcICAABNQAFFAcIKAAJACokAA==.',
Xy='Xy:BAAANQADCggICAAAAA==.',
Ya='Yarina:BAAANQADCgUIBQAAAA==.',
Yo='Yoyiek:BAACNQAFFH8OAAIKAAYKZAu0FAAhAQAKAAYKZAu0FAAhAQA1AAQKfy8AAwoACgoCHRoKAK4CAAoACgoCHRoKAK4CACQAAwq6AjBSAFoAAAAA.',
Za='Zalynn:BAAANQAECgEIAQAAAA==.Zanne:BAACNQAFFH8IAAILAAQKVRSVCgC+AAALAAQKVRSVCgC+AAA1AAQKfyoAAgsACgrxHd8XAJkCAAsACgrxHd8XAJkCAAAA.Zarthul:BAAANQAECgQICAAAAA==.',
Ze='Zehara:BAAANQADCgMJAwAAAA==.Zenori:BAAANQADCggIDgAAAA==.',
Zh='Zhenyu:BAAANQADCgQIBAABNQAECggICgAEAAAAAA==.',
Zi='Ziely:BAAANQADCgMIAwAAAA==.',
Zl='Zlot:BAECNQAFFH8oAAMTAAcKah6bBwAdAQATAAUKBB6bBwAdAQALAAQKFCA6BwD4AAA1AAQKf0EAAxMACgrAJG8iAA0DABMABwqsJm8iAA0DAAsACQqbIDQZAI0CAAAA.',
Zu='Zulani:BAAANQAECgYIBQAAAA==.',
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
