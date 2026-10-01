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

local lookup = {'Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Unknown-Unknown','Evoker-Devastation','DeathKnight-Blood','Shaman-Enhancement','Warlock-Demonology','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Balance','Druid-Restoration','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Unholy','Priest-Shadow','Priest-Holy','DeathKnight-Frost','Priest-Discipline','Mage-Arcane','Warlock-Destruction','Evoker-Preservation','Mage-Frost','Warrior-Protection','Hunter-Survival','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','Monk-Windwalker','Warlock-Affliction','Druid-Guardian',}
local provider = {region='US',realm='Blackrock',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Absolve:BAACNQAFFIEGAAIBAAMKqR04DAArAQABAAMKqR04DAArAQA1AAQKgR4AAgEACQofIUwLAE8DAAEACQofIUwLAE8DAAAA.',
Ac='Actionjakson:BAAANQAECgcICAAAAA==.',
Ad='Adamantium:BAAANQADCgQIBAABNQAFFAMICQACAJ8hAA==.Adamantorc:BAACNQAFFIEJAAICAAMKnyGlCwAwAQACAAMKnyGlCwAwAQA1AAQKgSwAAwIACQpOJSoDAKIDAAIACQpOJSoDAKIDAAMAAQrvA0MEAS4AAAAA.Adampal:BAAANQAECgIIAgABNQAFFAMICQACAJ8hAA==.Adlez:BAAANQAECgUJBQAAAA==.Adowarlord:BAAANQADCgYIDQAAAA==.',
Ae='Aethylas:BAAANQAECgYICwAAAA==.',
Af='Afsdruid:BAAANQADCgcIDAAAAA==.',
Ai='Aizzen:BAABNQAECoEjAAIEAAgKTxSnDQDZAQAEAAgKTxSnDQDZAQAAAA==.',
Ak='Akadeyjr:BAAANQADCggIFwAAAA==.Akaeus:BAAANQAECgQIBgAAAA==.Akhouel:BAAANQADCgQIBAAAAA==.',
Al='Albatross:BAAANQAECgUICwAAAA==.Alfalfaflow:BAAANQADCggIGwAAAA==.Aliais:BAAANQAECgcICAAAAA==.Alienfreakdt:BAAANQAECgcIEQAAAA==.Alizalynn:BAAANQADCggICAAAAA==.Allaon:BAAANQAECgcJDwAAAA==.Allerianna:BAAANQADCgIIAgAAAA==.Alphacarl:BAAANQADCgMIAwAAAA==.Alyriel:BAAANQAECgIIAgAAAA==.Alysun:BAAANQAECgUIEwAAAA==.Alysyn:BAAANQAECgUICwABNQAECgUIEwAFAAAAAA==.Alyys:BAAANQABCgQIBQABNQAECgUIEwAFAAAAAA==.Alèxander:BAAANQAECgMIBwAAAA==.',
Am='Amado:BAAANQADCgEIAQAAAA==.Amathel:BAAANQAECgcIEAAAAA==.Amynda:BAAANQADCggIDAAAAA==.',
An='Angelsfìst:BAAANQAECgYIEQAAAA==.Annexin:BAAANQAECgUIBQABNQAECgcIEwAFAAAAAA==.',
Ap='Apocalyptic:BAAANQADCgEJAQAAAA==.',
Ar='Arawein:BAAANQAECgEIAQAAAA==.Aremis:BAAANQAECgYIEgABNQAFFAQIBwAGAAIZAA==.Argonius:BAAANQADCgUIBQAAAA==.Arka:BAAANQAECgcICwAAAA==.Arkavine:BAAANQAECgUICwABNQAECgcJIAAHAJgZAA==.Arkelly:BAABNQAECoEgAAIHAAcKmBnqOQDdAQAHAAcKmBnqOQDdAQAAAA==.Armedcookies:BAAANQAECgEIAQABNQAECggIIwAIAAMgAA==.Artemicion:BAAANQADCgQIBAABNQAECgMIBAAFAAAAAA==.Arutoria:BAAANQAECgQIBQAAAA==.',
As='Asche:BAAANQADCgYIBgAAAA==.Ashlie:BAAANQADCgcIDgAAAA==.Asirili:BAAANQAECgcIDAAAAA==.Asmoodeus:BAAANQAFFAEIAQABNQAFFAcICwAJADgTAA==.',
Au='Auramaxxer:BAAANQADCggICAAAAA==.',
Av='Avachii:BAAANQAFFAMIAwAAAA==.Avazen:BAAANQAECgEIAQAAAA==.',
Aw='Awnshe:BAAANQAECgMIAQAAAA==.',
Ay='Ayrah:BAAANQAECgYIDgAAAA==.',
Ba='Baccano:BAAANQADCgIIAgAAAA==.Badaboom:BAAANQADCgcIDQAAAA==.Badeeasu:BAAANQADCgQIBAABNQAFFAMICQACAJ8hAA==.Badshammy:BAAANQAECgIJBAAAAA==.Baelcoz:BAAANQAECgUICwAAAA==.Baragan:BAAANQAECgUIBwAAAA==.',
Be='Beamqt:BAAANQAFFAEIAQAAAA==.Bear:BAAANQAECgUIDAAAAA==.Bearwurst:BAAANQAECgQICAAAAA==.Beazle:BAAANQAECgYIDwAAAA==.Beefchub:BAACNQAFFIEKAAIBAAQKvgMsEADiAAABAAQKvgMsEADiAAA1AAQKgRkAAwEACAqZBtdnAJABAAEACAqZBtdnAJABAAoAAQpcGxUzAU0AAAAA.Beladora:BAAANQAFFAEIAQAAAA==.Bellarke:BAAANQADCgYIBgAAAA==.Belldelphine:BAABNQAECoEdAAQLAAkKsBy9GwB1AgALAAkK0Be9GwB1AgAMAAgK9Bq6HAA2AgANAAIKVR/XGQCsAAAAAA==.Better:BAAANQADCgYIBwABNQAECgkJIwAMAKYdAA==.',
Bi='Bichyone:BAAANQADCggJDwAAAA==.Bigback:BAABNQAECoEgAAMOAAgKAxWaLgAlAgAOAAgKAxWaLgAlAgAPAAUK3RxzJgCKAQAAAA==.Bigmeattréat:BAAANQAECgEIAQAAAA==.Bigpurr:BAAANQAECgUICQABNQAFFAUIDAAMANYQAA==.Bigtruss:BAAANQAECgQIBgAAAA==.Bilo:BAABNQAECoEbAAIQAAgKGhY8XAAxAgAQAAgKGhY8XAAxAgAAAA==.Bimpo:BAAANQAECgEIAQAAAA==.Biohazzard:BAAANQADCgUICQAAAA==.Bipolar:BAAANQAECggICAAAAA==.',
Bl='Blangtron:BAAANQAECgYIDgAAAA==.Blickyz:BAAANQAECgcIEAAAAA==.Bloodbortie:BAAANQAECgYIEgAAAA==.Blueflame:BAAANQAECgQIBAAAAA==.Blödhgárm:BAAANQADCggICwABNQAECggIHgAHAMUWAA==.',
Bo='Boatsnack:BAAANQADCgcIHQAAAA==.Boboko:BAAANQAECgQIBAAAAA==.Boderationx:BAAANQAECgMIAwABNQAFFAQIBwARAGEeAA==.Bodyshots:BAABNQAECoEZAAIKAAgKQREkcwDpAQAKAAgKQREkcwDpAQAAAA==.Boing:BAAANQABCgEJAQABNQADCgMIAwAFAAAAAA==.Bokar:BAAANQAECgUIBQABNQAECgkJIQAQAG4hAA==.Bokatan:BAAANQAFFAIIAgAAAA==.Bolgc:BAAANQAECgIIAgABNQAECgUICAAFAAAAAA==.Bonethug:BAAANQADCgUIBQAAAA==.Boofoo:BAAANQAECgYIDQAAAA==.Bootyhawk:BAAANQAECgEIAQAAAA==.Borbleybim:BAABNQAFFIEFAAISAAUKZgk5BwB3AQASAAUKZgk5BwB3AQAAAA==.Borella:BAAANQADCgEIAQABNQAFFAUIFQATACYhAA==.Bortikai:BAAANQAECgIIAwABNQAECgYIEgAFAAAAAA==.Bortikus:BAAANQADCgUIBwABNQAECgYIEgAFAAAAAA==.Boscho:BAABNQAECoEYAAMUAAgKTxntGABDAgAUAAgKTxntGABDAgAVAAYKoQ61bgBlAQAAAA==.Boschoa:BAAANQAECgUICQABNQAECggIGAAUAE8ZAA==.Bouncedh:BAAANQAECgIIBAABNQAECgkJHgAQAOIiAA==.Bowzarr:BAAANQADCgUICQAAAA==.Bowzerr:BAAANQADCgYIDAAAAA==.',
Br='Bragas:BAAANQADCgQIBAAAAA==.Brayeda:BAAANQAECgEIAQAAAA==.Breadpudn:BAAANQAECgUIBwAAAA==.Briighe:BAAANQAECgcIBwABNQAFFAEIAQAFAAAAAA==.Brilliac:BAAANQABCgIIAgABNQAECgEIAQAFAAAAAA==.Broccoliched:BAAANQAECgMIBAAAAA==.Brodacz:BAAANQADCgYIEgAAAA==.Brownii:BAABNQAECoEWAAIKAAgK4w3dgwC6AQAKAAgK4w3dgwC6AQAAAA==.',
Bu='Bubsdk:BAAANQABCgUIBQAAAA==.Bullohme:BAAANQADCggIDgAAAA==.Burntbunss:BAAANQADCgUICQAAAA==.Burritortega:BAAANQADCggIIAAAAA==.Burstinatrix:BAAANQADCgYJBgAAAA==.',
['Bé']='Bérserkblave:BAAANQAECgYIBgAAAA==.',
['Bó']='Bóunce:BAABNQAECoEeAAIQAAkK4iJ1GAA7AwAQAAkK4iJ1GAA7AwAAAA==.',
Ca='Cainos:BAAANQADCgQIBQAAAA==.Calandra:BAABNQAECoEZAAIJAAgKoh1RJQC6AgAJAAgKoh1RJQC6AgAAAA==.Cantgetme:BAAANQAECgEIAQAAAA==.Carditis:BAACNQAFFIEHAAICAAMKPhRcDwDpAAACAAMKPhRcDwDpAAA1AAQKgSAAAgIACQogH+4cAMYCAAIACQogH+4cAMYCAAAA.Carditits:BAAANQADCgYIBgABNQAFFAMJBwACAD4UAA==.Catwilliams:BAAANQADCggIEAAAAA==.',
Ce='Celeríty:BAAANQADCgYIBwAAAA==.Ceri:BAAANQADCggJEAAAAA==.Cev:BAAANQAECgYJCgABNQAFFAMIBwATAHYiAA==.Cevren:BAACNQAFFIEHAAMTAAMKdiIpCgDjAAATAAMK3xgpCgDjAAAHAAIKSCDzEgC5AAA1AAQKgSUABBMACQpuJroDAKIDABMACQpuJroDAKIDABYAAgrnGjtjAJwAAAcAAQojGoSkAEMAAAAA.',
Ch='Chals:BAABNQAECoEeAAMVAAgKiyHmGADjAgAVAAgKXx/mGADjAgAXAAEK1xMpHQBJAAAAAA==.Chaoselite:BAABNQAECoEyAAMKAAkKtxziLADYAgAKAAkKtxziLADYAgABAAgKpxE+RwAHAgAAAA==.Charmie:BAAANQADCgQIBAABNQAECgUICQAFAAAAAA==.Chelia:BAAANQAECgIIAwAAAA==.Chuibacca:BAAANQAECggIEQAAAA==.',
Cl='Claanx:BAAANQAECgIJAgAAAA==.Clops:BAAANQADCgUICwAAAA==.',
Co='Cobrakilla:BAAANQAECgQIBgAAAA==.Cobrakiller:BAAANQAECgQIBAABNQAECgQIBgAFAAAAAA==.Coldgrasp:BAAANQADCgcIBwAAAA==.Coochpooch:BAAANQADCgYIDAAAAA==.Corbun:BAAANQADCggIHAAAAA==.Corpsebane:BAAANQAECgYIDwAAAA==.Cortèx:BAAANQADCgEIAQAAAA==.Cosmicgate:BAABNQAECoEkAAMMAAkKtiLWBgBSAwAMAAkKPyHWBgBSAwALAAUK6B24MwCuAQAAAA==.Cowguy:BAAANQAECgUIBgAAAA==.Cowlawladin:BAABNQAECoEVAAIKAAgK0Bi+TwBVAgAKAAgK0Bi+TwBVAgAAAA==.',
Cr='Crangs:BAAANQADCggICAAAAA==.Crockett:BAABNQAECoEsAAISAAkKWBtFHQDuAgASAAkKWBtFHQDuAgAAAA==.Croissantz:BAAANQAECgUIDQAAAA==.Crusha:BAAANQADCgYICQAAAA==.Cryssis:BAAANQADCgYIBgAAAA==.',
Cu='Cubanmage:BAAANQAECgUIDgABNQAECgYIDgAFAAAAAA==.Cubanpally:BAAANQAECgYIDgAAAA==.Cucucachoo:BAAANQAECgMIAwAAAA==.Cupgayke:BAAANQAECgcIDAABNQAECggIEAAFAAAAAA==.',
Cy='Cyndi:BAAANQAECgEIAQAAAA==.Cynnabar:BAAANQADCgIIAgAAAA==.Cyrce:BAAANQADCgQIBAAAAA==.',
Da='Daanos:BAAANQADCgYIBgABNQAECggIIAAYAGchAA==.Daddy:BAAANQAECgcIDgAAAA==.Daeltha:BAACNQAFFIEHAAIGAAQKAhkSBABkAQAGAAQKAhkSBABkAQA1AAQKgR8AAgYACQp7HNkIAMACAAYACQp7HNkIAMACAAAA.Dafdafdaf:BAAANQAECgQIBAAAAA==.Daffenprime:BAABNQAECoEtAAIWAAkKZCEBBwBPAwAWAAkKZCEBBwBPAwAAAA==.Dailong:BAAANQAECgIIAgABNQAECgcICAAFAAAAAA==.Dalgona:BAAANQABCgEIAgAAAA==.Dalux:BAAANQADCgUIBgAAAA==.Danastey:BAAANQADCgYIBgAAAA==.Daneglesack:BAAANQAECgYIDwAAAA==.Danoslock:BAAANQADCggICAABNQAECggIIAAYAGchAA==.Danosxd:BAABNQAECoEgAAIYAAgKZyGsSADNAgAYAAgKZyGsSADNAgAAAA==.Daragnos:BAABNQAECoErAAMJAAkKxR8FIwDEAgAJAAgKQB8FIwDEAgAZAAQKSRe4KAAeAQAAAA==.Darkfäll:BAAANQADCgMIAwAAAA==.Darkhært:BAABNQAECoEbAAIVAAcKkxXRVADJAQAVAAcKkxXRVADJAQAAAA==.Darkkai:BAABNQAECoElAAMCAAkK/xzYEQANAwACAAkK/xzYEQANAwADAAIKHA193ABnAAAAAA==.Darthmuffin:BAAANQAECggIEQAAAA==.Daryl:BAAANQAFFAEIAQABNQAFFAQICAAZAC0NAA==.Dasprime:BAAANQAECgcIDgAAAA==.Dastòmper:BAAANQADCgUIBQABNQAECgQJCAAFAAAAAA==.Dayven:BAAANQADCggIDgAAAA==.',
De='Deadhitmann:BAAANQAECgEIAQAAAA==.Deathbringer:BAAANQAECggIBQAAAA==.Deathpenance:BAAANQADCgYIBgAAAA==.Deathãngel:BAABNQAECoEbAAIHAAgKPRgtKgA4AgAHAAgKPRgtKgA4AgAAAA==.Decall:BAAANQAECgMIBgABNQAECgYICwAFAAAAAA==.Decepper:BAAANQAECgEIAgAAAA==.Degraded:BAABNQAECoEhAAIQAAkKzRfvQwCDAgAQAAkKzRfvQwCDAgAAAA==.Delenix:BAAANQADCgYIBgABNQAECgIIAgAFAAAAAA==.Demelion:BAAANQAECgMIAwABNQAFFAIIAgAFAAAAAA==.Demelionee:BAAANQADCgUIBQABNQAFFAIIAgAFAAAAAA==.Demonblood:BAAANQAFFAEIAQAAAA==.Denul:BAAANQAECggICgAAAA==.Ders:BAAANQADCggIDgAAAA==.Dessius:BAAANQAECggIEwAAAA==.Dethstra:BAAANQAECgUICgABNQAECgcIDAAFAAAAAA==.Devouring:BAAANQADCggICAAAAA==.Deüs:BAAANQAECgQICAAAAA==.',
Di='Diffstyle:BAAANQAECggICQAAAA==.Dionotus:BAAANQAECgEIAgAAAA==.Dirtgrub:BAAANQAECgUICQAAAA==.Divdan:BAAANQADCggICAAAAA==.Divert:BAAANQADCggICAAAAA==.',
Dk='Dkhaoz:BAAANQAFFAIIAgABNQADCgYIDAAFAAAAAA==.Dkinabox:BAAANQADCggIBwABNQADCggIEAAFAAAAAA==.',
Do='Docturnal:BAAANQADCgMIAwAAAA==.Dolphina:BAAANQAECgQIBAAAAA==.Donfrancisco:BAAANQAECgUIBgAAAA==.Donsaul:BAAANQADCggICgAAAA==.Donuts:BAAANQADCgMIAwAAAA==.Doomsure:BAAANQADCgMIAwAAAA==.Doryani:BAAANQAECgQIBAAAAA==.Doømhammer:BAAANQADCggICAAAAA==.',
Dr='Dracburton:BAAANQADCgEIAQAAAA==.Drachen:BAAANQADCgYIBgABNQAECggIGAAUAE8ZAA==.Dracnaphobia:BAAANQADCgMIAwABNQAECgYIEgAFAAAAAA==.Dragynaegis:BAAANQAECgUIAQAAAA==.Dragynsabor:BAAANQADCgYIFQAAAA==.Dragynsoul:BAAANQADCgYIDAAAAA==.Drakö:BAAANQAECgEIAQAAAA==.Dranok:BAAANQAECgYIBwAAAA==.Dratnosfan:BAAANQADCgYJCgABNQAECggIIAAYAGchAA==.Drballseks:BAAANQAECgUJBQAAAA==.Drdingus:BAAANQADCggICAAAAA==.Dreadfox:BAAANQADCggIEwAAAA==.Dreamlike:BAABNQAECoEsAAIPAAkK4iK9BABaAwAPAAkK4iK9BABaAwAAAA==.Drezco:BAAANQADCgUIBwABNQAFFAMIBwATAHYiAA==.Droit:BAAANQAECgQIBAAAAA==.Drstormii:BAAANQAECgEIAQAAAA==.Drumelion:BAAANQAFFAIIAgAAAA==.',
Du='Dukazra:BAAANQADCggIKQAAAA==.Dumbledalf:BAAANQAFFAEIAQAAAA==.Dunkndonuts:BAAANQAECgcIDAAAAA==.',
['Dé']='Déathy:BAAANQAECgcIDAAAAA==.',
Ea='Earthencore:BAABNQAECoEaAAIEAAYKOgKTHQCwAAAEAAYKOgKTHQCwAAAAAA==.',
Eb='Ebully:BAAANQAECgQIBQAAAA==.',
Ed='Edelbroy:BAAANQADCgQIBAAAAA==.Edgyboy:BAAANQAECgEJAgAAAA==.Edjelord:BAAANQADCgcICQAAAA==.',
Eg='Eggmilk:BAAANQAECgIIAgAAAA==.Egirltank:BAAANQADCgcJDQABNQAECgkJGgAKALofAA==.',
El='Elaxa:BAAANQADCggJDAABNQAFFAUIDgAMAHIZAA==.Eldanath:BAAANQADCgYIBgAAAA==.Eliriel:BAAANQADCgQIBAABNQADCgYICgAFAAAAAA==.Elnaa:BAAANQADCgUIBQAAAA==.Elsulan:BAAANQADCggICAAAAA==.Elteethree:BAABNQAECoEaAAIaAAkK5gymGAD5AQAaAAkK5gymGAD5AQABNQAFFAcIEQACAH0fAA==.Elunelock:BAAANQADCggIHQAAAA==.Elunepal:BAAANQAECgYIEgAAAA==.Elys:BAAANQAECgUIEAAAAA==.Elysel:BAAANQAECgYICAABNQAECgkKIwATAMMlAA==.',
Em='Emalynn:BAAANQADCgYIBgAAAA==.Emilyfrost:BAAANQADCgQIBAAAAA==.',
En='Enigmà:BAABNQAECoEcAAMYAAgKcBFZrQDdAQAYAAgKcBFZrQDdAQAbAAEK4AGJPwApAAAAAA==.Enmanuel:BAAANQAECgcIEgAAAA==.',
Ep='Epyôn:BAABNQAECoEpAAMDAAkKfSK5DwBQAwADAAkKfSK5DwBQAwAIAAYKMx7oEAARAgAAAA==.',
Er='Ericthebrave:BAAANQAECgEIAQAAAA==.Eriodara:BAAANQADCgIIAgAAAA==.',
Es='Escas:BAAANQAECgUICgAAAA==.Escaz:BAAANQAECgQIBAAAAA==.Esrahaddon:BAABNQAECoEdAAIGAAcKBxdCEQACAgAGAAcKBxdCEQACAgAAAA==.',
Et='Etreyu:BAAANQAECgUIBwABNQAECggIHwAKAHwKAA==.',
Ev='Evanora:BAABNQAECoEXAAIJAAcKaAjmlgBIAQAJAAcKaAjmlgBIAQAAAA==.Evillinx:BAAANQAECgcIDAAAAA==.Evilmaru:BAAANQAECgcICgAAAA==.Evokelion:BAAANQAECgQIBAABNQAFFAIIAgAFAAAAAA==.Evoxx:BAAANQAECgEIAQAAAA==.',
Ew='Ewok:BAAANQADCgQIBAAAAA==.',
Ex='Exploited:BAAANQADCgcIBwAAAA==.',
Fa='Factz:BAAANQADCgEIAQAAAA==.Faespalmn:BAABNQAECoElAAICAAkK+R+gDgAnAwACAAkK+R+gDgAnAwAAAA==.Farrwest:BAAANQADCgQIBQABNQADCggIFAAFAAAAAA==.Fatalstab:BAAANQAECgMJAwAAAA==.Fauin:BAAANQADCgYIBgAAAA==.',
Fe='Featheramby:BAAANQADCgIIAgAAAA==.Felenesh:BAAANQADCgEIAQAAAA==.Felwräth:BAAANQAECgcJBwAAAA==.Fenthead:BAAANQADCgYICgABNQAECgkJGgAKALofAA==.Fernandôge:BAAANQAECgUIDAAAAA==.',
Fi='Fidel:BAAANQAECggIDwAAAA==.Fil:BAABNQAECoEeAAITAAkKKxpnGgCtAgATAAkKKxpnGgCtAgAAAA==.Fisac:BAACNQAFFIESAAIRAAYKsxcdBADpAQARAAYKsxcdBADpAQA1AAQKgScAAhEACQpuIngHAEIDABEACQpuIngHAEIDAAAA.Fishbubble:BAAANQABCgYIBwAAAA==.Fistbox:BAAANQADCggICAAAAA==.',
Fl='Fletchtern:BAAANQADCgEIAQABNQAECgQIDQAFAAAAAA==.Flexicute:BAAANQADCgcIBwAAAA==.Flexlock:BAAANQADCgMIAwAAAA==.Flextime:BAAANQAECgYIDQAAAA==.Flippinfear:BAAANQAECgYJCwAAAA==.',
Fo='Folius:BAACNQAFFIEZAAMJAAcKmh5zAACqAgAJAAcKhh5zAACqAgAZAAEKIhFqFABXAAA1AAQKgSIAAwkACQppJkMCAMIDAAkACQppJkMCAMIDABkAAwr7HdkxAOkAAAAA.Fortyourself:BAAANQADCggIDwABNQAFFAMJBwACAD4UAA==.',
Fr='Franzu:BAABNQAECoEZAAIIAAkKDBJJCwCFAgAIAAkKDBJJCwCFAgAAAA==.Freehits:BAAANQADCgEIAQAAAA==.Freelaughs:BAAANQADCgQIBAAAAA==.Friggitte:BAAANQAECgEIAQAAAA==.Friholy:BAAANQAECgUIDwABNQAECgkJJgACAKwTAA==.Frostdragyn:BAAANQAECgEJAQAAAA==.Frosteviã:BAAANQAECgQIBAAAAA==.',
Fu='Full:BAAANQADCggIFAAAAA==.Furgoblin:BAAANQAECgUICwABNQAECgcIEwAFAAAAAA==.',
Fy='Fyiona:BAAANQAECgUIAQAAAA==.',
['Fâ']='Fâdêd:BAAANQAECgQIBAAAAA==.',
['Fä']='Fäerise:BAAANQAECgEIAQAAAA==.',
['Fé']='Fén:BAAANQADCgYIDAABNQAECgQJCQAFAAAAAA==.',
['Fë']='Fëanör:BAAANQAECgYIDgAAAA==.',
['Fø']='Førce:BAAANQAECgEIAgAAAA==.',
Ga='Gabi:BAAANQADCgcIDQAAAA==.Gacrüx:BAAANQAECgIIAwAAAA==.Galadrìel:BAABNQAECoEtAAIKAAkKOByeLQDVAgAKAAkKOByeLQDVAgAAAA==.Galadrìèl:BAAANQAECgUICAAAAA==.Gambol:BAAANQADCgYIBgAAAA==.Garegar:BAAANQADCgYIBgAAAA==.Gasrok:BAAANQAECgIIAgABNQAECgkJKAADAB0lAA==.',
Ge='Gengizkhan:BAAANQADCgUICgABNQADCgYICgAFAAAAAA==.',
Gh='Ghorn:BAAANQAECgUIDgAAAA==.',
Gi='Gimerce:BAAANQAECggIBwAAAA==.',
Gl='Glaivetoes:BAAANQAECggICwAAAA==.Glareaforsor:BAAANQADCggIEAAAAA==.Glimpse:BAAANQAECgUIDgAAAA==.Glitched:BAAANQAECgQIBAAAAA==.Glytteris:BAAANQAECgMIAwAAAA==.',
Go='Gochurass:BAAANQAECgEIAQAAAA==.Goonspree:BAAANQADCgEIAQAAAA==.',
Gr='Grabbyhands:BAAANQADCgEIAQAAAA==.Grapthar:BAAANQAECgYICwAAAA==.Graveröse:BAAANQAECgEIAQAAAA==.Grenth:BAAANQADCgMIAwAAAA==.Greyarrow:BAAANQAECgYIEQAAAA==.Greæd:BAACNQAFFIEZAAIVAAcKwhfvAQB2AgAVAAcKwhfvAQB2AgA1AAQKgScAAxUACQpoJAQNADUDABUACQpoJAQNADUDABcABgrLHQ0JAJcBAAAA.Grimgown:BAAANQAECgMIAwABNQAECggIEAAFAAAAAA==.Grimreaper:BAAANQAECgUICAABNQAECgYIEAAFAAAAAA==.Grizzard:BAAANQAECgcICwAAAA==.Grretbek:BAAANQAECgEIAQAAAA==.Gruckek:BAABNQAECoEmAAMQAAkKvh/4GwApAwAQAAkKSR/4GwApAwAcAAIKTg3qLQBYAAAAAA==.Grææd:BAAANQAECgQIBAABNQAFFAcIGQAVAMIXAA==.',
Gu='Gulanis:BAAANQAECgUIDgAAAA==.Guldhakii:BAAANQAECggIDQAAAA==.',
Gw='Gwendlyne:BAAANQAECgUIDAAAAA==.',
['Gó']='Góddess:BAAANQADCggICQAAAA==.',
Ha='Hadoken:BAAANQADCggICQAAAA==.Hag:BAAANQAECgQIBAABNQAFFAYIDgAKAJUTAA==.Hakarii:BAAANQAECgQICAABNQAFFAUIDAAMANYQAA==.Halloffaith:BAAANQAECgcIDwAAAA==.Harissa:BAAANQADCgEIAQABNQAECgcIDAAFAAAAAA==.Harry:BAAANQAECgEIAQAAAA==.Hawgneto:BAAANQADCggIDQAAAA==.Hazel:BAAANQAECgUICQAAAA==.',
He='Hellig:BAABNQAECoEjAAMVAAgKwxmARAANAgAVAAgKwxmARAANAgAUAAEK+BKLXwA3AAAAAA==.Hellofriday:BAAANQADCggICAAAAA==.Hellscreamjr:BAAANQAECgUIBQABNQAECgkJHAAdAMEkAA==.Hellíg:BAAANQADCggIDgAAAA==.Hetzfury:BAAANQAECgcICQAAAA==.Heyman:BAAANQAECgMIBQAAAA==.',
Hi='Hideyerweed:BAAANQAECgQJBAABNQAECgkJHAAQAO8bAA==.Higi:BAAANQADCgYIBgAAAA==.',
Ho='Holistic:BAABNQAECoEnAAICAAkKuyQ/AgCyAwACAAkKuyQ/AgCyAwAAAA==.Holyclanx:BAAANQADCgYIBgAAAA==.Holylips:BAAANQAECggIBwAAAA==.Holyzamboni:BAABNQAECoEbAAIBAAgK7xvxJACkAgABAAgK7xvxJACkAgAAAA==.Honeyblunt:BAAANQADCgIIAgAAAA==.Hoodedguy:BAAANQAECgEIAQAAAA==.Horsepower:BAAANQADCgIIAgAAAA==.Horvarth:BAAANQADCgUJBQAAAA==.Hotchocmilk:BAABNQAECoEXAAISAAgKChsMMwCRAgASAAgKChsMMwCRAgAAAA==.',
Hr='Hr:BAAANQADCgcIBwAAAA==.',
Hu='Huanglow:BAAANQADCgcIBwAAAA==.Hunex:BAAANQAECgcIDAAAAA==.Huntaa:BAABNQAECoEcAAMdAAkKwSRKAADLAwAdAAkKwSRKAADLAwARAAEKaxQAZABEAAAAAA==.Hurají:BAABNQAECoEZAAMBAAkKLRs+GwDcAgABAAkKLRs+GwDcAgAKAAUKuQJ+DgGOAAABNQAFFAYIDAAeACAXAA==.Huråji:BAACNQAFFIEMAAIeAAYKIBdnAQD6AQAeAAYKIBdnAQD6AQA1AAQKgSYAAh4ACQqnIRUFACkDAB4ACQqnIRUFACkDAAAA.',
Il='Ilnookll:BAAANQADCgUJCQAAAA==.',
Im='Imblooms:BAAANQADCgEIAQAAAA==.Imbooms:BAAANQADCgYJBgAAAA==.Imryl:BAABNQAECoEZAAITAAcKEh6RJgBSAgATAAcKEh6RJgBSAgAAAA==.',
Io='Ionea:BAAANQADCgYICwABNQAECggIIwAIAAMgAA==.',
Ir='Irisaar:BAAANQAECgQIBAAAAA==.Ironpaws:BAAANQAECgcIEwAAAA==.Iryssoscaly:BAAANQADCgIIAgAAAA==.',
Is='Isa:BAAANQAECgYIDQABNQAFFAUIDAAMANYQAA==.Isaa:BAACNQAFFIEMAAIMAAUK1hAvBQCZAQAMAAUK1hAvBQCZAQA1AAQKgSEAAwwACQrRGg0UAJsCAAwACQq5Gg0UAJsCAAsAAgqWFzdgAIoAAAAA.Isamaru:BAAANQADCgYJBgAAAA==.Istredd:BAAANQAECgEIAQAAAA==.',
It='Itsen:BAAANQADCgQIBAABNQAECgkJKAADAB0lAA==.',
Ja='Jackrackham:BAAANQAECgYIEwAAAA==.Jakuza:BAAANQADCgYIBgABNQAECgcIEAAFAAAAAA==.Jaydeep:BAAANQABCgIIAgAAAA==.Jayrayco:BAAANQABCgQIBQAAAA==.',
Jd='Jdub:BAAANQAECgYIEgAAAA==.',
Je='Jebx:BAAANQADCggICQABNQAFFAUIDwADAE4UAA==.Jebybrew:BAAANQADCgcIBwABNQAFFAUIDwADAE4UAA==.Jebydk:BAAANQAECgUIBwABNQAFFAUIDwADAE4UAA==.Jebysham:BAACNQAFFIEPAAIDAAUKThSPBwCZAQADAAUKThSPBwCZAQA1AAQKgSsABAMACQrJIAoVACYDAAMACQoqIAoVACYDAAgACQpOHLcGAPICAAIAAgpEAlLjAEQAAAAA.Jeffybubbles:BAAANQADCggIEAAAAA==.Jeffyshadows:BAAANQADCgUIBQABNQADCggIEAAFAAAAAA==.Jeffytotems:BAABNQAECoEYAAIIAAgKoxzCCQClAgAIAAgKoxzCCQClAgAAAA==.Jelsy:BAAANQAECgYIEQAAAA==.Jepx:BAAANQAECgUICgAAAA==.Jesly:BAAANQADCggIGwABNQAECgYIEQAFAAAAAA==.Jessibella:BAACNQAFFIEHAAIVAAMKcg7kEwD1AAAVAAMKcg7kEwD1AAA1AAQKgS8AAhUACQrIHjQSAA0DABUACQrIHjQSAA0DAAAA.',
Jh='Jhnstzy:BAAANQADCgYICwAAAA==.',
Ji='Jimmythegoat:BAAANQADCgMIAwAAAA==.',
Jo='Johnsteez:BAAANQAECgEIAQAAAA==.Jorndalf:BAABNQAECoEhAAIDAAgKLCJeGAANAwADAAgKLCJeGAANAwAAAA==.',
Jt='Jt:BAAANQABCgIIAgAAAA==.',
Ju='Juggz:BAAANQAECgUIDgAAAA==.Juicylewts:BAAANQADCgcIDQABNQAECgYIEgAFAAAAAA==.Justabutcher:BAABNQAECoEYAAMWAAcKYRabLADVAQAWAAcKUhabLADVAQATAAQKuw5DegDEAAAAAA==.',
Jw='Jwag:BAAANQAECgEIAgAAAA==.',
['Jê']='Jêcht:BAACNQAFFIEIAAIVAAQKSB4cCwCMAQAVAAQKSB4cCwCMAQA1AAQKgSkAAhUACQoGJfkDAJgDABUACQoGJfkDAJgDAAAA.',
Ka='Kafur:BAAANQAECgcIEwAAAA==.Kaiido:BAAANQAECgEIAgABNQAFFAUIDAAMANYQAA==.Kak:BAAANQAECgUICQAAAA==.Kakesoba:BAAANQADCgcIBwABNQAECgEIAQAFAAAAAA==.Kalstorm:BAAANQAECgQJBAABNQAECgcIDAAFAAAAAA==.Karmanda:BAAANQAECgIIAQAAAA==.Kattel:BAAANQADCggIGgAAAA==.Kaychow:BAAANQAECgcIDwAAAA==.',
Ke='Keither:BAAANQADCgMJAwABNQADCgMIAwAFAAAAAA==.Kelendor:BAACNQAFFIEFAAISAAMK6AW/DwDjAAASAAMK6AW/DwDjAAA1AAQKgS4AAhIACQppEe8/AGMCABIACQppEe8/AGMCAAAA.Kellandil:BAAANQADCgQICQAAAA==.Kemmlerok:BAAANQAECgUIBwAAAA==.Kenju:BAABNQAECoEXAAIPAAkKRiI5BABlAwAPAAkKRiI5BABlAwAAAA==.Kensie:BAAANQAECggIEwAAAA==.',
Kh='Khlampz:BAABNQAECoEgAAMfAAgK0xmuFQCCAgAfAAgK0xmuFQCCAgAgAAUKegXuMgDmAAAAAA==.Khlampzight:BAAANQAECgUICAABNQAECggIIAAfANMZAA==.Khlampzoker:BAAANQADCggIEAABNQAECggIIAAfANMZAA==.Khondor:BAAANQAECgEJAQAAAA==.',
Ki='Kiel:BAAANQAECgQICAABNQAECgMIBAAFAAAAAA==.Kigen:BAAANQAECgEIAQAAAA==.Kikurface:BAAANQADCggIIAAAAA==.Kilmonger:BAAANQADCggIAgAAAA==.Kimjongheal:BAAANQADCggICAABNQADCggIEAAFAAAAAA==.Kimjungun:BAAANQADCgEIAQAAAA==.Kiranax:BAACNQAFFIEHAAMTAAUK6hn7AgC1AQATAAUK6hn7AgC1AQAHAAEKfhcEHgBVAAA1AAQKgTQABBMACQrpJdcDAKADABMACQrpJdcDAKADAAcAAwpUBwKRAHkAABYAAQrVEueKACkAAAAA.Kiraxxus:BAABNQAFFIEFAAIJAAIKowlrJACPAAAJAAIKowlrJACPAAABNQAFFAUIBwATAOoZAA==.Kittensune:BAAANQADCgQIBAAAAA==.',
Ko='Koinu:BAABNQAECoEeAAIeAAgKdiHMBwDnAgAeAAgKdiHMBwDnAgABNQAFFAMIBQASAAYeAA==.Kooriaisu:BAAANQADCgUICAAAAA==.Korbun:BAAANQADCgYIFAAAAA==.Kovskii:BAAANQADCggIHAAAAA==.',
Kr='Krad:BAAANQADCggIEwAAAA==.Kriathura:BAAANQAECgYICgAAAA==.Krizah:BAAANQADCgcICwAAAA==.',
Ku='Kukui:BAAANQADCgYJBgABNQAECgYIEwAFAAAAAA==.',
Kw='Kwangpow:BAAANQAECgMICAAAAA==.',
['Kà']='Kàkàshi:BAABNQAECoEiAAIYAAgK/RPaigAqAgAYAAgK/RPaigAqAgAAAA==.',
La='Laethal:BAAANQADCgQIBQAAAA==.Lambbchopp:BAAANQADCgUIDgAAAA==.Lammaríé:BAAANQADCggICAAAAA==.Lassitar:BAAANQADCgEIAQAAAA==.Lazyrage:BAAANQAECgYIDwAAAA==.Lazyreaper:BAAANQADCgUICwABNQAECgYIDwAFAAAAAA==.',
Le='Lebronto:BAABNQAECoEhAAIQAAkKbiFFHAAnAwAQAAkKbiFFHAAnAwAAAA==.Legsquats:BAAANQAECgQJCAABNQAECggIJAAHADQdAA==.Lessirs:BAAANQAECgEIAgAAAA==.Lexatron:BAAANQABCgEIAQAAAA==.',
Li='Lichnaught:BAAANQADCggIGwABNQAECgYIEQAFAAAAAA==.Lifetapped:BAAANQAECgEIAgAAAA==.Lilfluffy:BAAANQAECgMJAgAAAA==.Liquid:BAAANQADCgcIEAAAAA==.Little:BAAANQABCgQIBAAAAA==.',
Ll='Llikdaor:BAABNQAECoEWAAIYAAgKVhhLaAB8AgAYAAgKVhhLaAB8AgAAAA==.',
Lo='Loaded:BAAANQAECgYIDgAAAA==.Lockitupp:BAAANQADCgUIBQAAAA==.Loikk:BAAANQADCgMIAwAAAA==.Loodacrits:BAAANQAECgUIBwAAAA==.',
Lu='Lushylock:BAAANQADCgEIAQAAAA==.',
Ma='Macklin:BAAANQAECgEIAQAAAA==.Maddalynn:BAABNQAECoEjAAIBAAgKMRS/QwAVAgABAAgKMRS/QwAVAgAAAA==.Maelstrox:BAAANQADCgUIDQAAAA==.Magandadrake:BAABNQAECoEoAAMaAAkKMxXFEABwAgAaAAkKMxXFEABwAgAGAAMKbRZzJQDHAAAAAA==.Magerita:BAAANQAECgEIAgAAAA==.Magharat:BAAANQADCgYIDwABNQAECgkJKAADAB0lAA==.Magicman:BAAANQADCgYIBgAAAA==.Malacanthet:BAAANQAECgIIAgAAAA==.Malyss:BAAANQAECgUJBQAAAA==.Manangtroll:BAAANQAECgUIBQAAAA==.Mandelstam:BAAANQAECgYIEgAAAA==.Mangkanor:BAAANQADCgYICgAAAA==.Mangoloidman:BAAANQADCgIIAgABNQADCggIEAAFAAAAAA==.Marow:BAAANQADCgUICAAAAA==.Marsan:BAAANQABCggICQAAAA==.Marxen:BAAANQADCgQIBAAAAA==.',
Mc='Mcsstab:BAAANQADCgYIBgAAAA==.',
Me='Meatballer:BAAANQAECgYICAAAAA==.Meatballz:BAABNQAECoEjAAIIAAgKAyB9BgD5AgAIAAgKAyB9BgD5AgAAAA==.Mecalux:BAAANQAECgEJAQAAAA==.Meladelm:BAAANQAECggICAAAAA==.Meliodäs:BAAANQADCgYJBgABNQAECgQJCQAFAAAAAA==.Meloco:BAAANQAECgUIDAAAAA==.Melody:BAACNQAFFIEZAAIVAAcK8yGeAAC+AgAVAAcK8yGeAAC+AgA1AAQKgSMAAhUACQoaJggHAG8DABUACQoaJggHAG8DAAAA.Menj:BAAANQAECgIIAgABNQAECgkJFwAPAEYiAA==.Meno:BAAANQADCggJEQAAAA==.Meowcheese:BAAANQAECgYIDwAAAA==.Meowmix:BAAANQADCgUIBQABNQAECgcIDAAFAAAAAA==.Meridah:BAAANQADCgUIBQAAAA==.Mert:BAAANQAECgEIAQAAAA==.Mesosphere:BAEANQAECgcIDQAAAA==.',
Mi='Midorii:BAAANQAECgUICQAAAA==.Migpala:BAAANQAECgUIDgAAAA==.Miiniimaage:BAAANQAECgQIBwAAAA==.Milkmann:BAAANQABCgIIAgAAAA==.Milkymoos:BAAANQAECgcIEAAAAA==.Minar:BAABNQAECoEaAAMNAAkKkhqqBACoAgANAAgKsR2qBACoAgALAAYKoAJ5VwC5AAABNQAECgkKIwATAMMlAA==.Minoic:BAAANQADCgYIFAAAAA==.Mistamiyagi:BAAANQAECgYIDAAAAA==.Mistchivus:BAAANQAECgQIBAAAAA==.Mistelion:BAAANQAECgQIBAABNQAFFAIIAgAFAAAAAA==.Mizrah:BAAANQADCggICAABNQAECggIHQANAJIfAA==.',
Mk='Mkultra:BAAANQAECgEIAQAAAA==.',
Mo='Moarmistz:BAAANQADCgUIBQAAAA==.Mobbster:BAAANQADCggIGgAAAA==.Mohnster:BAAANQADCgMIBAAAAA==.Moiststaff:BAAANQADCgcIBwAAAA==.Moisttotems:BAAANQADCgEIAQAAAA==.Monipouch:BAABNQAECoEcAAIXAAgKrhpoAwCKAgAXAAgKrhpoAwCKAgAAAA==.Moonchicken:BAAANQADCggIDAAAAA==.Moondaisy:BAAANQADCgIIAgAAAA==.Moopocalypse:BAAANQAFFAMIAwAAAA==.Moosenukle:BAAANQADCgUICAAAAA==.Morphaeus:BAAANQADCgUICgAAAA==.Mortar:BAAANQAECgMIAwAAAA==.Mozrog:BAAANQAECggIEQAAAA==.',
Ms='Mshchase:BAAANQADCgEIAQAAAA==.',
Mu='Muffblaster:BAABNQAECoElAAMYAAkKySIfGgBbAwAYAAkKySIfGgBbAwAbAAMKuxQlHQDDAAAAAA==.Murphet:BAAANQAECgYIEgAAAA==.',
My='Mythraz:BAAANQAECgIIAgABNQAECgkJJAAMALYiAA==.Mythrix:BAAANQAECgUIBwABNQAECgkJGAASAE4hAA==.',
['Mí']='Míra:BAAANQAECgQJBwAAAA==.',
['Mó']='Mónsoon:BAAANQABCgUIBQAAAA==.',
['Mö']='Mönïca:BAAANQAECgMIBAAAAA==.Mörrys:BAAANQAECgMIAgAAAA==.',
Na='Narrath:BAAANQABCgYICAAAAA==.Narwhal:BAAANQAECggIEAAAAA==.Nathenatra:BAAANQADCgYIBwABNQAECgkJLQAWAGQhAA==.Naurea:BAAANQADCggIDwAAAA==.',
Ne='Neeko:BAABNQAECoEfAAIGAAgKjxJmEAAUAgAGAAgKjxJmEAAUAgAAAA==.Nefariti:BAAANQAECgUIAQAAAA==.Nenechi:BAAANQAECggIBwABNQAFFAQICAAZAC0NAA==.Neonmoose:BAAANQAECgMIAwABNQAECggIDQAFAAAAAA==.Nezbrez:BAAANQADCgcIDQAAAA==.Nezzrad:BAAANQADCgMIAwAAAA==.',
Nh='Nhthree:BAAANQAECgUIEQAAAA==.',
Ni='Niklaws:BAAANQAECgQIBgABNQAECgkJJgACAKwTAA==.',
No='Nofsha:BAAANQADCgUIBQABNQAECgYIEgAFAAAAAA==.Noktyx:BAAANQAECgcIBQAAAA==.Nomoney:BAAANQAECgEIAwAAAA==.Norasong:BAAANQAECgEIAgAAAA==.Norava:BAAANQAECgUICAAAAA==.Nostick:BAABNQAECoEqAAMMAAkK1SJDCAA6AwAMAAkKayJDCAA6AwALAAUKZiB+MwCvAQAAAA==.Novacrono:BAABNQAECoEeAAIGAAkKmg93DwAnAgAGAAkKmg93DwAnAgAAAA==.Noxioustoast:BAAANQAFFAIIAwAAAA==.Nozdog:BAAANQADCgYIFAAAAA==.',
Nu='Nuke:BAABNQAECoFDAAIQAAkKXB2wHAAlAwAQAAkKXB2wHAAlAwAAAA==.',
['Nô']='Nôôk:BAAANQAECgUICAAAAA==.',
Oa='Oaklánd:BAAANQAECggIAQAAAA==.',
Od='Odeinn:BAAANQADCgEIAQAAAA==.Odiare:BAAANQADCgUIBQAAAA==.',
Ok='Okayu:BAAANQAECgIIAgABNQAFFAQICAAZAC0NAA==.Okogo:BAAANQADCgQJBAABNQADCgYICgAFAAAAAA==.',
Or='Orenishi:BAAANQADCgIIAgAAAA==.Orkhis:BAAANQAECgcIEwAAAA==.',
Ou='Outbrèak:BAAANQAECgYIEgAAAA==.',
Ow='Owo:BAAANQABCgQIBQABNQAECgYIEwAFAAAAAA==.',
Oz='Ozzyosbourne:BAAANQADCggICQAAAA==.',
['Oá']='Oáklánd:BAAANQAECggIEAAAAA==.',
Pa='Pakuru:BAABNQAECoEkAAIOAAkK8hihHgCjAgAOAAkK8hihHgCjAgAAAA==.Pal:BAAANQAECgUIBwAAAA==.Palachin:BAAANQAECgcIDQAAAA==.Paladelion:BAABNQAECoEkAAQBAAkKdB33FQD9AgABAAkKdB33FQD9AgAKAAUKMBoFrwBOAQAhAAEKmR42TQBTAAABNQAFFAIIAgAFAAAAAA==.Paleonebula:BAAANQAECgMIAwAAAA==.Pallmtree:BAAANQAECgMIBQABNQAECggIEAAFAAAAAA==.Pallyberry:BAAANQADCgYIBgABNQAECgYIDwAFAAAAAA==.Pangittroll:BAAANQAECgcIEgAAAA==.Papatotems:BAAANQADCggIEQAAAA==.Papå:BAAANQAECgcIDgAAAA==.Parang:BAAANQAECgYICwAAAA==.Partyphil:BAAANQAECgQICgAAAA==.Pawtirra:BAAANQADCgIIAgAAAA==.',
Pe='Perfume:BAAANQAECgEIAQAAAA==.Persephone:BAAANQADCgMIAwABNQAECgkJHgAQAPogAA==.Petri:BAAANQAECgQJBwAAAA==.',
Ph='Phyona:BAAANQADCgYIBgAAAA==.',
Pi='Piccolö:BAAANQADCggICQABNQAECgkJKQADAH0iAA==.Pickwaton:BAABNQAECoEgAAMCAAkKqRs9GwDPAgACAAkKqRs9GwDPAgAIAAMKHwT9IwCTAAAAAA==.Pinnhead:BAAANQAECgEIAgAAAA==.Pipen:BAACNQAFFIEVAAIBAAcKowqMAgAzAgABAAcKowqMAgAzAgA1AAQKgSoAAwEACQqQDg8/ACgCAAEACQqQDg8/ACgCAAoACAoTGXNpAAUCAAE1AAEKAwgDAAUAAAAA.Pixelglitter:BAAANQADCgYJCAAAAA==.',
Pl='Pld:BAAANQADCgcIBwAAAA==.',
Po='Potatatoes:BAAANQADCgUJBQAAAA==.Poxrot:BAAANQADCgQIBAABNQAECgEIAQAFAAAAAA==.',
Pr='Praize:BAACNQAFFIEFAAMJAAMKxRA6HgCjAAAJAAIKzhI6HgCjAAAZAAEKsQywFABWAAA1AAQKgS4AAwkACQqeHnkdAN4CAAkACAr8HnkdAN4CABkABApxFG8qABMBAAAA.Press:BAACNQAFFIEOAAIKAAYKlRNbAwDwAQAKAAYKlRNbAwDwAQA1AAQKgTAAAgoACQr5JZ4DANIDAAoACQr5JZ4DANIDAAAA.Prìde:BAAANQAECgQIBAABNQAFFAcIGQAVAMIXAA==.',
Ps='Psykopathik:BAAANQAECgYIEQAAAA==.',
Pu='Puddl:BAACNQAFFIEHAAIDAAIKWg+bGACbAAADAAIKWg+bGACbAAA1AAQKgSMAAwMACQp0HfceAN4CAAMACQp0HfceAN4CAAIACArLF3ZOANkBAAAA.Purrsephone:BAAANQADCgEIAQAAAA==.',
Py='Pyrocutie:BAAANQADCggICwABNQAECgkJHQALALAcAA==.Pyrostrasz:BAAANQADCggICAABNQADCggICQAFAAAAAA==.Pyró:BAAANQAECgQIBAAAAA==.',
Qa='Qaa:BAAANQAECgQICQAAAA==.',
Qh='Qhaos:BAAANQADCgYIBgABNQADCgYIDAAFAAAAAA==.Qhaoss:BAAANQADCgYIDAAAAA==.',
Qi='Qirl:BAAANQAECgIIAwAAAA==.',
Qt='Qti:BAAANQADCggIIAAAAA==.',
Qu='Quadnines:BAAANQAECgYIEAAAAA==.Quelivia:BAAANQADCgEIAQABNQAECgcIGQATABIeAA==.Ques:BAAANQADCgcIHQAAAA==.Quesly:BAAANQAECgYIEgAAAA==.Quetzacoatl:BAAANQAECgYIDwAAAA==.',
Ra='Rabbit:BAABNQAECoEYAAMCAAkKWhJ7RAACAgACAAkKWhJ7RAACAgADAAUKiSEBVwDOAQAAAA==.Racophorus:BAAANQADCggIIAAAAA==.Raffe:BAAANQAECgQIDgAAAA==.Rammsteen:BAAANQAECgMIAgAAAA==.Rarity:BAAANQAECgIIBAAAAA==.Ratarga:BAABNQAECoEoAAIDAAkKHSU9AwDLAwADAAkKHSU9AwDLAwAAAA==.Rattroll:BAAANQAECgUICwABNQAECgkJKAADAB0lAA==.Ratzgül:BAAANQAECggICgAAAA==.Ravenaa:BAABNQAECoEiAAIKAAkK4hhkPACZAgAKAAkK4hhkPACZAgAAAA==.',
Re='Readycheck:BAAANQADCgEIAQAAAA==.Reallywanna:BAAANQAECgEIAQAAAA==.Reddragyn:BAAANQAECgYIEgAAAA==.Reeves:BAAANQAECgUIBwAAAA==.Reggiez:BAAANQADCggIKQAAAA==.Reinbert:BAAANQAECgQIBAABNQAECgcIDAAFAAAAAA==.Rektski:BAABNQAECoEjAAMTAAkKwyUfBgB8AwATAAkKgiUfBgB8AwAHAAQKzyIoTACBAQABNQAECgkKIwATAMMlAA==.Remiel:BAAANQAECgMIBAAAAA==.Remixi:BAAANQAECgIIAwAAAA==.Renzer:BAAANQAECgEIAgAAAA==.Reprosal:BAAANQAECgMIBAABNQAECggIEwAFAAAAAA==.Restasis:BAAANQADCgUIBwAAAA==.Retburn:BAABNQAECoEfAAIKAAgKUxiMWAA5AgAKAAgKUxiMWAA5AgAAAA==.Reveluv:BAAANQAECgYJCwAAAA==.',
Rh='Rheagar:BAAANQADCggJCAAAAA==.Rheveus:BAAANQAECgcICwAAAA==.',
Ri='Rickehlol:BAAANQADCgYICgAAAA==.Righturn:BAAANQAECgQIDQAAAA==.Rikkeh:BAAANQADCgIIAgAAAA==.Rinaera:BAAANQAECgYIEQAAAA==.',
Ro='Roahr:BAAANQADCgUIBAAAAA==.Rollinsmacks:BAAANQADCgIIAgAAAA==.Rollsforham:BAAANQADCggIFgAAAA==.Rondali:BAAANQADCggICAAAAA==.Rotheris:BAABNQAECoEeAAIgAAYKdQa+KQBCAQAgAAYKdQa+KQBCAQAAAA==.Rottentreats:BAAANQADCgYJCQABNQAECgQJCQAFAAAAAA==.Rottie:BAACNQAFFIEJAAIJAAUKKA2uCQBqAQAJAAUKKA2uCQBqAQA1AAQKgR8AAwkACQqIHfAwAIoCAAkACAp7HvAwAIoCABkABApfFpcsAAYBAAAA.',
Rs='Rski:BAAANQAECgMIBAAAAA==.',
Rt='Rts:BAABNQAECoEqAAIYAAkK7yVPAwDXAwAYAAkK7yVPAwDXAwAAAA==.',
Ru='Rufio:BAACNQAFFIEIAAIHAAQKRhvbCQBhAQAHAAQKRhvbCQBhAQA1AAQKgSEAAgcACQpBIxEIAGMDAAcACQpBIxEIAGMDAAAA.Rufiu:BAAANQAECgcIEwAAAA==.',
Ry='Ryjaxqt:BAAANQAECgIIAgABNQAECgcIBQAFAAAAAA==.Ryogen:BAABNQAECoEkAAMeAAkKpB1gBwDxAgAeAAkKpB1gBwDxAgAiAAIK5RKeRwBzAAAAAA==.',
['Ré']='Rén:BAAANQAECgIIAgAAAA==.',
Sa='Saarahkin:BAAANQAECgQIBQAAAA==.Sablewhisper:BAAANQAECgYIDwAAAA==.Sabryel:BAABNQAECoEsAAISAAcKFh2hSQBEAgASAAcKFh2hSQBEAgAAAA==.Saintvyn:BAABNQAECoEpAAMVAAkKjyCHDwAhAwAVAAkKjyCHDwAhAwAXAAMKWQ2sFwB4AAAAAA==.Salmonroll:BAAANQAECgYIEQAAAA==.Salos:BAAANQADCgYIBgAAAA==.Salvation:BAAANQAECgQIBQAAAA==.Samael:BAAANQADCgUIBgAAAA==.Sandarah:BAABNQAECoEjAAMBAAkKlSL6AwChAwABAAkKlSL6AwChAwAhAAUKqhcsKABCAQABNQAFFAcIGQAVAPMhAA==.Sapling:BAAANQAECgcIEgAAAA==.Sathic:BAABNQAECoEWAAIjAAgKAg72CACnAQAjAAgKAg72CACnAQAAAA==.Satreser:BAAANQAECgcIEAAAAA==.Satyra:BAAANQADCgQIBAAAAA==.',
Sc='Scallywrath:BAAANQAECgIIAgAAAA==.Scaretale:BAAANQADCgQIBgAAAA==.Scribbles:BAABNQAECoEtAAMUAAkKWiVRAQDKAwAUAAkKWiVRAQDKAwAVAAUKlCCxSQD3AQAAAA==.Scribblesz:BAAANQAECgUIBQAAAA==.Scòtt:BAAANQADCgUIBQAAAA==.',
Se='Seanthepally:BAAANQAECgQIBQABNQAECgkJIQACANYcAA==.Seantheshamm:BAABNQAECoEhAAMCAAkK1hwZLAByAgACAAkK1hwZLAByAgADAAEKMQWkDAEpAAAAAA==.Secihots:BAABNQAECoEmAAMPAAkKASL3AgCEAwAPAAkKASL3AgCEAwAOAAQKDRldXAAMAQAAAA==.Secretaznman:BAAANQAECgIJAgAAAA==.Seidhkona:BAAANQADCgYIBgABNQAECggIHQANAJIfAA==.Seiko:BAAANQADCgYJBgAAAA==.Seishirou:BAAANQADCggICAABNQAECggIEAAFAAAAAA==.Serialheal:BAAANQAECgUICgABNQAECgcIEwAFAAAAAA==.Sevalynn:BAAANQADCggIEAAAAA==.',
Sh='Shadalune:BAABNQAECoEpAAMSAAkK8SMzGwD4AgASAAkKLiIzGwD4AgARAAcKtiPcDwDGAgAAAA==.Shamanelion:BAABNQAECoEeAAMCAAkKIB3GGgDTAgACAAkKIB3GGgDTAgADAAEKZBK39gA4AAABNQAFFAIIAgAFAAAAAA==.Shamnobi:BAAANQADCgQIBAAAAA==.Shampai:BAAANQAECgIIAgAAAA==.Shazza:BAAANQADCgcJCQAAAA==.Shinso:BAAANQAFFAMIAgABNQAFFAQICAAZAC0NAA==.Shiwang:BAABNQAECoEdAAINAAgKkh+PAwDZAgANAAgKkh+PAwDZAgAAAA==.Shockazuwu:BAABNQAECoEmAAMCAAkKrBNAQwAHAgACAAkKrBNAQwAHAgADAAQKKxsIjAAuAQAAAA==.Shocktagon:BAAANQADCgEIAQAAAA==.Shocktherapy:BAAANQAECgEIAQAAAA==.Shocktroopz:BAAANQAECgYIBgAAAA==.Shockzilla:BAAANQAECgMIAwAAAA==.Shockér:BAAANQAECgQJCQAAAA==.Shodoroki:BAAANQAECggIEAAAAA==.Shogunhanzo:BAAANQADCgUJBQAAAA==.Shuu:BAABNQAECoEdAAMCAAgKKxLsVgC5AQACAAgKKxLsVgC5AQADAAMKgAi7yACcAAAAAA==.Shwoidlord:BAAANQAECgQICAABNQAECgkJJgACAKwTAA==.Shwoop:BAAANQAECgUICQABNQAECgkJJgACAKwTAA==.',
Si='Sigurrose:BAAANQAECgUIEQAAAA==.Silëntshøt:BAAANQADCgEJAQAAAA==.',
Sk='Skitzosvnff:BAABNQAECoEbAAMRAAgKuxoSFQCJAgARAAgKnRoSFQCJAgASAAMK1BIt6QCxAAAAAA==.Skrai:BAAANQADCggIBgAAAA==.',
Sl='Slugtank:BAAANQAECgIIAgABNQAFFAcIGQAVAMIXAA==.',
Sm='Smetrios:BAAANQADCggIEAABNQAECggIHQANAJIfAA==.Smokedh:BAAANQAECgcIDwABNQAECgkJHAAQAO8bAA==.Smokezug:BAABNQAECoEcAAIQAAkK7xt7NgC0AgAQAAkK7xt7NgC0AgAAAA==.',
Sn='Snorter:BAAANQADCggIDQAAAA==.Snowfury:BAABNQAFFIEFAAISAAMKBh4jCwAhAQASAAMKBh4jCwAhAQAAAA==.Snowlock:BAAANQADCgYIEAAAAA==.Snowrain:BAABNQAECoEeAAITAAkK9SGfDgAYAwATAAkK9SGfDgAYAwAAAA==.',
So='Solamina:BAAANQAECgEIAQAAAA==.Solid:BAAANQADCggICAABNQAECgYIEAAFAAAAAA==.Sotek:BAAANQABCgIIAgAAAA==.Soulster:BAAANQADCgEIAQAAAA==.Sourdeath:BAAANQAECgYIEQAAAA==.',
Sp='Spinningbrew:BAAANQAECgQIBwAAAA==.Spinseason:BAAANQADCgMIAwAAAA==.Spirittide:BAAANQABCgIIAgAAAA==.Spit:BAAANQAECgEIAQAAAA==.',
Sr='Srf:BAAANQAECgUICQABNQAFFAQIEAAFAAAAAA==.',
Ss='Ssnoosnoo:BAAANQAECgYIDAAAAA==.',
St='Stanchion:BAAANQADCgUICAAAAA==.Steelmessiah:BAAANQADCggICwAAAA==.Stiizzyy:BAAANQAECggIBQAAAA==.Stinko:BAAANQAECgIIAQABNQAFFAYIDAAaABgWAA==.Stonecrusade:BAAANQAECgQJCAAAAA==.Stonedhokage:BAABNQAECoEkAAISAAkKfxoHIwDSAgASAAkKfxoHIwDSAgAAAA==.Stopthebleed:BAAANQADCggIDwAAAA==.Sturdy:BAAANQADCgYJBgAAAA==.Sty:BAACNQAFFIEPAAILAAUKEhmYBAC9AQALAAUKEhmYBAC9AQA1AAQKgSYAAwsACQobI54HAFwDAAsACQrvIp4HAFwDAAwACAqMGRYfABwCAAAA.Ståb:BAAANQADCgYIBgABNQAECggIHAAYAHARAA==.Stårr:BAAANQADCgYIDAAAAA==.',
Su='Suffering:BAAANQADCgYIFwAAAA==.Suicideblond:BAAANQADCggIIgAAAA==.Supadrac:BAACNQAFFIEGAAIaAAMKdw+qCwD0AAAaAAMKdw+qCwD0AAA1AAQKgSYAAhoACQrEHAgJAPMCABoACQrEHAgJAPMCAAAA.Surfnturf:BAAANQAFFAQIEAAAAQ==.Surging:BAABNQAECoEaAAIYAAYKjBUTygCgAQAYAAYKjBUTygCgAQAAAA==.Suri:BAAANQAECgIIAgABNQAFFAEIAQAFAAAAAA==.Surii:BAABNQAECoEXAAIYAAgKnxA7owDzAQAYAAgKnxA7owDzAQABNQAFFAEIAQAFAAAAAA==.',
Sw='Swaazz:BAABNQAECoEsAAIaAAcKSBP9GwDHAQAaAAcKSBP9GwDHAQAAAA==.Swampypants:BAAANQAECgYICAAAAA==.Swerve:BAAANQAECgMIBAAAAA==.Swinybswipen:BAAANQAECggIAgAAAA==.',
Sy='Sycorex:BAAANQADCgEJAQAAAA==.Sykocious:BAABNQAECoEjAAIgAAgKwBLVEwApAgAgAAgKwBLVEwApAgAAAA==.Sylleria:BAAANQAECgUICAAAAA==.Syllia:BAAANQAECggIEAABNQAECgkJHgAQAOIiAA==.Syngatesx:BAAANQADCggIAQAAAA==.Syphilia:BAABNQAECoEhAAIMAAkKbhT8GABhAgAMAAkKbhT8GABhAgAAAA==.',
Sz='Szeto:BAAANQAECgcIEAABNQAFFAUIDAAMANYQAA==.',
['Sè']='Sèanthewarr:BAAANQAECgIIAgABNQAECgkJIQACANYcAA==.',
Ta='Tacocát:BAAANQAECgIIBwABNQAFFAUIFQATACYhAA==.Tacosback:BAAANQADCgEIAQABNQAFFAUIFQATACYhAA==.Tacosdk:BAACNQAFFIENAAITAAMKGyFHCQD6AAATAAMKGyFHCQD6AAA1AAQKgRgAAhMACArTJW4MAC8DABMACArTJW4MAC8DAAE1AAUUBQgVABMAJiEA.Tacoslop:BAABNQAECoEUAAIIAAgKbRKgEAAXAgAIAAgKbRKgEAAXAgABNQAFFAUIFQATACYhAA==.Tacosneak:BAAANQAECgYICgABNQAFFAUIFQATACYhAA==.Talonarayan:BAAANQADCggIIAAAAA==.Taote:BAAANQABCgIIAgAAAA==.Taskili:BAAANQADCgQIBAABNQAECgYIEwAFAAAAAA==.',
Te='Teebonez:BAAANQAECgUJBwAAAA==.Teesdays:BAAANQABCggIEwAAAA==.Tefiti:BAAANQADCgcICwAAAA==.Tetrâ:BAAANQADCgYIBgAAAA==.Tewasha:BAABNQAECoEiAAIkAAkKwB3rBAAAAwAkAAkKwB3rBAAAAwAAAA==.',
Th='Thaylen:BAAANQADCgYIBQAAAA==.Thedoofy:BAAANQAECgEJAgAAAA==.Thiccmage:BAAANQAECggIEwABNQAECgkJJAAMALYiAA==.Thorskin:BAAANQADCgUIBQAAAA==.Threellamas:BAABNQAECoEcAAIUAAkKZRaMFQBwAgAUAAkKZRaMFQBwAgAAAA==.Thuggèr:BAAANQADCgcICwAAAA==.Thunderchub:BAAANQAECgQIBAAAAA==.Thunderx:BAAANQAECgcIDQAAAA==.Thuringwethl:BAAANQAECgQIBAAAAA==.',
Ti='Tidyswet:BAAANQADCgYIBgABNQAECgcIDAAFAAAAAA==.Tinydonny:BAAANQADCgQIBQAAAA==.',
To='Tokyø:BAAANQADCgcIBwAAAA==.Tonylildik:BAAANQAECgEIAQABNQAFFAMICAAbAEwYAA==.Toolwaffle:BAAANQADCgUIBQAAAA==.Toopac:BAEBNQAECoEvAAQRAAkK4CSeAgClAwARAAkKTySeAgClAwASAAMKUR5K2wDbAAAdAAMKbBnMCwC5AAAAAA==.Totö:BAAANQAECgUIEQAAAA==.',
Tr='Tracker:BAAANQADCgUIBQAAAA==.Tramana:BAABNQAECoEhAAIIAAgKeRs4CgCbAgAIAAgKeRs4CgCbAgAAAA==.Trashxbin:BAAANQADCgUIBQAAAA==.Trauk:BAAANQAFFAEIAQAAAA==.Triggéred:BAAANQAECgQICQAAAA==.Triig:BAAANQAECgYICgAAAA==.Trollcopter:BAAANQAECgMJBAABNQAECgYIEgAFAAAAAA==.Trollreroll:BAAANQAECgQIBAAAAA==.Trollwíthbow:BAAANQAECgYIDgAAAA==.Truzxz:BAAANQAECgYIBgABNQAECgcJDwAFAAAAAA==.Trytip:BAAANQADCgcIBwABNQAECgYICwAFAAAAAA==.',
Tu='Turr:BAAANQAECgEJAQAAAA==.',
Tw='Tweedledumb:BAAANQAECgQICgAAAA==.Twìnky:BAABNQAECoEoAAMIAAkKxiAyBAA6AwAIAAkKxiAyBAA6AwACAAIKIAaC1gBgAAAAAA==.',
Ul='Ulfric:BAAANQADCgIIAgAAAA==.',
Un='Unbreakkable:BAAANQAECgcIDgABNQAFFAUICAAEAMkTAA==.Unclepete:BAAANQAECgYIDAAAAA==.Unstobubble:BAAANQABCgIIAgAAAA==.',
Ur='Urouge:BAAANQAECgUICQABNQAFFAUIDAAMANYQAA==.',
Uw='Uwutangclan:BAAANQAECgEIAQABNQAECggIEAAFAAAAAA==.',
Va='Vacula:BAAANQAECgYIEQAAAA==.Vaelyriana:BAAANQAECgcIDwAAAA==.Valreaux:BAAANQAECgYIEQAAAA==.Vandalism:BAAANQAECgUIBgAAAA==.Vanian:BAAANQADCgUIBgAAAA==.Vanqsh:BAAANQAECgUIAQAAAA==.Vanquìshh:BAAANQADCggICgAAAA==.Vayu:BAAANQADCgcIDAAAAA==.',
Vd='Vdyr:BAAANQAECgQICQAAAA==.',
Ve='Velarayna:BAAANQAECgUIBgABNQAECgkKIwATAMMlAA==.Vend:BAAANQAECggICAAAAA==.Vex:BAAANQABCgMIAwAAAA==.',
Vi='Vilgefortz:BAABNQAECoEbAAMYAAcK9BNNqADnAQAYAAcKfRNNqADnAQAbAAEKsAx0PQAuAAAAAA==.Vivelf:BAAANQADCggJAQAAAA==.',
Vo='Voidborn:BAABNQAECoEWAAIHAAgK8walWwA8AQAHAAgK8walWwA8AQAAAA==.Voidling:BAAANQAECgIIAwAAAA==.Voidturned:BAAANQADCgQIBAAAAA==.Vortexis:BAAANQAECgYIEgAAAA==.',
Vu='Vulpurra:BAAANQAECgYIEAAAAA==.Vurm:BAABNQAECoEeAAIQAAgKFiMGPQCcAgAQAAgKFiMGPQCcAgAAAA==.',
Vy='Vyndk:BAAANQAECgIIAgABNQAECgkJKQAVAI8gAA==.Vytamin:BAAANQAECgQIBQAAAA==.',
['Vâ']='Vâlinoth:BAAANQAECgYIDgAAAA==.',
['Vó']='Vólkan:BAAANQADCgcIGQAAAA==.',
Wa='Walkinghealz:BAAANQADCgQIBQABNQAECgYIEgAFAAAAAA==.',
We='Weiss:BAAANQADCggICAAAAA==.Wengo:BAAANQADCgIIBAAAAA==.',
Wh='Whistlejinky:BAAANQADCgQIBAAAAA==.',
Wi='Willywonkie:BAAANQADCgQIBgAAAA==.Winbot:BAAANQAECgUICQABNQAFFAUIDwAiALwfAA==.Windfrey:BAAANQAECgUIBwAAAA==.Windsong:BAAANQADCgYICwAAAA==.Winghollow:BAAANQADCgIIAgAAAA==.Wintershock:BAAANQAECgcIEQAAAA==.Wisk:BAABNQAECoEXAAICAAkKNB30EwD/AgACAAkKNB30EwD/AgAAAA==.',
Wl='Wll:BAAANQAECgQIBgABNQAECgkJIAAWAIsfAA==.Wlx:BAABNQAECoEgAAMWAAkKix8TGACCAgAWAAgKHx8TGACCAgATAAkKVxspKQBAAgAAAA==.',
Wo='Wobs:BAACNQAFFIEFAAIVAAIKFB/OFwC3AAAVAAIKFB/OFwC3AAA1AAQKgSIAAhUACQqOIzEIAGEDABUACQqOIzEIAGEDAAAA.Woopoles:BAAANQADCggIHAAAAA==.',
Wr='Wredgeek:BAAANQAECgQIBAAAAA==.',
Wy='Wy:BAAANQAECgUIDQAAAA==.',
Xa='Xannaria:BAAANQAECgUIAQAAAA==.Xavierboí:BAAANQAECgYIDwAAAA==.',
Xi='Xileon:BAAANQAECgUICwAAAA==.',
Xo='Xombie:BAAANQADCgUIBQAAAA==.',
Ya='Yabishus:BAAANQAECgUIBwAAAA==.Yahboibangz:BAAANQAECgYIBwAAAA==.Yamajin:BAAANQADCgIIAgAAAA==.',
Yc='Ycetz:BAAANQADCgYICgABNQAECgQIDQAFAAAAAA==.',
Ye='Yelacsa:BAAANQAECgMIBQABNQAECgkJJgACAKwTAA==.',
Yi='Yinan:BAAANQAECggICwAAAA==.',
Yo='Yoshu:BAABNQAECoEZAAIKAAgKaiRjFwBCAwAKAAgKaiRjFwBCAwAAAA==.',
Yu='Yukyukyuk:BAAANQABCgQIBAAAAA==.',
Za='Zalarax:BAAANQAECggIEAAAAA==.Zalaraxe:BAAANQAECggJCAAAAA==.Zanthu:BAEANQADCgYIBgABNQAECgkJLwARAOAkAA==.Zanu:BAAANQADCgYICwAAAA==.Zardon:BAAANQADCgYIBgABNQAFFAMIBgAGAMQlAA==.Zarnak:BAAANQADCgYIBwAAAA==.',
Ze='Zecar:BAAANQADCgUJBQAAAA==.Zengard:BAAANQADCggIEQAAAA==.Zenkic:BAAANQADCgMIAwAAAA==.Zenlock:BAAANQADCgYIBgABNQAECgcIBwAFAAAAAA==.',
Zh='Zhaman:BAAANQAECgIIAgABNQAECggIGwAQAOgfAA==.',
Zi='Zivzs:BAAANQADCgYIDQAAAA==.Zivá:BAAANQABCgYICAAAAA==.',
Zn='Znightelf:BAAANQADCgcIBwAAAA==.',
Zo='Zoralari:BAABNQAECoEcAAMIAAgKCwx0EQAEAgAIAAgKCwx0EQAEAgADAAIKkQSz5QBVAAAAAA==.Zorke:BAABNQAECoEbAAIQAAgK6B+wMwC/AgAQAAgK6B+wMwC/AgAAAA==.',
Zu='Zulnas:BAABNQAECoEcAAIHAAkKeQ3uPgDCAQAHAAkKeQ3uPgDCAQAAAA==.',
['Çh']='Çhaos:BAAANQAECggIDAAAAA==.',
['Ön']='Önonta:BAAANQAECgUIBgAAAA==.Önotoes:BAAANQAECgYIEQAAAA==.',
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
