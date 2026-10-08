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

local lookup = {'Mage-Arcane','Mage-Frost','Unknown-Unknown','Warrior-Arms','Warrior-Protection','Shaman-Elemental','Shaman-Restoration','Hunter-BeastMastery','DeathKnight-Blood','Druid-Balance','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Devastation','Rogue-Assassination','Paladin-Retribution','Paladin-Holy','Warlock-Demonology','DemonHunter-Havoc','Hunter-Marksmanship','Paladin-Protection','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Priest-Discipline','Druid-Feral','Hunter-Survival','Warrior-Fury','Monk-Windwalker','Monk-Brewmaster','Priest-Shadow','Druid-Guardian','DeathKnight-Unholy',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abdorei:BAABNQAECoEWAAMBAAcKyBBk/QBsAQABAAYK4w5k/QBsAQACAAIKKhLZKgB6AAAAAA==.',
Ac='Accilatim:BAABNQAECoEZAAICAAgKVxs7BgB5AgACAAgKVxs7BgB5AgAAAA==.',
Ag='Aggressive:BAAANQAECgIIAgAAAA==.Agries:BAAANQADCgYIAgAAAA==.',
Ai='Aiba:BAAANQAECgQIDQABNQAECgYIDAADAAAAAA==.',
Ak='Akcloud:BAABNQAECoEVAAMEAAcKZRkWhwDlAQAEAAcKCxcWhwDlAQAFAAIKdhbELwCBAAAAAA==.',
Al='Alexei:BAAANQAECgMIBAAAAA==.Allhopeisded:BAAANQAECgYICAAAAA==.',
An='Andii:BAAANQAECggIEgAAAA==.Anglecat:BAAANQAECgcIEgAAAA==.Angusbeef:BAABNQAECoEVAAMGAAYKsRSXegCDAQAGAAYKsRSXegCDAQAHAAIKgRHz6wBhAAAAAA==.',
Ar='Arames:BAAANQADCgEIAQAAAA==.Ardon:BAAANQAECgUICgAAAA==.',
As='Asteruis:BAABNQAECoEfAAIIAAkKTR42HQAIAwAIAAkKTR42HQAIAwAAAA==.Asuraa:BAAANQADCgIIAgAAAA==.',
Av='Avoral:BAAANQADCgEIAQAAAA==.',
Ba='Bafoonery:BAAANQADCgUIBQAAAA==.Bananashoes:BAAANQABCgEIAQAAAA==.Barkendremix:BAAANQADCgYIBgABNQAECggIFQAJAD0VAA==.Bathsheber:BAAANQADCgYIBgABNQAFFAUIDgACAHojAA==.Baulbuster:BAAANQAECgEIAQAAAA==.',
Be='Bearden:BAABNQAECoEqAAIKAAkK6SDVCwBeAwAKAAkK6SDVCwBeAwAAAA==.Belroy:BAAANQAECgEIAgAAAA==.',
Bi='Bighani:BAAANQAECgQIBAABNQAECggIHAALALkaAA==.',
Bj='Bjorum:BAABNQAECoEdAAIMAAgKoSKmBwDzAgAMAAgKoSKmBwDzAgAAAA==.',
Bo='Bodytwodafa:BAABNQAECoETAAINAAgKJSGIBgALAwANAAgKJSGIBgALAwABNQAECgkJHAALAAsYAA==.',
Br='Bretero:BAAANQAECgEIAQAAAA==.Broken:BAAANQAECgUIDAAAAA==.Brucecampbel:BAAANQAECgEJAgAAAA==.',
Bu='Bubbleyou:BAAANQAECgUICwAAAA==.',
['Bé']='Bécca:BAAANQAECgMICAAAAA==.',
Ca='Calerina:BAAANQAECgIIAgAAAA==.Cantarella:BAABNQAECoEbAAIOAAcKQQSeUQApAQAOAAcKQQSeUQApAQAAAA==.Carlyle:BAABNQAECoEjAAMPAAgKag9onwCsAQAPAAcKQRBonwCsAQAQAAIKPwzo8ABjAAAAAA==.Casadora:BAAANQABCgQIBgAAAA==.Cascade:BAAANQADCgcIBwAAAA==.Caylara:BAAANQADCgYIBgAAAA==.',
Ch='Cheesecake:BAAANQADCgEIAQAAAA==.Chromehound:BAAANQADCgIIAgAAAA==.',
Cl='Claoibh:BAAANQAECgEJAQABNQAECggIGQARAPkdAA==.',
Co='Collossuss:BAAANQADCggIFgAAAA==.Corno:BAAANQAECgIIAgAAAA==.',
Cu='Cuddles:BAAANQADCggIBwAAAA==.Curacao:BAAANQAECgQIBAAAAA==.',
Da='Dafa:BAABNQAECoEcAAILAAkKCxiMFQCfAgALAAkKCxiMFQCfAgAAAA==.Dafaw:BAAANQAECgQIBAAAAA==.Darkstarr:BAAANQADCggIKAAAAA==.Darwynne:BAAANQADCgEIAQAAAA==.',
De='Deddafa:BAAANQAECgIIAgAAAA==.Dekaar:BAAANQAECgQICgAAAA==.Desdemonica:BAAANQAECgQIEgAAAA==.',
Di='Diaff:BAAANQADCgMIAwAAAA==.Dillythewily:BAAANQADCggICAAAAA==.Dirtyspice:BAAANQAECgUIEQAAAA==.',
Do='Domain:BAABNQAECoEcAAMLAAgKuRpVFwCMAgALAAgKuRpVFwCMAgASAAUKjA9XUwAKAQAAAA==.Domotouch:BAAANQAECgMICQABNQAECgYIEwADAAAAAA==.Donfalprun:BAABNQAECoEXAAIPAAgKiBwxYwBEAgAPAAgKiBwxYwBEAgAAAA==.Donot:BAAANQADCgcICAAAAA==.Doomstout:BAABNQAECoEfAAIBAAgKDx/EUwDIAgABAAgKDx/EUwDIAgAAAA==.',
Dr='Draconus:BAAANQAECgcICAAAAA==.Dralas:BAABNQAECoEVAAMTAAcK7gsBPQA7AQATAAYKiwsBPQA7AQAIAAEKQw4PLAFIAAAAAA==.',
Du='Durex:BAABNQAECoElAAIEAAgKLxqNUQB6AgAEAAgKLxqNUQB6AgAAAA==.Duskstout:BAAANQAECgEIAwAAAA==.',
Ea='Earthcrusher:BAAANQADCgEJAgAAAA==.',
El='Eldron:BAAANQAECgUIEAAAAA==.Elij:BAAANQAECgcIDgAAAA==.Elunaire:BAAANQADCgYJCQAAAA==.',
Em='Emelec:BAAANQADCgYJBgAAAA==.Emeraldwish:BAAANQAECgcIEwAAAA==.',
Es='Eskimojoe:BAAANQADCgYICQAAAA==.',
Ev='Evinco:BAAANQAECgcIEAAAAA==.',
Ex='Executie:BAACNQAFFIEMAAIEAAUKhxHnDwCJAQAEAAUKhxHnDwCJAQA1AAQKgS8AAwQACQpmIz8NAIoDAAQACQpmIz8NAIoDAAUABArOGHMiAAgBAAAA.',
Ez='Ezmerrelda:BAAANQAECgUICwAAAA==.',
Fa='Fancy:BAAANQAECgQIBAAAAA==.',
Fi='Fieryember:BAAANQAECgQIBwABNQAECggIHAALALkaAA==.Finni:BAAANQADCggJCAAAAA==.Fistvendor:BAAANQADCgYIBgAAAA==.',
Fl='Flasheals:BAABNQAECoElAAIQAAgKShnDOwBYAgAQAAgKShnDOwBYAgAAAA==.',
Fr='Frostwave:BAAANQAECgUIEwAAAA==.',
Fu='Fujiyama:BAAANQAECgYIEwAAAA==.',
Gb='Gbl:BAAANQAECgQIBAAAAA==.',
Gn='Gnometoaster:BAAANQAECgcICgAAAA==.',
Go='Goldendk:BAAANQAECgQICAAAAA==.Goldendwarf:BAAANQAECgQICgAAAA==.Goldenshield:BAAANQAECgcIDQAAAA==.',
Gr='Gravewrath:BAAANQADCgUJBwAAAA==.Groggi:BAAANQADCgIJAgAAAA==.',
Gu='Gunjamon:BAAANQADCgQICAAAAA==.',
Gy='Gymma:BAAANQAECgEIBAAAAA==.',
Ha='Hafsak:BAAANQAECgIIAgABNQAECgUIDAADAAAAAA==.Halppme:BAABNQAECoEUAAIUAAYKJRG9KwBTAQAUAAYKJRG9KwBTAQAAAA==.',
Ho='Hoowan:BAAANQADCgEIAQAAAA==.Horraoibhy:BAABNQAECoEZAAMRAAgK+R2vSQBYAgARAAcK0hyvSQBYAgAVAAIKGCDmPgC8AAAAAA==.',
Im='Immogen:BAAANQADCgMIAwAAAA==.',
Is='Isklexi:BAABNQAECoEeAAIKAAgKwBOmNwAHAgAKAAgKwBOmNwAHAgAAAA==.',
Iy='Iyatil:BAAANQAECgIJAgAAAA==.',
Ja='Jabjek:BAAANQAECgEIAQAAAA==.Jamaz:BAAANQAECgQIBgAAAA==.Jamdalf:BAAANQAECgIIBgAAAA==.Jamocalypse:BAAANQAECgYICAAAAA==.Jazal:BAAANQAECgEIAgAAAA==.',
Jo='Jordananon:BAAANQAECgQIBAAAAA==.',
Jt='Jtull:BAAANQAECgIIAQAAAA==.',
Ka='Kanamé:BAAANQADCggIEAAAAA==.Kaven:BAAANQADCgQIBAAAAA==.',
Ke='Kelisa:BAAANQAECgcICAAAAA==.Keramono:BAAANQADCgQIBAAAAA==.',
Ki='Kimaera:BAAANQADCggICQAAAA==.Kimjunggheal:BAAANQAECgIIAwAAAA==.',
Kr='Kreshath:BAAANQADCgYICQAAAA==.Krinxy:BAAANQADCgYIBgAAAA==.',
Ku='Kuratcha:BAAANQAECgQIDAABNQAECggIHAALALkaAA==.',
['Kí']='Kíng:BAAANQAECgQIBwABNQAECggIHAALALkaAA==.',
La='Ladelock:BAABNQAECoEVAAIWAAYK4wkMDgBNAQAWAAYK4wkMDgBNAQAAAA==.Lavose:BAAANQADCgIIAgABNQAECgQIDAADAAAAAA==.',
Le='Leaf:BAAANQAECgYICgAAAA==.',
Li='Liadan:BAABNQAECoEaAAIQAAgKMw38ZQDAAQAQAAgKMw38ZQDAAQAAAA==.Lighteye:BAAANQAECgUIEgAAAA==.Linesdel:BAAANQADCgcIBwAAAA==.',
Lo='Lomm:BAABNQAECoEVAAIJAAgKPRVjPQDrAQAJAAgKPRVjPQDrAQAAAA==.',
Ma='Macklerina:BAAANQAECgYIDAAAAA==.Magicdorf:BAABNQAECoEcAAIBAAcKbyB6bACQAgABAAcKbyB6bACQAgAAAA==.Manhitrogue:BAAANQAECgEIAQAAAA==.',
Mc='Mcgavin:BAAANQAECgUIBwAAAA==.',
Me='Megarayquaza:BAABNQAECoEUAAMSAAcKywzVQACBAQASAAcKywzVQACBAQALAAIKggHUYgAuAAAAAA==.',
Mi='Mikeyouk:BAAANQADCgUICAAAAA==.Minimum:BAAANQAECgcIEQAAAA==.Misties:BAAANQADCgQIBAAAAA==.',
Mo='Monnöke:BAABNQAECoEVAAIUAAYKrwfqOwDnAAAUAAYKrwfqOwDnAAAAAA==.Mooneater:BAABNQAECoEaAAMHAAcKSBrdUAD1AQAHAAcKSBrdUAD1AQAGAAEKLgJAKwEnAAAAAA==.Morgwyn:BAAANQAECgEIAQAAAA==.',
My='Myrolan:BAABNQAECoEXAAISAAcKJh/pIgBdAgASAAcKJh/pIgBdAgAAAA==.',
Na='Naturallight:BAAANQADCgYIBgAAAA==.',
Ne='Nergaoul:BAAANQADCgYIBgAAAA==.Nevyn:BAABNQAECoEUAAIBAAYKwg9U8wB/AQABAAYKwg9U8wB/AQAAAA==.',
Ni='Nightplague:BAAANQAECgEIAQAAAA==.Nightsage:BAAANQADCgIJAwAAAA==.Nightslayer:BAAANQAECgQICwAAAA==.Niji:BAAANQAECgYIDAAAAA==.Nininhp:BAAANQAECgEIBgABNQAECgQIBQADAAAAAA==.Nithari:BAAANQAECgUIEQAAAA==.',
No='Nosst:BAAANQADCgQIBwAAAA==.Nostdormu:BAAANQADCgMIAwAAAA==.Nostu:BAABNQAECoEXAAMXAAcKrByIQgA8AgAXAAcKahyIQgA8AgAYAAMKwiCMEAAIAQAAAA==.Now:BAABNQAECoEUAAIPAAgKWhxLUQB4AgAPAAgKWhxLUQB4AgAAAA==.',
Oa='Oathra:BAABNQAECoEUAAIUAAcKkxcNHgDNAQAUAAcKkxcNHgDNAQAAAA==.',
Oh='Ohpa:BAABNQAECoEaAAIRAAgKWBGFcgDgAQARAAgKWBGFcgDgAQAAAA==.',
Oj='Ojikan:BAABNQAECoEWAAIZAAcKUCS5BgDUAgAZAAcKUCS5BgDUAgAAAA==.',
Os='Ossian:BAAANQAECgEIBAAAAA==.',
Pa='Paje:BAAANQADCgUIBQAAAA==.Panday:BAAANQADCgIIAgAAAA==.Pathogenn:BAAANQADCgYIBQAAAA==.',
Pe='Peachoolong:BAAANQAECggIEAAAAA==.Peludisho:BAAANQADCgQIBQABNQAFFAIIAgADAAAAAA==.Pepecry:BAAANQAECgMIAwABNQAECggIHAALALkaAA==.',
Ph='Phoblade:BAAANQAECgUIDAAAAA==.Phobreeze:BAAANQAECgQICgAAAA==.Phogurl:BAAANQADCgQIBQAAAA==.Phoktard:BAAANQADCgYIBgAAAA==.',
Pi='Pirotess:BAABNQAECoEeAAIPAAgK+xmUYQBJAgAPAAgK+xmUYQBJAgAAAA==.',
Po='Popz:BAAANQADCgEIAQAAAA==.Pororo:BAAANQAECgYIBgAAAA==.',
Pr='Preorcthego:BAACNQAFFIELAAMTAAUKcBR3DQA5AQATAAQKjBR3DQA5AQAIAAIK9RWPHQCmAAA1AAQKgR8ABBMACQq1HGcVAJwCABMACQrYG2cVAJwCABoABAqPEQcNAL0AAAgAAQo1I24gAWMAAAAA.Presiric:BAAANQADCgEJAgAAAA==.',
Pu='Puppye:BAAANQAECgQIDAAAAA==.',
Ra='Ranalia:BAAANQADCgQIBAAAAA==.',
Re='Reeapally:BAABNQAECoEbAAMPAAgKzBMHhADuAQAPAAgKzBMHhADuAQAQAAYKTAgvoQAXAQAAAA==.Reylord:BAAANQADCgUICwAAAA==.',
Rh='Rheizen:BAABNQAECoEbAAIFAAcK9xHcFQCeAQAFAAcK9xHcFQCeAQAAAA==.',
Ro='Ropopo:BAAANQAECgQIBQABNQAECgQIDAADAAAAAA==.',
['Rö']='Röyksopp:BAABNQAECoEaAAMBAAcKgAskBgFcAQABAAYKcAskBgFcAQACAAEK3gv0OwA9AAAAAA==.',
Sa='Salbahe:BAAANQADCgUIBQAAAA==.Samarah:BAAANQADCgIJAgAAAA==.Sandewor:BAAANQADCgYICAABNQADCggJFwADAAAAAA==.Sarafyn:BAAANQAECgUIEQAAAA==.Sauceguzzler:BAAANQADCgYIBAAAAA==.',
Sc='Scáthach:BAAANQAECgEIAgAAAA==.',
Se='Seragaki:BAABNQAECoEZAAMXAAcKoRaNXADbAQAXAAcKoRaNXADbAQAYAAIK/BDiJAA2AAAAAA==.',
Sh='Sheepwarrior:BAABNQAECoEYAAIbAAcKvxKPDADMAQAbAAcKvxKPDADMAQAAAA==.Shop:BAAANQADCgMIAwAAAA==.',
Si='Siegescale:BAAANQAECgUIEgAAAA==.Siegrorc:BAAANQADCgcIEwAAAA==.Sindrila:BAAANQAECgIIBQAAAA==.Sionshope:BAAANQADCgIJAwAAAA==.',
Sl='Slaybelle:BAAANQADCgcIBwAAAA==.Slayerhunt:BAAANQADCggJFwAAAA==.Slayerlock:BAAANQADCgUIBQAAAA==.Slayertin:BAAANQADCgYIFAABNQADCggJFwADAAAAAA==.Sleptforever:BAABNQAECoEUAAMcAAYKmhkDKACtAQAcAAYKmhkDKACtAQAdAAEKFBQULAA4AAAAAA==.Slumped:BAAANQADCgEIAQAAAA==.',
So='Sorian:BAAANQADCgEIAQAAAA==.',
St='Stonehand:BAABNQAECoEsAAIeAAkKgBh7EgC6AgAeAAkKgBh7EgC6AgAAAA==.Strongbow:BAABNQAECoEVAAIIAAcKmQbvqACAAQAIAAcKmQbvqACAAQAAAA==.',
Su='Subudai:BAAANQAECgYIEgAAAA==.Sugarboi:BAABNQAECoEgAAIfAAgKyA7SHAB1AQAfAAgKyA7SHAB1AQAAAA==.',
Sx='Sxytrev:BAAANQAECgEIAgAAAA==.',
Ta='Tatonka:BAAANQADCgIIAgAAAA==.Tatsuryu:BAAANQABCgYJBgAAAA==.',
Tb='Tbizkut:BAAANQAECgEIAgAAAA==.',
Th='Then:BAABNQAECoEYAAMCAAkK/BfNBgBhAgACAAkK/BfNBgBhAgABAAUKjgwPJAEqAQAAAA==.Thisfar:BAAANQAECgIIAgABNQAECgYIEwADAAAAAA==.',
Ti='Timemaster:BAAANQADCgIJAwAAAA==.',
To='Tokido:BAAANQAECgIIAgAAAA==.Tongpakfu:BAAANQAECgQIBAAAAA==.Topflight:BAAANQAECgQIBwAAAA==.',
Tr='Trailblazegu:BAAANQADCgYIDwAAAA==.Troiikka:BAAANQAECgQICQAAAA==.Troiikâ:BAABNQAECoEfAAIUAAYKhw30MwAaAQAUAAYKhw30MwAaAQAAAA==.Troikä:BAAANQADCgIIAgAAAA==.',
Tz='Tzolkin:BAAANQADCgIIAgABNQAECgEIAQADAAAAAA==.',
Ul='Uldirtydemon:BAABNQAECoEaAAMLAAcK9xxaHgBBAgALAAcK9xxaHgBBAgASAAEKOwxHfwA8AAAAAA==.Uldirtydruid:BAAANQAECgEIAQAAAA==.',
Un='Unsamana:BAAANQAECgQICAABNQAECggIHAALALkaAA==.',
Up='Update:BAABNQAECoEaAAIBAAgKEwUy8gCAAQABAAgKEwUy8gCAAQAAAA==.',
Uw='Uwantwar:BAAANQAECgQIBAAAAA==.',
Ve='Velari:BAAANQADCggICAAAAA==.',
Vi='Vidich:BAAANQAECgMIDAAAAA==.Viralus:BAAANQADCgcICQAAAA==.',
Vo='Vomai:BAAANQAECgEIAwAAAA==.',
Wa='Wanaatlarboy:BAABNQAECoEfAAIeAAgK1wz3KAC5AQAeAAgK1wz3KAC5AQAAAA==.Waywyrd:BAAANQAECgMIAwAAAA==.',
Wu='Wunderbar:BAAANQAECgUIEAAAAA==.Wunderburger:BAAANQADCgIIAgAAAA==.Wunderground:BAAANQADCgIIAgAAAA==.',
Xa='Xannada:BAAANQADCgYICQAAAA==.',
Xe='Xeïla:BAAANQADCgQIAwABNQAECgQIDgADAAAAAA==.',
Xo='Xodiak:BAAANQAECgQICgAAAA==.',
Yo='Yodadogownz:BAAANQADCgEIAQAAAA==.Yoh:BAABNQAECoEVAAMJAAcKkh0JPADyAQAJAAYKdBwJPADyAQAgAAcKvBXMUQCjAQAAAA==.',
Za='Zarutobi:BAAANQAECgQIBQABNQAECgYIDAADAAAAAA==.',
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
