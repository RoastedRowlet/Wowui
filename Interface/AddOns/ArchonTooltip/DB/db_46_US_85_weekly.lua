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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Evoker-Augmentation','Hunter-BeastMastery','Unknown-Unknown','Priest-Discipline','Shaman-Elemental','Monk-Mistweaver','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Druid-Restoration','Priest-Holy','Rogue-Subtlety','Druid-Balance','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Paladin-Holy','Hunter-Survival','Monk-Brewmaster','Mage-Frost','Druid-Guardian','Rogue-Assassination','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Protection','Rogue-Outlaw','Hunter-Marksmanship',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=46,date='2026-07-28',data={Ab='Abominable:BAAALgADCgEJAQAAAA==.',
Ad='Addo:BAAALgAECgMJAwABLgAECgkJOwABAFgdAA==.',
Ae='Aelaster:BAAALgADCgYJBgAAAA==.',
Ag='Agden:BAAALgADCgEJAQAAAA==.',
Al='Alaìrn:BAAALgAECgUJCwABLgAECgkJFgACAKcdAA==.Aldrich:BAAALgAECgYJBwAAAA==.Alenciann:BAAALgAECgMJBwAAAA==.Allayna:BAAALgAECgEJAQAAAA==.Alstre:BAAALgAECgEJAQAAAA==.Alys:BAABLgAECn86AAIDAAkJYw4IIgCfAQADAAkJYw4IIgCfAQAAAA==.',
Am='Amaniatres:BAABLgAECn8pAAMEAAgJqhNoAwB8AQAEAAgJGhNoAwB8AQAFAAQJEw8XSwChAAABLgAECgkJHgAGANsYAA==.Ammartin:BAABLgAECn8YAAIHAAkJyQo1bQBnAQAHAAkJyQo1bQBnAQAAAA==.Amoonranara:BAAALgADCgEJAQAAAA==.',
An='Anaan:BAAALgAECgUJBgAAAA==.Anahera:BAAALgAECgEJAQABLgAECgYJDgAIAAAAAA==.Anfna:BAAALgAECgEJAgAAAA==.Angrylizard:BAAALgAECgEJAgAAAA==.Anklebiterr:BAAALgAECgUJBwAAAA==.',
Ap='Apothecary:BAAALgADCgcJBwAAAA==.',
Ar='Arabella:BAAALgAECggJEQAAAA==.Arandomidiot:BAAALgADCgYJBgAAAA==.Arathan:BAAALgADCgkJHAAAAA==.Arihana:BAAALgAECgUJBQAAAA==.Ariiana:BAABLgAECn8XAAIJAAkJIx7rBgAOAwAJAAkJIx7rBgAOAwAAAA==.Arngal:BAAALgAECgEJAQAAAA==.',
As='Asapshocky:BAACLgAFFH8WAAIKAAgJ+RhcCADDAQAKAAgJ+RhcCADDAQAuAAQKfy4AAgoACQnTIxIFAA0DAAoACQnTIxIFAA0DAAAA.Asclepios:BAAALgAECgMJBAAAAA==.Asmoday:BAAALgAECgYJBgAAAA==.Astraroth:BAAALgADCgcJCgAAAA==.',
Av='Avella:BAAALgADCgUJBwAAAA==.',
Ba='Balaris:BAAALgADCgcJBwABLgAECgkJIwALACEUAA==.Balum:BAAALgAECgEJAQAAAA==.Bamwham:BAAALgADCgcJBwAAAA==.Barrii:BAAALgAECgMJBQAAAA==.',
Be='Bearblaster:BAAALgADCgQJBAABLgAECgQJBgAIAAAAAA==.Bearlytanks:BAAALgADCgIJAgAAAA==.Beastwallker:BAAALgADCgUJBgAAAA==.Bellabelle:BAAALgAECgYJEwAAAA==.Bellgerra:BAAALgAECgEJAQAAAA==.Ben:BAAALgAECgcJEwAAAA==.Betamaxx:BAACLgAFFH8HAAMMAAMJuBH5LwCDAAAMAAIJThb5LwCDAAANAAIJAwitEwB3AAAuAAQKfxUAAgwABwmCHYgSAOYBAAwABwmCHYgSAOYBAAAA.Betterx:BAAALgAECgQJBQAAAA==.Bevian:BAAALgAECgEJAQABLgAECgkJDgAIAAAAAA==.',
Bi='Biggiepants:BAABLgAECn8iAAMOAAkJ0h9oBwC7AgAOAAkJ0h9oBwC7AgAPAAgJ9w6fYABoAQAAAA==.Bighead:BAAALgAECgYJCAABLgAFFAMJBwADALYHAA==.Bigwarlocks:BAAALgAECgMJBwABLgAFFAMJBwADALYHAA==.Bintje:BAAALgADCgcJEgAAAA==.Biollante:BAAALgAECgcJCwAAAA==.',
Bl='Blindedlïght:BAAALgAECgUJBgAAAA==.',
Bo='Bolsan:BAAALgAECgMJBQAAAA==.Bonq:BAAALgAECgIJAgABLgAECgkJEQAOACUcAA==.Bourg:BAAALgAECgYJCAAAAA==.Bowhemian:BAAALgAECgMJBgAAAA==.',
Bu='Buckis:BAABLgAECn8dAAIQAAgJnxjDBgABAgAQAAgJnxjDBgABAgAAAA==.Bufú:BAAALgADCgIJAgAAAA==.',
['Bö']='Böurbon:BAAALgADCgkJCgAAAA==.',
Ca='Cahk:BAAALgAECgMJAwAAAA==.Cajia:BAABLgAECn8uAAMRAAkJ4wo8HQC+AAASAAkJgwndfgA7AQARAAYJBgs8HQC+AAAAAA==.Canon:BAAALgAECgkJAwAAAA==.',
Ce='Celds:BAAALgADCgQJBAABLgAECgcJGQATAPEbAA==.Celiae:BAAALgAECgYJEAAAAA==.Cendanel:BAAALgAECgIJAgAAAA==.',
Ch='Childress:BAAALgAECgMJAwAAAA==.Chiwhiz:BAAALgAECgEJAQABLgAECgQJCwAIAAAAAA==.Choggy:BAABLgAECn8uAAIUAAkJxhvnDgBqAgAUAAkJxhvnDgBqAgAAAA==.Chogs:BAAALgAECgMJBAABLgAECgkJLgAUAMYbAA==.',
Ci='Cimbline:BAAALgADCgIJAgAAAA==.',
Cl='Clairerick:BAAALgAECgYJEAAAAA==.Clenise:BAAALgAECgEJAQAAAA==.',
Co='Cokebear:BAAALgAECgMJAwABLgAECggJJAAVAHEaAA==.Composer:BAABLgAECn8eAAIGAAkJ2xh+AQBCAgAGAAkJ2xh+AQBCAgAAAA==.Conception:BAAALgAECgEJAQABLgAECgkJUgAWAKUaAA==.Confessionn:BAAALgADCggJDAAAAA==.Cough:BAAALgAECgUJCwABLgAFFAMJBwADALYHAA==.',
Cr='Crinklecut:BAABLgAECn8ZAAIXAAgJQQwKJQBtAQAXAAgJQQwKJQBtAQAAAA==.Critos:BAAALgADCgcJBwAAAA==.Crotchout:BAAALgADCgMJAwAAAA==.Crybaby:BAAALgADCgEJAQAAAA==.Crystilpixy:BAAALgADCgMJBAAAAA==.',
['Cé']='Céline:BAAALgAECgEJAQAAAA==.',
Da='Dalal:BAAALgAECgUJCAABLgAECgkJUgAWAKUaAA==.Danielallen:BAAALgAFFAMJAwAAAA==.Danilov:BAAALgADCgYJBgAAAA==.',
De='Deadlyshift:BAABLgAECn8XAAMVAAkJsCKWBQBeAwAVAAkJsCKWBQBeAwAYAAUJMho8NgBjAQAAAA==.Deadmenace:BAAALgAECgEJAQAAAA==.Deadybear:BAAALgADCgkJEAABLgAECgkJSgAZAFMSAA==.Deathkyter:BAAALgAECgEJAQAAAA==.Delrok:BAAALgAECgEJAgAAAA==.Dephias:BAAALgADCgMJAwAAAA==.',
Di='Diagnosis:BAABLgAECn8eAAIQAAkJhSVqCwAKAwAQAAkJhSVqCwAKAwAAAA==.',
Do='Donnabb:BAABLgAECn8YAAIQAAgJCQW5MAB2AAAQAAgJCQW5MAB2AAAAAA==.Donteatbees:BAABLgAECn8UAAINAAkJZgquGAAPAQANAAkJZgquGAAPAQAAAA==.Dop:BAAALgAECgEJAwAAAA==.Doran:BAABLgAECn8eAAIOAAgJaRcHFwDNAQAOAAgJaRcHFwDNAQAAAA==.Doriathrin:BAAALgADCgcJCwAAAA==.Doujinshi:BAABLgAECn8OAAIPAAcJIBziUwCoAQAPAAcJIBziUwCoAQAAAA==.',
Dr='Dragonbladez:BAAALgADCgUJBQAAAA==.Dragoneye:BAAALgAECgMJBgAAAA==.Dragonhawk:BAAALgADCgQJBAABLgAECgMJEgAIAAAAAA==.Dragonname:BAAALgAECgEJAQAAAA==.Drakoil:BAABLgAECn87AAMaAAkJwBi7BAAkAgAaAAkJJRi7BAAkAgAGAAcJNxMiNQBdAQAAAA==.Dreademperor:BAACLgAFFH8JAAIEAAQJdBUnGgDGAAAEAAQJdBUnGgDGAAAuAAQKfycAAwQACQkhHvAEAPYCAAQACQkhHvAEAPYCABsABAlDDwliAM8AAAEuAAUUBQkMAAwAJR8A.Dreadnature:BAAALgAECgMJAwAAAA==.Dreadnight:BAABLgAFFH8MAAIMAAUJJR8NFwAwAQAMAAUJJR8NFwAwAQAAAA==.Dreadsteed:BAAALgAECgEJAQABLgAFFAUJDAAMACUfAA==.Dreadweaver:BAAALgADCgUJBQABLgAFFAUJDAAMACUfAA==.Drenrah:BAABLgAECn8pAAIcAAkJug+lKwC0AQAcAAkJug+lKwC0AQAAAA==.Drgndeeznutz:BAACLgAFFH8QAAIdAAQJYR4eBwAeAQAdAAQJYR4eBwAeAQAuAAQKfygAAh0ACQnPHykFANYCAB0ACQnPHykFANYCAAAA.Drunkenrage:BAACLgAFFH8pAAIeAAkJhhxbBABbAgAeAAkJhhxbBABbAgAuAAQKfx4AAh4ACQkcIvsBAIIDAB4ACQkcIvsBAIIDAAAA.',
Du='Dumorius:BAAALgAECgYJCAAAAA==.',
['Dé']='Déx:BAAALgAECgYJCwAAAA==.',
Ed='Edreth:BAAALgAECgEJAQAAAA==.',
El='Elbryan:BAABLgAECn8xAAIUAAkJhAinMABbAQAUAAkJhAinMABbAQAAAA==.Elementdemon:BAAALgAFFAEJAQAAAA==.Ellabelle:BAAALgADCgMJAwAAAA==.',
En='Enthalpy:BAABLgAECn8vAAIfAAkJch6IGwC2AgAfAAkJch6IGwC2AgAAAA==.',
Ep='Epipin:BAAALgAECgUJCAAAAA==.',
Er='Erakazsod:BAAALgAECgEJAQABLgAFFAQJEAAdAGEeAA==.Erazath:BAAALgAECgUJCAABLgAECgkJEAAIAAAAAA==.',
Es='Esperzoa:BAACLgAFFH8GAAIMAAMJFRVqEgDBAAAMAAMJFRVqEgDBAAAuAAQKfzIAAgwACQmRG30NADICAAwACQmRG30NADICAAAA.',
Et='Eternaldread:BAAALgADCgUJBQABLgAFFAUJDAAMACUfAA==.',
Eu='Eucalicdes:BAABLgAECn9CAAIgAAkJvhfFDQAGAgAgAAkJvhfFDQAGAgAAAA==.',
Ez='Ezal:BAAALgAECgYJCAAAAA==.Ezra:BAAALgAECgQJBAAAAA==.',
Fa='Fallyn:BAAALgAECgEJAQAAAA==.Farshran:BAAALgAECgkJEAAAAA==.Fate:BAAALgAECgQJBQABLgAECgkJJgAQAJQlAA==.Fathermajor:BAAALgAECgQJBAAAAA==.',
Fe='Felicity:BAACLgAFFH8WAAIXAAUJ2h0THAA6AQAXAAUJ2h0THAA6AQAuAAQKfzYAAxcACQmWIpIEAE4DABcACQmWIpIEAE4DACEABQmDDb8VANEAAAAA.Ferendis:BAABLgAECn8nAAIPAAgJPiOiEwCmAgAPAAgJPiOiEwCmAgAAAA==.Fernard:BAAALgADCgYJBgABLgAECgkJEQAOACUcAA==.',
Fl='Flokii:BAAALgAECgQJBAAAAA==.Florita:BAAALgAECgYJBwAAAA==.Flydormu:BAAALgAECgYJDAABLgAECgkJLwAfAIYZAA==.',
Fo='Fordinn:BAABLgAECn81AAMbAAkJsBiRGwARAgAbAAkJZRaRGwARAgAEAAcJeRUOGwBgAQAAAA==.',
Fr='Fractured:BAAALgADCgEJAQAAAA==.Freelor:BAAALgAECgIJBAAAAA==.Freemi:BAAALgAECgEJAQAAAA==.Frenzy:BAAALgAECgkJAQAAAA==.Frigidgrip:BAAALgAECgMJAwAAAA==.',
Fu='Fuddytwo:BAABLgAECn8wAAIYAAkJKR2IAgAhAgAYAAkJKR2IAgAhAgAAAA==.Furrypaw:BAAALgAECgcJBwABLgAFFAMJBgALAJcSAA==.Furrypunch:BAABLgAFFH8GAAMLAAMJlxK/IgCmAAALAAMJlxK/IgCmAAADAAIJPg3+EwB9AAAAAA==.',
Ga='Garzhvog:BAAALgADCgcJCwABLgAFFAIJBAASAFUaAA==.Gasket:BAACLgAFFH8bAAMNAAUJRhpKDgAnAQABAAUJ/BcQXgA4AQANAAUJ3hNKDgAnAQAuAAQKfyUAAwEACQlnIsMiALQCAAEACQlvIcMiALQCAA0AAwkcIEUZAAoBAAAA.Gauteng:BAAALgAECgIJAgABLgAFFAYJGwAQAHAfAA==.',
Gh='Ghidõráh:BAAALgAECgEJAQAAAA==.Ghorac:BAAALgADCgYJDAAAAA==.Ghoti:BAAALgADCgUJBQAAAA==.Ghoulz:BAAALgADCgcJDAAAAA==.',
Gl='Glazedham:BAAALgADCgMJAwAAAA==.',
Gn='Gnollfang:BAAALgADCgYJBgAAAA==.',
Go='Gorbubbli:BAAALgADCgkJGgAAAA==.',
Gr='Graceful:BAAALgAECgUJBgAAAA==.Griffith:BAAALgAECgEJAQAAAA==.Grit:BAAALgAECgYJDAAAAA==.',
Gu='Guidosarduci:BAAALgADCgEJAQAAAA==.Guilddrama:BAAALgADCgEJAQAAAA==.',
Ha='Haeler:BAAALgAECgIJAwAAAA==.Haelin:BAAALgADCgEJAQAAAA==.Halgoðfulk:BAAALgAECgEJAQAAAA==.Hamwarrior:BAAALgAECgEJAQAAAA==.Handicap:BAAALgAECgcJBwABLgAECgkJHgAQAIUlAA==.Hark:BAACLgAFFH8cAAIHAAYJ5g6oRQAiAQAHAAYJ5g6oRQAiAQAuAAQKfywAAgcACQmOG7RQALABAAcACQmOG7RQALABAAAA.Harpin:BAAALgAECgEJAQAAAA==.Harvin:BAABLgAECn80AAIZAAkJgCL0AQBlAwAZAAkJgCL0AQBlAwAAAA==.',
He='Heisenburgg:BAAALgAECgkJCQAAAA==.Hekus:BAEALgAECgcJEQAAAA==.Helanua:BAABLgAECn8rAAIKAAkJQhEQJwCzAQAKAAkJQhEQJwCzAQAAAA==.Hellsplay:BAAALgADCgIJAgAAAA==.',
Hi='Hibernate:BAAALgADCgEJAQAAAA==.Hippolytus:BAAALgADCgkJCQABLgAECgkJLgAeAPQkAA==.Hippopotamus:BAAALgAECgMJAwAAAA==.Hit:BAAALgAECgYJCwAAAA==.',
Ho='Holytide:BAABLgAECn82AAMKAAkJ9w4ZQwAnAQAKAAgJqgwZQwAnAQAiAAkJsgwFEAAQAQAAAA==.Hope:BAABLgAECn8wAAIYAAgJbww4OQAuAQAYAAgJbww4OQAuAQAAAA==.Horrorfang:BAABLgAECn9PAAIBAAkJUiHxCwANAwABAAkJUiHxCwANAwAAAA==.',
Hu='Hukjo:BAAALgAECgcJEgABLgAECgkJIwALACEUAA==.',
Ib='Ibaar:BAACLgAFFH8YAAIGAAcJFSLYHgBpAQAGAAcJFSLYHgBpAQAuAAQKfy4AAwYACQnNI00HAAUDAAYACAlEI00HAAUDABoABgneIAcNAAoCAAAA.',
Ic='Icepickle:BAAALgADCgcJAQAAAA==.Icialiaa:BAAALgAECggJEAABLgAECgkJIAAXAL8LAA==.',
Ii='Iilnut:BAABLgAECn8gAAMUAAgJnCA/CwDPAgAUAAgJnCA/CwDPAgAJAAQJPBW2NwDpAAABLgAFFAQJDAALALEgAA==.',
Il='Illedren:BAABLgAECn8QAAIPAAgJwwc7kAAAAQAPAAgJwwc7kAAAAQAAAA==.',
In='Innerdemon:BAAALgAECgQJBAAAAA==.Inno:BAABLgAECn8YAAIPAAkJDiTxEwDhAgAPAAkJDiTxEwDhAgAAAA==.',
Ir='Irraedorine:BAABLgAECn8gAAMXAAkJvwvcBgAAAQAXAAkJvwvcBgAAAQAhAAgJCwScEwDuAAAAAA==.',
Is='Isabel:BAAALgAECgcJDQABLgAECgkJFAAHAC4UAA==.',
It='Ithacus:BAABLgAECn8pAAIjAAkJtBGcEQCaAQAjAAkJtBGcEQCaAQAAAA==.',
Ja='Jandaar:BAAALgAECgEJAQAAAA==.Jatt:BAAALgAECgMJCAAAAA==.Jattao:BAAALgADCgEJAQAAAA==.Jattex:BAAALgAECgEJAgAAAA==.Jattix:BAAALgAECgIJBQAAAA==.',
Jd='Jdawgprime:BAAALgADCgcJBwAAAA==.',
Je='Jenjas:BAAALgAECgUJBQAAAA==.',
Ji='Jinnlee:BAAALgAECgYJBwAAAA==.Jinoo:BAABLgAECn9CAAIKAAkJhhswDwB9AgAKAAkJhhswDwB9AgAAAA==.Jinufan:BAAALgAECgUJBwABLgAFFAcJGAAGABUiAA==.',
Jo='Jodyhusky:BAAALgADCgYJBgAAAA==.Joe:BAAALgAECgcJCgAAAA==.Jorek:BAABLgAECn8WAAIbAAkJ7BT0KAC2AQAbAAkJ7BT0KAC2AQAAAA==.',
Ju='Jugulator:BAAALgADCgcJDQAAAA==.',
Ka='Kaejung:BAAALgAECgUJBgAAAA==.Kainairobi:BAAALgAECgUJCQAAAA==.Kaiva:BAAALgAECgQJBgABLgAECgYJDgAIAAAAAA==.Kallistô:BAAALgADCgYJBgAAAA==.Kamigawa:BAABLgAECn8VAAIbAAgJqwt/PABTAQAbAAgJqwt/PABTAQAAAA==.Kavik:BAABLgAECn8fAAIcAAkJHhlKEQCKAgAcAAkJHhlKEQCKAgAAAA==.Kazbodan:BAAALgADCgkJFQAAAA==.',
Ke='Keemo:BAACLgAFFH8cAAIMAAYJjRRTHwDsAAAMAAYJjRRTHwDsAAAuAAQKfykAAwwACQnJFachAEUBAAwACQmpFachAEUBAAEAAwmYDUX8AIMAAAAA.Keemosaki:BAAALgAFFAEJAwAAAA==.Keemõ:BAABLgAECn8XAAMPAAYJvw1QnwDkAAAPAAYJ0wxQnwDkAAAkAAYJownQIACXAAAAAA==.Keemøsabi:BAAALgAFFAEJAgAAAA==.Keflá:BAAALgAECgYJEgAAAA==.Keineliebe:BAAALgADCgcJBwAAAA==.Keysersöze:BAAALgADCgYJBwAAAA==.',
Kh='Khaas:BAABLgAECn9QAAIBAAkJuQ9CTgDYAQABAAkJuQ9CTgDYAQAAAA==.Khaleeb:BAAALgAECgEJAwAAAA==.',
Ki='Kierios:BAABLgAECn8oAAMNAAkJiRbCCAD+AQANAAkJTxPCCAD+AQABAAgJ3RDmawCOAQAAAA==.Kildurgan:BAAALgAECgQJDQAAAA==.Killawarlock:BAABLgAECn8hAAQSAAgJzCKLPgDiAQASAAcJNSCLPgDiAQATAAQJbCIsFAAuAQARAAEJ/hAbcAA2AAAAAA==.Kironn:BAAALgADCgYJBgABLgAFFAMJBwADALYHAA==.',
Kk='Kkain:BAAALgAECgIJBwAAAA==.',
Ko='Korihor:BAABLgAECn8pAAIlAAkJ6B1fCQA7AgAlAAkJ6B1fCQA7AgAAAA==.',
Kr='Krestus:BAABLgAECn8RAAMOAAcJJRyxQACzAAAPAAYJrxkZfgAvAQAOAAMJKSCxQACzAAAAAA==.Krispy:BAABLgAECn87AAQDAAkJHxbJFAAUAgADAAkJEhbJFAAUAgAeAAcJ2Q4VOAAcAQALAAUJvgO5TgCZAAAAAA==.Krith:BAAALgADCgYJCQAAAA==.Krix:BAAALgAECgMJBAAAAA==.',
Ky='Kyndil:BAAALgAECgcJEQAAAA==.',
La='Laerin:BAABLgAECn8UAAIcAAkJZBSxLACtAQAcAAkJZBSxLACtAQAAAA==.Laxus:BAAALgAECgMJAwABLgAECgkJHwAZAJMSAA==.Lazarius:BAAALgADCgQJBAAAAA==.',
Le='Leafblade:BAAALgAECgkJDAAAAA==.Levophed:BAABLgAECn8uAAIBAAcJkg+BrAAZAQABAAcJkg+BrAAZAQAAAA==.Lexor:BAAALgAECgMJAwAAAA==.',
Li='Liangwei:BAAALgAECgMJAwABLgAFFAMJBwAHAPMdAA==.Lightfallen:BAAALgAECgcJEQAAAA==.Lightseeker:BAAALgAECgEJAQABLgAECgkJHwAZAJMSAA==.Liisara:BAABLgAECn8bAAIPAAgJZggzigAMAQAPAAgJZggzigAMAQAAAA==.Lily:BAABLgAECn88AAIgAAkJHRu1DAAWAgAgAAkJHRu1DAAWAgAAAA==.Linadra:BAABLgAECn8uAAIQAAkJgwmikQBPAQAQAAkJgwmikQBPAQAAAA==.Linnt:BAAALgAECgQJBwAAAA==.Linzur:BAAALgAECgEJAQAAAA==.Littleyeti:BAAALgAECgMJAwAAAA==.Liyara:BAACLgAFFH8bAAIQAAYJcB82IACGAQAQAAYJcB82IACGAQAuAAQKfykAAhAACQm1JUgRAAYDABAACQm1JUgRAAYDAAAA.',
Ll='Llorsa:BAABLgAECn9FAAMWAAkJZhfiEQBQAgAWAAkJZhfiEQBQAgAUAAUJdA1aUADPAAAAAA==.',
Lo='Lohhan:BAAALgADCgUJCQAAAA==.Lolamontez:BAAALgAECgIJAgAAAA==.Lorachka:BAAALgADCgIJAgAAAA==.Lorthys:BAAALgADCgEJAQAAAA==.',
Lu='Luxian:BAACLgAFFH8JAAIQAAIJxghMSwB5AAAQAAIJxghMSwB5AAAuAAQKf1MAAhAACQkgFYIRADkBABAACQkgFYIRADkBAAAA.',
Ly='Lyssirix:BAABLgAECn8eAAIKAAcJdBYvBQCQAQAKAAcJdBYvBQCQAQAAAA==.',
Ma='Macandcheese:BAAALgAECgMJBwAAAA==.Macy:BAABLgAECn8YAAIfAAcJJhO4FQAWAQAfAAcJJhO4FQAWAQAAAA==.Mahiru:BAAALgADCgEJAQAAAA==.Mahralla:BAAALgADCgIJAgAAAA==.Maikagond:BAAALgAECgYJDgABLgAECgkJMwAQAKQLAA==.Makaria:BAAALgAECggJEAAAAA==.Malbisa:BAAALgAECgQJBgAAAA==.Malphoz:BAAALgAECgUJBwAAAA==.Mandragora:BAABLgAECn8bAAIQAAkJXBJgiQBdAQAQAAkJXBJgiQBdAQAAAA==.Maoriofdeath:BAAALgADCgEJAQABLgAECgYJDgAIAAAAAA==.Map:BAAALgAECgIJAwAAAA==.Marli:BAAALgADCgEJAQAAAA==.Mattieatzdot:BAAALgAECgQJBQAAAA==.',
Mc='Mcgrowlin:BAAALgAECgQJCwAAAA==.',
Me='Mekator:BAAALgAECgQJBAAAAA==.Meko:BAAALgAECgUJBwAAAA==.Merrycow:BAAALgAECggJCwAAAA==.Mew:BAAALgAECgIJAwABLgAECgcJCwAIAAAAAA==.',
Mi='Mickey:BAACLgAFFH8IAAIDAAQJJwsEHwDeAAADAAQJJwsEHwDeAAAuAAQKfygAAgMACQkTIlcHANQCAAMACQkTIlcHANQCAAAA.Migraine:BAAALgAECgYJCgAAAA==.Mikiik:BAABLgAECn9GAAISAAkJzwqaXACIAQASAAkJzwqaXACIAQAAAA==.Mildoo:BAABLgAECn8sAAITAAkJBA/2CwCeAQATAAkJBA/2CwCeAQAAAA==.Milkymoo:BAABLgAECn8iAAIEAAUJfxybHgA/AQAEAAUJfxybHgA/AQABLgAFFAkJNQAWAKYWAA==.Millina:BAAALgADCgIJAgABLgAECgkJOgADAGMOAA==.Mimira:BAAALgAECgEJAQAAAA==.Minipal:BAAALgAECgcJEQABLgAECgkJFgACAKcdAA==.Mixednuts:BAACLgAFFH8MAAILAAQJsSAOIABuAQALAAQJsSAOIABuAQAuAAQKfycAAwsACQmiIhoEAHIDAAsACQmiIhoEAHIDAAMABgkoIKofANoBAAAA.',
Mo='Mochii:BAAALgADCgYJBgAAAA==.Moneyshock:BAAALgAECgYJBgABLgAFFAQJEAAdAGEeAA==.Monq:BAABLgAECn8YAAMDAAgJBBjAHADIAQADAAgJBBjAHADIAQAeAAEJyAkqjQAqAAAAAA==.Moonamber:BAAALgADCgQJBgAAAA==.Morphinzerr:BAAALgAECgEJAQAAAA==.Moón:BAAALgAECgEJAwAAAA==.',
Mu='Murdrmittens:BAAALgADCgEJAQAAAA==.',
My='Mysterychogs:BAAALgAECgEJAQABLgAECgkJLgAUAMYbAA==.Mythion:BAABLgAECn8kAAMVAAgJcRpmJQAiAgAVAAgJcRpmJQAiAgAYAAQJCQWtawBzAAAAAA==.Mythlocked:BAAALgAECgYJBgAAAA==.Mythoridan:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîlk:BAABLgAFFH8HAAIOAAUJaguhDgC7AAAOAAUJaguhDgC7AAAAAA==.',
Na='Naeres:BAABLgAECn8fAAIBAAgJkBcvcACEAQABAAgJkBcvcACEAQAAAA==.Nafari:BAAALgAECggJCAAAAA==.Naofummi:BAAALgAECgcJBwAAAA==.Naomii:BAABLgAECn8rAAMWAAkJxxnUFwAPAgAWAAkJxxnUFwAPAgAUAAUJZQiXWQCvAAAAAA==.Narus:BAAALgAECgcJCgABLgAECgkJNQAbALAYAA==.Naturefury:BAAALgADCgEJAQAAAA==.',
Ne='Neeston:BAACLgAFFH8HAAIVAAMJzBI9PAC+AAAVAAMJzBI9PAC+AAAuAAQKfyIAAxUACAkJI5oPANcCABUACAkJI5oPANcCABgAAQllEtyAADAAAAEuAAUUBAkQAB0AYR4A.Neodin:BAABLgAECn8jAAIbAAkJlQ+0JgDEAQAbAAkJlQ+0JgDEAQAAAA==.Neoresto:BAAALgAECgMJAwAAAA==.Nephadin:BAAALgADCgUJAwABLgAECgkJKQAlABQiAA==.Nerfed:BAAALgAECgUJCAAAAA==.Neviaa:BAABLgAECn8uAAIBAAkJXRSyQAABAgABAAkJXRSyQAABAgAAAA==.',
Ni='Nickypoo:BAAALgAECgMJBgAAAA==.Nightmenace:BAAALgAECgcJCwAAAA==.Ninari:BAAALgADCgUJBQAAAA==.Niq:BAAALgAECgQJBAAAAA==.',
No='Nocshadue:BAAALgADCgYJCwAAAA==.Nordga:BAAALgADCgcJBwAAAA==.Norii:BAAALgADCgIJAgABLgAECgkJDgAIAAAAAA==.Nothealster:BAAALgAECgcJEwAAAA==.Nothros:BAAALgADCgQJBAAAAA==.',
Ob='Obitrice:BAAALgAECggJCwAAAA==.Obsidiian:BAABLgAECn8VAAImAAgJlREnCgCBAQAmAAgJlREnCgCBAQAAAA==.Obsidion:BAABLgAECn8YAAMUAAYJrwzAWwCnAAAUAAUJ5gnAWwCnAAAWAAQJDggFVgCEAAABLgAECgkJNQAbALAYAA==.',
Od='Odie:BAAALgAECgYJDwAAAA==.',
On='Onemorehit:BAAALgAECgEJAwAAAA==.Onlyfangs:BAABLgAECn9KAAMZAAkJUxIjDQAAAgAZAAkJUxIjDQAAAgAGAAYJtwX9awCXAAAAAA==.',
Os='Oscrapermort:BAAALgADCgMJAwAAAA==.Ossin:BAAALgAFFAIJBAAAAA==.',
Pa='Padivyn:BAABLgAECn8ZAAIKAAgJzxiQIwDKAQAKAAgJzxiQIwDKAQAAAA==.Padnamprik:BAAALgAECgQJBAAAAA==.Palidenman:BAAALgAECgQJAwAAAA==.Pantherlilly:BAAALgAECgYJCQAAAA==.',
Pe='Peanads:BAAALgADCgcJEAAAAA==.Pebblez:BAAALgADCgcJDgAAAA==.Perry:BAACLgAFFH8GAAIVAAMJcB5zKwAJAQAVAAMJcB5zKwAJAQAuAAQKfyoAAxUACQm6Ie8EAGwDABUACQm6Ie8EAGwDABgAAgkBBTuCAEQAAAAA.',
Ph='Phlampped:BAAALgADCgUJBQABLgAFFAgJIAAQAJsYAA==.',
Pi='Pinotage:BAAALgAECggJDgABLgAECgkJOwABAFgdAA==.',
Po='Po:BAAALgAECgkJCAAAAA==.Pozufuma:BAABLgAECn9HAAMbAAkJHB2ZDAChAgAbAAkJHB2ZDAChAgAEAAEJ7gtAFAAkAAAAAA==.',
Pr='Priestcraft:BAAALgADCgIJAgABLgAECggJCwAIAAAAAA==.',
Ps='Psychomantis:BAABLgAECn8qAAMUAAkJeRQGHwDNAQAUAAkJeRQGHwDNAQAWAAEJwRGYGgAvAAAAAA==.',
Pu='Punchypunch:BAAALgADCgkJFAAAAA==.',
Ra='Raek:BAAALgAECgQJBQABLgAECgcJGQATAPEbAA==.Raith:BAAALgAECgYJCwAAAA==.Ravenbear:BAAALgAECgQJBgABLgAECgkJSgAZAFMSAA==.Ravenbyrd:BAAALgADCgMJAwAAAA==.Rawberriez:BAAALgAECgQJBgAAAA==.',
Re='Reani:BAAALgADCgQJBAAAAA==.Reapin:BAAALgADCgUJBQAAAA==.Redpool:BAABLgAECn8fAAIHAAcJJBGNQACtAQAHAAcJJBGNQACtAQAAAA==.Remithedrood:BAAALgADCgIJAgAAAA==.Reqium:BAAALgADCgYJCAAAAA==.Resto:BAAALgAECgQJBgAAAA==.Rethandra:BAABLgAECn8YAAQHAAgJ9hP9XgCKAQAHAAcJSRX9XgCKAQAnAAMJLxRhHwC0AAAdAAIJ3gdOEAA9AAAAAA==.Retrix:BAAALgAECgIJAwAAAA==.Revorra:BAAALgAECgcJCAABLgAECgkJNQAbALAYAA==.',
Ri='Rion:BAABLgAECn8XAAIfAAkJcxHRYgC5AQAfAAkJcxHRYgC5AQAAAA==.Ristvakbaen:BAACLgAFFH8EAAISAAIJVRqZkwCbAAASAAIJVRqZkwCbAAAuAAQKfzoABBMACQnmJEEDAIYCABMACAlGJUEDAIYCABIACQm8HbofAGYCABEABgk9JRYGAAQCAAAA.',
Ro='Robynlee:BAABLgAECn9SAAIWAAgJpRoQAgBaAgAWAAgJpRoQAgBaAgAAAA==.Roccobb:BAAALgADCgYJBgAAAA==.Rogùe:BAAALgAFFAIJAgAAAA==.Rosebelle:BAAALgAECgQJAwAAAA==.',
Ru='Rugratt:BAAALgADCgQJBAABLgADCgcJDgAIAAAAAA==.',
Sa='Saeler:BAAALgAECgMJAwAAAA==.Sailrmoonkin:BAAALgAECgQJBQABLgAFFAMJBgAMABUVAA==.Samoth:BAAALgADCgEJAQAAAA==.Sanathein:BAAALgADCgcJBwAAAA==.Sanctuary:BAAALgAECgQJBAAAAA==.Santeclair:BAAALgAECgEJAQAAAA==.Satin:BAAALgAECggJDQAAAA==.',
Sc='Sceryna:BAACLgAFFH8GAAIQAAMJKA9vNAC9AAAQAAMJKA9vNAC9AAAuAAQKfygAAhAACQnMF0FJAOoBABAACQnMF0FJAOoBAAAA.Schiftly:BAAALgAFFAIJAgAAAA==.Schwiggity:BAAALgAECgQJCQABLgAECgkJGwAQAFwSAA==.Scottlock:BAABLgAECn8WAAIRAAcJqh6QBQAVAgARAAcJqh6QBQAVAgABLgAECgkJLgAjAAIjAA==.Screwbrew:BAAALgAECgIJAgAAAA==.Screwid:BAAALgAECgQJBAAAAA==.Screwtotems:BAAALgAECgEJAQAAAA==.Scrmndemn:BAABLgAECn80AAIQAAkJdAidpAAwAQAQAAkJdAidpAAwAQAAAA==.',
Se='Sepviva:BAABLgAECn8VAAIBAAcJNhZmcACoAQABAAcJNhZmcACoAQAAAA==.Serea:BAAALgAECgEJAQABLgAECgkJUgAWAKUaAA==.Serpent:BAACLgAFFH8OAAIEAAYJ5BS9CgCDAQAEAAYJ5BS9CgCDAQAuAAQKfyMAAgQACQlnHxkIAHoCAAQACQlnHxkIAHoCAAEuAAUUBwkkAAwAXxYA.',
Sh='Shadowheal:BAAALgADCgUJBgAAAA==.Shamadeus:BAAALgADCgUJBQABLgAFFAIJBAASAFUaAA==.Shamtastical:BAAALgAECggJCwABLgAECgkJUgAWAKUaAA==.Sharaseth:BAAALgAECggJEQAAAA==.Shikita:BAABLgAECn9MAAMVAAkJnB51DQDvAgAVAAkJnB51DQDvAgAYAAEJHAZfigAlAAAAAA==.Shimadin:BAACLgAFFH8gAAIQAAYJphdmOAA8AQAQAAYJphdmOAA8AQAuAAQKfykAAhAACQkfHvszADACABAACQkfHvszADACAAAA.Shimbuktu:BAAALgAECgEJAwABLgAFFAYJIAAQAKYXAA==.Shimfu:BAAALgAECgEJAgABLgAFFAYJIAAQAKYXAA==.Shimjun:BAAALgAECgUJCwABLgAFFAYJIAAQAKYXAA==.Shimpbizkit:BAABLgAECn8ZAAIfAAcJAg0VnwA8AQAfAAcJAg0VnwA8AQABLgAFFAYJIAAQAKYXAA==.Shimsong:BAAALgAECgYJEwABLgAFFAYJIAAQAKYXAA==.Shmerek:BAABLgAECn8XAAIEAAkJRSBCCAB3AgAEAAkJRSBCCAB3AgAAAA==.',
Si='Sidarien:BAAALgADCgQJBAAAAA==.Silenttits:BAAALgAECgEJAgAAAA==.Silveralae:BAAALgAECgEJAQAAAA==.Silveraven:BAAALgADCgIJAgAAAA==.Silverlumen:BAAALgAFFAEJAgAAAA==.Silversaevus:BAAALgAFFAEJAQAAAA==.Silverstream:BAACLgAFFH8IAAIVAAMJGgqLSQCUAAAVAAMJGgqLSQCUAAAuAAQKfyoAAhUACQnoER1CAJkBABUACQnoER1CAJkBAAAA.',
Sk='Skyblue:BAAALgADCgEJAQAAAA==.',
Sl='Slea:BAABLgAECn8VAAIdAAkJQxApFAAEAgAdAAkJQxApFAAEAgAAAA==.Slease:BAAALgAECgYJBgAAAA==.',
Sm='Smallrichard:BAAALgAECgEJAQAAAA==.Smootish:BAAALgADCgUJBQAAAA==.',
So='Solbin:BAAALgAECgUJDAABLgAECgkJLwAfAIYZAA==.Solitudé:BAABLgAECn8fAAMSAAgJBiSWHwBnAgASAAcJPiGWHwBnAgATAAUJoSW1FAAoAQABLgAFFAUJFAANAP4fAA==.Soteirian:BAABLgAECn8zAAMQAAkJpAuIcgCJAQAQAAkJpAuIcgCJAQAlAAEJjwJKXwASAAAAAA==.',
Sp='Spam:BAAALgAECgIJAgAAAA==.Spekey:BAAALgAECgEJAQAAAA==.Spider:BAABLgAECn87AAIBAAkJWB17BABAAgABAAkJWB17BABAAgAAAA==.Spineymagus:BAAALgADCgIJAgAAAA==.',
Sq='Squall:BAABLgAECn8rAAMiAAgJMhCNRwCQAQAiAAgJMhCNRwCQAQAKAAYJ0ROVRQAdAQAAAA==.',
St='Stalariais:BAAALgAECgQJBAABLgAECgkJGQAcAHoIAA==.Stardrand:BAAALgADCgUJBgAAAA==.Steeg:BAAALgAECgYJDgAAAA==.Steelreserve:BAAALgAECgYJDQAAAA==.Straw:BAAALgAECgYJCwABLgAECgkJQwAQAGgkAA==.',
Su='Sugarkitty:BAAALgADCgYJCgAAAA==.Supereclipse:BAABLgAECn9IAAIHAAkJ/hZDKQA5AgAHAAkJ/hZDKQA5AgAAAA==.',
Sw='Swolareclips:BAAALgADCgYJBgAAAA==.',
Sy='Sydvicious:BAABLgAECn8iAAIOAAkJPCVYBAAEAwAOAAkJPCVYBAAEAwAAAA==.Syriene:BAABLgAECn8uAAICAAkJPBByEQCjAQACAAkJPBByEQCjAQABLgAECgkJIAAXAL8LAA==.',
Ta='Taladiir:BAAALgAECgEJAQAAAA==.Talana:BAAALgAECgEJAQAAAA==.Tankhealz:BAAALgAECgMJBQAAAA==.Tanthe:BAAALgAECgMJAwAAAA==.Tayger:BAAALgAFFAEJAQAAAA==.',
Tb='Tbsp:BAAALgAECgEJAQABLgAFFAUJFgALAEocAA==.',
Te='Tecks:BAABLgAECn8XAAIWAAkJwgWfPAABAQAWAAkJwgWfPAABAQAAAA==.Teddy:BAAALgAECgUJCQAAAA==.Teslá:BAAALgAECgYJCgAAAA==.',
Th='Theatrix:BAAALgAECgQJBwABLgAECgkJHgAGANsYAA==.Thecuckler:BAAALgAECgQJCAAAAA==.Thefreeman:BAAALgAECgEJAQAAAA==.Themajor:BAABLgAECn8uAAMFAAkJFhfmDAAYAgAFAAkJFhfmDAAYAgAbAAcJ/AhwTAB0AQAAAA==.Then:BAAALgADCgEJAQAAAA==.Thiarad:BAAALgADCgEJAQAAAA==.Thiaraxo:BAACLgAFFH8JAAMLAAMJHyE7HQDPAAALAAMJHyE7HQDPAAADAAEJjhbEGgBJAAAuAAQKfxUAAgsACQmbBcp5ALAAAAsACQmbBcp5ALAAAAAA.Thrain:BAAALgADCgcJDAAAAA==.Threat:BAABLgAECn8mAAIQAAkJlCWXBQBHAwAQAAkJlCWXBQBHAwAAAA==.Thronkall:BAAALgAECgkJAgAAAA==.Thsarus:BAABLgAECn8vAAMPAAgJ6yDlHABnAgAPAAgJ6yDlHABnAgAkAAQJHBHQGwCxAAAAAA==.Thunderthigh:BAAALgAECgIJAgAAAA==.',
Ti='Tiamaat:BAABLgAECn8XAAIVAAkJmgQKegDJAAAVAAkJmgQKegDJAAAAAA==.Tireyne:BAAALgADCgEJAgAAAA==.Titus:BAAALgAECgEJBgAAAA==.',
Tk='Tkt:BAAALgAECgIJBAABLgAFFAIJAgAIAAAAAA==.',
To='Toatani:BAAALgAECgYJDgAAAA==.Tokkaebi:BAAALgAECgkJDAAAAA==.',
Tr='Treadlightly:BAAALgADCgUJBwAAAA==.Treefróg:BAAALgAECgUJBQAAAA==.Trentus:BAAALgADCgIJAgAAAA==.Trev:BAAALgAECgUJBgABLgAFFAUJBQASAIUWAA==.Trotem:BAAALgAECgUJBQAAAA==.',
Ts='Tsp:BAACLgAFFH8WAAILAAUJShwOHACSAQALAAUJShwOHACSAQAuAAQKfywAAwsACQn/Gd8cADECAAsACQn/Gd8cADECAB4ABAnxA0psAJEAAAAA.',
Ty='Tyletos:BAABLgAECn8vAAIfAAkJhhkoDACEAQAfAAkJhhkoDACEAQAAAA==.',
Ug='Ugolok:BAABLgAECn8pAAMNAAcJ7gfrIQC/AAANAAYJzQjrIQC/AAABAAcJKQUnLgBqAAAAAA==.',
Ur='Uriél:BAABLgAECn8yAAIPAAkJNSWeAgBeAwAPAAkJNSWeAgBeAwABLgAFFAUJFAANAP4fAA==.',
Va='Valeene:BAABLgAECn8uAAIYAAkJLiJSBAAcAwAYAAkJLiJSBAAcAwAAAA==.Valkion:BAAALgAECgEJAQAAAA==.Varek:BAABLgAECn8YAAIXAAkJ5yEyAwAbAwAXAAkJ5yEyAwAbAwAAAA==.Varlann:BAAALgADCgkJCQAAAA==.',
Ve='Veiler:BAABLgAECn9GAAMHAAkJEROKNgADAgAHAAkJEROKNgADAgAnAAEJ3wH2lgAhAAAAAA==.Velca:BAAALgAECgIJAgAAAA==.Veruca:BAAALgAECgMJAwAAAA==.Veviseron:BAABLgAECn8qAAIfAAkJNwSvpgAwAQAfAAkJNwSvpgAwAQAAAA==.',
Vh='Vhye:BAABLgAFFH8IAAIiAAMJtgZnZAB+AAAiAAMJtgZnZAB+AAAAAA==.',
Vi='Vidnoi:BAAALgAECgEJBAAAAA==.Vincentfreak:BAAALgADCgYJBgAAAA==.Vinstalation:BAABLgAECn81AAINAAkJcRwxBgBHAgANAAkJcRwxBgBHAgAAAA==.Vissa:BAAALgADCgYJBgAAAA==.',
Vo='Vonbismarck:BAABLgAECn8lAAMHAAkJ8hOSTQC5AQAHAAkJ8hOSTQC5AQAnAAEJFw87DAAvAAAAAA==.',
Vr='Vritraz:BAACLgAFFH8UAAMNAAUJ/h9wCABnAQANAAQJ/h9wCABnAQABAAEJAACtLQEAAAAuAAQKfxUAAw0ACQmLIqEGADkCAA0ABwk+I6EGADkCAAEAAgl0IAP3ALcAAAAA.Vrock:BAAALgAECgEJAQABLgAECgkJLwAfAHIeAA==.',
Wa='Warnam:BAAALgADCgcJBwAAAA==.Warsonge:BAAALgADCgMJAwAAAA==.',
We='Wendypini:BAACLgAFFH8VAAIHAAUJKAeKUwACAQAHAAUJKAeKUwACAQAuAAQKfyIAAgcACQkAEF5FAJsBAAcACQkAEF5FAJsBAAAA.Wetnwild:BAAALgADCgQJBAAAAA==.',
Wh='Whitehand:BAAALgAECgIJAgAAAA==.Whitlock:BAAALgAFFAEJAQAAAA==.',
Wo='Wooshwoosh:BAAALgAECgQJDgAAAA==.',
Wu='Wudeeps:BAAALgAECgcJEgAAAA==.Wuhanwarrior:BAAALgAECgYJEQAAAA==.',
Xa='Xalyra:BAAALgAECgEJAQAAAA==.',
Xe='Xendria:BAAALgAECgEJBAAAAA==.',
Ya='Yako:BAAALgAECgEJAQAAAA==.',
Ye='Yennefer:BAAALgAECgMJAwAAAA==.',
Yo='Yongary:BAAALgAECgkJCQAAAA==.',
Za='Zangolf:BAAALgADCgUJBAAAAA==.Zargoan:BAAALgAECgMJBAAAAA==.Zaye:BAAALgAECggJDAAAAA==.',
Ze='Zearas:BAABLgAECn8UAAIBAAgJJxE+kwBZAQABAAgJJxE+kwBZAQAAAA==.Zendonn:BAABLgAECn8bAAIDAAcJxwUiUgDAAAADAAcJxwUiUgDAAAAAAA==.Zerk:BAAALgAECgEJAQAAAA==.',
Zi='Zicatriz:BAAALgADCgcJDgAAAA==.',
Zo='Zodiaac:BAABLgAECn8XAAIMAAkJdxm1FQC+AQAMAAkJdxm1FQC+AQAAAA==.',
Zu='Zuggy:BAAALgAFFAEJAQABLgAFFAQJEAAdAGEeAA==.',
Zy='Zy:BAAALgADCgUJBQAAAA==.',
['Zà']='Zàknafein:BAABLgAECn8fAAMTAAYJ5hdyAgByAQATAAYJ5hdyAgByAQASAAMJ3wVHLQBCAAAAAA==.',
['Ëc']='Ëchõ:BAABLgAECn8gAAMVAAkJ+RXSNwDIAQAVAAkJ+RXSNwDIAQAYAAIJvwRldwBHAAAAAA==.',
['Ðï']='Ðï:BAAALgADCgQJBAABLgAECgkJLAAUAAcdAA==.',
['ßo']='ßoomer:BAAALgADCgIJAgABLgAFFAMJBwADALYHAA==.',
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
