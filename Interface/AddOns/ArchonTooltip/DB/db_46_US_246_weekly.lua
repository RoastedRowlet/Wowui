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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Priest-Discipline','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','Unknown-Unknown','DemonHunter-Havoc','Paladin-Holy','Druid-Restoration','Warrior-Arms','Paladin-Retribution','Shaman-Restoration','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','Paladin-Protection','DeathKnight-Blood','DeathKnight-Frost','Druid-Balance','DemonHunter-Devourer','Rogue-Assassination','Mage-Arcane','Monk-Mistweaver','Druid-Guardian','Monk-Brewmaster','Mage-Frost','Warrior-Protection','Rogue-Subtlety','Shaman-Elemental','Druid-Feral','Mage-Fire','Monk-Windwalker','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Evoker-Augmentation','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=46,date='2026-06-14',data={Aa='Aaron:BAAALgAECgEJAQABLgAECgkJIAABAFYcAA==.Aaronfreeze:BAACLgAFFH8JAAICAAMJehoFVAD6AAACAAMJehoFVAD6AAAuAAQKfzIAAgIACQn1HkQfAGkCAAIACQn1HkQfAGkCAAAA.',
Ab='Abrakazaam:BAAALgADCgEJAQAAAA==.',
Ad='Adrios:BAACLgAFFH8FAAIDAAIJmRTbOQCTAAADAAIJmRTbOQCTAAAuAAQKfyYABAMACQnQFp4ZAAICAAMACAn9F54ZAAICAAQABwlRB9FRAMkAAAUAAwnKCCRpAIgAAAAA.',
Ae='Aetherion:BAAALgAECgMJBAAAAA==.',
Ai='Airorca:BAAALgAECgUJBQAAAA==.',
Aj='Ajaxz:BAABLgAECn8VAAIGAAkJ+RLTYADRAQAGAAkJ+RLTYADRAQAAAA==.',
Ak='Akaßoss:BAAALgADCgEJAQABLgAECgMJBwAHAAAAAA==.',
Al='Albedô:BAAALgAFFAIJAwABLgAFFAIJBwAIAAohAA==.Aliren:BAAALgAECgYJCgAAAA==.Allmaick:BAAALgADCggJCAAAAA==.Alucard:BAABLgAFFH8OAAIJAAQJ5gdSKwDNAAAJAAQJ5gdSKwDNAAAAAA==.Alystrasza:BAABLgAECn8dAAIKAAYJvhZ6RAB8AQAKAAYJvhZ6RAB8AQAAAA==.',
Am='Amorlandian:BAAALgAECgMJAwAAAA==.',
An='Antimovsky:BAAALgAECgcJEwAAAA==.',
Ap='Aphroditê:BAAALgAECgMJAwABLgAECgcJCAAHAAAAAA==.',
Aq='Aqours:BAAALgADCgcJBwABLgAECgEJAgAHAAAAAA==.',
Ar='Arcan:BAAALgAECgIJAgAAAA==.',
As='Astellia:BAAALgADCgEJAQAAAA==.',
Au='Augustine:BAAALgAECgEJAQAAAA==.Aullyura:BAAALgADCgcJBwAAAA==.Auroras:BAACLgAFFH8IAAMFAAMJUwYbKAB/AAAFAAMJUwYbKAB/AAAEAAEJmAHAQAAvAAAuAAQKfxcAAgUABwmEE5k0AGwBAAUABwmEE5k0AGwBAAAA.',
Av='Aviaria:BAAALgAECgQJBAAAAA==.Avìendha:BAAALgADCgQJBAAAAA==.',
['Aì']='Aìnzooalgown:BAABLgAFFH8SAAIGAAQJESGROgB+AQAGAAQJESGROgB+AQABLgAFFAIJBwAIAAohAA==.',
Ba='Babakubwa:BAAALgAECgMJAwAAAA==.Babylonfive:BAAALgAECgcJDQAAAA==.Balhair:BAAALgADCgYJBgAAAA==.Banish:BAAALgAECgMJAgABLgAECgcJCgAHAAAAAA==.Barragdan:BAAALgADCgEJAQAAAA==.Basandra:BAAALgAECgEJAQAAAA==.Basicc:BAAALgADCgMJAwAAAA==.',
Be='Beachbumm:BAAALgADCgEJAQAAAA==.Beastreminna:BAAALgADCgEJAQAAAA==.Belleta:BAAALgAECggJEQAAAA==.Berserk:BAEBLgAECn8iAAILAAYJ3SPEDgD+AQALAAYJ3SPEDgD+AQAAAA==.Bertringer:BAAALgAECgEJAgABLgAECgYJBgAHAAAAAA==.',
Bi='Bigmack:BAAALgAECgYJCwABLgAFFAcJHAAMAHoYAA==.Bigwilli:BAABLgAECn8WAAINAAgJpxIhOQDIAQANAAgJpxIhOQDIAQAAAA==.Bingßong:BAAALgADCgYJEQAAAA==.Biscuit:BAACLgAFFH8QAAQOAAYJhBpFGwDTAAACAAQJvCLXVQD1AAAOAAMJ7BFFGwDTAAAPAAIJ+xEvKwCDAAAuAAQKfyIABA4ACAmPIycPAMgCAA4ACAl9HScPAMgCAA8AAwnZH+w5AO0AAAIABAk+HkuqAOoAAAAA.Bisha:BAABLgAECn9FAAMQAAkJEiHmDQDmAgAQAAkJ9CDmDQDmAgALAAYJcBhcMQD/AAAAAA==.Bizcocho:BAAALgAECgcJDAAAAA==.',
Bl='Black:BAAALgADCgEJAQAAAA==.Bloodsimple:BAAALgADCgUJBQAAAA==.Blákers:BAABLgAFFH8OAAIRAAQJuSTvAQCwAQARAAQJuSTvAQCwAQAAAA==.',
Bo='Boic:BAAALgADCgQJBAAAAA==.Bonesofdoom:BAACLgAFFH8HAAISAAMJ1w3CKwCYAAASAAMJ1w3CKwCYAAAuAAQKfyMAAxIACQkHGQQZAJcBABIACAmJGwQZAJcBAAYAAgkYBlo8AV8AAAAA.Boogsta:BAACLgAFFH8PAAITAAMJmgqeFwDHAAATAAMJmgqeFwDHAAAuAAQKfzYAAhMACQlxFTsHACUCABMACQlxFTsHACUCAAAA.Boomkingobrr:BAACLgAFFH8HAAIUAAMJ9wjoNACnAAAUAAMJ9wjoNACnAAAuAAQKfxsAAhQACQkOHEQLAOECABQACQkOHEQLAOECAAAA.Boops:BAAALgAECgEJAQAAAA==.Bootysweatt:BAABLgAECn8aAAIIAAYJNhtqJACaAQAIAAYJNhtqJACaAQAAAA==.Boss:BAAALgADCgEJAQABLgAECgMJBwAHAAAAAA==.',
Br='Brewnz:BAAALgAECgUJBgAAAA==.Brucewee:BAAALgAECgQJCgAAAA==.',
Bu='Buckits:BAAALgAECgcJEgAAAA==.Bunsey:BAAALgADCgIJAgAAAA==.Burnsx:BAAALgAECgUJCgABLgAFFAgJGAAVAEoeAA==.Bussyman:BAAALgAECgYJEQABLgAFFAMJCQAKACIWAA==.',
Bw='Bwoar:BAAALgAECgQJBgAAAA==.',
['Bø']='Bøw:BAAALgAECgMJAwAAAA==.',
['Bü']='Bübble:BAAALgADCgEJAQAAAA==.',
Ca='Captnmurloc:BAAALgAECgkJEQAAAA==.Capwackychan:BAAALgAECgEJAQAAAA==.Carl:BAAALgAECgEJAgABLgAFFAgJDwAWAMwbAA==.Carrach:BAAALgAECgIJBQAAAA==.Caveyodeler:BAAALgAECgQJCgAAAA==.',
Ce='Cedar:BAAALgAECgQJCwAAAA==.',
Ch='Cherga:BAAALgADCgYJBgAAAA==.Chinegga:BAAALgADCgYJBgAAAA==.Chitose:BAAALgADCgUJBQABLgAECgEJAgAHAAAAAA==.Chrapsasspee:BAAALgADCgcJGQAAAA==.Chrinn:BAAALgADCgMJAwAAAA==.',
Ci='Cindele:BAAALgADCgMJAwAAAA==.Cirvix:BAAALgAECgYJDAAAAA==.Cirxe:BAABLgAECn8iAAIXAAkJMg5mBACuAQAXAAkJMg5mBACuAQAAAA==.',
Cl='Clampire:BAAALgAECgQJBAAAAA==.Cliint:BAAALgAECgcJCwAAAA==.Cloúnt:BAAALgAECgEJAwABLgAFFAMJBwAUAPcIAA==.',
Co='Commotionn:BAAALgAECgQJBAAAAA==.Coms:BAAALgADCgIJAgAAAA==.Cooz:BAAALgAECgYJDgAAAA==.Corybooker:BAAALgAECgcJBAAAAA==.Cowdux:BAAALgAFFAEJAQAAAA==.Cowmoorem:BAAALgADCgEJAQAAAA==.',
Cr='Creamdragon:BAAALgADCgYJCgABLgAECggJMgAYAFgdAA==.',
Cu='Curuni:BAAALgADCgcJDAAAAA==.',
Cz='Czechhunter:BAAALgADCgUJBQAAAA==.',
['Cå']='Cåleb:BAAALgAECgEJAQAAAA==.',
['Cø']='Cønstance:BAABLgAECn8VAAIZAAcJvRF7JQAjAQAZAAcJvRF7JQAjAQAAAA==.',
Da='Daddyphat:BAABLgAECn8rAAIaAAgJrCSfBgDOAgAaAAgJrCSfBgDOAgAAAA==.Daddý:BAAALgAECgEJAQAAAA==.Dalight:BAABLgAECn8XAAIJAAYJKiYPDwCdAgAJAAYJKiYPDwCdAgAAAA==.Dankins:BAACLgAFFH8dAAINAAgJ2SJ1AQDiAgANAAgJ2SJ1AQDiAgAuAAQKfxYAAg0ACAkGHfYZAEcCAA0ACAkGHfYZAEcCAAAA.',
De='Deathmager:BAABLgAECn89AAIbAAkJjBLMSAD/AQAbAAkJjBLMSAD/AQAAAA==.Deathtraper:BAAALgAECgcJDQAAAA==.Debur:BAAALgADCgEJAQAAAA==.Deltaka:BAAALgAECgEJAQAAAA==.Demonfella:BAAALgADCgMJAwAAAA==.Demonicpeach:BAABLgAECn8YAAIBAAcJwwvbqgDuAAABAAcJwwvbqgDuAAAAAA==.Denaian:BAAALgADCgYJBgAAAA==.Dethsent:BAAALgAECggJEQAAAA==.Dette:BAABLgAECn8dAAICAAkJvBV1LQAkAgACAAkJvBV1LQAkAgAAAA==.Devilchaser:BAAALgAECggJDgAAAA==.Devourer:BAABLgAECn8VAAIVAAcJjg+mbQBaAQAVAAcJjg+mbQBaAQAAAA==.',
Dh='Dhtank:BAAALgAECgEJAQAAAA==.',
Di='Diaval:BAAALgADCgIJAgABLgAECgkJLAABAFsTAA==.Dinosforlife:BAAALgAECgYJDAAAAA==.',
Dk='Dkboss:BAAALgAECgEJAQABLgAECgMJBwAHAAAAAA==.',
Do='Donzilly:BAAALgAECgYJDgAAAA==.Doreme:BAAALgADCgIJAgAAAA==.Dorgrim:BAAALgAECgUJDAAAAA==.Doyuevendps:BAAALgADCgEJAQAAAA==.',
Dr='Drafted:BAAALgAECgcJEAAAAA==.Drax:BAAALgAECgMJAwAAAA==.Drewmcmoo:BAAALgADCgcJBgAAAA==.Drsath:BAAALgADCgcJBwAAAA==.Drunkorca:BAAALgADCgUJBQAAAA==.',
Ea='Earnar:BAAALgADCgYJDAAAAA==.',
Ed='Edarix:BAAALgADCggJDAABLgAECggJNwAMAHkYAA==.',
Ei='Eiliyah:BAABLgAECn8yAAMJAAgJehz0FgBaAgAJAAgJehz0FgBaAgAMAAIJHwL/xQEdAAAAAA==.',
Ek='Ekmek:BAAALgAECgEJAQAAAA==.',
El='Elabernathy:BAABLgAECn80AAICAAkJrhjpHAB1AgACAAkJrhjpHAB1AgAAAA==.Elenay:BAABLgAECn8UAAIKAAgJqR46IwAuAgAKAAgJqR46IwAuAgAAAA==.Elesia:BAAALgAECgkJEgAAAA==.Elfussy:BAAALgAECgEJAQAAAA==.Elgoku:BAAALgAECgQJCgABLgAECgUJDAAHAAAAAA==.Eliarssande:BAAALgAECgEJAQAAAA==.Elinay:BAAALgAECgQJBAABLgAECggJFAAKAKkeAA==.Elixia:BAABLgAECn8bAAIIAAgJDA35JQBFAQAIAAgJDA35JQBFAQAAAA==.Elpatron:BAABLgAFFH8HAAIKAAQJGQnaOQDDAAAKAAQJGQnaOQDDAAAAAA==.Elylanea:BAAALgAECgUJDgAAAA==.',
Em='Emulsdeath:BAABLgAECn8UAAMSAAgJKCEQEwDeAQASAAcJLB4QEwDeAQAGAAYJ8iCRagCPAQABLgAFFAQJEAAMADsjAA==.Emulsifier:BAACLgAFFH8QAAIMAAQJOyM/GwCWAQAMAAQJOyM/GwCWAQAuAAQKfzAAAgwACAmFJrsMAP4CAAwACAmFJrsMAP4CAAAA.',
En='Ennoa:BAAALgAECgEJAQAAAA==.',
Er='Ergen:BAACLgAFFH8aAAIPAAUJthruEAA8AQAPAAUJthruEAA8AQAuAAQKfyoAAg8ACAlvIaUGAJcCAA8ACAlvIaUGAJcCAAAA.',
Eu='Eusexua:BAAALgAECgQJBQABLgAECgcJCgAHAAAAAA==.',
Ex='Expiatory:BAAALgAECgYJCAAAAA==.',
Fa='Faielle:BAAALgADCgQJBAAAAA==.Fairbear:BAABLgAECn8dAAQQAAYJ+BxIOQBhAQAQAAYJ+BxIOQBhAQALAAEJZA5tPgA7AAAcAAEJ6QchXQAbAAAAAA==.Faustt:BAAALgAECgUJBwAAAA==.',
Fi='Filthyfabio:BAAALgADCgcJEQAAAA==.Finester:BAABLgAFFH8LAAIdAAQJdh9dEQB/AQAdAAQJdh9dEQB/AQAAAA==.Fireburr:BAAALgAECgMJAwAAAA==.',
Fl='Flatline:BAAALgAECgcJEgAAAA==.Fløw:BAAALgAECgMJCgAAAA==.',
Fr='Fragglerott:BAABLgAECn8bAAMNAAgJGBPzgQDYAAANAAQJUhLzgQDYAAAeAAgJ1AplZQCzAAAAAA==.Frati:BAAALgAECgEJAQAAAA==.Friedchickn:BAAALgAECgQJCAAAAA==.Frostboss:BAAALgADCgEJAQAAAA==.Frostnips:BAAALgADCgMJAwAAAA==.Frosttrinity:BAAALgADCgUJBAAAAA==.',
Fu='Funslinger:BAAALgAECgQJDAAAAA==.',
Ga='Gaffz:BAAALgAECgEJAgAAAA==.Galannar:BAAALgAECggJDQAAAA==.Galvrax:BAAALgAECgUJCgAAAA==.Gast:BAACLgAFFH8PAAIQAAUJZB0HGQBLAQAQAAUJZB0HGQBLAQAuAAQKfzYAAxAACQlRIKoJAMcCABAACQlRIKoJAMcCABwABAmpFlA1AKEAAAAA.',
Ge='Gearwick:BAAALgADCgYJBwABLgAECgcJJgAJAFAhAA==.',
Gh='Ghstfacekila:BAAALgADCgEJAQAAAA==.',
Go='Gorska:BAABLgAECn82AAIeAAkJfB3tDwBzAgAeAAkJfB3tDwBzAgAAAA==.',
Gr='Grawm:BAABLgAECn8iAAMOAAkJqiKzHgAxAgAOAAgJSRWzHgAxAgACAAkJPiAiTgC1AQAAAA==.Greedory:BAAALgADCgIJAgAAAA==.Groot:BAAALgADCgUJBgAAAA==.Gruetss:BAAALgAECgQJBAAAAA==.',
['Gä']='Gämbit:BAAALgADCgEJAQAAAA==.',
Ha='Hailbringer:BAAALgAECgcJDgAAAA==.Hakoona:BAABLgAECn8yAAIaAAkJFxqVEQAqAgAaAAkJFxqVEQAqAgAAAA==.Hanginaround:BAAALgAECgEJAQAAAA==.Hangman:BAACLgAFFH8aAAIJAAQJ8SW5EACsAQAJAAQJ8SW5EACsAQAuAAQKfyEAAwkACQmLJAECAJIDAAkACQmLJAECAJIDAAwABAklDQcbAZYAAAEuAAUUAwkJAAoAIhYA.Hanni:BAABLgAECn8dAAIOAAgJUhxoCwCvAQAOAAgJUhxoCwCvAQAAAA==.Haveaburitto:BAACLgAFFH8NAAIbAAQJWBw0WgAxAQAbAAQJWBw0WgAxAQAuAAQKfygAAhsACAk0JXkMAGEDABsACAk0JXkMAGEDAAAA.Hawktoetem:BAAALgAECgUJCAABLgAECgYJHQAQAPgcAA==.Hawktoouh:BAAALgAECgYJBwAAAA==.',
He='Healmemaybe:BAABLgAECn8bAAIKAAYJQiOkIgAxAgAKAAYJQiOkIgAxAgAAAA==.Healthyadult:BAAALgAECgMJBQAAAA==.Hellshand:BAAALgAECgYJDAAAAA==.Heracles:BAAALgAECgQJBAAAAA==.Heretic:BAAALgAECgEJAQAAAA==.',
Hi='Hickscale:BAAALgADCgMJAwAAAA==.',
Ho='Holycøw:BAAALgADCgMJAwAAAA==.Holydefender:BAAALgADCgcJDQAAAA==.Holyhands:BAAALgADCgYJBgAAAA==.Holyholyholy:BAAALgAECggJEgAAAA==.Honest:BAAALgADCgMJAwAAAA==.',
Hu='Hunniee:BAAALgAECgEJAQAAAA==.Huntrix:BAAALgADCgcJEgAAAA==.',
Ic='Icedatt:BAABLgAECn8VAAMGAAUJ8QIUJAF6AAAGAAUJ7AIUJAF6AAASAAUJcwGvUwBIAAAAAA==.Icefire:BAAALgADCgUJBAAAAA==.',
Ik='Ikur:BAACLgAFFH8PAAIJAAQJrxunHAAzAQAJAAQJrxunHAAzAQAuAAQKfzsAAgkACQmTHnAHABQDAAkACQmTHnAHABQDAAAA.',
Il='Ilinia:BAAALgAECgYJCAABLgAECgUJEgAHAAAAAA==.Illhealutoo:BAAALgAECgUJBwAAAA==.',
Im='Imsteve:BAAALgAECgUJBQAAAA==.',
In='Infoxicated:BAAALgADCgcJCAABLgAECgkJJAADALIeAA==.Insîght:BAAALgAECgQJCAAAAA==.',
Ip='Ipopkidneys:BAACLgAFFH8VAAMdAAcJ1SG5DAC9AQAdAAYJlSG5DAC9AQAWAAMJjB0HBwDxAAAuAAQKfycAAx0ACQnhJYQMANACAB0ACQnhJYQMANACABYAAQn1I9EeAGUAAAAA.',
Ir='Iroi:BAAALgAECgIJBQAAAA==.',
Is='Iskur:BAABLgAECn8mAAMNAAgJ4BieIgA8AgANAAgJ4BieIgA8AgAeAAMJMQ0ddQCKAAABLgAFFAQJDwAJAK8bAA==.Isuck:BAAALgAFFAIJAgAAAA==.Isurr:BAABLgAECn8iAAIYAAcJnhLPOACKAQAYAAcJnhLPOACKAQABLgAFFAQJDwAJAK8bAA==.',
It='Itakecandle:BAAALgAECgUJBwABLgAECgUJDAAHAAAAAA==.',
Iv='Ivanapump:BAAALgAECgIJAgABLgAECgYJBgAHAAAAAA==.',
Ja='Jackkal:BAAALgAECgcJCQAAAA==.Jadethecat:BAAALgADCgMJAwAAAA==.Jakbis:BAAALgADCgEJAQAAAA==.Jakychan:BAAALgAECgEJAQAAAA==.Jaldiar:BAAALgADCgcJBwABLgAECgYJBgAHAAAAAA==.Jametrok:BAAALgAECgEJAQAAAA==.Jazbek:BAAALgAECgQJDgAAAA==.Jazzonus:BAAALgAECgQJBAAAAA==.',
Je='Jefferey:BAAALgADCgMJAwAAAA==.Jennyanydots:BAAALgAECgMJBQABLgAFFAcJGgAEALAaAA==.Jeriçho:BAAALgADCgYJBgAAAA==.',
Jh='Jhonwick:BAAALgAECgIJAgAAAA==.',
Ji='Jippedo:BAAALgAECgYJAgABLgAECgcJBAAHAAAAAA==.Jiraîya:BAAALgAECgQJBQAAAA==.',
Jo='Jordak:BAABLgAECn8oAAIKAAkJBBwCDgDnAgAKAAkJBBwCDgDnAgAAAA==.Jorolee:BAAALgADCgEJAQAAAA==.',
Ka='Kaddiya:BAAALgAECgYJBwAAAA==.Kagonstrasza:BAAALgAECgQJBAAAAA==.Kallistos:BAABLgAECn8gAAINAAcJER1TLQD/AQANAAcJER1TLQD/AQAAAA==.Kariza:BAAALgAECgQJBgAAAA==.Karunik:BAAALgADCgYJBgABLgAECgcJCgAHAAAAAA==.Kasst:BAAALgAECgEJAQAAAA==.',
Ke='Kelenheller:BAAALgAECgUJBQAAAA==.Key:BAAALgAECgEJAQAAAA==.',
Kh='Khione:BAAALgADCgYJBgAAAA==.Khthonios:BAAALgAECgEJAQAAAA==.',
Ki='Kibblerina:BAAALgADCgcJBwAAAA==.Kiranam:BAABLgAECn8cAAQfAAgJrQ6dEQCTAQAfAAgJqQqdEQCTAQAZAAcJNQxCNwDGAAAUAAIJWwfecQBZAAAAAA==.',
Kn='Knarth:BAABLgAECn9CAAIgAAkJ5x7tAADZAgAgAAkJ5x7tAADZAgAAAA==.Kníght:BAAALgAECgcJBwAAAA==.',
Ko='Koisy:BAAALgAECgcJEAABLgAECggJFAAKAKkeAA==.Kole:BAAALgAECgEJAQAAAA==.Koopa:BAABLgAECn8rAAIQAAkJHyUrBQAPAwAQAAkJHyUrBQAPAwAAAA==.',
Kr='Krasul:BAACLgAFFH8VAAMNAAUJEBgPJABWAQANAAUJEBgPJABWAQAeAAIJ7Qk9RwBsAAAuAAQKfx8AAw0ACAkXIecIAOgCAA0ACAkXIecIAOgCAB4ABgm/HPIxAJQBAAAA.Krenthok:BAABLgAECn8eAAIBAAgJiQf5hwAqAQABAAgJiQf5hwAqAQAAAA==.',
Ku='Kuraha:BAAALgAECgQJBAAAAA==.Kushar:BAAALgAECgQJBQABLgAECgkJGAAhAMkQAA==.',
Ky='Kyuketsuki:BAAALgAFFAIJAgAAAA==.',
La='Lachance:BAAALgADCgYJBgAAAA==.Large:BAAALgADCgYJBgAAAA==.Largemann:BAAALgAECgcJDQABLgAFFAUJFwAGAIkcAA==.Lathspell:BAABLgAECn8yAAIbAAkJtiCHJQCEAgAbAAkJtiCHJQCEAgAAAA==.Lazyevoker:BAAALgADCgQJBAABLgAECgEJAQAHAAAAAA==.',
Le='Leahan:BAAALgAECgQJCgAAAA==.Leloo:BAAALgADCgYJCgABLgAECgIJAwAHAAAAAA==.',
Lh='Lhureciv:BAACLgAFFH8UAAMEAAQJERnMFAA6AQAEAAQJERnMFAA6AQADAAEJKRvVRwBFAAAuAAQKf0sAAwQACQnVI80GAB4DAAQACQnVI80GAB4DAAMABgn7HjAjAHoBAAAA.',
Li='Lightchaser:BAAALgADCgMJAgAAAA==.Lightfkyou:BAAALgADCgcJCgAAAA==.Lihvurce:BAABLgAECn8fAAMMAAgJWR2bMQA4AgAMAAgJWR2bMQA4AgAJAAQJpR0FSwBMAQABLgAFFAQJFAAEABEZAA==.Lillianna:BAACLgAFFH8HAAIdAAIJrBJ9LwCkAAAdAAIJrBJ9LwCkAAAuAAQKfzYAAh0ACAlQHQ4NAFMCAB0ACAlQHQ4NAFMCAAAA.Lingchi:BAAALgAECgQJBgAAAA==.',
Ll='Llew:BAAALgAECgMJBAAAAA==.',
Lo='Loenhart:BAAALgAECgEJAQAAAA==.Lolkurtone:BAAALgAECgIJAgAAAA==.',
Lu='Luciaan:BAAALgADCgkJGQAAAA==.Lucrative:BAAALgADCgcJDQAAAA==.Lug:BAAALgAECgEJAQAAAA==.Lulue:BAAALgADCgQJBAAAAA==.Luminari:BAAALgADCgUJBQAAAA==.Lunastorm:BAACLgAFFH8NAAIiAAQJLxN4GAAIAQAiAAQJLxN4GAAIAQAuAAQKfzgAAiIACQnQIoQCAD4DACIACQnQIoQCAD4DAAAA.Luponero:BAACLgAFFH8XAAMCAAUJiSO4GwCPAQACAAUJiSO4GwCPAQAOAAEJ5QapKgBGAAAuAAQKfyIAAw4ACAnnHuYQALUCAA4ACAl6HeYQALUCAAIAAwnNHyOVABIBAAAA.',
Ly='Lynney:BAAALgADCgYJBwAAAA==.',
Ma='Macmn:BAACLgAFFH8TAAIeAAUJzxzmEQCOAQAeAAUJzxzmEQCOAQAuAAQKfygAAh4ABwnAJGULAOICAB4ABwnAJGULAOICAAAA.Mageyouacake:BAAALgADCgMJAwAAAA==.Magicard:BAABLgAECn8fAAIbAAgJjg4vegCBAQAbAAgJjg4vegCBAQAAAA==.Makesfood:BAABLgAECn8qAAIbAAcJZBeSdADpAQAbAAcJZBeSdADpAQAAAA==.Mamaheals:BAABLgAECn8rAAIFAAkJSxoiFAA0AgAFAAkJSxoiFAA0AgAAAA==.Mandos:BAAALgAECgYJCAAAAA==.Mantistabogn:BAAALgAFFAEJAQAAAA==.Maor:BAABLgAECn8XAAIMAAgJlxcuUADxAQAMAAgJlxcuUADxAQAAAA==.March:BAAALgADCgEJAQAAAA==.Markeisha:BAAALgAECgQJCAABLgAECgYJDAAHAAAAAA==.',
Me='Mechz:BAAALgAECgYJBgABLgAFFAQJCQAbAPwKAA==.Mechzician:BAACLgAFFH8JAAIbAAQJ/ApIdQD0AAAbAAQJ/ApIdQD0AAAuAAQKfzgAAhsACAlwGXtZAC0CABsACAlwGXtZAC0CAAAA.Mechzlock:BAAALgADCgEJAQABLgAFFAQJCQAbAPwKAA==.Melinoe:BAAALgAECgEJAQAAAA==.Merlerk:BAAALgADCgYJBgAAAA==.Merlini:BAABLgAECn8dAAMEAAgJWRawIwCrAQAEAAcJ0xiwIwCrAQADAAUJThZ2PAAdAQAAAA==.Mets:BAAALgAECgYJCgABLgAECgYJFQABAEkYAA==.',
Mi='Microplastic:BAAALgAECgUJBQAAAA==.Micspanky:BAAALgAECggJEgAAAA==.Mistynight:BAAALgADCgIJAgAAAA==.Mithrandi:BAAALgAECgYJCQAAAA==.Mitzis:BAABLgAFFH8MAAICAAMJ8x8/TwAGAQACAAMJ8x8/TwAGAQAAAA==.',
Mo='Moltiy:BAAALgADCggJCwAAAA==.Moltten:BAAALgADCgcJEQAAAA==.Mornhathor:BAAALgAECggJDgABLgAECgYJCAAHAAAAAA==.',
Mu='Mufinblaster:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgADCgIJBgAAAA==.Musnicker:BAAALgAECgQJBwABLgAECgkJLAAOAPMQAA==.',
My='Myro:BAACLgAFFH8UAAMNAAQJ3B9NJgBKAQANAAQJ3B9NJgBKAQAeAAIJZRQUQQB/AAAuAAQKfxsAAg0ABwm/JsEHAPkCAA0ABwm/JsEHAPkCAAAA.',
['Mè']='Mètis:BAAALgAECgcJCAAAAA==.',
['Mø']='Møhax:BAAALgAECgYJBgAAAA==.',
Na='Nanis:BAAALgAECgYJBgABLgAFFAQJDwAUAB0kAA==.Narmer:BAAALgAECgIJAgAAAA==.',
Ne='Neel:BAAALgADCgQJBQAAAA==.Nervhoost:BAAALgADCgMJAwAAAA==.Neuropolis:BAAALgADCgcJFQAAAA==.Neuroscience:BAAALgADCgMJAwAAAA==.Neurotics:BAABLgAECn89AAQjAAkJFSbeAAAVAwAjAAgJxyXeAAAVAwAkAAcJsSPyAwBIAgABAAUJ5BoBuwDjAAAAAA==.Neò:BAABLgAECn8YAAMlAAYJvBB+EAD/AAAlAAYJXw5+EAD/AAAmAAEJ/hRQkQA1AAAAAA==.',
Ni='Niesh:BAAALgAECgEJBwAAAA==.Nightrush:BAAALgADCgEJAQAAAA==.Nineoneone:BAABLgAECn89AAMFAAkJzBNOFgAdAgAFAAkJzBNOFgAdAgADAAQJjgPqRQCLAAAAAA==.',
No='Nobledecay:BAAALgAECgQJBQAAAA==.Nocturne:BAAALgAECgEJAwAAAA==.',
Nu='Nubbletcake:BAAALgADCgEJAQABLgAECgkJJAADALIeAA==.Nula:BAAALgAECgMJBQABLgAFFAcJGgAEALAaAA==.',
Ny='Nylveth:BAACLgAFFH8PAAIEAAUJNg+YHAAGAQAEAAUJNg+YHAAGAQAuAAQKfyoAAgQACQkAHVwQAFkCAAQACQkAHVwQAFkCAAEuAAUUBwkIACcAmgsA.',
Oa='Oathatone:BAAALgAECgQJBAAAAA==.',
Oc='Ocra:BAABLgAECn8gAAInAAkJ9g41DgDKAQAnAAkJ9g41DgDKAQABLgAFFAQJFQACADEZAA==.',
Of='Offspeck:BAAALgAECgIJAgABLgAECgkJIAABAFYcAA==.',
Ou='Outtkast:BAAALgAECgIJAgAAAA==.Outtkastt:BAAALgAECgcJCQAAAA==.Ouutkast:BAAALgAECgIJAwAAAA==.',
Oz='Ozwald:BAABLgAECn81AAIPAAkJchxyEAArAgAPAAkJchxyEAArAgAAAA==.',
Pa='Pallyangel:BAAALgADCgcJDwAAAA==.Pandemul:BAAALgAECgMJAwABLgAFFAQJEAAMADsjAA==.Patrio:BAACLgAFFH8IAAIiAAMJGg0cIQCXAAAiAAMJGg0cIQCXAAAuAAQKfywAAiIACQllGdwHAHMCACIACQllGdwHAHMCAAEuAAUUBAkHAAoAGQkA.',
Pe='Peaceonea:BAABLgAECn8bAAIVAAkJrgR4mwDoAAAVAAkJrgR4mwDoAAAAAA==.Peachaid:BAECLgAFFH8cAAMDAAgJ9Re3CACRAgADAAgJ9Re3CACRAgAFAAEJRQgdOQAtAAAuAAQKfzAAAwMACQlVIkkFADQDAAMACQlVIkkFADQDAAUABgkYHSglAMABAAAA.Peatri:BAAALgAECgkJCwAAAA==.Peetree:BAABLgAFFH8KAAINAAQJOBnaLQAlAQANAAQJOBnaLQAlAQAAAA==.Pekin:BAAALgAECgEJAQAAAA==.',
Ph='Phosphorus:BAACLgAFFH8VAAMLAAQJFhVZGgAQAQALAAQJihNZGgAQAQAcAAIJjxToIgB8AAAuAAQKf1kAAwsACQnmIDQFALcCAAsACQnHHjQFALcCABwABgkqHD0YAHoBAAAA.',
Pl='Plagüë:BAACLgAFFH8QAAMSAAQJzRwmKACxAAAGAAMJpCA/dQAUAQASAAMJ3RAmKACxAAAuAAQKf00AAwYACQmjJWAQAOgCAAYACQmjJWAQAOgCABIABQmbD7M4AK8AAAAA.Pleistarchus:BAAALgAECgYJCQAAAA==.',
Po='Poic:BAAALgADCgEJAQAAAA==.Polo:BAAALgADCgEJAQAAAA==.Poofighter:BAAALgAECgMJBwABLgAFFAIJBwAIAAohAA==.Poonan:BAAALgAECgYJBgAAAA==.',
Pp='Ppgangandlaw:BAAALgADCgEJAQAAAA==.',
Pr='Precious:BAABLgAECn8dAAIYAAgJexWOJQDzAQAYAAgJexWOJQDzAQAAAA==.Primalistic:BAAALgADCgUJBQABLgAFFAQJCQAbAPwKAA==.Primàl:BAABLgAECn8sAAIKAAYJBRv2NADUAQAKAAYJBRv2NADUAQAAAA==.',
Pu='Punchinbag:BAAALgADCgYJBgAAAA==.Purifieds:BAAALgADCgEJAQAAAA==.',
Qs='Qsrqasda:BAABLgAECn8UAAISAAYJ4QUJPwCRAAASAAYJ4QUJPwCRAAAAAA==.',
Qt='Qtmenopaws:BAAALgAECgQJAwAAAA==.Qtptt:BAACLgAFFH8VAAIBAAMJKyNJHQAPAQABAAMJKyNJHQAPAQAuAAQKf0AAAgEACQmMI0kJAAgDAAEACQmMI0kJAAgDAAAA.',
Ra='Ragedeath:BAABLgAFFH8JAAISAAMJuA9lKwCbAAASAAMJuA9lKwCbAAABLgAFFAQJBAAHAAAAAA==.Ragedh:BAAALgAECgIJAgABLgAFFAQJBAAHAAAAAA==.Ragemonk:BAAALgADCgQJBAABLgAFFAQJBAAHAAAAAA==.Rageshaman:BAAALgAFFAQJBAAAAA==.Rasmong:BAABLgAECn8YAAIhAAkJyRCwHgC1AQAhAAkJyRCwHgC1AQAAAA==.Ravinsinda:BAAALgAECgYJBgAAAA==.Ravinursula:BAAALgAECgYJDwAAAA==.Rawrsaur:BAAALgAECgcJDQAAAA==.',
Re='Really:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.Reallyhpal:BAAALgAECgEJAQAAAA==.Redder:BAAALgAECgEJAQAAAA==.Remin:BAAALgADCgcJDAAAAA==.Retaliator:BAABLgAECn83AAMMAAgJeRgMXwCyAQAMAAgJeRgMXwCyAQARAAMJuAyEOAB6AAAAAA==.Reuuín:BAAALgAECggJCwABLgAECggJGQAdABwZAA==.Revan:BAAALgAECgYJBwAAAA==.',
Rh='Rhýs:BAAALgAECgYJBgAAAA==.',
Ri='Rih:BAAALgADCgMJBQAAAA==.Ripits:BAAALgADCgcJCAABLgAECgEJAQAHAAAAAA==.Risky:BAAALgAECgkJAwABLgAFFAIJAgAHAAAAAA==.Riskyfist:BAAALgAECgcJAgAAAA==.Risquae:BAAALgAECgIJAwAAAA==.',
Ro='Roadrashnuts:BAAALgAECgUJBwAAAA==.Rocc:BAAALgAECgcJBAAAAA==.Rocketeer:BAABLgAECn8mAAIbAAgJGg0BmwBBAQAbAAgJGg0BmwBBAQAAAA==.Romulis:BAAALgAECgEJAQAAAA==.Ronburgundii:BAAALgAECgEJAQAAAA==.',
Ru='Rudrya:BAABLgAECn8UAAInAAgJcAfhEwB8AQAnAAgJcAfhEwB8AQAAAA==.Rumpkey:BAAALgADCgcJCgAAAA==.Runalish:BAAALgAECgEJAQAAAA==.Runarinis:BAAALgADCgIJAgAAAA==.',
Ry='Rynopinn:BAACLgAFFH8JAAIKAAMJIhaCOQDEAAAKAAMJIhaCOQDEAAAuAAQKf0YABAoACAnqIxkLAOgCAAoACAnqIxkLAOgCAB8ABwm6G9IMAOUBABQAAgn4F4JkAIYAAAAA.Ryxn:BAAALgADCgYJBgAAAA==.',
['Rí']='Ríco:BAAALgADCgYJEAAAAA==.',
Sa='Saeed:BAAALgAECgEJAQAAAA==.Saelylasia:BAAALgAECgQJBQAAAA==.Sajaboy:BAAALgAECgMJBAAAAA==.Samusaran:BAAALgADCgEJAQAAAA==.Sarrania:BAAALgAECgUJBQAAAA==.Sartha:BAABLgAECn8pAAIMAAkJ0BfuLwA/AgAMAAkJ0BfuLwA/AgAAAA==.Sasuka:BAAALgAECggJCgAAAA==.Satsu:BAAALgAECgEJAQAAAA==.',
Sc='Scatherlia:BAAALgADCgYJBQABLgAECgQJBQAHAAAAAA==.Sco:BAAALgADCgEJAQABLgAECgYJDQAHAAAAAA==.Screwthebull:BAAALgAECgQJBAAAAA==.Scrumpvincet:BAAALgADCgUJBQAAAA==.',
Se='Sectiondk:BAAALgAECgYJEwAAAA==.Sedda:BAACLgAFFH8aAAIMAAcJ+SDRCgAgAgAMAAcJ+SDRCgAgAgAuAAQKfy0AAgwACAmnJc4GAGMDAAwACAmnJc4GAGMDAAAA.Seigfreid:BAAALgAECgYJCAAAAA==.Sensual:BAACLgAFFH8QAAIRAAQJDQjZDACoAAARAAQJDQjZDACoAAAuAAQKf0kAAhEACQlTFLMSAJsBABEACQlTFLMSAJsBAAAA.Seraphina:BAAALgAECgYJDgAAAA==.Sessano:BAAALgAECgYJDQAAAA==.Sesshomaru:BAACLgAFFH8HAAMIAAIJCiHgKABRAAAIAAEJ0CPgKABRAAAVAAEJRB7dkQBQAAAuAAQKf1MAAxUACQnUIxcTAOcCABUACAm3IRcTAOcCAAgACAkvJDIMAGACAAAA.',
Sh='Shadoly:BAAALgAECgcJEQAAAA==.Shadowboss:BAABLgAECn8iAAIEAAYJixERQQAKAQAEAAYJixERQQAKAQAAAA==.Shamhspriest:BAAALgAECgUJBQAAAA==.Shamnslam:BAAALgAECgEJAQAAAA==.Shang:BAACLgAFFH8PAAQUAAQJHSR/DwCkAQAUAAQJ2iN/DwCkAQAfAAEJhiCUGABeAAAKAAEJswMQeQApAAAuAAQKfzMABBQACQlMJVcCAE8DABQACQlMJVcCAE8DABkAAwm+HpU8AK8AAAoAAgnDEv7LADcAAAAA.Shiftchi:BAAALgAECgQJBQAAAA==.Shirona:BAABLgAECn80AAIVAAkJ6SFYBwAXAwAVAAkJ6SFYBwAXAwAAAA==.Shockazulu:BAAALgAECgEJAQAAAA==.Showstop:BAAALgAECgEJAQAAAA==.Shyvanna:BAABLgAECn8mAAMmAAkJyBHZIwC9AQAmAAkJyBHZIwC9AQAlAAQJ0wrQHABkAAAAAA==.Shïnïgämï:BAABLgAECn8WAAIoAAYJiCAvCQDeAQAoAAYJiCAvCQDeAQABLgAFFAIJBgANABwcAA==.Shøøtinlåvå:BAAALgADCgcJBwAAAA==.',
Si='Siare:BAABLgAECn8VAAIBAAYJSRhqfwA6AQABAAYJSRhqfwA6AQAAAA==.Sigarda:BAAALgAECgQJBAAAAA==.Silica:BAAALgAECgMJAwAAAA==.Silvershot:BAAALgADCgUJBQAAAA==.Siner:BAAALgAECgUJCAAAAA==.',
Sk='Skeeter:BAABLgAECn8+AAQkAAkJXR15AwBZAgAkAAkJBRp5AwBZAgABAAkJWxgbRwDFAQAjAAcJJx0PDACZAQAAAA==.Skiadrum:BAACLgAFFH8FAAIhAAMJgQFYOABgAAAhAAMJgQFYOABgAAAuAAQKf0IAAxgACQl+FBQpAN0BABgACAnXEhQpAN0BACEABAlBCTdmAIgAAAAA.Skoliro:BAAALgAECgcJCgAAAA==.Skorch:BAAALgADCgkJEAABLgAFFAQJCQAbAPwKAA==.',
Sm='Smotts:BAAALgAECgkJDwAAAA==.Smòtts:BAABLgAECn8bAAIZAAgJYx0QCgBEAgAZAAgJYx0QCgBEAgAAAA==.',
Sn='Snizard:BAABLgAECn8iAAICAAcJ9hxiNgABAgACAAcJ9hxiNgABAgAAAA==.Snuggiepoo:BAABLgAECn8kAAMDAAkJsh5wCwC3AgADAAgJ5CBwCwC3AgAEAAYJgRWqWACvAAAAAA==.',
So='Songbirds:BAAALgADCgcJDQAAAA==.Sonichoos:BAAALgAECgUJDAAAAA==.Sophiel:BAACLgAFFH8GAAIVAAMJqBKRYADJAAAVAAMJqBKRYADJAAAuAAQKfyMAAhUACAktG3gmADACABUACAktG3gmADACAAAA.Sosthenna:BAAALgADCgkJCQAAAA==.Soulbark:BAAALgAECgMJAwABLgAECgQJBAAHAAAAAQ==.Souleater:BAAALgADCgMJAwAAAA==.Soulforged:BAAALgADCgcJCwABLgAECgQJBAAHAAAAAA==.Soulreaver:BAAALgAECgcJCAAAAA==.Soulweaver:BAAALgAECgQJBAAAAQ==.',
Sp='Sparrowhåwk:BAAALgADCgUJBgAAAA==.Spicymustard:BAAALgAECgEJAQAAAA==.Spongebill:BAAALgADCgEJAQAAAA==.Spàdes:BAABLgAECn8cAAMQAAcJxxrGMQCGAQAQAAYJbhvGMQCGAQALAAMJbBLgRgCrAAAAAA==.',
St='Starel:BAAALgAECgQJBAAAAA==.Stellanoova:BAAALgAECgcJDwABLgAECggJFgAmAEoUAA==.Stevebushami:BAAALgAECgYJEAAAAA==.Stuwu:BAAALgAECgMJAwAAAA==.',
Su='Suffers:BAAALgAFFAEJAQAAAA==.Suou:BAAALgADCgcJCQABLgAECgEJAgAHAAAAAA==.Surj:BAABLgAECn8cAAMcAAYJ2RiFHABQAQAcAAYJ2RiFHABQAQAQAAQJeAuVZwC/AAAAAA==.',
Sv='Svmii:BAAALgADCgcJCgAAAA==.',
Sy='Sycther:BAAALgADCgEJAQABLgAFFAMJCQAKACIWAA==.',
Ta='Taazdingo:BAAALgAECgUJDwAAAA==.Taikuri:BAAALgAECggJDwABLgAECgYJFQABAEkYAA==.Taliela:BAAALgAECgQJBAAAAA==.Tanddralndra:BAAALgAECgUJBwAAAA==.Tanklilbaby:BAAALgAECgEJAQAAAA==.Tannia:BAAALgADCgYJCAAAAA==.Taxgirl:BAACLgAFFH8XAAMGAAUJiRzHTgBPAQAGAAUJiRzHTgBPAQATAAEJsQMPKwA3AAAuAAQKfycAAgYACAlAJWISAA0DAAYACAlAJWISAA0DAAAA.',
Te='Teabear:BAAALgAFFAMJBAAAAA==.Teralion:BAAALgAECgMJBgAAAA==.',
Th='Thaeldrik:BAAALgADCgcJCgAAAA==.Thaldreaux:BAAALgAECgMJBAAAAA==.Thefirst:BAAALgAECgMJBwAAAA==.Theleon:BAABLgAECn8dAAIUAAgJQg/0LgBhAQAUAAgJQg/0LgBhAQAAAA==.Thordrin:BAABLgAECn8yAAIJAAcJ/CQYCgDpAgAJAAcJ/CQYCgDpAgAAAA==.Thorlan:BAAALgADCgYJCAAAAA==.Thrasherzs:BAAALgAECgUJDQAAAA==.Thryen:BAAALgAECgUJCgAAAA==.Thunder:BAAALgADCgQJBAABLgAECgcJCgAHAAAAAA==.Thundergrasp:BAACLgAFFH8IAAInAAcJmgs0AwChAQAnAAcJmgs0AwChAQAuAAQKfxsAAicABwkNG5MPALUBACcABwkNG5MPALUBAAAA.',
Ti='Tianhe:BAAALgAECgMJAwAAAA==.Tiarisaril:BAAALgAECgYJBgAAAA==.Tigercita:BAAALgAECgMJAgAAAA==.Tippah:BAAALgAECgEJAwAAAA==.Tippers:BAAALgAECgEJAQAAAA==.',
Tj='Tjsneckbeard:BAAALgAECgEJAQAAAA==.',
To='Toe:BAABLgAFFH8FAAIGAAIJrRQGwwCdAAAGAAIJrRQGwwCdAAAAAA==.Tonkah:BAAALgAECgUJBQABLgAECggJEQAHAAAAAA==.Toobestake:BAAALgAFFAMJAwABLgAFFAUJFwACAIkjAA==.Topenga:BAACLgAFFH8VAAICAAQJMRnpMQBFAQACAAQJMRnpMQBFAQAuAAQKf0wAAgIACQnXH2kSAKQCAAIACQnXH2kSAKQCAAAA.Tosem:BAAALgAECgcJBwAAAA==.Touchypope:BAAALgADCgYJCwAAAA==.',
Tr='Treeage:BAAALgADCgMJAwAAAA==.Triggerd:BAAALgADCgEJAQAAAA==.Trunks:BAAALgADCgQJBAAAAA==.Trylok:BAAALgADCgEJAQAAAA==.Trüst:BAAALgAECggJDgAAAA==.',
Tw='Twicelife:BAABLgAECn8ZAAINAAgJ0R2VFgCSAgANAAgJ0R2VFgCSAgABLgAFFAQJFQALABYVAA==.',
Ty='Tyrygosa:BAAALgAECgUJBQABLgAFFAQJEAABAMEWAA==.',
['Tå']='Tånk:BAAALgAECggJEwAAAA==.',
Un='Undread:BAAALgAFFAEJAQABLgAFFAUJDwAQAGQdAA==.Uneedsummilk:BAAALgADCgcJBwAAAA==.Unholyapollo:BAAALgADCgYJCwAAAA==.',
Ur='Urthstripe:BAABLgAECn8uAAQKAAkJxBVdHABhAgAKAAkJxBVdHABhAgAUAAIJMgM9jQAxAAAfAAEJiwX7YgAaAAAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCAAGAIkhAA==.Vain:BAAALgAECgEJAgAAAA==.Valle:BAAALgAECgIJAwABLgAFFAcJGgAEALAaAA==.Valoria:BAAALgAECgMJCQABLgAFFAcJGgAEALAaAA==.',
Ve='Veil:BAAALgAECgIJCAABLgAFFAcJGgAEALAaAA==.Velarenea:BAAALgADCgEJAQAAAA==.Velgabrine:BAAALgAECgYJDAABLgAFFAQJEAAMADsjAA==.Veraani:BAAALgAECgYJBgAAAA==.Verra:BAAALgADCgYJBgAAAA==.',
Vi='Vil:BAAALgADCgcJBgAAAA==.Virlan:BAAALgADCgQJBAAAAA==.Viserion:BAABLgAECn8WAAMmAAgJShT5PAA1AQAmAAcJZBL5PAA1AQAiAAYJ2AySIADtAAAAAA==.',
Vo='Voidchaosfan:BAAALgAECgYJDAAAAA==.',
Vu='Vue:BAACLgAFFH8SAAIJAAQJQxNwJgDpAAAJAAQJQxNwJgDpAAAuAAQKf0YAAgkACQkkGzYfAB8CAAkACQkkGzYfAB8CAAAA.Vuldin:BAAALgAECgEJAgAAAA==.',
['Vö']='Völdemört:BAAALgADCgIJAgAAAA==.',
Wa='Wakasham:BAACLgAFFH8XAAInAAYJqCI3AQAeAgAnAAYJqCI3AQAeAgAuAAQKfzEAAicACQk9Jp4BAFMDACcACQk9Jp4BAFMDAAAA.Wardemon:BAAALgADCgIJAgAAAA==.Wardrake:BAAALgAECgEJAQAAAA==.',
We='Wehonoryou:BAABLgAECn8YAAIIAAYJ9CHYGAAAAgAIAAYJ9CHYGAAAAgAAAA==.Wetard:BAAALgADCgIJAgAAAA==.',
Wi='Willbyers:BAAALgAECgEJAQAAAA==.Winterloom:BAAALgAECgYJBgAAAA==.',
Wo='Wolfpacked:BAACLgAFFH8GAAINAAIJHBymWACYAAANAAIJHBymWACYAAAuAAQKfygAAg0ACQlBIP0IACADAA0ACQlBIP0IACADAAAA.Wolfzbåin:BAAALgAECgQJBAAAAA==.',
Wr='Wroot:BAAALgADCgYJCQAAAA==.Wrotten:BAABLgAECn8WAAIjAAgJ6RfOCgCvAQAjAAgJ6RfOCgCvAQAAAA==.',
Wu='Wunderlust:BAACLgAFFH8PAAIbAAQJhxdEUQBAAQAbAAQJhxdEUQBAAQAuAAQKf0QAAhsACQmFISYcAAYDABsACQmFISYcAAYDAAAA.',
Xe='Xemon:BAAALgAECgIJAgAAAA==.',
Xi='Xilyana:BAAALgAECgQJBAAAAA==.',
Xm='Xmatick:BAAALgAECgcJCQAAAA==.',
Xs='Xscrats:BAAALgAECgkJCAAAAA==.',
Ye='Yellowshaman:BAACLgAFFH8nAAIeAAYJiB9kDgC3AQAeAAYJiB9kDgC3AQAuAAQKfzIAAh4ACQk3IkQMANcCAB4ACQk3IkQMANcCAAAA.Yerac:BAAALgAECgEJAQAAAA==.',
Yu='Yukikage:BAAALgAECgMJAwAAAA==.Yutdaeng:BAAALgAECgMJBAAAAA==.',
Yv='Yvent:BAAALgADCgIJAgAAAA==.Yvraine:BAAALgAECgYJEgAAAA==.',
Za='Zakcarii:BAAALgADCgMJCAAAAA==.Zakin:BAAALgADCgcJBwAAAA==.Zalicy:BAAALgAECgYJEwAAAA==.Zalogar:BAAALgAECgcJCgAAAA==.Zapper:BAAALgAECgQJCwAAAA==.',
Zb='Zbarbb:BAAALgADCgUJBQAAAA==.',
Ze='Zealot:BAAALgAECgEJAQAAAA==.Zeeasyez:BAAALgAECgYJEwAAAA==.Zestul:BAAALgADCgEJAQAAAA==.',
Zh='Zhane:BAAALgADCgYJBwAAAA==.',
Zo='Zordon:BAAALgAECgYJEwAAAA==.',
Zs='Zslol:BAAALgAECgEJAQAAAA==.',
Zu='Zugg:BAAALgAECgMJBgABLgAFFAcJGgAEALAaAA==.Zuriznikov:BAAALgAECgEJAQABLgAECggJFgAmAEoUAA==.',
['Ån']='Ångie:BAAALgADCgMJAwAAAA==.',
['Øf']='Øffspeck:BAABLgAECn8gAAQBAAkJVhweLgBVAgABAAgJwxgeLgBVAgAjAAcJICEuDACXAQAkAAMJzh7MMAD3AAAAAA==.',
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
