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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Druid-Balance','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Warlock-Demonology','Rogue-Subtlety','Hunter-BeastMastery','DemonHunter-Devourer','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Rogue-Assassination','Mage-Frost','Evoker-Preservation','Shaman-Enhancement','Shaman-Elemental','DeathKnight-Blood','Hunter-Marksmanship','Warrior-Protection','Warrior-Fury','Shaman-Restoration','DemonHunter-Havoc','Monk-Mistweaver','Monk-Brewmaster','Mage-Fire','Paladin-Protection','Druid-Feral','DemonHunter-Vengeance','Rogue-Outlaw','Warrior-Arms','Druid-Guardian','Mage-Arcane','Hunter-Survival',}
local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Adorah:BAABLgAECn8gAAIBAAkJBBTlNgAFAgABAAkJBBTlNgAFAgAAAA==.',
Ak='Akazamello:BAAALgAECgEJAQAAAA==.',
Al='Aldafir:BAAALgAECgEJAQAAAA==.Allyia:BAAALgADCgEJAgABLgAECgYJBgACAAAAAA==.Alucarde:BAABLgAECn8ZAAIDAAgJTAtYLgA4AQADAAgJTAtYLgA4AQAAAA==.',
An='Angrboda:BAAALgADCgUJBQAAAA==.',
Ar='Arator:BAAALgADCgYJBQAAAA==.Artelios:BAAALgADCgMJAwAAAA==.Arvad:BAAALgADCgUJBQABLgAECggJMAAEADwjAA==.',
As='Ashknight:BAABLgAECn8WAAIFAAgJTAbVrgDsAAAFAAgJTAbVrgDsAAAAAA==.',
Au='Auroralights:BAAALgAECgQJBAAAAA==.',
Az='Azriel:BAAALgADCgkJCQABLgAFFAUJFQAGAJUhAA==.',
Ba='Babyjeebus:BAAALgAECgYJCgAAAA==.Bagged:BAAALgAECgcJEgAAAA==.Balzak:BAAALgADCgMJAwAAAA==.Bastas:BAABLgAECn8iAAIHAAkJKRgoJwAaAgAHAAkJKRgoJwAaAgAAAA==.',
Be='Beartreecat:BAAALgAECgEJAQAAAA==.Beastley:BAAALgADCgcJBwAAAA==.Beekro:BAACLgAFFH8VAAIIAAUJuSMTDwCfAQAIAAUJuSMTDwCfAQAuAAQKfzEAAggACQlYIzYGAOECAAgACQlYIzYGAOECAAAA.Belaen:BAABLgAECn8sAAIEAAkJKR6gCADcAgAEAAkJKR6gCADcAgAAAA==.Belarina:BAAALgAFFAEJAQABLgAFFAQJFgAJAGEXAA==.Belatink:BAACLgAFFH8WAAMJAAQJYRdEEQARAQAJAAQJYRdEEQARAQAKAAMJTAHtMQB5AAAuAAQKfywAAwkACQmYHUgJALcCAAkACQmYHUgJALcCAAoABwnxClkyAA4BAAAA.',
Bi='Bilando:BAAALgAECgYJDwAAAA==.',
Bl='Bloodveil:BAAALgAFFAEJAQABLgAFFAMJBgALACwgAA==.Blueberry:BAAALgAECgEJAQAAAA==.Blàckbeard:BAABLgAECn8mAAIMAAgJzxbWGACrAQAMAAgJzxbWGACrAQAAAA==.',
Bo='Borden:BAAALgAECgkJEQAAAA==.',
Br='Brutalize:BAAALgAECgcJCgAAAA==.',
Bu='Bustyvoidelf:BAAALgAECgQJBAAAAA==.Buttercup:BAACLgAFFH8XAAIHAAUJwCIFCgD+AQAHAAUJwCIFCgD+AQAuAAQKfywAAgcACQl2ISQIABsDAAcACQl2ISQIABsDAAAA.',
Ch='Chainer:BAABLgAECn8pAAINAAgJvBJORACpAQANAAgJvBJORACpAQAAAA==.Chirios:BAAALgAECgYJDgAAAA==.',
Ck='Ckdeath:BAABLgAECn8XAAIFAAgJJRmTVACiAQAFAAgJJRmTVACiAQAAAA==.Ckwarlock:BAAALgAECgIJAgAAAA==.',
Cl='Clam:BAAALgAECgEJAQABLgAECgkJFAALAEEeAA==.Clubsandwich:BAAALgAECgMJBAAAAA==.',
Cr='Crash:BAEALgAECgEJAgABLgAFFAUJDQAOABIaAA==.',
Cu='Cursén:BAABLgAECn8yAAQLAAkJbRidLgAGAgALAAkJbRidLgAGAgAPAAIJXQ+tIABvAAAQAAEJigcpdwAtAAAAAA==.',
Da='Dacker:BAAALgADCgUJBQAAAA==.Daelen:BAAALgAECgEJAgABLgAFFAIJBQACAAAAAQ==.Daiquiri:BAAALgAECggJCAABLgAFFAYJFQARAHcgAA==.Darlocke:BAABLgAECn8pAAISAAgJyRSnBgDYAQASAAgJyRSnBgDYAQAAAA==.Darwin:BAAALgADCgIJAgAAAA==.Daysforsand:BAAALgAECgEJAQAAAA==.',
De='Deathmurk:BAABLgAECn81AAIFAAkJSRuVJQBLAgAFAAkJSRuVJQBLAgAAAA==.Deathstyck:BAAALgADCgcJBwABLgADCgcJBwACAAAAAA==.',
Di='Diasoul:BAAALgAECgkJCAAAAA==.Dimblederf:BAAALgADCgMJAwAAAA==.Divinesteez:BAAALgAECgQJBgABLgAECgYJFQATAIIVAA==.',
Do='Doomentia:BAABLgAECn8ZAAMUAAgJQwz3JQBHAQAUAAgJQwz3JQBHAQAIAAYJuwoKTQDOAAAAAA==.',
Dr='Drezzarnbez:BAAALgAECgcJEAAAAA==.Drimdor:BAAALgAECgIJAgAAAA==.Druìdfluid:BAAALgAECgUJBgAAAA==.',
Du='Durgrim:BAACLgAFFH8SAAIVAAUJox1oBABMAQAVAAUJox1oBABMAQAuAAQKfyYAAhUACAk/IuQDAOoCABUACAk/IuQDAOoCAAAA.',
Dw='Dwuiduwu:BAAALgADCgMJAwAAAA==.',
Ed='Edine:BAAALgAECgMJBgAAAA==.',
Ee='Eeèva:BAAALgAECgYJCAAAAA==.',
Ef='Efah:BAAALgAECgUJCAAAAA==.',
El='Elementriix:BAAALgADCgEJAQAAAA==.Elgordo:BAAALgAECgYJBgAAAA==.',
Ep='Epoxxy:BAAALgADCgkJCgAAAA==.',
Es='Espresso:BAACLgAFFH8VAAIRAAYJdyB9BADqAQARAAYJdyB9BADqAQAuAAQKfy8AAhEACQnYJDcCADsDABEACQnYJDcCADsDAAAA.',
Ex='Exvo:BAAALgAECgQJBQAAAA==.',
Fa='Fallenseraph:BAAALgADCgUJBQAAAA==.',
Fe='Fellbent:BAAALgAECgIJAgABLgAECgYJFQATAIIVAA==.Fenric:BAAALgAECgEJAwAAAA==.',
Fh='Fhtagnglui:BAAALgAECgYJBgABLgAFFAIJBQACAAAAAQ==.',
Fr='Freddiemerc:BAAALgADCgcJDAAAAA==.Frogspawn:BAAALgADCgEJAQAAAA==.',
Fu='Furrywar:BAAALgAECgEJAQABLgAECgcJFwAWALcjAA==.',
Ga='Gaartak:BAACLgAFFH8VAAQGAAUJlSHJBABgAQAGAAQJ9B7JBABgAQAFAAMJziQgXgASAQAXAAEJAABsOwAAAAAuAAQKfycABAUACAnAJCYPACMDAAUACAmwIyYPACMDAAYABgksIQgHAOkBABcAAgmKHGgyAKMAAAAA.',
Ge='Geg:BAAALgAECgIJAgABLgAECgUJBgACAAAAAA==.Gengar:BAAALgAECggJEgAAAA==.Geto:BAAALgADCgYJBwAAAA==.',
Gi='Girlypop:BAAALgADCgQJBAAAAA==.Gith:BAAALgAFFAQJBAAAAA==.Githlock:BAABLgAECn8YAAQPAAgJIhKqBwDXAQAPAAcJ7ROqBwDXAQAQAAUJJwdoNwDYAAALAAIJUQibIwEvAAABLgAFFAQJBAACAAAAAA==.Githon:BAAALgAECggJDwABLgAFFAQJBAACAAAAAA==.Githpriest:BAAALgADCgcJBwABLgAFFAQJBAACAAAAAA==.',
Gl='Gluegun:BAACLgAFFH8IAAMYAAQJRxXvEwDgAAAYAAMJyxLvEwDgAAANAAIJcBoFWACfAAAuAAQKfxgAAxgACQm5HHkeADMCABgACAn6G3keADMCAA0AAgn0IWnZAFYAAAAA.',
Go='Gondo:BAAALgAECgUJBQABLgAFFAMJCAANAKUXAA==.Goodberry:BAAALgADCgYJBgAAAA==.',
Gr='Griselbrand:BAAALgAECgMJAwAAAA==.Grogrin:BAACLgAFFH8TAAMZAAUJJRatDgATAQAZAAQJJRatDgATAQAaAAMJoggONwCDAAAuAAQKfzEAAxoACAmnISoOAGsCABoACAkxISoOAGsCABkAAwkFF6IvAJsAAAAA.',
Gu='Gunnlaugr:BAAALgADCgYJBgAAAA==.',
Ha='Haleb:BAAALgADCgYJBgAAAA==.Haribooty:BAAALgAECgUJBQABLgAFFAUJFwAbAA4PAA==.Harlíequinn:BAABLgAECn8mAAIbAAgJsgIUbgDXAAAbAAgJsgIUbgDXAAAAAA==.Harmacist:BAABLgAECn8ZAAIRAAcJ9A4MLQBGAQARAAcJ9A4MLQBGAQAAAA==.',
He='Hex:BAAALgAECgYJDQABLgAFFAQJDQAJADgfAA==.',
Hi='Hitmonlee:BAAALgAFFAEJAQABLgAFFAgJIwAIAOIbAA==.',
Ho='Hobstwo:BAAALgAECgEJAQAAAA==.Hoofhearted:BAAALgAECgIJAgAAAA==.Hoofstompa:BAAALgADCgMJAwAAAA==.Houtoku:BAAALgAFFAIJBQAAAQ==.Hozi:BAABLgAECn88AAQFAAkJtiL3CwDuAgAFAAkJtiL3CwDuAgAXAAMJQA0CPQBfAAAGAAEJHwcxGQAqAAAAAA==.Hozjor:BAAALgAECgUJCAABLgAECgkJPAAFALYiAA==.',
Hp='Hpnosis:BAABLgAECn8XAAIBAAgJng8sfQCAAQABAAgJng8sfQCAAQAAAA==.',
Hu='Hukdonfonex:BAAALgAECgcJDAAAAA==.Hunterin:BAABLgAECn8ZAAMNAAgJ1CSGDADcAgANAAcJxiSGDADcAgAYAAMJryL2SgAmAQABLgAECgcJFwAWALcjAA==.Huntington:BAAALgAECgYJCAABLgAECgkJMgALAG0YAA==.',
Il='Illidanmello:BAACLgAFFH8UAAIOAAUJrB5yHwBsAQAOAAUJrB5yHwBsAQAuAAQKfysAAw4ACQkuICgfADwCAA4ACQkuICgfADwCABwAAwnqDwFTAJ0AAAAA.',
Im='Imtrying:BAACLgAFFH8XAAIbAAUJDg+QGgBOAQAbAAUJDg+QGgBOAQAuAAQKfywAAhsACQknFAorAOEBABsACQknFAorAOEBAAAA.',
Is='Isolet:BAAALgAECgYJBgAAAA==.',
Ja='Jayaegis:BAAALgADCgUJBgAAAA==.Jayaesir:BAAALgADCgEJAQAAAA==.Jayal:BAACLgAFFH8KAAIBAAQJAAz7NQAhAQABAAQJAAz7NQAhAQAuAAQKfyoAAgEACAmoE8tWAKgBAAEACAmoE8tWAKgBAAAA.',
Je='Jerdek:BAAALgAECgEJAQAAAA==.Jessïe:BAAALgAECgUJCAAAAA==.',
Jo='Joja:BAACLgAFFH8MAAIdAAQJZwpCIgDhAAAdAAQJZwpCIgDhAAAuAAQKfyEAAx0ACAmyGdUYABICAB0ACAmyGdUYABICAB4AAQkAAB2cAAAAAAAA.Jooja:BAABLgAECn8ZAAMSAAkJXQ5jDQAyAQASAAYJBBBjDQAyAQAMAAQJngu3MADqAAABLgAFFAQJDAAdAGcKAA==.',
Ju='Julow:BAAALgAECgEJAwAAAA==.',
['Jö']='Jökér:BAAALgADCgEJAQAAAA==.',
Ka='Kaizen:BAAALgAECgUJBQAAAA==.Katbelle:BAACLgAFFH8WAAIfAAUJzAswAQAhAQAfAAUJzAswAQAhAQAuAAQKfy4AAh8ACQmBGNkBADYCAB8ACQmBGNkBADYCAAAA.',
Ke='Keyi:BAAALgADCgcJDgABLgADCgcJBwACAAAAAA==.Keynallan:BAAALgAECgQJBAAAAA==.',
Kh='Khalur:BAAALgADCgkJCAABLgAFFAIJBQACAAAAAQ==.',
Ki='Kinkykelly:BAACLgAFFH8QAAIOAAcJIhVTCgCIAQAOAAcJIhVTCgCIAQAuAAQKfyIAAg4ACAmHIdklAG8CAA4ACAmHIdklAG8CAAAA.',
Kl='Kloo:BAAALgAECgEJAQAAAA==.',
Kr='Krixxus:BAAALgADCgEJAgAAAA==.Kruger:BAAALgAECgUJBQAAAA==.Krugidan:BAABLgAECn8UAAIcAAgJeiCqCAB0AgAcAAgJeiCqCAB0AgAAAA==.',
['Kú']='Kúsh:BAAALgAECgQJBwAAAA==.',
['Kü']='Küsh:BAAALgAECggJEwAAAA==.',
La='Lahar:BAAALgAECgQJCAABLgAFFAQJDQAJADgfAA==.Lala:BAAALgADCgEJAQAAAA==.',
Le='Leof:BAAALgAECgEJAQABLgAFFAUJEgAVAKMdAA==.Leshwi:BAAALgAECgYJDAABLgAECgYJEAACAAAAAA==.',
Li='Liltimmyp:BAAALgADCgEJAQAAAA==.Littlelam:BAACLgAFFH8TAAMFAAUJfSE0JQCCAQAFAAQJfSE0JQCCAQAXAAEJAAASTgAAAAAuAAQKfy0AAgUACAlUI7cTAAUDAAUACAlUI7cTAAUDAAAA.',
Lo='Locknar:BAAALgADCgYJBgABLgAECgUJCAACAAAAAA==.Lockybowboa:BAAALgAECgMJAwAAAA==.Locrock:BAAALgAECgEJAQAAAA==.Loken:BAAALgAECgkJDgAAAA==.Longneck:BAAALgADCgIJAwABLgAFFAQJDAAdAGcKAA==.Lorkhan:BAABLgAECn8VAAIgAAkJ2xW4FQB1AQAgAAkJ2xW4FQB1AQAAAA==.Loxsmith:BAAALgAECgYJBgABLgAECgYJFQATAIIVAA==.',
Lt='Ltcclover:BAAALgAECgQJCQAAAA==.',
Ma='Maledict:BAABLgAECn8WAAIOAAcJlwYggwAiAQAOAAcJlwYggwAiAQAAAA==.Malgan:BAAALgAECgcJCQABLgAFFAIJBQACAAAAAQ==.Manhattan:BAAALgAECgcJDwABLgAFFAYJFQARAHcgAA==.Martini:BAAALgAECgQJCgABLgAFFAYJFQARAHcgAA==.',
Me='Meko:BAAALgAECgUJBwAAAA==.Merikaya:BAAALgAECggJCwAAAA==.Meèko:BAAALgAFFAEJAQAAAA==.Meéko:BAAALgADCgQJBAAAAA==.',
Mi='Miau:BAAALgAECgYJBgAAAA==.Mistafridge:BAAALgAECgIJAgABLgAECgYJFQATAIIVAA==.',
Mo='Mollie:BAAALgAECgIJAwABLgAFFAQJCwAeAEwjAA==.Monkedor:BAAALgADCgIJAgAAAA==.Moocelee:BAAALgAECgQJCAAAAA==.',
Mu='Murk:BAAALgADCgkJDQABLgAECgkJNQAFAEkbAA==.Murloc:BAAALgADCgEJAQAAAA==.',
Na='Nah:BAAALgADCgcJBwAAAA==.Nahshadah:BAAALgADCggJCAAAAA==.Nanome:BAABLgAECn8VAAITAAYJghU1jgA/AQATAAYJghU1jgA/AQAAAA==.Nazure:BAAALgAECgEJAQAAAA==.',
Ne='Nedra:BAAALgADCgEJAQABLgAECgYJBgACAAAAAA==.Nesral:BAABLgAECn8ZAAINAAgJrhTDJwAaAgANAAgJrhTDJwAaAgAAAA==.Nevoir:BAAALgAECggJCQAAAA==.',
Nh='Nhasir:BAACLgAFFH8TAAIXAAUJ4RNIFgD3AAAXAAUJ4RNIFgD3AAAuAAQKfyIAAhcACQmHISQHAL4CABcACQmHISQHAL4CAAAA.Nhastea:BAABLgAECn8XAAIeAAcJgxqzGwCpAQAeAAcJgxqzGwCpAQABLgAFFAUJEwAXAOETAA==.',
Ni='Niceneasy:BAAALgAECgMJAwAAAA==.',
No='Normal:BAAALgAECgMJAwAAAA==.Nowaifu:BAAALgAECgYJDAAAAA==.',
Od='Odrade:BAAALgADCgIJAgABLgADCgIJAgACAAAAAA==.',
Ow='Owlbread:BAABLgAECn8VAAIhAAkJ6wnQFwBCAQAhAAkJ6wnQFwBCAQAAAA==.',
Oz='Ozwin:BAABLgAECn8VAAIeAAYJYRbCLAA2AQAeAAYJYRbCLAA2AQABLgAFFAUJFQAGAJUhAA==.',
Pe='Peccator:BAACLgAFFH8NAAIJAAQJOB/+CgBgAQAJAAQJOB/+CgBgAQAuAAQKfyMAAgkACQmRIu8CAE8DAAkACQmRIu8CAE8DAAAA.Pein:BAAALgADCgIJAgAAAA==.Percdirty:BAAALgADCgUJCAAAAA==.Persess:BAAALgADCgYJBgAAAA==.',
Ph='Phatality:BAEALgAECgMJCQABLgAECgQJBQACAAAAAA==.',
Pi='Pillowpants:BAAALgAECgUJBQAAAA==.',
Pl='Plat:BAAALgAECgEJAQAAAA==.Platsearthen:BAABLgAECn8cAAIBAAgJqAMu0QDMAAABAAgJqAMu0QDMAAAAAA==.Ploo:BAAALgADCgcJAQAAAA==.',
Pn='Pneumma:BAAALgAECgcJCQAAAA==.',
Po='Poodrinker:BAAALgAECgEJAQABLgAECgcJEAACAAAAAA==.',
Pr='Priya:BAAALgAECgYJEAAAAA==.Protect:BAAALgAECgMJBAABLgAFFAMJCAANAKUXAA==.Pròm:BAAALgAECgIJAQAAAA==.',
Ra='Ramordis:BAAALgADCgEJAQAAAA==.Ravia:BAABLgAECn8XAAIiAAcJDhyhBwALAgAiAAcJDhyhBwALAgAAAA==.',
Re='Rebyen:BAAALgADCgYJBQAAAA==.Refr:BAAALgAECggJCAAAAA==.Regularhorns:BAABLgAECn8XAAIOAAgJSg5mZwAxAQAOAAgJSg5mZwAxAQAAAA==.Rendhoof:BAAALgAECgIJBAAAAA==.Renzo:BAAALgADCgcJBwABLgAFFAUJFQAGAJUhAA==.Reptarr:BAAALgAECgUJBQABLgAECgYJFQATAIIVAA==.Restodruid:BAAALgAECgQJBAAAAA==.Rev:BAAALgADCgQJCAAAAA==.',
Ri='Richter:BAAALgADCgkJCQAAAA==.Rins:BAABLgAECn8XAAQWAAcJtyNDFQASAgAWAAcJRSNDFQASAgAVAAQJ2R0BGAADAQAbAAEJUx7FmwBWAAAAAA==.Rinslet:BAABLgAECn8VAAMRAAkJdBsHDgBRAgARAAgJyBwHDgBRAgAKAAMJQRXsQwC6AAABLgAECgcJFwAWALcjAA==.Riskante:BAACLgAFFH8LAAIBAAQJGhMfLgAzAQABAAQJGhMfLgAzAQAuAAQKfzMAAwEACQlLHb0XAJYCAAEACQlLHb0XAJYCAAQABQlmEfJbAA0BAAAA.',
Ro='Roonrana:BAAALgAECgMJBQAAAA==.Rosey:BAACLgAFFH8PAAIjAAUJtBm8AgBeAQAjAAUJtBm8AgBeAQAuAAQKfzUAAiMACAn1IWsCAHoCACMACAn1IWsCAHoCAAAA.',
Ru='Rubýrose:BAAALgAECgEJAQAAAA==.Rulutieh:BAAALgAECgMJBgAAAA==.Runebraker:BAAALgAECgYJCwAAAA==.',
Sa='Sandfordays:BAAALgAECgMJBgAAAA==.Sardor:BAAALgAECgQJCAABLgAFFAUJFQAGAJUhAA==.',
Sc='Scorn:BAAALgAECgkJEQAAAA==.Scottyno:BAACLgAFFH8KAAIBAAMJyxcQRgD2AAABAAMJyxcQRgD2AAAuAAQKfyYAAgEACQmrHtkSALcCAAEACQmrHtkSALcCAAAA.',
Se='Sempast:BAACLgAFFH8GAAILAAMJLCAgSAATAQALAAMJLCAgSAATAQAuAAQKfy0AAwsACQmuIjQHAAwDAAsACAmLIjQHAAwDABAABAngImcZAIABAAAA.Senarria:BAAALgAECgEJAQAAAA==.',
Sh='Shadyfear:BAAALgAECgEJAQAAAA==.Shaldin:BAABLgAECn8UAAIbAAcJBCDYIQAWAgAbAAcJBCDYIQAWAgAAAA==.Shaluesta:BAAALgAECgMJBAAAAA==.Shaluestaa:BAAALgAECgcJBwAAAA==.Shanithell:BAAALgADCgIJAgAAAA==.Shanksz:BAAALgAECgIJAwAAAA==.Shellyd:BAABLgAECn8gAAIaAAkJ1RNQGgD3AQAaAAkJ1RNQGgD3AQAAAA==.Shiryû:BAAALgADCgEJAQAAAA==.',
Si='Siennaa:BAAALgAECgIJAgAAAA==.Sinfulsmite:BAAALgADCgEJAQABLgAECgQJCgACAAAAAA==.Sins:BAACLgAFFH8NAAQFAAUJjhYiFgBLAQAFAAQJMxUiFgBLAQAGAAMJ5BA7DgDNAAAXAAEJAACATAAAAAAuAAQKfxYAAgUACAmFHxApAJYCAAUACAmFHxApAJYCAAAA.',
Sl='Slide:BAAALgAECgYJBgAAAA==.',
Sn='Sneakyhand:BAACLgAFFH8XAAMaAAUJryWdBAC/AQAaAAUJryWdBAC/AQAkAAQJICNICQBiAQAuAAQKfzAABBoACQlTJRYEAGoDABoACAkUJhYEAGoDACQABAlNI34VAIgBABkAAgl5IIYqALoAAAAA.',
So='Soupson:BAAALgADCgIJAgABLgAECgYJEAACAAAAAA==.',
St='Steelt:BAAALgAECgYJCwABLgAFFAQJBAACAAAAAA==.Steris:BAAALgAECgYJEAAAAA==.Stinkindwarf:BAAALgAECgQJBAAAAA==.Stizzy:BAAALgAECgMJBQAAAA==.',
Su='Sunadora:BAAALgAECgEJBAAAAA==.',
Sw='Swagula:BAABLgAECn8ZAAIgAAgJjiO+BACHAgAgAAgJjiO+BACHAgAAAA==.',
Sy='Sylvain:BAAALgAECgEJAQABLgAECgkJKAAWAJIdAA==.Sylvi:BAABLgAECn8XAAMlAAkJQhnqDAC5AQAlAAkJQhnqDAC5AQAhAAIJFRLUKwB2AAAAAA==.Syrup:BAAALgADCgkJCQAAAA==.Syurni:BAAALgADCgEJAgABLgAECgYJBgACAAAAAA==.',
Ta='Takitsu:BAACLgAFFH8VAAIlAAUJSwkODwDFAAAlAAUJSwkODwDFAAAuAAQKfy0AAiUACAmqFhUOAMYBACUACAmqFhUOAMYBAAAA.',
Th='Tharion:BAAALgAECgEJAQAAAA==.',
Ti='Tinyfist:BAAALgADCgYJBgAAAA==.Tired:BAAALgADCgEJAgAAAA==.',
To='Tombz:BAACLgAFFH8MAAIFAAUJDxqSOgBOAQAFAAUJDxqSOgBOAQAuAAQKfz4AAwUACQn0IMQaAIQCAAUACQn0IMQaAIQCABcAAgk1Ag5GADAAAAAA.Towa:BAAALgAECgMJBAAAAA==.',
Tr='Trilira:BAAALgADCgUJBwAAAA==.',
Tu='Turf:BAAALgADCgMJAgAAAA==.',
Ul='Ulangi:BAAALgAECgEJAQAAAA==.',
Un='Unbelavable:BAAALgAECgYJBwAAAA==.',
Ur='Uranis:BAAALgADCgEJAgAAAA==.Uroboros:BAAALgADCgEJAQAAAA==.Ursa:BAAALgAECgYJCgAAAA==.',
Ve='Veil:BAAALgAFFAIJBAABLgAFFAMJBgALACwgAA==.',
Vl='Vlorax:BAAALgADCgMJBgAAAA==.',
Vo='Volodinson:BAAALgAECgUJEAAAAA==.',
Vy='Vynesh:BAAALgADCgEJAwAAAA==.',
Wa='Wallê:BAAALgAECgEJAgAAAA==.Wandwanker:BAABLgAECn8aAAImAAkJ7h0kAQCRAgAmAAkJ7h0kAQCRAgAAAA==.Warsawz:BAAALgAECgEJAgAAAA==.',
We='Wetasscat:BAABLgAECn8UAAILAAkJQR5MOQAmAgALAAkJQR5MOQAmAgAAAA==.Weyae:BAAALgAECgQJCQAAAA==.',
Wh='Whorg:BAACLgAFFH8IAAINAAMJpRd5RgDcAAANAAMJpRd5RgDcAAAuAAQKfysAAw0ACAlkH7o0AOABAA0ACAneHLo0AOABACcABglHHPISAJQBAAAA.',
Wi='Willyboi:BAABLgAECn8iAAMTAAgJaRPUUgDHAQATAAgJaRPUUgDHAQAmAAQJNwp9DwDKAAAAAA==.Wisemanorc:BAAALgAECgMJBQAAAA==.',
Xa='Xavierr:BAABLgAECn8ZAAIdAAgJXhJEJQCvAQAdAAgJXhJEJQCvAQAAAA==.',
Ya='Yarkaz:BAAALgAECgQJCwAAAA==.',
Yi='Yinli:BAAALgAECgEJAQAAAA==.',
Yu='Yucky:BAAALgAECgEJAQABLgAECggJEwACAAAAAA==.Yuuyu:BAAALgAECgYJBgAAAA==.',
Za='Zaai:BAAALgADCgcJCgAAAA==.Zargus:BAABLgAECn8oAAIWAAkJkh0eHQDMAQAWAAkJkh0eHQDMAQAAAA==.Zarlunce:BAABLgAECn8iAAIaAAkJVRvUGAAEAgAaAAkJVRvUGAAEAgAAAA==.',
Ze='Zetsuon:BAABLgAECn81AAIHAAkJhR71CQD+AgAHAAkJhR71CQD+AgAAAA==.',
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
