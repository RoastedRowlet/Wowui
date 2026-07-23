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

local lookup = {'Monk-Mistweaver','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Augmentation','Druid-Guardian','Druid-Restoration','Druid-Balance','Paladin-Retribution','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Hunter-BeastMastery','Priest-Shadow','Rogue-Subtlety','Priest-Discipline','Warlock-Destruction','Unknown-Unknown','Hunter-Marksmanship','DemonHunter-Vengeance','Evoker-Preservation','Warrior-Fury','Warrior-Arms','Warrior-Protection','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Druid-Feral','Rogue-Outlaw','Priest-Holy','Mage-Arcane','Paladin-Protection','Monk-Brewmaster','Rogue-Assassination','DeathKnight-Frost','DemonHunter-Havoc',}
local provider = {region='US',realm='Andorhal',name='US',type='weekly',zone=46,date='2026-07-19',data={Ad='Adelyne:BAAALgAECgQJAwABLgAFFAQJBgABAHMQAA==.Adorablepine:BAABLgAECn8ZAAMCAAcJuANtxQDEAAACAAcJrANtxQDEAAADAAEJqgPzRQAgAAAAAA==.',
Ag='Agaze:BAACLgAFFH8ZAAIEAAcJESC0HADOAQAEAAcJESC0HADOAQAuAAQKfxYAAgQACAkTIgAZAL8CAAQACAkTIgAZAL8CAAAA.',
Ai='Aiedel:BAAALgAECgUJCQAAAA==.',
Al='Allesa:BAAALgAECgEJAQAAAA==.',
An='Antichamp:BAAALgAECgEJAQAAAA==.',
Ao='Aoise:BAAALgAECgkJCgAAAA==.',
Ap='Applejuuice:BAABLgAFFH8HAAIFAAMJexZAmgDbAAAFAAMJexZAmgDbAAABLgAFFAQJBwAGAMAKAA==.',
Ar='Aratre:BAAALgAECgEJAwAAAA==.Archblade:BAAALgAECgQJBwAAAA==.Arelith:BAAALgAECgMJBwAAAA==.Ariggs:BAAALgAECgEJAQAAAA==.Ariosx:BAABLgAFFH8MAAQHAAIJuBa8EwB6AAAHAAIJuBa8EwB6AAAIAAEJSgwcMAAvAAAJAAEJzwJvLAAlAAABLgAFFAQJEQAKAIsdAA==.Arlen:BAABLgAECn8uAAIKAAkJwhhnMgA3AgAKAAkJwhhnMgA3AgAAAA==.Arma:BAABLgAECn8cAAILAAgJjiNGBQAwAwALAAgJjiNGBQAwAwABLgAFFAYJGgAMALMgAA==.Armadro:BAABLgAFFH8aAAIMAAYJsyBEKQDQAQAMAAYJsyBEKQDQAQAAAA==.Armavoid:BAAALgAFFAEJAQAAAA==.',
As='Astoria:BAAALgAECgcJCAAAAA==.',
Au='Aurky:BAAALgAECgEJAwAAAA==.',
Ba='Bald:BAAALgADCgYJBgAAAA==.Balob:BAACLgAFFH8cAAMNAAgJOxk0EACrAQANAAcJYRk0EACrAQAOAAEJvwJCfwA9AAAuAAQKfyUAAg0ACAlqJXoEAFQDAA0ACAlqJXoEAFQDAAAA.Bandar:BAAALgADCgcJBwAAAA==.Bartho:BAAALgADCgEJAQAAAA==.',
Be='Beardlylegal:BAAALgAECgEJAQAAAA==.Behodius:BAAALgAECgMJBAAAAA==.Bellafists:BAAALgAECgYJBgAAAA==.Benchwong:BAAALgAFFAEJAQABLgAFFAgJHAANADsZAA==.',
Bl='Blacksteve:BAAALgAECgIJAgAAAA==.Bloodngore:BAABLgAECn8pAAIPAAkJTxu4CgBlAgAPAAkJTxu4CgBlAgAAAA==.Blumoon:BAAALgAECgEJAQAAAA==.',
Bm='Bmxdh:BAAALgAECgYJDwAAAA==.',
Bo='Bonecollectr:BAABLgAECn8UAAIQAAkJhRSbDgBTAQAQAAkJhRSbDgBTAQAAAA==.Bonkers:BAAALgADCgYJBgAAAA==.',
Br='Brewswayne:BAAALgAECgEJAQAAAA==.Broku:BAAALgAECggJDgABLgAECgkJLgAKAMcXAA==.Brudah:BAAALgAECgEJAQAAAA==.Brutus:BAAALgAFFAMJBAAAAA==.',
Bu='Bubblelove:BAACLgAFFH8KAAIRAAMJXgmyEgCxAAARAAMJXgmyEgCxAAAuAAQKfyQAAhEACQlMDQMmAJwBABEACQlMDQMmAJwBAAAA.Bubbly:BAABLgAECn8uAAIKAAkJxxdpQwD8AQAKAAkJxxdpQwD8AQAAAA==.Butes:BAAALgAECgkJDwAAAA==.',
Ca='Caelum:BAAALgAECgMJAwAAAA==.Callmepappy:BAAALgADCgUJBQAAAA==.Canníbal:BAAALgAECggJDwAAAA==.',
Ce='Censored:BAAALgADCgIJAgAAAA==.',
Ch='Chopsy:BAACLgAFFH8WAAILAAQJiyHLCgB0AQALAAQJiyHLCgB0AQAuAAQKf1wAAwsACQlHJRsCAFADAAsACQlHJRsCAFADAAEAAgnEC91eAFIAAAAA.Chris:BAAALgAECgUJDgAAAA==.Chucklez:BAAALgAFFAIJBAAAAA==.Chulobulo:BAABLgAECn8bAAISAAkJxxW0FQDxAQASAAkJxxW0FQDxAQAAAA==.Chulosdck:BAAALgAECgYJDwABLgAECgkJGwASAMcVAA==.',
Ci='Cinnabons:BAAALgAFFAEJAQABLgAFFAQJBwAGAMAKAA==.',
Cl='Cleopatrick:BAAALgADCgkJEAAAAA==.',
Co='Cobgoblin:BAAALgAECgEJAQAAAA==.Codingsocks:BAAALgADCgEJAgAAAA==.',
Cr='Crekton:BAAALgAECgMJAwAAAA==.Cronnos:BAAALgAECgYJBwAAAA==.',
Cu='Cudlemonster:BAABLgAECn89AAITAAkJbAyCJQCjAQATAAkJbAyCJQCjAQAAAA==.Cursed:BAACLgAFFH8VAAIDAAQJOxi1AwBXAQADAAQJOxi1AwBXAQAuAAQKf0oABAMACQmfIUUBAPQCAAMACQmPIUUBAPQCABQABAn2HHQOAFUBAAIAAwllD5vZAKUAAAAA.',
Da='Dabz:BAABLgAECn8XAAICAAgJhhrDNAAGAgACAAgJhhrDNAAGAgAAAA==.Daddyslaps:BAAALgAECgUJBQAAAA==.Daftmonk:BAAALgAECgUJBQABLgAECgkJLgAKAMcXAA==.Daghma:BAAALgAECgYJBgAAAA==.Danyel:BAAALgAECgMJAwAAAA==.Darmok:BAABLgAECn81AAMOAAkJ3yMLBQBjAwAOAAkJ3yMLBQBjAwANAAEJbBpjmwBBAAAAAA==.Darzamat:BAAALgADCgEJAQAAAA==.Dawtie:BAAALgAECgQJBgABLgAECgkJFAAQAIUUAA==.',
De='Demonbubble:BAACLgAFFH8ZAAIEAAgJeQ5hJQCYAQAEAAgJeQ5hJQCYAQAuAAQKfy0AAgQACQm8FrEuAAwCAAQACQm8FrEuAAwCAAAA.Dezric:BAAALgADCgYJDAABLgAECgYJBgAVAAAAAA==.Dezruf:BAAALgAECgYJBgAAAA==.',
Do='Dotomic:BAABLgAFFH8PAAICAAUJXCBhNAB1AQACAAUJXCBhNAB1AQABLgAFFAkJJQAWAAMhAA==.',
Dr='Drejan:BAAALgAECgcJCQAAAA==.Drfe:BAAALgADCgYJBgAAAA==.Drifthook:BAAALgAECgkJCQAAAA==.Drowarchon:BAAALgADCgIJAgABLgAECgQJBAAVAAAAAA==.Drownix:BAAALgAECgQJBAAAAA==.Drowzy:BAAALgADCgYJBAABLgAECgQJBAAVAAAAAA==.',
['Dä']='Dämonjäger:BAAALgADCggJCAAAAA==.',
Ea='Eastirras:BAAALgAECgUJBQAAAA==.',
Eb='Ebon:BAAALgADCgMJAwAAAA==.',
Ec='Ecaed:BAABLgAECn8bAAIXAAkJ1gaTEwAZAQAXAAkJ1gaTEwAZAQAAAA==.',
Ei='Eisenhørn:BAAALgADCgYJDgAAAA==.',
El='Elektriss:BAAALgAECgQJBAAAAA==.Elnaris:BAABLgAECn8jAAIKAAgJhA3WiABfAQAKAAgJhA3WiABfAQAAAA==.Elohime:BAAALgADCgYJCAAAAA==.',
Eo='Eon:BAAALgAECgIJCQAAAA==.',
Er='Erikkak:BAAALgADCgQJBAAAAA==.Eriu:BAAALgAFFAEJAgABLgAFFAQJEQAKAIsdAA==.Erõs:BAAALgAECgYJCwABLgAECgYJFQAYADUZAA==.',
Fe='Fenixbinkle:BAAALgAECgQJBAAAAA==.',
Fi='Fiero:BAABLgAECn8WAAQZAAgJjgdETgAPAQAZAAgJCAdETgAPAQAaAAEJsAoqFQAmAAAbAAEJkgciEwAbAAABLgAECgkJFAAQAIUUAA==.Fire:BAAALgAECgUJBQABLgAFFAYJFQAGAGUbAA==.',
Fo='Foe:BAAALgAFFAEJAwAAAA==.',
Fr='Fragga:BAABLgAECn8cAAIZAAYJaBbNQgA6AQAZAAYJaBbNQgA6AQAAAA==.',
Fu='Fullflavor:BAAALgADCgIJAgAAAA==.',
['Fü']='Füran:BAAALgADCgIJAgAAAA==.',
Ga='Ganryu:BAAALgADCgYJCgAAAA==.',
Gb='Gboybalili:BAAALgADCgcJDAAAAA==.',
Gi='Gitzi:BAACLgAFFH8OAAIQAAQJlQtwSwAVAQAQAAQJlQtwSwAVAQAuAAQKf0sAAhAACQlZHTEcAF0CABAACQlZHTEcAF0CAAAA.',
Gl='Glaciea:BAAALgADCgMJAwABLgAECggJHgAcAKciAA==.',
Gr='Grayl:BAAALgAECgkJCQAAAA==.Greenrage:BAAALgADCgQJBAAAAA==.Griever:BAAALgAECgYJCQAAAA==.Gripper:BAAALgAECgQJBwABLgAFFAQJFgALAIshAA==.Grips:BAAALgAFFAEJAQAAAA==.Grizzly:BAAALgAECgUJBgABLgAECggJMwAFAIYRAA==.Gro:BAAALgAECgEJAQAAAA==.Groovexgroov:BAABLgAECn8dAAIRAAkJOxhPEQBMAgARAAkJOxhPEQBMAgAAAA==.',
Ha='Harddon:BAAALgAECgUJBQAAAA==.Harlowe:BAAALgADCggJBwAAAA==.',
He='Healrog:BAAALgAECgYJBgAAAA==.Hellraiser:BAAALgAECgQJBQAAAA==.',
Hi='Highfive:BAAALgADCgIJAgAAAA==.',
Ho='Holyfiero:BAAALgAECgcJDgABLgAECgkJFAAQAIUUAA==.Holynight:BAAALgADCgMJBAABLgAECggJMwAFAIYRAA==.Hootie:BAAALgAECgEJAgAAAA==.Hordend:BAAALgAECgUJEAAAAA==.Hozru:BAAALgADCgEJAQAAAA==.',
Hu='Hulkfists:BAABLgAECn8UAAMNAAYJownMSgAcAQANAAYJownMSgAcAQAdAAYJ3gLVHgDiAAAAAA==.',
Hy='Hydration:BAAALgADCgMJAwAAAA==.',
['Hâ']='Hâruka:BAAALgAECgcJBgAAAA==.',
Im='Imcepsy:BAABLgAECn81AAITAAkJ7BkODACuAgATAAkJ7BkODACuAgAAAA==.',
In='Invisobull:BAAALgAECgEJAgAAAA==.',
Io='Iownzuu:BAAALgADCgMJAwAAAA==.',
Is='Istari:BAAALgAECgIJAgAAAA==.Istark:BAAALgAECgMJAwAAAA==.',
Ja='Jayjay:BAACLgAFFH8LAAIMAAUJHxEsXQAlAQAMAAUJHxEsXQAlAQAuAAQKfyIAAgwACQmxHD4mAIICAAwACQmxHD4mAIICAAAA.',
Je='Jethroy:BAABLgAECn8VAAIeAAgJbRHKNwBuAQAeAAgJbRHKNwBuAQAAAA==.',
Jf='Jfkwspvpfldg:BAAALgAECgYJBgAAAA==.',
Ji='Jimmie:BAABLgAECn8aAAISAAgJuiAkEQCYAgASAAgJuiAkEQCYAgAAAA==.Jinxy:BAAALgAECgEJAQABLgAECggJGQAMAHEQAA==.Jirani:BAAALgADCgEJAQAAAA==.',
Jo='Johnparstina:BAAALgAFFAEJAQAAAA==.Jolty:BAACLgAFFH8MAAIdAAQJNx+gBgBQAQAdAAQJNx+gBgBQAQAuAAQKfyEAAh0ACQmrIyICAAUDAB0ACQmrIyICAAUDAAAA.',
Jr='Jrbacnchee:BAAALgAECgEJAQAAAA==.Jrbcncheze:BAAALgAECggJEgAAAA==.',
Ka='Kainicus:BAACLgAFFH8UAAIXAAQJURPaBQAIAQAXAAQJURPaBQAIAQAuAAQKf1kAAhcACQnBGZYFAEsCABcACQnBGZYFAEsCAAAA.Kainigal:BAAALgADCgYJCwAAAA==.Kainisham:BAAALgADCgcJBwAAAA==.',
Ke='Kelador:BAABLgAECn8nAAIfAAkJFgwtGgA8AQAfAAkJFgwtGgA8AQAAAA==.Keoni:BAAALgAECgEJAQAAAA==.Kerrykoppene:BAAALgAECgIJAgAAAA==.',
Kh='Khappucino:BAAALgAECgcJCQAAAA==.Kharibou:BAAALgAECgcJCgAAAA==.Khellendros:BAAALgADCgYJCgAAAA==.Khrism:BAAALgADCgQJBAAAAA==.',
Ki='Kibbi:BAAALgADCgcJBwAAAA==.Kitsyune:BAABLgAECn8fAAIgAAkJ7BeCBQAMAgAgAAkJ7BeCBQAMAgAAAA==.',
Kj='Kjartan:BAAALgAECgUJBgAAAA==.',
Kl='Kløey:BAACLgAFFH8GAAISAAMJ5gtoKgDbAAASAAMJ5gtoKgDbAAAuAAQKfxQAAhIABgnZFMsuAI0BABIABgnZFMsuAI0BAAAA.',
La='Laethys:BAAALgADCggJCAABLgAFFAEJAQAVAAAAAA==.',
Le='Leepriest:BAAALgAECgQJBwAAAA==.',
Li='Lithini:BAAALgAECgQJCQAAAA==.',
Lo='Lowtech:BAAALgAECgMJAwAAAA==.',
Lu='Luminusrayne:BAACLgAFFH8PAAIhAAMJYQUCKACEAAAhAAMJYQUCKACEAAAuAAQKf0YAAxMACQm8DQMiAIQBABMACAn8CgMiAIQBACEACQk+DJkyAD8BAAAA.Lussypipz:BAABLgAFFH8GAAIJAAMJLwUPOgCSAAAJAAMJLwUPOgCSAAABLgAFFAMJBgASAOYLAA==.',
Ma='Mahwe:BAAALgAECggJDgAAAA==.Manafest:BAAALgAECgMJCgAAAA==.Maros:BAABLgAECn8kAAMMAAkJWhanOQAyAgAMAAkJWhanOQAyAgAiAAEJJA+/FgA2AAAAAA==.',
Me='Meheret:BAACLgAFFH8GAAIMAAMJwAAGqgCAAAAMAAMJwAAGqgCAAAAuAAQKf0EAAgwACQlmBsOsACcBAAwACQlmBsOsACcBAAAA.Melissenia:BAAALgAECgQJBAAAAA==.Menious:BAAALgAECgEJAQAAAA==.Mepha:BAAALgAECggJDwAAAA==.',
Mi='Mint:BAABLgAECn8hAAIMAAkJQh5dIwDlAgAMAAkJQh5dIwDlAgABLgAFFAEJAQAVAAAAAA==.',
Mo='Mokth:BAAALgADCgMJAwAAAA==.Molgrath:BAAALgAECgEJAQAAAA==.Mom:BAAALgAECgIJAgAAAA==.Mooby:BAABLgAECn8XAAISAAgJjRocGABHAgASAAgJjRocGABHAgAAAA==.Moomu:BAAALgAECgUJBQAAAA==.Moonfury:BAAALgAECgEJAQAAAA==.Moonleigh:BAAALgADCgMJBAAAAA==.Morganthe:BAAALgAECgIJAwAAAA==.Moria:BAAALgAECgUJBgAAAA==.Morrganx:BAAALgADCgMJAwAAAA==.',
Mu='Munt:BAAALgAECgQJBAABLgAFFAEJAQAVAAAAAA==.',
My='Mypriiest:BAAALgAECgQJBAAAAA==.Myroguëë:BAAALgADCgUJBQAAAA==.Myrolus:BAAALgADCgQJBgAAAA==.Mystx:BAABLgAFFH8PAAIMAAMJNRXwMwDdAAAMAAMJNRXwMwDdAAABLgAFFAQJEQAKAIsdAA==.Mythx:BAACLgAFFH8NAAIZAAQJPyHgFgBZAQAZAAQJPyHgFgBZAQAuAAQKfzgAAhkACQmZJjEBAHMDABkACQmZJjEBAHMDAAEuAAUUBAkRAAoAix0A.Mywarr:BAAALgADCgMJAwAAAA==.',
Na='Naturemage:BAAALgAECgUJBwAAAA==.Natâsi:BAACLgAFFH8MAAIeAAMJ+BhLLQDGAAAeAAMJ+BhLLQDGAAAuAAQKfzQAAh4ACQnUHRYDANUBAB4ACQnUHRYDANUBAAAA.',
Ne='Nerazul:BAABLgAECn8VAAQDAAYJph/GBQAKAgADAAYJph/GBQAKAgACAAMJ3wqC4wCTAAAUAAEJ/AgReAAsAAAAAA==.Netharec:BAAALgADCgEJAQABLgAFFAcJGAARAIsaAA==.Neuralgia:BAAALgADCgEJAQAAAA==.Nevai:BAABLgAECn8YAAIeAAkJCxILIgD0AQAeAAkJCxILIgD0AQAAAA==.',
Ni='Nielas:BAABLgAECn8UAAIFAAgJ7yAIKQBdAgAFAAgJ7yAIKQBdAgAAAA==.Nihilus:BAACLgAFFH8TAAIFAAcJmRmTCACMAQAFAAcJmRmTCACMAQAuAAQKfxUAAgUABwkWJLkvAHkCAAUABwkWJLkvAHkCAAAA.Nilari:BAABLgAECn8UAAIjAAYJIQmGMACkAAAjAAYJIQmGMACkAAAAAA==.Nine:BAAALgADCgYJBgABLgAFFAQJFgALAIshAA==.',
No='Noctazari:BAAALgADCgUJBQAAAA==.Noctium:BAABLgAECn8eAAIcAAgJpyL7AgB7AgAcAAgJpyL7AgB7AgAAAA==.Nostrildamus:BAAALgAECgYJEQABLgAECgkJGAAKADYYAA==.',
Nz='Nzoth:BAAALgADCgYJBgAAAA==.',
Of='Officimeeg:BAAALgAECgEJAQAAAA==.',
Ow='Owlaf:BAAALgAECgIJAgABLgAFFAYJIAATAB8aAA==.Owlchi:BAACLgAFFH8FAAIBAAQJ8wxKNgDQAAABAAQJ8wxKNgDQAAAuAAQKfxYAAwEABwktHcUZAEoCAAEABwktHcUZAEoCACQABQmRD/BMAMsAAAEuAAUUBgkgABMAHxoA.Owls:BAACLgAFFH8gAAITAAYJHxqBFADfAQATAAYJHxqBFADfAQAuAAQKfzoAAxMACQkWIyUHAAoDABMACQmGICUHAAoDACEABwkbJPcKAJ8CAAEuAAUUBgkgABMAHxoA.',
Pa='Pallywhacker:BAAALgAECgYJBwAAAA==.Panconcaca:BAAALgAFFAcJAwAAAA==.Pantsokay:BAAALgADCgEJAQAAAA==.',
Pe='Peach:BAABLgAECn8cAAMlAAgJ4Q3rCwBwAQAlAAgJ4Q3rCwBwAQASAAYJUAGeSwDNAAAAAA==.Peaches:BAAALgAECgEJAgAAAA==.Petsmart:BAAALgAECgQJBQAAAA==.',
Pi='Pinesol:BAAALgADCgcJBwAAAA==.',
Po='Potatoeshot:BAAALgAECgQJBQAAAA==.',
Pr='Praisethesun:BAAALgAECgQJCQAAAA==.Prayxx:BAAALgAECgYJCQAAAA==.Pretzel:BAACLgAFFH8UAAIFAAcJECUUMQCkAQAFAAcJECUUMQCkAQAuAAQKfzQAAwUACQljJZ4EAIoDAAUACQljJZ4EAIoDACYAAQk5IcExAFYAAAAA.Proved:BAACLgAFFH8FAAIhAAMJBgo2LgBeAAAhAAMJBgo2LgBeAAAuAAQKf00AAiEACQmRHUEKAMMCACEACQmRHUEKAMMCAAAA.',
Ps='Psillycybin:BAAALgAECgcJDQABLgAECgkJQgAhAP0JAA==.',
Pu='Puddingface:BAAALgADCgkJCQABLgAECgEJAQAVAAAAAA==.Puggar:BAAALgADCgQJBgAAAA==.Pugnacious:BAAALgAECgEJAQAAAA==.Pulpeh:BAAALgAECgYJDQAAAA==.Pulpp:BAAALgAECgIJAwAAAA==.Pumpspotter:BAAALgAECgkJEgAAAA==.',
Qu='Quiescence:BAAALgADCgYJBgAAAA==.',
Ra='Rakkór:BAAALgAECgEJAgAAAA==.Ranas:BAAALgADCgIJAgAAAA==.Ranessandi:BAAALgAECgEJAQAAAA==.Ratlemebonez:BAAALgAECgEJAQAAAA==.Ravèn:BAAALgAECgcJEQAAAA==.Rayana:BAAALgADCgYJBgAAAA==.Razeal:BAAALgAECgYJDwAAAA==.',
Re='Regerax:BAABLgAFFH8IAAIQAAIJdhgcOwCsAAAQAAIJdhgcOwCsAAABLgAFFAQJEQAKAIsdAA==.Rene:BAEALgAECggJCgAAAA==.Rev:BAAALgADCgEJAQAAAA==.',
Rh='Rhysan:BAACLgAFFH8OAAIOAAQJaByPKQA/AQAOAAQJaByPKQA/AQAuAAQKfzsAAg4ACQm9F4k2ANYBAA4ACQm9F4k2ANYBAAAA.Rhyuk:BAAALgADCgQJBAAAAA==.',
Ri='Rimzak:BAAALgAECgYJCgABLgAECgkJFAAQAIUUAA==.Ristria:BAAALgADCgYJEAABLgAECgcJIAAKAAgSAA==.Rizy:BAABLgAECn8iAAIFAAkJpA/QTQDZAQAFAAkJpA/QTQDZAQAAAA==.',
Ro='Robonord:BAAALgAECgIJAgAAAA==.Rokki:BAAALgADCgIJAgAAAA==.',
Ru='Rude:BAAALgADCgcJCwAAAA==.',
Ry='Rynhart:BAAALgADCgUJBQAAAA==.Ryntard:BAAALgAECgYJBgAAAA==.Ryushi:BAACLgAFFH8VAAIEAAQJ4hTRRAAZAQAEAAQJ4hTRRAAZAQAuAAQKf0gAAgQACQnGICoaAHcCAAQACQnGICoaAHcCAAAA.',
Sa='Sacerdote:BAABLgAECn8UAAICAAYJPiF3TgCvAQACAAYJPiF3TgCvAQAAAA==.Sakari:BAAALgADCgcJEAAAAA==.Sandara:BAAALgADCgYJBgAAAA==.Sangre:BAAALgADCgIJAgABLgAECgMJBAAVAAAAAA==.Sarasara:BAAALgADCgUJBQAAAA==.Sathicus:BAAALgAECgMJAwAAAA==.',
Sc='Scoots:BAAALgAECgUJCAABLgAFFAQJFgALAIshAA==.Scratster:BAAALgAECgcJCAAAAA==.',
Se='Sebnoth:BAABLgAECn81AAIFAAkJnyHIEwDRAgAFAAkJnyHIEwDRAgAAAA==.',
Sh='Shadowspark:BAABLgAECn8YAAIWAAgJVSB7AACbAgAWAAgJVSB7AACbAgAAAA==.Shalashaska:BAAALgADCgEJAQAAAA==.Shamantastik:BAAALgAECgMJAwAAAA==.Shazzy:BAAALgAECgEJAQAAAA==.Shiden:BAAALgAECgYJDwAAAA==.Shift:BAAALgADCgkJCQAAAA==.Shiift:BAAALgADCgYJBwAAAA==.Shockblocked:BAAALgADCgQJBAAAAA==.',
Si='Sidepiece:BAAALgADCgcJCAAAAA==.Sillyderek:BAACLgAFFH8GAAIjAAIJSghXFQBQAAAjAAIJSghXFQBQAAAuAAQKfx0AAiMABwmnDfchAAUBACMABwmnDfchAAUBAAAA.',
Sl='Slashology:BAAALgAECgYJDAAAAA==.',
Sm='Smallpally:BAABLgAECn8UAAIKAAcJBRV/fwBwAQAKAAcJBRV/fwBwAQAAAA==.',
So='Soarsha:BAAALgAECgIJAgAAAA==.Solarida:BAABLgAECn8yAAIKAAkJYhuvBAA3AgAKAAkJYhuvBAA3AgAAAA==.',
Sr='Srsawyer:BAABLgAECn8bAAICAAgJSA/nYACnAQACAAgJSA/nYACnAQAAAA==.',
St='Staralfur:BAAALgADCgcJBwAAAA==.Stevokerjobs:BAABLgAECn8VAAQYAAYJNRn3GQA4AQAYAAQJBRv3GQA4AQAcAAYJaxJQIAArAQAGAAQJRBP8UADrAAAAAA==.Stormshäde:BAAALgAFFAEJBAAAAA==.Stratos:BAAALgADCgcJBwAAAA==.',
Su='Sumlkithot:BAAALgAECgUJCQAAAA==.Sunwa:BAACLgAFFH8RAAMKAAQJix2eKQBlAQAKAAQJix2eKQBlAQAjAAIJvwUaEAAmAAAuAAQKfyIAAwoACAlZIFc6ABoCAAoACAlZIFc6ABoCACMABgnxCtIsALgAAAAA.',
['Sï']='Sïmba:BAAALgAECgMJCQAAAA==.',
Ta='Talyashamwow:BAAALgADCgYJBgAAAA==.',
Te='Terzhull:BAAALgADCgIJAgAAAA==.',
Th='Thepride:BAAALgAECggJDwAAAA==.Thespian:BAAALgAECgEJAQAAAA==.',
Ti='Timmytim:BAAALgAECgQJCAAAAA==.Tired:BAAALgAECgUJBgAAAA==.',
To='Tool:BAACLgAFFH8ZAAIMAAgJHBvBAADdAgAMAAgJHBvBAADdAgAuAAQKfyYAAgwACQnrJGMCANgDAAwACQnrJGMCANgDAAEuAAUUCQkvAAQAESUA.Tooms:BAAALgAECgcJBwAAAA==.Touchi:BAAALgAECggJDQABLgAECgkJKQAfABkcAA==.',
Tr='Troljin:BAAALgADCgEJAQAAAA==.',
Tu='Tuo:BAABLgAECn8pAAIfAAkJGRzwBQCNAgAfAAkJGRzwBQCNAgAAAA==.Turbid:BAABLgAECn9QAAMXAAkJ4xfBAQB9AQAEAAkJ4xf6JwArAgAXAAkJDA3BAQB9AQAAAA==.',
Ty='Ty:BAAALgAECgUJDAAAAA==.Tytank:BAAALgADCgMJBAAAAA==.',
Uh='Uhavemyrice:BAAALgADCgIJAgAAAA==.',
Ve='Velkin:BAAALgAECgEJAQAAAA==.',
Vi='Vivia:BAAALgADCgQJBAAAAA==.Viviann:BAAALgADCgMJAwAAAA==.Vivians:BAAALgADCggJCgAAAA==.',
Vo='Voutecomer:BAAALgAECgYJCQAAAA==.',
Vy='Vyndictive:BAAALgADCgkJCQAAAA==.',
Wa='Walls:BAABLgAECn8YAAIKAAkJNhg+MwAzAgAKAAkJNhg+MwAzAgAAAA==.Warrach:BAAALgADCgQJBAAAAA==.',
We='Welchnut:BAAALgADCgEJAQAAAA==.Wennoe:BAAALgADCgIJAgAAAA==.Westirras:BAABLgAECn8kAAMKAAgJdhFyeAB9AQAKAAgJdhFyeAB9AQAeAAIJTQiafwBNAAAAAA==.',
Wo='Wobblepox:BAAALgAECgkJCAAAAA==.',
Ya='Yarrow:BAAALgAECggJDAAAAA==.',
Yo='Yogurt:BAABLgAECn8UAAInAAcJdg90KgArAQAnAAcJdg90KgArAQABLgAECgkJLgAKAMcXAA==.',
Yu='Yusuke:BAABLgAECn8WAAMkAAcJfhF7KwBcAQAkAAcJfhF7KwBcAQABAAYJPQlyQADgAAABLgAECgkJKQAPAE8bAA==.',
Za='Zabuzabuza:BAAALgAECgIJAgABLgAECgYJFQAYADUZAA==.Zazabandit:BAAALgADCgUJBQAAAA==.',
Zo='Zolleta:BAAALgAECgQJBAAAAA==.',
Zu='Zuesulty:BAAALgADCgYJBgAAAA==.Zunden:BAABLgAECn8YAAMYAAgJWg9bEwCUAQAYAAgJWg9bEwCUAQAGAAEJAABtqgAAAAAAAA==.',
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
