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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Druid-Restoration','Shaman-Restoration','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Shaman-Enhancement','Hunter-BeastMastery','Warrior-Protection','Shaman-Elemental','Unknown-Unknown','Evoker-Augmentation','Paladin-Protection','Paladin-Retribution','Paladin-Holy','DeathKnight-Frost','Mage-Frost','Warrior-Arms','Warrior-Fury','Evoker-Preservation','Priest-Shadow','DemonHunter-Devourer','DeathKnight-Blood','Mage-Fire','Monk-Brewmaster','Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','Monk-Mistweaver','Druid-Guardian','Evoker-Devastation','Druid-Balance','Druid-Feral','Mage-Arcane','Rogue-Outlaw',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aabbigale:BAAALgAECgkJBwAAAA==.',
Ab='Abigt:BAABLgAECn8YAAMBAAcJDiAGCADrAQABAAcJDiAGCADrAQACAAQJexGexQDOAAAAAA==.',
Ad='Adalaidê:BAAALgAECgcJEQAAAA==.',
Ae='Aelusion:BAACLgAFFH8GAAICAAMJ3xYKcADiAAACAAMJ3xYKcADiAAAuAAQKfx8ABAIACAlIHzwaALcCAAIACAmBHjwaALcCAAMAAwlaIRUsAA4BAAEAAQlAJCInAFUAAAEuAAUUBQkMAAQAwhUA.Aeluu:BAAALgAECgcJBwABLgAECggJHwAFALgRAA==.Aerola:BAAALgADCgIJAgAAAA==.Aerynne:BAABLgAECn8bAAMCAAYJYAyADACMAAADAAUJOwtXIwCWAAACAAMJlAqADACMAAAAAA==.',
Ai='Aidén:BAAALgAECgEJAQAAAA==.Ailis:BAAALgAECgQJBAAAAA==.Airie:BAABLgAECn8+AAIGAAkJRxNEJgApAgAGAAkJRxNEJgApAgAAAA==.Aita:BAACLgAFFH8XAAIHAAUJAhd2BQASAQAHAAUJAhd2BQASAQAuAAQKfyQAAwcACQnXGO4GAB0CAAcACQnXGO4GAB0CAAgABgnSCpREAKQAAAAA.',
Ak='Akuso:BAAALgADCgYJCAAAAA==.',
Al='Alassa:BAAALgADCgQJBAAAAA==.Alayro:BAAALgAECgcJCQAAAA==.Alejandrø:BAAALgADCgUJBgAAAA==.Alisaa:BAAALgAECgUJCAAAAA==.Alistanë:BAAALgAECgUJCQAAAA==.Allegria:BAAALgAECgEJAgAAAA==.Alluna:BAAALgAECgYJCgAAAA==.Alondra:BAABLgAECn8gAAIDAAkJvB82AgCgAgADAAkJvB82AgCgAgAAAA==.Alulà:BAABLgAECn8gAAMJAAcJbh6nEgBOAgAJAAcJTB6nEgBOAgAKAAMJMx4lTQAEAQAAAA==.Aluucard:BAAALgADCgUJBQAAAA==.Aluuni:BAABLgAECn8mAAILAAkJiBc7CABDAgALAAkJiBc7CABDAgAAAA==.',
Am='Amednato:BAAALgAECgcJDgABLgAECgkJJAAMAKogAA==.Amo:BAAALgAECgIJAgABLgAECggJGAANADkZAA==.',
An='Anaeli:BAABLgAECn9IAAMGAAkJ5h29EgC3AgAGAAkJ5h29EgC3AgAOAAUJ9wjmbgCdAAAAAA==.Anariel:BAAALgADCgUJBQABLgAECgQJBAAPAAAAAA==.Ancalagonn:BAABLgAECn8ZAAIQAAYJDxShAgAgAQAQAAYJDxShAgAgAQABLgAECgkJIwAGAMEPAA==.Androth:BAABLgAECn8oAAMRAAkJnhuvCgAfAgARAAkJnhuvCgAfAgASAAMJpQqEHQGWAAAAAA==.Angelius:BAAALgAECgEJBgAAAA==.Angita:BAAALgAECgYJCQAAAA==.Antipæn:BAACLgAFFH8kAAMTAAUJ7yI8AgDoAQATAAUJ7yI8AgDoAQASAAMJChumaADdAAAuAAQKf00AAxIACQmfJjgBAIYDABIACQmfJjgBAIYDABMABwnIIvcpAOIBAAAA.',
Ap='Apologia:BAABLgAECn87AAISAAkJsCK6DQD3AgASAAkJsCK6DQD3AgAAAA==.',
Aq='Aquaphobic:BAAALgADCgEJAQAAAA==.Aquleynta:BAAALgADCgEJAQAAAA==.',
Ar='Arcainus:BAAALgADCgIJAgAAAA==.Arcanix:BAABLgAECn8UAAIUAAcJxglHGQAKAQAUAAcJxglHGQAKAQAAAA==.Arceé:BAAALgAECgMJBwAAAA==.Archaic:BAABLgAECn85AAIVAAkJvxGcVQDcAQAVAAkJvxGcVQDcAQAAAA==.Ardicelia:BAAALgAECgUJBwAAAA==.Ares:BAACLgAFFH8bAAMWAAgJfSBsBAA/AgAWAAgJfSBsBAA/AgAXAAIJCB71FgCuAAAuAAQKfyEAAxYACAlRJOUBABoDABYACAnfI+UBABoDABcABwlHIjMZAIICAAAA.Argomas:BAAALgAECgUJBQAAAA==.Argomir:BAAALgAECgEJAQAAAA==.Ariellä:BAAALgADCgEJAQAAAA==.Arifault:BAAALgAECgMJAwABLgAECgkJSAAGAOYdAA==.Arilynx:BAABLgAECn8iAAIYAAkJ4AesFwBWAQAYAAkJ4AesFwBWAQAAAA==.Arlynn:BAAALgADCgcJBwAAAA==.Armorgorden:BAABLgAECn9cAAINAAkJUSQ3AAD8AgANAAkJUSQ3AAD8AgAAAA==.Aroviaa:BAABLgAECn9GAAQKAAkJVh5BCADnAgAKAAkJVh5BCADnAgAZAAEJHhGFggA4AAAJAAEJ9gPXhwAjAAAAAA==.Arpmek:BAABLgAECn85AAIaAAkJuhWaBQAjAQAaAAkJuhWaBQAjAQAAAA==.Artemîs:BAAALgAECgQJBAAAAA==.Arydynn:BAAALgADCgIJAgAAAA==.',
As='Ashal:BAABLgAECn8nAAMXAAcJ5A3sRAAyAQAXAAcJ+AvsRAAyAQANAAcJQw22JgD9AAAAAA==.Ashlynne:BAABLgAECn8YAAMNAAgJORkkFwCKAQANAAcJzRokFwCKAQAXAAgJMAtLPABUAQAAAA==.Astrotoad:BAAALgAECgUJCgAAAA==.Astrìd:BAAALgADCgIJAgAAAA==.',
Au='Auntmary:BAAALgADCgYJCAAAAA==.Auramaximus:BAAALgAECgYJBwAAAA==.Aurtt:BAABLgAECn9LAAIbAAkJkBe8EgDkAQAbAAkJkBe8EgDkAQAAAA==.',
Av='Avanel:BAAALgAECgEJAQAAAA==.Avidae:BAAALgADCgcJCAAAAA==.',
Az='Azkadelia:BAAALgAECgEJAQAAAA==.',
Ba='Bageera:BAABLgAECn8vAAIFAAkJWh7HCgAQAwAFAAkJWh7HCgAQAwAAAA==.Bahahaknight:BAABLgAECn9FAAIbAAkJniCCBQDQAgAbAAkJniCCBQDQAgAAAA==.Barccky:BAAALgAECgIJAgAAAA==.Barcy:BAAALgAECgEJAwABLgAECgIJAgAPAAAAAA==.Barnette:BAACLgAFFH8WAAIcAAUJZggiAQDyAAAcAAUJZggiAQDyAAAuAAQKf0oAAhwACQlCGRUCAFYCABwACQlCGRUCAFYCAAAA.Bashdown:BAAALgADCgEJAQAAAA==.Basic:BAAALgADCgEJAQAAAA==.',
Be='Bearmissile:BAAALgAFFAIJAwAAAA==.Bearyy:BAAALgADCgQJBAAAAA==.Belthos:BAABLgAECn87AAISAAkJ4x1iGgCmAgASAAkJ4x1iGgCmAgAAAA==.Benjofamin:BAAALgAECgEJAQAAAA==.Berristan:BAACLgAFFH8LAAITAAMJkg52MgCoAAATAAMJkg52MgCoAAAuAAQKfzAAAxMACQkZGKIMALUCABMACQkZGKIMALUCABIABwnnCLrYAOcAAAAA.Bestwingman:BAAALgAECgEJAQAAAA==.',
Bg='Bgdaddyjupes:BAAALgADCgQJBAAAAA==.',
Bi='Bigdawgsteve:BAAALgAECgIJAgAAAA==.Bigmarv:BAABLgAECn8gAAIOAAgJ6helMwBtAQAOAAgJ6helMwBtAQAAAA==.Bigsam:BAAALgAECgEJAQAAAA==.Bittytigs:BAAALgADCgUJBQAAAA==.',
Bl='Blossom:BAACLgAFFH8MAAIYAAUJww1tFwAfAQAYAAUJww1tFwAfAQAuAAQKfxUAAhgACAmdEY8YAM4BABgACAmdEY8YAM4BAAAA.Bluespruce:BAAALgAECgcJDQAAAA==.Bluewitchpa:BAABLgAECn8UAAISAAUJlwnwEACvAAASAAUJlwnwEACvAAAAAA==.',
Bo='Boomboomkill:BAAALgADCgEJAQAAAA==.Bosc:BAABLgAECn8zAAIbAAkJTx5XBwCmAgAbAAkJTx5XBwCmAgABLgAECggJHQAdAP0SAA==.Boudiicca:BAABLgAECn8nAAIKAAYJWhRKAwA1AQAKAAYJWhRKAwA1AQAAAA==.Boxmasterr:BAABLgAECn88AAMBAAkJaxBOAQBAAQACAAkJFwzsWgCNAQABAAcJsBJOAQBAAQAAAA==.',
Br='Brasmir:BAABLgAECn8gAAIeAAkJSQ1CGwDEAQAeAAkJSQ1CGwDEAQAAAA==.Bremerton:BAAALgAECgYJEQAAAA==.Brianzero:BAAALgAECgEJAQAAAA==.Brino:BAAALgAECgEJAQAAAA==.Brinotriage:BAAALgAECgUJBwAAAA==.',
Bu='Bubblement:BAAALgAFFAUJEwAAAQ==.Bubblemoth:BAAALgAECggJEQABLgAECgkJLQAVAM0WAA==.Bulge:BAABLgAFFH8KAAIVAAMJzw3xLwB6AAAVAAMJzw3xLwB6AAABLgAFFAYJHAAEAKIXAA==.Bulgogi:BAACLgAFFH8cAAIEAAYJohfiOgCEAQAEAAYJohfiOgCEAQAuAAQKfzoAAgQACQnqIaoNAP8CAAQACQnqIaoNAP8CAAAA.Bushalabong:BAAALgAECgMJBAAAAA==.Butherrface:BAAALgAECgQJBAAAAA==.',
Bw='Bwonsmashdi:BAAALgADCgUJBgABLgAECgEJAQAPAAAAAA==.',
['Bì']='Bìjou:BAAALgAECgQJBAABLgAECggJGAANADkZAA==.',
['Bù']='Bùb:BAAALgADCgEJAQAAAA==.',
Ca='Cafo:BAAALgADCgYJDAAAAA==.Capy:BAACLgAFFH8UAAQeAAUJ3yI8DwBKAQAeAAQJ7B88DwBKAQAMAAQJ/h2gMwBGAQAfAAEJAACWPgAAAAAuAAQKfzwABAwACQmHI0spADkCAB4ACAnqH+kNAEkCAAwACAn9IUspADkCAB8ABgmIF1YyAKUBAAAA.Cardran:BAAALgADCgEJAQABLgAECgkJKAARAJ4bAA==.Carkusw:BAAALgAECgMJBwAAAA==.Cassyn:BAABLgAECn8YAAITAAgJ3yHWBwDwAgATAAgJ3yHWBwDwAgAAAA==.Catamay:BAABLgAECn8gAAIaAAkJxRmTKgAfAgAaAAkJxRmTKgAfAgABLgAECgEJAQAPAAAAAA==.Catprincess:BAABLgAECn8fAAIFAAgJuBF+OwC3AQAFAAgJuBF+OwC3AQAAAA==.Cayda:BAAALgADCgYJBgAAAA==.Caylara:BAABLgAECn8pAAIgAAgJDBPxAQBXAQAgAAgJDBPxAQBXAQAAAA==.Cayssaber:BAAALgADCgEJAQAAAA==.',
Ce='Celrythis:BAABLgAECn8dAAIaAAYJgg8bmgDtAAAaAAYJgg8bmgDtAAAAAA==.',
Ch='Chai:BAABLgAECn8cAAIhAAkJ9xOUAQB1AQAhAAkJ9xOUAQB1AQAAAA==.Chaintrain:BAAALgAECgEJAQABLgAECgkJKgADABEfAA==.Chewglass:BAAALgADCggJCAAAAA==.Chiji:BAABLgAECn8mAAIdAAkJSBRpFwDuAQAdAAkJSBRpFwDuAQAAAA==.Chioma:BAAALgAECgYJCgAAAA==.',
Ci='Cindrethal:BAAALgADCggJCAAAAA==.',
Cl='Claes:BAAALgAECgEJBgABLgAECggJHQAdAP0SAA==.Clayler:BAAALgADCgQJBAAAAA==.Cleõ:BAAALgADCggJCwAAAA==.Clipperz:BAAALgAECgMJBAAAAA==.Clonetrooper:BAAALgAFFAIJAwAAAA==.Clorox:BAAALgADCgEJAQAAAA==.',
Co='Coocoohead:BAAALgAECgMJBQAAAA==.Coofus:BAABLgAFFH8GAAIOAAIJ1AExUwBIAAAOAAIJ1AExUwBIAAAAAA==.Coralorchid:BAABLgAECn8yAAMRAAgJvxMjFwBoAQARAAcJJRUjFwBoAQASAAcJyA/OngA5AQAAAA==.Corrupt:BAAALgAECgEJAQABLgAECgMJCAAPAAAAAA==.',
Cp='Cptdarkk:BAABLgAECn8ZAAISAAcJUwuEuAATAQASAAcJUwuEuAATAQAAAA==.',
Cr='Crytal:BAAALgAECgMJBAAAAA==.',
Cu='Cuddlebucket:BAAALgADCgQJBQAAAA==.Curissan:BAABLgAECn8jAAIOAAkJrxnoEwBMAgAOAAkJrxnoEwBMAgAAAA==.',
Cy='Cyg:BAAALgADCgEJAQAAAA==.',
['Cè']='Cères:BAABLgAECn8UAAIFAAgJAiEvFQCgAgAFAAgJAiEvFQCgAgAAAA==.',
['Cø']='Cøndemn:BAAALgAECgYJCAAAAA==.',
Da='Daemyn:BAAALgADCgcJBwAAAA==.Daladalian:BAAALgAECgMJAwAAAA==.Dalir:BAABLgAECn8bAAIEAAgJvhp0NAAtAgAEAAgJvhp0NAAtAgAAAA==.Dalruend:BAAALgADCgYJCwABLgAFFAgJIAAiAB0RAA==.Dalspin:BAACLgAFFH8gAAIiAAgJHRGgDwAWAgAiAAgJHRGgDwAWAgAuAAQKfy0ABCIACQkpG9wHANkCACIACQkpG9wHANkCACEABwm8ElYqAIoBAB0ACAkCCDIDAMsAAAAA.Dalthepal:BAABLgAECn8VAAITAAgJ1R2pHgAiAgATAAgJ1R2pHgAiAgABLgAFFAgJIAAiAB0RAA==.Darassa:BAAALgAECgEJAQAAAA==.Darka:BAAALgADCgYJFgAAAA==.Davidline:BAACLgAFFH8jAAISAAUJiCGvBwBgAQASAAUJiCGvBwBgAQAuAAQKf0wAAhIACQmMJoABAIEDABIACQmMJoABAIEDAAAA.Davidshaman:BAAALgAECgcJBwAAAA==.Dawnfist:BAAALgAECgQJBAAAAA==.',
De='Deadish:BAAALgAECgYJCwAAAA==.Deathsaberss:BAABLgAECn8qAAIWAAkJABgHDwD9AQAWAAkJABgHDwD9AQAAAA==.Deathstealer:BAAALgAECgIJAwAAAA==.Deathszen:BAAALgAECgcJEQAAAA==.Debauch:BAABLgAECn8cAAICAAkJPw9LTgCwAQACAAkJPw9LTgCwAQAAAA==.Deight:BAAALgAECgEJAQAAAA==.Dejamoo:BAAALgADCgcJBgAAAA==.Demonkayk:BAAALgADCgkJDgAAAA==.Dendraculus:BAAALgADCgYJCgAAAA==.Dennathor:BAAALgADCgYJCAAAAA==.Denniah:BAAALgAECgQJBAAAAA==.Derke:BAAALgAECgQJBwAAAA==.Destinee:BAAALgAECgEJAQAAAA==.',
Di='Didudietho:BAAALgADCggJCAABLgAECgkJSQASADobAA==.Diladrin:BAACLgAFFH8nAAIjAAUJEhAkBwC8AAAjAAUJEhAkBwC8AAAuAAQKf0sAAiMACQnDHKsGAJECACMACQnDHKsGAJECAAAA.Diode:BAACLgAFFH8fAAQEAAYJ7xTbSwBbAQAEAAUJfBHbSwBbAQAUAAQJBBOYEAASAQAbAAEJAADcVwAAAAAuAAQKfzEAAwQACQlyIDUYAOoCAAQACAn8IDUYAOoCABQACQnmG/IGAC8CAAAA.Dirtymack:BAAALgAECgMJAwABLgAECgcJJwAaANYeAA==.Diyla:BAAALgAECgEJAgAAAA==.Dizzy:BAAALgAECgIJAgAAAA==.',
Do='Doileag:BAABLgAECn8zAAISAAcJaAsEDADlAAASAAcJaAsEDADlAAAAAA==.Domer:BAAALgAECgYJCAAAAA==.Doomsong:BAAALgADCgYJCgAAAA==.Dora:BAAALgAECgMJAwAAAA==.Dottmatrix:BAABLgAECn8fAAIDAAcJKg6sFAAIAQADAAcJKg6sFAAIAQAAAA==.',
Dr='Drachnia:BAAALgAECgQJBAAAAA==.Dragønbreath:BAACLgAFFH8MAAMVAAUJHAkxcAABAQAVAAUJHAkxcAABAQAcAAEJaANLCAAzAAAuAAQKfx0AAxwACQlxGhcCAEoCABwACAnMFxcCAEoCABUACAk3FW+1ABkBAAAA.Dreadwing:BAABLgAECn8lAAIEAAYJMxR1BgA2AQAEAAYJMxR1BgA2AQAAAA==.',
Du='Duf:BAACLgAFFH8jAAIdAAcJfx3pEACeAQAdAAcJfx3pEACeAQAuAAQKfy8AAh0ACQmEHyQPAEkCAB0ACQmEHyQPAEkCAAAA.Dunso:BAAALgADCgYJAQAAAA==.Dustbunny:BAABLgAECn9PAAIKAAkJPSCbBgAJAwAKAAkJPSCbBgAJAwAAAA==.',
Dw='Dwagon:BAAALgAFFAIJAgAAAA==.',
['Dæ']='Dæmôn:BAAALgAECgYJCQAAAA==.',
['Dó']='Dóómkin:BAAALgADCgEJAQAAAA==.',
['Dû']='Dûn:BAACLgAFFH8RAAMhAAMJdCBdFgANAQAhAAMJdCBdFgANAQAdAAEJNQ2iEgBKAAAuAAQKfzEAAx0ACQkpGzAPAEgCAB0ACQkpGzAPAEgCACEAAgmkGCFgAI8AAAAA.Dûna:BAACLgAFFH8HAAIZAAIJVR0SLQCWAAAZAAIJVR0SLQCWAAAuAAQKfyUAAhkACAkBIccNAHgCABkACAkBIccNAHgCAAEuAAUUAwkRACEAdCAA.',
Ei='Eira:BAAALgADCggJDQAAAA==.',
El='Elaatia:BAABLgAECn9LAAISAAkJQSR0BwAyAwASAAkJQSR0BwAyAwAAAA==.Elduar:BAAALgADCgEJAQAAAA==.Elidria:BAAALgADCgYJBgAAAA==.Elimental:BAABLgAECn8gAAIOAAgJYxInMQB6AQAOAAgJYxInMQB6AQAAAA==.Elketha:BAAALgAECgUJBQABLgAFFAUJJwAaAMkcAA==.Ellaring:BAAALgAECgYJCAABLgAECgcJDwAPAAAAAA==.Elle:BAAALgADCgcJBwAAAA==.Elleanna:BAAALgADCgcJBwAAAA==.Elrondd:BAAALgADCgEJAQABLgAECgkJLwAFAFoeAA==.Elrric:BAABLgAECn8WAAIEAAkJQAx2iQBRAQAEAAkJQAx2iQBRAQAAAA==.Elryck:BAAALgADCgYJBgAAAA==.',
En='Endora:BAAALgADCggJDQAAAA==.Enezath:BAAALgADCgYJBgAAAA==.',
Er='Erakron:BAABLgAECn8zAAMGAAgJ3h+tEADKAgAGAAgJ3h+tEADKAgAOAAgJJRNHMgB0AQAAAA==.Eriko:BAAALgADCgkJEAAAAA==.Erine:BAAALgAECgMJAwAAAA==.Erouvi:BAAALgAECgEJAQABLgAECgkJRgAKAFYeAA==.Eroviaa:BAAALgAECgkJEAABLgAECgkJRgAKAFYeAA==.Erovvia:BAAALgAECgUJBgABLgAECgkJRgAKAFYeAA==.',
Es='Essaelsia:BAAALgAECgcJBwAAAA==.',
Et='Etali:BAAALgAECgMJBAABLgAFFAEJAwAPAAAAAA==.',
Ev='Evorik:BAAALgAECgEJAQABLgAFFAUJEgAdALERAA==.',
Ez='Ezothen:BAABLgAECn8tAAMQAAgJpBCCAwD3AAAQAAgJpBCCAwD3AAAkAAQJawRpLwCdAAAAAA==.',
Fa='Faedoria:BAABLgAECn8kAAISAAkJ7wSMtgAWAQASAAkJ7wSMtgAWAQAAAA==.Faeryln:BAABLgAECn8nAAIKAAkJ+wuNLABmAQAKAAkJ+wuNLABmAQAAAA==.Faerynn:BAAALgADCgkJCQABLgAECgkJLwAFAFoeAA==.Faewrynn:BAAALgADCgMJAwAAAA==.Falenrush:BAAALgADCgEJAQAAAA==.Falkorr:BAAALgAECgQJCAABLgAECgkJQQAlAHcgAA==.Falorie:BAAALgADCgYJEQAAAA==.Fatesmage:BAAALgADCgUJCAAAAA==.Fatherfade:BAAALgAECgQJBAAAAA==.Fatherkarras:BAAALgADCgIJAgAAAA==.Faustion:BAABLgAECn80AAMYAAkJfCElBADzAgAYAAgJuCElBADzAgAQAAEJByGRfwBgAAAAAA==.Faustus:BAAALgADCgQJCgABLgAECgkJNAAYAHwhAA==.',
Fe='Feature:BAAALgAECgkJBwAAAA==.Felstormer:BAAALgADCggJEAABLgAECgUJEAAPAAAAAA==.Felyna:BAAALgAECgMJAwAAAA==.',
Fi='Filthy:BAAALgADCggJDgAAAA==.Finessed:BAAALgADCgEJAQAAAA==.Firebrande:BAAALgAECgcJCgAAAA==.Firefoxx:BAAALgAECgEJAQABLgAECgkJLwAFAFoeAA==.Fireføx:BAAALgAECgEJAQAAAA==.Fisticuffs:BAAALgAECgUJEAAAAA==.Fistingmoth:BAAALgAECgUJBQAAAA==.Fizzllebang:BAABLgAECn8oAAIDAAkJxxUFCQC5AQADAAkJxxUFCQC5AQAAAA==.',
Fl='Flamewhisker:BAAALgAECgcJCgAAAQ==.Flandre:BAAALgAECgYJBgAAAA==.Flogginrenee:BAAALgAECgYJEwAAAA==.Floggsdaddy:BAAALgAECgYJEwAAAA==.Floke:BAAALgAECgMJBAAAAA==.Flokie:BAAALgADCgYJEQAAAA==.',
Fo='Fourthmeal:BAAALgAECgIJAgAAAA==.',
Fr='Fraublucher:BAABLgAECn9GAAIKAAkJnxYiAQAIAgAKAAkJnxYiAQAIAgAAAA==.Fredrik:BAABLgAFFH8SAAMdAAUJsRFzJwALAQAdAAUJsRFzJwALAQAiAAIJywGIcAAiAAAAAA==.Frewyn:BAAALgAECgQJCQAAAA==.Frikk:BAAALgAECgQJBAAAAA==.Frostedcakes:BAAALgAECgUJBQAAAA==.Frostimoth:BAABLgAECn8tAAIVAAkJzRYpOwAtAgAVAAkJzRYpOwAtAgAAAA==.Frozty:BAABLgAECn8dAAIYAAkJuxONCwAhAgAYAAkJuxONCwAhAgAAAA==.',
Fu='Fujïn:BAAALgADCgEJAQAAAA==.',
Ga='Galandel:BAABLgAECn8UAAIfAAUJHBdXAQABAQAfAAUJHBdXAQABAQAAAA==.Galial:BAACLgAFFH8XAAIHAAYJkh/DAQCzAQAHAAYJkh/DAQCzAQAuAAQKfyIAAgcACQlaHzsBACIDAAcACQlaHzsBACIDAAAA.Gantar:BAACLgAFFH8LAAIjAAUJbCJ+AQCZAQAjAAUJbCJ+AQCZAQAuAAQKfxgAAiMACAl5I64CAPoCACMACAl5I64CAPoCAAAA.Garlicbread:BAAALgADCgYJBgABLgAFFAYJFwAHAJIfAA==.Garralock:BAAALgAECgcJAQAAAA==.Garrunter:BAAALgAECgkJDgAAAA==.Gaznol:BAABLgAECn8kAAIMAAkJqiAJHgBxAgAMAAkJqiAJHgBxAgAAAA==.',
Ge='Gelasera:BAAALgAECgcJCgAAAA==.Gerbert:BAAALgAECgUJCQAAAA==.',
Gh='Ghibli:BAABLgAECn8XAAMWAAkJuA+8GwB9AQAWAAkJuA+8GwB9AQAXAAIJ7AWjmgBWAAAAAA==.',
Gi='Gisa:BAAALgAECgEJAQABLgAFFAEJAwAPAAAAAA==.',
Gl='Glaivethras:BAABLgAECn8nAAIHAAkJNiPUAgDEAgAHAAkJNiPUAgDEAgAAAA==.Glyph:BAAALgAECgEJAQAAAA==.Glyphix:BAABLgAECn8nAAIXAAkJPwueMQCGAQAXAAkJPwueMQCGAQAAAA==.Glyphx:BAAALgAECgEJAwAAAA==.',
Gn='Gnarly:BAAALgAECgMJCAAAAA==.',
Go='Goochtrap:BAAALgAECgQJBAAAAA==.Gorgon:BAAALgAECgMJBAAAAA==.',
Gr='Grasman:BAAALgADCgYJBwAAAA==.Gremlynn:BAABLgAECn8hAAQeAAgJxgwxJAB8AQAeAAgJuAsxJAB8AQAMAAQJeQ4vgQDkAAAfAAQJXwUlaACeAAAAAA==.Gridluck:BAAALgAECgMJBAAAAA==.Grimclaw:BAAALgAECgIJAwABLgAFFAkJHwAEADEeAA==.Groot:BAABLgAECn8hAAMFAAcJchXlPACgAQAFAAYJ3xblPACgAQAlAAcJKQ1MPQAbAQABLgAFFAIJBgASAOMLAA==.Groovinchef:BAAALgAECgEJAQAAAA==.Grump:BAAALgAECgEJAQABLgAFFAIJAwAPAAAAAA==.',
Gu='Gundunn:BAAALgADCgEJAQAAAA==.',
Ha='Hackdk:BAAALgADCgYJCwAAAA==.Haedlesshour:BAAALgADCgcJBwAAAA==.Hahona:BAAALgADCgEJAQABLgAECgcJJwAGADMNAA==.Hamfist:BAAALgADCgYJBwAAAA==.Hanhealz:BAEBLgAECn8gAAIZAAgJsRCgLgBmAQAZAAgJsRCgLgBmAQABLgAECgYJBwAPAAAAAA==.Hannebal:BAABLgAECn8aAAITAAkJEhFyJwDPAQATAAkJEhFyJwDPAQAAAA==.',
He='Healsonyou:BAAALgAECgUJBQABLgAECggJFwAEAFsUAA==.Hearsebait:BAAALgADCgIJAgAAAA==.Heiter:BAAALgADCgIJAgAAAA==.Hemlock:BAAALgADCgYJCgAAAA==.Hexia:BAAALgADCggJEgAAAA==.Heydaw:BAAALgAECggJDgABLgAECgkJIAAEAHIgAA==.',
Hi='Highmountain:BAAALgADCgkJCgAAAA==.',
Ho='Hobloc:BAAALgADCgcJCwAAAA==.Hobs:BAAALgAECgEJAQAAAA==.Holybeatdown:BAAALgAECgMJBAAAAA==.Holyrage:BAAALgADCgYJCAAAAA==.Holyßloodelf:BAAALgAECggJCwABLgAECggJFwAEAFsUAA==.Honeysbadger:BAAALgAECgMJAwAAAA==.Hoosier:BAAALgAECgQJBQAAAA==.Hornet:BAABLgAECn8VAAMaAAgJZBDrYwBgAQAaAAgJ7w/rYwBgAQAIAAQJFwz3SADPAAAAAA==.Hotcupofjoe:BAAALgADCgYJBgAAAA==.Hotsauce:BAAALgAECgYJCAABLgAFFAcJGgAVAOIaAA==.',
Hu='Huasca:BAAALgAECgMJBQAAAA==.Humungous:BAAALgAECgcJDQAAAA==.Hunnybunz:BAAALgAECgYJDAAAAA==.Huntriss:BAAALgAECgIJAgAAAA==.',
Hy='Hyve:BAAALgAECgkJCQAAAA==.',
['Hà']='Hàney:BAEALgAECgYJBwAAAA==.',
['Hâ']='Hârkness:BAAALgAECgMJEgAAAA==.',
['Hé']='Hélio:BAAALgAECgUJCAAAAA==.',
Ia='Ia:BAABLgAFFH8LAAIUAAQJKAy2EAARAQAUAAQJKAy2EAARAQAAAA==.',
Ic='Icastfirebal:BAAALgAECgEJAQAAAA==.Icypants:BAAALgADCgcJBwAAAA==.',
If='Iffany:BAAALgAECggJDAAAAA==.',
Ig='Igotahitin:BAAALgADCgMJCAAAAA==.',
Ih='Ihitstuff:BAAALgADCgUJBAAAAA==.',
Ik='Iker:BAABLgAECn8dAAIdAAgJ/RIGIwCRAQAdAAgJ/RIGIwCRAQAAAA==.',
Il='Illida:BAAALgAECgYJCQAAAA==.',
Im='Imamalelol:BAABLgAECn8qAAQXAAcJsA0ESQAhAQAXAAcJkwwESQAhAQAWAAUJrQrfRwCsAAANAAEJqgCaYgATAAAAAA==.',
In='Indira:BAAALgADCgcJDQABLgAECgQJBAAPAAAAAA==.Insistonfist:BAAALgADCgEJAQAAAA==.Intol:BAAALgAFFAUJCQABLgAFFAUJDAAYAMMNAQ==.Inumimi:BAABLgAECn8iAAImAAkJBQaIJADlAAAmAAkJBQaIJADlAAAAAA==.Invincidemon:BAAALgAECgQJBAAAAA==.',
Ir='Irkenfox:BAECLgAFFH8eAAINAAcJ1CCPCQCYAQANAAcJ1CCPCQCYAQAuAAQKfyUAAg0ACAmhI54DABsDAA0ACAmhI54DABsDAAAA.',
Is='Isogni:BAAALgAECgQJBAABLgAECgcJIAAJAG4eAA==.',
It='Ithran:BAABLgAECn8pAAIVAAkJKQyacQCWAQAVAAkJKQyacQCWAQAAAA==.',
Iw='Iwilltank:BAAALgADCgYJDQAAAA==.',
Ix='Ixitt:BAABLgAECn8wAAIcAAkJ5x17AQCWAgAcAAkJ5x17AQCWAgAAAA==.',
Iz='Izanamí:BAAALgADCgMJAwAAAA==.',
Ja='Jallaz:BAAALgADCgQJBAAAAA==.Jama:BAAALgAECgUJBwAAAA==.James:BAACLgAFFH8gAAIVAAQJTBwHEgBDAQAVAAQJTBwHEgBDAQAuAAQKf0wAAhUACQlMIi0PAAEDABUACQlMIi0PAAEDAAEuAAUUBQkSAB0AsREA.Janderick:BAABLgAECn8lAAIXAAkJyiAsDACmAgAXAAkJyiAsDACmAgAAAA==.Janthara:BAAALgAECgQJBAAAAA==.',
Je='Jeannedarc:BAAALgAECgYJDgAAAA==.Jellacee:BAABLgAECn8gAAMIAAYJEBTAAwD2AAAIAAYJEBTAAwD2AAAaAAIJHgO4EwE2AAAAAA==.Jesterjoe:BAABLgAECn8WAAISAAYJ1SHtAgDrAQASAAYJ1SHtAgDrAQAAAA==.',
Jh='Jhonson:BAAALgADCgYJBgAAAA==.',
Ji='Jimboberjim:BAACLgAFFH8gAAIDAAcJ6R2vAgC8AQADAAcJ6R2vAgC8AQAuAAQKfy8AAgMACQmfIfQAAC8DAAMACQmfIfQAAC8DAAAA.Jimi:BAAALgADCgUJBQAAAA==.Jimreaper:BAAALgAECgkJCQAAAA==.Jinkx:BAAALgAECgEJAQABLgAECgkJQQAlAHcgAA==.',
Jj='Jjoosshhiiee:BAAALgADCgMJBAABLgAFFAUJCwAjAGwiAA==.',
Jo='Joejitsu:BAAALgAECgMJAwAAAA==.Jojokiller:BAAALgADCgEJAQAAAA==.Jolio:BAABLgAECn8qAAQDAAkJER+uCQCsAQADAAYJrx6uCQCsAQACAAQJhh/hdABQAQABAAEJXCB1KgBKAAAAAA==.Joltraxi:BAAALgAECgMJBgABLgAECgkJKgADABEfAA==.Jorlidan:BAAALgAECgYJCgAAAA==.Joshe:BAAALgAECgYJEwABLgAFFAUJCwAjAGwiAA==.Joshy:BAABLgAFFH8FAAISAAQJsQ4OVAAHAQASAAQJsQ4OVAAHAQABLgAFFAUJCwAjAGwiAA==.Jovae:BAAALgADCgIJAgAAAA==.',
Js='Jstnbieber:BAAALgAECgIJAgAAAA==.',
Ju='Juggernauht:BAAALgAECgUJCgAAAA==.Juicethevoid:BAABLgAECn8pAAIaAAkJnwcscQBAAQAaAAkJnwcscQBAAQAAAA==.Juniornite:BAABLgAECn82AAIVAAkJmCAvFwDOAgAVAAkJmCAvFwDOAgAAAA==.Justicus:BAAALgAECgYJEQABLgAECggJIgAIAO4iAA==.Justthetouch:BAAALgAECggJCQAAAA==.',
Jy='Jygglypuff:BAAALgAECgcJCQAAAA==.',
['Jü']='Jüst:BAAALgAECgMJAwAAAA==.',
Ka='Kadaan:BAAALgAECggJCgABLgAECgcJCgAPAAAAAA==.Kadtwo:BAAALgAECgEJAQABLgAECgcJCgAPAAAAAA==.Kaeirria:BAAALgAECgEJAQAAAA==.Kaeldrin:BAAALgADCgkJFAAAAA==.Kaelsanguine:BAAALgAECgEJAQAAAA==.Kagemaro:BAABLgAECn83AAQIAAkJNxuLEAAfAgAIAAgJbxuLEAAfAgAHAAcJVhWFDgBpAQAaAAgJsA4tZgBaAQABLgAFFAEJAwAPAAAAAA==.Kaiser:BAAALgAECgQJCQAAAA==.Kaisér:BAAALgADCgYJBgAAAA==.Kalimathath:BAAALgAECgUJDwAAAA==.Kalzod:BAACLgAFFH8eAAMCAAUJoRtrEQADAQACAAQJoRtrEQADAQABAAIJWRZXCABXAAAuAAQKfz4AAwIACQlLJqQCAGgDAAIACQlLJqQCAGgDAAEAAQkAAB0kAGEAAAAA.Kariana:BAAALgAECgYJDgAAAA==.Kataki:BAAALgAFFAEJAwAAAA==.Katett:BAAALgAECgcJDgAAAA==.Katia:BAAALgADCgUJBQAAAA==.Kativeria:BAAALgAECgcJCgAAAA==.Kattara:BAAALgAECgQJBAAAAA==.Kattitude:BAAALgADCgcJDwABLgAECgYJDgAPAAAAAA==.Katyla:BAAALgADCgcJCAAAAA==.Kauhuana:BAAALgAECgMJAwAAAA==.Kaysabr:BAAALgADCgkJDAAAAA==.Kayssaber:BAAALgAECgYJEgAAAA==.Kazarale:BAAALgADCgQJBAAAAA==.Kazkade:BAAALgAECgMJAwAAAA==.',
Ke='Keanuu:BAAALgADCgMJAwAAAA==.Keidric:BAAALgAECgIJAgAAAA==.Kerfufle:BAAALgAECgUJBQAAAA==.Keyn:BAAALgAECgIJAQAAAA==.Keynstolor:BAABLgAECn8hAAIMAAgJRBrwRwDKAQAMAAgJRBrwRwDKAQAAAA==.',
Kh='Khionè:BAAALgAECgEJAQAAAA==.Khálifá:BAAALgAECgUJBgAAAA==.',
Ki='Kicker:BAABLgAECn8UAAIXAAYJcgYNaAC+AAAXAAYJcgYNaAC+AAAAAA==.Killmora:BAABLgAECn8UAAIVAAUJeBPWCwDzAAAVAAUJeBPWCwDzAAAAAA==.Kippars:BAABLgAECn8hAAMjAAgJvRVzHQBiAQAjAAcJxxVzHQBiAQAmAAEJfRU0TQA+AAAAAA==.Kiritsugo:BAAALgAECgUJCgAAAA==.Kissame:BAAALgAECgYJCQAAAA==.',
Kn='Knaifu:BAAALgADCgkJDQAAAA==.',
Ko='Kodazoff:BAABLgAECn85AAQQAAkJixKNHgDjAQAQAAkJUhKNHgDjAQAkAAgJsQ1yCgB4AQAYAAIJIAdKPAAyAAAAAA==.Kora:BAAALgAECgYJBgAAAA==.Korevash:BAACLgAFFH8GAAILAAQJ2hD6AQAhAQALAAQJ2hD6AQAhAQAuAAQKfycAAwsACAn7Gx0LAAUCAAsACAn7Gx0LAAUCAAYAAgnjCf68AFUAAAEuAAUUBQkfAAkAAhQA.Korupta:BAABLgAECn8uAAMaAAgJHBAsYgBkAQAaAAgJHBAsYgBkAQAIAAUJ3A36PQAFAQABLgAECgkJJAACADgSAA==.Korzilius:BAAALgAECggJEAAAAA==.',
Kr='Krissylu:BAABLgAECn8gAAIBAAcJFQ3WEgA9AQABAAcJFQ3WEgA9AQAAAA==.Krockett:BAAALgAECgQJBAAAAA==.Krothix:BAABLgAECn9FAAIOAAkJrA0XMwBwAQAOAAkJrA0XMwBwAQAAAA==.Kruvix:BAAALgAECgYJCgAAAA==.Krygask:BAAALgAECgQJBAAAAA==.Kryjag:BAAALgAECgQJDgAAAA==.Krynir:BAAALgADCgkJDgAAAA==.Kryshym:BAABLgAECn8VAAITAAkJ7xyuAABpAgATAAkJ7xyuAABpAgAAAA==.Krythrall:BAAALgAECgUJCAABLgAECgkJFQATAO8cAA==.',
Ku='Kuatea:BAAALgADCgUJBQAAAA==.Kurorø:BAAALgAECgcJEwAAAA==.',
Ky='Kyrayna:BAAALgAECgMJAwAAAA==.',
La='Ladara:BAABLgAECn8tAAIBAAkJ8BAkCADLAQABAAkJ8BAkCADLAQAAAA==.Laima:BAAALgADCgcJEwAAAA==.Lalthras:BAAALgAECgcJBwAAAA==.Lamlam:BAAALgADCgUJBQAAAA==.Landor:BAAALgADCgEJAQAAAA==.Lanea:BAAALgAECgEJAgAAAA==.Lavitz:BAAALgAECgQJCgAAAA==.',
Le='Leheo:BAAALgAECgQJDAAAAA==.Lehua:BAAALgAECgQJCAAAAA==.Leilanii:BAAALgAECgQJCQAAAA==.Lemook:BAAALgAECggJEwAAAA==.Leonìdas:BAAALgAECgQJBgAAAA==.',
Lh='Lhei:BAABLgAECn8eAAIMAAYJOwpcCwAEAQAMAAYJOwpcCwAEAQAAAA==.',
Li='Lightstormer:BAAALgAECgUJEAAAAA==.Lilamae:BAAALgAECggJDgAAAA==.Lilarielle:BAABLgAECn9NAAImAAgJ+QplAwCzAAAmAAgJ+QplAwCzAAAAAA==.Lildash:BAAALgADCgIJAgABLgAECgkJKAARAJ4bAA==.Lildookie:BAAALgADCgYJBQAAAA==.Lilface:BAAALgAECgYJCgAAAA==.Liliela:BAAALgAECgQJBAABLgAECgkJKAARAJ4bAA==.Lilsham:BAAALgAECgQJBAABLgAECgkJKAARAJ4bAA==.Lilyannah:BAAALgAECgkJAQAAAA==.Linadra:BAAALgAECgcJBwAAAA==.Liobrew:BAAALgADCgEJAQABLgAECgIJAgAPAAAAAA==.Liopain:BAAALgAECgIJAgAAAA==.Liø:BAAALgAECgEJAQABLgAECgIJAgAPAAAAAA==.',
Lo='Lokir:BAAALgAECgMJBgAAAA==.Losoli:BAAALgAECgkJCQABLgAECgkJVwAhAG4cAA==.Lotheovian:BAEALgAECgIJAgABLgAECgkJLwAEANQaAA==.Lowchin:BAABLgAECn8VAAIFAAcJOwqEZwD+AAAFAAcJOwqEZwD+AAAAAA==.',
Lu='Lucciffer:BAAALgAECgEJAQAAAA==.Lumia:BAABLgAECn8dAAMZAAkJix4wEwBcAgAZAAcJlB8wEwBcAgAKAAYJFBjVSgANAQAAAA==.Lutherion:BAABLgAECn8bAAQNAAgJiyBxCABzAgANAAgJiyBxCABzAgAWAAEJCQdCSAAlAAAXAAEJUALIugASAAAAAA==.',
Lv='Lvispriestly:BAAALgADCgcJEgABLgAECgkJJAAlAKIDAA==.',
Ly='Lycemmas:BAAALgAECgQJBAAAAA==.',
['Lì']='Lìllìth:BAAALgAECgYJBgAAAA==.',
['Lí']='Líttlefoot:BAAALgADCgEJAQAAAA==.',
Ma='Mackdaddy:BAAALgAECgEJAQAAAA==.Mackshiesty:BAABLgAECn8nAAIaAAcJ1h6aLAAVAgAaAAcJ1h6aLAAVAgAAAA==.Macoun:BAABLgAECn88AAMMAAkJ0CSWBABHAwAMAAkJ0CSWBABHAwAfAAYJEhv0QABVAQAAAA==.Maeledictus:BAAALgAECgMJAwAAAA==.Maga:BAAALgADCgkJHgAAAA==.Magicshowers:BAABLgAECn9IAAIVAAkJLibhBABfAwAVAAkJLibhBABfAwAAAA==.Maikiee:BAAALgADCggJCAAAAA==.Manseed:BAABLgAECn8dAAIZAAgJzAqcNgA7AQAZAAgJzAqcNgA7AQAAAA==.Marksmen:BAAALgADCgEJAQABLgAECgQJBgAPAAAAAA==.Martei:BAACLgAFFH8cAAImAAYJ3BhdBgBHAQAmAAYJ3BhdBgBHAQAuAAQKfy8AAiYACQm/IkICAC8DACYACQm/IkICAC8DAAAA.Maruki:BAAALgADCgEJAQAAAA==.Maríneth:BAABLgAECn8mAAIFAAYJTxI8AwBAAQAFAAYJTxI8AwBAAQAAAA==.Mathías:BAABLgAECn8nAAIMAAkJgBkJKwAxAgAMAAkJgBkJKwAxAgAAAA==.Mavze:BAAALgADCgIJAgAAAA==.',
Me='Meadowfrey:BAAALgAECgEJAQAAAA==.Mentuko:BAAALgAECgQJBgAAAA==.Meowbae:BAABLgAECn84AAMmAAkJ5Rj7AACMAQAmAAkJ5Rj7AACMAQAlAAEJNAGaqQAVAAAAAA==.Merce:BAAALgAECgcJDwABLgAECgkJKAARAJ4bAA==.Mercesdes:BAAALgAECgUJCAAAAA==.Mercina:BAAALgAECgYJCgAAAA==.Mercuros:BAABLgAECn8UAAMKAAkJawMdPgD5AAAKAAkJawMdPgD5AAAZAAIJrgMwfgBBAAAAAA==.Merknlock:BAAALgAECgEJAQAAAA==.',
Mi='Micãh:BAAALgAECgIJAgAAAA==.Midnyte:BAABLgAECn9XAAMhAAkJbhy8DAB5AgAhAAkJbhy8DAB5AgAiAAkJARh9AgDKAQAAAA==.Mii:BAAALgAECgkJBQAAAA==.Milkyweí:BAAALgAECgMJAwAAAA==.Mindgames:BAAALgAECgEJAQAAAA==.Mini:BAAALgADCgUJBQABLgAFFAUJBgAeANQRAA==.Minizee:BAAALgAECgYJCAAAAA==.Mirabella:BAAALgAECgUJCwABLgAFFAQJDQAiABYZAA==.Mirokushan:BAABLgAECn8UAAMiAAQJKxE5bQDPAAAiAAQJKxE5bQDPAAAdAAQJwQMiaAB4AAABLgAECgYJGQACANYWAA==.Mistfit:BAAALgAECgQJAwAAAA==.Misticlady:BAAALgADCgEJAQAAAA==.Mistingmoo:BAAALgAECgkJDQAAAA==.Mistrariel:BAABLgAECn8pAAIHAAkJuh5dAwCqAgAHAAkJuh5dAwCqAgABLgAFFAEJAgAPAAAAAA==.',
Mo='Mojo:BAAALgADCgIJAgAAAA==.Moostafa:BAAALgAECgQJBAAAAA==.Moradin:BAAALgADCgIJAgAAAA==.Mordemour:BAABLgAECn8iAAIBAAYJwBktAQBOAQABAAYJwBktAQBOAQAAAA==.Morlune:BAAALgAECgEJAQAAAA==.',
Mu='Mungo:BAABLgAECn8rAAIVAAkJrRfzUQDmAQAVAAkJrRfzUQDmAQAAAA==.Musketoon:BAAALgAECgYJBgAAAA==.',
My='My:BAAALgAECgkJDgAAAA==.Mynkie:BAACLgAFFH8gAAIiAAUJqRcPCQBSAQAiAAUJqRcPCQBSAQAuAAQKfzYAAiIACQlfImEEAGsDACIACQlfImEEAGsDAAAA.Myrell:BAAALgAECgkJBgAAAA==.Mythreashis:BAAALgADCgMJAwAAAA==.',
['Mä']='Mägi:BAAALgAECgEJAQAAAA==.',
['Må']='Mååt:BAAALgADCgIJAgAAAA==.',
['Mæ']='Mæstra:BAAALgAECgEJAQAAAA==.',
['Më']='Mëlony:BAAALgADCgIJAgAAAA==.',
Na='Nachtmar:BAABLgAECn8lAAIjAAYJKBa9AgAmAQAjAAYJKBa9AgAmAQAAAA==.Nadaliss:BAAALgADCgkJCwAAAA==.Nahela:BAACLgAFFH8gAAIaAAYJKxSzMABiAQAaAAYJKxSzMABiAQAuAAQKfyoAAhoACAlDHMsyAPsBABoACAlDHMsyAPsBAAAA.Nalik:BAAALgAECgYJBwAAAA==.Nanou:BAAALgADCgUJBwAAAA==.Nardiaun:BAAALgAECgYJBgAAAA==.',
Ne='Necia:BAAALgADCgMJAwABLgAECgkJJwAKAPsLAA==.Neltu:BAAALgAECgQJBQAAAA==.Nevermøre:BAAALgAECgIJAgAAAA==.',
Ni='Nikkitta:BAAALgADCgMJAwAAAA==.Nimravidae:BAABLgAECn9EAAMSAAkJQBYIYACxAQASAAgJ4BMIYACxAQATAAgJXxiLAgByAQAAAA==.Ninelives:BAABLgAECn8kAAIlAAkJogOLTgDSAAAlAAkJogOLTgDSAAAAAA==.Nitecrawler:BAABLgAECn8jAAMVAAkJnw+SXgDEAQAVAAkJnw+SXgDEAQAnAAEJhQM/GwAZAAAAAA==.Nitelyt:BAAALgAECgIJAgABLgAECgkJNgAVAJggAA==.Niteryu:BAABLgAECn8kAAMkAAkJlxONAABbAQAkAAkJLRONAABbAQAQAAIJWQ/TCABkAAABLgAECgkJNgAVAJggAA==.Nixus:BAAALgAECgMJAwAAAA==.',
No='Nospitfisty:BAABLgAECn8nAAIQAAgJCQzSOwA7AQAQAAgJCQzSOwA7AQAAAA==.Noxium:BAAALgAECgYJDQAAAA==.Noxolon:BAABLgAECn9IAAIXAAkJ9B1hCgC+AgAXAAkJ9B1hCgC+AgAAAA==.',
Nr='Nreaf:BAABLgAECn8/AAMRAAkJ0CAqAQCdAQASAAkJNR+9JACUAgARAAkJJhwqAQCdAQAAAA==.',
Nu='Nufy:BAAALgAECgYJDwAAAA==.',
Ny='Nyctei:BAAALgAECgUJCQAAAA==.Nydhogg:BAAALgAECgEJAQABLgAFFAEJAgAPAAAAAA==.Nysca:BAAALgADCgcJBwAAAA==.Nytess:BAAALgAECgcJBwABLgAECgkJVwAhAG4cAA==.',
Ob='Obijuan:BAAALgAECgMJAwAAAA==.',
Oc='Octavia:BAAALgADCgYJCAAAAA==.',
Od='Oddotter:BAAALgADCgYJBgAAAA==.',
Oi='Oili:BAABLgAECn8ZAAIVAAkJ0x9lAwDYAQAVAAkJ0x9lAwDYAQAAAA==.',
Ol='Olarrick:BAABLgAFFH8HAAIbAAMJ/wS/MAB+AAAbAAMJ/wS/MAB+AAABLgAFFAUJEgAdALERAA==.',
Or='Ornstein:BAABLgAECn8tAAMRAAgJOCFGCQA9AgARAAgJDCFGCQA9AgASAAYJahSVvwAJAQAAAA==.',
Ot='Ottuk:BAACLgAFFH8XAAMEAAYJcxXBPgB6AQAEAAUJcxXBPgB6AQAbAAEJAAAHZAAAAAAuAAQKfyIAAwQACQnVIa8IAFgDAAQACQnVIa8IAFgDABsAAwlnHX0nAAMBAAAA.',
Pa='Padinbar:BAAALgAECgQJBAABLgAECgcJFQAVAAkSAA==.Pakraxes:BAAALgAFFAEJAQAAAA==.Paksenarrion:BAABLgAECn9FAAIRAAkJdBHbAQA/AQARAAkJdBHbAQA/AQAAAA==.Pancham:BAAALgADCgUJBQAAAA==.Pandemoniúm:BAAALgAECgMJAwAAAA==.Pandemonîum:BAAALgAECgkJEQAAAA==.Pandemônium:BAAALgAECggJEAAAAA==.Pandemönium:BAAALgAFFAIJAwAAAA==.Pandemöniüm:BAAALgAECgYJDAAAAA==.Pandèmonium:BAAALgAECgYJBgAAAA==.Parts:BAAALgAECgIJBQAAAA==.Patchington:BAABLgAECn8mAAIRAAYJxRb7AQAxAQARAAYJxRb7AQAxAQAAAA==.Pañdemönium:BAAALgAECgUJBQAAAA==.',
Pe='Peatmoss:BAAALgADCgQJBAAAAA==.Pendrgn:BAAALgAECgEJAQAAAA==.Perck:BAAALgAECgQJBAAAAA==.Peryite:BAAALgADCgMJAwAAAA==.Pezp:BAAALgAECgQJBAABLgAFFAIJBgAQAIgTAA==.Pezvoker:BAACLgAFFH8GAAIQAAIJiBOmUwB7AAAQAAIJiBOmUwB7AAAuAAQKfxUAAhAABgkgINMiAMQBABAABgkgINMiAMQBAAAA.',
Ph='Phaedrä:BAAALgAECgEJAQAAAA==.',
Pi='Pienarri:BAAALgAECgEJAgAAAA==.Pixelme:BAAALgAFFAIJAgAAAA==.',
Pl='Pleggster:BAABLgAECn8fAAMGAAkJcA2aTgB3AQAGAAkJcA2aTgB3AQAOAAEJiAGAwgAbAAAAAA==.',
Po='Pochula:BAABLgAECn8kAAIFAAgJaxVoKwD9AQAFAAgJaxVoKwD9AQAAAA==.Powerlock:BAAALgAECgQJBQAAAA==.',
Pr='Primo:BAACLgAFFH8KAAITAAMJLgqkDACaAAATAAMJLgqkDACaAAAuAAQKfzYAAxMACQmxFoscAB8CABMACQmxFoscAB8CABIAAglKBCJ1AUQAAAAA.Protricity:BAABLgAECn88AAMZAAkJdCDTCQCxAgAZAAkJdCDTCQCxAgAKAAEJ2AJchAAtAAAAAA==.',
Pu='Pumpernickel:BAAALgADCgUJBQABLgAFFAYJFwAHAJIfAA==.Puppytoes:BAABLgAECn8VAAMRAAYJ1BEmIAASAQARAAYJ1BEmIAASAQASAAEJXQgfmQEvAAAAAA==.',
Py='Pyrellyn:BAAALgADCggJCgAAAA==.',
['Pä']='Pändamönium:BAABLgAECn8XAAQLAAkJVBEqAgAQAQAOAAgJwBCUOABVAQALAAUJ8g0qAgAQAQAGAAMJ9BOsjwC5AAAAAA==.Pändemönium:BAAALgAFFAEJAQAAAA==.',
['Pæ']='Pæn:BAACLgAFFH8WAAIEAAUJOyaTLAC1AQAEAAUJOyaTLAC1AQAuAAQKfzMAAxsABwnHJQABAAcCAAQABwnHJRoiAH8CABsABwlqIwABAAcCAAEuAAUUBQkkABMA7yIA.',
Qt='Qtpi:BAAALgADCgcJCAAAAA==.',
Qu='Quan:BAAALgAECgcJCgAAAA==.Quantar:BAAALgAECgYJCwABLgAECgcJCgAPAAAAAA==.Quickstab:BAAALgAECgcJBwAAAA==.',
Qw='Qwe:BAAALgAECgQJCwAAAA==.',
['Qü']='Qüeenofdeath:BAAALgAECgkJBAAAAA==.',
Ra='Racingdead:BAAALgADCgEJAQAAAA==.Rakshine:BAAALgAECggJCQAAAA==.Rakta:BAAALgAECgcJEAAAAA==.Ramonga:BAAALgAECgkJBgAAAA==.Rancooll:BAABLgAECn8UAAITAAUJQxWzAwAgAQATAAUJQxWzAwAgAQAAAA==.Rasniir:BAACLgAFFH8IAAIFAAMJDgq6SQCTAAAFAAMJDgq6SQCTAAAuAAQKf0sAAgUACQlZIZcFAF4DAAUACQlZIZcFAF4DAAAA.Ravenlash:BAAALgAECgEJBAAAAA==.',
Re='Regna:BAACLgAFFH8eAAIXAAYJ0SZABQAZAgAXAAYJ0SZABQAZAgAuAAQKfzAAAhcACQmaJhgDAH8DABcACQmaJhgDAH8DAAAA.Regner:BAAALgAECgEJAQAAAA==.Reign:BAAALgADCgYJBwAAAA==.Relkon:BAABLgAECn8VAAIbAAcJlQzJLQDwAAAbAAcJlQzJLQDwAAAAAA==.Remaked:BAACLgAFFH8yAAIdAAcJ+x18AwCpAQAdAAcJ+x18AwCpAQAuAAQKf0AAAh0ACQmsIxMEAAgDAB0ACQmsIxMEAAgDAAAA.Remilia:BAABLgAECn87AAIZAAkJ9SJ3AwApAwAZAAkJ9SJ3AwApAwAAAA==.Requinix:BAABLgAECn9oAAIMAAkJXBvTAQBqAgAMAAkJXBvTAQBqAgAAAA==.Retro:BAAALgAECgQJBwAAAA==.Revelatiøn:BAAALgADCgIJAgAAAA==.Revunanto:BAAALgAFFAEJAQAAAA==.Revwrinkle:BAAALgAECgIJAwAAAA==.Rexthedragon:BAAALgADCgEJAQAAAA==.',
Ri='Riasu:BAAALgADCgYJCwAAAA==.Rickyybobbie:BAAALgAECgUJEAAAAA==.Ricochet:BAABLgAECn8hAAIeAAkJ0RC0FgDsAQAeAAkJ0RC0FgDsAQAAAA==.Riptidez:BAAALgADCgcJBgAAAA==.Ririko:BAABLgAECn9AAAMKAAkJFhF8HwDIAQAKAAkJFhF8HwDIAQAZAAEJ9QL7EwAdAAAAAA==.Ritzo:BAABLgAECn8xAAIXAAkJ4hSAHwDzAQAXAAkJ4hSAHwDzAQAAAA==.Rizzla:BAAALgAECgIJAgABLgAECgkJQQAlAHcgAA==.',
Ro='Robval:BAAALgADCgMJAwAAAA==.Rockllobster:BAAALgAECgcJDwAAAA==.Rocksanne:BAAALgAECgEJAQAAAA==.Rockyoysterz:BAAALgAECgMJAwAAAA==.Roguebâit:BAABLgAECn9qAAQBAAkJsiAmAAC+AgABAAkJpiAmAAC+AgACAAcJjBStWQCQAQADAAMJJw3SRACiAAAAAA==.Ronarvinge:BAABLgAECn8VAAIVAAcJCRINggBzAQAVAAcJCRINggBzAQAAAA==.Ronen:BAAALgAECgQJBAAAAA==.',
Ru='Rubywolf:BAAALgAECgYJDgABLgAFFAUJCQAlALsIAA==.Rukkis:BAABLgAECn8qAAMgAAkJFhtgCgB+AgAgAAkJFhtgCgB+AgAoAAEJjQkPJgAtAAAAAA==.Rukâ:BAAALgAECgYJDgAAAA==.Rumi:BAACLgAFFH8kAAIHAAUJ3h7TAABXAQAHAAUJ3h7TAABXAQAuAAQKf0sAAwcACQnrJBMBADUDAAcACQnrJBMBADUDAAgAAQlvEXhuADIAAAAA.',
Ry='Ryeekan:BAABLgAECn8yAAIMAAkJLBXTNQAGAgAMAAkJLBXTNQAGAgAAAA==.',
['Ró']='Róronoà:BAAALgAECgYJCgAAAA==.',
Sa='Saaconse:BAAALgADCgcJBwAAAA==.Saata:BAAALgAECgEJAQAAAA==.Sabrosura:BAACLgAFFH8GAAISAAIJ4wv/kwCMAAASAAIJ4wv/kwCMAAAuAAQKfykAAhIACQlbF/9SANABABIACQlbF/9SANABAAAA.Sacia:BAAALgADCgkJCQABLgAECgYJIgABAMAZAA==.Saelena:BAAALgADCgEJAQAAAA==.Sakheddala:BAAALgAECgQJBAAAAA==.Sancha:BAAALgAECgYJBgAAAA==.Sanosagara:BAABLgAECn9CAAIiAAgJahozGABXAgAiAAgJahozGABXAgAAAA==.Saps:BAAALgADCgIJAgAAAA==.Saraya:BAAALgAECgIJAwAAAA==.Sarithon:BAAALgAECgYJBgAAAA==.Saru:BAAALgADCgkJDQAAAA==.Saruta:BAACLgAFFH8YAAMXAAUJuhrXGABPAQAXAAUJuhrXGABPAQAWAAEJdQMqRwA3AAAuAAQKfzEAAxcACQnxIDEKAMECABcACQnxIDEKAMECABYABQmqDwoWAE4BAAAA.Sath:BAAALgAECgQJBAAAAA==.Sathari:BAABLgAECn86AAIaAAkJDBe5AwBZAQAaAAkJDBe5AwBZAQAAAA==.Satille:BAAALgADCgcJBwAAAA==.Satsuki:BAABLgAECn8iAAMJAAcJfR3QEwBBAgAJAAcJfR3QEwBBAgAZAAUJfxXfNABFAQABLgAFFAUJJwAaAMkcAA==.',
Sc='Scarycat:BAAALgADCgYJBgAAAA==.Schaden:BAAALgAECgEJAQABLgAECggJFAAFAAIhAA==.',
Se='Seijo:BAAALgAECgMJAwAAAA==.Seiryu:BAAALgAECgEJAQAAAA==.Sekk:BAABLgAECn9mAAMSAAkJvCA+AQDLAgASAAkJvCA+AQDLAgARAAYJvRY7GABcAQAAAA==.Selexi:BAAALgADCgYJEAAAAA==.Sereya:BAAALgADCgQJBAABLgAECgEJAQAPAAAAAA==.Sesshanmaru:BAAALgAECgUJCAAAAA==.',
Sg='Sgáil:BAAALgADCgkJCwAAAA==.',
Sh='Shaddai:BAAALgADCgcJFwAAAA==.Shadeofdark:BAACLgAFFH8JAAIIAAMJgRqCBgDQAAAIAAMJgRqCBgDQAAAuAAQKf3kAAggACQllJRwBAHADAAgACQllJRwBAHADAAAA.Shadoshiftt:BAABLgAECn8pAAMlAAkJGQdWQAANAQAlAAkJGQdWQAANAQAFAAgJGALwlwCeAAAAAA==.Shadowstar:BAAALgADCggJBwAAAA==.Shamwowee:BAAALgAECgUJEAAAAA==.Shamzee:BAACLgAFFH8ZAAMGAAUJ3h+MFQC5AQAGAAUJ3h+MFQC5AQAOAAEJrQJvXwAuAAAuAAQKfykAAwYACAnyHekdAF4CAAYACAnyHekdAF4CAA4AAQlWDa+qACwAAAAA.Shandalf:BAABLgAECn8ZAAMCAAYJ1hZMBABPAQACAAYJ5xVMBABPAQADAAQJ1REISwCNAAAAAA==.Shansebaim:BAAALgAECgYJBgAAAA==.Shintok:BAAALgAECggJEQAAAA==.Shuddarun:BAACLgAFFH8iAAIMAAcJnB6iAwBkAQAMAAcJnB6iAwBkAQAuAAQKfywAAgwACQlPIsUDAFQDAAwACQlPIsUDAFQDAAAA.',
Si='Sidera:BAAALgADCgQJAgABLgAECgQJBAAPAAAAAA==.Sify:BAAALgADCgYJBgAAAA==.Simental:BAAALgAECgEJAQAAAA==.Simn:BAABLgAECn8hAAIMAAkJdhooIgBcAgAMAAkJdhooIgBcAgAAAA==.Sindraesong:BAAALgAECggJEgAAAA==.Sinfulpirate:BAAALgADCgQJBAAAAA==.Siyeigon:BAAALgAECgIJBAAAAA==.',
Sk='Skithiryx:BAAALgAECgQJBAABLgAFFAEJAwAPAAAAAA==.Skrai:BAAALgAECgYJCgABLgAECgkJIgANAD4hAA==.',
Sl='Slayvylora:BAACLgAFFH8fAAMSAAcJjBfPDQA8AQASAAYJDhXPDQA8AQATAAEJ+QLFRgBFAAAuAAQKfz0ABBIACQnKIeIWALkCABIACQnKIeIWALkCABMABwkEEs8EAOUAABEAAgn2Fjs4AH4AAAAA.Sleep:BAAALgAECgQJBAABLgAFFAQJCwAUACgMAA==.Slughorn:BAAALgADCgMJAwAAAA==.',
Sm='Smallholy:BAAALgAECgIJBQAAAA==.Smarte:BAABLgAFFH8GAAIeAAUJ1BGCAgBFAQAeAAUJ1BGCAgBFAQAAAA==.Smellgripson:BAAALgAECgIJAgAAAA==.',
Sn='Snazzyjack:BAAALgAECgIJAgAAAA==.Sneakymoth:BAABLgAECn8VAAIgAAYJXxOyLgAoAQAgAAYJXxOyLgAoAQABLgAECgkJLQAVAM0WAA==.Sniff:BAACLgAFFH8FAAIVAAUJwg2dFQAiAQAVAAUJwg2dFQAiAQAuAAQKfysAAhUACAnsHtAuAF0CABUACAnsHtAuAF0CAAEuAAUUBQkGAB4A1BEA.Snookums:BAABLgAECn86AAIaAAgJbBqBMQAAAgAaAAgJbBqBMQAAAgAAAA==.',
So='Soulomon:BAABLgAECn8ZAAICAAkJsRMwgwBUAQACAAkJsRMwgwBUAQAAAA==.Soulsarisen:BAAALgAECgYJDwAAAA==.',
Sp='Spanki:BAAALgADCgkJEAAAAA==.Spellteaser:BAABLgAECn8VAAIVAAYJOhkguQBvAQAVAAYJOhkguQBvAQAAAA==.Spicymaker:BAABLgAECn8mAAIWAAgJ5yBkCQBZAgAWAAgJ5yBkCQBZAgAAAA==.Spiritual:BAAALgADCgIJAgAAAA==.',
St='Starar:BAAALgAECgMJCgAAAA==.Steelheart:BAAALgAECgEJCgAAAA==.Steviathan:BAAALgADCgQJBAAAAA==.Stolensøul:BAAALgADCgkJDgAAAA==.Strifewood:BAABLgAECn8cAAIbAAkJWhhKFQDDAQAbAAkJWhhKFQDDAQAAAA==.Stumper:BAABLgAECn9BAAIlAAkJdyDSAABLAgAlAAkJdyDSAABLAgAAAA==.',
Su='Sugondese:BAAALgAECgQJBgAAAA==.Suluna:BAAALgAECgUJCgABLgAECgkJSAAGAOYdAA==.Summêr:BAABLgAECn8YAAIiAAYJ2wgpbQDPAAAiAAYJ2wgpbQDPAAAAAA==.Suri:BAAALgAECgUJCgABLgAECggJGAANADkZAA==.Sux:BAABLgAECn8fAAIjAAkJ4A85AwAMAQAjAAkJ4A85AwAMAQAAAA==.',
Sy='Sybrina:BAACLgAFFH8GAAIMAAIJEQzXIwCdAAAMAAIJEQzXIwCdAAAuAAQKfxwAAgwACQkuFAE3AAICAAwACQkuFAE3AAICAAAA.Sylvia:BAAALgADCgcJBgABLgAECgEJAQAPAAAAAA==.Synevra:BAAALgADCggJFgAAAA==.Syngeance:BAABLgAECn81AAIMAAYJ4QvNnQAGAQAMAAYJ4QvNnQAGAQAAAA==.Synèsterwolf:BAAALgAECgIJAwABLgAFFAUJCQAlALsIAA==.',
['Sí']='Síf:BAAALgAECgcJDQAAAA==.',
Ta='Tabernacle:BAAALgAECgUJBQAAAA==.Tadeusz:BAABLgAECn8aAAIgAAkJ1xeTDABdAgAgAAkJ1xeTDABdAgAAAA==.Tamamò:BAABLgAECn8bAAIiAAcJOxKPKABvAQAiAAcJOxKPKABvAQAAAA==.Tarrok:BAAALgADCgMJBwAAAA==.',
Te='Tealleth:BAAALgADCgMJAwAAAA==.Telana:BAABLgAECn8TAAIoAAQJshAlAQCvAAAoAAQJshAlAQCvAAAAAA==.Tepache:BAAALgADCgEJAQABLgAFFAEJAwAPAAAAAA==.Tequitos:BAABLgAECn8mAAMTAAkJTBMqGgA0AgATAAkJTBMqGgA0AgASAAYJ7gtV2gDlAAAAAA==.Teranin:BAABLgAECn8UAAIlAAcJPwj+SgDgAAAlAAcJPwj+SgDgAAAAAA==.',
Tf='Tfortyone:BAAALgAECgYJCQAAAA==.',
Th='Tharbad:BAAALgADCgEJBQAAAA==.Thchosen:BAAALgAECgMJBAAAAA==.Theduk:BAAALgAECgQJBQAAAA==.Thorae:BAAALgADCgEJAQAAAA==.Thorias:BAACLgAFFH8YAAIVAAUJxR7OEwAyAQAVAAUJxR7OEwAyAQAuAAQKf0sAAhUACQnNJR4EAGgDABUACQnNJR4EAGgDAAAA.Thunderwalkr:BAAALgAECgEJAgAAAA==.',
Ti='Tiren:BAAALgAECgYJDQAAAA==.',
To='Torag:BAAALgAECgQJBAAAAA==.Torment:BAABLgAECn9wAAIbAAkJ5iDCBADkAgAbAAkJ5iDCBADkAgAAAA==.Tosti:BAAALgAECgkJAQAAAA==.',
Tr='Trepania:BAACLgAFFH8aAAIKAAYJRwtaDwBcAQAKAAYJRwtaDwBcAQAuAAQKfy8AAgoACQngGdEWACUCAAoACQngGdEWACUCAAAA.Tristén:BAABLgAECn8bAAIMAAgJ6Rn8BQB1AQAMAAgJ6Rn8BQB1AQAAAA==.Trogdoor:BAAALgAECgEJAQAAAA==.Trollycarp:BAABLgAECn8gAAMSAAkJQwq3vwAJAQASAAkJAgS3vwAJAQARAAUJdhDnLAC4AAAAAA==.Truvie:BAABLgAECn8VAAISAAYJHQwLEwCdAAASAAYJHQwLEwCdAAAAAA==.',
Tu='Tumbler:BAABLgAECn8XAAMGAAgJix0bHABrAgAGAAgJix0bHABrAgAOAAMJCBHGcgCTAAAAAA==.Tumbles:BAAALgAECgUJBwAAAA==.Tumni:BAABLgAECn9AAAMOAAgJCgwLQQAwAQAOAAgJCgwLQQAwAQAGAAYJdAwqeAD2AAAAAA==.',
Tw='Twinkletoes:BAAALgADCgIJAgAAAA==.Twylah:BAAALgADCgIJAgAAAA==.',
['Tá']='Táelah:BAABLgAECn8jAAIeAAkJRxFKFgDvAQAeAAkJRxFKFgDvAQAAAA==.Tángall:BAAALgAECgUJBQAAAA==.',
Ul='Ulnuk:BAACLgAFFH8XAAIGAAQJSh2xJQBUAQAGAAQJSh2xJQBUAQAuAAQKf0YAAgYACQnqIvUAAJ4CAAYACQnqIvUAAJ4CAAAA.Ulster:BAAALgAECgIJAwAAAA==.',
Un='Unholyshan:BAAALgAECgEJAQABLgAECgYJGQACANYWAA==.Unidus:BAAALgAECgYJBwAAAA==.',
Up='Uphellyaa:BAAALgADCgUJBQABLgAECgQJBAAPAAAAAA==.',
Ur='Urwelcome:BAAALgAECgcJBwAAAA==.',
Va='Vadka:BAABLgAECn8aAAITAAgJZRm2GwAmAgATAAgJZRm2GwAmAgAAAA==.Vaexxi:BAAALgAECgUJBgAAAA==.Vaha:BAABLgAECn8nAAMGAAcJMw1ZBwD+AAAGAAYJEw5ZBwD+AAAOAAYJnQf1ZwCvAAAAAA==.Vairian:BAABLgAECn8ZAAIIAAcJqQ8fLAAgAQAIAAcJqQ8fLAAgAQAAAA==.Valkree:BAABLgAECn8eAAISAAYJeRAfCgAFAQASAAYJeRAfCgAFAQAAAA==.Vallae:BAAALgADCgkJEQABLgAECgkJSAAGAOYdAA==.Valsavis:BAABLgAECn9NAAIHAAkJtxy9BABsAgAHAAkJtxy9BABsAgAAAA==.Valtier:BAABLgAECn8WAAMlAAgJ8BdOIQC+AQAlAAcJNRlOIQC+AQAFAAQJyBemXwAXAQAAAA==.Vampirä:BAABLgAECn8iAAQFAAkJQQVbhgCrAAAFAAgJAgRbhgCrAAAmAAQJngXhOAB2AAAlAAIJrgMxhwA8AAAAAA==.Vanyelle:BAAALgAECgQJBAAAAA==.Varactor:BAAALgAECgMJAwAAAA==.Vasarah:BAAALgAECgEJAQAAAA==.Vashidan:BAABLgAECn8YAAIhAAgJ7iA1CAD3AgAhAAgJ7iA1CAD3AgAAAA==.',
Ve='Velenar:BAAALgADCgIJAgAAAA==.Velisandre:BAAALgADCgcJIgAAAA==.Vellagosa:BAAALgAECgcJCgAAAA==.Vellini:BAAALgAECgEJAQABLgAECgcJIAAJAG4eAA==.Vernice:BAAALgAECgEJAQABLgAECgYJIgABAMAZAA==.Verulan:BAABLgAECn8gAAQlAAgJtQp6OQAtAQAlAAgJ1Al6OQAtAQAFAAQJjAojkwCOAAAmAAEJKA5sVAAwAAAAAA==.Vexeh:BAAALgAECgYJCgAAAA==.Vexomous:BAABLgAECn8WAAIeAAcJuh/OAAD5AQAeAAcJuh/OAAD5AQAAAA==.',
Vi='Vierilan:BAAALgADCgcJBwAAAA==.Vierina:BAAALgAECgEJAQAAAA==.Vikss:BAABLgAECn8zAAMMAAkJ0xJNRQDSAQAMAAkJ0xJNRQDSAQAeAAYJXQQsHQAFAQAAAA==.Viledk:BAAALgAECgUJBgAAAA==.Viserian:BAAALgAECgUJEQAAAA==.Vivenna:BAAALgAECgEJAQAAAA==.Vivien:BAAALgADCgYJBgABLgAECgEJAQAPAAAAAA==.',
Vl='Vll:BAABLgAECn8gAAImAAcJ6x9tCABYAgAmAAcJ6x9tCABYAgABLgAECggJIgAIAO4iAA==.',
Vo='Voidmayne:BAABLgAECn8/AAISAAkJjBGyVQDJAQASAAkJjBGyVQDJAQAAAA==.Vongogh:BAAALgADCgEJAQAAAA==.Vonhelsing:BAAALgAECgYJEwAAAA==.Vorcan:BAAALgADCgMJBgAAAA==.Vorenius:BAAALgADCgEJAQAAAA==.Voxella:BAAALgAECgQJBAAAAA==.',
Vr='Vrel:BAAALgADCgkJDgAAAA==.',
Vy='Vynnara:BAAALgAECgcJDgABLgAECgcJIAAJAG4eAA==.Vyv:BAABLgAECn8UAAIOAAcJtAUlWwDTAAAOAAcJtAUlWwDTAAAAAA==.Vyvboo:BAAALgADCgcJBwAAAA==.Vyvish:BAAALgADCgUJBQAAAA==.',
['Vö']='Vöid:BAABLgAECn8ZAAIaAAYJEhyzTQC+AQAaAAYJEhyzTQC+AQAAAA==.',
Wa='Warlogic:BAAALgAECgQJBAAAAA==.Warwounds:BAAALgAECgEJAQAAAA==.Wayadra:BAABLgAECn8XAAQQAAkJkSGlBwDdAgAQAAkJkSGlBwDdAgAkAAcJSQTlJgDrAAAYAAEJlgrESQAvAAAAAA==.',
We='Weiand:BAABLgAECn8wAAMSAAkJUhtaNwAkAgASAAgJpxpaNwAkAgATAAEJOwejiwAzAAAAAA==.Welil:BAAALgAECgUJCwAAAA==.',
Wh='Whachah:BAAALgAECgQJCAAAAA==.Whatami:BAACLgAFFH8LAAQDAAQJNw9bFACYAAACAAQJTwmAYwAAAQADAAIJGRJbFACYAAABAAEJHgj1KABFAAAuAAQKfzEABAIACQkMHRUBAIICAAIACQkMHRUBAIICAAMAAgnvD39XAGgAAAEAAQkAAA4xADwAAAAA.Wholemilk:BAABLgAECn8rAAIaAAkJvSByDQDaAgAaAAkJvSByDQDaAgAAAA==.',
Wi='Wiggz:BAAALgAECgcJCgAAAA==.Wilhellena:BAABLgAECn9GAAIKAAkJEB9XBgANAwAKAAkJEB9XBgANAwAAAA==.Wilhellfu:BAAALgAECgMJBwAAAA==.Winariel:BAAALgAFFAEJAgAAAA==.Wisteria:BAAALgAECgEJAQABLgABCgEJAQAPAAAAAA==.',
Wr='Wrathsoul:BAAALgAECgEJAQABLgAECgEJAwAPAAAAAA==.Wrecksoul:BAAALgAECgEJAQABLgAECgEJAwAPAAAAAA==.Writhesoul:BAAALgAECgEJAwAAAA==.Wroughtsoul:BAAALgAECgQJAgAAAA==.Wrëckagë:BAAALgAECgcJEwAAAA==.',
Wu='Wumbo:BAAALgAECgYJBwAAAA==.',
Xa='Xaiea:BAAALgADCgcJBwAAAA==.Xalatath:BAAALgAECgEJAQAAAA==.Xaldred:BAABLgAECn8kAAICAAkJOBLBRgDGAQACAAkJOBLBRgDGAQAAAA==.Xandir:BAABLgAECn9CAAIRAAkJexN5EgCfAQARAAkJexN5EgCfAQAAAA==.Xarhunt:BAAALgAECgYJEQAAAA==.Xaric:BAABLgAECn8nAAIFAAkJXhlRJwAWAgAFAAkJXhlRJwAWAgAAAA==.',
Xe='Xella:BAAALgAECgQJBAAAAA==.',
Xu='Xueshi:BAAALgAECgEJAQAAAA==.',
Xy='Xyal:BAABLgAECn88AAMKAAkJaSLMBwDxAgAKAAkJaSLMBwDxAgAZAAEJ8wjnkQApAAAAAA==.Xyp:BAAALgAECgEJAQABLgAECggJIAAlALUKAA==.',
Yg='Ygor:BAAALgAFFAEJAQAAAA==.',
Yi='Yiago:BAABLgAECn8lAAIXAAYJmAdwBwC7AAAXAAYJmAdwBwC7AAAAAA==.',
Yo='Yobabydaddy:BAAALgAECgMJAwAAAA==.Youknow:BAAALgAECgUJCQAAAA==.',
Yu='Yumiisaki:BAAALgAECgQJBAAAAA==.Yungslug:BAAALgAECgcJCQAAAA==.',
Za='Zahel:BAAALgADCgYJEgAAAA==.Zangbus:BAAALgADCgcJFAAAAA==.Zany:BAAALgAECgEJAQAAAA==.Zaranorinn:BAABLgAECn8dAAISAAkJ0AebmABEAQASAAkJ0AebmABEAQAAAA==.Zaxhdk:BAEBLgAECn8vAAMEAAkJ1BonJwBmAgAEAAkJ1BonJwBmAgAbAAUJTwbCRAB8AAAAAA==.Zaxhmonk:BAEALgADCgkJCQABLgAECgkJLwAEANQaAA==.',
Ze='Zedex:BAAALgADCgcJCAABLgADCggJDQAPAAAAAA==.Zedru:BAAALgADCggJDQAAAA==.Zenstormer:BAAALgADCgQJBAABLgAECgUJEAAPAAAAAA==.Zephril:BAAALgADCgEJAQAAAA==.Zephyrion:BAAALgAECgQJCwAAAA==.Zerfällt:BAAALgADCgYJCwAAAA==.Zerrus:BAABLgAECn8VAAIEAAYJfx0ijABMAQAEAAYJfx0ijABMAQAAAA==.',
Zh='Zhoryn:BAAALgAECgYJDQAAAA==.',
Zi='Zilvra:BAABLgAECn8hAAIGAAkJ+hc9JgApAgAGAAkJ+hc9JgApAgAAAA==.Zinrar:BAABLgAECn8qAAIEAAkJ/RmjKABfAgAEAAkJ/RmjKABfAgAAAA==.Zipagain:BAAALgADCgQJBAAAAA==.Ziparoo:BAABLgAECn8wAAIVAAcJqAisvAAPAQAVAAcJqAisvAAPAQAAAA==.Zittizle:BAAALgAECgEJAQAAAA==.',
Zr='Zraven:BAABLgAECn83AAMeAAkJKhYyEgAXAgAeAAkJYhUyEgAXAgAMAAEJKRoJGwFBAAAAAA==.',
Zu='Zushi:BAAALgAFFAIJAgAAAA==.',
['Äl']='Älphawolf:BAACLgAFFH8JAAIlAAUJuwisLQDRAAAlAAUJuwisLQDRAAAuAAQKfykABCUACQnNGA4dAOABACUACQkRFg4dAOABACMABQn2FCYjADcBAAUAAgl2CM+/AEYAAAAA.',
['Ðê']='Ðêmønicßløøð:BAABLgAECn8XAAIEAAgJWxTBXACxAQAEAAgJWxTBXACxAQAAAA==.',
['ßy']='ßyrøßløøð:BAAALgAECgUJBQAAAA==.',
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
