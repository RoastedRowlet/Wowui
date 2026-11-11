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

local lookup = {'Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Warlock-Destruction','Shaman-Elemental','Paladin-Retribution','Monk-Windwalker','Monk-Mistweaver','Priest-Shadow','DeathKnight-Blood','DeathKnight-Frost','Druid-Balance','Warrior-Fury','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Warrior-Arms','Warlock-Affliction','Shaman-Enhancement','Hunter-BeastMastery','Paladin-Holy','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Shaman-Restoration','Priest-Holy','DemonHunter-Havoc','Hunter-Survival','DemonHunter-Devourer','Paladin-Protection','Priest-Discipline','Druid-Restoration','Warrior-Protection','Evoker-Augmentation','Mage-Fire','Druid-Guardian','Monk-Brewmaster',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aaralia:BAAANQAECgYIDgAAAA==.',
Ab='Abyssdark:BAABNQAECn9EAAIBAAoKVBtlKADjAgABAAoKVBtlKADjAgAAAA==.',
Ac='Accusation:BAACNQAFFH8RAAICAAUK5xpkBQADAQACAAUK5xpkBQADAQA1AAQKfxcAAgIACgo4FZ1IAPQBAAIACgo4FZ1IAPQBAAAA.',
Ae='Aerialana:BAAANQADCgYIBgAAAA==.',
Ak='Akadeus:BAAANQAECgIIAwAAAA==.',
Al='Alarielle:BAAANQAECgMIDAABNQAECgoKQAADAOsVAA==.Altx:BAAANQAECgEIAQAAAA==.Alwaysdrunk:BAAANQAECgEIAQAAAA==.',
Am='Amirah:BAAANQADCgEIAgAAAA==.Ammathael:BAAANQAECgEJAQAAAA==.',
An='Anagela:BAAANQABCgUIBQABNQAECgQIDQAEAAAAAA==.Anamarie:BAAANQAECgQIBgABNQAECgkJGgAFAEATAA==.Antipasta:BAAANQAECggICAAAAA==.',
Ar='Aramist:BAAANQADCggIJQAAAA==.Arroy:BAAANQAECgEIAQAAAA==.',
As='Ashergreyson:BAAANQADCgYIBgAAAA==.Ashikahammer:BAAANQAECgYIDQABNQAECgkJIgADAJQgAA==.Ashtaroth:BAABNQAECn8jAAIBAAgKUwnTjgApAQABAAgKUwnTjgApAQABNQAECgoKQAADAOsVAA==.',
Az='Azraeth:BAAANQAECgYIEgABNQAECgoKFwAGAHANAA==.',
Ba='Bacon:BAAANQAECgQIBQABNQAECggIGgAHAL8MAA==.Baehyun:BAAANQAECggIDgABNQAFFAoKNQAIALwkAA==.Basou:BAAANQADCggICAAAAA==.Baspar:BAAANQADCgIIAgAAAA==.',
Be='Belanova:BAAANQADCgQIBAAAAA==.Belnathas:BAAANQADCggIHAAAAA==.',
Bi='Bigchonky:BAAANQAECgEIAQAAAA==.',
Bl='Blamethemage:BAAANQAECgcICgABNQAECgoKRgAGAFcZAA==.Bloodbeard:BAAANQAECgYICAAAAA==.Bloodedge:BAAANQADCgIIBAAAAA==.',
Bo='Bohmbear:BAAANQADCgYICgAAAA==.Bomboy:BAAANQAECgEIAwABNQAECgcIDAAEAAAAAA==.',
Br='Brasha:BAAANQAECgcIBwAAAA==.Brentobox:BAABNQAECn8qAAIJAAgK4B5yDQA3AgAJAAgK4B5yDQA3AgAAAA==.Brugara:BAAANQAECgEIAQAAAA==.',
Bu='Bullwalk:BAAANQAECgEIAgAAAA==.Bungeholio:BAABNQAECn8fAAIKAAgKygpTKAArAQAKAAgKygpTKAArAQABNQAECgoKRgAGAFcZAA==.',
Ca='Camael:BAAANQAECgYIEwAAAA==.Cannelle:BAABNQAECn8iAAIDAAkK+xHFCQDwAQADAAkK+xHFCQDwAQAAAA==.Carden:BAABNQAECn8qAAILAAgKOCCIHgD4AQALAAgKOCCIHgD4AQAAAA==.',
Ce='Cervantes:BAABNQAECn8VAAIMAAcKFAXKbwDJAAAMAAcKFAXKbwDJAAAAAA==.',
Ch='Charcyna:BAAANQAECgMICAABNQAFFAcIFAANAC0aAA==.Chardr:BAACNQAFFH8UAAINAAcKLRpEBQBRAgANAAcKLRpEBQBRAgA1AAQKfyYAAg0ACQqzJfIZAPgCAA0ACQqzJfIZAPgCAAAA.Chillywillie:BAABNQAECn8fAAIOAAYKaAqxGwDtAAAOAAYKaAqxGwDtAAAAAA==.Chrodne:BAAANQAECgIIAwAAAA==.Chucknorrîs:BAABNQAECn8XAAIIAAkKugvZJQBTAQAIAAkKugvZJQBTAQAAAA==.',
Ci='Cigam:BAAANQAECgUIEAAAAA==.',
Cl='Clintbarton:BAABNQAECn9VAAIPAAoKtxAAGgChAQAPAAoKtxAAGgChAQAAAA==.',
Cr='Crûtch:BAAANQADCggIDgAAAA==.',
Ct='Cthullu:BAAANQADCggICAAAAA==.',
Cu='Culebra:BAABNQAECn8uAAMQAAoKuxYmJQBhAgAQAAkKzxYmJQBhAgARAAUKdhMTlADHAAAAAA==.',
['Cø']='Cøldshoulder:BAABNQAECn8qAAIMAAoKPRclMwATAgAMAAoKPRclMwATAgAAAA==.',
Da='Dabi:BAAANQADCgcIIAAAAA==.Daehyun:BAAANQAECggIDQABNQAFFAoKNQAIALwkAA==.Danceofdeath:BAAANQAECgYICQABNQAFFAUICQASADgZAA==.Dane:BAABNQAECn8fAAISAAkKOgxBhQBlAQASAAkKOgxBhQBlAQAAAA==.Darcmatter:BAABNQAECn8iAAQBAAoKKx0AaQAhAgABAAgKvxwAaQAhAgAFAAMKahyZNQDsAAATAAMKzhzjGACkAAAAAA==.Darthmo:BAAANQADCgMIAwAAAA==.',
De='Deadtrap:BAAANQABCggIDwAAAA==.Deathsend:BAAANQADCgYICAAAAA==.Deepsicks:BAABNQAECn8pAAIUAAoKBxo3DgCIAgAUAAoKBxo3DgCIAgAAAA==.Deepstate:BAAANQAECgUIDQAAAA==.Deimos:BAAANQADCgYIBgABNQAECgYICAAEAAAAAA==.Demonaholio:BAAANQAECgQIBAABNQAECgoKRgAGAFcZAA==.Demonäde:BAAANQADCgUIAgAAAA==.Dezarda:BAAANQAECgEIAQAAAA==.',
Di='Dima:BAABNQAECn82AAIVAAkKzxfGWABpAgAVAAkKzxfGWABpAgAAAA==.Dithy:BAABNQAECn8WAAIWAAcKZgg3hgARAQAWAAcKZgg3hgARAQAAAA==.',
Dk='Dkrmk:BAAANQADCgMIAgAAAA==.Dktelli:BAABNQAECn8UAAMMAAgKPhGnSgCQAQAMAAgKPhGnSgCQAQALAAQKgAcWoACYAAABNQAECgoKVAAUAIcjAA==.',
Dn='Dne:BAAANQADCggIDgABNQAECgkJHwASADoMAA==.',
Do='Dolph:BAAANQAECgEIAQAAAA==.Donavon:BAAANQAECgYIEwAAAA==.Donutjelly:BAABNQAECn8hAAINAAgKrRi3LQB/AQANAAgKrRi3LQB/AQAAAA==.Dorivandor:BAAANQAECgUICgAAAA==.Dornnbryda:BAAANQADCggIDgABNQAECgoKKQAPABwUAA==.',
Dr='Drackothyr:BAABNQAECn8qAAMXAAkK0xp+CADqAQAXAAkK0xp+CADqAQAYAAMKKwXvRAB7AAAAAA==.Dreamweavver:BAAANQADCgQIBAAAAA==.Drumark:BAAANQADCgMIAwAAAA==.',
Du='Dugmaren:BAAANQABCggICAABNQAFFAQICAARAFIWAA==.Dumpsterfire:BAAANQAECgcIBwAAAA==.',
Dw='Dwastring:BAABNQAECn8xAAIVAAoKaBkVMwBqAgAVAAoKaBkVMwBqAgAAAA==.',
Dy='Dyrale:BAAANQADCgYIGwAAAA==.',
Ek='Eknivar:BAAANQAECgcIDQABNQAECgoKRQAZANocAA==.',
Er='Erebus:BAAANQAECgQIBAAAAA==.Erragorn:BAABNQAECn8jAAMOAAYK2BWBFgA0AQAOAAUKvhSBFgA0AQASAAYKUxTnsgD+AAAAAA==.',
Ev='Evisa:BAABNQAECn8gAAIZAAgKrwdcuwAdAQAZAAgKrwdcuwAdAQAAAA==.Evokholio:BAAANQAECgIIAwAAAA==.',
['Eö']='Eöath:BAAANQAECgEIAgAAAA==.',
Fa='Falaurenta:BAAANQADCgMIBgAAAA==.',
Fe='Fearzlol:BAAANQAECgIIAgABNQAFFAQICAARAFIWAA==.Fedahyin:BAAANQADCgUICQABNQAECgEIAQAEAAAAAA==.Feidao:BAABNQAECn8VAAIJAAUKFxfFGwA1AQAJAAUKFxfFGwA1AQAAAA==.Feralith:BAAANQADCgMIAQAAAA==.',
Fo='Foshizzle:BAAANQABCgIIAgAAAA==.Foxx:BAAANQAECgEIAQAAAA==.',
Fu='Funkenfox:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëânòr:BAAANQADCgUIBQAAAA==.',
Ga='Gailinn:BAABNQAECn8lAAIHAAgKDgau4gADAQAHAAgKDgau4gADAQAAAA==.',
Gh='Ghlen:BAAANQADCgEIAQAAAA==.',
Go='Gooraah:BAAANQADCgUIBQABNQADCgYICQAEAAAAAA==.Gorash:BAABNQAECn8XAAIGAAoKcA0MQQC5AQAGAAoKcA0MQQC5AQAAAA==.',
Gr='Greggd:BAAANQADCgIIAgABNQAECgoKPQAaABIfAA==.Greggdshami:BAABNQAECn89AAIaAAoKEh9oEgAUAwAaAAoKEh9oEgAUAwAAAA==.Gretagobbo:BAAANQAECgQIBAABNQAECgYICAAEAAAAAA==.',
Gu='Gundamus:BAAANQADCgYIBgAAAA==.Gurney:BAAANQADCgYIDAABNQAECgEIAQAEAAAAAA==.Guthrum:BAAANQADCgQIBwAAAA==.',
Gw='Gwenaelle:BAAANQAECgcIDQAAAA==.',
Ha='Halorah:BAAANQADCgYICQAAAA==.Hammburger:BAAANQAECgEIAgAAAA==.',
He='Healmonger:BAACNQAFFH8IAAIbAAQKbR1pEwBbAQAbAAQKbR1pEwBbAQA1AAQKf18AAxsACgpdJNkQAEADABsACgpdJNkQAEADAAoABwouCbo0ANYAAAAA.Hekili:BAAANQAECgUIDgAAAA==.Helgrin:BAAANQADCgYIBgAAAA==.Helmfirth:BAAANQADCgMIAwAAAA==.Heruin:BAAANQAECggIEgAAAA==.',
Hi='Hictor:BAAANQADCgMIAwAAAA==.',
Ho='Holly:BAAANQAECgYIBgAAAA==.Holyomega:BAAANQADCgUIBQAAAA==.Holypackin:BAAANQAECgEIAwABNQAECgcIDAAEAAAAAA==.Hongdou:BAAANQAECgQIAwAAAA==.Horse:BAACNQAFFH8pAAIbAAcKRQGbEQByAQAbAAcKRQGbEQByAQA1AAQKf0cAAhsACgpSDVBqAN8BABsACgpSDVBqAN8BAAAA.Hourzero:BAAANQAECgEIAQAAAA==.',
Ia='Iammyscars:BAACNQAFFH8OAAIcAAUKDRJMCQAlAQAcAAUKDRJMCQAlAQA1AAQKfz0AAhwACgr8INkNALoCABwACgr8INkNALoCAAAA.',
Ic='Icu:BAAANQAECgcIDwAAAA==.',
Ik='Ikillu:BAABNQAECn8vAAIUAAgKjR2sCwBMAgAUAAgKjR2sCwBMAgAAAA==.',
Il='Ilis:BAAANQAECgQICwAAAA==.Ilovecheetos:BAAANQAECgEIAQAAAA==.',
Im='Imachud:BAACNQAFFH8WAAIHAAgKuiJvAQBrAgAHAAgKuiJvAQBrAgA1AAQKfx8AAgcACgqnJX8DAHkDAAcACgqnJX8DAHkDAAAA.',
Ja='Jadawin:BAAANQAECgEIAgAAAA==.Jaiminvi:BAAANQADCgEIAQAAAA==.Jasnahh:BAAANQAECgQICQABNQAECgYICwAEAAAAAA==.Jaylas:BAAANQADCgEIAQABNQAECggILgAWAAMgAA==.',
Jo='Joeexotíc:BAACNQAFFH8QAAQdAAYK2yQ2AACiAQAdAAUK4yQ2AACiAQAVAAIK9iLFFgDLAAAPAAEKixBRIwBHAAA1AAQKfzUABB0ACgqGJhkAAJcDAB0ACgqGJhkAAJcDAA8ABQpEFhtBAEwBABUAAwoUHKIEAfwAAAAA.',
Ju='Jun:BAACNQAFFH8cAAIcAAcK2SJsAwBPAgAcAAcK2SJsAwBPAgA1AAQKf0kAAxwACgrDJq0AAPwDABwACgrDJq0AAPwDAB4ACAqAIgMdAGwCAAAA.Junfan:BAAANQAECggIEAAAAA==.',
Ka='Kandros:BAAANQABCgUIBwAAAA==.Kasumaus:BAABNQAECn8dAAQMAAkKtgYIYQAhAQAMAAkK4AUIYQAhAQACAAQK5AYipwCqAAALAAIKvwQYuABYAAAAAA==.',
Ke='Kelly:BAAANQADCggICAAAAA==.Kennifer:BAAANQADCggICQAAAA==.Kenshindune:BAAANQADCgQIBAAAAA==.Keragan:BAAANQADCgEJAQAAAA==.Kevrad:BAAANQAECgEIAwAAAA==.',
Kh='Khalyeesi:BAAANQADCgIIAwAAAA==.Khandris:BAAANQABCggIEwAAAA==.Khazjek:BAAANQADCgYICAAAAA==.Khephris:BAABNQAECn9AAAIDAAoK6xWfCwAGAgADAAoK6xWfCwAGAgAAAA==.',
Ki='Kiahrenee:BAAANQADCgYIBgAAAA==.Kiralni:BAAANQAECgMIBAAAAA==.',
Kn='Knivex:BAABNQAECn9FAAMZAAoK2hzwnABHAgAZAAkKKBzwnABHAgADAAMK4h1eHQADAQAAAA==.',
Ko='Koryann:BAABNQAECn8/AAIfAAoKKBfIDwAXAgAfAAoKKBfIDwAXAgAAAA==.Kosel:BAAANQAECgcIEQAAAA==.Kova:BAABNQAECn8oAAIGAAoKrRA+PwDBAQAGAAoKrRA+PwDBAQAAAA==.',
Kr='Kramm:BAAANQAECgQIAgAAAA==.Krazyplaya:BAAANQAECgEIAQAAAA==.',
Kw='Kwarthil:BAAANQAECgEIAgAAAA==.',
Ky='Kyrise:BAABNQAECn8jAAIaAAoKIhcJKwBlAgAaAAoKIhcJKwBlAgAAAA==.',
La='Lambo:BAAANQAECgQJBAAAAA==.Landam:BAABNQAECn8fAAIHAAgKqQp3vwA+AQAHAAgKqQp3vwA+AQAAAA==.',
Le='Leap:BAAANQADCgMIAwABNQAECgoKMwAeAHAWAA==.Leviticus:BAAANQADCgQIBAAAAA==.',
Li='Lifeaura:BAACNQAFFH8VAAIgAAYKsBC1AADhAQAgAAYKsBC1AADhAQA1AAQKfzUAAiAACQr3ICABAFcDACAACQr3ICABAFcDAAAA.Lifesmage:BAAANQAECggIBgAAAA==.Lifesshaman:BAAANQAECggICAAAAA==.Lightbläster:BAAANQAECgIICAAAAA==.Lightrider:BAAANQADCgYICwAAAA==.Linesta:BAAANQADCgEIAQAAAA==.Lionroar:BAACNQAFFH8TAAIhAAcKTRxmAwASAgAhAAcKTRxmAwASAgA1AAQKfzoAAyEACgouI+AHAEYDACEACgouI+AHAEYDAA0AAgp0DSRvAGUAAAAA.Littleguy:BAABNQAECn8kAAIGAAgKOwQSgQD4AAAGAAgKOwQSgQD4AAAAAA==.',
Ll='Llaothtaed:BAAANQAECggIBgAAAA==.',
Lo='Lochannis:BAABNQAECn8aAAIOAAoKaBH1CgDGAQAOAAoKaBH1CgDGAQAAAA==.Logi:BAABNQAECn8aAAMfAAoKNwduLgDxAAAfAAoKLgduLgDxAAAHAAMKoAWYXAFcAAAAAA==.Lokalock:BAABNQAECn8UAAIBAAcKQwtZpAD5AAABAAcKQwtZpAD5AAABNQAECgoKVAAUAIcjAA==.Lonee:BAAANQAECgEIAQAAAA==.Lorellei:BAABNQAECn8pAAIbAAgK8AwpfABMAQAbAAgK8AwpfABMAQAAAA==.Lothgow:BAAANQAECgEIAgAAAA==.',
Lu='Luxus:BAAANQAECgMIBQAAAA==.',
['Lâ']='Lân:BAACNQAFFH8IAAMRAAQKUhaZDwD7AAARAAQKUhaZDwD7AAAQAAIKHRFeCwCDAAA1AAQKfx4AAxEACQpgHqgRAOECABEACQrFHagRAOECABAACAq4GPAlAF0CAAAA.',
Ma='Maelynn:BAAANQADCgUIBQAAAA==.Magchro:BAAANQADCgQIBAABNQAECgIIAwAEAAAAAA==.Manticor:BAAANQADCgcIBgAAAA==.Martyglaive:BAABNQAECn8qAAIcAAgK2RijIADxAQAcAAgK2RijIADxAQAAAA==.Matknight:BAAANQAECgEIAQAAAA==.Matteas:BAABNQAECn8UAAIHAAcKgxxTkgAAAgAHAAcKgxxTkgAAAgAAAA==.',
Me='Menionblue:BAAANQADCgUIBQAAAA==.Mew:BAAANQAECgUIEQAAAA==.',
Mf='Mfdoom:BAABNQAECn9DAAQBAAoKzyBYNQArAgABAAkKySBYNQArAgATAAQKxxq1FwDQAAAFAAMKfBV8PgDIAAABNQADCgIIBAAEAAAAAA==.',
Mi='Mizrey:BAACNQAFFH8GAAIMAAQKWQzFEwCVAAAMAAQKWQzFEwCVAAA1AAQKfzAAAgwACgqNH9cSAPcCAAwACgqNH9cSAPcCAAAA.Mizukisakura:BAAANQAECgQIBAAAAA==.',
Mo='Mograins:BAABNQAECn9LAAMFAAoKoyBHDQAkAgABAAkK1h/kIwBzAgAFAAYKXSFHDQAkAgAAAA==.Monzcarro:BAAANQADCggICwAAAA==.Mordar:BAAANQADCgUIBwAAAA==.Morgainne:BAABNQAECn8WAAIbAAcKIwjqkgAKAQAbAAcKIwjqkgAKAQAAAA==.Mortmor:BAAANQAECgYIDAAAAA==.',
Ms='Mstrsinister:BAAANQAECgIIAgAAAA==.',
Mu='Muffinn:BAABNQAECn8vAAIVAAgKVQ2JmQDUAQAVAAgKVQ2JmQDUAQAAAA==.Mursê:BAAANQAECggICAAAAA==.',
My='Mymdos:BAABNQAECn9MAAISAAoKgSJxIAA2AwASAAoKgSJxIAA2AwABNQABCgIIAgAEAAAAAA==.Myrmidonn:BAAANQADCgYICgAAAA==.',
['Mä']='Mästérdòn:BAAANQAECgcIEAAAAA==.',
['Må']='Måsterdon:BAABNQAECn8bAAIfAAcKAwzlNQDHAAAfAAcKAwzlNQDHAAAAAA==.',
['Mô']='Môiraine:BAACNQAFFH8IAAIWAAQKcRQ8DwA1AQAWAAQKcRQ8DwA1AQA1AAQKfx8AAhYACQp+G9MgAKgCABYACQp+G9MgAKgCAAAA.',
Ne='Nercos:BAAANQAECgEIAQABNQAFFAIIAgAEAAAAAA==.Nercqt:BAAANQAFFAIIAgAAAA==.Neverborn:BAAANQAECgcIEgAAAA==.',
Ni='Niame:BAAANQAECgUIDAAAAA==.Nice:BAAANQAECgQIBAAAAA==.Nitraina:BAABNQAECn8WAAMDAAgKHgInMwBuAAAZAAcKGwF8jgGpAAADAAYKeAInMwBuAAAAAA==.Niyabelle:BAABNQAECn82AAMRAAoKmB05LAA7AgARAAoKmB05LAA7AgAQAAcKUhIbRAC4AQAAAA==.',
No='Noggenfloggr:BAAANQAECgUICQAAAA==.Nomesis:BAAANQAECgEIAgAAAA==.Norita:BAAANQADCgMIAwAAAA==.',
Ny='Nyxth:BAAANQADCgYIBgAAAA==.',
Oa='Oakmane:BAAANQABCgEIAQABNQAECgoKFwAGAHANAA==.',
Od='Odïn:BAAANQAECgEIAgAAAA==.',
Ol='Oleevia:BAABNQAECn9LAAIKAAoK7BruCwCNAgAKAAoK7BruCwCNAgAAAA==.',
Om='Omgdingers:BAAANQAECgYICQABNQAECgoKGQAMAK8bAA==.',
On='Oneshót:BAAANQADCgYICAABNQAECgcIFQAbABkVAA==.Oneth:BAAANQAECgIIAgABNQAECgcIFAAiAOAPAA==.',
Or='Oraxia:BAAANQAECgEIAQABNQAECgYICAAEAAAAAA==.Ords:BAAANQAECgEIAQABNQAECgcIDAAEAAAAAA==.Orgdynamite:BAAANQAECgcICgABNQAFFAcIKQAGANccAA==.Orgsham:BAACNQAFFH8pAAMGAAcK1xzwBACeAQAGAAcK1xzwBACeAQAUAAEKSBfiBwBTAAA1AAQKf0AAAwYACgq9JNMNAHoDAAYACgq9JNMNAHoDABQABAozFwsjACoBAAAA.',
Pa='Paedragon:BAABNQAECn8UAAIiAAcK4A/MHQD7AAAiAAcK4A/MHQD7AAAAAA==.Paimon:BAAANQAECgEIAgAAAA==.Paladareian:BAABNQAECn8uAAIWAAgKAyC+MgCaAgAWAAgKAyC+MgCaAgAAAA==.',
Pe='Pej:BAACNQAFFH8pAAQXAAcK4xfCBwAKAQAjAAUKdhJoBgAgAQAXAAQKXxDCBwAKAQAYAAQKPgoaDgDfAAA1AAQKf0oABBcACgqhHicPAGgCABcACQoJHicPAGgCABgABwpPFwgdAPsBACMABgovHHwLAKcBAAAA.Pejbolt:BAAANQADCgcICgABNQAFFAcIHAAcANkiAA==.',
Ph='Phenomenon:BAAANQAECgUIBQABNQAECgkJGgAFAEATAA==.Phoenixa:BAAANQAECgEIAQAAAA==.',
Pl='Plus:BAAANQAECgcIDwAAAA==.',
Po='Powerslavé:BAACNQAFFH8JAAISAAUKOBmaFgDkAAASAAUKOBmaFgDkAAA1AAQKfzoAAhIACgoQI0ASAAUDABIACgoQI0ASAAUDAAAA.',
Pr='Priestitoot:BAAANQAECgMIBAAAAA==.Proust:BAAANQADCggIDgAAAA==.',
Pu='Pumkinhead:BAABNQAECn8pAAIGAAoK2g2mYwD2AQAGAAoK2g2mYwD2AQAAAA==.',
Py='Pyromania:BAABNQAECn8aAAIFAAkKQBPKBACnAQAFAAkKQBPKBACnAQAAAA==.',
['Pä']='Pä:BAAANQADCgMIAQAAAA==.',
Qu='Quadzilla:BAAANQAECggIAQAAAA==.',
Ra='Raiden:BAABNQAECn8sAAIHAAkKUg+SmQCEAQAHAAkKUg+SmQCEAQAAAA==.Rat:BAAANQABCgIIAgAAAA==.Rauck:BAAANQAECgMIBAABNQAECgYICAAEAAAAAA==.',
Re='Rentacat:BAAANQAECgUICQAAAA==.Retropâlly:BAAANQADCgMIAwAAAA==.Revoker:BAAANQADCgUICAABNQAECgoKKAAVAN4YAA==.Reyl:BAAANQAECgEIAQAAAA==.',
Ro='Rockbìter:BAAANQAECgMIAwABNQAECgYICAAEAAAAAA==.Rogi:BAAANQAECgUICQABNQABCgIIAgAEAAAAAA==.',
['Rö']='Römana:BAABNQAECn8hAAIVAAkKAw4inADPAQAVAAkKAw4inADPAQAAAA==.',
Sa='Saliva:BAAANQAECggIBAAAAA==.Sanguinaris:BAAANQAECgEIAQABNQAECgoKFwAGAHANAA==.Sappinbubs:BAAANQAECgEIAQABNQAECgcIDAAEAAAAAA==.Sareya:BAAANQABCggIDwAAAA==.Sataanic:BAAANQAECgUICQAAAA==.Satyrical:BAABNQAECn81AAQMAAoKBxWqMQDMAQACAAgKzhXwSgDpAQAMAAoKDQ+qMQDMAQALAAQKjw1abQCOAAAAAA==.',
Sc='Scfy:BAAANQAECgYIBgABNQAFFAUICAALADINAA==.Scorch:BAABNQAECn8UAAIZAAcKuRXZ0QDjAQAZAAcKuRXZ0QDjAQAAAA==.',
Se='Sedrayn:BAAANQAECgYIBwAAAA==.Selatha:BAAANQABCgIIAgABNQAFFAYIEAAZAAEaAA==.Selystine:BAAANQADCgUICAAAAA==.Semaj:BAAANQADCgcIBwAAAA==.Sergantis:BAAANQAECgEIAQAAAA==.',
Sh='Shagee:BAAANQAECgEIAQAAAA==.Shamwowolio:BAABNQAECn9GAAIGAAoKVxnhJABCAgAGAAoKVxnhJABCAgAAAA==.Shayd:BAABNQAECn8oAAQVAAoK3hgwVwBtAgAdAAgKGBccBQB6AgAVAAkKvhgwVwBtAgAPAAMKJRixUwDYAAAAAA==.Shigz:BAAANQADCggICQAAAA==.Shirokyu:BAAANQADCggICAAAAA==.Shirra:BAAANQADCggIDwAAAA==.Shirraz:BAABNQAECn8rAAIeAAgKrgk1KwAoAQAeAAgKrgk1KwAoAQAAAA==.Sho:BAABNQAECn8aAAIHAAgKvwz8tABQAQAHAAgKvwz8tABQAQAAAA==.Shroomicide:BAAANQAECggIBgAAAA==.Shylinn:BAAANQAECgEIAgAAAA==.',
Si='Sicaris:BAAANQADCgYICgABNQAECggIEwAEAAAAAA==.Sicksdeep:BAACNQAFFH8PAAMSAAUKrg86GgDOAAASAAQKrg86GgDOAAAOAAEKAABsBgBEAAA1AAQKfz8AAxIACgrrHwkiALACABIACgrrHwkiALACAA4AAQoZHg0pAFYAAAAA.Sigürd:BAAANQADCgEIAQAAAA==.Silverblade:BAAANQADCgMIBAAAAA==.Silverstorm:BAABNQAECn8iAAIVAAYKigik3ABHAQAVAAYKigik3ABHAQAAAA==.',
Sk='Skÿe:BAABNQAECn8/AAIPAAoKdRsvDgBMAgAPAAoKdRsvDgBMAgAAAA==.',
Sl='Slamma:BAACNQAFFH8nAAISAAcKNSTMBgBVAgASAAcKNSTMBgBVAgA1AAQKf1cAAhIACgqdJo0EANIDABIACgqdJo0EANIDAAAA.Slappin:BAAANQAECgcIDAAAAA==.Slappinbubs:BAAANQAECgQIBQABNQAECgcIDAAEAAAAAA==.Slicedbreád:BAACNQAFFH8rAAMaAAcKhhHKCwCQAQAaAAYKBg7KCwCQAQAGAAUKDRi8DAD8AAA1AAQKf0MAAwYACgopI2QLAA8DAAYACgopI2QLAA8DABoACgohGPFOACkCAAE1AAQKAQgBAAQAAAAA.',
Sm='Smokadaganga:BAABNQAECn8WAAMkAAkKqwmmBABXAQAkAAYK1gumBABXAQAZAAcKWwU/KgFFAQAAAA==.',
So='Sols:BAAANQAECgYIEQABNQAFFAUICQASADgZAA==.Sondirion:BAABNQAECn8pAAIPAAoKHBTaEwDyAQAPAAoKHBTaEwDyAQAAAA==.Soulancer:BAAANQAECggIDAABNQAECgoKFwAGAHANAA==.Sowet:BAAANQAECgIIAgAAAA==.',
Sp='Speoghii:BAABNQAECn8mAAIBAAoKnhrFRwB7AgABAAoKnhrFRwB7AgAAAA==.Spifftreebug:BAABNQAECn9BAAMNAAoKpBFKMABuAQANAAkKTg9KMABuAQAhAAkKOQlxLwBYAQAAAA==.Sprinklez:BAABNQAECn8cAAIUAAcK0hv6FwB4AQAUAAcK0hv6FwB4AQAAAA==.',
St='Steelerschic:BAABNQAECn8fAAIGAAYK7gOmsgCQAAAGAAYK7gOmsgCQAAAAAA==.Stormleader:BAACNQAFFH8IAAIhAAUKewbdCQALAQAhAAUKewbdCQALAQA1AAQKfz8AAyEACgpSGTsWAJICACEACgpSGTsWAJICACUAAQoAADN2ABMAAAAA.',
Su='Surge:BAAANQAECgUIDQAAAA==.',
Ta='Tai:BAABNQAECn8/AAIiAAoKUhqfCQAjAgAiAAoKUhqfCQAjAgAAAA==.Tainema:BAAANQAECgIIBAAAAA==.Tankguywowie:BAAANQAECgUIBQABNQAFFAcIEAANAMkNAA==.Taurriel:BAAANQAECgYIEwAAAA==.Tazzm:BAABNQAECn8kAAIPAAgK2gRGQABSAQAPAAgK2gRGQABSAQAAAA==.',
Te='Teranok:BAABNQAECn8ZAAQmAAkKGhezEQDLAQAmAAgKIRmzEQDLAQAIAAYKZBFZPAAzAQAJAAEK1gFHVQAfAAAAAA==.Terozon:BAAANQAECgEIAwAAAA==.Terzal:BAAANQADCgYIBgAAAA==.',
Th='Thalel:BAAANQAECgQIEAAAAA==.Theacused:BAABNQAECn8ZAAIZAAoK0xmUVgAAAgAZAAoK0xmUVgAAAgABNQAFFAUIEQACAOcaAA==.Them:BAAANQADCgIIAgABNQAECgMIBAAEAAAAAA==.Thoir:BAACNQAFFH8pAAIaAAcKSyT4AQC8AgAaAAcKSyT4AQC8AgA1AAQKf0cAAhoACgrmJfwGAIsDABoACgrmJfwGAIsDAAE1AAUUBwgpABsARQEA.Thorodinson:BAAANQAECggIDwAAAA==.',
Ti='Tipsylorcet:BAABNQAECn8oAAImAAkKwBujBgD7AQAmAAkKwBujBgD7AQAAAA==.',
Tk='Tkrain:BAAANQADCggIIAAAAA==.',
Tr='Traen:BAAANQAECgIIAgAAAA==.Trashbull:BAAANQAECggIAwAAAA==.Tricktickler:BAABNQAECn8WAAIWAAcKcxz1OAAjAgAWAAcKcxz1OAAjAgAAAA==.Troy:BAAANQADCgUIBQAAAA==.',
Tu='Tuskani:BAAANQABCggIGgAAAA==.',
Ty='Tybird:BAABNQAECn8/AAIMAAoKxR0vGQDBAgAMAAoKxR0vGQDBAgAAAA==.Tyranisv:BAAANQADCgMIAwAAAA==.',
Ul='Ulsull:BAAANQAECgEIAQABNQAECgEIAQAEAAAAAA==.Ulybonez:BAEBNQAECn8WAAMQAAkKchPxVQBjAQAQAAgKag/xVQBjAQARAAgKdQ00cQA1AQABNQAFFAcIKQAKAP8gAA==.Ulyssi:BAECNQAFFH8pAAIKAAcK/yDzAgDTAQAKAAcK/yDzAgDTAQA1AAQKf0MAAgoACgoGJiMDAKkDAAoACgoGJiMDAKkDAAAA.',
Um='Ummpatas:BAAANQAECgEIAQAAAA==.',
Us='Usseel:BAAANQAECgEIAQAAAA==.',
['Uñ']='Uñàble:BAAANQADCgIIAgAAAA==.',
Va='Valymus:BAAANQADCgIIAgABNQAECgoKKAAVAN4YAA==.Vandagylon:BAAANQADCgYIDAAAAA==.Vandals:BAAANQAECgcIEgAAAA==.',
Ve='Ven:BAABNQAECn8qAAIKAAkKVwcqJgA8AQAKAAkKVwcqJgA8AQAAAA==.Ver:BAAANQADCgMIAQAAAA==.',
Vo='Voltaire:BAAANQADCgIIAgAAAA==.',
Wa='Walle:BAAANQADCgEIAQAAAA==.Wankstar:BAAANQAECgQIBAABNQAECgcIDAAEAAAAAA==.Wargas:BAAANQABCgIIAgAAAA==.Warvein:BAABNQAECn8gAAMSAAkK/A8CjwD2AQASAAkK/A8CjwD2AQAiAAQKMAdwNACTAAAAAA==.',
We='Weehunt:BAABNQAECn8rAAIVAAoKcg7jZADiAQAVAAoKcg7jZADiAQAAAA==.Weeshami:BAAANQADCgMIAwAAAA==.',
Wh='Whackem:BAAANQAECgEIAQAAAA==.Whillia:BAAANQAECgEIAQAAAA==.',
Wi='Wicah:BAABNQAECn8gAAIbAAcKJxu0RAAQAgAbAAcKJxu0RAAQAgAAAA==.Wicka:BAABNQAECn9EAAIaAAoKlCKrDABPAwAaAAoKlCKrDABPAwAAAA==.Widowblade:BAAANQAECgYIDgAAAA==.Wildriver:BAABNQAECn8fAAIhAAkKtxjrGAAwAgAhAAkKtxjrGAAwAgAAAA==.Willferàl:BAAANQADCgMIAwAAAA==.',
Xa='Xaehyun:BAACNQAFFH81AAIIAAoKvCQiAABlAwAIAAoKvCQiAABlAwA1AAQKfyoAAggACgoJJw8AAKQDAAgACgoJJw8AAKQDAAAA.Xandrelar:BAAANQAECgQIBAABNQAECgoKKAAVAN4YAA==.',
Xm='Xmrpdk:BAACNQAFFH8pAAILAAcKKiTrAgBtAgALAAcKKiTrAgBtAgA1AAQKf0cAAgsACgp0Jv8BANQDAAsACgp0Jv8BANQDAAAA.Xmrppally:BAAANQAECgcICAABNQAFFAcIKQALACokAA==.',
Xy='Xy:BAAANQADCggICAAAAA==.',
Ya='Yarina:BAAANQADCgUIBQAAAA==.',
Yo='Yoyiek:BAACNQAFFH8QAAINAAcKyQ20FAAhAQANAAcKyQ20FAAhAQA1AAQKfzUAAw0ACgrrHs0NAL4CAA0ACgrrHs0NAL4CACUAAwq6AjBSAFoAAAAA.',
Za='Zalynn:BAAANQAECgEIAgAAAA==.Zanne:BAACNQAFFH8IAAIPAAQKVRSxEQCyAAAPAAQKVRSxEQCyAAA1AAQKfy0AAg8ACgo1H98XAJkCAA8ACgo1H98XAJkCAAAA.Zaraele:BAAANQAECgQIBQAAAA==.Zarthul:BAAANQAECgQIDAAAAA==.',
Ze='Zehara:BAAANQADCgMIBAAAAA==.Zenori:BAAANQADCggIDgAAAA==.',
Zh='Zhenyu:BAAANQADCgQIBAABNQAECgoKFwAGAHANAA==.',
Zi='Ziely:BAAANQAECgUIBQAAAA==.',
Zl='Zlot:BAECNQAFFH8pAAMVAAcKah7EDACGAQAVAAUKBB7EDACGAQAPAAQKFCDYDwA/AQA1AAQKf0cAAxUACgrpJW8iAA0DABUACAoTJm8iAA0DAA8ACQroIDQZAI0CAAAA.',
Zu='Zulani:BAAANQAECgcIBQAAAA==.',
Zy='Zyphara:BAAANQAECgEIAwAAAA==.',
['Õn']='Õneshot:BAABNQAECn8VAAIbAAcKGRVJbwDQAQAbAAcKGRVJbwDQAQAAAA==.',
['Ör']='Öriana:BAAANQAECgYIBgAAAA==.',
['Øñ']='Øñêshot:BAAANQADCggIEwABNQAECgcIFQAbABkVAA==.',
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
