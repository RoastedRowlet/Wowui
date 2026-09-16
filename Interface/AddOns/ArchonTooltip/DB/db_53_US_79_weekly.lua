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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','DemonHunter-Havoc','Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaronius:BAAANQAECgQIBwAAAA==.',
Ac='Acceptance:BAAANQADCgYICAAAAA==.',
Ad='Adoe:BAAANQAECgEIAQAAAA==.Adora:BAAANQAECgMIAwAAAA==.',
Ag='Agaliarept:BAAANQADCgMIAwAAAA==.Agathos:BAAANQADCgUIBwAAAA==.',
Ai='Aidenator:BAAANQAECgEIAQAAAA==.',
Al='Aluni:BAAANQADCgEIAQAAAA==.',
Am='Ammastin:BAAANQABCgMIAwAAAA==.',
An='Andorix:BAAANQADCgEIAQAAAA==.Andretta:BAAANQADCggIDgAAAA==.Angelneko:BAAANQAECgQIBwAAAA==.',
At='Atetoomuch:BAAANQABCgYIBgAAAA==.Atthis:BAAANQADCgEIAQAAAA==.',
Au='Auroraa:BAAANQAECgEIAQAAAA==.',
Av='Avalectra:BAAANQAECgEIAQAAAA==.',
Az='Azmodeaz:BAAANQAECgQIEAAAAA==.Aztrik:BAAANQAECgQIBwAAAA==.',
Ba='Badmooddude:BAAANQADCgcICAAAAA==.Bajapanti:BAAANQAECgQIBgAAAA==.Ballyhøø:BAAANQAECgYICQAAAA==.Baxstab:BAAANQAECgIIBAAAAA==.',
Be='Belladeon:BAAANQAECgUIBQAAAA==.',
Bl='Blackpatch:BAAANQAECgQIBwAAAA==.Blaqkid:BAAANQADCgYIBgAAAA==.Blaqsun:BAAANQAECgIIAwAAAA==.Bloomhammer:BAAANQAECgEIAQAAAA==.Blooming:BAAANQAECgMIBAAAAA==.',
Bo='Booneboy:BAAANQADCggIDwAAAA==.Botemedel:BAAANQAECgEIAQABNQAECgcIDgABAAAAAA==.',
Br='Brennor:BAAANQAECgIIBAAAAA==.Brewslunt:BAAANQAECgUICwABNQAECgkJIAACAPEhAA==.',
Ca='Caeden:BAAANQAECgMIBQAAAA==.Cairyan:BAAANQAECgQIBgAAAA==.Castalia:BAAANQADCggIDwAAAA==.',
Ce='Celenara:BAAANQAECgcIEgAAAA==.Celendil:BAAANQADCgUIBQABNQAECgcIEgABAAAAAA==.',
Ch='Charmcaster:BAAANQAECgEIAgAAAA==.Charmstrike:BAAANQAECgIIAgAAAA==.Chedissa:BAAANQADCgQIBAAAAA==.Chleo:BAAANQADCgEIAQAAAA==.Choco:BAACNQAFFIEFAAIDAAQJsRFHBABRAQADAAQJsRFHBABRAQA1AAQKgR4AAwMACQnOIUMEAC8DAAMACQnOIUMEAC8DAAQAAQngFM8mAEAAAAAA.Chocolat:BAAANQADCggICAABNQAFFAQIBQADALERAA==.',
Co='Coggler:BAAANQADCggIFAAAAA==.Conqueror:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.',
Cr='Creatlach:BAAANQADCgYIBgABNQAECgkJIAACAPEhAA==.Crotchpox:BAAANQADCgQIBAAAAA==.Crualti:BAAANQAECgQIBAAAAA==.',
Cu='Cupper:BAAANQABCgcICQABNQADCggIGgABAAAAAA==.Curmudge:BAAANQAECgYICwAAAA==.',
Da='Dalectra:BAAANQAECgIIAgAAAA==.Darachane:BAAANQADCgYIFAAAAA==.Darkpriest:BAAANQAECgIIAgAAAA==.Darthnater:BAAANQADCgUIBQAAAA==.Dauglow:BAAANQAECgIIBAAAAA==.',
De='Deathstars:BAAANQABCgYICQAAAA==.Deboss:BAAANQADCggICAAAAA==.Delritha:BAAANQAECgQICAAAAA==.Deltithrax:BAAANQAECgQIBwAAAA==.Demonagent:BAAANQADCggIGgAAAA==.Desdh:BAABNQAECoEbAAIFAAgJkB6bCwDTAgAFAAgJkB6bCwDTAgAAAA==.',
Di='Dinö:BAAANQAECgEIAgABNQAECgQIBAABAAAAAA==.',
Dm='Dmnslyer:BAAANQADCggIDQAAAA==.',
Do='Docspades:BAAANQAECgQIBwAAAA==.Dornoch:BAAANQADCgUIBwAAAA==.',
Dr='Dramine:BAAANQADCgMIAwAAAA==.Draone:BAAANQAECgQIBwAAAA==.Dreabolic:BAAANQADCgYICwAAAA==.Dreamss:BAAANQAECgcICwAAAA==.Drhkillinger:BAAANQADCgUIBQABNQADCggIGgABAAAAAA==.Drspades:BAAANQAECgEIAQAAAA==.',
['Dé']='Démetal:BAAANQADCggIDgAAAA==.',
Ei='Einherja:BAAANQAECgQICAAAAA==.',
El='Elessaria:BAAANQADCggIGgAAAA==.Elfatheàrt:BAAANQADCgUIBwAAAA==.Elidrus:BAAANQADCgYICgABNQAECgQIBQABAAAAAA==.',
En='Enodlo:BAAANQADCgUIBQAAAA==.',
Er='Erora:BAAANQAECgIIBAAAAA==.',
Es='Estherras:BAAANQAECgEIAQAAAA==.',
Fe='Feardotrun:BAAANQAECgIIAwAAAA==.Felicious:BAAANQADCgUIBwAAAA==.',
Fi='Finally:BAAANQADCgUIBwAAAA==.Firemage:BAAANQAECgcIDAAAAA==.Fizzanelf:BAAANQADCgUIBQAAAA==.',
Fl='Flokíe:BAAANQADCggICAAAAA==.',
Fo='Fortytwo:BAAANQAECgIIAwAAAA==.',
Fr='Freyá:BAAANQAECgEIAgAAAA==.Friendo:BAAANQAECgQIBwAAAA==.Frostbight:BAAANQAECgcIEQAAAA==.Frostied:BAAANQAECgQIBQAAAA==.',
Fu='Futnuraz:BAAANQADCgUIBwAAAA==.',
Fy='Fyrakkobama:BAAANQAECgYIBgAAAA==.Fyriat:BAAANQAECgEIAQAAAA==.',
Ga='Galathel:BAAANQAECgMIBAAAAA==.Gazardiel:BAAANQAECgQIBgAAAA==.',
Ge='Gelinia:BAAANQAECgEIAQAAAA==.',
Gi='Girthquakes:BAAANQAECgEIAQAAAA==.',
Gl='Glorbo:BAAANQAECgEIAQAAAA==.',
Go='Goliath:BAAANQAECgQIBgAAAA==.',
Gr='Gregoron:BAAANQABCgYIBgAAAA==.Grimfelborn:BAAANQAECgcIEgAAAA==.Grondosh:BAAANQADCggIGgAAAA==.Gryphindor:BAAANQAECgQIBwAAAA==.',
['Gì']='Gìorgìa:BAAANQABCgIIAwAAAA==.',
Ha='Hahwe:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Hanoverfiste:BAAANQADCggIGgAAAA==.Hapsburg:BAAANQAECgIIBAAAAA==.Havince:BAAANQAECgEIAgAAAA==.Hawktuah:BAAANQAECgEIAQAAAA==.Haylee:BAAANQABCgIIAgAAAA==.',
He='Helle:BAAANQADCgIIAgAAAA==.Hercboyy:BAAANQAECgcIEQAAAA==.',
Hi='Higgs:BAAANQADCggICAABNQAECgUICwABAAAAAA==.Higgspally:BAAANQAECgUICwAAAA==.',
Ho='Holyball:BAAANQAECgQIBwAAAA==.',
Hu='Hughjahsol:BAAANQADCgIIAgAAAA==.Hukaru:BAAANQABCgIIAgABNQAECgEIAgABAAAAAA==.Huulkster:BAAANQADCgQIBAAAAA==.',
Hy='Hydra:BAAANQADCgIIAgAAAA==.',
Il='Ilyndra:BAAANQAECgQIBwAAAA==.',
In='Infernella:BAAANQADCgMIAwAAAA==.',
Ir='Ironskin:BAAANQADCgUIBQAAAA==.',
Is='Iselilja:BAAANQAECgEIAQAAAA==.',
It='Ithea:BAAANQAECggIBgAAAA==.',
Ja='Jackshots:BAAANQADCgIIAgAAAA==.Jaeson:BAEANQAECgEIAwAAAA==.Jakaro:BAAANQAECggIEwAAAA==.',
Je='Jeef:BAAANQADCgcICQABNQAECgYIBgABAAAAAA==.Jeefwrld:BAAANQAECgYIBgAAAA==.',
Ji='Jiinx:BAAANQAECgQIBwAAAA==.',
Jo='Joejr:BAAANQAECgQIBwAAAA==.Jonald:BAAANQAECgYICQAAAA==.',
Jt='Jtizlfrizl:BAAANQADCggIGgAAAA==.',
Ju='Juniperz:BAAANQAECgEIAQAAAA==.',
Jw='Jwise:BAAANQADCgQIBAAAAA==.',
Ka='Kaaydenn:BAAANQAECgIIAwAAAA==.Kalaziel:BAAANQADCgMIAwAAAA==.Kalierix:BAAANQADCgUIBQAAAA==.Kamus:BAAANQABCgQIBwAAAA==.Karawyn:BAAANQAECgEIAQABNQADCgQICAABAAAAAA==.Katrichi:BAAANQAECgEIAQAAAA==.Katrishy:BAAANQAECgcIEgAAAA==.',
Ke='Keedrid:BAAANQAECgQICAAAAA==.Kelaeno:BAAANQAECgIIBQAAAA==.Kev:BAABNQAECoEaAAIGAAkJqiTzAADNAwAGAAkJqiTzAADNAwAAAA==.',
Ki='Kirmit:BAAANQAECgIIAQAAAA==.',
Kn='Knoll:BAAANQADCggICQAAAA==.',
Kr='Kreeona:BAAANQAECgIIBQABNQAECgMIBAABAAAAAA==.Kruàlty:BAAANQAECgUICAAAAA==.',
La='Laird:BAAANQADCgcICwAAAA==.',
Le='Legreecast:BAAANQADCgUIBwAAAA==.',
Li='Liare:BAABNQAECoEdAAQHAAkJcyIlFADAAgAHAAgJFiElFADAAgAIAAYJVhgvEwC0AQAJAAIJKSZYCwDjAAAAAA==.Liasong:BAAANQADCgUICQAAAA==.Litheliice:BAAANQAECgIIBAAAAA==.',
Lo='Lodur:BAAANQAECgEIAQAAAA==.Lonen:BAAANQAECgEIAQAAAA==.Losat:BAAANQAECgQIBQAAAA==.',
['Lî']='Lîîght:BAAANQADCgYIBgAAAA==.',
Ma='Machiato:BAAANQADCgQIAgAAAA==.Mackkie:BAAANQAECgQIBAAAAA==.Madonkadonk:BAAANQAECgIIAgAAAA==.Maedai:BAAANQAECgIIBAAAAA==.Maeli:BAAANQADCgUIBgAAAA==.Maldive:BAAANQAECgQIBwAAAA==.Maligasia:BAAANQADCgIIAwAAAA==.Mallicia:BAAANQAECgcIEAAAAA==.Mallistra:BAAANQAECgIIAwABNQAECgcIEAABAAAAAA==.Mallwizard:BAAANQAECgUICgAAAA==.Martris:BAAANQADCggIGAAAAA==.Maryjane:BAAANQAECgMIAwAAAA==.Massoflice:BAAANQAECgYICgAAAA==.Maxblaide:BAAANQADCggIGAAAAA==.',
Me='Melovania:BAAANQADCgIIAgAAAA==.',
Mi='Miami:BAAANQAECgEIAQAAAA==.Misstangy:BAAANQADCgcIEQAAAA==.',
Mo='Moct:BAAANQAECgQIBwAAAA==.',
Mu='Musashi:BAAANQAECggIEgABNQAECgkJFwAKAFUmAA==.Muskeg:BAAANQAECgMIBAAAAA==.Mustardhunt:BAAANQADCgYICgAAAA==.',
Na='Namanari:BAAANQABCgIIAgAAAA==.Naris:BAAANQAECgQIBQAAAA==.',
Ne='Necrochade:BAAANQAECgEIAQAAAA==.Neptune:BAAANQAECgQIBgAAAA==.',
Ni='Nightstew:BAAANQADCgYICAAAAA==.Nishal:BAAANQADCgcIDQAAAA==.',
Ny='Nyxaries:BAAANQADCggIGgAAAA==.',
['Né']='Néwby:BAAANQAECgYIEAAAAA==.',
Op='Opalynn:BAAANQAECgEIAQAAAA==.Ophirra:BAAANQABCgYIDgAAAA==.',
Oz='Ozempic:BAAANQAECgQIBAABNQAFFAQIBQADALERAA==.',
Pa='Pablo:BAAANQAECgMIAwAAAA==.Patriot:BAAANQADCgUIBwAAAA==.Pawinurbutt:BAAANQADCgQIBAAAAA==.',
Pe='Peppert:BAAANQADCggICAAAAA==.',
Pu='Puffer:BAAANQAECgIIAgAAAA==.',
Px='Pxry:BAAANQAECgQIBAAAAA==.',
Ra='Rabone:BAAANQADCgIIAgAAAA==.Raevyn:BAAANQADCgYIBgAAAA==.Raito:BAAANQAECgMIAwAAAA==.Rakshasa:BAAANQAECgYIEAAAAA==.Rano:BAAANQADCgUIBgAAAA==.Rasetsungo:BAAANQAECgQIBQAAAA==.Raura:BAAANQADCgUIBwAAAA==.',
Re='Redblueblurr:BAAANQADCggIHwAAAA==.Remi:BAAANQAECgYICwAAAA==.Reveillark:BAAANQAECgIIAgAAAA==.',
Ro='Rolan:BAABNQAECoEWAAQLAAcJBiVoEADVAgALAAcJvSNoEADVAgAMAAQJqiOTMwCRAQANAAEJ4CPeQwBoAAAAAA==.Rosalian:BAAANQAECgEIAQAAAA==.Rotiko:BAAANQAECgIIAgAAAA==.Roweene:BAAANQAECgQIBwAAAA==.',
['Rá']='Rágnar:BAAANQAECgMIBgAAAA==.',
Sa='Sabiel:BAAANQAECgIIAgAAAA==.Sakuta:BAAANQADCgYIBgABNQAECgQICgABAAAAAA==.',
Se='Serenatee:BAAANQAECgEIAwAAAA==.',
Sh='Shakked:BAAANQADCgcIFAAAAA==.',
Sk='Skotojar:BAAANQADCgUIBQAAAA==.',
Sn='Snortedgfuel:BAAANQAECgYICAAAAA==.',
So='Solphera:BAAANQADCgQICAAAAA==.Sonknight:BAAANQADCggIHAAAAA==.',
Sp='Speedshot:BAAANQADCgUIBgAAAA==.Spitefulcrow:BAAANQAECgUICQAAAA==.',
St='Stardstr:BAAANQADCgMIAwAAAA==.Sto:BAAANQAECgEIAQAAAA==.',
Su='Sufferding:BAAANQAECgQIBQAAAA==.Suria:BAAANQAECgQIBwAAAA==.',
Sy='Syker:BAAANQADCgIIAgAAAA==.',
Ta='Tahrovin:BAAANQADCgYIBwAAAA==.Taytorchips:BAAANQAECgIIBQAAAA==.',
Th='Thaendrin:BAAANQADCgYICQAAAA==.Thearcane:BAAANQADCgQIBwAAAA==.Theefjeef:BAAANQAECgMIBAABNQAECgYIBgABAAAAAA==.Thorloim:BAAANQAECgQIBwAAAA==.Thornx:BAAANQADCgEIAQAAAA==.Thundercups:BAAANQAECgIIAwAAAA==.',
Ti='Tigerstarr:BAAANQAECgYICgAAAA==.Tinyshieva:BAAANQADCgQIBAAAAA==.',
To='Tonystandard:BAAANQADCgcIBwAAAA==.',
Tr='Treborlock:BAAANQAECgQIBQAAAA==.Triplock:BAAANQADCggICAAAAA==.Trolcain:BAAANQAECgQIBwAAAA==.',
Tw='Twistedspork:BAAANQADCgUICgAAAA==.',
Un='Unbuffed:BAAANQABCgIIAwABNQAECgUICwABAAAAAA==.',
Va='Vaedar:BAAANQAECgEIAQAAAA==.Vagglord:BAAANQAECgQICwAAAA==.Valha:BAAANQAECgEIAQAAAA==.Vardisk:BAAANQADCgQIBAAAAA==.Varteras:BAAANQAECgIIAwAAAA==.',
Ve='Vellron:BAAANQAECgQIBwAAAA==.',
['Vø']='Vødøu:BAAANQAECgIIAwAAAA==.',
Wa='Wafflelegend:BAAANQAECgYIDwABNQAECgcICwABAAAAAA==.Wardkbriggle:BAABNQAECoEXAAMNAAkJGxxRDQB8AgANAAkJgBlRDQB8AgALAAgJ6xgnIQAwAgAAAA==.Warint:BAAANQAECgQIBgAAAA==.',
We='Weeble:BAAANQADCgMIAwAAAA==.Welish:BAAANQABCgEIAQAAAA==.',
Wi='Wifi:BAAANQAECgEIAQAAAA==.',
Wo='Wolfdude:BAAANQAECggIBAAAAA==.',
Wy='Wydge:BAAANQAECgMIBgAAAA==.Wyven:BAAANQAECgUICgABNQADCgcICgABAAAAAA==.',
Xa='Xanddoria:BAAANQAECgQICAAAAA==.Xaoc:BAAANQAECgQIBgAAAA==.',
Xh='Xhared:BAAANQAECgQICgAAAA==.',
Xo='Xochital:BAAANQADCgEIAQAAAA==.',
Ze='Zephy:BAAANQADCggIEwAAAA==.',
['Åe']='Åeon:BAAANQADCgcIFwAAAA==.',
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
