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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Priest-Discipline','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','DemonHunter-Devourer','Paladin-Holy','Druid-Restoration','Unknown-Unknown','Warrior-Arms','Rogue-Subtlety','Paladin-Retribution','Shaman-Restoration','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','Paladin-Protection','DeathKnight-Blood','DeathKnight-Frost','Druid-Balance','DemonHunter-Havoc','Rogue-Assassination','Mage-Arcane','Druid-Guardian','Monk-Brewmaster','Mage-Frost','Warrior-Protection','Shaman-Elemental','Monk-Mistweaver','Druid-Feral','Mage-Fire','Monk-Windwalker','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Evoker-Augmentation','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=46,date='2026-06-28',data={Aa='Aaron:BAAALgAECgcJBwABLgAECgkJIQABAFYcAA==.Aaronfreeze:BAACLgAFFH8JAAICAAMJehr0VgD5AAACAAMJehr0VgD5AAAuAAQKfzIAAgIACQn1HuIfAGgCAAIACQn1HuIfAGgCAAAA.',
Ab='Abrakazaam:BAAALgADCgEJAQAAAA==.',
Ad='Adrios:BAACLgAFFH8FAAIDAAIJmRQ3OwCTAAADAAIJmRQ3OwCTAAAuAAQKfyYABAMACQnQFvMZAAACAAMACAn9F/MZAAACAAQABwlRB9pTAMMAAAUAAwnKCCRpAIgAAAAA.',
Ae='Aetherion:BAAALgAECgMJBAAAAA==.',
Ai='Airorca:BAAALgAECgUJBQAAAA==.',
Aj='Ajaxz:BAABLgAECn8VAAIGAAkJ+RLTYADRAQAGAAkJ+RLTYADRAQAAAA==.',
Ak='Akaßoss:BAAALgADCgEJAQABLgAECgYJIgAEAIsRAA==.',
Al='Albedô:BAAALgAFFAIJAwABLgAFFAIJCAAHAAohAA==.Aliren:BAAALgAECgYJCgAAAA==.Allaway:BAAALgAECgEJAQAAAA==.Allmaick:BAAALgADCggJCAAAAA==.Alucard:BAABLgAFFH8XAAIIAAUJcw17BgAjAQAIAAUJcw17BgAjAQAAAA==.Alystrasza:BAABLgAECn8dAAIJAAYJvhbhRAB9AQAJAAYJvhbhRAB9AQAAAA==.',
Am='Amorlandian:BAAALgAECgMJAwAAAA==.',
An='Antimovsky:BAAALgAECgcJEwAAAA==.',
Ap='Aphroditê:BAAALgAECgMJBAABLgAECgcJCAAKAAAAAA==.',
Aq='Aqours:BAAALgADCgcJBwABLgAECgEJAgAKAAAAAA==.',
Ar='Arcan:BAAALgAECgIJAgAAAA==.',
As='Astellia:BAAALgADCgEJAQAAAA==.',
Au='Augustine:BAAALgAECgEJAQAAAA==.Aullyura:BAAALgADCgcJBwAAAA==.Auroras:BAACLgAFFH8IAAMFAAMJUwbfKAB/AAAFAAMJUwbfKAB/AAAEAAEJmAEzQgAvAAAuAAQKfxcAAgUABwmEE5k0AGwBAAUABwmEE5k0AGwBAAAA.',
Av='Aviaria:BAAALgAECgQJBAAAAA==.Avìendha:BAAALgADCgQJBAAAAA==.',
Aw='Awsmpossum:BAAALgAECgEJAQAAAA==.',
Az='Azurah:BAAALgAECgEJAQAAAA==.',
['Aì']='Aìnzooalgown:BAABLgAFFH8SAAIGAAQJESGFPQB9AQAGAAQJESGFPQB9AQABLgAFFAIJCAAHAAohAA==.',
Ba='Babakubwa:BAAALgAECgMJAwAAAA==.Babylonfive:BAAALgAECgcJDQAAAA==.Balhair:BAAALgADCgYJBgAAAA==.Banger:BAAALgADCgEJAQAAAA==.Banish:BAAALgAECgMJAgABLgAECgcJCgAKAAAAAA==.Barragdan:BAAALgADCgEJAQAAAA==.Basandra:BAAALgAECgEJAQAAAA==.Basicc:BAAALgADCgUJBQAAAA==.',
Be='Beachbumm:BAAALgADCgEJAQAAAA==.Beastreminna:BAAALgADCgEJAQAAAA==.Belleta:BAAALgAECggJEQAAAA==.Berserk:BAEBLgAECn8iAAILAAYJ3SP5DgD+AQALAAYJ3SP5DgD+AQABLgAFFAQJCwAMAB0WAA==.Bertringer:BAAALgAECgEJAgABLgAECgYJBgAKAAAAAA==.',
Bi='Bigmack:BAAALgAECgYJCwABLgAFFAgJIgANAAcWAA==.Bigpoppa:BAAALgAECgEJAgABLgAECgYJBgAKAAAAAA==.Bigwilli:BAABLgAECn8XAAIOAAkJHRK+OQDIAQAOAAkJHRK+OQDIAQAAAA==.Bingßong:BAAALgADCgYJEwAAAA==.Biscuit:BAACLgAFFH8RAAQPAAcJahoYHADOAAACAAUJhyDBWAD0AAAPAAMJ7BEYHADOAAAQAAIJ+xHqKwCDAAAuAAQKfyIABA8ACAmPIycPAMgCAA8ACAl9HScPAMgCABAAAwnZH+45AO0AAAIABAk+HqCsAOoAAAAA.Bisha:BAABLgAECn9FAAMRAAkJEiHmDQDmAgARAAkJ9CDmDQDmAgALAAYJcBgnMgD/AAAAAA==.Bizcocho:BAAALgAECgcJEQAAAA==.',
Bl='Black:BAAALgADCgEJAQAAAA==.Bloodsimple:BAAALgADCgUJBQAAAA==.Blákers:BAABLgAFFH8OAAISAAQJuSQIAgCvAQASAAQJuSQIAgCvAQAAAA==.',
Bo='Boic:BAAALgADCgQJBAAAAA==.Bonesofdoom:BAACLgAFFH8HAAITAAMJ1w0iLQCUAAATAAMJ1w0iLQCUAAAuAAQKfyMAAxMACQkHGU8ZAJYBABMACAmJG08ZAJYBAAYAAgkYBtY/AV8AAAAA.Boogsta:BAACLgAFFH8QAAMUAAMJmgqBGADHAAAUAAMJmgqBGADHAAAGAAEJ7AIrJQExAAAuAAQKfzYAAhQACQlxFWgHACICABQACQlxFWgHACICAAAA.Boomkingobrr:BAACLgAFFH8HAAIVAAMJ9wj3NQCnAAAVAAMJ9wj3NQCnAAAuAAQKfxsAAhUACQkOHEQLAOECABUACQkOHEQLAOECAAAA.Boops:BAAALgAECgEJAQAAAA==.Bootysweatt:BAABLgAECn8aAAIWAAYJNhtqJACaAQAWAAYJNhtqJACaAQAAAA==.Boss:BAAALgADCgEJAQABLgAECgYJIgAEAIsRAA==.',
Br='Braahma:BAABLgAFFH8GAAQUAAYJNhnUAwAVAQAUAAMJNB3UAwAVAQAGAAIJOBNBLgC4AAATAAEJAACgHwAAAAAAAA==.Brewnz:BAAALgAECgUJBgAAAA==.Brucewee:BAAALgAECgQJCgAAAA==.',
Bu='Buckits:BAAALgAECgcJEgAAAA==.Bunsey:BAAALgADCgIJAgAAAA==.Burnsx:BAAALgAECgUJCgABLgAFFAkJGgAHAMAcAA==.Bussyman:BAAALgAECgYJEQABLgAFFAMJCQAJACIWAA==.',
Bw='Bwoar:BAAALgAECgQJBgAAAA==.',
['Bø']='Bøw:BAAALgAECgMJAwAAAA==.',
['Bü']='Bübble:BAAALgADCgEJAQAAAA==.',
Ca='Caiandol:BAAALgAECgEJAQAAAA==.Capnmurloc:BAAALgAECgEJAQAAAA==.Captnmurloc:BAAALgAECgkJEgAAAA==.Capwackychan:BAAALgAECgEJAQAAAA==.Carl:BAAALgAECgEJAgABLgAFFAgJDwAXAMwbAA==.Carrach:BAAALgAECgIJBQAAAA==.Caveyodeler:BAAALgAECgQJCgAAAA==.',
Ce='Cedar:BAAALgAECgYJEAAAAA==.',
Ch='Cherga:BAAALgADCgYJBgAAAA==.Chinegga:BAAALgADCgYJBgAAAA==.Chitose:BAAALgADCgUJBQABLgAECgEJAgAKAAAAAA==.Chrapsasspee:BAAALgADCgcJGQAAAA==.Chrinn:BAAALgADCgMJAwAAAA==.',
Ci='Cindele:BAAALgADCgMJAwAAAA==.Cirvix:BAAALgAECgYJDAAAAA==.Cirxe:BAABLgAECn8jAAIYAAkJXA+ABACtAQAYAAkJXA+ABACtAQAAAA==.',
Cl='Clampire:BAAALgAECgQJBAAAAA==.Cliint:BAAALgAECgcJCwAAAA==.Cloúnt:BAAALgAECgEJAwABLgAFFAMJBwAVAPcIAA==.',
Co='Commotionn:BAAALgAECgQJBAAAAA==.Coms:BAAALgADCgIJAgAAAA==.Cooz:BAAALgAECgYJDwAAAA==.Corybooker:BAAALgAECgcJBAAAAA==.Cowdux:BAAALgAFFAEJAQAAAA==.Cowmoorem:BAAALgADCgEJAQAAAA==.',
Cr='Creamdragon:BAAALgADCgcJDQABLgAECgYJCAAKAAAAAA==.',
Cu='Curuni:BAAALgADCgcJDAAAAA==.',
Cz='Czechhunter:BAAALgADCgUJBQAAAA==.',
['Cå']='Cåleb:BAAALgAECgEJAQAAAA==.',
['Cø']='Cønstance:BAABLgAECn8VAAIZAAcJvREUJgAjAQAZAAcJvREUJgAjAQAAAA==.',
Da='Daddyphat:BAABLgAECn8rAAIaAAgJrCS6BgDOAgAaAAgJrCS6BgDOAgAAAA==.Daddý:BAAALgAECgEJAQAAAA==.Dalight:BAABLgAECn8XAAIIAAYJKiYPDwCdAgAIAAYJKiYPDwCdAgAAAA==.Dankins:BAACLgAFFH8dAAIOAAgJ2SKvAQDhAgAOAAgJ2SKvAQDhAgAuAAQKfxYAAg4ACAkGHfYZAEcCAA4ACAkGHfYZAEcCAAAA.',
De='Deathmager:BAABLgAECn89AAIbAAkJjBJ4SQD/AQAbAAkJjBJ4SQD/AQAAAA==.Deathtraper:BAAALgAECgcJDQAAAA==.Debur:BAAALgADCgEJAQAAAA==.Deltaka:BAAALgAECgEJAQAAAA==.Demonfella:BAAALgADCgMJAwAAAA==.Demonicpeach:BAABLgAECn8YAAIBAAcJwwv9rADpAAABAAcJwwv9rADpAAAAAA==.Denaian:BAAALgADCgYJBgAAAA==.Dethsent:BAAALgAECggJEQAAAA==.Dette:BAABLgAECn8dAAICAAkJvBUrLgAkAgACAAkJvBUrLgAkAgAAAA==.Devilchaser:BAAALgAECggJDgAAAA==.Devourer:BAABLgAECn8VAAIHAAcJjg+mbQBaAQAHAAcJjg+mbQBaAQAAAA==.',
Dh='Dhtank:BAAALgAECgEJAQAAAA==.',
Di='Diaval:BAAALgADCgIJAgABLgAECgkJLAABAFsTAA==.Dinosforlife:BAAALgAECgYJDAAAAA==.',
Dk='Dkboss:BAAALgAECgIJAgABLgAECgYJIgAEAIsRAA==.',
Do='Donzilly:BAAALgAECgYJDgAAAA==.Doreme:BAAALgADCgIJAgAAAA==.Dorgrim:BAAALgAECgUJDAAAAA==.Doyuevendps:BAAALgADCgEJAQAAAA==.',
Dr='Drafted:BAAALgAECgcJEAAAAA==.Drax:BAAALgAECgMJAwAAAA==.Drewmcmoo:BAAALgADCgcJBgAAAA==.Drsath:BAAALgADCgcJBwAAAA==.Drunkorca:BAAALgADCgUJBQAAAA==.',
Ea='Earnar:BAAALgADCgYJDAAAAA==.',
Ed='Edarix:BAAALgADCggJDAABLgAECggJQAANAHkYAA==.Edstark:BAAALgAECgQJBQAAAA==.',
Ei='Eiliyah:BAABLgAECn8yAAMIAAgJehz0FgBaAgAIAAgJehz0FgBaAgANAAIJHwIaWgElAAAAAA==.',
Ek='Ekmek:BAAALgAECgEJAQAAAA==.',
El='Elabernathy:BAABLgAECn80AAICAAkJrhiDHQB0AgACAAkJrhiDHQB0AgAAAA==.Elenay:BAABLgAECn8UAAIJAAgJqR6QIwAuAgAJAAgJqR6QIwAuAgAAAA==.Elesia:BAAALgAECgkJEgAAAA==.Elfussy:BAAALgAECgEJAQAAAA==.Elgoku:BAAALgAECgQJCgABLgAECgUJDAAKAAAAAA==.Eliarssande:BAAALgAECgMJAwAAAA==.Elinay:BAAALgAECgQJBAABLgAECggJFAAJAKkeAA==.Elixia:BAABLgAECn8bAAIWAAgJDA2/JgBEAQAWAAgJDA2/JgBEAQAAAA==.Elpatron:BAABLgAFFH8MAAIJAAUJOxBEBwA1AQAJAAUJOxBEBwA1AQAAAA==.Elylanea:BAAALgAECgUJDgAAAA==.',
Em='Emulsdeath:BAABLgAECn8UAAMTAAgJKCFPEwDcAQATAAcJLB5PEwDcAQAGAAYJ8iCEawCOAQABLgAFFAQJEQANADsjAA==.Emulsifier:BAACLgAFFH8RAAINAAQJOyMZHQCUAQANAAQJOyMZHQCUAQAuAAQKfzAAAg0ACAmFJgMNAPwCAA0ACAmFJgMNAPwCAAAA.',
En='Ennoa:BAAALgAECgEJAQAAAA==.',
Er='Ergen:BAACLgAFFH8dAAIQAAYJBxdYEQA8AQAQAAYJBxdYEQA8AQAuAAQKfyoAAhAACAlvIaUGAJcCABAACAlvIaUGAJcCAAAA.',
Eu='Eusexua:BAAALgAECgQJBQABLgAECgcJCgAKAAAAAA==.',
Ex='Expiatory:BAAALgAECgYJCQAAAA==.',
Fa='Faielle:BAAALgAECgEJAQAAAA==.Fairbear:BAABLgAECn8dAAQRAAYJ+ByHOQBgAQARAAYJ+ByHOQBgAQALAAEJZA5tPgA7AAAcAAEJ6Qc6XgAbAAAAAA==.Faustt:BAAALgAECgUJBwAAAA==.',
Fi='Filthyfabio:BAAALgADCgcJEQAAAA==.Finester:BAACLgAFFH8MAAIMAAQJdh8tEgB9AQAMAAQJdh8tEgB9AQAuAAQKfxgAAgwACQmCIZoAAGsCAAwACQmCIZoAAGsCAAAA.Fireburr:BAAALgAECgMJAwAAAA==.',
Fl='Flatline:BAAALgAECgcJEgAAAA==.Fløw:BAAALgAECgMJCgAAAA==.',
Fr='Fragglerott:BAABLgAECn8bAAMOAAgJGBN9gwDYAAAOAAQJUhJ9gwDYAAAdAAgJ1AqdZgCyAAAAAA==.Frati:BAAALgAECgEJAQAAAA==.Friedchickn:BAAALgAECgQJCAAAAA==.Frostboss:BAAALgADCgEJAQABLgAECgYJIgAEAIsRAA==.Frostnips:BAAALgAECgcJCwAAAA==.Frosttrinity:BAAALgADCgUJBAAAAA==.',
Fu='Funslinger:BAAALgAECgQJDAAAAA==.',
Ga='Gaffz:BAAALgAECgEJAgAAAA==.Galannar:BAAALgAECggJDQAAAA==.Galvrax:BAAALgAECgUJCgAAAA==.Gast:BAACLgAFFH8PAAIRAAUJZB3nGQBKAQARAAUJZB3nGQBKAQAuAAQKfzYAAxEACQlRIN4JAMUCABEACQlRIN4JAMUCABwABAmpFuA1AKAAAAAA.',
Ge='Gearwick:BAAALgADCgYJBwABLgAECgcJJgAIAFAhAA==.',
Gh='Ghstfacekila:BAAALgADCgEJAQAAAA==.',
Go='Gorska:BAABLgAECn84AAIdAAkJfB0nEAByAgAdAAkJfB0nEAByAgAAAA==.',
Gr='Grawm:BAABLgAECn8iAAMPAAkJqiKzHgAxAgAPAAgJSRWzHgAxAgACAAkJPiBvTwC0AQAAAA==.Greedory:BAAALgADCgIJAgAAAA==.Groot:BAAALgADCgUJBgAAAA==.Gruetss:BAAALgAECgQJBAAAAA==.',
Gu='Guilty:BAAALgAECgEJAgAAAA==.',
['Gä']='Gämbit:BAAALgADCgEJAQAAAA==.',
Ha='Hailbringer:BAAALgAECgcJDgAAAA==.Hakoona:BAABLgAECn8yAAIaAAkJFxrGEQApAgAaAAkJFxrGEQApAgAAAA==.Hanginaround:BAAALgAECgEJAQAAAA==.Hangman:BAACLgAFFH8bAAIIAAQJ8SVXEQCrAQAIAAQJ8SVXEQCrAQAuAAQKfyEAAwgACQmLJBACAJADAAgACQmLJBACAJADAA0ABAklDR4gAZMAAAEuAAUUAwkJAAkAIhYA.Hanni:BAABLgAECn8dAAIPAAgJUhyUCwCuAQAPAAgJUhyUCwCuAQAAAA==.Haveaburitto:BAACLgAFFH8NAAIbAAQJWBxMXAAmAQAbAAQJWBxMXAAmAQAuAAQKfygAAhsACAk0JXkMAGEDABsACAk0JXkMAGEDAAAA.Hawktoetem:BAAALgAECgUJCAABLgAECgYJHQARAPgcAA==.Hawktoouh:BAABLgAECn8YAAMFAAgJEBrpAABAAgAFAAcJhhvpAABAAgADAAcJxg45AwBRAQABLgAFFAMJEAAUAJoKAA==.',
He='Healmemaybe:BAABLgAECn8bAAIJAAYJQiP8IgAxAgAJAAYJQiP8IgAxAgAAAA==.Healthyadult:BAAALgAECgMJBQAAAA==.Hellshand:BAAALgAECgYJDAAAAA==.Heracles:BAAALgAECgQJBAAAAA==.Heretic:BAAALgAECgEJAQAAAA==.',
Hi='Hickscale:BAAALgADCgMJAwAAAA==.',
Ho='Holycøw:BAAALgADCgMJAwAAAA==.Holydefender:BAAALgADCgcJDQAAAA==.Holyhands:BAAALgADCgYJBgAAAA==.Holyholyholy:BAAALgAECggJEgAAAA==.Honest:BAAALgADCgMJAwAAAA==.',
Hu='Hunniee:BAAALgAECgEJAQAAAA==.Huntrix:BAAALgADCgcJEgAAAA==.',
Ic='Icedatt:BAABLgAECn8VAAMGAAUJ8QIpKAF5AAAGAAUJ7AIpKAF5AAATAAUJcwGQVABIAAAAAA==.Icefire:BAAALgADCgUJBAAAAA==.',
Ik='Ikur:BAACLgAFFH8PAAIIAAQJrxtgHQAyAQAIAAQJrxtgHQAyAQAuAAQKfzsAAggACQmTHpMHABMDAAgACQmTHpMHABMDAAAA.',
Il='Ilinia:BAAALgAECgYJCAABLgAECgUJEgAKAAAAAA==.Illhealutoo:BAAALgAFFAEJAQAAAA==.',
Im='Imsteve:BAAALgAECgUJBQAAAA==.',
In='Infoxicated:BAAALgADCgcJCAABLgAECgkJJAADALIeAA==.Insîght:BAAALgAECgQJCAAAAA==.',
Ip='Ipopkidneys:BAACLgAFFH8VAAMMAAcJ1SFiDQC8AQAMAAYJlSFiDQC8AQAXAAMJjB0lBwDxAAAuAAQKfycAAwwACQnhJYQMANACAAwACQnhJYQMANACABcAAQn1IyQfAGUAAAAA.',
Ir='Iroi:BAAALgAECgIJBQAAAA==.',
Is='Iskur:BAABLgAECn8mAAMOAAgJ4BgbIwA8AgAOAAgJ4BgbIwA8AgAdAAMJMQ26dgCJAAABLgAFFAQJDwAIAK8bAA==.Isuck:BAAALgAFFAIJAgAAAA==.Isurr:BAABLgAECn8iAAIeAAcJnhK+OQCLAQAeAAcJnhK+OQCLAQABLgAFFAQJDwAIAK8bAA==.',
It='Itakecandle:BAAALgAECgUJBwABLgAECgUJDAAKAAAAAA==.',
Iv='Ivanapump:BAAALgAECgIJAgABLgAECgYJBgAKAAAAAA==.',
Ja='Jackkal:BAAALgAECggJCgAAAA==.Jadethecat:BAAALgADCgMJAwAAAA==.Jakbis:BAAALgADCgEJAQAAAA==.Jakychan:BAAALgAECgEJAQAAAA==.Jaldiar:BAAALgADCgcJBwABLgAECgYJBgAKAAAAAA==.Jametrok:BAAALgAECgEJAQAAAA==.Jazbek:BAAALgAECgQJDgAAAA==.Jazzonus:BAAALgAECgQJBAAAAA==.',
Je='Jefferey:BAAALgADCgMJAwAAAA==.Jennyanydots:BAAALgAECgMJBQABLgAFFAgJIQAEAGQaAA==.Jeriçho:BAAALgADCgYJBgAAAA==.',
Jh='Jhonwick:BAAALgAECgIJAgAAAA==.',
Ji='Jippedo:BAAALgAECgYJAgABLgAECgcJBAAKAAAAAA==.Jiraîya:BAAALgAECgQJBQAAAA==.',
Jo='Jordak:BAABLgAECn8oAAIJAAkJBBwrDgDnAgAJAAkJBBwrDgDnAgAAAA==.Jorolee:BAAALgADCgEJAQAAAA==.',
Ka='Kaddiya:BAAALgAECgYJEgAAAA==.Kagonstrasza:BAAALgAECgQJBAAAAA==.Kallistos:BAABLgAECn8gAAIOAAcJER3uLQD/AQAOAAcJER3uLQD/AQAAAA==.Kariza:BAAALgAECgQJBgAAAA==.Karunik:BAAALgADCgYJBgABLgAECgcJCgAKAAAAAA==.Kasst:BAAALgAECgEJAQAAAA==.',
Ke='Kelenheller:BAAALgAECgUJDAAAAA==.Key:BAAALgAFFAMJAwAAAA==.',
Kh='Khione:BAAALgAECgMJAwAAAA==.Khthonios:BAAALgAECgEJAQAAAA==.',
Ki='Kiba:BAAALgADCgIJAgABLgAECgYJCAAKAAAAAA==.Kibblerina:BAAALgADCgcJBwAAAA==.Kiranam:BAABLgAECn8fAAQfAAgJ5BKdEQCTAQAfAAgJqQqdEQCTAQAZAAcJfBEyOADGAAAVAAIJWwfecQBZAAAAAA==.',
Kn='Knarth:BAABLgAECn9CAAIgAAkJ5x71AADZAgAgAAkJ5x71AADZAgAAAA==.Kníght:BAABLgAFFH8FAAIGAAMJeQXaLgC2AAAGAAMJeQXaLgC2AAAAAA==.',
Ko='Koisy:BAAALgAECgcJEAABLgAECggJFAAJAKkeAA==.Kole:BAAALgAECgEJAQAAAA==.Koopa:BAABLgAECn8rAAIRAAkJHyVcBQALAwARAAkJHyVcBQALAwAAAA==.',
Kr='Krasul:BAACLgAFFH8WAAMOAAYJwRRDJQBWAQAOAAYJwRRDJQBWAQAdAAIJ7QkOSQBsAAAuAAQKfx8AAw4ACAkXIecIAOgCAA4ACAkXIecIAOgCAB0ABgm/HPIxAJQBAAAA.Krenthok:BAABLgAECn8eAAIBAAgJiQe3iQAmAQABAAgJiQe3iQAmAQAAAA==.',
Ku='Kuraha:BAAALgAECgQJBAAAAA==.Kuruni:BAAALgAECgYJCgAAAA==.Kushar:BAAALgAECgQJBQABLgAECgkJGAAhAMkQAA==.',
Ky='Kyuketsuki:BAAALgAFFAIJAwAAAA==.',
La='Lachance:BAAALgADCgYJBgAAAA==.Large:BAAALgADCgYJBgAAAA==.Largemann:BAAALgAFFAMJAwABLgAFFAUJGAAGAIkcAA==.Lathspell:BAABLgAECn8yAAIbAAkJtiAMJgCDAgAbAAkJtiAMJgCDAgAAAA==.Lazyevoker:BAAALgADCgQJBAABLgAECgEJAQAKAAAAAA==.',
Le='Leahan:BAAALgAECgQJDQAAAA==.Leloo:BAAALgADCgYJCgABLgAECgIJAwAKAAAAAA==.',
Lh='Lhureciv:BAACLgAFFH8VAAMEAAQJERl9FQA5AQAEAAQJERl9FQA5AQADAAEJKRuVSQBFAAAuAAQKf0sAAwQACQnVI80GAB4DAAQACQnVI80GAB4DAAMABgn7HjAjAHoBAAAA.',
Li='Lightchaser:BAAALgADCgMJAgAAAA==.Lightfkyou:BAAALgADCgcJCgAAAA==.Lihvurce:BAABLgAECn8fAAMNAAgJWR0/MgA3AgANAAgJWR0/MgA3AgAIAAQJpR0FSwBMAQABLgAFFAQJFQAEABEZAA==.Lillianna:BAACLgAFFH8HAAIMAAIJrBJ7MACkAAAMAAIJrBJ7MACkAAAuAAQKfz4AAgwACAmfHsQAABsCAAwACAmfHsQAABsCAAAA.Lingchi:BAAALgAECgQJBgAAAA==.',
Ll='Llew:BAAALgAECgYJCQAAAA==.',
Lo='Loenhart:BAAALgAECgEJAQAAAA==.Lolkurtone:BAAALgAECgIJAgAAAA==.',
Lu='Luciaan:BAAALgADCgkJGQAAAA==.Lucrative:BAAALgADCgcJDQAAAA==.Lug:BAAALgAECgEJAQAAAA==.Lulue:BAAALgADCgQJBAAAAA==.Luminari:BAAALgADCgUJBQAAAA==.Lunastorm:BAACLgAFFH8OAAIiAAQJLxPoGAAIAQAiAAQJLxPoGAAIAQAuAAQKfzgAAiIACQnQIooCAD8DACIACQnQIooCAD8DAAAA.Luponero:BAACLgAFFH8YAAMCAAUJiSPZHQCNAQACAAUJiSPZHQCNAQAPAAEJ5QapKgBGAAAuAAQKfyIAAw8ACAnnHuYQALUCAA8ACAl6HeYQALUCAAIAAwnNHxqXABIBAAAA.',
Ly='Lynney:BAAALgADCgYJBwAAAA==.',
Ma='Macmn:BAACLgAFFH8UAAIdAAYJPRoMEwCLAQAdAAYJPRoMEwCLAQAuAAQKfygAAh0ABwnAJGULAOICAB0ABwnAJGULAOICAAAA.Mageyouacake:BAAALgADCgMJAwAAAA==.Magicard:BAABLgAECn8fAAIbAAgJjg5IewCBAQAbAAgJjg5IewCBAQAAAA==.Makesfood:BAABLgAECn8qAAIbAAcJZBeSdADpAQAbAAcJZBeSdADpAQAAAA==.Mamaheals:BAABLgAECn8rAAIFAAkJSxpbFAAzAgAFAAkJSxpbFAAzAgAAAA==.Mandos:BAAALgAECgYJCAAAAA==.Mantistabogn:BAAALgAFFAEJAQAAAA==.Maor:BAABLgAECn8XAAINAAgJlxcuUADxAQANAAgJlxcuUADxAQAAAA==.March:BAAALgADCgEJAQAAAA==.Markeisha:BAAALgAECgQJCAABLgAECgYJDAAKAAAAAA==.',
Me='Mechz:BAAALgAECgYJBgABLgAFFAQJCQAbAPwKAA==.Mechzician:BAACLgAFFH8JAAIbAAQJ/Ao8dwDsAAAbAAQJ/Ao8dwDsAAAuAAQKfzgAAhsACAlwGXtZAC0CABsACAlwGXtZAC0CAAAA.Mechzlock:BAAALgADCgEJAQABLgAFFAQJCQAbAPwKAA==.Melinoe:BAAALgAECgEJAQAAAA==.Merlerk:BAAALgADCgYJBgABLgAFFAgJJwAFAKYVAA==.Merlini:BAABLgAECn8dAAMEAAgJWRYLJACpAQAEAAcJ0xgLJACpAQADAAUJThaqPAAbAQAAAA==.Mets:BAAALgAECgYJCgABLgAECgkJHwABAIobAA==.',
Mi='Microplastic:BAAALgAECgUJBQAAAA==.Micspanky:BAAALgAECggJEgAAAA==.Mistynight:BAAALgAECgMJAwAAAA==.Mithrandi:BAAALgAECgYJCQAAAA==.Mitzis:BAABLgAFFH8NAAICAAMJ8x89UgAFAQACAAMJ8x89UgAFAQAAAA==.',
Mo='Moltiy:BAAALgADCggJEwAAAA==.Moltten:BAAALgADCggJEgAAAA==.Mornhathor:BAAALgAECggJDgABLgAECgYJCAAKAAAAAA==.',
Mu='Mufinblaster:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgADCgIJBgAAAA==.Musnicker:BAAALgAECgQJBwABLgAECgkJOAAPAIYWAA==.',
My='Myro:BAACLgAFFH8UAAMOAAQJ3B+fJwBJAQAOAAQJ3B+fJwBJAQAdAAIJZRTKQgB/AAAuAAQKfxsAAg4ABwm/JsEHAPkCAA4ABwm/JsEHAPkCAAAA.',
['Mè']='Mètis:BAAALgAECgcJCAAAAA==.',
['Mø']='Møhax:BAAALgAECgYJBgAAAA==.',
Na='Nanis:BAAALgAECgYJBwABLgAFFAUJFwAVABglAA==.Narmer:BAAALgAECgIJAgAAAA==.',
Ne='Neel:BAAALgADCgQJBQAAAA==.Nervhoost:BAAALgADCgMJAwAAAA==.Neuropolis:BAAALgADCgcJFQAAAA==.Neuroscience:BAAALgADCgMJAwAAAA==.Neurotics:BAABLgAECn9MAAQjAAkJNyYZAAALAwAjAAkJryUZAAALAwAkAAcJsSMLBABHAgABAAYJ9xuOEQBjAAAAAA==.Neò:BAABLgAECn8YAAMlAAYJvBC1EAD/AAAlAAYJXw61EAD/AAAmAAEJ/hQHkwA1AAAAAA==.',
Ni='Niesh:BAAALgAECgEJBwAAAA==.Nightrush:BAAALgADCgEJAQAAAA==.Nineoneone:BAABLgAECn9MAAMFAAkJWhcmAQAYAgAFAAkJWhcmAQAYAgADAAQJjgPqRQCLAAAAAA==.Ninjá:BAAALgADCgYJBgAAAA==.',
No='Nobledecay:BAAALgAECgQJBQAAAA==.Nocturne:BAAALgAECgEJAwAAAA==.',
Nu='Nubbletcake:BAAALgADCgEJAQABLgAECgkJJAADALIeAA==.Nula:BAAALgAECgMJBQABLgAFFAgJIQAEAGQaAA==.',
Ny='Nylveth:BAACLgAFFH8QAAIEAAUJzw9EHQAGAQAEAAUJzw9EHQAGAQAuAAQKfyoAAgQACQkAHXQQAFgCAAQACQkAHXQQAFgCAAEuAAUUCAkLACcABwsA.',
Oa='Oathatone:BAAALgAECgUJCAAAAA==.',
Oc='Ocra:BAABLgAECn8gAAInAAkJ9g59DgDJAQAnAAkJ9g59DgDJAQABLgAFFAQJFgACALwZAA==.',
Of='Offspeck:BAAALgAECgIJAgABLgAECgkJIQABAFYcAA==.',
Ou='Outtkast:BAAALgAECgIJAgAAAA==.Outtkastt:BAAALgAECgcJCgAAAA==.Ouutkast:BAAALgAECgIJAwAAAA==.',
Oz='Ozwald:BAABLgAECn81AAIQAAkJchx/EAAqAgAQAAkJchx/EAAqAgAAAA==.',
Pa='Pallyangel:BAAALgADCgcJDwAAAA==.Pandemul:BAAALgAECgMJAwABLgAFFAQJEQANADsjAA==.Patrio:BAACLgAFFH8IAAIiAAMJGg24IQCXAAAiAAMJGg24IQCXAAAuAAQKfywAAiIACQllGfUHAHMCACIACQllGfUHAHMCAAEuAAUUBQkMAAkAOxAA.Pawkclaw:BAAALgAECgYJBgAAAA==.',
Pe='Peaceonea:BAABLgAECn8bAAIHAAkJrgQYnQDoAAAHAAkJrgQYnQDoAAAAAA==.Peachaid:BAECLgAFFH8cAAMDAAgJ9Rd6CQCNAgADAAgJ9Rd6CQCNAgAFAAEJRQgoOgAtAAAuAAQKfzAAAwMACQlVImoFADIDAAMACQlVImoFADIDAAUABgkYHSglAMABAAAA.Peatri:BAAALgAFFAEJAQAAAA==.Peetree:BAACLgAFFH8QAAIOAAQJOBlTLwAlAQAOAAQJOBlTLwAlAQAuAAQKfxYAAg4ACAk6Gm0EAG8BAA4ACAk6Gm0EAG8BAAAA.Pekin:BAAALgAECgEJAgAAAA==.',
Ph='Phosphorus:BAACLgAFFH8WAAMLAAQJFhUrGwAQAQALAAQJihMrGwAQAQAcAAIJkhjbIwB7AAAuAAQKf1kAAwsACQnmIEcFALcCAAsACQnHHkcFALcCABwABgkqHIkYAHoBAAAA.',
Pl='Plagüë:BAACLgAFFH8RAAMTAAQJzRxOKQCsAAAGAAMJpCC6eAASAQATAAMJ3RBOKQCsAAAuAAQKf00AAwYACQmjJbcQAOcCAAYACQmjJbcQAOcCABMABQmbD0E5AK4AAAAA.Pleistarchus:BAAALgAECgYJCQAAAA==.',
Po='Poic:BAAALgADCgEJAQAAAA==.Polo:BAAALgADCgEJAQAAAA==.Poofighter:BAAALgAECgMJBwABLgAFFAIJCAAHAAohAA==.Poonan:BAAALgAECgYJBgAAAA==.',
Pp='Ppgangandlaw:BAAALgADCgEJAQAAAA==.',
Pr='Precious:BAABLgAECn8lAAIeAAgJNxayIwADAgAeAAgJNxayIwADAgAAAA==.Primalistic:BAAALgADCgUJBQABLgAFFAQJCQAbAPwKAA==.Primàl:BAABLgAECn8sAAIJAAYJBRv2NADUAQAJAAYJBRv2NADUAQAAAA==.Prowar:BAAALgAECgUJBQAAAA==.',
Pu='Punchinbag:BAAALgADCgYJBgAAAA==.Purifieds:BAAALgADCgEJAQAAAA==.',
['Pà']='Pàladin:BAAALgAECgEJAQAAAA==.',
Qs='Qsrqasda:BAABLgAECn8VAAITAAYJ4QXnPwCPAAATAAYJ4QXnPwCPAAAAAA==.',
Qt='Qtmenopaws:BAAALgAECgQJAwAAAA==.Qtptt:BAACLgAFFH8XAAIBAAMJKyNJHQAPAQABAAMJKyNJHQAPAQAuAAQKf0AAAgEACQmMI4gJAAYDAAEACQmMI4gJAAYDAAAA.',
Ra='Ragedeath:BAABLgAFFH8JAAITAAMJuA+3LACWAAATAAMJuA+3LACWAAABLgAFFAQJBAAKAAAAAA==.Ragedh:BAAALgAECgIJAgABLgAFFAQJBAAKAAAAAA==.Ragemonk:BAAALgADCgQJBAABLgAFFAQJBAAKAAAAAA==.Rageshaman:BAAALgAFFAQJBAAAAA==.Rasmong:BAABLgAECn8YAAIhAAkJyRAJHwC1AQAhAAkJyRAJHwC1AQAAAA==.Ravinsinda:BAAALgAECgYJBgAAAA==.Ravinursula:BAAALgAECgYJDwAAAA==.Rawrsaur:BAAALgAECgcJDQAAAA==.',
Re='Really:BAAALgADCgYJBgABLgAECgEJAQAKAAAAAA==.Reallyhpal:BAAALgAECgEJAQAAAA==.Redder:BAAALgAECgEJAQAAAA==.Remin:BAAALgADCgkJHAAAAA==.Remun:BAAALgADCgEJAQAAAA==.Retaliator:BAABLgAECn9AAAMNAAgJeRiFBwBFAQANAAgJeRiFBwBFAQASAAMJuAwQOQB6AAAAAA==.Reuuín:BAAALgAECggJDAABLgAECggJGQAMABwZAA==.Revan:BAAALgAECgYJBwAAAA==.',
Rh='Rhýs:BAAALgAECgYJBgAAAA==.',
Ri='Rih:BAAALgADCgMJBQAAAA==.Ripits:BAAALgADCgcJCAABLgAECgEJAQAKAAAAAA==.Risky:BAAALgAECgkJAwABLgAFFAIJAwAKAAAAAA==.Riskyfist:BAAALgAECgcJAgAAAA==.Risquae:BAAALgAECgIJAwAAAA==.',
Ro='Roadrashnuts:BAAALgAECgUJBwAAAA==.Rocc:BAAALgAECgcJBAAAAA==.Rocketeer:BAABLgAECn8nAAIbAAgJGg1rnABBAQAbAAgJGg1rnABBAQAAAA==.Romulis:BAAALgAECgEJAQAAAA==.Ronburgundii:BAAALgAECgEJAQAAAA==.',
Ru='Rudrya:BAABLgAECn8UAAInAAgJcAfhEwB8AQAnAAgJcAfhEwB8AQAAAA==.Rumpkey:BAAALgADCgcJCgAAAA==.Runalish:BAAALgAECgEJAQAAAA==.Runarinis:BAAALgADCgIJAgAAAA==.',
Ry='Rynopinn:BAACLgAFFH8JAAIJAAMJIhZ/OgDEAAAJAAMJIhZ/OgDEAAAuAAQKf0YABAkACAnqIxkLAOgCAAkACAnqIxkLAOgCAB8ABwm6GwANAOYBABUAAgn4F6llAIYAAAAA.Ryxn:BAAALgADCgYJBgAAAA==.',
Sa='Sacredstud:BAAALgADCgEJAQAAAA==.Saeed:BAAALgAECgEJAQAAAA==.Saelylasia:BAAALgAECgQJBQAAAA==.Sajaboy:BAAALgAECgMJBAAAAA==.Samusaran:BAAALgADCgEJAQAAAA==.Sans:BAAALgAECgcJBwAAAA==.Sarrania:BAAALgAECgUJBQAAAA==.Sartha:BAABLgAECn8rAAINAAkJuhiPMAA+AgANAAkJuhiPMAA+AgAAAA==.Sasuka:BAAALgAECgkJDQAAAA==.Satsu:BAAALgAECgEJAQAAAA==.',
Sc='Scatherlia:BAAALgADCgYJBQABLgAECgQJBQAKAAAAAA==.Sco:BAAALgADCgEJAQABLgAECgYJDQAKAAAAAA==.Screwthebull:BAAALgAECgQJBAAAAA==.Scrumpvincet:BAAALgADCgUJBQAAAA==.',
Se='Sectiondk:BAAALgAECgYJEwAAAA==.Sedda:BAACLgAFFH8bAAINAAgJSSHqCwAeAgANAAgJSSHqCwAeAgAuAAQKfy0AAg0ACAmnJc4GAGMDAA0ACAmnJc4GAGMDAAAA.Seigfreid:BAAALgAECgYJCAAAAA==.Sensual:BAACLgAFFH8QAAISAAQJDQgtDQCnAAASAAQJDQgtDQCnAAAuAAQKf0kAAhIACQlTFOsSAJoBABIACQlTFOsSAJoBAAAA.Seraphina:BAAALgAECgYJDgAAAA==.Sessano:BAAALgAECgYJDQAAAA==.Sesshomaru:BAACLgAFFH8IAAMHAAIJCiGiLgBQAAAWAAEJ0CNDKgBQAAAHAAIJXhyiLgBQAAAuAAQKf1MAAwcACQnUIxcTAOcCAAcACAm3IRcTAOcCABYACAkvJGoMAGACAAAA.',
Sh='Shadoly:BAAALgAECgcJEQAAAA==.Shadowboss:BAABLgAECn8iAAIEAAYJixGTQQAJAQAEAAYJixGTQQAJAQAAAA==.Shamhspriest:BAAALgAECgUJBQAAAA==.Shamnslam:BAAALgAECgEJAQAAAA==.Shang:BAACLgAFFH8XAAQVAAUJGCUkBACRAQAVAAUJGCUkBACRAQAfAAEJhiD3GQBhAAAJAAEJswMIewApAAAuAAQKfzQABRUACQlMJWUCAE8DABUACQlMJWUCAE8DABkAAwm+Hqc9ALAAAB8AAQndJU4FAG4AAAkAAgnDEmXNADcAAAAA.Shiftchi:BAAALgAECgYJBwAAAA==.Shirona:BAACLgAFFH8FAAIHAAIJgx6tbACyAAAHAAIJgx6tbACyAAAuAAQKfzwAAgcACQnpIYIHABcDAAcACQnpIYIHABcDAAAA.Shockazulu:BAAALgAECgEJAQAAAA==.Showstop:BAAALgAECgEJAQAAAA==.Shyvanna:BAABLgAECn8mAAMmAAkJyBGCJAC5AQAmAAkJyBGCJAC5AQAlAAQJ0wonHQBkAAAAAA==.Sháman:BAAALgAECgUJBAAAAA==.Shïnïgämï:BAABLgAECn8WAAIoAAYJiCAvCQDeAQAoAAYJiCAvCQDeAQABLgAFFAIJBgAOABwcAA==.Shøøtinlåvå:BAAALgADCgcJBwAAAA==.',
Si='Siare:BAABLgAECn8fAAIBAAkJihsFAQCTAgABAAkJihsFAQCTAgAAAA==.Sigarda:BAAALgAECgUJCAAAAA==.Silica:BAAALgAECgMJAwAAAA==.Silvershot:BAAALgADCgUJBQAAAA==.Siner:BAAALgAECgUJCAAAAA==.',
Sk='Skeeter:BAABLgAECn8+AAQkAAkJXR2SAwBZAgAkAAkJBRqSAwBZAgABAAkJWxhVSADBAQAjAAcJJx1CDACYAQAAAA==.Skiadrum:BAACLgAFFH8FAAIhAAMJgQGlOQBgAAAhAAMJgQGlOQBgAAAuAAQKf0IAAx4ACQl+FMIpAN4BAB4ACAnXEsIpAN4BACEABAlBCRJnAIgAAAAA.Skoliro:BAAALgAECgcJCgAAAA==.Skorch:BAAALgADCgkJEAABLgAFFAQJCQAbAPwKAA==.',
Sm='Smotts:BAAALgAECgkJDwAAAA==.Smòtts:BAABLgAECn8qAAIZAAkJnh5uAAC6AgAZAAkJnh5uAAC6AgAAAA==.',
Sn='Snizard:BAABLgAECn8iAAICAAcJ9hxfNwAAAgACAAcJ9hxfNwAAAgAAAA==.Snizorc:BAAALgAECgEJAQAAAA==.Snuggiepoo:BAABLgAECn8kAAMDAAkJsh6hCwC1AgADAAgJ5CChCwC1AgAEAAYJgRWiWgCrAAAAAA==.',
So='Songbirds:BAAALgADCgcJDQAAAA==.Sonichoos:BAAALgAECgUJDAAAAA==.Sophiel:BAACLgAFFH8JAAIHAAMJRBlWFgDrAAAHAAMJRBlWFgDrAAAuAAQKfyQAAgcACAktG+YmADACAAcACAktG+YmADACAAAA.Sosthenna:BAAALgADCgkJCQAAAA==.Soulbark:BAAALgAECgMJAwABLgAECgQJBAAKAAAAAQ==.Souleater:BAAALgADCgMJAwAAAA==.Soulforged:BAAALgADCgcJCwABLgAECgQJBAAKAAAAAA==.Soulreaver:BAAALgAECgcJCAAAAA==.Soulweaver:BAAALgAECgQJBAAAAQ==.',
Sp='Sparrowhåwk:BAAALgADCgUJBgAAAA==.Spicymustard:BAAALgAECgEJAgAAAA==.Spongebill:BAAALgADCgEJAQAAAA==.Spàdes:BAABLgAECn8cAAMRAAcJxxoyMgCDAQARAAYJbhsyMgCDAQALAAMJbBILSACrAAAAAA==.',
St='Starel:BAAALgAECgQJBAAAAA==.Stellanoova:BAAALgAECgcJDwABLgAECggJFgAmAEoUAA==.Stevebushami:BAAALgAECgYJEAAAAA==.Stuwu:BAAALgAECgMJAwAAAA==.',
Su='Submistive:BAEALgAECgMJBAABLgAFFAQJCwAMAB0WAA==.Suffers:BAAALgAFFAEJAQAAAA==.Suou:BAAALgADCgcJCQABLgAECgEJAgAKAAAAAA==.Surj:BAABLgAECn8mAAMcAAYJPBxEAgAuAQAcAAYJghpEAgAuAQARAAUJFg+5aQC6AAAAAA==.',
Sv='Svmii:BAAALgADCgcJCgAAAA==.',
Sy='Sycther:BAAALgADCgEJAQABLgAFFAMJCQAJACIWAA==.',
Ta='Taazdingo:BAABLgAECn8YAAIZAAYJLRydAQCVAQAZAAYJLRydAQCVAQAAAA==.Taikuri:BAAALgAECggJDwABLgAECgkJHwABAIobAA==.Taliela:BAAALgAECgQJBAAAAA==.Tanddralndra:BAAALgAECgUJBwAAAA==.Tanklilbaby:BAAALgAECgEJAQAAAA==.Tannia:BAAALgADCgcJDgAAAA==.Taxgirl:BAACLgAFFH8YAAMGAAUJiRyeUQBOAQAGAAUJiRyeUQBOAQAUAAEJsQOXLAA3AAAuAAQKfygAAgYACAlAJWISAA0DAAYACAlAJWISAA0DAAAA.Taxxwomann:BAAALgAFFAEJAQABLgAFFAUJGAAGAIkcAA==.',
Te='Teabear:BAAALgAFFAMJBAAAAA==.Tealzin:BAAALgAECgEJAQAAAA==.Telandrî:BAAALgADCgIJAgAAAA==.Teralion:BAAALgAECgMJBgAAAA==.',
Th='Thaeldrik:BAAALgADCgcJCgAAAA==.Thaldreaux:BAAALgAECgMJBAAAAA==.Thefirst:BAAALgAECgMJBwABLgAECgYJIgAEAIsRAA==.Theleon:BAABLgAECn8dAAIVAAgJQg9sLwBiAQAVAAgJQg9sLwBiAQAAAA==.Theßoss:BAAALgAECgMJAwABLgAECgYJIgAEAIsRAA==.Thordrin:BAABLgAECn8yAAIIAAcJ/CQzCgDoAgAIAAcJ/CQzCgDoAgAAAA==.Thorlan:BAAALgADCgYJCAAAAA==.Thrasherzs:BAAALgAECgUJDQAAAA==.Thryen:BAAALgAECgYJDAAAAA==.Thunder:BAAALgADCgQJBAABLgAECgcJCgAKAAAAAA==.Thundergrasp:BAACLgAFFH8LAAMnAAgJBwt8AwCcAQAnAAgJBwt8AwCcAQAdAAIJPATaFgBjAAAuAAQKfxsAAicABwkNG9YPALQBACcABwkNG9YPALQBAAAA.',
Ti='Tianhe:BAAALgAECgMJAwAAAA==.Tiarisaril:BAAALgAECgYJBgAAAA==.Tigercita:BAAALgAECgMJAgAAAA==.Tippah:BAAALgAECgEJAwAAAA==.Tippers:BAAALgAECgEJAQAAAA==.',
Tj='Tjsneckbeard:BAAALgAECgEJAQAAAA==.',
To='Toe:BAABLgAFFH8FAAIGAAIJrRTFxwCdAAAGAAIJrRTFxwCdAAAAAA==.Tonkah:BAAALgAECgUJBQABLgAECggJEQAKAAAAAA==.Toobestake:BAAALgAFFAMJAwABLgAFFAUJGAACAIkjAA==.Topenga:BAACLgAFFH8WAAICAAQJvBmJNABFAQACAAQJvBmJNABFAQAuAAQKf0wAAgIACQnXH2kSAKQCAAIACQnXH2kSAKQCAAAA.Tosem:BAAALgAECgcJBwAAAA==.Touchypope:BAAALgADCgYJCwAAAA==.',
Tr='Treeage:BAAALgADCgMJAwAAAA==.Triggerd:BAAALgADCgEJAQAAAA==.Trunks:BAAALgADCgQJBAAAAA==.Trylok:BAAALgADCgEJAQAAAA==.Trüst:BAAALgAECggJDgAAAA==.',
Tw='Twicelife:BAABLgAECn8ZAAIOAAgJ0R3wFgCSAgAOAAgJ0R3wFgCSAgABLgAFFAQJFgALABYVAA==.',
Ty='Tyrygosa:BAAALgAECgUJBQABLgAFFAQJEAABAMEWAA==.',
['Tå']='Tånk:BAAALgAECggJEwAAAA==.',
Un='Undread:BAAALgAFFAEJAQABLgAFFAUJDwARAGQdAA==.Uneedsummilk:BAAALgADCgcJBwAAAA==.Unholyapollo:BAAALgADCgYJCwAAAA==.',
Ur='Urthstripe:BAABLgAECn8vAAQJAAkJxBWuHABhAgAJAAkJxBWuHABhAgAVAAIJMgMIjwAxAAAfAAEJiwUxZQAaAAAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAcJDwAGAPAXAA==.Vain:BAAALgAECgEJAgAAAA==.Valle:BAAALgAECgIJAwABLgAFFAgJIQAEAGQaAA==.Valoria:BAAALgAECgMJCQABLgAFFAgJIQAEAGQaAA==.',
Ve='Veil:BAAALgAECgIJCAABLgAFFAgJIQAEAGQaAA==.Velarenea:BAAALgADCgEJAQAAAA==.Velgabrine:BAAALgAECgYJDAABLgAFFAQJEQANADsjAA==.Veraani:BAAALgAECgYJBgAAAA==.Verra:BAAALgADCgYJBgAAAA==.',
Vi='Vil:BAAALgADCgcJBgAAAA==.Virlan:BAAALgADCgQJBAAAAA==.Viserion:BAABLgAECn8WAAMmAAgJShQxPgAxAQAmAAcJZBIxPgAxAQAiAAYJ2AzgIADtAAAAAA==.',
Vo='Voidchaosfan:BAAALgAECgYJDAAAAA==.',
Vu='Vue:BAACLgAFFH8TAAIIAAQJQxMiJwDpAAAIAAQJQxMiJwDpAAAuAAQKf0YAAggACQkkGzYfAB8CAAgACQkkGzYfAB8CAAAA.Vuldin:BAAALgAECgEJAgAAAA==.',
['Vö']='Völdemört:BAAALgADCgIJAgAAAA==.',
Wa='Wakasham:BAACLgAFFH8fAAInAAcJSCJbAAABAgAnAAcJSCJbAAABAgAuAAQKfzEAAicACQk9Jp4BAFMDACcACQk9Jp4BAFMDAAAA.Wardemon:BAAALgADCgIJAgAAAA==.Wardrake:BAAALgAECgQJBAAAAA==.',
We='Wehonoryou:BAABLgAECn8YAAIWAAYJ9CHYGAAAAgAWAAYJ9CHYGAAAAgAAAA==.Wetard:BAAALgADCgIJAgAAAA==.',
Wi='Willbyers:BAAALgAECgEJAQAAAA==.Winterloom:BAAALgAECgYJBgAAAA==.',
Wo='Wolfpacked:BAACLgAFFH8GAAIOAAIJHByYWgCXAAAOAAIJHByYWgCXAAAuAAQKfygAAg4ACQlBIDMJAB8DAA4ACQlBIDMJAB8DAAAA.Wolfzbåin:BAAALgAECgQJBAAAAA==.',
Wr='Wroot:BAAALgADCgYJCQAAAA==.Wrotten:BAABLgAECn8WAAIjAAgJ6RcFCwCtAQAjAAgJ6RcFCwCtAQAAAA==.',
Wu='Wunderlust:BAACLgAFFH8PAAIbAAQJhxfwUwA1AQAbAAQJhxfwUwA1AQAuAAQKf0QAAhsACQmFISYcAAYDABsACQmFISYcAAYDAAAA.',
Xe='Xemon:BAAALgAECgIJAgAAAA==.',
Xi='Xilyana:BAAALgAECgQJBAAAAA==.',
Xm='Xmatick:BAAALgAECgcJCQAAAA==.',
Xs='Xscrats:BAAALgAECgkJCAAAAA==.',
Ye='Yellowshaman:BAACLgAFFH8nAAIdAAYJiB+VDwCzAQAdAAYJiB+VDwCzAQAuAAQKfzIAAh0ACQk3IkQMANcCAB0ACQk3IkQMANcCAAAA.Yerac:BAAALgAECgEJAQAAAA==.',
Yu='Yukikage:BAAALgAECgMJAwAAAA==.Yutdaeng:BAAALgAECgMJBAAAAA==.',
Yv='Yvent:BAAALgADCgIJAgAAAA==.Yvraine:BAAALgAECgYJEgAAAA==.',
Za='Zakcarii:BAAALgADCgMJCAAAAA==.Zakin:BAAALgADCgcJBwAAAA==.Zalicy:BAAALgAECgYJEwAAAA==.Zalogar:BAAALgAECgcJCgAAAA==.Zapper:BAAALgAECgYJEAAAAA==.',
Zb='Zbarbb:BAAALgADCgUJBQAAAA==.',
Ze='Zealot:BAAALgAECgEJAQAAAA==.Zeeasyez:BAAALgAECgYJEwAAAA==.Zestul:BAAALgADCgEJAQAAAA==.',
Zh='Zhane:BAAALgADCgYJBwAAAA==.',
Zo='Zordon:BAAALgAECgYJEwAAAA==.',
Zs='Zslol:BAAALgAECgEJAQAAAA==.',
Zu='Zugg:BAAALgAECgMJBgABLgAFFAgJIQAEAGQaAA==.Zuriznikov:BAAALgAECgYJBwABLgAECggJFgAmAEoUAA==.',
['Ån']='Ångie:BAAALgADCgMJAwAAAA==.',
['Øf']='Øffspeck:BAABLgAECn8hAAQBAAkJVhweLgBVAgABAAgJwxgeLgBVAgAjAAcJICFwDACVAQAkAAMJzh7MMAD3AAAAAA==.',
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
