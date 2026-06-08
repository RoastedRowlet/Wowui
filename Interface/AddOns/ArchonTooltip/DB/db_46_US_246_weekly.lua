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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Priest-Discipline','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','Unknown-Unknown','DemonHunter-Havoc','Paladin-Holy','Druid-Restoration','Warrior-Arms','Rogue-Subtlety','Paladin-Retribution','Shaman-Restoration','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','Paladin-Protection','DeathKnight-Blood','DeathKnight-Frost','Druid-Balance','DemonHunter-Devourer','Rogue-Assassination','Mage-Arcane','Monk-Mistweaver','Druid-Guardian','Monk-Brewmaster','Mage-Frost','Evoker-Preservation','Warrior-Protection','Shaman-Elemental','Druid-Feral','Mage-Fire','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Evoker-Augmentation','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=46,date='2026-06-07',data={Aa='Aaron:BAAALgAECgEJAQABLgAECgkJIAABAFYcAA==.Aaronfreeze:BAACLgAFFH8JAAICAAMJehrbTAD8AAACAAMJehrbTAD8AAAuAAQKfzIAAgIACQn1HsgcAG8CAAIACQn1HsgcAG8CAAAA.',
Ab='Abrakazaam:BAAALgADCgEJAQAAAA==.',
Ad='Adrios:BAACLgAFFH8FAAIDAAIJmRTCNQCWAAADAAIJmRTCNQCWAAAuAAQKfyYABAMACQnQFoMYAAMCAAMACAn9F4MYAAMCAAQABwlRB0ZOAM4AAAUAAwnKCCRpAIgAAAAA.',
Ae='Aetherion:BAAALgAECgMJBAAAAA==.',
Ai='Airorca:BAAALgAECgUJBQAAAA==.',
Aj='Ajaxz:BAABLgAECn8VAAIGAAkJ+RLTYADRAQAGAAkJ+RLTYADRAQAAAA==.',
Ak='Akaßoss:BAAALgADCgEJAQABLgAECgMJBQAHAAAAAA==.',
Al='Albedô:BAAALgAFFAIJAwABLgAFFAIJBwAIAAohAA==.Aliren:BAAALgAECgYJCgAAAA==.Allmaick:BAAALgADCggJCAAAAA==.Alucard:BAABLgAFFH8OAAIJAAQJ5gfqJwDdAAAJAAQJ5gfqJwDdAAAAAA==.Alystrasza:BAABLgAECn8dAAIKAAYJvhY9QwB8AQAKAAYJvhY9QwB8AQAAAA==.',
Am='Amorlandian:BAAALgAECgMJAwAAAA==.',
An='Antimovsky:BAAALgAECgcJEgAAAA==.',
Ap='Aphroditê:BAAALgAECgIJAgABLgAECgcJCAAHAAAAAA==.',
Aq='Aqours:BAAALgADCgcJBwABLgAECgEJAgAHAAAAAA==.',
Ar='Arcan:BAAALgAECgIJAgAAAA==.',
Au='Augustine:BAAALgAECgEJAQAAAA==.Aullyura:BAAALgADCgcJBwAAAA==.Auroras:BAACLgAFFH8IAAMFAAMJUwajJQCCAAAFAAMJUwajJQCCAAAEAAEJmAGtPAAvAAAuAAQKfxcAAgUABwmEE5k0AGwBAAUABwmEE5k0AGwBAAAA.',
Av='Aviaria:BAAALgAECgQJBAAAAA==.Avìendha:BAAALgADCgQJBAAAAA==.',
['Aì']='Aìnzooalgown:BAABLgAFFH8SAAIGAAQJESFiMwCFAQAGAAQJESFiMwCFAQABLgAFFAIJBwAIAAohAA==.',
Ba='Babakubwa:BAAALgAECgMJAwAAAA==.Babylonfive:BAAALgAECgcJDQAAAA==.Balhair:BAAALgADCgYJBgAAAA==.Banish:BAAALgAECgMJAgABLgAECgcJCgAHAAAAAA==.Barragdan:BAAALgADCgEJAQAAAA==.Basandra:BAAALgAECgEJAQAAAA==.Basicc:BAAALgADCgMJAwAAAA==.',
Be='Beachbumm:BAAALgADCgEJAQAAAA==.Belleta:BAAALgAECggJEQAAAA==.Berserk:BAEBLgAECn8eAAILAAYJRyNQCAAyAgALAAYJRyNQCAAyAgABLgAFFAMJBQAMALwMAA==.Bertringer:BAAALgAECgEJAgABLgAECgYJBgAHAAAAAA==.',
Bi='Bigmack:BAAALgAECgYJCwABLgAFFAYJGgANALIaAA==.Bigwilli:BAABLgAECn8VAAIOAAgJpxLNNgDIAQAOAAgJpxLNNgDIAQAAAA==.Bingßong:BAAALgADCgYJEQAAAA==.Biscuit:BAACLgAFFH8QAAQPAAYJhBoaGQDZAAACAAQJvCI1TgD4AAAPAAMJ7BEaGQDZAAAQAAIJ+xHXKACEAAAuAAQKfyIABA8ACAmPIycPAMgCAA8ACAl9HScPAMgCABAAAwnZH3w4AO8AAAIABAk+HlekAOwAAAAA.Bisha:BAABLgAECn9FAAMRAAkJEiHmDQDmAgARAAkJ9CDmDQDmAgALAAYJcBi7LwAAAQAAAA==.Bizcocho:BAAALgAECgcJDAAAAA==.',
Bl='Black:BAAALgADCgEJAQAAAA==.Bloodsimple:BAAALgADCgUJBQAAAA==.Blákers:BAABLgAFFH8KAAISAAQJfB5YAwBmAQASAAQJfB5YAwBmAQAAAA==.',
Bo='Boic:BAAALgADCgQJBAAAAA==.Bonesofdoom:BAACLgAFFH8HAAITAAMJ1w1JKACgAAATAAMJ1w1JKACgAAAuAAQKfyMAAxMACQkHGcoXAJoBABMACAmJG8oXAJoBAAYAAgkYBggyAV8AAAAA.Boogsta:BAACLgAFFH8OAAIUAAMJmgrfFADHAAAUAAMJmgrfFADHAAAuAAQKfzEAAhQACQmuErUIAPEBABQACQmuErUIAPEBAAAA.Boomkingobrr:BAACLgAFFH8HAAIVAAMJ9wiiMQCnAAAVAAMJ9wiiMQCnAAAuAAQKfxsAAhUACQkOHEQLAOECABUACQkOHEQLAOECAAAA.Boops:BAAALgAECgEJAQAAAA==.Bootysweatt:BAABLgAECn8aAAIIAAYJNhtqJACaAQAIAAYJNhtqJACaAQAAAA==.Boss:BAAALgADCgEJAQABLgAECgMJBQAHAAAAAA==.',
Br='Brewnz:BAAALgAECgUJBgAAAA==.Brucewee:BAAALgAECgQJCgAAAA==.',
Bu='Buckits:BAAALgAECgcJEgAAAA==.Bunsey:BAAALgADCgIJAgAAAA==.Burnsx:BAAALgAECgUJCgABLgAFFAgJGAAWAEoeAA==.Bussyman:BAAALgAECgYJEQABLgAFFAMJCQAKACIWAA==.',
Bw='Bwoar:BAAALgAECgQJBgAAAA==.',
['Bø']='Bøw:BAAALgAECgMJAwAAAA==.',
['Bü']='Bübble:BAAALgADCgEJAQAAAA==.',
Ca='Captnmurloc:BAAALgAECgkJEQAAAA==.Carl:BAAALgAECgEJAgABLgAFFAcJDgAXAJAaAA==.Carrach:BAAALgAECgIJBAAAAA==.Caveyodeler:BAAALgAECgQJCgAAAA==.',
Ce='Cedar:BAAALgAECgQJCwAAAA==.',
Ch='Cherga:BAAALgADCgYJBgAAAA==.Chinegga:BAAALgADCgYJBgAAAA==.Chitose:BAAALgADCgUJBQABLgAECgEJAgAHAAAAAA==.Chrapsasspee:BAAALgADCgcJGQAAAA==.Chrinn:BAAALgADCgIJAgAAAA==.',
Ci='Cindele:BAAALgADCgMJAwAAAA==.Cirvix:BAAALgAECgYJDAAAAA==.Cirxe:BAABLgAECn8iAAIYAAkJMg46BACuAQAYAAkJMg46BACuAQAAAA==.',
Cl='Clampire:BAAALgAECgQJBAAAAA==.Cliint:BAAALgAECgcJCwAAAA==.Cloúnt:BAAALgAECgEJAwABLgAFFAMJBwAVAPcIAA==.',
Co='Commotionn:BAAALgAECgQJBAAAAA==.Coms:BAAALgADCgIJAgAAAA==.Cooz:BAAALgAECgYJDgAAAA==.Corybooker:BAAALgAECgcJBAAAAA==.Cowdux:BAAALgAECgkJEgAAAA==.',
Cr='Creamdragon:BAAALgADCgYJCgABLgAECggJMQAZAFgdAA==.',
Cu='Curuni:BAAALgADCgcJDAAAAA==.',
Cz='Czechhunter:BAAALgADCgUJBQAAAA==.',
['Cå']='Cåleb:BAAALgAECgEJAQAAAA==.',
['Cø']='Cønstance:BAABLgAECn8VAAIaAAcJvRFsIwAkAQAaAAcJvRFsIwAkAQAAAA==.',
Da='Daddyphat:BAABLgAECn8rAAIbAAgJrCRDBgDRAgAbAAgJrCRDBgDRAgAAAA==.Daddý:BAAALgAECgEJAQAAAA==.Dalight:BAABLgAECn8XAAIJAAYJKiYPDwCdAgAJAAYJKiYPDwCdAgAAAA==.Dankins:BAACLgAFFH8dAAIOAAgJ2SLxAADpAgAOAAgJ2SLxAADpAgAuAAQKfxYAAg4ACAkGHfYZAEcCAA4ACAkGHfYZAEcCAAAA.',
De='Deathmager:BAABLgAECn87AAIcAAkJjBLzRAAHAgAcAAkJjBLzRAAHAgAAAA==.Deathtraper:BAAALgAECgcJDQAAAA==.Debur:BAAALgADCgEJAQAAAA==.Deltaka:BAAALgAECgEJAQAAAA==.Demonfella:BAAALgADCgMJAwAAAA==.Demonicpeach:BAABLgAECn8YAAIBAAcJwwvDpQDxAAABAAcJwwvDpQDxAAAAAA==.Denaian:BAAALgADCgYJBgAAAA==.Dethsent:BAAALgAECggJEQAAAA==.Dette:BAABLgAECn8cAAICAAgJWhSAQwDNAQACAAgJWhSAQwDNAQAAAA==.Devilchaser:BAAALgAECgYJDAAAAA==.Devourer:BAABLgAECn8VAAIWAAcJjg+mbQBaAQAWAAcJjg+mbQBaAQAAAA==.',
Di='Diaval:BAAALgADCgIJAgABLgAECgkJLAABAFsTAA==.Dinosforlife:BAAALgAECgYJBgAAAA==.',
Dk='Dkboss:BAAALgAECgEJAQABLgAECgMJBQAHAAAAAA==.',
Do='Donzilly:BAAALgAECgYJDgAAAA==.Doreme:BAAALgADCgIJAgAAAA==.Dorgrim:BAAALgAECgQJBwAAAA==.',
Dr='Drafted:BAAALgAECgcJEAAAAA==.Drax:BAAALgAECgMJAwAAAA==.Drewmcmoo:BAAALgADCgcJBgAAAA==.Drsath:BAAALgADCgcJBwAAAA==.Drunkorca:BAAALgADCgUJBQAAAA==.',
Ea='Earnar:BAAALgADCgYJDAAAAA==.',
Ed='Edarix:BAAALgADCggJDAABLgAECggJMwANAHkYAA==.',
Ei='Eiliyah:BAABLgAECn8yAAMJAAgJehz0FgBaAgAJAAgJehz0FgBaAgANAAIJHwIaWgElAAAAAA==.',
Ek='Ekmek:BAAALgAECgEJAQAAAA==.',
El='Elabernathy:BAABLgAECn8sAAICAAkJKhbPJQBAAgACAAkJKhbPJQBAAgAAAA==.Elenay:BAABLgAECn8UAAIKAAgJqR49IgAvAgAKAAgJqR49IgAvAgAAAA==.Elesia:BAAALgAECgkJEgAAAA==.Elfussy:BAAALgAECgEJAQAAAA==.Elgoku:BAAALgAECgQJCgABLgAECgUJDAAHAAAAAA==.Eliarssande:BAAALgAECgEJAQAAAA==.Elinay:BAAALgAECgQJBAABLgAECggJFAAKAKkeAA==.Elixia:BAABLgAECn8bAAIIAAgJDA3RIwBIAQAIAAgJDA3RIwBIAQAAAA==.Elpatron:BAAALgAFFAMJAwABLgAFFAMJCAAdABoNAA==.Elylanea:BAAALgAECgUJDgAAAA==.',
Em='Emulsdeath:BAABLgAECn8UAAMTAAgJKCEiEgDhAQATAAcJLB4iEgDhAQAGAAYJ8iBzZgCTAQABLgAFFAQJEAANADsjAA==.Emulsifier:BAACLgAFFH8QAAINAAQJOyN9FgCdAQANAAQJOyN9FgCdAQAuAAQKfzAAAg0ACAmFJr8LAAADAA0ACAmFJr8LAAADAAAA.',
En='Ennoa:BAAALgAECgEJAQAAAA==.',
Er='Ergen:BAACLgAFFH8ZAAIQAAUJthp/DwA9AQAQAAUJthp/DwA9AQAuAAQKfyoAAhAACAlvIaUGAJcCABAACAlvIaUGAJcCAAAA.',
Eu='Eusexua:BAAALgAECgQJBQABLgAECgcJCgAHAAAAAA==.',
Ex='Expiatory:BAAALgAECgYJCAAAAA==.',
Fa='Fairbear:BAABLgAECn8dAAQRAAYJ+Bx9NwBjAQARAAYJ+Bx9NwBjAQALAAEJZA5tPgA7AAAeAAEJ6QcCWgAbAAAAAA==.Faustt:BAAALgAECgUJBwAAAA==.',
Fi='Filthyfabio:BAAALgADCgcJEQAAAA==.Finester:BAABLgAFFH8HAAIMAAQJNBhDEwBfAQAMAAQJNBhDEwBfAQAAAA==.Fireburr:BAAALgAECgMJAwAAAA==.',
Fl='Flatline:BAAALgAECgcJEgAAAA==.Fløw:BAAALgAECgMJCgAAAA==.',
Fr='Fragglerott:BAABLgAECn8bAAMOAAgJGBOhfQDYAAAOAAQJUhKhfQDYAAAfAAgJ1Ao8YQCzAAAAAA==.Frati:BAAALgAECgEJAQAAAA==.Friedchickn:BAAALgAECgQJCAAAAA==.Frostboss:BAAALgADCgEJAQAAAA==.Frostnips:BAAALgADCgMJAwAAAA==.Frosttrinity:BAAALgADCgUJBAAAAA==.',
Fu='Funslinger:BAAALgAECgQJDAAAAA==.',
Ga='Gaffz:BAAALgAECgEJAgAAAA==.Galannar:BAAALgAECggJDQAAAA==.Galvrax:BAAALgAECgUJCgAAAA==.Gast:BAACLgAFFH8PAAIRAAUJZB1PFgBOAQARAAUJZB1PFgBOAQAuAAQKfzUAAxEACQlRIOMIAMwCABEACQlRIOMIAMwCAB4ABAmpFmUzAKIAAAAA.',
Ge='Gearwick:BAAALgADCgYJBwABLgAECgcJJgAJAFAhAA==.',
Gh='Ghstfacekila:BAAALgADCgEJAQAAAA==.',
Go='Gorska:BAABLgAECn82AAIfAAkJfB0IDwB1AgAfAAkJfB0IDwB1AgAAAA==.',
Gr='Grawm:BAABLgAECn8iAAMPAAkJqiKzHgAxAgAPAAgJSRWzHgAxAgACAAkJPiA5SgC4AQAAAA==.Greedory:BAAALgADCgIJAgAAAA==.Groot:BAAALgADCgUJBgAAAA==.Gruetss:BAAALgAECgQJBAAAAA==.',
['Gä']='Gämbit:BAAALgADCgEJAQAAAA==.',
Ha='Hailbringer:BAAALgAECgcJDgAAAA==.Hakoona:BAABLgAECn8yAAIbAAkJFxrgEAAsAgAbAAkJFxrgEAAsAgAAAA==.Hanginaround:BAAALgAECgEJAQAAAA==.Hangman:BAACLgAFFH8XAAIJAAMJ8CV3GgBBAQAJAAMJ8CV3GgBBAQAuAAQKfx8AAwkACQmqH7AHAAgDAAkACQmqH7AHAAgDAA0ABAklDTkRAZcAAAEuAAUUAwkJAAoAIhYA.Hanni:BAABLgAECn8dAAIPAAgJUhzsCgCvAQAPAAgJUhzsCgCvAQAAAA==.Haveaburitto:BAACLgAFFH8NAAIcAAQJWBzMUwA3AQAcAAQJWBzMUwA3AQAuAAQKfygAAhwACAk0JXkMAGEDABwACAk0JXkMAGEDAAAA.Hawktoetem:BAAALgAECgUJCAABLgAECgYJHQARAPgcAA==.',
He='Healmemaybe:BAABLgAECn8bAAIKAAYJQiPUIQAxAgAKAAYJQiPUIQAxAgAAAA==.Healthyadult:BAAALgAECgMJBQAAAA==.Hellshand:BAAALgAECgYJDAAAAA==.Heracles:BAAALgAECgQJBAAAAA==.Heretic:BAAALgADCgEJAQAAAA==.',
Hi='Hickscale:BAAALgADCgMJAwAAAA==.',
Ho='Holycøw:BAAALgADCgMJAwAAAA==.Holydefender:BAAALgADCgcJDQAAAA==.Holyhands:BAAALgADCgYJBgAAAA==.Holyholyholy:BAAALgAECgYJCwAAAA==.Honest:BAAALgADCgMJAwAAAA==.',
Hu='Hunniee:BAAALgAECgEJAQAAAA==.Huntrix:BAAALgADCgcJEgAAAA==.',
Ic='Icedatt:BAABLgAECn8VAAMGAAUJ8QIbGQF8AAAGAAUJ7AIbGQF8AAATAAUJcwEHUABKAAAAAA==.Icefire:BAAALgADCgUJBAAAAA==.',
Ik='Ikur:BAACLgAFFH8PAAIJAAQJrxtNGwA7AQAJAAQJrxtNGwA7AQAuAAQKfzsAAgkACQmTHvwGABUDAAkACQmTHvwGABUDAAAA.',
Il='Ilinia:BAAALgAECgYJCAABLgAECgUJEgAHAAAAAA==.Illhealutoo:BAAALgAECgEJAgAAAA==.',
Im='Imsteve:BAAALgAECgEJAQAAAA==.',
In='Infoxicated:BAAALgADCgcJCAABLgAECgkJJAADALIeAA==.Insîght:BAAALgAECgQJCAAAAA==.',
Ip='Ipopkidneys:BAACLgAFFH8VAAMMAAcJ1SG1CgDGAQAMAAYJlSG1CgDGAQAXAAMJjB2JBgD8AAAuAAQKfycAAwwACQnhJYQMANACAAwACQnhJYQMANACABcAAQn1I8EdAGUAAAAA.',
Ir='Iroi:BAAALgAECgIJBQAAAA==.',
Is='Iskur:BAABLgAECn8mAAMOAAgJ4BgLIQA9AgAOAAgJ4BgLIQA9AgAfAAMJMQ1zcACKAAABLgAFFAQJDwAJAK8bAA==.Isuck:BAAALgAFFAIJAgAAAA==.Isurr:BAABLgAECn8iAAIZAAcJnhKfNQCJAQAZAAcJnhKfNQCJAQABLgAFFAQJDwAJAK8bAA==.',
It='Itakecandle:BAAALgAECgUJBwABLgAECgUJDAAHAAAAAA==.',
Iv='Ivanapump:BAAALgAECgIJAgABLgAECgYJBgAHAAAAAA==.',
Ja='Jackkal:BAAALgAECgcJCQAAAA==.Jadethecat:BAAALgADCgMJAwAAAA==.Jakbis:BAAALgADCgEJAQAAAA==.Jakychan:BAAALgAECgEJAQAAAA==.Jaldiar:BAAALgADCgcJBwABLgAECgYJBgAHAAAAAA==.Jametrok:BAAALgAECgEJAQAAAA==.Jazbek:BAAALgAECgQJDgAAAA==.Jazzonus:BAAALgAECgQJBAAAAA==.',
Je='Jefferey:BAAALgADCgMJAwAAAA==.Jennyanydots:BAAALgAECgIJBAABLgAFFAcJGgAEALAaAA==.Jeriçho:BAAALgADCgYJBgAAAA==.',
Jh='Jhonwick:BAAALgAECgIJAgAAAA==.',
Ji='Jippedo:BAAALgAECgYJAgABLgAECgcJBAAHAAAAAA==.Jiraîya:BAAALgAECgQJBQAAAA==.',
Jo='Jordak:BAABLgAECn8oAAIKAAkJBBw2DQDqAgAKAAkJBBw2DQDqAgAAAA==.Jorolee:BAAALgADCgEJAQAAAA==.',
Ka='Kaddiya:BAAALgAECgEJAQAAAA==.Kagonstrasza:BAAALgAECgQJBAAAAA==.Kallistos:BAABLgAECn8gAAIOAAcJER1aKwAAAgAOAAcJER1aKwAAAgAAAA==.Kariza:BAAALgAECgQJBgAAAA==.Karunik:BAAALgADCgYJBgABLgAECgcJCgAHAAAAAA==.Kasst:BAAALgAECgEJAQAAAA==.',
Ke='Kelenheller:BAAALgADCgcJFAAAAA==.',
Kh='Khione:BAAALgADCgYJBgAAAA==.Khthonios:BAAALgAECgEJAQAAAA==.',
Ki='Kibblerina:BAAALgADCgcJBwAAAA==.Kiranam:BAABLgAECn8cAAQgAAgJrQ6dEQCTAQAgAAgJqQqdEQCTAQAaAAcJNQwTNADGAAAVAAIJWwfecQBZAAAAAA==.',
Kn='Knarth:BAABLgAECn86AAIhAAkJHRxeAQCUAgAhAAkJHRxeAQCUAgAAAA==.Kníght:BAAALgAECgcJBwAAAA==.',
Ko='Koisy:BAAALgAECgUJDgABLgAECggJFAAKAKkeAA==.Kole:BAAALgAECgEJAQAAAA==.Koopa:BAABLgAECn8pAAIRAAkJ0yQeBQAKAwARAAkJ0yQeBQAKAwAAAA==.',
Kr='Krasul:BAACLgAFFH8VAAMOAAUJEBjpHwBbAQAOAAUJEBjpHwBbAQAfAAIJ7Qn6QQB2AAAuAAQKfx8AAw4ACAkXIecIAOgCAA4ACAkXIecIAOgCAB8ABgm/HPIxAJQBAAAA.Krenthok:BAABLgAECn8eAAIBAAgJiQfdgwAtAQABAAgJiQfdgwAtAQAAAA==.',
Ku='Kuraha:BAAALgAECgQJBAAAAA==.Kushar:BAAALgAECgQJBQABLgAECggJFwAiAMQQAA==.',
Ky='Kyuketsuki:BAAALgAFFAIJAgAAAA==.',
La='Lachance:BAAALgADCgQJBAAAAA==.Large:BAAALgADCgYJBgAAAA==.Largemann:BAAALgAECgYJDAABLgAFFAUJFgAGAIkcAA==.Lathspell:BAABLgAECn8yAAIcAAkJtiC9IwCIAgAcAAkJtiC9IwCIAgAAAA==.Lazyevoker:BAAALgADCgQJBAABLgAECgEJAQAHAAAAAA==.',
Le='Leahan:BAAALgAECgQJCgAAAA==.Leloo:BAAALgADCgYJCgABLgAECgIJAwAHAAAAAA==.',
Lh='Lhureciv:BAACLgAFFH8UAAMEAAQJERnOEgA9AQAEAAQJERnOEgA9AQADAAEJKRsSQwBFAAAuAAQKf0sAAwQACQnVI80GAB4DAAQACQnVI80GAB4DAAMABgn7HjAjAHoBAAAA.',
Li='Lightchaser:BAAALgADCgMJAgAAAA==.Lightfkyou:BAAALgADCgcJCgAAAA==.Lihvurce:BAABLgAECn8fAAMNAAgJWR3iLgA7AgANAAgJWR3iLgA7AgAJAAQJpR0FSwBMAQABLgAFFAQJFAAEABEZAA==.Lillianna:BAACLgAFFH8FAAIMAAIJoQ9sLwCWAAAMAAIJoQ9sLwCWAAAuAAQKfzQAAgwACAmSG4kNAEQCAAwACAmSG4kNAEQCAAAA.Lingchi:BAAALgAECgQJBgAAAA==.',
Ll='Llew:BAAALgAECgMJBAAAAA==.',
Lo='Loenhart:BAAALgAECgEJAQAAAA==.Lolkurtone:BAAALgAECgIJAgAAAA==.',
Lu='Luciaan:BAAALgADCgkJGQAAAA==.Lucrative:BAAALgADCgcJDQAAAA==.Lug:BAAALgAECgEJAQAAAA==.Lulue:BAAALgADCgQJBAAAAA==.Luminari:BAAALgADCgUJBQAAAA==.Lunastorm:BAACLgAFFH8NAAIdAAQJLxMOFwAQAQAdAAQJLxMOFwAQAQAuAAQKfzgAAh0ACQnQImgCAEIDAB0ACQnQImgCAEIDAAAA.Luponero:BAACLgAFFH8VAAMCAAUJiSMaGQCLAQACAAUJiSMaGQCLAQAPAAEJ5QapKgBGAAAuAAQKfyEAAw8ACAnnHuYQALUCAA8ACAl6HeYQALUCAAIAAwnNH0GQABMBAAAA.',
Ly='Lynney:BAAALgADCgYJBwAAAA==.',
Ma='Macmn:BAACLgAFFH8TAAIfAAUJzxx/DgCkAQAfAAUJzxx/DgCkAQAuAAQKfygAAh8ABwnAJGULAOICAB8ABwnAJGULAOICAAAA.Magicard:BAABLgAECn8fAAIcAAgJjg4ldQCKAQAcAAgJjg4ldQCKAQAAAA==.Makesfood:BAABLgAECn8qAAIcAAcJZBeSdADpAQAcAAcJZBeSdADpAQAAAA==.Mamaheals:BAABLgAECn8rAAIFAAkJTBoaEwA2AgAFAAkJTBoaEwA2AgAAAA==.Mandos:BAAALgAECgYJBwAAAA==.Mantistabogn:BAAALgAFFAEJAQAAAA==.Maor:BAABLgAECn8XAAINAAgJlxcuUADxAQANAAgJlxcuUADxAQAAAA==.March:BAAALgADCgEJAQAAAA==.Markeisha:BAAALgAECgQJCAABLgAECgYJDAAHAAAAAA==.',
Me='Mechz:BAAALgAECgYJBgABLgAFFAQJCQAcAPwKAA==.Mechzician:BAACLgAFFH8JAAIcAAQJ/ArqbgD6AAAcAAQJ/ArqbgD6AAAuAAQKfzgAAhwACAlwGXtZAC0CABwACAlwGXtZAC0CAAAA.Mechzlock:BAAALgADCgEJAQABLgAFFAQJCQAcAPwKAA==.Melinoe:BAAALgAECgEJAQAAAA==.Merlerk:BAAALgADCgYJBgAAAA==.Merlini:BAABLgAECn8dAAMEAAgJWRaLIQCzAQAEAAcJ0xiLIQCzAQADAAUJThbmOQAdAQAAAA==.Mets:BAAALgAECgYJCQABLgAECgYJFQABAEkYAA==.',
Mi='Microplastic:BAAALgAECgUJBQAAAA==.Micspanky:BAAALgAECggJEgAAAA==.Mistynight:BAAALgADCgIJAgAAAA==.Mithrandi:BAAALgAECgYJCQAAAA==.Mitzis:BAABLgAFFH8KAAICAAMJ8x+QRwALAQACAAMJ8x+QRwALAQAAAA==.',
Mo='Moltiy:BAAALgADCggJCwAAAA==.Moltten:BAAALgADCgYJCgAAAA==.Mornhathor:BAAALgAECggJDgABLgAECgYJBwAHAAAAAA==.',
Mu='Mufinblaster:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgADCgIJBgAAAA==.Musnicker:BAAALgAECgQJBwABLgAECggJJQAPAI8RAA==.',
My='Myro:BAACLgAFFH8UAAMOAAQJ3B8FIgBOAQAOAAQJ3B8FIgBOAQAfAAIJZRS+OwCKAAAuAAQKfxsAAg4ABwm/JsEHAPkCAA4ABwm/JsEHAPkCAAAA.',
['Mè']='Mètis:BAAALgAECgcJCAAAAA==.',
Na='Nanis:BAAALgAECgYJBgABLgAFFAQJCwAVAMwgAA==.Narmer:BAAALgAECgIJAgAAAA==.',
Ne='Neel:BAAALgADCgQJBQAAAA==.Nervhoost:BAAALgADCgMJAwAAAA==.Neuropolis:BAAALgADCgcJFQAAAA==.Neuroscience:BAAALgADCgMJAwAAAA==.Neurotics:BAABLgAECn80AAQjAAgJACZlAgCiAgAjAAcJsCVlAgCiAgAkAAcJoiO6AwBIAgABAAUJ5BoBuwDjAAAAAA==.Neò:BAABLgAECn8YAAMlAAYJvBDXDwAEAQAlAAYJXw7XDwAEAQAmAAEJ/hTuiwA0AAAAAA==.',
Ni='Niesh:BAAALgAECgEJBwAAAA==.Nightrush:BAAALgADCgEJAQAAAA==.Nineoneone:BAABLgAECn80AAMFAAgJ0xSJGgDoAQAFAAgJ0xSJGgDoAQADAAQJjgPqRQCLAAAAAA==.',
No='Nobledecay:BAAALgAECgQJBQAAAA==.Nocturne:BAAALgAECgEJAwAAAA==.',
Nu='Nubbletcake:BAAALgADCgEJAQABLgAECgkJJAADALIeAA==.Nula:BAAALgAECgMJBAABLgAFFAcJGgAEALAaAA==.',
Ny='Nylveth:BAACLgAFFH8PAAIEAAUJNg+ZGgAIAQAEAAUJNg+ZGgAIAQAuAAQKfyoAAgQACQkAHYsPAFsCAAQACQkAHYsPAFsCAAEuAAUUBgkHACcA+woA.',
Oa='Oathatone:BAAALgAECgEJAQAAAA==.',
Oc='Ocra:BAABLgAECn8gAAInAAkJ9g5KDQDQAQAnAAkJ9g5KDQDQAQABLgAFFAQJFQACADEZAA==.',
Of='Offspeck:BAAALgAECgIJAgABLgAECgkJIAABAFYcAA==.',
Ou='Outtkast:BAAALgAECgIJAgAAAA==.Outtkastt:BAAALgAECgcJBwAAAA==.Ouutkast:BAAALgAECgIJAwAAAA==.',
Oz='Ozwald:BAABLgAECn81AAIQAAkJchzNDwAwAgAQAAkJchzNDwAwAgAAAA==.',
Pa='Pallyangel:BAAALgADCgcJDwAAAA==.Pandemul:BAAALgAECgMJAwABLgAFFAQJEAANADsjAA==.Patrio:BAACLgAFFH8IAAIdAAMJGg2aHwCdAAAdAAMJGg2aHwCdAAAuAAQKfywAAh0ACQllGZcHAHYCAB0ACQllGZcHAHYCAAAA.',
Pe='Peaceonea:BAABLgAECn8bAAIWAAkJrgRtlgDoAAAWAAkJrgRtlgDoAAAAAA==.Peachaid:BAECLgAFFH8bAAMDAAgJ9Rf0BgCXAgADAAgJ9Rf0BgCXAgAFAAEJRQgLNgAtAAAuAAQKfzAAAwMACQlVIgMFADUDAAMACQlVIgMFADUDAAUABgkYHSglAMABAAAA.Peatri:BAAALgAECgkJCwAAAA==.Peetree:BAABLgAFFH8GAAIOAAQJPRhSKgAlAQAOAAQJPRhSKgAlAQAAAA==.Pekin:BAAALgAECgEJAQAAAA==.',
Ph='Phosphorus:BAACLgAFFH8VAAMLAAQJFhXEFwATAQALAAQJihPEFwATAQAeAAIJjxRQIACGAAAuAAQKf1kAAwsACQnmIOAEALoCAAsACQnHHuAEALoCAB4ABgkqHEYXAH0BAAAA.',
Pl='Plagüë:BAACLgAFFH8QAAMTAAQJzRw3JQC3AAAGAAMJpCCQbQAZAQATAAMJ3RA3JQC3AAAuAAQKf00AAwYACQmjJRYPAO0CAAYACQmjJRYPAO0CABMABQmbD7g2ALEAAAAA.Pleistarchus:BAAALgAECgYJCQAAAA==.',
Po='Poic:BAAALgADCgEJAQAAAA==.Polo:BAAALgADCgEJAQAAAA==.Poofighter:BAAALgAECgMJBwABLgAFFAIJBwAIAAohAA==.Poonan:BAAALgAECgYJBgAAAA==.',
Pp='Ppgangandlaw:BAAALgADCgEJAQAAAA==.',
Pr='Precious:BAAALgAECggJEgAAAA==.Primalistic:BAAALgADCgUJBQABLgAFFAQJCQAcAPwKAA==.Primàl:BAABLgAECn8sAAIKAAYJBRv2NADUAQAKAAYJBRv2NADUAQAAAA==.',
Pu='Punchinbag:BAAALgADCgYJBgAAAA==.Purifieds:BAAALgADCgEJAQAAAA==.',
Qs='Qsrqasda:BAABLgAECn8UAAITAAYJ4QVMPACVAAATAAYJ4QVMPACVAAAAAA==.',
Qt='Qtmenopaws:BAAALgAECgQJAwAAAA==.Qtptt:BAACLgAFFH8TAAIBAAMJyh9JHQAPAQABAAMJyh9JHQAPAQAuAAQKfz4AAgEACAkpI6gXAJECAAEACAkpI6gXAJECAAAA.',
Ra='Ragedeath:BAABLgAFFH8JAAITAAMJuA/1JwCiAAATAAMJuA/1JwCiAAABLgAFFAQJBAAHAAAAAA==.Ragedh:BAAALgAECgIJAgABLgAFFAQJBAAHAAAAAA==.Ragemonk:BAAALgADCgQJBAABLgAFFAQJBAAHAAAAAA==.Rageshaman:BAAALgAFFAQJBAAAAA==.Rasmong:BAABLgAECn8XAAIiAAgJxBBhJgB3AQAiAAgJxBBhJgB3AQAAAA==.Ravinsinda:BAAALgAECgYJBgAAAA==.Ravinursula:BAAALgAECgYJDQAAAA==.Rawrsaur:BAAALgAECgcJDQAAAA==.',
Re='Really:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.Reallyhpal:BAAALgAECgEJAQAAAA==.Redder:BAAALgAECgEJAQAAAA==.Remin:BAAALgADCgYJBgAAAA==.Retaliator:BAABLgAECn8zAAMNAAgJeRi8YgChAQANAAgJeRi8YgChAQASAAMJuAyfNgB6AAAAAA==.Reuuín:BAAALgAECggJCgABLgAECggJGAAMABwZAA==.Revan:BAAALgAECgYJBwAAAA==.',
Rh='Rhýs:BAAALgAECgYJBgAAAA==.',
Ri='Rih:BAAALgADCgMJBQAAAA==.Ripits:BAAALgADCgcJCAABLgAECgEJAQAHAAAAAA==.Risky:BAAALgAECgkJAwABLgAFFAIJAgAHAAAAAA==.Riskyfist:BAAALgAECgcJAgAAAA==.Risquae:BAAALgAECgIJAwAAAA==.',
Ro='Roadrashnuts:BAAALgAECgUJBwAAAA==.Rocc:BAAALgAECgcJBAAAAA==.Rocketeer:BAABLgAECn8kAAIcAAgJ1gvXoAA2AQAcAAgJ1gvXoAA2AQAAAA==.Romulis:BAAALgAECgEJAQAAAA==.Ronburgundii:BAAALgAECgEJAQAAAA==.',
Ru='Rudrya:BAABLgAECn8UAAInAAgJcAfhEwB8AQAnAAgJcAfhEwB8AQAAAA==.Rumpkey:BAAALgADCgcJCgAAAA==.Runalish:BAAALgAECgEJAQAAAA==.Runarinis:BAAALgADCgIJAgAAAA==.',
Ry='Rynopinn:BAACLgAFFH8JAAIKAAMJIhZ5NgDRAAAKAAMJIhZ5NgDRAAAuAAQKf0YABAoACAnqIxkLAOgCAAoACAnqIxkLAOgCACAABwm6Gy8MAOUBABUAAgn4Fw9hAIcAAAAA.Ryxn:BAAALgADCgYJBgAAAA==.',
['Rí']='Ríco:BAAALgADCgYJEAAAAA==.',
Sa='Saeed:BAAALgAECgEJAQAAAA==.Saelylasia:BAAALgAECgQJBQAAAA==.Sajaboy:BAAALgAECgMJBAAAAA==.Samusaran:BAAALgADCgEJAQAAAA==.Sarrania:BAAALgAECgUJBQAAAA==.Sartha:BAABLgAECn8mAAINAAgJUxbPSwDaAQANAAgJUxbPSwDaAQAAAA==.Sasuka:BAAALgAECgcJCQAAAA==.Satsu:BAAALgAECgEJAQAAAA==.',
Sc='Scatherlia:BAAALgADCgYJBQABLgAECgQJBQAHAAAAAA==.Sco:BAAALgADCgEJAQABLgAECgYJDQAHAAAAAA==.Screwthebull:BAAALgAECgQJBAAAAA==.Scrumpvincet:BAAALgADCgUJBQAAAA==.',
Se='Sectiondk:BAAALgAECgYJEwAAAA==.Sedda:BAACLgAFFH8ZAAINAAcJ+SAsCAArAgANAAcJ+SAsCAArAgAuAAQKfy0AAg0ACAmnJc4GAGMDAA0ACAmnJc4GAGMDAAAA.Seigfreid:BAAALgAECgYJCAAAAA==.Sensual:BAACLgAFFH8QAAISAAQJDQhyCwCzAAASAAQJDQhyCwCzAAAuAAQKf0kAAhIACQlTFNURAJ4BABIACQlTFNURAJ4BAAAA.Seraphina:BAAALgAECgYJDgAAAA==.Sessano:BAAALgAECgYJDQAAAA==.Sesshomaru:BAACLgAFFH8HAAMIAAIJCiEyJQBTAAAIAAEJ0CMyJQBTAAAWAAEJRB7+iQBSAAAuAAQKf1MAAxYACQnUIxcTAOcCABYACAm3IRcTAOcCAAgACAkvJFALAGQCAAAA.',
Sh='Shadoly:BAAALgAECgcJEQAAAA==.Shadowboss:BAABLgAECn8iAAIEAAYJixEEPwANAQAEAAYJixEEPwANAQAAAA==.Shamhspriest:BAAALgAECgUJBQAAAA==.Shamnslam:BAAALgAECgEJAQAAAA==.Shang:BAACLgAFFH8LAAMVAAQJzCALEQCCAQAVAAQJzCALEQCCAQAKAAEJswMBcwAtAAAuAAQKfzEABBUACQksJVkCAE0DABUACQksJVkCAE0DABoAAwm+Hhg5ALAAAAoAAgnDEoTHADcAAAAA.Shiftchi:BAAALgAECgEJAQAAAA==.Shirona:BAABLgAECn8uAAIWAAkJuyEPBwAUAwAWAAkJuyEPBwAUAwAAAA==.Shockazulu:BAAALgADCgEJAQAAAA==.Showstop:BAAALgAECgEJAQAAAA==.Shyvanna:BAABLgAECn8mAAMmAAkJyBGlIgC9AQAmAAkJyBGlIgC9AQAlAAQJ0wqHKwDBAAAAAA==.Shïnïgämï:BAABLgAECn8WAAIoAAYJiCAvCQDeAQAoAAYJiCAvCQDeAQABLgAFFAIJBgAOABwcAA==.',
Si='Siare:BAABLgAECn8VAAIBAAYJSRiIfAA7AQABAAYJSRiIfAA7AQAAAA==.Sigarda:BAAALgAECgQJBAAAAA==.Silica:BAAALgAECgMJAwAAAA==.Silvershot:BAAALgADCgUJBQAAAA==.Siner:BAAALgAECgUJCAAAAA==.',
Sk='Skeeter:BAABLgAECn8+AAQkAAkJXR02AwBdAgAkAAkJBRo2AwBdAgABAAkJWxjcRADGAQAjAAcJJx0/CwCbAQAAAA==.Skiadrum:BAACLgAFFH8FAAIiAAMJgQGeNABmAAAiAAMJgQGeNABmAAAuAAQKf0IAAxkACQl+FI4mAN0BABkACAnXEo4mAN0BACIABAlBCRdiAIgAAAAA.Skoliro:BAAALgAECgcJCgAAAA==.Skorch:BAAALgADCgkJEAABLgAFFAQJCQAcAPwKAA==.',
Sm='Smotts:BAAALgAECgcJDQAAAA==.Smòtts:BAABLgAECn8UAAIaAAgJYRzLCwAVAgAaAAgJYRzLCwAVAgAAAA==.',
Sn='Snizard:BAABLgAECn8dAAICAAcJhxwyNQD+AQACAAcJhxwyNQD+AQAAAA==.Snuggiepoo:BAABLgAECn8kAAMDAAkJsh7bCgC3AgADAAgJ5CDbCgC3AgAEAAYJgRVfVgCvAAAAAA==.',
So='Songbirds:BAAALgADCgcJDQAAAA==.Sonichoos:BAAALgAECgUJDAAAAA==.Sophiel:BAABLgAECn8hAAIWAAgJ+RquJQAsAgAWAAgJ+RquJQAsAgAAAA==.Sosthenna:BAAALgADCgkJCQAAAA==.Soulbark:BAAALgAECgMJAwABLgAECgQJBAAHAAAAAQ==.Souleater:BAAALgADCgMJAwAAAA==.Soulforged:BAAALgADCgcJCwABLgAECgQJBAAHAAAAAA==.Soulreaver:BAAALgAECgcJCAAAAA==.Soulweaver:BAAALgAECgQJBAAAAQ==.',
Sp='Sparrowhåwk:BAAALgADCgUJBgAAAA==.Spicymustard:BAAALgAECgEJAQAAAA==.Spongebill:BAAALgADCgEJAQAAAA==.Spàdes:BAABLgAECn8cAAMRAAcJxxpnLwCLAQARAAYJbhtnLwCLAQALAAMJbBLzQwCuAAAAAA==.',
St='Starel:BAAALgAECgQJBAAAAA==.Stellanoova:BAAALgAECgYJDgABLgAECggJFgAmAEoUAA==.Stevebushami:BAAALgAECgYJEAAAAA==.Stuwu:BAAALgADCgcJDAAAAA==.',
Su='Suffers:BAAALgAFFAEJAQAAAA==.Suou:BAAALgADCgcJCQABLgAECgEJAgAHAAAAAA==.Surj:BAABLgAECn8cAAMeAAYJ2Rg+GwBTAQAeAAYJ2Rg+GwBTAQARAAQJeAsbZAC/AAAAAA==.',
Sv='Svmii:BAAALgADCgcJCgAAAA==.',
Ta='Taazdingo:BAAALgAECgUJCQAAAA==.Taikuri:BAAALgAECgcJDgABLgAECgYJFQABAEkYAA==.Taliela:BAAALgAECgQJBAAAAA==.Tanddralndra:BAAALgAECgUJBwAAAA==.Tanklilbaby:BAAALgAECgEJAQAAAA==.Tannia:BAAALgADCgYJBwAAAA==.Taxgirl:BAACLgAFFH8WAAMGAAUJiRxIRgBXAQAGAAUJiRxIRgBXAQAUAAEJsQOcJgA3AAAuAAQKfyAAAgYACAnOJGISAA0DAAYACAnOJGISAA0DAAAA.',
Te='Teabear:BAAALgAFFAMJBAAAAA==.Teralion:BAAALgAECgMJBgAAAA==.',
Th='Thaeldrik:BAAALgADCgcJCgAAAA==.Thaldreaux:BAAALgAECgMJBAAAAA==.Thefirst:BAAALgAECgMJBQAAAA==.Theleon:BAABLgAECn8dAAIVAAgJQg9BLQBiAQAVAAgJQg9BLQBiAQAAAA==.Thordrin:BAABLgAECn8sAAIJAAcJfiT1CgDTAgAJAAcJfiT1CgDTAgAAAA==.Thorlan:BAAALgADCgYJCAAAAA==.Thrasherzs:BAAALgAECgUJDQAAAA==.Thryen:BAAALgAECgQJBQAAAA==.Thunder:BAAALgADCgQJBAABLgAECgcJCgAHAAAAAA==.Thundergrasp:BAACLgAFFH8HAAInAAYJ+wp8BQBYAQAnAAYJ+wp8BQBYAQAuAAQKfxsAAicABwkNG88OALgBACcABwkNG88OALgBAAAA.',
Ti='Tianhe:BAAALgAECgMJAwAAAA==.Tiarisaril:BAAALgAECgYJBgAAAA==.Tigercita:BAAALgAECgMJAgAAAA==.Tippah:BAAALgAECgEJAwAAAA==.Tippers:BAAALgAECgEJAQAAAA==.',
To='Toe:BAAALgAFFAIJBAAAAA==.Tonkah:BAAALgAECgUJBQABLgAECggJEQAHAAAAAA==.Toobestake:BAAALgAFFAEJAQABLgAFFAUJFQACAIkjAA==.Topenga:BAACLgAFFH8VAAICAAQJMRmtKgBOAQACAAQJMRmtKgBOAQAuAAQKf0sAAgIACQnNH2kSAKQCAAIACQnNH2kSAKQCAAAA.Tosem:BAAALgAECgcJBwAAAA==.Touchypope:BAAALgADCgYJCwAAAA==.',
Tr='Treeage:BAAALgADCgMJAwAAAA==.Triggerd:BAAALgADCgEJAQAAAA==.Trunks:BAAALgADCgQJBAAAAA==.Trylok:BAAALgADCgEJAQAAAA==.Trüst:BAAALgAECggJDgAAAA==.',
Tw='Twicelife:BAABLgAECn8ZAAIOAAgJ0R1mFQCUAgAOAAgJ0R1mFQCUAgABLgAFFAQJFQALABYVAA==.',
Ty='Tyrygosa:BAAALgAECgUJBQABLgAFFAQJEAABAMEWAA==.',
['Tå']='Tånk:BAAALgAECggJEwAAAA==.',
Un='Uneedsummilk:BAAALgADCgcJBwAAAA==.Unholyapollo:BAAALgADCgYJCwAAAA==.',
Ur='Urthstripe:BAABLgAECn8mAAQKAAgJwxd7IAA6AgAKAAgJwxd7IAA6AgAVAAIJMgPihwAxAAAgAAEJiwVjXAAaAAAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCAAGAIkhAA==.Vain:BAAALgAECgEJAgAAAA==.Valle:BAAALgAECgIJAwABLgAFFAcJGgAEALAaAA==.Valoria:BAAALgAECgMJBwABLgAFFAcJGgAEALAaAA==.',
Ve='Veil:BAAALgAECgIJBwABLgAFFAcJGgAEALAaAA==.Velarenea:BAAALgADCgEJAQAAAA==.Velgabrine:BAAALgAECgYJDAABLgAFFAQJEAANADsjAA==.Veraani:BAAALgAECgYJBgAAAA==.Verra:BAAALgADCgYJBgAAAA==.',
Vi='Vil:BAAALgADCgcJBgAAAA==.Virlan:BAAALgADCgQJBAAAAA==.Viserion:BAABLgAECn8WAAMmAAgJShSVOgA1AQAmAAcJZBKVOgA1AQAdAAYJ2AykHwDxAAAAAA==.',
Vo='Voidchaosfan:BAAALgAECgYJDAAAAA==.',
Vu='Vue:BAACLgAFFH8SAAIJAAQJQxOeIwD5AAAJAAQJQxOeIwD5AAAuAAQKf0YAAgkACQkkGzYfAB8CAAkACQkkGzYfAB8CAAAA.Vuldin:BAAALgAECgEJAgAAAA==.',
['Vö']='Völdemört:BAAALgADCgIJAgAAAA==.',
Wa='Wakasham:BAACLgAFFH8UAAInAAYJayByAgCtAQAnAAYJayByAgCtAQAuAAQKfzEAAicACQk9Jp4BAFMDACcACQk9Jp4BAFMDAAAA.Wardemon:BAAALgADCgIJAgAAAA==.Wardrake:BAAALgAECgEJAQAAAA==.',
We='Wehonoryou:BAABLgAECn8YAAIIAAYJ9CHYGAAAAgAIAAYJ9CHYGAAAAgAAAA==.Wetard:BAAALgADCgIJAgAAAA==.',
Wi='Willbyers:BAAALgAECgEJAQAAAA==.Winterloom:BAAALgAECgYJBgAAAA==.',
Wo='Wolfpacked:BAACLgAFFH8GAAIOAAIJHBwBUwCaAAAOAAIJHBwBUwCaAAAuAAQKfygAAg4ACQlBIGQIACEDAA4ACQlBIGQIACEDAAAA.Wolfzbåin:BAAALgAECgQJBAAAAA==.',
Wr='Wroot:BAAALgADCgYJCQAAAA==.Wrotten:BAABLgAECn8WAAIjAAgJ6RcWCgCxAQAjAAgJ6RcWCgCxAQAAAA==.',
Wu='Wunderlust:BAACLgAFFH8PAAIcAAQJhxfgSQBIAQAcAAQJhxfgSQBIAQAuAAQKf0QAAhwACQmFISYcAAYDABwACQmFISYcAAYDAAAA.',
Xe='Xemon:BAAALgAECgIJAgAAAA==.',
Xi='Xilyana:BAAALgAECgQJBAAAAA==.',
Xm='Xmatick:BAAALgAECgcJCQAAAA==.',
Xs='Xscrats:BAAALgAECgkJCAAAAA==.',
Ye='Yellowshaman:BAACLgAFFH8jAAIfAAYJLx3XDQCtAQAfAAYJLx3XDQCtAQAuAAQKfzIAAh8ACQk3IkQMANcCAB8ACQk3IkQMANcCAAAA.Yerac:BAAALgAECgEJAQAAAA==.',
Yu='Yukikage:BAAALgAECgMJAwAAAA==.Yutdaeng:BAAALgAECgMJBAAAAA==.',
Yv='Yvent:BAAALgADCgIJAgAAAA==.Yvraine:BAAALgAECgYJDgAAAA==.',
Za='Zakcarii:BAAALgADCgMJCAAAAA==.Zalicy:BAAALgAECgYJEwAAAA==.Zalogar:BAAALgAECgcJCgAAAA==.Zapper:BAAALgAECgQJCwAAAA==.',
Zb='Zbarbb:BAAALgADCgUJBQAAAA==.',
Ze='Zealot:BAAALgAECgEJAQAAAA==.Zeeasyez:BAAALgAECgYJEwAAAA==.Zestul:BAAALgADCgEJAQAAAA==.',
Zh='Zhane:BAAALgADCgYJBwAAAA==.',
Zo='Zordon:BAAALgAECgYJEwAAAA==.',
Zs='Zslol:BAAALgAECgEJAQAAAA==.',
Zu='Zugg:BAAALgAECgMJBQABLgAFFAcJGgAEALAaAA==.Zuriznikov:BAAALgAECgEJAQABLgAECggJFgAmAEoUAA==.',
['Ån']='Ångie:BAAALgADCgMJAwAAAA==.',
['Øf']='Øffspeck:BAABLgAECn8gAAQBAAkJVhweLgBVAgABAAgJwxgeLgBVAgAjAAcJICFgCwCZAQAkAAMJzh7MMAD3AAAAAA==.',
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
