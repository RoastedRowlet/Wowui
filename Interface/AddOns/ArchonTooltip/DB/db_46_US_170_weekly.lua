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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Balance','Druid-Guardian','Shaman-Elemental','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Holy','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Warrior-Protection','DeathKnight-Frost','Priest-Shadow','Mage-Frost','Mage-Arcane','Druid-Restoration','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Priest-Discipline','Monk-Mistweaver','Evoker-Preservation','Hunter-Survival','Shaman-Enhancement','Paladin-Protection','Evoker-Augmentation',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Adunei:BAAALgAECgIJAgAAAA==.',
Ae='Aeginalla:BAAALgADCgcJEgABLgAECgYJCAABAAAAAA==.Aela:BAAALgADCgEJAQABLgAECggJKAACANAgAA==.Aesalon:BAABLgAECn8zAAQDAAgJhCTeAQDfAgADAAgJhCTeAQDfAgAEAAIJrRTjeQA+AAAFAAIJGBMpQAA1AAAAAA==.',
Ah='Ahsokatano:BAABLgAECn8oAAMCAAgJ0CCtCgDCAgACAAgJ0CCtCgDCAgAGAAEJ8gyseQAtAAAAAA==.',
Ai='Aimspet:BAAALgAECgUJBQAAAA==.Aircanada:BAAALgAECgIJAgAAAA==.',
Ak='Akela:BAABLgAECn8ZAAIHAAgJhwvSSABwAQAHAAgJhwvSSABwAQAAAA==.',
Al='Alissu:BAAALgADCgIJAgAAAA==.Alvonaar:BAAALgADCgIJAgAAAA==.',
Am='Ames:BAAALgADCgQJBAAAAA==.Amonet:BAAALgADCggJIgAAAA==.',
An='Anaelcheese:BAABLgAECn8aAAQIAAcJ2RTQFwBfAQAIAAcJ2RTQFwBfAQAJAAEJkg0sLgAnAAAKAAEJywAN9wATAAAAAA==.Anamis:BAABLgAECn8eAAILAAcJxxTSLwCDAQALAAcJxxTSLwCDAQAAAA==.Andrina:BAAALgADCgYJAgAAAA==.Angeldemon:BAAALgADCgYJCAAAAA==.Angras:BAABLgAECn8YAAIMAAgJnwiIaQBLAQAMAAgJnwiIaQBLAQAAAA==.Angryorc:BAAALgAECgQJBQAAAA==.Anja:BAAALgADCgkJEAAAAA==.Anolana:BAABLgAECn8tAAMNAAgJOSG6BwBlAgANAAgJOSG6BwBlAgAOAAEJixG0HQA6AAAAAA==.Anyday:BAAALgADCgcJBwAAAA==.',
Ap='Aphalock:BAAALgAECggJEAAAAA==.',
Ar='Ariûs:BAAALgAECgYJDAAAAA==.Arlin:BAAALgAECgMJBQAAAA==.Arlorian:BAABLgAECn8pAAIOAAgJLBBnCADKAQAOAAgJLBBnCADKAQAAAA==.Arorra:BAAALgADCgkJEQAAAA==.Arrex:BAAALgAECgUJBwAAAA==.Arrowsmites:BAABLgAECn8iAAIHAAgJ4BhRMADLAQAHAAgJ4BhRMADLAQAAAA==.',
Au='Aubani:BAABLgAECn8nAAMPAAgJkh/2CQCnAgAPAAgJkh/2CQCnAgAQAAIJURF/IwE6AAAAAA==.',
Ay='Ayperos:BAABLgAECn8sAAMRAAgJ0xtlBwAxAgARAAgJ0xtlBwAxAgASAAYJPxAVUgBhAQAAAA==.Ayvaria:BAAALgAECgUJDQABLgAECgkJKwATACQXAA==.',
Ba='Baboyago:BAAALgAECgUJBQAAAA==.Badgerbrew:BAAALgADCgkJCQAAAA==.Baked:BAAALgAECgQJBAABLgAECgcJDQABAAAAAA==.Bakedpally:BAAALgAECgcJDQAAAA==.Bandomar:BAABLgAECn8YAAIEAAcJwAh1MwDzAAAEAAcJwAh1MwDzAAAAAA==.Baniemo:BAAALgAECgIJAwAAAA==.Banigor:BAAALgAECgYJEAAAAA==.Basak:BAAALgAECgYJCAABLgAFFAQJDQABAAAAAQ==.',
Be='Beammescotty:BAAALgADCgQJBAAAAA==.Bearnuts:BAAALgADCgEJAQAAAA==.Beck:BAABLgAECn8gAAIQAAkJvR6/FACLAgAQAAkJvR6/FACLAgAAAA==.Beggars:BAAALgAECgYJCQAAAA==.Bereth:BAAALgAECgMJBQAAAA==.Berreydingle:BAAALgAECgMJBQAAAA==.',
Bi='Bigkitty:BAABLgAECn8pAAISAAgJ4xnuFQD1AQASAAgJ4xnuFQD1AQAAAA==.Biz:BAAALgADCgYJBwABLgAECgcJEAABAAAAAA==.',
Bl='Blackanvil:BAAALgAECgMJAwAAAA==.Blackautumn:BAAALgADCgcJDgABLgAECgcJHgASAKodAA==.Blainn:BAAALgAECgcJBwAAAA==.Blindfred:BAAALgAECggJDQAAAA==.Blitzedbust:BAAALgADCggJDQAAAA==.Bloodredsky:BAAALgAECggJEQAAAA==.Bloodymagi:BAAALgAECggJEwAAAA==.Bluesummer:BAABLgAECn8eAAQSAAcJqh2CHwCmAQASAAYJQiGCHwCmAQAUAAYJxBrAGQCCAQARAAEJCAzpQQA1AAAAAA==.',
Bo='Bolts:BAAALgAECgEJAwAAAA==.Boomin:BAABLgAECn8iAAIFAAgJshsBCAAOAgAFAAgJshsBCAAOAgAAAA==.',
Br='Brendameeks:BAAALgAECgQJAwAAAA==.Brewnashot:BAAALgADCggJCgAAAA==.Brewrain:BAAALgADCgEJAQAAAA==.Broadzinatl:BAAALgAECgcJEAAAAA==.Brom:BAAALgAECgIJAgAAAA==.Brïn:BAAALgAECgEJAQAAAA==.',
Bu='Bulwark:BAAALgADCgYJBgAAAA==.',
['Bã']='Bãthory:BAABLgAECn8XAAIVAAkJIxRTBwCqAQAVAAkJIxRTBwCqAQAAAA==.',
['Bø']='Bøss:BAAALgADCgkJEQAAAA==.',
Ca='Calvert:BAAALgAECgUJBgAAAA==.Captnhammer:BAAALgADCgUJBQAAAA==.Carebearr:BAAALgADCgcJBwAAAA==.Carnelian:BAAALgAECgIJAgAAAA==.Castration:BAABLgAECn8YAAIWAAYJ3AmwNgDoAAAWAAYJ3AmwNgDoAAAAAA==.',
Ce='Ceylan:BAABLgAECn8nAAMXAAgJZhfsPwDcAQAXAAgJZhfsPwDcAQAYAAEJVQMVIQAqAAAAAA==.',
Ch='Chadillac:BAAALgAECgMJAwAAAA==.Chaleb:BAAALgAECgMJBAAAAA==.Charavane:BAAALgAECgEJAQAAAA==.Charlz:BAABLgAECn8jAAMWAAkJhRbzEAADAgAWAAkJhRbzEAADAgALAAQJCxHLVQDfAAAAAA==.Charsifood:BAAALgAECgcJDwAAAA==.Chass:BAAALgADCgQJBAAAAA==.Cheatdr:BAABLgAECn8XAAIZAAYJbBF9RQAyAQAZAAYJbBF9RQAyAQAAAA==.Cheatpriest:BAABLgAECn8wAAILAAkJdRUeHACeAQALAAkJdRUeHACeAQAAAA==.Chesthyr:BAAALgADCgcJBwAAAA==.Chesto:BAABLgAECn8mAAQaAAgJ6hziBQC2AQAaAAcJ4xriBQC2AQAbAAYJvhT2awCKAQAcAAgJzRdPCwA8AQAAAA==.Chimken:BAAALgAECgEJAQABLgAECgkJKQARADceAA==.Chokea:BAAALgAECgkJCAAAAA==.Chrome:BAAALgAECgEJAQAAAA==.Chuwhee:BAAALgADCgYJBgAAAA==.',
Co='Cognition:BAABLgAECn81AAIHAAkJHyXzAQBSAwAHAAkJHyXzAQBSAwAAAA==.Coldvengance:BAABLgAECn8sAAISAAgJhQjkNgAdAQASAAgJhQjkNgAdAQAAAA==.Corpser:BAAALgADCgUJBQAAAA==.',
Cr='Cranki:BAAALgAECgUJBgABLgAECgIJAwABAAAAAA==.Cranknstein:BAAALgADCgQJBAABLgAECgIJAwABAAAAAA==.',
Cy='Cymindel:BAABLgAECn8xAAIdAAkJ2xgCCgDqAQAdAAkJ2xgCCgDqAQAAAA==.',
Da='Dad:BAAALgADCgQJBAAAAA==.Daelein:BAAALgADCgEJAQABLgADCgEJAQABAAAAAA==.Daithi:BAAALgAECgYJDwAAAA==.Dakotà:BAAALgAECgYJEQAAAA==.Darc:BAAALgAECgMJBAAAAA==.Darklite:BAAALgADCgUJCAAAAA==.Darkmonk:BAAALgADCgUJBQAAAA==.Dassadin:BAAALgAECgQJBQAAAA==.Day:BAABLgAECn8eAAIHAAcJYBnoPgCSAQAHAAcJYBnoPgCSAQAAAA==.',
De='Decaydence:BAAALgAECggJEAAAAA==.Dejno:BAABLgAECn8YAAISAAcJLyARHgCxAQASAAcJLyARHgCxAQAAAA==.Deleted:BAAALgADCgEJAQABLgAECggJFAAMAAQfAA==.Demonicly:BAAALgAECgYJDwAAAA==.Demönslayer:BAAALgAECgcJAwAAAA==.Derowski:BAAALgAECgQJBQAAAA==.Deroz:BAAALgADCgUJBQAAAA==.Dethra:BAAALgADCgQJBAAAAA==.Dezign:BAACLgAFFH8SAAIXAAUJph3UKQBiAQAXAAUJph3UKQBiAQAuAAQKfygAAhcACQl2ICoYAJACABcACQl2ICoYAJACAAAA.Dezígn:BAAALgAECgkJCgABLgAFFAUJEgAXAKYdAA==.',
Di='Diabolical:BAAALgAECgEJAQAAAA==.Discordegirl:BAABLgAECn8WAAMeAAYJQQwqQADBAAAeAAUJvA4qQADBAAAfAAEJVQIQhwAcAAAAAA==.Divinitÿ:BAAALgADCgIJAgABLgAECgkJLAAbAL8jAA==.',
Do='Dolgorukov:BAABLgAECn8jAAIHAAgJ2xBpRQB7AQAHAAgJ2xBpRQB7AQAAAA==.Dologony:BAABLgAECn8aAAIZAAgJ9g5aPABcAQAZAAgJ9g5aPABcAQAAAA==.',
Dr='Dracigor:BAAALgAECgIJAwAAAA==.Draconair:BAAALgADCgYJCAAAAA==.Dragonsbaine:BAAALgADCgMJAwAAAA==.Dragonz:BAAALgAECgMJBQAAAA==.Dre:BAAALgAECgMJBgAAAA==.Drikken:BAABLgAECn83AAMKAAkJwxkKIQALAgAKAAkJORcKIQALAgAJAAUJ2xudDgASAQAAAA==.Drmaker:BAAALgAECgMJAwAAAA==.Drougs:BAABLgAECn8sAAIIAAkJURhdDgDcAQAIAAkJURhdDgDcAQAAAA==.Druiddeleted:BAAALgAECgEJAQABLgAECggJFAAMAAQfAA==.',
Du='Dubbshot:BAAALgAECgEJAQAAAA==.Dumara:BAAALgADCgIJAgAAAA==.Durasan:BAAALgAECgYJEAAAAA==.Duressa:BAAALgAECgcJBwAAAA==.',
Dy='Dymund:BAAALgAECgEJAQAAAA==.',
['Dö']='Dötdötdead:BAABLgAECn8dAAMaAAgJYhLmCABtAQAaAAgJYhLmCABtAQAbAAIJZwuE0ABiAAAAAA==.',
Ea='Earthie:BAAALgADCgEJAQAAAA==.Earthstorm:BAAALgADCgIJAgAAAA==.Eastwubz:BAAALgADCgIJAgAAAA==.',
Ed='Edge:BAAALgAECgMJBQAAAA==.',
Ef='Effin:BAAALgADCgUJBQAAAA==.Effindin:BAAALgAECgEJAQAAAA==.Effinfu:BAABLgAECn8aAAIeAAgJfhDsIABjAQAeAAgJfhDsIABjAQAAAA==.',
Ei='Eitent:BAABLgAECn8wAAMPAAkJux3VBwDOAgAPAAkJux3VBwDOAgAQAAcJuhIRdgCOAQAAAA==.',
El='Ele:BAAALgADCgcJCAABLgAECgYJCAABAAAAAA==.Ellesthara:BAAALgAECgYJDgAAAA==.Ellysiaa:BAAALgAECgYJEQAAAA==.Elwynlana:BAAALgADCgYJBwAAAA==.Elysa:BAAALgADCgEJAQAAAA==.',
Em='Emberstorm:BAAALgAECgQJBQAAAA==.Emmakyn:BAABLgAECn8oAAMEAAgJ5RIgHACQAQAEAAgJ5RIgHACQAQAZAAcJMA3HRQAxAQAAAA==.',
En='Enezath:BAAALgADCgIJAgAAAA==.Entrerie:BAAALgADCgUJBQAAAA==.Enyxea:BAAALgAECgcJEAAAAA==.',
Ep='Ephemera:BAAALgAECgQJBwAAAA==.',
Er='Erikuh:BAAALgADCgEJAQAAAA==.Erodin:BAAALgADCgYJBgAAAA==.',
Es='Esmeray:BAAALgADCgYJBgABLgAECgkJKwATACQXAA==.Estala:BAAALgADCgUJBQAAAA==.',
Ey='Eyedontknow:BAAALgAECgYJEAAAAA==.Eyewana:BAABLgAECn8jAAIIAAgJpBJLFwBkAQAIAAgJpBJLFwBkAQAAAA==.',
Ez='Ezzka:BAAALgAECgcJDAAAAA==.',
Fa='Fakesaint:BAAALgAECgQJBAAAAA==.Fangalor:BAAALgAECgEJAgAAAA==.Farnsworth:BAAALgAECgUJBwABLgAECggJMwADAIQkAA==.Farzix:BAABLgAECn8hAAIGAAgJkwe+QwDOAAAGAAgJkwe+QwDOAAAAAA==.Façade:BAABLgAECn8mAAIMAAkJDxNnQgC3AQAMAAkJDxNnQgC3AQAAAA==.',
Fe='Feelgood:BAAALgADCgQJBAAAAA==.Fefifiona:BAABLgAECn8YAAIgAAgJdBhjDQBCAgAgAAgJdBhjDQBCAgAAAA==.Fefifredrich:BAAALgAECgIJAgABLgAECggJGAAgAHQYAA==.Felvira:BAABLgAECn8aAAMKAAcJcgPjoACJAAAKAAYJbQPjoACJAAAIAAMJzgLhegAoAAAAAA==.',
Fi='Finnw:BAAALgAECgYJCAAAAA==.Firelite:BAAALgAECgYJDwAAAA==.',
Fl='Flairlock:BAABLgAECn8uAAMcAAgJSx8xAwAlAgAcAAgJSx8xAwAlAgAaAAIJBhULLQA7AAAAAA==.Flee:BAABLgAECn8iAAINAAkJqhoJCABeAgANAAkJqhoJCABeAgAAAA==.',
Fo='Fookster:BAAALgAECgkJBgAAAA==.Forsetee:BAABLgAFFH8FAAIeAAIJTRfqMQCcAAAeAAIJTRfqMQCcAAAAAA==.',
Fr='Frowdawn:BAABLgAECn8tAAIOAAgJ+w7jBwCKAQAOAAgJ+w7jBwCKAQAAAA==.',
['Fí']='Físter:BAAALgAECgYJDgABLgAECgcJGgAMACoaAA==.',
Ga='Galadris:BAAALgADCgkJDwAAAA==.Garythenpc:BAAALgAECgMJBQAAAA==.Gaztoria:BAAALgADCggJCAABLgAECggJIQAMAIUhAA==.',
Ge='Genavieve:BAAALgADCgQJBAAAAA==.',
Gh='Ghøst:BAAALgADCgMJAwAAAA==.Ghøstlord:BAAALgADCgEJAQAAAA==.Ghøstslayer:BAAALgADCgEJAQAAAA==.',
Gi='Gilas:BAAALgADCgQJBAAAAA==.',
Gl='Glacialkitty:BAABLgAECn8gAAIZAAgJwAmORgAuAQAZAAgJwAmORgAuAQAAAA==.',
Go='Googoobler:BAABLgAECn8UAAIIAAcJ4AXAJwDXAAAIAAcJ4AXAJwDXAAAAAA==.Goudanight:BAAALgAECgMJBAABLgAECggJKQASAOMZAA==.Goudavibes:BAAALgAECgEJAQABLgAECggJKQASAOMZAA==.',
Gr='Greenmagus:BAAALgADCgMJBAAAAA==.Grenadon:BAAALgAECgIJAgAAAA==.Grimlilith:BAABLgAECn8bAAQcAAgJ/gSbEQATAQAcAAgJ9gSbEQATAQAbAAMJBAOS7AA+AAAaAAEJAAAogQALAAAAAA==.Grundy:BAAALgAECgUJCAAAAA==.',
Gu='Gumbi:BAAALgADCgIJAgAAAA==.',
Ha='Hadorya:BAABLgAECn8vAAIWAAgJjRkMEgD2AQAWAAgJjRkMEgD2AQAAAA==.Hakitua:BAABLgAECn8dAAIJAAgJAguQDwACAQAJAAgJAguQDwACAQAAAA==.Hangi:BAAALgADCgkJCQAAAA==.Happymeel:BAAALgAECgEJAQAAAA==.Harleyqûinn:BAAALgAECgYJBwAAAA==.Hazard:BAABLgAECn8vAAISAAgJ8QyKKQBlAQASAAgJ8QyKKQBlAQAAAA==.',
He='Healonwheels:BAAALgADCgMJAwAAAA==.Heimdall:BAAALgAECgUJBQABLgAECgkJLAAbAL8jAA==.Heis:BAAALgAECgMJBQAAAA==.Hellboii:BAAALgAECggJEwAAAA==.Heyitsrat:BAABLgAECn8uAAIQAAgJzhRYSACmAQAQAAgJzhRYSACmAQAAAA==.',
Hi='Hiko:BAAALgAECgkJAQAAAA==.',
Ho='Holo:BAACLgAFFH8SAAMCAAYJJgqFAgC9AQACAAYJJgqFAgC9AQAGAAUJFB/xCwBlAQAuAAQKfyEAAwYACQlzIWYDAG0DAAYACQlzIWYDAG0DAAIABwnXDgJCAHkBAAAA.Holos:BAAALgAECgEJAQABLgAFFAYJEgACACYKAA==.Holyangus:BAAALgAECgQJBwAAAA==.Holyyknight:BAAALgAECgcJEwAAAA==.',
Hu='Hugecrit:BAAALgADCgkJDwAAAA==.',
Ib='Ibbert:BAAALgADCgcJDAAAAA==.',
Ic='Icculus:BAABLgAECn8XAAIHAAcJPBSvRAB9AQAHAAcJPBSvRAB9AQAAAA==.',
Im='Impasse:BAAALgAECgkJBwAAAA==.',
In='Indaskyz:BAAALgADCgEJAQAAAA==.',
Io='Iolz:BAAALgAECgYJCgAAAA==.',
Ir='Ironfist:BAABLgAECn8qAAIeAAkJaSBhAwDtAgAeAAkJaSBhAwDtAgAAAA==.',
It='Itankworlds:BAAALgAECgUJBQABLgAECgcJDgABAAAAAA==.',
Ja='Jacolynn:BAABLgAECn8YAAIhAAcJ7BHsKwBXAQAhAAcJ7BHsKwBXAQAAAA==.Jaenei:BAAALgAECgYJCAAAAA==.',
Je='Jelly:BAAALgADCgIJAgAAAA==.',
Jo='Joatmoa:BAAALgAFFAIJAwAAAA==.Joeexotics:BAAALgADCgkJDAAAAA==.Jordanleah:BAAALgAECgQJBAAAAA==.',
Ju='July:BAAALgAECgYJCQAAAA==.Julytonidas:BAAALgAECgcJBwAAAA==.Jurac:BAAALgADCgcJFQAAAA==.',
Ka='Kaelnis:BAAALgAECggJCAAAAA==.Kaimargonar:BAAALgAECgUJCQAAAA==.Kaitoi:BAAALgAECgYJDwAAAA==.Kallah:BAACLgAFFH8VAAIPAAUJcx/8BwDOAQAPAAUJcx/8BwDOAQAuAAQKfzUAAg8ACQnsI44BAGsDAA8ACQnsI44BAGsDAAAA.Kalthos:BAABLgAECn8vAAMiAAgJLhf9CAAUAgAiAAgJLhf9CAAUAgATAAgJ/hCnBgCYAQAAAA==.Kamakizeg:BAABLgAECn8pAAIQAAgJjhN+UACPAQAQAAgJjhN+UACPAQAAAA==.Kamayla:BAAALgADCgYJBgAAAA==.Kaspen:BAAALgADCgMJAwAAAA==.Kateria:BAABLgAECn8ZAAIXAAgJlBg2QgDVAQAXAAgJlBg2QgDVAQAAAA==.',
Ke='Kestrelle:BAAALgAECgcJEwABLgAECggJLwAZAHgQAA==.Keyzeus:BAABLgAECn8XAAITAAcJWhbNBgCUAQATAAcJWhbNBgCUAQAAAA==.',
Kh='Khas:BAAALgADCgkJGgAAAA==.Khui:BAACLgAFFH8UAAIhAAUJUSXVBQAPAgAhAAUJUSXVBQAPAgAuAAQKfyUAAyEACAkWJcACAFcDACEACAkWJcACAFcDAB8AAwkwGE06AMoAAAAA.',
Ki='Kittkat:BAAALgADCgkJEAAAAA==.',
Kn='Knìghtmàrè:BAACLgAFFH8QAAMMAAUJnh8fHAAnAQAMAAQJnh8fHAAnAQAdAAEJAACgMwAAAAAuAAQKfyMAAgwACQmrINMSAAsDAAwACQmrINMSAAsDAAAA.Kníghtfíst:BAABLgAECn8gAAIhAAgJHxXgGwDAAQAhAAgJHxXgGwDAAQABLgAFFAUJEAAMAJ4fAA==.',
Ko='Koltharaz:BAAALgAECgEJAQAAAA==.Korheo:BAAALgADCgUJBQAAAA==.Korloff:BAAALgAECgcJDQABLgAECgcJHAABAAAAAQ==.Kozan:BAAALgAECgcJHAAAAQ==.',
Kr='Krazysniper:BAABLgAECn8dAAMHAAgJZBjIOwCdAQAHAAcJzxrIOwCdAQAjAAEJ4wkGTQA0AAAAAA==.Krokk:BAABLgAECn8UAAIGAAcJ9QflOgDzAAAGAAcJ9QflOgDzAAAAAA==.',
Ku='Kungfister:BAAALgAECgEJAQAAAA==.',
La='Laatt:BAABLgAECn8aAAMQAAgJFh66KgB5AgAQAAgJFh66KgB5AgAPAAYJOBjmKwBlAQAAAA==.Lacosanostra:BAAALgAECgUJBQAAAA==.Laeiny:BAAALgADCgYJBgAAAA==.Lateralus:BAAALgAECgUJBgABLgAECggJGgAQABYeAA==.Latharel:BAAALgAECgEJAQAAAA==.Lawluss:BAABLgAECn8eAAIHAAcJQBcRQACvAQAHAAcJQBcRQACvAQAAAA==.Layethelor:BAAALgAECgEJBAAAAA==.',
Le='Legacyshot:BAAALgAECgcJFQAAAQ==.Leigola:BAAALgADCgUJCQAAAA==.Lela:BAAALgAECgUJBQAAAA==.Lezsul:BAAALgADCgEJAQAAAA==.',
Li='Lickthecrit:BAAALgAECggJEgAAAA==.Lidrelle:BAAALgAECgcJDwAAAA==.Lighthouse:BAABLgAECn8uAAIQAAkJlxtLHgBPAgAQAAkJlxtLHgBPAgAAAA==.Lileth:BAAALgADCggJBgAAAA==.Lilpaws:BAAALgAECgYJBgAAAA==.Lizy:BAAALgADCgUJBQAAAA==.',
Lo='Locust:BAAALgAECgMJAwAAAA==.Lokkar:BAAALgADCgQJBAAAAA==.Lolalazer:BAABLgAECn8WAAIKAAgJ9BV6QwBxAQAKAAgJ9BV6QwBxAQAAAA==.Lolhahabaha:BAAALgAECgMJAwAAAA==.Loopie:BAAALgADCgUJBQAAAA==.Lovesomev:BAAALgADCgMJAwAAAA==.',
Lu='Luckÿ:BAABLgAECn8XAAIdAAcJlxVrGwATAQAdAAcJlxVrGwATAQAAAA==.Lunabelle:BAAALgADCgEJAQAAAA==.Lunchbox:BAAALgAECgkJAQAAAA==.Lustfull:BAAALgAECgEJAgABLgAECggJFAAHALseAA==.',
Ly='Lypally:BAABLgAECn8WAAIQAAgJGQcqlgD+AAAQAAgJGQcqlgD+AAAAAA==.',
['Ló']='Lóla:BAABLgAECn8rAAIKAAgJTSSrCgC9AgAKAAgJTSSrCgC9AgAAAA==.',
['Lô']='Lônè:BAAALgAECgUJBwAAAA==.',
Ma='Maani:BAAALgAECgEJAQAAAA==.Madeah:BAACLgAFFH8dAAMOAAcJQRVCAQCdAQANAAYJDhf7BACwAQAOAAYJOw9CAQCdAQAuAAQKfyEAAw0ACAlGHtkMAMsCAA0ACAlGHtkMAMsCAA4AAQnoGt8aAFEAAAAA.Mahimahi:BAAALgAECggJBwAAAA==.Malýs:BAAALgAECgEJAQAAAA==.Mardain:BAABLgAECn8VAAIkAAgJ3w4FDQB3AQAkAAgJ3w4FDQB3AQAAAA==.Mariacuras:BAAALgAECgUJCQAAAA==.Marle:BAABLgAECn8qAAIKAAgJcxYkNQCoAQAKAAgJcxYkNQCoAQAAAA==.Marlete:BAAALgADCgYJBQAAAA==.Marshoon:BAAALgADCgkJKgAAAA==.Martis:BAAALgAECgYJBwAAAA==.Marynne:BAABLgAECn8vAAIZAAgJeBD9NACAAQAZAAgJeBD9NACAAQAAAA==.Matthis:BAAALgAECgUJBwAAAA==.Mazuko:BAABLgAECn8jAAIJAAgJCxOZCACVAQAJAAgJCxOZCACVAQAAAA==.',
Me='Medadh:BAAALgADCgUJBQAAAA==.Meepe:BAAALgADCgcJDAAAAA==.Meilnesar:BAAALgAECgIJAgAAAA==.Melaerissa:BAABLgAECn8gAAMWAAcJHgyoKQAwAQAWAAcJHgyoKQAwAQALAAUJxQwfPAC4AAAAAA==.Melbrooks:BAAALgADCgcJDQAAAA==.Melivant:BAAALgAECgMJBgABLgAECgQJBwABAAAAAA==.Merriklade:BAABLgAECn8aAAISAAYJcQk3QwDmAAASAAYJcQk3QwDmAAAAAA==.',
Mi='Missyjelliot:BAAALgAECgQJBwAAAA==.',
Mo='Moof:BAAALgADCgEJAQAAAA==.Morthos:BAAALgAECgMJAwAAAA==.',
Mw='Mw:BAAALgADCgIJAgABLgAECgYJCAABAAAAAA==.',
['Mà']='Màrli:BAAALgAECgEJAQAAAA==.',
['Mâ']='Mâgs:BAABLgAECn8bAAIlAAgJnxLVDwBwAQAlAAgJnxLVDwBwAQAAAA==.',
Na='Nabbed:BAAALgAECgIJAgABLgAECgkJKQARADceAA==.Nakasid:BAABLgAECn8rAAQLAAkJEhFbHwCCAQALAAkJ7A5bHwCCAQAWAAcJFQjUOQAiAQAgAAQJWwpiPwCcAAAAAA==.Nalaya:BAAALgAECgEJAQAAAA==.Nashoba:BAAALgADCgQJBAAAAA==.Natooka:BAAALgAECggJDgAAAA==.Navane:BAAALgAECgEJAQAAAA==.',
Ne='Neenja:BAAALgADCgYJBgAAAA==.Nefurtatta:BAAALgADCgEJAQAAAA==.Nertlogi:BAAALgADCgIJAgAAAA==.Nesrÿn:BAAALgADCgIJAgAAAA==.Nestina:BAAALgADCgMJBAAAAA==.Netherkeeper:BAABLgAECn8gAAIKAAkJKw0APQCJAQAKAAkJKw0APQCJAQAAAA==.Nevaehstar:BAABLgAECn8xAAIYAAkJwRydAADHAgAYAAkJwRydAADHAgAAAA==.',
Ni='Nibuto:BAAALgAECgQJCQAAAA==.Nightvision:BAAALgADCgMJAgAAAA==.Nijun:BAEBLgAECn8jAAILAAgJbxOQHACaAQALAAgJbxOQHACaAQAAAA==.Nikolia:BAAALgADCgYJBwAAAA==.Nini:BAABLgAECn8hAAIEAAgJZgK4RQCgAAAEAAgJZgK4RQCgAAAAAA==.Ninx:BAAALgAECgQJBAAAAA==.Nirazal:BAAALgADCgQJBQAAAA==.',
No='Noivana:BAAALgAFFAMJAwABLgAFFAUJDwAIAOYSAA==.Norgannia:BAAALgADCgkJDwAAAA==.Notprepared:BAAALgADCgEJAQAAAA==.Noys:BAAALgADCgcJDAAAAA==.',
Ol='Oldbenkenobi:BAAALgAECgQJBwAAAA==.Ollifuzzle:BAAALgADCgQJBAAAAA==.',
Op='Oppaissiah:BAABLgAECn8yAAMSAAgJjiKKBwCnAgASAAgJPyKKBwCnAgAUAAYJah2nEwDRAQAAAA==.',
Or='Oraclespyro:BAABLgAECn8WAAImAAYJYQIhVwB7AAAmAAYJYQIhVwB7AAAAAA==.Orlakx:BAAALgADCggJFAAAAA==.',
Os='Osoroshi:BAAALgAECgQJBAAAAA==.',
Ov='Ovrind:BAAALgADCgEJAQAAAA==.',
Oz='Ozài:BAAALgADCgcJCgAAAA==.',
Pa='Padmê:BAAALgADCgQJBgAAAA==.Papasbich:BAAALgAECgUJBwAAAA==.Patronous:BAAALgADCgUJBgAAAA==.',
Pe='Percthirty:BAAALgAECgEJAgAAAA==.Permafrost:BAAALgADCggJCgAAAA==.Perscila:BAAALgADCgUJBQAAAA==.',
Pi='Piggy:BAAALgAECgQJBgAAAA==.',
Pl='Planet:BAAALgADCgEJAQAAAA==.',
Po='Porkchopw:BAAALgAECgcJAQAAAA==.Poundpuppy:BAAALgADCgUJBQAAAA==.',
Pr='Presap:BAABLgAECn8rAAMZAAgJxiEpCAD7AgAZAAgJxiEpCAD7AgAEAAEJAACrdgBJAAAAAA==.Promethius:BAAALgADCgQJBAAAAA==.Proscris:BAAALgADCgUJBQAAAA==.Prïsm:BAAALgADCgYJBgAAAA==.',
Pt='Ptmuchuk:BAAALgADCgYJBgAAAA==.',
Pu='Puca:BAAALgAECgMJBQAAAA==.Pumdmuc:BAABLgAECn8/AAMLAAkJmiEOBAANAwALAAkJmiEOBAANAwAWAAcJKgWROgDVAAAAAA==.Purrie:BAAALgADCgIJAgAAAA==.',
['Pâ']='Pâlly:BAAALgADCgEJAQAAAA==.',
Qu='Quikglaives:BAAALgAECgMJAwAAAA==.Quille:BAAALgAECgUJCQAAAA==.',
Ra='Rahhem:BAABLgAECn8eAAIlAAkJrBJ5CwC5AQAlAAkJrBJ5CwC5AQAAAA==.Rallo:BAAALgAECgEJAQAAAA==.Rayspaly:BAAALgAECgEJAQAAAA==.',
Re='Recbra:BAAALgAECgIJAgAAAA==.Reddelish:BAAALgADCgYJCQAAAA==.Redrek:BAAALgADCgcJEAAAAA==.Redshunter:BAAALgADCgIJAgAAAA==.Redsmonk:BAAALgADCgYJBwAAAA==.Redwinter:BAAALgAECgIJBAABLgAECgcJHgASAKodAA==.Remmie:BAAALgAECgYJDAAAAA==.Retrolbution:BAAALgADCgkJEQAAAA==.Reznik:BAAALgAECgEJAQAAAA==.',
Rh='Rhaokir:BAAALgADCgIJAgAAAA==.',
Ri='Riqua:BAABLgAECn8WAAIZAAcJiwxiSAAnAQAZAAcJiwxiSAAnAQAAAA==.',
Ro='Rodeo:BAABLgAECn8nAAIEAAcJORCeJgA+AQAEAAcJORCeJgA+AQAAAA==.Rotgutwiskey:BAAALgADCgcJDwAAAA==.Roxanne:BAAALgADCgYJBQAAAA==.Roxies:BAAALgAFFAEJAQAAAA==.',
Rp='Rpg:BAAALgAECgcJDgAAAA==.',
Ru='Rumie:BAABLgAECn8YAAIKAAYJeQ6eegA4AQAKAAYJeQ6eegA4AQAAAA==.Runty:BAAALgADCgMJAwAAAA==.',
Sa='Sacket:BAAALgADCgYJBQAAAA==.Sadnhornless:BAAALgAECgEJAQAAAA==.Saeti:BAABLgAECn8rAAUDAAgJlR2WBwBvAgADAAgJlR2WBwBvAgAEAAYJgxq+HwBxAQAFAAQJvBXMIgC4AAAZAAMJ8RfopAB/AAAAAA==.Sandril:BAAALgAECgYJCwAAAA==.Sapplesauce:BAAALgAECgcJEgAAAA==.',
Sc='Scryer:BAAALgAECgEJAQAAAA==.',
Se='Serenìty:BAAALgAECggJDQAAAA==.Seresin:BAABLgAECn8vAAIZAAgJBRsnFgBQAgAZAAgJBRsnFgBQAgAAAA==.',
Sh='Shadý:BAABLgAECn8mAAIHAAgJ6wlRTwBcAQAHAAgJ6wlRTwBcAQAAAA==.Shamanoodles:BAAALgAECgEJAQABLgAECggJFAAMAAQfAA==.Shinbin:BAAALgAECgEJAgAAAA==.Shonna:BAABLgAECn8nAAQaAAcJFxs7BwCUAQAbAAcJXhhsQQCbAQAaAAcJeBg7BwCUAQAcAAIJERlTLQBEAAAAAA==.Shortwarrior:BAABLgAECn8nAAISAAgJGRnHFgDtAQASAAgJGRnHFgDtAQAAAA==.Shrimpimp:BAAALgAECgQJBAAAAA==.',
Si='Sidarya:BAAALgAECggJEAAAAA==.Siduna:BAAALgADCgEJAQAAAA==.Silent:BAACLgAFFH8GAAMRAAIJ0REGIwBIAAASAAEJZRerNABOAAARAAEJPAwGIwBIAAAuAAQKfxsAAxEACQkjFA8fAAoBABIABwkcEgZLAHkBABEABgkoEg8fAAoBAAAA.',
Sk='Skinnybutt:BAAALgADCgkJEQAAAA==.Skippinskipp:BAAALgAECgcJCwAAAA==.Skymaggedon:BAEBLgAECn8pAAMCAAgJdQ3nQwA9AQACAAgJdQ3nQwA9AQAGAAEJMwtieQAuAAAAAA==.',
Sl='Slappadrago:BAAALgAECgkJEwAAAA==.',
Sm='Smileyriley:BAABLgAECn8VAAIEAAYJ/gUVQAC3AAAEAAYJ/gUVQAC3AAAAAA==.',
Sn='Sneakylinks:BAAALgAECgMJBAABLgAECgcJDgABAAAAAA==.Snotlocker:BAAALgAECgEJAQAAAA==.',
So='Sodexorod:BAAALgADCgYJBwAAAA==.Sofiophya:BAAALgAECgMJBQAAAA==.Sooki:BAAALgAECgEJAQAAAA==.Sorlis:BAAALgADCgUJBQAAAA==.Soulber:BAAALgAECgcJEAAAAA==.Sourdew:BAABLgAECn8eAAIfAAcJtB65EAD0AQAfAAcJtB65EAD0AQAAAA==.',
Sp='Sparkey:BAAALgAECgIJAgAAAA==.Spiritair:BAAALgAECgUJBwABLgAECggJKwAZAMYhAA==.Spunklestain:BAAALgADCggJDQABLgAECgkJEwABAAAAAA==.Spyke:BAAALgADCgEJAQAAAA==.Spykids:BAAALgAECgQJBAAAAA==.',
St='Starrdust:BAEALgAECgMJAwAAAA==.Stelle:BAABLgAECn8XAAIgAAgJBREYJABzAQAgAAgJBREYJABzAQAAAA==.Stylos:BAABLgAECn8rAAIkAAgJ+RCmCwCSAQAkAAgJ+RCmCwCSAQAAAA==.Stãrburst:BAAALgAECgcJDQAAAA==.',
Ta='Taissa:BAAALgADCggJCgAAAA==.Taopaípai:BAAALgADCgMJBgAAAA==.Tatertotz:BAAALgAECgUJEAAAAA==.',
Te='Technine:BAAALgADCgMJAwAAAA==.Tegbless:BAAALgAECgkJDgAAAA==.Tegchill:BAABLgAECn8VAAQdAAgJAhRBGAAwAQAMAAgJBQ8oZwDAAQAdAAgJXRFBGAAwAQAVAAEJAACfGgAeAAABLgAECgkJDgABAAAAAA==.',
Th='Thalodrim:BAAALgAECgEJAQABLgAECggJMwADAIQkAA==.Tharelly:BAAALgAECggJEwAAAA==.Theholymatt:BAACLgAFFH8OAAMPAAUJcBm4EgBGAQAPAAQJABe4EgBGAQAQAAMJXhPSXwCUAAAuAAQKfy4AAxAACQkpIycFACADABAACQkpIycFACADAA8ABwnTI0EPAJsCAAAA.Thendari:BAABLgAECn9QAAIaAAgJ3BKwBwCIAQAaAAgJ3BKwBwCIAQAAAA==.Theodus:BAABLgAECn8yAAIXAAkJlBlmIgBXAgAXAAkJlBlmIgBXAgAAAA==.Therayen:BAAALgADCgQJBAAAAA==.Theràpy:BAAALgAECgQJBQAAAA==.Thesmaugmatt:BAABLgAECn8UAAImAAgJfhrKEgD+AQAmAAgJfhrKEgD+AQABLgAFFAUJDgAPAHAZAA==.Thorrune:BAAALgAECgQJBAAAAA==.Threnor:BAABLgAECn8uAAMRAAgJzSSPAgDSAgARAAgJICSPAgDSAgASAAcJYyPtGADZAQAAAA==.Thunderblade:BAAALgADCgIJAgAAAA==.',
Ti='Tialdari:BAAALgADCgYJBgAAAA==.Tiferis:BAACLgAFFH8JAAIPAAMJNCC9FwAbAQAPAAMJNCC9FwAbAQAuAAQKfysAAg8ACQnHGQkNAHgCAA8ACQnHGQkNAHgCAAAA.Tislam:BAAALgAECgcJEAAAAA==.Tizzeia:BAAALgADCgMJBQAAAA==.',
To='Toaster:BAABLgAECn8pAAQRAAkJNx7NBACaAgARAAkJGBrNBACaAgAUAAcJpCCqCQASAgASAAYJtx9dMgDiAQAAAA==.Tobes:BAAALgADCgEJAQAAAA==.Tobiquer:BAABLgAECn8yAAILAAgJtBtSCwBnAgALAAgJtBtSCwBnAgAAAA==.Toebackkey:BAAALgAECgEJAQAAAA==.Tojarmar:BAAALgAECggJEAABLgAECgQJBAABAAAAAA==.',
Tr='Traydra:BAAALgADCgkJGwAAAA==.Triven:BAAALgAECgIJAgAAAA==.Troglodyte:BAACLgAFFH8TAAIGAAUJmBdsEgAxAQAGAAUJmBdsEgAxAQAuAAQKfzoAAgYACQnNIjgEAPACAAYACQnNIjgEAPACAAAA.',
Ts='Tsonokwabain:BAABLgAECn8cAAQVAAcJqx+PBQDkAQAVAAcJqx+PBQDkAQAdAAEJah0qOwBNAAAMAAEJmAIUNQEaAAAAAA==.',
Tw='Twistdog:BAAALgAECgEJAwAAAA==.',
Ty='Tyranastrasz:BAABLgAECn8oAAIiAAkJ4RAODADMAQAiAAkJ4RAODADMAQAAAA==.Tyye:BAAALgAECgEJAQAAAA==.',
['Tâ']='Tâjik:BAABLgAECn8fAAINAAgJNQYUIgAnAQANAAgJNQYUIgAnAQAAAA==.',
Un='Unc:BAAALgAECgcJBwAAAA==.',
Va='Vade:BAAALgAFFAEJAwAAAA==.Vaelith:BAAALgAECggJDAAAAA==.Vaelyra:BAABLgAECn8mAAIKAAgJvBZbTgC8AQAKAAgJvBZbTgC8AQAAAA==.Vaerryn:BAABLgAECn8ZAAQVAAgJXCD5BAD8AQAVAAcJxx/5BAD8AQAMAAIJExyOyQCaAAAdAAIJQyDYOABWAAAAAA==.Vaethund:BAAALgAECgcJCgAAAA==.Vailenya:BAAALgADCgEJAQABLgAECgcJFgAJACggAA==.Valgavoth:BAAALgAECggJEwAAAA==.Vandrin:BAAALgADCgQJBgAAAA==.Vapir:BAAALgADCgUJBwAAAA==.Variala:BAAALgAECgcJEAAAAA==.Vassyra:BAABLgAECn8rAAITAAkJJBc1AwAvAgATAAkJJBc1AwAvAgAAAA==.',
Ve='Velara:BAAALgAECgEJAQAAAA==.Velesyn:BAABLgAECn8WAAMJAAcJKCC3BAAcAgAJAAcJKCC3BAAcAgAKAAEJGgll5gAsAAAAAA==.Vellayna:BAAALgADCgYJBgAAAA==.',
Vi='Vilga:BAAALgADCgkJCQAAAA==.Viral:BAAALgAECgYJDwAAAA==.Viriex:BAAALgADCgEJAQAAAA==.Visone:BAAALgADCgEJAQAAAA==.',
Vo='Vocivus:BAAALgAECggJEwAAAA==.Voidlighter:BAAALgAECggJDwABLgAECgkJMAAPALsdAA==.Volundr:BAABLgAECn8vAAIUAAgJSRfbDQC+AQAUAAgJSRfbDQC+AQAAAA==.Vonvaughan:BAAALgADCgcJCwABLgAECgcJEAABAAAAAA==.',
Vy='Vynirion:BAABLgAECn8UAAIXAAcJqxJUpACPAQAXAAcJqxJUpACPAQAAAA==.Vynisa:BAAALgAECgMJAwAAAA==.',
Wa='Waiseheil:BAAALgADCggJCQAAAA==.Warcreaper:BAAALgAECgcJDQAAAA==.Wargtar:BAABLgAECn8WAAINAAYJNhn1GwBbAQANAAYJNhn1GwBbAQAAAA==.Warlockbob:BAAALgAECgYJCwAAAA==.',
We='Weabe:BAABLgAECn8YAAMLAAcJFhH9JgBGAQALAAcJ9w/9JgBGAQAgAAIJpRHjSgBqAAAAAA==.',
Wh='Whiterrina:BAAALgADCgkJCgAAAA==.',
Wo='Woobee:BAAALgADCgEJAQAAAA==.',
Wy='Wyrdhoof:BAABLgAECn8WAAMEAAcJLgb2OQDTAAAEAAcJLgb2OQDTAAAZAAQJDghpegCFAAAAAA==.',
['Wù']='Wùsthof:BAABLgAECn8eAAIHAAkJywobVgBmAQAHAAkJywobVgBmAQAAAA==.',
Xa='Xandrios:BAAALgADCgMJAwAAAA==.Xaron:BAAALgADCgMJAwAAAA==.',
Xi='Xiae:BAABLgAECn8mAAICAAgJsSOQBgAAAwACAAgJsSOQBgAAAwAAAA==.',
Xk='Xkwizet:BAABLgAECn8WAAIXAAgJcQa0hgAwAQAXAAgJcQa0hgAwAQAAAA==.',
Xo='Xorrin:BAAALgAECgUJDQAAAA==.',
Xy='Xylpho:BAAALgADCgEJAQAAAA==.',
Ye='Yet:BAABLgAECn8jAAIQAAkJHiRaBQAdAwAQAAkJHiRaBQAdAwAAAA==.',
Yi='Yiffweaver:BAABLgAECn8oAAIeAAgJ5grEKAAwAQAeAAgJ5grEKAAwAQAAAA==.',
Yo='Yokoriazen:BAABLgAECn8zAAIlAAkJRxOyCgDKAQAlAAkJRxOyCgDKAQAAAA==.',
Yu='Yurtnaut:BAAALgAECgYJDgAAAA==.',
Za='Zarhianna:BAABLgAECn8iAAIEAAgJcBE6HgB+AQAEAAgJcBE6HgB+AQAAAA==.',
Ze='Zeo:BAAALgAECgEJAQAAAA==.',
Zm='Zmona:BAABLgAECn8nAAIQAAgJdg4dagBSAQAQAAgJdg4dagBSAQAAAA==.',
Zo='Zorsche:BAAALgADCgUJBwAAAA==.',
Zu='Zulrok:BAABLgAECn8nAAISAAgJUB28EgAUAgASAAgJUB28EgAUAgAAAA==.',
['Ðr']='Ðre:BAABLgAECn8VAAIXAAcJ0hZswwBfAQAXAAcJ0hZswwBfAQAAAA==.',
['Ût']='Ûther:BAAALgAECgMJAwAAAA==.',
['Ül']='Ültimecia:BAABLgAECn8rAAIXAAkJLiPZGgAMAwAXAAkJLiPZGgAMAwAAAA==.',
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
