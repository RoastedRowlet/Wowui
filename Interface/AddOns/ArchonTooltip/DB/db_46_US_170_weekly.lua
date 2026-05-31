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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Balance','Druid-Guardian','Shaman-Elemental','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Holy','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Warlock-Destruction','Warrior-Fury','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Evoker-Devastation','Monk-Windwalker','Monk-Mistweaver','Mage-Frost','Warrior-Protection','DeathKnight-Frost','Priest-Shadow','Mage-Arcane','Druid-Restoration','Warlock-Affliction','Warlock-Demonology','DeathKnight-Blood','Monk-Brewmaster','Paladin-Protection','Priest-Discipline','Evoker-Preservation','Hunter-Survival','Shaman-Enhancement','Evoker-Augmentation',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=46,date='2026-05-30',data={Ad='Adoraluna:BAAALgAECgEJAQAAAA==.Adunei:BAAALgAECgIJAgAAAA==.',
Ae='Aeginalla:BAAALgADCgcJEgABLgAECgYJCAABAAAAAA==.Aela:BAAALgADCgEJAQABLgAECgkJMwACAAYhAA==.Aesalon:BAABLgAECn80AAQDAAkJ1CMrAwDOAgADAAkJ1CMrAwDOAgAEAAIJrRTjeQA+AAAFAAIJGBNEXwA0AAAAAA==.',
Ah='Ahsokatano:BAABLgAECn8zAAMCAAkJBiHiBQA/AwACAAkJBiHiBQA/AwAGAAEJ8gzWnQAoAAAAAA==.',
Ai='Aimspet:BAAALgAECgYJEQAAAA==.Aircanada:BAAALgAECgIJBAAAAA==.',
Ak='Akela:BAABLgAECn8hAAIHAAkJ+wwiQgDEAQAHAAkJ+wwiQgDEAQAAAA==.',
Al='Algorithm:BAAALgAECgMJAwAAAA==.Alissu:BAAALgADCgIJAgAAAA==.Alvonaar:BAAALgADCgUJBwAAAA==.',
Am='Ames:BAAALgAECgQJBAAAAA==.Amonet:BAAALgAECgQJBwAAAA==.',
An='Anaelcheese:BAABLgAECn8aAAQIAAcJ2BQ/HgBkAQAIAAcJ2BQ/HgBkAQAJAAEJkg0sLgAnAAAKAAEJywAN9wATAAAAAA==.Anamis:BAABLgAECn8kAAILAAgJ/hKsJgB6AQALAAgJ/hKsJgB6AQAAAA==.Andrina:BAAALgADCgYJAgAAAA==.Angeldemon:BAAALgADCgYJCAAAAA==.Angras:BAABLgAECn8pAAIMAAkJcxJCOgADAgAMAAkJcxJCOgADAgAAAA==.Angryorc:BAAALgAECgQJBQAAAA==.Anja:BAAALgADCgkJFwAAAA==.Anolana:BAABLgAECn80AAMNAAgJjCJqCQB3AgANAAgJjCJqCQB3AgAOAAEJixFVIwA3AAAAAA==.Anyday:BAAALgADCgcJBwAAAA==.',
Ap='Aphalock:BAABLgAECn8mAAIPAAgJcRHeCgB2AQAPAAgJcRHeCgB2AQAAAA==.',
Ar='Aragoth:BAAALgAECgEJAQAAAA==.Ariûs:BAABLgAECn8VAAIQAAcJ+hBlNABjAQAQAAcJ+hBlNABjAQAAAA==.Arlin:BAAALgAECgUJDQAAAA==.Arlorian:BAABLgAECn8tAAIOAAkJGBBHCACwAQAOAAkJGBBHCACwAQAAAA==.Arorra:BAAALgADCgkJEQAAAA==.Arrex:BAAALgAECgYJCwAAAA==.Arrowsmites:BAABLgAECn8vAAIHAAkJ8BtuGwBrAgAHAAkJ8BtuGwBrAgAAAA==.',
Au='Aubani:BAABLgAECn8wAAMRAAkJFCDIBwD8AgARAAkJFCDIBwD8AgASAAUJIxLswQDoAAAAAA==.',
Ay='Ayperos:BAABLgAECn80AAMTAAgJ5husCgAmAgATAAgJ5husCgAmAgAQAAYJPxAVUgBhAQAAAA==.Ayvaria:BAAALgAECgYJEwABLgAECgkJKwAUACQXAA==.',
Ba='Baboyago:BAAALgAECgUJCAAAAA==.Badgerbrew:BAAALgADCgkJCQAAAA==.Baked:BAAALgAECgQJBAABLgAECggJGQASANwFAA==.Bakedpally:BAABLgAECn8ZAAISAAgJ3AWQsAACAQASAAgJ3AWQsAACAQAAAA==.Bandomar:BAABLgAECn8kAAIEAAgJogqgMwAwAQAEAAgJogqgMwAwAQAAAA==.Baniemo:BAAALgAECgIJAwAAAA==.Banigor:BAAALgAECgYJEAAAAA==.Basak:BAAALgAECgYJCwABLgAFFAQJDgABAAAAAQ==.',
Be='Beammescotty:BAAALgADCgQJBAAAAA==.Bearnuts:BAAALgADCgEJAQAAAA==.Beck:BAABLgAECn8yAAISAAkJjCG7DgDaAgASAAkJjCG7DgDaAgAAAA==.Beefflaps:BAAALgADCgEJAQAAAA==.Beggars:BAAALgAECgYJCQAAAA==.Belithsong:BAAALgAECgkJBQAAAA==.Bereth:BAAALgAECgUJDQAAAA==.Berreydingle:BAAALgAECgUJCgAAAA==.',
Bi='Bigkitty:BAABLgAECn8qAAIQAAkJnhmLFgAmAgAQAAkJnhmLFgAmAgABLgAECgcJIQAHAHIgAA==.Bikinibrenda:BAAALgAECgEJAQAAAA==.Biz:BAAALgADCgYJBwABLgAECggJFQAVAOMhAA==.',
Bl='Blackanvil:BAAALgAECgYJDQAAAA==.Blackautumn:BAAALgADCgcJDgABLgAECgcJHgAQAKsdAA==.Blainn:BAAALgAECgcJBwAAAA==.Blindfred:BAAALgAECggJDQAAAA==.Blitzedbust:BAAALgADCggJDQAAAA==.Bloodredsky:BAABLgAECn8YAAMWAAkJuQ5MLwCQAQAWAAkJuQ5MLwCQAQAVAAEJmwiwfwAxAAAAAA==.Bloodymagi:BAABLgAECn8bAAIXAAkJTAWKiQBJAQAXAAkJTAWKiQBJAQAAAA==.Bluesummer:BAABLgAECn8eAAQQAAcJqx3YKwCQAQAQAAYJQiHYKwCQAQAYAAYJxBrAGQCCAQATAAEJCAzpQQA1AAAAAA==.',
Bo='Bolts:BAAALgAECgEJAwAAAA==.Boomin:BAABLgAECn8wAAMFAAkJuhpTCABMAgAFAAkJuhpTCABMAgAEAAQJdQZ3YwBtAAAAAA==.',
Br='Brendameeks:BAAALgAECgcJEAAAAA==.Brewnashot:BAAALgADCggJCgAAAA==.Brewrain:BAAALgADCgEJAQAAAA==.Broadzinatl:BAABLgAECn8VAAIVAAgJ4yFZCACsAgAVAAgJ4yFZCACsAgAAAA==.Brom:BAAALgAECgYJBwAAAA==.Brïn:BAAALgAECgIJAgAAAA==.',
Bu='Bulwark:BAAALgADCgYJBgAAAA==.Bushwookië:BAAALgAECgIJAgAAAA==.',
['Bã']='Bãthory:BAABLgAECn8XAAIZAAkJIxTvCwCLAQAZAAkJIxTvCwCLAQAAAA==.',
['Bø']='Bøss:BAAALgADCgkJEQAAAA==.',
Ca='Calvert:BAAALgAECgUJBgAAAA==.Captnhammer:BAAALgAECgIJAgAAAA==.Carebearr:BAAALgADCgcJBwAAAA==.Carnelian:BAAALgAECgMJBQAAAA==.Castration:BAABLgAECn8YAAIaAAYJ3AnvRwDIAAAaAAYJ3AnvRwDIAAAAAA==.',
Ce='Ceylan:BAABLgAECn8vAAMXAAkJ9xikLQBMAgAXAAkJ9xikLQBMAgAbAAEJVQMVIQAqAAAAAA==.',
Ch='Chadillac:BAAALgAECgMJAwAAAA==.Chaleb:BAAALgAECgUJCAAAAA==.Charavane:BAAALgAECgEJAQAAAA==.Charlz:BAABLgAECn8jAAMaAAkJhBYJGQDiAQAaAAkJhBYJGQDiAQALAAQJChHLVQDfAAAAAA==.Charsifood:BAAALgAECgcJDwAAAA==.Chass:BAAALgADCgQJBAAAAA==.Cheatdr:BAABLgAECn8dAAIcAAYJbBEkUgAzAQAcAAYJbBEkUgAzAQAAAA==.Cheatpriest:BAABLgAECn83AAILAAkJ7RaXHgC4AQALAAkJ7RaXHgC4AQAAAA==.Chesthyr:BAAALgADCgcJBwAAAA==.Chesto:BAABLgAECn8yAAQdAAkJ7hySAwBbAgAdAAkJZBqSAwBbAgAPAAcJ4xqtCACkAQAeAAcJwRT2awCKAQAAAA==.Chimerax:BAAALgADCggJCAAAAA==.Chimken:BAAALgAECgcJCAABLgAECgkJKQATADUeAA==.Chokea:BAAALgAECgkJDgAAAA==.Chrome:BAAALgAECgEJAQAAAA==.Chuwhee:BAAALgADCgYJBgAAAA==.',
Co='Cognition:BAABLgAECn9BAAIHAAkJryVUAgBjAwAHAAkJryVUAgBjAwAAAA==.Coldvengance:BAABLgAECn8zAAIQAAgJUAq2OwBBAQAQAAgJUAq2OwBBAQAAAA==.Corpser:BAAALgADCgUJBQAAAA==.',
Cr='Cranki:BAAALgAECgUJBgABLgAECgIJBAABAAAAAA==.Cranknstein:BAAALgADCgQJBAABLgAECgIJBAABAAAAAA==.Crazycalla:BAAALgAFFAEJAgAAAA==.',
Cy='Cymindel:BAABLgAECn84AAIfAAkJCxrECgBMAgAfAAkJCxrECgBMAgAAAA==.',
Da='Dad:BAAALgADCgQJBAAAAA==.Daelein:BAAALgADCgEJAQABLgADCgEJAQABAAAAAA==.Daithi:BAAALgAECgcJEwAAAA==.Dakotà:BAABLgAECn8dAAIHAAYJAxaZbwBJAQAHAAYJAxaZbwBJAQAAAA==.Darc:BAAALgAECgMJBQAAAA==.Darklite:BAAALgADCgUJDAAAAA==.Darkmonk:BAAALgADCgUJBQAAAA==.Dassadin:BAAALgAECgQJBQAAAA==.Day:BAABLgAECn8fAAIHAAgJFBhwQQDGAQAHAAgJFBhwQQDGAQAAAA==.',
De='Decaydence:BAAALgAECggJEAAAAA==.Dejno:BAABLgAECn8YAAIQAAcJMiAYKACmAQAQAAcJMiAYKACmAQAAAA==.Deleted:BAAALgAECgEJAQABLgAECgkJHgAMAPEiAA==.Demonicly:BAABLgAECn8UAAIJAAcJuxNADQBlAQAJAAcJuxNADQBlAQAAAA==.Demönslayer:BAAALgAECgcJAwAAAA==.Derowski:BAAALgAECgQJBQAAAA==.Deroz:BAAALgADCgUJBQAAAA==.Dethra:BAAALgADCgcJCwAAAA==.Dezign:BAACLgAFFH8TAAIXAAYJ5RfPMAB7AQAXAAYJ5RfPMAB7AQAuAAQKfygAAhcACQl2IFAkAHUCABcACQl2IFAkAHUCAAAA.Dezígn:BAAALgAFFAMJAwABLgAFFAYJEwAXAOUXAA==.',
Di='Diabolical:BAAALgAECgEJAQAAAA==.Discordegirl:BAABLgAECn8WAAMgAAYJQQxETAC9AAAgAAUJvA5ETAC9AAAVAAEJVQLAqAAbAAAAAA==.Divinitÿ:BAAALgADCgIJAgABLgAECgkJLAAeAL8jAA==.',
Do='Dolgorukov:BAABLgAECn8uAAIHAAkJXhOzOgDdAQAHAAkJXhOzOgDdAQAAAA==.Dologony:BAABLgAECn8jAAIcAAkJmg5MOwCUAQAcAAkJmg5MOwCUAQAAAA==.',
Dr='Dracigor:BAAALgAECgIJAwAAAA==.Draconair:BAAALgADCgYJCAAAAA==.Dragonsbaine:BAAALgADCgMJAwAAAA==.Dragonz:BAAALgAECgUJDQAAAA==.Drakhan:BAAALgADCgIJAgAAAA==.Dre:BAAALgAECgMJCAAAAA==.Drikken:BAABLgAECn8/AAQKAAkJwxnqKwADAgAKAAkJOhfqKwADAgAIAAUJgBbPKQAKAQAJAAUJ2xukEgAIAQAAAA==.Drmaker:BAAALgAECgMJAwAAAA==.Drougs:BAABLgAECn8uAAIIAAkJVxiuFADIAQAIAAkJVxiuFADIAQAAAA==.Druiddeleted:BAAALgAECgEJAQABLgAECgkJHgAMAPEiAA==.',
Du='Dubbshot:BAAALgAECgEJAQAAAA==.Dumara:BAAALgADCgIJAgAAAA==.Durasan:BAABLgAECn8cAAIMAAYJjgjevwDmAAAMAAYJjgjevwDmAAAAAA==.Duressa:BAAALgAECgcJBwAAAA==.',
Dy='Dymund:BAAALgAECgIJBAAAAA==.',
['Dà']='Dàrkside:BAAALgAECgYJBgAAAA==.',
['Dö']='Dötdötdead:BAABLgAECn8pAAMPAAgJIhVQCACsAQAPAAgJIhVQCACsAQAeAAIJZwvT9gBhAAAAAA==.',
Ea='Earthie:BAAALgADCgEJAQAAAA==.Earthstorm:BAAALgADCgIJAgAAAA==.Eastwubz:BAAALgADCgIJAgAAAA==.',
Ed='Edge:BAAALgAECgMJBQAAAA==.',
Ef='Effin:BAAALgADCgUJBQAAAA==.Effindin:BAAALgAECgUJBwAAAA==.Effinfu:BAABLgAECn8fAAIgAAgJrxESJQByAQAgAAgJrxESJQByAQAAAA==.',
Ei='Eitent:BAABLgAECn8wAAMRAAkJux04DAC3AgARAAkJux04DAC3AgASAAcJuhIRdgCOAQAAAA==.',
El='Ele:BAAALgADCgcJCAABLgAECgcJEgABAAAAAA==.Ellesthara:BAAALgAECgYJDwAAAA==.Ellysiaa:BAABLgAECn8WAAIDAAYJLQUXKwCXAAADAAYJLQUXKwCXAAAAAA==.Elrïc:BAAALgADCgMJAwAAAA==.Elwynlana:BAAALgADCgYJBwAAAA==.Elysa:BAAALgADCgEJAQAAAA==.',
Em='Emberstorm:BAAALgAECgQJBQAAAA==.Emmakyn:BAABLgAECn8qAAMEAAgJMRQ9IgCdAQAEAAgJMRQ9IgCdAQAcAAcJMA0JUgA0AQAAAA==.',
En='Enezath:BAAALgADCgIJAgAAAA==.Entrerie:BAAALgADCgYJCwAAAA==.Enyxea:BAABLgAECn8VAAICAAgJFRdtJQAUAgACAAgJFRdtJQAUAgAAAA==.',
Ep='Ephemera:BAAALgAECgYJCwAAAA==.Epsolon:BAAALgAECgIJAgAAAA==.',
Er='Erikuh:BAAALgADCgEJAQAAAA==.Erodin:BAAALgAECgEJAQAAAA==.',
Es='Esmeray:BAAALgAECggJDAABLgAECgkJKwAUACQXAA==.Estala:BAAALgADCgUJBQAAAA==.',
Ey='Eyedontknow:BAABLgAECn8YAAIhAAcJYiC+CQAXAgAhAAcJYiC+CQAXAgAAAA==.Eyewana:BAABLgAECn8kAAIIAAkJchIWGQCXAQAIAAkJchIWGQCXAQAAAA==.',
Ez='Ezzka:BAABLgAECn8gAAIMAAgJORj5OAAIAgAMAAgJORj5OAAIAgAAAA==.',
Fa='Faelan:BAAALgADCgIJAQAAAA==.Fakesaint:BAAALgAECgYJCgAAAA==.Fangalor:BAAALgAECgEJAgAAAA==.Farnsworth:BAABLgAECn8UAAQeAAcJJxlLRQC/AQAeAAcJJxlLRQC/AQAdAAEJNBOWMQBBAAAPAAEJAACHSAAAAAABLgAECgkJNAADANQjAA==.Farzix:BAABLgAECn8jAAIGAAgJzAdPRQACAQAGAAgJzAdPRQACAQAAAA==.Façade:BAABLgAECn8mAAIMAAkJDxO4VACzAQAMAAkJDxO4VACzAQAAAA==.',
Fe='Feelgood:BAAALgAECgQJBAAAAA==.Fefifiona:BAACLgAFFH8FAAIiAAIJOA3DNAB9AAAiAAIJOA3DNAB9AAAuAAQKfxkAAiIACQkqFwoOAG8CACIACQkqFwoOAG8CAAAA.Fefifredrich:BAAALgAECgMJAwABLgAFFAIJBQAiADgNAA==.Fefifuredric:BAAALgAECgEJAgABLgAFFAIJBQAiADgNAA==.Felvira:BAABLgAECn8dAAMKAAgJPgT1wgCCAAAKAAYJbQP1wgCCAAAIAAUJWwTNTABeAAAAAA==.',
Fi='Finnw:BAAALgAECgcJEgAAAA==.Firelite:BAABLgAECn8bAAIGAAYJEhDRRwD4AAAGAAYJEhDRRwD4AAAAAA==.',
Fl='Flairlock:BAABLgAECn81AAMdAAgJtSCABAAwAgAdAAgJtSCABAAwAgAPAAIJBhVYNgA5AAAAAA==.Flee:BAABLgAECn8iAAINAAkJqRq5DABDAgANAAkJqRq5DABDAgAAAA==.',
Fo='Fookster:BAABLgAECn8ZAAIXAAkJyhOIOQAcAgAXAAkJyhOIOQAcAgAAAA==.Forsetee:BAABLgAFFH8GAAIgAAIJTRfCPACVAAAgAAIJTRfCPACVAAAAAA==.',
Fr='Frowdawn:BAABLgAECn85AAIOAAkJUxDQBgDiAQAOAAkJUxDQBgDiAQAAAA==.',
Fy='Fyf:BAAALgAECgYJBgABLgAECgIJBAABAAAAAA==.',
['Fí']='Físter:BAAALgAECgYJDwABLgAECgcJGgAMACoaAA==.',
Ga='Ga:BAAALgADCgYJBgAAAA==.Galadris:BAAALgADCgkJDwAAAA==.Garythenpc:BAAALgAECgUJDQAAAA==.Gaztoria:BAAALgADCggJCAABLgAECgkJLwAMANYiAA==.',
Ge='Genavieve:BAAALgADCgQJBAAAAA==.Gendra:BAAALgAECgEJAQAAAA==.',
Gh='Ghøst:BAAALgADCgEJAQAAAA==.Ghøstlord:BAAALgADCgEJAQAAAA==.',
Gi='Gilas:BAAALgADCgQJBAAAAA==.',
Gl='Glacialkitty:BAABLgAECn8tAAIcAAkJ4gstQQB6AQAcAAkJ4gstQQB6AQAAAA==.',
Go='Googoobler:BAABLgAECn8gAAIIAAgJKQcfKgAIAQAIAAgJKQcfKgAIAQAAAA==.Goudaluck:BAAALgADCgUJBwABLgAECgcJIQAHAHIgAA==.Goudanight:BAAALgAECgMJBAABLgAECgcJIQAHAHIgAA==.Goudavibes:BAAALgAECgEJAQABLgAECgcJIQAHAHIgAA==.',
Gr='Greenmagus:BAAALgAECgEJAQAAAA==.Grenadon:BAAALgAECgUJCgAAAA==.Gridimbor:BAAALgAECgEJAQAAAA==.Grimlilith:BAABLgAECn8bAAQdAAgJ/wSbEQATAQAdAAgJ9gSbEQATAQAeAAMJBAOmFgE8AAAPAAEJAAAogQALAAAAAA==.Grimmhoof:BAAALgAECgIJAgAAAA==.Grundy:BAAALgAECgUJCAAAAA==.',
Gu='Gumbi:BAAALgADCgIJAgAAAA==.',
Ha='Hadorya:BAABLgAECn82AAIaAAgJtBsRFQAIAgAaAAgJtBsRFQAIAgAAAA==.Hakitua:BAABLgAECn8mAAIJAAkJ2w2VDABzAQAJAAkJ2w2VDABzAQAAAA==.Hangi:BAAALgADCgkJCQAAAA==.Happymeel:BAAALgAECgEJAQAAAA==.Harleyqûinn:BAAALgAECgcJDQAAAA==.Hazard:BAABLgAECn82AAIQAAgJog6pMQBxAQAQAAgJog6pMQBxAQAAAA==.',
He='Healonwheels:BAAALgADCgMJAwAAAA==.Heimdall:BAAALgAECggJDgABLgAECgkJLAAeAL8jAA==.Heis:BAAALgAECgUJDQAAAA==.Hellboii:BAAALgAECggJEwAAAA==.Heyitsrat:BAABLgAECn8xAAISAAkJABcFPAD8AQASAAkJABcFPAD8AQAAAA==.',
Hi='Hiko:BAAALgAECgkJCAAAAA==.',
Ho='Holo:BAACLgAFFH8SAAMCAAYJJgqFAgC9AQACAAYJJgqFAgC9AQAGAAUJFB91FQBDAQAuAAQKfyEAAwYACQlzIWYDAG0DAAYACQlzIWYDAG0DAAIABwnXDgJCAHkBAAAA.Holos:BAAALgAECgEJAQABLgAFFAYJEgACACYKAA==.Holyangus:BAAALgAECgUJDAAAAA==.Holyyknight:BAAALgAECgcJEwAAAA==.',
Hu='Hugecrit:BAAALgADCgkJDwAAAA==.',
Ib='Ibbert:BAAALgADCggJEwAAAA==.',
Ic='Icculus:BAABLgAECn8jAAIHAAgJCxhvNAD0AQAHAAgJCxhvNAD0AQAAAA==.',
Il='Illuyanka:BAAALgAECgEJAQAAAA==.',
Im='Impasse:BAAALgAECgkJCAAAAA==.',
In='Indaskyz:BAAALgADCgEJAQAAAA==.',
Io='Iolz:BAAALgAECgYJCgAAAA==.',
Ir='Ironfist:BAABLgAECn88AAIgAAkJaSRyAQBPAwAgAAkJaSRyAQBPAwAAAA==.',
It='Itankworlds:BAAALgAECgUJBQABLgAECgcJDgABAAAAAA==.',
Iw='Iwanaplay:BAAALgAECgMJAwAAAA==.',
Ja='Jacolynn:BAABLgAECn8YAAIWAAcJ7BHsKwBXAQAWAAcJ7BHsKwBXAQAAAA==.Jaenei:BAAALgAECgcJDQAAAA==.',
Je='Jelly:BAAALgADCgIJAgAAAA==.',
Ji='Jinrok:BAAALgAECgUJBQAAAA==.',
Jo='Joatmoa:BAACLgAFFH8GAAIDAAMJNRRYCgDlAAADAAMJNRRYCgDlAAAuAAQKfxQAAgMACQmIHHINALwBAAMACQmIHHINALwBAAAA.Joeexotics:BAAALgADCgkJDAAAAA==.Jordanleah:BAAALgAECgQJBAAAAA==.',
Ju='July:BAAALgAECgcJDgAAAA==.Julytonidas:BAAALgAECgcJBwAAAA==.Jurac:BAAALgADCgcJGQAAAA==.',
Ka='Kaelnis:BAAALgAECggJEgAAAA==.Kaimargonar:BAAALgAECgYJDwAAAA==.Kaitoi:BAABLgAECn8XAAMDAAcJbRaHEACLAQADAAcJbRaHEACLAQAFAAUJKwhHQAB6AAAAAA==.Kallah:BAACLgAFFH8YAAIRAAYJZR14CAAHAgARAAYJZR14CAAHAgAuAAQKfzcAAhEACQnsI44BAGsDABEACQnsI44BAGsDAAAA.Kalthos:BAABLgAECn9AAAMjAAkJHBk0CABdAgAjAAgJjxk0CABdAgAUAAkJnBFxBgDSAQAAAA==.Kamakizeg:BAABLgAECn8tAAISAAkJBBMrUQC9AQASAAkJBBMrUQC9AQAAAA==.Kamayla:BAAALgADCgYJBgAAAA==.Karnus:BAAALgADCgUJBQAAAA==.Kaspen:BAAALgADCgMJAwAAAA==.Kateria:BAABLgAECn8nAAIXAAkJKR2uHACaAgAXAAkJKR2uHACaAgAAAA==.',
Ke='Kestrelle:BAAALgAECgcJEwABLgAECgkJOwAcAFsQAA==.Keyzeus:BAABLgAECn8jAAIUAAgJVxcXBgDgAQAUAAgJVxcXBgDgAQAAAA==.',
Kh='Khas:BAAALgADCgkJGgAAAA==.Khui:BAACLgAFFH8bAAIWAAYJSyVMBQB5AgAWAAYJSyVMBQB5AgAuAAQKfyUAAxYACAkWJcACAFcDABYACAkWJcACAFcDABUAAwkwGJBKAMAAAAAA.',
Ki='Kiarorin:BAAALgAECgEJAQAAAA==.Killerdeath:BAAALgAECgQJBwAAAA==.Kipziep:BAAALgAECgIJAgAAAA==.Kittkat:BAAALgADCgkJEAAAAA==.',
Kn='Knìghtmàrè:BAACLgAFFH8SAAMMAAYJ3xkaIwCfAQAMAAUJ3xkaIwCfAQAfAAEJAAB0RgAAAAAuAAQKfygAAgwACQn9INMSAAsDAAwACQn9INMSAAsDAAAA.Kníghtfíst:BAABLgAECn8rAAIWAAkJ/RfyEgBlAgAWAAkJ/RfyEgBlAgABLgAFFAYJEgAMAN8ZAA==.',
Ko='Koltharaz:BAAALgAECgEJAQAAAA==.Korheo:BAAALgADCgUJBQAAAA==.Korloff:BAAALgAECgcJDQABLgAECgcJHAABAAAAAQ==.Kozan:BAAALgAECgcJHAAAAQ==.',
Kr='Krazysniper:BAABLgAECn8oAAMHAAgJCRxNKQAiAgAHAAcJEB9NKQAiAgAkAAEJ4wmIWgA5AAAAAA==.Krokk:BAABLgAECn8UAAIGAAcJ9Qe9SgDuAAAGAAcJ9Qe9SgDuAAAAAA==.',
Ku='Kungfister:BAAALgAECgEJAQAAAA==.Kur:BAAALgAECgIJAgABLgAFFAQJDgABAAAAAQ==.',
La='Laatt:BAABLgAECn8aAAMSAAgJFh66KgB5AgASAAgJFh66KgB5AgARAAYJOBhuNgBeAQAAAA==.Lacosanostra:BAAALgAECgYJCgAAAA==.Laeiny:BAAALgADCgYJBgAAAA==.Lateralus:BAAALgAECgUJBgABLgAECggJGgASABYeAA==.Latharel:BAAALgAECgEJAQAAAA==.Lawluss:BAABLgAECn8lAAIHAAcJ5hkzSgCrAQAHAAcJ5hkzSgCrAQAAAA==.Layethelor:BAAALgAECgEJBAAAAA==.',
Le='Legacyshot:BAAALgAECggJIwAAAQ==.Leigola:BAAALgADCgUJCQAAAA==.Lela:BAAALgAECgYJBgAAAA==.Lezsul:BAAALgADCgEJAQAAAA==.',
Li='Lickthecrit:BAAALgAECggJEgAAAA==.Lidrelle:BAABLgAECn8dAAISAAcJAhLNggBOAQASAAcJAhLNggBOAQAAAA==.Lightguard:BAAALgAECgYJBgAAAA==.Lighthouse:BAABLgAECn8uAAISAAkJlxumLQAxAgASAAkJlxumLQAxAgAAAA==.Lileth:BAAALgAECgUJBQAAAA==.Lilpaws:BAAALgAECgYJBgAAAA==.Lizy:BAAALgADCgUJBQAAAA==.',
Lo='Locust:BAAALgAECgMJAwAAAA==.Lokkar:BAAALgADCgQJBAAAAA==.Lolalazer:BAABLgAECn8WAAIKAAgJ9RW4VQBtAQAKAAgJ9RW4VQBtAQAAAA==.Lolhahabaha:BAAALgAECggJDAAAAA==.Loopie:BAAALgADCgYJCgAAAA==.Lovesomev:BAAALgADCgMJAwAAAA==.',
Lu='Luckÿ:BAABLgAECn8XAAIfAAcJlxU3HwBBAQAfAAcJlxU3HwBBAQAAAA==.Lunabelle:BAAALgADCgEJAQAAAA==.Lunchbox:BAAALgAECgkJAQAAAA==.Lustfull:BAAALgAECgEJAgABLgAECgkJHwAHAPgfAA==.',
Ly='Lypally:BAABLgAECn8sAAISAAgJHQ7RdgBmAQASAAgJHQ7RdgBmAQAAAA==.',
['Ló']='Lóla:BAABLgAECn8uAAIKAAkJziOFBgASAwAKAAkJziOFBgASAwAAAA==.',
['Lô']='Lônè:BAAALgAECgUJBwAAAA==.',
Ma='Maani:BAAALgAECgEJAQAAAA==.Madeah:BAACLgAFFH8kAAMNAAgJcxVqAgB7AgANAAgJNxVqAgB7AgAOAAYJOw9BAgB/AQAuAAQKfyEAAw0ACAlGHtkMAMsCAA0ACAlGHtkMAMsCAA4AAQnoGt8aAFEAAAAA.Mahimahi:BAAALgAECggJCAAAAA==.Malýs:BAAALgAECgEJAQAAAA==.Mardain:BAABLgAECn8fAAIlAAkJphXLCAAcAgAlAAkJphXLCAAcAgAAAA==.Mariacuras:BAABLgAECn8VAAIRAAgJ3QsuMgB3AQARAAgJ3QsuMgB3AQAAAA==.Marle:BAABLgAECn8yAAIKAAkJqheQJAAmAgAKAAkJqheQJAAmAgAAAA==.Marlete:BAAALgADCgYJBQAAAA==.Marshoon:BAAALgAECgIJAgAAAA==.Martis:BAAALgAECgYJBwAAAA==.Marynne:BAABLgAECn87AAMcAAkJWxBDMgDCAQAcAAkJWxBDMgDCAQAEAAEJSwJ8mgAMAAAAAA==.Matthis:BAAALgAECgUJBwAAAA==.Mazuko:BAABLgAECn8qAAIJAAgJ6RYMCQDFAQAJAAgJ6RYMCQDFAQAAAA==.',
Me='Medadh:BAAALgADCgUJBQAAAA==.Meepe:BAAALgADCgcJDAAAAA==.Meilnesar:BAAALgAECgIJAgAAAA==.Melaerissa:BAABLgAECn8vAAMaAAgJhQ9tJACGAQAaAAgJhQ9tJACGAQALAAUJxQzERwCvAAAAAA==.Melbrooks:BAAALgADCgcJDQAAAA==.Melivant:BAAALgAECgUJDwABLgAECgYJEAABAAAAAA==.Merrikeath:BAAALgAECggJEQAAAA==.Merriklade:BAABLgAECn8kAAIQAAcJdQkeRQAZAQAQAAcJdQkeRQAZAQAAAA==.',
Mi='Missyjelliot:BAAALgAECgQJBwAAAA==.',
Mo='Moof:BAAALgADCgEJAQAAAA==.Morchuk:BAAALgADCgMJAwAAAA==.Morthos:BAAALgAECgMJBgAAAA==.',
Mw='Mw:BAAALgADCgIJAgABLgAECgcJEgABAAAAAA==.',
['Mà']='Màrli:BAAALgAECgEJAgAAAA==.',
['Mâ']='Mâgs:BAABLgAECn8gAAIhAAkJWhKWDwCvAQAhAAkJWhKWDwCvAQAAAA==.',
Na='Nabbed:BAAALgAECgcJCAABLgAECgkJKQATADUeAA==.Nakasid:BAACLgAFFH8HAAILAAMJTgtaHwCdAAALAAMJTgtaHwCdAAAuAAQKfzQABAsACQntFncQAEwCAAsACQntFncQAEwCABoABwkVCNQ5ACIBACIABAlbCsROAJYAAAAA.Nalaya:BAAALgAECgEJAQAAAA==.Nashoba:BAAALgADCgQJBAAAAA==.Natooka:BAAALgAECggJDgAAAA==.Navane:BAAALgAECgEJAgAAAA==.',
Ne='Necromaniac:BAAALgAECgEJAQAAAA==.Neenja:BAAALgADCgYJBgAAAA==.Nefurtatta:BAAALgADCgEJAQAAAA==.Nertlogi:BAAALgADCgIJAgAAAA==.Nesrÿn:BAAALgADCgIJAgAAAA==.Nestina:BAAALgADCgMJBAAAAA==.Netherkeeper:BAABLgAECn8rAAIKAAkJsBB8OwDCAQAKAAkJsBB8OwDCAQAAAA==.Nevaehstar:BAABLgAECn8yAAIbAAkJRR0GAQCzAgAbAAkJRR0GAQCzAgAAAA==.Neverëst:BAAALgAECgEJAQAAAA==.',
Ni='Nibuto:BAAALgAECgQJCQAAAA==.Nightvision:BAAALgADCgMJAgAAAA==.Nijun:BAEBLgAECn8sAAILAAkJOxRDHADMAQALAAkJOxRDHADMAQAAAA==.Nikolia:BAAALgAECgIJAgAAAA==.Nini:BAABLgAECn8hAAIEAAgJZwI+VQCfAAAEAAgJZwI+VQCfAAAAAA==.Ninx:BAAALgAECgQJBAAAAA==.Nirazal:BAAALgADCgQJBQAAAA==.',
No='Noivana:BAAALgAFFAMJAwABLgAFFAUJEAAIANcSAA==.Nokru:BAAALgADCgMJBAAAAA==.Norgannia:BAAALgADCgkJDwAAAA==.Notprepared:BAAALgADCgEJAQAAAA==.Noys:BAAALgADCgcJDAAAAA==.',
Nz='Nzuul:BAAALgAECgMJAwAAAA==.',
Ol='Oldbenkenobi:BAAALgAECgQJCAAAAA==.Ollichi:BAAALgADCgQJBAAAAA==.Ollifuzzle:BAAALgAECgEJAgAAAA==.',
Op='Oppaissiah:BAABLgAECn87AAMQAAkJhiLXBwDQAgAQAAkJ8R/XBwDQAgAYAAgJJCFcBwB3AgAAAA==.',
Or='Oraclespyro:BAABLgAECn8XAAImAAYJawL+bABoAAAmAAYJawL+bABoAAABLgAECggJCQABAAAAAA==.Orlakx:BAAALgADCggJFAAAAA==.Orman:BAAALgAECgEJAQAAAA==.',
Os='Osoroshi:BAAALgAECgQJBAAAAA==.',
Ov='Ovrind:BAAALgADCgEJAQAAAA==.',
Oz='Ozài:BAAALgADCgcJCgAAAA==.',
Pa='Padmê:BAAALgAECgcJDAAAAA==.Papasbich:BAAALgAECgYJCwABLgAECgkJPAASAE8SAA==.Patronous:BAAALgADCgUJBgAAAA==.',
Pe='Percthirty:BAAALgAECgEJAgAAAA==.Permafrost:BAAALgADCggJCgAAAA==.Perscila:BAAALgADCgUJBQAAAA==.',
Pi='Piggy:BAAALgAECgQJBgAAAA==.',
Pl='Planet:BAAALgADCgEJAQAAAA==.',
Po='Porkchoplust:BAAALgADCgUJBQAAAA==.Porkchopw:BAAALgAECgcJAQAAAA==.Porkribs:BAAALgAECgcJBAAAAA==.',
Pr='Presap:BAABLgAECn8sAAMcAAgJxCFnCwD3AgAcAAgJxCFnCwD3AgAEAAEJAACrdgBJAAABLgAECggJFQAjAHcbAA==.Promethius:BAAALgADCgQJBAAAAA==.Proscris:BAAALgADCgUJBQAAAA==.Prïsm:BAAALgADCgYJBgAAAA==.',
Pt='Ptmuchuk:BAAALgADCgYJBgAAAA==.',
Pu='Puca:BAAALgAECgUJDQAAAA==.Pumdmuc:BAACLgAFFH8HAAILAAMJLBlIGADZAAALAAMJLBlIGADZAAAuAAQKf0EAAwsACQmaIdoGAN8CAAsACQmaIdoGAN8CABoABwkqBa1MALUAAAAA.Purrie:BAAALgADCgIJAgAAAA==.',
['Pâ']='Pâlly:BAAALgAECgcJEAAAAA==.',
Qu='Quikglaives:BAAALgAECgQJBwAAAA==.Quille:BAAALgAECgYJDwAAAA==.',
Ra='Rahhem:BAABLgAECn8eAAIhAAkJrRJCDwC0AQAhAAkJrRJCDwC0AQAAAA==.Rallo:BAAALgAECgEJAQAAAA==.Rayspaly:BAAALgAECgEJAQAAAA==.',
Re='Recbra:BAAALgAECgIJAgAAAA==.Reddelish:BAAALgADCgYJCQAAAA==.Redrek:BAAALgADCgcJEAAAAA==.Redshunter:BAAALgADCgIJAgAAAA==.Redsknight:BAAALgADCgkJCQAAAA==.Redsmonk:BAAALgADCgYJBwAAAA==.Redwinter:BAAALgAECgIJBAABLgAECgcJHgAQAKsdAA==.Remmie:BAAALgAECgYJDAAAAA==.Retrolbution:BAAALgADCgkJEQAAAA==.Reznik:BAAALgAECgEJAQAAAA==.',
Rh='Rhaokir:BAAALgADCgIJAgAAAA==.',
Ri='Riqua:BAABLgAECn8fAAIcAAgJRRMpLgDaAQAcAAgJRRMpLgDaAQAAAA==.',
Ro='Rockmonsta:BAAALgAECgEJAQAAAA==.Rodeo:BAABLgAECn8sAAIEAAkJABDmHgC3AQAEAAkJABDmHgC3AQAAAA==.Rotgutwiskey:BAAALgADCgcJEwAAAA==.Roxies:BAAALgAFFAEJAQAAAA==.Royan:BAAALgAECgYJBgAAAA==.',
Rp='Rpg:BAAALgAECgcJDgAAAA==.',
Ru='Rumie:BAABLgAECn8bAAIKAAYJeQ6eegA4AQAKAAYJeQ6eegA4AQAAAA==.Runty:BAAALgADCgMJAwAAAA==.',
Sa='Sacket:BAAALgAECgQJBAAAAA==.Sadnhornless:BAAALgAECgEJAgAAAA==.Saeti:BAACLgAFFH8KAAMDAAQJTxnaCQDuAAADAAMJmhnaCQDuAAAEAAEJbxgXPQBQAAAuAAQKfzcABQMACQkaIZYHAG8CAAMACQkaIZYHAG8CAAQABgmdG9cmAH0BAAUABAm8FcQyALYAABwABAkUFh2BAKYAAAAA.Sandril:BAAALgAECgcJDAAAAA==.Sapplesauce:BAABLgAECn8XAAINAAgJ5BfbGgCoAQANAAgJ5BfbGgCoAQAAAA==.',
Sc='Scryer:BAAALgAECgEJAQAAAA==.',
Se='Serenìty:BAAALgAECggJDQAAAA==.Seresin:BAACLgAFFH8FAAMcAAMJHwXiRgCIAAAcAAMJHwXiRgCIAAAEAAEJ4wbcQwA0AAAuAAQKfzoAAhwACAkpG90aAFsCABwACAkpG90aAFsCAAAA.',
Sh='Shadý:BAABLgAECn8vAAIHAAkJ5ApaSQCtAQAHAAkJ5ApaSQCtAQAAAA==.Shamanoodles:BAAALgAECgEJAQABLgAECgkJHgAMAPEiAA==.Shinbin:BAAALgAECgEJAgAAAA==.Shonna:BAABLgAECn8oAAQPAAgJLBrCCQCNAQAeAAgJ1hcoPgDXAQAPAAcJeBjCCQCNAQAdAAIJERlTLQBEAAAAAA==.Shortwarrior:BAABLgAECn8xAAIQAAkJCRsfEQBbAgAQAAkJCRsfEQBbAgAAAA==.Shrimpimp:BAAALgAECgQJBAAAAA==.',
Si='Sidarya:BAAALgAECggJEgAAAA==.Sidera:BAAALgAECgYJBwAAAA==.Siduna:BAAALgADCgEJAQAAAA==.Silent:BAACLgAFFH8LAAMQAAMJqxqjJgD4AAAQAAMJqxqjJgD4AAATAAEJPAy2NABEAAAuAAQKfxsAAxMACQkkFM4ZACUBABAABwkdEgZLAHkBABMABgkoEs4ZACUBAAAA.Silverserket:BAAALgAECgIJBAAAAA==.Silverserqet:BAAALgADCgEJAQAAAA==.',
Sk='Skinnybutt:BAAALgADCgkJEQAAAA==.Skippinskipp:BAAALgAECgcJCwAAAA==.Skymaggedon:BAEBLgAECn8zAAMCAAkJzgxRSgBpAQACAAkJzgxRSgBpAQAGAAgJsAfgQgAMAQAAAA==.',
Sl='Slappadrago:BAAALgAECgkJEwAAAA==.',
Sm='Smileyriley:BAABLgAECn8aAAIEAAcJzQUWSADPAAAEAAcJzQUWSADPAAAAAA==.',
Sn='Sneakylinks:BAAALgAECgMJBAABLgAECgcJDgABAAAAAA==.Snotlocker:BAAALgAECgEJAQAAAA==.',
So='Sodexorod:BAAALgADCgYJBwAAAA==.Sofiophya:BAAALgAECgUJDQAAAA==.Sooki:BAAALgAECgIJAwAAAA==.Sorlis:BAAALgAECgUJBQAAAA==.Soulber:BAABLgAECn8VAAIMAAgJ2RPqTgDDAQAMAAgJ2RPqTgDDAQAAAA==.Sourdew:BAABLgAECn8eAAIVAAcJtB7UFgDoAQAVAAcJtB7UFgDoAQAAAA==.',
Sp='Sparkey:BAAALgAECgIJAgAAAA==.Spiritair:BAABLgAECn8VAAMjAAgJdxu9BgCCAgAjAAgJdxu9BgCCAgAUAAEJAACHKgAAAAAAAA==.Spunklestain:BAAALgADCggJDQABLgAECgkJEwABAAAAAA==.Spyke:BAAALgADCgEJAQAAAA==.Spykids:BAAALgAECgQJBAAAAA==.',
Sr='Srix:BAAALgAECgEJAQAAAA==.',
St='Starrdust:BAEALgAECgQJBwAAAA==.Stelle:BAABLgAECn8XAAIiAAgJBBEYJABzAQAiAAgJBBEYJABzAQAAAA==.Sternhoof:BAAALgAECgEJAQAAAA==.Stylos:BAABLgAECn8rAAIlAAgJ4BCOEACJAQAlAAgJ4BCOEACJAQAAAA==.Stãrburst:BAAALgAECgcJDQAAAA==.',
Ta='Taissa:BAAALgADCggJCgAAAA==.Taopaípai:BAAALgADCgMJBgAAAA==.Tas:BAAALgAECgQJBAAAAA==.Tatertotz:BAAALgAECgYJEQAAAA==.',
Te='Technine:BAAALgADCgMJAwAAAA==.Techno:BAAALgAECgcJAQAAAA==.Tegbless:BAAALgAECgkJDgAAAA==.Tegchill:BAABLgAECn8dAAQfAAgJNBnXEADjAQAfAAgJVBjXEADjAQAMAAgJBQ8oZwDAAQAZAAEJAACfGgAeAAABLgAECgkJDgABAAAAAA==.Tegmage:BAAALgAECgUJBQABLgAECgkJDgABAAAAAA==.Terentia:BAAALgAECgUJBQABLgAECgkJKwAUACQXAA==.',
Th='Thalodrim:BAAALgAECgEJAQABLgAECgkJNAADANQjAA==.Tharelly:BAABLgAECn8VAAIXAAgJ3hlLSwDiAQAXAAgJ3hlLSwDiAQAAAA==.Thasserian:BAAALgADCgIJAgABLgAECgkJLAAeAL8jAA==.Theholymatt:BAACLgAFFH8QAAMRAAUJcBlDGwAtAQARAAQJABdDGwAtAQASAAQJmhNxXQDUAAAuAAQKfy4AAxIACQkpI6gJAAcDABIACQkpI6gJAAcDABEABwnTI0EPAJsCAAAA.Thendari:BAABLgAECn9fAAIPAAkJ8RQsBQAFAgAPAAkJ8RQsBQAFAgAAAA==.Theodus:BAABLgAECn8yAAIXAAkJhxnVMAA+AgAXAAkJhxnVMAA+AgAAAA==.Therayen:BAAALgADCgQJBAAAAA==.Theràpy:BAAALgAECgQJBQAAAA==.Thesmaugmatt:BAABLgAECn8UAAImAAgJfxpnGQDyAQAmAAgJfxpnGQDyAQABLgAFFAUJEAARAHAZAA==.Thorrune:BAAALgAECgQJBAAAAA==.Threnor:BAABLgAECn8uAAMTAAgJyyRDBADCAgATAAgJECRDBADCAgAQAAcJZCP1IABLAgAAAA==.Thunderblade:BAAALgADCgIJAgAAAA==.',
Ti='Tialdari:BAAALgADCgYJBgAAAA==.Tiferis:BAACLgAFFH8QAAIRAAQJRB92EwB1AQARAAQJRB92EwB1AQAuAAQKfzYAAhEACQmNHOAMAK0CABEACQmNHOAMAK0CAAAA.Tislam:BAABLgAECn8VAAIeAAgJmg1eXgB5AQAeAAgJmg1eXgB5AQAAAA==.Tizzeia:BAAALgADCgMJBQAAAA==.',
To='Toaster:BAABLgAECn8pAAQTAAkJNR7NBACaAgATAAkJFhrNBACaAgAYAAcJpSCNDQD6AQAQAAYJtx9dMgDiAQAAAA==.Tobes:BAAALgADCgEJAQAAAA==.Tobiquer:BAABLgAECn87AAILAAkJbRsyEABPAgALAAkJbRsyEABPAgAAAA==.Toebackkey:BAAALgAECgEJAQAAAA==.Tojarmar:BAABLgAECn8XAAIYAAkJJBNMEQC9AQAYAAkJJBNMEQC9AQABLgAECgQJBAABAAAAAA==.',
Tr='Trauglodyte:BAAALgAECgYJBgAAAA==.Traydra:BAAALgAECgMJAwAAAA==.Triven:BAAALgAECgIJAgAAAA==.Troglodyte:BAACLgAFFH8bAAMGAAYJORnWCwCmAQAGAAYJORnWCwCmAQACAAEJYAyWZgBLAAAuAAQKf0cAAgYACQnMIs4DABsDAAYACQnMIs4DABsDAAAA.',
Ts='Tsonokwabain:BAABLgAECn8gAAQZAAkJbCFNAgDCAgAZAAkJbCFNAgDCAgAfAAEJah2MSwBKAAAMAAEJmAIseAEYAAAAAA==.Tsunami:BAAALgADCgYJBgAAAA==.',
Tw='Twistdog:BAAALgAECgEJAwAAAA==.',
Ty='Tyranastrasz:BAABLgAECn8xAAIjAAkJ7hH2DQDdAQAjAAkJ7hH2DQDdAQAAAA==.Tyye:BAAALgAECgEJAQAAAA==.',
['Tâ']='Tâjik:BAABLgAECn8kAAINAAkJ4QV/JABWAQANAAkJ4QV/JABWAQAAAA==.',
Ud='Udderlytasty:BAAALgAECgEJAQAAAA==.',
Un='Unc:BAAALgAECgcJCAAAAA==.',
Va='Vade:BAAALgAFFAEJAwAAAA==.Vaelith:BAAALgAECggJDAAAAA==.Vaelyra:BAABLgAECn8uAAIKAAgJOxg0RwCZAQAKAAgJOxg0RwCZAQAAAA==.Vaerryn:BAABLgAECn8kAAQZAAgJMyNCBQA8AgAZAAcJFiNCBQA8AgAMAAIJFxwd9wCYAAAfAAIJQyAiSQBRAAAAAA==.Vaethund:BAAALgAECggJDwAAAA==.Vailenya:BAAALgADCgEJAQABLgAECggJHAAJAFMfAA==.Valgavoth:BAAALgAECggJEwAAAA==.Vandrin:BAAALgADCgQJBgAAAA==.Vapir:BAAALgAECgMJAwAAAA==.Variala:BAABLgAECn8VAAMkAAgJ8wysJABoAQAkAAcJxQysJABoAQAHAAcJiAn2wwCZAAAAAA==.Vassyra:BAABLgAECn8rAAIUAAkJJBeNBAAXAgAUAAkJJBeNBAAXAgAAAA==.',
Ve='Velara:BAAALgAECgYJBgAAAA==.Velesyn:BAABLgAECn8cAAMJAAgJUx9zBgASAgAJAAcJKCBzBgASAgAKAAIJtxEx5ABOAAAAAA==.Vellayna:BAAALgADCgYJBgAAAA==.',
Vi='Vilga:BAAALgADCgkJCQAAAA==.Viral:BAAALgAECgYJDwAAAA==.Viriex:BAAALgADCgEJAQAAAA==.Visone:BAAALgADCgEJAQAAAA==.Vitoria:BAAALgAECgEJAQAAAA==.',
Vo='Vocivus:BAAALgAECggJEwAAAA==.Voidlighter:BAABLgAECn8gAAMiAAkJWxm/CgCmAgAiAAkJWxm/CgCmAgAaAAYJKwrYRQDRAAABLgAECgkJMAARALsdAA==.Volundr:BAABLgAECn82AAIYAAgJsxlEEADMAQAYAAgJsxlEEADMAQAAAA==.Vonvaughan:BAAALgADCgcJCwABLgAECggJFQAVAOMhAA==.',
Vy='Vynirion:BAABLgAECn8UAAIXAAcJqxJUpACPAQAXAAcJqxJUpACPAQAAAA==.Vynisa:BAAALgAECgMJAwAAAA==.',
Wa='Waiseheil:BAAALgADCggJCQAAAA==.Warcreaper:BAABLgAECn8XAAINAAgJFgasJwA9AQANAAgJFgasJwA9AQAAAA==.Wargtar:BAABLgAECn8sAAINAAcJdyHqCwBPAgANAAcJdyHqCwBPAgAAAA==.Warlockbob:BAAALgAECgYJCwAAAA==.',
We='Weabe:BAABLgAECn8YAAMLAAcJFhEjMQAwAQALAAcJ9w8jMQAwAQAiAAIJpRHjSgBqAAAAAA==.Weebes:BAAALgAECggJDQAAAA==.',
Wh='Whiterrina:BAAALgADCgkJCgAAAA==.',
Wo='Woobee:BAAALgADCgEJAQAAAA==.',
Wy='Wyrdhoof:BAABLgAECn8fAAMEAAcJlAhQQwDjAAAEAAcJlAhQQwDjAAAcAAUJEgfZggCiAAAAAA==.',
['Wù']='Wùsthof:BAABLgAECn8eAAIHAAkJywobVgBmAQAHAAkJywobVgBmAQAAAA==.',
Xa='Xandrios:BAAALgADCgMJAwAAAA==.Xaron:BAAALgADCgMJAwAAAA==.',
Xi='Xiae:BAABLgAECn8tAAMCAAgJsSPGCgD0AgACAAgJsSPGCgD0AgAGAAUJDRFEUwDQAAAAAA==.',
Xk='Xkwizet:BAABLgAECn8WAAIXAAgJcgYGqQARAQAXAAgJcgYGqQARAQAAAA==.',
Xo='Xorrin:BAAALgAECgYJDgAAAA==.',
Xy='Xylpho:BAAALgADCgEJAQAAAA==.',
Ye='Yet:BAABLgAECn8rAAISAAkJpCSnBABDAwASAAkJpCSnBABDAwAAAA==.',
Yi='Yiffweaver:BAABLgAECn8qAAIgAAkJvwltKQBWAQAgAAkJvwltKQBWAQAAAA==.',
Yo='Yokoriazen:BAABLgAECn8zAAIhAAkJRxNXDgDEAQAhAAkJRxNXDgDEAQAAAA==.',
Yu='Yurtnaut:BAAALgAECgYJDgAAAA==.',
Yv='Yvesass:BAAALgAECgYJDQAAAA==.',
Za='Zarhianna:BAABLgAECn8jAAIEAAkJgBDTHQDAAQAEAAkJgBDTHQDAAQAAAA==.',
Ze='Zeo:BAAALgAECgEJAQAAAA==.',
Zm='Zmona:BAABLgAECn8wAAISAAkJHg/IWwCiAQASAAkJHg/IWwCiAQAAAA==.',
Zo='Zorsche:BAAALgADCgUJBwAAAA==.',
Zu='Zulrok:BAABLgAECn8sAAIQAAkJbB2yDwBpAgAQAAkJbB2yDwBpAgAAAA==.',
['Ðr']='Ðre:BAABLgAECn8VAAIXAAcJ0hZswwBfAQAXAAcJ0hZswwBfAQAAAA==.',
['Ût']='Ûther:BAAALgAECgYJEAAAAA==.',
['Ül']='Ültimecia:BAABLgAECn8rAAIXAAkJMyPZGgAMAwAXAAkJMyPZGgAMAwAAAA==.',
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
