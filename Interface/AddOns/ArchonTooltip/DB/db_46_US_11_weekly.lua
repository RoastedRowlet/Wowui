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

local lookup = {'Priest-Discipline','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Augmentation','Paladin-Retribution','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Unknown-Unknown','Priest-Shadow','Monk-Mistweaver','Rogue-Subtlety','Hunter-Marksmanship','DemonHunter-Vengeance','Evoker-Preservation','Warrior-Fury','Hunter-BeastMastery','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Druid-Feral','Rogue-Outlaw','Priest-Holy','Mage-Arcane','Warlock-Destruction','Paladin-Protection','Monk-Brewmaster','Rogue-Assassination','DeathKnight-Frost',}
local provider = {region='US',realm='Andorhal',name='US',type='weekly',zone=46,date='2026-06-13',data={Ad='Adelyne:BAAALgAECgQJAwABLgAFFAUJEgABABkcAA==.Adorablepine:BAABLgAECn8ZAAMCAAcJuAMmwwDGAAACAAcJrAMmwwDGAAADAAEJqgMkRAAgAAAAAA==.',
Ag='Agaze:BAACLgAFFH8ZAAIEAAcJESDVGgDPAQAEAAcJESDVGgDPAQAuAAQKfxYAAgQACAkTIgAZAL8CAAQACAkTIgAZAL8CAAAA.',
Ai='Aiedel:BAAALgAECgUJCQAAAA==.',
Al='Allesa:BAAALgAECgEJAQAAAA==.',
Ao='Aoise:BAAALgAECgkJCAAAAA==.',
Ap='Applejuuice:BAABLgAFFH8HAAIFAAMJexZ4lQDfAAAFAAMJexZ4lQDfAAABLgAFFAQJBwAGAMAKAA==.',
Ar='Aratre:BAAALgADCgEJAQAAAA==.Archblade:BAAALgAECgQJBwAAAA==.Arelith:BAAALgAECgMJBwAAAA==.Ariggs:BAAALgAECgEJAQAAAA==.Ariosx:BAAALgAFFAIJBAABLgAFFAQJDgAHAIYdAA==.Arlen:BAABLgAECn8pAAIHAAkJtBeEMQA4AgAHAAkJtBeEMQA4AgAAAA==.Arma:BAABLgAECn8cAAIIAAgJjiNGBQAwAwAIAAgJjiNGBQAwAwABLgAFFAYJGQAJALMgAA==.Armadro:BAABLgAFFH8ZAAIJAAYJsyASJgDgAQAJAAYJsyASJgDgAQAAAA==.',
Au='Aurky:BAAALgAECgEJAwAAAA==.',
Ba='Bald:BAAALgADCgYJBgAAAA==.Balob:BAACLgAFFH8cAAMKAAgJOxkBDwCtAQAKAAcJYRkBDwCtAQALAAEJvwKiewA9AAAuAAQKfyUAAgoACAlqJXoEAFQDAAoACAlqJXoEAFQDAAAA.Bandar:BAAALgADCgcJBwAAAA==.',
Be='Beardlylegal:BAAALgAECgEJAQAAAA==.Behodius:BAAALgAECgMJBAAAAA==.Bellafists:BAAALgAECgYJBgAAAA==.Benchwong:BAAALgAFFAEJAQABLgAFFAgJHAAKADsZAA==.',
Bl='Blacksteve:BAAALgAECgIJAgAAAA==.Bloodngore:BAABLgAECn8nAAIMAAkJTxt4CgBoAgAMAAkJTxt4CgBoAgAAAA==.Blumoon:BAAALgAECgEJAQAAAA==.',
Bm='Bmxdh:BAAALgAECgYJDwAAAA==.',
Bo='Bonecollectr:BAAALgAECggJDQABLgAECggJDQANAAAAAA==.',
Br='Broku:BAAALgAECggJDAABLgAECgkJLgAHAMcXAA==.Brudah:BAAALgAECgEJAQAAAA==.Brutus:BAAALgAFFAMJBAAAAA==.',
Bu='Bubblelove:BAABLgAECn8kAAIOAAkJTA2eJACjAQAOAAkJTA2eJACjAQAAAA==.Bubbly:BAABLgAECn8uAAIHAAkJxxd5QQAAAgAHAAkJxxd5QQAAAgAAAA==.Butes:BAAALgAECgkJDwAAAA==.',
Ca='Caelum:BAAALgAECgMJAwAAAA==.Callmepappy:BAAALgADCgUJBQAAAA==.Canníbal:BAAALgAECggJDwAAAA==.',
Ce='Censored:BAAALgADCgIJAgAAAA==.',
Ch='Chopsy:BAACLgAFFH8VAAIIAAQJaCEuCgB1AQAIAAQJaCEuCgB1AQAuAAQKf1oAAwgACQlHJQACAFEDAAgACQlHJQACAFEDAA8AAgnEC91eAFIAAAAA.Chris:BAAALgAECgUJDQAAAA==.Chucklez:BAAALgAFFAIJBAAAAA==.Chulobulo:BAABLgAECn8bAAIQAAkJxxU1FQDzAQAQAAkJxxU1FQDzAQAAAA==.Chulosdck:BAAALgAECgYJDwABLgAECgkJGwAQAMcVAA==.',
Ci='Cinnabons:BAAALgAFFAEJAQABLgAFFAQJBwAGAMAKAA==.',
Cl='Cleopatrick:BAAALgADCgkJEAAAAA==.',
Co='Cobgoblin:BAAALgAECgEJAQAAAA==.Codingsocks:BAAALgADCgEJAgAAAA==.',
Cr='Crekton:BAAALgAECgMJAwAAAA==.Cronnos:BAAALgAECgYJBwAAAA==.',
Cu='Cudlemonster:BAABLgAECn89AAIBAAkJbAwuJACrAQABAAkJbAwuJACrAQAAAA==.Cursed:BAACLgAFFH8KAAIDAAQJ+BNhBABCAQADAAQJ+BNhBABCAQAuAAQKf0UAAwMACQmPITYBAPYCAAMACQmPITYBAPYCAAIAAwllD3jWAKgAAAAA.',
Da='Dabz:BAABLgAECn8XAAICAAgJhhoLNAAHAgACAAgJhhoLNAAHAgAAAA==.Daddyslaps:BAAALgAECgUJBQAAAA==.Daghma:BAAALgAECgYJBgAAAA==.Danyel:BAAALgADCgYJBwAAAA==.Darmok:BAABLgAECn81AAMLAAkJ3yPYBABkAwALAAkJ3yPYBABkAwAKAAEJbBpFmABBAAAAAA==.Darzamat:BAAALgADCgEJAQAAAA==.Dawtie:BAAALgAECgQJBQABLgAECggJDQANAAAAAA==.',
De='Demonbubble:BAACLgAFFH8YAAIEAAcJKw+EIwCYAQAEAAcJKw+EIwCYAQAuAAQKfy0AAgQACQm8FgguAAwCAAQACQm8FgguAAwCAAAA.Dezric:BAAALgADCgYJDAABLgAECgYJBgANAAAAAA==.Dezruf:BAAALgAECgYJBgAAAA==.',
Do='Dotomic:BAABLgAFFH8LAAICAAUJEx6TMQB3AQACAAUJEx6TMQB3AQABLgAFFAgJIAARAIgfAA==.',
Dr='Drejan:BAAALgAECgcJCQAAAA==.Drfe:BAAALgADCgYJBgAAAA==.Drifthook:BAAALgAECgkJCQAAAA==.Drowarchon:BAAALgADCgIJAgABLgAECgQJBAANAAAAAA==.Drownix:BAAALgAECgQJBAAAAA==.Drowzy:BAAALgADCgYJBAABLgAECgQJBAANAAAAAA==.',
['Dä']='Dämonjäger:BAAALgADCggJCAAAAA==.',
Eb='Ebon:BAAALgADCgMJAwAAAA==.',
Ec='Ecaed:BAABLgAECn8bAAISAAkJ1gZHEwAZAQASAAkJ1gZHEwAZAQAAAA==.',
Ei='Eisenhørn:BAAALgADCgYJDgAAAA==.',
El='Elektriss:BAAALgAECgQJBAAAAA==.Elnaris:BAABLgAECn8iAAIHAAgJlguahQBhAQAHAAgJlguahQBhAQAAAA==.Elohime:BAAALgADCgYJCAAAAA==.',
Eo='Eon:BAAALgAECgIJCAAAAA==.',
Er='Erikkak:BAAALgADCgQJBAAAAA==.Eriu:BAAALgAECgEJAQABLgAFFAQJDgAHAIYdAA==.Erõs:BAAALgAECgYJCwABLgAECgYJFQATADUZAA==.',
Fe='Fenixbinkle:BAAALgAECgQJBAAAAA==.',
Fi='Fiero:BAAALgAECggJDQAAAA==.Fire:BAAALgAECgUJBQABLgAFFAYJFQAGAGUbAA==.',
Fr='Fragga:BAABLgAECn8cAAIUAAYJaBboQQA8AQAUAAYJaBboQQA8AQAAAA==.',
Fu='Fullflavor:BAAALgADCgIJAgAAAA==.',
['Fü']='Füran:BAAALgADCgIJAgAAAA==.',
Ga='Ganryu:BAAALgADCgYJCgAAAA==.',
Gb='Gboybalili:BAAALgADCgcJDAAAAA==.',
Gi='Gitzi:BAACLgAFFH8NAAIVAAQJlQspSAAVAQAVAAQJlQspSAAVAQAuAAQKf0sAAhUACQlZHTEcAF0CABUACQlZHTEcAF0CAAAA.',
Gl='Glaciea:BAAALgADCgMJAwABLgAECggJHgAWAKciAA==.',
Gr='Grayl:BAAALgAECgkJCQAAAA==.Greenrage:BAAALgADCgQJBAAAAA==.Griever:BAAALgAECgYJCQAAAA==.Grizzly:BAAALgAECgEJAQAAAA==.Groovexgroov:BAABLgAECn8dAAIOAAkJOxjKEABSAgAOAAkJOxjKEABSAgAAAA==.',
Ha='Harlowe:BAAALgADCgYJBQAAAA==.',
He='Healrog:BAAALgAECgYJBgAAAA==.Hellraiser:BAAALgAECgQJBQAAAA==.',
Hi='Highfive:BAAALgADCgIJAgAAAA==.',
Ho='Holyfiero:BAAALgAECgQJBAABLgAECggJDQANAAAAAA==.Holynight:BAAALgADCgMJBAABLgAECgEJAQANAAAAAA==.Hordend:BAAALgAECgUJEAAAAA==.Hozru:BAAALgADCgEJAQAAAA==.',
Hu='Hulkfists:BAABLgAECn8UAAMKAAYJownMSgAcAQAKAAYJownMSgAcAQAXAAYJ3gLVHgDiAAAAAA==.',
Hy='Hydration:BAAALgADCgMJAwAAAA==.',
['Hâ']='Hâruka:BAAALgAECgcJBgAAAA==.',
Im='Imcepsy:BAABLgAECn81AAIBAAkJ7BnGCwCwAgABAAkJ7BnGCwCwAgAAAA==.',
Io='Iownzuu:BAAALgADCgMJAwAAAA==.',
Is='Istari:BAAALgAECgIJAgAAAA==.Istark:BAAALgAECgMJAwAAAA==.',
Ja='Jayjay:BAACLgAFFH8KAAIJAAQJ7RTPWgA0AQAJAAQJ7RTPWgA0AQAuAAQKfyIAAgkACQmxHIwlAIMCAAkACQmxHIwlAIMCAAAA.',
Je='Jethroy:BAABLgAECn8VAAIYAAgJbREfNwBvAQAYAAgJbREfNwBvAQAAAA==.',
Jf='Jfkwspvpfldg:BAAALgAECgYJBgAAAA==.',
Ji='Jimmie:BAABLgAECn8aAAIQAAgJuiAkEQCYAgAQAAgJuiAkEQCYAgAAAA==.',
Jo='Johnparstina:BAAALgAECgYJDgAAAA==.Jolty:BAACLgAFFH8KAAIXAAQJNx8+BgBUAQAXAAQJNx8+BgBUAQAuAAQKfyEAAhcACQmrIxECAAYDABcACQmrIxECAAYDAAAA.',
Jr='Jrbacnchee:BAAALgAECgEJAQAAAA==.Jrbcncheze:BAAALgAECggJEgAAAA==.',
Ka='Kainicus:BAACLgAFFH8TAAISAAQJUROMBQAJAQASAAQJUROMBQAJAQAuAAQKf1kAAhIACQnBGX4FAEsCABIACQnBGX4FAEsCAAAA.Kainigal:BAAALgADCgYJCwAAAA==.Kainisham:BAAALgADCgcJBwAAAA==.',
Ke='Kelador:BAABLgAECn8mAAIZAAkJQgqxGQA6AQAZAAkJQgqxGQA6AQAAAA==.Keoni:BAAALgAECgEJAQAAAA==.Kerrykoppene:BAAALgAECgIJAgAAAA==.',
Kh='Khappucino:BAAALgAECgcJCQAAAA==.Kharibou:BAAALgAECgQJBAAAAA==.Khellendros:BAAALgADCgYJCgAAAA==.Khrism:BAAALgADCgQJBAAAAA==.',
Ki='Kibbi:BAAALgADCgcJBwAAAA==.Kitsyune:BAABLgAECn8fAAIaAAkJ7BdpBQAOAgAaAAkJ7BdpBQAOAgAAAA==.',
Kj='Kjartan:BAAALgAECgUJBgAAAA==.',
Kl='Kløey:BAACLgAFFH8GAAIQAAMJ5gsrKQDbAAAQAAMJ5gsrKQDbAAAuAAQKfxQAAhAABgnZFMsuAI0BABAABgnZFMsuAI0BAAAA.',
La='Laethys:BAAALgADCggJCAABLgAECgkJIQAJAEIeAA==.',
Li='Lithini:BAAALgAECgQJCQAAAA==.',
Lo='Lowtech:BAAALgAECgMJAwAAAA==.',
Lu='Luminusrayne:BAACLgAFFH8PAAIbAAMJYQUIJwCEAAAbAAMJYQUIJwCEAAAuAAQKf0YAAwEACQm8DQMiAIQBAAEACAn8CgMiAIQBABsACQk+DMoxAD8BAAAA.Lussypipz:BAAALgAFFAMJBAABLgAFFAMJBgAQAOYLAA==.',
Ma='Mahwe:BAAALgAECggJDgAAAA==.Manafest:BAAALgAECgMJCgAAAA==.Maros:BAABLgAECn8kAAMJAAkJWhbfOAAyAgAJAAkJWhbfOAAyAgAcAAEJJA/uFQA2AAAAAA==.',
Me='Meheret:BAACLgAFFH8GAAIJAAMJwAA0pgCIAAAJAAMJwAA0pgCIAAAuAAQKf0EAAgkACQlmBkaqACcBAAkACQlmBkaqACcBAAAA.Melissenia:BAAALgAECgQJBAAAAA==.Menious:BAAALgAECgEJAQAAAA==.Mepha:BAAALgAECggJDwAAAA==.',
Mi='Mint:BAABLgAECn8hAAIJAAkJQh5dIwDlAgAJAAkJQh5dIwDlAgAAAA==.',
Mo='Mokth:BAAALgADCgMJAwAAAA==.Mom:BAAALgAECgIJAgAAAA==.Mooby:BAABLgAECn8XAAIQAAgJjRocGABHAgAQAAgJjRocGABHAgAAAA==.Moomu:BAAALgAECgUJBQAAAA==.Moonfury:BAAALgAECgEJAQAAAA==.Moonleigh:BAAALgADCgMJBAAAAA==.Morganthe:BAAALgAECgIJAwAAAA==.Moria:BAAALgAECgUJBgAAAA==.',
Mu='Munt:BAAALgAECgQJBAABLgAECgkJIQAJAEIeAA==.',
My='Mypriiest:BAAALgAECgQJBAAAAA==.Myroguëë:BAAALgADCgUJBQAAAA==.Mystx:BAABLgAFFH8JAAIJAAIJ/BLQmACbAAAJAAIJ/BLQmACbAAABLgAFFAQJDgAHAIYdAA==.Mythx:BAACLgAFFH8LAAIUAAQJgh68FQBaAQAUAAQJgh68FQBaAQAuAAQKfzcAAhQACQmZJhwBAHYDABQACQmZJhwBAHYDAAEuAAUUBAkOAAcAhh0A.Mywarr:BAAALgADCgMJAwAAAA==.',
Na='Naturemage:BAAALgAECgUJBwAAAA==.Natâsi:BAACLgAFFH8HAAIYAAMJ2g4gMwCeAAAYAAMJ2g4gMwCeAAAuAAQKfy8AAhgACQmkGbsYAD8CABgACQmkGbsYAD8CAAAA.',
Ne='Nerazul:BAABLgAECn8VAAQDAAYJph/GBQAKAgADAAYJph/GBQAKAgACAAMJ3wqC4wCTAAAdAAEJ/AgReAAsAAAAAA==.Netharec:BAAALgADCgEJAQABLgAFFAYJFwAOAPgcAA==.Nevai:BAABLgAECn8YAAIYAAkJCxKRIQD1AQAYAAkJCxKRIQD1AQAAAA==.',
Ni='Nielas:BAABLgAECn8UAAIFAAgJ7yBdKABeAgAFAAgJ7yBdKABeAgAAAA==.Nihilus:BAACLgAFFH8SAAIFAAYJJxuTCACMAQAFAAYJJxuTCACMAQAuAAQKfxUAAgUABwkWJLkvAHkCAAUABwkWJLkvAHkCAAAA.Nilari:BAABLgAECn8UAAIeAAYJIQnULwCkAAAeAAYJIQnULwCkAAAAAA==.Nine:BAAALgADCgYJBgABLgAFFAQJFQAIAGghAA==.',
No='Noctazari:BAAALgADCgUJBQAAAA==.Noctium:BAABLgAECn8eAAIWAAgJpyLfAgB8AgAWAAgJpyLfAgB8AgAAAA==.Nostrildamus:BAAALgAECgYJEQABLgAECgkJGAAHADYYAA==.',
Nz='Nzoth:BAAALgADCgYJBgAAAA==.',
Of='Officimeeg:BAAALgAECgEJAQAAAA==.',
Ow='Owlaf:BAAALgAECgIJAgABLgAFFAYJHgABAB8aAA==.Owlchi:BAACLgAFFH8FAAIPAAQJ8wzrMwDQAAAPAAQJ8wzrMwDQAAAuAAQKfxUAAw8ABwktHR4ZAEkCAA8ABwktHR4ZAEkCAB8ABQmRDypMAMsAAAEuAAUUBgkeAAEAHxoA.Owls:BAACLgAFFH8eAAIBAAYJHxppEwDkAQABAAYJHxppEwDkAQAuAAQKfzkAAwEACQkWI/YGAA0DAAEACQmGIPYGAA0DABsABwkbJPcKAJ8CAAEuAAUUBgkeAAEAHxoA.',
Pa='Pallywhacker:BAAALgAECgUJBQAAAA==.Panconcaca:BAAALgAFFAcJAwAAAA==.Pantsokay:BAAALgADCgEJAQAAAA==.',
Pe='Peach:BAABLgAECn8cAAMgAAgJ4Q3ECwBwAQAgAAgJ4Q3ECwBwAQAQAAYJUAGeSwDNAAAAAA==.Peaches:BAAALgAECgEJAgAAAA==.Petsmart:BAAALgAECgQJBQAAAA==.',
Pi='Pinesol:BAAALgADCgcJBwAAAA==.',
Po='Potatoeshot:BAAALgAECgQJBQAAAA==.',
Pr='Praisethesun:BAAALgAECgQJCQAAAA==.Prayxx:BAAALgAECgYJCQAAAA==.Pretzel:BAACLgAFFH8SAAIFAAUJKSVqLQCnAQAFAAUJKSVqLQCnAQAuAAQKfzQAAwUACQljJZ4EAIoDAAUACQljJZ4EAIoDACEAAQk5IYAwAFYAAAAA.Proved:BAABLgAECn9NAAIbAAkJkR0HCgDEAgAbAAkJkR0HCgDEAgAAAA==.',
Ps='Psillycybin:BAAALgAECgcJDQABLgAECgkJQgAbAP0JAA==.',
Pu='Puddingface:BAAALgADCgkJCQAAAA==.Puggar:BAAALgADCgQJBgAAAA==.Pulpp:BAAALgAECgIJAgAAAA==.Pumpspotter:BAAALgAECgkJEgAAAA==.',
Qu='Quiescence:BAAALgADCgYJBgAAAA==.',
Ra='Rakkór:BAAALgAECgEJAgAAAA==.Ranas:BAAALgADCgIJAgAAAA==.Ranessandi:BAAALgAECgEJAQAAAA==.Ratlemebonez:BAAALgAECgEJAQAAAA==.Ravèn:BAAALgAECgcJEQAAAA==.Rayana:BAAALgADCgYJBgAAAA==.Razeal:BAAALgAECgYJDwAAAA==.',
Re='Regerax:BAAALgAFFAIJAgABLgAFFAQJDgAHAIYdAA==.Rene:BAEALgAECggJCgAAAA==.Rev:BAAALgADCgEJAQAAAA==.',
Rh='Rhysan:BAACLgAFFH8NAAILAAQJUBuUJwBAAQALAAQJUBuUJwBAAQAuAAQKfzsAAgsACQm9F6M1ANYBAAsACQm9F6M1ANYBAAAA.Rhyuk:BAAALgADCgQJBAAAAA==.',
Ri='Ristria:BAAALgADCgYJEAABLgAECgYJHwAHADgSAA==.Rizy:BAABLgAECn8iAAIFAAkJpA8STADbAQAFAAkJpA8STADbAQAAAA==.',
Ro='Robonord:BAAALgAECgIJAgAAAA==.Rokki:BAAALgADCgIJAgAAAA==.',
Ru='Rude:BAAALgADCgcJCwAAAA==.',
Ry='Rynhart:BAAALgADCgUJBQAAAA==.Ryntard:BAAALgAECgYJBgAAAA==.Ryushi:BAACLgAFFH8UAAIEAAQJ4hQ8QgAaAQAEAAQJ4hQ8QgAaAQAuAAQKf0gAAgQACQnGILcZAHcCAAQACQnGILcZAHcCAAAA.',
Sa='Sacerdote:BAABLgAECn8UAAICAAYJPiG+TQCwAQACAAYJPiG+TQCwAQAAAA==.Sakari:BAAALgADCgcJEAAAAA==.Sandara:BAAALgADCgYJBgAAAA==.Sangre:BAAALgADCgIJAgABLgAECgMJBAANAAAAAA==.Sarasara:BAAALgADCgUJBQAAAA==.Sathicus:BAAALgAECgMJAwAAAA==.',
Sc='Scoots:BAAALgAECgUJCAABLgAFFAQJFQAIAGghAA==.Scratster:BAAALgAECgcJCAAAAA==.',
Se='Sebnoth:BAABLgAECn8zAAIFAAkJtCBcEwDSAgAFAAkJtCBcEwDSAgAAAA==.',
Sh='Shadowspark:BAAALgAECgYJCAAAAA==.Shalashaska:BAAALgADCgEJAQAAAA==.Shamantastik:BAAALgAECgMJAwAAAA==.Shiden:BAAALgAECgYJDwAAAA==.Shift:BAAALgADCgkJCQAAAA==.Shiift:BAAALgADCgYJBwAAAA==.Shockblocked:BAAALgADCgQJBAAAAA==.',
Si='Sideburn:BAAALgADCgUJBQAAAA==.Sidepiece:BAAALgADCgcJCAAAAA==.Sillyderek:BAACLgAFFH8GAAIeAAIJSgilFABQAAAeAAIJSgilFABQAAAuAAQKfx0AAh4ABwmnDYYhAAUBAB4ABwmnDYYhAAUBAAAA.',
Sl='Slashology:BAAALgAECgYJDAAAAA==.',
Sm='Smallpally:BAABLgAECn8UAAIHAAcJBRUffQBxAQAHAAcJBRUffQBxAQAAAA==.',
So='Soarsha:BAAALgAECgIJAgAAAA==.Solarida:BAABLgAECn8lAAIHAAgJShqsQwD5AQAHAAgJShqsQwD5AQAAAA==.',
Sr='Srsawyer:BAABLgAECn8bAAICAAgJSA/nYACnAQACAAgJSA/nYACnAQAAAA==.',
St='Staralfur:BAAALgADCgcJBwAAAA==.Stevokerjobs:BAABLgAECn8VAAQTAAYJNRmzGQA4AQATAAQJBRuzGQA4AQAWAAYJaxJQIAArAQAGAAQJRBPCTwDrAAAAAA==.Stormshäde:BAAALgAFFAEJAgAAAA==.Stratos:BAAALgADCgcJBwAAAA==.',
Su='Sumlkithot:BAAALgAECgQJAQAAAA==.Sunwa:BAACLgAFFH8OAAMHAAQJhh3lJgBnAQAHAAQJhh3lJgBnAQAeAAEJjwPaGwAgAAAuAAQKfyEAAwcACAlZIFU5ABsCAAcACAlZIFU5ABsCAB4ABgnxCjEsALgAAAAA.',
['Sï']='Sïmba:BAAALgAECgMJCQAAAA==.',
Ta='Talyashamwow:BAAALgADCgYJBgAAAA==.',
Te='Terzhull:BAAALgADCgIJAgAAAA==.',
Th='Thepride:BAAALgAECggJDwAAAA==.',
Ti='Timmytim:BAAALgAECgQJCAAAAA==.Tired:BAAALgAECgUJBgAAAA==.',
To='Tool:BAACLgAFFH8ZAAIJAAgJHBvBAADdAgAJAAgJHBvBAADdAgAuAAQKfyYAAgkACQnrJGMCANgDAAkACQnrJGMCANgDAAEuAAUUCQkvAAQAESUA.Touchi:BAAALgAECggJDAABLgAECgkJKQAZABkcAA==.',
Tr='Troljin:BAAALgADCgEJAQAAAA==.',
Tu='Tuo:BAABLgAECn8pAAIZAAkJGRzNBQCNAgAZAAkJGRzNBQCNAgAAAA==.Turbid:BAABLgAECn87AAIEAAkJgBWlNQDsAQAEAAkJgBWlNQDsAQAAAA==.',
Ty='Ty:BAAALgAECgUJDAAAAA==.Tytank:BAAALgADCgMJBAAAAA==.',
Uh='Uhavemyrice:BAAALgADCgIJAgAAAA==.',
Ve='Velkin:BAAALgAECgEJAQAAAA==.',
Vi='Vivia:BAAALgADCgQJBAAAAA==.Viviann:BAAALgADCgMJAwAAAA==.Vivians:BAAALgADCggJCgAAAA==.',
Vo='Voutecomer:BAAALgADCggJDAAAAA==.',
Wa='Walls:BAABLgAECn8YAAIHAAkJNhhWMgA0AgAHAAkJNhhWMgA0AgAAAA==.Warrach:BAAALgADCgQJBAAAAA==.',
We='Welchnut:BAAALgADCgEJAQAAAA==.Wennoe:BAAALgADCgIJAgAAAA==.Westirras:BAABLgAECn8iAAMHAAgJHRCGdQCAAQAHAAgJHRCGdQCAAQAYAAIJTQg/fgBNAAAAAA==.',
Wo='Wobblepox:BAAALgAECgkJCAAAAA==.',
Ya='Yarrow:BAAALgAECgMJBgAAAA==.',
Yo='Yogurt:BAAALgAECgcJEgABLgAECgkJLgAHAMcXAA==.',
Yu='Yusuke:BAABLgAECn8WAAMfAAcJfhH5KgBdAQAfAAcJfhH5KgBdAQAPAAYJPQlyQADgAAABLgAECgkJJwAMAE8bAA==.',
Za='Zabuzabuza:BAAALgAECgIJAgABLgAECgYJFQATADUZAA==.Zazabandit:BAAALgADCgUJBQAAAA==.',
Zo='Zolleta:BAAALgAECgQJBAAAAA==.',
Zu='Zuesulty:BAAALgADCgYJBgAAAA==.Zunden:BAABLgAECn8YAAMTAAgJWg8dEwCUAQATAAgJWg8dEwCUAQAGAAEJAABMpwAAAAAAAA==.',
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
