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

local lookup = {'Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Monk-Windwalker','Shaman-Elemental','DeathKnight-Blood','Druid-Balance','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Frost','Warrior-Arms','Warlock-Destruction','Warlock-Affliction','Shaman-Enhancement','Hunter-BeastMastery','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Warrior-Fury','Paladin-Retribution','Shaman-Restoration','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Paladin-Holy','Hunter-Survival','DemonHunter-Devourer','Paladin-Protection','Priest-Discipline','Druid-Restoration','Evoker-Augmentation','Mage-Fire','Druid-Guardian','Warrior-Protection','Monk-Brewmaster','Monk-Mistweaver',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aaralia:BAAANQAECgUIDAAAAA==.',
Ab='Abyssdark:BAABNQAECn82AAIBAAoKtBhlKADjAgABAAoKtBhlKADjAgAAAA==.',
Ac='Accusation:BAACNQAFFH8JAAICAAMKcBTVBQCMAAACAAMKcBTVBQCMAAA1AAQKfxUAAgIACgo3FCgNAHcBAAIACgo3FCgNAHcBAAAA.',
Ak='Akadeus:BAAANQAECgIIAgAAAA==.',
Al='Alarielle:BAAANQAECgQIBQABNQAECgcIKwADAB4dAA==.Altx:BAAANQABCgUIAwAAAA==.',
Am='Amirah:BAAANQADCgEIAgAAAA==.Ammathael:BAAANQAECgEJAQAAAA==.',
An='Anagela:BAAANQABCgUIBQABNQAECgIIBQAEAAAAAA==.Anamarie:BAAANQAECgQIBQABNQAECgYIDgAEAAAAAA==.Antipasta:BAAANQAECggICAAAAA==.',
Ar='Aramist:BAAANQADCgYIHQAAAA==.Arroy:BAAANQADCgcIDwAAAA==.',
As='Ashikahammer:BAAANQAECgYIDQABNQAECgkJIgADAJQgAA==.Ashtaroth:BAAANQAECgYIDwABNQAECgcIKwADAB4dAA==.',
Az='Azraeth:BAAANQAECgYIEgAAAA==.',
Ba='Bacon:BAAANQABCgMIAwABNQAECgUIBQAEAAAAAA==.Baehyun:BAAANQAECggIDQABNQAFFAkJJQAFAMcjAA==.Basou:BAAANQADCggICAAAAA==.',
Be='Belanova:BAAANQADCgQIBAAAAA==.Belnathas:BAAANQADCggIHAAAAA==.',
Bl='Blamethemage:BAAANQAECgUIBQABNQAECgoKLwAGAP0VAA==.Bloodbeard:BAAANQAECgYICAAAAA==.Bloodedge:BAAANQADCgIIBAAAAA==.',
Bo='Bohmbear:BAAANQADCgYIBgAAAA==.Bomboy:BAAANQAECgEIAQAAAA==.',
Br='Brentobox:BAAANQAECgUIEwAAAA==.Brugara:BAAANQADCggIFwAAAA==.',
Bu='Bungeholio:BAAANQAECgQIDAABNQAECgoKLwAGAP0VAA==.',
Ca='Camael:BAAANQAECgYIDwAAAA==.Cannelle:BAAANQAECgcIDAAAAA==.Carden:BAABNQAECn8YAAIHAAYKax5BPAASAgAHAAYKax5BPAASAgAAAA==.',
Ce='Cervantes:BAAANQAECgMIBwAAAA==.',
Ch='Charcyna:BAAANQAECgQICAABNQAFFAcIEwAIAC0aAA==.Chardr:BAACNQAFFH8TAAIIAAcKLRpEBQBRAgAIAAcKLRpEBQBRAgA1AAQKfyIAAggACQqlJfIZAPgCAAgACQqlJfIZAPgCAAAA.Chillywillie:BAAANQAECgQICgAAAA==.Chrodne:BAAANQADCgcIFQAAAA==.Chucknorrîs:BAAANQAECgQIBQAAAA==.',
Ci='Cigam:BAAANQAECgQIDAAAAA==.',
Cl='Clintbarton:BAABNQAECn9BAAIJAAkKxQ56DwANAQAJAAkKxQ56DwANAQAAAA==.',
Cr='Crûtch:BAAANQADCggIDgAAAA==.',
Ct='Cthullu:BAAANQADCggICAAAAA==.',
Cu='Culebra:BAABNQAECn8pAAMKAAoKQRUmJQBhAgAKAAkKzxYmJQBhAgALAAIK8g7VTwA5AAAAAA==.',
['Cø']='Cøldshoulder:BAABNQAECn8hAAIMAAgKehklMwATAgAMAAgKehklMwATAgAAAA==.',
Da='Dabi:BAAANQADCgYIDgAAAA==.Daehyun:BAAANQAECggIDQABNQAFFAkJJQAFAMcjAA==.Danceofdeath:BAAANQAECgYIBwABNQAFFAMIBgANAFUWAA==.Dane:BAABNQAECn8fAAINAAkKOgw7IACDAQANAAkKOgw7IACDAQAAAA==.Darcmatter:BAABNQAECn8bAAQBAAoKyBsAaQAhAgABAAgKKxwAaQAhAgAOAAMKahyZNQDsAAAPAAEKAAAQLAA+AAAAAA==.Darthmo:BAAANQADCgMIAwAAAA==.',
De='Deadtrap:BAAANQABCggIDwAAAA==.Deathsend:BAAANQADCgYICAAAAA==.Deepsicks:BAABNQAECn8iAAIQAAoKxRg3DgCIAgAQAAoKxRg3DgCIAgAAAA==.Deepstate:BAAANQAECgIIBAAAAA==.Deimos:BAAANQADCgYIBgABNQAECgYICAAEAAAAAA==.Demonaholio:BAAANQAECgEIAQABNQAECgoKLwAGAP0VAA==.Demonäde:BAAANQADCgUIAgAAAA==.',
Di='Dima:BAABNQAECn8sAAIRAAgKsxfGWABpAgARAAgKsxfGWABpAgAAAA==.Dithy:BAAANQAECgQICQAAAA==.',
Dk='Dkrmk:BAAANQADCgMIAgAAAA==.Dktelli:BAAANQAECgcIEQABNQAECgoKOgAQANQfAA==.',
Dn='Dne:BAAANQADCggIDgABNQAECgkJHwANADoMAA==.',
Do='Donavon:BAAANQAECgYIDAAAAA==.Donutjelly:BAABNQAECn8cAAIIAAcKcxnxDAB5AQAIAAcKcxnxDAB5AQAAAA==.Dorivandor:BAAANQAECgUIBgAAAA==.Dornnbryda:BAAANQADCggIDgABNQAECgcIGAAJALcUAA==.',
Dr='Drackothyr:BAABNQAECn8cAAMSAAgKYRw5EABTAgASAAgKYRw5EABTAgATAAMKKwXvRAB7AAAAAA==.Dreamweavver:BAAANQADCgQIBAAAAA==.Drumark:BAAANQADCgMIAwAAAA==.',
Dw='Dwastring:BAABNQAECn8fAAIRAAkKRBYqFQDKAQARAAkKRBYqFQDKAQAAAA==.',
Dy='Dyrale:BAAANQADCgYIGwAAAA==.',
Ek='Eknivar:BAAANQADCgQIBAABNQAECgkJMAAUAIMaAA==.',
Er='Erebus:BAAANQAECgQIBAAAAA==.Erragorn:BAABNQAECn8ZAAMVAAYKORSBFgA0AQAVAAUKvhSBFgA0AQANAAYKnRKhaADIAAAAAA==.',
Ev='Evisa:BAAANQAECgQIDQAAAA==.Evokholio:BAAANQAECgIIAwAAAA==.',
['Eö']='Eöath:BAAANQAECgEIAQAAAA==.',
Fa='Falaurenta:BAAANQADCgMIBgAAAA==.',
Fe='Fearzlol:BAAANQAECgIIAgABNQAFFAIIBAAEAAAAAA==.Feidao:BAAANQAECgQICgAAAA==.Feralith:BAAANQADCgMIAQAAAA==.',
Fo='Foshizzle:BAAANQABCgIIAgAAAA==.',
Fu='Funkenfox:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëânòr:BAAANQADCgUIBQAAAA==.',
Ga='Gailinn:BAABNQAECn8YAAIWAAYKaQW8FwH4AAAWAAYKaQW8FwH4AAAAAA==.',
Gh='Ghlen:BAAANQADCgEIAQAAAA==.',
Go='Gooraah:BAAANQADCgUIBQAAAA==.Gorash:BAAANQAECgQIBQABNQAECgYIEgAEAAAAAA==.',
Gr='Greggd:BAAANQADCgIIAgABNQAECgkJJwAXAIAdAA==.Greggdshami:BAABNQAECn8nAAIXAAkKgB27BACgAgAXAAkKgB27BACgAgAAAA==.Gretagobbo:BAAANQAECgQIBAABNQAECgYICAAEAAAAAA==.',
Gu='Gundamus:BAAANQADCgYIBgAAAA==.Gurney:BAAANQADCgUIBQABNQADCggIDgAEAAAAAA==.Guthrum:BAAANQADCgQIBAAAAA==.',
Ha='Halorah:BAAANQADCgUIBQABNQADCgUIBQAEAAAAAA==.Hammburger:BAAANQABCgIIAgAAAA==.',
He='Healmonger:BAABNQAECn89AAMYAAoKjSMZBADkAgAYAAoKjSMZBADkAgAZAAEKAABclgAMAAAAAA==.Hekili:BAAANQAECgUIDAAAAA==.Helgrin:BAAANQADCgYIBgAAAA==.Heruin:BAAANQAECgcIEgAAAA==.',
Hi='Hictor:BAAANQADCgMIAwAAAA==.',
Ho='Holly:BAAANQAECgQIBQAAAA==.Holypackin:BAAANQAECgEIAQAAAA==.Hongdou:BAAANQAECgQIAwAAAA==.Horse:BAACNQAFFH8hAAIYAAYKaQHFCABBAQAYAAYKaQHFCABBAQA1AAQKfzwAAhgACgpiC1BqAN8BABgACgpiC1BqAN8BAAAA.Hourzero:BAAANQAECgEIAQAAAA==.',
Ia='Iammyscars:BAACNQAFFH8LAAIaAAQKHhLWBADtAAAaAAQKHhLWBADtAAA1AAQKfywAAhoACgpmIAsBAAgDABoACgpmIAsBAAgDAAAA.',
Ic='Icu:BAAANQAECgcIDwAAAA==.',
Ik='Ikillu:BAABNQAECn8YAAIQAAgKPRhEAgAhAgAQAAgKPRhEAgAhAgAAAA==.',
Il='Ilis:BAAANQAECgQIBgAAAA==.Ilovecheetos:BAAANQADCggJDgAAAA==.',
Ja='Jadawin:BAAANQABCgIIAgAAAA==.Jaiminvi:BAAANQADCgEIAQAAAA==.Jasnahh:BAAANQAECgQICQABNQAECgYICgAEAAAAAA==.Jaylas:BAAANQADCgEIAQABNQAECggILgAbAAMgAA==.',
Jo='Joeexotíc:BAACNQAFFH8JAAMcAAQKPCQiAABTAQAcAAQKPCQiAABTAQAJAAEKixBRIwBHAAA1AAQKfxUABBwACQowHdUBAKUBABwABwp+ItUBAKUBAAkABQrFExtBAEwBABEAAwoUHKIEAfwAAAAA.',
Ju='Jun:BAACNQAFFH8UAAIaAAYKZiJsAwBPAgAaAAYKZiJsAwBPAgA1AAQKfzgAAxoACgqcJq0AAPwDABoACgqcJq0AAPwDAB0ACAqAIgMdAGwCAAAA.Junfan:BAAANQAECggIEAAAAA==.',
Ka='Kandros:BAAANQABCgUIBwAAAA==.Kasumaus:BAABNQAECn8VAAQMAAgKyQYIYQAhAQAMAAgKzwUIYQAhAQACAAQK5AYipwCqAAAHAAIKvwQYuABYAAAAAA==.',
Ke='Kelly:BAAANQADCggICAAAAA==.Kennifer:BAAANQADCggICQAAAA==.Kenshindune:BAAANQADCgQIBAAAAA==.Keragan:BAAANQADCgEJAQAAAA==.',
Kh='Khalyeesi:BAAANQADCgIIAwAAAA==.Khandris:BAAANQABCggIEwAAAA==.Khazjek:BAAANQADCgYICAAAAA==.Khephris:BAABNQAECn8rAAIDAAcKHh2fCwAGAgADAAcKHh2fCwAGAgAAAA==.',
Ki='Kiralni:BAAANQAECgMIAwAAAA==.',
Kn='Knivex:BAABNQAECn8wAAMUAAkKgxrwnABHAgAUAAgKUBnwnABHAgADAAMK4h1eHQADAQAAAA==.',
Ko='Koryann:BAABNQAECn8iAAIeAAgKEBQvKwCDAQAeAAgKEBQvKwCDAQAAAA==.Kosel:BAAANQAECgYIDAAAAA==.Kova:BAABNQAECn8ZAAIGAAgKmQ5cgACkAQAGAAgKmQ5cgACkAQAAAA==.',
Kr='Kramm:BAAANQAECgQIAgAAAA==.Krazyplaya:BAAANQAECgEIAQAAAA==.',
Kw='Kwarthil:BAAANQABCgEIAQAAAA==.',
Ky='Kyrise:BAABNQAECn8ZAAIXAAoKJBJhUgAdAgAXAAoKJBJhUgAdAgAAAA==.',
La='Lambo:BAAANQAECgQJBAAAAA==.Landam:BAABNQAECn8VAAIWAAcKZwecggDIAAAWAAcKZwecggDIAAAAAA==.',
Le='Leap:BAAANQADCgMIAwABNQAECgkJLAAdAOoXAA==.',
Li='Lifeaura:BAACNQAFFH8VAAIfAAYKsBC1AADhAQAfAAYKsBC1AADhAQA1AAQKfzUAAh8ACQr3ICABAFcDAB8ACQr3ICABAFcDAAAA.Lifesmage:BAAANQAECggIBgAAAA==.Lifesshaman:BAAANQAECggICAAAAA==.Lightbläster:BAAANQAECgIIBAAAAA==.Lightrider:BAAANQADCgYICwAAAA==.Linesta:BAAANQADCgEIAQAAAA==.Lionroar:BAACNQAFFH8TAAIgAAcKTRxmAwASAgAgAAcKTRxmAwASAgA1AAQKfy4AAiAACgouI+AHAEYDACAACgouI+AHAEYDAAAA.Littleguy:BAABNQAECn8aAAIGAAYKvgKP2gDgAAAGAAYKvgKP2gDgAAAAAA==.',
Ll='Llaothtaed:BAAANQAECggIBgAAAA==.',
Lo='Lochannis:BAAANQAECgYIDgAAAA==.Logi:BAAANQAECggICgAAAA==.Lokalock:BAAANQAECgUIDwABNQAECgoKOgAQANQfAA==.Lonee:BAAANQADCgIIAgAAAA==.Lorellei:BAAANQAECgUIEwAAAA==.Lothgow:BAAANQAECgEIAgAAAA==.',
Lu='Luxus:BAAANQAECgEIAQAAAA==.',
['Lâ']='Lân:BAAANQAFFAIIBAAAAA==.',
Ma='Maelynn:BAAANQADCgUIBQAAAA==.Magchro:BAAANQADCgQIBAABNQADCgcIFQAEAAAAAA==.Manticor:BAAANQADCgcIBgAAAA==.Martyglaive:BAABNQAECn8ZAAIaAAYKVBZ5QwCnAQAaAAYKVBZ5QwCnAQAAAA==.Matteas:BAABNQAECn8UAAIWAAcKgxxTkgAAAgAWAAcKgxxTkgAAAgAAAA==.',
Me='Menionblue:BAAANQADCgUIBQAAAA==.Mew:BAAANQAECgUIDwAAAA==.',
Mf='Mfdoom:BAABNQAECn85AAQBAAoKzx1cQQCOAgABAAkKcB1cQQCOAgAPAAMK/x21FwDQAAAOAAMKfBV8PgDIAAABNQADCgIIBAAEAAAAAA==.',
Mi='Mizrey:BAABNQAECn8bAAIMAAoKmhvXEgD3AgAMAAoKmhvXEgD3AgAAAA==.Mizukisakura:BAAANQAECgQIBAAAAA==.',
Mo='Mograins:BAABNQAECn86AAMBAAoKwh/9BQBUAgABAAkKPR79BQBUAgAOAAYKXSFHDQAkAgAAAA==.Monzcarro:BAAANQADCggICwAAAA==.Mordar:BAAANQADCgUIBwAAAA==.Morgainne:BAAANQAECgQICQAAAA==.Mortmor:BAAANQAECgYICwAAAA==.',
Mu='Muffinn:BAABNQAECn8iAAIRAAgKVwqJmQDUAQARAAgKVwqJmQDUAQAAAA==.Mursê:BAAANQAECgYICAAAAA==.',
My='Mymdos:BAABNQAECn9CAAINAAoKQx6lAwC+AgANAAoKQx6lAwC+AgABNQABCgIIAgAEAAAAAA==.Myrmidonn:BAAANQADCgYICgAAAA==.',
['Mä']='Mästérdòn:BAAANQAECgcIDAAAAA==.',
['Må']='Måsterdon:BAABNQAECn8aAAIeAAYKEQz1HACpAAAeAAYKEQz1HACpAAAAAA==.',
['Mô']='Môiraine:BAAANQAFFAIIBAAAAA==.',
Ne='Nercos:BAAANQAECgEIAQABNQAFFAIIAgAEAAAAAA==.Nercqt:BAAANQAFFAIIAgAAAA==.Neverborn:BAAANQAECgcIEgAAAA==.',
Ni='Niame:BAAANQAECgUIDAAAAA==.Nitraina:BAABNQAECn8VAAMDAAgKHgInMwBuAAAUAAcKGwF8jgGpAAADAAYKeAInMwBuAAAAAA==.Niyabelle:BAABNQAECn8oAAMLAAkKbRtBEwA9AQAKAAcKUhIbRAC4AQALAAgKoxtBEwA9AQAAAA==.',
No='Noggenfloggr:BAAANQAECgUICAAAAA==.Nomesis:BAAANQAECgEIAQAAAA==.',
Ny='Nyxth:BAAANQADCgYIBgAAAA==.',
Oa='Oakmane:BAAANQABCgEIAQABNQAECgYIEgAEAAAAAA==.',
Od='Odïn:BAAANQADCgYIDAAAAA==.',
Ol='Oleevia:BAABNQAECn8zAAIZAAoKlRi+AQBcAgAZAAoKlRi+AQBcAgAAAA==.',
Om='Omgdingers:BAAANQAECgYICAABNQAECgoKGQAMAK8bAA==.',
On='Oneshót:BAAANQADCgYICAABNQAECgcIFQAYABkVAA==.Oneth:BAAANQAECgIIAgABNQAECgQIBwAEAAAAAA==.',
Or='Oraxia:BAAANQAECgEIAQABNQAECgYICAAEAAAAAA==.Ords:BAAANQABCgYICAAAAA==.Orgdynamite:BAAANQAECgYIBwABNQAFFAYIIQAGAPMaAA==.Orgsham:BAACNQAFFH8hAAMGAAYK8xp7AgBWAQAGAAYK8xp7AgBWAQAQAAEKSBfiBwBTAAA1AAQKfzgAAwYACgrMIdMNAHoDAAYACgrMIdMNAHoDABAABAozFwsjACoBAAAA.',
Pa='Paedragon:BAAANQAECgQIBwAAAA==.Paimon:BAAANQADCgYIBgAAAA==.Paladareian:BAABNQAECn8uAAIbAAgKAyC+MgCaAgAbAAgKAyC+MgCaAgAAAA==.',
Pe='Pej:BAACNQAFFH8hAAQhAAYK8RXCAgDKAAASAAQKXxDCBwAKAQAhAAQKNxDCAgDKAAATAAMKhw20BwCrAAA1AAQKfz8ABBIACgqCHScPAGgCABIACApiICcPAGgCABMABwpPFwgdAPsBACEABgpPGbwDAAsBAAAA.Pejbolt:BAAANQADCgcICgABNQAFFAYIFAAaAGYiAA==.',
Ph='Phenomenon:BAAANQADCggICAABNQAECgYIDgAEAAAAAA==.Phoenixa:BAAANQAECgEIAQAAAA==.',
Pl='Plus:BAAANQAECgcICwAAAA==.',
Po='Powerslavé:BAACNQAFFH8GAAINAAMKVRYADwCpAAANAAMKVRYADwCpAAA1AAQKfywAAg0ACgobH20rAA4DAA0ACgobH20rAA4DAAAA.',
Pr='Priestitoot:BAAANQAECgMIAwAAAA==.Proust:BAAANQADCggIDgAAAA==.',
Pu='Pumkinhead:BAABNQAECn8hAAIGAAoKnQymYwD2AQAGAAoKnQymYwD2AQAAAA==.',
Py='Pyromania:BAAANQAECgYIDgAAAA==.',
['Pä']='Pä:BAAANQADCgMIAQAAAA==.',
Ra='Raiden:BAABNQAECn8cAAIWAAgKZQ3/sAC9AQAWAAgKZQ3/sAC9AQAAAA==.Rat:BAAANQABCgIIAgAAAA==.Rauck:BAAANQADCgUIBQABNQAECgYICAAEAAAAAA==.',
Re='Rentacat:BAAANQAECgQIBAAAAA==.Retropâlly:BAAANQADCgMIAwAAAA==.Revoker:BAAANQADCgUICAABNQAECgoKKAARAN4YAA==.',
Ro='Rogi:BAAANQAECgYIBwABNQABCgIIAgAEAAAAAA==.',
['Rö']='Römana:BAABNQAECn8bAAIRAAcKmw8inADPAQARAAcKmw8inADPAQAAAA==.',
Sa='Sanguinaris:BAAANQAECgEIAQABNQAECgYIEgAEAAAAAA==.Sareya:BAAANQABCggIDwAAAA==.Sataanic:BAAANQAECgQIBwAAAA==.Satyrical:BAABNQAECn8gAAQCAAgKzhXwSgDpAQACAAgKzhXwSgDpAQAMAAYKLAvUJAAOAQAHAAIKbAvXtwBYAAAAAA==.',
Sc='Scorch:BAABNQAECn8UAAIUAAcKuRXZ0QDjAQAUAAcKuRXZ0QDjAQAAAA==.',
Se='Sedrayn:BAAANQAECgYIBwAAAA==.Selatha:BAAANQABCgIIAgABNQAFFAUIDwAUALoYAA==.Selystine:BAAANQADCgUICAAAAA==.Semaj:BAAANQADCgcIBwAAAA==.Sergantis:BAAANQADCggIDgAAAA==.',
Sh='Shagee:BAAANQAECgEIAQAAAA==.Shamwowolio:BAABNQAECn8vAAIGAAoK/RWhOQCQAgAGAAoK/RWhOQCQAgAAAA==.Shayd:BAABNQAECn8oAAQRAAoK3hgwVwBtAgAcAAgKGBccBQB6AgARAAkKvhgwVwBtAgAJAAMKJRixUwDYAAAAAA==.Shigz:BAAANQADCggICQAAAA==.Shirokyu:BAAANQADCggICAAAAA==.Shirra:BAAANQADCggIDwAAAA==.Shirraz:BAABNQAECn8dAAIdAAgKKggPEQApAQAdAAgKKggPEQApAQAAAA==.Sho:BAAANQAECgUIBQAAAA==.Shroomicide:BAAANQAECggIBgAAAA==.',
Si='Sicaris:BAAANQADCgYICgABNQAECggIEQAEAAAAAA==.Sicksdeep:BAACNQAFFH8KAAMNAAQKrg8xCgDkAAANAAMKrg8xCgDkAAAVAAEKAABsBgBEAAA1AAQKfyoAAg0ACgoMFi1fAG8CAA0ACgoMFi1fAG8CAAAA.Sigürd:BAAANQADCgEIAQAAAA==.Silverstorm:BAAANQAECgUIDgAAAA==.',
Sk='Skÿe:BAABNQAECn8nAAIJAAkKyxhSAwDuAQAJAAkKyxhSAwDuAQAAAA==.',
Sl='Slamma:BAACNQAFFH8gAAINAAYKuyLMBgBVAgANAAYKuyLMBgBVAgA1AAQKfz4AAg0ACgpTJo0EANIDAA0ACgpTJo0EANIDAAAA.Slappin:BAAANQAECgIIAgAAAA==.Slappinbubs:BAAANQAECgEJAQAAAA==.Slicedbreád:BAACNQAFFH8eAAMXAAYKfgjKCwCQAQAXAAYKfgjKCwCQAQAGAAQK8BvEDwBxAQA1AAQKfzQAAxcACgohGPFOACkCABcACgohGPFOACkCAAYAAwpYJFeyAC4BAAE1AAQKAQgBAAQAAAAA.',
Sm='Smokadaganga:BAABNQAECn8WAAMiAAkKqwmmBABXAQAiAAYK1gumBABXAQAUAAcKWwU/KgFFAQAAAA==.',
So='Sols:BAAANQAECgYIDQABNQAFFAMIBgANAFUWAA==.Sondirion:BAABNQAECn8YAAIJAAcKtxSyMwCwAQAJAAcKtxSyMwCwAQAAAA==.Soulancer:BAAANQAECgQIBAABNQAECgYIEgAEAAAAAA==.Sowet:BAAANQAECgIIAgAAAA==.',
Sp='Speoghii:BAABNQAECn8kAAIBAAoKnhrFRwB7AgABAAoKnhrFRwB7AgAAAA==.Spifftreebug:BAABNQAECn8sAAMIAAoKsg7FGQAUAQAIAAkK8QvFGQAUAQAgAAIKTQu8dQA1AAAAAA==.Sprinklez:BAAANQAECgUIEgAAAA==.',
St='Steelerschic:BAAANQAECgQICwAAAA==.Stormleader:BAABNQAECn84AAMgAAoK2hU7FgCSAgAgAAoK2hU7FgCSAgAjAAEKAAAzdgATAAAAAA==.',
Su='Surge:BAAANQAECgQIBwAAAA==.',
Ta='Tai:BAABNQAECn8nAAIkAAkKWhlKAgDsAQAkAAkKWhlKAgDsAQAAAA==.Tainema:BAAANQAECgIIBAAAAA==.Tankguywowie:BAAANQAECgUIBQABNQAFFAUIDAAIAEgJAA==.Taurriel:BAAANQAECgYIEAAAAA==.Tazzm:BAABNQAECn8kAAIJAAgK2gRGQABSAQAJAAgK2gRGQABSAQAAAA==.',
Te='Teranok:BAABNQAECn8WAAQlAAkK4hazEQDLAQAlAAgK4RizEQDLAQAFAAYKZBFZPAAzAQAmAAEK1gFHVQAfAAAAAA==.Terzal:BAAANQADCgYIBgAAAA==.',
Th='Thalel:BAAANQAECgQIDgAAAA==.Theacused:BAAANQAECggIDQABNQAFFAMICQACAHAUAA==.Thoir:BAACNQAFFH8hAAIXAAYKnyMiAQA7AgAXAAYKnyMiAQA7AgA1AAQKfzwAAhcACgqhJfwGAIsDABcACgqhJfwGAIsDAAE1AAUUBgghABgAaQEA.Thorodinson:BAAANQAECgQIBQAAAA==.',
Ti='Tipsylorcet:BAABNQAECn8aAAIlAAgKcxuXDQAhAgAlAAgKcxuXDQAhAgAAAA==.',
Tk='Tkrain:BAAANQADCgYIGAAAAA==.',
Tr='Traen:BAAANQADCggICAAAAA==.Trashbull:BAAANQAECggIAgAAAA==.Tricktickler:BAAANQAECgQICQAAAA==.Troy:BAAANQADCgUIBQAAAA==.',
Tu='Tuskani:BAAANQABCggIGgAAAA==.',
Ty='Tybird:BAABNQAECn8tAAIMAAkKGBvTBQAAAgAMAAkKGBvTBQAAAgAAAA==.Tyranisv:BAAANQADCgMIAwAAAA==.',
Ul='Ulsull:BAAANQADCgcIEAABNQADCggIDgAEAAAAAA==.Ulybonez:BAAANQAECggIEAABNQAFFAYIIQAZAAAfAA==.Ulyssi:BAACNQAFFH8hAAIZAAYKAB+NAQB6AQAZAAYKAB+NAQB6AQA1AAQKfzwAAhkACgoDJCMDAKkDABkACgoDJCMDAKkDAAAA.',
Um='Ummpatas:BAAANQAECgEIAQAAAA==.',
Us='Usseel:BAAANQADCgMIAwAAAA==.',
['Uñ']='Uñàble:BAAANQADCgIIAgAAAA==.',
Va='Valymus:BAAANQADCgIIAgABNQAECgoKKAARAN4YAA==.Vandagylon:BAAANQADCgYIDAAAAA==.Vandals:BAAANQAECgcIEAAAAA==.',
Ve='Ven:BAABNQAECn8cAAIZAAgKuAaVPgA4AQAZAAgKuAaVPgA4AQAAAA==.Ver:BAAANQADCgMIAQAAAA==.',
Vo='Voltaire:BAAANQADCgIIAgAAAA==.',
Wa='Walle:BAAANQADCgEIAQAAAA==.Wankstar:BAAANQAECgEIAQAAAA==.Wargas:BAAANQABCgIIAgAAAA==.Warvein:BAABNQAECn8dAAMNAAkKrw8CjwD2AQANAAgKxBECjwD2AQAkAAQKMAdwNACTAAAAAA==.',
We='Weehunt:BAABNQAECn8bAAIRAAgKGBA4kQDnAQARAAgKGBA4kQDnAQAAAA==.Weeshami:BAAANQADCgMIAwAAAA==.',
Wh='Whillia:BAAANQADCgMIAwAAAA==.',
Wi='Wicah:BAAANQAECgQIDQAAAA==.Wicka:BAABNQAECn8sAAIXAAgKqSCJBwBOAgAXAAgKqSCJBwBOAgAAAA==.Widowblade:BAAANQAECgUIBQAAAA==.Wildriver:BAABNQAECn8VAAIgAAYKLxuaKQDSAQAgAAYKLxuaKQDSAQAAAA==.Willferàl:BAAANQADCgMIAwAAAA==.',
Xa='Xaehyun:BAACNQAFFH8lAAIFAAkKxyNkAABdAwAFAAkKxyNkAABdAwA1AAQKfx8AAgUACgr8JkAWAJ4CAAUACgr8JkAWAJ4CAAAA.Xandrelar:BAAANQAECgQIBAABNQAECgoKKAARAN4YAA==.',
Xm='Xmrpdk:BAACNQAFFH8hAAIHAAYKiSTrAgBtAgAHAAYKiSTrAgBtAgA1AAQKfzwAAgcACgrXJf8BANQDAAcACgrXJf8BANQDAAAA.Xmrppally:BAAANQAECgcICAABNQAFFAYIIQAHAIkkAA==.',
Xy='Xy:BAAANQADCggICAAAAA==.',
Ya='Yarina:BAAANQADCgUIBQAAAA==.',
Yo='Yoyiek:BAACNQAFFH8MAAIIAAUKSAm0FAAhAQAIAAUKSAm0FAAhAQA1AAQKfyQAAwgACgpcFGEuAGsCAAgACgpcFGEuAGsCACMAAwq6AjBSAFoAAAAA.',
Za='Zalynn:BAAANQAECgEIAQAAAA==.Zanne:BAACNQAFFH8HAAIJAAMKVRRWBgDJAAAJAAMKVRRWBgDJAAA1AAQKfyYAAgkACgrxHd8XAJkCAAkACgrxHd8XAJkCAAAA.Zarthul:BAAANQAECgUICAAAAA==.',
Ze='Zehara:BAAANQADCgMJAwAAAA==.Zenori:BAAANQADCggIDgAAAA==.',
Zh='Zhenyu:BAAANQADCgQIBAABNQAECgYIEgAEAAAAAA==.',
Zl='Zlot:BAECNQAFFH8hAAMRAAYKUiHEDACGAQARAAQKwiHEDACGAQAJAAQKFCDCAwAIAQA1AAQKfzwAAwkACgpXJLoGAH0BABEABwqsJm8iAA0DAAkACQrvH7oGAH0BAAAA.',
Zu='Zulani:BAAANQADCgIIAgAAAA==.',
['Õn']='Õneshot:BAABNQAECn8VAAIYAAcKGRVJbwDQAQAYAAcKGRVJbwDQAQAAAA==.',
['Øñ']='Øñêshot:BAAANQADCggIEwABNQAECgcIFQAYABkVAA==.',
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
