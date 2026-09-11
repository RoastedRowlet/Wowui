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

local lookup = {'Evoker-Preservation','Unknown-Unknown','Warrior-Arms','Hunter-Marksmanship','Monk-Brewmaster',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abnee:BAAANQADCgIIAwAAAA==.',
Ad='Adowyrm:BAABNQAECoEWAAIBAAgJzh4CBQDpAgABAAgJzh4CBQDpAgAAAA==.Adrielle:BAAANQADCgcICgAAAA==.',
Ai='Airali:BAAANQAECgQIBgAAAA==.Airedale:BAAANQADCggIEQAAAA==.',
Ak='Akairo:BAAANQAECgcIEQAAAA==.',
Al='Alexanderlx:BAAANQADCgQIBAAAAA==.Aleybobwa:BAAANQAECgUICgAAAA==.Althalas:BAAANQADCgQIBAAAAA==.',
An='Andramedae:BAAANQAECgIIAgAAAA==.Angyavocado:BAAANQAECgYICQAAAA==.Antithanatos:BAAANQABCgQICAAAAA==.',
Ao='Aolus:BAAANQAECgYICwAAAA==.',
Ap='Apoliis:BAAANQADCgcIDAAAAA==.Apollyon:BAAANQAECgEIAQAAAA==.',
Ar='Arcidaes:BAEANQAECgIIAgAAAA==.',
As='Astryd:BAAANQAECgIIAwAAAA==.Asurna:BAAANQADCggIEAAAAA==.',
At='Athlon:BAAANQAECgEIAQAAAA==.',
Au='Aurellia:BAAANQADCgYIBgAAAA==.',
Aw='Awake:BAAANQADCgcIBwAAAA==.Awooga:BAAANQAECgcICgAAAA==.',
Az='Azaekho:BAAANQADCgUIBQAAAA==.',
Ba='Baeyorn:BAAANQADCgEIAQAAAA==.Bajablaster:BAAANQADCggIEwAAAA==.Baliw:BAAANQAECgYICgAAAA==.Balto:BAAANQADCgQIBAAAAA==.Bandoliers:BAAANQAECgIIAgAAAA==.',
Bb='Bbl:BAEANQAECgcIEAAAAA==.',
Bc='Bchung:BAAANQAECgYICwAAAA==.',
Be='Bela:BAAANQADCgUIBQAAAA==.Bertus:BAAANQAFFAEIAQAAAA==.',
Bh='Bhain:BAAANQAECgUIBwAAAA==.',
Bi='Bieorne:BAAANQAECgIIAgAAAA==.',
Bl='Bloodwrath:BAAANQADCgQICQAAAA==.',
Bo='Boondocks:BAAANQAECgIIAgAAAA==.Bottomx:BAAANQADCgYIBQAAAA==.',
Br='Braca:BAAANQADCggIFAAAAA==.Bread:BAAANQADCggIDQAAAA==.Brielle:BAAANQAECgMIAwAAAA==.Brimmnin:BAAANQADCgQIBAAAAA==.Brokenbranch:BAAANQADCgMIAwAAAA==.',
Bu='Bubbletruble:BAAANQADCgUICgAAAA==.Buddylock:BAAANQADCgEIAQAAAA==.Buffalowings:BAAANQADCgEIAQABNQABCgIIAgACAAAAAA==.Bullymaguire:BAAANQADCgYIBgABNQADCggICAACAAAAAA==.',
Ce='Ceromaar:BAAANQAECgQICQABNQAECgUICQACAAAAAA==.',
Ch='Charge:BAABNQAECoEYAAIDAAkJJyOdBACcAwADAAkJJyOdBACcAwAAAA==.Checkurback:BAAANQADCgcIDQAAAA==.Chewtum:BAAANQADCgMIAwAAAA==.Chimo:BAAANQABCgUIBQABNQAECgQIBAACAAAAAA==.',
Co='Cobellex:BAAANQABCgUIBQAAAA==.Cops:BAAANQAECgEIAQAAAA==.',
Cr='Cruubakk:BAAANQADCgIIAgAAAA==.',
Cy='Cy:BAAANQADCgYIEQAAAA==.',
Da='Danaconda:BAAANQABCgQIBgABNQADCgYIEgACAAAAAA==.Darkenergy:BAAANQAECgIIAgAAAA==.Dashyll:BAAANQADCggICgAAAA==.Dazzled:BAAANQADCgcIBwAAAA==.',
De='Deadlegslul:BAAANQADCgYIDQAAAA==.Deathhelix:BAAANQADCgEIAQAAAA==.Deathmono:BAAANQADCggIDgAAAA==.Deathshark:BAAANQADCgQIBAABNQAECgUICwACAAAAAA==.Demacus:BAAANQADCgQICQABNQAECgMIBgACAAAAAA==.Demeter:BAAANQAECgQIBAAAAA==.',
Di='Dimeniare:BAAANQADCgcIDwAAAA==.Dirgen:BAAANQADCggIEwAAAA==.',
Do='Docktorwhom:BAAANQADCgQIBAAAAA==.Dookiee:BAAANQADCggIDgAAAA==.Doublenickel:BAAANQAECgUIBQAAAA==.',
Dr='Dragönlöl:BAAANQADCgUIBQAAAA==.Drakkaris:BAAANQADCggIEwAAAA==.Drat:BAAANQAECgIIAgAAAA==.Drustan:BAAANQADCgIIAgABNQADCgYIDAACAAAAAA==.',
Eb='Ebojager:BAAANQAECgIIAgAAAA==.',
Ed='Eddardstark:BAAANQADCgQIBAAAAA==.',
Ei='Eibon:BAAANQAFFAEIAQAAAA==.',
El='Elvispriesty:BAAANQADCgUIAwAAAA==.Elwarrioro:BAAANQAECgEIAQAAAA==.',
Er='Ere:BAAANQAECgIIAgAAAA==.Erus:BAAANQADCgEIAQAAAA==.',
Es='Eskath:BAAANQADCggIDwABNQAECgIIAgACAAAAAA==.Essential:BAAANQAECgUIBgAAAA==.',
Ev='Evavaria:BAAANQAECgEIAQABNQABCgMIAwACAAAAAA==.Evdoggy:BAAANQAECgUIBQAAAA==.Eveleonoc:BAAANQABCgMIAwAAAA==.',
Ex='Exterminate:BAAANQADCgUIBQAAAA==.',
Fe='Fellina:BAAANQAECgIIAgAAAA==.Felparsnip:BAEANQADCgYIBgABNQADCggIFwACAAAAAA==.Ferrara:BAABNQAECoEWAAIEAAgJdiGYCQDNAgAEAAgJdiGYCQDNAgAAAA==.',
Fi='Filthi:BAAANQAECgMIAwAAAA==.Fiz:BAAANQADCgYIBgABNQADCgcIBwACAAAAAA==.',
Fl='Flandri:BAAANQAFFAEIAQAAAA==.',
Fo='Forehead:BAAANQADCgQIBAAAAA==.Foskins:BAAANQAECgQIBAAAAA==.',
Fr='Frostednip:BAAANQAECgYICAAAAA==.',
Fu='Fuzz:BAAANQADCgUIBQAAAA==.',
Ga='Gabiru:BAAANQAECgQICQAAAA==.Gadreeste:BAAANQADCgQIBAAAAA==.Galnarn:BAABNQAECoEXAAIFAAkJqyOhAACjAwAFAAkJqyOhAACjAwAAAA==.Gambagood:BAAANQAECgIIAgAAAA==.Gank:BAAANQAECggIEgAAAA==.Garjingo:BAAANQADCgEIAQABNQADCggIEwACAAAAAA==.Garlicbae:BAAANQADCgcIDgAAAA==.Garwulf:BAAANQADCggICAAAAA==.',
Ge='Gefaustet:BAAANQAECgIIAgAAAA==.',
Gr='Grayes:BAAANQADCgcIEQABNQABCgEIAQACAAAAAA==.Grelin:BAAANQAECgQIBQAAAA==.Grog:BAAANQADCggICgAAAA==.',
Gu='Gumption:BAAANQADCgMIAwAAAA==.',
Ha='Hail:BAAANQAECgIIAgABNQAECgYICwACAAAAAA==.Hamshamwhich:BAAANQADCgQIBAABNQABCgIIAgACAAAAAA==.Harmôny:BAAANQADCgMIAwAAAA==.Hatredyes:BAAANQAECgMIAwAAAA==.',
He='Helare:BAAANQAECgMIAwAAAA==.Helowyn:BAAANQADCggIDAAAAA==.Hexenbane:BAAANQADCgYIDwAAAA==.',
Hy='Hyasin:BAAANQAECgYIBwAAAA==.Hype:BAAANQADCgUIBQAAAA==.',
Id='Idlewild:BAEANQABCgQIBAABNQADCgcIDAACAAAAAA==.',
Ig='Ignazio:BAAANQADCgEIAQAAAA==.',
Ih='Ihorns:BAAANQADCgIIAgAAAA==.',
Ik='Ikedizzy:BAAANQAECgEIAQAAAA==.Ikrys:BAAANQADCggICAAAAA==.',
Il='Illiae:BAAANQAECgUIBgAAAA==.',
Im='Impactr:BAAANQADCgYIBgAAAA==.',
In='Insecure:BAAANQAECgMIAwAAAA==.',
Io='Ionic:BAAANQAECgMIAwAAAA==.',
Is='Issidora:BAAANQADCgcIDgAAAA==.',
Ja='Jakeakuma:BAAANQAECgQIBQAAAA==.Janja:BAAANQABCgIIAgABNQAECgIIAwACAAAAAA==.Jaynne:BAAANQADCgUIBwAAAA==.',
Ji='Jimmywhisky:BAAANQADCgIIAgAAAA==.',
Jo='Johnivxx:BAAANQADCgYIBQAAAA==.',
Ju='Judokeg:BAAANQAECgMIAwAAAA==.',
['Jà']='Jàckblack:BAAANQADCgMIAwAAAA==.',
Ka='Kaashaa:BAAANQAECgYICQAAAA==.Kaelsgf:BAAANQAECgYICwAAAA==.Kahllan:BAAANQADCggIDgAAAA==.Kahnigitt:BAAANQADCgMIBQAAAA==.Kataltoholic:BAAANQAECgEIAQAAAA==.Kayhas:BAAANQADCgIIAwAAAA==.Kazarel:BAAANQADCggIDAAAAA==.',
Ke='Kelinïsha:BAAANQADCggIEgAAAA==.',
Kh='Khelldyr:BAAANQADCggIEgAAAA==.',
Ki='Kiiras:BAAANQADCggIEwAAAA==.Kimbodh:BAAANQAECgcICwAAAA==.Kimoora:BAAANQADCgcICwAAAA==.Kimshady:BAAANQADCgYIBgABNQADCgcICwACAAAAAA==.Kirathein:BAAANQADCgcIDwAAAA==.',
Kl='Klefthoof:BAAANQAECgMIBgAAAA==.',
Ko='Kodey:BAAANQADCggIFQABNQAECgQIBgACAAAAAA==.',
Kr='Krimboz:BAAANQADCgYIDAAAAA==.Krystallight:BAAANQAECgEIAQAAAA==.',
La='Lazreki:BAAANQABCgYIBQAAAA==.',
Le='Lechuzón:BAAANQADCgQIBAAAAA==.Legaloas:BAAANQAECgQICgAAAA==.Lenah:BAAANQADCgMIAwAAAA==.Leondero:BAAANQAECgQICQAAAA==.Leroyjenkins:BAAANQADCgYIDAAAAA==.',
Ll='Llevanya:BAAANQAECgIIAgAAAA==.',
Lo='Lofi:BAAANQADCggIEgAAAA==.Lokkhar:BAAANQAECgEIAQAAAA==.',
Lu='Lubricated:BAAANQADCggIEgAAAA==.Luxon:BAAANQADCgYICgAAAA==.',
['Lè']='Lèdrollan:BAAANQAECgQIBQAAAA==.',
Ma='Mageypoo:BAAANQADCggIBgAAAA==.Magicdreams:BAAANQAECgIIAgAAAA==.Mahll:BAAANQAECgIIAgAAAA==.Malmorte:BAAANQADCgYIBgAAAA==.Malorane:BAAANQAECgEIAQAAAA==.Malorix:BAAANQAECgYICQAAAA==.Maléficaa:BAAANQADCgQIBAAAAA==.Materia:BAAANQADCgcIEgAAAA==.Maz:BAAANQAECgIIAgAAAA==.',
Mc='Mcflury:BAAANQADCggIDAAAAA==.',
Me='Meatbeef:BAAANQADCgYIEgAAAA==.Meerchi:BAAANQADCggIDgAAAA==.Meknin:BAAANQAECgIIAgAAAA==.Meldia:BAAANQADCgYIBgAAAA==.Mesthos:BAAANQAECgEIAQABNQADCgYIDAACAAAAAA==.',
Mi='Mickieta:BAAANQAECgIIAgAAAA==.Mikalau:BAAANQAECgQIBAAAAA==.Milktide:BAAANQADCgQIBAAAAA==.Mistrunner:BAAANQADCgYIBgAAAA==.Mistspell:BAAANQAECgYICwAAAA==.',
Mo='Mochacho:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.Mognel:BAAANQADCggIEwAAAA==.Mogrungar:BAAANQAECgUIBwAAAA==.Moomootus:BAAANQAECggIEgAAAA==.Motoraxe:BAAANQAECgcIDgAAAA==.',
My='Mystynight:BAAANQADCgUIBgAAAA==.',
Na='Naajin:BAAANQADCgUIBQAAAA==.Nauty:BAAANQABCgUIBQAAAA==.',
Ne='Newt:BAAANQADCggIEQAAAA==.',
Ni='Nicegauges:BAEANQADCggIFwAAAA==.Nightcrest:BAAANQAECgQIBAAAAA==.Nightrocks:BAAANQADCgcICwAAAA==.Nilfgard:BAAANQADCgUIBwAAAA==.',
No='Nordrydsh:BAAANQADCgcIBwABNQAECgcIDAACAAAAAA==.',
Nu='Nuhpie:BAAANQAFFAEIAQAAAA==.',
Oc='Occultfish:BAAANQAECgIIAgAAAA==.',
Ol='Olimdar:BAAANQAFFAEIAQAAAA==.',
Oo='Oopositive:BAAANQADCgIIAgAAAA==.',
Or='Oraion:BAAANQAECgIIAgAAAA==.',
Ov='Ovarb:BAAANQADCggIEgAAAA==.',
Pa='Pallydan:BAAANQADCgcIFAABNQAECgIIAgACAAAAAA==.Pan:BAAANQADCgYIBgAAAA==.Pathofpain:BAAANQADCgEIAQAAAA==.',
Pe='Peachie:BAAANQADCggIFQAAAA==.Persicles:BAAANQADCgEIAQAAAA==.',
Pi='Pissedwolf:BAAANQADCgEIAQAAAA==.',
Po='Polong:BAAANQADCgUIBQAAAA==.Poutine:BAAANQADCggICAAAAA==.',
Pr='Prisman:BAAANQADCggICAAAAA==.Proserpìne:BAAANQADCggIFAAAAA==.',
Pu='Putt:BAAANQADCgYICwAAAA==.',
Qu='Quoril:BAAANQAECgcIDwAAAA==.',
Ra='Radiyra:BAAANQABCgIIAgAAAA==.Ragnahr:BAAANQADCgEIAQAAAA==.Rainstormin:BAAANQADCgcIEgAAAA==.Raitan:BAAANQAECgQIBAAAAA==.Rantah:BAAANQADCgQIBAAAAA==.Rawrstance:BAAANQAECgIIAgABNQABCgIIAgACAAAAAA==.Razgrize:BAAANQADCgMIAwAAAA==.',
Re='Remsham:BAAANQADCgYIDwAAAA==.Renwyck:BAAANQADCgYIDAAAAA==.Reovar:BAAANQABCgQIBAAAAA==.Reovarr:BAAANQADCgIIAgAAAA==.Revengemoon:BAAANQAECgYICwAAAA==.',
Ro='Robane:BAAANQADCgUIBQAAAA==.Rouen:BAAANQADCgIIAgAAAA==.',
Ru='Rubidea:BAAANQAECgIIAgAAAA==.Ruckus:BAEANQADCgcIDAAAAA==.Rude:BAAANQADCggIBgAAAA==.Ruder:BAAANQADCgEIAQABNQAECgMIAwACAAAAAA==.Rutabaga:BAAANQADCgIIAgAAAA==.',
Ry='Rythas:BAAANQADCgUIBQAAAA==.',
Sa='Sandkat:BAAANQAECgYIAgAAAA==.Santalight:BAAANQAECgEIAgABNQAECgYIDQACAAAAAA==.Santamoe:BAAANQAECgYIDQAAAA==.Saraelin:BAAANQAECgMIAwAAAA==.Saray:BAAANQAECgUIBwAAAA==.Saurelli:BAAANQADCgYICAAAAA==.',
Se='Sedak:BAAANQADCggIEAAAAA==.Seitana:BAAANQABCgQIBAAAAA==.Sevrus:BAAANQADCgYIBgAAAA==.',
Sh='Shamushamu:BAAANQADCgMIAwAAAA==.Shaqheal:BAAANQADCggIDwAAAA==.Shiftymage:BAAANQAECgIIAwAAAA==.Shirtles:BAAANQADCgcIDQAAAA==.Shockandmoo:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.Shèp:BAAANQAECgEIAQABNQAECgMIBAACAAAAAA==.',
Si='Sidecake:BAAANQADCgQIBAAAAA==.Singars:BAAANQADCgcIDgAAAA==.Siypra:BAAANQAECgIIAgAAAA==.',
Sn='Snokplaster:BAAANQADCgYIBwAAAA==.Snorri:BAAANQAECgYICAAAAA==.Snowbvnny:BAAANQAECgEIBAAAAA==.',
So='Soleyn:BAAANQADCgYIBgAAAA==.Soto:BAAANQADCgYIDQAAAA==.',
Sp='Sprodage:BAAANQADCgcIEwAAAA==.',
St='Stanil:BAAANQAECgEIAQAAAA==.Steampunkz:BAAANQADCggIEwAAAA==.Strangetame:BAAANQADCgIIAwAAAA==.Striest:BAAANQAECgIIAgAAAA==.Styló:BAAANQAECgEIAQAAAA==.',
Su='Suelly:BAAANQAECgIIAgABNQAECgIIAwACAAAAAA==.Sularma:BAAANQADCgYIEAAAAA==.Suraschi:BAAANQAECgQIBgAAAA==.',
Sw='Swisscake:BAAANQAECgEIAQAAAA==.Swtmystic:BAAANQADCgUIBQAAAA==.',
Ta='Taldrin:BAAANQADCgMIAwAAAA==.Tallinor:BAAANQAECgMIBAAAAA==.Tannatax:BAAANQAECgIIAgAAAA==.Tashah:BAAANQADCgEIAQAAAA==.',
Te='Teamspidey:BAAANQADCgMIAwABNQADCgMIAwACAAAAAA==.Terminator:BAAANQADCgYIDAAAAA==.',
Th='Thewhitness:BAAANQADCggIEgAAAA==.Thewretch:BAAANQAECgIIAgAAAA==.Thumpthump:BAAANQADCggIGQAAAA==.Thunderkiss:BAEANQADCgQIBQABNQADCgcIDAACAAAAAA==.',
Ti='Tindoranis:BAAANQADCgIIAgAAAA==.',
To='Toothguy:BAAANQADCgMIAwAAAA==.Totemii:BAAANQADCgYIBgAAAA==.',
Tr='Tradewarrior:BAAANQADCgQIBAAAAA==.Trevor:BAAANQADCgMIAwAAAA==.Trueheart:BAAANQAECgYIBgAAAA==.',
Ts='Tshark:BAAANQAECgUICwAAAA==.Tsura:BAAANQAECgMIAwAAAA==.',
Tu='Tutatotao:BAAANQABCgQIBgABNQADCgEIAQACAAAAAA==.',
Un='Unclepeepers:BAAANQAECgYICwAAAA==.Underpowered:BAAANQADCgcIEAAAAA==.Unearthed:BAAANQADCgQIBAAAAA==.',
Ur='Urlän:BAAANQADCgYIBgAAAA==.',
Us='Usirina:BAAANQADCgUIBQABNQAECgMIAwACAAAAAA==.',
Va='Valhen:BAAANQAECgUICQAAAA==.Valtar:BAAANQAECgYICwAAAA==.',
Ve='Velryn:BAAANQADCgQIBAABNQAECgUICQACAAAAAA==.',
Vi='Vicsen:BAAANQADCgUIBQAAAA==.Vikaya:BAAANQADCgQIBAAAAA==.Vilevixon:BAAANQAECgIIAgAAAA==.',
Wa='Wagu:BAAANQABCgQIBAAAAA==.Walla:BAAANQADCgIIAgABNQADCgMIAwACAAAAAA==.Warbuddy:BAAANQADCggICQAAAA==.Warmis:BAAANQADCgYICgAAAA==.Warriorlobo:BAAANQAECgIIAwAAAA==.Watts:BAAANQAECgYIBwABNQAECgcIDwACAAAAAA==.',
We='Weez:BAAANQADCgUIBQAAAA==.',
Wi='Wildfang:BAAANQAECgQIBQAAAA==.',
Xa='Xandronys:BAAANQAECgMIAwAAAA==.',
Xe='Xebec:BAAANQADCggIFQAAAA==.',
Xy='Xyra:BAAANQADCgUIBgAAAA==.',
Ya='Yalik:BAAANQADCgMIAwAAAA==.',
Ye='Yeet:BAAANQADCgcIBwAAAA==.',
Yz='Yzugzugo:BAAANQADCgYIBgAAAA==.',
Za='Zalandra:BAAANQABCgUIBQAAAA==.Zalckar:BAAANQADCgcIDQAAAA==.Zanos:BAAANQADCgIIAgAAAA==.',
Ze='Zeeva:BAAANQAECgEIAQAAAA==.Zendead:BAAANQADCggIFQAAAA==.',
Zi='Zionspartan:BAAANQADCgYIBgAAAA==.',
Zu='Zugzugpriest:BAAANQADCggIEgAAAA==.Zurokhan:BAAANQAECgYICQAAAA==.',
['Zø']='Zønda:BAAANQAECgQIBwAAAA==.',
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
