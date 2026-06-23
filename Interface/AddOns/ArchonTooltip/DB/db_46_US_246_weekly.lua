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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Priest-Discipline','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','DemonHunter-Havoc','Paladin-Holy','Druid-Restoration','Unknown-Unknown','Warrior-Arms','Paladin-Retribution','Shaman-Restoration','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','Paladin-Protection','DeathKnight-Blood','DeathKnight-Frost','Druid-Balance','DemonHunter-Devourer','Rogue-Assassination','Mage-Arcane','Monk-Mistweaver','Druid-Guardian','Monk-Brewmaster','Mage-Frost','Warrior-Protection','Rogue-Subtlety','Shaman-Elemental','Druid-Feral','Mage-Fire','Monk-Windwalker','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Evoker-Augmentation','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=46,date='2026-06-21',data={Aa='Aaron:BAAALgAECgcJBwABLgAECgkJIQABAFYcAA==.Aaronfreeze:BAACLgAFFH8JAAICAAMJehruVgD5AAACAAMJehruVgD5AAAuAAQKfzIAAgIACQn1HuUfAGgCAAIACQn1HuUfAGgCAAAA.',
Ab='Abrakazaam:BAAALgADCgEJAQAAAA==.',
Ad='Adrios:BAACLgAFFH8FAAIDAAIJmRQ5OwCTAAADAAIJmRQ5OwCTAAAuAAQKfyYABAMACQnQFvIZAAACAAMACAn9F/IZAAACAAQABwlRB9lTAMMAAAUAAwnKCCRpAIgAAAAA.',
Ae='Aetherion:BAAALgAECgMJBAAAAA==.',
Ai='Airorca:BAAALgAECgUJBQAAAA==.',
Aj='Ajaxz:BAABLgAECn8VAAIGAAkJ+RLTYADRAQAGAAkJ+RLTYADRAQAAAA==.',
Ak='Akaßoss:BAAALgADCgEJAQABLgAECgYJIgAEAIsRAA==.',
Al='Albedô:BAAALgAFFAIJAwABLgAFFAIJBwAHAAohAA==.Aliren:BAAALgAECgYJCgAAAA==.Allmaick:BAAALgADCggJCAAAAA==.Alucard:BAABLgAFFH8TAAIIAAUJcw19AgAWAQAIAAUJcw19AgAWAQAAAA==.Alystrasza:BAABLgAECn8dAAIJAAYJvhbjRAB9AQAJAAYJvhbjRAB9AQAAAA==.',
Am='Amorlandian:BAAALgAECgMJAwAAAA==.',
An='Antimovsky:BAAALgAECgcJEwAAAA==.',
Ap='Aphroditê:BAAALgAECgMJBAABLgAECgcJCAAKAAAAAA==.',
Aq='Aqours:BAAALgADCgcJBwABLgAECgEJAgAKAAAAAA==.',
Ar='Arcan:BAAALgAECgIJAgAAAA==.',
As='Astellia:BAAALgADCgEJAQAAAA==.',
Au='Augustine:BAAALgAECgEJAQAAAA==.Aullyura:BAAALgADCgcJBwAAAA==.Auroras:BAACLgAFFH8IAAMFAAMJUwbcKAB/AAAFAAMJUwbcKAB/AAAEAAEJmAEwQgAvAAAuAAQKfxcAAgUABwmEE5k0AGwBAAUABwmEE5k0AGwBAAAA.',
Av='Aviaria:BAAALgAECgQJBAAAAA==.Avìendha:BAAALgADCgQJBAAAAA==.',
Aw='Awsmpossum:BAAALgAECgEJAQAAAA==.',
['Aì']='Aìnzooalgown:BAABLgAFFH8SAAIGAAQJESGEPQB9AQAGAAQJESGEPQB9AQABLgAFFAIJBwAHAAohAA==.',
Ba='Babakubwa:BAAALgAECgMJAwAAAA==.Babylonfive:BAAALgAECgcJDQAAAA==.Balhair:BAAALgADCgYJBgAAAA==.Banger:BAAALgADCgEJAQAAAA==.Banish:BAAALgAECgMJAgABLgAECgcJCgAKAAAAAA==.Barragdan:BAAALgADCgEJAQAAAA==.Basandra:BAAALgAECgEJAQAAAA==.Basicc:BAAALgADCgUJBQAAAA==.',
Be='Beachbumm:BAAALgADCgEJAQAAAA==.Beastreminna:BAAALgADCgEJAQAAAA==.Belleta:BAAALgAECggJEQAAAA==.Berserk:BAEBLgAECn8iAAILAAYJ3SP6DgD+AQALAAYJ3SP6DgD+AQAAAA==.Bertringer:BAAALgAECgEJAgABLgAECgYJBgAKAAAAAA==.',
Bi='Bigmack:BAAALgAECgYJCwABLgAFFAcJHAAMAHoYAA==.Bigpoppa:BAAALgAECgEJAgABLgAECgYJBgAKAAAAAA==.Bigwilli:BAABLgAECn8XAAINAAkJHRK8OQDIAQANAAkJHRK8OQDIAQAAAA==.Bingßong:BAAALgADCgYJEQAAAA==.Biscuit:BAACLgAFFH8QAAQOAAYJhBobHADOAAACAAQJvCK7WAD0AAAOAAMJ7BEbHADOAAAPAAIJ+xHoKwCDAAAuAAQKfyIABA4ACAmPIycPAMgCAA4ACAl9HScPAMgCAA8AAwnZH+05AO0AAAIABAk+HpusAOoAAAAA.Bisha:BAABLgAECn9FAAMQAAkJEiHmDQDmAgAQAAkJ9CDmDQDmAgALAAYJcBgnMgD/AAAAAA==.Bizcocho:BAAALgAECgcJDAAAAA==.',
Bl='Black:BAAALgADCgEJAQAAAA==.Bloodsimple:BAAALgADCgUJBQAAAA==.Blákers:BAABLgAFFH8OAAIRAAQJuSQHAgCvAQARAAQJuSQHAgCvAQAAAA==.',
Bo='Boic:BAAALgADCgQJBAAAAA==.Bonesofdoom:BAACLgAFFH8HAAISAAMJ1w0iLQCUAAASAAMJ1w0iLQCUAAAuAAQKfyMAAxIACQkHGU8ZAJYBABIACAmJG08ZAJYBAAYAAgkYBs8/AV8AAAAA.Boogsta:BAACLgAFFH8QAAMTAAMJmgqCGADHAAATAAMJmgqCGADHAAAGAAEJ7AIuJQExAAAuAAQKfzYAAhMACQlxFWgHACICABMACQlxFWgHACICAAAA.Boomkingobrr:BAACLgAFFH8HAAIUAAMJ9wj3NQCnAAAUAAMJ9wj3NQCnAAAuAAQKfxsAAhQACQkOHEQLAOECABQACQkOHEQLAOECAAAA.Boops:BAAALgAECgEJAQAAAA==.Bootysweatt:BAABLgAECn8aAAIHAAYJNhtqJACaAQAHAAYJNhtqJACaAQAAAA==.Boss:BAAALgADCgEJAQABLgAECgYJIgAEAIsRAA==.',
Br='Brewnz:BAAALgAECgUJBgAAAA==.Brucewee:BAAALgAECgQJCgAAAA==.',
Bu='Buckits:BAAALgAECgcJEgAAAA==.Bunsey:BAAALgADCgIJAgAAAA==.Burnsx:BAAALgAECgUJCgABLgAFFAgJGQAVAFgeAA==.Bussyman:BAAALgAECgYJEQABLgAFFAMJCQAJACIWAA==.',
Bw='Bwoar:BAAALgAECgQJBgAAAA==.',
['Bø']='Bøw:BAAALgAECgMJAwAAAA==.',
['Bü']='Bübble:BAAALgADCgEJAQAAAA==.',
Ca='Captnmurloc:BAAALgAECgkJEgAAAA==.Capwackychan:BAAALgAECgEJAQAAAA==.Carl:BAAALgAECgEJAgABLgAFFAgJDwAWAMwbAA==.Carrach:BAAALgAECgIJBQAAAA==.Caveyodeler:BAAALgAECgQJCgAAAA==.',
Ce='Cedar:BAAALgAECgQJCwAAAA==.',
Ch='Cherga:BAAALgADCgYJBgAAAA==.Chinegga:BAAALgADCgYJBgAAAA==.Chitose:BAAALgADCgUJBQABLgAECgEJAgAKAAAAAA==.Chrapsasspee:BAAALgADCgcJGQAAAA==.Chrinn:BAAALgADCgMJAwAAAA==.',
Ci='Cindele:BAAALgADCgMJAwAAAA==.Cirvix:BAAALgAECgYJDAAAAA==.Cirxe:BAABLgAECn8iAAIXAAkJMg6ABACtAQAXAAkJMg6ABACtAQAAAA==.',
Cl='Clampire:BAAALgAECgQJBAAAAA==.Cliint:BAAALgAECgcJCwAAAA==.Cloúnt:BAAALgAECgEJAwABLgAFFAMJBwAUAPcIAA==.',
Co='Commotionn:BAAALgAECgQJBAAAAA==.Coms:BAAALgADCgIJAgAAAA==.Cooz:BAAALgAECgYJDwAAAA==.Corybooker:BAAALgAECgcJBAAAAA==.Cowdux:BAAALgAFFAEJAQAAAA==.Cowmoorem:BAAALgADCgEJAQAAAA==.',
Cr='Creamdragon:BAAALgADCgcJDQABLgAECggJOwAYAFEeAA==.',
Cu='Curuni:BAAALgADCgcJDAAAAA==.',
Cz='Czechhunter:BAAALgADCgUJBQAAAA==.',
['Cå']='Cåleb:BAAALgAECgEJAQAAAA==.',
['Cø']='Cønstance:BAABLgAECn8VAAIZAAcJvREWJgAjAQAZAAcJvREWJgAjAQAAAA==.',
Da='Daddyphat:BAABLgAECn8rAAIaAAgJrCS6BgDOAgAaAAgJrCS6BgDOAgAAAA==.Daddý:BAAALgAECgEJAQAAAA==.Dalight:BAABLgAECn8XAAIIAAYJKiYPDwCdAgAIAAYJKiYPDwCdAgAAAA==.Dankins:BAACLgAFFH8dAAINAAgJ2SKxAQDgAgANAAgJ2SKxAQDgAgAuAAQKfxYAAg0ACAkGHfYZAEcCAA0ACAkGHfYZAEcCAAAA.',
De='Deathmager:BAABLgAECn89AAIbAAkJjBJ6SQD/AQAbAAkJjBJ6SQD/AQAAAA==.Deathtraper:BAAALgAECgcJDQAAAA==.Debur:BAAALgADCgEJAQAAAA==.Deltaka:BAAALgAECgEJAQAAAA==.Demonfella:BAAALgADCgMJAwAAAA==.Demonicpeach:BAABLgAECn8YAAIBAAcJwwv/rADpAAABAAcJwwv/rADpAAAAAA==.Denaian:BAAALgADCgYJBgAAAA==.Dethsent:BAAALgAECggJEQAAAA==.Dette:BAABLgAECn8dAAICAAkJvBUuLgAkAgACAAkJvBUuLgAkAgAAAA==.Devilchaser:BAAALgAECggJDgAAAA==.Devourer:BAABLgAECn8VAAIVAAcJjg+mbQBaAQAVAAcJjg+mbQBaAQAAAA==.',
Dh='Dhtank:BAAALgAECgEJAQAAAA==.',
Di='Diaval:BAAALgADCgIJAgABLgAECgkJLAABAFsTAA==.Dinosforlife:BAAALgAECgYJDAAAAA==.',
Dk='Dkboss:BAAALgAECgIJAgABLgAECgYJIgAEAIsRAA==.',
Do='Donzilly:BAAALgAECgYJDgAAAA==.Doreme:BAAALgADCgIJAgAAAA==.Dorgrim:BAAALgAECgUJDAAAAA==.Doyuevendps:BAAALgADCgEJAQAAAA==.Doyueventry:BAAALgADCgYJBgAAAA==.',
Dr='Drafted:BAAALgAECgcJEAAAAA==.Drax:BAAALgAECgMJAwAAAA==.Drewmcmoo:BAAALgADCgcJBgAAAA==.Drsath:BAAALgADCgcJBwAAAA==.Drunkorca:BAAALgADCgUJBQAAAA==.',
Ea='Earnar:BAAALgADCgYJDAAAAA==.',
Ed='Edarix:BAAALgADCggJDAABLgAECggJQAAMAHkYAA==.',
Ei='Eiliyah:BAABLgAECn8yAAMIAAgJehz0FgBaAgAIAAgJehz0FgBaAgAMAAIJHwIaWgElAAAAAA==.',
Ek='Ekmek:BAAALgAECgEJAQAAAA==.',
El='Elabernathy:BAABLgAECn80AAICAAkJrhiFHQB0AgACAAkJrhiFHQB0AgAAAA==.Elenay:BAABLgAECn8UAAIJAAgJqR6TIwAuAgAJAAgJqR6TIwAuAgAAAA==.Elesia:BAAALgAECgkJEgAAAA==.Elfussy:BAAALgAECgEJAQAAAA==.Elgoku:BAAALgAECgQJCgABLgAECgUJDAAKAAAAAA==.Eliarssande:BAAALgAECgEJAQAAAA==.Elinay:BAAALgAECgQJBAABLgAECggJFAAJAKkeAA==.Elixia:BAABLgAECn8bAAIHAAgJDA29JgBEAQAHAAgJDA29JgBEAQAAAA==.Elpatron:BAABLgAFFH8LAAIJAAQJQxKPAwD2AAAJAAQJQxKPAwD2AAAAAA==.Elylanea:BAAALgAECgUJDgAAAA==.',
Em='Emulsdeath:BAABLgAECn8UAAMSAAgJKCFPEwDcAQASAAcJLB5PEwDcAQAGAAYJ8iCEawCOAQABLgAFFAQJEAAMADsjAA==.Emulsifier:BAACLgAFFH8QAAIMAAQJOyMeHQCUAQAMAAQJOyMeHQCUAQAuAAQKfzAAAgwACAmFJgENAPwCAAwACAmFJgENAPwCAAAA.',
En='Ennoa:BAAALgAECgEJAQAAAA==.',
Er='Ergen:BAACLgAFFH8bAAIPAAUJthpXEQA8AQAPAAUJthpXEQA8AQAuAAQKfyoAAg8ACAlvIaUGAJcCAA8ACAlvIaUGAJcCAAAA.',
Eu='Eusexua:BAAALgAECgQJBQABLgAECgcJCgAKAAAAAA==.',
Ex='Expiatory:BAAALgAECgYJCQAAAA==.',
Fa='Faielle:BAAALgAECgEJAQAAAA==.Fairbear:BAABLgAECn8dAAQQAAYJ+ByGOQBgAQAQAAYJ+ByGOQBgAQALAAEJZA5tPgA7AAAcAAEJ6Qc2XgAbAAAAAA==.Faustt:BAAALgAECgUJBwAAAA==.',
Fi='Filthyfabio:BAAALgADCgcJEQAAAA==.Finester:BAACLgAFFH8MAAIdAAQJdh8rEgB9AQAdAAQJdh8rEgB9AQAuAAQKfxgAAh0ACQmCIVMAAGkCAB0ACQmCIVMAAGkCAAAA.Fireburr:BAAALgAECgMJAwAAAA==.',
Fl='Flatline:BAAALgAECgcJEgAAAA==.Fløw:BAAALgAECgMJCgAAAA==.',
Fr='Fragglerott:BAABLgAECn8bAAMNAAgJGBN4gwDYAAANAAQJUhJ4gwDYAAAeAAgJ1AqZZgCyAAAAAA==.Frati:BAAALgAECgEJAQAAAA==.Friedchickn:BAAALgAECgQJCAAAAA==.Frostboss:BAAALgADCgEJAQABLgAECgYJIgAEAIsRAA==.Frostnips:BAAALgAECgQJBAAAAA==.Frosttrinity:BAAALgADCgUJBAAAAA==.',
Fu='Funslinger:BAAALgAECgQJDAAAAA==.',
Ga='Gaffz:BAAALgAECgEJAgAAAA==.Galannar:BAAALgAECggJDQAAAA==.Galvrax:BAAALgAECgUJCgAAAA==.Gast:BAACLgAFFH8PAAIQAAUJZB3lGQBKAQAQAAUJZB3lGQBKAQAuAAQKfzYAAxAACQlRIN0JAMUCABAACQlRIN0JAMUCABwABAmpFt41AKAAAAAA.',
Ge='Gearwick:BAAALgADCgYJBwABLgAECgcJJgAIAFAhAA==.',
Gh='Ghstfacekila:BAAALgADCgEJAQAAAA==.',
Go='Gorska:BAABLgAECn84AAIeAAkJfB0oEAByAgAeAAkJfB0oEAByAgAAAA==.',
Gr='Grawm:BAABLgAECn8iAAMOAAkJqiKzHgAxAgAOAAgJSRWzHgAxAgACAAkJPiBuTwC0AQAAAA==.Greedory:BAAALgADCgIJAgAAAA==.Groot:BAAALgADCgUJBgAAAA==.Gruetss:BAAALgAECgQJBAAAAA==.',
Gu='Guilty:BAAALgAECgEJAQAAAA==.',
['Gä']='Gämbit:BAAALgADCgEJAQAAAA==.',
Ha='Hailbringer:BAAALgAECgcJDgAAAA==.Hakoona:BAABLgAECn8yAAIaAAkJFxrFEQApAgAaAAkJFxrFEQApAgAAAA==.Hanginaround:BAAALgAECgEJAQAAAA==.Hangman:BAACLgAFFH8bAAIIAAQJ8SVZEQCrAQAIAAQJ8SVZEQCrAQAuAAQKfyEAAwgACQmLJBECAJADAAgACQmLJBECAJADAAwABAklDRwgAZMAAAEuAAUUAwkJAAkAIhYA.Hanni:BAABLgAECn8dAAIOAAgJUhyUCwCuAQAOAAgJUhyUCwCuAQAAAA==.Haveaburitto:BAACLgAFFH8NAAIbAAQJWBxIXAAmAQAbAAQJWBxIXAAmAQAuAAQKfygAAhsACAk0JXkMAGEDABsACAk0JXkMAGEDAAAA.Hawktoetem:BAAALgAECgUJCAABLgAECgYJHQAQAPgcAA==.Hawktoouh:BAAALgAECgcJDQAAAA==.',
He='Healmemaybe:BAABLgAECn8bAAIJAAYJQiP/IgAxAgAJAAYJQiP/IgAxAgAAAA==.Healthyadult:BAAALgAECgMJBQAAAA==.Hellshand:BAAALgAECgYJDAAAAA==.Heracles:BAAALgAECgQJBAAAAA==.Heretic:BAAALgAECgEJAQAAAA==.',
Hi='Hickscale:BAAALgADCgMJAwAAAA==.',
Ho='Holycøw:BAAALgADCgMJAwAAAA==.Holydefender:BAAALgADCgcJDQAAAA==.Holyhands:BAAALgADCgYJBgAAAA==.Holyholyholy:BAAALgAECggJEgAAAA==.Honest:BAAALgADCgMJAwAAAA==.',
Hu='Hunniee:BAAALgAECgEJAQAAAA==.Huntrix:BAAALgADCgcJEgAAAA==.',
Ic='Icedatt:BAABLgAECn8VAAMGAAUJ8QIlKAF5AAAGAAUJ7AIlKAF5AAASAAUJcwGPVABIAAAAAA==.Icefire:BAAALgADCgUJBAAAAA==.',
Ik='Ikur:BAACLgAFFH8PAAIIAAQJrxtfHQAyAQAIAAQJrxtfHQAyAQAuAAQKfzsAAggACQmTHpMHABMDAAgACQmTHpMHABMDAAAA.',
Il='Ilinia:BAAALgAECgYJCAABLgAECgUJEgAKAAAAAA==.Illhealutoo:BAAALgAFFAEJAQAAAA==.',
Im='Imsteve:BAAALgAECgUJBQAAAA==.',
In='Infoxicated:BAAALgADCgcJCAABLgAECgkJJAADALIeAA==.Insîght:BAAALgAECgQJCAAAAA==.',
Ip='Ipopkidneys:BAACLgAFFH8VAAMdAAcJ1SFhDQC8AQAdAAYJlSFhDQC8AQAWAAMJjB0kBwDxAAAuAAQKfycAAx0ACQnhJYQMANACAB0ACQnhJYQMANACABYAAQn1IyIfAGUAAAAA.',
Ir='Iroi:BAAALgAECgIJBQAAAA==.',
Is='Iskur:BAABLgAECn8mAAMNAAgJ4BgZIwA8AgANAAgJ4BgZIwA8AgAeAAMJMQ22dgCJAAABLgAFFAQJDwAIAK8bAA==.Isuck:BAAALgAFFAIJAgAAAA==.Isurr:BAABLgAECn8iAAIYAAcJnhK+OQCLAQAYAAcJnhK+OQCLAQABLgAFFAQJDwAIAK8bAA==.',
It='Itakecandle:BAAALgAECgUJBwABLgAECgUJDAAKAAAAAA==.',
Iv='Ivanapump:BAAALgAECgIJAgABLgAECgYJBgAKAAAAAA==.',
Ja='Jackkal:BAAALgAECggJCgAAAA==.Jadethecat:BAAALgADCgMJAwAAAA==.Jakbis:BAAALgADCgEJAQAAAA==.Jakychan:BAAALgAECgEJAQAAAA==.Jaldiar:BAAALgADCgcJBwABLgAECgYJBgAKAAAAAA==.Jametrok:BAAALgAECgEJAQAAAA==.Jazbek:BAAALgAECgQJDgAAAA==.Jazzonus:BAAALgAECgQJBAAAAA==.',
Je='Jefferey:BAAALgADCgMJAwAAAA==.Jennyanydots:BAAALgAECgMJBQABLgAFFAcJGgAEALAaAA==.Jeriçho:BAAALgADCgYJBgAAAA==.',
Jh='Jhonwick:BAAALgAECgIJAgAAAA==.',
Ji='Jippedo:BAAALgAECgYJAgABLgAECgcJBAAKAAAAAA==.Jiraîya:BAAALgAECgQJBQAAAA==.',
Jo='Jordak:BAABLgAECn8oAAIJAAkJBBwsDgDnAgAJAAkJBBwsDgDnAgAAAA==.Jorolee:BAAALgADCgEJAQAAAA==.',
Ka='Kaddiya:BAAALgAECgYJDQAAAA==.Kagonstrasza:BAAALgAECgQJBAAAAA==.Kallistos:BAABLgAECn8gAAINAAcJER3sLQD/AQANAAcJER3sLQD/AQAAAA==.Kariza:BAAALgAECgQJBgAAAA==.Karunik:BAAALgADCgYJBgABLgAECgcJCgAKAAAAAA==.Kasst:BAAALgAECgEJAQAAAA==.',
Ke='Kelenheller:BAAALgAECgUJDAAAAA==.Key:BAAALgAECgIJAgAAAA==.',
Kh='Khione:BAAALgADCgYJBgAAAA==.Khthonios:BAAALgAECgEJAQAAAA==.',
Ki='Kiba:BAAALgADCgIJAgABLgAECggJOwAYAFEeAA==.Kibblerina:BAAALgADCgcJBwAAAA==.Kiranam:BAABLgAECn8cAAQfAAgJrQ6dEQCTAQAfAAgJqQqdEQCTAQAZAAcJNQwxOADGAAAUAAIJWwfecQBZAAAAAA==.',
Kn='Knarth:BAABLgAECn9CAAIgAAkJ5x71AADZAgAgAAkJ5x71AADZAgAAAA==.Kníght:BAAALgAFFAMJAwAAAA==.',
Ko='Koisy:BAAALgAECgcJEAABLgAECggJFAAJAKkeAA==.Kole:BAAALgAECgEJAQAAAA==.Koopa:BAABLgAECn8rAAIQAAkJHyVcBQALAwAQAAkJHyVcBQALAwAAAA==.',
Kr='Krasul:BAACLgAFFH8WAAMNAAYJwRRRJQBWAQANAAYJwRRRJQBWAQAeAAIJ7QkPSQBsAAAuAAQKfx8AAw0ACAkXIecIAOgCAA0ACAkXIecIAOgCAB4ABgm/HPIxAJQBAAAA.Krenthok:BAABLgAECn8eAAIBAAgJiQe1iQAmAQABAAgJiQe1iQAmAQAAAA==.',
Ku='Kuraha:BAAALgAECgQJBAAAAA==.Kuruni:BAAALgAECgEJAQAAAA==.Kushar:BAAALgAECgQJBQABLgAECgkJGAAhAMkQAA==.',
Ky='Kyuketsuki:BAAALgAFFAIJAgAAAA==.',
La='Lachance:BAAALgADCgYJBgAAAA==.Large:BAAALgADCgYJBgAAAA==.Largemann:BAAALgAFFAIJAgABLgAFFAUJGAAGAIkcAA==.Lathspell:BAABLgAECn8yAAIbAAkJtiAPJgCDAgAbAAkJtiAPJgCDAgAAAA==.Lazyevoker:BAAALgADCgQJBAABLgAECgEJAQAKAAAAAA==.',
Le='Leahan:BAAALgAECgQJCgAAAA==.Leloo:BAAALgADCgYJCgABLgAECgIJAwAKAAAAAA==.',
Lh='Lhureciv:BAACLgAFFH8UAAMEAAQJERl7FQA5AQAEAAQJERl7FQA5AQADAAEJKRuWSQBFAAAuAAQKf0sAAwQACQnVI80GAB4DAAQACQnVI80GAB4DAAMABgn7HjAjAHoBAAAA.',
Li='Lightchaser:BAAALgADCgMJAgAAAA==.Lightfkyou:BAAALgADCgcJCgAAAA==.Lihvurce:BAABLgAECn8fAAMMAAgJWR1BMgA3AgAMAAgJWR1BMgA3AgAIAAQJpR0FSwBMAQABLgAFFAQJFAAEABEZAA==.Lillianna:BAACLgAFFH8HAAIdAAIJrBJ5MACkAAAdAAIJrBJ5MACkAAAuAAQKfzwAAh0ACAlqHYcAANcBAB0ACAlqHYcAANcBAAAA.Lingchi:BAAALgAECgQJBgAAAA==.',
Ll='Llew:BAAALgAECgQJBQAAAA==.',
Lo='Loenhart:BAAALgAECgEJAQAAAA==.Lolkurtone:BAAALgAECgIJAgAAAA==.',
Lu='Luciaan:BAAALgADCgkJGQAAAA==.Lucrative:BAAALgADCgcJDQAAAA==.Lug:BAAALgAECgEJAQAAAA==.Lulue:BAAALgADCgQJBAAAAA==.Luminari:BAAALgADCgUJBQAAAA==.Lunastorm:BAACLgAFFH8NAAIiAAQJLxPoGAAIAQAiAAQJLxPoGAAIAQAuAAQKfzgAAiIACQnQIooCAD8DACIACQnQIooCAD8DAAAA.Luponero:BAACLgAFFH8YAAMCAAUJiSPZHQCNAQACAAUJiSPZHQCNAQAOAAEJ5QapKgBGAAAuAAQKfyIAAw4ACAnnHuYQALUCAA4ACAl6HeYQALUCAAIAAwnNHxeXABIBAAAA.',
Ly='Lynney:BAAALgADCgYJBwAAAA==.',
Ma='Macmn:BAACLgAFFH8TAAIeAAUJzxwKEwCLAQAeAAUJzxwKEwCLAQAuAAQKfygAAh4ABwnAJGULAOICAB4ABwnAJGULAOICAAAA.Mageyouacake:BAAALgADCgMJAwAAAA==.Magicard:BAABLgAECn8fAAIbAAgJjg5HewCBAQAbAAgJjg5HewCBAQAAAA==.Makesfood:BAABLgAECn8qAAIbAAcJZBeSdADpAQAbAAcJZBeSdADpAQAAAA==.Mamaheals:BAABLgAECn8rAAIFAAkJSxpbFAAzAgAFAAkJSxpbFAAzAgAAAA==.Mandos:BAAALgAECgYJCAAAAA==.Mantistabogn:BAAALgAFFAEJAQAAAA==.Maor:BAABLgAECn8XAAIMAAgJlxcuUADxAQAMAAgJlxcuUADxAQAAAA==.March:BAAALgADCgEJAQAAAA==.Markeisha:BAAALgAECgQJCAABLgAECgYJDAAKAAAAAA==.',
Me='Mechz:BAAALgAECgYJBgABLgAFFAQJCQAbAPwKAA==.Mechzician:BAACLgAFFH8JAAIbAAQJ/Ao7dwDsAAAbAAQJ/Ao7dwDsAAAuAAQKfzgAAhsACAlwGXtZAC0CABsACAlwGXtZAC0CAAAA.Mechzlock:BAAALgADCgEJAQABLgAFFAQJCQAbAPwKAA==.Melinoe:BAAALgAECgEJAQAAAA==.Merlerk:BAAALgADCgYJBgABLgAFFAgJJwAFAKYVAA==.Merlini:BAABLgAECn8dAAMEAAgJWRYKJACpAQAEAAcJ0xgKJACpAQADAAUJTharPAAbAQAAAA==.Mets:BAAALgAECgYJCgABLgAECgYJGwABAGsdAA==.',
Mi='Microplastic:BAAALgAECgUJBQAAAA==.Micspanky:BAAALgAECggJEgAAAA==.Mistynight:BAAALgADCgIJAgAAAA==.Mithrandi:BAAALgAECgYJCQAAAA==.Mitzis:BAABLgAFFH8MAAICAAMJ8x84UgAFAQACAAMJ8x84UgAFAQAAAA==.',
Mo='Moltiy:BAAALgADCggJEQAAAA==.Moltten:BAAALgADCgcJEQAAAA==.Mornhathor:BAAALgAECggJDgABLgAECgYJCAAKAAAAAA==.',
Mu='Mufinblaster:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgADCgIJBgAAAA==.Musnicker:BAAALgAECgQJBwABLgAECgkJOAAOAIYWAA==.',
My='Myro:BAACLgAFFH8UAAMNAAQJ3B+TJwBJAQANAAQJ3B+TJwBJAQAeAAIJZRTLQgB/AAAuAAQKfxsAAg0ABwm/JsEHAPkCAA0ABwm/JsEHAPkCAAAA.',
['Mè']='Mètis:BAAALgAECgcJCAAAAA==.',
['Mø']='Møhax:BAAALgAECgYJBgAAAA==.',
Na='Nanis:BAAALgAECgYJBwABLgAFFAQJEgAUAB0kAA==.Narmer:BAAALgAECgIJAgAAAA==.',
Ne='Neel:BAAALgADCgQJBQAAAA==.Nervhoost:BAAALgADCgMJAwAAAA==.Neuropolis:BAAALgADCgcJFQAAAA==.Neuroscience:BAAALgADCgMJAwAAAA==.Neurotics:BAABLgAECn9GAAQjAAkJMCYJAAALAwAjAAkJqCUJAAALAwAkAAcJsSMLBABHAgABAAUJ5BoBuwDjAAAAAA==.Neò:BAABLgAECn8YAAMlAAYJvBC1EAD/AAAlAAYJXw61EAD/AAAmAAEJ/hQFkwA1AAAAAA==.',
Ni='Niesh:BAAALgAECgEJBwAAAA==.Nightrush:BAAALgADCgEJAQAAAA==.Nineoneone:BAABLgAECn9GAAMFAAkJWhdvAAAgAgAFAAkJWhdvAAAgAgADAAQJjgPqRQCLAAAAAA==.',
No='Nobledecay:BAAALgAECgQJBQAAAA==.Nocturne:BAAALgAECgEJAwAAAA==.',
Nu='Nubbletcake:BAAALgADCgEJAQABLgAECgkJJAADALIeAA==.Nula:BAAALgAECgMJBQABLgAFFAcJGgAEALAaAA==.',
Ny='Nylveth:BAACLgAFFH8QAAIEAAUJzw9BHQAGAQAEAAUJzw9BHQAGAQAuAAQKfyoAAgQACQkAHXQQAFgCAAQACQkAHXQQAFgCAAEuAAUUBwkIACcAmgsA.',
Oa='Oathatone:BAAALgAECgUJBgAAAA==.',
Oc='Ocra:BAABLgAECn8gAAInAAkJ9g5+DgDJAQAnAAkJ9g5+DgDJAQABLgAFFAQJFQACADEZAA==.',
Of='Offspeck:BAAALgAECgIJAgABLgAECgkJIQABAFYcAA==.',
Ou='Outtkast:BAAALgAECgIJAgAAAA==.Outtkastt:BAAALgAECgcJCQAAAA==.Ouutkast:BAAALgAECgIJAwAAAA==.',
Oz='Ozwald:BAABLgAECn81AAIPAAkJchyBEAAqAgAPAAkJchyBEAAqAgAAAA==.',
Pa='Pallyangel:BAAALgADCgcJDwAAAA==.Pandemul:BAAALgAECgMJAwABLgAFFAQJEAAMADsjAA==.Patrio:BAACLgAFFH8IAAIiAAMJGg23IQCXAAAiAAMJGg23IQCXAAAuAAQKfywAAiIACQllGfYHAHMCACIACQllGfYHAHMCAAEuAAUUBAkLAAkAQxIA.Pawkclaw:BAAALgAECgYJBgAAAA==.',
Pe='Peaceonea:BAABLgAECn8bAAIVAAkJrgQWnQDoAAAVAAkJrgQWnQDoAAAAAA==.Peachaid:BAECLgAFFH8cAAMDAAgJ9Rd7CQCNAgADAAgJ9Rd7CQCNAgAFAAEJRQglOgAtAAAuAAQKfzAAAwMACQlVImoFADIDAAMACQlVImoFADIDAAUABgkYHSglAMABAAAA.Peatri:BAAALgAECgkJCwAAAA==.Peetree:BAABLgAFFH8KAAINAAQJOBlJLwAlAQANAAQJOBlJLwAlAQAAAA==.Pekin:BAAALgAECgEJAQAAAA==.',
Ph='Phosphorus:BAACLgAFFH8VAAMLAAQJFhUvGwAQAQALAAQJihMvGwAQAQAcAAIJjxTYIwB7AAAuAAQKf1kAAwsACQnmIEcFALcCAAsACQnHHkcFALcCABwABgkqHIkYAHoBAAAA.',
Pl='Plagüë:BAACLgAFFH8QAAMSAAQJzRxNKQCsAAAGAAMJpCC6eAASAQASAAMJ3RBNKQCsAAAuAAQKf00AAwYACQmjJbYQAOcCAAYACQmjJbYQAOcCABIABQmbDz85AK4AAAAA.Pleistarchus:BAAALgAECgYJCQAAAA==.',
Po='Poic:BAAALgADCgEJAQAAAA==.Polo:BAAALgADCgEJAQAAAA==.Poofighter:BAAALgAECgMJBwABLgAFFAIJBwAHAAohAA==.Poonan:BAAALgAECgYJBgAAAA==.',
Pp='Ppgangandlaw:BAAALgADCgEJAQAAAA==.',
Pr='Precious:BAABLgAECn8lAAIYAAgJNxazIwADAgAYAAgJNxazIwADAgAAAA==.Primalistic:BAAALgADCgUJBQABLgAFFAQJCQAbAPwKAA==.Primàl:BAABLgAECn8sAAIJAAYJBRv2NADUAQAJAAYJBRv2NADUAQAAAA==.Prowar:BAAALgADCgEJAQAAAA==.',
Pu='Punchinbag:BAAALgADCgYJBgAAAA==.Purifieds:BAAALgADCgEJAQAAAA==.',
Qs='Qsrqasda:BAABLgAECn8VAAISAAYJ4QXkPwCPAAASAAYJ4QXkPwCPAAAAAA==.',
Qt='Qtmenopaws:BAAALgAECgQJAwAAAA==.Qtptt:BAACLgAFFH8XAAIBAAMJKyNJHQAPAQABAAMJKyNJHQAPAQAuAAQKf0AAAgEACQmMI4gJAAYDAAEACQmMI4gJAAYDAAAA.',
Ra='Ragedeath:BAABLgAFFH8JAAISAAMJuA+3LACWAAASAAMJuA+3LACWAAABLgAFFAQJBAAKAAAAAA==.Ragedh:BAAALgAECgIJAgABLgAFFAQJBAAKAAAAAA==.Ragemonk:BAAALgADCgQJBAABLgAFFAQJBAAKAAAAAA==.Rageshaman:BAAALgAFFAQJBAAAAA==.Rasmong:BAABLgAECn8YAAIhAAkJyRAIHwC1AQAhAAkJyRAIHwC1AQAAAA==.Ravinsinda:BAAALgAECgYJBgAAAA==.Ravinursula:BAAALgAECgYJDwAAAA==.Rawrsaur:BAAALgAECgcJDQAAAA==.',
Re='Really:BAAALgADCgYJBgABLgAECgEJAQAKAAAAAA==.Reallyhpal:BAAALgAECgEJAQAAAA==.Redder:BAAALgAECgEJAQAAAA==.Remin:BAAALgADCgkJEQAAAA==.Retaliator:BAABLgAECn9AAAMMAAgJeRgmAwBOAQAMAAgJeRgmAwBOAQARAAMJuAwPOQB6AAAAAA==.Reuuín:BAAALgAECggJCwABLgAECggJGQAdABwZAA==.Revan:BAAALgAECgYJBwAAAA==.',
Rh='Rhýs:BAAALgAECgYJBgAAAA==.',
Ri='Rih:BAAALgADCgMJBQAAAA==.Ripits:BAAALgADCgcJCAABLgAECgEJAQAKAAAAAA==.Risky:BAAALgAECgkJAwABLgAFFAIJAgAKAAAAAA==.Riskyfist:BAAALgAECgcJAgAAAA==.Risquae:BAAALgAECgIJAwAAAA==.',
Ro='Roadrashnuts:BAAALgAECgUJBwAAAA==.Rocc:BAAALgAECgcJBAAAAA==.Rocketeer:BAABLgAECn8nAAIbAAgJGg1pnABBAQAbAAgJGg1pnABBAQAAAA==.Romulis:BAAALgAECgEJAQAAAA==.Ronburgundii:BAAALgAECgEJAQAAAA==.',
Ru='Rudrya:BAABLgAECn8UAAInAAgJcAfhEwB8AQAnAAgJcAfhEwB8AQAAAA==.Rumpkey:BAAALgADCgcJCgAAAA==.Runalish:BAAALgAECgEJAQAAAA==.Runarinis:BAAALgADCgIJAgAAAA==.',
Ry='Rynopinn:BAACLgAFFH8JAAIJAAMJIhZ/OgDEAAAJAAMJIhZ/OgDEAAAuAAQKf0YABAkACAnqIxkLAOgCAAkACAnqIxkLAOgCAB8ABwm6G/4MAOYBABQAAgn4F6VlAIYAAAAA.Ryxn:BAAALgADCgYJBgAAAA==.',
['Rí']='Ríco:BAAALgADCgYJEAAAAA==.',
Sa='Saeed:BAAALgAECgEJAQAAAA==.Saelylasia:BAAALgAECgQJBQAAAA==.Sajaboy:BAAALgAECgMJBAAAAA==.Samusaran:BAAALgADCgEJAQAAAA==.Sarrania:BAAALgAECgUJBQAAAA==.Sartha:BAABLgAECn8qAAIMAAkJuhiQMAA+AgAMAAkJuhiQMAA+AgAAAA==.Sasuka:BAAALgAECgkJDQAAAA==.Satsu:BAAALgAECgEJAQAAAA==.',
Sc='Scatherlia:BAAALgADCgYJBQABLgAECgQJBQAKAAAAAA==.Sco:BAAALgADCgEJAQABLgAECgYJDQAKAAAAAA==.Screwthebull:BAAALgAECgQJBAAAAA==.Scrumpvincet:BAAALgADCgUJBQAAAA==.',
Se='Sectiondk:BAAALgAECgYJEwAAAA==.Sedda:BAACLgAFFH8bAAIMAAgJSSHvCwAeAgAMAAgJSSHvCwAeAgAuAAQKfy0AAgwACAmnJc4GAGMDAAwACAmnJc4GAGMDAAAA.Seigfreid:BAAALgAECgYJCAAAAA==.Sensual:BAACLgAFFH8QAAIRAAQJDQgtDQCnAAARAAQJDQgtDQCnAAAuAAQKf0kAAhEACQlTFOoSAJoBABEACQlTFOoSAJoBAAAA.Seraphina:BAAALgAECgYJDgAAAA==.Sessano:BAAALgAECgYJDQAAAA==.Sesshomaru:BAACLgAFFH8HAAMHAAIJCiFAKgBQAAAHAAEJ0CNAKgBQAAAVAAEJRB76lABQAAAuAAQKf1MAAxUACQnUIxcTAOcCABUACAm3IRcTAOcCAAcACAkvJGsMAGACAAAA.',
Sh='Shadoly:BAAALgAECgcJEQAAAA==.Shadowboss:BAABLgAECn8iAAIEAAYJixGPQQAJAQAEAAYJixGPQQAJAQAAAA==.Shamhspriest:BAAALgAECgUJBQAAAA==.Shamnslam:BAAALgAECgEJAQAAAA==.Shang:BAACLgAFFH8SAAQUAAQJHSRqEACiAQAUAAQJ2iNqEACiAQAfAAEJhiD2GQBhAAAJAAEJswMKewApAAAuAAQKfzMABBQACQlMJWUCAE8DABQACQlMJWUCAE8DABkAAwm+Hqc9ALAAAAkAAgnDEmbNADcAAAAA.Shiftchi:BAAALgAECgQJBQAAAA==.Shirona:BAABLgAECn84AAIVAAkJ6SGCBwAXAwAVAAkJ6SGCBwAXAwAAAA==.Shockazulu:BAAALgAECgEJAQAAAA==.Showstop:BAAALgAECgEJAQAAAA==.Shyvanna:BAABLgAECn8mAAMmAAkJyBGCJAC5AQAmAAkJyBGCJAC5AQAlAAQJ0wonHQBkAAAAAA==.Sháman:BAAALgAECgUJBAAAAA==.Shïnïgämï:BAABLgAECn8WAAIoAAYJiCAvCQDeAQAoAAYJiCAvCQDeAQABLgAFFAIJBgANABwcAA==.Shøøtinlåvå:BAAALgADCgcJBwAAAA==.',
Si='Siare:BAABLgAECn8bAAIBAAYJax1DAQC2AQABAAYJax1DAQC2AQAAAA==.Sigarda:BAAALgAECgUJCAAAAA==.Silica:BAAALgAECgMJAwAAAA==.Silvershot:BAAALgADCgUJBQAAAA==.Siner:BAAALgAECgUJCAAAAA==.',
Sk='Skeeter:BAABLgAECn8+AAQkAAkJXR2SAwBZAgAkAAkJBRqSAwBZAgABAAkJWxhTSADBAQAjAAcJJx1BDACYAQAAAA==.Skiadrum:BAACLgAFFH8FAAIhAAMJgQGlOQBgAAAhAAMJgQGlOQBgAAAuAAQKf0IAAxgACQl+FMQpAN4BABgACAnXEsQpAN4BACEABAlBCRNnAIgAAAAA.Skoliro:BAAALgAECgcJCgAAAA==.Skorch:BAAALgADCgkJEAABLgAFFAQJCQAbAPwKAA==.',
Sm='Smotts:BAAALgAECgkJDwAAAA==.Smòtts:BAABLgAECn8kAAIZAAkJcRtRAABfAgAZAAkJcRtRAABfAgAAAA==.',
Sn='Snizard:BAABLgAECn8iAAICAAcJ9hxhNwAAAgACAAcJ9hxhNwAAAgAAAA==.Snizorc:BAAALgAECgEJAQAAAA==.Snuggiepoo:BAABLgAECn8kAAMDAAkJsh6jCwC1AgADAAgJ5CCjCwC1AgAEAAYJgRWgWgCrAAAAAA==.',
So='Songbirds:BAAALgADCgcJDQAAAA==.Sonichoos:BAAALgAECgUJDAAAAA==.Sophiel:BAACLgAFFH8GAAIVAAMJqBKGYgDJAAAVAAMJqBKGYgDJAAAuAAQKfyQAAhUACAktG+kmADACABUACAktG+kmADACAAAA.Sosthenna:BAAALgADCgkJCQAAAA==.Soulbark:BAAALgAECgMJAwABLgAECgQJBAAKAAAAAQ==.Souleater:BAAALgADCgMJAwAAAA==.Soulforged:BAAALgADCgcJCwABLgAECgQJBAAKAAAAAA==.Soulreaver:BAAALgAECgcJCAAAAA==.Soulweaver:BAAALgAECgQJBAAAAQ==.',
Sp='Sparrowhåwk:BAAALgADCgUJBgAAAA==.Spicymustard:BAAALgAECgEJAQAAAA==.Spongebill:BAAALgADCgEJAQAAAA==.Spàdes:BAABLgAECn8cAAMQAAcJxxovMgCDAQAQAAYJbhsvMgCDAQALAAMJbBIJSACrAAAAAA==.',
St='Starel:BAAALgAECgQJBAAAAA==.Stellanoova:BAAALgAECgcJDwABLgAECggJFgAmAEoUAA==.Stevebushami:BAAALgAECgYJEAAAAA==.Stuwu:BAAALgAECgMJAwAAAA==.',
Su='Submistive:BAEALgAECgMJAwABLgAECgYJIgALAN0jAA==.Suffers:BAAALgAFFAEJAQAAAA==.Suou:BAAALgADCgcJCQABLgAECgEJAgAKAAAAAA==.Surj:BAABLgAECn8hAAMcAAYJ2RgrAQAVAQAcAAYJ2RgrAQAVAQAQAAQJeAu2aQC6AAAAAA==.',
Sv='Svmii:BAAALgADCgcJCgAAAA==.',
Sy='Sycther:BAAALgADCgEJAQABLgAFFAMJCQAJACIWAA==.',
Ta='Taazdingo:BAAALgAECgUJEAAAAA==.Taikuri:BAAALgAECggJDwABLgAECgYJGwABAGsdAA==.Taliela:BAAALgAECgQJBAAAAA==.Tanddralndra:BAAALgAECgUJBwAAAA==.Tanklilbaby:BAAALgAECgEJAQAAAA==.Tannia:BAAALgADCgcJDgAAAA==.Taxgirl:BAACLgAFFH8YAAMGAAUJiRycUQBOAQAGAAUJiRycUQBOAQATAAEJsQOYLAA3AAAuAAQKfycAAgYACAlAJWISAA0DAAYACAlAJWISAA0DAAAA.',
Te='Teabear:BAAALgAFFAMJBAAAAA==.Teralion:BAAALgAECgMJBgAAAA==.',
Th='Thaeldrik:BAAALgADCgcJCgAAAA==.Thaldreaux:BAAALgAECgMJBAAAAA==.Thefirst:BAAALgAECgMJBwABLgAECgYJIgAEAIsRAA==.Theleon:BAABLgAECn8dAAIUAAgJQg9pLwBiAQAUAAgJQg9pLwBiAQAAAA==.Thordrin:BAABLgAECn8yAAIIAAcJ/CQzCgDoAgAIAAcJ/CQzCgDoAgAAAA==.Thorlan:BAAALgADCgYJCAAAAA==.Thrasherzs:BAAALgAECgUJDQAAAA==.Thryen:BAAALgAECgUJCwAAAA==.Thunder:BAAALgADCgQJBAABLgAECgcJCgAKAAAAAA==.Thundergrasp:BAACLgAFFH8IAAInAAcJmgt8AwCcAQAnAAcJmgt8AwCcAQAuAAQKfxsAAicABwkNG9cPALQBACcABwkNG9cPALQBAAAA.',
Ti='Tianhe:BAAALgAECgMJAwAAAA==.Tiarisaril:BAAALgAECgYJBgAAAA==.Tigercita:BAAALgAECgMJAgAAAA==.Tippah:BAAALgAECgEJAwAAAA==.Tippers:BAAALgAECgEJAQAAAA==.',
Tj='Tjsneckbeard:BAAALgAECgEJAQAAAA==.',
To='Toe:BAABLgAFFH8FAAIGAAIJrRTCxwCdAAAGAAIJrRTCxwCdAAAAAA==.Tonkah:BAAALgAECgUJBQABLgAECggJEQAKAAAAAA==.Toobestake:BAAALgAFFAMJAwABLgAFFAUJGAACAIkjAA==.Topenga:BAACLgAFFH8VAAICAAQJMRmKNABFAQACAAQJMRmKNABFAQAuAAQKf0wAAgIACQnXH2kSAKQCAAIACQnXH2kSAKQCAAAA.Tosem:BAAALgAECgcJBwAAAA==.Touchypope:BAAALgADCgYJCwAAAA==.',
Tr='Treeage:BAAALgADCgMJAwAAAA==.Triggerd:BAAALgADCgEJAQAAAA==.Trunks:BAAALgADCgQJBAAAAA==.Trylok:BAAALgADCgEJAQAAAA==.Trüst:BAAALgAECggJDgAAAA==.',
Tw='Twicelife:BAABLgAECn8ZAAINAAgJ0R3uFgCSAgANAAgJ0R3uFgCSAgABLgAFFAQJFQALABYVAA==.',
Ty='Tyrygosa:BAAALgAECgUJBQABLgAFFAQJEAABAMEWAA==.',
['Tå']='Tånk:BAAALgAECggJEwAAAA==.',
Un='Undread:BAAALgAFFAEJAQABLgAFFAUJDwAQAGQdAA==.Uneedsummilk:BAAALgADCgcJBwAAAA==.Unholyapollo:BAAALgADCgYJCwAAAA==.',
Ur='Urthstripe:BAABLgAECn8vAAQJAAkJxBWwHABhAgAJAAkJxBWwHABhAgAUAAIJMgMGjwAxAAAfAAEJiwUwZQAaAAAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCQAGAGQiAA==.Vain:BAAALgAECgEJAgAAAA==.Valle:BAAALgAECgIJAwABLgAFFAcJGgAEALAaAA==.Valoria:BAAALgAECgMJCQABLgAFFAcJGgAEALAaAA==.',
Ve='Veil:BAAALgAECgIJCAABLgAFFAcJGgAEALAaAA==.Velarenea:BAAALgADCgEJAQAAAA==.Velgabrine:BAAALgAECgYJDAABLgAFFAQJEAAMADsjAA==.Veraani:BAAALgAECgYJBgAAAA==.Verra:BAAALgADCgYJBgAAAA==.',
Vi='Vil:BAAALgADCgcJBgAAAA==.Virlan:BAAALgADCgQJBAAAAA==.Viserion:BAABLgAECn8WAAMmAAgJShQxPgAxAQAmAAcJZBIxPgAxAQAiAAYJ2AzfIADtAAAAAA==.',
Vo='Voidchaosfan:BAAALgAECgYJDAAAAA==.',
Vu='Vue:BAACLgAFFH8SAAIIAAQJQxMkJwDpAAAIAAQJQxMkJwDpAAAuAAQKf0YAAggACQkkGzYfAB8CAAgACQkkGzYfAB8CAAAA.Vuldin:BAAALgAECgEJAgAAAA==.',
['Vö']='Völdemört:BAAALgADCgIJAgAAAA==.',
Wa='Wakasham:BAACLgAFFH8ZAAInAAYJqCJRAQAcAgAnAAYJqCJRAQAcAgAuAAQKfzEAAicACQk9Jp4BAFMDACcACQk9Jp4BAFMDAAAA.Wardemon:BAAALgADCgIJAgAAAA==.Wardrake:BAAALgAECgEJAQAAAA==.',
We='Wehonoryou:BAABLgAECn8YAAIHAAYJ9CHYGAAAAgAHAAYJ9CHYGAAAAgAAAA==.Wetard:BAAALgADCgIJAgAAAA==.',
Wi='Willbyers:BAAALgAECgEJAQAAAA==.Winterloom:BAAALgAECgYJBgAAAA==.',
Wo='Wolfpacked:BAACLgAFFH8GAAINAAIJHByYWgCXAAANAAIJHByYWgCXAAAuAAQKfygAAg0ACQlBIDUJAB8DAA0ACQlBIDUJAB8DAAAA.Wolfzbåin:BAAALgAECgQJBAAAAA==.',
Wr='Wroot:BAAALgADCgYJCQAAAA==.Wrotten:BAABLgAECn8WAAIjAAgJ6RcDCwCtAQAjAAgJ6RcDCwCtAQAAAA==.',
Wu='Wunderlust:BAACLgAFFH8PAAIbAAQJhxftUwA1AQAbAAQJhxftUwA1AQAuAAQKf0QAAhsACQmFISYcAAYDABsACQmFISYcAAYDAAAA.',
Xe='Xemon:BAAALgAECgIJAgAAAA==.',
Xi='Xilyana:BAAALgAECgQJBAAAAA==.',
Xm='Xmatick:BAAALgAECgcJCQAAAA==.',
Xs='Xscrats:BAAALgAECgkJCAAAAA==.',
Ye='Yellowshaman:BAACLgAFFH8nAAIeAAYJiB+TDwCzAQAeAAYJiB+TDwCzAQAuAAQKfzIAAh4ACQk3IkQMANcCAB4ACQk3IkQMANcCAAAA.Yerac:BAAALgAECgEJAQAAAA==.',
Yu='Yukikage:BAAALgAECgMJAwAAAA==.Yutdaeng:BAAALgAECgMJBAAAAA==.',
Yv='Yvent:BAAALgADCgIJAgAAAA==.Yvraine:BAAALgAECgYJEgAAAA==.',
Za='Zakcarii:BAAALgADCgMJCAAAAA==.Zakin:BAAALgADCgcJBwAAAA==.Zalicy:BAAALgAECgYJEwAAAA==.Zalogar:BAAALgAECgcJCgAAAA==.Zapper:BAAALgAECgQJCwAAAA==.',
Zb='Zbarbb:BAAALgADCgUJBQAAAA==.',
Ze='Zealot:BAAALgAECgEJAQAAAA==.Zeeasyez:BAAALgAECgYJEwAAAA==.Zestul:BAAALgADCgEJAQAAAA==.',
Zh='Zhane:BAAALgADCgYJBwAAAA==.',
Zo='Zordon:BAAALgAECgYJEwAAAA==.',
Zs='Zslol:BAAALgAECgEJAQAAAA==.',
Zu='Zugg:BAAALgAECgMJBgABLgAFFAcJGgAEALAaAA==.Zuriznikov:BAAALgAECgYJBwABLgAECggJFgAmAEoUAA==.',
['Ån']='Ångie:BAAALgADCgMJAwAAAA==.',
['Øf']='Øffspeck:BAABLgAECn8hAAQBAAkJVhweLgBVAgABAAgJwxgeLgBVAgAjAAcJICFyDACVAQAkAAMJzh7MMAD3AAAAAA==.',
['Ør']='Ørb:BAAALgADCgEJAQAAAA==.',
['ßo']='ßoss:BAAALgAECgIJAgABLgAECgYJIgAEAIsRAA==.',
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
