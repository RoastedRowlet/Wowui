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

local lookup = {'Warlock-Demonology','Mage-Frost','Unknown-Unknown','Monk-Windwalker','Shaman-Elemental','Druid-Balance','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Frost','Warrior-Arms','Shaman-Enhancement','Hunter-BeastMastery','Mage-Arcane','Shaman-Restoration','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Paladin-Holy','DemonHunter-Devourer','Paladin-Protection','Priest-Discipline','Druid-Restoration','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Fury','Mage-Fire','Druid-Guardian','Warrior-Protection',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaralia:BAAANQAECgUIDAAAAA==.',
Ab='Abyssdark:BAABNQAECoEnAAIBAAkKvBpWIgDjAgABAAkKvBpWIgDjAgAAAA==.',
Ac='Accusation:BAAANQAFFAIIAwAAAA==.',
Ak='Akadeus:BAAANQAECgIIAgAAAA==.',
Al='Alarielle:BAAANQAECgMIAwABNQAECgcIIAACAPgcAA==.Altx:BAAANQABCgUIAwAAAA==.',
Am='Amirah:BAAANQADCgEIAgAAAA==.Ammathael:BAAANQAECgEJAQAAAA==.',
An='Anamarie:BAAANQAECgQIBQABNQAECgYIDgADAAAAAA==.',
Ar='Aramist:BAAANQADCgUIEgAAAA==.Arroy:BAAANQADCgcIDwAAAA==.',
As='Ashikahammer:BAAANQAECgYIDQABNQAECgkJIgACAHkhAA==.Ashtaroth:BAAANQAECgYIBgABNQAECgcIIAACAPgcAA==.',
Az='Azraeth:BAAANQAECgUICgAAAA==.',
Ba='Baehyun:BAAANQAECggIDQABNQAFFAYIEAAEAIYjAA==.Basou:BAAANQADCggICAAAAA==.',
Be='Belanova:BAAANQADCgQIBAAAAA==.Belnathas:BAAANQADCggIHAAAAA==.',
Bl='Bloodbeard:BAAANQAECgYICAAAAA==.Bloodedge:BAAANQADCgIIBAAAAA==.',
Bo='Bohmbear:BAAANQADCgYIBgAAAA==.',
Br='Brentobox:BAAANQAECgQICgAAAA==.Brugara:BAAANQADCggIFwAAAA==.',
Bu='Bungeholio:BAAANQAECgMIAwABNQAECggIHwAFAMkRAA==.',
Ca='Camael:BAAANQAECgUIDgAAAA==.Cannelle:BAAANQADCggIGwAAAA==.Carden:BAAANQAECgQICgAAAA==.',
Ce='Cervantes:BAAANQAECgIIAgAAAA==.',
Ch='Charcyna:BAAANQAECgEIAQABNQAFFAYIEgAGADAVAA==.Chardr:BAACNQAFFIESAAIGAAYKMBUzBgAAAgAGAAYKMBUzBgAAAgA1AAQKgR4AAgYACAoQJf4VAAADAAYACAoQJf4VAAADAAAA.Chillywillie:BAAANQAECgMIBQAAAA==.Chrodne:BAAANQADCgcIEwAAAA==.Chucknorrîs:BAAANQAECgEIAQAAAA==.',
Ci='Cigam:BAAANQAECgQIBQAAAA==.',
Cl='Clintbarton:BAABNQAECoExAAIHAAcKURGHLgCwAQAHAAcKURGHLgCwAQAAAA==.',
Cr='Crûtch:BAAANQADCggJDgAAAA==.',
Ct='Cthullu:BAAANQADCggICAAAAA==.',
Cu='Culebra:BAABNQAECoElAAMIAAkKdhMBHAB1AgAIAAkKdhMBHAB1AgAJAAEKgBOZRwBFAAAAAA==.',
['Cø']='Cøldshoulder:BAABNQAECoEZAAIKAAcK7xTgMgDXAQAKAAcK7xTgMgDXAQAAAA==.',
Da='Daehyun:BAAANQAECggIDQABNQAFFAYIEAAEAIYjAA==.Danceofdeath:BAAANQAECgYIBwABNQAECgkJIwALANIeAA==.Dane:BAAANQAECgcIEwAAAA==.Darcmatter:BAAANQAECggIEgAAAA==.',
De='Deadtrap:BAAANQABCggIDwAAAA==.Deathsend:BAAANQADCgYICAAAAA==.Deepsicks:BAABNQAECoEdAAIMAAkKphivCwCfAgAMAAkKphivCwCfAgAAAA==.Deepstate:BAAANQAECgEIAQAAAA==.Demonäde:BAAANQADCgUIAgAAAA==.',
Di='Dima:BAABNQAECoEhAAINAAgK6hlORwBwAgANAAgK6hlORwBwAgAAAA==.Dithy:BAAANQAECgIIAgAAAA==.',
Dk='Dkrmk:BAAANQADCgMIAgAAAA==.Dktelli:BAAANQAECgQIBgABNQAECgkJMgAMAHAhAA==.',
Dn='Dne:BAAANQADCggIDgABNQAECgcIEwADAAAAAA==.',
Do='Donavon:BAAANQAECgUICQAAAA==.Donutjelly:BAAANQAECgUIEAAAAA==.Dorivandor:BAAANQAECgQIBAAAAA==.Dornnbryda:BAAANQADCggIDgABNQAECgYIEwADAAAAAA==.',
Dr='Drackothyr:BAAANQAECgUIEQAAAA==.Dreamweavver:BAAANQADCgQIBAAAAA==.Drumark:BAAANQADCgMIAwAAAA==.',
Dw='Dwastring:BAAANQAECgYIDQAAAA==.',
Dy='Dyrale:BAAANQADCgYIGwAAAA==.',
Ek='Eknivar:BAAANQADCgQIBAABNQAECggIIwAOAF0eAA==.',
Er='Erebus:BAAANQAECgQIBAAAAA==.Erragorn:BAAANQAECgQIDgAAAA==.',
Ev='Evisa:BAAANQAECgQIBQAAAA==.Evokholio:BAAANQAECgIIAwAAAA==.',
['Eö']='Eöath:BAAANQAECgEIAQAAAA==.',
Fa='Falaurenta:BAAANQADCgMIBgAAAA==.',
Fe='Feidao:BAAANQAECgIIBAAAAA==.Feralith:BAAANQADCgMIAQAAAA==.',
Fo='Foshizzle:BAAANQABCgIIAgAAAA==.',
Fu='Funkenfox:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëânòr:BAAANQADCgUIBQAAAA==.',
Ga='Gailinn:BAAANQAECgUIDwAAAA==.',
Go='Gorash:BAAANQAECgEJAQABNQAECgUICgADAAAAAA==.',
Gr='Greggdshami:BAABNQAECoEbAAIPAAcKihpTSQARAgAPAAcKihpTSQARAgAAAA==.',
Gu='Gundamus:BAAANQADCgYIBgAAAA==.',
He='Healmonger:BAABNQAECoErAAMQAAkKjh+kEQAnAwAQAAkKjh+kEQAnAwARAAEKwQBzhQANAAAAAA==.Hekili:BAAANQAECgMIAwAAAA==.Heruin:BAAANQAECgcIDwAAAA==.',
Hi='Hictor:BAAANQADCgMIAwAAAA==.',
Ho='Holly:BAAANQADCgEIAQAAAA==.Horse:BAACNQAFFIEVAAIQAAYKDwGNDwBxAQAQAAYKDwGNDwBxAQA1AAQKgTUAAhAACQpwDEVZAOcBABAACQpwDEVZAOcBAAAA.Hourzero:BAAANQAECgEIAQAAAA==.',
Ia='Iammyscars:BAACNQAFFIEFAAISAAIKPg3yEwCIAAASAAIKPg3yEwCIAAA1AAQKgRsAAhIACQreHpgTAOICABIACQreHpgTAOICAAAA.',
Ic='Icu:BAAANQAECgUIBwAAAA==.',
Ik='Ikillu:BAAANQAECgMIAwAAAA==.',
Il='Ilis:BAAANQAECgQIBAAAAA==.Ilovecheetos:BAAANQADCggJDgAAAA==.',
Ja='Jasnahh:BAAANQAECgQICQABNQAECgYICgADAAAAAA==.Jaylas:BAAANQADCgEIAQABNQAECgcIKgATAA4hAA==.',
Jo='Joeexotíc:BAAANQAFFAIIAgAAAA==.',
Ju='Jun:BAACNQAFFIEUAAISAAYKfyMNAgBkAgASAAYKfyMNAgBkAgA1AAQKgTUAAxIACQrRJmAAAAUEABIACQrRJmAAAAUEABQACAqlItoWAJECAAAA.Junfan:BAAANQAECggIDQAAAA==.',
Ka='Kasumaus:BAAANQAECgYIEAAAAA==.',
Ke='Kelly:BAAANQADCggICAAAAA==.Kennifer:BAAANQADCggICQAAAA==.Kenshindune:BAAANQADCgQIBAAAAA==.Keragan:BAAANQADCgEJAQAAAA==.',
Kh='Khalyeesi:BAAANQADCgIIAwAAAA==.Khandris:BAAANQABCggIEgAAAA==.Khazjek:BAAANQADCgYICAAAAA==.Khephris:BAABNQAECoEgAAICAAcK+ByKCQAIAgACAAcK+ByKCQAIAgAAAA==.',
Ki='Kiralni:BAAANQAECgMIAwAAAA==.',
Kn='Knivex:BAABNQAECoEjAAMOAAgKXR7OhgBXAgAOAAcKkh7OhgBXAgACAAMKZBu2GgD0AAAAAA==.',
Ko='Koryann:BAABNQAECoEYAAIVAAYKjxNXLQBHAQAVAAYKjxNXLQBHAQAAAA==.Kosel:BAAANQAECgEIAQAAAA==.Kova:BAAANQAECgUIDAAAAA==.',
Kr='Krazyplaya:BAAANQAECgEIAQAAAA==.',
Kw='Kwarthil:BAAANQABCgEIAQAAAA==.',
Ky='Kyrise:BAABNQAECoEVAAIPAAkKCxGMRQAgAgAPAAkKCxGMRQAgAgAAAA==.',
La='Lambo:BAAANQAECgQJBAAAAA==.Landam:BAAANQAECgQIBwAAAA==.',
Le='Leap:BAAANQADCgMIAwABNQAECggIIAAUACIUAA==.',
Li='Lifeaura:BAACNQAFFIEVAAIWAAYKsBCLAADmAQAWAAYKsBCLAADmAQA1AAQKgTUAAhYACQr3IN4AAF8DABYACQr3IN4AAF8DAAAA.Lifesshaman:BAAANQAECggICAAAAA==.Lightbläster:BAAANQAECgIIBAAAAA==.Lightrider:BAAANQADCgYICwAAAA==.Linesta:BAAANQADCgEIAQAAAA==.Lionroar:BAACNQAFFIELAAIXAAQKgiBvBgB5AQAXAAQKgiBvBgB5AQA1AAQKgScAAhcACQp3I/kFAFEDABcACQp3I/kFAFEDAAAA.Littleguy:BAAANQAECgYIEQAAAA==.',
Ll='Llaothtaed:BAAANQAECggIBgAAAA==.',
Lo='Lochannis:BAAANQAECgUIBQAAAA==.Lokalock:BAAANQAECgQIBQABNQAECgkJMgAMAHAhAA==.Lonee:BAAANQADCgIIAgAAAA==.Lorellei:BAAANQAECgQICgAAAA==.Lothgow:BAAANQAECgEIAgAAAA==.',
Lu='Luxus:BAAANQADCgIJAgAAAA==.',
['Lâ']='Lân:BAAANQAECgYIBwABNQABCgIIAgADAAAAAA==.',
Ma='Maelynn:BAAANQADCgUIBQAAAA==.Manticor:BAAANQADCgcIBgAAAA==.Martyglaive:BAAANQAECgYIEwAAAA==.Matteas:BAAANQAECgYIEAAAAA==.',
Me='Menionblue:BAAANQADCgUIBQAAAA==.Mew:BAAANQAECgUIDwAAAA==.',
Mf='Mfdoom:BAABNQAECoEsAAQBAAkKJR2KNwCSAgABAAgK6RyKNwCSAgAYAAMKIBspFQDNAAAZAAMKfBXmOgDLAAABNQADCgIIBAADAAAAAA==.',
Mi='Mizrey:BAAANQAFFAEIAQAAAA==.Mizukisakura:BAAANQAECgEIAQAAAA==.',
Mo='Mograins:BAABNQAECoEpAAMZAAkKzx5wDAAlAgABAAcKChxfUwA6AgAZAAYKUCFwDAAlAgAAAA==.Monzcarro:BAAANQADCggICwAAAA==.Mordar:BAAANQADCgUIBwAAAA==.Morgainne:BAAANQAECgIIAgAAAA==.Mortmor:BAAANQAECgYICwAAAA==.',
Mu='Muffinn:BAABNQAECoEfAAINAAgKawpRgADdAQANAAgKawpRgADdAQAAAA==.Mursê:BAAANQAECgUIBwAAAA==.',
My='Mymdos:BAABNQAECoEvAAILAAkKQyDCIQAiAwALAAkKQyDCIQAiAwABNQABCgIIAgADAAAAAA==.Myrmidonn:BAAANQADCgYICgAAAA==.',
['Mä']='Mästérdòn:BAAANQAECgYIBwAAAA==.',
['Må']='Måsterdon:BAAANQAECgQIDAAAAA==.',
['Mô']='Môiraine:BAAANQAECgYIBwAAAA==.',
Ne='Nercos:BAAANQAECgEIAQABNQAFFAIIAgADAAAAAA==.Nercqt:BAAANQAFFAIIAgAAAA==.Neverborn:BAAANQAECgYIEQAAAA==.',
Ni='Niame:BAAANQAECgQIBgAAAA==.Nitraina:BAAANQAECgUIEQAAAA==.Niyabelle:BAABNQAECoEcAAMJAAcKmhyPEQBWAgAJAAcKmhyPEQBWAgAIAAIKng+6cwCIAAAAAA==.',
No='Noggenfloggr:BAAANQAECgUIBwAAAA==.Nomesis:BAAANQAECgEIAQAAAA==.',
Ny='Nyxth:BAAANQABCggIDQAAAA==.',
Od='Odïn:BAAANQADCgYIDAAAAA==.',
Ol='Oleevia:BAABNQAECoEiAAIRAAgKGhaRHAA8AgARAAgKGhaRHAA8AgAAAA==.',
Om='Omgdingers:BAAANQAECgYICAABNQAECggICwADAAAAAA==.',
On='Oneshót:BAAANQADCgYICAABNQAECgcIDgADAAAAAA==.Oneth:BAAANQAECgIIAgAAAA==.',
Or='Oraxia:BAAANQAECgEIAQABNQAECgYICAADAAAAAA==.Ords:BAAANQABCgYICAAAAA==.Orgdynamite:BAAANQAECgUIBgABNQAFFAYIFQAFAIEXAA==.Orgsham:BAACNQAFFIEVAAIFAAYKgRf6BAAPAgAFAAYKgRf6BAAPAgA1AAQKgTEAAwUACQrOI1oKAIkDAAUACQrOI1oKAIkDAAwAAQprDpstAEYAAAAA.',
Pa='Paedragon:BAAANQADCgMIAwABNQAECgIIAgADAAAAAA==.Paimon:BAAANQADCgYIBgAAAA==.Paladareian:BAABNQAECoEqAAITAAcKDiFMKwCgAgATAAcKDiFMKwCgAgAAAA==.',
Pe='Pej:BAACNQAFFIEVAAQaAAYKXRWFBgAbAQAaAAQKbg6FBgAbAQAbAAQKSwwjBQAYAQAcAAMK3gdDDwDKAAA1AAQKgTgABBoACQqKH04NAHMCABoACAqJH04NAHMCABwABwpPF+UZAAgCABsABQo6HfYJAKoBAAAA.Pejbolt:BAAANQADCgcICgABNQAFFAYIFAASAH8jAA==.',
Ph='Phoenixa:BAAANQAECgEIAQAAAA==.',
Pl='Plus:BAAANQAECgcICwAAAA==.',
Po='Powerslavé:BAABNQAECoEjAAILAAkK0h5LLwDtAgALAAkK0h5LLwDtAgAAAA==.',
Pr='Priestitoot:BAAANQAECgMIAwAAAA==.',
Pu='Pumkinhead:BAABNQAECoEgAAIFAAkKPRC3VAD5AQAFAAkKPRC3VAD5AQAAAA==.',
Py='Pyromania:BAAANQAECgYIDgAAAA==.',
['Pä']='Pä:BAAANQADCgMIAQAAAA==.',
Ra='Raiden:BAAANQAECgYIEwAAAA==.Rat:BAAANQABCgIIAgAAAA==.',
Re='Rentacat:BAAANQADCggICwAAAA==.Retropâlly:BAAANQADCgMIAwAAAA==.Revoker:BAAANQADCgUICAABNQAECgkJIgAdADsbAA==.',
Ro='Rogi:BAAANQAECgMIBAABNQABCgIIAgADAAAAAA==.',
['Rö']='Römana:BAAANQAECgYIEwAAAA==.',
Sa='Saliva:BAAANQADCggICAAAAA==.Sanguinaris:BAAANQAECgEIAQABNQAECgUICgADAAAAAA==.Sareya:BAAANQABCgYIDgAAAA==.Sataanic:BAAANQAECgMIAwAAAA==.Satyrical:BAABNQAECoEVAAMeAAYKchj2VgCNAQAeAAYKchj2VgCNAQAfAAIKsAmlqQBYAAAAAA==.',
Sc='Scorch:BAAANQAECgYIEAAAAA==.',
Se='Sedrayn:BAAANQAECgEIAQAAAA==.Selatha:BAAANQABCgIIAgABNQAFFAMICgAOAIYcAA==.Selystine:BAAANQADCgUICAAAAA==.Semaj:BAAANQADCgcIBwAAAA==.',
Sh='Shamwowolio:BAABNQAECoEfAAIFAAgKyRHvWgDjAQAFAAgKyRHvWgDjAQAAAA==.Shayd:BAABNQAECoEiAAQdAAkKOxsUBACMAgAdAAgKchgUBACMAgANAAgKuRnzTABgAgAHAAEKOxvzbQBSAAAAAA==.Shirokyu:BAAANQADCggICAAAAA==.Shirra:BAAANQADCgcIBwAAAA==.Shirraz:BAAANQAECgYICwAAAA==.Sho:BAAANQABCgcICQAAAA==.Shroomicide:BAAANQAECggIBgAAAA==.',
Si='Sicaris:BAAANQADCgYICgABNQAECggIEQADAAAAAA==.Sicksdeep:BAACNQAFFIEFAAMLAAMKwAmWKQCJAAALAAIKmgyWKQCJAAAgAAEKDARTBQBEAAA1AAQKgSMAAgsACQp+FVpeAFQCAAsACQp+FVpeAFQCAAAA.Sigürd:BAAANQADCgEIAQAAAA==.Silverstorm:BAAANQAECgUIBwAAAA==.',
Sk='Skÿe:BAABNQAECoEbAAIHAAcKpBrCIQAgAgAHAAcKpBrCIQAgAgAAAA==.',
Sl='Slamma:BAACNQAFFIEUAAILAAYKCiLfBABaAgALAAYKCiLfBABaAgA1AAQKgTcAAgsACQqKJrwCAOMDAAsACQqKJrwCAOMDAAAA.Slappinbubs:BAAANQAECgEJAQAAAA==.Slicedbreád:BAACNQAFFIESAAMFAAUKbR+9CwB7AQAFAAQKkh29CwB7AQAPAAUKmgZSDABeAQA1AAQKgS0AAw8ACQp1GeFCACoCAA8ACQp1GeFCACoCAAUAAwrOI9eZADQBAAE1AAQKAQgBAAMAAAAA.',
Sm='Smokadaganga:BAABNQAECoEWAAMhAAkKDQsfBABeAQAhAAYKMA0fBABeAQAOAAcKQQbvCwFSAQAAAA==.',
So='Sols:BAABNQAECoEOAAMCAAcKFRj3GgDxAAAOAAYKYhPt3QCmAQACAAMKMhv3GgDxAAABNQAECgkJIwALANIeAA==.Sondirion:BAAANQAECgYIEwAAAA==.Sowet:BAAANQAECgIIAgAAAA==.',
Sp='Speoghii:BAABNQAECoEYAAIBAAcKVBh2XQAdAgABAAcKVBh2XQAdAgAAAA==.Spifftreebug:BAABNQAECoEcAAMGAAcKpwyCUQBrAQAGAAcKpwyCUQBrAQAXAAEKlhA9ZwA1AAAAAA==.Sprinklez:BAAANQAECgQIDAAAAA==.',
St='Steelerschic:BAAANQAECgIIBAAAAA==.Stormleader:BAABNQAECoEnAAMXAAkKJBLtGgA2AgAXAAkKJBLtGgA2AgAiAAEK4wBOXwATAAAAAA==.',
Su='Surge:BAAANQAECgIIAwAAAA==.',
Ta='Tai:BAABNQAECoEbAAIjAAcK4huDDgAYAgAjAAcK4huDDgAYAgAAAA==.Tainema:BAAANQAECgIIBAAAAA==.Tankguywowie:BAAANQAECgUIBQABNQAECgkJHAAGAB8VAA==.Taurriel:BAAANQAECgYIEAAAAA==.Tazzm:BAABNQAECoEfAAIHAAgKsgNcOwBHAQAHAAgKsgNcOwBHAQAAAA==.',
Te='Teranok:BAAANQAECgcICgAAAA==.Terzal:BAAANQADCgYIBgAAAA==.',
Th='Thalel:BAAANQAECgQIDQAAAA==.Theacused:BAAANQAECgYICQABNQAFFAIIAwADAAAAAA==.Thoir:BAACNQAFFIEVAAIPAAYKLCIqAgBvAgAPAAYKLCIqAgBvAgA1AAQKgTUAAg8ACQrSJb4EAJQDAA8ACQrSJb4EAJQDAAE1AAUUBggVABAADwEA.Thorodinson:BAAANQAECgQIAwAAAA==.',
Ti='Tipsylorcet:BAAANQAECgUIDwAAAA==.',
Tk='Tkrain:BAAANQADCgUIDQAAAA==.',
Tr='Trashbull:BAAANQAECggIAgAAAA==.Tricktickler:BAAANQAECgIIAgAAAA==.Troy:BAAANQADCgUIBQAAAA==.',
Tu='Tuskani:BAAANQABCggIEgAAAA==.',
Ty='Tybird:BAABNQAECoEdAAIKAAgKPB2vFgCyAgAKAAgKPB2vFgCyAgAAAA==.Tyranisv:BAAANQADCgMIAwAAAA==.',
Ul='Ulsull:BAAANQADCgcIEAAAAA==.Ulyssi:BAACNQAFFIEVAAIRAAYKYxt/AgA2AgARAAYKYxt/AgA2AgA1AAQKgTUAAhEACQqBJQoCALoDABEACQqBJQoCALoDAAAA.',
Um='Ummpatas:BAAANQAECgEIAQAAAA==.',
Us='Usseel:BAAANQADCgMIAwAAAA==.',
['Uñ']='Uñàble:BAAANQADCgIIAgAAAA==.',
Va='Valymus:BAAANQADCgIIAgABNQAECgkJIgAdADsbAA==.Vandagylon:BAAANQADCgYIDAAAAA==.Vandals:BAAANQAECgYIDwAAAA==.',
Ve='Ven:BAAANQAECgUIEQAAAA==.Ver:BAAANQADCgMIAQAAAA==.',
Vo='Voltaire:BAAANQADCgIIAgAAAA==.',
Wa='Walle:BAAANQADCgEIAQAAAA==.Wankstar:BAAANQAECgEIAQAAAA==.Warvein:BAAANQAECgcIEQAAAA==.',
We='Weehunt:BAAANQAECgUIEAAAAA==.Weeshami:BAAANQADCgMIAwAAAA==.',
Wh='Whillia:BAAANQADCgMIAwAAAA==.',
Wi='Wicah:BAAANQAECgQICQAAAA==.Wicka:BAABNQAECoEeAAIPAAcKcCGKKgCWAgAPAAcKcCGKKgCWAgAAAA==.Widowblade:BAAANQAECgIIAgAAAA==.Wildriver:BAAANQAECgUIDwAAAA==.Willferàl:BAAANQADCgMIAwAAAA==.',
Xa='Xaehyun:BAACNQAFFIEQAAIEAAYKhiM7BgByAQAEAAYKhiM7BgByAQA1AAQKgR0AAgQACQrvJuQUAIgCAAQACQrvJuQUAIgCAAAA.Xandrelar:BAAANQADCggIDQABNQAECgkJIgAdADsbAA==.',
Xm='Xmrpdk:BAACNQAFFIEVAAIfAAYKtCPIAQB5AgAfAAYKtCPIAQB5AgA1AAQKgTUAAh8ACQq1JbwBANUDAB8ACQq1JbwBANUDAAAA.Xmrppally:BAAANQAECgcICAABNQAFFAYIFQAfALQjAA==.',
Xy='Xy:BAAANQADCggICAAAAA==.',
Ya='Yarina:BAAANQADCgUIBQAAAA==.',
Yo='Yoyiek:BAABNQAECoEcAAMGAAkKHxU5KAByAgAGAAkKHxU5KAByAgAiAAMKcwLlQQBdAAAAAA==.',
Za='Zalynn:BAAANQAECgEIAQAAAA==.Zanne:BAABNQAECoEhAAIHAAkKDx3YFACiAgAHAAkKDx3YFACiAgAAAA==.Zarthul:BAAANQAECgIIBAAAAA==.',
Ze='Zehara:BAAANQADCgMJAwAAAA==.Zenori:BAAANQADCggICAAAAA==.',
Zh='Zhenyu:BAAANQADCgQIBAABNQAECgUICgADAAAAAA==.',
Zl='Zlot:BAECNQAFFIEVAAMNAAYKchxBCQCLAQANAAQKMh9BCQCLAQAHAAMKuhujEAAEAQA1AAQKgTUAAw0ACQrnJR4aABgDAA0ABwqbJh4aABgDAAcABwrAH5gfADUCAAAA.',
Zu='Zulani:BAAANQADCgIIAgAAAA==.',
['Õn']='Õneshot:BAAANQAECgcIDgAAAA==.',
['Øñ']='Øñêshot:BAAANQADCggIEwABNQAECgcIDgADAAAAAA==.',
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
