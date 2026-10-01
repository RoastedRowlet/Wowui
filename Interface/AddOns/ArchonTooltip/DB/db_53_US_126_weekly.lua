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

local lookup = {'Evoker-Preservation','Paladin-Retribution','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Warrior-Arms','Mage-Arcane','Rogue-Outlaw','Druid-Feral','Shaman-Elemental','Mage-Frost','Unknown-Unknown','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Hunter-BeastMastery','Monk-Brewmaster','Monk-Windwalker','Druid-Guardian','Warlock-Demonology','DemonHunter-Devourer','Warlock-Destruction','Shaman-Restoration','DeathKnight-Blood','Rogue-Assassination','Monk-Mistweaver','Warrior-Fury',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abnee:BAAANQADCgYICQAAAA==.',
Ad='Adowyrm:BAACNQAFFIEMAAIBAAUK1xOeBgCdAQABAAUK1xOeBgCdAQA1AAQKgSIAAgEACQqWIK0FADgDAAEACQqWIK0FADgDAAAA.Adrielle:BAAANQADCggIFQAAAA==.',
Ai='Airali:BAABNQAECoEeAAICAAgKBg2UggC9AQACAAgKBg2UggC9AQAAAA==.Airedale:BAAANQAECgQIBwAAAA==.',
Ak='Akairo:BAACNQAFFIEKAAIDAAUKfxexCAC3AQADAAUKfxexCAC3AQA1AAQKgS0ABAMACQpKI8MFAH8DAAMACQpKI8MFAH8DAAQABArEFJg5AAUBAAUAAQo1AfQnACAAAAAA.',
Al='Alexanderlx:BAAANQAECggICgAAAA==.Aleybobwa:BAABNQAECoEaAAMGAAgKKRXLPwAlAgAGAAgKKRXLPwAlAgACAAQKZxJX2gDyAAAAAA==.Algren:BAAANQADCgYIBgAAAA==.Althalas:BAAANQADCgQIBAAAAA==.',
An='Andramedae:BAAANQAECgcIEgAAAA==.Andrio:BAAANQADCgcICgAAAA==.Angyavocado:BAABNQAECoEiAAMHAAkK+RxNAwDOAgAHAAgKhx5NAwDOAgAIAAMKLRO4JADSAAAAAA==.Antithanatos:BAAANQABCgQICAAAAA==.',
Ao='Aolus:BAABNQAECoElAAIJAAgKURzyHgCgAgAJAAgKURzyHgCgAgAAAA==.',
Ap='Apoliis:BAAANQAECgIIAgAAAA==.Apollyon:BAAANQAECgEIAQAAAA==.',
Ar='Arcaina:BAAANQADCgcIAgAAAA==.Archis:BAABNQAECoEXAAIKAAgK0BEIaQAKAgAKAAgK0BEIaQAKAgAAAA==.Arcidaes:BAEANQAECgYIDAAAAA==.Arez:BAAANQADCgEJAQABNQAECggIGAALAIILAA==.',
As='Astryd:BAAANQAECgIIAwAAAA==.Asurna:BAAANQAECgIIAwAAAA==.',
At='Athlon:BAAANQAECgEIAQAAAA==.',
Au='Aurellia:BAAANQADCgYIBgAAAA==.',
Aw='Awake:BAAANQADCgcIBwAAAA==.Awooga:BAABNQAECoEXAAIMAAkKIiC8AQBFAwAMAAkKIiC8AQBFAwAAAA==.',
Az='Azaekho:BAAANQADCgUIBQAAAA==.Azaelleonoc:BAAANQABCgQIBAAAAA==.Azalet:BAAANQADCgQIAwAAAA==.',
Ba='Babysharrk:BAAANQADCgUJBQABNQAECgkJIAANALIdAA==.Baeyorn:BAAANQADCgEIAQAAAA==.Bajablaster:BAAANQAECgQIBgAAAA==.Baliw:BAABNQAECoEdAAIJAAkK7gukNAD4AQAJAAkK7gukNAD4AQAAAA==.Balto:BAAANQADCgQIBAAAAA==.Bandoliers:BAAANQAECgQICQAAAA==.Bavmorda:BAAANQADCgUIBQAAAA==.',
Bb='Bbl:BAEBNQAECoEhAAIOAAkKxRj/IQDKAgAOAAkKxRj/IQDKAgAAAA==.',
Bc='Bchung:BAABNQAECoEjAAMPAAgKeB9bBACkAgAPAAgKeB9bBACkAgALAAcKfw04wQCyAQAAAA==.',
Be='Bela:BAAANQADCggJDQAAAA==.Belathor:BAAANQADCgYIBgABNQAECgIIAwAQAAAAAA==.Bertus:BAACNQAFFIEMAAMRAAUKkyGpAQDoAQARAAUKkyGpAQDoAQASAAIKBiHcDACpAAA1AAQKgRwAAxIACQrcJJQMAC0DABIACQq9JJQMAC0DABEABgpOIq8pAOwBAAAA.',
Bh='Bhain:BAABNQAECoEZAAIOAAkKrhu+HADuAgAOAAkKrhu+HADuAgAAAA==.',
Bi='Bieorne:BAAANQAECgQICAAAAA==.',
Bl='Blikefire:BAAANQADCgEIAQAAAA==.Bloodwrath:BAAANQADCgQICQAAAA==.',
Bo='Boondocks:BAAANQAECgcIEgAAAA==.Bottomx:BAAANQAECgYICwAAAA==.',
Br='Braca:BAAANQAECgUIDgAAAA==.Bread:BAAANQADCggIEgAAAA==.Brielle:BAAANQAECgYIEgAAAA==.Brimmnin:BAAANQADCgQIBAAAAA==.Brokenbranch:BAAANQAECgQIBAAAAA==.Brudene:BAAANQAECgQIBgAAAA==.Brynjarr:BAAANQADCgUIBQAAAA==.',
Bu='Bubbletruble:BAAANQAECgEIAQAAAA==.Buddylock:BAAANQADCgEIAQAAAA==.Buffalowings:BAAANQADCgEIAQABNQADCgcIBwAQAAAAAA==.Bullymaguire:BAAANQAECgQIBAABNQAFFAUICAAOACcaAA==.',
Ca='Catknipp:BAAANQADCgYJBgAAAA==.',
Ce='Ceromaar:BAABNQAECoEiAAIKAAgK+RE0cwDsAQAKAAgK+RE0cwDsAQAAAA==.',
Ch='Chaindeez:BAAANQAECgEJAQAAAA==.Charge:BAACNQAFFIEPAAIKAAYKfR+MAwBWAgAKAAYKfR+MAwBWAgA1AAQKgSkAAgoACQpnJhwDANcDAAoACQpnJhwDANcDAAAA.Checkurback:BAAANQAECgUIBwAAAA==.Chewtum:BAAANQADCgMIAwAAAA==.Chimo:BAAANQAECgYIDAAAAA==.',
Ci='Cillah:BAAANQABCgEIAQABNQAECgcIEAAQAAAAAA==.',
Co='Cobellex:BAAANQABCgUIBQAAAA==.Cops:BAAANQAECgYIEAAAAA==.',
Cr='Crimewave:BAAANQAECgcIBgAAAA==.Cruubakk:BAAANQADCgIIAgAAAA==.',
Cy='Cy:BAAANQAECgMIAwAAAA==.',
Da='Danaconda:BAAANQABCgQIBgABNQAECgIIAwAQAAAAAA==.Darkenergy:BAAANQAECgcIEgAAAA==.Darà:BAAANQADCgcIBwABNQAECgUIBwAQAAAAAA==.Dashyll:BAAANQADCggIEgAAAA==.Dazzled:BAAANQADCgcIBwAAAA==.',
De='Deadlegslul:BAAANQAECgYICwAAAA==.Deathhelix:BAAANQADCgEJAQAAAA==.Deathmono:BAAANQAECgIIAwAAAA==.Deathshark:BAAANQADCgQIBAABNQAECgkJIAANALIdAA==.Demacus:BAAANQAECggIAwAAAA==.Demeter:BAAANQAECgYIDwAAAA==.Denalli:BAAANQABCgIIAgAAAA==.Devouress:BAAANQAECgEIAQAAAA==.',
Dh='Dhracian:BAAANQADCgYIBgAAAA==.',
Di='Dillkiller:BAAANQADCgYIEAAAAA==.Dimeniare:BAAANQADCggIHAAAAA==.Dirgen:BAAANQAECgMIBAAAAA==.Dirtymagic:BAAANQADCggIEAAAAA==.',
Do='Docktorwhom:BAAANQADCgQIBAAAAA==.Dookiee:BAAANQADCggIDgAAAA==.Doublenickel:BAAANQAECgYIEwAAAA==.',
Dr='Dragönlöl:BAAANQADCgUIBQAAAA==.Drakkaris:BAAANQAECgIIAgABNQAECgEIAQAQAAAAAA==.Drat:BAAANQAECgYIDAAAAA==.Drimbarn:BAAANQADCggICAAAAA==.Drustan:BAAANQADCgIIAgABNQAECgcIDgAQAAAAAA==.',
Dy='Dyorna:BAAANQADCgUIBwAAAA==.',
Eb='Ebojager:BAAANQAECgYIDQAAAA==.',
Ed='Eddardstark:BAAANQADCgQIBAAAAA==.',
Ei='Eibon:BAACNQAFFIEGAAISAAUKIhhvAwClAQASAAUKIhhvAwClAQA1AAQKgRUAAhIACQo7IFEbAKYCABIACQo7IFEbAKYCAAAA.',
El='Eldric:BAAANQAECgUIEwAAAA==.Elvispriesty:BAAANQADCggICgAAAA==.Elvymir:BAAANQABCggIDQAAAA==.Elwarrioro:BAAANQAECgEIAQABNQAECgkJIgACAPAdAA==.',
Er='Ere:BAABNQAECoEYAAMLAAgKggsmugDAAQALAAgK6QkmugDAAQAPAAEKBRnUMgBEAAAAAA==.Erus:BAAANQADCgEIAQAAAA==.',
Es='Eskath:BAAANQAECgQICAABNQAECgUIEgAQAAAAAA==.Essential:BAAANQAECgcIEwAAAA==.',
Ev='Evavaria:BAAANQAECgUICgABNQABCggIDQAQAAAAAA==.Evdoggy:BAAANQAECgYIDgAAAA==.Eveleonoc:BAAANQABCgMIAwAAAA==.',
Ex='Exterminate:BAAANQAECgEIAQAAAA==.',
Fe='Fellina:BAAANQAECgQIBgAAAA==.Felparsnip:BAEANQADCggIHQABNQAECgUIDQAQAAAAAA==.Ferrara:BAACNQAFFIEMAAMTAAUKIR/+BgCUAQATAAUK7xf+BgCUAQAUAAEKQyQjHgBpAAA1AAQKgSIAAhMACQpgI0IKABEDABMACQpgI0IKABEDAAAA.',
Fi='Filthi:BAAANQAECgUIBgAAAA==.Fiz:BAAANQADCgYIBgABNQADCggIDwAQAAAAAA==.Fizzbang:BAAANQADCgYICAABNQADCgcIBwAQAAAAAA==.',
Fl='Flandri:BAACNQAFFIEKAAIDAAQKKRKvDQBSAQADAAQKKRKvDQBSAQA1AAQKgR4AAgMACQpII08MADsDAAMACQpII08MADsDAAAA.',
Fo='Forehead:BAAANQADCgYJBwAAAA==.Foskins:BAAANQAECgQIBAABNQAECgYIDAAQAAAAAA==.',
Fr='Frostednip:BAABNQAECoEiAAMRAAgKShnjHQBPAgARAAgKShnjHQBPAgASAAIKAQZGoQBQAAAAAA==.',
Fu='Fuzz:BAAANQADCgUIBQAAAA==.',
Ga='Gabiru:BAABNQAECoEiAAIBAAgKjhwqDAC8AgABAAgKjhwqDAC8AgAAAA==.Gadreeste:BAAANQADCgQIBAAAAA==.Galnarn:BAACNQAFFIENAAIVAAUKjR1hAQC+AQAVAAUKjR1hAQC+AQA1AAQKgSMAAhUACQorJWUBAJwDABUACQorJWUBAJwDAAAA.Gambagood:BAAANQAECgIIBgAAAA==.Gank:BAECNQAFFIEJAAIVAAQKRRrSAgBJAQAVAAQKRRrSAgBJAQA1AAQKgSUAAxUACQrjIGYFAM4CABUACQrSHGYFAM4CABYACQoFIOYPAKoCAAAA.Garjingo:BAAANQADCgEIAQABNQAECgQIBgAQAAAAAA==.Garlicbae:BAAANQADCggIGQAAAA==.Garrgh:BAAANQADCgcIBwAAAA==.Garwulf:BAAANQAECgIIAgAAAA==.',
Ge='Gefaustet:BAAANQAECgcIEgAAAA==.',
Go='Goldenred:BAAANQAECgMIBQAAAA==.',
Gr='Graybrew:BAAANQAECgMIAwAAAA==.Grayes:BAAANQAECgQIBAABNQAECgMIAwAQAAAAAA==.Grelin:BAAANQAECgQJDAAAAA==.Grizzlydeath:BAAANQAECgEIAQAAAA==.Grog:BAAANQAECggIAwAAAA==.',
Gu='Gumption:BAAANQADCgMIAwAAAA==.',
Ha='Hail:BAAANQAECgIIAgAAAA==.Hamshamwhich:BAAANQADCgQIBAABNQADCgcIBwAQAAAAAA==.Harmôny:BAAANQADCgUJCAAAAA==.Hatredno:BAAANQABCggIDwAAAA==.Hatredyes:BAABNQAECoEYAAIXAAgK1xObEADTAQAXAAgK1xObEADTAQAAAA==.',
He='Helare:BAAANQAECgUIDwAAAA==.Helowyn:BAAANQADCggIDAAAAA==.Hexenbane:BAAANQAECgIIBAAAAA==.',
Hy='Hyasin:BAAANQAECgYICAAAAA==.Hype:BAAANQADCgUIBQAAAA==.',
Ic='Ice:BAAANQAECgEJAQABNQAECgEIAgAQAAAAAA==.',
Id='Idlewild:BAEANQADCgYIBgABNQAECgEIAQAQAAAAAA==.',
Ig='Ignazio:BAAANQADCgEIAQAAAA==.',
Ih='Ihorns:BAAANQADCgIIAgAAAA==.',
Ik='Ikedizzy:BAAANQAECgEIAgAAAA==.Ikor:BAAANQAECgUIBQAAAA==.Ikrys:BAAANQADCggIFwAAAA==.',
Il='Ilandrea:BAAANQABCgYIDgAAAA==.Illiae:BAABNQAECoEbAAIOAAcK0iImIgDJAgAOAAcK0iImIgDJAgAAAA==.',
Im='Impactr:BAAANQADCgYIBgAAAA==.',
In='Insecure:BAAANQAECgMIAwAAAA==.',
Io='Ionic:BAAANQAECgYICQAAAA==.',
Is='Issidora:BAAANQAECgIIBQAAAA==.',
Iv='Ivvy:BAAANQADCgMIBAAAAA==.',
Ix='Ix:BAAANQADCgQJBAAAAA==.',
Ja='Jagtat:BAAANQADCgQIBAAAAA==.Jakeakuma:BAABNQAECoEXAAIYAAgKqgkFgQCEAQAYAAgKqgkFgQCEAQAAAA==.Janeleonoc:BAAANQABCgEIAQAAAA==.Janja:BAAANQABCgIIAgABNQAECgcIEAAQAAAAAA==.Jaynne:BAAANQADCgUIBwAAAA==.',
Ji='Jimmywhisky:BAAANQADCgIIAgAAAA==.',
Jo='Johnivxx:BAAANQADCggICgAAAA==.',
Ju='Judokeg:BAABNQAECoEVAAIWAAcK7xZ7HwDaAQAWAAcK7xZ7HwDaAQAAAA==.',
['Jà']='Jàckblack:BAAANQADCgMJAwAAAA==.',
Ka='Kaandi:BAAANQADCgUIBQAAAA==.Kaashaa:BAABNQAECoEfAAIUAAgKWR44LgCjAgAUAAgKWR44LgCjAgAAAA==.Kaelsgf:BAABNQAECoEkAAIDAAgKZBvOKgB/AgADAAgKZBvOKgB/AgAAAA==.Kahllan:BAAANQAECgUIBwAAAA==.Kahnigitt:BAAANQADCgMIBQAAAA==.Kataltoholic:BAAANQAECgMIBgAAAA==.Kayhas:BAAANQADCgIIAwAAAA==.Kazarel:BAAANQADCggIDAAAAA==.',
Ke='Kelinïsha:BAAANQAECgEIAQAAAA==.Kenf:BAAANQAECgEIAgAAAA==.Kensshaman:BAAANQAECgEIAQAAAA==.Kevinbacon:BAAANQADCgQIBAAAAA==.',
Kh='Khelina:BAAANQAECgIIBAAAAA==.Khelldyr:BAAANQADCggIGgABNQAECgIIBAAQAAAAAA==.',
Ki='Kiiras:BAAANQAECgEIAQAAAA==.Kimbodh:BAACNQAFFIEIAAIZAAUKNBnbAwDTAQAZAAUKNBnbAwDTAQA1AAQKgSAAAhkACQrYIiwEAIYDABkACQrYIiwEAIYDAAAA.Kimoora:BAAANQADCgcIDAAAAA==.Kimshady:BAAANQADCgcICAABNQADCgcIDAAQAAAAAA==.Kirathein:BAAANQADCgcIEQAAAA==.',
Kl='Klefthoof:BAAANQAECgQIEQABNQAECggIAwAQAAAAAA==.',
Ko='Kodey:BAAANQAECgMIBQABNQAECggIFwAaAHMRAA==.',
Kr='Krelon:BAAANQADCgUIBgAAAA==.Krimboz:BAAANQAECgEIAgAAAA==.Krystallight:BAAANQAECgcIEgAAAA==.',
La='Lazreki:BAAANQABCgcIBwAAAA==.',
Le='Lechuzón:BAAANQADCgQIBAAAAA==.Legaloas:BAABNQAECoEgAAIUAAgKCh5cLQCmAgAUAAgKCh5cLQCmAgAAAA==.Lenah:BAAANQADCgMIAwAAAA==.Leondero:BAABNQAECoEeAAIUAAgKcRxgKwCuAgAUAAgKcRxgKwCuAgAAAA==.Leroyjenkins:BAAANQADCggJFAAAAA==.Leuthil:BAAANQADCgIIAgABNQAECgEIAQAQAAAAAA==.',
Li='Lintilla:BAAANQADCgcICAAAAA==.',
Ll='Llevanya:BAAANQAECgYIEQAAAA==.',
Lo='Lofi:BAAANQAECgUIDAAAAA==.Lokkhar:BAAANQAECgEIAQAAAA==.Loredalso:BAAANQAECgMIBgAAAA==.',
Lu='Lubricated:BAAANQAECgIJAwAAAA==.Lucíewilde:BAAANQADCgQIBAAAAA==.',
['Lè']='Lèdrollan:BAABNQAECoEgAAMUAAgKGSEoGgD+AgAUAAgKGSEoGgD+AgATAAEKwAPkdwAlAAAAAA==.',
Ma='Mageypoo:BAAANQADCggIBgABNQAECgIIAQAQAAAAAA==.Magicdreams:BAAANQAECgYICwAAAA==.Mahll:BAAANQAECgIIAgABNQAECggICwAQAAAAAA==.Malmorte:BAAANQADCgYIBgAAAA==.Malorane:BAAANQAECgEIAQAAAA==.Malorix:BAABNQAECoEhAAIOAAgKJxu7LgCAAgAOAAgKJxu7LgCAAgAAAA==.Maléficaa:BAAANQADCgQIBAAAAA==.Materia:BAAANQAECgEIAQAAAA==.Maz:BAAANQAECgUIBgAAAA==.',
Mc='Mcflury:BAAANQADCggIDgAAAA==.',
Me='Meatbeef:BAAANQAECgIIAwAAAA==.Meerchi:BAAANQAECgEIAQAAAA==.Meknin:BAAANQAECgUIDQAAAA==.Meldia:BAAANQAECgEIAQABNQAECgUJBQAQAAAAAA==.Merlinsdog:BAAANQADCgMIAwAAAA==.Mesthos:BAAANQAECgEIAQABNQAECgcIDgAQAAAAAA==.',
Mi='Mickieta:BAAANQAECgcIEgAAAA==.Mikalau:BAAANQAECgUIEwAAAA==.Mikaluu:BAAANQADCggIFQAAAA==.Milktide:BAAANQADCgUIBwABNQAECggIEwAQAAAAAA==.Minishields:BAAANQAECgMIBAAAAA==.Missteek:BAAANQAECgIIAgABNQAECgQIBgAQAAAAAA==.Mistrunner:BAAANQADCgYIBgAAAA==.Mistspell:BAABNQAECoElAAMDAAgKWhseLQB0AgADAAgKWhseLQB0AgAEAAgK+BShGwAgAgAAAA==.',
Mo='Mochacho:BAAANQADCgYIBgABNQAECgYIDAAQAAAAAA==.Mognel:BAAANQAECgEIAQAAAA==.Moomootus:BAABNQAECoEmAAICAAkK/iCGIQANAwACAAkK/iCGIQANAwAAAA==.Motoraxe:BAABNQAECoEbAAIKAAkKCBHuZgARAgAKAAkKCBHuZgARAgAAAA==.',
My='Mystynight:BAAANQADCgUIBgAAAA==.',
Na='Naajin:BAAANQADCgcIDAAAAA==.Nabyano:BAAANQAECgEIAQAAAA==.Nauty:BAAANQABCgYICQAAAA==.',
Ne='Newt:BAAANQADCggIEQAAAA==.',
Ni='Nicegauges:BAEANQAECgUIDQAAAA==.Nightcrest:BAAANQAECgUICAAAAA==.Nightrocks:BAAANQAECgIIAwAAAA==.Nilfgard:BAAANQAECgUIDAAAAA==.Nivix:BAAANQADCgQICAAAAA==.',
No='Nordrydsh:BAAANQADCgcIBwABNQAECgUIBQAQAAAAAA==.Noslock:BAAANQABCgYIBgAAAA==.Nosprey:BAAANQABCgEIAQAAAA==.',
Nu='Nuhpie:BAACNQAFFIELAAIKAAUKoRMXCwCYAQAKAAUKoRMXCwCYAQA1AAQKgSAAAgoACQoZIm8hAA4DAAoACQoZIm8hAA4DAAAA.',
Oc='Occultfish:BAAANQAECgIIAgAAAA==.',
Ol='Olimdar:BAACNQAFFIEJAAIbAAUKwRf1BQC4AQAbAAUKwRf1BQC4AQA1AAQKgR0AAhsACQrwIdsIAFwDABsACQrwIdsIAFwDAAAA.',
Oo='Oopositive:BAAANQADCgIIAgAAAA==.',
Or='Oraion:BAAANQAECgUIEgAAAA==.',
Ot='Otimion:BAAANQADCgMIAwAAAA==.',
Ov='Ovarb:BAAANQAECgIIAwAAAA==.',
Pa='Pallydan:BAAANQAECgUIBwABNQAECgUIEgAQAAAAAA==.Pan:BAAANQAECgEIAQAAAA==.Pathofpain:BAAANQADCgEIAQAAAA==.',
Pe='Peachie:BAAANQAECgQICAAAAA==.Persicles:BAAANQAECgIJAgAAAA==.',
Pi='Pissedwolf:BAAANQADCgEIAQAAAA==.',
Po='Polong:BAAANQADCgUIBQAAAA==.Poutine:BAAANQAECgIIAQAAAA==.',
Pr='Prisman:BAAANQADCggICAAAAA==.Proserpìne:BAAANQAECgUICAAAAA==.',
Pu='Pummel:BAAANQADCgQIBAAAAA==.Putt:BAAANQADCgYICwAAAA==.',
Qo='Qoolkumquat:BAAANQADCgcIBwAAAA==.',
Qu='Quoril:BAABNQAECoEfAAILAAkKDhjNZwB+AgALAAkKDhjNZwB+AgAAAA==.',
Ra='Radiyra:BAAANQABCgIIAgAAAA==.Ragnahr:BAAANQAECggIAQAAAA==.Rainstormin:BAAANQAECgEIAQAAAA==.Raitan:BAAANQAECgUICgAAAA==.Raivoker:BAAANQADCgQIBAABNQAECgUICgAQAAAAAA==.Rakarra:BAAANQADCgIIAgAAAA==.Rantah:BAAANQADCgQIBAAAAA==.Rawrstance:BAABNQAECoEYAAIcAAgKLAYLXAA6AQAcAAgKLAYLXAA6AQABNQADCgcIBwAQAAAAAA==.Razgrize:BAAANQAECgMIAwAAAA==.',
Re='Reilin:BAAANQAECgUIBgAAAA==.Remsham:BAAANQAECgIIBAAAAA==.Renwyck:BAAANQAECgcIDgAAAA==.Reovar:BAAANQABCgQIBAAAAA==.Reovarr:BAAANQADCgIIAgAAAA==.Revengemoon:BAABNQAECoEkAAICAAgKTB9kMgDBAgACAAgKTB9kMgDBAgAAAA==.',
Ro='Robane:BAAANQADCgYIEgAAAA==.Rouen:BAAANQADCgUJBgAAAA==.',
Ru='Rubidea:BAAANQAECgMIBAAAAA==.Ruckus:BAEANQAECgEIAQAAAA==.Rude:BAAANQAECgIIAgAAAA==.Ruder:BAAANQADCgEIAQABNQAECggIGAAXANcTAA==.Rutabaga:BAAANQADCgIIAgAAAA==.',
Ry='Rythas:BAAANQADCgUIBQAAAA==.',
Sa='Sahranna:BAAANQABCgIIAgAAAA==.Saintanic:BAAANQADCgcIBwAAAA==.Sandkat:BAAANQAECggIDwAAAA==.Santalight:BAAANQAECgEIAwABNQAECggIHwAWAEYhAA==.Santamoe:BAABNQAECoEfAAIWAAgKRiF0DADgAgAWAAgKRiF0DADgAgAAAA==.Saraelin:BAAANQAECgMIAwAAAA==.Saray:BAABNQAECoEYAAIUAAkK9yH8DwA+AwAUAAkK9yH8DwA+AwAAAA==.Sarwyn:BAAANQADCgUIBQAAAA==.Saurelli:BAAANQADCgYICAABNQAFFAMICAAdAKgUAA==.',
Se='Sedak:BAAANQADCggIHwAAAA==.Seitana:BAAANQABCgQIBAAAAA==.Sevrus:BAAANQADCgYIBgAAAA==.',
Sh='Shamushamu:BAAANQADCgMIAwAAAA==.Shaqheal:BAAANQADCggIDwAAAA==.Shiftey:BAAANQAECgUIDAAAAA==.Shiftymage:BAAANQAECgQIBwABNQAECgUIDAAQAAAAAA==.Shirtles:BAAANQADCgcIDQAAAA==.Shockandmoo:BAAANQADCgUIBQABNQAECgQIBgAQAAAAAA==.Shèp:BAAANQAECgEIAQABNQAECgQICAAQAAAAAA==.',
Si='Sidecake:BAAANQADCgQIBAAAAA==.Singars:BAAANQAECgcIDQAAAA==.Sixseven:BAAANQADCgcJBwAAAA==.Siypra:BAAANQAECgcIEQAAAA==.',
Sk='Skelmir:BAAANQADCgYJCgAAAA==.',
Sn='Snokplaster:BAAANQADCgYIBwAAAA==.Snorri:BAABNQAECoEYAAISAAgKkSOZEQD5AgASAAgKkSOZEQD5AgAAAA==.Snowbvnny:BAAANQAECgEIBAAAAA==.',
So='Soleyn:BAAANQADCgYIBgAAAA==.Soto:BAAANQAECgEJAQAAAA==.Sotosan:BAAANQADCgMIAwAAAA==.',
Sp='Spacechicken:BAAANQADCgEIAQABNQAECgEIAQAQAAAAAA==.Sprodage:BAAANQAECgUICAAAAA==.',
St='Stanil:BAAANQAECgQICwAAAA==.Steampunkz:BAAANQAECgEIAQAAAA==.Strangetame:BAAANQADCgMIBAAAAA==.Striest:BAAANQAECgUIBwAAAA==.Styló:BAAANQAECgEIAgAAAA==.',
Su='Suelly:BAAANQAECgcIEAAAAA==.Suguru:BAAANQAECgYICAAAAA==.Sularma:BAAANQAECgEIAQAAAA==.Sunsorrow:BAAANQADCggICAABNQADCgcIBwAQAAAAAA==.Suraschi:BAABNQAECoEbAAIVAAcKfhetDgDCAQAVAAcKfhetDgDCAQAAAA==.',
Sw='Swisscake:BAAANQAECgEIAQAAAA==.Swtmystic:BAAANQAECgIJAgAAAA==.',
Sy='Sygneus:BAAANQADCggICgAAAA==.Sylain:BAAANQADCggJCQABNQAECgQIBwAQAAAAAA==.Synwav:BAAANQAECgUIBQAAAA==.',
Ta='Taiani:BAAANQABCgMIAwAAAA==.Taldrin:BAAANQADCgMIAwAAAA==.Tallinor:BAAANQAECgMIBAAAAA==.Tannatax:BAAANQAECgYIDAAAAA==.Tashah:BAAANQADCgUICgAAAA==.',
Te='Teamspidey:BAAANQADCgMIAwABNQAECgQIBAAQAAAAAA==.Terminator:BAAANQADCgcIDQAAAA==.',
Th='Thewhitness:BAAANQAECgIIAwAAAA==.Thewretch:BAAANQAECgYIDAAAAA==.Thumpthump:BAAANQAECgUIBwAAAA==.Thunderkiss:BAEANQADCgUIDwABNQAECgEIAQAQAAAAAA==.',
Ti='Tindoranis:BAAANQADCgIIAgAAAA==.',
To='Toothguy:BAAANQADCgMIAwAAAA==.Toscus:BAAANQADCgMIAwAAAA==.Totemii:BAAANQADCgYIBgAAAA==.',
Tr='Tradewarrior:BAAANQAFFAEIAQAAAA==.Trayth:BAAANQAECggIBgAAAA==.Trevor:BAAANQADCgMIAwAAAA==.Trueheart:BAAANQAECgYIDAAAAA==.',
Ts='Tshark:BAABNQAECoEgAAINAAkKsh3+AwARAwANAAkKsh3+AwARAwAAAA==.Tsura:BAAANQAECgUIEQAAAA==.',
Tu='Tutatotao:BAAANQABCgQIBgABNQADCgEIAQAQAAAAAA==.',
Ty='Tyduss:BAAANQADCgEJAQAAAA==.',
Un='Unclepeepers:BAABNQAECoEjAAMeAAgKRx9RCADdAgAeAAgKRx9RCADdAgAWAAgK+RskFABrAgAAAA==.Underpowered:BAAANQADCgcIEAAAAA==.Unearthed:BAAANQADCgQIBAAAAA==.',
Ur='Urlän:BAAANQADCgYIBgAAAA==.',
Us='Usirina:BAAANQADCgUJBQABNQAECggIGAAXANcTAA==.',
Va='Vaeryn:BAAANQADCgcICQABNQAECggIIwAFAH8ZAA==.Valhen:BAABNQAECoEjAAQFAAgKfxl+BgDrAQADAAgKSBh/NABTAgAFAAcKgRZ+BgDrAQAEAAIKTAYbVwBRAAAAAA==.Valtar:BAABNQAECoEdAAIbAAgKMCQCDQA2AwAbAAgKMCQCDQA2AwAAAA==.',
Ve='Velryn:BAAANQADCgUIBgABNQAECggIIwAFAH8ZAA==.',
Vi='Vicsen:BAAANQADCgUIBQAAAA==.Vikaya:BAAANQADCgQIBAAAAA==.Vilevixon:BAAANQAECgcIEgAAAA==.',
Wa='Wagu:BAAANQABCgQIBAAAAA==.Walla:BAAANQADCgIIAgABNQAECgQIBAAQAAAAAA==.Wanlok:BAAANQAECgUICQAAAA==.Warbuddy:BAAANQAECgEIAQAAAA==.Warmis:BAAANQADCgYICgAAAA==.Warriorlobo:BAAANQAECgYIDAABNQAECgcIEAAQAAAAAA==.Watts:BAABNQAECoEXAAIUAAgKAhzJMACZAgAUAAgKAhzJMACZAgABNQAECgkJHwALAA4YAA==.',
We='Weez:BAAANQADCgUIBQAAAA==.',
Wi='Wildfang:BAABNQAECoEWAAMUAAcK3wjzhwCYAQAUAAcK3wjzhwCYAQATAAEK0AD4ewAUAAAAAA==.Wildside:BAAANQAECggIAwAAAA==.',
Xa='Xandronys:BAAANQAECgQIDgAAAA==.',
Xe='Xebec:BAAANQAECgYICgAAAA==.',
Xy='Xyra:BAAANQADCgcJCQAAAA==.',
Ya='Yalik:BAAANQADCgMIAwABNQAECgQIBAAQAAAAAA==.',
Ye='Yeet:BAAANQADCggIDwAAAA==.',
Yz='Yzugzugo:BAAANQAECgcICwAAAA==.',
Za='Zalandra:BAAANQABCgUIBQAAAA==.Zalckar:BAAANQAECgUIBwAAAA==.Zanos:BAAANQADCgUICAAAAA==.Zappyending:BAAANQAECgUIBQAAAA==.',
Ze='Zeeva:BAAANQAECgEIAQAAAA==.Zendead:BAAANQAECgUIBQAAAA==.',
Zi='Zigar:BAAANQAECgQIBAAAAA==.Zionspartan:BAAANQAECgcIDQAAAA==.',
Zu='Zugzugpriest:BAAANQAECgIJAwAAAA==.Zurokhan:BAABNQAECoEhAAIGAAgKFh2oJwCVAgAGAAgKFh2oJwCVAgAAAA==.',
['Zø']='Zønda:BAABNQAECoEYAAMfAAcKJiHtDACZAQAKAAUKWiAZjQCgAQAfAAQKliPtDACZAQAAAA==.',
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
