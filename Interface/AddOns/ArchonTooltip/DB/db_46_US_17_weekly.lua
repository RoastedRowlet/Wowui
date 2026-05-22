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

local lookup = {'Warrior-Protection','Warrior-Fury','Paladin-Retribution','Warlock-Demonology','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Priest-Holy','Warrior-Arms','Warlock-Destruction','Mage-Frost','DeathKnight-Unholy','Shaman-Restoration','Paladin-Holy','Unknown-Unknown','Druid-Balance','Shaman-Elemental','DeathKnight-Frost','Monk-Windwalker','Hunter-Marksmanship','Paladin-Protection','Priest-Discipline','Hunter-BeastMastery','DemonHunter-Vengeance','Warlock-Affliction','Monk-Brewmaster','Rogue-Subtlety','Monk-Mistweaver','DeathKnight-Blood','Evoker-Preservation','Shaman-Enhancement','Evoker-Devastation','Evoker-Augmentation','Hunter-Survival',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aanaleaa:BAAALgAECgUJCgAAAA==.',
Ab='Abelram:BAAALgADCgUJBQAAAA==.',
Ad='Ad:BAABLgAECn8XAAMBAAgJBBj3DgCqAQABAAgJBBj3DgCqAQACAAUJ+QqZSgDIAAAAAA==.Adellon:BAAALgAFFAIJBAAAAA==.Adhar:BAAALgAECgEJAQAAAA==.Adrielle:BAABLgAECn8dAAIDAAYJWxtZdQA3AQADAAYJWxtZdQA3AQAAAA==.',
Ae='Aeiox:BAAALgADCgMJAwAAAA==.Aevelman:BAABLgAECn8gAAIEAAgJmBSRPgCjAQAEAAgJmBSRPgCjAQAAAA==.',
Af='Affinty:BAAALgAECgQJBAABLgAFFAcJFgAFAHwbAA==.',
Ag='Ag:BAAALgAECgMJAwAAAA==.',
Ai='Airphobic:BAAALgAECgMJCgAAAA==.',
Ak='Akakage:BAAALgAECgEJAQABLgAECggJGQAGACoXAA==.Akakaji:BAABLgAECn8ZAAIGAAgJKhe7KQDaAQAGAAgJKhe7KQDaAQAAAA==.Akutoku:BAAALgADCgcJDAAAAA==.',
Al='Aland:BAAALgADCggJEgAAAA==.Alea:BAABLgAECn8cAAIHAAgJMxxsFACSAgAHAAgJMxxsFACSAgAAAA==.Almodiir:BAAALgADCgUJBwAAAA==.Almoraz:BAAALgAECgUJBQAAAA==.',
An='Anachron:BAAALgADCgIJAgAAAA==.Anaki:BAAALgADCgcJDwAAAA==.Anomander:BAAALgAECgYJEwAAAA==.Anonymoose:BAAALgADCgQJBAAAAA==.',
Ao='Aol:BAAALgADCgUJBQAAAA==.',
Ar='Ar:BAABLgAECn8VAAIIAAcJfBCFJABXAQAIAAcJfBCFJABXAQABLgAECggJFwABAAQYAA==.Arbiter:BAAALgAECgUJCQAAAA==.Archon:BAABLgAECn8cAAMCAAcJ3R2TFgDtAQACAAcJ3R2TFgDtAQAJAAMJWBqaMwCUAAAAAA==.Argig:BAAALgADCgcJCAAAAA==.Arienca:BAABLgAECn84AAMKAAkJ9A+FCgBIAQAEAAkJ6gpIRgCJAQAKAAgJnhCFCgBIAQAAAA==.Arwenn:BAAALgAECgEJAQAAAA==.',
As='Asu:BAAALgAECgYJEgAAAA==.',
At='At:BAABLgAECn8ZAAILAAYJyhUTqACJAQALAAYJyhUTqACJAQABLgAECggJFwABAAQYAA==.',
Au='Aubrey:BAACLgAFFH8MAAIHAAUJRwbdIwDxAAAHAAUJRwbdIwDxAAAuAAQKfxQAAgcACQlyCqVSAFwBAAcACQlyCqVSAFwBAAAA.',
Av='Avengion:BAAALgAECgYJDQAAAA==.',
Ba='Balthromaw:BAAALgADCggJDQAAAA==.Barbato:BAAALgADCgYJCQAAAA==.Barbie:BAAALgADCgYJBgAAAA==.',
Be='Beararms:BAAALgADCgcJCAAAAA==.Beav:BAAALgAECgYJBwABLgAFFAUJEgAHAAgbAA==.Beldent:BAAALgAECgQJBwAAAA==.',
Bl='Blazegrave:BAAALgADCgMJAwABLgAECgkJKAALAOcQAA==.Blazeofglory:BAAALgADCgUJBQABLgAECgYJFAAMAGIHAA==.Blazerunner:BAABLgAECn8oAAILAAkJ5xCvPQDiAQALAAkJ5xCvPQDiAQAAAA==.Blazesmasher:BAAALgADCgkJEwABLgAECgkJKAALAOcQAA==.Blitzkreig:BAAALgAECgYJDgAAAA==.Bluefoot:BAABLgAECn8UAAINAAYJtgiyWADqAAANAAYJtgiyWADqAAAAAA==.Blured:BAABLgAECn8yAAIGAAkJiCPVAwAjAwAGAAkJiCPVAwAjAwAAAA==.',
Bo='Booty:BAABLgAECn8oAAIBAAkJsyKtAwC5AgABAAkJsyKtAwC5AgAAAA==.',
Br='Brightblayde:BAABLgAECn8VAAIDAAYJChFTjgAJAQADAAYJChFTjgAJAQAAAA==.Brynhildre:BAABLgAECn8UAAIOAAcJfgtURABmAQAOAAcJfgtURABmAQABLgAFFAUJDAAHAEcGAA==.',
Bu='Buum:BAAALgAECgUJCgAAAA==.',
By='Byane:BAAALgADCgYJBgAAAA==.',
Ca='Cachelyn:BAAALgADCgcJBwAAAA==.Cali:BAACLgAFFH8dAAIGAAYJFyDZCgDRAQAGAAYJFyDZCgDRAQAuAAQKfywAAgYACAmkIeQSAOgCAAYACAmkIeQSAOgCAAAA.Cantouchthes:BAABLgAECn8UAAILAAgJYx7mKgAsAgALAAgJYx7mKgAsAgAAAA==.Captnage:BAAALgADCggJCAAAAA==.',
Ce='Cederred:BAAALgAECgUJBQABLgAECggJCgAPAAAAAA==.Cedertree:BAAALgADCgcJBwABLgAECggJCgAPAAAAAA==.Celline:BAAALgADCgEJAQAAAA==.Cephus:BAABLgAFFH8LAAIHAAUJehQZEgBtAQAHAAUJehQZEgBtAQAAAA==.Cerafina:BAAALgADCgEJAQAAAA==.',
Ch='Choom:BAABLgAECn8fAAMHAAkJuhUONgDQAQAHAAkJuhUONgDQAQAQAAYJjRPrLgCOAQAAAA==.Chorizo:BAAALgADCgEJAQAAAA==.Christhina:BAAALgADCgQJBAAAAA==.Chronocide:BAABLgAECn8qAAIRAAkJ2B8REACpAgARAAkJ2B8REACpAgAAAA==.Chronophasia:BAAALgAECgQJBAAAAA==.Chroños:BAAALgAECgcJDgAAAA==.Chumléé:BAAALgADCgQJBAAAAA==.Chérry:BAACLgAFFH8VAAIGAAUJrRwZHgBQAQAGAAUJrRwZHgBQAQAuAAQKfxsAAgYACAnoI4wQAPoCAAYACAnoI4wQAPoCAAAA.',
Cl='Climpwimp:BAAALgAECgEJAQAAAA==.Cluntasaur:BAAALgAECgUJBgAAAA==.',
Co='Connerr:BAABLgAECn8aAAIHAAgJtBohJADkAQAHAAgJtBohJADkAQAAAA==.Cowage:BAAALgAECgQJCQAAAA==.',
Cr='Crisse:BAAALgAECgEJAQAAAA==.Croh:BAABLgAECn8aAAMMAAgJpBNfVAD0AQAMAAgJpBNfVAD0AQASAAQJawb3DwCcAAAAAA==.Crucks:BAAALgADCgQJBAAAAA==.Cruknar:BAAALgAECgEJAQAAAA==.',
Cu='Curita:BAAALgADCgEJAQAAAA==.',
Cy='Cynestra:BAAALgAECgYJCgAAAA==.',
Da='Dadudadu:BAACLgAFFH8SAAIDAAYJXA6WDgA1AQADAAYJXA6WDgA1AQAuAAQKfzQAAgMACQkZIHoWAOICAAMACQkZIHoWAOICAAAA.Daffo:BAAALgAECgIJAQAAAA==.Daftmonk:BAACLgAFFH8aAAITAAUJFyXKAgCoAQATAAUJFyXKAgCoAQAuAAQKfyoAAhMACAnJJLECAG8DABMACAnJJLECAG8DAAAA.Daitanfuteki:BAAALgADCgEJAQABLgAFFAQJCAAUAOcVAA==.Darkfyre:BAAALgADCgEJAgAAAA==.Darks:BAAALgAECgIJAgAAAA==.Darkwingfish:BAABLgAECn8pAAIGAAkJrRTzMQC0AQAGAAkJrRTzMQC0AQAAAA==.Dartran:BAAALgADCgIJBwAAAA==.Dasarus:BAAALgAECgUJCwAAAA==.Dayman:BAABLgAECn8UAAMVAAcJggJRJgCRAAAVAAcJWwJRJgCRAAADAAYJ0wFE7QBvAAAAAA==.',
De='Deadmedic:BAAALgAECgMJAwABLgAECgcJHQAWAFcQAA==.Deadweight:BAABLgAECn8UAAMMAAcJmAkYewAjAQAMAAcJ+wgYewAjAQASAAcJxgWWEgDOAAAAAA==.Decày:BAAALgAECgcJDwAAAA==.Demoteck:BAAALgAECgQJBgAAAA==.Deredris:BAAALgAECgEJAQAAAA==.Deth:BAAALgAECgIJAgABLgAECgMJCgAPAAAAAA==.Dethblow:BAAALgAECgMJCgAAAA==.',
Di='Disconnects:BAAALgADCgUJBQAAAA==.Dium:BAAALgAECgEJAQAAAA==.Diwa:BAABLgAECn8ZAAMNAAkJ/AYCTAAbAQANAAkJ/AYCTAAbAQARAAYJSQfgUQD/AAAAAA==.',
Dk='Dklot:BAAALgAFFAMJAwAAAA==.',
Dr='Dragolot:BAAALgADCgQJBAABLgAFFAMJAwAPAAAAAA==.Draken:BAAALgAECgEJAQAAAA==.Draviin:BAABLgAECn8wAAIXAAkJ9x2eDgCVAgAXAAkJ9x2eDgCVAgAAAA==.',
Du='Duckcheese:BAAALgADCgEJAQAAAA==.Dunkyn:BAAALgAECgMJBgAAAA==.Durzoblint:BAAALgAECgUJCAAAAA==.',
Dy='Dyemon:BAAALgADCgIJAgAAAA==.',
['Dé']='Déad:BAAALgADCgcJDAAAAA==.',
El='Elementz:BAAALgAECgIJAgAAAA==.Elerae:BAABLgAECn8nAAIDAAkJ+BthFgDjAgADAAkJ+BthFgDjAgAAAA==.Eleshkigal:BAABLgAECn8oAAMGAAkJ1yaKAwCTAwAGAAkJ1yaKAwCTAwAYAAQJiBqDDAA3AQAAAA==.',
En='Enkeke:BAABLgAECn84AAIMAAkJ5BwAGQBtAgAMAAkJ5BwAGQBtAgAAAA==.',
Er='Eresanna:BAAALgAFFAMJAwAAAA==.Ereshkigal:BAAALgAECgEJAQAAAA==.',
Es='Esdeath:BAAALgAECgQJCAABLgAFFAMJAwAPAAAAAA==.Estus:BAAALgAECggJEwAAAA==.',
Ex='Extremefear:BAABLgAECn8iAAMKAAgJrBOIFgC3AAAEAAQJ/hKthwDsAAAKAAUJKhSIFgC3AAAAAA==.',
Fa='Fatima:BAAALgAECgIJAwAAAA==.',
Fe='Fearious:BAACLgAFFH8TAAMEAAUJVSUODwCoAQAEAAUJxiQODwCoAQAZAAEJYSa2BwBxAAAuAAQKfx8AAwQACAnPJdQrAF8CAAQABwn9I9QrAF8CAAoAAgkmJFQ3ANgAAAAA.Felphetamine:BAAALgADCggJCAAAAA==.Fenrisfangs:BAABLgAECn8VAAIXAAkJSA6YMwC7AQAXAAkJSA6YMwC7AQAAAA==.Fenrisul:BAAALgADCgkJCwAAAA==.Feralshunter:BAACLgAFFH8IAAIUAAQJ5xV6CwAtAQAUAAQJ5xV6CwAtAQAuAAQKfzIAAhQACQn/IJcQALcCABQACQn/IJcQALcCAAAA.Feroond:BAAALgADCgQJBAAAAA==.',
Fi='Fingeritout:BAAALgADCgIJAgAAAA==.Firefly:BAAALgAECgMJAwAAAA==.',
Fl='Florea:BAAALgADCggJDAAAAA==.',
Fo='Forfoxsake:BAABLgAECn8iAAIaAAgJlx86DAA2AgAaAAgJlx86DAA2AgAAAA==.',
Fr='Frogteeth:BAAALgADCgUJBQAAAA==.',
Fu='Furibeav:BAABLgAFFH8SAAIHAAUJCBteDACrAQAHAAUJCBteDACrAQAAAA==.Furrów:BAAALgADCgcJCAAAAA==.',
['Fû']='Fûrrow:BAAALgAECgEJAgAAAA==.',
Ga='Gallindral:BAABLgAECn82AAIGAAkJUR0/DQCeAgAGAAkJUR0/DQCeAgAAAA==.Garanda:BAAALgAECgQJBQAAAA==.Gatito:BAAALgADCgEJAQABLgAECgIJAgAPAAAAAA==.Gauthus:BAAALgAECggJCAAAAA==.',
Ge='Genericnpc:BAAALgAECgcJDgAAAA==.Geobrando:BAABLgAECn83AAMNAAkJOR9tCwDHAgANAAkJOR9tCwDHAgARAAYJmQ+xSQC1AAAAAA==.',
Gg='Ggbrews:BAACLgAFFH8UAAIDAAUJACCsEwBuAQADAAUJACCsEwBuAQAuAAQKf24ABAMACQmtJacCAFADAAMACQmtJacCAFADAA4ACAn1GNsTACYCABUABgmcCOgiAKgAAAAA.',
Gh='Ghostblaze:BAAALgAECgUJCwABLgAECgkJKAALAOcQAA==.',
Gi='Gier:BAAALgADCgUJBQAAAA==.Gino:BAAALgADCgEJAQAAAA==.',
Gl='Glacious:BAAALgADCgEJAQAAAA==.Glasswings:BAAALgAECgIJAgAAAA==.',
Gn='Gnosh:BAAALgAECgYJDQAAAA==.Gnova:BAABLgAECn8hAAILAAYJGyEBRgDHAQALAAYJGyEBRgDHAQAAAA==.',
Go='Gorian:BAAALgAECgcJBQAAAA==.',
Gr='Gregorz:BAAALgADCgEJAQAAAA==.Grish:BAAALgADCgcJGAAAAA==.',
Gu='Guidosarduci:BAABLgAECn8iAAINAAgJhhdgHAA2AgANAAgJhhdgHAA2AgAAAA==.',
Ha='Hairia:BAAALgADCgUJBQAAAA==.Halen:BAAALgADCgcJBwABLgAFFAYJHQAGABcgAA==.Harle:BAAALgAECgYJDgAAAA==.Hatari:BAAALgAECgMJAwAAAA==.',
He='Hektate:BAABLgAECn8WAAILAAcJXQvRgAA5AQALAAcJXQvRgAA5AQABLgAFFAYJEgADAFwOAA==.Henryjones:BAAALgADCgEJAQAAAA==.',
Hi='Hikari:BAABLgAECn8WAAIDAAgJZSFlFwB4AgADAAgJZSFlFwB4AgABLgAFFAYJHQARAKIaAA==.Hilkesad:BAAALgAECgQJBAAAAA==.Hizo:BAAALgADCgUJBQAAAA==.',
Ho='Holybeave:BAABLgAECn8eAAMIAAkJNB3/DACFAgAWAAkJaBi5CQCfAgAIAAgJqx7/DACFAgABLgAFFAUJEgAHAAgbAA==.Holyshortguy:BAAALgAECgQJBQAAAA==.Hoofer:BAAALgAECgYJDgAAAA==.',
Hu='Hunkomeat:BAABLgAECn8XAAICAAgJLhzkLAAAAgACAAgJLhzkLAAAAgAAAA==.',
['Hë']='Hënry:BAAALgAECgEJAQAAAA==.',
Ic='Icelmo:BAABLgAFFH8HAAICAAQJiRDBFQAnAQACAAQJiRDBFQAnAQAAAA==.',
Ih='Ihotyou:BAAALgADCgQJBwAAAA==.',
In='Inai:BAAALgADCgcJDAABLgAFFAMJAwAPAAAAAA==.Invizww:BAAALgAECgMJAwAAAA==.',
Ir='Ircapslock:BAAALgAECgYJCwAAAA==.',
Iv='Ivorypal:BAABLgAECn8gAAIOAAgJqR/dEACLAgAOAAgJqR/dEACLAgAAAA==.',
Ja='Jacksock:BAAALgADCgEJAQAAAA==.Jamzz:BAAALgADCgYJDQABLgAFFAUJEQAUALYVAA==.Jaromir:BAAALgADCgcJBwAAAA==.Jaskow:BAABLgAECn8uAAIHAAkJjyDHBAA+AwAHAAkJjyDHBAA+AwAAAA==.Jaymick:BAAALgAECgYJDQAAAA==.',
Jb='Jbizzler:BAAALgAECgcJBQAAAA==.',
Je='Jernau:BAAALgAECgEJAQAAAA==.Jessortess:BAAALgAECgQJBwAAAA==.',
Jo='Johnwicksdog:BAAALgAECggJEQAAAA==.Jorbies:BAAALgAECgYJCQABLgAFFAcJFgAFAHwbAA==.Jorls:BAACLgAFFH8WAAMFAAcJfBtMAgDeAQAFAAcJfBtMAgDeAQAWAAEJWAEnGwBDAAAuAAQKfxsABAUACQkFHlMIAP8CAAUACQkFHlMIAP8CABYABAnSCc08AMQAAAgAAglAAgl2AFEAAAAA.',
Ju='Jusdatip:BAAALgAECgUJDQAAAA==.',
Ka='Kaelthazed:BAAALgADCgEJAQABLgAECgkJMwAEANAfAA==.Kalfu:BAABLgAECn8XAAMXAAgJzR2rHwAZAgAXAAgJzR2rHwAZAgAUAAYJoBUDOgB5AQAAAA==.Kameshoga:BAAALgAECgIJAgAAAA==.Kammwin:BAAALgAECgYJEwAAAA==.Karten:BAAALgAECgMJAwAAAA==.Kaylea:BAAALgADCgIJAgAAAA==.',
Ke='Kellandria:BAAALgADCgYJBgAAAA==.',
Ki='Kittêh:BAAALgADCgMJAwAAAA==.',
Kn='Knathor:BAAALgAECgMJAwABLgAECgcJDgAPAAAAAA==.',
Ko='Korec:BAAALgAECgcJDgAAAA==.',
Kr='Krasis:BAABLgAECn8XAAIDAAkJvhrLWADYAQADAAkJvhrLWADYAQAAAA==.Krazermonk:BAACLgAFFH8GAAITAAMJgRepEgDpAAATAAMJgRepEgDpAAAuAAQKfyUAAhMACQmRHo4IAHUCABMACQmRHo4IAHUCAAAA.Kristysavage:BAABLgAECn8bAAIXAAgJTiElEgB3AgAXAAgJTiElEgB3AgAAAA==.',
Ku='Kurosakí:BAAALgAECgEJAQAAAA==.',
La='Lanc:BAAALgAECgQJCQAAAA==.Larradin:BAAALgADCggJEAAAAA==.Lawnchair:BAAALgAECggJCQAAAA==.',
Le='Lealta:BAAALgAECgYJCwAAAA==.Leonus:BAAALgAECgQJCQAAAA==.Leviathahn:BAAALgAECgEJAgAAAA==.',
Lh='Lhegholhaz:BAAALgADCgEJAQAAAA==.',
Li='Lichdawg:BAACLgAFFH8LAAISAAQJ8AtIBgAZAQASAAQJ8AtIBgAZAQAuAAQKfxQAAhIACAnSE3cHAKMBABIACAnSE3cHAKMBAAAA.Lilzayna:BAAALgADCgIJAgABLgAECgUJBgAPAAAAAA==.Linthori:BAEALgADCgMJAwABLgAECgcJDQAPAAAAAA==.Lithlia:BAAALgADCgcJBwAAAA==.Livvela:BAABLgAECn8iAAIbAAkJoBS4EADUAQAbAAkJoBS4EADUAQAAAA==.',
Ll='Llas:BAAALgADCgIJAgAAAA==.',
Lo='Lockdawg:BAACLgAFFH8XAAIEAAYJ7hBGGAB7AQAEAAYJ7hBGGAB7AQAuAAQKfyYAAwQACAmFHRImAHoCAAQACAmFHRImAHoCAAoAAQnWFc1sADoAAAAA.Lockedin:BAAALgAECgkJEgAAAA==.Lonne:BAAALgAECgYJDgABLgAFFAIJBAAPAAAAAA==.Lover:BAABLgAECn8jAAIIAAkJNh4qBwC6AgAIAAkJNh4qBwC6AgAAAA==.',
Lu='Lubu:BAAALgAFFAMJAwAAAA==.Lucianis:BAAALgADCgQJBwAAAA==.Luckycharmz:BAAALgAECgQJCQABLgAECgcJHQAWAFcQAA==.Luckywar:BAAALgADCgYJBgAAAA==.Luell:BAAALgAECgcJCQAAAA==.Luev:BAAALgAECgYJCAAAAA==.Lumiette:BAAALgAECgYJCQAAAA==.',
Ly='Lynai:BAAALgAECgUJDAAAAA==.',
['Lá']='Lándwhale:BAACLgAFFH8PAAIbAAQJISO2BwCEAQAbAAQJISO2BwCEAQAuAAQKfy4AAhsACQmTJNYBABMDABsACQmTJNYBABMDAAAA.',
['Lö']='Löver:BAAALgAECgcJBwAAAA==.',
Ma='Mabil:BAABLgAECn8UAAQEAAcJRRIadgARAQAEAAYJeg0adgARAQAZAAQJXRWcGAC2AAAKAAIJNAyaMQAsAAAAAA==.Macktimus:BAABLgAECn8XAAIKAAgJTxa1BQC6AQAKAAgJTxa1BQC6AQAAAA==.Mage:BAAALgAFFAEJAQAAAA==.Magictonyp:BAAALgAECgEJAQAAAA==.Magicznstuff:BAAALgAECgEJAQABLgAECgMJBgAPAAAAAA==.Magna:BAABLgAECn8lAAICAAkJYRJKGgDMAQACAAkJYRJKGgDMAQAAAA==.Makili:BAAALgAFFAMJAwAAAA==.Maladrix:BAAALgAECgQJDQAAAA==.Mauê:BAAALgADCgEJAQABLgAECgIJAgAPAAAAAA==.',
Mc='Mchunter:BAAALgAECgMJAwAAAA==.Mcshadow:BAAALgADCgIJAgAAAA==.',
Me='Menphina:BAAALgAECgIJAgAAAA==.Merigold:BAAALgAECgEJAQABLgAECgQJBAAPAAAAAA==.',
Mi='Minnow:BAAALgAECgYJDQAAAA==.Mintchip:BAAALgAECgcJEQAAAA==.',
Mo='Monk:BAAALgAECgEJAQAAAA==.Monza:BAAALgADCgEJAQABLgAECgkJKAALAOsWAA==.Moontini:BAAALgADCgYJBgABLgAECgQJDQAPAAAAAA==.Mordryn:BAAALgADCgcJBwAAAA==.',
My='Mysternia:BAAALgAECgYJDgAAAA==.Myyagie:BAAALgADCgUJDAAAAA==.',
Na='Nalthexon:BAABLgAECn8qAAMcAAgJ2wtFMQAzAQAcAAgJ2wtFMQAzAQATAAEJXQaCewAqAAABLgAFFAMJAwAPAAAAAA==.Natureborne:BAAALgAECgYJCQAAAA==.',
Ne='Nedrud:BAAALgADCgUJCAAAAA==.Nelson:BAEALgAECgYJBgABLgAECggJHQALANkWAA==.Nenno:BAAALgADCgEJAQAAAA==.Netzhul:BAAALgAFFAEJAQAAAA==.',
Ni='Night:BAAALgAECgcJEQAAAA==.Nikalos:BAAALgAECgYJDQAAAA==.Nikole:BAAALgAECgMJAwAAAA==.',
No='Noon:BAAALgADCgUJBQABLgAECggJEwAPAAAAAA==.Notorckrag:BAABLgAECn83AAIaAAkJ5iG/AgAAAwAaAAkJ5iG/AgAAAwAAAA==.Nozomi:BAAALgAECgIJAgAAAA==.',
Nu='Nut:BAAALgADCgQJBAAAAA==.',
['Nê']='Nêz:BAAALgAECgUJCAAAAA==.',
Oa='Oathbringer:BAAALgAECgQJBAAAAA==.',
Ob='Oblivionz:BAAALgAECgMJAwAAAA==.',
Oc='Ocho:BAAALgADCgYJCQAAAA==.',
Of='Offbrandcleo:BAAALgAECgkJBQAAAA==.',
Ol='Oldrecipe:BAAALgAFFAIJAwAAAA==.Oliange:BAABLgAECn8cAAILAAgJAAt7cgBVAQALAAgJAAt7cgBVAQAAAA==.',
Or='Ori:BAEALgADCgcJCwABLgAECgcJDQAPAAAAAA==.Originalgank:BAAALgAECgYJCgAAAA==.',
Pa='Papanell:BAAALgADCgYJCQAAAA==.',
Pe='Peachcobbler:BAAALgAECggJDgAAAA==.',
Ph='Philsner:BAEALgAECgcJDQAAAA==.Phink:BAAALgAECgQJCgAAAA==.',
Pi='Pinkk:BAAALgAFFAEJAQAAAA==.',
Pl='Plushie:BAAALgAECgcJDwAAAA==.',
Po='Pooqy:BAACLgAFFH8MAAMMAAUJlyQXFACkAQAMAAQJlyQXFACkAQAdAAEJAACCLAAAAAAuAAQKfxYAAgwACAlWIrskAKsCAAwACAlWIrskAKsCAAAA.Porcel:BAAALgADCgcJCwAAAA==.Potatoteng:BAAALgAECgcJBwABLgAFFAUJDQADADYZAA==.',
Pr='Pritej:BAAALgAECgYJCgABLgAFFAIJBAAPAAAAAA==.Proto:BAAALgAECgcJDAAAAA==.',
Pu='Puck:BAAALgAECgIJBgABLgAFFAMJAwAPAAAAAA==.',
Py='Pyraleus:BAAALgADCgQJBAAAAA==.',
Qu='Quickchicken:BAAALgADCgYJBgAAAA==.',
Ra='Ragel:BAABLgAECn8jAAIQAAgJDh2rDQAtAgAQAAgJDh2rDQAtAgAAAA==.Rainesage:BAABLgAECn8eAAMFAAgJ2hlpEgDwAQAFAAgJ2hlpEgDwAQAIAAEJxwePXQAnAAAAAA==.Ralphel:BAABLgAECn8ZAAIDAAcJRAYMlQD+AAADAAcJRAYMlQD+AAAAAA==.Rasu:BAAALgADCgcJBwABLgAECggJGgAeALUMAA==.Ravendark:BAAALgADCgcJCQAAAA==.Rayozap:BAAALgAECgQJBAAAAA==.',
Re='Redeye:BAAALgADCgMJAwAAAA==.',
Rh='Rhondaa:BAAALgAECgYJEQAAAA==.Rhubarb:BAABLgAECn81AAMJAAkJXiamAABQAwAJAAgJtyWmAABQAwACAAgJlyTbBgCzAgAAAA==.',
Ri='Riyci:BAAALgAECgEJAQAAAA==.',
Ro='Rohiem:BAABLgAECn8uAAICAAkJpBjqDQBLAgACAAkJpBjqDQBLAgAAAA==.',
Ry='Ryan:BAABLgAECn8eAAIDAAkJZR4ZHADBAgADAAkJZR4ZHADBAgAAAA==.Rylorthas:BAACLgAFFH8bAAIIAAUJJRntBwBtAQAIAAUJJRntBwBtAQAuAAQKfy0AAggACQl8HMsSAEoCAAgACQl8HMsSAEoCAAAA.Rylosh:BAAALgADCgYJBgABLgAFFAUJGwAIACUZAA==.',
Sa='Sabot:BAAALgAECgYJDQAAAA==.Sabrook:BAAALgADCggJCAAAAA==.Salazar:BAAALgAECgEJAwAAAA==.Sam:BAAALgAECgUJBAAAAA==.Satisfied:BAAALgAECgQJDAAAAA==.',
Sc='Scottmonk:BAAALgAECgIJBAAAAA==.Scottpaladin:BAAALgAECgEJAQABLgAECgIJBAAPAAAAAA==.',
Se='Sentaí:BAAALgAECgIJBAAAAA==.',
Sh='Shamerica:BAACLgAFFH8UAAIfAAYJBSKpAADRAQAfAAYJBSKpAADRAQAuAAQKfysAAx8ACQnvIsACABYDAB8ACQnvIsACABYDABEABAlTHVc/AE0BAAAA.Shizuku:BAAALgADCgUJBQAAAA==.Shmooythefox:BAABLgAECn8iAAIXAAcJYyHkHQAkAgAXAAcJYyHkHQAkAgAAAA==.Shokan:BAAALgADCgQJBAAAAA==.Shortleedin:BAAALgAECgIJAQAAAA==.Shòckwave:BAAALgADCgQJBAAAAA==.',
Si='Sixstar:BAAALgADCgEJAQAAAA==.',
Sk='Skrt:BAAALgADCgkJEgAAAA==.Skyleax:BAACLgAFFH8KAAMMAAQJdg0TRAAwAQAMAAQJdg0TRAAwAQASAAEJwAK7EgA+AAAuAAQKfxgABAwACQkSIEYuAH8CAAwACQnoHEYuAH8CABIABAkVHkUMAPAAAB0AAQn7D0ZLACAAAAAA.',
Sl='Slagothor:BAABLgAECn8VAAIMAAkJywRnmQBNAQAMAAkJywRnmQBNAQAAAA==.Sleaze:BAAALgADCgEJAQAAAA==.Sleazus:BAAALgAECgMJAwAAAA==.',
Sm='Smeesha:BAABLgAECn8fAAQeAAgJxRXPCwDPAQAeAAcJgxbPCwDPAQAgAAYJRQcGJgDzAAAhAAYJ1wahRgDBAAAAAA==.',
Sn='Snaxwell:BAAALgADCgEJAQAAAA==.',
So='Somin:BAAALgAECgMJBAAAAA==.',
Sp='Spekaleks:BAAALgADCgUJBwAAAA==.',
Sq='Squitwurt:BAAALgADCgYJBgAAAA==.',
St='Starbux:BAAALgAECgMJBAAAAA==.Starbúcks:BAAALgAECgIJAwABLgAECgcJHQAWAFcQAA==.Steppers:BAAALgAECgUJAgAAAA==.Straamm:BAAALgADCgMJAwAAAA==.',
Su='Sugarr:BAAALgADCgMJAwAAAA==.Sunfish:BAAALgADCgcJBwAAAA==.',
Sv='Svelana:BAABLgAECn8fAAMTAAgJwSF6DQCkAgATAAgJwSF6DQCkAgAcAAEJCgvmcwAlAAAAAA==.',
Sy='Syb:BAAALgAECgYJDgAAAA==.Sylphrena:BAACLgAFFH8MAAIFAAQJvRueCgBjAQAFAAQJvRueCgBjAQAuAAQKfykAAgUACQnSIjwDAAMDAAUACQnSIjwDAAMDAAAA.Syssana:BAAALgAECgIJBQAAAA==.',
Ta='Tadaa:BAAALgADCgIJAgAAAA==.Tamioka:BAAALgAECgYJCAAAAA==.Tanookii:BAAALgAECgYJEwAAAA==.',
Te='Telafar:BAAALgAECgkJAQAAAA==.',
Th='Theinsider:BAABLgAECn8zAAMEAAkJ0B+LDAAWAwAEAAkJ0B+LDAAWAwAKAAUJkA+nKwARAQAAAA==.Thenezath:BAAALgADCgQJBAAAAA==.Theoutsider:BAAALgAECgYJCAABLgAECgkJMwAEANAfAA==.Thunrus:BAAALgADCgYJBgAAAA==.',
Ti='Tibbles:BAAALgAECgcJCAAAAA==.Tigerbait:BAAALgAECgQJBwAAAA==.Tindril:BAAALgAECgYJBwAAAA==.Tinymo:BAAALgAECgMJAwAAAA==.',
To='Toji:BAAALgAECgcJDAABLgAFFAYJHQARAKIaAA==.Tomatoteng:BAACLgAFFH8NAAIDAAUJNhmPGQBYAQADAAUJNhmPGQBYAQAuAAQKfyAAAgMACQmPJH4DAJsDAAMACQmPJH4DAJsDAAAA.Totegoat:BAAALgADCgEJAQAAAA==.Totemmalotes:BAAALgADCgcJBwAAAA==.Totemofbear:BAAALgAECgcJDgAAAA==.',
Tr='Trandis:BAAALgADCgMJBAABLgAECgkJKAAGANcmAA==.Tranza:BAAALgAECggJEwAAAA==.Treesus:BAAALgADCgcJBwABLgAECgkJKAABALMiAA==.Trinshunter:BAABLgAECn8gAAQXAAgJcxYVMQDGAQAXAAgJcxYVMQDGAQAiAAEJ6gnELwA0AAAUAAEJ4gEnmgAZAAABLgAFFAQJDwADAOUOAA==.',
Tx='Tx:BAACLgAFFH8dAAIRAAYJohoBBwCsAQARAAYJohoBBwCsAQAuAAQKfygAAhEACAmNIUcQAKcCABEACAmNIUcQAKcCAAAA.',
Ty='Tyedye:BAAALgAECgEJAQAAAA==.',
['Tí']='Tíbs:BAAALgAECgYJCwAAAA==.',
Un='Unbound:BAAALgADCgcJEgAAAA==.Unholygirl:BAAALgAECgEJAQAAAA==.',
Ut='Utterchaos:BAAALgAECgQJCwAAAA==.',
Va='Vaporeon:BAAALgAECgEJAQAAAA==.',
Vi='Victreebel:BAAALgAECgYJDQAAAA==.',
We='Wekko:BAAALgADCgUJBQAAAA==.Wendys:BAABLgAECn8oAAILAAkJ6xbMUgA/AgALAAkJ6xbMUgA/AgAAAA==.Wetheals:BAAALgAECgMJBgAAAA==.',
Wh='Whitemonster:BAAALgADCggJDQAAAA==.',
Wi='Wickedhunter:BAAALgADCgYJBgAAAA==.Wimpykid:BAAALgADCggJCAAAAA==.Winar:BAABLgAECn8hAAILAAgJARClXQCFAQALAAgJARClXQCFAQAAAA==.',
Wr='Wraithsdaddy:BAAALgADCgEJAQAAAA==.',
Wt='Wtfdrood:BAAALgAECgQJCQAAAA==.Wtfmate:BAAALgADCgYJCQAAAA==.Wtfmonk:BAACLgAFFH8FAAIcAAMJigtoIAC1AAAcAAMJigtoIAC1AAAuAAQKfyMAAhwACQmdHGcHAMwCABwACQmdHGcHAMwCAAAA.',
Xa='Xaioli:BAABLgAECn8gAAMEAAkJZCV0CAA9AwAEAAkJZCV0CAA9AwAKAAIJwyF/RQCgAAAAAA==.',
Xe='Xemu:BAAALgADCgUJBQAAAA==.Xethani:BAAALgAECgYJDgAAAA==.',
Xo='Xorcopressor:BAAALgAECgIJAgAAAA==.',
Xs='Xsaber:BAAALgADCgkJLAAAAA==.',
Ya='Yazmo:BAACLgAFFH8MAAIFAAQJHCJwEQArAQAFAAQJHCJwEQArAQAuAAQKfzcAAgUACAmuI3QGAKsCAAUACAmuI3QGAKsCAAEuAAQKAQkBAA8AAAAA.',
Yu='Yuuky:BAACLgAFFH8LAAIHAAQJIw38HwAIAQAHAAQJIw38HwAIAQAuAAQKfyMAAgcACAn9GfokACYCAAcACAn9GfokACYCAAAA.',
Za='Zarivia:BAAALgADCgMJAwAAAA==.Zartaz:BAABLgAECn8aAAMeAAgJtQyXHAChAQAeAAgJtQyXHAChAQAgAAEJWgc2HwAoAAAAAA==.',
Ze='Zendrov:BAABLgAECn8bAAIhAAgJ6gTpPwDUAAAhAAgJ6gTpPwDUAAAAAA==.Zenpai:BAAALgAECgEJBgAAAA==.',
Zi='Ziillah:BAAALgAECgEJAQAAAA==.Zinogre:BAABLgAECn8nAAIfAAkJKhTkBgAFAgAfAAkJKhTkBgAFAgAAAA==.',
['Äp']='Äpollo:BAAALgAECgEJBAAAAA==.',
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
