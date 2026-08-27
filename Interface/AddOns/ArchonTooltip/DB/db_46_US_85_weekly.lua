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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Unknown-Unknown','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Hunter-BeastMastery','Priest-Discipline','Shaman-Elemental','Monk-Mistweaver','Priest-Holy','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Augmentation','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Druid-Restoration','Rogue-Subtlety','Druid-Balance','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Paladin-Holy','Hunter-Survival','Monk-Brewmaster','Mage-Frost','Druid-Guardian','Rogue-Assassination','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Protection','Rogue-Outlaw','Hunter-Marksmanship',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=46,date='2026-08-25',data={Ab='Abominable:BAAALgADCgEJAQAAAA==.',
Ad='Addo:BAAALgAECgMJAwABLgAECgkJQwABALodAA==.',
Ae='Aelaster:BAAALgADCgYJBgAAAA==.',
Ag='Agden:BAAALgADCgEJAQAAAA==.',
Al='Alaìrn:BAAALgAECgUJCwABLgAECgkJFgACAKcdAA==.Aldrich:BAAALgAECgYJBwAAAA==.Alenciann:BAAALgAECgMJBwAAAA==.Allayna:BAAALgAECgEJAQABLgAECgEJAwADAAAAAA==.Alstre:BAAALgAECgEJAQAAAA==.Alys:BAABLgAECn86AAIEAAkJYw4IIgCfAQAEAAkJYw4IIgCfAQAAAA==.',
Am='Amaniatres:BAABLgAECn8pAAMFAAgJqhMXBAB7AQAFAAgJGhMXBAB7AQAGAAQJEw8XSwChAAAAAA==.Ammartin:BAABLgAECn8YAAIHAAkJyQo1bQBnAQAHAAkJyQo1bQBnAQAAAA==.Amoonranara:BAAALgADCgEJAQAAAA==.',
An='Anaan:BAAALgAECgUJBgAAAA==.Anahera:BAAALgAECgEJAQABLgAECgYJDgADAAAAAA==.Anakha:BAAALgADCggJCAABLgAECgUJBgADAAAAAA==.Anfna:BAAALgAECgEJAgAAAA==.Angrylizard:BAAALgAECgEJAgAAAA==.Anklebiterr:BAAALgAECgUJBwAAAA==.',
Ap='Apothecary:BAAALgADCgcJBwAAAA==.',
Ar='Arabella:BAAALgAECggJEQAAAA==.Arandomidiot:BAAALgADCgYJBgAAAA==.Arathan:BAAALgADCgkJHAAAAA==.Arihana:BAAALgAECgYJEAAAAA==.Ariiana:BAABLgAECn8XAAIIAAkJIx7rBgAOAwAIAAkJIx7rBgAOAwAAAA==.Arngal:BAAALgAECgEJAQAAAA==.',
As='Asapshocky:BAACLgAFFH8bAAIJAAgJRBlIBwACAgAJAAgJRBlIBwACAgAuAAQKfzAAAgkACQmgJBIFAA0DAAkACQmgJBIFAA0DAAAA.Asclepios:BAAALgAECgMJBAAAAA==.Asmoday:BAAALgAECgYJBgAAAA==.Astraroth:BAAALgADCgcJCgAAAA==.',
Av='Avella:BAAALgADCgUJBwAAAA==.',
Ba='Balaris:BAAALgADCgcJBwABLgAECgkJIwAKACEUAA==.Balum:BAAALgAECgEJAQAAAA==.Bamwham:BAAALgADCgcJBwAAAA==.Barrii:BAAALgAECgMJBQAAAA==.',
Be='Bearblaster:BAAALgADCgQJBAABLgAECgQJBgADAAAAAA==.Bearlytanks:BAAALgADCgIJAgAAAA==.Beastwallker:BAAALgADCgUJBgAAAA==.Bellabelle:BAABLgAECn8XAAILAAgJ+gkACgAQAQALAAgJ+gkACgAQAQAAAA==.Bellgerra:BAAALgAECgEJAQAAAA==.Ben:BAAALgAECgcJEwAAAA==.Betamaxx:BAACLgAFFH8HAAMMAAMJuBH5LwCDAAAMAAIJThb5LwCDAAANAAIJAwhRFQB1AAAuAAQKfxUAAgwABwmCHYgSAOYBAAwABwmCHYgSAOYBAAAA.Betterx:BAAALgAECgQJBQAAAA==.Bevian:BAAALgAECgEJAQABLgAECgkJDgADAAAAAA==.',
Bi='Biggiepants:BAABLgAECn8iAAMOAAkJ0h9oBwC7AgAOAAkJ0h9oBwC7AgAPAAgJ9w6fYABoAQAAAA==.Bighead:BAAALgAECgYJCAABLgAECgUJCwADAAAAAA==.Bigwarlocks:BAAALgAECgMJBwABLgAECgUJCwADAAAAAA==.Bintje:BAAALgADCgcJEgAAAA==.Biollante:BAAALgAECgcJCwAAAA==.',
Bl='Blindedlïght:BAAALgAECgUJBgAAAA==.',
Bo='Bolsan:BAAALgAECgMJBQAAAA==.Bonq:BAAALgAECgIJAgABLgAECgkJEQAOACUcAA==.Bootyßandaid:BAACLgAFFH8RAAIQAAMJExp0PADVAAAQAAMJExp0PADVAAAuAAQKfxQAAhAACAm4GfoVACkCABAACAm4GfoVACkCAAAA.Bourg:BAAALgAECgYJCAAAAA==.Bowhemian:BAAALgAECgMJBgAAAA==.',
Bu='Bubbahubba:BAAALgAECgEJAQAAAA==.Buckis:BAABLgAECn8kAAIRAAkJERjgBwAGAgARAAkJERjgBwAGAgAAAA==.Bufú:BAAALgADCgIJAgAAAA==.',
['Bö']='Böurbon:BAAALgADCgkJCgAAAA==.',
Ca='Caelia:BAAALgADCgEJAQAAAA==.Cahk:BAAALgAECgMJAwAAAA==.Cajia:BAABLgAECn8uAAMSAAkJ4wo8HQC+AAATAAkJgwndfgA7AQASAAYJBgs8HQC+AAAAAA==.',
Ce='Celds:BAAALgADCgQJBAABLgAECgcJGQAUAPEbAA==.Celiae:BAAALgAECgYJEAAAAA==.Cendanel:BAAALgAECgIJAgAAAA==.',
Ch='Childress:BAAALgAECgMJAwAAAA==.Chiwhiz:BAAALgAECgEJAQABLgAECgQJCwADAAAAAA==.Choggy:BAABLgAECn8uAAIVAAkJxhvnDgBqAgAVAAkJxhvnDgBqAgAAAA==.Chogs:BAAALgAECgMJBAABLgAECgkJLgAVAMYbAA==.Chuec:BAAALgAECgEJAQAAAA==.',
Ci='Cimbline:BAAALgADCgIJAgAAAA==.',
Cl='Clairerick:BAAALgAECgYJEAAAAA==.Clenise:BAAALgAECgEJAQAAAA==.',
Co='Cokebear:BAAALgAECgMJAwABLgAECggJJAAWAHEaAA==.Composer:BAABLgAECn8eAAIQAAkJ2xizAQA6AgAQAAkJ2xizAQA6AgABLgAECggJKQAFAKoTAA==.Conception:BAAALgAECgUJBgABLgAECgkJUgALAKUaAA==.Confessionn:BAAALgADCggJDAAAAA==.Cough:BAAALgAECgUJCwAAAA==.',
Cr='Crinklecut:BAABLgAECn8ZAAIXAAgJQQwKJQBtAQAXAAgJQQwKJQBtAQAAAA==.Critos:BAAALgADCgcJBwAAAA==.Crotchout:BAAALgADCgMJAwAAAA==.Crybaby:BAAALgADCgEJAQAAAA==.Crystilpixy:BAAALgADCgMJBAAAAA==.',
['Cé']='Céline:BAAALgAECgEJAQAAAA==.',
Da='Dalal:BAAALgAECgUJCAABLgAECgkJUgALAKUaAA==.Danielallen:BAAALgAFFAMJBAAAAA==.Danilov:BAAALgADCgYJBgAAAA==.',
De='Deadlyshift:BAABLgAECn8XAAMWAAkJsCKWBQBeAwAWAAkJsCKWBQBeAwAYAAUJMho8NgBjAQAAAA==.Deadmenace:BAAALgAECgEJAQAAAA==.Deadybear:BAAALgADCgkJEAABLgAECgkJSgAZAFMSAA==.Deathkyter:BAAALgAECgEJAQAAAA==.Delrok:BAAALgAECgEJAgAAAA==.Demonicblade:BAAALgADCggJCAAAAA==.Dephias:BAAALgADCgMJAwAAAA==.',
Di='Diagnosis:BAABLgAECn8eAAIRAAkJhSVqCwAKAwARAAkJhSVqCwAKAwAAAA==.',
Do='Donnabb:BAABLgAECn8YAAIRAAgJCQXGOAB0AAARAAgJCQXGOAB0AAAAAA==.Donteatbees:BAABLgAECn8UAAINAAkJZgquGAAPAQANAAkJZgquGAAPAQAAAA==.Dop:BAAALgAECgEJAwAAAA==.Doran:BAABLgAECn8eAAIOAAgJaRcHFwDNAQAOAAgJaRcHFwDNAQAAAA==.Doriathrin:BAAALgADCgcJCwAAAA==.Doujinshi:BAABLgAECn8OAAIPAAcJIBziUwCoAQAPAAcJIBziUwCoAQAAAA==.',
Dr='Dragonbladez:BAAALgADCgUJBQAAAA==.Dragoneye:BAAALgAECgMJBgAAAA==.Dragonhawk:BAAALgADCgQJBAABLgAECgMJEgADAAAAAA==.Dragonname:BAAALgAECgEJAQAAAA==.Drakoil:BAABLgAECn87AAMaAAkJwBi7BAAkAgAaAAkJJRi7BAAkAgAQAAcJNxMiNQBdAQAAAA==.Dreademperor:BAACLgAFFH8JAAIFAAQJdBUnGgDGAAAFAAQJdBUnGgDGAAAuAAQKfycAAwUACQkhHvAEAPYCAAUACQkhHvAEAPYCABsABAlDDwliAM8AAAEuAAUUBQkMAAwAJR8A.Dreadnature:BAAALgAECgMJAwAAAA==.Dreadnight:BAABLgAFFH8MAAIMAAUJJR8NFwAwAQAMAAUJJR8NFwAwAQAAAA==.Dreadsteed:BAAALgAECgEJAQABLgAFFAUJDAAMACUfAA==.Dreadweaver:BAAALgADCgUJBQABLgAFFAUJDAAMACUfAA==.Drenrah:BAABLgAECn8pAAIcAAkJug+lKwC0AQAcAAkJug+lKwC0AQAAAA==.Drgndeeznutz:BAACLgAFFH8QAAIdAAQJYR4CCAAZAQAdAAQJYR4CCAAZAQAuAAQKfygAAh0ACQnPHykFANYCAB0ACQnPHykFANYCAAEuAAUUAwkRABAAExoA.Drunkenrage:BAACLgAFFH8pAAIeAAkJhhxbBABbAgAeAAkJhhxbBABbAgAuAAQKfx4AAh4ACQkcIvsBAIIDAB4ACQkcIvsBAIIDAAAA.',
Du='Dumorius:BAAALgAECgYJCAAAAA==.',
['Dé']='Déx:BAAALgAECgYJCwAAAA==.',
Ed='Edgemenace:BAAALgADCgQJBAAAAA==.Edreth:BAAALgAECgEJAQAAAA==.',
Ei='Eiduartpaw:BAABLgAFFH8IAAIRAAMJ7BdThACrAAARAAMJ7BdThACrAAAAAA==.',
El='Elbryan:BAABLgAECn8xAAIVAAkJhAinMABbAQAVAAkJhAinMABbAQAAAA==.Elementdemon:BAAALgAFFAEJAQAAAA==.Ellabelle:BAAALgADCgMJAwAAAA==.',
En='Enthalpy:BAABLgAECn8vAAIfAAkJch6IGwC2AgAfAAkJch6IGwC2AgAAAA==.',
Ep='Epipin:BAAALgAECgUJCAAAAA==.',
Er='Erakazsod:BAAALgAECgEJAQABLgAFFAMJEQAQABMaAA==.Erazath:BAAALgAECgUJCAABLgAECgkJEAADAAAAAA==.',
Es='Esperzoa:BAACLgAFFH8GAAIMAAMJFRVDFAC/AAAMAAMJFRVDFAC/AAAuAAQKfzIAAgwACQmRG30NADICAAwACQmRG30NADICAAAA.',
Et='Eternaldread:BAAALgADCgUJBQABLgAFFAUJDAAMACUfAA==.',
Eu='Eucalicdes:BAABLgAECn9CAAIgAAkJvhfFDQAGAgAgAAkJvhfFDQAGAgAAAA==.',
Ez='Ezal:BAAALgAECgYJCAAAAA==.Ezra:BAAALgAECgUJBQAAAA==.',
Fa='Fallyn:BAAALgAECgEJAQAAAA==.Fancy:BAAALgADCgUJBQAAAA==.Fangyi:BAABLgAECn8XAAIfAAkJcxHRYgC5AQAfAAkJcxHRYgC5AQAAAA==.Farshran:BAAALgAECgkJEAAAAA==.Fate:BAAALgAECgQJBQABLgAECgkJJgARAJQlAA==.Fathermajor:BAAALgAECgQJBAAAAA==.',
Fe='Felicity:BAACLgAFFH8WAAIXAAUJ2h0THAA6AQAXAAUJ2h0THAA6AQAuAAQKfzYAAxcACQmWIpIEAE4DABcACQmWIpIEAE4DACEABQmDDb8VANEAAAAA.Ferendis:BAABLgAECn8nAAIPAAgJPiOiEwCmAgAPAAgJPiOiEwCmAgAAAA==.Fernard:BAAALgADCgYJBgABLgAECgkJEQAOACUcAA==.',
Fl='Flokii:BAAALgAECgQJBQAAAA==.Florita:BAABLgAECn8VAAIHAAkJmgo7EwBOAQAHAAkJmgo7EwBOAQAAAA==.Flydormu:BAAALgAECgYJDAABLgAECgkJMAAfAIYZAA==.',
Fo='Fordinn:BAABLgAECn81AAMbAAkJsBiRGwARAgAbAAkJZRaRGwARAgAFAAcJeRUOGwBgAQAAAA==.',
Fr='Fractured:BAAALgADCgEJAQAAAA==.Freelor:BAAALgAECgIJBAAAAA==.Freemi:BAAALgAECgEJAQAAAA==.Frenzy:BAAALgAECgkJAQAAAA==.Frigidgrip:BAAALgAECgMJAwAAAA==.',
Fu='Fuddytwo:BAABLgAECn8wAAIYAAkJKR0fAwAXAgAYAAkJKR0fAwAXAgAAAA==.Furrypaw:BAAALgAECgcJBwABLgAFFAUJCgAKAMIPAA==.Furrypunch:BAABLgAFFH8KAAMKAAUJwg9cGAAOAQAKAAUJwg9cGAAOAQAEAAIJPg3CFQB8AAAAAA==.',
Ga='Garzhvog:BAAALgADCgcJCwABLgAFFAIJBAATAFUaAA==.Gasket:BAACLgAFFH8bAAMNAAUJRhpKDgAnAQABAAUJ/BcQXgA4AQANAAUJ3hNKDgAnAQAuAAQKfyUAAwEACQlnIsMiALQCAAEACQlvIcMiALQCAA0AAwkcIEUZAAoBAAAA.Gauteng:BAAALgAECgIJAgABLgAFFAYJGwARAHAfAA==.',
Gh='Ghidõráh:BAAALgAECgEJAQAAAA==.Ghorac:BAAALgADCgYJDAAAAA==.Ghoti:BAAALgADCgUJBQAAAA==.Ghoulz:BAAALgADCgcJDAAAAA==.',
Gl='Glazedham:BAAALgADCgMJAwAAAA==.',
Gn='Gnollfang:BAAALgADCgYJBgAAAA==.',
Go='Gorbubbli:BAAALgADCgkJGgAAAA==.',
Gr='Graceful:BAAALgAECgUJBgAAAA==.Griffith:BAAALgAECgEJAQAAAA==.Grit:BAAALgAECgYJDAAAAA==.',
Gu='Guidosarduci:BAAALgADCgEJAQAAAA==.Guilddrama:BAAALgADCgEJAQAAAA==.',
Ha='Haeler:BAAALgAECgIJAwAAAA==.Haelin:BAAALgADCgEJAQAAAA==.Halgoðfulk:BAAALgAECgEJAQAAAA==.Hamwarrior:BAAALgAECgEJAQAAAA==.Handicap:BAAALgAECggJEAABLgAECgkJHgARAIUlAA==.Hark:BAACLgAFFH8cAAIHAAYJ5g6oRQAiAQAHAAYJ5g6oRQAiAQAuAAQKfywAAgcACQmOG7RQALABAAcACQmOG7RQALABAAAA.Harpin:BAAALgAECgEJAQAAAA==.Harvin:BAABLgAECn80AAIZAAkJgCL0AQBlAwAZAAkJgCL0AQBlAwAAAA==.',
He='Heisenburgg:BAAALgAECgkJCQAAAA==.Hekus:BAEALgAECgcJEQAAAA==.Helanua:BAABLgAECn8rAAIJAAkJQhEQJwCzAQAJAAkJQhEQJwCzAQAAAA==.Hellsplay:BAAALgADCgIJAgAAAA==.',
Hi='Hibernate:BAAALgADCgEJAQAAAA==.Hippolytus:BAAALgADCgkJCQABLgAECgkJLgAeAPQkAA==.Hippopotamus:BAAALgAECgMJAwAAAA==.Hit:BAAALgAECgYJCwABLgAECgkJCQADAAAAAA==.',
Ho='Holytide:BAABLgAECn82AAMJAAkJ9w4ZQwAnAQAJAAgJqgwZQwAnAQAiAAkJsgycEgAQAQAAAA==.Hope:BAABLgAECn8wAAIYAAgJbww4OQAuAQAYAAgJbww4OQAuAQAAAA==.Horrorfang:BAABLgAECn9PAAIBAAkJUiHxCwANAwABAAkJUiHxCwANAwAAAA==.',
Hu='Hukjo:BAAALgAECgcJEgABLgAECgkJIwAKACEUAA==.',
Ib='Ibaar:BAACLgAFFH8YAAIQAAcJFSLYHgBpAQAQAAcJFSLYHgBpAQAuAAQKfy8AAxAACQlJJE0HAAUDABAACAnAI00HAAUDABoABgneIAcNAAoCAAAA.',
Ic='Icepickle:BAAALgADCgcJAQAAAA==.Icialiaa:BAAALgAECggJEAABLgAECgkJLgACADwQAA==.',
Ii='Iilnut:BAABLgAECn8gAAMVAAgJnCA/CwDPAgAVAAgJnCA/CwDPAgAIAAQJPBW2NwDpAAABLgAFFAQJDAAKALEgAA==.',
Il='Illedren:BAABLgAECn8QAAIPAAgJwwc7kAAAAQAPAAgJwwc7kAAAAQAAAA==.',
In='Innerdemon:BAAALgAECgQJBAAAAA==.Inno:BAABLgAECn8YAAIPAAkJDiTxEwDhAgAPAAkJDiTxEwDhAgAAAA==.',
Ir='Irraedorine:BAABLgAECn8gAAMXAAkJvwsHCAD+AAAXAAkJvwsHCAD+AAAhAAgJCwScEwDuAAABLgAECgkJLgACADwQAA==.',
Is='Isabel:BAAALgAECgcJDQABLgAECgkJFwAHAJAVAA==.',
It='Ithacus:BAABLgAECn8pAAIjAAkJtBGcEQCaAQAjAAkJtBGcEQCaAQAAAA==.',
Ja='Jandaar:BAAALgAECgEJAQAAAA==.Jatt:BAAALgAECgMJCAAAAA==.Jattao:BAAALgADCgEJAQAAAA==.Jattix:BAAALgAECgEJAgAAAA==.Jattwuzza:BAAALgAECgIJBQAAAA==.',
Jd='Jdawgprime:BAAALgADCgcJBwAAAA==.',
Je='Jenjas:BAAALgAECgUJBQAAAA==.',
Ji='Jinnlee:BAAALgAECgYJBwAAAA==.Jinoo:BAABLgAECn9CAAIJAAkJhhswDwB9AgAJAAkJhhswDwB9AgAAAA==.Jinufan:BAAALgAECgUJBwABLgAFFAcJGAAQABUiAA==.',
Jo='Jodyhusky:BAAALgADCgYJBgAAAA==.Joe:BAAALgAECgcJCgAAAA==.Jorek:BAABLgAECn8WAAIbAAkJ7BT0KAC2AQAbAAkJ7BT0KAC2AQAAAA==.',
Ju='Jugulator:BAAALgADCgcJDQAAAA==.',
Ka='Kaejung:BAAALgAECgUJBgAAAA==.Kainairobi:BAAALgAECgUJCQAAAA==.Kaiva:BAAALgAECgQJBgABLgAECgYJDgADAAAAAA==.Kallistô:BAAALgADCgYJBgAAAA==.Kamigawa:BAABLgAECn8VAAIbAAgJqwt/PABTAQAbAAgJqwt/PABTAQAAAA==.Kavik:BAABLgAECn8fAAIcAAkJHhlKEQCKAgAcAAkJHhlKEQCKAgAAAA==.Kazbodan:BAAALgADCgkJFQAAAA==.',
Ke='Keemo:BAACLgAFFH8cAAIMAAYJjRRTHwDsAAAMAAYJjRRTHwDsAAAuAAQKfykAAwwACQnJFachAEUBAAwACQmpFachAEUBAAEAAwmYDUX8AIMAAAAA.Keemosaki:BAAALgAFFAEJAwAAAA==.Keemõ:BAABLgAECn8XAAMPAAYJvw1QnwDkAAAPAAYJ0wxQnwDkAAAkAAYJownQIACXAAAAAA==.Keemøsabi:BAAALgAFFAEJAgAAAA==.Keflá:BAAALgAECgYJEgAAAA==.Keineliebe:BAAALgADCgcJBwAAAA==.Keysersöze:BAAALgADCgYJBwAAAA==.',
Kh='Khaas:BAABLgAECn9QAAIBAAkJuQ9CTgDYAQABAAkJuQ9CTgDYAQAAAA==.Khaleeb:BAAALgAECgEJAwAAAA==.Kheleze:BAAALgADCggJCAABLgAECgYJEgADAAAAAA==.',
Ki='Kierios:BAABLgAECn8oAAMNAAkJiRbCCAD+AQANAAkJTxPCCAD+AQABAAgJ3RDmawCOAQAAAA==.Kildurgan:BAAALgAECgQJDQAAAA==.Killawarlock:BAABLgAECn8hAAQTAAgJzCKLPgDiAQATAAcJNSCLPgDiAQAUAAQJbCIsFAAuAQASAAEJ/hAbcAA2AAAAAA==.Kironn:BAAALgADCgYJBgABLgAECgUJCwADAAAAAA==.',
Kk='Kkain:BAAALgAECgIJBwAAAA==.',
Ko='Korihor:BAABLgAECn8pAAIlAAkJ6B1fCQA7AgAlAAkJ6B1fCQA7AgAAAA==.',
Kr='Krestus:BAABLgAECn8RAAMOAAcJJRyxQACzAAAPAAYJrxkZfgAvAQAOAAMJKSCxQACzAAAAAA==.Krispy:BAABLgAECn87AAQEAAkJHxbJFAAUAgAEAAkJEhbJFAAUAgAeAAcJ2Q4VOAAcAQAKAAUJvgO5TgCZAAAAAA==.Krith:BAAALgADCgYJCQAAAA==.Krix:BAAALgAECgMJBAAAAA==.',
Ky='Kyndil:BAAALgAECgcJEQAAAA==.',
La='Laerin:BAABLgAECn8UAAIcAAkJZBSxLACtAQAcAAkJZBSxLACtAQAAAA==.Laxus:BAAALgAECgMJAwABLgAECgkJHwAZAJMSAA==.Lazarius:BAAALgADCgQJBAAAAA==.',
Le='Leafblade:BAAALgAECgkJDgAAAA==.Levophed:BAABLgAECn8xAAIBAAkJhQ+BrAAZAQABAAkJhQ+BrAAZAQAAAA==.Lexor:BAAALgAECgMJAwAAAA==.',
Li='Liangwei:BAAALgAECgMJAwABLgAFFAMJBwAHAPMdAA==.Lightfallen:BAAALgAECgcJEQAAAA==.Lightseeker:BAAALgAECgEJAQABLgAECgkJHwAZAJMSAA==.Liisara:BAABLgAECn8bAAIPAAgJZggzigAMAQAPAAgJZggzigAMAQAAAA==.Lily:BAABLgAECn88AAIgAAkJHRu1DAAWAgAgAAkJHRu1DAAWAgAAAA==.Linadra:BAABLgAECn8uAAIRAAkJgwmikQBPAQARAAkJgwmikQBPAQAAAA==.Linnt:BAAALgAECgQJBwAAAA==.Linzur:BAAALgAECgEJAQAAAA==.Littleyeti:BAAALgAECgMJAwAAAA==.Liyara:BAACLgAFFH8bAAIRAAYJcB82IACGAQARAAYJcB82IACGAQAuAAQKfykAAhEACQm1JUgRAAYDABEACQm1JUgRAAYDAAAA.',
Ll='Llorsa:BAABLgAECn9FAAMLAAkJZhfiEQBQAgALAAkJZhfiEQBQAgAVAAUJdA1aUADPAAAAAA==.',
Lo='Lohhan:BAAALgADCgUJCQAAAA==.Lolamontez:BAAALgAECgIJAgAAAA==.Lorachka:BAAALgADCgIJAgAAAA==.Lorthys:BAAALgADCgEJAQAAAA==.',
Lu='Luxian:BAACLgAFFH8JAAIRAAIJxghaTwB1AAARAAIJxghaTwB1AAAuAAQKf1MAAhEACQkgFR1LAOUBABEACQkgFR1LAOUBAAAA.',
Ly='Lyssirix:BAABLgAECn8eAAIJAAcJdBZdBgCMAQAJAAcJdBZdBgCMAQAAAA==.',
['Lä']='Ländrei:BAABLgAECn8lAAIHAAkJ4A+KdQBUAQAHAAkJ4A+KdQBUAQABLgAECgkJJQAHAOAPAA==.',
Ma='Macandcheese:BAAALgAECgMJBwAAAA==.Macy:BAABLgAECn8YAAIfAAcJJhPKGAAUAQAfAAcJJhPKGAAUAQAAAA==.Mahiru:BAAALgADCgEJAQAAAA==.Mahralla:BAAALgADCgIJAgAAAA==.Maikagond:BAAALgAECgYJDgABLgAECgkJMwARAKQLAA==.Makaria:BAAALgAECggJEAAAAA==.Malbisa:BAAALgAECgQJBgAAAA==.Malphoz:BAAALgAECgUJBwAAAA==.Mandragora:BAABLgAECn8bAAIRAAkJXBJgiQBdAQARAAkJXBJgiQBdAQAAAA==.Maoriofdeath:BAAALgADCgEJAQABLgAECgYJDgADAAAAAA==.Map:BAAALgAECgIJAwAAAA==.Marli:BAAALgADCgEJAQAAAA==.Mattieatzdot:BAAALgAECgQJBQAAAA==.',
Mc='Mcgrowlin:BAAALgAECgQJCwAAAA==.',
Me='Mekator:BAAALgAECgQJBAAAAA==.Meko:BAAALgAECgUJBwAAAA==.Merrycow:BAAALgAECggJCwAAAA==.Mew:BAAALgAECgIJAwABLgAFFAEJAgADAAAAAA==.',
Mi='Mickey:BAACLgAFFH8IAAIEAAQJJwsEHwDeAAAEAAQJJwsEHwDeAAAuAAQKfygAAgQACQkTIlcHANQCAAQACQkTIlcHANQCAAAA.Migraine:BAAALgAECgYJCgAAAA==.Mikiik:BAABLgAECn9GAAITAAkJzwqaXACIAQATAAkJzwqaXACIAQAAAA==.Mildoo:BAABLgAECn8sAAIUAAkJBA/2CwCeAQAUAAkJBA/2CwCeAQAAAA==.Milkymoo:BAABLgAECn8iAAIFAAUJfxybHgA/AQAFAAUJfxybHgA/AQABLgAFFAkJOAALAOUXAA==.Millina:BAAALgADCgIJAgABLgAECgkJOgAEAGMOAA==.Mimira:BAAALgAECgEJAQAAAA==.Minipal:BAAALgAECgcJEQABLgAECgkJFgACAKcdAA==.Mixednuts:BAACLgAFFH8MAAIKAAQJsSAOIABuAQAKAAQJsSAOIABuAQAuAAQKfycAAwoACQmiIhoEAHIDAAoACQmiIhoEAHIDAAQABgkoIKofANoBAAAA.',
Mo='Mochii:BAAALgADCgYJBgAAAA==.Moneyshock:BAAALgAECgYJBgABLgAFFAMJEQAQABMaAA==.Monq:BAABLgAECn8YAAMEAAgJBBjAHADIAQAEAAgJBBjAHADIAQAeAAEJyAkqjQAqAAAAAA==.Moonamber:BAAALgADCgQJBgAAAA==.Morphinzerr:BAAALgAECgEJAQAAAA==.Moón:BAAALgAECgEJAwAAAA==.',
Mu='Murdrmittens:BAAALgAECgEJAQAAAA==.',
My='Mysterychogs:BAAALgAECgEJAQABLgAECgkJLgAVAMYbAA==.Mythion:BAABLgAECn8kAAMWAAgJcRpmJQAiAgAWAAgJcRpmJQAiAgAYAAQJCQWtawBzAAAAAA==.Mythlocked:BAAALgAECgYJBgAAAA==.Mythoridan:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîlk:BAABLgAFFH8HAAIOAAUJagvXDwC4AAAOAAUJagvXDwC4AAAAAA==.',
Na='Naeres:BAABLgAECn8fAAIBAAgJkBcvcACEAQABAAgJkBcvcACEAQAAAA==.Nafari:BAAALgAECggJCAAAAA==.Naofummi:BAAALgAECgcJBwAAAA==.Naomii:BAABLgAECn8rAAMLAAkJxxnUFwAPAgALAAkJxxnUFwAPAgAVAAUJZQiXWQCvAAAAAA==.Narus:BAAALgAECgcJCgABLgAECgkJNQAbALAYAA==.Naturefury:BAAALgADCgEJAQAAAA==.',
Ne='Neeston:BAACLgAFFH8HAAIWAAMJzBI9PAC+AAAWAAMJzBI9PAC+AAAuAAQKfyIAAxYACAkJI5oPANcCABYACAkJI5oPANcCABgAAQllEtyAADAAAAEuAAUUAwkRABAAExoA.Neodin:BAABLgAECn8jAAIbAAkJlQ+0JgDEAQAbAAkJlQ+0JgDEAQAAAA==.Neoresto:BAAALgAECgMJAwAAAA==.Nephadin:BAAALgADCgUJAwABLgAECgkJKQAlABQiAA==.Nerfed:BAAALgAECgUJCAAAAA==.Neviaa:BAABLgAECn8uAAIBAAkJXRSyQAABAgABAAkJXRSyQAABAgAAAA==.',
Ni='Nickypoo:BAAALgAECgMJBgAAAA==.Nightmenace:BAAALgAECgcJCwAAAA==.Ninari:BAAALgADCgUJBQAAAA==.Niq:BAAALgAECgQJBAAAAA==.',
No='Nocshadue:BAAALgADCgYJCwAAAA==.Nordga:BAAALgADCgcJBwAAAA==.Norii:BAAALgADCgIJAgABLgAECgkJDgADAAAAAA==.Nothealster:BAAALgAECgcJEwAAAA==.Nothros:BAAALgADCgQJBAAAAA==.',
Ob='Obitrice:BAAALgAECggJCwAAAA==.Obsidiian:BAABLgAECn8VAAImAAgJlREnCgCBAQAmAAgJlREnCgCBAQAAAA==.Obsidion:BAABLgAECn8YAAMVAAYJrwzAWwCnAAAVAAUJ5gnAWwCnAAALAAQJDggFVgCEAAABLgAECgkJNQAbALAYAA==.',
Od='Odie:BAAALgAECgYJDwAAAA==.',
On='Onemorehit:BAAALgAECgEJAwAAAA==.Onlyfangs:BAABLgAECn9KAAMZAAkJUxIjDQAAAgAZAAkJUxIjDQAAAgAQAAYJtwX9awCXAAAAAA==.',
Os='Oscrapermort:BAAALgADCgMJAwAAAA==.Ossin:BAAALgAFFAIJBAAAAA==.',
Pa='Padivyn:BAABLgAECn8ZAAIJAAgJzxiQIwDKAQAJAAgJzxiQIwDKAQAAAA==.Padnamprik:BAAALgAECgQJBAAAAA==.Palidenman:BAAALgAECgQJAwAAAA==.Pallypower:BAAALgAECgEJAgAAAA==.Pantherlilly:BAAALgAECggJDwAAAA==.',
Pe='Peanads:BAAALgADCgcJEAAAAA==.Pebblez:BAAALgADCgcJDgAAAA==.Perry:BAACLgAFFH8GAAIWAAMJcB5zKwAJAQAWAAMJcB5zKwAJAQAuAAQKfyoAAxYACQm6Ie8EAGwDABYACQm6Ie8EAGwDABgAAgkBBTuCAEQAAAAA.',
Ph='Phlampped:BAAALgADCgUJBQABLgAFFAkJIQARAGMXAA==.',
Pi='Pinotage:BAAALgAECggJDgABLgAECgkJQwABALodAA==.',
Po='Po:BAAALgAECgkJCAAAAA==.Pozufuma:BAABLgAECn9HAAMbAAkJHB2ZDAChAgAbAAkJHB2ZDAChAgAFAAEJ7gsaFwAlAAAAAA==.',
Pr='Priestcraft:BAAALgADCgIJAgABLgAECggJCwADAAAAAA==.',
Ps='Psychomantis:BAABLgAECn8qAAMVAAkJeRQGHwDNAQAVAAkJeRQGHwDNAQALAAEJwREtHgAuAAAAAA==.',
Pu='Punchypunch:BAAALgADCgkJFAAAAA==.',
Ra='Raek:BAAALgAECgQJBQABLgAECgcJGQAUAPEbAA==.Raith:BAAALgAECgYJCwAAAA==.Ravenbear:BAAALgAECgQJBgABLgAECgkJSgAZAFMSAA==.Ravenbyrd:BAAALgADCgMJAwAAAA==.Rawberriez:BAAALgAECgQJBgAAAA==.',
Re='Reani:BAAALgADCgQJBAAAAA==.Reapin:BAAALgADCgUJBQAAAA==.Redpool:BAABLgAECn8fAAIHAAcJJBGNQACtAQAHAAcJJBGNQACtAQAAAA==.Remithedrood:BAAALgADCgIJAgAAAA==.Reqium:BAAALgADCgYJCAAAAA==.Resto:BAAALgAECgQJBgAAAA==.Rethandra:BAABLgAECn8YAAQHAAgJ9hP9XgCKAQAHAAcJSRX9XgCKAQAnAAMJLxRhHwC0AAAdAAIJ3geTEgA6AAAAAA==.Retrix:BAAALgAECgIJAwAAAA==.Revorra:BAAALgAECgcJCAABLgAECgkJNQAbALAYAA==.',
Ri='Ristvakbaen:BAACLgAFFH8EAAITAAIJVRqZkwCbAAATAAIJVRqZkwCbAAAuAAQKfzoABBQACQnmJEEDAIYCABQACAlGJUEDAIYCABMACQm8HbofAGYCABIABgk9JRYGAAQCAAAA.',
Ro='Robynlee:BAABLgAECn9SAAILAAgJpRpzAgBXAgALAAgJpRpzAgBXAgAAAA==.Roccobb:BAAALgADCgYJBgAAAA==.Rogùe:BAAALgAFFAIJAgAAAA==.Rosebelle:BAAALgAECgQJAwAAAA==.Roshu:BAAALgADCgEJAQAAAA==.',
Ru='Rugratt:BAAALgADCgQJBAABLgADCgcJDgADAAAAAA==.',
Sa='Saeler:BAAALgAECgMJAwAAAA==.Sailrmoonkin:BAAALgAECgQJBQABLgAFFAMJBgAMABUVAA==.Samoth:BAAALgADCgEJAQAAAA==.Sanathein:BAAALgADCgcJBwAAAA==.Sanctuary:BAAALgAECgQJBAAAAA==.Santeclair:BAAALgAECgEJAQAAAA==.Satin:BAAALgAECggJDQAAAA==.',
Sc='Sceryna:BAACLgAFFH8GAAIRAAMJKA9eOQCzAAARAAMJKA9eOQCzAAAuAAQKfygAAhEACQnMF0FJAOoBABEACQnMF0FJAOoBAAAA.Schiftly:BAAALgAFFAIJAgAAAA==.Schwiggity:BAAALgAECgQJCgABLgAECgkJGwARAFwSAA==.Scottlock:BAABLgAECn8WAAISAAcJqh6QBQAVAgASAAcJqh6QBQAVAgABLgAECgkJLgAjAAIjAA==.Screwbrew:BAAALgAECgIJAgAAAA==.Screwid:BAAALgAECgQJBAAAAA==.Screwtotems:BAAALgAECgEJAQAAAA==.Scrmndemn:BAABLgAECn80AAIRAAkJdAidpAAwAQARAAkJdAidpAAwAQAAAA==.Scytale:BAAALgAECgkJCQAAAA==.',
Se='Sepviva:BAABLgAECn8VAAIBAAcJNhZmcACoAQABAAcJNhZmcACoAQAAAA==.Serea:BAAALgAECgEJAQABLgAECgkJUgALAKUaAA==.Serpent:BAACLgAFFH8OAAIFAAYJ5BS9CgCDAQAFAAYJ5BS9CgCDAQAuAAQKfyMAAgUACQlnHxkIAHoCAAUACQlnHxkIAHoCAAEuAAUUCQkmAAwAvBEA.',
Sh='Shadowheal:BAAALgADCgUJBgAAAA==.Shamadeus:BAAALgADCgUJBQABLgAFFAIJBAATAFUaAA==.Shamtastical:BAAALgAECggJCwABLgAECgkJUgALAKUaAA==.Sharaseth:BAAALgAECggJEQAAAA==.Shikita:BAABLgAECn9MAAMWAAkJnB51DQDvAgAWAAkJnB51DQDvAgAYAAEJHAZfigAlAAAAAA==.Shimadin:BAACLgAFFH8gAAIRAAYJphdmOAA8AQARAAYJphdmOAA8AQAuAAQKfykAAhEACQkfHvszADACABEACQkfHvszADACAAAA.Shimbuktu:BAAALgAECgEJAwABLgAFFAYJIAARAKYXAA==.Shimfu:BAAALgAECgEJAgABLgAFFAYJIAARAKYXAA==.Shimjun:BAAALgAECgUJCwABLgAFFAYJIAARAKYXAA==.Shimpbizkit:BAABLgAECn8ZAAIfAAcJAg0VnwA8AQAfAAcJAg0VnwA8AQABLgAFFAYJIAARAKYXAA==.Shimsong:BAAALgAECgYJEwABLgAFFAYJIAARAKYXAA==.Shmerek:BAABLgAECn8XAAIFAAkJRSBCCAB3AgAFAAkJRSBCCAB3AgAAAA==.',
Si='Sidarien:BAAALgADCgQJBAAAAA==.Silenttits:BAAALgAECgEJAgAAAA==.Silveralae:BAAALgAECgEJAQAAAA==.Silveraven:BAAALgADCgIJAgAAAA==.Silverlumen:BAAALgAFFAEJAgAAAA==.Silversaevus:BAAALgAFFAEJAQAAAA==.Silverstream:BAACLgAFFH8IAAIWAAMJGgqLSQCUAAAWAAMJGgqLSQCUAAAuAAQKfyoAAhYACQnoER1CAJkBABYACQnoER1CAJkBAAAA.',
Sk='Skyblue:BAAALgADCgEJAQAAAA==.',
Sl='Slea:BAABLgAECn8VAAIdAAkJQxApFAAEAgAdAAkJQxApFAAEAgAAAA==.Slease:BAAALgAECgYJBgAAAA==.',
Sm='Smallrichard:BAAALgAECgEJAQAAAA==.Smootish:BAAALgADCgUJBQAAAA==.',
So='Solbin:BAAALgAECgUJDAABLgAECgkJMAAfAIYZAA==.Solitudé:BAABLgAECn8fAAMTAAgJBiSWHwBnAgATAAcJPiGWHwBnAgAUAAUJoSW1FAAoAQABLgAFFAUJFAANAP4fAA==.Soteirian:BAABLgAECn8zAAMRAAkJpAuIcgCJAQARAAkJpAuIcgCJAQAlAAEJjwJKXwASAAAAAA==.',
Sp='Spam:BAAALgAECgIJAgAAAA==.Spekey:BAAALgAECgEJAQAAAA==.Spider:BAABLgAECn9DAAIBAAkJuh3kAwCaAgABAAkJuh3kAwCaAgAAAA==.Spineymagus:BAAALgADCgIJAgAAAA==.',
Sq='Squall:BAABLgAECn8rAAMiAAgJMhCNRwCQAQAiAAgJMhCNRwCQAQAJAAYJ0ROVRQAdAQAAAA==.',
St='Stalariais:BAAALgAECgQJBAABLgAECgEJAQADAAAAAA==.Stardrand:BAAALgADCgUJBgAAAA==.Steeg:BAAALgAECgYJEQAAAA==.Steelreserve:BAAALgAECgYJDQAAAA==.Steve:BAAALgAECgYJBgAAAA==.Straw:BAAALgAECgYJCwABLgAECgkJQwARAGgkAA==.',
Su='Sugarkitty:BAAALgADCgYJCgAAAA==.Supahot:BAAALgAECgEJAQAAAA==.Supereclipse:BAABLgAECn9IAAIHAAkJ/hZDKQA5AgAHAAkJ/hZDKQA5AgAAAA==.',
Sw='Swolareclips:BAAALgADCgYJBgAAAA==.',
Sy='Sydvicious:BAABLgAECn8iAAIOAAkJPCVYBAAEAwAOAAkJPCVYBAAEAwAAAA==.Sylvia:BAAALgADCgEJAQAAAA==.Syriene:BAABLgAECn8uAAICAAkJPBByEQCjAQACAAkJPBByEQCjAQAAAA==.',
Ta='Taladiir:BAAALgAECgEJAQAAAA==.Talana:BAAALgAECgEJAQAAAA==.Tankhealz:BAAALgAECgMJBQAAAA==.Tanthe:BAAALgAECgMJAwAAAA==.Tayger:BAAALgAFFAEJAQAAAA==.',
Tb='Tbsp:BAAALgAECgEJAQABLgAFFAUJFgAKAEocAA==.',
Te='Tecks:BAABLgAECn8XAAILAAkJwgWfPAABAQALAAkJwgWfPAABAQAAAA==.Teddy:BAAALgAECgUJCQAAAA==.Teslá:BAAALgAECgYJCgAAAA==.Texican:BAAALgAECgEJAQAAAA==.',
Th='Theatrix:BAAALgAECgQJBwABLgAECggJKQAFAKoTAA==.Thecuckler:BAAALgAECgQJCAAAAA==.Thefreeman:BAAALgAECgEJAQAAAA==.Themajor:BAABLgAECn8uAAMGAAkJFhfmDAAYAgAGAAkJFhfmDAAYAgAbAAcJ/AhwTAB0AQAAAA==.Then:BAAALgADCgEJAQAAAA==.Thiarad:BAAALgADCgEJAQAAAA==.Thiaraxo:BAACLgAFFH8JAAMKAAMJHyGDHgDOAAAKAAMJHyGDHgDOAAAEAAEJjhYtHQBIAAAuAAQKfxUAAgoACQmbBcp5ALAAAAoACQmbBcp5ALAAAAAA.Thrain:BAAALgADCgcJDAAAAA==.Threat:BAABLgAECn8mAAIRAAkJlCWXBQBHAwARAAkJlCWXBQBHAwAAAA==.Thronkall:BAAALgAECgkJAgAAAA==.Thsarus:BAABLgAECn8vAAMPAAgJ6yDlHABnAgAPAAgJ6yDlHABnAgAkAAQJHBHQGwCxAAAAAA==.Thunderthigh:BAAALgAECgIJAgAAAA==.',
Ti='Tiamaat:BAABLgAECn8XAAIWAAkJmgQKegDJAAAWAAkJmgQKegDJAAAAAA==.Tireyne:BAAALgADCgEJAgAAAA==.Titus:BAAALgAECgEJBgAAAA==.',
Tk='Tkt:BAAALgAECgIJBAABLgAECgUJCQADAAAAAA==.',
To='Toatani:BAAALgAECgYJDgAAAA==.Tokkaebi:BAAALgAECgkJDAAAAA==.',
Tr='Treadlightly:BAAALgADCgUJBwAAAA==.Treefróg:BAAALgAECgUJBQAAAA==.Trentus:BAAALgADCgIJAgAAAA==.Trev:BAAALgAECgUJBgABLgAFFAUJBQATAIUWAA==.Trotem:BAAALgAECgUJBQAAAA==.',
Ts='Tsp:BAACLgAFFH8WAAIKAAUJShwOHACSAQAKAAUJShwOHACSAQAuAAQKfywAAwoACQn/Gd8cADECAAoACQn/Gd8cADECAB4ABAnxA0psAJEAAAAA.',
Ty='Tyletos:BAABLgAECn8wAAIfAAkJhhnXCgC3AQAfAAkJhhnXCgC3AQAAAA==.',
Ug='Ugolok:BAABLgAECn8pAAMNAAcJ7gfrIQC/AAABAAcJKQWY2wDZAAANAAYJzQjrIQC/AAAAAA==.',
Ur='Uriél:BAABLgAECn8yAAIPAAkJNSWeAgBeAwAPAAkJNSWeAgBeAwABLgAFFAUJFAANAP4fAA==.',
Va='Valeene:BAABLgAECn8uAAIYAAkJLiJSBAAcAwAYAAkJLiJSBAAcAwAAAA==.Valkion:BAAALgAECgEJAQAAAA==.Varek:BAABLgAECn8YAAIXAAkJ5yEyAwAbAwAXAAkJ5yEyAwAbAwAAAA==.Varlann:BAAALgADCgkJCQAAAA==.',
Ve='Veiler:BAABLgAECn9GAAMHAAkJEROKNgADAgAHAAkJEROKNgADAgAnAAEJ3wH2lgAhAAAAAA==.Velca:BAAALgAECgIJAgAAAA==.Veruca:BAAALgAECgMJAwAAAA==.Veviseron:BAABLgAECn8qAAIfAAkJNwSvpgAwAQAfAAkJNwSvpgAwAQAAAA==.',
Vh='Vhye:BAABLgAFFH8IAAIiAAMJtgZnZAB+AAAiAAMJtgZnZAB+AAAAAA==.',
Vi='Vidnoi:BAAALgAECgEJBAAAAA==.Vincentfreak:BAAALgAECgcJBwAAAA==.Vinstalation:BAABLgAECn81AAINAAkJcRwxBgBHAgANAAkJcRwxBgBHAgAAAA==.Vissa:BAAALgADCgYJBgAAAA==.',
Vo='Vonbismarck:BAABLgAECn8lAAMHAAkJ8hOSTQC5AQAHAAkJ8hOSTQC5AQAnAAEJFw/CDgAwAAAAAA==.',
Vr='Vritraz:BAACLgAFFH8UAAMNAAUJ/h9wCABnAQANAAQJ/h9wCABnAQABAAEJAACtLQEAAAAuAAQKfxUAAw0ACQmLIqEGADkCAA0ABwk+I6EGADkCAAEAAgl0IAP3ALcAAAAA.Vrock:BAAALgAECgEJAQABLgAECgkJLwAfAHIeAA==.',
Vy='Vynian:BAAALgAECgEJAwAAAA==.',
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
Ze='Zearas:BAABLgAECn8UAAIBAAgJJxE+kwBZAQABAAgJJxE+kwBZAQAAAA==.Zendonn:BAABLgAECn8bAAIEAAcJxwUiUgDAAAAEAAcJxwUiUgDAAAAAAA==.Zerk:BAAALgAECgEJAQAAAA==.Zevel:BAAALgADCgIJAgAAAA==.',
Zi='Zicatriz:BAAALgADCgcJDgAAAA==.',
Zo='Zodiaac:BAABLgAECn8XAAIMAAkJdxm1FQC+AQAMAAkJdxm1FQC+AQAAAA==.',
Zu='Zuggy:BAAALgAFFAEJAQABLgAFFAMJEQAQABMaAA==.',
Zy='Zy:BAAALgADCgUJBQAAAA==.',
['Zà']='Zàknafein:BAABLgAECn8lAAMUAAcJgxZ0AgCUAQAUAAcJgxZ0AgCUAQATAAMJ3wVbMwBBAAAAAA==.',
['Ëc']='Ëchõ:BAABLgAECn8gAAMWAAkJ+RXSNwDIAQAWAAkJ+RXSNwDIAQAYAAIJvwRldwBHAAAAAA==.',
['Ðï']='Ðï:BAAALgADCgQJBAABLgAECgkJLAAVAAcdAA==.',
['ßo']='ßoomer:BAAALgADCgIJAgABLgAECgUJCwADAAAAAA==.',
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
