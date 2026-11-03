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

local lookup = {'DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Hunter-BeastMastery','Priest-Discipline','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Monk-Mistweaver','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Mage-Arcane','Druid-Balance','Evoker-Devastation','Evoker-Preservation','Paladin-Holy','Priest-Shadow','DemonHunter-Devourer','Unknown-Unknown','DeathKnight-Frost','Hunter-Marksmanship','DemonHunter-Vengeance','Shaman-Elemental','Warrior-Protection','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Druid-Guardian','DemonHunter-Havoc','Monk-Windwalker','Rogue-Outlaw','Shaman-Enhancement','Shaman-Restoration','Monk-Brewmaster','Mage-Fire','Hunter-Survival',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Absofsteels:BAABNQAECn8gAAMBAAcKyRUdLgBHAQABAAcKyRUdLgBHAQACAAMKtQcDsABrAAAAAA==.',
Ac='Acaric:BAABNQAECn8cAAIDAAgKVAdpFwBAAQADAAgKVAdpFwBAAQAAAA==.',
Ad='Adrielon:BAAANQADCggIEQAAAA==.Adøra:BAACNQAFFH8IAAIEAAMKmAhtFADJAAAEAAMKmAhtFADJAAA1AAQKf1gAAgQACgrMHuAlAP8CAAQACgrMHuAlAP8CAAAA.',
Ae='Aegea:BAAANQAECgIIAgABNQAECgoKPQAFAA4ZAA==.',
Ag='Agumon:BAABNQAECn8ZAAICAAcKMRwVPQAOAgACAAcKMRwVPQAOAgAAAA==.',
Ai='Aircann:BAAANQADCggICAAAAA==.',
Al='Alchemist:BAAANQADCgUICQAAAA==.Alistair:BAAANQADCgUIBQAAAA==.Alluriel:BAAANQAECgIIBAAAAA==.Alonas:BAAANQAECgYICAABNQAECggIJgAGAPoTAA==.Altharoth:BAABNQAECn8xAAMHAAoKFBv/XACBAgAHAAoKFBv/XACBAgAIAAEKzAypcQAuAAAAAA==.Altherion:BAAANQAECgIIAQAAAA==.',
Am='Amique:BAAANQABCgIIAgAAAA==.Amira:BAAANQADCgYIDwABNQAFFAYIDAAJAPIXAA==.Amorfox:BAAANQADCgcIBwAAAA==.Amormage:BAAANQAECgUIEAAAAA==.Amphitrite:BAAANQAECggICAABNQAFFAYIDAAJAPIXAA==.',
An='Anabolicrage:BAAANQAECgIIAgAAAA==.Angmar:BAAANQAECgEIAQABNQAECgoKJgAKAFwaAA==.Anteiku:BAAANQAECgIIBAAAAA==.Anteikudeath:BAAANQADCgEIAQAAAA==.',
Ap='Applemoose:BAABNQAECn8nAAQLAAoKpx2McwAHAgALAAgKXR+McwAHAgAMAAIKhBgNUQCMAAANAAEK8BVmKQBGAAAAAA==.',
Ar='Aragrar:BAAANQAECgQIBQAAAA==.Arauial:BAABNQAECn8nAAIOAAkKMh+sNACVAgAOAAkKMh+sNACVAgAAAA==.Arcanis:BAABNQAECn82AAMPAAoKtBaLqAAxAgAPAAoKfxaLqAAxAgADAAIKBxftLwCBAAAAAA==.Aribella:BAACNQAFFH8HAAIEAAQKSQn5EwDNAAAEAAQKSQn5EwDNAAA1AAQKfykAAgQACgqQEvVgAFUCAAQACgqQEvVgAFUCAAAA.Arizae:BAAANQAECgUIDgAAAA==.Arizann:BAABNQAECn8mAAMKAAoKXBqqCgDnAgAKAAoKXBqqCgDnAgAQAAUKzRHcYwA+AQAAAA==.Arobotev:BAABNQAECn83AAMRAAgKZxLKCwBnAQARAAgKZxLKCwBnAQASAAEK7QHjOAAgAAAAAA==.',
As='Astaren:BAAANQADCgcIEAAAAA==.Astiria:BAAANQAECgIIAgAAAA==.Asuran:BAABNQAECn8VAAIGAAkKmRLtcgBxAQAGAAkKmRLtcgBxAQAAAA==.',
At='Atiya:BAACNQAFFH8HAAITAAUK7RLLCACSAQATAAUK7RLLCACSAQA1AAQKfzAAAhMACgpzIcYDANEDABMACgpzIcYDANEDAAAA.',
Az='Azaris:BAABNQAECn8hAAMUAAoK6RMIIwAaAgAUAAkK1xMIIwAaAgAOAAIK3wdQ9gBBAAAAAA==.',
Ba='Babykraze:BAABNQAECn8bAAIEAAcK1w3poQDCAQAEAAcK1w3poQDCAQAAAA==.Backshotz:BAAANQADCgMIAQAAAA==.Baelrog:BAABNQAECn8ZAAMTAAcKTwcpjgDfAAATAAcKTwcpjgDfAAAHAAUKVgQsPAHAAAAAAA==.Baiene:BAABNQAECn8VAAQMAAkKwBI9BwAzAQAMAAgKwBI9BwAzAQALAAQKgAZ6DAGzAAANAAIKUAtsIQBuAAAAAA==.Baiken:BAAANQAECgEIAQAAAA==.Baldheadelf:BAAANQADCgQIBAAAAA==.Bandalar:BAABNQAECn8lAAIVAAgKYxdSIwAvAgAVAAgKYxdSIwAvAgAAAA==.Banerino:BAAANQADCgIIAgAAAA==.Barkathemoon:BAAANQABCggICAABNQAECgIIAgAWAAAAAA==.Barnabust:BAAANQAECgcICwAAAA==.Barricaded:BAAANQAECgIIAQAAAA==.Bashems:BAAANQAECgEJAQAAAA==.Baston:BAAANQADCgIIAgAAAA==.Bastrd:BAAANQAECgQIDQAAAA==.',
Be='Bearypie:BAAANQAECggICAAAAA==.Beastums:BAABNQAECn85AAIEAAgK5xaXXgBaAgAEAAgK5xaXXgBaAgAAAA==.',
Bi='Bigbôotyjudy:BAAANQADCgIIAgAAAA==.Bigchungus:BAAANQADCggICQAAAA==.Bingbong:BAAANQADCgEIAQAAAA==.',
Bl='Blacken:BAAANQADCgQIBgAAAA==.Bleak:BAAANQADCgQIBAAAAA==.Blindmonk:BAAANQAECggIAwAAAA==.Blite:BAAANQADCgYIEgAAAA==.Bloodmary:BAABNQAECn8hAAIHAAcKTAws4ABbAQAHAAcKTAws4ABbAQAAAA==.Bloodor:BAAANQAECgEIAQAAAA==.Bloöm:BAABNQAECn9CAAIKAAoKEyMzBQBvAwAKAAoKEyMzBQBvAwAAAA==.',
Bm='Bmaazi:BAABNQAECn8nAAMSAAgKwxrlDQD3AQASAAgKwxrlDQD3AQARAAUKYgRMLADAAAAAAA==.',
Bo='Bonerina:BAAANQAECgQICQAAAA==.Boomadk:BAACNQAFFH8KAAIXAAUKyRLlBgAuAQAXAAUKyRLlBgAuAQA1AAQKf0QAAhcACgrBI2wKAEcDABcACgrBI2wKAEcDAAAA.',
Br='Bradburn:BAAANQADCgYIDAAAAA==.Bradkink:BAAANQAECgEIAQAAAA==.Brasserz:BAABNQAECn8hAAMEAAgKeRO0uwCMAQAEAAgKeRO0uwCMAQAYAAEKAABJlAAsAAAAAA==.Breezybone:BAABNQAECn8xAAIDAAoKQRwcBADzAgADAAoKQRwcBADzAgAAAA==.Briaela:BAAANQADCgIIAgAAAA==.Brice:BAAANQADCgYICgAAAA==.Briochebun:BAABNQAECn8cAAIHAAkKRxUYeQA6AgAHAAkKRxUYeQA6AgAAAA==.',
Bw='Bwangifer:BAABNQAECn84AAIZAAgKSBwwBwDgAQAZAAgKSBwwBwDgAQAAAA==.',
['Bë']='Bëcky:BAABNQAECn8wAAQHAAoKxyVOFgDyAgAHAAoKxyVOFgDyAgATAAYKYxL4kQBpAQAIAAIKWyFAMQDFAAAAAA==.',
Ca='Calabera:BAAANQADCgYIBgAAAA==.Caloren:BAABNQAECn8nAAIEAAoKrSNWDQB0AwAEAAoKrSNWDQB0AwABNQAECgkJNAAVADkcAA==.Camerarius:BAAANQAECgEIAQAAAA==.Cannala:BAAANQADCgYIEgAAAA==.Cargae:BAAANQADCgYIEgAAAA==.Caso:BAAANQADCgMIBAABNQAECgUICwAWAAAAAA==.',
Ce='Cellysia:BAABNQAECn8tAAMOAAkKaQTEkwDmAAAOAAkKaQTEkwDmAAAUAAIKFgPCdQA7AAAAAA==.Ceres:BAABNQAECn85AAIMAAgK/xZLCgBSAgAMAAgK/xZLCgBSAgAAAA==.Cesara:BAABNQAECn9EAAMUAAoKsRryEQDfAgAUAAoKsRryEQDfAgAOAAMKfwcTswCaAAAAAA==.',
Ch='Chal:BAABNQAECn8qAAIHAAcKxAl+6QBJAQAHAAcKxAl+6QBJAQAAAA==.Chaplin:BAAANQAECgMIBAABNQAECggIGwAaAIgMAA==.Chbribs:BAAANQAECgYIDwAAAA==.Chestypanda:BAAANQADCgQIBAAAAA==.Chillypepper:BAAANQAECgQIBAAAAA==.Chiptewth:BAAANQABCgYICQAAAA==.Chiron:BAAANQADCgEIAQAAAA==.',
Co='Coldsteel:BAAANQADCggIKAAAAA==.Columbina:BAABNQAECn8iAAIVAAoKhBOjKAD/AQAVAAoKhBOjKAD/AQAAAA==.Cooperhowerd:BAAANQADCgYIEAAAAA==.Corky:BAAANQADCgEIAQABNQAECgoKJgAKAFwaAA==.Corn:BAAANQADCgIIAgABNQAECgcIEAAWAAAAAA==.',
Cp='Cptredbeardd:BAAANQADCgYIDgAAAA==.',
Cr='Crackmonger:BAACNQAFFH8FAAIGAAIKLxXkLACWAAAGAAIKLxXkLACWAAA1AAQKfyMAAgYACQquGh9ZAIACAAYACQquGh9ZAIACAAAA.Crackundead:BAACNQAFFH8FAAIXAAIKJA75FgCIAAAXAAIKJA75FgCIAAA1AAQKfzsAAhcACgo2GechAH4CABcACgo2GechAH4CAAAA.Crapdragon:BAAANQAECgUIBgAAAA==.',
Cy='Cyphr:BAABNQAECn83AAIKAAgK4h3dFAA0AgAKAAgK4h3dFAA0AgAAAA==.Cyrinx:BAAANQAECggIEQAAAA==.',
Da='Daen:BAAANQADCggICAAAAA==.Dagravytrain:BAAANQAECgUJBgAAAA==.Dain:BAAANQADCgYIDAAAAA==.Dalend:BAABNQAECn8eAAMGAAoKVhuuRQAAAgAGAAoK9BquRQAAAgAbAAIKUhs0NACVAAAAAA==.Damerot:BAABNQAECn8rAAMcAAoK2hUVBwANAgAcAAoK2hUVBwANAgAbAAEK2geMPgAqAAAAAA==.Dangerous:BAABNQAECn8aAAIdAAcKag5XHgAhAQAdAAcKag5XHgAhAQAAAA==.Danpal:BAAANQADCggICQAAAA==.Dansharo:BAAANQADCgMIAwAAAA==.Darc:BAAANQAECgQIBAAAAA==.Darnnix:BAAANQAECgUICwAAAA==.Darthrevin:BAABNQAECn8iAAMeAAkKPA5EJACmAQAeAAkKOw1EJACmAQAdAAYKMAhnYAAzAQAAAA==.Dawnsingers:BAAANQADCggIFgAAAA==.',
De='Deadbeard:BAABNQAECn9UAAQXAAoKziXhAgC4AwAXAAoKziXhAgC4AwACAAYKJR2xSQDRAQABAAQKASTDeAA3AQAAAA==.Deathbash:BAAANQADCgEIAQAAAA==.Deathdream:BAAANQAECgIIAgAAAA==.Deathrar:BAAANQADCgcICwAAAA==.Deathviix:BAAANQAECgUICgAAAA==.Debased:BAABNQAECn8pAAIBAAgKGxUSJgB/AQABAAgKGxUSJgB/AQAAAA==.Demini:BAAANQADCgYIDQAAAA==.Demisê:BAABNQAECn9QAAICAAoK3Bp0FwAiAgACAAoK3Bp0FwAiAgAAAA==.Demonn:BAAANQAECgcIEgAAAA==.Derbygirl:BAAANQADCgYIDQAAAA==.Desperation:BAABNQAECn8WAAIIAAkKOhNUKACbAQAIAAkKOhNUKACbAQAAAA==.Desso:BAAANQAECgcIEgAAAA==.Detraz:BAAANQABCgEIAQAAAA==.Devilskin:BAAANQADCgUICgAAAA==.',
Di='Dillinger:BAAANQAECgYIBgAAAA==.Dingodgaf:BAABNQAECn8zAAIHAAcKTgjX8AA7AQAHAAcKTgjX8AA7AQAAAA==.',
Dj='Djinnjuicy:BAABNQAECn8dAAIPAAcKpQivHAFcAQAPAAcKpQivHAFcAQAAAA==.',
Do='Dodo:BAAANQAECgQICgAAAA==.Dorianmyth:BAABNQAECn8aAAIIAAgKRAecOAAnAQAIAAgKRAecOAAnAQAAAA==.',
Dr='Dragonshammy:BAAANQADCgMIAwABNQAECgoKLwATAGQdAA==.Drazzi:BAAANQAECgEIAQAAAA==.Dreamclaw:BAABNQAECn8lAAMfAAoK9g2/EwBAAQAfAAoKDg2/EwBAAQAgAAQKkwpgRQCeAAAAAA==.Drippindots:BAACNQAFFH8IAAMLAAQKIBstKgC1AAALAAMKiR8tKgC1AAAMAAEKThLTDgBMAAA1AAQKf0EAAwsACgrmIXoLAHEDAAsACgrmIXoLAHEDAAwAAQrOHeQjAFYAAAAA.Driztette:BAAANQAECgYICgAAAA==.Drnewport:BAAANQADCggIEwAAAA==.Drokash:BAAANQAECgYIBgAAAA==.Drystine:BAABNQAECn8bAAIhAAcKfg9MTABuAQAhAAcKfg9MTABuAQAAAA==.',
Dy='Dyronebiggum:BAAANQADCggIDAAAAA==.',
['Dí']='Dín:BAAANQAECgcIEQAAAA==.',
Ec='Ectharienne:BAAANQABCgMIAwAAAA==.',
Ee='Eedeeweewee:BAAANQADCgYIEgAAAA==.',
Eg='Eggs:BAAANQADCgEIAQAAAA==.',
Ei='Eillaura:BAABNQAECn9EAAIOAAoKfxupLgBUAgAOAAoKfxupLgBUAgAAAA==.',
El='Electroshokk:BAAANQAECgIIAgABNQAECgQIBQAWAAAAAA==.Elemag:BAAANQAECgUIBQAAAA==.Eleredra:BAAANQADCgYIBgABNQAECgkJJQAUAOASAA==.Elipsis:BAACNQAFFH8IAAIOAAQK6BpvEwA3AQAOAAQK6BpvEwA3AQA1AAQKfzYAAg4ACgqiJFcHAIoDAA4ACgqiJFcHAIoDAAAA.Elm:BAABNQAECn8eAAMQAAgKAhMiQQD0AQAQAAgKAhMiQQD0AQAKAAIK6gxuaABjAAAAAA==.Elybella:BAAANQADCgMIAwABNQAFFAUICAASAEsWAA==.Elycia:BAAANQAECgYIBwABNQAFFAUICAASAEsWAA==.Elyenora:BAACNQAFFH8IAAISAAUKSxYACABoAQASAAUKSxYACABoAQA1AAQKfywAAhIACgrxFw8WAFUCABIACgrxFw8WAFUCAAAA.',
En='Enquea:BAAANQAECgYICgABNQAECgoKJgAKAFwaAA==.Enricco:BAAANQAECgEIAQAAAA==.',
Er='Eraeste:BAAANQABCgQIAwAAAA==.Ereko:BAABNQAECn8mAAIEAAgKLA1opQC7AQAEAAgKLA1opQC7AQAAAA==.Eriss:BAABNQAECn8qAAIPAAoK5hDEWADhAQAPAAoK5hDEWADhAQAAAA==.Erythorbic:BAABNQAECn8kAAMLAAgKmRkKagBfAQALAAcKdxgKagBfAQAMAAMKeRiVGAB+AAAAAA==.',
Es='Estralage:BAAANQADCgUICwAAAA==.',
Ev='Evictor:BAAANQADCgIJAgABNQAECggIFQAiAP4SAA==.',
Fa='Fanaticism:BAAANQAECgMIAwAAAA==.Fangs:BAAANQAECggIDQABNQAECgkJHQAMAMUZAA==.Faranth:BAABNQAECn8cAAIEAAgKJxSdhgBiAQAEAAgKJxSdhgBiAQAAAA==.Fatman:BAAANQAECgIIBAABNQAECgUIBQAWAAAAAA==.',
Fe='Feer:BAAANQADCgQICAAAAA==.Feldron:BAAANQAECggIEQAAAA==.',
Ff='Ffugher:BAAANQAECgUICgAAAA==.Ffugme:BAABNQAECn8wAAMIAAoKjQkwOAAqAQAIAAoKTAkwOAAqAQAHAAYKiQVh8ADGAAAAAA==.Ffugnutz:BAAANQADCgQIBAAAAA==.Ffugoff:BAABNQAECn8XAAIaAAYK9AstcgD6AAAaAAYK9AstcgD6AAAAAA==.Ffugtard:BAABNQAECn8nAAIEAAkKCxDLgABvAQAEAAkKCxDLgABvAQAAAA==.Ffugyou:BAAANQADCggICwAAAA==.',
Fi='Finnian:BAABNQAECn8qAAITAAgKpRPhQwDRAQATAAgKpRPhQwDRAQAAAA==.Fio:BAAANQAECgYICQAAAA==.Firiona:BAABNQAECn8XAAMOAAgKDh0MMwA+AgAOAAcKIBwMMwA+AgAUAAUKDRR1MwC7AAABNQAECgkJMQAeAHseAA==.',
Fl='Flinn:BAAANQADCgIIAgAAAA==.Flowers:BAABNQAECn8qAAIVAAcKrR+FIABJAgAVAAcKrR+FIABJAgAAAA==.Fläva:BAAANQAECgEIAQAAAA==.',
Fo='Foot:BAAANQADCgYICgAAAA==.Forfuncasual:BAABNQAECn8iAAIjAAkKJxyABQCTAgAjAAkKJxyABQCTAgAAAA==.Foxhound:BAABNQAECn8jAAIiAAcKMw2ONgBhAQAiAAcKMw2ONgBhAQAAAA==.',
Fr='Fracture:BAAANQADCggICAABNQAECggILQAkALUIAA==.Fresca:BAAANQADCgEIAQAAAA==.Friendlyhoss:BAAANQADCgIIAgAAAA==.Frostypie:BAAANQADCggIEAAAAA==.',
Fu='Funkyfungi:BAAANQAECgIIAgAAAA==.Furyswarm:BAAANQAECggIBgAAAA==.',
['Fö']='Föx:BAAANQADCgYIBgAAAA==.',
Ga='Gaius:BAAANQAECgQICAABNQAECgUIBQAWAAAAAA==.Gawdcomplex:BAABNQAECn8bAAITAAcKYQzHiwB5AQATAAcKYQzHiwB5AQAAAA==.',
Ge='Gernaj:BAAANQADCgcICwAAAA==.',
Gh='Ghostfrudge:BAAANQADCggICAAAAA==.Ghostfudge:BAABNQAECn8yAAQIAAoKyxtkDgC1AgAIAAkKpx9kDgC1AgAHAAIKqwEciwEaAAATAAEKywAt+gAJAAAAAA==.Ghostlyfudge:BAAANQAECgEIAQAAAA==.',
Gi='Ginny:BAABNQAECn8aAAIIAAgKfwkGLADjAAAIAAgKfwkGLADjAAAAAA==.Ginsan:BAAANQADCgEIAQAAAA==.Ginthalos:BAAANQADCgcIEQAAAA==.',
Go='Golaru:BAAANQABCgIIAgAAAA==.',
Gr='Gramthyr:BAAANQADCgYIEgAAAA==.Grep:BAAANQADCgMIAwAAAA==.Greygor:BAAANQAECgYICwAAAA==.Grotok:BAAANQAECgIIAgABNQAECggIJQAEAGYVAA==.',
Gu='Gumer:BAABNQAECn8iAAMlAAkKrAzvmwBAAQAlAAkKrAzvmwBAAQAaAAUK0QIj7wC4AAAAAA==.Gurgatron:BAABNQAECn8dAAMdAAoKoxBtDADhAQAdAAoKoxBtDADhAQAjAAIK4QX4GABVAAABNQAECgoKPAAbACEmAA==.Guulen:BAAANQADCgIIAgAAAA==.',
['Gá']='Gárd:BAAANQAECgYIBgAAAA==.',
Ha='Halygos:BAAANQAECgQIBwAAAA==.Hariffug:BAAANQADCgcIBwAAAA==.Hasklaufien:BAAANQAECgcIEgAAAA==.',
He='Healinside:BAAANQAECgQICQABNQAECgoKLwATAGQdAA==.Hellvina:BAAANQADCggICAAAAA==.Hermie:BAAANQABCggICAAAAA==.',
Hi='Hinderberg:BAAANQAECgEIAQAAAA==.',
Ho='Holdor:BAABNQAECn8XAAMBAAYKqw0wPAD4AAABAAYKqw0wPAD4AAACAAQKdQOxeABfAAAAAA==.Horde:BAAANQADCgIIAgAAAA==.Horizons:BAAANQAECgIIAgAAAA==.',
Hu='Huntsum:BAABNQAECn8lAAMEAAgKZhVJfAAVAgAEAAcKthdJfAAVAgAYAAYKhgy0NgCdAAAAAA==.',
Ia='Iahsotgievhu:BAAANQADCgcICAAAAA==.Iamspeed:BAAANQABCgEIAQAAAA==.',
Ic='Iceblocklulz:BAAANQADCgMIAwAAAA==.Icedsoul:BAABNQAECn8ZAAMDAAYKrgrMHwDrAAADAAUKrgrMHwDrAAAPAAMKrAGargFkAAAAAA==.Iceflame:BAAANQADCgYIBgABNQAECgcIIwAKAMsbAA==.',
Ig='Iggey:BAABNQAECn8jAAIGAAoKjhHOlwDhAQAGAAoKjhHOlwDhAQAAAA==.',
Ik='Ikkaku:BAAANQADCggIDQAAAA==.',
Il='Ilandras:BAABNQAECn8hAAIVAAkKExY9JAAlAgAVAAkKExY9JAAlAgAAAA==.Illadus:BAABNQAECn8aAAIVAAgKDgwxPwBRAQAVAAgKDgwxPwBRAQAAAA==.Illiviix:BAAANQADCgcIHgAAAA==.',
In='Indra:BAABNQAECn8uAAIHAAkK2B1mSwCzAgAHAAkK2B1mSwCzAgAAAA==.Intoxicated:BAAANQAECgQICAAAAA==.',
Ir='Iranna:BAACNQAFFH8XAAMdAAcK4CObAQCHAQAdAAUK/ySbAQCHAQAeAAMKyyH3EABsAAA1AAQKfy8AAx0ACgosJR4NABwDAB0ACgoKJR4NABwDAB4ACAqUI+QdAGwCAAAA.',
It='Itsredbelow:BAAANQAECgEIBAAAAA==.',
Iz='Izlaz:BAAANQADCggICAAAAA==.',
Ja='Jacrispy:BAAANQAECgIJAwAAAA==.Jaggedace:BAABNQAECn8xAAQXAAoKJwc0QABbAQAXAAoKKQY0QABbAQACAAYKvgR3igDWAAABAAQKQQdSVgCJAAAAAA==.Janaki:BAABNQAECn9HAAMKAAoKUB1MCAAaAwAKAAoKUB1MCAAaAwAQAAYKiQhccAAJAQAAAA==.',
Je='Jellyfish:BAABNQAECn8YAAIHAAcK7hJovgAXAQAHAAcK7hJovgAXAQAAAA==.',
Ji='Jibbtotem:BAAANQADCgYIDQABNQAECgkJHwAUAI8WAA==.Jivanos:BAAANQADCgUIBQAAAA==.',
Jo='Joexotick:BAAANQABCgMIBQAAAA==.Jonnyquestt:BAABNQAECn8nAAIHAAgKXA3qtQCyAQAHAAgKXA3qtQCyAQAAAA==.',
Ju='Junlock:BAAANQAECgYICgABNQAFFAcIFgAVAIsXAA==.Junrush:BAACNQAFFH8WAAIVAAcKixcVAgCLAQAVAAcKixcVAgCLAQA1AAQKfy8AAxUACgoMI1sIALcCABUACgoMI1sIALcCABkAAQoAAMcvAD8AAAAA.Junshot:BAAANQAECgEIAQABNQAFFAcIFgAVAIsXAA==.',
Ka='Kalea:BAAANQABCgIIBAAAAA==.Kalietha:BAABNQAECn8UAAMMAAcKFQgcSACnAAALAAcKKAWX0QAmAQAMAAMK3gwcSACnAAAAAA==.Karaizula:BAABNQAECn8rAAMlAAoKgQ9jQQDeAQAlAAoKgQ9jQQDeAQAaAAQKTwFGBgGBAAAAAA==.Kasdeya:BAAANQADCgYIBwAAAA==.Kassandrah:BAAANQADCgUIBQAAAA==.Katsuko:BAABNQAECn8yAAICAAkKZxVjKACSAQACAAkKZxVjKACSAQAAAA==.Kattnirra:BAABNQAECn8iAAIEAAgKqwodqgCxAQAEAAgKqwodqgCxAQAAAA==.Katze:BAABNQAECn8mAAIEAAkKRhEzZABNAgAEAAkKRhEzZABNAgAAAA==.Kaylé:BAAANQAECgMIAwAAAA==.',
Ke='Keepper:BAAANQAECgQIBwAAAA==.Kenj:BAABNQAECn8zAAIOAAoKdCPuBgCOAwAOAAoKdCPuBgCOAwABNQAFFAYIEgAKAF0dAA==.Kenjurr:BAABNQAECn8fAAMSAAkKTB/HBgA6AwASAAkKTB/HBgA6AwARAAIKOAtdNQBiAAABNQAFFAYIEgAKAF0dAA==.Kenslynn:BAABNQAECn8pAAIOAAoKYRykKQDCAgAOAAoKYRykKQDCAgAAAA==.Ketheric:BAAANQADCgEIAQABNQAECgkJHQAMAMUZAA==.',
Ki='Kiannor:BAABNQAECn8qAAIiAAgKzwZuKgAPAQAiAAgKzwZuKgAPAQAAAA==.Killahaseo:BAABNQAECn8pAAIHAAoKeiH0SQC3AgAHAAoKeiH0SQC3AgAAAA==.Killmoedee:BAABNQAECn82AAMIAAkKDCA5EACaAgAIAAkKDCA5EACaAgAHAAMKCQUNSwFQAAAAAA==.Kishibe:BAAANQAECgUIDQAAAA==.Kiss:BAAANQAECggIEwABNQAFFAgILgAlAGokAA==.Kitwryn:BAAANQADCgYIEgAAAA==.',
Kl='Klexios:BAAANQAECgQIDAAAAA==.',
Ko='Koopa:BAAANQAECgcIEAAAAA==.',
Kr='Kraulhoof:BAAANQAECgEIAQABNQAECgQIBQAWAAAAAA==.Kronohs:BAAANQAECgIIAwAAAA==.Krymson:BAAANQADCgcIBwAAAA==.',
Ku='Kui:BAABNQAECn80AAImAAgK1RuhBgDZAQAmAAgK1RuhBgDZAQAAAA==.Kuneia:BAAANQADCgQIBAABNQAECgoKRwAKAFAdAA==.Kurakka:BAAANQADCgEIAQAAAA==.Kuyna:BAAANQADCgYIDgAAAA==.',
Ky='Kylohendrix:BAAANQAECgQIBAAAAA==.',
['Kö']='Köz:BAAANQADCgQIBAAAAA==.',
La='Laetri:BAAANQAECgQIBAAAAA==.Lailiia:BAABNQAECn8hAAIJAAcKFBJtHwCVAQAJAAcKFBJtHwCVAQABNQAECggIDwAWAAAAAA==.Laindrin:BAAANQADCgcIDQAAAA==.Lavendarlace:BAAANQADCgYIDAAAAA==.Lawrence:BAAANQADCggICAAAAA==.Lazloo:BAABNQAECn8zAAIGAAkKaCRqJgAfAwAGAAkKaCRqJgAfAwAAAA==.Lazymidget:BAABNQAECn8YAAIYAAkKYgduOQCFAQAYAAkKYgduOQCFAQAAAA==.Lazytok:BAAANQAECgYIBAAAAA==.',
Le='Leftÿ:BAABNQAECn9IAAIXAAoKsB0fEgD8AgAXAAoKsB0fEgD8AgAAAA==.Legindkiller:BAAANQADCgYIEgAAAA==.Lenie:BAABNQAECn8bAAQOAAkKLSFhEwASAwAOAAgK5iJhEwASAwAUAAIKigpVUQA9AAAFAAEKVwnvMgAbAAABNQAFFAYIEwACAGghAA==.Levoyon:BAABNQAECn8fAAIkAAkKiQbfFQBwAQAkAAkKiQbfFQBwAQAAAA==.Lexibelle:BAABNQAECn80AAILAAkKlAy1ZwBlAQALAAkKlAy1ZwBlAQAAAA==.Lexsing:BAAANQABCgEIAQAAAA==.',
Lf='Lfty:BAAANQADCggIDAABNQAECgoKSAAXALAdAA==.',
Li='Lianthael:BAAANQAECgUIBQABNQAECggIJQAEAGYVAA==.Lightace:BAABNQAECn8yAAMHAAoKsgu3pwA+AQAHAAoKage3pwA+AQAIAAYK0A8KPQAMAQAAAA==.Lightbunny:BAAANQAECggIEQAAAA==.Lightlicious:BAAANQADCgQIBAAAAA==.Lincia:BAAANQAECgQIBgAAAA==.Linkkil:BAAANQAECgYICwAAAA==.Liv:BAAANQADCgMIAwABNQAECgkJGAAOAFAXAA==.',
Lo='Loastotem:BAAANQADCgIIAgAAAA==.Lobos:BAABNQAECn8tAAILAAkKhA5OdQACAgALAAkKhA5OdQACAgAAAA==.Lockrah:BAAANQADCgYIEAAAAA==.Lorvinion:BAAANQAECgMIBAAAAA==.Lostdraco:BAAANQAECgYIDgAAAA==.Lostdream:BAABNQAECn87AAMhAAoKrQleMwBDAQAhAAoKrQleMwBDAQAZAAgKhAWCHgDaAAAAAA==.Loun:BAABNQAECn8cAAImAAgKvBn4CwBHAgAmAAgKvBn4CwBHAgAAAA==.',
Lu='Luiss:BAABNQAECn8cAAIHAAYKDAc1AwGrAAAHAAYKDAc1AwGrAAAAAA==.Luminism:BAABNQAECn8dAAMTAAoKvxnSPgBpAgATAAoKvxnSPgBpAgAHAAEKAACCjgFGAAABNQAECggIEQAWAAAAAA==.Luvlycruelty:BAAANQAECgYIDQAAAA==.',
Ly='Lycos:BAAANQABCgQIBAAAAA==.Lyn:BAEBNQAECn81AAImAAoKaCZmAADvAwAmAAoKaCZmAADvAwAAAA==.',
['Lê']='Lêônà:BAAANQABCggICAAAAA==.',
Ma='Maazi:BAAANQADCgYIBgAAAA==.Mackenziiee:BAABNQAECn89AAIEAAoKAhgROwC5AgAEAAoKAhgROwC5AgAAAA==.Magerick:BAAANQAECgYIDgAAAA==.Magicwater:BAAANQADCggICwABNQAECgoKMwAHAGgkAA==.Magtaki:BAAANQADCgEJAQAAAA==.Mainline:BAAANQAECgUICgAAAA==.Maizepriest:BAABNQAECn8qAAIUAAkKgh6hDgA9AgAUAAkKgh6hDgA9AgAAAA==.Maliaa:BAAANQAECgIIAgAAAA==.Malloryrose:BAAANQADCgcIBwAAAA==.Mandrison:BAABNQAECn8ZAAIGAAkKKA8VTwDfAQAGAAkKKA8VTwDfAQAAAA==.Masfima:BAAANQADCgIIAgAAAA==.Maxz:BAAANQADCggIHAAAAA==.',
Mc='Mcstàbby:BAAANQABCgMIAwAAAA==.',
Me='Meerkat:BAAANQAECgUIBAAAAA==.Mellowblink:BAABNQAECn8YAAIPAAYKmBWJAAGNAQAPAAYKmBWJAAGNAQABNQAECgkJMQAeAHseAA==.Mellowlink:BAABNQAECn8xAAMeAAkKex76DQCXAgAeAAkKex76DQCXAgAdAAEKURL9XAA4AAAAAA==.',
Mi='Migglet:BAAANQAECgMIAwAAAA==.Miirya:BAAANQADCgYIAwAAAA==.Milkybar:BAAANQAECggIDgAAAA==.Mimi:BAACNQAFFH80AAMEAAoKqSVPAgBYAgAYAAkKLSRBAQBhAgAEAAYKLiZPAgBYAgA1AAQKfzIAAxgACgrEJoEGAGgDABgACgpkJoEGAGgDAAQACApFJj8mAP4CAAAA.Miramage:BAAANQADCgcIBwABNQAECgoKJQAEACEcAA==.Miravus:BAAANQAECgcIEgABNQAECgoKJQAEACEcAA==.Mirlanda:BAAANQAECgIIBAAAAA==.Misttie:BAABNQAECn8nAAImAAoKwxxuAwCDAgAmAAoKwxxuAwCDAgABNQAFFAQICAAOAOgaAA==.Mitcheoff:BAAANQAECgQIDgAAAA==.',
Mo='Moisturizer:BAAANQAECgUICwAAAA==.Moltenkam:BAAANQADCgEIAQAAAA==.Monkerick:BAAANQADCgQIBwAAAA==.Mooningyall:BAAANQAECgQIBAAAAA==.Mowte:BAAANQADCgYIEgAAAA==.',
Mu='Murkoobi:BAAANQAECgEIAQAAAA==.',
My='Mystrial:BAAANQABCgcICwAAAA==.Mystáke:BAAANQAECggIDgAAAA==.',
['Mó']='Mómo:BAAANQADCgMIAwAAAA==.Móus:BAAANQADCgIIAgABNQAECgkJIwAlAOMTAA==.',
Na='Narbus:BAABNQAECn8UAAIQAAUKBQ4acAAKAQAQAAUKBQ4acAAKAQAAAA==.Narcissus:BAAANQADCgUIDgAAAA==.Naromancer:BAABNQAECn85AAIPAAkKrCFJMQBdAgAPAAkKrCFJMQBdAgAAAA==.Nathadon:BAABNQAECn9FAAIUAAoKLSBICQBKAwAUAAoKLSBICQBKAwAAAA==.Nautrium:BAAANQAECgQIBwAAAA==.',
Ne='Necrotis:BAAANQADCgYIEgAAAA==.Nekhraros:BAABNQAECn8dAAMMAAkKxRmPMAAGAQALAAYKHhYwogCRAQAMAAMKox6PMAAGAQAAAA==.Neko:BAAANQAECggIEAABNQAECgkJrQAJAPMmAA==.Nergál:BAAANQADCgYIBQABNQADCggICAAWAAAAAA==.Nevelia:BAAANQAECggIDwAAAA==.Neytfury:BAAANQADCgUIBQAAAA==.Neyti:BAAANQADCgIIAgAAAA==.Neytvengy:BAAANQAECgMIAwAAAA==.Nezukô:BAAANQADCgUICQAAAA==.',
Ni='Nienna:BAAANQAECgMIBAABNQAECgoKJgAKAFwaAA==.Nightwulf:BAAANQADCgIIAgAAAA==.Nikkikynz:BAAANQABCgIIAgAAAA==.Nikkisan:BAAANQADCgYIGAAAAA==.Nixk:BAAANQAECgYIEAAAAA==.',
No='Noapte:BAAANQADCgYICQAAAA==.Noixi:BAABNQAECn8kAAMDAAcKuAmTJACGAAAPAAcKTAaD0QDcAAADAAQKfQqTJACGAAAAAA==.Noras:BAABNQAECn8VAAIiAAgK/hLyJgDqAQAiAAgK/hLyJgDqAQAAAA==.Nordicslayer:BAAANQAECgEIAQAAAA==.Notagnoblin:BAECNQAFFH8bAAICAAcKKCOmAgD7AQACAAcKKCOmAgD7AQA1AAQKfzkAAgIACgqmJuwBAGcDAAIACgqmJuwBAGcDAAAA.Notrick:BAAANQAECgQIBwAAAA==.',
Nu='Nuffsaid:BAAANQADCgUIBgAAAA==.',
Ny='Nyko:BAAANQADCgUIBgAAAA==.',
Oa='Oaklyn:BAAANQADCgUIBQAAAA==.',
Ob='Obolisq:BAAANQADCgIIAgAAAA==.Obsidious:BAAANQAECgYICQAAAA==.',
Od='Oddsoul:BAAANQAECgIIAgAAAA==.',
Og='Ogrelurd:BAABNQAECn9OAAMGAAoK+B3SIACjAgAGAAoK+B3SIACjAgAcAAEKAAAfNQAAAAAAAA==.',
Ol='Oliveia:BAAANQADCgQIBAAAAA==.',
Op='Opalfox:BAAANQADCgEIAQAAAA==.Ophelia:BAABNQAECn9AAAQNAAoKax9dCwC2AQALAAgKiR7dPQDrAQANAAUKqyBdCwC2AQAMAAIK6xKWVACBAAAAAA==.',
Or='Orakwa:BAABNQAECn8VAAMGAAkKoBGqjwD1AQAGAAkKoBGqjwD1AQAcAAQKshEfGwD1AAAAAA==.',
Os='Osteroth:BAAANQADCggIEQAAAA==.',
Pa='Pachez:BAAANQAECgIIAgAAAA==.Paladont:BAAANQAECgUICwAAAA==.Pallinda:BAABNQAECn8vAAMTAAoKZB3pFwDLAgATAAoKZB3pFwDLAgAHAAYKoQ4s6wBFAQAAAA==.Palmogant:BAAANQAECgYIEQAAAA==.Panztide:BAAANQADCgcIBwABNQAECgkJKQAfAMESAA==.Pappyoblues:BAAANQAECgEIAgAAAA==.Patt:BAAANQADCgUIBQAAAA==.',
Pe='Pendulumlaw:BAACNQAFFH8RAAIGAAYK3wjUEgDpAAAGAAYK3wjUEgDpAAA1AAQKfy4AAgYACgpkGT1nAFoCAAYACgpkGT1nAFoCAAAA.Pennypacker:BAAANQAECgUICQABNQAECgoKJgAKAFwaAA==.Pepe:BAAANQADCgEIAQAAAA==.',
Ph='Phinn:BAABNQAECn8qAAIQAAcKkwnyRQDZAAAQAAcKkwnyRQDZAAAAAA==.Phoel:BAAANQADCgUIDAAAAA==.Phoopanchu:BAABNQAECn8UAAIJAAcKzgwKGQA2AQAJAAcKzgwKGQA2AQAAAA==.',
Pi='Pimikoh:BAAANQAECgQIBAAAAA==.Pinkbuns:BAABNQAECn8dAAIDAAgK2h2kCQA4AgADAAgK2h2kCQA4AgAAAA==.',
Pn='Pneuma:BAABNQAECn8XAAIZAAgKmRwACADCAQAZAAgKmRwACADCAQAAAA==.',
Po='Pollonius:BAAANQADCgQIBAAAAA==.Poncho:BAAANQADCgIIAgAAAA==.Popsy:BAAANQAECgUIBQAAAA==.',
Pr='Praxel:BAAANQAECgUIBQAAAA==.Prenton:BAABNQAECn8zAAIGAAkKBxlYUwDQAQAGAAkKBxlYUwDQAQAAAA==.Prepotente:BAAANQAECgMIBAABNQAECgkJMQAeAHseAA==.Prideflag:BAAANQADCggICAAAAA==.Priestin:BAAANQAECgEIAQAAAA==.Profundity:BAAANQAECgEIAQABNQAECgoKJgAKAFwaAA==.',
Ps='Psyduck:BAABNQAFFH8FAAIGAAUKfAszFwBpAQAGAAUKfAszFwBpAQABNQAFFAoKNAAHAI4kAA==.',
Pu='Punie:BAABNQAECn8mAAIaAAgKfRZQVgAhAgAaAAgKfRZQVgAhAgAAAA==.Punkte:BAAANQAECgQIBAAAAA==.Puzzykat:BAAANQADCgYIBgAAAA==.',
Pv='Pvptankin:BAAANQAECgEIAQABNQAECggIAgAWAAAAAA==.',
['Pä']='Päg:BAAANQADCgEIAQABNQAECgoKSAAXALAdAA==.',
Qe='Qeini:BAABNQAECn8rAAIFAAcKbgwvDgBMAQAFAAcKbgwvDgBMAQAAAA==.',
Ra='Radrin:BAAANQADCgcIEwAAAA==.Rafoff:BAAANQAECgYICQAAAA==.Ragnarax:BAABNQAECn8gAAIGAAoKAh8RIwCXAgAGAAoKAh8RIwCXAgAAAA==.Rahll:BAAANQADCgIIAgAAAA==.Raikami:BAAANQAECgQIBAAAAA==.Rancoramble:BAAANQAECgYICwAAAA==.Randis:BAABNQAECn8yAAIBAAgKkw2HLQBKAQABAAgKkw2HLQBKAQAAAA==.Raysonna:BAAANQAECgYIEgAAAA==.',
Re='Recapitator:BAAANQADCgIIAQAAAA==.Rengår:BAAANQAECgUIBAAAAA==.Reo:BAAANQAECgMIAwAAAA==.Reticent:BAAANQAECgYIBgAAAA==.Reversewally:BAAANQAECgcIEAAAAA==.Rexhà:BAAANQAECgMIBQAAAA==.Rexiis:BAABNQAECn8gAAILAAgK3w4OhwAZAQALAAgK3w4OhwAZAQAAAA==.Reyth:BAAANQAECgQICwAAAA==.',
Rh='Rhuby:BAABNQAECn8vAAICAAgKqxU0NgBDAQACAAgKqxU0NgBDAQAAAA==.',
Ri='Rimos:BAAANQAECggIDQAAAA==.Riptîde:BAAANQAECgYICQAAAA==.Rivening:BAAANQAECgQICAAAAA==.',
Rk='Rk:BAAANQADCgYICAAAAA==.',
Ro='Rochelle:BAAANQAECgEIAQAAAA==.Roeyth:BAAANQADCggICAAAAA==.Rokki:BAABNQAECn9BAAIPAAkKYgnd7ACxAQAPAAkKYgnd7ACxAQAAAA==.Roostor:BAAANQADCggIEQAAAA==.Rosael:BAAANQADCgQJBAAAAA==.Roundhouse:BAABNQAECn8eAAImAAgKpBrlDQAZAgAmAAgKpBrlDQAZAgAAAA==.',
Ru='Rubbmytotems:BAAANQAECgYIEAAAAA==.Rubicôn:BAAANQABCgYICAABNQAFFAcIHAAPAK0ZAA==.Rubmyoysters:BAAANQADCgEIAQAAAA==.Ruleti:BAABNQAECn8pAAIEAAoKsRg1PwCtAgAEAAoKsRg1PwCtAgAAAA==.Rumí:BAAANQADCggJIgAAAA==.Rundeep:BAAANQABCgYICgAAAA==.Russell:BAAANQADCgYIEgAAAA==.',
Sa='Sabado:BAAANQAECgMIAwAAAA==.Safewerd:BAEBNQAECn8UAAIJAAcKpAuxLQD+AAAJAAcKpAuxLQD+AAAAAA==.Saitama:BAAANQAECgYICQABNQAECgkJMgAGACoWAA==.Sangriel:BAABNQAECn8nAAICAAkKyA+rZwBUAQACAAkKyA+rZwBUAQAAAA==.Saraceleste:BAAANQAECgQIBAAAAA==.Sarafinmae:BAAANQAECgUIBwAAAA==.Sarahfi:BAAANQAECgIJAgABNQAECgcIFwAgABsXAA==.Saralanna:BAABNQAECn81AAILAAoKhQ1USADGAQALAAoKhQ1USADGAQAAAA==.Sarasophie:BAAANQADCgcIGAAAAA==.Sarefina:BAAANQAECgQICQAAAA==.Sathenazarke:BAABNQAECn8WAAIRAAoKXx6zCADsAgARAAoKXx6zCADsAgABNQAFFAcIFwAdAOAjAA==.',
Sc='Schism:BAAANQAECgMIBAAAAA==.Schmingus:BAAANQADCgIIAgAAAA==.Scoban:BAACNQAFFH8QAAITAAYKuBn1BwClAQATAAYKuBn1BwClAQA1AAQKfxoAAhMACQoRHng2AIoCABMACQoRHng2AIoCAAAA.',
Se='Seaworld:BAABNQAECn8dAAQfAAkKuhvcCAATAgAfAAcKlR7cCAATAgAQAAcKMRCLRgDXAAAgAAEKJhWXXgA2AAABNQAECgkJMQAeAHseAA==.Selènè:BAAANQAECgcIBwABNQAFFAQICAAOAOgaAA==.Seraphine:BAAANQABCgIIAgAAAA==.Seraphnite:BAAANQADCgIIAgAAAA==.Seriousjakk:BAAANQADCgEIAQABNQADCgQIBwAWAAAAAA==.',
Sh='Shadeebear:BAAANQADCgEIAQAAAA==.Shadowtax:BAAANQADCgYIBgAAAA==.Shan:BAAANQAECgcIEwAAAA==.Shaohlin:BAAANQAECgEIAQAAAA==.Shaqfu:BAAANQADCgYIEgAAAA==.Shavemybush:BAAANQADCgcJBwAAAA==.Shayy:BAABNQAECn89AAIFAAoKDhnnAwCeAgAFAAoKDhnnAwCeAgAAAA==.Sheve:BAAANQAECgQIDAABNQAECgkJLwAlADAiAA==.Shevee:BAAANQAECgMIBQABNQAECgkJLwAlADAiAA==.Shigure:BAABNQAECn8jAAMDAAoKpwqHFgBKAQAPAAoKrAgW0wDgAQADAAcKOQqHFgBKAQAAAA==.Sholin:BAABNQAECn8dAAImAAkKmyCgCACfAgAmAAkKmyCgCACfAgAAAA==.Shomea:BAAANQAECgUIDAAAAA==.Shugz:BAAANQADCgYIEQAAAA==.Shumai:BAAANQAECgYIDQAAAA==.',
Si='Sigons:BAAANQABCgYICAAAAA==.Sikotick:BAABNQAECn8fAAIKAAgKhBdRLQCxAQAKAAgKhBdRLQCxAQAAAA==.Sikxrapture:BAAANQADCgYIBgAAAA==.Siliconista:BAACNQAFFH8JAAIPAAQKORedHgDkAAAPAAQKORedHgDkAAA1AAQKf00AAw8ACgrbJEgVAH4DAA8ACgooJEgVAH4DAAMABwrgJKkLAAUCAAAA.Simbelmyne:BAAANQAECgUIBgABNQAECgoKJgAKAFwaAA==.',
Sk='Skitrit:BAAANQAECgEIAQABNQAECgoKKQAEALEYAA==.Skyjin:BAAANQADCgYJCQAAAA==.',
Sl='Slammurai:BAAANQADCgcICwAAAA==.Slew:BAAANQAECgQIAwAAAA==.Slippie:BAAANQADCgQIBAAAAA==.Slippinwater:BAABNQAECn8zAAIHAAoKaCSsHQBMAwAHAAoKaCSsHQBMAwAAAA==.Sllew:BAABNQAECn9KAAMBAAoKzRtOGQD1AgABAAkKax1OGQD1AgAXAAoKjBNRHwAcAgAAAA==.Slylent:BAAANQAECgIIAQAAAA==.Slyyce:BAAANQAECggIEAAAAA==.',
Sm='Smoulder:BAAANQAECgIIBAAAAA==.',
Sn='Snigles:BAABNQAECn8iAAIeAAoKbQlTKgBxAQAeAAoKbQlTKgBxAQAAAA==.Snowlily:BAAANQAECgQICgABNQAECgkJJQAUAOASAA==.Snurp:BAAANQAECgYIDAABNQAECgoKKAAYAJ4gAA==.',
So='Softnsquishy:BAAANQAECgEIAgAAAA==.Solmarrow:BAABNQAECn8YAAQDAAcKmggwGAA4AQADAAcKRggwGAA4AQAPAAQKaAQchAG8AAAnAAEKFAbKDQA0AAAAAA==.',
Sp='Spagoni:BAAANQADCggICAAAAA==.Spanksbar:BAAANQADCggIFAAAAA==.Spartos:BAABNQAECn8rAAMGAAcKPBt2VQDIAQAGAAcKPBt2VQDIAQAbAAIKUA/tLQBmAAAAAA==.Spazzlixx:BAAANQAECgUIBQAAAA==.Speedy:BAABNQAECn8iAAIEAAYKwwMDCQH1AAAEAAYKwwMDCQH1AAAAAA==.Speedyspeed:BAAANQADCgQIBQAAAA==.Spokes:BAAANQADCgYICQABNQAECggIAwAWAAAAAA==.Sposi:BAABNQAECn8gAAMCAAkKxiErGwDVAgACAAkKxiErGwDVAgAXAAIKzwz6ggBwAAAAAA==.Sprinkle:BAAANQAECggJCQABNQAECggIEQAWAAAAAA==.',
Sr='Srimrithyu:BAAANQADCgYIEwAAAA==.',
Ss='Sselionn:BAAANQAECgUIDgAAAA==.',
St='Stomps:BAABNQAECn8iAAIbAAgKyBccEAAnAgAbAAgKyBccEAAnAgAAAA==.Stoneweaver:BAAANQADCgYIBgABNQAECgcIIwAKAMsbAA==.Stonezef:BAABNQAECn8jAAIPAAkKkAzf+ACbAQAPAAkKkAzf+ACbAQAAAA==.',
Su='Suffocation:BAAANQADCgYIBwAAAA==.Sumasuka:BAAANQADCgcIDQAAAA==.Sumbtch:BAABNQAECn8fAAILAAcKJAOPxQCXAAALAAcKJAOPxQCXAAAAAA==.Sungdihhwoo:BAAANQADCgQIBwAAAA==.Susann:BAABNQAECn8jAAIlAAkK4xNyaQDQAQAlAAkK4xNyaQDQAQAAAA==.',
Sy='Syravia:BAAANQAECgYIEwAAAA==.',
['Sò']='Sòlushan:BAAANQAECgEIAQABNQAECgoKKAAHAKEbAA==.',
Ta='Tahoa:BAAANQABCgQIBwAAAA==.Talarin:BAAANQAECgIIBAAAAA==.Talayro:BAAANQADCgIIAgAAAA==.Tameka:BAABNQAECn83AAIEAAoKHhrFNQDKAgAEAAoKHhrFNQDKAgAAAA==.Tardis:BAAANQAECgcIBwABNQAECgoKJgAOAOcXAA==.Tatersdh:BAEANQAECgYIDAABNQAFFAcIGwACACgjAA==.Tavinrayn:BAAANQAECgYIDAAAAA==.',
Te='Tekesh:BAAANQAECggIDgAAAA==.Teksham:BAAANQADCgYIEgAAAA==.Telarin:BAABNQAECn8rAAMEAAgKHRhIaQCoAQAoAAcKdxPABwDtAQAEAAgKbBdIaQCoAQAAAA==.Tenebrefigo:BAAANQADCgcIBwABNQAECgoKPAAbACEmAA==.Teremup:BAAANQAECgIIAQAAAA==.Tezrian:BAAANQADCgYJCgABNQAECgkJMQAeAHseAA==.',
Th='Thebigdawg:BAAANQADCggICQAAAA==.Theladyboy:BAABNQAECn8pAAMZAAgKoBfkCgBzAQAZAAgKoBfkCgBzAQAhAAMKtgrieQCRAAAAAA==.Thomss:BAABNQAECn8uAAIEAAkKdBO5awA7AgAEAAkKdBO5awA7AgAAAA==.Thraiene:BAAANQAECgUIDwABNQAECgkJFQAMAMASAA==.Thrawn:BAAANQAECgMIAwAAAA==.Throhk:BAAANQADCgcIFQAAAA==.Thrumgar:BAAANQAECgEIAgAAAA==.',
Ti='Tiamut:BAAANQADCgQIBAAAAA==.Tigerliley:BAAANQAECgQIDAABNQAECgkJJQAUAOASAA==.Tinneas:BAAANQAECgEIAQAAAA==.',
To='Tomás:BAABNQAECn8bAAIaAAgKiAxVjACFAQAaAAgKiAxVjACFAQAAAA==.Topg:BAAANQADCggIEwAAAA==.Torstai:BAABNQAECn8ZAAINAAcKkwqwDwBTAQANAAcKkwqwDwBTAQAAAA==.Totemic:BAAANQADCggIEgAAAA==.Toyun:BAAANQADCgMIAwAAAA==.',
Tr='Trap:BAAANQADCgQIBAAAAA==.Trueshöt:BAABNQAECn8nAAMYAAgKDhXCIQAjAQAoAAYK7xCZCQCXAQAYAAgKpBHCIQAjAQAAAA==.',
Ts='Tserendolgor:BAAANQAECgYIDAABNQAECgkJMQAeAHseAA==.',
Tu='Tukker:BAAANQADCgYIBgABNQAECgoKPAAbACEmAA==.',
Ty='Tyedindis:BAAANQADCgEIAQAAAA==.Tyresious:BAABNQAECn8aAAIHAAkKqhVslwD1AQAHAAkKqhVslwD1AQAAAA==.',
Ut='Utherrex:BAAANQAECgMIBQABNQAECggIIAALAN8OAA==.',
Va='Vahaghn:BAABNQAECn8/AAIGAAoKUSMAEwBwAwAGAAoKUSMAEwBwAwAAAA==.Valcerus:BAAANQAECgUIDgAAAA==.Valedus:BAABNQAECn8vAAIHAAoK1SFJOQDrAgAHAAoK1SFJOQDrAgAAAA==.',
Ve='Veelete:BAAANQADCgcICwABNQAECggILAATADAjAA==.Vengeancedh:BAABNQAECn8XAAICAAgK9BvHHQDiAQACAAgK9BvHHQDiAQAAAA==.Veroya:BAAANQAECgEIAQAAAA==.Vespra:BAAANQADCgYIBgAAAA==.Veylara:BAAANQADCgIIAgAAAA==.',
Vi='Viix:BAAANQADCgUIBQAAAA==.Vinno:BAAANQAECgEIAgAAAA==.Virr:BAABNQAECn8XAAIgAAcKGxdhHwBOAQAgAAcKGxdhHwBOAQAAAA==.',
Vo='Volcker:BAABNQAECn8yAAIIAAgKwwiNKwDmAAAIAAgKwwiNKwDmAAAAAA==.Volthreal:BAAANQADCggICAABNQAECgoKPAAbACEmAA==.Voltuk:BAABNQAECn88AAQbAAoKISYZAQBYAwAbAAoKISYZAQBYAwAcAAMKiQrgJQCAAAAGAAEK2wkjDQE4AAAAAA==.',
Wa='Wadoralock:BAAANQAECgcICAABNQAFFAMICAAEAJgIAA==.Walrustusk:BAAANQAECgcIBwAAAA==.Wariius:BAAANQAECgIIAgAAAA==.Warwarb:BAAANQAECgcICwABNQAECgoKMgALAJEVAA==.Wasabijack:BAAANQADCgcJCgAAAA==.Waterliliy:BAABNQAECn8lAAQUAAkK4BKWKADkAQAUAAkK4BKWKADkAQAFAAIKPQuSIABdAAAOAAIKhAEz9wA/AAAAAA==.Wayhn:BAAANQADCgYIBgAAAA==.',
Wh='Whatcrap:BAAANQAECgIIAgAAAA==.Whathehay:BAAANQADCgQIBAAAAA==.',
Wi='Wickedmon:BAAANQADCgMIAwAAAA==.Windfurypie:BAAANQADCggICQAAAA==.',
Wo='Wolfbish:BAAANQAECgUICAAAAA==.Wongidan:BAAANQAECggIDgAAAA==.',
['Wý']='Wýler:BAAANQADCgIIAgABNQADCggICAAWAAAAAA==.',
Xa='Xacious:BAAANQAECgcIEwAAAA==.',
Xh='Xhuri:BAAANQADCgYIBgAAAA==.',
['Xë']='Xëna:BAABNQAECn8jAAMKAAcKyxvcIACjAQAKAAcKyxvcIACjAQAQAAIKSwSCpwBJAAAAAA==.',
Yo='Yorllik:BAAANQAECgUIDgAAAA==.',
Yt='Yt:BAABNQAECn8XAAIVAAgKGBJUIgBUAQAVAAgKGBJUIgBUAQAAAA==.',
Yu='Yueguanghua:BAAANQADCgUIBQAAAA==.Yuzuha:BAAANQADCgIIAgAAAA==.',
Ze='Zeddicus:BAAANQAECgQIBAAAAA==.Zendragon:BAABNQAECn8wAAMIAAoKmSMGBQD1AgAIAAoKmSMGBQD1AgAHAAcKWAq9AQEdAQABNQAECgoKPAAbACEmAA==.',
Zh='Zhorvan:BAAANQADCggIGQABNQAECggIGgAIAEQHAA==.',
Zi='Zilstar:BAAANQAECgUIBQAAAA==.',
Zo='Zoomy:BAAANQADCggICAAAAA==.',
Zu='Zuggondeez:BAAANQAECgUIBQABNQAECggIJQAEAGYVAA==.Zuggsalot:BAAANQAECgIIAQAAAA==.',
['Âr']='Ârtëmïs:BAABNQAECn8WAAIEAAcKIQfj4AA/AQAEAAcKIQfj4AA/AQAAAA==.',
['Åp']='Åpollo:BAACNQAFFH8MAAIJAAYK8hcWBACjAQAJAAYK8hcWBACjAQA1AAQKfx4AAgkACgqIG9wQAHECAAkACgqIG9wQAHECAAAA.',
['Ðe']='Ðeja:BAAANQAECgMIAwABNQAECgcIFwAgABsXAA==.',
['Òm']='Òmgitsbwòng:BAABNQAECn8bAAIYAAgKGgq0NACoAQAYAAgKGgq0NACoAQABNQAECggIDgAWAAAAAA==.',
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
