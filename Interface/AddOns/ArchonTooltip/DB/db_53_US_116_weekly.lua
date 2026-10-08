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

local lookup = {'Shaman-Restoration','Unknown-Unknown','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Druid-Balance','Evoker-Devastation','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Mage-Arcane','DeathKnight-Frost','Priest-Shadow','DeathKnight-Unholy','Warrior-Protection','Evoker-Preservation','Rogue-Subtlety','Hunter-Marksmanship','Paladin-Retribution','Rogue-Assassination','Paladin-Holy','Priest-Holy','Mage-Fire','Mage-Frost','Druid-Guardian','Priest-Discipline','Evoker-Augmentation','Paladin-Protection','Hunter-Survival','Shaman-Enhancement','Druid-Restoration','Druid-Feral','Monk-Brewmaster','Monk-Windwalker',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aadrisedh:BAAANQAECgMIAwAAAA==.Aaeryn:BAAANQAECgEIAQAAAA==.Aaliyshaa:BAAANQAECgIIBQAAAA==.Aanorim:BAAANQADCgMIBgAAAA==.Aaramis:BAABNQAECoEcAAIBAAgK5hGcXQDHAQABAAgK5hGcXQDHAQAAAA==.',
Ab='Abrakadabruh:BAAANQAECgQIBwAAAA==.Abyssal:BAAANQAECgYIDgAAAA==.',
Ac='Achin:BAAANQADCgYICgAAAA==.',
Ad='Adanbad:BAAANQADCggICAAAAA==.',
Ae='Aelanthir:BAAANQAECgYICQAAAA==.Aellwyn:BAAANQAECgIIAQABNQAECgUIBQACAAAAAA==.',
Ai='Aidoffhealer:BAAANQADCgQIBQAAAA==.',
Al='Alariah:BAAANQADCgMIAwAAAQ==.Aldoraline:BAAANQADCggIEAAAAA==.Alfredstare:BAAANQADCgcIBwAAAA==.Alliancewar:BAAANQADCgEIAQAAAA==.Alordros:BAAANQADCgYIFAAAAA==.Alystair:BAAANQADCgYIBgABNQAECgUIBwACAAAAAA==.',
Am='Amadayus:BAABNQAECoEbAAIDAAgKMSU4DwBVAwADAAgKMSU4DwBVAwAAAA==.Ambellina:BAAANQAECgUIBAAAAA==.',
An='Anaria:BAAANQADCgUIBQAAAA==.Anduinz:BAAANQAECgQIBQAAAA==.',
Ar='Aranyssa:BAABNQAECoE8AAQEAAgKSR6gCgCfAQAFAAcKLx0tVQA1AgAEAAUKfxugCgCfAQAGAAEKyRlzZwBGAAAAAA==.Arclock:BAAANQAECgQICAAAAA==.Arconnai:BAABNQAECoEuAAIHAAkKAyDnLwDrAgAHAAkKAyDnLwDrAgAAAA==.Areiotyrict:BAAANQAECgEIAQAAAA==.Arnøld:BAAANQAECgMIAwABNQAECgQIBgACAAAAAA==.Arrnac:BAAANQADCgYIBgAAAA==.',
As='Asham:BAAANQADCgYIEAAAAA==.Asiago:BAAANQAECgQIDgABNQAECgkJHAAIAOwbAA==.Asondra:BAAANQADCgMIAwAAAA==.Aspect:BAAANQAECgUIBwAAAA==.',
Av='Avvalethra:BAAANQAECgYIEwAAAA==.',
Az='Azdoroth:BAAANQADCgMIAwAAAA==.Azenet:BAAANQAECgQJCAABNQAFFAYIEAAJAPcYAA==.',
Ba='Babyball:BAAANQAECgIIAgAAAA==.Bainefreeze:BAAANQAECgUICQAAAA==.Balancedtech:BAAANQAECgEIAQAAAA==.Bananataffy:BAAANQADCgUIBQAAAA==.Barackoshama:BAABNQAECoEhAAIKAAcKMheJWgDlAQAKAAcKMheJWgDlAQAAAA==.Barkimadog:BAAANQAECgMIAwAAAA==.Battle:BAAANQADCgIIAgAAAA==.Baw:BAAANQAECgYJDAAAAA==.',
Be='Bearlinwall:BAAANQAECgEIAQAAAA==.Bearmaster:BAAANQAECgYICwAAAA==.Belacc:BAAANQADCggIEwAAAA==.Belfiyajr:BAAANQAECgcICgAAAA==.Bereaved:BAAANQADCgUIBQAAAA==.',
Bi='Biggiebertha:BAAANQAECgcIEAAAAA==.Bighooves:BAAANQADCgIIAgAAAA==.Bigskymage:BAAANQAFFAEIAQAAAA==.Billybones:BAAANQAECgQIDAAAAA==.Bimbobaby:BAAANQABCgEIAQAAAA==.',
Bl='Blackholes:BAAANQAECgQICwAAAA==.Blackwÿn:BAAANQADCggIEwABNQAECgUIDQACAAAAAA==.Bladeblade:BAAANQAECgcICgABNQAECgkJLgAHAEkhAA==.Bladedozzer:BAAANQAECgMIBwAAAA==.Blindinglite:BAABNQAECoElAAILAAcK7B1+IgBhAgALAAcK7B1+IgBhAgAAAA==.Bloodhaze:BAABNQAECoEYAAILAAkKOyLpFgDEAgALAAkKOyLpFgDEAgAAAA==.Blueorange:BAAANQAECggICAAAAA==.',
Bo='Bodizzle:BAAANQADCggIHgAAAA==.Bombil:BAAANQADCgYIEgAAAA==.Boombastique:BAAANQAECgMIAwAAAA==.Bootychaser:BAAANQADCgUIBQAAAA==.Borestus:BAAANQADCgUJBwAAAA==.',
Br='Brchm:BAAANQAECgQICgAAAA==.Brickly:BAABNQAECoEZAAMLAAkKsR0dGAC5AgALAAgKNx4dGAC5AgAMAAEKfRmfJwBKAAAAAA==.Brieter:BAAANQADCgYICgABNQAECgkJHAAIAOwbAA==.Broncolock:BAAANQADCggICAAAAA==.Brotheldog:BAAANQADCgUIBQAAAA==.Brutusx:BAAANQAECgMIAwAAAA==.',
Bu='Bulaktheliar:BAAANQADCgcIGQAAAA==.',
Bx='Bxxberry:BAAANQAECgEIAQAAAA==.',
['Bú']='Búkki:BAAANQADCgYIHAAAAA==.',
['Bü']='Bükkì:BAAANQADCgYICQAAAA==.Bükkï:BAAANQADCgcIEQAAAA==.',
Ca='Caboodles:BAAANQAECgcIEQAAAA==.Cachamama:BAAANQAECgIIAgAAAA==.Camishami:BAAANQAECgcIDAAAAA==.Candyhandz:BAAANQADCgUICwABNQAECgQIBwACAAAAAA==.Carmane:BAAANQADCgEIAQAAAA==.Carsher:BAAANQADCgYIBgAAAA==.Cassander:BAAANQADCgYIBgAAAA==.Casstyelle:BAAANQADCgEIAQABNQAECgkJKAABABIZAA==.Catharsis:BAAANQAECgEIAQAAAA==.',
Ce='Ceraph:BAAANQADCgQIBAAAAA==.Cexiback:BAABNQAECoErAAINAAkKUh7HCQAwAwANAAkKUh7HCQAwAwAAAA==.Cexifist:BAAANQAECgQIBQAAAA==.',
Ch='Chancew:BAAANQADCgQIBAAAAA==.Cheebsz:BAAANQADCgYIDgAAAA==.Cheesus:BAABNQAECoEcAAIIAAkK7BtdGwDTAgAIAAkK7BtdGwDTAgAAAA==.Chicharon:BAABNQAECoEYAAIOAAcKvwma6QCQAQAOAAcKvwma6QCQAQAAAA==.Chillfrost:BAAANQADCgEIAQAAAA==.Chingazossal:BAAANQAECgYIDwAAAA==.Chokolock:BAAANQAECgYIBgABNQAECggIIQAPAHQTAA==.Chunggus:BAAANQABCgYICQAAAA==.Churva:BAABNQAECoEbAAMKAAcKogk+pQAbAQAKAAYK+QU+pQAbAQABAAYKeQZmrgDlAAAAAA==.',
Co='Coko:BAAANQADCgYIBgABNQAECggIJAADACsdAA==.Condemned:BAAANQADCgQIBgAAAA==.Coochie:BAAANQAECgMIAwAAAA==.Cosecantes:BAAANQAECgQIEwAAAA==.Cowdozer:BAAANQADCggICwABNQAECggIGgADAPASAA==.Cowtools:BAAANQADCgQIBAAAAA==.',
Cr='Crackjones:BAAANQAECgYIBgAAAA==.Crisgmt:BAAANQAECgQIBQAAAA==.Crism:BAAANQAECgQIBQAAAA==.Crismtg:BAAANQAECgYIEQAAAA==.Critsandgigg:BAAANQADCgYIBwAAAA==.Crusäderaura:BAAANQAECgYIDQAAAA==.Cryptìc:BAACNQAFFIEJAAIQAAQKPhVnCABOAQAQAAQKPhVnCABOAQA1AAQKgR8AAhAACQqqIE8NAAADABAACQqqIE8NAAADAAE1AAQKCAgXAA4APx0A.Cryptîc:BAABNQAECoEXAAIOAAgKPx2jXQCxAgAOAAgKPx2jXQCxAgAAAA==.',
Da='Dabbia:BAABNQAECoEdAAQEAAkKeR2nCADbAQAEAAYKRR+nCADbAQAFAAQK0xxHsABAAQAGAAQKMxelLgAFAQAAAA==.Dabhill:BAAANQADCgIIAgAAAA==.Daedleus:BAAANQAECgcICQAAAA==.Damara:BAAANQADCgYIBgAAAA==.Damented:BAAANQADCggIEQABNQAECgkJKAABABIZAA==.Dandaris:BAAANQAECgEIAQAAAA==.Darkfugg:BAAANQADCgUICgAAAA==.Darood:BAAANQADCggIHgAAAA==.Dasmilnti:BAAANQADCgcIBQAAAA==.Dawnchild:BAAANQAECgIIAgAAAA==.Dazdraperma:BAAANQAECgIIBAAAAA==.',
De='Deadvocate:BAAANQAECgQICgAAAA==.Deathballz:BAABNQAECoEhAAMPAAgKdBPcLwDtAQAPAAgKdBPcLwDtAQARAAIKWwcBuwBTAAAAAA==.Declake:BAAANQADCgMIAwAAAA==.Deeznugs:BAAANQAECgIIAgAAAA==.Delthrus:BAAANQAECgQIBwABNQAECggIHQASACAPAA==.Demonarc:BAABNQAECoEcAAINAAkKehTDGQBwAgANAAkKehTDGQBwAgAAAA==.Detreset:BAABNQAECoEZAAITAAkKaRgxDwCiAgATAAkKaRgxDwCiAgAAAA==.Devocate:BAAANQADCgEIAQAAAA==.Devomorph:BAAANQADCgcIBwAAAA==.',
Di='Dinguskhaan:BAABNQAECoEVAAIOAAcKYAZbAQFlAQAOAAcKYAZbAQFlAQAAAA==.Dinkles:BAAANQADCgcIEAAAAA==.Dinkys:BAAANQAECgEIAQABNQAECgUICgACAAAAAA==.Dinsum:BAAANQABCggIDwAAAA==.Dirtytaint:BAAANQAECgQJBgABNQAECgkJJAAUAF0kAA==.Disorder:BAAANQAECgEIAQAAAA==.',
Dk='Dkballz:BAAANQAECgEIAQABNQAECgkJJAAUAF0kAA==.',
Do='Doflamingo:BAAANQABCgEIAQAAAA==.Doldion:BAAANQADCgUICQAAAA==.Donkypunch:BAAANQADCgEIAQAAAA==.Donut:BAAANQAECgIIAgABNQABCgIIAgACAAAAAA==.Dotnrun:BAAANQADCgEJAQAAAA==.',
Dr='Dragonhamer:BAAANQADCgYICAAAAA==.Dragtiago:BAAANQADCgQIBAAAAA==.Drakarys:BAAANQADCgIIAgAAAA==.Drexybear:BAABNQAECoEVAAIVAAgKYhgPHQBNAgAVAAgKYhgPHQBNAgAAAA==.Drezbi:BAAANQAECgEIAQAAAA==.Drunkenmaste:BAAANQADCgYIBgAAAA==.',
Du='Dunbarth:BAABNQAECoEjAAIWAAcKzw2MqgCSAQAWAAcKzw2MqgCSAQAAAA==.Durzaka:BAAANQAECgUIBgAAAA==.Durzu:BAAANQAECgQIDgAAAA==.Duty:BAAANQAECgIIAgAAAA==.',
['Dà']='Dàrkfate:BAAANQAECgUICQAAAA==.',
Ea='Earthdozzer:BAAANQADCgMIAwAAAA==.',
Ec='Echohavo:BAAANQAECgMIBgAAAA==.',
Ef='Eff:BAABNQAECoEqAAMXAAkKvxGcIQBLAgAXAAkKgRGcIQBLAgAUAAYKJAmpLQA2AQAAAA==.',
Eg='Eggy:BAAANQAECggIBgAAAA==.Egholom:BAABNQAECoEkAAILAAgKmAreQACBAQALAAgKmAreQACBAQAAAA==.',
Ek='Eks:BAAANQABCgcICQAAAA==.',
El='Electrcfrost:BAABNQAECoEjAAIKAAkKFxmNLACoAgAKAAkKFxmNLACoAgABNQAECgkJKQAIAI4bAA==.Elkanàh:BAABNQAECoEZAAMYAAkK/xpPQgA+AgAYAAcK7xpPQgA+AgAWAAgKixVGegAHAgABNQAFFAUIDgAZAPUYAA==.Elorene:BAABNQAECoEdAAMaAAgKLAhLAwCgAQAaAAgKCQhLAwCgAQAOAAYK9gFNawG4AAAAAA==.Elunara:BAAANQAECgYIDgABNQAECggIPAAEAEkeAA==.Elyysian:BAACNQAFFIEKAAIQAAUKkRSBBgCRAQAQAAUKkRSBBgCRAQA1AAQKgSMAAxAACQrpHt4LABMDABAACQrpHt4LABMDABkAAwqWA8nLAHoAAAAA.',
Em='Emokitten:BAAANQAECgEIAQAAAA==.Emptor:BAAANQAECgIIAwAAAA==.',
Er='Erebeius:BAAANQADCgMIAwAAAA==.Ereleb:BAAANQADCgUIBQAAAA==.',
Es='Escanör:BAAANQADCgIIAgABNQAECgUIBwACAAAAAA==.Esil:BAAANQADCgUIBQAAAA==.Espresso:BAAANQADCgcIBwAAAA==.Essekk:BAACNQAFFIEJAAIOAAUKURbBFACoAQAOAAUKURbBFACoAQA1AAQKgSAAAw4ACQrnIe0zABYDAA4ACQrnIe0zABYDABsAAQosF3g1AE8AAAAA.',
Ev='Evasivem:BAAANQADCgQIBAAAAA==.Event:BAAANQADCgYIBgAAAA==.',
Ew='Ewoo:BAAANQAECgYIEQABNQAECggIHgAcAJclAA==.',
Ex='Executtioner:BAAANQADCggJDQAAAA==.Explicit:BAAANQADCgYIBgAAAA==.Expression:BAAANQADCgYIBgABNQAECggIHgAcAJclAA==.',
Fa='Fadam:BAAANQAECgYIDQAAAA==.Faei:BAAANQADCgUICAAAAA==.Famjam:BAAANQAECggIBgAAAA==.Fatigue:BAAANQADCgcIDgAAAA==.Fatpo:BAABNQAECoEXAAQZAAgK2hynWADpAQAZAAcK3xunWADpAQAQAAQKuB8ONABbAQAdAAEKBSC7HgBXAAABNQAECgkJGQALALEdAA==.Fazy:BAAANQADCgYIEAAAAA==.',
Fe='Feldrakka:BAAANQADCgMIBAAAAA==.Felgore:BAAANQADCgQIBAAAAA==.',
Fi='Finality:BAABNQAECoEjAAIOAAkKRhsgXgCwAgAOAAkKRhsgXgCwAgAAAA==.',
Fl='Flexo:BAAANQADCgUIBQAAAA==.Flirtatious:BAACNQAFFIEIAAIKAAMKoAsGFgDnAAAKAAMKoAsGFgDnAAA1AAQKgRUAAgoACQoIEPBOAA4CAAoACQoIEPBOAA4CAAAA.Floriyana:BAAANQAECgIIBQAAAA==.',
Fo='Forsakenvoid:BAAANQADCgQIBAAAAA==.Fortknight:BAAANQADCgUIBQABNQAECgkJLwAOALUfAA==.Fourpriest:BAAANQAECgIIAgAAAA==.Foô:BAABNQAECoEjAAMXAAgKCR/vEADXAgAXAAgKCR/vEADXAgAUAAUKAhPxLQAzAQAAAA==.',
Fr='Freehands:BAAANQADCgIIAgAAAA==.Frizza:BAAANQAECgEIAgAAAA==.Frostpaw:BAAANQABCgIIAgAAAA==.',
Fu='Fudead:BAAANQAECgMIAwAAAA==.Fugarra:BAAANQAECgQIBAABNQAECgUIBQACAAAAAA==.Furyrosa:BAAANQADCgcIBwAAAA==.Fuzi:BAAANQADCgMIAwABNQADCggICAACAAAAAA==.',
Fy='Fyah:BAABNQAECoEbAAIWAAgKKhq+XgBRAgAWAAgKKhq+XgBRAgABNQAFFAUIDwADADoSAA==.Fyaza:BAAANQADCggICAABNQAFFAUIDwADADoSAA==.',
Ga='Gaga:BAAANQADCgIIAgAAAA==.Gargamels:BAAANQAECgUIBQAAAA==.Garou:BAAANQAECgQIBQAAAA==.',
Ge='Geekyshaman:BAAANQAECgMIAwAAAA==.Genesis:BAAANQAECggICgAAAA==.Gerttie:BAAANQAECgcIEAAAAA==.',
Gg='Ggoottss:BAAANQADCgYIDQAAAA==.',
Gi='Gingdrac:BAACNQAFFIEUAAITAAYKPBJyBgDIAQATAAYKPBJyBgDIAQA1AAQKgSEAAhMACQqeHiYNAMECABMACQqeHiYNAMECAAAA.',
Go='Gobsquadp:BAAANQAECgUICwABNQAECggIHgAcAJclAA==.',
Gr='Grassmoker:BAAANQAECgUIBwAAAA==.Grek:BAAANQAECgcIDQABNQAECgkJIAAeACkeAA==.Grievex:BAABNQAECoEgAAIWAAgKgAatvgBmAQAWAAgKgAatvgBmAQAAAA==.Grimbladez:BAAANQADCgYICgAAAA==.Grololo:BAAANQADCgcIGwAAAA==.Grozloo:BAAANQADCgMIAwAAAA==.Grumpel:BAAANQADCgYICgAAAA==.',
Gu='Guzzlr:BAAANQAECgYIBwAAAA==.',
Ha='Habeebe:BAAANQAECgUIDQABNQAECgkKIwAVAKodAA==.Hagen:BAAANQADCgYIBgAAAA==.Hammerrhoid:BAAANQADCgEIAQAAAA==.Hanyu:BAAANQADCggICAAAAA==.Harryoneeye:BAAANQAECgEJAQAAAA==.',
Hb='Hbots:BAAANQAECgQIBAAAAA==.',
He='Healthiss:BAABNQAECoEkAAIZAAkKHxs0HQDjAgAZAAkKHxs0HQDjAgAAAA==.Heelz:BAAANQADCgMIBAAAAA==.Hemostasis:BAABNQAECoEtAAQWAAkKHSNSEwBoAwAWAAkKHSNSEwBoAwAYAAEKghiJ/ABIAAAfAAEKHRZzXwA7AAAAAA==.Herjä:BAAANQAECgQIDAAAAA==.Hexem:BAAANQADCgYIBwABNQADCggIDQACAAAAAA==.Hexoon:BAAANQAECgQICAAAAA==.',
Ho='Homeslice:BAABNQAECoEXAAQEAAcKIxGeEQAIAQAEAAQKeBGeEQAIAQAFAAQKyAic6gDGAAAGAAIKQRRSUQB/AAAAAA==.',
Hu='Hukeg:BAAANQADCgQIBAAAAA==.Huntweak:BAAANQADCggICQAAAA==.Huun:BAABNQAECoEgAAIgAAkKPh4BAgAgAwAgAAkKPh4BAgAgAwAAAA==.',
Hy='Hyasynthia:BAAANQADCgIIAgAAAA==.Hycindraeda:BAAANQADCgcJBwAAAA==.',
Ia='Iamgabrielsj:BAABNQAECoEmAAMFAAcKDwjLoQBiAQAFAAcK3wfLoQBiAQAGAAMKBAapTwCEAAAAAA==.',
Id='Idontdps:BAAANQADCgYIBwAAAA==.',
Im='Imphetamine:BAAANQAECggICAAAAA==.',
In='Inayasha:BAAANQADCgUIBQAAAA==.',
Ir='Irrenadro:BAABNQAECoEwAAIWAAkKFQ7nhQDpAQAWAAkKFQ7nhQDpAQAAAA==.',
Is='Islandhunter:BAAANQABCgQJBAAAAA==.',
Iy='Iyahna:BAAANQAECgQIBgAAAA==.',
Ja='Jabaru:BAAANQADCgQIBAAAAA==.Jaypee:BAAANQAECgUICgAAAA==.',
Je='Jeage:BAAANQAECgQIBQABNQAECgkJIAAKACAjAA==.',
Ji='Jimboslice:BAAANQADCgQIBAAAAA==.Jimmoh:BAAANQAECgQIBQABNQAECggIGAAhAFwiAA==.Jimmybones:BAAANQABCgIIAgAAAA==.',
Jk='Jkn:BAAANQADCgcIBwAAAA==.',
Jo='Joes:BAABNQAECoEYAAIDAAcKFxhOYwAkAgADAAcKFxhOYwAkAgAAAA==.Jonesy:BAAANQAECgQIBQAAAA==.Jormingon:BAAANQADCgYIBwAAAA==.',
Ju='Juicygossip:BAAANQADCggIFgAAAA==.',
Ka='Kalabar:BAAANQADCgEIAQAAAA==.Kanada:BAAANQAFFAIIAgABNQAFFAcIGgAWALwaAA==.Kanikitddon:BAAANQADCgIJAgAAAA==.Katanya:BAAANQAECgIIAgABNQAECggIPAAEAEkeAA==.',
Ke='Keetra:BAABNQAFFIELAAIDAAUKSgzJCQCCAQADAAUKSgzJCQCCAQAAAA==.Keiriline:BAAANQAECgUIDQAAAA==.',
Ki='Killbreed:BAAANQAECgEIAQAAAA==.Kinkster:BAAANQADCgUIBQAAAA==.Kioshiro:BAAANQADCgQIBAAAAA==.',
Kl='Klix:BAAANQADCgQJBAABNQAECgQIBwACAAAAAA==.',
Kn='Knight:BAABNQAECoEYAAMOAAkK4hqaagCUAgAOAAgKWhyaagCUAgAaAAIK9QtxCABrAAAAAA==.Knuggz:BAAANQAECgUICAAAAA==.',
Kr='Kratoswrath:BAAANQAECgEIAQAAAA==.',
Ku='Kubluk:BAAANQAECgIIAgAAAA==.Kumbustinher:BAAANQADCgYICgAAAA==.',
Ky='Kyledh:BAAANQADCggICAABNQAECgkJKQAZAGomAA==.Kylepala:BAAANQAECgYIBgABNQAECgkJKQAZAGomAA==.Kylepriest:BAABNQAECoEpAAMZAAkKaiYkAQDXAwAZAAkKaiYkAQDXAwAdAAIKKSMFFQC/AAAAAA==.',
['Kã']='Kãyron:BAAANQADCggICQAAAA==.',
La='Lamashtuu:BAAANQADCgIIAgABNQAECgQIBwACAAAAAA==.Lambeáu:BAAANQAECgUIBwAAAA==.Lambrusca:BAAANQADCgcIBwAAAA==.Lamda:BAAANQAECgIIAwAAAA==.Lamdadk:BAAANQADCggICQAAAA==.Landistis:BAAANQADCgYICwAAAA==.Lanstoll:BAAANQAECggIDgAAAA==.Larcisong:BAAANQAECgYIDgAAAA==.Larzoe:BAAANQADCgUIBQABNQAECggIIwALAM8hAA==.Larzoh:BAABNQAECoEjAAMLAAgKzyHrEAD/AgALAAgKzyHrEAD/AgANAAMKug/sTgClAAAAAA==.Lateesha:BAAANQAECgUICgAAAA==.Lavac:BAAANQAECgEIAQAAAA==.',
Le='Lemonheads:BAAANQAECgYIEQAAAA==.Lethargy:BAAANQADCgUICQAAAA==.Levapally:BAAANQADCgUICAAAAA==.',
Li='Lidorila:BAAANQADCgMICAAAAA==.Lightguard:BAABNQAECoEaAAIWAAcKzRdYigDeAQAWAAcKzRdYigDeAQAAAA==.Lightinburn:BAAANQADCgQIBAAAAA==.Lilplottwist:BAABNQAECoEZAAIDAAcKsgPNvwBPAQADAAcKsgPNvwBPAQAAAA==.Lilwiz:BAAANQADCgcIFwAAAA==.Linalala:BAABNQAECoFhAAMiAAgKiyYFAwCNAwAiAAgKiyYFAwCNAwAjAAcKpREFEQC+AQAAAA==.Linnxvx:BAAANQADCgYIBgAAAA==.Lishp:BAAANQADCgYIBgAAAA==.Literacola:BAAANQAECgYICQAAAA==.',
Lo='Lorino:BAAANQADCgcICwAAAA==.Lothaire:BAAANQABCgIIAgAAAA==.',
Lu='Lubaduba:BAAANQADCggIDQAAAA==.Lugeya:BAAANQAECgUIBAAAAA==.Lugeyamnk:BAAANQAECgMIAgAAAA==.Lumenadiel:BAAANQAECgEJAQAAAA==.Lustnbeiber:BAABNQAECoEjAAQKAAgK3BVHSQAlAgAKAAgK3BVHSQAlAgABAAQKMQmszgCiAAAhAAEKgwIcMQAzAAAAAA==.Lustpls:BAAANQABCgUIBQAAAA==.Luuciferr:BAAANQAECgYICAAAAA==.Luv:BAAANQADCgQIBAAAAA==.',
Ly='Lynchà:BAABNQAECoEZAAIfAAgK0yK6BwAMAwAfAAgK0yK6BwAMAwAAAA==.',
Ma='Maakun:BAABNQAECoEmAAIZAAkKYBalMQCBAgAZAAkKYBalMQCBAgAAAA==.Maddevil:BAAANQADCggIEwAAAA==.Magawarrior:BAAANQADCgQIBgAAAA==.Mahoragga:BAAANQAECgMIAwAAAA==.Mahzad:BAABNQAECoEmAAMBAAkKICDyFAAMAwABAAkKICDyFAAMAwAKAAQKwhldnwAnAQAAAA==.Malchezaar:BAAANQAECgQIBAAAAA==.Malfrun:BAABNQAECoEdAAISAAgKIA9dFQClAQASAAgKIA9dFQClAQAAAA==.Marinnite:BAAANQADCgYIBgAAAA==.Marox:BAABNQAECoEgAAIOAAcKcRu3nAApAgAOAAcKcRu3nAApAgAAAA==.Marrøwgar:BAAANQAECgUIBwAAAA==.Mathrim:BAACNQAFFIEFAAIFAAIK0h+yIADCAAAFAAIK0h+yIADCAAA1AAQKgSkAAwUACQozJbECAMUDAAUACQozJbECAMUDAAYAAgqOFXdPAIUAAAAA.Matooka:BAAANQAECgUIDQAAAA==.Maynji:BAAANQADCggICAAAAA==.',
Mc='Mcthugger:BAAANQADCgYIEAABNQAECggIGgAWAE4XAA==.',
Mi='Miinthara:BAAANQADCgEIAQAAAA==.Minithril:BAAANQADCgUICAAAAA==.Misspetite:BAAANQADCgYJEgAAAA==.Mitskii:BAAANQADCgMIAwAAAA==.',
Mo='Mojosmiles:BAAANQADCgQIBAAAAA==.Mojosmilês:BAAANQAECgEIAQAAAA==.Mokxî:BAAANQAECgEIAQAAAA==.Molodeath:BAAANQAECgUICgAAAA==.Mommÿ:BAABNQAECoEqAAMZAAkKHhqzJgCyAgAZAAkKHhqzJgCyAgAdAAYKSAyGDgAvAQAAAA==.Moneymage:BAAANQAECgQIBAAAAA==.Monkgroom:BAAANQAFFAEIAQAAAA==.Montra:BAABNQAECoEpAAIcAAkKFxNYEgD6AQAcAAkKFxNYEgD6AQAAAA==.Moogaag:BAAANQADCgEIAQABNQAECggIJAADACsdAA==.Moolificent:BAAANQAECgUICgAAAA==.Moonshea:BAAANQADCgQIBAAAAA==.Morgaine:BAAANQADCgUIBgAAAA==.Motorinkashi:BAAANQAECgcIEQAAAA==.',
Mu='Muddbane:BAAANQADCgQIBAABNQAECggIJQAXAI4XAA==.Muddgore:BAAANQADCggIDgABNQAECggIJQAXAI4XAA==.Muddthir:BAAANQADCgQIBAABNQAECggIJQAXAI4XAA==.Murong:BAAANQAECgEIAQAAAA==.Mustardmage:BAAANQAECgYICQABNQAECgkJLQADADcgAA==.',
My='Myzarei:BAAANQAECgUICwAAAA==.',
['Mø']='Møkxi:BAAANQADCggICAAAAA==.',
['Mû']='Mûdd:BAABNQAECoElAAMXAAgKjhfpIQBJAgAXAAgKIhfpIQBJAgAUAAQKPRWrMgAFAQAAAA==.',
Ne='Nebur:BAAANQADCgUICQAAAA==.Nestaah:BAAANQADCgYJCwAAAA==.Nethender:BAAANQADCgMIAwAAAA==.Newtlid:BAAANQAECgYIBwAAAA==.',
Ni='Nirath:BAABNQAECoEiAAIOAAgKaAqByQDOAQAOAAgKaAqByQDOAQAAAA==.Nisia:BAAANQAECgUICQABNQAECgkJLgAHAEkhAA==.Nito:BAABNQAECoElAAIPAAkKvRLgKAAeAgAPAAkKvRLgKAAeAgAAAA==.',
No='Nohkano:BAABNQAECoEoAAIkAAkK3CWJAADeAwAkAAkK3CWJAADeAwAAAA==.Nokt:BAAANQAECgIIAwAAAA==.Norrbert:BAAANQADCgcIBwAAAA==.Norriz:BAAANQAECgcIDgAAAA==.Noveerra:BAAANQADCgUIBgAAAA==.',
Nu='Numbuh:BAAANQAECgQIBgAAAA==.Nusix:BAAANQADCggIGAAAAA==.',
Oa='Oakremi:BAAANQADCgMIAwAAAA==.Oakrogue:BAAANQADCggIHwAAAA==.',
Od='Odysseusxap:BAAANQADCgIIAgAAAA==.',
Ol='Oldirtytank:BAAANQADCgMIAwAAAA==.',
On='Oneshothel:BAAANQADCgEIAQAAAA==.',
Ov='Overdoze:BAAANQADCgUICwAAAA==.Overkill:BAAANQAECggICAAAAA==.',
Pa='Painwhisper:BAAANQABCgQJBAAAAA==.Paladeez:BAAANQAECgYICwABNQAECgkJLQAWAB0jAA==.Pallymans:BAAANQADCgMIAwAAAA==.Pangpang:BAAANQADCgcJDAAAAA==.Pantheons:BAAANQAECgQIBQAAAA==.Parsi:BAABNQAECoEYAAMMAAcKsheYDADMAQAMAAYKvhqYDADMAQANAAIKmQemVQBsAAAAAA==.Pattysmyth:BAAANQAECgMIAwABNQADCggIDgACAAAAAA==.Paulinemaroi:BAAANQAECgcICwAAAA==.Paulinethree:BAAANQAECgQIBAABNQAECgcICwACAAAAAA==.Pawtism:BAAANQAECggIEAAAAA==.',
Pe='Peleaihonua:BAAANQADCgQJBQABNQAECgQIBwACAAAAAA==.Pennywhys:BAAANQADCgYIBgAAAA==.',
Ph='Philip:BAAANQAECgUIBwAAAA==.',
Pl='Playstayshon:BAAANQADCgMIAgAAAA==.',
Po='Pofat:BAAANQADCgYIBgABNQAECgkJGQALALEdAA==.Polis:BAAANQADCgcIBwABNQAECgQIDAACAAAAAA==.Pottyy:BAAANQABCgIIAgAAAA==.Pougadina:BAAANQAECgIIAgABNQAECgkJGQALALEdAA==.Powjr:BAAANQADCgYIBgAAAA==.',
Pr='Primal:BAAANQADCgcJBwAAAA==.Pritee:BAAANQADCggIGgAAAA==.',
Pu='Puriel:BAAANQABCgYICQAAAA==.Putu:BAAANQADCgUIBgAAAA==.',
Py='Pyrina:BAAANQAECgQIBwABNQAECgYIDgACAAAAAA==.',
['Pä']='Pändora:BAAANQADCggIDgAAAA==.',
Ra='Rabite:BAABNQAECoEeAAIcAAgKlyVHAwBtAwAcAAgKlyVHAwBtAwAAAA==.Radiance:BAEANQAECgQIBQABNQAFFAMIBQAVABIfAA==.Raelinastus:BAAANQADCgYICAAAAA==.Ragehound:BAAANQADCgEIAQAAAA==.Rah:BAAANQADCgYJCQAAAA==.Ramshunter:BAAANQAECgMIBQAAAA==.Randyvivaldi:BAAANQAECgEIBAAAAA==.Rashanda:BAAANQAECgQIBAAAAA==.Rathasas:BAABNQAECoEeAAITAAcKHxlyFwArAgATAAcKHxlyFwArAgAAAA==.Ratnob:BAABNQAECoEWAAIRAAcKpxXFTwCrAQARAAcKpxXFTwCrAQAAAA==.',
Re='Reddemon:BAABNQAECoEgAAMeAAkKKR46AwDsAgAeAAkKKR46AwDsAgAJAAEKfwY/OgAvAAAAAA==.Relda:BAAANQAECgIIBQABNQAECggIGAAhAFwiAA==.Remye:BAABNQAECoEhAAIYAAgK6xZ+RwAqAgAYAAgK6xZ+RwAqAgAAAA==.Rennshi:BAABNQAECoEdAAILAAkK0SWHBQCPAwALAAkK0SWHBQCPAwAAAA==.Reportedhunt:BAABNQAECoEaAAIDAAgK8BIRXQA0AgADAAgK8BIRXQA0AgAAAA==.Rezzan:BAAANQAECgMIBwAAAA==.',
Rh='Rhavetta:BAAANQADCgUIBQAAAA==.',
Ri='Riani:BAAANQAECgEIAQAAAA==.Richie:BAAANQADCgcIBwAAAA==.',
Ro='Rolanthas:BAABNQAECoEZAAMNAAUK/QOdSQDSAAANAAUKnAOdSQDSAAALAAIKyQR5eQBTAAAAAA==.Roldaza:BAAANQAECgUIBgAAAA==.Rolexiós:BAAANQADCgIJAgAAAA==.Roranhamer:BAAANQADCgcICQAAAA==.Rosario:BAABNQAECoEtAAMDAAkKNyBFIQD1AgADAAgKoCJFIQD1AgAVAAYKxAndQgANAQAAAA==.',
Ru='Rulep:BAAANQADCgEIAQAAAA==.',
Ry='Rykû:BAAANQAECgEIAgAAAA==.Rythmatic:BAABNQAECoEkAAMUAAkKXSTmBQAeAwAUAAgKiiHmBQAeAwAXAAcKlyH5FwCVAgAAAA==.',
Sa='Sacrifice:BAAANQADCgEIAQAAAA==.Sagà:BAAANQABCgEIAQAAAA==.Sainttaint:BAAANQADCggIEwABNQADCgEIAQACAAAAAA==.Sakieri:BAABNQAECoEgAAMQAAgKGBruFwByAgAQAAgKGBruFwByAgAZAAEKKQOf5wApAAAAAA==.Salazar:BAAANQAECgEJAQAAAA==.Saluke:BAAANQADCgUIBQAAAA==.Samedi:BAAANQAECgMIAwAAAA==.Samwisegam:BAAANQADCgQIBAAAAA==.Sandordel:BAAANQADCgYIEQAAAA==.Sangan:BAABNQAECoEmAAIOAAkKuxpqSADjAgAOAAkKuxpqSADjAgAAAA==.Santaclaus:BAAANQADCggIDQAAAA==.Sappie:BAAANQADCgIIAgABNQADCgYIBwACAAAAAA==.Sarafinmae:BAAANQABCgIIAgAAAA==.',
Se='Seanoevil:BAAANQAECgIIAgAAAA==.Selaris:BAAANQADCggICAAAAA==.Selathviala:BAAANQADCgMIAgAAAA==.Serazal:BAACNQAFFIEQAAIJAAYK9xgtAgDqAQAJAAYK9xgtAgDqAQA1AAQKgSQAAgkACQqUInsEAEMDAAkACQqUInsEAEMDAAAA.Sergregorsly:BAAANQADCgIIAgAAAA==.Serintalis:BAAANQADCgEIAQAAAA==.',
Sh='Shadowblitzx:BAAANQADCggICwAAAA==.Shakaphase:BAAANQAECgEJAQAAAA==.Shalidor:BAAANQADCgUIBQAAAA==.Shamshamz:BAAANQAECgIIAgAAAA==.Shangan:BAAANQADCgQIBAAAAA==.Sharpshotz:BAAANQADCggIDQAAAA==.Shenanigan:BAAANQAECgUJBQAAAA==.Shionslime:BAAANQADCgQIBAAAAA==.',
Si='Sidequest:BAAANQADCgQJBAAAAA==.Sinaga:BAABNQAECoEbAAMFAAgK5SCJNwCSAgAFAAcKjSGJNwCSAgAGAAIK8RtISQCZAAAAAA==.Sinsear:BAAANQADCgcIBwAAAA==.Sintha:BAABNQAECoEZAAIOAAcK/gsi5QCYAQAOAAcK/gsi5QCYAQAAAA==.',
Sl='Slimedink:BAAANQADCgYICAAAAA==.',
Sm='Smarfus:BAAANQADCgQIBAABNQAECgkJIAAeACkeAA==.Smilingp:BAAANQADCgUICgAAAA==.Smolworm:BAAANQADCgUIDQAAAA==.',
So='Soulezz:BAAANQAECgUJBwAAAA==.Sourmash:BAAANQAECggICAAAAA==.',
St='Starfrost:BAAANQADCgIJAwAAAA==.Stingerai:BAABNQAECoEkAAIDAAgKKx1KLwC9AgADAAgKKx1KLwC9AgAAAA==.Stingerjb:BAAANQAECgQIBgABNQAECggIJAADACsdAA==.Stormj:BAAANQAECgEIAQAAAA==.',
Su='Subjugator:BAAANQAECggICwAAAA==.Sukunaa:BAAANQADCgUJDAAAAA==.Sunbeamer:BAAANQABCgYIBgAAAA==.Superdeej:BAAANQAECgYIBwABNQAECgkJFgAWAM8hAA==.',
Sy='Syl:BAAANQAECgQICAAAAA==.',
['Sá']='Sága:BAAANQADCgMJAwAAAA==.',
Ta='Tarashock:BAAANQADCgUIBgAAAA==.',
Te='Teecat:BAAANQADCgQIBwAAAA==.Teehuntee:BAAANQADCgEIAQABNQAECggIHQAlAJ8eAA==.Teemonk:BAABNQAECoEdAAIlAAgKnx77EAC8AgAlAAgKnx77EAC8AgAAAA==.Teepal:BAAANQADCgUIBQABNQAECggIHQAlAJ8eAA==.Telamanus:BAAANQABCgIIAgAAAA==.Tempist:BAAANQAECgQICAAAAA==.Teribullduce:BAABNQAECoEdAAIDAAkKWiPVEQBEAwADAAkKWiPVEQBEAwAAAA==.Terscheckii:BAAANQADCgYIDAAAAA==.',
Th='Thalissille:BAAANQAECgEIAQAAAA==.Thickyricky:BAAANQAECggICAABNQAECggIGAAhAFwiAA==.Thingol:BAAANQABCgYIEwAAAA==.Thormor:BAAANQAECgQICAABNQAFFAYIFAATADwSAA==.Thugger:BAAANQAECgQIBAABNQAECggIGgAWAE4XAA==.Thuggerjr:BAABNQAECoEaAAIWAAgKThevcgAaAgAWAAgKThevcgAaAgAAAA==.Thundersurge:BAAANQAECgEIAQABNQAECggIGgADAPASAA==.Thænes:BAAANQAECgUIDQAAAA==.Thûr:BAAANQADCgYIEgABNQAECgkJKAABABIZAA==.',
Ti='Tigg:BAABNQAECoEWAAIKAAgKCQM64ACcAAAKAAgKCQM64ACcAAAAAA==.Tildin:BAAANQADCgUIBQAAAA==.Tinkerdinker:BAAANQADCggIDgAAAA==.Tipsout:BAABNQAECoEuAAMHAAkKSSGDGABLAwAHAAkKSSGDGABLAwASAAYK3xIwHQBCAQAAAA==.',
Tn='Tnemith:BAAANQABCgUIBQAAAA==.',
To='Toddlyv:BAAANQADCggICAABNQAECggIHQAlAJ8eAA==.Totemm:BAAANQAECgcIDQAAAA==.Totomlystond:BAAANQADCgMIAwAAAA==.Tottemdrop:BAABNQAECoEoAAMBAAkKEhmeNgBdAgABAAkKEhmeNgBdAgAKAAUKQhE9mQA1AQAAAA==.',
Tr='Trailertrash:BAAANQADCgIIAgAAAA==.Traque:BAAANQAECgIIAgAAAA==.Trassenok:BAAANQADCgcIEAAAAA==.Trealin:BAAANQADCgYIDwAAAA==.',
Ty='Tyllinar:BAAANQADCgYIBgAAAA==.Tyrgor:BAAANQADCgYIFgAAAA==.Tyrsside:BAAANQAECgUICQAAAA==.',
Ub='Ubeenbained:BAAANQADCgIIAwAAAA==.',
Un='Unfocused:BAABNQAECoEpAAIIAAkKjhvQGADnAgAIAAkKjhvQGADnAgAAAA==.Unholybelac:BAAANQADCgQIBAAAAA==.',
Ur='Urgmathron:BAAANQAECgYIDQAAAA==.',
Va='Vakhara:BAAANQAECgQIBwAAAA==.Valorisa:BAAANQAECgMIAwABNQAFFAUICgAQAJEUAA==.Vansthir:BAAANQAECggIBgAAAA==.Vargko:BAAANQADCggICAAAAA==.Vaush:BAAANQAECgYIBgAAAA==.',
Ve='Veigär:BAAANQAECgEIAQAAAA==.Verasuchi:BAAANQAECgIIAQAAAA==.',
Vi='Vinsmoke:BAAANQADCggIFQAAAA==.',
Vo='Voidflare:BAABNQAECoEWAAIeAAYK4gsgDwAhAQAeAAYK4gsgDwAhAQAAAA==.Voidnutz:BAAANQADCgMIAwAAAA==.Voidyvoid:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.Volcanoez:BAAANQADCgYIBwAAAA==.Vonrx:BAAANQAECgEIAwAAAA==.',
Vy='Vyndrian:BAAANQADCgUIBQABNQAECggIIgAIAHAkAA==.',
Wa='Wardian:BAAANQADCggICAABNQAECgUIGQAfABwWAA==.Wariastos:BAAANQADCgQIBAAAAA==.Warlockhimup:BAAANQADCgMIBAABNQAECggIGgADAPASAA==.',
We='Welfairline:BAAANQADCggIFwAAAA==.',
Wh='Whatasham:BAAANQAECgMIAwABNQAECgkJHQADAFojAA==.',
Wy='Wynter:BAAANQADCgMIAwAAAA==.',
['Wô']='Wôrm:BAAANQADCgUIDQAAAA==.',
Xa='Xalarys:BAAANQADCgYIDAAAAA==.Xandra:BAAANQADCgMJBQAAAA==.',
Xs='Xsslopgob:BAAANQADCgEIAQAAAA==.',
Xu='Xufoxpikmin:BAAANQADCgEIAQAAAA==.',
Ya='Yappars:BAAANQAECgcIEgAAAA==.Yassera:BAAANQAECgQIDAAAAA==.',
Ye='Yekteniya:BAAANQAECgUICgAAAA==.',
Yu='Yurio:BAAANQAECgUIEAAAAA==.Yutch:BAAANQAECgQIBQAAAA==.',
Za='Zacalkan:BAAANQADCgYIFwAAAA==.Zarik:BAAANQAECgMIBgAAAA==.',
Ze='Zeddoc:BAEANQADCgYIFwAAAA==.Zedward:BAEANQADCgMIBQABNQADCgYIFwACAAAAAA==.Zenfist:BAAANQADCgQIBAAAAA==.Zenithar:BAAANQADCgIIAgAAAA==.Zenoath:BAAANQAECgUICgAAAA==.',
Zo='Zolidus:BAAANQADCggIFAAAAA==.Zosiris:BAAANQADCgYICgAAAA==.',
Zu='Zulugangrene:BAABNQAECoEgAAIWAAcKyw0bsACGAQAWAAcKyw0bsACGAQAAAA==.Zun:BAABNQAECoEVAAIbAAYKqgkWFwAeAQAbAAYKqgkWFwAeAQAAAA==.',
['Åt']='Åthenä:BAAANQADCgMIAwAAAA==.',
['Æg']='Ægir:BAAANQADCgUIBQABNQAECgUIDQACAAAAAA==.',
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
