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

local lookup = {'Priest-Discipline','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Preservation','Paladin-Retribution','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Priest-Shadow','Monk-Mistweaver','Rogue-Subtlety','Unknown-Unknown','Hunter-Marksmanship','DemonHunter-Vengeance','Evoker-Augmentation','Warrior-Fury','Hunter-BeastMastery','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Druid-Feral','Rogue-Outlaw','Priest-Holy','Mage-Arcane','Warlock-Destruction','Paladin-Protection','Rogue-Assassination','DeathKnight-Frost','Monk-Brewmaster',}
local provider = {region='US',realm='Andorhal',name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Adelyne:BAAALgAECgMJAwABLgAFFAUJDgABAG0SAA==.Adorablepine:BAABLgAECn8ZAAMCAAcJuAMCmQDLAAACAAcJrAMCmQDLAAADAAEJqgOUKQAgAAAAAA==.',
Ag='Agaze:BAACLgAFFH8VAAIEAAYJHiAkEACfAQAEAAYJHiAkEACfAQAuAAQKfxYAAgQACAkTIgAZAL8CAAQACAkTIgAZAL8CAAAA.',
Ai='Aiedel:BAAALgAECgUJCQAAAA==.',
Al='Allesa:BAAALgAECgEJAQAAAA==.',
Ao='Aoise:BAAALgAECgkJCAAAAA==.',
Ap='Applejuuice:BAABLgAFFH8FAAIFAAMJ5BI4YADyAAAFAAMJ5BI4YADyAAABLgAECggJFwAGAMcSAA==.',
Ar='Archblade:BAAALgADCgMJBAAAAA==.Arelith:BAAALgAECgMJBwAAAA==.Arlen:BAABLgAECn8fAAIHAAgJuBXWTQCUAQAHAAgJuBXWTQCUAQAAAA==.Arma:BAABLgAECn8cAAIIAAgJjiNGBQAwAwAIAAgJjiNGBQAwAwAAAA==.Armadro:BAABLgAFFH8MAAIJAAQJPBzfIQB5AQAJAAQJPBzfIQB5AQAAAA==.',
Au='Aurky:BAAALgAECgEJAwAAAA==.',
Ba='Bald:BAAALgADCgYJBgAAAA==.Balob:BAACLgAFFH8XAAMKAAYJ6h4WBgB3AQAKAAUJjiAWBgB3AQALAAEJvwKyTwBCAAAuAAQKfyUAAgoACAlqJXoEAFQDAAoACAlqJXoEAFQDAAAA.Bandar:BAAALgADCgcJBwAAAA==.',
Be='Bellafists:BAAALgAECgYJBgAAAA==.',
Bl='Blacksteve:BAAALgAECgIJAgAAAA==.Bloodngore:BAABLgAECn8UAAIMAAgJqguYHAAdAQAMAAgJqguYHAAdAQAAAA==.',
Bm='Bmxdh:BAAALgAECgYJDwAAAA==.',
Br='Broku:BAAALgAECgYJCAABLgAECgkJLAAHALwWAA==.Brudah:BAAALgAECgEJAQAAAA==.',
Bu='Bubblelove:BAABLgAECn8cAAINAAkJxAxdGgCeAQANAAkJxAxdGgCeAQAAAA==.Bubbly:BAABLgAECn8sAAIHAAkJvBb/MQDwAQAHAAkJvBb/MQDwAQAAAA==.Butes:BAAALgAECggJCAAAAA==.',
Ca='Caelum:BAAALgAECgMJAwAAAA==.Callmepappy:BAAALgADCgUJBQAAAA==.Canníbal:BAAALgAECggJDwAAAA==.',
Ce='Censored:BAAALgADCgIJAgAAAA==.',
Ch='Chopsy:BAACLgAFFH8KAAIIAAMJxCGwCgAwAQAIAAMJxCGwCgAwAQAuAAQKf1QAAwgACQkeJf4AAFoDAAgACQkeJf4AAFoDAA4AAgnEC91eAFIAAAAA.Chris:BAAALgAECgUJCQAAAA==.Chucklez:BAAALgAECgEJAQAAAA==.Chulobulo:BAABLgAECn8WAAIPAAgJFBQCEgDEAQAPAAgJFBQCEgDEAQAAAA==.Chulosdck:BAAALgAECgUJCQABLgAECggJFgAPABQUAA==.',
Ci='Cinnabons:BAAALgAECgYJDQABLgAECggJFwAGAMcSAA==.',
Cl='Cleopatrick:BAAALgADCgkJEAAAAA==.',
Co='Codingsocks:BAAALgADCgEJAgAAAA==.',
Cr='Crekton:BAAALgAECgMJAwAAAA==.Cronnos:BAAALgAECgYJBwAAAA==.',
Cu='Cudlemonster:BAABLgAECn8sAAIBAAkJKgziFwC7AQABAAkJKgziFwC7AQAAAA==.Cursed:BAABLgAECn8tAAMDAAkJhCCNAQCMAgADAAkJhCCNAQCMAgACAAIJlwuaywBoAAAAAA==.',
Da='Dabz:BAAALgAFFAEJAQAAAA==.Daddyslaps:BAAALgAECgUJBQAAAA==.Danyel:BAAALgADCgYJBwAAAA==.Darmok:BAABLgAECn81AAMLAAkJ3yP0AQB1AwALAAkJ3yP0AQB1AwAKAAEJbBoSbQBGAAAAAA==.Darzamat:BAAALgADCgEJAQAAAA==.',
De='Demonbubble:BAACLgAFFH8PAAIEAAUJ2QoQMwAMAQAEAAUJ2QoQMwAMAQAuAAQKfy0AAgQACQn1Fk8dACACAAQACQn1Fk8dACACAAAA.Dezric:BAAALgADCgYJDAABLgAECgYJDQAQAAAAAA==.Dezruf:BAAALgAECgEJAQABLgAECgYJDQAQAAAAAA==.',
Do='Dotomic:BAAALgAFFAEJAQABLgAFFAcJGQARAAAfAA==.',
Dr='Drejan:BAAALgAECgcJBwAAAA==.Drfe:BAAALgADCgYJBgAAAA==.Drowarchon:BAAALgADCgIJAgABLgAECgQJBAAQAAAAAA==.Drownix:BAAALgAECgQJBAAAAA==.Drowzy:BAAALgADCgQJBAABLgAECgQJBAAQAAAAAA==.',
['Dä']='Dämonjäger:BAAALgADCggJCAAAAA==.',
Eb='Ebon:BAAALgADCgMJAwAAAA==.',
Ec='Ecaed:BAABLgAECn8ZAAISAAgJFgcQEAD4AAASAAgJFgcQEAD4AAAAAA==.',
Ei='Eisenhørn:BAAALgADCgYJBgAAAA==.',
El='Elektriss:BAAALgAECgQJBAAAAA==.Elnaris:BAABLgAECn8ZAAIHAAcJlQZRkwABAQAHAAcJlQZRkwABAQAAAA==.Elohime:BAAALgADCgYJCAAAAA==.',
Eo='Eon:BAAALgAECgIJBwAAAA==.',
Er='Erikkak:BAAALgADCgQJBAAAAA==.Erõs:BAAALgAECgQJBQABLgAFFAEJAgAQAAAAAA==.',
Fi='Fire:BAAALgAECgUJBQABLgAFFAYJFQATAGUbAA==.',
Fr='Fragga:BAABLgAECn8XAAIUAAYJuxQGNQAlAQAUAAYJuxQGNQAlAQAAAA==.',
Fu='Fullflavor:BAAALgADCgIJAgAAAA==.',
['Fü']='Füran:BAAALgADCgIJAgAAAA==.',
Ga='Ganryu:BAAALgADCgYJCgAAAA==.',
Gb='Gboybalili:BAAALgADCgcJDAAAAA==.',
Gi='Gitzi:BAABLgAECn9IAAIVAAkJ7Rt9EwBsAgAVAAkJ7Rt9EwBsAgAAAA==.',
Gl='Glaciea:BAAALgADCgMJAwABLgAECggJHAAWAKgiAA==.',
Gr='Greenrage:BAAALgADCgQJBAAAAA==.Griever:BAAALgAECgYJCQAAAA==.Grizzly:BAAALgADCgcJCgABLgAECgYJEQAQAAAAAA==.Groovexgroov:BAAALgAECggJCwAAAA==.',
He='Healrog:BAAALgAECgYJBgAAAA==.Hellraiser:BAAALgAECgMJAwAAAA==.',
Hi='Highfive:BAAALgADCgIJAgAAAA==.',
Ho='Holynight:BAAALgADCgEJAQABLgAECgYJEQAQAAAAAA==.Hordend:BAAALgAECgUJEAAAAA==.Hozru:BAAALgADCgEJAQAAAA==.',
Hu='Hulkfists:BAABLgAECn8UAAMKAAYJownMSgAcAQAKAAYJownMSgAcAQAXAAYJ3gLVHgDiAAAAAA==.',
Hy='Hydration:BAAALgADCgMJAwAAAA==.',
Im='Imcepsy:BAABLgAECn8uAAIBAAgJRxmzDABMAgABAAgJRxmzDABMAgAAAA==.',
Io='Iownzuu:BAAALgADCgMJAwAAAA==.',
Is='Istari:BAAALgAECgIJAgAAAA==.Istark:BAAALgAECgMJAwAAAA==.',
Ja='Jayjay:BAABLgAECn8VAAIJAAkJRxsrIQBcAgAJAAkJRxsrIQBcAgAAAA==.',
Je='Jethroy:BAABLgAECn8VAAIYAAgJbREZKQB2AQAYAAgJbREZKQB2AQAAAA==.',
Jf='Jfkwspvpfldg:BAAALgAECgYJBgAAAA==.',
Ji='Jimmie:BAABLgAECn8aAAIPAAgJuiAkEQCYAgAPAAgJuiAkEQCYAgAAAA==.',
Jo='Johnparstina:BAAALgAECgYJCgAAAA==.Jolty:BAACLgAFFH8KAAIXAAQJNx/GAQCFAQAXAAQJNx/GAQCFAQAuAAQKfx8AAhcACQnwH48BAOcCABcACQnwH48BAOcCAAAA.',
Jr='Jrbacnchee:BAAALgAECgEJAQAAAA==.Jrbcncheze:BAAALgAECggJEgAAAA==.',
Ka='Kainicus:BAACLgAFFH8IAAISAAMJJxNiBADVAAASAAMJJxNiBADVAAAuAAQKf1AAAhIACQmnFxsEADcCABIACQmnFxsEADcCAAAA.Kainigal:BAAALgADCgYJCwAAAA==.Kainisham:BAAALgADCgcJBwAAAA==.',
Ke='Kelador:BAABLgAECn8bAAIZAAYJdAZHHADAAAAZAAYJdAZHHADAAAAAAA==.Keoni:BAAALgAECgEJAQAAAA==.',
Kh='Khappucino:BAAALgAECgYJCAAAAA==.Kharibou:BAAALgAECgIJAgAAAA==.Khellendros:BAAALgADCgYJCgAAAA==.Khrism:BAAALgADCgQJBAAAAA==.',
Ki='Kibbi:BAAALgADCgcJBwAAAA==.Kitsyune:BAABLgAECn8fAAIaAAkJ6RdpAwAZAgAaAAkJ6RdpAwAZAgAAAA==.',
Kl='Kløey:BAAALgAECgYJEwAAAA==.',
La='Laethys:BAAALgADCggJCAABLgAECgkJIQAJAEEeAA==.',
Li='Lithini:BAAALgAECgQJCAAAAA==.',
Lo='Lowtech:BAAALgAECgMJAwAAAA==.',
Lu='Luminusrayne:BAACLgAFFH8IAAIbAAMJoQPyGACiAAAbAAMJoQPyGACiAAAuAAQKf0UAAxsACQm8DbgcAJcBABsACQk+DLgcAJcBAAEACAn8CgMiAIQBAAAA.Lussypipz:BAAALgAECgYJDQAAAA==.',
Ma='Mahwe:BAAALgAECggJDAAAAA==.Manafest:BAAALgAECgMJCgAAAA==.Maros:BAABLgAECn8eAAMJAAkJtRWIKQAyAgAJAAkJtRWIKQAyAgAcAAEJJA9NDwA6AAAAAA==.',
Me='Meheret:BAABLgAECn9AAAIJAAkJcQZeZwBuAQAJAAkJcQZeZwBuAQAAAA==.Melissenia:BAAALgAECgQJBAAAAA==.Mepha:BAAALgAECgYJCQAAAA==.',
Mi='Mint:BAABLgAECn8hAAIJAAkJQR5bGgCCAgAJAAkJQR5bGgCCAgAAAA==.',
Mo='Mokth:BAAALgADCgMJAwAAAA==.Mom:BAAALgAECgIJAgAAAA==.Mooby:BAABLgAECn8XAAIPAAgJjRqIEQDKAQAPAAgJjRqIEQDKAQAAAA==.Moonfury:BAAALgAECgEJAQAAAA==.Moonleigh:BAAALgADCgMJBAAAAA==.Morganthe:BAAALgAECgIJAwAAAA==.',
Mu='Munt:BAAALgAECgQJBAABLgAECgkJIQAJAEEeAA==.',
My='Mypriiest:BAAALgAECgQJBAAAAA==.Myroguëë:BAAALgADCgUJBQAAAA==.Mystx:BAAALgAECgUJCAABLgAFFAMJBgAUAEoeAA==.Mythx:BAACLgAFFH8GAAIUAAMJSh6hGQAQAQAUAAMJSh6hGQAQAQAuAAQKfyoAAhQACAmsIkQHAKsCABQACAmsIkQHAKsCAAAA.Mywarr:BAAALgADCgMJAwAAAA==.',
Na='Naturemage:BAAALgAECgUJBwAAAA==.Natâsi:BAABLgAECn8tAAIYAAkJOhmOEQA+AgAYAAkJOhmOEQA+AgAAAA==.',
Ne='Nerazul:BAABLgAECn8VAAQDAAYJph/GBQAKAgADAAYJph/GBQAKAgACAAMJ3wqC4wCTAAAdAAEJ/AgReAAsAAAAAA==.Netharec:BAAALgADCgEJAQABLgAFFAQJBwANAAEWAA==.Nevai:BAABLgAECn8WAAIYAAgJXxNtHADTAQAYAAgJXxNtHADTAQAAAA==.',
Ni='Nielas:BAAALgAECgcJEwAAAA==.Nihilus:BAACLgAFFH8PAAIFAAUJVheTCACMAQAFAAUJVheTCACMAQAuAAQKfxUAAgUABwkWJLkvAHkCAAUABwkWJLkvAHkCAAAA.Nilari:BAABLgAECn8UAAIeAAYJIQniIgCoAAAeAAYJIQniIgCoAAAAAA==.Nine:BAAALgADCgYJBgABLgAFFAMJCgAIAMQhAA==.',
No='Noctazari:BAAALgADCgUJBQAAAA==.Noctium:BAABLgAECn8cAAIWAAgJqCKdAQCYAgAWAAgJqCKdAQCYAgAAAA==.Nostrildamus:BAAALgAECgYJEQABLgAECgkJFQAHAK0XAA==.',
Nz='Nzoth:BAAALgADCgYJBgAAAA==.',
Of='Officimeeg:BAAALgADCgEJAQAAAA==.',
Ow='Owlaf:BAAALgAECgIJAgABLgAFFAQJEQABANUbAA==.Owls:BAACLgAFFH8RAAIBAAQJ1RscFABGAQABAAQJ1RscFABGAQAuAAQKfzcAAwEACQkWI+cDABwDAAEACQmGIOcDABwDABsABwkbJPcKAJ8CAAEuAAUUBAkRAAEA1RsA.',
Pa='Pallywhacker:BAAALgADCgMJAwAAAA==.Panconcaca:BAAALgAFFAcJAwAAAA==.Pantsokay:BAAALgADCgEJAQAAAA==.',
Pe='Peach:BAABLgAECn8cAAMfAAgJ3w1HCAB/AQAfAAgJ3w1HCAB/AQAPAAYJUAGeSwDNAAAAAA==.Peaches:BAAALgADCgkJCQAAAA==.Petsmart:BAAALgAECgQJBQAAAA==.',
Po='Potatoeshot:BAAALgAECgQJBQAAAA==.',
Pr='Praisethesun:BAAALgAECgQJCQAAAA==.Prayxx:BAAALgAECgYJCQAAAA==.Pretzel:BAACLgAFFH8HAAIFAAQJrRpiMQBQAQAFAAQJrRpiMQBQAQAuAAQKfzIAAwUACQlRJZ4EAIoDAAUACQlRJZ4EAIoDACAAAQk5Ie8bAFsAAAAA.Proved:BAABLgAECn9EAAIbAAkJmRy+BgDEAgAbAAkJmRy+BgDEAgAAAA==.',
Ps='Psillycybin:BAAALgAECgcJDQAAAA==.',
Pu='Puddingface:BAAALgADCgkJCQAAAA==.Puggar:BAAALgADCgQJBgAAAA==.Pumpspotter:BAAALgAECgkJEgAAAA==.',
Qu='Quiescence:BAAALgADCgYJBgAAAA==.',
Ra='Ranas:BAAALgADCgIJAgAAAA==.Ranessandi:BAAALgADCgUJBQAAAA==.Ratlemebonez:BAAALgAECgEJAQAAAA==.Ravèn:BAAALgAECgcJEQAAAA==.Rayana:BAAALgADCgYJBgAAAA==.Razeal:BAAALgAECgYJDwAAAA==.',
Re='Rene:BAEALgAECgYJCAAAAA==.Rev:BAAALgADCgEJAQAAAA==.',
Rh='Rhysan:BAACLgAFFH8IAAILAAMJCRjXJgDvAAALAAMJCRjXJgDvAAAuAAQKfzoAAgsACQm9F8cWAD8CAAsACQm9F8cWAD8CAAAA.Rhyuk:BAAALgADCgQJBAAAAA==.',
Ri='Ristria:BAAALgADCgYJEAABLgAECgUJFAAHADMRAA==.Rizy:BAABLgAECn8ZAAIFAAkJkg4CQAC9AQAFAAkJkg4CQAC9AQAAAA==.',
Ro='Robonord:BAAALgAECgIJAgAAAA==.Rokki:BAAALgADCgIJAgAAAA==.',
Ru='Rude:BAAALgADCgcJCwAAAA==.',
Ry='Rynhart:BAAALgADCgUJBQAAAA==.Ryushi:BAACLgAFFH8JAAIEAAMJhhclOwDtAAAEAAMJhhclOwDtAAAuAAQKf0cAAgQACQnGIFUGAPUCAAQACQnGIFUGAPUCAAAA.',
Sa='Sacerdote:BAABLgAECn8UAAICAAYJPiFnNQDDAQACAAYJPiFnNQDDAQAAAA==.Sakari:BAAALgADCgcJEAAAAA==.Sandara:BAAALgADCgYJBgAAAA==.Sangre:BAAALgADCgIJAgAAAA==.Sarasara:BAAALgADCgUJBQAAAA==.',
Sc='Scoots:BAAALgAECgUJCAABLgAFFAMJCgAIAMQhAA==.Scratster:BAAALgAECgcJCAAAAA==.',
Se='Sebnoth:BAABLgAECn8qAAIFAAgJCRziJwAbAgAFAAgJCRziJwAbAgAAAA==.',
Sh='Shalashaska:BAAALgADCgEJAQAAAA==.Shamantastik:BAAALgAECgMJAwAAAA==.Shiden:BAAALgAECgYJDwAAAA==.Shiift:BAAALgADCgYJBwAAAA==.Shockblocked:BAAALgADCgQJBAAAAA==.',
Si='Sideburn:BAAALgADCgUJBQAAAA==.Sidepiece:BAAALgADCgcJCAAAAA==.Sillyderek:BAABLgAECn8aAAIeAAcJpw11FwAPAQAeAAcJpw11FwAPAQAAAA==.',
Sl='Slashology:BAAALgAECgYJBwAAAA==.',
Sm='Smallpally:BAAALgAECgQJDQAAAA==.',
So='Soarsha:BAAALgAECgEJAQAAAA==.Solarida:BAABLgAECn8eAAIHAAcJSBdPUgCIAQAHAAcJSBdPUgCIAQAAAA==.',
Sr='Srsawyer:BAABLgAECn8bAAICAAgJSA/nYACnAQACAAgJSA/nYACnAQAAAA==.',
St='Staralfur:BAAALgADCgcJBwAAAA==.Stevokerjobs:BAAALgAFFAEJAgAAAA==.Stratos:BAAALgADCgcJBwAAAA==.',
Su='Sunwa:BAABLgAECn8WAAMHAAcJMheNWQB2AQAHAAYJTBmNWQB2AQAeAAYJ8QruHwC9AAABLgAFFAMJBgAUAEoeAA==.',
['Sï']='Sïmba:BAAALgAECgMJCQAAAA==.',
Te='Terzhull:BAAALgADCgIJAgAAAA==.',
Th='Thepride:BAAALgAECggJDwAAAA==.',
Ti='Timmytim:BAAALgAECgQJCAAAAA==.Tired:BAAALgAECgUJBgAAAA==.',
To='Tool:BAACLgAFFH8ZAAIJAAgJHBvBAADdAgAJAAgJHBvBAADdAgAuAAQKfyYAAgkACQnrJGMCANgDAAkACQnrJGMCANgDAAAA.Touchi:BAAALgAECgMJBAABLgAECggJHQAZAHIaAA==.',
Tr='Troljin:BAAALgADCgEJAQAAAA==.',
Tu='Tuo:BAABLgAECn8dAAIZAAgJchprBwAEAgAZAAgJchprBwAEAgAAAA==.Turbid:BAABLgAECn8oAAIEAAkJghNRLQDJAQAEAAkJghNRLQDJAQAAAA==.',
Ty='Ty:BAAALgAECgUJDAAAAA==.Tytank:BAAALgADCgMJAwAAAA==.',
Uh='Uhavemyrice:BAAALgADCgIJAgAAAA==.',
Ve='Velkin:BAAALgAECgEJAQAAAA==.',
Vi='Vivia:BAAALgADCgQJBAAAAA==.Viviann:BAAALgADCgMJAwAAAA==.Vivians:BAAALgADCggJCgAAAA==.',
Vo='Voutecomer:BAAALgADCgYJCAAAAA==.',
Wa='Walls:BAABLgAECn8VAAIHAAkJrRceJAAtAgAHAAkJrRceJAAtAgAAAA==.Warrach:BAAALgADCgQJBAAAAA==.',
We='Wennoe:BAAALgADCgIJAgAAAA==.Westirras:BAAALgAECgYJCgAAAA==.',
Yo='Yogurt:BAAALgAECgYJCQABLgAECgkJLAAHALwWAA==.',
Yu='Yusuke:BAABLgAECn8WAAMhAAcJfhHHHwBqAQAhAAcJfhHHHwBqAQAOAAYJPQlyQADgAAABLgAECggJFAAMAKoLAA==.',
Za='Zazabandit:BAAALgADCgUJBQAAAA==.',
Zo='Zolleta:BAAALgAECgQJBAAAAA==.',
Zu='Zuesulty:BAAALgADCgYJBgAAAA==.Zunden:BAAALgAECgcJEQAAAA==.',
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
