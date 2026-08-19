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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Unknown-Unknown','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Evoker-Augmentation','Hunter-BeastMastery','Priest-Discipline','Shaman-Elemental','Monk-Mistweaver','Priest-Holy','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Druid-Restoration','Rogue-Subtlety','Druid-Balance','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Paladin-Holy','Hunter-Survival','Monk-Brewmaster','Mage-Frost','Druid-Guardian','Rogue-Assassination','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Protection','Rogue-Outlaw','Hunter-Marksmanship',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=46,date='2026-08-18',data={Ab='Abominable:BAAALgADCgEJAQAAAA==.',
Ad='Addo:BAAALgAECgMJAwABLgAECgkJQwABALodAA==.',
Ae='Aelaster:BAAALgADCgYJBgAAAA==.',
Ag='Agden:BAAALgADCgEJAQAAAA==.',
Al='Alaìrn:BAAALgAECgUJCwABLgAECgkJFgACAKcdAA==.Aldrich:BAAALgAECgYJBwAAAA==.Alenciann:BAAALgAECgMJBwAAAA==.Allayna:BAAALgAECgEJAQABLgAECgEJAwADAAAAAA==.Alstre:BAAALgAECgEJAQAAAA==.Alys:BAABLgAECn86AAIEAAkJYw4IIgCfAQAEAAkJYw4IIgCfAQAAAA==.',
Am='Amaniatres:BAABLgAECn8pAAMFAAgJqhMVBAB7AQAFAAgJGhMVBAB7AQAGAAQJEw8XSwChAAABLgAECgkJHgAHANsYAA==.Ammartin:BAABLgAECn8YAAIIAAkJyQo1bQBnAQAIAAkJyQo1bQBnAQAAAA==.Amoonranara:BAAALgADCgEJAQAAAA==.',
An='Anaan:BAAALgAECgUJBgAAAA==.Anahera:BAAALgAECgEJAQABLgAECgYJDgADAAAAAA==.Anakha:BAAALgADCggJCAABLgAECgUJBgADAAAAAA==.Anfna:BAAALgAECgEJAgAAAA==.Angrylizard:BAAALgAECgEJAgAAAA==.Anklebiterr:BAAALgAECgUJBwAAAA==.',
Ap='Apothecary:BAAALgADCgcJBwAAAA==.',
Ar='Arabella:BAAALgAECggJEQAAAA==.Arandomidiot:BAAALgADCgYJBgAAAA==.Arathan:BAAALgADCgkJHAAAAA==.Arihana:BAAALgAECgYJEAAAAA==.Ariiana:BAABLgAECn8XAAIJAAkJIx7rBgAOAwAJAAkJIx7rBgAOAwAAAA==.Arngal:BAAALgAECgEJAQAAAA==.',
As='Asapshocky:BAACLgAFFH8bAAIKAAgJRBlKBwACAgAKAAgJRBlKBwACAgAuAAQKfzAAAgoACQmgJBIFAA0DAAoACQmgJBIFAA0DAAAA.Asclepios:BAAALgAECgMJBAAAAA==.Asmoday:BAAALgAECgYJBgAAAA==.Astraroth:BAAALgADCgcJCgAAAA==.',
Av='Avella:BAAALgADCgUJBwAAAA==.',
Ba='Balaris:BAAALgADCgcJBwABLgAECgkJIwALACEUAA==.Balum:BAAALgAECgEJAQAAAA==.Bamwham:BAAALgADCgcJBwAAAA==.Barrii:BAAALgAECgMJBQAAAA==.',
Be='Bearblaster:BAAALgADCgQJBAABLgAECgQJBgADAAAAAA==.Bearlytanks:BAAALgADCgIJAgAAAA==.Beastwallker:BAAALgADCgUJBgAAAA==.Bellabelle:BAABLgAECn8XAAIMAAgJ+gn+CQAQAQAMAAgJ+gn+CQAQAQAAAA==.Bellgerra:BAAALgAECgEJAQAAAA==.Ben:BAAALgAECgcJEwAAAA==.Betamaxx:BAACLgAFFH8HAAMNAAMJuBH5LwCDAAANAAIJThb5LwCDAAAOAAIJAwhSFQB1AAAuAAQKfxUAAg0ABwmCHYgSAOYBAA0ABwmCHYgSAOYBAAAA.Betterx:BAAALgAECgQJBQAAAA==.Bevian:BAAALgAECgEJAQABLgAECgkJDgADAAAAAA==.',
Bi='Biggiepants:BAABLgAECn8iAAMPAAkJ0h9oBwC7AgAPAAkJ0h9oBwC7AgAQAAgJ9w6fYABoAQAAAA==.Bighead:BAAALgAECgYJCAABLgAFFAMJBwAEALYHAA==.Bigwarlocks:BAAALgAECgMJBwABLgAFFAMJBwAEALYHAA==.Bintje:BAAALgADCgcJEgAAAA==.Biollante:BAAALgAECgcJCwAAAA==.',
Bl='Blindedlïght:BAAALgAECgUJBgAAAA==.',
Bo='Bolsan:BAAALgAECgMJBQAAAA==.Bonq:BAAALgAECgIJAgABLgAECgkJEQAPACUcAA==.Bourg:BAAALgAECgYJCAAAAA==.Bowhemian:BAAALgAECgMJBgAAAA==.',
Bu='Bubbahubba:BAAALgAECgEJAQAAAA==.Buckis:BAABLgAECn8kAAIRAAkJERjiBwAGAgARAAkJERjiBwAGAgAAAA==.Bufú:BAAALgADCgIJAgAAAA==.',
['Bö']='Böurbon:BAAALgADCgkJCgAAAA==.',
Ca='Caelia:BAAALgADCgEJAQAAAA==.Cahk:BAAALgAECgMJAwAAAA==.Cajia:BAABLgAECn8uAAMSAAkJ4wo8HQC+AAATAAkJgwndfgA7AQASAAYJBgs8HQC+AAAAAA==.',
Ce='Celds:BAAALgADCgQJBAABLgAECgcJGQAUAPEbAA==.Celiae:BAAALgAECgYJEAAAAA==.Cendanel:BAAALgAECgIJAgAAAA==.',
Ch='Childress:BAAALgAECgMJAwAAAA==.Chiwhiz:BAAALgAECgEJAQABLgAECgQJCwADAAAAAA==.Choggy:BAABLgAECn8uAAIVAAkJxhvnDgBqAgAVAAkJxhvnDgBqAgAAAA==.Chogs:BAAALgAECgMJBAABLgAECgkJLgAVAMYbAA==.Chuec:BAAALgAECgEJAQAAAA==.',
Ci='Cimbline:BAAALgADCgIJAgAAAA==.',
Cl='Clairerick:BAAALgAECgYJEAAAAA==.Clenise:BAAALgAECgEJAQAAAA==.',
Co='Cokebear:BAAALgAECgMJAwABLgAECggJJAAWAHEaAA==.Composer:BAABLgAECn8eAAIHAAkJ2xi0AQA5AgAHAAkJ2xi0AQA5AgAAAA==.Conception:BAAALgAECgUJBgABLgAECgkJUgAMAKUaAA==.Confessionn:BAAALgADCggJDAAAAA==.Cough:BAAALgAECgUJCwABLgAFFAMJBwAEALYHAA==.',
Cr='Crinklecut:BAABLgAECn8ZAAIXAAgJQQwKJQBtAQAXAAgJQQwKJQBtAQAAAA==.Critos:BAAALgADCgcJBwAAAA==.Crotchout:BAAALgADCgMJAwAAAA==.Crybaby:BAAALgADCgEJAQAAAA==.Crystilpixy:BAAALgADCgMJBAAAAA==.',
['Cé']='Céline:BAAALgAECgEJAQAAAA==.',
Da='Dalal:BAAALgAECgUJCAABLgAECgkJUgAMAKUaAA==.Danielallen:BAAALgAFFAMJBAAAAA==.Danilov:BAAALgADCgYJBgAAAA==.',
De='Deadlyshift:BAABLgAECn8XAAMWAAkJsCKWBQBeAwAWAAkJsCKWBQBeAwAYAAUJMho8NgBjAQAAAA==.Deadmenace:BAAALgAECgEJAQAAAA==.Deadybear:BAAALgADCgkJEAABLgAECgkJSgAZAFMSAA==.Deathkyter:BAAALgAECgEJAQAAAA==.Delrok:BAAALgAECgEJAgAAAA==.Demonicblade:BAAALgADCggJCAAAAA==.Dephias:BAAALgADCgMJAwAAAA==.',
Di='Diagnosis:BAABLgAECn8eAAIRAAkJhSVqCwAKAwARAAkJhSVqCwAKAwAAAA==.',
Do='Donnabb:BAABLgAECn8YAAIRAAgJCQXGOAB0AAARAAgJCQXGOAB0AAAAAA==.Donteatbees:BAABLgAECn8UAAIOAAkJZgquGAAPAQAOAAkJZgquGAAPAQAAAA==.Dop:BAAALgAECgEJAwAAAA==.Doran:BAABLgAECn8eAAIPAAgJaRcHFwDNAQAPAAgJaRcHFwDNAQAAAA==.Doriathrin:BAAALgADCgcJCwAAAA==.Doujinshi:BAABLgAECn8OAAIQAAcJIBziUwCoAQAQAAcJIBziUwCoAQAAAA==.',
Dr='Dragonbladez:BAAALgADCgUJBQAAAA==.Dragoneye:BAAALgAECgMJBgAAAA==.Dragonhawk:BAAALgADCgQJBAABLgAECgMJEgADAAAAAA==.Dragonname:BAAALgAECgEJAQAAAA==.Drakoil:BAABLgAECn87AAMaAAkJwBi7BAAkAgAaAAkJJRi7BAAkAgAHAAcJNxMiNQBdAQAAAA==.Dreademperor:BAACLgAFFH8JAAIFAAQJdBUnGgDGAAAFAAQJdBUnGgDGAAAuAAQKfycAAwUACQkhHvAEAPYCAAUACQkhHvAEAPYCABsABAlDDwliAM8AAAEuAAUUBQkMAA0AJR8A.Dreadnature:BAAALgAECgMJAwAAAA==.Dreadnight:BAABLgAFFH8MAAINAAUJJR8NFwAwAQANAAUJJR8NFwAwAQAAAA==.Dreadsteed:BAAALgAECgEJAQABLgAFFAUJDAANACUfAA==.Dreadweaver:BAAALgADCgUJBQABLgAFFAUJDAANACUfAA==.Drenrah:BAABLgAECn8pAAIcAAkJug+lKwC0AQAcAAkJug+lKwC0AQAAAA==.Drgndeeznutz:BAACLgAFFH8QAAIdAAQJYR4HCAAZAQAdAAQJYR4HCAAZAQAuAAQKfygAAh0ACQnPHykFANYCAB0ACQnPHykFANYCAAAA.Drunkenrage:BAACLgAFFH8pAAIeAAkJhhxbBABbAgAeAAkJhhxbBABbAgAuAAQKfx4AAh4ACQkcIvsBAIIDAB4ACQkcIvsBAIIDAAAA.',
Du='Dumorius:BAAALgAECgYJCAAAAA==.',
['Dé']='Déx:BAAALgAECgYJCwAAAA==.',
Ed='Edgemenace:BAAALgADCgQJBAAAAA==.Edreth:BAAALgAECgEJAQAAAA==.',
El='Elbryan:BAABLgAECn8xAAIVAAkJhAinMABbAQAVAAkJhAinMABbAQAAAA==.Elementdemon:BAAALgAFFAEJAQAAAA==.Ellabelle:BAAALgADCgMJAwAAAA==.',
En='Enthalpy:BAABLgAECn8vAAIfAAkJch6IGwC2AgAfAAkJch6IGwC2AgAAAA==.',
Ep='Epipin:BAAALgAECgUJCAAAAA==.',
Er='Erakazsod:BAAALgAECgEJAQABLgAFFAQJEAAdAGEeAA==.Erazath:BAAALgAECgUJCAABLgAECgkJEAADAAAAAA==.',
Es='Esperzoa:BAACLgAFFH8GAAINAAMJFRVCFAC/AAANAAMJFRVCFAC/AAAuAAQKfzIAAg0ACQmRG30NADICAA0ACQmRG30NADICAAAA.',
Et='Eternaldread:BAAALgADCgUJBQABLgAFFAUJDAANACUfAA==.',
Eu='Eucalicdes:BAABLgAECn9CAAIgAAkJvhfFDQAGAgAgAAkJvhfFDQAGAgAAAA==.',
Ez='Ezal:BAAALgAECgYJCAAAAA==.Ezra:BAAALgAECgUJBQAAAA==.',
Fa='Fallyn:BAAALgAECgEJAQAAAA==.Fancy:BAAALgADCgUJBQAAAA==.Farshran:BAAALgAECgkJEAAAAA==.Fate:BAAALgAECgQJBQABLgAECgkJJgARAJQlAA==.Fathermajor:BAAALgAECgQJBAAAAA==.',
Fe='Felicity:BAACLgAFFH8WAAIXAAUJ2h0THAA6AQAXAAUJ2h0THAA6AQAuAAQKfzYAAxcACQmWIpIEAE4DABcACQmWIpIEAE4DACEABQmDDb8VANEAAAAA.Ferendis:BAABLgAECn8nAAIQAAgJPiOiEwCmAgAQAAgJPiOiEwCmAgAAAA==.Fernard:BAAALgADCgYJBgABLgAECgkJEQAPACUcAA==.',
Fl='Flokii:BAAALgAECgQJBQAAAA==.Florita:BAABLgAECn8VAAIIAAkJmgo+EwBOAQAIAAkJmgo+EwBOAQAAAA==.Flydormu:BAAALgAECgYJDAABLgAECgkJMAAfAIYZAA==.',
Fo='Fordinn:BAABLgAECn81AAMbAAkJsBiRGwARAgAbAAkJZRaRGwARAgAFAAcJeRUOGwBgAQAAAA==.',
Fr='Fractured:BAAALgADCgEJAQAAAA==.Freelor:BAAALgAECgIJBAAAAA==.Freemi:BAAALgAECgEJAQAAAA==.Frenzy:BAAALgAECgkJAQAAAA==.Frigidgrip:BAAALgAECgMJAwAAAA==.',
Fu='Fuddytwo:BAABLgAECn8wAAIYAAkJKR0hAwAXAgAYAAkJKR0hAwAXAgAAAA==.Furrypaw:BAAALgAECgcJBwABLgAFFAUJCgALAMIPAA==.Furrypunch:BAABLgAFFH8KAAMLAAUJwg9bGAAOAQALAAUJwg9bGAAOAQAEAAIJPg3CFQB8AAAAAA==.',
Ga='Garzhvog:BAAALgADCgcJCwABLgAFFAIJBAATAFUaAA==.Gasket:BAACLgAFFH8bAAMOAAUJRhpKDgAnAQABAAUJ/BcQXgA4AQAOAAUJ3hNKDgAnAQAuAAQKfyUAAwEACQlnIsMiALQCAAEACQlvIcMiALQCAA4AAwkcIEUZAAoBAAAA.Gauteng:BAAALgAECgIJAgABLgAFFAYJGwARAHAfAA==.',
Gh='Ghidõráh:BAAALgAECgEJAQAAAA==.Ghorac:BAAALgADCgYJDAAAAA==.Ghoti:BAAALgADCgUJBQAAAA==.Ghoulz:BAAALgADCgcJDAAAAA==.',
Gl='Glazedham:BAAALgADCgMJAwAAAA==.',
Gn='Gnollfang:BAAALgADCgYJBgAAAA==.',
Go='Gorbubbli:BAAALgADCgkJGgAAAA==.',
Gr='Graceful:BAAALgAECgUJBgAAAA==.Griffith:BAAALgAECgEJAQAAAA==.Grit:BAAALgAECgYJDAAAAA==.',
Gu='Guidosarduci:BAAALgADCgEJAQAAAA==.Guilddrama:BAAALgADCgEJAQAAAA==.',
Ha='Haeler:BAAALgAECgIJAwAAAA==.Haelin:BAAALgADCgEJAQAAAA==.Halgoðfulk:BAAALgAECgEJAQAAAA==.Hamwarrior:BAAALgAECgEJAQAAAA==.Handicap:BAAALgAECggJEAABLgAECgkJHgARAIUlAA==.Hark:BAACLgAFFH8cAAIIAAYJ5g6oRQAiAQAIAAYJ5g6oRQAiAQAuAAQKfywAAggACQmOG7RQALABAAgACQmOG7RQALABAAAA.Harpin:BAAALgAECgEJAQAAAA==.Harvin:BAABLgAECn80AAIZAAkJgCL0AQBlAwAZAAkJgCL0AQBlAwAAAA==.',
He='Heisenburgg:BAAALgAECgkJCQAAAA==.Hekus:BAEALgAECgcJEQAAAA==.Helanua:BAABLgAECn8rAAIKAAkJQhEQJwCzAQAKAAkJQhEQJwCzAQAAAA==.Hellsplay:BAAALgADCgIJAgAAAA==.',
Hi='Hibernate:BAAALgADCgEJAQAAAA==.Hippolytus:BAAALgADCgkJCQABLgAECgkJLgAeAPQkAA==.Hippopotamus:BAAALgAECgMJAwAAAA==.Hit:BAAALgAECgYJCwABLgAECgkJCQADAAAAAA==.',
Ho='Holytide:BAABLgAECn82AAMKAAkJ9w4ZQwAnAQAKAAgJqgwZQwAnAQAiAAkJsgydEgAQAQAAAA==.Hope:BAABLgAECn8wAAIYAAgJbww4OQAuAQAYAAgJbww4OQAuAQAAAA==.Horrorfang:BAABLgAECn9PAAIBAAkJUiHxCwANAwABAAkJUiHxCwANAwAAAA==.',
Hu='Hukjo:BAAALgAECgcJEgABLgAECgkJIwALACEUAA==.',
Ib='Ibaar:BAACLgAFFH8YAAIHAAcJFSLYHgBpAQAHAAcJFSLYHgBpAQAuAAQKfy8AAwcACQlJJE0HAAUDAAcACAnAI00HAAUDABoABgneIAcNAAoCAAAA.',
Ic='Icepickle:BAAALgADCgcJAQAAAA==.Icialiaa:BAAALgAECggJEAABLgAECgkJLgACADwQAA==.',
Ii='Iilnut:BAABLgAECn8gAAMVAAgJnCA/CwDPAgAVAAgJnCA/CwDPAgAJAAQJPBW2NwDpAAABLgAFFAQJDAALALEgAA==.',
Il='Illedren:BAABLgAECn8QAAIQAAgJwwc7kAAAAQAQAAgJwwc7kAAAAQAAAA==.',
In='Innerdemon:BAAALgAECgQJBAAAAA==.Inno:BAABLgAECn8YAAIQAAkJDiTxEwDhAgAQAAkJDiTxEwDhAgAAAA==.',
Ir='Irraedorine:BAABLgAECn8gAAMXAAkJvwsGCAD+AAAXAAkJvwsGCAD+AAAhAAgJCwScEwDuAAABLgAECgkJLgACADwQAA==.',
Is='Isabel:BAAALgAECgcJDQABLgAECgkJFwAIAJAVAA==.',
It='Ithacus:BAABLgAECn8pAAIjAAkJtBGcEQCaAQAjAAkJtBGcEQCaAQAAAA==.',
Ja='Jandaar:BAAALgAECgEJAQAAAA==.Jatt:BAAALgAECgMJCAAAAA==.Jattao:BAAALgADCgEJAQAAAA==.Jattex:BAAALgAECgEJAgAAAA==.Jattix:BAAALgAECgIJBQAAAA==.',
Jd='Jdawgprime:BAAALgADCgcJBwAAAA==.',
Je='Jenjas:BAAALgAECgUJBQAAAA==.',
Ji='Jinnlee:BAAALgAECgYJBwAAAA==.Jinoo:BAABLgAECn9CAAIKAAkJhhswDwB9AgAKAAkJhhswDwB9AgAAAA==.Jinufan:BAAALgAECgUJBwABLgAFFAcJGAAHABUiAA==.',
Jo='Jodyhusky:BAAALgADCgYJBgAAAA==.Joe:BAAALgAECgcJCgAAAA==.Jorek:BAABLgAECn8WAAIbAAkJ7BT0KAC2AQAbAAkJ7BT0KAC2AQAAAA==.',
Ju='Jugulator:BAAALgADCgcJDQAAAA==.',
Ka='Kaejung:BAAALgAECgUJBgAAAA==.Kainairobi:BAAALgAECgUJCQAAAA==.Kaiva:BAAALgAECgQJBgABLgAECgYJDgADAAAAAA==.Kallistô:BAAALgADCgYJBgAAAA==.Kamigawa:BAABLgAECn8VAAIbAAgJqwt/PABTAQAbAAgJqwt/PABTAQAAAA==.Kavik:BAABLgAECn8fAAIcAAkJHhlKEQCKAgAcAAkJHhlKEQCKAgAAAA==.Kazbodan:BAAALgADCgkJFQAAAA==.',
Ke='Keemo:BAACLgAFFH8cAAINAAYJjRRTHwDsAAANAAYJjRRTHwDsAAAuAAQKfykAAw0ACQnJFachAEUBAA0ACQmpFachAEUBAAEAAwmYDUX8AIMAAAAA.Keemosaki:BAAALgAFFAEJAwAAAA==.Keemõ:BAABLgAECn8XAAMQAAYJvw1QnwDkAAAQAAYJ0wxQnwDkAAAkAAYJownQIACXAAAAAA==.Keemøsabi:BAAALgAFFAEJAgAAAA==.Keflá:BAAALgAECgYJEgAAAA==.Keineliebe:BAAALgADCgcJBwAAAA==.Keysersöze:BAAALgADCgYJBwAAAA==.',
Kh='Khaas:BAABLgAECn9QAAIBAAkJuQ9CTgDYAQABAAkJuQ9CTgDYAQAAAA==.Khaleeb:BAAALgAECgEJAwAAAA==.Kheleze:BAAALgADCggJCAABLgAECgYJEgADAAAAAA==.',
Ki='Kierios:BAABLgAECn8oAAMOAAkJiRbCCAD+AQAOAAkJTxPCCAD+AQABAAgJ3RDmawCOAQAAAA==.Kildurgan:BAAALgAECgQJDQAAAA==.Killawarlock:BAABLgAECn8hAAQTAAgJzCKLPgDiAQATAAcJNSCLPgDiAQAUAAQJbCIsFAAuAQASAAEJ/hAbcAA2AAAAAA==.Kironn:BAAALgADCgYJBgABLgAFFAMJBwAEALYHAA==.',
Kk='Kkain:BAAALgAECgIJBwAAAA==.',
Ko='Korihor:BAABLgAECn8pAAIlAAkJ6B1fCQA7AgAlAAkJ6B1fCQA7AgAAAA==.',
Kr='Krestus:BAABLgAECn8RAAMPAAcJJRyxQACzAAAQAAYJrxkZfgAvAQAPAAMJKSCxQACzAAAAAA==.Krispy:BAABLgAECn87AAQEAAkJHxbJFAAUAgAEAAkJEhbJFAAUAgAeAAcJ2Q4VOAAcAQALAAUJvgO5TgCZAAAAAA==.Krith:BAAALgADCgYJCQAAAA==.Krix:BAAALgAECgMJBAAAAA==.',
Ky='Kyndil:BAAALgAECgcJEQAAAA==.',
La='Laerin:BAABLgAECn8UAAIcAAkJZBSxLACtAQAcAAkJZBSxLACtAQAAAA==.Laxus:BAAALgAECgMJAwABLgAECgkJHwAZAJMSAA==.Lazarius:BAAALgADCgQJBAAAAA==.',
Le='Leafblade:BAAALgAECgkJDgAAAA==.Levophed:BAABLgAECn8xAAIBAAkJhQ+BrAAZAQABAAkJhQ+BrAAZAQAAAA==.Lexor:BAAALgAECgMJAwAAAA==.',
Li='Liangwei:BAAALgAECgMJAwABLgAFFAMJBwAIAPMdAA==.Lightfallen:BAAALgAECgcJEQAAAA==.Lightseeker:BAAALgAECgEJAQABLgAECgkJHwAZAJMSAA==.Liisara:BAABLgAECn8bAAIQAAgJZggzigAMAQAQAAgJZggzigAMAQAAAA==.Lily:BAABLgAECn88AAIgAAkJHRu1DAAWAgAgAAkJHRu1DAAWAgAAAA==.Linadra:BAABLgAECn8uAAIRAAkJgwmikQBPAQARAAkJgwmikQBPAQAAAA==.Linnt:BAAALgAECgQJBwAAAA==.Linzur:BAAALgAECgEJAQAAAA==.Littleyeti:BAAALgAECgMJAwAAAA==.Liyara:BAACLgAFFH8bAAIRAAYJcB82IACGAQARAAYJcB82IACGAQAuAAQKfykAAhEACQm1JUgRAAYDABEACQm1JUgRAAYDAAAA.',
Ll='Llorsa:BAABLgAECn9FAAMMAAkJZhfiEQBQAgAMAAkJZhfiEQBQAgAVAAUJdA1aUADPAAAAAA==.',
Lo='Lohhan:BAAALgADCgUJCQAAAA==.Lolamontez:BAAALgAECgIJAgAAAA==.Lorachka:BAAALgADCgIJAgAAAA==.Lorthys:BAAALgADCgEJAQAAAA==.',
Lu='Luxian:BAACLgAFFH8JAAIRAAIJxghZTwB1AAARAAIJxghZTwB1AAAuAAQKf1MAAhEACQkgFR1LAOUBABEACQkgFR1LAOUBAAAA.',
Ly='Lyssirix:BAABLgAECn8eAAIKAAcJdBZgBgCMAQAKAAcJdBZgBgCMAQAAAA==.',
['Lä']='Ländrei:BAABLgAECn8lAAIIAAkJ4A+KdQBUAQAIAAkJ4A+KdQBUAQABLgAECgkJJQAIAOAPAA==.',
Ma='Macandcheese:BAAALgAECgMJBwAAAA==.Macy:BAABLgAECn8YAAIfAAcJJhPNGAAUAQAfAAcJJhPNGAAUAQAAAA==.Mahiru:BAAALgADCgEJAQAAAA==.Mahralla:BAAALgADCgIJAgAAAA==.Maikagond:BAAALgAECgYJDgABLgAECgkJMwARAKQLAA==.Makaria:BAAALgAECggJEAAAAA==.Malbisa:BAAALgAECgQJBgAAAA==.Malphoz:BAAALgAECgUJBwAAAA==.Mandragora:BAABLgAECn8bAAIRAAkJXBJgiQBdAQARAAkJXBJgiQBdAQAAAA==.Maoriofdeath:BAAALgADCgEJAQABLgAECgYJDgADAAAAAA==.Map:BAAALgAECgIJAwAAAA==.Marli:BAAALgADCgEJAQAAAA==.Mattieatzdot:BAAALgAECgQJBQAAAA==.',
Mc='Mcgrowlin:BAAALgAECgQJCwAAAA==.',
Me='Mekator:BAAALgAECgQJBAAAAA==.Meko:BAAALgAECgUJBwAAAA==.Merrycow:BAAALgAECggJCwAAAA==.Mew:BAAALgAECgIJAwABLgAFFAEJAgADAAAAAA==.',
Mi='Mickey:BAACLgAFFH8IAAIEAAQJJwsEHwDeAAAEAAQJJwsEHwDeAAAuAAQKfygAAgQACQkTIlcHANQCAAQACQkTIlcHANQCAAAA.Migraine:BAAALgAECgYJCgAAAA==.Mikiik:BAABLgAECn9GAAITAAkJzwqaXACIAQATAAkJzwqaXACIAQAAAA==.Mildoo:BAABLgAECn8sAAIUAAkJBA/2CwCeAQAUAAkJBA/2CwCeAQAAAA==.Milkymoo:BAABLgAECn8iAAIFAAUJfxybHgA/AQAFAAUJfxybHgA/AQABLgAFFAkJOAAMAOUXAA==.Millina:BAAALgADCgIJAgABLgAECgkJOgAEAGMOAA==.Mimira:BAAALgAECgEJAQAAAA==.Minipal:BAAALgAECgcJEQABLgAECgkJFgACAKcdAA==.Mixednuts:BAACLgAFFH8MAAILAAQJsSAOIABuAQALAAQJsSAOIABuAQAuAAQKfycAAwsACQmiIhoEAHIDAAsACQmiIhoEAHIDAAQABgkoIKofANoBAAAA.',
Mo='Mochii:BAAALgADCgYJBgAAAA==.Moneyshock:BAAALgAECgYJBgABLgAFFAQJEAAdAGEeAA==.Monq:BAABLgAECn8YAAMEAAgJBBjAHADIAQAEAAgJBBjAHADIAQAeAAEJyAkqjQAqAAAAAA==.Moonamber:BAAALgADCgQJBgAAAA==.Morphinzerr:BAAALgAECgEJAQAAAA==.Moón:BAAALgAECgEJAwAAAA==.',
Mu='Murdrmittens:BAAALgAECgEJAQAAAA==.',
My='Mysterychogs:BAAALgAECgEJAQABLgAECgkJLgAVAMYbAA==.Mythion:BAABLgAECn8kAAMWAAgJcRpmJQAiAgAWAAgJcRpmJQAiAgAYAAQJCQWtawBzAAAAAA==.Mythlocked:BAAALgAECgYJBgAAAA==.Mythoridan:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîlk:BAABLgAFFH8HAAIPAAUJagvWDwC4AAAPAAUJagvWDwC4AAAAAA==.',
Na='Naeres:BAABLgAECn8fAAIBAAgJkBcvcACEAQABAAgJkBcvcACEAQAAAA==.Nafari:BAAALgAECggJCAAAAA==.Naofummi:BAAALgAECgcJBwAAAA==.Naomii:BAABLgAECn8rAAMMAAkJxxnUFwAPAgAMAAkJxxnUFwAPAgAVAAUJZQiXWQCvAAAAAA==.Narus:BAAALgAECgcJCgABLgAECgkJNQAbALAYAA==.Naturefury:BAAALgADCgEJAQAAAA==.',
Ne='Neeston:BAACLgAFFH8HAAIWAAMJzBI9PAC+AAAWAAMJzBI9PAC+AAAuAAQKfyIAAxYACAkJI5oPANcCABYACAkJI5oPANcCABgAAQllEtyAADAAAAEuAAUUBAkQAB0AYR4A.Neodin:BAABLgAECn8jAAIbAAkJlQ+0JgDEAQAbAAkJlQ+0JgDEAQAAAA==.Neoresto:BAAALgAECgMJAwAAAA==.Nephadin:BAAALgADCgUJAwABLgAECgkJKQAlABQiAA==.Nerfed:BAAALgAECgUJCAAAAA==.Neviaa:BAABLgAECn8uAAIBAAkJXRSyQAABAgABAAkJXRSyQAABAgAAAA==.',
Ni='Nickypoo:BAAALgAECgMJBgAAAA==.Nightmenace:BAAALgAECgcJCwAAAA==.Ninari:BAAALgADCgUJBQAAAA==.Niq:BAAALgAECgQJBAAAAA==.',
No='Nocshadue:BAAALgADCgYJCwAAAA==.Nordga:BAAALgADCgcJBwAAAA==.Norii:BAAALgADCgIJAgABLgAECgkJDgADAAAAAA==.Nothealster:BAAALgAECgcJEwAAAA==.Nothros:BAAALgADCgQJBAAAAA==.',
Ob='Obitrice:BAAALgAECggJCwAAAA==.Obsidiian:BAABLgAECn8VAAImAAgJlREnCgCBAQAmAAgJlREnCgCBAQAAAA==.Obsidion:BAABLgAECn8YAAMVAAYJrwzAWwCnAAAVAAUJ5gnAWwCnAAAMAAQJDggFVgCEAAABLgAECgkJNQAbALAYAA==.',
Od='Odie:BAAALgAECgYJDwAAAA==.',
On='Onemorehit:BAAALgAECgEJAwAAAA==.Onlyfangs:BAABLgAECn9KAAMZAAkJUxIjDQAAAgAZAAkJUxIjDQAAAgAHAAYJtwX9awCXAAAAAA==.',
Os='Oscrapermort:BAAALgADCgMJAwAAAA==.Ossin:BAAALgAFFAIJBAAAAA==.',
Pa='Padivyn:BAABLgAECn8ZAAIKAAgJzxiQIwDKAQAKAAgJzxiQIwDKAQAAAA==.Padnamprik:BAAALgAECgQJBAAAAA==.Palidenman:BAAALgAECgQJAwAAAA==.Pallypower:BAAALgAECgEJAgAAAA==.Pantherlilly:BAAALgAECggJDwAAAA==.',
Pe='Peanads:BAAALgADCgcJEAAAAA==.Pebblez:BAAALgADCgcJDgAAAA==.Perry:BAACLgAFFH8GAAIWAAMJcB5zKwAJAQAWAAMJcB5zKwAJAQAuAAQKfyoAAxYACQm6Ie8EAGwDABYACQm6Ie8EAGwDABgAAgkBBTuCAEQAAAAA.',
Ph='Phlampped:BAAALgADCgUJBQABLgAFFAkJIQARAGMXAA==.',
Pi='Pinotage:BAAALgAECggJDgABLgAECgkJQwABALodAA==.',
Po='Po:BAAALgAECgkJCAAAAA==.Pozufuma:BAABLgAECn9HAAMbAAkJHB2ZDAChAgAbAAkJHB2ZDAChAgAFAAEJ7gsaFwAlAAAAAA==.',
Pr='Priestcraft:BAAALgADCgIJAgABLgAECggJCwADAAAAAA==.',
Ps='Psychomantis:BAABLgAECn8qAAMVAAkJeRQGHwDNAQAVAAkJeRQGHwDNAQAMAAEJwRErHgAvAAAAAA==.',
Pu='Punchypunch:BAAALgADCgkJFAAAAA==.',
Ra='Raek:BAAALgAECgQJBQABLgAECgcJGQAUAPEbAA==.Raith:BAAALgAECgYJCwAAAA==.Ravenbear:BAAALgAECgQJBgABLgAECgkJSgAZAFMSAA==.Ravenbyrd:BAAALgADCgMJAwAAAA==.Rawberriez:BAAALgAECgQJBgAAAA==.',
Re='Reani:BAAALgADCgQJBAAAAA==.Reapin:BAAALgADCgUJBQAAAA==.Redpool:BAABLgAECn8fAAIIAAcJJBGNQACtAQAIAAcJJBGNQACtAQAAAA==.Remithedrood:BAAALgADCgIJAgAAAA==.Reqium:BAAALgADCgYJCAAAAA==.Resto:BAAALgAECgQJBgAAAA==.Rethandra:BAABLgAECn8YAAQIAAgJ9hP9XgCKAQAIAAcJSRX9XgCKAQAnAAMJLxRhHwC0AAAdAAIJ3gePEgA6AAAAAA==.Retrix:BAAALgAECgIJAwAAAA==.Revorra:BAAALgAECgcJCAABLgAECgkJNQAbALAYAA==.',
Ri='Rion:BAABLgAECn8XAAIfAAkJcxHRYgC5AQAfAAkJcxHRYgC5AQAAAA==.Ristvakbaen:BAACLgAFFH8EAAITAAIJVRqZkwCbAAATAAIJVRqZkwCbAAAuAAQKfzoABBQACQnmJEEDAIYCABQACAlGJUEDAIYCABMACQm8HbofAGYCABIABgk9JRYGAAQCAAAA.',
Ro='Robynlee:BAABLgAECn9SAAIMAAgJpRpzAgBXAgAMAAgJpRpzAgBXAgAAAA==.Roccobb:BAAALgADCgYJBgAAAA==.Rogùe:BAAALgAFFAIJAgAAAA==.Rosebelle:BAAALgAECgQJAwAAAA==.Roshu:BAAALgADCgEJAQAAAA==.',
Ru='Rugratt:BAAALgADCgQJBAABLgADCgcJDgADAAAAAA==.',
Sa='Saeler:BAAALgAECgMJAwAAAA==.Sailrmoonkin:BAAALgAECgQJBQABLgAFFAMJBgANABUVAA==.Samoth:BAAALgADCgEJAQAAAA==.Sanathein:BAAALgADCgcJBwAAAA==.Sanctuary:BAAALgAECgQJBAAAAA==.Santeclair:BAAALgAECgEJAQAAAA==.Satin:BAAALgAECggJDQAAAA==.',
Sc='Sceryna:BAACLgAFFH8GAAIRAAMJKA9eOQCzAAARAAMJKA9eOQCzAAAuAAQKfygAAhEACQnMF0FJAOoBABEACQnMF0FJAOoBAAAA.Schiftly:BAAALgAFFAIJAgAAAA==.Schwiggity:BAAALgAECgQJCgABLgAECgkJGwARAFwSAA==.Scottlock:BAABLgAECn8WAAISAAcJqh6QBQAVAgASAAcJqh6QBQAVAgABLgAECgkJLgAjAAIjAA==.Screwbrew:BAAALgAECgIJAgAAAA==.Screwid:BAAALgAECgQJBAAAAA==.Screwtotems:BAAALgAECgEJAQAAAA==.Scrmndemn:BAABLgAECn80AAIRAAkJdAidpAAwAQARAAkJdAidpAAwAQAAAA==.Scytale:BAAALgAECgkJCQAAAA==.',
Se='Sepviva:BAABLgAECn8VAAIBAAcJNhZmcACoAQABAAcJNhZmcACoAQAAAA==.Serea:BAAALgAECgEJAQABLgAECgkJUgAMAKUaAA==.Serpent:BAACLgAFFH8OAAIFAAYJ5BS9CgCDAQAFAAYJ5BS9CgCDAQAuAAQKfyMAAgUACQlnHxkIAHoCAAUACQlnHxkIAHoCAAEuAAUUCQkmAA0AvBEA.',
Sh='Shadowheal:BAAALgADCgUJBgAAAA==.Shamadeus:BAAALgADCgUJBQABLgAFFAIJBAATAFUaAA==.Shamtastical:BAAALgAECggJCwABLgAECgkJUgAMAKUaAA==.Sharaseth:BAAALgAECggJEQAAAA==.Shikita:BAABLgAECn9MAAMWAAkJnB51DQDvAgAWAAkJnB51DQDvAgAYAAEJHAZfigAlAAAAAA==.Shimadin:BAACLgAFFH8gAAIRAAYJphdmOAA8AQARAAYJphdmOAA8AQAuAAQKfykAAhEACQkfHvszADACABEACQkfHvszADACAAAA.Shimbuktu:BAAALgAECgEJAwABLgAFFAYJIAARAKYXAA==.Shimfu:BAAALgAECgEJAgABLgAFFAYJIAARAKYXAA==.Shimjun:BAAALgAECgUJCwABLgAFFAYJIAARAKYXAA==.Shimpbizkit:BAABLgAECn8ZAAIfAAcJAg0VnwA8AQAfAAcJAg0VnwA8AQABLgAFFAYJIAARAKYXAA==.Shimsong:BAAALgAECgYJEwABLgAFFAYJIAARAKYXAA==.Shmerek:BAABLgAECn8XAAIFAAkJRSBCCAB3AgAFAAkJRSBCCAB3AgAAAA==.',
Si='Sidarien:BAAALgADCgQJBAAAAA==.Silenttits:BAAALgAECgEJAgAAAA==.Silveralae:BAAALgAECgEJAQAAAA==.Silveraven:BAAALgADCgIJAgAAAA==.Silverlumen:BAAALgAFFAEJAgAAAA==.Silversaevus:BAAALgAFFAEJAQAAAA==.Silverstream:BAACLgAFFH8IAAIWAAMJGgqLSQCUAAAWAAMJGgqLSQCUAAAuAAQKfyoAAhYACQnoER1CAJkBABYACQnoER1CAJkBAAAA.',
Sk='Skyblue:BAAALgADCgEJAQAAAA==.',
Sl='Slea:BAABLgAECn8VAAIdAAkJQxApFAAEAgAdAAkJQxApFAAEAgAAAA==.Slease:BAAALgAECgYJBgAAAA==.',
Sm='Smallrichard:BAAALgAECgEJAQAAAA==.Smootish:BAAALgADCgUJBQAAAA==.',
So='Solbin:BAAALgAECgUJDAABLgAECgkJMAAfAIYZAA==.Solitudé:BAABLgAECn8fAAMTAAgJBiSWHwBnAgATAAcJPiGWHwBnAgAUAAUJoSW1FAAoAQABLgAFFAUJFAAOAP4fAA==.Soteirian:BAABLgAECn8zAAMRAAkJpAuIcgCJAQARAAkJpAuIcgCJAQAlAAEJjwJKXwASAAAAAA==.',
Sp='Spam:BAAALgAECgIJAgAAAA==.Spekey:BAAALgAECgEJAQAAAA==.Spider:BAABLgAECn9DAAIBAAkJuh3jAwCaAgABAAkJuh3jAwCaAgAAAA==.Spineymagus:BAAALgADCgIJAgAAAA==.',
Sq='Squall:BAABLgAECn8rAAMiAAgJMhCNRwCQAQAiAAgJMhCNRwCQAQAKAAYJ0ROVRQAdAQAAAA==.',
St='Stalariais:BAAALgAECgQJBAABLgAECgkJGgAcAIIJAA==.Stardrand:BAAALgADCgUJBgAAAA==.Steeg:BAAALgAECgYJEQAAAA==.Steelreserve:BAAALgAECgYJDQAAAA==.Steve:BAAALgAECgYJBgAAAA==.Straw:BAAALgAECgYJCwABLgAECgkJQwARAGgkAA==.',
Su='Sugarkitty:BAAALgADCgYJCgAAAA==.Supahot:BAAALgAECgEJAQAAAA==.Supereclipse:BAABLgAECn9IAAIIAAkJ/hZDKQA5AgAIAAkJ/hZDKQA5AgAAAA==.',
Sw='Swolareclips:BAAALgADCgYJBgAAAA==.',
Sy='Sydvicious:BAABLgAECn8iAAIPAAkJPCVYBAAEAwAPAAkJPCVYBAAEAwAAAA==.Sylvia:BAAALgADCgEJAQAAAA==.Syriene:BAABLgAECn8uAAICAAkJPBByEQCjAQACAAkJPBByEQCjAQAAAA==.',
Ta='Taladiir:BAAALgAECgEJAQAAAA==.Talana:BAAALgAECgEJAQAAAA==.Tankhealz:BAAALgAECgMJBQAAAA==.Tanthe:BAAALgAECgMJAwAAAA==.Tayger:BAAALgAFFAEJAQAAAA==.',
Tb='Tbsp:BAAALgAECgEJAQABLgAFFAUJFgALAEocAA==.',
Te='Tecks:BAABLgAECn8XAAIMAAkJwgWfPAABAQAMAAkJwgWfPAABAQAAAA==.Teddy:BAAALgAECgUJCQAAAA==.Teslá:BAAALgAECgYJCgAAAA==.Texican:BAAALgAECgEJAQAAAA==.',
Th='Theatrix:BAAALgAECgQJBwABLgAECgkJHgAHANsYAA==.Thecuckler:BAAALgAECgQJCAAAAA==.Thefreeman:BAAALgAECgEJAQAAAA==.Themajor:BAABLgAECn8uAAMGAAkJFhfmDAAYAgAGAAkJFhfmDAAYAgAbAAcJ/AhwTAB0AQAAAA==.Then:BAAALgADCgEJAQAAAA==.Thiarad:BAAALgADCgEJAQAAAA==.Thiaraxo:BAACLgAFFH8JAAMLAAMJHyGCHgDOAAALAAMJHyGCHgDOAAAEAAEJjhYtHQBIAAAuAAQKfxUAAgsACQmbBcp5ALAAAAsACQmbBcp5ALAAAAAA.Thrain:BAAALgADCgcJDAAAAA==.Threat:BAABLgAECn8mAAIRAAkJlCWXBQBHAwARAAkJlCWXBQBHAwAAAA==.Thronkall:BAAALgAECgkJAgAAAA==.Thsarus:BAABLgAECn8vAAMQAAgJ6yDlHABnAgAQAAgJ6yDlHABnAgAkAAQJHBHQGwCxAAAAAA==.Thunderthigh:BAAALgAECgIJAgAAAA==.',
Ti='Tiamaat:BAABLgAECn8XAAIWAAkJmgQKegDJAAAWAAkJmgQKegDJAAAAAA==.Tireyne:BAAALgADCgEJAgAAAA==.Titus:BAAALgAECgEJBgAAAA==.',
Tk='Tkt:BAAALgAECgIJBAABLgAFFAIJAgADAAAAAA==.',
To='Toatani:BAAALgAECgYJDgAAAA==.Tokkaebi:BAAALgAECgkJDAAAAA==.',
Tr='Treadlightly:BAAALgADCgUJBwAAAA==.Treefróg:BAAALgAECgUJBQAAAA==.Trentus:BAAALgADCgIJAgAAAA==.Trev:BAAALgAECgUJBgABLgAFFAUJBQATAIUWAA==.Trotem:BAAALgAECgUJBQAAAA==.',
Ts='Tsp:BAACLgAFFH8WAAILAAUJShwOHACSAQALAAUJShwOHACSAQAuAAQKfywAAwsACQn/Gd8cADECAAsACQn/Gd8cADECAB4ABAnxA0psAJEAAAAA.',
Ty='Tyletos:BAABLgAECn8wAAIfAAkJhhnZCgC3AQAfAAkJhhnZCgC3AQAAAA==.',
Ug='Ugolok:BAABLgAECn8pAAMOAAcJ7gfrIQC/AAABAAcJKQWY2wDZAAAOAAYJzQjrIQC/AAAAAA==.',
Ur='Uriél:BAABLgAECn8yAAIQAAkJNSWeAgBeAwAQAAkJNSWeAgBeAwABLgAFFAUJFAAOAP4fAA==.',
Va='Valeene:BAABLgAECn8uAAIYAAkJLiJSBAAcAwAYAAkJLiJSBAAcAwAAAA==.Valkion:BAAALgAECgEJAQAAAA==.Varek:BAABLgAECn8YAAIXAAkJ5yEyAwAbAwAXAAkJ5yEyAwAbAwAAAA==.Varlann:BAAALgADCgkJCQAAAA==.',
Ve='Veiler:BAABLgAECn9GAAMIAAkJEROKNgADAgAIAAkJEROKNgADAgAnAAEJ3wH2lgAhAAAAAA==.Velca:BAAALgAECgIJAgAAAA==.Veruca:BAAALgAECgMJAwAAAA==.Veviseron:BAABLgAECn8qAAIfAAkJNwSvpgAwAQAfAAkJNwSvpgAwAQAAAA==.',
Vh='Vhye:BAABLgAFFH8IAAIiAAMJtgZnZAB+AAAiAAMJtgZnZAB+AAAAAA==.',
Vi='Vidnoi:BAAALgAECgEJBAAAAA==.Vincentfreak:BAAALgAECgcJBwAAAA==.Vinstalation:BAABLgAECn81AAIOAAkJcRwxBgBHAgAOAAkJcRwxBgBHAgAAAA==.Vissa:BAAALgADCgYJBgAAAA==.',
Vo='Vonbismarck:BAABLgAECn8lAAMIAAkJ8hOSTQC5AQAIAAkJ8hOSTQC5AQAnAAEJFw/HDgAwAAAAAA==.',
Vr='Vritraz:BAACLgAFFH8UAAMOAAUJ/h9wCABnAQAOAAQJ/h9wCABnAQABAAEJAACtLQEAAAAuAAQKfxUAAw4ACQmLIqEGADkCAA4ABwk+I6EGADkCAAEAAgl0IAP3ALcAAAAA.Vrock:BAAALgAECgEJAQABLgAECgkJLwAfAHIeAA==.',
Vy='Vynian:BAAALgAECgEJAwAAAA==.',
Wa='Warnam:BAAALgADCgcJBwAAAA==.Warsonge:BAAALgADCgMJAwAAAA==.',
We='Wendypini:BAACLgAFFH8VAAIIAAUJKAeKUwACAQAIAAUJKAeKUwACAQAuAAQKfyIAAggACQkAEF5FAJsBAAgACQkAEF5FAJsBAAAA.Wetnwild:BAAALgADCgQJBAAAAA==.',
Wh='Whitehand:BAAALgAECgIJAgAAAA==.Whitlock:BAAALgAFFAEJAQAAAA==.',
Wo='Wooshwoosh:BAAALgAECgQJDgAAAA==.',
Wu='Wudeeps:BAAALgAECgcJEgAAAA==.Wuhanwarrior:BAAALgAECgYJEQAAAA==.',
Xa='Xalyra:BAAALgAECgEJAQAAAA==.',
Xe='Xendria:BAAALgAECgEJBAAAAA==.',
Ya='Yako:BAAALgAECgEJAQAAAA==.',
Ye='Yennefer:BAAALgAECgMJAwAAAA==.',
Yo='Yongary:BAAALgAECgkJCQAAAA==.',
Za='Zangolf:BAAALgADCgUJBAAAAA==.Zargoan:BAAALgAECgMJBAAAAA==.Zaye:BAAALgAECggJDAAAAA==.',
Ze='Zearas:BAABLgAECn8UAAIBAAgJJxE+kwBZAQABAAgJJxE+kwBZAQAAAA==.Zendonn:BAABLgAECn8bAAIEAAcJxwUiUgDAAAAEAAcJxwUiUgDAAAAAAA==.Zerk:BAAALgAECgEJAQAAAA==.Zevel:BAAALgADCgIJAgAAAA==.',
Zi='Zicatriz:BAAALgADCgcJDgAAAA==.',
Zo='Zodiaac:BAABLgAECn8XAAINAAkJdxm1FQC+AQANAAkJdxm1FQC+AQAAAA==.',
Zu='Zuggy:BAAALgAFFAEJAQABLgAFFAQJEAAdAGEeAA==.',
Zy='Zy:BAAALgADCgUJBQAAAA==.',
['Zà']='Zàknafein:BAABLgAECn8lAAMUAAcJgxZ2AgCUAQAUAAcJgxZ2AgCUAQATAAMJ3wVaMwBBAAAAAA==.',
['Ëc']='Ëchõ:BAABLgAECn8gAAMWAAkJ+RXSNwDIAQAWAAkJ+RXSNwDIAQAYAAIJvwRldwBHAAAAAA==.',
['Ðï']='Ðï:BAAALgADCgQJBAABLgAECgkJLAAVAAcdAA==.',
['ßo']='ßoomer:BAAALgADCgIJAgABLgAFFAMJBwAEALYHAA==.',
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
