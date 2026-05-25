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

local lookup = {'Warrior-Protection','Warrior-Fury','Shaman-Enhancement','Paladin-Retribution','Warlock-Demonology','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Priest-Holy','Warrior-Arms','Warlock-Destruction','Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','Shaman-Restoration','Paladin-Holy','Druid-Balance','Shaman-Elemental','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Frost','Monk-Windwalker','Hunter-Marksmanship','Paladin-Protection','Priest-Discipline','Hunter-BeastMastery','DemonHunter-Vengeance','DemonHunter-Havoc','Warlock-Affliction','Monk-Brewmaster','Rogue-Subtlety','Monk-Mistweaver','Evoker-Preservation','DeathKnight-Blood','Druid-Feral','Hunter-Survival',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aanaleaa:BAAALgAECgcJEAAAAA==.',
Ab='Abelram:BAAALgADCgUJBQAAAA==.',
Ad='Ad:BAABLgAECn8gAAMBAAkJcB0CBQCuAgABAAkJcB0CBQCuAgACAAUJ+QrBVwDDAAAAAA==.Adellon:BAABLgAFFH8GAAIDAAMJ/hGMCADpAAADAAMJ/hGMCADpAAAAAA==.Adhar:BAAALgAECgEJAQAAAA==.Adrielle:BAABLgAECn8fAAIEAAYJWxuHhgBCAQAEAAYJWxuHhgBCAQAAAA==.',
Ae='Aeiox:BAAALgADCgMJAwAAAA==.Aevelman:BAABLgAECn8pAAIFAAgJCRwcHwBRAgAFAAgJCRwcHwBRAgAAAA==.',
Af='Affinty:BAAALgAECgQJBAABLgAFFAcJFgAGAHkbAA==.',
Ag='Ag:BAAALgAECgQJBQAAAA==.',
Ai='Airphobic:BAAALgAECgQJEAAAAA==.',
Ak='Akakage:BAAALgAECgEJAQABLgAECggJGQAHACoXAA==.Akakaji:BAABLgAECn8ZAAIHAAgJKhcmMgDdAQAHAAgJKhcmMgDdAQAAAA==.Akutoku:BAAALgADCgcJDAAAAA==.',
Al='Aland:BAAALgADCggJEgAAAA==.Alea:BAABLgAECn8cAAIIAAgJMxxsFACSAgAIAAgJMxxsFACSAgAAAA==.Almodiir:BAAALgADCgUJBwAAAA==.Almoraz:BAAALgAECgUJBQAAAA==.',
An='Anachron:BAAALgADCgIJAgAAAA==.Anaki:BAAALgADCgcJDwAAAA==.Annakkin:BAAALgAECgQJBAAAAA==.Anomander:BAABLgAECn8bAAIHAAYJzgvCkgDQAAAHAAYJzgvCkgDQAAAAAA==.Anonymoose:BAAALgADCgQJBAAAAA==.',
Ao='Aol:BAAALgADCgUJBQAAAA==.',
Ar='Ar:BAABLgAECn8VAAIJAAcJfBC1KgBPAQAJAAcJfBC1KgBPAQABLgAECgkJIAABAHAdAA==.Arbiter:BAAALgAECgUJCQAAAA==.Archon:BAABLgAECn8dAAMCAAgJaRseHQDgAQACAAcJ3h0eHQDgAQAKAAQJyRX7MwDFAAAAAA==.Argig:BAAALgADCgcJCAAAAA==.Arienca:BAABLgAECn85AAMLAAkJchBHFgCYAQAFAAkJaAsyTACfAQALAAgJnhBHFgCYAQAAAA==.Arwenn:BAAALgAECgEJAQAAAA==.',
As='Asu:BAAALgAECgYJEwAAAA==.',
At='At:BAABLgAECn8ZAAIMAAYJyhUTqACJAQAMAAYJyhUTqACJAQABLgAECgkJIAABAHAdAA==.',
Au='Aubrey:BAACLgAFFH8NAAIIAAYJpQXzHgAsAQAIAAYJpQXzHgAsAQAuAAQKfxQAAggACQlyCqVSAFwBAAgACQlyCqVSAFwBAAAA.',
Av='Avengion:BAAALgAECgcJDwAAAA==.',
Ba='Balthromaw:BAAALgADCggJDQAAAA==.Barbato:BAAALgADCgYJCQAAAA==.Barbie:BAAALgADCgYJBgAAAA==.',
Be='Beararms:BAAALgADCgcJCAAAAA==.Beav:BAAALgAECgYJBwABLgAFFAUJEwAIAAgbAA==.Beldent:BAAALgAECgQJBwAAAA==.',
Bl='Blazegrave:BAAALgAECgEJAQABLgAECgkJMQAMAJsRAA==.Blazeofglory:BAAALgADCgUJBQABLgAECgYJBgANAAAAAA==.Blazerunner:BAABLgAECn8xAAIMAAkJmxFeQwD2AQAMAAkJmxFeQwD2AQAAAA==.Blazesmasher:BAAALgADCgkJEwABLgAECgkJMQAMAJsRAA==.Blitzkreig:BAABLgAECn8UAAIOAAcJSRj9VAChAQAOAAcJSRj9VAChAQAAAA==.Bluefoot:BAABLgAECn8aAAIPAAYJ/AjOZwDrAAAPAAYJ/AjOZwDrAAAAAA==.Blured:BAABLgAECn8zAAIHAAkJOSRqBAAvAwAHAAkJOSRqBAAvAwAAAA==.',
Bo='Booty:BAABLgAECn8oAAIBAAkJvCJOBQCkAgABAAkJvCJOBQCkAgAAAA==.',
Br='Brightblayde:BAABLgAECn8XAAIEAAcJHw8NjgA1AQAEAAcJHw8NjgA1AQAAAA==.Brynhildre:BAABLgAECn8UAAIQAAcJfgtURABmAQAQAAcJfgtURABmAQABLgAFFAYJDQAIAKUFAA==.',
Bu='Buum:BAAALgAECgcJEAAAAA==.',
By='Byane:BAAALgADCgYJBgAAAA==.',
Ca='Cachelyn:BAAALgAECgQJBAAAAA==.Cali:BAACLgAFFH8fAAIHAAcJoB0ECQAZAgAHAAcJoB0ECQAZAgAuAAQKfywAAgcACAmkIeQSAOgCAAcACAmkIeQSAOgCAAAA.Cantouchthes:BAABLgAECn8UAAIMAAgJZB5sNwAeAgAMAAgJZB5sNwAeAgAAAA==.Captnage:BAAALgADCggJCAAAAA==.',
Ce='Cederred:BAAALgAECgUJBQABLgAECggJCgANAAAAAA==.Cedertree:BAAALgADCgcJBwABLgAECggJCgANAAAAAA==.Celline:BAAALgADCgEJAQAAAA==.Cephus:BAABLgAFFH8NAAIIAAYJjBYeDQDMAQAIAAYJjBYeDQDMAQAAAA==.Cerafina:BAAALgADCgEJAQAAAA==.',
Ch='Chayse:BAAALgAFFAEJAQABLgAFFAYJDQAIAKUFAA==.Choom:BAABLgAECn8fAAMIAAkJuhUONgDQAQAIAAkJuhUONgDQAQARAAYJjRPrLgCOAQAAAA==.Chorizo:BAAALgADCgEJAQAAAA==.Christhina:BAAALgADCgQJBAAAAA==.Chronocide:BAACLgAFFH8FAAISAAIJLhpULQCkAAASAAIJLhpULQCkAAAuAAQKfyoAAhIACQnbHxEQAKkCABIACQnbHxEQAKkCAAAA.Chronophasia:BAAALgAECggJCAAAAA==.Chroños:BAABLgAECn8UAAMTAAcJEA/nOQAdAQATAAcJ6g3nOQAdAQAUAAQJZw7TEADZAAAAAA==.Chumléé:BAAALgADCgQJBAAAAA==.Chérry:BAACLgAFFH8aAAIHAAYJJhvUFQChAQAHAAYJJhvUFQChAQAuAAQKfx4AAgcACAnpI4wQAPoCAAcACAnpI4wQAPoCAAAA.',
Cl='Climpwimp:BAAALgAECgEJAQAAAA==.Cluntasaur:BAAALgAECgUJBgAAAA==.',
Co='Connerr:BAABLgAECn8aAAIIAAgJtBqnKQDlAQAIAAgJtBqnKQDlAQAAAA==.Cowage:BAAALgAECgQJCQAAAA==.',
Cr='Crisse:BAAALgAECgUJCgAAAA==.Croh:BAABLgAECn8aAAMOAAgJpBNfVAD0AQAOAAgJpBNfVAD0AQAVAAQJawb3DwCcAAAAAA==.Crucks:BAAALgADCgQJBAAAAA==.Cruknar:BAAALgAFFAEJAQAAAA==.',
Cu='Curita:BAAALgADCgEJAQAAAA==.',
Cy='Cynestra:BAAALgAECgcJEAAAAA==.',
Da='Dadudadu:BAACLgAFFH8SAAIEAAYJXA6WDgA1AQAEAAYJXA6WDgA1AQAuAAQKfzQAAgQACQkZIHoWAOICAAQACQkZIHoWAOICAAAA.Daffo:BAAALgAECgIJAQAAAA==.Daftmonk:BAACLgAFFH8fAAIWAAYJVyVkAQAeAgAWAAYJVyVkAQAeAgAuAAQKfywAAhYACQmSJbECAG8DABYACQmSJbECAG8DAAAA.Daitanfuteki:BAAALgADCgEJAQABLgAFFAQJCAAXAOcVAA==.Darkfyre:BAAALgADCgEJAgAAAA==.Darks:BAAALgAECgIJAgAAAA==.Darkwingfish:BAABLgAECn8pAAIHAAkJrRSeOADDAQAHAAkJrRSeOADDAQAAAA==.Dartran:BAAALgADCgIJBwAAAA==.Dasarus:BAAALgAECgUJCwAAAA==.Dayman:BAABLgAECn8UAAMYAAcJgwJeKwCVAAAYAAcJXAJeKwCVAAAEAAYJ0gEcEwFsAAAAAA==.',
De='Deadmedic:BAAALgAECgQJBAABLgAECgcJIgAZAJUQAA==.Decày:BAAALgAECgcJEAAAAA==.Demoteck:BAAALgAECgQJBgAAAA==.Deredris:BAAALgAECgEJAQAAAA==.Deth:BAAALgAECgIJAgABLgAECgMJDAANAAAAAA==.Dethblow:BAAALgAECgMJDAAAAA==.',
Di='Disconnects:BAAALgADCgUJBQAAAA==.Dium:BAAALgAECgEJAQAAAA==.Diwa:BAACLgAFFH8FAAIPAAUJ5QHZJwAKAQAPAAUJ5QHZJwAKAQAuAAQKfxkAAw8ACQn8BgpaABkBAA8ACQn8BgpaABkBABIABglJB+BRAP8AAAAA.',
Dk='Dklot:BAABLgAECn8YAAMOAAcJWRzUZAB6AQAOAAcJWRzUZAB6AQAVAAEJ9QwQKwAwAAAAAA==.',
Dr='Dragolot:BAAALgADCgQJBAABLgAECgcJGAAOAFkcAA==.Draken:BAAALgAECgEJAQAAAA==.Draviin:BAABLgAECn8wAAIaAAkJ9x0eFgB6AgAaAAkJ9x0eFgB6AgAAAA==.',
Du='Duckcheese:BAAALgADCgEJAQAAAA==.Dunkyn:BAAALgAECgMJBgAAAA==.Durzoblint:BAAALgAECgUJCAAAAA==.',
Dy='Dyemon:BAAALgADCgIJAgAAAA==.',
['Dé']='Déad:BAAALgADCgcJDAAAAA==.',
El='Elementz:BAAALgAECgIJAgAAAA==.Elerae:BAABLgAECn8nAAIEAAkJ+hthFgDjAgAEAAkJ+hthFgDjAgAAAA==.Eleshkigal:BAABLgAECn8oAAMHAAkJ1yaKAwCTAwAHAAkJ1yaKAwCTAwAbAAQJiBoaDwAwAQAAAA==.',
En='Enkeke:BAABLgAECn85AAIOAAkJTR0NIABmAgAOAAkJTR0NIABmAgAAAA==.',
Er='Eresanna:BAABLgAFFH8GAAIMAAQJ/wbiVQAZAQAMAAQJ/wbiVQAZAQAAAA==.Ereshkigal:BAAALgAECgUJBgAAAA==.',
Es='Esdeath:BAAALgAECgQJCAABLgAFFAYJCQAcAMsQAA==.Estus:BAABLgAECn8VAAMQAAgJNheNIwDCAQAQAAgJNheNIwDCAQAEAAIJ1gkSQQFAAAAAAA==.',
Ex='Extremefear:BAABLgAECn8qAAMLAAgJ+RbIEQD9AAAFAAQJRRWZiwANAQALAAYJDBXIEQD9AAAAAA==.',
Fa='Fatima:BAAALgAECgIJAwAAAA==.',
Fe='Fearious:BAACLgAFFH8TAAMFAAUJVSX1GACaAQAFAAUJxiT1GACaAQAdAAEJYSb0CwBsAAAuAAQKfx8AAwUACAnPJdQrAF8CAAUABwn9I9QrAF8CAAsAAgkmJFQ3ANgAAAAA.Felphetamine:BAAALgADCggJCAAAAA==.Fenrisfangs:BAABLgAECn8VAAIaAAkJSA6xQQCxAQAaAAkJSA6xQQCxAQAAAA==.Fenrisul:BAAALgAECgUJBQAAAA==.Feralshunter:BAACLgAFFH8IAAIXAAQJ5xUUDwAlAQAXAAQJ5xUUDwAlAQAuAAQKfzIAAhcACQkAIZcQALcCABcACQkAIZcQALcCAAAA.Feroond:BAAALgADCgQJBAAAAA==.',
Fi='Fingeritout:BAAALgADCgIJAgAAAA==.Firefly:BAAALgAECgMJAwAAAA==.',
Fl='Florea:BAAALgADCggJDAAAAA==.',
Fo='Forfoxsake:BAABLgAECn8kAAIeAAgJmR+mDgAxAgAeAAgJmR+mDgAxAgAAAA==.',
Fr='Frogteeth:BAAALgADCgUJBQAAAA==.',
Fu='Furibeav:BAABLgAFFH8TAAIIAAUJCBtUEACmAQAIAAUJCBtUEACmAQAAAA==.Furrów:BAAALgAECgEJAQAAAA==.',
['Fû']='Fûrrow:BAAALgAECgEJAwAAAA==.',
Ga='Gallindral:BAABLgAECn88AAIHAAkJah1aEACkAgAHAAkJah1aEACkAgAAAA==.Garanda:BAAALgAECgQJBQAAAA==.Gatito:BAAALgADCgEJAQABLgAECgIJAgANAAAAAA==.Gauthus:BAAALgAECgkJCQAAAA==.',
Ge='Genericnpc:BAAALgAECgcJDgAAAA==.Geobrando:BAABLgAECn84AAMPAAkJTiBtCwDHAgAPAAkJTiBtCwDHAgASAAYJmQ/WVgCwAAAAAA==.',
Gg='Ggbrews:BAACLgAFFH8YAAIEAAUJACDlHQBcAQAEAAUJACDlHQBcAQAuAAQKf34ABAQACQmqJacDAFEDAAQACQmqJacDAFEDABAACAnDGQAVAD8CABgABgmcCKQoAKUAAAAA.',
Gh='Ghostblaze:BAAALgAECgUJDAABLgAECgkJMQAMAJsRAA==.',
Gi='Gier:BAAALgADCgUJBQAAAA==.Gino:BAAALgADCgEJAQAAAA==.',
Gl='Glacious:BAAALgADCgEJAQAAAA==.Glasswings:BAAALgAECgIJAgAAAA==.',
Gn='Gnosh:BAAALgAECgcJEwAAAA==.Gnova:BAABLgAECn8jAAIMAAYJfSEWVADDAQAMAAYJfSEWVADDAQAAAA==.',
Go='Gorian:BAAALgAECgcJCAAAAA==.',
Gr='Gregorz:BAAALgADCgEJAQAAAA==.Grish:BAAALgADCgcJGAAAAA==.',
Gu='Guidosarduci:BAABLgAECn8iAAIPAAgJhhdgHAA2AgAPAAgJhhdgHAA2AgAAAA==.',
Ha='Hairia:BAAALgADCgUJBQAAAA==.Halen:BAAALgADCgcJBwABLgAFFAcJHwAHAKAdAA==.Harle:BAABLgAECn8UAAIMAAcJGhMjbACGAQAMAAcJGhMjbACGAQAAAA==.Hatari:BAAALgAECgMJAwAAAA==.',
He='Hektate:BAABLgAECn8WAAIMAAcJXQuxlwAuAQAMAAcJXQuxlwAuAQABLgAFFAYJEgAEAFwOAA==.Henryjones:BAAALgADCgEJAQAAAA==.',
Hi='Hikari:BAABLgAECn8WAAIEAAgJZiECIABpAgAEAAgJZiECIABpAgABLgAFFAYJIQASAKIaAA==.Hilkesad:BAAALgAECgQJBAAAAA==.Hizo:BAAALgADCgUJBQAAAA==.',
Ho='Holybeave:BAABLgAECn8eAAMJAAkJNB3/DACFAgAZAAkJaBi5CQCfAgAJAAgJqx7/DACFAgABLgAFFAUJEwAIAAgbAA==.Holyshortguy:BAAALgAECgQJCAAAAA==.Hoofer:BAAALgAECgYJDgAAAA==.',
Hu='Hunkomeat:BAABLgAECn8XAAICAAgJLhzkLAAAAgACAAgJLhzkLAAAAgAAAA==.',
['Hë']='Hënry:BAAALgAECgEJAQAAAA==.',
Ic='Icelmo:BAABLgAFFH8JAAICAAQJbBNUGAAtAQACAAQJbBNUGAAtAQAAAA==.',
Ih='Ihotyou:BAAALgADCgQJBwAAAA==.',
In='Inai:BAAALgADCgcJDAABLgAFFAYJCQAcAMsQAA==.Invizww:BAAALgAECgQJBQAAAA==.',
Ir='Ircapslock:BAAALgAECgYJCwAAAA==.',
Iv='Ivorypal:BAABLgAECn8gAAIQAAgJqR/dEACLAgAQAAgJqR/dEACLAgAAAA==.',
Ja='Jacksock:BAAALgADCgEJAQAAAA==.Jamzz:BAAALgADCgYJEAABLgAFFAYJFgAXAL0RAA==.Jaromir:BAAALgADCgcJBwAAAA==.Jaskow:BAABLgAECn8uAAIIAAkJjiAxBgA8AwAIAAkJjiAxBgA8AwAAAA==.Jaymick:BAAALgAECgcJEwAAAA==.',
Jb='Jbizzler:BAAALgAECgcJBgAAAA==.',
Jc='Jcrypt:BAAALgAECgcJAgAAAA==.',
Je='Jennika:BAAALgAFFAEJAQAAAA==.Jernau:BAAALgAECgEJAQAAAA==.Jessortess:BAAALgAECgQJBwAAAA==.',
Jo='Johnwicksdog:BAAALgAECggJEQAAAA==.Jorbies:BAAALgAECgYJCQABLgAFFAcJFgAGAHkbAA==.Jorls:BAACLgAFFH8WAAMGAAcJeRtMAgDeAQAGAAcJeRtMAgDeAQAZAAEJWAEnGwBDAAAuAAQKfxsABAYACQkFHlMIAP8CAAYACQkFHlMIAP8CABkABAnSCc08AMQAAAkAAglAAgl2AFEAAAAA.',
Ju='Junatooka:BAAALgAECgIJAgAAAA==.Jusdatip:BAAALgAECgUJDQAAAA==.',
Ka='Kaelthazed:BAAALgADCgEJAQABLgAECgkJNAAFAG4hAA==.Kalfu:BAABLgAECn8XAAMaAAgJ0B0CLQD/AQAaAAgJ0B0CLQD/AQAXAAYJoBUDOgB5AQAAAA==.Kameshoga:BAAALgAECgIJAgAAAA==.Kammwin:BAAALgAECgYJEwAAAA==.Karten:BAAALgAECgQJBwAAAA==.Kaylea:BAAALgADCgIJAgAAAA==.',
Ke='Kellandria:BAAALgADCgYJBgAAAA==.',
Ki='Kittêh:BAAALgAECgEJAQAAAA==.',
Kn='Knathor:BAAALgAECgQJBAABLgAECgcJDgANAAAAAA==.',
Ko='Korec:BAAALgAECgcJDgAAAA==.',
Kr='Krasis:BAABLgAECn8XAAIEAAkJvhrLWADYAQAEAAkJvhrLWADYAQAAAA==.Krazermonk:BAACLgAFFH8IAAIWAAMJgRd1FwDiAAAWAAMJgRd1FwDiAAAuAAQKfygAAhYACQmlHkkLAGoCABYACQmlHkkLAGoCAAAA.Kristysavage:BAABLgAECn8pAAIaAAkJYiNpBAAuAwAaAAkJYiNpBAAuAwAAAA==.Kroflavinof:BAAALgAECgQJBQAAAA==.',
Ku='Kurosakí:BAAALgAECgEJAQAAAA==.',
La='Lanc:BAAALgAECgQJCQAAAA==.Lappytopdog:BAAALgADCgUJBQAAAA==.Larradin:BAAALgADCggJEAAAAA==.Lawnchair:BAAALgAECggJCQAAAA==.',
Le='Lealta:BAAALgAFFAEJAQAAAA==.Leonus:BAAALgAECgQJCQAAAA==.Leviathahn:BAAALgAECgEJAgAAAA==.',
Lh='Lhegholhaz:BAAALgADCgIJAgAAAA==.',
Li='Lichdawg:BAACLgAFFH8PAAIVAAQJ3ROGBwA3AQAVAAQJ3ROGBwA3AQAuAAQKfxQAAhUACAnSE7AKAIsBABUACAnSE7AKAIsBAAAA.Lilzayna:BAAALgADCgIJAgABLgAECgUJBgANAAAAAA==.Linthori:BAEALgADCgMJAwABLgAECgcJDQANAAAAAA==.Lithlia:BAAALgADCgcJBwAAAA==.Livvela:BAABLgAECn8iAAIfAAkJoBSlFADWAQAfAAkJoBSlFADWAQAAAA==.',
Ll='Llas:BAAALgADCgIJAgAAAA==.',
Lo='Lockdawg:BAACLgAFFH8XAAIFAAYJ7hA9IgB2AQAFAAYJ7hA9IgB2AQAuAAQKfyYAAwUACAmFHRImAHoCAAUACAmFHRImAHoCAAsAAQnWFc1sADoAAAAA.Lockedin:BAAALgAECgkJEgAAAA==.Lonne:BAAALgAECgYJDgABLgAFFAIJBAANAAAAAA==.Lover:BAABLgAECn8jAAIJAAkJNR54CQCtAgAJAAkJNR54CQCtAgAAAA==.',
Lu='Lubu:BAACLgAFFH8JAAIcAAYJyxC3BACBAQAcAAYJyxC3BACBAQAuAAQKfxoAAhwACQn+HzoDAP4CABwACQn+HzoDAP4CAAAA.Lucianis:BAAALgADCgQJBwAAAA==.Luckycharmz:BAAALgAECgQJCQABLgAECgcJIgAZAJUQAA==.Luckywar:BAAALgADCgYJBgAAAA==.Luell:BAAALgAECgcJDwAAAA==.Luev:BAAALgAECgYJCAAAAA==.Lumiette:BAAALgAECgcJCwAAAA==.',
Ly='Lynai:BAAALgAECgUJEAAAAA==.',
['Lá']='Lándwhale:BAACLgAFFH8RAAIfAAQJISNNDQBtAQAfAAQJISNNDQBtAQAuAAQKfy4AAh8ACQmTJMsCAAsDAB8ACQmTJMsCAAsDAAAA.',
['Lö']='Löver:BAAALgAECgcJBwAAAA==.',
Ma='Mabil:BAABLgAECn8UAAQFAAcJRhKNhgAXAQAFAAYJew2NhgAXAQAdAAQJXRWcGAC2AAALAAIJNAzMNwArAAAAAA==.Macktimus:BAABLgAECn8dAAILAAkJGBilAwAtAgALAAkJGBilAwAtAgAAAA==.Mage:BAAALgAFFAEJAgAAAA==.Magictonyp:BAAALgAECgEJAQAAAA==.Magicznstuff:BAAALgAECgEJAQABLgAECgMJBgANAAAAAA==.Magna:BAABLgAECn8lAAICAAkJYRItIADJAQACAAkJYRItIADJAQAAAA==.Makili:BAABLgAFFH8HAAIMAAQJZwjmWgAHAQAMAAQJZwjmWgAHAQAAAA==.Maladrix:BAAALgAECgQJDQAAAA==.Mauê:BAAALgADCgEJAQABLgAECgIJAgANAAAAAA==.',
Mc='Mchunter:BAAALgAECgMJAwAAAA==.Mcshadow:BAAALgADCgIJAgAAAA==.',
Me='Menphina:BAAALgAECgIJAgAAAA==.Merigold:BAAALgAECgEJAQABLgAECgQJBAANAAAAAA==.',
Mi='Minnow:BAAALgAECgYJDgAAAA==.Mintchip:BAABLgAECn8QAAIHAAcJ3ReDPwCpAQAHAAcJ3ReDPwCpAQAAAA==.',
Mo='Monk:BAAALgAECgEJAQAAAA==.Monza:BAAALgADCgEJAQABLgAECgkJKAAMAOsWAA==.Moontini:BAAALgADCgYJBgABLgAECgQJDQANAAAAAA==.Mordryn:BAAALgADCgcJBwAAAA==.',
My='Mysternia:BAAALgAECgYJDgAAAA==.Myyagie:BAAALgADCgUJDAAAAA==.',
Na='Nalthexon:BAABLgAECn8qAAMgAAgJ2wtFMQAzAQAgAAgJ2wtFMQAzAQAWAAEJXQZcjwAoAAABLgAFFAMJBgAIAHUGAA==.Natureborne:BAAALgAECgYJCQAAAA==.',
Ne='Nedrud:BAAALgADCgUJCAAAAA==.Nelson:BAEALgAECgYJBgABLgAECggJJQAMANcbAA==.Nenno:BAAALgADCgEJAQAAAA==.Netzhul:BAAALgAFFAEJAQAAAA==.',
Ni='Night:BAAALgAECgcJEQAAAA==.Nikalos:BAAALgAECgYJDQAAAA==.Nikole:BAAALgAECgMJAwAAAA==.',
No='Noon:BAAALgADCgUJBQABLgAECggJFQAQADYXAA==.Notorckrag:BAABLgAECn84AAIeAAkJEyPgAgATAwAeAAkJEyPgAgATAwAAAA==.Nozomi:BAAALgAECgIJAgAAAA==.',
Nu='Nut:BAAALgADCgQJBAAAAA==.',
['Nê']='Nêz:BAAALgAECgUJCAAAAA==.',
Oa='Oathbringer:BAAALgAECgQJBAAAAA==.',
Ob='Oblivionz:BAAALgAECgMJAwAAAA==.',
Oc='Ocho:BAAALgADCgYJCQAAAA==.',
Of='Offbrandcleo:BAAALgAECgkJBgAAAA==.',
Ok='Okibi:BAAALgAECgMJAwABLgAFFAYJCQAcAMsQAA==.',
Ol='Oldrecipe:BAABLgAFFH8FAAIQAAMJARRyJQDIAAAQAAMJARRyJQDIAAAAAA==.Oliange:BAABLgAECn8cAAIMAAgJAAvBgABZAQAMAAgJAAvBgABZAQAAAA==.',
Or='Ori:BAEALgADCgcJCwABLgAECgcJDQANAAAAAA==.Originalgank:BAAALgAFFAEJAQAAAA==.',
Pa='Papanell:BAAALgADCgYJCQAAAA==.',
Pe='Peachcobbler:BAAALgAECggJDgAAAA==.Perc:BAAALgAECgQJBAAAAA==.',
Ph='Philsner:BAEALgAECgcJDQAAAA==.Phink:BAAALgAECgQJCgAAAA==.',
Pi='Pinkk:BAAALgAFFAEJAgAAAA==.',
Pl='Plushie:BAABLgAECn8WAAIGAAcJ7wl8MwAjAQAGAAcJ7wl8MwAjAQAAAA==.',
Po='Pong:BAAALgAECgQJBQABLgAECggJKAAhAC4SAA==.Pooqy:BAACLgAFFH8QAAMOAAUJ4SRlGgCnAQAOAAQJ4SRlGgCnAQAiAAEJAAAuNQAAAAAuAAQKfxYAAg4ACAlWIrskAKsCAA4ACAlWIrskAKsCAAAA.Porcel:BAAALgADCgcJCwAAAA==.Potatoteng:BAAALgAFFAEJAQABLgAFFAUJDQAEADYZAA==.',
Pr='Pritej:BAAALgAECgYJCgABLgAFFAIJBAANAAAAAA==.Proto:BAAALgAECgcJDAAAAA==.',
Pu='Puck:BAAALgAECgIJCAABLgAFFAYJCQAcAMsQAA==.',
Py='Pyraleus:BAAALgADCgQJBAAAAA==.',
Qu='Quickchicken:BAAALgADCgYJBgAAAA==.',
Ra='Ragel:BAABLgAECn8sAAIRAAgJRB82DABtAgARAAgJRB82DABtAgAAAA==.Rainesage:BAABLgAECn8mAAMGAAgJAhr1FQD2AQAGAAgJAhr1FQD2AQAJAAEJxwf6ZgAnAAAAAA==.Ralphel:BAABLgAECn8fAAIEAAcJZwYtrwD+AAAEAAcJZwYtrwD+AAAAAA==.Rasu:BAAALgADCgcJBwABLgAECggJGgAhALUMAA==.Ravendark:BAAALgAECgEJAQAAAA==.Rayozap:BAAALgAECgUJBgAAAA==.',
Re='Redeye:BAAALgADCgMJAwAAAA==.',
Rh='Rhondaa:BAAALgAECgYJEQAAAA==.Rhubarb:BAABLgAECn89AAMKAAkJjiahAABtAwAKAAgJIiahAABtAwACAAgJoySoCQCnAgAAAA==.',
Ri='Riyci:BAAALgAECgEJAQAAAA==.',
Ro='Rohiem:BAABLgAECn81AAICAAkJpBgcEwA2AgACAAkJpBgcEwA2AgAAAA==.',
Ry='Ryan:BAABLgAECn8eAAIEAAkJZR4ZHADBAgAEAAkJZR4ZHADBAgAAAA==.Rylorthas:BAACLgAFFH8dAAIJAAYJThYmBgCvAQAJAAYJThYmBgCvAQAuAAQKfy0AAgkACQl8HMsSAEoCAAkACQl8HMsSAEoCAAAA.Rylosh:BAAALgADCgYJBgABLgAFFAYJHQAJAE4WAA==.',
Sa='Sabot:BAAALgAECgcJEwAAAA==.Sabrook:BAAALgADCggJCAAAAA==.Salazar:BAAALgAECgEJAwAAAA==.Sam:BAAALgAECgUJBAAAAA==.Satisfied:BAAALgAECgQJEAAAAA==.',
Sc='Scottmonk:BAAALgAECgIJBAAAAA==.Scottpaladin:BAAALgAECgEJAQABLgAECgIJBAANAAAAAA==.',
Se='Sentaí:BAAALgAECgIJBAAAAA==.',
Sh='Shamerica:BAACLgAFFH8VAAIDAAYJBSIQAQDKAQADAAYJBSIQAQDKAQAuAAQKfzMAAwMACQn2Ig0BACIDAAMACQn2Ig0BACIDABIABAlTHVc/AE0BAAAA.Shizuku:BAAALgADCgUJBQAAAA==.Shmooythefox:BAABLgAECn8iAAIaAAcJYyECKgAMAgAaAAcJYyECKgAMAgAAAA==.Shokan:BAAALgADCgQJBAAAAA==.Shortleedin:BAAALgAECgIJAQAAAA==.Shòckwave:BAAALgADCgQJBAAAAA==.',
Si='Sinrex:BAAALgADCgIJAgAAAA==.Sixstar:BAAALgADCgEJAQAAAA==.',
Sk='Skrt:BAAALgADCgkJEgAAAA==.Skyleax:BAACLgAFFH8KAAMOAAQJdg1MVwAgAQAOAAQJdg1MVwAgAQAVAAEJwAJ/GwA3AAAuAAQKfxgABA4ACQkSIEYuAH8CAA4ACQnoHEYuAH8CABUABAkVHkUMAPAAACIAAQn7D0ZLACAAAAAA.',
Sl='Slagothor:BAABLgAECn8VAAIOAAkJywRnmQBNAQAOAAkJywRnmQBNAQAAAA==.Slanesh:BAAALgADCgcJBwABLgAECgcJEAAHAN0XAA==.Sleaze:BAAALgADCgEJAQAAAA==.Sleazus:BAAALgAECgMJAwAAAA==.',
Sm='Smeesha:BAABLgAECn8fAAQhAAgJwhUEDgDKAQAhAAcJgxYEDgDKAQAUAAYJRQcGJgDzAAATAAYJ1wahRgDBAAAAAA==.',
Sn='Snaxwell:BAAALgADCgEJAQAAAA==.',
So='Somin:BAAALgAECgMJBAAAAA==.',
Sp='Spekaleks:BAAALgADCgUJBwAAAA==.',
Sq='Squitwurt:BAAALgADCgYJBgAAAA==.',
St='Starbux:BAAALgAECgMJBAAAAA==.Starbúcks:BAAALgAECgIJAwABLgAECgcJIgAZAJUQAA==.Steppers:BAAALgAECgUJAgAAAA==.Straamm:BAAALgADCgMJAwAAAA==.',
Su='Sugarr:BAAALgADCgMJAwAAAA==.Sunfish:BAAALgAECgYJBgAAAA==.',
Sv='Svelana:BAABLgAECn8gAAMWAAgJwSF6DQCkAgAWAAgJwSF6DQCkAgAgAAEJCguFjgAlAAAAAA==.',
Sy='Syb:BAABLgAECn8UAAMTAAcJQBXqJwCCAQATAAcJQBXqJwCCAQAhAAEJFwU3SwArAAAAAA==.Sylphrena:BAACLgAFFH8MAAIGAAQJvRvCDgBRAQAGAAQJvRvCDgBRAQAuAAQKfykAAgYACQnSIqEEAPYCAAYACQnSIqEEAPYCAAAA.Syssana:BAAALgAECgIJBgAAAA==.',
Ta='Tadaa:BAAALgADCgIJAgAAAA==.Tamerlein:BAAALgAECgEJAwAAAA==.Tamioka:BAAALgAECgYJCAAAAA==.Tanookii:BAAALgAECgYJEwAAAA==.',
Te='Telafar:BAAALgAECgkJAwAAAA==.',
Th='Theinsider:BAABLgAECn80AAMFAAkJbiGLDAAWAwAFAAkJbiGLDAAWAwALAAUJkA+nKwARAQAAAA==.Thenezath:BAAALgADCgQJBAAAAA==.Theoutsider:BAAALgAECgYJCAABLgAECgkJNAAFAG4hAA==.Thunrus:BAAALgADCgYJBgAAAA==.',
Ti='Tibbles:BAAALgAECgcJCAAAAA==.Tigerbait:BAAALgAECgYJEQAAAA==.Tindril:BAAALgAECgYJBwAAAA==.Tinymo:BAAALgAECgMJAwAAAA==.',
To='Toji:BAABLgAECn8VAAIGAAcJ+hiQGwDCAQAGAAcJ+hiQGwDCAQABLgAFFAYJIQASAKIaAA==.Tomatoteng:BAACLgAFFH8NAAIEAAUJNhnvIwBKAQAEAAUJNhnvIwBKAQAuAAQKfyAAAgQACQmPJH4DAJsDAAQACQmPJH4DAJsDAAAA.Totegoat:BAAALgADCgEJAQAAAA==.Totemmalotes:BAAALgADCgcJBwAAAA==.Totemofbear:BAABLgAECn8WAAIjAAgJvg18EwBMAQAjAAgJvg18EwBMAQAAAA==.',
Tr='Trandis:BAAALgADCgMJBAABLgAECgkJKAAHANcmAA==.Tranza:BAABLgAECn8cAAQkAAgJOw33HQCOAQAkAAgJcgr3HQCOAQAaAAYJXwvhfgDrAAAXAAYJzAZBWADlAAAAAA==.Treesus:BAAALgADCgcJBwABLgAECgkJKAABALwiAA==.Trinshunter:BAABLgAECn8oAAQaAAgJHxj7NwDTAQAaAAgJHxj7NwDTAQAkAAEJ6gnELwA0AAAXAAEJ4gEnmgAZAAABLgAFFAQJEAAEAOUOAA==.',
Tx='Tx:BAACLgAFFH8hAAISAAYJohr8CQCkAQASAAYJohr8CQCkAQAuAAQKfywAAhIACAmNIUcQAKcCABIACAmNIUcQAKcCAAAA.',
Ty='Tyedye:BAAALgAECgEJAQAAAA==.',
['Tí']='Tíbs:BAAALgAECgYJCwAAAA==.',
Un='Unbound:BAAALgADCgcJEgAAAA==.Unholygirl:BAAALgAECgEJAQAAAA==.',
Ut='Utterchaos:BAAALgAECgUJDwAAAA==.',
Va='Vaporeon:BAAALgAECgEJAQAAAA==.',
Vi='Victreebel:BAAALgAECgYJDQAAAA==.',
Vo='Volg:BAAALgAECgQJBAAAAA==.',
We='Wekko:BAAALgADCgUJBQAAAA==.Wendys:BAABLgAECn8oAAIMAAkJ6xbMUgA/AgAMAAkJ6xbMUgA/AgAAAA==.Wetheals:BAAALgAECgMJBgAAAA==.',
Wh='Whitemonster:BAAALgADCggJDQAAAA==.',
Wi='Wickedhunter:BAAALgADCgYJBgAAAA==.Wimpykid:BAAALgADCggJCAAAAA==.Winar:BAABLgAECn8hAAIMAAgJAhBubACFAQAMAAgJAhBubACFAQAAAA==.',
Wo='Worgnfreeman:BAABLgAECn8VAAMOAAcJ0gm+kwAZAQAOAAcJ+wi+kwAZAQAVAAcJIQaOGADEAAAAAA==.',
Wr='Wraithsdaddy:BAAALgADCgEJAQAAAA==.',
Wt='Wtfdrood:BAAALgAECgQJCQAAAA==.Wtfmate:BAAALgADCgYJCQAAAA==.Wtfmonk:BAACLgAFFH8GAAIgAAMJigtBKgCpAAAgAAMJigtBKgCpAAAuAAQKfygAAiAACQn+HF4JAM8CACAACQn+HF4JAM8CAAAA.',
Xa='Xaioli:BAABLgAECn8gAAMFAAkJaSV0CAA9AwAFAAkJaSV0CAA9AwALAAIJwyF/RQCgAAAAAA==.',
Xe='Xemu:BAAALgADCgUJBQAAAA==.Xethani:BAABLgAECn8UAAIbAAcJkhG5DABcAQAbAAcJkhG5DABcAQAAAA==.',
Xo='Xorcopressor:BAAALgAECgIJAgAAAA==.',
Xs='Xsaber:BAAALgAECgIJAgAAAA==.',
Ya='Yazmo:BAACLgAFFH8MAAIGAAQJHCKlFQAdAQAGAAQJHCKlFQAdAQAuAAQKfzcAAgYACAmwI80IAKECAAYACAmwI80IAKECAAEuAAUUAQkBAA0AAAAA.',
Yu='Yuuky:BAACLgAFFH8PAAIIAAQJ1RKYIQAcAQAIAAQJ1RKYIQAcAQAuAAQKfywAAggACQl2GyMTAJECAAgACQl2GyMTAJECAAAA.',
Za='Zarivia:BAAALgADCgMJAwAAAA==.Zartaz:BAABLgAECn8aAAMhAAgJtQyXHAChAQAhAAgJtQyXHAChAQAUAAEJWgdvIwAoAAAAAA==.',
Ze='Zendrov:BAABLgAECn8dAAITAAgJqwW3SADeAAATAAgJqwW3SADeAAAAAA==.Zenpai:BAAALgAECgEJBgAAAA==.',
Zi='Ziillah:BAAALgAECgIJAgAAAA==.Zinogre:BAABLgAECn8vAAIDAAkJDxV5CAAJAgADAAkJDxV5CAAJAgAAAA==.',
['Äp']='Äpollo:BAAALgAECgMJBgAAAA==.',
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
