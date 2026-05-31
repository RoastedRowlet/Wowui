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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Priest-Discipline','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','DemonHunter-Havoc','Paladin-Holy','Druid-Restoration','Unknown-Unknown','Warrior-Arms','Rogue-Subtlety','Paladin-Retribution','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','Paladin-Protection','DeathKnight-Blood','DeathKnight-Frost','Druid-Balance','DemonHunter-Devourer','Rogue-Assassination','Mage-Arcane','Druid-Guardian','Monk-Brewmaster','Shaman-Restoration','Mage-Frost','Evoker-Preservation','Warrior-Protection','Shaman-Elemental','Monk-Mistweaver','Druid-Feral','Mage-Fire','Monk-Windwalker','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Evoker-Augmentation','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=46,date='2026-05-31',data={Aa='Aaron:BAAALgAECgEJAQABLgAECgkJIAABAFYcAA==.Aaronfreeze:BAACLgAFFH8HAAICAAMJehqdQgAEAQACAAMJehqdQgAEAQAuAAQKfzIAAgIACQn1HvwZAHYCAAIACQn1HvwZAHYCAAAA.',
Ab='Abrakazaam:BAAALgADCgEJAQAAAA==.',
Ad='Adrios:BAABLgAECn8mAAQDAAkJ0BY0FgAIAgADAAgJ/Rc0FgAIAgAEAAcJUQezTAC4AAAFAAMJyggkaQCIAAAAAA==.',
Ae='Aetherion:BAAALgAECgMJBAAAAA==.',
Aj='Ajaxz:BAABLgAECn8VAAIGAAkJ+RLTYADRAQAGAAkJ+RLTYADRAQAAAA==.',
Ak='Akaßoss:BAAALgADCgEJAQAAAA==.',
Al='Albedô:BAAALgAFFAIJAwABLgAFFAIJBgAHAAohAA==.Aleyefarmer:BAAALgAECgMJAwAAAA==.Aliren:BAAALgAECgYJCgAAAA==.Allmaick:BAAALgADCggJCAAAAA==.Alucard:BAABLgAFFH8KAAIIAAQJTAT0JgDYAAAIAAQJTAT0JgDYAAAAAA==.Alystrasza:BAABLgAECn8dAAIJAAYJvhYxQQB8AQAJAAYJvhYxQQB8AQAAAA==.',
Am='Amorlandian:BAAALgAECgMJAwAAAA==.',
An='Antimovsky:BAAALgAECgcJEQAAAA==.',
Ap='Aphroditê:BAAALgADCgYJBgABLgAECgcJCAAKAAAAAA==.',
Aq='Aqours:BAAALgADCgcJBwABLgAECgEJAgAKAAAAAA==.',
Ar='Arcan:BAAALgAECgIJAgAAAA==.',
Au='Augustine:BAAALgAECgEJAQAAAA==.Auroras:BAACLgAFFH8FAAMFAAMJEAbBIgCGAAAFAAMJEAbBIgCGAAAEAAEJmAF+NwAzAAAuAAQKfxcAAgUABwmEE5k0AGwBAAUABwmEE5k0AGwBAAAA.',
Av='Aviaria:BAAALgAECgQJBAAAAA==.Avìendha:BAAALgADCgQJBAAAAA==.',
['Aì']='Aìnzooalgown:BAABLgAFFH8PAAIGAAQJ4x+ILgB9AQAGAAQJ4x+ILgB9AQABLgAFFAIJBgAHAAohAA==.',
Ba='Babakubwa:BAAALgAECgMJAwAAAA==.Babylonfive:BAAALgAECgcJDQAAAA==.Balhair:BAAALgADCgYJBgAAAA==.Banish:BAAALgAECgMJAgABLgAECgcJCgAKAAAAAA==.Barragdan:BAAALgADCgEJAQAAAA==.Basandra:BAAALgAECgEJAQAAAA==.Basicc:BAAALgADCgMJAwAAAA==.',
Be='Beachbumm:BAAALgADCgEJAQAAAA==.Belleta:BAAALgAECggJDwAAAA==.Berserk:BAEBLgAECn8XAAILAAYJJyJQCAAyAgALAAYJJyJQCAAyAgABLgAFFAMJBQAMALwMAA==.Bertringer:BAAALgAECgEJAgABLgAECgYJBgAKAAAAAA==.',
Bi='Bigmack:BAAALgAECgYJCwABLgAFFAYJFQANANkXAA==.Bigwilli:BAAALgAECgcJEwAAAA==.Bingßong:BAAALgADCgYJEQAAAA==.Biscuit:BAACLgAFFH8PAAQCAAUJpR8qRAAAAQACAAQJvCIqRAAAAQAOAAIJ4hemHQCQAAAPAAIJ+xHkJgCGAAAuAAQKfyIABA4ACAmPIycPAMgCAA4ACAl9HScPAMgCAA8AAwnZHyc2APIAAAIABAk+HtWcAO4AAAAA.Bisha:BAABLgAECn9FAAMQAAkJEiHmDQDmAgAQAAkJ9CDmDQDmAgALAAYJcBiiLAABAQAAAA==.Bizcocho:BAAALgAECgcJDAAAAA==.',
Bl='Black:BAAALgADCgEJAQAAAA==.Bloodsimple:BAAALgADCgUJBQAAAA==.Blákers:BAABLgAFFH8HAAIRAAQJRBx3AwBOAQARAAQJRBx3AwBOAQAAAA==.',
Bo='Boic:BAAALgADCgQJBAAAAA==.Bonesofdoom:BAACLgAFFH8HAAISAAMJ1w0oJACkAAASAAMJ1w0oJACkAAAuAAQKfyIAAxIACAmJGycWAJ8BABIACAmJGycWAJ8BAAYAAQm3BLhwASMAAAAA.Boogsta:BAACLgAFFH8JAAITAAMJ7AOREwC1AAATAAMJ7AOREwC1AAAuAAQKfy0AAhMACQmWEXEIANsBABMACQmWEXEIANsBAAAA.Boomkingobrr:BAACLgAFFH8HAAIUAAMJ9wiFLQCnAAAUAAMJ9wiFLQCnAAAuAAQKfxsAAhQACQkOHEQLAOECABQACQkOHEQLAOECAAAA.Boops:BAAALgAECgEJAQAAAA==.Bootysweatt:BAABLgAECn8aAAIHAAYJNhtqJACaAQAHAAYJNhtqJACaAQAAAA==.Boss:BAAALgADCgEJAQAAAA==.',
Br='Brewnz:BAAALgAECgUJBgAAAA==.Brucewee:BAAALgAECgQJCQAAAA==.',
Bu='Buckits:BAAALgAECgcJEgAAAA==.Bunsey:BAAALgADCgIJAgAAAA==.Burnsx:BAAALgAECgUJCgABLgAFFAgJGAAVAEoeAA==.Bussyman:BAAALgAECgYJEQABLgAFFAMJCQAJACIWAA==.',
Bw='Bwoar:BAAALgAECgQJBgAAAA==.',
['Bø']='Bøw:BAAALgAECgMJAwAAAA==.',
['Bü']='Bübble:BAAALgADCgEJAQAAAA==.',
Ca='Captnmurloc:BAAALgAECgkJEQAAAA==.Carl:BAAALgAECgEJAgABLgAFFAcJDgAWAJAaAA==.Carrach:BAAALgAECgIJAwAAAA==.Caveyodeler:BAAALgAECgQJCgAAAA==.',
Ce='Cedar:BAAALgAECgQJCwAAAA==.',
Ch='Cherga:BAAALgADCgYJBgAAAA==.Chinegga:BAAALgADCgYJBgAAAA==.Chitose:BAAALgADCgUJBQABLgAECgEJAgAKAAAAAA==.Chrapsasspee:BAAALgADCgcJGQAAAA==.Chrinn:BAAALgADCgIJAgAAAA==.',
Ci='Cindele:BAAALgADCgMJAwAAAA==.Cirvix:BAAALgAECgYJDAAAAA==.Cirxe:BAABLgAECn8iAAIXAAkJMg7gAwC4AQAXAAkJMg7gAwC4AQAAAA==.',
Cl='Clampire:BAAALgAECgQJBAAAAA==.Cliint:BAAALgAECgcJCwAAAA==.Cloúnt:BAAALgAECgEJAgABLgAFFAMJBwAUAPcIAA==.',
Co='Commotionn:BAAALgAECgQJBAAAAA==.Coms:BAAALgADCgIJAgAAAA==.Cooz:BAAALgAECgYJDgAAAA==.Corybooker:BAAALgAECgcJBAAAAA==.Cowdux:BAAALgAECgkJEAAAAA==.',
Cr='Creamdragon:BAAALgADCgYJCgABLgADCgcJDAAKAAAAAA==.',
Cu='Curuni:BAAALgADCgcJDAAAAA==.',
Cz='Czechhunter:BAAALgADCgUJBQAAAA==.',
['Cå']='Cåleb:BAAALgAECgEJAQAAAA==.',
['Cø']='Cønstance:BAABLgAECn8VAAIYAAcJvRGDIAAnAQAYAAcJvRGDIAAnAQAAAA==.',
Da='Daddyphat:BAABLgAECn8rAAIZAAgJrCTVBQDSAgAZAAgJrCTVBQDSAgAAAA==.Daddý:BAAALgAECgEJAQAAAA==.Dalight:BAABLgAECn8XAAIIAAYJKiYPDwCdAgAIAAYJKiYPDwCdAgAAAA==.Dankins:BAACLgAFFH8bAAIaAAcJUyKIAgCCAgAaAAcJUyKIAgCCAgAuAAQKfxYAAhoACAkGHfYZAEcCABoACAkGHfYZAEcCAAAA.',
De='Deathmager:BAABLgAECn8wAAIbAAkJWA8YUwDMAQAbAAkJWA8YUwDMAQAAAA==.Deathtraper:BAAALgAECgcJDQAAAA==.Debur:BAAALgADCgEJAQAAAA==.Deltaka:BAAALgAECgEJAQAAAA==.Demonfella:BAAALgADCgMJAwAAAA==.Demonicpeach:BAABLgAECn8YAAIBAAcJwwsYngD5AAABAAcJwwsYngD5AAAAAA==.Denaian:BAAALgADCgYJBgAAAA==.Dethsent:BAAALgAECggJEQAAAA==.Dette:BAABLgAECn8cAAICAAgJWhS5PQDVAQACAAgJWhS5PQDVAQAAAA==.Devilchaser:BAAALgAECgYJCwAAAA==.Devourer:BAABLgAECn8VAAIVAAcJjg+mbQBaAQAVAAcJjg+mbQBaAQAAAA==.',
Di='Diaval:BAAALgADCgIJAgABLgAECgkJLAABAFsTAA==.Dinosforlife:BAAALgAECgYJBgAAAA==.',
Do='Donzilly:BAAALgAECgYJDgAAAA==.Doreme:BAAALgADCgIJAgAAAA==.',
Dr='Drafted:BAAALgAECgcJEAAAAA==.Drax:BAAALgAECgMJAwAAAA==.Drewmcmoo:BAAALgADCgcJBgAAAA==.Drsath:BAAALgADCgcJBwAAAA==.Drunkorca:BAAALgADCgUJBQAAAA==.',
Ea='Earnar:BAAALgADCgYJDAAAAA==.',
Ed='Edarix:BAAALgADCggJDAABLgAECggJMgANAHkYAA==.',
Ei='Eiliyah:BAABLgAECn8yAAMIAAgJehz0FgBaAgAIAAgJehz0FgBaAgANAAIJHwIaWgElAAAAAA==.',
Ek='Ekmek:BAAALgAECgEJAQAAAA==.',
El='Elabernathy:BAABLgAECn8sAAICAAkJKhabIgBEAgACAAkJKhabIgBEAgAAAA==.Elenay:BAABLgAECn8UAAIJAAgJqR7KIAAwAgAJAAgJqR7KIAAwAgAAAA==.Elesia:BAAALgAECgkJEgAAAA==.Elfussy:BAAALgAECgEJAQAAAA==.Elgoku:BAAALgAECgQJCgABLgAECgUJDAAKAAAAAA==.Eliarssande:BAAALgADCgQJBAAAAA==.Elinay:BAAALgADCgcJCQABLgAECggJFAAJAKkeAA==.Elixia:BAABLgAECn8bAAIHAAgJDA0mIQBNAQAHAAgJDA0mIQBNAQAAAA==.Elpatron:BAAALgAFFAMJAwABLgAFFAMJCAAcABoNAA==.Elylanea:BAAALgAECgUJDgAAAA==.',
Em='Emulsdeath:BAABLgAECn8UAAMSAAgJKCHGEADmAQASAAcJLB7GEADmAQAGAAYJ8iCMYQCTAQABLgAFFAQJDQANAOQiAA==.Emulsifier:BAACLgAFFH8NAAINAAQJ5CKcEwCYAQANAAQJ5CKcEwCYAQAuAAQKfzAAAg0ACAmFJn4KAAADAA0ACAmFJn4KAAADAAAA.',
En='Ennoa:BAAALgAECgEJAQAAAA==.',
Er='Ergen:BAACLgAFFH8WAAIPAAUJthr5DABRAQAPAAUJthr5DABRAQAuAAQKfyoAAg8ACAlvIaUGAJcCAA8ACAlvIaUGAJcCAAAA.',
Eu='Eusexua:BAAALgAECgQJBQABLgAECgcJCgAKAAAAAA==.',
Ex='Expiatory:BAAALgAECgYJCAAAAA==.',
Fa='Fairbear:BAABLgAECn8dAAQQAAYJ+ByoNABkAQAQAAYJ+ByoNABkAQALAAEJZA5tPgA7AAAdAAEJ6QfjVQAbAAAAAA==.Faustt:BAAALgAECgUJBwAAAA==.',
Fi='Filthyfabio:BAAALgADCgcJEQAAAA==.Finester:BAAALgAFFAMJBAAAAA==.Fireburr:BAAALgAECgMJAwAAAA==.',
Fl='Flatline:BAAALgAECgcJEgAAAA==.Fløw:BAAALgAECgMJCgAAAA==.',
Fr='Fragglerott:BAABLgAECn8aAAMeAAgJ1Aq6WgC6AAAeAAgJ1Aq6WgC6AAAaAAQJUhIvhgCxAAAAAA==.Frati:BAAALgAECgEJAQAAAA==.Friedchickn:BAAALgAECgQJCAAAAA==.Frosttrinity:BAAALgADCgUJBAAAAA==.',
Fu='Funslinger:BAAALgAECgQJDAAAAA==.',
Ga='Gaffz:BAAALgAECgEJAgAAAA==.Galannar:BAAALgAECggJDQAAAA==.Galvrax:BAAALgAECgUJCgAAAA==.Gast:BAACLgAFFH8NAAIQAAQJMRxtFgBEAQAQAAQJMRxtFgBEAQAuAAQKfzMAAxAACQnHH2APAG4CABAACQnHH2APAG4CAB0ABAmpFh0xAKQAAAAA.',
Ge='Gearwick:BAAALgADCgYJBwABLgAECgcJJgAIAFAhAA==.',
Gh='Ghstfacekila:BAAALgADCgEJAQAAAA==.',
Go='Gorska:BAABLgAECn8wAAIeAAkJmBz0EABWAgAeAAkJmBz0EABWAgAAAA==.',
Gr='Grawm:BAABLgAECn8iAAMOAAkJqiKzHgAxAgAOAAgJSRWzHgAxAgACAAkJPiAXRQC9AQAAAA==.Greedory:BAAALgADCgIJAgAAAA==.Groot:BAAALgADCgUJBgAAAA==.Gruetss:BAAALgAECgQJBAAAAA==.',
['Gä']='Gämbit:BAAALgADCgEJAQAAAA==.',
Ha='Hailbringer:BAAALgAECgcJDgAAAA==.Hakoona:BAABLgAECn8yAAIZAAkJFxr/DwAuAgAZAAkJFxr/DwAuAgAAAA==.Hanginaround:BAAALgAECgEJAQAAAA==.Hangman:BAACLgAFFH8SAAIIAAMJCSUoGgA5AQAIAAMJCSUoGgA5AQAuAAQKfxsAAwgACAloH3gNAKYCAAgACAloH3gNAKYCAA0AAwkbCRk6AVcAAAEuAAUUAwkJAAkAIhYA.Hanni:BAABLgAECn8dAAIOAAgJUhweCgC4AQAOAAgJUhweCgC4AQAAAA==.Haveaburitto:BAACLgAFFH8NAAIbAAQJWBw+SwA4AQAbAAQJWBw+SwA4AQAuAAQKfygAAhsACAk0JXkMAGEDABsACAk0JXkMAGEDAAAA.Hawktoetem:BAAALgAECgUJCAABLgAECgYJHQAQAPgcAA==.',
He='Healmemaybe:BAABLgAECn8bAAIJAAYJQiNGIAAzAgAJAAYJQiNGIAAzAgAAAA==.Healthyadult:BAAALgAECgMJBQAAAA==.Hellshand:BAAALgAECgYJDAAAAA==.Heracles:BAAALgAECgQJBAAAAA==.Heretic:BAAALgADCgEJAQAAAA==.',
Hi='Hickscale:BAAALgADCgMJAwAAAA==.',
Ho='Holycøw:BAAALgADCgMJAwAAAA==.Holydefender:BAAALgADCgcJDQAAAA==.Holyhands:BAAALgADCgYJBgAAAA==.Holyholyholy:BAAALgAECgQJBgAAAA==.Honest:BAAALgADCgMJAwAAAA==.',
Hu='Hunniee:BAAALgAECgEJAQAAAA==.Huntrix:BAAALgADCgcJEgAAAA==.',
Ic='Icedatt:BAABLgAECn8VAAMGAAUJ8QJEDAF8AAAGAAUJ7AJEDAF8AAASAAUJcwEATABKAAAAAA==.Icefire:BAAALgADCgUJBAAAAA==.',
Ik='Ikur:BAACLgAFFH8PAAIIAAQJrxv7GABDAQAIAAQJrxv7GABDAQAuAAQKfzsAAggACQmTHkoGABkDAAgACQmTHkoGABkDAAAA.',
Il='Ilinia:BAAALgAECgYJCAABLgAECgUJEgAKAAAAAA==.',
Im='Imsteve:BAAALgAECgEJAQAAAA==.',
In='Infoxicated:BAAALgADCgcJCAABLgAECgkJJAADALIeAA==.Insîght:BAAALgAECgQJCAAAAA==.',
Ip='Ipopkidneys:BAACLgAFFH8UAAMMAAYJICLQDwBqAQAMAAUJ4yHQDwBqAQAWAAMJjB3qBQD9AAAuAAQKfycAAwwACQnhJYQMANACAAwACQnhJYQMANACABYAAQn1I3ocAGYAAAAA.',
Ir='Iroi:BAAALgAECgIJBQAAAA==.',
Is='Iskur:BAABLgAECn8hAAIaAAgJ4BjwHgA/AgAaAAgJ4BjwHgA/AgABLgAFFAQJDwAIAK8bAA==.Isuck:BAAALgAFFAIJAgAAAA==.Isurr:BAABLgAECn8iAAIfAAcJnhJnMQCIAQAfAAcJnhJnMQCIAQABLgAFFAQJDwAIAK8bAA==.',
It='Itakecandle:BAAALgAECgUJBwABLgAECgUJDAAKAAAAAA==.',
Iv='Ivanapump:BAAALgAECgIJAgABLgAECgYJBgAKAAAAAA==.',
Ja='Jackkal:BAAALgAECgMJAwAAAA==.Jadethecat:BAAALgADCgMJAwAAAA==.Jakbis:BAAALgADCgEJAQAAAA==.Jakychan:BAAALgAECgEJAQAAAA==.Jaldiar:BAAALgADCgcJBwABLgAECgYJBgAKAAAAAA==.Jametrok:BAAALgAECgEJAQAAAA==.Jazbek:BAAALgAECgQJDgAAAA==.Jazzonus:BAAALgAECgQJBAAAAA==.',
Je='Jefferey:BAAALgADCgMJAwAAAA==.Jennyanydots:BAAALgAECgIJBAABLgAFFAcJGgAEALAaAA==.Jeriçho:BAAALgADCgYJBgAAAA==.',
Jh='Jhonwick:BAAALgAECgIJAgAAAA==.',
Ji='Jippedo:BAAALgAECgYJAgABLgAECgcJBAAKAAAAAA==.Jiraîya:BAAALgAECgQJBQAAAA==.',
Jo='Jordak:BAABLgAECn8oAAIJAAkJBBxWDADsAgAJAAkJBBxWDADsAgAAAA==.Jorolee:BAAALgADCgEJAQAAAA==.',
Ka='Kallistos:BAABLgAECn8gAAIaAAcJER3RKAACAgAaAAcJER3RKAACAgAAAA==.Kariza:BAAALgAECgQJBgAAAA==.Karunik:BAAALgADCgYJBgABLgAECgcJCgAKAAAAAA==.',
Ke='Kelenheller:BAAALgADCgcJCAAAAA==.',
Kh='Khione:BAAALgADCgYJBgAAAA==.Khthonios:BAAALgAECgEJAQAAAA==.',
Ki='Kibblerina:BAAALgADCgcJBwAAAA==.Kiranam:BAABLgAECn8cAAQgAAgJrQ6dEQCTAQAgAAgJqQqdEQCTAQAYAAcJNQwGMADHAAAUAAIJWwfecQBZAAAAAA==.',
Kn='Knarth:BAABLgAECn80AAIhAAkJHRwlAQCkAgAhAAkJHRwlAQCkAgAAAA==.Kníght:BAAALgAECgUJBQAAAA==.',
Ko='Koisy:BAAALgAECgIJCgABLgAECggJFAAJAKkeAA==.Kole:BAAALgAECgEJAQAAAA==.Koopa:BAABLgAECn8pAAIQAAkJ0yR7BAAOAwAQAAkJ0yR7BAAOAwAAAA==.',
Kr='Krasul:BAACLgAFFH8VAAMaAAUJEBjIGgBpAQAaAAUJEBjIGgBpAQAeAAIJ7QmdPAB3AAAuAAQKfx8AAxoACAkXIecIAOgCABoACAkXIecIAOgCAB4ABgm/HPIxAJQBAAAA.Krenthok:BAABLgAECn8eAAIBAAgJiQc8fQA1AQABAAgJiQc8fQA1AQAAAA==.',
Ku='Kuraha:BAAALgAECgQJBAAAAA==.Kushar:BAAALgAECgQJBQABLgAECggJFwAiAMQQAA==.',
Ky='Kyuketsuki:BAAALgAFFAIJAgAAAA==.',
La='Large:BAAALgADCgYJBgAAAA==.Largemann:BAAALgAECgYJDAABLgAFFAQJEQAGAPkYAA==.Lathspell:BAABLgAECn8yAAIbAAkJtiAMIQCGAgAbAAkJtiAMIQCGAgAAAA==.Lazyevoker:BAAALgADCgQJBAABLgAECgEJAQAKAAAAAA==.',
Le='Leahan:BAAALgAECgQJCgAAAA==.Leloo:BAAALgADCgYJCgABLgAECgIJAwAKAAAAAA==.',
Lh='Lhureciv:BAACLgAFFH8RAAMEAAQJERnpEQA4AQAEAAQJERnpEQA4AQADAAEJKRtEPQBIAAAuAAQKf0oAAwQACQnVI9IIAKoCAAQACQnVI9IIAKoCAAMABgn7HjAjAHoBAAAA.',
Li='Lightchaser:BAAALgADCgMJAgAAAA==.Lightfkyou:BAAALgADCgcJCgAAAA==.Lihvurce:BAABLgAECn8eAAMNAAgJXBoxOAAKAgANAAgJXBoxOAAKAgAIAAQJpR0FSwBMAQABLgAFFAQJEQAEABEZAA==.Lillianna:BAACLgAFFH8FAAIMAAIJoQ98KwCZAAAMAAIJoQ98KwCZAAAuAAQKfzMAAgwACAmSG38MAEgCAAwACAmSG38MAEgCAAAA.Lingchi:BAAALgAECgQJBgAAAA==.',
Ll='Llew:BAAALgAECgMJBAAAAA==.',
Lo='Loenhart:BAAALgAECgEJAQAAAA==.Lolkurtone:BAAALgAECgIJAgAAAA==.',
Lu='Luciaan:BAAALgADCgcJGAAAAA==.Lucrative:BAAALgADCgcJDQAAAA==.Lug:BAAALgAECgEJAQAAAA==.Lulue:BAAALgADCgQJBAAAAA==.Luminari:BAAALgADCgUJBQAAAA==.Lunastorm:BAACLgAFFH8KAAIcAAQJLxOmFQAfAQAcAAQJLxOmFQAfAQAuAAQKfzYAAhwACQlhIe4CAB4DABwACQlhIe4CAB4DAAAA.Luponero:BAACLgAFFH8UAAMCAAQJiSO0EQCWAQACAAQJiSO0EQCWAQAOAAEJ5QapKgBGAAAuAAQKfyEAAw4ACAnnHuYQALUCAA4ACAl6HeYQALUCAAIAAwnNHw6KABQBAAAA.',
Ly='Lynney:BAAALgADCgYJBwAAAA==.',
Ma='Macmn:BAACLgAFFH8RAAIeAAQJdhh2GgAjAQAeAAQJdhh2GgAjAQAuAAQKfygAAh4ABwnAJGULAOICAB4ABwnAJGULAOICAAAA.Magicard:BAABLgAECn8fAAIbAAgJjg65bgCFAQAbAAgJjg65bgCFAQAAAA==.Makesfood:BAABLgAECn8qAAIbAAcJZBeSdADpAQAbAAcJZBeSdADpAQAAAA==.Mamaheals:BAABLgAECn8qAAIFAAkJeRnaFwD7AQAFAAkJeRnaFwD7AQAAAA==.Mandos:BAAALgAECgYJBgAAAA==.Mantistabogn:BAAALgAFFAEJAQAAAA==.Maor:BAABLgAECn8XAAINAAgJlxcuUADxAQANAAgJlxcuUADxAQAAAA==.March:BAAALgADCgEJAQAAAA==.Markeisha:BAAALgAECgQJCAABLgAECgYJDAAKAAAAAA==.',
Me='Mechz:BAAALgAECgYJBgABLgAFFAQJCQAbAPwKAA==.Mechzician:BAACLgAFFH8JAAIbAAQJ/ArZZgD6AAAbAAQJ/ArZZgD6AAAuAAQKfzgAAhsACAlwGf1SAMwBABsACAlwGf1SAMwBAAAA.Mechzlock:BAAALgADCgEJAQABLgAFFAQJCQAbAPwKAA==.Melinoe:BAAALgAECgEJAQAAAA==.Merlerk:BAAALgADCgYJBgAAAA==.Merlini:BAABLgAECn8cAAMEAAcJOhbLKgBfAQAEAAYJLBnLKgBfAQADAAUJThZrNgAXAQAAAA==.Mets:BAAALgAECgYJBwABLgAECgcJDgAKAAAAAA==.',
Mi='Microplastic:BAAALgAECgUJBQAAAA==.Micspanky:BAAALgAECggJEgAAAA==.Mithrandi:BAAALgAECgYJCQAAAA==.Mitzis:BAABLgAFFH8IAAICAAMJ8x8GPQAWAQACAAMJ8x8GPQAWAQAAAA==.',
Mo='Moltten:BAAALgADCgUJCQAAAA==.Mornhathor:BAAALgAECggJDgABLgAECgYJBgAKAAAAAA==.',
Mu='Mufinblaster:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgADCgIJBgAAAA==.Musnicker:BAAALgAECgQJBwABLgAECgcJGQAOANYPAA==.',
My='Myro:BAACLgAFFH8UAAMaAAQJ3B+4HQBXAQAaAAQJ3B+4HQBXAQAeAAIJZRRMNgCMAAAuAAQKfxsAAhoABwm/JsEHAPkCABoABwm/JsEHAPkCAAAA.',
['Mè']='Mètis:BAAALgAECgcJCAAAAA==.',
Na='Nanis:BAAALgAECgYJBgABLgAFFAMJBwAUAB8gAA==.Narmer:BAAALgAECgIJAgAAAA==.',
Ne='Neel:BAAALgADCgQJBQAAAA==.Nervhoost:BAAALgADCgMJAwAAAA==.Neuropolis:BAAALgADCgcJFQAAAA==.Neuroscience:BAAALgADCgMJAwAAAA==.Neurotics:BAABLgAECn8sAAQjAAgJByVcAwBMAgAjAAcJoiNcAwBMAgAkAAYJBiAMBwDkAQABAAUJ5BoBuwDjAAAAAA==.Neò:BAABLgAECn8YAAMlAAYJvBACDwAKAQAlAAYJXw4CDwAKAQAmAAEJ/hSmggA4AAAAAA==.',
Ni='Niesh:BAAALgAECgEJBwAAAA==.Nineoneone:BAABLgAECn8sAAMFAAgJORMgIACuAQAFAAgJORMgIACuAQADAAQJjgPqRQCLAAAAAA==.',
No='Nobledecay:BAAALgAECgQJBQAAAA==.Nocturne:BAAALgAECgEJAwAAAA==.',
Nu='Nubbletcake:BAAALgADCgEJAQABLgAECgkJJAADALIeAA==.Nula:BAAALgAECgEJAQABLgAFFAcJGgAEALAaAA==.',
Ny='Nylveth:BAACLgAFFH8OAAIEAAUJNg/PFwARAQAEAAUJNg/PFwARAQAuAAQKfyoAAgQACQkAHVsOAFcCAAQACQkAHVsOAFcCAAEuAAUUBgkHACcA+woA.',
Oc='Ocra:BAABLgAECn8eAAInAAgJnwyYEgBvAQAnAAgJnwyYEgBvAQABLgAFFAQJEgACADEZAA==.',
Of='Offspeck:BAAALgAECgIJAgABLgAECgkJIAABAFYcAA==.',
Ou='Outtkast:BAAALgAECgIJAgAAAA==.Outtkastt:BAAALgAECgEJAQAAAA==.Ouutkast:BAAALgAECgEJAgAAAA==.',
Oz='Ozwald:BAABLgAECn81AAIPAAkJchy+DgAzAgAPAAkJchy+DgAzAgAAAA==.',
Pa='Pallyangel:BAAALgADCgcJDwAAAA==.Pandemul:BAAALgAECgMJAwABLgAFFAQJDQANAOQiAA==.Patrio:BAACLgAFFH8IAAIcAAMJGg1pHQCyAAAcAAMJGg1pHQCyAAAuAAQKfywAAhwACQllGTgHAHYCABwACQllGTgHAHYCAAAA.',
Pe='Peaceonea:BAABLgAECn8ZAAIVAAgJTgQUpQC8AAAVAAgJTgQUpQC8AAAAAA==.Peachaid:BAECLgAFFH8YAAIDAAgJ9RfkBACnAgADAAgJ9RfkBACnAgAuAAQKfzAAAwMACQlVIqkEADEDAAMACQlVIqkEADEDAAUABgkYHSglAMABAAAA.Peatri:BAAALgAECgkJCwAAAA==.Peetree:BAAALgAFFAIJAgAAAA==.',
Ph='Phosphorus:BAACLgAFFH8SAAMLAAQJFhUvFAAXAQALAAQJihMvFAAXAQAdAAIJjxTQHQCOAAAuAAQKf1cAAwsACQnHHnkEALwCAAsACQnHHnkEALwCAB0ABAlNHusmAOQAAAAA.',
Pl='Plagüë:BAACLgAFFH8NAAMSAAQJuRw1IQC7AAAGAAMJiiCRbAAJAQASAAMJ3RA1IQC7AAAuAAQKf0sAAwYACQnaJDMRANMCAAYACQnaJDMRANMCABIABQmbD6wzALQAAAAA.Pleistarchus:BAAALgAECgYJCQAAAA==.',
Po='Poic:BAAALgADCgEJAQAAAA==.Polo:BAAALgADCgEJAQAAAA==.Poofighter:BAAALgAECgMJAwABLgAFFAIJBgAHAAohAA==.Poonan:BAAALgAECgYJBgAAAA==.',
Pp='Ppgangandlaw:BAAALgADCgEJAQAAAA==.',
Pr='Precious:BAAALgAECgYJEAAAAA==.Primalistic:BAAALgADCgUJBQABLgAFFAQJCQAbAPwKAA==.Primàl:BAABLgAECn8sAAIJAAYJBRv2NADUAQAJAAYJBRv2NADUAQAAAA==.',
Pu='Punchinbag:BAAALgADCgYJBgAAAA==.Purifieds:BAAALgADCgEJAQAAAA==.',
Qs='Qsrqasda:BAABLgAECn8UAAISAAYJ4QVpOQCWAAASAAYJ4QVpOQCWAAAAAA==.',
Qt='Qtmenopaws:BAAALgAECgQJAwAAAA==.Qtptt:BAACLgAFFH8SAAIBAAMJpB9JHQAPAQABAAMJpB9JHQAPAQAuAAQKfz4AAgEACAkpIywWAJUCAAEACAkpIywWAJUCAAAA.',
Ra='Ragedeath:BAABLgAFFH8JAAISAAMJuA/ZIwCnAAASAAMJuA/ZIwCnAAABLgAFFAQJBAAKAAAAAA==.Ragedh:BAAALgAECgIJAgABLgAFFAQJBAAKAAAAAA==.Ragemonk:BAAALgADCgQJBAABLgAFFAQJBAAKAAAAAA==.Rageshaman:BAAALgAFFAQJBAAAAA==.Rasmong:BAABLgAECn8XAAIiAAgJxBDTIwB+AQAiAAgJxBDTIwB+AQAAAA==.Ravinsinda:BAAALgAECgYJBgAAAA==.Ravinursula:BAAALgAECgYJDQAAAA==.Rawrsaur:BAAALgAECgcJDQAAAA==.',
Re='Really:BAAALgADCgYJBgABLgAECgEJAQAKAAAAAA==.Reallyhpal:BAAALgAECgEJAQAAAA==.Redder:BAAALgAECgEJAQAAAA==.Retaliator:BAABLgAECn8yAAMNAAgJeRh0XAChAQANAAgJeRh0XAChAQARAAMJuAzlMwB6AAAAAA==.Reuuín:BAAALgAECgUJBQABLgAECggJFgAMAIYYAA==.Revan:BAAALgAECgYJBwAAAA==.',
Rh='Rhýs:BAAALgAECgYJBgAAAA==.',
Ri='Rih:BAAALgADCgMJBQAAAA==.Ripits:BAAALgADCgcJCAABLgAECgEJAQAKAAAAAA==.Risky:BAAALgAECgkJAwABLgAFFAIJAgAKAAAAAA==.Riskyfist:BAAALgAECgcJAgAAAA==.Risquae:BAAALgAECgIJAwAAAA==.',
Ro='Roadrashnuts:BAAALgAECgQJBQAAAA==.Rocc:BAAALgAECgcJBAAAAA==.Rocketeer:BAABLgAECn8kAAIbAAgJ1gvamwApAQAbAAgJ1gvamwApAQAAAA==.Romulis:BAAALgAECgEJAQAAAA==.Ronburgundii:BAAALgAECgEJAQAAAA==.',
Ru='Rudrya:BAABLgAECn8UAAInAAgJcAfhEwB8AQAnAAgJcAfhEwB8AQAAAA==.Rumpkey:BAAALgADCgcJCgAAAA==.Runalish:BAAALgAECgEJAQAAAA==.Runarinis:BAAALgADCgIJAgAAAA==.',
Ry='Rynopinn:BAACLgAFFH8JAAIJAAMJIha/MgDXAAAJAAMJIha/MgDXAAAuAAQKf0YABAkACAnqIxkLAOgCAAkACAnqIxkLAOgCACAABwm6G04LAOcBABQAAgn4F6pcAIcAAAAA.Ryxn:BAAALgADCgYJBgAAAA==.',
['Rí']='Ríco:BAAALgADCgYJEAAAAA==.',
Sa='Saeed:BAAALgAECgEJAQAAAA==.Saelylasia:BAAALgAECgQJBQAAAA==.Sajaboy:BAAALgAECgMJBAAAAA==.Samusaran:BAAALgADCgEJAQAAAA==.Sarrania:BAAALgAECgUJBQAAAA==.Sartha:BAABLgAECn8jAAINAAgJ4xQZUADBAQANAAgJ4xQZUADBAQAAAA==.Sasuka:BAAALgAECgcJCAAAAA==.Satsu:BAAALgAECgEJAQAAAA==.',
Sc='Scatherlia:BAAALgADCgYJBQABLgAECgQJBQAKAAAAAA==.Sco:BAAALgADCgEJAQABLgAECgYJDQAKAAAAAA==.Screwthebull:BAAALgAECgQJBAAAAA==.Scrumpvincet:BAAALgADCgQJBQAAAA==.',
Se='Sectiondk:BAAALgAECgYJEwAAAA==.Sedda:BAACLgAFFH8YAAINAAYJVSMNCwDhAQANAAYJVSMNCwDhAQAuAAQKfy0AAg0ACAmnJc4GAGMDAA0ACAmnJc4GAGMDAAAA.Seigfreid:BAAALgAECgYJCAAAAA==.Sensual:BAACLgAFFH8NAAIRAAQJ5AYsCwCpAAARAAQJ5AYsCwCpAAAuAAQKf0kAAhEACQlTFIYQAKMBABEACQlTFIYQAKMBAAAA.Seraphina:BAAALgAECgQJCgAAAA==.Sessano:BAAALgAECgYJDQAAAA==.Sesshomaru:BAACLgAFFH8GAAMHAAIJCiHSIABXAAAHAAEJ0CPSIABXAAAVAAEJRB5KgABUAAAuAAQKf1MAAxUACQnUIxcTAOcCABUACAm3IRcTAOcCAAcACAkvJEEKAGkCAAAA.',
Sh='Shadoly:BAAALgAECgcJEQAAAA==.Shadowboss:BAABLgAECn8iAAIEAAYJixF+OgAHAQAEAAYJixF+OgAHAQAAAA==.Shamnslam:BAAALgAECgEJAQAAAA==.Shang:BAACLgAFFH8HAAMUAAMJHyDHGwAVAQAUAAMJHyDHGwAVAQAJAAEJswNWawAxAAAuAAQKfzEABBQACQksJRsCAE8DABQACQksJRsCAE8DABgAAwm+HgI1ALAAAAkAAgnDEsfBADcAAAAA.Shiftchi:BAAALgAECgEJAQAAAA==.Shirona:BAABLgAECn8nAAIVAAkJ1B9jCgDmAgAVAAkJ1B9jCgDmAgAAAA==.Shockazulu:BAAALgADCgEJAQAAAA==.Showstop:BAAALgAECgEJAQAAAA==.Shyvanna:BAABLgAECn8mAAMmAAkJyBHYIAC5AQAmAAkJyBHYIAC5AQAlAAQJ0wqHKwDBAAAAAA==.Shïnïgämï:BAABLgAECn8WAAIoAAYJiCAvCQDeAQAoAAYJiCAvCQDeAQABLgAFFAIJBgAaABwcAA==.',
Si='Siare:BAABLgAECn8UAAIBAAYJEBjSfQA0AQABAAYJEBjSfQA0AQABLgAECgcJDgAKAAAAAA==.Sigarda:BAAALgAECgQJBAAAAA==.Silica:BAAALgAECgMJAwAAAA==.Silvershot:BAAALgADCgUJBQAAAA==.Siner:BAAALgAECgUJCAAAAA==.',
Sk='Skeeter:BAABLgAECn88AAQjAAkJXR3jAgBjAgAjAAkJBRrjAgBjAgABAAkJNhfDRQC/AQAkAAcJJx2ECgCYAQAAAA==.Skiadrum:BAACLgAFFH8FAAIiAAMJgQHILwBpAAAiAAMJgQHILwBpAAAuAAQKf0IAAx8ACQl+FGQnAMMBAB8ACAnXEmQnAMMBACIABAlBCThdAIoAAAAA.Skoliro:BAAALgAECgcJCQAAAA==.Skorch:BAAALgADCgkJEAABLgAFFAQJCQAbAPwKAA==.',
Sm='Smotts:BAAALgAECgcJDQAAAA==.Smòtts:BAAALgAECgcJDAAAAA==.',
Sn='Snizard:BAABLgAECn8WAAICAAcJlxfVRQC7AQACAAcJlxfVRQC7AQAAAA==.Snuggiepoo:BAABLgAECn8kAAMDAAkJsh4WCgC0AgADAAgJ5CAWCgC0AgAEAAYJgRUoTgCyAAAAAA==.',
So='Songbirds:BAAALgADCgcJDQAAAA==.Sonichoos:BAAALgAECgUJDAAAAA==.Sophiel:BAABLgAECn8fAAIVAAcJ1RctSwCOAQAVAAcJ1RctSwCOAQAAAA==.Sosthenna:BAAALgADCgkJCQAAAA==.Soulbark:BAAALgAECgMJAwABLgAECgQJBAAKAAAAAQ==.Souleater:BAAALgADCgMJAwAAAA==.Soulforged:BAAALgADCgcJCwABLgAECgQJBAAKAAAAAA==.Soulreaver:BAAALgAECgcJBwAAAA==.Soulweaver:BAAALgAECgQJBAAAAQ==.',
Sp='Sparrowhåwk:BAAALgADCgUJBgAAAA==.Spongebill:BAAALgADCgEJAQAAAA==.Spàdes:BAABLgAECn8cAAMQAAcJxxrALACOAQAQAAYJbhvALACOAQALAAMJbBLqPwCuAAAAAA==.',
St='Starel:BAAALgAECgQJBAAAAA==.Stellanoova:BAAALgAECgYJCQABLgAECggJFgAmAEoUAA==.Stevebushami:BAAALgAECgYJEAAAAA==.Stuwu:BAAALgADCgcJBwAAAA==.',
Su='Suou:BAAALgADCgcJCQABLgAECgEJAgAKAAAAAA==.Surj:BAABLgAECn8cAAMdAAYJ2RihGQBYAQAdAAYJ2RihGQBYAQAQAAQJeAtvXwC/AAAAAA==.',
Sv='Svmii:BAAALgADCgcJCgAAAA==.',
Ta='Taazdingo:BAAALgAECgQJBAAAAA==.Taikuri:BAAALgAECgcJDgAAAA==.Taliela:BAAALgAECgQJBAAAAA==.Tanddralndra:BAAALgAECgUJBwAAAA==.Tanklilbaby:BAAALgAECgEJAQAAAA==.Tannia:BAAALgADCgYJBgAAAA==.Taxgirl:BAACLgAFFH8RAAMGAAQJ+RjlQwBLAQAGAAQJ+RjlQwBLAQATAAEJsQMrIgA3AAAuAAQKfyAAAgYACAnOJGISAA0DAAYACAnOJGISAA0DAAAA.',
Te='Teabear:BAAALgAFFAMJBAAAAA==.Teralion:BAAALgAECgMJBgAAAA==.',
Th='Thaeldrik:BAAALgADCgcJCQAAAA==.Thaldreaux:BAAALgAECgMJBAAAAA==.Thefirst:BAAALgAECgMJAwAAAA==.Theleon:BAABLgAECn8dAAIUAAgJQg/zKgBjAQAUAAgJQg/zKgBjAQAAAA==.Thordrin:BAABLgAECn8sAAIIAAcJfiQwCgDVAgAIAAcJfiQwCgDVAgAAAA==.Thorlan:BAAALgADCgYJCAAAAA==.Thrasherzs:BAAALgAECgUJDAAAAA==.Thryen:BAAALgADCgYJCgAAAA==.Thunder:BAAALgADCgQJBAABLgAECgcJCgAKAAAAAA==.Thundergrasp:BAACLgAFFH8HAAInAAYJ+wonBABpAQAnAAYJ+wonBABpAQAuAAQKfxsAAicABwkNG7wNALsBACcABwkNG7wNALsBAAAA.',
Ti='Tianhe:BAAALgAECgMJAwAAAA==.Tiarisaril:BAAALgAECgYJBgAAAA==.Tigercita:BAAALgAECgMJAgAAAA==.Tippah:BAAALgAECgEJAwAAAA==.Tippers:BAAALgAECgEJAQAAAA==.',
To='Toe:BAAALgAFFAIJAwAAAA==.Tonkah:BAAALgAECgUJBQABLgAECggJDwAKAAAAAA==.Toobestake:BAAALgAECgQJBQABLgAFFAQJFAACAIkjAA==.Topenga:BAACLgAFFH8SAAICAAQJMRk7IwBTAQACAAQJMRk7IwBTAQAuAAQKf0sAAgIACQnNH2kSAKQCAAIACQnNH2kSAKQCAAAA.Tosem:BAAALgAECgEJAQAAAA==.Touchypope:BAAALgADCgYJCwAAAA==.',
Tr='Treeage:BAAALgADCgMJAwAAAA==.Triggerd:BAAALgADCgEJAQAAAA==.Trunks:BAAALgADCgQJBAAAAA==.Trylok:BAAALgADCgEJAQAAAA==.Trüst:BAAALgAECggJDgAAAA==.',
Tw='Twicelife:BAABLgAECn8ZAAIaAAgJ0R2rEwCXAgAaAAgJ0R2rEwCXAgABLgAFFAQJEgALABYVAA==.',
Ty='Tyrygosa:BAAALgAECgUJBQABLgAFFAQJEAABAMEWAA==.',
['Tå']='Tånk:BAAALgAECggJEwAAAA==.',
Un='Uneedsummilk:BAAALgADCgcJBwAAAA==.Unholyapollo:BAAALgADCgYJCwAAAA==.',
Ur='Urthstripe:BAABLgAECn8jAAIJAAgJwxcfHwA7AgAJAAgJwxcfHwA7AgAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCAAGAIkhAA==.Vain:BAAALgAECgEJAQAAAA==.Valle:BAAALgAECgIJAwABLgAFFAcJGgAEALAaAA==.Valoria:BAAALgAECgIJBgABLgAFFAcJGgAEALAaAA==.',
Ve='Veil:BAAALgAECgIJBgABLgAFFAcJGgAEALAaAA==.Velarenea:BAAALgADCgEJAQAAAA==.Velgabrine:BAAALgAECgYJDAABLgAFFAQJDQANAOQiAA==.Veraani:BAAALgAECgYJBgAAAA==.Verra:BAAALgADCgYJBgAAAA==.',
Vi='Vil:BAAALgADCgcJBgAAAA==.Virlan:BAAALgADCgQJBAAAAA==.Viserion:BAABLgAECn8WAAMmAAgJShRwNwAyAQAmAAcJZBJwNwAyAQAcAAYJ2AydHgDyAAAAAA==.',
Vo='Voidchaosfan:BAAALgAECgYJDAAAAA==.',
Vu='Vue:BAACLgAFFH8QAAIIAAQJQxN2IAAGAQAIAAQJQxN2IAAGAQAuAAQKf0YAAggACQkkGzYfAB8CAAgACQkkGzYfAB8CAAAA.Vuldin:BAAALgAECgEJAgAAAA==.',
['Vö']='Völdemört:BAAALgADCgIJAgAAAA==.',
Wa='Wakasham:BAACLgAFFH8SAAInAAUJryNrBABhAQAnAAUJryNrBABhAQAuAAQKfzAAAicACQk5Jp4BAFMDACcACQk5Jp4BAFMDAAAA.Wardrake:BAAALgAECgEJAQAAAA==.',
We='Wehonoryou:BAABLgAECn8WAAIHAAYJ9CHYGAAAAgAHAAYJ9CHYGAAAAgAAAA==.Wetard:BAAALgADCgIJAgAAAA==.',
Wi='Willbyers:BAAALgAECgEJAQAAAA==.Winterloom:BAAALgAECgYJBgAAAA==.',
Wo='Wolfpacked:BAACLgAFFH8GAAIaAAIJHBz+TACkAAAaAAIJHBz+TACkAAAuAAQKfygAAhoACQlBIKgHACMDABoACQlBIKgHACMDAAAA.Wolfzbåin:BAAALgAECgQJBAAAAA==.',
Wr='Wroot:BAAALgADCgYJCQAAAA==.Wrotten:BAABLgAECn8WAAIkAAgJ6RcrCQCyAQAkAAgJ6RcrCQCyAQAAAA==.',
Wu='Wunderlust:BAACLgAFFH8MAAIbAAQJjBbiQwBFAQAbAAQJjBbiQwBFAQAuAAQKf0QAAhsACQmFISYcAAYDABsACQmFISYcAAYDAAAA.',
Xe='Xemon:BAAALgAECgIJAgAAAA==.',
Xi='Xilyana:BAAALgAECgQJBAAAAA==.',
Xm='Xmatick:BAAALgAECgcJCQAAAA==.',
Xs='Xscrats:BAAALgAECgkJBwAAAA==.',
Ye='Yellowshaman:BAACLgAFFH8eAAIeAAUJ+RlbFgA/AQAeAAUJ+RlbFgA/AQAuAAQKfzIAAh4ACQk3Ig4OAHcCAB4ACQk3Ig4OAHcCAAAA.Yerac:BAAALgAECgEJAQAAAA==.',
Yu='Yukikage:BAAALgAECgMJAwAAAA==.Yutdaeng:BAAALgAECgMJBAAAAA==.',
Yv='Yvent:BAAALgADCgIJAgAAAA==.Yvraine:BAAALgAECgYJDQAAAA==.',
Za='Zakcarii:BAAALgADCgMJCAAAAA==.Zalicy:BAAALgAECgYJEwAAAA==.Zalogar:BAAALgAECgcJCgAAAA==.Zapper:BAAALgAECgQJCwAAAA==.',
Zb='Zbarbb:BAAALgADCgUJBQAAAA==.',
Ze='Zealot:BAAALgAECgEJAQAAAA==.Zeeasyez:BAAALgAECgYJEwAAAA==.Zestul:BAAALgADCgEJAQAAAA==.',
Zh='Zhane:BAAALgADCgYJBwAAAA==.',
Zo='Zordon:BAAALgAECgYJEwAAAA==.',
Zu='Zugg:BAAALgAECgIJBAABLgAFFAcJGgAEALAaAA==.Zuriznikov:BAAALgAECgEJAQABLgAECggJFgAmAEoUAA==.',
['Ån']='Ångie:BAAALgADCgMJAwAAAA==.',
['Øf']='Øffspeck:BAABLgAECn8gAAQBAAkJVhweLgBVAgABAAgJwxgeLgBVAgAkAAcJICFkCgCaAQAjAAMJzh7MMAD3AAAAAA==.',
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
