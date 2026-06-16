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

local lookup = {'Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','DeathKnight-Blood','Warrior-Arms','Warrior-Fury','Warrior-Protection','Mage-Frost','Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Paladin-Retribution','Hunter-Survival','Druid-Restoration','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Priest-Discipline','Paladin-Holy','DeathKnight-Unholy','Evoker-Augmentation','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Druid-Guardian','Priest-Shadow','DemonHunter-Havoc','Rogue-Subtlety','DeathKnight-Frost','Priest-Holy','Shaman-Enhancement','Rogue-Assassination','Druid-Feral','Hunter-Marksmanship',}
local provider = {region='US',realm='Gorgonnash',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aakira:BAABLgAECn8VAAMBAAkJzQjpPAA9AQABAAkJzQjpPAA9AQACAAEJuAOW5gAkAAAAAA==.Aangie:BAABLgAECn8YAAIDAAcJngZMPAD0AAADAAcJngZMPAD0AAAAAA==.Aanjie:BAABLgAECn8aAAIDAAYJQwk4aQDSAAADAAYJQwk4aQDSAAAAAA==.Aathea:BAAALgAECgYJBgAAAA==.',
Ab='Abban:BAAALgAECgMJAwAAAA==.Abom:BAAALgAECgIJAgAAAA==.Abrastal:BAAALgAECgQJCAAAAA==.',
Ad='Adrestia:BAAALgAECgQJBgAAAA==.',
Ak='Akbar:BAAALgAECgUJBQAAAA==.',
Al='Alline:BAABLgAECn8dAAIEAAYJcBL4JQAgAQAEAAYJcBL4JQAgAQAAAA==.Alswaron:BAAALgAECgUJEwAAAA==.',
Am='Amador:BAACLgAFFH8VAAQFAAQJ8R6gEgBCAQAFAAQJnB2gEgBCAQAGAAMJoRQSPwCeAAAHAAEJnB3tKABLAAAuAAQKfyoABAUACQl5IrkGAI0CAAUACAl5IrkGAI0CAAYABAndGulpAA4BAAcAAgmuFo06AHcAAAAA.Amorlan:BAAALgAECgEJAQAAAA==.Amyra:BAAALgAECgEJAQAAAA==.',
An='Annox:BAAALgAECgQJBwAAAA==.',
Ap='Apsallar:BAABLgAECn8aAAIIAAkJhRtkJQCEAgAIAAkJhRtkJQCEAgAAAA==.',
Ar='Arcanedream:BAAALgAECgUJBQABLgAECgcJCQAJAAAAAA==.Arcanism:BAABLgAECn8cAAIIAAcJshOjngCZAQAIAAcJshOjngCZAQAAAA==.Arlas:BAAALgAECgIJAwAAAA==.Arthone:BAAALgADCgUJBQAAAA==.',
As='Aserai:BAAALgADCgMJAwAAAA==.Asstalor:BAABLgAECn8dAAMKAAgJmxAzYwB4AQAKAAgJWxAzYwB4AQALAAEJjxJOPQA0AAAAAA==.',
Au='Auggy:BAAALgAECgMJAwAAAA==.Auryon:BAACLgAFFH8FAAIMAAEJcxjWmABQAAAMAAEJcxjWmABQAAAuAAQKfzAAAgwACAnDIW8hAFsCAAwACAnDIW8hAFsCAAAA.',
Av='Avelna:BAAALgADCgcJBwABLgADCgcJDQAJAAAAAA==.',
Az='Azmodea:BAAALgADCgEJAgAAAA==.',
Ba='Baccstab:BAAALgAECgYJDAAAAA==.Bagains:BAAALgADCgcJEwAAAA==.Baraka:BAAALgAECgYJCgAAAA==.Baulder:BAABLgAECn8cAAIGAAcJaweGTwAJAQAGAAcJaweGTwAJAQAAAA==.',
Bi='Bigb:BAAALgAFFAEJAQABLgAFFAkJMAAIAL0jAA==.Bigolcrittie:BAAALgADCgIJAgAAAA==.',
Bl='Blerpleberry:BAAALgAECgUJBQAAAA==.Bloodfurry:BAAALgAECgMJAQAAAA==.Bluè:BAABLgAECn8ZAAMBAAgJ+BTvLwB8AQABAAgJ+BTvLwB8AQACAAUJjBq9TAB5AQAAAA==.',
Bn='Bnakka:BAAALgAFFAEJAQAAAA==.',
Bo='Bobdaunicorn:BAAALgAECgEJAQAAAA==.Boltz:BAAALgAECgMJAwAAAA==.Bombalaharis:BAAALgAECgcJDQAAAA==.',
Br='Brekke:BAACLgAFFH8MAAINAAQJsQ++SAAWAQANAAQJsQ++SAAWAQAuAAQKfy8AAg0ACQlgGME0ACsCAA0ACQlgGME0ACsCAAAA.Brokenbow:BAACLgAFFH8HAAMOAAQJjQoQIADSAAAOAAMJwgcQIADSAAAMAAEJ7BJ5ngBJAAAuAAQKfxsAAw4ACQmmE7QeAKYBAA4ACQnNDrQeAKYBAAwABAkIGMV9AO4AAAAA.',
Bu='Bullshaft:BAAALgAECgEJAQAAAA==.Buntz:BAABLgAECn8qAAINAAkJgCM0DAACAwANAAkJgCM0DAACAwAAAA==.Bushmethsin:BAACLgAFFH8bAAIPAAcJLSPtBAC9AgAPAAcJLSPtBAC9AgAuAAQKfxUAAg8ACAlVIg0eAE4CAA8ACAlVIg0eAE4CAAAA.Buttery:BAAALgAECgcJEgAAAA==.',
Bz='Bz:BAAALgADCgcJBwAAAA==.',
Ca='Cabb:BAABLgAECn8WAAMGAAYJihajRgApAQAGAAQJGxqjRgApAQAHAAYJtgdxMAC5AAAAAA==.',
Ce='Ceedubble:BAAALgAECgkJDgAAAA==.Celestine:BAAALgADCgYJBgABLgAECgkJKAAQAEsOAA==.',
Ch='Charmanderz:BAABLgAECn8mAAMRAAgJIxFyFQBxAQARAAgJIxFyFQBxAQASAAEJIhWjOwA/AAABLgAECgkJFAATAO8LAA==.Cherchlglsia:BAAALgADCgQJCAAAAA==.Chewsdee:BAAALgAECgQJBAAAAA==.Christlovesu:BAAALgAECgIJAgAAAA==.Chuckrules:BAAALgADCgcJDgAAAA==.',
Cl='Clackshi:BAAALgAECgYJCgAAAA==.',
Cr='Critable:BAABLgAECn8yAAMUAAkJIxbfGgArAgAUAAkJIxbfGgArAgANAAgJNggXggB2AQAAAA==.',
Cu='Curst:BAAALgAECggJEwAAAA==.',
Da='Dagares:BAAALgADCggJDQAAAA==.Dahnte:BAAALgAECgEJAQAAAA==.',
De='Dechala:BAABLgAECn8oAAIQAAkJSw49UgCLAQAQAAkJSw49UgCLAQAAAA==.Deezknights:BAACLgAFFH8UAAMVAAgJzBzPEABFAgAVAAgJzBzPEABFAgAEAAEJAAB3VgAAAAAuAAQKfycAAhUACQkGJU4JAFIDABUACQkGJU4JAFIDAAAA.Deezpuffs:BAABLgAFFH8KAAMWAAQJOxWyLAANAQAWAAQJOxWyLAANAQARAAEJpQDYLwAiAAABLgAFFAgJFAAVAMwcAA==.Deezrage:BAAALgADCgYJBgAAAA==.Derailed:BAAALgADCgEJAgAAAA==.Dergon:BAACLgAFFH8FAAIKAAMJNw0jegDKAAAKAAMJNw0jegDKAAAuAAQKfykAAgoACQloHLAjAE8CAAoACQloHLAjAE8CAAAA.Destiria:BAABLgAECn8kAAMKAAgJuBlrQADaAQAKAAgJuBlrQADaAQAXAAMJegd5JwBUAAAAAA==.Devistatorxx:BAAALgAECgYJCgAAAA==.',
Do='Doggyystyle:BAAALgAECgEJAQAAAA==.Donaldpump:BAAALgAECgYJBwAAAA==.Doomedturtle:BAAALgAECgMJBAAAAA==.Doublekill:BAAALgAECgUJDAAAAA==.',
Du='Duergan:BAACLgAFFH8RAAIYAAQJ6xAPGQD5AAAYAAQJ6xAPGQD5AAAuAAQKfykABBgACQkDElArAGABABgACAkTFFArAGABABkACAnEBSo4ABkBAAMAAQlFAwRyACEAAAAA.',
['Dà']='Dàrkblade:BAAALgAECgQJBwAAAA==.',
Ea='Eatz:BAAALgADCgYJBgAAAA==.',
Eh='Ehcks:BAAALgAECgQJBAAAAA==.',
Em='Emotionaldmg:BAAALgADCgYJCwAAAA==.',
Fa='Faelyn:BAAALgADCgEJBAAAAA==.Fansy:BAAALgAECgYJBwAAAA==.',
Fe='Felwind:BAABLgAECn8UAAIMAAcJJR7EMAAVAgAMAAcJJR7EMAAVAgAAAA==.',
Fi='Fillycheese:BAAALgAECgEJAQAAAA==.',
Fl='Fleurelle:BAAALgAECgIJAgAAAA==.',
Fr='Frollo:BAAALgAECgEJAQAAAA==.Frosstitute:BAAALgAECgMJAwAAAA==.',
Fu='Furfiend:BAACLgAFFH8IAAIVAAQJYxcsUQBLAQAVAAQJYxcsUQBLAQAuAAQKfykAAxUACQndH2sqAFQCABUACQlaHmsqAFQCAAQABQk4G/4nABEBAAAA.',
Gi='Giantdog:BAAALgAECgUJBQAAAA==.Gilraen:BAACLgAFFH8MAAMGAAQJ+g0NJwAUAQAGAAQJVgwNJwAUAQAFAAEJXQ8LQgA+AAAuAAQKfz8AAwUACQk3GaUNAAsCAAUACQn5FqUNAAsCAAYACQmSE/omAMABAAAA.Gingerjen:BAABLgAECn8UAAMPAAgJ9wdlZAAFAQAPAAgJ9wdlZAAFAQAaAAgJcgPRUADFAAAAAA==.',
Go='Gorgrand:BAAALgAECgcJBwAAAA==.Gothbiotch:BAAALgAECgMJAwAAAA==.',
Gr='Greggnog:BAAALgAECgkJDAAAAA==.Greggy:BAAALgAECgUJCQABLgAECgkJDAAJAAAAAA==.Grenache:BAAALgAECgMJBAAAAA==.',
Ha='Hairypotter:BAAALgADCgIJAgAAAA==.Halfworld:BAAALgADCgYJBgAAAA==.Happydaze:BAACLgAFFH8GAAIEAAMJKBGjKACsAAAEAAMJKBGjKACsAAAuAAQKfyoAAwQACQlUG44PABACAAQACQkGG44PABACABUAAgnZF4HuAKEAAAAA.Harshdruid:BAAALgAECgEJAQAAAA==.Haxthedk:BAAALgAECgEJAQAAAA==.Haxthedruid:BAAALgAECgEJAQAAAA==.Haxthemonk:BAAALgAECgEJAQAAAA==.',
He='Hemotoxin:BAAALgAECgMJAwAAAA==.Hendel:BAAALgAECgQJBgAAAA==.Herkaferk:BAABLgAECn8XAAIBAAYJiBMNRAAfAQABAAYJiBMNRAAfAQAAAA==.',
Ho='Hojx:BAAALgAECgEJAQAAAA==.',
Hr='Hrolf:BAABLgAECn8qAAIbAAgJHRGaHQBbAQAbAAgJHRGaHQBbAQABLgAFFAQJEQAYAOsQAA==.',
Il='Illiannà:BAABLgAECn8UAAMTAAkJ7ws5JACqAQATAAkJ7ws5JACqAQAcAAEJwRXbewBBAAAAAA==.Illidont:BAABLgAECn8WAAIdAAkJWRBPGwCfAQAdAAkJWRBPGwCfAQAAAA==.Illijr:BAABLgAECn8cAAIdAAkJ1BMbFQDiAQAdAAkJ1BMbFQDiAQAAAA==.',
It='Ithil:BAAALgADCgkJDwAAAA==.',
Ja='Jaemison:BAAALgADCgQJAwAAAA==.',
Ji='Jicks:BAABLgAECn8gAAITAAcJpAkJOQAsAQATAAcJpAkJOQAsAQAAAA==.',
Jk='Jkass:BAACLgAFFH8GAAIeAAMJ/wv9KgDOAAAeAAMJ/wv9KgDOAAAuAAQKfxsAAh4ACAn+FosbALYBAB4ACAn+FosbALYBAAAA.',
Ju='Judgementdày:BAAALgAECggJCgAAAA==.',
['Jà']='Jàk:BAAALgAECgIJAgAAAA==.',
Ka='Kamaeria:BAACLgAFFH8MAAIcAAQJEgNnJwC6AAAcAAQJEgNnJwC6AAAuAAQKfzMAAhwACQndERwcAOMBABwACQndERwcAOMBAAEuAAUUBAkMAAwApwUA.Kaíros:BAAALgADCgMJAwAAAA==.',
Kh='Khaotica:BAAALgADCgkJCQAAAA==.',
Ki='Kiandara:BAACLgAFFH8aAAMGAAUJrhm1HAA6AQAGAAUJrhm1HAA6AQAFAAQJwRL7GQARAQAuAAQKfyQAAwYACQmQHPIMAO4CAAYACQmQHPIMAO4CAAcABQkcG94dAFcBAAAA.Kikkoman:BAABLgAFFH8FAAIeAAMJmBlEIwABAQAeAAMJmBlEIwABAQAAAA==.Kilmas:BAAALgAECgIJAgAAAA==.Kirant:BAAALgADCggJDQAAAA==.Kirara:BAAALgADCgYJBgAAAA==.',
Ko='Kooz:BAAALgADCgUJBQAAAA==.Kooze:BAAALgADCgUJCAAAAA==.Koozo:BAAALgADCgMJAwAAAA==.',
Kt='Kt:BAABLgAECn8aAAIIAAcJNhODlwBGAQAIAAcJNhODlwBGAQAAAA==.',
Ku='Kush:BAAALgADCgEJAQABLgAECgkJKgANAIAjAA==.',
Ky='Kynrath:BAAALgAECgYJCQAAAA==.',
La='Laurie:BAAALgADCgMJBgAAAA==.Lava:BAAALgADCgUJBQABLgAECggJDwAJAAAAAA==.Lavablast:BAAALgADCgYJCwAAAA==.',
Le='Lelanie:BAAALgADCggJDgAAAA==.',
Li='Lichnfamous:BAACLgAFFH8IAAIVAAQJ/AsmcwAYAQAVAAQJ/AsmcwAYAQAuAAQKfykAAxUACAnRFW1MANoBABUACAnRFW1MANoBAB8ABAnqDB8fAM8AAAAA.Lightfrost:BAAALgAECgIJAgAAAA==.Lightning:BAAALgAECgUJCAAAAA==.Likkan:BAAALgAECgEJAQAAAA==.Lilithdawn:BAABLgAECn8iAAIgAAkJvhuiEABdAgAgAAkJvhuiEABdAgAAAA==.',
Lo='Lockwar:BAABLgAECn8aAAQXAAcJrRalCgCwAQAXAAcJrRalCgCwAQAKAAQJFAeh4gCVAAALAAEJTwB4SAAFAAAAAA==.Louvre:BAABLgAECn8uAAIeAAkJtxw3CQCQAgAeAAkJtxw3CQCQAgAAAA==.',
Lu='Lukarian:BAABLgAFFH8GAAINAAMJiw5ubgDOAAANAAMJiw5ubgDOAAAAAA==.',
Ma='Makthra:BAAALgAECgUJEQAAAA==.Marek:BAAALgADCgUJCAAAAA==.Marionette:BAAALgADCgkJGwAAAA==.Mawseeker:BAAALgADCgEJAQAAAA==.',
Me='Megabettegaa:BAACLgAFFH8PAAIVAAMJlRl0jQDrAAAVAAMJlRl0jQDrAAAuAAQKf3UAAhUACQlsGMwrAE4CABUACQlsGMwrAE4CAAAA.Mennathil:BAAALgADCgEJAQAAAA==.Meric:BAAALgAECgEJAwAAAA==.',
Mi='Microbrew:BAAALgAECgcJCQABLgAECgkJNQAbAHEbAA==.Midnight:BAAALgAECgcJCQAAAA==.Milo:BAAALgAFFAEJAQAAAA==.Miniangel:BAACLgAFFH8RAAMgAAUJjxTmDgBbAQAgAAUJjxTmDgBbAQAcAAIJfQGENQBXAAAuAAQKfx4AAyAACQl8FQAVACoCACAACQl8FQAVACoCABwACAk+EPAoAJMBAAAA.Mixednuts:BAAALgAECgIJAgAAAA==.',
Mo='Molasses:BAACLgAFFH8bAAIIAAUJuxHqXAAwAQAIAAUJuxHqXAAwAQAuAAQKf0AAAggACQnTHg8XAMwCAAgACQnTHg8XAMwCAAAA.Moof:BAAALgAECgEJAQAAAA==.',
['Mú']='Músic:BAAALgAECgIJAwAAAA==.',
Na='Najitar:BAAALgAECgQJBQAAAA==.Nazaibrew:BAAALgAECggJDAABLgAECgkJMgATAIgeAA==.Nazera:BAAALgAECgEJAQAAAA==.',
Ne='Necromalus:BAAALgAECgEJAgAAAA==.Neerx:BAAALgADCgUJBQAAAA==.',
Nu='Nubkselk:BAABLgAECn8zAAIQAAkJ7x2zFQCTAgAQAAkJ7x2zFQCTAgAAAA==.Nurishment:BAACLgAFFH8cAAIPAAgJAhSzCwAuAgAPAAgJAhSzCwAuAgAuAAQKfyUAAg8ACQn7HWwSAKICAA8ACQn7HWwSAKICAAAA.',
Ny='Nyrr:BAAALgADCgEJAgAAAA==.',
Og='Ogmurka:BAAALgAECgEJAQAAAA==.',
On='Oni:BAAALgADCgUJBQAAAA==.Onitachi:BAABLgAECn8rAAMBAAgJzxF1RQAaAQABAAgJzxF1RQAaAQAhAAQJcAk4LQCEAAAAAA==.',
Op='Optistriker:BAABLgAECn9LAAIPAAkJaxndFAChAgAPAAkJaxndFAChAgAAAA==.',
Oy='Oythsar:BAAALgADCgQJBAAAAA==.',
Pa='Painfree:BAAALgADCgQJBAAAAA==.Papabear:BAAALgAECgEJAQAAAA==.',
Pe='Pemburumalam:BAAALgADCgEJAQAAAA==.',
Pi='Pig:BAABLgAECn8cAAIGAAgJKhjaKwAGAgAGAAgJKhjaKwAGAgABLgAECgkJKgANAIAjAA==.Pinks:BAAALgADCgkJCQAAAA==.Pizlex:BAAALgAECgMJAwAAAA==.',
Po='Poplockndrop:BAAALgAECgUJBgAAAA==.Portion:BAABLgAECn8uAAIIAAgJWhwTVgDXAQAIAAgJWhwTVgDXAQAAAA==.Portlybob:BAAALgADCgEJAQAAAA==.',
Pr='Pretentious:BAACLgAFFH8GAAINAAQJrQzCTQAOAQANAAQJrQzCTQAOAQAuAAQKfx4AAg0ACAmiHysmAI4CAA0ACAmiHysmAI4CAAAA.Prettyfun:BAAALgADCgUJBQAAAA==.Prettysavage:BAAALgAECgIJAgAAAA==.Primo:BAAALgADCgYJEQAAAA==.',
['Pè']='Pèrsephônè:BAAALgADCgIJAgAAAA==.',
Ra='Radicalism:BAAALgAECgQJBQAAAA==.Raechan:BAAALgAECgEJAQAAAA==.Ranigard:BAAALgAECgUJCAAAAA==.Rantioc:BAAALgAECgUJBQAAAA==.Raugan:BAAALgAECgEJAgAAAA==.',
Re='Reparations:BAABLgAECn8ZAAMcAAgJewXNRwDtAAAcAAgJewXNRwDtAAATAAUJugKtXwB4AAAAAA==.Repentofsin:BAAALgAECgQJBAAAAA==.Rexbriefs:BAABLgAECn8jAAIVAAcJoQyTlgA4AQAVAAcJoQyTlgA4AQAAAA==.',
Ri='Rice:BAAALgAFFAEJAQAAAA==.Riptong:BAAALgADCgEJAQAAAA==.',
Ro='Rovinj:BAAALgAECgkJBwAAAA==.',
Ru='Rumi:BAABLgAECn8iAAIQAAgJUxbLPgDKAQAQAAgJUxbLPgDKAQAAAA==.',
Ry='Rydle:BAABLgAFFH8HAAIMAAMJDhKHWwDmAAAMAAMJDhKHWwDmAAAAAA==.',
Sa='Samedhi:BAAALgAECgQJBQAAAA==.Sanlesh:BAAALgADCgUJBgAAAA==.Sapodillà:BAAALgAECggJDQAAAA==.Sarijevo:BAAALgAECgkJBQAAAA==.Saurax:BAAALgAECgEJAgAAAA==.',
Sc='Scatz:BAAALgADCgIJAgAAAA==.Scott:BAAALgAECgcJCwAAAA==.Scylla:BAAALgAECgYJDwAAAA==.',
Se='Sevrin:BAACLgAFFH8QAAIeAAQJjCCMEQB7AQAeAAQJjCCMEQB7AQAuAAQKfy8AAh4ACQlrIwEFAOUCAB4ACQlrIwEFAOUCAAAA.',
Sh='Shadowfuryy:BAAALgAECgUJBQAAAA==.Shalati:BAAALgADCgYJBgAAAA==.Sharts:BAAALgADCgYJCAAAAA==.Shestrouble:BAACLgAFFH8GAAIIAAIJyhsklQCkAAAIAAIJyhsklQCkAAAuAAQKfyAAAggACQmrIs8JACkDAAgACQmrIs8JACkDAAAA.Shirerat:BAAALgADCgMJBAAAAA==.Shtzson:BAABLgAECn8WAAIZAAkJ5xdYEAA4AgAZAAkJ5xdYEAA4AgAAAA==.Shyjinx:BAAALgAECgYJBgAAAA==.Shíft:BAAALgAECgUJBQABLgAFFAMJCgAeAPEiAA==.Shííft:BAAALgAECgUJBQABLgAFFAMJCgAeAPEiAA==.Shîft:BAACLgAFFH8KAAIeAAMJ8SL4GwA2AQAeAAMJ8SL4GwA2AQAuAAQKfzEAAx4ACQnQI4cGAMQCAB4ACAnPI4cGAMQCACIAAwkgH7gSAPgAAAAA.',
Si='Siiwwy:BAAALgAECgMJAwAAAA==.',
Sl='Slice:BAAALgAFFAEJAQAAAA==.',
Sn='Snugglemuff:BAAALgAECgcJDQABLgAFFAQJBgANAK0MAA==.',
So='Sok:BAAALgAECgEJAwAAAA==.Soladin:BAAALgAECgQJBQABLgAECgkJNQAbAHEbAA==.Solicide:BAABLgAECn81AAUbAAkJcRsLDwDvAQAbAAgJ4hgLDwDvAQAjAAcJ8RueDADnAQAPAAEJRBMbyAA6AAAaAAEJ2g5njAAxAAAAAA==.Solthicc:BAAALgAECggJDQAAAA==.Sonarra:BAAALgAECgYJBgAAAA==.',
Sp='Sparkle:BAACLgAFFH8hAAIWAAcJExQrEwDTAQAWAAcJExQrEwDTAQAuAAQKf4EAAhYACQkdJtkAAIIDABYACQkdJtkAAIIDAAAA.Splatacular:BAAALgADCgEJAQAAAA==.',
St='Stolenhearth:BAABLgAECn8pAAIGAAYJVwxvWADsAAAGAAYJVwxvWADsAAAAAA==.',
Sv='Svets:BAABLgAECn8yAAMTAAkJiB61CADnAgATAAkJiB61CADnAgAgAAEJ3AnKhQArAAAAAA==.',
Sw='Swavey:BAAALgADCgQJBAAAAA==.',
Sy='Sylphrenna:BAAALgAECgcJCQAAAA==.Syrana:BAAALgADCgEJAQAAAA==.',
Te='Teeanna:BAAALgAECgIJAgABLgAECgIJAwAJAAAAAA==.Temaile:BAAALgADCgEJBAAAAA==.Tenin:BAAALgADCgEJAQAAAA==.',
Th='Thinmint:BAAALgADCgEJAQAAAA==.Thoranter:BAAALgADCgYJBgAAAA==.',
Ti='Tinnman:BAAALgADCgYJBgAAAA==.',
To='Toughguytony:BAAALgADCgUJBgAAAA==.',
Tr='Trebekk:BAAALgADCgEJAQAAAA==.Treydk:BAACLgAFFH8NAAIVAAQJWh1ESgBZAQAVAAQJWh1ESgBZAQAuAAQKfxwAAxUACQm/HSIZAK0CABUACQl2HSIZAK0CAB8ABQkYHNQYAAoBAAAA.Trreyy:BAABLgAECn8fAAINAAgJqh5YKACEAgANAAgJqh5YKACEAgAAAA==.',
Ts='Tsimfuqis:BAABLgAFFH8LAAIeAAQJMhIzHQAvAQAeAAQJMhIzHQAvAQAAAA==.',
Tw='Twighumper:BAAALgAECgUJBwABLgAECgkJFgAZAOcXAA==.Twizzly:BAAALgAFFAIJAgAAAA==.Twizzy:BAACLgAFFH8MAAIMAAQJpwWuXADjAAAMAAQJpwWuXADjAAAuAAQKf0IAAgwACQnyFIQnAD0CAAwACQnyFIQnAD0CAAAA.',
Ty='Tyranhikar:BAAALgADCgEJAQAAAA==.',
Tz='Tzechan:BAACLgAFFH8GAAIUAAMJ8RpTJQDwAAAUAAMJ8RpTJQDwAAAuAAQKfx8AAxQACQkiG1MdABYCABQACQkiG1MdABYCAA0AAgmcEvA5AW0AAAAA.',
Ug='Uggalee:BAAALgAFFAIJAwAAAA==.',
Va='Valtirya:BAAALgAECgQJBgAAAA==.Vampirellaa:BAAALgAECgEJAQAAAA==.Vayzen:BAABLgAECn8YAAIWAAcJDB4uEwBNAgAWAAcJDB4uEwBNAgAAAA==.',
Vi='Virexus:BAAALgADCgIJAgAAAA==.',
Vo='Voidfree:BAABLgAECn8nAAIQAAgJIgqPcQA7AQAQAAgJIgqPcQA7AQAAAA==.',
Vy='Vynarc:BAABLgAECn8qAAINAAgJihHPZQC1AQANAAgJihHPZQC1AQAAAA==.',
Wa='Warcrimes:BAAALgAECgEJAQAAAA==.Watervendor:BAABLgAECn8vAAIIAAkJgBv4LwBXAgAIAAkJgBv4LwBXAgAAAA==.',
We='Wearegroot:BAAALgAECgEJAQAAAA==.Webedeadiy:BAAALgADCgEJAQAAAA==.',
Wh='Whiteknight:BAAALgAECgUJBQAAAA==.',
Wi='Wiggimbottom:BAAALgAECgYJEgAAAA==.Wihtè:BAAALgAECgMJAwAAAA==.Willscarlet:BAAALgADCgQJBAAAAA==.',
Wo='Wolffoxfangs:BAABLgAECn8VAAIMAAcJ/BUPZgBzAQAMAAcJ/BUPZgBzAQAAAA==.',
['Wá']='Wárpaiint:BAABLgAECn8jAAIkAAcJoQs+FwD2AAAkAAcJoQs+FwD2AAABLgAFFAMJBgAIAKkFAA==.',
Xa='Xalatoes:BAAALgAECgUJBQAAAA==.',
Xe='Xeados:BAAALgAECgIJAgAAAA==.',
Yi='Yin:BAAALgADCgcJDQAAAA==.',
['Yè']='Yèlloow:BAAALgAECgMJBQAAAA==.',
Za='Zaquel:BAAALgAFFAEJAQAAAA==.Zarcissa:BAAALgAECgYJDQAAAA==.Zavira:BAAALgADCgcJBwAAAA==.',
Ze='Zerofoxgiven:BAAALgAECgYJBgAAAA==.',
Zy='Zyrin:BAAALgAECgYJDwAAAA==.',
['ßl']='ßlackpanther:BAAALgAECgcJDwAAAA==.',
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
