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

local lookup = {'Hunter-BeastMastery','Priest-Discipline','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','DemonHunter-Havoc','Paladin-Holy','Druid-Restoration','Unknown-Unknown','Warrior-Arms','Rogue-Subtlety','Paladin-Retribution','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','DeathKnight-Blood','DeathKnight-Frost','Druid-Balance','DemonHunter-Devourer','Rogue-Assassination','Mage-Arcane','Monk-Mistweaver','Druid-Guardian','Monk-Brewmaster','Shaman-Restoration','Mage-Frost','Warlock-Demonology','Evoker-Preservation','Warrior-Protection','Shaman-Elemental','Druid-Feral','Mage-Fire','Monk-Windwalker','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Evoker-Augmentation','Shaman-Enhancement','Paladin-Protection','DemonHunter-Vengeance',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=46,date='2026-05-24',data={Aa='Aaronfreeze:BAACLgAFFH8FAAIBAAMJPRj1OwD+AAABAAMJPRj1OwD+AAAuAAQKfzIAAgEACQn1HoMVAH8CAAEACQn1HoMVAH8CAAAA.',
Ab='Abrakazaam:BAAALgADCgEJAQAAAA==.',
Ad='Adrios:BAABLgAECn8kAAQCAAgJEhVQHwCoAQACAAgJABVQHwCoAQADAAYJ/gYxUgCXAAAEAAMJyggkaQCIAAAAAA==.',
Ae='Aetherion:BAAALgAECgMJBAAAAA==.',
Aj='Ajaxz:BAABLgAECn8VAAIFAAkJ+RLTYADRAQAFAAkJ+RLTYADRAQAAAA==.',
Ak='Akaßoss:BAAALgADCgEJAQAAAA==.',
Al='Albedô:BAAALgAFFAIJAwABLgAFFAIJBgAGAAohAA==.Aliren:BAAALgAECgYJCgAAAA==.Allmaick:BAAALgADCggJCAAAAA==.Alucard:BAABLgAFFH8GAAIHAAMJFwRiLACgAAAHAAMJFwRiLACgAAAAAA==.Alystrasza:BAABLgAECn8dAAIIAAYJvhYcPgB7AQAIAAYJvhYcPgB7AQAAAA==.',
Am='Amorlandian:BAAALgAECgMJAwAAAA==.',
An='Antimovsky:BAAALgAECgcJDQAAAA==.',
Ap='Aphroditê:BAAALgADCgYJBgABLgAECgcJCAAJAAAAAA==.',
Aq='Aqours:BAAALgADCgcJBwABLgAECgEJAgAJAAAAAA==.',
Ar='Arcan:BAAALgAECgIJAgAAAA==.',
Au='Augustine:BAAALgAECgEJAQAAAA==.Auroras:BAABLgAECn8XAAIEAAcJhBOZNABsAQAEAAcJhBOZNABsAQAAAA==.',
Av='Aviaria:BAAALgAECgQJBAAAAA==.Avìendha:BAAALgADCgEJAQAAAA==.',
['Aì']='Aìnzooalgown:BAABLgAFFH8LAAIFAAQJ+RmmMwBfAQAFAAQJ+RmmMwBfAQABLgAFFAIJBgAGAAohAA==.',
Ba='Babakubwa:BAAALgAECgMJAwAAAA==.Babylonfive:BAAALgAECgcJDAAAAA==.Balhair:BAAALgADCgYJBgAAAA==.Banish:BAAALgAECgMJAgABLgAECgcJCgAJAAAAAA==.Barragdan:BAAALgADCgEJAQAAAA==.Basandra:BAAALgAECgEJAQAAAA==.Basicc:BAAALgADCgMJAwAAAA==.',
Be='Beachbumm:BAAALgADCgEJAQAAAA==.Belleta:BAAALgAECggJDwAAAA==.Berserk:BAEBLgAECn8XAAIKAAYJJyJQCAAyAgAKAAYJJyJQCAAyAgABLgAFFAMJBQALALwMAA==.Bertringer:BAAALgAECgEJAgAAAA==.',
Bi='Bigmack:BAAALgAECgYJCwABLgAFFAYJFQAMANkXAA==.Bigwilli:BAAALgAECgYJEgAAAA==.Bingßong:BAAALgADCgYJEQAAAA==.Biscuit:BAACLgAFFH8PAAQBAAUJpR/WOAAIAQABAAQJvCLWOAAIAQANAAIJ4heyGQCeAAAOAAIJ+xECIwCKAAAuAAQKfyIABA0ACAmPIycPAMgCAA0ACAl9HScPAMgCAA4AAwnZH34yAPUAAAEABAk+HiiQAPAAAAAA.Bisha:BAABLgAECn9FAAMPAAkJEiFxCwCPAgAPAAkJ9CBxCwCPAgAKAAYJcBjHJwAHAQAAAA==.Bizcocho:BAAALgAECgcJDAAAAA==.',
Bl='Black:BAAALgADCgEJAQAAAA==.Bloodsimple:BAAALgADCgUJBQAAAA==.Blákers:BAAALgAFFAMJAwAAAA==.',
Bo='Boic:BAAALgADCgQJBAAAAA==.Bonesofdoom:BAABLgAECn8bAAMQAAcJNRyNFwB8AQAQAAcJNRyNFwB8AQAFAAEJtwR9VwEjAAAAAA==.Boogsta:BAABLgAECn8eAAIRAAkJvQ7aCAC6AQARAAkJvQ7aCAC6AQAAAA==.Boomkingobrr:BAACLgAFFH8HAAISAAMJ9wjeJwDCAAASAAMJ9wjeJwDCAAAuAAQKfxsAAhIACQkOHEQLAOECABIACQkOHEQLAOECAAAA.Boops:BAAALgAECgEJAQAAAA==.Bootysweatt:BAABLgAECn8aAAIGAAYJNhtqJACaAQAGAAYJNhtqJACaAQAAAA==.Boss:BAAALgADCgEJAQAAAA==.',
Br='Brewnz:BAAALgAECgUJBgAAAA==.Brucewee:BAAALgAECgQJCQAAAA==.',
Bu='Buckits:BAAALgAECgcJEgAAAA==.Bunsey:BAAALgADCgIJAgAAAA==.Burnsx:BAAALgAECgUJCgABLgAFFAgJGAATAEoeAA==.Bussyman:BAAALgAECgYJEQABLgAFFAMJCQAIACIWAA==.',
Bw='Bwoar:BAAALgAECgQJBgAAAA==.',
['Bø']='Bøw:BAAALgAECgMJAwAAAA==.',
['Bü']='Bübble:BAAALgADCgEJAQAAAA==.',
Ca='Captnmurloc:BAAALgAECggJDwAAAA==.Carl:BAAALgAECgEJAgABLgAFFAYJDQAUAPUcAA==.Carrach:BAAALgAECgEJAQAAAA==.Caveyodeler:BAAALgAECgQJCgAAAA==.',
Ce='Cedar:BAAALgAECgQJCQAAAA==.',
Ch='Cherga:BAAALgADCgYJBgAAAA==.Chinegga:BAAALgADCgYJBgAAAA==.Chitose:BAAALgADCgUJBQABLgAECgEJAgAJAAAAAA==.Chrapsasspee:BAAALgADCgcJGQAAAA==.Chrinn:BAAALgADCgIJAgAAAA==.',
Ci='Cindele:BAAALgADCgMJAwAAAA==.Cirvix:BAAALgAECgYJDAAAAA==.Cirxe:BAABLgAECn8dAAIVAAgJ9QpfBQBZAQAVAAgJ9QpfBQBZAQAAAA==.',
Cl='Clampire:BAAALgAECgQJBAAAAA==.Cliint:BAAALgAECgcJCwAAAA==.Cloúnt:BAAALgAECgEJAQAAAA==.Cluumn:BAAALgAFFAMJAwAAAA==.',
Co='Coms:BAAALgADCgIJAgAAAA==.Cooz:BAAALgAECgYJDgAAAA==.Corybooker:BAAALgAECgcJBAAAAA==.Cowdux:BAAALgAECgkJEAAAAA==.',
Cr='Creamdragon:BAAALgADCgYJCgABLgAECgcJKwAWANgdAA==.',
Cu='Curuni:BAAALgADCgYJCwAAAA==.',
Cz='Czechhunter:BAAALgADCgUJBQAAAA==.',
['Cå']='Cåleb:BAAALgAECgEJAQAAAA==.',
['Cø']='Cønstance:BAABLgAECn8VAAIXAAcJvRGIHAAqAQAXAAcJvRGIHAAqAQAAAA==.',
Da='Daddyphat:BAABLgAECn8rAAIYAAgJrCQfBQDWAgAYAAgJrCQfBQDWAgAAAA==.Daddý:BAAALgAECgEJAQAAAA==.Dalight:BAABLgAECn8XAAIHAAYJKiYPDwCdAgAHAAYJKiYPDwCdAgAAAA==.Dankins:BAACLgAFFH8bAAIZAAcJUyJyAQCUAgAZAAcJUyJyAQCUAgAuAAQKfxYAAhkACAkGHfYZAEcCABkACAkGHfYZAEcCAAAA.',
De='Deathmager:BAABLgAECn8vAAIaAAkJEA72TQDXAQAaAAkJEA72TQDXAQAAAA==.Deathtraper:BAAALgAECgcJDQAAAA==.Debur:BAAALgADCgEJAQAAAA==.Deltaka:BAAALgAECgEJAQAAAA==.Demonfella:BAAALgADCgMJAwAAAA==.Demonicpeach:BAABLgAECn8XAAIbAAcJHwtDmQD3AAAbAAcJHwtDmQD3AAAAAA==.Denaian:BAAALgADCgYJBgAAAA==.Dethsent:BAAALgAECgUJCwAAAA==.Dette:BAABLgAECn8ZAAIBAAcJgBPGTACQAQABAAcJgBPGTACQAQAAAA==.Devilchaser:BAAALgAECgYJCgAAAA==.Devourer:BAABLgAECn8VAAITAAcJjg+mbQBaAQATAAcJjg+mbQBaAQAAAA==.',
Di='Diaval:BAAALgADCgIJAgABLgAECgkJJgAbAPgSAA==.Dinosforlife:BAAALgAECgYJBgAAAA==.',
Do='Donzilly:BAAALgAECgYJDQAAAA==.Doreme:BAAALgADCgIJAgAAAA==.',
Dr='Drafted:BAAALgAECgcJEAAAAA==.Drax:BAAALgAECgMJAwAAAA==.Drewmcmoo:BAAALgADCgcJBgAAAA==.Drsath:BAAALgADCgcJBwAAAA==.Drunkorca:BAAALgADCgUJBQABLgAECggJMgAFANIcAA==.',
Ea='Earnar:BAAALgADCgYJDAAAAA==.',
Ed='Edarix:BAAALgADCggJDAABLgAECgYJKwAMANEWAA==.',
Ei='Eiliyah:BAABLgAECn8yAAMHAAgJehz0FgBaAgAHAAgJehz0FgBaAgAMAAIJHwIaWgElAAAAAA==.',
Ek='Ekmek:BAAALgAECgEJAQAAAA==.',
El='Elabernathy:BAABLgAECn8rAAIBAAgJjBYmLgD7AQABAAgJjBYmLgD7AQAAAA==.Elenay:BAABLgAECn8UAAIIAAgJqR6eHgAwAgAIAAgJqR6eHgAwAgAAAA==.Elesia:BAAALgAECgkJEgAAAA==.Elfussy:BAAALgAECgEJAQAAAA==.Elgoku:BAAALgAECgQJCgABLgAECgUJDAAJAAAAAA==.Eliarssande:BAAALgADCgQJBAAAAA==.Elinay:BAAALgADCgcJCQABLgAECggJFAAIAKkeAA==.Elixia:BAABLgAECn8bAAIGAAgJDA3jHQBSAQAGAAgJDA3jHQBSAQAAAA==.Elpatron:BAAALgAECgQJBAABLgAFFAMJCAAcABoNAA==.Elylanea:BAAALgAECgUJDgAAAA==.',
Em='Emulsdeath:BAAALgAECgcJEAABLgAFFAMJCQAMAHceAA==.Emulsifier:BAACLgAFFH8JAAIMAAMJdx4RPwANAQAMAAMJdx4RPwANAQAuAAQKfzAAAgwACAmFJsAIAAwDAAwACAmFJsAIAAwDAAAA.',
En='Ennoa:BAAALgAECgEJAQAAAA==.',
Er='Ergen:BAACLgAFFH8SAAIOAAUJthqPCgBYAQAOAAUJthqPCgBYAQAuAAQKfygAAg4ACAk6IaUGAJcCAA4ACAk6IaUGAJcCAAAA.',
Eu='Eusexua:BAAALgAECgQJBQABLgAECgcJCgAJAAAAAA==.',
Ex='Expiatory:BAAALgAECgYJCAAAAA==.',
Fa='Fairbear:BAABLgAECn8dAAQPAAYJ+By5MABnAQAPAAYJ+By5MABnAQAKAAEJZA5tPgA7AAAdAAEJ6QdDUAAbAAAAAA==.Faustt:BAAALgAECgUJBwAAAA==.',
Fi='Filthyfabio:BAAALgADCgcJEQAAAA==.Finester:BAAALgAFFAEJAQAAAA==.Fireburr:BAAALgAECgMJAwAAAA==.',
Fl='Flatline:BAAALgAECgYJDQAAAA==.Fløw:BAAALgAECgMJCgAAAA==.',
Fr='Fragglerott:BAABLgAECn8aAAMeAAgJ1AoPVAC8AAAeAAgJ1AoPVAC8AAAZAAQJUhJ2fACxAAAAAA==.Frati:BAAALgAECgEJAQAAAA==.Friedchickn:BAAALgAECgQJCAAAAA==.Frosttrinity:BAAALgADCgUJBAAAAA==.',
Fu='Funslinger:BAAALgAECgQJDAAAAA==.',
Ga='Gaffz:BAAALgAECgEJAQAAAA==.Galannar:BAAALgAECggJDQAAAA==.Galvrax:BAAALgAECgUJCgAAAA==.Gast:BAACLgAFFH8MAAIPAAQJMRwYEgBKAQAPAAQJMRwYEgBKAQAuAAQKfy0AAw8ACQksH98QAE8CAA8ACQksH98QAE8CAB0ABAmpFvMtAKgAAAAA.',
Ge='Gearwick:BAAALgADCgYJBwABLgAECgcJJgAHAFAhAA==.',
Gh='Ghstfacekila:BAAALgADCgEJAQAAAA==.',
Gl='Glizzybreath:BAAALgAECgUJBQABLgAECgYJBgAJAAAAAA==.',
Go='Gorska:BAABLgAECn8wAAIeAAkJmBxODwBZAgAeAAkJmBxODwBZAgAAAA==.',
Gr='Grawm:BAABLgAECn8iAAMNAAkJqiKzHgAxAgANAAgJSRWzHgAxAgABAAkJPiCrPADDAQAAAA==.Greedory:BAAALgADCgIJAgAAAA==.Groot:BAAALgADCgUJBgAAAA==.Gruetss:BAAALgAECgQJBAAAAA==.',
Ha='Hailbringer:BAAALgAECgcJDgAAAA==.Hakoona:BAABLgAECn8yAAIYAAkJFxqkDgAzAgAYAAkJFxqkDgAzAgAAAA==.Hanginaround:BAAALgAECgEJAQAAAA==.Hangman:BAACLgAFFH8MAAIHAAMJCSXdFgA+AQAHAAMJCSXdFgA+AQAuAAQKfxsAAwcACAloHwsMAKsCAAcACAloHwsMAKsCAAwAAwkbCYcrAVgAAAEuAAUUAwkJAAgAIhYA.Hanni:BAABLgAECn8dAAINAAgJUhxICQC7AQANAAgJUhxICQC7AQAAAA==.Haveaburitto:BAACLgAFFH8NAAIaAAQJWBx0QABGAQAaAAQJWBx0QABGAQAuAAQKfygAAhoACAk0JXkMAGEDABoACAk0JXkMAGEDAAAA.Hawktoetem:BAAALgAECgQJBQABLgAECgYJHQAPAPgcAA==.',
He='Healmemaybe:BAABLgAECn8bAAIIAAYJQiMWHgA0AgAIAAYJQiMWHgA0AgAAAA==.Healthyadult:BAAALgAECgMJBQAAAA==.Hellshand:BAAALgAECgYJDAAAAA==.Heracles:BAAALgAECgQJBAAAAA==.Heretic:BAAALgADCgEJAQAAAA==.',
Hi='Hickscale:BAAALgADCgMJAwAAAA==.',
Ho='Holycøw:BAAALgADCgMJAwAAAA==.Holydefender:BAAALgADCgYJCwAAAA==.Holyhands:BAAALgADCgYJBgAAAA==.Holyholyholy:BAAALgAECgQJBQAAAA==.Honest:BAAALgADCgMJAwAAAA==.',
Hu='Hunniee:BAAALgAECgEJAQAAAA==.Huntrix:BAAALgADCgcJEgAAAA==.',
Ic='Icedatt:BAAALgAECgUJEAAAAA==.Icefire:BAAALgADCgUJBAAAAA==.',
Ik='Ikur:BAACLgAFFH8LAAIHAAQJghl+GQAnAQAHAAQJghl+GQAnAQAuAAQKfzUAAgcACQnFHUsKAMUCAAcACQnFHUsKAMUCAAAA.',
Il='Ilinia:BAAALgAECgYJCAABLgAECgUJEgAJAAAAAA==.',
Im='Imsteve:BAAALgAECgEJAQAAAA==.',
In='Infoxicated:BAAALgADCgcJCAABLgAECgkJJAACALIeAA==.Insîght:BAAALgAECgQJBwAAAA==.',
Ip='Ipopkidneys:BAACLgAFFH8TAAMLAAUJICKXDAB1AQALAAQJ4yGXDAB1AQAUAAMJjB0JBQAOAQAuAAQKfycAAwsACQnhJYQMANACAAsACQnhJYQMANACABQAAQn1I7caAGcAAAAA.',
Ir='Iroi:BAAALgAECgIJBQAAAA==.',
Is='Iskur:BAABLgAECn8hAAIZAAgJ4BjnGwBCAgAZAAgJ4BjnGwBCAgABLgAFFAQJCwAHAIIZAA==.Isuck:BAAALgAFFAIJAgAAAA==.Isurr:BAABLgAECn8dAAIWAAcJnhL5KwCIAQAWAAcJnhL5KwCIAQABLgAFFAQJCwAHAIIZAA==.',
It='Itakecandle:BAAALgAECgUJBwABLgAECgUJDAAJAAAAAA==.',
Iv='Ivanapump:BAAALgAECgIJAgABLgAECgYJBgAJAAAAAA==.',
Ja='Jackkal:BAAALgAECgMJAwAAAA==.Jadethecat:BAAALgADCgMJAwAAAA==.Jakbis:BAAALgADCgEJAQAAAA==.Jakychan:BAAALgAECgEJAQAAAA==.Jaldiar:BAAALgADCgcJBwABLgAECgYJBgAJAAAAAA==.Jametrok:BAAALgAECgEJAQAAAA==.Jazbek:BAAALgAECgMJDQAAAA==.Jazzonus:BAAALgAECgQJBAAAAA==.',
Je='Jefferey:BAAALgADCgMJAwAAAA==.Jeriçho:BAAALgADCgYJBgAAAA==.',
Jh='Jhonwick:BAAALgAECgIJAgAAAA==.',
Ji='Jippedo:BAAALgAECgYJAgABLgAECgcJBAAJAAAAAA==.Jiraîya:BAAALgAECgQJBQAAAA==.',
Jo='Jordak:BAABLgAECn8oAAIIAAkJBBxICwDuAgAIAAkJBBxICwDuAgAAAA==.Jorolee:BAAALgADCgEJAQAAAA==.',
Ka='Kallistos:BAABLgAECn8gAAIZAAcJER37JAAFAgAZAAcJER37JAAFAgAAAA==.Kariza:BAAALgAECgMJAwAAAA==.Karunik:BAAALgADCgYJBgABLgAECgcJCgAJAAAAAA==.',
Ke='Kelenheller:BAAALgADCgcJCAAAAA==.',
Kh='Khione:BAAALgADCgYJBgAAAA==.Khthonios:BAAALgADCgYJBgAAAA==.',
Ki='Kibblerina:BAAALgADCgcJBwAAAA==.Kiranam:BAABLgAECn8cAAQfAAgJrQ6dEQCTAQAfAAgJqQqdEQCTAQAXAAcJNQz1KQDKAAASAAIJWwfecQBZAAAAAA==.',
Kn='Knarth:BAABLgAECn8xAAIgAAgJhBvAAQBCAgAgAAgJhBvAAQBCAgAAAA==.',
Ko='Koisy:BAAALgAECgIJCQABLgAECggJFAAIAKkeAA==.Kole:BAAALgAECgEJAQAAAA==.Koopa:BAABLgAECn8kAAIPAAkJ3iLYBwDEAgAPAAkJ3iLYBwDEAgAAAA==.',
Kr='Krasul:BAACLgAFFH8VAAMZAAUJEBhTFAB+AQAZAAUJEBhTFAB+AQAeAAIJ7QmiNgB9AAAuAAQKfx8AAxkACAkXIecIAOgCABkACAkXIecIAOgCAB4ABgm/HPIxAJQBAAAA.Krenthok:BAABLgAECn8eAAIbAAgJiQdydQA7AQAbAAgJiQdydQA7AQAAAA==.',
Ku='Kuraha:BAAALgAECgQJBAAAAA==.Kushar:BAAALgAECgQJBQABLgAECgcJFAAhAP8QAA==.',
La='Large:BAAALgADCgYJBgAAAA==.Largemann:BAAALgAECgYJDAABLgAFFAQJDQAFAN4YAA==.Lathspell:BAABLgAECn8yAAIaAAkJtiBiHQCTAgAaAAkJtiBiHQCTAgAAAA==.Lazyevoker:BAAALgADCgQJBAABLgAECgEJAQAJAAAAAA==.',
Le='Leahan:BAAALgAECgQJCgAAAA==.Leloo:BAAALgADCgYJCgABLgAECgIJAgAJAAAAAA==.',
Lh='Lhureciv:BAACLgAFFH8NAAMDAAQJWhcAEABKAQADAAQJWhcAEABKAQACAAEJKRt6OABKAAAuAAQKf0oAAwMACQnVI6sHALkCAAMACQnVI6sHALkCAAIABgn7HjAjAHoBAAAA.',
Li='Lightchaser:BAAALgADCgMJAgAAAA==.Lightfkyou:BAAALgADCgcJCgAAAA==.Lihvurce:BAABLgAECn8YAAMMAAYJYxyAawB6AQAMAAYJYxyAawB6AQAHAAQJpR0FSwBMAQABLgAFFAQJDQADAFoXAA==.Lillianna:BAACLgAFFH8FAAILAAIJoQ8cJwCdAAALAAIJoQ8cJwCdAAAuAAQKfyoAAgsACAlBGlgPABQCAAsACAlBGlgPABQCAAAA.Lingchi:BAAALgAECgQJBgAAAA==.',
Ll='Llew:BAAALgAECgMJBAAAAA==.',
Lo='Loenhart:BAAALgAECgEJAQAAAA==.Lolkurtone:BAAALgAECgIJAgAAAA==.',
Lu='Luciaan:BAAALgADCgcJEgAAAA==.Lucrative:BAAALgADCgcJDQAAAA==.Lug:BAAALgAECgEJAQAAAA==.Lulue:BAAALgADCgQJBAAAAA==.Luminari:BAAALgADCgUJBQAAAA==.Lunastorm:BAACLgAFFH8GAAIcAAQJ4g2VGADeAAAcAAQJ4g2VGADeAAAuAAQKfzYAAhwACQlhIaICACADABwACQlhIaICACADAAAA.Luponero:BAACLgAFFH8QAAMBAAQJ8SJsEQCAAQABAAQJ8SJsEQCAAQANAAEJ5QapKgBGAAAuAAQKfyEAAw0ACAnnHuYQALUCAA0ACAl6HeYQALUCAAEAAwnNH9KAABEBAAAA.',
Ly='Lynney:BAAALgADCgYJBwAAAA==.',
Ma='Macmn:BAACLgAFFH8QAAIeAAQJrhe1FwArAQAeAAQJrhe1FwArAQAuAAQKfygAAh4ABwnAJGULAOICAB4ABwnAJGULAOICAAAA.Magicard:BAABLgAECn8bAAIaAAgJ6AyFbwCBAQAaAAgJ6AyFbwCBAQAAAA==.Makesfood:BAABLgAECn8qAAIaAAcJZBeSdADpAQAaAAcJZBeSdADpAQAAAA==.Mamaheals:BAABLgAECn8kAAIEAAgJyBloHAC/AQAEAAgJyBloHAC/AQAAAA==.Mandos:BAAALgAECgYJBgAAAA==.Mantistabogn:BAAALgAECgYJDwAAAA==.Maor:BAABLgAECn8XAAIMAAgJlxcuUADxAQAMAAgJlxcuUADxAQAAAA==.March:BAAALgADCgEJAQAAAA==.Markeisha:BAAALgAECgQJCAAAAA==.',
Me='Mechz:BAAALgAECgYJBgABLgAFFAMJBQAaAEUIAA==.Mechzician:BAACLgAFFH8FAAIaAAMJRQiebwDZAAAaAAMJRQiebwDZAAAuAAQKfzgAAhoACAlwGWVNANkBABoACAlwGWVNANkBAAAA.Mechzlock:BAAALgADCgEJAQABLgAFFAMJBQAaAEUIAA==.Melinoe:BAAALgAECgEJAQAAAA==.Merlerk:BAAALgADCgYJBgAAAA==.Merlini:BAABLgAECn8aAAMDAAcJrBTdKwBPAQADAAYJThfdKwBPAQACAAUJThZCMwAfAQAAAA==.Mets:BAAALgAECgEJAQABLgAECgcJDAAJAAAAAA==.',
Mi='Microplastic:BAAALgAECgUJBQAAAA==.Micspanky:BAAALgAECggJEgAAAA==.Mithrandi:BAAALgAECgYJCQAAAA==.Mitzis:BAABLgAFFH8FAAIBAAMJuhdLPAD8AAABAAMJuhdLPAD8AAAAAA==.',
Mo='Mornhathor:BAAALgAECggJDgABLgAECgYJBgAJAAAAAA==.',
Mu='Mufinblaster:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgADCgIJBgAAAA==.Musnicker:BAAALgAECgQJBwABLgAECgcJDQAJAAAAAA==.',
['Mè']='Mètis:BAAALgAECgcJCAAAAA==.',
Na='Nanis:BAAALgAECgEJAQAAAA==.Narmer:BAAALgAECgIJAgAAAA==.',
Ne='Neel:BAAALgADCgQJBQAAAA==.Nervhoost:BAAALgADCgMJAwAAAA==.Neuropolis:BAAALgADCgcJFQAAAA==.Neuroscience:BAAALgADCgMJAwAAAA==.Neurotics:BAABLgAECn8lAAQiAAgJEiSUAwAyAgAiAAcJjCKUAwAyAgAjAAYJ/h+gBgDeAQAbAAUJ5BoBuwDjAAAAAA==.Neò:BAABLgAECn8YAAMkAAYJvBDyDQARAQAkAAYJXw7yDQARAQAlAAEJ/hTEewA4AAAAAA==.',
Ni='Niesh:BAAALgAECgEJBwAAAA==.Nineoneone:BAABLgAECn8lAAMEAAgJphEvIwCJAQAEAAgJphEvIwCJAQACAAQJjgPqRQCLAAAAAA==.',
No='Nobledecay:BAAALgAECgQJBQAAAA==.Nocturne:BAAALgAECgEJAwAAAA==.',
Nu='Nubbletcake:BAAALgADCgEJAQABLgAECgkJJAACALIeAA==.',
Ny='Nylveth:BAACLgAFFH8LAAIDAAUJHQ34FQAeAQADAAUJHQ34FQAeAQAuAAQKfyoAAgMACQkAHecMAGQCAAMACQkAHecMAGQCAAAA.',
Oc='Ocra:BAABLgAECn8YAAImAAYJuAkeGwDkAAAmAAYJuAkeGwDkAAABLgAFFAQJDgABAFIVAA==.',
Of='Offspeck:BAAALgAECgIJAgABLgAECgkJIAAbAFYcAA==.',
Ou='Outtkast:BAAALgAECgIJAgAAAA==.Outtkastt:BAAALgADCgEJAQAAAA==.Ouutkast:BAAALgAECgEJAgAAAA==.',
Oz='Ozwald:BAABLgAECn81AAIOAAkJchwgDQA6AgAOAAkJchwgDQA6AgAAAA==.',
Pa='Pallyangel:BAAALgADCgcJDwAAAA==.Pandemul:BAAALgAECgMJAwABLgAFFAMJCQAMAHceAA==.Patrio:BAACLgAFFH8IAAIcAAMJGg3eGgC8AAAcAAMJGg3eGgC8AAAuAAQKfywAAhwACQllGZIGAHoCABwACQllGZIGAHoCAAAA.',
Pe='Peaceonea:BAAALgAECgYJEwAAAA==.Peachaid:BAECLgAFFH8YAAICAAgJ9RfxAgDAAgACAAgJ9RfxAgDAAgAuAAQKfzAAAwIACQlVIgMEAD0DAAIACQlVIgMEAD0DAAQABgkYHSglAMABAAAA.Peatri:BAAALgAECgkJCwAAAA==.Peetree:BAAALgAECgkJEAAAAA==.',
Ph='Phosphorus:BAACLgAFFH8OAAIKAAQJihMNEAAgAQAKAAQJihMNEAAgAQAuAAQKf1cAAwoACQnHHqQDAMwCAAoACQnHHqQDAMwCAB0ABAlNHiYkAOkAAAAA.',
Pl='Plagüë:BAACLgAFFH8LAAMFAAMJiiA2XwATAQAFAAMJiiA2XwATAQAQAAEJWwnLMAAyAAAuAAQKf0sAAwUACQnaJOEOANkCAAUACQnaJOEOANkCABAABQmbD7svALYAAAAA.Pleistarchus:BAAALgAECgYJCQAAAA==.',
Po='Poic:BAAALgADCgEJAQAAAA==.Poofighter:BAAALgAECgMJAwABLgAFFAIJBgAGAAohAA==.Poonan:BAAALgAECgYJBgAAAA==.',
Pp='Ppgangandlaw:BAAALgADCgEJAQAAAA==.',
Pr='Precious:BAAALgAECgYJEAAAAA==.Primalistic:BAAALgADCgUJBQABLgAFFAMJBQAaAEUIAA==.Primàl:BAABLgAECn8sAAIIAAYJBRv2NADUAQAIAAYJBRv2NADUAQAAAA==.',
Pu='Purifieds:BAAALgADCgEJAQAAAA==.',
Qs='Qsrqasda:BAABLgAECn8UAAIQAAYJ4QViNQCXAAAQAAYJ4QViNQCXAAAAAA==.',
Qt='Qtmenopaws:BAAALgAECgQJAwAAAA==.Qtptt:BAACLgAFFH8SAAIbAAMJpB9JHQAPAQAbAAMJpB9JHQAPAQAuAAQKfz0AAhsACAkpIyAUAJkCABsACAkpIyAUAJkCAAAA.',
Ra='Ragedeath:BAABLgAFFH8JAAIQAAMJuA8DHwC1AAAQAAMJuA8DHwC1AAAAAA==.Ragedh:BAAALgAECgIJAgABLgAFFAMJCQAQALgPAA==.Ragemonk:BAAALgADCgQJBAABLgAFFAMJCQAQALgPAA==.Rasmong:BAABLgAECn8UAAIhAAcJ/xCvKABKAQAhAAcJ/xCvKABKAQAAAA==.Ravinsinda:BAAALgAECgYJBgAAAA==.Ravinursula:BAAALgAECgYJDQAAAA==.Rawrsaur:BAAALgAECgcJDQAAAA==.',
Re='Really:BAAALgADCgYJBgABLgAECgEJAQAJAAAAAA==.Reallyhpal:BAAALgAECgEJAQAAAA==.Redder:BAAALgAECgEJAQAAAA==.Retaliator:BAABLgAECn8rAAMMAAYJ0Rb1iQBnAQAMAAYJ0Rb1iQBnAQAnAAEJ1QYSTAAbAAAAAA==.Revan:BAAALgAECgYJBwAAAA==.',
Rh='Rhýs:BAAALgAECgYJBgAAAA==.',
Ri='Rih:BAAALgADCgMJBQAAAA==.Ripits:BAAALgADCgcJCAABLgAECgEJAQAJAAAAAA==.Risky:BAAALgAECgkJAwAAAA==.Riskyfist:BAAALgAECgcJAgAAAA==.Risquae:BAAALgAECgIJAgAAAA==.',
Ro='Roadrashnuts:BAAALgAECgMJAwAAAA==.Rocc:BAAALgAECgcJBAAAAA==.Rocketeer:BAABLgAECn8kAAIaAAgJ1gvUjwA/AQAaAAgJ1gvUjwA/AQAAAA==.Romulis:BAAALgAECgEJAQAAAA==.Ronburgundii:BAAALgAECgEJAQAAAA==.',
Ru='Rudrya:BAABLgAECn8UAAImAAgJcAfhEwB8AQAmAAgJcAfhEwB8AQAAAA==.Rumpkey:BAAALgADCgYJBgAAAA==.Runalish:BAAALgAECgEJAQAAAA==.Runarinis:BAAALgADCgIJAgAAAA==.',
Ry='Rynopinn:BAACLgAFFH8JAAIIAAMJIhYLLQDkAAAIAAMJIhYLLQDkAAAuAAQKf0QABAgACAnqIxkLAOgCAAgACAnqIxkLAOgCAB8ABwmcGv0KAN0BABIAAgn4F7xWAIgAAAAA.Ryxn:BAAALgADCgYJBgAAAA==.',
['Rí']='Ríco:BAAALgADCgYJCwAAAA==.',
Sa='Saeed:BAAALgAECgEJAQAAAA==.Saelylasia:BAAALgAECgQJBQAAAA==.Sajaboy:BAAALgAECgMJBAAAAA==.Samusaran:BAAALgADCgEJAQAAAA==.Sarrania:BAAALgAECgUJBQAAAA==.Sartha:BAABLgAECn8iAAIMAAgJZhQ6TwC+AQAMAAgJZhQ6TwC+AQAAAA==.Sasuka:BAAALgADCgUJCwAAAA==.Satsu:BAAALgAECgEJAQAAAA==.',
Sc='Scatherlia:BAAALgADCgYJBQABLgAECgQJBQAJAAAAAA==.Sco:BAAALgADCgEJAQABLgAECgYJDQAJAAAAAA==.Screwthebull:BAAALgAECgQJBAAAAA==.Scrumpvincet:BAAALgADCgQJBQAAAA==.',
Se='Sectiondk:BAAALgAECgYJEwAAAA==.Sedda:BAACLgAFFH8XAAIMAAYJVSNWBwD0AQAMAAYJVSNWBwD0AQAuAAQKfy0AAgwACAmnJc4GAGMDAAwACAmnJc4GAGMDAAAA.Seigfreid:BAAALgAECgYJCAAAAA==.Sensual:BAACLgAFFH8NAAInAAQJ5AaTCQCwAAAnAAQJ5AaTCQCwAAAuAAQKf0kAAicACQlTFB0PAKYBACcACQlTFB0PAKYBAAAA.Seraphina:BAAALgAECgQJCgAAAA==.Sessano:BAAALgAECgYJDQAAAA==.Sesshomaru:BAACLgAFFH8GAAMGAAIJCiEBHABdAAAGAAEJ0CMBHABdAAATAAEJRB4RdQBXAAAuAAQKf08AAxMACQnUIxcTAOcCABMACAm3IRcTAOcCAAYACAkvJPcIAHACAAAA.',
Sh='Shadoly:BAAALgAECgcJEQAAAA==.Shadowboss:BAABLgAECn8iAAIDAAYJixH4NgAUAQADAAYJixH4NgAUAQAAAA==.Shamnslam:BAAALgAECgEJAQAAAA==.Shang:BAABLgAECn8uAAQSAAgJbyWkBQDlAgASAAgJbyWkBQDlAgAXAAMJvh6kLgCwAAAIAAIJwxK2uQA3AAAAAA==.Shirona:BAABLgAECn8fAAITAAkJAhz0EQCYAgATAAkJAhz0EQCYAgAAAA==.Shockazulu:BAAALgADCgEJAQAAAA==.Showstop:BAAALgAECgEJAQAAAA==.Shyvanna:BAABLgAECn8lAAMlAAkJ0RBbHwC9AQAlAAkJ0RBbHwC9AQAkAAQJ0wrYGABrAAAAAA==.Shïnïgämï:BAABLgAECn8WAAIoAAYJiCAvCQDeAQAoAAYJiCAvCQDeAQABLgAFFAIJBgAZABwcAA==.',
Si='Siare:BAAALgAECgYJEQABLgAECgcJDAAJAAAAAA==.Sigarda:BAAALgAECgQJBAAAAA==.Silica:BAAALgAECgMJAwAAAA==.Silvershot:BAAALgADCgUJBQAAAA==.Siner:BAAALgAECgUJCAAAAA==.',
Sk='Skeeter:BAABLgAECn81AAQiAAkJLB18AgBsAgAiAAkJBRp8AgBsAgAbAAkJBRc+RAC5AQAjAAcJ0hxGCgCKAQAAAA==.Skiadrum:BAACLgAFFH8FAAIhAAMJgQFHKgBsAAAhAAMJgQFHKgBsAAAuAAQKfzsAAxYACQn+EMwrAIkBABYACAnmDswrAIkBACEABAlBCWpVAI0AAAAA.Skoliro:BAAALgAECgUJBQAAAA==.Skorch:BAAALgADCgkJEAABLgAFFAMJBQAaAEUIAA==.',
Sm='Smotts:BAAALgAECgcJDAAAAA==.Smòtts:BAAALgAECgUJBgAAAA==.',
Sn='Snizard:BAAALgAECgcJEwAAAA==.Snuggiepoo:BAABLgAECn8kAAMCAAkJsh72CAC/AgACAAgJ5CD2CAC/AgADAAYJgRUqTACyAAAAAA==.',
So='Songbirds:BAAALgADCgcJDQAAAA==.Sonichoos:BAAALgAECgUJDAAAAA==.Sophiel:BAABLgAECn8aAAITAAYJShWTbAAnAQATAAYJShWTbAAnAQAAAA==.Sosthenna:BAAALgADCgkJCQAAAA==.Soulbark:BAAALgAECgMJAwABLgAECgQJBAAJAAAAAQ==.Souleater:BAAALgADCgMJAwAAAA==.Soulforged:BAAALgADCgcJCwABLgAECgQJBAAJAAAAAA==.Soulweaver:BAAALgAECgQJBAAAAQ==.',
Sp='Sparrowhåwk:BAAALgADCgUJBgAAAA==.Spongebill:BAAALgADCgEJAQAAAA==.Spàdes:BAABLgAECn8VAAMPAAYJmhkxSwB4AQAPAAUJOB0xSwB4AQAKAAMJTA5LQQCSAAAAAA==.',
St='Starel:BAAALgAECgIJAgAAAA==.Stellanoova:BAAALgAECgMJAwABLgAECggJFQAlAEoUAA==.Stevebushami:BAAALgAECgYJEAAAAA==.Stuwu:BAAALgADCgcJBwAAAA==.',
Su='Suou:BAAALgADCgcJCQABLgAECgEJAgAJAAAAAA==.Surj:BAABLgAECn8XAAMdAAYJSBaaHAAqAQAdAAYJKRWaHAAqAQAPAAQJeAs/WQDCAAAAAA==.',
Sv='Svmii:BAAALgADCgcJCgAAAA==.',
Ta='Taikuri:BAAALgAECgcJDAAAAA==.Taliela:BAAALgAECgQJBAAAAA==.Tanddralndra:BAAALgAECgUJBwAAAA==.Tanklilbaby:BAAALgAECgEJAQAAAA==.Taxgirl:BAACLgAFFH8NAAMFAAQJ3hiyQABFAQAFAAQJ3hiyQABFAQARAAEJsQM/HAA4AAAuAAQKfx0AAgUACAnOJGISAA0DAAUACAnOJGISAA0DAAAA.',
Te='Teralion:BAAALgAECgMJBgAAAA==.',
Th='Thaeldrik:BAAALgADCgcJBwAAAA==.Thaldreaux:BAAALgAECgMJBAAAAA==.Thefirst:BAAALgAECgEJAQAAAA==.Theleon:BAABLgAECn8dAAISAAgJQg/WJwBkAQASAAgJQg/WJwBkAQAAAA==.Thordrin:BAABLgAECn8lAAIHAAcJVx88GABQAgAHAAcJVx88GABQAgAAAA==.Thorlan:BAAALgADCgYJCAAAAA==.Thrasherzs:BAAALgAECgUJCwAAAA==.Thryen:BAAALgADCgYJBgAAAA==.Thunder:BAAALgADCgQJBAABLgAECgcJCgAJAAAAAA==.Thundergrasp:BAACLgAFFH8FAAImAAUJpAtNBgAoAQAmAAUJpAtNBgAoAQAuAAQKfxsAAiYABwkNGwoMAL8BACYABwkNGwoMAL8BAAEuAAUUBQkLAAMAHQ0A.',
Ti='Tianhe:BAAALgAECgMJAwAAAA==.Tiarisaril:BAAALgAECgYJBgAAAA==.Tigercita:BAAALgAECgMJAgAAAA==.Tippah:BAAALgAECgEJAwAAAA==.Tippers:BAAALgAECgEJAQAAAA==.',
To='Toe:BAAALgAECgUJBwAAAA==.Tonkah:BAAALgAECgUJBQABLgAECggJDwAJAAAAAA==.Toobestake:BAAALgAECgEJAQABLgAFFAQJEAABAPEiAA==.Topenga:BAACLgAFFH8OAAIBAAQJUhVqJAA/AQABAAQJUhVqJAA/AQAuAAQKf0sAAgEACQnNH2kSAKQCAAEACQnNH2kSAKQCAAAA.Touchypope:BAAALgADCgYJCwAAAA==.',
Tr='Treeage:BAAALgADCgMJAwAAAA==.Triggerd:BAAALgADCgEJAQAAAA==.Trunks:BAAALgADCgQJBAAAAA==.Trylok:BAAALgADCgEJAQAAAA==.Trüst:BAAALgAECggJDgAAAA==.',
Tw='Twicelife:BAAALgAECgYJEwABLgAFFAQJDgAKAIoTAA==.',
Ty='Tyrygosa:BAAALgAECgUJBQABLgAFFAQJDQAbAMEWAA==.',
['Tå']='Tånk:BAAALgAECggJEwAAAA==.',
Un='Uneedsummilk:BAAALgADCgcJBwAAAA==.Unholyapollo:BAAALgADCgYJCwAAAA==.',
Ur='Urthstripe:BAABLgAECn8iAAIIAAgJwxcPHQA8AgAIAAgJwxcPHQA8AgAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCAAFAIkhAA==.Valle:BAAALgAECgIJAwABLgAFFAcJGgADALAaAA==.Valoria:BAAALgAECgIJBQABLgAFFAcJGgADALAaAA==.',
Ve='Veil:BAAALgAECgIJBAABLgAFFAcJGgADALAaAA==.Velarenea:BAAALgADCgEJAQAAAA==.Velgabrine:BAAALgAECgYJDAABLgAFFAMJCQAMAHceAA==.Veraani:BAAALgAECgYJBgAAAA==.Verra:BAAALgADCgYJBgAAAA==.',
Vi='Vil:BAAALgADCgcJBgAAAA==.Virlan:BAAALgADCgQJBAAAAA==.Viserion:BAABLgAECn8VAAMlAAgJShS4NAA5AQAlAAcJZBK4NAA5AQAcAAYJ2AwkHQDxAAAAAA==.',
Vo='Voidchaosfan:BAAALgAECgQJBgABLgAECgQJCAAJAAAAAA==.',
Vu='Vue:BAACLgAFFH8MAAIHAAQJQxNrHAAQAQAHAAQJQxNrHAAQAQAuAAQKf0YAAgcACQkkGycbAAYCAAcACQkkGycbAAYCAAAA.Vuldin:BAAALgAECgEJAgAAAA==.',
['Vö']='Völdemört:BAAALgADCgIJAgAAAA==.',
Wa='Wakasham:BAACLgAFFH8RAAImAAUJSiN2AQCAAQAmAAUJSiN2AQCAAQAuAAQKfzAAAiYACQk5Jp4BAFMDACYACQk5Jp4BAFMDAAAA.Wardrake:BAAALgAECgEJAQAAAA==.',
We='Wehonoryou:BAABLgAECn8WAAIGAAYJ9CHYGAAAAgAGAAYJ9CHYGAAAAgAAAA==.Wetard:BAAALgADCgIJAgAAAA==.',
Wi='Willbyers:BAAALgAECgEJAQAAAA==.Winterloom:BAAALgAECgYJBgAAAA==.',
Wo='Wolfpacked:BAACLgAFFH8GAAIZAAIJHBxqRACnAAAZAAIJHBxqRACnAAAuAAQKfygAAhkACQlBIF0GACcDABkACQlBIF0GACcDAAAA.Wolfzbåin:BAAALgAECgQJBAAAAA==.',
Wr='Wroot:BAAALgADCgYJCQAAAA==.Wrotten:BAABLgAECn8WAAIjAAgJ6RejBwDCAQAjAAgJ6RejBwDCAQAAAA==.',
Wu='Wunderlust:BAACLgAFFH8IAAIaAAQJHhGmSQA3AQAaAAQJHhGmSQA3AQAuAAQKf0QAAhoACQmFISYcAAYDABoACQmFISYcAAYDAAAA.',
Xe='Xemon:BAAALgAECgIJAgAAAA==.',
Xi='Xilyana:BAAALgAECgQJBAAAAA==.',
Xm='Xmatick:BAAALgAECgcJCQAAAA==.',
Xs='Xscrats:BAAALgAECgkJBwAAAA==.',
Ye='Yellowshaman:BAACLgAFFH8ZAAIeAAUJthh2EwBGAQAeAAUJthh2EwBGAQAuAAQKfzEAAh4ACQl1IUQMANcCAB4ACQl1IUQMANcCAAAA.Yerac:BAAALgAECgEJAQAAAA==.',
Yu='Yukikage:BAAALgAECgMJAwAAAA==.Yutdaeng:BAAALgAECgMJBAAAAA==.',
Yv='Yvent:BAAALgADCgIJAgAAAA==.Yvraine:BAAALgAECgYJDQAAAA==.',
Za='Zakcarii:BAAALgADCgMJCAAAAA==.Zalicy:BAAALgAECgYJEwAAAA==.Zalogar:BAAALgAECgcJCgAAAA==.Zapper:BAAALgAECgQJCQAAAA==.',
Zb='Zbarbb:BAAALgADCgUJBQAAAA==.',
Ze='Zealot:BAAALgAECgEJAQAAAA==.Zeeasyez:BAAALgAECgYJEQAAAA==.Zestul:BAAALgADCgEJAQAAAA==.',
Zh='Zhane:BAAALgADCgYJBwAAAA==.',
Zo='Zordon:BAAALgAECgYJEwAAAA==.',
Zu='Zugg:BAAALgAECgIJBAABLgAFFAcJGgADALAaAA==.Zuriznikov:BAAALgAECgEJAQABLgAECggJFQAlAEoUAA==.',
['Ån']='Ångie:BAAALgADCgMJAwAAAA==.',
['Øf']='Øffspeck:BAABLgAECn8gAAQbAAkJVhweLgBVAgAbAAgJwxgeLgBVAgAjAAcJICH8CACkAQAiAAMJzh7MMAD3AAAAAA==.',
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
