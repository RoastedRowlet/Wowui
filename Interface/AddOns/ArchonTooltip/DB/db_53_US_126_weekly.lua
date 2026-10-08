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

local lookup = {'Evoker-Preservation','Paladin-Retribution','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Druid-Restoration','Druid-Balance','Evoker-Augmentation','Evoker-Devastation','Unknown-Unknown','Warrior-Arms','Warrior-Protection','Mage-Arcane','Rogue-Outlaw','Druid-Feral','Shaman-Elemental','Mage-Frost','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Hunter-BeastMastery','DemonHunter-Havoc','Paladin-Protection','Hunter-Marksmanship','Monk-Brewmaster','Monk-Windwalker','Druid-Guardian','DemonHunter-Devourer','Shaman-Restoration','Hunter-Survival','DeathKnight-Blood','Warrior-Fury','Rogue-Assassination','Monk-Mistweaver',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abnee:BAAANQADCgYICQAAAA==.',
Ad='Adowyrm:BAACNQAFFIEQAAIBAAYKMxVhBQDsAQABAAYKMxVhBQDsAQA1AAQKgSQAAgEACQqWINsGAC0DAAEACQqWINsGAC0DAAAA.Adrielle:BAAANQADCggIFQAAAA==.',
Ai='Airali:BAABNQAECoElAAICAAgKyRD1iADhAQACAAgKyRD1iADhAQAAAA==.Airedale:BAAANQAECgUIDAAAAA==.',
Ak='Akairo:BAACNQAFFIEQAAIDAAYKEhyxBAAzAgADAAYKEhyxBAAzAgA1AAQKgTIABAMACQplJEcGAIYDAAMACQplJEcGAIYDAAQABAovF+U+AA0BAAUAAQo1Ae8sACAAAAAA.',
Al='Alexanderlx:BAAANQAECggIDgAAAA==.Aleybobwa:BAABNQAECoEeAAMGAAkKMxeqKwCeAgAGAAkKMxeqKwCeAgACAAUKqxLK3QAmAQAAAA==.Algren:BAAANQADCgYIBgAAAA==.Alindrya:BAAANQABCgYIDQAAAA==.Althalas:BAAANQADCgQIBAAAAA==.',
An='Andramedae:BAABNQAECoEcAAMHAAgKah9NDADsAgAHAAgKah9NDADsAgAIAAEKpwSXpQAqAAAAAA==.Andrio:BAAANQADCgcICgAAAA==.Angyavocado:BAABNQAECoEqAAMJAAkKnR60AgASAwAJAAkK6h20AgASAwAKAAMKLRM/KADNAAAAAA==.Antithanatos:BAAANQAECgIIAgABNQAECgIIAgALAAAAAA==.',
Ao='Aolus:BAABNQAECoEpAAIIAAkKKxzrGADmAgAIAAkKKxzrGADmAgAAAA==.',
Ap='Apoliis:BAAANQAECgMIBQAAAA==.Apollyon:BAAANQAECgEIAQAAAA==.',
Ar='Arcaina:BAAANQADCgcIAgAAAA==.Archis:BAABNQAECoEdAAMMAAgK0BECfAACAgAMAAgK0BECfAACAgANAAYKYgi3IQAQAQAAAA==.Arcidaes:BAEANQAECgYIEgAAAA==.Arez:BAAANQADCgEJAQABNQAECggIHwAOAM0OAA==.',
As='Astryd:BAAANQAECgIIAwAAAA==.Asurna:BAAANQAECgIIAwAAAA==.',
At='Athlon:BAAANQAECgEIAQAAAA==.',
Au='Aurellia:BAAANQADCgYIBgAAAA==.',
Aw='Awake:BAAANQADCgcIBwAAAA==.Awooga:BAABNQAECoEcAAIPAAkKKSGQAQBgAwAPAAkKKSGQAQBgAwAAAA==.',
Az='Azaekho:BAAANQADCgUIBQAAAA==.Azaelleonoc:BAAANQABCgQIBAAAAA==.Azalet:BAAANQADCgQIAwAAAA==.',
Ba='Babysharrk:BAAANQADCgUJBQABNQAECgkJIwAQAO8dAA==.Baeyorn:BAAANQADCgEIAQAAAA==.Bajablaster:BAAANQAECgUICgAAAA==.Baliw:BAABNQAECoElAAIIAAkKYw9KNAAeAgAIAAkKYw9KNAAeAgAAAA==.Balto:BAAANQADCgQIBAAAAA==.Bandoliers:BAAANQAECgQICQAAAA==.Bavmorda:BAAANQADCgUIBQAAAA==.',
Bb='Bbl:BAEBNQAECoElAAIRAAkKHBtlJADVAgARAAkKHBtlJADVAgAAAA==.',
Bc='Bchung:BAABNQAECoEnAAMSAAkKQx/eAwDaAgASAAkKQx/eAwDaAgAOAAgKsg7LuQDtAQAAAA==.',
Be='Bela:BAAANQADCggIDQAAAA==.Belathil:BAAANQAECgcIBwAAAA==.Belathor:BAAANQADCgYIBgABNQAECgIIAwALAAAAAA==.Bertus:BAACNQAFFIEPAAMTAAUKyCGDAgDdAQATAAUKkyGDAgDdAQAUAAQKIyBPCABuAQA1AAQKgSAAAxQACQpSJZQQAB0DABQACQrIJJQQAB0DABMABwqWIwoaAJMCAAAA.',
Bh='Bhain:BAABNQAECoEcAAIRAAkK7Bv8IgDdAgARAAkK7Bv8IgDdAgAAAA==.',
Bi='Bieorne:BAAANQAECgYICgAAAA==.',
Bl='Blikefire:BAAANQADCgEIAQAAAA==.Bloodwrath:BAAANQADCgQICQAAAA==.',
Bo='Bog:BAAANQADCgIIAgAAAA==.Boondocks:BAABNQAECoEeAAQVAAgKDRRAcwDeAQAVAAcKXRJAcwDeAQAWAAMKXxYRFADdAAAXAAEKlAVfewAqAAAAAA==.Bottomx:BAAANQAECgcIEgAAAA==.',
Br='Braca:BAAANQAECgYIEAAAAA==.Bread:BAAANQADCggIEgAAAA==.Brielle:BAABNQAECoEZAAIYAAcKgRD7hwDLAQAYAAcKgRD7hwDLAQAAAA==.Brimmnin:BAAANQADCgQIBAAAAA==.Brokenbranch:BAAANQAECgQIBwAAAA==.Brudene:BAAANQAECgQICwAAAA==.Brynjarr:BAAANQADCgUIBQAAAA==.',
Bu='Bubbletruble:BAAANQAECgIIAwAAAA==.Buddylock:BAAANQADCgEIAQAAAA==.Buffalowings:BAAANQAECgQIBAABNQADCgcIBwALAAAAAA==.Bullymaguire:BAAANQAECgQIBAABNQAFFAUICwARACcaAA==.',
Ca='Catknipp:BAAANQADCgYIBgAAAA==.',
Ce='Ceromaar:BAABNQAECoEpAAIMAAgKGRNLfAACAgAMAAgKGRNLfAACAgAAAA==.',
Ch='Chaindeez:BAAANQAECgEJAQAAAA==.Charge:BAACNQAFFIEVAAIMAAYKfCDTBABcAgAMAAYKfCDTBABcAgA1AAQKgS0AAgwACQpnJjMFAMcDAAwACQpnJjMFAMcDAAAA.Checkurback:BAAANQAECgYIDQAAAA==.Chewtum:BAAANQAECgMIAwAAAA==.Chimo:BAAANQAECgYIEgAAAA==.',
Ci='Cillah:BAAANQABCgEIAQABNQAECgkJHQAOACMZAA==.',
Co='Cobellex:BAAANQABCgUIBQAAAA==.Cops:BAABNQAECoEbAAIGAAcKvR+VMwB6AgAGAAcKvR+VMwB6AgAAAA==.',
Cr='Crimewave:BAAANQAECgcIBgAAAA==.Cruubakk:BAAANQADCgIIAgAAAA==.',
Cy='Cy:BAAANQAECgMIBQAAAA==.',
Da='Danaconda:BAAANQABCgQIBgABNQAECgYICAALAAAAAA==.Darkenergy:BAABNQAECoEeAAIZAAgKPx9aGgCkAgAZAAgKPx9aGgCkAgAAAA==.Darà:BAAANQADCgcIBwABNQAECgYIDQALAAAAAA==.Dashyll:BAAANQAECgUIBQAAAA==.Dazzled:BAAANQADCgcIBwAAAA==.',
De='Deadlegslul:BAAANQAECgcIEgAAAA==.Deathhelix:BAAANQADCgEJAQAAAA==.Deathmono:BAAANQAECgIIAwAAAA==.Deathshark:BAAANQADCgQIBAABNQAECgkJIwAQAO8dAA==.Demacus:BAAANQAECggIBgAAAA==.Demeter:BAABNQAECoEVAAIaAAYKXg4nMgAmAQAaAAYKXg4nMgAmAQAAAA==.Denalli:BAAANQAECgEIAQAAAA==.Devouress:BAAANQAECgEIAQAAAA==.',
Dh='Dhracian:BAAANQADCgYIBgAAAA==.',
Di='Dillkiller:BAAANQADCgcIFwAAAA==.Dimeniare:BAAANQADCggIHAAAAA==.Dirgen:BAAANQAECgYICgAAAA==.Dirtymagic:BAAANQAECgUIBQAAAA==.',
Do='Docktorwhom:BAAANQADCgQIBAAAAA==.Dookiee:BAAANQADCggIDgAAAA==.Doublenickel:BAAANQAECgYIEwAAAA==.',
Dr='Dragönlöl:BAAANQADCgUIBQAAAA==.Drakkaris:BAAANQAECgQIBgABNQAECgEIAQALAAAAAA==.Drat:BAAANQAECgYIDAAAAA==.Drimbarn:BAAANQADCggICAAAAA==.Drustan:BAAANQADCgIIAgABNQAECgcIEAALAAAAAA==.',
Dy='Dyorna:BAAANQADCgcICgAAAA==.',
Eb='Ebojager:BAAANQAECgYIEwAAAA==.',
Ed='Eddardstark:BAAANQADCgQIBAAAAA==.',
Ei='Eibon:BAACNQAFFIEJAAIUAAYKTBYrAwDtAQAUAAYKTBYrAwDtAQA1AAQKgRcAAhQACQo7IAsoAHoCABQACQo7IAsoAHoCAAAA.',
El='Eldric:BAABNQAECoEZAAIOAAYKHQ5I9AB9AQAOAAYKHQ5I9AB9AQAAAA==.Elvispriesty:BAAANQADCggICgAAAA==.Elvymir:BAAANQABCggIDQAAAA==.Elwarrioro:BAAANQAECgEIAQABNQAECgkJJAACAAEfAA==.',
En='Enabran:BAAANQAECgEIAQAAAA==.',
Er='Ere:BAABNQAECoEfAAMOAAgKzQ6XvQDlAQAOAAgKNA2XvQDlAQASAAEKBRmpOQBCAAAAAA==.Erus:BAAANQADCgEIAQAAAA==.',
Es='Eskath:BAAANQAECgQIDAABNQAECgcIHQAOAFEVAA==.Essential:BAABNQAECoEfAAICAAgKKxUzegAHAgACAAgKKxUzegAHAgAAAA==.',
Ev='Evavaria:BAAANQAECgYIEAABNQABCggIEwALAAAAAA==.Evdoggy:BAAANQAECgYIDgAAAA==.Eveleonoc:BAAANQABCgMIAwAAAA==.',
Ex='Exterminate:BAAANQAECgIIAwAAAA==.',
Fe='Fellina:BAAANQAECgQIBgAAAA==.Felparsnip:BAEANQADCggIJQABNQAECggIGwADANEPAA==.Ferrara:BAACNQAFFIEQAAMbAAYKhB85BAAJAgAbAAYKhRk5BAAJAgAYAAEKQyTdJQBnAAA1AAQKgSQAAhsACQqmI48MAAMDABsACQqmI48MAAMDAAAA.',
Fi='Filthi:BAAANQAECgUIBgAAAA==.Fiz:BAAANQADCgYIBgABNQAECgYIBgALAAAAAA==.Fizzbang:BAAANQADCgYICAABNQADCgcIBwALAAAAAA==.',
Fl='Flandri:BAACNQAFFIEOAAIDAAUKvQ8rDQCUAQADAAUKvQ8rDQCUAQA1AAQKgSAAAgMACQpIIyERACoDAAMACQpIIyERACoDAAAA.',
Fo='Forehead:BAAANQADCgYJBwAAAA==.Foskins:BAAANQAECgQIBAABNQAECgYIEgALAAAAAA==.',
Fr='Fraliende:BAAANQADCgYIBgABNQABCggIEwALAAAAAA==.Frostednip:BAABNQAECoEpAAMTAAgKah4RFwCuAgATAAgKah4RFwCuAgAUAAIKAQZmvQBOAAAAAA==.',
Fu='Fuzz:BAAANQADCgUIBQAAAA==.',
Ga='Gabaghoul:BAAANQADCgMIAwAAAA==.Gabiru:BAABNQAECoEkAAIBAAkKARs/CQAAAwABAAkKARs/CQAAAwAAAA==.Gadreeste:BAAANQADCgQIBAAAAA==.Galnarn:BAACNQAFFIERAAIcAAYK2B3+AAAQAgAcAAYK2B3+AAAQAgA1AAQKgSUAAhwACQorJdwBAI4DABwACQorJdwBAI4DAAAA.Gambagood:BAAANQAECgIIBgAAAA==.Gank:BAECNQAFFIEOAAIcAAUKVBifAgCMAQAcAAUKVBifAgCMAQA1AAQKgSgAAxwACQruIG4GAMgCABwACQrfHG4GAMgCAB0ACQoFIIsUAI0CAAAA.Garjingo:BAAANQADCgEIAQABNQAECgUICgALAAAAAA==.Garlicbae:BAAANQAECgMIAwAAAA==.Garrgh:BAAANQADCgcIBwAAAA==.Garwulf:BAAANQAECgUIBwAAAA==.',
Ge='Gefaustet:BAABNQAECoEeAAINAAgKYxOyEgDNAQANAAgKYxOyEgDNAQAAAA==.Gewch:BAAANQADCgEIAQAAAA==.',
Go='Goldenred:BAAANQAECgQICQAAAA==.Goregrim:BAAANQAFFAEIAQAAAA==.',
Gr='Graybrew:BAAANQAECgMIAwAAAA==.Grayes:BAAANQAECgQICAABNQAECgMIAwALAAAAAA==.Grayze:BAAANQADCgUIBQABNQAECgMIAwALAAAAAA==.Grelin:BAAANQAECgQIDQAAAA==.Grizzlydeath:BAAANQAECgEIAQAAAA==.Grog:BAAANQAECggIBgAAAA==.',
Gu='Gumption:BAAANQADCgMIAwAAAA==.',
Ha='Hail:BAAANQAECgIIAgAAAA==.Hamshamwhich:BAAANQADCgQIBAABNQADCgcIBwALAAAAAA==.Harmôny:BAAANQADCgYICQAAAA==.Hatredno:BAAANQADCgQIBAAAAA==.Hatredyes:BAABNQAECoEfAAIeAAgKXRRgFQDMAQAeAAgKXRRgFQDMAQAAAA==.',
He='Helare:BAABNQAECoEaAAIIAAgKKBLXOwDrAQAIAAgKKBLXOwDrAQAAAA==.Helowyn:BAAANQADCggIDAAAAA==.Hexenbane:BAAANQAECgQICAAAAA==.',
Ho='Holyghosst:BAAANQADCgEIAQAAAA==.',
Hy='Hyasin:BAAANQAECgYICAAAAA==.Hype:BAAANQADCgUIBQAAAA==.',
Ic='Ice:BAAANQAECgEIAgABNQAECgMIAgALAAAAAA==.',
Id='Idlewild:BAEANQADCgYIBgABNQAECgQICAALAAAAAA==.',
Ig='Ignazio:BAAANQADCgEIAQAAAA==.',
Ih='Ihorns:BAAANQADCgIIAgAAAA==.',
Ik='Ikedizzy:BAAANQAECgMIAgAAAA==.Ikor:BAAANQAECgUICgAAAA==.Ikrys:BAAANQAECgUIBQAAAA==.',
Il='Ilandrea:BAAANQABCgYIDgAAAA==.Illiae:BAABNQAECoEiAAIRAAgKryOwEQBOAwARAAgKryOwEQBOAwAAAA==.',
Im='Impactr:BAAANQADCgYIBgAAAA==.',
In='Insecure:BAAANQAECgMIBAAAAA==.',
Io='Ionic:BAAANQAECgYICQAAAA==.',
Is='Issidora:BAAANQAECgMICAAAAA==.',
Iv='Ivvy:BAAANQADCgMIBAAAAA==.',
Ix='Ix:BAAANQADCgQJBAAAAA==.',
Ja='Jagtat:BAAANQADCgQIBAAAAA==.Jakeakuma:BAABNQAECoEaAAIVAAgKHAoHiQChAQAVAAgKHAoHiQChAQAAAA==.Janeleonoc:BAAANQABCgEIAQAAAA==.Janja:BAAANQABCgIIAgABNQAECgkJHQAOACMZAA==.Jascob:BAAANQAECgMIAwAAAA==.Jaynne:BAAANQAECgEIAQAAAA==.',
Ji='Jimmywhisky:BAAANQADCgIIAgAAAA==.',
Jo='Johnivxx:BAAANQADCggICgAAAA==.',
Ju='Judokeg:BAABNQAECoEcAAIdAAgKKBYXHwAMAgAdAAgKKBYXHwAMAgAAAA==.',
['Jà']='Jàckblack:BAAANQADCgMIBQAAAA==.',
Ka='Kaandi:BAAANQADCgUIBQAAAA==.Kaashaa:BAABNQAECoEnAAIYAAkKoB49IwDsAgAYAAkKoB49IwDsAgAAAA==.Kaelsgf:BAABNQAECoEoAAIDAAkKURy0GwDrAgADAAkKURy0GwDrAgAAAA==.Kahllan:BAAANQAECgYIDQAAAA==.Kahnigitt:BAAANQADCgMIBQAAAA==.Kataltoholic:BAAANQAECgQICgAAAA==.Kayhas:BAAANQADCgIIAwAAAA==.Kazarel:BAAANQADCggIDAAAAA==.',
Ke='Kelinïsha:BAAANQAECgIIAwAAAA==.Kenf:BAAANQAECgEIAgAAAA==.Kensshaman:BAAANQAECgEIAQAAAA==.Kevinbacon:BAAANQAECgEIAQAAAA==.',
Kh='Khelina:BAAANQAECgQICAAAAA==.Khelldyr:BAAANQADCggIGgABNQAECgQICAALAAAAAA==.',
Ki='Kiiras:BAAANQAECgIIAwAAAA==.Kimbodh:BAACNQAFFIENAAIfAAUKVh6LBADcAQAfAAUKVh6LBADcAQA1AAQKgSYAAh8ACQqRI5EDAJkDAB8ACQqRI5EDAJkDAAAA.Kimoora:BAAANQADCgcIDAAAAA==.Kimshady:BAAANQADCgcICAABNQADCgcIDAALAAAAAA==.Kirathein:BAAANQADCggIFAAAAA==.',
Kl='Klefthoof:BAABNQAECoEeAAMRAAYKjAmToQAiAQARAAYKjAmToQAiAQAgAAUKKQutrADpAAABNQAECggIBgALAAAAAA==.',
Ko='Kodey:BAAANQAECgQICQABNQAECggIHwAXAIATAA==.',
Kr='Krelon:BAAANQADCggIDQAAAA==.Krimboz:BAAANQAECgMIBAAAAA==.Krystallight:BAABNQAECoEcAAIhAAgKuSFuAgD7AgAhAAgKuSFuAgD7AgAAAA==.',
La='Lanwulf:BAAANQADCggIBwAAAA==.Lazreki:BAAANQABCgcIBwAAAA==.',
Le='Lechuzón:BAAANQADCgQIBAAAAA==.Legaloas:BAABNQAECoEnAAIYAAgKTh74NQCmAgAYAAgKTh74NQCmAgAAAA==.Lenah:BAAANQADCgMIAwABNQAECgMIAwALAAAAAA==.Leondero:BAABNQAECoEiAAIYAAkKTBy2IgDvAgAYAAkKTBy2IgDvAgAAAA==.Leroyjenkins:BAAANQADCggIFAAAAA==.Leuthil:BAAANQAECgIIAgABNQAECgEIAQALAAAAAA==.',
Li='Lintilla:BAAANQADCgcICAAAAA==.',
Ll='Llevanya:BAABNQAECoEdAAICAAgKrA1nlgDBAQACAAgKrA1nlgDBAQAAAA==.',
Lo='Lofi:BAAANQAECgYIEQAAAA==.Lokkhar:BAAANQAECgEIAQAAAA==.Loredalso:BAAANQAECgUICwAAAA==.',
Lu='Lubricated:BAAANQAECgQIBwAAAA==.Lucíewilde:BAAANQADCgQIBAAAAA==.Luxon:BAAANQAECgUIBQAAAA==.',
['Lè']='Lèdrollan:BAABNQAECoEnAAMYAAgKBCINHAAOAwAYAAgKBCINHAAOAwAbAAEKwAP8hwAlAAAAAA==.',
Ma='Magicdreams:BAAANQAECgYIDgAAAA==.Mahll:BAAANQAECgIIAgABNQAECggIEgALAAAAAA==.Malmorte:BAAANQADCgYIBgAAAA==.Malorane:BAAANQAECgEIAQAAAA==.Malorix:BAABNQAECoElAAIRAAkK3hlaLgCfAgARAAkK3hlaLgCfAgAAAA==.Maléficaa:BAAANQADCgQIBAAAAA==.Materia:BAAANQAECgIIAwAAAA==.Maz:BAAANQAECgUIBgAAAA==.',
Mc='Mcflury:BAAANQADCggIDgAAAA==.',
Me='Meatbeef:BAAANQAECgYICAAAAA==.Meerchi:BAAANQAECgIIAwAAAA==.Meknin:BAAANQAECgYIEwAAAA==.Meldia:BAAANQAECgYIBwAAAA==.Merlinsdog:BAAANQADCgMIAwAAAA==.Mesmal:BAAANQAECgEIAQABNQAECggIBAALAAAAAA==.Mesthos:BAAANQAECgEIAQABNQAECgcIEAALAAAAAA==.',
Mi='Mickieta:BAABNQAECoEeAAICAAgKMhrcVQBrAgACAAgKMhrcVQBrAgAAAA==.Mikalau:BAABNQAECoEeAAIYAAcKvhr9YQAoAgAYAAcKvhr9YQAoAgAAAA==.Mikaluu:BAAANQADCggIFQAAAA==.Milktide:BAAANQADCgUIBwABNQAECgkJGQAVALgfAA==.Minishields:BAAANQAECgMIBAAAAA==.Missteek:BAAANQAECgIIAwABNQAECgUICgALAAAAAA==.Mistrunner:BAAANQADCgYIBgAAAA==.Mistspell:BAABNQAECoEpAAMDAAkK7BmxJwCtAgADAAkK7BmxJwCtAgAEAAgKMhZVHgAnAgAAAA==.',
Mo='Mochacho:BAAANQADCgYIBgABNQAECgYIEgALAAAAAA==.Mognel:BAAANQAECgIIAwAAAA==.Moomootus:BAABNQAECoEnAAICAAkK/iAxMADqAgACAAkK/iAxMADqAgAAAA==.Motoraxe:BAABNQAECoEbAAIMAAkKCBHgdgAPAgAMAAkKCBHgdgAPAgAAAA==.',
My='Mystynight:BAAANQADCgUIBgAAAA==.',
Na='Naajin:BAAANQADCgcIDAAAAA==.Nabyano:BAAANQAECgEIAQAAAA==.Nauty:BAAANQABCgYICQAAAA==.',
Ne='Newt:BAAANQADCggIEQAAAA==.',
Ni='Nicegauges:BAEBNQAECoEbAAMDAAgK0Q96WQDmAQADAAgK0Q96WQDmAQAEAAcKbQ9qKwCjAQAAAA==.Nightcrest:BAAANQAECgUICAAAAA==.Nightrocks:BAAANQAECgYICQAAAA==.Nilfgard:BAAANQAECgUIDAAAAA==.Nivix:BAAANQADCgQICAAAAA==.Niyyx:BAAANQAECgIIAgAAAA==.',
No='Nordrydsh:BAAANQADCgcIBwABNQAFFAUIBwABAJsKAA==.Noslock:BAAANQABCgYIBgAAAA==.Nosprey:BAAANQABCgEIAQAAAA==.',
Nu='Nuhpie:BAACNQAFFIEPAAIMAAYKpRNpCAAAAgAMAAYKpRNpCAAAAgA1AAQKgSIAAgwACQpVIlArAP0CAAwACQpVIlArAP0CAAAA.',
Ny='Nybish:BAAANQADCgIIAgAAAA==.',
Oc='Occultfish:BAAANQAECgIIAgAAAA==.',
Ol='Olimdar:BAACNQAFFIEMAAIgAAYK+xnZAwAlAgAgAAYK+xnZAwAlAgA1AAQKgR8AAiAACQrwIbYLAE4DACAACQrwIbYLAE4DAAAA.',
Oo='Oopositive:BAAANQADCgIIAgAAAA==.',
Or='Oraion:BAABNQAECoEdAAMOAAcKURUJ2wCrAQAOAAYK6xUJ2wCrAQASAAEKthHCOQBCAAAAAA==.',
Ot='Otimion:BAAANQADCgMIAwAAAA==.',
Ov='Ovarb:BAAANQAECgQIBwAAAA==.',
Pa='Pallydan:BAAANQAECgYIDQABNQAECgcIHQAOAFEVAA==.Pan:BAAANQAECgEIAQAAAA==.Pathofpain:BAAANQADCgEIAQAAAA==.',
Pe='Peachie:BAAANQAECgQICAAAAA==.Persicles:BAAANQAECgIIAwAAAA==.',
Pi='Pissedwolf:BAAANQADCgEIAQAAAA==.',
Po='Polong:BAAANQADCgUIBQAAAA==.Pompouspear:BAAANQADCgcIBwAAAA==.Poutine:BAAANQAECgIIAQAAAA==.',
Pr='Prisman:BAAANQADCggIDgAAAA==.Proserpìne:BAAANQAECgUICgAAAA==.',
Pu='Pummel:BAAANQADCgQIBAAAAA==.Putt:BAAANQADCgYICwAAAA==.',
Qo='Qoolkumquat:BAAANQADCgcIBwAAAA==.',
Qu='Quoril:BAABNQAECoEiAAIOAAkKdBj6bgCKAgAOAAkKdBj6bgCKAgAAAA==.',
Ra='Radiyra:BAAANQABCgIIAgAAAA==.Ragnahr:BAAANQAECggIAwAAAA==.Rainstormin:BAAANQAECgIIAwAAAA==.Raitan:BAAANQAECgYIEAAAAA==.Raivoker:BAAANQADCgQIBAABNQAECgYIEAALAAAAAA==.Rakarra:BAAANQADCgIIAgAAAA==.Rantah:BAAANQADCgQIBAAAAA==.Rawrstance:BAABNQAECoEfAAIiAAgKNA1jTwCXAQAiAAgKNA1jTwCXAQABNQADCgcIBwALAAAAAA==.Razgrize:BAAANQAECgMIAwAAAA==.',
Re='Reilin:BAAANQAECgUIBgAAAA==.Remsham:BAAANQAECgQICAAAAA==.Renwyck:BAAANQAECgcIEAAAAA==.Reovar:BAAANQABCgQIBAAAAA==.Reovarr:BAAANQADCgIIAgAAAA==.Revengemoon:BAABNQAECoEoAAICAAkKnR60KwD8AgACAAkKnR60KwD8AgAAAA==.',
Ro='Robane:BAAANQADCgYIEgAAAA==.Rouen:BAAANQAECgQIBAAAAA==.',
Ru='Rubidea:BAAANQAECgMIBAAAAA==.Ruckus:BAEANQAECgQICAAAAA==.Rude:BAAANQAECgIIBAAAAA==.Ruder:BAAANQADCgEIAQABNQAECggIHwAeAF0UAA==.Rutabaga:BAAANQADCgIIAgAAAA==.',
Ry='Rythas:BAAANQADCgUIBQAAAA==.',
Sa='Safetwo:BAAANQADCgQIBAABNQAECggIHQADAPQYAA==.Sahranna:BAAANQABCgIIAgAAAA==.Saintanic:BAAANQADCgcIBwAAAA==.Sandkat:BAABNQAECoEYAAIjAAkKVBqzBADAAgAjAAkKVBqzBADAAgAAAA==.Santalight:BAAANQAECgEIAwABNQAECggIKAAdAH8iAA==.Santamoe:BAABNQAECoEoAAIdAAgKfyIqDAD8AgAdAAgKfyIqDAD8AgAAAA==.Saraelin:BAAANQAECgMIAwAAAA==.Saray:BAABNQAECoEYAAIYAAkK9yEWFwAnAwAYAAkK9yEWFwAnAwAAAA==.Sarwyn:BAAANQADCgYIBgAAAA==.Saurelli:BAAANQADCgYICAABNQAFFAQIDAAkAPcUAA==.',
Se='Sedak:BAAANQADCggIIQAAAA==.Seitana:BAAANQABCgQIBAAAAA==.Sevrus:BAAANQADCgYIBgAAAA==.',
Sh='Shadysadie:BAAANQAECggIAwAAAA==.Shamushamu:BAAANQADCgMIAwAAAA==.Shaqheal:BAAANQADCggIDwAAAA==.Shiftey:BAAANQAECgUIDAAAAA==.Shiftymage:BAAANQAECgQIBwABNQAECgUIDAALAAAAAA==.Shirtles:BAAANQADCgcIDQAAAA==.Shockandmoo:BAAANQADCgUIBQABNQAECgQIBgALAAAAAA==.Shèp:BAAANQAECgEIAQABNQAECgQICAALAAAAAA==.',
Si='Sidecake:BAAANQADCgQIBAAAAA==.Singars:BAAANQAECgcIEwAAAA==.Sixseven:BAAANQADCgcJBwAAAA==.Siypra:BAABNQAECoEbAAIiAAgKyR0MHQCvAgAiAAgKyR0MHQCvAgAAAA==.',
Sk='Skelmir:BAAANQADCgYJCgAAAA==.',
Sn='Snokplaster:BAAANQADCgYIBwAAAA==.Snorri:BAABNQAECoEgAAIUAAkKnSMzCABvAwAUAAkKnSMzCABvAwAAAA==.Snowbvnny:BAAANQAECgEIBAAAAA==.',
So='Soleyn:BAAANQADCgYIBgAAAA==.Solie:BAAANQAECgIIAgAAAA==.Soto:BAAANQAECgEJAQAAAA==.Sotosan:BAAANQADCgMIAwAAAA==.',
Sp='Spacechicken:BAAANQADCgEIAQABNQAECgEIAQALAAAAAA==.Sprintd:BAAANQADCgUIBQAAAA==.Sprodage:BAAANQAECgUIDQAAAA==.',
St='Stanil:BAAANQAECgQICwAAAA==.Steampunkz:BAAANQAECgEIAQAAAA==.Strangetame:BAAANQADCgMIBAAAAA==.Striest:BAAANQAECgUIBwAAAA==.Styló:BAAANQAECgEIAgAAAA==.',
Su='Suelly:BAABNQAECoEdAAMOAAkKIxnHbACPAgAOAAkKNhbHbACPAgASAAQKmRuyGAAMAQAAAA==.Suguru:BAAANQAECgYICgAAAA==.Sularma:BAAANQAECgEIAQAAAA==.Sunsorrow:BAAANQADCggIDAABNQADCgcIBwALAAAAAA==.Suraschi:BAABNQAECoEcAAIcAAgK9BWXDgDqAQAcAAgK9BWXDgDqAQAAAA==.',
Sw='Swisscake:BAAANQAECgEIAQAAAA==.Swtmystic:BAAANQAECgIIAgAAAA==.',
Sy='Sygneus:BAAANQADCggIDQAAAA==.Sylain:BAAANQADCggICQABNQAECgQIBwALAAAAAA==.Synwav:BAAANQAECggIEwAAAA==.',
Ta='Taiani:BAAANQABCgMIAwAAAA==.Taldrin:BAAANQADCgMIAwAAAA==.Tallinor:BAAANQAECgMIBAAAAA==.Tannatax:BAAANQAECgYIEgAAAA==.Tashah:BAAANQADCgUICgAAAA==.',
Te='Teamspidey:BAAANQADCgMIAwABNQAECgQIBAALAAAAAA==.Tekvet:BAAANQAECggIBAAAAA==.Terminator:BAAANQADCgcIDQAAAA==.',
Th='Thewhitness:BAAANQAECgQIBwAAAA==.Thewretch:BAAANQAECgYIEgAAAA==.Thumpthump:BAAANQAECgYIDQAAAA==.Thunderkiss:BAEANQADCggIFwABNQAECgQICAALAAAAAA==.',
Ti='Tindoranis:BAAANQADCgIIAgAAAA==.',
To='Toothguy:BAAANQADCgMIAwAAAA==.Toscus:BAAANQADCgMIAwAAAA==.Totemii:BAAANQADCgYIBgAAAA==.',
Tr='Tradewarrior:BAABNQAECoEVAAIMAAgKmhotUAB+AgAMAAgKmhotUAB+AgAAAA==.Trayth:BAAANQAECggIBgAAAA==.Trevor:BAAANQADCgMIAwAAAA==.Trueheart:BAAANQAECgYIDAAAAA==.',
Ts='Tshark:BAABNQAECoEjAAIQAAkK7x0DBQAMAwAQAAkK7x0DBQAMAwAAAA==.Tsura:BAAANQAECgYIEgAAAA==.',
Tu='Tutatotao:BAAANQABCgQIBgABNQADCgQIBQALAAAAAA==.',
Ty='Tyduss:BAAANQADCgEJAQAAAA==.',
Un='Unclepeepers:BAABNQAECoEnAAMlAAkKxCDfBABAAwAlAAkKxCDfBABAAwAdAAgK+RsCGQBRAgAAAA==.Underpowered:BAAANQADCgcIEAAAAA==.Unearthed:BAAANQADCgQIBAAAAA==.',
Ur='Urlän:BAAANQADCgYIBgAAAA==.',
Us='Usirina:BAAANQADCgUIBQABNQAECggIHwAeAF0UAA==.',
Va='Vaeryn:BAAANQAECgEIAgABNQAECggIMwAFAH4aAA==.Valhen:BAABNQAECoEzAAQFAAgKfhqDBwDlAQADAAgK5hlsNgBsAgAFAAcKgRaDBwDlAQAEAAMKIgeSVgCAAAAAAA==.Valtar:BAABNQAECoEhAAIgAAkKuCJ3BgCBAwAgAAkKuCJ3BgCBAwAAAA==.',
Ve='Velryn:BAAANQADCgUIBgABNQAECggIMwAFAH4aAA==.',
Vi='Vicsen:BAAANQADCgUIBQAAAA==.Vikaya:BAAANQADCgQIBAAAAA==.Vilevixon:BAABNQAECoEeAAMEAAgKSRsFGQBmAgAEAAgKSRsFGQBmAgAFAAEKvAjQJgAxAAAAAA==.',
Wa='Wagu:BAAANQABCgQIBAAAAA==.Walla:BAAANQADCgIIAgABNQAECgQIBAALAAAAAA==.Wanlok:BAAANQAECgUICwAAAA==.Warbuddy:BAAANQAECgEIAQAAAA==.Warmis:BAAANQADCgYICgAAAA==.Warriorlobo:BAAANQAECgYIEgABNQAECgkJHQAOACMZAA==.Watts:BAABNQAECoEdAAIYAAgKCR5oLQDDAgAYAAgKCR5oLQDDAgABNQAECgkJIgAOAHQYAA==.',
We='Weez:BAAANQADCgUIBQAAAA==.',
Wi='Wildfang:BAABNQAECoEXAAMYAAgKZwnwgQDZAQAYAAgKZwnwgQDZAQAbAAEK0AAcjQAUAAAAAA==.Wildside:BAAANQAECggIBgAAAA==.',
Xa='Xandronys:BAABNQAECoEZAAQWAAgKGRTvBwDyAQAWAAcKmhTvBwDyAQAVAAUKbhDKvAAkAQAXAAEKvgnGcwA0AAAAAA==.',
Xe='Xebec:BAAANQAECgYIDAAAAA==.',
Xy='Xyra:BAAANQADCgcJCQAAAA==.',
Ya='Yalik:BAAANQADCgMIAwABNQAECgQIBAALAAAAAA==.Yalla:BAAANQAECgMIAwAAAA==.',
Ye='Yeet:BAAANQAECgYIBgAAAA==.',
Yz='Yzugzugo:BAAANQAECggIDQAAAA==.',
Za='Zalandra:BAAANQABCgUIBQAAAA==.Zalckar:BAAANQAECgYIDQAAAA==.Zanos:BAAANQADCgYICQAAAA==.Zappyending:BAAANQAECgUIBQAAAA==.',
Ze='Zeeva:BAAANQAECgcICAAAAA==.Zendead:BAAANQAECgYICwAAAA==.',
Zi='Zigar:BAAANQAECgQIBAAAAA==.Zionspartan:BAAANQAECgcIEwAAAA==.',
Zu='Zugzugpriest:BAAANQAECgQIBwAAAA==.Zurokhan:BAABNQAECoEpAAIGAAkKKxxpHwDcAgAGAAkKKxxpHwDcAgAAAA==.',
['Zø']='Zønda:BAABNQAECoEfAAMjAAcKHiOrDgCfAQAMAAUK/yLvlADAAQAjAAQKuiOrDgCfAQAAAA==.',
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
