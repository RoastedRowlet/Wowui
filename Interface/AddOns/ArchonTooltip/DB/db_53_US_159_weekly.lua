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

local lookup = {'Unknown-Unknown','Druid-Guardian','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Holy','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','Priest-Holy','Priest-Discipline','Priest-Shadow','Paladin-Retribution','Warrior-Arms','Paladin-Protection','Shaman-Restoration','Warrior-Protection','Mage-Fire','DeathKnight-Blood','DeathKnight-Unholy','Evoker-Devastation','Hunter-Survival','Druid-Feral','Warlock-Demonology','Warlock-Destruction','Druid-Balance','DemonHunter-Devourer','Monk-Windwalker','Monk-Mistweaver','Mage-Arcane','Mage-Frost','Shaman-Enhancement','Monk-Brewmaster','Rogue-Outlaw','DeathKnight-Frost','Evoker-Preservation','Warlock-Affliction','Warrior-Fury','Evoker-Augmentation',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abris:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.',
Ac='Acekith:BAAANQABCgMIAwABNQAECgQJBgABAAAAAA==.Acense:BAAANQAECgQJBgAAAA==.Acidhunter:BAAANQADCgcIBwAAAA==.Acidlock:BAAANQAECggIDgAAAA==.Acidpriest:BAAANQAECgYICgAAAA==.',
Ad='Adacey:BAAANQAECgcIDwAAAA==.Adragon:BAAANQADCgQIBAABNQAECgUICgABAAAAAA==.Adrenalized:BAAANQADCgMIBAAAAA==.',
Ae='Aesuga:BAAANQADCgYIBgAAAA==.',
Ak='Aktras:BAAANQAECgQIEQAAAA==.',
Al='Alaunu:BAABNQAECn8oAAICAAkKxRKlFwDuAQACAAkKxRKlFwDuAQAAAA==.Aleas:BAAANQADCgQIBAAAAA==.Alexx:BAAANQAECgQICAAAAA==.Alkaid:BAAANQAECgYIDgAAAA==.Alunariel:BAAANQADCgUICgAAAA==.',
An='Anari:BAAANQAECgQJBwABNQAECggIDQABAAAAAA==.Anarky:BAAANQAECggIEAAAAA==.Angelcorp:BAAANQADCgIIAgAAAA==.Annebonny:BAAANQAECgUIDAAAAA==.',
Ap='Apsalar:BAAANQADCgcJBwAAAA==.',
Ar='Archdemon:BAABNQAECn9IAAMDAAkKISVlAwC6AwADAAkKxSRlAwC6AwAEAAgK3B4xBQDeAgAAAA==.Arienys:BAAANQADCgYICwAAAA==.Arigosa:BAAANQADCgYIBwAAAA==.Ariis:BAAANQADCgUICQAAAA==.Arkh:BAAANQADCgMIAwAAAA==.Arkhanx:BAAANQADCgUJBQAAAA==.Arkhfu:BAAANQAECgIIAgAAAA==.Arleen:BAAANQADCgEIAQAAAA==.Arquen:BAABNQAECn8eAAIFAAcKOyEbMgCbAgAFAAcKOyEbMgCbAgAAAA==.Artemisia:BAAANQADCgYIFAAAAA==.',
As='Asevenx:BAAANQADCgUIBQAAAA==.Ashamane:BAAANQAECgEIAQAAAA==.Asheril:BAAANQADCgYICQAAAA==.Asian:BAAANQADCgIIAgAAAA==.Asra:BAAANQAECgYICgAAAA==.Astrov:BAABNQAECn8XAAIDAAgKyBH7NgDzAQADAAgKyBH7NgDzAQAAAA==.',
At='Atulmags:BAAANQAECgYICQAAAA==.',
Au='Auani:BAABNQAECn8yAAIGAAkK2CAhBwBOAwAGAAkK2CAhBwBOAwAAAA==.Aurelily:BAAANQADCgYJDAAAAA==.Ausia:BAAANQAECgQIBgAAAA==.',
Az='Azazyl:BAAANQADCgQIDAAAAA==.Azzeus:BAAANQAECgMIBgABNQAECgkJIQAHAIIUAA==.Azzfists:BAAANQADCgQIBAABNQAECgkJIQAHAIIUAA==.Azzshot:BAABNQAECn8hAAMHAAkKghRvfgANAgAHAAcKHhVvfgANAgAIAAkKDwbcOQB8AQAAAA==.',
Ba='Babyrinsjr:BAAANQAECgUICwAAAA==.Badista:BAAANQADCgIIAgAAAA==.Baile:BAAANQAECgIIAQABNQAECgMIBAABAAAAAA==.Balleont:BAABNQAECn8fAAIHAAkKCRQdVwBrAgAHAAkKCRQdVwBrAgAAAA==.Barrada:BAABNQAECn8aAAIHAAcKswUcxQBzAQAHAAcKswUcxQBzAQAAAA==.',
Be='Beefcakeßody:BAAANQADCgYIBgAAAA==.Berea:BAABNQAECn81AAMJAAYKZQzzVABhAQAJAAYKZQzzVABhAQAKAAUKsgNoOgDeAAAAAA==.',
Bl='Blankdemonic:BAAANQABCgYICAAAAA==.Blankwar:BAAANQADCgUIBQAAAA==.Bleedblue:BAABNQAECn8XAAIKAAcKcwyIJQCXAQAKAAcKcwyIJQCXAQAAAA==.Blitzed:BAAANQADCgIIAgAAAA==.Bloodhaven:BAAANQADCgEIAQAAAA==.',
Bo='Bo:BAABNQAECn8yAAIHAAkKrx1NJAAEAwAHAAkKrx1NJAAEAwAAAA==.Bobbinrobin:BAAANQAECgQIBQABNQAECgkJHgALAF8UAA==.Borahae:BAAANQAECgQICAABNQAECgkJKAAFAMIFAA==.Borden:BAAANQADCgQJBAAAAA==.',
Br='Bradent:BAAANQAECgcIBwAAAA==.Breach:BAAANQAECgIIAwABNQAECgMIBAABAAAAAA==.Brunnhild:BAAANQAECgIIAgAAAA==.Bryxi:BAAANQAECgEIAQAAAA==.Brünhilde:BAABNQAECn8jAAQMAAkKVRAcVwAZAgAMAAkKEg8cVwAZAgANAAQKAxBxFQDRAAAOAAEKAACDhQAiAAAAAA==.',
Bs='Bstbll:BAACNQAFFH8VAAIGAAYK1BmeAwABAgAGAAYK1BmeAwABAgA1AAQKfygAAgYACQpnHQ4SAL0CAAYACQpnHQ4SAL0CAAAA.',
Bu='Bubbleheals:BAABNQAECn8oAAMFAAgKzA4KcADFAQAFAAgKzA4KcADFAQAPAAEKAADwmAE4AAABNQAECgkJNgALAJcbAA==.Bundtcake:BAAANQAECggIBwAAAA==.Burningfist:BAAANQAECgMICQAAAA==.Buttsnacks:BAABNQAECn8jAAIQAAkKrxYaVwCDAgAQAAkKrxYaVwCDAgAAAA==.',
Ca='Caletha:BAAANQADCgYICwAAAA==.Callistrah:BAAANQAECgQIBgAAAA==.Caltaa:BAABNQAECn8yAAIRAAkKLSG4BQBRAwARAAkKLSG4BQBRAwAAAA==.Canarah:BAAANQADCgQIBAABNQAECgkJGgASAJIZAA==.Canverian:BAAANQAECgUICwAAAA==.Captsmash:BAABNQAECn8dAAITAAkKgxmaCgCTAgATAAkKgxmaCgCTAgAAAA==.Carmedic:BAAANQADCgIIAgAAAA==.Caudel:BAAANQABCgIIAgAAAA==.',
Cd='Cdub:BAAANQAECgYIDQAAAA==.',
Ch='Charcuterie:BAAANQAECgQIDQAAAA==.Chasseurfool:BAAANQAECgQICQAAAA==.Chat:BAACNQAFFH8HAAILAAMKmw0DGgDtAAALAAMKmw0DGgDtAAA1AAQKfywAAgsACQpMHIUuAL8CAAsACQpMHIUuAL8CAAAA.Chevre:BAABNQAECn8UAAIHAAQKxBME8AAcAQAHAAQKxBME8AAcAQAAAA==.Chezaro:BAABNQAECn8VAAIPAAYKAA5m6ABEAQAPAAYKAA5m6ABEAQAAAA==.Chickenwing:BAABNQAECn8eAAIUAAgKYCAkAQDcAgAUAAgKYCAkAQDcAgAAAA==.Christano:BAABNQAECn8YAAMPAAgK2hpBVgCQAgAPAAgKShpBVgCQAgARAAIK3SHCSQDBAAAAAA==.Christhecold:BAABNQAECn8gAAIQAAgKHxpBbQBHAgAQAAgKHxpBbQBHAgAAAA==.Chrollo:BAAANQAECgQIDwAAAA==.Chuchu:BAAANQADCgMIAwAAAA==.Chumba:BAAANQAECgYIDgAAAA==.',
Ci='Cinnamilk:BAAANQAECgMIAwABNQAECgkJMgAVAB8cAA==.',
Cl='Clamslamm:BAEANQADCgUIBQABNQAECgcIHwAWAJIhAA==.Cloudcrack:BAECNQAFFH8OAAMSAAQKAg+IEgAiAQASAAQKAg+IEgAiAQALAAMKdAr5GwDcAAA1AAQKfycAAwsACQo2HHAsAMkCAAsACQo2HHAsAMkCABIACAoUHwI6AHQCAAAA.',
Co='Cocotaso:BAAANQABCgIIAgAAAA==.Codemon:BAABNQAECn8bAAIXAAcKEBmVFQDwAQAXAAcKEBmVFQDwAQAAAA==.Cole:BAAANQADCgUIBQAAAA==.Cosmoline:BAABNQAECn8ZAAIYAAkKchU3BACoAgAYAAkKchU3BACoAgABNQAECgYIEwABAAAAAA==.Cotw:BAAANQAECgIIAgABNQAECgUICgABAAAAAA==.Coverttops:BAAANQAECgYIDwAAAA==.',
Cp='Cptcharis:BAAANQADCgEIAQAAAA==.',
Cr='Critmyshorts:BAAANQADCggICAAAAA==.Critnespears:BAAANQADCgYIBgAAAA==.',
Cu='Cubann:BAAANQAECgIIAgAAAA==.',
Cy='Cylrhea:BAAANQAECgUIDwAAAA==.Cynri:BAAANQADCgQIBQABNQAECgIIAgABAAAAAA==.Cyntrill:BAAANQAECgIIBAAAAA==.',
Da='Daboulder:BAAANQAECgEIAQAAAA==.Dadderz:BAAANQADCgYIGQAAAA==.Daedean:BAAANQAECgIIAgABNQAECgMIBAABAAAAAA==.Dagnome:BAAANQADCggICAAAAA==.Dahunter:BAAANQAECgIIAgAAAA==.Dajoel:BAAANQAECgIIAgAAAA==.Dalacia:BAAANQAECgcIEQAAAA==.Daphera:BAAANQADCgYIBgAAAA==.Darkhollow:BAAANQADCggIFQAAAA==.Darkhunta:BAAANQADCgQIBAAAAA==.Darknature:BAABNQAECn8fAAIGAAgKJRWKIQAXAgAGAAgKJRWKIQAXAgAAAA==.Darkodin:BAABNQAECn8YAAIWAAcKXgnbcQBLAQAWAAcKXgnbcQBLAQAAAA==.Darkshamy:BAAANQAECgEIAQAAAA==.Darksknightt:BAAANQADCgEIAQAAAA==.Darrad:BAAANQAECgUIBwAAAA==.Datnagadrake:BAACNQAFFH8LAAIQAAQKShHJHAAlAQAQAAQKShHJHAAlAQA1AAQKfz0AAxAACQr3IWEsAAgDABAACQpvIGEsAAgDABMABgrdINMPACgCAAAA.Dawinchy:BAABNQAECn8rAAMGAAkKixl9GAB2AgAGAAkKixl9GAB2AgAZAAYKxg7bGgBPAQAAAA==.',
De='Deadlypsycho:BAAANQAECgEIAQAAAA==.Deathavoider:BAAANQADCggICgAAAA==.Deathawakens:BAAANQADCgEIAQAAAA==.Deathlyill:BAAANQAECgIJAgAAAA==.Decemberr:BAAANQAECgQICQAAAA==.Dekudin:BAAANQAECgYIEgAAAA==.Dellistia:BAAANQADCgYICwAAAA==.Dennywenny:BAAANQAECgUIDAAAAA==.Deric:BAAANQAECgEIAQAAAA==.Desdamona:BAAANQAECgUIDQAAAA==.Destrodemon:BAAANQADCggICAAAAA==.Destropally:BAABNQAECn8eAAIPAAgKIQ9lqADKAQAPAAgKIQ9lqADKAQAAAA==.Devorick:BAABNQAECn8uAAMaAAkK5xwTKgDZAgAaAAkK5xwTKgDZAgAbAAIKIhDUVgB5AAAAAA==.',
Di='Diaval:BAAANQADCgYIFQAAAA==.Dih:BAAANQADCgYIBgABNQAECggIJAAbAAsYAA==.Dijarl:BAABNQAECn8WAAIHAAgK6BlKTACHAgAHAAgK6BlKTACHAgAAAA==.Dipndots:BAAANQAECgIIAgAAAA==.Dirtyboy:BAAANQADCgIIAgAAAA==.Discórdia:BAAANQAECgMIAwAAAA==.Diyiya:BAAANQAECgUIDwAAAA==.',
Do='Doorki:BAAANQADCggIDwAAAA==.Dottey:BAAANQAECgUIDgAAAA==.Doubleott:BAAANQAECgEIAQAAAA==.',
Dr='Drael:BAAANQAECgUIBwAAAA==.Draickin:BAABNQAECn8aAAIFAAcKPRbOYwDqAQAFAAcKPRbOYwDqAQAAAA==.Drekle:BAAANQAECgMIDQABNQAECggIJQAcADAUAA==.Drelian:BAAANQAECgIIBAAAAA==.Drevy:BAAANQAECgcIEgAAAA==.Drewdox:BAAANQADCgUJDAAAAA==.Drewsguy:BAAANQADCgYIGQAAAA==.Drexchan:BAAANQAECgEIAQAAAA==.Drizzlenuts:BAAANQAECgcIDQABNQAECgcIEwABAAAAAA==.Drrabbít:BAAANQADCgQIBAAAAA==.Drumira:BAAANQADCgMIAwABNQAECgkJHgAOAPEPAA==.Drumk:BAAANQADCgIIAgABNQAECgkJHgAOAPEPAA==.Drumma:BAAANQADCgcIBwAAAA==.Drummer:BAABNQAECn8eAAQOAAkK8Q9ENAB9AQAOAAcKnQxENAB9AQANAAUKrhSPDwAwAQAMAAUKkgUBugDlAAAAAA==.Drumroleplz:BAAANQAECgQIBAABNQAECgkJHgAOAPEPAA==.',
Dw='Dw:BAABNQAECn8eAAMdAAgKchxMFwChAgAdAAgKchxMFwChAgADAAMKqw/ZdACgAAABNQAFFAQICAAHAOERAA==.',
['Dà']='Dàddybear:BAAANQAECggICAAAAA==.',
Ea='Earthsangel:BAAANQAECgQIBAAAAA==.',
Ec='Eclair:BAAANQAECgQICQAAAA==.',
Ed='Edralyia:BAAANQADCgYICwAAAA==.',
Eg='Egwene:BAAANQADCgQIBAAAAA==.',
Ei='Eilaurosa:BAAANQAECgcIEgAAAA==.Einnarr:BAAANQAECggIBQAAAA==.',
El='Eldrinne:BAABNQAECn8cAAIUAAcKDwTkBQANAQAUAAcKDwTkBQANAQAAAA==.Eleblast:BAAANQAECgIIAgAAAA==.Elizavoid:BAABNQAECn8YAAQMAAgKsRsZQgBgAgAMAAgKsRsZQgBgAgANAAEKLheNJABEAAAOAAEKAABohwAhAAAAAA==.Elizawrath:BAAANQADCgIIAgAAAA==.Elkuco:BAAANQAECgEIAQAAAA==.Elmindreyda:BAAANQAECgUICwAAAA==.Elthiss:BAABNQAECn8oAAICAAgKaBlpEABUAgACAAgKaBlpEABUAgAAAA==.',
En='Enfer:BAAANQAECgIIAgABNQAFFAMIBwALAJsNAA==.',
Er='Erequois:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Erianthe:BAABNQAECn8iAAIWAAgKdgaTcgBIAQAWAAgKdgaTcgBIAQAAAA==.Eriok:BAAANQABCggIDwAAAA==.Erophien:BAAANQADCgMIBAAAAA==.Erovynael:BAAANQAECgQICAAAAA==.Erovynthalin:BAAANQADCgYIEAAAAA==.Errorwing:BAAANQADCggIDAAAAA==.',
Es='Eshera:BAAANQADCgIIAgAAAA==.Esherä:BAAANQAECgEIAQAAAA==.',
Ev='Eversong:BAAANQADCgYIDAAAAA==.',
Ex='Exmar:BAAANQAECgYIBgAAAA==.',
Fa='Faewhisker:BAABNQAECn8YAAMeAAkKyw07KQDQAQAeAAkKyw07KQDQAQAfAAQKBQZfOgCZAAAAAA==.Faithfool:BAABNQAECn8dAAILAAgKpwhVkgByAQALAAgKpwhVkgByAQAAAA==.Falshallnot:BAAANQADCggIBQABNQAECggIJQAcADAUAA==.Fancyfeet:BAAANQAECgUIBQABNQAECgkJGgAKADEUAA==.Fanduelfiend:BAAANQADCgMIAwAAAA==.Fangmonarch:BAAANQADCgUIBQAAAA==.Fashaladd:BAABNQAECn8lAAMcAAgKMBRuPgACAgAcAAgKMBRuPgACAgACAAEKAAAfVgBIAAAAAA==.',
Fe='Fearios:BAABNQAECn8yAAIVAAkKHxxCGADoAgAVAAkKHxxCGADoAgAAAA==.Felbeast:BAAANQAECgMIBQAAAA==.Felbound:BAAANQADCgUICQAAAA==.Femboy:BAAANQADCggICAAAAA==.Feorar:BAAANQADCgYJBgAAAA==.Feta:BAAANQAECgYICgABNQAECggIDQABAAAAAA==.',
Fi='Fieldtrip:BAAANQAECgQIBwAAAA==.Fiendfyre:BAAANQADCgUIBQAAAA==.Fizzlenuts:BAAANQAECgcIEwAAAA==.',
Fl='Flightless:BAAANQADCggICgAAAA==.',
Fo='Foxi:BAAANQAECgQJBAAAAA==.',
Fr='Frosttbyte:BAABNQAECn8yAAMgAAkK3RjjZwCuAgAgAAkKTxjjZwCuAgAhAAEKjB4/OABaAAAAAA==.Frostytute:BAAANQADCgIIAgAAAA==.',
Fu='Fullmetalass:BAAANQAECgYIEgAAAA==.',
Fy='Fyyre:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëiróx:BAAANQADCgIIAgAAAA==.',
Ga='Galistar:BAAANQAECgUICgAAAA==.Garglelots:BAAANQADCgcIBwABNQAECgkJHgALAF8UAA==.Garrotxa:BAAANQAECggICAABNQAECggIDQABAAAAAA==.',
Ge='Gevallen:BAAANQAECgYIBwAAAA==.',
Gh='Ghavinental:BAABNQAECn8dAAMLAAcKFBHCfwChAQALAAcKAQ/CfwChAQAiAAYKxQ6yHgBwAQAAAA==.',
Gi='Gil:BAABNQAECn8ZAAIdAAkKFR9qFADBAgAdAAkKFR9qFADBAgAAAA==.Gilgamesh:BAAANQAECgUICgABNQAECgkJGQAdABUfAA==.',
Gl='Glizzard:BAAANQAECgUIDAABNQAECgYIEwABAAAAAA==.Glocket:BAAANQAECgIIBQAAAA==.Gloom:BAAANQAECgYIBgAAAA==.',
Gn='Gnolan:BAAANQAECgYIEwAAAA==.',
Go='Goatspace:BAABNQAECn8cAAQHAAgKwQYXwwB3AQAHAAcK7QYXwwB3AQAIAAUKDQOuXgCnAAAYAAEKAAEkFQAaAAAAAA==.Gomu:BAAANQADCgQIBAAAAA==.Gongagà:BAABNQAECn8iAAIdAAgKSxAsLQDUAQAdAAgKSxAsLQDUAQAAAA==.Goodwithabow:BAAANQAECgQICAAAAA==.Goremaster:BAAANQAECgQICgAAAA==.Gothbaddie:BAAANQAECgQIBAABNQAECggIDQABAAAAAA==.Goyum:BAAANQADCgEIAQAAAA==.',
Gr='Grankino:BAABNQAECn8iAAQZAAcKjwxsHgAkAQAcAAcKlAb3YgA+AQAZAAUK2xBsHgAkAQACAAEKiAQrbAAeAAAAAA==.Greedisgood:BAAANQADCgMIAwAAAA==.Greenthumbs:BAAANQADCgYIBgAAAA==.',
Gw='Gwaelphypha:BAABNQAECn8gAAIVAAcKghiZQgDvAQAVAAcKghiZQgDvAQABNQAECgEIAQABAAAAAA==.',
Ha='Hakarii:BAAANQADCgEIAQAAAA==.Halder:BAAANQAECgEIAQAAAA==.Hapkido:BAABNQAECn8yAAIjAAkKGCR9AQCwAwAjAAkKGCR9AQCwAwAAAA==.Hauwitzer:BAAANQADCgYIBQAAAA==.Hawk:BAAANQAECgMIAwAAAA==.Hazrek:BAABNQAECn8VAAIiAAcKpguYGwClAQAiAAcKpguYGwClAQAAAA==.',
He='Hecate:BAAANQAECgUICgAAAA==.Heidnik:BAAANQAECgUIBQAAAA==.Heihei:BAAANQAECgYIDAAAAA==.Heneedsumilk:BAAANQADCgYICgAAAA==.Heretic:BAAANQAECgIIAgAAAA==.',
Hi='Hillboy:BAAANQADCggIDgAAAA==.',
Ho='Holydes:BAAANQAECgQIBAABNQAECgUIDQABAAAAAA==.Holytrinityy:BAAANQADCgYIBgAAAA==.Hooch:BAAANQAECgUICAAAAA==.',
Hu='Humboldt:BAAANQAECggIBAABNQAECggIDQABAAAAAA==.Huunaron:BAAANQAECgYICwAAAA==.',
['Hé']='Héx:BAACNQAFFH8gAAMgAAcKrBV4DAAQAgAgAAYKzxh4DAAQAgAhAAEKIglGDgBTAAA1AAQKfxkAAiAACQpMF5KXAFACACAACQpMF5KXAFACAAAA.',
Id='Idylwilde:BAAANQAECgUICwAAAA==.',
Ie='Ienzo:BAAANQADCgQIBwAAAA==.',
Ih='Iheartoreos:BAABNQAECn8fAAIVAAcKsBK4UACvAQAVAAcKsBK4UACvAQAAAA==.',
Il='Ilovefuta:BAAANQADCgYIBgAAAA==.Iloveoreos:BAAANQADCgYIBgAAAA==.',
In='Instakill:BAAANQADCgQIBAAAAA==.Intent:BAAANQADCgMIAwAAAA==.Invictae:BAAANQAECgUICQAAAA==.',
Io='Iobo:BAACNQAFFH8PAAIdAAYKIx51AwAfAgAdAAYKIx51AwAfAgA1AAQKfyMAAh0ACQqFJKcGAGYDAB0ACQqFJKcGAGYDAAAA.',
Ir='Irk:BAAANQAECgQIBAAAAA==.Ironic:BAAANQADCgYIBgABNQAECgkJLwAKAOsgAA==.',
Ja='Jagaerr:BAAANQABCgUICQAAAA==.Jarco:BAEANQAECgEIAQABNQAFFAYIDAAkABwaAA==.Jasseca:BAAANQAECgMIAwABNQAECgEIAQABAAAAAA==.',
Je='Jeandarc:BAAANQADCggICAAAAA==.Jezäbelle:BAAANQAECgIIAgAAAA==.',
Jo='Joesh:BAAANQABCgcIEQAAAA==.',
Ka='Kaadra:BAAANQAECgUIBQAAAA==.Kaelkin:BAABNQAECn8fAAMMAAkKhBPUTgA0AgAMAAkKhBPUTgA0AgANAAIK6gZgIgBRAAAAAA==.Kaelun:BAAANQADCgcICwABNQAECgkJHwAMAIQTAA==.Kaelundrus:BAAANQAECgYIDAABNQAECgkJHwAMAIQTAA==.Kainis:BAAANQAECgMIBQAAAA==.Kamonorin:BAAANQABCgIIAgAAAA==.Kaotika:BAAANQAECgMIAwAAAA==.Karmus:BAAANQADCgUJCAAAAA==.',
Ke='Keadin:BAAANQADCgYICwAAAA==.Keilas:BAABNQAECn8cAAIZAAYKrBzZEQDfAQAZAAYKrBzZEQDfAQAAAA==.Kerron:BAAANQAECgEIAQAAAA==.Keylala:BAAANQAECgQICQAAAA==.',
Ki='Kickenmage:BAAANQADCgQIBAABNQAECgUIDwABAAAAAA==.Kickentail:BAAANQAECgUIDwAAAA==.Kiegh:BAAANQABCgQIBAAAAA==.Kior:BAAANQADCgYIBwAAAA==.Kirisham:BAAANQADCgMIAwAAAA==.Kiriwar:BAACNQAFFH8FAAIQAAIKmxTVLACSAAAQAAIKmxTVLACSAAA1AAQKfy8AAhAACQpkInYhADEDABAACQpkInYhADEDAAAA.Kirlia:BAABNQAECn8eAAIbAAcKigx6FQDAAQAbAAcKigx6FQDAAQAAAA==.',
Kl='Klymax:BAAANQAECgYIDAAAAA==.',
Ko='Kowkowkachoo:BAAANQAECgQIBgAAAA==.',
Kr='Krellis:BAAANQAECgEIAQAAAA==.Krisp:BAABNQAECn8uAAMgAAkKCSKAFwB2AwAgAAkKCSKAFwB2AwAhAAEKrSM5NABoAAAAAA==.Krobelus:BAABNQAECn8iAAIPAAgKZQYa2wBeAQAPAAgKZQYa2wBeAQAAAA==.',
Ks='Ksharp:BAAANQADCgYIBgABNQAECgYIBgABAAAAAA==.',
Kv='Kvedadormu:BAAANQADCgYIEQAAAA==.Kvedeitrormr:BAAANQAECgEIAQAAAA==.Kvedfróðleik:BAAANQABCgEIAQAAAA==.Kvedærilaz:BAAANQADCgEIAQAAAA==.',
Ky='Kylearean:BAAANQADCgMJAwAAAA==.Kyran:BAAANQAECgIIAgAAAA==.',
['Kè']='Kèrónos:BAAANQAECgUIBwAAAA==.',
['Kì']='Kìllstheweak:BAABNQAECn8hAAIlAAgKawrLSgCIAQAlAAgKawrLSgCIAQAAAA==.',
La='Laeythe:BAAANQAECgQIBAABNQAFFAIIBgAMAI0mAA==.Lannah:BAAANQADCgYIDgAAAA==.Lash:BAAANQAECgUIBwAAAA==.',
Lc='Lclc:BAAANQAECgMIBQAAAA==.',
Le='Leafeon:BAAANQAFFAQIBAABNQAFFAcIEAASADkaAA==.Lebrin:BAABNQAECn8UAAISAAQKghnOqwAVAQASAAQKghnOqwAVAQAAAA==.Legaia:BAABNQAECn8xAAIQAAkKox+6HQA/AwAQAAkKox+6HQA/AwAAAA==.Legendknewl:BAAANQAECgQIBAAAAA==.Leliel:BAAANQADCggICAABNQAECgkJJgAFAFkbAA==.Lennyzamwam:BAAANQAECgQIBwAAAA==.Lesindre:BAAANQADCgcIDQABNQAECggIAQABAAAAAA==.Letaria:BAAANQADCgYIBgAAAA==.Lexapro:BAAANQAECgQIBgAAAA==.',
Li='Lianissa:BAAANQADCggIFAAAAA==.Lillinna:BAAANQAECgQICwAAAA==.Lipidot:BAAANQAECgIIBAAAAA==.Lithlina:BAAANQADCgYIBgAAAA==.',
Lo='Loamein:BAAANQAECgcIDQAAAA==.Lockrocks:BAAANQAECgYIEAAAAA==.Lockycharmz:BAAANQAECgEIAgABNQAECgkJMgAVAB8cAA==.Lorcán:BAAANQADCgYICwAAAA==.Lorithan:BAAANQADCgIIAgAAAA==.Lormazlezrax:BAABNQAECn8aAAISAAkKkhnRRABLAgASAAkKkhnRRABLAgAAAA==.',
Lu='Lucernyx:BAAANQAECgIIAgABNQAECgEIAQABAAAAAA==.Luckystars:BAAANQADCgQIBAAAAA==.Luis:BAAANQADCgQIBAAAAA==.Luminara:BAAANQADCgYIBgAAAA==.Lunaera:BAAANQAECgYIDAAAAA==.Lune:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Lunella:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Lunellia:BAAANQAECgQIBAAAAA==.Lunevra:BAAANQABCgcIBwABNQAECgQIBAABAAAAAA==.Lupi:BAAANQADCggIDwAAAA==.Lurkaburger:BAABNQAECn8ZAAIQAAkKthZXZgBZAgAQAAkKthZXZgBZAgAAAA==.',
Ly='Lythindra:BAAANQADCgQIBAAAAA==.',
Ma='Madhatter:BAAANQAECgQICgAAAA==.Mageistmage:BAACNQAFFH8PAAIgAAUKzhdiHQCQAQAgAAUKzhdiHQCQAQA1AAQKfxwAAiAACQqkI/BCAP4CACAACQqkI/BCAP4CAAAA.Magori:BAAANQADCgYIBgAAAA==.Majarl:BAAANQAECgYIEgAAAA==.Maki:BAAANQADCgEIAQABNQAECgcIGwAFANsgAA==.Malegar:BAAANQADCgcIFQAAAA==.Malificent:BAAANQAECgQIBAAAAA==.Mammajamma:BAABNQAECn8lAAIcAAgKtBioNQA5AgAcAAgKtBioNQA5AgAAAA==.Marsvolta:BAAANQAECgQICAAAAA==.Maruxus:BAABNQAECn8qAAIJAAgKJhdJLAAxAgAJAAgKJhdJLAAxAgAAAA==.Marwen:BAAANQADCgYIEQAAAA==.Maulsin:BAAANQADCgUIBQAAAA==.Mavanthia:BAABNQAECn8dAAMQAAgKrBFFnQDPAQAQAAgKrBFFnQDPAQATAAEK0hIWQQA4AAAAAA==.',
Mc='Mcdeathy:BAAANQAECgUICgAAAA==.Mclardragos:BAABNQAECn8cAAMmAAkKuSImBQBZAwAmAAkKuSImBQBZAwAXAAEKAADuPQAvAAAAAA==.',
Me='Meadõw:BAAANQADCgUIBQAAAA==.Meatshield:BAAANQADCgcIDAAAAA==.Mecharoni:BAABNQAECn8vAAMKAAkK6yCIDACqAgAKAAgKzx6IDACqAgAJAAcKwSCXIQBzAgAAAA==.Meganaturexl:BAAANQABCgQIBAAAAA==.Megashamxl:BAAANQABCgQIBAAAAA==.Mendication:BAAANQAECgcIDQAAAA==.Meretrixee:BAAANQADCgIIAgABNQAECgkJLAAMAEkVAA==.Meteion:BAAANQAECgQICAABNQAECggIAQABAAAAAA==.',
Mi='Miacyn:BAAANQAECgIIBQAAAA==.Miladybast:BAAANQAECgUIEAAAAA==.Miniwheet:BAAANQAECgQIBAABNQAECgkJMgAVAB8cAA==.Minke:BAAANQADCggIFgAAAA==.Mirra:BAAANQAECgYIEwAAAA==.Missdorei:BAAANQADCgUIBQAAAA==.',
Mo='Momsrymommy:BAAANQAECgUIDwAAAA==.Moodrian:BAAANQADCggICQABNQAECggIJQAcADAUAA==.Moonaurora:BAAANQABCgMIAwAAAA==.Moontater:BAAANQADCgYIBgAAAA==.Mordekaiser:BAAANQADCggICAAAAA==.Morionso:BAAANQAECgUIEQAAAA==.Morphyrinsjr:BAAANQADCgcIBwABNQAECgUICwABAAAAAA==.Mortarion:BAABNQAECn8wAAMWAAkKOxmuQQASAgAWAAcK5RuuQQASAgAlAAgK4xGZQgC0AQAAAA==.Morwenspring:BAAANQADCgMIAwAAAA==.',
Ms='Mssrbubbles:BAAANQABCggIFAAAAA==.',
Mu='Murdiûs:BAABNQAECn8nAAMeAAgK+R/1EQDLAgAeAAgK+R/1EQDLAgAfAAEKYxm8RgBKAAAAAA==.',
My='Mythbruh:BAEBNQAECn8fAAMWAAcKkiHPSgDnAQAWAAcKhiDPSgDnAQAlAAcKfhoOOwDeAQAAAA==.',
Na='Nachokru:BAAANQABCgEIAgAAAA==.Nahla:BAAANQAECgIIAgAAAA==.Namrevlis:BAAANQADCgIIAgABNQAECgkJHgAOAPEPAA==.Narl:BAAANQAECgUICAAAAA==.Nayrditation:BAAANQAECgcIDQAAAA==.Nayrlock:BAAANQAECgcICwABNQAECgcIDQABAAAAAA==.',
Nc='Nctee:BAAANQAECgUICgAAAA==.',
Ne='Necropally:BAAANQADCgcIDQAAAA==.Nevermore:BAAANQAECgYIBgAAAA==.',
Ni='Nightsmoke:BAAANQAECgMJBQAAAA==.',
No='Nolabull:BAAANQADCgQIBAAAAA==.Nonattarius:BAAANQAECgUICwAAAA==.Noraelara:BAAANQAECggIAQAAAA==.Norezfou:BAABNQAECn8yAAMMAAkKyRaxPgBsAgAMAAkKyRaxPgBsAgAOAAcKkhgRJAAOAgAAAA==.Norran:BAAANQADCgMIAwAAAA==.Notalice:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Nottartar:BAAANQAECgIJAgAAAA==.',
Nu='Nuker:BAAANQADCgYIEgAAAA==.Nurobi:BAABNQAECn8kAAIcAAkKnA9YOAAoAgAcAAkKnA9YOAAoAgAAAA==.',
Od='Odanobunaga:BAABNQAECn8mAAIQAAkKsxlNVACLAgAQAAkKsxlNVACLAgAAAA==.Odyn:BAAANQAECgQICQAAAA==.',
Oe='Oerrael:BAAANQADCgcIEAAAAA==.',
Or='Oridk:BAABNQAECn8mAAIWAAgKnBtZKgCLAgAWAAgKnBtZKgCLAgABNQAFFAMIBQAHAOUMAA==.Oripal:BAAANQADCgcICAABNQAFFAMIBQAHAOUMAA==.Oríon:BAACNQAFFH8FAAMHAAMK5QycGADyAAAHAAMK5QycGADyAAAYAAEK7wuQAgBOAAA1AAQKfycABBgACQpqIcMCAP4CABgACQpsHsMCAP4CAAcABQqhGG6pAK4BAAgABgrwFW86AHgBAAAA.',
Pa='Pangjang:BAAANQADCgcIBwAAAA==.Pankratease:BAAANQAECgcICQAAAA==.Pankratoes:BAAANQAECgIIAgABNQAECgcICQABAAAAAA==.Pankratos:BAAANQADCgUIBQABNQAECgcICQABAAAAAA==.Papahess:BAABNQAECn8gAAMcAAcKRxaaRADbAQAcAAcKRxaaRADbAQACAAMKyQxCSACFAAAAAA==.Paradias:BAABNQAECn8aAAIKAAkKMRSVEwBMAgAKAAkKMhSVEwBMAgAAAA==.Pastor:BAAANQABCgIIAgAAAA==.Paxxul:BAAANQADCggICwAAAA==.',
Pe='Peppersham:BAAANQAECgUICAAAAA==.Petespally:BAAANQAECgUICgAAAA==.',
Pf='Pfftpfft:BAAANQAECgIIBAAAAA==.',
Ph='Pha:BAAANQAFFAEIAQAAAA==.Phatdanny:BAAANQAECggIDAAAAA==.Phonycheese:BAABNQAECn8oAAMPAAgKYhdZdwA6AgAPAAgKYhdZdwA6AgAFAAIKNglRCwFaAAAAAA==.Phur:BAAANQAECgMIAwAAAA==.',
Pi='Pixen:BAABNQAECn85AAMaAAkKjxl3OACoAgAaAAkKjxl3OACoAgAnAAEKAACSMAAzAAAAAA==.',
Po='Pocalypse:BAAANQAECgQIBQAAAA==.Ponkeyfists:BAABNQAECn8hAAIeAAkKQiLSCABBAwAeAAkKQiLSCABBAwAAAA==.Portstar:BAABNQAECn8gAAIgAAkKBwlH0wDdAQAgAAkKBwlH0wDdAQAAAA==.Powderhorn:BAAANQADCgUIBQAAAA==.',
Pr='Pravium:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.Primed:BAABNQAECn8xAAIZAAkKtRJDDQBFAgAZAAkKtRJDDQBFAgAAAA==.Prozac:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.',
Pu='Pungla:BAAANQAECggIEQAAAA==.',
Qu='Quelthanos:BAABNQAECn8iAAMPAAgKQhGhlQD0AQAPAAgKQhGhlQD0AQAFAAEKfBB0GAE8AAAAAA==.',
Ra='Radical:BAAANQAECgMIBQAAAA==.Ralvick:BAAANQADCgEJAQAAAA==.Ramuun:BAAANQADCgIIAgAAAA==.Randomclown:BAAANQAECgEIAQAAAA==.Rascalfats:BAAANQAECgQIBwABNQAECgUICAABAAAAAA==.Rashii:BAABNQAECn8eAAIMAAgKbxNrXQAFAgAMAAgKbxNrXQAFAgAAAA==.Raworrior:BAABNQAECn8aAAMQAAcKFg3gvgB7AQAQAAcKFg3gvgB7AQAoAAEKOAilNAAwAAAAAA==.',
Re='Reax:BAAANQADCgYIBgAAAA==.Rebaderchi:BAABNQAECn8hAAIdAAkKYhm3GgB/AgAdAAkKYhm3GgB/AgABNQADCgMIAwABAAAAAA==.Reignofpower:BAAANQADCgUIBQAAAA==.Remoria:BAAANQAECgUIDQAAAA==.Renildan:BAAANQAECgYICgAAAA==.Renmazuo:BAAANQADCgMIAwAAAA==.Rezputan:BAAANQADCggICAAAAA==.',
Rh='Rhavin:BAAANQAECgIIAgAAAA==.Rholand:BAABNQAECn8lAAIQAAkK3xkKUwCOAgAQAAkK3xkKUwCOAgAAAA==.',
Ri='Rivalt:BAAANQABCgMIAwAAAA==.Riverra:BAAANQADCgcICgAAAA==.Rizzoy:BAABNQAECn8dAAMoAAYKThd1FABVAQAoAAUKaRl1FABVAQAQAAUKWBAC3wAmAQAAAA==.',
Ro='Rollo:BAAANQADCgIIBQAAAA==.Roottender:BAAANQADCgcICwAAAA==.Rovyr:BAABNQAECn8nAAMmAAcKAR/2EwBtAgAmAAcKAR/2EwBtAgApAAEKAAA6JwAlAAAAAA==.Rowinna:BAAANQADCgUIBQAAAA==.',
Ru='Ruckabis:BAABNQAECn8cAAISAAkKeBXoRABKAgASAAkKeBXoRABKAgAAAA==.',
Ry='Rybearkin:BAAANQADCgMIAwAAAA==.Rylos:BAAANQAECggIDQAAAA==.Ryshadow:BAAANQADCgYICwAAAA==.Ryumi:BAAANQAECgYIEgAAAA==.',
Sa='Saansula:BAAANQADCgEIAQAAAA==.Sacmaster:BAAANQADCggIDAABNQAECggIJAAbAAsYAA==.Saitamå:BAABNQAECn8iAAIfAAgKyxc5FgAUAgAfAAgKyxc5FgAUAgAAAA==.Samanaras:BAABNQAECn8eAAMTAAgKRBHbIQA4AQAQAAgKrg6hoQDEAQATAAYKUBPbIQA4AQAAAA==.Sangwyn:BAAANQADCgYIBgABNQAECgcIGwAFANsgAA==.Santiago:BAAANQADCgMIAwAAAA==.Saratoga:BAAANQAECgQICwAAAA==.Sarkana:BAABNQAECn8mAAIFAAkKWRutIgDfAgAFAAkKWRutIgDfAgAAAA==.Saxonn:BAAANQAECgIIAgAAAA==.Saydis:BAAANQAECgUICQAAAA==.',
Sc='Scatterbrain:BAAANQADCgcIDAAAAA==.',
Se='Sebattan:BAAANQADCgYIBwAAAA==.Seleinai:BAAANQADCgMIAwABNQAECgkJMgANAH8dAA==.Seleine:BAABNQAECn8yAAINAAkKfx0kAgAIAwANAAkKfx0kAgAIAwAAAA==.Seloric:BAABNQAECn8aAAIVAAcKFiFYKwBqAgAVAAcKFiFYKwBqAgAAAA==.Serendrin:BAABNQAECn8pAAIJAAgKtSAxEQDxAgAJAAgKtSAxEQDxAgAAAA==.Sevalandre:BAAANQADCggICgABNQAECgEIAQABAAAAAA==.',
Sh='Shadowskyz:BAAANQAECgQICgABNQAECgkJNgALAJcbAA==.Shaggimaggi:BAAANQAECgYIEQAAAA==.Shamanis:BAAANQADCgQIBAAAAA==.Shamina:BAABNQAECn82AAILAAkKlxuBJQDsAgALAAkKlxuBJQDsAgAAAA==.Shamorex:BAABNQAECn8gAAILAAcKjhqJTABBAgALAAcKjhqJTABBAgAAAA==.Shatter:BAAANQAECgYIEwAAAA==.Shax:BAAANQADCggICAABNQAECgkJLgAgAAkiAA==.Shlevin:BAAANQADCgcIDAAAAA==.',
Si='Sideshift:BAAANQAECgQIBAABNQAECgkJNgALAJcbAA==.Sinara:BAAANQAECgQIBAAAAA==.',
Sk='Skaarr:BAAANQADCgQIBQAAAA==.Skibidiheals:BAAANQAECgEIAQAAAA==.Skybear:BAAANQABCgYICAAAAA==.',
Sl='Slash:BAAANQADCgYIBgAAAA==.Slayn:BAABNQAECn8dAAIhAAgKRRUACgApAgAhAAgKRRUACgApAgAAAA==.Sleinx:BAAANQADCgcIBwABNQAFFAMIBwALAJsNAA==.Slyrak:BAAANQAECgYICAAAAA==.',
Sm='Smitus:BAAANQABCgIIAgAAAA==.',
Sn='Snackie:BAAANQAECgYIEQAAAA==.Snooty:BAAANQAECggJAgAAAA==.Snotpig:BAAANQAECggIBwAAAA==.',
So='Sokar:BAAANQAECggICAAAAA==.Sokolovva:BAAANQADCgcIDAAAAA==.Souled:BAAANQADCgUIBQABNQAECgkJMgAgAO4SAA==.Sourpunchkid:BAAANQAECgEIAQAAAA==.',
Sp='Spacedemon:BAAANQAECgYIEgAAAA==.Sparroh:BAAANQADCgYIBgAAAA==.Spikedriver:BAABNQAECn8gAAIHAAkK+A4FaQA/AgAHAAkK+A4FaQA/AgAAAA==.Spiky:BAAANQADCgMIAwAAAA==.',
St='Stariane:BAABNQAECn8iAAIDAAkK3hr8GADQAgADAAkK3hr8GADQAgAAAA==.Startaker:BAAANQADCggIDwAAAA==.Startaster:BAAANQADCgcIBwAAAA==.Starvoid:BAAANQAECgIIAgAAAA==.Steeldk:BAAANQAECgIJAgAAAA==.Stella:BAAANQAECgMIBAAAAA==.Stonyfist:BAAANQADCgEIAQAAAA==.Stonyy:BAAANQAECgIIAgAAAA==.Stubhorn:BAAANQADCgUICAAAAA==.',
Su='Summers:BAAANQADCgYICwAAAA==.Sumonmyface:BAABNQAECn8kAAMbAAgKCxiTIgBcAQAbAAQKEh6TIgBcAQAaAAUKAxIJwwBAAQAAAA==.Superillbomb:BAAANQADCgYJCQAAAA==.Superold:BAAANQAECgUICgAAAA==.',
Sw='Swamprot:BAABNQAECn8aAAIWAAcKah8JMwBcAgAWAAcKah8JMwBcAgAAAA==.',
Sy='Syletage:BAAANQADCgYICwAAAA==.Syral:BAAANQADCgYICwAAAA==.Syrel:BAAANQAECgEIBAAAAA==.',
Ta='Tailfordays:BAAANQADCgIIAgAAAA==.Tanky:BAAANQADCgIIAgAAAA==.Tantor:BAAANQADCgEIAQAAAA==.Taylorswift:BAABNQAECn8XAAMGAAgKriUDIgASAgAGAAUKYSUDIgASAgAZAAQKZB06GwBKAQAAAA==.',
Tc='Tchiratha:BAAANQAECgUIBQABNQAECggIIgAPAEIRAA==.',
Te='Tednougat:BAAANQADCgYIBgAAAA==.Telain:BAABNQAECn8eAAQFAAgKtAuynABKAQAFAAcKuQiynABKAQAPAAYKWAvX9gAqAQARAAIKSQzzXABjAAAAAA==.Tensuki:BAAANQADCgQIBAAAAA==.Tesh:BAAANQADCgQIBgAAAA==.',
Th='Thaelynn:BAAANQADCgYIEAAAAA==.Thakilla:BAABNQAECn8tAAIcAAkK2hFWMQBUAgAcAAkK2hFWMQBUAgAAAA==.Thordrik:BAAANQAECgEIAQAAAA==.Thorix:BAAANQAECgUICQAAAA==.Thornhub:BAAANQAECggICgABNQAFFAkJLQAbABUhAA==.Thrust:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Thrustwood:BAAANQADCgMIAwAAAA==.',
Ti='Tiammanth:BAAANQAECgUICQAAAA==.Tigerbrew:BAAANQADCgUIBQAAAA==.Tigerburn:BAAANQADCgQIBAAAAA==.Tigerdawn:BAAANQADCgYIBgAAAA==.Tikya:BAAANQADCgYIBwAAAA==.Tilsit:BAAANQAECggIDQAAAA==.Timberreaper:BAAANQADCgcICAAAAA==.Tinyz:BAAANQAECgQIBwAAAA==.Tisisme:BAAANQADCgUIBQAAAA==.',
To='Tonythetiger:BAAANQAECgQIBAABNQAECgkJMgAVAB8cAA==.',
Tr='Train:BAAANQADCgcIBwAAAA==.Trei:BAAANQADCgIIAgABNQAECgcIDQABAAAAAA==.Trexlot:BAAANQADCgIIAgAAAA==.Trinjal:BAAANQAECgEIAgAAAA==.',
Tu='Tubbylumpkin:BAAANQADCggIDAAAAA==.Tummi:BAAANQADCgcIEAAAAA==.Tumnus:BAAANQAECgEIAQAAAA==.',
Ty='Tyjan:BAAANQAECgIIAwAAAA==.',
['Tâ']='Tâfa:BAAANQADCggICAAAAA==.',
Uh='Uhtred:BAAANQADCgYIBwAAAA==.',
Ul='Ulti:BAABNQAECn8bAAIFAAcK2yBmMwCUAgAFAAcK2yBmMwCUAgAAAA==.',
Un='Unholyheart:BAAANQAECgIIAgAAAA==.',
Va='Varthios:BAAANQABCgQIBgAAAA==.Varyusha:BAAANQAECgEIAQAAAA==.',
Ve='Velantra:BAAANQAECggICQAAAA==.Venari:BAAANQAECgUIDQAAAA==.',
Vi='Vilelyn:BAAANQAECgUIDwABNQADCgEIAQABAAAAAA==.Viloria:BAABNQAECn8aAAICAAcKgRYJHgCqAQACAAcKgRYJHgCqAQAAAA==.Vincent:BAAANQADCgQIBAAAAA==.Virrard:BAABNQAECn8dAAIHAAgKDRrEUgB2AgAHAAgKDRrEUgB2AgAAAA==.',
Vl='Vladimor:BAAANQAECgQICAAAAA==.Vladimyrr:BAAANQADCgUJCAAAAA==.',
Vo='Vozrezz:BAAANQAECgUICwAAAA==.',
['Vë']='Vëda:BAABNQAECn8oAAIMAAkKeR5JGwAEAwAMAAkKeR5JGwAEAwAAAA==.',
Wa='Waffle:BAAANQAECgIIAwABNQAFFAUIBQAiAPUSAA==.Warage:BAAANQAECgEIAQAAAA==.Warske:BAAANQAECgIIAgABNQAECgUICAABAAAAAA==.',
Wh='Wheaties:BAAANQAECgYICgABNQAECgkJMgAVAB8cAA==.Whizzie:BAABNQAECn8yAAIgAAkK7hI+nQBFAgAgAAkK7hI+nQBFAgAAAA==.Whizzlecrank:BAABNQAECn8yAAIgAAkKfxH0ogA6AgAgAAkKfxH0ogA6AgAAAA==.',
Wi='Wicker:BAABNQAECn8mAAMcAAgKCxcLQwDlAQAcAAYKPxgLQwDlAQAGAAQKQRKHRQD+AAAAAA==.Willpharaoh:BAAANQADCgUICgAAAA==.Wiçker:BAAANQADCgIIAgABNQAECggIJgAcAAsXAA==.',
Wo='Wolford:BAAANQADCgYIBgAAAA==.',
Wr='Wras:BAAANQAECgUICwAAAA==.Wrectt:BAAANQAECgUIDgABNQAECgYIBgABAAAAAA==.',
['Wò']='Wòbbles:BAAANQAECgQIDAABNQAECgUICAABAAAAAA==.',
Xa='Xandrah:BAAANQADCgUJBQAAAA==.Xandrel:BAABNQAECn8gAAIPAAcKXA8wxgCJAQAPAAcKXA8wxgCJAQAAAA==.',
Xe='Xed:BAABNQAECn8oAAILAAcKshgESgBLAgALAAcKshgESgBLAgAAAA==.Xenogears:BAABNQAECn8aAAIIAAgK4BhTHgBcAgAIAAgK4BhTHgBcAgAAAA==.',
Xi='Xiansai:BAABNQAECn8jAAIOAAkKvRKCIAAyAgAOAAkKvRKCIAAyAgAAAA==.',
Ya='Yappey:BAAANQAECgcIBwAAAA==.',
Yi='Yippee:BAAANQAECgQICAAAAA==.',
Yo='Youthinasia:BAAANQAECgUIEAAAAA==.',
Ze='Zerega:BAAANQADCgcIEwABNQAECgYINQAJAGUMAA==.',
Zh='Zhi:BAAANQAECgMIBQAAAA==.Zhukov:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.',
Zo='Zombiehippo:BAABNQAECn8kAAIgAAkKlxkfVQDWAgAgAAkKlxkfVQDWAgAAAA==.',
['Áu']='Áutarch:BAAANQAECgYIEAAAAA==.',
['Ðe']='Ðemøn:BAAANQADCggIGQAAAA==.',
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
