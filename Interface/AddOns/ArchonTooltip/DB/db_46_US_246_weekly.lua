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

local lookup = {'Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','DemonHunter-Havoc','Druid-Restoration','Unknown-Unknown','Warrior-Arms','Rogue-Subtlety','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','Mage-Frost','DeathKnight-Blood','DeathKnight-Frost','Druid-Balance','DemonHunter-Devourer','Rogue-Assassination','Mage-Arcane','Monk-Mistweaver','Druid-Guardian','Monk-Brewmaster','Paladin-Holy','Shaman-Restoration','Warlock-Demonology','Paladin-Retribution','Evoker-Preservation','Warrior-Protection','Shaman-Elemental','Druid-Feral','Mage-Fire','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Evoker-Augmentation','Shaman-Enhancement','Paladin-Protection','DemonHunter-Vengeance','Monk-Windwalker',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=46,date='2026-05-17',data={Aa='Aaronfreeze:BAABLgAECn8tAAIBAAkJ6xz2FgBcAgABAAkJ6xz2FgBcAgAAAA==.',
Ab='Abrakazaam:BAAALgADCgEJAQAAAA==.',
Ad='Adrios:BAABLgAECn8jAAQCAAgJEhUSGwCsAQACAAgJABUSGwCsAQADAAMJyggkaQCIAAAEAAUJeQbtUgBqAAAAAA==.',
Ae='Aetherion:BAAALgAECgMJAwAAAA==.',
Aj='Ajaxz:BAABLgAECn8VAAIFAAkJ+RLTYADRAQAFAAkJ+RLTYADRAQAAAA==.',
Al='Albedô:BAAALgAFFAIJAwABLgAFFAIJBgAGAAohAA==.Aliren:BAAALgAECgYJCgAAAA==.Allmaick:BAAALgADCggJCAAAAA==.Alucard:BAAALgAFFAMJAwAAAA==.Alystrasza:BAABLgAECn8cAAIHAAYJvhZnOAB6AQAHAAYJvhZnOAB6AQAAAA==.',
Am='Amorlandian:BAAALgAECgMJAwAAAA==.',
An='Antimovsky:BAAALgAECgYJCwAAAA==.',
Ap='Aphroditê:BAAALgADCgYJBgABLgAECgcJBwAIAAAAAA==.',
Aq='Aqours:BAAALgADCgcJBwABLgAECgEJAgAIAAAAAA==.',
Ar='Arcan:BAAALgAECgIJAgAAAA==.',
Au='Augustine:BAAALgAECgEJAQAAAA==.Auroras:BAABLgAECn8XAAIDAAcJghOZNABsAQADAAcJghOZNABsAQAAAA==.',
Av='Aviaria:BAAALgAECgQJBAAAAA==.Avìendha:BAAALgADCgEJAQAAAA==.',
['Aì']='Aìnzooalgown:BAABLgAFFH8IAAIFAAMJhRM+XgD7AAAFAAMJhRM+XgD7AAABLgAFFAIJBgAGAAohAA==.',
Ba='Babakubwa:BAAALgAECgMJAwAAAA==.Babylonfive:BAAALgAECgcJCwAAAA==.Balhair:BAAALgADCgYJBgAAAA==.Banish:BAAALgAECgMJAgABLgAECgcJCgAIAAAAAA==.Barragdan:BAAALgADCgEJAQAAAA==.Basandra:BAAALgAECgEJAQAAAA==.Basicc:BAAALgADCgMJAwAAAA==.',
Be='Beachbumm:BAAALgADCgEJAQAAAA==.Belleta:BAAALgAECgYJCAAAAA==.Berserk:BAEBLgAECn8XAAIJAAYJJyJQCAAyAgAJAAYJJyJQCAAyAgABLgAFFAMJBQAKALwMAA==.Bertringer:BAAALgAECgEJAgAAAA==.',
Bi='Bigmack:BAAALgAECgYJCwAAAA==.Bigwilli:BAAALgAECgUJDAAAAA==.Bingßong:BAAALgADCgYJDgAAAA==.Biscuit:BAACLgAFFH8NAAQBAAQJeB2fNAD3AAABAAMJaByfNAD3AAALAAIJ4hcDFgCeAAAMAAIJ/BE8HgCRAAAuAAQKfyIABAsACAmPIycPAMgCAAsACAl9HScPAMgCAAwAAwnaH7YsAPwAAAEABAk+Hvt7APkAAAAA.Bisha:BAABLgAECn9FAAMNAAkJESFVCACiAgANAAkJ8yBVCACiAgAJAAYJcBj+EwB5AQAAAA==.Bizcocho:BAAALgAECgYJCwAAAA==.',
Bl='Black:BAAALgADCgEJAQAAAA==.Bloodsimple:BAAALgADCgUJBQAAAA==.Blákers:BAAALgAECgcJCgABLgAFFAMJBwAOAGADAA==.',
Bo='Boic:BAAALgADCgQJBAAAAA==.Bonesofdoom:BAABLgAECn8VAAIPAAcJvRvwFQBvAQAPAAcJvRvwFQBvAQAAAA==.Boogsta:BAABLgAECn8VAAIQAAgJxAVjEAADAQAQAAgJxAVjEAADAQAAAA==.Boomkingobrr:BAACLgAFFH8HAAIRAAMJ9wjrIQDFAAARAAMJ9wjrIQDFAAAuAAQKfxsAAhEACQkOHEQLAOECABEACQkOHEQLAOECAAAA.Boops:BAAALgAECgEJAQAAAA==.Bootysweatt:BAABLgAECn8aAAIGAAYJNhtqJACaAQAGAAYJNhtqJACaAQAAAA==.Boss:BAAALgADCgEJAQAAAA==.',
Br='Brewnz:BAAALgAECgUJBgAAAA==.Brucewee:BAAALgAECgIJAwAAAA==.',
Bu='Buckits:BAAALgAECgcJEgAAAA==.Bunsey:BAAALgADCgIJAgAAAA==.Burnsx:BAAALgAECgUJCgABLgAFFAcJEQASAE8dAA==.Bussyman:BAAALgAECgYJDgAAAA==.',
Bw='Bwoar:BAAALgAECgQJBgAAAA==.',
['Bø']='Bøw:BAAALgAECgMJAwAAAA==.',
['Bü']='Bübble:BAAALgADCgEJAQAAAA==.',
Ca='Captnmurloc:BAAALgAECggJDwAAAA==.Carl:BAAALgAECgEJAgABLgAFFAYJDQATAPUcAA==.Caveyodeler:BAAALgAECgQJCgAAAA==.',
Ce='Cedar:BAAALgAECgQJCQAAAA==.',
Ch='Cherga:BAAALgADCgYJBgAAAA==.Chinegga:BAAALgADCgYJBgAAAA==.Chitose:BAAALgADCgUJBQABLgAECgEJAgAIAAAAAA==.Chrapsasspee:BAAALgADCgcJGQAAAA==.Chrinn:BAAALgADCgIJAgAAAA==.',
Ci='Cindele:BAAALgADCgMJAwAAAA==.Cirvix:BAAALgAECgYJDAAAAA==.Cirxe:BAABLgAECn8ZAAIUAAgJegiNBQBDAQAUAAgJegiNBQBDAQAAAA==.',
Cl='Clampire:BAAALgAECgQJBAAAAA==.Cliint:BAAALgAECgcJCwAAAA==.Cloúnt:BAAALgADCgUJBQAAAA==.Cluumn:BAAALgAECgkJCgAAAA==.',
Co='Coms:BAAALgADCgIJAgAAAA==.Cooz:BAAALgAECgYJDgAAAA==.Corybooker:BAAALgAECgcJBAAAAA==.Cowdux:BAAALgAECgYJCQAAAA==.',
Cr='Creamdragon:BAAALgADCgYJCgABLgAECgYJJAAVAIseAA==.',
Cu='Curuni:BAAALgADCgYJBgAAAA==.',
Cz='Czechhunter:BAAALgADCgUJBQAAAA==.',
['Cå']='Cåleb:BAAALgAECgEJAQAAAA==.',
['Cø']='Cønstance:BAABLgAECn8UAAIWAAcJvhFlFwAuAQAWAAcJvhFlFwAuAQAAAA==.',
Da='Daddyphat:BAABLgAECn8pAAIXAAgJSySfBADQAgAXAAgJSySfBADQAgAAAA==.Daddý:BAAALgAECgEJAQAAAA==.Dalight:BAABLgAECn8XAAIYAAYJKiYPDwCdAgAYAAYJKiYPDwCdAgAAAA==.Dankins:BAACLgAFFH8ZAAIZAAYJ5iE6AwAuAgAZAAYJ5iE6AwAuAgAuAAQKfxYAAhkACAkGHfYZAEcCABkACAkGHfYZAEcCAAAA.',
De='Deathmager:BAABLgAECn8mAAIOAAkJqQplUgCrAQAOAAkJqQplUgCrAQAAAA==.Deathtraper:BAAALgAECgcJDQAAAA==.Debur:BAAALgADCgEJAQAAAA==.Deltaka:BAAALgAECgEJAQAAAA==.Demonfella:BAAALgADCgMJAwAAAA==.Demonicpeach:BAABLgAECn8XAAIaAAcJHwvniQD4AAAaAAcJHwvniQD4AAAAAA==.Dethsent:BAAALgAECgUJCwAAAA==.Dette:BAAALgAECgYJEgAAAA==.Devilchaser:BAAALgAECgYJCgAAAA==.Devourer:BAAALgAECgcJEgAAAA==.',
Di='Diaval:BAAALgADCgIJAgABLgAECggJIwAaAAkUAA==.',
Do='Donzilly:BAAALgAECgUJCwAAAA==.Doreme:BAAALgADCgIJAgAAAA==.',
Dr='Drafted:BAAALgAECgcJEAAAAA==.Drax:BAAALgAECgMJAwAAAA==.Drewmcmoo:BAAALgADCgcJBgAAAA==.Drsath:BAAALgADCgcJBwAAAA==.Drunkorca:BAAALgADCgUJBQABLgAECggJLgAFABgcAA==.',
Ea='Earnar:BAAALgADCgYJDAAAAA==.',
Ed='Edarix:BAAALgADCggJDAABLgAECgYJJgAbANEWAA==.',
Ei='Eiliyah:BAABLgAECn8yAAMYAAgJehz0FgBaAgAYAAgJehz0FgBaAgAbAAIJHwIaWgElAAAAAA==.',
Ek='Ekmek:BAAALgAECgEJAQAAAA==.',
El='Elabernathy:BAABLgAECn8jAAIBAAgJ+BN0PQCkAQABAAgJ+BN0PQCkAQAAAA==.Elenay:BAAALgAECgcJEgAAAA==.Elesia:BAAALgAECgkJEgAAAA==.Elfussy:BAAALgAECgEJAQAAAA==.Elgoku:BAAALgAECgQJCgABLgAECgUJDAAIAAAAAA==.Eliarssande:BAAALgADCgQJBAAAAA==.Elinay:BAAALgADCgcJCQABLgAECgcJEgAIAAAAAA==.Elixia:BAABLgAECn8XAAIGAAcJkwwNHwAoAQAGAAcJkwwNHwAoAQAAAA==.Elpatron:BAAALgADCgQJBAABLgAFFAMJBQAcAKMKAA==.Elylanea:BAAALgAECgUJDgAAAA==.',
Em='Emulsdeath:BAAALgAECgcJEAABLgAFFAMJCQAbAHceAA==.Emulsifier:BAACLgAFFH8JAAIbAAMJdx6iMQAXAQAbAAMJdx6iMQAXAQAuAAQKfzAAAhsACAmFJnAGABMDABsACAmFJnAGABMDAAAA.',
En='Ennoa:BAAALgAECgEJAQAAAA==.',
Er='Ergen:BAACLgAFFH8NAAIMAAQJ8RYPCgBRAQAMAAQJ8RYPCgBRAQAuAAQKfyYAAgwACAk6IaUGAJcCAAwACAk6IaUGAJcCAAAA.',
Eu='Eusexua:BAAALgAECgQJBQABLgAECgcJCgAIAAAAAA==.',
Ex='Expiatory:BAAALgAECgYJBgAAAA==.',
Fa='Fairbear:BAABLgAECn8cAAQNAAYJ+BxzKQByAQANAAYJ+BxzKQByAQAJAAEJZA5tPgA7AAAdAAEJ6QePSAAhAAAAAA==.Faustt:BAAALgAECgEJAgAAAA==.',
Fe='Februarysix:BAAALgADCgYJBgAAAA==.',
Fi='Filthyfabio:BAAALgADCgcJEQAAAA==.Fireburr:BAAALgAECgMJAwAAAA==.',
Fl='Flatline:BAAALgAECgYJDQAAAA==.Fløw:BAAALgAECgMJCgAAAA==.',
Fr='Fragglerott:BAABLgAECn8VAAMeAAgJXAiRUQAAAQAeAAgJXAiRUQAAAQAZAAIJJAi8kQBTAAAAAA==.Frati:BAAALgAECgEJAQAAAA==.Friedchickn:BAAALgAECgMJBwAAAA==.Frosttrinity:BAAALgADCgUJBAAAAA==.',
Fu='Funslinger:BAAALgAECgQJCgAAAA==.',
Ga='Gaffz:BAAALgAECgEJAQAAAA==.Galannar:BAAALgAECggJDQAAAA==.Galvrax:BAAALgAECgUJCgAAAA==.Gast:BAACLgAFFH8KAAINAAQJtha4EgA5AQANAAQJtha4EgA5AQAuAAQKfy0AAw0ACQksHzsNAF0CAA0ACQksHzsNAF0CAB0ABAmpFnUpAKwAAAAA.',
Ge='Gearwick:BAAALgADCgYJBwABLgAECgcJJgAYAFAhAA==.',
Gh='Ghstfacekila:BAAALgADCgEJAQAAAA==.',
Gl='Glizzybreath:BAAALgAECgMJAwABLgAECgYJBgAIAAAAAA==.',
Go='Gorska:BAABLgAECn8tAAIeAAkJmByYDABdAgAeAAkJmByYDABdAgAAAA==.',
Gr='Grawm:BAABLgAECn8iAAMBAAkJqiJYMQDSAQALAAgJSRWzHgAxAgABAAkJPyBYMQDSAQAAAA==.Greedory:BAAALgADCgIJAgAAAA==.Groot:BAAALgADCgUJBgAAAA==.Gruetss:BAAALgAECgQJBAAAAA==.',
Ha='Hailbringer:BAAALgAECgcJDgAAAA==.Hakoona:BAABLgAECn8vAAIXAAkJFxqKDAA5AgAXAAkJFxqKDAA5AgAAAA==.Hanginaround:BAAALgAECgEJAQAAAA==.Hangman:BAACLgAFFH8JAAIYAAMJORwhGQAXAQAYAAMJORwhGQAXAQAuAAQKfxkAAxgACAloH88JALECABgACAloH88JALECABsAAgnHCf1LAS8AAAEuAAUUAwkIAAcAIhYA.Hanni:BAABLgAECn8dAAILAAgJUhztBwDCAQALAAgJUhztBwDCAQAAAA==.Haveaburitto:BAACLgAFFH8NAAIOAAQJWBx7MgBTAQAOAAQJWBx7MgBTAQAuAAQKfygAAg4ACAk0JXkMAGEDAA4ACAk0JXkMAGEDAAAA.Hawktoetem:BAAALgAECgQJBAABLgAECgYJHAANAPgcAA==.',
He='Healmemaybe:BAABLgAECn8bAAIHAAYJQiNiGgA1AgAHAAYJQiNiGgA1AgAAAA==.Healthyadult:BAAALgAECgMJBQAAAA==.Hellshand:BAAALgAECgYJDAAAAA==.Heracles:BAAALgAECgQJBAAAAA==.Heretic:BAAALgADCgEJAQAAAA==.',
Hi='Hickscale:BAAALgADCgMJAwAAAA==.',
Ho='Holycøw:BAAALgADCgMJAwAAAA==.Holydefender:BAAALgADCgUJBQAAAA==.Holyhands:BAAALgADCgYJBgAAAA==.Holyholyholy:BAAALgAECgEJAgAAAA==.Honest:BAAALgADCgMJAwAAAA==.',
Hu='Hunniee:BAAALgAECgEJAQAAAA==.Huntrix:BAAALgADCgcJEgAAAA==.',
Ic='Icedatt:BAAALgAECgUJCwAAAA==.Icefire:BAAALgADCgUJBAAAAA==.',
Ik='Ikur:BAACLgAFFH8HAAIYAAMJ0BaRHwDdAAAYAAMJ0BaRHwDdAAAuAAQKfzQAAhgACAlXIGELAJcCABgACAlXIGELAJcCAAAA.',
Il='Ilinia:BAAALgAECgYJCAABLgAECgQJDgAIAAAAAA==.',
Im='Imsteve:BAAALgAECgEJAQAAAA==.',
In='Infoxicated:BAAALgADCgcJCAABLgAECgkJJAACALIeAA==.Insîght:BAAALgAECgQJBAAAAA==.',
Ip='Ipopkidneys:BAACLgAFFH8QAAMTAAQJ0x96BAAKAQATAAMJ/Bl6BAAKAQAKAAMJTiL1FwABAQAuAAQKfyUAAwoACQlUJYQMANACAAoACQlUJYQMANACABMAAQn1I2UYAGgAAAAA.',
Ir='Iroi:BAAALgAECgIJBQAAAA==.',
Is='Iskur:BAABLgAECn8hAAIZAAgJ4BhxFwBGAgAZAAgJ4BhxFwBGAgABLgAFFAMJBwAYANAWAA==.Isuck:BAAALgAFFAIJAgAAAA==.Isurr:BAABLgAECn8XAAIVAAcJnhJJJQCDAQAVAAcJnhJJJQCDAQABLgAFFAMJBwAYANAWAA==.',
It='Itakecandle:BAAALgAECgMJAwABLgAECgUJDAAIAAAAAA==.',
Iv='Ivanapump:BAAALgAECgIJAgABLgAECgYJBgAIAAAAAA==.',
Ja='Jackkal:BAAALgAECgMJAwAAAA==.Jadethecat:BAAALgADCgMJAwAAAA==.Jakbis:BAAALgADCgEJAQAAAA==.Jaldiar:BAAALgADCgcJBwABLgAECgYJBgAIAAAAAA==.Jametrok:BAAALgAECgEJAQAAAA==.Jazbek:BAAALgAECgMJCgAAAA==.Jazzonus:BAAALgAECgEJAQAAAA==.',
Je='Jefferey:BAAALgADCgMJAwAAAA==.Jeriçho:BAAALgADCgYJBgAAAA==.',
Jh='Jhonwick:BAAALgAECgIJAgAAAA==.',
Ji='Jippedo:BAAALgAECgYJAgABLgAECgcJBAAIAAAAAA==.Jiraîya:BAAALgAECgQJBQAAAA==.',
Jo='Jordak:BAABLgAECn8oAAIHAAkJBBxLCQDxAgAHAAkJBBxLCQDxAgAAAA==.Jorolee:BAAALgADCgEJAQAAAA==.',
Ka='Kallistos:BAABLgAECn8bAAIZAAcJgxxLIgD2AQAZAAcJgxxLIgD2AQAAAA==.Kariza:BAAALgAECgMJAgAAAA==.Karunik:BAAALgADCgYJBgABLgAECgcJCgAIAAAAAA==.',
Ke='Kelenheller:BAAALgADCgEJAQAAAA==.',
Kh='Khione:BAAALgADCgYJBgAAAA==.Khthonios:BAAALgADCgYJBgAAAA==.',
Ki='Kibblerina:BAAALgADCgcJBwAAAA==.Kiranam:BAABLgAECn8cAAQfAAgJrQ6dEQCTAQAfAAgJqQqdEQCTAQAWAAcJNQxNIgDOAAARAAIJWwfecQBZAAAAAA==.',
Kn='Knarth:BAABLgAECn8pAAIgAAgJmxZlAgDgAQAgAAgJmxZlAgDgAQAAAA==.',
Ko='Koisy:BAAALgAECgIJBwABLgAECgcJEgAIAAAAAA==.Kole:BAAALgAECgEJAQAAAA==.Koopa:BAABLgAECn8jAAINAAgJISO/CwBvAgANAAgJISO/CwBvAgAAAA==.',
Kr='Krasul:BAACLgAFFH8RAAMZAAQJ4Rx3GAA9AQAZAAQJ4Rx3GAA9AQAeAAEJwg2AOABFAAAuAAQKfx8AAxkACAkXIecIAOgCABkACAkXIecIAOgCAB4ABgm/HPIxAJQBAAAA.Krenthok:BAABLgAECn8eAAIaAAgJiAdKbAA0AQAaAAgJiAdKbAA0AQAAAA==.',
Ku='Kuraha:BAAALgAECgQJBAAAAA==.Kushar:BAAALgAECgQJBQABLgAECgYJDQAIAAAAAA==.',
La='Large:BAAALgADCgYJBgAAAA==.Largemann:BAAALgAECgYJBwABLgAFFAQJDQAFAN4YAA==.Lathspell:BAABLgAECn8yAAIOAAkJtiANGQCRAgAOAAkJtiANGQCRAgAAAA==.Lazyevoker:BAAALgADCgQJBAABLgAECgEJAQAIAAAAAA==.',
Le='Leahan:BAAALgAECgMJBgAAAA==.Leloo:BAAALgADCgYJCgABLgAECgEJAQAIAAAAAA==.',
Lh='Lhureciv:BAACLgAFFH8JAAMEAAMJhhmsFAAKAQAEAAMJhhmsFAAKAQACAAEJKRsYMABMAAAuAAQKf0kAAwQACQnVIyECADEDAAQACQnVIyECADEDAAIABgn7HjAjAHoBAAAA.',
Li='Lightchaser:BAAALgADCgMJAgAAAA==.Lightfkyou:BAAALgADCgcJCgAAAA==.Lihvurce:BAABLgAECn8YAAMbAAYJYxxUWQCEAQAbAAYJYxxUWQCEAQAYAAQJpR0FSwBMAQABLgAFFAMJCQAEAIYZAA==.Lillianna:BAABLgAECn8lAAIKAAgJmRimEADhAQAKAAgJmRimEADhAQAAAA==.Lingchi:BAAALgAECgMJAwAAAA==.',
Ll='Llew:BAAALgAECgEJAQAAAA==.',
Lo='Loenhart:BAAALgAECgEJAQAAAA==.Lolkurtone:BAAALgAECgIJAgAAAA==.',
Lu='Luciaan:BAAALgADCgcJEgAAAA==.Lucrative:BAAALgADCgcJDQAAAA==.Lug:BAAALgAECgEJAQAAAA==.Lulue:BAAALgADCgQJBAAAAA==.Luminari:BAAALgADCgUJBQAAAA==.Lunastorm:BAABLgAECn8xAAIcAAkJYSEtAgAlAwAcAAkJYSEtAgAlAwAAAA==.Luponero:BAACLgAFFH8MAAMBAAQJ5iKwDACAAQABAAQJ5iKwDACAAQALAAEJ5QapKgBGAAAuAAQKfyAAAwsACAnnHuYQALUCAAsACAl6HeYQALUCAAEAAwm/H+xwABMBAAAA.',
Ly='Lynney:BAAALgADCgYJBwAAAA==.',
Ma='Macmn:BAACLgAFFH8QAAIeAAQJrhf/EQA4AQAeAAQJrhf/EQA4AQAuAAQKfygAAh4ABwnAJGULAOICAB4ABwnAJGULAOICAAAA.Magicard:BAABLgAECn8bAAIOAAgJ6AxAZQB7AQAOAAgJ6AxAZQB7AQAAAA==.Makesfood:BAABLgAECn8qAAIOAAcJZBeSdADpAQAOAAcJZBeSdADpAQAAAA==.Mamaheals:BAABLgAECn8iAAIDAAgJyBlFGADMAQADAAgJyBlFGADMAQAAAA==.Mandos:BAAALgAECgYJBgAAAA==.Mantistabogn:BAAALgAECgYJDwAAAA==.Maor:BAABLgAECn8XAAIbAAgJlxdAUACbAQAbAAgJlxdAUACbAQAAAA==.March:BAAALgADCgEJAQAAAA==.Markeisha:BAAALgAECgQJCAAAAA==.',
Me='Mechzician:BAABLgAECn84AAIOAAgJbxl/RADVAQAOAAgJbxl/RADVAQAAAA==.Mechzlock:BAAALgADCgEJAQABLgAECggJOAAOAG8ZAA==.Melinoe:BAAALgAECgEJAQAAAA==.Merlerk:BAAALgADCgYJBgAAAA==.Merlini:BAABLgAECn8WAAMEAAcJuBRdJQBWAQAEAAYJXRddJQBWAQACAAQJHhYwOQDTAAAAAA==.',
Mi='Microplastic:BAAALgAECgUJBQAAAA==.Micspanky:BAAALgAECggJEgAAAA==.Mithrandi:BAAALgAECgMJBAAAAA==.',
Mo='Mornhathor:BAAALgAECggJDgABLgAECgYJBgAIAAAAAA==.',
Mu='Mufinblaster:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgADCgIJBgAAAA==.Musnicker:BAAALgAECgQJBwAAAA==.',
['Mè']='Mètis:BAAALgAECgcJBwAAAA==.',
Ne='Neel:BAAALgADCgQJBQAAAA==.Nervhoost:BAAALgADCgMJAwAAAA==.Neuropolis:BAAALgADCgcJFQAAAA==.Neuroscience:BAAALgADCgMJAwAAAA==.Neurotics:BAABLgAECn8dAAQhAAcJhyIJBQDYAQAhAAYJJCMJBQDYAQAiAAMJYiWCDAA3AQAaAAUJ5BoBuwDjAAAAAA==.Neò:BAABLgAECn8YAAMjAAYJvBAoDAAXAQAjAAYJXw4oDAAXAQAkAAEJ/hR1bwA4AAAAAA==.',
Ni='Niesh:BAAALgAECgEJBwAAAA==.Nineoneone:BAABLgAECn8dAAMDAAcJDxM1JABlAQADAAcJDxM1JABlAQACAAQJjgPqRQCLAAAAAA==.',
No='Nobledecay:BAAALgAECgQJBQAAAA==.Nocturne:BAAALgAECgEJAwAAAA==.',
Nu='Nubbletcake:BAAALgADCgEJAQABLgAECgkJJAACALIeAA==.',
Ny='Nylveth:BAACLgAFFH8LAAIEAAUJHQ0OEgAqAQAEAAUJHQ0OEgAqAQAuAAQKfyoAAgQACQkAHTgKAG0CAAQACQkAHTgKAG0CAAAA.',
Oc='Ocra:BAABLgAECn8YAAIlAAYJuAkxFwDkAAAlAAYJuAkxFwDkAAABLgAFFAMJCgABAIwQAA==.',
Of='Offspeck:BAAALgAECgIJAgABLgAECgkJIAAiAFYcAA==.',
Ou='Outtkast:BAAALgAECgIJAgAAAA==.Ouutkast:BAAALgAECgEJAgAAAA==.',
Oz='Ozwald:BAABLgAECn81AAIMAAkJchxUBQClAgAMAAkJchxUBQClAgAAAA==.',
Pa='Pallyangel:BAAALgADCgcJDwAAAA==.Patrio:BAACLgAFFH8FAAIcAAMJowqCGAC1AAAcAAMJowqCGAC1AAAuAAQKfyoAAhwACQloF2UHAEkCABwACQloF2UHAEkCAAAA.',
Pe='Peaceonea:BAAALgAECgYJEwAAAA==.Peachaid:BAECLgAFFH8YAAICAAgJ9Rd6AQDVAgACAAgJ9Rd6AQDVAgAuAAQKfzAAAwIACQlWIjEDAEQDAAIACQlWIjEDAEQDAAMABgkYHSglAMABAAAA.Peatri:BAAALgAECgkJBAAAAA==.Peetree:BAAALgAECgkJEAAAAA==.',
Ph='Phosphorus:BAACLgAFFH8KAAIJAAMJsBMMEwDeAAAJAAMJsBMMEwDeAAAuAAQKf1MAAwkACQnIHsoCAM8CAAkACQnIHsoCAM8CAB0ABAlNHlkgAO4AAAAA.',
Pl='Plagüë:BAACLgAFFH8LAAMFAAMJiiAiTQAjAQAFAAMJiiAiTQAjAQAPAAEJWwkfKgAyAAAuAAQKf0sAAwUACQnZJJIDAE0DAAUACQnZJJIDAE0DAA8ABQmZDxEpAMIAAAAA.Pleistarchus:BAAALgAECgYJCQAAAA==.',
Po='Poic:BAAALgADCgEJAQAAAA==.Poofighter:BAAALgAECgMJAwABLgAFFAIJBgAGAAohAA==.Poonan:BAAALgAECgYJBgAAAA==.',
Pp='Ppgangandlaw:BAAALgADCgEJAQAAAA==.',
Pr='Precious:BAAALgAECgYJEAAAAA==.Primalistic:BAAALgADCgUJBQABLgAECggJOAAOAG8ZAA==.Primàl:BAABLgAECn8pAAIHAAYJBRv2NADUAQAHAAYJBRv2NADUAQAAAA==.',
Pu='Purifieds:BAAALgADCgEJAQAAAA==.',
Qs='Qsrqasda:BAABLgAECn8UAAIPAAYJ4QWVLwCaAAAPAAYJ4QWVLwCaAAAAAA==.',
Qt='Qtmenopaws:BAAALgAECgQJAwAAAA==.Qtptt:BAACLgAFFH8SAAIaAAMJpB9JHQAPAQAaAAMJpB9JHQAPAQAuAAQKfzwAAhoACAkpI18RAJQCABoACAkpI18RAJQCAAAA.',
Ra='Ragedeath:BAABLgAFFH8GAAIPAAMJsw8KGgC3AAAPAAMJsw8KGgC3AAAAAA==.Ragedh:BAAALgAECgIJAgABLgAFFAMJBgAPALMPAA==.Ragemonk:BAAALgADCgQJBAABLgAFFAMJBgAPALMPAA==.Rasmong:BAAALgAECgYJDQAAAA==.Ravinsinda:BAAALgAECgYJBgAAAA==.Ravinursula:BAAALgAECgYJDQAAAA==.Rawrsaur:BAAALgAECgcJDQAAAA==.',
Re='Really:BAAALgADCgYJBgABLgAECgEJAQAIAAAAAA==.Redder:BAAALgAECgEJAQAAAA==.Retaliator:BAABLgAECn8mAAMbAAYJ0Rb1iQBnAQAbAAYJ0Rb1iQBnAQAmAAEJ1QZgRAAbAAAAAA==.Revan:BAAALgADCggJDgAAAA==.',
Rh='Rhýs:BAAALgAECgYJBgAAAA==.',
Ri='Rih:BAAALgADCgMJBQAAAA==.Ripits:BAAALgADCgcJCAABLgAECgEJAQAIAAAAAA==.Risky:BAAALgAECgkJAwAAAA==.Riskyfist:BAAALgAECgcJAgAAAA==.Risquae:BAAALgAECgEJAQAAAA==.',
Ro='Rocc:BAAALgAECgcJBAAAAA==.Rocketeer:BAABLgAECn8iAAIOAAgJ1gvhfgBFAQAOAAgJ1gvhfgBFAQAAAA==.Romulis:BAAALgAECgEJAQAAAA==.Ronburgundii:BAAALgAECgEJAQAAAA==.',
Ru='Rudrya:BAABLgAECn8UAAIlAAgJcAfhEwB8AQAlAAgJcAfhEwB8AQAAAA==.Runalish:BAAALgAECgEJAQAAAA==.Runarinis:BAAALgADCgIJAgAAAA==.',
Ry='Rynopinn:BAACLgAFFH8IAAIHAAMJIhbJJgDnAAAHAAMJIhbJJgDnAAAuAAQKfzoAAwcACAnqIxkLAOgCAAcACAnqIxkLAOgCABEAAQk5GLZkAEMAAAAA.Ryxn:BAAALgADCgYJBgAAAA==.',
['Rí']='Ríco:BAAALgADCgYJCwAAAA==.',
Sa='Saeed:BAAALgAECgEJAQAAAA==.Saelylasia:BAAALgAECgQJBQAAAA==.Sajaboy:BAAALgAECgIJAgAAAA==.Samusaran:BAAALgADCgEJAQAAAA==.Sarrania:BAAALgAECgUJBQAAAA==.Sartha:BAABLgAECn8cAAIbAAcJZxQ8XgB4AQAbAAcJZxQ8XgB4AQAAAA==.Sasuka:BAAALgADCgUJCwAAAA==.Satsu:BAAALgAECgEJAQAAAA==.',
Sc='Scatherlia:BAAALgADCgYJBQABLgAECgQJBQAIAAAAAA==.Sco:BAAALgADCgEJAQAAAA==.Screwthebull:BAAALgAECgQJBAAAAA==.Scrumpvincet:BAAALgADCgQJBQAAAA==.',
Se='Sectiondk:BAAALgAECgYJEwAAAA==.Sedda:BAACLgAFFH8UAAIbAAUJ0CI1DQCTAQAbAAUJ0CI1DQCTAQAuAAQKfy0AAhsACAmjJc4GAGMDABsACAmjJc4GAGMDAAAA.Seigfreid:BAAALgAECgYJCAAAAA==.Sensual:BAACLgAFFH8JAAImAAMJdwijCQCNAAAmAAMJdwijCQCNAAAuAAQKf0gAAiYACQlTFLgJAOYBACYACQlTFLgJAOYBAAAA.Seraphina:BAAALgAECgQJCgAAAA==.Sessano:BAAALgAECgYJCgAAAA==.Sesshomaru:BAACLgAFFH8GAAMGAAIJCiEjFwBjAAAGAAEJ0CMjFwBjAAASAAEJRB4EaABaAAAuAAQKf0sAAwYACQnPIy4HAHkCABIACAmwIRcTAOcCAAYACAkvJC4HAHkCAAAA.',
Sh='Shadoly:BAAALgAECgcJEQAAAA==.Shadowboss:BAABLgAECn8cAAIEAAYJ7RDuMQAOAQAEAAYJ7RDuMQAOAQAAAA==.Shamnslam:BAAALgAECgEJAQAAAA==.Shang:BAABLgAECn8pAAMRAAgJbyWFBADlAgARAAgJbyWFBADlAgAHAAEJCxNWywA0AAAAAA==.Shirona:BAABLgAECn8YAAISAAgJyxVYKwDfAQASAAgJyxVYKwDfAQAAAA==.Showstop:BAAALgAECgEJAQAAAA==.Shyvanna:BAABLgAECn8fAAMkAAgJsRFJJQBwAQAkAAgJsRFJJQBwAQAjAAQJ+gmHKwDBAAAAAA==.Shïnïgämï:BAABLgAECn8WAAInAAYJiCAvCQDeAQAnAAYJiCAvCQDeAQABLgAFFAIJBQAZACsbAA==.',
Si='Siare:BAAALgAECgYJEAAAAA==.Silica:BAAALgAECgMJAwAAAA==.Silvershot:BAAALgADCgUJBQAAAA==.Siner:BAAALgAECgUJCAAAAA==.',
Sk='Skeeter:BAABLgAECn8sAAQiAAkJVxr6BwCTAQAaAAkJAxdgOgC9AQAiAAcJ0hz6BwCTAQAhAAEJEBq2KgBJAAAAAA==.Skiadrum:BAACLgAFFH8FAAIoAAMJgQF6IwBwAAAoAAMJgQF6IwBwAAAuAAQKfzkAAxUACQlQDk0uAEYBABUACAniC00uAEYBACgABAlBCTRMAJEAAAAA.Skoliro:BAAALgAECgEJAQAAAA==.Skorch:BAAALgADCgkJEAABLgAECggJOAAOAG8ZAA==.',
Sm='Smotts:BAAALgAECgYJCwAAAA==.Smòtts:BAAALgAECgUJBgAAAA==.',
Sn='Snizard:BAAALgAECgUJDAAAAA==.Snuggiepoo:BAABLgAECn8kAAMCAAkJsh4yBwDHAgACAAgJ5CAyBwDHAgAEAAYJgRVXQgC6AAAAAA==.',
So='Songbirds:BAAALgADCgcJDQAAAA==.Sonichoos:BAAALgAECgUJDAAAAA==.Sophiel:BAABLgAECn8ZAAISAAYJ4BLwXgApAQASAAYJ4BLwXgApAQAAAA==.Sosthenna:BAAALgADCgkJCQAAAA==.Soulbark:BAAALgAECgMJAwABLgAECgQJBAAIAAAAAQ==.Souleater:BAAALgADCgMJAwAAAA==.Soulforged:BAAALgADCgcJCwABLgAECgQJBAAIAAAAAA==.Soulweaver:BAAALgAECgQJBAAAAQ==.',
Sp='Sparrowhåwk:BAAALgADCgUJBgAAAA==.Spongebill:BAAALgADCgEJAQAAAA==.Spàdes:BAABLgAECn8UAAMNAAYJmhkxSwB4AQANAAUJOB0xSwB4AQAJAAMJTA6pNwCSAAAAAA==.',
St='Starel:BAAALgADCgYJBwAAAA==.Stellanoova:BAAALgAECgMJAwABLgAECgcJFAAcAH4PAA==.Stevebushami:BAAALgAECgYJEAAAAA==.Stuwu:BAAALgADCgEJAQAAAA==.',
Su='Suou:BAAALgADCgcJCQABLgAECgEJAgAIAAAAAA==.Surj:BAAALgAECgYJEgAAAA==.',
Sv='Svmii:BAAALgADCgcJCgAAAA==.',
Ta='Taikuri:BAAALgAECgYJCgABLgAECgYJEAAIAAAAAA==.Tanddralndra:BAAALgAECgUJBgAAAA==.Tanklilbaby:BAAALgAECgEJAQAAAA==.Taxgirl:BAACLgAFFH8NAAMFAAQJ3hhWMABXAQAFAAQJ3hhWMABXAQAQAAEJsQMbFAA9AAAuAAQKfxwAAgUACAnOJGISAA0DAAUACAnOJGISAA0DAAAA.',
Te='Teralion:BAAALgAECgMJBQAAAA==.',
Th='Thaldreaux:BAAALgAECgMJBAAAAA==.Thefirst:BAAALgAECgEJAQAAAA==.Theleon:BAABLgAECn8dAAIRAAgJQQ/FIwBeAQARAAgJQQ/FIwBeAQAAAA==.Thordrin:BAABLgAECn8lAAIYAAcJVx88GABQAgAYAAcJVx88GABQAgAAAA==.Thorlan:BAAALgADCgYJCAAAAA==.Thrasherzs:BAAALgAECgUJCwAAAA==.Thunder:BAAALgADCgQJBAABLgAECgcJCgAIAAAAAA==.Thundergrasp:BAABLgAECn8ZAAIlAAcJxxdSDgBuAQAlAAcJxxdSDgBuAQABLgAFFAUJCwAEAB0NAA==.',
Ti='Tianhe:BAAALgAECgMJAwAAAA==.Tiarisaril:BAAALgAECgYJBgAAAA==.Tigercita:BAAALgAECgMJAgAAAA==.Tippah:BAAALgAECgEJAwAAAA==.Tippers:BAAALgAECgEJAQAAAA==.',
To='Toe:BAAALgAECgQJBAAAAA==.Tonkah:BAAALgAECgUJBQABLgAECgYJCAAIAAAAAA==.Topenga:BAACLgAFFH8KAAIBAAMJjBCYNQD1AAABAAMJjBCYNQD1AAAuAAQKf0oAAgEACQnNHxwJANkCAAEACQnNHxwJANkCAAAA.Touchypope:BAAALgADCgYJCwAAAA==.',
Tr='Treeage:BAAALgADCgMJAwAAAA==.Triggerd:BAAALgADCgEJAQAAAA==.Trunks:BAAALgADCgQJBAAAAA==.Trüst:BAAALgAECggJDgAAAA==.',
Tw='Twicelife:BAAALgAECgYJEwABLgAFFAMJCgAJALATAA==.',
Ty='Tyrygosa:BAAALgAECgUJBQABLgAFFAQJCwAaAMEWAA==.',
['Tå']='Tånk:BAAALgAECggJEwAAAA==.',
Un='Uneedsummilk:BAAALgADCgcJBwAAAA==.Unholyapollo:BAAALgADCgYJCwAAAA==.',
Ur='Urthstripe:BAABLgAECn8cAAIHAAcJBhmcJQDmAQAHAAcJBhmcJQDmAQAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCAAFAIkhAA==.Valle:BAAALgAECgIJAwABLgAFFAcJGQAEALUaAA==.Valoria:BAAALgAECgIJAwABLgAFFAcJGQAEALUaAA==.',
Ve='Veil:BAAALgAECgIJAgABLgAFFAcJGQAEALUaAA==.Velarenea:BAAALgADCgEJAQAAAA==.Velgabrine:BAAALgAECgYJDAABLgAFFAMJCQAbAHceAA==.Veraani:BAAALgAECgYJBgAAAA==.Verra:BAAALgADCgYJBgAAAA==.',
Vi='Vil:BAAALgADCgcJBgAAAA==.Virlan:BAAALgADCgQJBAAAAA==.Viserion:BAABLgAECn8UAAMcAAcJfg9xGgD2AAAcAAYJ2AxxGgD2AAAkAAYJVROuOwD2AAAAAA==.',
Vo='Voidchaosfan:BAAALgAECgQJBgABLgAECgQJCAAIAAAAAA==.',
Vu='Vue:BAACLgAFFH8IAAIYAAMJwQ2YIgDIAAAYAAMJwQ2YIgDIAAAuAAQKf0UAAhgACQkkG78PAF4CABgACQkkG78PAF4CAAAA.Vuldin:BAAALgAECgEJAgAAAA==.',
['Vö']='Völdemört:BAAALgADCgIJAgAAAA==.',
Wa='Wakasham:BAACLgAFFH8QAAIlAAUJFCJ2AQCAAQAlAAUJFCJ2AQCAAQAuAAQKfy4AAiUACQnrJZ4BAFMDACUACQnrJZ4BAFMDAAAA.Wardrake:BAAALgAECgEJAQAAAA==.',
We='Wehonoryou:BAABLgAECn8WAAIGAAYJ9CHYGAAAAgAGAAYJ9CHYGAAAAgAAAA==.Wetard:BAAALgADCgIJAgAAAA==.',
Wi='Willbyers:BAAALgAECgEJAQAAAA==.Winterloom:BAAALgAECgUJBQAAAA==.',
Wo='Wolfpacked:BAACLgAFFH8FAAIZAAIJKxsOPACbAAAZAAIJKxsOPACbAAAuAAQKfygAAhkACQlCILQEACsDABkACQlCILQEACsDAAAA.Wolfzbåin:BAAALgAECgQJBAAAAA==.',
Wr='Wroot:BAAALgADCgYJCQAAAA==.Wrotten:BAABLgAECn8UAAIiAAgJzhf0BgCsAQAiAAgJzhf0BgCsAQAAAA==.',
Wu='Wunderlust:BAACLgAFFH8HAAIOAAMJXBFpWQD2AAAOAAMJXBFpWQD2AAAuAAQKf0QAAg4ACQmFIdsKAPkCAA4ACQmFIdsKAPkCAAAA.',
Xe='Xemon:BAAALgAECgIJAgAAAA==.',
Xi='Xilyana:BAAALgAECgQJBAAAAA==.',
Xm='Xmatick:BAAALgAECgcJCQAAAA==.',
Xs='Xscrats:BAAALgAECgkJBwAAAA==.',
Ye='Yellowshaman:BAACLgAFFH8YAAIeAAUJthiWDgBSAQAeAAUJthiWDgBSAQAuAAQKfzEAAh4ACQl1ISULAHECAB4ACQl1ISULAHECAAAA.Yerac:BAAALgAECgEJAQAAAA==.',
Yu='Yukikage:BAAALgAECgMJAwAAAA==.Yutdaeng:BAAALgAECgMJBAAAAA==.',
Yv='Yvent:BAAALgADCgIJAgAAAA==.Yvraine:BAAALgAECgYJCwAAAA==.',
Za='Zakcarii:BAAALgADCgMJCAAAAA==.Zalicy:BAAALgAECgYJEwAAAA==.Zalogar:BAAALgAECgcJCgAAAA==.Zapper:BAAALgAECgQJCQAAAA==.',
Ze='Zealot:BAAALgAECgEJAQAAAA==.Zeeasyez:BAAALgAECgYJEQAAAA==.Zestul:BAAALgADCgEJAQAAAA==.',
Zh='Zhane:BAAALgADCgYJBwAAAA==.',
Zo='Zordon:BAAALgAECgYJEwAAAA==.',
Zu='Zugg:BAAALgAECgIJBAABLgAFFAcJGQAEALUaAA==.Zuriznikov:BAAALgADCgcJCgABLgAECgcJFAAcAH4PAA==.',
['Øf']='Øffspeck:BAABLgAECn8gAAQiAAkJVhzdBgCvAQAaAAgJwxgeLgBVAgAiAAcJICHdBgCvAQAhAAMJzh7MMAD3AAAAAA==.',
['Ør']='Ørb:BAAALgADCgEJAQAAAA==.',
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
