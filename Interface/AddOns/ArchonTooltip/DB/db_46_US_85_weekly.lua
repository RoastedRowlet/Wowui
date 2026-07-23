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

local lookup = {'Druid-Feral','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Evoker-Augmentation','Hunter-BeastMastery','Unknown-Unknown','Priest-Discipline','Shaman-Elemental','Monk-Mistweaver','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Druid-Restoration','Rogue-Subtlety','Priest-Holy','Druid-Balance','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Paladin-Holy','Hunter-Survival','Monk-Brewmaster','Mage-Frost','Druid-Guardian','Rogue-Assassination','DeathKnight-Unholy','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Protection','Rogue-Outlaw','Hunter-Marksmanship',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abominable:BAAALgADCgEJAQAAAA==.',
Ae='Aelaster:BAAALgADCgYJBgAAAA==.',
Ag='Agden:BAAALgADCgEJAQAAAA==.',
Al='Alaìrn:BAAALgAECgUJCwABLgAECgkJFgABAKcdAA==.Aldrich:BAAALgAECgYJBwAAAA==.Alenciann:BAAALgAECgMJBwAAAA==.Allayna:BAAALgAECgEJAQAAAA==.Alstre:BAAALgAECgEJAQAAAA==.Alys:BAABLgAECn86AAICAAkJYw4IIgCfAQACAAkJYw4IIgCfAQAAAA==.',
Am='Amaniatres:BAABLgAECn8pAAMDAAgJqhPnAgCBAQADAAgJGhPnAgCBAQAEAAQJEw8XSwChAAABLgAECgcJFAAFAP4VAA==.Ammartin:BAABLgAECn8YAAIGAAkJyQo1bQBnAQAGAAkJyQo1bQBnAQAAAA==.Amoonranara:BAAALgADCgEJAQAAAA==.',
An='Anaan:BAAALgAECgUJBgAAAA==.Anahera:BAAALgADCgQJBAABLgAECgYJDgAHAAAAAA==.Anfna:BAAALgAECgEJAQAAAA==.Angrylizard:BAAALgAECgEJAgAAAA==.Anklebiterr:BAAALgAECgUJBwAAAA==.',
Ap='Apothecary:BAAALgADCgcJBwAAAA==.',
Ar='Arabella:BAAALgAECggJEQAAAA==.Arandomidiot:BAAALgADCgYJBgAAAA==.Arathan:BAAALgADCgkJHAAAAA==.Ariiana:BAABLgAECn8XAAIIAAkJIx7rBgAOAwAIAAkJIx7rBgAOAwAAAA==.Arngal:BAAALgAECgEJAQAAAA==.',
As='Asapshocky:BAACLgAFFH8TAAIJAAgJLhi9CgBqAQAJAAgJLhi9CgBqAQAuAAQKfy4AAgkACQnTIxIFAA0DAAkACQnTIxIFAA0DAAAA.Asclepios:BAAALgAECgMJBAAAAA==.Asmoday:BAAALgAECgYJBgAAAA==.Astraroth:BAAALgADCgQJBAAAAA==.',
Av='Avella:BAAALgADCgUJBwAAAA==.',
Ba='Balaris:BAAALgADCgcJBwABLgAECgkJIwAKACEUAA==.Balum:BAAALgAECgEJAQAAAA==.Bamwham:BAAALgADCgcJBwAAAA==.Barrii:BAAALgAECgMJBQAAAA==.',
Be='Bearblaster:BAAALgADCgQJBAABLgAECgQJBgAHAAAAAA==.Bearlytanks:BAAALgADCgIJAgAAAA==.Beastwallker:BAAALgADCgUJBgAAAA==.Bellabelle:BAAALgAECgUJCgAAAA==.Ben:BAAALgAECgcJEwAAAA==.Betamaxx:BAACLgAFFH8HAAMLAAMJuBH5LwCDAAALAAIJThb5LwCDAAAMAAIJAwjXEQB8AAAuAAQKfxUAAgsABwmCHYgSAOYBAAsABwmCHYgSAOYBAAAA.Betterx:BAAALgAECgQJBQAAAA==.Bevian:BAAALgAECgEJAQABLgAECgkJDgAHAAAAAA==.',
Bi='Biggiepants:BAABLgAECn8iAAMNAAkJ0h9oBwC7AgANAAkJ0h9oBwC7AgAOAAgJ9w6fYABoAQAAAA==.Bighead:BAAALgAECgYJCAABLgAFFAMJBwACALYHAA==.Bigwarlocks:BAAALgAECgMJBwABLgAFFAMJBwACALYHAA==.Bintje:BAAALgADCgcJEgAAAA==.Biollante:BAAALgAECgcJCwAAAA==.',
Bl='Blindedlïght:BAAALgAECgUJBgAAAA==.',
Bo='Bolsan:BAAALgAECgMJBQAAAA==.Bonq:BAAALgAECgIJAgABLgAECgkJEQANACUcAA==.Bourg:BAAALgAECgYJCAAAAA==.Bowhemian:BAAALgAECgMJBgAAAA==.',
Bu='Buckis:BAABLgAECn8WAAIPAAcJvRaACwB2AQAPAAcJvRaACwB2AQAAAA==.Bufú:BAAALgADCgIJAgAAAA==.',
['Bö']='Böurbon:BAAALgADCgkJCgAAAA==.',
Ca='Cahk:BAAALgAECgMJAwAAAA==.Cajia:BAABLgAECn8uAAMQAAkJ4wo8HQC+AAARAAkJgwndfgA7AQAQAAYJBgs8HQC+AAAAAA==.Canon:BAAALgAECgkJAwAAAA==.',
Ce='Celds:BAAALgADCgQJBAABLgAECgcJGQASAPEbAA==.Celiae:BAAALgAECgYJEAAAAA==.Cendanel:BAAALgAECgIJAgAAAA==.',
Ch='Childress:BAAALgAECgMJAwAAAA==.Chiwhiz:BAAALgAECgEJAQABLgAECgQJCwAHAAAAAA==.Choggy:BAABLgAECn8uAAITAAkJxhvnDgBqAgATAAkJxhvnDgBqAgAAAA==.Chogs:BAAALgAECgMJBAABLgAECgkJLgATAMYbAA==.',
Ci='Cimbline:BAAALgADCgIJAgAAAA==.',
Cl='Clairerick:BAAALgAECgYJEAAAAA==.Clenise:BAAALgAECgEJAQAAAA==.',
Co='Cokebear:BAAALgAECgMJAwABLgAECggJJAAUAHEaAA==.Composer:BAABLgAECn8UAAIFAAcJ/hXSAwBlAQAFAAcJ/hXSAwBlAQAAAA==.Confessionn:BAAALgADCggJDAAAAA==.Cough:BAAALgAECgUJCwABLgAFFAMJBwACALYHAA==.',
Cr='Crinklecut:BAABLgAECn8ZAAIVAAgJQQwKJQBtAQAVAAgJQQwKJQBtAQAAAA==.Critos:BAAALgADCgcJBwAAAA==.Crotchout:BAAALgADCgMJAwAAAA==.Crybaby:BAAALgADCgEJAQAAAA==.Crystilpixy:BAAALgADCgMJBAAAAA==.',
['Cé']='Céline:BAAALgAECgEJAQAAAA==.',
Da='Dalal:BAAALgAECgQJBgABLgAECgkJUgAWAKUaAA==.Danielallen:BAAALgAECgUJBQAAAA==.Danilov:BAAALgADCgYJBgAAAA==.',
De='Deadlyshift:BAABLgAECn8XAAMUAAkJsCKWBQBeAwAUAAkJsCKWBQBeAwAXAAUJMho8NgBjAQAAAA==.Deadmenace:BAAALgAECgEJAQAAAA==.Deadybear:BAAALgADCgkJEAABLgAECgkJSgAYAFMSAA==.Deathkyter:BAAALgAECgEJAQAAAA==.Delrok:BAAALgAECgEJAgAAAA==.Dephias:BAAALgADCgMJAwAAAA==.',
Di='Diagnosis:BAABLgAECn8eAAIPAAkJhSVqCwAKAwAPAAkJhSVqCwAKAwAAAA==.',
Do='Donnabb:BAABLgAECn8YAAIPAAgJCQWRKgB+AAAPAAgJCQWRKgB+AAAAAA==.Donteatbees:BAABLgAECn8UAAIMAAkJZgquGAAPAQAMAAkJZgquGAAPAQAAAA==.Dop:BAAALgAECgEJAwAAAA==.Doran:BAABLgAECn8eAAINAAgJaRcHFwDNAQANAAgJaRcHFwDNAQAAAA==.Doriathrin:BAAALgADCgcJCwAAAA==.Doujinshi:BAABLgAECn8OAAIOAAcJIBziUwCoAQAOAAcJIBziUwCoAQAAAA==.',
Dr='Dragonbladez:BAAALgADCgUJBQAAAA==.Dragoneye:BAAALgAECgMJBgAAAA==.Dragonhawk:BAAALgADCgQJBAABLgAECgMJEgAHAAAAAA==.Dragonname:BAAALgAECgEJAQAAAA==.Drakoil:BAABLgAECn87AAMZAAkJwBi7BAAkAgAZAAkJJRi7BAAkAgAFAAcJNxMiNQBdAQAAAA==.Dreademperor:BAACLgAFFH8JAAIDAAQJdBUnGgDGAAADAAQJdBUnGgDGAAAuAAQKfycAAwMACQkhHvAEAPYCAAMACQkhHvAEAPYCABoABAlDDwliAM8AAAEuAAUUBQkMAAsAJR8A.Dreadnature:BAAALgAECgMJAwAAAA==.Dreadnight:BAABLgAFFH8MAAILAAUJJR8NFwAwAQALAAUJJR8NFwAwAQAAAA==.Dreadsteed:BAAALgAECgEJAQABLgAFFAUJDAALACUfAA==.Dreadweaver:BAAALgADCgUJBQABLgAFFAUJDAALACUfAA==.Drenrah:BAABLgAECn8pAAIbAAkJug+lKwC0AQAbAAkJug+lKwC0AQAAAA==.Drgndeeznutz:BAACLgAFFH8QAAIcAAQJYR5PBgAiAQAcAAQJYR5PBgAiAQAuAAQKfygAAhwACQnPHykFANYCABwACQnPHykFANYCAAAA.Drunkenrage:BAACLgAFFH8oAAIdAAkJixtbBABbAgAdAAkJixtbBABbAgAuAAQKfx4AAh0ACQkcIvsBAIIDAB0ACQkcIvsBAIIDAAAA.',
Du='Dumorius:BAAALgAECgYJCAAAAA==.',
['Dé']='Déx:BAAALgAECgYJCwAAAA==.',
Ed='Edreth:BAAALgAECgEJAQAAAA==.',
El='Elbryan:BAABLgAECn8xAAITAAkJhAinMABbAQATAAkJhAinMABbAQAAAA==.Elementdemon:BAAALgAFFAEJAQAAAA==.Ellabelle:BAAALgADCgMJAwAAAA==.',
En='Enthalpy:BAABLgAECn8vAAIeAAkJch6IGwC2AgAeAAkJch6IGwC2AgAAAA==.',
Ep='Epipin:BAAALgAECgUJCAAAAA==.',
Er='Erakazsod:BAAALgAECgEJAQABLgAFFAQJEAAcAGEeAA==.Erazath:BAAALgAECgUJCAABLgAECgkJEAAHAAAAAA==.',
Es='Esperzoa:BAACLgAFFH8GAAILAAMJFRV+EADIAAALAAMJFRV+EADIAAAuAAQKfzIAAgsACQmRG30NADICAAsACQmRG30NADICAAAA.',
Et='Eternaldread:BAAALgADCgUJBQABLgAFFAUJDAALACUfAA==.',
Eu='Eucalicdes:BAABLgAECn9CAAIfAAkJvhfFDQAGAgAfAAkJvhfFDQAGAgAAAA==.',
Ez='Ezal:BAAALgAECgYJCAAAAA==.Ezra:BAAALgAECgQJBAAAAA==.',
Fa='Fallyn:BAAALgAECgEJAQAAAA==.Farshran:BAAALgAECgkJEAAAAA==.Fate:BAAALgAECgQJBQABLgAECgkJJgAPAJQlAA==.Fathermajor:BAAALgAECgQJBAAAAA==.',
Fe='Felicity:BAACLgAFFH8WAAIVAAUJ2h0THAA6AQAVAAUJ2h0THAA6AQAuAAQKfzYAAxUACQmWIpIEAE4DABUACQmWIpIEAE4DACAABQmDDb8VANEAAAAA.Ferendis:BAABLgAECn8nAAIOAAgJPiOiEwCmAgAOAAgJPiOiEwCmAgAAAA==.Fernard:BAAALgADCgYJBgABLgAECgkJEQANACUcAA==.',
Fl='Flokii:BAAALgAECgQJBAAAAA==.Florita:BAAALgAECgYJBwAAAA==.Flydormu:BAAALgAECgYJDAABLgAECgkJLwAeAIYZAA==.',
Fo='Fordinn:BAABLgAECn81AAMaAAkJsBiRGwARAgAaAAkJZRaRGwARAgADAAcJeRUOGwBgAQAAAA==.',
Fr='Fractured:BAAALgADCgEJAQAAAA==.Freelor:BAAALgAECgIJBAAAAA==.Freemi:BAAALgAECgEJAQAAAA==.Frenzy:BAAALgAECgkJAQAAAA==.Frigidgrip:BAAALgAECgMJAwAAAA==.',
Fu='Fuddytwo:BAABLgAECn8wAAIXAAkJKR0ZAgAoAgAXAAkJKR0ZAgAoAgAAAA==.Furrypaw:BAAALgAECgcJBwABLgAFFAMJBAAHAAAAAA==.Furrypunch:BAAALgAFFAMJBAAAAA==.',
Ga='Garzhvog:BAAALgADCgcJCwABLgAFFAIJBAARAFUaAA==.Gasket:BAACLgAFFH8bAAMMAAUJRhpKDgAnAQAhAAUJ/BcQXgA4AQAMAAUJ3hNKDgAnAQAuAAQKfyUAAyEACQlnIsMiALQCACEACQlvIcMiALQCAAwAAwkcIEUZAAoBAAAA.Gauteng:BAAALgAECgIJAgABLgAFFAYJGwAPAHAfAA==.',
Gh='Ghidõráh:BAAALgAECgEJAQAAAA==.Ghorac:BAAALgADCgYJDAAAAA==.Ghoti:BAAALgADCgUJBQAAAA==.Ghoulz:BAAALgADCgcJDAAAAA==.',
Gl='Glazedham:BAAALgADCgMJAwAAAA==.',
Gn='Gnollfang:BAAALgADCgYJBgAAAA==.',
Go='Gorbubbli:BAAALgADCgkJGgAAAA==.',
Gr='Graceful:BAAALgAECgUJBgAAAA==.Griffith:BAAALgAECgEJAQAAAA==.Grit:BAAALgAECgYJDAAAAA==.',
Gu='Guidosarduci:BAAALgADCgEJAQAAAA==.Guilddrama:BAAALgADCgEJAQAAAA==.',
Ha='Haeler:BAAALgAECgIJAwAAAA==.Haelin:BAAALgADCgEJAQAAAA==.Halgoðfulk:BAAALgAECgEJAQAAAA==.Hamwarrior:BAAALgAECgEJAQAAAA==.Handicap:BAAALgAECgcJBwABLgAECgkJHgAPAIUlAA==.Hark:BAACLgAFFH8cAAIGAAYJ5g6oRQAiAQAGAAYJ5g6oRQAiAQAuAAQKfywAAgYACQmOG7RQALABAAYACQmOG7RQALABAAAA.Harpin:BAAALgADCgEJAQAAAA==.Harvin:BAABLgAECn80AAIYAAkJgCL0AQBlAwAYAAkJgCL0AQBlAwAAAA==.',
He='Heisenburgg:BAAALgAECgkJCQAAAA==.Hekus:BAEALgAECgcJEQAAAA==.Helanua:BAABLgAECn8rAAIJAAkJQhEQJwCzAQAJAAkJQhEQJwCzAQAAAA==.Hellsplay:BAAALgADCgIJAgAAAA==.',
Hi='Hibernate:BAAALgADCgEJAQAAAA==.Hippolytus:BAAALgADCgkJCQABLgAECgkJLgAdAPQkAA==.Hippopotamus:BAAALgAECgMJAwAAAA==.Hit:BAAALgAECgYJCwAAAA==.',
Ho='Holytide:BAABLgAECn81AAMJAAkJXA4ZQwAnAQAJAAgJ+QsZQwAnAQAiAAkJsgwUDgAPAQAAAA==.Hope:BAABLgAECn8wAAIXAAgJbww4OQAuAQAXAAgJbww4OQAuAQAAAA==.Horrorfang:BAABLgAECn9OAAIhAAkJUiHxCwANAwAhAAkJUiHxCwANAwAAAA==.',
Hu='Hukjo:BAAALgAECgcJEgABLgAECgkJIwAKACEUAA==.',
Ib='Ibaar:BAACLgAFFH8XAAIFAAYJrCLYHgBpAQAFAAYJrCLYHgBpAQAuAAQKfy4AAwUACQnNI00HAAUDAAUACAlEI00HAAUDABkABgneIAcNAAoCAAAA.',
Ic='Icepickle:BAAALgADCgcJAQAAAA==.Icialiaa:BAAALgAECgYJDAABLgAECgkJIAAVAL8LAA==.',
Ii='Iilnut:BAABLgAECn8gAAMTAAgJnCA/CwDPAgATAAgJnCA/CwDPAgAIAAQJPBW2NwDpAAABLgAFFAQJDAAKALEgAA==.',
Il='Illedren:BAABLgAECn8QAAIOAAgJwwc7kAAAAQAOAAgJwwc7kAAAAQAAAA==.',
In='Innerdemon:BAAALgAECgQJBAAAAA==.Inno:BAABLgAECn8YAAIOAAkJDiTxEwDhAgAOAAkJDiTxEwDhAgAAAA==.',
Ir='Irraedorine:BAABLgAECn8gAAMVAAkJvwv6BQAIAQAVAAkJvwv6BQAIAQAgAAgJCwScEwDuAAAAAA==.',
Is='Isabel:BAAALgAECgcJDQABLgAECgkJFAAGAC4UAA==.',
It='Ithacus:BAABLgAECn8pAAIjAAkJtBGcEQCaAQAjAAkJtBGcEQCaAQAAAA==.',
Ja='Jandaar:BAAALgAECgEJAQAAAA==.Jatt:BAAALgAECgMJCAAAAA==.Jattao:BAAALgADCgEJAQAAAA==.Jattex:BAAALgAECgEJAgAAAA==.Jattix:BAAALgAECgIJBQAAAA==.',
Jd='Jdawgprime:BAAALgADCgcJBwAAAA==.',
Je='Jenjas:BAAALgAECgUJBQAAAA==.',
Ji='Jinnlee:BAAALgAECgYJBwAAAA==.Jinoo:BAABLgAECn9CAAIJAAkJhhswDwB9AgAJAAkJhhswDwB9AgAAAA==.Jinufan:BAAALgAECgUJBwABLgAFFAYJFwAFAKwiAA==.',
Jo='Jodyhusky:BAAALgADCgYJBgAAAA==.Joe:BAAALgAECgcJCgAAAA==.Jorek:BAABLgAECn8WAAIaAAkJ7BT0KAC2AQAaAAkJ7BT0KAC2AQAAAA==.',
Ju='Jugulator:BAAALgADCgcJDQAAAA==.',
Ka='Kaejung:BAAALgAECgUJBgAAAA==.Kainairobi:BAAALgAECgUJCQAAAA==.Kaiva:BAAALgAECgQJBgABLgAECgYJDgAHAAAAAA==.Kallistô:BAAALgADCgYJBgAAAA==.Kamigawa:BAABLgAECn8VAAIaAAgJqwt/PABTAQAaAAgJqwt/PABTAQAAAA==.Kavik:BAABLgAECn8fAAIbAAkJHhlKEQCKAgAbAAkJHhlKEQCKAgAAAA==.Kazbodan:BAAALgADCgkJFQAAAA==.',
Ke='Keemo:BAACLgAFFH8cAAILAAYJjRRTHwDsAAALAAYJjRRTHwDsAAAuAAQKfykAAwsACQnJFachAEUBAAsACQmpFachAEUBACEAAwmYDUX8AIMAAAAA.Keemosaki:BAAALgAFFAEJAgAAAA==.Keemõ:BAABLgAECn8XAAMOAAYJvw1QnwDkAAAOAAYJ0wxQnwDkAAAkAAYJownQIACXAAAAAA==.Keemøsabi:BAAALgAFFAEJAgAAAA==.Keflá:BAAALgAECgYJEgAAAA==.Keineliebe:BAAALgADCgcJBwAAAA==.Keysersöze:BAAALgADCgYJBwAAAA==.',
Kh='Khaas:BAABLgAECn9PAAIhAAkJuQ9CTgDYAQAhAAkJuQ9CTgDYAQAAAA==.Khaleeb:BAAALgAECgEJAwAAAA==.',
Ki='Kierios:BAABLgAECn8oAAMMAAkJiRbCCAD+AQAMAAkJTxPCCAD+AQAhAAgJ3RDmawCOAQAAAA==.Kildurgan:BAAALgAECgQJDQAAAA==.Killawarlock:BAABLgAECn8hAAQRAAgJzCKLPgDiAQARAAcJNSCLPgDiAQASAAQJbCIsFAAuAQAQAAEJ/hAbcAA2AAAAAA==.Kironn:BAAALgADCgYJBgABLgAFFAMJBwACALYHAA==.',
Kk='Kkain:BAAALgAECgIJBwAAAA==.',
Ko='Korihor:BAABLgAECn8pAAIlAAkJ6B1fCQA7AgAlAAkJ6B1fCQA7AgAAAA==.',
Kr='Krestus:BAABLgAECn8RAAMNAAcJJRyxQACzAAAOAAYJrxkZfgAvAQANAAMJKSCxQACzAAAAAA==.Krispy:BAABLgAECn87AAQCAAkJHxbJFAAUAgACAAkJEhbJFAAUAgAdAAcJ2Q4VOAAcAQAKAAUJvgO5TgCZAAAAAA==.Krith:BAAALgADCgYJCQAAAA==.Krix:BAAALgAECgMJBAAAAA==.',
Ky='Kyndil:BAAALgAECgcJEQAAAA==.',
La='Laerin:BAABLgAECn8UAAIbAAkJZBSxLACtAQAbAAkJZBSxLACtAQAAAA==.Laxus:BAAALgAECgMJAwABLgAECgkJHwAYAJMSAA==.Lazarius:BAAALgADCgQJBAAAAA==.',
Le='Leafblade:BAAALgAECgkJCwAAAA==.Levophed:BAABLgAECn8uAAIhAAcJkg+BrAAZAQAhAAcJkg+BrAAZAQAAAA==.Lexor:BAAALgAECgMJAwAAAA==.',
Li='Liangwei:BAAALgAECgMJAwABLgAFFAMJBwAGAPMdAA==.Lightfallen:BAAALgAECgcJEQAAAA==.Lightseeker:BAAALgAECgEJAQABLgAECgkJHwAYAJMSAA==.Liisara:BAABLgAECn8bAAIOAAgJZggzigAMAQAOAAgJZggzigAMAQAAAA==.Lily:BAABLgAECn87AAIfAAkJHRu1DAAWAgAfAAkJHRu1DAAWAgAAAA==.Linadra:BAABLgAECn8uAAIPAAkJgwmikQBPAQAPAAkJgwmikQBPAQAAAA==.Linnt:BAAALgAECgMJAwAAAA==.Linzur:BAAALgAECgEJAQAAAA==.Littleyeti:BAAALgAECgMJAwAAAA==.Liyara:BAACLgAFFH8bAAIPAAYJcB82IACGAQAPAAYJcB82IACGAQAuAAQKfykAAg8ACQm1JUgRAAYDAA8ACQm1JUgRAAYDAAAA.',
Ll='Llorsa:BAABLgAECn9EAAMWAAkJZhfiEQBQAgAWAAkJZhfiEQBQAgATAAUJdA1aUADPAAAAAA==.',
Lo='Lohhan:BAAALgADCgUJCQAAAA==.Lolamontez:BAAALgAECgIJAgAAAA==.Lorachka:BAAALgADCgIJAgAAAA==.Lorthys:BAAALgADCgEJAQAAAA==.',
Lu='Luxian:BAACLgAFFH8JAAIPAAIJxgjhRQB5AAAPAAIJxgjhRQB5AAAuAAQKf1MAAg8ACQkgFU0PADwBAA8ACQkgFU0PADwBAAAA.',
Ly='Lyssirix:BAABLgAECn8YAAIJAAcJZBPHBQBaAQAJAAcJZBPHBQBaAQAAAA==.',
Ma='Macandcheese:BAAALgAECgMJBAAAAA==.Macy:BAABLgAECn8YAAIeAAcJJhMQEwAYAQAeAAcJJhMQEwAYAQAAAA==.Mahiru:BAAALgADCgEJAQAAAA==.Mahralla:BAAALgADCgIJAgAAAA==.Maikagond:BAAALgAECgYJDgABLgAECgkJMwAPAKQLAA==.Makaria:BAAALgAECggJEAAAAA==.Malbisa:BAAALgAECgQJBgAAAA==.Malphoz:BAAALgAECgUJBwAAAA==.Mandragora:BAABLgAECn8bAAIPAAkJXBJgiQBdAQAPAAkJXBJgiQBdAQAAAA==.Maoriofdeath:BAAALgADCgEJAQABLgAECgYJDgAHAAAAAA==.Map:BAAALgAECgIJAwAAAA==.Marli:BAAALgADCgEJAQAAAA==.Mattieatzdot:BAAALgAECgQJBQAAAA==.',
Mc='Mcgrowlin:BAAALgAECgQJCwAAAA==.',
Me='Mekator:BAAALgAECgQJBAAAAA==.Meko:BAAALgAECgUJBwAAAA==.Merrycow:BAAALgAECggJCwAAAA==.Mew:BAAALgAECgIJAwAAAA==.',
Mi='Mickey:BAACLgAFFH8IAAICAAQJJwsEHwDeAAACAAQJJwsEHwDeAAAuAAQKfygAAgIACQkTIlcHANQCAAIACQkTIlcHANQCAAAA.Migraine:BAAALgAECgYJCgAAAA==.Mikiik:BAABLgAECn9FAAIRAAkJzwqaXACIAQARAAkJzwqaXACIAQAAAA==.Mildoo:BAABLgAECn8sAAISAAkJBA/2CwCeAQASAAkJBA/2CwCeAQAAAA==.Milkymoo:BAABLgAECn8iAAIDAAUJfxybHgA/AQADAAUJfxybHgA/AQABLgAFFAkJMwAWAGAWAA==.Millina:BAAALgADCgIJAgABLgAECgkJOgACAGMOAA==.Mimira:BAAALgAECgEJAQAAAA==.Minipal:BAAALgAECgcJEQABLgAECgkJFgABAKcdAA==.Mixednuts:BAACLgAFFH8MAAIKAAQJsSAOIABuAQAKAAQJsSAOIABuAQAuAAQKfycAAwoACQmiIhoEAHIDAAoACQmiIhoEAHIDAAIABgkoIKofANoBAAAA.',
Mo='Mochii:BAAALgADCgYJBgAAAA==.Moneyshock:BAAALgAECgYJBgABLgAFFAQJEAAcAGEeAA==.Monq:BAABLgAECn8YAAMCAAgJBBjAHADIAQACAAgJBBjAHADIAQAdAAEJyAkqjQAqAAAAAA==.Moonamber:BAAALgADCgQJBgAAAA==.Morphinzerr:BAAALgAECgEJAQAAAA==.Moón:BAAALgAECgEJAwAAAA==.',
Mu='Murdrmittens:BAAALgADCgEJAQAAAA==.',
My='Mysterychogs:BAAALgAECgEJAQABLgAECgkJLgATAMYbAA==.Mythion:BAABLgAECn8kAAMUAAgJcRpmJQAiAgAUAAgJcRpmJQAiAgAXAAQJCQWtawBzAAAAAA==.Mythlocked:BAAALgAECgYJBgAAAA==.Mythoridan:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîlk:BAABLgAFFH8HAAINAAUJagspDQC/AAANAAUJagspDQC/AAAAAA==.',
Na='Naeres:BAABLgAECn8fAAIhAAgJkBcvcACEAQAhAAgJkBcvcACEAQAAAA==.Nafari:BAAALgAECggJCAAAAA==.Naofummi:BAAALgAECgcJBwAAAA==.Naomii:BAABLgAECn8rAAMWAAkJxxnUFwAPAgAWAAkJxxnUFwAPAgATAAUJZQiXWQCvAAAAAA==.Narus:BAAALgAECgcJCgABLgAECgkJNQAaALAYAA==.Naturefury:BAAALgADCgEJAQAAAA==.',
Ne='Neeston:BAACLgAFFH8HAAIUAAMJzBI9PAC+AAAUAAMJzBI9PAC+AAAuAAQKfyIAAxQACAkJI5oPANcCABQACAkJI5oPANcCABcAAQllEtyAADAAAAEuAAUUBAkQABwAYR4A.Neodin:BAABLgAECn8jAAIaAAkJlQ+0JgDEAQAaAAkJlQ+0JgDEAQAAAA==.Neoresto:BAAALgADCgcJBQAAAA==.Nephadin:BAAALgADCgUJAwABLgAECgkJKQAlABQiAA==.Nerfed:BAAALgAECgUJCAAAAA==.Neviaa:BAABLgAECn8uAAIhAAkJXRSyQAABAgAhAAkJXRSyQAABAgAAAA==.',
Ni='Nickypoo:BAAALgAECgMJBgAAAA==.Nightmenace:BAAALgAECgcJCwAAAA==.Ninari:BAAALgADCgUJBQAAAA==.Niq:BAAALgAECgQJBAAAAA==.',
No='Nocshadue:BAAALgADCgYJCwAAAA==.Nordga:BAAALgADCgcJBwAAAA==.Norii:BAAALgADCgIJAgABLgAECgkJDgAHAAAAAA==.Nothealster:BAAALgAECgcJEwAAAA==.Nothros:BAAALgADCgQJBAAAAA==.',
Ob='Obitrice:BAAALgAECggJCgAAAA==.Obsidiian:BAABLgAECn8VAAImAAgJlREnCgCBAQAmAAgJlREnCgCBAQAAAA==.Obsidion:BAABLgAECn8YAAMTAAYJrwzAWwCnAAATAAUJ5gnAWwCnAAAWAAQJDggFVgCEAAABLgAECgkJNQAaALAYAA==.',
Od='Odie:BAAALgAECgYJDwAAAA==.',
On='Onemorehit:BAAALgAECgEJAwAAAA==.Onlyfangs:BAABLgAECn9KAAMYAAkJUxIjDQAAAgAYAAkJUxIjDQAAAgAFAAYJtwX9awCXAAAAAA==.',
Os='Oscrapermort:BAAALgADCgMJAwAAAA==.Ossin:BAAALgAFFAIJBAAAAA==.',
Pa='Padivyn:BAABLgAECn8ZAAIJAAgJzxiQIwDKAQAJAAgJzxiQIwDKAQAAAA==.Padnamprik:BAAALgAECgQJBAAAAA==.Palidenman:BAAALgAECgQJAwAAAA==.Pantherlilly:BAAALgAECgUJBQAAAA==.',
Pe='Peanads:BAAALgADCgcJEAAAAA==.Pebblez:BAAALgADCgcJDgAAAA==.Perry:BAACLgAFFH8GAAIUAAMJcB5zKwAJAQAUAAMJcB5zKwAJAQAuAAQKfyoAAxQACQm6Ie8EAGwDABQACQm6Ie8EAGwDABcAAgkBBTuCAEQAAAAA.',
Ph='Phlampped:BAAALgADCgUJBQABLgAFFAgJIAAPAJsYAA==.',
Pi='Pinotage:BAAALgAECggJDgABLgAECgkJOwAhAFgdAA==.',
Po='Po:BAAALgAECgkJCAAAAA==.Pozufuma:BAABLgAECn9GAAIaAAkJHB2ZDAChAgAaAAkJHB2ZDAChAgAAAA==.',
Pr='Priestcraft:BAAALgADCgIJAgABLgAECggJCwAHAAAAAA==.',
Ps='Psychomantis:BAABLgAECn8qAAMTAAkJeRQGHwDNAQATAAkJeRQGHwDNAQAWAAEJwRECGAAvAAAAAA==.',
Pu='Punchypunch:BAAALgADCgkJFAAAAA==.',
Ra='Raek:BAAALgAECgQJBQABLgAECgcJGQASAPEbAA==.Raith:BAAALgAECgYJCwAAAA==.Ravenbear:BAAALgAECgQJBgABLgAECgkJSgAYAFMSAA==.Ravenbyrd:BAAALgADCgMJAwAAAA==.Rawberriez:BAAALgAECgQJBgAAAA==.',
Re='Reani:BAAALgADCgQJBAAAAA==.Reapin:BAAALgADCgUJBQAAAA==.Redpool:BAABLgAECn8fAAIGAAcJJBGNQACtAQAGAAcJJBGNQACtAQAAAA==.Remithedrood:BAAALgADCgIJAgAAAA==.Reqium:BAAALgADCgYJCAAAAA==.Resto:BAAALgAECgQJBgAAAA==.Rethandra:BAABLgAECn8YAAQGAAgJ9hP9XgCKAQAGAAcJSRX9XgCKAQAnAAMJLxRhHwC0AAAcAAIJ3gdXDwA9AAAAAA==.Retrix:BAAALgAECgIJAwAAAA==.Revorra:BAAALgAECgEJAQABLgAECgkJNQAaALAYAA==.',
Ri='Rion:BAABLgAECn8XAAIeAAkJcxHRYgC5AQAeAAkJcxHRYgC5AQAAAA==.Ristvakbaen:BAACLgAFFH8EAAIRAAIJVRqZkwCbAAARAAIJVRqZkwCbAAAuAAQKfzoABBIACQnmJEEDAIYCABIACAlGJUEDAIYCABEACQm8HbofAGYCABAABgk9JRYGAAQCAAAA.',
Ro='Robynlee:BAABLgAECn9SAAIWAAgJpRrFAQBcAgAWAAgJpRrFAQBcAgAAAA==.Roccobb:BAAALgADCgYJBgAAAA==.Rogùe:BAAALgAFFAIJAgAAAA==.Rosebelle:BAAALgADCggJHQAAAA==.',
Ru='Rugratt:BAAALgADCgQJBAABLgADCgcJDgAHAAAAAA==.',
Sa='Saeler:BAAALgAECgMJAwAAAA==.Sailrmoonkin:BAAALgAECgQJBQABLgAFFAMJBgALABUVAA==.Samoth:BAAALgADCgEJAQAAAA==.Sanathein:BAAALgADCgcJBwAAAA==.Sanctuary:BAAALgAECgQJBAAAAA==.Santeclair:BAAALgAECgEJAQAAAA==.Satin:BAAALgAECggJDQAAAA==.',
Sc='Sceryna:BAABLgAECn8oAAIPAAkJzBdBSQDqAQAPAAkJzBdBSQDqAQAAAA==.Schiftly:BAAALgAFFAIJAgAAAA==.Schwiggity:BAAALgAECgQJCQABLgAECgkJGwAPAFwSAA==.Scottlock:BAABLgAECn8WAAIQAAcJqh6QBQAVAgAQAAcJqh6QBQAVAgABLgAECgkJLgAjAAIjAA==.Screwbrew:BAAALgAECgIJAgAAAA==.Screwid:BAAALgAECgQJBAAAAA==.Screwtotems:BAAALgAECgEJAQAAAA==.Scrmndemn:BAABLgAECn80AAIPAAkJdAidpAAwAQAPAAkJdAidpAAwAQAAAA==.',
Se='Sepviva:BAABLgAECn8VAAIhAAcJNhZmcACoAQAhAAcJNhZmcACoAQAAAA==.Serea:BAAALgAECgEJAQABLgAECgkJUgAWAKUaAA==.Serpent:BAACLgAFFH8OAAIDAAYJ5BS9CgCDAQADAAYJ5BS9CgCDAQAuAAQKfyMAAgMACQlnHxkIAHoCAAMACQlnHxkIAHoCAAEuAAUUBwkkAAsAXxYA.',
Sh='Shadowheal:BAAALgADCgUJBgAAAA==.Shamadeus:BAAALgADCgUJBQABLgAFFAIJBAARAFUaAA==.Shamtastical:BAAALgAECgYJBgABLgAECgkJUgAWAKUaAA==.Sharaseth:BAAALgAECggJEQAAAA==.Shikita:BAABLgAECn9MAAMUAAkJnB51DQDvAgAUAAkJnB51DQDvAgAXAAEJHAZfigAlAAAAAA==.Shimadin:BAACLgAFFH8gAAIPAAYJphdmOAA8AQAPAAYJphdmOAA8AQAuAAQKfykAAg8ACQkfHvszADACAA8ACQkfHvszADACAAAA.Shimbuktu:BAAALgAECgEJAwABLgAFFAYJIAAPAKYXAA==.Shimfu:BAAALgAECgEJAgABLgAFFAYJIAAPAKYXAA==.Shimjun:BAAALgAECgUJCwABLgAFFAYJIAAPAKYXAA==.Shimpbizkit:BAABLgAECn8ZAAIeAAcJAg0VnwA8AQAeAAcJAg0VnwA8AQABLgAFFAYJIAAPAKYXAA==.Shimsong:BAAALgAECgYJEwABLgAFFAYJIAAPAKYXAA==.Shmerek:BAABLgAECn8XAAIDAAkJRSBCCAB3AgADAAkJRSBCCAB3AgAAAA==.',
Si='Sidarien:BAAALgADCgQJBAAAAA==.Silenttits:BAAALgAECgEJAgAAAA==.Silveralae:BAAALgAECgEJAQAAAA==.Silveraven:BAAALgADCgIJAgAAAA==.Silverlumen:BAAALgAFFAEJAgAAAA==.Silversaevus:BAAALgAFFAEJAQAAAA==.Silverstream:BAACLgAFFH8IAAIUAAMJGgqLSQCUAAAUAAMJGgqLSQCUAAAuAAQKfyoAAhQACQnoER1CAJkBABQACQnoER1CAJkBAAAA.',
Sk='Skyblue:BAAALgADCgEJAQAAAA==.',
Sl='Slea:BAABLgAECn8VAAIcAAkJQxApFAAEAgAcAAkJQxApFAAEAgAAAA==.Slease:BAAALgAECgYJBgAAAA==.',
Sm='Smallrichard:BAAALgAECgEJAQAAAA==.Smootish:BAAALgADCgUJBQAAAA==.',
So='Solbin:BAAALgAECgUJDAABLgAECgkJLwAeAIYZAA==.Solitudé:BAABLgAECn8fAAMRAAgJBiSWHwBnAgARAAcJPiGWHwBnAgASAAUJoSW1FAAoAQABLgAFFAUJFAAMAP4fAA==.Soteirian:BAABLgAECn8zAAMPAAkJpAuIcgCJAQAPAAkJpAuIcgCJAQAlAAEJjwJKXwASAAAAAA==.',
Sp='Spam:BAAALgAECgIJAgAAAA==.Spekey:BAAALgAECgEJAQAAAA==.Spider:BAABLgAECn87AAIhAAkJWB3wAwBGAgAhAAkJWB3wAwBGAgAAAA==.Spineymagus:BAAALgADCgIJAgAAAA==.',
Sq='Squall:BAABLgAECn8rAAMiAAgJMhCNRwCQAQAiAAgJMhCNRwCQAQAJAAYJ0ROVRQAdAQAAAA==.',
St='Stalariais:BAAALgAECgQJBAABLgAECgkJGQAbAHoIAA==.Stardrand:BAAALgADCgUJBgAAAA==.Steeg:BAAALgAECgYJDAAAAA==.Steelreserve:BAAALgAECgYJDQAAAA==.Straw:BAAALgAECgYJCwABLgAECgkJQwAPAGgkAA==.',
Su='Sugarkitty:BAAALgADCgYJCgAAAA==.Supereclipse:BAABLgAECn9HAAIGAAkJ/hZDKQA5AgAGAAkJ/hZDKQA5AgAAAA==.',
Sw='Swolareclips:BAAALgADCgYJBgAAAA==.',
Sy='Sydvicious:BAABLgAECn8iAAINAAkJPCVYBAAEAwANAAkJPCVYBAAEAwAAAA==.Syriene:BAABLgAECn8uAAIBAAkJPBByEQCjAQABAAkJPBByEQCjAQABLgAECgkJIAAVAL8LAA==.',
Ta='Taladiir:BAAALgAECgEJAQAAAA==.Talana:BAAALgAECgEJAQAAAA==.Tankhealz:BAAALgAECgMJBQAAAA==.Tanthe:BAAALgAECgMJAwAAAA==.Tayger:BAAALgAFFAEJAQAAAA==.',
Tb='Tbsp:BAAALgAECgEJAQABLgAFFAUJFgAKAEocAA==.',
Te='Tecks:BAABLgAECn8XAAIWAAkJwgWfPAABAQAWAAkJwgWfPAABAQAAAA==.Teddy:BAAALgAECgUJCQAAAA==.Teslá:BAAALgAECgYJCgAAAA==.',
Th='Theatrix:BAAALgAECgQJBwABLgAECgcJFAAFAP4VAA==.Thecuckler:BAAALgAECgQJCAAAAA==.Thefreeman:BAAALgAECgEJAQAAAA==.Themajor:BAABLgAECn8uAAMEAAkJFhfmDAAYAgAEAAkJFhfmDAAYAgAaAAcJ/AhwTAB0AQAAAA==.Then:BAAALgADCgEJAQAAAA==.Thiarad:BAAALgADCgEJAQAAAA==.Thiaraxo:BAACLgAFFH8JAAMKAAMJHyHuGgDRAAAKAAMJHyHuGgDRAAACAAEJjhajGABLAAAuAAQKfxUAAgoACQmbBcp5ALAAAAoACQmbBcp5ALAAAAAA.Thrain:BAAALgADCgcJDAAAAA==.Threat:BAABLgAECn8mAAIPAAkJlCWXBQBHAwAPAAkJlCWXBQBHAwAAAA==.Thronkall:BAAALgAECgkJAgAAAA==.Thsarus:BAABLgAECn8vAAMOAAgJ6yDlHABnAgAOAAgJ6yDlHABnAgAkAAQJHBHQGwCxAAAAAA==.',
Ti='Tiamaat:BAABLgAECn8XAAIUAAkJmgQKegDJAAAUAAkJmgQKegDJAAAAAA==.Tireyne:BAAALgADCgEJAgAAAA==.Titus:BAAALgAECgEJBgAAAA==.',
Tk='Tkt:BAAALgAECgIJBAABLgAFFAIJAgAHAAAAAA==.',
To='Toatani:BAAALgAECgYJDgAAAA==.Tokkaebi:BAAALgAECgkJDAAAAA==.',
Tr='Treadlightly:BAAALgADCgUJBwAAAA==.Treefróg:BAAALgAECgUJBQAAAA==.Trentus:BAAALgADCgIJAgAAAA==.Trev:BAAALgAECgUJBgABLgAFFAUJBQARAIUWAA==.Trotem:BAAALgAECgUJBQAAAA==.',
Ts='Tsp:BAACLgAFFH8WAAIKAAUJShwOHACSAQAKAAUJShwOHACSAQAuAAQKfywAAwoACQn/Gd8cADECAAoACQn/Gd8cADECAB0ABAnxA0psAJEAAAAA.',
Ty='Tyletos:BAABLgAECn8vAAIeAAkJhhmNCgCGAQAeAAkJhhmNCgCGAQAAAA==.',
Ug='Ugolok:BAABLgAECn8pAAMMAAcJ7gfrIQC/AAAMAAYJzQjrIQC/AAAhAAcJKQWvKABuAAAAAA==.',
Ur='Uriél:BAABLgAECn8yAAIOAAkJNSWeAgBeAwAOAAkJNSWeAgBeAwABLgAFFAUJFAAMAP4fAA==.',
Va='Valeene:BAABLgAECn8uAAIXAAkJLiJSBAAcAwAXAAkJLiJSBAAcAwAAAA==.Valkion:BAAALgAECgEJAQAAAA==.Varek:BAABLgAECn8XAAIVAAkJ5yEyAwAbAwAVAAkJ5yEyAwAbAwAAAA==.Varlann:BAAALgADCgkJCQAAAA==.',
Ve='Veiler:BAABLgAECn9GAAMGAAkJEROKNgADAgAGAAkJEROKNgADAgAnAAEJ3wH2lgAhAAAAAA==.Velca:BAAALgAECgIJAgAAAA==.Veruca:BAAALgAECgMJAwAAAA==.Veviseron:BAABLgAECn8qAAIeAAkJNwSvpgAwAQAeAAkJNwSvpgAwAQAAAA==.',
Vh='Vhye:BAABLgAFFH8IAAIiAAMJtgZnZAB+AAAiAAMJtgZnZAB+AAAAAA==.',
Vi='Vidnoi:BAAALgAECgEJBAAAAA==.Vincentfreak:BAAALgADCgYJBgAAAA==.Vinstalation:BAABLgAECn81AAIMAAkJcRwxBgBHAgAMAAkJcRwxBgBHAgAAAA==.Vissa:BAAALgADCgYJBgAAAA==.',
Vo='Vonbismarck:BAABLgAECn8lAAMGAAkJ8hOSTQC5AQAGAAkJ8hOSTQC5AQAnAAEJFw/KCgAuAAAAAA==.',
Vr='Vritraz:BAACLgAFFH8UAAMMAAUJ/h9wCABnAQAMAAQJ/h9wCABnAQAhAAEJAACtLQEAAAAuAAQKfxUAAwwACQmLIqEGADkCAAwABwk+I6EGADkCACEAAgl0IAP3ALcAAAAA.Vrock:BAAALgAECgEJAQABLgAECgkJLwAeAHIeAA==.',
Wa='Warnam:BAAALgADCgcJBwAAAA==.Warsonge:BAAALgADCgMJAwAAAA==.',
We='Wendypini:BAACLgAFFH8VAAIGAAUJKAeKUwACAQAGAAUJKAeKUwACAQAuAAQKfyIAAgYACQkAEF5FAJsBAAYACQkAEF5FAJsBAAAA.Wetnwild:BAAALgADCgQJBAAAAA==.',
Wh='Whitehand:BAAALgAECgIJAgAAAA==.Whitlock:BAAALgAECgcJCgAAAA==.',
Wo='Wooshwoosh:BAAALgAECgQJDgAAAA==.',
Wu='Wudeeps:BAAALgAECgcJEgAAAA==.Wuhanwarrior:BAAALgAECgYJEQAAAA==.',
Xe='Xendria:BAAALgAECgEJBAAAAA==.',
Ya='Yako:BAAALgAECgEJAQAAAA==.',
Ye='Yennefer:BAAALgAECgMJAwAAAA==.',
Yo='Yongary:BAAALgAECgkJCQAAAA==.',
Za='Zangolf:BAAALgADCgUJBAAAAA==.Zargoan:BAAALgAECgMJBAAAAA==.Zaye:BAAALgAECggJDAAAAA==.',
Ze='Zearas:BAABLgAECn8UAAIhAAgJJxE+kwBZAQAhAAgJJxE+kwBZAQAAAA==.Zendonn:BAABLgAECn8bAAICAAcJxwUiUgDAAAACAAcJxwUiUgDAAAAAAA==.Zerk:BAAALgAECgEJAQAAAA==.',
Zi='Zicatriz:BAAALgADCgcJDgAAAA==.',
Zo='Zodiaac:BAABLgAECn8XAAILAAkJdxm1FQC+AQALAAkJdxm1FQC+AQAAAA==.',
Zu='Zuggy:BAAALgAFFAEJAQABLgAFFAQJEAAcAGEeAA==.',
Zy='Zy:BAAALgADCgUJBQAAAA==.',
['Zà']='Zàknafein:BAABLgAECn8WAAMSAAYJWBV2AgBTAQASAAYJWBV2AgBTAQARAAMJ3wUpKQBCAAAAAA==.',
['Ëc']='Ëchõ:BAABLgAECn8gAAMUAAkJ+RXSNwDIAQAUAAkJ+RXSNwDIAQAXAAIJvwRldwBHAAAAAA==.',
['Ðï']='Ðï:BAAALgADCgQJBAABLgAECgkJLAATAAcdAA==.',
['ßo']='ßoomer:BAAALgADCgIJAgABLgAFFAMJBwACALYHAA==.',
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
