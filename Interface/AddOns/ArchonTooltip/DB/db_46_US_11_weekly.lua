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

local lookup = {'Priest-Discipline','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Augmentation','Druid-Guardian','Druid-Restoration','Paladin-Retribution','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Priest-Shadow','Monk-Mistweaver','Rogue-Subtlety','Warlock-Destruction','Unknown-Unknown','Hunter-Marksmanship','DemonHunter-Vengeance','Evoker-Preservation','Warrior-Fury','Hunter-BeastMastery','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Druid-Feral','Rogue-Outlaw','Priest-Holy','Druid-Balance','Mage-Arcane','Paladin-Protection','Monk-Brewmaster','Rogue-Assassination','DeathKnight-Frost',}
local provider = {region='US',realm='Andorhal',name='US',type='weekly',zone=46,date='2026-06-20',data={Ad='Adelyne:BAAALgAECgQJAwABLgAFFAUJEgABABkcAA==.Adorablepine:BAABLgAECn8ZAAMCAAcJuANvxQDEAAACAAcJrANvxQDEAAADAAEJqgP2RQAgAAAAAA==.',
Ag='Agaze:BAACLgAFFH8ZAAIEAAcJESDKHADOAQAEAAcJESDKHADOAQAuAAQKfxYAAgQACAkTIgAZAL8CAAQACAkTIgAZAL8CAAAA.',
Ai='Aiedel:BAAALgAECgUJCQAAAA==.',
Al='Allesa:BAAALgAECgEJAQAAAA==.',
Ao='Aoise:BAAALgAECgkJCgAAAA==.',
Ap='Applejuuice:BAABLgAFFH8HAAIFAAMJexZGmgDbAAAFAAMJexZGmgDbAAABLgAFFAQJBwAGAMAKAA==.',
Ar='Aratre:BAAALgADCgEJAQAAAA==.Archblade:BAAALgAECgQJBwAAAA==.Arelith:BAAALgAECgMJBwAAAA==.Ariggs:BAAALgAECgEJAQAAAA==.Ariosx:BAABLgAFFH8GAAMHAAIJDAeLNwBIAAAHAAIJDAeLNwBIAAAIAAEJswIffQAmAAABLgAFFAQJDgAJAIYdAA==.Arlen:BAABLgAECn8rAAIJAAkJoBhnMgA3AgAJAAkJoBhnMgA3AgAAAA==.Arma:BAABLgAECn8cAAIKAAgJjiNGBQAwAwAKAAgJjiNGBQAwAwABLgAFFAYJGQALALMgAA==.Armadro:BAABLgAFFH8ZAAILAAYJsyBeKQDQAQALAAYJsyBeKQDQAQAAAA==.Armavoid:BAAALgAFFAEJAQAAAA==.',
Au='Aurky:BAAALgAECgEJAwAAAA==.',
Ba='Bald:BAAALgADCgYJBgAAAA==.Balob:BAACLgAFFH8cAAMMAAgJOxkzEACrAQAMAAcJYRkzEACrAQANAAEJvwJBfwA9AAAuAAQKfyUAAgwACAlqJXoEAFQDAAwACAlqJXoEAFQDAAAA.Bandar:BAAALgADCgcJBwAAAA==.',
Be='Beardlylegal:BAAALgAECgEJAQAAAA==.Behodius:BAAALgAECgMJBAAAAA==.Bellafists:BAAALgAECgYJBgAAAA==.Benchwong:BAAALgAFFAEJAQABLgAFFAgJHAAMADsZAA==.',
Bl='Blacksteve:BAAALgAECgIJAgAAAA==.Bloodngore:BAABLgAECn8nAAIOAAkJTxu6CgBlAgAOAAkJTxu6CgBlAgAAAA==.Blumoon:BAAALgAECgEJAQAAAA==.',
Bm='Bmxdh:BAAALgAECgYJDwAAAA==.',
Bo='Bonecollectr:BAAALgAECgkJDgAAAA==.',
Br='Brewswayne:BAAALgAECgEJAQAAAA==.Broku:BAAALgAECggJDQABLgAECgkJLgAJAMcXAA==.Brudah:BAAALgAECgEJAQAAAA==.Brutus:BAAALgAFFAMJBAAAAA==.',
Bu='Bubblelove:BAABLgAECn8kAAIPAAkJTA0AJgCcAQAPAAkJTA0AJgCcAQAAAA==.Bubbly:BAABLgAECn8uAAIJAAkJxxdrQwD8AQAJAAkJxxdrQwD8AQAAAA==.Butes:BAAALgAECgkJDwAAAA==.',
Ca='Caelum:BAAALgAECgMJAwAAAA==.Callmepappy:BAAALgADCgUJBQAAAA==.Canníbal:BAAALgAECggJDwAAAA==.',
Ce='Censored:BAAALgADCgIJAgAAAA==.',
Ch='Chopsy:BAACLgAFFH8VAAIKAAQJaCHKCgB0AQAKAAQJaCHKCgB0AQAuAAQKf1oAAwoACQlHJRsCAFADAAoACQlHJRsCAFADABAAAgnEC91eAFIAAAAA.Chris:BAAALgAECgUJDgAAAA==.Chucklez:BAAALgAFFAIJBAAAAA==.Chulobulo:BAABLgAECn8bAAIRAAkJxxW0FQDxAQARAAkJxxW0FQDxAQAAAA==.Chulosdck:BAAALgAECgYJDwABLgAECgkJGwARAMcVAA==.',
Ci='Cinnabons:BAAALgAFFAEJAQABLgAFFAQJBwAGAMAKAA==.',
Cl='Cleopatrick:BAAALgADCgkJEAAAAA==.',
Co='Cobgoblin:BAAALgAECgEJAQAAAA==.Codingsocks:BAAALgADCgEJAgAAAA==.',
Cr='Crekton:BAAALgAECgMJAwAAAA==.Cronnos:BAAALgAECgYJBwAAAA==.',
Cu='Cudlemonster:BAABLgAECn89AAIBAAkJbAyAJQCjAQABAAkJbAyAJQCjAQAAAA==.Cursed:BAACLgAFFH8OAAIDAAQJOxi1AwBXAQADAAQJOxi1AwBXAQAuAAQKf0oABAMACQmfIUUBAPQCAAMACQmPIUUBAPQCABIABAn2HHQOAFUBAAIAAwllD5zZAKUAAAAA.',
Da='Dabz:BAABLgAECn8XAAICAAgJhhrCNAAGAgACAAgJhhrCNAAGAgAAAA==.Daddyslaps:BAAALgAECgUJBQAAAA==.Daghma:BAAALgAECgYJBgAAAA==.Danyel:BAAALgADCgYJBwAAAA==.Darmok:BAABLgAECn81AAMNAAkJ3yMMBQBjAwANAAkJ3yMMBQBjAwAMAAEJbBpjmwBBAAAAAA==.Darzamat:BAAALgADCgEJAQAAAA==.Dawtie:BAAALgAECgQJBQABLgAECgkJDgATAAAAAA==.',
De='Demonbubble:BAACLgAFFH8YAAIEAAcJKw9xJQCYAQAEAAcJKw9xJQCYAQAuAAQKfy0AAgQACQm8FrMuAAwCAAQACQm8FrMuAAwCAAAA.Dezric:BAAALgADCgYJDAABLgAECgYJBgATAAAAAA==.Dezruf:BAAALgAECgYJBgAAAA==.',
Do='Dotomic:BAABLgAFFH8LAAICAAUJEx6INAB1AQACAAUJEx6INAB1AQABLgAFFAgJIAAUAIgfAA==.',
Dr='Drejan:BAAALgAECgcJCQAAAA==.Drfe:BAAALgADCgYJBgAAAA==.Drifthook:BAAALgAECgkJCQAAAA==.Drowarchon:BAAALgADCgIJAgABLgAECgQJBAATAAAAAA==.Drownix:BAAALgAECgQJBAAAAA==.Drowzy:BAAALgADCgYJBAABLgAECgQJBAATAAAAAA==.',
['Dä']='Dämonjäger:BAAALgADCggJCAAAAA==.',
Eb='Ebon:BAAALgADCgMJAwAAAA==.',
Ec='Ecaed:BAABLgAECn8bAAIVAAkJ1gaTEwAZAQAVAAkJ1gaTEwAZAQAAAA==.',
Ei='Eisenhørn:BAAALgADCgYJDgAAAA==.',
El='Elektriss:BAAALgAECgQJBAAAAA==.Elnaris:BAABLgAECn8jAAIJAAgJhA3WiABfAQAJAAgJhA3WiABfAQAAAA==.Elohime:BAAALgADCgYJCAAAAA==.',
Eo='Eon:BAAALgAECgIJCQAAAA==.',
Er='Erikkak:BAAALgADCgQJBAAAAA==.Eriu:BAAALgAECgEJAQABLgAFFAQJDgAJAIYdAA==.Erõs:BAAALgAECgYJCwABLgAECgYJFQAWADUZAA==.',
Fe='Fenixbinkle:BAAALgAECgQJBAAAAA==.',
Fi='Fiero:BAAALgAECggJEwABLgAECgkJDgATAAAAAA==.Fire:BAAALgAECgUJBQABLgAFFAYJFQAGAGUbAA==.',
Fr='Fragga:BAABLgAECn8cAAIXAAYJaBbLQgA6AQAXAAYJaBbLQgA6AQAAAA==.',
Fu='Fullflavor:BAAALgADCgIJAgAAAA==.',
['Fü']='Füran:BAAALgADCgIJAgAAAA==.',
Ga='Ganryu:BAAALgADCgYJCgAAAA==.',
Gb='Gboybalili:BAAALgADCgcJDAAAAA==.',
Gi='Gitzi:BAACLgAFFH8NAAIYAAQJlQtySwAVAQAYAAQJlQtySwAVAQAuAAQKf0sAAhgACQlZHTEcAF0CABgACQlZHTEcAF0CAAAA.',
Gl='Glaciea:BAAALgADCgMJAwABLgAECggJHgAZAKciAA==.',
Gr='Grayl:BAAALgAECgkJCQAAAA==.Greenrage:BAAALgADCgQJBAAAAA==.Griever:BAAALgAECgYJCQAAAA==.Grizzly:BAAALgAECgUJBgABLgAECggJJwAFAIMOAA==.Groovexgroov:BAABLgAECn8dAAIPAAkJOxhPEQBMAgAPAAkJOxhPEQBMAgAAAA==.',
Ha='Harlowe:BAAALgADCgYJBQAAAA==.',
He='Healrog:BAAALgAECgYJBgAAAA==.Hellraiser:BAAALgAECgQJBQAAAA==.',
Hi='Highfive:BAAALgADCgIJAgAAAA==.',
Ho='Holyfiero:BAAALgAECgQJBAABLgAECgkJDgATAAAAAA==.Holynight:BAAALgADCgMJBAABLgAECggJJwAFAIMOAA==.Hordend:BAAALgAECgUJEAAAAA==.Hozru:BAAALgADCgEJAQAAAA==.',
Hu='Hulkfists:BAABLgAECn8UAAMMAAYJownMSgAcAQAMAAYJownMSgAcAQAaAAYJ3gLVHgDiAAAAAA==.',
Hy='Hydration:BAAALgADCgMJAwAAAA==.',
['Hâ']='Hâruka:BAAALgAECgcJBgAAAA==.',
Im='Imcepsy:BAABLgAECn81AAIBAAkJ7BkPDACuAgABAAkJ7BkPDACuAgAAAA==.',
Io='Iownzuu:BAAALgADCgMJAwAAAA==.',
Is='Istari:BAAALgAECgIJAgAAAA==.Istark:BAAALgAECgMJAwAAAA==.',
Ja='Jayjay:BAACLgAFFH8KAAILAAQJ7RRGXQAlAQALAAQJ7RRGXQAlAQAuAAQKfyIAAgsACQmxHEEmAIICAAsACQmxHEEmAIICAAAA.',
Je='Jethroy:BAABLgAECn8VAAIbAAgJbRHHNwBuAQAbAAgJbRHHNwBuAQAAAA==.',
Jf='Jfkwspvpfldg:BAAALgAECgYJBgAAAA==.',
Ji='Jimmie:BAABLgAECn8aAAIRAAgJuiAkEQCYAgARAAgJuiAkEQCYAgAAAA==.',
Jo='Johnparstina:BAAALgAECgYJDgAAAA==.Jolty:BAACLgAFFH8LAAIaAAQJNx+hBgBQAQAaAAQJNx+hBgBQAQAuAAQKfyEAAhoACQmrIyMCAAUDABoACQmrIyMCAAUDAAAA.',
Jr='Jrbacnchee:BAAALgAECgEJAQAAAA==.Jrbcncheze:BAAALgAECggJEgAAAA==.',
Ka='Kainicus:BAACLgAFFH8TAAIVAAQJURPYBQAIAQAVAAQJURPYBQAIAQAuAAQKf1kAAhUACQnBGZUFAEsCABUACQnBGZUFAEsCAAAA.Kainigal:BAAALgADCgYJCwAAAA==.Kainisham:BAAALgADCgcJBwAAAA==.',
Ke='Kelador:BAABLgAECn8mAAIcAAkJQgosGgA8AQAcAAkJQgosGgA8AQAAAA==.Keoni:BAAALgAECgEJAQAAAA==.Kerrykoppene:BAAALgAECgIJAgAAAA==.',
Kh='Khappucino:BAAALgAECgcJCQAAAA==.Kharibou:BAAALgAECgQJBAAAAA==.Khellendros:BAAALgADCgYJCgAAAA==.Khrism:BAAALgADCgQJBAAAAA==.',
Ki='Kibbi:BAAALgADCgcJBwAAAA==.Kitsyune:BAABLgAECn8fAAIdAAkJ7BeCBQAMAgAdAAkJ7BeCBQAMAgAAAA==.',
Kj='Kjartan:BAAALgAECgUJBgAAAA==.',
Kl='Kløey:BAACLgAFFH8GAAIRAAMJ5gtrKgDbAAARAAMJ5gtrKgDbAAAuAAQKfxQAAhEABgnZFMsuAI0BABEABgnZFMsuAI0BAAAA.',
La='Laethys:BAAALgADCggJCAABLgAECgkJIQALAEIeAA==.',
Li='Lithini:BAAALgAECgQJCQAAAA==.',
Lo='Lowtech:BAAALgAECgMJAwAAAA==.',
Lu='Luminusrayne:BAACLgAFFH8PAAIeAAMJYQUBKACEAAAeAAMJYQUBKACEAAAuAAQKf0YAAwEACQm8DQMiAIQBAAEACAn8CgMiAIQBAB4ACQk+DJQyAD8BAAAA.Lussypipz:BAABLgAFFH8GAAIfAAMJLwUVOgCSAAAfAAMJLwUVOgCSAAABLgAFFAMJBgARAOYLAA==.',
Ma='Mahwe:BAAALgAECggJDgAAAA==.Manafest:BAAALgAECgMJCgAAAA==.Maros:BAABLgAECn8kAAMLAAkJWhaqOQAyAgALAAkJWhaqOQAyAgAgAAEJJA+/FgA2AAAAAA==.',
Me='Meheret:BAACLgAFFH8GAAILAAMJwAAUqgCAAAALAAMJwAAUqgCAAAAuAAQKf0EAAgsACQlmBr2sACcBAAsACQlmBr2sACcBAAAA.Melissenia:BAAALgAECgQJBAAAAA==.Menious:BAAALgAECgEJAQAAAA==.Mepha:BAAALgAECggJDwAAAA==.',
Mi='Mint:BAABLgAECn8hAAILAAkJQh5dIwDlAgALAAkJQh5dIwDlAgAAAA==.',
Mo='Mokth:BAAALgADCgMJAwAAAA==.Mom:BAAALgAECgIJAgAAAA==.Mooby:BAABLgAECn8XAAIRAAgJjRocGABHAgARAAgJjRocGABHAgAAAA==.Moomu:BAAALgAECgUJBQAAAA==.Moonfury:BAAALgAECgEJAQAAAA==.Moonleigh:BAAALgADCgMJBAAAAA==.Morganthe:BAAALgAECgIJAwAAAA==.Moria:BAAALgAECgUJBgAAAA==.',
Mu='Munt:BAAALgAECgQJBAABLgAECgkJIQALAEIeAA==.',
My='Mypriiest:BAAALgAECgQJBAAAAA==.Myroguëë:BAAALgADCgUJBQAAAA==.Mystx:BAABLgAFFH8KAAILAAIJBhhxmACbAAALAAIJBhhxmACbAAABLgAFFAQJDgAJAIYdAA==.Mythx:BAACLgAFFH8LAAIXAAQJgh7uFgBZAQAXAAQJgh7uFgBZAQAuAAQKfzcAAhcACQmZJjEBAHMDABcACQmZJjEBAHMDAAEuAAUUBAkOAAkAhh0A.Mywarr:BAAALgADCgMJAwAAAA==.',
Na='Naturemage:BAAALgAECgUJBwAAAA==.Natâsi:BAACLgAFFH8KAAIbAAMJZxRLLQDGAAAbAAMJZxRLLQDGAAAuAAQKfy8AAhsACQmkGWEZADwCABsACQmkGWEZADwCAAAA.',
Ne='Nerazul:BAABLgAECn8VAAQDAAYJph/GBQAKAgADAAYJph/GBQAKAgACAAMJ3wqC4wCTAAASAAEJ/AgReAAsAAAAAA==.Netharec:BAAALgADCgEJAQABLgAFFAcJGAAPABobAA==.Nevai:BAABLgAECn8YAAIbAAkJCxILIgD0AQAbAAkJCxILIgD0AQAAAA==.',
Ni='Nielas:BAABLgAECn8UAAIFAAgJ7yAHKQBdAgAFAAgJ7yAHKQBdAgAAAA==.Nihilus:BAACLgAFFH8SAAIFAAYJJxuTCACMAQAFAAYJJxuTCACMAQAuAAQKfxUAAgUABwkWJLkvAHkCAAUABwkWJLkvAHkCAAAA.Nilari:BAABLgAECn8UAAIhAAYJIQmFMACkAAAhAAYJIQmFMACkAAAAAA==.Nine:BAAALgADCgYJBgABLgAFFAQJFQAKAGghAA==.',
No='Noctazari:BAAALgADCgUJBQAAAA==.Noctium:BAABLgAECn8eAAIZAAgJpyL7AgB7AgAZAAgJpyL7AgB7AgAAAA==.Nostrildamus:BAAALgAECgYJEQABLgAECgkJGAAJADYYAA==.',
Nz='Nzoth:BAAALgADCgYJBgAAAA==.',
Of='Officimeeg:BAAALgAECgEJAQAAAA==.',
Ow='Owlaf:BAAALgAECgIJAgABLgAFFAYJHwABAB8aAA==.Owlchi:BAACLgAFFH8FAAIQAAQJ8wxHNgDQAAAQAAQJ8wxHNgDQAAAuAAQKfxYAAxAABwktHcUZAEoCABAABwktHcUZAEoCACIABQmRD+9MAMsAAAEuAAUUBgkfAAEAHxoA.Owls:BAACLgAFFH8fAAIBAAYJHxqTFADfAQABAAYJHxqTFADfAQAuAAQKfzkAAwEACQkWIyUHAAoDAAEACQmGICUHAAoDAB4ABwkbJPcKAJ8CAAEuAAUUBgkfAAEAHxoA.',
Pa='Pallywhacker:BAAALgAECgUJBQAAAA==.Panconcaca:BAAALgAFFAcJAwAAAA==.Pantsokay:BAAALgADCgEJAQAAAA==.',
Pe='Peach:BAABLgAECn8cAAMjAAgJ4Q3sCwBwAQAjAAgJ4Q3sCwBwAQARAAYJUAGeSwDNAAAAAA==.Peaches:BAAALgAECgEJAgAAAA==.Petsmart:BAAALgAECgQJBQAAAA==.',
Pi='Pinesol:BAAALgADCgcJBwAAAA==.',
Po='Potatoeshot:BAAALgAECgQJBQAAAA==.',
Pr='Praisethesun:BAAALgAECgQJCQAAAA==.Prayxx:BAAALgAECgYJCQAAAA==.Pretzel:BAACLgAFFH8TAAIFAAYJryQkMQCkAQAFAAYJryQkMQCkAQAuAAQKfzQAAwUACQljJZ4EAIoDAAUACQljJZ4EAIoDACQAAQk5IcIxAFYAAAAA.Proved:BAACLgAFFH8FAAIeAAMJBgo2LgBeAAAeAAMJBgo2LgBeAAAuAAQKf00AAh4ACQmRHUEKAMMCAB4ACQmRHUEKAMMCAAAA.',
Ps='Psillycybin:BAAALgAECgcJDQABLgAECgkJQgAeAP0JAA==.',
Pu='Puddingface:BAAALgADCgkJCQAAAA==.Puggar:BAAALgADCgQJBgAAAA==.Pulpp:BAAALgAECgIJAgAAAA==.Pumpspotter:BAAALgAECgkJEgAAAA==.',
Qu='Quiescence:BAAALgADCgYJBgAAAA==.',
Ra='Rakkór:BAAALgAECgEJAgAAAA==.Ranas:BAAALgADCgIJAgAAAA==.Ranessandi:BAAALgAECgEJAQAAAA==.Ratlemebonez:BAAALgAECgEJAQAAAA==.Ravèn:BAAALgAECgcJEQAAAA==.Rayana:BAAALgADCgYJBgAAAA==.Razeal:BAAALgAECgYJDwAAAA==.',
Re='Regerax:BAAALgAFFAIJAwABLgAFFAQJDgAJAIYdAA==.Rene:BAEALgAECggJCgAAAA==.Rev:BAAALgADCgEJAQAAAA==.',
Rh='Rhysan:BAACLgAFFH8NAAINAAQJUBuLKQA/AQANAAQJUBuLKQA/AQAuAAQKfzsAAg0ACQm9F4Y2ANYBAA0ACQm9F4Y2ANYBAAAA.Rhyuk:BAAALgADCgQJBAAAAA==.',
Ri='Rimzak:BAAALgAECgMJAwABLgAECgkJDgATAAAAAA==.Ristria:BAAALgADCgYJEAABLgAECgYJHwAJADgSAA==.Rizy:BAABLgAECn8iAAIFAAkJpA/LTQDZAQAFAAkJpA/LTQDZAQAAAA==.',
Ro='Robonord:BAAALgAECgIJAgAAAA==.Rokki:BAAALgADCgIJAgAAAA==.',
Ru='Rude:BAAALgADCgcJCwAAAA==.',
Ry='Rynhart:BAAALgADCgUJBQAAAA==.Ryntard:BAAALgAECgYJBgAAAA==.Ryushi:BAACLgAFFH8UAAIEAAQJ4hTeRAAZAQAEAAQJ4hTeRAAZAQAuAAQKf0gAAgQACQnGICwaAHcCAAQACQnGICwaAHcCAAAA.',
Sa='Sacerdote:BAABLgAECn8UAAICAAYJPiF3TgCvAQACAAYJPiF3TgCvAQAAAA==.Sakari:BAAALgADCgcJEAAAAA==.Sandara:BAAALgADCgYJBgAAAA==.Sangre:BAAALgADCgIJAgABLgAECgMJBAATAAAAAA==.Sarasara:BAAALgADCgUJBQAAAA==.Sathicus:BAAALgAECgMJAwAAAA==.',
Sc='Scoots:BAAALgAECgUJCAABLgAFFAQJFQAKAGghAA==.Scratster:BAAALgAECgcJCAAAAA==.',
Se='Sebnoth:BAABLgAECn8zAAIFAAkJtCDGEwDRAgAFAAkJtCDGEwDRAgAAAA==.',
Sh='Shadowspark:BAAALgAECgYJCgAAAA==.Shalashaska:BAAALgADCgEJAQAAAA==.Shamantastik:BAAALgAECgMJAwAAAA==.Shiden:BAAALgAECgYJDwAAAA==.Shift:BAAALgADCgkJCQAAAA==.Shiift:BAAALgADCgYJBwAAAA==.Shockblocked:BAAALgADCgQJBAAAAA==.',
Si='Sidepiece:BAAALgADCgcJCAAAAA==.Sillyderek:BAACLgAFFH8GAAIhAAIJSghWFQBQAAAhAAIJSghWFQBQAAAuAAQKfx0AAiEABwmnDfYhAAUBACEABwmnDfYhAAUBAAAA.',
Sl='Slashology:BAAALgAECgYJDAAAAA==.',
Sm='Smallpally:BAABLgAECn8UAAIJAAcJBRWCfwBwAQAJAAcJBRWCfwBwAQAAAA==.',
So='Soarsha:BAAALgAECgIJAgAAAA==.Solarida:BAABLgAECn8tAAIJAAgJVhzuAAAEAgAJAAgJVhzuAAAEAgAAAA==.',
Sr='Srsawyer:BAABLgAECn8bAAICAAgJSA/nYACnAQACAAgJSA/nYACnAQAAAA==.',
St='Staralfur:BAAALgADCgcJBwAAAA==.Stevokerjobs:BAABLgAECn8VAAQWAAYJNRn3GQA4AQAWAAQJBRv3GQA4AQAZAAYJaxJQIAArAQAGAAQJRBP8UADrAAAAAA==.Stormshäde:BAAALgAFFAEJAwAAAA==.Stratos:BAAALgADCgcJBwAAAA==.',
Su='Sumlkithot:BAAALgAECgQJAQAAAA==.Sunwa:BAACLgAFFH8OAAMJAAQJhh2zKQBlAQAJAAQJhh2zKQBlAQAhAAEJjwPGHAAgAAAuAAQKfyEAAwkACAlZIFs6ABoCAAkACAlZIFs6ABoCACEABgnxCtMsALgAAAAA.',
['Sï']='Sïmba:BAAALgAECgMJCQAAAA==.',
Ta='Talyashamwow:BAAALgADCgYJBgAAAA==.',
Te='Terzhull:BAAALgADCgIJAgAAAA==.',
Th='Thepride:BAAALgAECggJDwAAAA==.',
Ti='Timmytim:BAAALgAECgQJCAAAAA==.Tired:BAAALgAECgUJBgAAAA==.',
To='Tool:BAACLgAFFH8ZAAILAAgJHBvBAADdAgALAAgJHBvBAADdAgAuAAQKfyYAAgsACQnrJGMCANgDAAsACQnrJGMCANgDAAEuAAUUCQkvAAQAESUA.Tooms:BAAALgAECgcJBwAAAA==.Touchi:BAAALgAECggJDAABLgAECgkJKQAcABkcAA==.',
Tr='Troljin:BAAALgADCgEJAQAAAA==.',
Tu='Tuo:BAABLgAECn8pAAIcAAkJGRzuBQCOAgAcAAkJGRzuBQCOAgAAAA==.Turbid:BAABLgAECn9EAAIEAAkJvhf9JwArAgAEAAkJvhf9JwArAgAAAA==.',
Ty='Ty:BAAALgAECgUJDAAAAA==.Tytank:BAAALgADCgMJBAAAAA==.',
Uh='Uhavemyrice:BAAALgADCgIJAgAAAA==.',
Ve='Velkin:BAAALgAECgEJAQAAAA==.',
Vi='Vivia:BAAALgADCgQJBAAAAA==.Viviann:BAAALgADCgMJAwAAAA==.Vivians:BAAALgADCggJCgAAAA==.',
Vo='Voutecomer:BAAALgAECgMJAwAAAA==.',
Wa='Walls:BAABLgAECn8YAAIJAAkJNhhAMwAzAgAJAAkJNhhAMwAzAgAAAA==.Warrach:BAAALgADCgQJBAAAAA==.',
We='Welchnut:BAAALgADCgEJAQAAAA==.Wennoe:BAAALgADCgIJAgAAAA==.Westirras:BAABLgAECn8iAAMJAAgJHRB1eAB9AQAJAAgJHRB1eAB9AQAbAAIJTQiffwBNAAAAAA==.',
Wo='Wobblepox:BAAALgAECgkJCAAAAA==.',
Ya='Yarrow:BAAALgAECgQJBwAAAA==.',
Yo='Yogurt:BAAALgAECgcJEwABLgAECgkJLgAJAMcXAA==.',
Yu='Yusuke:BAABLgAECn8WAAMiAAcJfhF4KwBcAQAiAAcJfhF4KwBcAQAQAAYJPQlyQADgAAABLgAECgkJJwAOAE8bAA==.',
Za='Zabuzabuza:BAAALgAECgIJAgABLgAECgYJFQAWADUZAA==.Zazabandit:BAAALgADCgUJBQAAAA==.',
Zo='Zolleta:BAAALgAECgQJBAAAAA==.',
Zu='Zuesulty:BAAALgADCgYJBgAAAA==.Zunden:BAABLgAECn8YAAMWAAgJWg9bEwCUAQAWAAgJWg9bEwCUAQAGAAEJAABsqgAAAAAAAA==.',
['Éz']='Ézon:BAAALgADCggJCAAAAA==.',
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
