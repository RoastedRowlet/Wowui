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

local lookup = {'Priest-Discipline','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Augmentation','Warrior-Fury','Paladin-Retribution','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Unknown-Unknown','Priest-Shadow','Monk-Mistweaver','Rogue-Subtlety','Hunter-Marksmanship','DemonHunter-Vengeance','Evoker-Preservation','Hunter-BeastMastery','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Druid-Feral','Rogue-Outlaw','Priest-Holy','Mage-Arcane','Warlock-Destruction','Paladin-Protection','Monk-Brewmaster','Rogue-Assassination','DeathKnight-Frost',}
local provider = {region='US',realm='Andorhal',name='US',type='weekly',zone=46,date='2026-06-06',data={Ad='Adelyne:BAAALgAECgQJAwABLgAFFAUJEgABABkcAA==.Adorablepine:BAABLgAECn8ZAAMCAAcJuAMAvgDJAAACAAcJrAMAvgDJAAADAAEJqgNAQAAgAAAAAA==.',
Ag='Agaze:BAACLgAFFH8ZAAIEAAcJESA2FgDdAQAEAAcJESA2FgDdAQAuAAQKfxYAAgQACAkTIgAZAL8CAAQACAkTIgAZAL8CAAAA.',
Ai='Aiedel:BAAALgAECgUJCQAAAA==.',
Al='Allesa:BAAALgAECgEJAQAAAA==.',
Ao='Aoise:BAAALgAECgkJCAAAAA==.',
Ap='Applejuuice:BAABLgAFFH8HAAIFAAMJexYSiwDiAAAFAAMJexYSiwDiAAABLgAFFAQJBwAGAMAKAA==.',
Ar='Archblade:BAAALgAECgQJBwAAAA==.Arelith:BAAALgAECgMJBwAAAA==.Ariggs:BAAALgAECgEJAQAAAA==.Ariosx:BAAALgAFFAIJAgABLgAFFAQJCwAHAIIeAA==.Arlen:BAABLgAECn8kAAIIAAkJbRXIPwD9AQAIAAkJbRXIPwD9AQAAAA==.Arma:BAABLgAECn8cAAIJAAgJjiNGBQAwAwAJAAgJjiNGBQAwAwAAAA==.Armadro:BAABLgAFFH8YAAIKAAUJ4x9NOAB4AQAKAAUJ4x9NOAB4AQAAAA==.',
Au='Aurky:BAAALgAECgEJAwAAAA==.',
Ba='Bald:BAAALgADCgYJBgAAAA==.Balob:BAACLgAFFH8bAAMLAAgJOxktDADBAQALAAcJYRktDADBAQAMAAEJvwLBcwA9AAAuAAQKfyUAAgsACAlqJXoEAFQDAAsACAlqJXoEAFQDAAAA.Bandar:BAAALgADCgcJBwAAAA==.',
Be='Behodius:BAAALgAECgMJBAAAAA==.Bellafists:BAAALgAECgYJBgAAAA==.',
Bl='Blacksteve:BAAALgAECgIJAgAAAA==.Bloodngore:BAABLgAECn8lAAINAAkJIhpnCgBhAgANAAkJIhpnCgBhAgAAAA==.Blumoon:BAAALgAECgEJAQAAAA==.',
Bm='Bmxdh:BAAALgAECgYJDwAAAA==.',
Bo='Bonecollectr:BAAALgAECgUJBgABLgAECggJDQAOAAAAAA==.',
Br='Broku:BAAALgAECgcJCwABLgAECgkJLgAIAMcXAA==.Brudah:BAAALgAECgEJAQAAAA==.Brutus:BAAALgAFFAMJBAAAAA==.',
Bu='Bubblelove:BAABLgAECn8kAAIPAAkJTA10IgCsAQAPAAkJTA10IgCsAQAAAA==.Bubbly:BAABLgAECn8uAAIIAAkJxxdJPgACAgAIAAkJxxdJPgACAgAAAA==.Butes:BAAALgAECgkJDwAAAA==.',
Ca='Caelum:BAAALgAECgMJAwAAAA==.Callmepappy:BAAALgADCgUJBQAAAA==.Canníbal:BAAALgAECggJDwAAAA==.',
Ce='Censored:BAAALgADCgIJAgAAAA==.',
Ch='Chopsy:BAACLgAFFH8VAAIJAAQJaCHPCAB9AQAJAAQJaCHPCAB9AQAuAAQKf1oAAwkACQlHJcMBAFQDAAkACQlHJcMBAFQDABAAAgnEC91eAFIAAAAA.Chris:BAAALgAECgUJDQAAAA==.Chucklez:BAAALgAFFAIJBAAAAA==.Chulobulo:BAABLgAECn8bAAIRAAkJxxU3FAD0AQARAAkJxxU3FAD0AQAAAA==.Chulosdck:BAAALgAECgYJDwABLgAECgkJGwARAMcVAA==.',
Ci='Cinnabons:BAAALgAFFAEJAQABLgAFFAQJBwAGAMAKAA==.',
Cl='Cleopatrick:BAAALgADCgkJEAAAAA==.',
Co='Cobgoblin:BAAALgAECgEJAQAAAA==.Codingsocks:BAAALgADCgEJAgAAAA==.',
Cr='Crekton:BAAALgAECgMJAwAAAA==.Cronnos:BAAALgAECgYJBwAAAA==.',
Cu='Cudlemonster:BAABLgAECn89AAIBAAkJbAw8IgCtAQABAAkJbAw8IgCtAQAAAA==.Cursed:BAACLgAFFH8HAAIDAAQJww7nBAAvAQADAAQJww7nBAAvAQAuAAQKfz0AAwMACQnnIKkBAM8CAAMACQnnIKkBAM8CAAIAAgmXC2L9AGIAAAAA.',
Da='Dabz:BAABLgAECn8XAAICAAgJhhp1MgAJAgACAAgJhhp1MgAJAgAAAA==.Daddyslaps:BAAALgAECgUJBQAAAA==.Daghma:BAAALgAECgYJBgAAAA==.Danyel:BAAALgADCgYJBwAAAA==.Darmok:BAABLgAECn81AAMMAAkJ3yNqBABmAwAMAAkJ3yNqBABmAwALAAEJbBojkQBCAAAAAA==.Darzamat:BAAALgADCgEJAQAAAA==.Dawtie:BAAALgAECgQJBQABLgAECggJDQAOAAAAAA==.',
De='Demonbubble:BAACLgAFFH8WAAIEAAYJNBBrLQBXAQAEAAYJNBBrLQBXAQAuAAQKfy0AAgQACQm8FiYsAAwCAAQACQm8FiYsAAwCAAAA.Dezric:BAAALgADCgYJDAABLgAECgYJBgAOAAAAAA==.Dezruf:BAAALgAECgYJBgAAAA==.',
Do='Dotomic:BAABLgAFFH8HAAICAAUJzRkVNwBVAQACAAUJzRkVNwBVAQABLgAFFAgJHAASAIgfAA==.',
Dr='Drejan:BAAALgAECgcJCQAAAA==.Drfe:BAAALgADCgYJBgAAAA==.Drifthook:BAAALgAECgcJBwAAAA==.Drowarchon:BAAALgADCgIJAgABLgAECgQJBAAOAAAAAA==.Drownix:BAAALgAECgQJBAAAAA==.Drowzy:BAAALgADCgYJBAABLgAECgQJBAAOAAAAAA==.',
['Dä']='Dämonjäger:BAAALgADCggJCAAAAA==.',
Eb='Ebon:BAAALgADCgMJAwAAAA==.',
Ec='Ecaed:BAABLgAECn8bAAITAAkJ1gZxEgAZAQATAAkJ1gZxEgAZAQAAAA==.',
Ei='Eisenhørn:BAAALgADCgYJDgAAAA==.',
El='Elektriss:BAAALgAECgQJBAAAAA==.Elnaris:BAABLgAECn8fAAIIAAcJPQjeugADAQAIAAcJPQjeugADAQAAAA==.Elohime:BAAALgADCgYJCAAAAA==.',
Eo='Eon:BAAALgAECgIJBwAAAA==.',
Er='Erikkak:BAAALgADCgQJBAAAAA==.Erõs:BAAALgAECgYJCwABLgAECgYJFQAUADUZAA==.',
Fi='Fiero:BAAALgAECggJDQAAAA==.Fire:BAAALgAECgUJBQABLgAFFAYJFQAGAGUbAA==.',
Fr='Fragga:BAABLgAECn8cAAIHAAYJaBaXPwA+AQAHAAYJaBaXPwA+AQAAAA==.',
Fu='Fullflavor:BAAALgADCgIJAgAAAA==.',
['Fü']='Füran:BAAALgADCgIJAgAAAA==.',
Ga='Ganryu:BAAALgADCgYJCgAAAA==.',
Gb='Gboybalili:BAAALgADCgcJDAAAAA==.',
Gi='Gitzi:BAACLgAFFH8NAAIVAAQJlQuOQAAfAQAVAAQJlQuOQAAfAQAuAAQKf0sAAhUACQlZHTEcAF0CABUACQlZHTEcAF0CAAAA.',
Gl='Glaciea:BAAALgADCgMJAwABLgAECggJHgAWAKciAA==.',
Gr='Grayl:BAAALgAECgkJCQAAAA==.Greenrage:BAAALgADCgQJBAAAAA==.Griever:BAAALgAECgYJCQAAAA==.Grizzly:BAAALgAECgEJAQAAAA==.Groovexgroov:BAABLgAECn8dAAIPAAkJOxjDDwBYAgAPAAkJOxjDDwBYAgAAAA==.',
He='Healrog:BAAALgAECgYJBgAAAA==.Hellraiser:BAAALgAECgQJBQAAAA==.',
Hi='Highfive:BAAALgADCgIJAgAAAA==.',
Ho='Holyfiero:BAAALgAECgQJBAABLgAECggJDQAOAAAAAA==.Holynight:BAAALgADCgEJAgABLgAECgEJAQAOAAAAAA==.Hordend:BAAALgAECgUJEAAAAA==.Hozru:BAAALgADCgEJAQAAAA==.',
Hu='Hulkfists:BAABLgAECn8UAAMLAAYJownMSgAcAQALAAYJownMSgAcAQAXAAYJ3gLVHgDiAAAAAA==.',
Hy='Hydration:BAAALgADCgMJAwAAAA==.',
['Hâ']='Hâruka:BAAALgAECgcJBgAAAA==.',
Im='Imcepsy:BAABLgAECn81AAIBAAkJ7BkuCwCxAgABAAkJ7BkuCwCxAgAAAA==.',
Io='Iownzuu:BAAALgADCgMJAwAAAA==.',
Is='Istari:BAAALgAECgIJAgAAAA==.Istark:BAAALgAECgMJAwAAAA==.',
Ja='Jayjay:BAACLgAFFH8KAAIKAAQJ7RSWUwA1AQAKAAQJ7RSWUwA1AQAuAAQKfxgAAgoACQlHG2IxAEwCAAoACQlHG2IxAEwCAAAA.',
Je='Jethroy:BAABLgAECn8VAAIYAAgJbRFtNQBwAQAYAAgJbRFtNQBwAQAAAA==.',
Jf='Jfkwspvpfldg:BAAALgAECgYJBgAAAA==.',
Ji='Jimmie:BAABLgAECn8aAAIRAAgJuiAkEQCYAgARAAgJuiAkEQCYAgAAAA==.',
Jo='Johnparstina:BAAALgAECgYJDgAAAA==.Jolty:BAACLgAFFH8KAAIXAAQJNx8/BQBaAQAXAAQJNx8/BQBaAQAuAAQKfyEAAhcACQmrI9cBAAoDABcACQmrI9cBAAoDAAAA.',
Jr='Jrbacnchee:BAAALgAECgEJAQAAAA==.Jrbcncheze:BAAALgAECggJEgAAAA==.',
Ka='Kainicus:BAACLgAFFH8TAAITAAQJURPyBAAKAQATAAQJURPyBAAKAQAuAAQKf1kAAhMACQnBGTQFAEwCABMACQnBGTQFAEwCAAAA.Kainigal:BAAALgADCgYJCwAAAA==.Kainisham:BAAALgADCgcJBwAAAA==.',
Ke='Kelador:BAABLgAECn8kAAIZAAcJ8wjHIADvAAAZAAcJ8wjHIADvAAAAAA==.Keoni:BAAALgAECgEJAQAAAA==.Kerrykoppene:BAAALgAECgIJAgAAAA==.',
Kh='Khappucino:BAAALgAECgYJCAAAAA==.Kharibou:BAAALgAECgQJBAAAAA==.Khellendros:BAAALgADCgYJCgAAAA==.Khrism:BAAALgADCgQJBAAAAA==.',
Ki='Kibbi:BAAALgADCgcJBwAAAA==.Kitsyune:BAABLgAECn8fAAIaAAkJ7BdHBQAMAgAaAAkJ7BdHBQAMAgAAAA==.',
Kj='Kjartan:BAAALgAECgUJBgAAAA==.',
Kl='Kløey:BAACLgAFFH8FAAIRAAIJvQ8eLQCgAAARAAIJvQ8eLQCgAAAuAAQKfxQAAhEABgnZFMsuAI0BABEABgnZFMsuAI0BAAAA.',
La='Laethys:BAAALgADCggJCAABLgAECgkJIQAKAEIeAA==.',
Li='Lithini:BAAALgAECgQJCQAAAA==.',
Lo='Lowtech:BAAALgAECgMJAwAAAA==.',
Lu='Luminusrayne:BAACLgAFFH8PAAIbAAMJYQVOJACIAAAbAAMJYQVOJACIAAAuAAQKf0YAAwEACQm8DQMiAIQBAAEACAn8CgMiAIQBABsACQk+DA0wAEEBAAAA.Lussypipz:BAAALgAFFAEJAQABLgAFFAIJBQARAL0PAA==.',
Ma='Mahwe:BAAALgAECggJDgAAAA==.Manafest:BAAALgAECgMJCgAAAA==.Maros:BAABLgAECn8kAAMKAAkJWha7NgA3AgAKAAkJWha7NgA3AgAcAAEJJA9WFAA2AAAAAA==.',
Me='Meheret:BAACLgAFFH8GAAIKAAMJwACmngCJAAAKAAMJwACmngCJAAAuAAQKf0EAAgoACQlmBqujADABAAoACQlmBqujADABAAAA.Melissenia:BAAALgAECgQJBAAAAA==.Menious:BAAALgAECgEJAQAAAA==.Mepha:BAAALgAECggJDwAAAA==.',
Mi='Mint:BAABLgAECn8hAAIKAAkJQh5dIwDlAgAKAAkJQh5dIwDlAgAAAA==.',
Mo='Mokth:BAAALgADCgMJAwAAAA==.Mom:BAAALgAECgIJAgAAAA==.Mooby:BAABLgAECn8XAAIRAAgJjRocGABHAgARAAgJjRocGABHAgAAAA==.Moomu:BAAALgAECgUJBQAAAA==.Moonfury:BAAALgAECgEJAQAAAA==.Moonleigh:BAAALgADCgMJBAAAAA==.Morganthe:BAAALgAECgIJAwAAAA==.Moria:BAAALgAECgUJBgAAAA==.',
Mu='Munt:BAAALgAECgQJBAABLgAECgkJIQAKAEIeAA==.',
My='Mypriiest:BAAALgAECgQJBAAAAA==.Myroguëë:BAAALgADCgUJBQAAAA==.Mystx:BAABLgAFFH8HAAIKAAIJ1gxYmACRAAAKAAIJ1gxYmACRAAABLgAFFAQJCwAHAIIeAA==.Mythx:BAACLgAFFH8LAAIHAAQJgh7jEgBfAQAHAAQJgh7jEgBfAQAuAAQKfzQAAgcACQk3I/4DACADAAcACQk3I/4DACADAAAA.Mywarr:BAAALgADCgMJAwAAAA==.',
Na='Naturemage:BAAALgAECgUJBwAAAA==.Natâsi:BAACLgAFFH8GAAIYAAMJ2g5VLwCsAAAYAAMJ2g5VLwCsAAAuAAQKfy8AAhgACQmkGaQXAEACABgACQmkGaQXAEACAAAA.',
Ne='Nerazul:BAABLgAECn8VAAQDAAYJph/GBQAKAgADAAYJph/GBQAKAgACAAMJ3wqC4wCTAAAdAAEJ/AgReAAsAAAAAA==.Netharec:BAAALgADCgEJAQABLgAFFAYJFgAPALwcAA==.Nevai:BAABLgAECn8YAAIYAAkJCxJDIAD2AQAYAAkJCxJDIAD2AQAAAA==.',
Ni='Nielas:BAABLgAECn8UAAIFAAgJ7yBKJgBhAgAFAAgJ7yBKJgBhAgAAAA==.Nihilus:BAACLgAFFH8SAAIFAAYJJxuTCACMAQAFAAYJJxuTCACMAQAuAAQKfxUAAgUABwkWJLkvAHkCAAUABwkWJLkvAHkCAAAA.Nilari:BAABLgAECn8UAAIeAAYJIQkdLgCkAAAeAAYJIQkdLgCkAAAAAA==.Nine:BAAALgADCgYJBgABLgAFFAQJFQAJAGghAA==.',
No='Noctazari:BAAALgADCgUJBQAAAA==.Noctium:BAABLgAECn8eAAIWAAgJpyKpAgCAAgAWAAgJpyKpAgCAAgAAAA==.Nostrildamus:BAAALgAECgYJEQABLgAECgkJGAAIADYYAA==.',
Nz='Nzoth:BAAALgADCgYJBgAAAA==.',
Of='Officimeeg:BAAALgAECgEJAQAAAA==.',
Ow='Owlaf:BAAALgAECgIJAgABLgAFFAUJHAABAIYdAA==.Owlchi:BAACLgAFFH8FAAIQAAQJ8ww5LgDXAAAQAAQJ8ww5LgDXAAAuAAQKfxUAAxAABwktHaoXAEkCABAABwktHaoXAEkCAB8ABQmOD+ZJAM4AAAEuAAUUBQkcAAEAhh0A.Owls:BAACLgAFFH8cAAIBAAUJhh3FFgCXAQABAAUJhh3FFgCXAQAuAAQKfzkAAwEACQkWI5sGAAwDAAEACQmGIJsGAAwDABsABwkbJPcKAJ8CAAEuAAUUBQkcAAEAhh0A.',
Pa='Pallywhacker:BAAALgAECgUJBQAAAA==.Panconcaca:BAAALgAFFAcJAwAAAA==.Pantsokay:BAAALgADCgEJAQAAAA==.',
Pe='Peach:BAABLgAECn8cAAMgAAgJ4Q1YCwByAQAgAAgJ4Q1YCwByAQARAAYJUAGeSwDNAAAAAA==.Peaches:BAAALgAECgEJAgAAAA==.Petsmart:BAAALgAECgQJBQAAAA==.',
Pi='Pinesol:BAAALgADCgcJBwAAAA==.',
Po='Potatoeshot:BAAALgAECgQJBQAAAA==.',
Pr='Praisethesun:BAAALgAECgQJCQAAAA==.Prayxx:BAAALgAECgYJCQAAAA==.Pretzel:BAACLgAFFH8SAAIFAAUJKSU2JgCuAQAFAAUJKSU2JgCuAQAuAAQKfzMAAwUACQlRJZ4EAIoDAAUACQlRJZ4EAIoDACEAAQk5IWAtAFYAAAAA.Proved:BAABLgAECn9MAAIbAAkJkR1UCQDHAgAbAAkJkR1UCQDHAgAAAA==.',
Ps='Psillycybin:BAAALgAECgcJDQABLgAECgkJQgAbAP0JAA==.',
Pu='Puddingface:BAAALgADCgkJCQAAAA==.Puggar:BAAALgADCgQJBgAAAA==.Pulpp:BAAALgAECgIJAgAAAA==.Pumpspotter:BAAALgAECgkJEgAAAA==.',
Qu='Quiescence:BAAALgADCgYJBgAAAA==.',
Ra='Rakkór:BAAALgAECgEJAQAAAA==.Ranas:BAAALgADCgIJAgAAAA==.Ranessandi:BAAALgAECgEJAQAAAA==.Ratlemebonez:BAAALgAECgEJAQAAAA==.Ravèn:BAAALgAECgcJEQAAAA==.Rayana:BAAALgADCgYJBgAAAA==.Razeal:BAAALgAECgYJDwAAAA==.',
Re='Regerax:BAAALgAECgYJCgABLgAFFAQJCwAHAIIeAA==.Rene:BAEALgAECggJCgAAAA==.Rev:BAAALgADCgEJAQAAAA==.',
Rh='Rhysan:BAACLgAFFH8NAAIMAAQJUBtcIwBEAQAMAAQJUBtcIwBEAQAuAAQKfzsAAgwACQm9F5QzANYBAAwACQm9F5QzANYBAAAA.Rhyuk:BAAALgADCgQJBAAAAA==.',
Ri='Ristria:BAAALgADCgYJEAABLgAECgYJHwAIADgSAA==.Rizy:BAABLgAECn8iAAIFAAkJpA+TRwDkAQAFAAkJpA+TRwDkAQAAAA==.',
Ro='Robonord:BAAALgAECgIJAgAAAA==.Rokki:BAAALgADCgIJAgAAAA==.',
Ru='Rude:BAAALgADCgcJCwAAAA==.',
Ry='Rynhart:BAAALgADCgUJBQAAAA==.Ryushi:BAACLgAFFH8UAAIEAAQJ4hR/PAAhAQAEAAQJ4hR/PAAhAQAuAAQKf0gAAgQACQnGII0YAHgCAAQACQnGII0YAHgCAAAA.',
Sa='Sacerdote:BAABLgAECn8UAAICAAYJPiHkSwCyAQACAAYJPiHkSwCyAQAAAA==.Sakari:BAAALgADCgcJEAAAAA==.Sandara:BAAALgADCgYJBgAAAA==.Sangre:BAAALgADCgIJAgABLgAECgMJBAAOAAAAAA==.Sarasara:BAAALgADCgUJBQAAAA==.',
Sc='Scoots:BAAALgAECgUJCAABLgAFFAQJFQAJAGghAA==.Scratster:BAAALgAECgcJCAAAAA==.',
Se='Sebnoth:BAABLgAECn8yAAIFAAkJtCDaEQDXAgAFAAkJtCDaEQDXAgAAAA==.',
Sh='Shadowspark:BAAALgAECgMJAwAAAA==.Shalashaska:BAAALgADCgEJAQAAAA==.Shamantastik:BAAALgAECgMJAwAAAA==.Shiden:BAAALgAECgYJDwAAAA==.Shift:BAAALgADCgkJCQAAAA==.Shiift:BAAALgADCgYJBwAAAA==.Shockblocked:BAAALgADCgQJBAAAAA==.',
Si='Sideburn:BAAALgADCgUJBQAAAA==.Sidepiece:BAAALgADCgcJCAAAAA==.Sillyderek:BAACLgAFFH8GAAIeAAIJSgjpEgBXAAAeAAIJSgjpEgBXAAAuAAQKfx0AAh4ABwmnDRggAAYBAB4ABwmnDRggAAYBAAAA.',
Sl='Slashology:BAAALgAECgYJDAAAAA==.',
Sm='Smallpally:BAAALgAECgQJDwAAAA==.',
So='Soarsha:BAAALgAECgIJAgAAAA==.Solarida:BAABLgAECn8jAAIIAAgJShpMQgD1AQAIAAgJShpMQgD1AQAAAA==.',
Sr='Srsawyer:BAABLgAECn8bAAICAAgJSA/nYACnAQACAAgJSA/nYACnAQAAAA==.',
St='Staralfur:BAAALgADCgcJBwAAAA==.Stevokerjobs:BAABLgAECn8VAAQUAAYJNRlEGQA4AQAUAAQJBRtEGQA4AQAWAAYJaxJQIAArAQAGAAQJRBPDTADtAAAAAA==.Stormshäde:BAAALgAFFAEJAgAAAA==.Stratos:BAAALgADCgcJBwAAAA==.',
Su='Sunwa:BAACLgAFFH8JAAMIAAIJqxxJeACoAAAIAAIJqxxJeACoAAAeAAEJjwN/GQAnAAAuAAQKfyEAAwgACAlZIE42AB0CAAgACAlZIE42AB0CAB4ABgnxCpgqALkAAAEuAAUUBAkLAAcAgh4A.',
['Sï']='Sïmba:BAAALgAECgMJCQAAAA==.',
Te='Terzhull:BAAALgADCgIJAgAAAA==.',
Th='Thepride:BAAALgAECggJDwAAAA==.',
Ti='Timmytim:BAAALgAECgQJCAAAAA==.Tired:BAAALgAECgUJBgAAAA==.',
To='Tool:BAACLgAFFH8ZAAIKAAgJHBvBAADdAgAKAAgJHBvBAADdAgAuAAQKfyYAAgoACQnrJGMCANgDAAoACQnrJGMCANgDAAEuAAUUCQktAAQAESUA.Touchi:BAAALgAECggJDAABLgAECgkJKQAZABkcAA==.',
Tr='Troljin:BAAALgADCgEJAQAAAA==.',
Tu='Tuo:BAABLgAECn8pAAIZAAkJGRxhBQCQAgAZAAkJGRxhBQCQAgAAAA==.Turbid:BAABLgAECn85AAIEAAkJgBWmMwDsAQAEAAkJgBWmMwDsAQAAAA==.',
Ty='Ty:BAAALgAECgUJDAAAAA==.Tytank:BAAALgADCgMJBAAAAA==.',
Uh='Uhavemyrice:BAAALgADCgIJAgAAAA==.',
Ve='Velkin:BAAALgAECgEJAQAAAA==.',
Vi='Vivia:BAAALgADCgQJBAAAAA==.Viviann:BAAALgADCgMJAwAAAA==.Vivians:BAAALgADCggJCgAAAA==.',
Vo='Voutecomer:BAAALgADCggJDAAAAA==.',
Wa='Walls:BAABLgAECn8YAAIIAAkJNhi8LwA3AgAIAAkJNhi8LwA3AgAAAA==.Warrach:BAAALgADCgQJBAAAAA==.',
We='Welchnut:BAAALgADCgEJAQAAAA==.Wennoe:BAAALgADCgIJAgAAAA==.Westirras:BAABLgAECn8bAAMIAAcJiw6BmQA2AQAIAAcJiw6BmQA2AQAYAAIJTQjCegBNAAAAAA==.',
Wo='Wobblepox:BAAALgAECgkJCAAAAA==.',
Ya='Yarrow:BAAALgAECgMJBAAAAA==.',
Yo='Yogurt:BAAALgAECgcJEQABLgAECgkJLgAIAMcXAA==.',
Yu='Yusuke:BAABLgAECn8WAAMfAAcJfhHgKQBeAQAfAAcJfhHgKQBeAQAQAAYJPQlyQADgAAABLgAECgkJJQANACIaAA==.',
Za='Zabuzabuza:BAAALgAECgIJAgABLgAECgYJFQAUADUZAA==.Zazabandit:BAAALgADCgUJBQAAAA==.',
Zo='Zolleta:BAAALgAECgQJBAAAAA==.',
Zu='Zuesulty:BAAALgADCgYJBgAAAA==.Zunden:BAABLgAECn8YAAMUAAgJWg88EgCcAQAUAAgJWg88EgCcAQAGAAEJAACQoAAAAAAAAA==.',
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
