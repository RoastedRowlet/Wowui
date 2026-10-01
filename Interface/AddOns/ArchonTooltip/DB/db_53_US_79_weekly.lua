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

local lookup = {'Mage-Arcane','Shaman-Restoration','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Unknown-Unknown','Druid-Restoration','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Holy','Paladin-Protection','Priest-Shadow','Druid-Feral','Druid-Balance','Priest-Holy','Hunter-BeastMastery','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Frost','Hunter-Survival','Monk-Mistweaver',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaronius:BAAANQAECgUIDAAAAA==.',
Ac='Acceptance:BAAANQADCgYICAAAAA==.',
Ad='Adoe:BAAANQAECgUICAAAAA==.Adora:BAAANQAECgMJBQAAAA==.',
Ag='Agaliarept:BAAANQADCgMIAwAAAA==.Agathos:BAAANQADCgYJDQAAAA==.',
Ai='Aidenator:BAAANQAECgUICAAAAA==.',
Al='Aluni:BAAANQADCgEIAQAAAA==.',
Am='Ammastin:BAAANQABCgMIAwAAAA==.',
An='Andorix:BAAANQADCgEIAQAAAA==.Andretta:BAAANQADCggIDgAAAA==.Angelneko:BAAANQAECgUIEAAAAA==.',
Ar='Arinthian:BAAANQABCgQIBAAAAA==.Artrian:BAAANQADCggJCAAAAA==.',
At='Atetoomuch:BAAANQABCgYIBgAAAA==.Atthis:BAAANQADCgEIAQAAAA==.',
Au='Auroraa:BAAANQAECgQICQAAAA==.',
Av='Avalectra:BAAANQAECgEIAQAAAA==.',
Az='Azmodeaz:BAABNQAECoEdAAIBAAcKGAwyygCgAQABAAcKGAwyygCgAQAAAA==.Aztrik:BAAANQAECgUJDAAAAA==.',
Ba='Bajapanti:BAAANQAECgYIDwAAAA==.Ballyhøø:BAAANQAECgcICwAAAA==.Baxstab:BAAANQAECgYIDwAAAA==.',
Be='Belladeon:BAAANQAECgcIEgAAAA==.',
Bh='Bhagee:BAAANQADCgUIBQAAAA==.',
Bl='Blackpatch:BAAANQAECgYIEAAAAA==.Blaqkid:BAAANQADCgYIBgAAAA==.Blaqsun:BAAANQAECgYIDwAAAA==.Blargg:BAAANQAECgIIAgAAAA==.Bloomhammer:BAAANQAECgEIAQAAAA==.Blooming:BAAANQAECgYIDwAAAA==.',
Bo='Booneboy:BAAANQAECgQIBwAAAA==.Botemedel:BAAANQAECgcIDQAAAA==.',
Br='Brennor:BAAANQAECgYIDwAAAA==.Brewslunt:BAAANQAECgcIEAABNQAFFAUICQACAFoRAA==.Bronamaly:BAAANQADCgMIAwAAAA==.',
Ca='Cabbagehunt:BAAANQADCgYJBgAAAA==.Caeden:BAAANQAECgUIDQAAAA==.Cairyan:BAAANQAECgcIEgAAAA==.Cassin:BAAANQADCgEIAQAAAA==.Castalia:BAAANQAECgQIBwAAAA==.Cattilina:BAAANQADCgcICAAAAA==.',
Ce='Celenara:BAABNQAECoEhAAMBAAkKLRtMVwCnAgABAAkKLRtMVwCnAgADAAIKIA68KgBhAAAAAA==.Celendil:BAAANQADCgUIBQABNQAECgkJIQABAC0bAA==.Celithe:BAAANQAECgIIAgAAAA==.',
Ch='Charmcaster:BAAANQAECgYIDQAAAA==.Charmstrike:BAAANQAECgIIAgAAAA==.Chedissa:BAAANQADCgQIBAAAAA==.Chleo:BAAANQAECgQIBgAAAA==.Choco:BAACNQAFFIEQAAIEAAYKTB7xAgAtAgAEAAYKTB7xAgAtAgA1AAQKgSYAAwQACQrOIY8HABADAAQACQrOIY8HABADAAUAAgobFr4qAIAAAAAA.Chocolat:BAAANQADCggICAABNQAFFAYIEAAEAEweAA==.Chudfox:BAAANQADCgEJAQAAAA==.',
Co='Coggler:BAAANQAECgIIAwAAAA==.Conqueror:BAAANQAECgMIAwABNQAECgYICwAGAAAAAA==.',
Cr='Creatlach:BAAANQAECgIIAgABNQAFFAUICQACAFoRAA==.Crotchpox:BAAANQADCgQIBAAAAA==.Crualti:BAAANQAECgUIDQAAAA==.',
Cu='Cupper:BAAANQABCgcJCQABNQAECgQIBwAGAAAAAA==.Curmudge:BAABNQAECoEbAAIHAAcKnhd1HgDiAQAHAAcKnhd1HgDiAQAAAA==.',
Da='Dalectra:BAAANQAECgQICAAAAA==.Darachane:BAAANQADCgcIJgAAAA==.Darkpriest:BAAANQAECgIIAgAAAA==.Darovan:BAAANQADCggJEAABNQAECgYIFgAIAMoeAA==.Darthnater:BAAANQAECgcICgAAAA==.Dauglow:BAAANQAECgYIDwAAAA==.',
De='Deathstars:BAAANQADCgYIBgAAAA==.Deboss:BAAANQADCggJDwAAAA==.Delritha:BAAANQAECgQICAAAAA==.Deltithrax:BAAANQAECgUIEAAAAA==.Demonagent:BAAANQAECgIIAwAAAA==.Desdh:BAABNQAECoEiAAIJAAgKER8HFwChAgAJAAgKER8HFwChAgAAAA==.Devious:BAAANQADCggICAABNQAECgYIDwAGAAAAAA==.',
Di='Dinö:BAAANQAECgMJBAABNQAECgQIDAAGAAAAAA==.',
Dm='Dmnslyer:BAAANQADCggIDQAAAA==.',
Do='Docspades:BAAANQAECgQICgAAAA==.Dornoch:BAAANQADCgYJDQAAAA==.',
Dr='Dramine:BAAANQADCgQJBwAAAA==.Draone:BAAANQAECgYIEAAAAA==.Dreabolic:BAAANQADCgYICwAAAA==.Dreamss:BAABNQAECoEaAAMKAAgK/wgOLQCYAQAKAAgK5wcOLQCYAQAJAAUKbAgeSwD9AAAAAA==.Drhkillinger:BAAANQADCgUIBwABNQAECgIIAwAGAAAAAA==.Drspades:BAAANQAECgEIAQAAAA==.',
['Dé']='Démetal:BAAANQADCggIDgAAAA==.',
Ei='Einherja:BAAANQAECgYIEwAAAA==.',
El='Elessaria:BAAANQAECgQIBwAAAA==.Elfatheàrt:BAAANQADCgYJDQAAAA==.Elidrus:BAAANQADCgYICgABNQAECgQIBgAGAAAAAA==.',
En='Enodlo:BAAANQADCgUIBQAAAA==.',
Er='Erora:BAAANQAECgYIEAAAAA==.',
Es='Estherras:BAAANQAECgUICAAAAA==.',
Fe='Feardotrun:BAAANQAECgUIDAAAAA==.Felicious:BAAANQADCgYJDQAAAA==.',
Fi='Finally:BAAANQADCgYJDQAAAA==.Firemage:BAABNQAECoEaAAMLAAgKbSIOQgBMAgALAAYKViIOQgBMAgAMAAQKiR43HwBjAQAAAA==.Fizzanelf:BAAANQADCgYICwAAAA==.',
Fl='Flokíe:BAAANQADCggICAAAAA==.',
Fo='Fortytwo:BAAANQAECgcIDAAAAA==.',
Fr='Freyá:BAAANQAECgEIAgAAAA==.Friendo:BAAANQAECgYIEAAAAA==.Frostbight:BAABNQAECoEfAAIBAAcKsxV5ogD0AQABAAcKsxV5ogD0AQAAAA==.Frostied:BAAANQAECgYICgAAAA==.',
Fu='Futnuraz:BAAANQADCgYJDQAAAA==.',
Fy='Fyrakkobama:BAAANQAECgYIBgAAAA==.Fyriat:BAAANQAECgUICAAAAA==.',
Ga='Galathel:BAAANQAECgYIDwAAAA==.Gazardiel:BAAANQAECgQJCgAAAA==.',
Ge='Gelinia:BAAANQAECgUICAAAAA==.Getafix:BAAANQADCggJCAABNQAECgYIDwAGAAAAAA==.',
Gi='Girthquakes:BAAANQAECgEIAQAAAA==.',
Gl='Glorbo:BAAANQAECgUICAAAAA==.',
Go='Goldstorm:BAAANQADCggIDgAAAA==.Goliath:BAAANQAECgUIEAAAAA==.',
Gr='Gregoron:BAAANQABCgYIBgAAAA==.Grimfelborn:BAABNQAECoEhAAMLAAkKCxr3MQCGAgALAAkKCxr3MQCGAgANAAEK9B0AHwBRAAAAAA==.Grondosh:BAAANQAECgIIAgAAAA==.Gryphindor:BAAANQAECgQIDgAAAA==.',
['Gì']='Gìorgìa:BAAANQABCgIJAwAAAA==.',
Ha='Hahwe:BAAANQADCgIIAgABNQAECgQIBgAGAAAAAA==.Haljo:BAAANQADCgQJBAAAAA==.Hanoverfiste:BAAANQAECgQIBwAAAA==.Hapsburg:BAAANQAECgYIDwAAAA==.Havince:BAAANQAECgYIDQAAAA==.Hawktuah:BAAANQAECgEIAQAAAA==.Haylee:BAAANQABCgIIAgAAAA==.',
He='Helle:BAAANQADCgUICAAAAA==.Hercboyy:BAABNQAECoEgAAMOAAgKZCNJEgAXAwAOAAcKgSZJEgAXAwAPAAEKwR/HSwBZAAAAAA==.',
Hi='Higgs:BAAANQADCggICQABNQAECgYIEQAGAAAAAA==.Higgspally:BAAANQAECgYIEQAAAA==.',
Ho='Holyball:BAAANQAECgUIDwAAAA==.Holytalon:BAAANQADCgIIAgAAAA==.',
Hu='Hughjahsol:BAAANQADCgIIAgAAAA==.Hukaru:BAAANQABCgIIAgABNQAECgYIDQAGAAAAAA==.Huulkster:BAAANQADCgQIBAAAAA==.',
Hy='Hydra:BAAANQAECgEJAQAAAA==.',
Il='Ilovehunter:BAAANQADCggJCAAAAA==.Ilyndra:BAAANQAECgUIEAAAAA==.',
In='Infernella:BAAANQADCgMIAwAAAA==.',
Ir='Ironskin:BAAANQAECgQIBgAAAA==.',
Is='Iselilja:BAAANQAECgUICAAAAA==.',
It='Ithea:BAABNQAECoEaAAIBAAkKYhUpdABgAgABAAkKYhUpdABgAgAAAA==.',
Ja='Jackshots:BAAANQADCgIIAgAAAA==.Jaeson:BAEANQAECgUICAAAAA==.Jakaro:BAABNQAECoEaAAMMAAgK7BNmJQAzAQALAAYKzxTEewCUAQAMAAUKgxFmJQAzAQAAAA==.',
Je='Jeefgpt:BAAANQAECgEIAQABNQAECgYIBgAGAAAAAA==.Jeefwrld:BAAANQAECgYICQAAAA==.Jeffers:BAAANQAECgEIAgABNQAECgYIBgAGAAAAAA==.Jeffha:BAAANQADCggICAAAAA==.',
Ji='Jiinx:BAAANQAECgUIEAAAAA==.',
Jo='Joejr:BAAANQAECgYIEAAAAA==.Jonald:BAAANQAECgcIEAAAAA==.',
Jt='Jtizlfrizl:BAAANQAECgQIBwAAAA==.',
Ju='Juniperz:BAAANQAECgUICAAAAA==.',
Jw='Jwise:BAAANQADCgQIBAAAAA==.',
Ka='Kaaydenn:BAAANQAECgQICgAAAA==.Kaghro:BAAANQADCgUIBQAAAA==.Kalaziel:BAAANQADCgMIAwAAAA==.Kalierix:BAAANQAECgYICAAAAA==.Kamus:BAAANQADCgcIBwAAAA==.Karawyn:BAAANQAECgEIAgABNQADCgQICAAGAAAAAA==.Katrichi:BAAANQAECgEIAQAAAA==.Katrishy:BAABNQAECoEhAAIQAAkKER7vDADvAgAQAAkKER7vDADvAgAAAA==.Kayde:BAAANQAECgQIBAAAAA==.',
Ke='Keedrid:BAAANQAECgYIDgAAAA==.Kelaeno:BAAANQAECgYIDgAAAA==.Kev:BAABNQAECoEgAAIOAAkKqiSWAgC5AwAOAAkKqiSWAgC5AwAAAA==.',
Ki='Kirmit:BAAANQAECgIIAQAAAA==.',
Kr='Kreeona:BAAANQAECgYIDgABNQAECgYIDwAGAAAAAA==.Kruàlty:BAABNQAECoEXAAMRAAgKwBOqCgAfAgARAAgKwBOqCgAfAgASAAMK9Qr8dgCWAAAAAA==.',
La='Laird:BAAANQADCgcICwAAAA==.',
Le='Legreecast:BAAANQADCgYJDQAAAA==.',
Li='Liare:BAACNQAFFIEMAAQMAAUKDSDyBQC8AAALAAIK5CI7GADNAAAMAAIKsSDyBQC8AAANAAEKFhk/BwBSAAA1AAQKgSUABAsACQpyJYgJAFwDAAsACQreI4gJAFwDAAwABgpWGDMZAJUBAA0AAgopJtsRANwAAAAA.Liasong:BAAANQADCgUJDgAAAA==.Litheliice:BAAANQAECgYIDwAAAA==.',
Lo='Lodur:BAAANQAECgUICAAAAA==.Lonen:BAAANQAECgIIBQAAAA==.Losat:BAAANQAECgYIDgAAAA==.',
['Lî']='Lîîght:BAAANQADCggIFgAAAA==.',
Ma='Machiato:BAAANQADCgYJCAAAAA==.Mackkie:BAAANQAECgUIDQAAAA==.Madonkadonk:BAAANQAECgYIDQAAAA==.Maedai:BAAANQAECgUIDgAAAA==.Maeli:BAAANQAECgEIAQAAAA==.Magladroth:BAAANQABCgQJBAAAAA==.Maldive:BAAANQAECgYJDQAAAA==.Maligasia:BAAANQADCgIJAwAAAA==.Mallicia:BAABNQAECoEjAAITAAgKKCL/EgAIAwATAAgKKCL/EgAIAwAAAA==.Mallistra:BAAANQAECgYIDAABNQAECggIIwATACgiAA==.Mallwizard:BAAANQAECgUJCgAAAA==.Martris:BAAANQAECgIIAwAAAA==.Maryjane:BAAANQAECgMJAwAAAA==.Massoflice:BAAANQAECgYICwAAAA==.Maxblaide:BAAANQADCggIGAAAAA==.',
Me='Melovania:BAAANQADCgIIAgAAAA==.',
Mi='Miami:BAAANQAECgMIBAABNQAFFAYIFAAFAEYZAA==.Milah:BAAANQABCgIIAgAAAA==.Missile:BAAANQAECgMIAwAAAA==.Misstangy:BAAANQADCgcIFwAAAA==.',
Mo='Moct:BAAANQAECgYIEAAAAA==.Monikal:BAAANQADCgEIAQAAAA==.',
Mu='Musashi:BAABNQAECoEkAAIUAAgK3yTeDwA/AwAUAAgK3yTeDwA/AwABNQAECgkJGwAUAFUmAA==.Muskeg:BAAANQAECgYIDwAAAA==.Mustardhunt:BAAANQADCgYICgAAAA==.',
['Mü']='Münchkiné:BAAANQABCggIEgAAAA==.',
Na='Namanari:BAAANQABCgIJAgAAAA==.Naris:BAAANQAECgQIBgAAAA==.',
Ne='Necrochade:BAAANQAECgEIAQAAAA==.Neptune:BAAANQAECgcIEwAAAA==.',
Ni='Nightstew:BAAANQADCgcICgAAAA==.Nishal:BAAANQADCggIGAAAAA==.',
Ny='Nyxaries:BAAANQAECgEJAQAAAA==.',
['Né']='Néwby:BAABNQAECoEfAAIVAAgKux/+BQDYAgAVAAgKux/+BQDYAgAAAA==.',
Op='Opalynn:BAAANQAECgEIAQAAAA==.Ophirra:BAAANQABCgYIDgAAAA==.',
Oz='Ozempic:BAAANQAECgQIBAABNQAFFAYIEAAEAEweAA==.',
Pa='Pablo:BAAANQAECgYICQAAAA==.Patriot:BAAANQADCgUICAAAAA==.Pawinurbutt:BAAANQADCgQIBAAAAA==.',
Pe='Peppert:BAAANQAECgUIBAAAAA==.',
Ph='Phane:BAAANQAECgQIBwAAAA==.',
Pu='Puffer:BAAANQAECgQICQAAAA==.',
Px='Pxry:BAAANQAECgQIBAAAAA==.',
Ra='Rabone:BAAANQADCgIJAgAAAA==.Raevyn:BAAANQADCgYIBgAAAA==.Raito:BAAANQAECgQIBgAAAA==.Rakshasa:BAABNQAECoEfAAMLAAgKyR2hNQB4AgALAAcKIR+hNQB4AgAMAAMK3w/KPgCyAAAAAA==.Rano:BAAANQADCgUIBgAAAA==.Rasetsungo:BAAANQAECgYIDgAAAA==.Raura:BAAANQADCgYJDQAAAA==.',
Re='Redblueblurr:BAAANQAECgQIAwAAAA==.Remi:BAAANQAECgYIEQAAAA==.Rev:BAAANQADCgUIBQAAAA==.Reveillark:BAAANQAECgIIAgAAAA==.',
Ri='Rise:BAAANQADCgYIBgAAAA==.',
Ro='Rolan:BAABNQAECoEfAAQWAAgKvSXjEwDlAgAWAAgKJCTjEwDlAgAXAAYKESXeGAB7AgAIAAQKVCQvSgCLAQAAAA==.Rosalian:BAAANQAECgUICAAAAA==.Rotiko:BAAANQAECgQICAAAAA==.Roweene:BAAANQAECgUIEAAAAA==.',
['Rá']='Rágnar:BAAANQAECgQIDgAAAA==.',
Sa='Sabiel:BAAANQAECgQIBgAAAA==.Sakuta:BAAANQADCgYIBgABNQAECgkJGwACAMwdAA==.',
Se='Serenatee:BAAANQAECgUIDAAAAA==.',
Sh='Shaedai:BAAANQAECgEIAQAAAA==.Shagohod:BAAANQADCgQIBAAAAA==.Shakked:BAAANQAECgEIAQAAAA==.',
Sk='Skotojar:BAAANQADCgUIBQAAAA==.',
Sn='Snortedgfuel:BAAANQAECgcIEQAAAA==.',
So='Solphera:BAAANQADCgQICAAAAA==.Sonknight:BAAANQADCggIJAAAAA==.',
Sp='Speedshot:BAAANQADCgUIBgAAAA==.Spitefulcrow:BAABNQAECoEXAAIYAAcKxAkzBwCtAQAYAAcKxAkzBwCtAQAAAA==.',
St='Stardstr:BAAANQADCgMIAwAAAA==.Sto:BAAANQAECgEIAgAAAA==.',
Su='Sufferding:BAAANQAECgUICgAAAA==.Suria:BAAANQAECgYIEAAAAA==.',
Sy='Syker:BAAANQADCgIIAgAAAA==.',
Ta='Tahrovin:BAAANQAECgEIAQAAAA==.Taytorchips:BAAANQAECgYIDgAAAA==.',
Th='Thaendrin:BAAANQADCgYICQAAAA==.Thearcane:BAAANQADCgQIBwAAAA==.Thedoc:BAAANQAECgUIBAAAAA==.Theefjeef:BAAANQAECgQIBQABNQAECgYIBgAGAAAAAA==.Thorloim:BAAANQAECgUIEAAAAA==.Thornx:BAAANQADCgEIAQAAAA==.Thundercups:BAAANQAECgYIDAAAAA==.',
Ti='Tigerstarr:BAAANQAECggIDQAAAA==.Tinyshieva:BAAANQADCgQIBAAAAA==.Tizuki:BAAANQAECgQIBAAAAA==.',
To='Tonystandard:BAAANQAECgUICQABNQAECgkJLAAZAPofAA==.',
Tr='Treborlock:BAAANQAECgUIDQAAAA==.Triplock:BAAANQAECgEJAQAAAA==.Trolcain:BAAANQAECggIEgAAAA==.',
Tw='Twistedspork:BAAANQADCgcIFwAAAA==.',
Un='Unbuffed:BAAANQADCgIIAgABNQAECgYIEQAGAAAAAA==.',
Va='Vaedar:BAAANQAECgEIAQAAAA==.Vagglord:BAAANQAECgQIDwAAAA==.Valha:BAAANQAECgYICwAAAA==.Vardisk:BAAANQADCgQIBAAAAA==.Varteras:BAAANQAECgYIDgAAAA==.',
Ve='Vellron:BAAANQAECgYIEAAAAA==.Veroque:BAAANQADCgUIBQAAAA==.',
['Vø']='Vødøu:BAAANQAECgQICgAAAA==.',
Wa='Wafflelegend:BAABNQAECoEdAAIJAAgKoSPLCQA9AwAJAAgKoSPLCQA9AwAAAA==.Wardkbriggle:BAABNQAECoEXAAMXAAkKGxxvIgAmAgAXAAkKgBlvIgAmAgAWAAgK6xjEOwDOAQAAAA==.Warint:BAAANQAECgQIBgAAAA==.',
We='Weeble:BAAANQADCgMIAwAAAA==.Welish:BAAANQABCgEIAQAAAA==.',
Wi='Wifi:BAAANQAECgYICwAAAA==.',
Wo='Wolfdude:BAAANQAECggICQAAAA==.',
Wy='Wydge:BAAANQAECgUIDwAAAA==.Wyven:BAABNQAECoEZAAIWAAgKiCMpEwDrAgAWAAgKiCMpEwDrAgABNQADCgcICgAGAAAAAA==.',
Xa='Xanddoria:BAAANQAECgYIEQAAAA==.Xaoc:BAAANQAECgUIDgAAAA==.',
Xh='Xhared:BAABNQAECoEWAAIIAAYKyh53LAApAgAIAAYKyh53LAApAgAAAA==.',
Xo='Xochital:BAAANQADCgEIAQAAAA==.',
Ze='Zephy:BAAANQAECgQIBwAAAA==.',
['Åe']='Åeon:BAAANQAECgMIAwAAAA==.',
['Ðr']='Ðráco:BAAANQADCgYIBgAAAA==.',
['ßu']='ßullzeye:BAAANQADCgcIBwAAAA==.',
['Ÿu']='Ÿunalessca:BAAANQAECgYICwAAAA==.',
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
