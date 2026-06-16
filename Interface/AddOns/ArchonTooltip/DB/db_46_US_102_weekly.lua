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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Paladin-Retribution','Druid-Balance','Druid-Feral','Paladin-Protection','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Fury','Hunter-Survival','Warrior-Protection','Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','DemonHunter-Devourer','Monk-Windwalker','DemonHunter-Vengeance','Mage-Arcane','Hunter-Marksmanship','Priest-Shadow','Priest-Discipline','Mage-Fire','Monk-Mistweaver','DemonHunter-Havoc','Druid-Guardian','DeathKnight-Frost','Paladin-Holy','Monk-Brewmaster',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abortheira:BAAALgADCgUJBQAAAA==.',
Ac='Acelord:BAABLgAECn8jAAIBAAkJbxi8JABMAgABAAkJbxi8JABMAgAAAA==.Actaeon:BAAALgAECgQJBgAAAA==.',
Ad='Adaar:BAAALgAECgEJAQAAAA==.Adadebox:BAAALgAECgYJEAAAAA==.Adakat:BAAALgADCgEJAQAAAA==.Adanthedark:BAAALgADCgIJAgAAAA==.Adariom:BAAALgADCgUJCAAAAA==.Adrian:BAAALgADCgEJAQAAAA==.Adriannos:BAAALgAECgEJAQAAAA==.',
Ae='Aethir:BAAALgADCgYJBwAAAA==.',
Ag='Aghatta:BAAALgAECgYJBgAAAA==.Agonyy:BAAALgAECgUJEAAAAA==.Agrias:BAAALgAECgEJAgAAAA==.',
Ah='Aharadack:BAAALgAECgIJAgAAAA==.',
Ak='Akawaka:BAAALgAECgEJAQAAAA==.Akiji:BAAALgAECgEJBAAAAA==.Akimurad:BAAALgAECgYJBwAAAA==.',
Al='Alakazam:BAAALgADCgcJBwAAAA==.Alanie:BAAALgADCggJCAABLgAECggJIwACABUeAA==.Ald:BAAALgAECgEJAgAAAA==.Aldebaraum:BAAALgAECgcJDQAAAA==.Alexextreme:BAAALgAECgcJEQAAAA==.Aliaksandr:BAAALgAECgEJAQAAAA==.Alikth:BAAALgADCgYJBgAAAA==.Alista:BAAALgAECgQJAwAAAA==.Allandyr:BAACLgAFFH8LAAIBAAMJ0A7aXwDdAAABAAMJ0A7aXwDdAAAuAAQKf0sAAgEACQkMGjwfAGgCAAEACQkMGjwfAGgCAAAA.Alvarao:BAAALgAECgQJBAAAAA==.',
Am='Amandadark:BAAALgAECgEJAQAAAA==.Amano:BAAALgADCgYJDAAAAA==.',
An='Anaxthacia:BAAALgADCgMJAwAAAA==.Andarilho:BAAALgAECgYJBwAAAA==.Andinth:BAAALgAECgIJAgAAAA==.Andrepvp:BAAALgADCggJDwAAAA==.Andrit:BAAALgADCgEJAQAAAA==.Anelie:BAAALgAECgcJBwABLgAECggJIwACABUeAA==.Anellÿ:BAAALgAECgEJAQAAAA==.Angelloz:BAABLgAECn8rAAIDAAgJARLjeQB4AQADAAgJARLjeQB4AQAAAA==.Anjelvs:BAAALgAECgYJBgAAAA==.Anksunamoon:BAACLgAFFH8FAAICAAUJxAXAMQDhAAACAAUJxAXAMQDhAAAuAAQKfx0ABAIACQkrEi1AAI8BAAIACAmRDy1AAI8BAAQABgm4DtU1ADsBAAUAAgk+EMo6AGcAAAAA.Annaoh:BAABLgAECn8cAAIDAAgJVB2yQAACAgADAAgJVB2yQAACAgAAAA==.Annia:BAAALgADCgYJBwAAAA==.Anyid:BAAALgAECgMJAwAAAA==.Anãodengoso:BAABLgAECn8pAAMDAAgJSCZgFQDpAgADAAgJSCZgFQDpAgAGAAIJIxLnPABmAAABLgAECggJKQADAEgmAA==.',
Ap='Apökalÿpsïs:BAABLgAECn8tAAIHAAkJPxvwHACsAgAHAAkJPxvwHACsAgAAAA==.',
Ar='Arator:BAAALgAECggJDwAAAA==.Ardry:BAAALgADCgYJBgAAAA==.Argaloth:BAAALgAECgYJBwAAAA==.Argonzinha:BAAALgAECgEJAQAAAA==.',
As='Ashryel:BAAALgAECgEJAQAAAA==.Ashthon:BAABLgAECn8eAAIBAAcJgxxINgDVAQABAAcJgxxINgDVAQAAAA==.Asmitta:BAAALgADCgQJBAAAAA==.',
At='Atalantha:BAAALgAECgIJAgAAAA==.Atomicdk:BAAALgAECgUJBwAAAA==.Atomictank:BAAALgAECgcJEwAAAA==.Atonos:BAAALgAECgcJDQAAAA==.',
Au='Auquenai:BAAALgADCgUJBQAAAA==.Aurielis:BAAALgAECgEJAgAAAA==.',
Av='Averagemage:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAAALgAECgQJBAAAAA==.',
Az='Azadium:BAAALgAECgUJCgAAAA==.Azul:BAAALgAECgUJCwAAAA==.',
Ba='Baala:BAAALgAECgEJAgAAAA==.Badayaga:BAAALgADCgIJAgAAAA==.Bakunogrind:BAAALgAECgUJBQABLgAFFAQJBwAIAEMeAA==.Balragouldur:BAAALgAECgQJBgAAAA==.Balthar:BAACLgAFFH8HAAQIAAIJqAVIawBgAAAIAAIJqAVIawBgAAAJAAIJfwJvTgBRAAAKAAEJ5gKVGwA6AAAuAAQKfyAABAkABwk6EtxIAAwBAAkABwmjEdxIAAwBAAoABAkKEWsdAPUAAAgABAkGD0mnAHUAAAAA.Barathrum:BAAALgAECgEJAQAAAA==.Barcaldas:BAAALgAECgUJBgAAAA==.Barrocø:BAAALgAECgQJBQABLgAECggJGAALAAIcAA==.Basara:BAAALgAECgcJEgAAAA==.Batefraco:BAAALgADCgIJAgAAAA==.',
Bb='Bbiel:BAABLgAECn8kAAMMAAYJnROdEwAQAQAMAAYJnROdEwAQAQANAAEJtwfnSQEuAAAAAA==.',
Be='Beatriz:BAAALgAFFAEJAQAAAA==.Beelgarath:BAAALgAECgYJCwAAAA==.Beherit:BAAALgAECgMJBgAAAA==.Beliall:BAAALgAECgQJBwAAAA==.Belowlight:BAAALgAECgYJEAAAAA==.Belttazar:BAAALgADCgkJDwAAAA==.Bemmaith:BAAALgAECgQJBAAAAA==.Benzema:BAAALgADCgMJAgAAAA==.Berzan:BAAALgAECgUJCwAAAA==.Beyoond:BAACLgAFFH8bAAQNAAUJrxVHbgDgAAANAAMJFBVHbgDgAAAOAAIJgBdCIABPAAAMAAEJ+werJgBHAAAuAAQKfzoABA0ACQm+HMgkAEoCAA0ACQm/G8gkAEoCAAwABAm3D+cxAPEAAA4AAwnBFvQeAMMAAAAA.',
Bh='Bhalin:BAAALgAECgUJCQABLgAECggJKQADAP4fAA==.',
Bi='Bielinski:BAAALgAECgQJBAAAAA==.Biinarc:BAAALgAECgEJAQAAAA==.',
Bl='Blackdut:BAACLgAFFH8IAAINAAMJtgQ1igCrAAANAAMJtgQ1igCrAAAuAAQKfxUAAw0ABwmyEQJsAGMBAA0ABwl5EQJsAGMBAAwABAkpCiIlAIYAAAAA.Blackfear:BAAALgAECgQJBgABLgAFFAIJBgABAPQNAA==.Blackrøse:BAAALgADCgYJBgAAAA==.Blackteriaa:BAABLgAECn8UAAIHAAYJ/RNDmABFAQAHAAYJ/RNDmABFAQAAAA==.Blacrapumzel:BAAALgAECgMJAwAAAA==.Blakwolf:BAAALgAECgYJCQAAAA==.Blankis:BAAALgADCgYJCQAAAA==.Blastoize:BAAALgAECgQJCAAAAA==.Blizther:BAAALgADCgIJAgAAAA==.Bloodh:BAAALgAECgUJCQAAAA==.Bls:BAAALgADCgMJAwAAAA==.',
Bo='Boijf:BAAALgADCgEJAQAAAA==.Boladomal:BAAALgAECgMJBAAAAA==.Bolt:BAAALgADCgIJAgAAAA==.Bones:BAAALgAECgEJAQAAAA==.Boromy:BAAALgAECgcJDQAAAA==.Boruck:BAAALgAECgIJAwAAAA==.',
Br='Braandom:BAAALgAECgcJEAAAAA==.Bradan:BAABLgAECn8eAAIPAAgJURWcKgAOAgAPAAgJURWcKgAOAgAAAA==.Brandomm:BAAALgAECgYJDwAAAA==.Branmir:BAAALgAECgMJBgAAAA==.Bridda:BAAALgAECggJEAAAAA==.Brolho:BAAALgADCgEJAQAAAA==.Brusque:BAAALgAECgcJCgAAAA==.Bruzapaladin:BAAALgADCgUJBQAAAA==.',
Bt='Btrcaotics:BAAALgAECgIJCAAAAA==.Btrguard:BAAALgAECgIJAgAAAA==.',
['Bé']='Béto:BAABLgAECn8WAAIIAAkJXx28CwD7AgAIAAkJXx28CwD7AgAAAA==.',
['Bí']='Bíbs:BAABLgAECn8VAAIBAAgJkRMtVQCfAQABAAgJkRMtVQCfAQAAAA==.',
Ca='Cabanagé:BAAALgAECgUJBwAAAA==.Cabeludometa:BAAALgAECgYJDAAAAA==.Cabodecobre:BAAALgAECgUJCwAAAA==.Cainmarko:BAAALgAECgYJEAAAAA==.Caiowisk:BAABLgAECn8eAAMNAAgJNgoDiwAjAQANAAgJSQcDiwAjAQAMAAMJZxCFLABjAAAAAA==.Calir:BAAALgADCgYJFgAAAA==.Calçadora:BAACLgAFFH8GAAIQAAIJYxXjJwCSAAAQAAIJYxXjJwCSAAAuAAQKf0EAAhAACQmqIYEFAM0CABAACQmqIYEFAM0CAAAA.Caquinha:BAAALgAECgEJAQAAAA==.Cardrok:BAAALgADCgEJAQAAAA==.Caridosa:BAAALgADCgUJBQAAAA==.Carnius:BAACLgAFFH8MAAMRAAMJmhXnHACpAAARAAMJmhXnHACpAAALAAEJDAXERQA0AAAuAAQKf0QABBEACAlHHhoRANUBABEACAkhHRoRANUBAA8AAgm6IMORAEoAAAsAAQkPHGRsAEMAAAAA.Casipala:BAAALgAECgIJAgAAAA==.Casuall:BAAALgAECgcJBwAAAA==.Cataclysm:BAAALgAECgMJBAAAAA==.Catalango:BAAALgAECgQJCgAAAA==.Catapó:BAAALgAFFAEJAQAAAA==.Catapózão:BAABLgAECn8zAAICAAkJniCUBgBMAwACAAkJniCUBgBMAwAAAA==.Catü:BAAALgAECgEJAQAAAA==.Cavernus:BAAALgADCgMJAwAAAA==.Caves:BAAALgADCgIJAgAAAA==.Caveston:BAAALgADCgUJCgAAAA==.',
Cb='Cbestabr:BAAALgADCgYJBgAAAA==.',
Ch='Chamadmordor:BAAALgAECgMJBQAAAA==.Charats:BAAALgADCgYJDQAAAA==.Charterine:BAAALgADCgYJBgAAAA==.Chaya:BAAALgADCgUJBQAAAA==.Chicknorris:BAAALgADCgUJBQAAAA==.Chifrudaxl:BAAALgAECgMJAwAAAA==.Chrisjks:BAAALgADCgYJCgAAAA==.',
Ci='Cindyn:BAAALgAECgEJAQAAAA==.',
Cl='Clared:BAAALgADCgEJAQAAAA==.Clarkcrente:BAAALgADCgYJBgABLgAECgMJAwASAAAAAA==.Clebeya:BAAALgADCgQJBAAAAA==.Climps:BAABLgAECn8WAAIBAAgJRRfuOwDsAQABAAgJRRfuOwDsAQAAAA==.',
Co='Cobyx:BAAALgADCgcJDAAAAA==.Cocaferoz:BAAALgADCgEJAQAAAA==.Coffeeaddict:BAAALgADCgMJAwAAAA==.Colugo:BAAALgADCgIJAgAAAA==.Coriisco:BAAALgADCgIJAgAAAA==.Corollaxei:BAABLgAECn83AAQTAAkJsxfVCwAXAgATAAkJsxfVCwAXAgAUAAYJsQkMRwALAQAVAAEJWAyaJQAyAAAAAA==.Cosculluela:BAAALgADCgUJBwAAAA==.Cosmuh:BAAALgAECgUJBQAAAA==.',
Cr='Crauwlinhu:BAAALgAECgMJAwAAAA==.Cretaceous:BAAALgADCgEJAQAAAA==.Creuzapriest:BAAALgAECgEJAQAAAA==.Cristïe:BAAALgAECgUJBQAAAA==.Crookedyoung:BAAALgAECgEJAwABLgAECgcJEAASAAAAAA==.Cruzade:BAABLgAECn8VAAMGAAcJXxA/IwD3AAAGAAYJwBA/IwD3AAADAAYJdw8d6QDPAAABLgAFFAIJBgABAPQNAA==.Cröwllëy:BAACLgAFFH8IAAIWAAMJiw1JowDPAAAWAAMJiw1JowDPAAAuAAQKfyMAAhYACAnZF9tDAPUBABYACAnZF9tDAPUBAAAA.',
Cu='Cubatao:BAABLgAECn8UAAIBAAYJUxQ0hQAvAQABAAYJUxQ0hQAvAQAAAA==.Cucaracha:BAABLgAECn8YAAINAAYJVBakbwBaAQANAAYJVBakbwBaAQAAAA==.',
Da='Dahaka:BAAALgADCgEJAQAAAA==.Dahhak:BAAALgAECgUJCwAAAA==.Dakhgagul:BAAALgADCgUJBQAAAA==.Dakshayani:BAAALgAECgQJBQAAAA==.Dalaigalds:BAAALgAECgEJAQAAAA==.Danielbrz:BAAALgAECgUJBwAAAA==.Daniellpvp:BAAALgADCgEJAQAAAA==.Danygatuxa:BAAALgAECgUJDQAAAA==.Daree:BAAALgAECgEJAQAAAA==.Darkenes:BAAALgAECgEJAQAAAA==.Darkinmt:BAAALgADCgcJCAAAAA==.Darknesstk:BAAALgAECgYJEAAAAA==.Darkowllskul:BAAALgAECgQJBwABLgAECgYJEgASAAAAAA==.Darksiderptc:BAAALgADCgcJDwAAAA==.Darthmansur:BAABLgAFFH8FAAIPAAIJAgJ5SwBdAAAPAAIJAgJ5SwBdAAAAAA==.Dasmithy:BAAALgAECgEJAQAAAA==.',
De='Deadvi:BAABLgAECn8YAAIXAAgJXh02DQA7AgAXAAgJXh02DQA7AgAAAA==.Deadziin:BAABLgAECn8ZAAMYAAgJigQ2FwC7AAAYAAcJTAM2FwC7AAAZAAMJpgXhSgB/AAAAAA==.Deathbringër:BAAALgAECgEJAQAAAA==.Deathheav:BAAALgADCgQJBAAAAA==.Deathmäsk:BAAALgADCgcJBwAAAA==.Defensivepls:BAAALgAECgYJBQAAAA==.Demetrix:BAAALgADCgkJCgAAAA==.Dennyam:BAAALgAECgYJCQAAAA==.Derothey:BAABLgAECn8pAAIHAAgJYBbBWADQAQAHAAgJYBbBWADQAQAAAA==.Deservis:BAAALgADCgYJBgAAAA==.Deulorem:BAACLgAFFH8PAAIaAAQJih54DwBUAQAaAAQJih54DwBUAQAuAAQKfz0AAhoACQmBIwECAIwDABoACQmBIwECAIwDAAAA.Devilblade:BAABLgAECn8RAAIbAAgJXgmljwACAQAbAAgJXgmljwACAQAAAA==.',
Di='Diabolynn:BAAALgAECgcJEwAAAA==.',
Dk='Dkatraia:BAAALgAECgMJAwAAAA==.',
Dn='Dngfafinir:BAAALgAECgkJDwABLgAFFAUJDAADAFgXAA==.Dnghidan:BAACLgAFFH8MAAIDAAUJWBd+QQAjAQADAAUJWBd+QQAjAQAuAAQKfygAAgMACQmrHvohAKICAAMACQmrHvohAKICAAAA.Dngpain:BAAALgAECgUJDAABLgAFFAUJDAADAFgXAA==.Dngtobi:BAAALgAECgUJCQABLgAFFAUJDAADAFgXAA==.',
Do='Dollynhø:BAABLgAECn8nAAIcAAkJFSBbBgDkAgAcAAkJFSBbBgDkAgAAAA==.Donyed:BAAALgAECgUJCwAAAA==.Doomsman:BAAALgADCgUJBQAAAA==.Dottado:BAAALgADCgcJCgAAAA==.',
Dr='Drackah:BAAALgADCgcJBwAAAA==.Draconían:BAAALgAECgEJBwAAAA==.Dracón:BAAALgAECgYJDAAAAA==.Draigo:BAAALgAECgIJAgAAAA==.Dreykar:BAABLgAECn8uAAMbAAkJfBhGIwBAAgAbAAkJfBhGIwBAAgAdAAEJ2ByPLABNAAAAAA==.Drogorn:BAAALgAECgUJCwAAAA==.Druidaezeki:BAAALgADCgYJCwAAAA==.Druidjm:BAAALgADCgMJAwAAAA==.Druvannar:BAAALgADCgEJAQAAAA==.Dröwränger:BAAALgADCgYJCwAAAA==.',
Du='Dultrasenegl:BAABLgAECn8lAAIBAAYJAA3yZQA2AQABAAYJAA3yZQA2AQAAAA==.Dunois:BAAALgAECgIJBgABLgAECgUJCwASAAAAAA==.',
['Dä']='Dähäkä:BAABLgAECn8dAAIDAAkJJBugIwB1AgADAAkJJBugIwB1AgAAAA==.',
Ed='Edven:BAACLgAFFH8RAAITAAMJTAO1IwB5AAATAAMJTAO1IwB5AAAuAAQKfyEAAhMABgnKDMYlAEgBABMABgnKDMYlAEgBAAAA.',
Ei='Eini:BAAALgAECgEJAgAAAA==.',
El='Elbermt:BAAALgAECgEJAQAAAA==.Elbruxão:BAAALgAECgEJAQAAAA==.Eldrick:BAAALgADCgMJAwAAAA==.Eldros:BAAALgAECgYJCAAAAA==.Elementais:BAABLgAECn8eAAIIAAcJDw9sTwBvAQAIAAcJDw9sTwBvAQAAAA==.Elgado:BAAALgAECgEJAwAAAA==.Elgatadexota:BAAALgADCgkJCgAAAA==.Eliksir:BAAALgAECgUJBQAAAA==.Ellanor:BAABLgAECn8dAAIHAAgJ+hgpVADdAQAHAAgJ+hgpVADdAQAAAA==.Ellocopere:BAAALgAECgEJAQAAAA==.Elruth:BAAALgADCggJCAABLgAFFAQJDwAaAIoeAA==.Eltão:BAAALgAECgEJAgAAAA==.Elunah:BAAALgADCgQJBAAAAA==.Elwindor:BAAALgAECgEJAQAAAA==.Elyind:BAAALgADCgYJBwAAAA==.Elyn:BAAALgAECgUJBwAAAA==.',
Em='Emmymm:BAAALgAECgEJAQAAAA==.',
En='Endeavour:BAAALgADCgEJAQAAAA==.Enegadiel:BAABLgAECn8pAAIDAAcJWxUucgCHAQADAAcJWxUucgCHAQAAAA==.Enoia:BAAALgADCgcJDQAAAA==.',
Eq='Equidnah:BAAALgAECgIJAgAAAA==.',
Er='Erickya:BAAALgAECggJEgAAAA==.Ervadocè:BAABLgAECn8ZAAIEAAYJwhjbNABAAQAEAAYJwhjbNABAAQAAAA==.Ervelino:BAAALgAECgMJBAAAAA==.Eryz:BAAALgAECgMJBAAAAA==.',
Es='Estrogosbald:BAABLgAECn8ZAAIeAAgJMQyuBgBMAQAeAAgJMQyuBgBMAQAAAA==.',
Eu='Euteinvoco:BAAALgAECgIJAgABLgAECgUJBQASAAAAAA==.',
Ev='Evely:BAABLgAECn8iAAIfAAgJ0hqZBwAGAgAfAAgJ0hqZBwAGAgAAAA==.',
Ex='Exarch:BAACLgAFFH8NAAIQAAQJaRSaEwArAQAQAAQJaRSaEwArAQAuAAQKfysAAhAACQm/IWIDAAEDABAACQm/IWIDAAEDAAAA.',
Fa='Faengar:BAAALgAECgUJCAAAAA==.Falcondk:BAAALgAECgEJAQAAAA==.Falconess:BAAALgADCgEJAQAAAA==.',
Fe='Feathria:BAAALgAECgMJAwAAAA==.Felipebritoo:BAAALgAECgMJBgABLgAECgYJEgASAAAAAA==.Fenrirsp:BAABLgAECn8XAAMgAAgJcyFGGwDpAQAgAAYJpyFGGwDpAQAhAAQJxxp6NQA+AQAAAA==.Ferdruiid:BAAALgADCgkJEwAAAA==.Feropudo:BAAALgADCgkJDgAAAA==.Ferrarig:BAAALgAECgEJBQAAAA==.',
Fi='Figy:BAAALgAECgQJBAAAAA==.Filixy:BAAALgADCgYJBgAAAA==.',
Fl='Flemma:BAABLgAECn8YAAITAAgJJgd7HQALAQATAAgJJgd7HQALAQAAAA==.Flexer:BAAALgAECgIJAgAAAA==.Flores:BAAALgADCgMJBgAAAA==.Floridastyle:BAABLgAECn8fAAIhAAUJTxZXNwA1AQAhAAUJTxZXNwA1AQAAAA==.',
Fo='Foguerosa:BAACLgAFFH8JAAMHAAMJpRyQLwD4AAAHAAMJpRyQLwD4AAAiAAEJggDcBwAxAAAuAAQKfxYAAgcACAlpIVREAGsCAAcACAlpIVREAGsCAAAA.Folghunthir:BAAALgADCgQJBAAAAA==.',
Fr='Frankkquini:BAAALgADCgYJEgAAAA==.Friodokrl:BAACLgAFFH8IAAIWAAMJIw45ogDQAAAWAAMJIw45ogDQAAAuAAQKfzYAAxcACQkHHuUOABsCABcACQkuG+UOABsCABYACAkdGvlDAPQBAAAA.Fritzgerhart:BAAALgAECgEJAQAAAA==.Frostkller:BAAALgADCgIJAgAAAA==.Frostmhaw:BAAALgADCgUJBQAAAA==.Frostreaper:BAAALgAECgQJBgAAAA==.',
Fu='Fubukiofhell:BAACLgAFFH8FAAIHAAMJMBIMewDnAAAHAAMJMBIMewDnAAAuAAQKfxoAAgcACAnVGXhAABgCAAcACAnVGXhAABgCAAAA.Fuginzao:BAAALgAECgEJAQAAAA==.Furtacor:BAAALgAECgEJAQAAAA==.Furyarh:BAAALgAECgMJAwAAAA==.',
['Fí']='Fí:BAAALgADCggJDgABLgAECgkJHQABALAaAA==.',
Ga='Gabana:BAAALgADCgQJBAAAAA==.Gabdobbuh:BAAALgAECgUJCAAAAA==.Gabn:BAAALgAECgMJBgAAAA==.Gafgar:BAAALgADCgUJCQAAAA==.Gaila:BAAALgAECgIJBgAAAA==.Galduin:BAACLgAFFH8HAAIPAAMJ5wwFOADMAAAPAAMJ5wwFOADMAAAuAAQKfzAAAg8ACQlBGDAYACsCAA8ACQlBGDAYACsCAAAA.',
Ge='Gedexx:BAAALgAECgMJAgAAAA==.Geduntruppa:BAAALgAECgYJBgAAAA==.Gentioiroh:BAAALgAECgQJBAAAAA==.',
Gh='Ghorderp:BAAALgADCgcJDAAAAA==.Ghosstt:BAAALgAECgEJAgAAAA==.Ghoulrozon:BAAALgADCgYJBgAAAA==.',
Gi='Giovannapala:BAABLgAECn8ZAAIDAAgJ/A3pnAA5AQADAAgJ/A3pnAA5AQAAAA==.Giovannasham:BAAALgAECgEJAwAAAA==.Giripoca:BAAALgAECgQJCQAAAA==.',
Gl='Gladsmonge:BAABLgAECn8pAAIjAAcJ3h9uFQBpAgAjAAcJ3h9uFQBpAgAAAA==.Glorcckk:BAAALgAECgMJAwAAAA==.',
Gn='Gnomagga:BAAALgAECgcJEAABLgAECggJNgAGAB8cAA==.Gnomohabe:BAAALgADCgQJBgAAAA==.',
Go='Goddofwarr:BAAALgADCggJEQAAAA==.Gonb:BAAALgADCgUJBQAAAA==.Goueki:BAABLgAECn80AAMBAAgJmBqGLwAZAgABAAgJmBqGLwAZAgAfAAIJSwEtgwA8AAAAAA==.',
Gr='Greenzle:BAAALgAECgUJBgAAAA==.Grillnborst:BAAALgADCgEJAgAAAA==.Grilonp:BAAALgADCgQJCAAAAA==.Grogath:BAAALgAECgQJCAAAAA==.Grogtixa:BAAALgAECggJCQABLgAECgkJKgAJAFcWAA==.Gromoff:BAABLgAFFH8HAAINAAIJwiRJgQC9AAANAAIJwiRJgQC9AAAAAA==.Grunmonk:BAAALgADCgEJAQAAAA==.Grømmar:BAAALgADCgMJAwAAAA==.',
Gu='Gudangara:BAAALgAECgIJAgAAAA==.Gumy:BAAALgAECgEJBAAAAA==.Guztaverdead:BAAALgADCgQJBAAAAA==.',
['Gü']='Güistrong:BAAALgADCgIJAwAAAA==.',
Ha='Haakaí:BAAALgAECgUJEAAAAA==.Haandir:BAAALgAECgMJBQAAAA==.Hackterin:BAAALgADCgYJBgAAAA==.Hadorah:BAAALgAECgUJBgAAAA==.Haerys:BAAALgAFFAEJAQAAAA==.Handhemirr:BAAALgAECgMJBAAAAA==.Harany:BAABLgAECn8nAAMhAAgJXRcxEgBRAgAhAAgJXRcxEgBRAgAgAAYJywtZSQDnAAAAAA==.Harrypotinho:BAABLgAECn8xAAINAAgJch2OJgBBAgANAAgJch2OJgBBAgAAAA==.Haunexd:BAAALgADCgMJAwAAAA==.Havenna:BAAALgAECgUJCAAAAA==.',
He='Headøhunter:BAAALgAECgEJAgAAAA==.Healgate:BAAALgAECgEJAQAAAA==.Heeythaly:BAAALgADCgcJEQAAAA==.Helessa:BAAALgAECgEJAQAAAA==.Hellenah:BAAALgADCggJCAAAAA==.Herablack:BAAALgAECgQJBAAAAA==.Herika:BAAALgADCgMJAwAAAA==.',
Hi='Hidenz:BAAALgADCgIJAwAAAA==.',
Ho='Hoem:BAAALgAECgMJAwAAAA==.Holand:BAAALgAECgYJDAAAAA==.Holydread:BAAALgAECgIJAgAAAA==.',
Hu='Hulig:BAABLgAECn8pAAMDAAgJ/h+zJgBnAgADAAgJ/h+zJgBnAgAGAAEJAQeaUwAnAAAAAA==.Hunthearthas:BAAALgAECgMJAwAAAA==.',
['Hø']='Høkulani:BAABLgAECn8dAAIHAAcJchHuiQBgAQAHAAcJchHuiQBgAQAAAA==.',
Ib='Ibrad:BAAALgAECgQJBAAAAA==.Ibuprofens:BAAALgAECgEJAQAAAA==.',
Ic='Iceyag:BAAALgAECgIJAgAAAA==.',
Ig='Igthil:BAAALgADCgYJCwAAAA==.',
Ik='Ikiam:BAAALgAECgUJDAAAAA==.Ikslawok:BAAALgADCgYJEAAAAA==.',
Il='Ileria:BAAALgAECgYJBwAAAA==.Iliriana:BAAALgAECgEJAQAAAA==.Illarion:BAAALgADCgQJBAAAAA==.Illidanos:BAABLgAECn8cAAIkAAgJ/RFLHwB7AQAkAAgJ/RFLHwB7AQAAAA==.Illidansan:BAAALgAECgQJBQABLgAECgYJCwASAAAAAA==.Illidris:BAAALgAECgUJBQAAAA==.Illumiinated:BAABLgAECn8UAAIlAAYJiwxlHADCAAAlAAYJiwxlHADCAAAAAA==.',
In='Incarus:BAAALgAECgcJCgAAAA==.Incognita:BAAALgAECgEJAQAAAA==.Indis:BAAALgADCgQJBgAAAA==.Interst:BAAALgAECgEJAQAAAA==.',
Ir='Irion:BAAALgAECgQJBQAAAA==.',
Is='Iscalio:BAAALgAECgYJCgAAAA==.',
It='Itatchii:BAAALgAECgQJBQAAAA==.',
Iv='Ivinhosilva:BAAALgADCgYJBgAAAA==.',
Ja='Jackdawnsong:BAABLgAECn8aAAIHAAgJiRrNOQAvAgAHAAgJiRrNOQAvAgAAAA==.Jaene:BAAALgADCgYJCQAAAA==.Jahuun:BAABLgAECn8aAAIDAAcJ7Q0qmQBAAQADAAcJ7Q0qmQBAAQAAAA==.Jamantoso:BAAALgAECgEJAQAAAA==.',
Je='Jeess:BAAALgADCgMJAwAAAA==.Jefflich:BAABLgAECn8iAAMWAAgJ4AqUiQBuAQAWAAgJiwmUiQBuAQAmAAEJhxLwOgAuAAAAAA==.',
Jg='Jg:BAAALgAECgUJBwABLgAECgYJDgASAAAAAA==.',
Ji='Jinknu:BAAALgAECgIJBAAAAA==.',
Jo='Jottapeg:BAAALgADCgcJAwAAAA==.',
Ju='Jubard:BAAALgADCgkJDAAAAA==.Juliamarques:BAAALgAECgMJBAAAAA==.',
['Jü']='Jüllÿe:BAAALgADCgEJAQAAAA==.',
Ka='Kaaellthas:BAAALgAECgQJDQAAAA==.Kacolux:BAAALgADCgEJAQAAAA==.Kaisaargente:BAAALgAECgEJAQAAAA==.Kakarotho:BAAALgAECgMJCQAAAA==.Kalarath:BAAALgAECgYJBgAAAA==.Kaldonios:BAAALgADCgcJEgAAAA==.Kalma:BAAALgAECgEJAQAAAA==.Kamasutram:BAAALgADCgYJCwAAAA==.Kanadriel:BAAALgAECgcJDAAAAA==.Kanarinho:BAABLgAECn80AAICAAkJIh/MCAApAwACAAkJIh/MCAApAwAAAA==.Karmussie:BAAALgADCgEJAQAAAA==.Karmysh:BAAALgAECgMJAwAAAA==.Katari:BAAALgAECgYJCgABLgAECgkJIAAnAAMfAA==.Kayanz:BAAALgADCgUJBQAAAA==.Kazandra:BAAALgADCgYJBgAAAA==.',
Ke='Kendars:BAABLgAECn8VAAQEAAYJ0xKfSAAKAQAEAAUJJhKfSAAKAQACAAUJFQ+5dgDzAAAFAAEJhRXVSABDAAABLgAFFAMJBwAXALAMAA==.Keox:BAAALgADCgUJBQAAAA==.Ket:BAAALgADCgMJAwAAAA==.',
Kh='Khanmir:BAAALgAECgMJBgAAAA==.Kharon:BAAALgAECgYJBwAAAA==.Khild:BAAALgAECgYJDQAAAA==.Khonar:BAAALgADCgUJBwAAAA==.',
Ki='Killerdek:BAAALgAECgUJBQAAAA==.Killshoty:BAAALgAECgEJAgAAAA==.',
Kl='Klissera:BAAALgADCgQJBAAAAA==.Kluzlocak:BAABLgAECn8iAAIhAAYJUQwwPQAXAQAhAAYJUQwwPQAXAQAAAA==.',
Ko='Komah:BAAALgAECgEJAQAAAA==.Korav:BAAALgAECgMJCQABLgAFFAEJAQASAAAAAA==.Korium:BAAALgADCgUJBQABLgAECgkJOAARAFckAA==.Koruno:BAAALgADCgYJBgAAAA==.',
Kr='Krosn:BAAALgAECgEJAQAAAA==.Krozhul:BAAALgAECgcJDQAAAA==.Krypthor:BAAALgAECgEJAQAAAA==.',
Ku='Kurnous:BAAALgAECgEJAQAAAA==.Kutirenzo:BAAALgADCgUJBwAAAA==.',
La='Lafiel:BAAALgAECgcJEQAAAA==.Lahllis:BAAALgADCgEJAgAAAA==.Lahnara:BAAALgAECgcJCAAAAA==.Lamelo:BAAALgADCgYJBgAAAA==.Lanjelanje:BAAALgAECgQJBQAAAA==.Lanmo:BAAALgAFFAIJAwAAAA==.Largatixazul:BAAALgADCgUJBgAAAA==.Lataria:BAAALgADCgEJAQAAAA==.Laurea:BAAALgAECgkJEQABLgAECgkJIAAnAAMfAA==.',
Le='Ledor:BAAALgAECgEJAgAAAA==.Leebron:BAAALgAECgYJDAAAAA==.Lefthalas:BAAALgAECgUJCgAAAA==.Leitchero:BAAALgAECgIJAgAAAA==.Lemaz:BAAALgAECgEJAQAAAA==.Lemonhunter:BAAALgAECgYJCAAAAA==.Leonelmessi:BAAALgAFFAQJAgAAAA==.Lesco:BAAALgADCgMJAwAAAA==.',
Li='Lianele:BAAALgAECgcJDAAAAA==.Liaras:BAABLgAECn8pAAMaAAgJXBf3HQDRAQAaAAgJXBf3HQDRAQAgAAIJzABFaQAmAAAAAA==.Libertinagem:BAAALgAECgYJDQAAAA==.Lichtbaum:BAABLgAECn8iAAMCAAgJQR1aIABAAgACAAgJQR1aIABAAgAEAAUJwxkHOAAwAQAAAA==.Lightsertrop:BAAALgADCgIJAgAAAA==.Liifecomm:BAACLgAFFH8VAAIaAAUJSRTIDQBpAQAaAAUJSRTIDQBpAQAuAAQKfzwAAhoACQl+HlkNAIICABoACQl+HlkNAIICAAAA.Liike:BAAALgAECgcJDQAAAA==.Linestra:BAAALgADCgUJBQAAAA==.Liniak:BAAALgAECgcJEAAAAA==.Lisong:BAAALgAECgIJAgAAAA==.Littlepurple:BAACLgAFFH8JAAIbAAMJzxJ7GwD2AAAbAAMJzxJ7GwD2AAAuAAQKfyQAAhsACQl0HJwYAMICABsACQl0HJwYAMICAAAA.',
Lo='Longhai:BAAALgADCgUJCAAAAA==.Lookatmylock:BAABLgAECn8iAAMMAAYJ/xtmDAB1AQAMAAYJ/xtmDAB1AQANAAIJmBFZGQFLAAAAAA==.Lordpain:BAAALgAECggJDgAAAA==.Lortherti:BAAALgAECgIJAgAAAA==.Lorwin:BAABLgAECn8UAAIBAAgJhBnVSADCAQABAAgJhBnVSADCAQAAAA==.Lotusbr:BAAALgADCgEJAQAAAA==.Louisenacioo:BAABLgAECn8UAAMTAAcJUhBRFQBzAQATAAcJUhBRFQBzAQAUAAMJqwW+eQBpAAAAAA==.Loátrak:BAAALgADCgMJAwAAAA==.',
Lu='Luanne:BAAALgADCgEJAQAAAA==.Luccablack:BAAALgAECgMJAwAAAA==.Luccagelido:BAAALgAECgUJCAAAAA==.Lucyx:BAAALgAECgIJAgAAAA==.Luidar:BAAALgAECgQJBAAAAA==.Lukaslions:BAABLgAECn8gAAIPAAkJaA+kKwClAQAPAAkJaA+kKwClAQAAAA==.Lukathan:BAAALgADCgQJBAAAAA==.Lunarie:BAAALgAECgYJEwABLgAECgcJBwASAAAAAA==.Luphoe:BAABLgAECn8nAAMCAAcJ9RzHJwAWAgACAAcJ9RzHJwAWAgAEAAQJkw57YgCLAAAAAA==.Luxanä:BAAALgAECgYJBgAAAA==.',
['Lé']='Léio:BAAALgADCgcJCAAAAA==.Léora:BAAALgADCgIJAgAAAA==.',
['Lø']='Lørdsith:BAAALgAECgYJCAABLgAECggJBgASAAAAAA==.',
['Lÿ']='Lÿcäns:BAAALgADCgMJAwAAAA==.',
Ma='Madagalux:BAABLgAECn8rAAIOAAgJQQp9DwBgAQAOAAgJQQp9DwBgAQAAAA==.Madalenna:BAAALgAECgMJBQAAAA==.Madjack:BAAALgAECgMJAwAAAA==.Madushi:BAAALgAFFAEJAQAAAA==.Madzerø:BAAALgAECgEJAgAAAA==.Magatiun:BAAALgADCgMJBAAAAA==.Magogunt:BAABLgAECn8kAAIHAAkJMxF1UwDfAQAHAAkJMxF1UwDfAQAAAA==.Maguul:BAABLgAECn8ZAAIGAAgJ5hVPEQCsAQAGAAgJ5hVPEQCsAQAAAA==.Magzifeh:BAABLgAECn8UAAIBAAcJ3SC2OQDzAQABAAcJ3SC2OQDzAQAAAA==.Mahadevi:BAAALgADCgIJAgAAAA==.Mahdemon:BAAALgAECgYJCQAAAA==.Maiconhood:BAAALgAFFAEJAQAAAA==.Malandrvs:BAAALgAFFAEJAwAAAA==.Maljamim:BAAALgADCgIJAgAAAA==.Mamuthwar:BAABLgAECn8ZAAMPAAcJnRgeNgDQAQAPAAcJnRgeNgDQAQALAAEJMQ7ZQQA1AAAAAA==.Mandingavudu:BAAALgAECgYJBwABLgAFFAEJAQASAAAAAA==.Manei:BAAALgAECgMJAwAAAA==.Mangalarga:BAAALgADCgEJAQAAAA==.Manmoden:BAAALgADCgUJBQABLgAFFAEJAQASAAAAAA==.Mannatur:BAABLgAECn8bAAMEAAkJ6hwhEgBDAgAEAAgJ3xshEgBDAgAlAAgJaheGEQDQAQABLgAFFAEJAQASAAAAAA==.Manopaladino:BAAALgADCgYJBgAAAA==.Manowlo:BAAALgAECgMJAwAAAA==.Manzagon:BAAALgAECgYJCQABLgAFFAEJAQASAAAAAA==.Marandracon:BAAALgADCgMJAwAAAA==.Marmelo:BAAALgADCgQJBAAAAA==.Marretasanta:BAABLgAECn8kAAIDAAcJCRSEjQBUAQADAAcJCRSEjQBUAQAAAA==.Maruterrestr:BAAALgAECgMJAgAAAA==.Marù:BAAALgAECgYJCwAAAA==.Marúh:BAACLgAFFH8SAAIIAAUJPRgcIQBkAQAIAAUJPRgcIQBkAQAuAAQKfygAAggACAnzIsQFABYDAAgACAnzIsQFABYDAAAA.Matedellmor:BAAALgADCgIJAwAAAA==.Matroná:BAAALgADCggJBwAAAA==.Maxmorf:BAAALgADCgUJBQAAAA==.Mayarabr:BAAALgAECgYJDwAAAA==.Mazeratos:BAAALgAECgMJBQAAAA==.',
Mc='Mcorelhao:BAAALgADCgEJAQAAAA==.',
Me='Medoza:BAAALgAECgQJBgAAAA==.Megrezz:BAAALgAECgEJAQAAAA==.Mehiel:BAAALgAECgEJAQAAAA==.Mekihlvshtak:BAAALgAECgYJBwAAAA==.Meliøðas:BAAALgADCgEJAQAAAA==.Mendingu:BAABLgAECn8YAAMLAAgJAhx8GgCDAQAPAAgJRxgYKAAdAgALAAQJ/CB8GgCDAQAAAA==.Mercenarybr:BAAALgAECgEJAgAAAA==.Merumim:BAAALgAECgYJCwAAAA==.Metalgirl:BAAALgADCgYJCwAAAA==.Methamorfo:BAAALgADCggJCQAAAA==.',
Mi='Midrão:BAAALgAFFAEJAQAAAA==.Miisuky:BAAALgADCgUJBAAAAA==.Mikasaackerr:BAAALgAECgEJAgAAAA==.Milczarek:BAAALgAECgEJAwAAAA==.Mindlocker:BAABLgAECn8dAAINAAcJMwknkQAYAQANAAcJMwknkQAYAQAAAA==.Minorus:BAAALgAFFAIJAgAAAA==.Mirager:BAAALgAECgQJBAAAAA==.Mistifs:BAABLgAECn8pAAIjAAgJ5R0ZDwCsAgAjAAgJ5R0ZDwCsAgAAAA==.Miticamais:BAAALgAECgQJBQAAAA==.',
Mo='Modogz:BAAALgADCgYJBgAAAA==.Momongadk:BAAALgADCgcJBwAAAA==.Monkeydking:BAAALgADCgUJBQAAAA==.Morania:BAABLgAECn8XAAIMAAgJUwZiFwDjAAAMAAgJUwZiFwDjAAAAAA==.Mordekais:BAAALgAECgIJAgAAAA==.Morganne:BAAALgAECgEJAQAAAA==.Morinami:BAAALgAECgQJBAAAAA==.Moriyama:BAABLgAECn8pAAMCAAkJuhveIAA9AgACAAgJwBreIAA9AgAEAAIJExLAagBxAAAAAA==.Morphisz:BAAALgAFFAEJAQAAAA==.Morphiszs:BAAALgAECgMJBQABLgAFFAEJAQASAAAAAA==.Morphizs:BAAALgAECgEJBAABLgAFFAEJAQASAAAAAA==.Mortesan:BAAALgAECgEJAQABLgAECgYJCwASAAAAAA==.',
Mp='Mpastor:BAAALgADCgUJBQAAAA==.',
Mu='Muca:BAAALgADCgEJAQAAAA==.Muho:BAAALgADCgEJAQAAAA==.Mukonha:BAABLgAECn8jAAINAAcJeA5sigAkAQANAAcJeA5sigAkAQAAAA==.',
['Mã']='Mãoleves:BAAALgADCgEJAQAAAA==.',
['Må']='Måximus:BAAALgAECgUJCQAAAA==.',
['Mü']='Müller:BAAALgADCgEJAQABLgAECgcJEAASAAAAAA==.',
Na='Naeryndam:BAAALgADCgEJAQAAAA==.Namyara:BAAALgAECgEJAQAAAA==.Narutowow:BAAALgADCgMJAwAAAA==.Natcmd:BAAALgADCggJJQAAAA==.Nathilell:BAAALgADCgIJAgAAAA==.Navira:BAAALgAECgEJAQAAAA==.Nayanna:BAAALgADCgcJDQAAAA==.Nazzd:BAAALgAECgQJBAAAAA==.',
Ne='Negblack:BAABLgAFFH8GAAIBAAMJswrOZgDOAAABAAMJswrOZgDOAAAAAA==.Neggi:BAAALgAECgUJBwAAAA==.Nemesysy:BAAALgAECgMJAwAAAA==.Nerphien:BAAALgADCgUJBQAAAA==.Nesktpally:BAAALgAECgcJCAAAAA==.Netbrood:BAAALgADCgUJBgABLgAECgUJBwASAAAAAA==.Netbrother:BAAALgAECgUJBwAAAA==.Nethdorai:BAAALgADCgQJBAAAAA==.Netherbane:BAABLgAECn8tAAMLAAcJOh0RDwD6AQALAAcJOh0RDwD6AQAPAAIJGQ9ZoAA0AAAAAA==.Nezuko:BAAALgAECgUJBQABLgAECggJMQANAHIdAA==.',
Ni='Niar:BAAALgAECgQJBAAAAA==.Nightmære:BAAALgAECgQJCwAAAA==.Nikelok:BAABLgAECn8YAAINAAcJ9wZXpAD4AAANAAcJ9wZXpAD4AAAAAA==.Ninfador:BAABLgAECn8eAAIhAAYJgxcBMQBXAQAhAAYJgxcBMQBXAQAAAA==.Ninpus:BAAALgAECgMJAwAAAA==.',
No='Noobmasteer:BAAALgADCgIJAgAAAA==.Nooneknow:BAACLgAFFH8HAAIWAAQJTBXvjgDpAAAWAAQJTBXvjgDpAAAuAAQKfzkAAhYACQlUIcMVAMMCABYACQlUIcMVAMMCAAAA.Nosios:BAAALgAECgYJBgAAAA==.Nosrede:BAAALgAECgEJAQAAAA==.Notz:BAAALgADCgMJBAAAAA==.',
Nu='Nucciwarrior:BAAALgAECgUJCAAAAA==.Nuccixama:BAAALgAECgcJCQAAAA==.',
Ny='Nyde:BAAALgAECgMJAwAAAA==.',
['Nø']='Nøar:BAAALgADCgIJAgAAAA==.',
Oa='Oakshlar:BAAALgAFFAEJAQAAAA==.',
Oc='Ocelaris:BAAALgAECgEJAgAAAA==.',
Oh='Ohlu:BAAALgAECgYJCQAAAA==.Ohluh:BAAALgAECgcJDQAAAA==.',
Or='Ormagh:BAAALgADCgYJBgAAAA==.Oryana:BAAALgAECgEJAQAAAA==.Oríon:BAAALgADCgIJAgAAAA==.',
Ot='Otton:BAABLgAECn8oAAIDAAgJiggbuQAPAQADAAgJiggbuQAPAQAAAA==.',
Ov='Overnigth:BAAALgADCgIJAgAAAA==.Overwalker:BAAALgAECgEJAgAAAA==.Ovosemdente:BAAALgADCgEJAQAAAA==.',
Ow='Owllskull:BAAALgAECgYJEgAAAA==.',
Oz='Ozovo:BAAALgAECgcJEAAAAA==.',
Pa='Pacoka:BAAALgADCgQJBQAAAA==.Padrafferty:BAAALgADCgcJBwAAAA==.Paidesanto:BAABLgAECn8WAAQOAAcJyhB0GgDlAAAOAAYJKg90GgDlAAANAAYJMgsDzwC0AAAMAAMJ5RGTRgCcAAAAAA==.Paidesantox:BAABLgAECn8YAAIEAAcJRAn9QwD4AAAEAAcJRAn9QwD4AAABLgAFFAMJBwAPAOcMAA==.Paidocharles:BAAALgAECgIJBAAAAA==.Paladinokun:BAAALgAECgYJCwAAAA==.Palanis:BAAALgAECgcJBwAAAA==.Palazarta:BAABLgAECn8XAAIDAAcJBAqWugANAQADAAcJBAqWugANAQAAAA==.Pandavoli:BAAALgAECgUJDAAAAA==.Pangolinho:BAAALgAECgQJBQAAAA==.Panky:BAAALgAECgQJBAAAAA==.Panquecudo:BAAALgADCgIJAgAAAA==.',
Pd='Pdois:BAAALgADCgMJAwAAAA==.',
Pe='Pesscador:BAAALgAECgMJAwAAAA==.Petrolesk:BAAALgAECgYJEwAAAA==.',
Pi='Piriguetee:BAAALgADCgEJAQAAAA==.Pirro:BAAALgAECgEJAQAAAA==.Pisadinha:BAAALgADCgcJBwAAAA==.',
Pk='Pkzimn:BAAALgADCgUJBQAAAA==.',
Pl='Playsson:BAAALgAECgYJEgAAAA==.Plottwist:BAAALgADCgcJDwABLgAECgkJOAAWAOEaAA==.',
Po='Pogonus:BAAALgADCgIJAgAAAA==.Pontocego:BAAALgAECgQJBAAAAA==.Pororocaa:BAAALgAECgQJCAAAAA==.Posturado:BAAALgADCgEJAQAAAA==.Powerworth:BAAALgAECgEJAQAAAA==.',
Pr='Pravios:BAAALgAECggJDgAAAA==.Priestkill:BAAALgADCgcJCQAAAA==.Prikithon:BAAALgAECgEJAQAAAA==.Primewolf:BAAALgAECgMJAwAAAA==.',
Ps='Psicomanic:BAAALgADCgMJAwAAAA==.',
Pt='Pterodactilo:BAAALgAECgYJAQAAAA==.',
Pu='Puherito:BAAALgAECgUJDAAAAA==.Purgas:BAAALgAFFAEJAQAAAA==.',
Qu='Quartohokage:BAAALgADCgEJAQAAAA==.Quinthalam:BAAALgADCgMJAwAAAA==.',
Ra='Rafac:BAAALgAECgEJAgABLgAFFAEJAQASAAAAAA==.Rafazinho:BAAALgADCgQJBAAAAA==.Ramyna:BAAALgAECgMJBQAAAA==.Ramyra:BAAALgADCgcJDQAAAA==.Raphaeldh:BAAALgAECgEJAgAAAA==.Raphahunterr:BAAALgADCgEJAQAAAA==.Raposa:BAAALgADCgEJAQAAAA==.Raposinha:BAAALgADCgMJAwAAAA==.Rarkway:BAAALgAECgcJCwAAAA==.Ravenblak:BAAALgADCgMJAwAAAA==.Rayanne:BAAALgADCgYJBgAAAA==.',
Re='Reckfull:BAAALgAECgYJBgAAAA==.Regininha:BAAALgAECgEJAQAAAA==.Reloumifrend:BAAALgAECgcJCgAAAA==.Rendros:BAAALgADCgUJBQAAAA==.',
Rh='Rhaegaar:BAAALgAECgcJDQAAAA==.Rhanideri:BAAALgADCgEJAQAAAA==.Rhodinius:BAAALgAECgMJCAAAAA==.',
Ri='Rivotreel:BAAALgADCgQJBAAAAA==.',
Ro='Robeerth:BAABLgAFFH8GAAIBAAIJ9A3kfgCTAAABAAIJ9A3kfgCTAAAAAA==.Rochera:BAAALgAECgEJAQAAAA==.Rokhanar:BAAALgAECgUJCwAAAA==.',
Ru='Rudemonster:BAAALgAECgEJAQAAAA==.Ruhtarr:BAAALgADCgEJAQAAAA==.',
Ry='Ryukato:BAAALgAECgQJBQAAAA==.',
Sa='Saek:BAAALgAECgcJEgAAAA==.Saelor:BAAALgAECgEJAgAAAA==.Sanderclone:BAAALgAECgEJAQAAAA==.Sanguenafaca:BAAALgADCgYJCgAAAA==.Santiss:BAABLgAECn8WAAIDAAYJDhVApwApAQADAAYJDhVApwApAQAAAA==.Santorini:BAAALgAECgcJDQAAAA==.Saphirot:BAAALgADCgUJBQAAAA==.Saphis:BAAALgADCgEJAQAAAA==.Sardado:BAAALgAECgEJAQAAAA==.Sardron:BAAALgADCgMJAwAAAA==.',
Sc='Scanorr:BAAALgAECgYJDAAAAA==.Scheffers:BAABLgAECn8VAAIgAAYJvxJEOAAxAQAgAAYJvxJEOAAxAQAAAA==.',
Se='Selah:BAAALgADCgQJBgAAAA==.Selver:BAAALgAECgcJCAABLgAFFAcJGgAgALAaAA==.Selüne:BAAALgAECgcJDQAAAA==.Sephora:BAAALgAECgYJCwABLgAECggJKQAaAFwXAA==.Sevagoth:BAAALgAECggJDQAAAA==.',
Sh='Shadowlock:BAAALgADCgIJAQABLgAECgYJFAAbAN8UAA==.Shadowmornac:BAAALgAECgMJBgAAAA==.Shallkiller:BAAALgADCgIJBAAAAA==.Shamanica:BAAALgAECgEJAgAAAA==.Shamateus:BAAALgADCggJEwAAAA==.Shasuna:BAAALgADCgIJAgAAAA==.Shaunnun:BAAALgADCgEJAQAAAA==.Shenloong:BAAALgADCgYJBgAAAA==.Shinnók:BAAALgAECgIJAgAAAA==.Shiíro:BAAALgAFFAIJBAABLgAFFAUJEwADABAkAA==.Shynato:BAAALgADCgEJAQAAAA==.Shynock:BAAALgADCgEJAQAAAA==.Shyriull:BAAALgAECgEJAQAAAA==.Shyzuno:BAAALgADCgQJBAAAAA==.Shãka:BAAALgADCgMJAwAAAA==.',
Si='Siladriel:BAAALgADCgMJAwAAAA==.Silfirrion:BAAALgADCgEJAQABLgAECgkJPAAMAIEfAA==.Silvao:BAAALgADCgIJBAAAAA==.Sirgonzo:BAABLgAECn8XAAIDAAkJtxeHPQANAgADAAkJtxeHPQANAgAAAA==.',
Sk='Skullexus:BAAALgAECgMJBAAAAA==.Skunkbr:BAAALgADCgEJAQAAAA==.',
Sl='Sleepychety:BAAALgAECgUJBgAAAA==.Slowsmoke:BAAALgADCgYJBwAAAA==.Slyfer:BAABLgAFFH8GAAIBAAIJwRQJewCYAAABAAIJwRQJewCYAAAAAA==.',
Sn='Snatzz:BAAALgADCgMJAgAAAA==.',
So='Soggoth:BAAALgADCgkJCQAAAA==.Solk:BAAALgAECgMJBgAAAA==.Sontarfury:BAAALgAECgEJAQAAAA==.Soray:BAAALgAECgMJAwAAAA==.Sorim:BAABLgAECn8oAAICAAgJvhuUGwBnAgACAAgJvhuUGwBnAgAAAA==.Soryan:BAABLgAECn8qAAMCAAgJeBU5LwDlAQACAAgJeBU5LwDlAQAEAAUJ+g2rTwDKAAAAAA==.Soulassassin:BAAALgADCgIJAwAAAA==.Soulhell:BAABLgAECn8cAAIhAAYJaxSPMwBIAQAhAAYJaxSPMwBIAQAAAA==.',
Sp='Spartanlofs:BAAALgADCgcJEQAAAA==.Spawndeath:BAAALgADCgEJAQAAAA==.Spezia:BAAALgAECgEJAQAAAA==.',
Ss='Ssushii:BAAALgAECgEJAQAAAA==.',
St='Staffkiller:BAAALgAECgYJCwAAAA==.Stellån:BAAALgADCgYJBwAAAA==.Stigmata:BAAALgAECgEJAgAAAA==.Stixlightmix:BAABLgAFFH8FAAMcAAMJ5hHOLACPAAAcAAIJORjOLACPAAAoAAEJQAUGXgAxAAAAAA==.Stixmixdk:BAABLgAFFH8FAAIXAAMJIhaSMAB3AAAXAAMJIhaSMAB3AAAAAA==.Stixmixwarr:BAAALgAFFAYJAQAAAA==.Straz:BAAALgADCgQJBAAAAA==.Strongman:BAAALgAECgYJBgAAAA==.Stx:BAAALgAECgYJDgAAAA==.',
Su='Subsdk:BAACLgAFFH8VAAIWAAYJpQ/OPwBxAQAWAAYJpQ/OPwBxAQAuAAQKfyQAAxYACAmUHRpHAOoBABYACAmUHRpHAOoBACYAAQnfH1cvAFwAAAAA.Sunwalkers:BAAALgAECgUJBgAAAA==.Supfurry:BAAALgAFFAIJAgAAAA==.',
Sw='Swam:BAAALgADCgkJCQAAAA==.Sweetl:BAAALgAECgQJBAAAAA==.',
Sy='Syreenaa:BAAALgAECgEJAQAAAA==.Systeni:BAAALgADCgkJCwAAAA==.',
['Sø']='Søøssø:BAAALgAECgYJCAAAAA==.',
Ta='Tacaagua:BAAALgAECgIJAgAAAA==.Taha:BAAALgAECgYJDgAAAA==.Taillys:BAAALgADCgMJBAAAAA==.Tainy:BAAALgAECgEJAQAAAA==.Takemywand:BAAALgADCgUJBQABLgAECgcJFAATAFIQAA==.Takenaka:BAAALgADCgMJAwAAAA==.Tarez:BAAALgAECgkJDgAAAA==.Tarfonir:BAAALgAECgYJCQAAAA==.Tashian:BAAALgADCgIJAgAAAA==.Tavalira:BAAALgADCgYJBgAAAA==.Taylör:BAAALgADCgEJAQAAAA==.',
Te='Tealen:BAAALgAECgEJAQAAAA==.Ted:BAAALgAECgcJDAAAAA==.Teiseken:BAAALgAECgcJBwAAAA==.Tempesfúria:BAAALgADCgIJAgAAAA==.Tenébria:BAAALgAECgcJBwAAAA==.Teratsemknk:BAAALgAECgUJBQAAAA==.',
Th='Tharnforge:BAAALgAECgEJAQAAAA==.Thejokker:BAACLgAFFH8HAAIPAAMJ7gD0SQBvAAAPAAMJ7gD0SQBvAAAuAAQKfxcAAg8ABwl6BLxmAMAAAA8ABwl6BLxmAMAAAAAA.Thelaststorm:BAAALgAECgkJAwAAAA==.Themooster:BAABLgAFFH8GAAMGAAMJuAweEgBlAAADAAIJYg0GjgCOAAAGAAIJNA0eEgBlAAAAAA==.Thepickles:BAAALgAECgUJCQAAAA==.Thepunk:BAAALgAECgQJEQAAAA==.Thesindorei:BAAALgAECgEJAgAAAA==.Thintor:BAAALgADCgEJAQAAAA==.Thormento:BAABLgAECn8VAAIIAAcJkBERWQBOAQAIAAcJkBERWQBOAQAAAA==.Thraell:BAAALgAECgEJAQAAAA==.',
Ti='Tigerblood:BAAALgADCgUJBQAAAA==.Tipooreeii:BAAALgADCgEJAQAAAA==.Titanicos:BAAALgAFFAIJAgAAAA==.',
Tj='Tjhunter:BAABLgAECn8fAAIBAAgJnQpeSQCNAQABAAgJnQpeSQCNAQAAAA==.',
To='Tobbiy:BAABLgAFFH8IAAIXAAMJWxigIQDaAAAXAAMJWxigIQDaAAAAAA==.Toddyb:BAAALgAECggJCwAAAA==.Tonytornado:BAAALgAECgEJAgAAAA==.',
Tr='Tranh:BAAALgADCgkJFQAAAA==.Traxer:BAAALgADCgQJBAAAAA==.Tripäsecä:BAAALgAECgcJDgAAAA==.Troladora:BAABLgAECn8VAAIHAAYJqA7AwQAEAQAHAAYJqA7AwQAEAQAAAA==.Trévor:BAAALgAECgEJAQAAAA==.',
Ts='Tsreis:BAAALgADCgEJAQAAAA==.',
Tw='Twoheavy:BAAALgADCgkJCQABLgAECgYJCQASAAAAAA==.',
Ty='Tyrandrisa:BAAALgADCgIJAQAAAA==.',
['Tá']='Tátu:BAAALgADCgMJAwAAAA==.',
Uh='Uhdyr:BAAALgAECgQJBQAAAA==.',
Um='Ummetrodefio:BAAALgADCgEJAQAAAA==.',
Ur='Urthemiel:BAAALgAECgEJAQABLgAECgYJBwASAAAAAA==.',
Ut='Uthred:BAACLgAFFH8GAAMWAAMJnwFb0gCMAAAWAAMJnwFb0gCMAAAmAAIJUgAYKQA8AAAuAAQKfzEABBYACQkdByOXADcBABYACQnOBCOXADcBACYABgmqBG8MAOsAABcAAwmuCcFJAGQAAAAA.',
Va='Vaelryn:BAAALgAECgYJCQABLgAECgYJBwASAAAAAA==.Valdemmon:BAAALgAECgQJBwAAAA==.Valororo:BAABLgAECn8bAAIHAAkJtAYRjABcAQAHAAkJtAYRjABcAQAAAA==.Vandlesh:BAABLgAECn8WAAIHAAcJBw3kpAAwAQAHAAcJBw3kpAAwAQAAAA==.Vardha:BAAALgADCgQJBAAAAA==.Varka:BAAALgADCgYJGQAAAA==.',
Ve='Velkharun:BAAALgAECgQJDAABLgAFFAIJBgABAPQNAA==.Velkryon:BAAALgAECgUJBgAAAA==.Venatrin:BAAALgADCgkJCQAAAA==.Vess:BAAALgAECgQJBAAAAA==.Vexxv:BAABLgAECn8UAAIWAAUJshqnigBrAQAWAAUJshqnigBrAQAAAA==.Vexxz:BAAALgAECgYJBwAAAA==.',
Vi='Viquue:BAAALgADCgYJBgAAAA==.Vivisoft:BAAALgADCgMJAwAAAA==.',
Vl='Vlannytic:BAAALgAECgMJAwAAAA==.',
Vo='Voidrb:BAAALgADCgcJBwABLgAECggJGAALAAIcAA==.Vovogamer:BAAALgAECgQJBgAAAA==.',
['Vò']='Vòxs:BAACLgAFFH8SAAMLAAQJohRAIgDiAAALAAMJhxhAIgDiAAAPAAIJug/1QQCSAAAuAAQKf0sAAwsACAk8JLYDAMQCAAsABwnDJLYDAMQCAA8ABglHHoQuAPcBAAAA.',
Wa='Walkery:BAAALgADCgIJAgAAAA==.Wattari:BAABLgAECn8bAAIRAAYJDgTcOgCEAAARAAYJDgTcOgCEAAAAAA==.Watters:BAAALgAECgUJCwABLgAFFAMJCQAhAJQMAA==.',
Wh='Whiteep:BAAALgADCgYJCAAAAA==.Whiteseraph:BAAALgADCgEJAQAAAA==.Whynchester:BAAALgADCgEJAQAAAA==.',
Wi='Wiilami:BAAALgADCgMJAwAAAA==.Windsailor:BAAALgAECgUJBQAAAA==.Wiserys:BAACLgAFFH8GAAINAAMJKA5/gQC9AAANAAMJKA5/gQC9AAAuAAQKfzAAAw0ACAkSI/MVAJ8CAA0ACAk0IvMVAJ8CAA4ABgn+HNYKAK0BAAAA.',
Wm='Wmarcão:BAABLgAECn8YAAMMAAcJbw0tFgDwAAAMAAYJlA8tFgDwAAANAAcJYAVxwADLAAAAAA==.',
Wo='Wolfiez:BAAALgAECgUJDAAAAA==.Wolfnwar:BAAALgAECgQJEAAAAA==.Wopz:BAAALgADCgcJBwAAAA==.Worq:BAAALgADCgYJBgAAAA==.',
Wq='Wqz:BAABLgAECn8XAAIBAAcJxxmTNgDUAQABAAcJxxmTNgDUAQAAAA==.',
Wu='Wunamuno:BAAALgAECgEJAQAAAA==.',
Xa='Xallatath:BAAALgADCgUJBQAAAA==.Xamela:BAAALgADCgMJAwAAAA==.Xamãna:BAAALgAECgQJCQAAAA==.',
Xb='Xbleidexx:BAAALgADCgYJBgAAAA==.',
Xe='Xevron:BAAALgAECgQJBAAAAA==.Xexnetw:BAAALgAECgQJDQAAAA==.Xexnew:BAACLgAFFH8FAAIXAAIJLg5ENABiAAAXAAIJLg5ENABiAAAuAAQKfxkAAxcACQn0GoUPABECABcACQn0GoUPABECABYAAQlpB8eIAScAAAAA.',
Xf='Xframengox:BAAALgADCgEJAQAAAA==.',
Xi='Xidevill:BAABLgAECn8XAAIkAAYJuQVNQwCkAAAkAAYJuQVNQwCkAAAAAA==.Xinthorak:BAAALgADCgEJAgAAAA==.Xinzhou:BAAALgADCgQJCAAAAA==.Xiseth:BAAALgAECgIJAgAAAA==.Xixíca:BAAALgADCgUJBgAAAA==.',
Xm='Xmari:BAAALgAECgYJBwAAAA==.',
Xn='Xnyx:BAAALgAECgEJAQAAAA==.',
Xs='Xseth:BAAALgAECgYJBwAAAA==.',
Xu='Xulaman:BAAALgAECgcJDgAAAA==.Xungodz:BAAALgADCgQJBAAAAA==.Xunxu:BAABLgAECn8ZAAMDAAYJdhMQhwBsAQADAAYJdhMQhwBsAQAnAAEJJgM2ngArAAAAAA==.',
Xx='Xxcantsidex:BAAALgAECgEJAQAAAA==.',
Xy='Xynrath:BAAALgADCgMJAwAAAA==.',
['Xÿ']='Xÿon:BAAALgAECgEJAQAAAA==.',
Ya='Yamëte:BAAALgAECgQJBQAAAA==.Yangyung:BAAALgAECgEJAQAAAA==.Yannadcg:BAACLgAFFH8GAAIaAAQJ9gJwIQCoAAAaAAQJ9gJwIQCoAAAuAAQKfy4AAhoACQmRC4IpAHcBABoACQmRC4IpAHcBAAAA.',
Yo='Yorickundyer:BAAALgAECgIJAwAAAA==.Youdie:BAABLgAECn8YAAIgAAgJhRLwKgCEAQAgAAgJhRLwKgCEAQAAAA==.',
Yu='Yulthuan:BAAALgADCgMJAwAAAA==.',
Yv='Yvernus:BAAALgAECgQJBgAAAA==.',
Yz='Yziepala:BAAALgAECgMJBAAAAA==.',
Za='Zaaraki:BAABLgAECn84AAMWAAkJ4Rq5MwAtAgAWAAkJpBm5MwAtAgAXAAcJoRaPIQBDAQAAAA==.Zarolho:BAABLgAECn8VAAIJAAYJSA6EUAAFAQAJAAYJSA6EUAAFAQAAAA==.',
Ze='Zenitsua:BAAALgAECgYJCQAAAA==.Zenzeluk:BAAALgAECgMJAwAAAA==.Zephiir:BAABLgAECn8ZAAIDAAYJExUgnQA5AQADAAYJExUgnQA5AQAAAA==.Zeroxyz:BAAALgADCgYJBgABLgAECgYJGAAbAJUPAA==.Zeryen:BAAALgAECgEJAQAAAA==.',
Zh='Zhunka:BAAALgADCgEJAwAAAA==.',
Zi='Ziikiipala:BAAALgAECgEJAQAAAA==.',
Zo='Zornak:BAAALgADCgUJBQAAAA==.',
Zz='Zzx:BAAALgADCgcJBwAAAA==.',
['Zé']='Zécasete:BAAALgADCgUJBwAAAA==.',
['Ál']='Álucard:BAABLgAECn8XAAIWAAgJtgz1cgB7AQAWAAgJtgz1cgB7AQAAAA==.',
['Ån']='Åntares:BAAALgADCgMJAwAAAA==.',
['Éy']='Éyga:BAAALgAECgEJBAAAAA==.',
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
