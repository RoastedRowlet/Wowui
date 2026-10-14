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

local lookup = {'Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Monk-Windwalker','Shaman-Elemental','Druid-Balance','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Frost','Warrior-Arms','Shaman-Enhancement','Hunter-BeastMastery','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Shaman-Restoration','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Paladin-Holy','Hunter-Survival','DemonHunter-Devourer','Paladin-Protection','Priest-Discipline','Druid-Restoration','Warlock-Affliction','Warlock-Destruction','Evoker-Augmentation','Paladin-Retribution','DeathKnight-Blood','Warrior-Fury','Mage-Fire','Druid-Guardian','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaralia:BAAANQAECgUIDAAAAA==.',
Ab='Abyssdark:BAABNQAECn8vAAIBAAkKxRqQJwDjAgABAAkKxRqQJwDjAgAAAA==.',
Ac='Accusation:BAABNQAFFH8GAAICAAMKcBRiEgDiAAACAAMKcBRiEgDiAAAAAA==.',
Ak='Akadeus:BAAANQAECgIIAgAAAA==.',
Al='Alarielle:BAAANQAECgMIBQABNQAECgcIJgADAOUbAA==.Altx:BAAANQABCgUIAwAAAA==.',
Am='Amirah:BAAANQADCgEIAgAAAA==.Ammathael:BAAANQAECgEJAQAAAA==.',
An='Anamarie:BAAANQAECgQIBQABNQAECgYIDgAEAAAAAA==.Antipasta:BAAANQAECggICAAAAA==.',
Ar='Aramist:BAAANQADCgYIGAAAAA==.Arroy:BAAANQADCgcIDwAAAA==.',
As='Ashikahammer:BAAANQAECgYIDQABNQAECgkJIgADAJQgAA==.Ashtaroth:BAAANQAECgYICwABNQAECgcIJgADAOUbAA==.',
Az='Azraeth:BAAANQAECgYIDgAAAA==.',
Ba='Baehyun:BAAANQAECggIDQABNQAFFAgIHQAFAAIlAA==.Basou:BAAANQADCggICAAAAA==.',
Be='Belanova:BAAANQADCgQIBAAAAA==.Belnathas:BAAANQADCggIHAAAAA==.',
Bl='Blamethemage:BAAANQADCgMIAwABNQAECgkJKQAGAJsXAA==.Bloodbeard:BAAANQAECgYICAAAAA==.Bloodedge:BAAANQADCgIIBAAAAA==.',
Bo='Bohmbear:BAAANQADCgYIBgAAAA==.Bomboy:BAAANQAECgEIAQAAAA==.',
Br='Brentobox:BAAANQAECgUIDwAAAA==.Brugara:BAAANQADCggIFwAAAA==.',
Bu='Bungeholio:BAAANQAECgQIBwABNQAECgkJKQAGAJsXAA==.',
Ca='Camael:BAAANQAECgYIDwAAAA==.Cannelle:BAAANQAECgQIBQAAAA==.Carden:BAAANQAECgYIDwAAAA==.',
Ce='Cervantes:BAAANQAECgIIBAAAAA==.',
Ch='Charcyna:BAAANQAECgMIBQABNQAFFAcIEwAHAC0aAA==.Chardr:BAACNQAFFH8TAAIHAAcKLRoEBQBSAgAHAAcKLRoEBQBSAgA1AAQKfyEAAgcACAqdJasZAPkCAAcACAqdJasZAPkCAAAA.Chillywillie:BAAANQAECgQICQAAAA==.Chrodne:BAAANQADCgcIFQAAAA==.Chucknorrîs:BAAANQAECgIIAwAAAA==.',
Ci='Cigam:BAAANQAECgQICAAAAA==.',
Cl='Clintbarton:BAABNQAECn85AAIIAAkKCA7QKgDyAQAIAAkKCA7QKgDyAQAAAA==.',
Cr='Crûtch:BAAANQADCggJDgAAAA==.',
Ct='Cthullu:BAAANQADCggICAAAAA==.',
Cu='Culebra:BAABNQAECn8nAAMJAAkKYRaRJABgAgAJAAkKYRaRJABgAgAKAAEKgBOdTQBFAAAAAA==.',
['Cø']='Cøldshoulder:BAABNQAECn8fAAILAAcKABr4MQAUAgALAAcKABr4MQAUAgAAAA==.',
Da='Dabi:BAAANQADCgQIBAAAAA==.Daehyun:BAAANQAECggIDQABNQAFFAgIHQAFAAIlAA==.Danceofdeath:BAAANQAECgYIBwABNQAECgkJKAAMAAMfAA==.Dane:BAABNQAECn8XAAIMAAkK2QlGogDCAQAMAAkK2QlGogDCAQAAAA==.Darcmatter:BAAANQAECggIEwAAAA==.Darthmo:BAAANQADCgMIAwAAAA==.',
De='Deadtrap:BAAANQABCggIDwAAAA==.Deathsend:BAAANQADCgYICAAAAA==.Deepsicks:BAABNQAECn8fAAINAAkKXxkaDgCJAgANAAkKXxkaDgCJAgAAAA==.Deepstate:BAAANQAECgEIAgAAAA==.Demonäde:BAAANQADCgUIAgAAAA==.',
Di='Dima:BAABNQAECn8lAAIOAAgKsxchVwBrAgAOAAgKsxchVwBrAgAAAA==.Dithy:BAAANQAECgMIBQAAAA==.',
Dk='Dkrmk:BAAANQADCgMIAgAAAA==.Dktelli:BAAANQAECgYIEAABNQAECgkJNQANAJAhAA==.',
Dn='Dne:BAAANQADCggIDgABNQAECgkJFwAMANkJAA==.',
Do='Donavon:BAAANQAECgYICwAAAA==.Donutjelly:BAAANQAECgUIEQAAAA==.Dorivandor:BAAANQAECgQIBQAAAA==.Dornnbryda:BAAANQADCggIDgABNQAECgYIEwAEAAAAAA==.',
Dr='Drackothyr:BAABNQAECn8bAAMPAAcKDx0UEABUAgAPAAcKDx0UEABUAgAQAAMKKwUvRAB7AAAAAA==.Dreamweavver:BAAANQADCgQIBAAAAA==.Drumark:BAAANQADCgMIAwAAAA==.',
Dw='Dwastring:BAAANQAECgcIEwAAAA==.',
Dy='Dyrale:BAAANQADCgYIGwAAAA==.',
Ek='Eknivar:BAAANQADCgQIBAABNQAECggIKQARADAeAA==.',
Er='Erebus:BAAANQAECgQIBAAAAA==.Erragorn:BAAANQAECgQIEgAAAA==.',
Ev='Evisa:BAAANQAECgQICQAAAA==.Evokholio:BAAANQAECgIIAwAAAA==.',
['Eö']='Eöath:BAAANQAECgEIAQAAAA==.',
Fa='Falaurenta:BAAANQADCgMIBgAAAA==.',
Fe='Feidao:BAAANQAECgQICAAAAA==.Feralith:BAAANQADCgMIAQAAAA==.',
Fo='Foshizzle:BAAANQABCgIIAgAAAA==.',
Fu='Funkenfox:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëânòr:BAAANQADCgUIBQAAAA==.',
Ga='Gailinn:BAAANQAECgUIEwAAAA==.',
Go='Gooraah:BAAANQADCgUIBQAAAA==.Gorash:BAAANQAECgQIBQABNQAECgYIDgAEAAAAAA==.',
Gr='Greggdshami:BAABNQAECn8eAAISAAgKJRyRPwBfAgASAAgKJRyRPwBfAgAAAA==.Gretagobbo:BAAANQADCgUIBQABNQAECgYICAAEAAAAAA==.',
Gu='Gundamus:BAAANQADCgYIBgAAAA==.Guthrum:BAAANQADCgQIBAAAAA==.',
He='Healmonger:BAABNQAECn8xAAMTAAkKTiF5EABBAwATAAkKTiF5EABBAwAUAAEKAABWlAAMAAAAAA==.Hekili:BAAANQAECgQIBwAAAA==.Heruin:BAAANQAECgcIEgAAAA==.',
Hi='Hictor:BAAANQADCgMIAwAAAA==.',
Ho='Holly:BAAANQADCgEIAQAAAA==.Hongdou:BAAANQAECgIIAgAAAA==.Horse:BAACNQAFFH8bAAITAAYKXQHtEwBjAQATAAYKXQHtEwBjAQA1AAQKfzgAAhMACQpwDPRoAN8BABMACQpwDPRoAN8BAAAA.Hourzero:BAAANQAECgEIAQAAAA==.',
Ia='Iammyscars:BAACNQAFFH8HAAIVAAIK8g/wFgCBAAAVAAIK8g/wFgCBAAA1AAQKfyMAAhUACQo5IGcSAAgDABUACQo5IGcSAAgDAAAA.',
Ic='Icu:BAAANQAECgcIDgAAAA==.',
Ik='Ikillu:BAAANQAECgYIEAAAAA==.',
Il='Ilis:BAAANQAECgQIBQAAAA==.Ilovecheetos:BAAANQADCggJDgAAAA==.',
Ja='Jaiminvi:BAAANQADCgEIAQAAAA==.Jasnahh:BAAANQAECgQICQABNQAECgYICgAEAAAAAA==.Jaylas:BAAANQADCgEIAQABNQAECgcILAAWAA4hAA==.',
Jo='Joeexotíc:BAABNQAFFH8FAAMXAAMK8iL+AAA+AQAXAAMK8iL+AAA+AQAIAAEKixC/IgBHAAAAAA==.',
Ju='Jun:BAACNQAFFH8UAAIVAAYKZiJKAwBQAgAVAAYKZiJKAwBQAgA1AAQKfzYAAxUACQrHJqUAAPwDABUACQrHJqUAAPwDABgACAqAIpwcAG0CAAAA.Junfan:BAAANQAECggIDwAAAA==.',
Ka='Kasumaus:BAAANQAECgYIEAAAAA==.',
Ke='Kelly:BAAANQADCggICAAAAA==.Kennifer:BAAANQADCggICQAAAA==.Kenshindune:BAAANQADCgQIBAAAAA==.Keragan:BAAANQADCgEJAQAAAA==.',
Kh='Khalyeesi:BAAANQADCgIIAwAAAA==.Khandris:BAAANQABCggIEwAAAA==.Khazjek:BAAANQADCgYICAAAAA==.Khephris:BAABNQAECn8mAAIDAAcK5RttCwAGAgADAAcK5RttCwAGAgAAAA==.',
Ki='Kiralni:BAAANQAECgMIAwAAAA==.',
Kn='Knivex:BAABNQAECn8pAAMRAAgKMB7/mwBIAgARAAcKex3/mwBIAgADAAMK4h3wHAAEAQAAAA==.',
Ko='Koryann:BAABNQAECn8eAAIZAAYKmxSLKgCFAQAZAAYKmxSLKgCFAQAAAA==.Kosel:BAAANQAECgUIBwAAAA==.Kova:BAAANQAECgYIEQAAAA==.',
Kr='Kramm:BAAANQAECgEIAQAAAA==.Krazyplaya:BAAANQAECgEIAQAAAA==.',
Kw='Kwarthil:BAAANQABCgEIAQAAAA==.',
Ky='Kyrise:BAABNQAECn8VAAISAAkKCxFYUQAdAgASAAkKCxFYUQAdAgAAAA==.',
La='Lambo:BAAANQAECgQJBAAAAA==.Landam:BAAANQAECgUIDAAAAA==.',
Le='Leap:BAAANQADCgMIAwABNQAECgkJKQAYACwXAA==.',
Li='Lifeaura:BAACNQAFFH8VAAIaAAYKsBC0AADiAQAaAAYKsBC0AADiAQA1AAQKfzUAAhoACQr3IB4BAFYDABoACQr3IB4BAFYDAAAA.Lifesshaman:BAAANQAECggICAAAAA==.Lightbläster:BAAANQAECgIIBAAAAA==.Lightrider:BAAANQADCgYICwAAAA==.Linesta:BAAANQADCgEIAQAAAA==.Lionroar:BAACNQAFFH8RAAIbAAYKaB1BAwASAgAbAAYKaB1BAwASAgA1AAQKfyoAAhsACQp3I74HAEYDABsACQp3I74HAEYDAAAA.Littleguy:BAABNQAECn8WAAIGAAYKvgLq1wDgAAAGAAYKvgLq1wDgAAAAAA==.',
Ll='Llaothtaed:BAAANQAECggIBgAAAA==.',
Lo='Lochannis:BAAANQAECgUICQAAAA==.Logi:BAAANQAECgcIBwAAAA==.Lokalock:BAAANQAECgQICQABNQAECgkJNQANAJAhAA==.Lonee:BAAANQADCgIIAgAAAA==.Lorellei:BAAANQAECgUIDwAAAA==.Lothgow:BAAANQAECgEIAgAAAA==.',
Lu='Luxus:BAAANQAECgEIAQAAAA==.',
['Lâ']='Lân:BAAANQAFFAIIAgAAAA==.',
Ma='Maelynn:BAAANQADCgUIBQAAAA==.Manticor:BAAANQADCgcIBgAAAA==.Martyglaive:BAABNQAECn8YAAIVAAYKHRSoQgCnAQAVAAYKHRSoQgCnAQAAAA==.Matteas:BAAANQAECgYIEAAAAA==.',
Me='Menionblue:BAAANQADCgUIBQAAAA==.Mew:BAAANQAECgUIDwAAAA==.',
Mf='Mfdoom:BAABNQAECn80AAQBAAkKXB0lQACOAgABAAgK2RwlQACOAgAcAAMK/x17FwDQAAAdAAMKfBUrPgDIAAABNQADCgIIBAAEAAAAAA==.',
Mi='Mizrey:BAABNQAECn8ZAAILAAkKjx5hEgD4AgALAAkKjx5hEgD4AgAAAA==.Mizukisakura:BAAANQAECgMIAwAAAA==.',
Mo='Mograins:BAABNQAECn8xAAMdAAkKoh4uDQAkAgABAAcKWh0hUgBcAgAdAAYKXSEuDQAkAgAAAA==.Monzcarro:BAAANQADCggICwAAAA==.Mordar:BAAANQADCgUIBwAAAA==.Morgainne:BAAANQAECgMIBQAAAA==.Mortmor:BAAANQAECgYICwAAAA==.',
Mu='Muffinn:BAABNQAECn8fAAIOAAgKNgpOlwDVAQAOAAgKNgpOlwDVAQAAAA==.Mursê:BAAANQAECgUIBwAAAA==.',
My='Mymdos:BAABNQAECn84AAIMAAkKniDYHwA3AwAMAAkKniDYHwA3AwABNQABCgIIAgAEAAAAAA==.Myrmidonn:BAAANQADCgYICgAAAA==.',
['Mä']='Mästérdòn:BAAANQAECgcIDAAAAA==.',
['Må']='Måsterdon:BAAANQAECgQIEQAAAA==.',
['Mô']='Môiraine:BAAANQAFFAIIAgAAAA==.',
Ne='Nercos:BAAANQAECgEIAQABNQAFFAIIAgAEAAAAAA==.Nercqt:BAAANQAFFAIIAgAAAA==.Neverborn:BAAANQAECgcIEgAAAA==.',
Ni='Niame:BAAANQAECgQICQAAAA==.Nitraina:BAAANQAECgYIEgAAAA==.Niyabelle:BAABNQAECn8iAAMKAAgK1xlIEgBdAgAKAAcK4htIEgBdAgAJAAcKNhDrQgC4AQAAAA==.',
No='Noggenfloggr:BAAANQAECgUICAAAAA==.Nomesis:BAAANQAECgEIAQAAAA==.',
Ny='Nyxth:BAAANQABCggIDQAAAA==.',
Oa='Oakmane:BAAANQABCgEIAQABNQAECgYIDgAEAAAAAA==.',
Od='Odïn:BAAANQADCgYIDAAAAA==.',
Ol='Oleevia:BAABNQAECn8pAAIUAAkKqBVIFQC0AgAUAAkKqBVIFQC0AgAAAA==.',
Om='Omgdingers:BAAANQAECgYICAABNQAECggIEgAEAAAAAA==.',
On='Oneshót:BAAANQADCgYICAABNQAECgcIFQATABkVAA==.Oneth:BAAANQAECgIIAgABNQAECgMIAwAEAAAAAA==.',
Or='Oraxia:BAAANQAECgEIAQABNQAECgYICAAEAAAAAA==.Ords:BAAANQABCgYICAAAAA==.Orgdynamite:BAAANQAECgYIBwABNQAFFAYIGwAGAK0ZAA==.Orgsham:BAACNQAFFH8bAAMGAAYKrRnKBgAIAgAGAAYKmRnKBgAIAgANAAEKSBfHBwBTAAA1AAQKfzQAAwYACQp5JJINAHoDAAYACQp5JJINAHoDAA0ABAozF5oiACsBAAAA.',
Pa='Paedragon:BAAANQAECgMIAwAAAA==.Paimon:BAAANQADCgYIBgAAAA==.Paladareian:BAABNQAECn8sAAIWAAcKDiEnMgCaAgAWAAcKDiEnMgCaAgAAAA==.',
Pe='Pej:BAACNQAFFH8bAAQPAAYKNhWqBwAOAQAeAAQKNxA2BgAhAQAPAAQKXxCqBwAOAQAQAAMKLgiEEQDHAAA1AAQKfzsABA8ACQpZHw0PAGkCAA8ACApiIA0PAGkCABAABwpPF+McAPsBAB4ABQp5G2QLAKYBAAAA.Pejbolt:BAAANQADCgcICgABNQAFFAYIFAAVAGYiAA==.',
Ph='Phenomenon:BAAANQADCggICAABNQAECgYIDgAEAAAAAA==.Phoenixa:BAAANQAECgEIAQAAAA==.',
Pl='Plus:BAAANQAECgcICwAAAA==.',
Po='Powerslavé:BAABNQAECn8oAAIMAAkKAx9/NADtAgAMAAkKAx9/NADtAgAAAA==.',
Pr='Priestitoot:BAAANQAECgMIAwAAAA==.Proust:BAAANQADCgYIBgAAAA==.',
Pu='Pumkinhead:BAABNQAECn8gAAIGAAkKPw5XYgD2AQAGAAkKPw5XYgD2AQAAAA==.',
Py='Pyromania:BAAANQAECgYIDgAAAA==.',
['Pä']='Pä:BAAANQADCgMIAQAAAA==.',
Ra='Raiden:BAABNQAECn8bAAIfAAgKZQ1srgC9AQAfAAgKZQ1srgC9AQAAAA==.Rat:BAAANQABCgIIAgAAAA==.Rauck:BAAANQADCgUIBQABNQAECgYICAAEAAAAAA==.',
Re='Rentacat:BAAANQADCggIEQAAAA==.Retropâlly:BAAANQADCgMIAwAAAA==.Revoker:BAAANQADCgUICAABNQAECgkJJgAOAAUbAA==.',
Ro='Rogi:BAAANQAECgQIBgABNQABCgIIAgAEAAAAAA==.',
['Rö']='Römana:BAABNQAECn8bAAIOAAcKmw/tmQDPAQAOAAcKmw/tmQDPAQAAAA==.',
Sa='Saliva:BAAANQADCggICAAAAA==.Sanguinaris:BAAANQAECgEIAQABNQAECgYIDgAEAAAAAA==.Sareya:BAAANQABCggIDwAAAA==.Sataanic:BAAANQAECgQIBwAAAA==.Satyrical:BAABNQAECn8aAAMCAAgKzhUYSgDqAQACAAgKzhUYSgDqAQAgAAIKbAs/tgBYAAAAAA==.',
Sc='Scorch:BAAANQAECgYIEAAAAA==.',
Se='Sedrayn:BAAANQAECgYIBwAAAA==.Selatha:BAAANQABCgIIAgABNQAFFAQIDgARAFEgAA==.Selystine:BAAANQADCgUICAAAAA==.Semaj:BAAANQADCgcIBwAAAA==.Sergantis:BAAANQADCgcIBwABNQADCgcIEAAEAAAAAA==.',
Sh='Shagee:BAAANQAECgEIAQAAAA==.Shamwowolio:BAABNQAECn8pAAIGAAkKmxfZOACQAgAGAAkKmxfZOACQAgAAAA==.Shayd:BAABNQAECn8mAAQOAAkKBRuDVQBvAgAXAAgKGBcSBQB6AgAOAAgKGhuDVQBvAgAIAAMKJRjGUgDYAAAAAA==.Shirokyu:BAAANQADCggICAAAAA==.Shirra:BAAANQADCggIDwAAAA==.Shirraz:BAAANQAECgYIEQAAAA==.Sho:BAAANQABCgcICQAAAA==.Shroomicide:BAAANQAECggIBgAAAA==.',
Si='Sicaris:BAAANQADCgYICgABNQAECggIEQAEAAAAAA==.Sicksdeep:BAACNQAFFH8HAAMMAAMKHQ5eLwCKAAAMAAIKHQ5eLwCKAAAhAAEKAABRBgBEAAA1AAQKfyYAAgwACQqvFyZeAG8CAAwACQqvFyZeAG8CAAAA.Sigürd:BAAANQADCgEIAQAAAA==.Silverstorm:BAAANQAECgUIDAAAAA==.',
Sk='Skÿe:BAABNQAECn8eAAIIAAgKpRcIHwBVAgAIAAgKpRcIHwBVAgAAAA==.',
Sl='Slamma:BAACNQAFFH8aAAIMAAYKmCF9BgBVAgAMAAYKmCF9BgBVAgA1AAQKfzoAAgwACQqQJlsEANMDAAwACQqQJlsEANMDAAAA.Slappinbubs:BAAANQAECgEJAQAAAA==.Slicedbreád:BAACNQAFFH8YAAMSAAYKSgh/CwCQAQASAAYKSgh/CwCQAQAGAAQK8BtuDwByAQA1AAQKfzAAAxIACQp1GfxNACkCABIACQp1GfxNACkCAAYAAwpYJBiwAC4BAAE1AAQKAQgBAAQAAAAA.',
Sm='Smokadaganga:BAABNQAECn8WAAMiAAkKqwmeBABXAQAiAAYK1gueBABXAQARAAcKWwUnJgFIAQAAAA==.',
So='Sols:BAAANQAECgYIDQABNQAECgkJKAAMAAMfAA==.Sondirion:BAAANQAECgYIEwAAAA==.Sowet:BAAANQAECgIIAgAAAA==.',
Sp='Speoghii:BAABNQAECn8fAAIBAAgK+hhXRgB8AgABAAgK+xhXRgB8AgAAAA==.Spifftreebug:BAABNQAECn8kAAMHAAgKwQuISwCyAQAHAAgKwQuISwCyAQAbAAEKlhDbcwA1AAAAAA==.Sprinklez:BAAANQAECgUIDgAAAA==.',
St='Steelerschic:BAAANQAECgMIBwAAAA==.Stormleader:BAABNQAECn8xAAMbAAkKiBfrFQCSAgAbAAkKiBfrFQCSAgAjAAEKAAAacwATAAAAAA==.',
Su='Surge:BAAANQAECgMIBgAAAA==.',
Ta='Tai:BAABNQAECn8eAAIkAAgKFxq2DgA+AgAkAAgKFxq2DgA+AgAAAA==.Tainema:BAAANQAECgIIBAAAAA==.Tankguywowie:BAAANQAECgUIBQABNQAFFAUICwAHAEgJAA==.Taurriel:BAAANQAECgYIEAAAAA==.Tazzm:BAABNQAECn8kAAIIAAgK2gSJPwBSAQAIAAgK2gSJPwBSAQAAAA==.',
Te='Teranok:BAAANQAECgcIEAAAAA==.Terzal:BAAANQADCgYIBgAAAA==.',
Th='Thalel:BAAANQAECgQIDgAAAA==.Theacused:BAAANQAECgcICgABNQAFFAMIBgACAHAUAA==.Thoir:BAACNQAFFH8bAAISAAYKnyOyAgByAgASAAYKnyOyAgByAgA1AAQKfzgAAhIACQrSJc0GAIsDABIACQrSJc0GAIsDAAE1AAUUBggbABMAXQEA.Thorodinson:BAAANQAECgQIAwAAAA==.',
Ti='Tipsylorcet:BAABNQAECn8ZAAIlAAcKeBttDQAhAgAlAAcKeBttDQAhAgAAAA==.',
Tk='Tkrain:BAAANQADCgYIEwAAAA==.',
Tr='Traen:BAAANQADCggICAAAAA==.Trashbull:BAAANQAECggIAgAAAA==.Tricktickler:BAAANQAECgMIBQAAAA==.Troy:BAAANQADCgUIBQAAAA==.',
Tu='Tuskani:BAAANQABCggIFgAAAA==.',
Ty='Tybird:BAABNQAECn8lAAILAAgK8h2NGADDAgALAAgK8h2NGADDAgAAAA==.Tyranisv:BAAANQADCgMIAwAAAA==.',
Ul='Ulsull:BAAANQADCgcIEAAAAA==.Ulybonez:BAAANQAECggICAABNQAFFAYIGwAUAIAcAA==.Ulyssi:BAACNQAFFH8bAAIUAAYKgBx1AwArAgAUAAYKgBx1AwArAgA1AAQKfzgAAhQACQpzJQcDAKkDABQACQpzJQcDAKkDAAAA.',
Um='Ummpatas:BAAANQAECgEIAQAAAA==.',
Us='Usseel:BAAANQADCgMIAwAAAA==.',
['Uñ']='Uñàble:BAAANQADCgIIAgAAAA==.',
Va='Valymus:BAAANQADCgIIAgABNQAECgkJJgAOAAUbAA==.Vandagylon:BAAANQADCgYIDAAAAA==.Vandals:BAAANQAECgYIDwAAAA==.',
Ve='Ven:BAABNQAECn8bAAIUAAcKzQb/PQA4AQAUAAcKzQb/PQA4AQAAAA==.Ver:BAAANQADCgMIAQAAAA==.',
Vo='Voltaire:BAAANQADCgIIAgAAAA==.',
Wa='Walle:BAAANQADCgEIAQAAAA==.Wankstar:BAAANQAECgEIAQAAAA==.Warvein:BAABNQAECn8aAAMMAAgKxBE/jQD3AQAMAAgKxBE/jQD3AQAkAAMKMAm3MwCTAAAAAA==.',
We='Weehunt:BAABNQAECn8aAAIOAAcK1xHmjgDoAQAOAAcK1xHmjgDoAQAAAA==.Weeshami:BAAANQADCgMIAwAAAA==.',
Wh='Whillia:BAAANQADCgMIAwAAAA==.',
Wi='Wicah:BAAANQAECgQICQAAAA==.Wicka:BAABNQAECn8lAAISAAgKZSD2IQDeAgASAAgKZSD2IQDeAgAAAA==.Widowblade:BAAANQAECgQIBAAAAA==.Wildriver:BAABNQAECn8VAAIbAAYKLxszKQDRAQAbAAYKLxszKQDRAQAAAA==.Willferàl:BAAANQADCgMIAwAAAA==.',
Xa='Xaehyun:BAACNQAFFH8dAAIFAAgKAiVbAABeAwAFAAgKAiVbAABeAwA1AAQKfx4AAgUACQr7Ju8VAJ4CAAUACQr7Ju8VAJ4CAAAA.Xandrelar:BAAANQADCggIDQABNQAECgkJJgAOAAUbAA==.',
Xm='Xmrpdk:BAACNQAFFH8bAAIgAAYKiSTAAgBtAgAgAAYKiSTAAgBtAgA1AAQKfzgAAiAACQrXJfgBANQDACAACQrXJfgBANQDAAAA.Xmrppally:BAAANQAECgcICAABNQAFFAYIGwAgAIkkAA==.',
Xy='Xy:BAAANQADCggICAAAAA==.',
Ya='Yarina:BAAANQADCgUIBQAAAA==.',
Yo='Yoyiek:BAACNQAFFH8LAAIHAAUKSAlMFAAhAQAHAAUKSAlMFAAhAQA1AAQKfx8AAwcACQp4FP8tAGsCAAcACQp4FP8tAGsCACMAAwq6AlBQAFoAAAAA.',
Za='Zalynn:BAAANQAECgEIAQAAAA==.Zanne:BAABNQAECn8jAAIIAAkK3x2GFwCaAgAIAAkK3x2GFwCaAgAAAA==.Zarthul:BAAANQAECgIIBwAAAA==.',
Ze='Zehara:BAAANQADCgMJAwAAAA==.Zenori:BAAANQADCggIDgAAAA==.',
Zh='Zhenyu:BAAANQADCgQIBAABNQAECgYIDgAEAAAAAA==.',
Zl='Zlot:BAECNQAFFH8bAAMOAAYK3R5UDACGAQAOAAQKwiFUDACGAQAIAAQKCReFDwBAAQA1AAQKfzgAAw4ACQoaJuIhAA4DAA4ABwqsJuIhAA4DAAgACApBIeMYAI4CAAAA.',
Zu='Zulani:BAAANQADCgIIAgAAAA==.',
['Õn']='Õneshot:BAABNQAECn8VAAITAAcKGRXZbQDQAQATAAcKGRXZbQDQAQAAAA==.',
['Øñ']='Øñêshot:BAAANQADCggIEwABNQAECgcIFQATABkVAA==.',
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
