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

local lookup = {'Mage-Arcane','Unknown-Unknown','Shaman-Restoration','Mage-Frost','Evoker-Preservation','Evoker-Devastation','DemonHunter-Havoc','Warlock-Demonology','Warlock-Affliction','Paladin-Holy','Warlock-Destruction','Priest-Shadow','Priest-Holy','Hunter-BeastMastery','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Monk-Mistweaver',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaronius:BAAANQAECgUIDAAAAA==.',
Ac='Acceptance:BAAANQADCgYICAAAAA==.',
Ad='Adoe:BAAANQAECgIIAwAAAA==.Adora:BAAANQAECgMJBQAAAA==.',
Ag='Agaliarept:BAAANQADCgMIAwAAAA==.Agathos:BAAANQADCgYJDQAAAA==.',
Ai='Aidenator:BAAANQAECgIIAwAAAA==.',
Al='Aluni:BAAANQADCgEIAQAAAA==.',
Am='Ammastin:BAAANQABCgMIAwAAAA==.',
An='Andorix:BAAANQADCgEIAQAAAA==.Andretta:BAAANQADCggIDgAAAA==.Angelneko:BAAANQAECgUIDAAAAA==.',
Ar='Arinthian:BAAANQABCgQJBAAAAA==.Artrian:BAAANQADCggJCAAAAA==.',
At='Atetoomuch:BAAANQABCgYIBgAAAA==.Atthis:BAAANQADCgEIAQAAAA==.',
Au='Auroraa:BAAANQAECgQJBQAAAA==.',
Av='Avalectra:BAAANQAECgEIAQAAAA==.',
Az='Azmodeaz:BAABNQAECoEWAAIBAAUKegug6QAwAQABAAUKegug6QAwAQAAAA==.Aztrik:BAAANQAECgUJDAAAAA==.',
Ba='Bajapanti:BAAANQAECgYJDAAAAA==.Ballyhøø:BAAANQAECgYICQAAAA==.Baxstab:BAAANQAECgUICQAAAA==.',
Be='Belladeon:BAAANQAECgYJCwAAAA==.',
Bl='Blackpatch:BAAANQAECgYJDQAAAA==.Blaqkid:BAAANQADCgYIBgAAAA==.Blaqsun:BAAANQAECgMIBgAAAA==.Bloomhammer:BAAANQAECgEIAQAAAA==.Blooming:BAAANQAECgUICQAAAA==.',
Bo='Booneboy:BAAANQAECgMJAwAAAA==.Botemedel:BAAANQAECgUJBgABNQAECgcIEgACAAAAAA==.',
Br='Brennor:BAAANQAECgUICQAAAA==.Brewslunt:BAAANQAECgUICwABNQAECgkJJAADAJAiAA==.',
Ca='Cabbagehunt:BAAANQADCgYJBgAAAA==.Caeden:BAAANQAECgUICAAAAA==.Cairyan:BAAANQAECgUJCwAAAA==.Castalia:BAAANQAECgMJAwAAAA==.',
Ce='Celenara:BAABNQAECoEdAAMBAAgKnhsaXQB2AgABAAgKnhsaXQB2AgAEAAIKIA7TIgBnAAAAAA==.Celendil:BAAANQADCgUIBQABNQAECggIHQABAJ4bAA==.',
Ch='Charmcaster:BAAANQAECgUIBwAAAA==.Charmstrike:BAAANQAECgIIAgAAAA==.Chedissa:BAAANQADCgQIBAAAAA==.Chleo:BAAANQAECgIJAgAAAA==.Choco:BAACNQAFFIEKAAIFAAUKVhrIAwDGAQAFAAUKVhrIAwDGAQA1AAQKgSMAAwUACQrOIRoGABwDAAUACQrOIRoGABwDAAYAAgobFgQmAIcAAAAA.Chocolat:BAAANQADCggICAABNQAFFAUICgAFAFYaAA==.Chudfox:BAAANQADCgEJAQAAAA==.',
Co='Coggler:BAAANQAECgEJAQAAAA==.Conqueror:BAAANQADCgUIBQABNQAECgQIBQACAAAAAA==.',
Cr='Creatlach:BAAANQADCgYJBgABNQAECgkJJAADAJAiAA==.Crotchpox:BAAANQADCgQIBAAAAA==.Crualti:BAAANQAECgUICQAAAA==.',
Cu='Cupper:BAAANQABCgcJCQABNQAECgMJAwACAAAAAA==.Curmudge:BAAANQAECgYJEQAAAA==.',
Da='Dalectra:BAAANQAECgMIBAAAAA==.Darachane:BAAANQADCgcJIQAAAA==.Darkpriest:BAAANQAECgIIAgAAAA==.Darovan:BAAANQADCggJEAABNQAECgUJEAACAAAAAA==.Darthnater:BAAANQAECgcIBwAAAA==.Dauglow:BAAANQAECgUICQAAAA==.',
De='Deathstars:BAAANQADCgYJBgAAAA==.Deboss:BAAANQADCggJDwAAAA==.Delritha:BAAANQAECgQICAAAAA==.Deltithrax:BAAANQAECgUIDAAAAA==.Demonagent:BAAANQAECgEJAQAAAA==.Desdh:BAABNQAECoEfAAIHAAgK7B5gEQC7AgAHAAgK7B5gEQC7AgAAAA==.Devious:BAAANQADCggJCAABNQAECgUICQACAAAAAA==.',
Di='Dinö:BAAANQAECgMJBAABNQAECgQJCAACAAAAAA==.',
Dm='Dmnslyer:BAAANQADCggIDQAAAA==.',
Do='Docspades:BAAANQAECgQICgAAAA==.Dornoch:BAAANQADCgYJDQAAAA==.',
Dr='Dramine:BAAANQADCgQJBwAAAA==.Draone:BAAANQAECgYJDQAAAA==.Dreabolic:BAAANQADCgYICwAAAA==.Dreamss:BAAANQAECgcIDgAAAA==.Drhkillinger:BAAANQADCgUIBQABNQAECgEJAQACAAAAAA==.Drspades:BAAANQAECgEIAQAAAA==.',
['Dé']='Démetal:BAAANQADCggIDgAAAA==.',
Ei='Einherja:BAAANQAECgUJDQAAAA==.',
El='Elessaria:BAAANQAECgMJAwAAAA==.Elfatheàrt:BAAANQADCgYJDQAAAA==.Elidrus:BAAANQADCgYICgABNQAECgQIBgACAAAAAA==.',
En='Enodlo:BAAANQADCgUIBQAAAA==.',
Er='Erora:BAAANQAECgYJCgAAAA==.',
Es='Estherras:BAAANQAECgIIAwAAAA==.',
Fe='Feardotrun:BAAANQAECgUICAAAAA==.Felicious:BAAANQADCgYJDQAAAA==.',
Fi='Finally:BAAANQADCgYJDQAAAA==.Firemage:BAAANQAECgcIDQAAAA==.Fizzanelf:BAAANQADCgYICwAAAA==.',
Fl='Flokíe:BAAANQADCggICAAAAA==.',
Fo='Fortytwo:BAAANQAECgcJCgAAAA==.',
Fr='Freyá:BAAANQAECgEIAgAAAA==.Friendo:BAAANQAECgYJDQAAAA==.Frostbight:BAABNQAECoEYAAIBAAcKKRPbjQD1AQABAAcKKRPbjQD1AQAAAA==.Frostied:BAAANQAECgYJCAAAAA==.',
Fu='Futnuraz:BAAANQADCgYJDQAAAA==.',
Fy='Fyrakkobama:BAAANQAECgYIBgAAAA==.Fyriat:BAAANQAECgIIAwAAAA==.',
Ga='Galathel:BAAANQAECgUICQABNQAECgYJCwACAAAAAA==.Gazardiel:BAAANQAECgQJCgAAAA==.',
Ge='Gelinia:BAAANQAECgIIAwAAAA==.Getafix:BAAANQADCggJCAABNQAECgYJCwACAAAAAA==.',
Gi='Girthquakes:BAAANQAECgEIAQAAAA==.',
Gl='Glorbo:BAAANQAECgIIAwAAAA==.',
Go='Goldstorm:BAAANQADCgYJBgAAAA==.Goliath:BAAANQAECgUICwAAAA==.',
Gr='Gregoron:BAAANQABCgYIBgAAAA==.Grimfelborn:BAABNQAECoEdAAMIAAgKThtKMQBZAgAIAAgKThtKMQBZAgAJAAEK9B0sGgBTAAAAAA==.Grondosh:BAAANQADCggJIgAAAA==.Gryphindor:BAAANQAECgQJCwAAAA==.',
['Gì']='Gìorgìa:BAAANQABCgIJAwAAAA==.',
Ha='Hahwe:BAAANQADCgIIAgABNQAECgQIBgACAAAAAA==.Haljo:BAAANQADCgQJBAAAAA==.Hanoverfiste:BAAANQAECgMJAwAAAA==.Hapsburg:BAAANQAECgUICQAAAA==.Havince:BAAANQAECgUIBwAAAA==.Hawktuah:BAAANQAECgEIAQAAAA==.Haylee:BAAANQABCgIIAgAAAA==.',
He='Helle:BAAANQADCgQJBAAAAA==.Hercboyy:BAABNQAECoEYAAIKAAcKAiWQEQD/AgAKAAcKAiWQEQD/AgAAAA==.',
Hi='Higgs:BAAANQADCggJCAABNQAECgUIEAACAAAAAA==.Higgspally:BAAANQAECgUIEAAAAA==.',
Ho='Holyball:BAAANQAECgUJDAAAAA==.',
Hu='Hughjahsol:BAAANQADCgIIAgAAAA==.Hukaru:BAAANQABCgIIAgABNQAECgUIBwACAAAAAA==.Huulkster:BAAANQADCgQIBAAAAA==.',
Hy='Hydra:BAAANQAECgEJAQAAAA==.',
Il='Ilovehunter:BAAANQADCggJCAAAAA==.Ilyndra:BAAANQAECgUIDAAAAA==.',
In='Infernella:BAAANQADCgMIAwAAAA==.',
Ir='Ironskin:BAAANQAECgIIAgAAAA==.',
Is='Iselilja:BAAANQAECgIIAwAAAA==.',
It='Ithea:BAAANQAECggIEwAAAA==.',
Ja='Jackshots:BAAANQADCgIIAgAAAA==.Jaeson:BAEANQAECgUICAAAAA==.Jakaro:BAABNQAECoEaAAMLAAgK7BM+IgA7AQAIAAYKzxQvYACoAQALAAUKgxE+IgA7AQAAAA==.',
Je='Jeef:BAAANQADCgcICQABNQAECgYIBgACAAAAAA==.Jeefwrld:BAAANQAECgYICQAAAA==.Jeffers:BAAANQAECgEJAQABNQAECgYIBgACAAAAAA==.Jeffha:BAAANQADCggJCAAAAA==.',
Ji='Jiinx:BAAANQAECgUIDAAAAA==.',
Jo='Joejr:BAAANQAECgYJDQAAAA==.Jonald:BAAANQAECgcIEAAAAA==.',
Jt='Jtizlfrizl:BAAANQAECgMJAwAAAA==.',
Ju='Juniperz:BAAANQAECgIIAwAAAA==.',
Jw='Jwise:BAAANQADCgQIBAAAAA==.',
Ka='Kaaydenn:BAAANQAECgQJBgAAAA==.Kalaziel:BAAANQADCgMIAwAAAA==.Kalierix:BAAANQAECgYJBgAAAA==.Kamus:BAAANQABCgQIBwAAAA==.Karawyn:BAAANQAECgEJAgABNQADCgQICAACAAAAAA==.Katrichi:BAAANQAECgEIAQAAAA==.Katrishy:BAABNQAECoEdAAIMAAgKlh36DQDAAgAMAAgKlh36DQDAAgAAAA==.Kayde:BAAANQAECgQIBAAAAA==.',
Ke='Keedrid:BAAANQAECgUJDQAAAA==.Kelaeno:BAAANQAECgYJCwAAAA==.Kev:BAABNQAECoEeAAIKAAkKqiS+AQDCAwAKAAkKqiS+AQDCAwAAAA==.',
Ki='Kirmit:BAAANQAECgIIAQAAAA==.',
Kn='Knoll:BAAANQADCggICQAAAA==.',
Kr='Kreeona:BAAANQAECgYJCwAAAA==.Kruàlty:BAAANQAECgYIDAAAAA==.',
La='Laird:BAAANQADCgcICwAAAA==.',
Le='Legreecast:BAAANQADCgYJDQAAAA==.',
Li='Liare:BAACNQAFFIEHAAMLAAMKUx2fBAC/AAALAAIKNx2fBAC/AAAIAAEKih0bHwBZAAA1AAQKgSMABAgACQpqJeYFAG0DAAgACQrWI+YFAG0DAAsABgpWGHEWAKEBAAkAAgopJscOAN8AAAAA.Liasong:BAAANQADCgUJDgAAAA==.Litheliice:BAAANQAECgUICQAAAA==.',
Lo='Lodur:BAAANQAECgIIAwAAAA==.Lonen:BAAANQAECgIIAwAAAA==.Losat:BAAANQAECgYJCwAAAA==.',
['Lî']='Lîîght:BAAANQADCggIDgAAAA==.',
Ma='Machiato:BAAANQADCgYJCAAAAA==.Mackkie:BAAANQAECgUICQAAAA==.Madonkadonk:BAAANQAECgUIBwAAAA==.Maedai:BAAANQAECgUICQAAAA==.Maeli:BAAANQADCggJDgAAAA==.Magladroth:BAAANQABCgQJBAAAAA==.Maldive:BAAANQAECgYJDQAAAA==.Maligasia:BAAANQADCgIJAwAAAA==.Mallicia:BAABNQAECoEbAAINAAgKdSH+EgDoAgANAAgKdSH+EgDoAgAAAA==.Mallistra:BAAANQAECgUJCAABNQAECggJGwANAHUhAA==.Mallwizard:BAAANQAECgUJCgAAAA==.Martris:BAAANQAECgEJAQAAAA==.Maryjane:BAAANQAECgMJAwAAAA==.Massoflice:BAAANQAECgYJCgAAAA==.Maxblaide:BAAANQADCggIGAAAAA==.',
Me='Melovania:BAAANQADCgIIAgAAAA==.',
Mi='Miami:BAAANQAECgEJAQABNQAFFAUIDgAGAA8bAA==.Misstangy:BAAANQADCgcIFwAAAA==.',
Mo='Moct:BAAANQAECgYJDQAAAA==.',
Mu='Musashi:BAABNQAECoEeAAIOAAgK3yRVCwBNAwAOAAgK3yRVCwBNAwABNQAECgkJGQAOAFUmAA==.Muskeg:BAAANQAECgUICQAAAA==.Mustardhunt:BAAANQADCgYICgAAAA==.',
['Mü']='Münchkiné:BAAANQABCggIDgAAAA==.',
Na='Namanari:BAAANQABCgIJAgAAAA==.Naris:BAAANQAECgQIBgAAAA==.',
Ne='Necrochade:BAAANQAECgEIAQAAAA==.Neptune:BAAANQAECgYIDAAAAA==.',
Ni='Nightstew:BAAANQADCgYICAAAAA==.Nishal:BAAANQADCggJFQAAAA==.',
Ny='Nyxaries:BAAANQAECgEJAQAAAA==.',
['Né']='Néwby:BAABNQAECoEbAAIPAAgKux88BADjAgAPAAgKux88BADjAgAAAA==.',
Op='Opalynn:BAAANQAECgEIAQAAAA==.Ophirra:BAAANQABCgYIDgAAAA==.',
Oz='Ozempic:BAAANQAECgQIBAABNQAFFAUICgAFAFYaAA==.',
Pa='Pablo:BAAANQAECgUICAAAAA==.Patriot:BAAANQADCgUJBwAAAA==.Pawinurbutt:BAAANQADCgQIBAAAAA==.',
Pe='Peppert:BAAANQADCggICAAAAA==.',
Ph='Phane:BAAANQAECgQJBAAAAA==.',
Pu='Puffer:BAAANQAECgQJBgAAAA==.',
Px='Pxry:BAAANQAECgQIBAAAAA==.',
Ra='Rabone:BAAANQADCgIJAgAAAA==.Raevyn:BAAANQADCgYIBgAAAA==.Raito:BAAANQAECgMJAwAAAA==.Rakshasa:BAABNQAECoEaAAMIAAgKph3eJwCEAgAIAAcK+h7eJwCEAgALAAMK3w8wOQC5AAAAAA==.Rano:BAAANQADCgUIBgAAAA==.Rasetsungo:BAAANQAECgYJCwAAAA==.Raura:BAAANQADCgYJDQAAAA==.',
Re='Redblueblurr:BAAANQADCggIHwAAAA==.Remi:BAAANQAECgYICwAAAA==.Rev:BAAANQADCgUIBQAAAA==.Reveillark:BAAANQAECgIIAgAAAA==.',
Ro='Rolan:BAABNQAECoEZAAQQAAgKmCXnCgA3AwAQAAgKJCTnCgA3AwARAAQKVCSUPgCTAQASAAEK4CPRXgBkAAAAAA==.Rosalian:BAAANQAECgIIAwAAAA==.Rotiko:BAAANQAECgIJBAAAAA==.Roweene:BAAANQAECgUIDAAAAA==.',
['Rá']='Rágnar:BAAANQAECgQICgAAAA==.',
Sa='Sabiel:BAAANQAECgQIBgAAAA==.Sakuta:BAAANQADCgYIBgABNQAECgYIEAACAAAAAA==.',
Se='Serenatee:BAAANQAECgUICAAAAA==.Setthole:BAAANQADCgYIBgAAAA==.',
Sh='Shagohod:BAAANQADCgQIBAAAAA==.Shakked:BAAANQADCgcIFAAAAA==.',
Sk='Skotojar:BAAANQADCgUIBQAAAA==.',
Sn='Snortedgfuel:BAAANQAECgcIDQAAAA==.',
So='Solphera:BAAANQADCgQICAAAAA==.Sonknight:BAAANQADCggIJAAAAA==.',
Sp='Speedshot:BAAANQADCgUIBgAAAA==.Spitefulcrow:BAAANQAECgYJDwAAAA==.',
St='Stardstr:BAAANQADCgMIAwAAAA==.Sto:BAAANQAECgEJAQAAAA==.',
Su='Sufferding:BAAANQAECgQJBQAAAA==.Suria:BAAANQAECgYJDQAAAA==.',
Sy='Syker:BAAANQADCgIIAgAAAA==.',
Ta='Tahrovin:BAAANQAECgEIAQAAAA==.Taytorchips:BAAANQAECgYJCwAAAA==.',
Th='Thaendrin:BAAANQADCgYICQAAAA==.Thearcane:BAAANQADCgQIBwAAAA==.Theefjeef:BAAANQAECgMIBAABNQAECgYIBgACAAAAAA==.Thorloim:BAAANQAECgUIDAAAAA==.Thornx:BAAANQADCgEIAQAAAA==.Thundercups:BAAANQAECgUICAAAAA==.',
Ti='Tigerstarr:BAAANQAECgcICwAAAA==.Tinyshieva:BAAANQADCgQIBAAAAA==.Tizuki:BAAANQAECgQIBAAAAA==.',
To='Tonystandard:BAAANQAECgUIBQABNQAECggIIQATANweAA==.',
Tr='Treborlock:BAAANQAECgUJCgAAAA==.Triplock:BAAANQAECgEJAQAAAA==.Trolcain:BAAANQAECgYJDQAAAA==.',
Tw='Twistedspork:BAAANQADCgYIEAAAAA==.',
Un='Unbuffed:BAAANQABCgQJBQABNQAECgUIEAACAAAAAA==.',
Va='Vaedar:BAAANQAECgEIAQAAAA==.Vagglord:BAAANQAECgQIDwAAAA==.Valha:BAAANQAECgQJBQAAAA==.Vardisk:BAAANQADCgQIBAAAAA==.Varteras:BAAANQAECgUICAAAAA==.',
Ve='Vellron:BAAANQAECgYJDQAAAA==.Veroque:BAAANQADCgUJBQAAAA==.',
['Vø']='Vødøu:BAAANQAECgMIBgAAAA==.',
Wa='Wafflelegend:BAABNQAECoEWAAIHAAcKlSA4EwClAgAHAAcKlSA4EwClAgAAAA==.Wardkbriggle:BAABNQAECoEXAAMSAAkKGxwWFwBXAgASAAkKgBkWFwBXAgAQAAgK6xg8KQAeAgAAAA==.Warint:BAAANQAECgQIBgAAAA==.',
We='Weeble:BAAANQADCgMIAwAAAA==.Welish:BAAANQABCgEIAQAAAA==.',
Wi='Wifi:BAAANQAECgUIBgAAAA==.',
Wo='Wolfdude:BAAANQAECggJBQAAAA==.',
Wy='Wydge:BAAANQAECgUICwAAAA==.Wyven:BAAANQAECgYJEAABNQADCgcICgACAAAAAA==.',
Xa='Xanddoria:BAAANQAECgYIDgAAAA==.Xaoc:BAAANQAECgUICQAAAA==.',
Xh='Xhared:BAAANQAECgUJEAAAAA==.',
Xo='Xochital:BAAANQADCgEIAQAAAA==.',
Ze='Zephy:BAAANQAECgMJAwAAAA==.',
['Åe']='Åeon:BAAANQADCggIHwAAAA==.',
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
