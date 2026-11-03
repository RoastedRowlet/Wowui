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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Druid-Balance','Priest-Holy','Priest-Shadow','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Destruction','Warrior-Fury','Rogue-Assassination','Hunter-BeastMastery','Paladin-Holy','Warrior-Arms','Mage-Arcane','Unknown-Unknown','Druid-Feral','Mage-Frost','Monk-Mistweaver','Mage-Fire','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian','DeathKnight-Frost','Monk-Brewmaster','Monk-Windwalker','Evoker-Devastation','Shaman-Enhancement','Rogue-Subtlety','DemonHunter-Havoc','Warrior-Protection','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Absol:BAABNQAECn8uAAMBAAoKHCOkAACaAwABAAoKwCKkAACaAwACAAoKjB73PQCZAgAAAA==.',
Ac='Achilles:BAABNQAECn8zAAMDAAoK8xKRmADyAQADAAoK9A+RmADyAQAEAAUKVBN2LQDaAAAAAA==.',
Ad='Adenox:BAAANQAECgMIAwAAAA==.',
Ae='Aeon:BAAANQAECgQICAAAAA==.Aerís:BAAANQADCgIIAgAAAA==.',
Ah='Ahsokatano:BAABNQAECn8pAAMFAAkKRRmoJgBiAgAFAAkKRRmoJgBiAgAGAAEKAACaPgEuAAAAAA==.',
Ai='Ailing:BAAANQADCgYIDAAAAA==.Aimspet:BAABNQAECn8rAAIFAAkKYxmHJQBpAgAFAAkKYxmHJQBpAgAAAA==.Airocket:BAAANQADCgMIAwAAAA==.',
Ak='Akasha:BAAANQABCgMIBwAAAA==.Akos:BAAANQAECgcIBgABNQAECgoKZQAHAIkZAA==.',
Al='Alukai:BAAANQAECgQIBAAAAA==.Alzaeryan:BAABNQAECn8aAAIIAAgKtBdwQwDmAQAIAAgKtBdwQwDmAQAAAA==.',
Am='Am:BAAANQADCgYIBgAAAA==.Amonet:BAAANQAECgEIAQAAAA==.',
An='Anamis:BAABNQAECn8oAAMJAAoKOhSXUwAoAgAJAAoKOhSXUwAoAgAKAAEKHwXcgQAoAAAAAA==.Angras:BAABNQAECn8dAAMLAAYKogsPiQDbAAALAAUKwwwPiQDbAAAMAAUK0gZOWACCAAAAAA==.',
Ap='Aphalock:BAABNQAECn8xAAINAAoKgAiqBgBBAQANAAoKgAiqBgBBAQAAAA==.',
Ar='Aradial:BAAANQADCgEIAQAAAA==.Arane:BAAANQADCgcIBwAAAA==.Ariûs:BAABNQAECn8XAAIOAAYKuw0wFQBKAQAOAAYKuw0wFQBKAQAAAA==.Arlin:BAAANQAECgEIAQAAAA==.Arlorian:BAABNQAECn8+AAIPAAoK9A1qDgC8AQAPAAoK9A1qDgC8AQAAAA==.Arrenn:BAAANQAECgcIDgAAAA==.Arrowsmites:BAABNQAECn8lAAIQAAkKRhsTRAARAgAQAAkKRhsTRAARAgAAAA==.',
As='Askelad:BAABNQAECn8gAAIDAAcKYgdWBgEUAQADAAcKYgdWBgEUAQAAAA==.',
Au='Aubani:BAABNQAECn8vAAMRAAkKYBVpPwDkAQARAAkKYBVpPwDkAQADAAcKoRA+6gBHAQAAAA==.',
Ax='Axelot:BAAANQAECgcICwAAAA==.',
Ay='Ayperos:BAABNQAECn8/AAISAAkKmQ9hWwC1AQASAAkKmQ9hWwC1AQAAAA==.',
Ba='Bakedpally:BAABNQAECn8hAAIDAAcKhQdP9wAvAQADAAcKhQdP9wAvAQAAAA==.Bakedwarrior:BAAANQADCgIIAgAAAA==.Bandomar:BAAANQAECgIIAwAAAA==.Baniemo:BAAANQAECgQIBAAAAA==.Banigor:BAAANQAECgUIDAAAAA==.Bankaltanon:BAAANQAECgUICQAAAA==.Baragnis:BAAANQAECgUIBQAAAA==.',
Be='Beavur:BAABNQAECn8UAAITAAYKXQreKgFEAQATAAYKXQreKgFEAQAAAA==.Beck:BAABNQAECn8wAAIDAAgKziHgMQBvAgADAAgKziHgMQBvAgAAAA==.Beggars:BAAANQAECgQIDAAAAA==.Bereth:BAAANQAECgEIAQAAAA==.Berreydingle:BAAANQADCggJFwAAAA==.',
Bi='Bigboii:BAAANQAECgEIAQAAAA==.Bigkitty:BAAANQAECgIIAgABNQAECgoKIQATADsVAA==.Bikinibrenda:BAAANQAECgUIDgAAAA==.',
Bl='Blackhuuf:BAAANQADCgUIBQAAAA==.Blitzedbust:BAAANQADCggIFQAAAA==.Bloodmender:BAAANQADCgYIBwABNQAECgoKKwATAL0iAA==.Bluesummer:BAAANQAECgYIDAABNQAECgkJJwALAFQgAA==.',
Bo='Bobeh:BAAANQAECgEIAgABNQADCgEIAQAUAAAAAA==.Bonzai:BAAANQAECggICAABNQAECgoKLgABABwjAA==.Boomskittles:BAAANQABCgMIAwAAAA==.Borat:BAABNQAECn8uAAITAAoKJiPOCQCxAwATAAoKJiPOCQCxAwAAAA==.Borsam:BAAANQABCgcICQAAAA==.',
Br='Brendameeks:BAAANQADCgQIBAAAAA==.Broadzinatl:BAAANQAECgIIAgABNQAECgQIAgAUAAAAAA==.Brom:BAAANQAECgQIBgAAAA==.Brutesse:BAAANQAECgQIDAAAAA==.Bròly:BAAANQADCgMIAwAAAA==.',
Bu='Buttercups:BAAANQAECgQIBAAAAA==.',
['Bè']='Bètflèch:BAAANQAECgMIBAAAAA==.',
['Bø']='Bøss:BAAANQADCggIGQAAAA==.',
Ca='Cad:BAAANQADCgYIEAAAAA==.Calytrix:BAEBNQAECn8tAAQIAAoKRRPxOgAcAgAIAAoKRRPxOgAcAgAHAAIKQBMBVQBrAAAVAAEKXxG4QAA5AAABNQAECgoKGQAEAA8SAA==.Captnhammer:BAAANQADCgEIAQAAAA==.Carnelian:BAAANQAECgEIAQAAAA==.Castration:BAAANQADCgYICQAAAA==.',
Ce='Ceylan:BAABNQAECn8mAAIWAAkKqxxjCABcAgAWAAkKqxxjCABcAgAAAA==.',
Ch='Chaleb:BAAANQAECgEIAQAAAA==.Charlz:BAABNQAECn8eAAMJAAoKzBZBLABhAgAJAAkKARdBLABhAgAKAAUKUA5KNgCsAAAAAA==.Charsifood:BAAANQAECgcIDgAAAA==.Chat:BAABNQAECn8XAAIXAAgKaiYbAwCEAwAXAAgKaiYbAwCEAwABNQAECgkJrQAXAPMmAA==.Cheatpriest:BAABNQAECn82AAIJAAoKCxMrVgCpAQAJAAoKCxMrVgCpAQAAAA==.Cheatwl:BAAANQADCgIIAgAAAA==.Chepis:BAAANQADCgcJEAAAAA==.Chesthyr:BAAANQADCgcIDgAAAA==.Chestoe:BAAANQAECgUIEAAAAA==.Chitchatted:BAAANQADCgIIAgAAAA==.',
Ci='Cindrethresh:BAAANQADCgMIAwAAAA==.',
Co='Cognition:BAABNQAECn9AAAIQAAoK3COgDQAIAwAQAAoK3COgDQAIAwAAAA==.Coldvengance:BAABNQAECn8jAAIOAAoKoAhtEwBpAQAOAAoKoAhtEwBpAQAAAA==.Cortisol:BAAANQAECggIBgAAAA==.',
Cr='Cranknstein:BAAANQADCggJCAABNQADCggIEQAUAAAAAA==.Crazh:BAAANQAECgIIAwAAAA==.Crazycalla:BAAANQAECgQIBwAAAA==.Croven:BAAANQADCgUIBQAAAA==.Crànk:BAAANQAECgcIAQABNQADCggIEQAUAAAAAA==.',
Cu='Cuensour:BAAANQADCgcJDQAAAA==.Cutemenace:BAAANQADCgIIAgABNQAECgkJHAAEAJ0gAA==.',
Cy='Cymindel:BAABNQAECn87AAILAAoKiBc7FwAkAgALAAoKiBc7FwAkAgAAAA==.Cyphr:BAAANQAECgYICgAAAA==.',
Da='Dakotà:BAABNQAECn8rAAIQAAgKURbHZQCxAQAQAAgKURbHZQCxAQAAAA==.Darc:BAAANQAECgcICgAAAA==.Daredayo:BAAANQADCgIIAgAAAA==.Darkangelz:BAAANQAECgUIBQAAAA==.Darklorising:BAAANQAECgIIAgAAAA==.Darktroll:BAAANQAECgUIBQAAAA==.Darkwave:BAAANQAECggIAgAAAA==.',
De='Dejno:BAABNQAECn8WAAMOAAcKlSD7CQAxAgAOAAYKxCL7CQAxAgASAAIK/BTGKAGFAAAAAA==.Deleted:BAAANQADCgUIBQABNQAECgoKKwATAL0iAA==.Demonred:BAAANQADCgQIBAAAAA==.Dethra:BAAANQAECgQIEwAAAA==.Dezign:BAACNQAFFH8eAAMWAAcKOyEuAQB7AQATAAYKxx6kFADSAQAWAAQKpSMuAQB7AQA1AAQKf1YABBYACgp8JlEAANwDABYACQoMJlEAANwDABMACgqbJYkHADoDABgAAwoSIDgFALwAAAAA.',
Do='Dolgorukov:BAABNQAECn8uAAIQAAoKLQ9jTgDzAQAQAAoKLQ9jTgDzAQAAAA==.Dologony:BAAANQAECgcIEwAAAA==.Dorgar:BAAANQADCgcIDQAAAA==.',
Dr='Draccosa:BAAANQADCgIIAgAAAA==.Dracigor:BAAANQAECgQIBAAAAA==.Dragonmage:BAAANQAECgYICwAAAA==.Drakhan:BAAANQAECgUIBgAAAA==.Drakma:BAAANQAECgMIBQAAAA==.Drastio:BAAANQADCgMIAwAAAA==.Drikken:BAABNQAECn9HAAMZAAoKjRmSCwAVAgAZAAoKjRmSCwAVAgAaAAoKLxBNFgDVAQAAAA==.Drmaker:BAAANQAECgUIBQAAAA==.Druj:BAEANQADCggIDAABNQAECgoKGQAEAA8SAA==.',
Du='Durasan:BAAANQADCgMIAwAAAA==.Duressa:BAAANQADCggIDwAAAA==.',
['Dö']='Dötdötdead:BAAANQAECgcIEwAAAA==.',
Ef='Effindin:BAAANQADCgYIBgAAAA==.Effinsick:BAAANQAECgQIBAAAAA==.',
Ei='Eins:BAAANQADCggICAABNQAECgQIDAAUAAAAAA==.Eisheth:BAAANQAECgIIAwAAAA==.',
El='Elerav:BAAANQAECgQIBwAAAA==.Ellysiaa:BAAANQADCggIJwAAAA==.',
Em='Emmakyn:BAABNQAECn8hAAMIAAoKSxBlQgDtAQAIAAoKSxBlQgDtAQAbAAEK3BamXAA8AAAAAA==.Emriss:BAABNQAECn8xAAIcAAkKrAmRSQCVAQAcAAkKrAmRSQCVAQAAAA==.',
En='Endjinns:BAAANQADCggICAAAAA==.Enyxea:BAAANQAECgMIBAAAAA==.',
Er='Erodin:BAAANQADCgYICwAAAA==.',
Es='Esman:BAAANQADCgMIAwAAAA==.',
Ey='Eyedontknow:BAABNQAECn8jAAIEAAgKyhu/FQCaAQAEAAgKyhu/FQCaAQAAAA==.',
Ez='Ezzka:BAABNQAECn89AAMMAAoKQCH/CQC1AgAMAAoKQCH/CQC1AgALAAIKxhsUqgB8AAAAAA==.',
Fa='Faceless:BAAANQAECgYIBQAAAA==.Failroots:BAAANQAECgIIAgAAAA==.False:BAAANQAECgUIDAAAAA==.Farnsworth:BAABNQAECn8fAAMCAAoKpxR5SQDCAQACAAoKfRN5SQDCAQANAAIK0hUSGACBAAAAAA==.Farzix:BAABNQAECn8UAAIGAAcK4AZguwAbAQAGAAcK4AZguwAbAQAAAA==.Fatherdrew:BAABNQAECn8lAAMJAAoK4iA9DgBEAwAJAAoK4iA9DgBEAwAKAAEKkwdMWgArAAAAAA==.Façade:BAABNQAECn8hAAMcAAoKnxKNNwD4AQAcAAkKQBSNNwD4AQAMAAcKrw9TbQBeAQAAAA==.',
Fe='Fefifabrizio:BAAANQAECgEIAQAAAA==.Felix:BAAANQAECgUIEAAAAA==.Felraena:BAAANQADCgIIAgAAAA==.',
Fi='Finnagas:BAAANQAECgEJAQAAAA==.Finnw:BAAANQABCgcJCgAAAA==.Firelite:BAABNQAECn8kAAMGAAgKWAlpZQAcAQAGAAgKWAlpZQAcAQAFAAEKkwEyMgEeAAAAAA==.',
Fl='Flairadin:BAABNQAECn8mAAIRAAoKMRisPQBuAgARAAoKMRisPQBuAgAAAA==.Flee:BAAANQAECggIEwAAAA==.Fleromars:BAAANQAECgUIBQABNQAECggIEwAUAAAAAA==.Flexo:BAAANQAECgQIBQABNQAECgoKHwACAKcUAA==.',
Fo='Fookmii:BAAANQADCgUIBgAAAA==.',
Fr='Frogfist:BAAANQAECgMIAwAAAA==.Frowdawn:BAABNQAECn8sAAIPAAgKNguyHAAsAQAPAAgKNguyHAAsAQAAAA==.',
Fy='Fyf:BAAANQAECggIAwABNQADCggIEQAUAAAAAA==.',
Ga='Gallea:BAAANQAECgIIAgAAAA==.Garbanzo:BAAANQAECgUICgAAAA==.Garythenpc:BAAANQAECgEIAQAAAA==.',
Ge='Genericeric:BAAANQAECgUIBwAAAA==.Getsumei:BAEBNQAECn8ZAAMEAAoKDxLwEQDNAQAEAAoKDxLwEQDNAQADAAEKcwWLeQErAAAAAA==.',
Gi='Gidgett:BAAANQADCgcIFAAAAA==.Gilas:BAAANQADCgcICQAAAA==.',
Gl='Glacialkitty:BAABNQAECn8nAAIHAAkKLgc+MgAaAQAHAAkKLgc+MgAaAQAAAA==.Glizzygoblin:BAAANQADCgQIBAAAAA==.',
Go='Gobibug:BAAANQADCgIJAgAAAA==.Googoobler:BAAANQAECgEIAQAAAA==.Goudalovin:BAAANQADCgQIBAABNQAECgoKIQATADsVAA==.Goudanight:BAAANQADCgIIAgABNQAECgoKIQATADsVAA==.Goudatime:BAABNQAECn8hAAILAAcKoAsHSgDrAAALAAcKoAsHSgDrAAABNQAECgoKIQATADsVAA==.',
Gr='Greenknight:BAAANQADCggICQAAAA==.Greenmagus:BAAANQAECgEJAQAAAA==.Grenadon:BAAANQAECgEIAQAAAA==.Greyni:BAAANQABCgEIAQAAAA==.',
Gu='Gutz:BAAANQADCgMIAwAAAA==.',
Ha='Hadorya:BAAANQAECgIIAgAAAA==.Hakibalboa:BAABNQAECn9AAAIdAAkK1gziCwBBAQAdAAkK1gziCwBBAQAAAA==.Hakitua:BAAANQADCgYIBgAAAA==.Harick:BAAANQADCgQIBAAAAA==.Hazard:BAABNQAECn8pAAIOAAoKHQ+rDwCvAQAOAAoKHQ+rDwCvAQAAAA==.',
He='Heis:BAAANQAECgEIAQAAAA==.Hellboii:BAAANQAECgcIDgAAAA==.Heyitsrat:BAABNQAECn8pAAIDAAkKVAshkABrAQADAAkKVAshkABrAQAAAA==.',
Hi='Highhealzz:BAAANQADCgcIBwAAAA==.',
Ho='Hollowtips:BAAANQADCggIEwAAAA==.Holo:BAABNQAECn83AAMGAAoKrSQjGQAyAwAGAAkK+iQjGQAyAwAFAAoKPA4ldQCsAQAAAA==.Holyangus:BAAANQAECgYIEAAAAA==.Holyboga:BAAANQADCgIIAgAAAA==.Housemom:BAABNQAECn8VAAMEAAgKwAfLOQCZAAADAAcK2AfKBQEVAQAEAAQKJAbLOQCZAAAAAA==.',
Hu='Huntem:BAAANQADCgMIAgAAAA==.Huuginn:BAAANQADCggICgAAAA==.',
Ib='Ibbert:BAAANQADCggIKQAAAA==.',
Ic='Icculus:BAAANQAECgIIAwAAAA==.',
Il='Illadai:BAAANQADCggIEAAAAA==.Illyden:BAAANQABCgIIAgAAAA==.',
Im='Imamunch:BAAANQAECgEIAQAAAA==.Imaresmashy:BAAANQADCgIIAgABNQAECgcICgAUAAAAAA==.Iminyou:BAABNQAECn8rAAMGAAoKjhKTYAAAAgAGAAoKjhKTYAAAAgAFAAEK+Qow5AAyAAAAAA==.Impasse:BAAANQAECggICAAAAA==.',
Io='Iolz:BAAANQABCgQIBgABNQAECgoKMAASAMUXAA==.',
Ja='Jaenei:BAAANQAECgMIBAAAAA==.Janet:BAAANQAECgYIBgAAAA==.',
Je='Jeeb:BAABNQAECn8xAAITAAgKHA9lkQBVAQATAAgKHA9lkQBVAQAAAA==.',
Ji='Jinxta:BAABNQAECn8mAAINAAoKdRwGBQDQAgANAAoKdRwGBQDQAgAAAA==.',
Jo='Joansnow:BAABNQAECn8XAAIcAAkKFwhLTQCCAQAcAAkKFwhLTQCCAQAAAA==.Joeeo:BAABNQAECn8+AAMJAAoKHR7JIQCgAgAJAAoKHR7JIQCgAgAKAAcKigjlPgA2AQAAAA==.',
Ju='July:BAAANQAECgMIBAAAAA==.Julytonidas:BAABNQAECn8uAAITAAoKkRcwQAAoAgATAAoKkRcwQAAoAgAAAA==.Jurac:BAAANQADCggIGgAAAA==.',
Ka='Kaimargonar:BAABNQAECn8gAAINAAYKahH7DADUAAANAAYKahH7DADUAAAAAA==.Kaitoi:BAABNQAECn8hAAIVAAcKFxy+DQCgAQAVAAcKFxy+DQCgAQAAAA==.Kamakizeg:BAABNQAECn8lAAIDAAkKXA5UlwBdAQADAAkKXA5UlwBdAQAAAA==.Kamayla:BAAANQADCgYIBgAAAA==.Kateria:BAAANQAECggIDAABNQAECgoKPQAMAEAhAA==.Katimalice:BAAANQADCgQIDQAAAA==.',
Ke='Keathry:BAAANQAECgEIAQAAAA==.Keyzeus:BAAANQAECgIIAwAAAA==.',
Kh='Khas:BAAANQADCgYIDAAAAA==.Khui:BAACNQAFFH8OAAIXAAYKbiQNBAClAQAXAAYKbiQNBAClAQA1AAQKfzAAAxcACgrHI7IEAFoDABcACgrHI7IEAFoDAB4ABQqUHQk1AG0BAAAA.',
Ki='Killatu:BAAANQABCggIDQAAAA==.Killerdeath:BAAANQAECgQIAwAAAA==.',
Kn='Knìghtmàrè:BAACNQAFFH8OAAMMAAcK0A1xAwAsAQAMAAYKtQxxAwAsAQALAAMKhRRxHwCPAAA1AAQKfy0AAwwACgqzIxYUABgDAAwACgqzIxYUABgDAAsABwpzHuw0ADgCAAAA.',
Ko='Koltharaz:BAACNQAFFH8GAAIfAAIK4h8TCgDAAAAfAAIK4h8TCgDAAAA1AAQKfzIAAh8ACgrHG6cJANYCAB8ACgrHG6cJANYCAAAA.Korloff:BAAANQADCggIEwABNQAECgIIAwAUAAAAAQ==.Kozan:BAAANQAECgIIAwAAAQ==.',
Kr='Krazsz:BAAANQADCgQIBAAAAA==.Krazykraw:BAAANQAECgIIBQAAAA==.Krazylock:BAAANQAECgQICQAAAA==.Krokk:BAAANQABCgUIBQAAAA==.',
Ku='Kuiy:BAAANQADCgIIAgAAAA==.Kumah:BAAANQABCgEIAQAAAA==.Kungfuupanda:BAAANQAECgcIEwAAAA==.',
Ky='Kylar:BAAANQAECgQIBgAAAA==.',
La='Lateralus:BAABNQAECn8eAAIMAAgKsSIsMABvAgAMAAgKsSIsMABvAgABNQAECgoKGQAFAHEQAA==.Latt:BAABNQAECn8ZAAQFAAoKcRCyZABWAQAFAAkKRw6yZABWAQAgAAUKERa3GgAoAQAGAAIK3xhsAwGIAAAAAA==.Lawluss:BAABNQAECn8fAAIQAAkK+BJ5eACDAQAQAAkK+BJ5eACDAQAAAA==.Layonface:BAAANQAECgQIDAAAAA==.',
Le='Legacyshot:BAAANQAECgcICgAAAQ==.Lelwani:BAAANQADCgEIAQAAAA==.',
Li='Lickthecrit:BAAANQAECgMIBQAAAA==.Lightguard:BAAANQADCggICgAAAA==.Lighthouse:BAABNQAECn86AAMRAAoK+hfZSgA9AgARAAkK8xbZSgA9AgADAAkKPwqJlABiAQAAAA==.Lightload:BAAANQAECgQIDAAAAA==.Lileth:BAAANQAECgIIAwAAAA==.',
Lo='Lolhahabaha:BAAANQAECgUIDQAAAA==.Lonê:BAAANQAECgIIAgAAAA==.Loopie:BAAANQAECgYIDAAAAA==.Lorax:BAAANQAECgYICAAAAA==.',
Lu='Luckÿ:BAAANQAECgEJAQAAAA==.Luminah:BAAANQABCgIIAQAAAA==.',
Ly='Lypally:BAABNQAECn85AAIDAAoKeAZspABEAQADAAoKeAZspABEAQAAAA==.',
['Lï']='Lïllïth:BAABNQAECn8hAAIQAAgKDQdywQB/AQAQAAgKDQdywQB/AQAAAA==.Lïly:BAAANQAECgUIBwABNQAECgcICgAUAAAAAA==.',
['Ló']='Lóla:BAABNQAECn8rAAIaAAgKvB4dEwDRAgAaAAgKvB4dEwDRAgAAAA==.',
['Lü']='Lüvine:BAAANQAECggIBQAAAA==.',
Ma='Madeah:BAACNQAFFH8fAAIPAAcKtBSLAgBcAgAPAAcKtBSLAgBcAgA1AAQKfyAAAw8ACQoDJPQBADQDAA8ACQoDJPQBADQDACEACApcCrMpAHcBAAAA.Madforge:BAABNQAECn88AAIFAAkKAxnoIwBzAgAFAAkKAxnoIwBzAgAAAA==.Magegrizz:BAAANQAECgYIDgAAAA==.Magnyson:BAAANQAECggIDAAAAA==.Mahimahi:BAAANQADCgYICgAAAA==.Manahole:BAABNQAECn8/AAITAAoKRiL3DQAJAwATAAoKRiL3DQAJAwAAAA==.Mariacuras:BAABNQAECn8nAAIRAAkKHhKHOAAEAgARAAkKHhKHOAAEAgAAAA==.Marijwana:BAAANQAECgcIEAAAAA==.Marynne:BAABNQAECn8yAAIHAAkK0AxPJACFAQAHAAkK0AxPJACFAQAAAA==.Massaker:BAAANQADCggICgAAAA==.Mazuko:BAABNQAECn8lAAIiAAoKwRj1LwAoAgAiAAoKwRj1LwAoAgAAAA==.',
Mc='Mctank:BAAANQADCggIFAAAAA==.',
Me='Mecandry:BAABNQAECn8/AAIQAAkK7xL9ZQBIAgAQAAkK7xL9ZQBIAgAAAA==.Mecks:BAAANQADCggIJAAAAA==.Meepe:BAAANQADCgcIDQAAAA==.Melivant:BAABNQAECn8mAAQEAAgK7RETMwBKAQAEAAYKVRMTMwBKAQARAAUKeQ+hgQABAQADAAcKvQrbNAHLAAAAAA==.Meranda:BAABNQAECn8hAAITAAoKOxWHqAAxAgATAAoKOxWHqAAxAgAAAA==.Merrikfang:BAAANQADCgcIBwAAAA==.Merriklade:BAABNQAECn8wAAQOAAkKVA3fDwA6AQASAAcK7wWL1QBFAQAOAAgKSA7fDwA6AQAjAAIKrwf3MQBVAAAAAA==.Merrikoid:BAABNQAECn8ZAAMZAAcKqQ1BHQDrAAAZAAYKEg9BHQDrAAAaAAYKsAXjOgCXAAAAAA==.Merrikwolf:BAAANQADCggIDgAAAA==.',
Mi='Mico:BAAANQAECgUIEAAAAA==.Missyjelliot:BAAANQAECgMIAwAAAA==.',
Mo='Mokkii:BAAANQADCgEIAQAAAA==.Morbidstyle:BAAANQAECgYIDQABNQAECgoKOQAGAFMUAA==.Morgoth:BAABNQAECn81AAICAAoKqRZsUwBbAgACAAoKqRZsUwBbAgAAAA==.Morthos:BAAANQADCgcICgAAAA==.Mosry:BAABNQAECn87AAILAAoKKB5CEwBVAgALAAoKKB5CEwBVAgABNQABCgQIBgAUAAAAAA==.Mourneblood:BAAANQADCgUIBQAAAA==.',
My='Myora:BAEANQADCgcICQABNQAECgoKGQAEAA8SAA==.Mythundirus:BAABNQAECn8eAAIaAAoKsAJrOwCUAAAaAAoKsAJrOwCUAAAAAA==.',
['Mà']='Màrli:BAABNQAECn81AAILAAkKthcDJgChAQALAAkKthcDJgChAQAAAA==.',
['Mâ']='Mâgs:BAABNQAECn8qAAIEAAkKJA1QIQAvAQAEAAkKJA1QIQAvAQAAAA==.',
Na='Nakasid:BAABNQAECn9BAAMJAAoKshnWGwDLAgAJAAoKshnWGwDLAgAKAAUKBgcBUADSAAAAAA==.Nashoba:BAAANQADCgYJCwAAAA==.Natooka:BAAANQADCgUIBQAAAA==.',
Ne='Nein:BAAANQAECgQIDAAAAA==.Neins:BAAANQADCgYIEAABNQAECgQIDAAUAAAAAA==.Nevaehstar:BAABNQAECn9GAAITAAoKexFVTgD+AQATAAoKexFVTgD+AQAAAA==.',
Ni='Nibuto:BAAANQAECgYIEQAAAA==.Nijun:BAEBNQAECn80AAIJAAoKpA8bOwAXAgAJAAoKpA8bOwAXAgAAAA==.Nik:BAABNQAECn8YAAMFAAkKkg3EUgCVAQAFAAkKkg3EUgCVAQAGAAEKAAA9XgEbAAAAAA==.Nikita:BAAANQABCgQIBgAAAA==.Nikolia:BAABNQAECn8ZAAQjAAcKtggfKgDpAAAjAAUK7AwfKgDpAAAOAAQKegRwKwBYAAASAAQK8QHWBAFBAAAAAA==.Ninetynine:BAAANQADCgQIBAAAAA==.Nini:BAABNQAECn8VAAIIAAcKEAJtjwCZAAAIAAcKEAJtjwCZAAAAAA==.Ninx:BAAANQADCgUICQAAAA==.',
No='Noivana:BAAANQABCgEIAQABNQAFFAcIEgAiAM4YAA==.',
Ny='Nystel:BAAANQADCgEIAQAAAA==.',
Ol='Ollichi:BAAANQADCgIIAgAAAA==.',
Or='Ornn:BAAANQAECgcICwABNQAECgoKLgABABwjAA==.',
Os='Osoroshi:BAAANQADCgYJBgABNQAECgkJPwAQAO8SAA==.',
Ov='Overtime:BAAANQADCggIEQAAAA==.',
Pa='Padmê:BAAANQADCgMIAwAAAA==.Paladrak:BAAANQADCgIIAgAAAA==.Pandamared:BAAANQADCggIEgAAAA==.Patronous:BAAANQADCgYIDAAAAA==.',
Ph='Phenol:BAAANQADCgEIAQAAAA==.',
Po='Polog:BAAANQAECgIIAgABNQAECgoKKwATAL0iAA==.Porkchoplust:BAAANQADCgYIBQAAAA==.Porkribs:BAABNQAECn8bAAIRAAgKkRqKRQBQAgARAAgKkRqKRQBQAgAAAA==.',
Pr='Pranks:BAAANQAECgQICgAAAA==.Premalone:BAAANQADCgUICQAAAA==.',
Pu='Puca:BAAANQAECgEIAQAAAA==.Pumdmuc:BAABNQAECn8bAAMJAAgKph8sLwBSAgAJAAcKfCEsLwBSAgAKAAEKCgjUVAA2AAAAAA==.Punchymcheal:BAAANQAECggIDgABNQAECgoKOwAJAPMaAA==.',
Qu='Quikfix:BAAANQAECgIIAgAAAA==.Quikglaives:BAAANQAECgMIAgAAAA==.Quille:BAABNQAECn8oAAIQAAoKiB75VQBwAgAQAAoKiB75VQBwAgAAAA==.',
Ra='Ragretts:BAAANQAECgEIAQAAAA==.Rahhem:BAAANQADCgYIBgAAAA==.Ranmo:BAAANQAECggIEQAAAA==.Ratkol:BAAANQABCgIIAgAAAA==.Raysdknight:BAAANQADCgIJBwAAAA==.',
Re='Recbra:BAAANQAECgYIBgAAAA==.Redrek:BAAANQADCgcILQAAAA==.Redsbank:BAAANQADCgUIBQAAAA==.Redshunter:BAAANQADCgcIJQAAAA==.Redsknight:BAAANQADCgYIAQAAAA==.Redsmonk:BAAANQADCggICQAAAA==.Redwinter:BAABNQAECn8nAAMLAAkKVCCNLABlAgALAAkKVCCNLABlAgAcAAEKAAAXtQAAAAAAAA==.Regnor:BAAANQADCgUIBQAAAA==.Reikisong:BAAANQAECgMIBgAAAA==.Reiluune:BAAANQADCgQIAwABNQAECggIKwAaALweAA==.Remmie:BAAANQADCgUIBwAAAA==.',
Rh='Rhagurion:BAABNQAECn8+AAIbAAoKdSa6AADtAwAbAAoKdSa6AADtAwAAAA==.',
Ri='Riqua:BAAANQAECgMIBQAAAA==.',
Ro='Rockmonsta:BAAANQADCgYJCgAAAA==.Rockys:BAAANQABCgQIBQAAAA==.Roxies:BAAANQAECgMIBgAAAA==.',
Rp='Rpg:BAABNQAECn8cAAITAAkKlRkjmQBOAgATAAkKlRkjmQBOAgAAAA==.',
Ru='Rumie:BAAANQADCgUIBQAAAA==.Runes:BAAANQAECgcICwAAAA==.',
Sa='Saeti:BAABNQAECn9MAAUVAAoKdCSMAQBCAwAVAAkKdCSMAQBCAwAIAAYKnx5AMABMAQAHAAUKEQyeTwDLAAAbAAEKxB+XUwBWAAAAAA==.Sanare:BAAANQAECggIBwABNQAECgoKOwAJAPMaAA==.Sanbit:BAAANQAECgQIBQAAAA==.Santhaenis:BAAANQAECgQIBQAAAA==.Sapplesauce:BAAANQAECgcIBwAAAA==.',
Se='Seethrowwar:BAABNQAECn8iAAMSAAkKuh6vOwDYAgASAAkKaB6vOwDYAgAjAAYKQRbiGwB9AQAAAA==.Senbit:BAAANQAECgUIDQAAAA==.Serenìty:BAAANQAECgYIDAAAAA==.Seresin:BAABNQAECn9lAAMHAAoKiRlfFQCbAgAHAAoKiRlfFQCbAgAIAAUKkwVbggDHAAAAAA==.',
Sh='Shadý:BAABNQAECn8jAAIQAAkKiQUu5AA4AQAQAAkKiQUu5AA4AQAAAA==.Shamanoodles:BAAANQADCggIFAABNQAECgoKKwATAL0iAA==.Shortwarrior:BAABNQAECn8lAAIOAAcKUxK+EAAqAQAOAAcKUxK+EAAqAQAAAA==.',
Si='Sianu:BAAANQAECgQICwABNQAECgkJMgAHANAMAA==.Sidraya:BAABNQAECn8WAAMWAAYKwxT2FwA6AQAWAAYKwxT2FwA6AQATAAEKxQN+SQExAAAAAA==.Silent:BAABNQAECn8wAAISAAoKxReraQBTAgASAAoKxReraQBTAgAAAA==.Silverserqet:BAABNQAECn8hAAIQAAcKzQrTrQASAQAQAAcKzQrTrQASAQAAAA==.',
Sl='Slipknaught:BAAANQABCgQIBQABNQAECgkJFwAcABcIAA==.',
Sm='Smileyriley:BAAANQADCgUIBQAAAA==.',
Sn='Sneakylinks:BAAANQADCgIIAgABNQAECgkJHAATAJUZAA==.',
So='Sonbit:BAAANQADCggJDwAAAA==.Sonichero:BAAANQAECgQIBAAAAA==.Sooki:BAAANQAECgMIBQAAAA==.Sophie:BAAANQAECgQIDgAAAA==.Soulber:BAAANQAECgMIBAAAAA==.',
Sp='Spunky:BAAANQAECgQIBAAAAA==.',
Ss='Ssenbit:BAAANQAECgUIBAAAAA==.Ssonbit:BAAANQADCggIEAAAAA==.',
St='Stefeana:BAAANQADCgYIBgAAAA==.Sternhoof:BAAANQABCgMIBQAAAA==.Stigma:BAAANQADCggIFQABNQAECgoKJQAJAOIgAA==.Stylos:BAABNQAECn8xAAIgAAkKXBHjEADIAQAgAAkKXBHjEADIAQAAAA==.',
Su='Summersong:BAAANQADCgQIBAAAAA==.Sumofwhy:BAAANQADCgcIBwAAAA==.',
Sw='Swarli:BAAANQAECgIIAgAAAA==.Swowtitbang:BAAANQAECgYIEAAAAA==.',
Sy='Sylven:BAAANQAECgUIBwABNQAECgoKNAAGAAcgAA==.',
Te='Techno:BAAANQAECggICgAAAA==.Tegbolt:BAABNQAECn8dAAMGAAgKeRXAZgDsAQAGAAgKghPAZgDsAQAgAAcKLhLWGwCmAQAAAA==.Teghorn:BAAANQAECggICAABNQAECggIHQAGAHkVAA==.Tekko:BAABNQAECn9BAAMbAAoK4RphCwBTAgAbAAkK+R1hCwBTAgAVAAEKOQX8UAAQAAAAAA==.Tempestrike:BAABNQAECn8oAAIaAAoKehuRDwD3AgAaAAoKehuRDwD3AgAAAA==.',
Th='Theholymatt:BAABNQAECn9BAAMRAAoKTiREEgA9AwARAAoKTiREEgA9AwADAAUKtRDnzgD7AAAAAA==.Thendari:BAABNQAECn9UAAINAAkKjA4dBQB0AQANAAkKjA4dBQB0AQAAAA==.Theodus:BAABNQAECn8oAAITAAoK+RG2twAUAgATAAoK+RG2twAUAgAAAA==.Therayen:BAAANQADCgYJCwAAAA==.Thomeriddle:BAAANQABCgMIAQAAAA==.',
Ti='Tiferis:BAACNQAFFH8IAAIRAAUKqBQIDgAoAQARAAUKqBQIDgAoAQA1AAQKfz8AAhEACgqfICUJAG8DABEACgqfICUJAG8DAAAA.Tigerclawss:BAAANQADCggIKwAAAA==.Tislam:BAAANQAECgMIBAAAAA==.',
To='Tobiquer:BAABNQAECn9CAAIJAAkKpCH/GQAMAwAJAAkKpCH/GQAMAwAAAA==.Tojarmar:BAAANQADCgQIBAAAAA==.Torolf:BAAANQAECgMIBQAAAA==.',
Tq='Tqco:BAAANQADCgMIAwABNQAECgoKQQAbAOEaAA==.',
Tr='Traydra:BAAANQADCgUIBwAAAA==.Trinbug:BAAANQADCgEIAQAAAA==.Troglodyte:BAABNQAECn9PAAIGAAoKBiS0BgA5AwAGAAoKBiS0BgA5AwAAAA==.',
Ts='Tsonokwabain:BAABNQAECn8jAAIcAAkKMh3pKgBFAgAcAAkKMh3pKgBFAgAAAA==.Tsunami:BAAANQADCgMIAwAAAA==.',
Tw='Twistdog:BAAANQABCgQIBgAAAA==.',
Ty='Tye:BAABNQAECn8iAAIQAAoKohfmRwAFAgAQAAoKohfmRwAFAgAAAA==.Tyranastrasz:BAABNQAECn80AAQfAAoKeQdVHgBtAQAfAAgK1QVVHgBtAQAkAAoK0QTNFgBHAQAlAAEKTQCNKQANAAAAAA==.Tyye:BAABNQAECn8oAAIOAAcKiCJ0BgAjAgAOAAcKiCJ0BgAjAgAAAA==.',
['Tâ']='Tâjik:BAABNQAECn8jAAIhAAoKtATKKQB2AQAhAAoKtATKKQB2AQAAAA==.',
Ul='Ulquiorra:BAACNQAFFH8LAAMaAAUK4w9sDQDUAAAaAAQK4w9sDQDUAAAZAAIKQAiPBwBCAAA1AAQKfzYAAxoACgoVIQ0QAPICABoACQoVIQ0QAPICABkABAoIDe8gAL0AAAAA.',
Ut='Uthers:BAAANQADCgYIAgAAAA==.',
Va='Vaethund:BAAANQAECgMIBAAAAA==.Valdred:BAAANQAECgcIBgABNQAFFAcIEgAiAM4YAA==.Valgavoth:BAABNQAECn8VAAILAAkK4Bf/NwApAgALAAkK4Bf/NwApAgAAAA==.Vangar:BAAANQADCgQIBAAAAA==.Vanthion:BAAANQADCggICgAAAA==.',
Ve='Velara:BAAANQAECgQIBQAAAA==.Velinna:BAAANQADCgUIBwABNQAECgEIAQAUAAAAAA==.Venekor:BAAANQADCgIIAgAAAA==.',
Vi='Viriex:BAAANQADCgIIAgAAAA==.Vitoria:BAAANQAECgQIBgAAAA==.',
Vo='Voidlighter:BAABNQAECn87AAIJAAoK8xo1JADcAgAJAAoK8xo1JADcAgAAAA==.Volundr:BAABNQAECn8oAAIjAAoKlRkeDgBNAgAjAAoKlRkeDgBNAgAAAA==.Vonvaughan:BAAANQAECgQIAgAAAA==.',
Vy='Vynel:BAAANQADCgMIAwABNQAECgoKNAAGAAcgAA==.Vynirion:BAAANQAECgEIAQAAAA==.',
Wa='Wardellmo:BAAANQADCgQIBAAAAA==.Wargtar:BAABNQAECn8bAAIPAAcKCBnbMwAMAgAPAAcKCBnbMwAMAgAAAA==.Warriorskull:BAAANQADCgYICAAAAA==.',
We='Weabe:BAAANQAECgIIAwAAAA==.',
Wh='Whiterrina:BAAANQADCgIJAgAAAA==.Whitespring:BAAANQAECgYIEAABNQAECgkJJwALAFQgAA==.',
Wo='Wolfgarou:BAAANQABCgIIAgAAAA==.',
Wy='Wyrdo:BAAANQADCgYIBgAAAA==.',
['Wù']='Wùsthof:BAABNQAECn8fAAIQAAkKYApKiQD4AQAQAAkKYApKiQD4AQAAAA==.',
Xa='Xandrios:BAAANQAECgEJAQAAAA==.',
Xi='Xiae:BAABNQAECn8pAAMGAAoKdBfzTABDAgAGAAgK6RbzTABDAgAFAAQKfQ/1jwDXAAAAAA==.',
Ya='Yasuke:BAAANQADCgUJBQAAAA==.',
Ye='Yet:BAAANQAECgEIAQABNQAECgoKLgATACYjAA==.',
Yi='Yiffweaver:BAAANQAECgEIAQAAAA==.',
Yo='Yokochan:BAAANQABCgIIAgAAAA==.Yokoriazen:BAABNQAECn83AAIDAAoKfxUMYQB2AgADAAoKfxUMYQB2AgAAAA==.',
Za='Zakaradin:BAAANQADCgcICAABNQAECgIIAwAUAAAAAA==.Zandigor:BAAANQAECgIIAQAAAA==.Zaraeliana:BAAANQAECgMIBAAAAA==.Zarastraza:BAABNQAECn8kAAMkAAkKFhFxIgC3AQAkAAkKFhFxIgC3AQAfAAUKFQt0JQAPAQAAAA==.',
Ze='Zephnor:BAABNQAECn8hAAMbAAgKhw9lJABzAQAbAAcK/xBlJABzAQAIAAgKxQnTYgBDAQAAAA==.',
Zh='Zhao:BAAANQADCgYIBgAAAA==.',
Zm='Zmona:BAAANQAECgQIBAAAAA==.',
Zo='Zorsche:BAAANQAECgEIAQAAAA==.',
Zu='Zulrok:BAABNQAECn8uAAISAAkKRRKJXACxAQASAAkKRRKJXACxAQAAAA==.',
['Áb']='Ábsurd:BAAANQAECggICgABNQABCgIIAQAUAAAAAA==.',
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
