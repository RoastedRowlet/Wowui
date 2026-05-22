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

local lookup = {'Unknown-Unknown','Warrior-Fury','DemonHunter-Devourer','DeathKnight-Unholy','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Druid-Feral','Warrior-Protection','Paladin-Retribution','Mage-Frost','Druid-Restoration','Priest-Discipline','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Paladin-Holy','Hunter-Survival','Druid-Guardian','DemonHunter-Havoc','Druid-Balance','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','Rogue-Assassination','DeathKnight-Blood',}
local provider = {region='US',realm='Haomarush',name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Adderall:BAAALgAECggJDgAAAA==.',
Ae='Aethrion:BAAALgADCgMJAwABLgAECgEJAwABAAAAAA==.',
Al='Alexya:BAAALgADCgIJAgAAAA==.All:BAAALgADCgEJAQAAAA==.Alphahawk:BAACLgAFFH8GAAICAAMJVwd+JADLAAACAAMJVwd+JADLAAAuAAQKfzkAAgIACQkBGkcPADkCAAIACQkBGkcPADkCAAAA.',
Ap='Apocalipsis:BAAALgAECgMJAwAAAA==.',
Aq='Aquilis:BAABLgAECn8TAAIDAAkJAhigVgCeAQADAAkJAhigVgCeAQAAAA==.',
Ar='Aramis:BAAALgAECgUJCQABLgAECgkJGwAEAN4fAA==.Arathrok:BAABLgAECn8bAAIEAAkJ3h/SPwA5AgAEAAkJ3h/SPwA5AgAAAA==.',
As='Asha:BAACLgAFFH8NAAIFAAUJ/xZXCQA+AQAFAAUJ/xZXCQA+AQAuAAQKfxwABAUACAnLICYTANQBAAUACAnLICYTANQBAAYABAnQHOkqAEkBAAcABQnGGWMqACYBAAAA.Asmoday:BAABLgAECn8nAAIEAAkJrCEPCgDoAgAEAAkJrCEPCgDoAgAAAA==.Astra:BAAALgAECgEJAQAAAA==.Asunawa:BAAALgADCgUJBQAAAA==.',
Au='Aundarr:BAAALgADCgEJAQABLgAECgkJJwAEAKwhAA==.Autoshift:BAABLgAECn8WAAIIAAgJ7QoCEQBBAQAIAAgJ7QoCEQBBAQAAAA==.Auun:BAAALgAECgEJAQABLgAECgkJJwAEAKwhAA==.',
Ba='Bat:BAABLgAECn8ZAAIIAAgJAyWyAQDpAgAIAAgJAyWyAQDpAgAAAA==.',
Be='Benedictine:BAAALgAECgEJBQAAAA==.',
Bi='Bigcleavage:BAABLgAECn8cAAIJAAkJnxqFDADWAQAJAAkJnxqFDADWAQAAAA==.',
Bl='Blueberrypie:BAAALgAFFAEJAQABLgAFFAEJAQABAAAAAA==.',
Bo='Boomster:BAAALgAFFAgJAwAAAA==.',
Br='Bridgetpower:BAAALgADCgIJAgAAAA==.',
Ca='Calixta:BAABLgAECn8dAAIKAAkJnyHyGgBiAgAKAAkJnyHyGgBiAgAAAA==.Carbshock:BAAALgADCgYJCgAAAA==.',
Ce='Ceroah:BAAALgAECgYJCwAAAA==.',
Ch='Cherrypie:BAAALgAFFAEJAQAAAA==.',
Co='Coodown:BAAALgAECgYJCAAAAA==.',
Cy='Cylla:BAACLgAFFH8LAAILAAMJgQmyXwDiAAALAAMJgQmyXwDiAAAuAAQKfzEAAgsACAmJHX4wABUCAAsACAmJHX4wABUCAAAA.',
Di='Dilfdormu:BAAALgAECgcJDwAAAA==.',
Dk='Dkvaluemenu:BAAALgAECgEJAQAAAA==.',
Do='Donkey:BAAALgADCgIJAgAAAA==.Doson:BAACLgAFFH8GAAIMAAIJ/xF2OgCGAAAMAAIJ/xF2OgCGAAAuAAQKfzUAAgwACQkrH9wFACcDAAwACQkrH9wFACcDAAAA.',
Dr='Dragonmabals:BAAALgAECgQJBAAAAA==.Dratak:BAACLgAFFH8oAAIJAAcJsiOuAABvAgAJAAcJsiOuAABvAgAuAAQKf1YAAgkACQnJJV0AANMDAAkACQnJJV0AANMDAAAA.Dread:BAABLgAECn8bAAIFAAgJjBrAEAB2AgAFAAgJjBrAEAB2AgAAAA==.Dreadfang:BAAALgADCgcJCgAAAA==.Dred:BAAALgAECgMJBwAAAA==.Drizbul:BAAALgAECgEJAQABLgAFFAcJKAAJALIjAA==.',
Ea='Earthswrath:BAAALgAECgUJDgAAAA==.',
El='Elitzai:BAAALgAECgIJAgAAAA==.',
Em='Emeralda:BAAALgADCgcJDQAAAA==.',
Ev='Evalueate:BAAALgAECgQJBAAAAA==.',
Fl='Fluf:BAAALgADCgcJDAAAAA==.',
Fr='Frocknor:BAAALgAECgUJEQAAAA==.',
Fu='Fuki:BAAALgAECgQJDAAAAA==.Furrymythh:BAAALgAECgQJBAABLgAFFAMJDAAJAAclAA==.',
Fy='Fyrstureinn:BAAALgADCgIJAgAAAA==.',
Ga='Galumian:BAACLgAFFH8qAAINAAgJYyKgAAAgAwANAAgJYyKgAAAgAwAuAAQKfzMABA0ACQlsJaYDAC4DAA0ACAlDJaYDAC4DAA4ABwkSEUAvAIYBAA8AAgncIbpGAMkAAAAA.',
Go='Goo:BAAALgAECgcJDAAAAA==.',
Gu='Guy:BAAALgADCgcJBwAAAA==.',
Ha='Hamhock:BAAALgAECgQJCwAAAA==.Haradali:BAAALgAFFAQJBAAAAA==.',
Ho='Holydiah:BAAALgAECgYJEgAAAA==.Holypriest:BAAALgAECgcJCQAAAA==.Hordehound:BAAALgADCgIJAgAAAA==.',
Ja='Jakimozo:BAAALgAECgcJDAAAAA==.Jasminetea:BAABLgAECn8fAAMNAAkJfBuwEgAdAgANAAgJwh2wEgAdAgAOAAQJjgkZQACeAAAAAA==.',
Ju='Judgecutie:BAAALgAECgkJCQAAAA==.',
Ka='Kadesh:BAAALgADCgYJBgABLgAECgkJJwAEAKwhAA==.Kayla:BAAALgAECgEJAwAAAA==.',
Ki='Kiran:BAAALgAECgEJAwAAAA==.',
Kr='Krizara:BAAALgAECgEJAQABLgAECgUJEQABAAAAAA==.Kroth:BAABLgAECn9BAAIMAAkJ8hFFJADjAQAMAAkJ8hFFJADjAQAAAA==.',
Ku='Kubfury:BAAALgAECgUJBgAAAA==.Kudi:BAAALgAECgYJDAAAAA==.',
['Kí']='Kíllian:BAABLgAECn8hAAIQAAkJFSGiCwC0AgAQAAkJFSGiCwC0AgAAAA==.',
La='Labatblue:BAAALgADCgEJAQAAAA==.Lacey:BAAALgAECgYJBgAAAA==.Lavitz:BAAALgAECgYJCgAAAA==.',
Lo='Loris:BAAALgAECgcJBgABLgAFFAgJAwABAAAAAA==.',
Lu='Lunaci:BAABLgAECn8kAAMRAAkJvxmkDABLAgARAAkJvxmkDABLAgASAAYJmQ6eDAACAQAAAA==.Lunylu:BAAALgADCgUJBQAAAA==.',
Ma='Magicmagicin:BAAALgAECgMJAgAAAA==.Magnusson:BAABLgAECn8oAAIJAAkJjBulBQB2AgAJAAkJjBulBQB2AgAAAA==.Mandrah:BAAALgAECgYJCQAAAA==.Masutado:BAABLgAECn8oAAILAAkJcRvYFwCRAgALAAkJcRvYFwCRAgAAAA==.Maven:BAAALgAECgQJBAAAAA==.Mayelle:BAAALgADCgkJEAAAAA==.Mayernnaise:BAAALgAECgQJBQAAAA==.Mayvoker:BAAALgADCgEJAQAAAA==.',
Me='Metier:BAAALgAECgUJCQABLgAFFAMJDAAJAAclAA==.',
Mi='Miao:BAAALgAECgYJBgAAAA==.Mirror:BAAALgAECgcJBQABLgAFFAgJAwABAAAAAA==.Misfortune:BAAALgAECgMJBAABLgAECgkJHQAKAJ8hAA==.Mitsy:BAABLgAECn8WAAIPAAcJFg8tJgBEAQAPAAcJFg8tJgBEAQAAAA==.',
Mo='Money:BAABLgAECn8jAAMKAAgJGCGfIACpAgAKAAcJFiGfIACpAgATAAIJcAfeXwBbAAAAAA==.Montipython:BAAALgAFFAIJAgAAAA==.Moons:BAACLgAFFH8RAAIUAAYJtRPPAgCiAQAUAAYJtRPPAgCiAQAuAAQKf0gAAhQACQlII6sBABMDABQACQlII6sBABMDAAAA.Mothman:BAAALgADCgUJBAAAAA==.Moussebreath:BAACLgAFFH8FAAINAAUJSAdXDwDaAAANAAUJSAdXDwDaAAAuAAQKfxgAAg0ABwmrH1UOAFUCAA0ABwmrH1UOAFUCAAAA.',
Mu='Mudpie:BAABLgAECn8YAAIVAAgJiB+vCgDRAQAVAAgJiB+vCgDRAQABLgAFFAEJAQABAAAAAA==.Munco:BAACLgAFFH8FAAIWAAQJVhvnBABeAQAWAAQJVhvnBABeAQAuAAQKfzYAAhYACQkyIzMCAAcDABYACQkyIzMCAAcDAAAA.Muncola:BAAALgAECgEJAQABLgAFFAQJBQAWAFYbAA==.Muncoli:BAAALgAECgMJBAABLgAFFAQJBQAWAFYbAA==.Muncolito:BAAALgADCgEJAQABLgAFFAQJBQAWAFYbAA==.Mungus:BAAALgAECgQJCQAAAA==.',
My='Mythhleremix:BAAALgADCgUJBgABLgAFFAMJDAAJAAclAA==.',
Ne='Nellie:BAABLgAECn8gAAMXAAkJJg68GgCaAQAXAAkJJg68GgCaAQAMAAQJlQHMsABkAAAAAA==.Newtree:BAAALgAFFAQJAgABLgAFFAgJAwABAAAAAA==.',
No='Notker:BAABLgAECn8oAAIOAAkJPCOTAQByAwAOAAkJPCOTAQByAwAAAA==.',
Ny='Nynaa:BAAALgADCgIJAgABLgAECgkJJwAEAKwhAA==.',
Or='Orcwarr:BAABLgAECn8oAAQJAAgJQRtoCQAWAgAJAAgJQRtoCQAWAgACAAMJlAl4jwCAAAAYAAEJPQsKQwAzAAAAAA==.',
Pa='Panders:BAABLgAFFH8KAAIKAAQJ+AX4MQARAQAKAAQJ+AX4MQARAQAAAA==.Patadita:BAAALgAECgYJDgAAAA==.',
Pe='Pecanpie:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Penne:BAAALgADCgcJDAAAAA==.',
Pi='Pinkpony:BAAALgAFFAQJAwABLgAFFAgJAwABAAAAAA==.Pipsi:BAAALgAECgEJAQABLgAFFAQJBQAWAFYbAA==.',
Pk='Pk:BAAALgAECgUJBQABLgAFFAQJBgAEAIQWAA==.',
Pr='Pryor:BAAALgAECgEJAQABLgAECgkJJwAEAKwhAA==.',
Qu='Quiverinpalm:BAABLgAECn8UAAIHAAcJ5Q7fKAAuAQAHAAcJ5Q7fKAAuAQAAAA==.',
Ra='Rageoverrun:BAAALgADCgYJCgAAAA==.',
Re='Remiwog:BAAALgADCggJCgAAAA==.Rennik:BAACLgAFFH8MAAQZAAMJ4RsCCwChAAAZAAIJWhkCCwChAAAaAAIJIhMSbACcAAAbAAEJ8COhCwBXAAAuAAQKfzEABBkACAmaI1kOAOMBABkABQmLIlkOAOMBABoABgldHaU8AKkBABsAAwlUJKITALwAAAAA.Rentiak:BAAALgAECgYJEwAAAA==.',
Ru='Rue:BAAALgAECgYJCwAAAA==.',
Sa='Saffy:BAAALgADCgYJBwAAAA==.',
Sc='Scorevival:BAAALgAECgEJAQAAAA==.Scorewin:BAEBLgAECn8hAAIcAAkJCiTeAQD1AgAcAAkJCiTeAQD1AgAAAA==.',
Se='Serenity:BAAALgAECgEJAwABLgAFFAEJAgABAAAAAA==.Serraku:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfern:BAEALgAECgMJBgAAAA==.Shalniar:BAAALgADCgYJBgABLgAFFAUJFQAdAAIlAA==.Shioh:BAAALgADCgUJBQAAAA==.Shocky:BAAALgAECgEJAQAAAA==.',
Si='Sienda:BAAALgADCgUJBAAAAA==.Sinappi:BAAALgAECgEJAgAAAA==.Siñ:BAABLgAECn8gAAIeAAgJRAjxCQBVAQAeAAgJRAjxCQBVAQAAAA==.',
Sk='Skeetshootah:BAABLgAECn8nAAIQAAkJkxZmHgAhAgAQAAkJkxZmHgAhAgAAAA==.',
Sl='Slowbadon:BAABLgAECn8YAAITAAkJixOPJgCIAQATAAkJixOPJgCIAQAAAA==.',
St='Stabpokestab:BAAALgADCgcJDQAAAA==.Stay:BAAALgAECgcJBgABLgAFFAgJAwABAAAAAA==.Streetlight:BAAALgAECggJDwABLgABCgEJAQABAAAAAA==.Streetlights:BAAALgAECgYJDgABLgABCgEJAQABAAAAAA==.Streets:BAAALgAECggJEQABLgABCgEJAQABAAAAAA==.',
Ta='Tank:BAACLgAFFH8MAAIJAAMJByXgCABDAQAJAAMJByXgCABDAQAuAAQKfy0AAgkACAm8Ja8CADwDAAkACAm8Ja8CADwDAAAA.',
Te='Teafayd:BAAALgAECgYJEgAAAA==.',
Th='Thunderdot:BAABLgAECn8pAAIPAAkJBx1TDgCeAgAPAAkJBx1TDgCeAgAAAA==.Thunderlok:BAAALgADCgEJAgAAAA==.',
Ti='Tilvayne:BAACLgAFFH8HAAIEAAQJBBKqOQBCAQAEAAQJBBKqOQBCAQAuAAQKf00AAgQACQnOIhQHAAwDAAQACQnOIhQHAAwDAAAA.',
To='Tomayter:BAABLgAECn8nAAIOAAkJNB4ABgDXAgAOAAkJNB4ABgDXAgAAAA==.',
Tr='Trap:BAAALgAFFAEJAgAAAA==.Trinitee:BAAALgADCgYJCgAAAA==.Trisriane:BAAALgAECgMJBgABLgAECgkJHQAKAG4aAA==.Trist:BAABLgAECn8dAAIKAAkJbhpzPgArAgAKAAkJbhpzPgArAgAAAA==.',
Tu='Turbogoat:BAABLgAECn8lAAIEAAgJuh4GLQCFAgAEAAgJuh4GLQCFAgAAAA==.Turok:BAAALgAECgEJAgABLgAFFAMJBQAUAFMYAA==.',
Tw='Twaave:BAABLgAECn8kAAILAAkJpSH1GwAHAwALAAkJpSH1GwAHAwAAAA==.',
['Tÿ']='Tÿ:BAAALgAECgQJBQAAAA==.',
Va='Vaz:BAAALgAECgYJCwAAAA==.Vazp:BAAALgAECgUJBQABLgAECgYJCwABAAAAAA==.',
Ve='Verdessa:BAAALgAECgQJCAAAAA==.',
Wa='Waltz:BAAALgADCgEJAQAAAA==.',
Xi='Xins:BAAALgAECgQJBAAAAA==.',
Yi='Yikezvelobtw:BAAALgAECgIJAwAAAA==.',
Ze='Zennah:BAAALgADCgQJBAAAAA==.Zerene:BAABLgAECn8oAAMZAAkJ0xgIAwApAgAZAAkJ0xgIAwApAgAaAAcJ/wXydwANAQAAAA==.',
['Æs']='Æsc:BAABLgAECn8oAAIfAAkJ3RYuDgDRAQAfAAkJ3RYuDgDRAQAAAA==.',
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
