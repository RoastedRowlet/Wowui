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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Druid-Balance','Priest-Holy','Priest-Shadow','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Destruction','Warrior-Fury','Unknown-Unknown','Rogue-Assassination','Hunter-BeastMastery','Paladin-Holy','Warrior-Arms','Mage-Arcane','Warrior-Protection','Druid-Feral','Mage-Frost','Monk-Mistweaver','DeathKnight-Frost','Mage-Fire','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian','Rogue-Subtlety','Monk-Brewmaster','Monk-Windwalker','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Havoc','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Absol:BAABNQAECn8uAAMBAAoKHCOkAACaAwABAAoKwCKkAACaAwACAAoKjB73PQCZAgAAAA==.',
Ac='Achilles:BAABNQAECn83AAMDAAoK8xKRmADyAQADAAoK9A+RmADyAQAEAAUKVBNOMgDaAAAAAA==.',
Ad='Adenox:BAAANQAECgMIBAAAAA==.',
Ae='Aeon:BAAANQAECgQICAAAAA==.Aerís:BAAANQAECgEIAQAAAA==.',
Ah='Ahsokatano:BAABNQAECn8rAAMFAAoKKhqwHQC4AgAFAAoKKhqwHQC4AgAGAAEKAACaPgEuAAAAAA==.',
Ai='Ailing:BAAANQADCgYIDAAAAA==.Aimspet:BAABNQAECn8vAAIFAAkKKBsdIQChAgAFAAkKKBsdIQChAgAAAA==.Airocket:BAAANQADCgMIAwAAAA==.',
Ak='Akasha:BAAANQABCgMIBwAAAA==.Akos:BAAANQAECgcIBgABNQAECgoKcwAHAKkZAA==.',
Al='Alukai:BAAANQAECgQIBgAAAA==.Alzaeryan:BAABNQAECn8aAAIIAAgKtBdwQwDmAQAIAAgKtBdwQwDmAQAAAA==.',
Am='Am:BAAANQAECgQIAwAAAA==.Amonet:BAAANQAECgEIAQAAAA==.',
An='Anaelcheese:BAAANQAECgQIBAAAAA==.Anamis:BAABNQAECn8sAAMJAAoKHBWXUwAoAgAJAAoKHBWXUwAoAgAKAAEKHwXcgQAoAAAAAA==.Angras:BAABNQAECn8dAAMLAAYKogsPiQDbAAALAAUKwwwPiQDbAAAMAAUK0gbLXgCBAAAAAA==.',
Ap='Aphalock:BAABNQAECn8xAAINAAoKiAgECAA7AQANAAoKiAgECAA7AQAAAA==.',
Ar='Aradial:BAAANQADCgEIAQAAAA==.Arane:BAAANQADCgcIBwAAAA==.Ariûs:BAABNQAECn8aAAIOAAgKiQwdEwAsAQAOAAgKiQwdEwAsAQAAAA==.Arlin:BAAANQAECgEIAQABNQAECgEIAgAPAAAAAA==.Arlorian:BAABNQAECn9CAAIQAAoKyg9fDgDVAQAQAAoKyg9fDgDVAQAAAA==.Arrenn:BAAANQAECgUIEAAAAA==.Arrowsmites:BAABNQAECn8rAAIRAAoKthmuOwBQAgARAAoKthmuOwBQAgAAAA==.',
As='Askelad:BAABNQAECn8jAAIDAAgKmQcG4wACAQADAAgKmQcG4wACAQAAAA==.',
Au='Aubani:BAABNQAECn80AAMSAAoKAxhHKwBpAgASAAoKAxhHKwBpAgADAAcKoRA+6gBHAQAAAA==.',
Ax='Axelot:BAAANQAECgcIEAAAAA==.',
Ay='Ayperos:BAABNQAECn9CAAITAAoKZg9aVgDoAQATAAoKZg9aVgDoAQAAAA==.',
Ba='Bakedpally:BAABNQAECn8jAAIDAAgKegdP9wAvAQADAAgKegdP9wAvAQAAAA==.Bakedwarrior:BAAANQADCgIIAgAAAA==.Bandomar:BAAANQAECgIIBQAAAA==.Baniemo:BAAANQAECgUIBgAAAA==.Banigor:BAAANQAECgYIEQAAAA==.Bankaltanon:BAAANQAECgUICQAAAA==.Baragnis:BAAANQAECgUIBQAAAA==.',
Be='Beavur:BAABNQAECn8UAAIUAAYKXQreKgFEAQAUAAYKXQreKgFEAQAAAA==.Beck:BAABNQAECn8wAAIDAAgKziGjPABmAgADAAgKziGjPABmAgAAAA==.Beggars:BAAANQAECgUIDQAAAA==.Bereth:BAAANQAECgEIAQAAAA==.Berreydingle:BAAANQADCggJFwAAAA==.',
Bi='Bigboii:BAAANQAECgEIAQAAAA==.Bigkitty:BAAANQAECgIIAgABNQAECgoKIQAUADsVAA==.Bigntall:BAAANQAECgIIAgAAAA==.Bikinibrenda:BAAANQAECgUIEAAAAA==.',
Bl='Blackhuuf:BAAANQADCgUIBQAAAA==.Blitzedbust:BAAANQAECgEIAQAAAA==.Bloodmender:BAAANQADCgYIBwABNQAECgoKKwAUAL0iAA==.Bluesummer:BAABNQAECn8WAAMTAAgKjRT8hABmAQATAAcKjRT8hABmAQAVAAIKaBNJPgBJAAABNQAECgkJKwALAGMgAA==.',
Bo='Bobeh:BAAANQAECgEIAgABNQADCgEIAQAPAAAAAA==.Bolts:BAAANQAECgEIBAAAAA==.Bonzai:BAAANQAECgcICwABNQAECgoKLgABABwjAA==.Boomskittles:BAAANQABCgMIAwAAAA==.Borat:BAABNQAECn8uAAIUAAoKJiPOCQCxAwAUAAoKJiPOCQCxAwAAAA==.Borsam:BAAANQABCgcICQAAAA==.',
Br='Brendameeks:BAAANQADCgQIBAAAAA==.Broadzinatl:BAAANQAECgIIBAABNQAECgQIBAAPAAAAAA==.Brom:BAAANQAECgQIBwAAAA==.Brutesse:BAAANQAECgQIDgAAAA==.Bròly:BAAANQADCgMIAwAAAA==.',
Bu='Buttercups:BAAANQAECgQIBAAAAA==.',
['Bè']='Bètflèch:BAAANQAECgMIBAAAAA==.',
['Bø']='Bøss:BAAANQADCggIGQAAAA==.',
Ca='Cad:BAAANQADCgYIEAAAAA==.Calytrix:BAEBNQAECn8uAAQIAAoKRRPxOgAcAgAIAAoKRRPxOgAcAgAHAAIKQBPMXQBqAAAWAAEKXxG4QAA5AAAAAA==.Captnhammer:BAAANQADCgEIAQAAAA==.Carnelian:BAAANQAECgEIAQAAAA==.Castration:BAAANQADCgYICQAAAA==.',
Ce='Ceylan:BAABNQAECn8sAAIXAAoKMBxPBgBSAgAXAAoKMBxPBgBSAgAAAA==.',
Ch='Chaleb:BAAANQAECgEIAQAAAA==.Charlz:BAABNQAECn8kAAMJAAoKlRpkFgASAwAJAAoKlRpkFgASAwAKAAUKUA5qPACsAAAAAA==.Charsifood:BAAANQAECgcIDgAAAA==.Chat:BAABNQAECn8XAAIYAAgKaiYbAwCEAwAYAAgKaiYbAwCEAwAAAA==.Cheatpriest:BAABNQAECn85AAIJAAoK+ROaVgDLAQAJAAoK+ROaVgDLAQAAAA==.Cheatwl:BAAANQADCgIIAgAAAA==.Chepis:BAAANQADCgcJEAAAAA==.Chesthyr:BAAANQADCgcIDgAAAA==.Chestoe:BAAANQAECgUIEQAAAA==.Chitchatted:BAAANQADCgIIAgAAAA==.',
Ci='Cindrethresh:BAAANQADCgMIAwAAAA==.',
Co='Cognition:BAABNQAECn9KAAIRAAoKGCSZDQAaAwARAAoKGCSZDQAaAwAAAA==.Coldvengance:BAABNQAECn8mAAIOAAoKrQhtEwBpAQAOAAoKrQhtEwBpAQAAAA==.Cortisol:BAAANQAECggICQAAAA==.',
Cr='Cranknstein:BAAANQADCggJCAABNQADCggIEQAPAAAAAA==.Crazh:BAAANQAECgIIAwAAAA==.Crazycalla:BAAANQAECgQICAAAAA==.Croven:BAAANQADCgUIBQAAAA==.Crànk:BAAANQAECgcIAgABNQADCggIEQAPAAAAAA==.',
Cu='Cuensour:BAAANQADCgcJDQAAAA==.Cutemenace:BAAANQADCgIIAgABNQAECgkJHAAEAJ0gAA==.',
Cy='Cymindel:BAABNQAECn8+AAILAAoKPRiXFwA6AgALAAoKPRiXFwA6AgAAAA==.Cyphr:BAAANQAECgYICgAAAA==.',
Da='Dakotà:BAABNQAECn8tAAIRAAoKTBIyVAANAgARAAoKTBIyVAANAgAAAA==.Darc:BAAANQAECggIDgAAAA==.Daredayo:BAAANQADCgIIAgAAAA==.Darkangelz:BAAANQAECgUIBQAAAA==.Darklorising:BAAANQAECgIIAgAAAA==.Darktroll:BAAANQAECgUIBQAAAA==.Darkwave:BAAANQAECggICgAAAA==.',
De='Dejno:BAABNQAECn8WAAMOAAcKlSD7CQAxAgAOAAYKxCL7CQAxAgATAAIK/BTGKAGFAAAAAA==.Deleted:BAAANQADCgUIBQABNQAECgoKKwAUAL0iAA==.Demonred:BAAANQADCgQIBAAAAA==.Derpla:BAAANQAECgEIAQABNQAECgoKHQAZALsJAA==.Dethra:BAAANQAECgQIEwAAAA==.Dezign:BAACNQAFFH8gAAMXAAgKAx0uAQB7AQAXAAQKpSMuAQB7AQAUAAcKNRrcEABUAQA1AAQKf1oABBcACgqNJlEAANwDABcACQpzJlEAANwDABQACgqbJd0JADEDABoAAwoSIHkGALYAAAAA.',
Do='Dolgorukov:BAABNQAECn8uAAIRAAoKLQ+aWwD6AQARAAoKLQ+aWwD6AQAAAA==.Dologony:BAABNQAECn8bAAIHAAoKmwreKACMAQAHAAoKmwreKACMAQAAAA==.Doran:BAAANQAECgEIAQAAAA==.Dorgar:BAAANQADCgcIDQAAAA==.',
Dr='Draccosa:BAAANQADCgIIAgAAAA==.Dracigor:BAAANQAECgQIBQAAAA==.Dragonmage:BAAANQAECgYICwAAAA==.Drakhan:BAAANQAECgUIBgAAAA==.Drakma:BAAANQAECgMIBgAAAA==.Drastio:BAAANQADCgMIAwAAAA==.Drikken:BAABNQAECn9NAAMbAAoKjRmSCwAVAgAbAAoKjRmSCwAVAgAcAAoKCxGLGADcAQAAAA==.Drmaker:BAAANQAECgUIBwAAAA==.Druj:BAEANQADCggIDAABNQAECgoKLgAIAEUTAA==.',
Du='Durasan:BAAANQADCgMIAwAAAA==.Duressa:BAAANQAECgUIBAAAAA==.',
['Dö']='Dötdötdead:BAABNQAECn8YAAMCAAgK+A2IgwBDAQACAAgK+A2IgwBDAQANAAEKAABphgAiAAAAAA==.',
Ef='Effindin:BAAANQADCgYIBgAAAA==.Effinsick:BAAANQAECgQIBgAAAA==.',
Ei='Eins:BAAANQADCggICAABNQAECgQIDwAPAAAAAA==.Eisheth:BAAANQAECgIIAwAAAA==.',
El='Elerav:BAAANQAECgQIBwAAAA==.Ellysiaa:BAAANQADCggIJwAAAA==.',
Em='Emmakyn:BAABNQAECn8lAAMIAAoKyxBlQgDtAQAIAAoKyxBlQgDtAQAdAAEK3BamXAA8AAAAAA==.Emriss:BAABNQAECn83AAIZAAoK2QoWOACpAQAZAAoK2QoWOACpAQAAAA==.',
En='Endjinns:BAAANQADCggICAAAAA==.Enyxea:BAAANQAECgMIBQAAAA==.',
Es='Esman:BAAANQADCgMIAwAAAA==.',
Ey='Eyedontknow:BAABNQAECn8mAAIEAAkKXRqzFADJAQAEAAkKXRqzFADJAQAAAA==.',
Ez='Ezzka:BAABNQAECn9GAAMMAAoKBCLBCADhAgAMAAoKBCLBCADhAgALAAIKxhsUqgB8AAAAAA==.',
Fa='Faceless:BAAANQAECgYIBQAAAA==.Failroots:BAAANQAECgIIAgAAAA==.False:BAAANQAECgUIDAAAAA==.Farnsworth:BAABNQAECn8mAAMNAAoKSxmADADmAAACAAoKbBU9RQDzAQANAAMK7hmADADmAAAAAA==.Farzix:BAABNQAECn8UAAIGAAcK4AZguwAbAQAGAAcK4AZguwAbAQAAAA==.Fatherdrew:BAABNQAECn8xAAMJAAoKICKZCwB4AwAJAAoKICKZCwB4AwAKAAIKkwcDYwArAAAAAA==.Façade:BAABNQAECn8hAAMZAAoKnxKNNwD4AQAZAAkKQBSNNwD4AQAMAAcKrw9TbQBeAQAAAA==.',
Fe='Fefifabrizio:BAAANQAECgEIAQAAAA==.Felix:BAAANQAECgQIEgAAAA==.Felraena:BAAANQADCgIIAgAAAA==.',
Fi='Finnagas:BAAANQAECgEJAgAAAA==.Finnw:BAAANQABCgcJCgAAAA==.Firelite:BAABNQAECn8lAAMGAAgKWAmAcgAcAQAGAAgKWAmAcgAcAQAFAAEKkwEyMgEeAAAAAA==.',
Fl='Flairadin:BAABNQAECn8nAAISAAoKMRisPQBuAgASAAoKMRisPQBuAgAAAA==.Flee:BAABNQAECn8fAAMeAAoKvBG3NgALAgAeAAoKvBG3NgALAgAQAAEKyQb4pAAyAAAAAA==.Fleromars:BAAANQAECgUIBQABNQAECgoKHwAeALwRAA==.Flexo:BAAANQAECgQIBQABNQAECgoKJgANAEsZAA==.',
Fo='Fookmii:BAAANQADCgUIBgAAAA==.',
Fr='Frogfist:BAAANQAECgMIAwAAAA==.Frowdawn:BAABNQAECn8vAAIQAAgKvAtvHAA6AQAQAAgKvAtvHAA6AQAAAA==.',
Fy='Fyf:BAAANQAECggIAwABNQADCggIEQAPAAAAAA==.',
Ga='Gallea:BAAANQAECgIIAgAAAA==.Garbanzo:BAAANQAECgUICgAAAA==.Garythenpc:BAAANQAECgEIAQAAAA==.',
Ge='Genericeric:BAAANQAECgUICAAAAA==.Getsumei:BAEBNQAECn8gAAMEAAoKDxJFFQDBAQAEAAoKDxJFFQDBAQADAAQK+wm0IQGkAAABNQAECgoKLgAIAEUTAA==.',
Gi='Gidgett:BAAANQADCgcIFAAAAA==.Gilas:BAAANQADCgcIDwAAAA==.',
Gl='Glacialkitty:BAABNQAECn8sAAIHAAoKNghpLwBYAQAHAAoKNghpLwBYAQAAAA==.Glizzygoblin:BAAANQADCgQIBAAAAA==.',
Go='Gobibug:BAAANQADCgIJAgAAAA==.Googoobler:BAAANQAECgEIAwAAAA==.Goudalovin:BAAANQADCgQIBAABNQAECgoKIQAUADsVAA==.Goudanight:BAAANQADCgIIAgABNQAECgoKIQAUADsVAA==.Goudatime:BAABNQAECn8hAAILAAcKoAv+UADqAAALAAcKoAv+UADqAAABNQAECgoKIQAUADsVAA==.',
Gr='Greenknight:BAAANQADCggICQAAAA==.Greenmagus:BAAANQAECgEJAQAAAA==.Grenadon:BAAANQAECgEIAQAAAA==.Greyni:BAAANQABCgEIAQAAAA==.',
Gu='Gutz:BAAANQADCgMIAwAAAA==.',
Ha='Hadorya:BAAANQAECgIIAgAAAA==.Hakibalboa:BAABNQAECn9JAAIfAAoKDw34CgB2AQAfAAoKDw34CgB2AQAAAA==.Hakitua:BAAANQADCgYIBgAAAA==.Harick:BAAANQAECgEIAQAAAA==.Hazard:BAABNQAECn8tAAIOAAoKWhCrDwCvAQAOAAoKWhCrDwCvAQAAAA==.',
He='Heis:BAAANQAECgEIAgAAAA==.Hellboii:BAAANQAECgcIDgAAAA==.Heyitsrat:BAABNQAECn8vAAIDAAkKbAzgmACFAQADAAkKbAzgmACFAQAAAA==.',
Hi='Highhealzz:BAAANQADCgcIBwAAAA==.',
Ho='Hollowtips:BAAANQADCggIEwAAAA==.Holo:BAABNQAECn83AAMGAAoKrSQjGQAyAwAGAAkK+iQjGQAyAwAFAAoKPA4ldQCsAQAAAA==.Holyangus:BAAANQAECgYIEAAAAA==.Holyboga:BAAANQADCgIIAgAAAA==.Housemom:BAABNQAECn8bAAMDAAkK8gcX1QAaAQADAAgKDwgX1QAaAQAEAAQKJAYIQACWAAAAAA==.',
Hu='Huntem:BAAANQADCgMIAgAAAA==.Huuginn:BAAANQADCggICgAAAA==.',
Ib='Ibbert:BAAANQADCggILwAAAA==.',
Ic='Icculus:BAAANQAECgIIBQAAAA==.Iceticles:BAAANQAECgEIAgAAAA==.',
Il='Illadai:BAAANQADCggIEAAAAA==.Illyden:BAAANQABCgQIBAAAAA==.',
Im='Imamunch:BAAANQAECgEIAQABNQAECgIIAgAPAAAAAA==.Imaresmashy:BAAANQAECgEIAQABNQAECgcIDgAPAAAAAA==.Iminyou:BAABNQAECn8sAAMGAAoKjhKTYAAAAgAGAAoKjhKTYAAAAgAFAAEK+Qrs8QAyAAAAAA==.Impasse:BAAANQAECggIEAAAAA==.',
Io='Iolz:BAAANQAECgEIBQABNQAECgoKNwATAKMbAA==.',
Iw='Iwanaplay:BAAANQAECgEIAQAAAA==.',
Ja='Jaenei:BAAANQAECgMIBgAAAA==.Janet:BAAANQAECgYICAABNQAECgoKMgAJADglAA==.',
Je='Jeeb:BAABNQAECn8xAAIUAAgKHA8cpABKAQAUAAgKHA8cpABKAQAAAA==.',
Ji='Jinxta:BAABNQAECn8qAAINAAoKfRwGBQDQAgANAAoKfRwGBQDQAgAAAA==.',
Jo='Joansnow:BAABNQAECn8dAAIZAAoKuwnaPQCOAQAZAAoKuwnaPQCOAQAAAA==.Joeeo:BAABNQAECn9CAAMJAAoKgx5VJACwAgAJAAoKgx5VJACwAgAKAAcKigjlPgA2AQAAAA==.',
Ju='July:BAAANQAECgMIBQAAAA==.Julytonidas:BAABNQAECn81AAIUAAoKFhhlOwBPAgAUAAoKFhhlOwBPAgAAAA==.Jurac:BAAANQADCggIGgAAAA==.',
Ka='Kaimargonar:BAABNQAECn8kAAINAAkKXw9yBgBiAQANAAkKXw9yBgBiAQAAAA==.Kaitoi:BAABNQAECn8hAAIWAAcKFxzrEACYAQAWAAcKFxzrEACYAQAAAA==.Kamakizeg:BAABNQAECn8oAAIDAAkKiQ6FogBzAQADAAkKiQ6FogBzAQAAAA==.Kamayla:BAAANQADCgYIBgAAAA==.Kantharia:BAAANQAECgEIAwAAAA==.Kateria:BAAANQAECggIDgABNQAECgoKRgAMAAQiAA==.Katimalice:BAAANQADCgQIDQAAAA==.',
Ke='Keathry:BAAANQAECgEIAQAAAA==.Keyzeus:BAAANQAECgIIBwAAAA==.',
Kh='Khas:BAAANQADCgYIDwAAAA==.Khui:BAACNQAFFH8OAAIYAAYKbiQNBAClAQAYAAYKbiQNBAClAQA1AAQKfzIAAxgACgrHI7IEAFoDABgACgrHI7IEAFoDACAABQqUHQk1AG0BAAAA.',
Ki='Killatu:BAAANQABCggIDQAAAA==.Killerdeath:BAAANQAECgQIBAAAAA==.',
Kn='Knìghtmàrè:BAACNQAFFH8OAAMMAAcK0A08BAAoAQAMAAYKtQw8BAAoAQALAAMKhRRxHwCPAAA1AAQKfy4AAwwACgqzIxYUABgDAAwACgqzIxYUABgDAAsABwpzHuw0ADgCAAAA.',
Ko='Koltharaz:BAACNQAFFH8GAAIhAAIK4h8TCgDAAAAhAAIK4h8TCgDAAAA1AAQKfzIAAiEACgrHG6cJANYCACEACgrHG6cJANYCAAAA.Korloff:BAAANQADCggIEwABNQAECgIIAwAPAAAAAQ==.Kozan:BAAANQAECgIIAwAAAQ==.',
Kr='Krazsz:BAAANQADCgQIBAAAAA==.Krazykraw:BAAANQAECgIIBQAAAA==.Krazylock:BAAANQAECgQIDgAAAA==.Krokk:BAAANQABCgUIBQAAAA==.',
Ku='Kuiy:BAAANQADCgIIAgAAAA==.Kumah:BAAANQABCgEIAQAAAA==.Kungfuupanda:BAAANQAECgcIEwAAAA==.',
Ky='Kylar:BAAANQAECgQICAAAAA==.',
La='Lateralus:BAABNQAECn8eAAIMAAgKsSIsMABvAgAMAAgKsSIsMABvAgABNQAECgoKHQAFAMUQAA==.Latt:BAABNQAECn8dAAQFAAoKxRCrZQBuAQAFAAkKpQ6rZQBuAQAiAAUKERa8HQAoAQAGAAIK3xhsAwGIAAAAAA==.Lawluss:BAABNQAECn8iAAIRAAkKTBRgdAC6AQARAAkKTBRgdAC6AQAAAA==.Layonface:BAAANQAECgQIDAAAAA==.',
Le='Legacyshot:BAAANQAECgcIDgAAAQ==.Lelwani:BAAANQADCgEIAQAAAA==.',
Li='Lickthecrit:BAAANQAECgMIBQAAAA==.Lightguard:BAAANQADCggICgAAAA==.Lighthouse:BAABNQAECn8/AAMSAAoK+hfZSgA9AgASAAkK8xbZSgA9AgADAAkKoArSoAB2AQAAAA==.Lightload:BAAANQAECgYIEgAAAA==.Lileth:BAAANQAECgIIAwAAAA==.',
Lo='Lolhahabaha:BAAANQAECgUIDgAAAA==.Lonê:BAAANQAECgIIAgAAAA==.Loopie:BAAANQAECgcIDwAAAA==.Lorax:BAAANQAECgYICAAAAA==.',
Lu='Luckÿ:BAAANQAECgEJAgAAAA==.Luminah:BAAANQABCgIIAQAAAA==.',
Ly='Lypally:BAABNQAECn8/AAIDAAoKfQYFswBUAQADAAoKfQYFswBUAQAAAA==.',
['Lï']='Lïllïth:BAABNQAECn8hAAIRAAgKDQdywQB/AQARAAgKDQdywQB/AQAAAA==.Lïly:BAAANQAECgUIBwABNQAECgcIDgAPAAAAAA==.',
['Ló']='Lóla:BAABNQAECn8rAAIcAAgKvB4dEwDRAgAcAAgKvB4dEwDRAgAAAA==.',
['Lü']='Lüvine:BAAANQAECggICAAAAA==.',
Ma='Madeah:BAACNQAFFH8gAAIQAAgKfhRpAQDeAQAQAAgKfhRpAQDeAQA1AAQKfyAAAxAACQoDJG8CACsDABAACQoDJG8CACsDAB4ACApcCrMpAHcBAAAA.Madforge:BAABNQAECn9AAAMFAAoKGRncIACjAgAFAAoKGRncIACjAgAGAAEKxhUb4ABFAAAAAA==.Magegrizz:BAAANQAECgYIDgAAAA==.Magnyson:BAAANQAECggIDAAAAA==.Mahimahi:BAAANQADCgYICgAAAA==.Manahole:BAABNQAECn9DAAIUAAoKeiKqEAAGAwAUAAoKeiKqEAAGAwAAAA==.Mariacuras:BAABNQAECn8nAAISAAkKHhJHQQD8AQASAAkKHhJHQQD8AQAAAA==.Marijwana:BAABNQAECn8UAAIEAAcK7BayKwB/AQAEAAcK7BayKwB/AQAAAA==.Marynne:BAABNQAECn87AAIHAAkKpw28JgCdAQAHAAkKpw28JgCdAQAAAA==.Massaker:BAAANQADCggICgAAAA==.Mazuko:BAABNQAECn8pAAIjAAoK9hj1LwAoAgAjAAoK9hj1LwAoAgAAAA==.',
Mc='Mctank:BAAANQAECgEIAQAAAA==.',
Me='Mecandry:BAABNQAECn9FAAIRAAkK9hL9ZQBIAgARAAkK9hL9ZQBIAgAAAA==.Mecks:BAAANQADCggIKQAAAA==.Meepe:BAAANQAECgEIAQAAAA==.Melivant:BAABNQAECn8vAAQDAAoK9hBLigCjAQADAAoKXgtLigCjAQAEAAYKVRMTMwBKAQASAAUKeQ9CjwD5AAAAAA==.Meranda:BAABNQAECn8hAAIUAAoKOxWHqAAxAgAUAAoKOxWHqAAxAgAAAA==.Merrikfang:BAAANQADCgcIBwAAAA==.Merriklade:BAABNQAECn82AAQOAAoKQA7PDgB3AQAOAAkKMw/PDgB3AQATAAcK7wWL1QBFAQAVAAIKrwdwNwBTAAAAAA==.Merrikoid:BAABNQAECn8cAAMbAAcKsA1BHQDrAAAbAAYKEg9BHQDrAAAcAAYKuQUOOgC7AAAAAA==.Merrikwolf:BAAANQADCggIDgAAAA==.',
Mi='Mico:BAAANQAECgUIEgAAAA==.Missyjelliot:BAAANQAECgYICgAAAA==.',
Mo='Mokkii:BAAANQADCgEIAQAAAA==.Morbidstyle:BAAANQAECgYIDQABNQAECgoKOQAGAFMUAA==.Morgoth:BAABNQAECn84AAICAAoKqRZsUwBbAgACAAoKqRZsUwBbAgAAAA==.Morthos:BAAANQADCgcICgAAAA==.Mosry:BAABNQAECn87AAILAAoKKB7EFQBPAgALAAoKKB7EFQBPAgABNQABCgQIBgAPAAAAAA==.Mourneblood:BAAANQADCgUIBQAAAA==.',
My='Myora:BAEANQADCgcICQABNQAECgoKLgAIAEUTAA==.Mythundirus:BAABNQAECn8kAAIcAAoKcAOaOQC+AAAcAAoKcAOaOQC+AAAAAA==.',
['Mà']='Màrli:BAABNQAECn87AAILAAoKVxiUHgD4AQALAAoKVxiUHgD4AQAAAA==.',
['Mâ']='Mâgs:BAABNQAECn8vAAIEAAoKsAyOIABTAQAEAAoKsAyOIABTAQAAAA==.',
Na='Nakasid:BAABNQAECn9FAAMJAAoKshm5IgC6AgAJAAoKshm5IgC6AgAKAAUKBgcBUADSAAAAAA==.Nashoba:BAAANQADCgYJCwAAAA==.Natooka:BAAANQADCgUIBQAAAA==.',
Ne='Nein:BAAANQAECgQIDwAAAA==.Neins:BAAANQAECgEIAQABNQAECgQIDwAPAAAAAA==.Nevaehstar:BAABNQAECn9LAAIUAAoK5BEDVAAHAgAUAAoK5BEDVAAHAgAAAA==.',
Ni='Nibuto:BAABNQAECn8aAAIiAAgKQQeBIAAHAQAiAAgKQQeBIAAHAQAAAA==.Nijun:BAEBNQAECn80AAIJAAoKpA+SRQAMAgAJAAoKpA+SRQAMAgAAAA==.Nik:BAABNQAECn8bAAMFAAkK9Q3cXgCFAQAFAAkK9Q3cXgCFAQAGAAEKAAA9XgEbAAAAAA==.Nikita:BAAANQAECgUIBAAAAA==.Nikolia:BAABNQAECn8ZAAQVAAcKtggfKgDpAAAVAAUK7AwfKgDpAAAOAAQKegRwKwBYAAATAAQK8QHMFQFBAAAAAA==.Ninetynine:BAAANQADCgQIBAAAAA==.Nini:BAABNQAECn8VAAIIAAcKEAJtjwCZAAAIAAcKEAJtjwCZAAAAAA==.Ninx:BAAANQADCgUICQAAAA==.',
No='Noivana:BAAANQABCgEIAQABNQAFFAcIEgAjAM4YAA==.',
Ny='Nystel:BAAANQADCgEIAQAAAA==.',
Ol='Ollichi:BAAANQADCgIIAgAAAA==.',
Or='Ornn:BAAANQAECgcIDwABNQAECgoKLgABABwjAA==.',
Os='Osoroshi:BAAANQADCgYJBgABNQAECgkJRQARAPYSAA==.',
Ov='Overtime:BAAANQADCggIEQAAAA==.',
Pa='Padmê:BAAANQADCgMIAwAAAA==.Padrizul:BAAANQAECgEIAQAAAA==.Paladrak:BAAANQADCgIIAgAAAA==.Pandamared:BAAANQADCggIFwAAAA==.Patronous:BAAANQADCgYIDAAAAA==.',
Ph='Phearless:BAAANQAECgEIAQAAAA==.Phenol:BAAANQADCgEIAQAAAA==.',
Po='Polog:BAAANQAECgIIAwABNQAECgoKKwAUAL0iAA==.Porkchoplust:BAAANQAECgEIAQAAAA==.Porkribs:BAABNQAECn8bAAISAAgKkRqKRQBQAgASAAgKkRqKRQBQAgAAAA==.',
Pr='Pranks:BAAANQAECgQIDQAAAA==.Premalone:BAAANQADCgUICQAAAA==.',
Pu='Puca:BAAANQAECgEIAQAAAA==.Puchõ:BAAANQAECgIIAgAAAA==.Pumdmuc:BAABNQAECn8fAAMJAAkKwRwBIwC4AgAJAAkKwRwBIwC4AgAKAAEKCggJXQA2AAAAAA==.Punchymcheal:BAAANQAECggIEQABNQAECgoKOwAJAPMaAA==.',
Qu='Quikfix:BAAANQAECgIIAgAAAA==.Quikglaives:BAAANQAECgMIBgAAAA==.Quille:BAABNQAECn8uAAIRAAoKNh/FIACvAgARAAoKNh/FIACvAgAAAA==.',
Ra='Ragretts:BAAANQAECgEIAQAAAA==.Rahhem:BAAANQADCgYIBgAAAA==.Ranmo:BAAANQAECgcIEQAAAA==.Ratkol:BAAANQABCgIIAgAAAA==.Raysdknight:BAAANQADCgIJBwAAAA==.',
Re='Recbra:BAAANQAECgYIBwAAAA==.Redrek:BAAANQADCggINQAAAA==.Redsbank:BAAANQADCgUIBQAAAA==.Redshunter:BAAANQADCggIKQAAAA==.Redsknight:BAAANQADCgYIAQAAAA==.Redsmonk:BAAANQADCggICQAAAA==.Redwinter:BAABNQAECn8rAAMLAAkKYyCNLABlAgALAAkKYyCNLABlAgAZAAEKAACUwwAAAAAAAA==.Regnor:BAAANQADCgUIBQAAAA==.Reikisong:BAAANQAECgMICAAAAA==.Reiluune:BAAANQADCgQIAwABNQAECggIKwAcALweAA==.Remmie:BAAANQADCgUIBwAAAA==.',
Rh='Rhagurion:BAABNQAECn8+AAIdAAoKdSa6AADtAwAdAAoKdSa6AADtAwAAAA==.',
Ri='Riqua:BAAANQAECgMICAAAAA==.',
Ro='Rockmonsta:BAAANQADCgYJCgAAAA==.Rockys:BAAANQAECgEIAQAAAA==.Roxies:BAAANQAECgMIBwAAAA==.',
Rp='Rpg:BAABNQAECn8cAAIUAAkKlRkjmQBOAgAUAAkKlRkjmQBOAgAAAA==.',
Ru='Rumie:BAAANQADCgUIBQAAAA==.Runes:BAAANQAECgcIDwAAAA==.',
Ry='Ryllan:BAAANQAECgEIAQAAAA==.',
Sa='Saeti:BAABNQAECn9RAAUWAAoKdCT6AQA8AwAWAAkKdCT6AQA8AwAIAAYKnx7ANQBLAQAHAAYKgg2eTwDLAAAdAAEKxB+XUwBWAAAAAA==.Sanare:BAAANQAECggICQABNQAECgoKOwAJAPMaAA==.Sanbit:BAAANQAECgQICQAAAA==.Santhaenis:BAAANQAECgcICgAAAA==.Sapplesauce:BAAANQAECgcIDgAAAA==.Satchelhammr:BAAANQAECgEIAQAAAA==.Saurfang:BAAANQADCgEIAQAAAA==.',
Se='Sedael:BAAANQAECgEIAgAAAA==.Seethrowwar:BAABNQAECn8iAAMTAAkKuh6vOwDYAgATAAkKaB6vOwDYAgAVAAYKQRbiGwB9AQAAAA==.Senbit:BAAANQAECgUIEQAAAA==.Serenìty:BAAANQAECgYIDgAAAA==.Seresin:BAABNQAECn9zAAMHAAoKqRlfFQCbAgAHAAoKqRlfFQCbAgAIAAUKkwVbggDHAAAAAA==.',
Sh='Shadý:BAABNQAECn8lAAIRAAkKiQUu5AA4AQARAAkKiQUu5AA4AQAAAA==.Shamanoodles:BAAANQAECgEIAQABNQAECgoKKwAUAL0iAA==.Shortwarrior:BAABNQAECn8rAAIOAAgKoRG/DwBmAQAOAAgKoRG/DwBmAQAAAA==.',
Si='Sianu:BAAANQAECgYIEQABNQAECgkJOwAHAKcNAA==.Sidraya:BAABNQAECn8cAAMXAAcKDRL2FwA6AQAXAAcKDRL2FwA6AQAUAAEKxQOcWwEsAAAAAA==.Silent:BAABNQAECn83AAITAAoKoxsnKACUAgATAAoKoxsnKACUAgAAAA==.Silverserqet:BAABNQAECn8hAAIRAAcKzQrQygBrAQARAAcKzQrQygBrAQAAAA==.',
Sl='Slipknaught:BAAANQAECgEIAQABNQAECgoKHQAZALsJAA==.',
Sm='Smileyriley:BAAANQAECgEIAQAAAA==.',
Sn='Sneakylinks:BAAANQADCgIIAgABNQAECgkJHAAUAJUZAA==.',
So='Sonbit:BAAANQAECgQIBAAAAA==.Sonichero:BAAANQAECgQIBAAAAA==.Sooki:BAAANQAECgMIBgAAAA==.Sophie:BAAANQAECgQIEgAAAA==.Soulber:BAAANQAECgMIBgAAAA==.',
Sp='Spunky:BAAANQAECgQIBAAAAA==.',
Ss='Ssenbit:BAAANQAECgQICAAAAA==.Ssonbit:BAAANQADCggIEQAAAA==.',
St='Stefeana:BAAANQADCgYIBgAAAA==.Sternhoof:BAAANQABCgMIBQAAAA==.Stigma:BAAANQADCggIFQABNQAECgoKMQAJACAiAA==.Stylos:BAABNQAECn8zAAIiAAoKYxDtDwACAgAiAAoKYxDtDwACAgAAAA==.',
Su='Summersong:BAAANQADCgQIBAAAAA==.Sumofwhy:BAAANQADCgcIBwAAAA==.',
Sw='Swarli:BAAANQAECgIIAgAAAA==.Swowtitbang:BAAANQAECgYIEgAAAA==.',
Sy='Sylven:BAAANQAECgUIBwABNQAECgoKNQAGAAcgAA==.',
Te='Techno:BAABNQAECn8UAAMcAAkKUgLnTABLAAAcAAcKNALnTABLAAAjAAkKcwEJfgA1AAAAAA==.Tegbolt:BAABNQAECn8dAAMGAAgKeRXAZgDsAQAGAAgKghPAZgDsAQAiAAcKLhLWGwCmAQAAAA==.Teghorn:BAAANQAECggICAABNQAECggIHQAGAHkVAA==.Tekko:BAABNQAECn9HAAMdAAoKWB4iCAC2AgAdAAoKWB4iCAC2AgAWAAEKOQX8UAAQAAAAAA==.Tempestrike:BAABNQAECn8uAAIcAAoKehuRDwD3AgAcAAoKehuRDwD3AgAAAA==.',
Th='Theholymatt:BAABNQAECn9HAAMSAAoKdiREEgA9AwASAAoKdiREEgA9AwADAAUKtRBt6QD4AAAAAA==.Thendari:BAABNQAECn9XAAINAAoKBQ41BQCUAQANAAoKBQ41BQCUAQAAAA==.Theodus:BAABNQAECn8vAAIUAAoKOhK2twAUAgAUAAoKOhK2twAUAgAAAA==.Therayen:BAAANQADCgYJCwAAAA==.Thomeriddle:BAAANQABCgMIAQAAAA==.Thorrune:BAAANQAECgIIAgAAAA==.',
Ti='Tiferis:BAACNQAFFH8IAAISAAUKqBRCEAAlAQASAAUKqBRCEAAlAQA1AAQKf0EAAhIACgqfIMcLAGEDABIACgqfIMcLAGEDAAAA.Tigerclawss:BAAANQADCggIMwAAAA==.Tislam:BAAANQAECgMIBgAAAA==.',
To='Tobiquer:BAABNQAECn9JAAIJAAoKNiLTCQCNAwAJAAoKNiLTCQCNAwAAAA==.Tojarmar:BAAANQADCgQIBAABNQAECgIIAgAPAAAAAA==.Torolf:BAAANQAECgMIBQAAAA==.',
Tq='Tqco:BAAANQADCgMIAwABNQAECgoKRwAdAFgeAA==.',
Tr='Traydra:BAAANQADCgUIBwAAAA==.Trinbug:BAAANQADCgEIAQAAAA==.Troglodyte:BAABNQAECn9XAAIGAAoKniQuBgBJAwAGAAoKniQuBgBJAwAAAA==.',
Ts='Tsonokwabain:BAABNQAECn8lAAIZAAkKMh3pKgBFAgAZAAkKMh3pKgBFAgAAAA==.Tsunami:BAAANQADCgMIAwAAAA==.',
Tw='Twistdog:BAAANQABCgQIBgAAAA==.',
Ty='Tye:BAABNQAECn8iAAIRAAoKohekUwB2AgARAAoKohekUwB2AgAAAA==.Tyranastrasz:BAABNQAECn83AAQhAAoKsQdVHgBtAQAhAAgK1QVVHgBtAQAkAAoKmwX5GABOAQAlAAEKTQCNKQANAAAAAA==.Tyye:BAABNQAECn8qAAIOAAcK+iIwBwAvAgAOAAcK+iIwBwAvAgAAAA==.',
['Tâ']='Tâjik:BAABNQAECn8jAAIeAAoKtATKKQB2AQAeAAoKtATKKQB2AQAAAA==.',
Ul='Ulquiorra:BAACNQAFFH8LAAMcAAUK4w9sDQDUAAAcAAQK4w9sDQDUAAAbAAIKQAiPBwBCAAA1AAQKfzcAAxwACgoVIQ0QAPICABwACQoVIQ0QAPICABsABAoIDe8gAL0AAAAA.',
Ur='Uraja:BAAANQABCgIIAgAAAA==.',
Ut='Uthers:BAAANQADCgYIAgAAAA==.',
Va='Vaethund:BAAANQAECgMIBgAAAA==.Valdred:BAAANQAECgYIBgABNQAFFAcIEgAjAM4YAA==.Valgavoth:BAABNQAECn8VAAILAAkK4Bf/NwApAgALAAkK4Bf/NwApAgAAAA==.Vangar:BAAANQADCgQIBAAAAA==.Vanthion:BAAANQADCggICgAAAA==.',
Ve='Velara:BAAANQAECgQIBgAAAA==.Velinna:BAAANQADCgUIBwABNQAECgEIAwAPAAAAAA==.Venekor:BAAANQADCgIIAgAAAA==.',
Vi='Viriex:BAAANQAECgEIAQAAAA==.Vitoria:BAAANQAECgQICAAAAA==.',
Vo='Voidlighter:BAABNQAECn87AAIJAAoK8xo1JADcAgAJAAoK8xo1JADcAgAAAA==.Volundr:BAABNQAECn8sAAIVAAoKqBkeDgBNAgAVAAoKqBkeDgBNAgAAAA==.Vonvaughan:BAAANQAECgQIBAAAAA==.',
Vy='Vynel:BAAANQAECgIIAgABNQAECgoKNQAGAAcgAA==.Vynirion:BAAANQAECgEIAwAAAA==.',
Wa='Wardellmo:BAAANQADCgQIBAAAAA==.Wargtar:BAABNQAECn8bAAIQAAcKCBnbMwAMAgAQAAcKCBnbMwAMAgAAAA==.Warriorskull:BAAANQADCgYICAAAAA==.',
We='Weabe:BAAANQAECgIIBgAAAA==.',
Wh='Whiterrina:BAAANQADCgIJAgAAAA==.Whitespring:BAAANQAECgYIEAABNQAECgkJKwALAGMgAA==.',
Wo='Wolfgarou:BAAANQAECgEIAQAAAA==.',
Wy='Wyrdo:BAAANQADCgYIBgAAAA==.',
['Wù']='Wùsthof:BAABNQAECn8fAAIRAAkKYApKiQD4AQARAAkKYApKiQD4AQAAAA==.',
Xa='Xandrios:BAAANQAECgEJAQAAAA==.',
Xi='Xiae:BAABNQAECn8tAAMGAAoKdBfzTABDAgAGAAgK6RbzTABDAgAFAAQKCxAtmgDYAAAAAA==.',
Ya='Yasuke:BAAANQADCgUJBQAAAA==.',
Ye='Yet:BAAANQAECgEIAQABNQAECgoKLgAUACYjAA==.',
Yi='Yiffweaver:BAAANQAECgEIAQAAAA==.',
Yo='Yokochan:BAAANQABCgIIAgAAAA==.Yokoriazen:BAABNQAECn87AAIDAAoKfxUMYQB2AgADAAoKfxUMYQB2AgAAAA==.',
Za='Zakaradin:BAAANQADCgcICAABNQAECgIIAwAPAAAAAA==.Zandigor:BAAANQAECgIIAgAAAA==.Zaraeliana:BAAANQAECgMIBgAAAA==.Zarastraza:BAABNQAECn8kAAMkAAkKFhFxIgC3AQAkAAkKFhFxIgC3AQAhAAUKFQt0JQAPAQAAAA==.',
Ze='Zephnor:BAABNQAECn8hAAMdAAgKhw9lJABzAQAdAAcK/xBlJABzAQAIAAgKxQnTYgBDAQAAAA==.',
Zh='Zhao:BAAANQADCgYIBgAAAA==.',
Zm='Zmona:BAAANQAECgQIBAAAAA==.',
Zo='Zorsche:BAAANQAECgEIAQAAAA==.',
Zu='Zulrok:BAABNQAECn8zAAITAAoKOBMPTgACAgATAAoKOBMPTgACAgAAAA==.',
['Áb']='Ábsurd:BAAANQAECggIDAABNQABCgIIAQAPAAAAAA==.',
['Ðr']='Ðre:BAAANQAECgMIBgAAAA==.',
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
