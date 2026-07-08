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

local lookup = {'Druid-Feral','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Unknown-Unknown','Hunter-BeastMastery','Priest-Discipline','Shaman-Elemental','Monk-Mistweaver','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Druid-Restoration','Rogue-Subtlety','Priest-Holy','Druid-Balance','Evoker-Preservation','DeathKnight-Frost','Evoker-Devastation','Evoker-Augmentation','Warrior-Fury','Paladin-Holy','Hunter-Survival','Monk-Brewmaster','Mage-Frost','Druid-Guardian','Rogue-Assassination','DeathKnight-Unholy','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Protection','Rogue-Outlaw','Hunter-Marksmanship',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abominable:BAAALgADCgEJAQAAAA==.',
Ae='Aelaster:BAAALgADCgYJBgAAAA==.',
Ag='Agden:BAAALgADCgEJAQAAAA==.',
Al='Alaìrn:BAAALgAECgUJCwABLgAECgkJFgABAKcdAA==.Aldrich:BAAALgAECgYJBwAAAA==.Alenciann:BAAALgAECgMJBwAAAA==.Alys:BAABLgAECn83AAICAAkJYw4IIgCfAQACAAkJYw4IIgCfAQAAAA==.',
Am='Amaniatres:BAABLgAECn8eAAMDAAcJHxJXBQC2AAADAAcJdhBXBQC2AAAEAAQJEw8XSwChAAABLgAECgcJEgAFAAAAAA==.Ammartin:BAABLgAECn8YAAIGAAkJyQo1bQBnAQAGAAkJyQo1bQBnAQAAAA==.Amoonranara:BAAALgADCgEJAQAAAA==.',
An='Anaan:BAAALgAECgUJBgAAAA==.Anahera:BAAALgADCgQJBAABLgAECgYJDQAFAAAAAA==.Anfna:BAAALgAECgEJAQAAAA==.Angrylizard:BAAALgAECgEJAgAAAA==.Anklebiterr:BAAALgAECgUJBwAAAA==.',
Ap='Apothecary:BAAALgADCgcJBwAAAA==.',
Ar='Arabella:BAAALgAECggJEQAAAA==.Arandomidiot:BAAALgADCgYJBgAAAA==.Arathan:BAAALgADCgkJHAAAAA==.Ariiana:BAABLgAECn8XAAIHAAkJIx7rBgAOAwAHAAkJIx7rBgAOAwAAAA==.',
As='Asapshocky:BAACLgAFFH8TAAIIAAgJLhjFBgCIAQAIAAgJLhjFBgCIAQAuAAQKfy4AAggACQnTIxIFAA0DAAgACQnTIxIFAA0DAAAA.Asclepios:BAAALgAECgMJBAAAAA==.Asmoday:BAAALgAECgYJBgAAAA==.Astraroth:BAAALgADCgQJBAAAAA==.',
Av='Avella:BAAALgADCgUJBwAAAA==.',
Ba='Balaris:BAAALgADCgcJBwABLgAECgkJIwAJACEUAA==.Balum:BAAALgAECgEJAQAAAA==.Bamwham:BAAALgADCgcJBwAAAA==.Barrii:BAAALgAECgMJBQAAAA==.',
Be='Bearblaster:BAAALgADCgQJBAABLgAECgQJBgAFAAAAAA==.Bearlytanks:BAAALgADCgIJAgAAAA==.Beastwallker:BAAALgADCgUJBgAAAA==.Bellabelle:BAAALgAECgQJCQAAAA==.Ben:BAAALgAECgcJEwAAAA==.Betamaxx:BAABLgAECn8VAAIKAAcJgh2IEgDmAQAKAAcJgh2IEgDmAQAAAA==.Betterx:BAAALgAECgQJBQAAAA==.Bevian:BAAALgADCgIJAgABLgAECgkJDAAFAAAAAA==.',
Bi='Biggiepants:BAABLgAECn8iAAMLAAkJ0h9oBwC7AgALAAkJ0h9oBwC7AgAMAAgJ9w6fYABoAQAAAA==.Bighead:BAAALgAECgYJCAABLgAFFAMJBwACALYHAA==.Bigwarlocks:BAAALgAECgMJBwABLgAFFAMJBwACALYHAA==.Bintje:BAAALgADCgcJEgAAAA==.Biollante:BAAALgAECgcJCwAAAA==.',
Bl='Blindedlïght:BAAALgAECgUJBgAAAA==.',
Bo='Bolsan:BAAALgAECgMJBQAAAA==.Bonq:BAAALgAECgIJAgABLgAECgkJEQALACUcAA==.Bourg:BAAALgAECgYJCAAAAA==.Bowhemian:BAAALgAECgMJBgAAAA==.',
Bu='Buckis:BAABLgAECn8VAAINAAYJrBdDCgBEAQANAAYJrBdDCgBEAQAAAA==.Bufú:BAAALgADCgIJAgAAAA==.',
['Bö']='Böurbon:BAAALgADCgkJCgAAAA==.',
Ca='Cahk:BAAALgAECgMJAwAAAA==.Cajia:BAABLgAECn8sAAMOAAgJRws8HQC+AAAPAAgJtQndfgA7AQAOAAYJBgs8HQC+AAAAAA==.Canon:BAAALgAECgkJAwAAAA==.',
Ce='Celds:BAAALgADCgQJBAABLgAECgcJGQAQAPEbAA==.Celiae:BAAALgAECgYJEAAAAA==.Cendanel:BAAALgAECgIJAgAAAA==.',
Ch='Childress:BAAALgAECgMJAwAAAA==.Chiwhiz:BAAALgAECgEJAQABLgAECgQJCwAFAAAAAA==.Choggy:BAABLgAECn8uAAIRAAkJxhvnDgBqAgARAAkJxhvnDgBqAgAAAA==.Chogs:BAAALgAECgMJBAABLgAECgkJLgARAMYbAA==.',
Ci='Cimbline:BAAALgADCgIJAgAAAA==.',
Cl='Clairerick:BAAALgAECgYJEAAAAA==.',
Co='Cokebear:BAAALgAECgMJAwABLgAECggJJAASAHEaAA==.Composer:BAAALgAECgcJEgAAAA==.Confessionn:BAAALgADCggJDAAAAA==.Cough:BAAALgAECgUJCwABLgAFFAMJBwACALYHAA==.',
Cr='Crinklecut:BAABLgAECn8ZAAITAAgJQQwKJQBtAQATAAgJQQwKJQBtAQAAAA==.Critos:BAAALgADCgcJBwAAAA==.Crotchout:BAAALgADCgMJAwAAAA==.Crybaby:BAAALgADCgEJAQAAAA==.Crystilpixy:BAAALgADCgMJBAAAAA==.',
['Cé']='Céline:BAAALgAECgEJAQAAAA==.',
Da='Dalal:BAAALgAECgQJBAABLgAECgkJSwAUAF4ZAA==.Danilov:BAAALgADCgYJBgAAAA==.',
De='Deadlyshift:BAABLgAECn8XAAMSAAkJsCKWBQBeAwASAAkJsCKWBQBeAwAVAAUJMho8NgBjAQAAAA==.Deadmenace:BAAALgAECgEJAQAAAA==.Deadybear:BAAALgADCgkJEAABLgAECgkJSgAWAFMSAA==.Deathkyter:BAAALgAECgEJAQAAAA==.Delrok:BAAALgAECgEJAgAAAA==.Dephias:BAAALgADCgMJAwAAAA==.',
Di='Diagnosis:BAABLgAECn8eAAINAAkJhSVqCwAKAwANAAkJhSVqCwAKAwAAAA==.',
Do='Donnabb:BAABLgAECn8YAAINAAgJCQXcHgCDAAANAAgJCQXcHgCDAAAAAA==.Donteatbees:BAABLgAECn8UAAIXAAkJZgquGAAPAQAXAAkJZgquGAAPAQAAAA==.Dop:BAAALgAECgEJAwAAAA==.Doran:BAABLgAECn8eAAILAAgJaRcHFwDNAQALAAgJaRcHFwDNAQAAAA==.Doriathrin:BAAALgADCgcJCwAAAA==.Doujinshi:BAABLgAECn8OAAIMAAcJIBziUwCoAQAMAAcJIBziUwCoAQAAAA==.',
Dr='Dragonbladez:BAAALgADCgUJBQAAAA==.Dragoneye:BAAALgAECgMJBgAAAA==.Dragonhawk:BAAALgADCgQJBAABLgAECgMJEgAFAAAAAA==.Dragonname:BAAALgAECgEJAQAAAA==.Drakoil:BAABLgAECn87AAMYAAkJwBi7BAAkAgAYAAkJJRi7BAAkAgAZAAcJNxMiNQBdAQAAAA==.Dreademperor:BAACLgAFFH8JAAIDAAQJdBUnGgDGAAADAAQJdBUnGgDGAAAuAAQKfycAAwMACQkhHvAEAPYCAAMACQkhHvAEAPYCABoABAlDDwliAM8AAAEuAAUUBQkMAAoAJR8A.Dreadnature:BAAALgAECgMJAwAAAA==.Dreadnight:BAABLgAFFH8MAAIKAAUJJR8NFwAwAQAKAAUJJR8NFwAwAQAAAA==.Dreadsteed:BAAALgAECgEJAQABLgAFFAUJDAAKACUfAA==.Dreadweaver:BAAALgADCgUJBQABLgAFFAUJDAAKACUfAA==.Drenrah:BAABLgAECn8pAAIbAAkJug+lKwC0AQAbAAkJug+lKwC0AQAAAA==.Drgndeeznutz:BAACLgAFFH8LAAIcAAQJfheDEwAvAQAcAAQJfheDEwAvAQAuAAQKfygAAhwACQnPHykFANYCABwACQnPHykFANYCAAAA.Drunkenrage:BAACLgAFFH8nAAIdAAgJOxxbBABbAgAdAAgJOxxbBABbAgAuAAQKfx4AAh0ACQkcIvsBAIIDAB0ACQkcIvsBAIIDAAAA.',
Du='Dumorius:BAAALgAECgYJCAAAAA==.',
['Dé']='Déx:BAAALgAECgYJCwAAAA==.',
Ed='Edreth:BAAALgAECgEJAQAAAA==.',
El='Elbryan:BAABLgAECn8xAAIRAAkJhAinMABbAQARAAkJhAinMABbAQAAAA==.Elementdemon:BAAALgAECgUJBgAAAA==.Ellabelle:BAAALgADCgMJAwAAAA==.',
En='Enthalpy:BAABLgAECn8rAAIeAAkJch6IGwC2AgAeAAkJch6IGwC2AgAAAA==.',
Ep='Epipin:BAAALgAECgUJBQAAAA==.',
Er='Erakazsod:BAAALgAECgEJAQAAAA==.Erazath:BAAALgAECgUJCAABLgAECgkJEAAFAAAAAA==.',
Es='Esperzoa:BAABLgAECn8wAAIKAAgJgRx9DQAyAgAKAAgJgRx9DQAyAgAAAA==.',
Et='Eternaldread:BAAALgADCgUJBQABLgAFFAUJDAAKACUfAA==.',
Eu='Eucalicdes:BAABLgAECn9CAAIfAAkJvhfFDQAGAgAfAAkJvhfFDQAGAgAAAA==.',
Ez='Ezal:BAAALgAECgYJCAAAAA==.Ezra:BAAALgAECgQJBAAAAA==.',
Fa='Fallyn:BAAALgAECgEJAQAAAA==.Farshran:BAAALgAECgkJEAAAAA==.Fate:BAAALgAECgQJBQABLgAECgkJJgANAJQlAA==.Fathermajor:BAAALgAECgQJBAAAAA==.',
Fe='Felicity:BAACLgAFFH8WAAITAAUJ2h0THAA6AQATAAUJ2h0THAA6AQAuAAQKfzYAAxMACQmWIpIEAE4DABMACQmWIpIEAE4DACAABQmDDb8VANEAAAAA.Ferendis:BAABLgAECn8nAAIMAAgJPiOiEwCmAgAMAAgJPiOiEwCmAgAAAA==.Fernard:BAAALgADCgYJBgABLgAECgkJEQALACUcAA==.',
Fl='Flokii:BAAALgAECgQJBAAAAA==.Florita:BAAALgAECgYJBwAAAA==.Flydormu:BAAALgAECgYJDAABLgAECgkJKQAeAOQYAA==.',
Fo='Fordinn:BAABLgAECn81AAMaAAkJsBiRGwARAgAaAAkJZRaRGwARAgADAAcJeRUOGwBgAQAAAA==.',
Fr='Fractured:BAAALgADCgEJAQAAAA==.Freelor:BAAALgAECgIJBAAAAA==.Freemi:BAAALgAECgEJAQAAAA==.Frenzy:BAAALgAECgkJAQAAAA==.Frigidgrip:BAAALgAECgMJAwAAAA==.',
Fu='Fuddytwo:BAABLgAECn8pAAIVAAkJ+Bw4DACSAgAVAAkJ+Bw4DACSAgAAAA==.Furrypaw:BAAALgAECgcJBwABLgAFFAEJAgAFAAAAAA==.Furrypunch:BAAALgAFFAEJAgAAAA==.',
Ga='Garzhvog:BAAALgADCgcJCwABLgAFFAIJBAAPAFUaAA==.Gasket:BAACLgAFFH8aAAMXAAUJRhpKDgAnAQAhAAUJ/BcQXgA4AQAXAAUJ3hNKDgAnAQAuAAQKfyUAAyEACQlnIsMiALQCACEACQlvIcMiALQCABcAAwkcIEUZAAoBAAAA.Gauteng:BAAALgAECgIJAgABLgAFFAUJGQANAHwiAA==.',
Gh='Ghidõráh:BAAALgAECgEJAQAAAA==.Ghorac:BAAALgADCgYJDAAAAA==.Ghoti:BAAALgADCgUJBQAAAA==.Ghoulz:BAAALgADCgcJDAAAAA==.',
Gl='Glazedham:BAAALgADCgMJAwAAAA==.',
Gn='Gnollfang:BAAALgADCgYJBgAAAA==.',
Go='Gorbubbli:BAAALgADCgkJGgAAAA==.',
Gr='Graceful:BAAALgAECgUJBgAAAA==.Griffith:BAAALgAECgEJAQAAAA==.Grit:BAAALgAECgYJDAAAAA==.',
Gu='Guidosarduci:BAAALgADCgEJAQAAAA==.Guilddrama:BAAALgADCgEJAQAAAA==.',
Ha='Haeler:BAAALgAECgIJAwAAAA==.Haelin:BAAALgADCgEJAQAAAA==.Halgoðfulk:BAAALgAECgEJAQAAAA==.Hamwarrior:BAAALgAECgEJAQAAAA==.Handicap:BAAALgAECgcJBwABLgAECgkJHgANAIUlAA==.Hark:BAACLgAFFH8aAAIGAAUJwA6oRQAiAQAGAAUJwA6oRQAiAQAuAAQKfywAAgYACQmOG7RQALABAAYACQmOG7RQALABAAAA.Harpin:BAAALgADCgEJAQAAAA==.Harvin:BAABLgAECn80AAIWAAkJgCL0AQBlAwAWAAkJgCL0AQBlAwAAAA==.',
He='Heisenburgg:BAAALgAECgkJCQAAAA==.Hekus:BAEALgAECgcJEQAAAA==.Helanua:BAABLgAECn8rAAIIAAkJQhEQJwCzAQAIAAkJQhEQJwCzAQAAAA==.Hellsplay:BAAALgADCgIJAgAAAA==.',
Hi='Hibernate:BAAALgADCgEJAQAAAA==.Hippolytus:BAAALgADCgkJCQABLgAECgkJLgAdAPQkAA==.Hippopotamus:BAAALgAECgMJAwAAAA==.Hit:BAAALgAECgYJCwAAAA==.',
Ho='Holytide:BAABLgAECn8yAAMIAAkJXA4ZQwAnAQAIAAgJ+QsZQwAnAQAiAAkJmgkAeQD0AAAAAA==.Hope:BAABLgAECn8wAAIVAAgJbww4OQAuAQAVAAgJbww4OQAuAQAAAA==.Horrorfang:BAABLgAECn9LAAIhAAkJUiHxCwANAwAhAAkJUiHxCwANAwAAAA==.',
Hu='Hukjo:BAAALgAECgcJEgABLgAECgkJIwAJACEUAA==.',
Ib='Ibaar:BAACLgAFFH8WAAIZAAUJ/iPYHgBpAQAZAAUJ/iPYHgBpAQAuAAQKfy4AAxkACQnNI00HAAUDABkACAlEI00HAAUDABgABgneIAcNAAoCAAAA.',
Ic='Icepickle:BAAALgADCgcJAQAAAA==.',
Ii='Iilnut:BAABLgAECn8gAAMRAAgJnCA/CwDPAgARAAgJnCA/CwDPAgAHAAQJPBW2NwDpAAABLgAFFAQJDAAJALEgAA==.',
Il='Illedren:BAABLgAECn8QAAIMAAgJwwc7kAAAAQAMAAgJwwc7kAAAAQAAAA==.',
In='Innerdemon:BAAALgAECgQJBAAAAA==.Inno:BAABLgAECn8YAAIMAAkJDiTxEwDhAgAMAAkJDiTxEwDhAgAAAA==.',
Ir='Irraedorine:BAABLgAECn8gAAMTAAkJuw2yBAACAQATAAkJuw2yBAACAQAgAAgJCwScEwDuAAAAAA==.',
Is='Isabel:BAAALgAECgcJDQABLgAECgkJFAAGAC4UAA==.',
It='Ithacus:BAABLgAECn8pAAIjAAkJtBGcEQCaAQAjAAkJtBGcEQCaAQAAAA==.',
Ja='Jandaar:BAAALgAECgEJAQAAAA==.Jatt:BAAALgAECgMJCAAAAA==.Jattao:BAAALgADCgEJAQAAAA==.Jattex:BAAALgAECgEJAgAAAA==.Jattix:BAAALgAECgIJBQAAAA==.',
Jd='Jdawgprime:BAAALgADCgcJBwAAAA==.',
Je='Jenjas:BAAALgAECgUJBQAAAA==.',
Ji='Jinnlee:BAAALgAECgYJBwAAAA==.Jinoo:BAABLgAECn9CAAIIAAkJhhswDwB9AgAIAAkJhhswDwB9AgAAAA==.Jinufan:BAAALgAECgUJBwABLgAFFAUJFgAZAP4jAA==.',
Jo='Joe:BAAALgAECgcJCgAAAA==.Jorek:BAABLgAECn8WAAIaAAkJ7BT0KAC2AQAaAAkJ7BT0KAC2AQAAAA==.',
Ju='Jugulator:BAAALgADCgcJDQAAAA==.',
Ka='Kaejung:BAAALgAECgUJBgAAAA==.Kainairobi:BAAALgAECgUJCQAAAA==.Kaiva:BAAALgAECgQJBgABLgAECgYJDQAFAAAAAA==.Kallistô:BAAALgADCgYJBgAAAA==.Kamigawa:BAABLgAECn8VAAIaAAgJqwt/PABTAQAaAAgJqwt/PABTAQAAAA==.Kavik:BAABLgAECn8fAAIbAAkJHhlKEQCKAgAbAAkJHhlKEQCKAgAAAA==.Kazbodan:BAAALgADCgkJFQAAAA==.',
Ke='Keemo:BAACLgAFFH8aAAIKAAUJxRNTHwDsAAAKAAUJxRNTHwDsAAAuAAQKfykAAwoACQnJFachAEUBAAoACQmpFachAEUBACEAAwmYDUX8AIMAAAAA.Keemosaki:BAAALgAFFAEJAQAAAA==.Keemõ:BAABLgAECn8XAAMMAAYJvw1QnwDkAAAMAAYJ0wxQnwDkAAAkAAYJownQIACXAAAAAA==.Keemøsabi:BAAALgAFFAEJAgAAAA==.Keflá:BAAALgAECgYJEgAAAA==.Keineliebe:BAAALgADCgcJBwAAAA==.Keysersöze:BAAALgADCgYJBwAAAA==.',
Kh='Khaas:BAABLgAECn9MAAIhAAkJuQ9CTgDYAQAhAAkJuQ9CTgDYAQAAAA==.Khaleeb:BAAALgAECgEJAwAAAA==.',
Ki='Kierios:BAABLgAECn8oAAMXAAkJiRbCCAD+AQAXAAkJTxPCCAD+AQAhAAgJ3RDmawCOAQAAAA==.Kildurgan:BAAALgAECgQJDQAAAA==.Killawarlock:BAABLgAECn8hAAQPAAgJzCKLPgDiAQAPAAcJNSCLPgDiAQAQAAQJbCIsFAAuAQAOAAEJ/hAbcAA2AAAAAA==.Kironn:BAAALgADCgYJBgABLgAFFAMJBwACALYHAA==.',
Kk='Kkain:BAAALgAECgIJBwAAAA==.',
Ko='Korihor:BAABLgAECn8nAAIlAAgJYx1fCQA7AgAlAAgJYx1fCQA7AgAAAA==.',
Kr='Krestus:BAABLgAECn8RAAMLAAcJJRyxQACzAAAMAAYJrxkZfgAvAQALAAMJKSCxQACzAAAAAA==.Krispy:BAABLgAECn84AAQCAAkJEhbJFAAUAgACAAkJEhbJFAAUAgAdAAcJOA0VOAAcAQAJAAUJvgO5TgCZAAAAAA==.Krith:BAAALgADCgYJCQAAAA==.Krix:BAAALgAECgMJBAAAAA==.',
Ky='Kyndil:BAAALgAECgcJEQAAAA==.',
La='Laerin:BAABLgAECn8UAAIbAAkJZBSxLACtAQAbAAkJZBSxLACtAQAAAA==.Laxus:BAAALgADCgcJDAABLgAECgkJHwAWAJMSAA==.Lazarius:BAAALgADCgQJBAAAAA==.',
Le='Levophed:BAABLgAECn8uAAIhAAcJkg+BrAAZAQAhAAcJkg+BrAAZAQAAAA==.Lexor:BAAALgAECgMJAwAAAA==.',
Li='Liangwei:BAAALgAECgMJAwABLgAFFAMJBwAGAPMdAA==.Lightfallen:BAAALgAECgcJEQAAAA==.Liisara:BAABLgAECn8bAAIMAAgJZggzigAMAQAMAAgJZggzigAMAQAAAA==.Lily:BAABLgAECn84AAIfAAkJDRu1DAAWAgAfAAkJDRu1DAAWAgAAAA==.Linadra:BAABLgAECn8tAAINAAkJgwmikQBPAQANAAkJgwmikQBPAQAAAA==.Linzur:BAAALgAECgEJAQAAAA==.Littleyeti:BAAALgAECgMJAwAAAA==.Liyara:BAACLgAFFH8ZAAINAAUJfCI2IACGAQANAAUJfCI2IACGAQAuAAQKfykAAg0ACQm1JUgRAAYDAA0ACQm1JUgRAAYDAAAA.',
Ll='Llorsa:BAABLgAECn9EAAMUAAkJZhfiEQBQAgAUAAkJZhfiEQBQAgARAAUJdA1aUADPAAAAAA==.',
Lo='Lohhan:BAAALgADCgUJCQAAAA==.Lolamontez:BAAALgAECgIJAgAAAA==.Lorachka:BAAALgADCgIJAgAAAA==.Lorthys:BAAALgADCgEJAQAAAA==.',
Lu='Luxian:BAACLgAFFH8HAAINAAIJxggaNgCAAAANAAIJxggaNgCAAAAuAAQKf1MAAg0ACQkgFeQKADoBAA0ACQkgFeQKADoBAAAA.',
Ly='Lyssirix:BAAALgAECgYJCwAAAA==.',
Ma='Macandcheese:BAAALgADCgMJCgAAAA==.Macy:BAABLgAECn8YAAIeAAcJJhO9DAAkAQAeAAcJJhO9DAAkAQAAAA==.Mahiru:BAAALgADCgEJAQAAAA==.Mahralla:BAAALgADCgIJAgAAAA==.Maikagond:BAAALgAECgYJDgABLgAECgkJMwANAKQLAA==.Makaria:BAAALgAECggJEAAAAA==.Malbisa:BAAALgAECgQJBgAAAA==.Malphoz:BAAALgAECgUJBwAAAA==.Mandragora:BAABLgAECn8bAAINAAkJXBJgiQBdAQANAAkJXBJgiQBdAQAAAA==.Maoriofdeath:BAAALgADCgEJAQABLgAECgYJDQAFAAAAAA==.Map:BAAALgAECgIJAwAAAA==.Marli:BAAALgADCgEJAQAAAA==.Mattieatzdot:BAAALgAECgQJBQAAAA==.',
Mc='Mcgrowlin:BAAALgAECgQJCwAAAA==.',
Me='Mekator:BAAALgAECgQJBAAAAA==.Meko:BAAALgAECgUJBwAAAA==.Merrycow:BAAALgAECggJCwAAAA==.Mew:BAAALgAECgIJAwAAAA==.',
Mi='Mickey:BAACLgAFFH8IAAICAAQJJwsEHwDeAAACAAQJJwsEHwDeAAAuAAQKfygAAgIACQkTIlcHANQCAAIACQkTIlcHANQCAAAA.Migraine:BAAALgAECgYJCgAAAA==.Mikiik:BAABLgAECn9CAAIPAAkJzwqaXACIAQAPAAkJzwqaXACIAQAAAA==.Mildoo:BAABLgAECn8sAAIQAAkJBA/2CwCeAQAQAAkJBA/2CwCeAQAAAA==.Milkymoo:BAABLgAECn8iAAIDAAUJfxybHgA/AQADAAUJfxybHgA/AQAAAA==.Millina:BAAALgADCgIJAgABLgAECgkJNwACAGMOAA==.Mimira:BAAALgAECgEJAQAAAA==.Minipal:BAAALgAECgcJEQABLgAECgkJFgABAKcdAA==.Mixednuts:BAACLgAFFH8MAAIJAAQJsSAOIABuAQAJAAQJsSAOIABuAQAuAAQKfycAAwkACQmiIhoEAHIDAAkACQmiIhoEAHIDAAIABgkoIKofANoBAAAA.',
Mo='Mochii:BAAALgADCgYJBgAAAA==.Moneyshock:BAAALgAECgYJBgABLgAFFAQJCwAcAH4XAA==.Monq:BAABLgAECn8YAAMCAAgJBBjAHADIAQACAAgJBBjAHADIAQAdAAEJyAkqjQAqAAAAAA==.Moonamber:BAAALgADCgQJBgAAAA==.Morithus:BAAALgADCgkJDgAAAA==.Morphinzerr:BAAALgAECgEJAQAAAA==.Moón:BAAALgAECgEJAgAAAA==.',
Mu='Murdrmittens:BAAALgADCgEJAQAAAA==.',
My='Mysterychogs:BAAALgAECgEJAQABLgAECgkJLgARAMYbAA==.Mythion:BAABLgAECn8kAAMSAAgJcRpmJQAiAgASAAgJcRpmJQAiAgAVAAQJCQWtawBzAAAAAA==.Mythlocked:BAAALgAECgYJBgAAAA==.Mythoridan:BAAALgAECgEJAQAAAA==.',
Na='Naeres:BAABLgAECn8fAAIhAAgJkBcvcACEAQAhAAgJkBcvcACEAQAAAA==.Nafari:BAAALgAECggJCAAAAA==.Naofummi:BAAALgAECgcJBwAAAA==.Naomii:BAABLgAECn8rAAMUAAkJxxnUFwAPAgAUAAkJxxnUFwAPAgARAAUJZQiXWQCvAAAAAA==.Narus:BAAALgAECgcJCgABLgAECgkJNQAaALAYAA==.Naturefury:BAAALgADCgEJAQAAAA==.',
Ne='Neeston:BAACLgAFFH8HAAISAAMJzBI9PAC+AAASAAMJzBI9PAC+AAAuAAQKfyIAAxIACAkJI5oPANcCABIACAkJI5oPANcCABUAAQllEtyAADAAAAEuAAUUBAkLABwAfhcA.Neodin:BAABLgAECn8jAAIaAAkJlQ+0JgDEAQAaAAkJlQ+0JgDEAQAAAA==.Nephadin:BAAALgADCgUJAwABLgAECgkJKQAlABQiAA==.Nerfed:BAAALgAECgUJCAAAAA==.Neviaa:BAABLgAECn8uAAIhAAkJXRSyQAABAgAhAAkJXRSyQAABAgAAAA==.',
Ni='Nickypoo:BAAALgAECgMJBgAAAA==.Nightmenace:BAAALgAECgcJCwAAAA==.Ninari:BAAALgADCgUJBQAAAA==.Niq:BAAALgAECgQJBAAAAA==.',
No='Nocshadue:BAAALgADCgYJCwAAAA==.Nordga:BAAALgADCgcJBwAAAA==.Nothealster:BAAALgAECgcJEwAAAA==.Nothros:BAAALgADCgQJBAAAAA==.',
Ob='Obitrice:BAAALgAECgcJCAAAAA==.Obsidiian:BAABLgAECn8VAAImAAgJlREnCgCBAQAmAAgJlREnCgCBAQAAAA==.Obsidion:BAABLgAECn8YAAMRAAYJrwzAWwCnAAARAAUJ5gnAWwCnAAAUAAQJDggFVgCEAAABLgAECgkJNQAaALAYAA==.',
Od='Odie:BAAALgAECgYJDwAAAA==.',
On='Onemorehit:BAAALgAECgEJAwAAAA==.Onlyfangs:BAABLgAECn9KAAMWAAkJUxIjDQAAAgAWAAkJUxIjDQAAAgAZAAYJtwX9awCXAAAAAA==.',
Os='Oscrapermort:BAAALgADCgMJAwAAAA==.Ossin:BAAALgAFFAEJAgAAAA==.',
Pa='Padivyn:BAABLgAECn8ZAAIIAAgJzxiQIwDKAQAIAAgJzxiQIwDKAQAAAA==.Padnamprik:BAAALgAECgQJBAAAAA==.Palidenman:BAAALgAECgQJAwAAAA==.',
Pe='Peanads:BAAALgADCgcJEAAAAA==.Pebblez:BAAALgADCgcJDgAAAA==.Perry:BAACLgAFFH8GAAISAAMJcB5zKwAJAQASAAMJcB5zKwAJAQAuAAQKfyoAAxIACQm6Ie8EAGwDABIACQm6Ie8EAGwDABUAAgkBBTuCAEQAAAAA.',
Ph='Phlampped:BAAALgADCgUJBQABLgAFFAgJIAANAJsYAA==.',
Pi='Pinotage:BAAALgAECgcJCgABLgAECgkJNQAhAFEcAA==.',
Po='Po:BAAALgAECgkJCAAAAA==.Pozufuma:BAABLgAECn9GAAIaAAkJHB2ZDAChAgAaAAkJHB2ZDAChAgAAAA==.',
Pr='Priestcraft:BAAALgADCgIJAgABLgAECggJCwAFAAAAAA==.',
Ps='Psychomantis:BAABLgAECn8qAAMRAAkJeRQGHwDNAQARAAkJeRQGHwDNAQAUAAEJwREjEgAwAAAAAA==.',
Pu='Punchypunch:BAAALgADCgkJFAAAAA==.',
Ra='Raek:BAAALgAECgQJBQABLgAECgcJGQAQAPEbAA==.Raith:BAAALgAECgYJCwAAAA==.Ravenbear:BAAALgAECgQJBgABLgAECgkJSgAWAFMSAA==.Ravenbyrd:BAAALgADCgMJAwAAAA==.Rawberriez:BAAALgAECgQJBgAAAA==.',
Re='Reani:BAAALgADCgQJBAAAAA==.Reapin:BAAALgADCgUJBQAAAA==.Redpool:BAABLgAECn8fAAIGAAcJJBGNQACtAQAGAAcJJBGNQACtAQAAAA==.Remithedrood:BAAALgADCgIJAgAAAA==.Reqium:BAAALgADCgYJCAAAAA==.Resto:BAAALgAECgQJBgAAAA==.Rethandra:BAABLgAECn8YAAQGAAgJ9hP9XgCKAQAGAAcJSRX9XgCKAQAnAAMJLxRhHwC0AAAcAAIJ3gc0DAA9AAAAAA==.Retrix:BAAALgAECgIJAwAAAA==.',
Ri='Rion:BAABLgAECn8XAAIeAAkJcxHRYgC5AQAeAAkJcxHRYgC5AQAAAA==.Ristvakbaen:BAACLgAFFH8EAAIPAAIJVRqZkwCbAAAPAAIJVRqZkwCbAAAuAAQKfzoABBAACQnmJEEDAIYCABAACAlGJUEDAIYCAA8ACQm8HbofAGYCAA4ABgk9JRYGAAQCAAAA.',
Ro='Robynlee:BAABLgAECn9LAAIUAAgJXhlUAQBAAgAUAAgJXhlUAQBAAgAAAA==.Roccobb:BAAALgADCgYJBgAAAA==.Rogùe:BAAALgAECgQJBgAAAA==.Rosebelle:BAAALgADCgcJHAAAAA==.',
Ru='Rugratt:BAAALgADCgQJBAABLgADCgcJDgAFAAAAAA==.',
Sa='Saeler:BAAALgAECgMJAwAAAA==.Sailrmoonkin:BAAALgAECgQJBQABLgAECggJMAAKAIEcAA==.Samoth:BAAALgADCgEJAQAAAA==.Sanathein:BAAALgADCgcJBwAAAA==.Sanctuary:BAAALgAECgQJBAAAAA==.Santeclair:BAAALgAECgEJAQAAAA==.Satin:BAAALgAECggJDQAAAA==.',
Sc='Sceryna:BAABLgAECn8oAAINAAkJzBdBSQDqAQANAAkJzBdBSQDqAQAAAA==.Schiftly:BAAALgAFFAIJAgAAAA==.Schwiggity:BAAALgAECgQJCQABLgAECgkJGwANAFwSAA==.Scottlock:BAABLgAECn8WAAIOAAcJqh6QBQAVAgAOAAcJqh6QBQAVAgABLgAECgkJLgAjAAIjAA==.Screwbrew:BAAALgAECgIJAgAAAA==.Screwid:BAAALgAECgQJBAAAAA==.Screwtotems:BAAALgAECgEJAQAAAA==.Scrmndemn:BAABLgAECn80AAINAAkJdAidpAAwAQANAAkJdAidpAAwAQAAAA==.',
Se='Sepviva:BAABLgAECn8VAAIhAAcJNhZmcACoAQAhAAcJNhZmcACoAQAAAA==.Serpent:BAACLgAFFH8OAAIDAAYJ5BS9CgCDAQADAAYJ5BS9CgCDAQAuAAQKfyMAAgMACQlnHxkIAHoCAAMACQlnHxkIAHoCAAEuAAUUBwkkAAoAXxYA.',
Sh='Shadowheal:BAAALgADCgUJBgAAAA==.Shamadeus:BAAALgADCgUJBQABLgAFFAIJBAAPAFUaAA==.Sharaseth:BAAALgAECggJEAAAAA==.Shikita:BAABLgAECn9JAAMSAAkJnB51DQDvAgASAAkJnB51DQDvAgAVAAEJHAZfigAlAAAAAA==.Shimadin:BAACLgAFFH8gAAINAAYJphdmOAA8AQANAAYJphdmOAA8AQAuAAQKfykAAg0ACQkfHvszADACAA0ACQkfHvszADACAAAA.Shimbuktu:BAAALgAECgEJAgABLgAFFAYJIAANAKYXAA==.Shimfu:BAAALgAECgEJAgABLgAFFAYJIAANAKYXAA==.Shimjun:BAAALgAECgUJCwABLgAFFAYJIAANAKYXAA==.Shimpbizkit:BAABLgAECn8ZAAIeAAcJAg0VnwA8AQAeAAcJAg0VnwA8AQABLgAFFAYJIAANAKYXAA==.Shimsong:BAAALgAECgYJEwABLgAFFAYJIAANAKYXAA==.Shmerek:BAABLgAECn8XAAIDAAkJRSBCCAB3AgADAAkJRSBCCAB3AgAAAA==.',
Si='Sidarien:BAAALgADCgQJBAAAAA==.Silenttits:BAAALgAECgEJAgAAAA==.Silverlumen:BAAALgAFFAEJAgAAAA==.Silversaevus:BAAALgAECgYJCQAAAA==.Silverstream:BAACLgAFFH8IAAISAAMJGgqLSQCUAAASAAMJGgqLSQCUAAAuAAQKfyoAAhIACQnoER1CAJkBABIACQnoER1CAJkBAAAA.',
Sk='Skyblue:BAAALgADCgEJAQAAAA==.',
Sl='Slea:BAABLgAECn8VAAIcAAkJQxApFAAEAgAcAAkJQxApFAAEAgAAAA==.',
Sm='Smallrichard:BAAALgAECgEJAQAAAA==.Smootish:BAAALgADCgUJBQAAAA==.',
So='Solbin:BAAALgAECgUJDAABLgAECgkJKQAeAOQYAA==.Solitudé:BAABLgAECn8fAAMPAAgJBiSWHwBnAgAPAAcJPiGWHwBnAgAQAAUJoSW1FAAoAQABLgAFFAUJEwAXAP4fAA==.Soteirian:BAABLgAECn8zAAMNAAkJpAuIcgCJAQANAAkJpAuIcgCJAQAlAAEJjwJKXwASAAAAAA==.',
Sp='Spam:BAAALgAECgIJAgAAAA==.Spekey:BAAALgAECgEJAQAAAA==.Spider:BAABLgAECn81AAIhAAkJURxTGQCuAgAhAAkJURxTGQCuAgAAAA==.Spineymagus:BAAALgADCgIJAgAAAA==.',
Sq='Squall:BAABLgAECn8rAAMiAAgJMhCNRwCQAQAiAAgJMhCNRwCQAQAIAAYJ0ROVRQAdAQAAAA==.',
St='Stalariais:BAAALgAECgQJBAABLgAECgkJGQAbAHoIAA==.Stardrand:BAAALgADCgUJBgAAAA==.Steelreserve:BAAALgAECgYJDQAAAA==.Straw:BAAALgAECgYJCwABLgAECgkJQwANAGgkAA==.',
Su='Sugarkitty:BAAALgADCgYJCgAAAA==.Supereclipse:BAABLgAECn9EAAIGAAkJ/hZDKQA5AgAGAAkJ/hZDKQA5AgAAAA==.',
Sw='Swolareclips:BAAALgADCgYJBgAAAA==.',
Sy='Sydvicious:BAABLgAECn8iAAILAAkJPCVYBAAEAwALAAkJPCVYBAAEAwAAAA==.Syriene:BAABLgAECn8uAAIBAAkJPBByEQCjAQABAAkJPBByEQCjAQABLgAECgkJIAATALsNAA==.',
Ta='Taladiir:BAAALgAECgEJAQAAAA==.Tankhealz:BAAALgAECgMJBQAAAA==.Tanthe:BAAALgAECgMJAwAAAA==.Tayger:BAAALgAECgQJBAAAAA==.',
Tb='Tbsp:BAAALgAECgEJAQABLgAFFAUJFgAJAEocAA==.',
Te='Tecks:BAABLgAECn8XAAIUAAkJwgWfPAABAQAUAAkJwgWfPAABAQAAAA==.Teddy:BAAALgAECgUJCQAAAA==.Teslá:BAAALgAECgYJCgAAAA==.',
Th='Theatrix:BAAALgAECgQJBwABLgAECgcJEgAFAAAAAA==.Thecuckler:BAAALgAECgQJCAAAAA==.Thefreeman:BAAALgAECgEJAQAAAA==.Themajor:BAABLgAECn8uAAMEAAkJFhfmDAAYAgAEAAkJFhfmDAAYAgAaAAcJ/AhwTAB0AQAAAA==.Then:BAAALgADCgEJAQAAAA==.Thiarad:BAAALgADCgEJAQAAAA==.Thiaraxo:BAACLgAFFH8IAAIJAAMJHyHzFADbAAAJAAMJHyHzFADbAAAuAAQKfxUAAgkACQmbBcp5ALAAAAkACQmbBcp5ALAAAAAA.Thrain:BAAALgADCgcJDAAAAA==.Threat:BAABLgAECn8mAAINAAkJlCWXBQBHAwANAAkJlCWXBQBHAwAAAA==.Thronkall:BAAALgAECgkJAQAAAA==.Thsarus:BAABLgAECn8vAAMMAAgJ6yDlHABnAgAMAAgJ6yDlHABnAgAkAAQJHBHQGwCxAAAAAA==.',
Ti='Tiamaat:BAABLgAECn8XAAISAAkJmgQKegDJAAASAAkJmgQKegDJAAAAAA==.Tireyne:BAAALgADCgEJAgAAAA==.Titus:BAAALgAECgEJBgAAAA==.',
Tk='Tkt:BAAALgAECgIJBAABLgAECgUJCQAFAAAAAA==.',
To='Toatani:BAAALgAECgYJDQAAAA==.Tokkaebi:BAAALgAECgkJCwAAAA==.',
Tr='Treadlightly:BAAALgADCgUJBwAAAA==.Treefróg:BAAALgAECgUJBQAAAA==.Trentus:BAAALgADCgIJAgAAAA==.Trev:BAAALgAECgUJBgABLgAFFAUJBQAPAIUWAA==.Trotem:BAAALgAECgUJBQAAAA==.',
Ts='Tsp:BAACLgAFFH8WAAIJAAUJShwOHACSAQAJAAUJShwOHACSAQAuAAQKfywAAwkACQn/Gd8cADECAAkACQn/Gd8cADECAB0ABAnxA0psAJEAAAAA.',
Ty='Tyletos:BAABLgAECn8pAAIeAAkJ5BiFCABqAQAeAAkJ5BiFCABqAQAAAA==.Tyravia:BAAALgAECgYJBgABLgAECgkJIAATALsNAA==.',
Ug='Ugolok:BAABLgAECn8pAAMXAAcJ7gdWBgB9AAAXAAYJzQhWBgB9AAAhAAcJKQVqHQB1AAAAAA==.',
Ur='Uriél:BAABLgAECn8yAAIMAAkJNSWeAgBeAwAMAAkJNSWeAgBeAwABLgAFFAUJEwAXAP4fAA==.',
Va='Valeene:BAABLgAECn8uAAIVAAkJLiJSBAAcAwAVAAkJLiJSBAAcAwAAAA==.Valkion:BAAALgAECgEJAQAAAA==.Varek:BAABLgAECn8XAAITAAkJ5yEyAwAbAwATAAkJ5yEyAwAbAwAAAA==.',
Ve='Veiler:BAABLgAECn9GAAMGAAkJEROKNgADAgAGAAkJEROKNgADAgAnAAEJ3wH2lgAhAAAAAA==.Velca:BAAALgAECgIJAgAAAA==.Veruca:BAAALgAECgMJAwAAAA==.Veviseron:BAABLgAECn8qAAIeAAkJNwSvpgAwAQAeAAkJNwSvpgAwAQAAAA==.',
Vh='Vhye:BAABLgAFFH8IAAIiAAMJtgbmLwBbAAAiAAMJtgbmLwBbAAAAAA==.',
Vi='Vidnoi:BAAALgAECgEJBAAAAA==.Vinstalation:BAABLgAECn81AAIXAAkJcRwxBgBHAgAXAAkJcRwxBgBHAgAAAA==.Vissa:BAAALgADCgYJBgAAAA==.',
Vo='Vonbismarck:BAABLgAECn8lAAMGAAkJ8hOSTQC5AQAGAAkJ8hOSTQC5AQAnAAEJFw/9BwAwAAAAAA==.',
Vr='Vritraz:BAACLgAFFH8TAAMXAAUJ/h9wCABnAQAXAAQJ/h9wCABnAQAhAAEJAACtLQEAAAAuAAQKfxUAAxcACQmLIqEGADkCABcABwk+I6EGADkCACEAAgl0IAP3ALcAAAAA.Vrock:BAAALgAECgEJAQABLgAECgkJKwAeAHIeAA==.',
Wa='Warnam:BAAALgADCgcJBwAAAA==.Warsonge:BAAALgADCgMJAwAAAA==.',
We='Wendypini:BAACLgAFFH8TAAIGAAQJDQaKUwACAQAGAAQJDQaKUwACAQAuAAQKfyIAAgYACQkAEF5FAJsBAAYACQkAEF5FAJsBAAAA.Wetnwild:BAAALgADCgQJBAAAAA==.',
Wh='Whitehand:BAAALgAECgIJAgAAAA==.',
Wo='Wooshwoosh:BAAALgAECgQJDgAAAA==.',
Wu='Wudeeps:BAAALgAECgcJEgAAAA==.Wuhanwarrior:BAAALgAECgYJEQAAAA==.',
Xe='Xendria:BAAALgAECgEJAgAAAA==.',
Ya='Yako:BAAALgAECgEJAQAAAA==.',
Ye='Yennefer:BAAALgAECgMJAwAAAA==.',
Yo='Yongary:BAAALgAECgkJCQAAAA==.',
Za='Zangolf:BAAALgADCgUJBAAAAA==.Zaros:BAAALgAECgUJBQAAAA==.Zaye:BAAALgAECggJDAAAAA==.',
Ze='Zearas:BAABLgAECn8UAAIhAAgJJxE+kwBZAQAhAAgJJxE+kwBZAQAAAA==.Zendonn:BAABLgAECn8bAAICAAcJxwUiUgDAAAACAAcJxwUiUgDAAAAAAA==.Zerk:BAAALgAECgEJAQAAAA==.',
Zi='Zicatriz:BAAALgADCgcJDgAAAA==.',
Zo='Zodiaac:BAABLgAECn8XAAIKAAkJdxm1FQC+AQAKAAkJdxm1FQC+AQAAAA==.',
Zu='Zuggy:BAAALgAECgQJBAABLgAFFAQJCwAcAH4XAA==.',
Zy='Zy:BAAALgADCgUJBQAAAA==.',
['Zà']='Zàknafein:BAAALgAECgYJEQAAAA==.',
['Ëc']='Ëchõ:BAABLgAECn8gAAMSAAkJ+RXSNwDIAQASAAkJ+RXSNwDIAQAVAAIJvwRldwBHAAAAAA==.',
['Ðï']='Ðï:BAAALgADCgQJBAABLgAECgkJKgARABgcAA==.',
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
