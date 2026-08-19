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

local lookup = {'Priest-Discipline','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Augmentation','Unknown-Unknown','Druid-Guardian','Druid-Balance','Druid-Restoration','Paladin-Retribution','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Hunter-BeastMastery','Priest-Shadow','Monk-Mistweaver','Rogue-Subtlety','Warlock-Destruction','Hunter-Marksmanship','DemonHunter-Vengeance','Evoker-Preservation','Warrior-Fury','Warrior-Arms','Warrior-Protection','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Druid-Feral','Rogue-Outlaw','Priest-Holy','Mage-Arcane','Paladin-Protection','Monk-Brewmaster','Rogue-Assassination','DeathKnight-Frost','DemonHunter-Havoc',}
local provider = {region='US',realm='Andorhal',name='US',type='weekly',zone=46,date='2026-08-18',data={Ad='Adelyne:BAAALgAECgQJAwABLgAFFAcJEgABABkcAA==.Adorablepine:BAABLgAECn8ZAAMCAAcJuANtxQDEAAACAAcJrANtxQDEAAADAAEJqgPzRQAgAAAAAA==.Adoreith:BAAALgAECgYJBgAAAA==.',
Ag='Agaze:BAACLgAFFH8bAAIEAAgJfR+0HADOAQAEAAgJfR+0HADOAQAuAAQKfxYAAgQACAkTIgAZAL8CAAQACAkTIgAZAL8CAAAA.',
Ai='Aiedel:BAAALgAECgUJCQAAAA==.',
Al='Allesa:BAAALgAECgEJAQAAAA==.',
An='Antichamp:BAAALgAECgEJAQAAAA==.',
Ao='Aoise:BAAALgAECgkJCgAAAA==.',
Ap='Applejuuice:BAABLgAFFH8HAAIFAAMJexZAmgDbAAAFAAMJexZAmgDbAAABLgAFFAQJBwAGAMAKAA==.',
Ar='Aratre:BAAALgAECgEJAwABLgAECgkJEQAHAAAAAA==.Archblade:BAAALgAECgQJBwAAAA==.Arelith:BAAALgAECgMJBwAAAA==.Ariggs:BAAALgAECgEJAQAAAA==.Ariosx:BAABLgAFFH8NAAQIAAIJuBa/FgB0AAAIAAIJuBa/FgB0AAAJAAIJHwiGJQBdAAAKAAEJSgzWMwAsAAABLgAFFAQJEgALAAUfAA==.Arlen:BAABLgAECn8uAAILAAkJwhhnMgA3AgALAAkJwhhnMgA3AgAAAA==.Arma:BAABLgAECn8cAAIMAAgJjiNGBQAwAwAMAAgJjiNGBQAwAwABLgAFFAYJGgANALMgAA==.Armadro:BAABLgAFFH8aAAINAAYJsyBEKQDQAQANAAYJsyBEKQDQAQAAAA==.Armavoid:BAAALgAFFAEJAQAAAA==.',
As='Astoria:BAAALgAECgcJCQABLgAECgkJEQAHAAAAAA==.',
Au='Aurky:BAAALgAECgEJAwAAAA==.',
Ba='Bald:BAAALgADCgYJBgAAAA==.Balob:BAACLgAFFH8dAAMOAAkJoxc0EACrAQAOAAgJiRc0EACrAQAPAAEJvwJCfwA9AAAuAAQKfyUAAg4ACAlqJXoEAFQDAA4ACAlqJXoEAFQDAAAA.Bandar:BAAALgADCgcJBwAAAA==.Bartho:BAAALgADCgEJAQAAAA==.',
Be='Beardlylegal:BAAALgAECgEJAQAAAA==.Behodius:BAAALgAECgMJBAAAAA==.Bellafists:BAAALgAECgYJBgAAAA==.Benchwong:BAAALgAFFAEJAQABLgAFFAkJHQAOAKMXAA==.',
Bl='Blacksteve:BAAALgAECgIJAgAAAA==.Bloodngore:BAABLgAECn8pAAIQAAkJTxu4CgBlAgAQAAkJTxu4CgBlAgAAAA==.Blumoon:BAAALgAECgEJAQAAAA==.Bluos:BAAALgADCgMJBAAAAA==.',
Bm='Bmxdh:BAAALgAECgYJDwAAAA==.',
Bo='Bonecollectr:BAABLgAECn8UAAIRAAkJhRSTEwBLAQARAAkJhRSTEwBLAQAAAA==.Bonkers:BAAALgADCgYJBgAAAA==.',
Br='Brewswayne:BAAALgAECgEJAQAAAA==.Brightghoul:BAAALgADCgYJDAAAAA==.Brightghoulz:BAAALgAECgIJAgAAAA==.Broku:BAAALgAECggJDwABLgAECgkJLgALAMcXAA==.Brudah:BAAALgAECgEJAQAAAA==.Brutus:BAAALgAFFAMJBAAAAA==.',
Bu='Bubblelove:BAACLgAFFH8KAAISAAMJXglDFwCmAAASAAMJXglDFwCmAAAuAAQKfyQAAhIACQlMDQMmAJwBABIACQlMDQMmAJwBAAAA.Bubbly:BAABLgAECn8uAAILAAkJxxdpQwD8AQALAAkJxxdpQwD8AQAAAA==.Butes:BAAALgAECgkJDwAAAA==.',
Ca='Caelum:BAAALgAECgMJAwAAAA==.Callmepappy:BAAALgADCgUJBQAAAA==.Canníbal:BAAALgAECggJDwAAAA==.',
Ce='Censored:BAAALgADCgIJAgAAAA==.',
Ch='Chopsy:BAACLgAFFH8WAAIMAAQJiyHLCgB0AQAMAAQJiyHLCgB0AQAuAAQKf1wAAwwACQlHJRsCAFADAAwACQlHJRsCAFADABMAAgnEC91eAFIAAAAA.Chris:BAAALgAECgUJDgAAAA==.Chucklez:BAAALgAFFAIJBAAAAA==.Chulobulo:BAABLgAECn8bAAIUAAkJxxW0FQDxAQAUAAkJxxW0FQDxAQAAAA==.Chulosdck:BAAALgAECgYJDwABLgAECgkJGwAUAMcVAA==.',
Ci='Cinnabons:BAAALgAFFAEJAQABLgAFFAQJBwAGAMAKAA==.',
Cl='Cleopatrick:BAAALgADCgkJEAAAAA==.',
Co='Cobgoblin:BAAALgAECgEJAQAAAA==.Codingsocks:BAAALgADCgEJAgAAAA==.Comeplay:BAABLgAFFH8JAAIOAAUJ/Q4YFgDqAAAOAAUJ/Q4YFgDqAAAAAA==.',
Cr='Crekton:BAAALgAECgMJAwAAAA==.Cronnos:BAAALgAECgYJBwAAAA==.',
Cu='Cudlemonster:BAABLgAECn89AAIBAAkJbAyCJQCjAQABAAkJbAyCJQCjAQAAAA==.Cursed:BAACLgAFFH8VAAIDAAQJOxi1AwBXAQADAAQJOxi1AwBXAQAuAAQKf0oABAMACQmfIUUBAPQCAAMACQmPIUUBAPQCABUABAn2HHQOAFUBAAIAAwllD5vZAKUAAAAA.',
Da='Dabz:BAABLgAECn8XAAICAAgJhhrDNAAGAgACAAgJhhrDNAAGAgAAAA==.Daddyslaps:BAAALgAECgUJBQAAAA==.Daftmonk:BAAALgAECgUJBQABLgAECgkJLgALAMcXAA==.Daghma:BAAALgAECgYJBgAAAA==.Danyel:BAAALgAECgMJAwAAAA==.Darmok:BAABLgAECn81AAMPAAkJ3yMLBQBjAwAPAAkJ3yMLBQBjAwAOAAEJbBpjmwBBAAAAAA==.Darzamat:BAAALgADCgEJAQAAAA==.Dawtie:BAAALgAECgQJBgABLgAECgkJFAARAIUUAA==.',
De='Demonbubble:BAACLgAFFH8ZAAIEAAgJeQ5hJQCYAQAEAAgJeQ5hJQCYAQAuAAQKfy0AAgQACQm8FrEuAAwCAAQACQm8FrEuAAwCAAAA.Dezric:BAAALgADCgYJDAABLgAECgYJBgAHAAAAAA==.Dezruf:BAAALgAECgYJBgAAAA==.',
Do='Dotomic:BAABLgAFFH8QAAICAAUJXCBhNAB1AQACAAUJXCBhNAB1AQABLgAFFAkJMwAWAHIjAA==.',
Dr='Drejan:BAAALgAECgcJCQAAAA==.Drfe:BAAALgADCgYJBgAAAA==.Drifthook:BAAALgAECgkJCQAAAA==.Drowarchon:BAAALgADCgIJAgABLgAECgQJBAAHAAAAAA==.Drownix:BAAALgAECgQJBAAAAA==.Drowzy:BAAALgADCgYJBAABLgAECgQJBAAHAAAAAA==.',
['Dä']='Dämonjäger:BAAALgADCggJCAAAAA==.',
Ea='Eastirras:BAAALgAECgUJBQAAAA==.',
Eb='Ebon:BAAALgADCgMJAwAAAA==.',
Ec='Ecaed:BAABLgAECn8bAAIXAAkJ1gaTEwAZAQAXAAkJ1gaTEwAZAQAAAA==.',
Ed='Edinaz:BAAALgAECgQJBQABLgAECgkJEQAHAAAAAA==.',
Ei='Eisenhørn:BAAALgADCgYJDgAAAA==.',
El='Elektriss:BAAALgAECgQJBAAAAA==.Elnaris:BAABLgAECn8jAAILAAgJhA3WiABfAQALAAgJhA3WiABfAQAAAA==.Elohime:BAAALgADCgYJCAAAAA==.',
Em='Emiliow:BAAALgADCgcJCQAAAA==.Empìre:BAAALgAECgIJAgAAAA==.',
Eo='Eon:BAAALgAECgIJCQAAAA==.',
Er='Erikkak:BAAALgADCgQJBAAAAA==.Eriu:BAAALgAFFAEJAgABLgAFFAQJEgALAAUfAA==.Erõs:BAAALgAECgYJCwABLgAECgYJFQAYADUZAA==.',
Fe='Fenixbinkle:BAAALgAECgQJBAAAAA==.',
Fi='Fiero:BAABLgAECn8WAAQZAAgJjgdETgAPAQAZAAgJCAdETgAPAQAaAAEJsArRHgAkAAAbAAEJkgd3GAAbAAABLgAECgkJFAARAIUUAA==.Fire:BAAALgAECgUJBQABLgAFFAYJFQAGAGUbAA==.',
Fo='Foe:BAAALgAFFAEJAwAAAA==.',
Fr='Fragga:BAABLgAECn8cAAIZAAYJaBbNQgA6AQAZAAYJaBbNQgA6AQAAAA==.',
Fu='Fullflavor:BAAALgADCgIJAgAAAA==.',
['Fü']='Füran:BAAALgADCgIJAgAAAA==.',
Ga='Ganryu:BAAALgADCgYJCgAAAA==.',
Gb='Gboybalili:BAAALgADCgcJDAAAAA==.',
Gi='Gitzi:BAACLgAFFH8OAAIRAAQJlQtwSwAVAQARAAQJlQtwSwAVAQAuAAQKf0sAAhEACQlZHTEcAF0CABEACQlZHTEcAF0CAAAA.',
Gl='Glaciea:BAAALgADCgMJAwABLgAECgkJHwAcAKciAA==.',
Gr='Grayl:BAAALgAECgkJCQAAAA==.Greenrage:BAAALgADCgQJBAAAAA==.Griever:BAAALgAECgYJCQAAAA==.Gripper:BAAALgAECgQJBwABLgAFFAQJFgAMAIshAA==.Grizzly:BAAALgAECgUJBgABLgAECgkJNAAFAEwSAA==.Gro:BAAALgAECgEJAQABLgAECgkJEQAHAAAAAA==.Groovexgroov:BAABLgAECn8dAAISAAkJOxhPEQBMAgASAAkJOxhPEQBMAgAAAA==.',
Ha='Hallena:BAAALgAECgkJAQAAAA==.Harddon:BAAALgAECgUJBQAAAA==.Harlowe:BAAALgADCggJBwAAAA==.',
He='Headie:BAAALgAECgEJAgAAAA==.Healrog:BAAALgAECgYJBgAAAA==.Hellraiser:BAAALgAECgQJBQAAAA==.',
Hi='Highfive:BAAALgADCgIJAgAAAA==.',
Ho='Holyblast:BAAALgAECgQJBAAAAA==.Holyfiero:BAAALgAECgcJDgABLgAECgkJFAARAIUUAA==.Holynight:BAAALgADCgMJBAABLgAECgkJNAAFAEwSAA==.Hootie:BAAALgAECgEJAgAAAA==.Hordend:BAAALgAECgUJEAAAAA==.Hozru:BAAALgADCgEJAQAAAA==.',
Hu='Hulkfists:BAABLgAECn8UAAMOAAYJownMSgAcAQAOAAYJownMSgAcAQAdAAYJ3gLVHgDiAAAAAA==.',
Hy='Hydration:BAAALgADCgMJAwAAAA==.',
['Hâ']='Hâruka:BAAALgAECgkJBgAAAA==.',
Im='Imcepsy:BAABLgAECn81AAIBAAkJ7BkODACuAgABAAkJ7BkODACuAgAAAA==.',
In='Invisobull:BAAALgAECgEJAgAAAA==.',
Io='Iownzuu:BAAALgADCgMJAwAAAA==.',
Is='Istari:BAAALgAECgIJAgAAAA==.Istark:BAAALgAECgMJAwAAAA==.',
Ja='Jayjay:BAACLgAFFH8LAAINAAUJHxEsXQAlAQANAAUJHxEsXQAlAQAuAAQKfyMAAg0ACQmKHz4mAIICAA0ACQmKHz4mAIICAAAA.',
Je='Jethroy:BAABLgAECn8VAAIeAAgJbRHKNwBuAQAeAAgJbRHKNwBuAQAAAA==.',
Ji='Jiga:BAAALgAECgkJEQAAAA==.Jimmie:BAABLgAECn8aAAIUAAgJuiAkEQCYAgAUAAgJuiAkEQCYAgAAAA==.Jinxy:BAAALgAECgIJAgABLgAECgkJHQANACIVAA==.Jirani:BAAALgADCgEJAQAAAA==.',
Jo='Johnparstina:BAABLgAECn8UAAMRAAgJchvWCwC1AQARAAgJchvWCwC1AQAWAAQJGgK6bwCAAAAAAA==.Jolty:BAACLgAFFH8MAAIdAAQJNx+gBgBQAQAdAAQJNx+gBgBQAQAuAAQKfyEAAh0ACQmrIyICAAUDAB0ACQmrIyICAAUDAAAA.Jorb:BAAALgAFFAEJAgAAAA==.',
Jr='Jraz:BAAALgAECgkJAgAAAA==.Jrbacnchee:BAAALgAECgEJAQAAAA==.Jrbcncheze:BAAALgAECggJEgAAAA==.',
Ka='Kainicus:BAACLgAFFH8UAAIXAAQJURPaBQAIAQAXAAQJURPaBQAIAQAuAAQKf1kAAhcACQnBGZYFAEsCABcACQnBGZYFAEsCAAAA.Kainigal:BAAALgADCgYJCwAAAA==.Kainisham:BAAALgADCgcJBwAAAA==.',
Ke='Kelador:BAABLgAECn8pAAIfAAkJ0g4tGgA8AQAfAAkJ0g4tGgA8AQAAAA==.Keoni:BAAALgAECgEJAQAAAA==.Kerrykoppene:BAAALgAECgIJAgAAAA==.',
Kh='Khappucino:BAAALgAECgcJCQAAAA==.Kharibou:BAAALgAECgcJCgAAAA==.Khellendros:BAAALgADCgYJCgAAAA==.Khrism:BAAALgADCgQJBAAAAA==.',
Ki='Kibbi:BAAALgADCgcJBwAAAA==.',
Kj='Kjartan:BAAALgAECgUJBgAAAA==.',
Kl='Kløey:BAACLgAFFH8GAAIUAAMJ5gtoKgDbAAAUAAMJ5gtoKgDbAAAuAAQKfxQAAhQABgnZFMsuAI0BABQABgnZFMsuAI0BAAAA.',
La='Laethys:BAAALgADCggJCAABLgAFFAEJAgAHAAAAAA==.',
Le='Leepriest:BAAALgAECgQJBwAAAA==.',
Li='Lithini:BAAALgAECgQJCQAAAA==.',
Lo='Lowtech:BAAALgAECgMJAwAAAA==.',
Lu='Luckii:BAABLgAECn8fAAIgAAkJ7BeCBQAMAgAgAAkJ7BeCBQAMAgAAAA==.Luminusrayne:BAACLgAFFH8PAAIhAAMJYQUCKACEAAAhAAMJYQUCKACEAAAuAAQKf0YAAwEACQm8DQMiAIQBAAEACAn8CgMiAIQBACEACQk+DJkyAD8BAAAA.Lussypipz:BAABLgAFFH8GAAIJAAMJLwUPOgCSAAAJAAMJLwUPOgCSAAABLgAFFAMJBgAUAOYLAA==.Lustie:BAAALgAECgUJCAAAAA==.',
Ma='Mahwe:BAAALgAECggJDgAAAA==.Manafest:BAAALgAECgMJCgAAAA==.Maros:BAABLgAECn8kAAMNAAkJWhanOQAyAgANAAkJWhanOQAyAgAiAAEJJA+/FgA2AAAAAA==.',
Me='Meheret:BAACLgAFFH8GAAINAAMJwAAGqgCAAAANAAMJwAAGqgCAAAAuAAQKf0EAAg0ACQlmBsOsACcBAA0ACQlmBsOsACcBAAAA.Melissenia:BAAALgAECgQJBAAAAA==.Menious:BAAALgAECgEJAQAAAA==.Mepha:BAAALgAECggJDwAAAA==.',
Mi='Mint:BAABLgAECn8hAAINAAkJQh5dIwDlAgANAAkJQh5dIwDlAgABLgAFFAEJAgAHAAAAAA==.',
Mo='Mokth:BAAALgADCgMJAwAAAA==.Molgrath:BAAALgAECgEJAQAAAA==.Mom:BAAALgAECgIJAgAAAA==.Mooby:BAABLgAECn8XAAIUAAgJjRocGABHAgAUAAgJjRocGABHAgAAAA==.Moomu:BAAALgAECgUJBQAAAA==.Moonfury:BAAALgAECgEJAQAAAA==.Moonleigh:BAAALgADCgMJBAAAAA==.Morganthe:BAAALgAECgIJAwAAAA==.Moria:BAAALgAECgUJBgAAAA==.Morrganx:BAAALgAECgUJBQAAAA==.',
Mu='Munt:BAAALgAECgQJBAABLgAFFAEJAgAHAAAAAA==.',
My='Mypriiest:BAAALgAECgQJBAAAAA==.Myroguëë:BAAALgADCgUJBQAAAA==.Myrolus:BAAALgADCgUJBwAAAA==.Mystx:BAABLgAFFH8RAAINAAMJRhkVOQDgAAANAAMJRhkVOQDgAAABLgAFFAQJEgALAAUfAA==.Mythx:BAACLgAFFH8NAAIZAAQJPyHgFgBZAQAZAAQJPyHgFgBZAQAuAAQKfzkAAhkACQmZJjEBAHMDABkACQmZJjEBAHMDAAEuAAUUBAkSAAsABR8A.Mywarr:BAAALgADCgMJAwAAAA==.',
Na='Naturemage:BAAALgAECgUJBwAAAA==.Natâsi:BAACLgAFFH8MAAIeAAMJ+BhLLQDGAAAeAAMJ+BhLLQDGAAAuAAQKfzQAAh4ACQnWHWMEANQBAB4ACQnWHWMEANQBAAAA.',
Ne='Nebulis:BAAALgAECgMJAwAAAA==.Nerazul:BAABLgAECn8VAAQDAAYJph/GBQAKAgADAAYJph/GBQAKAgACAAMJ3wqC4wCTAAAVAAEJ/AgReAAsAAAAAA==.Netharec:BAAALgADCgEJAQABLgAFFAcJGAASAIsaAA==.Neuralgia:BAAALgAECgEJAQABLgAECgkJEQAHAAAAAA==.Nevai:BAABLgAECn8YAAIeAAkJCxILIgD0AQAeAAkJCxILIgD0AQAAAA==.',
Ni='Nielas:BAABLgAECn8UAAIFAAgJ7yAIKQBdAgAFAAgJ7yAIKQBdAgAAAA==.Nihilus:BAACLgAFFH8XAAIFAAcJURqTCACMAQAFAAcJURqTCACMAQAuAAQKfxUAAgUABwkWJLkvAHkCAAUABwkWJLkvAHkCAAAA.Nilari:BAABLgAECn8UAAIjAAYJIQmGMACkAAAjAAYJIQmGMACkAAAAAA==.Nine:BAAALgADCgYJBgABLgAFFAQJFgAMAIshAA==.',
No='Noctazari:BAAALgADCgUJBQAAAA==.Noctium:BAABLgAECn8fAAIcAAgJpyL7AgB7AgAcAAgJpyL7AgB7AgAAAA==.Nostrildamus:BAAALgAECgYJEQABLgAECgkJGAALADYYAA==.',
Nz='Nzoth:BAAALgADCgYJBgAAAA==.',
Of='Officimeeg:BAAALgAECgEJAQAAAA==.',
Ow='Owlaf:BAAALgAECgIJAgABLgAFFAYJIAABAB8aAA==.Owlchi:BAACLgAFFH8FAAITAAQJ8wxKNgDQAAATAAQJ8wxKNgDQAAAuAAQKfxYAAxMABwktHcUZAEoCABMABwktHcUZAEoCACQABQmRD/BMAMsAAAEuAAUUBgkgAAEAHxoA.Owls:BAACLgAFFH8gAAIBAAYJHxqBFADfAQABAAYJHxqBFADfAQAuAAQKfzoAAwEACQkWIyUHAAoDAAEACQmGICUHAAoDACEABwkbJPcKAJ8CAAEuAAUUBgkgAAEAHxoA.',
Pa='Panconcaca:BAAALgAFFAcJAwAAAA==.Pantsokay:BAAALgADCgEJAQAAAA==.',
Pe='Peach:BAABLgAECn8cAAMlAAgJ4Q3rCwBwAQAlAAgJ4Q3rCwBwAQAUAAYJUAGeSwDNAAAAAA==.Peaches:BAAALgAECgEJAgAAAA==.Petsmart:BAAALgAECgQJBQAAAA==.',
Pi='Pily:BAAALgAECgEJAQAAAA==.Pinesol:BAAALgADCgcJBwAAAA==.',
Po='Porkstomper:BAAALgAECgEJAQAAAA==.Potatoeshot:BAAALgAECgQJBQAAAA==.',
Pr='Praisethesun:BAAALgAECgQJCQAAAA==.Prayxx:BAAALgAECgYJCQAAAA==.Pretzel:BAACLgAFFH8YAAIFAAgJqyQ+CAB8AgAFAAgJqyQ+CAB8AgAuAAQKfzQAAwUACQljJZ4EAIoDAAUACQljJZ4EAIoDACYAAQk5IcExAFYAAAAA.Proved:BAACLgAFFH8FAAIhAAMJBgo2LgBeAAAhAAMJBgo2LgBeAAAuAAQKf00AAiEACQmRHUEKAMMCACEACQmRHUEKAMMCAAAA.',
Ps='Psillycybin:BAAALgAECgcJDQABLgAECgkJQgAhAP0JAA==.',
Pu='Puddingface:BAAALgADCgkJCQABLgAECgEJAQAHAAAAAA==.Puggar:BAAALgADCgQJBgAAAA==.Pugnacious:BAAALgAECgEJAQAAAA==.Pulpeh:BAAALgAECgYJDQAAAA==.Pulpp:BAAALgAECgMJBQABLgAECgYJDQAHAAAAAA==.Pumpspotter:BAAALgAECgkJEgAAAA==.',
Qu='Quiescence:BAAALgADCgYJBgAAAA==.',
Ra='Rakkór:BAAALgAECgEJAgAAAA==.Ranas:BAAALgADCgIJAgAAAA==.Ranessandi:BAAALgAECgEJAQAAAA==.Ratlemebonez:BAAALgAECgEJAQAAAA==.Ravèn:BAAALgAECgcJEQAAAA==.Rayana:BAAALgADCgYJBgAAAA==.Razeal:BAAALgAECgkJDwAAAA==.',
Re='Regerax:BAABLgAFFH8PAAIRAAQJ/x/TFAB8AQARAAQJ/x/TFAB8AQABLgAFFAQJEgALAAUfAA==.Rene:BAEALgAECggJCgAAAA==.Rev:BAAALgADCgEJAQAAAA==.',
Rh='Rhysan:BAACLgAFFH8OAAIPAAQJaByPKQA/AQAPAAQJaByPKQA/AQAuAAQKfzsAAg8ACQm9F4k2ANYBAA8ACQm9F4k2ANYBAAAA.Rhyuk:BAAALgADCgQJBAAAAA==.',
Ri='Rimzak:BAAALgAECgYJCgABLgAECgkJFAARAIUUAA==.Ristria:BAAALgADCgYJEAABLgAECgcJIAALAAgSAA==.Rizy:BAABLgAECn8iAAIFAAkJpA/QTQDZAQAFAAkJpA/QTQDZAQAAAA==.',
Ro='Robonord:BAAALgAECgIJAgAAAA==.Rokki:BAAALgADCgIJAgAAAA==.',
Ru='Rude:BAAALgADCgcJCwAAAA==.',
Ry='Rynhart:BAAALgADCgUJBQAAAA==.Rynpry:BAAALgAECgMJAwAAAA==.Ryntard:BAAALgAECgYJBgAAAA==.Ryushi:BAACLgAFFH8VAAIEAAQJ4hTRRAAZAQAEAAQJ4hTRRAAZAQAuAAQKf0gAAgQACQnGICoaAHcCAAQACQnGICoaAHcCAAAA.',
Sa='Sacerdote:BAABLgAECn8UAAICAAYJPiF3TgCvAQACAAYJPiF3TgCvAQAAAA==.Sakari:BAAALgADCgcJEAAAAA==.Sandara:BAAALgADCgYJBgAAAA==.Sangre:BAAALgADCgIJAgABLgAECgMJBAAHAAAAAA==.Sarasara:BAAALgADCgUJBQAAAA==.Sathicus:BAAALgAECgMJAwAAAA==.',
Sc='Scoots:BAAALgAECgUJCAABLgAFFAQJFgAMAIshAA==.Scratster:BAAALgAECgcJCAAAAA==.',
Se='Sebnoth:BAABLgAECn81AAIFAAkJnyHIEwDRAgAFAAkJnyHIEwDRAgAAAA==.',
Sh='Shadowspark:BAABLgAECn8ZAAIWAAkJmyBnAAAAAwAWAAkJmyBnAAAAAwAAAA==.Shalashaska:BAAALgADCgEJAQAAAA==.Shamadams:BAAALgAECgEJAQAAAA==.Shamantastik:BAAALgAECgMJAwAAAA==.Shazzy:BAAALgAECgEJAQAAAA==.Shiden:BAAALgAECgYJDwAAAA==.Shift:BAAALgADCgkJCQAAAA==.Shiift:BAAALgADCgYJBwAAAA==.Shockblocked:BAAALgADCgQJBAAAAA==.',
Si='Sidepiece:BAAALgADCgcJCAAAAA==.Sillyderek:BAACLgAFFH8GAAIjAAIJSghXFQBQAAAjAAIJSghXFQBQAAAuAAQKfx0AAiMABwmnDfchAAUBACMABwmnDfchAAUBAAAA.Simpletom:BAAALgAECgEJAQAAAA==.',
Sl='Slashology:BAAALgAECgYJDAAAAA==.',
Sm='Smallpally:BAABLgAECn8UAAILAAcJBRV/fwBwAQALAAcJBRV/fwBwAQAAAA==.',
So='Soarsha:BAAALgAECgIJAgAAAA==.Solarida:BAABLgAECn8yAAILAAkJYhurBgAtAgALAAkJYhurBgAtAgAAAA==.',
Sr='Srsawyer:BAABLgAECn8bAAICAAgJSA/nYACnAQACAAgJSA/nYACnAQAAAA==.',
St='Staralfur:BAAALgADCgcJBwAAAA==.Stevokerjobs:BAABLgAECn8VAAQYAAYJNRn3GQA4AQAYAAQJBRv3GQA4AQAcAAYJaxJQIAArAQAGAAQJRBP8UADrAAAAAA==.Stormshäde:BAAALgAFFAEJBAAAAA==.Stratos:BAAALgADCgcJBwAAAA==.',
Su='Sumlkithot:BAAALgAECgUJCgAAAA==.Sunwa:BAACLgAFFH8SAAMLAAQJBR+eKQBlAQALAAQJBR+eKQBlAQAjAAIJvwX9EwAgAAAuAAQKfyYAAwsACQl2IVc6ABoCAAsACQl2IVc6ABoCACMABgnxCtIsALgAAAAA.',
['Sï']='Sïmba:BAAALgAECgMJCQAAAA==.',
Ta='Talyashamwow:BAAALgADCgYJBgAAAA==.',
Te='Terzhull:BAAALgADCgIJAgAAAA==.',
Th='Thepride:BAAALgAECggJDwAAAA==.Thespian:BAAALgAECgEJAgAAAA==.Thugrakotan:BAAALgAECgEJAQAAAA==.Thugrakotane:BAAALgAECgEJAQAAAA==.',
Ti='Timmytim:BAAALgAECgQJCAAAAA==.Tired:BAAALgAECgUJBgAAAA==.',
To='Tool:BAACLgAFFH8ZAAINAAgJHBvBAADdAgANAAgJHBvBAADdAgAuAAQKfyYAAg0ACQnrJGMCANgDAA0ACQnrJGMCANgDAAEuAAUUCQkvAAQAESUA.Tooms:BAAALgAECgcJBwAAAA==.Touchi:BAAALgAECggJDQABLgAECgkJKQAfABkcAA==.',
Tr='Troljin:BAAALgADCgEJAQAAAA==.',
Tu='Tuo:BAABLgAECn8pAAIfAAkJGRzwBQCNAgAfAAkJGRzwBQCNAgAAAA==.Turbid:BAABLgAECn9QAAMEAAkJ4xf6JwArAgAEAAkJ4xf6JwArAgAXAAkJDA1VAgB7AQAAAA==.',
Ty='Ty:BAAALgAECgUJDAAAAA==.Tytank:BAAALgADCgMJBAAAAA==.',
Uh='Uhavemyrice:BAAALgADCgIJAgAAAA==.',
Ve='Velkin:BAAALgAECgEJAQAAAA==.',
Vi='Vivia:BAAALgADCgQJBAAAAA==.Viviann:BAAALgADCgMJAwAAAA==.Vivians:BAAALgADCggJCgAAAA==.',
Vo='Voutecomer:BAAALgAECgcJCgAAAA==.',
Vy='Vyndictive:BAAALgAECgIJAgAAAA==.',
Wa='Walls:BAABLgAECn8YAAILAAkJNhg+MwAzAgALAAkJNhg+MwAzAgAAAA==.Warrach:BAAALgADCgQJBAAAAA==.',
We='Welchnut:BAAALgADCgEJAQAAAA==.Wennoe:BAAALgADCgIJAgAAAA==.Westirras:BAABLgAECn8oAAMLAAkJ2xERHwDqAAALAAkJ2xERHwDqAAAeAAIJTQiafwBNAAAAAA==.',
Wo='Wobblepox:BAAALgAECgkJCAAAAA==.',
Ya='Yarrow:BAAALgAECgkJEQAAAA==.',
Yo='Yogurt:BAABLgAECn8UAAInAAcJdg90KgArAQAnAAcJdg90KgArAQABLgAECgkJLgALAMcXAA==.',
Yu='Yusuke:BAABLgAECn8WAAMkAAcJfhF7KwBcAQAkAAcJfhF7KwBcAQATAAYJPQlyQADgAAABLgAECgkJKQAQAE8bAA==.',
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
