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
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aabbigale:BAAALgAECgkJBwAAAA==.Aarar:BAAALgADCgIJAgAAAA==.',
Ab='Abigt:BAABLgAECn8YAAMBAAcJDiAGCADrAQABAAcJDiAGCADrAQACAAQJexGexQDOAAAAAA==.',
Ad='Adalaidê:BAAALgAECgcJEwAAAA==.Adu:BAAALgAECgEJAQAAAA==.',
Ae='Aelusion:BAACLgAFFH8GAAICAAMJ3xYKcADiAAACAAMJ3xYKcADiAAAuAAQKfx8ABAIACAlIHzwaALcCAAIACAmBHjwaALcCAAMAAwlaIRUsAA4BAAEAAQlAJCInAFUAAAEuAAUUBQkNAAQAwhUA.Aeluu:BAAALgAECgcJBwABLgAECggJHwAFALgRAA==.Aerola:BAAALgADCgIJAgAAAA==.Aerynne:BAABLgAECn8cAAMDAAYJYAxXIwCWAAADAAUJOwtXIwCWAAACAAMJlApwEgCHAAAAAA==.',
Ai='Aidén:BAAALgAECgEJAQAAAA==.Ailis:BAAALgAECgQJBAAAAA==.Airie:BAABLgAECn8+AAIGAAkJRxNEJgApAgAGAAkJRxNEJgApAgAAAA==.Aita:BAACLgAFFH8XAAIHAAUJAhd2BQASAQAHAAUJAhd2BQASAQAuAAQKfyQAAwcACQnXGO4GAB0CAAcACQnXGO4GAB0CAAgABgnSCpREAKQAAAAA.',
Ak='Akuso:BAAALgADCgYJCAAAAA==.',
Al='Alassa:BAAALgADCgQJBAAAAA==.Alayro:BAAALgAECgcJCQAAAA==.Alejandrø:BAAALgADCgUJBgAAAA==.Alisaa:BAAALgAECgUJCQAAAA==.Alistanë:BAAALgAECgUJCQAAAA==.Allegria:BAAALgAECgEJAgAAAA==.Alluna:BAAALgAECgYJCgAAAA==.Alondra:BAABLgAECn8gAAIDAAkJvB82AgCgAgADAAkJvB82AgCgAgAAAA==.Alulà:BAABLgAECn8gAAMJAAcJbh6nEgBOAgAJAAcJTB6nEgBOAgAKAAMJMx4lTQAEAQAAAA==.Aluucard:BAAALgADCgUJBQAAAA==.Aluuni:BAABLgAECn8nAAILAAkJiBc7CABDAgALAAkJiBc7CABDAgAAAA==.',
Am='Amednato:BAAALgAECgcJDgABLgAECgkJJQAMABkhAA==.Amo:BAAALgAECgIJAgABLgAECggJGAANAGIZAA==.Améthyst:BAAALgADCgkJCQAAAA==.',
An='Anaeli:BAABLgAECn9IAAMGAAkJ5h29EgC3AgAGAAkJ5h29EgC3AgAOAAUJ9wjmbgCdAAAAAA==.Anariel:BAAALgADCgUJBQABLgAECgQJBAAPAAAAAA==.Ancalagonn:BAABLgAECn8ZAAIQAAYJDxT+AwAhAQAQAAYJDxT+AwAhAQABLgAECgkJIwAGAMEPAA==.Androth:BAABLgAECn8oAAMRAAkJnhuvCgAfAgARAAkJnhuvCgAfAgASAAMJpQqEHQGWAAAAAA==.Angelius:BAAALgAECgEJBgAAAA==.Angita:BAAALgAECgYJCQAAAA==.Antipæn:BAACLgAFFH8kAAMTAAUJ7yKGAwDjAQATAAUJ7yKGAwDjAQASAAMJChumaADdAAAuAAQKf00AAxIACQmfJjgBAIYDABIACQmfJjgBAIYDABMABwmoIvcpAOIBAAAA.',
Ap='Apologia:BAABLgAECn87AAISAAkJsCK6DQD3AgASAAkJsCK6DQD3AgAAAA==.',
Aq='Aquaphobic:BAAALgADCgEJAQAAAA==.Aquleynta:BAAALgADCgEJAQAAAA==.',
Ar='Arcainus:BAAALgADCgIJAgAAAA==.Arcanix:BAABLgAECn8UAAIUAAcJxglHGQAKAQAUAAcJxglHGQAKAQAAAA==.Arceé:BAAALgAECgMJBwAAAA==.Archaic:BAABLgAECn85AAIVAAkJvxGcVQDcAQAVAAkJvxGcVQDcAQAAAA==.Ardicelia:BAAALgAECgUJBwAAAA==.Ares:BAACLgAFFH8bAAMWAAgJfSBsBAA/AgAWAAgJfSBsBAA/AgAXAAIJCB71FgCuAAAuAAQKfyEAAxYACAlRJOUBABoDABYACAnfI+UBABoDABcABwlHIjMZAIICAAAA.Argomir:BAAALgAECgEJAQAAAA==.Ariellä:BAAALgADCgEJAQAAAA==.Arifault:BAAALgAECgMJAwABLgAECgkJSAAGAOYdAA==.Arilynx:BAABLgAECn8iAAIYAAkJ4AesFwBWAQAYAAkJ4AesFwBWAQAAAA==.Arlynn:BAAALgADCgcJBwAAAA==.Armorgorden:BAABLgAECn9lAAINAAkJwCTjAQA3AwANAAkJwCTjAQA3AwAAAA==.Aroviaa:BAABLgAECn9GAAQKAAkJVh5BCADnAgAKAAkJVh5BCADnAgAZAAEJHhGFggA4AAAJAAEJ9gPXhwAjAAAAAA==.Arpmek:BAABLgAECn85AAIaAAkJuhU2CAAhAQAaAAkJuhU2CAAhAQAAAA==.Artemîs:BAAALgAECgQJBwAAAA==.Arydynn:BAAALgADCgIJAgAAAA==.',
As='Ashal:BAABLgAECn8nAAMXAAcJ5A3sRAAyAQAXAAcJ+AvsRAAyAQANAAcJQw22JgD9AAAAAA==.Ashlynne:BAABLgAECn8YAAMNAAgJYhkkFwCKAQANAAcJ/hokFwCKAQAXAAgJMAtLPABUAQAAAA==.Astrotoad:BAAALgAECgUJCgAAAA==.Astrìd:BAAALgADCgIJAgAAAA==.',
Au='Auntmary:BAAALgADCgYJCAAAAA==.Auramaximus:BAAALgAECgYJBwAAAA==.Aurtt:BAABLgAECn9LAAIbAAkJkBe8EgDkAQAbAAkJkBe8EgDkAQAAAA==.',
Av='Avanel:BAAALgAECgEJAgAAAA==.Avidae:BAAALgADCgcJCAAAAA==.',
Ay='Ayther:BAAALgADCggJCAAAAA==.',
Az='Azkadelia:BAAALgAECgEJAQAAAA==.',
Ba='Bageera:BAABLgAECn8vAAIFAAkJXR7HCgAQAwAFAAkJXR7HCgAQAwAAAA==.Bahahaknight:BAABLgAECn9FAAIbAAkJniCCBQDQAgAbAAkJniCCBQDQAgAAAA==.Bandidos:BAAALgAECgUJCQAAAA==.Barccky:BAAALgAECgIJAgAAAA==.Barcy:BAAALgAECgEJAwABLgAECgIJAgAPAAAAAA==.Barnette:BAACLgAFFH8WAAIcAAUJZgi1AQDrAAAcAAUJZgi1AQDrAAAuAAQKf0oAAhwACQlCGRUCAFYCABwACQlCGRUCAFYCAAAA.Bashdown:BAAALgADCgEJAQAAAA==.Basic:BAAALgADCgEJAQAAAA==.',
Be='Bearmissile:BAAALgAFFAIJAwAAAA==.Bearyy:BAAALgADCgQJBAAAAA==.Belthos:BAABLgAECn87AAISAAkJ4x1iGgCmAgASAAkJ4x1iGgCmAgAAAA==.Benjofamin:BAAALgAECgEJAQAAAA==.Berristan:BAACLgAFFH8LAAITAAMJkg52MgCoAAATAAMJkg52MgCoAAAuAAQKfzAAAxMACQkZGKIMALUCABMACQkZGKIMALUCABIABwnnCLrYAOcAAAAA.Bestwingman:BAAALgAECgEJAQAAAA==.',
Bg='Bgdaddyjupes:BAAALgADCgQJBAAAAA==.',
Bi='Bigdawgsteve:BAAALgAECgQJBAAAAA==.Bigmarv:BAABLgAECn8gAAIOAAgJ6helMwBtAQAOAAgJ6helMwBtAQAAAA==.Bigsam:BAAALgAECgEJAQAAAA==.Bittytigs:BAAALgAECgQJBAAAAA==.',
Bl='Blossom:BAACLgAFFH8MAAIYAAUJww1tFwAfAQAYAAUJww1tFwAfAQAuAAQKfxUAAhgACAmdEY8YAM4BABgACAmdEY8YAM4BAAAA.Bluespruce:BAAALgAECgcJDQAAAA==.Bluewitchpa:BAABLgAECn8XAAISAAUJlwkBGgCkAAASAAUJlwkBGgCkAAAAAA==.',
Bo='Boomboomkill:BAAALgADCgEJAQAAAA==.Bosc:BAABLgAECn87AAIbAAkJYR/NAACmAgAbAAkJYR/NAACmAgABLgAECggJHQAdAP0SAA==.Boudiicca:BAABLgAECn8oAAIKAAYJmRTVBAAvAQAKAAYJmRTVBAAvAQAAAA==.Boxmasterr:BAABLgAECn88AAMBAAkJaxD9AQA2AQACAAkJFwzsWgCNAQABAAcJsBL9AQA2AQAAAA==.',
Br='Brasmir:BAABLgAECn8tAAIeAAkJVxNVAQDcAQAeAAkJVxNVAQDcAQAAAA==.Bremerton:BAAALgAECgYJEQAAAA==.Brianzero:BAAALgAECgEJAQAAAA==.Brino:BAAALgAECgEJAQAAAA==.Brinotriage:BAAALgAECgUJBwAAAA==.',
Bu='Bubblement:BAAALgAFFAUJEwAAAQ==.Bubblemoth:BAAALgAECggJEQABLgAECgkJLgAVAM0WAA==.Bulge:BAABLgAFFH8NAAIVAAMJTQ9vLwDFAAAVAAMJTQ9vLwDFAAABLgAFFAYJHQAEAKIXAA==.Bulgogi:BAACLgAFFH8dAAIEAAYJohfiOgCEAQAEAAYJohfiOgCEAQAuAAQKfzoAAgQACQnqIaoNAP8CAAQACQnqIaoNAP8CAAAA.Bushalabong:BAAALgAECgMJBAAAAA==.Butherrface:BAAALgAECgQJBAAAAA==.',
Bw='Bwonsmashdi:BAAALgADCgUJBgABLgAECgEJAQAPAAAAAA==.',
['Bì']='Bìjou:BAAALgAECgQJBAABLgAECggJGAANAGIZAA==.',
['Bù']='Bùb:BAAALgADCgEJAQAAAA==.',
Ca='Cafo:BAAALgADCgYJDAAAAA==.Capy:BAACLgAFFH8UAAQeAAUJ3yI8DwBKAQAeAAQJ7B88DwBKAQAMAAQJ/h2gMwBGAQAfAAEJAACWPgAAAAAuAAQKfzwABAwACQmHI0spADkCAB4ACAnqH+kNAEkCAAwACAn9IUspADkCAB8ABgmIF1YyAKUBAAAA.Cardran:BAAALgADCgEJAQABLgAECgkJKAARAJ4bAA==.Carkusw:BAAALgAECgMJBwAAAA==.Cassyn:BAABLgAECn8YAAITAAgJ3yHWBwDwAgATAAgJ3yHWBwDwAgAAAA==.Catamay:BAABLgAECn8gAAIaAAkJxRmTKgAfAgAaAAkJxRmTKgAfAgABLgAECgEJAgAPAAAAAA==.Catprincess:BAABLgAECn8fAAIFAAgJuBF+OwC3AQAFAAgJuBF+OwC3AQAAAA==.Cayda:BAAALgADCgYJBgAAAA==.Caylara:BAABLgAECn8wAAIgAAgJ1BYvAQD/AQAgAAgJ1BYvAQD/AQAAAA==.Cayssaber:BAAALgADCgEJAQAAAA==.',
Ce='Celrythis:BAABLgAECn8dAAIaAAYJgg8bmgDtAAAaAAYJgg8bmgDtAAAAAA==.',
Ch='Chai:BAABLgAECn8cAAIhAAkJuxOOAgBrAQAhAAkJuxOOAgBrAQAAAA==.Chaintrain:BAAALgAECgEJAgABLgAECgkJLAADAE0fAA==.Chewglass:BAAALgADCggJCAAAAA==.Chiji:BAABLgAECn8nAAIdAAkJSBRpFwDuAQAdAAkJSBRpFwDuAQAAAA==.Chioma:BAAALgAECgYJCwAAAA==.',
Ci='Cindrethal:BAAALgADCggJCAAAAA==.',
Cl='Claes:BAAALgAECgEJBgABLgAECggJHQAdAP0SAA==.Clayler:BAAALgADCgQJBAAAAA==.Cleõ:BAAALgADCggJCwAAAA==.Clipperz:BAAALgAECgMJBAAAAA==.Clonetrooper:BAAALgAFFAIJAwAAAA==.Clorox:BAAALgADCgEJAQAAAA==.',
Co='Coocoohead:BAAALgAECgMJBQAAAA==.Coofus:BAABLgAFFH8GAAIOAAIJ1AExUwBIAAAOAAIJ1AExUwBIAAAAAA==.Coralorchid:BAABLgAECn8yAAMRAAgJvxMjFwBoAQARAAcJJRUjFwBoAQASAAcJyA/OngA5AQAAAA==.Corrupt:BAAALgAECgEJAQABLgAECgMJCAAPAAAAAA==.',
Cp='Cptdarkk:BAABLgAECn8ZAAISAAcJUwuEuAATAQASAAcJUwuEuAATAQAAAA==.',
Cr='Crytal:BAAALgAECgMJBAAAAA==.',
Cu='Cuddlebucket:BAAALgADCgQJBQAAAA==.Curissan:BAABLgAECn8jAAIOAAkJrxnoEwBMAgAOAAkJrxnoEwBMAgAAAA==.',
Cy='Cyg:BAAALgADCgEJAQAAAA==.',
['Cè']='Cères:BAABLgAECn8UAAIFAAgJAiEvFQCgAgAFAAgJAiEvFQCgAgAAAA==.',
['Cø']='Cøndemn:BAAALgAECgYJCAAAAA==.',
Da='Daemyn:BAAALgADCgcJBwAAAA==.Dahl:BAAALgAECgEJAQABLgAECgkJIQAeANEQAA==.Daladalian:BAAALgAECgMJAwAAAA==.Dalir:BAABLgAECn8cAAIEAAgJvhp0NAAtAgAEAAgJvhp0NAAtAgAAAA==.Dalruend:BAAALgADCgYJCwABLgAFFAkJIQAiAD8QAA==.Dalspin:BAACLgAFFH8hAAIiAAkJPxCgDwAWAgAiAAkJPxCgDwAWAgAuAAQKfy8ABCIACQn2HdwHANkCACIACQn2HdwHANkCACEABwm8ElYqAIoBAB0ACAnNBykFALUAAAAA.Dalthepal:BAABLgAECn8VAAITAAgJ1R2pHgAiAgATAAgJ1R2pHgAiAgABLgAFFAkJIQAiAD8QAA==.Darassa:BAAALgAECgEJAQAAAA==.Darka:BAAALgADCgYJFgAAAA==.Davidline:BAACLgAFFH8jAAISAAUJiCFhDABWAQASAAUJiCFhDABWAQAuAAQKf0wAAhIACQmMJoABAIEDABIACQmMJoABAIEDAAAA.Davidshaman:BAAALgAECgcJBwAAAA==.Dawnfist:BAAALgAECgQJBAAAAA==.',
De='Deadish:BAAALgAECgYJCwAAAA==.Deathsaberss:BAABLgAECn8qAAIWAAkJABgHDwD9AQAWAAkJABgHDwD9AQAAAA==.Deathstealer:BAAALgAECgIJAwAAAA==.Deathszen:BAAALgAECgcJEQAAAA==.Debauch:BAABLgAECn8cAAICAAkJPw9LTgCwAQACAAkJPw9LTgCwAQAAAA==.Deight:BAAALgAECgEJAQAAAA==.Dejamoo:BAAALgADCgcJBgAAAA==.Demonkayk:BAAALgADCgkJDgAAAA==.Dendraculus:BAAALgADCgYJCgAAAA==.Dennathor:BAAALgADCgYJCAAAAA==.Denniah:BAAALgAECgQJBQAAAA==.Derke:BAAALgAECgQJBwAAAA==.Destinee:BAAALgAECgEJAQAAAA==.',
Di='Didudietho:BAAALgAECgUJBQABLgAFFAMJBQASANMJAA==.Diladrin:BAACLgAFFH8nAAIjAAUJEhDlCgCwAAAjAAUJEhDlCgCwAAAuAAQKf0sAAiMACQnDHKsGAJECACMACQnDHKsGAJECAAAA.Diode:BAACLgAFFH8fAAQEAAYJ7xTbSwBbAQAEAAUJfBHbSwBbAQAUAAQJBBOYEAASAQAbAAEJAADcVwAAAAAuAAQKfzEAAwQACQlyIDUYAOoCAAQACAn8IDUYAOoCABQACQnmG/IGAC8CAAAA.Dirtymack:BAAALgAECgMJAwABLgAECgcJJwAaANYeAA==.Diyla:BAAALgAECgEJAgAAAA==.Dizzy:BAAALgAECgIJAgAAAA==.',
Do='Doileag:BAABLgAECn86AAISAAgJnQ0eCgBHAQASAAgJnQ0eCgBHAQAAAA==.Domer:BAAALgAECgYJCAAAAA==.Doomsong:BAAALgADCgYJCgAAAA==.Dora:BAAALgAECgMJAwAAAA==.Dottmatrix:BAABLgAECn8lAAIDAAcJzxAMAwD2AAADAAcJzxAMAwD2AAAAAA==.',
Dr='Drachnia:BAAALgAECgQJBAAAAA==.Dragønbreath:BAACLgAFFH8MAAMVAAUJHAkxcAABAQAVAAUJHAkxcAABAQAcAAEJaANLCAAzAAAuAAQKfx0AAxwACQlxGhcCAEoCABwACAnMFxcCAEoCABUACAk3FW+1ABkBAAAA.Dreadwing:BAABLgAECn8mAAIEAAYJMxSJCQAyAQAEAAYJMxSJCQAyAQAAAA==.',
Du='Duf:BAACLgAFFH8jAAIdAAcJfx3pEACeAQAdAAcJfx3pEACeAQAuAAQKfy8AAh0ACQmEHyQPAEkCAB0ACQmEHyQPAEkCAAAA.Dunso:BAAALgADCgYJAQAAAA==.Dustbunny:BAABLgAECn9PAAIKAAkJPSCbBgAJAwAKAAkJPSCbBgAJAwAAAA==.',
Dw='Dwagon:BAAALgAFFAIJAgAAAA==.',
Dy='Dylsonlolqt:BAAALgADCgIJAQAAAA==.',
['Dæ']='Dæmôn:BAAALgAECgYJCQAAAA==.',
['Dó']='Dóómkin:BAAALgADCgEJAQAAAA==.',
['Dû']='Dûn:BAACLgAFFH8RAAMhAAMJdCBdFgANAQAhAAMJdCBdFgANAQAdAAEJNQ3uGABGAAAuAAQKfzEAAx0ACQkpGzAPAEgCAB0ACQkpGzAPAEgCACEAAgmkGCFgAI8AAAAA.Dûna:BAACLgAFFH8HAAIZAAIJVR0SLQCWAAAZAAIJVR0SLQCWAAAuAAQKfyUAAhkACAkBIccNAHgCABkACAkBIccNAHgCAAEuAAUUAwkRACEAdCAA.',
Ea='Eastwind:BAAALgAECgEJAQAAAA==.',
Ei='Eira:BAAALgADCggJDQAAAA==.',
El='Elaatia:BAABLgAECn9LAAISAAkJQSR0BwAyAwASAAkJQSR0BwAyAwAAAA==.Elduar:BAAALgADCgEJAQAAAA==.Elidria:BAAALgADCgYJBgAAAA==.Elimental:BAABLgAECn8gAAIOAAgJYxInMQB6AQAOAAgJYxInMQB6AQAAAA==.Elketha:BAAALgAECgUJBQABLgAFFAUJJwAaAMkcAA==.Ellaring:BAAALgAECgYJCAABLgAECgcJDwAPAAAAAA==.Elle:BAAALgADCgcJBwAAAA==.Elleanna:BAAALgADCgcJBwAAAA==.Elrondd:BAAALgADCgEJAQABLgAECgkJLwAFAF0eAA==.Elrric:BAABLgAECn8WAAIEAAkJQgx2iQBRAQAEAAkJQgx2iQBRAQAAAA==.Elryck:BAAALgADCgYJBgAAAA==.',
En='Endora:BAAALgADCggJDQAAAA==.Enezath:BAAALgADCgYJBgAAAA==.',
Er='Erakron:BAABLgAECn80AAMGAAgJ3h+tEADKAgAGAAgJ3h+tEADKAgAOAAgJchVHMgB0AQAAAA==.Eriko:BAAALgADCgkJEAAAAA==.Erine:BAAALgAECgQJBAAAAA==.Erouvi:BAAALgAECgEJAQABLgAECgkJRgAKAFYeAA==.Eroviaa:BAAALgAFFAEJAQABLgAECgkJRgAKAFYeAA==.Erovvia:BAAALgAECgUJBgABLgAECgkJRgAKAFYeAA==.',
Es='Essaelsia:BAAALgAECgcJBwAAAA==.',
Et='Etali:BAAALgAECgMJBQABLgAFFAEJBAAPAAAAAA==.',
Ev='Evorik:BAAALgAFFAMJAwABLgAFFAUJEgAdALERAA==.',
Ez='Ezothen:BAABLgAECn8tAAMQAAgJpBA8BQD1AAAQAAgJpBA8BQD1AAAkAAQJawRpLwCdAAAAAA==.',
Fa='Faedoria:BAABLgAECn8kAAISAAkJ7wSMtgAWAQASAAkJ7wSMtgAWAQAAAA==.Faeryln:BAABLgAECn8nAAIKAAkJ+wuNLABmAQAKAAkJ+wuNLABmAQAAAA==.Faerynn:BAAALgADCgkJCQABLgAECgkJLwAFAF0eAA==.Faewrynn:BAAALgADCgMJAwAAAA==.Falenrush:BAAALgADCgEJAQAAAA==.Falkorr:BAAALgAECgQJCAABLgAECgkJQgAlAHogAA==.Falorie:BAAALgADCgYJEQAAAA==.Fatesmage:BAAALgADCgUJCAAAAA==.Fatherfade:BAAALgAECgQJBAAAAA==.Fatherkarras:BAAALgADCgIJAgAAAA==.Faustion:BAABLgAECn80AAMYAAkJfCElBADzAgAYAAgJuSElBADzAgAQAAEJByGRfwBgAAAAAA==.Faustus:BAAALgADCgQJCgABLgAECgkJNAAYAHwhAA==.',
Fe='Feature:BAAALgAECgkJBwAAAA==.Felstormer:BAAALgADCggJEAABLgAECgUJEwAPAAAAAA==.Felyna:BAAALgAECgMJAwAAAA==.',
Fi='Filthy:BAAALgADCggJDgAAAA==.Finessed:BAAALgADCgEJAQAAAA==.Firebrande:BAAALgAECgcJCgAAAA==.Firefoxx:BAAALgAECgEJAQABLgAECgkJLwAFAF0eAA==.Fireføx:BAAALgAECgEJAQAAAA==.Fisticuffs:BAAALgAECgUJEwAAAA==.Fistingmoth:BAAALgAECgUJBQAAAA==.Fizzllebang:BAABLgAECn8oAAIDAAkJxxUFCQC5AQADAAkJxxUFCQC5AQAAAA==.',
Fl='Flamewhisker:BAAALgAECgcJCgAAAQ==.Flandre:BAAALgAECgYJBgAAAA==.Flogginrenee:BAAALgAECgYJEwAAAA==.Floggsdaddy:BAAALgAECgYJEwAAAA==.Floke:BAAALgAECgMJBAAAAA==.Flokie:BAAALgADCgYJEQAAAA==.',
Fo='Fodin:BAAALgAECgEJAQAAAA==.Fourthmeal:BAAALgAECgIJAgAAAA==.',
Fr='Fraublucher:BAABLgAECn9GAAIKAAkJjxb4AQD0AQAKAAkJjxb4AQD0AQAAAA==.Fredrik:BAABLgAFFH8SAAMdAAUJsRFzJwALAQAdAAUJsRFzJwALAQAiAAIJywGIcAAiAAAAAA==.Frewyn:BAAALgAECgQJCgAAAA==.Frikk:BAAALgAECgQJBAAAAA==.Frostedcakes:BAAALgAECgUJBQAAAA==.Frostimoth:BAABLgAECn8uAAIVAAkJzRYpOwAtAgAVAAkJzRYpOwAtAgAAAA==.Frozty:BAABLgAECn8hAAIYAAkJaBSNCwAhAgAYAAkJaBSNCwAhAgAAAA==.',
Fu='Fujïn:BAAALgADCgEJAQAAAA==.',
Ga='Galandel:BAABLgAECn8UAAIfAAUJHBcCAgD/AAAfAAUJHBcCAgD/AAAAAA==.Galial:BAACLgAFFH8YAAIHAAcJchzDAQCzAQAHAAcJchzDAQCzAQAuAAQKfyIAAgcACQlaHzsBACIDAAcACQlaHzsBACIDAAAA.Gantar:BAACLgAFFH8LAAIjAAUJbCJPAgCSAQAjAAUJbCJPAgCSAQAuAAQKfxgAAiMACAl5I64CAPoCACMACAl5I64CAPoCAAAA.Garlicbread:BAAALgADCgYJBgABLgAFFAcJGAAHAHIcAA==.Garralock:BAAALgAECgcJAQAAAA==.Garrunter:BAABLgAECn8UAAMMAAcJ/xNaCAB4AQAMAAcJ/xNaCAB4AQAfAAEJ0wHTRwASAAAAAA==.Gaznol:BAABLgAECn8lAAIMAAkJGSEJHgBxAgAMAAkJGSEJHgBxAgAAAA==.',
Ge='Gelasera:BAAALgAECgcJCgAAAA==.Geralt:BAAALgADCgYJBgAAAA==.Gerbert:BAAALgAECgUJCQAAAA==.',
Gh='Ghibli:BAABLgAECn8XAAMWAAkJuA+8GwB9AQAWAAkJuA+8GwB9AQAXAAIJ7AWjmgBWAAAAAA==.',
Gi='Gisa:BAAALgAECgEJAQABLgAFFAEJBAAPAAAAAA==.',
Gl='Glaivethras:BAABLgAECn8nAAIHAAkJNiPUAgDEAgAHAAkJNiPUAgDEAgAAAA==.Glyph:BAAALgAECgEJAQAAAA==.Glyphix:BAABLgAECn8nAAIXAAkJPwueMQCGAQAXAAkJPwueMQCGAQAAAA==.Glyphx:BAAALgAECgEJAwAAAA==.',
Gn='Gnarly:BAAALgAECgMJCAAAAA==.',
Go='Goochtrap:BAAALgAECgQJBAAAAA==.Gorgon:BAAALgAECgQJBAAAAA==.',
Gr='Grasman:BAAALgADCgYJBwAAAA==.Gremlynn:BAABLgAECn8hAAQeAAgJxgwxJAB8AQAeAAgJuAsxJAB8AQAMAAQJeQ4vgQDkAAAfAAQJXwUlaACeAAAAAA==.Gridluck:BAAALgAECgMJBAAAAA==.Grimclaw:BAAALgAFFAEJAQABLgAFFAkJIQAEAB0eAA==.Groot:BAABLgAECn8hAAMFAAcJchXlPACgAQAFAAYJ3xblPACgAQAlAAcJKQ1MPQAbAQABLgAFFAIJBgASAOMLAA==.Groovinchef:BAAALgAECgEJAQAAAA==.Grump:BAAALgAECgEJAQABLgAFFAIJAwAPAAAAAA==.',
Gu='Gundunn:BAAALgADCgEJAQAAAA==.',
Ha='Hackdk:BAAALgADCgYJCwAAAA==.Haedlesshour:BAAALgADCgcJBwAAAA==.Hahona:BAAALgADCgEJAQABLgAECggJNQAGABwNAA==.Hamfist:BAAALgADCgYJBwAAAA==.Hanhealz:BAABLgAECn8gAAIZAAgJsRCgLgBmAQAZAAgJsRCgLgBmAQABLgAECgYJBwAPAAAAAA==.Hannebal:BAABLgAECn8aAAITAAkJEhFyJwDPAQATAAkJEhFyJwDPAQAAAA==.',
He='Healsonyou:BAAALgAECgUJBQABLgAECggJFwAEAFsUAA==.Hearsebait:BAAALgADCgIJAgAAAA==.Heiter:BAAALgADCgIJAgAAAA==.Hemlock:BAAALgADCgYJCgAAAA==.Hexia:BAAALgADCggJEgAAAA==.Heydaw:BAAALgAECggJDgABLgAECgkJIAAEAHIgAA==.',
Hi='Highmountain:BAAALgADCgkJCgAAAA==.',
Ho='Hobloc:BAAALgADCgcJCwAAAA==.Hobs:BAAALgAECgEJAQAAAA==.Holybeatdown:BAAALgAECgMJBAAAAA==.Holyrage:BAAALgADCgYJCAAAAA==.Holyßloodelf:BAAALgAECggJCwABLgAECggJFwAEAFsUAA==.Honeysbadger:BAAALgAECgMJAwAAAA==.Hoosier:BAAALgAECgQJBQAAAA==.Hornet:BAABLgAECn8VAAMaAAgJZBDrYwBgAQAaAAgJ7w/rYwBgAQAIAAQJFwz3SADPAAAAAA==.Hotcupofjoe:BAAALgADCgYJBgAAAA==.Hotsauce:BAAALgAECgYJCAABLgAFFAcJGgAVAOIaAA==.',
Hu='Huasca:BAAALgAECgMJBQAAAA==.Humungous:BAAALgAECgcJDQAAAA==.Hunnybunz:BAAALgAECgYJDAAAAA==.Huntriss:BAAALgAECgIJAgAAAA==.',
Hy='Hybles:BAAALgAECgEJAQAAAA==.Hyve:BAAALgAECgkJCQAAAA==.',
['Hà']='Hàney:BAAALgAECgYJBwAAAA==.',
['Hâ']='Hârkness:BAAALgAECgMJEgAAAA==.',
['Hé']='Hélio:BAAALgAECgUJCwAAAA==.',
Ia='Ia:BAABLgAFFH8LAAIUAAQJKAy2EAARAQAUAAQJKAy2EAARAQAAAA==.',
Ic='Icastfirebal:BAAALgAECgEJAQAAAA==.Icypants:BAAALgADCgcJBwAAAA==.',
If='Iffany:BAAALgAECggJDAAAAA==.',
Ig='Igotahitin:BAAALgADCgMJCAAAAA==.',
Ih='Ihitstuff:BAAALgADCgUJBAAAAA==.',
Ik='Iker:BAABLgAECn8dAAIdAAgJ/RIGIwCRAQAdAAgJ/RIGIwCRAQAAAA==.',
Il='Illida:BAAALgAECgYJCQAAAA==.',
Im='Imamalelol:BAABLgAECn8vAAQXAAcJexBmCADjAAAXAAcJ4A9mCADjAAAWAAUJrQrfRwCsAAANAAEJqgCaYgATAAAAAA==.',
In='Indira:BAAALgADCgcJDQABLgAECgQJBAAPAAAAAA==.Insistonfist:BAAALgADCgEJAQAAAA==.Intol:BAAALgAFFAUJCQABLgAFFAUJDAAYAMMNAQ==.Inumimi:BAABLgAECn8iAAImAAkJBQaIJADlAAAmAAkJBQaIJADlAAAAAA==.Invincidemon:BAAALgAECgQJBAAAAA==.',
Ir='Irkenfox:BAECLgAFFH8eAAINAAcJ1CCPCQCYAQANAAcJ1CCPCQCYAQAuAAQKfycAAg0ACQmII54DABsDAA0ACQmII54DABsDAAAA.',
Is='Isogni:BAAALgAECgQJBAABLgAECgcJIAAJAG4eAA==.',
It='Ithran:BAABLgAECn8pAAIVAAkJKQyacQCWAQAVAAkJKQyacQCWAQAAAA==.',
Iw='Iwilltank:BAAALgADCgYJDQAAAA==.',
Ix='Ixitt:BAABLgAECn8wAAIcAAkJ5x17AQCWAgAcAAkJ5x17AQCWAgAAAA==.',
Iz='Izanamí:BAAALgADCgMJAwAAAA==.',
Ja='Jallaz:BAAALgADCgQJBAAAAA==.Jama:BAAALgAECgUJBwAAAA==.James:BAACLgAFFH8jAAIVAAQJTBzHGwAvAQAVAAQJTBzHGwAvAQAuAAQKf0wAAhUACQlNIi0PAAEDABUACQlNIi0PAAEDAAEuAAUUBQkSAB0AsREA.Janderick:BAABLgAECn8lAAIXAAkJyiAsDACmAgAXAAkJyiAsDACmAgAAAA==.Janthara:BAAALgAECgQJBAAAAA==.',
Je='Jeannedarc:BAAALgAECgYJDwAAAA==.Jellacee:BAABLgAECn8hAAMIAAYJfRUlBQAIAQAIAAYJfRUlBQAIAQAaAAIJHgO4EwE2AAAAAA==.Jesterjoe:BAABLgAECn8eAAISAAgJkx9aAgB7AgASAAgJkx9aAgB7AgAAAA==.',
Jh='Jhonson:BAAALgADCgYJBgAAAA==.',
Ji='Jimboberjim:BAACLgAFFH8gAAIDAAcJ6R2vAgC8AQADAAcJ6R2vAgC8AQAuAAQKfy8AAgMACQmfIfQAAC8DAAMACQmfIfQAAC8DAAAA.Jimi:BAAALgADCgUJBQAAAA==.Jimreaper:BAAALgAECgkJCQAAAA==.Jinkx:BAAALgAECgEJAQABLgAECgkJQgAlAHogAA==.',
Jj='Jjoosshhiiee:BAAALgADCgMJBAABLgAFFAUJCwAjAGwiAA==.',
Jo='Joejitsu:BAAALgAECgMJAwAAAA==.Jojokiller:BAAALgADCgEJAQAAAA==.Jolio:BAABLgAECn8sAAQDAAkJTR+uCQCsAQADAAcJ+B6uCQCsAQACAAQJhh/hdABQAQABAAEJXCB1KgBKAAAAAA==.Joltraxi:BAAALgAECgMJBgABLgAECgkJLAADAE0fAA==.Jorlidan:BAAALgAECgYJCgAAAA==.Joshe:BAAALgAECgYJEwABLgAFFAUJCwAjAGwiAA==.Joshy:BAABLgAFFH8FAAISAAQJsQ4OVAAHAQASAAQJsQ4OVAAHAQABLgAFFAUJCwAjAGwiAA==.Jovae:BAAALgADCgIJAgAAAA==.',
Js='Jstnbieber:BAAALgAECgIJAgAAAA==.',
Ju='Juggernauht:BAAALgAECgUJCgAAAA==.Juicethevoid:BAABLgAECn8pAAIaAAkJnwcscQBAAQAaAAkJnwcscQBAAQAAAA==.Juniornite:BAABLgAECn82AAIVAAkJmCAvFwDOAgAVAAkJmCAvFwDOAgAAAA==.Justicus:BAAALgAECgYJEQABLgAECggJIgAIAO4iAA==.Justthetouch:BAAALgAECggJCQAAAA==.',
Jy='Jygglypuff:BAAALgAECgcJCgAAAA==.',
['Jü']='Jüst:BAAALgAECgMJAwAAAA==.',
Ka='Kadaan:BAAALgAECggJCgABLgAECgcJCgAPAAAAAA==.Kadtwo:BAAALgAECgEJAQABLgAECgcJCgAPAAAAAA==.Kaeirria:BAAALgAECgEJAQAAAA==.Kaeldrin:BAAALgADCgkJFAAAAA==.Kaelsanguine:BAAALgAECgEJAQAAAA==.Kagemaro:BAABLgAECn83AAQIAAkJOBuLEAAfAgAIAAgJcBuLEAAfAgAHAAcJVhWFDgBpAQAaAAgJsA4tZgBaAQABLgAFFAEJBAAPAAAAAA==.Kaiser:BAAALgAECgQJCQAAAA==.Kaisér:BAAALgADCgYJBgAAAA==.Kalimathath:BAAALgAECgUJEgAAAA==.Kalzod:BAACLgAFFH8eAAMCAAUJoRs+GwD4AAACAAQJoRs+GwD4AAABAAIJWRaeCwBXAAAuAAQKfz4AAwIACQlLJqQCAGgDAAIACQlLJqQCAGgDAAEAAQkAAB0kAGEAAAAA.Kariana:BAAALgAECgYJDgAAAA==.Kataki:BAAALgAFFAEJBAAAAA==.Katett:BAAALgAECgcJDgAAAA==.Katia:BAAALgADCgUJBQAAAA==.Kativeria:BAAALgAECgcJCgAAAA==.Kattara:BAAALgAECgQJBAAAAA==.Kattitude:BAAALgADCgcJDwABLgAECgYJDgAPAAAAAA==.Kattya:BAAALgADCgcJCAAAAA==.Kauhuana:BAAALgAECgQJBQAAAA==.Kaysabr:BAAALgADCgkJDAAAAA==.Kayssaber:BAAALgAECgYJEgAAAA==.Kazarale:BAAALgADCgQJBAAAAA==.Kazkade:BAAALgAECgMJAwAAAA==.',
Ke='Keanuu:BAAALgADCgMJAwAAAA==.Keidric:BAAALgAECgIJAgAAAA==.Kempra:BAAALgAECgUJBQAAAA==.Kerfufle:BAAALgAECgUJBQAAAA==.Keyn:BAAALgAECgIJAQAAAA==.Keynstolor:BAABLgAECn8hAAIMAAgJRBrwRwDKAQAMAAgJRBrwRwDKAQAAAA==.',
Kh='Khionè:BAAALgAECgEJAQAAAA==.Khálifá:BAAALgAECgUJBgAAAA==.',
Ki='Kicker:BAABLgAECn8UAAIXAAYJcgYNaAC+AAAXAAYJcgYNaAC+AAAAAA==.Killmora:BAABLgAECn8XAAIVAAUJeBMdEQDwAAAVAAUJeBMdEQDwAAAAAA==.Kippars:BAABLgAECn8iAAMjAAkJABRzHQBiAQAjAAgJyRNzHQBiAQAmAAEJfRU0TQA+AAAAAA==.Kiritsugo:BAAALgAECgUJCwAAAA==.Kissame:BAAALgAECgYJCQAAAA==.',
Kn='Knaifu:BAAALgADCgkJDQAAAA==.',
Ko='Kodazoff:BAABLgAECn85AAQQAAkJixKNHgDjAQAQAAkJUhKNHgDjAQAkAAgJsQ1yCgB4AQAYAAIJIAdKPAAyAAAAAA==.Kora:BAAALgAECgYJBgAAAA==.Korevash:BAACLgAFFH8GAAILAAQJ2hA9AwAbAQALAAQJ2hA9AwAbAQAuAAQKfycAAwsACAn7Gx0LAAUCAAsACAn7Gx0LAAUCAAYAAgnjCf68AFUAAAEuAAUUBQkfAAkAAhQA.Korupta:BAABLgAECn8uAAMaAAgJHBAsYgBkAQAaAAgJHBAsYgBkAQAIAAUJ3A36PQAFAQABLgAECgkJJAACADgSAA==.Korzilius:BAAALgAECggJEAAAAA==.',
Kr='Krissylu:BAABLgAECn8gAAIBAAcJFQ3WEgA9AQABAAcJFQ3WEgA9AQAAAA==.Krockett:BAAALgAECgQJBAAAAA==.Krothix:BAABLgAECn9FAAIOAAkJrA0XMwBwAQAOAAkJrA0XMwBwAQAAAA==.Kruvix:BAAALgAECgYJCgAAAA==.Krygask:BAAALgAECgQJBAAAAA==.Kryjag:BAAALgAECgQJDgAAAA==.Krynir:BAAALgADCgkJDgAAAA==.Kryshym:BAABLgAECn8YAAITAAkJaB7BAACdAgATAAkJaB7BAACdAgAAAA==.Krythrall:BAAALgAECgYJDgABLgAECgkJGAATAGgeAA==.',
Ku='Kuatea:BAAALgADCgUJBQAAAA==.Kurorø:BAABLgAECn8bAAIMAAgJBxSiBQDAAQAMAAgJBxSiBQDAAQAAAA==.',
Ky='Kyrayna:BAAALgAECgMJAwAAAA==.',
La='Ladara:BAABLgAECn8tAAIBAAkJ8BAkCADLAQABAAkJ8BAkCADLAQAAAA==.Laima:BAAALgADCgcJEwAAAA==.Lalthras:BAAALgAECgcJBwAAAA==.Lamlam:BAAALgADCgUJBQAAAA==.Landor:BAAALgADCgEJAQAAAA==.Lanea:BAAALgAECgEJAgAAAA==.Lavitz:BAAALgAECgUJCwAAAA==.',
Le='Leheo:BAAALgAECgQJDwAAAA==.Lehua:BAAALgAECgQJCAAAAA==.Leilanii:BAAALgAECgQJDAAAAA==.Lemook:BAAALgAECggJEwAAAA==.Leonìdas:BAAALgAECgQJBgAAAA==.',
Lh='Lhei:BAABLgAECn8mAAIMAAgJyAonCwBCAQAMAAgJyAonCwBCAQAAAA==.',
Li='Lightstormer:BAAALgAECgUJEwAAAA==.Lilamae:BAAALgAECggJDgAAAA==.Lilarielle:BAABLgAECn9NAAImAAgJ+QocBQCsAAAmAAgJ+QocBQCsAAAAAA==.Lildash:BAAALgADCgIJAgABLgAECgkJKAARAJ4bAA==.Lildookie:BAAALgAECgYJBQAAAA==.Lilface:BAAALgAECgYJCgAAAA==.Liliela:BAAALgAECgQJBAABLgAECgkJKAARAJ4bAA==.Lilsham:BAAALgAECgQJBAABLgAECgkJKAARAJ4bAA==.Lilyannah:BAAALgAECgkJAQAAAA==.Linadra:BAAALgAECgcJBwAAAA==.Linear:BAAALgAECgYJBgAAAA==.Liobrew:BAAALgADCgEJAQABLgAECgIJAgAPAAAAAA==.Liopain:BAAALgAECgIJAgAAAA==.Liø:BAAALgAECgEJAQABLgAECgIJAgAPAAAAAA==.',
Lo='Lokir:BAAALgAECgMJBgAAAA==.Losoli:BAAALgAECgkJCQABLgAECgkJVwAhAGwcAA==.Lotheovian:BAEALgAECgIJAgABLgAECgkJLwAEANQaAA==.Lowchin:BAABLgAECn8WAAIFAAcJOwqEZwD+AAAFAAcJOwqEZwD+AAAAAA==.',
Lu='Lucciffer:BAAALgAECgEJAQAAAA==.Lumia:BAABLgAECn8dAAMZAAkJix4wEwBcAgAZAAcJlB8wEwBcAgAKAAYJFBjVSgANAQAAAA==.Lutherion:BAABLgAECn8bAAQNAAgJkCBxCABzAgANAAgJkCBxCABzAgAWAAEJCQdCSAAlAAAXAAEJUALIugASAAAAAA==.',
Lv='Lvispriestly:BAAALgADCgcJEgABLgAECgkJJAAlAKIDAA==.',
Ly='Lycemmas:BAAALgAECgQJBAAAAA==.',
['Lì']='Lìllìth:BAAALgAECgYJBgAAAA==.',
['Lí']='Líttlefoot:BAAALgADCgEJAQAAAA==.',
Ma='Mackdaddy:BAAALgAECgEJAQAAAA==.Mackshiesty:BAABLgAECn8nAAIaAAcJ1h6aLAAVAgAaAAcJ1h6aLAAVAgAAAA==.Macoun:BAABLgAECn8+AAMMAAkJ0CSWBABHAwAMAAkJ0CSWBABHAwAfAAYJEhv0QABVAQAAAA==.Maeledictus:BAAALgAECgMJAwAAAA==.Maga:BAAALgADCgkJHgAAAA==.Magicshowers:BAABLgAECn9IAAIVAAkJLibhBABfAwAVAAkJLibhBABfAwAAAA==.Maikiee:BAAALgADCggJCAAAAA==.Manseed:BAABLgAECn8dAAIZAAgJzAqcNgA7AQAZAAgJzAqcNgA7AQAAAA==.Marksmen:BAAALgADCgEJAQABLgAECgQJBgAPAAAAAA==.Martei:BAACLgAFFH8cAAImAAYJ3BhdBgBHAQAmAAYJ3BhdBgBHAQAuAAQKfy8AAiYACQm/IkICAC8DACYACQm/IkICAC8DAAAA.Maruki:BAAALgADCgEJAQAAAA==.Maríneth:BAABLgAECn8uAAIFAAgJMBIKAwCxAQAFAAgJMBIKAwCxAQAAAA==.Mathías:BAABLgAECn8nAAIMAAkJgBkJKwAxAgAMAAkJgBkJKwAxAgAAAA==.Mavze:BAAALgADCgIJAgAAAA==.',
Me='Meadowfrey:BAAALgAECgEJAQAAAA==.Mentuko:BAAALgAECgQJBwAAAA==.Meowbae:BAABLgAECn84AAMmAAkJ5RjOCAA9AgAmAAkJ5RjOCAA9AgAlAAEJNAGaqQAVAAAAAA==.Merce:BAAALgAECgcJDwABLgAECgkJKAARAJ4bAA==.Mercesdes:BAAALgAECgUJCAAAAA==.Mercina:BAAALgAECgYJCgAAAA==.Mercuros:BAABLgAECn8UAAMKAAkJawMdPgD5AAAKAAkJawMdPgD5AAAZAAIJrgMwfgBBAAAAAA==.Merknlock:BAAALgAECgEJAQAAAA==.',
Mi='Micãh:BAAALgAECgIJAgAAAA==.Midnyte:BAABLgAECn9XAAMhAAkJbBy8DAB5AgAhAAkJbBy8DAB5AgAiAAkJ+RfOAwDGAQAAAA==.Mii:BAAALgAECgkJBQAAAA==.Milkyweí:BAAALgAECgMJAwAAAA==.Mindgames:BAAALgAECgEJAQAAAA==.Mini:BAAALgADCgUJBQABLgAFFAUJBgAeANQRAA==.Minizee:BAAALgAECgYJCAAAAA==.Mirabella:BAAALgAECgUJCwABLgAFFAQJDQAiABYZAA==.Mirokushan:BAABLgAECn8UAAMiAAQJKxE5bQDPAAAiAAQJKxE5bQDPAAAdAAQJwQMiaAB4AAABLgAECgYJGgACAF4YAA==.Mistfit:BAAALgAECgQJAwAAAA==.Misticlady:BAAALgADCgEJAQAAAA==.Mistingmoo:BAAALgAECgkJDQAAAA==.Mistrariel:BAABLgAECn8pAAIHAAkJuh5dAwCqAgAHAAkJuh5dAwCqAgABLgAFFAEJAgAPAAAAAA==.',
Mo='Mojo:BAAALgADCgIJAgAAAA==.Momesca:BAAALgAECgEJAgAAAA==.Moostafa:BAAALgAECgQJBAAAAA==.Moradin:BAAALgADCgIJAgAAAA==.Mordemour:BAABLgAECn8pAAIBAAcJLhkMAQCtAQABAAcJLhkMAQCtAQAAAA==.Morlune:BAAALgAECgEJAQAAAA==.',
Mu='Mungo:BAABLgAECn8rAAIVAAkJrRfzUQDmAQAVAAkJrRfzUQDmAQAAAA==.Musketoon:BAAALgAECgYJBgAAAA==.',
My='My:BAAALgAECgkJDgAAAA==.Mynkie:BAACLgAFFH8gAAIiAAUJqRduDQBHAQAiAAUJqRduDQBHAQAuAAQKfzYAAiIACQlfImEEAGsDACIACQlfImEEAGsDAAAA.Myrell:BAAALgAECgkJBgAAAA==.Mythreashis:BAAALgADCgMJAwAAAA==.',
['Mä']='Mägi:BAAALgAECgEJAQAAAA==.',
['Må']='Mååt:BAAALgADCgIJAgAAAA==.',
['Mæ']='Mæstra:BAAALgAECgEJAQAAAA==.',
['Më']='Mëlony:BAAALgADCgIJAgAAAA==.',
Na='Nachtmar:BAABLgAECn8tAAIjAAgJ7BQcAgCiAQAjAAgJ7BQcAgCiAQAAAA==.Nadaliss:BAAALgADCgkJCwAAAA==.Nahela:BAACLgAFFH8gAAIaAAYJKxSzMABiAQAaAAYJKxSzMABiAQAuAAQKfyoAAhoACAlDHMsyAPsBABoACAlDHMsyAPsBAAAA.Nalik:BAAALgAECgYJCAAAAA==.Nanou:BAAALgADCgUJBwAAAA==.Nardiaun:BAAALgAECgcJDQAAAA==.',
Ne='Necia:BAAALgADCgMJAwABLgAECgkJJwAKAPsLAA==.Neltu:BAAALgAECgQJBQAAAA==.Nevermøre:BAAALgAECgIJAgAAAA==.',
Ni='Nikkitta:BAAALgADCgMJAwAAAA==.Nimravidae:BAABLgAECn9EAAMSAAkJQBYIYACxAQASAAgJ4BMIYACxAQATAAgJXxjrAwBUAQAAAA==.Ninelives:BAABLgAECn8kAAIlAAkJogOLTgDSAAAlAAkJogOLTgDSAAAAAA==.Nitecrawler:BAABLgAECn8jAAMVAAkJnw+SXgDEAQAVAAkJnw+SXgDEAQAnAAEJhQM/GwAZAAAAAA==.Niteeye:BAAALgADCgMJAwABLgAECgkJNgAVAJggAA==.Nitelyt:BAAALgAECgIJAwABLgAECgkJNgAVAJggAA==.Niteryu:BAABLgAECn8kAAMkAAkJlxPqAABTAQAkAAkJLRPqAABTAQAQAAIJWQ+EDABkAAABLgAECgkJNgAVAJggAA==.Nixus:BAAALgAECgMJAwAAAA==.',
No='Nospitfisty:BAABLgAECn8oAAIQAAkJfgvSOwA7AQAQAAkJfgvSOwA7AQAAAA==.Noxium:BAAALgAECgYJDQAAAA==.Noxolon:BAABLgAECn9KAAIXAAkJvh5hCgC+AgAXAAkJvh5hCgC+AgAAAA==.',
Nr='Nreaf:BAABLgAECn9BAAMRAAkJ0SC4AQCfAQASAAkJNR+9JACUAgARAAkJdhy4AQCfAQAAAA==.',
Nu='Nufy:BAAALgAECgYJDwAAAA==.',
Ny='Nyctei:BAAALgAECgcJCwAAAA==.Nydhogg:BAAALgAECgEJAQABLgAFFAEJAgAPAAAAAA==.Nysca:BAAALgADCgcJBwAAAA==.Nytess:BAAALgAECgcJBwABLgAECgkJVwAhAGwcAA==.',
Ob='Obijuan:BAAALgAECgMJAwAAAA==.',
Oc='Octavia:BAAALgADCgYJCAAAAA==.',
Od='Oddotter:BAAALgADCgYJBgAAAA==.',
Oi='Oili:BAABLgAECn8ZAAIVAAkJ0h8dBQDKAQAVAAkJ0h8dBQDKAQAAAA==.',
Ol='Olarrick:BAABLgAFFH8HAAIbAAMJ/wS/MAB+AAAbAAMJ/wS/MAB+AAABLgAFFAUJEgAdALERAA==.',
Or='Ornstein:BAABLgAECn8tAAMRAAgJOCFGCQA9AgARAAgJDCFGCQA9AgASAAYJahSVvwAJAQAAAA==.',
Ot='Ottuk:BAACLgAFFH8YAAMEAAcJbBTBPgB6AQAEAAYJbBTBPgB6AQAbAAEJAAAHZAAAAAAuAAQKfyIAAwQACQnVIa8IAFgDAAQACQnVIa8IAFgDABsAAwlnHX0nAAMBAAAA.',
Pa='Padinbar:BAAALgAECgQJBAABLgAECgcJFQAVAAkSAA==.Pakraxes:BAAALgAFFAEJAQAAAA==.Paksenarrion:BAABLgAECn9FAAIRAAkJIxHwAgAxAQARAAkJIxHwAgAxAQAAAA==.Pancham:BAAALgADCgUJBQAAAA==.Pandemoniúm:BAAALgAECgMJAwAAAA==.Pandemonîum:BAAALgAECgkJEQAAAA==.Pandemônium:BAAALgAECggJEAAAAA==.Pandemönium:BAAALgAFFAIJAwAAAA==.Pandemöniüm:BAAALgAECgYJDAAAAA==.Pandèmonium:BAAALgAECgYJBgAAAA==.Parts:BAAALgAECgIJBwAAAA==.Patchington:BAABLgAECn8uAAIRAAgJohSyAQCiAQARAAgJohSyAQCiAQAAAA==.Pañdemönium:BAAALgAECgUJBQAAAA==.',
Pe='Peatmoss:BAAALgADCgQJBAAAAA==.Pendrgn:BAAALgAECgEJAQAAAA==.Perck:BAAALgAECgQJBAAAAA==.Peryite:BAAALgADCgMJAwAAAA==.Pezp:BAAALgAECgQJBAABLgAFFAIJBgAQAIgTAA==.Pezvoker:BAACLgAFFH8GAAIQAAIJiBOmUwB7AAAQAAIJiBOmUwB7AAAuAAQKfxUAAhAABgkgINMiAMQBABAABgkgINMiAMQBAAAA.',
Ph='Phaedrä:BAAALgAECgEJAQAAAA==.',
Pi='Pienarri:BAAALgAECgEJAgAAAA==.Pixelme:BAAALgAFFAIJAwAAAA==.',
Pl='Pleggster:BAABLgAECn8fAAMGAAkJcA2aTgB3AQAGAAkJcA2aTgB3AQAOAAEJiAGAwgAbAAAAAA==.',
Po='Pochula:BAABLgAECn8kAAIFAAgJaxVoKwD9AQAFAAgJaxVoKwD9AQAAAA==.Powerlock:BAAALgAECgQJBQAAAA==.',
Pr='Primo:BAACLgAFFH8KAAITAAMJLgqkEQCWAAATAAMJLgqkEQCWAAAuAAQKf0EAAxMACQlYFyEDAIQBABMACQlYFyEDAIQBABIAAglKBCJ1AUQAAAAA.Protricity:BAABLgAECn88AAMZAAkJdCDTCQCxAgAZAAkJdCDTCQCxAgAKAAEJ2AJchAAtAAAAAA==.',
Pu='Pumpernickel:BAAALgADCgUJBQABLgAFFAcJGAAHAHIcAA==.Puppytoes:BAABLgAECn8VAAMRAAYJ1BEmIAASAQARAAYJ1BEmIAASAQASAAEJXQgfmQEvAAAAAA==.',
Py='Pyrellyn:BAAALgADCggJCgAAAA==.',
['Pä']='Pändamönium:BAABLgAECn8XAAQLAAkJVBGFAwD9AAAOAAgJwBCUOABVAQALAAUJ8g2FAwD9AAAGAAMJ9BOsjwC5AAAAAA==.Pändemönium:BAAALgAFFAEJAQAAAA==.',
['Pæ']='Pæn:BAACLgAFFH8aAAIEAAUJOyYqDgCxAQAEAAUJOyYqDgCxAQAuAAQKfzUAAxsABwkbJnwBAAYCAAQABwkbJhoiAH8CABsABwlqI3wBAAYCAAEuAAUUBQkkABMA7yIA.',
Qt='Qtpi:BAAALgADCgcJCAAAAA==.',
Qu='Quan:BAAALgAECgcJCgAAAA==.Quantar:BAAALgAECgYJCwABLgAECgcJCgAPAAAAAA==.Quickstab:BAAALgAECgcJBwAAAA==.',
Qw='Qwe:BAAALgAECgQJCwAAAA==.',
['Qü']='Qüeenofdeath:BAAALgAECgkJBAAAAA==.',
Ra='Racingdead:BAAALgADCgEJAQAAAA==.Rakshine:BAAALgAECggJCQAAAA==.Rakta:BAAALgAECgcJEAAAAA==.Ramonga:BAAALgAECgkJBgAAAA==.Rancooll:BAABLgAECn8XAAITAAUJQxU8BQAUAQATAAUJQxU8BQAUAQAAAA==.Rasniir:BAACLgAFFH8IAAIFAAMJDgq6SQCTAAAFAAMJDgq6SQCTAAAuAAQKf0sAAgUACQlZIZcFAF4DAAUACQlZIZcFAF4DAAAA.Ravenlash:BAAALgAECgEJBAAAAA==.',
Re='Regna:BAACLgAFFH8eAAIXAAYJ0SZABQAZAgAXAAYJ0SZABQAZAgAuAAQKfzAAAhcACQmaJhgDAH8DABcACQmaJhgDAH8DAAAA.Regner:BAAALgAECgEJAQAAAA==.Reign:BAAALgADCgYJBwAAAA==.Relkon:BAABLgAECn8WAAIbAAcJlQzJLQDwAAAbAAcJlQzJLQDwAAAAAA==.Remaked:BAACLgAFFH8yAAIdAAcJ+x18AwCpAQAdAAcJ+x18AwCpAQAuAAQKf0AAAh0ACQmsIxMEAAgDAB0ACQmsIxMEAAgDAAAA.Remilia:BAABLgAECn89AAIZAAkJ9SJ3AwApAwAZAAkJ9SJ3AwApAwAAAA==.Requinix:BAABLgAECn9oAAIMAAkJWhurAgBgAgAMAAkJWhurAgBgAgAAAA==.Retro:BAAALgAECgQJCgAAAA==.Revelatiøn:BAAALgADCgIJAgAAAA==.Revunanto:BAAALgAFFAEJAQAAAA==.Revwrinkle:BAAALgAECgIJAwAAAA==.Rexthedragon:BAAALgADCgEJAQAAAA==.',
Ri='Riasu:BAAALgADCgYJCwAAAA==.Rickyybobbie:BAAALgAECgUJEAAAAA==.Ricochet:BAABLgAECn8hAAIeAAkJ0RC0FgDsAQAeAAkJ0RC0FgDsAQAAAA==.Riptidez:BAAALgADCgcJBgAAAA==.Ririko:BAABLgAECn9AAAMKAAkJFhF8HwDIAQAKAAkJFhF8HwDIAQAZAAEJ9QKOGwAcAAAAAA==.Ritzo:BAABLgAECn8xAAIXAAkJsxSAHwDzAQAXAAkJsxSAHwDzAQAAAA==.Rizzla:BAAALgAECgIJAgABLgAECgkJQgAlAHogAA==.',
Ro='Robval:BAAALgADCgMJAwAAAA==.Rockllobster:BAAALgAECgcJDwAAAA==.Rocksanne:BAAALgAECgUJBQAAAA==.Rockyoysterz:BAAALgAECgMJAwAAAA==.Roguebâit:BAABLgAECn9qAAQBAAkJsiA3AACwAgABAAkJpiA3AACwAgACAAcJjBStWQCQAQADAAMJJw3SRACiAAAAAA==.Ronarvinge:BAABLgAECn8VAAIVAAcJCRINggBzAQAVAAcJCRINggBzAQAAAA==.Ronen:BAAALgAECgQJBAAAAA==.',
Ru='Rubywolf:BAAALgAECgYJDgABLgAFFAUJCQAlALsIAA==.Rukkis:BAABLgAECn8qAAMgAAkJFhtgCgB+AgAgAAkJFhtgCgB+AgAoAAEJjQkPJgAtAAAAAA==.Rukâ:BAAALgAECgYJDwAAAA==.Rumi:BAACLgAFFH8kAAIHAAUJ3h5DAQBNAQAHAAUJ3h5DAQBNAQAuAAQKf0sAAwcACQnrJBMBADUDAAcACQnrJBMBADUDAAgAAQlvEXhuADIAAAAA.',
Ry='Ryeekan:BAABLgAECn8zAAIMAAkJKxbTNQAGAgAMAAkJKxbTNQAGAgAAAA==.',
['Ró']='Róronoà:BAAALgAECgYJCgAAAA==.',
Sa='Saaconse:BAAALgADCgcJBwAAAA==.Saata:BAAALgAECgEJAQAAAA==.Sabrosura:BAACLgAFFH8GAAISAAIJ4wv/kwCMAAASAAIJ4wv/kwCMAAAuAAQKfy4AAxIACQneF/9SANABABIACQlbF/9SANABABEABQmiFc8DAP4AAAAA.Sacia:BAAALgADCgkJCQABLgAECgcJKQABAC4ZAA==.Saelena:BAAALgADCgEJAQAAAA==.Sakheddala:BAAALgAECgQJBAAAAA==.Sancha:BAAALgAECgYJBgAAAA==.Sanosagara:BAABLgAECn9CAAIiAAgJahozGABXAgAiAAgJahozGABXAgAAAA==.Saps:BAAALgADCgIJAgAAAA==.Saraya:BAAALgAECgIJAwAAAA==.Sarithon:BAAALgAECgYJBgAAAA==.Saru:BAAALgADCgkJDQAAAA==.Saruta:BAACLgAFFH8YAAMXAAUJuhrXGABPAQAXAAUJuhrXGABPAQAWAAEJdQMqRwA3AAAuAAQKfzEAAxcACQnxIDEKAMECABcACQnxIDEKAMECABYABQmqDwoWAE4BAAAA.Sath:BAAALgAECgQJBAAAAA==.Sathari:BAABLgAECn86AAIaAAkJDBchBgBLAQAaAAkJDBchBgBLAQAAAA==.Satille:BAAALgADCgcJBwAAAA==.Satsuki:BAABLgAECn8iAAMJAAcJfR3QEwBBAgAJAAcJfR3QEwBBAgAZAAUJfxXfNABFAQABLgAFFAUJJwAaAMkcAA==.',
Sc='Scarycat:BAAALgADCgYJBgAAAA==.Schaden:BAAALgAECgEJAQABLgAECggJFAAFAAIhAA==.',
Se='Seijo:BAAALgAECgMJAwAAAA==.Seiryu:BAAALgAECgEJAQAAAA==.Sekk:BAABLgAECn9mAAMSAAkJtCDKAQDEAgASAAkJtCDKAQDEAgARAAYJvRY7GABcAQAAAA==.Selexi:BAAALgADCgYJEAAAAA==.Sereya:BAAALgADCgQJBAABLgAECgEJAQAPAAAAAA==.Sesshanmaru:BAAALgAECgUJCAAAAA==.',
Sg='Sgáil:BAAALgADCgkJCwAAAA==.',
Sh='Shaddai:BAAALgADCgcJFwAAAA==.Shadeofdark:BAACLgAFFH8JAAIIAAMJgRpZCQDPAAAIAAMJgRpZCQDPAAAuAAQKf4EAAggACQllJRwBAHADAAgACQllJRwBAHADAAAA.Shadoshiftt:BAABLgAECn8pAAMlAAkJGQdWQAANAQAlAAkJGQdWQAANAQAFAAgJGALwlwCeAAAAAA==.Shadowstar:BAAALgADCggJBwAAAA==.Shamwowee:BAAALgAECgUJEwAAAA==.Shamzee:BAACLgAFFH8ZAAMGAAUJ3h+MFQC5AQAGAAUJ3h+MFQC5AQAOAAEJrQJvXwAuAAAuAAQKfyoAAwYACAkTH+kdAF4CAAYACAkTH+kdAF4CAA4AAQlWDa+qACwAAAAA.Shandalf:BAABLgAECn8aAAMCAAYJXhiaBQBjAQACAAYJbxeaBQBjAQADAAQJ1REISwCNAAAAAA==.Shansebaim:BAAALgAECgYJBgAAAA==.Shintok:BAAALgAECggJEgAAAA==.Shuddarun:BAACLgAFFH8iAAIMAAcJnB6iAwBkAQAMAAcJnB6iAwBkAQAuAAQKfywAAgwACQlPIsUDAFQDAAwACQlPIsUDAFQDAAAA.',
Si='Sidera:BAAALgADCgQJAgABLgAECgQJBAAPAAAAAA==.Sify:BAAALgADCgYJBgAAAA==.Simental:BAAALgAECgEJAQAAAA==.Simn:BAABLgAECn8iAAIMAAkJvhooIgBcAgAMAAkJvhooIgBcAgAAAA==.Sindraesong:BAAALgAECggJEgAAAA==.Sinfulpirate:BAAALgADCgQJBAAAAA==.Siyeigon:BAAALgAECgIJBAAAAA==.',
Sk='Skithiryx:BAAALgAECgQJBAABLgAFFAEJBAAPAAAAAA==.Skrai:BAAALgAECgYJEAABLgAECgkJIgANAEghAA==.',
Sl='Slayvylora:BAACLgAFFH8fAAMSAAcJjBfPDQA8AQASAAYJDhXPDQA8AQATAAEJ+QLFRgBFAAAuAAQKfz8ABBIACQl+IuIWALkCABIACQl+IuIWALkCABMABwkDEp8HAMAAABEAAgn2Fjs4AH4AAAAA.Sleep:BAAALgAECgQJBAABLgAFFAQJCwAUACgMAA==.Slughorn:BAAALgADCgMJAwAAAA==.',
Sm='Smallholy:BAAALgAECgIJBQAAAA==.Smarte:BAABLgAFFH8GAAIeAAUJ1BFCBAAyAQAeAAUJ1BFCBAAyAQAAAA==.Smellgripson:BAAALgAECgIJAgAAAA==.',
Sn='Snazzyjack:BAAALgAECgIJAgAAAA==.Sneakymoth:BAABLgAECn8VAAIgAAYJXxOyLgAoAQAgAAYJXxOyLgAoAQABLgAECgkJLgAVAM0WAA==.Sniff:BAACLgAFFH8FAAIVAAUJwg0HIAAVAQAVAAUJwg0HIAAVAQAuAAQKfysAAhUACAnsHtAuAF0CABUACAnsHtAuAF0CAAEuAAUUBQkGAB4A1BEA.Snookums:BAABLgAECn86AAIaAAgJbBqBMQAAAgAaAAgJbBqBMQAAAgAAAA==.',
So='Soulomon:BAABLgAECn8ZAAICAAkJsRMwgwBUAQACAAkJsRMwgwBUAQAAAA==.Soulsarisen:BAAALgAECgYJDwAAAA==.',
Sp='Spanki:BAAALgADCgkJEAAAAA==.Spellteaser:BAABLgAECn8VAAIVAAYJOhkguQBvAQAVAAYJOhkguQBvAQAAAA==.Spicymaker:BAABLgAECn8mAAIWAAgJ5yBkCQBZAgAWAAgJ5yBkCQBZAgAAAA==.Spiritual:BAAALgADCgIJAgAAAA==.',
St='Starar:BAAALgAECgMJCgAAAA==.Steelheart:BAAALgAECgEJCgAAAA==.Steviathan:BAAALgADCgQJBAAAAA==.Stolensøul:BAAALgADCgkJDgAAAA==.Stormguard:BAAALgAECgEJAQAAAA==.Strifewood:BAABLgAECn8cAAIbAAkJWhhKFQDDAQAbAAkJWhhKFQDDAQAAAA==.Stumper:BAABLgAECn9CAAIlAAkJeiA/AQBBAgAlAAkJeiA/AQBBAgAAAA==.',
Su='Sugondese:BAAALgAECgQJBgAAAA==.Suluna:BAAALgAECgUJCgABLgAECgkJSAAGAOYdAA==.Summêr:BAABLgAECn8YAAIiAAYJ2wgpbQDPAAAiAAYJ2wgpbQDPAAAAAA==.Suri:BAAALgAECgUJCgABLgAECggJGAANAGIZAA==.Sux:BAABLgAECn8fAAIjAAkJ4A/QBAAKAQAjAAkJ4A/QBAAKAQAAAA==.',
Sy='Sybrina:BAACLgAFFH8HAAIMAAIJEQztMwCZAAAMAAIJEQztMwCZAAAuAAQKfyAAAgwACQnVFQE3AAICAAwACQnVFQE3AAICAAAA.Sylvia:BAAALgADCgcJBgABLgAECgEJAQAPAAAAAA==.Synevra:BAAALgADCggJFgAAAA==.Syngeance:BAABLgAECn81AAIMAAYJ4QvNnQAGAQAMAAYJ4QvNnQAGAQAAAA==.Synèsterwolf:BAAALgAECgIJAwABLgAFFAUJCQAlALsIAA==.',
['Sí']='Síf:BAAALgAECgcJDQAAAA==.',
Ta='Tabernacle:BAAALgAECgUJBQAAAA==.Tadeusz:BAABLgAECn8aAAIgAAkJ1xeTDABdAgAgAAkJ1xeTDABdAgAAAA==.Tamamò:BAABLgAECn8bAAIiAAcJOxKPKABvAQAiAAcJOxKPKABvAQAAAA==.Tarrok:BAAALgADCgMJBwAAAA==.',
Te='Tealleth:BAAALgADCgMJAwAAAA==.Telana:BAABLgAECn8WAAIoAAQJzxG0AQC0AAAoAAQJzxG0AQC0AAAAAA==.Tepache:BAAALgADCgEJAQABLgAFFAEJAwAPAAAAAA==.Tequitos:BAABLgAECn8mAAMTAAkJTBMqGgA0AgATAAkJTBMqGgA0AgASAAYJ7gtV2gDlAAAAAA==.Teranin:BAABLgAECn8UAAIlAAcJPwj+SgDgAAAlAAcJPwj+SgDgAAAAAA==.',
Tf='Tfortyone:BAAALgAECgYJCQAAAA==.',
Th='Tharbad:BAAALgADCgEJBQAAAA==.Thchosen:BAAALgAECgMJBAAAAA==.Theduk:BAAALgAECgQJCAAAAA==.Thorae:BAAALgADCgEJAQAAAA==.Thorias:BAACLgAFFH8YAAIVAAUJxR6THQAkAQAVAAUJxR6THQAkAQAuAAQKf0sAAhUACQnNJR4EAGgDABUACQnNJR4EAGgDAAAA.Thunderwalkr:BAAALgAECgEJAgAAAA==.',
Ti='Tiren:BAAALgAECgYJDQAAAA==.',
To='Torag:BAAALgAECgYJCQAAAA==.Torment:BAABLgAECn9wAAIbAAkJ5iDCBADkAgAbAAkJ5iDCBADkAgAAAA==.Tosti:BAAALgAECgkJAQAAAA==.',
Tr='Trepania:BAACLgAFFH8aAAIKAAYJRwtaDwBcAQAKAAYJRwtaDwBcAQAuAAQKfy8AAgoACQngGdEWACUCAAoACQngGdEWACUCAAAA.Tristén:BAABLgAECn8bAAIMAAgJ6RnJCABvAQAMAAgJ6RnJCABvAQAAAA==.Trogdoor:BAAALgAECgEJAQAAAA==.Trollycarp:BAABLgAECn8gAAMSAAkJQwq3vwAJAQASAAkJAgS3vwAJAQARAAUJdhDnLAC4AAAAAA==.Truvie:BAABLgAECn8ZAAISAAYJxwyJFQDDAAASAAYJxwyJFQDDAAAAAA==.',
Tu='Tumbler:BAABLgAECn8YAAMGAAkJ+BwbHABrAgAGAAkJ+BwbHABrAgAOAAMJCBHGcgCTAAAAAA==.Tumbles:BAAALgAECgUJBwAAAA==.Tumni:BAABLgAECn9AAAMOAAgJCgwLQQAwAQAOAAgJCgwLQQAwAQAGAAYJdAwqeAD2AAAAAA==.',
Tw='Twinkletoes:BAAALgADCgIJAgAAAA==.Twylah:BAAALgADCgIJAgAAAA==.',
['Tá']='Táelah:BAABLgAECn8jAAIeAAkJRxFKFgDvAQAeAAkJRxFKFgDvAQAAAA==.Tángall:BAAALgAECgUJBQAAAA==.',
Ul='Ulnuk:BAACLgAFFH8XAAIGAAQJSh2xJQBUAQAGAAQJSh2xJQBUAQAuAAQKf0YAAgYACQnoInYIACkDAAYACQnoInYIACkDAAAA.Ulster:BAAALgAECgIJAwAAAA==.',
Un='Unholyshan:BAAALgAECgEJAQABLgAECgYJGgACAF4YAA==.Unidus:BAAALgAECgYJBwAAAA==.',
Up='Uphellyaa:BAAALgADCgUJBQABLgAECgQJBAAPAAAAAA==.',
Ur='Urwelcome:BAAALgAECgcJBwAAAA==.',
Va='Vadka:BAABLgAECn8aAAITAAgJZRm2GwAmAgATAAgJZRm2GwAmAgAAAA==.Vaexxi:BAAALgAECgUJBgAAAA==.Vaha:BAABLgAECn81AAMGAAgJHA1JBwBJAQAGAAgJHA1JBwBJAQAOAAgJFwgfBwDuAAAAAA==.Vairian:BAABLgAECn8ZAAIIAAcJqQ8fLAAgAQAIAAcJqQ8fLAAgAQAAAA==.Valkree:BAABLgAECn8kAAISAAcJqREmCwA3AQASAAcJqREmCwA3AQAAAA==.Vallae:BAAALgADCgkJEQABLgAECgkJSAAGAOYdAA==.Valsavis:BAABLgAECn9NAAIHAAkJtxy9BABsAgAHAAkJtxy9BABsAgAAAA==.Valtier:BAABLgAECn8WAAMlAAgJ8BdOIQC+AQAlAAcJNRlOIQC+AQAFAAQJyBemXwAXAQAAAA==.Vampirä:BAABLgAECn8iAAQFAAkJQQVbhgCrAAAFAAgJAgRbhgCrAAAmAAQJngXhOAB2AAAlAAIJrgMxhwA8AAAAAA==.Vanyelle:BAAALgAECgQJBAAAAA==.Varactor:BAAALgAECgMJAwAAAA==.Varlaris:BAAALgAECgMJAwAAAA==.Vasarah:BAAALgAECgEJAQAAAA==.Vashidan:BAABLgAECn8YAAIhAAgJ7iA1CAD3AgAhAAgJ7iA1CAD3AgAAAA==.',
Ve='Velenar:BAAALgADCgIJAgAAAA==.Velisandre:BAAALgADCgcJIgAAAA==.Vellagosa:BAAALgAECgcJCgAAAA==.Vellini:BAAALgAECgEJAQABLgAECgcJIAAJAG4eAA==.Vernice:BAAALgAECgEJAQABLgAECgcJKQABAC4ZAA==.Verulan:BAABLgAECn8gAAQlAAgJtQp6OQAtAQAlAAgJ1Al6OQAtAQAFAAQJjAojkwCOAAAmAAEJKA5sVAAwAAAAAA==.Vexeh:BAAALgAECgYJCgAAAA==.Vexomous:BAABLgAECn8WAAIeAAcJtR89AQDwAQAeAAcJtR89AQDwAQAAAA==.',
Vi='Vierilan:BAAALgADCgcJBwAAAA==.Vierina:BAAALgAECgEJAQAAAA==.Vikss:BAABLgAECn8zAAMMAAkJ0xJNRQDSAQAMAAkJ0xJNRQDSAQAeAAYJXQQsHQAFAQAAAA==.Viledk:BAAALgAECgUJBgAAAA==.Viserian:BAAALgAECgYJEwAAAA==.Vivenna:BAAALgAECgUJBQAAAA==.Vivien:BAAALgADCgYJBgABLgAECgEJAQAPAAAAAA==.',
Vl='Vll:BAABLgAECn8gAAImAAcJ6x9tCABYAgAmAAcJ6x9tCABYAgABLgAECggJIgAIAO4iAA==.',
Vo='Voidmayne:BAABLgAECn8/AAISAAkJjBGyVQDJAQASAAkJjBGyVQDJAQAAAA==.Vongogh:BAAALgADCgEJAQAAAA==.Vonhelsing:BAAALgAECgYJEwAAAA==.Vorcan:BAAALgADCgMJBgAAAA==.Vorenius:BAAALgADCgEJAQAAAA==.Voxella:BAAALgAECgQJBAAAAA==.',
Vr='Vrel:BAAALgADCgkJDgAAAA==.',
Vy='Vynnara:BAAALgAECgcJDgABLgAECgcJIAAJAG4eAA==.Vyv:BAABLgAECn8UAAIOAAcJtAUlWwDTAAAOAAcJtAUlWwDTAAAAAA==.Vyvboo:BAAALgADCgcJBwAAAA==.Vyvish:BAAALgADCgUJBQAAAA==.',
['Vö']='Vöid:BAABLgAECn8ZAAIaAAYJEhyzTQC+AQAaAAYJEhyzTQC+AQAAAA==.',
Wa='Warlogic:BAAALgAECgQJBAAAAA==.Warwounds:BAAALgAECgEJAQAAAA==.Wayadra:BAABLgAECn8XAAQQAAkJkSGlBwDdAgAQAAkJkSGlBwDdAgAkAAcJSQTlJgDrAAAYAAEJlgrESQAvAAAAAA==.',
We='Weiand:BAABLgAECn8wAAMSAAkJUhtaNwAkAgASAAgJpxpaNwAkAgATAAEJOwejiwAzAAAAAA==.Welil:BAAALgAECgUJCwAAAA==.',
Wh='Whachah:BAAALgAECgQJCAAAAA==.Whatami:BAACLgAFFH8LAAQDAAQJNw9bFACYAAACAAQJTwmAYwAAAQADAAIJGRJbFACYAAABAAEJHgj1KABFAAAuAAQKfzEABAIACQk1HbMBAH0CAAIACQk1HbMBAH0CAAMAAgnvD39XAGgAAAEAAQkAAA4xADwAAAAA.Wholemilk:BAABLgAECn8rAAIaAAkJuyByDQDaAgAaAAkJuyByDQDaAgAAAA==.',
Wi='Wiggz:BAAALgAECgcJCgAAAA==.Wilhellena:BAABLgAECn9GAAIKAAkJEB9XBgANAwAKAAkJEB9XBgANAwAAAA==.Wilhellfu:BAAALgAECgMJBwAAAA==.Willôw:BAAALgAECgEJAQAAAA==.Winariel:BAAALgAFFAEJAgAAAA==.Wisteria:BAAALgAECgEJAQABLgABCgEJAQAPAAAAAA==.',
Wr='Wrathsoul:BAAALgAECgEJAQABLgAECgEJAwAPAAAAAA==.Wrecksoul:BAAALgAECgEJAQABLgAECgEJAwAPAAAAAA==.Writhesoul:BAAALgAECgEJAwAAAA==.Wroughtsoul:BAAALgAECgQJAgAAAA==.Wrëckagë:BAAALgAECgcJEwAAAA==.',
Wu='Wumbo:BAAALgAECgYJBwAAAA==.',
Xa='Xaiea:BAAALgADCgcJBwAAAA==.Xalatath:BAAALgAECgEJAQAAAA==.Xaldred:BAABLgAECn8kAAICAAkJOBLBRgDGAQACAAkJOBLBRgDGAQAAAA==.Xandir:BAABLgAECn9CAAIRAAkJehN5EgCfAQARAAkJehN5EgCfAQAAAA==.Xarhunt:BAAALgAECgcJEgAAAA==.Xaric:BAABLgAECn8nAAIFAAkJXhlRJwAWAgAFAAkJXhlRJwAWAgAAAA==.',
Xe='Xella:BAAALgAECgQJBAAAAA==.',
Xu='Xueshi:BAAALgAECgEJAQAAAA==.',
Xy='Xyal:BAABLgAECn8/AAMKAAkJTyPMBwDxAgAKAAkJTyPMBwDxAgAZAAEJ8wjnkQApAAAAAA==.Xyp:BAAALgAECgIJAgABLgAECggJIAAlALUKAA==.',
Yg='Ygor:BAAALgAFFAEJAQAAAA==.',
Yi='Yiago:BAABLgAECn8rAAIXAAcJ0Qr4BgAFAQAXAAcJ0Qr4BgAFAQAAAA==.',
Yo='Yobabydaddy:BAAALgAECgMJAwAAAA==.Youknow:BAAALgAECgUJCQAAAA==.',
Yu='Yumiisaki:BAAALgAECgQJBAAAAA==.Yungslug:BAAALgAECgcJCQAAAA==.',
Za='Zahel:BAAALgADCgYJEgAAAA==.Zangbus:BAAALgADCgcJFAAAAA==.Zany:BAAALgAECgEJAQAAAA==.Zaranorinn:BAABLgAECn8dAAISAAkJ0AebmABEAQASAAkJ0AebmABEAQAAAA==.Zaxhdk:BAEBLgAECn8vAAMEAAkJ1BonJwBmAgAEAAkJ1BonJwBmAgAbAAUJTwbCRAB8AAAAAA==.Zaxhmonk:BAEALgADCgkJCQABLgAECgkJLwAEANQaAA==.',
Ze='Zedex:BAAALgADCgcJCAABLgADCggJDQAPAAAAAA==.Zedru:BAAALgADCggJDQAAAA==.Zenstormer:BAAALgADCgQJBAABLgAECgUJEwAPAAAAAA==.Zephril:BAAALgADCgEJAQAAAA==.Zephyrion:BAAALgAECgQJDAAAAA==.Zerfällt:BAAALgADCgYJCwAAAA==.Zerrus:BAABLgAECn8VAAIEAAYJfx0ijABMAQAEAAYJfx0ijABMAQAAAA==.',
Zh='Zhoryn:BAAALgAECgYJDQAAAA==.',
Zi='Zilvra:BAABLgAECn8hAAIGAAkJ+hc9JgApAgAGAAkJ+hc9JgApAgAAAA==.Zinrar:BAABLgAECn8qAAIEAAkJ/RmjKABfAgAEAAkJ/RmjKABfAgAAAA==.Zipagain:BAAALgADCgQJBAAAAA==.Ziparoo:BAABLgAECn8wAAIVAAcJqAisvAAPAQAVAAcJqAisvAAPAQAAAA==.Zittizle:BAAALgAECgEJAQAAAA==.',
Zr='Zraven:BAABLgAECn84AAMeAAkJJRYyEgAXAgAeAAkJXRUyEgAXAgAMAAEJKRoJGwFBAAAAAA==.',
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
