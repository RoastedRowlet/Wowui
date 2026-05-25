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

local lookup = {'Monk-Windwalker','Shaman-Elemental','Monk-Mistweaver','Unknown-Unknown','DemonHunter-Devourer','DemonHunter-Havoc','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Rogue-Subtlety','Druid-Restoration','Druid-Balance','Evoker-Preservation','Paladin-Retribution','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Fury','DeathKnight-Blood','Paladin-Holy','Monk-Brewmaster','Mage-Frost','Druid-Guardian','Rogue-Assassination','DeathKnight-Frost','DeathKnight-Unholy','Hunter-BeastMastery','Shaman-Restoration','Priest-Discipline','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Protection','Priest-Holy','Rogue-Outlaw','Druid-Feral','Warrior-Arms','Hunter-Marksmanship',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abominable:BAAALgADCgEJAQAAAA==.',
Ag='Agden:BAAALgADCgEJAQAAAA==.',
Al='Alaìrn:BAAALgAECgUJCwAAAA==.Alenciann:BAAALgAECgMJBwAAAA==.Alys:BAABLgAECn8nAAIBAAgJowjwLwAeAQABAAgJowjwLwAeAQAAAA==.',
Am='Amaniatres:BAAALgAECgQJDgAAAA==.Ammartin:BAAALgAECgYJBwAAAA==.Amoonranara:BAAALgADCgEJAQAAAA==.',
An='Anaan:BAAALgAECgUJBQAAAA==.Angrylizard:BAAALgAECgEJAgAAAA==.Anklebiterr:BAAALgAECgUJBgAAAA==.',
Ap='Apothecary:BAAALgADCgcJBwAAAA==.',
Ar='Arabella:BAAALgADCgYJBgAAAA==.Arandomidiot:BAAALgADCgYJBgAAAA==.Arathan:BAAALgADCgkJFAAAAA==.Ariiana:BAAALgAECgkJDwAAAA==.',
As='Asapshocky:BAACLgAFFH8NAAICAAUJMBhLFQA1AQACAAUJMBhLFQA1AQAuAAQKfywAAgIACAloIhILAIwCAAIACAloIhILAIwCAAAA.Asclepios:BAAALgAECgMJAwAAAA==.Asmoday:BAAALgADCgEJAQAAAA==.Astraroth:BAAALgADCgQJBAAAAA==.',
Av='Avella:BAAALgADCgUJBwAAAA==.',
Ba='Balaris:BAAALgADCgcJBwABLgAECggJIAADAHcUAA==.Bamwham:BAAALgADCgcJBwAAAA==.Barrii:BAAALgAECgMJBQAAAA==.',
Be='Bearblaster:BAAALgADCgQJBAABLgAECgQJBgAEAAAAAA==.Bearlytanks:BAAALgADCgIJAgAAAA==.Beastwallker:BAAALgADCgEJAQAAAA==.Bellabelle:BAAALgAECgQJBAAAAA==.Ben:BAAALgAECgcJEwAAAA==.Betamaxx:BAAALgAECgYJDgAAAA==.Betterx:BAAALgAECgQJBQAAAA==.Bevian:BAAALgADCgIJAgABLgAECgUJBwAEAAAAAA==.',
Bi='Biggiepants:BAABLgAECn8bAAMFAAgJoRzwTwBzAQAFAAgJ9w7wTwBzAQAGAAgJoRzwIAA1AQAAAA==.Bighead:BAAALgADCgUJCwABLgAFFAMJBwABALYHAA==.Bigwarlocks:BAAALgAECgMJBwABLgAFFAMJBwABALYHAA==.Bintje:BAAALgADCgcJEgAAAA==.Biollante:BAAALgAECgcJCwAAAA==.',
Bl='Blindedlïght:BAAALgAECgUJBgAAAA==.',
Bo='Bolsan:BAAALgAECgMJBQAAAA==.Bonq:BAAALgAECgIJAgABLgAECgkJEQAGACUcAA==.Bootyßandaid:BAAALgAFFAMJAwABLgAFFAQJCwAHAH4XAA==.Bourg:BAAALgAECgYJCAAAAA==.Bowhemian:BAAALgAECgMJBgAAAA==.',
Bu='Buckis:BAAALgAECgYJEAAAAA==.Bufú:BAAALgADCgIJAgAAAA==.',
['Bö']='Böurbon:BAAALgADCgkJCgAAAA==.',
Ca='Cahk:BAAALgAECgIJAgAAAA==.Cajia:BAABLgAECn8jAAMIAAgJRwu7FgDMAAAJAAgJtQmgaQBSAQAIAAYJBgu7FgDMAAAAAA==.Canon:BAAALgAECgkJAQAAAA==.',
Ce='Celds:BAAALgADCgQJBAABLgAECgcJGQAKAPEbAA==.Celiae:BAAALgAECgYJEAAAAA==.Cendanel:BAAALgAECgIJAgAAAA==.',
Ch='Childress:BAAALgAECgMJAwAAAA==.Choggy:BAABLgAECn8nAAILAAgJaRqFFAAEAgALAAgJaRqFFAAEAgAAAA==.',
Ci='Cimbline:BAAALgADCgIJAgAAAA==.',
Cl='Clairerick:BAAALgAECgYJEAAAAA==.',
Co='Confessionn:BAAALgADCggJDAAAAA==.Cough:BAAALgAECgIJBAABLgAFFAMJBwABALYHAA==.',
Cr='Crinklecut:BAABLgAECn8YAAIMAAgJQQzdHQB7AQAMAAgJQQzdHQB7AQAAAA==.Critos:BAAALgADCgcJBwAAAA==.Crotchout:BAAALgADCgMJAwAAAA==.Crybaby:BAAALgADCgEJAQAAAA==.Crystilpixy:BAAALgADCgMJBAAAAA==.',
['Cé']='Céline:BAAALgAECgEJAQAAAA==.',
Da='Danilov:BAAALgADCgYJBgAAAA==.',
De='Deadlyshift:BAABLgAECn8XAAMNAAkJsCIiBABjAwANAAkJsCIiBABjAwAOAAUJMho8NgBjAQAAAA==.Deadybear:BAAALgADCgcJCQABLgAECggJRwAPAEgUAA==.Deathkyter:BAAALgAECgEJAQAAAA==.Delrok:BAAALgAECgEJAgAAAA==.Dephias:BAAALgADCgMJAwAAAA==.',
Di='Diagnosis:BAABLgAECn8eAAIQAAkJhSWoBgAjAwAQAAkJhSWoBgAjAwAAAA==.',
Do='Donnabb:BAAALgAECggJEgAAAA==.Donteatbees:BAAALgADCgYJBgAAAA==.Doran:BAAALgAECgYJEAAAAA==.Doriathrin:BAAALgADCgcJCwAAAA==.Doujinshi:BAABLgAECn8OAAIFAAcJIBziUwCoAQAFAAcJIBziUwCoAQAAAA==.',
Dr='Draedis:BAAALgAECgMJCAAAAA==.Dragonbladez:BAAALgADCgUJBQAAAA==.Dragoneye:BAAALgAECgMJBgAAAA==.Dragonhawk:BAAALgADCgQJBAABLgAECgMJEgAEAAAAAA==.Dragonname:BAAALgAECgEJAQAAAA==.Drakoil:BAABLgAECn8pAAMRAAgJjRYzBwCqAQARAAgJXBIzBwCqAQASAAcJ1BGvMQBFAQAAAA==.Dreademperor:BAACLgAFFH8JAAITAAQJdBVrEQD1AAATAAQJdBVrEQD1AAAuAAQKfycAAxMACQkhHvAEAPYCABMACQkhHvAEAPYCABQABAlDD/NRANgAAAEuAAUUBQkMABUAJR8A.Dreadnature:BAAALgAECgMJAwAAAA==.Dreadnight:BAABLgAFFH8MAAIVAAUJJR/XDABVAQAVAAUJJR/XDABVAQAAAA==.Dreadsteed:BAAALgAECgEJAQABLgAFFAUJDAAVACUfAA==.Dreadweaver:BAAALgADCgUJBQABLgAFFAUJDAAVACUfAA==.Drenrah:BAABLgAECn8nAAIWAAkJug/IJAC6AQAWAAkJug/IJAC6AQAAAA==.Drgndeeznutz:BAACLgAFFH8LAAIHAAQJfheRDABJAQAHAAQJfheRDABJAQAuAAQKfycAAgcACQnPH3cDAOoCAAcACQnPH3cDAOoCAAAA.Drizz:BAAALgAECgIJAwAAAA==.Drunkenrage:BAACLgAFFH8jAAIXAAcJZR0RAwAkAgAXAAcJZR0RAwAkAgAuAAQKfx4AAhcACQkcIvsBAIIDABcACQkcIvsBAIIDAAAA.',
Du='Dumorius:BAAALgAECgYJCAAAAA==.',
['Dé']='Déx:BAAALgAECgYJCwAAAA==.',
Ed='Edreth:BAAALgAECgEJAQAAAA==.',
El='Elbryan:BAABLgAECn8xAAILAAkJhAjuJQB0AQALAAkJhAjuJQB0AQAAAA==.Elementdemon:BAAALgAECgUJBgAAAA==.Ellabelle:BAAALgADCgMJAwAAAA==.',
En='Enthalpy:BAABLgAECn8dAAIYAAgJfhnEggDMAQAYAAgJfhnEggDMAQAAAA==.',
Er='Erazath:BAAALgAECgUJCAABLgAECgkJEAAEAAAAAA==.',
Es='Esperzoa:BAABLgAECn8aAAIVAAgJGxpmDQAEAgAVAAgJGxpmDQAEAgAAAA==.',
Et='Eternaldread:BAAALgADCgUJBQABLgAFFAUJDAAVACUfAA==.',
Eu='Eucalicdes:BAABLgAECn8+AAIZAAkJgBfTCQAPAgAZAAkJgBfTCQAPAgAAAA==.',
Ez='Ezal:BAAALgAECgUJBwAAAA==.Ezra:BAAALgADCgYJBgAAAA==.',
Fa='Farshran:BAAALgAECgkJEAAAAA==.Fate:BAAALgAECgQJBQABLgAECgkJJQAQAJQlAA==.Fathermajor:BAAALgADCgYJBgAAAA==.',
Fe='Felicity:BAACLgAFFH8WAAIMAAUJ2h2zEQBPAQAMAAUJ2h2zEQBPAQAuAAQKfzYAAwwACQmWIpIEAE4DAAwACQmWIpIEAE4DABoABQmDDXASANoAAAAA.Ferendis:BAABLgAECn8nAAIFAAgJPiMjDwCvAgAFAAgJPiMjDwCvAgAAAA==.Fernard:BAAALgADCgYJBgABLgAECgkJEQAGACUcAA==.',
Fl='Florita:BAAALgAECgQJBAAAAA==.Flydormu:BAAALgAECgIJAwABLgAECgkJIwAYAFYYAA==.',
Fo='Fordinn:BAABLgAECn8mAAMTAAcJ7BYrHgAZAQAUAAcJyBOrPgAiAQATAAUJoBYrHgAZAQAAAA==.',
Fr='Fractured:BAAALgADCgEJAQAAAA==.Freelor:BAAALgAECgIJBAAAAA==.Freemi:BAAALgAECgEJAQAAAA==.Frigidgrip:BAAALgAECgMJAwAAAA==.',
Fu='Fuddytwo:BAABLgAECn8ZAAIOAAgJjhuREQAlAgAOAAgJjhuREQAlAgAAAA==.',
Ga='Garzhvog:BAAALgADCgcJCwABLgAECgkJNwAKAOYkAA==.Gasket:BAACLgAFFH8JAAMbAAMJuBrdCwDwAAAbAAMJNBbdCwDwAAAcAAIJ9RgsmACeAAAuAAQKfyUAAxwACQlnIsMiALQCABwACQlvIcMiALQCABsAAwkcILURABUBAAAA.Gauteng:BAAALgAECgIJAgABLgAFFAMJCAAQAL8jAA==.',
Gh='Ghidõráh:BAAALgADCgkJEAAAAA==.Ghorac:BAAALgADCgYJDAAAAA==.Ghoti:BAAALgADCgUJBQAAAA==.Ghoulz:BAAALgADCgcJDAAAAA==.',
Gl='Glazedham:BAAALgADCgMJAwAAAA==.',
Gn='Gnollfang:BAAALgADCgYJBgAAAA==.',
Go='Gorbubbli:BAAALgADCgkJGgAAAA==.',
Gr='Graceful:BAAALgAECgUJBgAAAA==.Grit:BAAALgAECgYJBwAAAA==.',
Gu='Guilddrama:BAAALgADCgEJAQAAAA==.',
Ha='Haeler:BAAALgAECgIJAwAAAA==.Haelin:BAAALgADCgEJAQAAAA==.Halgoðfulk:BAAALgAECgEJAQAAAA==.Hamwarrior:BAAALgAECgEJAQAAAA==.Handicap:BAAALgAECgcJBwABLgAECgkJHgAQAIUlAA==.Hark:BAACLgAFFH8JAAIdAAMJVQwfSADXAAAdAAMJVQwfSADXAAAuAAQKfyoAAh0ACQkNGqdEAKgBAB0ACQkNGqdEAKgBAAAA.Harpin:BAAALgADCgEJAQAAAA==.Harvin:BAABLgAECn8tAAIPAAgJMiI9AwD+AgAPAAgJMiI9AwD+AgAAAA==.',
He='Hekus:BAAALgAECgcJDgAAAA==.Helanua:BAABLgAECn8aAAICAAgJBQ8CLgBcAQACAAgJBQ8CLgBcAQAAAA==.Hellsplay:BAAALgADCgIJAgAAAA==.',
Hi='Hibernate:BAAALgADCgEJAQAAAA==.Hippopotamus:BAAALgAECgMJAwAAAA==.Hit:BAAALgAECgYJCwAAAA==.',
Ho='Holytide:BAABLgAECn8WAAMCAAgJjwn0OQAeAQACAAgJjwn0OQAeAQAeAAUJzAT5hQB8AAAAAA==.Hope:BAABLgAECn8jAAIOAAcJFwuNOwDxAAAOAAcJFwuNOwDxAAAAAA==.Horrorfang:BAABLgAECn8vAAIcAAgJSRwmLAAsAgAcAAgJSRwmLAAsAgAAAA==.',
Hu='Hukjo:BAAALgAECgcJEAABLgAECggJIAADAHcUAA==.',
Ib='Ibaar:BAACLgAFFH8VAAISAAUJ/iNOEACPAQASAAUJ/iNOEACPAQAuAAQKfy4AAxIACQm9I00HAAUDABIACAk0I00HAAUDABEABgneIAcNAAoCAAAA.',
Ic='Icepickle:BAAALgADCgcJAQAAAA==.',
Ii='Iilnut:BAABLgAECn8cAAMLAAgJmiA/CwDPAgALAAgJmiA/CwDPAgAfAAQJPBW2NwDpAAABLgAFFAQJCQADANUfAA==.',
Il='Illedren:BAABLgAECn8QAAIFAAgJwwc7kAAAAQAFAAgJwwc7kAAAAQAAAA==.',
In='Innerdemon:BAAALgAECgQJBAAAAA==.Inno:BAABLgAECn8YAAIFAAkJDiTxEwDhAgAFAAkJDiTxEwDhAgAAAA==.',
Is='Isabel:BAAALgAECgYJBgABLgAECggJEQAEAAAAAA==.',
It='Ithacus:BAABLgAECn8nAAIgAAkJSBBIDQClAQAgAAkJSBBIDQClAQAAAA==.',
Ja='Jandaar:BAAALgAECgEJAQAAAA==.Jattao:BAAALgADCgEJAQAAAA==.',
Jd='Jdawgprime:BAAALgADCgcJBwAAAA==.',
Je='Jenjas:BAAALgAECgUJBQAAAA==.',
Ji='Jinnlee:BAAALgAECgQJBQAAAA==.Jinoo:BAABLgAECn8uAAICAAgJkB3BFAAXAgACAAgJkB3BFAAXAgAAAA==.Jinufan:BAAALgAECgUJBwABLgAFFAUJFQASAP4jAA==.',
Jo='Joe:BAAALgAECgcJCgAAAA==.Jorek:BAABLgAECn8WAAIUAAkJ7BQ0IADJAQAUAAkJ7BQ0IADJAQAAAA==.',
Ju='Jugulator:BAAALgADCgcJDQAAAA==.',
Ka='Kaejung:BAAALgAECgQJBAAAAA==.Kaihune:BAAALgADCgIJAgAAAA==.Kainairobi:BAAALgAECgUJBQAAAA==.Kaiva:BAAALgAECgQJBgAAAA==.Kallistô:BAAALgADCgYJBgAAAA==.Kamigawa:BAAALgAECgYJEwAAAA==.Kavik:BAABLgAECn8cAAIWAAkJHhlyDQCVAgAWAAkJHhlyDQCVAgAAAA==.Kazbodan:BAAALgADCgkJFQAAAA==.',
Ke='Keemo:BAACLgAFFH8JAAIVAAMJnw7CHgCwAAAVAAMJnw7CHgCwAAAuAAQKfykAAxUACQnJFQkbAFIBABUACQmpFQkbAFIBABwAAwmYDUX8AIMAAAAA.Keemosaki:BAAALgAECgcJEwAAAA==.Keemõ:BAABLgAECn8XAAMhAAYJvw2NGgCgAAAFAAYJ0wzriADlAAAhAAYJowmNGgCgAAAAAA==.Keflá:BAAALgAECgQJDAAAAA==.Keysersöze:BAAALgADCgYJBwAAAA==.',
Kh='Khaas:BAABLgAECn8wAAIcAAgJjwpTbgBjAQAcAAgJjwpTbgBjAQAAAA==.Khaleeb:BAAALgAECgEJAwAAAA==.',
Ki='Kierios:BAABLgAECn8XAAMcAAgJww7faQBtAQAcAAgJhQzfaQBtAQAbAAMJ3gweHgCLAAAAAA==.Kildurgan:BAAALgAECgQJDQAAAA==.Killawarlock:BAABLgAECn8ZAAQJAAgJEyBIUADXAQAJAAcJEyBIUADXAQAKAAEJAABSJwBUAAAIAAEJ/hAbcAA2AAAAAA==.Kironn:BAAALgADCgYJBgABLgAFFAMJBwABALYHAA==.',
Kk='Kkain:BAAALgAECgIJBwAAAA==.',
Ko='Korihor:BAABLgAECn8ZAAIiAAgJLhsKCQASAgAiAAgJLhsKCQASAgAAAA==.',
Kr='Krestus:BAABLgAECn8RAAMGAAcJJRw3MwC6AAAFAAYJrxkZfgAvAQAGAAMJKSA3MwC6AAAAAA==.Krispy:BAABLgAECn8jAAMBAAgJABPiHgCOAQABAAgJABPiHgCOAQADAAUJvgO5TgCZAAAAAA==.Krith:BAAALgADCgYJCQAAAA==.Krix:BAAALgAECgMJBAAAAA==.',
Ky='Kyndil:BAAALgAECgYJCQAAAA==.',
La='Laerin:BAAALgADCgYJBgAAAA==.Laxus:BAAALgADCgcJDAABLgAECgkJGAARAHkMAA==.Lazarius:BAAALgADCgQJBAAAAA==.',
Le='Levophed:BAABLgAECn8uAAIcAAcJkg/AjwAgAQAcAAcJkg/AjwAgAQAAAA==.',
Li='Liangwei:BAAALgAECgMJAwABLgAFFAMJBwAdAPMdAA==.Lightfallen:BAAALgAECgcJEQAAAA==.Liisara:BAABLgAECn8bAAIFAAgJZghlcgAXAQAFAAgJZghlcgAXAQAAAA==.Lily:BAABLgAECn8vAAIZAAgJIxrwDADZAQAZAAgJIxrwDADZAQAAAA==.Linadra:BAABLgAECn8iAAIQAAgJ9wlYhABGAQAQAAgJ9wlYhABGAQAAAA==.Littleyeti:BAAALgAECgMJAwAAAA==.Liyara:BAACLgAFFH8IAAIQAAMJvyM2LAA3AQAQAAMJvyM2LAA3AQAuAAQKfykAAhAACQm1JUgRAAYDABAACQm1JUgRAAYDAAAA.',
Ll='Llorsa:BAABLgAECn8vAAIjAAgJ0BIzHAC/AQAjAAgJ0BIzHAC/AQAAAA==.',
Lo='Lohhan:BAAALgADCgUJCQAAAA==.Lolamontez:BAAALgAECgIJAgAAAA==.Lorachka:BAAALgADCgIJAgAAAA==.Lorthys:BAAALgADCgEJAQAAAA==.',
Lu='Luxian:BAABLgAECn8xAAIQAAgJ7w2UbgBxAQAQAAgJ7w2UbgBxAQAAAA==.',
Ma='Mahiru:BAAALgADCgEJAQAAAA==.Mahralla:BAAALgADCgIJAgAAAA==.Maikagond:BAAALgAECgQJCAABLgAECgcJHgAQABsMAA==.Makaria:BAAALgAECggJEAAAAA==.Malbisa:BAAALgAECgQJBAAAAA==.Malphoz:BAAALgADCggJCAAAAA==.Mandragora:BAAALgAECgUJEAAAAA==.Marli:BAAALgADCgEJAQAAAA==.Mattieatzdot:BAAALgAECgQJBQAAAA==.',
Mc='Mcgrowlin:BAAALgAECgQJCwAAAA==.',
Me='Mekator:BAAALgAECgQJBAAAAA==.Meko:BAAALgAECgUJBwAAAA==.Mew:BAAALgAECgEJAQAAAA==.',
Mi='Mickey:BAACLgAFFH8IAAIBAAQJJwsGFAD8AAABAAQJJwsGFAD8AAAuAAQKfygAAgEACQkTIsQEAOgCAAEACQkTIsQEAOgCAAAA.Migraine:BAAALgAECgYJCgAAAA==.Mikiik:BAABLgAECn8tAAIJAAgJSQjTcABCAQAJAAgJSQjTcABCAQAAAA==.Mildoo:BAABLgAECn8rAAIKAAkJBA8BCAC1AQAKAAkJBA8BCAC1AQAAAA==.Milkymoo:BAAALgAECgUJEwABLgAFFAgJLgAjAPsWAA==.Millina:BAAALgADCgIJAgABLgAECggJJwABAKMIAA==.Minipal:BAAALgAECgcJDAAAAA==.Mixednuts:BAACLgAFFH8JAAIDAAQJ1R+5EgB5AQADAAQJ1R+5EgB5AQAuAAQKfycAAwMACQmiIsgCAHYDAAMACQmiIsgCAHYDAAEABgkoIKofANoBAAAA.',
Mo='Mochii:BAAALgADCgYJBgAAAA==.Moneyshock:BAAALgAECgYJBgABLgAFFAQJCwAHAH4XAA==.Monq:BAABLgAECn8WAAMBAAgJdBb5IAB+AQABAAgJdBb5IAB+AQAXAAEJyAkqjQAqAAAAAA==.Moonamber:BAAALgADCgQJBgAAAA==.Morithus:BAAALgADCgkJDgAAAA==.Morphinzerr:BAAALgAECgEJAQAAAA==.',
Mu='Murdrmittens:BAAALgADCgEJAQAAAA==.',
My='Mythion:BAABLgAECn8dAAMNAAcJvBkALwDFAQANAAcJvBkALwDFAQAOAAIJoQP1eQAtAAAAAA==.Mythoridan:BAAALgAECgEJAQAAAA==.',
Na='Naeres:BAABLgAECn8fAAIcAAgJkBddXACOAQAcAAgJkBddXACOAQAAAA==.Nafari:BAAALgADCgkJEQAAAA==.Naofummi:BAAALgAECgcJBwAAAA==.Naomii:BAABLgAECn8pAAMjAAkJ9hZKFwDuAQAjAAkJ9hZKFwDuAQALAAUJZQj/SAC9AAAAAA==.Narus:BAAALgAECgUJBAABLgAECgcJJgATAOwWAA==.Naturefury:BAAALgADCgEJAQAAAA==.',
Ne='Neeston:BAACLgAFFH8HAAINAAMJzBKdLgDWAAANAAMJzBKdLgDWAAAuAAQKfyIAAw0ACAkJI5EMANsCAA0ACAkJI5EMANsCAA4AAQllEtyAADAAAAEuAAUUBAkLAAcAfhcA.Neodin:BAABLgAECn8WAAIUAAgJBgslMABnAQAUAAgJBgslMABnAQAAAA==.Nephadin:BAAALgADCgUJAwABLgAECgkJJgAiANchAA==.Nerfed:BAAALgAECgUJCAAAAA==.Neviaa:BAABLgAECn8iAAIcAAgJ7w3fZgB0AQAcAAgJ7w3fZgB0AQAAAA==.',
Ni='Nickypoo:BAAALgAECgMJBgAAAA==.Nightmenace:BAAALgAECgcJCwAAAA==.Ninari:BAAALgADCgUJBQAAAA==.Niq:BAAALgAECgQJBAAAAA==.',
No='Nocshadue:BAAALgADCgUJBQAAAA==.Nordga:BAAALgADCgcJBwAAAA==.Nothealster:BAAALgAECgcJEgAAAA==.Nothros:BAAALgADCgQJBAAAAA==.',
Ob='Obsidiian:BAABLgAECn8UAAIkAAgJjRF+CACDAQAkAAgJjRF+CACDAQAAAA==.Obsidion:BAAALgAECgUJDgABLgAECgcJJgATAOwWAA==.',
Od='Odie:BAAALgAECgYJCQAAAA==.',
On='Onemorehit:BAAALgAECgEJAQAAAA==.Onlyfangs:BAABLgAECn9HAAMPAAgJSBTdDADfAQAPAAgJSBTdDADfAQASAAYJtwXPVwCoAAAAAA==.',
Os='Oscrapermort:BAAALgADCgMJAwAAAA==.',
Pa='Padivyn:BAABLgAECn8bAAICAAgJzxjQGwDWAQACAAgJzxjQGwDWAQAAAA==.Padnamprik:BAAALgAECgQJBAAAAA==.Palidenman:BAAALgAECgIJAgAAAA==.',
Pe='Peanads:BAAALgADCgcJEAAAAA==.Pebblez:BAAALgADCgcJDgAAAA==.Perry:BAABLgAECn8hAAMNAAkJNxtLGABhAgANAAgJvxlLGABhAgAOAAIJAQVIbQBEAAAAAA==.',
Po='Po:BAAALgAECgkJCAAAAA==.Pozufuma:BAABLgAECn8vAAIUAAgJWh2SFgAWAgAUAAgJWh2SFgAWAgAAAA==.',
Pr='Priestcraft:BAAALgADCgIJAgABLgAECggJCwAEAAAAAA==.',
Ps='Psychomantis:BAABLgAECn8nAAMLAAkJeRReGADfAQALAAkJeRReGADfAQAjAAEJQgQHhQAsAAAAAA==.',
Pu='Punchypunch:BAAALgADCgkJFAAAAA==.',
Ra='Raek:BAAALgAECgQJBQABLgAECgcJGQAKAPEbAA==.Ravenbyrd:BAAALgADCgMJAwAAAA==.Rawberriez:BAAALgAECgQJBgAAAA==.',
Re='Reani:BAAALgADCgQJBAAAAA==.Reapin:BAAALgADCgUJBQAAAA==.Redpool:BAABLgAECn8dAAIdAAcJXhCNQACtAQAdAAcJXhCNQACtAQAAAA==.Remithedrood:BAAALgADCgIJAgAAAA==.Reqium:BAAALgADCgYJCAAAAA==.Resto:BAAALgAECgQJBgAAAA==.Rethandra:BAAALgAECgYJDAAAAA==.',
Ri='Rion:BAABLgAECn8XAAIYAAkJcxG1UADNAQAYAAkJcxG1UADNAQAAAA==.Ristvakbaen:BAABLgAECn83AAQKAAkJ5iT7AQCbAgAKAAgJRiX7AQCbAgAJAAkJvB1yGQByAgAIAAYJPSVfBAAOAgAAAA==.',
Ro='Robynlee:BAABLgAECn8pAAIjAAgJZhJ/IwDKAQAjAAgJZhJ/IwDKAQAAAA==.Rogùe:BAAALgAECgIJBAAAAA==.Rosebelle:BAAALgADCgUJCQAAAA==.',
Ru='Rugratt:BAAALgADCgQJBAABLgADCgcJDgAEAAAAAA==.',
Sa='Saeler:BAAALgAECgMJAwAAAA==.Sailrmoonkin:BAAALgAECgQJBAABLgAECggJGgAVABsaAA==.Samoth:BAAALgADCgEJAQAAAA==.Sanctuary:BAAALgAECgQJBAAAAA==.Santeclair:BAAALgAECgEJAQAAAA==.',
Sc='Sceryna:BAABLgAECn8oAAIQAAkJzBfaNgAFAgAQAAkJzBfaNgAFAgAAAA==.Schiftly:BAAALgAFFAIJAgAAAA==.Schwiggity:BAAALgAECgQJBAABLgAECgUJEAAEAAAAAA==.Scottlock:BAAALgAECgcJBwABLgAECggJKAAgACciAA==.Scrmndemn:BAABLgAECn8hAAIQAAcJGghbogASAQAQAAcJGghbogASAQAAAA==.',
Se='Sepviva:BAABLgAECn8VAAIcAAcJNhZmcACoAQAcAAcJNhZmcACoAQAAAA==.Serpent:BAACLgAFFH8KAAITAAYJCRJWBwB/AQATAAYJCRJWBwB/AQAuAAQKfyMAAhMACQlnH5oFAJsCABMACQlnH5oFAJsCAAAA.',
Sh='Shadowheal:BAAALgADCgUJBgAAAA==.Shamadeus:BAAALgADCgUJBQABLgAECgkJNwAKAOYkAA==.Sharaseth:BAAALgAECgcJDwAAAA==.Shikita:BAABLgAECn8vAAMNAAgJ0B69GABdAgANAAgJ0B69GABdAgAOAAEJHAZfigAlAAAAAA==.Shimadin:BAACLgAFFH8YAAIQAAUJTxvPIgBNAQAQAAUJTxvPIgBNAQAuAAQKfycAAhAACAmxHyIvAGYCABAACAmxHyIvAGYCAAAA.Shimjun:BAAALgAECgUJBQABLgAFFAUJGAAQAE8bAA==.Shimpbizkit:BAABLgAECn8WAAIYAAcJWAyAiABKAQAYAAcJWAyAiABKAQABLgAFFAUJGAAQAE8bAA==.Shimsong:BAAALgAECgYJDAABLgAFFAUJGAAQAE8bAA==.Shmerek:BAABLgAECn8XAAITAAkJRSC0BQCXAgATAAkJRSC0BQCXAgAAAA==.',
Si='Sidarien:BAAALgADCgQJBAAAAA==.Silenttits:BAAALgAECgEJAQAAAA==.Silverlumen:BAAALgAECgYJDAAAAA==.Silverstream:BAABLgAECn8qAAINAAkJ6BEdQgCZAQANAAkJ6BEdQgCZAQAAAA==.',
Sk='Skyblue:BAAALgADCgEJAQAAAA==.',
Sl='Slea:BAAALgADCgQJBAAAAA==.Slease:BAAALgADCgYJBgAAAA==.',
Sm='Smootish:BAAALgADCgUJBQAAAA==.',
So='Solbin:BAAALgAECgUJCwABLgAECgkJIwAYAFYYAA==.Solitudé:BAABLgAECn8dAAMJAAgJBiR9HgBUAgAJAAcJBiF9HgBUAgAKAAUJoSVhDwAxAQABLgAFFAMJBgAbAAQgAA==.Soteirian:BAABLgAECn8eAAMQAAcJGwzykwArAQAQAAcJGwzykwArAQAiAAEJjwIzTwASAAAAAA==.',
Sp='Spam:BAAALgAECgIJAgAAAA==.Spekey:BAAALgAECgEJAQAAAA==.Spider:BAABLgAECn8dAAIcAAgJSxZuQADgAQAcAAgJSxZuQADgAQAAAA==.Spineymagus:BAAALgADCgIJAgAAAA==.',
Sq='Squall:BAABLgAECn8eAAMeAAcJyhGGQQB1AQAeAAcJyhGGQQB1AQACAAYJ9BJFPAAUAQAAAA==.',
St='Stalariais:BAAALgAECgQJBAABLgAECgkJGQAWAHoIAA==.Stardrand:BAAALgADCgUJBgAAAA==.Steelreserve:BAAALgAECgYJDQAAAA==.Straw:BAAALgAECgYJCwABLgAECgkJOAAQAFEkAA==.',
Su='Sugarkitty:BAAALgADCgYJCgAAAA==.Supereclipse:BAABLgAECn8vAAIdAAgJMRURPwC6AQAdAAgJMRURPwC6AQAAAA==.',
Sw='Swolareclips:BAAALgADCgYJBgAAAA==.',
Sy='Sydvicious:BAABLgAECn8iAAIGAAkJPCVpAgAaAwAGAAkJPCVpAgAaAwAAAA==.Syriene:BAABLgAECn8ZAAIlAAYJ6Q3OGgD7AAAlAAYJ6Q3OGgD7AAAAAA==.',
Ta='Tankhealz:BAAALgAECgMJBQAAAA==.Tanthe:BAAALgAECgMJAwAAAA==.',
Tb='Tbsp:BAAALgAECgEJAQAAAA==.',
Te='Tecks:BAABLgAECn8XAAIjAAkJwgWhMwATAQAjAAkJwgWhMwATAQAAAA==.Teddy:BAAALgAECgUJCQAAAA==.',
Th='Theatrix:BAAALgAECgQJBAAAAA==.Thecuckler:BAAALgAECgQJCAAAAA==.Thefreeman:BAAALgAECgEJAQAAAA==.Themajor:BAABLgAECn8eAAMmAAkJvxLKDwDGAQAmAAkJphLKDwDGAQAUAAcJ/AhwTAB0AQAAAA==.Then:BAAALgADCgEJAQAAAA==.Thiarad:BAAALgADCgEJAQAAAA==.Thiaraxo:BAAALgAECgkJEgAAAA==.Thrain:BAAALgADCgcJDAAAAA==.Threat:BAABLgAECn8lAAIQAAkJlCUrAwBaAwAQAAkJlCUrAwBaAwAAAA==.Thsarus:BAABLgAECn8vAAMFAAgJ6yAWFwBvAgAFAAgJ6yAWFwBvAgAhAAQJHBHQGwCxAAAAAA==.',
Ti='Tiamaat:BAABLgAECn8XAAINAAkJmgQAbADPAAANAAkJmgQAbADPAAAAAA==.Tireyne:BAAALgADCgEJAgAAAA==.Titus:BAAALgAECgEJBgAAAA==.',
To='Tokkaebi:BAAALgAECgkJAQAAAA==.',
Tr='Treadlightly:BAAALgADCgUJBwAAAA==.Treefróg:BAAALgAECgUJBQAAAA==.Trentus:BAAALgADCgIJAgAAAA==.Trev:BAAALgAECgUJBgABLgAFFAUJBQAJAIUWAA==.Trotem:BAAALgAECgUJBQAAAA==.',
Ts='Tsp:BAACLgAFFH8WAAIDAAUJShx5DgCtAQADAAUJShx5DgCtAQAuAAQKfysAAwMACQnQGBUZABACAAMACQnQGBUZABACABcABAnxA0psAJEAAAAA.',
Ty='Tyletos:BAABLgAECn8jAAIYAAkJVhicMAA4AgAYAAkJVhicMAA4AgAAAA==.',
Ug='Ugolok:BAAALgAECgYJEwAAAA==.',
Ur='Uriél:BAABLgAECn8iAAIFAAgJ+COxCwDQAgAFAAgJ+COxCwDQAgABLgAFFAMJBgAbAAQgAA==.',
Va='Valeene:BAABLgAECn8ZAAIOAAkJuSAeBQDsAgAOAAkJuSAeBQDsAgAAAA==.Varek:BAAALgAECgIJAgAAAA==.',
Ve='Veiler:BAABLgAECn89AAMdAAkJ/xB4LQD9AQAdAAkJ/xB4LQD9AQAnAAEJ3wH2lgAhAAAAAA==.Velca:BAAALgAECgIJAgAAAA==.Veruca:BAAALgAECgMJAwAAAA==.Veviseron:BAABLgAECn8nAAIYAAkJqAMNjgA/AQAYAAkJqAMNjgA/AQAAAA==.',
Vh='Vhye:BAAALgAFFAIJAgAAAA==.',
Vi='Vinstalation:BAABLgAECn80AAIbAAkJcRwdBABUAgAbAAkJcRwdBABUAgAAAA==.Vissa:BAAALgADCgYJBgAAAA==.',
Vo='Vonbismarck:BAABLgAECn8iAAIdAAkJ8hMqPADEAQAdAAkJ8hMqPADEAQAAAA==.',
Vr='Vritraz:BAACLgAFFH8GAAIbAAMJBCDUCQATAQAbAAMJBCDUCQATAQAuAAQKfxUAAxsACQmLImIEAEkCABsABwk+I2IEAEkCABwAAgl0IC3QALoAAAAA.Vrock:BAAALgAECgEJAQABLgAECggJHQAYAH4ZAA==.',
Wa='Warnam:BAAALgADCgcJBwAAAA==.Warsonge:BAAALgADCgMJAwAAAA==.',
We='Wendypini:BAACLgAFFH8JAAIdAAMJRALmVgChAAAdAAMJRALmVgChAAAuAAQKfyIAAh0ACQkAEF5FAJsBAB0ACQkAEF5FAJsBAAAA.Wetnwild:BAAALgADCgQJBAAAAA==.',
Wh='Whitehand:BAAALgAECgIJAgAAAA==.',
Wo='Wooshwoosh:BAAALgAECgQJCwAAAA==.',
Wu='Wudeeps:BAAALgAECgcJEgAAAA==.Wuhanwarrior:BAAALgAECgYJEQAAAA==.',
Ya='Yako:BAAALgAECgEJAQAAAA==.',
Ye='Yennefer:BAAALgAECgMJAwAAAA==.',
Za='Zangolf:BAAALgADCgUJBAAAAA==.Zaye:BAAALgAECgcJBwAAAA==.',
Ze='Zearas:BAABLgAECn8UAAIcAAgJJxE+kwBZAQAcAAgJJxE+kwBZAQAAAA==.Zendonn:BAABLgAECn8WAAIBAAYJ+wQyTgChAAABAAYJ+wQyTgChAAAAAA==.',
Zi='Zicatriz:BAAALgADCgcJDgAAAA==.',
Zo='Zodiaac:BAABLgAECn8XAAIVAAkJdxmCEADSAQAVAAkJdxmCEADSAQAAAA==.',
Zy='Zy:BAAALgADCgUJBQAAAA==.',
['Ëc']='Ëchõ:BAABLgAECn8gAAMNAAkJ+RXSNwDIAQANAAkJ+RXSNwDIAQAOAAIJvwRldwBHAAAAAA==.',
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
