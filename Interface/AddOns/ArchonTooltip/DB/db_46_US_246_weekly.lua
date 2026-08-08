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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Priest-Discipline','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','DemonHunter-Devourer','Paladin-Holy','Druid-Restoration','Unknown-Unknown','Warrior-Arms','Rogue-Subtlety','Paladin-Retribution','Shaman-Restoration','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','Paladin-Protection','Mage-Frost','DeathKnight-Blood','DeathKnight-Frost','Druid-Balance','DemonHunter-Havoc','Rogue-Assassination','Mage-Arcane','Monk-Mistweaver','Druid-Guardian','Monk-Brewmaster','Druid-Feral','Warrior-Protection','Shaman-Elemental','Mage-Fire','Monk-Windwalker','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Evoker-Augmentation','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=46,date='2026-08-04',data={Aa='Aaron:BAAALgAECgcJBwABLgAECgkJIQABAFYcAA==.Aaronfreeze:BAACLgAFFH8JAAICAAMJehr0VgD5AAACAAMJehr0VgD5AAAuAAQKfzIAAgIACQn1HuIfAGgCAAIACQn1HuIfAGgCAAAA.',
Ab='Abrakazaam:BAAALgADCgEJAQAAAA==.',
Ad='Adrios:BAACLgAFFH8FAAIDAAIJmRQ3OwCTAAADAAIJmRQ3OwCTAAAuAAQKfyYABAMACQnQFvMZAAACAAMACAn9F/MZAAACAAQABwlRB9pTAMMAAAUAAwnKCCRpAIgAAAAA.',
Ae='Aetherion:BAAALgAECgMJBAAAAA==.',
Ai='Airorca:BAAALgAECgUJBQAAAA==.',
Aj='Ajaxz:BAABLgAECn8VAAIGAAkJ+RLTYADRAQAGAAkJ+RLTYADRAQAAAA==.',
Ak='Akaßoss:BAAALgAECgMJBAABLgAECgYJIgAEAIsRAA==.',
Al='Albedô:BAAALgAFFAIJAwABLgAFFAIJCAAHAAohAA==.Aliren:BAAALgAECgYJCgAAAA==.Allaway:BAAALgAECgEJAQAAAA==.Allformarc:BAAALgAFFAEJAQAAAA==.Allmaick:BAAALgAECgIJAQAAAA==.Alucard:BAABLgAFFH8bAAIIAAUJcw3sDgAFAQAIAAUJcw3sDgAFAQAAAA==.Alystrasza:BAABLgAECn8dAAIJAAYJvhbhRAB9AQAJAAYJvhbhRAB9AQAAAA==.',
Am='Ambivalent:BAAALgAECgEJAQAAAA==.Amorlandian:BAAALgAECgMJAwAAAA==.',
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
Be='Beachbumm:BAAALgADCgEJAQAAAA==.Beastreminna:BAAALgADCgEJAQAAAA==.Belleta:BAAALgAECggJEQAAAA==.Belligerente:BAAALgAECgEJAQAAAA==.Berserk:BAEBLgAECn8iAAILAAYJ3SP5DgD+AQALAAYJ3SP5DgD+AQABLgAFFAUJDAAMABISAA==.Bertringer:BAAALgAECgEJAgABLgAECgYJBgAKAAAAAA==.',
Bi='Bigmack:BAAALgAECgYJCwABLgAFFAgJIwANACkWAA==.Bigpoppa:BAAALgAECgEJAgABLgAECgYJBgAKAAAAAA==.Bigwave:BAAALgAECgQJBAAAAA==.Bigwilli:BAABLgAECn8YAAIOAAkJBBS+OQDIAQAOAAkJBBS+OQDIAQAAAA==.Bingßong:BAAALgADCgcJFwAAAA==.Biscuit:BAACLgAFFH8SAAQPAAgJyBoYHADOAAACAAUJ4CDBWAD0AAAPAAQJVhQYHADOAAAQAAIJ+xHqKwCDAAAuAAQKfyIABA8ACAmPIycPAMgCAA8ACAl9HScPAMgCABAAAwnZH+45AO0AAAIABAk+HqCsAOoAAAAA.Bisha:BAABLgAECn9FAAMRAAkJEiHmDQDmAgARAAkJ9CDmDQDmAgALAAYJcBgnMgD/AAAAAA==.Bizcocho:BAAALgAECggJEgAAAA==.',
Bl='Black:BAAALgADCgEJAQAAAA==.Blinkaway:BAAALgAECgMJAgAAAA==.Bloodsimple:BAAALgADCgUJBQAAAA==.Blákers:BAABLgAFFH8OAAISAAQJuSQIAgCvAQASAAQJuSQIAgCvAQABLgAFFAUJHAATAOYGAA==.',
Bo='Boic:BAAALgADCgQJBAAAAA==.Bonesofdoom:BAACLgAFFH8HAAIUAAMJ1w0iLQCUAAAUAAMJ1w0iLQCUAAAuAAQKfyMAAxQACQkHGU8ZAJYBABQACAmJG08ZAJYBAAYAAgkYBtY/AV8AAAAA.Boogsta:BAACLgAFFH8QAAMVAAMJmgqBGADHAAAVAAMJmgqBGADHAAAGAAEJ7AIrJQExAAAuAAQKfzYAAhUACQlxFWgHACICABUACQlxFWgHACICAAAA.Boomkingobrr:BAACLgAFFH8HAAIWAAMJ9wj3NQCnAAAWAAMJ9wj3NQCnAAAuAAQKfxsAAhYACQkOHEQLAOECABYACQkOHEQLAOECAAAA.Boops:BAAALgAECgEJAQAAAA==.Bootysweatt:BAABLgAECn8aAAIXAAYJNhtqJACaAQAXAAYJNhtqJACaAQAAAA==.Boss:BAAALgAECgEJAQABLgAECgYJIgAEAIsRAA==.',
Br='Braahma:BAABLgAFFH8SAAQVAAkJACN6BQBoAQAVAAYJvCJ6BQBoAQAGAAMJGSInNAAAAQAUAAEJAADxNgAAAAAAAA==.Brewnz:BAAALgAECgUJBgAAAA==.Brucewee:BAAALgAECgQJCgAAAA==.',
Bu='Buckits:BAAALgAECgcJEgAAAA==.Bunsey:BAAALgADCgIJAgAAAA==.Burnsx:BAAALgAECgUJCgABLgAFFAkJLwAHACYgAA==.Bussyman:BAAALgAECgYJEQABLgAFFAMJCQAJACIWAA==.',
Bw='Bwoar:BAAALgAECgQJBgAAAA==.',
['Bø']='Bøw:BAAALgAECgMJAwAAAA==.',
['Bü']='Bübble:BAAALgADCgEJAQAAAA==.',
Ca='Caiandol:BAABLgAECn8XAAIHAAcJRBXrCABpAQAHAAcJRBXrCABpAQAAAA==.Capnmurloc:BAAALgAECgEJAgABLgAECgkJEwAKAAAAAA==.Captnmurloc:BAAALgAECgkJEwAAAA==.Capwackychan:BAAALgAECgEJAQABLgAECgkJEwAKAAAAAA==.Carl:BAAALgAECgEJAgABLgAFFAkJEAAYAM4ZAA==.Carrach:BAAALgAECgIJBQAAAA==.Caveyodeler:BAAALgAECgQJCgAAAA==.',
Ce='Cedar:BAAALgAECggJEgAAAA==.',
Ch='Cherga:BAAALgADCgYJBgAAAA==.Chinegga:BAAALgADCgYJBgAAAA==.Chitose:BAAALgADCgUJBQABLgAECgEJAgAKAAAAAA==.Chrapsasspee:BAAALgADCgcJGQAAAA==.Chrinn:BAAALgAECgEJAQAAAA==.',
Ci='Cindele:BAAALgADCgMJAwAAAA==.Cirvix:BAAALgAECgYJDAAAAA==.Cirxe:BAABLgAECn8kAAIZAAkJdRCABACtAQAZAAkJdRCABACtAQAAAA==.',
Cl='Clampire:BAAALgAECgQJBAAAAA==.Cliint:BAAALgAECgcJCwAAAA==.Cloúnt:BAAALgAECgEJAwABLgAFFAMJBwAWAPcIAA==.',
Co='Commotionn:BAAALgAECgQJBAAAAA==.Coms:BAAALgAECgcJCQAAAA==.Cooz:BAAALgAECgYJDwAAAA==.Corybooker:BAAALgAECgcJBAAAAA==.Cowdux:BAAALgAFFAEJAQAAAA==.Cowmoorem:BAAALgAECgEJAQAAAA==.',
Cr='Creamdragon:BAAALgADCgcJDQABLgAECggJQgAaAFEeAA==.',
Cu='Curuni:BAAALgAECgEJAQAAAA==.',
Cz='Czechhunter:BAAALgADCgUJBQAAAA==.',
['Cå']='Cåleb:BAAALgAECgEJAQAAAA==.',
['Cø']='Cønstance:BAABLgAECn8VAAIbAAcJvREUJgAjAQAbAAcJvREUJgAjAQAAAA==.',
Da='Dabai:BAAALgADCgUJBQAAAA==.Daddyphat:BAABLgAECn8rAAIcAAgJrCS6BgDOAgAcAAgJrCS6BgDOAgAAAA==.Daddý:BAAALgAECgEJAQAAAA==.Dalight:BAABLgAECn8XAAIIAAYJKiYPDwCdAgAIAAYJKiYPDwCdAgAAAA==.Dankins:BAACLgAFFH8eAAIOAAkJ/yGvAQDhAgAOAAkJ/yGvAQDhAgAuAAQKfxYAAg4ACAkGHfYZAEcCAA4ACAkGHfYZAEcCAAAA.',
De='Deathmager:BAABLgAECn89AAITAAkJjBJ4SQD/AQATAAkJjBJ4SQD/AQAAAA==.Deathtraper:BAAALgAECgcJDQAAAA==.Debur:BAAALgADCgEJAQAAAA==.Deltaka:BAAALgAECgEJAQAAAA==.Demonfella:BAAALgADCgMJAwAAAA==.Demonicpeach:BAABLgAECn8YAAIBAAcJwwv9rADpAAABAAcJwwv9rADpAAAAAA==.Denaian:BAAALgAECgcJDQAAAA==.Dethsent:BAAALgAECggJEQAAAA==.Dette:BAABLgAECn8dAAICAAkJvBUrLgAkAgACAAkJvBUrLgAkAgAAAA==.Devilchaser:BAAALgAECggJDgAAAA==.Devourer:BAABLgAECn8VAAIHAAcJjg+mbQBaAQAHAAcJjg+mbQBaAQAAAA==.',
Dh='Dhtank:BAAALgAECgEJAQAAAA==.',
Di='Diaval:BAAALgADCgIJAgABLgAECgkJLAABAFsTAA==.Dinosforlife:BAAALgAECgYJDAAAAA==.',
Dk='Dkboss:BAAALgAECgIJAwABLgAECgYJIgAEAIsRAA==.',
Do='Donzilly:BAAALgAECgYJDgAAAA==.Doreme:BAAALgADCgIJAgAAAA==.Dorgrim:BAAALgAECgUJDAAAAA==.Doyueventank:BAAALgAECgEJAgAAAA==.',
Dr='Drafted:BAAALgAECgcJEAAAAA==.Drax:BAAALgAECgMJAwAAAA==.Drewmcmoo:BAAALgADCgcJBgAAAA==.Drsath:BAAALgADCgcJBwAAAA==.Drunkorca:BAAALgADCgUJBQAAAA==.Drüìd:BAABLgAFFH8LAAMdAAMJrBrpBADzAAAdAAMJrBrpBADzAAAbAAEJ1wT8NgAdAAAAAA==.',
Ea='Earnar:BAAALgADCgYJDAAAAA==.',
Ed='Edarix:BAAALgADCggJDAABLgAECggJQQANANoYAA==.Edstark:BAAALgAECgUJEAAAAA==.',
Ei='Eiliyah:BAABLgAECn8yAAMIAAgJehz0FgBaAgAIAAgJehz0FgBaAgANAAIJHwIaWgElAAAAAA==.',
Ek='Ekmek:BAAALgAECgEJAQAAAA==.',
El='Elabernathy:BAABLgAECn80AAICAAkJrhiDHQB0AgACAAkJrhiDHQB0AgAAAA==.Elenay:BAABLgAECn8WAAMJAAgJqR6QIwAuAgAJAAgJqR6QIwAuAgAdAAEJrCMtDABpAAAAAA==.Elesia:BAAALgAECgkJEgAAAA==.Elfussy:BAAALgAECgEJAQAAAA==.Elgoku:BAAALgAECgQJCgABLgAECgUJDAAKAAAAAA==.Eliarssande:BAAALgAECgMJAwAAAA==.Elinay:BAAALgAECgQJBAABLgAECggJFgAJAKkeAA==.Elixia:BAABLgAECn8gAAIXAAgJKBCACwDUAAAXAAgJKBCACwDUAAAAAA==.Elpatron:BAABLgAFFH8NAAIJAAUJOxDMDwAeAQAJAAUJOxDMDwAeAQAAAA==.Elylanea:BAAALgAECgUJDgAAAA==.',
Em='Emulsdeath:BAABLgAECn8UAAMUAAgJKCFPEwDcAQAUAAcJLB5PEwDcAQAGAAYJ8iCEawCOAQABLgAFFAQJEQANADsjAA==.Emulsifier:BAACLgAFFH8RAAINAAQJOyMZHQCUAQANAAQJOyMZHQCUAQAuAAQKfzAAAg0ACAmFJgMNAPwCAA0ACAmFJgMNAPwCAAAA.',
En='Endboss:BAAALgADCgEJAQABLgAECgYJIgAEAIsRAA==.Ennoa:BAAALgAECgEJAQAAAA==.',
Er='Ergen:BAACLgAFFH8dAAIQAAYJBxdYEQA8AQAQAAYJBxdYEQA8AQAuAAQKfyoAAhAACAlvIaUGAJcCABAACAlvIaUGAJcCAAAA.',
Eu='Eusexua:BAAALgAECgQJBQABLgAECgcJCgAKAAAAAA==.',
Ex='Expiatory:BAAALgAECgYJCgAAAA==.',
Fa='Faielle:BAAALgAECgEJAQAAAA==.Fairbear:BAABLgAECn8dAAQRAAYJ+ByHOQBgAQARAAYJ+ByHOQBgAQALAAEJZA5tPgA7AAAeAAEJ6Qc6XgAbAAAAAA==.Faustt:BAAALgAECgUJBwAAAA==.',
Fi='Filthyfabio:BAAALgADCgcJEQAAAA==.Finester:BAACLgAFFH8MAAIMAAQJdh8tEgB9AQAMAAQJdh8tEgB9AQAuAAQKfxkAAgwACQlbIYIBAFYCAAwACQlbIYIBAFYCAAAA.Fireburr:BAAALgAECgMJAwAAAA==.',
Fl='Flatline:BAAALgAECgcJEgAAAA==.Fløw:BAAALgAECgMJCgAAAA==.',
Fr='Fragglerott:BAABLgAECn8dAAMOAAkJQxV9gwDYAAAOAAUJWBF9gwDYAAAfAAgJAgydZgCyAAAAAA==.Frati:BAAALgAECgEJAQAAAA==.Friedchickn:BAAALgAECgQJCAAAAA==.Frostboss:BAAALgADCgEJAQABLgAECgYJIgAEAIsRAA==.Frosttrinity:BAAALgADCgUJBAAAAA==.',
Fu='Funslinger:BAAALgAECgQJDAAAAA==.',
Ga='Gaffz:BAAALgAECgEJAgAAAA==.Galannar:BAAALgAECggJDQAAAA==.Galvrax:BAAALgAECgUJCgAAAA==.Gast:BAACLgAFFH8QAAIRAAUJZB3nGQBKAQARAAUJZB3nGQBKAQAuAAQKfzgAAxEACQnZIN4JAMUCABEACQnZIN4JAMUCAB4ABAmpFuA1AKAAAAAA.',
Ge='Gearwick:BAAALgADCgYJBwABLgAECgcJJgAIAFAhAA==.',
Gh='Ghstfacekila:BAAALgADCgEJAQAAAA==.',
Go='Gorska:BAACLgAFFH8HAAIfAAMJJBGBHQCvAAAfAAMJJBGBHQCvAAAuAAQKfzgAAh8ACQl8HScQAHICAB8ACQl8HScQAHICAAAA.',
Gr='Grawm:BAABLgAECn8iAAMPAAkJqiKzHgAxAgAPAAgJSRWzHgAxAgACAAkJPiBvTwC0AQAAAA==.Greedory:BAAALgADCgIJAgAAAA==.Groot:BAAALgADCgUJBgAAAA==.Gruetss:BAAALgAECgQJBAAAAA==.',
Gu='Guilty:BAAALgAECgEJAwAAAA==.',
['Gä']='Gämbit:BAAALgADCgEJAQAAAA==.',
Ha='Hailbringer:BAAALgAECgcJDgAAAA==.Hakoona:BAABLgAECn8yAAIcAAkJFxrGEQApAgAcAAkJFxrGEQApAgAAAA==.Hanginaround:BAAALgAECgEJAQAAAA==.Hangman:BAACLgAFFH8bAAIIAAQJ8SVXEQCrAQAIAAQJ8SVXEQCrAQAuAAQKfyEAAwgACQmLJBACAJADAAgACQmLJBACAJADAA0ABAklDR4gAZMAAAEuAAUUAwkJAAkAIhYA.Hanni:BAABLgAECn8dAAIPAAgJUhyUCwCuAQAPAAgJUhyUCwCuAQAAAA==.Haveaburitto:BAACLgAFFH8NAAITAAQJWBxMXAAmAQATAAQJWBxMXAAmAQAuAAQKfygAAhMACAk0JXkMAGEDABMACAk0JXkMAGEDAAAA.Hawktoetem:BAAALgAECgUJCAABLgAECgYJHQARAPgcAA==.Hawktoouh:BAACLgAFFH8JAAMFAAMJYBtMDADfAAAFAAMJYBtMDADfAAADAAEJ2gHONgAlAAAuAAQKfyoABAUACQlAH7kAADYDAAUACQlAH7kAADYDAAMABwnGDmcIAFYBAAQAAgn9FYMVAIIAAAEuAAUUAwkQABUAmgoA.',
He='Healmemaybe:BAABLgAECn8bAAIJAAYJQiP8IgAxAgAJAAYJQiP8IgAxAgAAAA==.Healthyadult:BAAALgAECgMJBQAAAA==.Hellshand:BAAALgAECgYJDAAAAA==.Heracles:BAAALgAECgQJBAAAAA==.Heretic:BAAALgAECgEJAQAAAA==.',
Hi='Hickscale:BAAALgADCgMJAwAAAA==.',
Ho='Holycøw:BAAALgADCgMJAwAAAA==.Holydefender:BAAALgADCgcJDQAAAA==.Holyhands:BAAALgADCgYJBgAAAA==.Holyholyholy:BAAALgAECggJEgAAAA==.Honest:BAAALgADCgMJAwAAAA==.',
Hu='Hunniee:BAAALgAECgEJAQAAAA==.Huntrix:BAAALgADCgcJEgAAAA==.Huntër:BAABLgAFFH8HAAICAAUJWggyKgD2AAACAAUJWggyKgD2AAAAAA==.',
Ib='Ibringchaos:BAAALgAECggJEAAAAA==.',
Ic='Icedatt:BAABLgAECn8VAAMGAAUJ8QIpKAF5AAAGAAUJ7AIpKAF5AAAUAAUJcwGQVABIAAAAAA==.Icefire:BAAALgADCgUJBAAAAA==.',
Ik='Ikur:BAACLgAFFH8PAAIIAAQJrxtgHQAyAQAIAAQJrxtgHQAyAQAuAAQKfzsAAggACQmTHpMHABMDAAgACQmTHpMHABMDAAAA.',
Il='Ilinia:BAAALgAECgYJCAABLgAFFAEJAQAKAAAAAA==.Illhealutoo:BAAALgAFFAEJAQAAAA==.',
Im='Imsteve:BAAALgAECgUJBQAAAA==.',
In='Infoxicated:BAAALgADCgcJCAABLgAECgkJJAADALIeAA==.Insîght:BAAALgAECgQJCAAAAA==.',
Ip='Ipopkidneys:BAACLgAFFH8WAAMMAAgJGB5iDQC8AQAMAAcJRB1iDQC8AQAYAAMJjB0lBwDxAAAuAAQKfycAAwwACQnhJYQMANACAAwACQnhJYQMANACABgAAQn1IyQfAGUAAAAA.',
Ir='Iroi:BAAALgAECgIJBQAAAA==.',
Is='Iskur:BAABLgAECn8mAAMOAAgJ4BgbIwA8AgAOAAgJ4BgbIwA8AgAfAAMJMQ26dgCJAAABLgAFFAQJDwAIAK8bAA==.Isuck:BAAALgAFFAIJAgAAAA==.Isurr:BAABLgAECn8iAAIaAAcJnhK+OQCLAQAaAAcJnhK+OQCLAQABLgAFFAQJDwAIAK8bAA==.',
It='Itakecandle:BAAALgAECgUJBwABLgAECgUJDAAKAAAAAA==.',
Iv='Ivanapump:BAAALgAECgIJAgABLgAECgYJBgAKAAAAAA==.',
Ja='Jackkal:BAAALgAECggJCgAAAA==.Jadethecat:BAAALgADCgMJAwAAAA==.Jakbis:BAAALgADCgEJAQAAAA==.Jakychan:BAAALgAECgEJAQAAAA==.Jaldiar:BAAALgADCgcJBwABLgAECgYJBgAKAAAAAA==.Jametrok:BAAALgAECgEJAQAAAA==.Jazbek:BAAALgAECgQJDgAAAA==.Jazzonus:BAAALgAECgQJBAAAAA==.',
Je='Jefferey:BAAALgADCgMJAwAAAA==.Jennyanydots:BAAALgAECgMJBQABLgAFFAkJMAAEAD8ZAA==.Jennycide:BAAALgADCggJCAAAAA==.Jeriçho:BAAALgADCgYJBgAAAA==.',
Jh='Jhonwick:BAAALgAECgIJAgAAAA==.',
Ji='Jippedo:BAAALgAECgYJAgABLgAECgcJBAAKAAAAAA==.Jiraîya:BAAALgAECgQJBQAAAA==.',
Jo='Jordak:BAABLgAECn8oAAIJAAkJBBwrDgDnAgAJAAkJBBwrDgDnAgAAAA==.Jorolee:BAAALgADCgEJAQAAAA==.',
Ju='Jumbok:BAAALgAECgMJAwAAAA==.Just:BAAALgAECgcJDAAAAA==.',
Ka='Kaast:BAAALgAECgEJAQAAAA==.Kaddiya:BAAALgAECgYJEgAAAA==.Kagonstrasza:BAAALgAECgQJBAAAAA==.Kallistos:BAABLgAECn8gAAIOAAcJER3uLQD/AQAOAAcJER3uLQD/AQAAAA==.Kangaroo:BAAALgAECgUJBQAAAA==.Kariza:BAAALgAECgQJBgAAAA==.Karunik:BAAALgADCgYJBgABLgAECgcJCgAKAAAAAA==.Kasst:BAAALgAECgQJBQAAAA==.Kasstt:BAAALgAECgUJBQAAAA==.',
Ke='Kelenheller:BAAALgAECgUJEgAAAA==.Kevdogg:BAAALgADCgYJBgAAAA==.Key:BAAALgAFFAMJAwAAAA==.',
Kh='Khione:BAAALgAECgMJAwAAAA==.Khthonios:BAAALgAECgEJAQAAAA==.',
Ki='Kiba:BAAALgADCgIJAgABLgAECggJQgAaAFEeAA==.Kibblerina:BAAALgADCgcJBwAAAA==.Kiranam:BAABLgAECn8fAAQbAAgJ8xJQCgDWAAAdAAgJqQqdEQCTAQAbAAcJjhFQCgDWAAAWAAIJWwfecQBZAAAAAA==.',
Kn='Knarth:BAABLgAECn9CAAIgAAkJ5x71AADZAgAgAAkJ5x71AADZAgAAAA==.Kníght:BAABLgAFFH8XAAIGAAUJGBNbKgAmAQAGAAUJGBNbKgAmAQAAAA==.',
Ko='Koisy:BAAALgAECgcJEAABLgAECggJFgAJAKkeAA==.Kole:BAAALgAECgEJAQAAAA==.Koopa:BAABLgAECn8uAAIRAAkJHyVcBQALAwARAAkJHyVcBQALAwAAAA==.',
Kr='Krasul:BAACLgAFFH8WAAMOAAYJtBRDJQBWAQAOAAYJtBRDJQBWAQAfAAIJ7QkOSQBsAAAuAAQKfx8AAw4ACAkXIecIAOgCAA4ACAkXIecIAOgCAB8ABgm/HPIxAJQBAAAA.Krenthok:BAABLgAECn8eAAIBAAgJiQe3iQAmAQABAAgJiQe3iQAmAQAAAA==.',
Ku='Kuraha:BAAALgAECgQJBAAAAA==.Kuruni:BAAALgAECgYJCgAAAA==.Kushar:BAAALgAECgQJBQABLgAECgkJGQAhAEkRAA==.',
Ky='Kyuketsuki:BAAALgAFFAIJAwAAAA==.',
La='Lachance:BAAALgADCgYJBgAAAA==.Ladieraven:BAAALgADCgUJBQAAAA==.Large:BAAALgADCgYJBgAAAA==.Largemann:BAAALgAFFAMJAwABLgAFFAUJGAAGAIkcAA==.Lathspell:BAABLgAECn8yAAITAAkJtiAMJgCDAgATAAkJtiAMJgCDAgAAAA==.Lazyevoker:BAAALgADCgQJBAABLgAECgEJAQAKAAAAAA==.',
Le='Leahan:BAABLgAECn8UAAINAAUJfgerMwB5AAANAAUJfgerMwB5AAAAAA==.Leloo:BAAALgADCgYJCgABLgAECgIJAwAKAAAAAA==.',
Lh='Lhureciv:BAACLgAFFH8VAAMEAAQJERl9FQA5AQAEAAQJERl9FQA5AQADAAEJKRuVSQBFAAAuAAQKf0sAAwQACQnVI80GAB4DAAQACQnVI80GAB4DAAMABgn7HjAjAHoBAAAA.',
Li='Lightchaser:BAAALgADCgMJAgAAAA==.Lightfkyou:BAAALgADCgcJCgAAAA==.Lihvurce:BAABLgAECn8fAAMNAAgJWR0/MgA3AgANAAgJWR0/MgA3AgAIAAQJpR0FSwBMAQABLgAFFAQJFQAEABEZAA==.Lillianna:BAACLgAFFH8HAAIMAAIJrBJ7MACkAAAMAAIJrBJ7MACkAAAuAAQKf0sAAgwACAk8HrYBADkCAAwACAk8HrYBADkCAAAA.Lingchi:BAAALgAECgQJBgAAAA==.',
Ll='Llew:BAAALgAECgYJCQAAAA==.',
Lo='Loenhart:BAAALgAECgIJAgAAAA==.Lolkurtone:BAAALgAECgIJAgAAAA==.',
Lu='Luciaan:BAAALgADCgkJGQAAAA==.Lucrative:BAAALgADCgcJDQAAAA==.Lug:BAAALgAECgEJAQAAAA==.Lulue:BAAALgADCgQJBAAAAA==.Luminari:BAAALgADCgUJBQAAAA==.Lunastorm:BAACLgAFFH8OAAIiAAQJLxPoGAAIAQAiAAQJLxPoGAAIAQAuAAQKfzgAAiIACQnQIooCAD8DACIACQnQIooCAD8DAAAA.Luponero:BAACLgAFFH8fAAMCAAYJ3CHZHQCNAQACAAUJiSPZHQCNAQAPAAIJBhGpFwBNAAAuAAQKfyIAAw8ACAnnHuYQALUCAA8ACAl6HeYQALUCAAIAAwnNHxqXABIBAAAA.',
Ly='Lynney:BAAALgADCgYJBwAAAA==.',
Ma='Macmn:BAACLgAFFH8WAAIfAAYJaxsMEwCLAQAfAAYJaxsMEwCLAQAuAAQKfy0AAh8ABwnAJGULAOICAB8ABwnAJGULAOICAAAA.Mageyouacake:BAAALgADCgYJBgAAAA==.Magicard:BAABLgAECn8fAAITAAgJjg5IewCBAQATAAgJjg5IewCBAQAAAA==.Makesfood:BAABLgAECn8qAAITAAcJZBeSdADpAQATAAcJZBeSdADpAQAAAA==.Mamaheals:BAABLgAECn8rAAIFAAkJSxpbFAAzAgAFAAkJSxpbFAAzAgAAAA==.Mandos:BAAALgAECgYJCAAAAA==.Mantistabogn:BAAALgAFFAEJAQAAAA==.Maor:BAABLgAECn8XAAINAAgJlxcuUADxAQANAAgJlxcuUADxAQAAAA==.March:BAAALgADCgEJAQAAAA==.Markeisha:BAAALgAECgQJCAABLgAECgYJDAAKAAAAAA==.',
Me='Mechz:BAAALgAECgYJBgABLgAFFAQJCQATAPwKAA==.Mechzician:BAACLgAFFH8JAAITAAQJ/Ao8dwDsAAATAAQJ/Ao8dwDsAAAuAAQKfzgAAhMACAlwGXtZAC0CABMACAlwGXtZAC0CAAAA.Mechzlock:BAAALgADCgEJAQABLgAFFAQJCQATAPwKAA==.Melinoe:BAAALgAECgEJAQAAAA==.Merlerk:BAAALgADCgYJBgABLgAFFAkJKQAFABoWAA==.Merlini:BAABLgAECn8dAAMEAAgJWRYLJACpAQAEAAcJ0xgLJACpAQADAAUJThaqPAAbAQAAAA==.Metrohexual:BAAALgAECggJCgAAAA==.Mets:BAAALgAECgYJCwABLgAECgkJHwABAJgbAA==.',
Mi='Microplastic:BAAALgAECgUJBQAAAA==.Micspanky:BAAALgAECggJEgAAAA==.Mistynight:BAAALgAECgMJAwAAAA==.Mithrandi:BAAALgAECgYJCQAAAA==.Mitzis:BAABLgAFFH8NAAICAAMJ8x89UgAFAQACAAMJ8x89UgAFAQAAAA==.',
Mo='Moltii:BAAALgADCgMJAwAAAA==.Moltiy:BAAALgADCggJFQAAAA==.Moltten:BAABLgAECn8XAAMOAAYJyhBZEAAeAQAOAAUJmhNZEAAeAQAfAAQJpwOUIgBIAAAAAA==.Mornhathor:BAAALgAECggJDgABLgAECgYJCAAKAAAAAA==.',
Mu='Mufinblaster:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgADCgIJBgAAAA==.Musnicker:BAAALgAECgQJBwABLgAECgkJOAAPAIYWAA==.',
My='Myro:BAACLgAFFH8UAAMOAAQJ3B+fJwBJAQAOAAQJ3B+fJwBJAQAfAAIJZRTKQgB/AAAuAAQKfxsAAg4ABwm/JsEHAPkCAA4ABwm/JsEHAPkCAAAA.',
['Mè']='Mètis:BAAALgAECgcJCQAAAA==.',
['Mø']='Møhax:BAAALgAECgYJBgAAAA==.',
Na='Nadnoo:BAAALgAECgMJAwAAAA==.Nanis:BAAALgAECgYJBwABLgAFFAcJIgAWAKglAA==.Narmer:BAAALgAECgIJAgAAAA==.',
Ne='Neel:BAAALgADCgQJBQAAAA==.Nefarius:BAAALgAECgEJAQABLgAFFAEJAQAKAAAAAA==.Nervhoost:BAAALgADCgMJAwAAAA==.Neuropolis:BAAALgADCgcJFQAAAA==.Neuroscience:BAAALgADCgMJAwAAAA==.Neurotics:BAABLgAECn9kAAQjAAkJSyZEAAAKAwAjAAkJqyVEAAAKAwAkAAcJ3SQLBABHAgABAAYJ1BtbJABiAAAAAA==.Neò:BAABLgAECn8YAAMlAAYJvBC1EAD/AAAlAAYJXw61EAD/AAAmAAEJ/hQHkwA1AAAAAA==.',
Ni='Niesh:BAAALgAECgEJBwAAAA==.Nightrush:BAAALgADCgEJAQAAAA==.Nineoneone:BAABLgAECn9kAAMFAAkJ1hqpAQCaAgAFAAkJ1hqpAQCaAgADAAQJjgPqRQCLAAAAAA==.Ninjá:BAAALgAECgEJAQAAAA==.',
No='Nobledecay:BAAALgAECgQJBQAAAA==.Nocturne:BAAALgAECgEJAwAAAA==.Norí:BAAALgAECgYJCAAAAA==.',
Nu='Nubbletcake:BAAALgADCgEJAQABLgAECgkJJAADALIeAA==.Nula:BAAALgAECgMJBQABLgAFFAkJMAAEAD8ZAA==.',
Ny='Nylveth:BAACLgAFFH8SAAIEAAUJzw9EHQAGAQAEAAUJzw9EHQAGAQAuAAQKfyoAAgQACQkAHXQQAFgCAAQACQkAHXQQAFgCAAEuAAUUCAkNACcAtgwA.',
Oa='Oathatone:BAAALgAECgUJCAAAAA==.',
Oc='Ocra:BAABLgAECn8gAAInAAkJ9g59DgDJAQAnAAkJ9g59DgDJAQABLgAFFAQJFgACALwZAA==.Octaviå:BAAALgAECgEJAQABLgAECgcJCQAKAAAAAA==.',
Of='Offspeck:BAAALgAECgIJAgABLgAECgkJIQABAFYcAA==.',
Ou='Outtkast:BAAALgAECgIJAgAAAA==.Outtkastt:BAAALgAECgcJDQAAAA==.Ouutkast:BAAALgAECgIJBAAAAA==.',
Oz='Ozwald:BAABLgAECn81AAIQAAkJchx/EAAqAgAQAAkJchx/EAAqAgAAAA==.',
Pa='Pallyangel:BAAALgADCgcJDwAAAA==.Pandemul:BAAALgAECgMJAwABLgAFFAQJEQANADsjAA==.Pastasaladin:BAAALgADCgEJAQAAAA==.Patrio:BAACLgAFFH8IAAIiAAMJGg24IQCXAAAiAAMJGg24IQCXAAAuAAQKfywAAiIACQllGfUHAHMCACIACQllGfUHAHMCAAEuAAUUBQkNAAkAOxAA.Pawkclaw:BAAALgAECgYJBgAAAA==.',
Pe='Peaceonea:BAABLgAECn8bAAIHAAkJrgQYnQDoAAAHAAkJrgQYnQDoAAAAAA==.Peachaid:BAECLgAFFH8cAAMDAAgJ9Rd6CQCNAgADAAgJ9Rd6CQCNAgAFAAEJRQgoOgAtAAAuAAQKfzAAAwMACQlVImoFADIDAAMACQlVImoFADIDAAUABgkYHSglAMABAAAA.Peatri:BAAALgAFFAEJAQAAAA==.Peetree:BAACLgAFFH8RAAIOAAQJOBlTLwAlAQAOAAQJOBlTLwAlAQAuAAQKfx4AAg4ACAnMH3sCAK8CAA4ACAnMH3sCAK8CAAAA.Pekin:BAAALgAECgEJAgAAAA==.',
Ph='Phosphorus:BAACLgAFFH8WAAMLAAQJFhUrGwAQAQALAAQJihMrGwAQAQAeAAIJkhjbIwB7AAAuAAQKf1kAAwsACQnmIEcFALcCAAsACQnHHkcFALcCAB4ABgkqHIkYAHoBAAAA.',
Pl='Plagüë:BAACLgAFFH8RAAMUAAQJzRxOKQCsAAAGAAMJpCC6eAASAQAUAAMJ3RBOKQCsAAAuAAQKf00AAwYACQmjJbcQAOcCAAYACQmjJbcQAOcCABQABQmbD0E5AK4AAAAA.Pleistarchus:BAAALgAECgYJCQAAAA==.',
Po='Poic:BAAALgADCgEJAQAAAA==.Polo:BAAALgADCgEJAQAAAA==.Poofighter:BAAALgAECgMJBwABLgAFFAIJCAAHAAohAA==.Poonan:BAAALgAECgYJBgAAAA==.',
Pp='Ppgangandlaw:BAAALgADCgEJAQAAAA==.',
Pr='Precious:BAABLgAECn8tAAIaAAkJNBbBCQCHAQAaAAkJNBbBCQCHAQAAAA==.Prezfaux:BAAALgAECgQJBAAAAA==.Primalistic:BAAALgADCgUJBQABLgAFFAQJCQATAPwKAA==.Primàl:BAABLgAECn8sAAIJAAYJBRv2NADUAQAJAAYJBRv2NADUAQAAAA==.Prowar:BAAALgAECgYJBgABLgAECgYJIgAEAIsRAA==.',
Pu='Pullnprey:BAAALgADCgEJAQAAAA==.Punchinbag:BAAALgADCgYJBgAAAA==.Purifieds:BAAALgADCgEJAQAAAA==.',
['Pà']='Pàladin:BAABLgAFFH8KAAMSAAMJBxWWCACMAAANAAMJDAtOPgClAAASAAIJCxeWCACMAAAAAA==.',
Qs='Qsrqasda:BAABLgAECn8VAAIUAAYJ4QXnPwCPAAAUAAYJ4QXnPwCPAAAAAA==.',
Qt='Qtmenopaws:BAAALgAECgQJAwAAAA==.Qtptt:BAACLgAFFH8bAAIBAAQJBCQXIQAZAQABAAQJBCQXIQAZAQAuAAQKf0AAAgEACQmMI4gJAAYDAAEACQmMI4gJAAYDAAAA.',
Ra='Ragedeath:BAABLgAFFH8JAAIUAAMJuA+3LACWAAAUAAMJuA+3LACWAAABLgAFFAQJBAAKAAAAAA==.Ragedh:BAAALgAECgIJAgABLgAFFAQJBAAKAAAAAA==.Ragemonk:BAAALgADCgQJBAABLgAFFAQJBAAKAAAAAA==.Rageshaman:BAAALgAFFAQJBAAAAA==.Rasmong:BAABLgAECn8ZAAIhAAkJSREJHwC1AQAhAAkJSREJHwC1AQAAAA==.Ravinsinda:BAAALgAECgYJBgAAAA==.Ravinursula:BAABLgAECn8VAAMjAAcJCQ3MGQDyAAAjAAYJtArMGQDyAAAkAAcJYgkuCQCZAAAAAA==.Rawrs:BAAALgAECgEJAQABLgAFFAQJDAAmAMsPAA==.Rawrsaur:BAAALgAECgcJDQAAAA==.',
Re='Really:BAAALgADCgYJBgABLgAECgEJAQAKAAAAAA==.Reallyhpal:BAAALgAECgEJAQAAAA==.Reddbull:BAAALgAECgYJBgAAAA==.Redder:BAAALgAECgEJAQAAAA==.Remin:BAABLgAECn8XAAMIAAgJDQ61BQCKAQAIAAgJDQ61BQCKAQANAAUJAAnkMQCBAAAAAA==.Remun:BAAALgADCgMJAwAAAA==.Retaliator:BAABLgAECn9BAAMNAAgJ2hghDgB3AQANAAgJ2hghDgB3AQASAAMJuAwQOQB6AAAAAA==.Reuuín:BAAALgAECggJDAABLgAECggJGQAMABwZAA==.Revan:BAAALgAECgYJBwAAAA==.',
Rh='Rhýs:BAAALgAECgYJBgAAAA==.',
Ri='Rih:BAAALgADCgMJBQAAAA==.Riitari:BAAALgAECgEJAQABLgAECgkJHwABAJgbAA==.Ripits:BAAALgADCgcJCAABLgAECgEJAQAKAAAAAA==.Risky:BAAALgAECgkJAwABLgAFFAIJAwAKAAAAAA==.Riskyfist:BAAALgAECgcJAgAAAA==.Risquae:BAAALgAECgIJAwAAAA==.',
Ro='Roadrashnuts:BAAALgAECgUJBwAAAA==.Rocc:BAAALgAECgcJBAAAAA==.Rocketeer:BAABLgAECn8nAAITAAgJGg1rnABBAQATAAgJGg1rnABBAQAAAA==.Romulis:BAAALgAECgEJAQAAAA==.Ronburgundii:BAAALgAECgEJAQAAAA==.Roosk:BAAALgAECgEJAgAAAA==.',
Ru='Rudrya:BAABLgAECn8UAAInAAgJcAfhEwB8AQAnAAgJcAfhEwB8AQAAAA==.Ruka:BAAALgAECgEJAQAAAA==.Rumpke:BAAALgADCgEJAQAAAA==.Rumpkey:BAAALgADCgcJCgAAAA==.Runalish:BAAALgAECgEJAQAAAA==.Runarinis:BAAALgADCgIJAgAAAA==.',
Ry='Ryhia:BAAALgADCgkJCQABLgAECgYJCAAKAAAAAA==.Rynopinn:BAACLgAFFH8JAAIJAAMJIhZ/OgDEAAAJAAMJIhZ/OgDEAAAuAAQKf0YABAkACAnqIxkLAOgCAAkACAnqIxkLAOgCAB0ABwm6GwANAOYBABYAAgn4F6llAIYAAAAA.Ryxn:BAAALgADCgYJBgAAAA==.',
['Rí']='Ríco:BAAALgAECgYJCwAAAA==.',
Sa='Sacredstud:BAAALgADCgEJAQAAAA==.Saeed:BAAALgAECgEJAQAAAA==.Saelylasia:BAAALgAECgQJBQAAAA==.Sajaboy:BAAALgAECgMJBAAAAA==.Samusaran:BAAALgADCgEJAQAAAA==.Sans:BAAALgAECgcJBwAAAA==.Sapphier:BAAALgAECgUJCAAAAA==.Sarrania:BAAALgAECgUJBQAAAA==.Sartha:BAABLgAECn8rAAINAAkJuhiPMAA+AgANAAkJuhiPMAA+AgAAAA==.Sasuka:BAAALgAECgkJDgAAAA==.Satsu:BAAALgAECgEJAQAAAA==.',
Sc='Scatherlia:BAAALgADCgYJBQABLgAECgQJBQAKAAAAAA==.Sco:BAAALgADCgEJAQABLgAECgYJDQAKAAAAAA==.Scratchit:BAAALgAECgEJAQAAAA==.Screwthebull:BAAALgAECgQJBAAAAA==.Scrumpdragon:BAAALgAECgIJAgAAAA==.Scrumpvincet:BAAALgADCgUJBQABLgAECgIJAgAKAAAAAA==.',
Se='Sectiondk:BAAALgAECgYJEwAAAA==.Sedda:BAACLgAFFH8cAAINAAkJ3SDqCwAeAgANAAkJ3SDqCwAeAgAuAAQKfy0AAg0ACAmnJc4GAGMDAA0ACAmnJc4GAGMDAAAA.Seigfreid:BAAALgAECgYJCAAAAA==.Sensual:BAACLgAFFH8QAAISAAQJDQgtDQCnAAASAAQJDQgtDQCnAAAuAAQKf0kAAhIACQlTFOsSAJoBABIACQlTFOsSAJoBAAAA.Seraphina:BAAALgAECgYJDgAAAA==.Sessano:BAAALgAECgYJDQAAAA==.Sesshomaru:BAACLgAFFH8IAAMHAAIJCiGpTABEAAAXAAEJ0CNDKgBQAAAHAAIJXhypTABEAAAuAAQKf1MAAwcACQnUIxcTAOcCAAcACAm3IRcTAOcCABcACAkvJGoMAGACAAAA.',
Sh='Shadoly:BAAALgAECgcJEQAAAA==.Shadowboss:BAABLgAECn8iAAIEAAYJixGTQQAJAQAEAAYJixGTQQAJAQAAAA==.Shamh:BAAALgAECgIJAgAAAA==.Shamhspriest:BAAALgAECgYJBgAAAA==.Shamnslam:BAAALgAECgEJAQAAAA==.Shampooh:BAAALgAECgYJBgAAAA==.Shang:BAACLgAFFH8iAAUWAAcJqCXnAgB0AgAWAAcJqCXnAgB0AgAdAAEJhiD3GQBhAAAbAAEJ2x6LHwBUAAAJAAEJswMIewApAAAuAAQKfzwABRYACQlMJWUCAE8DABYACQlMJWUCAE8DAAkABwm3GkEEAOMBABsAAwm+Hqc9ALAAAB0AAQndJWQMAGgAAAAA.Shiftchi:BAAALgAECgYJBwAAAA==.Shirona:BAACLgAFFH8FAAIHAAIJgx6tbACyAAAHAAIJgx6tbACyAAAuAAQKfzwAAgcACQnpIYIHABcDAAcACQnpIYIHABcDAAAA.Shmized:BAAALgADCgIJAgAAAA==.Shockazulu:BAAALgAECgEJAQAAAA==.Showstop:BAAALgAECgEJAQAAAA==.Shyne:BAAALgADCgMJAwAAAA==.Shyvanna:BAABLgAECn8mAAMmAAkJyBGCJAC5AQAmAAkJyBGCJAC5AQAlAAQJ0wonHQBkAAAAAA==.Sháman:BAAALgAECgUJBAAAAA==.Shïnïgämï:BAABLgAECn8WAAIoAAYJiCAvCQDeAQAoAAYJiCAvCQDeAQABLgAFFAIJBgAOABwcAA==.Shøøtinlåvå:BAAALgADCgcJBwAAAA==.',
Si='Siare:BAABLgAECn8fAAIBAAkJmBvLAgCAAgABAAkJmBvLAgCAAgAAAA==.Sigarda:BAAALgAECgUJCAAAAA==.Silica:BAAALgAECgMJAwAAAA==.Silvershot:BAAALgADCgUJBQAAAA==.Siner:BAAALgAECgUJCAAAAA==.',
Sk='Skeeter:BAACLgAFFH8JAAMBAAYJoAreIwAJAQABAAYJoAreIwAJAQAkAAEJAA2JJgBIAAAuAAQKfz4ABCQACQldHZIDAFkCACQACQkFGpIDAFkCAAEACQlbGFVIAMEBACMABwknHUIMAJgBAAAA.Skiadrum:BAACLgAFFH8FAAIhAAMJgQGlOQBgAAAhAAMJgQGlOQBgAAAuAAQKf0IAAxoACQl+FMIpAN4BABoACAnXEsIpAN4BACEABAlBCRJnAIgAAAAA.Skoliro:BAAALgAECgcJCwAAAA==.Skorch:BAAALgADCgkJEAABLgAFFAQJCQATAPwKAA==.Skroncer:BAAALgADCgUJCAAAAA==.',
Sm='Smotts:BAABLgAECn8VAAMiAAkJ8hKwDgDjAQAiAAkJ8hKwDgDjAQAmAAMJNAZxUwB5AAAAAA==.Smòtts:BAABLgAECn88AAIbAAkJyyG4AAD3AgAbAAkJyyG4AAD3AgAAAA==.',
Sn='Snizard:BAABLgAECn8sAAICAAkJwx4DBQBhAgACAAkJwx4DBQBhAgAAAA==.Snizorc:BAAALgAECgIJAgAAAA==.Snuggiepoo:BAABLgAECn8kAAMDAAkJsh6hCwC1AgADAAgJ5CChCwC1AgAEAAYJgRWiWgCrAAAAAA==.',
So='Songbirds:BAAALgADCgcJDQAAAA==.Sonichoos:BAAALgAECgUJDAAAAA==.Sophiel:BAACLgAFFH8LAAIHAAMJRBm0KwDMAAAHAAMJRBm0KwDMAAAuAAQKfyQAAgcACAktG+YmADACAAcACAktG+YmADACAAAA.Sosthenna:BAAALgADCgkJCQAAAA==.Soulbark:BAAALgAECgMJAwABLgAECgQJBAAKAAAAAQ==.Souleater:BAAALgADCgMJAwAAAA==.Soulforged:BAAALgADCgcJCwABLgAECgQJBAAKAAAAAA==.Soulreaver:BAAALgAECgcJCAAAAA==.Soulweaver:BAAALgAECgQJBAAAAQ==.',
Sp='Sparrowhåwk:BAAALgADCgUJBgAAAA==.Spicymustard:BAAALgAECgEJAgAAAA==.Spongebill:BAAALgADCgEJAQAAAA==.Spàdes:BAABLgAECn8cAAMRAAcJxxoyMgCDAQARAAYJbhsyMgCDAQALAAMJbBILSACrAAAAAA==.',
Sq='Squírtlé:BAAALgAFFAEJAQAAAA==.',
St='Starel:BAAALgAECgQJBAAAAA==.Stellanoova:BAAALgAFFAEJAQABLgAFFAQJDAAmAMsPAA==.Stevebushami:BAAALgAECgYJEAAAAA==.Stuwu:BAAALgAECgMJBAAAAA==.',
Su='Submistive:BAEALgAECgQJBQABLgAFFAUJDAAMABISAA==.Suffers:BAAALgAFFAEJAQAAAA==.Suou:BAAALgADCgcJCQABLgAECgEJAgAKAAAAAA==.Surj:BAABLgAECn8mAAMeAAYJPByBBQAkAQAeAAYJghqBBQAkAQARAAUJFg+5aQC6AAAAAA==.',
Sv='Svmii:BAAALgADCgcJCgAAAA==.',
Sy='Sycther:BAAALgADCgEJAQABLgAFFAMJCQAJACIWAA==.Syradori:BAAALgAECgEJAQAAAA==.',
Ta='Taazdingo:BAABLgAECn8ZAAIbAAYJjRwcBACMAQAbAAYJjRwcBACMAQAAAA==.Taikuri:BAAALgAECggJDwABLgAECgkJHwABAJgbAA==.Taliela:BAAALgAECgQJBAAAAA==.Tanddralndra:BAAALgAECgUJBwAAAA==.Tanklilbaby:BAAALgAECgEJAQAAAA==.Tannia:BAAALgAECgEJAwAAAA==.Taxgirl:BAACLgAFFH8YAAMGAAUJiRyeUQBOAQAGAAUJiRyeUQBOAQAVAAEJsQOXLAA3AAAuAAQKfygAAgYACAlAJWISAA0DAAYACAlAJWISAA0DAAAA.Taxxwomann:BAABLgAECn8aAAQBAAcJMSWqAgCKAgABAAcJBSWqAgCKAgAkAAUJ6yMOAgCpAQAjAAEJKyUjCwBrAAABLgAFFAUJGAAGAIkcAA==.',
Te='Teabear:BAAALgAFFAMJBAAAAA==.Tealzin:BAAALgAECgEJAQAAAA==.Telandrî:BAAALgADCgIJAgAAAA==.Teralion:BAAALgAECgMJBgAAAA==.',
Th='Thaeldrik:BAAALgADCgcJCgAAAA==.Thaldreaux:BAAALgAECgMJBAAAAA==.Thefirst:BAAALgAECgMJBwABLgAECgYJIgAEAIsRAA==.Theleon:BAABLgAECn8dAAIWAAgJQg9sLwBiAQAWAAgJQg9sLwBiAQAAAA==.Theßoss:BAAALgAECgMJAwABLgAECgYJIgAEAIsRAA==.Thordrin:BAABLgAECn8yAAIIAAcJ/CQzCgDoAgAIAAcJ/CQzCgDoAgAAAA==.Thorlan:BAAALgADCgYJCAAAAA==.Thrasherzs:BAAALgAECgUJDQAAAA==.Thryen:BAAALgAECgcJEwAAAA==.Thunder:BAAALgADCgQJBAABLgAECgcJCgAKAAAAAA==.Thundergrasp:BAACLgAFFH8NAAMnAAgJtgx8AwCcAQAnAAgJBwt8AwCcAQAfAAIJjw9vJgB0AAAuAAQKfxsAAicABwkNG9YPALQBACcABwkNG9YPALQBAAAA.',
Ti='Tianhe:BAAALgAECgMJAwAAAA==.Tiarisaril:BAAALgAECgYJBgAAAA==.Tigercita:BAAALgAECgMJAgAAAA==.Tippah:BAAALgAECgEJAwAAAA==.Tippers:BAAALgAECgEJAQAAAA==.',
Tj='Tjsneckbeard:BAAALgAECgEJAQAAAA==.',
To='Toe:BAABLgAFFH8FAAIGAAIJrRTFxwCdAAAGAAIJrRTFxwCdAAAAAA==.Tonkah:BAAALgAECgUJBQABLgAECggJEQAKAAAAAA==.Toobestake:BAABLgAFFH8GAAIWAAMJ4BXuMgC1AAAWAAMJ4BXuMgC1AAABLgAFFAYJHwACANwhAA==.Topenga:BAACLgAFFH8WAAICAAQJvBmJNABFAQACAAQJvBmJNABFAQAuAAQKf0wAAgIACQnXH2kSAKQCAAIACQnXH2kSAKQCAAAA.Tosem:BAAALgAECgcJBwAAAA==.Touchypope:BAAALgADCgYJCwAAAA==.',
Tr='Treeage:BAAALgADCgMJAwAAAA==.Triggerd:BAAALgADCgEJAQAAAA==.Trunks:BAAALgADCgQJBAAAAA==.Trylok:BAAALgADCgEJAQAAAA==.Trüst:BAAALgAECggJDgAAAA==.',
Tw='Twicelife:BAABLgAECn8ZAAIOAAgJ0R3wFgCSAgAOAAgJ0R3wFgCSAgABLgAFFAQJFgALABYVAA==.',
Ty='Tyrygosa:BAAALgAECgUJBQABLgAFFAQJEAABAMEWAA==.',
['Tñ']='Tñt:BAAALgADCgQJBAABLgAECgkJIQABAFYcAA==.',
Un='Undread:BAAALgAFFAEJAQABLgAFFAUJEAARAGQdAA==.Uneedsummilk:BAAALgADCggJCAAAAA==.Unholyapollo:BAAALgADCgYJCwAAAA==.',
Ur='Urthstripe:BAABLgAECn8vAAQJAAkJxBWuHABhAgAJAAkJxBWuHABhAgAWAAIJMgMIjwAxAAAdAAEJiwUxZQAaAAAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAcJEAAGABMYAA==.Vain:BAAALgAECgEJAgAAAA==.Valle:BAAALgAECgIJAwABLgAFFAkJMAAEAD8ZAA==.Valoria:BAAALgAECgMJCQABLgAFFAkJMAAEAD8ZAA==.',
Ve='Veil:BAAALgAECgIJCAABLgAFFAkJMAAEAD8ZAA==.Velarenea:BAAALgADCgEJAQAAAA==.Velgabrine:BAAALgAECgYJDAABLgAFFAQJEQANADsjAA==.Veraani:BAAALgAECgYJBgAAAA==.Verra:BAAALgADCgYJBgAAAA==.',
Vi='Vil:BAAALgADCgcJBgAAAA==.Virlan:BAAALgADCgQJBAAAAA==.Viserion:BAACLgAFFH8MAAMmAAMJyw/+HwCqAAAmAAMJyw/+HwCqAAAiAAEJfgbdGwAkAAAuAAQKfxYAAyYACAlKFDE+ADEBACYABwlkEjE+ADEBACIABgnYDOAgAO0AAAAA.',
Vo='Voidchaosfan:BAAALgAECgYJDAAAAA==.',
Vu='Vue:BAACLgAFFH8TAAIIAAQJQxMiJwDpAAAIAAQJQxMiJwDpAAAuAAQKf0YAAggACQkkGzYfAB8CAAgACQkkGzYfAB8CAAAA.Vuldin:BAAALgAECgEJAgAAAA==.',
['Vö']='Völdemört:BAAALgADCgIJAgAAAA==.',
Wa='Wakasham:BAACLgAFFH8lAAInAAcJSCJRAQAcAgAnAAcJSCJRAQAcAgAuAAQKfzUAAicACQlCJp4BAFMDACcACQlCJp4BAFMDAAAA.Wardemon:BAAALgADCgIJAgAAAA==.Wardrake:BAAALgAECgQJBAAAAA==.',
We='Wehonoryou:BAABLgAECn8YAAIXAAYJ9CHYGAAAAgAXAAYJ9CHYGAAAAgAAAA==.Wetard:BAAALgADCgIJAgAAAA==.',
Wi='Willbyers:BAAALgAECgEJAQAAAA==.Winterloom:BAAALgAECgYJBgAAAA==.',
Wl='Wlock:BAAALgADCgIJAgAAAA==.',
Wo='Wolfpacked:BAACLgAFFH8GAAIOAAIJHByYWgCXAAAOAAIJHByYWgCXAAAuAAQKfygAAg4ACQlBIDMJAB8DAA4ACQlBIDMJAB8DAAAA.Wolfzbåin:BAAALgAECgQJBAAAAA==.',
Wr='Wroot:BAAALgADCgYJCQAAAA==.Wrotten:BAABLgAECn8WAAIjAAgJ6RcFCwCtAQAjAAgJ6RcFCwCtAQAAAA==.',
Wu='Wunderlust:BAACLgAFFH8PAAITAAQJhxfwUwA1AQATAAQJhxfwUwA1AQAuAAQKf0QAAhMACQmFISYcAAYDABMACQmFISYcAAYDAAAA.',
['Wà']='Wàrrior:BAABLgAECn8YAAMRAAgJIQtMSwAZAQARAAgJIQtMSwAZAQAeAAEJxgOEFwAZAAAAAA==.',
Xe='Xemon:BAAALgAECgIJAgAAAA==.',
Xi='Xilyana:BAAALgAECgQJBAAAAA==.',
Xm='Xmatick:BAAALgAECgcJCQAAAA==.',
Xs='Xscrats:BAAALgAECgkJCAAAAA==.',
Ye='Yellowshaman:BAACLgAFFH8rAAIfAAgJuBiVDwCzAQAfAAgJuBiVDwCzAQAuAAQKfzIAAh8ACQk3IkQMANcCAB8ACQk3IkQMANcCAAAA.Yerac:BAAALgAECgEJAQAAAA==.',
Yu='Yukikage:BAAALgAECgMJAwAAAA==.Yutdaeng:BAAALgAECgMJBAAAAA==.',
Yv='Yvent:BAAALgADCgIJAgAAAA==.Yvraine:BAAALgAECgYJEgAAAA==.',
Za='Zakcarii:BAAALgADCgMJCAAAAA==.Zakin:BAAALgADCgcJBwAAAA==.Zalicy:BAAALgAECgYJEwAAAA==.Zalogar:BAAALgAECgcJCgAAAA==.Zapper:BAAALgAECgcJEQAAAA==.',
Zb='Zbarbb:BAAALgADCgUJBQAAAA==.',
Ze='Zealot:BAAALgAECgEJAQAAAA==.Zeeasyez:BAAALgAECgYJEwAAAA==.Zestul:BAAALgADCgEJAQAAAA==.',
Zh='Zhane:BAAALgADCgYJBwAAAA==.',
Zo='Zordon:BAAALgAECgYJEwAAAA==.',
Zs='Zslol:BAAALgAECgEJAQAAAA==.',
Zu='Zugg:BAAALgAECgMJBgABLgAFFAkJMAAEAD8ZAA==.Zuriznikov:BAAALgAFFAEJAwABLgAFFAQJDAAmAMsPAA==.',
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
