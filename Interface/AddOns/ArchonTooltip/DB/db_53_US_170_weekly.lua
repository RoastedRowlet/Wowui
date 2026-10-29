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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Druid-Balance','Priest-Holy','Priest-Shadow','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Destruction','Warrior-Fury','Rogue-Assassination','Hunter-BeastMastery','Paladin-Holy','Warrior-Arms','Mage-Arcane','Unknown-Unknown','Druid-Feral','Mage-Frost','Monk-Mistweaver','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian','DeathKnight-Frost','Monk-Brewmaster','Monk-Windwalker','Evoker-Devastation','Rogue-Subtlety','DemonHunter-Havoc','Warrior-Protection','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Absol:BAABNQAECn8uAAMBAAoKHCOkAACaAwABAAoKwCKkAACaAwACAAoKjB73PQCZAgAAAA==.',
Ac='Achilles:BAABNQAECn8vAAMDAAoKtRKRmADyAQADAAoK9A+RmADyAQAEAAUKrhFpJgDOAAAAAA==.',
Ad='Adenox:BAAANQAECgMIAwAAAA==.',
Ae='Aeon:BAAANQAECgIIBAAAAA==.Aerís:BAAANQADCgIIAgAAAA==.',
Ah='Ahsokatano:BAABNQAECn8oAAMFAAkKRRk9JAApAgAFAAkKRRk9JAApAgAGAAEKAACaPgEuAAAAAA==.',
Ai='Ailing:BAAANQADCgYIDAAAAA==.Aimspet:BAABNQAECn8jAAIFAAkKGRguGwBnAgAFAAkKGRguGwBnAgAAAA==.Airocket:BAAANQADCgMIAwAAAA==.',
Ak='Akasha:BAAANQABCgMIBwAAAA==.Akos:BAAANQAECgcIBgABNQAECgoKWAAHALQYAA==.',
Al='Alzaeryan:BAABNQAECn8ZAAIIAAgKtBdwQwDmAQAIAAgKtBdwQwDmAQAAAA==.',
Am='Am:BAAANQADCgYIBgAAAA==.Amonet:BAAANQADCggIHwAAAA==.',
An='Anamis:BAABNQAECn8kAAMJAAkK6RSXUwAoAgAJAAkK6RSXUwAoAgAKAAEKHwXcgQAoAAAAAA==.Angras:BAABNQAECn8YAAMLAAYKogsPiQDbAAALAAUKwwwPiQDbAAAMAAUK0ga8mwDHAAAAAA==.',
Ap='Aphalock:BAABNQAECn8rAAINAAoKZQfPBQAvAQANAAoKZQfPBQAvAQAAAA==.',
Ar='Aradial:BAAANQADCgEIAQAAAA==.Ariûs:BAABNQAECn8XAAIOAAYKuw0wFQBKAQAOAAYKuw0wFQBKAQAAAA==.Arlin:BAAANQADCggIFgAAAA==.Arlorian:BAABNQAECn83AAIPAAoKeQtbEACCAQAPAAoKeQtbEACCAQAAAA==.Arrenn:BAAANQAECgUIDgAAAA==.Arrowsmites:BAABNQAECn8jAAIQAAkKZhluLwAiAgAQAAkKZhluLwAiAgAAAA==.',
As='Askelad:BAABNQAECn8cAAIDAAcKHQdWBgEUAQADAAcKHQdWBgEUAQAAAA==.',
Au='Aubani:BAABNQAECn8rAAMRAAkKXRHJQwCGAQARAAkKXRHJQwCGAQADAAcKoRA+6gBHAQAAAA==.',
Ax='Axelot:BAAANQADCgQIBAAAAA==.',
Ay='Ayperos:BAABNQAECn83AAISAAkKzA0HUgCNAQASAAkKzA0HUgCNAQAAAA==.',
Ba='Bakedpally:BAABNQAECn8bAAIDAAcKhQdP9wAvAQADAAcKhQdP9wAvAQAAAA==.Bakedwarrior:BAAANQADCgIIAgAAAA==.Bandomar:BAAANQAECgIIAwAAAA==.Baniemo:BAAANQAECgQIBAAAAA==.Banigor:BAAANQAECgcICwAAAA==.Bankaltanon:BAAANQAECgUIBAAAAA==.Baragnis:BAAANQAECgUIBQAAAA==.',
Be='Beavur:BAABNQAECn8UAAITAAYKXQreKgFEAQATAAYKXQreKgFEAQAAAA==.Beck:BAABNQAECn8qAAIDAAgKziEWSQC5AgADAAgKziEWSQC5AgAAAA==.Beggars:BAAANQAECgQICgAAAA==.Bereth:BAAANQADCggIHwAAAA==.Berreydingle:BAAANQADCggJFwAAAA==.',
Bi='Bigboii:BAAANQAECgEIAQAAAA==.Bigkitty:BAAANQAECgIIAgABNQAECgoKIQATADsVAA==.Bikinibrenda:BAAANQAECgYIDQAAAA==.',
Bl='Blackhuuf:BAAANQADCgUIBQAAAA==.Blitzedbust:BAAANQADCggIFQAAAA==.Bloodmender:BAAANQADCgYIBwABNQAECgoKKwATAL0iAA==.Bluesummer:BAAANQAECggICwABNQAECggIIwALABseAA==.',
Bo='Bobeh:BAAANQAECgEIAgABNQADCgEIAQAUAAAAAA==.Bolts:BAAANQABCgEIAQAAAA==.Bonzai:BAAANQAECggIBwABNQAECgoKLgABABwjAA==.Boomskittles:BAAANQABCgMIAwAAAA==.Borat:BAABNQAECn8oAAITAAoKCCLOCQCxAwATAAoKCCLOCQCxAwAAAA==.Borsam:BAAANQABCgcICgAAAA==.',
Br='Brendameeks:BAAANQADCgQIBAAAAA==.Broadzinatl:BAAANQAECgIIAgABNQAECgQIAgAUAAAAAA==.Brom:BAAANQAECgQIBgAAAA==.Brutesse:BAAANQAECgQIDAAAAA==.Bròly:BAAANQADCgMIAwAAAA==.',
Bu='Buttercups:BAAANQAECgQIBAAAAA==.',
['Bè']='Bètflèch:BAAANQAECgIIAgAAAA==.',
['Bø']='Bøss:BAAANQADCggIFQAAAA==.',
Ca='Cad:BAAANQADCgYIEAAAAA==.Calytrix:BAEBNQAECn8rAAQIAAoKRRPxOgAcAgAIAAoKRRPxOgAcAgAHAAIKQBPFRQB2AAAVAAEKXxG4QAA5AAAAAA==.Captnhammer:BAAANQADCgEIAQAAAA==.Carnelian:BAAANQADCggIHAAAAA==.Castration:BAAANQADCgYICQAAAA==.',
Ce='Ceylan:BAABNQAECn8iAAIWAAkKBRtjCABcAgAWAAkKBRtjCABcAgAAAA==.',
Ch='Chaleb:BAAANQADCggICAAAAA==.Charlz:BAAANQAECggIDwAAAA==.Charsifood:BAAANQAECgcIDgAAAA==.Chat:BAABNQAECn8XAAIXAAgKaiYbAwCEAwAXAAgKaiYbAwCEAwAAAA==.Cheatpriest:BAABNQAECn8uAAIJAAoKCxPOPwC1AQAJAAoKCxPOPwC1AQAAAA==.Chepis:BAAANQADCgcJEAAAAA==.Chesthyr:BAAANQADCgcIDgAAAA==.Chestoe:BAAANQAECgYIEAAAAA==.Chitchatted:BAAANQADCgIIAgAAAA==.',
Ci='Cindrethresh:BAAANQADCgMIAwAAAA==.',
Co='Cognition:BAABNQAECn83AAIQAAkKHSKnHgAdAwAQAAkKHSKnHgAdAwAAAA==.Coldvengance:BAABNQAECn8gAAIOAAkKpgdtEwBpAQAOAAkKpgdtEwBpAQAAAA==.',
Cr='Cranknstein:BAAANQADCggJCAABNQADCggIEQAUAAAAAA==.Crazh:BAAANQAECgIIAwAAAA==.Crazycalla:BAAANQAECgUIBgAAAA==.Croven:BAAANQADCgUIBQAAAA==.',
Cu='Cuensour:BAAANQADCgcJDQAAAA==.Cutemenace:BAAANQADCgIIAgABNQAECgkJHAAEAJ0gAA==.',
Cy='Cymindel:BAABNQAECn8yAAILAAoKFBcYFQD9AQALAAoKFBcYFQD9AQAAAA==.Cyphr:BAAANQAECgQICAAAAA==.',
Da='Dakotà:BAABNQAECn8lAAIQAAcKThNVcwBPAQAQAAcKThNVcwBPAQAAAA==.Darc:BAAANQAECgcICgAAAA==.Daredayo:BAAANQADCgIIAgAAAA==.Darkangelz:BAAANQAECgUIBQAAAA==.Darklorising:BAAANQAECgIIAgAAAA==.Darktroll:BAAANQADCgYICAAAAA==.Darkwave:BAAANQAECgMIAgAAAA==.',
De='Dejno:BAABNQAECn8WAAMOAAcKlSD7CQAxAgAOAAYKxCL7CQAxAgASAAIK/BTGKAGFAAAAAA==.Deleted:BAAANQADCgUIBQABNQAECgoKKwATAL0iAA==.Dethra:BAAANQAECgQIEgAAAA==.Dezign:BAACNQAFFH8eAAMWAAcKOyEuAQB7AQATAAYKxx6kFADSAQAWAAQKpSMuAQB7AQA1AAQKf0wAAxYACgp8JlEAANwDABYACQoMJlEAANwDABMACgqUJXYEAEQDAAAA.',
Do='Dolgorukov:BAABNQAECn8oAAIQAAgK1w9gXQCGAQAQAAgK1w9gXQCGAQAAAA==.Dologony:BAAANQAECgcIEwAAAA==.Dorgar:BAAANQADCgcIBwAAAA==.',
Dr='Draccosa:BAAANQADCgIIAgAAAA==.Dragonmage:BAAANQAECgUICwAAAA==.Drakhan:BAAANQAECgUIBgAAAA==.Drakma:BAAANQAECgMIBQAAAA==.Drastio:BAAANQADCgMIAwAAAA==.Drikken:BAABNQAECn88AAMYAAoKjRmSCwAVAgAYAAoKjRmSCwAVAgAZAAgKJRDDGwBQAQAAAA==.Drmaker:BAAANQAECgMIBAAAAA==.Druj:BAEANQADCggIDAABNQAECgoKKwAIAEUTAA==.',
Du='Durasan:BAAANQADCgMIAwAAAA==.Duressa:BAAANQADCggICAAAAA==.',
['Dö']='Dötdötdead:BAAANQAECgcIDwAAAA==.',
Ef='Effindin:BAAANQADCgYIBgAAAA==.Effinsick:BAAANQAECgQIBAAAAA==.',
Ei='Eisheth:BAAANQAECgIIAwAAAA==.',
El='Elerav:BAAANQAECgQIBwAAAA==.Ellysiaa:BAAANQADCggIJwAAAA==.',
Em='Emmakyn:BAABNQAECn8dAAMIAAkKBQ9lQgDtAQAIAAkKdg5lQgDtAQAaAAEK3BamXAA8AAAAAA==.Emriss:BAABNQAECn8tAAIbAAkKVgmRSQCVAQAbAAkKVgmRSQCVAQAAAA==.',
En='Endjinns:BAAANQADCggICAAAAA==.Enyxea:BAAANQAECgMIBAAAAA==.',
Er='Erodin:BAAANQADCgYICwAAAA==.',
Es='Esman:BAAANQADCgMIAwAAAA==.',
Ey='Eyedontknow:BAABNQAECn8cAAIEAAYKzhx/HAAIAgAEAAYKzhx/HAAIAgAAAA==.',
Ez='Ezzka:BAABNQAECn81AAMMAAoKzSDLBwCvAgAMAAoKzSDLBwCvAgALAAIKxhsUqgB8AAAAAA==.',
Fa='Faceless:BAAANQAECgYIBQAAAA==.Failroots:BAAANQAECgIIAgAAAA==.False:BAAANQAECgUIBwAAAA==.Farnsworth:BAABNQAECn8WAAMCAAoKcBT/QgCeAQACAAoKpRL/QgCeAQANAAIKShVdEwB/AAAAAA==.Farzix:BAABNQAECn8UAAIGAAcK4AZguwAbAQAGAAcK4AZguwAbAQAAAA==.Fatherdrew:BAABNQAECn8cAAIJAAkK8iCiDwD2AgAJAAkK8iCiDwD2AgAAAA==.Façade:BAABNQAECn8hAAMbAAoKnxKNNwD4AQAbAAkKQBSNNwD4AQAMAAcKrw9TbQBeAQAAAA==.',
Fe='Fefifabrizio:BAAANQAECgEIAQAAAA==.Felix:BAAANQAECgQIEAAAAA==.Felraena:BAAANQADCgIIAgAAAA==.',
Fi='Finnagas:BAAANQAECgEJAQAAAA==.Finnw:BAAANQABCgcJCgAAAA==.Firelite:BAABNQAECn8eAAMGAAcKOQnwYwDhAAAGAAcKOQnwYwDhAAAFAAEKkwEyMgEeAAAAAA==.',
Fl='Flairadin:BAABNQAECn8lAAIRAAkKfxmsPQBuAgARAAkKfxmsPQBuAgAAAA==.Flee:BAAANQAECgcICwAAAA==.Fleromars:BAAANQAECgUIBQABNQAECgcICwAUAAAAAA==.Flexo:BAAANQAECgQIBQABNQAECgoKFgACAHAUAA==.',
Fo='Fookmii:BAAANQADCgUIBgAAAA==.',
Fr='Frogfist:BAAANQAECgMIAwAAAA==.Frowdawn:BAABNQAECn8kAAIPAAcKLgt2HwAHAQAPAAcKLgt2HwAHAQAAAA==.',
Ga='Gallea:BAAANQAECgIIAgAAAA==.Garbanzo:BAAANQAECgUICgAAAA==.Garythenpc:BAAANQADCggIHwAAAA==.',
Ge='Genericeric:BAAANQAECgUIBwAAAA==.Getsumei:BAEANQAECggIDQABNQAECgoKKwAIAEUTAA==.',
Gi='Gidgett:BAAANQADCgcIFAAAAA==.Gilas:BAAANQADCgcIBwAAAA==.',
Gl='Glacialkitty:BAABNQAECn8nAAIHAAkKLgd0JgApAQAHAAkKLgd0JgApAQAAAA==.Glizzygoblin:BAAANQADCgQIBAAAAA==.',
Go='Gobibug:BAAANQADCgIJAgAAAA==.Googoobler:BAAANQAECgEIAQAAAA==.Goudalovin:BAAANQADCgQIBAABNQAECgoKIQATADsVAA==.Goudanight:BAAANQADCgIIAgABNQAECgoKIQATADsVAA==.Goudatime:BAABNQAECn8cAAILAAYK3wz5SAC/AAALAAYK3wz5SAC/AAABNQAECgoKIQATADsVAA==.',
Gr='Greenknight:BAAANQADCggICQAAAA==.Greenmagus:BAAANQAECgEJAQAAAA==.Grenadon:BAAANQADCggIHgAAAA==.Greyni:BAAANQABCgEIAQAAAA==.',
Gu='Gutz:BAAANQADCgMIAwAAAA==.',
Ha='Hadorya:BAAANQADCgQIBAAAAA==.Hakibalboa:BAABNQAECn85AAIcAAkK4wtFCQBHAQAcAAkK4wtFCQBHAQAAAA==.Hakitua:BAAANQADCgYIBgAAAA==.Harick:BAAANQADCgQIBAAAAA==.Hazard:BAABNQAECn8lAAIOAAkKIQ2rDwCvAQAOAAkKIQ2rDwCvAQAAAA==.',
He='Heis:BAAANQADCggIFgAAAA==.Hellboii:BAAANQAECgcIDgAAAA==.Heyitsrat:BAABNQAECn8gAAIDAAkK7QeH6ABKAQADAAkK7QeH6ABKAQAAAA==.',
Ho='Hollowtips:BAAANQADCggIEgAAAA==.Holo:BAABNQAECn81AAMGAAoKoSMjGQAyAwAGAAkKxyMjGQAyAwAFAAoKPA4ldQCsAQAAAA==.Holyangus:BAAANQAECgYIDAAAAA==.Holyboga:BAAANQADCgIIAgAAAA==.Housemom:BAAANQAECggIEgAAAA==.',
Hu='Huntem:BAAANQADCgMIAgAAAA==.Huuginn:BAAANQADCggICgAAAA==.',
Ib='Ibbert:BAAANQADCggIIQAAAA==.',
Ic='Icculus:BAAANQAECgIIAwAAAA==.',
Il='Illadai:BAAANQADCggIEAAAAA==.',
Im='Imamunch:BAAANQADCgIIAgAAAA==.Imaresmashy:BAAANQADCgIIAgABNQAECgYICQAUAAAAAA==.Iminyou:BAABNQAECn8qAAIGAAoKjhI/OAB0AQAGAAoKjhI/OAB0AQAAAA==.',
Io='Iolz:BAAANQABCgQIBgABNQAECgoKLQASAMUXAA==.',
Ja='Jaenei:BAAANQAECgMIBAAAAA==.Janet:BAAANQAECgYIBgABNQAECgkJLgAJAIgkAA==.',
Je='Jeeb:BAABNQAECn8vAAITAAgKHA8aeQBRAQATAAgKHA8aeQBRAQAAAA==.',
Ji='Jinxta:BAABNQAECn8kAAINAAkKgRsGBQDQAgANAAkKgRsGBQDQAgAAAA==.',
Jo='Joansnow:BAABNQAECn8XAAIbAAkKFwjhNQBFAQAbAAkKFwjhNQBFAQAAAA==.Joeeo:BAABNQAECn86AAMJAAoKHR6cFQC4AgAJAAoKHR6cFQC4AgAKAAcKigjlPgA2AQAAAA==.',
Ju='July:BAAANQAECgMIBAAAAA==.Julytonidas:BAABNQAECn8kAAITAAoKsRTmWACiAQATAAoKsRTmWACiAQAAAA==.Jurac:BAAANQADCggIFQAAAA==.',
Ka='Kaimargonar:BAABNQAECn8aAAINAAYK+hBHIgBfAQANAAYK+hBHIgBfAQAAAA==.Kaitoi:BAABNQAECn8bAAIVAAYKdRr5DgA8AQAVAAYKdRr5DgA8AQAAAA==.Kamakizeg:BAABNQAECn8jAAIDAAcKTBBhnQAZAQADAAcKTBBhnQAZAQAAAA==.Kamayla:BAAANQADCgYIBgAAAA==.Kateria:BAAANQAECgcICgABNQAECgoKNQAMAM0gAA==.Katimalice:BAAANQADCgQJDQAAAA==.',
Ke='Keathry:BAAANQADCggIEwAAAA==.Keyzeus:BAAANQAECgIIAwAAAA==.',
Kh='Khas:BAAANQADCgYICQAAAA==.Khui:BAACNQAFFH8NAAIXAAUKeyQNBAClAQAXAAUKeyQNBAClAQA1AAQKfywAAxcACgpYI7IEAFoDABcACgpYI7IEAFoDAB0ABQqUHQk1AG0BAAAA.',
Ki='Killatu:BAAANQABCggIDQAAAA==.Killerdeath:BAAANQAECgQIAwAAAA==.',
Kn='Knìghtmàrè:BAACNQAFFH8NAAMMAAYKiQ8pBQDqAAAMAAUKJw4pBQDqAAALAAMKhRRxHwCPAAA1AAQKfywAAwwACgqzIxYUABgDAAwACgqzIxYUABgDAAsABwpzHuw0ADgCAAAA.',
Ko='Koltharaz:BAACNQAFFH8GAAIeAAIK4h8TCgDAAAAeAAIK4h8TCgDAAAA1AAQKfzEAAh4ACgrHG6cJANYCAB4ACgrHG6cJANYCAAAA.Korloff:BAAANQADCggIEwABNQAECgIIAwAUAAAAAQ==.Kozan:BAAANQAECgIIAwAAAQ==.',
Kr='Krazsz:BAAANQADCgQIBAAAAA==.Krazykraw:BAAANQAECgIIBAAAAA==.Krazylock:BAAANQAECgQICAAAAA==.Krokk:BAAANQABCgUIBQAAAA==.',
Ku='Kuiy:BAAANQADCgIIAgAAAA==.Kumah:BAAANQABCgEIAQAAAA==.Kungfuupanda:BAAANQAECgcIEwAAAA==.',
Ky='Kylar:BAAANQAECgQIBgAAAA==.',
La='Lateralus:BAABNQAECn8eAAIMAAgKsSIsMABvAgAMAAgKsSIsMABvAgAAAA==.Latt:BAAANQAECggIEAABNQAECggIHgAMALEiAA==.Lawluss:BAABNQAECn8aAAIQAAgKSBM5vgCHAQAQAAgKSBM5vgCHAQAAAA==.Layonface:BAAANQAECgQIDAAAAA==.',
Le='Legacyshot:BAAANQAECgYICQAAAQ==.Lelwani:BAAANQADCgEIAQAAAA==.',
Li='Lickthecrit:BAAANQAECgMIBQAAAA==.Lightguard:BAAANQADCggICgAAAA==.Lighthouse:BAABNQAECn8xAAMRAAoK+hfZSgA9AgARAAkK8xbZSgA9AgADAAcKXwqspAAMAQAAAA==.Lightload:BAAANQAECgQIDAAAAA==.Lileth:BAAANQAECgIIAwAAAA==.',
Lo='Lolhahabaha:BAAANQAECgYICgAAAA==.Lonê:BAAANQAECgIIAgAAAA==.Loopie:BAAANQAECgUIBgAAAA==.Lorax:BAAANQAECgYICAAAAA==.',
Lu='Luckÿ:BAAANQAECgEJAQAAAA==.Luminah:BAAANQABCgIIAQAAAA==.',
Ly='Lypally:BAABNQAECn8zAAIDAAoKFAZWggBMAQADAAoKFAZWggBMAQAAAA==.',
['Lï']='Lïllïth:BAABNQAECn8fAAIQAAgK6AZywQB/AQAQAAgK6AZywQB/AQAAAA==.Lïly:BAAANQAECgUIBwABNQAECgYICQAUAAAAAA==.',
['Ló']='Lóla:BAABNQAECn8rAAIZAAgKvB4dEwDRAgAZAAgKvB4dEwDRAgAAAA==.',
Ma='Madeah:BAACNQAFFH8eAAIPAAcKtBQEAQCfAQAPAAcKtBQEAQCfAQA1AAQKfx8AAw8ACQqeIz4BAEMDAA8ACQqeIz4BAEMDAB8ACApcCrMpAHcBAAAA.Madforge:BAABNQAECn82AAIFAAgKzxlIKQAJAgAFAAgKzxlIKQAJAgAAAA==.Magegrizz:BAAANQAECgYIDgAAAA==.Magnyson:BAAANQAECggICAAAAA==.Mahimahi:BAAANQADCgYICgAAAA==.Manahole:BAABNQAECn87AAITAAoKRiIfBwAmAwATAAoKRiIfBwAmAwAAAA==.Mariacuras:BAABNQAECn8iAAIRAAkKjxGFKQAIAgARAAkKjxGFKQAIAgAAAA==.Marijwana:BAAANQAECgcIEAAAAA==.Marynne:BAABNQAECn8tAAIHAAkKSgxIGwCNAQAHAAkKSgxIGwCNAQAAAA==.Massaker:BAAANQADCggICAAAAA==.Mazuko:BAABNQAECn8hAAIgAAkKaBb1LwAoAgAgAAkKaBb1LwAoAgAAAA==.',
Mc='Mctank:BAAANQADCggIDQAAAA==.',
Me='Mecandry:BAABNQAECn82AAIQAAgKihX9ZQBIAgAQAAgKihX9ZQBIAgAAAA==.Mecks:BAAANQADCggIHwAAAA==.Meepe:BAAANQADCgcIDQAAAA==.Melivant:BAABNQAECn8fAAQEAAcKVRMTMwBKAQAEAAYKVRMTMwBKAQADAAUK2gnbNAHLAAARAAIKrAf5xQA0AAAAAA==.Meranda:BAABNQAECn8hAAITAAoKOxWHqAAxAgATAAoKOxWHqAAxAgAAAA==.Merriklade:BAABNQAECn8pAAQOAAkKVA3FCwBAAQASAAcK7wWL1QBFAQAOAAgKSA7FCwBAAQAhAAEKpQfFNAApAAAAAA==.Merrikoid:BAABNQAECn8XAAMYAAcKqQ1BHQDrAAAYAAYKEg9BHQDrAAAZAAYKrwURMwCUAAAAAA==.Merrikwolf:BAAANQADCggIDgAAAA==.',
Mi='Mico:BAAANQAECgUIEAAAAA==.',
Mo='Morbidstyle:BAAANQAECgcICgABNQAECgoKMwAGAFMUAA==.Morgoth:BAABNQAECn8uAAICAAoKqRZsUwBbAgACAAoKqRZsUwBbAgAAAA==.Morthos:BAAANQADCgcICgAAAA==.Mosry:BAABNQAECn8xAAILAAgK/h8jHADNAgALAAgK/h8jHADNAgABNQABCgQIBwAUAAAAAA==.Mourneblood:BAAANQADCgUIBQAAAA==.',
My='Myora:BAEANQADCgIIAgABNQAECgoKKwAIAEUTAA==.Mythundirus:BAABNQAECn8aAAIZAAkKggK0NACIAAAZAAkKggK0NACIAAAAAA==.',
['Mà']='Màrli:BAABNQAECn8tAAILAAgK/hhXPAASAgALAAgK/hhXPAASAgAAAA==.',
['Mâ']='Mâgs:BAABNQAECn8mAAIEAAkKJA34GAA3AQAEAAkKJA34GAA3AQAAAA==.',
Na='Nakasid:BAABNQAECn83AAMJAAoKshnCEADoAgAJAAoKshnCEADoAgAKAAUKBgcBUADSAAAAAA==.Nashoba:BAAANQADCgYJCwAAAA==.Natooka:BAAANQADCgUIBQAAAA==.',
Ne='Nein:BAAANQAECgQIDAAAAA==.Neins:BAAANQADCgYIEAABNQAECgQIDAAUAAAAAA==.Nevaehstar:BAABNQAECn87AAITAAoK3Q6qSwDNAQATAAoK3Q6qSwDNAQAAAA==.',
Ni='Nibuto:BAAANQAECgYIDgAAAA==.Nijun:BAEBNQAECn8tAAIJAAkKxw++OADVAQAJAAkKxw++OADVAQAAAA==.Nik:BAAANQAECgYIEAAAAA==.Nikolia:BAABNQAECn8ZAAQhAAcKtggfKgDpAAAhAAUK7AwfKgDpAAAOAAQKegRwKwBYAAASAAQK8QH+6gBCAAAAAA==.Ninetynine:BAAANQADCgQIBAAAAA==.Nini:BAABNQAECn8VAAIIAAcKEALaWgBkAAAIAAcKEALaWgBkAAAAAA==.Ninx:BAAANQADCgUICQAAAA==.',
No='Noivana:BAAANQABCgEIAQABNQAFFAYIEQAgAK0YAA==.',
Ny='Nystel:BAAANQADCgEIAQAAAA==.',
Ol='Ollichi:BAAANQADCgIIAgAAAA==.',
Or='Ornn:BAAANQAECgcICwABNQAECgoKLgABABwjAA==.',
Os='Osoroshi:BAAANQADCgYJBgABNQAECggINgAQAIoVAA==.',
Ov='Overtime:BAAANQADCggIEQAAAA==.',
Pa='Padmê:BAAANQADCgMIAwAAAA==.Paladrak:BAAANQADCgIIAgAAAA==.Pandamared:BAAANQADCggIEQAAAA==.Patronous:BAAANQADCgYIDAAAAA==.',
Ph='Phenol:BAAANQADCgEIAQAAAA==.',
Po='Polog:BAAANQAECgIIAgABNQAECgoKKwATAL0iAA==.Porkchoplust:BAAANQADCgUIBQAAAA==.Porkribs:BAABNQAECn8bAAIRAAgKkRqKRQBQAgARAAgKkRqKRQBQAgAAAA==.',
Pr='Pranks:BAAANQAECgQIBgAAAA==.Premalone:BAAANQADCgUICQAAAA==.',
Pu='Puca:BAAANQADCggIHwAAAA==.Pumdmuc:BAABNQAECn8ZAAIJAAcKfCF5HwBlAgAJAAcKfCF5HwBlAgABNQAECgoKMQAFAJgcAA==.Punchymcheal:BAAANQAECgMIBgABNQAECgoKOQAJAPMaAA==.',
Qu='Quikglaives:BAAANQAECgEIAQAAAA==.Quille:BAABNQAECn8nAAIQAAoKiB6rOAD+AQAQAAoKiB6rOAD+AQAAAA==.',
Ra='Ragretts:BAAANQAECgEIAQAAAA==.Rahhem:BAAANQADCgYIBgAAAA==.Ranmo:BAAANQAECggIEQAAAA==.Ratkol:BAAANQABCgIIAgAAAA==.Raysdknight:BAAANQADCgIJBwAAAA==.',
Re='Recbra:BAAANQAECgYIBgAAAA==.Redrek:BAAANQADCgcIKQAAAA==.Redshunter:BAAANQADCgcIGQAAAA==.Redsmonk:BAAANQADCgYIBgAAAA==.Redwinter:BAABNQAECn8jAAMLAAgKGx6NLABlAgALAAgKGx6NLABlAgAbAAEKAACOnQAAAAAAAA==.Reikisong:BAAANQAECgMIBAAAAA==.Reiluune:BAAANQADCgQIAwABNQAECggIKwAZALweAA==.Remmie:BAAANQADCgUIBwAAAA==.',
Rh='Rhagurion:BAABNQAECn86AAIaAAoKdSa6AADtAwAaAAoKdSa6AADtAwAAAA==.',
Ri='Riqua:BAAANQAECgMIBQAAAA==.',
Ro='Rockmonsta:BAAANQADCgYJCgAAAA==.Rockys:BAAANQABCgQIBQAAAA==.Roxies:BAAANQAECgMIBgAAAA==.',
Rp='Rpg:BAABNQAECn8cAAITAAkKlRkjmQBOAgATAAkKlRkjmQBOAgAAAA==.',
Ru='Rumie:BAAANQADCgUIBQAAAA==.Runes:BAAANQAECgcICwAAAA==.',
Sa='Saeti:BAABNQAECn9DAAUVAAoKYyRuBQAnAwAVAAkKYyRuBQAnAwAIAAUK1x5FNAD9AAAHAAQK4AyeTwDLAAAaAAEKxB+XUwBWAAAAAA==.Sanare:BAAANQADCggICAABNQAECgoKOQAJAPMaAA==.Sanbit:BAAANQAECgEIAQAAAA==.Santhaenis:BAAANQAECgIIAgAAAA==.Sapplesauce:BAAANQADCggICQAAAA==.',
Se='Seethrowwar:BAABNQAECn8iAAMSAAkKuh6vOwDYAgASAAkKaB6vOwDYAgAhAAYKQRbiGwB9AQAAAA==.Senbit:BAAANQAECgUIDQAAAA==.Serenìty:BAAANQAECgYIDAAAAA==.Seresin:BAABNQAECn9YAAMHAAoKtBhfFQCbAgAHAAoKtBhfFQCbAgAIAAUKkwVbggDHAAAAAA==.',
Sh='Shadý:BAABNQAECn8gAAIQAAkKgAUHsQDMAAAQAAkKgAUHsQDMAAAAAA==.Shamanoodles:BAAANQADCggIFAABNQAECgoKKwATAL0iAA==.Shortwarrior:BAABNQAECn8fAAIOAAcKQBKnDQAbAQAOAAcKQBKnDQAbAQAAAA==.',
Si='Sianu:BAAANQAECgUIBwABNQAECgkJLQAHAEoMAA==.Sidraya:BAAANQAECgUIDwAAAA==.Silent:BAABNQAECn8tAAISAAoKxReraQBTAgASAAoKxReraQBTAgAAAA==.Silverserqet:BAABNQAECn8cAAIQAAYKZwvQygBrAQAQAAYKZwvQygBrAQAAAA==.',
Sl='Slipknaught:BAAANQABCgQIBQABNQAECgkJFwAbABcIAA==.',
Sm='Smileyriley:BAAANQADCgUIBQAAAA==.',
Sn='Sneakylinks:BAAANQADCgIIAgABNQAECgkJHAATAJUZAA==.',
So='Sonbit:BAAANQADCggJDwAAAA==.Sooki:BAAANQAECgMIBQAAAA==.Sophie:BAAANQAECgQIDgAAAA==.Soulber:BAAANQAECgMIBAAAAA==.',
Sp='Spunky:BAAANQAECgQIBAAAAA==.',
Ss='Ssenbit:BAAANQADCggIKwAAAA==.Ssonbit:BAAANQADCggIEAAAAA==.',
St='Stefeana:BAAANQADCgYIBgAAAA==.Sternhoof:BAAANQABCgMIBQAAAA==.Stigma:BAAANQADCggIFQABNQAECgkJHAAJAPIgAA==.Stylos:BAABNQAECn8qAAIiAAkKBBBKDQC+AQAiAAkKBBBKDQC+AQAAAA==.',
Su='Summersong:BAAANQADCgQIBAAAAA==.Sumofwhy:BAAANQADCgcIBwAAAA==.',
Sw='Swarli:BAAANQAECgIIAgAAAA==.Swowtitbang:BAAANQAECgQICgAAAA==.',
Sy='Sylven:BAAANQAECgQIBQABNQAECgoKMgAGABUfAA==.',
Te='Techno:BAAANQAECgIIAgAAAA==.Tegbolt:BAABNQAECn8dAAMGAAgKeRXAZgDsAQAGAAgKghPAZgDsAQAiAAcKLhLWGwCmAQAAAA==.Teghorn:BAAANQAECggICAABNQAECggIHQAGAHkVAA==.Tekko:BAABNQAECn85AAMaAAoKMhq9CgATAgAaAAkKMR29CgATAgAVAAEKOQX8UAAQAAAAAA==.Tempestrike:BAABNQAECn8nAAIZAAoKVhqRDwD3AgAZAAoKVhqRDwD3AgAAAA==.',
Th='Theholymatt:BAABNQAECn82AAMRAAoKTiREEgA9AwARAAoKTiREEgA9AwADAAUKQg9UsgD0AAAAAA==.Thendari:BAABNQAECn9IAAINAAkKBwy1BABSAQANAAkKBwy1BABSAQAAAA==.Theodus:BAABNQAECn8oAAITAAoK+RG2twAUAgATAAoK+RG2twAUAgAAAA==.Therayen:BAAANQADCgYJCwAAAA==.Thomeriddle:BAAANQABCgMIAQAAAA==.',
Ti='Tiferis:BAACNQAFFH8HAAIRAAQKMRRpDgDhAAARAAQKMRRpDgDhAAA1AAQKfzYAAhEACgrgH5MHAFEDABEACgrgH5MHAFEDAAAA.Tigerclawss:BAAANQADCggIJQAAAA==.Tislam:BAAANQAECgMIBAAAAA==.',
To='Tobiquer:BAABNQAECn84AAIJAAkKpCH/GQAMAwAJAAkKpCH/GQAMAwAAAA==.Torolf:BAAANQAECgMIBQAAAA==.',
Tq='Tqco:BAAANQADCgMIAwABNQAECgoKOQAaADIaAA==.',
Tr='Traydra:BAAANQADCgUIBwAAAA==.Trinbug:BAAANQADCgEIAQAAAA==.Troglodyte:BAABNQAECn9FAAIGAAoKviKbCQCaAwAGAAoKviKbCQCaAwAAAA==.',
Ts='Tsonokwabain:BAABNQAECn8dAAIbAAkKbBzpKgBFAgAbAAkKbBzpKgBFAgAAAA==.Tsunami:BAAANQADCgMIAwAAAA==.',
Tw='Twistdog:BAAANQABCgQIBgAAAA==.',
Ty='Tye:BAABNQAECn8eAAIQAAoKKhcfMwATAgAQAAoKKhcfMwATAgAAAA==.Tyranastrasz:BAABNQAECn8pAAQeAAoKEQZVHgBtAQAeAAgK1QVVHgBtAQAjAAYK/ANbIQCSAAAkAAEKTQCNKQANAAAAAA==.Tyye:BAABNQAECn8lAAIOAAcKiCJKBAA3AgAOAAcKiCJKBAA3AgAAAA==.',
['Tâ']='Tâjik:BAABNQAECn8jAAIfAAoKtATKKQB2AQAfAAoKtATKKQB2AQAAAA==.',
Ul='Ulquiorra:BAACNQAFFH8KAAMZAAQKog5sDQDUAAAZAAMKog5sDQDUAAAYAAIKQAiPBwBCAAA1AAQKfzMAAxkACgqwHw0QAPICABkACQqwHw0QAPICABgABAoIDe8gAL0AAAAA.',
Ut='Uthers:BAAANQADCgYIAgAAAA==.',
Va='Vaethund:BAAANQAECgMIBAAAAA==.Valdred:BAAANQAECgcIBgABNQAFFAYIEQAgAK0YAA==.Valgavoth:BAABNQAECn8VAAILAAkK4Bf/NwApAgALAAkK4Bf/NwApAgAAAA==.Vangar:BAAANQADCgQIBAAAAA==.Vanthion:BAAANQADCggICgAAAA==.',
Ve='Velara:BAAANQAECgQIBQAAAA==.Velinna:BAAANQADCgUIBwABNQAECgEIAQAUAAAAAA==.Venekor:BAAANQADCgIIAgAAAA==.',
Vi='Viriex:BAAANQADCgIIAgAAAA==.Vitoria:BAAANQAECgQIBgAAAA==.',
Vo='Voidlighter:BAABNQAECn85AAIJAAoK8xo1JADcAgAJAAoK8xo1JADcAgAAAA==.Volundr:BAABNQAECn8kAAIhAAkKcRgeDgBNAgAhAAkKcRgeDgBNAgAAAA==.Vonvaughan:BAAANQAECgQIAgAAAA==.',
Vy='Vynel:BAAANQADCgMIAwABNQAECgoKMgAGABUfAA==.Vynirion:BAAANQAECgEIAQAAAA==.',
Wa='Wardellmo:BAAANQADCgQIBAAAAA==.Wargtar:BAABNQAECn8bAAIPAAcKCBnbMwAMAgAPAAcKCBnbMwAMAgAAAA==.',
We='Weabe:BAAANQAECgIIAwAAAA==.',
Wh='Whiterrina:BAAANQADCgIJAgAAAA==.Whitespring:BAAANQAECgYIDQABNQAECggIIwALABseAA==.',
Wo='Wolfgarou:BAAANQABCgIIAgAAAA==.',
Wy='Wyrdo:BAAANQADCgYIBgAAAA==.',
['Wù']='Wùsthof:BAABNQAECn8fAAIQAAkKYApKiQD4AQAQAAkKYApKiQD4AQAAAA==.',
Xa='Xandrios:BAAANQAECgEJAQAAAA==.',
Xi='Xiae:BAABNQAECn8lAAMGAAkKhRbzTABDAgAGAAgK6RbzTABDAgAFAAEKNRlYuwBFAAAAAA==.',
Ya='Yasuke:BAAANQADCgUJBQAAAA==.',
Ye='Yet:BAAANQAECgEIAQABNQAECgoKKAATAAgiAA==.',
Yi='Yiffweaver:BAAANQAECgEIAQAAAA==.',
Yo='Yokochan:BAAANQABCgIIAgAAAA==.Yokoriazen:BAABNQAECn8zAAIDAAoKIBUMYQB2AgADAAoKIBUMYQB2AgAAAA==.',
Za='Zakaradin:BAAANQADCgcICAABNQAECgIIAwAUAAAAAA==.Zandigor:BAAANQAECgIIAQAAAA==.Zaraeliana:BAAANQAECgMIBAAAAA==.Zarastraza:BAABNQAECn8hAAMjAAcKtRJxIgC3AQAjAAcKtRJxIgC3AQAeAAUKFQt0JQAPAQAAAA==.',
Ze='Zephnor:BAABNQAECn8fAAMaAAgKhw9lJABzAQAaAAYKxBJlJABzAQAIAAgKxQnTYgBDAQAAAA==.',
Zh='Zhao:BAAANQADCgYIBgAAAA==.',
Zm='Zmona:BAAANQAECgQIBAAAAA==.',
Zo='Zorsche:BAAANQAECgEIAQAAAA==.',
Zu='Zulrok:BAABNQAECn8qAAISAAkK1BBRSACuAQASAAkK1BBRSACuAQAAAA==.',
['Áb']='Ábsurd:BAAANQAECgYICAABNQABCgIIAQAUAAAAAA==.',
['Ðr']='Ðre:BAAANQAECgMIAwAAAA==.',
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
