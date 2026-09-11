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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Monk-Windwalker','Paladin-Protection','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','Druid-Restoration','Monk-Brewmaster','Mage-Arcane',}
local provider = {region='US',realm='Frostmane',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abaz:BAAANQABCgEIAQAAAA==.Aberdus:BAAANQAECgIIAwAAAA==.',
Ac='Accalon:BAAANQADCgcIDwAAAA==.',
Ad='Advacus:BAAANQAECgcICgAAAA==.',
Ag='Agamar:BAAANQADCgcIEwAAAA==.Ageina:BAAANQADCggICAABNQAECgkJFwABADMiAA==.Agnostec:BAAANQADCgEIAQAAAA==.',
Ak='Akrama:BAAANQAECgIIAQAAAA==.',
Al='Alatáriel:BAAANQAECgEIAQAAAA==.Althenot:BAAANQADCgcIDwAAAA==.',
Am='Amari:BAAANQADCgEIAQAAAA==.Amegoracy:BAAANQADCgYICgAAAA==.',
An='Anruu:BAAANQAECgUICAAAAA==.',
Ar='Archolaoch:BAAANQAECgQIBAAAAA==.Arconite:BAAANQADCgQIBQABNQAECgQIBQACAAAAAA==.Arkthurus:BAAANQADCgYIBgAAAA==.',
As='Ashenknight:BAAANQADCgEIAQAAAA==.Ashijin:BAAANQAECgcIDQAAAA==.',
At='Athelos:BAAANQADCgUICQAAAA==.Atroce:BAAANQAECgcICAAAAA==.',
Au='Aura:BAAANQAECgYICgAAAA==.Auxilium:BAAANQADCggIDgAAAA==.',
Aw='Awnen:BAAANQADCggIEQAAAA==.',
Ax='Axkicker:BAAANQAECggIEwAAAA==.',
Ba='Balethar:BAAANQADCggICAABNQAECgUICgACAAAAAA==.Ballador:BAAANQADCgcIDQAAAA==.Balluh:BAAANQAECgIIAgAAAA==.Balzluzzak:BAAANQAECgMIAwAAAA==.Baughter:BAAANQABCgIIAgAAAA==.',
Be='Beetledeww:BAAANQADCgQIBAAAAA==.Beetledont:BAAANQADCgYIBgAAAA==.Beezbonk:BAAANQAECggICAAAAA==.Bellemorte:BAAANQABCgQIBAAAAA==.Bellmage:BAAANQAECgEIAQAAAA==.Bestricer:BAACNQAFFIEPAAIDAAcJVhM5AAB+AgADAAcJVhM5AAB+AgA1AAQKgRsAAgMACQlHI4oBAJgDAAMACQlHI4oBAJgDAAAA.Bevis:BAAANQAECgIIAgABNQAECggIEwACAAAAAA==.',
Bi='Bigmayex:BAAANQAECgUIBwAAAA==.Bilmuri:BAAANQADCgYIBgAAAA==.Bippot:BAAANQAECgcIEAAAAA==.',
Bl='Blackbride:BAAANQADCggICQAAAA==.Bloodybill:BAAANQADCgUIBQAAAA==.Blort:BAAANQADCggICAAAAA==.',
Bo='Bombadormu:BAAANQADCgcIBwAAAA==.Bonezs:BAAANQAECgMIBQAAAA==.',
Br='Bruhkakke:BAAANQAECggIAQABNQAECggICQACAAAAAA==.',
Bu='Bugbear:BAAANQADCgQIBAAAAA==.Bumbly:BAAANQAECgEIAQAAAA==.Bushybrowsy:BAAANQAECgYICgAAAA==.Buttermeupz:BAAANQAECgQIBAAAAA==.Buttsnorkle:BAAANQAECgIIAgAAAA==.',
Ca='Cacho:BAAANQAECgcICwAAAA==.Caothand:BAAANQADCgYIBgAAAA==.',
Cc='Ccyll:BAAANQADCgcIDwAAAA==.',
Ch='Chazandi:BAAANQADCgQIBAABNQAECgcIDgACAAAAAA==.Chexmix:BAAANQAECgUIBQAAAA==.Chomboslice:BAAANQAECgQIBAAAAA==.',
Ci='Cinnamon:BAAANQAECgQIBAAAAA==.',
Cm='Cmil:BAAANQAECgcIEAAAAA==.',
Co='Coffeegin:BAAANQADCgMIAwAAAA==.',
Cr='Crittingbull:BAAANQABCgQIBAAAAA==.Cruiddeath:BAAANQAECgEIAQABNQAECgcIEQACAAAAAA==.',
Cu='Curserodlock:BAAANQAECgcIEQAAAA==.',
Cy='Cyanide:BAAANQADCggIDgAAAA==.',
Da='Dabbinshamin:BAAANQADCgYIBgAAAA==.Dads:BAAANQAFFAIIAgAAAA==.Daedra:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Daillin:BAAANQADCgEIAQAAAA==.Dakadakadaka:BAAANQAECgEIAQAAAA==.Darcdk:BAAANQADCgIIAgABNQAECggIEgACAAAAAA==.Darcevoker:BAAANQADCgcIBwABNQAECggIEgACAAAAAA==.Darcpaladin:BAAANQAECggIEgAAAA==.Darkrune:BAAANQADCgcIEgAAAA==.Darkschneide:BAAANQAECgQIBgAAAA==.Darthtemplar:BAAANQAECgUIBQAAAA==.',
De='Deckaye:BAAANQADCgYICwABNQADCgcIDQACAAAAAA==.Demodorn:BAAANQAECggIEwAAAA==.Demyst:BAAANQAECgcIEQAAAA==.Dewwarrior:BAAANQADCgUICAAAAA==.Dezeraz:BAEANQAECgYIBgABNQAFFAEIAQACAAAAAA==.',
Dh='Dhecaye:BAAANQADCgcIDQAAAA==.',
Di='Disengage:BAAANQAECgQIBAABNQAECgcIEAACAAAAAA==.',
Do='Dohdan:BAAANQADCgUIBwAAAA==.Donkey:BAAANQAECgUIBQAAAA==.Donmega:BAAANQADCgYIDgAAAA==.Dougalleone:BAAANQAECgcIEQAAAA==.',
Dr='Drekkwarr:BAAANQADCgQICAABNQAECgUIBQACAAAAAA==.Drentalth:BAAANQADCgEIAQAAAA==.Drezzakzdh:BAAANQAECgYICAAAAA==.Drezzakzz:BAAANQADCgUIBgABNQAECgYICAACAAAAAA==.',
Du='Dugren:BAAANQAECgIIAQAAAA==.',
Ek='Ekaterin:BAAANQAECgYIDQAAAA==.',
El='Elaidine:BAAANQAECgQIBAAAAA==.Electraknub:BAAANQADCgEIAQAAAA==.Electroh:BAAANQAECgQICAAAAA==.',
Ev='Evion:BAAANQADCggIEAAAAA==.',
Fa='Falconsha:BAAANQADCgcIEQAAAA==.Fattynattyy:BAAANQADCgYIBgAAAA==.',
Fi='Fiercia:BAAANQAECgQIBwABNQAECggIEgACAAAAAA==.Firefrost:BAAANQAECgcIDwAAAA==.Firescrotum:BAAANQAECgUIBwAAAA==.',
Fl='Flashquinaz:BAAANQADCgYIBgAAAA==.',
Fo='Fourimborniy:BAAANQAECgUICQAAAA==.',
Fr='Frenzi:BAAANQADCgUIBQAAAA==.',
Fu='Fundipme:BAAANQADCgcIDAABNQAECgkJFwAEAKUgAA==.',
['Fá']='Fáelen:BAAANQAECgcICQAAAA==.',
Ga='Galasmina:BAAANQADCgYIDQAAAA==.Galaxius:BAAANQADCgEIAQABNQAECgQIBQACAAAAAA==.Garm:BAAANQAECgQIBAAAAA==.Gavinrad:BAAANQAECgEIAQAAAA==.',
Ge='Gep:BAAANQADCggIDQABNQAECgIIAgACAAAAAA==.',
Gh='Ghostshadow:BAAANQAECgIIAgAAAA==.',
Gi='Girthfury:BAAANQAECggICQAAAA==.',
Gn='Gnew:BAAANQADCgUICgAAAA==.Gnumchuck:BAAANQAECgIIAgAAAA==.',
Go='Goat:BAAANQAECgMIAwAAAA==.Goku:BAAANQAECgcICQAAAA==.Goodman:BAAANQAECgEIAQAAAA==.Goom:BAAANQADCgIIAgABNQAECgkJFwADABQeAA==.Goomei:BAABNQAECoEXAAIDAAkJFB7QBQDgAgADAAkJFB7QBQDgAgAAAA==.Goomkin:BAAANQAECggIEgABNQAECgkJFwADABQeAA==.Gordanramsey:BAAANQADCgUIBQAAAA==.Gorok:BAAANQADCgYIBgAAAA==.',
Gr='Gravymonk:BAAANQAECgQIBAAAAA==.Greatbooty:BAAANQAECgEIAQAAAA==.Gremmi:BAAANQADCgYIBgAAAA==.Grombeefdal:BAAANQADCgUIBQAAAA==.Groundbeéf:BAAANQAECggIEgAAAA==.Grovoath:BAAANQADCgYIBgAAAA==.',
Gu='Gurthon:BAAANQADCggIDwAAAA==.',
Ha='Halligan:BAAANQADCggIDwAAAA==.Hallowfear:BAAANQAECgQIBAAAAA==.Handadinite:BAAANQADCgUICAAAAA==.Handysummons:BAAANQAECgQIBgAAAA==.Harie:BAAANQADCggIFAAAAA==.Hawtsoss:BAAANQABCgQIBwAAAA==.',
He='Hein:BAAANQAECgEIAQAAAA==.Heiny:BAAANQAECgcICwAAAA==.Heinyheinyho:BAAANQADCgMIBAABNQAECgcICwACAAAAAA==.',
Ho='Holeybeef:BAAANQADCgYICQAAAA==.Holymoly:BAAANQADCgMIAQABNQAECgcIDwACAAAAAA==.Holynoodles:BAAANQAECgQIBQAAAA==.Holytest:BAAANQAECgcIDwAAAA==.Hoofmetoo:BAAANQAECgEIAgAAAA==.Howboudah:BAAANQADCgcIBwAAAA==.',
Hu='Hulzar:BAAANQAECgQIBAAAAA==.',
Hy='Hypocrisy:BAAANQAECggIBwAAAA==.',
['Hô']='Hôlyblight:BAAANQAECgcIDgAAAA==.',
Id='Idotyouto:BAAANQADCgcIBwAAAA==.',
Il='Ilbryen:BAAANQADCgYICgABNQAECgcIEQACAAAAAA==.Illaam:BAAANQADCggIDAAAAA==.Illidrag:BAAANQAECgYICAAAAA==.',
Im='Immørtlzed:BAABNQAFFIEGAAIFAAUJyB+7AAD2AQAFAAUJyB+7AAD2AQAAAA==.',
In='Insurion:BAAANQAECgEIAQAAAA==.Invective:BAAANQADCgIIAgAAAA==.',
Iz='Izzyumi:BAAANQADCgYIBgAAAA==.',
Ja='Jarizard:BAABNQAECoEYAAMGAAkJ3Q/CCwArAgAGAAkJ3Q/CCwArAgAHAAEJ8wfEIgA4AAAAAA==.Jarrie:BAAANQADCgcIBwAAAA==.Jassar:BAAANQAECgEIAgAAAA==.Jaxek:BAAANQAECgUICAAAAA==.Jaxs:BAABNQAECoEWAAIFAAkJtRS1EQCHAgAFAAkJtRS1EQCHAgAAAA==.Jaylen:BAAANQAECgQIBQAAAA==.Jaymo:BAAANQAECgEIAQAAAA==.',
Je='Jebke:BAAANQADCggIDgAAAA==.',
Jo='Jopha:BAAANQAECggIEgAAAA==.Jophr:BAAANQADCgYICgABNQAECggIEgACAAAAAA==.',
Jp='Jpbruiser:BAAANQAECgcIDwAAAA==.',
Ju='Jumpndeath:BAAANQAECgcIEQAAAA==.Jumpnpray:BAAANQAECgQIBAABNQAECgcIEQACAAAAAA==.Justgetme:BAAANQAECgUICgAAAA==.',
Ka='Kaan:BAAANQADCgEIAQAAAA==.Kaariel:BAAANQADCgYIBgAAAA==.Kabo:BAAANQAECggIDgAAAA==.Kagger:BAAANQAECgEIAQAAAA==.Kardoroth:BAAANQAECgYIDAAAAA==.Karîba:BAAANQAECggIEgAAAA==.',
Ke='Keld:BAEANQADCggICwAAAA==.Kellienna:BAAANQAECgMIBAAAAA==.Kelsaz:BAAANQAECgcIEAAAAA==.Kelshock:BAAANQAECgEIAQAAAA==.Kelsi:BAAANQAECgYICAAAAA==.Kenný:BAAANQADCgcICQAAAA==.Kerrìgàn:BAAANQAFFAEIAQAAAA==.Kestral:BAAANQAECgcICgAAAA==.',
Kh='Khalisi:BAAANQAECgEIAgAAAA==.',
Ko='Kookiie:BAAANQAECggIEgAAAA==.Kosian:BAAANQADCgUIBwABNQAECgcIDgACAAAAAA==.Kosigan:BAAANQADCgUIBQABNQAECgYIDQACAAAAAA==.',
Kr='Krepuscular:BAAANQAECgMIAwAAAA==.Kryptiq:BAAANQAECgcIEQAAAA==.',
La='Larielin:BAAANQADCgYIBgAAAA==.Larra:BAAANQAECgcIEQAAAA==.',
Le='Lemondonut:BAAANQADCgUIBQAAAA==.Levitas:BAAANQAECgQIBgAAAA==.Leyron:BAAANQADCgQIBAABNQAECgMIBAACAAAAAA==.',
Li='Likkhan:BAAANQAECgEIAQAAAA==.',
Lo='Lockdragoon:BAAANQABCgIIBAAAAA==.Logics:BAAANQAECgcIDAAAAA==.Longsham:BAAANQADCgQIBAAAAA==.Lostmyvigor:BAAANQAECgQICAAAAA==.Lostvoker:BAAANQAECgcIEQAAAA==.Lovespell:BAAANQAECgMIBQAAAA==.',
Lu='Lucarad:BAAANQAECgUIBgAAAA==.Lucivia:BAAANQAECgIIAgAAAA==.Lumafist:BAAANQAECgUICAAAAA==.Lunär:BAAANQADCgUIBQAAAA==.',
['Lè']='Lènneth:BAAANQAECgUICAAAAA==.',
Ma='Maddelyn:BAAANQAECggIEgAAAA==.Magicdaddy:BAAANQADCgEIAQAAAA==.Majaer:BAAANQADCgYIBgAAAA==.Mapp:BAAANQAECgQIBAAAAA==.Mashanu:BAAANQAECgcIDQAAAA==.Mashpriest:BAAANQADCgIIAgAAAA==.Mazur:BAAANQAECgUICQAAAA==.',
Mc='Mcmonkton:BAAANQADCgIIAgAAAA==.',
Me='Meanssa:BAEANQAECgcIDgAAAA==.Megamaxamx:BAAANQADCgIIAgAAAA==.Melaan:BAAANQAECgEIAQAAAA==.',
Mi='Misosalty:BAAANQAECgQICQAAAA==.',
Mo='Mohjito:BAAANQAECgQIBgAAAA==.Monica:BAAANQAECgEIAQAAAA==.Mooshanu:BAAANQABCgMIBAABNQAECgcIDQACAAAAAA==.Morguth:BAAANQAECgYICgAAAA==.Moripriest:BAAANQAECggIDwAAAA==.',
Mu='Musclewizard:BAAANQAECgQIBAAAAA==.',
My='Myrthael:BAAANQADCgUIBQAAAA==.Mythiks:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.',
['Mï']='Mïlo:BAAANQAECgQIBQAAAA==.',
Na='Nancybrew:BAAANQAECgUIBQAAAA==.',
Ne='Nesqwik:BAAANQADCggIEQAAAA==.Nevan:BAAANQAECgQIBAAAAA==.',
Ni='Nidalee:BAAANQAECgEIAQAAAA==.Nineball:BAAANQAECgIIAgAAAA==.Niyx:BAAANQADCgcICwAAAA==.',
No='Noochallange:BAAANQAECgEIAQAAAA==.Norex:BAAANQAECgcIEQAAAA==.',
Ny='Nylariaa:BAAANQADCgYIBgAAAA==.',
Ol='Oldmagic:BAAANQAECgEIAQAAAA==.',
Oo='Ooglaboogla:BAAANQAECgMIBAAAAA==.',
Or='Orbutt:BAAANQADCgYICgAAAA==.Orillian:BAAANQADCgYIBwAAAA==.',
Ov='Overtime:BAAANQADCgcICwAAAA==.',
Pa='Pabons:BAAANQADCgQIBwAAAA==.Paddlin:BAAANQAECgUIBgAAAA==.Panzeria:BAAANQAECggIEgAAAA==.Pawsome:BAAANQAECgUIBQAAAA==.',
Pi='Pixel:BAAANQAECgEIAgAAAA==.',
Pr='Proowee:BAAANQAECgcIDAAAAA==.Propayne:BAAANQADCggICAAAAA==.',
Pu='Pukebreath:BAAANQADCgEIAQAAAA==.Putridvigor:BAAANQAECgQIBQAAAA==.',
['Pä']='Pälii:BAAANQAECgEIAQAAAA==.',
Ra='Ramaan:BAAANQAECgIIAgAAAA==.Rastaa:BAAANQAECgEIAQAAAA==.Ravette:BAAANQAECgEIAQAAAA==.Ravissante:BAAANQAECgEIAQAAAA==.Rawranator:BAAANQAECgIIAgAAAA==.',
Rh='Rhonis:BAAANQADCgEIAQAAAA==.',
Ri='Ricksancheez:BAAANQADCgUIBQAAAA==.',
Ro='Ronnycoleman:BAAANQADCgIIAgAAAA==.',
Sa='Safehaven:BAAANQADCggIEQAAAA==.Samwìse:BAAANQAECgcIEgAAAA==.Sarranidan:BAAANQAECgQIBAABNQAECgcIDgACAAAAAA==.Sathelyn:BAAANQADCgcIBwABNQAECgcIEQACAAAAAA==.',
Sc='Scatman:BAAANQADCgUIBQAAAA==.Scire:BAAANQADCggIFQAAAA==.Scopenrage:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.',
Se='Sedontas:BAAANQADCggIFAAAAA==.Senggolbacok:BAAANQADCgQIBAAAAA==.Serengenuity:BAAANQAECggIEgAAAA==.',
Sh='Shark:BAAANQAECgcIEAAAAA==.Sheera:BAAANQADCgEIAQAAAA==.Shiggyll:BAAANQAECgEIAQABNQAECgcIDwACAAAAAA==.Shizzo:BAAANQADCgQIBAAAAA==.Shockin:BAAANQAECgYIBwAAAA==.Shootin:BAAANQAECgIIAgAAAA==.Shypoke:BAAANQABCgEIAQAAAA==.',
Si='Sifting:BAAANQAECgUIBwAAAA==.Sinswrath:BAAANQAECggIEgAAAA==.',
Sk='Skidxx:BAAANQADCgYIDQAAAA==.Skygnome:BAAANQAECggIEAAAAA==.',
Sl='Slaye:BAAANQAECgQIBAAAAA==.Slimjjim:BAAANQAECgQIBQAAAA==.',
Sm='Smakaho:BAAANQADCgcICwAAAA==.Smores:BAAANQADCgEIAQABNQAECgkJFwAIAJsmAA==.',
Sn='Sneakyteeth:BAAANQAECgUICAAAAA==.',
So='Songi:BAAANQAECgcIDwAAAA==.Soulwhisper:BAAANQAECggIEgAAAA==.',
Sp='Spanda:BAABNQAECoEXAAIJAAgJfBcwBQA3AgAJAAgJfBcwBQA3AgAAAA==.Sparrkel:BAAANQAECgQIBAAAAA==.Splagzhul:BAAANQADCgYIBgAAAA==.Splendi:BAAANQAECgMIAwABNQAECggIFwAJAHwXAA==.Sprogg:BAAANQAECgEIAQAAAA==.Spyropaly:BAAANQAECgYIEAAAAA==.Spyroshaman:BAAANQADCgUICQABNQAECgYIEAACAAAAAA==.',
St='Stampede:BAAANQADCggICAAAAA==.Stormsinger:BAAANQAECgUICAAAAA==.',
Su='Sugarblast:BAAANQAECgcIEgAAAA==.Summonuber:BAAANQAECgIIAQAAAA==.Suou:BAAANQAECgcIEQAAAA==.',
Sy='Sylint:BAAANQADCgYICwAAAA==.Sylliseas:BAAANQADCgYIBgAAAA==.',
Ta='Tandaley:BAAANQADCgQIBQABNQAECgUICAACAAAAAA==.Tanthyr:BAAANQADCgEIAQAAAA==.',
Te='Testme:BAAANQADCgQIBAAAAA==.Textaco:BAAANQADCgEIAQAAAA==.',
Th='Thedevilssin:BAAANQAECgIIAwAAAA==.Theodas:BAAANQAECgQIBAAAAA==.Thiccgnome:BAAANQADCggIEAAAAA==.Thiccthighs:BAAANQAECgEIAQAAAA==.Thirdlegolas:BAAANQAECgEIAQAAAA==.Thuuros:BAAANQAECgUIBwAAAA==.',
Ti='Tirent:BAAANQAECgQIBQAAAA==.',
To='Tokenbeef:BAAANQAECgEIAQAAAA==.Tokenshaman:BAAANQAECgMIBAAAAA==.Toxicdk:BAAANQAECgYICgAAAA==.Toxicshamy:BAAANQADCggIDgABNQAECgYICgACAAAAAA==.',
Tr='Traylay:BAAANQAECgcIEQAAAA==.Trixaintime:BAAANQADCgcIBwAAAA==.Trommel:BAAANQADCgYIBgAAAA==.Trèè:BAAANQADCgMIBQAAAA==.',
Tt='Ttocs:BAAANQAECggIEwAAAA==.',
Tu='Tujori:BAAANQAECggIEgAAAA==.',
Tw='Twherk:BAAANQAECgcIBgABNQAECggICQACAAAAAA==.Twoeye:BAAANQADCgYIBgAAAA==.',
['Tü']='Tüyria:BAAANQADCggICAAAAA==.',
Ug='Uglydorf:BAAANQAECgQIBQAAAA==.',
Us='Ustoo:BAAANQAECgQIBAAAAA==.',
Va='Vaeros:BAAANQAECgEIAQAAAA==.Variana:BAAANQAECgEIAQAAAA==.',
Ve='Vekz:BAAANQAECgUIBwAAAA==.Veles:BAAANQADCggICAAAAA==.Velytia:BAAANQAECgQIBgAAAA==.Vexøs:BAAANQADCggICAAAAA==.',
Vi='Vitiliga:BAAANQAECgEIAQAAAA==.',
Wa='Wasteofpants:BAAANQAECgUIBwAAAA==.',
Wh='Whîrly:BAAANQADCgIIAgAAAA==.',
Wo='Wolf:BAAANQAECgIIAgAAAA==.',
Wt='Wtfheal:BAAANQAECgQICgABNQAECggICQACAAAAAA==.',
Wu='Wumbology:BAAANQADCgMIAwAAAA==.',
['Wà']='Wàrrior:BAAANQADCgEIAQAAAA==.',
Ya='Yamashaman:BAAANQAECgQIBwABNQAECgYIDQACAAAAAA==.Yardgnome:BAAANQADCgMIAwAAAA==.',
Yu='Yuna:BAAANQAECgQIBAAAAA==.',
Za='Zacheris:BAAANQADCgYIBgAAAA==.Zafod:BAAANQADCgUICAAAAA==.Zamasu:BAAANQADCgcIEQAAAA==.Zapped:BAAANQADCggICAAAAA==.Zaszadin:BAEANQAECgUIBQAAAA==.',
Ze='Zekt:BAAANQADCgcICQAAAA==.Zeltron:BAAANQADCgUICgAAAA==.Zerax:BAAANQAECgEIAQAAAA==.',
Zi='Zira:BAAANQAECgIIAgAAAA==.',
Zo='Zombidruid:BAAANQADCgMIAwAAAA==.Zoìdberg:BAAANQAFFAEIAgAAAA==.',
Zs='Zshot:BAAANQAECgQIBAAAAA==.',
Zu='Zubzer:BAAANQADCgYIBgAAAA==.',
Zz='Zzor:BAABNQAECoEYAAIKAAkJ6iELDgBMAwAKAAkJ6iELDgBMAwAAAA==.',
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
