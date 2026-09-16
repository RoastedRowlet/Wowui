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

local lookup = {'Evoker-Preservation','Priest-Holy','Priest-Shadow','Priest-Discipline','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','Warrior-Arms','Hunter-Marksmanship','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Devourer','Paladin-Retribution','Shaman-Restoration','Mage-Arcane','Rogue-Assassination',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abnee:BAAANQADCgYICQAAAA==.',
Ad='Adowyrm:BAABNQAECoEeAAIBAAkJRiAIAwBSAwABAAkJRiAIAwBSAwAAAA==.Adrielle:BAAANQADCgcICgAAAA==.',
Ai='Airali:BAAANQAECgYIDAAAAA==.Airedale:BAAANQAECgEIAQAAAA==.',
Ak='Akairo:BAABNQAECoEcAAQCAAkJOCIpBwAzAwACAAkJOCIpBwAzAwADAAEJDAdNRgA2AAAEAAEJNQFZHQAhAAAAAA==.',
Al='Alexanderlx:BAAANQAECgIIAgAAAA==.Aleybobwa:BAAANQAECgUICgAAAA==.Althalas:BAAANQADCgQIBAAAAA==.',
An='Andramedae:BAAANQAECgMIBQAAAA==.Angyavocado:BAAANQAECgYIDwAAAA==.Antithanatos:BAAANQABCgQICAAAAA==.',
Ao='Aolus:BAAANQAECgcIEgAAAA==.',
Ap='Apoliis:BAAANQADCggIDQAAAA==.Apollyon:BAAANQAECgEIAQAAAA==.',
Ar='Arcidaes:BAEANQAECgIIAwAAAA==.Arcus:BAAANQAECgYIBgAAAA==.',
As='Astryd:BAAANQAECgIIAwAAAA==.Asurna:BAAANQAECgIIAgAAAA==.',
At='Athlon:BAAANQAECgEIAQAAAA==.',
Au='Aurellia:BAAANQADCgYIBgAAAA==.',
Aw='Awake:BAAANQADCgcIBwAAAA==.Awooga:BAAANQAECggIDAAAAA==.',
Az='Azaekho:BAAANQADCgUIBQAAAA==.Azalet:BAAANQADCgQIAwAAAA==.',
Ba='Baeyorn:BAAANQADCgEIAQAAAA==.Bajablaster:BAAANQAECgIIAgAAAA==.Baliw:BAAANQAECgcIEQAAAA==.Balto:BAAANQADCgQIBAAAAA==.Bandoliers:BAAANQAECgIIAwAAAA==.',
Bb='Bbl:BAEANQAECgcIEQAAAA==.',
Bc='Bchung:BAAANQAECgcIEQAAAA==.',
Be='Bela:BAAANQADCgYICwAAAA==.Belathor:BAAANQADCgYIBgABNQAECgIIAgAFAAAAAA==.Bertus:BAABNQAECoEXAAMGAAkJ2SQwBACVAwAGAAkJvSQwBACVAwAHAAQJTSDCJwApAQAAAA==.',
Bh='Bhain:BAAANQAECgcIDgAAAA==.',
Bi='Bieorne:BAAANQAECgIIAwAAAA==.',
Bl='Blikefire:BAAANQADCgEIAQAAAA==.Bloodwrath:BAAANQADCgQICQAAAA==.',
Bo='Boondocks:BAAANQAECgMIBQAAAA==.Bottomx:BAAANQAECgEIAQAAAA==.',
Br='Braca:BAAANQAECgQIBAAAAA==.Bread:BAAANQADCggIEgAAAA==.Brielle:BAAANQAECgMIBgAAAA==.Brimmnin:BAAANQADCgQIBAAAAA==.Brokenbranch:BAAANQADCgMIAwAAAA==.Brudene:BAAANQADCgYIBgAAAA==.',
Bu='Bubbletruble:BAAANQADCgUICgAAAA==.Buddylock:BAAANQADCgEIAQAAAA==.Buffalowings:BAAANQADCgEIAQABNQADCgcIBwAFAAAAAA==.Bullymaguire:BAAANQAECgQIBAAAAA==.',
Ce='Ceromaar:BAAANQAECgcIEAAAAA==.',
Ch='Charge:BAABNQAECoEhAAIIAAkJtyX6AQDfAwAIAAkJtyX6AQDfAwAAAA==.Checkurback:BAAANQADCggIFQAAAA==.Chewtum:BAAANQADCgMIAwAAAA==.Chimo:BAAANQAECgUIBQAAAA==.',
Ci='Cillah:BAAANQABCgEIAQABNQAECgQIBgAFAAAAAA==.',
Co='Cobellex:BAAANQABCgUIBQAAAA==.Cops:BAAANQAECgQIBQAAAA==.',
Cr='Cruubakk:BAAANQADCgIIAgAAAA==.',
Cy='Cy:BAAANQADCggIGQAAAA==.',
Da='Danaconda:BAAANQABCgQIBgABNQADCgYIEgAFAAAAAA==.Darkenergy:BAAANQAECgMIBQAAAA==.Dashyll:BAAANQADCggIEgAAAA==.Dazzled:BAAANQADCgcIBwAAAA==.',
De='Deadlegslul:BAAANQADCgYIEwAAAA==.Deathhelix:BAAANQADCgEIAQAAAA==.Deathmono:BAAANQAECgIIAgAAAA==.Deathshark:BAAANQADCgQIBAABNQAECgYIEQAFAAAAAA==.Demacus:BAAANQAECgEIAQABNQAECgQICwAFAAAAAA==.Demeter:BAAANQAECgUICQAAAA==.',
Di='Dillkiller:BAAANQADCgMIAwAAAA==.Dimeniare:BAAANQADCggIFQAAAA==.Dirgen:BAAANQADCggIGwAAAA==.Dirtymagic:BAAANQADCggICAAAAA==.',
Do='Docktorwhom:BAAANQADCgQIBAAAAA==.Dookiee:BAAANQADCggIDgAAAA==.Doublenickel:BAAANQAECgUICAAAAA==.',
Dr='Dragönlöl:BAAANQADCgUIBQAAAA==.Drakkaris:BAAANQAECgIIAgAAAA==.Drat:BAAANQAECgQIBgAAAA==.Drimbarn:BAAANQADCggICAAAAA==.Drustan:BAAANQADCgIIAgABNQADCgYIDAAFAAAAAA==.',
Eb='Ebojager:BAAANQAECgIIAwAAAA==.',
Ed='Eddardstark:BAAANQADCgQIBAAAAA==.',
Ei='Eibon:BAAANQAFFAEIAQAAAA==.',
El='Eldric:BAAANQAECgQIBwAAAA==.Elvispriesty:BAAANQADCggICgAAAA==.Elvymir:BAAANQABCggICAAAAA==.Elwarrioro:BAAANQAECgEIAQAAAA==.',
Er='Ere:BAAANQAECgUIBwAAAA==.Erus:BAAANQADCgEIAQAAAA==.',
Es='Eskath:BAAANQADCggIDwABNQAECgIIAgAFAAAAAA==.Essential:BAAANQAECgYIDAAAAA==.',
Ev='Evavaria:BAAANQAECgIIAwABNQABCgUIBQAFAAAAAA==.Evdoggy:BAAANQAECgUICQAAAA==.Eveleonoc:BAAANQABCgMIAwAAAA==.',
Ex='Exterminate:BAAANQADCgUIBQAAAA==.',
Fe='Fellina:BAAANQAECgQIBgAAAA==.Felparsnip:BAEANQADCggIDwABNQADCggIHwAFAAAAAA==.Ferrara:BAABNQAECoEeAAIJAAkJCSLGBgApAwAJAAkJCSLGBgApAwAAAA==.',
Fi='Filthi:BAAANQAECgMIAwAAAA==.Fiz:BAAANQADCgYIBgABNQADCggIDwAFAAAAAA==.Fizzbang:BAAANQADCgYICAABNQADCgcIBwAFAAAAAA==.',
Fl='Flandri:BAABNQAECoEaAAICAAkJSCNgBQBOAwACAAkJSCNgBQBOAwAAAA==.',
Fo='Forehead:BAAANQADCgQIBAAAAA==.Foskins:BAAANQAECgQIBAABNQAECgUIBQAFAAAAAA==.',
Fr='Frostednip:BAABNQAECoESAAMHAAcJFBeZFwDeAQAHAAcJFBeZFwDeAQAGAAIJAQaMcwBfAAAAAA==.',
Fu='Fuzz:BAAANQADCgUIBQAAAA==.',
Ga='Gabiru:BAAANQAECgcIEAAAAA==.Gadreeste:BAAANQADCgQIBAAAAA==.Galnarn:BAABNQAECoEfAAIKAAkJRCTjAACpAwAKAAkJRCTjAACpAwAAAA==.Gambagood:BAAANQAECgIIBgAAAA==.Gank:BAABNQAECoEeAAMLAAkJJyBcBwD2AgALAAkJBSBcBwD2AgAKAAkJrxrmAwDGAgAAAA==.Garjingo:BAAANQADCgEIAQABNQAECgIIAgAFAAAAAA==.Garlicbae:BAAANQADCgcIDgAAAA==.Garwulf:BAAANQADCggIFAAAAA==.',
Ge='Gefaustet:BAAANQAECgMIBQAAAA==.',
Gr='Graybrew:BAAANQADCgQIBAAAAA==.Grayes:BAAANQADCggIGQABNQADCgQIBAAFAAAAAA==.Grelin:BAAANQAECgQICQAAAA==.Grog:BAAANQADCggIEgAAAA==.',
Gu='Gumption:BAAANQADCgMIAwAAAA==.',
Ha='Hail:BAAANQAECgIIAgABNQAECgcIDgAFAAAAAA==.Hamshamwhich:BAAANQADCgQIBAABNQADCgcIBwAFAAAAAA==.Harmôny:BAAANQADCgQIBQAAAA==.Hatredyes:BAAANQAECgUICAAAAA==.',
He='Helare:BAAANQAECgQIBwAAAA==.Helowyn:BAAANQADCggIDAAAAA==.Hexenbane:BAAANQAECgEIAQAAAA==.',
Hy='Hyasin:BAAANQAECgYICAAAAA==.Hype:BAAANQADCgUIBQAAAA==.',
Ic='Ice:BAAANQADCgIIAgABNQAECgEIAgAFAAAAAA==.',
Id='Idlewild:BAEANQABCgQIBAABNQAECgEIAQAFAAAAAA==.',
Ig='Ignazio:BAAANQADCgEIAQAAAA==.',
Ih='Ihorns:BAAANQADCgIIAgAAAA==.',
Ik='Ikedizzy:BAAANQAECgEIAgAAAA==.Ikrys:BAAANQADCggIDAAAAA==.',
Il='Illiae:BAAANQAECgUICgAAAA==.',
Im='Impactr:BAAANQADCgYIBgAAAA==.',
In='Insecure:BAAANQAECgMIAwAAAA==.',
Io='Ionic:BAAANQAECgYICQAAAA==.',
Is='Issidora:BAAANQADCggIFgAAAA==.',
Ix='Ix:BAAANQADCgQIBAAAAA==.',
Ja='Jakeakuma:BAAANQAECgUICgAAAA==.Janja:BAAANQABCgIIAgABNQAECgQIBgAFAAAAAA==.Jascob:BAAANQADCgcICAAAAA==.Jaynne:BAAANQADCgUIBwAAAA==.',
Ji='Jimmywhisky:BAAANQADCgIIAgAAAA==.',
Jo='Johnivxx:BAAANQADCggICgAAAA==.',
Ju='Judokeg:BAAANQAECgUICAAAAA==.',
['Jà']='Jàckblack:BAAANQADCgMIAwAAAA==.',
Ka='Kaashaa:BAAANQAECgYIDwAAAA==.Kaelsgf:BAAANQAECgcIEgAAAA==.Kahllan:BAAANQADCggIFgAAAA==.Kahnigitt:BAAANQADCgMIBQAAAA==.Kataltoholic:BAAANQAECgEIAQAAAA==.Kayhas:BAAANQADCgIIAwAAAA==.Kazarel:BAAANQADCggIDAAAAA==.',
Ke='Kelinïsha:BAAANQADCggIGgAAAA==.',
Kh='Khelina:BAAANQAECgIIAgAAAA==.Khelldyr:BAAANQADCggIGgAAAA==.',
Ki='Kiiras:BAAANQADCggIEwAAAA==.Kimbodh:BAABNQAECoEYAAIMAAkJkyG/AwCAAwAMAAkJkyG/AwCAAwAAAA==.Kimoora:BAAANQADCgcICwAAAA==.Kimshady:BAAANQADCgcICAABNQADCgcICwAFAAAAAA==.Kirathein:BAAANQADCgcIEQAAAA==.',
Kl='Klefthoof:BAAANQAECgQICwAAAA==.',
Ko='Kodey:BAAANQADCggIFQABNQAECgQICgAFAAAAAA==.',
Kr='Krimboz:BAAANQAECgEIAQAAAA==.Krystallight:BAAANQAECgQIBQAAAA==.',
La='Lazreki:BAAANQABCgcIBwAAAA==.',
Le='Lechuzón:BAAANQADCgQIBAAAAA==.Legaloas:BAAANQAECgYIEAAAAA==.Lenah:BAAANQADCgMIAwAAAA==.Leondero:BAAANQAECgcIEAAAAA==.Leroyjenkins:BAAANQADCgYIDAAAAA==.',
Li='Lintilla:BAAANQADCgUIBQAAAA==.',
Ll='Llevanya:BAAANQAECgMIBQAAAA==.',
Lo='Lofi:BAAANQAECgIIAgAAAA==.Lokkhar:BAAANQAECgEIAQAAAA==.Loredalso:BAAANQADCgIIAgAAAA==.',
Lu='Lubricated:BAAANQAECgIIAgAAAA==.Luxon:BAAANQADCggIDAAAAA==.',
['Lè']='Lèdrollan:BAAANQAECgYICwAAAA==.',
Ma='Mageypoo:BAAANQADCggIBgAAAA==.Magicdreams:BAAANQAECgIIAgAAAA==.Mahll:BAAANQAECgIIAgABNQAECgYIDwAFAAAAAA==.Malmorte:BAAANQADCgYIBgAAAA==.Malorane:BAAANQAECgEIAQAAAA==.Malorix:BAAANQAECgYIDwAAAA==.Maléficaa:BAAANQADCgQIBAAAAA==.Materia:BAAANQADCggIGgAAAA==.Maz:BAAANQAECgIIAgAAAA==.',
Mc='Mcflury:BAAANQADCggIDgAAAA==.',
Me='Meatbeef:BAAANQADCgYIEgAAAA==.Meerchi:BAAANQADCggIEgAAAA==.Meknin:BAAANQAECgUIBwAAAA==.Meldia:BAAANQADCggICwAAAA==.Mesthos:BAAANQAECgEIAQABNQADCgYIDAAFAAAAAA==.',
Mi='Mickieta:BAAANQAECgMIBQAAAA==.Mikalau:BAAANQAECgUICQAAAA==.Mikaluu:BAAANQADCggIDQAAAA==.Milktide:BAAANQADCgUIBwABNQAECgIIAgAFAAAAAA==.Mistrunner:BAAANQADCgYIBgAAAA==.Mistspell:BAAANQAECgcIEgAAAA==.',
Mo='Mochacho:BAAANQADCgYIBgABNQAECgUIBQAFAAAAAA==.Mognel:BAAANQADCggIGwAAAA==.Mogrungar:BAAANQAECgYIDQAAAA==.Moomootus:BAABNQAECoEdAAINAAkJMyA1DQA/AwANAAkJMyA1DQA/AwAAAA==.Motoraxe:BAABNQAECoEXAAIIAAkJOg2sSwAFAgAIAAkJOg2sSwAFAgAAAA==.',
My='Mystynight:BAAANQADCgUIBgAAAA==.',
Na='Naajin:BAAANQADCgUIBQAAAA==.Nauty:BAAANQABCgYICQAAAA==.',
Ne='Newt:BAAANQADCggIEQAAAA==.',
Ni='Nicegauges:BAEANQADCggIHwAAAA==.Nightcrest:BAAANQAECgUICAAAAA==.Nightrocks:BAAANQADCgcICwAAAA==.Nilfgard:BAAANQAECgQIAwAAAA==.Nivix:BAAANQADCgQIBAAAAA==.',
No='Nordrydsh:BAAANQADCgcIBwABNQAECggIDgAFAAAAAA==.',
Nu='Nuhpie:BAABNQAECoEcAAIIAAkJ/yCNEQA7AwAIAAkJ/yCNEQA7AwAAAA==.',
Oc='Occultfish:BAAANQAECgIIAgAAAA==.',
Ol='Olimdar:BAABNQAECoEbAAIOAAkJ2yFfAwCJAwAOAAkJ2yFfAwCJAwAAAA==.',
Oo='Oopositive:BAAANQADCgIIAgAAAA==.',
Or='Oraion:BAAANQAECgIIAgAAAA==.',
Ov='Ovarb:BAAANQAECgIIAgAAAA==.',
Pa='Pallydan:BAAANQADCggIHAABNQAECgIIAgAFAAAAAA==.Pan:BAAANQADCgYIBgAAAA==.Pathofpain:BAAANQADCgEIAQAAAA==.',
Pe='Peachie:BAAANQADCggIFQAAAA==.Persicles:BAAANQADCgMIBAAAAA==.',
Pi='Pissedwolf:BAAANQADCgEIAQAAAA==.',
Po='Polong:BAAANQADCgUIBQAAAA==.Poutine:BAAANQADCggICAAAAA==.',
Pr='Prisman:BAAANQADCggICAAAAA==.Proserpìne:BAAANQAECgIIAgAAAA==.',
Pu='Putt:BAAANQADCgYICwAAAA==.',
Qo='Qoolkumquat:BAAANQADCgcIBwAAAA==.',
Qu='Quoril:BAABNQAECoEYAAIPAAgJ6RkOSgBvAgAPAAgJ6RkOSgBvAgAAAA==.',
Ra='Radiyra:BAAANQABCgIIAgAAAA==.Ragnahr:BAAANQADCgEIAQAAAA==.Rainstormin:BAAANQADCggIGgAAAA==.Raitan:BAAANQAECgQICAAAAA==.Rantah:BAAANQADCgQIBAAAAA==.Rawrstance:BAAANQAECgUIBwABNQADCgcIBwAFAAAAAA==.Razgrize:BAAANQAECgMIAwAAAA==.',
Re='Reilin:BAAANQAECgEIAQAAAA==.Remsham:BAAANQAECgEIAQAAAA==.Renwyck:BAAANQADCgYIDAAAAA==.Reovar:BAAANQABCgQIBAAAAA==.Reovarr:BAAANQADCgIIAgAAAA==.Revengemoon:BAAANQAECgcIEgAAAA==.',
Ro='Robane:BAAANQADCgUIDAAAAA==.Rouen:BAAANQADCgIIAgAAAA==.',
Ru='Rubidea:BAAANQAECgMIBAAAAA==.Ruckus:BAEANQAECgEIAQAAAA==.Rude:BAAANQADCggIBgAAAA==.Ruder:BAAANQADCgEIAQABNQAECgUICAAFAAAAAA==.Rutabaga:BAAANQADCgIIAgAAAA==.',
Ry='Rythas:BAAANQADCgUIBQAAAA==.',
Sa='Sahranna:BAAANQABCgIIAgAAAA==.Saintanic:BAAANQADCgcIBwAAAA==.Sandkat:BAAANQAECgYIAwAAAA==.Santalight:BAAANQAECgEIAwABNQAECgcIFAALANUeAA==.Santamoe:BAABNQAECoEUAAILAAcJ1R6wCwCRAgALAAcJ1R6wCwCRAgAAAA==.Saraelin:BAAANQAECgMIAwAAAA==.Saray:BAAANQAECgYIDgAAAA==.Saurelli:BAAANQADCgYICAABNQAECgkJIAAQAA4jAA==.',
Se='Sedak:BAAANQADCggIFgAAAA==.Seitana:BAAANQABCgQIBAAAAA==.Sevrus:BAAANQADCgYIBgAAAA==.',
Sh='Shadysadie:BAAANQADCgQIAwAAAA==.Shamushamu:BAAANQADCgMIAwAAAA==.Shaqheal:BAAANQADCggIDwAAAA==.Shiftey:BAAANQAECgMIBAABNQAECgQIBwAFAAAAAA==.Shiftymage:BAAANQAECgQIBwAAAA==.Shirtles:BAAANQADCgcIDQAAAA==.Shockandmoo:BAAANQADCgUIBQABNQAECgQIBgAFAAAAAA==.Shèp:BAAANQAECgEIAQABNQAECgQICAAFAAAAAA==.',
Si='Sidecake:BAAANQADCgQIBAAAAA==.Singars:BAAANQAECgYIBQAAAA==.Siypra:BAAANQAECgMIBQAAAA==.',
Sk='Skelmir:BAAANQADCgYIBgAAAA==.',
Sn='Snokplaster:BAAANQADCgYIBwAAAA==.Snorri:BAAANQAECgYICQAAAA==.Snowbvnny:BAAANQAECgEIBAAAAA==.',
So='Soleyn:BAAANQADCgYIBgAAAA==.Soto:BAAANQADCgYIDwAAAA==.Sotosan:BAAANQADCgMIAwAAAA==.',
Sp='Sprodage:BAAANQAECgIIAgAAAA==.',
St='Stanil:BAAANQAECgIIAwAAAA==.Steampunkz:BAAANQADCggIGwAAAA==.Strangetame:BAAANQADCgIIAwAAAA==.Striest:BAAANQAECgIIAgAAAA==.Styló:BAAANQAECgEIAQAAAA==.',
Su='Suelly:BAAANQAECgMIAwABNQAECgQIBgAFAAAAAA==.Sularma:BAAANQAECgEIAQAAAA==.Suraschi:BAAANQAECgUICwAAAA==.',
Sw='Swisscake:BAAANQAECgEIAQAAAA==.Swtmystic:BAAANQADCgUIBgAAAA==.',
Sy='Sylain:BAAANQADCgYIBgABNQAECgIIAwAFAAAAAA==.',
Ta='Taldrin:BAAANQADCgMIAwAAAA==.Tallinor:BAAANQAECgMIBAAAAA==.Tannatax:BAAANQAECgIIAwAAAA==.Tashah:BAAANQADCgMIAwAAAA==.',
Te='Teamspidey:BAAANQADCgMIAwABNQADCgMIAwAFAAAAAA==.Terminator:BAAANQADCgYIDAAAAA==.',
Th='Thewhitness:BAAANQAECgIIAgAAAA==.Thewretch:BAAANQAECgIIAwAAAA==.Thumpthump:BAAANQADCggIIQAAAA==.Thunderkiss:BAEANQADCgQIBQABNQAECgEIAQAFAAAAAA==.',
Ti='Tindoranis:BAAANQADCgIIAgAAAA==.',
To='Toothguy:BAAANQADCgMIAwAAAA==.Totemii:BAAANQADCgYIBgAAAA==.',
Tr='Tradewarrior:BAAANQAECgEIAQAAAA==.Trevor:BAAANQADCgMIAwAAAA==.Trueheart:BAAANQAECgYIDAAAAA==.',
Ts='Tshark:BAAANQAECgYIEQAAAA==.Tsura:BAAANQAECgQIBwAAAA==.',
Tu='Tutatotao:BAAANQABCgQIBgABNQADCgEIAQAFAAAAAA==.',
Un='Unclepeepers:BAAANQAECgcIEgAAAA==.Underpowered:BAAANQADCgcIEAAAAA==.Unearthed:BAAANQADCgQIBAAAAA==.',
Ur='Urlän:BAAANQADCgYIBgAAAA==.',
Us='Usirina:BAAANQADCgUIBQABNQAECgUICAAFAAAAAA==.',
Va='Valhen:BAAANQAECgUICgAAAA==.Valtar:BAAANQAECgcIDAAAAA==.',
Ve='Velryn:BAAANQADCgUIBgABNQAECgUICgAFAAAAAA==.',
Vi='Vicsen:BAAANQADCgUIBQAAAA==.Vikaya:BAAANQADCgQIBAAAAA==.Vilevixon:BAAANQAECgMIBQAAAA==.',
Wa='Wagu:BAAANQABCgQIBAAAAA==.Walla:BAAANQADCgIIAgABNQADCgMIAwAFAAAAAA==.Wanlok:BAAANQAECgIIAgAAAA==.Warbuddy:BAAANQADCggIEQAAAA==.Warmis:BAAANQADCgYICgAAAA==.Warriorlobo:BAAANQAECgQIBgAAAA==.Watts:BAAANQAECgcICgABNQAECggIGAAPAOkZAA==.',
We='Weez:BAAANQADCgUIBQAAAA==.',
Wi='Wildfang:BAAANQAECgQICQAAAA==.',
Xa='Xandronys:BAAANQAECgQIBwAAAA==.',
Xe='Xebec:BAAANQAECgQIBAAAAA==.',
Xy='Xyra:BAAANQADCgUIBgAAAA==.',
Ya='Yalik:BAAANQADCgMIAwAAAA==.',
Ye='Yeet:BAAANQADCggIDwAAAA==.',
Yz='Yzugzugo:BAAANQAECgcIBwAAAA==.',
Za='Zalandra:BAAANQABCgUIBQAAAA==.Zalckar:BAAANQADCggIFQAAAA==.Zanos:BAAANQADCgQIBAAAAA==.',
Ze='Zeeva:BAAANQAECgEIAQAAAA==.Zendead:BAAANQADCggIFQAAAA==.',
Zi='Zionspartan:BAAANQADCgYIBgAAAA==.',
Zu='Zugzugpriest:BAAANQAECgIIAgAAAA==.Zurokhan:BAAANQAECgYIDwAAAA==.',
['Zø']='Zønda:BAAANQAECgQICwAAAA==.',
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
