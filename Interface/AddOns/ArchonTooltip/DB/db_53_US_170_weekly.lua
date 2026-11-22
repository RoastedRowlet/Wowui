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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Druid-Balance','Priest-Holy','Priest-Shadow','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Destruction','Warrior-Fury','Rogue-Assassination','Hunter-BeastMastery','Paladin-Holy','Warrior-Arms','Mage-Arcane','Warrior-Protection','Unknown-Unknown','Druid-Feral','Mage-Frost','Monk-Mistweaver','DeathKnight-Frost','Mage-Fire','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian','Rogue-Subtlety','Monk-Brewmaster','Monk-Windwalker','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Havoc','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Absol:BAABNQAECn8uAAMBAAoKHCOkAACaAwABAAoKwCKkAACaAwACAAoKjB73PQCZAgAAAA==.',
Ac='Achilles:BAABNQAECn85AAMDAAoKWxORmADyAQADAAoKXBCRmADyAQAEAAUKVBMoNgDZAAAAAA==.',
Ad='Adenox:BAAANQAECgMIAwAAAA==.',
Ae='Aeon:BAAANQAECgQICAAAAA==.Aerís:BAAANQADCgIIAgAAAA==.',
Ah='Ahsokatano:BAABNQAECn8rAAMFAAoKKhqvIQCyAgAFAAoKKhqvIQCyAgAGAAEKAACaPgEuAAAAAA==.',
Ai='Ailing:BAAANQADCgYIDAAAAA==.Aimspet:BAABNQAECn8vAAIFAAkKKBtYJQCcAgAFAAkKKBtYJQCcAgAAAA==.Airocket:BAAANQADCgMIAwAAAA==.',
Ak='Akasha:BAAANQABCgMIBwAAAA==.Akos:BAAANQAECgcIBgABNQAECgoKgQAHAMkZAA==.',
Al='Alukai:BAAANQAECgQIBgAAAA==.Alzaeryan:BAABNQAECn8aAAIIAAgKtBdwQwDmAQAIAAgKtBdwQwDmAQAAAA==.',
Am='Am:BAAANQAECgMIAwAAAA==.Amonet:BAAANQAECgEIAQAAAA==.',
An='Anaelcheese:BAAANQAECgYIBwAAAA==.Anamis:BAABNQAECn8wAAMJAAoKHBWXUwAoAgAJAAoKHBWXUwAoAgAKAAEKHwXcgQAoAAAAAA==.Angras:BAABNQAECn8dAAMLAAYKogsPiQDbAAALAAUKwwwPiQDbAAAMAAUK0gbcYgCBAAAAAA==.',
Ap='Aphalock:BAABNQAECn81AAINAAoKlQmBCABFAQANAAoKlQmBCABFAQAAAA==.',
Ar='Aradial:BAAANQADCgEIAQAAAA==.Arane:BAAANQADCgcIBwAAAA==.Ariûs:BAABNQAECn8fAAIOAAoKZw5oDQCsAQAOAAoKZw5oDQCsAQAAAA==.Arlin:BAAANQAECgEIAQAAAA==.Arlorian:BAABNQAECn9FAAIPAAoKZhAJDwDXAQAPAAoKZhAJDwDXAQAAAA==.Arrenn:BAAANQAECgUIDgAAAA==.Arrowsmites:BAABNQAECn8xAAIQAAoK4xr6PABdAgAQAAoK4xr6PABdAgAAAA==.',
As='Askelad:BAABNQAECn8mAAIDAAkKVwiB0AA3AQADAAkKVwiB0AA3AQAAAA==.',
Au='Aubani:BAABNQAECn80AAMRAAoKAxjVMABdAgARAAoKAxjVMABdAgADAAcKoRA+6gBHAQAAAA==.',
Ax='Axelot:BAAANQAECgcIDgAAAA==.',
Ay='Ayperos:BAABNQAECn9CAAISAAoKZg/KXQDmAQASAAoKZg/KXQDmAQAAAA==.',
Ba='Bakedpally:BAABNQAECn8rAAIDAAoK/AZPzAA+AQADAAoK/AZPzAA+AQAAAA==.Bakedwarrior:BAAANQADCgIIAgAAAA==.Bandomar:BAAANQAECgIIAwAAAA==.Baniemo:BAAANQAECgUIBQAAAA==.Banigor:BAABNQAECn8YAAISAAgKUwrSqAApAQASAAgKUwrSqAApAQAAAA==.Bankaltanon:BAAANQAECgUICQAAAA==.Baragnis:BAAANQAECgUIBQAAAA==.',
Be='Beavur:BAABNQAECn8UAAITAAYKXQreKgFEAQATAAYKXQreKgFEAQAAAA==.Beck:BAABNQAECn8wAAIDAAgKziEYRABdAgADAAgKziEYRABdAgAAAA==.Beggars:BAAANQAECgUIDAAAAA==.Bereth:BAAANQAECgEIAQAAAA==.Berreydingle:BAAANQADCggIFwAAAA==.',
Bi='Bigboii:BAAANQAECgEIAQAAAA==.Bigkitty:BAAANQAECgIIAgABNQAECgoKIQATADsVAA==.Bigntall:BAAANQAECgIIAgAAAA==.Bikinibrenda:BAAANQAECgQIEgAAAA==.',
Bl='Blackhuuf:BAAANQADCgUIBQAAAA==.Blitzedbust:BAAANQADCggIFQAAAA==.Bloodmender:BAAANQADCgYIBwABNQAECgoKKwATAL0iAA==.Bluesummer:BAABNQAECn8WAAMSAAgKjRTMjgBkAQASAAcKjRTMjgBkAQAUAAIKaBNJPgBJAAABNQAECgkJLwALAGQgAA==.',
Bo='Bobeh:BAAANQAECgEIAgABNQADCgEIAQAVAAAAAA==.Bonzai:BAAANQAECgcICQABNQAECgoKLgABABwjAA==.Boomskittles:BAAANQABCgMIAwAAAA==.Borat:BAABNQAECn8uAAITAAoKJiPOCQCxAwATAAoKJiPOCQCxAwAAAA==.Borsam:BAAANQABCgcICQAAAA==.',
Br='Brendameeks:BAAANQADCgQIBAAAAA==.Broadzinatl:BAAANQAECgIIAgABNQAECgQIAgAVAAAAAA==.Brom:BAAANQAECgQIBgAAAA==.Brutesse:BAAANQAECgQIDAAAAA==.Bròly:BAAANQADCgMIAwAAAA==.',
Bu='Buttercups:BAAANQAECgQIBAAAAA==.',
['Bè']='Bètflèch:BAAANQAECgMIBAAAAA==.',
['Bø']='Bøss:BAAANQADCggIGQAAAA==.',
Ca='Cad:BAAANQADCgYIEAAAAA==.Calytrix:BAEBNQAECn8uAAQIAAoKRRPxOgAcAgAIAAoKRRPxOgAcAgAHAAIKQBOIYwBqAAAWAAEKXxG4QAA5AAABNQAECgoKJgAEAJESAA==.Captnhammer:BAAANQADCgEIAQAAAA==.Carnelian:BAAANQAECgEIAQAAAA==.Castration:BAAANQADCgYICQAAAA==.',
Ce='Ceylan:BAABNQAECn8uAAIXAAoKSxwfBwBPAgAXAAoKSxwfBwBPAgAAAA==.',
Ch='Chaleb:BAAANQAECgEIAQAAAA==.Charlz:BAABNQAECn8mAAMJAAoKlRrZGQAJAwAJAAoKlRrZGQAJAwAKAAUKUA6wQACsAAAAAA==.Charsifood:BAAANQAECgcIDgAAAA==.Chat:BAABNQAECn8XAAIYAAgKaiYbAwCEAwAYAAgKaiYbAwCEAwAAAA==.Cheatpriest:BAABNQAECn8/AAIJAAoK+RPGYAC+AQAJAAoK+RPGYAC+AQAAAA==.Cheatw:BAAANQAECgMIAwAAAA==.Cheatwl:BAAANQADCgIIAgAAAA==.Chepis:BAAANQADCgcJEAAAAA==.Chesthyr:BAAANQADCgcIDgAAAA==.Chestoe:BAAANQAECgUIEAAAAA==.Chitchatted:BAAANQADCgIIAgAAAA==.',
Ci='Cindrethresh:BAAANQADCgMIAwAAAA==.',
Co='Cognition:BAABNQAECn9OAAIQAAoKGCRFEAARAwAQAAoKGCRFEAARAwAAAA==.Coldvengance:BAABNQAECn8qAAIOAAoKKwltEwBpAQAOAAoKKwltEwBpAQAAAA==.Cortisol:BAAANQAECggICQAAAA==.',
Cr='Cranknstein:BAAANQADCggJCAABNQADCggIEQAVAAAAAA==.Crazh:BAAANQAECgIIAwAAAA==.Crazycalla:BAAANQAECgQICQAAAA==.Croven:BAAANQADCgUIBQAAAA==.Crànk:BAAANQAECgcIAgABNQADCggIEQAVAAAAAA==.',
Cu='Cuensour:BAAANQADCgcJDQAAAA==.Cutemenace:BAAANQADCgIIAgABNQAECgoKQgALAMAbAA==.',
Cy='Cymindel:BAABNQAECn9BAAILAAoKsBlcFQBgAgALAAoKsBlcFQBgAgAAAA==.Cyphr:BAAANQAECgYICgAAAA==.',
Da='Dakotà:BAABNQAECn8tAAIQAAoKTBLSXgAKAgAQAAoKTBLSXgAKAgAAAA==.Darc:BAAANQAECggIDAAAAA==.Daredayo:BAAANQADCgIIAgAAAA==.Darkangelz:BAAANQAECgUIBQAAAA==.Darklorising:BAAANQAECgIIAgAAAA==.Darktroll:BAAANQAECgUIBQAAAA==.Darkwave:BAAANQAECggIEgAAAA==.',
De='Dejno:BAABNQAECn8WAAMOAAcKlSD7CQAxAgAOAAYKxCL7CQAxAgASAAIK/BTGKAGFAAAAAA==.Deleted:BAAANQADCgUIBQABNQAECgoKKwATAL0iAA==.Demonred:BAAANQADCgQIBAAAAA==.Derpla:BAAANQAECgMIBQABNQAECgoKHQAZALsJAA==.Dethra:BAAANQAECgQIEwAAAA==.Dezign:BAACNQAFFH8gAAMXAAgKAx0uAQB7AQATAAcKNRqkFADSAQAXAAQKpSMuAQB7AQA1AAQKf1oABBcACgqNJlEAANwDABcACQpzJlEAANwDABMACgqbJX4LACwDABoAAwoSIEgHALUAAAAA.',
Do='Dolgorukov:BAABNQAECn8uAAIQAAoKLQ9hZgD4AQAQAAoKLQ9hZgD4AQAAAA==.Dologony:BAABNQAECn8bAAIHAAoKmwq5LACKAQAHAAoKmwq5LACKAQAAAA==.Dorgar:BAAANQADCgcIDQAAAA==.',
Dr='Draccosa:BAAANQADCgIIAgAAAA==.Dracigor:BAAANQAECgQIBAAAAA==.Dragonmage:BAAANQAECgUICwAAAA==.Drakhan:BAAANQAECgUIBgAAAA==.Drakma:BAAANQAECgMIBQAAAA==.Drastio:BAAANQADCgMIAwAAAA==.Drikken:BAABNQAECn9UAAMbAAoKshmSCwAVAgAbAAoKshmSCwAVAgAcAAoKeRELGgDdAQAAAA==.Drmaker:BAAANQAECgUIBgAAAA==.Druj:BAEANQADCggIDAABNQAECgoKJgAEAJESAA==.',
Du='Durasan:BAAANQADCgMIAwAAAA==.Duressa:BAAANQAECgUIBAAAAA==.',
['Dö']='Dötdötdead:BAABNQAECn8ZAAMCAAkKeg1YeQByAQACAAkKeg1YeQByAQANAAEKAABphgAiAAAAAA==.',
Ef='Effindin:BAAANQADCgYIBgAAAA==.Effinsick:BAAANQAECgQIBAAAAA==.',
Ei='Eins:BAAANQADCggICAABNQAECgQIDwAVAAAAAA==.Eisheth:BAAANQAECgIIAwAAAA==.',
El='Elerav:BAAANQAECgQIBwAAAA==.Ellysiaa:BAAANQADCggIJwAAAA==.',
Em='Emmakyn:BAABNQAECn8lAAMIAAoKyxBlQgDtAQAIAAoKyxBlQgDtAQAdAAEK3BamXAA8AAAAAA==.Emriss:BAABNQAECn87AAIZAAoKzgtTOwCxAQAZAAoKzgtTOwCxAQAAAA==.',
En='Endjinns:BAAANQADCggICAAAAA==.Enyxea:BAAANQAECgMIBAAAAA==.',
Ep='Ephemera:BAAANQAECgEIAQAAAA==.',
Er='Erodin:BAAANQADCgYICwAAAA==.',
Es='Esman:BAAANQADCgMIAwAAAA==.',
Ey='Eyedontknow:BAABNQAECn8oAAIEAAkKMxvbFQDSAQAEAAkKMxvbFQDSAQAAAA==.',
Ez='Ezzka:BAABNQAECn9KAAMMAAoKZCLECADpAgAMAAoKZCLECADpAgALAAIKxhsUqgB8AAAAAA==.',
Fa='Faceless:BAAANQAECgYIBQAAAA==.Failroots:BAAANQAECgIIAgAAAA==.False:BAAANQAECgUIDAAAAA==.Farnsworth:BAABNQAECn8vAAQNAAoKyRm4CABAAQACAAoK/xb5RgAAAgANAAQKaxu4CABAAQABAAEKsBITLAA9AAAAAA==.Farzix:BAABNQAECn8UAAIGAAcK4AZguwAbAQAGAAcK4AZguwAbAQAAAA==.Fatherdrew:BAABNQAECn86AAMJAAoKQyICDQB4AwAJAAoKQyICDQB4AwAKAAIKkwcJaQArAAAAAA==.Façade:BAABNQAECn8hAAMZAAoKnxKNNwD4AQAZAAkKQBSNNwD4AQAMAAcKrw9TbQBeAQAAAA==.',
Fe='Fefifabrizio:BAAANQAECgEIAQAAAA==.Felix:BAAANQAECgQIEAAAAA==.Felraena:BAAANQADCgIIAgAAAA==.',
Fi='Finnagas:BAAANQAECgEJAQAAAA==.Finnw:BAAANQABCgcJCgAAAA==.Firelite:BAABNQAECn8lAAMGAAgKWAltewAcAQAGAAgKWAltewAcAQAFAAEKkwEyMgEeAAAAAA==.',
Fl='Flairadin:BAABNQAECn8pAAIRAAoKMRisPQBuAgARAAoKMRisPQBuAgAAAA==.Flee:BAABNQAECn8fAAMeAAoKvBF0PAAKAgAeAAoKvBF0PAAKAgAPAAEKyQb4pAAyAAAAAA==.Fleromars:BAAANQAECgUIBQABNQAECgoKHwAeALwRAA==.Flexo:BAAANQAECgQIBQABNQAECgoKLwANAMkZAA==.',
Fo='Fookmii:BAAANQADCgUIBgAAAA==.',
Fr='Frogfist:BAAANQAECgMIAwAAAA==.Frowdawn:BAABNQAECn83AAIPAAoK0wvNEgCiAQAPAAoK0wvNEgCiAQAAAA==.',
Fy='Fyf:BAAANQAECggIAwABNQADCggIEQAVAAAAAA==.',
Ga='Gallea:BAAANQAECgIIAgAAAA==.Garbanzo:BAAANQAECgUICgAAAA==.Garythenpc:BAAANQAECgEIAQAAAA==.',
Ge='Genericeric:BAAANQAECgUIBwAAAA==.Getsumei:BAEBNQAECn8mAAMEAAoKkRK3FgDHAQAEAAoKkRK3FgDHAQADAAQK+wlyMQGiAAAAAA==.',
Gi='Gidgett:BAAANQADCgcIFAAAAA==.Gilas:BAAANQAECgEIAQAAAA==.',
Gl='Glacialkitty:BAABNQAECn8sAAIHAAoKNghYMwBXAQAHAAoKNghYMwBXAQAAAA==.Glizzygoblin:BAAANQADCgQIBAAAAA==.',
Go='Gobibug:BAAANQADCgIJAgAAAA==.Googoobler:BAAANQAECgEIAQAAAA==.Goudalovin:BAAANQADCgQIBAABNQAECgoKIQATADsVAA==.Goudanight:BAAANQADCgIIAgABNQAECgoKIQATADsVAA==.Goudatime:BAABNQAECn8jAAILAAkKmgs0QQA5AQALAAkKmgs0QQA5AQABNQAECgoKIQATADsVAA==.',
Gr='Greenknight:BAAANQADCggICQAAAA==.Greenmagus:BAAANQAECgEJAQAAAA==.Grenadon:BAAANQAECgEIAQAAAA==.Greyni:BAAANQABCgEIAQAAAA==.',
Gu='Gutz:BAAANQADCgMIAwAAAA==.',
Ha='Hadorya:BAAANQAECgIIAgAAAA==.Hakibalboa:BAABNQAECn9SAAIfAAoKQQ42CwCIAQAfAAoKQQ42CwCIAQAAAA==.Hakitua:BAAANQADCgYIBgAAAA==.Harick:BAAANQADCgQIBAAAAA==.Hazard:BAABNQAECn8xAAIOAAoKhhCrDwCvAQAOAAoKhhCrDwCvAQAAAA==.',
He='Heis:BAAANQAECgEIAQAAAA==.Hellboii:BAAANQAECgcIDgAAAA==.Heyitsrat:BAABNQAECn82AAIDAAoK4g0ohADEAQADAAoK4g0ohADEAQAAAA==.',
Ho='Hollowtips:BAAANQADCggIEwAAAA==.Holo:BAABNQAECn83AAMGAAoKrSQjGQAyAwAGAAkK+iQjGQAyAwAFAAoKPA4ldQCsAQAAAA==.Holyangus:BAAANQAECgYIEQAAAA==.Holyboga:BAAANQADCgIIAgAAAA==.Housemom:BAABNQAECn8cAAMDAAkKhAhM3wAeAQADAAgKuQhM3wAeAQAEAAQKJAZCRACWAAAAAA==.',
Hu='Huntem:BAAANQADCgMIAgAAAA==.Huuginn:BAAANQADCggICgAAAA==.',
Ib='Ibbert:BAAANQADCggINAAAAA==.',
Ic='Icculus:BAAANQAECgIIAwAAAA==.',
Il='Illadai:BAAANQADCggIEAAAAA==.Illyden:BAAANQABCgQIBAAAAA==.',
Im='Imamunch:BAAANQAECgEIAQABNQAECgIIAgAVAAAAAA==.Imaresmashy:BAAANQADCgIIAgABNQAECgcICwAVAAAAAA==.Iminyou:BAABNQAECn8sAAMGAAoKjhKTYAAAAgAGAAoKjhKTYAAAAgAFAAEK+QrS+gAyAAAAAA==.Impasse:BAAANQAECggIEAAAAA==.',
Io='Iolz:BAAANQABCgQIBgABNQAECgoKOgASAOgcAA==.',
Ja='Jaenei:BAAANQAECgMIBAAAAA==.Janet:BAAANQAECgYIBgABNQAECgoKMgAJADglAA==.',
Je='Jeeb:BAABNQAECn82AAITAAkKhg7eiQCTAQATAAkKhg7eiQCTAQAAAA==.',
Ji='Jinxta:BAABNQAECn8uAAINAAoKjRwGBQDQAgANAAoKjRwGBQDQAgAAAA==.',
Jo='Joansnow:BAABNQAECn8dAAIZAAoKuwnbQwCKAQAZAAoKuwnbQwCKAQAAAA==.Joeeo:BAABNQAECn9CAAMJAAoKgx55KgC/AgAJAAoKgx55KgC/AgAKAAcKigjlPgA2AQAAAA==.',
Ju='July:BAAANQAECgMIBAAAAA==.Julytonidas:BAABNQAECn8+AAITAAoKERy5KACcAgATAAoKERy5KACcAgAAAA==.Jurac:BAAANQADCggIHwAAAA==.',
Ka='Kaimargonar:BAABNQAECn8kAAINAAkKXw9TBwBeAQANAAkKXw9TBwBeAQAAAA==.Kaitoi:BAABNQAECn8jAAIWAAkKuxlKDAAOAgAWAAkKuxlKDAAOAgAAAA==.Kamakizeg:BAABNQAECn8vAAIDAAoK1g6ThADDAQADAAoK1g6ThADDAQAAAA==.Kamayla:BAAANQADCgYIBgAAAA==.Kateria:BAAANQAECggIDAABNQAECgoKSgAMAGQiAA==.Katimalice:BAAANQADCgQIDQAAAA==.',
Ke='Keathry:BAAANQAECgEIAQAAAA==.Keyzeus:BAAANQAECgIIAwAAAA==.',
Kh='Khas:BAAANQADCgYIEgAAAA==.Khui:BAACNQAFFH8OAAIYAAYKbiQNBAClAQAYAAYKbiQNBAClAQA1AAQKfzIAAxgACgrHI7IEAFoDABgACgrHI7IEAFoDACAABQqUHQk1AG0BAAAA.',
Ki='Killatu:BAAANQABCggIDQAAAA==.Killerdeath:BAAANQAECgUIBQAAAA==.',
Kn='Knìghtmàrè:BAACNQAFFH8OAAMMAAcK0A02BQAdAQAMAAYKtQw2BQAdAQALAAMKhRRxHwCPAAA1AAQKfzIAAwwACgqzIxYUABgDAAwACgqzIxYUABgDAAsABwpzHuw0ADgCAAAA.',
Ko='Koltharaz:BAACNQAFFH8GAAIhAAIK4h8TCgDAAAAhAAIK4h8TCgDAAAA1AAQKfzIAAiEACgrHG6cJANYCACEACgrHG6cJANYCAAAA.Korloff:BAAANQADCggIEwABNQAECgIIAwAVAAAAAQ==.Kozan:BAAANQAECgIIAwAAAQ==.',
Kr='Krazsz:BAAANQADCgQIBAAAAA==.Krazykraw:BAAANQAECgIIBQAAAA==.Krazylock:BAAANQAECgQICQAAAA==.Krokk:BAAANQABCgUIBQAAAA==.',
Ku='Kuiy:BAAANQADCgIIAgAAAA==.Kumah:BAAANQABCgEIAQAAAA==.Kungfuupanda:BAAANQAECgcIEwAAAA==.',
Ky='Kylar:BAAANQAECgQIBgAAAA==.',
La='Lateralus:BAABNQAECn8eAAIMAAgKsSIsMABvAgAMAAgKsSIsMABvAgABNQAECgoKIAAiAGsZAA==.Latt:BAABNQAECn8gAAQiAAoKaxm/GACIAQAiAAYKdBi/GACIAQAFAAkKFw/BbABuAQAGAAIK3xhsAwGIAAAAAA==.Lawluss:BAABNQAECn8iAAIQAAkKTBTRgQC2AQAQAAkKTBTRgQC2AQAAAA==.Layonface:BAAANQAECgQIDAAAAA==.',
Le='Legacyshot:BAAANQAECgcICwAAAQ==.Lelwani:BAAANQADCgEIAQAAAA==.',
Li='Lickthecrit:BAAANQAECgMIBQAAAA==.Lightguard:BAAANQADCggICgAAAA==.Lighthouse:BAABNQAECn9DAAMRAAoK+hfZSgA9AgARAAkK8xbZSgA9AgADAAkKIwzQowCGAQAAAA==.Lightload:BAAANQAECgYIEgAAAA==.Lileth:BAAANQAECgIIAwAAAA==.',
Lo='Lolhahabaha:BAAANQAECgUIDgAAAA==.Lonê:BAAANQAECgIIAgAAAA==.Loopie:BAAANQAECggIEwAAAA==.Lorax:BAAANQAECgYICAAAAA==.',
Lu='Luckÿ:BAAANQAECgEJAQAAAA==.Luminah:BAAANQABCgIIAQAAAA==.',
Ly='Lypally:BAABNQAECn9DAAIDAAoK2QbavABZAQADAAoK2QbavABZAQAAAA==.',
['Lï']='Lïllïth:BAABNQAECn8kAAIQAAkKJwdywQB/AQAQAAkKJwdywQB/AQAAAA==.Lïly:BAAANQAECgUIBwABNQAECgcICwAVAAAAAA==.',
['Ló']='Lóla:BAABNQAECn8rAAIcAAgKvB4dEwDRAgAcAAgKvB4dEwDRAgAAAA==.',
['Lü']='Lüvine:BAAANQAECggICAAAAA==.',
Ma='Madeah:BAACNQAFFH8gAAIPAAgKfhSLAgBcAgAPAAgKfhSLAgBcAgA1AAQKfyAAAw8ACQoDJLMCACYDAA8ACQoDJLMCACYDAB4ACApcCrMpAHcBAAAA.Madforge:BAABNQAECn9GAAMFAAoKGRkGJQCeAgAFAAoKGRkGJQCeAgAGAAYKZhNoWQB7AQAAAA==.Magegrizz:BAAANQAECgYIDgAAAA==.Magnyson:BAAANQAECggIDAAAAA==.Mahimahi:BAAANQADCgYICgAAAA==.Manahole:BAABNQAECn9GAAITAAoKfCJ9EgACAwATAAoKfCJ9EgACAwAAAA==.Mariacuras:BAABNQAECn8nAAIRAAkKHhIySADyAQARAAkKHhIySADyAQAAAA==.Marijwana:BAABNQAECn8UAAIEAAcK7BayKwB/AQAEAAcK7BayKwB/AQAAAA==.Marynne:BAABNQAECn9EAAIHAAkKyg4SJwC5AQAHAAkKyg4SJwC5AQAAAA==.Massaker:BAAANQADCggICgAAAA==.Mazuko:BAABNQAECn8tAAIjAAoKThn1LwAoAgAjAAoKThn1LwAoAgAAAA==.',
Mc='Mctank:BAAANQAECgEIAQAAAA==.',
Me='Mecandry:BAABNQAECn9MAAIQAAkKYRP9ZQBIAgAQAAkKYRP9ZQBIAgAAAA==.Mecks:BAAANQADCggILAAAAA==.Meepe:BAAANQADCgcIDQAAAA==.Melivant:BAABNQAECn8wAAQDAAoK9hBAlwCeAQADAAoKXgtAlwCeAQAEAAYKVRMTMwBKAQARAAUKeQ91mAD0AAAAAA==.Meranda:BAABNQAECn8hAAITAAoKOxWHqAAxAgATAAoKOxWHqAAxAgAAAA==.Merrikfang:BAAANQADCgcIBwAAAA==.Merriklade:BAABNQAECn87AAQOAAoK1Q53DwCFAQAOAAkK3Q93DwCFAQASAAcK7wWL1QBFAQAUAAIKrwcrOwBTAAAAAA==.Merrikoid:BAABNQAECn8hAAMbAAgKCg5BHQDrAAAbAAcKGw9BHQDrAAAcAAYKGwZsOwDFAAAAAA==.Merrikwolf:BAAANQADCggIDgAAAA==.',
Mi='Mico:BAAANQAECgQIEAAAAA==.Missyjelliot:BAAANQAECgYICQAAAA==.',
Mo='Mokkii:BAAANQADCgEIAQAAAA==.Morbidstyle:BAAANQAECgYIDQABNQAECgoKOQAGAFMUAA==.Morgoth:BAABNQAECn88AAICAAoKahdsUwBbAgACAAoKahdsUwBbAgAAAA==.Morthos:BAAANQADCgcICgAAAA==.Mosry:BAABNQAECn87AAILAAoKKB4jHADNAgALAAoKKB4jHADNAgABNQABCgQIBgAVAAAAAA==.Mourneblood:BAAANQADCgUIBQAAAA==.',
My='Myora:BAEANQADCgcICQABNQAECgoKJgAEAJESAA==.Mythundirus:BAABNQAECn8oAAIcAAoKrwOvOgDLAAAcAAoKrwOvOgDLAAAAAA==.',
['Mà']='Màrli:BAABNQAECn87AAILAAoKVxhLIQDxAQALAAoKVxhLIQDxAQAAAA==.',
['Mâ']='Mâgs:BAABNQAECn8vAAIEAAoKsAxqIwBTAQAEAAoKsAxqIwBTAQAAAA==.',
Na='Nakasid:BAABNQAECn9JAAMJAAoKshkpKACuAgAJAAoKshkpKACuAgAKAAUKBgcBUADSAAAAAA==.Nashoba:BAAANQADCgYJCwAAAA==.Natooka:BAAANQADCgUIBQAAAA==.',
Ne='Nein:BAAANQAECgQIDwAAAA==.Neins:BAAANQADCgYIEAABNQAECgQIDwAVAAAAAA==.Nevaehstar:BAABNQAECn9SAAITAAoKNhMKUgAbAgATAAoKNhMKUgAbAgAAAA==.',
Ni='Nibuto:BAABNQAECn8aAAIiAAgKQQfFIgAGAQAiAAgKQQfFIgAGAQAAAA==.Nijun:BAEBNQAECn80AAIJAAoKpA+dTQACAgAJAAoKpA+dTQACAgAAAA==.Nik:BAABNQAECn8bAAMFAAkK9Q17ZwB/AQAFAAkK9Q17ZwB/AQAGAAEKAAA9XgEbAAAAAA==.Nikita:BAAANQAECgUIBAAAAA==.Nikolia:BAABNQAECn8ZAAQUAAcKtggfKgDpAAAUAAUK7AwfKgDpAAAOAAQKegRwKwBYAAASAAQK8QHrIAFBAAAAAA==.Ninetynine:BAAANQADCgQIBAAAAA==.Nini:BAABNQAECn8VAAIIAAcKEAJtjwCZAAAIAAcKEAJtjwCZAAAAAA==.Ninx:BAAANQADCgUICQAAAA==.',
No='Noivana:BAAANQABCgEIAQABNQAFFAcIEgAjAM4YAA==.',
Ny='Nystel:BAAANQADCgEIAQAAAA==.',
Ol='Ollichi:BAAANQADCgIIAgAAAA==.',
Or='Ornn:BAAANQAECgcICwABNQAECgoKLgABABwjAA==.',
Os='Osoroshi:BAAANQADCgYJBgABNQAECgkJTAAQAGETAA==.',
Ov='Overtime:BAAANQADCggIEQAAAA==.',
Pa='Padmê:BAAANQADCgMIAwAAAA==.Paladrak:BAAANQADCgIIAgAAAA==.Pandamared:BAAANQADCggIFwAAAA==.Patronous:BAAANQADCgYIDAAAAA==.',
Ph='Phenol:BAAANQADCgEIAQAAAA==.',
Po='Polog:BAAANQAECgIIAgABNQAECgoKKwATAL0iAA==.Porkchoplust:BAAANQAECgEIAQAAAA==.Porkribs:BAABNQAECn8bAAIRAAgKkRqKRQBQAgARAAgKkRqKRQBQAgAAAA==.',
Pr='Pranks:BAAANQAECgQIDQAAAA==.Premalone:BAAANQADCgUIDgAAAA==.',
Pu='Puca:BAAANQAECgEIAQAAAA==.Puchõ:BAAANQAECgIIAgAAAA==.Pumdmuc:BAABNQAECn8fAAMJAAkKwRzCJwCwAgAJAAkKwRzCJwCwAgAKAAEKCgjbYgA2AAAAAA==.Punchymcheal:BAAANQAECggIDgABNQAECgoKOwAJAPMaAA==.',
Qu='Quikfix:BAAANQAECgIIAgAAAA==.Quikglaives:BAAANQAECgIIAwAAAA==.Quille:BAABNQAECn8wAAIQAAoKNh+4JACsAgAQAAoKNh+4JACsAgAAAA==.',
Ra='Ragretts:BAAANQAECgEIAQAAAA==.Rahhem:BAAANQADCgYIBgAAAA==.Ranmo:BAABNQAECn8WAAMLAAgKHx6/SwDHAQALAAcKAyO/SwDHAQAMAAIKqwX5AgETAAAAAA==.Ratkol:BAAANQABCgIIAgAAAA==.Raysdknight:BAAANQADCgIJBwAAAA==.',
Re='Recbra:BAAANQAECgYIBgAAAA==.Redrek:BAAANQADCggIOwAAAA==.Redsbank:BAAANQADCgUIBQAAAA==.Redshunter:BAAANQADCggIMQAAAA==.Redsknight:BAAANQADCgYIBwAAAA==.Redsmonk:BAAANQADCggIEQAAAA==.Redwinter:BAABNQAECn8vAAMLAAkKZCCNLABlAgALAAkKZCCNLABlAgAZAAEKAADbzQAAAAAAAA==.Regnor:BAAANQADCgUIBQAAAA==.Reikisong:BAAANQAECgMIBgAAAA==.Reiluune:BAAANQADCgQIAwABNQAECggIKwAcALweAA==.Remmie:BAAANQADCgUIBwAAAA==.',
Rh='Rhagurion:BAABNQAECn8+AAIdAAoKdSa6AADtAwAdAAoKdSa6AADtAwAAAA==.',
Ri='Riqua:BAAANQAECgMIBQAAAA==.',
Ro='Rockmonsta:BAAANQADCgYJCgAAAA==.Rockys:BAAANQABCgQIBQAAAA==.Roxies:BAAANQAECgMIBgAAAA==.',
Rp='Rpg:BAABNQAECn8cAAITAAkKlRkjmQBOAgATAAkKlRkjmQBOAgAAAA==.',
Ru='Rumie:BAAANQADCgUIBQAAAA==.Runes:BAAANQAECgcIDwAAAA==.',
Sa='Saeti:BAABNQAECn9WAAUWAAoKdCQ8AgA5AwAWAAkKdCQ8AgA5AwAHAAcKIRQzJgDBAQAIAAYKnx71OQBJAQAdAAEKxB+XUwBWAAAAAA==.Sanare:BAAANQAECggICQABNQAECgoKOwAJAPMaAA==.Sanbit:BAAANQAECgUIDgAAAA==.Santhaenis:BAAANQAECgcIDQAAAA==.Sapplesauce:BAAANQAECgcIDgAAAA==.Saurfang:BAAANQADCgQIBQAAAA==.',
Se='Seethrowwar:BAABNQAECn8iAAMSAAkKuh6vOwDYAgASAAkKaB6vOwDYAgAUAAYKQRbiGwB9AQAAAA==.Senbit:BAAANQAECgUIDQAAAA==.Serenìty:BAAANQAECgYIDAAAAA==.Seresin:BAABNQAECn+BAAMHAAoKyRlfFQCbAgAHAAoKyRlfFQCbAgAIAAUKkwVbggDHAAAAAA==.',
Sh='Shadý:BAABNQAECn8lAAIQAAkKiQUu5AA4AQAQAAkKiQUu5AA4AQAAAA==.Shamanoodles:BAAANQADCggIFAABNQAECgoKKwATAL0iAA==.Shortwarrior:BAABNQAECn8zAAIOAAoKXRF2CwDUAQAOAAoKXRF2CwDUAQAAAA==.',
Si='Sianu:BAABNQAECn8ZAAIFAAcKYxibSADxAQAFAAcKYxibSADxAQABNQAECgkJRAAHAMoOAA==.Sidraya:BAABNQAECn8iAAMXAAcKDRL2FwA6AQAXAAcKDRL2FwA6AQATAAIKRAfvLgFqAAAAAA==.Silent:BAABNQAECn86AAISAAoK6BzgJgClAgASAAoK6BzgJgClAgAAAA==.Silverserqet:BAABNQAECn8jAAIQAAkK5An4pQBnAQAQAAkK5An4pQBnAQAAAA==.',
Sl='Slipknaught:BAAANQABCgQIBQABNQAECgoKHQAZALsJAA==.',
Sm='Smileyriley:BAAANQADCgUIBQAAAA==.',
Sn='Sneakylinks:BAAANQADCgIIAgABNQAECgkJHAATAJUZAA==.',
So='Sonbit:BAAANQAECgYIDgAAAA==.Sonichero:BAAANQAECgQIBAAAAA==.Sooki:BAAANQAECgMIBQAAAA==.Sophie:BAAANQAECgQIDgAAAA==.Soulber:BAAANQAECgMIBAAAAA==.',
Sp='Spunky:BAAANQAECgQIBAAAAA==.',
Ss='Ssenbit:BAAANQAECgQICgAAAA==.Ssonbit:BAAANQADCggIEQAAAA==.Ssunbit:BAAANQADCgEIAQAAAA==.',
St='Stefeana:BAAANQADCgYIBgAAAA==.Sternhoof:BAAANQABCgMIBQAAAA==.Stigma:BAAANQADCggIFQABNQAECgoKOgAJAEMiAA==.Stylos:BAABNQAECn8zAAIiAAoKYxBzEQD/AQAiAAoKYxBzEQD/AQAAAA==.',
Su='Summersong:BAAANQADCgQIBAAAAA==.Sumofwhy:BAAANQADCgcIBwAAAA==.',
Sw='Swarli:BAAANQAECgIIAgAAAA==.Swowtitbang:BAAANQAECgYIEAAAAA==.',
Sy='Sylven:BAAANQAECgUIBwABNQAECgoKOAAGAIUgAA==.',
Te='Techno:BAABNQAECn8UAAMcAAkKUgLJUABIAAAcAAcKNALJUABIAAAjAAkKcwFIhAA1AAAAAA==.Tegbolt:BAABNQAECn8dAAMGAAgKeRXAZgDsAQAGAAgKghPAZgDsAQAiAAcKLhLWGwCmAQAAAA==.Teghorn:BAAANQAECggICAABNQAECggIHQAGAHkVAA==.Tekko:BAABNQAECn9HAAMdAAoKWB75CACyAgAdAAoKWB75CACyAgAWAAEKOQX8UAAQAAAAAA==.Tempestrike:BAABNQAECn8vAAIcAAoKehuRDwD3AgAcAAoKehuRDwD3AgAAAA==.',
Th='Theholymatt:BAABNQAECn9MAAMRAAoKdiREEgA9AwARAAoKdiREEgA9AwADAAYK9A9l1AAwAQAAAA==.Thendari:BAABNQAECn9YAAINAAoKdA66BQCVAQANAAoKdA66BQCVAQAAAA==.Theodus:BAABNQAECn8vAAITAAoKOhK2twAUAgATAAoKOhK2twAUAgAAAA==.Therayen:BAAANQADCgYJCwAAAA==.Thomeriddle:BAAANQABCgMIAQAAAA==.Thorrune:BAAANQAECgMIAwAAAA==.',
Ti='Tiferis:BAACNQAFFH8IAAIRAAUKqBT9EQAhAQARAAUKqBT9EQAhAQA1AAQKf0EAAhEACgqfIM4NAFYDABEACgqfIM4NAFYDAAAA.Tigerclawss:BAAANQADCggINgAAAA==.Tislam:BAAANQAECgMIBAAAAA==.',
To='Tobiquer:BAABNQAECn9JAAIJAAoKNiLJCwCFAwAJAAoKNiLJCwCFAwAAAA==.Tojarmar:BAAANQADCgQIBAABNQAECgMIAwAVAAAAAA==.Torolf:BAAANQAECgMIBQAAAA==.',
Tq='Tqco:BAAANQADCgMIAwABNQAECgoKRwAdAFgeAA==.',
Tr='Traydra:BAAANQADCgUIBwAAAA==.Trinbug:BAAANQADCgEIAQAAAA==.Troglodyte:BAABNQAECn9XAAIGAAoKniTsBgBGAwAGAAoKniTsBgBGAwAAAA==.',
Ts='Tsonokwabain:BAABNQAECn8qAAIZAAoKqBsDKQATAgAZAAoKqBsDKQATAgAAAA==.Tsunami:BAAANQADCgMIAwAAAA==.',
Tw='Twistdog:BAAANQABCgQIBgAAAA==.',
Ty='Tye:BAABNQAECn8iAAIQAAoKohekUwB2AgAQAAoKohekUwB2AgAAAA==.Tyranastrasz:BAABNQAECn89AAQhAAoK1QZVHgBtAQAhAAkKsQVVHgBtAQAkAAoKmwXEGgBLAQAlAAEKTQCNKQANAAAAAA==.Tyye:BAABNQAECn8qAAIOAAcK+iIrCAAoAgAOAAcK+iIrCAAoAgAAAA==.',
['Tâ']='Tâjik:BAABNQAECn8jAAIeAAoKtATKKQB2AQAeAAoKtATKKQB2AQAAAA==.',
Ul='Ulquiorra:BAACNQAFFH8MAAMcAAYKzA1sDQDUAAAcAAUKzA1sDQDUAAAbAAIKQAiPBwBCAAA1AAQKfzcAAxwACgoVIQ0QAPICABwACQoVIQ0QAPICABsABAoIDe8gAL0AAAAA.',
Ur='Uraja:BAAANQABCgIIAgAAAA==.',
Ut='Uthers:BAAANQADCgYIAgAAAA==.',
Va='Vaethund:BAAANQAECgMIBAAAAA==.Valdred:BAAANQAECgYIBgABNQAFFAcIEgAjAM4YAA==.Valgavoth:BAABNQAECn8VAAILAAkK4Bf/NwApAgALAAkK4Bf/NwApAgAAAA==.Vangar:BAAANQADCgQIBAAAAA==.Vanthion:BAAANQADCggICgAAAA==.',
Ve='Velara:BAAANQAECgQIBQAAAA==.Velinna:BAAANQADCgUIBwABNQAECgEIAQAVAAAAAA==.Venekor:BAAANQADCgIIAgAAAA==.',
Vi='Viriex:BAAANQADCgIIAgAAAA==.Vitoria:BAAANQAECgQIBgAAAA==.',
Vo='Voidlighter:BAABNQAECn87AAIJAAoK8xo1JADcAgAJAAoK8xo1JADcAgAAAA==.Volundr:BAABNQAECn8wAAIUAAoKqBkeDgBNAgAUAAoKqBkeDgBNAgAAAA==.Vonvaughan:BAAANQAECgQIAgAAAA==.',
Vy='Vynel:BAAANQAECgIIAgABNQAECgoKOAAGAIUgAA==.Vynirion:BAAANQAECgEIAQAAAA==.',
Wa='Wardellmo:BAAANQADCgQIBAAAAA==.Wargtar:BAABNQAECn8bAAIPAAcKCBnbMwAMAgAPAAcKCBnbMwAMAgAAAA==.Warriorskull:BAAANQADCgYICAAAAA==.',
We='Weabe:BAAANQAECgIIAwAAAA==.',
Wh='Whiterrina:BAAANQADCgIIAgAAAA==.Whitespring:BAAANQAECgYIEAABNQAECgkJLwALAGQgAA==.',
Wo='Wolfgarou:BAAANQABCgIIAgAAAA==.',
Wy='Wyrdo:BAAANQADCgYIBgAAAA==.',
['Wù']='Wùsthof:BAABNQAECn8fAAIQAAkKYApKiQD4AQAQAAkKYApKiQD4AQAAAA==.',
Xa='Xandrios:BAAANQAECgEJAQAAAA==.',
Xi='Xiae:BAABNQAECn8xAAMGAAoK4BbzTABDAgAGAAkKQhfzTABDAgAFAAQKCxAvowDXAAAAAA==.',
Ya='Yasuke:BAAANQADCgUJBQAAAA==.',
Ye='Yet:BAAANQAECgEIAQABNQAECgoKLgATACYjAA==.',
Yi='Yiffweaver:BAAANQAECgEIAQAAAA==.',
Yo='Yokochan:BAAANQABCgIIAgAAAA==.Yokoriazen:BAABNQAECn87AAIDAAoKfxUMYQB2AgADAAoKfxUMYQB2AgAAAA==.',
Za='Zakaradin:BAAANQADCgcICAABNQAECgIIAwAVAAAAAA==.Zandigor:BAAANQAECgEIAQAAAA==.Zaraeliana:BAAANQAECgMIBAAAAA==.Zarastraza:BAABNQAECn8kAAMkAAkKFhFxIgC3AQAkAAkKFhFxIgC3AQAhAAUKFQt0JQAPAQAAAA==.',
Ze='Zephnor:BAABNQAECn8kAAMdAAkKOw9lJABzAQAdAAcK/xBlJABzAQAIAAkKTArTYgBDAQAAAA==.',
Zh='Zhao:BAAANQADCgYIBgAAAA==.',
Zm='Zmona:BAAANQAECgQIBAAAAA==.',
Zo='Zorsche:BAAANQAECgEIAQAAAA==.',
Zu='Zulrok:BAABNQAECn8zAAISAAoKOBPwVAD/AQASAAoKOBPwVAD/AQAAAA==.',
['Áb']='Ábsurd:BAAANQAECggICgABNQABCgIIAQAVAAAAAA==.',
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
