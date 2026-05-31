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

local lookup = {'Monk-Windwalker','Shaman-Elemental','Monk-Mistweaver','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Augmentation','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Rogue-Subtlety','Druid-Restoration','Druid-Balance','Evoker-Preservation','Paladin-Retribution','Evoker-Devastation','Warrior-Protection','Warrior-Fury','DeathKnight-Blood','Paladin-Holy','Monk-Brewmaster','Mage-Frost','Druid-Guardian','Rogue-Assassination','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Shaman-Restoration','Priest-Discipline','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Protection','Priest-Holy','Rogue-Outlaw','Druid-Feral','Warrior-Arms','Hunter-Marksmanship',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abominable:BAAALgADCgEJAQAAAA==.',
Ag='Agden:BAAALgADCgEJAQAAAA==.',
Al='Alaìrn:BAAALgAECgUJCwAAAA==.Alenciann:BAAALgAECgMJBwAAAA==.Alys:BAABLgAECn8xAAIBAAgJoQ6IJQBwAQABAAgJoQ6IJQBwAQAAAA==.',
Am='Amaniatres:BAAALgAECgQJDgAAAA==.Ammartin:BAAALgAECgYJDAAAAA==.Amoonranara:BAAALgADCgEJAQAAAA==.',
An='Anaan:BAAALgAECgUJBQAAAA==.Angrylizard:BAAALgAECgEJAgAAAA==.Anklebiterr:BAAALgAECgUJBwAAAA==.',
Ap='Apothecary:BAAALgADCgcJBwAAAA==.',
Ar='Arabella:BAAALgADCgYJBgAAAA==.Arandomidiot:BAAALgADCgYJBgAAAA==.Arathan:BAAALgADCgkJGgAAAA==.Ariiana:BAAALgAECgkJDwAAAA==.',
As='Asapshocky:BAACLgAFFH8OAAICAAYJthlADgCGAQACAAYJthlADgCGAQAuAAQKfy4AAgIACQnTIw8EABUDAAIACQnTIw8EABUDAAAA.Asclepios:BAAALgAECgMJBAAAAA==.Asmoday:BAAALgAECgUJBQAAAA==.Astraroth:BAAALgADCgQJBAAAAA==.',
Av='Avella:BAAALgADCgUJBwAAAA==.',
Ba='Balaris:BAAALgADCgcJBwABLgAECgkJIwADACEUAA==.Bamwham:BAAALgADCgcJBwAAAA==.Barrii:BAAALgAECgMJBQAAAA==.',
Be='Bearblaster:BAAALgADCgQJBAABLgAECgQJBgAEAAAAAA==.Bearlytanks:BAAALgADCgIJAgAAAA==.Beastwallker:BAAALgADCgQJBAAAAA==.Bellabelle:BAAALgAECgQJBAAAAA==.Ben:BAAALgAECgcJEwAAAA==.Betamaxx:BAAALgAECgYJDgAAAA==.Betterx:BAAALgAECgQJBQAAAA==.Bevian:BAAALgADCgIJAgABLgADCgcJDwAEAAAAAA==.',
Bi='Biggiepants:BAABLgAECn8cAAMFAAkJ5RwxGgCNAQAFAAkJ5RwxGgCNAQAGAAgJ9w5rVgBrAQAAAA==.Bighead:BAAALgAECgYJCAABLgAFFAMJBwABALYHAA==.Bigwarlocks:BAAALgAECgMJBwABLgAFFAMJBwABALYHAA==.Bintje:BAAALgADCgcJEgAAAA==.Biollante:BAAALgAECgcJCwAAAA==.',
Bl='Blindedlïght:BAAALgAECgUJBgAAAA==.',
Bo='Bolsan:BAAALgAECgMJBQAAAA==.Bonq:BAAALgAECgIJAgABLgAECgkJEQAFACUcAA==.Bootyßandaid:BAABLgAFFH8GAAIHAAMJXxTSNQDMAAAHAAMJXxTSNQDMAAABLgAFFAQJCwAIAH4XAA==.Bourg:BAAALgAECgYJCAAAAA==.Bowhemian:BAAALgAECgMJBgAAAA==.',
Bu='Buckis:BAAALgAECgYJEAAAAA==.Bufú:BAAALgADCgIJAgAAAA==.',
['Bö']='Böurbon:BAAALgADCgkJCgAAAA==.',
Ca='Cahk:BAAALgAECgIJAgAAAA==.Cajia:BAABLgAECn8nAAMJAAgJRwswGQDGAAAKAAgJtQmMcQBMAQAJAAYJBgswGQDGAAAAAA==.Canon:BAAALgAECgkJAQAAAA==.',
Ce='Celds:BAAALgADCgQJBAABLgAECgcJGQALAPEbAA==.Celiae:BAAALgAECgYJEAAAAA==.Cendanel:BAAALgAECgIJAgAAAA==.',
Ch='Childress:BAAALgAECgMJAwAAAA==.Chiwhiz:BAAALgAECgEJAQABLgAECgQJCwAEAAAAAA==.Choggy:BAABLgAECn8qAAIMAAgJKRslFQAHAgAMAAgJKRslFQAHAgAAAA==.Chogs:BAAALgAECgIJAgABLgAECggJKgAMACkbAA==.',
Ci='Cimbline:BAAALgADCgIJAgAAAA==.',
Cl='Clairerick:BAAALgAECgYJEAAAAA==.',
Co='Confessionn:BAAALgADCggJDAAAAA==.Cough:BAAALgAECgMJBgABLgAFFAMJBwABALYHAA==.',
Cr='Crinklecut:BAABLgAECn8YAAINAAgJQQwJIQByAQANAAgJQQwJIQByAQAAAA==.Critos:BAAALgADCgcJBwAAAA==.Crotchout:BAAALgADCgMJAwAAAA==.Crybaby:BAAALgADCgEJAQAAAA==.Crystilpixy:BAAALgADCgMJBAAAAA==.',
['Cé']='Céline:BAAALgAECgEJAQAAAA==.',
Da='Danilov:BAAALgADCgYJBgAAAA==.',
De='Deadlyshift:BAABLgAECn8XAAMOAAkJsCKyBABiAwAOAAkJsCKyBABiAwAPAAUJMho8NgBjAQAAAA==.Deadybear:BAAALgADCggJDAABLgAECgkJSgAQAFMSAA==.Deathkyter:BAAALgAECgEJAQAAAA==.Delrok:BAAALgAECgEJAgAAAA==.Dephias:BAAALgADCgMJAwAAAA==.',
Di='Diagnosis:BAABLgAECn8eAAIRAAkJhSVwCAAUAwARAAkJhSVwCAAUAwAAAA==.',
Do='Donnabb:BAAALgAECggJEgAAAA==.Donteatbees:BAAALgADCgYJBgAAAA==.Dop:BAAALgAECgEJAQAAAA==.Doran:BAABLgAECn8XAAIFAAgJpQ5MHQBtAQAFAAgJpQ5MHQBtAQAAAA==.Doriathrin:BAAALgADCgcJCwAAAA==.Doujinshi:BAABLgAECn8OAAIGAAcJIBziUwCoAQAGAAcJIBziUwCoAQAAAA==.',
Dr='Draedis:BAAALgAECgMJCAAAAA==.Dragonbladez:BAAALgADCgUJBQAAAA==.Dragoneye:BAAALgAECgMJBgAAAA==.Dragonhawk:BAAALgADCgQJBAABLgAECgMJEgAEAAAAAA==.Dragonname:BAAALgAECgEJAQAAAA==.Drakoil:BAABLgAECn8xAAMSAAgJORkyBgDdAQASAAgJMhYyBgDdAQAHAAcJNxPPLgBgAQAAAA==.Dreademperor:BAACLgAFFH8JAAITAAQJdBVvFADjAAATAAQJdBVvFADjAAAuAAQKfycAAxMACQkhHvAEAPYCABMACQkhHvAEAPYCABQABAlDDx9YANUAAAEuAAUUBQkMABUAJR8A.Dreadnature:BAAALgAECgMJAwAAAA==.Dreadnight:BAABLgAFFH8MAAIVAAUJJR9oEABDAQAVAAUJJR9oEABDAQAAAA==.Dreadsteed:BAAALgAECgEJAQABLgAFFAUJDAAVACUfAA==.Dreadweaver:BAAALgADCgUJBQABLgAFFAUJDAAVACUfAA==.Drenrah:BAABLgAECn8nAAIWAAkJug+xJwC3AQAWAAkJug+xJwC3AQAAAA==.Drgndeeznutz:BAACLgAFFH8LAAIIAAQJfhcPDwBDAQAIAAQJfhcPDwBDAQAuAAQKfycAAggACQnPHywEAOICAAgACQnPHywEAOICAAAA.Drizz:BAAALgAECgIJAwAAAA==.Drizzaer:BAAALgAECgEJAgAAAA==.Drunkenrage:BAACLgAFFH8lAAIXAAgJOxwBAgBwAgAXAAgJOxwBAgBwAgAuAAQKfx4AAhcACQkcIvsBAIIDABcACQkcIvsBAIIDAAAA.',
Du='Dumorius:BAAALgAECgYJCAAAAA==.',
['Dé']='Déx:BAAALgAECgYJCwAAAA==.',
Ed='Edaddylock:BAAALgADCgUJBQAAAA==.Edreth:BAAALgAECgEJAQAAAA==.',
El='Elbryan:BAABLgAECn8xAAIMAAkJhAgRLABVAQAMAAkJhAgRLABVAQAAAA==.Elementdemon:BAAALgAECgUJBgAAAA==.Ellabelle:BAAALgADCgMJAwAAAA==.',
En='Enthalpy:BAABLgAECn8hAAIYAAkJGhtrTwDWAQAYAAkJGhtrTwDWAQAAAA==.',
Er='Erakazsod:BAAALgAECgEJAQAAAA==.Erazath:BAAALgAECgUJCAABLgAECgkJEAAEAAAAAA==.',
Es='Esperzoa:BAABLgAECn8dAAIVAAgJUBqbDgAFAgAVAAgJUBqbDgAFAgAAAA==.',
Et='Eternaldread:BAAALgADCgUJBQABLgAFFAUJDAAVACUfAA==.',
Eu='Eucalicdes:BAABLgAECn9CAAIZAAkJvhc/CwAPAgAZAAkJvhc/CwAPAgAAAA==.',
Ez='Ezal:BAAALgAECgYJCAAAAA==.Ezra:BAAALgADCgYJBgAAAA==.',
Fa='Fallyn:BAAALgAECgEJAQAAAA==.Farshran:BAAALgAECgkJEAAAAA==.Fate:BAAALgAECgQJBQABLgAECgkJJQARAJQlAA==.Fathermajor:BAAALgADCgYJBgAAAA==.',
Fe='Felicity:BAACLgAFFH8WAAINAAUJ2h2DFQBEAQANAAUJ2h2DFQBEAQAuAAQKfzYAAw0ACQmWIpIEAE4DAA0ACQmWIpIEAE4DABoABQmDDaYTANgAAAAA.Ferendis:BAABLgAECn8nAAIGAAgJPiMdEQCnAgAGAAgJPiMdEQCnAgAAAA==.Fernard:BAAALgADCgYJBgABLgAECgkJEQAFACUcAA==.',
Fl='Florita:BAAALgAECgUJBQAAAA==.Flydormu:BAAALgAECgYJCQABLgAECgkJIwAYAFYYAA==.',
Fo='Fordinn:BAABLgAECn8uAAMUAAkJlRi1IgDJAQAUAAkJCxW1IgDJAQATAAcJgRQCGgBTAQAAAA==.',
Fr='Fractured:BAAALgADCgEJAQAAAA==.Freelor:BAAALgAECgIJBAAAAA==.Freemi:BAAALgAECgEJAQAAAA==.Frigidgrip:BAAALgAECgMJAwAAAA==.',
Fu='Fuddytwo:BAABLgAECn8ZAAIPAAgJjhtsEwAjAgAPAAgJjhtsEwAjAgAAAA==.',
Ga='Garzhvog:BAAALgADCgcJCwABLgAECgkJOAALAOYkAA==.Gasket:BAACLgAFFH8NAAMbAAQJRhqCRgBEAQAbAAQJ/BeCRgBEAQAcAAMJNBb/DgDmAAAuAAQKfyUAAxsACQlnIsMiALQCABsACQlvIcMiALQCABwAAwkcIMUTABIBAAAA.Gauteng:BAAALgAECgIJAgABLgAFFAQJDAARAHwiAA==.',
Gh='Ghidõráh:BAAALgAECgEJAQAAAA==.Ghorac:BAAALgADCgYJDAAAAA==.Ghoti:BAAALgADCgUJBQAAAA==.Ghoulz:BAAALgADCgcJDAAAAA==.',
Gl='Glazedham:BAAALgADCgMJAwAAAA==.',
Gn='Gnollfang:BAAALgADCgYJBgAAAA==.',
Go='Gorbubbli:BAAALgADCgkJGgAAAA==.',
Gr='Graceful:BAAALgAECgUJBgAAAA==.Grit:BAAALgAECgYJDAAAAA==.',
Gu='Guilddrama:BAAALgADCgEJAQAAAA==.',
Ha='Haeler:BAAALgAECgIJAwAAAA==.Haelin:BAAALgADCgEJAQAAAA==.Halgoðfulk:BAAALgAECgEJAQAAAA==.Hamwarrior:BAAALgAECgEJAQAAAA==.Handicap:BAAALgAECgcJBwABLgAECgkJHgARAIUlAA==.Hark:BAACLgAFFH8NAAIdAAQJiQyTOgAdAQAdAAQJiQyTOgAdAQAuAAQKfyoAAh0ACQkNGvc3AM4BAB0ACQkNGvc3AM4BAAAA.Harpin:BAAALgADCgEJAQAAAA==.Harvin:BAABLgAECn8zAAIQAAgJnCJPAwAGAwAQAAgJnCJPAwAGAwAAAA==.',
He='Hekus:BAAALgAECgcJEQAAAA==.Helanua:BAABLgAECn8iAAICAAgJfhHaKwB9AQACAAgJfhHaKwB9AQAAAA==.Hellsplay:BAAALgADCgIJAgAAAA==.',
Hi='Hibernate:BAAALgADCgEJAQAAAA==.Hippolytus:BAAALgADCgkJCQABLgAECgkJKgAXAM0kAA==.Hippopotamus:BAAALgAECgMJAwAAAA==.Hit:BAAALgAECgYJCwAAAA==.',
Ho='Holytide:BAABLgAECn8jAAMCAAgJqQpvOwArAQACAAgJqQpvOwArAQAeAAcJ1QX6kwCFAAAAAA==.Hope:BAABLgAECn8pAAIPAAcJ1ww1QADxAAAPAAcJ1ww1QADxAAAAAA==.Horrorfang:BAABLgAECn88AAIbAAgJdR6qIgBoAgAbAAgJdR6qIgBoAgAAAA==.',
Hu='Hukjo:BAAALgAECgcJEAABLgAECgkJIwADACEUAA==.',
Ib='Ibaar:BAACLgAFFH8VAAIHAAUJ/iOtFACDAQAHAAUJ/iOtFACDAQAuAAQKfy4AAwcACQm9I00HAAUDAAcACAk0I00HAAUDABIABgneIAcNAAoCAAAA.',
Ic='Icepickle:BAAALgADCgcJAQAAAA==.',
Ii='Iilnut:BAABLgAECn8gAAMMAAgJnCA/CwDPAgAMAAgJnCA/CwDPAgAfAAQJPBW2NwDpAAABLgAFFAQJDAADALEgAA==.',
Il='Illedren:BAABLgAECn8QAAIGAAgJwwc7kAAAAQAGAAgJwwc7kAAAAQAAAA==.',
In='Innerdemon:BAAALgAECgQJBAAAAA==.Inno:BAABLgAECn8YAAIGAAkJDiTxEwDhAgAGAAkJDiTxEwDhAgAAAA==.',
Is='Isabel:BAAALgAECgYJBgABLgAECggJEQAEAAAAAA==.',
It='Ithacus:BAABLgAECn8nAAIgAAkJSBDNDgClAQAgAAkJSBDNDgClAQAAAA==.',
Ja='Jandaar:BAAALgAECgEJAQAAAA==.Jattao:BAAALgADCgEJAQAAAA==.',
Jd='Jdawgprime:BAAALgADCgcJBwAAAA==.',
Je='Jenjas:BAAALgAECgUJBQAAAA==.',
Ji='Jinnlee:BAAALgAECgUJBgAAAA==.Jinoo:BAABLgAECn87AAICAAgJBB6CEQBOAgACAAgJBB6CEQBOAgAAAA==.Jinufan:BAAALgAECgUJBwABLgAFFAUJFQAHAP4jAA==.',
Jo='Joe:BAAALgAECgcJCgAAAA==.Jorek:BAABLgAECn8WAAIUAAkJ7BTcIwDBAQAUAAkJ7BTcIwDBAQAAAA==.',
Ju='Jugulator:BAAALgADCgcJDQAAAA==.',
Ka='Kaejung:BAAALgAECgQJBAAAAA==.Kaihune:BAAALgADCgIJAgAAAA==.Kainairobi:BAAALgAECgUJBQAAAA==.Kaiva:BAAALgAECgQJBgAAAA==.Kallistô:BAAALgADCgYJBgAAAA==.Kamigawa:BAAALgAECgYJEwAAAA==.Kavik:BAABLgAECn8fAAIWAAkJHhkRDwCPAgAWAAkJHhkRDwCPAgAAAA==.Kazbodan:BAAALgADCgkJFQAAAA==.',
Ke='Keemo:BAACLgAFFH8NAAIVAAQJnBAHGgDsAAAVAAQJnBAHGgDsAAAuAAQKfykAAxUACQnJFcEdAE4BABUACQmpFcEdAE4BABsAAwmYDUX8AIMAAAAA.Keemosaki:BAAALgAECgcJEgAAAA==.Keemõ:BAABLgAECn8XAAMGAAYJvw2GkADgAAAGAAYJ0wyGkADgAAAhAAYJowkGHQCZAAAAAA==.Keflá:BAAALgAECgQJDAAAAA==.Keysersöze:BAAALgADCgYJBwAAAA==.',
Kh='Khaas:BAABLgAECn89AAIbAAgJ8Q7YZACKAQAbAAgJ8Q7YZACKAQAAAA==.Khaleeb:BAAALgAECgEJAwAAAA==.',
Ki='Kierios:BAABLgAECn8fAAMcAAgJmRZgDQBwAQAbAAgJ3RCPXwCWAQAcAAcJzBNgDQBwAQAAAA==.Kildurgan:BAAALgAECgQJDQAAAA==.Killawarlock:BAABLgAECn8hAAQKAAgJzCLaOADqAQAKAAcJNSDaOADqAQALAAQJbCLwEAAyAQAJAAEJ/hAbcAA2AAAAAA==.Kironn:BAAALgADCgYJBgABLgAFFAMJBwABALYHAA==.',
Kk='Kkain:BAAALgAECgIJBwAAAA==.',
Ko='Korihor:BAABLgAECn8cAAIiAAgJGRtJCgANAgAiAAgJGRtJCgANAgAAAA==.',
Kr='Krestus:BAABLgAECn8RAAMFAAcJJRwOOAC3AAAGAAYJrxkZfgAvAQAFAAMJKSAOOAC3AAAAAA==.Krispy:BAABLgAECn8tAAQBAAgJdxblGQDKAQABAAgJdxblGQDKAQAXAAUJEAc9VQCgAAADAAUJvgO5TgCZAAAAAA==.Krith:BAAALgADCgYJCQAAAA==.Krix:BAAALgAECgMJBAAAAA==.',
Ky='Kyndil:BAAALgAECgYJCgAAAA==.',
La='Laerin:BAAALgADCgYJBgAAAA==.Laxus:BAAALgADCgcJDAABLgAECgkJGAASAHkMAA==.Lazarius:BAAALgADCgQJBAAAAA==.',
Le='Levophed:BAABLgAECn8uAAIbAAcJkg/emQAgAQAbAAcJkg/emQAgAQAAAA==.',
Li='Liangwei:BAAALgAECgMJAwABLgAFFAMJBwAdAPMdAA==.Lightfallen:BAAALgAECgcJEQAAAA==.Liisara:BAABLgAECn8bAAIGAAgJZggRfwAGAQAGAAgJZggRfwAGAQAAAA==.Lily:BAABLgAECn8vAAIZAAgJIxr0DgDVAQAZAAgJIxr0DgDVAQAAAA==.Linadra:BAABLgAECn8qAAIRAAkJgwn0gwBMAQARAAkJgwn0gwBMAQAAAA==.Linzur:BAAALgADCgEJAQAAAA==.Littleyeti:BAAALgAECgMJAwAAAA==.Liyara:BAACLgAFFH8MAAIRAAQJfCL4FQCKAQARAAQJfCL4FQCKAQAuAAQKfykAAhEACQm1JUgRAAYDABEACQm1JUgRAAYDAAAA.',
Ll='Llorsa:BAABLgAECn85AAIjAAgJ1xcoFAAfAgAjAAgJ1xcoFAAfAgAAAA==.',
Lo='Lohhan:BAAALgADCgUJCQAAAA==.Lolamontez:BAAALgAECgIJAgAAAA==.Lorachka:BAAALgADCgIJAgAAAA==.Lorthys:BAAALgADCgEJAQAAAA==.',
Lu='Luxian:BAABLgAECn8xAAIRAAgJ7w2PgABTAQARAAgJ7w2PgABTAQAAAA==.',
Ma='Mahiru:BAAALgADCgEJAQAAAA==.Mahralla:BAAALgADCgIJAgAAAA==.Maikagond:BAAALgAECgQJCAABLgAECggJJgARABALAA==.Makaria:BAAALgAECggJEAAAAA==.Malbisa:BAAALgAECgQJBQAAAA==.Malphoz:BAAALgAECgIJAgAAAA==.Mandragora:BAAALgAECgYJEwAAAA==.Marli:BAAALgADCgEJAQAAAA==.Mattieatzdot:BAAALgAECgQJBQAAAA==.',
Mc='Mcgrowlin:BAAALgAECgQJCwAAAA==.',
Me='Mekator:BAAALgAECgQJBAAAAA==.Meko:BAAALgAECgUJBwAAAA==.Mew:BAAALgAECgEJAgAAAA==.',
Mi='Mickey:BAACLgAFFH8IAAIBAAQJJwvUFwD0AAABAAQJJwvUFwD0AAAuAAQKfygAAgEACQkTIrYFAOICAAEACQkTIrYFAOICAAAA.Migraine:BAAALgAECgYJCgAAAA==.Mikiik:BAABLgAECn81AAIKAAgJUgs0ZwBkAQAKAAgJUgs0ZwBkAQAAAA==.Mildoo:BAABLgAECn8rAAILAAkJBA+SCQCoAQALAAkJBA+SCQCoAQAAAA==.Milkymoo:BAABLgAECn8WAAITAAUJkhInKgDLAAATAAUJkhInKgDLAAAAAA==.Millina:BAAALgADCgIJAgABLgAECggJMQABAKEOAA==.Mimira:BAAALgADCgEJAQAAAA==.Minipal:BAAALgAECgcJDgAAAA==.Mixednuts:BAACLgAFFH8MAAIDAAQJsSDVFQB7AQADAAQJsSDVFQB7AQAuAAQKfycAAwMACQmiIjsDAHMDAAMACQmiIjsDAHMDAAEABgkoIKofANoBAAAA.',
Mo='Mochii:BAAALgADCgYJBgAAAA==.Moneyshock:BAAALgAECgYJBgABLgAFFAQJCwAIAH4XAA==.Monq:BAABLgAECn8XAAMBAAgJBBh8GQDOAQABAAgJBBh8GQDOAQAXAAEJyAkqjQAqAAAAAA==.Moonamber:BAAALgADCgQJBgAAAA==.Morithus:BAAALgADCgkJDgAAAA==.Morphinzerr:BAAALgAECgEJAQAAAA==.',
Mu='Murdrmittens:BAAALgADCgEJAQAAAA==.',
My='Mythion:BAABLgAECn8hAAMOAAgJBxg+KwDrAQAOAAgJBxg+KwDrAQAPAAQJCQVqYQB0AAAAAA==.Mythoridan:BAAALgAECgEJAQAAAA==.',
Na='Naeres:BAABLgAECn8fAAIbAAgJkBd6ZACLAQAbAAgJkBd6ZACLAQAAAA==.Nafari:BAAALgAECggJCAAAAA==.Naofummi:BAAALgAECgcJBwAAAA==.Naomii:BAABLgAECn8pAAMjAAkJ9hbQGQDlAQAjAAkJ9hbQGQDlAQAMAAUJZQizUAClAAAAAA==.Narus:BAAALgAECgcJCgABLgAECgkJLgAUAJUYAA==.Naturefury:BAAALgADCgEJAQAAAA==.',
Ne='Neeston:BAACLgAFFH8HAAIOAAMJzBJmMwDRAAAOAAMJzBJmMwDRAAAuAAQKfyIAAw4ACAkJI9INANoCAA4ACAkJI9INANoCAA8AAQllEtyAADAAAAEuAAUUBAkLAAgAfhcA.Neodin:BAABLgAECn8eAAIUAAgJWQ++LACMAQAUAAgJWQ++LACMAQAAAA==.Nephadin:BAAALgADCgUJAwABLgAECgkJJwAiANchAA==.Nerfed:BAAALgAECgUJCAAAAA==.Neviaa:BAABLgAECn8nAAIbAAgJ3RGXWwCgAQAbAAgJ3RGXWwCgAQAAAA==.',
Ni='Nickypoo:BAAALgAECgMJBgAAAA==.Nightmenace:BAAALgAECgcJCwAAAA==.Ninari:BAAALgADCgUJBQAAAA==.Niq:BAAALgAECgQJBAAAAA==.',
No='Nocshadue:BAAALgADCgUJBQAAAA==.Nordga:BAAALgADCgcJBwAAAA==.Nothealster:BAAALgAECgcJEwAAAA==.Nothros:BAAALgADCgQJBAAAAA==.',
Ob='Obsidiian:BAABLgAECn8UAAIkAAgJjRFRCQCBAQAkAAgJjRFRCQCBAQAAAA==.Obsidion:BAABLgAECn8UAAMjAAYJggbOTQCOAAAjAAQJDgjOTQCOAAAMAAUJ+QXEVgCMAAABLgAECgkJLgAUAJUYAA==.',
Od='Odie:BAAALgAECgYJDwAAAA==.',
On='Onemorehit:BAAALgAECgEJAgAAAA==.Onlyfangs:BAABLgAECn9KAAMQAAkJUxL8CwAFAgAQAAkJUxL8CwAFAgAHAAYJtwU6YQCOAAAAAA==.',
Os='Oscrapermort:BAAALgADCgMJAwAAAA==.',
Pa='Padivyn:BAABLgAECn8ZAAICAAgJzxjkHgDSAQACAAgJzxjkHgDSAQAAAA==.Padnamprik:BAAALgAECgQJBAAAAA==.Palidenman:BAAALgAECgIJAgAAAA==.',
Pe='Peanads:BAAALgADCgcJEAAAAA==.Pebblez:BAAALgADCgcJDgAAAA==.Perry:BAABLgAECn8pAAMOAAkJuiEhBABvAwAOAAkJuiEhBABvAwAPAAIJAQWddQBEAAAAAA==.',
Po='Po:BAAALgAECgkJCAAAAA==.Pozufuma:BAABLgAECn83AAIUAAgJGh+1DwBpAgAUAAgJGh+1DwBpAgAAAA==.',
Pr='Priestcraft:BAAALgADCgIJAgABLgAECggJCwAEAAAAAA==.',
Ps='Psychomantis:BAABLgAECn8oAAMMAAkJeRSqGgDTAQAMAAkJeRSqGgDTAQAjAAEJQgQHhQAsAAAAAA==.',
Pu='Punchypunch:BAAALgADCgkJFAAAAA==.',
Ra='Raek:BAAALgAECgQJBQABLgAECgcJGQALAPEbAA==.Ravenbyrd:BAAALgADCgMJAwAAAA==.Rawberriez:BAAALgAECgQJBgAAAA==.',
Re='Reani:BAAALgADCgQJBAAAAA==.Reapin:BAAALgADCgUJBQAAAA==.Redpool:BAABLgAECn8eAAIdAAcJaxCNQACtAQAdAAcJaxCNQACtAQAAAA==.Remithedrood:BAAALgADCgIJAgAAAA==.Reqium:BAAALgADCgYJCAAAAA==.Resto:BAAALgAECgQJBgAAAA==.Rethandra:BAAALgAECgYJEgAAAA==.',
Ri='Rion:BAABLgAECn8XAAIYAAkJcxGmWwCzAQAYAAkJcxGmWwCzAQAAAA==.Ristvakbaen:BAABLgAECn84AAQLAAkJ5iRqAgCRAgALAAgJRiVqAgCRAgAKAAkJvB2EGwBxAgAJAAYJPSUFBQAKAgAAAA==.',
Ro='Robynlee:BAABLgAECn8pAAIjAAgJZhJ/IwDKAQAjAAgJZhJ/IwDKAQAAAA==.Rogùe:BAAALgAECgQJBgAAAA==.Rosebelle:BAAALgADCgUJCQAAAA==.',
Ru='Rugratt:BAAALgADCgQJBAABLgADCgcJDgAEAAAAAA==.',
Sa='Saeler:BAAALgAECgMJAwAAAA==.Sailrmoonkin:BAAALgAECgQJBAABLgAECggJHQAVAFAaAA==.Samoth:BAAALgADCgEJAQAAAA==.Sanathein:BAAALgADCgYJBgAAAA==.Sanctuary:BAAALgAECgQJBAAAAA==.Santeclair:BAAALgAECgEJAQAAAA==.Satin:BAAALgAECggJDQAAAA==.',
Sc='Sceryna:BAABLgAECn8oAAIRAAkJzBexPwDvAQARAAkJzBexPwDvAQAAAA==.Schiftly:BAAALgAFFAIJAgAAAA==.Schwiggity:BAAALgAECgQJBgABLgAECgYJEwAEAAAAAA==.Scottlock:BAAALgAECgcJDAABLgAECgkJLAAgAF0iAA==.Scrmndemn:BAABLgAECn8nAAIRAAcJGgiptwD3AAARAAcJGgiptwD3AAAAAA==.',
Se='Sepviva:BAABLgAECn8VAAIbAAcJNhZmcACoAQAbAAcJNhZmcACoAQAAAA==.Serpent:BAACLgAFFH8KAAITAAYJCRLdCQBpAQATAAYJCRLdCQBpAQAuAAQKfyMAAhMACQlnH44GAI0CABMACQlnH44GAI0CAAAA.',
Sh='Shadowheal:BAAALgADCgUJBgAAAA==.Shamadeus:BAAALgADCgUJBQABLgAECgkJOAALAOYkAA==.Sharaseth:BAAALgAECgcJDwAAAA==.Shikita:BAABLgAECn88AAMOAAgJVx8/EwCgAgAOAAgJVx8/EwCgAgAPAAEJHAZfigAlAAAAAA==.Shimadin:BAACLgAFFH8dAAIRAAUJTxuZKwA/AQARAAUJTxuZKwA/AQAuAAQKfycAAhEACAmxHyIvAGYCABEACAmxHyIvAGYCAAAA.Shimjun:BAAALgAECgUJBgABLgAFFAUJHQARAE8bAA==.Shimpbizkit:BAABLgAECn8YAAIYAAcJ6QylkgA4AQAYAAcJ6QylkgA4AQABLgAFFAUJHQARAE8bAA==.Shimsong:BAAALgAECgYJDgABLgAFFAUJHQARAE8bAA==.Shmerek:BAABLgAECn8XAAITAAkJRSCrBgCJAgATAAkJRSCrBgCJAgAAAA==.',
Si='Sidarien:BAAALgADCgQJBAAAAA==.Silenttits:BAAALgAECgEJAgAAAA==.Silverlumen:BAAALgAECgYJEgAAAA==.Silverstream:BAABLgAECn8qAAIOAAkJ6BEdQgCZAQAOAAkJ6BEdQgCZAQAAAA==.',
Sk='Skyblue:BAAALgADCgEJAQAAAA==.',
Sl='Slea:BAAALgAECggJDgAAAA==.Slease:BAAALgADCgYJBwAAAA==.',
Sm='Smootish:BAAALgADCgUJBQAAAA==.',
So='Solbin:BAAALgAECgUJCwABLgAECgkJIwAYAFYYAA==.Solitudé:BAABLgAECn8eAAMKAAgJBiSqGwBwAgAKAAcJPiGqGwBwAgALAAUJoSVUEQAsAQABLgAFFAQJCgAcALgeAA==.Soteirian:BAABLgAECn8mAAMRAAgJEAsyjwA4AQARAAgJEAsyjwA4AQAiAAEJjwKZVQASAAAAAA==.',
Sp='Spam:BAAALgAECgIJAgAAAA==.Spekey:BAAALgAECgEJAQAAAA==.Spider:BAABLgAECn8kAAIbAAgJIBnnOAAIAgAbAAgJIBnnOAAIAgAAAA==.Spineymagus:BAAALgADCgIJAgAAAA==.',
Sq='Squall:BAABLgAECn8kAAMeAAcJ/BHwRgB2AQAeAAcJ/BHwRgB2AQACAAYJ0RNUPQAjAQAAAA==.',
St='Stalariais:BAAALgAECgQJBAABLgAECgkJGQAWAHoIAA==.Stardrand:BAAALgADCgUJBgAAAA==.Steelreserve:BAAALgAECgYJDQAAAA==.Straw:BAAALgAECgYJCwABLgAECgkJQQARAGgkAA==.',
Su='Sugarkitty:BAAALgADCgYJCgAAAA==.Supereclipse:BAABLgAECn88AAIdAAgJMRh+MwD4AQAdAAgJMRh+MwD4AQAAAA==.',
Sw='Swolareclips:BAAALgADCgYJBgAAAA==.',
Sy='Sydvicious:BAABLgAECn8iAAIFAAkJPCUPAwARAwAFAAkJPCUPAwARAwAAAA==.Syriene:BAABLgAECn8fAAIlAAYJVw/PHAD9AAAlAAYJVw/PHAD9AAAAAA==.',
Ta='Tankhealz:BAAALgAECgMJBQAAAA==.Tanthe:BAAALgAECgMJAwAAAA==.',
Tb='Tbsp:BAAALgAECgEJAQABLgAFFAUJFgADAEocAA==.',
Te='Tecks:BAABLgAECn8XAAIjAAkJwgX/NgAMAQAjAAkJwgX/NgAMAQAAAA==.Teddy:BAAALgAECgUJCQAAAA==.',
Th='Theatrix:BAAALgAECgQJBAAAAA==.Thecuckler:BAAALgAECgQJCAAAAA==.Thefreeman:BAAALgAECgEJAQAAAA==.Themajor:BAABLgAECn8eAAMmAAkJvxIREgC8AQAmAAkJphIREgC8AQAUAAcJ/AhwTAB0AQAAAA==.Then:BAAALgADCgEJAQAAAA==.Thiarad:BAAALgADCgEJAQAAAA==.Thiaraxo:BAABLgAECn8VAAIDAAkJmwV0ZgCrAAADAAkJmwV0ZgCrAAAAAA==.Thrain:BAAALgADCgcJDAAAAA==.Threat:BAABLgAECn8lAAIRAAkJlCUKBABMAwARAAkJlCUKBABMAwAAAA==.Thsarus:BAABLgAECn8vAAMGAAgJ6yCbGQBnAgAGAAgJ6yCbGQBnAgAhAAQJHBHQGwCxAAAAAA==.',
Ti='Tiamaat:BAABLgAECn8XAAIOAAkJmgSucQDOAAAOAAkJmgSucQDOAAAAAA==.Tireyne:BAAALgADCgEJAgAAAA==.Titus:BAAALgAECgEJBgAAAA==.',
To='Tokkaebi:BAAALgAECgkJAgAAAA==.',
Tr='Treadlightly:BAAALgADCgUJBwAAAA==.Treefróg:BAAALgAECgUJBQAAAA==.Trentus:BAAALgADCgIJAgAAAA==.Trev:BAAALgAECgUJBgABLgAFFAUJBQAKAIUWAA==.Trotem:BAAALgAECgUJBQAAAA==.',
Ts='Tsp:BAACLgAFFH8WAAIDAAUJShx4EgCgAQADAAUJShx4EgCgAQAuAAQKfywAAwMACQn/GU4YADACAAMACQn/GU4YADACABcABAnxA0psAJEAAAAA.',
Ty='Tyletos:BAABLgAECn8jAAIYAAkJVhi6NQAqAgAYAAkJVhi6NQAqAgAAAA==.',
Ug='Ugolok:BAABLgAECn8aAAMcAAcJ+gRhIACVAAAbAAYJ3wPW5gCvAAAcAAYJvwRhIACVAAAAAA==.',
Ur='Uriél:BAABLgAECn8sAAIGAAgJOCUkCQDyAgAGAAgJOCUkCQDyAgABLgAFFAQJCgAcALgeAA==.',
Va='Valeene:BAABLgAECn8hAAIPAAkJdyGbBAAGAwAPAAkJdyGbBAAGAwAAAA==.Varek:BAAALgAECgcJCQAAAA==.',
Ve='Veiler:BAABLgAECn9GAAMdAAkJERMQLgANAgAdAAkJERMQLgANAgAnAAEJ3wH2lgAhAAAAAA==.Velca:BAAALgAECgIJAgAAAA==.Veruca:BAAALgAECgMJAwAAAA==.Veviseron:BAABLgAECn8oAAIYAAkJqANbnAAmAQAYAAkJqANbnAAmAQAAAA==.',
Vh='Vhye:BAAALgAFFAIJAwAAAA==.',
Vi='Vinstalation:BAABLgAECn80AAIcAAkJcRzZBABLAgAcAAkJcRzZBABLAgAAAA==.Vissa:BAAALgADCgYJBgAAAA==.',
Vo='Vonbismarck:BAABLgAECn8jAAMdAAkJ8hOVQQDFAQAdAAkJ8hOVQQDFAQAnAAEJFw9rOAAuAAAAAA==.',
Vr='Vritraz:BAACLgAFFH8KAAIcAAQJuB5wBQBpAQAcAAQJuB5wBQBpAQAuAAQKfxUAAxwACQmLIjUFAD4CABwABwk+IzUFAD4CABsAAgl0IB/gALkAAAAA.Vrock:BAAALgAECgEJAQABLgAECgkJIQAYABobAA==.',
Wa='Warnam:BAAALgADCgcJBwAAAA==.Warsonge:BAAALgADCgMJAwAAAA==.',
We='Wendypini:BAACLgAFFH8NAAIdAAQJrQRKRgD4AAAdAAQJrQRKRgD4AAAuAAQKfyIAAh0ACQkAEF5FAJsBAB0ACQkAEF5FAJsBAAAA.Wetnwild:BAAALgADCgQJBAAAAA==.',
Wh='Whitehand:BAAALgAECgIJAgAAAA==.',
Wo='Wooshwoosh:BAAALgAECgQJDgAAAA==.',
Wu='Wudeeps:BAAALgAECgcJEgAAAA==.Wuhanwarrior:BAAALgAECgYJEQAAAA==.',
Ya='Yako:BAAALgAECgEJAQAAAA==.',
Ye='Yennefer:BAAALgAECgMJAwAAAA==.',
Za='Zangolf:BAAALgADCgUJBAAAAA==.Zaye:BAAALgAECgcJCgAAAA==.',
Ze='Zearas:BAABLgAECn8UAAIbAAgJJxE+kwBZAQAbAAgJJxE+kwBZAQAAAA==.Zendonn:BAABLgAECn8YAAIBAAcJvAT6SwC8AAABAAcJvAT6SwC8AAAAAA==.',
Zi='Zicatriz:BAAALgADCgcJDgAAAA==.',
Zo='Zodiaac:BAABLgAECn8XAAIVAAkJdxlxEgDMAQAVAAkJdxlxEgDMAQAAAA==.',
Zy='Zy:BAAALgADCgUJBQAAAA==.',
['Ëc']='Ëchõ:BAABLgAECn8gAAMOAAkJ+RXSNwDIAQAOAAkJ+RXSNwDIAQAPAAIJvwRldwBHAAAAAA==.',
['Ðï']='Ðï:BAAALgADCgQJBAAAAA==.',
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
