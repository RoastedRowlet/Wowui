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

local lookup = {'Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Warlock-Destruction','Shaman-Elemental','Paladin-Retribution','Monk-Windwalker','Monk-Mistweaver','Priest-Shadow','DeathKnight-Blood','DeathKnight-Frost','Druid-Balance','Warrior-Fury','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Warrior-Arms','Warlock-Affliction','Shaman-Enhancement','Hunter-BeastMastery','Paladin-Holy','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Shaman-Restoration','Paladin-Protection','Priest-Holy','DemonHunter-Havoc','Hunter-Survival','DemonHunter-Devourer','Priest-Discipline','Druid-Restoration','Warrior-Protection','Evoker-Augmentation','Mage-Fire','Druid-Guardian','Monk-Brewmaster',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aaralia:BAAANQAECgUIDAAAAA==.',
Ab='Abyssdark:BAABNQAECn9JAAIBAAoKVBtlKADjAgABAAoKVBtlKADjAgAAAA==.',
Ac='Accusation:BAACNQAFFH8SAAICAAYKNBtkAwBYAQACAAYKNBtkAwBYAQA1AAQKfxcAAgIACgo4FZ1IAPQBAAIACgo4FZ1IAPQBAAAA.',
Ae='Aerialana:BAAANQADCgYIBgAAAA==.',
Ak='Akadeus:BAAANQAECgIIAgAAAA==.',
Al='Alarielle:BAAANQAECgMICAABNQAECgoKRwADAMMWAA==.Altx:BAAANQABCgUIAwAAAA==.Alwaysdrunk:BAAANQAECgEIAQAAAA==.',
Am='Amirah:BAAANQADCgEIAgAAAA==.Ammathael:BAAANQAECgEJAQAAAA==.',
An='Anagela:BAAANQABCgUIBQABNQAECgQIDAAEAAAAAA==.Anamarie:BAAANQAECgQIBQABNQAECgkJGgAFAEATAA==.Antipasta:BAAANQAECggICgAAAA==.',
Ar='Aramist:BAAANQAECgEIAQAAAA==.',
As='Ashergreyson:BAAANQADCgYIBgAAAA==.Ashikahammer:BAAANQAECgYIDQABNQAECgkJIgADAJQgAA==.Ashtaroth:BAABNQAECn8jAAIBAAgKUwnvlwApAQABAAgKUwnvlwApAQABNQAECgoKRwADAMMWAA==.',
Az='Azraeth:BAAANQAECgYIEgABNQAECgoKGQAGAOgOAA==.',
Ba='Bacon:BAAANQAECgcICgABNQAECgoKHgAHABMPAA==.Baehyun:BAAANQAECggIDQABNQAFFAoKOAAIAPYkAA==.Basou:BAAANQADCggICAAAAA==.Baspar:BAAANQADCgIIAgAAAA==.',
Be='Belanova:BAAANQADCgQIBAAAAA==.Belnathas:BAAANQADCggIHAAAAA==.',
Bl='Blamethemage:BAAANQAECgcICQABNQAECgoKSgAGAAUaAA==.Bloodbeard:BAAANQAECgYICAAAAA==.Bloodedge:BAAANQADCgIIBAAAAA==.',
Bo='Bohmbear:BAAANQADCgYICgAAAA==.Bomboy:BAAANQAECgEIAQABNQAECgcICwAEAAAAAA==.',
Br='Brasha:BAAANQAECgcICAAAAA==.Brentobox:BAABNQAECn8yAAIJAAkKuB7kCgCTAgAJAAkKuB7kCgCTAgAAAA==.Brogdar:BAAANQADCgQIBAAAAA==.Brugara:BAAANQADCggIFwAAAA==.',
Bu='Bungeholio:BAABNQAECn8gAAIKAAkKXQoRJgBUAQAKAAkKXQoRJgBUAQABNQAECgoKSgAGAAUaAA==.',
Ca='Camael:BAAANQAECgYIDwAAAA==.Cannelle:BAABNQAECn8mAAIDAAkK+xEuCwDuAQADAAkK+xEuCwDuAQAAAA==.Carden:BAABNQAECn8yAAILAAkKVx+XGABAAgALAAkKVx+XGABAAgAAAA==.',
Ce='Cervantes:BAABNQAECn8YAAIMAAgKGwZNZwD+AAAMAAgKGwZNZwD+AAAAAA==.',
Ch='Charcyna:BAAANQAECgMICAABNQAFFAcIFAANAC0aAA==.Chardr:BAACNQAFFH8UAAINAAcKLRpEBQBRAgANAAcKLRpEBQBRAgA1AAQKfyYAAg0ACQqzJfIZAPgCAA0ACQqzJfIZAPgCAAAA.Chillywillie:BAABNQAECn8jAAIOAAkKZwhyGQDwAAAOAAkKZwhyGQDwAAAAAA==.Chrodne:BAAANQAECgIIAwAAAA==.Chucknorrîs:BAABNQAECn8cAAIIAAoK7gpjIwCAAQAIAAoK7gpjIwCAAQAAAA==.',
Ci='Cigam:BAAANQAECgQIDgAAAA==.',
Cl='Clintbarton:BAACNQAFFH8FAAIPAAIKtAKpGwBtAAAPAAIKtAKpGwBtAAA1AAQKf1oAAg8ACgp8EdcUAPcBAA8ACgp8EdcUAPcBAAAA.',
Cr='Crûtch:BAAANQADCggIDgAAAA==.',
Ct='Cthullu:BAAANQADCggICAAAAA==.',
Cu='Culebra:BAABNQAECn8uAAMQAAoKuxYmJQBhAgAQAAkKzxYmJQBhAgARAAUKdhOGnwDHAAAAAA==.',
['Cø']='Cøldshoulder:BAABNQAECn8qAAIMAAoKPRclMwATAgAMAAoKPRclMwATAgAAAA==.',
Da='Dabi:BAAANQADCgcIIAAAAA==.Daehyun:BAAANQAECggIDQABNQAFFAoKOAAIAPYkAA==.Danceofdeath:BAAANQAECgYIBwABNQAFFAUICQASADgZAA==.Dane:BAABNQAECn8fAAISAAkKOgzzjgBjAQASAAkKOgzzjgBjAQAAAA==.Darcmatter:BAABNQAECn8iAAQBAAoKKx0AaQAhAgABAAgKvxwAaQAhAgAFAAMKahyZNQDsAAATAAMKzhyPGwCfAAAAAA==.Darthmo:BAAANQADCgMIAwAAAA==.',
De='Deadtrap:BAAANQABCggIDwAAAA==.Deathdaddy:BAAANQAECgcIAwAAAA==.Deathsend:BAAANQADCgYICAAAAA==.Deepsicks:BAABNQAECn8pAAIUAAoKBxo3DgCIAgAUAAoKBxo3DgCIAgAAAA==.Deepstate:BAAANQAECgUIDQAAAA==.Deimos:BAAANQADCgYIBgABNQAECgYICAAEAAAAAA==.Demonaholio:BAAANQAECgQIBAABNQAECgoKSgAGAAUaAA==.Demonäde:BAAANQADCgUIAgAAAA==.',
Di='Dima:BAABNQAECn82AAIVAAkKzxfGWABpAgAVAAkKzxfGWABpAgAAAA==.Dithy:BAABNQAECn8YAAIWAAgKRQhPfwA4AQAWAAgKRQhPfwA4AQAAAA==.',
Dk='Dkrmk:BAAANQADCgMIAgAAAA==.Dktelli:BAABNQAECn8UAAMMAAgKPhGnSgCQAQAMAAgKPhGnSgCQAQALAAQKgAcWoACYAAABNQAECgoKVAAUAIcjAA==.',
Dn='Dne:BAAANQADCggIDgABNQAECgkJHwASADoMAA==.',
Do='Donavon:BAAANQAECgYIEAAAAA==.Donutjelly:BAABNQAECn8hAAINAAgKrRhrMQB+AQANAAgKrRhrMQB+AQAAAA==.Dorivandor:BAAANQAECgYIDQAAAA==.Dornnbryda:BAAANQADCggIDgABNQAECgoKLAAPABwUAA==.',
Dr='Drackothyr:BAABNQAECn8wAAMXAAkK0xqVCAD4AQAXAAkK0xqVCAD4AQAYAAMKKwXvRAB7AAAAAA==.Dreamweavver:BAAANQADCgQIBAAAAA==.Drumark:BAAANQADCgMIAwAAAA==.',
Du='Dugmaren:BAAANQABCggICAABNQAFFAQICAARAFIWAA==.Dumpsterfire:BAAANQAECgcIBwAAAA==.',
Dw='Dwastring:BAABNQAECn8xAAIVAAoKaBkwOgBlAgAVAAoKaBkwOgBlAgAAAA==.',
Dy='Dyrale:BAAANQADCgYIGwAAAA==.',
Ek='Eknivar:BAAANQAECgcIDQABNQAECgoKSQAZAHYdAA==.',
Er='Erebus:BAAANQAECgQIBAAAAA==.Erragorn:BAABNQAECn8jAAMOAAYK2BWBFgA0AQAOAAUKvhSBFgA0AQASAAYKUxS9vAD9AAAAAA==.',
Ev='Evisa:BAABNQAECn8hAAIZAAkKqwchqQBSAQAZAAkKqwchqQBSAQAAAA==.Evokholio:BAAANQAECgIIAwAAAA==.',
['Eö']='Eöath:BAAANQAECgEIAQAAAA==.',
Fa='Falaurenta:BAAANQADCgMIBgAAAA==.',
Fe='Fearzlol:BAAANQAECgIIAgABNQAFFAQICAARAFIWAA==.Fedahyin:BAAANQADCgUICQABNQADCggIFAAEAAAAAA==.Feidao:BAAANQAECgQIEgAAAA==.Feralith:BAAANQADCgMIAQAAAA==.',
Fl='Fluffytatas:BAAANQAECgYIBgAAAA==.',
Fo='Foshizzle:BAAANQABCgIIAgAAAA==.',
Fu='Funkenfox:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëânòr:BAAANQADCgUIBQAAAA==.',
Ga='Gailinn:BAABNQAECn8sAAIHAAoK8QbmtwBhAQAHAAoK8QbmtwBhAQAAAA==.',
Gh='Ghlen:BAAANQADCgEIAQAAAA==.',
Go='Gooraah:BAAANQADCgUIBQABNQADCgYICQAEAAAAAA==.Gorash:BAABNQAECn8ZAAIGAAoK6A4gQADTAQAGAAoK6A4gQADTAQAAAA==.',
Gr='Greggd:BAAANQADCgIIAgABNQAECgoKRgAaABwhAA==.Greggdshami:BAABNQAECn9GAAIaAAoKHCFpCQCEAwAaAAoKHCFpCQCEAwAAAA==.Gretagobbo:BAAANQAECgQIBQABNQAECgYICAAEAAAAAA==.',
Gu='Gundamus:BAAANQADCgYIBgAAAA==.Gurney:BAAANQADCgYIDAABNQADCggIFAAEAAAAAA==.Guthrum:BAAANQADCgQIBwAAAA==.',
Gw='Gwenaelle:BAABNQAECn8WAAIbAAkKzQXqKgAfAQAbAAkKzQXqKgAfAQAAAA==.',
Ha='Halorah:BAAANQADCgYICQAAAA==.',
He='Healmonger:BAACNQAFFH8IAAIcAAQKbR2GFgBQAQAcAAQKbR2GFgBQAQA1AAQKf18AAxwACgpdJNkQAEADABwACgpdJNkQAEADAAoABwouCXM4ANYAAAAA.Hekili:BAABNQAECn8WAAIaAAkKzRsnKACKAgAaAAkKzRsnKACKAgAAAA==.Helgrin:BAAANQADCgYIBgAAAA==.Helmfirth:BAAANQAECgQIBAAAAA==.Heruin:BAAANQAECggIEgAAAA==.',
Hi='Hictor:BAAANQADCgMIAwAAAA==.',
Ho='Holly:BAAANQAECgYIBQAAAA==.Holyomega:BAAANQADCgUIBQAAAA==.Holypackin:BAAANQAECgEIAwABNQAECgcICwAEAAAAAA==.Hongdou:BAAANQAECgQIAwAAAA==.Horse:BAACNQAFFH8rAAIcAAgKRgFVDwCxAQAcAAgKRgFVDwCxAQA1AAQKf0kAAhwACgpSDVBqAN8BABwACgpSDVBqAN8BAAAA.Hourzero:BAAANQAECgEIAQAAAA==.',
Ia='Iammyscars:BAACNQAFFH8OAAIdAAUKDRJFCwAeAQAdAAUKDRJFCwAeAQA1AAQKfz0AAh0ACgr8IGIPALYCAB0ACgr8IGIPALYCAAAA.',
Ic='Icu:BAAANQAECgcIDwAAAA==.',
Ik='Ikillu:BAABNQAECn8xAAIUAAgKFh4zDABUAgAUAAgKFh4zDABUAgAAAA==.',
Il='Ilis:BAAANQAECgQICwAAAA==.',
Im='Imachud:BAACNQAFFH8cAAIHAAkKjSK7AADfAgAHAAkKjSK7AADfAgA1AAQKfx8AAgcACgqnJXoEAHMDAAcACgqnJXoEAHMDAAAA.',
Ja='Jadawin:BAAANQABCgIIAgAAAA==.Jaiminvi:BAAANQADCgEIAQAAAA==.Jasnahh:BAAANQAECgQICQABNQAECgYICgAEAAAAAA==.Jaylas:BAAANQADCgEIAQABNQAECggILgAWAAMgAA==.',
Jo='Joeexotíc:BAACNQAFFH8QAAQeAAYK2yRHAACUAQAeAAUK4yRHAACUAQAVAAIK9iJ9GQDIAAAPAAEKixBRIwBHAAA1AAQKfzUABB4ACgqGJh4AAJUDAB4ACgqGJh4AAJUDAA8ABQpEFhtBAEwBABUAAwoUHKIEAfwAAAAA.',
Ju='Jun:BAACNQAFFH8eAAIdAAgK+CJsAwBPAgAdAAgK+CJsAwBPAgA1AAQKf0sAAx0ACgrDJq0AAPwDAB0ACgrDJq0AAPwDAB8ACAqAIgMdAGwCAAAA.Junfan:BAAANQAECggIEAAAAA==.',
Ka='Kandros:BAAANQABCgUIBwAAAA==.Kasumaus:BAABNQAECn8dAAQMAAkKtgYIYQAhAQAMAAkK4AUIYQAhAQACAAQK5AYipwCqAAALAAIKvwQYuABYAAAAAA==.',
Ke='Kelly:BAAANQADCggICAAAAA==.Kennifer:BAAANQADCggICQAAAA==.Kenshindune:BAAANQADCgQIBAAAAA==.Keragan:BAAANQADCgEJAQAAAA==.',
Kh='Khalyeesi:BAAANQADCgIIAwAAAA==.Khandris:BAAANQABCggIEwAAAA==.Khazjek:BAAANQADCgYICAAAAA==.Khephris:BAABNQAECn9HAAIDAAoKwxafCwAGAgADAAoKwxafCwAGAgAAAA==.',
Ki='Kiahrenee:BAAANQADCgYIBgAAAA==.Kiralni:BAAANQAECgYICwAAAA==.',
Kn='Knivex:BAABNQAECn9JAAMZAAoKdh3wnABHAgAZAAkK2hzwnABHAgADAAMK4h1eHQADAQAAAA==.',
Ko='Koryann:BAABNQAECn9JAAIbAAoK9xfGDwAsAgAbAAoK9xfGDwAsAgAAAA==.Kosel:BAAANQAECgcIEwAAAA==.Kova:BAABNQAECn8vAAIGAAoKLRNaPADjAQAGAAoKLRNaPADjAQAAAA==.',
Kr='Kramm:BAAANQAECgQIAgAAAA==.Krazyplaya:BAAANQAECgEIAQAAAA==.',
Kw='Kwarthil:BAAANQABCgEIAQAAAA==.',
Ky='Kyrise:BAABNQAECn8kAAIaAAoKIhdNMABfAgAaAAoKIhdNMABfAgAAAA==.',
La='Lambo:BAAANQAECgQJBAAAAA==.Landam:BAABNQAECn8hAAIHAAgKdguNyQBDAQAHAAgKdguNyQBDAQAAAA==.',
Le='Leap:BAAANQADCgMIAwABNQAECgoKMwAfAHAWAA==.Leviticus:BAAANQADCgQIBAAAAA==.',
Li='Lifeaura:BAACNQAFFH8VAAIgAAYKsBC1AADhAQAgAAYKsBC1AADhAQA1AAQKfzUAAiAACQr3ICABAFcDACAACQr3ICABAFcDAAAA.Lifesmage:BAAANQAECggIBgAAAA==.Lifesshaman:BAAANQAECggICAAAAA==.Lightbläster:BAAANQAECgIIBAAAAA==.Lightrider:BAAANQADCgYICwAAAA==.Linesta:BAAANQADCgEIAQAAAA==.Lionroar:BAACNQAFFH8TAAIhAAcKTRxmAwASAgAhAAcKTRxmAwASAgA1AAQKfzsAAyEACgouI+AHAEYDACEACgouI+AHAEYDAA0AAgp0DXd0AGUAAAAA.Littleguy:BAABNQAECn8kAAIGAAgKOwSFigD4AAAGAAgKOwSFigD4AAAAAA==.',
Ll='Llaothtaed:BAAANQAECggIBgAAAA==.',
Lo='Lochannis:BAABNQAECn8aAAIOAAoKaBFcDADBAQAOAAoKaBFcDADBAQAAAA==.Logi:BAABNQAECn8aAAMbAAoKNwfYMQDxAAAbAAoKLgfYMQDxAAAHAAMKoAWCbQFbAAAAAA==.Lokalock:BAABNQAECn8UAAIBAAcKQwv0rQD4AAABAAcKQwv0rQD4AAABNQAECgoKVAAUAIcjAA==.Lonee:BAAANQADCgIIAgAAAA==.Lorellei:BAABNQAECn8pAAIcAAgK8Ax6hgBFAQAcAAgK8Ax6hgBFAQAAAA==.Lothgow:BAAANQAECgEIAgAAAA==.',
Lu='Luxus:BAAANQAECgMIBQAAAA==.',
['Lâ']='Lân:BAACNQAFFH8IAAMRAAQKUhaeEQD6AAARAAQKUhaeEQD6AAAQAAIKHREdDQCDAAA1AAQKfx4AAxEACQpgHlMTAN4CABEACQrFHVMTAN4CABAACAq4GPAlAF0CAAAA.',
Ma='Maelynn:BAAANQADCgUIBQAAAA==.Magchro:BAAANQADCgQIBAABNQAECgIIAwAEAAAAAA==.Manticor:BAAANQADCgcIBgAAAA==.Martyglaive:BAABNQAECn8qAAIdAAgK2RiqIwDtAQAdAAgK2RiqIwDtAQAAAA==.Matteas:BAABNQAECn8UAAIHAAcKgxxTkgAAAgAHAAcKgxxTkgAAAgAAAA==.',
Me='Menionblue:BAAANQADCgUIBQAAAA==.Mew:BAAANQAECgUIDwAAAA==.',
Mf='Mfdoom:BAABNQAECn9DAAQBAAoKzyBcQQCOAgABAAkKySBcQQCOAgATAAQKxxq1FwDQAAAFAAMKfBV8PgDIAAABNQADCgIIBAAEAAAAAA==.',
Mi='Mizrey:BAACNQAFFH8GAAIMAAQKWQxLFgCRAAAMAAQKWQxLFgCRAAA1AAQKfzIAAgwACgqNH9cSAPcCAAwACgqNH9cSAPcCAAAA.Mizukisakura:BAAANQAECgQIBAAAAA==.',
Mo='Mograins:BAABNQAECn9UAAMFAAoKxiBHDQAkAgABAAkK/h+GJQB7AgAFAAYKXSFHDQAkAgAAAA==.Monzcarro:BAAANQADCggICwAAAA==.Mordar:BAAANQADCgUIBwAAAA==.Morgainne:BAABNQAECn8YAAIcAAgKmwdNigA6AQAcAAgKmwdNigA6AQAAAA==.Mortmor:BAAANQAECgYICwAAAA==.',
Ms='Mstrsinister:BAAANQAECgIIAwAAAA==.',
Mu='Muffinn:BAABNQAECn8wAAIVAAgK7w2JmQDUAQAVAAgK7w2JmQDUAQAAAA==.Mursê:BAAANQAECggICAAAAA==.',
My='Mymdos:BAABNQAECn9MAAISAAoKgSJxIAA2AwASAAoKgSJxIAA2AwABNQABCgIIAgAEAAAAAA==.Myrmidonn:BAAANQADCgYICgAAAA==.',
['Mä']='Mästérdòn:BAAANQAECgcIDgAAAA==.',
['Må']='Måsterdon:BAABNQAECn8bAAIbAAcKAwyfOQDHAAAbAAcKAwyfOQDHAAAAAA==.',
['Mô']='Môiraine:BAACNQAFFH8IAAIWAAQKcRQtEQAuAQAWAAQKcRQtEQAuAQA1AAQKfx8AAhYACQp+G+YkAJ8CABYACQp+G+YkAJ8CAAAA.',
Ne='Nercos:BAAANQAECgEIAQABNQAFFAIIAgAEAAAAAA==.Nercqt:BAAANQAFFAIIAgAAAA==.Neverborn:BAAANQAECgcIEgAAAA==.',
Ni='Niame:BAAANQAECgUIDAAAAA==.Nice:BAAANQAECgQIBAAAAA==.Nitraina:BAABNQAECn8WAAMDAAgKHgInMwBuAAAZAAcKGwF8jgGpAAADAAYKeAInMwBuAAAAAA==.Niyabelle:BAABNQAECn82AAMRAAoKmB0SMQA4AgARAAoKmB0SMQA4AgAQAAcKUhIbRAC4AQAAAA==.',
No='Noggenfloggr:BAAANQAECgUICAAAAA==.Nomesis:BAAANQAECgEIAQAAAA==.Norita:BAAANQADCgMIAwAAAA==.',
Ny='Nyxth:BAAANQADCgYIBgAAAA==.',
Oa='Oakmane:BAAANQABCgEIAQABNQAECgoKGQAGAOgOAA==.',
Od='Odïn:BAAANQADCgYIDAAAAA==.',
Ol='Oleevia:BAABNQAECn9LAAIKAAoK7BrYDACNAgAKAAoK7BrYDACNAgAAAA==.',
Om='Omgdingers:BAAANQAECgYICAABNQAECgoKGQAMAK8bAA==.',
On='Oneshót:BAAANQADCgYICAABNQAECgcIFQAcABkVAA==.Oneth:BAAANQAECgIIAgABNQAECggIFgAiAGIQAA==.',
Or='Oraxia:BAAANQAECgEIAQABNQAECgYICAAEAAAAAA==.Ords:BAAANQABCgYICAABNQAECgcICwAEAAAAAA==.Orgdynamite:BAAANQAECgcICgABNQAFFAgIKwAGABwaAA==.Orgsham:BAACNQAFFH8rAAMGAAgKHBo1BADrAQAGAAgKHBo1BADrAQAUAAEKSBfiBwBTAAA1AAQKf0IAAwYACgq9JNMNAHoDAAYACgq9JNMNAHoDABQABAozFwsjACoBAAAA.',
Pa='Paedragon:BAABNQAECn8WAAIiAAgKYhCUGgAzAQAiAAgKYhCUGgAzAQAAAA==.Paimon:BAAANQAECgEIAQAAAA==.Paladareian:BAABNQAECn8uAAIWAAgKAyC+MgCaAgAWAAgKAyC+MgCaAgAAAA==.',
Pe='Pej:BAACNQAFFH8rAAQXAAgKYBTCBwAKAQAXAAQKXxDCBwAKAQAjAAYKjQ7sBwD7AAAYAAQKPgrgDwDcAAA1AAQKf0wABBcACgqhHicPAGgCABcACQoJHicPAGgCABgABwpPFwgdAPsBACMABgovHHwLAKcBAAAA.Pejbolt:BAAANQADCgcICgABNQAFFAgIHgAdAPgiAA==.',
Ph='Phenomenon:BAAANQAECgUIBQABNQAECgkJGgAFAEATAA==.Phoenixa:BAAANQAECgEIAQAAAA==.',
Pl='Plus:BAAANQAECgcICwAAAA==.',
Po='Powerslavé:BAACNQAFFH8JAAISAAUKOBm3GQDjAAASAAUKOBm3GQDjAAA1AAQKfzoAAhIACgoQI+0UAP0CABIACgoQI+0UAP0CAAAA.',
Pr='Priestitoot:BAAANQAECgMIBAAAAA==.Proust:BAAANQADCggIDgAAAA==.',
Pu='Pumkinhead:BAABNQAECn8pAAIGAAoK2g2mYwD2AQAGAAoK2g2mYwD2AQAAAA==.',
Py='Pyromania:BAABNQAECn8aAAIFAAkKQBNnBQCkAQAFAAkKQBNnBQCkAQAAAA==.',
['Pä']='Pä:BAAANQADCgMIAQAAAA==.',
Qu='Quadzilla:BAAANQAECggIAQAAAA==.',
Ra='Raiden:BAABNQAECn8sAAIHAAkKUg9dpwCAAQAHAAkKUg9dpwCAAQAAAA==.Rat:BAAANQABCgIIAgAAAA==.Rauck:BAAANQAECgMIBQABNQAECgYICAAEAAAAAA==.',
Re='Rentacat:BAAANQAECgUICAAAAA==.Retropâlly:BAAANQADCgMIAwAAAA==.Revoker:BAAANQADCgUICAABNQAECgoKKAAVAN4YAA==.',
Ro='Rockbitér:BAAANQAECgMIAwABNQAECgYICAAEAAAAAA==.Rockbìter:BAAANQAECgMIAwABNQAECgYICAAEAAAAAA==.Rogi:BAAANQAECgUICAABNQABCgIIAgAEAAAAAA==.',
['Rö']='Römana:BAABNQAECn8iAAIVAAkKAw4inADPAQAVAAkKAw4inADPAQAAAA==.',
Sa='Saliva:BAAANQAECggIBAAAAA==.Sanguinaris:BAAANQAECgEIAQABNQAECgoKGQAGAOgOAA==.Sappinbubs:BAAANQAECgEIAQABNQAECgcICwAEAAAAAA==.Sareya:BAAANQABCggIDwAAAA==.Sataanic:BAAANQAECgQICwAAAA==.Satyrical:BAABNQAECn87AAQMAAoKYRUBNgDKAQACAAgKzhXwSgDpAQAMAAoKZg8BNgDKAQALAAQKDRBHbgCYAAAAAA==.',
Sc='Scfy:BAAANQAECggIDgABNQAFFAUICAALADINAA==.Scorch:BAABNQAECn8UAAIZAAcKuRXZ0QDjAQAZAAcKuRXZ0QDjAQAAAA==.',
Se='Sedrayn:BAAANQAECgYIBwAAAA==.Selatha:BAAANQABCgIIAgABNQAFFAYIEAAZAAEaAA==.Selystine:BAAANQADCgUICAAAAA==.Semaj:BAAANQADCgcIBwAAAA==.',
Sh='Shagee:BAAANQAECgEIAQAAAA==.Shamwowolio:BAABNQAECn9KAAMGAAoKBRrkJgBJAgAGAAoKBRrkJgBJAgAaAAIKCQPp7wA+AAAAAA==.Shayd:BAABNQAECn8oAAQVAAoK3hgwVwBtAgAeAAgKGBccBQB6AgAVAAkKvhgwVwBtAgAPAAMKJRixUwDYAAAAAA==.Shigz:BAAANQADCggICQAAAA==.Shirokyu:BAAANQADCggICAAAAA==.Shirra:BAAANQADCggIDwAAAA==.Shirraz:BAABNQAECn8rAAIfAAgKrgkVLgAnAQAfAAgKrgkVLgAnAQAAAA==.Sho:BAABNQAECn8eAAIHAAoKEw/9fADTAQAHAAoKEw/9fADTAQAAAA==.Shroomicide:BAAANQAECggIBgAAAA==.Shylinn:BAAANQAECgEIAQAAAA==.',
Si='Sicaris:BAAANQADCgYICgABNQAECggIEQAEAAAAAA==.Sicksdeep:BAACNQAFFH8PAAMSAAUKrg9jHQDOAAASAAQKrg9jHQDOAAAOAAEKAABsBgBEAAA1AAQKfz8AAxIACgrrH1MlAKsCABIACgrrH1MlAKsCAA4AAQoZHvQsAFQAAAAA.Sigürd:BAAANQADCgEIAQAAAA==.Silverblade:BAAANQAECgQIBAAAAA==.Silverstorm:BAABNQAECn8kAAIVAAYKigik3ABHAQAVAAYKigik3ABHAQAAAA==.',
Sk='Skÿe:BAABNQAECn9IAAIPAAoKoRsBDQBrAgAPAAoKoRsBDQBrAgAAAA==.',
Sl='Slamma:BAACNQAFFH8pAAISAAgKPiOoBQA0AgASAAgKPiOoBQA0AgA1AAQKf1kAAhIACgqdJo0EANIDABIACgqdJo0EANIDAAAA.Slappin:BAAANQAECgcICwAAAA==.Slappinbubs:BAAANQAECgQIBQABNQAECgcICwAEAAAAAA==.Slicedbreád:BAACNQAFFH8rAAMaAAcKhhHKCwCQAQAaAAYKBg7KCwCQAQAGAAUKDRjEDwBxAQA1AAQKf0MAAwYACgopI7AMAAoDAAYACgopI7AMAAoDABoACgohGPFOACkCAAE1AAQKAQgBAAQAAAAA.',
Sm='Smokadaganga:BAABNQAECn8WAAMkAAkKqwmmBABXAQAkAAYK1gumBABXAQAZAAcKWwU/KgFFAQAAAA==.',
So='Sols:BAAANQAECgYIDQABNQAFFAUICQASADgZAA==.Sondirion:BAABNQAECn8sAAIPAAoKHBROFQDxAQAPAAoKHBROFQDxAQAAAA==.Soulancer:BAAANQAECggIEQABNQAECgoKGQAGAOgOAA==.Sowet:BAAANQAECgIIAgAAAA==.',
Sp='Speoghii:BAABNQAECn8mAAIBAAoKnhrFRwB7AgABAAoKnhrFRwB7AgAAAA==.Spifftreebug:BAABNQAECn9FAAMNAAoKFQ+cKwClAQANAAoKFQ+cKwClAQAhAAkKOQlvMwBWAQAAAA==.Sprinklez:BAABNQAECn8cAAIUAAcK0hsGGgB1AQAUAAcK0hsGGgB1AQAAAA==.',
St='Steelerschic:BAABNQAECn8kAAIGAAcKCAQ6pQC8AAAGAAcKCAQ6pQC8AAAAAA==.Stormleader:BAACNQAFFH8IAAIhAAUKewb/CgALAQAhAAUKewb/CgALAQA1AAQKfz8AAyEACgpSGTsWAJICACEACgpSGTsWAJICACUAAQoAADN2ABMAAAAA.',
Su='Surge:BAAANQAECgUIDAAAAA==.',
Ta='Tai:BAABNQAECn9IAAIiAAoKIxuqCABWAgAiAAoKIxuqCABWAgAAAA==.Tainema:BAAANQAECgIIBAAAAA==.Tankguywowie:BAAANQAECgUIBQABNQAFFAcIEAANAMkNAA==.Taurriel:BAAANQAECgYIEAAAAA==.Tazzm:BAABNQAECn8kAAIPAAgK2gRGQABSAQAPAAgK2gRGQABSAQAAAA==.',
Te='Teranok:BAABNQAECn8ZAAQmAAkKGhezEQDLAQAmAAgKIRmzEQDLAQAIAAYKZBFZPAAzAQAJAAEK1gFHVQAfAAAAAA==.Terzal:BAAANQADCgYIBgAAAA==.',
Th='Thalel:BAAANQAECgQIDgAAAA==.Theacused:BAABNQAECn8cAAIZAAoKUR2nRwA2AgAZAAoKUR2nRwA2AgABNQAFFAYIEgACADQbAA==.Them:BAAANQADCgIIAgABNQAECgMIBAAEAAAAAA==.Thoir:BAACNQAFFH8rAAIaAAgKOCQjAQAmAwAaAAgKOCQjAQAmAwA1AAQKf0kAAhoACgrmJfwGAIsDABoACgrmJfwGAIsDAAE1AAUUCAgrABwARgEA.Thorodinson:BAAANQAECgcIEwAAAA==.',
Ti='Tipsylorcet:BAABNQAECn8uAAImAAkKwBuyBgAUAgAmAAkKwBuyBgAUAgAAAA==.',
Tk='Tkrain:BAAANQADCggIIAAAAA==.',
Tr='Traen:BAAANQAECgIIAgAAAA==.Trashbull:BAAANQAECggIAgAAAA==.Tricktickler:BAABNQAECn8YAAIWAAgK0xt/LwBkAgAWAAgK0xt/LwBkAgAAAA==.Troy:BAAANQADCgUIBQAAAA==.',
Tu='Tuskani:BAAANQABCggIGgAAAA==.',
Ty='Tybird:BAABNQAECn8/AAIMAAoKxR0vGQDBAgAMAAoKxR0vGQDBAgAAAA==.Tyranisv:BAAANQADCgMIAwAAAA==.',
Ul='Ulsull:BAAANQADCggIFAAAAA==.Ulybonez:BAEBNQAECn8XAAMQAAkKchPxVQBjAQAQAAgKag/xVQBjAQARAAgKTA53egA5AQABNQAFFAgIKwAKAOYfAA==.Ulyssi:BAECNQAFFH8rAAIKAAgK5h+QAgArAgAKAAgK5h+QAgArAgA1AAQKf0QAAgoACgoGJiMDAKkDAAoACgoGJiMDAKkDAAAA.',
Um='Ummpatas:BAAANQAECgEIAQAAAA==.',
Us='Usseel:BAAANQADCgQIBQAAAA==.',
['Uñ']='Uñàble:BAAANQADCgIIAgAAAA==.',
Va='Valymus:BAAANQADCgIIAgABNQAECgoKKAAVAN4YAA==.Vandagylon:BAAANQADCgYIDAAAAA==.Vandals:BAAANQAECgcIEAAAAA==.',
Ve='Ven:BAABNQAECn8wAAIKAAkK0Ad/JwBIAQAKAAkK0Ad/JwBIAQAAAA==.Ver:BAAANQADCgMIAQAAAA==.',
Vo='Voltaire:BAAANQADCgIIAgAAAA==.',
Wa='Walle:BAAANQADCgEIAQAAAA==.Wankstar:BAAANQAECgQIBAABNQAECgcICwAEAAAAAA==.Wargas:BAAANQABCgIIAgAAAA==.Warvein:BAABNQAECn8gAAMSAAkK/A8CjwD2AQASAAkK/A8CjwD2AQAiAAQKMAdwNACTAAAAAA==.',
We='Weehunt:BAABNQAECn8xAAIVAAoKPQ+BZwD1AQAVAAoKPQ+BZwD1AQAAAA==.Weeshami:BAAANQADCgMIAwAAAA==.',
Wh='Whillia:BAAANQADCgMIAwAAAA==.',
Wi='Wicah:BAABNQAECn8jAAIcAAgKCxo8PABKAgAcAAgKCxo8PABKAgAAAA==.Wicka:BAABNQAECn9NAAIaAAoKsSK1BgCtAwAaAAoKsSK1BgCtAwAAAA==.Widowblade:BAAANQAECgYIDgAAAA==.Wildriver:BAABNQAECn8gAAIhAAkKyBiVGwAtAgAhAAkKyBiVGwAtAgAAAA==.Willferàl:BAAANQADCgMIAwAAAA==.',
Xa='Xaehyun:BAACNQAFFH84AAIIAAoK9iQfAABsAwAIAAoK9iQfAABsAwA1AAQKfyoAAggACgoJJxcAAKMDAAgACgoJJxcAAKMDAAAA.Xandrelar:BAAANQAECgQIBAABNQAECgoKKAAVAN4YAA==.',
Xm='Xmrpdk:BAACNQAFFH8rAAILAAgKoyPrAgBtAgALAAgKoyPrAgBtAgA1AAQKf0oAAgsACgp0Jv8BANQDAAsACgp0Jv8BANQDAAAA.Xmrppally:BAAANQAECgcICAABNQAFFAgIKwALAKMjAA==.',
Xy='Xy:BAAANQADCggICAAAAA==.',
Ya='Yarina:BAAANQADCgUIBQAAAA==.',
Yo='Yoyiek:BAACNQAFFH8QAAINAAcKyQ20FAAhAQANAAcKyQ20FAAhAQA1AAQKfzUAAw0ACgrrHvgOALsCAA0ACgrrHvgOALsCACUAAwq6AjBSAFoAAAAA.',
Za='Zalynn:BAAANQAECgEIAQAAAA==.Zanne:BAACNQAFFH8IAAIPAAQKVRRuFACwAAAPAAQKVRRuFACwAAA1AAQKfy4AAg8ACgo1H98XAJkCAA8ACgo1H98XAJkCAAAA.Zaraele:BAAANQAECgQIBQAAAA==.Zarthul:BAAANQAECgQICAAAAA==.',
Ze='Zehara:BAAANQADCgMIBAAAAA==.Zenori:BAAANQADCggIDgAAAA==.',
Zh='Zhenyu:BAAANQADCgQIBAABNQAECgoKGQAGAOgOAA==.',
Zi='Ziely:BAAANQAECgUICQAAAA==.',
Zl='Zlot:BAECNQAFFH8rAAMVAAgKhxq+CQBTAQAVAAYKbxm+CQBTAQAPAAQKFCDYDwA/AQA1AAQKf0kAAxUACgrpJW8iAA0DABUACAoTJm8iAA0DAA8ACQroIDQZAI0CAAAA.',
Zu='Zulani:BAAANQAECgcIBQAAAA==.',
['Õn']='Õneshot:BAABNQAECn8VAAIcAAcKGRVJbwDQAQAcAAcKGRVJbwDQAQAAAA==.',
['Ör']='Öriana:BAAANQAECgYIBgAAAA==.',
['Øñ']='Øñêshot:BAAANQADCggIEwABNQAECgcIFQAcABkVAA==.',
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
