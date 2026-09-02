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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=53,date='2026-09-01',data={Ad='Adowyrm:BAAANQAECgcIDQAAAA==.Adrielle:BAAANQADCgMIAwAAAA==.',
Ai='Airali:BAAANQAECgEIAgAAAA==.Airedale:BAAANQADCggICgAAAA==.',
Ak='Akairo:BAAANQAECgcICgAAAA==.',
Al='Alexanderlx:BAAANQADCgMIAwAAAA==.Aleybobwa:BAAANQAECgQIBQAAAA==.',
An='Andramedae:BAAANQADCggICgAAAA==.Angyavocado:BAAANQAECgMIAwAAAA==.Antithanatos:BAAANQABCgQIBQAAAA==.',
Ao='Aolus:BAAANQAECgQIBQAAAA==.',
Ap='Apoliis:BAAANQADCgMIBQAAAA==.Apollyon:BAAANQADCgUIBQAAAA==.',
Ar='Arcidaes:BAEANQADCggIDgAAAA==.',
As='Astryd:BAAANQAECgEIAQAAAA==.Asurna:BAAANQADCgUICAAAAA==.',
At='Athlon:BAAANQADCgQIBAAAAA==.',
Aw='Awooga:BAAANQAECgYICQAAAA==.',
Az='Azaekho:BAAANQADCgUIBQAAAA==.',
Ba='Baeyorn:BAAANQADCgEIAQAAAA==.Bajablaster:BAAANQADCgcICwAAAA==.Baliw:BAAANQAECgMIBAAAAA==.Balto:BAAANQADCgQIBAAAAA==.Bandoliers:BAAANQADCggICwAAAA==.',
Bb='Bbl:BAEANQAECgYICQAAAA==.',
Bc='Bchung:BAAANQAECgQIBQAAAA==.',
Be='Bela:BAAANQADCgMIAwAAAA==.Bertus:BAAANQAECgcICQAAAA==.',
Bh='Bhain:BAAANQAECgIIAgAAAA==.',
Bi='Bieorne:BAAANQADCggIDgAAAA==.',
Bl='Bloodwrath:BAAANQADCgQICQAAAA==.',
Bo='Boondocks:BAAANQADCggICgAAAA==.',
Br='Braca:BAAANQADCgYIDAAAAA==.Bread:BAAANQADCggIDQAAAA==.Brielle:BAAANQADCggIDgAAAA==.Brimmnin:BAAANQADCgQIBAAAAA==.Brokenbranch:BAAANQADCgMIAwAAAA==.',
Bu='Bubbletruble:BAAANQADCgUIBgAAAA==.Buddylock:BAAANQADCgEIAQAAAA==.Buffalowings:BAAANQADCgEIAQABNQABCgIIAgABAAAAAA==.Bullymaguire:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.',
Ce='Ceromaar:BAAANQAECgQIBQAAAA==.',
Ch='Charge:BAAANQAECgcIDQAAAA==.Checkurback:BAAANQADCgcIDQAAAA==.Chewtum:BAAANQADCgMIAwAAAA==.',
Co='Cobellex:BAAANQABCgQIBAAAAA==.Cops:BAAANQADCgYIBgAAAA==.',
Cr='Cruubakk:BAAANQADCgIIAgAAAA==.',
Cy='Cy:BAAANQADCgYICwAAAA==.',
Da='Darkenergy:BAAANQADCggICgAAAA==.Dashyll:BAAANQADCgIIAgAAAA==.Dazzled:BAAANQADCgcIBwAAAA==.',
De='Deadlegslul:BAAANQADCgUIBwAAAA==.Deathhelix:BAAANQADCgEIAQAAAA==.Deathmono:BAAANQADCgYIBgAAAA==.Demacus:BAAANQADCgQIBwABNQAECgMIAwABAAAAAA==.Demeter:BAAANQADCggIDgAAAA==.',
Di='Dimeniare:BAAANQADCgYICAAAAA==.Dirgen:BAAANQADCgYICwAAAA==.',
Do='Docktorwhom:BAAANQADCgQIBAAAAA==.Dookiee:BAAANQADCggIDgAAAA==.',
Dr='Drakkaris:BAAANQADCgYICwAAAA==.Drat:BAAANQADCggIDgAAAA==.Drustan:BAAANQABCgQIBAABNQADCgYIBgABAAAAAA==.',
Eb='Ebojager:BAAANQADCggIDgAAAA==.',
Ed='Eddardstark:BAAANQADCgIIAgAAAA==.',
Ei='Eibon:BAAANQAECgcICAAAAA==.',
El='Elwarrioro:BAAANQADCggIDAAAAA==.',
Er='Ere:BAAANQADCgcIDQAAAA==.Erus:BAAANQADCgEIAQAAAA==.',
Es='Eskath:BAAANQADCgYIBwABNQADCgcIDQABAAAAAA==.Essential:BAAANQAECgEIAQAAAA==.',
Ev='Evavaria:BAAANQAECgEIAQAAAA==.Evdoggy:BAAANQADCgcIDQAAAA==.Eveleonoc:BAAANQABCgMIAwAAAA==.',
Ex='Exterminate:BAAANQADCgQIBAAAAA==.',
Fe='Fellina:BAAANQADCgQIBAAAAA==.Ferrara:BAAANQAECgcIDQAAAA==.',
Fi='Filthi:BAAANQADCggICwAAAA==.Fiz:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.',
Fl='Flandri:BAAANQAECgUICAAAAA==.',
Fo='Forehead:BAAANQADCgQIBAAAAA==.Foskins:BAAANQADCggICAAAAA==.',
Fr='Frostednip:BAAANQAECgEIAgAAAA==.',
Fu='Fuzz:BAAANQADCgUIBQAAAA==.',
Ga='Gabiru:BAAANQAECgQIBQAAAA==.Gadreeste:BAAANQADCgIIAgAAAA==.Galnarn:BAAANQAECgcIDQAAAA==.Gambagood:BAAANQADCgYICQAAAA==.Gank:BAAANQAECgcICgAAAA==.Garjingo:BAAANQADCgEIAQABNQADCgcICwABAAAAAA==.Garlicbae:BAAANQADCgUIBwAAAA==.',
Ge='Gefaustet:BAAANQADCggICgAAAA==.',
Gr='Grayes:BAAANQADCgYICgABNQABCgEIAQABAAAAAA==.Grelin:BAAANQAECgEIAQAAAA==.Grog:BAAANQADCgIIAgAAAA==.',
Gu='Gumption:BAAANQADCgMIAwAAAA==.',
Ha='Hail:BAAANQADCgcICwABNQAECgQIBQABAAAAAA==.Hamshamwhich:BAAANQADCgQIBAABNQABCgIIAgABAAAAAA==.Harmôny:BAAANQADCgEIAQAAAA==.Hatredyes:BAAANQADCgcICAAAAA==.',
He='Helare:BAAANQADCggIDQAAAA==.Helowyn:BAAANQADCggIDAAAAA==.Hexenbane:BAAANQADCgYICQAAAA==.',
Hy='Hyasin:BAAANQAECgEIAQAAAA==.Hype:BAAANQADCgUIBQAAAA==.',
Ig='Ignazio:BAAANQADCgEIAQAAAA==.',
Ih='Ihorns:BAAANQADCgIIAgAAAA==.',
Ik='Ikedizzy:BAAANQAECgEIAQAAAA==.',
Il='Illiae:BAAANQAECgEIAQAAAA==.',
Im='Impactr:BAAANQADCgYIBgAAAA==.',
In='Insecure:BAAANQAECgEIAQAAAA==.',
Io='Ionic:BAAANQADCgUICgAAAA==.',
Is='Issidora:BAAANQADCgUIBwAAAA==.',
Ja='Jakeakuma:BAAANQAECgEIAQAAAA==.Jaynne:BAAANQADCgQIBAAAAA==.',
Jo='Johnivxx:BAAANQADCgIIAgAAAA==.',
Ju='Judokeg:BAAANQADCggICAAAAA==.',
Ka='Kaashaa:BAAANQAECgMIAwAAAA==.Kaelsgf:BAAANQAECgQIBQAAAA==.Kahllan:BAAANQADCgYICwAAAA==.Kahnigitt:BAAANQADCgMIBQAAAA==.Kataltoholic:BAAANQADCgcIDQAAAA==.Kayhas:BAAANQADCgIIAwAAAA==.Kazarel:BAAANQADCggIDAAAAA==.',
Ke='Kelinïsha:BAAANQADCgYICgAAAA==.',
Kh='Khelldyr:BAAANQADCgYICgAAAA==.',
Ki='Kiiras:BAAANQADCgYICwAAAA==.Kimbodh:BAAANQAECgcICwAAAA==.Kimoora:BAAANQADCgIIAgAAAA==.Kirathein:BAAANQADCgUICAAAAA==.',
Kl='Klefthoof:BAAANQAECgMIAwAAAA==.',
Ko='Kodey:BAAANQADCgcIDQABNQAECgIIAgABAAAAAA==.',
Kr='Krimboz:BAAANQADCgUICAAAAA==.Krystallight:BAAANQADCggIEAAAAA==.',
Le='Legaloas:BAAANQAECgQIBgAAAA==.Lenah:BAAANQADCgMIAwAAAA==.Leondero:BAAANQAECgQIBQAAAA==.Leroyjenkins:BAAANQADCgYIDAAAAA==.',
Ll='Llevanya:BAAANQADCggIDgAAAA==.',
Lo='Lofi:BAAANQADCgcICgAAAA==.Lokkhar:BAAANQAECgEIAQAAAA==.',
Lu='Lubricated:BAAANQADCgYICgAAAA==.Luxon:BAAANQADCgQIBAAAAA==.',
['Lè']='Lèdrollan:BAAANQAECgEIAQAAAA==.',
Ma='Mageypoo:BAAANQADCggIBgAAAA==.Magicdreams:BAAANQADCggIDgAAAA==.Mahll:BAAANQAECgIIAgAAAA==.Malmorte:BAAANQADCgYIBgAAAA==.Malorane:BAAANQAECgEIAQAAAA==.Malorix:BAAANQAECgMIAwAAAA==.Materia:BAAANQADCgYICwAAAA==.Maz:BAAANQADCggIDgAAAA==.',
Mc='Mcflury:BAAANQADCggICAAAAA==.',
Me='Meatbeef:BAAANQADCgYIDAAAAA==.Meerchi:BAAANQADCgYIBgAAAA==.Meknin:BAAANQADCgcICQAAAA==.Meldia:BAAANQADCgYIBgAAAA==.Mesthos:BAAANQADCggIDwABNQADCgYIBgABAAAAAA==.',
Mi='Mickieta:BAAANQADCggICgAAAA==.Mikalau:BAAANQADCgcICwAAAA==.Milktide:BAAANQADCgQIBAABNQADCgUICQABAAAAAA==.Mistrunner:BAAANQADCgYIBgAAAA==.Mistspell:BAAANQAECgQIBQAAAA==.',
Mo='Mochacho:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Mognel:BAAANQADCgYICwAAAA==.Mogrungar:BAAANQAECgIIAgAAAA==.Moomootus:BAAANQAECgcICgAAAA==.Motoraxe:BAAANQAECgQIBwAAAA==.',
My='Mystynight:BAAANQADCgEIAQAAAA==.',
Na='Naajin:BAAANQADCgUIBQAAAA==.',
Ne='Newt:BAAANQADCgYICQAAAA==.',
Ni='Nicegauges:BAEANQADCggIDwAAAA==.Nightcrest:BAAANQADCgEIAQAAAA==.Nightrocks:BAAANQADCgcICwAAAA==.Nilfgard:BAAANQADCgQIBAAAAA==.',
Nu='Nuhpie:BAAANQAECgcICgAAAA==.',
Oc='Occultfish:BAAANQADCggIDQAAAA==.',
Ol='Olimdar:BAAANQAECgcICgAAAA==.',
Or='Oraion:BAAANQADCgYICgABNQADCgcIDQABAAAAAA==.',
Ov='Ovarb:BAAANQADCgYICgAAAA==.',
Pa='Pallydan:BAAANQADCgcIDQAAAA==.Pan:BAAANQADCgYIBgAAAA==.Pathofpain:BAAANQADCgEIAQAAAA==.',
Pe='Peachie:BAAANQADCgcIDQAAAA==.Persicles:BAAANQABCgIIAgAAAA==.',
Pi='Pissedwolf:BAAANQADCgEIAQAAAA==.',
Po='Polong:BAAANQADCgUIBQAAAA==.',
Pr='Prisman:BAAANQABCgIIAgAAAA==.Proserpìne:BAAANQADCgcIDAAAAA==.',
Pu='Putt:BAAANQADCgYICwAAAA==.',
Qu='Quoril:BAAANQAECgYICAAAAA==.',
Ra='Radiyra:BAAANQABCgIIAgAAAA==.Rainstormin:BAAANQADCgYICwAAAA==.Raitan:BAAANQADCggIDgAAAA==.Rantah:BAAANQADCgQIBAAAAA==.Rawrstance:BAAANQADCgcIDQABNQABCgIIAgABAAAAAA==.Razgrize:BAAANQADCgMIAwAAAA==.',
Re='Remsham:BAAANQADCgYICQAAAA==.Renwyck:BAAANQADCgYIBgAAAA==.Reovar:BAAANQABCgQIBAAAAA==.Revengemoon:BAAANQAECgQIBQAAAA==.',
Ro='Rouen:BAAANQADCgIIAgAAAA==.',
Ru='Rubidea:BAAANQADCgUIBQAAAA==.Ruckus:BAEANQADCgMIBQAAAA==.Rude:BAAANQADCggIBgAAAA==.Rutabaga:BAAANQADCgIIAgAAAA==.',
Ry='Rythas:BAAANQADCgUIBQAAAA==.',
Sa='Sandkat:BAAANQADCggIDgAAAA==.Santalight:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Santamoe:BAAANQAECgQIBAAAAA==.Saraelin:BAAANQADCgcIDAAAAA==.Saray:BAAANQAECgEIAgAAAA==.Saurelli:BAAANQADCgMIAwABNQAECgcIDAABAAAAAA==.',
Se='Sedak:BAAANQADCgYICgAAAA==.Seitana:BAAANQABCgQIBAAAAA==.Sevrus:BAAANQADCgYIBgAAAA==.',
Sh='Shaqheal:BAAANQADCggIDwAAAA==.Shiftymage:BAAANQAECgEIAQAAAA==.Shirtles:BAAANQADCgcIDQAAAA==.Shockandmoo:BAAANQADCgQIBAAAAA==.Shèp:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
Si='Sidecake:BAAANQADCgQIBAAAAA==.Singars:BAAANQADCgcIDQAAAA==.Siypra:BAAANQADCggICgAAAA==.',
Sn='Snokplaster:BAAANQADCgMIAwAAAA==.Snorri:BAAANQAECgIIAgAAAA==.Snowbvnny:BAAANQAECgEIAQAAAA==.',
So='Soto:BAAANQADCgYIBwAAAA==.',
Sp='Sprodage:BAAANQADCgcIDAAAAA==.',
St='Stanil:BAAANQADCggICgAAAA==.Steampunkz:BAAANQADCgYICwAAAA==.Strangetame:BAAANQADCgIIAgAAAA==.Striest:BAAANQADCgcICgAAAA==.Styló:BAAANQADCggICQAAAA==.',
Su='Suelly:BAAANQADCggICgABNQAECgIIAgABAAAAAA==.Sularma:BAAANQADCgUICgAAAA==.Suraschi:BAAANQAECgIIAgAAAA==.',
Sw='Swisscake:BAAANQAECgEIAQAAAA==.Swtmystic:BAAANQADCgQIBAAAAA==.',
Ta='Taldrin:BAAANQADCgMIAwAAAA==.Tallinor:BAAANQAECgEIAQAAAA==.Tannatax:BAAANQADCggIDgAAAA==.',
Te='Teamspidey:BAAANQADCgMIAwABNQADCgMIAwABAAAAAA==.Terminator:BAAANQADCgUIBwAAAA==.',
Th='Thewhitness:BAAANQADCgYICgAAAA==.Thewretch:BAAANQADCggIDgAAAA==.Thumpthump:BAAANQADCggIEQAAAA==.Thunderkiss:BAEANQADCgIIAgABNQADCgMIBQABAAAAAA==.',
Ti='Tindoranis:BAAANQADCgIIAgAAAA==.',
Tr='Trevor:BAAANQADCgMIAwAAAA==.',
Ts='Tshark:BAAANQAECgQIBgAAAA==.Tsura:BAAANQADCggICwAAAA==.',
Un='Unclepeepers:BAAANQAECgQIBQAAAA==.Underpowered:BAAANQADCgcIDQAAAA==.Unearthed:BAAANQADCgQIBAAAAA==.',
Ur='Urlän:BAAANQADCgYIBgAAAA==.',
Va='Valhen:BAAANQAECgMIBAAAAA==.Valtar:BAAANQAECgQIBQAAAA==.',
Ve='Velryn:BAAANQADCgQIBAABNQAECgMIBAABAAAAAA==.',
Vi='Vicsen:BAAANQADCgUIBQAAAA==.Vikaya:BAAANQADCgIIAgAAAA==.Vilevixon:BAAANQADCggICgAAAA==.',
Wa='Wagu:BAAANQABCgQIBAAAAA==.Walla:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.Warbuddy:BAAANQADCgEIAQAAAA==.Warmis:BAAANQADCgYICgAAAA==.Warriorlobo:BAAANQAECgIIAgAAAA==.Watts:BAAANQADCggIDgABNQAECgYICAABAAAAAA==.',
We='Weez:BAAANQADCgUIBQAAAA==.',
Wi='Wildfang:BAAANQAECgEIAQAAAA==.',
Xa='Xandronys:BAAANQADCgUICgAAAA==.',
Xe='Xebec:BAAANQADCggIDQAAAA==.',
Xy='Xyra:BAAANQADCgEIAQAAAA==.',
Ya='Yalik:BAAANQADCgMIAwAAAA==.',
Ye='Yeet:BAAANQADCgcIBwAAAA==.',
Yz='Yzugzugo:BAAANQADCgYIBgAAAA==.',
Za='Zalandra:BAAANQABCgIIAgAAAA==.Zalckar:BAAANQADCgcIDQAAAA==.',
Ze='Zendead:BAAANQADCgcIDQAAAA==.',
Zi='Zionspartan:BAAANQADCgYIBgAAAA==.',
Zu='Zugzugpriest:BAAANQADCgYICgAAAA==.Zurokhan:BAAANQAECgMIAwAAAA==.',
['Zø']='Zønda:BAAANQAECgMIAwAAAA==.',
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
