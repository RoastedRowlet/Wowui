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

local lookup = {'Evoker-Preservation','Priest-Holy','Priest-Shadow','Priest-Discipline','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Unknown-Unknown','Druid-Feral','Shaman-Elemental','Mage-Frost','DeathKnight-Frost','DeathKnight-Unholy','Warrior-Arms','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Devourer','Shaman-Restoration','Mage-Arcane','Rogue-Assassination','Monk-Mistweaver','Paladin-Holy',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abnee:BAAANQADCgYICQAAAA==.',
Ad='Adowyrm:BAACNQAFFIEHAAIBAAQKihLABgBPAQABAAQKihLABgBPAQA1AAQKgSAAAgEACQpGIJIEAEADAAEACQpGIJIEAEADAAAA.Adrielle:BAAANQADCggJDQAAAA==.',
Ai='Airali:BAAANQAECgYIEgAAAA==.Airedale:BAAANQAECgMJBAAAAA==.',
Ak='Akairo:BAACNQAFFIEFAAICAAMKPxxLDAASAQACAAMKPxxLDAASAQA1AAQKgSUABAIACQrfIuoDAIkDAAIACQrfIuoDAIkDAAMAAwqGDRM+AKgAAAQAAQo1AWohACEAAAAA.',
Al='Alexanderlx:BAAANQAECggIBQAAAA==.Aleybobwa:BAAANQAECgcJEQAAAA==.Algren:BAAANQADCgYIBgAAAA==.Althalas:BAAANQADCgQIBAAAAA==.',
An='Andramedae:BAAANQAECgYJCwAAAA==.Andrio:BAAANQADCgMJAwAAAA==.Angyavocado:BAABNQAECoEbAAMFAAkKGBpOAwCoAgAFAAgKExxOAwCoAgAGAAMKWgsVJACmAAAAAA==.Antithanatos:BAAANQABCgQICAAAAA==.',
Ao='Aolus:BAABNQAECoEeAAIHAAgK2RobHACSAgAHAAgK2RobHACSAgAAAA==.',
Ap='Apoliis:BAAANQADCggIDQAAAA==.Apollyon:BAAANQAECgEIAQAAAA==.',
Ar='Arcaina:BAAANQADCgcIAgAAAA==.Archis:BAAANQAECgcIDQAAAA==.Arcidaes:BAEANQAECgQIBgAAAA==.Arez:BAAANQADCgEJAQABNQAECgYJDQAIAAAAAA==.',
As='Astryd:BAAANQAECgIIAwAAAA==.Asurna:BAAANQAECgIIAgAAAA==.',
At='Athlon:BAAANQAECgEIAQAAAA==.',
Au='Aurellia:BAAANQADCgYIBgAAAA==.',
Aw='Awake:BAAANQADCgcIBwAAAA==.Awooga:BAAANQAFFAEIAQAAAA==.',
Az='Azaekho:BAAANQADCgUIBQAAAA==.Azalet:BAAANQADCgQIAwAAAA==.',
Ba='Babysharrk:BAAANQADCgUJBQABNQAECggIHAAJABQcAA==.Baeyorn:BAAANQADCgEIAQAAAA==.Bajablaster:BAAANQAECgIIAgAAAA==.Baliw:BAAANQAECgcJEgAAAA==.Balto:BAAANQADCgQIBAAAAA==.Bandoliers:BAAANQAECgQIBwAAAA==.',
Bb='Bbl:BAEBNQAECoEbAAIKAAkKkxYXIgChAgAKAAkKkxYXIgChAgAAAA==.',
Bc='Bchung:BAABNQAECoEcAAILAAgKeB/DAgDIAgALAAgKeB/DAgDIAgAAAA==.',
Be='Bela:BAAANQADCggJDQAAAA==.Belathor:BAAANQADCgYIBgABNQAECgIIAgAIAAAAAA==.Bertus:BAACNQAFFIEIAAMMAAQK2CLbAQCgAQAMAAQKtSLbAQCgAQANAAIKBiHxBgDLAAA1AAQKgRkAAw0ACQrZJJQGAHkDAA0ACQq9JJQGAHkDAAwABgpRIZIhAOsBAAAA.',
Bh='Bhain:BAAANQAECggIDwAAAA==.',
Bi='Bieorne:BAAANQAECgQIBgAAAA==.',
Bl='Blikefire:BAAANQADCgEIAQAAAA==.Bloodwrath:BAAANQADCgQICQAAAA==.',
Bo='Boondocks:BAAANQAECgYJCwAAAA==.Bottomx:BAAANQAECgQJBQAAAA==.',
Br='Braca:BAAANQAECgUICQAAAA==.Bread:BAAANQADCggIEgAAAA==.Brielle:BAAANQAECgYIDAAAAA==.Brimmnin:BAAANQADCgQIBAAAAA==.Brokenbranch:BAAANQAECgEIAQAAAA==.Brudene:BAAANQAECgQJAgAAAA==.Brynjarr:BAAANQADCgUIBQAAAA==.',
Bu='Bubbletruble:BAAANQAECgEIAQAAAA==.Buddylock:BAAANQADCgEIAQAAAA==.Buffalowings:BAAANQADCgEIAQABNQADCgcIBwAIAAAAAA==.Bullymaguire:BAAANQAECgQIBAABNQAECgkJHQAKANojAA==.',
Ca='Catknipp:BAAANQADCgYJBgAAAA==.',
Ce='Ceromaar:BAABNQAECoEaAAIOAAgK3xA4YgDqAQAOAAgK3xA4YgDqAQAAAA==.',
Ch='Chaindeez:BAAANQAECgEJAQAAAA==.Charge:BAACNQAFFIEJAAIOAAUKYx5vBAD0AQAOAAUKYx5vBAD0AQA1AAQKgSUAAg4ACQpaJvcBAOIDAA4ACQpaJvcBAOIDAAAA.Checkurback:BAAANQAECgIJAgAAAA==.Chewtum:BAAANQADCgMIAwAAAA==.Chimo:BAAANQAECgUICgAAAA==.',
Ci='Cillah:BAAANQABCgEIAQABNQAECgYJCQAIAAAAAA==.',
Co='Cobellex:BAAANQABCgUIBQAAAA==.Cops:BAAANQAECgUJCgAAAA==.',
Cr='Cruubakk:BAAANQADCgIIAgAAAA==.',
Cy='Cy:BAAANQADCggIIQAAAA==.',
Da='Danaconda:BAAANQABCgQIBgABNQAECgEJAQAIAAAAAA==.Darkenergy:BAAANQAECgYICwAAAA==.Darà:BAAANQADCgcIBwABNQAECgIIAgAIAAAAAA==.Dashyll:BAAANQADCggIEgAAAA==.Dazzled:BAAANQADCgcIBwAAAA==.',
De='Deadlegslul:BAAANQAECgUIBQAAAA==.Deathhelix:BAAANQADCgEJAQAAAA==.Deathmono:BAAANQAECgIJAwAAAA==.Deathshark:BAAANQADCgQIBAABNQAECggIHAAJABQcAA==.Demacus:BAAANQAECgIJAwABNQAECgQJDgAIAAAAAA==.Demeter:BAAANQAECgUIDgAAAA==.Devouress:BAAANQADCggJCAAAAA==.',
Dh='Dhracian:BAAANQADCgYIBgAAAA==.',
Di='Dillkiller:BAAANQADCgYJCgAAAA==.Dimeniare:BAAANQADCggIFQAAAA==.Dirgen:BAAANQAECgEIAQAAAA==.Dirtymagic:BAAANQADCggICAAAAA==.',
Do='Docktorwhom:BAAANQADCgQIBAAAAA==.Dookiee:BAAANQADCggIDgAAAA==.Doublenickel:BAAANQAECgYIDgAAAA==.',
Dr='Dragönlöl:BAAANQADCgUJBQAAAA==.Drakkaris:BAAANQAECgIIAgABNQADCggJCAAIAAAAAA==.Drat:BAAANQAECgUICwAAAA==.Drimbarn:BAAANQADCggICAAAAA==.Drustan:BAAANQADCgIIAgABNQAECgcIBwAIAAAAAA==.',
Dy='Dyorna:BAAANQADCgUIBQAAAA==.',
Eb='Ebojager:BAAANQAECgQIBwAAAA==.',
Ed='Eddardstark:BAAANQADCgQIBAAAAA==.',
Ei='Eibon:BAAANQAFFAQIBAAAAA==.',
El='Eldric:BAAANQAECgUIEAAAAA==.Elvispriesty:BAAANQADCggICgAAAA==.Elvymir:BAAANQABCggICQAAAA==.Elwarrioro:BAAANQAECgEIAQABNQAECgkJHgAPAE0dAA==.',
Er='Ere:BAAANQAECgYJDQAAAA==.Erus:BAAANQADCgEIAQAAAA==.',
Es='Eskath:BAAANQAECgMIAwABNQAECgQJBwAIAAAAAA==.Essential:BAAANQAECgcJEwAAAA==.',
Ev='Evavaria:BAAANQAECgMIBQABNQABCgUJBQAIAAAAAA==.Evdoggy:BAAANQAECgYIDgAAAA==.Eveleonoc:BAAANQABCgMIAwAAAA==.',
Ex='Exterminate:BAAANQAECgEIAQAAAA==.',
Fe='Fellina:BAAANQAECgQIBgAAAA==.Felparsnip:BAEANQADCggIDwABNQAECgIJAgAIAAAAAA==.Ferrara:BAACNQAFFIEHAAMQAAQKgx+QCgAEAQAQAAMK7R2QCgAEAQARAAEKQyStFQBsAAA1AAQKgSAAAhAACQqVIhoJABMDABAACQqVIhoJABMDAAAA.',
Fi='Filthi:BAAANQAECgUIBgAAAA==.Fiz:BAAANQADCgYIBgABNQADCggIDwAIAAAAAA==.Fizzbang:BAAANQADCgYICAABNQADCgcIBwAIAAAAAA==.',
Fl='Flandri:BAACNQAFFIEGAAICAAMKfBC8DQD+AAACAAMKfBC8DQD+AAA1AAQKgRwAAgIACQpIIwMIAE8DAAIACQpIIwMIAE8DAAAA.',
Fo='Forehead:BAAANQADCgYJBwAAAA==.Foskins:BAAANQAECgQIBAABNQAECgUICgAIAAAAAA==.',
Fr='Frostednip:BAABNQAECoEaAAMMAAgKhBh4GQA8AgAMAAgKhBh4GQA8AgANAAIKAQbTggBfAAAAAA==.',
Fu='Fuzz:BAAANQADCgUIBQAAAA==.',
Ga='Gabiru:BAABNQAECoEbAAIBAAgKRhugCwCmAgABAAgKRhugCwCmAgAAAA==.Gadreeste:BAAANQADCgQIBAAAAA==.Galnarn:BAACNQAFFIEIAAISAAQK5yBbAQCFAQASAAQK5yBbAQCFAQA1AAQKgSEAAhIACQrjJCMBAKIDABIACQrjJCMBAKIDAAAA.Gambagood:BAAANQAECgIIBgAAAA==.Gank:BAABNQAECoEiAAMSAAkK0CB+BADVAgATAAkKBSD1CgDWAgASAAkKXxx+BADVAgAAAA==.Garjingo:BAAANQADCgEIAQABNQAECgIIAgAIAAAAAA==.Garlicbae:BAAANQADCggIEQAAAA==.Garwulf:BAAANQAECgIIAgAAAA==.',
Ge='Gefaustet:BAAANQAECgYJCwAAAA==.',
Go='Goldenred:BAAANQAECgIIAgAAAA==.',
Gr='Graybrew:BAAANQADCgQJBAAAAA==.Grayes:BAAANQADCggIHAABNQADCgQJBAAIAAAAAA==.Grelin:BAAANQAECgQJDAAAAA==.Grog:BAAANQAECggIAwAAAA==.',
Gu='Gumption:BAAANQADCgMIAwAAAA==.',
Ha='Hail:BAAANQAECgIIAgABNQAECggIEQAIAAAAAA==.Hamshamwhich:BAAANQADCgQIBAABNQADCgcIBwAIAAAAAA==.Harmôny:BAAANQADCgUJCAAAAA==.Hatredno:BAAANQABCggICAAAAA==.Hatredyes:BAAANQAECgYJDgAAAA==.',
He='Helare:BAAANQAECgQICgAAAA==.Helowyn:BAAANQADCggIDAAAAA==.Hexenbane:BAAANQAECgEJAgAAAA==.',
Hy='Hyasin:BAAANQAECgYICAAAAA==.Hype:BAAANQADCgUIBQAAAA==.',
Ic='Ice:BAAANQAECgEJAQABNQAECgEIAgAIAAAAAA==.',
Id='Idlewild:BAEANQABCgQIBAABNQAECgEIAQAIAAAAAA==.',
Ig='Ignazio:BAAANQADCgEIAQAAAA==.',
Ih='Ihorns:BAAANQADCgIIAgAAAA==.',
Ik='Ikedizzy:BAAANQAECgEIAgAAAA==.Ikrys:BAAANQADCggIEwAAAA==.',
Il='Illiae:BAAANQAECgYIEAAAAA==.',
Im='Impactr:BAAANQADCgYIBgAAAA==.',
In='Insecure:BAAANQAECgMIAwAAAA==.',
Io='Ionic:BAAANQAECgYICQAAAA==.',
Is='Issidora:BAAANQAECgIIAgAAAA==.',
Ix='Ix:BAAANQADCgQJBAAAAA==.',
Ja='Jakeakuma:BAAANQAECgYJEAAAAA==.Janeleonoc:BAAANQABCgEJAQAAAA==.Janja:BAAANQABCgIIAgABNQAECgYJCQAIAAAAAA==.Jascob:BAAANQADCgcICAAAAA==.Jaynne:BAAANQADCgUIBwAAAA==.',
Ji='Jimmywhisky:BAAANQADCgIIAgAAAA==.',
Jo='Johnivxx:BAAANQADCggICgAAAA==.',
Ju='Judokeg:BAAANQAECgYIDgAAAA==.',
['Jà']='Jàckblack:BAAANQADCgMJAwAAAA==.',
Ka='Kaashaa:BAABNQAECoEZAAIRAAgKHR3CIQCzAgARAAgKHR3CIQCzAgAAAA==.Kaelsgf:BAABNQAECoEcAAICAAgKexrpKQBXAgACAAgKexrpKQBXAgAAAA==.Kahllan:BAAANQAECgIIAgAAAA==.Kahnigitt:BAAANQADCgMIBQAAAA==.Kataltoholic:BAAANQAECgIIAwAAAA==.Kayhas:BAAANQADCgIIAwAAAA==.Kazarel:BAAANQADCggIDAAAAA==.',
Ke='Kelinïsha:BAAANQADCggIGgAAAA==.',
Kh='Khelina:BAAANQAECgIIBAAAAA==.Khelldyr:BAAANQADCggIGgABNQAECgIIBAAIAAAAAA==.',
Ki='Kiiras:BAAANQADCggIEwAAAA==.Kimbodh:BAABNQAECoEcAAIUAAkKkyFaBQBmAwAUAAkKkyFaBQBmAwAAAA==.Kimoora:BAAANQADCgcIDAAAAA==.Kimshady:BAAANQADCgcICAABNQADCgcIDAAIAAAAAA==.Kirathein:BAAANQADCgcIEQAAAA==.',
Kl='Klefthoof:BAAANQAECgQJDgAAAA==.',
Ko='Kodey:BAAANQAECgIIAgABNQAECgYIEAAIAAAAAA==.',
Kr='Krelon:BAAANQADCgIIAgAAAA==.Krimboz:BAAANQAECgEJAQAAAA==.Krystallight:BAAANQAECgYICwAAAA==.',
La='Lazreki:BAAANQABCgcIBwAAAA==.',
Le='Lechuzón:BAAANQADCgQIBAAAAA==.Legaloas:BAABNQAECoEZAAIRAAgKQhymKACTAgARAAgKQhymKACTAgAAAA==.Lenah:BAAANQADCgMIAwAAAA==.Leondero:BAABNQAECoEYAAIRAAgKZhj5JgCbAgARAAgKZhj5JgCbAgAAAA==.Leroyjenkins:BAAANQADCggJFAAAAA==.',
Li='Lintilla:BAAANQADCgcICAAAAA==.',
Ll='Llevanya:BAAANQAECgYJCwAAAA==.',
Lo='Lofi:BAAANQAECgUIBwAAAA==.Lokkhar:BAAANQAECgEIAQAAAA==.Loredalso:BAAANQAECgMIAwAAAA==.',
Lu='Lubricated:BAAANQAECgIJAwAAAA==.Lucíewilde:BAAANQADCgQIBAAAAA==.',
['Lè']='Lèdrollan:BAAANQAECgcJEgAAAA==.',
Ma='Mageypoo:BAAANQADCggIBgAAAA==.Magicdreams:BAAANQAECgQIBQAAAA==.Mahll:BAAANQAECgIIAgAAAA==.Malmorte:BAAANQADCgYIBgAAAA==.Malorane:BAAANQAECgEIAQAAAA==.Malorix:BAABNQAECoEaAAIKAAgKkRp1JwB+AgAKAAgKkRp1JwB+AgAAAA==.Maléficaa:BAAANQADCgQIBAAAAA==.Materia:BAAANQADCggJIgAAAA==.Maz:BAAANQAECgQJBgAAAA==.',
Mc='Mcflury:BAAANQADCggIDgAAAA==.',
Me='Meatbeef:BAAANQAECgEJAQAAAA==.Meerchi:BAAANQADCggJFgAAAA==.Meknin:BAAANQAECgUICAAAAA==.Meldia:BAAANQADCggICwABNQAECgUJBQAIAAAAAA==.Mesthos:BAAANQAECgEIAQABNQAECgcIBwAIAAAAAA==.',
Mi='Mickieta:BAAANQAECgYJCwAAAA==.Mikalau:BAAANQAECgUJDgAAAA==.Mikaluu:BAAANQADCggJFQAAAA==.Milktide:BAAANQADCgUIBwABNQAECgIIAwAIAAAAAA==.Minishields:BAAANQAECgMJAwAAAA==.Missteek:BAAANQAECgEJAQABNQAECgIIAgAIAAAAAA==.Mistrunner:BAAANQADCgYIBgAAAA==.Mistspell:BAABNQAECoEeAAMCAAgKWhuNIQCFAgACAAgKWhuNIQCFAgADAAYK9RAyJQCEAQAAAA==.',
Mo='Mochacho:BAAANQADCgYIBgABNQAECgUICgAIAAAAAA==.Mognel:BAAANQADCggJIgAAAA==.Mogrungar:BAAANQAECgYJEwAAAA==.Moomootus:BAABNQAECoEkAAIPAAkK/iABFAA3AwAPAAkK/iABFAA3AwAAAA==.Motoraxe:BAABNQAECoEZAAIOAAkKoA/uXQD5AQAOAAkKoA/uXQD5AQAAAA==.',
My='Mystynight:BAAANQADCgUIBgAAAA==.',
Na='Naajin:BAAANQADCgcIDAAAAA==.Nauty:BAAANQABCgYICQAAAA==.',
Ne='Newt:BAAANQADCggIEQAAAA==.',
Ni='Nicegauges:BAEANQAECgIJAgAAAA==.Nightcrest:BAAANQAECgUICAAAAA==.Nightrocks:BAAANQAECgEIAQAAAA==.Nilfgard:BAAANQAECgUICAAAAA==.Nivix:BAAANQADCgQICAAAAA==.',
No='Nordrydsh:BAAANQADCgcIBwABNQADCggICgAIAAAAAA==.',
Nu='Nuhpie:BAACNQAFFIEHAAIOAAMK9hnJDgD9AAAOAAMK9hnJDgD9AAA1AAQKgR4AAg4ACQqrIf0XACgDAA4ACQqrIf0XACgDAAAA.',
Oc='Occultfish:BAAANQAECgIIAgAAAA==.',
Ol='Olimdar:BAACNQAFFIEIAAIVAAQKHhrJBQB9AQAVAAQKHhrJBQB9AQA1AAQKgR0AAhUACQrwIXsFAHkDABUACQrwIXsFAHkDAAAA.',
Oo='Oopositive:BAAANQADCgIJAgAAAA==.',
Or='Oraion:BAAANQAECgQJBwAAAA==.',
Ov='Ovarb:BAAANQAECgIIAwAAAA==.',
Pa='Pallydan:BAAANQAECgIJAgABNQAECgQJBwAIAAAAAA==.Pan:BAAANQADCgYIBgAAAA==.Pathofpain:BAAANQADCgEIAQAAAA==.',
Pe='Peachie:BAAANQAECgQIBAAAAA==.Persicles:BAAANQAECgIJAgAAAA==.',
Pi='Pissedwolf:BAAANQADCgEIAQAAAA==.',
Po='Polong:BAAANQADCgUIBQAAAA==.',
Pr='Prisman:BAAANQADCggICAAAAA==.Proserpìne:BAAANQAECgIJAwAAAA==.',
Pu='Putt:BAAANQADCgYICwAAAA==.',
Qo='Qoolkumquat:BAAANQADCgcIBwAAAA==.',
Qu='Quoril:BAABNQAECoEbAAIWAAkKDhh9UACaAgAWAAkKDhh9UACaAgAAAA==.',
Ra='Radiyra:BAAANQABCgIIAgAAAA==.Rainstormin:BAAANQADCggIGgAAAA==.Raitan:BAAANQAECgQICAAAAA==.Rakarra:BAAANQADCgIIAgAAAA==.Rantah:BAAANQADCgQIBAAAAA==.Rawrstance:BAAANQAECgYJDQABNQADCgcIBwAIAAAAAA==.Razgrize:BAAANQAECgMIAwAAAA==.',
Re='Reilin:BAAANQAECgEIAQAAAA==.Remsham:BAAANQAECgEJAgAAAA==.Renwyck:BAAANQAECgcIBwAAAA==.Reovar:BAAANQABCgQIBAAAAA==.Reovarr:BAAANQADCgIIAgAAAA==.Revengemoon:BAABNQAECoEdAAIPAAgKKh5NMQCSAgAPAAgKKh5NMQCSAgAAAA==.',
Ro='Robane:BAAANQADCgYIEgAAAA==.Rouen:BAAANQADCgUJBgAAAA==.',
Ru='Rubidea:BAAANQAECgMIBAAAAA==.Ruckus:BAEANQAECgEIAQAAAA==.Rude:BAAANQAECgIIAgAAAA==.Ruder:BAAANQADCgEIAQABNQAECgYJDgAIAAAAAA==.Rutabaga:BAAANQADCgIIAgAAAA==.',
Ry='Rythas:BAAANQADCgUIBQAAAA==.',
Sa='Sahranna:BAAANQABCgIIAgAAAA==.Saintanic:BAAANQADCgcIBwAAAA==.Sandkat:BAAANQAECggICQAAAA==.Santalight:BAAANQAECgEIAwABNQAECgcIGwATAMQhAA==.Santamoe:BAABNQAECoEbAAITAAcKxCFlDQCnAgATAAcKxCFlDQCnAgAAAA==.Saraelin:BAAANQAECgMIAwAAAA==.Saray:BAAANQAFFAEJAQAAAA==.Saurelli:BAAANQADCgYICAABNQAFFAMJBQAXAIEUAA==.',
Se='Sedak:BAAANQADCggIHAAAAA==.Seitana:BAAANQABCgQIBAAAAA==.Sevrus:BAAANQADCgYIBgAAAA==.',
Sh='Shadysadie:BAAANQADCgQIAwAAAA==.Shamushamu:BAAANQADCgMIAwAAAA==.Shaqheal:BAAANQADCggIDwAAAA==.Shiftey:BAAANQAECgQJCAAAAA==.Shiftymage:BAAANQAECgQIBwABNQAECgQJCAAIAAAAAA==.Shirtles:BAAANQADCgcIDQAAAA==.Shockandmoo:BAAANQADCgUIBQABNQAECgQIBgAIAAAAAA==.Shèp:BAAANQAECgEIAQABNQAECgQICAAIAAAAAA==.',
Si='Sidecake:BAAANQADCgQIBAAAAA==.Singars:BAAANQAECgcIDAAAAA==.Sixseven:BAAANQADCgcJBwAAAA==.Siypra:BAAANQAECgYJCwAAAA==.',
Sk='Skelmir:BAAANQADCgYJCgAAAA==.',
Sn='Snokplaster:BAAANQADCgYIBwAAAA==.Snorri:BAAANQAECgcIEAAAAA==.Snowbvnny:BAAANQAECgEIBAAAAA==.',
So='Soleyn:BAAANQADCgYIBgAAAA==.Soto:BAAANQAECgEJAQAAAA==.Sotosan:BAAANQADCgMIAwAAAA==.',
Sp='Spacechicken:BAAANQADCgEIAQABNQADCggJCAAIAAAAAA==.Sprodage:BAAANQAECgIJAwAAAA==.',
St='Stanil:BAAANQAECgQJBwAAAA==.Steampunkz:BAAANQADCggIGwAAAA==.Strangetame:BAAANQADCgIJAwAAAA==.Striest:BAAANQAECgUJBwAAAA==.Styló:BAAANQAECgEIAgAAAA==.',
Su='Suelly:BAAANQAECgYJCQAAAA==.Suguru:BAAANQAECgIJAgAAAA==.Sularma:BAAANQAECgEJAQAAAA==.Suraschi:BAAANQAECgYIEQAAAA==.',
Sw='Swisscake:BAAANQAECgEIAQAAAA==.Swtmystic:BAAANQAECgIJAgAAAA==.',
Sy='Sygneus:BAAANQABCgQIBAAAAA==.Sylain:BAAANQADCggJCQABNQAECgQIBwAIAAAAAA==.',
Ta='Taiani:BAAANQABCgMIAwAAAA==.Taldrin:BAAANQADCgMIAwAAAA==.Tallinor:BAAANQAECgMIBAAAAA==.Tannatax:BAAANQAECgQIBgAAAA==.Tashah:BAAANQADCgUJBgAAAA==.',
Te='Teamspidey:BAAANQADCgMIAwABNQADCgUIBQAIAAAAAA==.Terminator:BAAANQADCgYIDAAAAA==.',
Th='Thewhitness:BAAANQAECgIJAwAAAA==.Thewretch:BAAANQAECgQIBgAAAA==.Thumpthump:BAAANQAECgIJAgAAAA==.Thunderkiss:BAEANQADCgUICgABNQAECgEIAQAIAAAAAA==.',
Ti='Tindoranis:BAAANQADCgIIAgAAAA==.',
To='Toothguy:BAAANQADCgMIAwAAAA==.Toscus:BAAANQADCgMIAwAAAA==.Totemii:BAAANQADCgYIBgAAAA==.',
Tr='Tradewarrior:BAAANQAECgYIBwAAAA==.Trayth:BAAANQAECggJAQAAAA==.Trevor:BAAANQADCgMIAwAAAA==.Trueheart:BAAANQAECgYIDAAAAA==.',
Ts='Tshark:BAABNQAECoEcAAIJAAgKFBzLBAC4AgAJAAgKFBzLBAC4AgAAAA==.Tsura:BAAANQAECgUJDAAAAA==.',
Tu='Tutatotao:BAAANQABCgQIBgABNQADCgEIAQAIAAAAAA==.',
Ty='Tyduss:BAAANQADCgEJAQAAAA==.',
Un='Unclepeepers:BAABNQAECoEcAAMYAAgKdh7gBgDgAgAYAAgKdh7gBgDgAgATAAgK+RvzDQCeAgAAAA==.Underpowered:BAAANQADCgcIEAAAAA==.Unearthed:BAAANQADCgQIBAAAAA==.',
Ur='Urlän:BAAANQADCgYIBgAAAA==.',
Us='Usirina:BAAANQADCgUJBQABNQAECgYJDgAIAAAAAA==.',
Va='Vaeryn:BAAANQADCgQIBAABNQAECgYIEAAIAAAAAA==.Valhen:BAAANQAECgYIEAAAAA==.Valtar:BAAANQAECgcJEwAAAA==.',
Ve='Velryn:BAAANQADCgUIBgABNQAECgYIEAAIAAAAAA==.',
Vi='Vicsen:BAAANQADCgUIBQAAAA==.Vikaya:BAAANQADCgQIBAAAAA==.Vilevixon:BAAANQAECgYJCwAAAA==.',
Wa='Wagu:BAAANQABCgQIBAAAAA==.Walla:BAAANQADCgIIAgABNQADCgUIBQAIAAAAAA==.Wanlok:BAAANQAECgQJBQAAAA==.Warbuddy:BAAANQAECgEIAQAAAA==.Warmis:BAAANQADCgYICgAAAA==.Warriorlobo:BAAANQAECgQIBgABNQAECgYJCQAIAAAAAA==.Watts:BAAANQAECgcIDgABNQAECgkJGwAWAA4YAA==.',
We='Weez:BAAANQADCgUIBQAAAA==.',
Wi='Wildfang:BAAANQAECgUJDgAAAA==.Wildside:BAAANQAECggIAgAAAA==.',
Xa='Xandronys:BAAANQAECgQICgAAAA==.',
Xe='Xebec:BAAANQAECgQIBAAAAA==.',
Xy='Xyra:BAAANQADCgcJCQAAAA==.',
Ya='Yalik:BAAANQADCgMIAwABNQADCgUIBQAIAAAAAA==.',
Ye='Yeet:BAAANQADCggIDwAAAA==.',
Yz='Yzugzugo:BAAANQAECgcIBwAAAA==.',
Za='Zalandra:BAAANQABCgUIBQAAAA==.Zalckar:BAAANQAECgIJAgAAAA==.Zanos:BAAANQADCgQJBgAAAA==.Zappyending:BAAANQAECgUIBQAAAA==.',
Ze='Zeeva:BAAANQAECgEIAQAAAA==.Zendead:BAAANQADCggIFQAAAA==.',
Zi='Zigar:BAAANQADCgUIBQAAAA==.Zionspartan:BAAANQAECgYJBgAAAA==.',
Zu='Zugzugpriest:BAAANQAECgIJAwAAAA==.Zurokhan:BAABNQAECoEaAAIZAAgKrhpLJgBzAgAZAAgKrhpLJgBzAgAAAA==.',
['Zø']='Zønda:BAAANQAECgYIEQAAAA==.',
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
