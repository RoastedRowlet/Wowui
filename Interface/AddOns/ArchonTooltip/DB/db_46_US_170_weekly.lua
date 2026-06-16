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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Balance','Druid-Guardian','Warlock-Demonology','Shaman-Elemental','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Holy','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Warlock-Destruction','Warrior-Fury','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Evoker-Devastation','Monk-Windwalker','Monk-Mistweaver','Mage-Frost','Warrior-Protection','DeathKnight-Frost','Priest-Shadow','Mage-Arcane','Druid-Restoration','Warlock-Affliction','DeathKnight-Blood','Monk-Brewmaster','Priest-Discipline','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','Hunter-Survival','Shaman-Enhancement','Hunter-Marksmanship',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=46,date='2026-06-13',data={Ac='Achilles:BAAALgADCgEJAQAAAA==.',
Ad='Adoraluna:BAAALgAECgEJAQAAAA==.Adunei:BAAALgAECgIJAgAAAA==.',
Ae='Aeginalla:BAAALgADCgcJEgABLgAECgYJCAABAAAAAA==.Aela:BAAALgADCgEJAQABLgAECgkJMwACAAYhAA==.Aesalon:BAABLgAECn80AAQDAAkJ1CPzAwDHAgADAAkJ1CPzAwDHAgAEAAIJrRTjeQA+AAAFAAIJGBOUbwA0AAABLgAECgkJHQAGAOEdAA==.',
Ah='Ahsokatano:BAABLgAECn8zAAMCAAkJBiE7BwA6AwACAAkJBiE7BwA6AwAHAAEJ8gyprQAoAAAAAA==.',
Ai='Aimspet:BAAALgAECgYJEQAAAA==.Aircanada:BAAALgAECgIJBAAAAA==.',
Ak='Akela:BAABLgAECn8oAAIIAAkJIQ2/SwC6AQAIAAkJIQ2/SwC6AQAAAA==.',
Al='Algorithm:BAAALgAECgMJAwAAAA==.Alissu:BAAALgADCgIJAgAAAA==.Alvonaar:BAAALgADCgUJBwAAAA==.',
Am='Ames:BAAALgAECgcJDAAAAA==.Amonet:BAAALgAECgUJDwAAAA==.',
An='Anaelcheese:BAABLgAECn8aAAQJAAcJ2BRYIgBfAQAJAAcJ2BRYIgBfAQAKAAEJkg0sLgAnAAALAAEJywAN9wATAAAAAA==.Anamis:BAABLgAECn8qAAIMAAkJ5BKPIgCqAQAMAAkJ5BKPIgCqAQAAAA==.Andrina:BAAALgADCgYJAgAAAA==.Angeldemon:BAAALgADCgYJCAAAAA==.Angras:BAABLgAECn86AAINAAkJZBZgLgBDAgANAAkJZBZgLgBDAgAAAA==.Angryorc:BAAALgAECgQJBQAAAA==.Anja:BAAALgAECgcJBwAAAA==.Anolana:BAABLgAECn86AAMOAAkJfiHmBQDQAgAOAAkJfiHmBQDQAgAPAAEJixF0JgA3AAAAAA==.Anrom:BAAALgAECgEJAQAAAA==.Anyday:BAAALgADCgcJBwAAAA==.',
Ap='Aphalock:BAABLgAECn85AAIQAAkJwBV0BQATAgAQAAkJwBV0BQATAgAAAA==.',
Ar='Aragoth:BAAALgAECgEJAQAAAA==.Ariûs:BAABLgAECn8XAAIRAAgJnREVLACiAQARAAgJnREVLACiAQAAAA==.Arlin:BAABLgAECn8VAAISAAUJ0SCvJQDYAQASAAUJ0SCvJQDYAQAAAA==.Arlorian:BAABLgAECn81AAIPAAkJmRI/BwDmAQAPAAkJmRI/BwDmAQAAAA==.Arorra:BAAALgAECgYJBgAAAA==.Arrex:BAAALgAECgYJCAAAAA==.Arrowsmites:BAABLgAECn8yAAIIAAkJhRx4HAB2AgAIAAkJhRx4HAB2AgAAAA==.',
Au='Aubani:BAABLgAECn8xAAMSAAkJFCAvCQD2AgASAAkJFCAvCQD2AgATAAUJIxIl2ADlAAAAAA==.',
Ay='Ayperos:BAABLgAECn9EAAMUAAgJ/BwXCgBHAgAUAAgJ/BwXCgBHAgARAAYJPxAVUgBhAQAAAA==.Ayvaria:BAEALgAECgYJEwABLgAECgkJKwAVACQXAA==.',
Az='Azorus:BAAALgADCgEJAQAAAA==.',
Ba='Baboyago:BAAALgAECgcJDwAAAA==.Badgerbrew:BAAALgADCgkJCQAAAA==.Bahemith:BAAALgAECgEJAQAAAA==.Baked:BAAALgAECgQJBAABLgAECgkJIQATAMcGAA==.Bakedpally:BAABLgAECn8hAAITAAkJxwaznQA4AQATAAkJxwaznQA4AQAAAA==.Bandomar:BAABLgAECn8mAAIEAAgJywsMNQA/AQAEAAgJywsMNQA/AQAAAA==.Baniemo:BAAALgAECgIJBAAAAA==.Banigor:BAAALgAECgYJEAAAAA==.Basak:BAAALgAECgYJCwABLgAFFAUJEgABAAAAAQ==.',
Be='Beammescotty:BAAALgADCgQJBAAAAA==.Bearnuts:BAAALgADCgEJAQAAAA==.Beck:BAABLgAECn81AAITAAkJliGZEQDYAgATAAkJliGZEQDYAgAAAA==.Beefflaps:BAAALgADCgEJAQAAAA==.Beggars:BAAALgAECgYJDQAAAA==.Belithsong:BAAALgAECgkJBwAAAA==.Bereth:BAABLgAECn8VAAIIAAUJZBmShQAuAQAIAAUJZBmShQAuAQAAAA==.Berreydingle:BAAALgAECgUJDgAAAA==.',
Bi='Bigkitty:BAABLgAECn8qAAIRAAkJnhn0GQAcAgARAAkJnhn0GQAcAgABLgAECggJMQAIAEsiAA==.Bikinibrenda:BAAALgAECgEJAQAAAA==.Birchum:BAAALgADCgcJBwAAAA==.Biz:BAAALgADCgYJBwABLgAECggJFwAWAOMhAA==.',
Bl='Blackanvil:BAABLgAECn8VAAIRAAgJ/g71MACIAQARAAgJ/g71MACIAQAAAA==.Blackautumn:BAAALgADCgcJDgABLgAECggJHwARAPcbAA==.Blainn:BAAALgAECgcJBwAAAA==.Blindfred:BAAALgAECggJDQAAAA==.Blitzedbust:BAAALgADCggJDQAAAA==.Bloodredsky:BAABLgAECn8gAAMXAAkJhBKjKQDXAQAXAAkJhBKjKQDXAQAWAAEJmwiwfwAxAAAAAA==.Bloodymagi:BAABLgAECn8pAAIYAAkJCQfVgQBwAQAYAAkJCQfVgQBwAQAAAA==.Bluesummer:BAABLgAECn8fAAQRAAgJ9xufJADPAQARAAcJrR6fJADPAQAZAAYJxBrAGQCCAQAUAAEJCAzpQQA1AAAAAA==.',
Bo='Bolts:BAAALgAECgEJAwAAAA==.Boomin:BAABLgAECn8wAAMFAAkJuhrNCQBIAgAFAAkJuhrNCQBIAgAEAAQJdQYUbABtAAAAAA==.Borat:BAAALgAECgQJCAABLgAECgkJLgATAKQkAA==.',
Br='Brendameeks:BAAALgAECgcJEAAAAA==.Brewnashot:BAAALgADCggJCgAAAA==.Brewrain:BAAALgADCgEJAQAAAA==.Broadzinatl:BAABLgAECn8XAAIWAAgJ4yG+CQCkAgAWAAgJ4yG+CQCkAgAAAA==.Brom:BAAALgAECgYJBwAAAA==.Brïn:BAAALgAECgcJCQAAAA==.Bròly:BAAALgADCgYJBgAAAA==.',
Bu='Bulwark:BAAALgADCgYJBgAAAA==.Bushwookië:BAAALgAECgIJAgAAAA==.',
['Bã']='Bãthory:BAABLgAECn8XAAIaAAkJIxQHDgCSAQAaAAkJIxQHDgCSAQAAAA==.',
['Bø']='Bøss:BAAALgADCgkJEQAAAA==.',
Ca='Calquo:BAAALgAECgIJAgABLgAECgcJMwAOAHchAA==.Calvert:BAAALgAECgUJBgAAAA==.Captnhammer:BAAALgAECgIJBAAAAA==.Carebearr:BAAALgADCgcJBwAAAA==.Carnelian:BAAALgAECgUJDQAAAA==.Castration:BAABLgAECn8YAAIbAAYJ3AkrTQDYAAAbAAYJ3AkrTQDYAAAAAA==.',
Ce='Ceylan:BAABLgAECn8xAAMYAAkJgxnJLwBYAgAYAAkJgxnJLwBYAgAcAAEJVQMVIQAqAAAAAA==.',
Ch='Chadillac:BAAALgAECgMJAwAAAA==.Chaleb:BAAALgAECgUJCgAAAA==.Charavane:BAAALgAECgQJBAAAAA==.Charlz:BAABLgAECn8jAAMbAAkJhBZsGwDoAQAbAAkJhBZsGwDoAQAMAAQJChHLVQDfAAAAAA==.Charsifood:BAAALgAECgcJDwAAAA==.Chass:BAAALgADCgQJBAAAAA==.Cheatdr:BAABLgAECn8tAAIdAAkJKw/XNgC7AQAdAAkJKw/XNgC7AQAAAA==.Cheatpriest:BAABLgAECn87AAIMAAkJlRkHGgD3AQAMAAkJlRkHGgD3AQAAAA==.Chesthyr:BAAALgAECgEJAQAAAA==.Chesto:BAABLgAECn84AAQeAAkJ7hx/BABSAgAeAAkJZBp/BABSAgAQAAcJ4xohCgCfAQAGAAcJwRT2awCKAQAAAA==.Chimerax:BAAALgAECgIJAgAAAA==.Chimken:BAAALgAECgcJCAABLgAECgkJKQAUADUeAA==.Chokea:BAAALgAECgkJDgAAAA==.Chrome:BAAALgAECgEJAQAAAA==.Chuwhee:BAAALgADCgYJBgAAAA==.',
Ci='Cindrethresh:BAAALgAECgUJBQAAAA==.',
Co='Cognition:BAACLgAFFH8FAAIIAAIJ5h6AbwC1AAAIAAIJ5h6AbwC1AAAuAAQKf1MAAggACQnxJbUBAHgDAAgACQnxJbUBAHgDAAAA.Coldvengance:BAABLgAECn85AAIRAAkJAQrmNAB1AQARAAkJAQrmNAB1AQAAAA==.Corpser:BAAALgADCgUJBQAAAA==.',
Cr='Cranki:BAAALgAECgUJBgABLgAECgIJBAABAAAAAA==.Cranknstein:BAAALgAECgEJAQABLgAECgIJBAABAAAAAA==.Crazycalla:BAAALgAFFAEJAgAAAA==.Crosbyy:BAAALgAECgUJBQAAAA==.Crànk:BAAALgAECgEJAgABLgAECgIJBAABAAAAAA==.',
Cy='Cymindel:BAABLgAECn84AAIfAAkJCxqODABBAgAfAAkJCxqODABBAgAAAA==.',
Da='Dad:BAAALgADCgQJBAAAAA==.Daelein:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Daithi:BAAALgAECgcJEwAAAA==.Dakotà:BAABLgAECn8nAAIIAAcJeRhaSwC7AQAIAAcJeRhaSwC7AQAAAA==.Darc:BAAALgAECgQJBgAAAA==.Darkkubo:BAAALgAECgEJAQAAAA==.Darklite:BAAALgADCgYJEgAAAA==.Darkmonk:BAAALgADCgUJBQAAAA==.Dassadin:BAAALgAECgQJBQAAAA==.Davinci:BAAALgADCgEJAQAAAA==.Day:BAABLgAECn8hAAIIAAgJmhjmQwDRAQAIAAgJmhjmQwDRAQAAAA==.Dayztocome:BAAALgADCgEJAQAAAA==.',
De='Decaydence:BAAALgAECggJEAAAAA==.Dejno:BAABLgAECn8YAAIRAAcJMiBOLAChAQARAAcJMiBOLAChAQAAAA==.Deleted:BAAALgAECgEJAQABLgAECgkJKQANAOgkAA==.Demonicly:BAABLgAECn8UAAIKAAcJuxOeDgBiAQAKAAcJuxOeDgBiAQAAAA==.Demonred:BAAALgADCgYJBgAAAA==.Demönslayer:BAAALgAECgcJAwAAAA==.Derowski:BAAALgAECgQJBQAAAA==.Deroz:BAAALgADCgUJBQAAAA==.Dethra:BAAALgADCgcJCwAAAA==.Dezign:BAACLgAFFH8WAAIYAAcJYBdLKADTAQAYAAcJYBdLKADTAQAuAAQKfygAAhgACQl2IOooAM8CABgACQl2IOooAM8CAAAA.Dezígn:BAABLgAFFH8IAAIGAAQJAhJ4UgAdAQAGAAQJAhJ4UgAdAQABLgAFFAcJFgAYAGAXAA==.',
Di='Diabolical:BAAALgAECgEJAQAAAA==.Discordegirl:BAABLgAECn8WAAMgAAYJQQyiUAC9AAAgAAUJvA6iUAC9AAAWAAEJVQJzvAAYAAAAAA==.Divinitÿ:BAAALgADCgIJAgABLgAECgkJJAAZAIwlAA==.',
Do='Dolgorukov:BAABLgAECn8vAAIIAAkJXhPFQwDSAQAIAAkJXhPFQwDSAQAAAA==.Dologony:BAABLgAECn8jAAIdAAkJmg6rPwCRAQAdAAkJmg6rPwCRAQAAAA==.',
Dr='Dracigor:BAAALgAECgQJBQAAAA==.Draconair:BAAALgADCgYJCAAAAA==.Dragonsbaine:BAAALgADCgMJAwAAAA==.Dragonz:BAAALgAECgUJEQAAAA==.Drakhan:BAAALgADCgIJAgAAAA==.Dre:BAAALgAECgMJCAAAAA==.Dreåm:BAAALgADCgQJBAABLgAECgkJJAAZAIwlAA==.Drikken:BAABLgAECn8/AAQLAAkJwxleMAACAgALAAkJOhdeMAACAgAKAAUJ2xuPFAAHAQAJAAUJgBZZLwAGAQAAAA==.Drmaker:BAAALgAECgMJAwAAAA==.Drougs:BAABLgAECn8uAAIJAAkJVxiSFwDEAQAJAAkJVxiSFwDEAQAAAA==.Druiddeleted:BAAALgAECgEJAQABLgAECgkJKQANAOgkAA==.',
Du='Dubbshot:BAAALgAECgEJAQAAAA==.Dumara:BAAALgADCgIJAgAAAA==.Durasan:BAABLgAECn8jAAMaAAcJgwzSGQD/AAAaAAUJqA3SGQD/AAANAAcJWweqxgDyAAAAAA==.Duressa:BAAALgAECgcJBwAAAA==.',
Dy='Dymund:BAAALgAECgIJBAAAAA==.',
['Dà']='Dàrkside:BAAALgAECgYJBgAAAA==.',
['Dö']='Dötdötdead:BAABLgAECn8pAAMQAAgJIhWnCQCnAQAQAAgJIhWnCQCnAQAGAAIJZwvRCgFbAAAAAA==.',
Ea='Earthie:BAAALgADCgEJAQAAAA==.Earthstorm:BAAALgADCgIJAgAAAA==.Eastwubz:BAAALgADCgIJAgAAAA==.',
Ed='Edge:BAAALgAECgMJBQAAAA==.',
Ef='Effin:BAAALgADCgUJBQAAAA==.Effindin:BAAALgAECgUJBwAAAA==.Effinfu:BAABLgAECn8jAAIgAAkJpRA/HwCqAQAgAAkJpRA/HwCqAQAAAA==.',
Ei='Eitent:BAABLgAECn8wAAMSAAkJux3FDQCqAgASAAkJux3FDQCqAgATAAcJuhIRdgCOAQABLgAFFAMJBgAhAKoRAA==.',
El='Ele:BAAALgADCgcJCAABLgAECgcJHQASALEfAA==.Ellesthara:BAAALgAECgcJEQAAAA==.Ellysiaa:BAABLgAECn8WAAIDAAYJLQVUMQCVAAADAAYJLQVUMQCVAAAAAA==.Elrïc:BAAALgAECgUJBgAAAA==.Elwynlana:BAAALgADCgYJBwAAAA==.Elysa:BAAALgADCgEJAQAAAA==.',
Em='Emberstorm:BAAALgAECgQJBQAAAA==.Emmakyn:BAABLgAECn8vAAMEAAgJ2RVSHwDKAQAEAAgJ2RVSHwDKAQAdAAcJMA08VwAxAQAAAA==.',
En='Enezath:BAAALgADCgIJAgAAAA==.Entrerie:BAAALgADCgcJFgAAAA==.Enyxea:BAABLgAECn8XAAICAAgJFRfEKQARAgACAAgJFRfEKQARAgAAAA==.',
Ep='Ephemera:BAAALgAECgYJDgAAAA==.Epsolon:BAAALgAECgIJAgAAAA==.',
Er='Erikuh:BAAALgADCgEJAQAAAA==.Erodin:BAAALgAECgEJAgAAAA==.',
Es='Esmeray:BAEBLgAECn8ZAAIhAAkJoBSIEQBZAgAhAAkJoBSIEQBZAgABLgAECgkJKwAVACQXAA==.Estala:BAAALgADCgUJBQAAAA==.',
Ey='Eyedontknow:BAABLgAECn8gAAIiAAgJCCHMBQCMAgAiAAgJCCHMBQCMAgAAAA==.Eyewana:BAABLgAECn8kAAIJAAkJchKVHACTAQAJAAkJchKVHACTAQAAAA==.',
Ez='Ezzka:BAABLgAECn8jAAINAAkJxRi7JQBrAgANAAkJxRi7JQBrAgAAAA==.',
Fa='Faelan:BAAALgADCgIJAQAAAA==.Fakesaint:BAAALgAECgYJDgAAAA==.Fangalor:BAAALgAECgEJBAAAAA==.Farnsworth:BAABLgAECn8dAAQGAAkJ4R1vHgBsAgAGAAgJ+x1vHgBsAgAQAAMJGBydIAClAAAeAAEJNBN3OABBAAAAAA==.Farzix:BAABLgAECn8qAAIHAAkJKQmVOwBDAQAHAAkJKQmVOwBDAQAAAA==.Façade:BAABLgAECn8mAAINAAkJDxP9XQCsAQANAAkJDxP9XQCsAQAAAA==.',
Fe='Feelgood:BAAALgAECgQJBAAAAA==.Fefifiona:BAACLgAFFH8FAAIhAAIJOA1vPgB4AAAhAAIJOA1vPgB4AAAuAAQKfxkAAiEACQkqFwYQAG0CACEACQkqFwYQAG0CAAAA.Fefifredrich:BAAALgAECgMJAwABLgAFFAIJBQAhADgNAA==.Fefifuredric:BAAALgAECgQJBQABLgAFFAIJBQAhADgNAA==.Felvira:BAABLgAECn8dAAMLAAgJPgRu0QCLAAALAAYJbQNu0QCLAAAJAAUJWwTvVwBaAAAAAA==.',
Fi='Finnw:BAABLgAECn8dAAISAAcJsR+nEACQAgASAAcJsR+nEACQAgAAAA==.Firelite:BAABLgAECn8iAAIHAAcJag/JQwAgAQAHAAcJag/JQwAgAQAAAA==.',
Fl='Flairlock:BAABLgAECn87AAMeAAkJZyGcAgCgAgAeAAkJZyGcAgCgAgAQAAIJBhWFOwA5AAAAAA==.Flee:BAABLgAECn8iAAIOAAkJqRqoDgA9AgAOAAkJqRqoDgA9AgAAAA==.',
Fo='Fookster:BAABLgAECn8ZAAIYAAkJyhPKPwAaAgAYAAkJyhPKPwAaAgAAAA==.Forsetee:BAABLgAFFH8GAAIgAAIJTRc5QwCQAAAgAAIJTRc5QwCQAAAAAA==.',
Fr='Frowdawn:BAABLgAECn87AAIPAAkJUxCQBwDcAQAPAAkJUxCQBwDcAQAAAA==.',
Fy='Fyf:BAAALgAECgYJBgABLgAECgIJBAABAAAAAA==.',
['Fí']='Físter:BAAALgAECgYJDwABLgAECgcJGgANACoaAA==.',
Ga='Ga:BAAALgAECgIJAgAAAA==.Galadris:BAAALgADCgkJDwAAAA==.Garythenpc:BAABLgAECn8VAAIZAAUJKxLRLQDJAAAZAAUJKxLRLQDJAAAAAA==.Gaztoria:BAAALgADCggJCAABLgAECgkJLwANANYiAA==.',
Ge='Genavieve:BAAALgADCgQJBAAAAA==.Gendra:BAAALgAECgEJAQAAAA==.',
Gh='Ghøst:BAAALgADCgEJAQAAAA==.',
Gi='Gilas:BAAALgADCgQJBAAAAA==.',
Gl='Glacialkitty:BAABLgAECn8vAAIdAAkJ4gv2RQB1AQAdAAkJ4gv2RQB1AQAAAA==.',
Go='Googoobler:BAABLgAECn8iAAIJAAgJ7AdVLgANAQAJAAgJ7AdVLgANAQAAAA==.Goudaluck:BAAALgADCgUJBwABLgAECggJMQAIAEsiAA==.Goudanight:BAAALgAECgMJBQABLgAECggJMQAIAEsiAA==.Goudavibes:BAAALgAECgEJAQABLgAECggJMQAIAEsiAA==.',
Gr='Greenmagus:BAAALgAECgEJAQAAAA==.Grenadon:BAAALgAECgUJEgAAAA==.Gridimbor:BAAALgAECgEJAQAAAA==.Grimlilith:BAABLgAECn8bAAQeAAgJ/wSbEQATAQAeAAgJ9gSbEQATAQAGAAMJBAPMLQE5AAAQAAEJAAAogQALAAAAAA==.Grimmhoof:BAAALgAECgIJAgAAAA==.Grundy:BAAALgAECgUJCAAAAA==.',
Gu='Gumbi:BAAALgADCgIJAgAAAA==.',
Ha='Hadorya:BAABLgAECn88AAIbAAkJOx3eDACEAgAbAAkJOx3eDACEAgAAAA==.Hakitua:BAABLgAECn8mAAIKAAkJ2w0uDgBqAQAKAAkJ2w0uDgBqAQAAAA==.Hando:BAAALgAECgEJAQAAAA==.Hangi:BAAALgADCgkJCQAAAA==.Happymeel:BAAALgAECgEJAQAAAA==.Harleyqûinn:BAAALgAECgcJDQAAAA==.Hatshepsut:BAAALgAECgEJAQAAAA==.Hazard:BAABLgAECn88AAIRAAkJSA/tKAC1AQARAAkJSA/tKAC1AQAAAA==.',
He='Healonwheels:BAAALgADCgMJAwAAAA==.Heimdall:BAABLgAECn8kAAQZAAkJjCW5AABqAwAZAAkJjCW5AABqAwARAAcJ7hw4HgD7AQAUAAMJvxDuSgCcAAAAAA==.Heis:BAABLgAECn8VAAIRAAUJiBgsRQAwAQARAAUJiBgsRQAwAQAAAA==.Hellboii:BAAALgAECggJEwAAAA==.Heyitsrat:BAABLgAECn8xAAITAAkJABdKQQAAAgATAAkJABdKQQAAAgAAAA==.',
Hi='Hiko:BAAALgAECgkJEgAAAA==.',
Ho='Holo:BAACLgAFFH8SAAMCAAYJJgqFAgC9AQACAAYJJgqFAgC9AQAHAAUJFB+VHAAwAQAuAAQKfyEAAwcACQlzIWYDAG0DAAcACQlzIWYDAG0DAAIABwnXDgJCAHkBAAAA.Holos:BAAALgAECgEJAQABLgAFFAYJEgACACYKAA==.Holyangus:BAAALgAECgUJDAAAAA==.Holyfawn:BAAALgADCgEJAQAAAA==.Holyyknight:BAAALgAECgcJEwAAAA==.',
Hu='Hugecrit:BAAALgADCgkJDwAAAA==.',
Ib='Ibbert:BAAALgADCggJFQAAAA==.',
Ic='Icculus:BAABLgAECn8lAAIIAAgJJxnDNwD6AQAIAAgJJxnDNwD6AQAAAA==.',
Il='Illuyanka:BAAALgAECgEJAQAAAA==.',
Im='Imaresmashy:BAAALgAECgIJAgABLgAECgkJJAABAAAAAA==.Impasse:BAAALgAECgkJCAAAAA==.',
In='Indaskyz:BAAALgADCgEJAQAAAA==.',
Io='Iolz:BAAALgAECgYJCgAAAA==.',
Ir='Ironfist:BAABLgAECn8+AAIgAAkJaSTPAQBKAwAgAAkJaSTPAQBKAwAAAA==.',
It='Itankworlds:BAAALgAECgUJBQABLgAECgcJDgABAAAAAA==.',
Iw='Iwanaplay:BAAALgAECgMJAwAAAA==.',
Ja='Jacolynn:BAABLgAECn8YAAIXAAcJ7BHsKwBXAQAXAAcJ7BHsKwBXAQAAAA==.Jaenei:BAAALgAECgcJDwAAAA==.',
Je='Jelly:BAAALgADCgIJAgAAAA==.',
Ji='Jinrok:BAAALgAECgUJBgAAAA==.',
Jo='Joansnow:BAAALgAECgIJAgABLgAECgkJIAAXAIQSAA==.Joatmoa:BAACLgAFFH8GAAIDAAMJNRRPDQDbAAADAAMJNRRPDQDbAAAuAAQKfxQAAgMACQmIHJ0PALYBAAMACQmIHJ0PALYBAAAA.Joeexotics:BAAALgADCgkJDAAAAA==.Jordanleah:BAAALgAECgQJBAAAAA==.',
Ju='July:BAAALgAECgcJEAAAAA==.Julytonidas:BAAALgAECgcJBwAAAA==.Jurac:BAAALgADCgcJGwAAAA==.',
Ka='Kaelnis:BAAALgAECggJEgAAAA==.Kaimargonar:BAABLgAECn8ZAAIQAAgJbBJcCwCGAQAQAAgJbBJcCwCGAQAAAA==.Kaitoi:BAABLgAECn8fAAMDAAgJRR4fBwBnAgADAAgJRR4fBwBnAgAFAAUJKwixSgB4AAAAAA==.Kalinth:BAAALgADCgIJAgAAAA==.Kallah:BAACLgAFFH8bAAISAAcJwhxYBwBAAgASAAcJwhxYBwBAAgAuAAQKfzcAAhIACQnsI44BAGsDABIACQnsI44BAGsDAAAA.Kalthos:BAABLgAECn9AAAMjAAkJHBntCABYAgAjAAgJjxntCABYAgAVAAkJnBFsBwDCAQAAAA==.Kamakizeg:BAACLgAFFH8FAAITAAIJIQ2ojgCNAAATAAIJIQ2ojgCNAAAuAAQKfy4AAhMACQmYE+xPANYBABMACQmYE+xPANYBAAAA.Kamayla:BAAALgADCgYJBgAAAA==.Karnus:BAAALgADCgUJBQAAAA==.Kaspen:BAAALgADCgMJAwAAAA==.Kateria:BAABLgAECn8nAAIYAAkJKR3vIACYAgAYAAkJKR3vIACYAgAAAA==.',
Ke='Kestrelle:BAAALgAECgcJEwABLgAECgkJUwAdAAkSAA==.Keyzeus:BAABLgAECn8lAAMVAAgJCxiBBgDiAQAVAAgJCxiBBgDiAQAkAAEJ5xuvhABOAAAAAA==.',
Kh='Khas:BAAALgADCgkJGgAAAA==.Khui:BAACLgAFFH8bAAIXAAYJSyUKCQBqAgAXAAYJSyUKCQBqAgAuAAQKfyUAAxcACAkWJcACAFcDABcACAkWJcACAFcDABYAAwkwGH5RAL8AAAAA.',
Ki='Kiarorin:BAAALgAECgEJAQAAAA==.Killerdeath:BAAALgAECgQJBwAAAA==.Kipziep:BAAALgAECgIJAgAAAA==.',
Kn='Knìghtmàrè:BAACLgAFFH8VAAMNAAcJ6BcLIgDaAQANAAYJ6BcLIgDaAQAfAAEJAAB9UwAAAAAuAAQKfygAAg0ACQn9INMSAAsDAA0ACQn9INMSAAsDAAAA.Kníghtfíst:BAABLgAECn8rAAIXAAkJ/ReqFQBnAgAXAAkJ/ReqFQBnAgABLgAFFAcJFQANAOgXAA==.',
Ko='Koltharaz:BAAALgAECgEJAQAAAA==.Korheo:BAAALgADCgUJBQAAAA==.Korloff:BAAALgAECgcJDQABLgAECgcJHAABAAAAAQ==.Kozan:BAAALgAECgcJHAAAAQ==.',
Kr='Krankthas:BAAALgAECgEJAQABLgAECgIJBAABAAAAAA==.Krazysniper:BAABLgAECn8oAAMIAAgJCRx0LwAaAgAIAAcJEB90LwAaAgAlAAEJ4wkqYQA3AAAAAA==.Krokk:BAABLgAECn8UAAIHAAcJ9QeXUwDmAAAHAAcJ9QeXUwDmAAAAAA==.Kruulock:BAAALgADCgcJBwAAAA==.',
Ku='Kungfister:BAAALgAECgEJAQAAAA==.Kur:BAAALgAFFAEJAQABLgAFFAUJEgABAAAAAQ==.',
La='Laatt:BAABLgAECn8aAAMTAAgJFh66KgB5AgATAAgJFh66KgB5AgASAAYJOBimOgBcAQAAAA==.Lacosanostra:BAAALgAECgYJCwAAAA==.Laeiny:BAAALgADCgYJBgAAAA==.Lateralus:BAAALgAECgUJBgABLgAECggJGgATABYeAA==.Latharel:BAAALgAECgEJAQAAAA==.Lawluss:BAABLgAECn8nAAIIAAcJ5hnNTQC0AQAIAAcJ5hnNTQC0AQAAAA==.Layethelor:BAAALgAECgEJBAAAAA==.',
Le='Legacyshot:BAAALgAECgkJJAAAAQ==.Leigola:BAAALgADCgUJCQAAAA==.Lela:BAAALgAECgYJBgAAAA==.Lezsul:BAAALgAECgIJAgAAAA==.',
Li='Lickthecrit:BAAALgAECggJEgAAAA==.Lidrelle:BAABLgAECn8fAAITAAcJAhJnkgBLAQATAAcJAhJnkgBLAQAAAA==.Lightguard:BAAALgAECgYJCwAAAA==.Lighthouse:BAABLgAECn8uAAITAAkJlxtJNAAtAgATAAkJlxtJNAAtAgAAAA==.Lileth:BAAALgAECgUJBQAAAA==.Lilpaws:BAAALgAECgYJBgAAAA==.Lizy:BAAALgADCgUJBQAAAA==.',
Lo='Locust:BAAALgAECgMJAwAAAA==.Lokkar:BAAALgADCgQJBAAAAA==.Lolalazer:BAABLgAECn8WAAILAAgJ9RU0WgB1AQALAAgJ9RU0WgB1AQAAAA==.Lolhahabaha:BAAALgAECggJDAAAAA==.Loopie:BAAALgADCgYJCgAAAA==.Lovesomev:BAAALgADCgMJAwAAAA==.',
Lu='Luckÿ:BAABLgAECn8XAAIfAAcJlxXdIgA5AQAfAAcJlxXdIgA5AQAAAA==.Lunabelle:BAAALgADCgEJAQAAAA==.Lunchbox:BAAALgAECgkJAQAAAA==.Lustfull:BAAALgAECgEJAgABLgAECgkJHwAIAPgfAA==.',
Ly='Lypally:BAABLgAECn9AAAITAAkJshLcRgDvAQATAAkJshLcRgDvAQAAAA==.',
['Lï']='Lïllïth:BAAALgADCgIJAgAAAA==.',
['Ló']='Lóla:BAABLgAECn8wAAILAAkJziPbBwAQAwALAAkJziPbBwAQAwAAAA==.',
['Lô']='Lônè:BAAALgAECgUJBwAAAA==.',
Ma='Maani:BAAALgAECgEJAQAAAA==.Madeah:BAACLgAFFH8oAAMOAAgJGRbFBABnAgAOAAgJGRbFBABnAgAPAAYJOw8QAwBzAQAuAAQKfyEAAw4ACAlGHtkMAMsCAA4ACAlGHtkMAMsCAA8AAQnoGt8aAFEAAAAA.Mahimahi:BAAALgAECggJCAAAAA==.Malýs:BAAALgAECgEJAQAAAA==.Mardain:BAABLgAECn8fAAImAAkJphUYCgAVAgAmAAkJphUYCgAVAgAAAA==.Mariacuras:BAABLgAECn8WAAISAAkJ7AqDMACUAQASAAkJ7AqDMACUAQAAAA==.Marle:BAABLgAECn8yAAILAAkJqhdrKAAlAgALAAkJqhdrKAAlAgAAAA==.Marlete:BAAALgADCgYJBQAAAA==.Marshoon:BAAALgAECgUJBwAAAA==.Martis:BAAALgAECgYJBwAAAA==.Marynne:BAABLgAECn9TAAMdAAkJCRIFLgDsAQAdAAkJCRIFLgDsAQAEAAEJSwJYqQAMAAAAAA==.Matthis:BAAALgAECgUJBwAAAA==.Mazuko:BAABLgAECn8wAAIKAAkJUBcXBwASAgAKAAkJUBcXBwASAgAAAA==.',
Mc='Mcdo:BAAALgAECgQJBAABLgAFFAYJFAAnALAhAA==.',
Me='Medadh:BAAALgADCgUJBQAAAA==.Meepe:BAAALgADCgcJDAAAAA==.Meilnesar:BAAALgAECgIJAgAAAA==.Melaerissa:BAABLgAECn8wAAMbAAgJhQ8WKQCGAQAbAAgJhQ8WKQCGAQAMAAUJxQzsTACqAAAAAA==.Melbrooks:BAAALgADCgcJDQAAAA==.Melivant:BAABLgAECn8aAAMTAAYJJxmVewB1AQATAAYJJxmVewB1AQASAAQJwhENVwDYAAAAAA==.Merrikeath:BAAALgAECggJEwAAAA==.Merriklade:BAABLgAECn8zAAMZAAkJAA/RFgCKAQAZAAkJRw7RFgCKAQARAAgJygogTAAVAQAAAA==.',
Mi='Missyjelliot:BAAALgAECgYJCQAAAA==.',
Mo='Monster:BAAALgADCgEJAQAAAA==.Moof:BAAALgADCgEJAQAAAA==.Morbidstyle:BAAALgAECgQJBQAAAA==.Morchuk:BAAALgADCgMJAwAAAA==.Morigith:BAAALgAECgMJAwABLgAECgUJBgABAAAAAA==.Morthos:BAAALgAECgMJBgAAAA==.',
Mw='Mw:BAAALgADCgIJAgABLgAECgcJHQASALEfAA==.',
My='Myora:BAEBLgAECn8UAAIOAAgJ4BDMGwC0AQAOAAgJ4BDMGwC0AQABLgAECgkJKwAVACQXAA==.Mythundirus:BAAALgADCgMJAwAAAA==.',
['Mà']='Màrli:BAAALgAECgcJDwAAAA==.',
['Mâ']='Mâgs:BAABLgAECn8gAAIiAAkJWhKREQCpAQAiAAkJWhKREQCpAQAAAA==.',
Na='Nabbed:BAAALgAECgcJCAABLgAECgkJKQAUADUeAA==.Nakasid:BAACLgAFFH8KAAIMAAMJYxEcIQCrAAAMAAMJYxEcIQCrAAAuAAQKfzUABAwACQnWFxwRAFcCAAwACQnWFxwRAFcCABsABwkVCNQ5ACIBACEABAlbCtxZAJMAAAAA.Nalaya:BAAALgAECgEJAQAAAA==.Nashoba:BAAALgADCgQJBAAAAA==.Natooka:BAAALgAECggJDgAAAA==.Navane:BAAALgAECgUJBwAAAA==.',
Ne='Necromaniac:BAAALgAECgEJAQAAAA==.Neenja:BAAALgADCgYJBgAAAA==.Nefurtatta:BAAALgADCgEJAQAAAA==.Nertlogi:BAAALgADCgIJAgAAAA==.Nesrÿn:BAAALgADCgIJAgAAAA==.Nestina:BAAALgADCgMJBAAAAA==.Netherkeeper:BAABLgAECn8rAAILAAkJsBABQwC8AQALAAkJsBABQwC8AQAAAA==.Nevaehstar:BAABLgAECn85AAIcAAkJoB+2AADuAgAcAAkJoB+2AADuAgAAAA==.Neverëst:BAAALgAECgEJAQAAAA==.',
Ni='Nibuto:BAAALgAECgQJCwAAAA==.Nightvision:BAAALgADCgMJAgAAAA==.Nijun:BAEBLgAECn8uAAIMAAkJOxR6HwDDAQAMAAkJOxR6HwDDAQAAAA==.Nikolia:BAAALgAECgUJCAAAAA==.Ninetynine:BAAALgADCgMJAwAAAA==.Nini:BAABLgAECn8hAAIEAAgJZwLpXACeAAAEAAgJZwLpXACeAAAAAA==.Ninx:BAAALgAECgQJBAAAAA==.Nirazal:BAAALgADCgQJBQAAAA==.',
No='Noivana:BAAALgAFFAMJAwABLgAFFAUJEAAJANcSAA==.Nokru:BAAALgADCgMJBQAAAA==.Norgannia:BAAALgADCgkJDwAAAA==.Notprepared:BAAALgADCgEJAQAAAA==.Noys:BAAALgADCgcJDAAAAA==.',
Nz='Nzuul:BAAALgAECgQJBwAAAA==.',
Ol='Oldbenkenobi:BAAALgAECgQJCAAAAA==.Ollichi:BAAALgADCgQJBAAAAA==.Ollifuzzle:BAAALgAECgEJAwAAAA==.',
Om='Ominous:BAAALgAECgMJAwAAAA==.',
Op='Oppaissiah:BAABLgAECn9EAAMZAAkJ6iM7AgAmAwAZAAkJlSM7AgAmAwARAAkJ8R+9CQDGAgAAAA==.',
Or='Oraclespyro:BAABLgAECn8XAAIkAAYJawJwdAB5AAAkAAYJawJwdAB5AAABLgAECgkJDwABAAAAAA==.Orlakx:BAAALgADCggJFAAAAA==.Orman:BAAALgAECgEJAQAAAA==.',
Os='Osoroshi:BAAALgAECgQJBAAAAA==.',
Ov='Ovrind:BAAALgADCgEJAQAAAA==.',
Oz='Ozài:BAAALgADCgcJCgAAAA==.',
Pa='Padmê:BAAALgAECgcJDAAAAA==.Pandamared:BAAALgADCggJCgAAAA==.Papasbich:BAAALgAECgcJEwABLgAECgkJSQATABkVAA==.Patronous:BAAALgADCgUJBgAAAA==.',
Pe='Percthirty:BAAALgAECgEJAgAAAA==.Permafrost:BAAALgADCggJCgAAAA==.Perscila:BAAALgADCgUJBQAAAA==.',
Pi='Piggy:BAAALgAECgQJBgAAAA==.',
Pl='Planet:BAAALgADCgEJAQAAAA==.',
Po='Porkchoplust:BAAALgAECgEJAQAAAA==.Porkchopw:BAAALgAECgcJAQAAAA==.Porkribs:BAAALgAFFAIJAgAAAA==.',
Pr='Presap:BAABLgAECn8tAAMdAAkJ5SAkBwBCAwAdAAkJ5SAkBwBCAwAEAAEJAACrdgBJAAABLgAECgkJGAAjAKwcAA==.Promethius:BAAALgADCgQJBAAAAA==.Proscris:BAAALgADCgUJBQAAAA==.Prïsm:BAAALgADCgYJBgAAAA==.',
Pt='Ptmuchuk:BAAALgADCgYJBgAAAA==.',
Pu='Puca:BAABLgAECn8VAAIDAAUJVBirHAAfAQADAAUJVBirHAAfAQAAAA==.Pumdmuc:BAACLgAFFH8LAAIMAAQJCRx/EABHAQAMAAQJCRx/EABHAQAuAAQKf0QAAwwACQnlIdoGAN8CAAwACQnlIdoGAN8CABsABwkqBUZSAMYAAAAA.Purrie:BAAALgADCgIJAgAAAA==.',
['Pâ']='Pâlly:BAAALgAECgcJEAAAAA==.',
Qu='Quikglaives:BAAALgAFFAIJAgAAAA==.Quille:BAABLgAECn8dAAIIAAgJSiNxDgDaAgAIAAgJSiNxDgDaAgAAAA==.',
Ra='Rahhem:BAABLgAECn8eAAIiAAkJrRIqEQCuAQAiAAkJrRIqEQCuAQAAAA==.Rallo:BAAALgAECgEJAQAAAA==.Rayspaly:BAAALgAECgMJBAAAAA==.',
Re='Recbra:BAAALgAECgIJAgAAAA==.Reddelish:BAAALgADCgYJCQAAAA==.Redrek:BAAALgADCggJFgAAAA==.Redsbank:BAAALgADCgMJAwAAAA==.Redshunter:BAAALgADCgcJDAAAAA==.Redsknight:BAAALgADCgkJCQAAAA==.Redsmonk:BAAALgADCgYJCgAAAA==.Redwinter:BAAALgAECgIJBAABLgAECggJHwARAPcbAA==.Reikisong:BAAALgAECgMJBAAAAA==.Remmie:BAAALgAECgYJDAAAAA==.Retrolbution:BAAALgADCgkJEQAAAA==.Reylia:BAAALgAECgMJAwAAAA==.Reznik:BAAALgAECgEJAQAAAA==.',
Rh='Rhagurion:BAAALgAECggJCQAAAA==.Rhaokir:BAAALgADCgIJAgAAAA==.',
Ri='Riqua:BAABLgAECn8lAAIdAAgJJhQLLwDmAQAdAAgJJhQLLwDmAQAAAA==.',
Ro='Rockmonsta:BAAALgAECgUJCAAAAA==.Rodeo:BAABLgAECn8sAAIEAAkJABCqIgCwAQAEAAkJABCqIgCwAQAAAA==.Rotgutwiskey:BAAALgAECgIJAgAAAA==.Roxies:BAAALgAFFAEJAQAAAA==.Royan:BAAALgAECgcJDQAAAA==.',
Rp='Rpg:BAAALgAECgcJDgAAAA==.',
Ru='Rumie:BAABLgAECn8bAAILAAYJeQ6eegA4AQALAAYJeQ6eegA4AQAAAA==.Runty:BAAALgADCgMJAwAAAA==.',
Sa='Sacket:BAAALgAECgcJCgAAAA==.Sadnhornless:BAAALgAECgEJAwAAAA==.Saeti:BAACLgAFFH8PAAMDAAQJbRvACgD/AAADAAMJbRzACgD/AAAEAAEJbxhqRwBMAAAuAAQKfz4ABQMACQlIIZYHAG8CAAMACQlAIZYHAG8CAAQABgmdG54qAHsBAAUABAk2HlIqAAQBAB0ABAkUFm2HAKYAAAAA.Sandril:BAAALgAECgcJDAAAAA==.Sapplesauce:BAABLgAECn8XAAIOAAgJ5BfFHQCkAQAOAAgJ5BfFHQCkAQAAAA==.',
Sc='Scryer:BAAALgAECgEJAQAAAA==.',
Se='Serenìty:BAAALgAECggJDQAAAA==.Seresin:BAACLgAFFH8HAAMdAAMJ6wWNTwB9AAAdAAMJ6wWNTwB9AAAEAAEJ4wbWTgA0AAAuAAQKf1AAAx0ACQnHHdALAAADAB0ACQnHHdALAAADAAQABgmbE9c3ADEBAAAA.',
Sh='Shadý:BAABLgAECn8vAAIIAAkJ5ApdVACiAQAIAAkJ5ApdVACiAQAAAA==.Shamanoodles:BAAALgAECgEJAQABLgAECgkJKQANAOgkAA==.Shinbin:BAAALgAECgEJAgAAAA==.Shonna:BAABLgAECn8oAAQQAAgJLBpGCwCIAQAGAAgJ1hd0QwDQAQAQAAcJeBhGCwCIAQAeAAIJERlTLQBEAAAAAA==.Shortwarrior:BAABLgAECn8/AAIRAAkJohwUDgCNAgARAAkJohwUDgCNAgAAAA==.Shrimpimp:BAAALgAECgQJBAAAAA==.',
Si='Sianu:BAAALgAECgcJBwABLgAECgkJUwAdAAkSAA==.Sidarya:BAABLgAECn8UAAMMAAgJZReQGQD7AQAMAAgJZReQGQD7AQAbAAEJpQNBlQAhAAAAAA==.Sidera:BAAALgAECggJDgAAAA==.Siduna:BAAALgADCgEJAQAAAA==.Silent:BAACLgAFFH8SAAMRAAQJVhzcFABgAQARAAQJVhzcFABgAQAUAAEJPAz0PwBDAAAuAAQKfx4AAxQACQmjFs4ZACUBABEABwlxFetCADgBABQABgkoEs4ZACUBAAAA.Silverserket:BAAALgAECgIJBAAAAA==.Silverserqet:BAAALgAECgYJDAAAAA==.',
Sk='Skinnybutt:BAAALgADCgkJEQAAAA==.Skippinskipp:BAAALgAECgcJCwAAAA==.Skymaggedon:BAEBLgAECn9BAAMCAAkJPQ2ZSACIAQACAAkJPQ2ZSACIAQAHAAgJQAgJSQAMAQAAAA==.',
Sl='Slappadrago:BAAALgAECgkJEwAAAA==.',
Sm='Smileyriley:BAABLgAECn8aAAIEAAcJzQWSTgDOAAAEAAcJzQWSTgDOAAAAAA==.',
Sn='Sneakylinks:BAAALgAECgMJBQABLgAECgcJDgABAAAAAA==.Snotlocker:BAAALgAECgEJAQAAAA==.',
So='Sodexorod:BAAALgADCgYJBwAAAA==.Sofiophya:BAABLgAECn8VAAIXAAUJ7wOjkABtAAAXAAUJ7wOjkABtAAAAAA==.Sooki:BAAALgAECgIJAwAAAA==.Sorilea:BAAALgADCgcJCAAAAA==.Sorlis:BAAALgAECgcJEgAAAA==.Soulber:BAABLgAECn8XAAMNAAgJ1BRhVwC9AQANAAgJ2RNhVwC9AQAfAAIJnxx2OwChAAAAAA==.Sourdew:BAABLgAECn8eAAIWAAcJtB5SGQDjAQAWAAcJtB5SGQDjAQAAAA==.',
Sp='Sparkey:BAAALgAECgIJAgAAAA==.Spiritair:BAABLgAECn8YAAMjAAkJrBwTBADzAgAjAAkJrBwTBADzAgAVAAEJAABtLgAAAAAAAA==.Spunklestain:BAAALgADCggJDQABLgAECgkJEwABAAAAAA==.Spyke:BAAALgADCgEJAQAAAA==.Spykids:BAAALgAECgQJBAAAAA==.',
Sr='Srix:BAAALgAECgEJAQAAAA==.',
St='Starrdust:BAEALgAECgUJCwAAAA==.Stelle:BAABLgAECn8XAAIhAAgJBBEYJABzAQAhAAgJBBEYJABzAQAAAA==.Sternhoof:BAAALgAECgIJAgAAAA==.Stylos:BAABLgAECn87AAImAAgJ6xYADADuAQAmAAgJ6xYADADuAQAAAA==.Stãrburst:BAABLgAECn8UAAMCAAgJZQrkeQDsAAACAAcJswfkeQDsAAAHAAEJUAS+uwAeAAAAAA==.',
Su='Subrinea:BAAALgAECgUJBQABLgAECgkJOQAcAKAfAA==.',
Sy='Sylven:BAAALgADCgYJBgABLgAECgkJJAAZAIwlAA==.',
Ta='Taissa:BAAALgADCggJCgAAAA==.Taopaípai:BAAALgADCgMJBgAAAA==.Tas:BAAALgAECgQJBAAAAA==.Tatertotz:BAAALgAECgcJEgAAAA==.',
Te='Technine:BAAALgADCgMJAwAAAA==.Techno:BAAALgAECgcJAQAAAA==.Tegbless:BAAALgAECgkJDgAAAA==.Tegchill:BAABLgAECn8dAAQfAAgJNBlhEwDZAQAfAAgJVBhhEwDZAQANAAgJBQ8oZwDAAQAaAAEJAACfGgAeAAABLgAECgkJDgABAAAAAA==.Tegmage:BAAALgAECgUJBQABLgAECgkJDgABAAAAAA==.Terentia:BAEALgAECgUJBQABLgAECgkJKwAVACQXAA==.',
Th='Thadind:BAAALgAECgEJAQAAAA==.Thalodrim:BAAALgAECgEJAQABLgAECgkJHQAGAOEdAA==.Tharelly:BAABLgAECn8XAAIYAAkJrxjlOgArAgAYAAkJrxjlOgArAgAAAA==.Thasserian:BAAALgADCgIJAgABLgAECgkJJAAZAIwlAA==.Theholymatt:BAACLgAFFH8SAAMSAAYJihbqFwBeAQASAAUJAxTqFwBeAQATAAQJmhOmcgDIAAAuAAQKfzgAAxMACQkpI0ILAAoDABMACQkpI0ILAAoDABIABwnnJEEPAJsCAAAA.Thendari:BAABLgAECn9pAAIQAAkJDBhKBAA4AgAQAAkJDBhKBAA4AgAAAA==.Theodus:BAABLgAECn8yAAIYAAkJhxmJNwA4AgAYAAkJhxmJNwA4AgAAAA==.Therayen:BAAALgADCgQJBAAAAA==.Theràpy:BAAALgAECgQJBQAAAA==.Thesmaugmatt:BAABLgAECn8UAAIkAAgJfxqtGwD3AQAkAAgJfxqtGwD3AQABLgAFFAYJEgASAIoWAA==.Thorrune:BAAALgAECgQJBAAAAA==.Threnor:BAABLgAECn83AAMUAAkJFyR1AgAgAwAUAAkJkyN1AgAgAwARAAcJZCP1IABLAgAAAA==.Thunderblade:BAAALgADCgIJAgAAAA==.',
Ti='Tialdari:BAAALgADCgYJBgAAAA==.Tiferis:BAACLgAFFH8SAAISAAUJwBoIEQCnAQASAAUJwBoIEQCnAQAuAAQKfz0AAhIACQn3IBQFAEEDABIACQn3IBQFAEEDAAAA.Tislam:BAABLgAECn8XAAIGAAgJ3A3BZgBvAQAGAAgJ3A3BZgBvAQAAAA==.Tizzeia:BAAALgADCgMJBQAAAA==.',
To='Toaster:BAABLgAECn8pAAQUAAkJNR7NBACaAgAUAAkJFhrNBACaAgAZAAcJpSBSDwDvAQARAAYJtx9dMgDiAQAAAA==.Tobes:BAAALgADCgEJAQAAAA==.Tobiquer:BAABLgAECn8/AAIMAAkJcxtqDACcAgAMAAkJcxtqDACcAgAAAA==.Toebackkey:BAAALgAECgEJAQAAAA==.Tojarmar:BAABLgAECn8XAAIZAAkJJBPCEwCwAQAZAAkJJBPCEwCwAQABLgAECgQJBAABAAAAAA==.Torolf:BAAALgAECgMJAwAAAA==.',
Tr='Trauglodyte:BAAALgAECgYJBgAAAA==.Traydra:BAAALgAECgMJBAAAAA==.Triven:BAAALgAECgIJAgAAAA==.Troglodyte:BAACLgAFFH8dAAMHAAcJXRV3DQDDAQAHAAcJXRV3DQDDAQACAAEJYAx4dgBLAAAuAAQKf0gAAgcACQnMIqMEABUDAAcACQnMIqMEABUDAAAA.',
Ts='Tsonokwabain:BAABLgAECn8mAAQaAAkJhyKUAQAbAwAaAAkJhyKUAQAbAwAfAAEJah0fUwBIAAANAAEJmAIOngEYAAAAAA==.Tsunami:BAAALgADCgYJCAAAAA==.',
Tw='Twistdog:BAAALgAECgEJAwAAAA==.',
Ty='Tyranastrasz:BAABLgAECn8yAAMjAAkJ7hFBDwDUAQAjAAkJ7hFBDwDUAQAVAAEJ6gZmKAAqAAAAAA==.Tyye:BAAALgAECgEJAQAAAA==.',
['Tâ']='Tâjik:BAABLgAECn8kAAIOAAkJ4QURKABSAQAOAAkJ4QURKABSAQAAAA==.',
Ud='Udderlytasty:BAAALgAECgEJAQAAAA==.',
Un='Unc:BAAALgAECgcJCAAAAA==.',
Va='Vade:BAAALgAFFAEJAwAAAA==.Vaelith:BAAALgAECggJDAAAAA==.Vaelyra:BAABLgAECn8uAAILAAgJOxgbTQCbAQALAAgJOxgbTQCbAQAAAA==.Vaerryn:BAABLgAECn8mAAQaAAgJMyNaBgA+AgAaAAcJFiNaBgA+AgANAAMJcBtm0ADlAAAfAAIJQyBiUABQAAAAAA==.Vaethund:BAAALgAECggJEQAAAA==.Vailenya:BAAALgADCgEJAQABLgAECggJHAAKAFMfAA==.Valgavoth:BAAALgAECggJEwAAAA==.Vandrin:BAAALgADCgQJBgAAAA==.Vapir:BAAALgAECgMJAwAAAA==.Variala:BAABLgAECn8XAAMlAAgJig2lJwBiAQAlAAcJxQylJwBiAQAIAAcJPQsm0ACjAAAAAA==.Vassyra:BAEBLgAECn8rAAIVAAkJJBc7BQANAgAVAAkJJBc7BQANAgAAAA==.',
Ve='Velara:BAAALgAECgcJCAAAAA==.Velesyn:BAABLgAECn8cAAMKAAgJUx83BwAOAgAKAAcJKCA3BwAOAgALAAIJtxG8+QBOAAAAAA==.Vellayna:BAAALgADCgYJBgAAAA==.',
Vi='Vilga:BAAALgADCgkJCQAAAA==.Viral:BAAALgAECgYJDwAAAA==.Viriex:BAAALgADCgEJAQAAAA==.Visone:BAAALgADCgEJAQAAAA==.Vitoria:BAAALgAECgEJAQAAAA==.',
Vo='Vocivus:BAAALgAECggJEwAAAA==.Voidlighter:BAACLgAFFH8GAAIhAAMJqhFfMADIAAAhAAMJqhFfMADIAAAuAAQKfygAAyEACQlbGRkMAKoCACEACQlbGRkMAKoCABsACAnVF5gZAPgBAAAA.Volundr:BAABLgAECn88AAIZAAkJ7xi+DQAMAgAZAAkJ7xi+DQAMAgAAAA==.Vonvaughan:BAAALgADCgcJCwABLgAECggJFwAWAOMhAA==.',
Vy='Vynel:BAAALgADCgQJBAABLgAECgkJJAAZAIwlAA==.Vynirion:BAABLgAECn8UAAIYAAcJqxJUpACPAQAYAAcJqxJUpACPAQAAAA==.Vynisa:BAAALgAECgMJAwAAAA==.',
Wa='Waiseheil:BAAALgADCggJCQAAAA==.Warcreaper:BAABLgAECn8bAAIOAAkJAwZ6IwB0AQAOAAkJAwZ6IwB0AQAAAA==.Wardellmo:BAAALgAECgEJAQAAAA==.Wargtar:BAABLgAECn8zAAIOAAcJdyG1DQBJAgAOAAcJdyG1DQBJAgAAAA==.Warlockbob:BAAALgAECgYJCwAAAA==.',
We='Weabe:BAABLgAECn8YAAMMAAcJFhGmNQAmAQAMAAcJ9w+mNQAmAQAhAAIJpRHjSgBqAAAAAA==.Weebes:BAAALgAECggJDwAAAA==.',
Wh='Whiterrina:BAAALgADCgkJCgAAAA==.',
Wo='Woobee:BAAALgADCgEJAQAAAA==.',
Wy='Wyrdhoof:BAABLgAECn8iAAMEAAkJ9AiHMQBSAQAEAAkJ9AiHMQBSAQAdAAUJEgeVigCfAAAAAA==.',
['Wù']='Wùsthof:BAABLgAECn8eAAIIAAkJywobVgBmAQAIAAkJywobVgBmAQAAAA==.',
Xa='Xandrios:BAAALgADCgMJAwAAAA==.Xaron:BAAALgADCgMJAwAAAA==.',
Xi='Xiae:BAABLgAECn8zAAMCAAkJiCPLDADvAgACAAgJsSPLDADvAgAHAAcJChfRKAClAQAAAA==.',
Xk='Xkwizet:BAABLgAECn8aAAIYAAgJPgfWngA6AQAYAAgJPgfWngA6AQAAAA==.',
Xo='Xorrin:BAAALgAECgYJDgAAAA==.',
Xy='Xylpho:BAAALgAECgEJAQAAAA==.',
Ye='Yet:BAABLgAECn8uAAITAAkJpCThBQBCAwATAAkJpCThBQBCAwAAAA==.',
Yi='Yiffweaver:BAABLgAECn8rAAIgAAkJ0wl9KwBaAQAgAAkJ0wl9KwBaAQAAAA==.',
Yo='Yokoriazen:BAABLgAECn8zAAIiAAkJRxMVEAC/AQAiAAkJRxMVEAC/AQAAAA==.',
Yu='Yurtnaut:BAAALgAECgYJDgAAAA==.',
Yv='Yvesass:BAAALgAECggJEwAAAA==.',
Za='Zarhianna:BAABLgAECn8jAAIEAAkJgBBnIQC5AQAEAAkJgBBnIQC5AQAAAA==.',
Ze='Zeo:BAAALgAECgEJAQAAAA==.Zephnor:BAAALgADCgIJAgAAAA==.',
Zm='Zmona:BAABLgAECn8xAAITAAkJHg8XZQCjAQATAAkJHg8XZQCjAQAAAA==.',
Zo='Zorsche:BAAALgADCgcJEQAAAA==.',
Zu='Zulrok:BAABLgAECn8tAAIRAAkJbB2CEgBdAgARAAkJbB2CEgBdAgAAAA==.',
['Åv']='Åviendha:BAAALgADCgcJCAAAAA==.',
['Ðr']='Ðre:BAABLgAECn8VAAIYAAcJ0hZswwBfAQAYAAcJ0hZswwBfAQAAAA==.',
['Ût']='Ûther:BAABLgAECn8VAAITAAYJ6wNACQGpAAATAAYJ6wNACQGpAAAAAA==.',
['Ül']='Ültimecia:BAABLgAECn8uAAIYAAkJUiNVFADdAgAYAAkJUiNVFADdAgAAAA==.',
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
