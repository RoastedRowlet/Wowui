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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Balance','Druid-Guardian','Shaman-Elemental','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Holy','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Warlock-Destruction','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Warrior-Protection','DeathKnight-Frost','Priest-Shadow','Mage-Arcane','Druid-Restoration','Warlock-Affliction','Warlock-Demonology','DeathKnight-Blood','Monk-Brewmaster','Priest-Discipline','Evoker-Preservation','Hunter-Survival','Shaman-Enhancement','Paladin-Protection','Evoker-Augmentation',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Adoraluna:BAAALgAECgEJAQAAAA==.Adunei:BAAALgAECgIJAgAAAA==.',
Ae='Aeginalla:BAAALgADCgcJEgABLgAECgYJCAABAAAAAA==.Aela:BAAALgADCgEJAQABLgAECgkJLQACAG8gAA==.Aesalon:BAABLgAECn80AAQDAAkJ1COqAgDXAgADAAkJ1COqAgDXAgAEAAIJrRTjeQA+AAAFAAIJGBNPUgA0AAAAAA==.',
Ah='Ahsokatano:BAABLgAECn8tAAMCAAkJbyCDBwARAwACAAkJbyCDBwARAwAGAAEJ8gyDkQAoAAAAAA==.',
Ai='Aimspet:BAAALgAECgYJEAAAAA==.Aircanada:BAAALgAECgIJAgAAAA==.',
Ak='Akela:BAABLgAECn8eAAIHAAgJjw3+TgCHAQAHAAgJjw3+TgCHAQAAAA==.',
Al='Algorithm:BAAALgAECgMJAwAAAA==.Alissu:BAAALgADCgIJAgAAAA==.Alvonaar:BAAALgADCgUJBwAAAA==.',
Am='Ames:BAAALgADCgYJCgAAAA==.Amonet:BAAALgAECgQJBAAAAA==.',
An='Anaelcheese:BAABLgAECn8aAAQIAAcJ2BRcGwBoAQAIAAcJ2BRcGwBoAQAJAAEJkg0sLgAnAAAKAAEJywAN9wATAAAAAA==.Anamis:BAABLgAECn8jAAILAAcJxxTSLwCDAQALAAcJxxTSLwCDAQAAAA==.Andrina:BAAALgADCgYJAgAAAA==.Angeldemon:BAAALgADCgYJCAAAAA==.Angras:BAABLgAECn8gAAIMAAgJPxAQVgCfAQAMAAgJPxAQVgCfAQAAAA==.Angryorc:BAAALgAECgQJBQAAAA==.Anja:BAAALgADCgkJFwAAAA==.Anolana:BAABLgAECn8zAAMNAAgJjCIYCACDAgANAAgJjCIYCACDAgAOAAEJixHIIAA6AAAAAA==.Anyday:BAAALgADCgcJBwAAAA==.',
Ap='Aphalock:BAABLgAECn8fAAIPAAgJqRBMCgBxAQAPAAgJqRBMCgBxAQAAAA==.',
Ar='Aragoth:BAAALgAECgEJAQAAAA==.Ariûs:BAAALgAECgYJDgAAAA==.Arlin:BAAALgAECgQJCQAAAA==.Arlorian:BAABLgAECn8rAAIOAAkJrQ/IBwCwAQAOAAkJrQ/IBwCwAQAAAA==.Arorra:BAAALgADCgkJEQAAAA==.Arrex:BAAALgAECgYJCwAAAA==.Arrowsmites:BAABLgAECn8qAAIHAAkJCBuKGgBeAgAHAAkJCBuKGgBeAgAAAA==.',
Au='Aubani:BAABLgAECn8sAAMQAAkJFCCVBgACAwAQAAkJFCCVBgACAwARAAUJIxIbuADxAAAAAA==.',
Ay='Ayperos:BAABLgAECn80AAMSAAgJ5ht/CQAtAgASAAgJ5ht/CQAtAgATAAYJPxAVUgBhAQAAAA==.Ayvaria:BAAALgAECgYJEwABLgAECgkJKwAUACQXAA==.',
Ba='Baboyago:BAAALgAECgUJBgAAAA==.Badgerbrew:BAAALgADCgkJCQAAAA==.Baked:BAAALgAECgQJBAABLgAECgcJGAARAD4GAA==.Bakedpally:BAABLgAECn8YAAIRAAcJPgbcswD3AAARAAcJPgbcswD3AAAAAA==.Bandomar:BAABLgAECn8gAAIEAAgJgArnLwAvAQAEAAgJgArnLwAvAQAAAA==.Baniemo:BAAALgAECgIJAwAAAA==.Banigor:BAAALgAECgYJEAAAAA==.Basak:BAAALgAECgYJCwABLgAFFAQJDQABAAAAAQ==.',
Be='Beammescotty:BAAALgADCgQJBAAAAA==.Bearnuts:BAAALgADCgEJAQAAAA==.Beck:BAABLgAECn8uAAIRAAkJKyDjEQC+AgARAAkJKyDjEQC+AgAAAA==.Beefflaps:BAAALgADCgEJAQAAAA==.Beggars:BAAALgAECgYJCQAAAA==.Belithsong:BAAALgAECgkJBQAAAA==.Bereth:BAAALgAECgQJCQAAAA==.Berreydingle:BAAALgAECgQJCQAAAA==.',
Bi='Bigkitty:BAABLgAECn8qAAITAAkJnhmrEwAwAgATAAkJnhmrEwAwAgABLgAECgYJGwAHAHIgAA==.Biz:BAAALgADCgYJBwABLgAECggJEwABAAAAAA==.',
Bl='Blackanvil:BAAALgAECgYJDQAAAA==.Blackautumn:BAAALgADCgcJDgABLgAECgcJHgATAKsdAA==.Blainn:BAAALgAECgcJBwAAAA==.Blindfred:BAAALgAECggJDQAAAA==.Blitzedbust:BAAALgADCggJDQAAAA==.Bloodredsky:BAABLgAECn8YAAMVAAkJuQ7xKQCPAQAVAAkJuQ7xKQCPAQAWAAEJmwiwfwAxAAAAAA==.Bloodymagi:BAABLgAECn8YAAIXAAgJhAUFlgAxAQAXAAgJhAUFlgAxAQAAAA==.Bluesummer:BAABLgAECn8eAAQTAAcJqx3/JwCWAQATAAYJQiH/JwCWAQAYAAYJxBrAGQCCAQASAAEJCAzpQQA1AAAAAA==.',
Bo='Bolts:BAAALgAECgEJAwAAAA==.Boomin:BAABLgAECn8wAAMFAAkJuhomBwBPAgAFAAkJuhomBwBPAgAEAAQJdQa7XABtAAAAAA==.',
Br='Brendameeks:BAAALgAECgcJEAAAAA==.Brewnashot:BAAALgADCggJCgAAAA==.Brewrain:BAAALgADCgEJAQAAAA==.Broadzinatl:BAAALgAECggJEwAAAA==.Brom:BAAALgAECgYJBwAAAA==.Brïn:BAAALgAECgEJAQAAAA==.',
Bu='Bulwark:BAAALgADCgYJBgAAAA==.Bushwookië:BAAALgAECgIJAgAAAA==.',
['Bã']='Bãthory:BAABLgAECn8XAAIZAAkJIxQmCgCYAQAZAAkJIxQmCgCYAQAAAA==.',
['Bø']='Bøss:BAAALgADCgkJEQAAAA==.',
Ca='Calvert:BAAALgAECgUJBgAAAA==.Captnhammer:BAAALgADCgUJBQAAAA==.Carebearr:BAAALgADCgcJBwAAAA==.Carnelian:BAAALgAECgMJBQAAAA==.Castration:BAABLgAECn8YAAIaAAYJ3AnUPwDmAAAaAAYJ3AnUPwDmAAAAAA==.',
Ce='Ceylan:BAABLgAECn8sAAMXAAkJqxbSLwA7AgAXAAkJqxbSLwA7AgAbAAEJVQMVIQAqAAAAAA==.',
Ch='Chadillac:BAAALgAECgMJAwAAAA==.Chaleb:BAAALgAECgMJBAAAAA==.Charavane:BAAALgAECgEJAQAAAA==.Charlz:BAABLgAECn8jAAMaAAkJhBaAFQD7AQAaAAkJhBaAFQD7AQALAAQJChHLVQDfAAAAAA==.Charsifood:BAAALgAECgcJDwAAAA==.Chass:BAAALgADCgQJBAAAAA==.Cheatdr:BAABLgAECn8dAAIcAAYJbBERTgAzAQAcAAYJbBERTgAzAQAAAA==.Cheatpriest:BAABLgAECn83AAILAAkJ7RbhGwDCAQALAAkJ7RbhGwDCAQAAAA==.Chesthyr:BAAALgADCgcJBwAAAA==.Chesto:BAABLgAECn8uAAQdAAgJPx1JBQAEAgAdAAgJ9xlJBQAEAgAPAAcJ4xqvBwCqAQAeAAcJwRT2awCKAQAAAA==.Chimerax:BAAALgADCggJCAAAAA==.Chimken:BAAALgAECgEJAQABLgAECgkJKQASADUeAA==.Chokea:BAAALgAECgkJDgAAAA==.Chrome:BAAALgAECgEJAQAAAA==.Chuwhee:BAAALgADCgYJBgAAAA==.',
Co='Cognition:BAABLgAECn8+AAIHAAkJryUJCAD6AgAHAAkJryUJCAD6AgAAAA==.Coldvengance:BAABLgAECn8yAAITAAgJSAorNwBEAQATAAgJSAorNwBEAQAAAA==.Corpser:BAAALgADCgUJBQAAAA==.',
Cr='Cranki:BAAALgAECgUJBgABLgAECgIJBAABAAAAAA==.Cranknstein:BAAALgADCgQJBAABLgAECgIJBAABAAAAAA==.Crazycalla:BAAALgAECgEJAQAAAA==.',
Cy='Cymindel:BAABLgAECn84AAIfAAkJCxpOCQBVAgAfAAkJCxpOCQBVAgAAAA==.',
Da='Dad:BAAALgADCgQJBAAAAA==.Daelein:BAAALgADCgEJAQABLgADCgEJAQABAAAAAA==.Daithi:BAAALgAECgcJEQAAAA==.Dakotà:BAABLgAECn8dAAIHAAYJAxbtZABMAQAHAAYJAxbtZABMAQAAAA==.Darc:BAAALgAECgMJBQAAAA==.Darklite:BAAALgADCgUJDAAAAA==.Darkmonk:BAAALgADCgUJBQAAAA==.Dassadin:BAAALgAECgQJBQAAAA==.Day:BAABLgAECn8fAAIHAAgJFBhCOgDLAQAHAAgJFBhCOgDLAQAAAA==.',
De='Decaydence:BAAALgAECggJEAAAAA==.Dejno:BAABLgAECn8YAAITAAcJMiCpJACrAQATAAcJMiCpJACrAQAAAA==.Deleted:BAAALgADCgEJAQABLgAECgkJHQAMAPEiAA==.Demonicly:BAAALgAECgcJEgAAAA==.Demönslayer:BAAALgAECgcJAwAAAA==.Derowski:BAAALgAECgQJBQAAAA==.Deroz:BAAALgADCgUJBQAAAA==.Dethra:BAAALgADCgQJBAAAAA==.Dezign:BAACLgAFFH8TAAIXAAYJ5Rd8JgCJAQAXAAYJ5Rd8JgCJAQAuAAQKfygAAhcACQl2IJkgAIECABcACQl2IJkgAIECAAAA.Dezígn:BAAALgAFFAMJAwABLgAFFAYJEwAXAOUXAA==.',
Di='Diabolical:BAAALgAECgEJAQAAAA==.Discordegirl:BAABLgAECn8WAAMgAAYJQQwtSADAAAAgAAUJvA4tSADAAAAWAAEJVQJcmgAbAAAAAA==.Divinitÿ:BAAALgADCgIJAgABLgAECgkJLAAeAL8jAA==.',
Do='Dolgorukov:BAABLgAECn8oAAIHAAkJTA+hRQCkAQAHAAkJTA+hRQCkAQAAAA==.Dologony:BAABLgAECn8eAAIcAAgJlg+cQQBnAQAcAAgJlg+cQQBnAQAAAA==.',
Dr='Dracigor:BAAALgAECgIJAwAAAA==.Draconair:BAAALgADCgYJCAAAAA==.Dragonsbaine:BAAALgADCgMJAwAAAA==.Dragonz:BAAALgAECgQJCQAAAA==.Dre:BAAALgAECgMJCAAAAA==.Drikken:BAABLgAECn8+AAQKAAkJwxnwJwANAgAKAAkJOhfwJwANAgAIAAUJgBYTJgANAQAJAAUJ2xtZEQAKAQAAAA==.Drmaker:BAAALgAECgMJAwAAAA==.Drougs:BAABLgAECn8uAAIIAAkJVxhHEgDQAQAIAAkJVxhHEgDQAQAAAA==.Druiddeleted:BAAALgAECgEJAQABLgAECgkJHQAMAPEiAA==.',
Du='Dubbshot:BAAALgAECgEJAQAAAA==.Dumara:BAAALgADCgIJAgAAAA==.Durasan:BAABLgAECn8cAAIMAAYJjgiPsgDmAAAMAAYJjgiPsgDmAAAAAA==.Duressa:BAAALgAECgcJBwAAAA==.',
Dy='Dymund:BAAALgAECgIJBAAAAA==.',
['Dà']='Dàrkside:BAAALgAECgYJBgAAAA==.',
['Dö']='Dötdötdead:BAABLgAECn8pAAMPAAgJIhVOBwCyAQAPAAgJIhVOBwCyAQAeAAIJZwu26QBiAAAAAA==.',
Ea='Earthie:BAAALgADCgEJAQAAAA==.Earthstorm:BAAALgADCgIJAgAAAA==.Eastwubz:BAAALgADCgIJAgAAAA==.',
Ed='Edge:BAAALgAECgMJBQAAAA==.',
Ef='Effin:BAAALgADCgUJBQAAAA==.Effindin:BAAALgAECgUJBgAAAA==.Effinfu:BAABLgAECn8fAAIgAAgJrxGYIgB2AQAgAAgJrxGYIgB2AQAAAA==.',
Ei='Eitent:BAABLgAECn8wAAMQAAkJux3ICgC8AgAQAAkJux3ICgC8AgARAAcJuhIRdgCOAQAAAA==.',
El='Ele:BAAALgADCgcJCAABLgAECgYJEQABAAAAAA==.Ellesthara:BAAALgAECgYJDwAAAA==.Ellysiaa:BAABLgAECn8WAAIDAAYJJgXYJgCbAAADAAYJJgXYJgCbAAAAAA==.Elrïc:BAAALgADCgMJAwAAAA==.Elwynlana:BAAALgADCgYJBwAAAA==.Elysa:BAAALgADCgEJAQAAAA==.',
Em='Emberstorm:BAAALgAECgQJBQAAAA==.Emmakyn:BAABLgAECn8pAAMEAAgJMRR9HwCeAQAEAAgJMRR9HwCeAQAcAAcJMA0VTgAzAQAAAA==.',
En='Enezath:BAAALgADCgIJAgAAAA==.Entrerie:BAAALgADCgYJCwAAAA==.Enyxea:BAAALgAECggJEwAAAA==.',
Ep='Ephemera:BAAALgAECgQJCQAAAA==.Epsolon:BAAALgAECgIJAgAAAA==.',
Er='Erikuh:BAAALgADCgEJAQAAAA==.Erodin:BAAALgADCgYJBgAAAA==.',
Es='Esmeray:BAAALgAECgcJCAABLgAECgkJKwAUACQXAA==.Estala:BAAALgADCgUJBQAAAA==.',
Ey='Eyedontknow:BAAALgAECgYJEQAAAA==.Eyewana:BAABLgAECn8kAAIIAAkJchJXFgCfAQAIAAkJchJXFgCfAQAAAA==.',
Ez='Ezzka:BAABLgAECn8aAAIMAAgJnxIvTgC1AQAMAAgJnxIvTgC1AQAAAA==.',
Fa='Faelan:BAAALgADCgIJAQAAAA==.Fakesaint:BAAALgAECgYJCgAAAA==.Fangalor:BAAALgAECgEJAgAAAA==.Farnsworth:BAAALgAECgYJEwABLgAECgkJNAADANQjAA==.Farzix:BAABLgAECn8jAAIGAAgJzAfYPwAEAQAGAAgJzAfYPwAEAQAAAA==.Façade:BAABLgAECn8mAAIMAAkJDxMATgC2AQAMAAkJDxMATgC2AQAAAA==.',
Fe='Feelgood:BAAALgADCggJCwAAAA==.Fefifiona:BAABLgAECn8ZAAIhAAkJKheNDAB5AgAhAAkJKheNDAB5AgAAAA==.Fefifredrich:BAAALgAECgMJAwABLgAECgkJGQAhACoXAA==.Fefifuredric:BAAALgAECgEJAQABLgAECgkJGQAhACoXAA==.Felvira:BAABLgAECn8dAAMKAAgJPgQntgCLAAAKAAYJbQMntgCLAAAIAAUJWwT+RQBfAAAAAA==.',
Fi='Finnw:BAAALgAECgYJEQAAAA==.Firelite:BAABLgAECn8bAAIGAAYJEhCYQgD5AAAGAAYJEhCYQgD5AAAAAA==.',
Fl='Flairlock:BAABLgAECn80AAMdAAgJtSDAAwA7AgAdAAgJtSDAAwA7AgAPAAIJBhXRMgA6AAAAAA==.Flee:BAABLgAECn8iAAINAAkJqRr3CgBSAgANAAkJqRr3CgBSAgAAAA==.',
Fo='Fookster:BAABLgAECn8YAAIXAAgJrhQfSwDeAQAXAAgJrhQfSwDeAQAAAA==.Forsetee:BAABLgAFFH8GAAIgAAIJTRcuOACaAAAgAAIJTRcuOACaAAAAAA==.',
Fr='Frowdawn:BAABLgAECn81AAIOAAgJqhBcCAChAQAOAAgJqhBcCAChAQAAAA==.',
Fy='Fyf:BAAALgAECgYJBgABLgAECgIJBAABAAAAAA==.',
['Fí']='Físter:BAAALgAECgYJDwABLgAECgcJGgAMACoaAA==.',
Ga='Galadris:BAAALgADCgkJDwAAAA==.Garythenpc:BAAALgAECgQJCQAAAA==.Gaztoria:BAAALgADCggJCAABLgAECgkJLgAMALAiAA==.',
Ge='Genavieve:BAAALgADCgQJBAAAAA==.Gendra:BAAALgAECgEJAQAAAA==.',
Gh='Ghøst:BAAALgADCgYJCQAAAA==.Ghøstlord:BAAALgADCgEJAQAAAA==.Ghøstslayer:BAAALgADCgEJAQAAAA==.',
Gi='Gilas:BAAALgADCgQJBAAAAA==.',
Gl='Glacialkitty:BAABLgAECn8lAAIcAAgJngtgSgBCAQAcAAgJngtgSgBCAQAAAA==.',
Go='Googoobler:BAABLgAECn8cAAIIAAgJoQbnJwAAAQAIAAgJoQbnJwAAAQAAAA==.Goudaluck:BAAALgADCgMJAwABLgAECgYJGwAHAHIgAA==.Goudanight:BAAALgAECgMJBAABLgAECgYJGwAHAHIgAA==.Goudavibes:BAAALgAECgEJAQABLgAECgYJGwAHAHIgAA==.',
Gr='Greenmagus:BAAALgADCgYJCAAAAA==.Grenadon:BAAALgAECgQJBgAAAA==.Grimlilith:BAABLgAECn8bAAQdAAgJ/wSbEQATAQAdAAgJ9gSbEQATAQAeAAMJBAOXBgE+AAAPAAEJAAAogQALAAAAAA==.Grundy:BAAALgAECgUJCAAAAA==.',
Gu='Gumbi:BAAALgADCgIJAgAAAA==.',
Ha='Hadorya:BAABLgAECn81AAIaAAgJtBsAEwAVAgAaAAgJtBsAEwAVAgAAAA==.Hakitua:BAABLgAECn8dAAIJAAgJAgtHEgD8AAAJAAgJAgtHEgD8AAAAAA==.Hangi:BAAALgADCgkJCQAAAA==.Happymeel:BAAALgAECgEJAQAAAA==.Harleyqûinn:BAAALgAECgcJDQAAAA==.Hazard:BAABLgAECn81AAITAAgJdg1pLwBqAQATAAgJdg1pLwBqAQAAAA==.',
He='Healonwheels:BAAALgADCgMJAwAAAA==.Heimdall:BAAALgAECgYJDAABLgAECgkJLAAeAL8jAA==.Heis:BAAALgAECgQJCQAAAA==.Hellboii:BAAALgAECggJEwAAAA==.Heyitsrat:BAABLgAECn8vAAIRAAgJ/BTxVwClAQARAAgJ/BTxVwClAQAAAA==.',
Hi='Hiko:BAAALgAECgkJCAAAAA==.',
Ho='Holo:BAACLgAFFH8SAAMCAAYJJgqFAgC9AQACAAYJJgqFAgC9AQAGAAUJFB8JEQBVAQAuAAQKfyEAAwYACQlzIWYDAG0DAAYACQlzIWYDAG0DAAIABwnXDgJCAHkBAAAA.Holos:BAAALgAECgEJAQABLgAFFAYJEgACACYKAA==.Holyangus:BAAALgAECgUJBwAAAA==.Holyyknight:BAAALgAECgcJEwAAAA==.',
Hu='Hugecrit:BAAALgADCgkJDwAAAA==.',
Ib='Ibbert:BAAALgADCggJEwAAAA==.',
Ic='Icculus:BAABLgAECn8fAAIHAAgJBxXJOQDMAQAHAAgJBxXJOQDMAQAAAA==.',
Il='Illuyanka:BAAALgAECgEJAQAAAA==.',
Im='Impasse:BAAALgAECgkJBwAAAA==.',
In='Indaskyz:BAAALgADCgEJAQAAAA==.',
Io='Iolz:BAAALgAECgYJCgAAAA==.',
Ir='Ironfist:BAABLgAECn8zAAIgAAkJViPRAQA4AwAgAAkJViPRAQA4AwAAAA==.',
It='Itankworlds:BAAALgAECgUJBQABLgAECgcJDgABAAAAAA==.',
Iw='Iwanaplay:BAAALgAECgMJAwAAAA==.',
Ja='Jacolynn:BAABLgAECn8YAAIVAAcJ7BHsKwBXAQAVAAcJ7BHsKwBXAQAAAA==.Jaenei:BAAALgAECgcJCwAAAA==.',
Je='Jelly:BAAALgADCgIJAgAAAA==.',
Jo='Joatmoa:BAAALgAFFAIJAwAAAA==.Joeexotics:BAAALgADCgkJDAAAAA==.Jordanleah:BAAALgAECgQJBAAAAA==.',
Ju='July:BAAALgAECgcJDAAAAA==.Julytonidas:BAAALgAECgcJBwAAAA==.Jurac:BAAALgADCgcJGQAAAA==.',
Ka='Kaelnis:BAAALgAECggJDgAAAA==.Kaimargonar:BAAALgAECgUJCQAAAA==.Kaitoi:BAABLgAECn8VAAMDAAYJZROKFgApAQADAAYJZROKFgApAQAFAAUJKwj1NwB8AAAAAA==.Kallah:BAACLgAFFH8WAAIQAAUJcx9fCwC5AQAQAAUJcx9fCwC5AQAuAAQKfzcAAhAACQnsI44BAGsDABAACQnsI44BAGsDAAAA.Kalthos:BAABLgAECn84AAMiAAkJGBmoBwBcAgAiAAgJihmoBwBcAgAUAAkJnBGaBQDiAQAAAA==.Kamakizeg:BAABLgAECn8rAAIRAAkJlBLjRADYAQARAAkJlBLjRADYAQAAAA==.Kamayla:BAAALgADCgYJBgAAAA==.Karnus:BAAALgADCgIJAgAAAA==.Kaspen:BAAALgADCgMJAwAAAA==.Kateria:BAABLgAECn8mAAIXAAkJ5BtbHwCHAgAXAAkJ5BtbHwCHAgAAAA==.',
Ke='Kestrelle:BAAALgAECgcJEwABLgAECggJOAAcAOoRAA==.Keyzeus:BAABLgAECn8fAAIUAAgJFRbjBQDVAQAUAAgJFRbjBQDVAQAAAA==.',
Kh='Khas:BAAALgADCgkJGgAAAA==.Khui:BAACLgAFFH8VAAIVAAUJUSX1CAABAgAVAAUJUSX1CAABAgAuAAQKfyUAAxUACAkWJcACAFcDABUACAkWJcACAFcDABYAAwkwGItEAMEAAAAA.',
Ki='Kiarorin:BAAALgAECgEJAQAAAA==.Killerdeath:BAAALgAECgQJBgAAAA==.Kittkat:BAAALgADCgkJEAAAAA==.',
Kn='Knìghtmàrè:BAACLgAFFH8RAAMMAAUJnh+OLgBoAQAMAAQJnh+OLgBoAQAfAAEJAAD2PQAAAAAuAAQKfygAAgwACQn9INMSAAsDAAwACQn9INMSAAsDAAAA.Kníghtfíst:BAABLgAECn8qAAIVAAkJyhdWGAAXAgAVAAkJyhdWGAAXAgABLgAFFAUJEQAMAJ4fAA==.',
Ko='Koltharaz:BAAALgAECgEJAQAAAA==.Korheo:BAAALgADCgUJBQAAAA==.Korloff:BAAALgAECgcJDQABLgAECgcJHAABAAAAAQ==.Kozan:BAAALgAECgcJHAAAAQ==.',
Kr='Krazysniper:BAABLgAECn8oAAMHAAgJCRw/IwAsAgAHAAcJEB8/IwAsAgAjAAEJ4wmeVAA5AAAAAA==.Krokk:BAABLgAECn8UAAIGAAcJ9QcfRQDvAAAGAAcJ9QcfRQDvAAAAAA==.',
Ku='Kungfister:BAAALgAECgEJAQAAAA==.Kur:BAAALgAECgEJAQABLgAFFAQJDQABAAAAAQ==.',
La='Laatt:BAABLgAECn8aAAMRAAgJFh66KgB5AgARAAgJFh66KgB5AgAQAAYJOBjfMgBgAQAAAA==.Lacosanostra:BAAALgAECgYJCgAAAA==.Laeiny:BAAALgADCgYJBgAAAA==.Lateralus:BAAALgAECgUJBgABLgAECggJGgARABYeAA==.Latharel:BAAALgAECgEJAQAAAA==.Lawluss:BAABLgAECn8fAAIHAAcJ1BgRQACvAQAHAAcJ1BgRQACvAQAAAA==.Layethelor:BAAALgAECgEJBAAAAA==.',
Le='Legacyshot:BAAALgAECggJIAAAAQ==.Leigola:BAAALgADCgUJCQAAAA==.Lela:BAAALgAECgYJBgAAAA==.Lezsul:BAAALgADCgEJAQAAAA==.',
Li='Lickthecrit:BAAALgAECggJEgAAAA==.Lidrelle:BAABLgAECn8XAAIRAAcJAhJNeABdAQARAAcJAhJNeABdAQAAAA==.Lightguard:BAAALgADCgkJCgAAAA==.Lighthouse:BAABLgAECn8uAAIRAAkJlxsuJwBFAgARAAkJlxsuJwBFAgAAAA==.Lileth:BAAALgADCggJBgAAAA==.Lilpaws:BAAALgAECgYJBgAAAA==.Lizy:BAAALgADCgUJBQAAAA==.',
Lo='Locust:BAAALgAECgMJAwAAAA==.Lokkar:BAAALgADCgQJBAAAAA==.Lolalazer:BAABLgAECn8WAAIKAAgJ9RWDTAB+AQAKAAgJ9RWDTAB+AQAAAA==.Lolhahabaha:BAAALgAECggJDAAAAA==.Loopie:BAAALgADCgUJBQAAAA==.Lovesomev:BAAALgADCgMJAwAAAA==.',
Lu='Luckÿ:BAABLgAECn8XAAIfAAcJlxViHABFAQAfAAcJlxViHABFAQAAAA==.Lunabelle:BAAALgADCgEJAQAAAA==.Lunchbox:BAAALgAECgkJAQAAAA==.Lustfull:BAAALgAECgEJAgABLgAECggJHAAHANIhAA==.',
Ly='Lypally:BAABLgAECn8lAAIRAAgJcw1HbAB2AQARAAgJcw1HbAB2AQAAAA==.',
['Ló']='Lóla:BAABLgAECn8sAAIKAAgJTiTkDQC6AgAKAAgJTiTkDQC6AgAAAA==.',
['Lô']='Lônè:BAAALgAECgUJBwAAAA==.',
Ma='Maani:BAAALgAECgEJAQAAAA==.Madeah:BAACLgAFFH8eAAMOAAcJRBWzAQCZAQANAAYJEheWCACiAQAOAAYJOw+zAQCZAQAuAAQKfyEAAw0ACAlGHtkMAMsCAA0ACAlGHtkMAMsCAA4AAQnoGt8aAFEAAAAA.Mahimahi:BAAALgAECggJCAAAAA==.Malýs:BAAALgAECgEJAQAAAA==.Mardain:BAABLgAECn8aAAIkAAkJ3xFECgDfAQAkAAkJ3xFECgDfAQAAAA==.Mariacuras:BAABLgAECn8UAAIQAAcJRQ2fMwBbAQAQAAcJRQ2fMwBbAQAAAA==.Marle:BAABLgAECn8xAAIKAAgJLhlgLgDuAQAKAAgJLhlgLgDuAQAAAA==.Marlete:BAAALgADCgYJBQAAAA==.Marshoon:BAAALgADCgkJKgAAAA==.Martis:BAAALgAECgYJBwAAAA==.Marynne:BAABLgAECn84AAMcAAgJ6hE+NgCdAQAcAAgJ6hE+NgCdAQAEAAEJSwKmjgANAAAAAA==.Matthis:BAAALgAECgUJBwAAAA==.Mazuko:BAABLgAECn8pAAIJAAgJ6RY5CADJAQAJAAgJ6RY5CADJAQAAAA==.',
Me='Medadh:BAAALgADCgUJBQAAAA==.Meepe:BAAALgADCgcJDAAAAA==.Meilnesar:BAAALgAECgIJAgAAAA==.Melaerissa:BAABLgAECn8uAAMaAAgJBA+dIQCSAQAaAAgJBA+dIQCSAQALAAUJxQx3QwC1AAAAAA==.Melbrooks:BAAALgADCgcJDQAAAA==.Melivant:BAAALgAECgQJCgABLgAECgUJCwABAAAAAA==.Merrikeath:BAAALgAECgcJDQAAAA==.Merriklade:BAABLgAECn8jAAITAAYJMwqyTgDjAAATAAYJMwqyTgDjAAAAAA==.',
Mi='Missyjelliot:BAAALgAECgQJBwAAAA==.',
Mo='Moof:BAAALgADCgEJAQAAAA==.Morthos:BAAALgAECgMJAwAAAA==.',
Mw='Mw:BAAALgADCgIJAgABLgAECgYJEQABAAAAAA==.',
['Mà']='Màrli:BAAALgAECgEJAgAAAA==.',
['Mâ']='Mâgs:BAABLgAECn8gAAIlAAkJWhIgDgCzAQAlAAkJWhIgDgCzAQAAAA==.',
Na='Nabbed:BAAALgAECgcJCAABLgAECgkJKQASADUeAA==.Nakasid:BAABLgAECn80AAQLAAkJ7RbFDgBUAgALAAkJ7RbFDgBUAgAaAAcJFQjUOQAiAQAhAAQJWwoWSgCZAAAAAA==.Nalaya:BAAALgAECgEJAQAAAA==.Nashoba:BAAALgADCgQJBAAAAA==.Natooka:BAAALgAECggJDgAAAA==.Navane:BAAALgAECgEJAgAAAA==.',
Ne='Neenja:BAAALgADCgYJBgAAAA==.Nefurtatta:BAAALgADCgEJAQAAAA==.Nertlogi:BAAALgADCgIJAgAAAA==.Nesrÿn:BAAALgADCgIJAgAAAA==.Nestina:BAAALgADCgMJBAAAAA==.Netherkeeper:BAABLgAECn8mAAIKAAkJKQ8kPAC2AQAKAAkJKQ8kPAC2AQAAAA==.Nevaehstar:BAABLgAECn8xAAIbAAkJxBzoAACyAgAbAAkJxBzoAACyAgAAAA==.Neverëst:BAAALgAECgEJAQAAAA==.',
Ni='Nibuto:BAAALgAECgQJCQAAAA==.Nightvision:BAAALgADCgMJAgAAAA==.Nijun:BAEBLgAECn8oAAILAAkJOxTZGQDTAQALAAkJOxTZGQDTAQAAAA==.Nikolia:BAAALgADCgkJDgAAAA==.Nini:BAABLgAECn8hAAIEAAgJZwJRTwCfAAAEAAgJZwJRTwCfAAAAAA==.Ninx:BAAALgAECgQJBAAAAA==.Nirazal:BAAALgADCgQJBQAAAA==.',
No='Noivana:BAAALgAFFAMJAwABLgAFFAUJDwAIANcSAA==.Norgannia:BAAALgADCgkJDwAAAA==.Notprepared:BAAALgADCgEJAQAAAA==.Noys:BAAALgADCgcJDAAAAA==.',
Nz='Nzuul:BAAALgADCgYJBgAAAA==.',
Ol='Oldbenkenobi:BAAALgAECgQJCAAAAA==.Ollichi:BAAALgADCgQJBAAAAA==.Ollifuzzle:BAAALgAECgEJAgAAAA==.',
Op='Oppaissiah:BAABLgAECn86AAMTAAkJhSLzCgCUAgATAAgJGSLzCgCUAgAYAAgJJCFsCgAmAgAAAA==.',
Or='Oraclespyro:BAABLgAECn8XAAImAAYJawJPYgCCAAAmAAYJawJPYgCCAAAAAA==.Orlakx:BAAALgADCggJFAAAAA==.',
Os='Osoroshi:BAAALgAECgQJBAAAAA==.',
Ov='Ovrind:BAAALgADCgEJAQAAAA==.',
Oz='Ozài:BAAALgADCgcJCgAAAA==.',
Pa='Padmê:BAAALgAECgcJCQAAAA==.Papasbich:BAAALgAECgYJCQABLgAECgkJOwARAE8SAA==.Patronous:BAAALgADCgUJBgAAAA==.',
Pe='Percthirty:BAAALgAECgEJAgAAAA==.Permafrost:BAAALgADCggJCgAAAA==.Perscila:BAAALgADCgUJBQAAAA==.',
Pi='Piggy:BAAALgAECgQJBgAAAA==.',
Pl='Planet:BAAALgADCgEJAQAAAA==.',
Po='Porkchoplust:BAAALgADCgUJBQAAAA==.Porkchopw:BAAALgAECgcJAQAAAA==.Porkribs:BAAALgAECgcJAgAAAA==.',
Pr='Presap:BAABLgAECn8sAAMcAAgJxCFRCgD4AgAcAAgJxCFRCgD4AgAEAAEJAACrdgBJAAABLgAECgcJFAAiAEkdAA==.Promethius:BAAALgADCgQJBAAAAA==.Proscris:BAAALgADCgUJBQAAAA==.Prïsm:BAAALgADCgYJBgAAAA==.',
Pt='Ptmuchuk:BAAALgADCgYJBgAAAA==.',
Pu='Puca:BAAALgAECgQJCQAAAA==.Pumdmuc:BAABLgAECn9AAAMLAAkJmiHaBgDfAgALAAkJmiHaBgDfAgAaAAcJKgUnRADTAAAAAA==.Purrie:BAAALgADCgIJAgAAAA==.',
['Pâ']='Pâlly:BAAALgAECgcJCgAAAA==.',
Qu='Quikglaives:BAAALgAECgQJBwAAAA==.Quille:BAAALgAECgUJCQAAAA==.',
Ra='Rahhem:BAABLgAECn8eAAIlAAkJrRLlDQC3AQAlAAkJrRLlDQC3AQAAAA==.Rallo:BAAALgAECgEJAQAAAA==.Rayspaly:BAAALgAECgEJAQAAAA==.',
Re='Recbra:BAAALgAECgIJAgAAAA==.Reddelish:BAAALgADCgYJCQAAAA==.Redrek:BAAALgADCgcJEAAAAA==.Redshunter:BAAALgADCgIJAgAAAA==.Redsknight:BAAALgADCgkJCQAAAA==.Redsmonk:BAAALgADCgYJBwAAAA==.Redwinter:BAAALgAECgIJBAABLgAECgcJHgATAKsdAA==.Remmie:BAAALgAECgYJDAAAAA==.Retrolbution:BAAALgADCgkJEQAAAA==.Reznik:BAAALgAECgEJAQAAAA==.',
Rh='Rhaokir:BAAALgADCgIJAgAAAA==.',
Ri='Riqua:BAABLgAECn8eAAIcAAgJRRN8KwDaAQAcAAgJRRN8KwDaAQAAAA==.',
Ro='Rodeo:BAABLgAECn8rAAIEAAkJABAvHAC5AQAEAAkJABAvHAC5AQAAAA==.Rotgutwiskey:BAAALgADCgcJEwAAAA==.Roxies:BAAALgAFFAEJAQAAAA==.',
Rp='Rpg:BAAALgAECgcJDgAAAA==.',
Ru='Rumie:BAABLgAECn8bAAIKAAYJeQ6eegA4AQAKAAYJeQ6eegA4AQAAAA==.Runty:BAAALgADCgMJAwAAAA==.',
Sa='Sacket:BAAALgAECgQJBAAAAA==.Sadnhornless:BAAALgAECgEJAQAAAA==.Saeti:BAACLgAFFH8GAAIDAAMJTRNnCAD5AAADAAMJTRNnCAD5AAAuAAQKfzQABQMACQkaIZYHAG8CAAMACQkaIZYHAG8CAAQABgmdG7MjAH4BAAUABAm8FVQsALcAABwABAkUFlJ7AKYAAAAA.Sandril:BAAALgAECgcJDAAAAA==.Sapplesauce:BAAALgAECgcJEgAAAA==.',
Sc='Scryer:BAAALgAECgEJAQAAAA==.',
Se='Serenìty:BAAALgAECggJDQAAAA==.Seresin:BAABLgAECn81AAIcAAgJKRv2GABbAgAcAAgJKRv2GABbAgAAAA==.',
Sh='Shadý:BAABLgAECn8tAAIHAAgJtAtHUQCBAQAHAAgJtAtHUQCBAQAAAA==.Shamanoodles:BAAALgAECgEJAQABLgAECgkJHQAMAPEiAA==.Shinbin:BAAALgAECgEJAgAAAA==.Shonna:BAABLgAECn8oAAQPAAgJLBq1CACTAQAeAAgJ1heKOQDbAQAPAAcJeBi1CACTAQAdAAIJERlTLQBEAAAAAA==.Shortwarrior:BAABLgAECn8tAAITAAgJBxrVGQD7AQATAAgJBxrVGQD7AQAAAA==.Shrimpimp:BAAALgAECgQJBAAAAA==.',
Si='Sidarya:BAAALgAECggJEQAAAA==.Sidera:BAAALgAECgUJBQAAAA==.Siduna:BAAALgADCgEJAQAAAA==.Silent:BAACLgAFFH8IAAMTAAIJjBOiMQCYAAATAAIJjBOiMQCYAAASAAEJPAwlLQBEAAAuAAQKfxsAAxIACQkkFM4ZACUBABMABwkdEgZLAHkBABIABgkoEs4ZACUBAAAA.Silverserket:BAAALgAECgIJAgAAAA==.',
Sk='Skinnybutt:BAAALgADCgkJEQAAAA==.Skippinskipp:BAAALgAECgcJCwAAAA==.Skymaggedon:BAEBLgAECn8yAAMCAAkJzgxhUAA7AQACAAkJzgxhUAA7AQAGAAgJsAe2PQANAQAAAA==.',
Sl='Slappadrago:BAAALgAECgkJEwAAAA==.',
Sm='Smileyriley:BAABLgAECn8VAAIEAAYJ/gWVSgCwAAAEAAYJ/gWVSgCwAAAAAA==.',
Sn='Sneakylinks:BAAALgAECgMJBAABLgAECgcJDgABAAAAAA==.Snotlocker:BAAALgAECgEJAQAAAA==.',
So='Sodexorod:BAAALgADCgYJBwAAAA==.Sofiophya:BAAALgAECgQJCQAAAA==.Sooki:BAAALgAECgIJAgAAAA==.Sorlis:BAAALgADCggJDwAAAA==.Soulber:BAAALgAECggJEwAAAA==.Sourdew:BAABLgAECn8eAAIWAAcJtB7UFADrAQAWAAcJtB7UFADrAQAAAA==.',
Sp='Sparkey:BAAALgAECgIJAgAAAA==.Spiritair:BAABLgAECn8UAAMiAAcJSR0rCABMAgAiAAcJSR0rCABMAgAUAAEJAACMJwAAAAAAAA==.Spunklestain:BAAALgADCggJDQABLgAECgkJEwABAAAAAA==.Spyke:BAAALgADCgEJAQAAAA==.Spykids:BAAALgAECgQJBAAAAA==.',
Sr='Srix:BAAALgAECgEJAQAAAA==.',
St='Starrdust:BAEALgAECgQJBAAAAA==.Stelle:BAABLgAECn8XAAIhAAgJBBEYJABzAQAhAAgJBBEYJABzAQAAAA==.Sternhoof:BAAALgAECgEJAQAAAA==.Stylos:BAABLgAECn8rAAIkAAgJ4BDKDgCKAQAkAAgJ4BDKDgCKAQAAAA==.Stãrburst:BAAALgAECgcJDQAAAA==.',
Ta='Taissa:BAAALgADCggJCgAAAA==.Taopaípai:BAAALgADCgMJBgAAAA==.Tas:BAAALgAECgQJBAAAAA==.Tatertotz:BAAALgAECgUJEAAAAA==.',
Te='Technine:BAAALgADCgMJAwAAAA==.Techno:BAAALgAECgcJAQAAAA==.Tegbless:BAAALgAECgkJDgAAAA==.Tegchill:BAABLgAECn8dAAQfAAgJNBnnDgDrAQAfAAgJVBjnDgDrAQAMAAgJBQ8oZwDAAQAZAAEJAACfGgAeAAABLgAECgkJDgABAAAAAA==.Terentia:BAAALgAECgUJBQABLgAECgkJKwAUACQXAA==.',
Th='Thalodrim:BAAALgAECgEJAQABLgAECgkJNAADANQjAA==.Tharelly:BAABLgAECn8VAAIXAAgJ3hlmRQDwAQAXAAgJ3hlmRQDwAQAAAA==.Thasserian:BAAALgADCgIJAgABLgAECgkJLAAeAL8jAA==.Theholymatt:BAACLgAFFH8PAAMQAAUJcBmNFwA0AQAQAAQJABeNFwA0AQARAAQJmhNZUgDdAAAuAAQKfy4AAxEACQkpI70HABUDABEACQkpI70HABUDABAABwnTI0EPAJsCAAAA.Thendari:BAABLgAECn9cAAIPAAkJOxOHBQDmAQAPAAkJOxOHBQDmAQAAAA==.Theodus:BAABLgAECn8yAAIXAAkJhxmsLABJAgAXAAkJhxmsLABJAgAAAA==.Therayen:BAAALgADCgQJBAAAAA==.Theràpy:BAAALgAECgQJBQAAAA==.Thesmaugmatt:BAABLgAECn8UAAImAAgJfxpkFwD7AQAmAAgJfxpkFwD7AQABLgAFFAUJDwAQAHAZAA==.Thorrune:BAAALgAECgQJBAAAAA==.Threnor:BAABLgAECn8uAAMSAAgJyySiAwDKAgASAAgJECSiAwDKAgATAAcJZCP1IABLAgAAAA==.Thunderblade:BAAALgADCgIJAgAAAA==.',
Ti='Tialdari:BAAALgADCgYJBgAAAA==.Tiferis:BAACLgAFFH8KAAIQAAMJoCN9GAArAQAQAAMJoCN9GAArAQAuAAQKfzMAAhAACQl8GjkOAIsCABAACQl8GjkOAIsCAAAA.Tislam:BAAALgAECggJEwAAAA==.Tizzeia:BAAALgADCgMJBQAAAA==.',
To='Toaster:BAABLgAECn8pAAQSAAkJNR7NBACaAgASAAkJFhrNBACaAgAYAAcJpSAZDAADAgATAAYJtx9dMgDiAQAAAA==.Tobes:BAAALgADCgEJAQAAAA==.Tobiquer:BAABLgAECn87AAILAAkJbBt7DgBYAgALAAkJbBt7DgBYAgAAAA==.Toebackkey:BAAALgAECgEJAQAAAA==.Tojarmar:BAABLgAECn8XAAIYAAkJJBNZDwDKAQAYAAkJJBNZDwDKAQABLgAECgQJBAABAAAAAA==.',
Tr='Trauglodyte:BAAALgAECgYJBgAAAA==.Traydra:BAAALgAECgMJAwAAAA==.Triven:BAAALgAECgIJAgAAAA==.Troglodyte:BAACLgAFFH8aAAMGAAYJORmsCAC4AQAGAAYJORmsCAC4AQACAAEJYAznWQBQAAAuAAQKf0IAAgYACQnMIj4DAB0DAAYACQnMIj4DAB0DAAAA.',
Ts='Tsonokwabain:BAABLgAECn8dAAQZAAgJeyDFBAA4AgAZAAgJeyDFBAA4AgAfAAEJah1+RQBLAAAMAAEJmAL7XAEYAAAAAA==.Tsunami:BAAALgADCgEJAQAAAA==.',
Tw='Twistdog:BAAALgAECgEJAwAAAA==.',
Ty='Tyranastrasz:BAABLgAECn8vAAIiAAkJ4hAyDgDHAQAiAAkJ4hAyDgDHAQAAAA==.Tyye:BAAALgAECgEJAQAAAA==.',
['Tâ']='Tâjik:BAABLgAECn8kAAINAAkJ4QVRIQBdAQANAAkJ4QVRIQBdAQAAAA==.',
Ud='Udderlytasty:BAAALgAECgEJAQAAAA==.',
Un='Unc:BAAALgAECgcJCAAAAA==.',
Va='Vade:BAAALgAFFAEJAwAAAA==.Vaelith:BAAALgAECggJDAAAAA==.Vaelyra:BAABLgAECn8uAAIKAAgJOxgKQgCgAQAKAAgJOxgKQgCgAQAAAA==.Vaerryn:BAABLgAECn8eAAQZAAgJXSDaBgDwAQAZAAcJxx/aBgDwAQAMAAIJFxyM5QCZAAAfAAIJQyBDQwBSAAAAAA==.Vaethund:BAAALgAECggJDQAAAA==.Vailenya:BAAALgADCgEJAQABLgAECggJHAAJAFMfAA==.Valgavoth:BAAALgAECggJEwAAAA==.Vandrin:BAAALgADCgQJBgAAAA==.Vapir:BAAALgAECgMJAwAAAA==.Variala:BAAALgAECggJEwAAAA==.Vassyra:BAABLgAECn8rAAIUAAkJJBf6AwAjAgAUAAkJJBf6AwAjAgAAAA==.',
Ve='Velara:BAAALgAECgEJAQAAAA==.Velesyn:BAABLgAECn8cAAMJAAgJUx/aBQAXAgAJAAcJKCDaBQAXAgAKAAIJtxHU1wBPAAAAAA==.Vellayna:BAAALgADCgYJBgAAAA==.',
Vi='Vilga:BAAALgADCgkJCQAAAA==.Viral:BAAALgAECgYJDwAAAA==.Viriex:BAAALgADCgEJAQAAAA==.Visone:BAAALgADCgEJAQAAAA==.',
Vo='Vocivus:BAAALgAECggJEwAAAA==.Voidlighter:BAAALgAECgkJEAABLgAECgkJMAAQALsdAA==.Volundr:BAABLgAECn81AAIYAAgJvhjtDwDBAQAYAAgJvhjtDwDBAQAAAA==.Vonvaughan:BAAALgADCgcJCwABLgAECggJEwABAAAAAA==.',
Vy='Vynirion:BAABLgAECn8UAAIXAAcJqxJUpACPAQAXAAcJqxJUpACPAQAAAA==.Vynisa:BAAALgAECgMJAwAAAA==.',
Wa='Waiseheil:BAAALgADCggJCQAAAA==.Warcreaper:BAAALgAECggJEQAAAA==.Wargtar:BAABLgAECn8hAAINAAYJVCJhEgDvAQANAAYJVCJhEgDvAQAAAA==.Warlockbob:BAAALgAECgYJCwAAAA==.',
We='Weabe:BAABLgAECn8YAAMLAAcJFhE0LQA+AQALAAcJ9w80LQA+AQAhAAIJpRHjSgBqAAAAAA==.Weebes:BAAALgAECggJCQAAAA==.',
Wh='Whiterrina:BAAALgADCgkJCgAAAA==.',
Wo='Woobee:BAAALgADCgEJAQAAAA==.',
Wy='Wyrdhoof:BAABLgAECn8eAAMEAAcJlAiIPgDjAAAEAAcJlAiIPgDjAAAcAAUJEgfdfACiAAAAAA==.',
['Wù']='Wùsthof:BAABLgAECn8eAAIHAAkJywobVgBmAQAHAAkJywobVgBmAQAAAA==.',
Xa='Xandrios:BAAALgADCgMJAwAAAA==.Xaron:BAAALgADCgMJAwAAAA==.',
Xi='Xiae:BAABLgAECn8sAAMCAAgJsSMcCQD5AgACAAgJsSMcCQD5AgAGAAUJDREFTQDRAAAAAA==.',
Xk='Xkwizet:BAABLgAECn8WAAIXAAgJcgYVlgAxAQAXAAgJcgYVlgAxAQAAAA==.',
Xo='Xorrin:BAAALgAECgYJDgAAAA==.',
Xy='Xylpho:BAAALgADCgEJAQAAAA==.',
Ye='Yet:BAABLgAECn8mAAIRAAkJiCQTBgArAwARAAkJiCQTBgArAwAAAA==.',
Yi='Yiffweaver:BAABLgAECn8pAAIgAAgJ3wpLLgAuAQAgAAgJ3wpLLgAuAQAAAA==.',
Yo='Yokoriazen:BAABLgAECn8zAAIlAAkJRxMGDQDHAQAlAAkJRxMGDQDHAQAAAA==.',
Yu='Yurtnaut:BAAALgAECgYJDgAAAA==.',
Yv='Yvesass:BAAALgAECgYJCgAAAA==.',
Za='Zarhianna:BAABLgAECn8jAAIEAAkJgBAtGwDCAQAEAAkJgBAtGwDCAQAAAA==.',
Ze='Zeo:BAAALgAECgEJAQAAAA==.',
Zm='Zmona:BAABLgAECn8tAAIRAAgJhA9tbwBvAQARAAgJhA9tbwBvAQAAAA==.',
Zo='Zorsche:BAAALgADCgUJBwAAAA==.',
Zu='Zulrok:BAABLgAECn8sAAITAAkJbB1kDQB0AgATAAkJbB1kDQB0AgAAAA==.',
['Ðr']='Ðre:BAABLgAECn8VAAIXAAcJ0hZswwBfAQAXAAcJ0hZswwBfAQAAAA==.',
['Ût']='Ûther:BAAALgAECgQJBwAAAA==.',
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
