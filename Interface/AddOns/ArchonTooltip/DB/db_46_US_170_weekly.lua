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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Balance','Druid-Guardian','Shaman-Elemental','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Holy','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Warlock-Destruction','Warrior-Fury','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Evoker-Devastation','Monk-Windwalker','Monk-Mistweaver','Mage-Frost','Warrior-Protection','DeathKnight-Frost','Priest-Shadow','Mage-Arcane','Druid-Restoration','Warlock-Affliction','Warlock-Demonology','DeathKnight-Blood','Monk-Brewmaster','Paladin-Protection','Priest-Discipline','Evoker-Preservation','Evoker-Augmentation','Hunter-Survival','Shaman-Enhancement','Hunter-Marksmanship',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=46,date='2026-06-06',data={Ad='Adoraluna:BAAALgAECgEJAQAAAA==.Adunei:BAAALgAECgIJAgAAAA==.',
Ae='Aeginalla:BAAALgADCgcJEgABLgAECgYJCAABAAAAAA==.Aela:BAAALgADCgEJAQABLgAECgkJMwACAAYhAA==.Aesalon:BAABLgAECn80AAQDAAkJ1COhAwDLAgADAAkJ1COhAwDLAgAEAAIJrRTjeQA+AAAFAAIJGBMjaAA0AAAAAA==.',
Ah='Ahsokatano:BAABLgAECn8zAAMCAAkJBiGlBgA8AwACAAkJBiGlBgA8AwAGAAEJ8gycpQAoAAAAAA==.',
Ai='Aimspet:BAAALgAECgYJEQAAAA==.Aircanada:BAAALgAECgIJBAAAAA==.',
Ak='Akela:BAABLgAECn8oAAIHAAkJIQ21RgDBAQAHAAkJIQ21RgDBAQAAAA==.',
Al='Algorithm:BAAALgAECgMJAwAAAA==.Alissu:BAAALgADCgIJAgAAAA==.Alvonaar:BAAALgADCgUJBwAAAA==.',
Am='Ames:BAAALgAECgcJCwAAAA==.Amonet:BAAALgAECgUJCwAAAA==.',
An='Anaelcheese:BAABLgAECn8aAAQIAAcJ2BSaIABgAQAIAAcJ2BSaIABgAQAJAAEJkg0sLgAnAAAKAAEJywAN9wATAAAAAA==.Anamis:BAABLgAECn8pAAILAAgJ1RORJwB8AQALAAgJ1RORJwB8AQAAAA==.Andrina:BAAALgADCgYJAgAAAA==.Angeldemon:BAAALgADCgYJCAAAAA==.Angras:BAABLgAECn8xAAIMAAkJQRXVMQAvAgAMAAkJQRXVMQAvAgAAAA==.Angryorc:BAAALgAECgQJBQAAAA==.Anja:BAAALgADCgkJFwAAAA==.Anolana:BAABLgAECn85AAMNAAgJjCKiCQB/AgANAAgJjCKiCQB/AgAOAAEJixEPJQA3AAAAAA==.Anyday:BAAALgADCgcJBwAAAA==.',
Ap='Aphalock:BAABLgAECn8vAAIPAAkJ6xMbBgD2AQAPAAkJ6xMbBgD2AQAAAA==.',
Ar='Aragoth:BAAALgAECgEJAQAAAA==.Ariûs:BAABLgAECn8VAAIQAAcJ+hBVNwBiAQAQAAcJ+hBVNwBiAQAAAA==.Arlin:BAAALgAECgUJEQAAAA==.Arlorian:BAABLgAECn81AAIOAAkJmRL6BgDoAQAOAAkJmRL6BgDoAQAAAA==.Arorra:BAAALgAECgYJBgAAAA==.Arrex:BAAALgAECgYJCwAAAA==.Arrowsmites:BAABLgAECn8yAAIHAAkJhRwkGgB8AgAHAAkJhRwkGgB8AgAAAA==.',
Au='Aubani:BAABLgAECn8xAAMRAAkJFCCHCAD4AgARAAkJFCCHCAD4AgASAAUJIxKWzwDmAAAAAA==.',
Ay='Ayperos:BAABLgAECn9CAAMTAAgJ9hskCwAqAgATAAgJ9hskCwAqAgAQAAYJPxAVUgBhAQAAAA==.Ayvaria:BAEALgAECgYJEwABLgAECgkJKwAUACQXAA==.',
Ba='Baboyago:BAAALgAECgcJDwAAAA==.Badgerbrew:BAAALgADCgkJCQAAAA==.Bahemith:BAAALgAECgEJAQAAAA==.Baked:BAAALgAECgQJBAABLgAECgkJGwASAO8FAA==.Bakedpally:BAABLgAECn8bAAISAAkJ7wUAnwAtAQASAAkJ7wUAnwAtAQAAAA==.Bandomar:BAABLgAECn8mAAIEAAgJywvvMgBAAQAEAAgJywvvMgBAAQAAAA==.Baniemo:BAAALgAECgIJBAAAAA==.Banigor:BAAALgAECgYJEAAAAA==.Basak:BAAALgAECgYJCwABLgAFFAQJEQABAAAAAQ==.',
Be='Beammescotty:BAAALgADCgQJBAAAAA==.Bearnuts:BAAALgADCgEJAQAAAA==.Beck:BAABLgAECn81AAISAAkJliEoEADbAgASAAkJliEoEADbAgAAAA==.Beefflaps:BAAALgADCgEJAQAAAA==.Beggars:BAAALgAECgYJCQAAAA==.Belithsong:BAAALgAECgkJBwAAAA==.Bereth:BAAALgAECgUJEQAAAA==.Berreydingle:BAAALgAECgUJDgAAAA==.',
Bi='Bigkitty:BAABLgAECn8qAAIQAAkJnhlsGAAkAgAQAAkJnhlsGAAkAgABLgAECggJLwAHAA0iAA==.Bikinibrenda:BAAALgAECgEJAQAAAA==.Birchum:BAAALgADCgcJBwAAAA==.Biz:BAAALgADCgYJBwABLgAECggJFwAVAOMhAA==.',
Bl='Blackanvil:BAABLgAECn8UAAIQAAcJlA9fOABdAQAQAAcJlA9fOABdAQAAAA==.Blackautumn:BAAALgADCgcJDgABLgAECgcJHgAQAKsdAA==.Blainn:BAAALgAECgcJBwAAAA==.Blindfred:BAAALgAECggJDQAAAA==.Blitzedbust:BAAALgADCggJDQAAAA==.Bloodredsky:BAABLgAECn8gAAMWAAkJgxJfJwDVAQAWAAkJgxJfJwDVAQAVAAEJmwiwfwAxAAAAAA==.Bloodymagi:BAABLgAECn8iAAIXAAkJWwa8gABwAQAXAAkJWwa8gABwAQAAAA==.Bluesummer:BAABLgAECn8eAAQQAAcJqx2jLgCOAQAQAAYJQiGjLgCOAQAYAAYJxBrAGQCCAQATAAEJCAzpQQA1AAAAAA==.',
Bo='Bolts:BAAALgAECgEJAwAAAA==.Boomin:BAABLgAECn8wAAMFAAkJuhojCQBIAgAFAAkJuhojCQBIAgAEAAQJdQYuaABtAAAAAA==.Borat:BAAALgAECgQJBAABLgAECgkJLQASAKQkAA==.',
Br='Brendameeks:BAAALgAECgcJEAAAAA==.Brewnashot:BAAALgADCggJCgAAAA==.Brewrain:BAAALgADCgEJAQAAAA==.Broadzinatl:BAABLgAECn8XAAIVAAgJ4yEkCQCnAgAVAAgJ4yEkCQCnAgAAAA==.Brom:BAAALgAECgYJBwAAAA==.Brïn:BAAALgAECgcJCAAAAA==.',
Bu='Bulwark:BAAALgADCgYJBgAAAA==.Bushwookië:BAAALgAECgIJAgAAAA==.',
['Bã']='Bãthory:BAABLgAECn8XAAIZAAkJIxToDACXAQAZAAkJIxToDACXAQAAAA==.',
['Bø']='Bøss:BAAALgADCgkJEQAAAA==.',
Ca='Calvert:BAAALgAECgUJBgAAAA==.Captnhammer:BAAALgAECgIJBAAAAA==.Carebearr:BAAALgADCgcJBwAAAA==.Carnelian:BAAALgAECgQJCQAAAA==.Castration:BAABLgAECn8YAAIaAAYJ3AmoSQDeAAAaAAYJ3AmoSQDeAAAAAA==.',
Ce='Ceylan:BAABLgAECn8xAAMXAAkJgxmyLQBcAgAXAAkJgxmyLQBcAgAbAAEJVQMVIQAqAAAAAA==.',
Ch='Chadillac:BAAALgAECgMJAwAAAA==.Chaleb:BAAALgAECgUJCAAAAA==.Charavane:BAAALgAECgQJBAAAAA==.Charlz:BAABLgAECn8jAAMaAAkJhBaxGQDxAQAaAAkJhBaxGQDxAQALAAQJChHLVQDfAAAAAA==.Charsifood:BAAALgAECgcJDwAAAA==.Chass:BAAALgADCgQJBAAAAA==.Cheatdr:BAABLgAECn8oAAIcAAcJQxFLTQBPAQAcAAcJQxFLTQBPAQAAAA==.Cheatpriest:BAABLgAECn86AAILAAkJ7RYyIQCsAQALAAkJ7RYyIQCsAQAAAA==.Chesthyr:BAAALgAECgEJAQAAAA==.Chesto:BAABLgAECn83AAQdAAkJ7hwgBABUAgAdAAkJZBogBABUAgAPAAcJ4xpfCQCiAQAeAAcJwRT2awCKAQAAAA==.Chimerax:BAAALgAECgIJAgAAAA==.Chimken:BAAALgAECgcJCAABLgAECgkJKQATADUeAA==.Chokea:BAAALgAECgkJDgAAAA==.Chrome:BAAALgAECgEJAQAAAA==.Chuwhee:BAAALgADCgYJBgAAAA==.',
Ci='Cindrethresh:BAAALgAECgUJBQAAAA==.',
Co='Cognition:BAABLgAECn9PAAIHAAkJtiXsAQBuAwAHAAkJtiXsAQBuAwAAAA==.Coldvengance:BAABLgAECn84AAIQAAgJVgq5PgBCAQAQAAgJVgq5PgBCAQAAAA==.Corpser:BAAALgADCgUJBQAAAA==.',
Cr='Cranki:BAAALgAECgUJBgABLgAECgIJBAABAAAAAA==.Cranknstein:BAAALgAECgEJAQABLgAECgIJBAABAAAAAA==.Crazycalla:BAAALgAFFAEJAgAAAA==.Crosbyy:BAAALgAECgUJBQAAAA==.',
Cy='Cymindel:BAABLgAECn84AAIfAAkJCxrECwBHAgAfAAkJCxrECwBHAgAAAA==.',
Da='Dad:BAAALgADCgQJBAAAAA==.Daelein:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Daithi:BAAALgAECgcJEwAAAA==.Dakotà:BAABLgAECn8kAAIHAAcJpBaBUACkAQAHAAcJpBaBUACkAQAAAA==.Darc:BAAALgAECgMJBQAAAA==.Darklite:BAAALgADCgUJDAAAAA==.Darkmonk:BAAALgADCgUJBQAAAA==.Dassadin:BAAALgAECgQJBQAAAA==.Davinci:BAAALgADCgEJAQAAAA==.Day:BAABLgAECn8hAAIHAAgJmhjLPwDXAQAHAAgJmhjLPwDXAQAAAA==.Dayztocome:BAAALgADCgEJAQAAAA==.',
De='Decaydence:BAAALgAECggJEAAAAA==.Dejno:BAABLgAECn8YAAIQAAcJMiDTKgCjAQAQAAcJMiDTKgCjAQAAAA==.Deleted:BAAALgAECgEJAQABLgAECgkJKAAMAOgkAA==.Demonicly:BAABLgAECn8UAAIJAAcJuxP2DQBjAQAJAAcJuxP2DQBjAQAAAA==.Demönslayer:BAAALgAECgcJAwAAAA==.Derowski:BAAALgAECgQJBQAAAA==.Deroz:BAAALgADCgUJBQAAAA==.Dethra:BAAALgADCgcJCwAAAA==.Dezign:BAACLgAFFH8WAAIXAAcJYBfZIgDUAQAXAAcJYBfZIgDUAQAuAAQKfygAAhcACQl2IOsmAHkCABcACQl2IOsmAHkCAAAA.Dezígn:BAABLgAFFH8HAAIeAAQJag7AUQAWAQAeAAQJag7AUQAWAQABLgAFFAcJFgAXAGAXAA==.',
Di='Diabolical:BAAALgAECgEJAQAAAA==.Discordegirl:BAABLgAECn8WAAMgAAYJQQwDTwC9AAAgAAUJvA4DTwC9AAAVAAEJVQLiswAYAAAAAA==.Divinitÿ:BAAALgADCgIJAgABLgAECgkJLAAeAL8jAA==.',
Do='Dolgorukov:BAABLgAECn8vAAIHAAkJXhNzPwDZAQAHAAkJXhNzPwDZAQAAAA==.Dologony:BAABLgAECn8jAAIcAAkJmg4VPgCRAQAcAAkJmg4VPgCRAQAAAA==.',
Dr='Dracigor:BAAALgAECgQJBQAAAA==.Draconair:BAAALgADCgYJCAAAAA==.Dragonsbaine:BAAALgADCgMJAwAAAA==.Dragonz:BAAALgAECgUJEQAAAA==.Drakhan:BAAALgADCgIJAgAAAA==.Dre:BAAALgAECgMJCAAAAA==.Dreåm:BAAALgADCgQJBAABLgAECgkJLAAeAL8jAA==.Drikken:BAABLgAECn8/AAQKAAkJwxmZLgABAgAKAAkJOheZLgABAgAIAAUJgBbiLAAIAQAJAAUJ2xuXEwAHAQAAAA==.Drmaker:BAAALgAECgMJAwAAAA==.Drougs:BAABLgAECn8uAAIIAAkJVxhWFgDEAQAIAAkJVxhWFgDEAQAAAA==.Druiddeleted:BAAALgAECgEJAQABLgAECgkJKAAMAOgkAA==.',
Du='Dubbshot:BAAALgAECgEJAQAAAA==.Dumara:BAAALgADCgIJAgAAAA==.Durasan:BAABLgAECn8eAAMMAAcJQQlzvgD2AAAMAAcJWwdzvgD2AAAZAAEJuxRXMgBAAAAAAA==.Duressa:BAAALgAECgcJBwAAAA==.',
Dy='Dymund:BAAALgAECgIJBAAAAA==.',
['Dà']='Dàrkside:BAAALgAECgYJBgAAAA==.',
['Dö']='Dötdötdead:BAABLgAECn8pAAMPAAgJIhX4CACrAQAPAAgJIhX4CACrAQAeAAIJZwtJAQFeAAAAAA==.',
Ea='Earthie:BAAALgADCgEJAQAAAA==.Earthstorm:BAAALgADCgIJAgAAAA==.Eastwubz:BAAALgADCgIJAgAAAA==.',
Ed='Edge:BAAALgAECgMJBQAAAA==.',
Ef='Effin:BAAALgADCgUJBQAAAA==.Effindin:BAAALgAECgUJBwAAAA==.Effinfu:BAABLgAECn8gAAIgAAkJpRATHgCsAQAgAAkJpRATHgCsAQAAAA==.',
Ei='Eitent:BAABLgAECn8wAAMRAAkJux3FDQCqAgARAAkJux3FDQCqAgASAAcJuhIRdgCOAQAAAA==.',
El='Ele:BAAALgADCgcJCAABLgAECgcJHAARALEfAA==.Ellesthara:BAAALgAECgYJDwAAAA==.Ellysiaa:BAABLgAECn8WAAIDAAYJLQV2LgCWAAADAAYJLQV2LgCWAAAAAA==.Elrïc:BAAALgAECgUJBQAAAA==.Elwynlana:BAAALgADCgYJBwAAAA==.Elysa:BAAALgADCgEJAQAAAA==.',
Em='Emberstorm:BAAALgAECgQJBQAAAA==.Emmakyn:BAABLgAECn8vAAMEAAgJ2RX7HQDLAQAEAAgJ2RX7HQDLAQAcAAcJMA0QVQAxAQAAAA==.',
En='Enezath:BAAALgADCgIJAgAAAA==.Entrerie:BAAALgADCgYJEAAAAA==.Enyxea:BAABLgAECn8XAAICAAgJFRf1JwASAgACAAgJFRf1JwASAgAAAA==.',
Ep='Ephemera:BAAALgAECgYJDQAAAA==.Epsolon:BAAALgAECgIJAgAAAA==.',
Er='Erikuh:BAAALgADCgEJAQAAAA==.Erodin:BAAALgAECgEJAgAAAA==.',
Es='Esmeray:BAEALgAECggJEQABLgAECgkJKwAUACQXAA==.Estala:BAAALgADCgUJBQAAAA==.',
Ey='Eyedontknow:BAABLgAECn8gAAIhAAgJCCFmBQCOAgAhAAgJCCFmBQCOAgAAAA==.Eyewana:BAABLgAECn8kAAIIAAkJchIZGwCUAQAIAAkJchIZGwCUAQAAAA==.',
Ez='Ezzka:BAABLgAECn8jAAIMAAkJxRjaIwBuAgAMAAkJxRjaIwBuAgAAAA==.',
Fa='Faelan:BAAALgADCgIJAQAAAA==.Fakesaint:BAAALgAECgYJDgAAAA==.Fangalor:BAAALgAECgEJBAAAAA==.Farnsworth:BAABLgAECn8cAAQeAAkJ3hxTIQBXAgAeAAgJ0xxTIQBXAgAPAAMJGBxdHwClAAAdAAEJNBNGNQBBAAABLgAECgkJNAADANQjAA==.Farzix:BAABLgAECn8lAAIGAAkJlwhkPQAvAQAGAAkJlwhkPQAvAQAAAA==.Façade:BAABLgAECn8mAAIMAAkJDxMpWQCzAQAMAAkJDxMpWQCzAQAAAA==.',
Fe='Feelgood:BAAALgAECgQJBAAAAA==.Fefifiona:BAACLgAFFH8FAAIiAAIJOA01OgB4AAAiAAIJOA01OgB4AAAuAAQKfxkAAiIACQkqF00PAG4CACIACQkqF00PAG4CAAAA.Fefifredrich:BAAALgAECgMJAwABLgAFFAIJBQAiADgNAA==.Fefifuredric:BAAALgAECgEJAgABLgAFFAIJBQAiADgNAA==.Felvira:BAABLgAECn8dAAMKAAgJPgQjygCLAAAKAAYJbQMjygCLAAAIAAUJWwQnUwBbAAAAAA==.',
Fi='Finnw:BAABLgAECn8cAAIRAAcJsR/WDwCRAgARAAcJsR/WDwCRAgAAAA==.Firelite:BAABLgAECn8fAAIGAAcJag/cQAAgAQAGAAcJag/cQAAgAQAAAA==.',
Fl='Flairlock:BAABLgAECn86AAMdAAgJtSD+BAAxAgAdAAgJtSD+BAAxAgAPAAIJBhU9OQA5AAAAAA==.Flee:BAABLgAECn8iAAINAAkJqRrhDQA+AgANAAkJqRrhDQA+AgAAAA==.',
Fo='Fookster:BAABLgAECn8ZAAIXAAkJyhN3PQAeAgAXAAkJyhN3PQAeAgAAAA==.Forsetee:BAABLgAFFH8GAAIgAAIJTRdcQACSAAAgAAIJTRdcQACSAAAAAA==.',
Fr='Frowdawn:BAABLgAECn87AAIOAAkJUxBJBwDeAQAOAAkJUxBJBwDeAQAAAA==.',
Fy='Fyf:BAAALgAECgYJBgABLgAECgIJBAABAAAAAA==.',
['Fí']='Físter:BAAALgAECgYJDwABLgAECgcJGgAMACoaAA==.',
Ga='Ga:BAAALgAECgIJAgAAAA==.Galadris:BAAALgADCgkJDwAAAA==.Garythenpc:BAAALgAECgUJEQAAAA==.Gaztoria:BAAALgADCggJCAABLgAECgkJLwAMANYiAA==.',
Ge='Genavieve:BAAALgADCgQJBAAAAA==.Gendra:BAAALgAECgEJAQAAAA==.',
Gh='Ghøst:BAAALgADCgEJAQAAAA==.Ghøstlord:BAAALgADCgEJAQAAAA==.',
Gi='Gilas:BAAALgADCgQJBAAAAA==.',
Gl='Glacialkitty:BAABLgAECn8vAAIcAAkJ4gvpQwB3AQAcAAkJ4gvpQwB3AQAAAA==.',
Go='Googoobler:BAABLgAECn8iAAIIAAgJ7AfwKwANAQAIAAgJ7AfwKwANAQAAAA==.Goudaluck:BAAALgADCgUJBwABLgAECggJLwAHAA0iAA==.Goudanight:BAAALgAECgMJBAABLgAECggJLwAHAA0iAA==.Goudavibes:BAAALgAECgEJAQABLgAECggJLwAHAA0iAA==.',
Gr='Greenmagus:BAAALgAECgEJAQAAAA==.Grenadon:BAAALgAECgUJDgAAAA==.Gridimbor:BAAALgAECgEJAQAAAA==.Grimlilith:BAABLgAECn8bAAQdAAgJ/wSbEQATAQAdAAgJ9gSbEQATAQAeAAMJBAN4IAE8AAAPAAEJAAAogQALAAAAAA==.Grimmhoof:BAAALgAECgIJAgAAAA==.Grundy:BAAALgAECgUJCAAAAA==.',
Gu='Gumbi:BAAALgADCgIJAgAAAA==.',
Ha='Hadorya:BAABLgAECn87AAIaAAgJAB3AEwAqAgAaAAgJAB3AEwAqAgAAAA==.Hakitua:BAABLgAECn8mAAIJAAkJ2w2PDQBqAQAJAAkJ2w2PDQBqAQAAAA==.Hando:BAAALgAECgEJAQAAAA==.Hangi:BAAALgADCgkJCQAAAA==.Happymeel:BAAALgAECgEJAQAAAA==.Harleyqûinn:BAAALgAECgcJDQAAAA==.Hatshepsut:BAAALgAECgEJAQAAAA==.Hazard:BAABLgAECn87AAIQAAgJnA9NMgB7AQAQAAgJnA9NMgB7AQAAAA==.',
He='Healonwheels:BAAALgADCgMJAwAAAA==.Heimdall:BAABLgAECn8bAAQYAAgJ8SI5CABtAgAYAAcJByQ5CABtAgAQAAcJ7hxAHQD9AQATAAMJvxBSRwCgAAABLgAECgkJLAAeAL8jAA==.Heis:BAAALgAECgUJEQAAAA==.Hellboii:BAAALgAECggJEwAAAA==.Heyitsrat:BAABLgAECn8xAAISAAkJABcJPgACAgASAAkJABcJPgACAgAAAA==.',
Hi='Hiko:BAAALgAECgkJEAAAAA==.',
Ho='Holo:BAACLgAFFH8SAAMCAAYJJgqFAgC9AQACAAYJJgqFAgC9AQAGAAUJFB9XGQA6AQAuAAQKfyEAAwYACQlzIWYDAG0DAAYACQlzIWYDAG0DAAIABwnXDgJCAHkBAAAA.Holos:BAAALgAECgEJAQABLgAFFAYJEgACACYKAA==.Holyangus:BAAALgAECgUJDAAAAA==.Holyfawn:BAAALgADCgEJAQAAAA==.Holyyknight:BAAALgAECgcJEwAAAA==.',
Hu='Hugecrit:BAAALgADCgkJDwAAAA==.',
Ib='Ibbert:BAAALgADCggJFQAAAA==.',
Ic='Icculus:BAABLgAECn8lAAIHAAgJJxlBNAAAAgAHAAgJJxlBNAAAAgAAAA==.',
Il='Illuyanka:BAAALgAECgEJAQAAAA==.',
Im='Imaresmashy:BAAALgAECgEJAQABLgAECgkJJAABAAAAAA==.Impasse:BAAALgAECgkJCAAAAA==.',
In='Indaskyz:BAAALgADCgEJAQAAAA==.',
Io='Iolz:BAAALgAECgYJCgAAAA==.',
Ir='Ironfist:BAABLgAECn8+AAIgAAkJaSSoAQBNAwAgAAkJaSSoAQBNAwAAAA==.',
It='Itankworlds:BAAALgAECgUJBQABLgAECgcJDgABAAAAAA==.',
Iw='Iwanaplay:BAAALgAECgMJAwAAAA==.',
Ja='Jacolynn:BAABLgAECn8YAAIWAAcJ7BHsKwBXAQAWAAcJ7BHsKwBXAQAAAA==.Jaenei:BAAALgAECgcJDwAAAA==.',
Je='Jelly:BAAALgADCgIJAgAAAA==.',
Ji='Jinrok:BAAALgAECgUJBgAAAA==.',
Jo='Joatmoa:BAACLgAFFH8GAAIDAAMJNRTjCwDiAAADAAMJNRTjCwDiAAAuAAQKfxQAAgMACQmIHKIOALkBAAMACQmIHKIOALkBAAAA.Joeexotics:BAAALgADCgkJDAAAAA==.Jordanleah:BAAALgAECgQJBAAAAA==.',
Ju='July:BAAALgAECgcJEAAAAA==.Julytonidas:BAAALgAECgcJBwAAAA==.Jurac:BAAALgADCgcJGwAAAA==.',
Ka='Kaelnis:BAAALgAECggJEgAAAA==.Kaimargonar:BAAALgAECgYJEQAAAA==.Kaitoi:BAABLgAECn8fAAMDAAgJRR6aBgBqAgADAAgJRR6aBgBqAgAFAAUJKwgNRgB5AAAAAA==.Kallah:BAACLgAFFH8ZAAIRAAYJZR2NCgD4AQARAAYJZR2NCgD4AQAuAAQKfzcAAhEACQnsI44BAGsDABEACQnsI44BAGsDAAAA.Kalthos:BAABLgAECn9AAAMjAAkJHBmUCABdAgAjAAgJjxmUCABdAgAUAAkJnBH4BgDHAQAAAA==.Kamakizeg:BAACLgAFFH8FAAISAAIJIQ13hQCNAAASAAIJIQ13hQCNAAAuAAQKfy0AAhIACQkEEwRVAMEBABIACQkEEwRVAMEBAAAA.Kamayla:BAAALgADCgYJBgAAAA==.Karnus:BAAALgADCgUJBQAAAA==.Kaspen:BAAALgADCgMJAwAAAA==.Kateria:BAABLgAECn8nAAIXAAkJKR1OHwCcAgAXAAkJKR1OHwCcAgAAAA==.',
Ke='Kestrelle:BAAALgAECgcJEwABLgAECgkJSAAcAAkSAA==.Keyzeus:BAABLgAECn8lAAMUAAgJCxgjBgDlAQAUAAgJCxgjBgDlAQAkAAEJ5xvDfwBOAAAAAA==.',
Kh='Khas:BAAALgADCgkJGgAAAA==.Khui:BAACLgAFFH8bAAIWAAYJSyUdBwBxAgAWAAYJSyUdBwBxAgAuAAQKfyUAAxYACAkWJcACAFcDABYACAkWJcACAFcDABUAAwkwGFhOAL8AAAAA.',
Ki='Kiarorin:BAAALgAECgEJAQAAAA==.Killerdeath:BAAALgAECgQJBwAAAA==.Kipziep:BAAALgAECgIJAgAAAA==.',
Kn='Knìghtmàrè:BAACLgAFFH8TAAMMAAYJ3xmeLACWAQAMAAUJ3xmeLACWAQAfAAEJAACUTQAAAAAuAAQKfygAAgwACQn9INMSAAsDAAwACQn9INMSAAsDAAAA.Kníghtfíst:BAABLgAECn8rAAIWAAkJ/ReDFABlAgAWAAkJ/ReDFABlAgABLgAFFAYJEwAMAN8ZAA==.',
Ko='Koltharaz:BAAALgAECgEJAQAAAA==.Korheo:BAAALgADCgUJBQAAAA==.Korloff:BAAALgAECgcJDQABLgAECgcJHAABAAAAAQ==.Kozan:BAAALgAECgcJHAAAAQ==.',
Kr='Krazysniper:BAABLgAECn8oAAMHAAgJCRzqLAAeAgAHAAcJEB/qLAAeAgAlAAEJ4wmAXgA5AAAAAA==.Krokk:BAABLgAECn8UAAIGAAcJ9QcAUADmAAAGAAcJ9QcAUADmAAAAAA==.',
Ku='Kungfister:BAAALgAECgEJAQAAAA==.Kur:BAAALgAFFAEJAQABLgAFFAQJEQABAAAAAQ==.',
La='Laatt:BAABLgAECn8aAAMSAAgJFh66KgB5AgASAAgJFh66KgB5AgARAAYJOBjSOABdAQAAAA==.Lacosanostra:BAAALgAECgYJCwAAAA==.Laeiny:BAAALgADCgYJBgAAAA==.Lateralus:BAAALgAECgUJBgABLgAECggJGgASABYeAA==.Latharel:BAAALgAECgEJAQAAAA==.Lawluss:BAABLgAECn8lAAIHAAcJ5hnITwCmAQAHAAcJ5hnITwCmAQAAAA==.Layethelor:BAAALgAECgEJBAAAAA==.',
Le='Legacyshot:BAAALgAECgkJJAAAAQ==.Leigola:BAAALgADCgUJCQAAAA==.Lela:BAAALgAECgYJBgAAAA==.Lezsul:BAAALgAECgIJAgAAAA==.',
Li='Lickthecrit:BAAALgAECggJEgAAAA==.Lidrelle:BAABLgAECn8dAAISAAcJAhKIjABMAQASAAcJAhKIjABMAQAAAA==.Lightguard:BAAALgAECgYJBgAAAA==.Lighthouse:BAABLgAECn8uAAISAAkJlxtMMQAwAgASAAkJlxtMMQAwAgAAAA==.Lileth:BAAALgAECgUJBQAAAA==.Lilpaws:BAAALgAECgYJBgAAAA==.Lizy:BAAALgADCgUJBQAAAA==.',
Lo='Locust:BAAALgAECgMJAwAAAA==.Lokkar:BAAALgADCgQJBAAAAA==.Lolalazer:BAABLgAECn8WAAIKAAgJ9RVvVwB1AQAKAAgJ9RVvVwB1AQAAAA==.Lolhahabaha:BAAALgAECggJDAAAAA==.Loopie:BAAALgADCgYJCgAAAA==.Lovesomev:BAAALgADCgMJAwAAAA==.',
Lu='Luckÿ:BAABLgAECn8XAAIfAAcJlxU3IQA/AQAfAAcJlxU3IQA/AQAAAA==.Lunabelle:BAAALgADCgEJAQAAAA==.Lunchbox:BAAALgAECgkJAQAAAA==.Lustfull:BAAALgAECgEJAgABLgAECgkJHwAHAPgfAA==.',
Ly='Lypally:BAABLgAECn81AAISAAkJaw9lVwC7AQASAAkJaw9lVwC7AQAAAA==.',
['Ló']='Lóla:BAABLgAECn8wAAIKAAkJziM8BwARAwAKAAkJziM8BwARAwAAAA==.',
['Lô']='Lônè:BAAALgAECgUJBwAAAA==.',
Ma='Maani:BAAALgAECgEJAQAAAA==.Madeah:BAACLgAFFH8oAAMNAAgJGRaSAwByAgANAAgJGRaSAwByAgAOAAYJOw+dAgB+AQAuAAQKfyEAAw0ACAlGHtkMAMsCAA0ACAlGHtkMAMsCAA4AAQnoGt8aAFEAAAAA.Mahimahi:BAAALgAECggJCAAAAA==.Malýs:BAAALgAECgEJAQAAAA==.Mardain:BAABLgAECn8fAAImAAkJphV7CQAZAgAmAAkJphV7CQAZAgAAAA==.Mariacuras:BAABLgAECn8VAAIRAAgJ3QtiNAB2AQARAAgJ3QtiNAB2AQAAAA==.Marle:BAABLgAECn8yAAIKAAkJqhfrJgAlAgAKAAkJqhfrJgAlAgAAAA==.Marlete:BAAALgADCgYJBQAAAA==.Marshoon:BAAALgAECgIJAgAAAA==.Martis:BAAALgAECgYJBwAAAA==.Marynne:BAABLgAECn9IAAMcAAkJCRKFLADtAQAcAAkJCRKFLADtAQAEAAEJSwLRogAMAAAAAA==.Matthis:BAAALgAECgUJBwAAAA==.Mazuko:BAABLgAECn8vAAIJAAgJexf9CADQAQAJAAgJexf9CADQAQAAAA==.',
Mc='Mcdo:BAAALgAECgEJAQABLgAFFAUJEgAnAGMhAA==.',
Me='Medadh:BAAALgADCgUJBQAAAA==.Meepe:BAAALgADCgcJDAAAAA==.Meilnesar:BAAALgAECgIJAgAAAA==.Melaerissa:BAABLgAECn8wAAMaAAgJhQ/AJgCPAQAaAAgJhQ/AJgCPAQALAAUJxQxDSgCsAAAAAA==.Melbrooks:BAAALgADCgcJDQAAAA==.Melivant:BAABLgAECn8UAAMSAAUJABi3pwAgAQASAAUJABi3pwAgAQARAAQJwhHaVADYAAABLgAECgYJEAABAAAAAA==.Merrikeath:BAAALgAECggJEgAAAA==.Merriklade:BAABLgAECn8vAAMQAAgJIg7JSAAZAQAQAAcJdQnJSAAZAQAYAAcJig/0OACDAAAAAA==.',
Mi='Missyjelliot:BAAALgAECgQJBwAAAA==.',
Mo='Monster:BAAALgADCgEJAQAAAA==.Moof:BAAALgADCgEJAQAAAA==.Morchuk:BAAALgADCgMJAwAAAA==.Morigith:BAAALgADCgcJBwABLgAECgUJBQABAAAAAA==.Morthos:BAAALgAECgMJBgAAAA==.',
Mw='Mw:BAAALgADCgIJAgABLgAECgcJHAARALEfAA==.',
My='Myora:BAEALgAECggJEwABLgAECgkJKwAUACQXAA==.Mythundirus:BAAALgADCgMJAwAAAA==.',
['Mà']='Màrli:BAAALgAECgcJDwAAAA==.',
['Mâ']='Mâgs:BAABLgAECn8gAAIhAAkJWhKyEACsAQAhAAkJWhKyEACsAQAAAA==.',
Na='Nabbed:BAAALgAECgcJCAABLgAECgkJKQATADUeAA==.Nakasid:BAACLgAFFH8KAAILAAMJYxHqHgCtAAALAAMJYxHqHgCtAAAuAAQKfzUABAsACQnWFwsQAFoCAAsACQnWFwsQAFoCABoABwkVCNQ5ACIBACIABAlbCh5VAJYAAAAA.Nalaya:BAAALgAECgEJAQAAAA==.Nashoba:BAAALgADCgQJBAAAAA==.Natooka:BAAALgAECggJDgAAAA==.Navane:BAAALgAECgUJBwAAAA==.',
Ne='Necromaniac:BAAALgAECgEJAQAAAA==.Neenja:BAAALgADCgYJBgAAAA==.Nefurtatta:BAAALgADCgEJAQAAAA==.Nertlogi:BAAALgADCgIJAgAAAA==.Nesrÿn:BAAALgADCgIJAgAAAA==.Nestina:BAAALgADCgMJBAAAAA==.Netherkeeper:BAABLgAECn8rAAIKAAkJsBCuQAC7AQAKAAkJsBCuQAC7AQAAAA==.Nevaehstar:BAABLgAECn84AAIbAAkJzh4sAQCmAgAbAAkJzh4sAQCmAgAAAA==.Neverëst:BAAALgAECgEJAQAAAA==.',
Ni='Nibuto:BAAALgAECgQJCwAAAA==.Nightvision:BAAALgADCgMJAgAAAA==.Nijun:BAEBLgAECn8uAAILAAkJOxRKHgDEAQALAAkJOxRKHgDEAQAAAA==.Nikolia:BAAALgAECgQJBgAAAA==.Ninetynine:BAAALgADCgMJAwAAAA==.Nini:BAABLgAECn8hAAIEAAgJZwJ7WQCeAAAEAAgJZwJ7WQCeAAAAAA==.Ninx:BAAALgAECgQJBAAAAA==.Nirazal:BAAALgADCgQJBQAAAA==.',
No='Noivana:BAAALgAFFAMJAwABLgAFFAUJEAAIANcSAA==.Nokru:BAAALgADCgMJBQAAAA==.Norgannia:BAAALgADCgkJDwAAAA==.Notprepared:BAAALgADCgEJAQAAAA==.Noys:BAAALgADCgcJDAAAAA==.',
Nz='Nzuul:BAAALgAECgMJAwAAAA==.',
Ol='Oldbenkenobi:BAAALgAECgQJCAAAAA==.Ollichi:BAAALgADCgQJBAAAAA==.Ollifuzzle:BAAALgAECgEJAwAAAA==.',
Om='Ominous:BAAALgAECgMJAwAAAA==.',
Op='Oppaissiah:BAABLgAECn9DAAMYAAkJ6iMZAgAlAwAYAAkJlSMZAgAlAwAQAAkJ8R/YCADLAgAAAA==.',
Or='Oraclespyro:BAABLgAECn8XAAIkAAYJawI6cAB6AAAkAAYJawI6cAB6AAABLgAECgkJDwABAAAAAA==.Orlakx:BAAALgADCggJFAAAAA==.Orman:BAAALgAECgEJAQAAAA==.',
Os='Osoroshi:BAAALgAECgQJBAAAAA==.',
Ov='Ovrind:BAAALgADCgEJAQAAAA==.',
Oz='Ozài:BAAALgADCgcJCgAAAA==.',
Pa='Padmê:BAAALgAECgcJDAAAAA==.Pandamared:BAAALgADCgMJAwAAAA==.Papasbich:BAAALgAECgcJEgABLgAECgkJRwASACIUAA==.Patronous:BAAALgADCgUJBgAAAA==.',
Pe='Percthirty:BAAALgAECgEJAgAAAA==.Permafrost:BAAALgADCggJCgAAAA==.Perscila:BAAALgADCgUJBQAAAA==.',
Pi='Piggy:BAAALgAECgQJBgAAAA==.',
Pl='Planet:BAAALgADCgEJAQAAAA==.',
Po='Porkchoplust:BAAALgAECgEJAQAAAA==.Porkchopw:BAAALgAECgcJAQAAAA==.Porkribs:BAAALgAECggJCgAAAA==.',
Pr='Presap:BAABLgAECn8sAAMcAAgJxCE2DAD1AgAcAAgJxCE2DAD1AgAEAAEJAACrdgBJAAABLgAECggJFQAjAHcbAA==.Promethius:BAAALgADCgQJBAAAAA==.Proscris:BAAALgADCgUJBQAAAA==.Prïsm:BAAALgADCgYJBgAAAA==.',
Pt='Ptmuchuk:BAAALgADCgYJBgAAAA==.',
Pu='Puca:BAAALgAECgUJEQAAAA==.Pumdmuc:BAACLgAFFH8HAAILAAMJLBkuGwDMAAALAAMJLBkuGwDMAAAuAAQKf0IAAwsACQmaIdoGAN8CAAsACQmaIdoGAN8CABoABwkqBfdNAM4AAAAA.Purrie:BAAALgADCgIJAgAAAA==.',
['Pâ']='Pâlly:BAAALgAECgcJEAAAAA==.',
Qu='Quikglaives:BAAALgAECgQJBwAAAA==.Quille:BAABLgAECn8VAAIHAAcJ9BaOTACwAQAHAAcJ9BaOTACwAQAAAA==.',
Ra='Rahhem:BAABLgAECn8eAAIhAAkJrRJ0EACvAQAhAAkJrRJ0EACvAQAAAA==.Rallo:BAAALgAECgEJAQAAAA==.Rayspaly:BAAALgAECgMJBAAAAA==.',
Re='Recbra:BAAALgAECgIJAgAAAA==.Reddelish:BAAALgADCgYJCQAAAA==.Redrek:BAAALgADCgcJEAAAAA==.Redsbank:BAAALgADCgMJAwAAAA==.Redshunter:BAAALgADCgQJBQAAAA==.Redsknight:BAAALgADCgkJCQAAAA==.Redsmonk:BAAALgADCgYJCgAAAA==.Redwinter:BAAALgAECgIJBAABLgAECgcJHgAQAKsdAA==.Reikisong:BAAALgAECgEJAQAAAA==.Remmie:BAAALgAECgYJDAAAAA==.Retrolbution:BAAALgADCgkJEQAAAA==.Reylia:BAAALgAECgMJAwAAAA==.Reznik:BAAALgAECgEJAQAAAA==.',
Rh='Rhagurion:BAAALgAECgcJBwAAAA==.Rhaokir:BAAALgADCgIJAgAAAA==.',
Ri='Riqua:BAABLgAECn8iAAIcAAgJJhSdLQDmAQAcAAgJJhSdLQDmAQAAAA==.',
Ro='Rockmonsta:BAAALgAECgUJBQAAAA==.Rodeo:BAABLgAECn8sAAIEAAkJABAsIQCxAQAEAAkJABAsIQCxAQAAAA==.Rotgutwiskey:BAAALgADCgcJGQAAAA==.Roxies:BAAALgAFFAEJAQAAAA==.Royan:BAAALgAECgcJDAAAAA==.',
Rp='Rpg:BAAALgAECgcJDgAAAA==.',
Ru='Rumie:BAABLgAECn8bAAIKAAYJeQ6eegA4AQAKAAYJeQ6eegA4AQAAAA==.Runty:BAAALgADCgMJAwAAAA==.',
Sa='Sacket:BAAALgAECgQJBAAAAA==.Sadnhornless:BAAALgAECgEJAgAAAA==.Saeti:BAACLgAFFH8PAAMDAAQJbRubCQAFAQADAAMJbRybCQAFAQAEAAEJbxjTQgBOAAAuAAQKfzoABQMACQkaIZYHAG8CAAMACQkaIZYHAG8CAAQABgmdG9YoAHwBAAUABAk2Fh43ALYAABwABAkUFnSEAKYAAAAA.Sandril:BAAALgAECgcJDAAAAA==.Sapplesauce:BAABLgAECn8XAAINAAgJ5Bd7HAClAQANAAgJ5Bd7HAClAQAAAA==.',
Sc='Scryer:BAAALgAECgEJAQAAAA==.',
Se='Serenìty:BAAALgAECggJDQAAAA==.Seresin:BAACLgAFFH8HAAMcAAMJ6wVRSgCJAAAcAAMJ6wVRSgCJAAAEAAEJ4wYQSgA0AAAuAAQKf0YAAxwACAk6HjUSALICABwACAk6HjUSALICAAQAAQniDLiGADIAAAAA.',
Sh='Shadý:BAABLgAECn8vAAIHAAkJ5AoETwCpAQAHAAkJ5AoETwCpAQAAAA==.Shamanoodles:BAAALgAECgEJAQABLgAECgkJKAAMAOgkAA==.Shinbin:BAAALgAECgEJAgAAAA==.Shonna:BAABLgAECn8oAAQPAAgJLBqMCgCMAQAeAAgJ1heZQQDSAQAPAAcJeBiMCgCMAQAdAAIJERlTLQBEAAAAAA==.Shortwarrior:BAABLgAECn83AAIQAAkJCRt2EgBaAgAQAAkJCRt2EgBaAgAAAA==.Shrimpimp:BAAALgAECgQJBAAAAA==.',
Si='Sianu:BAAALgAECgcJBwABLgAECgkJSAAcAAkSAA==.Sidarya:BAAALgAECggJEwAAAA==.Sidera:BAAALgAECggJDgAAAA==.Siduna:BAAALgADCgEJAQAAAA==.Silent:BAACLgAFFH8OAAMQAAQJixqHFwBHAQAQAAQJixqHFwBHAQATAAEJPAx1OgBEAAAuAAQKfxsAAxMACQkkFM4ZACUBABAABwkdEgZLAHkBABMABgkoEs4ZACUBAAAA.Silverserket:BAAALgAECgIJBAAAAA==.Silverserqet:BAAALgAECgYJCgAAAA==.',
Sk='Skinnybutt:BAAALgADCgkJEQAAAA==.Skippinskipp:BAAALgAECgcJCwAAAA==.Skymaggedon:BAEBLgAECn9BAAMCAAkJPg3dRQCIAQACAAkJPg3dRQCIAQAGAAgJQAjZRQAMAQAAAA==.',
Sl='Slappadrago:BAAALgAECgkJEwAAAA==.',
Sm='Smileyriley:BAABLgAECn8aAAIEAAcJzQW4SwDOAAAEAAcJzQW4SwDOAAAAAA==.',
Sn='Sneakylinks:BAAALgAECgMJBQABLgAECgcJDgABAAAAAA==.Snotlocker:BAAALgAECgEJAQAAAA==.',
So='Sodexorod:BAAALgADCgYJBwAAAA==.Sofiophya:BAAALgAECgUJEQAAAA==.Sooki:BAAALgAECgIJAwAAAA==.Sorlis:BAAALgAECgcJDAAAAA==.Soulber:BAABLgAECn8XAAMMAAgJ1BSGUwDCAQAMAAgJ2ROGUwDCAQAfAAIJnxxuOQCiAAAAAA==.Sourdew:BAABLgAECn8eAAIVAAcJtB4rGADkAQAVAAcJtB4rGADkAQAAAA==.',
Sp='Sparkey:BAAALgAECgIJAgAAAA==.Spiritair:BAABLgAECn8VAAMjAAgJdxscBwCCAgAjAAgJdxscBwCCAgAUAAEJAACYLAAAAAAAAA==.Spunklestain:BAAALgADCggJDQABLgAECgkJEwABAAAAAA==.Spyke:BAAALgADCgEJAQAAAA==.Spykids:BAAALgAECgQJBAAAAA==.',
Sr='Srix:BAAALgAECgEJAQAAAA==.',
St='Starrdust:BAEALgAECgUJCwAAAA==.Stelle:BAABLgAECn8XAAIiAAgJBBEYJABzAQAiAAgJBBEYJABzAQAAAA==.Sternhoof:BAAALgAECgEJAQAAAA==.Stylos:BAABLgAECn85AAImAAgJQBWkDADZAQAmAAgJQBWkDADZAQAAAA==.Stãrburst:BAABLgAECn8UAAMCAAgJZQohdQDtAAACAAcJswchdQDtAAAGAAEJUAQcswAeAAAAAA==.',
Su='Subrinea:BAAALgAECgUJBQABLgAECgkJOAAbAM4eAA==.',
Ta='Taissa:BAAALgADCggJCgAAAA==.Taopaípai:BAAALgADCgMJBgAAAA==.Tas:BAAALgAECgQJBAAAAA==.Tatertotz:BAAALgAECgcJEgAAAA==.',
Te='Technine:BAAALgADCgMJAwAAAA==.Techno:BAAALgAECgcJAQAAAA==.Tegbless:BAAALgAECgkJDgAAAA==.Tegchill:BAABLgAECn8dAAQfAAgJNBkwEgDfAQAfAAgJVBgwEgDfAQAMAAgJBQ8oZwDAAQAZAAEJAACfGgAeAAABLgAECgkJDgABAAAAAA==.Tegmage:BAAALgAECgUJBQABLgAECgkJDgABAAAAAA==.Terentia:BAEALgAECgUJBQABLgAECgkJKwAUACQXAA==.',
Th='Thadind:BAAALgAECgEJAQAAAA==.Thalodrim:BAAALgAECgEJAQABLgAECgkJNAADANQjAA==.Tharelly:BAABLgAECn8WAAIXAAgJ3hntTwDmAQAXAAgJ3hntTwDmAQAAAA==.Thasserian:BAAALgADCgIJAgABLgAECgkJLAAeAL8jAA==.Theholymatt:BAACLgAFFH8RAAMRAAYJihaLFQBvAQARAAUJAxSLFQBvAQASAAQJmhNtaQDLAAAuAAQKfzcAAxIACQkpIx4LAAUDABIACQkpIx4LAAUDABEABwnnJEEPAJsCAAAA.Thendari:BAABLgAECn9oAAIPAAkJWBYKBQAXAgAPAAkJWBYKBQAXAgAAAA==.Theodus:BAABLgAECn8yAAIXAAkJhxkjNABBAgAXAAkJhxkjNABBAgAAAA==.Therayen:BAAALgADCgQJBAAAAA==.Theràpy:BAAALgAECgQJBQAAAA==.Thesmaugmatt:BAABLgAECn8UAAIkAAgJfxrgGgD3AQAkAAgJfxrgGgD3AQABLgAFFAYJEQARAIoWAA==.Thorrune:BAAALgAECgQJBAAAAA==.Threnor:BAABLgAECn82AAMTAAgJyyR0BADGAgATAAgJMyR0BADGAgAQAAcJZCP1IABLAgAAAA==.Thunderblade:BAAALgADCgIJAgAAAA==.',
Ti='Tialdari:BAAALgADCgYJBgAAAA==.Tiferis:BAACLgAFFH8SAAIRAAUJwBpPDwC1AQARAAUJwBpPDwC1AQAuAAQKfz0AAhEACQn3IKkEAEMDABEACQn3IKkEAEMDAAAA.Tislam:BAABLgAECn8XAAIeAAgJ3A3/YQB3AQAeAAgJ3A3/YQB3AQAAAA==.Tizzeia:BAAALgADCgMJBQAAAA==.',
To='Toaster:BAABLgAECn8pAAQTAAkJNR7NBACaAgATAAkJFhrNBACaAgAYAAcJpSCFDgDzAQAQAAYJtx9dMgDiAQAAAA==.Tobes:BAAALgADCgEJAQAAAA==.Tobiquer:BAABLgAECn89AAILAAkJcxswEQBNAgALAAkJcxswEQBNAgAAAA==.Toebackkey:BAAALgAECgEJAQAAAA==.Tojarmar:BAABLgAECn8XAAIYAAkJJBOyEgC1AQAYAAkJJBOyEgC1AQABLgAECgQJBAABAAAAAA==.',
Tr='Trauglodyte:BAAALgAECgYJBgAAAA==.Traydra:BAAALgAECgMJAwAAAA==.Triven:BAAALgAECgIJAgAAAA==.Troglodyte:BAACLgAFFH8dAAMGAAcJXRUOCwDTAQAGAAcJXRUOCwDTAQACAAEJYAxZbwBLAAAuAAQKf0gAAgYACQnMIjkEABYDAAYACQnMIjkEABYDAAAA.',
Ts='Tsonokwabain:BAABLgAECn8mAAQZAAkJhyJbAQAgAwAZAAkJhyJbAQAgAwAfAAEJah3VTwBJAAAMAAEJmAJwjAEYAAAAAA==.Tsunami:BAAALgADCgYJCAAAAA==.',
Tw='Twistdog:BAAALgAECgEJAwAAAA==.',
Ty='Tyranastrasz:BAABLgAECn8xAAIjAAkJ7hGMDgDcAQAjAAkJ7hGMDgDcAQAAAA==.Tyye:BAAALgAECgEJAQAAAA==.',
['Tâ']='Tâjik:BAABLgAECn8kAAINAAkJ4QWUJgBSAQANAAkJ4QWUJgBSAQAAAA==.',
Ud='Udderlytasty:BAAALgAECgEJAQAAAA==.',
Un='Unc:BAAALgAECgcJCAAAAA==.',
Va='Vade:BAAALgAFFAEJAwAAAA==.Vaelith:BAAALgAECggJDAAAAA==.Vaelyra:BAABLgAECn8uAAIKAAgJOxidSgCaAQAKAAgJOxidSgCaAQAAAA==.Vaerryn:BAABLgAECn8mAAQZAAgJMyPWBQBBAgAZAAcJFiPWBQBBAgAMAAMJcBttygDlAAAfAAIJQyBITQBRAAAAAA==.Vaethund:BAAALgAECggJEQAAAA==.Vailenya:BAAALgADCgEJAQABLgAECggJHAAJAFMfAA==.Valgavoth:BAAALgAECggJEwAAAA==.Vandrin:BAAALgADCgQJBgAAAA==.Vapir:BAAALgAECgMJAwAAAA==.Variala:BAABLgAECn8XAAMlAAgJig1HJgBnAQAlAAcJxQxHJgBnAQAHAAcJPQsmxwCmAAAAAA==.Vassyra:BAEBLgAECn8rAAIUAAkJJBfwBAAPAgAUAAkJJBfwBAAPAgAAAA==.',
Ve='Velara:BAAALgAECgYJBgAAAA==.Velesyn:BAABLgAECn8cAAMJAAgJUx/QBgAPAgAJAAcJKCDQBgAPAgAKAAIJtxGl8ABOAAAAAA==.Vellayna:BAAALgADCgYJBgAAAA==.',
Vi='Vilga:BAAALgADCgkJCQAAAA==.Viral:BAAALgAECgYJDwAAAA==.Viriex:BAAALgADCgEJAQAAAA==.Visone:BAAALgADCgEJAQAAAA==.Vitoria:BAAALgAECgEJAQAAAA==.',
Vo='Vocivus:BAAALgAECggJEwAAAA==.Voidlighter:BAABLgAECn8gAAMiAAkJWxmECwCqAgAiAAkJWxmECwCqAgAaAAYJKwrZRgDqAAABLgAECgkJMAARALsdAA==.Volundr:BAABLgAECn87AAIYAAgJ0BmZEADSAQAYAAgJ0BmZEADSAQAAAA==.Vonvaughan:BAAALgADCgcJCwABLgAECggJFwAVAOMhAA==.',
Vy='Vynirion:BAABLgAECn8UAAIXAAcJqxJUpACPAQAXAAcJqxJUpACPAQAAAA==.Vynisa:BAAALgAECgMJAwAAAA==.',
Wa='Waiseheil:BAAALgADCggJCQAAAA==.Warcreaper:BAABLgAECn8ZAAINAAgJSQZ4KQA8AQANAAgJSQZ4KQA8AQAAAA==.Wardellmo:BAAALgAECgEJAQAAAA==.Wargtar:BAABLgAECn8zAAINAAcJdyHpDABLAgANAAcJdyHpDABLAgAAAA==.Warlockbob:BAAALgAECgYJCwAAAA==.',
We='Weabe:BAABLgAECn8YAAMLAAcJFhHCMwAoAQALAAcJ9w/CMwAoAQAiAAIJpRHjSgBqAAAAAA==.Weebes:BAAALgAECggJDwAAAA==.',
Wh='Whiterrina:BAAALgADCgkJCgAAAA==.',
Wo='Woobee:BAAALgADCgEJAQAAAA==.',
Wy='Wyrdhoof:BAABLgAECn8iAAMEAAkJ9Ah9LwBTAQAEAAkJ9Ah9LwBTAQAcAAUJEgeehwCeAAAAAA==.',
['Wù']='Wùsthof:BAABLgAECn8eAAIHAAkJywobVgBmAQAHAAkJywobVgBmAQAAAA==.',
Xa='Xandrios:BAAALgADCgMJAwAAAA==.Xaron:BAAALgADCgMJAwAAAA==.',
Xi='Xiae:BAABLgAECn8yAAMCAAgJsSPzCwDxAgACAAgJsSPzCwDxAgAGAAYJIRmQMABuAQAAAA==.',
Xk='Xkwizet:BAABLgAECn8WAAIXAAgJcgYVqAApAQAXAAgJcgYVqAApAQAAAA==.',
Xo='Xorrin:BAAALgAECgYJDgAAAA==.',
Xy='Xylpho:BAAALgAECgEJAQAAAA==.',
Ye='Yet:BAABLgAECn8tAAISAAkJpCQ4BQBGAwASAAkJpCQ4BQBGAwAAAA==.',
Yi='Yiffweaver:BAABLgAECn8qAAIgAAkJvwkuKwBWAQAgAAkJvwkuKwBWAQAAAA==.',
Yo='Yokoriazen:BAABLgAECn8zAAIhAAkJRxNzDwDAAQAhAAkJRxNzDwDAAQAAAA==.',
Yu='Yurtnaut:BAAALgAECgYJDgAAAA==.',
Yv='Yvesass:BAAALgAECggJEgAAAA==.',
Za='Zarhianna:BAABLgAECn8jAAIEAAkJgBD4HwC6AQAEAAkJgBD4HwC6AQAAAA==.',
Ze='Zeo:BAAALgAECgEJAQAAAA==.',
Zm='Zmona:BAABLgAECn8xAAISAAkJHg/+YACkAQASAAkJHg/+YACkAQAAAA==.',
Zo='Zorsche:BAAALgADCgcJEQAAAA==.',
Zu='Zulrok:BAABLgAECn8tAAIQAAkJbB0zEQBlAgAQAAkJbB0zEQBlAgAAAA==.',
['Ðr']='Ðre:BAABLgAECn8VAAIXAAcJ0hZswwBfAQAXAAcJ0hZswwBfAQAAAA==.',
['Ût']='Ûther:BAAALgAECgYJEwAAAA==.',
['Ül']='Ültimecia:BAABLgAECn8uAAIXAAkJUiMZEwDiAgAXAAkJUiMZEwDiAgAAAA==.',
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
