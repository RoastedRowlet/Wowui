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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Priest-Discipline','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','DemonHunter-Devourer','Paladin-Holy','Druid-Restoration','Unknown-Unknown','Warrior-Arms','Rogue-Subtlety','Paladin-Retribution','Shaman-Restoration','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','Paladin-Protection','DeathKnight-Blood','DeathKnight-Frost','Druid-Balance','DemonHunter-Havoc','Rogue-Assassination','Mage-Arcane','Monk-Mistweaver','Druid-Guardian','Monk-Brewmaster','Mage-Frost','Warrior-Protection','Shaman-Elemental','Druid-Feral','Mage-Fire','Monk-Windwalker','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Evoker-Augmentation','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=46,date='2026-07-19',data={Aa='Aaron:BAAALgAECgcJBwABLgAECgkJIQABAFYcAA==.Aaronfreeze:BAACLgAFFH8JAAICAAMJehr0VgD5AAACAAMJehr0VgD5AAAuAAQKfzIAAgIACQn1HuIfAGgCAAIACQn1HuIfAGgCAAAA.',
Ab='Abrakazaam:BAAALgADCgEJAQAAAA==.',
Ad='Adrios:BAACLgAFFH8FAAIDAAIJmRQ3OwCTAAADAAIJmRQ3OwCTAAAuAAQKfyYABAMACQnQFvMZAAACAAMACAn9F/MZAAACAAQABwlRB9pTAMMAAAUAAwnKCCRpAIgAAAAA.',
Ae='Aetherion:BAAALgAECgMJBAAAAA==.',
Ai='Airorca:BAAALgAECgUJBQAAAA==.',
Aj='Ajaxz:BAABLgAECn8VAAIGAAkJ+RLTYADRAQAGAAkJ+RLTYADRAQAAAA==.',
Ak='Akaßoss:BAAALgAECgMJBAABLgAECgYJIgAEAIsRAA==.',
Al='Albedô:BAAALgAFFAIJAwABLgAFFAIJCAAHAAohAA==.Aliren:BAAALgAECgYJCgAAAA==.Allaway:BAAALgAECgEJAQAAAA==.Allformarc:BAAALgAFFAEJAQAAAA==.Allmaick:BAAALgAECgIJAQAAAA==.Alucard:BAABLgAFFH8bAAIIAAUJcw2aDAASAQAIAAUJcw2aDAASAQAAAA==.Alystrasza:BAABLgAECn8dAAIJAAYJvhbhRAB9AQAJAAYJvhbhRAB9AQAAAA==.',
Am='Amorlandian:BAAALgAECgMJAwAAAA==.',
An='Anatar:BAAALgAECgEJAQABLgAECgYJCAAKAAAAAA==.Antimovsky:BAAALgAECgcJEwAAAA==.',
Ap='Aphroditê:BAAALgAECgMJBAABLgAECgcJCQAKAAAAAA==.',
Aq='Aqours:BAAALgADCgcJBwABLgAECgEJAgAKAAAAAA==.',
Ar='Arcan:BAAALgAECgIJAgAAAA==.',
As='Astellia:BAAALgADCgEJAQAAAA==.',
Au='Augustine:BAAALgAECgEJAQAAAA==.Aullyura:BAAALgADCgcJBwAAAA==.Auroras:BAACLgAFFH8IAAMFAAMJUwbfKAB/AAAFAAMJUwbfKAB/AAAEAAEJmAEzQgAvAAAuAAQKfxcAAgUABwmEE5k0AGwBAAUABwmEE5k0AGwBAAAA.',
Av='Aviaria:BAAALgAECgQJBAAAAA==.Avìendha:BAAALgADCgQJBAAAAA==.',
Aw='Awsmpossum:BAAALgAECgEJAQAAAA==.',
Az='Azurah:BAAALgAECgEJAQAAAA==.',
['Aì']='Aìnzooalgown:BAABLgAFFH8SAAIGAAQJESGFPQB9AQAGAAQJESGFPQB9AQABLgAFFAIJCAAHAAohAA==.',
Ba='Babakubwa:BAAALgAECgMJAwAAAA==.Babylonfive:BAAALgAECgcJDQAAAA==.Balhair:BAAALgADCgYJBgAAAA==.Banger:BAAALgADCgEJAgAAAA==.Banish:BAAALgAECgMJAgABLgAECgcJCgAKAAAAAA==.Barragdan:BAAALgADCgEJAQAAAA==.Basandra:BAAALgAECgEJAQAAAA==.Basicc:BAAALgADCgUJBQAAAA==.',
Be='Beachbumm:BAAALgADCgEJAQAAAA==.Beastreminna:BAAALgADCgEJAQAAAA==.Belleta:BAAALgAECggJEQAAAA==.Berserk:BAEBLgAECn8iAAILAAYJ3SP5DgD+AQALAAYJ3SP5DgD+AQABLgAFFAUJDAAMABISAA==.Bertringer:BAAALgAECgEJAgABLgAECgYJBgAKAAAAAA==.',
Bi='Bigmack:BAAALgAECgYJCwABLgAFFAgJIwANACkWAA==.Bigpoppa:BAAALgAECgEJAgABLgAECgYJBgAKAAAAAA==.Bigwave:BAAALgAECgMJAwAAAA==.Bigwilli:BAABLgAECn8XAAIOAAkJHhK+OQDIAQAOAAkJHhK+OQDIAQAAAA==.Bingßong:BAAALgADCgcJFwAAAA==.Biscuit:BAACLgAFFH8SAAQPAAgJyBoYHADOAAACAAUJ4CDBWAD0AAAPAAQJVhQYHADOAAAQAAIJ+xHqKwCDAAAuAAQKfyIABA8ACAmPIycPAMgCAA8ACAl9HScPAMgCABAAAwnZH+45AO0AAAIABAk+HqCsAOoAAAAA.Bisha:BAABLgAECn9FAAMRAAkJEiHmDQDmAgARAAkJ9CDmDQDmAgALAAYJcBgnMgD/AAAAAA==.Bizcocho:BAAALgAECggJEgAAAA==.',
Bl='Black:BAAALgADCgEJAQAAAA==.Blinkaway:BAAALgAECgMJAgAAAA==.Bloodsimple:BAAALgADCgUJBQAAAA==.Blákers:BAABLgAFFH8OAAISAAQJuSQIAgCvAQASAAQJuSQIAgCvAQAAAA==.',
Bo='Boic:BAAALgADCgQJBAAAAA==.Bonesofdoom:BAACLgAFFH8HAAITAAMJ1w0iLQCUAAATAAMJ1w0iLQCUAAAuAAQKfyMAAxMACQkHGU8ZAJYBABMACAmJG08ZAJYBAAYAAgkYBtY/AV8AAAAA.Boogsta:BAACLgAFFH8QAAMUAAMJmgqBGADHAAAUAAMJmgqBGADHAAAGAAEJ7AIrJQExAAAuAAQKfzYAAhQACQlxFWgHACICABQACQlxFWgHACICAAAA.Boomkingobrr:BAACLgAFFH8HAAIVAAMJ9wj3NQCnAAAVAAMJ9wj3NQCnAAAuAAQKfxsAAhUACQkOHEQLAOECABUACQkOHEQLAOECAAAA.Boops:BAAALgAECgEJAQAAAA==.Bootysweatt:BAABLgAECn8aAAIWAAYJNhtqJACaAQAWAAYJNhtqJACaAQAAAA==.Boss:BAAALgAECgEJAQABLgAECgYJIgAEAIsRAA==.',
Br='Braahma:BAABLgAFFH8QAAQUAAkJ9SEZCAACAQAUAAYJVyEZCAACAQAGAAIJzyO8UgClAAATAAEJAAD4MAAAAAAAAA==.Brewnz:BAAALgAECgUJBgAAAA==.Brucewee:BAAALgAECgQJCgAAAA==.',
Bu='Buckits:BAAALgAECgcJEgAAAA==.Bunsey:BAAALgADCgIJAgAAAA==.Burnsx:BAAALgAECgUJCgABLgAFFAkJJQAHAKYeAA==.Bussyman:BAAALgAECgYJEQABLgAFFAMJCQAJACIWAA==.',
Bw='Bwoar:BAAALgAECgQJBgAAAA==.',
['Bø']='Bøw:BAAALgAECgMJAwAAAA==.',
['Bü']='Bübble:BAAALgADCgEJAQAAAA==.',
Ca='Caiandol:BAAALgAECgcJEAAAAA==.Capnmurloc:BAAALgAECgEJAgABLgAECgkJEwAKAAAAAA==.Captnmurloc:BAAALgAECgkJEwAAAA==.Capwackychan:BAAALgAECgEJAQABLgAECgkJEwAKAAAAAA==.Carl:BAAALgAECgEJAgABLgAFFAgJDwAXAMwbAA==.Carrach:BAAALgAECgIJBQAAAA==.Caveyodeler:BAAALgAECgQJCgAAAA==.',
Ce='Cedar:BAAALgAECgYJEAAAAA==.',
Ch='Cherga:BAAALgADCgYJBgAAAA==.Chinegga:BAAALgADCgYJBgAAAA==.Chitose:BAAALgADCgUJBQABLgAECgEJAgAKAAAAAA==.Chrapsasspee:BAAALgADCgcJGQAAAA==.Chrinn:BAAALgAECgEJAQAAAA==.',
Ci='Cindele:BAAALgADCgMJAwAAAA==.Cirvix:BAAALgAECgYJDAAAAA==.Cirxe:BAABLgAECn8kAAIYAAkJdRCABACtAQAYAAkJdRCABACtAQAAAA==.',
Cl='Clampire:BAAALgAECgQJBAAAAA==.Cliint:BAAALgAECgcJCwAAAA==.Cloúnt:BAAALgAECgEJAwABLgAFFAMJBwAVAPcIAA==.',
Co='Commotionn:BAAALgAECgQJBAAAAA==.Coms:BAAALgAECgYJCAAAAA==.Cooz:BAAALgAECgYJDwAAAA==.Corybooker:BAAALgAECgcJBAAAAA==.Cowdux:BAAALgAFFAEJAQAAAA==.Cowmoorem:BAAALgAECgEJAQAAAA==.',
Cr='Creamdragon:BAAALgADCgcJDQABLgAECggJQgAZAFEeAA==.',
Cu='Curuni:BAAALgAECgEJAQAAAA==.',
Cz='Czechhunter:BAAALgADCgUJBQAAAA==.',
['Cå']='Cåleb:BAAALgAECgEJAQAAAA==.',
['Cø']='Cønstance:BAABLgAECn8VAAIaAAcJvREUJgAjAQAaAAcJvREUJgAjAQAAAA==.',
Da='Daddyphat:BAABLgAECn8rAAIbAAgJrCS6BgDOAgAbAAgJrCS6BgDOAgAAAA==.Daddý:BAAALgAECgEJAQAAAA==.Dalight:BAABLgAECn8XAAIIAAYJKiYPDwCdAgAIAAYJKiYPDwCdAgAAAA==.Dankins:BAACLgAFFH8dAAIOAAgJ2SKvAQDhAgAOAAgJ2SKvAQDhAgAuAAQKfxYAAg4ACAkGHfYZAEcCAA4ACAkGHfYZAEcCAAAA.',
De='Deathmager:BAABLgAECn89AAIcAAkJjBJ4SQD/AQAcAAkJjBJ4SQD/AQAAAA==.Deathtraper:BAAALgAECgcJDQAAAA==.Debur:BAAALgADCgEJAQAAAA==.Deltaka:BAAALgAECgEJAQAAAA==.Demonfella:BAAALgADCgMJAwAAAA==.Demonicpeach:BAABLgAECn8YAAIBAAcJwwv9rADpAAABAAcJwwv9rADpAAAAAA==.Denaian:BAAALgADCgYJBgAAAA==.Dethsent:BAAALgAECggJEQAAAA==.Dette:BAABLgAECn8dAAICAAkJvBUrLgAkAgACAAkJvBUrLgAkAgAAAA==.Devilchaser:BAAALgAECggJDgAAAA==.Devourer:BAABLgAECn8VAAIHAAcJjg+mbQBaAQAHAAcJjg+mbQBaAQAAAA==.',
Dh='Dhtank:BAAALgAECgEJAQAAAA==.',
Di='Diaval:BAAALgADCgIJAgABLgAECgkJLAABAFsTAA==.Dinosforlife:BAAALgAECgYJDAAAAA==.',
Dk='Dkboss:BAAALgAECgIJAgABLgAECgYJIgAEAIsRAA==.',
Do='Donzilly:BAAALgAECgYJDgAAAA==.Doreme:BAAALgADCgIJAgAAAA==.Dorgrim:BAAALgAECgUJDAAAAA==.Doyueventank:BAAALgAECgEJAgAAAA==.',
Dr='Drafted:BAAALgAECgcJEAAAAA==.Drax:BAAALgAECgMJAwAAAA==.Drewmcmoo:BAAALgADCgcJBgAAAA==.Drsath:BAAALgADCgcJBwAAAA==.Drunkorca:BAAALgADCgUJBQAAAA==.Drüìd:BAAALgAFFAIJAgAAAA==.',
Ea='Earnar:BAAALgADCgYJDAAAAA==.',
Ed='Edarix:BAAALgADCggJDAABLgAECggJQQANANoYAA==.Edstark:BAAALgAECgUJCAAAAA==.',
Ei='Eiliyah:BAABLgAECn8yAAMIAAgJehz0FgBaAgAIAAgJehz0FgBaAgANAAIJHwIaWgElAAAAAA==.',
Ek='Ekmek:BAAALgAECgEJAQAAAA==.',
El='Elabernathy:BAABLgAECn80AAICAAkJrhiDHQB0AgACAAkJrhiDHQB0AgAAAA==.Elenay:BAABLgAECn8UAAIJAAgJqR6QIwAuAgAJAAgJqR6QIwAuAgAAAA==.Elesia:BAAALgAECgkJEgAAAA==.Elfussy:BAAALgAECgEJAQAAAA==.Elgoku:BAAALgAECgQJCgABLgAECgUJDAAKAAAAAA==.Eliarssande:BAAALgAECgMJAwAAAA==.Elinay:BAAALgAECgQJBAABLgAECggJFAAJAKkeAA==.Elixia:BAABLgAECn8gAAIWAAgJKBBxCQDTAAAWAAgJKBBxCQDTAAAAAA==.Elpatron:BAABLgAFFH8NAAIJAAUJOxBrDQAsAQAJAAUJOxBrDQAsAQAAAA==.Elylanea:BAAALgAECgUJDgAAAA==.',
Em='Emulsdeath:BAABLgAECn8UAAMTAAgJKCFPEwDcAQATAAcJLB5PEwDcAQAGAAYJ8iCEawCOAQABLgAFFAQJEQANADsjAA==.Emulsifier:BAACLgAFFH8RAAINAAQJOyMZHQCUAQANAAQJOyMZHQCUAQAuAAQKfzAAAg0ACAmFJgMNAPwCAA0ACAmFJgMNAPwCAAAA.',
En='Endboss:BAAALgADCgEJAQABLgAECgYJIgAEAIsRAA==.Ennoa:BAAALgAECgEJAQAAAA==.',
Er='Ergen:BAACLgAFFH8dAAIQAAYJBxdYEQA8AQAQAAYJBxdYEQA8AQAuAAQKfyoAAhAACAlvIaUGAJcCABAACAlvIaUGAJcCAAAA.',
Eu='Eusexua:BAAALgAECgQJBQABLgAECgcJCgAKAAAAAA==.',
Ex='Expiatory:BAAALgAECgYJCgAAAA==.',
Fa='Faielle:BAAALgAECgEJAQAAAA==.Fairbear:BAABLgAECn8dAAQRAAYJ+ByHOQBgAQARAAYJ+ByHOQBgAQALAAEJZA5tPgA7AAAdAAEJ6Qc6XgAbAAAAAA==.Faustt:BAAALgAECgUJBwAAAA==.',
Fi='Filthyfabio:BAAALgADCgcJEQAAAA==.Finester:BAACLgAFFH8MAAIMAAQJdh8tEgB9AQAMAAQJdh8tEgB9AQAuAAQKfxkAAgwACQlbITEBAF4CAAwACQlbITEBAF4CAAAA.Fireburr:BAAALgAECgMJAwAAAA==.',
Fl='Flatline:BAAALgAECgcJEgAAAA==.Fløw:BAAALgAECgMJCgAAAA==.',
Fr='Fragglerott:BAABLgAECn8cAAMOAAkJdxJ9gwDYAAAOAAUJWBF9gwDYAAAeAAgJ1AqdZgCyAAAAAA==.Frati:BAAALgAECgEJAQAAAA==.Friedchickn:BAAALgAECgQJCAAAAA==.Frostboss:BAAALgADCgEJAQABLgAECgYJIgAEAIsRAA==.Frosttrinity:BAAALgADCgUJBAAAAA==.',
Fu='Funslinger:BAAALgAECgQJDAAAAA==.',
Ga='Gaffz:BAAALgAECgEJAgAAAA==.Galannar:BAAALgAECggJDQAAAA==.Galvrax:BAAALgAECgUJCgAAAA==.Gast:BAACLgAFFH8QAAIRAAUJZB3nGQBKAQARAAUJZB3nGQBKAQAuAAQKfzgAAxEACQnZIN4JAMUCABEACQnZIN4JAMUCAB0ABAmpFuA1AKAAAAAA.',
Ge='Gearwick:BAAALgADCgYJBwABLgAECgcJJgAIAFAhAA==.',
Gh='Ghstfacekila:BAAALgADCgEJAQAAAA==.',
Go='Gorska:BAACLgAFFH8HAAIeAAMJJBGvGAC6AAAeAAMJJBGvGAC6AAAuAAQKfzgAAh4ACQl8HScQAHICAB4ACQl8HScQAHICAAAA.',
Gr='Grawm:BAABLgAECn8iAAMPAAkJqiKzHgAxAgAPAAgJSRWzHgAxAgACAAkJPiBvTwC0AQAAAA==.Greedory:BAAALgADCgIJAgAAAA==.Groot:BAAALgADCgUJBgAAAA==.Gruetss:BAAALgAECgQJBAAAAA==.',
Gu='Guilty:BAAALgAECgEJAwAAAA==.',
['Gä']='Gämbit:BAAALgADCgEJAQAAAA==.',
Ha='Hailbringer:BAAALgAECgcJDgAAAA==.Hakoona:BAABLgAECn8yAAIbAAkJFxrGEQApAgAbAAkJFxrGEQApAgAAAA==.Hanginaround:BAAALgAECgEJAQAAAA==.Hangman:BAACLgAFFH8bAAIIAAQJ8SVXEQCrAQAIAAQJ8SVXEQCrAQAuAAQKfyEAAwgACQmLJBACAJADAAgACQmLJBACAJADAA0ABAklDR4gAZMAAAEuAAUUAwkJAAkAIhYA.Hanni:BAABLgAECn8dAAIPAAgJUhyUCwCuAQAPAAgJUhyUCwCuAQAAAA==.Haveaburitto:BAACLgAFFH8NAAIcAAQJWBxMXAAmAQAcAAQJWBxMXAAmAQAuAAQKfygAAhwACAk0JXkMAGEDABwACAk0JXkMAGEDAAAA.Hawktoetem:BAAALgAECgUJCAABLgAECgYJHQARAPgcAA==.Hawktoouh:BAACLgAFFH8HAAMFAAMJlxnGCwDWAAAFAAMJlxnGCwDWAAADAAEJ2gHKMQAlAAAuAAQKfyMABAUACQkuHOEAAOkCAAUACQkuHOEAAOkCAAMABwnGDscGAFcBAAQAAgn9Fb8RAIIAAAEuAAUUAwkQABQAmgoA.',
He='Healmemaybe:BAABLgAECn8bAAIJAAYJQiP8IgAxAgAJAAYJQiP8IgAxAgAAAA==.Healthyadult:BAAALgAECgMJBQAAAA==.Hellshand:BAAALgAECgYJDAAAAA==.Heracles:BAAALgAECgQJBAAAAA==.Heretic:BAAALgAECgEJAQAAAA==.',
Hi='Hickscale:BAAALgADCgMJAwAAAA==.',
Ho='Holycøw:BAAALgADCgMJAwAAAA==.Holydefender:BAAALgADCgcJDQAAAA==.Holyhands:BAAALgADCgYJBgAAAA==.Holyholyholy:BAAALgAECggJEgAAAA==.Honest:BAAALgADCgMJAwAAAA==.',
Hu='Hunniee:BAAALgAECgEJAQAAAA==.Huntrix:BAAALgADCgcJEgAAAA==.Huntër:BAAALgAFFAQJBAAAAA==.',
Ib='Ibringchaos:BAAALgAECggJEAAAAA==.',
Ic='Icedatt:BAABLgAECn8VAAMGAAUJ8QIpKAF5AAAGAAUJ7AIpKAF5AAATAAUJcwGQVABIAAAAAA==.Icefire:BAAALgADCgUJBAAAAA==.',
Ik='Ikur:BAACLgAFFH8PAAIIAAQJrxtgHQAyAQAIAAQJrxtgHQAyAQAuAAQKfzsAAggACQmTHpMHABMDAAgACQmTHpMHABMDAAAA.',
Il='Ilinia:BAAALgAECgYJCAABLgAECgcJFAAOAEIZAA==.Illhealutoo:BAAALgAFFAEJAQAAAA==.',
Im='Imsteve:BAAALgAECgUJBQAAAA==.',
In='Infoxicated:BAAALgADCgcJCAABLgAECgkJJAADALIeAA==.Insîght:BAAALgAECgQJCAAAAA==.',
Ip='Ipopkidneys:BAACLgAFFH8VAAMMAAcJ1SFiDQC8AQAMAAYJlSFiDQC8AQAXAAMJjB0lBwDxAAAuAAQKfycAAwwACQnhJYQMANACAAwACQnhJYQMANACABcAAQn1IyQfAGUAAAAA.',
Ir='Iroi:BAAALgAECgIJBQAAAA==.',
Is='Iskur:BAABLgAECn8mAAMOAAgJ4BgbIwA8AgAOAAgJ4BgbIwA8AgAeAAMJMQ26dgCJAAABLgAFFAQJDwAIAK8bAA==.Isuck:BAAALgAFFAIJAgAAAA==.Isurr:BAABLgAECn8iAAIZAAcJnhK+OQCLAQAZAAcJnhK+OQCLAQABLgAFFAQJDwAIAK8bAA==.',
It='Itakecandle:BAAALgAECgUJBwABLgAECgUJDAAKAAAAAA==.',
Iv='Ivanapump:BAAALgAECgIJAgABLgAECgYJBgAKAAAAAA==.',
Ja='Jackkal:BAAALgAECggJCgAAAA==.Jadethecat:BAAALgADCgMJAwAAAA==.Jakbis:BAAALgADCgEJAQAAAA==.Jakychan:BAAALgAECgEJAQAAAA==.Jaldiar:BAAALgADCgcJBwABLgAECgYJBgAKAAAAAA==.Jametrok:BAAALgAECgEJAQAAAA==.Jazbek:BAAALgAECgQJDgAAAA==.Jazzonus:BAAALgAECgQJBAAAAA==.',
Je='Jefferey:BAAALgADCgMJAwAAAA==.Jennyanydots:BAAALgAECgMJBQABLgAFFAkJLQAEAD8ZAA==.Jeriçho:BAAALgADCgYJBgAAAA==.',
Jh='Jhonwick:BAAALgAECgIJAgAAAA==.',
Ji='Jippedo:BAAALgAECgYJAgABLgAECgcJBAAKAAAAAA==.Jiraîya:BAAALgAECgQJBQAAAA==.',
Jo='Jordak:BAABLgAECn8oAAIJAAkJBBwrDgDnAgAJAAkJBBwrDgDnAgAAAA==.Jorolee:BAAALgADCgEJAQAAAA==.',
Ju='Jumbok:BAAALgAECgEJAQAAAA==.Just:BAAALgAECgEJAQAAAA==.',
Ka='Kaast:BAAALgAECgEJAQAAAA==.Kaddiya:BAAALgAECgYJEgAAAA==.Kagonstrasza:BAAALgAECgQJBAAAAA==.Kallistos:BAABLgAECn8gAAIOAAcJER3uLQD/AQAOAAcJER3uLQD/AQAAAA==.Kangaroo:BAAALgAECgUJBQAAAA==.Kariza:BAAALgAECgQJBgAAAA==.Karunik:BAAALgADCgYJBgABLgAECgcJCgAKAAAAAA==.Kasst:BAAALgAECgQJBQAAAA==.Kasstt:BAAALgAECgUJBQAAAA==.',
Ke='Kelenheller:BAAALgAECgUJDQAAAA==.Key:BAAALgAFFAMJAwAAAA==.',
Kh='Khione:BAAALgAECgMJAwAAAA==.Khthonios:BAAALgAECgEJAQAAAA==.',
Ki='Kiba:BAAALgADCgIJAgABLgAECggJQgAZAFEeAA==.Kibblerina:BAAALgADCgcJBwAAAA==.Kiranam:BAABLgAECn8fAAQaAAgJ8xKSCADbAAAfAAgJqQqdEQCTAQAaAAcJjhGSCADbAAAVAAIJWwfecQBZAAAAAA==.',
Kn='Knarth:BAABLgAECn9CAAIgAAkJ5x71AADZAgAgAAkJ5x71AADZAgAAAA==.Kníght:BAABLgAFFH8NAAIGAAUJVwmXMAABAQAGAAUJVwmXMAABAQAAAA==.',
Ko='Koisy:BAAALgAECgcJEAABLgAECggJFAAJAKkeAA==.Kole:BAAALgAECgEJAQAAAA==.Koopa:BAABLgAECn8rAAIRAAkJHyVcBQALAwARAAkJHyVcBQALAwAAAA==.',
Kr='Krasul:BAACLgAFFH8WAAMOAAYJtBRDJQBWAQAOAAYJtBRDJQBWAQAeAAIJ7QkOSQBsAAAuAAQKfx8AAw4ACAkXIecIAOgCAA4ACAkXIecIAOgCAB4ABgm/HPIxAJQBAAAA.Krenthok:BAABLgAECn8eAAIBAAgJiQe3iQAmAQABAAgJiQe3iQAmAQAAAA==.',
Ku='Kuraha:BAAALgAECgQJBAAAAA==.Kuruni:BAAALgAECgYJCgAAAA==.Kushar:BAAALgAECgQJBQABLgAECgkJGQAhAEkRAA==.',
Ky='Kyuketsuki:BAAALgAFFAIJAwAAAA==.',
La='Lachance:BAAALgADCgYJBgAAAA==.Ladieraven:BAAALgADCgUJBQAAAA==.Large:BAAALgADCgYJBgAAAA==.Largemann:BAAALgAFFAMJAwABLgAFFAUJGAAGAIkcAA==.Lathspell:BAABLgAECn8yAAIcAAkJtiAMJgCDAgAcAAkJtiAMJgCDAgAAAA==.Lazyevoker:BAAALgADCgQJBAABLgAECgEJAQAKAAAAAA==.',
Le='Leahan:BAABLgAECn8UAAINAAUJfgfgKACHAAANAAUJfgfgKACHAAAAAA==.Leloo:BAAALgADCgYJCgABLgAECgIJAwAKAAAAAA==.',
Lh='Lhureciv:BAACLgAFFH8VAAMEAAQJERl9FQA5AQAEAAQJERl9FQA5AQADAAEJKRuVSQBFAAAuAAQKf0sAAwQACQnVI80GAB4DAAQACQnVI80GAB4DAAMABgn7HjAjAHoBAAAA.',
Li='Lightchaser:BAAALgADCgMJAgAAAA==.Lightfkyou:BAAALgADCgcJCgAAAA==.Lihvurce:BAABLgAECn8fAAMNAAgJWR0/MgA3AgANAAgJWR0/MgA3AgAIAAQJpR0FSwBMAQABLgAFFAQJFQAEABEZAA==.Lillianna:BAACLgAFFH8HAAIMAAIJrBJ7MACkAAAMAAIJrBJ7MACkAAAuAAQKf0sAAgwACAk8HlQBAEACAAwACAk8HlQBAEACAAAA.Lingchi:BAAALgAECgQJBgAAAA==.',
Ll='Llew:BAAALgAECgYJCQAAAA==.',
Lo='Loenhart:BAAALgAECgEJAQAAAA==.Lolkurtone:BAAALgAECgIJAgAAAA==.',
Lu='Luciaan:BAAALgADCgkJGQAAAA==.Lucrative:BAAALgADCgcJDQAAAA==.Lug:BAAALgAECgEJAQAAAA==.Lulue:BAAALgADCgQJBAAAAA==.Luminari:BAAALgADCgUJBQAAAA==.Lunastorm:BAACLgAFFH8OAAIiAAQJLxPoGAAIAQAiAAQJLxPoGAAIAQAuAAQKfzgAAiIACQnQIooCAD8DACIACQnQIooCAD8DAAAA.Luponero:BAACLgAFFH8fAAMCAAYJ3CHZHQCNAQACAAUJiSPZHQCNAQAPAAIJBhFOEwBXAAAuAAQKfyIAAw8ACAnnHuYQALUCAA8ACAl6HeYQALUCAAIAAwnNHxqXABIBAAAA.',
Ly='Lynney:BAAALgADCgYJBwAAAA==.',
Ma='Macmn:BAACLgAFFH8UAAIeAAYJGxoMEwCLAQAeAAYJGxoMEwCLAQAuAAQKfygAAh4ABwnAJGULAOICAB4ABwnAJGULAOICAAAA.Mageyouacake:BAAALgADCgMJAwAAAA==.Magicard:BAABLgAECn8fAAIcAAgJjg5IewCBAQAcAAgJjg5IewCBAQAAAA==.Makesfood:BAABLgAECn8qAAIcAAcJZBeSdADpAQAcAAcJZBeSdADpAQAAAA==.Mamaheals:BAABLgAECn8rAAIFAAkJSxpbFAAzAgAFAAkJSxpbFAAzAgAAAA==.Mandos:BAAALgAECgYJCAAAAA==.Mantistabogn:BAAALgAFFAEJAQAAAA==.Maor:BAABLgAECn8XAAINAAgJlxcuUADxAQANAAgJlxcuUADxAQAAAA==.March:BAAALgADCgEJAQAAAA==.Markeisha:BAAALgAECgQJCAABLgAECgYJDAAKAAAAAA==.',
Me='Mechz:BAAALgAECgYJBgABLgAFFAQJCQAcAPwKAA==.Mechzician:BAACLgAFFH8JAAIcAAQJ/Ao8dwDsAAAcAAQJ/Ao8dwDsAAAuAAQKfzgAAhwACAlwGXtZAC0CABwACAlwGXtZAC0CAAAA.Mechzlock:BAAALgADCgEJAQABLgAFFAQJCQAcAPwKAA==.Melinoe:BAAALgAECgEJAQAAAA==.Merlerk:BAAALgADCgYJBgABLgAFFAgJJwAFAKYVAA==.Merlini:BAABLgAECn8dAAMEAAgJWRYLJACpAQAEAAcJ0xgLJACpAQADAAUJThaqPAAbAQAAAA==.Metrohexual:BAAALgAECgYJCAAAAA==.Mets:BAAALgAECgYJCwABLgAECgkJHwABAJgbAA==.',
Mi='Microplastic:BAAALgAECgUJBQAAAA==.Micspanky:BAAALgAECggJEgAAAA==.Mistynight:BAAALgAECgMJAwAAAA==.Mithrandi:BAAALgAECgYJCQAAAA==.Mitzis:BAABLgAFFH8NAAICAAMJ8x89UgAFAQACAAMJ8x89UgAFAQAAAA==.',
Mo='Moltii:BAAALgADCgMJAwAAAA==.Moltiy:BAAALgADCggJFQAAAA==.Moltten:BAAALgAECgYJDAAAAA==.Mornhathor:BAAALgAECggJDgABLgAECgYJCAAKAAAAAA==.',
Mu='Mufinblaster:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgADCgIJBgAAAA==.Musnicker:BAAALgAECgQJBwABLgAECgkJOAAPAIYWAA==.',
My='Myro:BAACLgAFFH8UAAMOAAQJ3B+fJwBJAQAOAAQJ3B+fJwBJAQAeAAIJZRTKQgB/AAAuAAQKfxsAAg4ABwm/JsEHAPkCAA4ABwm/JsEHAPkCAAAA.',
['Mè']='Mètis:BAAALgAECgcJCQAAAA==.',
['Mø']='Møhax:BAAALgAECgYJBgAAAA==.',
Na='Nadnoo:BAAALgAECgMJAwAAAA==.Nanis:BAAALgAECgYJBwABLgAFFAYJIQAVANMlAA==.Narmer:BAAALgAECgIJAgAAAA==.',
Ne='Neel:BAAALgADCgQJBQAAAA==.Nervhoost:BAAALgADCgMJAwAAAA==.Neuropolis:BAAALgADCgcJFQAAAA==.Neuroscience:BAAALgADCgMJAwAAAA==.Neurotics:BAABLgAECn9eAAQjAAkJNyYqAAAJAwAjAAkJlyUqAAAJAwAkAAcJsSMLBABHAgABAAYJ1BuyHgBiAAAAAA==.Neò:BAABLgAECn8YAAMlAAYJvBC1EAD/AAAlAAYJXw61EAD/AAAmAAEJ/hQHkwA1AAAAAA==.',
Ni='Niesh:BAAALgAECgEJBwAAAA==.Nightrush:BAAALgADCgEJAQAAAA==.Nineoneone:BAABLgAECn9eAAMFAAkJZBpuAQCOAgAFAAkJZBpuAQCOAgADAAQJjgPqRQCLAAAAAA==.Ninjá:BAAALgAECgEJAQAAAA==.',
No='Nobledecay:BAAALgAECgQJBQAAAA==.Nocturne:BAAALgAECgEJAwAAAA==.Norí:BAAALgAECgIJAgAAAA==.',
Nu='Nubbletcake:BAAALgADCgEJAQABLgAECgkJJAADALIeAA==.Nula:BAAALgAECgMJBQABLgAFFAkJLQAEAD8ZAA==.',
Ny='Nylveth:BAACLgAFFH8QAAIEAAUJzw9EHQAGAQAEAAUJzw9EHQAGAQAuAAQKfyoAAgQACQkAHXQQAFgCAAQACQkAHXQQAFgCAAEuAAUUCAkNACcAtgwA.',
Oa='Oathatone:BAAALgAECgUJCAAAAA==.',
Oc='Ocra:BAABLgAECn8gAAInAAkJ9g59DgDJAQAnAAkJ9g59DgDJAQABLgAFFAQJFgACALwZAA==.Octaviå:BAAALgAECgEJAQABLgAECgcJCQAKAAAAAA==.',
Of='Offspeck:BAAALgAECgIJAgABLgAECgkJIQABAFYcAA==.',
Ou='Outtkast:BAAALgAECgIJAgAAAA==.Outtkastt:BAAALgAECgcJDQAAAA==.Ouutkast:BAAALgAECgIJBAAAAA==.',
Oz='Ozwald:BAABLgAECn81AAIQAAkJchx/EAAqAgAQAAkJchx/EAAqAgAAAA==.',
Pa='Pallyangel:BAAALgADCgcJDwAAAA==.Pandemul:BAAALgAECgMJAwABLgAFFAQJEQANADsjAA==.Pastasaladin:BAAALgADCgEJAQAAAA==.Patrio:BAACLgAFFH8IAAIiAAMJGg24IQCXAAAiAAMJGg24IQCXAAAuAAQKfywAAiIACQllGfUHAHMCACIACQllGfUHAHMCAAEuAAUUBQkNAAkAOxAA.Pawkclaw:BAAALgAECgYJBgAAAA==.',
Pe='Peaceonea:BAABLgAECn8bAAIHAAkJrgQYnQDoAAAHAAkJrgQYnQDoAAAAAA==.Peachaid:BAECLgAFFH8cAAMDAAgJ9Rd6CQCNAgADAAgJ9Rd6CQCNAgAFAAEJRQgoOgAtAAAuAAQKfzAAAwMACQlVImoFADIDAAMACQlVImoFADIDAAUABgkYHSglAMABAAAA.Peatri:BAAALgAFFAEJAQAAAA==.Peetree:BAACLgAFFH8RAAIOAAQJOBlTLwAlAQAOAAQJOBlTLwAlAQAuAAQKfx4AAg4ACAnMH/EBALICAA4ACAnMH/EBALICAAAA.Pekin:BAAALgAECgEJAgAAAA==.',
Ph='Phosphorus:BAACLgAFFH8WAAMLAAQJFhUrGwAQAQALAAQJihMrGwAQAQAdAAIJkhjbIwB7AAAuAAQKf1kAAwsACQnmIEcFALcCAAsACQnHHkcFALcCAB0ABgkqHIkYAHoBAAAA.',
Pl='Plagüë:BAACLgAFFH8RAAMTAAQJzRxOKQCsAAAGAAMJpCC6eAASAQATAAMJ3RBOKQCsAAAuAAQKf00AAwYACQmjJbcQAOcCAAYACQmjJbcQAOcCABMABQmbD0E5AK4AAAAA.Pleistarchus:BAAALgAECgYJCQAAAA==.',
Po='Poic:BAAALgADCgEJAQAAAA==.Polo:BAAALgADCgEJAQAAAA==.Poofighter:BAAALgAECgMJBwABLgAFFAIJCAAHAAohAA==.Poonan:BAAALgAECgYJBgAAAA==.',
Pp='Ppgangandlaw:BAAALgADCgEJAQAAAA==.',
Pr='Precious:BAABLgAECn8tAAIZAAkJNBb8BwCIAQAZAAkJNBb8BwCIAQAAAA==.Prezfaux:BAAALgAECgQJBAAAAA==.Primalistic:BAAALgADCgUJBQABLgAFFAQJCQAcAPwKAA==.Primàl:BAABLgAECn8sAAIJAAYJBRv2NADUAQAJAAYJBRv2NADUAQAAAA==.Prowar:BAAALgAECgUJBQABLgAECgYJIgAEAIsRAA==.',
Pu='Punchinbag:BAAALgADCgYJBgAAAA==.Purifieds:BAAALgADCgEJAQAAAA==.',
['Pà']='Pàladin:BAAALgAFFAEJAgAAAA==.',
Qs='Qsrqasda:BAABLgAECn8VAAITAAYJ4QXnPwCPAAATAAYJ4QXnPwCPAAAAAA==.',
Qt='Qtmenopaws:BAAALgAECgQJAwAAAA==.Qtptt:BAACLgAFFH8bAAIBAAQJBCQwHAAgAQABAAQJBCQwHAAgAQAuAAQKf0AAAgEACQmMI4gJAAYDAAEACQmMI4gJAAYDAAAA.',
Ra='Ragedeath:BAABLgAFFH8JAAITAAMJuA+3LACWAAATAAMJuA+3LACWAAABLgAFFAQJBAAKAAAAAA==.Ragedh:BAAALgAECgIJAgABLgAFFAQJBAAKAAAAAA==.Ragemonk:BAAALgADCgQJBAABLgAFFAQJBAAKAAAAAA==.Rageshaman:BAAALgAFFAQJBAAAAA==.Rasmong:BAABLgAECn8ZAAIhAAkJSREJHwC1AQAhAAkJSREJHwC1AQAAAA==.Ravinsinda:BAAALgAECgYJBgAAAA==.Ravinursula:BAABLgAECn8VAAMjAAcJCQ3MGQDyAAAjAAYJtArMGQDyAAAkAAcJYgl4BwCYAAAAAA==.Rawrsaur:BAAALgAECgcJDQAAAA==.',
Re='Really:BAAALgADCgYJBgABLgAECgEJAQAKAAAAAA==.Reallyhpal:BAAALgAECgEJAQAAAA==.Reddbull:BAAALgADCgYJBgAAAA==.Redder:BAAALgAECgEJAQAAAA==.Remin:BAAALgAECgcJDQAAAA==.Remun:BAAALgADCgMJAwAAAA==.Retaliator:BAABLgAECn9BAAMNAAgJ2hgqCwB7AQANAAgJ2hgqCwB7AQASAAMJuAwQOQB6AAAAAA==.Reuuín:BAAALgAECggJDAABLgAECggJGQAMABwZAA==.Revan:BAAALgAECgYJBwAAAA==.',
Rh='Rhýs:BAAALgAECgYJBgAAAA==.',
Ri='Rih:BAAALgADCgMJBQAAAA==.Ripits:BAAALgADCgcJCAABLgAECgEJAQAKAAAAAA==.Risky:BAAALgAECgkJAwABLgAFFAIJAwAKAAAAAA==.Riskyfist:BAAALgAECgcJAgAAAA==.Risquae:BAAALgAECgIJAwAAAA==.',
Ro='Roadrashnuts:BAAALgAECgUJBwAAAA==.Rocc:BAAALgAECgcJBAAAAA==.Rocketeer:BAABLgAECn8nAAIcAAgJGg1rnABBAQAcAAgJGg1rnABBAQAAAA==.Romulis:BAAALgAECgEJAQAAAA==.Ronburgundii:BAAALgAECgEJAQAAAA==.Roosk:BAAALgAECgEJAQAAAA==.',
Ru='Rudrya:BAABLgAECn8UAAInAAgJcAfhEwB8AQAnAAgJcAfhEwB8AQAAAA==.Rumpkey:BAAALgADCgcJCgAAAA==.Runalish:BAAALgAECgEJAQAAAA==.Runarinis:BAAALgADCgIJAgAAAA==.',
Ry='Rynopinn:BAACLgAFFH8JAAIJAAMJIhZ/OgDEAAAJAAMJIhZ/OgDEAAAuAAQKf0YABAkACAnqIxkLAOgCAAkACAnqIxkLAOgCAB8ABwm6GwANAOYBABUAAgn4F6llAIYAAAAA.Ryxn:BAAALgADCgYJBgAAAA==.',
['Rí']='Ríco:BAAALgAECgYJCwAAAA==.',
Sa='Sacredstud:BAAALgADCgEJAQAAAA==.Saeed:BAAALgAECgEJAQAAAA==.Saelylasia:BAAALgAECgQJBQAAAA==.Sajaboy:BAAALgAECgMJBAAAAA==.Samusaran:BAAALgADCgEJAQAAAA==.Sans:BAAALgAECgcJBwAAAA==.Sapphier:BAAALgAECgUJCAAAAA==.Sarrania:BAAALgAECgUJBQAAAA==.Sartha:BAABLgAECn8rAAINAAkJuhiPMAA+AgANAAkJuhiPMAA+AgAAAA==.Sasuka:BAAALgAECgkJDgAAAA==.Satsu:BAAALgAECgEJAQAAAA==.',
Sc='Scatherlia:BAAALgADCgYJBQABLgAECgQJBQAKAAAAAA==.Sco:BAAALgADCgEJAQABLgAECgYJDQAKAAAAAA==.Scratchit:BAAALgAECgEJAQAAAA==.Screwthebull:BAAALgAECgQJBAAAAA==.Scrumpdragon:BAAALgAECgIJAgAAAA==.Scrumpvincet:BAAALgADCgUJBQABLgAECgIJAgAKAAAAAA==.',
Se='Sectiondk:BAAALgAECgYJEwAAAA==.Sedda:BAACLgAFFH8bAAINAAgJSSHqCwAeAgANAAgJSSHqCwAeAgAuAAQKfy0AAg0ACAmnJc4GAGMDAA0ACAmnJc4GAGMDAAAA.Seigfreid:BAAALgAECgYJCAAAAA==.Sensual:BAACLgAFFH8QAAISAAQJDQgtDQCnAAASAAQJDQgtDQCnAAAuAAQKf0kAAhIACQlTFOsSAJoBABIACQlTFOsSAJoBAAAA.Seraphina:BAAALgAECgYJDgAAAA==.Sessano:BAAALgAECgYJDQAAAA==.Sesshomaru:BAACLgAFFH8IAAMHAAIJCiHqRQBGAAAWAAEJ0CNDKgBQAAAHAAIJXhzqRQBGAAAuAAQKf1MAAwcACQnUIxcTAOcCAAcACAm3IRcTAOcCABYACAkvJGoMAGACAAAA.',
Sh='Shadoly:BAAALgAECgcJEQAAAA==.Shadowboss:BAABLgAECn8iAAIEAAYJixGTQQAJAQAEAAYJixGTQQAJAQAAAA==.Shamh:BAAALgAECgIJAgAAAA==.Shamhspriest:BAAALgAECgYJBgAAAA==.Shamnslam:BAAALgAECgEJAQAAAA==.Shang:BAACLgAFFH8hAAUVAAYJ0yXoAwAYAgAVAAYJ0yXoAwAYAgAfAAEJhiD3GQBhAAAaAAEJ2x5PHABWAAAJAAEJswMIewApAAAuAAQKfzYABRUACQlMJWUCAE8DABUACQlMJWUCAE8DABoAAwm+Hqc9ALAAAB8AAQndJTgKAGoAAAkAAgnDEmXNADcAAAAA.Shiftchi:BAAALgAECgYJBwAAAA==.Shirona:BAACLgAFFH8FAAIHAAIJgx6tbACyAAAHAAIJgx6tbACyAAAuAAQKfzwAAgcACQnpIYIHABcDAAcACQnpIYIHABcDAAAA.Shmized:BAAALgADCgIJAgAAAA==.Shockazulu:BAAALgAECgEJAQAAAA==.Showstop:BAAALgAECgEJAQAAAA==.Shyne:BAAALgADCgMJAwAAAA==.Shyvanna:BAABLgAECn8mAAMmAAkJyBGCJAC5AQAmAAkJyBGCJAC5AQAlAAQJ0wonHQBkAAAAAA==.Sháman:BAAALgAECgUJBAAAAA==.Shïnïgämï:BAABLgAECn8WAAIoAAYJiCAvCQDeAQAoAAYJiCAvCQDeAQABLgAFFAIJBgAOABwcAA==.Shøøtinlåvå:BAAALgADCgcJBwAAAA==.',
Si='Siare:BAABLgAECn8fAAIBAAkJmBtBAgCHAgABAAkJmBtBAgCHAgAAAA==.Sigarda:BAAALgAECgUJCAAAAA==.Silica:BAAALgAECgMJAwAAAA==.Silvershot:BAAALgADCgUJBQAAAA==.Siner:BAAALgAECgUJCAAAAA==.',
Sk='Skeeter:BAACLgAFFH8GAAMBAAQJugiMQACDAAABAAQJugiMQACDAAAkAAEJAA2JJgBIAAAuAAQKfz4ABCQACQldHZIDAFkCACQACQkFGpIDAFkCAAEACQlbGFVIAMEBACMABwknHUIMAJgBAAAA.Skiadrum:BAACLgAFFH8FAAIhAAMJgQGlOQBgAAAhAAMJgQGlOQBgAAAuAAQKf0IAAxkACQl+FMIpAN4BABkACAnXEsIpAN4BACEABAlBCRJnAIgAAAAA.Skoliro:BAAALgAECgcJCgAAAA==.Skorch:BAAALgADCgkJEAABLgAFFAQJCQAcAPwKAA==.',
Sm='Smotts:BAABLgAECn8VAAMiAAkJ8hKwDgDjAQAiAAkJ8hKwDgDjAQAmAAMJNAZxUwB5AAAAAA==.Smòtts:BAABLgAECn82AAIaAAkJgiGPAAD3AgAaAAkJgiGPAAD3AgAAAA==.',
Sn='Snizard:BAABLgAECn8pAAICAAgJnB76BgDrAQACAAgJnB76BgDrAQAAAA==.Snizorc:BAAALgAECgEJAQAAAA==.Snuggiepoo:BAABLgAECn8kAAMDAAkJsh6hCwC1AgADAAgJ5CChCwC1AgAEAAYJgRWiWgCrAAAAAA==.',
So='Songbirds:BAAALgADCgcJDQAAAA==.Sonichoos:BAAALgAECgUJDAAAAA==.Sophiel:BAACLgAFFH8LAAIHAAMJRBlgJgDTAAAHAAMJRBlgJgDTAAAuAAQKfyQAAgcACAktG+YmADACAAcACAktG+YmADACAAAA.Sosthenna:BAAALgADCgkJCQAAAA==.Soulbark:BAAALgAECgMJAwABLgAECgQJBAAKAAAAAQ==.Souleater:BAAALgADCgMJAwAAAA==.Soulforged:BAAALgADCgcJCwABLgAECgQJBAAKAAAAAA==.Soulreaver:BAAALgAECgcJCAAAAA==.Soulweaver:BAAALgAECgQJBAAAAQ==.',
Sp='Sparrowhåwk:BAAALgADCgUJBgAAAA==.Spicymustard:BAAALgAECgEJAgAAAA==.Spongebill:BAAALgADCgEJAQAAAA==.Spàdes:BAABLgAECn8cAAMRAAcJxxoyMgCDAQARAAYJbhsyMgCDAQALAAMJbBILSACrAAAAAA==.',
St='Starel:BAAALgAECgQJBAAAAA==.Stellanoova:BAAALgAECgcJDwABLgAFFAQJBgAmAPkLAA==.Stevebushami:BAAALgAECgYJEAAAAA==.Stuwu:BAAALgAECgMJBAAAAA==.',
Su='Submistive:BAEALgAECgQJBQABLgAFFAUJDAAMABISAA==.Suffers:BAAALgAFFAEJAQAAAA==.Suou:BAAALgADCgcJCQABLgAECgEJAgAKAAAAAA==.Surj:BAABLgAECn8mAAMdAAYJPBx2BAAnAQAdAAYJghp2BAAnAQARAAUJFg+5aQC6AAAAAA==.',
Sv='Svmii:BAAALgADCgcJCgAAAA==.',
Sy='Sycther:BAAALgADCgEJAQABLgAFFAMJCQAJACIWAA==.Syradori:BAAALgAECgEJAQAAAA==.',
Ta='Taazdingo:BAABLgAECn8ZAAIaAAYJjRxMAwCTAQAaAAYJjRxMAwCTAQAAAA==.Taikuri:BAAALgAECggJDwABLgAECgkJHwABAJgbAA==.Taliela:BAAALgAECgQJBAAAAA==.Tanddralndra:BAAALgAECgUJBwAAAA==.Tanklilbaby:BAAALgAECgEJAQAAAA==.Tannia:BAAALgAECgEJAwAAAA==.Taxgirl:BAACLgAFFH8YAAMGAAUJiRyeUQBOAQAGAAUJiRyeUQBOAQAUAAEJsQOXLAA3AAAuAAQKfygAAgYACAlAJWISAA0DAAYACAlAJWISAA0DAAAA.Taxxwomann:BAAALgAFFAEJAgABLgAFFAUJGAAGAIkcAA==.',
Te='Teabear:BAAALgAFFAMJBAAAAA==.Tealzin:BAAALgAECgEJAQAAAA==.Telandrî:BAAALgADCgIJAgAAAA==.Teralion:BAAALgAECgMJBgAAAA==.',
Th='Thaeldrik:BAAALgADCgcJCgAAAA==.Thaldreaux:BAAALgAECgMJBAAAAA==.Thefirst:BAAALgAECgMJBwABLgAECgYJIgAEAIsRAA==.Theleon:BAABLgAECn8dAAIVAAgJQg9sLwBiAQAVAAgJQg9sLwBiAQAAAA==.Theßoss:BAAALgAECgMJAwABLgAECgYJIgAEAIsRAA==.Thordrin:BAABLgAECn8yAAIIAAcJ/CQzCgDoAgAIAAcJ/CQzCgDoAgAAAA==.Thorlan:BAAALgADCgYJCAAAAA==.Thrasherzs:BAAALgAECgUJDQAAAA==.Thryen:BAAALgAECgcJEQAAAA==.Thunder:BAAALgADCgQJBAABLgAECgcJCgAKAAAAAA==.Thundergrasp:BAACLgAFFH8NAAMnAAgJtgx8AwCcAQAnAAgJBwt8AwCcAQAeAAIJjw9bIQB7AAAuAAQKfxsAAicABwkNG9YPALQBACcABwkNG9YPALQBAAAA.',
Ti='Tianhe:BAAALgAECgMJAwAAAA==.Tiarisaril:BAAALgAECgYJBgAAAA==.Tigercita:BAAALgAECgMJAgAAAA==.Tippah:BAAALgAECgEJAwAAAA==.Tippers:BAAALgAECgEJAQAAAA==.',
Tj='Tjsneckbeard:BAAALgAECgEJAQAAAA==.',
To='Toe:BAABLgAFFH8FAAIGAAIJrRTFxwCdAAAGAAIJrRTFxwCdAAAAAA==.Tonkah:BAAALgAECgUJBQABLgAECggJEQAKAAAAAA==.Toobestake:BAAALgAFFAMJBAABLgAFFAYJHwACANwhAA==.Topenga:BAACLgAFFH8WAAICAAQJvBmJNABFAQACAAQJvBmJNABFAQAuAAQKf0wAAgIACQnXH2kSAKQCAAIACQnXH2kSAKQCAAAA.Tosem:BAAALgAECgcJBwAAAA==.Touchypope:BAAALgADCgYJCwAAAA==.',
Tr='Treeage:BAAALgADCgMJAwAAAA==.Triggerd:BAAALgADCgEJAQAAAA==.Trunks:BAAALgADCgQJBAAAAA==.Trylok:BAAALgADCgEJAQAAAA==.Trüst:BAAALgAECggJDgAAAA==.',
Tw='Twicelife:BAABLgAECn8ZAAIOAAgJ0R3wFgCSAgAOAAgJ0R3wFgCSAgABLgAFFAQJFgALABYVAA==.',
Ty='Tyrygosa:BAAALgAECgUJBQABLgAFFAQJEAABAMEWAA==.',
['Tå']='Tånk:BAAALgAECggJEwAAAA==.',
['Tñ']='Tñt:BAAALgADCgQJBAABLgAECgkJIQABAFYcAA==.',
Un='Undread:BAAALgAFFAEJAQABLgAFFAUJEAARAGQdAA==.Uneedsummilk:BAAALgADCgcJBwAAAA==.Unholyapollo:BAAALgADCgYJCwAAAA==.',
Ur='Urthstripe:BAABLgAECn8vAAQJAAkJxBWuHABhAgAJAAkJxBWuHABhAgAVAAIJMgMIjwAxAAAfAAEJiwUxZQAaAAAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAcJEAAGABMYAA==.Vain:BAAALgAECgEJAgAAAA==.Valle:BAAALgAECgIJAwABLgAFFAkJLQAEAD8ZAA==.Valoria:BAAALgAECgMJCQABLgAFFAkJLQAEAD8ZAA==.',
Ve='Veil:BAAALgAECgIJCAABLgAFFAkJLQAEAD8ZAA==.Velarenea:BAAALgADCgEJAQAAAA==.Velgabrine:BAAALgAECgYJDAABLgAFFAQJEQANADsjAA==.Veraani:BAAALgAECgYJBgAAAA==.Verra:BAAALgADCgYJBgAAAA==.',
Vi='Vil:BAAALgADCgcJBgAAAA==.Virlan:BAAALgADCgQJBAAAAA==.Viserion:BAACLgAFFH8GAAMmAAMJ+QtHHwCnAAAmAAMJ+QtHHwCnAAAiAAEJfgYLGQAkAAAuAAQKfxYAAyYACAlKFDE+ADEBACYABwlkEjE+ADEBACIABgnYDOAgAO0AAAAA.',
Vo='Voidchaosfan:BAAALgAECgYJDAAAAA==.',
Vu='Vue:BAACLgAFFH8TAAIIAAQJQxMiJwDpAAAIAAQJQxMiJwDpAAAuAAQKf0YAAggACQkkGzYfAB8CAAgACQkkGzYfAB8CAAAA.Vuldin:BAAALgAECgEJAgAAAA==.',
['Væ']='Vælkor:BAAALgAFFAEJAQAAAA==.',
['Vö']='Völdemört:BAAALgADCgIJAgAAAA==.',
Wa='Wakasham:BAACLgAFFH8lAAInAAcJSCLgAAAPAgAnAAcJSCLgAAAPAgAuAAQKfzUAAicACQlCJp4BAFMDACcACQlCJp4BAFMDAAAA.Wardemon:BAAALgADCgIJAgAAAA==.Wardrake:BAAALgAECgQJBAAAAA==.',
We='Wehonoryou:BAABLgAECn8YAAIWAAYJ9CHYGAAAAgAWAAYJ9CHYGAAAAgAAAA==.Wetard:BAAALgADCgIJAgAAAA==.',
Wi='Willbyers:BAAALgAECgEJAQAAAA==.Winterloom:BAAALgAECgYJBgAAAA==.',
Wl='Wlock:BAAALgADCgIJAgAAAA==.',
Wo='Wolfpacked:BAACLgAFFH8GAAIOAAIJHByYWgCXAAAOAAIJHByYWgCXAAAuAAQKfygAAg4ACQlBIDMJAB8DAA4ACQlBIDMJAB8DAAAA.Wolfzbåin:BAAALgAECgQJBAAAAA==.',
Wr='Wroot:BAAALgADCgYJCQAAAA==.Wrotten:BAABLgAECn8WAAIjAAgJ6RcFCwCtAQAjAAgJ6RcFCwCtAQAAAA==.',
Wu='Wunderlust:BAACLgAFFH8PAAIcAAQJhxfwUwA1AQAcAAQJhxfwUwA1AQAuAAQKf0QAAhwACQmFISYcAAYDABwACQmFISYcAAYDAAAA.',
Xe='Xemon:BAAALgAECgIJAgAAAA==.',
Xi='Xilyana:BAAALgAECgQJBAAAAA==.',
Xm='Xmatick:BAAALgAECgcJCQAAAA==.',
Xs='Xscrats:BAAALgAECgkJCAAAAA==.',
Ye='Yellowshaman:BAACLgAFFH8rAAIeAAgJuBiVDwCzAQAeAAgJuBiVDwCzAQAuAAQKfzIAAh4ACQk3IkQMANcCAB4ACQk3IkQMANcCAAAA.Yerac:BAAALgAECgEJAQAAAA==.',
Yu='Yukikage:BAAALgAECgMJAwAAAA==.Yutdaeng:BAAALgAECgMJBAAAAA==.',
Yv='Yvent:BAAALgADCgIJAgAAAA==.Yvraine:BAAALgAECgYJEgAAAA==.',
Za='Zakcarii:BAAALgADCgMJCAAAAA==.Zakin:BAAALgADCgcJBwAAAA==.Zalicy:BAAALgAECgYJEwAAAA==.Zalogar:BAAALgAECgcJCgAAAA==.Zapper:BAAALgAECgYJEAAAAA==.',
Zb='Zbarbb:BAAALgADCgUJBQAAAA==.',
Ze='Zealot:BAAALgAECgEJAQAAAA==.Zeeasyez:BAAALgAECgYJEwAAAA==.Zestul:BAAALgADCgEJAQAAAA==.',
Zh='Zhane:BAAALgADCgYJBwAAAA==.',
Zo='Zordon:BAAALgAECgYJEwAAAA==.',
Zs='Zslol:BAAALgAECgEJAQAAAA==.',
Zu='Zugg:BAAALgAECgMJBgABLgAFFAkJLQAEAD8ZAA==.Zuriznikov:BAAALgAFFAEJAQABLgAFFAQJBgAmAPkLAA==.',
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
