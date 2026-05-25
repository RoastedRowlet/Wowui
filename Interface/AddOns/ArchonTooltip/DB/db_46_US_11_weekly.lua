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

local lookup = {'Priest-Discipline','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Preservation','Warrior-Fury','Paladin-Retribution','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Priest-Shadow','Monk-Mistweaver','Rogue-Subtlety','Unknown-Unknown','Hunter-Marksmanship','DemonHunter-Vengeance','Evoker-Devastation','Evoker-Augmentation','Hunter-BeastMastery','Shaman-Enhancement','Paladin-Holy','Druid-Feral','Rogue-Outlaw','Priest-Holy','Mage-Arcane','Warlock-Destruction','Paladin-Protection','Rogue-Assassination','DeathKnight-Frost','Monk-Brewmaster',}
local provider = {region='US',realm='Andorhal',name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Adelyne:BAAALgAECgQJAwABLgAFFAUJDgABAG0SAA==.Adorablepine:BAABLgAECn8ZAAMCAAcJuANzrQDQAAACAAcJrANzrQDQAAADAAEJqgMANQAgAAAAAA==.',
Ag='Agaze:BAACLgAFFH8YAAIEAAcJESA1DAD0AQAEAAcJESA1DAD0AQAuAAQKfxYAAgQACAkTIgAZAL8CAAQACAkTIgAZAL8CAAAA.',
Ai='Aiedel:BAAALgAECgUJCQAAAA==.',
Al='Allesa:BAAALgAECgEJAQAAAA==.',
Ao='Aoise:BAAALgAECgkJCAAAAA==.',
Ap='Applejuuice:BAABLgAFFH8HAAIFAAMJexbLbgDtAAAFAAMJexbLbgDtAAABLgAECggJFwAGAMcSAA==.',
Ar='Archblade:BAAALgAECgMJAwAAAA==.Arelith:BAAALgAECgMJBwAAAA==.Ariosx:BAAALgADCgMJAwABLgAFFAMJCAAHABMeAA==.Arlen:BAABLgAECn8hAAIIAAgJYRWvSwDFAQAIAAgJYRWvSwDFAQAAAA==.Arma:BAABLgAECn8cAAIJAAgJjiNGBQAwAwAJAAgJjiNGBQAwAwAAAA==.Armadro:BAABLgAFFH8RAAIKAAUJ9Bz/LQBsAQAKAAUJ9Bz/LQBsAQAAAA==.',
Au='Aurky:BAAALgAECgEJAwAAAA==.',
Ba='Bald:BAAALgADCgYJBgAAAA==.Balob:BAACLgAFFH8ZAAMLAAcJoRu7CwCNAQALAAYJSRy7CwCNAQAMAAEJvwJ/YABBAAAuAAQKfyUAAgsACAlqJXoEAFQDAAsACAlqJXoEAFQDAAAA.Bandar:BAAALgADCgcJBwAAAA==.',
Be='Behodius:BAAALgADCgMJAwAAAA==.Bellafists:BAAALgAECgYJBgAAAA==.',
Bl='Blacksteve:BAAALgAECgIJAgAAAA==.Bloodngore:BAABLgAECn8cAAINAAgJVBq6DAAQAgANAAgJVBq6DAAQAgAAAA==.',
Bm='Bmxdh:BAAALgAECgYJDwAAAA==.',
Br='Broku:BAAALgAECgYJCAABLgAECgkJLgAIAMcXAA==.Brudah:BAAALgAECgEJAQAAAA==.Brutus:BAAALgAFFAMJAwAAAA==.',
Bu='Bubblelove:BAABLgAECn8jAAIOAAkJHQ1NHQCzAQAOAAkJHQ1NHQCzAQAAAA==.Bubbly:BAABLgAECn8uAAIIAAkJxxfMMQAYAgAIAAkJxxfMMQAYAgAAAA==.Butes:BAAALgAECggJCAAAAA==.',
Ca='Caelum:BAAALgAECgMJAwAAAA==.Callmepappy:BAAALgADCgUJBQAAAA==.Canníbal:BAAALgAECggJDwAAAA==.',
Ce='Censored:BAAALgADCgIJAgAAAA==.',
Ch='Chopsy:BAACLgAFFH8OAAIJAAQJaCGlBQCLAQAJAAQJaCGlBQCLAQAuAAQKf1gAAwkACQkeJZYBAFEDAAkACQkeJZYBAFEDAA8AAgnEC91eAFIAAAAA.Chris:BAAALgAECgUJCwAAAA==.Chucklez:BAAALgAFFAIJAgAAAA==.Chulobulo:BAABLgAECn8bAAIQAAkJxxVSEAAGAgAQAAkJxxVSEAAGAgAAAA==.Chulosdck:BAAALgAECgUJDAABLgAECgkJGwAQAMcVAA==.',
Ci='Cinnabons:BAAALgAFFAEJAQABLgAECggJFwAGAMcSAA==.',
Cl='Cleopatrick:BAAALgADCgkJEAAAAA==.',
Co='Cobgoblin:BAAALgAECgEJAQAAAA==.Codingsocks:BAAALgADCgEJAgAAAA==.',
Cr='Crekton:BAAALgAECgMJAwAAAA==.Cronnos:BAAALgAECgYJBwAAAA==.',
Cu='Cudlemonster:BAABLgAECn80AAIBAAkJMwwyHQC1AQABAAkJMwwyHQC1AQAAAA==.Cursed:BAABLgAECn82AAMDAAkJlCB6AQC9AgADAAkJlCB6AQC9AgACAAIJlwsg5gBnAAAAAA==.',
Da='Dabz:BAABLgAECn8XAAICAAgJhhq2KwASAgACAAgJhhq2KwASAgAAAA==.Daddyslaps:BAAALgAECgUJBQAAAA==.Danyel:BAAALgADCgYJBwAAAA==.Darmok:BAABLgAECn81AAMMAAkJ3yMJAwBuAwAMAAkJ3yMJAwBuAwALAAEJbBo2fgBEAAAAAA==.Darzamat:BAAALgADCgEJAQAAAA==.Dawtie:BAAALgAECgQJBQAAAA==.',
De='Demonbubble:BAACLgAFFH8UAAIEAAUJkQ+bNgAaAQAEAAUJkQ+bNgAaAQAuAAQKfy0AAgQACQm8FmwlABoCAAQACQm8FmwlABoCAAAA.Dezric:BAAALgADCgYJDAABLgAECgYJBgARAAAAAA==.Dezruf:BAAALgAECgYJBgAAAA==.',
Do='Dotomic:BAAALgAFFAEJAgABLgAFFAgJGgASADIfAA==.',
Dr='Drejan:BAAALgAECgcJBwAAAA==.Drfe:BAAALgADCgYJBgAAAA==.Drowarchon:BAAALgADCgIJAgABLgAECgQJBAARAAAAAA==.Drownix:BAAALgAECgQJBAAAAA==.Drowzy:BAAALgADCgQJBAABLgAECgQJBAARAAAAAA==.',
['Dä']='Dämonjäger:BAAALgADCggJCAAAAA==.',
Eb='Ebon:BAAALgADCgMJAwAAAA==.',
Ec='Ecaed:BAABLgAECn8bAAITAAkJ1gaDDwAqAQATAAkJ1gaDDwAqAQAAAA==.',
Ei='Eisenhørn:BAAALgADCgYJDAAAAA==.',
El='Elektriss:BAAALgAECgQJBAAAAA==.Elnaris:BAABLgAECn8ZAAIIAAcJlQarsAD8AAAIAAcJlQarsAD8AAAAAA==.Elohime:BAAALgADCgYJCAAAAA==.',
Eo='Eon:BAAALgAECgIJBwAAAA==.',
Er='Erikkak:BAAALgADCgQJBAAAAA==.Erõs:BAAALgAECgYJCwABLgAECgYJFAAUAJUVAA==.',
Fi='Fiero:BAAALgAECgEJAQABLgAECgQJBQARAAAAAA==.Fire:BAAALgAECgUJBQABLgAFFAYJFQAVAGUbAA==.',
Fr='Fragga:BAABLgAECn8aAAIHAAYJlxVxOgA2AQAHAAYJlxVxOgA2AQAAAA==.',
Fu='Fullflavor:BAAALgADCgIJAgAAAA==.',
['Fü']='Füran:BAAALgADCgIJAgAAAA==.',
Ga='Ganryu:BAAALgADCgYJCgAAAA==.',
Gb='Gboybalili:BAAALgADCgcJDAAAAA==.',
Gi='Gitzi:BAACLgAFFH8GAAIWAAQJQAurLwAiAQAWAAQJQAurLwAiAQAuAAQKf0kAAhYACQm6GzEcAF0CABYACQm6GzEcAF0CAAAA.',
Gl='Glaciea:BAAALgADCgMJAwABLgAECggJHgAUAKciAA==.',
Gr='Grayl:BAAALgAECgkJCQAAAA==.Greenrage:BAAALgADCgQJBAAAAA==.Griever:BAAALgAECgYJCQAAAA==.Grizzly:BAAALgADCggJDAABLgAECgYJFwAFAHMLAA==.Groovexgroov:BAABLgAECn8UAAIOAAkJ9A9WGQDWAQAOAAkJ9A9WGQDWAQAAAA==.',
He='Healrog:BAAALgAECgYJBgAAAA==.Hellraiser:BAAALgAECgMJAwAAAA==.',
Hi='Highfive:BAAALgADCgIJAgAAAA==.',
Ho='Holyfiero:BAAALgAECgMJAwABLgAECgQJBQARAAAAAA==.Holynight:BAAALgADCgEJAgABLgAECgYJFwAFAHMLAA==.Hordend:BAAALgAECgUJEAAAAA==.Hozru:BAAALgADCgEJAQAAAA==.',
Hu='Hulkfists:BAABLgAECn8UAAMLAAYJownMSgAcAQALAAYJownMSgAcAQAXAAYJ3gLVHgDiAAAAAA==.',
Hy='Hydration:BAAALgADCgMJAwAAAA==.',
Im='Imcepsy:BAABLgAECn81AAIBAAkJ7BkECQC8AgABAAkJ7BkECQC8AgAAAA==.',
Io='Iownzuu:BAAALgADCgMJAwAAAA==.',
Is='Istari:BAAALgAECgIJAgAAAA==.Istark:BAAALgAECgMJAwAAAA==.',
Ja='Jayjay:BAACLgAFFH8IAAIKAAQJdxNeRAA9AQAKAAQJdxNeRAA9AQAuAAQKfxcAAgoACQlHG9opAFYCAAoACQlHG9opAFYCAAAA.',
Je='Jethroy:BAABLgAECn8VAAIYAAgJbRG5LwBzAQAYAAgJbRG5LwBzAQAAAA==.',
Jf='Jfkwspvpfldg:BAAALgAECgYJBgAAAA==.',
Ji='Jimmie:BAABLgAECn8aAAIQAAgJuiAkEQCYAgAQAAgJuiAkEQCYAgAAAA==.',
Jo='Johnparstina:BAAALgAECgYJDgAAAA==.Jolty:BAACLgAFFH8KAAIXAAQJNx8DAwBvAQAXAAQJNx8DAwBvAQAuAAQKfyEAAhcACQmrI1MBAA8DABcACQmrI1MBAA8DAAAA.',
Jr='Jrbacnchee:BAAALgAECgEJAQAAAA==.Jrbcncheze:BAAALgAECggJEgAAAA==.',
Ka='Kainicus:BAACLgAFFH8MAAITAAQJ6BJ/AwASAQATAAQJ6BJ/AwASAQAuAAQKf1EAAhMACQmoF88GAPQBABMACQmoF88GAPQBAAAA.Kainigal:BAAALgADCgYJCwAAAA==.Kainisham:BAAALgADCgcJBwAAAA==.',
Ke='Kelador:BAABLgAECn8hAAIZAAYJtAjHHwDNAAAZAAYJtAjHHwDNAAAAAA==.Keoni:BAAALgAECgEJAQAAAA==.Kerrykoppene:BAAALgAECgEJAQAAAA==.',
Kh='Khappucino:BAAALgAECgYJCAAAAA==.Kharibou:BAAALgAECgIJAgAAAA==.Khellendros:BAAALgADCgYJCgAAAA==.Khrism:BAAALgADCgQJBAAAAA==.',
Ki='Kibbi:BAAALgADCgcJBwAAAA==.Kitsyune:BAABLgAECn8fAAIaAAkJ7BdsBAASAgAaAAkJ7BdsBAASAgAAAA==.',
Kj='Kjartan:BAAALgAECgUJBQAAAA==.',
Kl='Kløey:BAAALgAECgYJEwAAAA==.',
La='Laethys:BAAALgADCggJCAABLgAECgkJIQAKAEIeAA==.',
Li='Lithini:BAAALgAECgQJCAAAAA==.',
Lo='Lowtech:BAAALgAECgMJAwAAAA==.',
Lu='Luminusrayne:BAACLgAFFH8KAAIbAAMJmgQ0HQCiAAAbAAMJmgQ0HQCiAAAuAAQKf0YAAwEACQm8DQMiAIQBAAEACAn8CgMiAIQBABsACQk+DCcqAFMBAAAA.Lussypipz:BAAALgAECgYJDQAAAA==.',
Ma='Mahwe:BAAALgAECggJDgAAAA==.Manafest:BAAALgAECgMJCgAAAA==.Maros:BAABLgAECn8kAAMKAAkJWhZxLgBBAgAKAAkJWhZxLgBBAgAcAAEJJA+JEQA2AAAAAA==.',
Me='Meheret:BAABLgAECn9BAAIKAAkJZgZ8kwA2AQAKAAkJZgZ8kwA2AQAAAA==.Melissenia:BAAALgAECgQJBAAAAA==.Menious:BAAALgAECgEJAQAAAA==.Mepha:BAAALgAECgYJCQAAAA==.',
Mi='Mint:BAABLgAECn8hAAIKAAkJQh5dIwDlAgAKAAkJQh5dIwDlAgAAAA==.',
Mo='Mokth:BAAALgADCgMJAwAAAA==.Mom:BAAALgAECgIJAgAAAA==.Mooby:BAABLgAECn8XAAIQAAgJjRocGABHAgAQAAgJjRocGABHAgAAAA==.Moonfury:BAAALgAECgEJAQAAAA==.Moonleigh:BAAALgADCgMJBAAAAA==.Morganthe:BAAALgAECgIJAwAAAA==.',
Mu='Munt:BAAALgAECgQJBAABLgAECgkJIQAKAEIeAA==.',
My='Mypriiest:BAAALgAECgQJBAAAAA==.Myroguëë:BAAALgADCgUJBQAAAA==.Mystx:BAAALgAFFAIJBAABLgAFFAMJCAAHABMeAA==.Mythx:BAACLgAFFH8IAAIHAAMJEx4pIQD/AAAHAAMJEx4pIQD/AAAuAAQKfzIAAgcACAnFIsMIALYCAAcACAnFIsMIALYCAAAA.Mywarr:BAAALgADCgMJAwAAAA==.',
Na='Naturemage:BAAALgAECgUJBwAAAA==.Natâsi:BAABLgAECn8vAAIYAAkJpBlMFABGAgAYAAkJpBlMFABGAgAAAA==.',
Ne='Nerazul:BAABLgAECn8VAAQDAAYJph/GBQAKAgADAAYJph/GBQAKAgACAAMJ3wqC4wCTAAAdAAEJ/AgReAAsAAAAAA==.Netharec:BAAALgADCgEJAQABLgAFFAQJCgAOACUYAA==.Nevai:BAABLgAECn8YAAIYAAkJCxLjGwD+AQAYAAkJCxLjGwD+AQAAAA==.',
Ni='Nielas:BAABLgAECn8UAAIFAAgJ7yDvHwBnAgAFAAgJ7yDvHwBnAgAAAA==.Nihilus:BAACLgAFFH8QAAIFAAYJ6RmTCACMAQAFAAYJ6RmTCACMAQAuAAQKfxUAAgUABwkWJLkvAHkCAAUABwkWJLkvAHkCAAAA.Nilari:BAABLgAECn8UAAIeAAYJIQmfKAClAAAeAAYJIQmfKAClAAAAAA==.Nine:BAAALgADCgYJBgABLgAFFAQJDgAJAGghAA==.',
No='Noctazari:BAAALgADCgUJBQAAAA==.Noctium:BAABLgAECn8eAAIUAAgJpyIxAgCIAgAUAAgJpyIxAgCIAgAAAA==.Nostrildamus:BAAALgAECgYJEQABLgAECgkJGAAIADYYAA==.',
Nz='Nzoth:BAAALgADCgYJBgAAAA==.',
Of='Officimeeg:BAAALgADCgEJAQAAAA==.',
Ow='Owlaf:BAAALgAECgIJAgABLgAFFAUJFgABAA8ZAA==.Owls:BAACLgAFFH8WAAIBAAUJDxnAEQCeAQABAAUJDxnAEQCeAQAuAAQKfzcAAwEACQkWI0kFABMDAAEACQmGIEkFABMDABsABwkbJPcKAJ8CAAEuAAUUBQkWAAEADxkA.',
Pa='Pallywhacker:BAAALgADCgMJAwAAAA==.Panconcaca:BAAALgAFFAcJAwAAAA==.Pantsokay:BAAALgADCgEJAQAAAA==.',
Pe='Peach:BAABLgAECn8cAAMfAAgJ4Q2yCQB/AQAfAAgJ4Q2yCQB/AQAQAAYJUAGeSwDNAAAAAA==.Peaches:BAAALgAECgEJAgAAAA==.Petsmart:BAAALgAECgQJBQAAAA==.',
Po='Potatoeshot:BAAALgAECgQJBQAAAA==.',
Pr='Praisethesun:BAAALgAECgQJCQAAAA==.Prayxx:BAAALgAECgYJCQAAAA==.Pretzel:BAACLgAFFH8MAAIFAAUJ0SMtGwCjAQAFAAUJ0SMtGwCjAQAuAAQKfzMAAwUACQlRJZ4EAIoDAAUACQlRJZ4EAIoDACAAAQk5IcMjAFgAAAAA.Proved:BAABLgAECn9MAAIbAAkJkR1PBwDXAgAbAAkJkR1PBwDXAgAAAA==.',
Ps='Psillycybin:BAAALgAECgcJDQAAAA==.',
Pu='Puddingface:BAAALgADCgkJCQAAAA==.Puggar:BAAALgADCgQJBgAAAA==.Pumpspotter:BAAALgAECgkJEgAAAA==.',
Qu='Quiescence:BAAALgADCgYJBgAAAA==.',
Ra='Ranas:BAAALgADCgIJAgAAAA==.Ranessandi:BAAALgAECgEJAQAAAA==.Ratlemebonez:BAAALgAECgEJAQAAAA==.Ravèn:BAAALgAECgcJEQAAAA==.Rayana:BAAALgADCgYJBgAAAA==.Razeal:BAAALgAECgYJDwAAAA==.',
Re='Rene:BAEALgAECgYJCAAAAA==.Rev:BAAALgADCgEJAQAAAA==.',
Rh='Rhysan:BAACLgAFFH8KAAIMAAQJUBs7GQBXAQAMAAQJUBs7GQBXAQAuAAQKfzsAAgwACQm9FxEsANoBAAwACQm9FxEsANoBAAAA.Rhyuk:BAAALgADCgQJBAAAAA==.',
Ri='Ristria:BAAALgADCgYJEAABLgAECgUJGQAIAHwRAA==.Rizy:BAABLgAECn8ZAAIFAAkJiw6gTAC6AQAFAAkJiw6gTAC6AQAAAA==.',
Ro='Robonord:BAAALgAECgIJAgAAAA==.Rokki:BAAALgADCgIJAgAAAA==.',
Ru='Rude:BAAALgADCgcJCwAAAA==.',
Ry='Rynhart:BAAALgADCgUJBQAAAA==.Ryushi:BAACLgAFFH8NAAIEAAQJYhQ0MQAoAQAEAAQJYhQ0MQAoAQAuAAQKf0gAAgQACQnGIFkUAIMCAAQACQnGIFkUAIMCAAAA.',
Sa='Sacerdote:BAABLgAECn8UAAICAAYJPiHMQwC4AQACAAYJPiHMQwC4AQAAAA==.Sakari:BAAALgADCgcJEAAAAA==.Sandara:BAAALgADCgYJBgAAAA==.Sangre:BAAALgADCgIJAgABLgADCgMJAwARAAAAAA==.Sarasara:BAAALgADCgUJBQAAAA==.',
Sc='Scoots:BAAALgAECgUJCAABLgAFFAQJDgAJAGghAA==.Scratster:BAAALgAECgcJCAAAAA==.',
Se='Sebnoth:BAABLgAECn8yAAIFAAkJtCBzDQDhAgAFAAkJtCBzDQDhAgAAAA==.',
Sh='Shalashaska:BAAALgADCgEJAQAAAA==.Shamantastik:BAAALgAECgMJAwAAAA==.Shiden:BAAALgAECgYJDwAAAA==.Shiift:BAAALgADCgYJBwAAAA==.Shockblocked:BAAALgADCgQJBAAAAA==.',
Si='Sideburn:BAAALgADCgUJBQAAAA==.Sidepiece:BAAALgADCgcJCAAAAA==.Sillyderek:BAACLgAFFH8FAAIeAAIJSgj4DgBaAAAeAAIJSgj4DgBaAAAuAAQKfxoAAh4ABwmnDQIcAAkBAB4ABwmnDQIcAAkBAAAA.',
Sl='Slashology:BAAALgAECgYJDAAAAA==.',
Sm='Smallpally:BAAALgAECgQJDgAAAA==.',
So='Soarsha:BAAALgAECgIJAgAAAA==.Solarida:BAABLgAECn8gAAIIAAcJzRj+WwCbAQAIAAcJzRj+WwCbAQAAAA==.',
Sr='Srsawyer:BAABLgAECn8bAAICAAgJSA/nYACnAQACAAgJSA/nYACnAQAAAA==.',
St='Staralfur:BAAALgADCgcJBwAAAA==.Stevokerjobs:BAABLgAECn8UAAQUAAYJlRVQIAArAQAUAAYJaxJQIAArAQAGAAMJih2fGwAAAQAVAAQJRBN+RADvAAAAAA==.Stormshäde:BAAALgAECgUJAQAAAA==.Stratos:BAAALgADCgcJBwAAAA==.',
Su='Sunwa:BAACLgAFFH8GAAMIAAIJqQ5QawCZAAAIAAIJqQ5QawCZAAAeAAEJjwOTFAAnAAAuAAQKfxwAAwgACAluGuEvAB8CAAgACAluGuEvAB8CAB4ABgnxCmclALoAAAEuAAUUAwkIAAcAEx4A.',
['Sï']='Sïmba:BAAALgAECgMJCQAAAA==.',
Te='Terzhull:BAAALgADCgIJAgAAAA==.',
Th='Thepride:BAAALgAECggJDwAAAA==.',
Ti='Timmytim:BAAALgAECgQJCAAAAA==.Tired:BAAALgAECgUJBgAAAA==.',
To='Tool:BAACLgAFFH8ZAAIKAAgJHBvBAADdAgAKAAgJHBvBAADdAgAuAAQKfyYAAgoACQnrJGMCANgDAAoACQnrJGMCANgDAAAA.Touchi:BAAALgAECgYJCgABLgAECgkJKQAZABkcAA==.',
Tr='Troljin:BAAALgADCgEJAQAAAA==.',
Tu='Tuo:BAABLgAECn8pAAIZAAkJGRwTBACeAgAZAAkJGRwTBACeAgAAAA==.Turbid:BAABLgAECn8xAAIEAAkJHBR9MgDcAQAEAAkJHBR9MgDcAQAAAA==.',
Ty='Ty:BAAALgAECgUJDAAAAA==.Tytank:BAAALgADCgMJBAAAAA==.',
Uh='Uhavemyrice:BAAALgADCgIJAgAAAA==.',
Ve='Velkin:BAAALgAECgEJAQAAAA==.',
Vi='Vivia:BAAALgADCgQJBAAAAA==.Viviann:BAAALgADCgMJAwAAAA==.Vivians:BAAALgADCggJCgAAAA==.',
Vo='Voutecomer:BAAALgADCgYJCAAAAA==.',
Wa='Walls:BAABLgAECn8YAAIIAAkJNhjFJQBMAgAIAAkJNhjFJQBMAgAAAA==.Warrach:BAAALgADCgQJBAAAAA==.',
We='Wennoe:BAAALgADCgIJAgAAAA==.Westirras:BAAALgAECgcJDQAAAA==.',
Yo='Yogurt:BAAALgAECgcJEAABLgAECgkJLgAIAMcXAA==.',
Yu='Yusuke:BAABLgAECn8WAAMhAAcJfhGtJQBiAQAhAAcJfhGtJQBiAQAPAAYJPQlyQADgAAABLgAECggJHAANAFQaAA==.',
Za='Zabuzabuza:BAAALgAECgIJAgABLgAECgYJFAAUAJUVAA==.Zazabandit:BAAALgADCgUJBQAAAA==.',
Zo='Zolleta:BAAALgAECgQJBAAAAA==.',
Zu='Zuesulty:BAAALgADCgYJBgAAAA==.Zunden:BAAALgAECggJEwAAAA==.',
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
