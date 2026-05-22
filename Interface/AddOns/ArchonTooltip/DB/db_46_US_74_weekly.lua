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

local lookup = {'Paladin-Retribution','Druid-Balance','Paladin-Holy','DeathKnight-Unholy','Druid-Restoration','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Unknown-Unknown','Rogue-Subtlety','Hunter-BeastMastery','Warlock-Demonology','DemonHunter-Devourer','Warlock-Affliction','Warlock-Destruction','Rogue-Assassination','Mage-Frost','Evoker-Preservation','Shaman-Enhancement','Priest-Shadow','DeathKnight-Frost','Hunter-Marksmanship','Warrior-Protection','Warrior-Fury','Shaman-Restoration','DeathKnight-Blood','DemonHunter-Havoc','Monk-Mistweaver','Monk-Brewmaster','Mage-Fire','Paladin-Protection','Druid-Feral','DemonHunter-Vengeance','Rogue-Outlaw','Warrior-Arms','Shaman-Elemental','Druid-Guardian','Mage-Arcane','Hunter-Survival',}
local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Adorah:BAABLgAECn8gAAIBAAkJBBR+KgAPAgABAAkJBBR+KgAPAgAAAA==.',
Ak='Akazamello:BAAALgAECgEJAQAAAA==.',
Al='Allyia:BAAALgADCgEJAgAAAA==.Alucarde:BAABLgAECn8YAAICAAgJGApFKQArAQACAAgJGApFKQArAQAAAA==.',
An='Angrboda:BAAALgADCgUJBQAAAA==.',
Ar='Arator:BAAALgADCgYJBQAAAA==.Artelios:BAAALgADCgMJAwAAAA==.Arvad:BAAALgADCgUJBQABLgAECggJLQADAJMiAA==.',
As='Ashknight:BAABLgAECn8WAAIEAAgJTAaxmADsAAAEAAgJTAaxmADsAAAAAA==.',
Au='Auroralights:BAAALgAECgEJAQAAAA==.',
Az='Azriel:BAAALgADCgkJCQAAAA==.',
Ba='Babyjeebus:BAAALgAECgYJCgAAAA==.Bagged:BAAALgAECgcJEgAAAA==.Balzak:BAAALgADCgMJAwAAAA==.Bastas:BAABLgAECn8iAAIFAAkJKRgoJwAaAgAFAAkJKRgoJwAaAgAAAA==.',
Be='Beastley:BAAALgADCgcJBwAAAA==.Beekro:BAACLgAFFH8QAAIGAAQJzB0vEgBcAQAGAAQJzB0vEgBcAQAuAAQKfzEAAgYACQlYI8AEAOUCAAYACQlYI8AEAOUCAAAA.Belaen:BAABLgAECn8rAAIDAAgJ5B+RCQCsAgADAAgJ5B+RCQCsAgAAAA==.Belarina:BAAALgAECgcJCwABLgAFFAQJEgAHAN4WAA==.Belatink:BAACLgAFFH8SAAMHAAQJ3hYdDgATAQAHAAQJ3hYdDgATAQAIAAMJTAECKgB6AAAuAAQKfywAAwcACQmYHUgJALcCAAcACQmYHUgJALcCAAgABwnxClkyAA4BAAAA.',
Bi='Bilando:BAAALgAECgYJDwAAAA==.',
Bl='Bloodveil:BAAALgAFFAEJAQABLgAFFAIJBAAJAAAAAA==.Blueberry:BAAALgAECgEJAQAAAA==.Blàckbeard:BAABLgAECn8mAAIKAAgJzhZSEwC1AQAKAAgJzhZSEwC1AQAAAA==.',
Bo='Borden:BAAALgAECgkJEQAAAA==.',
Br='Brutalize:BAAALgAECgEJAwAAAA==.',
Bu='Bustyvoidelf:BAAALgAECgQJBAAAAA==.Buttercup:BAACLgAFFH8SAAIFAAQJAyL0DgCOAQAFAAQJAyL0DgCOAQAuAAQKfywAAgUACQl2IV8GABwDAAUACQl2IV8GABwDAAAA.',
Ch='Chainer:BAABLgAECn8hAAILAAcJMBOtRgB1AQALAAcJMBOtRgB1AQAAAA==.Chirios:BAAALgAECgYJDgAAAA==.',
Ck='Ckdeath:BAABLgAECn8XAAIEAAgJJBnYQwCwAQAEAAgJJBnYQwCwAQAAAA==.Ckwarlock:BAAALgAECgIJAgAAAA==.',
Cl='Clam:BAAALgAECgEJAQABLgAECgkJFAAMAD8eAA==.Clubsandwich:BAAALgAECgIJAwAAAA==.',
Cr='Crash:BAEALgAECgEJAgABLgAFFAUJDAANAJ8ZAA==.',
Cu='Cursén:BAABLgAECn8yAAQMAAkJaBhLJQAMAgAMAAkJaBhLJQAMAgAOAAIJXQ+tIABvAAAPAAEJigcpdwAtAAAAAA==.',
Da='Dacker:BAAALgADCgUJBQAAAA==.Daelen:BAAALgAECgEJAgABLgAFFAIJBQAJAAAAAQ==.Darlocke:BAABLgAECn8hAAIQAAcJKhaeBwCQAQAQAAcJKhaeBwCQAQAAAA==.Darwin:BAAALgADCgIJAgAAAA==.Daysforsand:BAAALgAECgEJAQAAAA==.',
De='Deathmurk:BAABLgAECn8xAAIEAAkJSBuLHABYAgAEAAkJSBuLHABYAgAAAA==.Deathstyck:BAAALgADCgcJBwABLgADCgcJBwAJAAAAAA==.',
Di='Diasoul:BAAALgAECgkJBQAAAA==.Dimblederf:BAAALgADCgMJAwAAAA==.Divinesteez:BAAALgAECgQJBgABLgAECgYJFQARAIIVAA==.',
Do='Doomentia:BAABLgAECn8ZAAMSAAgJRAz3JQBHAQASAAgJRAz3JQBHAQAGAAYJuwp2QQDOAAAAAA==.',
Dr='Drezzarnbez:BAAALgAECgcJEAAAAA==.Drimdor:BAAALgAECgIJAgAAAA==.Druìdfluid:BAAALgAECgEJAgAAAA==.',
Du='Durgrim:BAACLgAFFH8NAAITAAQJGx3wAgBZAQATAAQJGx3wAgBZAQAuAAQKfyIAAhMACAnUIeQDAOoCABMACAnUIeQDAOoCAAAA.',
Dw='Dwuiduwu:BAAALgADCgMJAwAAAA==.',
Ed='Edine:BAAALgAECgMJBgAAAA==.',
Ee='Eeèva:BAAALgAECgYJCAAAAA==.',
Ef='Efah:BAAALgAECgUJCAAAAA==.',
El='Elgordo:BAAALgAECgYJBgAAAA==.',
Ep='Epoxxy:BAAALgADCgkJCgAAAA==.',
Es='Espresso:BAACLgAFFH8TAAIUAAUJhSIOBgChAQAUAAUJhSIOBgChAQAuAAQKfy4AAhQACQnXJJoBAEQDABQACQnXJJoBAEQDAAAA.',
Ex='Exvo:BAAALgAECgQJBAAAAA==.',
Fa='Fallenseraph:BAAALgADCgUJBQAAAA==.',
Fe='Fellbent:BAAALgAECgEJAQABLgAECgYJFQARAIIVAA==.Fenric:BAAALgAECgEJAwAAAA==.',
Fh='Fhtagnglui:BAAALgAECgYJBgABLgAFFAIJBQAJAAAAAQ==.',
Fr='Freddiemerc:BAAALgADCgcJDAAAAA==.Frogspawn:BAAALgADCgEJAQAAAA==.',
Fu='Furrywar:BAAALgAECgEJAQABLgAECggJGQALANQkAA==.',
Ga='Gaartak:BAACLgAFFH8QAAMVAAQJlSG7AgBnAQAVAAQJcx67AgBnAQAEAAMJziRsSwAfAQAuAAQKfx8AAgQACAmwIyYPACMDAAQACAmwIyYPACMDAAAA.',
Ge='Geg:BAAALgAECgIJAgAAAA==.Gengar:BAAALgAECggJEgAAAA==.Geto:BAAALgADCgYJBwAAAA==.',
Gi='Girlypop:BAAALgADCgQJBAAAAA==.Gith:BAAALgAECgEJAQABLgAECggJGAAOACISAA==.Githlock:BAABLgAECn8YAAQOAAgJIhKqBwDXAQAOAAcJ7ROqBwDXAQAPAAUJJwdoNwDYAAAMAAIJUQj0BQEvAAAAAA==.Githon:BAAALgAECgcJCwABLgAECggJGAAOACISAA==.Githpriest:BAAALgADCgcJBwABLgAECggJGAAOACISAA==.',
Gl='Gluegun:BAABLgAECn8YAAMWAAkJuRx5HgAzAgAWAAgJ+Rt5HgAzAgALAAIJ9CHJugBbAAAAAA==.',
Go='Gondo:BAAALgAECgUJBQABLgAFFAMJCAALAKUXAA==.Goodberry:BAAALgADCgYJBgAAAA==.',
Gr='Griselbrand:BAAALgAECgMJAwAAAA==.Grogrin:BAACLgAFFH8OAAMXAAQJhRQBDQAJAQAXAAQJhRQBDQAJAQAYAAIJoghQLgCLAAAuAAQKfy8AAxgACAlKHgERACUCABgACAnUHQERACUCABcAAwkFF10pAKEAAAAA.',
Gu='Gunnlaugr:BAAALgADCgYJBgAAAA==.',
Ha='Haleb:BAAALgADCgYJBgAAAA==.Haribooty:BAAALgAECgUJBQABLgAFFAQJEgAZANgOAA==.Harlíequinn:BAABLgAECn8eAAIZAAcJnQJuZwC3AAAZAAcJnQJuZwC3AAAAAA==.Harmacist:BAABLgAECn8VAAIUAAcJjwvPKgAnAQAUAAcJjwvPKgAnAQAAAA==.',
He='Hex:BAAALgAECgYJDQABLgAFFAQJDQAHADgfAA==.',
Hi='Hitmonlee:BAAALgAFFAEJAQABLgAFFAgJIwAGAOIbAA==.',
Ho='Hobstwo:BAAALgAECgEJAQAAAA==.Hoofhearted:BAAALgAECgIJAgAAAA==.Hoofstompa:BAAALgADCgMJAwAAAA==.Houtoku:BAAALgAFFAIJBQAAAQ==.Hozi:BAABLgAECn87AAQEAAkJmiK4CAD3AgAEAAkJmiK4CAD3AgAaAAMJQA0CPQBfAAAVAAEJHwcxGQAqAAAAAA==.',
Hp='Hpnosis:BAABLgAECn8XAAIBAAgJnQ8sfQCAAQABAAgJnQ8sfQCAAQAAAA==.',
Hu='Hukdonfonex:BAAALgAECgcJDAAAAA==.Hunterin:BAABLgAECn8ZAAMLAAgJ1CSGDADcAgALAAcJxiSGDADcAgAWAAMJryL2SgAmAQAAAA==.Huntington:BAAALgAECgYJCAABLgAECgkJMgAMAGgYAA==.',
Il='Illidanmello:BAACLgAFFH8PAAINAAQJIBbkJwAuAQANAAQJIBbkJwAuAQAuAAQKfygAAw0ACQktIK8fAJMCAA0ACQktIK8fAJMCABsAAwnqDwFTAJ0AAAAA.',
Im='Imtrying:BAACLgAFFH8SAAIZAAQJ2A7TIQAEAQAZAAQJ2A7TIQAEAQAuAAQKfywAAhkACQkrFAorAOEBABkACQkrFAorAOEBAAAA.',
Is='Isolet:BAAALgAECgYJBgAAAA==.',
Ja='Jayaegis:BAAALgADCgUJBgAAAA==.Jayaesir:BAAALgADCgEJAQAAAA==.Jayal:BAACLgAFFH8GAAIBAAQJ9AEVQQDpAAABAAQJ9AEVQQDpAAAuAAQKfyoAAgEACAmnE1hHAKcBAAEACAmnE1hHAKcBAAAA.',
Je='Jessïe:BAAALgAECgUJCAAAAA==.',
Jo='Joja:BAACLgAFFH8LAAIcAAQJYgqrIACzAAAcAAQJYgqrIACzAAAuAAQKfyAAAxwACAkkGeUUAAMCABwACAkkGeUUAAMCAB0AAQkAAJeOAAAAAAAA.Jooja:BAAALgAECgMJBwABLgAFFAQJCwAcAGIKAA==.',
Ju='Julow:BAAALgAECgEJAgAAAA==.',
['Jö']='Jökér:BAAALgADCgEJAQAAAA==.',
Ka='Kaizen:BAAALgAECgUJBQAAAA==.Katbelle:BAACLgAFFH8RAAIeAAQJDAcNAQAXAQAeAAQJDAcNAQAXAQAuAAQKfy4AAh4ACQmBGF0BAD0CAB4ACQmBGF0BAD0CAAAA.',
Ke='Keyi:BAAALgADCgcJDgABLgADCgcJBwAJAAAAAA==.Keynallan:BAAALgAECgQJBAAAAA==.',
Ki='Kinkykelly:BAACLgAFFH8OAAINAAYJjxNTCgCIAQANAAYJjxNTCgCIAQAuAAQKfx8AAg0ACAlVIdklAG8CAA0ACAlVIdklAG8CAAAA.',
Kl='Kloo:BAAALgAECgEJAQAAAA==.',
Kr='Krixxus:BAAALgADCgEJAgAAAA==.Krugidan:BAAALgAECgcJEgAAAA==.',
['Kú']='Kúsh:BAAALgAECgQJBwAAAA==.',
['Kü']='Küsh:BAAALgAECggJEwAAAA==.',
La='Lahar:BAAALgAECgQJBAABLgAFFAQJDQAHADgfAA==.',
Le='Leof:BAAALgAECgEJAQABLgAFFAQJDQATABsdAA==.Leshwi:BAAALgAECgYJDAABLgAECgYJEAAJAAAAAA==.',
Li='Liltimmyp:BAAALgADCgEJAQAAAA==.Littlelam:BAACLgAFFH8OAAIEAAQJzRkZMABSAQAEAAQJzRkZMABSAQAuAAQKfy0AAgQACAlUI7cTAAUDAAQACAlUI7cTAAUDAAAA.',
Lo='Locknar:BAAALgADCgYJBgABLgAECgUJCAAJAAAAAA==.Lockybowboa:BAAALgAECgMJAwAAAA==.Locrock:BAAALgAECgEJAQAAAA==.Loken:BAAALgAECgkJDAAAAA==.Lorkhan:BAABLgAECn8VAAIfAAkJ2xW4FQB1AQAfAAkJ2xW4FQB1AQAAAA==.Loxsmith:BAAALgAECgYJBgABLgAECgYJFQARAIIVAA==.',
Lt='Ltcclover:BAAALgAECgQJCQAAAA==.',
Ma='Maledict:BAABLgAECn8WAAINAAcJlwYggwAiAQANAAcJlwYggwAiAQAAAA==.Malgan:BAAALgAECgcJCQABLgAFFAIJBQAJAAAAAQ==.Manhattan:BAAALgAECgcJDwABLgAFFAUJEwAUAIUiAA==.Martini:BAAALgAECgQJCgABLgAFFAUJEwAUAIUiAA==.',
Me='Meko:BAAALgAECgUJBwAAAA==.Merikaya:BAAALgAECggJCgAAAA==.Meèko:BAAALgAFFAEJAQAAAA==.Meéko:BAAALgADCgQJBAAAAA==.',
Mi='Miau:BAAALgAECgYJBgAAAA==.Mistafridge:BAAALgADCgcJCAABLgAECgYJFQARAIIVAA==.',
Mo='Mollie:BAAALgAECgIJAgABLgAFFAQJBwAdALMiAA==.Monkedor:BAAALgADCgIJAgAAAA==.Moocelee:BAAALgAECgQJCAAAAA==.',
Mu='Murk:BAAALgADCgkJDQABLgAECgkJMQAEAEgbAA==.Murloc:BAAALgADCgEJAQAAAA==.',
Na='Nah:BAAALgADCgcJBwAAAA==.Nahshadah:BAAALgADCggJCAAAAA==.Nanome:BAABLgAECn8VAAIRAAYJghXbdwBLAQARAAYJghXbdwBLAQAAAA==.Nazure:BAAALgAECgEJAQAAAA==.',
Ne='Nedra:BAAALgADCgEJAQABLgADCgEJAgAJAAAAAA==.Nesral:BAABLgAECn8ZAAILAAgJrhTDJwAaAgALAAgJrhTDJwAaAgAAAA==.Nevoir:BAAALgAECggJCQAAAA==.',
Nh='Nhasir:BAACLgAFFH8QAAIaAAQJuBJqEQABAQAaAAQJuBJqEQABAQAuAAQKfyIAAhoACQmHISQHAL4CABoACQmHISQHAL4CAAAA.Nhastea:BAABLgAECn8XAAIdAAcJhBrEFwCsAQAdAAcJhBrEFwCsAQABLgAFFAQJEAAaALgSAA==.',
Ni='Niceneasy:BAAALgAECgMJAwAAAA==.',
No='Normal:BAAALgAECgMJAwAAAA==.Nowaifu:BAAALgAECgEJBAAAAA==.',
Od='Odrade:BAAALgADCgIJAgABLgADCgIJAgAJAAAAAA==.',
Ow='Owlbread:BAABLgAECn8VAAIgAAkJ6wnQFwBCAQAgAAkJ6wnQFwBCAQAAAA==.',
Oz='Ozwin:BAABLgAECn8VAAIdAAYJYRagJgA8AQAdAAYJYRagJgA8AQAAAA==.',
Pe='Peccator:BAACLgAFFH8NAAIHAAQJOB//BwBrAQAHAAQJOB//BwBrAQAuAAQKfyMAAgcACQmRIgsCAFoDAAcACQmRIgsCAFoDAAAA.Pein:BAAALgADCgIJAgAAAA==.Percdirty:BAAALgADCgUJCAAAAA==.Persess:BAAALgADCgYJBgAAAA==.',
Ph='Phatality:BAEALgAECgMJCQABLgAECgQJBQAJAAAAAA==.',
Pi='Pillowpants:BAAALgADCgcJBwAAAA==.',
Pl='Plat:BAAALgAECgEJAQAAAA==.Platsearthen:BAABLgAECn8UAAIBAAYJYwSDwQC1AAABAAYJYwSDwQC1AAAAAA==.Ploo:BAAALgADCgcJAQAAAA==.',
Pn='Pneumma:BAAALgAECgcJCQAAAA==.',
Po='Poodrinker:BAAALgADCgcJBwABLgAECgcJEAAJAAAAAA==.',
Pr='Priya:BAAALgAECgYJEAAAAA==.Protect:BAAALgAECgMJBAABLgAFFAMJCAALAKUXAA==.Pròm:BAAALgAECgIJAQAAAA==.',
Ra='Ramordis:BAAALgADCgEJAQAAAA==.Ravia:BAABLgAECn8XAAIhAAcJDhyhBwALAgAhAAcJDhyhBwALAgAAAA==.',
Re='Rebyen:BAAALgADCgYJBQAAAA==.Regularhorns:BAABLgAECn8XAAINAAgJSQ4lXAAhAQANAAgJSQ4lXAAhAQAAAA==.Rendhoof:BAAALgAECgEJAwAAAA==.Reptarr:BAAALgADCgYJBQABLgAECgYJFQARAIIVAA==.Restodruid:BAAALgAECgQJBAAAAA==.Rev:BAAALgADCgQJCAAAAA==.',
Ri='Richter:BAAALgADCgkJCQAAAA==.Rins:BAAALgAFFAEJAQABLgAECggJGQALANQkAA==.Rinslet:BAAALgAECgkJDwABLgAECggJGQALANQkAA==.Riskante:BAACLgAFFH8HAAIBAAIJixfqUwCmAAABAAIJixfqUwCmAAAuAAQKfzAAAwEACQkVHPkWAHsCAAEACQkVHPkWAHsCAAMABQlmEfJbAA0BAAAA.',
Ro='Roonrana:BAAALgAECgMJBQAAAA==.Rosey:BAACLgAFFH8LAAIiAAQJdA5lAwA2AQAiAAQJdA5lAwA2AQAuAAQKfy0AAiIACAngHokBAMICACIACAngHokBAMICAAAA.',
Ru='Rubýrose:BAAALgAECgEJAQAAAA==.Rulutieh:BAAALgAECgMJBgAAAA==.Runebraker:BAAALgAECgYJCwAAAA==.',
Sa='Sandfordays:BAAALgAECgMJBgAAAA==.Sardor:BAAALgAECgQJCAAAAA==.',
Sc='Scorn:BAAALgAECgkJEQAAAA==.Scottyno:BAACLgAFFH8HAAIBAAIJ6RpaUACsAAABAAIJ6RpaUACsAAAuAAQKfyYAAgEACQmqHqwMAMkCAAEACQmqHqwMAMkCAAAA.',
Se='Sempast:BAABLgAECn8tAAMMAAkJsiIREgCEAgAMAAgJkCIREgCEAgAPAAQJ4CJnGQCAAQABLgAFFAIJBAAJAAAAAA==.Senarria:BAAALgAECgEJAQAAAA==.',
Sh='Shadyfear:BAAALgAECgEJAQAAAA==.Shaldin:BAABLgAECn8UAAIZAAcJBCDKGgAeAgAZAAcJBCDKGgAeAgAAAA==.Shaluesta:BAAALgAECgMJBAAAAA==.Shaluestaa:BAAALgAECgcJBwAAAA==.Shanithell:BAAALgADCgIJAgAAAA==.Shanksz:BAAALgAECgIJAwAAAA==.Shellyd:BAABLgAECn8YAAIYAAgJbBLCJwBuAQAYAAgJbBLCJwBuAQAAAA==.Shiryû:BAAALgADCgEJAQAAAA==.',
Si='Siennaa:BAAALgAECgIJAgAAAA==.Sinfulsmite:BAAALgADCgEJAQABLgAECgQJCgAJAAAAAA==.Sins:BAACLgAFFH8NAAQEAAUJjhYiFgBLAQAEAAQJMxUiFgBLAQAVAAMJ5BA8CQDYAAAaAAEJAAC1PwAAAAAuAAQKfxYAAgQACAmFHxApAJYCAAQACAmFHxApAJYCAAAA.',
Sl='Slide:BAAALgAECgYJBgAAAA==.',
Sn='Sneakyhand:BAACLgAFFH8SAAMYAAQJRSNWBwB+AQAYAAQJJB5WBwB+AQAjAAQJICOYBQB4AQAuAAQKfzAABBgACQlTJRYEAGoDABgACAkUJhYEAGoDACMABAlRIw8RAIoBABcAAgl5INgkAMAAAAAA.',
So='Soupson:BAAALgADCgIJAgABLgAECgYJEAAJAAAAAA==.',
St='Steelt:BAAALgAECgYJCwABLgAECggJGAAOACISAA==.Steris:BAAALgAECgYJEAAAAA==.Stinkindwarf:BAAALgAECgQJBAAAAA==.Stizzy:BAAALgAECgMJBQAAAA==.',
Su='Sunadora:BAAALgAECgEJBAAAAA==.',
Sw='Swagula:BAABLgAECn8ZAAIfAAgJjiN3AwCRAgAfAAgJjiN3AwCRAgAAAA==.',
Sy='Sylvain:BAAALgAECgEJAQABLgAECgkJKAAkAJIdAA==.Sylvi:BAABLgAECn8XAAMlAAkJQhnqDAC5AQAlAAkJQhnqDAC5AQAgAAIJFRKfJAB3AAAAAA==.Syrup:BAAALgADCgkJCQAAAA==.Syurni:BAAALgADCgEJAgABLgADCgEJAgAJAAAAAA==.',
Ta='Takitsu:BAACLgAFFH8QAAIlAAQJSwn3CQDLAAAlAAQJSwn3CQDLAAAuAAQKfyUAAiUACAn9EecTAEEBACUACAn9EecTAEEBAAAA.',
Th='Tharion:BAAALgAECgEJAQAAAA==.',
Ti='Tinyfist:BAAALgADCgYJBgAAAA==.Tired:BAAALgADCgEJAgAAAA==.',
To='Tombz:BAACLgAFFH8HAAIEAAQJZwkySgAiAQAEAAQJZwkySgAiAQAuAAQKfz4AAwQACQn0IBkTAJYCAAQACQn0IBkTAJYCABoAAgk1Ag5GADAAAAAA.Towa:BAAALgAECgMJBAAAAA==.',
Tr='Trilira:BAAALgADCgUJBwAAAA==.',
Tu='Turf:BAAALgADCgMJAgAAAA==.',
Ul='Ulangi:BAAALgAECgEJAQAAAA==.',
Un='Unbelavable:BAAALgAECgYJBwAAAA==.',
Ur='Uranis:BAAALgADCgEJAgAAAA==.Uroboros:BAAALgADCgEJAQAAAA==.Ursa:BAAALgAECgYJCgAAAA==.',
Ve='Veil:BAAALgAFFAIJBAAAAA==.',
Vl='Vlorax:BAAALgADCgMJBgAAAA==.',
Vo='Volodinson:BAAALgAECgUJDAAAAA==.',
Vy='Vynesh:BAAALgADCgEJAwAAAA==.',
Wa='Wallê:BAAALgAECgEJAQAAAA==.Wandwanker:BAABLgAECn8aAAImAAkJ5R1xAQBQAgAmAAkJ5R1xAQBQAgAAAA==.Warsawz:BAAALgAECgEJAgAAAA==.',
We='Wetasscat:BAABLgAECn8UAAIMAAkJPx5MOQAmAgAMAAkJPx5MOQAmAgAAAA==.Weyae:BAAALgAECgMJBAAAAA==.',
Wh='Whorg:BAACLgAFFH8IAAILAAMJpRcHNwDoAAALAAMJpRcHNwDoAAAuAAQKfysAAwsACAllH9smAPQBAAsACAneHNsmAPQBACcABglHHPISAJQBAAAA.',
Wi='Willyboi:BAABLgAECn8cAAMRAAcJUxJsZgBwAQARAAcJUxJsZgBwAQAmAAQJNwp9DwDKAAAAAA==.Wisemanorc:BAAALgAECgMJBQAAAA==.',
Xa='Xavierr:BAABLgAECn8YAAIcAAcJYhOYIwB9AQAcAAcJYhOYIwB9AQAAAA==.',
Ya='Yarkaz:BAAALgAECgQJBwAAAA==.',
Yi='Yinli:BAAALgAECgEJAQAAAA==.',
Yu='Yucky:BAAALgAECgEJAQABLgAECggJEwAJAAAAAA==.',
Za='Zaai:BAAALgADCgcJCgAAAA==.Zargus:BAABLgAECn8oAAIkAAkJkh0UFwDZAQAkAAkJkh0UFwDZAQAAAA==.Zarlunce:BAABLgAECn8fAAIYAAgJQB38FQDyAQAYAAgJQB38FQDyAQAAAA==.',
Ze='Zetsuon:BAABLgAECn8wAAIFAAkJXh4FCAD8AgAFAAkJXh4FCAD8AgAAAA==.',
Zu='Zuk:BAAALgAECgcJDQAAAA==.',
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
