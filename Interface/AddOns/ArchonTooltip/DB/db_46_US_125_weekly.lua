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

local lookup = {'Paladin-Holy','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Devourer','Paladin-Protection','Warlock-Destruction','Evoker-Augmentation','DemonHunter-Havoc','Priest-Holy','Mage-Frost','Hunter-Survival','Unknown-Unknown','Warlock-Demonology','DeathKnight-Unholy','Druid-Restoration','Druid-Feral','Druid-Balance','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Priest-Shadow','Druid-Guardian','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Vengeance','Warrior-Protection','Priest-Discipline','Mage-Arcane','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm="Jubei'Thos",name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abaoaqu:BAAALgAECgEJBAAAAA==.Abelas:BAACLgAFFH8HAAIBAAQJ9CG0BwBYAQABAAQJ9CG0BwBYAQAuAAQKfxUAAgEACAk+IzIMALkCAAEACAk+IzIMALkCAAEuAAUUCAkdAAIAEh8A.Abemonkey:BAABLgAFFH8dAAICAAgJEh9mAgC0AgACAAgJEh9mAgC0AgAAAA==.Abuden:BAAALgAECgEJAgAAAA==.',
Ac='Actaeus:BAABLgAECn8XAAMDAAcJ+ht1LAABAgADAAYJQxx1LAABAgAEAAQJMRRJWADlAAAAAA==.Activion:BAAALgAECgYJBAAAAA==.',
Ad='Addelana:BAACLgAFFH8JAAIFAAQJdgXBMwDdAAAFAAQJdgXBMwDdAAAuAAQKfx4AAwUACQlKEd81AKwBAAUACQlKEd81AKwBAAYABwkDDRM8ABUBAAAA.Adelyda:BAAALgAECgQJCAAAAA==.Adrasta:BAABLgAECn8VAAMHAAYJBw8+DgAjAQAHAAYJBw8+DgAjAQAIAAMJswGOVgBzAAAAAA==.',
Ae='Aedrius:BAAALgAECgEJAQAAAA==.Aelador:BAAALgADCgMJBAAAAA==.Aelathe:BAAALgAECgEJAQAAAA==.Aerys:BAAALgAECgEJAQAAAA==.',
Af='Afewbeerz:BAAALgADCgMJAwAAAA==.Africandrake:BAAALgADCgYJBgAAAA==.',
Ah='Ahnkori:BAAALgAECgIJAgAAAA==.Ahnoose:BAAALgAECgUJBQAAAA==.',
Ai='Aifik:BAAALgAECgIJAgAAAA==.',
Ak='Akey:BAABLgAECn83AAIDAAkJUgx0RQClAQADAAkJUgx0RQClAQAAAA==.Akiller:BAAALgAECgMJBQAAAA==.',
Al='Alamal:BAAALgAECgEJAQAAAA==.Alamwah:BAACLgAFFH8QAAIJAAUJgR6cIQBhAQAJAAUJgR6cIQBhAQAuAAQKfyYAAgkACAmxGQwuAEQCAAkACAmxGQwuAEQCAAAA.Alanaz:BAAALgAECgcJCwAAAA==.Alaroo:BAAALgAECgYJCgAAAA==.Albinoslug:BAAALgADCgUJBQAAAA==.Aleine:BAABLgAECn9gAAIKAAkJHxVLCwDmAQAKAAkJHxVLCwDmAQAAAA==.Aleio:BAAALgAECgIJAgAAAA==.Alektra:BAABLgAECn8aAAILAAkJlAw3CgByAQALAAkJlAw3CgByAQAAAA==.Alessi:BAAALgAECgYJCAAAAA==.Alexrose:BAAALgADCgcJBwAAAA==.Aliq:BAAALgAECgEJAQAAAA==.Alliete:BAAALgAECgEJAQABLgAECggJGQAMAMkMAA==.Alliyah:BAAALgAECgEJAgABLgAECgkJFQANAO4BAA==.Aloine:BAABLgAECn8tAAIOAAkJmwbLLwArAQAOAAkJmwbLLwArAQAAAA==.Alphonze:BAAALgAECgIJAgAAAA==.Alynne:BAABLgAECn8VAAIPAAcJHAw9jABDAQAPAAcJHAw9jABDAQAAAA==.',
Am='Amelior:BAAALgADCgIJAgAAAA==.Amogus:BAAALgAECgkJDAAAAA==.Amorallan:BAAALgAECgQJBAAAAA==.Ampuzzible:BAABLgAECn8tAAIOAAkJwxr+DQBfAgAOAAkJwxr+DQBfAgAAAA==.',
An='Andju:BAAALgADCgMJAwAAAA==.Anhedonias:BAAALgAECgcJAQAAAA==.Animism:BAAALgADCgUJBQAAAA==.Anivar:BAAALgADCgcJBwAAAA==.Anneke:BAAALgADCgMJAwABLgAECggJGQAMAMkMAA==.Antakeassing:BAAALgAECgUJCgAAAA==.Anyá:BAABLgAECn8nAAIQAAgJuwnpHwB9AQAQAAgJuwnpHwB9AQAAAA==.',
Ar='Arbitera:BAABLgAECn8zAAICAAkJ2yGqAwBZAwACAAkJ2yGqAwBZAwAAAA==.Arcaneth:BAAALgADCggJCAAAAA==.Arcette:BAAALgADCgkJHQAAAA==.Archmystique:BAABLgAECn8wAAIPAAcJ8xncfgDTAQAPAAcJ8xncfgDTAQAAAA==.Arcthane:BAAALgADCgQJBAABLgADCgkJHQARAAAAAA==.Arkona:BAABLgAECn8UAAIOAAYJyBlUIgDRAQAOAAYJyBlUIgDRAQAAAA==.Arkzart:BAAALgAECgQJBAAAAA==.Arrogant:BAAALgAFFAEJAQAAAA==.',
As='Asanath:BAAALgADCgkJDwAAAA==.Asdf:BAAALgAECgEJAQAAAA==.Ashley:BAABLgAECn8zAAIDAAkJMSSkBgALAwADAAkJMSSkBgALAwAAAA==.Ashryveris:BAAALgAECgYJEwAAAA==.Asmonjoel:BAAALgAECgMJBgAAAA==.Assumi:BAABLgAECn8dAAISAAYJtAsGkwAAAQASAAYJtAsGkwAAAQAAAA==.',
At='Ataturk:BAAALgAECgUJDAAAAA==.Athenis:BAAALgAECgcJDgAAAA==.Atka:BAAALgADCgcJBwAAAA==.Atumor:BAABLgAFFH8FAAITAAQJRwyzWAAdAQATAAQJRwyzWAAdAQAAAA==.',
Au='Audree:BAAALgADCgMJAwAAAA==.Augiediaz:BAAALgAECgcJDAAAAA==.Auraine:BAAALgAECggJDgAAAA==.Aurelionn:BAAALgAECgEJAgAAAA==.',
Av='Avadacadavra:BAAALgADCgUJBwABLgAFFAIJAgARAAAAAA==.',
Ax='Axonpredator:BAAALgADCgEJAQAAAA==.',
Az='Azamat:BAAALgAECggJCQAAAA==.Azazêll:BAABLgAECn8bAAILAAgJ8A08DgAuAQALAAgJ8A08DgAuAQAAAA==.Azidian:BAAALgADCgEJAQAAAA==.Azmodais:BAAALgAECgIJAgAAAA==.Azuredemonx:BAABLgAECn8/AAIJAAgJERywIwAjAgAJAAgJERywIwAjAgAAAA==.Azurgosa:BAAALgADCgUJBQAAAA==.',
Ba='Baagul:BAAALgAECgUJCgAAAA==.Badheals:BAACLgAFFH8GAAIUAAMJTQiCOACxAAAUAAMJTQiCOACxAAAuAAQKfygABBQACQmkFdgoABACABQACQmkFdgoABACABUAAgllB6AvAGEAABYAAwlDBt1oAE4AAAAA.Bailough:BAAALgAECgIJBgAAAA==.Balfin:BAAALgADCggJCAAAAA==.Balid:BAAALgADCggJCQAAAA==.Banan:BAAALgAECgYJCgAAAA==.Bartelle:BAAALgADCgEJAQAAAA==.Bazaseal:BAAALgAECgUJBwAAAA==.',
Bb='Bbqporkbuns:BAACLgAFFH8NAAIXAAMJ/hhBCADvAAAXAAMJ/hhBCADvAAAuAAQKfykAAhcACQkvG7MDAPACABcACQkvG7MDAPACAAAA.',
Be='Beauranged:BAAALgAECgIJAgAAAA==.Bece:BAAALgADCgcJDgAAAA==.Beefcakes:BAAALgADCgEJAQAAAA==.Beenafflictn:BAAALgADCgEJAQAAAA==.Beerpong:BAABLgAECn8YAAMYAAYJtBB7PAAqAQAYAAYJfw17PAAqAQAZAAYJ3ArxTwAEAQABLgAECgkJIwADAP0eAA==.Belevie:BAAALgAECgYJEQABLgAECgkJQgAMABsOAA==.Bellanoth:BAABLgAECn8cAAQaAAkJfQYwFgBFAQAaAAkJfQYwFgBFAQAMAAgJIwl1NwAoAQAbAAIJYwUdJAAkAAAAAA==.Belledormi:BAABLgAECn9CAAQMAAkJGw6aIwCdAQAMAAkJGw6aIwCdAQAaAAEJDwc0OAAlAAAbAAEJ5QFXRQAhAAAAAA==.Bellfurion:BAAALgAECgQJCgAAAA==.Belltree:BAAALgADCgIJAgAAAA==.Bendyendy:BAAALgADCgYJBwAAAA==.',
Bf='Bfev:BAACLgAFFH8FAAIIAAIJWiB9IwCuAAAIAAIJWiB9IwCuAAAuAAQKfyYAAggACQmKHVQJAG0CAAgACQmKHVQJAG0CAAAA.',
Bg='Bggestthighs:BAAALgAECgcJCAABLgAECgkJKwAQACAZAA==.',
Bh='Bhad:BAAALgADCgMJAwAAAA==.',
Bi='Bid:BAABLgAECn8pAAIDAAkJQB27IgAuAgADAAkJQB27IgAuAgAAAA==.Bierfiendx:BAAALgAECgEJAQAAAA==.Bify:BAAALgADCgYJCAAAAA==.Bigalo:BAABLgAECn8qAAIQAAkJbBLjEgD2AQAQAAkJbBLjEgD2AQAAAA==.Bigcogg:BAAALgAFFAIJBAAAAA==.Bigdikbusta:BAABLgAFFH8GAAIcAAMJPCHgMQArAQAcAAMJPCHgMQArAQAAAA==.Biggesthighz:BAABLgAECn8rAAIQAAkJIBlTBwCRAgAQAAkJIBlTBwCRAgAAAA==.Bigjer:BAACLgAFFH8TAAIdAAUJ3x62DwBWAQAdAAUJ3x62DwBWAQAuAAQKfyUAAh0ACQlhH3QSALwCAB0ACQlhH3QSALwCAAAA.Biglee:BAAALgAECgEJAwAAAA==.Bigzugg:BAAALgAECgEJAQAAAA==.Bird:BAACLgAFFH8IAAMaAAQJnRcsEgA5AQAaAAQJnRcsEgA5AQAMAAEJjCE1HwBXAAAuAAQKfyAAAwwACAk0IekNAJYCAAwACAk0IekNAJYCABoACAk6GUsMAOoBAAAA.',
Bl='Blaisy:BAABLgAECn8wAAIOAAkJfxezEAA7AgAOAAkJfxezEAA7AgAAAA==.Blakdynamite:BAAALgAECgQJBwAAAA==.Blayx:BAAALgADCgQJBAABLgAECgcJHwAPAEAkAA==.Blerdsterm:BAABLgAECn8zAAMeAAkJjx/+BACcAgAeAAkJ5x3+BACcAgAdAAcJ+x9XIQBJAgAAAA==.Blitzz:BAAALgAECgQJBAAAAA==.Blueragebar:BAAALgAECgEJAQAAAA==.',
Bo='Bofà:BAACLgAFFH8JAAIJAAQJ9hoaKQBCAQAJAAQJ9hoaKQBCAQAuAAQKfx0AAgkACAn+I9AKANsCAAkACAn+I9AKANsCAAAA.Boogeyman:BAABLgAECn8UAAILAAcJoAeqGgCwAAALAAcJoAeqGgCwAAAAAA==.Boohbooh:BAAALgADCgUJBQAAAA==.Borgnine:BAABLgAECn8cAAIYAAkJxxJsFgDaAQAYAAkJxxJsFgDaAQAAAA==.',
Br='Brannie:BAABLgAECn8zAAIfAAkJzAdOKABjAQAfAAkJzAdOKABjAQAAAA==.Brenine:BAABLgAECn8zAAQVAAgJehmkDAC4AQAVAAcJ6RSkDAC4AQAWAAcJIBW5JwBhAQAgAAYJuASxSABJAAAAAA==.Brewdaddy:BAAALgAECgEJAQAAAA==.Brewskie:BAAALgAECgEJAQAAAA==.Brila:BAAALgAECgkJDgAAAA==.Britneyfears:BAAALgAECgcJBQABLgAECgkJBgARAAAAAA==.Brodess:BAACLgAFFH8UAAIGAAUJ4yO5CwCNAQAGAAUJ4yO5CwCNAQAuAAQKfzEAAgYACQmcJMEBAFEDAAYACQmcJMEBAFEDAAAA.Brody:BAABLgAECn8oAAIJAAkJnh73DwCnAgAJAAkJnh73DwCnAgAAAA==.Bromorc:BAAALgAECgIJBAAAAA==.Brox:BAAALgAECgMJBgAAAA==.',
Bs='Bse:BAAALgADCgYJBgAAAA==.',
Bu='Bubbleo:BAAALgAECgEJAgAAAA==.Budholy:BAAALgAECgEJAwAAAA==.Buggyboi:BAAALgADCgMJAwABLgAFFAYJHwAUAG8fAA==.Buggyhealz:BAACLgAFFH8fAAIUAAYJbx8GBgBHAgAUAAYJbx8GBgBHAgAuAAQKfzQAAhQACQkgJRUEAGUDABQACQkgJRUEAGUDAAAA.Bulimio:BAAALgAECgIJAwAAAA==.Bungeye:BAAALgAECgEJAQAAAA==.Bunzbunnie:BAAALgAECgYJEQAAAA==.Bunzbunny:BAAALgAECgQJCQAAAA==.Buratt:BAAALgAECgIJBAAAAA==.Burtmonklin:BAABLgAECn8iAAIZAAkJDSXvAwDzAgAZAAkJDSXvAwDzAgAAAA==.Busdriver:BAACLgAFFH8UAAITAAUJxByHOABSAQATAAUJxByHOABSAQAuAAQKfyEAAhMACQk1IesmAEQCABMACQk1IesmAEQCAAAA.Buster:BAAALgAECgEJAQAAAA==.Busterr:BAAALgAECgQJCwAAAA==.',
Ca='Cakee:BAAALgAECgcJBwAAAA==.Caleroice:BAAALgAECgcJDgAAAA==.Capacitør:BAABLgAECn8pAAIGAAkJHSDMCgCPAgAGAAkJHSDMCgCPAgAAAA==.Cardib:BAABLgAECn9IAAQSAAgJDCN0MwDzAQASAAYJYSN0MwDzAQALAAYJ4htcGgB6AQAhAAEJAAArIABxAAAAAA==.Cartier:BAAALgADCgYJBgAAAA==.Cattabloom:BAAALgAECgEJAwAAAA==.Cattakai:BAAALgAECgEJAQAAAA==.Cattazap:BAACLgAFFH8PAAMFAAQJkh58FwBjAQAFAAQJkh58FwBjAQAGAAEJgwSGQwA7AAAuAAQKfyYAAwUACQk9Iz8EADADAAUACQk9Iz8EADADAAYAAwm8CwF5AF8AAAAA.',
Ce='Ceefu:BAABLgAFFH8LAAICAAYJwhqZCgDnAQACAAYJwhqZCgDnAQAAAA==.Celtic:BAAALgAECgcJAQAAAA==.Cerran:BAAALgAECgEJAQAAAA==.',
Ch='Chaengrang:BAAALgAFFAEJAQABLgAFFAcJJgAiAKQfAA==.Chakrakhan:BAABLgAECn8jAAIYAAkJqhHtGADAAQAYAAkJqhHtGADAAQAAAA==.Char:BAABLgAECn8WAAMLAAYJqxsIDABQAQALAAYJqxsIDABQAQASAAEJiRc1BgE+AAAAAA==.Chase:BAABLgAECn8nAAIeAAgJNR/TCQAlAgAeAAgJNR/TCQAlAgAAAA==.Chayang:BAAALgAECggJDgAAAA==.Cherryqueque:BAAALgAFFAIJAgAAAA==.Chopzuey:BAAALgADCgYJCAAAAA==.Chugtiki:BAABLgAECn83AAMFAAkJSh4YCwDeAgAFAAkJSh4YCwDeAgAGAAgJnhMYLwBXAQAAAA==.',
Ci='Cinderaz:BAAALgAECgIJBAAAAA==.Ciyus:BAAALgAECgYJCAAAAA==.',
Cl='Clann:BAABLgAECn8bAAQhAAcJoA1BEAAmAQAhAAYJIQ9BEAAmAQALAAUJOgceIACFAAASAAUJ2wWW2gB6AAAAAA==.Clarissahh:BAAALgAECgUJDgAAAA==.',
Co='Cones:BAAALgAECgIJAwAAAA==.Coolrunnins:BAABLgAECn8dAAIVAAkJTRo5BQB1AgAVAAkJTRo5BQB1AgAAAA==.Coolwhip:BAAALgAECgMJDQAAAA==.Coquin:BAAALgADCgEJAwAAAA==.Coquina:BAAALgAECgUJDQAAAA==.Cordeilia:BAACLgAFFH8XAAIOAAUJaRjtCACBAQAOAAUJaRjtCACBAQAuAAQKf0EAAg4ACQkBIcUDADQDAA4ACQkBIcUDADQDAAAA.Corgoan:BAAALgAECgEJAQAAAA==.Cosmi:BAAALgAECgYJDwABLgAFFAMJAwARAAAAAQ==.Costiigan:BAAALgAECgYJDwAAAA==.',
Cr='Criznara:BAAALgAECgcJCwAAAA==.Crowlie:BAAALgAECgkJCwAAAA==.Cruxxi:BAACLgAFFH8HAAISAAUJCQ6xIgB1AQASAAUJCQ6xIgB1AQAuAAQKfygAAxIACQk9H+wRAKYCABIACQk9H+wRAKYCAAsABAlYHEIkADgBAAAA.',
Cu='Curthill:BAAALgAECgQJBgAAAA==.',
Cx='Cxaxukluth:BAAALgAECgYJDAABLgAFFAMJAwARAAAAAQ==.',
Cy='Cyberdots:BAAALgAECgYJBQAAAA==.Cyenthea:BAABLgAECn8UAAMBAAcJiyMeFwBZAgABAAYJQiQeFwBZAgAcAAcJdR8nTgD4AQABLgAFFAgJHQAJABIdAA==.Cygeance:BAAALgADCgYJCQAAAA==.Cyklar:BAAALgAECgIJBAAAAA==.Cyphren:BAAALgAECgYJDwAAAA==.Cyrias:BAAALgADCgUJBQAAAA==.',
Da='Dacaille:BAAALgAECgYJCAAAAA==.Daddysouls:BAAALgAECgcJBwAAAA==.Dadingding:BAAALgAECgcJEgAAAA==.Damnflanders:BAABLgAECn8cAAIjAAkJHQv+DABbAQAjAAkJHQv+DABbAQAAAA==.Dankozdravic:BAAALgAECgQJBwAAAA==.Daqueta:BAAALgAECggJEgAAAA==.Daquetamk:BAAALgAECgUJCAAAAA==.Daquetapl:BAAALgAECgUJCAAAAA==.Daquetawar:BAAALgAECgQJBgAAAA==.Darkniggura:BAABLgAECn8WAAIPAAgJJQ8+kgA4AQAPAAgJJQ8+kgA4AQAAAA==.Darknstormy:BAAALgAECgUJDwAAAA==.Darkpal:BAABLgAFFH8HAAIcAAMJqRJXSADyAAAcAAMJqRJXSADyAAABLgAFFAQJBQATAEcMAA==.Darkskye:BAAALgAECggJDgAAAA==.Darthbane:BAAALgAECgQJBAAAAA==.Dazer:BAAALgAECgcJEAAAAA==.Dazgrim:BAAALgAECgQJAwABLgAECgYJDQARAAAAAA==.Daznum:BAAALgAECgQJBAABLgAECgYJDQARAAAAAA==.Dazrawr:BAAALgADCgEJAQABLgAECgYJDQARAAAAAA==.',
De='Deadlobster:BAAALgADCgcJBwAAAA==.Deadlyfreak:BAAALgAFFAEJAgAAAA==.Deadnick:BAAALgAECggJCgAAAA==.Deathax:BAAALgADCggJDwAAAA==.Deathcerby:BAAALgADCgIJAgAAAA==.Deathicus:BAABLgAECn8lAAIcAAkJ0gVekAAxAQAcAAkJ0gVekAAxAQAAAA==.Decapitation:BAACLgAFFH8PAAIDAAMJSyN3CwAGAQADAAMJSyN3CwAGAQAuAAQKfzYAAgMACQlOJPsGAAcDAAMACQlOJPsGAAcDAAAA.Deify:BAABLgAECn8dAAMGAAYJ4xxpLABmAQAGAAYJ4xxpLABmAQAFAAEJlQ19ngAyAAAAAA==.Deifyh:BAAALgAECgMJAwAAAA==.Deliaz:BAAALgAECgIJBAAAAA==.Deltaz:BAAALgADCgEJAQAAAA==.Demønknight:BAAALgADCgkJCQAAAA==.Derek:BAAALgADCgIJAgAAAA==.Devoidh:BAABLgAECn8rAAIkAAkJtx+RAgDMAgAkAAkJtx+RAgDMAgAAAA==.Devya:BAAALgADCgYJBgAAAA==.',
Di='Dinadan:BAAALgAECgMJAwABLgAECgkJKgAkADkRAA==.Dindu:BAAALgAECgEJAQAAAA==.Dirge:BAAALgADCgcJFQAAAA==.Dirtybob:BAAALgAECgUJBgAAAA==.Disastros:BAAALgAECgQJBgAAAA==.Discosisqo:BAAALgAECgYJEgAAAA==.Divinebeef:BAAALgAECgEJAgAAAA==.',
Dj='Djapana:BAABLgAECn8XAAIIAAYJ1xJlMACDAQAIAAYJ1xJlMACDAQAAAA==.Djavolo:BAAALgAECgIJAwAAAA==.',
Dk='Dkkotni:BAAALgAECgUJBQAAAA==.',
Dn='Dnomm:BAAALgAECgIJBAAAAA==.',
Do='Dodjy:BAAALgAECgQJEAAAAA==.Donussy:BAAALgADCgMJAwAAAA==.Doomcannon:BAAALgAECgcJCAAAAA==.Dopeyplane:BAAALgAECgIJAgAAAA==.Dowob:BAAALgAFFAIJAwABLgAFFAIJBwATANIdAA==.',
Dr='Dracheal:BAAALgAECgEJAQAAAA==.Dracknstoob:BAABLgAECn8qAAQaAAkJZw9+DgDCAQAaAAkJZw9+DgDCAQAbAAIJGAfRGgBXAAAMAAIJwgTZdQBDAAAAAA==.Dragidy:BAAALgADCgQJBAAAAA==.Dragondaddy:BAAALgADCgUJBQAAAA==.Dragonfyre:BAAALgADCgEJAQAAAA==.Dragongirlqt:BAAALgAECgEJAQABLgAECgkJMwAKANwdAA==.Drasani:BAAALgAECgUJBQAAAA==.Dreaddlord:BAAALgAECgYJDgABLgAECgkJDgARAAAAAA==.Dreadiedude:BAABLgAECn8yAAIWAAkJ3BPGFgDuAQAWAAkJ3BPGFgDuAQAAAA==.Drowlie:BAAALgADCgMJBAABLgAECggJFQABACwiAA==.Drpwnface:BAAALgADCgUJBQAAAA==.',
Dt='Dtree:BAAALgAFFAEJAwAAAA==.',
Du='Duardin:BAAALgAECgIJAgAAAA==.Dureth:BAAALgAECgIJAgAAAA==.Durrin:BAAALgAECggJCgAAAA==.Dusktoday:BAAALgAECgEJAgAAAA==.Dutchman:BAACLgAFFH8HAAIXAAQJcQSqBwAAAQAXAAQJcQSqBwAAAQAuAAQKfyoAAhcACAmwFUcLAMoBABcACAmwFUcLAMoBAAAA.',
Dw='Dwaka:BAECLgAFFH8rAAMMAAgJjx6rAQDVAgAMAAgJUR6rAQDVAgAbAAUJ5SKHAADiAQAuAAQKfxwAAxsACAlPJIQHAHMCABsABgnEJYQHAHMCAAwACAlYIQsVABICAAEuAAUUCAkwAAwA8SMA.',
['Dë']='Dëathvader:BAAALgAECgQJBAAAAA==.',
['Dø']='Døden:BAABLgAECn8bAAIjAAgJuRVsCgCRAQAjAAgJuRVsCgCRAQAAAA==.',
Eb='Ebonflow:BAAALgADCgQJBAAAAA==.',
Ed='Edgestreak:BAAALgAECgEJAQAAAA==.Edricas:BAAALgAECgEJAQAAAA==.',
Ei='Eio:BAAALgAECgEJAgAAAA==.',
El='Eleice:BAAALgAECgIJAgAAAA==.Elele:BAAALgAECgYJDAAAAA==.Eleshock:BAACLgAFFH8QAAIFAAYJTR6YBwD8AQAFAAYJTR6YBwD8AQAuAAQKfxYAAgUACAnTHa4PAJoCAAUACAnTHa4PAJoCAAAA.Elizan:BAAALgAECgQJBAAAAA==.Ellell:BAAALgAECggJDwAAAA==.Ellieb:BAABLgAECn8zAAIWAAkJUxfdDgBGAgAWAAkJUxfdDgBGAgAAAA==.Ellinah:BAAALgAECgcJDQABLgAFFAMJCQAFAHAWAA==.Elodina:BAAALgADCgYJCQAAAA==.Elshaddai:BAABLgAECn8XAAMcAAcJHA2ajgA0AQAcAAcJHA2ajgA0AQAKAAEJ4AeQTAAaAAAAAA==.Elwynrind:BAAALgADCgkJCAAAAA==.',
Em='Emsulquiorra:BAACLgAFFH8FAAIPAAMJ5Aa5bwDUAAAPAAMJ5Aa5bwDUAAAuAAQKfxYAAg8ACAkrHDdJAOQBAA8ACAkrHDdJAOQBAAAA.',
En='Endersfault:BAACLgAFFH8IAAIlAAIJviGMFwC0AAAlAAIJviGMFwC0AAAuAAQKfzAAAiUACQkDI4kCAAQDACUACQkDI4kCAAQDAAAA.Englaived:BAAALgAECgUJEgAAAA==.Enmebaragesi:BAAALgAECggJEQAAAA==.Enve:BAABLgAECn8VAAMJAAcJNgyvngC6AAANAAUJrgsFSQDOAAAJAAYJoAmvngC6AAABLgAECgkJFQATAIgQAA==.',
Eo='Eomar:BAAALgAECgEJAQAAAA==.',
Ep='Epicdemoness:BAAALgAFFAIJAgAAAA==.',
Er='Eremano:BAAALgAECgQJCgAAAA==.',
Es='Esshhayy:BAAALgAECgEJAQAAAA==.',
Eu='Euphea:BAAALgAECgUJCAAAAA==.Euustace:BAABLgAECn8WAAMJAAYJXRECcwAVAQAJAAYJXRECcwAVAQANAAEJ1wBrZwAPAAAAAA==.',
Ev='Evokunt:BAAALgADCgEJAQAAAA==.',
Ex='Extintion:BAACLgAFFH8MAAITAAQJcgiRXAAVAQATAAQJcgiRXAAVAQAuAAQKfzMAAhMACQlXGaUhAF4CABMACQlXGaUhAF4CAAAA.Extratusks:BAAALgAECgEJAQAAAA==.',
Fa='Faartwizard:BAAALgAECgUJDAAAAA==.Fabe:BAEBLgAECn8/AAIQAAgJUh+CDABCAgAQAAgJUh+CDABCAgAAAA==.Falion:BAACLgAFFH8QAAIOAAUJgRjaAwBQAQAOAAUJgRjaAwBQAQAuAAQKfzIAAw4ACQm2IAYIAMsCAA4ACQm2IAYIAMsCACYAAQnnBkBYADEAAAAA.Fanks:BAAALgAECgMJAwABLgAECgkJFQATAIgQAA==.Fanny:BAAALgADCgEJAQAAAA==.Farkq:BAAALgADCgUJBQAAAA==.Farseer:BAABLgAECn8ZAAIGAAcJER2fLAC0AQAGAAcJER2fLAC0AQAAAA==.Fatchina:BAAALgAECgYJBgAAAA==.Fatpandah:BAAALgAECgQJBgAAAA==.Fatrider:BAABLgAECn80AAIcAAkJQBddNQAKAgAcAAkJQBddNQAKAgAAAA==.',
Fe='Feelsgoodman:BAAALgADCgMJAwAAAA==.Fefetux:BAAALgADCgcJBwAAAA==.Felburn:BAAALgAECgcJDwAAAA==.Felicia:BAABLgAECn8pAAINAAkJeiMEAgArAwANAAkJeiMEAgArAwAAAA==.Fellordkiki:BAAALgAECgkJEwAAAA==.Fenrig:BAEBLgAECn8YAAIlAAYJKhAxIQA1AQAlAAYJKhAxIQA1AQABLgAECggJJwAZAN4QAA==.Ferakus:BAAALgAECgEJAQABLgAFFAQJEwAMANAQAA==.Ferrante:BAACLgAFFH8JAAITAAMJigdGgwDOAAATAAMJigdGgwDOAAAuAAQKfzoAAhMACQkBEDhIAMcBABMACQkBEDhIAMcBAAAA.',
Fi='Figwigs:BAABLgAECn8hAAIPAAgJDBEYZgCUAQAPAAgJDBEYZgCUAQAAAA==.Filthymaje:BAAALgAECgIJAQAAAA==.Filthypally:BAACLgAFFH8VAAIcAAUJayRLDACxAQAcAAUJayRLDACxAQAuAAQKf0UAAhwACQlRJnIBAHoDABwACQlRJnIBAHoDAAAA.Fishetbek:BAAALgAECgQJBAAAAA==.Fishingbot:BAAALgADCgEJAQAAAA==.Fister:BAAALgADCgIJAgABLgAECgQJBAARAAAAAA==.Fistymonky:BAAALgADCgQJBgAAAA==.Fivëam:BAABLgAECn8iAAMnAAkJnx7mAgBWAgAnAAgJWR/mAgBWAgAPAAkJThjZLABIAgAAAA==.',
Fl='Flashheart:BAABLgAECn8XAAIcAAYJRBeNfQBTAQAcAAYJRBeNfQBTAQAAAA==.Flashnlights:BAAALgAECggJEAAAAA==.Fletchers:BAAALgAECgYJDQAAAA==.',
Fo='Fohgoh:BAAALgAFFAMJAwAAAA==.Foodoom:BAAALgAECgYJBgAAAA==.',
Fr='Fraerel:BAAALgAECgEJAQAAAA==.Fraktured:BAAALgAECgEJAQAAAA==.Françoise:BAAALgADCggJDAABLgAECgUJBQARAAAAAA==.Freezefauker:BAABLgAECn8rAAIPAAkJZBNPPwADAgAPAAkJZBNPPwADAgAAAA==.Fridge:BAABLgAECn8oAAIPAAkJ2yALGgCjAgAPAAkJ2yALGgCjAgAAAA==.Frobrew:BAAALgADCgIJAQAAAA==.Frostsmash:BAABLgAECn8VAAMjAAgJyB7yAQC9AgAjAAgJyB7yAQC9AgAiAAEJ5AL2TwAVAAAAAA==.Frostxfury:BAABLgAECn87AAITAAgJdyOMFQClAgATAAgJdyOMFQClAgAAAA==.Frostybunz:BAAALgAECgEJAwAAAA==.Frostyshiver:BAABLgAECn8rAAIPAAgJpSBfIgB4AgAPAAgJpSBfIgB4AgABLgAFFAQJCQAJAPYaAA==.Frósty:BAAALgAECgcJCAAAAA==.Frøstynips:BAACLgAFFH84AAMjAAgJchlQAQDHAQAjAAYJAxtQAQDHAQATAAcJgRnXBQCmAQAuAAQKf08AAxMACQnhJUoHAGcDABMACQnhJUoHAGcDACMACAnFIp0DAGgCAAAA.',
Fu='Funkymunky:BAAALgAECgMJAgAAAA==.Furrbulous:BAAALgADCgIJAgAAAA==.Furysgrip:BAACLgAFFH8MAAIiAAQJTAdIHADGAAAiAAQJTAdIHADGAAAuAAQKfyMAAiIACAmdE6UeAC8BACIACAmdE6UeAC8BAAAA.',
Fy='Fyre:BAAALgADCgcJCwAAAA==.',
['Fí']='Fírnen:BAAALgAECgMJAwAAAA==.',
['Fú']='Fúnk:BAABLgAECn8sAAQQAAkJMBSLFgDRAQAQAAkJ5AuLFgDRAQADAAcJHxcRZgBKAQAEAAEJqQIXlgAjAAAAAA==.',
Ga='Gaara:BAAALgAECgQJBAAAAA==.Galedrial:BAAALgADCgEJAQAAAA==.Garaktou:BAAALgAECgEJAQAAAA==.Garius:BAACLgAFFH8GAAIcAAMJiRCHUwDaAAAcAAMJiRCHUwDaAAAuAAQKfxsAAhwACQlNHscaAMkCABwACQlNHscaAMkCAAAA.Gartah:BAAALgADCgIJAgABLgAECgQJBAARAAAAAA==.Garthception:BAAALgAECgUJBQAAAA==.Gashweaver:BAAALgAECgMJAQAAAA==.',
Ge='Gentlegiantt:BAACLgAFFH8TAAIWAAQJQxq3EgBKAQAWAAQJQxq3EgBKAQAuAAQKfzMAAxYACQmNIhQDACEDABYACQmNIhQDACEDACAAAQkAAGIwADQAAAAA.Gentlemonstr:BAAALgAFFAEJAQAAAA==.',
Gh='Ghood:BAAALgADCgMJAwAAAA==.',
Gi='Gigit:BAAALgAECgYJEwAAAA==.Giji:BAABLgAECn8lAAMFAAgJbRAeNQCsAQAFAAgJbRAeNQCsAQAGAAcJPBW2LgBZAQAAAA==.Gingersnapss:BAAALgAECgYJEgAAAA==.Girlsdayoni:BAAALgADCgcJBwAAAA==.Girlsnight:BAAALgADCgYJBgAAAA==.',
Gl='Glizzyblasta:BAAALgADCgcJBwAAAA==.',
Gn='Gnimble:BAABLgAECn8bAAICAAkJ5hlkHAD0AQACAAkJ5hlkHAD0AQAAAA==.Gnuh:BAAALgAECgEJAQABLgAECgQJCAARAAAAAA==.',
Go='Gohan:BAABLgAECn8SAAIDAAYJ1x9qUgBxAQADAAYJ1x9qUgBxAQAAAA==.Goku:BAAALgAECgMJBgABLgAECggJEgADANcfAA==.Gommo:BAABLgAFFH8HAAIcAAMJigZUVwDPAAAcAAMJigZUVwDPAAAAAA==.Gooblento:BAABLgAECn81AAIcAAkJaRvLHQB1AgAcAAkJaRvLHQB1AgAAAA==.Gorbad:BAABLgAECn8hAAMdAAkJcAgWPQApAQAdAAcJJwkWPQApAQAeAAUJGwcLMADXAAAAAA==.Gotwood:BAAALgAECggJAwAAAA==.',
Gr='Grahamington:BAABLgAECn8WAAIPAAYJzQYD0gDOAAAPAAYJzQYD0gDOAAAAAA==.Grandmaster:BAAALgAECgcJDwAAAA==.Grapes:BAAALgAECgcJEwAAAA==.Grayfang:BAAALgADCgYJAQAAAA==.Greatranger:BAAALgAECgMJAwAAAA==.Grimmic:BAAALgADCgIJAgAAAA==.Grooveygoog:BAAALgAECgUJBQAAAA==.Groovywar:BAAALgAECgIJAgAAAA==.Groundizzle:BAACLgAFFH8HAAIOAAMJqga6HACmAAAOAAMJqga6HACmAAAuAAQKfyUAAg4ACAloGtQSAB8CAA4ACAloGtQSAB8CAAAA.',
Gu='Guineamon:BAABLgAECn8eAAMmAAgJnxLnHgCoAQAmAAgJnxLnHgCoAQAOAAEJcwTohAAsAAAAAA==.',
Gw='Gwwalker:BAAALgAECgcJCwAAAA==.',
Gz='Gzul:BAAALgAECgEJAgAAAA==.',
['Gô']='Gôof:BAAALgAECgEJAgAAAA==.',
Ha='Haerinm:BAAALgAECgcJDQAAAA==.Hailii:BAAALgADCgcJBwAAAA==.Haj:BAAALgAECgEJAwAAAA==.Hammel:BAAALgAECgkJEwAAAA==.Hanzxo:BAAALgAECgYJBwAAAA==.Harry:BAABLgAECn8rAAIPAAgJxyLdIACAAgAPAAgJxyLdIACAAgAAAA==.Harryrox:BAAALgADCgYJBgAAAA==.Haruk:BAABLgAECn82AAIBAAkJOCIpBAA4AwABAAkJOCIpBAA4AwAAAA==.Hatememore:BAAALgAECgEJBAAAAA==.Hattle:BAAALgAECgIJAgAAAA==.Hazchum:BAAALgADCgQJAgAAAA==.',
He='Healsdead:BAAALgAECgEJAQAAAA==.Heatfist:BAABLgAECn84AAInAAkJ9Q66BQDMAQAnAAkJ9Q66BQDMAQAAAA==.Helldrag:BAAALgAECggJCQAAAA==.Hellhost:BAABLgAECn8mAAMjAAgJDRdrCwB7AQAjAAgJDRdrCwB7AQATAAIJRQNKHwFJAAAAAA==.Hellko:BAAALgAECgQJBAAAAA==.Hertfor:BAAALgAECgYJBwAAAA==.Heåls:BAABLgAECn8oAAIBAAgJFBpUHgAkAgABAAgJFBpUHgAkAgAAAA==.',
Hi='Hisoka:BAAALgAECgQJCwABLgAECgUJDQARAAAAAA==.',
Ho='Hoboface:BAAALgAECggJEAAAAA==.Hoelishock:BAABLgAECn8dAAIBAAkJOCFJBAA2AwABAAkJOCFJBAA2AwAAAA==.Hollynova:BAABLgAECn8jAAMmAAgJXBYfGgDTAQAmAAcJoxgfGgDTAQAOAAEJZgafYgAsAAABLgAECgkJOQAMACIRAA==.Holyheck:BAAALgADCgMJAQAAAA==.Holyreimer:BAAALgADCgcJAwAAAA==.Honeydew:BAACLgAFFH8aAAICAAgJYRTjBQBDAgACAAgJYRTjBQBDAgAuAAQKfx8AAgIACQkLHeQFAAEDAAIACQkLHeQFAAEDAAAA.Hotteemie:BAAALgADCggJEwAAAA==.',
Hr='Hrkx:BAAALgAECgQJBAAAAA==.Hrkz:BAAALgAECgIJAwABLgAECgQJBAARAAAAAA==.',
Hu='Huddson:BAAALgAECgMJBgAAAA==.Humilitatem:BAAALgAECgEJAQAAAA==.',
Hy='Hydrastrider:BAAALgADCgEJAgAAAA==.Hydraxius:BAAALgAECgEJAgAAAA==.Hylingaar:BAAALgADCgQJBgABLgAECgYJBwARAAAAAA==.Hyoinmaru:BAAALgADCgEJAQAAAA==.',
['Hâ']='Hârry:BAAALgAECggJCAAAAA==.',
Ia='Iamokuz:BAAALgAFFAEJAQAAAA==.',
Ic='Icevoker:BAECLgAFFH8WAAMbAAQJuRYGBQD2AAAbAAMJ5RcGBQD2AAAMAAIJ1hQ7PgCMAAAuAAQKfz0ABBsACQljH8ICAP8CABsACAkWIMICAP8CAAwAAgkAEWRkAHoAABoAAQlNA/FKACwAAAAA.Iceyq:BAAALgAECgQJBwAAAA==.Icysoul:BAAALgAECgkJCgABLgAFFAMJAwARAAAAAA==.',
If='Ifloat:BAAALgAECgYJBgABLgAECggJGgAkAHQbAA==.',
Ig='Igni:BAAALgAECgcJEQAAAA==.',
Ii='Iilliidann:BAAALgADCgEJAQAAAA==.',
Il='Ilioa:BAAALgADCggJGwAAAA==.',
Im='Immortus:BAAALgADCgUJBQABLgAECgcJAgARAAAAAA==.Impetus:BAAALgAECgQJBAABLgAFFAEJAQARAAAAAA==.Imsteve:BAAALgAECgQJCwAAAA==.Imugi:BAABLgAECn8ZAAIMAAgJyQyNKQByAQAMAAgJyQyNKQByAQAAAA==.',
In='Innarial:BAAALgAECgMJAQABLgAFFAMJCQATAIoHAA==.Interia:BAAALgAECgYJEgABLgAECgcJHgAaABIYAA==.Intress:BAAALgADCgIJAgAAAA==.',
Io='Ionsw:BAAALgAECgQJDwAAAA==.',
Ir='Ironski:BAAALgADCgEJAQABLgAECgkJGwATADchAA==.',
Is='Ishgard:BAAALgADCgcJCAAAAA==.Isopentene:BAAALgAECgMJAwAAAA==.',
It='Itchystrasz:BAAALgAECgEJAQAAAA==.',
Iu='Iudex:BAAALgAECgIJAgAAAA==.',
Iv='Ivalace:BAAALgAECgkJAQAAAA==.Ivyoxide:BAAALgAECgYJEgAAAA==.',
Ja='Jacabon:BAAALgADCgQJBwAAAA==.Jackillz:BAABLgAECn8aAAMCAAYJzh1fIQCoAQACAAUJ6R1fIQCoAQAYAAUJpg86OgA0AQAAAA==.Jackpriest:BAAALgAFFAEJAQAAAA==.Jadè:BAAALgADCgYJBwABLgAECgUJCQARAAAAAA==.Jagalr:BAAALgADCgYJBgAAAA==.Jarok:BAAALgAECggJDQAAAA==.',
Jb='Jbhunna:BAAALgAECgUJCwAAAA==.',
Je='Jee:BAABLgAECn8sAAIdAAkJEhAWHwDSAQAdAAkJEhAWHwDSAQAAAA==.Jellypriest:BAAALgAECgEJAQAAAA==.Jenish:BAAALgAECgEJAQAAAA==.Jescon:BAAALgAFFAEJAQAAAA==.Jeteil:BAAALgADCgEJAQABLgAECgkJMwAWAFMXAA==.Jexs:BAAALgAECgUJCQAAAA==.',
Ji='Jiamil:BAAALgAFFAIJBAAAAA==.Jiayu:BAAALgADCgEJAQAAAA==.Jibberwish:BAAALgADCgcJDAABLgAECgkJJwATAEEiAA==.Jics:BAAALgAECgEJAgAAAA==.',
Jo='Johlissa:BAAALgAECgUJBgAAAA==.Johnmaestro:BAAALgAECgcJBgAAAA==.Jojobobo:BAAALgAECgEJAQAAAA==.Jojoburn:BAAALgAECgEJAwAAAA==.Jojokiller:BAAALgAECgEJAgAAAA==.Jojoshock:BAAALgAECgEJAwAAAA==.Jolteon:BAAALgAECgIJBAAAAA==.Jorkin:BAAALgAECgEJAQAAAA==.',
Ju='Juanster:BAAALgADCgcJBwAAAA==.Jubber:BAABLgAECn8nAAMTAAkJQSI/FQCnAgATAAkJQSI/FQCnAgAiAAYJZxlHFADMAQAAAA==.Jumpnglide:BAAALgAECgMJBgAAAA==.Justaliltren:BAAALgAECgkJBwAAAA==.',
Jx='Jxidyn:BAAALgAECgYJDAAAAA==.',
Jy='Jynx:BAABLgAECn80AAIJAAkJKSNgBQAfAwAJAAkJKSNgBQAfAwAAAA==.',
['Jø']='Jøzzy:BAAALgADCgUJBQAAAA==.',
Ka='Kaherd:BAABLgAECn9AAAIdAAgJ3hZzHgDXAQAdAAgJ3hZzHgDXAQAAAA==.Kahora:BAAALgADCgcJCgAAAA==.Kallavan:BAAALgADCgEJAQAAAA==.Kalmonk:BAABLgAECn8yAAMCAAkJaBZNFgArAgACAAkJaBZNFgArAgAZAAIJyQx2ewBXAAAAAA==.Kalmyth:BAAALgADCgYJBgABLgAFFAMJCQAFAHAWAA==.Kaltizdat:BAAALgADCgcJBwABLgAFFAEJAgARAAAAAA==.Karinter:BAAALgAECgIJAwAAAA==.Karytheca:BAAALgADCgUJBQAAAA==.Karâ:BAAALgAECgEJAgAAAA==.Kasadori:BAAALgAECgEJAQAAAA==.Kasualz:BAAALgAECgcJEQAAAA==.Kayrali:BAAALgAECgQJBAAAAA==.Kazsham:BAAALgAECgQJCQAAAA==.',
Kb='Kboomz:BAAALgAECgUJBgAAAA==.',
Kd='Kdvt:BAACLgAFFH8TAAIPAAUJSw5RUgAjAQAPAAUJSw5RUgAjAQAuAAQKfyUAAg8ACAlhIN4oAFoCAA8ACAlhIN4oAFoCAAAA.',
Ke='Keedrimath:BAAALgAECgYJBgAAAA==.Keenagon:BAAALgADCgcJBwAAAA==.Kelf:BAAALgADCgcJCgAAAA==.Kellbow:BAAALgAECggJDQAAAA==.Kelynada:BAAALgADCgMJAwAAAA==.Keyevokey:BAAALgAECgEJAQAAAA==.Keymissty:BAAALgAECgEJAQAAAA==.',
Kh='Khaemset:BAAALgADCgkJCQAAAA==.',
Ki='Kieldaz:BAABLgAECn8qAAIkAAkJORETCwCAAQAkAAkJORETCwCAAQAAAA==.Kinore:BAAALgAECgQJBAAAAA==.Kirista:BAAALgAECgYJDAAAAA==.Kirisute:BAABLgAECn8zAAIPAAkJbyHxIADwAgAPAAkJbyHxIADwAgAAAA==.Kitchenboss:BAABLgAECn8TAAIPAAgJ2R06dADqAQAPAAgJ2R06dADqAQAAAA==.Kithari:BAAALgAECgYJEQABLgAECgkJMAACAOsfAA==.',
Kn='Knickerbits:BAAALgADCgMJAwAAAA==.Knotting:BAABLgAECn8bAAIVAAYJFRQ9FgAtAQAVAAYJFRQ9FgAtAQAAAA==.',
Ko='Koll:BAAALgADCgIJAgAAAA==.Kollateral:BAABLgAECn9OAAIKAAgJCRxhCwDkAQAKAAgJCRxhCwDkAQAAAA==.Kopara:BAAALgAECgcJEQAAAA==.Korell:BAAALgAECgIJAwABLgAECggJDwARAAAAAA==.Koriella:BAAALgAECgIJAgAAAA==.Kotetsu:BAAALgADCgUJBQAAAA==.',
Kr='Kraejekta:BAAALgAECgUJBQAAAA==.Krankiekunt:BAAALgAECgYJEQAAAA==.Krazmar:BAAALgADCgYJCwAAAA==.Kreigor:BAAALgADCgUJBQAAAA==.Krellhim:BAAALgAECgcJCwAAAA==.Krislocked:BAAALgAECgYJEQAAAA==.Krusper:BAAALgAECgkJDwAAAA==.Krustie:BAAALgADCgEJAQAAAA==.',
Ku='Kungfused:BAAALgAECgQJBQAAAA==.Kuppusamy:BAAALgADCgcJCgAAAA==.',
Ky='Kyza:BAABLgAFFH8KAAIIAAQJ5QQYHAD/AAAIAAQJ5QQYHAD/AAAAAA==.',
La='Laaurge:BAAALgAECgUJBwAAAA==.Laceia:BAAALgADCgMJAwABLgAECgYJBwARAAAAAA==.Landwalker:BAACLgAFFH8RAAIUAAUJfhCaGQBUAQAUAAUJfhCaGQBUAQAuAAQKfzAAAhQACAlQIakOAMICABQACAlQIakOAMICAAAA.Langas:BAAALgAECgkJBgAAAA==.Latorius:BAABLgAECn8jAAIJAAkJNw1DQwCcAQAJAAkJNw1DQwCcAQAAAA==.Lazarian:BAAALgADCgUJDQABLgAECgkJEgARAAAAAA==.Lazziel:BAABLgAECn8jAAIPAAgJCgUgrgAJAQAPAAgJCgUgrgAJAQAAAA==.',
Le='Leebear:BAAALgADCgEJAQAAAA==.Leilashte:BAAALgAECgcJEwAAAA==.Lenn:BAABLgAECn9SAAIWAAkJ5A93IACXAQAWAAkJ5A93IACXAQAAAA==.Letmesolodps:BAAALgAECgQJBgAAAA==.Lettucelordh:BAABLgAECn8oAAMbAAkJOiBaAgB/AgAbAAgJBSFaAgB/AgAMAAMJBRiVSADfAAAAAA==.Lexavis:BAACLgAFFH8GAAIcAAMJ9yPGKQA8AQAcAAMJ9yPGKQA8AQAuAAQKfxkAAhwACQntID4MAOgCABwACQntID4MAOgCAAAA.Leyi:BAABLgAECn8lAAMSAAcJCxpwOwAeAgASAAcJCxpwOwAeAgALAAMJeguRRQCfAAABLgAECggJJgAgAEIgAA==.Leyian:BAAALgAECgYJDgABLgAECggJJgAgAEIgAA==.Leyissa:BAABLgAECn8mAAIgAAgJQiBkBQCCAgAgAAgJQiBkBQCCAgAAAA==.',
Li='Liggma:BAABLgAECn8zAAMmAAkJlhimEAA8AgAmAAkJPxOmEAA8AgAOAAYJBxp7IQCUAQAAAA==.Lilfatty:BAAALgAECgEJAQABLgAECgkJCwARAAAAAA==.Lily:BAAALgAECgEJAQAAAA==.Linkss:BAAALgADCgYJCwAAAA==.Linshadow:BAAALgAECgEJAQAAAA==.Litchblade:BAACLgAFFH8JAAITAAQJrwXKbQDuAAATAAQJrwXKbQDuAAAuAAQKfxYAAhMACAkbFapHAB0CABMACAkbFapHAB0CAAAA.Litgoblin:BAAALgADCgEJAgAAAA==.Littlecoops:BAAALgADCgYJCAAAAA==.Livelord:BAAALgAECgYJCgAAAA==.',
Lo='Loalo:BAAALgADCgUJBQAAAA==.Lockaboom:BAAALgADCgYJAwAAAA==.Locky:BAAALgAECgQJBgAAAA==.Loldruid:BAAALgAECgkJDgAAAA==.Lomzz:BAAALgAECgEJBQAAAA==.Lootminator:BAAALgADCgQJBQAAAA==.Loptr:BAAALgADCgEJAQAAAA==.Lorelai:BAAALgADCgcJEQAAAA==.Lowkey:BAAALgAECgYJAgABLgAECgcJEgARAAAAAA==.Lozza:BAAALgADCgQJBQAAAA==.',
Lu='Lucullus:BAAALgAECgYJCwAAAA==.Luminarus:BAAALgAECgYJCwAAAA==.Luminhunter:BAAALgAECgYJCQAAAA==.Lurethuid:BAAALgAECgQJBAAAAA==.Luts:BAAALgADCgIJAgAAAA==.',
Ly='Lyd:BAABLgAECn8kAAMeAAgJ7w0bGgBfAQAeAAgJ7w0bGgBfAQAdAAMJhgGsmABeAAAAAA==.Lynarium:BAAALgAECgcJDgAAAA==.Lynnmage:BAAALgADCgQJBAAAAA==.Lynnoni:BAAALgAECgMJBAAAAA==.',
['Lû']='Lûmiere:BAABLgAECn8ZAAIcAAgJYh9aOQA+AgAcAAgJYh9aOQA+AgAAAA==.',
Ma='Magharitta:BAABLgAECn8/AAITAAkJhSJiCAATAwATAAkJhSJiCAATAwAAAA==.Majicx:BAAALgAECgUJDQAAAA==.Malign:BAABLgAECn8WAAISAAgJegplWQC8AQASAAgJegplWQC8AQAAAA==.Malthayel:BAAALgAECgEJAQAAAA==.Manaseeker:BAAALgADCgkJDAAAAA==.Mannitol:BAAALgADCgEJAQAAAA==.Maraku:BAACLgAFFH8GAAMQAAQJvggRGgDWAAAQAAMJSwgRGgDWAAADAAIJlwhyKgBNAAAuAAQKfxQAAwMABwlVGJBkADkBAAMABAn6GJBkADkBABAABwkEF3gZADgBAAAA.Masonic:BAABLgAECn8VAAMJAAYJrxDmdgAMAQAJAAYJrxDmdgAMAQAkAAIJpADiLAAtAAAAAA==.Mathdori:BAAALgAECgkJBgAAAA==.Matter:BAAALgAECgUJDQAAAA==.Maxxfury:BAAALgAECgYJAwAAAA==.',
Mc='Mcshok:BAAALgADCgcJCAAAAA==.',
Me='Medesin:BAAALgAECgIJBAAAAA==.Medhic:BAAALgADCgIJAQAAAA==.Meirge:BAAALgAECgUJBQAAAA==.Mekhanite:BAABLgAECn82AAIiAAkJ8SSAAQA3AwAiAAkJ8SSAAQA3AwAAAA==.Memebeam:BAAALgAECgYJBwAAAA==.Memedemon:BAAALgAECgEJAQABLgAECgUJCQARAAAAAA==.Mercykill:BAAALgAECgEJAQAAAA==.Mesmagius:BAAALgAECgUJBQAAAA==.Metasoul:BAABLgAECn8vAAMJAAkJlxVULgDuAQAJAAkJlxVULgDuAQAkAAUJsQ0zGAC0AAAAAA==.',
Mi='Midknight:BAABLgAECn8WAAIcAAgJWRsdOQD9AQAcAAgJWRsdOQD9AQAAAA==.Milambir:BAAALgAECgUJCQAAAA==.Milfdella:BAABLgAECn8aAAIkAAgJdBs4BgAIAgAkAAgJdBs4BgAIAgAAAA==.Milspec:BAACLgAFFH8HAAIdAAIJPhf2LwCgAAAdAAIJPhf2LwCgAAAuAAQKfycAAh0ACQlpG9oQAE4CAB0ACQlpG9oQAE4CAAAA.Minami:BAABLgAECn8zAAMcAAkJux/IEwCxAgAcAAkJux/IEwCxAgAKAAEJQw3dRgAmAAAAAA==.Minhiriath:BAABLgAECn8mAAITAAgJ2R0lJgBIAgATAAgJ2R0lJgBIAgAAAA==.Mintbadger:BAAALgAECgcJCgAAAA==.Mintwolf:BAAALgAECgYJCAAAAA==.Missgertie:BAAALgADCgMJAwABLgAECgUJBQARAAAAAA==.Mistea:BAAALgAECgYJBgAAAA==.',
Mo='Modren:BAAALgAECgMJBwAAAA==.Moistmaker:BAAALgAECgMJBQABLgAECgkJEgARAAAAAA==.Mold:BAAALgAECgMJBwAAAA==.Mollyaddikt:BAAALgAECgkJAQAAAA==.Momotaku:BAABLgAECn8hAAMFAAkJVBrGEQCUAgAFAAkJVBrGEQCUAgAGAAQJxgv3bgBkAAAAAA==.Monalisa:BAABLgAECn8aAAIPAAcJLhQVtQD+AAAPAAcJLhQVtQD+AAAAAA==.Monkecco:BAAALgAECgcJBQAAAA==.Monkeyox:BAAALgADCgEJAQABLgAFFAUJGwAJAMgbAA==.Monkgyatso:BAAALgAECgUJCwAAAA==.Monkhax:BAAALgADCgYJBQAAAA==.Monkow:BAAALgAECgQJCQAAAA==.Monne:BAAALgADCgYJBgABLgAECgkJMwAWAFMXAA==.Monthax:BAAALgAECgIJAgAAAA==.Moomoos:BAABLgAECn8/AAIKAAkJqhsnBgBdAgAKAAkJqhsnBgBdAgAAAA==.Moonoo:BAAALgADCgIJAgAAAA==.Moonsblades:BAAALgAECgEJAQAAAA==.Moonthorn:BAABLgAECn8VAAIDAAYJvgEWwQB/AAADAAYJvgEWwQB/AAAAAA==.Morada:BAAALgAECgEJAQAAAA==.Mordok:BAAALgAECgEJAwAAAA==.Morena:BAAALgAECgQJBwAAAA==.Morgaina:BAABLgAECn8pAAILAAgJuxzdAwAlAgALAAgJuxzdAwAlAgAAAA==.Movski:BAABLgAECn8gAAQIAAYJyyCgHwD9AQAIAAYJYiCgHwD9AQAHAAQJxhf+DwAPAQAoAAMJbR1nDwDiAAAAAA==.Moñk:BAABLgAECn85AAMYAAgJ9hcpIgB1AQAZAAgJoRd7KADDAQAYAAgJVBEpIgB1AQAAAA==.',
Ms='Msbearhaven:BAAALgADCgYJBgAAAA==.',
Mu='Multîpass:BAAALgADCggJCQAAAA==.Mum:BAAALgAFFAEJAQAAAA==.Murst:BAABLgAECn89AAMSAAkJ3BuxHwBOAgASAAkJ3BuxHwBOAgALAAEJ/g++YgBJAAAAAA==.',
My='Myeyeshurt:BAAALgAECgUJEgAAAA==.Myk:BAAALgAECgEJAQABLgAECgQJBAARAAAAAA==.Mysterymeat:BAAALgADCgEJAQAAAA==.',
['Mä']='Mäya:BAAALgAECgcJEwAAAA==.',
['Më']='Mëmëmë:BAAALgAECgcJDgAAAA==.',
Na='Nahyeah:BAAALgAECgQJBAAAAA==.Narutox:BAAALgAECgEJAgAAAA==.Natria:BAABLgAECn8wAAMbAAkJyBINBgDNAQAbAAkJyBINBgDNAQAMAAMJGgokTwCRAAAAAA==.Natural:BAAALgAECgQJBAAAAA==.Naw:BAAALgAECgYJCwAAAA==.Nayashka:BAABLgAECn8XAAIYAAkJMRaLDwApAgAYAAkJMRaLDwApAgAAAA==.',
Nd='Ndir:BAAALgAECgQJBgAAAA==.',
Ne='Neeb:BAABLgAFFH8HAAITAAIJ0h0AkACtAAATAAIJ0h0AkACtAAAAAA==.Neebd:BAAALgAFFAEJAQABLgAFFAIJBwATANIdAA==.Nepth:BAABLgAECn8oAAIBAAgJqh96FABuAgABAAgJqh96FABuAgAAAA==.Nerfde:BAAALgAECgYJCQAAAA==.Nerfdelag:BAABLgAECn8cAAITAAkJtRxxHQB1AgATAAkJtRxxHQB1AgAAAA==.Nerfgün:BAAALgAECgUJBQABLgAFFAMJCQAFAHAWAA==.',
Ni='Nihonshu:BAAALgADCgIJAQAAAA==.Niskus:BAAALgAECgYJEQAAAA==.Nixipixie:BAAALgADCgcJCAAAAA==.Nizan:BAAALgAECgQJBgAAAA==.Nizie:BAAALgADCgMJAgAAAA==.',
No='Nobbiepally:BAAALgAECgYJEwAAAA==.Nonono:BAAALgAECgMJBQAAAA==.Notagoblin:BAAALgAECgYJDQAAAA==.Notahealer:BAAALgAECgcJDwAAAA==.Notdahuntard:BAAALgAECgkJDgAAAA==.Notso:BAAALgAECggJCwAAAA==.',
Np='Nps:BAAALgAECgUJEQAAAA==.',
Nr='Nragz:BAAALgAFFAEJAQAAAA==.',
Ns='Nsi:BAACLgAFFH8MAAIJAAMJCCPhOAAUAQAJAAMJCCPhOAAUAQAuAAQKfxUAAgkABwm1IB8yADICAAkABwm1IB8yADICAAAA.',
Nu='Nulldeath:BAABLgAECn8UAAITAAcJpCE3NQBiAgATAAcJpCE3NQBiAgAAAA==.Nutsdormu:BAABLgAECn9LAAIaAAkJKxPKCgAMAgAaAAkJKxPKCgAMAgAAAA==.Nuvlov:BAAALgAECgUJBwAAAA==.',
Ny='Nyssaela:BAAALgAECgUJBQAAAA==.Nyxmoona:BAAALgAECgIJAgAAAA==.',
['Nà']='Nàishà:BAABLgAECn8xAAMOAAkJnhidDQBlAgAOAAkJnhidDQBlAgAfAAYJKgVqQgDnAAAAAA==.',
Ob='Obskur:BAAALgAECgcJDwABLgAECgcJHgAaABIYAA==.',
Od='Odinwolf:BAABLgAFFH8LAAIFAAUJMB1wBQB1AQAFAAUJMB1wBQB1AQABLgAFFAYJCwACAMIaAA==.',
Og='Oggie:BAAALgAFFAEJAQAAAA==.Oginn:BAAALgAECgQJBgAAAA==.',
Oh='Ohspeghettii:BAAALgAECgUJBQABLgAECgcJGwAhAKANAA==.',
Oi='Oioi:BAAALgAECgMJAwAAAA==.',
Oj='Ojisancage:BAABLgAECn8aAAISAAkJexCBdwA0AQASAAkJexCBdwA0AQAAAA==.',
On='Onepuff:BAACLgAFFH8FAAIPAAIJ8wJ1kQB/AAAPAAIJ8wJ1kQB/AAAuAAQKfyMAAg8ACAnJFAFUAMQBAA8ACAnJFAFUAMQBAAAA.Onism:BAAALgADCgkJDAAAAA==.',
Oo='Ooggabooga:BAAALgAECgEJAQAAAA==.',
Op='Oprahwndfury:BAAALgAECgEJAQAAAA==.',
Or='Orinys:BAABLgAECn8/AAIaAAgJ3hLiDQDMAQAaAAgJ3hLiDQDMAQAAAA==.Orkky:BAABLgAECn84AAMiAAkJiCGjBADFAgAiAAkJECGjBADFAgAjAAUJ7hjzDwAtAQAAAA==.',
Pa='Packnwang:BAAALgADCgEJAQAAAA==.Page:BAACLgAFFH8OAAIIAAQJ2hRtEwBGAQAIAAQJ2hRtEwBGAQAuAAQKfx4AAggACAm8GDMZADsCAAgACAm8GDMZADsCAAAA.Pakurruun:BAAALgADCgcJFAAAAA==.Pallatress:BAAALgAECgIJBAAAAA==.Panginoon:BAACLgAFFH8FAAMiAAMJ1xZyJAB5AAATAAMJnRaGcgDnAAAiAAIJ2RByJAB5AAAuAAQKfy0AAxMACQkHIFwpADkCABMACAkCIFwpADkCACIABwmoF8QdAFwBAAAA.Paphio:BAAALgAECgMJBgAAAA==.Papipalala:BAAALgAECgYJDAAAAA==.Papíaíyúyü:BAAALgAECgYJAwAAAA==.Patrikk:BAAALgAECgIJAgAAAA==.Pawadin:BAAALgAECgcJCQAAAA==.',
Pe='Pepapo:BAAALgAECgUJDAAAAA==.Pepio:BAAALgAECgMJBgABLgAECgQJBAARAAAAAA==.Peppsi:BAAALgADCgcJDAAAAA==.Perden:BAAALgADCgMJAwAAAA==.',
Pg='Pgundry:BAAALgAECgUJBQAAAA==.',
Ph='Phakin:BAAALgAECgEJAQAAAA==.Phatboss:BAAALgAECgYJCwABLgAECggJEwAPANkdAA==.Phayzedout:BAACLgAFFH8FAAITAAMJRRNBfADaAAATAAMJRRNBfADaAAAuAAQKfyUAAxMACQleG54oADwCABMACQleG54oADwCACMAAQkAACgWADgAAAAA.',
Pi='Pierat:BAAALgAECggJEwAAAA==.Piergeiron:BAAALgAECggJDwAAAA==.Pinkrawr:BAAALgADCgMJAwAAAA==.Pinkwarrior:BAAALgAECgYJEQAAAA==.Pinkyblue:BAACLgAFFH8IAAISAAQJQwTxYQDUAAASAAQJQwTxYQDUAAAuAAQKfx0AAxIACAkLG10/ABACABIACAkLG10/ABACAAsAAQkAAKttADkAAAAA.Pipeppy:BAAALgADCgYJBgAAAA==.Pipssqeek:BAABLgAECn8UAAMPAAcJ0gFE8wCTAAAPAAcJmwFE8wCTAAAnAAEJhQHqIgAUAAAAAA==.Pipung:BAAALgAECgQJBQAAAA==.',
Pl='Plarrior:BAABLgAFFH8KAAIdAAQJ3RH6FgAyAQAdAAQJ3RH6FgAyAQAAAA==.Plutô:BAAALgADCgYJDAAAAA==.',
Po='Poairua:BAAALgADCgEJAQAAAA==.Poda:BAAALgAECgEJAQAAAA==.Polloloco:BAAALgAECgQJBQAAAA==.Poobumhead:BAABLgAECn85AAMSAAgJNxYYRgCyAQASAAgJZRUYRgCyAQALAAIJohQVIgB0AAAAAA==.Potoro:BAAALgADCgIJAgAAAA==.Powzar:BAAALgAECgcJEQAAAA==.',
Pr='Praetorian:BAAALgAECgYJCAAAAA==.Priestmn:BAAALgAECgMJBgAAAA==.Probabely:BAAALgADCgEJAQABLgAFFAYJGgATAJkdAA==.Probably:BAACLgAFFH8aAAITAAYJmR1PFADGAQATAAYJmR1PFADGAQAuAAQKfzMAAhMACQktJvQCAGADABMACQktJvQCAGADAAAA.Prís:BAAALgAECgQJBgAAAA==.',
Pt='Ptree:BAAALgADCgcJBwABLgAFFAEJAwARAAAAAA==.Ptreei:BAAALgAFFAEJAgABLgAFFAEJAwARAAAAAA==.',
Pu='Puck:BAABLgAECn8XAAMbAAgJJxm4CgBNAQAbAAcJVRi4CgBNAQAMAAUJ1BKpMgA1AQAAAA==.Pudgeydk:BAAALgAECgYJBgAAAA==.Pudgeys:BAACLgAFFH8QAAIXAAQJPx4OBABTAQAXAAQJPx4OBABTAQAuAAQKfxUAAhcABwkfIpQIAAcCABcABwkfIpQIAAcCAAAA.Punj:BAAALgAECggJDAABLgADCgYJBgARAAAAAA==.Purdxpriest:BAAALgADCgQJAwABLgADCgcJCQARAAAAAA==.Purdxwarlock:BAAALgADCgEJAQABLgADCgcJCQARAAAAAA==.Purecarnage:BAAALgADCgMJAwAAAA==.',
Py='Pyropuff:BAAALgADCgEJAQABLgAECgkJOQAkAAIhAA==.Pyroskolv:BAAALgAECgUJCQABLgAFFAUJFAAJAHsgAA==.Pytranze:BAAALgAECgcJEgAAAA==.Pywarrior:BAAALgADCgEJAQAAAA==.',
Qo='Qoldia:BAAALgADCgYJBgAAAA==.',
Qu='Quarizma:BAACLgAFFH8dAAMEAAcJcSBiBQDdAQAEAAYJ2iRiBQDdAQADAAIJqhVRUgCvAAAuAAQKfzUAAwQACQkPJtUBANUCAAQACQkPJtUBANUCAAMABQlCJr09AL8BAAAA.',
Ra='Radiantbunz:BAAALgAECgUJBwAAAA==.Rajbl:BAAALgAECgYJDgAAAA==.Rampagefist:BAAALgAECgEJAQAAAA==.Randalor:BAAALgADCgYJCgAAAA==.Rano:BAAALgAECgYJCAAAAA==.Ravenknight:BAAALgAECgUJBQAAAA==.Rayningdeath:BAAALgAECgkJCwAAAA==.Rayá:BAAALgADCgcJCAAAAA==.',
Re='Reaperzx:BAABLgAECn8XAAQdAAcJIBbsKACRAQAdAAcJIBbsKACRAQAlAAEJvwPmUQAZAAAeAAEJNgFzSwAHAAAAAA==.Reblle:BAAALgADCgIJAgAAAA==.Recks:BAAALgAECgMJAwAAAA==.Rejzo:BAAALgAECgMJBQABLgAECggJCgARAAAAAA==.Rejzogue:BAAALgAECggJCgAAAA==.Rejzosun:BAAALgAECgMJAwAAAA==.Renavant:BAABLgAECn8bAAIJAAcJVQw9dAATAQAJAAcJVQw9dAATAQAAAA==.Repliod:BAABLgAECn9GAAMgAAkJhyWfAABdAwAgAAkJhyWfAABdAwAVAAIJSQL5KgBvAAAAAA==.Restho:BAABLgAECn8jAAMFAAkJrx2oEACgAgAFAAgJkh2oEACgAgAGAAUJgw3uXgCWAAAAAA==.Revarix:BAACLgAFFH8GAAMjAAIJChOIEQCZAAAjAAIJChOIEQCZAAATAAEJ3wW/2AA/AAAuAAQKfy8AAyMACQkAGI8FABoCACMACQkAGI8FABoCABMAAQkoB2U4ASAAAAAA.',
Rh='Rhaella:BAABLgAECn8xAAMBAAkJ7BH7HwDdAQABAAkJ7BH7HwDdAQAcAAYJ+wi9uADwAAAAAA==.Rhuiser:BAAALgAECgcJEAAAAA==.Rhéá:BAAALgAECgYJCwAAAA==.',
Ri='Riggerized:BAAALgAECgcJEQABLgAECgkJPwAKAKobAA==.Rightmeow:BAAALgAECgEJAQAAAA==.Rilirian:BAABLgAECn8ZAAIcAAkJYQIw3gC5AAAcAAkJYQIw3gC5AAAAAA==.Riseth:BAACLgAFFH8IAAIGAAMJmyApGQAfAQAGAAMJmyApGQAfAQAuAAQKfywAAgYACAkjJXwIALQCAAYACAkjJXwIALQCAAAA.Riteboys:BAAALgAECgcJCAABLgAECggJEAARAAAAAA==.Ritéboys:BAAALgAECgEJAgABLgAECggJEAARAAAAAA==.Ritëboys:BAAALgAECgEJAwABLgAECggJEAARAAAAAA==.Rivella:BAAALgAECgcJCQAAAA==.',
Ro='Rockmelons:BAAALgADCgEJAQAAAA==.Rockosocko:BAAALgAECggJCAAAAA==.Roflpwnnt:BAABLgAECn8sAAQQAAkJvxr9DgAiAgAQAAkJQhb9DgAiAgAEAAYJ6xSzQABXAQADAAIJhh/0rgBmAAAAAA==.Rolln:BAAALgADCggJCwAAAA==.Romanée:BAAALgAECgQJDAAAAA==.Rootdaddy:BAAALgADCgEJAQAAAA==.Rootweaver:BAAALgADCgYJBgAAAA==.Rousay:BAABLgAECn8aAAIYAAkJswYnKQBDAQAYAAkJswYnKQBDAQAAAA==.',
Ru='Rusdar:BAAALgAECgMJAwABLgAECggJHQAdAKIDAA==.Rustylightz:BAAALgAECgQJBAAAAA==.Rutactic:BAAALgAECgMJAwAAAA==.Rutee:BAACLgAFFH8KAAIcAAMJIxAuSgDuAAAcAAMJIxAuSgDuAAAuAAQKfzoAAhwACQkbGzMlAE8CABwACQkbGzMlAE8CAAAA.',
Ry='Ryn:BAABLgAECn8UAAIJAAgJWwQnnwDYAAAJAAgJWwQnnwDYAAAAAA==.Ryuk:BAAALgAECgYJEQAAAA==.Ryuu:BAAALgAECgcJBgAAAA==.Ryz:BAAALgAECgkJCQABLgAFFAQJBgAZAPQcAA==.',
['Rà']='Ràvon:BAAALgAECgMJAwAAAA==.',
Sa='Sabelin:BAAALgAECgEJAQABLgAECgkJMAACAOsfAA==.Saellia:BAAALgAECgUJBQABLgAECgkJOQAMACIRAA==.Safy:BAACLgAFFH8FAAIZAAMJ7gbrMwC0AAAZAAMJ7gbrMwC0AAAuAAQKfy0AAhkACQkpDiAeAJYBABkACQkpDiAeAJYBAAAA.Saltyslug:BAAALgAECgUJDQAAAA==.Saltz:BAAALgAECgQJBAABLgAECgkJFQATAIgQAA==.Sanctilaz:BAAALgAECgkJEgAAAA==.Sanghyeok:BAAALgAECgUJBQAAAA==.Sanosan:BAAALgAECgMJBgABLgAECgUJBAARAAAAAA==.Saraedor:BAAALgADCgMJAwABLgAFFAMJCQAFAHAWAA==.Sartoc:BAACLgAFFH8JAAIFAAMJcBazNwDNAAAFAAMJcBazNwDNAAAuAAQKfxQAAgUACQlkHeMKAOACAAUACQlkHeMKAOACAAAA.',
Sc='Scabbo:BAABLgAECn8kAAILAAkJsRXZBAD+AQALAAkJsRXZBAD+AQAAAA==.Scaleseeker:BAAALgADCgcJDQAAAA==.Scalesoul:BAAALgAFFAMJAwAAAQ==.Scarfeast:BAAALgADCgQJBAAAAA==.Scummbag:BAAALgAECgEJBAAAAA==.',
Sd='Sdfgoose:BAAALgAECgkJDwAAAA==.Sdw:BAAALgAECgEJAQABLgAECgEJAgARAAAAAA==.',
Se='Sebille:BAABLgAECn8sAAIPAAgJJh6dLwC0AgAPAAgJJh6dLwC0AgAAAA==.Sebrogue:BAAALgAECgQJBgAAAA==.Seiferoth:BAAALgAECgEJAQABLgAFFAYJCwACAMIaAA==.Selais:BAABLgAECn8WAAIdAAYJTh7YNADWAQAdAAYJTh7YNADWAQAAAA==.Selfless:BAAALgAECgcJDgAAAA==.Selitha:BAAALgAECgIJAwAAAA==.Selunara:BAAALgADCgYJBgAAAA==.Selussa:BAAALgAECgYJBgABLgAFFAgJHQAJABIdAA==.Senddori:BAAALgAECgUJBQAAAA==.Sepl:BAAALgAECgYJCgAAAA==.Serana:BAAALgAECgUJBgAAAA==.Serasashrain:BAAALgADCgEJAQAAAA==.',
Sh='Shaddai:BAABLgAECn83AAIKAAkJRxhYCgAqAgAKAAkJRxhYCgAqAgAAAA==.Shadowmaggot:BAAALgAECgcJCAAAAA==.Shadylock:BAAALgAECgMJBQAAAA==.Shadypally:BAAALgAFFAEJAgAAAA==.Shakyrabbit:BAAALgADCgMJBAAAAA==.Shalash:BAAALgAECgQJBAAAAA==.Shamankiller:BAAALgAFFAIJBAAAAA==.Shamannoodle:BAAALgADCgIJAgAAAA==.Shamitsdk:BAAALgADCgMJBgABLgAECgcJHgAFANUWAA==.Shamix:BAAALgADCgYJDAAAAA==.Shamlen:BAAALgAECgQJBAAAAA==.Shaniquasimo:BAABLgAECn8aAAISAAgJASBpHQBaAgASAAgJASBpHQBaAgAAAA==.Shaquiqui:BAAALgAECgIJAgAAAA==.Sharddaddy:BAAALgADCgIJAgAAAA==.Sharftay:BAAALgAECgYJEgABLgAFFAcJGAADAI0KAA==.Sharissa:BAAALgAECgYJDgAAAA==.Shatgun:BAAALgADCgcJBwAAAA==.Shiicho:BAAALgAECgIJAgAAAA==.Shinieedruid:BAAALgAECgMJAgABLgAFFAQJBgASALsSAA==.Shockedurmum:BAABLgAECn8WAAMXAAcJIhYlFgBcAQAXAAYJNA8lFgBcAQAGAAYJ+RmWRQAyAQAAAA==.Shocknôrris:BAAALgAECgYJEgAAAA==.Shouffle:BAAALgAECgEJAQAAAA==.',
Si='Sickomode:BAAALgADCgMJAwABLgAECgcJHgAaABIYAA==.Sidatas:BAAALgADCgEJAQAAAA==.Siferbooze:BAAALgADCgQJBAAAAA==.Silcy:BAAALgADCgMJAwAAAA==.Sillàrus:BAAALgAECgcJAgAAAA==.Silverspulse:BAABLgAECn8/AAMOAAgJvx7PDABxAgAOAAgJvx7PDABxAgAmAAQJrRokLAA6AQAAAA==.Sinfulbeast:BAAALgAECgYJBgABLgAECggJMAAcAA0fAA==.Sinfulpally:BAABLgAECn8wAAIcAAgJDR/wLQAnAgAcAAgJDR/wLQAnAgAAAA==.Sippy:BAABLgAFFH8NAAISAAQJzgehTQAFAQASAAQJzgehTQAFAQAAAA==.Sippycup:BAACLgAFFH8JAAITAAIJMhw6kwClAAATAAIJMhw6kwClAAAuAAQKfyMAAhMACQnIH54YAOgCABMACQnIH54YAOgCAAEuAAUUBAkNABIAzgcA.Sisisi:BAAALgAECgQJBwAAAA==.',
Sk='Skartos:BAAALgAECgIJAgAAAA==.Skilledplaya:BAAALgAECgYJCQAAAA==.Skruffles:BAAALgAECgcJDQAAAA==.Skulv:BAACLgAFFH8UAAIJAAUJeyAXHwBuAQAJAAUJeyAXHwBuAQAuAAQKfzcAAgkACQlxJawCAFADAAkACQlxJawCAFADAAAA.Skum:BAAALgAECgEJBAAAAA==.Skunkdmeow:BAAALgAECgcJCgAAAA==.',
Sl='Slayher:BAAALgAECgUJDQABLgAFFAQJEAAPAPsVAA==.Slimygerald:BAAALgAECgIJAgAAAA==.Slopain:BAABLgAECn8XAAIkAAgJCRZKCgCTAQAkAAgJCRZKCgCTAQAAAA==.Slopflop:BAAALgADCgYJBgAAAA==.Slåppery:BAABLgAECn8XAAMEAAcJ4Rc0CwCPAQAEAAcJ4Rc0CwCPAQADAAEJAADGygA7AAAAAA==.',
Sm='Smallarms:BAAALgAECgcJBQABLgAECggJKQAmAAETAA==.',
Sn='Sneakyshark:BAAALgAECgcJBgAAAA==.Sniickorzz:BAAALgAECgEJAgAAAA==.Snipereye:BAAALgAECgEJAgABLgAFFAEJAQARAAAAAA==.Snorlax:BAAALgAECgcJDgAAAA==.Snort:BAABLgAECn8oAAMcAAkJ+iGXEADIAgAcAAkJ+iGXEADIAgABAAgJfiGZCwCvAgAAAA==.Snërt:BAAALgAECgYJCgAAAA==.Snört:BAAALgAFFAIJAgAAAA==.',
So='Sonotafurry:BAAALgAECgkJDwAAAA==.Soojung:BAAALgAECgEJAQAAAA==.Soova:BAAALgAECgYJDQAAAA==.Sorcus:BAAALgAECgUJDwAAAA==.Soreknees:BAAALgADCgEJAQAAAA==.Souliuge:BAAALgADCgMJAwAAAA==.Soundface:BAABLgAECn8jAAIGAAYJVyBiJQDmAQAGAAYJVyBiJQDmAQAAAA==.',
Sp='Sparkysteve:BAABLgAECn8fAAMGAAgJ6SBjEAClAgAGAAgJ6SBjEAClAgAFAAIJnA0dmgA5AAAAAA==.Spastichits:BAAALgAFFAMJAwABLgAFFAQJCQAJAPYaAA==.Spelcastndog:BAACLgAFFH8JAAIPAAQJ5gpMTwAqAQAPAAQJ5gpMTwAqAQAuAAQKfzUAAg8ACAlXH5oiAHcCAA8ACAlXH5oiAHcCAAAA.Spindrift:BAABLgAECn8hAAMBAAkJkR7GBwDrAgABAAkJkR7GBwDrAgAcAAEJZgOnfAEkAAAAAA==.Spinypubes:BAAALgAECgMJBQAAAA==.Spiritfuzz:BAAALgAECgQJBAABLgAFFAQJCQATAK8FAA==.Spiritrez:BAAALgADCgYJAwABLgAECgYJBwARAAAAAA==.Spodermin:BAAALgADCgEJAQAAAA==.Spoonyy:BAABLgAECn8nAAIPAAkJVxxUGgChAgAPAAkJVxxUGgChAgAAAA==.Spukz:BAACLgAFFH8PAAIdAAMJUh1IIAAFAQAdAAMJUh1IIAAFAQAuAAQKfxsAAx0ABgnSH+coAJEBAB0ABgnSH+coAJEBAB4AAQk4D6A/ADkAAAAA.Spunkmonk:BAAALgAECgEJAwAAAA==.',
St='Stabbyhunt:BAAALgAECgkJBgAAAA==.Starstorm:BAAALgAECgYJBwAAAA==.Sterlybo:BAAALgAECgQJBgABLgAECgcJHQAcAJ4cAA==.Stillwater:BAAALgAECgEJAQAAAA==.Stoneyboi:BAAALgADCgcJCQAAAA==.Stoolth:BAAALgAFFAEJAQAAAA==.Stormwrath:BAAALgAECgYJEAAAAA==.Stoutbrew:BAAALgAECgYJDwAAAA==.Stuy:BAACLgAFFH8SAAMEAAQJYQ4vEAAVAQAEAAQJsAwvEAAVAQAQAAMJOAc8HACyAAAuAAQKf0EAAwQACQmOGugGAPgBAAQACQmOGegGAPgBABAABwl7FMIZALIBAAAA.Stãria:BAABLgAECn81AAIDAAkJMRTPKQAMAgADAAkJMRTPKQAMAgAAAA==.Stårlå:BAAALgADCgEJAgAAAA==.Stèpsis:BAAALgAECgMJBAAAAA==.Störme:BAAALgAECgIJBAAAAA==.',
Su='Sugarburst:BAABLgAECn8YAAMXAAYJ2xmeDwC+AQAXAAYJ2xmeDwC+AQAFAAEJ7AEjxgAeAAAAAA==.Sugmanutz:BAAALgAECgMJAwAAAA==.Sukmahdisc:BAABLgAECn8aAAImAAkJLwzhIQCEAQAmAAkJLwzhIQCEAQAAAA==.Sulph:BAAALgADCgEJAQAAAA==.Supershy:BAAALgAECgEJAQAAAA==.Supl:BAAALgAECgIJAgAAAA==.Suppirin:BAAALgADCgYJCAAAAA==.Supprakus:BAACLgAFFH8TAAIMAAQJ0BBrIwAPAQAMAAQJ0BBrIwAPAQAuAAQKfzQAAgwACAkQHRMUABwCAAwACAkQHRMUABwCAAAA.Suspectsusan:BAAALgAECgEJAwABLgAECggJEAARAAAAAA==.Susuryss:BAAALgADCgUJBQAAAA==.',
Sv='Svendlemoon:BAABLgAECn8uAAIVAAkJgxmhBQBnAgAVAAkJgxmhBQBnAgAAAA==.',
Sw='Swak:BAABLgAECn8VAAITAAgJQRPRWQCVAQATAAgJQRPRWQCVAQABLgAFFAIJAgARAAAAAA==.Swakhunt:BAAALgAFFAIJAgAAAA==.Swaky:BAAALgADCgMJAwABLgAFFAIJAgARAAAAAA==.Sweaty:BAAALgADCgkJCQAAAA==.Swinginwilly:BAAALgAECgYJBgAAAA==.Swippy:BAAALgADCgQJBAAAAA==.Swirlo:BAACLgAFFH8IAAIJAAMJ6gzzTgDNAAAJAAMJ6gzzTgDNAAAuAAQKfzgAAgkACQl1HYMPAKwCAAkACQl1HYMPAKwCAAAA.Swirlyball:BAAALgADCgkJEQABLgAFFAMJCAAJAOoMAA==.',
Sy='Syaphire:BAAALgAECgQJCwAAAA==.Sylaen:BAAALgADCgQJBAABLgAECgkJFwAYADEWAA==.Syndeath:BAAALgADCgIJAgAAAA==.Synths:BAABLgAECn8fAAQOAAgJdhlUGgAJAgAOAAgJ7xZUGgAJAgAmAAYJjRsjGwDJAQAfAAEJtAomYQA2AAAAAA==.',
['Sì']='Sìns:BAAALgAECgUJCgAAAA==.',
['Sñ']='Sñort:BAAALgAECgcJEgAAAA==.',
['Sý']='Sýìvàñás:BAAALgAECgUJAQAAAA==.',
Ta='Taffinator:BAAALgADCgEJAQABLgAECgkJMAACAOsfAA==.Taffyclown:BAABLgAECn8wAAICAAkJ6x92BwD2AgACAAkJ6x92BwD2AgAAAA==.Taharuot:BAAALgAECgYJDwAAAA==.Takahe:BAAALgAECgEJAQAAAA==.Tallinor:BAABLgAECn85AAMPAAgJABJNXACtAQAPAAgJABJNXACtAQApAAQJhgc8CQDAAAAAAA==.Taumast:BAAALgAECgcJEwABLgAFFAMJBwAOAKoGAA==.Tauter:BAAALgAECgIJBAAAAA==.Tazzee:BAAALgAECgEJAQAAAA==.',
Te='Teeki:BAAALgADCgcJBwAAAA==.Teiresius:BAAALgADCgYJBgAAAA==.Telsda:BAAALgAECgEJAgAAAA==.Telsrok:BAAALgADCgUJBQAAAA==.Tempyst:BAABLgAECn8eAAMaAAcJEhhIEwAOAgAaAAcJEhhIEwAOAgAMAAYJzAxFTwDGAAAAAA==.Tessdee:BAAALgAECgYJCQAAAA==.Tetactic:BAAALgADCgIJAgAAAA==.',
Th='Thalia:BAACLgAFFH8GAAQKAAIJUxQWDQBwAAAcAAIJPgWudgCHAAAKAAIJUxQWDQBwAAABAAEJbAhOPwA2AAAuAAQKfyYAAgoACQlzH1MEAJQCAAoACQlzH1MEAJQCAAAA.Thaytred:BAAALgAECgMJCAAAAA==.Thecheezels:BAAALgAECgIJAwAAAA==.Thegòòch:BAAALgAECgQJAQAAAA==.Thesean:BAAALgADCgcJBwAAAA==.Thevoice:BAAALgADCgQJBAAAAA==.Thomzhar:BAAALgAECgUJCwAAAA==.Thornir:BAAALgADCgEJAQABLgADCgMJBAARAAAAAA==.Thors:BAAALgAECgYJCAAAAA==.Thraznith:BAAALgAECgUJDAAAAA==.Threeföld:BAAALgADCgYJBgABLgAFFAMJCgAcAJUSAA==.Throber:BAAALgADCgkJDAAAAA==.',
Ti='Tienchi:BAABLgAECn8wAAMYAAkJ0yBeBADzAgAYAAkJ0yBeBADzAgAZAAEJTARMfgA1AAAAAA==.Tierk:BAAALgAECgcJDAAAAA==.Tillyhunter:BAAALgADCgcJEQAAAA==.Timmyy:BAABLgAECn8XAAITAAkJcRzZHwBoAgATAAkJcRzZHwBoAgAAAA==.Tinainverse:BAAALgADCgEJAQAAAA==.',
To='Tomatofarmer:BAAALgADCgUJBQAAAA==.Torgeist:BAAALgAECgcJCgAAAA==.Tormént:BAACLgAFFH8LAAIjAAMJeiCyCQAVAQAjAAMJeiCyCQAVAQAuAAQKf1cAAiMACQlHJmQAAGoDACMACQlHJmQAAGoDAAAA.Torvold:BAAALgAECgMJAwAAAA==.Totemskrotem:BAAALgAECgEJAQAAAA==.',
Tr='Transport:BAAALgAECgYJBQAAAA==.Traumatizer:BAABLgAECn8zAAIdAAkJxBuHDwBcAgAdAAkJxBuHDwBcAgAAAA==.Treehumpin:BAAALgAECgMJAwAAAA==.Tremorlover:BAAALgAECgIJBQAAAA==.Trogas:BAAALgAECgMJAwAAAA==.Tronix:BAABLgAECn8jAAIDAAkJ/R4HFACIAgADAAkJ/R4HFACIAgAAAA==.Tronixs:BAAALgAECgEJAQABLgAECgkJIwADAP0eAA==.Trucidario:BAAALgAECgYJDwAAAA==.Trulsdk:BAAALgAECgQJCgABLgAECgYJBwARAAAAAA==.Truwar:BAAALgAECgYJBwAAAA==.',
Tu='Turtlewave:BAAALgAECgUJAgAAAA==.',
Tw='Twiganomicon:BAAALgAECgEJAQAAAA==.Twiggz:BAABLgAECn8cAAIDAAcJUgbLmQDWAAADAAcJUgbLmQDWAAAAAA==.Twinkleface:BAAALgAECgQJBAAAAA==.',
Ty='Tylund:BAABLgAECn9WAAIDAAkJlRkLGgBhAgADAAkJlRkLGgBhAgAAAA==.Tyrilara:BAAALgADCgUJCAAAAA==.Tyruu:BAAALgAECgYJBwAAAA==.',
['Tâ']='Tânk:BAAALgAECgEJBQAAAA==.',
['Tï']='Tïm:BAAALgAECgMJAwABLgAECgkJFwATAHEcAA==.',
Ul='Ultimatdeath:BAAALgAECgkJAQAAAA==.',
Un='Unchaotic:BAAALgADCgMJAwAAAA==.Unholykníght:BAAALgADCgEJAQAAAA==.',
Ur='Uratowel:BAAALgADCgEJAQAAAA==.Urukhar:BAAALgAECgIJAwAAAA==.',
Va='Valaya:BAAALgAECgYJDAAAAA==.Valcaris:BAABLgAECn8ZAAInAAgJJhBuBACGAQAnAAgJJhBuBACGAQAAAA==.Valdr:BAAALgAECgQJBAABLgAFFAUJCQAgAGkTAA==.Valentine:BAABLgAECn8dAAIPAAkJgBNEOwARAgAPAAkJgBNEOwARAgAAAA==.Valex:BAAALgAECgEJAQAAAA==.Valithor:BAAALgAECggJCQAAAA==.Vampaph:BAAALgADCgEJAQAAAA==.Vazwitch:BAAALgAECgMJAwAAAA==.',
Ve='Velaris:BAAALgAECgYJEwAAAA==.Velarrine:BAAALgAECgQJBQAAAA==.Veledor:BAAALgADCgEJAQAAAA==.Velenair:BAABLgAECn8pAAMmAAgJAROJGgDOAQAmAAgJAROJGgDOAQAfAAQJ5BDRQQDeAAAAAA==.Velenlerolan:BAACLgAFFH8HAAITAAMJVxnabQDuAAATAAMJVxnabQDuAAAuAAQKfy0AAhMACAmKH2skAFECABMACAmKH2skAFECAAAA.Velicelia:BAAALgAECgQJBQAAAA==.Velthara:BAABLgAECn8sAAIcAAkJVBwhIACrAgAcAAkJVBwhIACrAgAAAA==.Velzan:BAACLgAFFH8NAAIMAAQJSQj7NQC7AAAMAAQJSQj7NQC7AAAuAAQKfxUAAgwABwmjEjxLANUAAAwABwmjEjxLANUAAAAA.Verailde:BAAALgADCgcJCAAAAA==.Verathos:BAAALgADCgIJAgAAAA==.Vergil:BAABLgAFFH8FAAMYAAIJmA4dKAB3AAAZAAIJmA7FPQCCAAAYAAIJ0AUdKAB3AAAAAA==.Verilence:BAABLgAECn8oAAMhAAkJCyVrAABYAwAhAAkJCyVrAABYAwASAAEJ+wd9JAEtAAAAAA==.Verks:BAAALgADCgYJBgABLgAECgUJCQARAAAAAA==.Vext:BAAALgAECgkJCAAAAA==.',
Vi='Victar:BAAALgADCgMJAwAAAA==.Villios:BAABLgAECn8WAAMnAAcJDRi1CwAZAQAnAAUJPBe1CwAZAQAPAAUJhRl01ADKAAAAAA==.Vindicor:BAAALgAFFAIJAgAAAA==.Vivify:BAAALgAFFAMJAwAAAA==.',
Vo='Voidberg:BAAALgAECgYJCwABLgAFFAQJGAAUAPsJAA==.Voidfondler:BAACLgAFFH8KAAIJAAQJNBmzMAApAQAJAAQJNBmzMAApAQAuAAQKfxUAAgkACAl5IokTAOMCAAkACAl5IokTAOMCAAAA.Voidgasm:BAAALgAECgMJBQAAAA==.Voidlocked:BAAALgAECgYJCwAAAA==.Voidwings:BAAALgAECgYJBgAAAA==.Vorndryad:BAAALgADCgYJBgAAAA==.',
Vy='Vynburn:BAABLgAECn8mAAIPAAkJEhUKPQALAgAPAAkJEhUKPQALAgAAAA==.Vynnaris:BAABLgAECn8pAAQiAAgJFgvhIgANAQAiAAgJFgvhIgANAQATAAMJ2QIeHgFKAAAjAAIJkwPrLAArAAAAAA==.',
['Vì']='Vìn:BAAALgAECgEJAgAAAA==.',
Wa='Wabby:BAAALgAECgEJAQAAAA==.Wadadadadeng:BAAALgAECgcJDwAAAA==.Waise:BAAALgAECgEJAwAAAA==.Wakuja:BAAALgADCgYJBgABLgAFFAYJCwACAMIaAA==.Wallahi:BAAALgAECgUJDQAAAA==.Warriorlol:BAAALgADCgEJAQAAAA==.Warspear:BAAALgADCgEJAQAAAA==.Watson:BAABLgAECn8dAAIPAAgJ6BFMYwCbAQAPAAgJ6BFMYwCbAQAAAA==.Waveryy:BAAALgAECgIJAgAAAA==.',
We='Wehex:BAAALgADCgIJAgAAAA==.Wemblitz:BAAALgAECgIJBAAAAA==.Weraise:BAAALgADCgcJBwAAAA==.Wesh:BAAALgAFFAIJAwAAAA==.',
Wh='Whio:BAABLgAECn8eAAMYAAkJiBHWGADBAQAYAAkJiBHWGADBAQACAAQJIQsaUACTAAAAAA==.',
Wi='Wildglaive:BAAALgADCgkJHQAAAA==.Willowg:BAAALgAECgQJBQAAAA==.Windwankur:BAAALgAECgIJAgAAAA==.Wintersfence:BAAALgAECgYJEgAAAA==.',
Wo='Woshiwacky:BAAALgADCgcJCQAAAA==.',
['Wî']='Wîngman:BAAALgAECgYJBgAAAA==.',
Xa='Xaldrin:BAAALgADCgEJAQAAAA==.Xallatath:BAACLgAFFH8OAAImAAQJExW+IgDmAAAmAAQJExW+IgDmAAAuAAQKfx0ABCYACQlMGysMAH8CACYACQkwGysMAH8CAB8ABAkfBxBJALoAAA4AAQkjFN5gADEAAAAA.Xanxes:BAAALgADCgIJAgAAAA==.',
Xe='Xenarn:BAEBLgAECn8nAAIZAAgJ3hANIQCAAQAZAAgJ3hANIQCAAQAAAA==.Xenoruin:BAABLgAECn8pAAINAAkJ8BBSFAC2AQANAAkJ8BBSFAC2AQAAAA==.Xerez:BAAALgADCgYJDAAAAA==.Xertzart:BAABLgAECn9PAAIUAAgJJSKYCgD0AgAUAAgJJSKYCgD0AgAAAA==.Xev:BAAALgADCgkJEgAAAA==.',
Xi='Ximigo:BAAALgAECgYJEwAAAA==.Xinrat:BAAALgAECgIJAgAAAA==.Xiongzzrwar:BAABLgAECn8gAAIdAAgJWh/aDwBYAgAdAAgJWh/aDwBYAgABLgAFFAcJGgAIAFwbAA==.',
['Xê']='Xêv:BAABLgAFFH8LAAITAAQJUBT+TQAvAQATAAQJUBT+TQAvAQAAAA==.',
Ya='Yangdu:BAAALgADCgcJBwAAAA==.Yay:BAAALgAECgEJAgABLgAFFAYJFgAPAFwVAA==.',
Yo='Yojambuh:BAAALgAECgMJBQAAAA==.Yondari:BAAALgAECgcJBgABLgAECggJKQAmAAETAA==.Yoyo:BAAALgAECgYJCgAAAA==.',
Yr='Yrugae:BAAALgADCgYJDgAAAA==.',
['Yõ']='Yõzõrã:BAAALgADCgcJCAAAAA==.',
Za='Zae:BAABLgAECn8ZAAIpAAYJqh7EAgANAgApAAYJqh7EAgANAgABLgAECgkJHwAcAA8jAA==.Zaeley:BAABLgAECn8fAAIcAAkJDyPyBAA7AwAcAAkJDyPyBAA7AwAAAA==.Zanisha:BAABLgAECn83AAIWAAgJoQdDNQARAQAWAAgJoQdDNQARAQAAAA==.Zargrim:BAABLgAECn8WAAIGAAYJOiJLHgDDAQAGAAYJOiJLHgDDAQAAAA==.Zatasia:BAACLgAFFH8RAAICAAQJlRJxHgAAAQACAAQJlRJxHgAAAQAuAAQKfxkAAwIACQmpD6soAJgBAAIACQmpD6soAJgBABgAAwkhF/9CAMcAAAAA.',
Ze='Zeddar:BAAALgAECgQJBAAAAA==.Zegion:BAABLgAECn8bAAMBAAYJCAqeVgAhAQABAAYJCAqeVgAhAQAcAAEJ3QOAWQElAAAAAA==.Zelendorm:BAABLgAECn8zAAIKAAkJ3B2XBQBtAgAKAAkJ3B2XBQBtAgAAAA==.Zelis:BAAALgADCgIJAgAAAA==.Zenara:BAAALgAECggJAQAAAA==.Zephyreus:BAAALgADCgkJFgAAAA==.Zerat:BAAALgAECgUJBQABLgAECgkJMwAWAFMXAA==.Zeroth:BAAALgADCgcJCgAAAA==.Zezîma:BAAALgADCgYJBgAAAA==.',
Zi='Zingerböx:BAAALgADCgYJBgAAAA==.Zionara:BAAALgADCgUJBQABLgAFFAYJAQARAAAAAA==.',
Zo='Zorevi:BAAALgAECgQJBQAAAA==.',
Zu='Zugzak:BAAALgAECgYJBgABLgAFFAMJBgAUAE0IAA==.Zunara:BAAALgADCgcJBwAAAA==.',
Zy='Zyr:BAAALgAECgEJAQAAAA==.',
['Ãk']='Ãkillies:BAABLgAECn8dAAMdAAgJogMCaQARAQAdAAgJbQMCaQARAQAeAAIJ9QI2RgArAAAAAA==.',
['År']='Årrow:BAAALgADCgMJAwAAAA==.',
['Ær']='Æries:BAAALgAECgIJAgAAAA==.',
['Îl']='Îllshot:BAAALgADCgcJBwAAAA==.',
['Ðo']='Ðomino:BAAALgAECgEJAQAAAA==.',
['ßa']='ßaccycønes:BAAALgAECgQJBAAAAA==.',
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
